# 门禁新增: defun 顶层定义检查(坑 #73) —— 每个 defun 行"开始时"的括号深度必须为 0
# (defun 是多行表达式, 行"结束"时深度 +1 属正常; 行"开始"时深度 >0 = 嵌套在
#  别的表达式内部, 加载时永不定义为全局函数 —— 字符串匹配型检查测不出此症)
# 用法: python tools/check_defun_depth.py [文件...]; 无参时检查 scripts/ 全部 .lsp
import os
import sys

BS = chr(92)


def scan(path):
    with open(path, 'rb') as f:
        src = f.read().decode('utf-8-sig', 'replace')
    bal = 0
    in_str = in_com = esc = False
    ln = 0
    bad = []
    for line in src.split('\n'):
        ln += 1
        start_bal = bal                      # 行开始时的深度
        for ch in line:
            if in_com:
                continue
            if in_str:
                if esc:
                    esc = False
                elif ch == BS:
                    esc = True
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
        in_com = False
        esc = False
        s = line.strip()
        if (s.startswith('(defun') and start_bal != 0
                and not s.startswith('(defun *error*')):  # 局部错误处理器惯用法, 豁免
            bad.append((ln, start_bal, s[:56]))
    return bad


def main():
    args = sys.argv[1:]
    if not args:
        here = os.path.dirname(os.path.abspath(__file__))
        d = os.path.normpath(os.path.join(here, '..', 'scripts'))
        args = sorted(os.path.join(d, f) for f in os.listdir(d) if f.lower().endswith('.lsp'))
    total = 0
    for path in args:
        bad = scan(path)
        name = os.path.basename(path)
        if bad:
            print('%-22s %d 个 defun 未定义在顶层:' % (name, len(bad)))
            for ln, bal, txt in bad[:10]:
                print('    L%d 深度=%d  %s' % (ln, bal, txt))
            total += len(bad)
        else:
            print('%-22s 全部 defun 顶层定义 OK' % name)
    print('结果:', 'ALL OK' if total == 0 else '存在 %d 个嵌套 defun' % total)
    sys.exit(0 if total == 0 else 1)


if __name__ == '__main__':
    main()
