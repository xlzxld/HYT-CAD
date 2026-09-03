# -*- coding: utf-8 -*-
"""跨文件同名函数冲突分析: 提取每个 lsp 的 (函数名 -> 规范化函数体哈希),
找出在多个文件中定义且函数体不一致的名字(后加载覆盖先加载的隐患)。"""
import re, hashlib

FILES = ['offset_runner.lsp', 'slot_runner.lsp', 'jrt_runner.lsp', 'size_runner.lsp', 'dt_start.lsp']  # 2026-08-31 目录分类: 与本工具同移 tools\, 分析对象在 ..\scripts

def extract(path):
    text = open(path, encoding='utf-8-sig').read()
    lines = text.split('\n')
    defs = {}
    i = 0
    while i < len(lines):
        m = re.match(r'^\(defun\s+([A-Za-z0-9:*_-]+)\s*\(([^)]*)\)', lines[i])
        if m:
            name = m.group(1)
            sig = ' '.join(m.group(2).split())
            # 函数体: 从 defun 行起到下一个顶层 defun/结尾, 只保留代码行
            body = [lines[i]]
            j = i + 1
            while j < len(lines) and not lines[j].startswith('(defun'):
                body.append(lines[j])
                j += 1
            codebody = '\n'.join(re.sub(r';.*$', '', l).rstrip() for l in body)
            codebody = re.sub(r'\s+', ' ', codebody).strip()
            defs[name] = (sig, hashlib.md5(codebody.encode()).hexdigest()[:8])
            i = j
        else:
            i += 1
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
