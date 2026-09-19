#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""deploy_old_pc.py —— 一键生成「老旧电脑（AutoCAD 2007~2020）」移植包。

用法（在仓库根目录）：
    python tools/deploy_old_pc.py                # 生成到 deploy/ 并打包 zip
    python tools/deploy_old_pc.py --out D:\\pkg   # 指定输出目录
    python tools/deploy_old_pc.py --check         # 只自检，不写盘
    python tools/deploy_old_pc.py --no-zip        # 不打包 zip

产出（默认 deploy\\HYT-CAD-老机版\\）：
    dt_start.lsp / flb_runner.lsp / cx_runner.lsp / jrt_runner.lsp
    wx_runner.lsp / demo_recorder.lsp   —— 6 个 GBK(ANSI) 编码脚本，逐字节取自 scripts_ansi\\
    wx_runner.ini                        —— 出图目录配置模板（GBK，root 默认注释掉）
    install.bat                          —— 老电脑上一键安装（GBK + CRLF）
    使用说明.txt                          —— 一页纸说明（GBK + CRLF）
    manifest.txt                         —— 文件名 + 字节数（供 install.bat 校验拷贝完整性）

设计约束（与项目契约一致）：
    * 纯 Python 3 标准库，零第三方依赖；
    * 生成前强制跑 `tools/make_ansi.py --check`，保证 scripts_ansi\\ 与 scripts\\ 同源，
      避免把过期/未生成的 GBK 副本打包出去；
    * 只做「让老机器能用」的最小集：不含 tools\\、不含文档、不含 ini/dcl/mem 运行生成物。

退出码：0 = 成功；1 = 前置校验或写盘失败（错误信息含上下文）。
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile

# 打包的 6 个脚本（老机器一律用 GBK 副本）
SCRIPTS = [
    "dt_start.lsp",
    "flb_runner.lsp",
    "cx_runner.lsp",
    "jrt_runner.lsp",
    "wx_runner.lsp",
    "demo_recorder.lsp",
]

# 版本串提取规则（顺序即打印顺序；None 表示无版本常量的文件用备用正则）
VERSION_PATTERNS = {
    "dt_start.lsp": r'dt:st-version\s+"([^"]+)"',
    "flb_runner.lsp": r'\*dt-flb-ver\*\s+"([^"]+)"',
    "cx_runner.lsp": r'\*dt-cx-ver\*\s+"([^"]+)"',
    "jrt_runner.lsp": r'\*dt-jrt-ver\*\s+"([^"]+)"',
    "wx_runner.lsp": r'\*dt-wx-ver\*\s+"([^"]+)"',
    "demo_recorder.lsp": r'(?m)^;;;\s*(v\d+\.\d+)',
}

PKG_NAME = "HYT-CAD-老机版"

WX_INI = """; wx_runner.ini —— 外协加工配置(记事本可改, 保存必须保持 ANSI 编码)
; 保存成 UTF-8 会导致中文节名 [线切割]/[精雕] 匹配失败、配置静默失效。
; 本文件只被脚本读取, 脚本不回写; 删掉本文件 = 回代码内置默认。
; 不配 root 时的默认出图落点: 我的文档\\CAD\\线切割 与 我的文档\\CAD\\精雕

[线切割]
; 出图根目录, 把下面这行开头的分号去掉再改成实际路径(盘符必须真实存在)
; root = D:\\CAD出图\\线切割

[精雕]
; root = D:\\CAD出图\\精雕

[测量加热条]
; 测量加热条长度 JRTSZ 专用: 归堆间距(mm), 两线最小间距<=此值算同一根加热条
strip_gap = 15.0

[排版]
; 外协出图排版(线切割/精雕共用)
box_gap = 100.0
per_row = 4
text_gap = 50.0
box_margin = 20.0
"""

INSTALL_BAT = r"""@echo off
chcp 936 >nul 2>nul
setlocal enabledelayedexpansion
title HYT-CAD 老电脑一键移植

set "SRC=%~dp0"
set "PF86=%ProgramFiles(x86)%"
set "DST=%~1"
set "MODE="
if /i "%~1"=="--check" (set "DST=%SystemDrive%\HYTCAD" & set "MODE=check")
if "%DST%"=="" set "DST=%SystemDrive%\HYTCAD"
if /i "%~2"=="--check" set "MODE=check"

echo ================================================
echo   HYT-CAD 老电脑移植  (AutoCAD 2007~2020 完整版)
echo ================================================
echo   源目录  : %SRC%
echo   目标目录: %DST%
echo.

rem ---------- 1. 建立目标目录 ----------
if not exist "%DST%" mkdir "%DST%"
if not exist "%DST%" (echo [失败] 无法创建目录 %DST% & goto :fail)

rem ---------- 2. 复制 6 个 GBK 脚本 ----------
set /a N=0
for %%F in (dt_start.lsp flb_runner.lsp cx_runner.lsp jrt_runner.lsp wx_runner.lsp demo_recorder.lsp) do (
  if not exist "%SRC%%%F" (echo [失败] 源文件缺失: %%F & goto :fail)
  copy /y "%SRC%%%F" "%DST%\%%F" >nul
  if errorlevel 1 (echo [失败] 复制失败: %%F & goto :fail)
  set /a N+=1
)
echo [1/4] 已复制 !N! 个 .lsp 到 %DST%

rem ---------- 3. 字节数校验(防 U 盘拷贝不完整) ----------
set /a BAD=0
if exist "%SRC%manifest.txt" (
  for /f "usebackq tokens=1,2" %%A in ("%SRC%manifest.txt") do (
    set "SZ="
    for %%F in ("%DST%\%%A") do set "SZ=%%~zF"
    if not "!SZ!"=="%%B" (echo [失败] 字节数不符: %%A 实际 !SZ! 应为 %%B & set /a BAD+=1)
  )
)
if !BAD! GTR 0 goto :fail
echo [2/4] 字节数校验通过

rem ---------- 4. 出图配置(已存在就不覆盖, 保留原配置) ----------
if exist "%DST%\wx_runner.ini" (
  echo [3/4] wx_runner.ini 已存在, 保留原配置
) else (
  if exist "%SRC%wx_runner.ini" copy /y "%SRC%wx_runner.ini" "%DST%\wx_runner.ini" >nul
  echo [3/4] 已放入 wx_runner.ini(出图目录, 按需改, 保存保持 ANSI 编码)
)

rem ---------- 5. 生成 AutoCAD 安装脚本 ----------
set "FWD=%DST:\=/%"
> "%DST%\install.scr" echo (load "%FWD%/dt_start.lsp")
>>"%DST%\install.scr" echo (c:DTINSTALL)
echo [4/4] 已生成 %DST%\install.scr

if defined MODE goto :manual

rem ---------- 6. 找 acad.exe 并自动执行安装 ----------
set "ACAD="
for /d %%P in ("%ProgramFiles%\Autodesk\AutoCAD*") do if exist "%%~fP\acad.exe" set "ACAD=%%~fP\acad.exe"
if defined PF86 for /d %%P in ("%PF86%\Autodesk\AutoCAD*") do if exist "%%~fP\acad.exe" set "ACAD=%%~fP\acad.exe"
rem 精简版常装在自定目录: 各盘符一级目录兜底扫描(浅层, 秒级)
if not defined ACAD for %%D in (C D E F) do if exist "%%D:\" for /d %%P in ("%%D:\*") do if exist "%%~fP\acad.exe" set "ACAD=%%~fP\acad.exe"
if not defined ACAD goto :manual

echo.
echo 找到 AutoCAD: !ACAD!
echo 正在启动 AutoCAD 并自动执行 DTINSTALL ...
start "" "!ACAD!" /b "%DST%\install.scr"
echo.
echo 请看 CAD 命令行的输出, 出现下面这句就算成功:
echo    【安装】完成: 钩子已写入 acaddoc.lsp(含确定性目录注入), 目录已加入支持/受信任路径。
echo 然后完全关掉 CAD 再打开, 顶栏应自动出现「热流道自动化(R)」菜单。
echo.
echo 注意: 若以前把脚本拷到过其它目录, 开机时命令行还报旧路径的错误,
echo       是开机钩子还指着旧目录 —— CAD 里运行 DTUNINSTALL 再 DTINSTALL 即可改写。
goto :done

:manual
echo.
echo 未自动执行安装(没找到 acad.exe 或用了 --check)。请手工两步:
echo   1) 打开 AutoCAD, 命令行输 APPLOAD, 选 %DST%\dt_start.lsp, 点「加载」
echo   2) 命令行输 DTINSTALL 回车
echo   或者在 CAD 命令行输 SCRIPT, 选 %DST%\install.scr, 一次跑完这两步。
echo.
echo 成功标志: 出现「【安装】完成: 钩子已写入 acaddoc.lsp ...」
echo 之后完全关掉 CAD 再打开, 顶栏应自动出现「热流道自动化(R)」菜单。
echo 卸载: CAD 命令行输 DTUNINSTALL, 再删掉 %DST% 目录。
goto :done

:fail
echo.
echo 安装中断, 请把上面的失败信息发给维护者。
endlocal
pause
exit /b 1

:done
echo.
echo 本窗口可以关闭了。
endlocal
pause
exit /b 0
"""

USAGE_TXT = """HYT-CAD 老电脑移植包 —— 使用说明
================================================================
适用: AutoCAD 2007 ~ 2020 完整版(不能是 AutoCAD LT, LT 没有 COM 接口)。
不需要装 Python / .NET / 插件。目录里这 6 个 .lsp 就是全部运行文件。

一、装(只做一次)
  1. 把这个文件夹整个拷到老电脑, 建议放纯英文短路径, 例如 D:\\HYTCAD\\
     (中文路径下老 CAD 的文件读写偶发失败, 避开最省事)
  2. 双击 install.bat
       - 它会自动拷文件、校验字节数、生成安装脚本, 并尝试启动 AutoCAD
         自动执行 DTINSTALL;
       - 也可指定目录:   install.bat  D:\\HYTCAD
       - 只放文件不碰 CAD: install.bat  D:\\HYTCAD  --check
  3. 若没自动执行安装, 按屏幕提示手工两步:
       打开 CAD -> 命令行输 APPLOAD -> 选 <目标目录>\\dt_start.lsp -> 「加载」
       命令行输 DTINSTALL 回车
  4. 看到「【安装】完成: 钩子已写入 acaddoc.lsp ...」就成功了。
     完全关掉 CAD 再打开, 顶栏应自动出现「热流道自动化(R)」菜单。

二、验收(逐条过)
  DTDBG       诊断, 看输出开头的 [0z] 段(ACADVER / 系统变量可用性 / acaddoc 落点)
  FLBPARAM    分流板参数框        CXPARAM   出线槽参数框      JRTPARAM  加热条参数框
  关上 CAD 再开 -> 菜单自动出现(这才证明自启动生效)

三、出图目录(想改再改, 不改也能用)
  默认落到: 我的文档\\CAD\\线切割  与  我的文档\\CAD\\精雕
  要改: 记事本打开目标目录里的 wx_runner.ini, 改 [线切割]/[精雕] 下的 root 两行,
  保存时必须选 ANSI 编码(选 UTF-8 会导致中文节名匹配失败、配置静默失效)。
  盘符写错不会报错, 会自动退回「我的文档\\CAD\\」。

四、日常使用
  顶栏「热流道自动化(&R)」菜单顺序: 分流板 / 加热条 / 出线槽 / 外协加工 / 工具 / 关于
  源线: 分流板/假体/加热条画在 LD 层; 出线槽画在 CX 层; 垫片(可选)画在 DP 层
  分流板 FLB  -> 选模板[通用/矩形] -> 参数框 -> 全自动
  加热条 JRT  -> 选模板[通用一/通用二] -> 参数框 -> 全自动
  出线槽 CX   -> 参数框 -> 选压线板贴壁侧 -> 全自动
  测量   FLBSZ(分流板) / JRTSZ(加热条长度) -> 结果写剪贴板
  外协   XQG(线切割) / JD(精雕) / SJTZ(数据图纸)
  换版本 DTRELOAD      卸载 DTUNINSTALL      诊断 DTDBG

五、正常现象, 不用管
  * 安装时打印「TRUSTEDPATHS=无(老版本, 跳过)」—— 该安全机制 AutoCAD 2016 才有。
  * 对话框是经典样式, 不是 Ribbon 面板。

六、出问题怎么查
  加载就报「错误: 输入中的点位置不正确」
      用的是 UTF-8 版脚本。本包全部是 GBK 编码, 别拿 scripts\\ 里的原版替换。
  DTINSTALL 报「参数类型错误: stringp nil」且中断
      dt_start.lsp 是 v2.9 之前的老版本, 换成包里这份。
  敲命令报「no function definition: XXX」
      脚本半加载 —— 完全关闭 CAD 重开; 还不行敲 DTRELOAD。
  顶栏菜单不出现
      敲 DTRELOAD 重挂; 仍不行重启 CAD, 把命令行输出发给维护者。
  参数框弹不出来
      目标目录只读, .dcl 生成失败(脚本会退回 TEMP)。确认目录可写。
  重开 CAD 没菜单(自启动没生效)
      acaddoc.lsp 写失败(权限/杀软)。用管理员权限重跑 install.bat 或 DTINSTALL。
  出图跑到别处去了
      wx_runner.ini 的 root 盘符在老电脑上不存在, 自动降级到我的文档。
  排查通用动作: 敲 DTDBG, 把命令行全部输出发给维护者。

七、卸载
  CAD 命令行输 DTUNINSTALL(摘菜单 + 删 acaddoc.lsp 钩子 + 移出支持路径),
  然后删掉目标目录(例如 D:\\HYTCAD)。

八、红线
  * 老电脑上只留一份 dt_start.lsp —— 别处再放一份, 自启动会认错目录。
  * 别把 UTF-8 版(scripts\\)和 GBK 版混在同一目录, 混了必报加载错误。
  * 一台机器装多个 AutoCAD 版本时, 每个版本各自 APPLOAD + DTINSTALL 一次,
    脚本目录共用一份即可。
  * 别手工改 .lsp 的编码(记事本另存会偷偷改编码, 一改就废)。

本包由开发机 `python tools/deploy_old_pc.py` 生成, 每次改完脚本都要重新生成。
"""


def repo_root():
    """仓库根目录（本文件位于 <root>/tools/ 下）。"""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_text_utf8_bom(path):
    """读 UTF-8(可带 BOM) 文本；文件不存在抛 FileNotFoundError 由调用方处理。"""
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8-sig")


def extract_version(text, fname):
    pat = VERSION_PATTERNS.get(fname)
    if not pat:
        return "?"
    m = re.search(pat, text)
    return m.group(1) if m else "?"


def run_ansi_check(root):
    """跑 make_ansi.py --check，保证 scripts_ansi 与 scripts 同源。返回 (ok, 输出)。"""
    tool = os.path.join(root, "tools", "make_ansi.py")
    if not os.path.isfile(tool):
        return False, "找不到 %s" % tool
    proc = subprocess.run([sys.executable, tool, "--check"],
                          cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = proc.stdout.decode("utf-8", "replace").strip()
    return proc.returncode == 0, out


def build(root, out_dir, make_zip=True, check_only=False):
    src_dir = os.path.join(root, "scripts_ansi")
    if not os.path.isdir(src_dir):
        print("[失败] 找不到 GBK 副本目录：%s" % src_dir)
        return 1

    ok, out = run_ansi_check(root)
    print("== 前置校验：tools/make_ansi.py --check ==")
    print(out or "(无输出)")
    if not ok:
        print("\n[失败] scripts_ansi 与 scripts 不同源（见上方输出）。"
              "先跑 `python tools/make_ansi.py` 重新生成 GBK 副本再打包。")
        return 1
    print()

    # 逐个校验源文件存在 + 可 GBK 解码 + 取版本号
    plan = []
    for name in SCRIPTS:
        path = os.path.join(src_dir, name)
        if not os.path.isfile(path):
            print("[失败] 缺少源文件：%s" % path)
            return 1
        with open(path, "rb") as fh:
            data = fh.read()
        try:
            data.decode("gbk")
        except UnicodeDecodeError as exc:
            print("[失败] %s 不是合法 GBK：%s" % (name, exc))
            return 1
        ver = extract_version(data.decode("gbk"), name)
        plan.append((name, len(data), ver))

    print("== 待打包（全部 GBK 编码）==")
    for name, size, ver in plan:
        print("   %-20s %7d 字节   版本 %s" % (name, size, ver))
    print()

    if check_only:
        print("--check：仅自检，未写盘。")
        return 0

    pkg_dir = os.path.join(out_dir, PKG_NAME)
    if os.path.isdir(pkg_dir):
        shutil.rmtree(pkg_dir)
    os.makedirs(pkg_dir)

    for name, size, _ in plan:
        shutil.copyfile(os.path.join(src_dir, name), os.path.join(pkg_dir, name))

    manifest = "".join("%s %d\n" % (name, size) for name, size, _ in plan)

    # 文本文件一律 GBK + CRLF（老 Windows 记事本 / cmd 才认）
    texts = [
        ("wx_runner.ini", WX_INI),
        ("install.bat", INSTALL_BAT),
        ("使用说明.txt", USAGE_TXT),
        ("manifest.txt", manifest),
    ]
    for name, content in texts:
        path = os.path.join(pkg_dir, name)
        try:
            data = content.replace("\n", "\r\n").encode("gbk")
        except UnicodeEncodeError as exc:
            print("[失败] %s 无法用 GBK 编码：%s" % (name, exc))
            return 1
        with open(path, "wb") as fh:
            fh.write(data)

    # 写盘后逐文件复核：脚本字节一致、文本可 GBK 回读
    print("== 写盘复核 ==")
    for name, size, _ in plan:
        with open(os.path.join(pkg_dir, name), "rb") as fh:
            packed = fh.read()
        with open(os.path.join(src_dir, name), "rb") as fh:
            origin = fh.read()
        if packed != origin:
            print("[失败] %s 打包后与源不一致" % name)
            return 1
    for name, content in texts:
        with open(os.path.join(pkg_dir, name), "rb") as fh:
            back = fh.read().decode("gbk")
        if back.replace("\r\n", "\n") != content:
            print("[失败] %s 回读不一致" % name)
            return 1
    print("   6 个 .lsp 与 scripts_ansi 逐字节一致；4 个文本 GBK 回读一致")

    zip_path = None
    if make_zip:
        zip_path = os.path.join(out_dir, PKG_NAME + ".zip")
        if os.path.exists(zip_path):
            os.remove(zip_path)
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for name in sorted(os.listdir(pkg_dir)):
                zf.write(os.path.join(pkg_dir, name), PKG_NAME + "/" + name)
        print("   zip: %s (%d 字节)" % (zip_path, os.path.getsize(zip_path)))

    print()
    print("== 完成 ==")
    print("   目录: %s" % pkg_dir)
    if zip_path:
        print("   压缩: %s" % zip_path)
    print("   老电脑上：拷过去 -> 双击 install.bat（或 install.bat D:\\HYTCAD）")
    print("   仅放文件不碰 CAD：install.bat D:\\HYTCAD --check")
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="生成老旧电脑（AutoCAD 2007~2020）最小移植包")
    ap.add_argument("--out", default="deploy",
                    help="输出目录（默认仓库根下 deploy/）")
    ap.add_argument("--no-zip", action="store_true", help="不打包 zip")
    ap.add_argument("--check", action="store_true",
                    help="只做前置校验与清单，不写盘")
    args = ap.parse_args()

    root = repo_root()
    out_dir = args.out if os.path.isabs(args.out) else os.path.join(root, args.out)
    print("仓库根: %s" % root)
    print("输出到: %s" % out_dir)
    print()
    try:
        if not args.check:
            os.makedirs(out_dir, exist_ok=True)
        rc = build(root, out_dir, make_zip=not args.no_zip, check_only=args.check)
    except OSError as exc:
        print("[失败] 写盘出错：%s" % exc)
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
