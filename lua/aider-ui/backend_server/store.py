# -*- coding: utf-8 -*-
from typing import List, TypedDict, Optional
from queue import Queue
from aider.coders import Coder
import logging


log = logging.getLogger(__name__)


# {
#      code = "unused-local",
#      col = 8,
#      lnum = 17,
#      end_col = 17,
#      end_lnum = 17,
#      message = "Unused local `telescope`.",
#      namespace = 59,
#      severity = 4,
#      source = "Lua Diagnostics.",
#      user_data = {
#        lsp = {
#          code = "unused-local"
#        }
#      }
#    } }
class Diagnostic(TypedDict):
    code: str
    lnum: int
    col: int
    end_lnum: int
    message: str


class FileDiagnostics(TypedDict):
    fname: str
    diagnostics: List[Diagnostic]


class Store:
    def __init__(self):
        self.chat_history: List[str] = []
        self.output_history: List[str] = []
        self.diagnostics: List[FileDiagnostics] = []
        self.coder: Optional[Coder] = None
        self.running = False
        self.notification_queue = Queue(9999)
        self.waiting_add_files: List[str] = []
        self.waiting_read_files: List[str] = []
        self.waiting_drop_files: List[str] = []
        self.change_files = {
            "before_tmp_dir": "",
            "files": [], 
        }

    def add_notify_message(self, data):
        log.info('add_notify_message: %s', data)
        self.notification_queue.put(data)


store = Store()
