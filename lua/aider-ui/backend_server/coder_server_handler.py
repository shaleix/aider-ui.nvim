# -*- coding: utf-8 -*-
import logging
import os
import tempfile
import time
from pathlib import Path
from typing import List, Optional, TypedDict

from aider.commands import Commands
from aider.linter import tree_context
from aider.llm import litellm
from backend_server.consts import NotifyType
from backend_server.store import FileDiagnostics, store
from backend_server.utils import copy_files_to_dir

log = logging.getLogger(__name__)


class ErrorData(TypedDict):
    code: int
    message: str


class CoderServerHandler:

    def handle_message(self, message):
        """
        handle rpc server message
        """
        method, params = message.get("method"), message.get("params")

        handler_method = getattr(self, f"method_{method}", None)
        if not handler_method:
            return {
                "jsonrpc": "2.0",
                "error": {"code": 32601, "message": "Invalid method"},
                "result": None,
                "id": message.get("id"),
            }

        res, err = handler_method(params)
        data = {
            "jsonrpc": "2.0",
            "result": res,
            "id": message.get("id"),
        }
        if err:
            data["error"] = err
        keep_alive = method in ("notify")
        return data, keep_alive

    def method_list_files(self, *args, **kwargs):
        """
        get add and read files
        """
        if not store.coder:
            return {"added": [], "readonly": []}, None
        inchat_files = store.coder.get_inchat_relative_files()
        read_only_files = []
        for abs_file_path in store.coder.abs_read_only_fnames or []:
            rel_file_path = store.coder.get_rel_fname(abs_file_path)
            read_only_files.append(rel_file_path)

        return {
            "added": inchat_files,
            "readonly": read_only_files,
        }, None

    def method_add_files(self, params: List[str]):
        """
        /add params
        """
        params = [params] if isinstance(params, str) else params
        if store.coder is None or store.running:
            for item in params:
                if item in store.waiting_read_files:
                    store.waiting_read_files.remove(item)
                if item in store.waiting_drop_files:
                    store.waiting_drop_files.remove(item)
                store.waiting_add_files.append(item)
            return "waiting", None

        args = " ".join(params)
        store.coder.commands.cmd_add(args)
        return "add file success", None

    def method_read_files(self, params: List[str]):
        """
        /read-only params
        """
        params = [params] if isinstance(params, str) else params
        if store.coder is None or store.running:
            for item in params:
                if item in store.waiting_add_files:
                    store.waiting_add_files.remove(item)
                if item in store.waiting_drop_files:
                    store.waiting_drop_files.remove(item)
                store.waiting_read_files.append(item)
            return "waiting", None

        store.coder.commands.cmd_read_only(" ".join(params))
        return "read file success", None

    def method_drop(self, params: List[str]):
        """
        aider /drop
        """
        params = [params] if isinstance(params, str) else params
        if store.coder is None or store.running:
            for item in params:
                if item in store.waiting_add_files:
                    store.waiting_add_files.remove(item)
                if item in store.waiting_read_files:
                    store.waiting_read_files.remove(item)
                store.waiting_drop_files.append(item)
            return "waiting", None

        args = " ".join(params)
        store.coder.commands.cmd_drop(args)
        return "drop file success", None

    def method_clear(self, params):
        """
        aider /clear
        """
        if not store.coder:
            return None, None
        if store.running:
            return None, {"code": 32603, "message": "Server is running"}
        store.coder.commands.cmd_clear(params)
        return "clear success", None

    def method_reset(self, params):
        """
        aider /reset
        """
        if not store.coder:
            return None, None
        if store.running:
            return None, {"code": 32603, "message": "Server is running"}
        store.coder.commands.cmd_reset(params)
        return "reset success", None

    def method_load(self, params: str):
        """
        aider /load, params is file path
        """
        if not store.coder:
            return None, {"code": 32603, "message": "CoderNotInit"}
        if store.running:
            return None, {"code": 32603, "message": "Server is running"}
        file_path = params
        store.coder.commands.cmd_load(file_path)
        return "load session success", None

    def method_exchange_files(self, params):
        """
        Exchange files
        """
        if not store.coder:
            return None, {"code": 32603, "message": "CoderNotInit"}
        if store.running:
            return None, {"code": 32603, "message": "Server is running"}
        added_files = list(store.coder.get_inchat_relative_files())
        cmd = Commands(store.coder.io, store.coder)
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
        if not store.coder:
            return [], {"code": 32603, "message": "CoderNotInit"}
        

        history = store.coder.io.get_input_history()
        chat_histories = []
        multi_lines = []
        for row in history:
            if row.endswith("}"):
                multi_lines = [row.rstrip("}")] if row.rstrip("}") else []
                continue
            row = row.lstrip("{")
            if row.startswith(("/code ", "/ask ", "/architect ")):
                prefix, content = row.split(" ", 1)
                multi_lines.insert(0, content)
                chat_histories.append(
                    {
                        "cmd": prefix,
                        "content": "\n".join(multi_lines),
                    }
                )
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
        if not store.coder:
            return [], None

        lines = store.coder.get_announcements()
        return lines, None

    def method_notify(self, params):
        """
        Get next notification from queue
        """
        return store.notification_queue.get(block=True), None  # 改为从store获取

    def method_fix_diagnostic(self, params: List[FileDiagnostics]):
        if not store.coder:
            raise
        if not params:
            return "", None
        store.diagnostics = params
        return "", None

    @classmethod
    def handle_fix_diagnostic(cls):
        if not store.coder:
            raise
        if not store.diagnostics:
            return
        lint_coder = store.coder.clone(
            # Clear the chat history, fnames
            cur_messages=[],
            done_messages=[],
            fnames=None,
        )
        linter = store.coder.linter
        store.running = False
        cls.handle_process_start()
        for item in store.diagnostics:
            fname = item["fname"]
            rel_fname = linter.get_rel_fname(fname)
            lines = set()
            try:
                file_content = Path(fname).read_text(
                    encoding=linter.encoding, errors="replace"
                )
            except OSError as err:
                print(f"Unable to read {fname}: {err}")
            res = "# Fix any errors below, if possible.\n\n"
            for diagnostic in item["diagnostics"]:
                code, message = diagnostic.get("code"), diagnostic.get("message")
                lnum, col = diagnostic.get("lnum"), diagnostic.get("col")
                end_lnum = diagnostic.get("end_lnum")
                res += f"{fname}:{lnum}:{col}: {code}: {message}\n"
                res += "\n"
                lines.update(range(lnum, end_lnum + 1))
            res += tree_context(rel_fname, file_content, lines)

            store.coder.io.tool_output(res)
            lint_coder.add_rel_fname(fname)
            lint_coder.run(res)
            lint_coder.abs_fnames = set()
        store.running = False
        cls.handle_cmd_complete("fix-diagnostic")

    @classmethod
    def handle_process_start(cls):
        store.add_notify_message(
            {"type": NotifyType.AIDER_START, "message": "aider started"}
        )

    @classmethod
    def handle_cmd_start(cls, message: Optional[str] = None) -> int:
        """
        Before chat
        """
        log.info("handle cmd: %s", message)
        store.running = True
        if message:
            store.add_notify_message(
                {
                    "type": NotifyType.CMD_START,
                    "message": f"{cls._get_cmd_from_message(message)} start",
                }
            )
        # Create a temporary directory and record it in change_files, and clear file_paths
        temp_dir = tempfile.mkdtemp()
        store.change_files["before_tmp_dir"] = temp_dir
        store.change_files["files"].clear()
        return len(store.output_history)

    @classmethod
    def handle_cmd_complete(
        cls, message: Optional[str] = None, output_idx: Optional[int] = None
    ):
        """
        handle chat process complete
        """
        log.info(
            "handle_cmd_complete: %s, output_idx: %s",
            message,
            output_idx,
            stack_info=True,
        )
        assert store.coder is not None
        after_tmp_dir = tempfile.mkdtemp()
        after_tmp_map = copy_files_to_dir(
            [file["path"] for file in store.change_files["files"]],
            after_tmp_dir,
        )
        modified_info = [
            {
                "path": file["path"],
                "abs_path": store.coder.abs_root_path(file["path"]),
                "before_path": file.get("before_path"),
                "after_path": after_tmp_map.get(file["path"]),
            }
            for file in store.change_files["files"]
        ]
        cls.running = False
        res_msg = ""
        if message and output_idx is not None:
            message = message.strip()
            command = cls._get_cmd_from_message(message)
            if command == "/commit":
                for msg in store.output_history[output_idx:]:
                    if msg.startswith("Commit "):
                        res_msg = msg
                        break
            elif command in ("/ask", "/architect", "/code", "/lint"):
                res_msg = f"{command} complete"
            else:
                res_msg = "complete"
        store.add_notify_message(
            {
                "type": NotifyType.CMD_COMPLETE,
                "modified_info": modified_info,
                "message": res_msg,
            }
        )
        cls.handle_cache_files()

    @classmethod
    def handle_cache_files(cls):
        if store.waiting_add_files:
            cls().method_add_files(store.waiting_add_files)
            store.waiting_add_files.clear()
        if store.waiting_read_files:
            cls().method_read_files(store.waiting_read_files)
            store.waiting_read_files.clear()
        if store.waiting_drop_files:
            cls().method_drop(store.waiting_drop_files)
            store.waiting_drop_files.clear()

    @classmethod
    def _get_cmd_from_message(cls, message: str) -> str:
        """
        Extract the command from the message.
        """
        if message:
            return message.split(" ", 1)[0] if " " in message else message
        return ""

    @classmethod
    def method_chat_history(cls, params):
        return store.chat_history, None

    def method_exit(self, params):
        """
        退出服务器
        """
        store.add_notify_message(
            {"type": NotifyType.AIDER_EXIT, "message": "aider exited"}
        )
        time.sleep(0.1)
        os._exit(0)

    def method_save(self, params: str):
        """
        Save session command
        """
        if not store.coder:
            return None, {"code": 32603, "message": "CoderNotInit"}
        if self.__class__.running:
            return None, {"code": 32603, "message": "Server is running"}

        file_path = params
        dir_path = os.path.dirname(file_path)

        if dir_path and not os.path.exists(dir_path):
            os.makedirs(dir_path, exist_ok=True)

        store.coder.commands.cmd_save(file_path)
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
                fq_model = model if model.startswith(provider) else provider + model
            else:
                fq_model = model
            chat_models.add(fq_model)
        return sorted(chat_models), None

