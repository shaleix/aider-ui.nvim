# -*- coding: utf-8 -*-
import logging

from aider.io import InputOutput

from backend_server.coder_server_handler import CoderServerHandler
from backend_server.store import store

log = logging.getLogger(__name__)


def listener(func, before_call, after_call=None):

    def wrapper_func(self, *args, **kwargs):
        before_call(*args, **kwargs)
        ret = func(self, *args, **kwargs)
        if after_call:
            after_call(ret, *args, **kwargs)
        return ret

    return wrapper_func


def _on_tool_output(*messages, **kwargs):
    for item in messages:
        if isinstance(item, str):
            store.output_history.append(item)


def on_append_chat_history(text, linebreak=False, blockquote=False, strip=True):
    if blockquote:
        if strip:
            text = text.strip()
        text = "> " + text
    if linebreak:
        if strip:
            text = text.rstrip()
        text = text + "  "
    for line in text.split("\n"):
        store.chat_history.append(line)


def setup_listeners():
    InputOutput.tool_output = listener(InputOutput.tool_output, _on_tool_output)
    InputOutput.confirm_ask = listener(
        InputOutput.confirm_ask,
        CoderServerHandler.before_confirm,
        CoderServerHandler.after_confirm,
    )
    InputOutput.write_text = listener(
        InputOutput.write_text, CoderServerHandler.before_write_text
    )
    InputOutput.append_chat_history = listener(
        InputOutput.append_chat_history, on_append_chat_history
    )
