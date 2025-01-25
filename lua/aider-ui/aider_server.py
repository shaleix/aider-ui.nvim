# -*- coding: utf-8 -*-
import json
import logging
import os
import socket
import sys
import threading
import traceback
from pathlib import Path

from aider.coders import Coder
from aider.main import SwitchCoder
from aider.main import main as aider_main

# Add current directory to Python path
sys.path.append(str(Path(__file__).parent))

from backend_server.coder_server_handler import CoderServerHandler
from backend_server.listener import setup_listeners
from backend_server.store import store

logging.basicConfig(
    filename="/tmp/nvim_aider.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
log = logging.getLogger(__name__)
# litellm start slow, https://github.com/BerriAI/litellm/issues/2677
os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"

END_OF_MESSAGE = b"\r\n\r\n"

setup_listeners()


def coder_run_one_wrapper(run_one):

    def wrapper_run_one(self, user_message: str, *args, **kwargs):
        # Get the current stack information
        stack = traceback.extract_stack()
        run_one_count = sum(1 for frame in stack if frame.name.endswith("run_one"))

        # If run_one is called more than once, skip the following actions
        if run_one_count > 1:
            return run_one(self, user_message, *args, **kwargs)

        try:
            output_idx = CoderServerHandler.handle_cmd_start(user_message)
            if user_message == "fix-diagnostics":
                CoderServerHandler.handle_fix_diagnostic()
            else:
                run_one(self, user_message, *args, **kwargs)
            CoderServerHandler.handle_cmd_complete(user_message, output_idx=output_idx)
        except SwitchCoder as switch:
            if switch.kwargs:
                switch.kwargs["switch_coder"] = True
            else:
                switch.kwargs = {"switch_coder": True}
            CoderServerHandler.handle_cmd_complete(user_message, output_idx=output_idx)
            raise switch

    return wrapper_run_one


Coder.run_one = coder_run_one_wrapper(Coder.run_one)


def coder_create_wrapper(create_method):

    def wrapper_create(*args, **kwargs):
        if "switch_coder" in kwargs:
            switch_coder = True
            kwargs.pop("switch_coder")
        else:
            switch_coder = False
        new_coder = create_method(*args, **kwargs)
        if switch_coder:
            store.coder = new_coder
        elif store.coder is None:
            # first init coder
            CoderServerHandler.handle_process_start()
            store.coder = new_coder
            CoderServerHandler.handle_cache_files()
        return new_coder

    return wrapper_create


Coder.create = coder_create_wrapper(Coder.create)


class SocketServer:

    def __init__(self, host):
        self.host = host
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.bind((self.host, 0))
        self.port = self.server_socket.getsockname()[1]
        print(f"Aider server port: {self.port}")
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

                try:
                    json_data = json.loads(message.decode())
                    res, keep_alive = handler.handle_message(json_data)
                    log.info("Received JSON: %s", json_data)
                    response = json.dumps(res).encode()
                    log.info("response: %s", response.decode())
                    client_socket.sendall(response + END_OF_MESSAGE)
                    if not keep_alive:
                        break
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


if __name__ == "__main__":
    server = SocketServer("127.0.0.1")
    server_thread = threading.Thread(target=server.start)
    server_thread.daemon = True
    server_thread.start()
    log.info("server started on port %d", server.port)

    aider_main()
