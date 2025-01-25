# -*- coding: utf-8 -*-
from typing import List, TypedDict


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


store = Store()
