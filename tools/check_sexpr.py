#!/usr/bin/env python3
"""check_sexpr.py -- LISP 结构门禁: setq 参数奇偶 / if 元素数 / foreach 元素数。

背景(坑 #75, 2026-09-19): dt_start v3.13 的 dt:st-filemenu-lines then 分支
`(setq` 少一个右括号, else 分支被吞进 setq 的参数表 —— 括号总数仍平衡,
check_lisp(括号计数)/check_defun_depth/_audit 全查不出; defun 体不被求值所以
新机(2024)加载无恙; 只有真 AutoCAD 2007 在 (load) 时报「语法错误」。
本门禁按 S 表达式语义检查常见调用形态, 专防"平衡但残缺"的暗雷。

检查项:
  setq    参数个数必须为偶数(符号/值成对)
  if      参数个数必须为 2 或 3(测试/则/否则)
  foreach 参数个数必须 >= 3(变量/表/体...)

用法: python tools/check_sexpr.py            (审计 scripts\\ 全部 6 个 .lsp)
      python tools/check_sexpr.py <file.lsp> (只查指定文件)
退出码: 0=全过, 1=发现问题, 2=用法错误。
字符串/注释按字节级读取器语义剥离(GBK 安全: 引号括号不在双字节第二字节范围)。
"""
import sys, os, glob

QUOTE_NOTE = "'"


class Str:
    """字符串字面量叶子节点(内容不参与结构检查)"""
    __slots__ = ()


def tokenize(data):
    """字节级读取器: 返回 token 列表 ('(' / ')' / ('atom', bytes) / ('str', bytes))"""
    toks = []
    i, n = 0, len(data)
    instr = esc = com = False
    while i < n:
        b = data[i]
        if instr:
            if esc:
                esc = False
            elif b == 0x5C:
                esc = True
            elif b == 0x22:
                instr = False
            i += 1
            continue
        if com:
            if b == 0x0A:
                com = False
            i += 1
            continue
        if b == 0x22:
            # 字符串字面量: 整体作为一个 token
            j = i + 1
            while j < n:
                if data[j] == 0x5C:
                    j += 2
                    continue
                if data[j] == 0x22:
                    break
                j += 1
            toks.append(("str", data[i:j + 1]))
            i = j + 1
            continue
        if b == 0x3B:
            com = True
            i += 1
            continue
        if b == 0x28:
            toks.append(("(", None))
            i += 1
            continue
        if b == 0x29:
            toks.append((")", None))
            i += 1
            continue
        if b in (0x20, 0x0A, 0x0D, 0x09):
            i += 1
            continue
        # 原子(含 ' 引用前缀与 . 点号)
        j = i
        while j < n and data[j] not in (0x20, 0x0A, 0x0D, 0x09, 0x28, 0x29,
                                        0x22, 0x3B):
            j += 1
        toks.append(("atom", data[i:j]))
        i = j
    return toks


def parse(toks):
    """token 列表 -> 顶层节点列表; 节点 = bytes(原子) | Str | list(节点)
    引用糖 'X 与 X 视为同一参数(粘合), 避免 (setq x '(1 2 3)) 误报奇数"""
    pos = [0]

    def rd():
        kind, val = toks[pos[0]]
        pos[0] += 1
        if kind == "str":
            return Str()
        if kind == "atom":
            if val == b"'":
                if pos[0] < len(toks):
                    return rd()      # 引用糖: 粘合后一个元素
                return val
            return val
        if kind == "(":
            lst = []
            while pos[0] < len(toks):
                k, _ = toks[pos[0]]
                if k == ")":
                    pos[0] += 1
                    return lst
                lst.append(rd())
            raise ValueError("unbalanced ( at top level")
        raise ValueError("unexpected ) at top level")

    out = []
    while pos[0] < len(toks):
        out.append(rd())
    return out


def head_of(node):
    if isinstance(node, list) and node and isinstance(node[0], bytes):
        return node[0].decode("latin1").lower()
    return None


def walk(node, path, issues):
    if isinstance(node, (bytes, Str)):
        return
    hs = head_of(node)
    args = len(node) - 1
    if hs == "setq" and args % 2 != 0:
        issues.append((path, "setq 参数个数为奇数(%d) —— 缺右括号或符号/值不配对" % args))
    if hs == "if" and args not in (2, 3):
        issues.append((path, "if 参数个数为 %d (应为 2 或 3)" % args))
    if hs == "foreach" and args < 3:
        issues.append((path, "foreach 参数个数为 %d (<3)" % args))
    for i, ch in enumerate(node):
        walk(ch, path + "/" + str(i), issues)


def check_file(path, issues):
    data = open(path, "rb").read()
    if data[:3] == b"\xef\xbb\xbf":
        data = data[3:]          # 剥 UTF-8 BOM(2021+ 原版), 避免顶层垃圾原子
    try:
        forms = parse(tokenize(data))
    except ValueError as e:
        issues.append((path, "顶层解析失败: %s" % e))
        return
    for k, f in enumerate(forms, 1):
        walk(f, "%s[form %d]" % (os.path.basename(path), k), issues)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    scripts = os.path.normpath(os.path.join(here, "..", "scripts"))
    if len(sys.argv) > 1:
        files = sys.argv[1:]
    else:
        files = sorted(glob.glob(os.path.join(scripts, "*.lsp")))
    if not files:
        print("check_sexpr: 没有找到待检文件")
        return 2
    issues = []
    for p in files:
        check_file(p, issues)
    if issues:
        for path, msg in issues:
            print("[FAIL] %s : %s" % (path, msg))
        print("结果: %d 个结构问题" % len(issues))
        return 1
    print("check_sexpr: %d 个文件全部通过(setq 奇偶/if 元素数/foreach 元素数)" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
