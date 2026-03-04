#!/usr/bin/env python3
"""PostToolUse hook: 编辑 .py 文件时检查语法，编辑 .yaml/.yml 时验证结构。"""
import sys
import os
import json

try:
    inp = json.load(sys.stdin)
    fp = (
        inp.get("tool_input", {}).get("file_path")
        or inp.get("tool_input", {}).get("path")
        or ""
    )
except Exception:
    sys.exit(0)

if not fp or not os.path.exists(fp):
    sys.exit(0)

name = os.path.basename(fp)

if fp.endswith(".py"):
    import py_compile
    try:
        py_compile.compile(fp, doraise=True)
        print(f"[hook] OK  {name}")
    except py_compile.PyCompileError as e:
        print(f"[hook] Python syntax error in {name}:\n{e}", file=sys.stderr)
        sys.exit(1)

elif fp.endswith((".yaml", ".yml")):
    try:
        import yaml
        with open(fp, "r", encoding="utf-8") as f:
            yaml.safe_load(f)
        print(f"[hook] OK  {name}")
    except ImportError:
        pass  # yaml not installed, skip
    except yaml.YAMLError as e:
        print(f"[hook] YAML error in {name}:\n{e}", file=sys.stderr)
        sys.exit(1)
