# -*- coding: utf-8 -*-
"""跨文件同名函数冲突分析: 提取每个 lsp 的 (函数名 -> 规范化函数体哈希),
找出在多个文件中定义且函数体不一致的名字(后加载覆盖先加载的隐患)。"""
import re, hashlib, os

FILES = ['flb_runner.lsp', 'cx_runner.lsp', 'jrt_runner.lsp', 'wx_runner.lsp', 'dt_start.lsp']  # 2026-08-31 目录分类: 与本工具同移 tools\, 分析对象在 ..\scripts
HERE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))

def strip_comments_strings(text):
    """去注释 + 掏空字符串内容(保留引号占位) —— 供括号深度扫描用,
    字符串内的括号/分号不再干扰配对(旧版逐行 r';.*$' 会误删字符串内
    分号、且字符串内括号会破坏深度计数, 两处同为启发式盲区)。"""
    out = []
    i, n = 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == '\\' and i + 1 < n:
                i += 2
                continue
            if c == '"':
                in_str = False
                out.append(c)
            i += 1
            continue
        if c == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def extract(path):
    if not os.path.exists(path) and os.path.exists(os.path.join(HERE, path)):
        path = os.path.join(HERE, path)
    with open(path, encoding='utf-8-sig') as f:
        text = f.read()
    code = strip_comments_strings(text)
    # v2: 括号深度扫描取顶层 sexp —— 旧版逐行找 '^\\(defun' 并以行首
    #     '(defun' 切函数体, 签名跨行的 defun 会漏提取、嵌套 defun
    #    (坑#73 类)会被误切, 同名冲突随之漏报
    defs = {}
    depth = 0
    start = None
    for i, c in enumerate(code):
        if c == '(':
            if depth == 0:
                start = i
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0 and start is not None:
                blk = code[start:i + 1]
                m = re.match(r'\(defun\s+([A-Za-z0-9:*_-]+)\s*\(([^)]*)\)',
                             blk, re.S)
                if m:
                    sig = ' '.join(m.group(2).split())
                    body = re.sub(r'\s+', ' ', blk).strip()
                    defs[m.group(1)] = (
                        sig, hashlib.md5(body.encode()).hexdigest()[:8])
                start = None
    return defs

all_defs = {f: extract(f) for f in FILES}
names = {}
for f, d in all_defs.items():
    for n in d:
        names.setdefault(n, []).append(f)

print('=== 跨文件同名定义 ===')
conflict = 0
for n in sorted(names):
    fl = names[n]
    if len(fl) < 2:
        continue
    sigs = {all_defs[f][n][0] for f in fl}
    hashs = {all_defs[f][n][1] for f in fl}
    tag = '!!!体不同' if len(hashs) > 1 else ('签名不同' if len(sigs) > 1 else '一致')
    if tag != '一致':
        conflict += 1
        print('%-24s %s  [%s]' % (n, tag, ' '.join(fl)))
        for f in fl:
            print('    %-24s sig=(%s) h=%s' % (f, all_defs[f][n][0], all_defs[f][n][1]))
print('冲突函数总数:', conflict)
same = [n for n in names if len(names[n]) >= 2
        and len({all_defs[f][n][1] for f in names[n]}) == 1]
print('逐字一致的同名函数:', len(same), '个(安全)')
