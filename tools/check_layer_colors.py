#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图层配色门禁(零依赖): 扫描 scripts/*.lsp 的图层色登记, 断言三条:

  A. 一致性 —— 同一图层在所有脚本中的登记色必须同值
     (flb 预建表 / wx 出图层 / cx 内联建层 分头写色, 防漂移);
  B. 唯一性 —— 不允许两个图层共用同一 ACI 色号;
  C. 区分度 —— 任意两色 CIE Lab 色差 dE >= 30
     (v10.11/flb + v9.34/jrt + v11.8/cx + v2.11/wx 配色重排口径:
      现状曾有 5 对图层完全同色, 重排后全 21 色两两最小 dE=31.3).

扫描规则(只认数字字面量, 变量传色天然跳过):
  a. ensure 登记表行:        (list "层名" 色号 "中文名")
  b. ensure 直接调用:        dt:ensure-layer <layers> "层名" 色号
  c. wx 出图层:              dt:sz-ensure-doc-layer <doc> "层名" 色号
  d. cx 内联建层:            (tblsearch "LAYER" "层名") 后 6 行内的
                             (vla-put-color lay 色号)
  e. 实体级颜色字面量:       (vla-put-color <obj> 色号) —— 色号必须在
                             登记色号集合内(防止旁路硬编码旧色).

登记基准 EXPECTED = 21 层; 扫到基准外的 层名/色号 组合即报错
(新图层/改色须先更新本表再过门禁).

退出码: 全部通过=0, 任一失败=1(逐条列出).
"""
import math
import re
import sys
from pathlib import Path

from _aci_colors import ACI_RGB

MIN_DE = 30.0

# 21 层登记基准(v10.11/flb 预建表为单一来源, 其他脚本必须与之一致)
EXPECTED = {
    'LD': 7, 'FLB': 1, 'FBX': 3, 'LS': 4, 'JT': 6, 'JTFBX': 230,
    'RZ': 30, 'DK': 8, 'DP': 5, 'CX': 161, 'CXK': 122,
    'JRT': 2, 'JRTDW': 61, 'JRTFBX': 21, 'ZJJ': 193,
    'FLB_BOX': 42, '数据图纸': 63, 'JD': 101, '外协文字': 144,
    '外协包络盒': 222, 'YXB': 84,
}

# cx 内联建层的 tblsearch+put-color 窗口行数
CXK_WINDOW = 6


def lab(rgb):
    def f(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in rgb)
    x = (0.4360747 * r + 0.3850649 * g + 0.1430804 * b) / 0.95047
    y = (0.2136537 * r + 0.6153983 * g + 0.1474997 * b)
    z = (0.0179971 * r + 0.1191948 * g + 0.9225022 * b) / 1.08883

    def t(v):
        return v ** (1 / 3) if v > 0.008856 else 7.787 * v + 16 / 116
    fx, fy, fz = t(x), t(y), t(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def dE(c1, c2):
    return math.dist(lab(c1), lab(c2))


def aci_rgb(aci):
    v = ACI_RGB[aci]
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def scan_lsp(path):
    """返回 [(层名, 色号, 行号)] 与 [put-color 数字字面量(色号, 行号)]."""
    text = path.read_text(encoding='utf-8-sig')
    lines = text.splitlines()
    found, literals = [], []
    pat_list = re.compile(r'\(list\s+"([^"]+)"\s+(\d+)\s+"')
    pat_direct = re.compile(r'dt:ensure-layer\s+.+?"([^"]+)"\s+(\d+)')
    pat_doc = re.compile(r'dt:sz-ensure-doc-layer\s+\S+\s+"([^"]+)"\s+(\d+)')
    pat_put = re.compile(r'\(vla-put-color\s+(\S+)\s+(\d+)\)')
    pat_tbl = re.compile(r'\(tblsearch "LAYER" "([^"]+)"\)')
    for i, ln in enumerate(lines):
        for m in pat_list.finditer(ln):
            found.append((m.group(1), int(m.group(2)), i + 1))
        for m in pat_direct.finditer(ln):
            found.append((m.group(1), int(m.group(2)), i + 1))
        for m in pat_doc.finditer(ln):
            found.append((m.group(1), int(m.group(2)), i + 1))
        for m in pat_put.finditer(ln):
            literals.append((int(m.group(2)), i + 1))
        for m in pat_tbl.finditer(ln):
            name = m.group(1)
            for j in range(i + 1, min(i + 1 + CXK_WINDOW, len(lines))):
                pm = pat_put.search(lines[j])
                if pm:
                    found.append((name, int(pm.group(2)), j + 1))
                    break
    return found, literals


def main():
    scripts = sorted(Path(__file__).resolve().parent.parent.glob('scripts/*.lsp'))
    if not scripts:
        print('未找到 scripts/*.lsp')
        return 1
    fails = []

    # A. 逐点比对登记基准
    reg = {}
    for path in scripts:
        found, _ = scan_lsp(path)
        for name, aci, lineno in found:
            key = (path.name, name)
            reg.setdefault(name, []).append((aci, path.name, lineno))
            if name in EXPECTED:
                if aci != EXPECTED[name]:
                    fails.append('A. %s:%d 图层 "%s" 色号 %d != 登记值 %d'
                                 % (path.name, lineno, name, aci, EXPECTED[name]))
            else:
                fails.append('A. %s:%d 出现基准外图层 "%s"(色号 %d), '
                             '请更新 check_layer_colors.py 的 EXPECTED'
                             % (path.name, lineno, name, aci))
    for name, rows in sorted(reg.items()):
        acis = {r[0] for r in rows}
        if len(acis) > 1:
            fails.append('A. 图层 "%s" 多脚本登记色不一致: %s'
                         % (name, sorted((a, f) for a, f, _ in rows)))

    # B. 唯一性
    used = {}
    for name, aci in EXPECTED.items():
        used.setdefault(aci, []).append(name)
    for aci, names in sorted(used.items()):
        if len(names) > 1:
            fails.append('B. 色号 %d 被多图层共用: %s' % (aci, names))

    # C. 两两色差
    acis = sorted(EXPECTED.values())
    weak = []
    for i, a in enumerate(acis):
        for b in acis[i + 1:]:
            d = dE(aci_rgb(a), aci_rgb(b))
            if d < MIN_DE:
                weak.append((round(d, 1), a, b))
    if weak:
        fails.append('C. 色差不足 %s 的组合: %s'
                     % (MIN_DE, sorted(weak)[:10]))

    # D. put-color 数字字面量必须落在登记色号集合内
    known = set(EXPECTED.values())
    for path in scripts:
        _, literals = scan_lsp(path)
        for aci, lineno in literals:
            if aci not in known:
                fails.append('D. %s:%d (vla-put-color ...) 用了登记外色号 %d'
                             % (path.name, lineno, aci))

    worst = min((dE(aci_rgb(a), aci_rgb(b)) for x, a in enumerate(acis)
                 for b in acis[x + 1:]), default=0)
    print('图层 %d 个, 色号 %d 个, 两两最小 dE=%.1f' %
          (len(EXPECTED), len(acis), worst))
    if fails:
        print('== FAIL')
        for m in fails:
            print('  ' + m)
        return 1
    print('== ALL OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
