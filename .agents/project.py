# -*- coding: utf-8 -*-
"""本项目自己的门禁命令（tsc.py verify 会按顺序执行这里登记的 4 条命令）。

取值来源：AGENTS.md §2（check-config 校验同源）。
"""
__all__ = ["FMT_CHECK_CMD", "LINT_CMD", "TEST_CMD", "BUILD_CMD"]

FMT_CHECK_CMD = None
LINT_CMD = "python tools/check_lisp.py scripts/cx_runner.lsp && python tools/check_lisp.py scripts/demo_recorder.lsp && python tools/check_lisp.py scripts/dt_start.lsp && python tools/check_lisp.py scripts/flb_runner.lsp && python tools/check_lisp.py scripts/jrt_runner.lsp && python tools/check_lisp.py scripts/wx_runner.lsp && python tools/check_sysvars.py && python tools/check_defun_depth.py"
TEST_CMD = "python tools/test_direction.py && python tools/check_audit_fixes.py"
BUILD_CMD = "python tools/make_ansi.py"
