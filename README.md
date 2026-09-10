# HYT-CAD — 热流道自动化 AutoCAD 出图脚本

一套在 AutoCAD 里**一键生成热流道分流板、出线槽、加热条二维图纸**，并完成**尺寸测量与外协出图（线切割 / 精雕 / 数据图纸）**的 AutoLISP 工具箱。

装一次，之后每次打开 AutoCAD 顶部菜单栏自动出现「热流道自动化(&R)」——点菜单或敲命令即可出图。

- **适用版本**：AutoCAD **2007 ~ 2026** 全系列（**不支持 AutoCAD LT**，LT 的 LISP 没有 COM 接口）
- **技术栈**：AutoLISP + Visual LISP (COM) + DCL，纯 `vla-*` / `vlax-*` 几何操作，不调用 CAD 命令（撤销用 COM 撤销标记）
- **开发工具**：Python 3 纯标准库，零第三方依赖

当前版本：`flb_runner` **v10.11** / `jrt_runner` **v9.36** / `cx_runner` **v11.8** / `wx_runner` **v2.14** / `dt_start` **v3.3** / `demo_recorder` **v1.1**

---

## 1. 项目用途

针对热流道模具的二维出图环节：设计员在 `LD` 图层画流道中心线（源线），脚本自动完成**偏移 → 裁剪 → 圆角 → 封口 → 倒角 → 假体 → 热咀/点孔 → 主进胶**等一整套几何构造；再由测量/外协模块直接产出车间可用的下料尺寸与外协 DWG（线切割、精雕正反面、数据图纸）。目标是**把重复的手工画线工作变成"画源线 + 点菜单"两步**。

## 2. 主要功能

| 模块 | 命令 | 能做什么 |
|---|---|---|
| **分流板** `flb_runner` | `FLB` / `FLBPARAM`（兼容 `OFF` / `PARAM`） | 模板选择「通用 / 矩形」→ 源线偏移、通道裁剪、断口圆角、通道封口、热咀圆 + 点孔圆、螺丝孔、封口倒角、假体（传统逐步 / 包络法开关）、自动扫 DP 圆心生成主进胶圆 |
| **加热条** `jrt_runner` | `JRT` / `JRTPARAM` | 多模板：**通用一**（LD 多层嵌套轮廓 + 端帽，圆帽 / 直线帽按间隙判定）、**通用二**（外壁整圈 + 定位线单线自动补边，自动开出线口、破口封闭线、颈线，方向全部几何判定，与画线方向无关） |
| **出线槽** `cx_runner` | `CX` / `CXPARAM`（兼容 `SLOT` / `SLOTPARAM`） | 通道壁偏移、区域裁剪、大小两级圆角自动适配、悬空端头延长收头、敞口封闭、CXK 封闭线自动分流，并**沿选定侧壁自动布置压线板**（内壁 / 外壁 / 左壁 / 右壁可选） |
| **测量与外协** `wx_runner` | `FLBSZ`（别名 `FLBSIZE` / `SZ` / `WXSZ`） | 自动量出分流板最长 / 最宽（双引擎闭合校验：ACIS Region + 端点拓扑），结果写入剪贴板，可选绘制包络框与长宽标注 |
| | `XQG` | **线切割出图**：提取闭合分流板轮廓，倾斜工件自动正交摆正，按「幅」网格排版克隆到目标 DWG 并标注文件名 |
| | `JD` | **精雕出图**：白名单加工曲线提取，镜像体排在本体右侧（正反面间隔 75mm），每幅加包络盒，正反面分流排版 |
| | `SJTZ` | **数据图纸**：加工曲线提取克隆进隔离图层，右侧生成双列信息文本块（日期全自动） |
| **引导器** `dt_start` | `DTINSTALL` / `DTRELOAD` / `DTUNINSTALL` / `DTDBG` / `DTDEMO` | 一键加载全部脚本、写开机自启钩子、挂顶部菜单、逐家族加载验证、安装/卸载/目录定位诊断 |
| **演示记录器** `demo_recorder` | `DEMOREC` / `DEMOSTOP` / `DEMOMARK` | 把手工操作录成命令 / 拾取点 / 新建实体日志，供开发者与 AI 分析操作意图（开发辅助工具） |

其他特性：

- **21 个约定图层**（拼音缩写：LD/FLB/LS/JT/RZ/DK/DP/ZJJ/CX/CXK/YXB/JRT/JRTFBX/JRTDW/FLB_BOX/数据图纸/外协文字/JD/外协包络盒…），全脚本配色统一并经门禁校验；
- **参数外置**：默认值与常用开关写在 `scripts\*.ini`（记事本可改，改完下次弹框 / 出图即生效），另有 `*_mem.ini` 跨会话记忆上次填值与所选模板；ini / dcl / 记忆文件都是**运行生成物，不入库**，新机首次运行自动生成；
- **双编码部署**：`scripts\`（UTF-8 with BOM）供 AutoCAD 2021+，`scripts_ansi\`（GBK）供 2007~2020 老电脑，由 `tools\make_ansi.py` 从原版自动生成并逐字节校验；
- **全版本兼容底座**：老版本 `getvar` 读不到的系统变量一律收敛为 `""`（`dt:st-gets` / `dt:st-hasvar`），已实测通过 AutoCAD 2007 安装、自启、菜单与全命令。

## 3. 适用场景

- 热流道 / 注塑模具设计，需要批量出**分流板、出线槽、加热条**二维加工图；
- 需要把分流板轮廓交给**线切割 / 精雕**外协厂，并要求自动摆正、正反面排版、文件名标注的规范化出图；
- 需要快速得到下料尺寸（最长 × 最宽）并粘贴进下料单；
- 车间电脑 AutoCAD 版本杂（2007 老机台与新版本混用）的场合。

## 4. 快速开始

### 4.1 安装（只需一次）

1. 打开 AutoCAD，命令行输入 `APPLOAD`，选择 **`scripts\dt_start.lsp`** 并加载；
2. 命令行输入 `DTINSTALL`；
3. 完成。之后每次开 CAD 会自动加载全部脚本并挂出顶栏菜单「热流道自动化(&R)」。

> **AutoCAD 2007 ~ 2020 的老电脑**：先把 `scripts_ansi\` 里的 6 个 `.lsp` 复制到 `scripts\` **覆盖同名文件**，再执行上面的安装步骤（ini / dcl / 记忆文件两种版本通用，且会自动生成）。

### 4.2 日常使用

顶栏「热流道自动化(&R)」二级菜单顺序为 **分流板 / 加热条 / 出线槽 / 外协加工 / 工具 / 关于**，点菜单与敲命令等价。

```
源头线:  分流板/假体/加热条 → 画在 LD 层；出线槽 → 画在 CX 层；垫片(可选) → DP 层
分流板:  FLB    → 选模板[通用/矩形] → 参数框 → 全自动
加热条:  JRT    → 选模板[通用一/通用二] → 参数框 → 全自动
出线槽:  CX     → 参数框 → 选压线板贴壁侧 → 全自动
测量:    FLBSZ  → 自动量最长/最宽并写入剪贴板
外协:    XQG(线切割) / JD(精雕) / SJTZ(数据图纸) → 自动输出到配置的根目录
换版本:  DTRELOAD（不重启刷新 + 重挂菜单）   卸载: DTUNINSTALL
诊断:    DTDBG（打印目录定位与对话框链路状态）
```

详细的分步流程、参数含义、图层对照与排错方法见 **[`README_CAD.md`](README_CAD.md)**（完整使用手册）。

## 5. 目录结构

```
HYT-CAD/
├─ scripts/                 主脚本（UTF-8 with BOM，AutoCAD 2021+）
│  ├─ dt_start.lsp          引导器：加载/自启/顶栏菜单/安装诊断
│  ├─ flb_runner.lsp        分流板
│  ├─ jrt_runner.lsp        加热条（通用一 / 通用二）
│  ├─ cx_runner.lsp         出线槽 + 压线板
│  ├─ wx_runner.lsp         尺寸测量 + 线切割/精雕/数据图纸出图
│  ├─ demo_recorder.lsp     演示记录器（开发辅助）
│  └─ *.ini / *.dcl / *_mem.ini   运行生成物（不入库，首次运行自动生成）
├─ scripts_ansi/            GBK 副本目录（AutoCAD 2007~2020），由 make_ansi.py 生成
├─ tools/                   开发与门禁工具（Python 3 纯标准库）
└─ *.md                     文档：README / README_CAD / AGENTS / AGENTS_CAD / AUDIT-SPEC / BOOTSTRAP
```

## 6. 文档索引

| 文档 | 读者 | 内容 |
|---|---|---|
| `README.md` | 浏览仓库的人 | 项目用途、功能概览、快速开始（本文） |
| [`README_CAD.md`](README_CAD.md) | CAD 使用者 | 操作手册：安装、分步画图流程、命令手册、图层对照、参数详解、注意事项与排错 |
| [`AGENTS_CAD.md`](AGENTS_CAD.md) | 接手代码的 AI / 开发者 | 技术细节：函数清单、算法要点、数据结构、版本历史、已知坑、接手流程 |
| [`AGENTS.md`](AGENTS.md) | AI 编码助手 | 协作契约：铁律、验证门禁命令、红线与指令映射 |
| `AUDIT-SPEC.md` / `BOOTSTRAP.md` | 维护者 | 代码体检规范 / 规范部署与升级流程 |

## 7. 开发者：门禁命令

改动 `.lsp` 后本地必须全绿（Python 3 纯标准库，无第三方依赖）：

```bash
# 构建：scripts/ (UTF-8+BOM) → scripts_ansi/ (GBK) 并逐字节校验（改任何 .lsp 后必跑）
python tools/make_ansi.py

# 回归测试
python tools/test_direction.py        # 方向 / 排版 / 模板回归（16 组 89 断言）
python tools/check_audit_fixes.py     # 历史体检修复项回归（14 项）
python tools/check_jrt2_out.py <JRT通用二产物.dxf>   # 需 AutoCAD 出图后人工执行

# 静态检查（6 个脚本逐一跑）
python tools/check_lisp.py scripts/flb_runner.lsp     # 括号/编码/规范
python tools/check_sysvars.py                         # 低版本系统变量 nil 泄漏门禁
python tools/check_defun_depth.py                     # defun 顶层深度门禁
python tools/check_layer_colors.py                    # 图层配色门禁（21 图层，去重 19 色）

# 仅报告不阻断的深度审计
python tools/_audit.py     # 同名不同体 / 死函数 / 全局变量泄漏 / 未定义引用
python tools/_collide.py   # 跨脚本同名函数冲突
```

完整协作契约（铁律、红线、提交规范）见 [`AGENTS.md`](AGENTS.md)。

---

*本项目为单人维护的工程实用工具集，脚本与文档同批更新（版本号单一来源：各 `.lsp` 头注 + 脚本内 `*dt-*-ver*` 常量）。*
