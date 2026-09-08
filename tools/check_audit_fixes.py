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
# 叠加。断言: 清理分支的图层判定为双成员 member '("JRT" "JT")。
# ---------------------------------------------------------------------------
A01 = re.compile(
    r"member\s*\(vl-catch-all-apply 'vla-get-layer \(list obj\)\)"
    r"\s*'\(\"JRT\" \"JT\"\)")


def a01():
    src = load('jrt_runner.lsp')
    return bool(A01.search(src)), "未找到清理分支 member '(\"JRT\" \"JT\")"


check('A-01', 'jrt 通用二出线口重跑幂等(清理含 JT 层)', a01)

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


def main():
    n_ok = sum(1 for _, ok in RESULTS if ok)
    fails = [cid for cid, ok in RESULTS if not ok]
    print('结果: %s (%d/%d 通过)' % ('ALL OK' if not fails else
                                    'FAIL: ' + ','.join(fails),
                                    n_ok, len(RESULTS)))
    sys.exit(0 if not fails else 1)


if __name__ == '__main__':
    main()
