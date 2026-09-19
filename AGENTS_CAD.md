# AGENTS_CAD.md — AutoCAD 流道分流板脚本（AI 接手文档）

> 本文档供接手本项目的 AI 使用（**仅 AutoCAD 侧**；NX 侧工具在独立仓库/项目，不在本目录）。包含完整的技术细节、函数清单、算法、版本历史、已知坑与接手流程。**改代码前请先通读本文档。**
> 编码协作契约（铁律、门禁命令、红线）见根目录 `AGENTS.md`；仓库首页总览见 `README.md`；用户操作手册见 `README_CAD.md`。



---


## 1. 项目概览

| 项 | 内容 |
|---|---|
| 工作目录 | `C:\Users\5600\Desktop\ZDH\HYT-CAD\`（仓库根目录，2026-09-16 实测；旧记 `Documents\ZDH\HYT-CAD` 本机不存在），Git 远程 `xlzxld/HYT-CAD`；2026-08-30 发版并分类：**`scripts\` = 6 .lsp 入库 + ini/dcl 运行生成物(脚本启动/弹框时自动再生, 2026-09-09 起移出仓库不入 git)合成一个运行单位**；`scripts_ansi\` = 6 个老版本 GBK 编码脚本副本(供 2007~2020 老电脑使用, 坑 #64)；`tools\` = check_lisp/\_audit/\_collide/make_ansi/check_sysvars/check_defun_depth/check_audit_fixes/test_direction/check_jrt2_out/check_layer_colors/\_aci_colors/**deploy_old_pc**（生成本仓一键移植包，见 §11 第 6 步）；根目录 = 5 份 md(README 首页总览 / README_CAD 操作手册 / AGENTS 协作契约 / AGENTS_CAD 本文件 / CHANGELOG 版本历史) + **`一键生成移植包.bat`（双击即出老机移植包，= make_ansi + check_lisp×6 + deploy_old_pc）**；`.agents\` 下另有 AUDIT-SPEC / BOOTSTRAP 两份契约外置件。自启钩子指向 scripts\dt_start.lsp） |
| 改前备份 | 无固定目录（原 test\pc\ 已随发版删除）——改动前自行 `cp` 原件到临时位置, 用完即删, **勿在 CAD\ 内留第二份 .lsp**（坑 #35/#49 多副本误载） |
| 主脚本(分流板) | `flb_runner.lsp`（**v10.11**，2662 行，101 defun，多模板 通用/矩形，命令 FLB/FLBPARAM，保留 c:OFF 兼容别名；假体默认传统逐步, 参数框勾选「包络法」切换；参数「主进胶R (zjj_r 14.35)」与图层 ZJJ，自动扫描 DP 圆心生成主进胶圆；v10.11 预建清单扩为 15 层(新增 JRTFBX)+全图层配色重排+ensure-layer 已存在也校正登记色) |
| 出线槽脚本 | `cx_runner.lsp`（**v11.9**，1948 行，81 defun，命令 CX/CXPARAM，保留 c:SLOT 兼容别名；断口圆角函数 `dt:slot-fillet-pair`，CXK 图层青绿 122；**生成出线槽时自动布置压线板**(YXB 图层深绿 84, 模板=v11.2 新 D 形 6 件(重合线16.6/上下边11/右边15.3/R4.3弧×2, 出自更新后 tools\1.dxf), 重合线中点(白线交界)=定位点, 沿选定壁 gap 均匀分布整组居中+斜壁旋转, **壁候选=直线+多段线直段(v11.3), 弧段跳过+失败自诊断计数**, plan/place 两步——删源线前规划/删源线后放置, 无碰撞判断, entnext 全库扫描死循环已根治; **v11.7 左壁畸形根治**(镜像系弧角区间反向) + **运行时可选 内壁(I)/外壁(O) 整圈一致取侧**(相连源线中点投票, 左/右壁语义保留))；全文件零 (command) 主流程(COM标记撤销, 坑 #69 根除)） |
| 加热条脚本 | `jrt_runner.lsp`（**v9.36**，3122 行，119 defun，多模板 通用一/通用二，命令 JRT/JRTPARAM；**封闭线定位层 JRTFBX(浅橙 21)**——v9.36 定案: 通用二破口封闭线**本体在 JRT**(加热条结构完整, 与 v9.33 一致), "JRTFBX" 仅为其同几何定位副本(dt:jrt2-trace, 供另一项目建模脚本按层定位; 不在外协白名单, 不进数据图纸/精雕出图, 重跑随产物自清)；通用二支持**单线自动补边**——外壁整圈 + JRTDW 定位线(长线一头埋板内亦可, 两端按轮廓围合区域分里外; 通道线裁板内侧留板边侧+外端延长保留), 出线口自动开出, **圆弧/圆外壁通道线双端自动延伸(参数 jrt2_hook_ext 默认5, 0=旧行为)**；**方向几何判定(v9.25/26/27)**: 嵌套内偏=整环传播 A/B 两候选环取离 FLB 壁更远者朝内(围合奇偶→JRTDW 逐级回退)/颈线=FLB 围合区 24 段采样奇偶判外(L 形非凸也对, 包围盒中心兜底)；vlax-curve nil 返回全双判(numberp: nil 崩溃已根治)；坑 #73 已根治(undo-mark 缺括号吞函数, hook-one 等回顶层)；全文件零 (command) 调用, 坑 #69 根除) |
| 尺寸测量与外协 | `wx_runner.lsp`（**v2.18**，2488 行，75 defun，独立第 4 脚本，命令 FLBSZ/JRTSZ/XQG/JD/SJTZ；**测量加热条长度(v2.17, JRTSZ)**——JRT 曲线按归堆间距聚条(可配 [测量加热条] strip_gap 默认15)/长度=各层嵌套线取中间值/封闭线排除双通道(JRTFBX 副本精确匹配优先 + 几何复核=生成规则反推: 两头都接线的短直线试剔, 剔后线链"几乎等长"才确认, 圆弧一律不动)/多条点选连测/无加热条·仅1条开口线·端点断口0.01~2mm 即弹窗取消不降级手动选；工件倾斜自动正交摆正；**精雕镜像在本体右侧(竖直轴,间隔75mm)，每幅(本体+镜像+文字)绿色包络盒框住(实体级颜色,盒=内容精确bbox)；精雕/线切割 网格排版(v2.13 根治间距): 单元盒 = (图形 ∪ 本幅文字) 外扩 box_margin, 相邻盒四向净距恒 = box_gap; "外协文字"层MText为幅标记, 行内追加锚定上一幅单元盒右缘, 无会话游标时由几何反推本行盒右缘(dt:sz-row-right, 弃"文字 maxx"旧基准); [排版] box_gap/per_row/text_gap/box_margin 四项可配；剪贴板格式 350*180**；主进胶ZJJ与DP白名单提取；数据图纸独立图层隔离防测量干扰；v2.11 配色重排(FLB_BOX 赭黄42/数据图纸 橄榄绿63/外协文字 深青144)；v2.12 精雕配色(JD 黄2: 层色+精雕实体统一置黄/外协包络盒 绿3: 层色+盒实体色；精雕为独立 dwg, 与主图 JRT 黄2/FBX 绿3 同色按用户定案豁免配色门禁唯一性(B)与色差(C))；全文件零 (command) 主流程(COM标记撤销)） |
| 引导器 | `dt_start.lsp`（**v3.14**，994 行，34 defun；一键加载+随 CAD 自启动+**顶部菜单「热流道自动化(R)」**(二级序: 分流板/加热条/出线槽/外协加工/工具, 外协加工三级序(v3.5 用户指定, 使用频率)=测量加热条长度/测量分流板/数据图纸/线切割/精雕, 工具内含演示记录器 DTDEMO 按需加载 demo_recorder.lsp)+**boot/DTRELOAD 逐家族加载验证**(主命令缺失=半加载, 明确警告)；v2.9 起含 `dt:st-gets`/`dt:st-hasvar`/`dt:st-support-root` 低版本兼容底座，**全版本通用**（2026-08-31 AutoCAD 2007 实测通过）。发版后无独立 old 副本。**v3.13 坑 #74 根治**: 精简版老 CAD(真 2007 有 MenuGroups.Add, 该机报"未知名称: Add"=精简版特征)COM 菜单接口半残, ACAD 组里塞的 COM popup 在菜单栏刷新时抛抓不住的 Automation 错误打断命令(JRT 通用二必现) → Add 失败且 ACADVER<24 时改走 **MENULOAD 文件菜单**(`dt:st-menu-fileload`: 写 dt_tools.mns → MENULOAD → menucmd "Pn=+DTTOOLS.POP1", 全程不碰 ActiveX 菜单接口); 其余版本行为零变化; 文件菜单失败退回 COM popup(最坏=v3.6 行为)；menu-remove 三路清理(+MENUUNLOAD), DTDBG 增菜单链路探测行。**v3.14 坑 #75 根治**: v3.13 的 `dt:st-filemenu-lines` then 分支 `(setq` 少一个右括号(else 被吞, 末行多一个 `)` 补平总数, 平衡类门禁全查不出, 真 2007 `(load)` 报「语法错误」) —— 补括号修复 + **新增门禁 `tools/check_sexpr.py`**(setq 奇偶/if/foreach 元素数) 防同类暗雷) |
| 演示记录器 | `demo_recorder.lsp`（**v1.1**，348 行，18 defun，开发辅助工具：命令级反应器把手工操作录成 AI 可读日志；v1.1 补盲区(ESC/异常退出的命令也记新建实体+记录被删实体+INIT 全量清单)；菜单 DTDEMO 按需加载，命令 DEMOREC/DEMOSTOP/DEMOMARK） |
| 校验工具 | `tools\check_lisp.py`（按文件名自动区分清单 flb/cx/jrt/wx/dt_start/demo 六套：括号 stack/BOM/UNDO/死名/代码区非 ASCII/if 参数超限） |
| 审查工具 | `tools\_audit.py`（按自身位置定位 \`..\scripts\ 的 LSP；跨五文件静态审计：①同名不同体函数 ②从未被引用的死函数 ③未声明的全局变量泄漏 ④未使用的形参/局部 ⑤未定义函数引用） |
| 冲突工具 | `tools\_collide.py`（脚本同名函数冲突检测；跨文件同名必须逐字一致） |
| 编码工具 | `tools\make_ansi.py`（**发版必跑**：scripts\ UTF-8 → scripts_ansi\ GBK 副本 + 逐字节读取器模拟校验，供车间 2007~2020 老电脑部署，坑 #64） |
| 兼容门禁 | `tools\check_sysvars.py`（**发版必跑**：系统变量读取的「nil 泄漏」静态门禁——版本相关变量(TRUSTEDPATHS/SECURELOAD/ROAMABLEROOTPREFIX/LOCALROOTPREFIX/DWGPREFIX…)必须走 `dt:st-gets`/`dt:st-hasvar`，且 getvar 结果不得直接作 strcat/strlen 实参；坑 #65。反向验证：v2.8 命中 5 处风险，v2.9 全过） |
| 回归门禁 | `tools\test_direction.py`（**16 组 89 断言**, 纯 stdlib: 点内判定/封口/颈向/压线板排布与模板/镜像弧角闭合(v11.7)/内外壁取侧(v11.7), 口径锚定 tools\1.dxf·2.dxf 实测）+ `tools\check_audit_fixes.py`（14 项体检修复回归）+ `tools\check_defun_depth.py`（defun 顶层深度门禁）+ `tools\check_layer_colors.py`（图层配色门禁: 全脚本登记色一致/唯一/两两 Lab 色差 ≥30, 伴生 `tools\_aci_colors.py` 标准色表）+ `tools\check_jrt2_out.py`（JRT 通用二产物检查, 需 AutoCAD 出图后人工执行; 口径=1714 测试图, 已移出仓库, 重跑需自备同图; **v9.36 起口径回归单层 "JRT"**——封闭线本体在 JRT, JRTFBX 只是定位副本, v9.34 的"两层并集"口径已废）；均带退出码阻断, 命令清单见根目录 AGENTS.md §2 |
| 版本命名 | 每次改动交付 `*_v<N><M>.lsp`（去点：v9.5→`_v95`）；v9.9 之后进 v10→`_v10`。**正式投用版无版本后缀**（`flb_runner.lsp` 等四个脚本 + `dt_start.lsp`），dt_start 优先加载正式版 |
| 历史备份 | 本目录保留全部旧版；更早(v4~v820)在 `C:\Users\5600\WorkBuddy\2026-08-18-16-15-32\autocad-offset-tool\`；多文件试验场(已废弃)在 `Documents\2D3D`、`Documents\dph\autocad` |
| 目标平台 | AutoCAD 2024（2007+）；AutoLISP + Visual LISP (COM) + DCL |

**四脚本架构（2026-09-03 起，2026-09-04 更名）**：flb_runner(原 offset_runner) 只画分流板（命令 FLB/OFF）；cx_runner(原 slot_runner) 只画出线槽（命令 CX/SLOT）；jrt_runner 只画加热条（LD 偏移/裁剪/端帽/多层嵌套轮廓/多模板）；**wx_runner（原 size_runner）独立负责外协加工与尺寸数据测量（分流板最长最宽/双引擎闭合校验/剪贴板写入/FLB_BOX 标注，线切割/精雕外协自动出图，数据图纸文本块生成）**。各脚本**各自自包含**（公共几何库逐字复制），可单独或同时加载——除逐字相同的库函数外，参数表、对话框、dcl 文件、回调函数全部不同名隔离；凡**同名不同体**的函数一律改名隔离（坑 #46）。四个脚本家族在 `dt_start.lsp` 的 `dt:st-families` 统一注册，各对应一个二级菜单，二级菜单内再分布三级子项。

**核心原则**：纯 COM 几何操作（`vla-*`/`vlax-*`），不调 CAD 命令（`command` 仅 UNDO 分组）。

## 2. 运行与加载

### 2.1 推荐：dt_start 引导器（一键/自启动/顶部菜单）

```
APPLOAD dt_start.lsp → DTINSTALL(装完即自启, 本会话立即加载全部脚本+挂出顶栏菜单)
日常: 开 CAD 自动就位; 顶栏「热流道自动化(R)」点击即用(二级分组, 与 dt:st-families 同序:
      分流板▸画分流板/分流板参数(FLB/FLBPARAM), 加热条▸JRT/JRTPARAM, 出线槽▸CX/CXPARAM,
      外协加工▸测量分流板/测量加热条长度/线切割/精雕/数据图纸(FLBSZ/JRTSZ/XQG/JD/SJTZ),
      工具▸重载/诊断/安装/卸载/打开目录/演示记录器, 关于), 命令行输入照旧可用
换版本: 新文件放同目录 → DTRELOAD(不重启刷新+重挂菜单); 菜单异常就重启 CAD(自动重建)
卸载:   DTUNINSTALL(摘菜单+删 acaddoc.lsp 钩子+移出支持/受信任路径, 配置还原)
诊断:   DTDBG(参数对话框链路逐步打印, 定位 stringp 类错误)
```

- 钩子只认固定的 `dt_start.lsp`；**正式版（无版本后缀）优先加载**，无正式版才取"v+数字"最大者（纪元感知编码：v90-99=9.0-9.9 / v20-89=单次版本 / v10-19=10.0+ / 三位首位1=10.x，如 v816=8.16<v96=9.6）。
- **顶部菜单为会话级 COM popup**（塞在 ACAD 主菜单组内，不入主 CUI、不跨会话持久）：每次引导加载成功后自动重建，会话内只完整构建一次（`*dt-st-menu-done*`），工作区切换挤掉菜单 → DTRELOAD 重挂。宏机制定案见坑 #50~#53：`chr(3)` 真取消码 + `(c:命令)` LISP 表达式宏 + 尾空格=回车，全部经 `dt:st-macro` 一处构造。
- 整包复制到新目录/新电脑：重跑 APPLOAD+DTINSTALL 即可（getfiled 兜底定位）。

### 2.2 手动逐个加载

```
分流板: APPLOAD flb_runner.lsp → FLB(先选模板[通用/矩形]→参数框→全自动) / FLBPARAM(只改参数)   [兼容别名 OFF/PARAM]
出线槽: APPLOAD cx_runner.lsp  → CX(弹参数框→选压线板贴壁侧→全自动) / CXPARAM(只改参数)        [兼容别名 SLOT/SLOTPARAM]
加热条: APPLOAD jrt_runner.lsp → JRT(先选模板[通用一/通用二]→参数框→全自动) / JRTPARAM; 通用一需先跑 FLB(RZ 存在)
外协加工: APPLOAD wx_runner.lsp → FLBSZ(测量分流板) / JRTSZ(测量加热条长度) / XQG(线切割) / JD(精雕) / SJTZ(数据图纸)
演示记录: APPLOAD demo_recorder.lsp → DEMOREC / DEMOSTOP / DEMOMARK（或顶栏工具▸演示记录器 DTDEMO 按需加载）
源线: 分流板/假体画在 "LD" 层; 出线槽画在 "CX" 层; 加热条不画源线(复用 LD); 通用二需画 "JRT"(外壁整圈) 与 "JRTDW"(出线口定位线)
```


### 2.3 版本兼容性（2026-08-31 编码补丁 + v2.9 低版本修复后定案）

| AutoCAD 版本 | 四脚本（flb/cx/jrt/wx） | 自启动 | 顶部菜单 | 结论 |
|---|---|---|---|---|
| **2007**（32位） | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅ | ⚠️ 菜单能挂出，但 **`MenuGroups.Add` 实测不可用**（2026-09-16 报「未知名称: Add」，与 2024 同病）→ 自动回退"把 popup 塞进 ACAD 主菜单组"，该回退路径有隐患，见下方注 | **已实测**（2026-08-31 安装/自启/全命令；2026-09-16 复核菜单路径） |
| 2008/2009（32位） | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅ | ⚠️ 同上（回退 ACAD 主菜单组） | 可用（与 2007 同代，预期一致） |
| 2010~2015 | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅ | ✅ | 可用 |
| 2016~2020 | ✅ **须用 scripts_ansi\ 的 GBK 副本** | ✅ TRUSTEDPATHS 生效 | ✅ | 可用 |
| 2021~2023（Unicode LISP） | ✅ 用 scripts\ 的 UTF-8 原版 | ✅ | ✅ 回退已覆盖 | 可用 |
| **2024** | ✅ 实测（UTF-8 原版） | ✅ 实测 | ✅ 实测 | 已验证 |
| 2025/2026 | 预计 ✅（UTF-8 原版） | 预计 ✅ | 按下方清单验证 | 待验证 |
| AutoCAD LT（任意年份） | ❌ | ❌ | ❌ | **不支持**：LT 的 LISP 无 vla-* COM |

> **2007 实测记录（2026-08-31）**：GBK 副本 APPLOAD 成功 → `DTINSTALL` 一次通过 → 三脚本加载 + 顶栏菜单挂出。此前 v2.8 在同一台 2007 上 `DTINSTALL` 报「参数类型错误: stringp nil」（坑 #65），v2.9 修复后即通过。**注意**：2007 无 `TRUSTEDPATHS`（2016 才引入），安装时该步会打印"无(老版本, 跳过)"，属正常。
>
> **⚠️ 顶部菜单在 2007 上的更正与根治（坑 #74）**：原表写"MenuGroups.Add 老版原生可用"**与实测不符** ——
> 该机 `MenuGroups.Add` 报「未知名称: Add」。**2026-09-19 根因定案：真 AutoCAD 2007 有 MenuGroups.Add**
> （2000~2020 全系有, 2024 才移除），报"未知名称: Add"说明该机是**精简版**，ActiveX 菜单层半残 ——
> 塞进 ACAD 组的 COM popup 不属于 CUI 菜单体系, AutoCAD 在**每次菜单栏刷新**（弹框关闭必触发）时校验它
> 就抛抓不住的 Automation 错误并**直接终止正在执行的命令**（`vl-catch-all-apply` 抓不住）。
> 2026-09-16 夜里针对它试过 4 版修法（v3.9~v3.12，含"默认不建 COM 菜单"），均未解决且引入更多问题，
> 已整体回滚（代码回到 v3.6 行为）。
> **v3.13 根治（2026-09-19）**：`MenuGroups.Add` 失败且 `ACADVER < 24` 时挂菜单改走 **MENULOAD 文件菜单**
> 原生链路（写 dt_tools.mns → MENULOAD → menucmd "Pn=+DTTOOLS.POP1"），全程不碰 ActiveX 菜单接口；
> 真版 2021+/Add 成功的版本行为零变化。老机部署新版后**重启 CAD** 即生效。
> 若文件菜单挂载失败会自动退回 COM popup（最坏 = v3.6 旧行为，不会更糟）。

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


### 2.4 参数配置文件与记忆（flb v10.11 / cx v11.9 / jrt v9.36 / wx v2.18）

> ini/dcl/\*_mem.ini 均为**运行生成物**：2026-09-09 起已移出 Git（`.gitignore` §2.2 全局排除 `*.ini`/`*.dcl`），新机部署无需携带——ini 由 `dt:*-cfg-boot` 首次运行自动生成，dcl 由 `dt:*-write-dcl` 弹框时生成，mem 为本机参数记忆。

| 文件（脚本目录，TEMP 兜底） | 内容 | 谁写 |
|---|---|---|
| `flb_runner.ini` / `jrt_runner.ini` | 默认值，按模板分节 `[通用]`/`[矩形]`/`[通用一]`/`[通用二]`，`键 = 数值` + `; 中文注释`（labels 表生成） | 首次运行自动生成，用户记事本改 |
| `cx_runner.ini` | 同上，固定节 `[参数]`（无模板；v10.1 起也带中文注释；v10.5 起含压线板间距 `cx_yxb_gap`） | 同上 |
| `wx_runner.ini` | **只被读取不回写**：`[线切割]`/`[精雕]` 的 `root` 出图根路径 + `[排版]` 四项（box_gap/per_row/text_gap/box_margin）；缺失则回退代码内置默认 | 用户记事本改（脚本不写） |
| `*_mem.ini`（三个：flb/cx/jrt） | 上次值记忆 + 单独一行写出的 `[模板] template=下标`（**只写一次**，v10.2d/v9.13 修复重复节） | 程序在**确定参数框时**自动保存 |

- **语义**：预填=全局变量（加载时 boot 已从 mem 恢复上次模板+该模板上次值）；**恢复默认按钮 = ini 配置值**（无该键回模板内置默认→表 caddr 三级兜底）；**切换模板 = 该模板记忆值→ini 节→模板内置默认→caddr**；ini **每次弹框前重读**（改完保存即生效，无需 DTRELOAD）；取消对话框不触发保存。
- **实现**：各脚本尾部 `(dt:off-cfg-boot)` / `(dt:slot-cfg-boot)` / `(dt:jrt-cfg-boot)`（文件尾调用，定义在前）；解析器只认"键 = 数值"行（distof 校验，0 合法），注释/乱码/未知键跳过；全程 vl-catch-all，文件缺失/损坏静默回退内置默认。函数名带脚本前缀隔离（坑 #46）。

**编码**：`.lsp` 必须 UTF-8 with BOM（中文乱码→图层匹配失败）；`.dcl` 自动生成为 ANSI/GBK（两文件规则相反）。行尾 LF。`.ini` 走 AutoLISP 文本 IO（ANSI/GBK），键值行纯 ASCII，中文只在注释——用户误存 UTF-8 仅注释乱码、解析不受影响。三个脚本的 `find-dcl` 均为**确定性模式**：优先用 dt_start 注入的 `*dt-script-dir*` 写 `<dir>\*.dcl`，无引导器时写 `%TEMP%\*_tmp.dcl`（jrt v9.11b 对齐；旧 findfile 候选链已全部移除）。  
**≤2020 部署（坑 #64）**：2007~2020 加载 UTF-8 版报「输入中的点位置不正确」，须用 `scripts_ansi\` 的 GBK 副本（内容逐字同源，仅注释/个别提示文字的 ▸⇒²↔ 符号替换为 `>` `=>` `^2` `<->`）；由 `python tools\make_ansi.py` 生成并自动校验（GBK 可编码性 + 逐字节读取器模拟：字符串/括号结构与原件逐项一致），**改版 scripts\ 后必须重跑**。ini/dcl/mem 本就走 ANSI，两版共用无差异。

## 3. 图层约定（v9.4 起拼音缩写）

| 缩写 | 含义 | 颜色 | 说明 |
|---|---|---|---|
| LD | 流道线 | 白 7 | 分流板源中心线（用户画，脚本不碰） |
| FLB | 分流板 | 红 1 | 含并入的封口线/倒角斜线 |
| FBX | 封闭线 | 绿 3 | **流程临时层**：倒角后并入 FLB 并删除（第 9.5 步） |
| LS | 螺丝 | 青 4 | v9.6 起单圆 |
| JT | 分流板假体 | 洋红 6 | v9.1 前称"分流板挖孔" |
| JTFBX | 假体封闭线 | 玫红 230 | **流程临时层**：圆角后并入 JT 并删除（第 15.5 步） |
| RZ | 热咀 | 橙 30 | 热咀圆 R11.35 |
| DK | 点孔 | 灰 8 | 点孔圆 R3（与热咀同心） |
| DP | 垫片 | 蓝 5 | **预留层**：只创建不自动画、不参与清理（用户手画） |
| ZJJ | 主进胶 | 灰紫 193 | 自动检测 DP 圆并在其圆心生成 R14.35 主进胶圆(flb_runner 管理) |
| CX | 出线槽 | 浅蓝 161 | 源线+通道壁+圆角弧+封闭线同层（cx_runner 管理） |
| CXK | 出线口封闭线 | 青绿 122 | v9.9：距 DP 最远的那条封闭线自动分流到此层（cx 创建） |
| YXB | 压线板 | 深绿 84 | v10.5 出线槽自动布置压线板（cx 管理；D 形模板, 重合线贴壁, 定位点=重合线中点, 每次运行先清旧实例；v11.8 配色重排 4→84 与 LS 青 4 区分） |
| JRT | 加热条 | 黄 2 | 多层嵌套轮廓+端帽同层（jrt_runner 管理；纯产物层，重跑全清） |
| JRTFBX | 加热条封闭线定位层 | 浅橙 21 | v9.36：通用二破口封闭线的**同几何定位副本**（本体在 JRT；供另一项目建模脚本按层定位, 不在外协白名单；OFF 预建, 通用二描并重跑自清） |
| JRTDW | 加热条定位 | 浅黄绿 61 | 通用二出线口位置标记（用户画, 一条线穿过外壁指向板边；v9.24 起内外方向几何判定, 与其画向无关） |
| FLB_BOX | 分流板外包矩形及标注 | 赭黄 42 | 分流板最长最宽包络参考框与字高 15 线性标注（FLBSZ 管理） |
| 数据图纸 | 数据图纸克隆图形 | 橄榄绿 63 | SJTZ 克隆加工曲线后独立置入该层，彻底隔离母件 FLB 防测量误报 |
| 外协文字 | 外协标注与信息块 | 深青 144 | 线切割/精雕居中多行文件名标注与数据图纸双列信息文本块 |
| JD | 精雕合并层 | 黄 2 | v2.8 精雕正反面合并单层；v2.12 层色改黄且精雕实体统一置黄（覆盖原"逐实体保色"；精雕为独立 dwg, 与 JRT 同色豁免门禁 B/C） |
| 外协包络盒 | 精雕包络盒 | 绿 3 | v2.3 精雕每幅(本体+镜像+文字)整体包络盒(实体级同色)；v2.12 改绿 3(层色+盒实体色同步) |

> `ensure-layer`（flb/jrt/wx）对已存在但大小写不一致的图层自动改名纠正（如 dp→DP；AutoCAD 图层名不区分大小写，坑 #29）。CXK/YXB 由 cx 内联创建（无 ensure-layer）。**v10.11 起全 21 图层统一配色重排**（旧版 5 对图层完全同色、黄色/蓝色系大面积相近, 重排后去重 19 色两两最小 Lab 色差 31.3），且 ensure-layer 对已存在图层也把颜色校正为登记值（老图重跑自动换新色）；`tools\check_layer_colors.py` 门禁防多脚本分头写色漂移。**v2.12 例外**：JD 黄 2 与 外协包络盒 绿 3 按用户定案用标准色（与 JRT/FBX 同值）—— 二者只出现在独立的外协输出 dwg, 故在该门禁中豁免唯一性(B)与色差(C)校验（登记核对 A 与字面量白名单 D 仍照查）。

## 4. 完整流程

### 4.1 `c:FLB`（兼容 `c:OFF`，flb_runner v10.11，v9.8 起先弹**模板选择框**[通用/矩形]，取消中止）

0 选模板(**通用**=下述现状全流程，行为零变化；**矩形**=`dt:rect-process` 自管全流程，见 §7) → 0.5 弹参数框(取消中止；v9.9 起按模板动态显示参数键；v10.8 新增主进胶 R 参数 `zjj_r` 默认 14.35) → 1 检查 LD 层 → 2 全选 → 3 建 15 层(LD/FLB/FBX/LS/JT/JTFBX/RZ/DK/DP/CX/CXK/JRT/JRTDW/JRTFBX/ZJJ) → 3.5 清理旧产物(含 RZ/DK/ZJJ；**不清 DP、不清 CX**) → 4 偏移35→FLB → 5 裁剪 → 6 断口圆角R15 → 7 通道封口→FBX → **7.5 热咀+点孔圆**(RZ/DK，须在倒角前：倒角后 FBX 混入斜线无法按层识别) → 8 螺丝孔(单圆，必须在倒角前) → 9 倒角 → **9.5 FBX 并入 FLB 并删层**(v9.1) → **10~15.5 假体(v10.2 包络法，见 §7；FLB 为空/外扩量过小时回退旧五步：LD偏移50→带状裁剪→断口圆角→延长15→端点封口→封口圆角→并层)** → **16.5 自动检测 DP 图层上的圆并在其圆心创建 ZJJ 主进胶圆(R14.35)** → 17 统计。（以上大括号前为通用模板流程，行号参考）

### 4.2 `c:CX`（兼容 `c:SLOT`，cx_runner v11.9，`dt:cx-process` 压线板链 `dt:cx-yxb-*`）

0 弹参数框 → 检查 CX 层 → 只对**源线**(eName 记录)偏移 17.5 生成通道壁(源线同层保留) → 1 区域裁剪(exclude 源线) → 2 小圆角R15 → 3 悬空端头固定延长 50 → 4 **收头+大圆角**(v9.5/7)：每条延长壁沿方向找第一个交点并收头(=FILLET 自带修剪)；交点处双方端头重合→与小圆角**同一套 fillet-pair 仅换 R30**(nochk=T)；端头落在宿主壁内部(T形)→打断宿主壁取同侧断头配对；未命中→复原 → 5 **封闭**(v9.6/7)：每个敞口(源线悬空端的两壁端头，距源线端点≈17.5)连一条封闭线；**收尾 CXK 分流**(v9.9)：距 DP(垫片)最远的那条封闭线移入 CXK 层(青绿 122，DP 为空则提示跳过) → 6 **删除全部源线**(v9.6，重跑需重画源线)。**垫片要在跑 CX 之前画好才会分流出 CXK**。

### 4.3 `c:JRT`（jrt_runner v9.36，`dt:jrt-build`/`dt:jrt-decide`/通用二 `dt:jrt2-process`）

0 弹参数框/选模板(v9.8 多模板) → 1 检查 LD 层 → 2 建 JRT 层(黄2)+清上轮产物 → 3 检查 RZ 层(无→警告，端头全部退化为直线帽) → 4 **端帽统一判定**(`dt:jrt-decide`，各层共用)：自由端头(端点不落在其他 LD 线上)逐一算 `gap = 本LD线与不相交LD线的最小轴线距 − 2×偏移值`，|gap−偏移值|≤1 且匹配到 RZ → 圆帽；否则直线帽；gap 过近 → 告警+直线帽 → 5 **多层构建**(`dt:jrt-build`，k=0..N)：每层 = 偏移 LD→JRT → LD±半宽带状裁剪(仅本层实体，eName 快照差集隔离) → 端帽(圆帽=RZ圆心整圆R=半宽+侧线修到切点；直线帽=LD端点平面向内偏 inset 画帽线+侧线端头修到帽平面) → 统一断口圆角(交汇断口+帽角同一套 jrt-fillet-pair) → 零长残段清理 → 6 统计。**不读 FBX**：全部几何由 LD+RZ 推导。参数：jrt_fillet_r 19(内层逐层+step=同心弧)、jrt_cap_r 29(≥半宽时封闭线=相切圆弧)、jrt_inner_count 2(层数=次数+1)；默认自洽 40−11=29=半宽。

### 4.4 `c:FLBSZ` / `c:JRTSZ` / `c:XQG` / `c:JD` / `c:SJTZ`（wx_runner v2.18，外协加工与测量工具箱；别名 `c:FLBSIZE`/`c:SZ`/`c:WXSZ` 均指向 FLBSZ）

- **FLBSZ 测量分流板**：0 探测 FLB 图层；0.5 检验闭合(双引擎：vla-AddRegion + 端点 0.5mm 拓扑度数，若检测到多独立连通域自动警示多份包络并提示手动框选目标)；1 手动选线闭合校验；2 AABB+OBB 最佳包络矩形计算最长与最宽；3 自动写入剪贴板(如 350x180)；4 交互式确认后在 FLB_BOX 绘制包络矩形与长宽标注(字高≥15)。
- **JRTSZ 测量加热条长度(v2.17)**：0 提取 JRT 图层曲线(无→弹窗取消, 不降级手动选)；0.5 封闭线标记——JRTFBX 实体与 JRT 直线两端点重合(<0.5)即精确剔除；1 归堆=最小间距聚类分条(**可配 wx_runner.ini [测量加热条] strip_gap 默认 15, 误填<1 回落默认**; bbox 预过滤+双向采样投影求距)；2 逐条建模(缓存端点/邻接, 端点贴"无端点曲线"线身也算相接——通用一圆帽整圆)→**几何复核剔除(v2.16 重做, 生成规则反推, 用户定案只剔封闭线本身圆弧不动)**: 候选=两头都接在别的曲线端点上的短直线(<max(6%全条长,40)), 单根/成对试剔(成对只试最短 12 根), 剔后线链"几乎等长"(极差变小且最短/最长≥0.8 单剔/0.45 成对)才确认, 剔后更乱一律不动——嵌套轮廓各层长度天生几乎相等即判据; 3 各层嵌套线长度取**中间值**；4 单条自动测, 多条列表点选连测(就近匹配点选位置)；5 完整性守卫——仅 1 条开口线/端点断口 0.01~2mm→弹窗取消；短链/整圆/各层差异>20% 仅提示不取消；6 结果写剪贴板+弹窗+各层线长明细。只读测量, 不建图层不动图形。(v2.15 的"近垂直切向过滤+相切弧带出+连通分量增益验证"已废)
- **XQG 线切割出图**：提取闭合 FLB，自动探测主倾角并旋转正交摆正；全自动生成年月目录与日期递增目标 DWG(如 26\09\09.04.dwg，已存在回车追加/输入N新建 09.04_1)；在原图纸中完成原点归一与平移，调用 `vla-copyobjects` 原子级克隆入目标图纸；**排版 v2.13**：单元盒 = (图形 ∪ 本幅文字) 外扩 `box_margin`，相邻盒四向净距恒 = `box_gap`(ini [排版])，文字底边距图形最小包络盒顶边 = `text_gap`(可配；基准 = 摆正后的最小外包盒，**只作基准不画盒**)；工件上方居中标注多行文件名(字高 15，\P 折行，宋仿黑探测)。
- **JD 精雕出图**：白名单提取有效曲线(FLB/LS/RZ/DK/JRT/DP/ZJJ)；自动探测倾角旋转摆正；当前文档原生镜像(`dt:sz-mirror-in-curdoc`)在工件下方严格生成 75mm 间距反面镜像体；**分流规则**：手动模式 100% 全部图元保留，正反面零丢失；自动模式正面排除 RZ/DP，反面排除 ZJJ/DK；`vla-copyobjects` 原子级深拷贝写入目标图纸；**排版 v2.13 同 XQG**，另按单元盒绘制 `外协包络盒`(绿 3；盒 = 单元盒，与间距同源 → 相邻盒四向净距恒 = `box_gap`)；正上方居中标注文件名。
- **SJTZ 数据图纸**：白名单提取加工曲线；自动探测倾角并旋转摆正；鼠标拖动或位移输入交互式复制；**克隆体置入隔离图层"数据图纸"**，彻底防止干扰 FLB 尺寸测量；右侧+30 生成规范化双列信息文本块(列间距 95 杜绝重叠，系统日期全自动无空格，单一 MText 支持双击直接编辑)。

## 5. 参数表

**主脚本 `dt:param-table`（13 项，v10.8 增 zjj_r；v9.8 增 rect_chamfer 后；v9.6 螺丝单圆；v10.7 更名后表名仍为 `dt:param-table` 未随脚本改名）**：offset_dist 35 / hole_dist 50 / hole_extend 15 / fillet_r 15 / fillet_r_hole 15 / chamfer_d 5 / screw_in 10 / screw_r 4.25 / nozzle_offset 40 / nozzle_r 11.35 / pin_r 3(设0不画) / rect_chamfer 10(矩形模板板角倒角) / zjj_r 14.35(主进胶圆半径)。预填/应用/恢复默认全由表驱动，对话框分组：基本尺寸/螺丝孔与倒角/热咀和点孔。**v10.5 勾选框**：参数框底部「假体用包络法」toggle（全模板可见, 不随模板键变化），全局 *dt-jt-envelope*；默认值 = ini [假体] envelope(0=传统逐步默认, 1=包络法)，确定才记忆(mem [假体])，恢复默认=ini 值；旧 ini 由 cfg-boot 自动追加该节(不重写全文件)。

**cx `dt:cx-param-table`（5 项，v10.5 增 cx_yxb_gap）**：cx_dist 17.5(通道半宽) / cx_extend 50(悬空端头延长) / cx_fillet_r_small 15(相交断口小圆角) / cx_fillet_r_large 30(延长交会大圆角) / cx_yxb_gap 125(压线板放置间距)。对话框分组"基本设置"。

**jrt `dt:jrt-param-table`（13 项 = 通用一 6 + 通用二专属 7，其中 jrt_inner_step/jrt_inner_count 两模板共用）**：通用一 —— jrt_offset 29(半宽) / jrt_cap_inset 11(直线帽内偏) / jrt_fillet_r 19(交汇圆角，内层+step=同心弧) / jrt_cap_r 29(封闭线圆角，≥半宽时为相切圆弧) / jrt_inner_step 4(向内步长) / jrt_inner_count 2(层数=次数+1)；通用二 —— jrt_inner_step 4 / jrt_inner_count 2 / jrt2_neck_len 65(颈线长) / jrt2_neck_off 35(颈线偏移) / jrt2_close_r 15(封口圆角) / jrt2_trim_r 15(相交圆角) / jrt2_half_w 16.5(单线补边半宽) / jrt2_end_r 12(端部过渡弧) / jrt2_hook_ext 5(出线口通道双端延伸，0=旧行为，v9.26)。另有多模板表 `dt:jrt-template-table` 与模板键表 `dt:jrt-tpl-keys`。

注意：每次 APPLOAD 重载参数重置为默认。固定参数：字高 10、圆角递减步长 1/最小 1、断口配对容差 1e-3、find-touch 上限 15、封口配对容差 max(1, 15%×off-dist)、出线槽延长命中容差 0.5、敞口封闭窗口 17.5±15%、CXK 距离=3 采样点最小法。

## 6. 函数清单

> **本节只记函数名、不记行号**（2026-09-16 定案）：行号每次改脚本就失效（一轮审查下来 84 个行号锚点只剩 14 个还对），
> 函数名唯一且可检索。定位某个函数：`grep -n "^(defun 函数名" scripts/*.lsp`（注意 `dt:` / `c:` 前缀与脚本家族）。


### 6.1 flb_runner v10.11（101 defun，2662 行）
- 工具：dist/flat->pts/inters-pts/ss->list/ms/layer-vlas/poly-pts/point-on-line/uniq/excluded-p/**curve-p/curves-only(v10.6 非曲线实体过滤)**/norm-angle/in-zone/unit/pt+vec/acos/tan/angle-between/not-parallel/arc-covers/end-infos/set-endpoint/endpoint-in
- **参数配置与记忆**：**dt:flb-cfg-dir**/flb-cfg-kv/flb-cfg-read(distof 校验 INI 解析)/flb-cfg-sec/flb-cfg-get/**flb-param-default(cfg→模板表→caddr 三级)**/flb-cfg-gen(带注释生成 ini)/**flb-mem-save(按模板保存)**/**flb-cfg-boot(文件尾调用: 生成缺失 ini+恢复上次模板/值)**（v10.7 由 `dt:off-cfg-*` 整体更名）
- 切割链：cut-params(v10.6 getparamatpoint 剔 nil)/seg-mid/rebuild-seg/cut-curve(统一驱动: nil=打断/TRIM=裁剪)/poly-rebuild/trim-curve/cross-points(**v10.6 包围盒预过滤**: bbox 不相交跳过 intersectwith, 复用 dt:rect-bbox)/trim-all
- 圆角：fillet-pair(6参)/collect-heads/pair-heads/fillet-all
- 封口：end-free/pick-pair/close-pair/same-pair/make-close-line/close-channels
- 倒角+热咀+假体+主进胶：collect-plate-ends/find-touch/**nozzle-circles**/add-close-line/mark-fail/chamfer-one/chamfer-close/near-center-end/extend-ends/fillet-close-one/fillet-close/**dt:flb-process-zjj(v10.8 新增, 扫描 DP 圆心生成 ZJJ 主进胶圆)**
- 图层偏移：ensure-layer(大小写纠正; v10.11 起已存在图层也校正登记色)/purge-layer/**merge-layer**/offset-enames/offset-layer/offset-inward
- 螺丝：add-screw(单圆)/drill-holes
- **多模板(v9.8~v10.0)**：**dt:flb-template-table(setq 表, 通用/矩形, 矩形 process 级覆盖)**/dt:flb-template-row/dt:flb-apply-template/dt:flb-template-dcl-lines/dt:flb-template-dialog/dt:flb-tpl-keys/**dt:flb-param-labels**；**dt:rect-bb-pts(boundingbox 的 variant/safearray 双兼容)**/**dt:rect-bbox(对象列表→包络盒)**/**dt:rect-plate/dt:rect-jt/dt:rect-corners/dt:rect-process**
- **假体包络法(v10.2 起)**：**dt:jt-build(FLB 包络盒外扩 hole_dist−offset_dist 圆角矩形, 复用 dt:rect-bbox；v10.2d 起圆角上限与 rect-jt 同为 0.45×短边)**/dt:jt-line
- 对话框：dcl-lines(v9.9 按模板动态生成)/write-dcl/find-dcl/get-num/param-reset/param-apply/param-dialog/c:FLBPARAM/c:PARAM(兼容别名)
- **c:FLB(含局部 `*error*`) / c:OFF(兼容别名)**

### 6.2 cx_runner v11.9（81 defun，1948 行）
- **参数配置与记忆(v10.1)**：cx-cfg-dir/kv/read(v10.3 句柄兜底关闭)/sec/get/**cx-param-default**/cx-cfg-gen/**cx-mem-save**/**cx-cfg-boot**(文件尾)；全局 \*dt-cx-cfg\*/\*dt-cx-mem\*（固定节"参数"）
- **撤销(v11.x)**：**cx-undo-mark/cx-undo-end**（COM 撤销标记, 坑 #69 全文件零 `(command)`）
- 工具+切割链+圆角+偏移：与主脚本逐字一致的公共库（dist/flat->pts/inters-pts/ss->list/ms/layer-vlas/poly-pts/point-on-line/uniq/excluded-p/curve-p/curves-only/norm-angle/in-zone/unit/pt+vec/acos/tan/angle-between/not-parallel/end-infos/set-endpoint/endpoint-in/cut-params/seg-mid/rebuild-seg/cut-curve/poly-rebuild/trim-curve/rect-bb-pts/rect-bbox/bbox-overlap-p/cross-points）+ offset-enames；**fillet-pair = dt:cx-fillet-pair(缺省层 "CX"/本脚本小圆角, 消除跨脚本隐藏耦合, 坑 #46)**
- 出线槽链：collect-ends/break-curve/**cx-trim**/cx-fillet-all/cx-first-cross/cx-extend-fixed/**cx-join**/near-src-fwd/**cx-close**/**cx-cxk**/**cx-process**
- **压线板链(v10.5~v11.8)**：**yxb-tpl(D 形模板 6 件)**/yxb-map-pt/**yxb-draw(本地系 +X→外法向 +Y→壁向; v11.7 镜像系弧角区间反向修左壁畸形)**/**yxb-resolve-side(v11.7 内壁(I)/外壁(O) 按相连源线投票整圈一致取侧)**/yxb-plan/**yxb-place**/yxb-pt-line-dist/**yxb-segs-of(v11.3 多段线逐段拆壁, 弧段跳过并计数)**/**yxb-find-walls**
- 对话框：cx-dcl-lines/cx-write-dcl/cx-find-dcl/get-num/cx-param-reset/apply/dialog/c:CXPARAM；**c:CX(含局部 `*error*`；c:SLOT 为兼容别名)**

### 6.3 jrt_runner v9.36（119 defun，3122 行）
- **参数配置与记忆(v9.13)**：jrt-cfg-dir/kv/read/sec/get/**jrt-param-default**/jrt-cfg-gen/**jrt-mem-save**/**jrt-cfg-boot**(文件尾)；全局 \*jrt-cfg\*/\*jrt-mem\*；**撤销 = dt:jrt-undo-mark/-end（坑 #69, 全文件零 `(command)`）**
- 工具+切割链+圆角+图层偏移：公共库保留原名；**fillet-pair/cut-curve/trim-curve 改名 dt:jrt-\***（坑 #46）
- 加热条链（通用一）：jrt-snapshot/jrt-diff(eName 快照差集)/jrt-sample-pts/jrt-curve-dist/jrt-touch-p/jrt-free-ends/jrt-match-rz/**jrt-decide(端帽判定,1242)**/jrt-head-walls/jrt-cap-circle/**jrt-cap-line**/jrt-trim/jrt-fillet/jrt-zero-clean/jrt-template-row/jrt-stage/**jrt-build**
- **通用二链（v9.16~v9.36）**：jrt2-grp-touch/jrt2-group/jrt2-cands/jrt2-min-dist/jrt2-pick-near/jrt2-curve-edges/**jrt2-region-edges-n/jrt2-region-edges/jrt2-pt-inside(射线奇偶点内)/jrt2-pick-side/jrt2-propagate(整环传播 RingA/RingB)/jrt2-flb-score(到 FLB 壁平均最近距离裁决内偏方向)/jrt2-layer**/**jrt2-close(破口封闭线; v9.36 层名参数化, 调用点传 "JRT")**/**jrt2-trace(v9.36 新增: 在 JRTFBX 描同几何定位副本)**/jrt2-offset-line/**jrt2-line-extend(v9.26 圆弧壁够不着时双端加长)**/jrt2-ch-exist/jrt2-line-x-curve/jrt2-wall-tan/jrt2-near-pt/jrt2-osculating/jrt2-true-fillet/jrt2-hook-arc/**jrt2-hook-one(出线口 S 形开口)**/jrt2-trim-line/jrt2-seg-rebuild/jrt2-hooks/**jrt2-process(通用二全覆盖)**/jrt2-fillet2/jrt2-junction/**jrt2-neck(颈线按 FLB 围合区奇偶判外)**
- 对话框：jrt-dcl-lines/jrt-template-dcl-lines/jrt-write-dcl/**jrt-find-dcl(v9.11b 确定性模式)**/jrt-get-num/jrt-param-reset/apply/dialog/jrt-apply-template/jrt-template-dialog/c:JRTPARAM；**c:JRT(含局部 `*error*`)**

### 6.4 wx_runner v2.18（75 defun（含 6 个局部 `*error*` 与 stringp 垫片），2488 行，外协加工与尺寸测量工具箱）
- 自包含基础几何库：dt:ms/dt:ss->list/dt:ensure-layer/dt:rect-bb-pts/dt:rect-bbox/dt:sz-curve-p/dt:sz-curves-only/stringp(兼容垫片)
- 倾角探测与摆正：dt:sz-detect-tilt-angle(优先探测 FLB 主斜角)/dt:sz-straighten-objs(绕基准旋转正交摆正)
- 测量核心引擎：dt:sz-copy-clip(ActiveX+clip.exe双通道)/dt:sz-curve-sample-pts/dt:sz-curve-angle/dt:sz-uniq-angles/dt:sz-rot-pt/dt:sz-check-closed(双引擎: ACIS Region + 端点0.5mm拓扑度数)/dt:sz-calc-box(AABB+OBB最佳包络)/dt:sz-fmt-num/dt:sz-draw-box-dim(FLB_BOX 字高15)
- **加热条长度测量引擎(v2.16, §二.5 起)**：dt:sz-jrt-curve-len/dt:sz-jrt-ends(整圆/闭合pline视为无端点)/dt:sz-jrt-min-dist(双向5采样投影)/dt:sz-jrt-obj-bbox/dt:sz-jrt-bb-gap/dt:sz-jrt-strips(15mm 归堆分条)/dt:sz-jrt-fbx-match(JRTFBX 副本两端点无序重合精确剔除)/dt:sz-jrt-adj-p(相接判定: 端点重合+端点贴"无端点曲线"线身——通用一圆帽整圆切点)/dt:sz-jrt-comps-i(下标连通分量, 按邻接表传播)/dt:sz-jrt-lens-at(给定剔除表算各线链长)/dt:sz-jrt-spread(线链整齐度=相对中间值极差, 单链=1)/dt:sz-jrt-joined-p(候选资格: 直线两头都接别的曲线端点)/dt:sz-jrt-close-pick(几何复核=生成规则反推: 单根/成对试剔, 剔后线链几乎等长才确认; 成对只试最短12根)/dt:sz-jrt-nearmiss(端点间距0.01~2mm断口)/dt:sz-jrt-chain-closed-p/dt:sz-jrt-median/dt:sz-jrt-strip-rec(模型+剔除+测量记录)/dt:sz-jrt-report(完整性守卫+各层明细+结果输出)
- 外协导出引擎：dt:sz-format-multiline(长连文件名智能 \P 换行)/dt:sz-get-font-face/dt:sz-ensure-style/dt:sz-ensure-doc-layer/dt:sz-flatten-layer/dt:sz-migrate-layers(精雕并入 JD 层)/dt:sz-find-open-doc/**dt:sz-doc-ms-bbox(v2.13 增可选 excl-layers 求"内容"外包盒)**/**dt:sz-doc-texts(v2.14 只取「外协文字」插入点——非活动文档的 MText boundingbox 不可靠)**/dt:sz-collect-auto-curves(白名单 FLB/LS/RZ/DK/JRT/DP/ZJJ)/dt:sz-mirror-in-curdoc(活动文档任意轴镜像, 正反面间隔 75mm)/**dt:sz-row-right(v2.13 由几何反推本行单元盒右缘)**/**dt:sz-make-title(v2.13 统一规格幅标题 MText)**/dt:sz-export-to-dwg(跨文档原子克隆 + 单元盒网格排版 + 标题随件拷入)
- 配置与路径：dt:sz-gets/dt:sz-get-date-str/dt:sz-split/dt:sz-mkdir-p/dt:sz-cfg-get/dt:sz-get-latest-target/dt:sz-next-avail-name/dt:sz-auto-target-path
- 命令接口：c:FLBSZ / c:FLBSIZE / c:SZ / c:WXSZ(均转 FLBSZ) / c:JRTSZ / c:XQG / c:JD / c:SJTZ
- **v2.14 排版基准铁律**：行判定/行内容顶取「外协文字」**插入点**（属性直读，= 文字底边 = 内容顶 + text_gap），行右缘/内容底缘取**内容实体 bbox**（排除 外协文字/外协包络盒）——禁止再读 MText 的 boundingbox（非活动文档不可靠，v2.13 实测把行顶算低 86mm 导致 Y 乱飘且永不换行）；回归 `check_audit_fixes.py` B-12 硬断言文件内不得再出现 MText bbox 读取

### 6.5 dt_start v3.6（31 defun，814 行；v3.4 外协加工子菜单 +「测量加热条长度(JRTSZ)」+ about 清单同步；v3.5 外协加工三级序重排；v3.6 体检修复 `c:DTDEMO` 死分支）
- **低版本兼容底座(v2.9 新增, 坑 #65)**：**st-gets(取系统变量, 抛错/nil/非字符串一律返回 "")**/**st-hasvar(变量是否存在)**/**st-support-root(ROAMABLEROOTPREFIX→LOCALROOTPREFIX→"" 兜底)** —— 全文件所有 getvar 必须经这三个函数, 禁止裸调 getvar(check_sysvars.py 门禁)
- 引导：st-families(**五元组**: 前缀/中文名/主命令/参数命令/子菜单热键, 加载与菜单共用)/st-init(\*dt-script-dir\* 注入+propagate)/**st-locate(findfile→dwgprefix(走 st-gets)→getfiled 兜底)**/st-digits/st-vernum(纪元感知)/st-pick(正式版优先)/st-join/st-boot(会话守卫, 加载成功后自动挂菜单)
- 钩子+路径：**st-acadoc-path(收 dir 参数; 支持根不可用→兜底写脚本目录)**/st-2bs/st-write-hook(标记块幂等; 支持根可用才 vl-mkdir 且包 catch)/**st-remove-hook(收 dir 参数)**/st-path-list/**st-split(入参 null 直接返回 nil)**/**st-add-support(收 front 参数: 兜底模式须把脚本目录顶到支持路径最前)**/st-del-support/**st-trusted-add/del(v2.9 起补 null + 非字符串判断: 老版本无此变量即跳过, 不再把 nil 喂给 st-path-list)**
- **顶部菜单(v2.1~v2.6)**：st-version/st-menugroup/st-menutitle 全局量；**st-macro(chr3 取消+(c:命令) LISP 宏+尾空格=回车, 坑 #50~#53 定案)**/st-open-dir/st-about/**st-menu-remove(自建组 Detach+ACAD 组同名 popup 清理, 双路径)**/**st-menu-build(自建组失败→ACAD 组塞 popup→同名残留复用, 会话内只建一次)**/st-menu-ensure(已建成仅重挂菜单栏)
- 命令：**c:DTINSTALL(打印 ACADVER/支持根/变量可用性 → 先加支持路径 → 再写钩子 → 再处理 TRUSTEDPATHS; 兜底模式 front=T)**/c:DTRELOAD(刷新+重挂菜单)/**c:DTDBG(新增 [0z] 环境探测段: ACADVER + 五个系统变量可用性 + acaddoc.lsp 落点, 专治 stringp nil)**/c:DTUNINSTALL(摘菜单+删钩子+移路径+重置菜单会话状态)


## 7. 核心算法要点（增量）

- **热咀+点孔（`dt:nozzle-circles`）**：每条封口线=一个封闭通道端头；圆心=封口线中点+垂直于封口线、指向通道内侧×nozzle_offset(40)；内侧方向由相连分流板线中点相对封口线中点的点积判号。热咀圆→RZ，同心点孔圆→DK(pin_r=0 不画)。**必须在倒角前**调用。
- **并层（`dt:merge-layer`）**：移全部对象到目标层→删空层定义(失败静默)。FBX→FLB(第9.5步)、JTFBX→JT(第15.5步)。
- **出线槽收头+大圆角（`dt:cx-join`）**：Pass1a 在未收头几何上逐条求延长向第一交点(实际交点过滤"沿方向且≤延长长+1"，无交点兜底端头贴壁≤0.5)→Pass1b 统一 set-endpoint 收至交点(命中)/复原(未命中)→Pass2 逐交点(去重)：≥2 重合端头→`fillet-pair ... T`(**与小圆角同公式仅 R 换大，nochk=T 关闭区域方向验证**——延长接头处两源线区域不重叠，区域检查会误拒正确方向，v9.3/v9.4 方向错的根源)；仅 1 端头(T形)→打断宿主壁、取主体方向与宿主源线前进方向同侧的断头配对。
- **敞口封闭（`dt:cx-close`）**：v10.1 起去重改为双向比较(反向命中不再画重复封闭线)。：源线悬空端的壁端头距源线端点恰 17.5(窗口±15%)且悬空(end-free)→两不同对象端头连线。接头处壁端头已被移动(实测距≥22)天然排除。**端点记录必须用 collect-ends 的 (坐标 对象 端类型) 格式**（坑 #31）。
- **CXK 分流（`dt:cx-cxk`，v9.9）**：每条封闭线 3 采样点(起/中/终)到各 DP 对象最近点(getclosestpointto)求最小=该线 DP 距离；取最大者(并列取先)移入 CXK(青绿 122，内联创建)。DP 空则提示跳过(全部留 CX)；1 条封闭线时它即最远仍移入。与封闭同 UNDO 组。
- **加热条端帽判定（`dt:jrt-decide`）**：自由端头按 `gap = 本LD线与不相交LD线最小轴线距 − 2×jrt_offset` 判定：|gap−jrt_offset|≤1 且 RZ 匹配 → 圆帽；否则直线帽。端帽形式各层共用。RZ 匹配=圆心落在 LD 线上(垂距<0.5)且离本端点近；inward=端点→RZ圆心(无 RZ 时=端点→另一端点)。
- **加热条多层隔离（`dt:jrt-snapshot`/`dt:jrt-diff`）**：每层构建用 JRT 层 eName 快照+差集跟踪本层产物，裁剪/圆角/端帽只作用于本层实体。裁剪会删除重建对象，故每步后重新差集刷新。
- **矩形模板（`dt:rect-process`，flb v9.8~v10.0）**：LD 包围盒四边向外扩 offset_dist 画矩形板边(rect-bb-pts 兼容 boundingbox 输出参数的 variant/safearray 两种绑定)→四角 rect_chamfer(默认10) 倒角→圆角矩形假体(外扩 hole_dist, fillet_r_hole)→热咀(预画 RZ 优先, 否则流道拐点兜底)→螺丝(预画 LS 优先, 否则左右板边中点向内 screw_in=15 兜底)→建 13 层/清理/统计自管全流程→**画完删 LD 源线**(与画图同一 UNDO 组, 一次 Ctrl+Z 找回)。process 级覆盖=整个流程由该模板函数自管, 不走内置流程。通用模板行为零变化。
- **假体包络法（`dt:jt-build`+`dt:jt-line`，flb v10.2~v10.2d）**：JT = **FLB 包络盒外扩 (hole-dist − offset-dist) 的圆角矩形**，四角 R=fillet_r_hole（圆角过大自动让位为直角）。替代旧五步启发式（LD偏移50→带状裁剪→断口圆角→延长→端点封口→封口圆角）。**旧法死因**（工字形实测, 通道间距 70≤D<100）：相向 JT 线互相落入对方 ±50 带区且平行无交点 → cut-curve "整线在区域内"分支整线删除；封口只认"LD 端点 ±50±tol"的端头, 组间断裂无法配对 → JT 碎裂。包络法手画答案逐点验证（flb_1.dxf：四边=FLB包络±15, 四角弧圆心=未倒角原角点）；内部通道（不达板边, 如工字形竖流道）由毛坯盘直接桥过。FLB 为空/外扩量 ≤1 时回退旧五步（旧函数全部保留, hole_extend 仅旧路径使用）。**v10.2b/c 三连修**：包络盒改用 dt:rect-bbox（内联 vla-getboundingbox 漏传引用参数恒失败→误回退, 坑 #56）；四角弧补 put-layer + **象限修正**（BR=270°→360°/TR=0°→90°/TL=90°→180°/BL=180°→270°, 此前每角画成隔壁角的弧与四边不接）；倒角计数 bug 修复（坑 #57）。**v10.2d**：四角圆角上限由"边长−1"改为与 rect-jt 同款的 0.45×短边（细长包络盒上四角弧会互相重叠）。
- 其余算法(偏移/裁剪/圆角几何/封口配对/螺丝 ref/假体延长)同 v8.16 一脉相承，详见历史备份文件内注释。

## 8. 关键数据结构（三套端点格式，勿混用！）

| 结构 | 形态 | 用于 |
|---|---|---|
| heads(圆角) | `(对象 "S"/"E" 端头点 指向主体方向)` | collect-heads/pair-heads/fillet-pair |
| ends(封口/封闭) | `(端点坐标 对象 "S"/"E")` | collect-ends/end-free/slot-close/close-pair |
| plate-ends(倒角/螺丝) | `(端点坐标 对象 "S"/"E" 指向主体方向)` | collect-plate-ends/find-touch |
| 延长记录 ext-rec | `(对象 端类型 原端头 新端头)` | slot-extend-fixed → slot-join |
| 命中记录 hits | `(对象 端类型 交点 宿主壁)` | slot-join 内部 |


## 9. 版本历史

> **本节已拆出 → 见 [`CHANGELOG.md`](CHANGELOG.md)**（v9.0 起的逐版变更与
> 「批次N」跨脚本修复决策记录；2026-09-16 拆分，内容一字未删）。
> 日常排查「代码为什么长这样」直接看 §10 已知坑；本节只作索引，避免和 §10 重复承载历史。

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

68. **AutoLISP 无原生 `stringp` 谓词，字符串判断必须用 `(= (type x) 'STR')`**（2026-09-04 实测）：调用 `c:SJTZ`/`c:XQG`/`c:JD` 时报错「错误: no function definition: STRINGP」。AutoLISP/Visual LISP 只有 `numberp`、`vl-symbolp` 等函数，并**没有** Common Lisp 规范的 `stringp`。若误写 `(stringp x)` 运行时必崩。**定案**：全库严格使用标准表达式 `(= (type x) 'STR')`；并在通用基础库注入兼容垫片 `(if (null (boundp 'stringp)) (defun stringp (x) (= (type x) 'STR'))) `。

69. **AutoCAD 2015+ 在 `*error*` 中调用 `command` 抛 `*push-error-using-command*` 异常**（2026-09-04 实测）：运行时按 ESC 或报错时，AutoCAD 提示「调用(*push-error-using-command*)前无法从 *error* 调用(command)。建议将(command)调用转换为(command-s)」。旧写法 `(vl-catch-all-apply '(lambda () (command "_.UNDO" "E")))` 在现代 CAD 异常堆栈中直接被拦截，导致错误处理器二次崩溃、UNDO 组无法闭合、系统变量发生不可逆漂移。**定案**：撤销标记全面改用 COM 原生接口 `(vla-StartUndoMark doc)` 与 `(vla-EndUndoMark doc)`，或用 `(vl-cmdf ...)` / `command-s`，彻底废弃在 `*error*` 中裸调 `(command)`。

70. **后台非活动文档 (`tgt-doc`) 无法执行 `vla-mirror` / LISP 手工反射样条曲线必然崩溃**（2026-09-04 精雕镜像实测定案）：
   - 现象：在后台通过 `vla-open` 打开的目标文档执行 `(vla-mirror obj p1 p2)` 报「Automation Error: Cannot get UCS in non-active document」或静默失效；尝试用 LISP 手工提取控制点计算几何镜像，直线/圆/圆弧虽可重绘，但样条曲线 (`AcDbSpline`) 因包含 Degree、Knot Vector（节点向量，如 496 个浮点数）及权值，手工用 `vla-put-controlpoints` 或 `AddSpline` 会触发 AutoCAD C++ 内部公差拓扑校验异常。循环因未捕获异常在中途中断，表现为「第一次甚至只镜像了一个圆」、「第二次追加镜像仍然丢失图元」、「最后它们都没有文字标注」（因为异常导致循环提前退出，后面的多行文字生成和保存代码根本没机会执行）。
   - 教训：**严禁在后台非活动文档中通过 LISP 手工逆向重构 CAD 复杂几何体**。

71. **外协加工正反面镜像的最佳架构：原生活动文档引擎 + 原子级 `vla-copyobjects` 跨文档克隆**（2026-09-04 精雕与线切割定案）：
   - 核心原则：**几何计算与变换全部放在当前活动文档 (`cur-doc`) 中进行，目标文档只负责接收成品图元**。
   - 完整管线：
     1) **当前文档安全环境**：在 `cur-doc`（具备完整视口、UCS、变换矩阵）中开启 `(vla-startundomark cur-doc)`，克隆源候选曲线；
     2) **旋转摆正**：通过 `dt:sz-detect-tilt-angle` 探测工件倾斜角并调用 `dt:sz-straighten-objs` 统一正交摆正；
     3) **正面与镜像反面生成**：正面移至原点 $(0, 0)$；直接调用 `dt:sz-mirror-in-curdoc` 以水平线 $Y = -37.5$ 为镜像轴执行原生镜像（优先 `vla-mirror`，保底 `_.MIRROR` 命令），保证正反面工件外框间隔严格为 $75.0\text{mm}$，且 100% 完美保持样条曲线、椭圆、复合线曲率；
     4) **图层分流过滤**：若为手动选择模式，100% 保留全部图元，正反面零丢失；若为自动选择模式，正面删除 RZ/DP，反面删除 ZJJ/DK；
     5) **原子级跨文档克隆**：将正面与反面图元**连同幅标题文字**整体平移，使"单元盒"（= 图形 ∪ 文字，外扩 `box_margin`）左下角落到排版点 `(x0, by0)`，组装 Safearray 调用 `(vla-copyobjects cur-doc sa ms-tgt)` 一次性整体深拷贝进入目标文档（**v2.13**：排版间距以单元盒为准，故文字必须先于拷贝生成并量出真实包围盒）；
     6) **清理与收尾**：删除 `cur-doc` 中的临时图元并闭合撤销组；保存目标文档（正上方文件名 MText 已在第 5 步随件拷入，不再事后补写）。

74. **AutoCAD 自己抛的「菜单 Automation 错误」抓不住，而且会打断正在执行的命令**（2026-09-16 用户 AutoCAD 2007 实测，**至今未解决**）：
   现场：`(c:JRT)` 选「通用二」，打完模板横幅后立即报
   `Automation 错误。参数 热流道自动化(&R) (位于 Item 中) 无效`（另一次报 `ActiveX 服务器返回错误: 无效索引`），之后**再无任何输出**；而 FLB / CX / JRT「通用一」全部正常。
   **三个关键特征（下轮排查起点）**：
   ① 报错文本**点名菜单标题**（`热流道自动化(&R)` 就是自建 popup 的名字）；
   ② 我们加的**分层诊断一行都没打出来**（`【JRT】① 模板选择框完成/异常`）⇒ 该错误**不是 LISP 异常**，
      `vl-catch-all-apply` **抓不住**，它是 AutoCAD 在**菜单栏刷新**时抛出并**直接终止当前命令**的；
   ③ **参数框已实测排除** —— 孤立调用 `(dt:jrt-apply-template 1 T)` + `(dt:jrt-param-dialog)` 完全正常、返回 T。
   **疑点**：把 popup 用 COM 塞进 ACAD 主菜单组这条兜底路径（`MenuGroups.Add` 在实测的 **2007 与 2024 上都报「未知名称: Add」**，
   即该兜底在两个版本上都会启用 —— 原文档"2007 老版原生可用"的说法已证伪，见 §2.3 注）。
   2026-09-16 夜里连试 4 版修法（v3.9 ASCII 名 + Label／v3.10 回退／v3.11 插第 0 位／v3.12 默认不建 COM 菜单），
   **均未解决且引入更多问题 → 2026-09-17 整体回滚到 v3.6 / v9.36**（这些修法在代码中已不存在，别再按它们推理）。
   **下轮动手前必须先做最小实验**：在同一台 2007 上分别试「**不建菜单**跑通用二」与「建了菜单但**不开模板框**跑通用二」，
   先把因果关系钉死，再谈改代码。
   **✅ 2026-09-19 根因定案 + v3.13 根治**：
   - **根因不在 4 版修法找不到的地方，而在前提里**：真 AutoCAD 2007 **有** `MenuGroups.Add`
     （2000~2020 全系都有，2024 才移除），该机报「未知名称: Add」⇒ 这台 2007 是**精简版**，
     ActiveX 菜单层半残 —— 这同时解释了「Add 失败」「popup Delete 被拒」「菜单栏刷新抛抓不住的
     Automation 错误」三个现象同源。v3.12"不建菜单"仍复现，是因为 `st-menu-remove` 摘不掉
     ACAD 组 popup（Delete 被拒），且 boot 每次开图都会重挂。
   - **报错点名「热流道自动化(&R)」**＝刷新校验的对象就是那个 COM popup 本体；删掉它（改走文件菜单）
     该错误在结构上不可能再发生。
   - **修法（dt_start v3.13）**：`MenuGroups.Add` 失败且 `ACADVER < 24` → 挂菜单走 **MENULOAD 文件菜单**
     （`dt:st-menu-fileload`：写 dt_tools.mns → MENULOAD → menucmd "Pn=+DTTOOLS.POP1"），
     全程不碰 ActiveX 菜单接口；其余版本行为零变化；文件菜单失败退回 COM popup（最坏=旧行为）。
     卸载走 `MENUUNLOAD`；DTDBG 的 [0z] 段新增菜单链路探测行（版本号/Add 成败/文件菜单/菜单组状态），
     老机再出问题先跑 DTDBG 把 [0z] 两行发回。
   - **实机验收（2007）**：重启 CAD → 顶栏出现菜单且点击各命令可用 → **JRT 选「通用二」连跑 3 次
     不再报 Automation 错误** → DTDBG 输出里 `MenuGroups.Add=未成功/未试  文件菜单=T`。
     若此时仍报同名错误（理论上不可能——popup 已不存在），则菜单非唯一诱因，再按最小实验二分。

75. **"平衡但残缺"的括号结构：总数平衡掩盖分支吞并，真 2007 `(load)` 报「语法错误」**（2026-09-19 实测定案，**坑 #74 的最终真凶**）：
   - 现场：v3.13 GBK 副本在真 2007 上 `(load)` 即报 `; 错误: 语法错误`（连横幅都不打），
     而开发机 check_lisp(括号计数)/check_defun_depth/_audit 全绿、2024 加载无恙。
   - 定位手段：**探针 `deploy/dt_probe.lsp`**（纯 ASCII，字节级 S 表达式切分 → 49 个顶层表单逐个
     `(vl-catch-all-apply 'load ...)` → 唯一失败者 form 37 `dt:st-filemenu-lines`；其 36 个字符串
     字面量单独加载全过、字符串清空的骨架仍失败 ⇒ 毒在代码骨架）。
   - 根因：**then 分支 `(setq` 少一个右括号** —— else 分支 `(setq ...)` 被吞进 then-setq 的参数表
     （成为第 3 个参数），末行多出的一个 `)` 恰好把总数补平。三层"看不见"：
     ①括号计数只看总量；②defun 体不被求值，2024/CI 加载从不报错；
     ③该函数只有"精简版 2007 + 文件菜单路径"才会被调用，全链路无端到端覆盖。
   - 修复（v3.14）：then 分支补 `)`、末行去一个 `)`；结构恢复本意（foreach 3 体元素 + append 在 foreach 外）。
   - **新门禁 `tools/check_sexpr.py`**（已登记 AGENTS.md §2）：字节级 S 表达式解析，检查
     `setq` 参数奇偶 / `if` 元素数∈{2,3} / `foreach` 元素数≥3 —— 专防"平衡但残缺"。
   - **教训**：①"括号总数平衡"≠"结构正确"，分支级吞并必须靠语义级门禁；②只被特定机器/特定路径
     调用的新函数，交付前必须在该路径上端到端跑一次（本次靠探针补上了这一课）；③自写仿真器
     必须与真读取器逐分支对表（本次探针曾两次漏分支：开引号分支、闭引号/转义字节收集）。

## 11. 接手流程

1. **备份**：改动前把要动的原件 `cp` 到 `HYT-CAD\` 外的临时目录（用完即删）——**勿在 `HYT-CAD\` 内留第二份 .lsp**（坑 #35/#49 多副本误载）。
2. **改代码**：精确 Edit，replace_all 后必须通读复核（坑 #32）；新代码传参前核对数据格式（坑 #31）；**新增/修改函数后跑 `_audit.py` 核对局部变量声明（坑 #61）**。
3. **版本**：新文件 `*_v<N><M>.lsp`（正式投用版去后缀），版本号写进 文件头/横幅。
4. **校验**：`python tools\check_lisp.py scripts\<文件名>`（6 个逐一跑：flb/cx/jrt/wx/dt_start/demo，按文件名自动区分清单）；**改到系统变量读取时必跑 `python tools\check_sysvars.py`（坑 #65 nil 泄漏门禁）**；另跑 `python tools\check_defun_depth.py`（defun 顶层深度）+ `python tools\check_sexpr.py`（**S 表达式结构门禁: setq 奇偶/if/foreach 元素数, 坑 #75**）+ `python tools\check_layer_colors.py`（图层配色）；回归 `python tools\test_direction.py` + `python tools\check_audit_fixes.py`；深度排查另跑 `python tools\_audit.py`；同名一致性 `python tools\_collide.py`（在 scripts\ 目录下跑）。
5. **生成编码副本（发版必做）**：`python tools\make_ansi.py` —— 重新生成 `scripts_ansi\` 并自动做逐字节读取器结构校验，车间 2007~2020 老机器部署只认这份副本；
6. **文档**：用户明确要求时才更新（默认不动）；CAD 侧改动更新 `AGENTS_CAD.md`/`README_CAD.md`（版本号、行数、defun 数、函数清单要同步，否则文档会持续失真）；版本历史写进 `CHANGELOG.md`（§9 已拆出，**别再记行号**——函数名足矣，行号每改必烂）。
7. **测试**：让用户 APPLOAD（或 DTRELOAD）后跑 FLB/CX/JRT/FLBSZ（XQG/JD/SJTZ 出图类另测）；几何问题优先要 **截图+DXF(2007)**，用坑 #33 的复算法定位；对话框/加载类疑难用 DTDBG；JRT 通用二出图后另跑 `python tools\check_jrt2_out.py <产物.dxf>`。
8. **发布**：脚本目录即正式目录（`C:\Users\5600\Desktop\ZDH\HYT-CAD\`，2026-09-16 实测；旧 `test\` 已删除）——在本目录改完、**check_lisp 全绿 + check_sysvars 全过 + 回归/配色/深度门禁全过 + make_ansi 生成成功** + 用户 CAD 实测通过即为发布（2007~2020 用 scripts_ansi\ 副本覆盖后验证）; .dcl/ini 运行时自管, 无需同步动作。
9. **低版本验证清单（2007~2015 尤其要跑）**：① APPLOAD 无「输入中的点位置不正确」（编码，坑 #64）② `DTINSTALL` 无「stringp nil」且打印出 ACADVER/支持根/变量可用性（坑 #65）③ 顶栏菜单出现且点击可执行 ④ FLB/CX/JRT 各跑一次 ⑤ 重启 CAD 自动挂载 ⑥ `DTUNINSTALL` 能干净还原。
10. **打包发老机（要装机时才做）**：**双击仓库根目录 `一键生成移植包.bat`** —— 它会依次跑 `make_ansi.py`（再生 GBK 副本）→ `check_lisp.py`×6（任一不过即中止，不会把坏脚本打进包）→ `deploy_old_pc.py`（打包并逐字节复核），产物在 `deploy\HYT-CAD-老机版\`：
    6 个 GBK `.lsp` + `wx_runner.ini` + `install.bat` + `使用说明.txt`（一页纸手册）+ `manifest.txt`（名+字节数），并附同名 `.zip`。
    老机上**双击 `install.bat`** 即完成装机（自动拷贝 → 校验字节数 → 找 `acad.exe` → `acad.exe /b install.scr` 跑 APPLOAD+DTINSTALL）；
    `install.bat <目录> --check` = 只放文件不碰 CAD。命令行等价写法：`python tools\deploy_old_pc.py`（`--out` / `--no-zip` / `--check`）。
    > `deploy\` 已入 `.gitignore`（构建产物，可再生，不入库）；`使用说明.txt` 由脚本内置模板生成，**不要再写独立的手册文档**。
