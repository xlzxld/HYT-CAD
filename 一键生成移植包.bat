@echo off
rem ============================================================================
rem  一键生成「老旧电脑（AutoCAD 2007~2020）移植包」—— 双击本文件即可。
rem  等价于依次执行：
rem     python tools\make_ansi.py      再生 scripts_ansi\ 的 GBK 副本
rem     python tools\check_lisp.py     6 个脚本静态检查（逐个）
rem     python tools\deploy_old_pc.py  打包到 deploy\ 并生成 zip
rem
rem  可选参数（命令行调用时用，双击不用管）：
rem     noopen    跑完不自动打开 deploy 目录
rem     nopause   跑完不等待按键（给脚本调用）
rem
rem  编码约定：本文件为 GBK + CRLF。cmd.exe 按 OEM 代码页逐字节解析 .bat，
rem  中文必须存成 GBK；存成 UTF-8 会让解析器丢同步、命令被从中间劈开执行。
rem ============================================================================

chcp 936 >nul
setlocal
cd /d "%~dp0"
title HYT-CAD 生成老机移植包

set "NOOPEN="
set "SKIPPAUSE="
if /i "%~1"=="noopen" set "NOOPEN=1"
if /i "%~2"=="noopen" set "NOOPEN=1"
if /i "%~1"=="nopause" set "SKIPPAUSE=1"
if /i "%~2"=="nopause" set "SKIPPAUSE=1"

echo ============================================================================
echo   HYT-CAD  老电脑移植包生成器
echo   目标机: AutoCAD 2007~2020 完整版(非 LT)     产物: deploy\ 目录 + zip
echo ============================================================================
echo.

rem ---------- 1. 找 Python 3 ----------
set "PY="
if defined HYTCAD_PYTHON if exist "%HYTCAD_PYTHON%" set "PY=%HYTCAD_PYTHON%"
if defined PY goto :havepy

py -3 -c "import sys" >nul 2>nul
if not errorlevel 1 set "PY=py -3"
if defined PY goto :havepy

python -c "import sys" >nul 2>nul
if not errorlevel 1 set "PY=python"
if defined PY goto :havepy

python3 -c "import sys" >nul 2>nul
if not errorlevel 1 set "PY=python3"
if defined PY goto :havepy

echo [错误] 找不到 Python 3。
echo        装一个 Python 3.6 以上即可；或用环境变量指定，例如：
echo        set HYTCAD_PYTHON=C:\Python314\python.exe
goto :fail

:havepy
echo   使用的 Python: %PY%
echo.

echo ---------- [1/3] 再生 GBK 副本：scripts_ansi\ ----------
%PY% "tools\make_ansi.py"
if errorlevel 1 goto :fail
echo.

echo ---------- [2/3] 静态检查 6 个脚本 ----------
for %%F in (dt_start flb_runner cx_runner jrt_runner wx_runner demo_recorder) do (
  %PY% "tools\check_lisp.py" "scripts\%%F.lsp"
  if errorlevel 1 (echo [错误] %%F.lsp 检查未通过，已中止。 & goto :fail)
)
echo.

echo ---------- [3/3] 打包移植包 ----------
%PY% "tools\deploy_old_pc.py"
if errorlevel 1 goto :fail
echo.

if defined NOOPEN goto :done
start "" "%~dp0deploy"

:done
echo ============================================================================
echo   完成。
echo   产物目录: %~dp0deploy
echo   下一步  : 把该目录(或里面的 zip)拷到老电脑, 双击其中的 install.bat 。
echo ============================================================================
echo.
if not defined SKIPPAUSE pause
endlocal
exit /b 0

:fail
echo.
echo ============================================================================
echo   失败：没有生成任何包。请看上面的错误信息。
echo ============================================================================
echo.
if not defined SKIPPAUSE pause
endlocal
exit /b 1
