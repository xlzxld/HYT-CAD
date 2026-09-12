#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""JRT 通用二出线口产物回归检查(零依赖, 只读解析 DXF).

用法: python tools/check_jrt2_out.py <dxf文件> [--layer JRT]

断言(口径=1714 测试图(2026-09-09 已移出仓库) + 默认参数跑 JRT 通用二
后的正确产物; jrt v9.36 起破口封闭线本体回归 "JRT" —— "JRTFBX" 只是
定位副本(不在默认口径内), 故默认检查回归单层 "JRT"(= v9.33 及以前口径)):
  A. 无短斜线: 长度<12 且非水平/竖直的 LINE = 0
     (v9.27 缺口 -> 环链断裂 -> dt:jrt2-close 误配出 4 条 X 交叉斜线)
  B. 无近失接头: 端点间距落在 (0.01, 3.0) 的端点对 = 0
     (v9.27 肩部缺口实测 0.65/1.33/1.78mm, 两侧共 6 对)
  C. 自由端恰 2 个(两条中线墙顶, v9.27 为 6 个)
  D. 图层实体数: 15 弧 + 14 线(v9.27 为 15 弧 + 18 线)

注: 本检查绑定 1714 测试图(已移出仓库, 重跑需自备同图)与默认参数
(half_w=16.5, step=4, count=2,
end_r=12, hook_ext=10); 换图/换参后断言 C/D 需按新结构核对。

退出码: 全部通过=0, 任一失败=1(逐条列出)。
"""
import sys

TOL_JOIN = 0.01      # 端点重合判定
NEAR_LO, NEAR_HI = 0.01, 3.0   # 近失接头距离带
SHORT_LEN = 12.0     # 短斜线长度上限
AXIS_TOL = 1e-6      # 水平/竖直判定
EXPECT_ARCS = 15
EXPECT_LINES = 14
EXPECT_FREE = 2


def groups(path):
    with open(path, 'r', encoding='latin-1') as f:
        lines = f.read().splitlines()
    i = 0
    while i + 1 < len(lines):
        yield lines[i].strip(), lines[i + 1]
        i += 2


def parse_entities(path):
    """返回 ENTITIES 节内实体列表 [(type, {code: [values...]})]。"""
    ents, cur, section = [], None, None
    for code, val in groups(path):
        if code == '0':
            if val == 'SECTION':
                section, cur = None, None
            elif val == 'ENDSEC':
                section, cur = None, None
            elif section == 'ENTITIES':
                cur = {'type': val, 'g': {}}
                ents.append(cur)
            else:
                cur = None
            continue
        if section is None and code == '2':
            section = val  # 节名: HEADER/TABLES/BLOCKS/ENTITIES/...
            continue
        if cur is not None and section == 'ENTITIES':
            cur['g'].setdefault(code, []).append(val)
    return ents


def f1(vals):
    return float(vals[0])


def endpoints(ent):
    """实体端点列表(LINE 两端/ARC 两端/CIRCLE 闭合无端点)。"""
    t, g = ent['type'], ent['g']
    if t == 'LINE':
        return [(f1(g['10']), f1(g['20'])), (f1(g['11']), f1(g['21']))]
    if t == 'ARC':
        import math
        cx, cy, r = f1(g['10']), f1(g['20']), f1(g['40'])
        a1, a2 = math.radians(f1(g['50'])), math.radians(f1(g['51']))
        return [(cx + r * math.cos(a1), cy + r * math.sin(a1)),
                (cx + r * math.cos(a2), cy + r * math.sin(a2))]
    return []  # CIRCLE/其他: 闭合或忽略


def main():
    # 两两扫描: --layer 的取值是它的下一参数, 不算位置参数
    # (旧写法把带值选项的取值也收进位置参数, `--layer JD x.dxf` 会把
    #  "JD" 当文件名, 裸 traceback)
    argv = sys.argv[1:]
    args = []
    layers = {'JRT'}
    i = 0
    # jrt v9.36 起破口封闭线本体在 "JRT"(JRTFBX 仅定位副本), 口径单层;
    # --layer 可改查其他单层。
    while i < len(argv):
        a = argv[i]
        if a == '--layer':
            if i + 1 < len(argv):
                layers = {argv[i + 1]}
                i += 2
            else:
                print('错误: --layer 需要一个图层名参数')
                return 2
        elif a.startswith('--'):
            print('错误: 未知选项 %r' % a)
            return 2
        else:
            args.append(a)
            i += 1
    if not args:
        print(__doc__)
        return 2
    ents = [e for e in parse_entities(args[0])
            if e['g'].get('8', [''])[0] in layers]
    lines = [e for e in ents if e['type'] == 'LINE']
    arcs = [e for e in ents if e['type'] == 'ARC']
    others = [e for e in ents if e['type'] not in ('LINE', 'ARC', 'CIRCLE')]

    pts = []  # (x, y, 实体序号)
    for i, e in enumerate(ents):
        for p in endpoints(e):
            pts.append((p[0], p[1], i))

    fails = []

    # A. 短斜线(封口误配的 X 交叉斜线特征)
    skew = []
    for e in lines:
        g = e['g']
        dx = f1(g['11']) - f1(g['10'])
        dy = f1(g['21']) - f1(g['20'])
        ln = (dx * dx + dy * dy) ** 0.5
        if ln < SHORT_LEN and abs(dx) > AXIS_TOL * ln and abs(dy) > AXIS_TOL * ln:
            skew.append(((f1(g['10']), f1(g['20'])), (f1(g['11']), f1(g['21'])), ln))
    if skew:
        fails.append('A. 短斜线 %d 条(应0): %s' % (len(skew), skew))
    else:
        print('A. 短斜线=0 OK')

    # B. 近失接头(链上缺口特征)
    near = []
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            if pts[i][2] == pts[j][2]:
                continue
            d = ((pts[i][0] - pts[j][0]) ** 2 + (pts[i][1] - pts[j][1]) ** 2) ** 0.5
            if NEAR_LO < d < NEAR_HI:
                near.append((pts[i][:2], pts[j][:2], round(d, 3)))
    if near:
        fails.append('B. 近失接头 %d 对(应0): %s' % (len(near), near))
    else:
        print('B. 近失接头=0 OK')

    # C. 自由端(无其他实体端点在 TOL_JOIN 内)
    free = []
    for i, p in enumerate(pts):
        if not any(k != i and pts[k][2] != p[2] and
                   (pts[k][0] - p[0]) ** 2 + (pts[k][1] - p[1]) ** 2 < TOL_JOIN ** 2
                   for k in range(len(pts))):
            free.append((round(p[0], 2), round(p[1], 2)))
    if len(free) != EXPECT_FREE:
        fails.append('C. 自由端 %d 个(应%d): %s' % (len(free), EXPECT_FREE, sorted(free)))
    else:
        print('C. 自由端=%d OK %s' % (len(free), sorted(free)))

    # D. 实体数量结构
    if len(arcs) != EXPECT_ARCS or len(lines) != EXPECT_LINES or others:
        fails.append('D. 实体数 弧%d(应%d)/线%d(应%d)/其他%d(应0)'
                     % (len(arcs), EXPECT_ARCS, len(lines), EXPECT_LINES, len(others)))
    else:
        print('D. 实体数 弧%d/线%d OK' % (len(arcs), EXPECT_LINES))

    print('== %s: %s' % (args[0], 'FAIL' if fails else 'ALL OK'))
    for m in fails:
        print('  ' + m)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
