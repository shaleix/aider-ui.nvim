# -*- coding: utf-8 -*-
import logging

from aider.io import InputOutput

from backend_server.utils import copy_files_to_dir
from backend_server.store import store
from backend_server.consts import NotifyType

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


def before_confirm(
    question,
    *args,
    default="y",
    subject=None,
    explicit_yes_required=False,
    group=None,
    allow_never=False,
):
    store.last_confirm_output_idx = len(store.output_history)
    if not store.running or (store.coder and store.coder.io.yes):
        log.debug(
            "skip confirm, for running: %s, store.coder: %s, store.coder.io.yes: %s",
            store.running,
            store.coder,
            store.coder and store.coder and store.coder.io and store.coder.io.yes,
        )
        return

    options = [
        {"label": "(Y)es", "value": "y"},
        {"label": "(N)o", "value": "n"},
    ]
    if group:
        if not explicit_yes_required:
            options.append({"label": "(A)ll", "value": "a"})
            options.append({"label": "(S)kip", "value": "s"})
    if allow_never:
        options.append({"label": "(D)on't ask again", "value": "d"})
    confirm_info = {
        "default": default,
        "options": options,
    }
    if subject and "\n" in subject:
        confirm_info["subject"] = subject.splitlines()
    store.add_notify_message(
        {
            "type": NotifyType.CONFIRM_ASK,
            "last_confirm_output_idx": store.last_confirm_output_idx,
            "confirm_info": dict(
                question=question,
                **confirm_info,
            ),
        }
    )


def after_confirm(ret, *args, **kwargs):
    if store.running and not (store.coder and store.coder.io.yes):
        store.add_notify_message(
            {
                "type": NotifyType.CONFIRM_COMPLETE,
            }
        )


def before_write_text(filename: str, *args, **kwargs):
    if filename not in [file["path"] for file in store.change_files["files"]]:
        # 使用copy_files_to_dir将文件复制到临时目录
        temp_dir = store.change_files["before_tmp_dir"]
        file_map = copy_files_to_dir([filename], temp_dir)
        # 将文件信息添加到change_files
        store.change_files["files"].append(
            {"path": filename, "before_path": file_map.get(filename)}
        )

def setup_listeners():
    InputOutput.tool_output = listener(InputOutput.tool_output, _on_tool_output)
    InputOutput.confirm_ask = listener(
        InputOutput.confirm_ask,
        before_confirm,
        after_confirm,
    )
    InputOutput.write_text = listener(
        InputOutput.write_text, 
        before_write_text
    )
    InputOutput.append_chat_history = listener(
        InputOutput.append_chat_history, on_append_chat_history
    )
