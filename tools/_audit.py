# -*- coding: utf-8 -*-
"""
三脚本 + 引导器 静态审计(第二版)
  1) 同名不同体函数(多脚本同加载互相覆盖, 坑 #46)
  2) 从未被引用的函数(死代码) —— 统计"符号出现次数", 覆盖引号引用与字符串内宏
  3) 函数体里 setq/foreach 绑定了但未声明的符号(全局变量泄漏)
  4) 声明了但从未使用的参数/局部变量
  5) 调用了但既未定义也非内置的函数
"""
import re, io, os
from collections import defaultdict

FILES = ["offset_runner.lsp", "slot_runner.lsp", "jrt_runner.lsp", "dt_start.lsp"]
HERE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))  # 审计对象在 scripts\ (2026-08-31 目录分类)

BUILTINS = set("""
if while repeat foreach cond and or not null setq defun lambda quote function progn
list cons car cdr caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
cadddr nth length append reverse member assoc subst vl-remove vl-remove-if vl-some vl-every
mapcar apply last abs min max fix float itoa atoi atof distof rtos angtos substr strlen
strcat strcase vl-string-search vl-string-trim vl-prin1-to-string read-line write-line
open close princ print prin1 terpri getvar setvar command load vl-load-com
vla-add vla-item vla-delete vla-get-layer vla-put-layer vla-get-layers
vla-get-activedocument vlax-get-acad-object vla-get-modelspace vla-get-handle
vla-get-Handle vla-get-ObjectName
vlax-ename->vla-object vlax-vla-object->ename vlax-3d-point vlax-make-variant
vlax-make-safearray vlax-safearray-fill vlax-safearray->list vlax-variant-value
vlax-vbArray vlax-vbDouble vlax-curve-getstartpoint vlax-curve-getendpoint
vlax-curve-getstartparam vlax-curve-getendparam vlax-curve-getdistatparam
vlax-curve-getpointatdist vlax-curve-getpointatparam vlax-curve-getparamatpoint
vlax-curve-getclosestpointto vlax-curve-getfirstderiv vlax-erased-p
vla-getboundingbox vla-intersectwith vla-offset vla-addline vla-addarc vla-addcircle
vla-addtext vla-addlightweightpolyline vla-addpolyline vla-put-name vla-put-color
vla-put-startpoint vla-put-endpoint vla-put-startangle vla-put-endangle vla-put-height
vla-put-coordinate vla-get-coordinates vla-get-objectname vla-get-closed
vla-get-numberofvertices vla-get-center vla-get-radius vla-get-startpoint vla-get-endpoint
vla-get-startangle vla-get-endangle vla-get-menugroups vla-get-menus vla-get-count
vla-get-menubar vla-get-submenu vla-addsubmenu vla-addmenuitem vla-addseparator
vla-insertinmenubar vla-removefrommenubar vla-detach vla-get-macro vla-get-files
vla-get-preferences vla-put-supportpath vla-get-supportpath vla-get-name
vl-catch-all-apply vl-catch-all-error-p vl-catch-all-error-message vl-propagate
sqrt expt sin cos atan pi angle distance polar ssget ssname sslength
tblsearch handent vl-position vl-directory-files vl-filename-directory
findfile getfiled vl-mkdir vl-file-delete startapp alert load_dialog new_dialog
start_dialog unload_dialog set_tile get_tile action_tile done_dialog vl-sort
getenv numberp listp equal eq logior type atom boundp
1+ 1- + - * / = /= < > <= >= T nil
""".split())


def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == ';':
            while i < n and src[i] != '\n':
                i += 1
        elif c == '"':
            out.append('""')          # 字符串整体替换, 内部符号不参与分析
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2; continue
                if src[i] == '"':
                    break
                i += 1
            i += 1
        else:
            out.append(c); i += 1
    return ''.join(out)


def tokenize(code):
    return re.findall(r'\(|\)|""|[^\s()]+', code)


def split_top_level(src):
    forms, depth, start, line = [], 0, None, 1
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
        elif c == ';':
            while i < n and src[i] != '\n':
                i += 1
            continue
        elif c == '"':
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2; continue
                if src[i] == '"':
                    break
                i += 1
        elif c == '(':
            if depth == 0:
                start, l0 = i, line
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0 and start is not None:
                forms.append((l0, src[start:i+1])); start = None
        i += 1
    return forms


def analyze(path):
    raw = io.open(path, encoding='utf-8-sig').read()
    code = strip_comments(raw)
    defs, symcount = {}, defaultdict(int)
    for lineno, txt in split_top_level(code):
        tk = tokenize(txt)
        if len(tk) >= 3 and tk[1] == 'defun':
            name = tk[2]
            params, locals_, i = [], [], 3
            if i < len(tk) and tk[i] == '(':
                j, cur = i + 1, params
                while j < len(tk) and tk[j] != ')':
                    if tk[j] == '/':
                        cur = locals_
                    else:
                        cur.append(tk[j])
                    j += 1
                i = j + 1
            defs[name] = dict(line=lineno, params=params, locals=locals_,
                              body=tk[i:], norm=re.sub(r'\s+', ' ', ' '.join(tk[i:])).strip())
        for t in tk:
            if t not in ('(', ')', '""'):
                symcount[t.strip("'")] += 1
    # 字符串里的符号(DCL 宏 / action_tile 回调)也要计入引用
    for s in re.findall(r'"([^"]*)"', raw):
        for t in re.findall(r'[A-Za-z0-9_:+\-*/<>=.?!&%$#@]+', s):
            symcount[t] += 1
    return raw, code, defs, symcount


def bound_symbols(body):
    """返回函数体里被 setq / foreach / (lambda (...) ...) 绑定的符号集合"""
    tk = body
    out = set()
    i, n = 0, len(tk)
    while i < n:
        t = tk[i]
        if t == '(':
            # 跳过整个括号组: 只在组外识别 setq/foreach
            depth, j = 0, i
            while j < n:
                if tk[j] == '(':
                    depth += 1
                elif tk[j] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            head = tk[i+1] if i + 1 < n else ''
            inner = tk[i+1:j]
            if head == 'setq':
                k = 1
                while k < len(inner):
                    if inner[k] == '(':
                        d = 0
                        while k < len(inner):
                            if inner[k] == '(':
                                d += 1
                            elif inner[k] == ')':
                                d -= 1
                                if d == 0:
                                    break
                            k += 1
                    elif inner[k] != ')':
                        out.add(inner[k])
                    k += 1
            elif head == 'foreach':
                if len(inner) > 1:
                    out.add(inner[1])
            elif head == 'lambda':
                b = 2
                if b < len(inner) and inner[b] == '(':
                    b += 1
                    while b < len(inner) and inner[b] != ')':
                        if inner[b] != '/':
                            out.add(inner[b])
                        b += 1
            out |= bound_symbols(inner)   # 递归进入子组
            i = j + 1
        else:
            i += 1
    return out


def main():
    all_defs, all_sym, raws = {}, {}, {}
    for f in FILES:
        raw, code, defs, sym = analyze(os.path.join(HERE, f))
        raws[f], all_defs[f], all_sym[f] = raw, defs, sym

    print("=" * 78)
    print("1) 同名不同体函数(三脚本同加载时互相覆盖 —— 坑 #46)")
    print("=" * 78)
    byname = defaultdict(dict)
    for f, d in all_defs.items():
        for n, i in d.items():
            byname[n][f] = i
    bad = [(n, p) for n, p in byname.items()
           if len(p) > 1 and len(set(x['norm'] for x in p.values())) > 1]
    if bad:
        for n, p in sorted(bad):
            print(f"  [冲突] {n}  定义于 {list(p.keys())}")
            for f, i in p.items():
                print(f"      {f}:{i['line']} 参数={i['params']} 局部={i['locals']}")
    else:
        print(f"  无冲突(同名同体 {sum(1 for p in byname.values() if len(p) > 1)} 个, 安全)")

    print()
    print("=" * 78)
    print("2) 定义但从未被引用的函数(死代码候选)")
    print("=" * 78)
    total = defaultdict(int)
    for f in FILES:
        for k, v in all_sym[f].items():
            total[k] += v
    for f in FILES:
        dead = [(i['line'], n) for n, i in all_defs[f].items()
                if not n.startswith('c:') and n != '*error*' and total.get(n, 0) <= 1]
        if dead:
            print(f"  {f}:")
            for ln, n in sorted(dead):
                print(f"      L{ln}  {n}   (出现 {total.get(n, 0)} 次)")

    print()
    print("=" * 78)
    print("3) 绑定了但未声明为参数/局部变量的符号(全局变量泄漏)")
    print("=" * 78)
    hit = False
    for f in FILES:
        for n, info in sorted(all_defs[f].items(), key=lambda x: x[1]['line']):
            declared = set(info['params']) | set(info['locals'])
            leak = sorted(v for v in bound_symbols(info['body'])
                          if v not in declared
                          and not v.startswith('*')
                          and not re.match(r'^[-\d.]', v)
                          and v != '""')
            if leak:
                hit = True
                print(f"  {f}:{info['line']}  {n}  ->  {leak}")
    if not hit:
        print("  无")

    print()
    print("=" * 78)
    print("4) 声明了但从未使用的参数/局部变量")
    print("=" * 78)
    for f in FILES:
        for n, info in sorted(all_defs[f].items(), key=lambda x: x[1]['line']):
            toks = set(info['body'])
            unused = [v for v in (info['params'] + info['locals']) if v not in toks]
            if unused:
                print(f"  {f}:{info['line']}  {n}  ->  {unused}")

    print()
    print("=" * 78)
    print("5) 调用了但既未定义也非内置的函数")
    print("=" * 78)
    defined = set()
    for f in FILES:
        defined |= set(all_defs[f].keys())
    known = BUILTINS | defined
    calls = set()
    for f in FILES:
        for lineno, txt in split_top_level(strip_comments(raws[f])):
            tk = tokenize(txt)
            for k, t in enumerate(tk):
                if t == '(' and k + 1 < len(tk) and tk[k+1] not in ('lambda',):
                    calls.add(tk[k+1].strip("'"))
    miss = sorted(c for c in calls if c not in known and not c.startswith('dt:') and not c.startswith('c:'))
    print("  " + (", ".join(miss) if miss else "无"))


if __name__ == '__main__':
    main()
