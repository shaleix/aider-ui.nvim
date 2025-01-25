# -*- coding: utf-8 -*-
from typing import List


class Store:
    def __init__(self):
        self.chat_history: List[str] = []
        self.output_history: List[str] = []


store = Store()
