# -*- coding: utf-8 -*-
import json
import logging
import os
import re
import shutil
import socket
import sys
import tempfile
import threading
from typing import Dict, List, Optional, TypedDict

from aider.coders import Coder
from aider.commands import Commands
from aider.io import InputOutput
from aider.llm import litellm
from aider.main import SwitchCoder
from aider.main import main as aider_main

logging.basicConfig(filename='/tmp/nvim_aider.log',
                    level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)
# litellm start slow, https://github.com/BerriAI/litellm/issues/2677
os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"

END_OF_MESSAGE = b"\r\n\r\n"
CHUNK_END = b"\t\n\t\n"


class ErrorData(TypedDict):
    code: int
    message: str


class CoderServerHandler:
    coder: Optional[Coder] = None
    output_history = []
    running = False
    send_chunk = None
    waiting_add_files = []
    waiting_read_files = []
    waiting_drop_files = []
    exit_event = threading.Event()
    change_files = {
        "before_tmp_dir": "",
        "files": []  # [{'path': path, 'before_path': path_tmp_map.get(path) }]
    }

    CHUNK_TYPE_AIDER_START = "aider_start"
    CHUNK_TYPE_NOTIFY = "notify"
    CHUNK_TYPE_CMD_START = "cmd_start"
    CHUNK_TYPE_CMD_COMPLETE = "cmd_complete"
    CHUNK_TYPE_CONFIRM_ASK = "confirm_ask"

    def handle_message(self, message, send_chunk):
        """
        handle rpc server message
        """
        method, params = message.get("method"), message.get("params")

        handler_method = getattr(self, f"method_{method}", None)
        if not handler_method:
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": 32601,
                    "message": "Invalid method"
                },
                "result": None,
                "id": message.get("id"),
            }

        if method == 'process_status':
            CoderServerHandler.send_chunk = send_chunk

        res, err = handler_method(params)
        data = {
            "jsonrpc": "2.0",
            "result": res,
            "id": message.get("id"),
        }
        if err:
            data["error"] = err
        return data

    def method_list_files(self, *args, **kwargs):
        """
        get add and read files
        """
        if not self.coder:
            return {'added': [], 'readonly': []}, None
        inchat_files = self.coder.get_inchat_relative_files()
        read_only_files = []
        for abs_file_path in self.coder.abs_read_only_fnames or []:
            rel_file_path = self.coder.get_rel_fname(abs_file_path)
            read_only_files.append(rel_file_path)

        return {
            'added': inchat_files,
            'readonly': read_only_files,
        }, None

    def method_add_files(self, params: List[str]):
        """
        /add params
        """
        params = [params] if isinstance(params, str) else params
        if self.coder is None or self.running:
            for item in params:
                if item in self.waiting_read_files:
                    self.waiting_read_files.remove(item)
                if item in self.waiting_drop_files:
                    self.waiting_drop_files.remove(item)
                self.waiting_add_files.append(item)
            return "waiting", None

        args = " ".join(params)
        self.coder.commands.cmd_add(args)
        return "add file success", None

    def method_read_files(self, params: List[str]):
        """
        /read-only params
        """
        params = [params] if isinstance(params, str) else params
        if self.coder is None or self.running:
            for item in params:
                if item in self.waiting_add_files:
                    self.waiting_add_files.remove(item)
                if item in self.waiting_drop_files:
                    self.waiting_drop_files.remove(item)
                self.waiting_read_files.append(item)
            return "waiting", None

        self.coder.commands.cmd_read_only(" ".join(params))
        return "read file success", None

    def method_drop(self, params: List[str]):
        """
        aider /drop
        """
        params = [params] if isinstance(params, str) else params
        if self.coder is None or self.running:
            for item in params:
                if item in self.waiting_add_files:
                    self.waiting_add_files.remove(item)
                if item in self.waiting_read_files:
                    self.waiting_read_files.remove(item)
                self.waiting_drop_files.append(item)
            return "waiting", None

        args = " ".join(params)
        self.coder.commands.cmd_drop(args)
        return "drop file success", None

    def method_clear(self, params):
        """
        aider /clear
        """
        if not self.coder:
            return None, None
        if self.running:
            return None, {"code": 32603, "message": "Server is running"}
        self.coder.commands.cmd_clear(params)
        return "clear success", None

    def method_reset(self, params):
        """
        aider /reset
        """
        if not self.coder:
            return None, None
        if self.running:
            return None, {"code": 32603, "message": "Server is running"}
        self.coder.commands.cmd_reset(params)
        return "reset success", None

    def method_load(self, params: str):
        """
        aider /load, params is file path
        """
        if not self.coder:
            return None, {"code": 32603, "message": "CoderNotInit"}
        if self.running:
            return None, {"code": 32603, "message": "Server is running"}
        file_path = params
        self.coder.commands.cmd_load(file_path)
        return "load session success", None

    def method_exchange_files(self, params):
        """
        Exchange files
        """
        if not self.coder:
            return None, {"code": 32603, "message": "CoderNotInit"}
        if self.running:
            return None, {"code": 32603, "message": "Server is running"}
        added_files = list(self.coder.get_inchat_relative_files())
        cmd = Commands(self.coder.io, self.coder)
        args = " ".join(params)
        cmd.cmd_drop(args)
        for file_path in params:
            cmd.cmd_drop(file_path)
            if file_path in added_files:
                cmd.cmd_read_only(file_path)
            else:
                cmd.cmd_add(file_path)
        return "exchange file success", None

    def method_get_history(self, params):
        """
        get history command
        """
        if not self.coder:
            return [], {"code": 32603, "message": "CoderNotInit"}

        history = self.coder.io.get_input_history()
        chat_histories = []
        multi_lines = []
        for row in history:
            if row.endswith('}'):
                multi_lines = [row.rstrip('}')] if row.rstrip('}') else []
                continue
            row = row.lstrip('{')
            if row.startswith(('/code ', '/ask ', '/architect ')):
                prefix, content = row.split(' ', 1)
                multi_lines.insert(0, content)
                chat_histories.append({
                    'cmd': prefix,
                    'content': '\n'.join(multi_lines),
                })
                multi_lines = []
            else:
                multi_lines.insert(0, row)
            if len(chat_histories) > 50:
                break
        return chat_histories, None

    def method_get_announcements(self, params):
        """
        Get announcements and settings content
        """
        if not self.coder:
            return [], None

        lines = self.coder.get_announcements()
        return lines, None

    def method_process_status(self, params) -> (dict, Optional[ErrorData]):
        if self.coder is not None and self.__class__.send_chunk:
            self.__class__.send_chunk({
                "type": self.CHUNK_TYPE_AIDER_START,
                "message": "aider started"
            })
        self.exit_event.wait()
        return "exit", None

    @classmethod
    def handle_process_start(cls):
        if cls.send_chunk is not None:
            cls.send_chunk({
                "type": cls.CHUNK_TYPE_AIDER_START,
                "message": "aider started"
            })

    @classmethod
    def handle_cmd_start(cls, message: str = None) -> int:
        """
        before chat
        """
        cls.running = True
        if cls.send_chunk is not None and message:
            cls.send_chunk({
                "type":
                cls.CHUNK_TYPE_CMD_START,
                "message":
                f"{cls._get_cmd_from_message(message)} start"
            })
        # 创建临时目录并记录在 change_files 中，同时清空 file_paths
        temp_dir = tempfile.mkdtemp()
        cls.change_files["before_tmp_dir"] = temp_dir
        cls.change_files["files"].clear()
        return len(cls.output_history)

    @classmethod
    def handle_cmd_complete(cls, message: str = None, output_idx: int = None):
        """
        handle chat process complete
        """
        after_tmp_dir = tempfile.mkdtemp()
        after_tmp_map = copy_files_to_dir(
            [file['path'] for file in cls.change_files['files']],
            after_tmp_dir,
        )
        modified_info = [{
            'path': file['path'],
            'before_path': file['before_path'],
            'after_path': after_tmp_map[file['path']]
        } for file in cls.change_files['files']]
        cls.running = False
        res_msg = ''
        if message and output_idx is not None:
            message = message.strip()
            command = cls._get_cmd_from_message(message)
            if command == '/commit':
                for msg in cls.output_history[output_idx:]:
                    if msg.startswith("Commit "):
                        res_msg = msg
                        break
            elif command in ('/ask', '/architect', '/code', '/lint'):
                res_msg = f"{command} complete"
        if cls.send_chunk is not None:
            cls.send_chunk({
                "type": cls.CHUNK_TYPE_CMD_COMPLETE,
                "modified_info": modified_info,
                "message": res_msg
            })
        cls.handle_cache_files()

    @classmethod
    def handle_cache_files(cls):
        if cls.waiting_add_files:
            cls().method_add_files(cls.waiting_add_files)
            cls.waiting_add_files.clear()
        if cls.waiting_read_files:
            cls().method_read_files(cls.waiting_read_files)
            cls.waiting_read_files.clear()
        if cls.waiting_drop_files:
            cls().method_drop(cls.waiting_drop_files)
            cls.waiting_drop_files.clear()

    @classmethod
    def _get_cmd_from_message(cls, message: str) -> str:
        """
        Extract the command from the message.
        """
        if message:
            return message.split(' ', 1)[0] if ' ' in message else message
        return ""

    def method_exit(self, params):
        """
        退出服务器
        """
        os._exit(0)

    def method_save(self, params: str):
        """
        Save session command
        """
        if not self.coder:
            return None, {"code": 32603, "message": "CoderNotInit"}
        if self.__class__.running:
            return None, {"code": 32603, "message": "Server is running"}
        file_path = params
        self.coder.commands.cmd_save(file_path)
        return "save session success", None

    def method_list_models(self, parmas):
        """
        list chat models
        """
        chat_models = set()
        for model, attrs in litellm.model_cost.items():
            model = model.lower()
            if attrs.get("mode") != "chat":
                continue
            if "litellm_provider" in attrs:
                provider = attrs.get("litellm_provider").lower() + "/"
                fq_model = model if model.startswith(
                    provider) else provider + model
            else:
                fq_model = model
            chat_models.add(fq_model)
        return sorted(chat_models), None

    @classmethod
    def on_confirm(cls, question, *args, **kwargs):
        if cls.running and cls.send_chunk and not (cls.coder
                                                   and cls.coder.io.yes):
            cls.send_chunk({
                'type': cls.CHUNK_TYPE_CONFIRM_ASK,
                'prompt': question
            })

    @classmethod
    def before_write_text(cls, filename: str):
        if filename not in [
                file['path'] for file in cls.change_files['files']
        ]:
            # Use copy_files_to_dir to copy the file to a temporary directory
            temp_dir = cls.change_files["before_tmp_dir"]
            file_map = copy_files_to_dir([filename], temp_dir)
            # Add file information to change_files
            cls.change_files['files'].append({
                'path': filename,
                'before_path': file_map[filename]
            })


def listener(func, before_call):

    def wrapper_func(*args, **kwargs):
        before_call(*args, **kwargs)
        return func(*args, **kwargs)

    return wrapper_func


def _on_tool_output(self, *messages, **kwargs):
    for item in messages:
        if isinstance(item, str):
            CoderServerHandler.output_history.append(item)


def _on_write_text(self, filename, content, *args, **kwargs):
    CoderServerHandler.before_write_text(filename)


def _on_confirm_ask(self, question, *args, **kwargs):
    CoderServerHandler.on_confirm(question)


InputOutput.tool_output = listener(InputOutput.tool_output, _on_tool_output)
InputOutput.confirm_ask = listener(InputOutput.confirm_ask, _on_confirm_ask)
InputOutput.write_text = listener(InputOutput.write_text, _on_write_text)


class SocketServer:

    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)

    # sourcery skip: avoid-too-many-statements
    def handle_client(self, client_socket: socket.socket, client_address):
        """
        handle rpc request
        """
        handler = CoderServerHandler()
        buffer = b""
        while True:
            data = client_socket.recv(1024)
            if not data:
                break
            log.info("get_data: %s", data.strip())
            buffer += data
            if END_OF_MESSAGE in buffer:
                message, buffer = buffer.split(END_OF_MESSAGE, 1)

                def send_chunk(chunk_res):
                    log.info("Sending chunk: %s", chunk_res)
                    chunk_res = json.dumps(chunk_res).encode()
                    client_socket.sendall(chunk_res + CHUNK_END)

                try:
                    json_data = json.loads(message.decode())
                    res = handler.handle_message(json_data, send_chunk)
                    log.info("Received JSON: %s", json_data)
                    response = json.dumps(res).encode()
                    log.info("response: %s", response.decode())
                    client_socket.sendall(response + END_OF_MESSAGE)
                except json.JSONDecodeError as e:
                    print(f"JSON Decode Error: {e}")
                    client_socket.sendall(b"Invalid JSON" + END_OF_MESSAGE)
        client_socket.close()

    def start(self):
        try:
            while True:
                client_socket, client_address = self.server_socket.accept()
                client_thread = threading.Thread(
                    target=self.handle_client,
                    args=(client_socket, client_address),
                    daemon=True,
                )
                client_thread.start()
        except KeyboardInterrupt:
            log.info("Server shutting down.")
        finally:
            self.server_socket.close()


def copy_files_to_dir(file_paths, dir_path) -> Dict[str, str]:
    """
    Return: 
        {source_path: copy_tmp_path}
    """
    file_map = {}

    for file_path in file_paths:
        file_name = str(file_path).replace(os.path.sep, "@@").replace(" ", "_")
        dest_path = os.path.join(dir_path, file_name)
        shutil.copy2(file_path, dest_path)
        file_map[file_path] = dest_path
    return file_map


def aider_cmd(coder):
    while True:
        try:
            user_message = coder.get_input()
            output_idx = CoderServerHandler.handle_cmd_start(user_message)
            coder.run_one(user_message, preproc=True)
            CoderServerHandler.handle_cmd_complete(user_message,
                                                   output_idx=output_idx)
            coder.show_undo_hint()
        except KeyboardInterrupt:
            coder.keyboard_interrupt()
        except SwitchCoder as switch:
            CoderServerHandler.handle_cmd_complete(user_message,
                                                   output_idx=output_idx)
            kwargs = dict(io=coder.io, from_coder=coder)
            kwargs.update(switch.kwargs)
            if "show_announcements" in kwargs:
                del kwargs["show_announcements"]

            coder = Coder.create(**kwargs)
            CoderServerHandler.coder = coder

            if switch.kwargs.get("show_announcements") is not False:
                coder.show_announcements()
        except EOFError:
            return


if __name__ == "__main__":
    sys.argv[0] = re.sub(r'(-script\.pyw|\.exe)?$', '', sys.argv[0])
    port = int(sys.argv.pop(1))
    log.info("server started on port %d", port)
    server = SocketServer('127.0.0.1', port)
    server_thread = threading.Thread(target=server.start)
    server_thread.daemon = True
    server_thread.start()

    coder = aider_main(return_coder=True)
    CoderServerHandler.coder = coder
    CoderServerHandler.handle_process_start()
    CoderServerHandler.handle_cache_files()
    coder.show_announcements()
    aider_cmd(coder)
