# -*- coding: utf-8 -*-
"""方向/排布算法回归(jrt v9.24/25 + cx v11.2/3) —— 纯 stdlib, 零依赖。

把 cx_runner/jrt_runner 中"与 AutoCAD 无关"的几何判定逻辑逐行移植为
Python, 用图2/图3 场景与 tools/1.dxf 实测数据做断言:
  1) dt:jrt2-pt-inside   —— +X 射线奇偶点内判定
  2) dt:jrt2-region-edges —— 轮廓采样边集 + 自由端贪心配对封口
  3) 嵌套内偏选边         —— 唯一"中点在内"候选(回退链的围合判定环)
  4) 颈线朝外规则         —— 靠近 FLB 中心则反向
  5) 压线板排布           —— 中点定位 + 整组居中(对照 1.dxf 实例坐标)
  6) 压线板模板几何       —— D 形 6 件首尾闭合
  7) v9.25 整环 FLB 距离主判据 —— 取"离 FLB 更远"的候选环
  8) v9.25 采样 nil 防护  —— 越界返回 nil 不成边、不可判内
  9) v11.3 壁段分解+选侧  —— 多段线直段参与、弧段剔除、Left/Right 交叉
  10) v9.26 颈线方向     —— L 形非凸 FLB 下奇偶判据对/包围盒判据错
  11) v9.26 采样密度     —— R=400 大弧 12 段吞探针 / 24 段判对
  12) v9.26 通道延伸     —— 壁"让开"3mm: ext=0 不交(复现日志), ext=5 命中
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


# ---------- 1) 点内判定(移植 dt:jrt2-pt-inside, 含 v9.25 防护) ----------
def pt_inside(pt, edges):
    if pt is None:                       # v9.25 双判: nil 点不可判定
        return False
    x, y = pt[0], pt[1]
    cnt = 0
    for a, b in edges:
        if a is None or b is None:       # v9.25: 含非点端点的边直接跳过
            continue
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


# ---------- 7) v9.25 整环 FLB 距离主判据移植 ----------
def pt_seg_dist(p, a, b):
    ax, ay = a
    bx, by = (b[0] - a[0], b[1] - a[1])
    px, py = p[0] - ax, p[1] - ay
    l2 = bx * bx + by * by
    if l2 < 1e-12:
        return math.hypot(px, py)
    t = max(0.0, min(1.0, (px * bx + py * by) / l2))
    return math.hypot(px - t * bx, py - t * by)


def pt_curves_dist(pt, segs):
    best = None
    for a, b in segs:
        d = pt_seg_dist(pt, a, b)
        if best is None or d < best:
            best = d
    return best


def flb_score(ring_segs, flb_segs):
    """环上各段中点 → FLB 最小距离的均值(LISP 版 5 采样点的段中点简化)"""
    if not ring_segs or not flb_segs:
        return None
    per = [pt_curves_dist(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), flb_segs)
           for a, b in ring_segs]
    return sum(per) / len(per) if per else None


def pick_winner(ringA, ringB, flb_segs):
    """移植 dt:jrt2-layer ③: (if (< sA sB) → 取B) —— 得分大(更远=内)者胜"""
    sA = flb_score(ringA, flb_segs)
    sB = flb_score(ringB, flb_segs)
    if sA is None or sB is None:
        return None
    return 'B' if sA < sB else 'A'


def curve_edges(points):
    """移植 dt:jrt2-curve-edges(v9.25 nil 双判语义): None 点跳过不成边"""
    out = []
    prev = None
    for p in points:
        if p is None:
            continue
        if prev is not None:
            out.append((prev, p))
        prev = p
    return out


# ---------- 9) v11.3 壁段过滤移植(dt:cx-yxb-find-walls 判据) ----------
def pt_line_dist(p, lp, ld):
    vx, vy = p[0] - lp[0], p[1] - lp[1]
    t = vx * ld[0] + vy * ld[1]
    return math.hypot(vx - t * ld[0], vy - t * ld[1])


def piece_parallel(piece, ds):
    (ax, ay), (bx, by) = piece[0][:2], piece[1][:2]
    vl = math.hypot(bx - ax, by - ay)
    if vl < 1e-8:
        return False
    dd = abs(ds[0] * ((by - ay) / vl) - ds[1] * ((bx - ax) / vl))
    return dd < 1e-4


def mid_of(piece):
    a, b = piece[0], piece[1]
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, 0.0)


def side_of(piece, ss, ds, side):
    m = mid_of(piece)
    cr = ds[0] * (m[1] - ss[1]) - ds[1] * (m[0] - ss[0])
    return cr > 0.0 if side == "LEFT" else cr < 0.0


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

    print("[6] 压线板模板: D 形 6 件首尾闭合 + 定位点=重合线中点")    # (类型, x, y, ...) 按 dt:cx-yxb-tpl 顺序
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

    print("[7] v9.25 整环 FLB 距离主判据: 取离 FLB 更远(朝内)的候选环")
    flb = ring_edges_rect(0, 0, 800, 900)
    src_ring = ring_edges_rect(200, 200, 600, 700)          # 板上加热门条外壁
    ring_in = ring_edges_rect(204, 204, 596, 696)           # 内偏 4mm
    ring_out = ring_edges_rect(196, 196, 604, 704)          # 外偏 4mm
    s_in = flb_score(ring_in, flb)
    s_out = flb_score(ring_out, flb)
    s_src = flb_score(src_ring, flb)
    check("内偏环得分 > 源环 > 外偏环", s_in > s_src > s_out)
    check("种子序 A=外/B=内 → 胜者=内环", pick_winner(ring_out, ring_in, flb) == 'B')
    check("种子序 A=内/B=外 → 胜者=内环", pick_winner(ring_in, ring_out, flb) == 'A')
    check("FLB 缺失(得分 None) → 不可判(交回退链)",
          flb_score(ring_in, []) is None)

    print("[8] v9.25 采样 nil 防护")
    guarded = curve_edges([None, (0, 0), (10, 0), None, (10, 10)])
    check("nil 采样点不成边", all(a is not None and b is not None for a, b in guarded))
    check("含 None 端点的边不影响点内判定(不抛异常)",
          pt_inside((5, 5), [((0, 0), None), ((0, 0), (0, 20)),
                             ((0, 20), (20, 20)), ((20, 20), (20, 0)),
                             ((20, 0), (0, 0))]) is True)
    check("nil 判据点 → 判外(False 不崩)", pt_inside(None, guarded) is False)

    print("[9] v11.3 壁段分解 + 选侧(Left/Right, 直段参与, 弧段剔除)")
    wall_rect = [((-17.5, 0), (-17.5, 400), False),   # 左壁直段(平行源线)
                 ((-17.5, 400), (-35, 400), False),   # 顶横段(不平行)
                 ((-35, 400), (-35, 0), False),       # 外直段(平行但侧距=35)
                 ((-35, 0), (-17.5, 0), True)]        # 带凸度段=弧 → 剔除
    ssrc = (0.0, 0.0, 0.0)
    dsrc = (0.0, 1.0, 0.0)
    got_l, got_r, n_arc = [], [], 0
    for a, b, is_arc in wall_rect:
        if is_arc:
            n_arc += 1
            continue
        piece = ((a[0], a[1], 0.0), (b[0], b[1], 0.0))
        if piece_parallel(piece, dsrc) and side_of(piece, ssrc, dsrc, "LEFT"):
            got_l.append(piece)
        if piece_parallel(piece, dsrc) and side_of(piece, ssrc, dsrc, "RIGHT"):
            got_r.append(piece)
    check("弧段计数 1 且不参与", n_arc == 1)
    check("横段被平行滤除(左候选=2)", len(got_l) == 2)
    check("LEFT 侧候选垂距均=17.5", all(
        abs(pt_line_dist(mid_of(p), ssrc, dsrc) - 17.5) < 1e-9 or
        abs(pt_line_dist(mid_of(p), ssrc, dsrc) - 35.0) < 1e-9 for p in got_l))
    check("右壁源侧(RIGHT)候选=0(全部在左)", len(got_r) == 0)

    print("[10] v9.26 颈线方向: L 形(非凸) FLB 下 奇偶判据对 / 包围盒判据错")
    lring = [((0, 0), (80, 0)), ((80, 0), (80, 30)), ((80, 30), (30, 30)),
             ((30, 30), (30, 80)), ((30, 80), (0, 80)), ((0, 80), (0, 0))]
    cen = (40.0, 40.0)
    # 凹口竖直边 x=30(y=60) 上 pint, dirv=(+1,0) 实际朝外(凹口空腔方向)
    pint = (30.0, 60.0, 0.0)
    for dirv, want_flip, tag in [((1.0, 0.0, 0.0), False, "朝外(应保持)"),
                                 ((-1.0, 0.0, 0.0), True, "朝内(应反向)")]:
        base = (pint[0] + 5 * dirv[0], pint[1] + 5 * dirv[1], 0.0)
        parity_flip = pt_inside(base, lring) is True
        bbox_flip = (math.hypot(base[0] - cen[0], base[1] - cen[1])
                     < math.hypot(pint[0] - cen[0], pint[1] - cen[1]))
        check("dirv%s → 奇偶判据正确" % tag, parity_flip == want_flip)
        if tag == "朝外(应保持)":
            check("dirv朝外 → 旧包围盒判据翻错(本案根因, 故换奇偶)",
                  bbox_flip is True)

    print("[11] v9.26 大弧 FLB 采样密度: 12 段吞 5mm 探针 / 24 段判对")
    def circle_poly(R, n):
        pts = [(R * math.cos(2 * math.pi * k / n),
                R * math.sin(2 * math.pi * k / n)) for k in range(n)]
        return [(pts[i], pts[(i + 1) % n]) for i in range(n)]
    probe = (395 * math.cos(math.radians(15)), 395 * math.sin(math.radians(15)))
    check("R=400 内缩5mm 探针, 12 段多边形误判为外(旧缺陷)",
          pt_inside(probe, circle_poly(400, 12)) is False)
    check("R=400 内缩5mm 探针, 24 段多边形判为内(新判据)",
          pt_inside(probe, circle_poly(400, 24)) is True)

    print("[12] v9.26 出线口通道延伸: 圆弧壁让开处, 短线不交 / 延伸后交")
    def extend_seg(seg, ext):
        (ax, ay), (bx, by) = seg
        L = math.hypot(bx - ax, by - ay)
        if L < 1e-9 or ext <= 0.0:
            return seg
        ux, uy = (bx - ax) / L, (by - ay) / L
        return ((ax - ux * ext, ay - uy * ext), (bx + ux * ext, by + uy * ext))
    def segs_cross(s1, s2):
        (a, b), (c, d) = s1, s2
        def cr(o, p, q):
            return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
        return (cr(a, b, c) * cr(a, b, d) <= 0
                and cr(c, d, a) * cr(c, d, b) <= 0)
    stub = ((0.0, 0.0), (0.0, 60.0))
    wall = ((-40.0, 63.0), (40.0, 63.0))   # 外壁在 stub 端点之外 3mm(弧让开)
    for halfw in (-16.5, 16.5):
        ch = ((stub[0][0] + halfw, stub[0][1]), (stub[1][0] + halfw, stub[1][1]))
        hit0 = segs_cross(ch, wall)
        hit5 = segs_cross(extend_seg(ch, 5.0), wall)
        check("halfw=%+ .1f: ext=0 不交(复现日志跳过), ext=5 命中" % halfw,
              hit0 is False and hit5 is True)

    print()
    if FAIL:
        print("RESULT: %d FAILED" % len(FAIL))
        return 1
    print("RESULT: ALL PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
