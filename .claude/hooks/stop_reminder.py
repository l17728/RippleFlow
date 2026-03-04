#!/usr/bin/env python3
"""Stop hook: 会话结束时提示文档一致性检查。"""
import sys
import json

try:
    inp = json.load(sys.stdin)
    # 避免 stop hook 触发自身循环
    if inp.get("stop_hook_active"):
        sys.exit(0)
except Exception:
    pass

print("请检查所有文档的一致性，刷新文档中需要重构的设计和需要刷新补充的内容")
