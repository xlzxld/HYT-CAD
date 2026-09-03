# AGENTS_CAD.md — AutoCAD 流道分流板脚本（AI 接手文档）

> 本文档供接手本项目的 AI 使用（仅 AutoCAD 侧；NX 下游工具见 `AGENTS.md` §12）。包含完整的技术细节、函数清单、算法、版本历史、已知坑与接手流程。**改代码前请先通读本文档。**



---


## 1. 项目概览

| 项        | 内容                                                                                                                                                                                                                                                                                                                                                     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 工作目录     | `C:\Users\5600\Documents\ZDH\CAD\`（2026-08-30 发版并分类：**`scripts\` = 5 .lsp + 3 ini + 运行生成物(mem/dcl)一个运行单位**；`scripts_ansi\` = 5 个老版本 GBK 编码脚本副本(供 2007~2020 老电脑使用, 坑 #64)；`tools\` = check_lisp/\_audit/\_collide/make_ansi；根目录 = 两份 md。自启钩子指向 scripts\dt_start.lsp） |
| 改前备份     | 无固定目录（原 test\pc\ 已随发版删除）——改动前自行 `cp` 原件到临时位置, 用完即删, **勿在 CAD\ 内留第二份 .lsp**（坑 #35/#49 多副本误载）                                                                                                                                                                                                                                                            |
| 主脚本(分流板) | `offset_runner.lsp`（**v10.6**，2576 行，98 defun，多模板 通用/矩形，命令 OFF/PARAM；假体默认传统逐步, 参数框勾选「包络法」切换) |
| 出线槽脚本    | `slot_runner.lsp`（**v10.3**，1487 行，68 defun，命令 SLOT/SLOTPARAM；v10.3 起断口圆角函数改名 `dt:slot-fillet-pair`）                                                                                                                                                                                                                                                   |
| 加热条脚本    | `jrt_runner.lsp`（**v9.14**，2266 行，93 defun，多模板 通用一/通用二，命令 JRT/JRTPARAM）                                                                                                                                                                                                                                                                                |
| 尺寸测量与外协 | `wx_runner.lsp`（**v2.0**，1092 行，39 defun，独立第 4 脚本，命令 FLBSZ/XQG/JD/SJTZ；分流板最长最宽尺寸测量、线切割/精雕全自动年月路径与日期递增出图[已存在09.04则回车追加/输入N自动新建09.04_1]、MText 宽度设限自动折行居中标注、AABB向右平铺排版防覆盖、自动化图层白名单提取、数据图纸交互自由移动与右侧 95mm 间距双列信息文本块无打扰生成） |
| 引导器      | `dt_start.lsp`（**v3.0**，762 行，30 defun；一键加载+随 CAD 自启动+**顶部菜单「热流道自动化(R)」**(二级序: 分流板/加热条/出线槽/外协加工/工具)；v2.9 起含 `dt:st-gets`/`dt:st-hasvar`/`dt:st-support-root` 低版本兼容底座，**全版本通用**（2026-08-31 AutoCAD 2007 实测通过）。发版后无独立 old 副本） |
| 校验工具     | `tools\check_lisp.py`（按文件名自动区分清单 offset/slot/jrt/dt_start/wx：括号 stack/BOM/UNDO/死名/代码区非 ASCII/if 参数超限）                                                                                                                                                                                                                                                     |
| 审查工具     | `tools\_audit.py`（按自身位置定位 \`..\scripts\ 的 LSP；跨五文件静态审计：①同名不同体函数 ②从未被引用的死函数 ③未声明的全局变量泄漏 ④未使用的形参/局部 ⑤未定义函数引用）                                                                                                                                                                                                                                            |
| 冲突工具     | `tools\_collide.py`（脚本同名函数冲突检测；跨文件同名必须逐字一致）                                                                                                                                                                                                                                                                                                            |
| 编码工具     | `tools\make_ansi.py`（**发版必跑**：scripts\ UTF-8 → scripts_ansi\ GBK 副本 + 逐字节读取器模拟校验，供车间 2007~2020 老电脑部署，坑 #64）                                                                                                                                                                                                                                                 |
| 兼容门禁     | `tools\check_sysvars.py`（**发版必跑**：系统变量读取的「nil 泄漏」静态门禁——版本相关变量(TRUSTEDPATHS/SECURELOAD/ROAMABLEROOTPREFIX/LOCALROOTPREFIX/DWGPREFIX…)必须走 `dt:st-gets`/`dt:st-hasvar`，且 getvar 结果不得直接作 strcat/strlen 实参；坑 #65。反向验证：v2.8 命中 5 处风险，v2.9 全过）                                                                                                                |
| 版本命名     | 每次改动交付 `*_v<N><M>.lsp`（去点：v9.5→`_v95`）；v9.9 之后进 v10→`_v10`。**正式投用版无版本后缀**（`offset_runner.lsp` 等），dt_start 优先加载正式版                                                                                                                                                                                                                                      |
| 历史备份     | 本目录保留全部旧版；更早(v4~v820)在 `C:\Users\5600\WorkBuddy\2026-08-18-16-15-32\autocad-offset-tool\`；多文件试验场(已废弃)在 `Documents\2D3D`、`Documents\dph\autocad`                                                                                                                                                                                                        |
| 目标平台     | AutoCAD 2024（2007+）；AutoLISP + Visual LISP (COM) + DCL                                                                                                                                                                                                                                                                                                 |

**四脚本架构（2026-09-03 起，2026-09-04 更名）**：flb_runner(原 offset_runner) 只画分流板（命令 FLB/OFF）；cx_runner(原 slot_runner) 只画出线槽（命令 CX/SLOT）；jrt_runner 只画加热条（LD 偏移/裁剪/端帽/多层嵌套轮廓/多模板）；**wx_runner（原 size_runner）独立负责外协加工与尺寸数据测量（分流板最长最宽/双引擎闭合校验/剪贴板写入/FLB_BOX 标注，线切割/精雕外协自动出图，数据图纸文本块生成）**。各脚本**各自自包含**（公共几何库逐字复制），可单独或同时加载——除逐字相同的库函数外，参数表、对话框、dcl 文件、回调函数全部不同名隔离；凡**同名不同体**的函数一律改名隔离（坑 #46）。四个脚本家族在 `dt_start.lsp` 的 `dt:st-families` 统一注册，各对应一个二级菜单，二级菜单内再分布三级子项。

**核心原则**：纯 COM 几何操作（`vla-*`/`vlax-*`），不调 CAD 命令（`command` 仅 UNDO 分组）。

## 2. 运行与加载

### 2.1 推荐：dt_start 引导器（一键/自启动/顶部菜单）

```
APPLOAD dt_start.lsp → DTINSTALL(装完即自启, 本会话立即加载全部脚本+挂出顶栏菜单)
日常: 开 CAD 自动就位; 顶栏「热流道自动化(R)」点击即用(二级分组:
      分流板▸OFF/PARAM, 加热条▸JRT/JRTPARAM, 出线槽▸SLOT/SLOTPARAM,
      工具▸重载/诊断/安装/卸载/打开目录, 关于), 命令行输入照旧可用
换版本: 新文件放同目录 → DTRELOAD(不重启刷新+重挂菜单); 菜单异常就重启 CAD(自动重建)
卸载:   DTUNINSTALL(摘菜单+删 acaddoc.lsp 钩子+移出支持/受信任路径, 配置还原)
诊断:   DTDBG(参数对话框链路逐步打印, 定位 stringp 类错误)
```

- 钩子只认固定的 `dt_start.lsp`；**正式版（无版本后缀）优先加载**，无正式版才取"v+数字"最大者（纪元感知编码：v90-99=9.0-9.9 / v20-89=单次版本 / v10-19=10.0+ / 三位首位1=10.x，如 v816=8.16<v96=9.6）。
- **顶部菜单为会话级 COM popup**（塞在 ACAD 主菜单组内，不入主 CUI、不跨会话持久）：每次引导加载成功后自动重建，会话内只完整构建一次（`*dt-st-menu-done*`），工作区切换挤掉菜单 → DTRELOAD 重挂。宏机制定案见坑 #50~#53：`chr(3)` 真取消码 + `(c:命令)` LISP 表达式宏 + 尾空格=回车，全部经 `dt:st-macro` 一处构造。
- 整包复制到新目录/新电脑：重跑 APPLOAD+DTINSTALL 即可（getfiled 兜底定位）。

### 2.2 手动逐个加载

```
分流板: APPLOAD offset_runner.lsp → OFF(先选模板[通用/矩形]→参数框→全自动) / PARAM(只改参数)
出线槽: APPLOAD slot_runner.lsp   → SLOT(弹参数框→全自动) / SLOTPARAM(只改参数)
加热条: APPLOAD jrt_runner.lsp    → JRT(先选模板[通用一/通用二]→参数框→全自动); 通用一需先跑 OFF(RZ 存在)
源线: 分流板/假体画在 "LD" 层; 出线槽画在 "CX" 层; 加热条不画源线(复用 LD)
```


### 2.3 版本兼容性（2026-08-31 编码补丁 + v2.9 低版本修复后定案）

| AutoCAD 版本              | 三脚本                             | 自启动               | 顶部菜单                    | 结论                                  |
| ----------------------- | ------------------------------- | ----------------- | ----------------------- | ----------------------------------- |
| **2007**（32位）           | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅                 | ✅ MenuGroups.Add 老版原生可用 | **已实测通过**（2026-08-31，dt_start v2.9） |
| 2008/2009（32位）          | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅                 | ✅ MenuGroups.Add 老版原生可用 | 可用（与 2007 同代，预期一致）                  |
| 2010~2015               | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅                 | ✅                       | 可用                                  |
| 2016~2020               | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅ TRUSTEDPATHS 生效 | ✅                       | 可用                                  |
| 2021~2023（Unicode LISP） | ✅ 用 scripts\ 的 UTF-8 原版         | ✅                 | ✅ 回退已覆盖                 | 可用                                  |
| **2024**                | ✅ 实测（UTF-8 原版）                  | ✅ 实测              | ✅ 实测                    | 已验证                                 |
| 2025/2026               | 预计 ✅（UTF-8 原版）                  | 预计 ✅              | 按下方清单验证                 | 待验证                                 |
| AutoCAD LT（任意年份）        | ❌                               | ❌                 | ❌                       | **不支持**：LT 的 LISP 无 vla-* COM       |

> **2007 实测记录（2026-08-31）**：GBK 副本 APPLOAD 成功 → `DTINSTALL` 一次通过 → 三脚本加载 + 顶栏菜单挂出。此前 v2.8 在同一台 2007 上 `DTINSTALL` 报「参数类型错误: stringp nil」（坑 #65），v2.9 修复后即通过。**注意**：2007 无 `TRUSTEDPATHS`（2016 才引入），安装时该步会打印"无(老版本, 跳过)"，属正常。

- **编码红线（坑 #64, 2026-08-31 实锤）**：≤2020 的 AutoCAD 是 MBCS(GBK) LISP，其读取器按双字节规则解析文件——加载 UTF-8 版 .lsp 时中文注释/字符串的字节被当作 GBK 双字节字符吞掉换行/引号/括号/点号，报「错误: 输入中的点位置不正确」（2007 实测，横幅都来不及打印）。**2007~2020 一律部署 `scripts_ansi\` 的 GBK 副本（覆盖 scripts\ 同名文件即可）；2021+ 用 scripts\ 的 UTF-8 原版**。副本由 `python tools\make_ansi.py` 从原件生成（含逐字节读取器模拟校验），**每次改版 scripts\ 后必须重跑**。原「全版本通用一份文件」的结论作废——API 层面仍全版本通用，文件编码层面分两份。
- **v2.9 起 `dt_start.lsp` 真正全版本通用（坑 #65，2007 实测定案）**：v2.6 只把 TRUSTEDPATHS 的 getvar/setvar 包了 `vl-catch-all-apply`，**只挡住"抛异常"这半边**；老版本读本版本没有的系统变量时是**静默返回 nil**，nil 漏出后被喂进 `strcat`/`strlen` 就报 `参数类型错误: stringp nil`（DTINSTALL 当场中断，无任何中文提示）。v2.9 新增兼容底座把三种情况（抛错 / nil / 非字符串）统一收敛：
  - `dt:st-gets` —— 取系统变量，不可用一律返回 `""`（**绝不给 nil**），全文件所有 getvar 必经此函数；
  - `dt:st-hasvar` —— 变量是否存在（DTDBG/DTINSTALL 打印可用性用）；
  - `dt:st-support-root` —— `ROAMABLEROOTPREFIX` → `LOCALROOTPREFIX` → `""`；取不到时 `acaddoc.lsp` **兜底写进脚本目录**，且 `DTINSTALL` 会把该目录**顶到支持路径最前**（AutoCAD 只加载搜索路径里第一个 acaddoc.lsp，不置顶兜底那份不生效）。
  - 三个泄漏点已全部封死：`dt:st-trusted-add/-del`（TRUSTEDPATHS，2007~2015 命中）、`dt:st-acadoc-path`/`st-write-hook`（ROAMABLEROOTPREFIX）、`dt:st-locate`（DWGPREFIX，无图纸打开时）。
- ~~v2.6 起 `dt_start.lsp` 全版本通用~~（已被 v2.9 取代，保留原因：v2.6 的 catch 对"静默 nil"无效）。此前需按 CAD 版本在正式版 v2.5 与 `old\dt_start.lsp` v2.6 之间挑文件 —— 该区分已取消。
- 架构性保证：纯 LISP+COM（接口均 A2000+）；不调 CAD 命令（仅 UNDO 分组）；DCL 非 Ribbon；无 .NET/ARX/DLL；ini/dcl 走系统 ANSI/GBK 且键值行纯 ASCII。
- 版本敏感点与防护：**INI 中文节名解析**（v10.2d 修复，坑 #59 —— 2021 前 strlen 按字节/substr 按字符，旧写法节名会残留 `]`）；MenuGroups.Add 2024 移除（双路径回退，坑 #50）；boundingbox 绑定差异（v9.8a 双兼容，坑 #56）。
- **同机多版本共存**：各版本 Roaming 钩子/注册表/配置文件按版本隔离，互不干扰——每个 CAD 版本各自 APPLOAD+DTINSTALL 一次，共用同一脚本目录与 ini。
- 2025/2026 验证清单：① APPLOAD+DTINSTALL ② 顶栏菜单+OFF 弹框 ③ 改 ini→恢复默认 ④ 重启自动挂载+DTRELOAD/DTUNINSTALL；异常按坑 #50~#62 输出定位。


### 2.4 参数配置文件与记忆（offset v10.6 / slot v10.3 / jrt v9.14）

| 文件（脚本目录，TEMP 兜底）                       | 内容                                                                      | 谁写                |
| -------------------------------------- | ----------------------------------------------------------------------- | ----------------- |
| `offset_runner.ini` / `jrt_runner.ini` | 默认值，按模板分节 `[通用]`/`[矩形]`/`[通用一]`/`[通用二]`，`键 = 数值` + `; 中文注释`（labels 表生成） | 首次运行自动生成，用户记事本改   |
| `slot_runner.ini`                      | 同上，固定节 `[参数]`（无模板；v10.1 起也带中文注释）                                        | 同上                |
| `*_mem.ini`（三个）                        | 上次值记忆 + 单独一行写出的 `[模板] template=下标`（**只写一次**，v10.2d/v9.13 修复重复节）         | 程序在**确定参数框时**自动保存 |

- **语义**：预填=全局变量（加载时 boot 已从 mem 恢复上次模板+该模板上次值）；**恢复默认按钮 = ini 配置值**（无该键回模板内置默认→表 caddr 三级兜底）；**切换模板 = 该模板记忆值→ini 节→模板内置默认→caddr**；ini **每次弹框前重读**（改完保存即生效，无需 DTRELOAD）；取消对话框不触发保存。
- **实现**：各脚本尾部 `(dt:off-cfg-boot)` / `(dt:slot-cfg-boot)` / `(dt:jrt-cfg-boot)`（文件尾调用，定义在前）；解析器只认"键 = 数值"行（distof 校验，0 合法），注释/乱码/未知键跳过；全程 vl-catch-all，文件缺失/损坏静默回退内置默认。函数名带脚本前缀隔离（坑 #46）。

**编码**：`.lsp` 必须 UTF-8 with BOM（中文乱码→图层匹配失败）；`.dcl` 自动生成为 ANSI/GBK（两文件规则相反）。行尾 LF。`.ini` 走 AutoLISP 文本 IO（ANSI/GBK），键值行纯 ASCII，中文只在注释——用户误存 UTF-8 仅注释乱码、解析不受影响。三个脚本的 `find-dcl` 均为**确定性模式**：优先用 dt_start 注入的 `*dt-script-dir*` 写 `<dir>\*.dcl`，无引导器时写 `%TEMP%\*_tmp.dcl`（jrt v9.11b 对齐；旧 findfile 候选链已全部移除）。  
**≤2020 部署（坑 #64）**：2007~2020 加载 UTF-8 版报「输入中的点位置不正确」，须用 `scripts_ansi\` 的 GBK 副本（内容逐字同源，仅注释/个别提示文字的 ▸⇒²↔ 符号替换为 `>` `=>` `^2` `<->`）；由 `python tools\make_ansi.py` 生成并自动校验（GBK 可编码性 + 逐字节读取器模拟：字符串/括号结构与原件逐项一致），**改版 scripts\ 后必须重跑**。ini/dcl/mem 本就走 ANSI，两版共用无差异。

## 3. 图层约定（v9.4 起拼音缩写）

| 缩写    | 含义     | 颜色   | 说明                                   |
| ----- | ------ | ---- | ------------------------------------ |
| LD    | 流道线    | —    | 分流板源中心线（用户画，脚本不碰）                    |
| FLB   | 分流板    | 红 1  | 含并入的封口线/倒角斜线                         |
| FBX   | 封闭线    | 绿 3  | **流程临时层**：倒角后并入 FLB 并删除（第 9.5 步）     |
| LS    | 螺丝     | 青 4  | v9.6 起单圆                             |
| JT    | 分流板假体  | 洋红 6 | v9.1 前称"分流板挖孔"                       |
| JTFBX | 假体封闭线  | 黄 2  | **流程临时层**：圆角后并入 JT 并删除（第 15.5 步）     |
| RZ    | 热咀     | 橙 30 | 热咀圆 R11.35                           |
| DK    | 点孔     | 白 7  | 点孔圆 R3（与热咀同心）                        |
| DP    | 垫片     | 蓝 5  | **预留层**：只创建不自动画、不参与清理（用户手画）          |
| CX    | 出线槽    | 蓝 5  | 源线+通道壁+圆角弧+封闭线同层（slot_runner 管理）     |
| CXK   | 出线口封闭线 | 蓝 5  | v9.9：距 DP 最远的那条封闭线自动分流到此层（slot 创建）   |
| JRT   | 加热条    | 黄 2  | 多层嵌套轮廓+端帽同层（jrt_runner 管理；纯产物层，重跑全清） |
| JRTDW | — | 通用二加热条的定位源线 | 你画 |
| FLB_BOX | 分流板外包矩形及标注 | 青 4 | 分流板最长最宽包络参考框与字高 15 线性标注（FLBSZ 管理） |

> `ensure-layer`（offset/jrt）对已存在但大小写不一致的图层自动改名纠正（如 dp→DP；AutoCAD 图层名不区分大小写，坑 #29）。CXK 由 slot 内联创建（无 ensure-layer）。

## 4. 完整流程

### 4.1 `c:OFF`（offset_runner v10.7，行 2340；v9.8 起先弹**模板选择框**[通用/矩形]，取消中止）

0 选模板(**通用**=下述现状全流程，行为零变化；**矩形**=`dt:rect-process` 自管全流程，见 §7) → 0.5 弹参数框(取消中止；v9.9 起按模板动态显示参数键) → 1 检查 LD 层 → 2 全选 → 3 建 8 层(FLB/FBX/LS/JT/JTFBX/RZ/DK/DP) → 3.5 清理旧产物(含 RZ/DK；**不清 DP、不清 CX**) → 4 偏移35→FLB → 5 裁剪 → 6 断口圆角R15 → 7 通道封口→FBX → **7.5 热咀+点孔圆**(RZ/DK，须在倒角前：倒角后 FBX 混入斜线无法按层识别) → 8 螺丝孔(单圆，必须在倒角前) → 9 倒角 → **9.5 FBX 并入 FLB 并删层**(v9.1) → **10~15.5 假体(v10.2 包络法，见 §7；FLB 为空/外扩量过小时回退旧五步：LD偏移50→带状裁剪→断口圆角→延长15→端点封口→封口圆角→并层)** → 17 统计。（以上大括号前为通用模板流程，行号参考）

### 4.2 `c:SLOT`（slot_runner v10.3，行 1456；`dt:slot-process` 行 1276）

0 弹参数框 → 检查 CX 层 → 只对**源线**(eName 记录)偏移 17.5 生成通道壁(源线同层保留) → 1 区域裁剪(exclude 源线) → 2 小圆角R15 → 3 悬空端头固定延长 50 → 4 **收头+大圆角**(v9.5/7)：每条延长壁沿方向找第一个交点并收头(=FILLET 自带修剪)；交点处双方端头重合→与小圆角**同一套 fillet-pair 仅换 R30**(nochk=T)；端头落在宿主壁内部(T形)→打断宿主壁取同侧断头配对；未命中→复原 → 5 **封闭**(v9.6/7)：每个敞口(源线悬空端的两壁端头，距源线端点≈17.5)连一条封闭线；**收尾 CXK 分流**(v9.9)：距 DP(垫片)最远的一条封闭线移入 CXK 层(DP 为空则提示跳过) → 6 **删除全部源线**(v9.6，重跑需重画源线)。**垫片要在跑 SLOT 之前画好才会分流出 CXK**。

### 4.3 `c:JRT`（jrt_runner v9.14，行 2182；`dt:jrt-build`(1326)/`dt:jrt-decide`(1065)）

0 弹参数框/选模板(v9.8 多模板) → 1 检查 LD 层 → 2 建 JRT 层(黄2)+清上轮产物 → 3 检查 RZ 层(无→警告，端头全部退化为直线帽) → 4 **端帽统一判定**(`dt:jrt-decide`，各层共用)：自由端头(端点不落在其他 LD 线上)逐一算 `gap = 本LD线与不相交LD线的最小轴线距 − 2×偏移值`，|gap−偏移值|≤1 且匹配到 RZ → 圆帽；否则直线帽；gap 过近 → 告警+直线帽 → 5 **多层构建**(`dt:jrt-build`，k=0..N)：每层 = 偏移 LD→JRT → LD±半宽带状裁剪(仅本层实体，eName 快照差集隔离) → 端帽(圆帽=RZ圆心整圆R=半宽+侧线修到切点；直线帽=LD端点平面向内偏 inset 画帽线+侧线端头修到帽平面) → 统一断口圆角(交汇断口+帽角同一套 jrt-fillet-pair) → 零长残段清理 → 6 统计。**不读 FBX**：全部几何由 LD+RZ 推导。参数：jrt_fillet_r 19(内层逐层+step=同心弧)、jrt_cap_r 29(≥半宽时封闭线=相切圆弧)、jrt_inner_count 2(层数=次数+1)；默认自洽 40−11=29=半宽。

### 4.4 `c:FLBSZ` / `c:FLBSIZE`（wx_runner v2.0，外协与独立测量脚本）

0 探测 FLB 图层(无/空→提示并转入第1步) → 0.5 检验闭合(双引擎：vla-AddRegion + 端点 0.5mm 拓扑度数；闭合→直达第2步，未闭合→提示并转入第1步) → 1 手动选线(ssget 选线，ESC/空选取消退出；闭合校验通过→第2步，未闭合→弹窗提示并取消退出) → 2 计算外包尺寸(AABB+OBB 最小外接矩形计算，求最长与最宽) → 3 自动复制剪贴板(如 350x180) + 命令行打印 + 结果弹窗 → 4 询问是否绘图(选择 Y 在 FLB_BOX 绘制包络矩形与长宽标注，字高≥15)。

## 5. 参数表

**主脚本 `dt:param-table`（12 项，v9.8 增 rect_chamfer 后；v9.6 螺丝单圆）**：offset_dist 35 / hole_dist 50 / hole_extend 15 / fillet_r 15 / fillet_r_hole 15 / chamfer_d 5 / screw_in 10 / screw_r 4.25 / nozzle_offset 40 / nozzle_r 11.35 / pin_r 3(设0不画) / rect_chamfer 10(矩形模板板角倒角)。预填/应用/恢复默认全由表驱动，对话框分组：基本尺寸/螺丝孔与倒角/热咀和点孔。**v10.5 勾选框**：参数框底部「假体用包络法」toggle（全模板可见, 不随模板键变化），全局 *dt-jt-envelope*；默认值 = ini [假体] envelope(0=传统逐步默认, 1=包络法)，确定才记忆(mem [假体])，恢复默认=ini 值；旧 ini 由 cfg-boot 自动追加该节(不重写全文件)。

**slot `dt:slot-param-table`（4 项）**：slot_dist 17.5 / slot_extend 50 / slot_fillet_r_small 15 / slot_fillet_r_large 30。对话框分组"基本设置"。

**jrt `dt:jrt-param-table`（6 项，v9.8）**：jrt_offset 29(半宽) / jrt_cap_inset 11(直线帽内偏) / jrt_fillet_r 19(交汇圆角，内层+step=同心弧) / jrt_cap_r 29(封闭线圆角，≥半宽时为相切圆弧) / jrt_inner_step 4(向内步长) / jrt_inner_count 2(层数=次数+1)。另有多模板表 `dt:jrt-template-table`。

注意：每次 APPLOAD 重载参数重置为默认。固定参数：字高 10、圆角递减步长 1/最小 1、断口配对容差 1e-3、find-touch 上限 15、封口配对容差 max(1, 15%×off-dist)、出线槽延长命中容差 0.5、敞口封闭窗口 17.5±15%、CXK 距离=3 采样点最小法。

## 6. 函数清单


### 6.1 offset_runner v10.6（98 defun）
- 工具(104-310)：dist/flat->pts/inters-pts/ss->list/ms/layer-vlas/poly-pts/point-on-line/uniq/excluded-p/**curve-p/curves-only(v10.6 非曲线实体过滤)**/norm-angle/in-zone/unit/pt+vec/acos/tan/angle-between/not-parallel/arc-covers/end-infos/set-endpoint/endpoint-in
- **参数配置与记忆(v10.1, 139-260)**：off-cfg-dir/off-cfg-kv(off-cfg-read(distof 校验 INI 解析)/off-cfg-sec/off-cfg-get/**off-param-default(cfg→模板表→caddr 三级)**/off-cfg-gen(带注释生成 ini)/**off-mem-save(按模板保存)**/**off-cfg-boot(文件尾调用: 生成缺失 ini+恢复上次模板/值)**；全局 \*dt-off-cfg\*/\*dt-off-mem\*
- 切割链(326-493)：cut-params(v10.6 getparamatpoint 剔 nil)/seg-mid/rebuild-seg/cut-curve(统一驱动: nil=打断/TRIM=裁剪)/poly-rebuild/trim-curve/cross-points(**v10.6 包围盒预过滤**: bbox 不相交跳过 intersectwith, 复用 dt:rect-bbox)/trim-all
- 圆角(531-671)：fillet-pair(6参)/collect-heads/pair-heads/fillet-all
- 封口(673-788)：end-free/pick-pair/close-pair/same-pair/make-close-line/close-channels
- 倒角+热咀+假体(790-1150)：collect-plate-ends/find-touch/**nozzle-circles(820)**/add-close-line/mark-fail/chamfer-one/chamfer-close/near-center-end/extend-ends/fillet-close-one/fillet-close
- 图层偏移(1151-1299)：ensure-layer(大小写纠正, **1471**)/purge-layer/**merge-layer(1506)**/offset-enames/offset-layer/offset-inward
- 螺丝(1300-1384)：add-screw(1302 单圆)/drill-holes
- **多模板(v9.8~v10.0)**：off-template-table(**1853**, 通用/矩形, 矩形 process 级覆盖)/off-template-row(1894)/**rect-bb-pts(2006, boundingbox 的 variant/safearray 双兼容)**/**dt:rect-bbox(2012, 对象列表→包络盒)**/**dt:rect-process(2120)**/**dt:off-param-labels(1875)**
- **假体包络法(v10.2, 1348 起)**：**dt:jt-build(1410, FLB 包络盒外扩 hole_dist−offset_dist 圆角矩形, 复用 dt:rect-bbox；v10.2d 起圆角上限与 rect-jt 同为 0.45×短边)**/dt:jt-line(1462)
- 对话框(1386-1528)：dcl-lines(v9.9 按模板动态生成)/write-dcl/find-dcl/get-num/param-reset/param-apply/param-dialog/c:PARAM
- c:OFF(2218，含局部 *error*)

### 6.4 wx_runner v2.0（39 defun，外协加工与尺寸测量脚本）
- 自包含基础几何库：dt:ms/dt:ss->list/dt:ensure-layer/dt:rect-bb-pts/dt:rect-bbox/dt:sz-curve-p/dt:sz-curves-only
- 测量核心引擎：dt:sz-copy-clip(ActiveX+clip.exe双通道)/dt:sz-curve-sample-pts/dt:sz-curve-angle/dt:sz-uniq-angles/dt:sz-rot-pt/dt:sz-check-closed(双引擎: ACIS Region + 端点0.5mm拓扑度数)/dt:sz-calc-box(AABB+OBB最佳包络)/dt:sz-fmt-num/dt:sz-draw-box-dim(FLB_BOX 字高15)
- 命令接口：c:FLBSZ / c:FLBSIZE

### 6.2 slot_runner v10.3（68 defun）
- **参数配置与记忆(v10.1, 36-195)**：slot-cfg-dir/kv/read(v10.3 句柄兜底关闭)/sec/get/**slot-param-default**/slot-cfg-gen/**slot-mem-save**/**slot-cfg-boot**(文件尾)；全局 \*dt-slot-cfg\*/\*dt-slot-mem\*（固定节"参数"）；**dt:slot-param-labels(v10.1 新增, 生成 ini 中文注释)**
- 工具+切割链+圆角+偏移(40-591)：与主脚本逐字一致 + offset-enames；**v10.3: fillet-pair 改名 dt:slot-fillet-pair(缺省层/缺省半径绑定本脚本 "CX"/slot 小圆角, 消除对 offset 全局的隐藏耦合, 坑 #46)**；collect-heads/collect-ends 按 dt:curve-p 过滤(修 v10.2 回退丢失的文字防护)；**新增 dt:rect-bb-pts/dt:rect-bbox/dt:bbox-overlap-p(cross-points 包围盒预过滤)**；cut-params 剔 nil
- 出线槽链(744-1178)：collect-ends(744)/break-curve(753)/slot-trim(762)/slot-fillet-all(796)/**slot-first-cross(836)**/slot-extend-fixed(874)/**slot-join(921)**/near-src-fwd(1034)/**slot-close(1059, v10.1 去掉未用的 exclude 形参)**/**slot-cxk(1127)**/slot-process(1178)
- 对话框(1077-1192)：slot-dcl-lines/**slot-write-dcl(1104, v9.8 改名防冲突)**/slot-find-dcl(1115)/get-num/slot-param-reset/apply/dialog/c:SLOTPARAM
- c:SLOT(1349，含局部 *error*)

### 6.3 jrt_runner v9.14（93 defun）
- **参数配置与记忆(v9.13, 117-271)**：jrt-cfg-dir/kv/read/sec/get/**jrt-param-default**/jrt-cfg-gen/**jrt-mem-save**/**jrt-cfg-boot**(文件尾)；全局 \*jrt-cfg\*/\*jrt-mem\*
- 工具+切割链+圆角+图层偏移(103-667)：与主脚本逐字一致的库函数保留原名；**fillet-pair/cut-curve/trim-curve 改名 dt:jrt-\***（坑 #46）
- 加热条链(668-1063)：jrt-snapshot/jrt-diff(eName 快照差集)/jrt-sample-pts/jrt-curve-dist/jrt-touch-p/jrt-free-ends/jrt-match-rz/**jrt-decide(端帽判定,983)**/jrt-head-walls/jrt-cap-circle(1040)/jrt-cap-line(1070)/jrt-trim/jrt-fillet/jrt-zero-clean/jrt-template-row/jrt-stage/**jrt-build(1244)**
- 对话框(1064-1249→v9.11 后行号漂移以 grep 为准)：jrt-dcl-lines/jrt-template-dcl-lines/jrt-write-dcl/**jrt-find-dcl(v9.11b 确定性模式)**/jrt-get-num/jrt-param-reset/apply/dialog/jrt-apply-template/jrt-template-dialog/c:JRTPARAM
- c:JRT(2089，含局部 *error*)


### 6.4 dt_start v2.9（30 defun）
- **低版本兼容底座(v2.9 新增, 坑 #65)**：**st-gets(取系统变量, 抛错/nil/非字符串一律返回 "")**/**st-hasvar(变量是否存在)**/**st-support-root(ROAMABLEROOTPREFIX→LOCALROOTPREFIX→"" 兜底)** —— 全文件所有 getvar 必须经这三个函数, 禁止裸调 getvar(check_sysvars.py 门禁)
- 引导：st-families(**五元组**: 前缀/中文名/主命令/参数命令/子菜单热键, 加载与菜单共用)/st-init(\*dt-script-dir\* 注入+propagate)/**st-locate(findfile→dwgprefix(走 st-gets)→getfiled 兜底)**/st-digits/st-vernum(纪元感知)/st-pick(正式版优先)/st-join/st-boot(会话守卫, 加载成功后自动挂菜单)
- 钩子+路径：**st-acadoc-path(收 dir 参数; 支持根不可用→兜底写脚本目录)**/st-2bs/st-write-hook(标记块幂等; 支持根可用才 vl-mkdir 且包 catch)/**st-remove-hook(收 dir 参数)**/st-path-list/**st-split(入参 null 直接返回 nil)**/**st-add-support(收 front 参数: 兜底模式须把脚本目录顶到支持路径最前)**/st-del-support/**st-trusted-add/del(v2.9 起补 null + 非字符串判断: 老版本无此变量即跳过, 不再把 nil 喂给 st-path-list)**
- **顶部菜单(v2.1~v2.6)**：st-version/st-menugroup/st-menutitle 全局量；**st-macro(chr3 取消+(c:命令) LISP 宏+尾空格=回车, 坑 #50~#53 定案)**/st-open-dir/st-about/**st-menu-remove(自建组 Detach+ACAD 组同名 popup 清理, 双路径)**/**st-menu-build(自建组失败→ACAD 组塞 popup→同名残留复用, 会话内只建一次)**/st-menu-ensure(已建成仅重挂菜单栏)
- 命令：**c:DTINSTALL(打印 ACADVER/支持根/变量可用性 → 先加支持路径 → 再写钩子 → 再处理 TRUSTEDPATHS; 兜底模式 front=T)**/c:DTRELOAD(刷新+重挂菜单)/**c:DTDBG(新增 [0z] 环境探测段: ACADVER + 五个系统变量可用性 + acaddoc.lsp 落点, 专治 stringp nil)**/c:DTUNINSTALL(摘菜单+删钩子+移路径+重置菜单会话状态)


## 7. 核心算法要点（增量）

- **热咀+点孔（`dt:nozzle-circles`，1058 行）**：每条封口线=一个封闭通道端头；圆心=封口线中点+垂直于封口线、指向通道内侧×nozzle_offset(40)；内侧方向由相连分流板线中点相对封口线中点的点积判号。热咀圆→RZ，同心点孔圆→DK(pin_r=0 不画)。**必须在倒角前**调用。
- **并层（`dt:merge-layer`，1506 行）**：移全部对象到目标层→删空层定义(失败静默)。FBX→FLB(第9.5步)、JTFBX→JT(第15.5步)。
- **出线槽收头+大圆角（`dt:slot-join`，912 行）**：Pass1a 在未收头几何上逐条求延长向第一交点(实际交点过滤"沿方向且≤延长长+1"，无交点兜底端头贴壁≤0.5)→Pass1b 统一 set-endpoint 收至交点(命中)/复原(未命中)→Pass2 逐交点(去重)：≥2 重合端头→`fillet-pair ... T`(**与小圆角同公式仅 R 换大，nochk=T 关闭区域方向验证**——延长接头处两源线区域不重叠，区域检查会误拒正确方向，v9.3/v9.4 方向错的根源)；仅 1 端头(T形)→打断宿主壁、取主体方向与宿主源线前进方向同侧的断头配对。
- **敞口封闭（`dt:slot-close`，1059 行）**：v10.1 起去重改为双向比较(反向命中不再画重复封闭线)。：源线悬空端的壁端头距源线端点恰 17.5(窗口±15%)且悬空(end-free)→两不同对象端头连线。接头处壁端头已被移动(实测距≥22)天然排除。**端点记录必须用 collect-ends 的 (坐标 对象 端类型) 格式**（坑 #31）。
- **CXK 分流（`dt:slot-cxk`，1127 行，v9.9）**：每条封闭线 3 采样点(起/中/终)到各 DP 对象最近点(getclosestpointto)求最小=该线 DP 距离；取最大者(并列取先)移入 CXK(蓝5，内联创建)。DP 空则提示跳过(全部留 CX)；1 条封闭线时它即最远仍移入。与封闭同 UNDO 组。
- **加热条端帽判定（`dt:jrt-decide`）**：自由端头按 `gap = 本LD线与不相交LD线最小轴线距 − 2×jrt_offset` 判定：|gap−jrt_offset|≤1 且 RZ 匹配 → 圆帽；否则直线帽。端帽形式各层共用。RZ 匹配=圆心落在 LD 线上(垂距<0.5)且离本端点近；inward=端点→RZ圆心(无 RZ 时=端点→另一端点)。
- **加热条多层隔离（`dt:jrt-snapshot`/`dt:jrt-diff`）**：每层构建用 JRT 层 eName 快照+差集跟踪本层产物，裁剪/圆角/端帽只作用于本层实体。裁剪会删除重建对象，故每步后重新差集刷新。
- **矩形模板（`dt:rect-process`，offset v9.8~v10.0，2120 行）**：LD 包围盒四边向外扩 offset_dist 画矩形板边(rect-bb-pts 兼容 boundingbox 输出参数的 variant/safearray 两种绑定)→四角 rect_chamfer(默认10) 倒角→圆角矩形假体(外扩 hole_dist, fillet_r_hole)→热咀(预画 RZ 优先, 否则流道拐点兜底)→螺丝(预画 LS 优先, 否则左右板边中点向内 screw_in=15 兜底)→建 13 层/清理/统计自管全流程→**画完删 LD 源线**(与画图同一 UNDO 组, 一次 Ctrl+Z 找回)。process 级覆盖=整个流程由该模板函数自管, 不走内置流程。通用模板行为零变化。
- **假体包络法（`dt:jt-build`+`dt:jt-line`，offset v10.2~v10.2d，1348 行起）**：JT = **FLB 包络盒外扩 (hole-dist − offset-dist) 的圆角矩形**，四角 R=fillet_r_hole（圆角过大自动让位为直角）。替代旧五步启发式（LD偏移50→带状裁剪→断口圆角→延长→端点封口→封口圆角）。**旧法死因**（工字形实测, 通道间距 70≤D<100）：相向 JT 线互相落入对方 ±50 带区且平行无交点 → cut-curve "整线在区域内"分支整线删除；封口只认"LD 端点 ±50±tol"的端头, 组间断裂无法配对 → JT 碎裂。包络法手画答案逐点验证（flb_1.dxf：四边=FLB包络±15, 四角弧圆心=未倒角原角点）；内部通道（不达板边, 如工字形竖流道）由毛坯盘直接桥过。FLB 为空/外扩量 ≤1 时回退旧五步（旧函数全部保留, hole_extend 仅旧路径使用）。**v10.2b/c 三连修**：包络盒改用 dt:rect-bbox（内联 vla-getboundingbox 漏传引用参数恒失败→误回退, 坑 #56）；四角弧补 put-layer + **象限修正**（BR=270°→360°/TR=0°→90°/TL=90°→180°/BL=180°→270°, 此前每角画成隔壁角的弧与四边不接）；倒角计数 bug 修复（坑 #57）。**v10.2d**：四角圆角上限由"边长−1"改为与 rect-jt 同款的 0.45×短边（细长包络盒上四角弧会互相重叠）。
- 其余算法(偏移/裁剪/圆角几何/封口配对/螺丝 ref/假体延长)同 v8.16 一脉相承，详见历史备份文件内注释。

## 8. 关键数据结构（三套端点格式，勿混用！）

| 结构 | 形态 | 用于 |
|---|---|---|
| heads(圆角) | `(对象 "S"/"E" 端头点 指向主体方向)` | collect-heads/pair-heads/fillet-pair |
| ends(封口/封闭) | `(端点坐标 对象 "S"/"E")` | collect-ends/end-free/slot-close/close-pair |
| plate-ends(倒角/螺丝) | `(端点坐标 对象 "S"/"E" 指向主体方向)` | collect-plate-ends/find-touch |
| 延长记录 ext-rec | `(对象 端类型 原端头 新端头)` | slot-extend-fixed → slot-join |
| 命中记录 hits | `(对象 端类型 交点 宿主壁)` | slot-join 内部 |


## 9. 版本历史（v9.0 起；v1.0→v8.16 见 `offset_runner_v816.lsp` 文件头）

| 脚本 | 版本 | 变更 |
|---|---|---|
| offset | v9.0 | 出线槽拆分为独立 slot_runner；删 6 死函数+去重重构+精简注释（整理自 v8.16，逻辑零变化） |
| offset | v9.1 | 封口线收尾并层(FBX→FLB、JTFBX→JT 并删层)；"分流板挖孔"全部更名"分流板假体" |
| offset | v9.2 | 新增热咀圆(参数 nozzle_offset 40/nozzle_r 11.35，定位=封口线中点向内) |
| offset | v9.3 | 新增同心点孔圆(pin_r 3，设0不画) |
| offset | v9.4 | **图层全部拼音化**(LD/FLB/FBX/LS/JT/JTFBX/RZ/CX)；热咀与点孔拆为 RZ/DK 两层；新建 DP 垫片预留层 |
| offset | v9.5 | 参数框分组 RZ→"热咀和点孔"(中文)；ensure-layer 自动纠正图层大小写(dp→DP) |
| offset | v9.6 | 螺丝孔双同心圆(R4.25+R7)合并为单圆，参数单化 screw_r |
| offset | v9.8(a) | 多模板框架：通用/矩形模板(dt:off-template-table，矩形 process 级覆盖 dt:rect-process 自管全流程)+板角倒角参数；a 修 boundingbox 的 variant/safearray 绑定差异 |
| offset | v9.9 | 参数框按模板动态显示（同 jrt v9.9 模式） |
| offset | v10.0 | 矩形模板完善：螺丝内偏默认15(通用保持10)；画完自动删 LD 源线(与画图同撤销组) |
| offset | v10.1 | **参数默认值外置 offset_runner.ini**(按模板分节, 弹框前重读=随时生效)；参数记忆 offset_runner_mem.ini(按模板各一套, 确定自动保存, 上次模板+上次值跨会话恢复)；恢复默认 = ini 默认值 |
| offset | v10.2 | **假体重构为包络法**：JT = FLB 包络盒外扩(hole_dist−offset_dist)圆角矩形，四角 R=fillet_r_hole；修复工字形(通道间距 70≤D<100)旧五步 JT 互删碎裂(手画 flb_1.dxf 逐点验证)；链环/接合清理中间方案(约 270 行)被包络法替代删除；旧五步保留为回退路径 |
| offset | v10.2b/c | 修复实测三连：包络盒改用 dt:rect-bbox(引用参数漏传恒失败→误回退)；封口/端点收集跳过文字对象(圆角标注文字致 AcDbText 崩溃)；四角弧补图层+象限修正(每角画成隔壁角弧)；倒角计数陈年 bug(v6.0 起, 每封口线虚报 1 失败, 4 封口线恒报"失败 4 端"而几何全成功, flb_3 实测)统一为 (成功数,失败数) 并补 find-touch 失败分支标注 |
| offset | v10.4 | 包络法改分步绘制(步骤1 原始包络盒/步骤2 成品, 双撤销组观察)；c:OFF 恢复调用包络法(期间曾按用户要求短暂直跑传统五步) |
| 全部 | **发版 2026-08-30** | test\ 迁移至 CAD\ 根并删除 test\（4 .lsp + 3 ini + _audit.py 迁移; mem/dcl/old 不迁; acaddoc.lsp 钩子改指 CAD\）; 三个 ini 重写为逐参数中文注释版(GBK, 现值不变); README_CAD 重写为操作手册 |
| offset | **v10.2d** | **全面审查定稿**: ①参数框数值 atof→distof(垃圾输入不再静默当 0, 坑#54/#60); ②INI 中文节名解析改用"截到行尾再裁方括号"(修复 2021 前 strlen 字节/substr 字符不一致导致节名残留 "]"、配置节永远匹配不上, 坑#59); ③mem 文件不再重复写出第二个 [模板] 节(坑#62); ④补声明全部遗漏的 foreach/setq 局部(no/cl/seg/pt/obj/ln/p/…, 坑#61); ⑤闭合多段线判定补 vl-catch-all-error-p; ⑥假体包络矩形圆角上限改 0.45×短边; ⑦删死函数 dt:fix-layer-case 与未使用局部; ⑧修横幅版本号(v10.2→实际 v10.2c)与陈旧 slot_runner_v90.lsp 引用 |
| offset | **v10.5** | **假体改人工决策**：参数框新增勾选框「假体用包络法」(默认不勾=传统逐步直跑)；默认值外置 ini [假体] envelope(旧 ini 自动追加该节, 不动用户已改值)；确定才记忆(mem [假体] 节), 恢复默认=ini 值；勾选但包络失败不静默回退(明确提示无假体)；dt:jt-build 撤分步观察恢复单撤销组 |
| offset | **v10.6** | **健壮性修复(几何零变化)**: ①非曲线实体防护补全 —— 新增 dt:curve-p/dt:curves-only, LD 源图层混入文字/块时 close-channels/extend-ends 不再崩, FBX/JTFBX 上的历史失败标注文字不再使 chamfer-close/fillet-close/drill-holes 独立重跑崩溃, collect-heads/trim-all/fillet-all 同步过滤(v10.2b 只修了封口侧, 本次补全); ②cut-params 多段线分支 getparamatpoint 包 catch+剔 nil 再排序(nil 进 vl-sort 报错); ③对话框 load_dialog/start_dialog 包 catch 且保证 unload_dialog; ini 句柄异常兜底关闭(含 boot 的 [假体]节追加写); ④c:OFF 的 *error* 兜底闭合 UNDO 组; ⑤参数应用负值回退当前值; ⑥cross-points 包围盒预过滤(bbox 不相交跳过 COM 求交, 大图提速, 结果不变) |
| slot | v9.0 | 自 offset_runner 独立(逻辑零改动)，命令 SLOT/SLOTPARAM，CX 源线+壁同层 |
| slot | v9.1 | 图层"出线槽"→CX |
| slot | v9.2 | 参数框分组标题→"基本设置" |
| slot | v9.3 | 大圆角重构：延长收头到第一交点(修复 v8.15"冲过头") + 交点配对圆角 |
| slot | v9.4 | 尝试"前进方向张角外角侧"定位(方向仍错，废弃) |
| slot | v9.5 | **方向定案**：大圆角=小圆角同款 fillet-pair 仅换 R30，nochk=T(用户实测确认) |
| slot | v9.6 | 新增敞口封闭线(3 处验证)+ 完成后删除全部源线 |
| slot | v9.7 | 修复 slot-close 端点格式错误(ends vs heads，弧对象当点崩溃) |
| slot | v9.8 | **dt:write-dcl 改名 dt:slot-write-dcl**：与主脚本同名不同体，三脚本同加载互相覆盖致对话框错乱(坑 #46) |
| slot | v9.9 | 新增 CXK：距 DP 最远的封闭线自动移入 CXK 层(蓝5)，DP 空则跳过 |
| slot | v10.0 | **参数默认值外置 slot_runner.ini**(固定节[参数]) + 参数记忆(确定自动保存, 跨会话预填)；恢复默认 = ini 默认值 |
| slot | v10.2 | **大小圆角自动适配**(用户要求): fillet-pair 重构为"每候选半径同时过线长+方向两关"统一递减(>2 步长1/≤2 步长0.5/下限0.5) —— 旧版两关分开, 小圆角方向全堵即失败不试小半径; 自动适配成功标 "R<n>自动", 递减到底仍失败标 "圆角失败"文字(小圆角/大圆角/T形三分支); CX 层标注文字类型防护(slot-curve-p 过滤 collect-heads/collect-ends/延长); slot-join Pass2 整体重写(修多轮修补遗留括号错位 "no function definition: nil" 崩溃)+单接合 vl-catch-all 诊断(意外错误降级为标注继续) | **←已整体回退, 用户实测同板恢复大圆角 4 处成功(R120)**。0/0 的真因不是判定规则, 是重建版 slot-join 括号"全局配平但嵌套错位"(闭合提前吃掉 cond/lambda/foreach, 转角与 T 形分支成死代码, 圆角逻辑从未执行且不崩溃不报错, 表面就是安静 0/0) —— 判定逻辑 v10.1 与重建版逐字一致, 差异纯在结构(坑 #44 二次事故)
| slot | **v10.1** | **全面审查定稿**(与 offset v10.2d 同期): ①atof→distof; ②INI 节名解析修复(坑#59); ③补声明遗漏局部; ④闭合多段线判定补错误检查; ⑤敞口封闭去重改双向比较(反向命中不再画重复封闭线); ⑥延长收头存活检查失败时不再整批跳过(否则"收头+大圆角"整体静默失效); ⑦ini 配置补中文注释(与 offset/jrt 一致, 新增 dt:slot-param-labels); ⑧删未使用的 exclude 形参与死局部; ⑨改文件头旧图层名"出线槽通道"(触发 check_lisp 死名告警) |
| slot | **v10.3** | **健壮性修复(几何零变化; 版本号跳过已废弃的 v10.2)**: ①**补回 v10.2 随整版回退丢失的标注文字类型防护** —— collect-heads/collect-ends 按新增 dt:curve-p 过滤, 各图层收集(slot-trim/fillet-all/extend-fixed/join)走 dt:curves-only, 修"小圆角 R 递减 → CX 层写 Rn 标注 → 后续延长/大圆角/封闭对文字求端点必崩"链; ②dt:fillet-pair 改名 **dt:slot-fillet-pair**, 缺省层/缺省半径由 offset 的 "FLB"/*dt-fillet-r* 改为本脚本 "CX"/*dt-slot-fillet-r-small*(消除跨脚本隐藏耦合, 坑 #46); ③cut-params getparamatpoint 包 catch+剔 nil; ④对话框 load/start_dialog 包 catch+保证 unload, ini/dcl 句柄兜底关闭; ⑤c:SLOT 的 *error* 兜底闭合 UNDO 组; ⑥参数应用负值回退; ⑦cross-points 包围盒预过滤(新增 dt:rect-bb-pts/dt:rect-bbox/dt:bbox-overlap-p 库副本); ⑧删重复注释块 |
| jrt | v9.5 | **新增独立脚本**：LD±29 三层嵌套加热条轮廓、交汇裁剪+圆角、端帽按 gap 判定(RZ 圆帽/直线帽) |
| jrt | v9.6~v9.8 | 端帽/圆角参数化(jrt_cap_r/jrt_fillet_r 19)、内层数可调(jrt_inner_count)、多模板框架(dt:jrt-template-table+模板对话框)；详见 jrt 文件头 |
| jrt | v9.9 | 新增"两点式"模板(JRT 源线+JRTDW 定位线内偏嵌套) |
| jrt | v9.10 | 模板更名 通用→通用一、两点式→通用二；通用二扩写出线口 |
| jrt | v9.11 | 出线口修正：壁裁剪保留 cap 侧/裁 pint 侧 |
| jrt | v9.11b | find-dcl 弃用旧 findfile 候选链(v95~v98 文件名已不存在)，统一 *dt-script-dir* 确定性模式（与 offset/slot 对齐） |
| jrt | v9.12 | **参数默认值外置 jrt_runner.ini**(按模板分节) + 参数记忆(按模板各一套, 上次模板+上次值跨会话)；恢复默认 = ini 默认值 |
| jrt | **v9.13** | **全面审查定稿**(与 offset v10.2d 同期): ①atof→distof; ②INI 节名解析修复(坑#59); ③mem 文件不再重复写出第二个 [模板] 节; ④补声明遗漏局部(dt:jrt-decide 的 o、dt:jrt2-neck 的 p/sgn/wx、dt:jrt2-junction 的 t2 等); ⑤闭合多段线判定补错误检查; ⑥移除出线口相交处的遗留【调试】输出; ⑦更陈旧注释(两点式→通用二、参数项数) |
| jrt | **v9.14** | **健壮性修复(几何零变化)**: ①LD 源图层混入文字/块不再崩溃 —— c:JRT 取 LD 后统一 dt:curves-only 过滤(原 dt:jrt-touch-p/jrt-free-ends 对全量 LD 对象直接求端点, 无 catch 无过滤), jrt-trim/jrt-fillet 的 LD 引用同步过滤; ②cut-params getparamatpoint 包 catch+剔 nil; ③对话框 load/start_dialog 包 catch+保证 unload, ini/dcl 句柄兜底关闭; ④c:JRT 的 *error* 兜底闭合 UNDO 组; ⑤参数应用负值回退; ⑥cross-points 包围盒预过滤(新增 dt:rect-bb-pts/dt:rect-bbox/dt:bbox-overlap-p 库副本, collect-heads 按 dt:curve-p 过滤) |
| dt_start | v1.0~v1.3 | 一键加载/自启动引导器：v1.1 修四段 if+正式版优先；v1.2 修 digits 取位差一；v1.3 加 DTDBG 诊断 |
| dt_start | v2.0 | 重构：acaddoc 钩子显式 `(dt:st-init "<目录>")` 注入 *dt-script-dir*，治多副本定位错乱/stringp |
| dt_start | v2.1~v2.3 | **顶部菜单模块「热流道自动化(R)」**二级分组(分流板/出线槽/加热条/工具/关于)：2024 移除 MenuGroups.Add(坑 #50)→改 ACAD 主菜单组塞 popup；会话内只建一次+同名残留复用 |
| dt_start | v2.4~v2.5 | 菜单宏定案(坑 #51~#53)：chr(3) 真取消码 + 全 LISP 表达式宏 + 尾空格=回车 → 点击即执行 |
| dt_start | **v2.6** | **老版本兼容并入正式版**: TRUSTEDPATHS 的 getvar/setvar 包 vl-catch-all(该变量 2016 才引入, 2007~2015 静默跳过)。**正式版与 old\\dt_start.lsp 合并为一份、全版本通用**, 不再需要按 CAD 版本挑文件(两份现逐字一致)。**(v2.9 修正: catch 只挡"抛异常"、挡不住"静默返回 nil", 老版本实际仍会崩, 见坑 #65)** |
| dt_start | **v2.8** | acaddoc.lsp 钩子读/写中途异常兜底 close(句柄不滞留, 与 offset v10.6 / slot v10.3 / jrt v9.14 同期健壮性收尾); 其余逻辑零变化(版本号 2.7 未对外发布, 直接顺延) |
| dt_start | **v2.9** | **低版本「参数类型错误: stringp nil」根因修复(坑 #65, 用户 2007 实测 DTINSTALL 报错)**: 老版本 getvar 读本版本没有的变量**静默返回 nil**(非抛异常), nil 流进 strcat/strlen 即炸。新增 `dt:st-gets`/`dt:st-hasvar`/`dt:st-support-root` 兼容底座(抛错/nil/非字符串统一返回 ""), 封死三处泄漏点 —— st-trusted-add/del(TRUSTEDPATHS, 2007~2015 命中)、st-acadoc-path + st-write-hook(ROAMABLEROOTPREFIX)、st-locate(DWGPREFIX); st-split 补 null 返回; st-add-support 加 front 参数(支持根不可用时 acaddoc.lsp 兜底写脚本目录并置顶支持路径); DTINSTALL 改序(先加支持路径 → 再写钩子 → 再 TRUSTEDPATHS)并打印 ACADVER/支持根/变量可用性; DTDBG 加 `[0z]` 环境探测段。新增 `tools\check_sysvars.py` 门禁(反向验证: v2.8 命中 5 处风险, v2.9 全过) |
| 全部 | **编码补丁 2026-08-31** | **用户 2007 实测加载报「输入中的点位置不正确」, 定案坑 #64**: ≤2020 的 MBCS(GBK) LISP 读取器读 UTF-8 文件必炸(双字节吞字符, 报错位置与真实问题无关)。新增 `tools\make_ansi.py` 发版工具 + `scripts_ansi\` GBK 副本目录(说明.txt 同目录), §2.3 兼容表改双轨: 2007~2020 用 GBK 副本 / 2021+ 用 UTF-8 原版; 代码零改动(仅注释/提示文字 4 个符号替换) |
| 全部 | **低版本补丁 + 2007 实测 2026-08-31** | **2007 上 DTINSTALL 报「参数类型错误: stringp nil」, 定案坑 #65**: 与编码无关(两份 dt_start.lsp 逻辑逐字相同, 仅注释装饰符号差异), 根因是 getvar 静默 nil, 见上方 v2.9 条目。**修完用户 2007 实测通过**: GBK 副本 APPLOAD → DTINSTALL 一次成功 → 三脚本加载 + 顶栏菜单挂出。至此 2007~2026 全链路打通(2007 无 TRUSTEDPATHS, 安装时打印"无(老版本, 跳过)"属正常) |
| size | **v1.0** | **新增独立尺寸测量脚本 (size_runner.lsp v1.0, 500行, 19 defun)**：架构解耦，建立第 4 独立脚本，与 offset/slot/jrt 形成 4 家族等价架构。支持：①FLB 图层自动探测与提取；②双引擎闭合判定(vla-AddRegion + 0.5mm 容差端点拓扑度数)；③未闭合自动转入手动框选模式，手动选线未闭合明确告警并取消；④AABB+OBB 最佳外接矩形求最长与最宽；⑤自动写入 Windows 剪贴板(如 350x180)；⑥交互式确认后在 FLB_BOX 专用图层绘制外包矩形及字高≥15 的长宽标注；⑦顶栏菜单在出线槽之后挂载「测量数据(&M) ▸ 测量分流板(&F)」 |
| wx | **v2.0** | **升级外协加工与数据测量工具箱 (wx_runner.lsp v2.0, 1092行, 39 defun)**：更名自 size_runner，架构融合，支持：①线切割出图 (c:XQG)：FLB 双引擎闭合检测/手动框选，全自动按当前系统年月生成子目录与日期命名 (如 26\09\09.04.dwg)，已存在时回车默认追加平铺/输入N自动递增新建 09.04_1.dwg，免弹窗直达目标，AABB 向右平铺(50mm 间距)防覆盖，MText 宽度设限自动折行(2~X行)居中标注原图纸名；②精雕出图 (c:JD)：仅提取热流道脚本生成的自动化图层白名单曲线 (FLB, LS, RZ, DK, JRT)，彻底排除 CX/JT/FBX 等无关曲线，同规则自动命名/递增克隆至精雕目标 DWG 并向右平铺，MText 折行标注图纸名(宋仿黑/Standard 字体探测降级)；③数据图纸 (c:SJTZ)：白名单图层提取，支持鼠标自由拖动或输入位移交互式复制，图形右侧+30 处生成规范化双列信息文本块，列间距扩大至 95mm 彻底消除重叠，无空格系统日期 (YYYY.M.D)，客户/中心距/热咀/出线留空不弹窗打扰；④新增 `wx_runner.ini` 配置文件支持自定义各分支保存根路径 |
| dt_start | **v3.0** | **顶栏二级菜单重构 (dt_start.lsp v3.0, 762行, 30 defun)**：将「测量数据(&M)」升级为「外协加工(&W)」，下挂 4 个三级子项：测量分流板(&F) / 线切割(&W) / 精雕(&J) / 数据图纸(&D) |
| offset | v10.6 | 纯洁分流板生成职责，剥离测量逻辑，维持 2576 行，98 defun |
| flb | **v10.7** | **全系统名称对齐重命名 (flb_runner.lsp v10.7, 2582行, 100 defun)**：offset_runner.* 更名为 flb_runner.* (lsp/ini/dcl/mem)；主命令升级为 FLB/FLBPARAM，保留 c:OFF 与 c:PARAM 兼容别名；内部函数与变量全面迁移为 dt:flb-* 与 *dt-flb-*；引导器菜单宏与检查清单同步对齐 |
| cx | **v10.4** | **全系统名称对齐与参数修复 (cx_runner.lsp v10.4, 1498行, 70 defun)**：slot_runner.* 更名为 cx_runner.* (lsp/ini/dcl/mem)；主命令升级为 CX/CXPARAM，保留 c:SLOT 与 c:SLOTPARAM 兼容别名；内部函数与变量迁移为 dt:cx-* 与 *dt-cx-*；修复 DCL 控件 key 遗留为 slot_* 导致的参数框不显示与恢复默认失效，全量对齐为 cx_* |
| wx | **v2.1** | **外协加工与数据图纸全量体验加固 (wx_runner.lsp v2.1, 1102行, 41 defun)**：①平铺间距翻倍至 150.0mm；②线切割与精雕字高设为 15.0；③新增 `dt:sz-format-multiline`，解决工业连字符文件名 (如 SL-26142-RLD-PC+ABS-9.1) 无空格时不自动折行的问题，按符号断句并注入 \P 实现多行居中；④彻底根除「读取形文件 simsun.ttc 时出错」：严禁 put-fontfile 绑定 ttc 路径，改用 COM 原生 vla-setfont 134/34 绑定宋体，大字体兜底；⑤首图新建 was-closed 标 T，确保保存后物理关闭刷盘，首张图纸上方立刻带文字；⑥数据图纸 c:SJTZ 重构为单一整体 vla-addmtext 多行文字图元，双击可一次性直接修改所有空缺数据 |


## 10. 已知坑 / 经验教训（v9.x 新增；v1.0~v8.16 的 28 条详见 `offset_runner_v816.lsp` 文件头，核心条目仍有效：纯 COM/求交用 vla-intersectwith/BOM 编码/无默认参数/圆弧端点只读/切点沿曲线/劣弧/vla-offset 继承图层/eName 比较/延长方向指向线外/边遍历边删/括号 stack 校验）

29. **AutoCAD 图层名不区分大小写**：已存在小写 dp 时 tblsearch 命中而跳过创建——ensure-layer 需自动纠正大小写。
30. **延长接头处区域方向验证失效**：交叉接头两源线区域重叠，"圆心入区换方向"有效；延长接头区域不重叠，正确圆心可能恰在带状区内被误拒→大圆角须 nochk=T 用 b1。
31. **三套端点记录格式不可混用**（heads/ends/plate-ends，见第 8 节）——v9.6 把 heads 传给 end-free 致弧对象当点崩溃。
32. **replace_all 会波及新函数自身定义**（dt:ms 自递归事故）；**Read 工具对 >100 字节长行折行导致行号偏移**，行号以 grep 为准。
33. **DXF 复算法定位几何问题**：用户提供 SAVEAS 2007 DXF + 手画正确基准 → 解析坐标 → 用候选公式复算对比偏差(手画容差~3-5) → 确认规则后再改代码。
34. **python 写文件前必须完成全部计算**：`open('wb')` 即截断文件，中途异常会留下空文件。
35. **机器上只保留一份在用脚本**（每脚本一条版本链）；find-dcl 候选链按"无版本号→最新→次新"排列，新版本交付时插链首；**正式投用版无版本后缀，dt_start 优先加载正式版**。
36~43.（历史条目，见 AGENTS.md）
44. **手抄/复制长函数体必须脚本 diff 验证**：整体括号平衡=0 掩盖局部函数缺括号。逐 defun 括号扫描+同名函数规范化 diff 双重校验。
45. **脚本按括号平衡切块替换前必须先验证源块结构**：目标函数本身缺括号时"平衡终点"会越过函数尾吞掉后续代码。先验证再动文件。
46. **多脚本同加载时同名不同体的函数互相覆盖**（v9.8 slot write-dcl 事故实锤）：新增/维护自包含脚本时先 diff 与各旧脚本的共享名，凡函数体有差异的一律改名隔离。
47. **AutoLISP 的 if 只允许"测试/则/否则"三段**，四段运行时报"语法错误"（dt_start v1.0 事故）；多动作必须 progn 包裹。check_lisp 已内置 if 参数超限检查。
48. **代码区混入全角字符（括号/引号/│等）报"语法错误"而括号计数查不出**：check_lisp 已内置代码区非 ASCII 检查。
49. **CAD 会话污染"幽灵错误"**：磁盘文件已修好仍报旧错=会话内存驻留旧定义（2026-08-21 stringp 事故、dt_start 调试期同现）→ 完全退出 CAD 重开；怀疑磁盘侧再用 DTDBG 的 findfile 候选打印排查支持路径里的来路不明旧副本。
50. **AutoCAD 2024 类型库移除 MenuGroups.Add**（报"未知名称: Add"，v2.1 实测）：程序化自建菜单组此路不通 → 改往 **ACAD 主菜单组**的 PopupMenus.Add 塞 popup（可用）。但 ACAD 组内 popup 的 **Delete 被拒**（静默失败）且**不跨会话持久** → 对策：会话内只完整构建一次(`*dt-st-menu-done*`) + 构建前 `vla-item` 按名查同名残留直接复用；重启 CAD 天然干净，不会累积垃圾。
51. **COM 通道菜单宏不经 MNU/CUI 文件解析器**（v2.3 实测"未知命令 ^C^C(...)"）：`^C^C` 只是 MNU/CUI **文件**里的记号，导入时才翻译成控制字符；ActiveX Macro 属性直塞的字符串点击时**整串字面量**进命令行 → 取消码必须用真控制字符 `(chr 3)`。
52. **COM 菜单宏播放器不自动补回车**（v2.4 实测）：点击后文本停在命令行等手按回车 → 宏尾必须补一个**空格**（菜单宏语法：空格=回车）。
53. **菜单宏统一包 LISP 表达式 `(c:命令名)`**：LISP 表达式提交即求值，不依赖命令名回车语义，规避 #51/#52 的残留不确定性；三件事全部收敛在 `dt:st-macro` 一处构造（chr3+chr3+表达式+空格），改宏只动它。
54. **AutoLISP 文本 IO 无编码参数（按系统 ANSI/GBK 读写）**：`.ini` 配置/记忆文件的键值行保持纯 ASCII，中文只放注释行——用户记事本误存 UTF-8 时仅注释乱码，解析不受影响。数值校验必须用 **distof 而非 atof**（atof 对垃圾串返回 0，会把 `abc` 静默当 0；distof 返回 nil 可识别非法）。值 0 是合法参数（pin_r=0 不画点孔），"键存在但值为 0" 与 "键不存在" 靠 **0 非 nil** 的 LISP 真值语义区分，不要用 `/= v 0` 判存在性。
55. **带状裁剪+端点封口的假体算法在"通道间距 < 2×假体偏移"时必然碎裂**（工字形 70≤D<100 实测）：相向偏移线互相落入对方带区且平行无交点 → "整线在区域内"分支整线删除；断口只发生在有交点处, 平行相向对之间连断口都没有; 封口又只认"LD 端点±50±tol"的端头 → 组间豁口无法闭合。**修复 = 改变问题定义**：假体的本质是毛坯盘外形(=FLB 包络盒外扩), 不是通道带的拼合 —— 手画答案(flb_1.dxf)逐点验证后改包络法(v10.2), 中间方案"链环+逐段外偏+接合清理"(约 270 行)已完成大半仍被删除重写。教训：几何规则拿不准时先让用户给手画基准 DXF 复算(坑 #33), 且"能跑的复杂方案"若与手画答案有系统性偏差, 应回头质疑问题定义本身。
56. **vla-getboundingbox 是引用参数调用**：必须 `(vla-getboundingbox o 'mn 'mx)`, 经 vl-catch-all-apply 时传 `(list o 'mn 'mx)`；漏传引用参数不报编译错、运行时恒失败——若外层有"失败回退"逻辑就会静默降级（v10.2 包络法误回退实测, 用户日志只看到"不可用"看不到真实原因）。取包络盒一律复用 **dt:rect-bbox**（v9.8a 双绑定兼容实现）, 不要内联重写。
57. **多函数协作的返回值语义必须统一**（chamfer-one v6.0~v10.2b 陈年计数 bug, flb_3 实测定案）：chamfer-one 正常路径返回 (起点成功数, 终点成功数), chamfer-close 把第二个数当失败数累加 → 每条封口线虚报 1 失败, 4 条封口线恒报"失败 4 端"而几何 8 端全成功。**日志异常时先用产物几何对照**（数一数倒角斜线数量）再动算法。同函数 find-touch 失败分支曾静默(不标注不计数)——"失败必须可诊断"：每个失败分支都要标注+计数。
58. **包络矩形四角弧的象限**：右下=270°→360°、右上=0°→90°、左上=90°→180°、左下=180°→270°（每弧从接一边扫到接另一边, 短弧 ≤90°）; 错一格弧就悬空不接边且极难肉眼定位（v10.2 初版实测, 用户截图才发现）。新增圆角矩形一律照抄 dt:rect-* 的同款映射, 不要重推。
59. **AutoCAD 2021 前后 strlen/substr 对中文的口径不一致**（v10.2d 审查发现）：2021 起是 Unicode LISP，`strlen` 按**字符**计；2021 前是 MBCS，`strlen` 按**字节**计，而 `substr` 两种都按**字符**计。旧写法 `(substr ln 2 (- (strlen ln) 2))` 解析 INI 节名时，在老版本上 `[通用]` 会被截成 `通用]`（多带一个 `]`）→ 节名永远匹配不上，`offset_runner.ini` / `jrt_runner.ini` 的配置**静默失效**（不报错，只是回退内置默认，极难察觉）。**一律改用 `(vl-string-trim " \t[]" (substr ln 2))`** —— 截到行尾再裁方括号，两种口径都正确。同理：凡"按长度截字符串"的地方都要避开 strlen 与 substr 混用。
60. **对话框数值读取必须用 distof，不能用 atof**（v10.2d 审查发现）：三个脚本的 `get-num` 原为 `(if (and s (/= s "") (numberp (atof s))) (atof s) def)` —— `atof` 对垃圾串返回 0.0、`numberp` 恒为 T，所以在参数框里误输 `abc` 会**静默把该参数改成 0**（偏移距离=0 画出退化几何、点孔半径=0 不画）。坑 #54 只在 INI 解析里落实了 distof，对话框这条漏了。现改为 `(distof s)` 返回 nil 即回退默认值。
61. **AutoLISP 是动态作用域，漏声明的局部会变成全局并可能被别处改写**（v10.2d 审查发现，共 40 余处）：`foreach`/`setq` 绑定的符号若没写进 `(defun name (args / 局部...) ...)`，就会泄漏为全局变量。本次实测泄漏的有 offset 的 `no`（包络四角弧）/ `cl`（三处 foreach）/`seg`/`pt`/`obj`/`ln`/`p`/`tpl`/`s`/`c`/`l`，jrt 的 `o`（dt:jrt-decide）/`t2`（dt:jrt2-junction）/`p`/`sgn`/`wx`/`pa`/`pb`/`bar`/`pair`/`rec`/`kv` 等。虽然当前调用链没有触发实际冲突，但动态作用域下**任何一层嵌套调用都可能读到被污染的值**。新增/修改函数后务必跑 `test\_audit.py` 第 3 项核对（该项已排除 `*xxx*` 全局与常量 nil/T）。
62. **"读进来的数据再写回去"必须先剔除控制键，否则会自我复制**（v10.2d 审查发现，`offset_runner_mem.ini` 实测已复现两个 `[模板]` 节）：`dt:off-mem-save` / `dt:jrt-mem-save` 先单独写 `[模板]` 节，再遍历 `*xxx-mem*` 写出各模板节 —— 而该表是刚从 mem 文件读回来的，**本身就含 `[模板]` 节**，于是被再写一遍（第二个值的格式还不同：`itoa` vs `rtos`）。去重靠"读时按节名覆盖"兜住了功能，但文件持续脏。修法：遍历时 `(if (/= (car sc) "模板") ...)` 跳过控制节。
63. **文字/块等非曲线实体混入源图层或产物图层 = vlax-curve 全家崩**（v10.6 全面补全）：`vlax-curve-getstartpoint/getparamatpoint` 等对 AcDbText 直接抛"参数类型错误"，且大多不在 catch 内。历史三次事故同根：v10.2b 只修了 offset 封口/端点收集侧；slot v10.2 曾加 slot-curve-p 全套防护但**随 v10.2 整版回退丢失**（v10.1~v10.3 期间"小圆角半径递减 → fillet-pair 在 CX 层写 Rn 标注 → 后续延长/大圆角/封闭对文字求端点必崩"为活性缺陷）；jrt 的 touch-p/free-ends 一直无防护。**定案**：三脚本统一 `dt:curve-p`/`dt:curves-only`，凡 collect-heads/collect-ends/图层全量迭代一律先过滤（新增收口点必须过 _audit 第 1 项同名同体核对）；`getparamatpoint` 必须包 catch 并剔除 nil 再进 vl-sort。另两条例程：文件 open/close 之间必须异常兜底关闭（v10.6/v2.8 定案的双 catch 收尾写法）；局部 `*error*` 应兜底闭合 UNDO 组（`vl-catch-all-apply '(lambda () (command "_.UNDO" "E"))`，无开放组时无副作用）。
64. **≤2020 的 AutoCAD 是 MBCS(GBK) LISP，读 UTF-8 文件必炸**（2026-08-31 用户 2007 实测）：报「错误: 输入中的点位置不正确」——UTF-8 中文字节被逐字节读取器当 GBK 双字节字符吞掉后面的换行/引号/括号/点号，读取在文件中途就死（横幅不打印），报错位置（点对）与真实问题（编码）毫无关系，极难排查。**此前"全版本通用一份文件"的结论只对 API 成立，对文件编码不成立**。对策：`python tools\make_ansi.py` 生成 `scripts_ansi\` GBK 副本发 2007~2020，`scripts\` UTF-8 原版发 2021+；工具含逐字节读取器模拟校验（字符串/括号结构与原件逐项一致）。注意 GBK 双字节第二字节可为 0x5C，理论上字符串尾部"汉字+\"+引号"会被吞——本工具的结构比对正是为此兜底；文件头注释声明"必须 UTF-8 with BOM"只对 2021+ 为真，2020- 用副本后该声明自然满足（副本是 GBK 无 BOM）。
65. **老版本 `getvar` 读本版本不存在的系统变量时静默返回 nil，不是抛异常**（2026-08-31 用户 2007 实测 `DTINSTALL` 报「参数类型错误: stringp nil」定案）：v2.6 给 TRUSTEDPATHS 做的兼容只包了 `vl-catch-all-apply`，**只挡住"抛异常"那半边**；而 2007~2015 上没有 TRUSTEDPATHS（2016 才引入）时 `getvar` 直接返回 nil，`(vl-catch-all-error-p nil)` = nil 于是继续往下走 → `(dt:st-path-list nil)` → `(dt:st-split nil ";")` → `(strlen nil)` → 崩溃。**崩溃点在字符串函数里，报错信息不含任何中文提示，也不指向真正的源头（系统变量），排查成本极高**。同类隐患共三处：`TRUSTEDPATHS`（2007~2015 必中）、`ROAMABLEROOTPREFIX`（2006+ 才有，极老版本/部分国产 CAD 没有）、`DWGPREFIX`（无图纸打开时部分版本返回 nil）。**定案写法**：
   - 统一收口到 `dt:st-gets`（取系统变量，抛错/nil/非字符串一律返回 `""`）+ `dt:st-hasvar`（判存在），全文件**禁止裸调 getvar**；
   - `dt:st-split` 等字符串工具函数入参为 null 时直接返回 nil，做二次兜底；
   - 支持根（ROAMABLEROOTPREFIX/LOCALROOTPREFIX）取不到时，`acaddoc.lsp` 兜底写进脚本目录，且必须把该目录**顶到支持路径最前** —— AutoCAD 只加载搜索路径里**第一个** acaddoc.lsp，不置顶兜底那份永远不生效；
   - `DTINSTALL` 顺序改为：先加支持路径 → 再写钩子 → 再处理 TRUSTEDPATHS（顺序错了兜底那份就不会被搜到）。
   - **门禁**：`python tools\check_sysvars.py` —— 版本相关变量未走 `dt:st-gets`/`dt:st-hasvar` 即报警，且 getvar 结果直接作 strcat/strlen 实参即报警。反向验证有效：v2.8 命中 5 处风险（正好覆盖三个根因），v2.9 全过。
   - **排查心法**：老版本上出现 `参数类型错误: stringp nil`，先怀疑"系统变量返回 nil"，而不是崩溃点那一行代码本身 —— 报错位置与根因常常不在同一个函数。用 `DTDBG` 的 `[0z]` 段一眼看清哪些变量本版本没有。

66. **TrueType 字体严禁使用 `vla-put-fontfile` 绑定 `.ttc`/`.ttf` 路径**（2026-09-04 用户报错实测）：AutoCAD 的 `FontFile` 属性**专用于 SHX 形文件**。若将系统字体文件路径（如 `C:\Windows\Fonts\simsun.ttc`）赋值给 `FontFile`，AutoCAD 在模型重生成 (REGEN) 时会强行以 SHX 二进制头解析，报错「读取形文件 ... simsun.ttc 时出错」，并使文字样式退化为空心线框甚至干扰视口图元。**正确做法**：使用 AutoCAD COM 原生接口 `(vla-setfont st "宋体" :vlax-false :vlax-false 134 34)`（字符集 134=GB2312, 34=变宽），绝不触碰 `FontFile`；降级时再赋给 `txt.shx` + `gbcbig.shx`。
67. **AutoCAD MText 遇到无空格的长连字符串绝不自动断行**（2026-09-04 用户出图实测）：工业零件与图纸命名（如 `SL-26142-RLD-PC+ABS-9.1`）通常用 `-`、`_`、`+` 连接，全串无空格。AutoCAD MText 引擎将无空格字符串视作单一「单词」，宁可宽度溢出也绝不断开。**解决**：编写 LISP 智能断句函数（`dt:sz-format-multiline`），检测长串并在符号处分段、主动注入 MText 原生换行符 `\P`；配合 `acAttachmentPointBottomCenter`（底部居中）实现多行严格居中悬停于工件正上方。同时，后台新建目标图纸时必须设 `was-closed T`，确保图元文字写入后 `vla-close` 物理刷盘，否则首图在磁盘未闭合滞留于内存不可见。

## 11. 接手流程

1. **备份**：改动前把要动的原件 `cp` 到 CAD\ 外的临时目录（用完即删）——**勿在 CAD\ 内留第二份 .lsp**（坑 #35/#49 多副本误载）。
2. **改代码**：精确 Edit，replace_all 后必须通读复核（坑 #32）；新代码传参前核对数据格式（坑 #31）；**新增/修改函数后跑 `_audit.py` 核对局部变量声明（坑 #61）**。
3. **版本**：新文件 `*_v<N><M>.lsp`（正式投用版去后缀），版本号写进 文件头/横幅。
4. **校验**：`python tools\check_lisp.py scripts\<文件名>`（自动区分 offset/slot/jrt/dt_start 四清单）；**改到系统变量读取时必跑 `python tools\check_sysvars.py`（坑 #65 nil 泄漏门禁）**；深度排查另跑 `python tools\_audit.py`；同名一致性 `python tools\_collide.py`（在 scripts\ 目录下跑）。
5. **生成编码副本（发版必做）**：`python tools\make_ansi.py` —— 重新生成 `scripts_ansi\` 并自动做逐字节读取器结构校验，车间 2007~2020 老机器部署只认这份副本；
6. **文档**：用户明确要求时才更新（默认不动）；CAD 侧改动更新 `AGENTS_CAD.md`/`README_CAD.md`（版本号、行数、defun 数、行号、函数清单、版本历史要同步，否则文档会持续失真）。
7. **测试**：让用户 APPLOAD（或 DTRELOAD）后跑 OFF/SLOT/JRT/FLBSZ；几何问题优先要 **截图+DXF(2007)**，用坑 #33 的复算法定位；对话框/加载类疑难用 DTDBG。
8. **发布**：2026-08-30 起脚本目录即正式目录（C:\Users\5600\Documents\ZDH\CAD\，test\ 已删除）——在本目录改完、**check_lisp 全绿 + check_sysvars 全过 + make_ansi 生成成功** + 用户 CAD 实测通过即为发布（2007~2020 用 scripts_ansi\ 副本覆盖后验证）; .dcl/ini 运行时自管, 无需同步动作。
9. **低版本验证清单（2007~2015 尤其要跑）**：① APPLOAD 无「输入中的点位置不正确」（编码，坑 #64）② `DTINSTALL` 无「stringp nil」且打印出 ACADVER/支持根/变量可用性（坑 #65）③ 顶栏菜单出现且点击可执行 ④ OFF/SLOT/JRT 各跑一次 ⑤ 重启 CAD 自动挂载 ⑥ `DTUNINSTALL` 能干净还原。
