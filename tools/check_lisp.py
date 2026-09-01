# -*- coding: utf-8 -*-
"""offset_runner.lsp 结构校验工具(AGENTS.md 第11节流程的强化版)。
用法: python check_lisp.py [文件名]
检查: BOM / 括号 stack 平衡(处理字符串与 \" 转义) / defun 计数 /
      command 全部为 UNDO 分组 / TRIM 残留 / 指定函数存在性 / 死名残留。"""
import re
import sys

P = sys.argv[1] if len(sys.argv) > 1 else 'offset_runner.lsp'
raw = open(P, 'rb').read()

ok = True
def fail(msg):
    global ok
    ok = False
    print('[FAIL]', msg)

# 1) BOM
print('BOM:', 'OK' if raw[:3] == b'\xef\xbb\xbf' else 'MISSING')
if raw[:3] != b'\xef\xbb\xbf':
    fail('UTF-8 BOM 丢失')

src = raw.decode('utf-8-sig', 'replace')
lines = src.splitlines()
print('行数:', len(lines))

# 2) 括号平衡: 逐字符 stack 跟踪(注释/字符串感知, 字符串内处理 \" 转义)
bal = 0
min_bal = 0
bad_line = None
in_str = False
in_com = False
escaped = False
ln = 1
for ch in src:
    if ch == '\n':
        ln += 1
        in_com = False
        escaped = False
        continue
    if in_com:
        continue
    if in_str:
        if escaped:
            escaped = False
        elif ch == '\\':
            escaped = True
        elif ch == '"':
            in_str = False
        continue
    if ch == ';':
        in_com = True
    elif ch == '"':
        in_str = True
    elif ch == '(':
        bal += 1
    elif ch == ')':
        bal -= 1
        if bal < 0 and bad_line is None:
            bad_line = ln
        min_bal = min(min_bal, bal)
print('括号: balance=%d min=%d %s' % (bal, min_bal, 'OK' if (bal == 0 and min_bal >= 0) else ''))
if bal != 0 or min_bal < 0:
    fail('括号不平衡 (首个负深度行: %s)' % bad_line)
if in_str:
    fail('文件结尾仍在字符串内(引号未闭合)')

# 3) 代码视图(去注释)做 token 检查
code = '\n'.join(re.sub(r';.*$', '', l) for l in lines)

defuns = re.findall(r'\(defun\s+([^\s(]+)', code)
print('defun 总数:', len(defuns), '(含 c:OFF 内局部 *error*)')

cmds = re.findall(r'\(command\s+([^\n)]*)', code)
non_undo = [c for c in cmds if 'UNDO' not in c.upper()]
print('command 调用:', len(cmds), '处, 非 UNDO:', len(non_undo))
if non_undo:
    fail('存在非 UNDO 的 command: %r' % non_undo[:3])

if '_.TRIM' in code:
    fail('存在 _.TRIM 残留')
else:
    print('TRIM 残留: 0')

# 4) 关键函数/命令存在性(按文件区分: slot 脚本 / 主脚本)
COMMON = ['dt:ms', 'dt:layer-vlas', 'dt:excluded-p',
          'dt:curve-p', 'dt:curves-only',
          'dt:cut-params', 'dt:seg-mid', 'dt:rebuild-seg', 'dt:cut-curve',
          'dt:poly-rebuild', 'dt:trim-curve', 'dt:cross-points',
          'dt:fillet-pair', 'dt:collect-heads', 'dt:pair-heads',
          'dt:offset-enames', 'dt:get-num', 'dt:end-free',
          'dt:set-endpoint', 'dt:bbox-overlap-p']
PLATE = COMMON + ['c:OFF', 'c:PARAM', 'dt:param-dialog', 'dt:param-apply',
                  'dt:param-reset', 'dt:dcl-lines', 'dt:write-dcl', 'dt:find-dcl',
                  'dt:trim-all', 'dt:fillet-all', 'dt:close-channels',
                  'dt:drill-holes', 'dt:chamfer-close', 'dt:fillet-close',
                  'dt:offset-layer', 'dt:offset-inward', 'dt:extend-ends',
                  'dt:purge-layer', 'dt:ensure-layer', 'dt:fillet-close-one',
                  'dt:merge-layer', 'dt:nozzle-circles']
# slot v10.3: fillet-pair 改名 dt:slot-fillet-pair(缺省值绑定本脚本参数,
# 坑 #46 同名不同体改名隔离); 新增 dt:rect-bbox(cross-points 包围盒预过滤)
SLOT = [n for n in COMMON if n != 'dt:fillet-pair'] + \
       ['dt:slot-fillet-pair', 'dt:rect-bbox'] + \
       ['c:SLOT', 'c:SLOTPARAM', 'dt:slot-param-dialog',
        'dt:slot-param-apply', 'dt:slot-param-reset',
        'dt:slot-dcl-lines', 'dt:slot-write-dcl', 'dt:slot-find-dcl',
        'dt:break-curve', 'dt:collect-ends', 'dt:slot-trim',
        'dt:slot-fillet-all', 'dt:slot-extend-fixed',
        'dt:slot-first-cross', 'dt:slot-join', 'dt:near-src-fwd',
        'dt:slot-close', 'dt:slot-cxk', 'dt:slot-process']
# JRT(加热条)脚本: 与 COMMON 的差异 —— 对话框函数用 dt:jrt-* 改名隔离,
# 不含封口链(dt:end-free); cut-curve/trim-curve/fillet-pair 因 slot 版
# 签名/默认值不同也改名隔离(详见 AGENTS.md 双脚本架构说明)
JRT_COMMON = [n for n in COMMON
              if n not in ('dt:write-dcl', 'dt:get-num', 'dt:end-free',
                           'dt:cut-curve', 'dt:trim-curve', 'dt:fillet-pair')]
JRT = JRT_COMMON + ['c:JRT', 'c:JRTPARAM', 'dt:jrt-param-dialog',
                'dt:jrt-param-apply', 'dt:jrt-param-reset',
                'dt:jrt-dcl-lines', 'dt:jrt-find-dcl', 'dt:jrt-write-dcl',
                'dt:jrt-get-num', 'dt:jrt-decide', 'dt:jrt-match-rz',
                'dt:jrt-free-ends', 'dt:jrt-head-walls', 'dt:jrt-cap-circle',
                'dt:jrt-cap-line', 'dt:jrt-trim', 'dt:jrt-fillet',
                'dt:jrt-zero-clean', 'dt:jrt-build', 'dt:jrt-snapshot',
                'dt:jrt-diff', 'dt:jrt-touch-p', 'dt:jrt-curve-dist',
                'dt:jrt-cut-curve', 'dt:jrt-trim-curve', 'dt:jrt-fillet-pair',
                'dt:jrt-template-row', 'dt:jrt-stage',
                'dt:jrt-template-dialog', 'dt:jrt-template-dcl-lines',
                'dt:jrt-apply-template', 'dt:jrt-tpl-keys',
                'dt:jrt2-process', 'dt:jrt2-cands', 'dt:jrt2-min-dist',
                'dt:jrt2-pick-near', 'dt:jrt2-rec-of', 'dt:jrt2-layer',
                'dt:jrt2-free-ends',
                'dt:jrt2-close', 'dt:jrt2-group', 'dt:jrt2-grp-touch',
                'dt:jrt2-fillet2', 'dt:jrt2-neck', 'dt:jrt2-junction',
                'dt:rect-bbox']
import os
base = os.path.basename(P).lower()
# dt_start 引导器(独立小工具: 无几何库, 只查自身三命令与辅助函数)
DTSTART = ['c:DTINSTALL', 'c:DTRELOAD', 'c:DTUNINSTALL', 'c:DTDBG',
           'dt:st-locate', 'dt:st-vernum', 'dt:st-digits', 'dt:st-pick',
           'dt:st-join', 'dt:st-boot', 'dt:st-2bs', 'dt:st-acadoc-path',
           'dt:st-write-hook', 'dt:st-remove-hook',
           'dt:st-path-list', 'dt:st-split',
           'dt:st-add-support', 'dt:st-del-support',
           'dt:st-trusted-add', 'dt:st-trusted-del']
if 'dt_start' in base:
    need = DTSTART
elif 'slot' in base:
    need = SLOT
elif 'jrt' in base:
    need = JRT
else:
    need = PLATE
missing = [n for n in need if '(defun %s' % n not in code]
print('关键函数缺失:', missing if missing else '无')
if missing:
    fail('关键函数缺失: %s' % missing)

# 5) 死名残留(代码+注释全文都不应再出现; slot-extend 需排除 slot-extend-fixed)
dead_pats = [r'dt:nearest-center', r'dt:parallel-p', r'dt:extend-inters',
             r'dt:slot-break-all', r'dt:slot-extend(?!-fixed)',
             r'出线槽通道', r'出线槽源线暂存(?!.*purge)']
leftover = []
for p in dead_pats:
    for i, l in enumerate(lines):
        if re.search(p, l):
            leftover.append((p, i + 1, l.strip()[:50]))
if leftover:
    for p, n, t in leftover[:10]:
        print('[死名?]', p, 'L%d: %s' % (n, t))
else:
    print('死名/旧图层名残留: 无')

# 5b) 代码区非 ASCII 字符(字符串/注释之外) —— AutoLISP 读到会报"语法错误"
BS = chr(92)
bad_char = []
in_str = False; esc = False
for ln, line in enumerate(lines, 1):
    in_com = False
    for col, ch in enumerate(line, 1):
        if in_com: break
        if in_str:
            if esc: esc = False
            elif ch == BS: esc = True
            elif ch == '"': in_str = False
            continue
        if ch == ';': in_com = True
        elif ch == '"': in_str = True
        elif ord(ch) > 127:
            bad_char.append('L%d:%d %r' % (ln, col, ch))
print('代码区非ASCII:', bad_char[:5] if bad_char else '无')
if bad_char:
    fail('代码区存在非 ASCII 字符(全角符号等), AutoLISP 将报语法错误: %s' % bad_char[:3])

# 5c) if 参数个数检查(AutoLISP if 只允许"测试/则[/否则]"2~3 段;
#     4 段及以上运行时报"语法错误" —— dt_start v1.0 事故)
def tokenize(text):
    toks = []; i = 0; n = len(text); in_s = False; esc2 = False; buf = ''
    while i < n:
        ch = text[i]
        if in_s:
            buf += ch
            if esc2: esc2 = False
            elif ch == BS: esc2 = True
            elif ch == '"':
                in_s = False; toks.append(('S', buf)); buf = ''
            i += 1; continue
        if ch == ';':
            while i < n and text[i] != '\n': i += 1
            continue
        if ch == '"':
            in_s = True; buf = '"'; i += 1; continue
        if ch in '()':
            toks.append(('P', ch)); i += 1; continue
        if ch.isspace():
            i += 1; continue
        j = i
        while j < n and not text[j].isspace() and text[j] not in '();"':
            j += 1
        toks.append(('A', text[i:j])); i = j
    return toks

def build_tree(toks):
    stack = [[]]
    for kind, v in toks:
        if kind == 'P':
            if v == '(':
                nxt = []; stack[-1].append(nxt); stack.append(nxt)
            else:
                if len(stack) == 1: return None
                stack.pop()
        else:
            stack[-1].append(v if kind == 'A' else ('STR', v))
    return stack[0] if len(stack) == 1 else None

def walk_if(node, out):
    if not isinstance(node, list) or not node:
        return
    head = node[0]
    if isinstance(head, str) and head.upper() == 'IF':
        argc = len(node) - 1
        if argc not in (2, 3):
            out.append('if 有 %d 段参数(只允许2~3): %s' % (argc, str(node[:5])[:60]))
    for x in node:
        walk_if(x, out)

tree = build_tree(tokenize(src))
bad_if = []
if tree is None:
    fail('sexp 解析失败(括号/引号结构异常)')
else:
    walk_if(tree, bad_if)
print('if 参数超限:', bad_if if bad_if else '无')
if bad_if:
    fail('存在参数超限的 if: %s' % bad_if[:3])

print('结果:', 'ALL OK' if ok else '存在问题')
sys.exit(0 if ok else 1)
