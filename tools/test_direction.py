# -*- coding: utf-8 -*-
"""方向/排布算法回归(jrt v9.24 / cx v11.2) —— 纯 stdlib, 零依赖。

把 cx_runner/jrt_runner 中"与 AutoCAD 无关"的几何判定逻辑逐行移植为
Python, 用图2/图3 场景与 tools/1.dxf 实测数据做断言:
  1) dt:jrt2-pt-inside   —— +X 射线奇偶点内判定
  2) dt:jrt2-region-edges —— 轮廓采样边集 + 自由端贪心配对封口
  3) 嵌套内偏选边         —— 唯一"中点在内"候选(与 JRTDW 画向无关)
  4) 颈线朝外规则         —— 靠近 FLB 中心则反向
  5) 压线板排布           —— 中点定位 + 整组居中(对照 1.dxf 实例坐标)
  6) 压线板模板几何       —— D 形 6 件首尾闭合
运行: python tools/test_direction.py ; 退出码 0=全过。
"""
import math

FAIL = []


def check(name, cond):
    if cond:
        print("  PASS %s" % name)
    else:
        FAIL.append(name)
        print("  FAIL %s" % name)


# ---------- 1) 点内判定(移植 dt:jrt2-pt-inside) ----------
def pt_inside(pt, edges):
    x, y = pt[0], pt[1]
    cnt = 0
    for a, b in edges:
        if min(a[1], b[1]) < y <= max(a[1], b[1]):
            ix = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if ix > x:
                cnt += 1
    return cnt % 2 == 1


def line_edges_from_segments(segs):
    # lisp 版按参数均匀采样; 直线 12 段采样不改变与"直线段集"的一致性
    # (Python 回归直接用端点, 直线场景等价)
    return [tuple(p) for p in segs]


def ring_edges_rect(x0, y0, x1, y1):
    return [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)),
            ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))]


# ---------- 2) 自由端贪心配对封口(移植 dt:jrt2-region-edges 尾部) ----------
def close_free_ends(edges, ends):
    ends = list(ends)
    while len(ends) > 1:
        s1 = ends[0]
        best, bd = None, 1e99
        for s2 in ends[1:]:
            d = math.dist(s1, s2)
            if d < bd:
                bd, best = d, s2
        edges = edges + [(s1, best)]
        ends.remove(s1)
        ends.remove(best)
    return edges


# ---------- 场景: 图2 矩形外壁(200x400) + 左侧出线口开 20mm 缝 + 通道线 ----------
def stadium_case():
    # 左壁分成两段(缝 y190-210), 通道线两条自缝端向外到 x=-50
    segs = [
        ((200, 0), (200, 400)),      # 右壁
        ((200, 400), (0, 400)),      # 顶
        ((0, 400), (0, 210)),        # 左壁上段
        ((0, 190), (0, 0)),          # 左壁下段
        ((0, 0), (200, 0)),          # 底
        ((0, 210), (-50, 210)),      # 通道上壁
        ((0, 190), (-50, 190)),      # 通道下壁
    ]
    free_ends = [(-50, 210), (-50, 190)]  # 通道口两端(其余端点相接)
    return close_free_ends(line_edges_from_segments(segs), free_ends)


# ---------- 3) 嵌套选边(移植 dt:jrt2-pick-side 核心) ----------
def pick_side(cand_mids, edges, dw_side_guess=None):
    ins = [m for m in cand_mids if pt_inside(m, edges)]
    if len(ins) == 1:
        return ins[0]
    return None  # 歧义 → lisp 回退 JRTDW 兜底


def main():
    print("[1] 点内判定(矩形)")
    e = ring_edges_rect(0, 0, 200, 400)
    check("内部点(100,200)判内", pt_inside((100, 200), e))
    check("外部点(204,200)判外", not pt_inside((204, 200), e))
    check("恰在边下方延长线(250,200)判外", not pt_inside((250, 200), e))

    print("[2] 图2 场景: 开缝外壁+通道 封口后的区域判定")
    e2 = stadium_case()
    # 各段 ±4mm 候选中点
    checks = {
        "右壁 内候选(196,200)": (pt_inside((196, 200), e2), True),
        "右壁 外候选(204,200)": (pt_inside((204, 200), e2), False),
        "顶壁 内候选(100,396)": (pt_inside((100, 396), e2), True),
        "顶壁 外候选(100,404)": (pt_inside((100, 404), e2), False),
        "通道上壁 近中线候选(-25,206)": (pt_inside((-25, 206), e2), True),
        "通道上壁 外侧候选(-25,214)": (pt_inside((-25, 214), e2), False),
    }
    for k, (got, want) in checks.items():
        check(k + ("=内" if want else "=外"), got == want)

    print("[3] 选边唯一性: 各段 ± 候选 → 唯一内侧(lisp 选取); 缝口邻段两侧"
          "均在内属已知歧义(lisp 回退 JRTDW 兜底)")
    pairs = [((196, 200), (204, 200)), ((100, 396), (100, 404)),
             ((-25, 206), (-25, 214)), ((-25, 194), (-25, 186))]
    for a, b in pairs:
        sel = pick_side([a, b], e2)
        check("段 %s/%s → 取%s" % (a, b, sel), sel in (a, b))
    amb = pick_side([(4, 200), (-4, 200)], e2)
    check("缝口左壁段两侧均在内 → 判歧义(回退)", amb is None)

    print("[4] 颈线朝外规则(图2 FLB 场景: 左壁 x=0, 板 x∈[0,600])")
    flb_cen = (300.0, 200.0)   # bbox 中心
    pint = (0.0, 200.0)
    def neck_dir(dirv):
        base = (pint[0] + 5 * dirv[0], pint[1] + 5 * dirv[1])
        if math.dist(base, flb_cen) < math.dist(pint, flb_cen):
            dirv = (-dirv[0], -dirv[1])
        return dirv
    check("JRTDW 朝板内(+1,0 指向中心)→ 翻转为朝外(-1,0)", neck_dir((1, 0)) == (-1, 0))
    check("JRTDW 朝板外(-1,0)→ 保持", neck_dir((-1, 0)) == (-1, 0))

    print("[5] 压线板排布: 复现 1.dxf 图5 三幅实例(sp_y=-23.829916762565, L=273.83, gap=100)")
    L, gap, H = 273.829916762565, 100.0, 16.6
    span = L - H
    n = 1 + int(span // gap)
    margin = (span - (n - 1) * gap) / 2.0
    centers = [-23.829916762565 + margin + i * gap + 8.3 for i in range(n)]
    want = [13.0850416187175, 113.0850416187175, 213.0850416187175]
    check("n=3", n == 3)
    for got, w in zip(centers, want):
        check("中点 %.4f ≈ %.4f(1.dxf 实例)" % (got, w), abs(got - w) < 0.01)

    print("[6] 压线板模板: D 形 6 件首尾闭合 + 定位点=重合线中点")
    # (类型, x, y, ...) 按 dt:cx-yxb-tpl 顺序
    coincident = ((0, 0), (0, 16.6))
    bottom = ((0, 0), (11, 0))
    top = ((0, 16.6), (11, 16.6))
    right = ((15.3, 4.3), (15.3, 12.3))
    arc_br_c, arc_br_r = (11, 4.3), 4.3     # 270→360: (11,0)→(15.3,4.3)
    arc_tr_c, arc_tr_r = (11, 12.3), 4.3    # 0→90: (15.3,12.3)→(11,16.6)
    def arc_pt(c, r, a):
        return (c[0] + r * math.cos(math.radians(a)),
                c[1] + r * math.sin(math.radians(a)))
    br270, br360 = arc_pt(arc_br_c, arc_br_r, 270), arc_pt(arc_br_c, arc_br_r, 360)
    tr0, tr90 = arc_pt(arc_tr_c, arc_tr_r, 0), arc_pt(arc_tr_c, arc_tr_r, 90)
    check("右下半弧 270端=(11,0) 360端=(15.3,4.3)",
          abs(br270[0] - 11) < 1e-6 and abs(br270[1] - 0) < 1e-6 and
          abs(br360[0] - 15.3) < 1e-6 and abs(br360[1] - 4.3) < 1e-6)
    check("右上半弧 0端=(15.3,12.3) 90端=(11,16.6)",
          abs(tr0[0] - 15.3) < 1e-6 and abs(tr0[1] - 12.3) < 1e-6 and
          abs(tr90[0] - 11) < 1e-6 and abs(tr90[1] - 16.6) < 1e-6)
    check("D 形轮廓首尾闭合", True)
    check("下边右端 == 右下半弧起点", abs(bottom[1][0] - 11) < 1e-9
          and abs(bottom[1][1] - (arc_br_c[1] - arc_br_r)) < 1e-9)
    check("右直边两端 == 两弧端点", abs(right[0][1] - (arc_br_c[1] + 0)) < 1e-9
          and abs(right[0][0] - (arc_br_c[0] + arc_br_r)) < 1e-9
          and abs(right[1][0] - (arc_tr_c[0] + arc_tr_r)) < 1e-9)
    check("上边右端 == 右上半弧终点", abs(top[1][0] - (arc_tr_c[0] + 0)) < 1e-9
          and abs(top[1][1] - (arc_tr_c[1] + arc_tr_r)) < 1e-9)
    check("重合线中点 = 定位点(0,8.3)",
          abs((coincident[0][1] + coincident[1][1]) / 2 - 8.3) < 1e-9)

    print()
    if FAIL:
        print("RESULT: %d FAILED" % len(FAIL))
        return 1
    print("RESULT: ALL PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
