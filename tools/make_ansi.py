# -*- coding: utf-8 -*-
"""make_ansi.py —— 生成并校验 ≤2020 AutoCAD(含 2007) 用的 ANSI/GBK 编码脚本副本。

背景(坑 #64, 2026-08-31): 本项目 scripts\\ 下的 .lsp 是 UTF-8 with BOM(2021+
Unicode LISP 正确解码)。≤2020 的 AutoCAD 是 MBCS(GBK) LISP, 其读取器按双字节
规则解析文件 —— UTF-8 中文注释/字符串的字节会被当作 GBK 双字节字符吞掉后面
的换行/引号/括号/点号, 破坏代码结构, 加载报「错误: 输入中的点位置不正确」。

用法: python make_ansi.py   (改完任何 .lsp 后、发版前必跑)
行为: scripts\\*.lsp -> scripts_ansi\\ 同名 GBK 副本(内容逐字同源, 仅注释与
      个别显示字符串里的 4 个非 GBK 装饰符号做等价替换), 并用"逐字节读取器
      模拟"校验副本与原件的字符串/括号结构完全一致; 任何一步失败即退出码 1。

部署: ≤2020 机器用 scripts_ansi\\ 的四个 .lsp 覆盖 scripts\\ 下同名文件(整个
      文件夹照常拷贝), APPLOAD + DTINSTALL; 2021+ 机器用 UTF-8 原版。
      scripts_ansi 不在支持路径上, 勿加入 2021+ 机器的支持路径(坑 #35)。
注意: check_lisp.py/_audit.py/_collide.py 只针对 UTF-8 原件; GBK 副本由本工具
      的回读+结构双重校验兜底, 不要拿 check_lisp 直接跑 GBK 文件(utf-8-sig
      解码会乱)。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
SRC = os.path.join(ROOT, 'scripts')
DST = os.path.join(ROOT, 'scripts_ansi')
FILES = ['dt_start.lsp', 'offset_runner.lsp', 'slot_runner.lsp', 'jrt_runner.lsp', 'size_runner.lsp']

# 仅注释与个别显示字符串中出现的非 GBK 装饰符号 -> GBK 等价写法(代码区纯 ASCII 不受影响)
REPL = {'▸': '>', '⇒': '=>', '²': '^2', '↔': '<->'}

README = """scripts_ansi —— ANSI/GBK 编码脚本副本(供 AutoCAD 2007~2020 使用)
================================================================
scripts\\ 里的 .lsp 是 UTF-8 with BOM 编码(2021+ 的 AutoCAD 需要);
2007~2020 的 AutoCAD 按 GBK 解析文件, 加载 UTF-8 版会报
「错误: 输入中的点位置不正确」。

部署(2007~2020 机器):
  1. 把整个 CAD 文件夹拷过去;
  2. 用本目录 4 个 .lsp 覆盖 scripts\\ 下同名文件(文件名相同, 直接替换);
  3. APPLOAD scripts\\dt_start.lsp -> DTINSTALL。其余步骤与 README 相同。

2021 及以上版本的 AutoCAD 不要用本目录, 用 scripts\\ 里的原版。
本目录不在 CAD 支持路径上; 每次改版 scripts\\ 后用 tools\\make_ansi.py 重新生成。
与原版的唯一内容差异: 个别注释/提示文字里的符号替换(▸ >、⇒ =>、O(n²) O(n^2)、↔ <->)。

已实测: AutoCAD 2007(32位) —— dt_start v2.9 的 GBK 副本 APPLOAD + DTINSTALL
一次通过, 三个脚本加载正常、顶栏「热流道自动化(R)」菜单挂出。
2007~2015 的 CAD 没有 TRUSTEDPATHS(2016 才引入), 安装时会打印
「TRUSTEDPATHS=无(老版本, 跳过)」, 这是正常的, 不影响使用。
若 DTINSTALL 报「参数类型错误: stringp nil」, 说明用的是 v2.8 或更早的
dt_start.lsp —— 换成 v2.9(重新生成本目录副本并覆盖)即可。
"""


def parse_unicode_strings(text):
    """UTF-8 文本的字符串提取(基准)"""
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            out.append(text[i + 1:j])
            i = j + 1
            continue
        if ch == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        i += 1
    return out


def parse_bytes(data):
    """逐字节模拟 ≤2020 AutoLISP 读取器: 返回 (字符串bytes列表, 括号平衡, 最小平衡, 错误)"""
    strings = []
    bal = min_bal = 0
    errors = []
    i, n = 0, len(data)
    in_str = in_com = False
    cur = bytearray()
    while i < n:
        b = data[i]
        if in_str:
            if b == 0x5C:
                cur.append(b)
                if i + 1 < n:
                    cur.append(data[i + 1])
                i += 2
                continue
            if b == 0x22:
                strings.append(bytes(cur))
                cur = bytearray()
                in_str = False
                i += 1
                continue
            cur.append(b)
            i += 1
            continue
        if in_com:
            if b == 0x0A:
                in_com = False
            i += 1
            continue
        if b == 0x22:
            in_str = True
            cur = bytearray()
        elif b == 0x3B:
            in_com = True
        elif b == 0x28:
            bal += 1
        elif b == 0x29:
            bal -= 1
            min_bal = min(min_bal, bal)
        i += 1
    if in_str:
        errors.append('文件结尾仍在字符串内(引号被吞)')
    if in_com:
        errors.append('文件结尾仍在注释内')
    return strings, bal, min_bal, errors


def main():
    ok = True
    os.makedirs(DST, exist_ok=True)
    for fn in FILES:
        text = open(os.path.join(SRC, fn), encoding='utf-8-sig').read()
        for k, v in REPL.items():
            text = text.replace(k, v)
        try:
            data = text.encode('gbk')
        except UnicodeEncodeError as e:
            ch = text[e.start:e.end]
            print('[FAIL] %s: 存在 GBK 不可编码字符 %r(请在 REPL 表补等价替换)' % (fn, ch))
            ok = False
            continue
        open(os.path.join(DST, fn), 'wb').write(data)

        # ---- 校验: 逐字节读取器模拟 vs 原件 ----
        g_strs, bal, min_bal, errors = parse_bytes(data)
        u_strs = parse_unicode_strings(text)
        same = u_strs == [s.decode('gbk', 'replace') for s in g_strs]
        good = same and bal == 0 and min_bal >= 0 and not errors
        print('%s: GBK %d bytes, strings %d/%d, 括号 %d(min %d) -> %s'
              % (fn, len(data), len(u_strs), len(g_strs), bal, min_bal,
                 'OK' if good else 'FAIL'))
        if not good:
            ok = False
            for a, b in zip(u_strs, g_strs):
                if a != b:
                    print('   首个差异: 期望 %r 实得 %r' % (a[:40], b[:40]))
                    break
            for e in errors:
                print('   错误:', e)
    readme = README
    for k, v in REPL.items():
        readme = readme.replace(k, v)
    with open(os.path.join(DST, '说明.txt'), 'w', encoding='gbk') as f:
        f.write(readme)
    print('结果:', 'ALL OK(说明.txt 已更新)' if ok else '存在问题')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
