# -*- coding: utf-8 -*-
"""check_audit_fixes.py —— 2026-09-09 全项目体检(AGENTS.md §4)修复回归断言。

每项断言对应体检清单中一处确凿缺陷的修复: 修复前失败、修复后通过。
纯标准库、零依赖, 做文本/结构级断言; 运行时几何行为仍需 AutoCAD 实测
(见体检报告的手动验证清单)。
用法: python tools/check_audit_fixes.py    退出码 0=全部通过 1=有失败。
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.normpath(os.path.join(HERE, '..', 'scripts'))

RESULTS = []


def load(name):
    with io.open(os.path.join(SCRIPTS, name), encoding='utf-8-sig') as f:
        return f.read()


def code_of(name):
    """去注释代码视图(与 check_lisp.py 口径一致) —— 断言只看代码,
    不被版本账注释里引用的旧写法字样误命中。"""
    return '\n'.join(re.sub(r';.*$', '', l)
                     for l in load(name).splitlines())


def check(cid, desc, fn):
    try:
        ok, evidence = fn()
    except Exception as e:  # 断言工具必须把加载失败报告出来而非吞掉
        ok, evidence = False, '加载失败: %r' % (e,)
    RESULTS.append((cid, ok))
    print('[%s] %s: %s' % ('PASS' if ok else 'FAIL', cid,
                           desc if ok else '%s | %s' % (desc, evidence)))


# ---------------------------------------------------------------------------
# A-02 多段线类名判定恒假: LWPolyline 的 ObjectName 是 "AcDbPolyline",
# "(= ... \"AcDbLWPolyline\")" 单名等式恒 nil → dt:poly-pts 把 2D 平铺坐标
# 按 3 元素切分(顶点全错位)、dt:poly-rebuild 误建 3D 多段线。
# 断言: cx/flb/jrt 三文件中不得再有单名等式, 且双名 member 各不少于 2 处
# (dt:poly-pts 与 dt:seg-rebuild 各一; cut-curve 闭合检查本就双名, 不计)。
# ---------------------------------------------------------------------------
BAD_IS2D = re.compile(
    r'=\s*(\(vla-get-objectname obj\)|obj-type)\s*"AcDbLWPolyline"')
GOOD_IS2D = re.compile(
    r"member\s*(?:\(vla-get-objectname obj\)|obj-type)"
    r"\s*'\(\"AcDbLWPolyline\" \"AcDbPolyline\"\)")


def a02():
    bad = []
    for fn_name in ('cx_runner.lsp', 'flb_runner.lsp', 'jrt_runner.lsp'):
        src = load(fn_name)
        n_bad = len(BAD_IS2D.findall(src))
        n_good = len(GOOD_IS2D.findall(src))
        if n_bad:
            bad.append('%s: 仍有 %d 处单名等式' % (fn_name, n_bad))
        if n_good < 2:
            bad.append('%s: 双名 member 应>=2 处, 实为 %d' % (fn_name, n_good))
    return (not bad), ('; '.join(bad) if bad
                       else 'cx/flb/jrt 各 2 处均已双名 member')


check('A-02', '多段线类名判定恒假根治(cx/flb/jrt 各2处)', a02)


# ---------------------------------------------------------------------------
# A-01 通用二出线口重跑不幂等: 重跑清理(遍历 *jrt2-made*)只删图层 "JRT"
# 的句柄, 而 dt:jrt2-neck 产物全部画在 "JT" 层 → 旧出线口永不清除, 逐次
# 叠加。断言: 清理分支的图层判定为 member '("JRT" "JT" "JRTFBX")
# (v9.31 双成员; v9.34 封闭线移 "JRTFBX" 层后一并纳入, 三缺一即 FAIL)。
# ---------------------------------------------------------------------------
A01 = re.compile(
    r"member\s*\(vl-catch-all-apply 'vla-get-layer \(list obj\)\)"
    r"\s*'\(\"JRT\" \"JT\" \"JRTFBX\"\)")


def a01():
    src = load('jrt_runner.lsp')
    return bool(A01.search(src)), "未找到清理分支 member '(\"JRT\" \"JT\" \"JRTFBX\")"


check('A-01', 'jrt 通用二出线口重跑幂等(清理含 JT/JRTFBX 层)', a01)

# ---------------------------------------------------------------------------
# A-04 封闭线图层契约: v9.34 把通用二破口封闭线整体挪到 "JRTFBX", 破坏了
# "JRT = 完整加热条"契约(外协按图层白名单取线, 漏 JRTFBX 即出图缺线);
# v9.35 又确认它同样不该加给通用一(通用一是"半成品"嵌套轮廓, 无出线口,
# 其帽线属端帽)。v9.36 定案: 封闭线本体在 "JRT", "JRTFBX" 仅为同几何定位
# 副本(dt:jrt2-trace), 供另一项目建模脚本按层定位。
# 断言: 两侧均不得把实体直接 put-layer 到 "JRTFBX"(须经 trace 助手);
#       通用一不得做 JRTFBX 快照/清理; dt:jrt2-close 传 "JRT" 且
#       dt:jrt2-trace 描 "JRTFBX"; ensure-layer "JRTFBX" 恰 1 处。
# ---------------------------------------------------------------------------
A04_DIRECT = [
    (re.compile(r'\(vla-put-layer\s+\S+\s+"JRTFBX"\)'), 'JRTFBX 直接 put-layer(应经 dt:jrt2-trace)'),
    (re.compile(r'\(dt:jrt-snapshot "JRTFBX"\)'), 'dt:jrt-snapshot "JRTFBX"'),
    (re.compile(r'\(dt:purge-layer "JRTFBX"\)'), 'dt:purge-layer "JRTFBX"'),
]
A04_CLOSE = re.compile(r'\(dt:jrt2-close ends kmap "JRT"\)')
A04_TRACE = re.compile(r'\(dt:jrt2-trace clns "JRTFBX"\)')
A04_ENSURE = re.compile(r'\(dt:ensure-layer layers "JRTFBX" 21')


def a04():
    src = code_of('jrt_runner.lsp')
    bad = [d for p, d in A04_DIRECT if p.search(src)]
    if bad:
        return False, '残留直接写 JRTFBX: %s' % '; '.join(bad)
    n = len(A04_ENSURE.findall(src))
    if n != 1:
        return False, 'ensure-layer "JRTFBX" 应恰好 1 处(通用二), 实为 %d' % n
    if not A04_CLOSE.search(src):
        return False, '通用二 dt:jrt2-close 未传 "JRT"'
    if not A04_TRACE.search(src):
        return False, '缺 dt:jrt2-trace ... "JRTFBX" 定位副本'
    return True, '封闭线本体在 JRT + JRTFBX 仅定位副本(ensure 恰 1 处)'


check('A-04', '封闭线图层契约(本体 JRT / JRTFBX 仅定位副本)', a04)

# ---------------------------------------------------------------------------
# B-08 dt:jrt2-wall-tan 终点侧取样未判空: 交点距壁端 <0.01 时
# getpointatdist(+dist 0.01) 越界返 nil(低版本不抛错), (nth 0 p2) 直接
# 入减法 → 参数类型错误。断言: 函数内存在 p1/p2 非 nil + error-p 双判。
# ---------------------------------------------------------------------------
B08 = re.compile(
    r"\(and p1 p2\s*\(not \(vl-catch-all-error-p p1\)\)"
    r"\s*\(not \(vl-catch-all-error-p p2\)\)\)")


def b08():
    src = load('jrt_runner.lsp')
    return bool(B08.search(src)), 'dt:jrt2-wall-tan 缺 p1/p2 双判'


check('B-08', 'jrt wall-tan 端点取样判空', b08)


# ---------------------------------------------------------------------------
# A-03 flb 包络法假体包络盒混入文字: dt:jt-build 取 FLB 包络盒未过滤实体
# 类型, 倒角失败标注文字(chamfer-close 标注 FBX → merge-layer 并入 FLB)
# 的 boundingbox 被计入 → JT 假体沿标注方向不对称撑大。
# 断言: objs 必须经 dt:curves-only 过滤后再取包络盒。
# ---------------------------------------------------------------------------
A03 = re.compile(
    r'\(setq objs \(dt:curves-only \(dt:layer-vlas "FLB"\)\)\)')


def a03():
    src = load('flb_runner.lsp')
    return bool(A03.search(src)), 'dt:jt-build 未对 FLB 实体做 curves-only 过滤'


check('A-03', 'flb 包络法假体包络盒剔除文字标注', a03)


# ---------------------------------------------------------------------------
# B-01 wx 精雕保色查错文档: dt:sz-flatten-layer 第一实参传 tgt-doc, 但实体
# 此刻还是 cur-doc 的临时克隆(CopyObjects 在其后才发生) → ByLayer 实体查到
# 目标图 ensure 过的固定层色, 原色保留落空。断言: 两处调用均传 cur-doc。
# ---------------------------------------------------------------------------
def b01():
    src = code_of('wx_runner.lsp')
    n_cur = len(re.findall(r'dt:sz-flatten-layer cur-doc', src))
    n_tgt = len(re.findall(r'dt:sz-flatten-layer tgt-doc', src))
    return n_cur >= 2 and n_tgt == 0, \
        'flatten-layer 调用 cur-doc=%d(需>=2), 残留 tgt-doc=%d(需0)' % (n_cur, n_tgt)


check('B-01', 'wx 精雕 JD 保色 flatten 实参改 cur-doc', b01)

# ---------------------------------------------------------------------------
# B-02 wx 硬编码本机路径: ini 未配置 root 时的兜底写死 C:\Users\5600\...,
# 换机即往错误位置建目录。断言: wx_runner.lsp 不再出现硬编码用户目录。
# ---------------------------------------------------------------------------
B02 = re.compile(r'C:\\\\Users\\\\')


def b02():
    src = code_of('wx_runner.lsp')
    n = len(B02.findall(src))
    return n == 0, '仍有 %d 处 C:\\\\Users\\\\ 硬编码' % n


check('B-02', 'wx 兜底根目录改 USERPROFILE 推导', b02)

# ---------------------------------------------------------------------------
# B-05/B-06 死代码: 定义后全库零引用(体检时 grep 取证)。
# ---------------------------------------------------------------------------
def dead_symbols():
    src = code_of('wx_runner.lsp')
    jrt = code_of('jrt_runner.lsp')
    problems = []
    if '*dt-outsource-target-dwg*' in src:
        problems.append('wx 仍有死全局 *dt-outsource-target-dwg*')
    if 'dt:sz-norm-ang' in src:
        problems.append('wx 仍有死函数 dt:sz-norm-ang')
    if 'dt:jrt2-out-end' in jrt:
        problems.append('jrt 仍有死函数 dt:jrt2-out-end')
    n_undo_end = len(re.findall(r'\(defun dt:jrt-undo-end', jrt))
    if n_undo_end != 1:
        problems.append('dt:jrt-undo-end 应恰好定义 1 次, 实为 %d' % n_undo_end)
    return not problems, ('; '.join(problems) if problems
                          else '死符号清零, dt:jrt-undo-end 唯一定义')


check('B-03/B-04/B-05/B-06', '死代码清除(wx×2, jrt×2 含重复defun)', dead_symbols)

# ---------------------------------------------------------------------------
# B-11 wx FLBSZ 撤销组兜底 + SJTZ API 混用: FLBSZ 的 *error* 只打印不闭合
# 包络框 UNDO 组(command BE); SJTZ 以 (command "_.UNDO" "E") 闭合
# vla-startundomark 开的组(与坑#69 全 COM 化相悖)。
# 断言: FLBSZ 有 undo-started 兜底; wx 中 "_.UNDO" "E" 仅剩 BE/E 配对 1 处。
# ---------------------------------------------------------------------------
def b11():
    src = code_of('wx_runner.lsp')
    m = re.search(r'\(defun c:FLBSZ\b.*?\n\(defun c:FLBSIZE', src, re.S)
    if not m:
        return False, '未定位到 c:FLBSZ 函数块'
    if 'undo-started' not in m.group(0):
        return False, 'c:FLBSZ 缺 undo-started 兜底'
    n_e = len(re.findall(r'"\_\.UNDO" "E"', src))
    return n_e == 1, '残留 (command "_.UNDO" "E") 应为1处(BE/E配对), 实为 %d' % n_e


check('B-11', 'wx FLBSZ 撤销兜底 + SJTZ 撤销收口 COM 化', b11)

# ---------------------------------------------------------------------------
# B-12 wx 排版定位基准(可靠源, 而非文字 maxx / MText bbox):
#   旧版(≤v2.12)行内追加在无会话游标时回退"文字 maxx + 20 + box_gap", 文字居中
#   且宽钳 <=220、比工件窄 → 相邻幅间距忽大忽小(实测 10 幅里 1 幅不同)。
#   v2.13 起: 单元盒 = (图形 ∪ 本幅文字) 外扩 box_margin, 四向净距 = box_gap。
#   v2.14: 又发现 v2.13 用"目标图里 MText 的 boundingbox"算行顶/行右缘不可靠
#   (非活动文档里复制过去的 MText, 实体范围不即时正确 —— 实测行顶偏低 86mm,
#   导致逐幅 Y 乱飘、行判定失效永不换行)。现在排版基准只取可靠源:
#   文字"插入点"(属性直读)、内容实体 bbox、当前图里的单元盒测量。
#   断言: 可靠源基准齐备 + 旧"文字 maxx"基准清零 + 文件内不得再出现 MText bbox 读取。
# ---------------------------------------------------------------------------
def b12():
    src = code_of('wx_runner.lsp')
    if '*dt-wx-last-right*' not in src:
        return False, '缺单元盒右缘游标 *dt-wx-last-right*'
    if not re.search(r'\(\+ \(if \*dt-wx-last-right\* \*dt-wx-last-right\* 0\.0\) box-gap\)', src):
        return False, '行内追加未以单元盒右缘 + box_gap 定位'
    if '(setq *dt-wx-last-right* (+ x0 ub-w))' not in src:
        return False, '成功导出后未把游标更新为单元盒右缘'
    if re.search(r'\(\+ row-maxx 20\.0 box-gap\)', src):
        return False, '仍残留"文字 maxx + 盒边距"旧基准'
    if '(dt:sz-row-right tgt-doc row-ctop box-margin)' not in src:
        return False, '缺无游标时的内容几何反推 dt:sz-row-right'
    if '(dt:sz-make-title cur-doc' not in src:
        return False, '文字未在排版前生成(无法量出"图形∪文字"单元盒)'
    if 'txt-bb' in src:
        return False, '仍在读 MText 的 boundingbox(非活动文档里不可靠, 见 v2.14)'
    if '(- txt-min-y text-gap)' not in src:
        return False, '行内容顶未由"文字插入点 Y − text_gap"推导'
    if '"text_gap"' not in src or '"box_margin"' not in src:
        return False, '缺 text_gap / box_margin 配置读取'
    return True, '可靠源基准齐备(插入点/内容 bbox/当前图测量); 旧文字 maxx 与 MText bbox 均清零'


check('B-12', 'wx 排版定位基准(可靠源: 插入点/内容 bbox/当前图测量)', b12)


# ---------------------------------------------------------------------------
# B-07 cx 3D 折线静默忽略: dt:cx-yxb-segs-of 的 member 表含无效类名
# "AcDbLWPolyline"(死项)且缺 "AcDb3dPolyline" → 3D 折线落入 (T nil) 被静默
# 跳过, 与函数头注释"3D 折线按直段处理"矛盾。断言: member 表三真实类名。
# ---------------------------------------------------------------------------
B07 = re.compile(
    r"\(member oname '\(\"AcDb2dPolyline\" \"AcDbPolyline\" \"AcDb3dPolyline\"\)\)")


def b07():
    src = code_of('cx_runner.lsp')
    return bool(B07.search(src)), 'segs-of 的 member 表未改为三个真实类名'


check('B-07', 'cx segs-of 3D 折线入列+死类名清除', b07)

# ---------------------------------------------------------------------------
# B-10 cx 宿主壁失效引用: 同一宿主壁两端各命中 T 接时, 第二处循环的 host
# 已被首次 break-curve(删旧建新)删除, 对已删实体的几何调用抛错中断整个
# 阶段。断言: break-curve 前存在 host 存活复检。
# ---------------------------------------------------------------------------
B10 = re.compile(r"vlax-erased-p \(list host\)")


def b10():
    src = code_of('cx_runner.lsp')
    return bool(B10.search(src)), 'dt:cx-join 的 host 缺存活复检'


check('B-10', 'cx T接宿主壁存活复检', b10)


# ---------------------------------------------------------------------------
# B-09 flb *error* 撤销兜底失效: 坑#69(jrt v9.17 定案)—— *error* 内调
# (command) 会抛错并被 catch 吞掉, 兜底恰在出错场景失效、UNDO 组悬挂。
# 断言: c:FLB 的 *error* 兜底为 COM vla-EndUndoMark, 旧 command 兜底消失。
# ---------------------------------------------------------------------------
B09_OLD = re.compile(r"'\(lambda \( \) \(command \"_\.UNDO\" \"E\"\)\)")


def b09():
    src = code_of('flb_runner.lsp')
    if B09_OLD.search(src):
        return False, '*error* 仍在 *error* 内用 (command "_.UNDO" "E") 兜底'
    if 'vla-EndUndoMark' not in src:
        return False, 'flb 缺 COM EndUndoMark 兜底'
    return True, '*error* 兜底已 COM 化'


check('B-09', 'flb *error* 撤销兜底 COM 化', b09)


# ---------------------------------------------------------------------------
# BANNER 加载横幅版本单一来源: 横幅曾长期硬编码版本号导致与头注脱节
# (体检时 v9.29/v11.3/v10.6/v2.8 全部滞后)。断言: 四个 runner 均定义版本
# 常量且横幅引用变量, 代码中不再出现 "已加载 v<数字>" 式硬编码。
# ---------------------------------------------------------------------------
def banners():
    problems = []
    specs = [('jrt_runner.lsp', '*dt-jrt-ver*'),
             ('cx_runner.lsp', '*dt-cx-ver*'),
             ('flb_runner.lsp', '*dt-flb-ver*'),
             ('wx_runner.lsp', '*dt-wx-ver*')]
    for fn, var in specs:
        src = code_of(fn)
        if var not in src:
            problems.append('%s 缺版本常量 %s' % (fn, var))
        if re.search(r'已加载 v\d', src):
            problems.append('%s 横幅仍硬编码版本号' % fn)
    dt = code_of('dt_start.lsp')
    if '(strcat "\\ndt_start 已加载 " dt:st-version' not in dt:
        problems.append('dt_start 横幅未引用 dt:st-version')
    return not problems, ('; '.join(problems) if problems
                          else '四个 runner + dt_start 横幅均走版本常量')


check('BANNER', '加载横幅版本号单一来源(不再硬编码)', banners)


def main():
    n_ok = sum(1 for _, ok in RESULTS if ok)
    fails = [cid for cid, ok in RESULTS if not ok]
    print('结果: %s (%d/%d 通过)' % ('ALL OK' if not fails else
                                    'FAIL: ' + ','.join(fails),
                                    n_ok, len(RESULTS)))
    sys.exit(0 if not fails else 1)


if __name__ == '__main__':
    main()
