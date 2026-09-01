# -*- coding: utf-8 -*-
"""check_sysvars.py —— 系统变量读取的"低版本兼容"静态门禁(坑 #65 回归防护)。

背景(2026-08-31, dt_start v2.9): 低版本 AutoCAD(2007~2015)执行 DTINSTALL 报
    ; 错误: 参数类型错误: stringp nil
根因是老版本上 getvar 读取"本版本不存在的系统变量"时**静默返回 nil**(并非抛
异常), 之前的写法只 catch 了抛异常那半边; nil 流进 strcat / strlen 就炸成
stringp nil。修复手法是统一 dt:st-gets / dt:st-hasvar 兜底, 本工具防止再犯。

用法: python check_sysvars.py [目录]   (默认 ..\\scripts)
检查项:
  A) 版本相关变量(下表)必须经由 dt:st-gets / dt:st-hasvar 读取,
     或在取到值后立刻做 (null ...) 判定 —— 否则视为 nil 泄漏风险。
  B) 任何 getvar 调用结果不得直接作为 strcat / strlen / substr /
     vl-filename-directory 的实参(同一表达式内), 必须先进 dt:st-gets。
  C) dt:st-path-list / dt:st-split 的实参不得是未判空的 getvar 结果。

只做静态正则+括号配对分析, 不执行 LISP。退出码 0=通过 1=有问题。
"""
import os
import re
import sys

# 版本相关 / 历史上出过 nil 的系统变量: 老版本可能根本没有, getvar 会返回 nil
GATED = {
    'TRUSTEDPATHS',        # 2016+ 才有
    'SECURELOAD',          # 2016+ 才有
    'ROAMABLEROOTPREFIX',  # 2006+ 才有(国产 CAD / 更早版本没有)
    'LOCALROOTPREFIX',     # 2006+ 才有
    'DWGPREFIX',           # 无图纸打开时部分版本返回 nil
    'MYDOCUMENTSPREFIX',   # 部分精简环境没有
    'TRUSTEDDOMAINS',
    'ACADLSPASDOC',
}
# 全版本都有的"常青"变量, 无需兜底
EVERGREEN = {'ACADVER', 'DWGNAME', 'DWGTITLED', 'CLAYER', 'CMDECHO', 'LUNITS',
             'OSMODE', 'BLIPMODE', 'FILEDIA', 'ATTDIA', 'DIMSCALE', 'FILLETRAD',
             'TEXTSIZE', 'PICKBOX', 'APERTURE', 'ORTHOMODE', 'SNAPMODE', 'UCSICON'}

# 会拿字符串"开刀"的函数: 传 nil 就报 stringp / bad argument type
STRING_EATERS = ('strcat', 'strlen', 'substr', 'vl-filename-directory',
                 'vl-string-search', 'vl-string-trim', 'strcase', 'findfile',
                 'dt:st-path-list', 'dt:st-split', 'dt:st-2bs')

GETVAR_RE = re.compile(r"""\(getvar\s+            # (getvar "
                           ["']([A-Za-z0-9_]+)["']""", re.X)
GETVAR_APPLY_RE = re.compile(r"""'getvar\s*\)?\s*\(list\s+["']([A-Za-z0-9_]+)["']""", re.X)
DEFUN_RE = re.compile(r'^\(defun\s+([A-Za-z0-9:*_+-]+)', re.I)


def strip_comments(text):
    out, i, n = [], 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == '\\' and i + 1 < n:
                out.append(text[i:i + 2])
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
    return ''.join(out)


def split_top_level(text):
    """按顶层括号配对切成若干 (defun ...) 代码块, 返回 [(函数名, 代码)]"""
    blocks, depth, start, i, n = [], 0, 0, 0, len(text)
    while i < n:
        c = text[i]
        if c == '(':
            if depth == 0:
                start = i
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                blk = text[start:i + 1]
                m = DEFUN_RE.match(blk.lstrip())
                if m:
                    blocks.append((m.group(1), blk))
        i += 1
    return blocks


def check_file(path):
    src = strip_comments(open(path, encoding='utf-8-sig').read())
    problems = []
    for name, blk in split_top_level(src):
        safe_wrapper = name in ('dt:st-gets', 'dt:st-hasvar')
        for m in list(GETVAR_RE.finditer(blk)) + list(GETVAR_APPLY_RE.finditer(blk)):
            var = m.group(1).upper()
            guarded = '(null ' in blk                       # 同函数内做过判空
            if safe_wrapper:
                continue
            # B) 先查最硬的一条: getvar 结果直接进了吞字符串的函数
            #    (取该调用所在的表达式, 向外扩到最近的配对左括号)
            ctx = expr_starting_at(blk, m.start())
            if ctx and re.match(r'\(\s*(%s)\b' % '|'.join(STRING_EATERS), ctx):
                problems.append('%s: (getvar "%s") 直接作为 (%s 的实参, '
                                '请改用 (dt:st-gets "%s")'
                                % (name, var, ctx[1:].split(' ')[0].split(')')[0], var))
                continue
            # A) 版本相关变量未走安全通道(老版本返回 nil)
            if var in GATED and not guarded:
                problems.append('%s: 变量 %s 为版本相关, 未走 dt:st-gets/dt:st-hasvar '
                                '也未判 null(老版本返回 nil 会炸 stringp)'
                                % (name, var))
                continue
            if var in EVERGREEN:
                continue
    return problems


def expr_starting_at(text, pos):
    """从 pos(某个 '(' )**向外**找包裹它的那一层表达式, 返回该片段。
    例如 (strcat (getvar "X") "y") 里传入 getvar 的 '(' , 返回整个 strcat 表达式。"""
    depth, i = 0, pos - 1
    while i >= 0:
        c = text[i]
        if c == ')':
            depth += 1
        elif c == '(':
            if depth == 0:
                j, d2 = i, 0
                while j < len(text):
                    if text[j] == '(':
                        d2 += 1
                    elif text[j] == ')':
                        d2 -= 1
                        if d2 == 0:
                            return text[i:j + 1]
                    j += 1
                return None
            depth -= 1
        i -= 1
    return None


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(here, '..', 'scripts'))
    files = sorted(f for f in os.listdir(d) if f.lower().endswith('.lsp'))
    total = 0
    for fn in files:
        ps = check_file(os.path.join(d, fn))
        print('%-22s %s' % (fn, 'OK' if not ps else '%d 处风险' % len(ps)))
        for p in ps:
            print('    [RISK]', p)
        total += len(ps)
    print('结果:', 'ALL OK(无 nil 泄漏风险)' if total == 0 else '存在 %d 处风险' % total)
    sys.exit(0 if total == 0 else 1)


if __name__ == '__main__':
    main()
