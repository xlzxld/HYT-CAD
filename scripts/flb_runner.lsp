;;; ============================================================================
;;; 程序名 : 流道线双向偏移 + 区域裁剪 + 断口圆角 + 通道封口 + 螺丝孔定位
;;;          + 封口倒角 + 分流板假体 + 参数对话框工具 (flb_runner.lsp)  v10.9
;;; v10.9  : 体检B-09: c:FLB 的 *error* 撤销兜底由 (command "_.UNDO" "E")
;;;          改 COM vla-EndUndoMark —— 坑#69(jrt v9.17 定案): *error* 内调
;;;          (command) 在部分版本抛错并被 catch 吞掉, 兜底恰在出错场景
;;;          失效、UNDO 组悬挂; EndUndoMark 无开放标记时无副作用。
;;;          注: 流程内部 9 处 (command "_.UNDO" "BE"/"E") 子组保持原样
;;;          (最小改动; 单独命令行调用子流程时仍无独立收口, 已知局限)。
;;; v10.8  : 体检A-03: dt:jt-build(包络法假体)取 FLB 包络盒未过滤实体
;;;          类型 —— 倒角失败标注文字(chamfer-close 标注 FBX, merge-layer
;;;          并入 FLB)的 boundingbox 被计入 → JT 假体沿标注方向不对称
;;;          撑大。objs 改经 dt:curves-only 过滤(与 jrt dt:jrt2-neck 同规)。
;;; v10.7  : 体检A-02根治(与 cx v11.4 / jrt v9.30 同期): LWPolyline 的
;;;          ObjectName 实为 "AcDbPolyline", dt:poly-pts/dt:seg-rebuild
;;;          的 is-2d 单名 "(= ... \"AcDbLWPolyline\")" 判定恒 nil →
;;;          多段线重建时 2D 平铺坐标按 3 元素错位切分、误建 3D 多段线。
;;;          两处改双名 member; dt:set-endpoint 同款死子句清除。
;;;          新增回归 tools/check_audit_fixes.py。
;;; v10.6  : 健壮性修复(与 slot v10.3 / jrt v9.14 / dt_start v2.8 同期,
;;;          几何行为零变化):
;;;          1) 非曲线实体防护补全 —— v10.2b 只防了封口/端点收集侧, 本次
;;;             统一加 dt:curve-p/dt:curves-only: LD 源图层混入文字/块时
;;;             close-channels/extend-ends 不再崩溃; FBX/JTFBX 上已有的
;;;             "失败"标注文字不再使 chamfer-close/fillet-close/drill-holes
;;;             独立重跑崩溃; collect-heads/trim-all/fillet-all 同步过滤;
;;;          2) cut-params 多段线分支 getparamatpoint 返回 nil 时剔除再
;;;             排序(nil 进 vl-sort 报 bad argument type);
;;;          3) 对话框 load_dialog/start_dialog 包 catch 且保证
;;;             unload_dialog 执行; ini 文件句柄异常兜底关闭(含 boot 的
;;;             [假体]节追加写);
;;;          4) c:OFF 的 *error* 兜底闭合 UNDO 组;
;;;          5) 参数应用增加负值校验(负值回退当前值);
;;;          6) cross-points 加包围盒预过滤(复用 dt:rect-bbox, bbox 不
;;;             相交跳过 COM 求交, 结果不变, 大图提速)。
;;; 多模板 : v9.8 起支持多套规则模板(dt:flb-template-table, 模式同 jrt_runner)。
;;;          OFF 执行时先弹模板选择框(单选, 取消中止):
;;;          "通用" = 现状全流程(偏移+裁剪+圆角+封口+螺丝+倒角+假体+热咀);
;;;          "矩形" = LD 整体范围向外扩「分流板偏移距离」画矩形板边, 四角
;;;          倒角用「板角倒角」参数; 假体 = LD 外扩「假体偏移距离」的圆角
;;;          矩形(圆角=「假体圆角R」); 热咀采用预画 RZ 圆否则放流道拐点
;;;          (半径=热咀半径R), 同心点孔; 螺丝采用预画 LS 圆否则放左右板边
;;;          中点向内「螺丝孔内偏」; 画完删除 LD 源线(重跑需重画); 照样
;;;          预建全部 13 图层。
;;;          覆盖表含 process 的模板整个主流程自管(同 jrt"通用二"模式)。
;;;          v9.9 起参数框按模板动态显示: 只显示当前模板用到的参数键,
;;;          顶部显示模板名(通用 11 项 / 矩形 8 项, 同 jrt v9.9 模式)。
;;; 适用   : AutoCAD 2024 (AutoCAD 2007 及以上版本均可)
;;; 功能   : OFF 一条命令全自动完成(全部尺寸参数可由 PARAM 对话框修改):
;;;          1) "LD"图层中心线向两侧各偏移 35 → "FLB"图层(红色);
;;;          2) 区域裁剪: 侵入其他流道带状区域(±35)的段整段删除, 交叉处
;;;             断开让行;
;;;          3) 断口圆角: 断口两线用圆弧连接(弧凸向交叉中心, 圆心在区域
;;;             外; R15, 线太短不足相切则递减半径并文字标注);
;;;          4) 通道封口: 每条流道通道两端用封口线封闭(临时"FBX"图层,
;;;             倒角后并入"FLB"图层, 图层随之移除);
;;;          5) 螺丝孔: 封口线与两侧分流板线各向内偏移 10, 交点处画圆
;;;             (螺丝孔R, 默认4.25) → "LS"图层(必须在倒角之前执行);
;;;          6) 封口倒角: 封口线两端 45° 倒角(距离 5, 失败文字标注);
;;;          7) 分流板假体: 流道线再向两侧偏移 50 → "JT"(洋红),
;;;             同样裁剪/圆角; 只延长"会被封口线连接的端头"15 再封口,
;;;             封口线落在"分流板封闭线向外15"处, 两端圆角 R15;
;;;          8) 热咀+点孔(v9.2~v9.4): 每条封口线端头沿通道向内偏移
;;;             热咀偏移(默认40)处画热咀半径(默认11.35)圆 → "RZ"(橙) +
;;;             同心点孔半径(默认3)圆 → "DK"(白); 另预留 "DP" 垫片层(蓝);
;;;          9) 出线槽已独立: v9.0 起出线槽拆分为独立脚本 cx_runner
;;;             (命令 SLOT/SLOTPARAM), 本脚本不再处理出线槽。
;;; 图层约定(v9.4 起用拼音缩写, 中英对照; v9.7 起 OFF 预建全部 13 层):
;;;   "LD"    = 流道线(源中心线图层, 用户画; OFF 预建空层属正常)
;;;   "FLB"   = 分流板轮廓线(红色)
;;;   "FBX"   = 封闭线(封口线/倒角斜线的流程临时层, 绿色; 收尾并入 FLB 后移除)
;;;   "LS"    = 螺丝孔圆(青色)
;;;   "JT"    = 分流板假体轮廓线(洋红, 前称"分流板挖孔")
;;;   "JTFBX" = 假体封闭线(封口线/圆角弧的流程临时层, 黄色; 收尾并入 JT 后移除)
;;;   "RZ"    = 热咀圆(橙色)
;;;   "DK"    = 点孔圆(白色, 与热咀圆同心)
;;;   "DP"    = 垫片(蓝色, 预留层: 只创建不自动绘制, 不参与重跑清理)
;;;   "CX"    = 出线槽(归独立脚本 cx_runner 管理)
;;;   "CXK"   = 出线口(蓝色, slot v9.9 分流产物层: 距 DP 最远的封闭线)
;;;   "JRT"   = 加热条(黄色, 归独立脚本 jrt_runner 管理)
;;;   "JRTDW" = 加热条定位(黄色, jrt 通用二模板出线口位置标记, 用户画定位线)
;;; 加载   : APPLOAD 选择本文件加载(flb_runner.dcl 由脚本自动生成,
;;;          无需手工准备)。
;;; 运行   : 加载后在命令行输入 OFF 并回车, 弹出参数对话框, 确认后全程
;;;          自动执行, 无需人工选择。
;;;          也可单独执行: (dt:trim-all 35.0 "FLB") 区域裁剪
;;;                        (dt:fillet-all 35.0 "FLB") 断口圆角
;;;                        (dt:close-channels 35.0 "FLB" "FBX") 通道封口
;;;                        (dt:chamfer-close) 封口倒角
;;;                        (dt:drill-holes) 螺丝孔定位
;;;                        (dt:fillet-close) 假体封口圆角
;;;                        (dt:offset-layer "LD" "JT" 50.0) 假体偏移
;;;                        PARAM 弹出参数对话框(只改参数)
;;;            注意: AutoLISP 无默认参数, 带图层的函数必须传全参数。
;;;
;;; 版本   : v9.0 = v8.16 逻辑原样 + 全面整理(删废弃函数/去重重构/精简注释,
;;;          此前内部迭代号 v9.0/v9.1 合并为本系列起点)+ 出线槽拆分独立
;;;          为 cx_runner(命令 SLOT)。
;;;          v9.1 = 封口线收尾并层: 倒角后"封闭线"并入"分流板"、圆角后
;;;          "分流板假体封闭线"并入"分流板假体", 两封闭线图层随之移除;
;;;          "分流板挖孔"全部更名"分流板假体"。
;;;          v9.2 = 新增热咀: 参数 热咀偏移(40)/热咀半径(11.35), 每条
;;;          分流板封口线端头沿通道向内偏移处画圆 → "热咀与点孔"图层(橙)。
;;;          v9.3 = 新增点孔: 参数 点孔半径(默认3, 设0不画), 与热咀圆
;;;          同心; 图层"热咀"更名"热咀与点孔"。
;;;          v9.4 = 图层名全部改为拼音缩写(LD/FLB/FBX/LS/JT/JTFBX/RZ/CX,
;;;          见上方对照表), 根治中文名编码问题; 热咀与点孔拆分为 RZ/DK
;;;          两层; 新建 DP(垫片)预留层; 移除旧图残留清理项。
;;;          v9.5 = 界面修正: 参数框分组标题 RZ→"热咀和点孔"(中文);
;;;          ensure-layer 对已存在图层自动纠正大小写(如 dp→DP)。
;;;          v9.6 = 螺丝孔双同心圆(R4.25+R7)合并为单圆, 参数单化
;;;          为 螺丝孔R(默认 4.25, 对话框可改)。
;;;          v9.7 = OFF 预建三脚本全部 13 个图层: 新增 LD/CXK/JRTDW
;;;          (原 LD 靠用户手建, CXK 由 slot 分流按需建, JRTDW 无脚本建),
;;;          建层提前到选 LD 对象之前 —— 空图跑 OFF 即可一次建齐, LD 无
;;;          对象时提示后就中止(图层已就绪); 清理范围不变。颜色与
;;;          slot/jrt 自建时一致(CXK 蓝5/JRT 黄2), ensure-layer 对已存在
;;;          图层不改属性, 三脚本互不冲突。
;;;          v9.8 = 多模板框架(通用/矩形, 模式同 jrt v9.8): OFF 先弹模板
;;;          选择框; 新增参数 板角倒角(默认10, 矩形模板用); 矩形模板 =
;;;          LD 范围向外扩矩形板边+四角倒角+圆角矩形假体+热咀(预画 RZ
;;;          优先/流道拐点兜底)+螺丝(预画 LS 优先/左右板边中点兜底),
;;;          process 级覆盖自管全流程(含建 13 层/清理/统计); 通用模板
;;;          行为零变化。
;;;          v9.8a = 修复矩形模板中止于"variantp 类型错误": vla-getboundingbox
;;;          的输出参数部分版本绑定为 safearray 本体(非 variant), 解包
;;;          改为两种绑定兼容(dt:rect-bb-pts)。
;;;          v9.9 = 参数框按模板动态显示(v9.8 方案A落地, 同 jrt v9.9):
;;;          dt:flb-template-table 各模板参数默认表列出该模板用到的键,
;;;          dt:dcl-lines 按键动态生成 edit_box, 预填/应用/恢复默认/命令行
;;;          汇总都只处理当前模板的键; 未列出的参数选模板时重置为默认。
;;;          v10.0 = 矩形模板: 螺丝孔内偏默认 15(通用模板保持 10); 画完
;;;          自动删除 LD 源线(slot v9.6 同款约定, 重跑需重画, 与画图同组
;;;          撤销)。FBX/JTFBX 空临时层对 NX 建模脚本无影响(建模仅认
;;;          LAYER_TABLE 图层), 不处理。
;;;          v10.1 = 参数默认值外置 flb_runner.ini(按模板分节, 记事本
;;;          可改, 弹框前重读=随时生效, 首次运行自动生成); 参数记忆
;;;          flb_runner_mem.ini(按模板各一套, 确定参数框自动保存, 上次
;;;          模板+上次值跨会话恢复); 恢复默认按钮 = ini 配置的默认值。
;;;          v10.2 = 假体重构为"包络法": JT = FLB 包络盒外扩(hole-dist -
;;;          offset-dist)的圆角矩形, 四角 R=假体圆角R —— 与矩形模板假体同
;;;          概念, 任意通道布局一步封闭(内部通道由毛坯盘直接桥过)。修复
;;;          工字形(通道间距 70≤D<100)下旧"LD偏移+带状裁剪+端点封口"互删
;;;          碎裂、JT 不封闭不包裹的问题(手画答案 flb_1.dxf 逐点验证: 四边
;;;          =FLB包络±15, 四角弧圆心=FLB角点)。hole_extend 仅旧回退路径使用。
;;;          v10.2b = 修复两处实测错误: 1) dt:jt-build 的包络盒改用
;;;          dt:rect-bbox(v9.8a 双绑定兼容实现) —— 此前内联 vla-getboundingbox
;;;          漏传两个引用参数恒失败, 误触发回退; 2) 封口/端点收集跳过文字
;;;          对象(圆角"半径递减"标注在 JT 层时, close-channels 的
;;;          vlax-curve-getstartpoint 对 AcDbText 报"参数值错误"中断)。
;;;          v10.2c = 修复包络矩形四角弧: 1) 象限整体错转 90°(每角画成隔壁
;;;          角的弧, 与四边不接) —— 改为正确象限, 与矩形模板同款圆角矩形
;;;          代码一致; 2) 四弧补 vla-put-layer(此前落在当前层); 3) 倒角计数
;;;          陈年 bug(v6.0 起): chamfer-one 正常路径返回 (起点成功,终点成功),
;;;          入口把第二个数当失败数 → 每条封口线虚报 1 失败(4 封口线恒报
;;;          "失败 4 端"), 几何其实全成功(flb_3 实测: 8 斜线俱在); 统一为
;;;          (成功数, 失败数) 并补 find-touch 失败分支的标注。
;;;          v10.2d = 全面审查定稿版(与 slot v10.1 / jrt v9.13 / dt_start
;;;          v2.6 同期): 1) 参数框数值读取 atof→distof(垃圾输入不再被静默
;;;          当成 0, 坑 #54); 2) INI 节名解析改用"截到行尾再裁方括号",
;;;          修复 AutoCAD 2021 之前 strlen 按字节/substr 按字符导致中文
;;;          节名(如"[通用]")残留 "]" 而配置节永远匹配不上的问题;
;;;          3) 记忆文件不再重复写出第二个 [模板] 节; 4) 补声明全部遗漏的
;;;          foreach/setq 局部变量(此前 no/cl/seg/pt/obj 等泄漏为全局);
;;;          5) 闭合多段线判定补 vl-catch-all-error-p(原写法在 vla-get-closed
;;;          失败时会抛类型错误); 6) 假体包络矩形圆角上限改为与矩形模板
;;;          同款 0.45×短边; 7) 删除死函数 dt:fix-layer-case 及未使用局部。
;;;          v10.5 = 假体改人工决策: 参数框新增勾选框「假体用包络法」(默认
;;;          不勾=传统逐步直跑); 默认值外置 ini [假体] envelope(旧文件自动
;;;          追加该节, 不动用户已改值); 确定才记忆(mem [假体]), 恢复默认=ini
;;;          值; 勾选但包络失败时不静默回退传统, 明确提示本次无假体。
;;;          完整版本历史(v1.0 → v9.7)见 AGENTS_CAD.md。
;;;          v10.4 = 应要求包络法改分步绘制: 步骤1 画 FLB 原始包络盒
;;;          (独立撤销组, 观察包络盒从哪来) → 步骤2 删盒+画外扩圆角矩形
;;;          成品(独立撤销组) —— UNDO 可逐步后退观察; c:OFF 恢复调用
;;;          包络法(传统五步此前一轮按用户要求直跑过, 函数仍全保留)。
;;; 实现方式: 全部为纯编程式几何操作(不调用任何CAD命令, 不会中断)。
;;; 已知限制:
;;;   - 多段线重建/修剪会丢失圆弧段凸度(bulge);
;;;   - 闭合多段线跳过(请先炸开);
;;;   - 两条流道中心线距离小于 2 倍偏移距离(区域重叠)时, 侵入段按规则删除;
;;;   - 圆角半径尝试到 1 仍无法相切的断口将跳过并计入统计;
;;;   - 流道线端点若位于交叉区域内(偏移线端头被圆角修剪), 该端无法封口, 跳过;
;;; 说明   : 本文件请以 UTF-8(BOM) 或 ANSI(GBK) 编码保存, 避免中文乱码。
;;; ============================================================================

(vl-load-com)  ; 加载 Visual LISP 扩展, 使 vla-* 系列函数可用

;; ============================================================================
;; 全局参数(v8.0 新增) —— 可由参数对话框(命令 PARAM, 或 OFF 弹出)修改
;; 修改后对后续所有流程生效; 也可在命令行直接 setq 覆盖(如 (setq *dt-offset-dist* 40.0))
;; v9.1: 默认值/预填/应用/恢复默认统一由 dt:param-table 驱动, 新增参数只需
;;       在表中加一行 + dt:dcl-lines 加对应 edit_box, 不再改多处(根除 v8.8 类失同步)
;; ============================================================================
(setq dt:param-table
      (list
        (list "offset_dist" '*dt-offset-dist* 35.0) ; 分流板偏移距离(向两侧各偏移该值)
        (list "hole_dist" '*dt-hole-dist* 50.0) ; 假体偏移距离
        (list "hole_extend" '*dt-hole-extend* 15.0) ; 假体线端头延长量(假体封闭线靠外 15)
        (list "fillet_r" '*dt-fillet-r* 15.0) ; 分流板圆角半径(断口圆角, 不足自动递减)
        (list "fillet_r_hole" '*dt-fillet-r-hole* 15.0) ; 假体圆角半径(假体断口+假体封口)
        (list "chamfer_d" '*dt-chamfer-d* 5.0) ; 封口倒角距离
        (list "screw_in" '*dt-screw-in* 10.0) ; 螺丝孔向内偏移距离
        (list "screw_r" '*dt-screw-r* 4.25) ; 螺丝孔半径(v9.6: 双圆合并为单圆)
        (list "nozzle_offset" '*dt-nozzle-offset* 40.0) ; 热咀偏移(封口线中点沿通道向内)
        (list "nozzle_r" '*dt-nozzle-r* 11.35) ; 热咀半径
        (list "pin_r" '*dt-pin-r* 3.0) ; 点孔半径(与热咀圆同心, 设 0 不画)
        (list "rect_chamfer" '*dt-rect-chamfer* 10.0) ; 板角倒角(v9.8 矩形模板: 板边四角45°倒角)
        (list "zjj_r" '*dt-zjj-r* 14.35))) ; 主进胶半径(默认14.35, DP圆心画圆)
(foreach p dt:param-table (set (cadr p) (caddr p)))
(setq *dt-jt-envelope* nil)  ; v10.5: 假体包络法开关(参数框勾选框; 默认关=传统逐步; ini[假体]节/mem 可改)

;; ============================================================================
;; 参数配置与记忆(v10.1): 默认值外置 flb_runner.ini(按模板分节, 记事本可改,
;; 每次弹框前重读=随时生效); 上次值记忆 flb_runner_mem.ini(按模板各一套,
;; 确定参数框时自动保存, 上次模板+上次值跨会话恢复)。
;; 解析只认"键 = 数值"行, 注释/空行/未知键跳过; 全程 vl-catch-all 保护,
;; 文件缺失/损坏静默回退代码内置默认。命名带 dt:off- 前缀防同加载覆盖(坑 #46)。
;; 函数在此定义, 启动 (dt:flb-cfg-boot) 在文件尾调用(定义须先于执行)。
;; ============================================================================
(setq *dt-flb-cfg* nil   ; 配置(默认值) ((节 (键 . 值)...) ...) 节=模板名
      *dt-flb-mem* nil)  ; 记忆(上次值)   同结构 + [模板] template=下标

;; 配置/记忆文件目录: 优先 dt_start 注入的脚本目录, 无则 TEMP(与 find-dcl 同规则)
(defun dt:flb-cfg-dir ( / )
  (if (and *dt-script-dir* (/= *dt-script-dir* ""))
    *dt-script-dir*
    (getenv "TEMP")))

;; 单行 "键 = 数值" → (键 . 值); 无等号/空值/非数值返回 nil(distof 校验, 0 合法)
(defun dt:flb-cfg-kv (ln / p k vs n)
  (setq p (vl-string-search "=" ln))
  (if p
    (progn
      (setq k (vl-string-trim " \t" (substr ln 1 p))
            vs (vl-string-trim " \t" (substr ln (+ p 2)))
            n (if (= vs "") nil (distof vs)))
      (if (and (/= k "") n (numberp n)) (cons k n) nil))
    nil))

;; 读 INI → ((节名 (键 . 值)...) ...); 文件不存在/读失败返回 nil
(defun dt:flb-cfg-read (path / f ln sec ent tmp secs)
  (setq secs nil sec nil)
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "r"))
       (if f
         (progn
           (while (setq ln (read-line f))
             (setq ln (vl-string-trim " \t\r" ln))
             (cond
               ((= ln "") nil)
               ((member (substr ln 1 1) '(";" "#")) nil)
               ((= (substr ln 1 1) "[")
                ;; v10.2d: 原用 (- (strlen ln) 2) 取长度 —— AutoCAD 2021 之前
                ;;   strlen 按字节计而 substr 按字符计, 中文节名(如 "[通用]")
                ;;   会连带尾部 "]"(变成 "通用]")导致配置节永远匹配不上。
                ;;   改为截到行尾再统一裁方括号, 新旧 LISP 都正确。
                (setq sec (vl-string-trim " \t[]" (substr ln 2))))
               ((setq ent (dt:flb-cfg-kv ln))
                (if (and sec (/= sec ""))
                  (progn
                    (setq tmp (vl-remove (assoc (car ent) (cdr (assoc sec secs)))
                                         (cdr (assoc sec secs)))
                          tmp (cons ent tmp)
                          secs (cons (cons sec tmp)
                                     (vl-remove (assoc sec secs) secs))))))))
           (close f)
           (setq f nil))))
    nil)
  ;; v10.6: 异常兜底关闭 —— 读行中途出错时句柄不再滞留
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (reverse secs))

;; 数据 → 指定节的键值表(无该节 nil)
(defun dt:flb-cfg-sec (data sec / e)
  (if (and data (setq e (assoc sec data))) (cdr e)))

;; 节内取键值(无该键 nil; 值可为 0, 0 非 nil 仍算"有")
(defun dt:flb-cfg-get (data sec key)
  (cdr (assoc key (dt:flb-cfg-sec data sec))))

;; 当前模板的参数默认值: ini 配置节 → 模板内置默认表 → dt:param-table caddr
(defun dt:flb-param-default (key / tpl v)
  (setq tpl (dt:flb-template-row))
  (cond ((setq v (dt:flb-cfg-get *dt-flb-cfg* (car tpl) key)) v)
        ((cdr (assoc key (nth 2 tpl))))
        (T (caddr (assoc key dt:param-table)))))

;; 首次自动生成配置文件(按模板分节 + 中文注释标签)
(defun dt:flb-cfg-gen (path / f tpl kv lbl)
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "w"))
       (if f
         (progn
           (write-line "; flb_runner 参数默认值配置(首次运行自动生成, 记事本可改)" f)
           (write-line "; 按模板分节; 改数值保存后, 下次打开模板/参数窗口即生效(无需重载)" f)
           (write-line "; 恢复默认按钮 = 本文件的值; 删除本文件 = 回代码内置默认" f)
           (write-line "; 上次填的值在 flb_runner_mem.ini(程序自动维护, 一般不用管)" f)
           (write-line "" f)
           (foreach tpl dt:flb-template-table
             (write-line (strcat "[" (car tpl) "]") f)
             (foreach kv (nth 2 tpl)
               (setq lbl (cdr (assoc (car kv) dt:flb-param-labels)))
               (if lbl (write-line (strcat "; " lbl) f))
               (write-line (strcat (car kv) " = " (rtos (cdr kv) 2 4)) f))
             (write-line "" f))
           ;; v10.5: 包络法勾选框默认值(独立节, 不随模板)
           (write-line "[假体]" f)
           (write-line "; 假体绘制方式: 1=包络法(FLB外扩整体圆角矩形) 0=传统逐步(默认)" f)
           (write-line "envelope = 0" f)
           (write-line "" f)
           (close f)
           (setq f nil))))
    nil)
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  T)

;; 确定参数框后保存当前模板的上次值(每模板各一套; 只存该模板可见键)
(defun dt:flb-mem-save ( / name keys vals path sc f kv)
  (setq name (car (dt:flb-template-row))
        keys (dt:flb-tpl-keys)
        vals (mapcar '(lambda (k) (cons k (eval (cadr (assoc k dt:param-table)))))
                     keys))
  (setq *dt-flb-mem* (cons (cons name vals)
                           (vl-remove (assoc name *dt-flb-mem*) *dt-flb-mem*))
        path (strcat (dt:flb-cfg-dir) "\\flb_runner_mem.ini"))
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "w"))
       (if f
         (progn
           (write-line "; flb_runner 参数记忆(确定参数窗口时自动更新, 可删除)" f)
           (write-line "[模板]" f)
           (write-line (strcat "template = " (itoa *dt-flb-template*)) f)
           (write-line "" f)
           (foreach sc *dt-flb-mem*
             ;; v10.2d: 跳过 "[模板]" 节(上方已单独写出)—— 此前会把它再写
             ;;   一遍, 造成 mem 文件里出现两个 [模板](第二个值为 rtos 格式)
             ;; v10.5: 同理跳过 "[假体]" 节(下方已单独写出)
             (if (not (member (car sc) '("模板" "假体")))
               (progn
                 (write-line (strcat "[" (car sc) "]") f)
                 (foreach kv (cdr sc)
                   (write-line (strcat (car kv) " = " (rtos (cdr kv) 2 4)) f))
                 (write-line "" f))))
           ;; v10.5: 包络法勾选框记忆(与数值参数同语义: 确定才记忆)
           (write-line "[假体]" f)
           (write-line (strcat "envelope = " (if *dt-jt-envelope* "1" "0")) f)
           (write-line "" f)
           (close f)
           (setq f nil))))
    nil)
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (princ))

;; 加载末尾调用: 生成缺失配置 + 恢复上次模板与该模板的上次参数值
(defun dt:flb-cfg-boot ( / path idx)
  (vl-catch-all-apply
    '(lambda ( )
       (setq path (strcat (dt:flb-cfg-dir) "\\flb_runner.ini"))
       (setq *dt-flb-cfg* (dt:flb-cfg-read path))
       (if (null *dt-flb-cfg*)
         (progn
           (dt:flb-cfg-gen path)
           (setq *dt-flb-cfg* (dt:flb-cfg-read path))))
       (setq *dt-flb-mem*
             (dt:flb-cfg-read (strcat (dt:flb-cfg-dir) "\\flb_runner_mem.ini")))
       ;; v10.5: 旧 ini 迁移 —— [假体] 节缺失时追加(不重写全文件, 保留用户已改值)
       (if (null (dt:flb-cfg-get *dt-flb-cfg* "假体" "envelope"))
         (vl-catch-all-apply
           '(lambda ( / f)
              (setq f (open path "a"))
              (if f
                (progn
                  ;; v10.6: 写中途异常也保证 close(句柄不滞留)
                  (vl-catch-all-apply
                    '(lambda ( )
                       (write-line "" f)
                       (write-line "[假体]" f)
                       (write-line "; 假体绘制方式: 1=包络法(FLB外扩整体圆角矩形) 0=传统逐步(默认)" f)
                       (write-line "envelope = 0" f))
                    nil)
                  (close f)))))
         nil)
       ;; v10.5: 勾选框恢复 —— 记忆值优先, 无记忆用 ini 默认(缺省关)
       (setq idx (dt:flb-cfg-get *dt-flb-mem* "假体" "envelope"))
       (if (null idx) (setq idx (dt:flb-cfg-get *dt-flb-cfg* "假体" "envelope")))
       (setq *dt-jt-envelope* (and idx (/= idx 0.0)))
       (setq idx (dt:flb-cfg-get *dt-flb-mem* "模板" "template"))
       (if (and idx (numberp idx)
                (>= (fix idx) 0) (< (fix idx) (length dt:flb-template-table)))
         (progn
           (setq *dt-flb-template* (fix idx)
                 *dt-flb-tpl-pick* (fix idx))
           (dt:flb-apply-template (fix idx) T))))
    nil)
  (princ))

;; ============================================================================
;; 一、工具函数
;; ============================================================================

;; 计算两点距离
(defun dt:dist (p1 p2)
  (sqrt (+ (expt (- (car p1) (car p2)) 2)
           (expt (- (cadr p1) (cadr p2)) 2)
           (expt (- (caddr p1) (caddr p2)) 2))))

;; 把平铺坐标列表 (x1 y1 z1 x2 y2 z2 ...) 转成点列表 ((x1 y1 z1) (x2 y2 z2) ...)
(defun dt:flat->pts (lst / pts)
  (setq pts nil)
  (while lst
    (setq pts (cons (list (car lst) (cadr lst) (caddr lst)) pts)
          lst (cdddr lst)))
  (reverse pts))

;; 求两个 VLA 对象的交点列表 (不延伸)
;; 必须用 vla-intersectwith(返回类型固定的 Variant), 不要用 vlax-invoke
(defun dt:inters-pts (o1 o2 / v arr)
  (setq v (vl-catch-all-apply 'vla-intersectwith (list o1 o2 0)))
  (if (not (vl-catch-all-error-p v))
    (progn
      (setq arr (vl-catch-all-apply
                  'vlax-safearray->list (list (vlax-variant-value v))))
      (if (not (vl-catch-all-error-p arr))
        (dt:flat->pts arr)
        nil))
    nil))

;; 选择集 -> 图元名列表
(defun dt:ss->list (ss / i lst)
  (setq i 0 lst nil)
  (repeat (sslength ss)
    (setq lst (cons (ssname ss i) lst)
          i (1+ i)))
  (reverse lst))

;; 当前文档模型空间(集中获取, 避免各函数重复拼 vla-get 链)
(defun dt:ms ()
  (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object))))

;; 选中指定图层全部对象并转为 VLA 对象列表(图层为空返回 nil)
(defun dt:layer-vlas (layer / ss)
  (setq ss (ssget "X" (list (cons 8 layer))))
  (if ss
    (mapcar 'vlax-ename->vla-object (dt:ss->list ss))))

;; 取多段线的全部顶点(3D点列表)
(defun dt:poly-pts (obj / coords is-2d n i pts)
  (setq coords (vlax-safearray->list (vlax-variant-value (vla-get-coordinates obj)))
        is-2d   (member (vla-get-objectname obj) '("AcDbLWPolyline" "AcDbPolyline")))
  (if is-2d
    (setq n (/ (length coords) 2))
    (setq n (/ (length coords) 3)))
  (setq i 0 pts nil)
  (repeat n
    (if is-2d
      (setq pts (cons (list (nth (* i 2) coords)
                            (nth (1+ (* i 2)) coords)
                            0.0) pts))
      (setq pts (cons (list (nth (* i 3) coords)
                            (nth (1+ (* i 3)) coords)
                            (nth (+ 2 (* i 3)) coords)) pts)))
    (setq i (1+ i)))
  (reverse pts))

;; 直线上按"到起点距离"取点: sp=起点 ep=终点 d=距离 total=总长
(defun dt:point-on-line (sp ep d total / k)
  (if (> total 1e-9)
    (progn
      (setq k (/ d total))
      (list (+ (car sp) (* k (- (car ep) (car sp))))
            (+ (cadr sp) (* k (- (cadr ep) (cadr sp))))
            (+ (caddr sp) (* k (- (caddr ep) (caddr sp))))))
    sp))

;; 已排序的数值列表按容差去重
(defun dt:uniq (lst tol / r x)
  (setq r nil)
  (foreach x lst
    (if (or (null r) (> (- x (car r)) tol))
      (setq r (cons x r))))
  (reverse r))

;; eName 排除判定: 对象 obj 是否在 eName 列表 exclude 中
;; (v8.14 关键坑: vla-object 每次转换生成新实例, 跨函数 equal 恒不成立,
;;  对象身份比较必须用 eName)
(defun dt:excluded-p (obj exclude)
  (vl-some '(lambda (x) (equal x (vlax-vla-object->ename obj)))
           exclude))

;; v10.6: 实体是否为可求端点/曲线参数的曲线(直线/弧/多段线) —— 文字/块等
;; 混入源图层或产物图层时 vlax-curve 系列会抛"参数类型错误"中断流程
;; (v10.2b 只防了封口/端点收集侧, 本次统一补全), 收集/迭代前先过本判定
(defun dt:curve-p (obj / tp)
  (setq tp (vl-catch-all-apply 'vla-get-objectname (list obj)))
  (if (vl-catch-all-error-p tp)
    nil
    (member tp '("AcDbLine" "AcDbArc" "AcDbLWPolyline" "AcDbPolyline"))))

;; v10.6: 列表过滤, 只留 dt:curve-p 为真的实体
(defun dt:curves-only (vla-list)
  (vl-remove-if '(lambda (o) (not (dt:curve-p o))) vla-list))

;; 点相对圆心的角度, 归一化到 [start-a, start-a+2pi)
(defun dt:norm-angle (pt center start-a / a)
  (setq a (angle (list (car center) (cadr center)) (list (car pt) (cadr pt))))
  (if (< a start-a) (setq a (+ a (* 2 pi))))
  (if (>= a (+ start-a (* 2 pi))) (setq a (- a (* 2 pi))))
  a)

;; 判断点是否位于某条流道线的带状区域内
;; (即: 该点到最近一条流道中心线的距离 < 偏移距离 - 容差)
(defun dt:in-zone (pt center-lines off-dist / d cp cl)
  (setq d 1e30)
  (foreach cl center-lines
    (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list cl pt)))
    (if (not (vl-catch-all-error-p cp))
      (setq d (min d (distance pt cp)))))
  (< d (- off-dist 1e-3)))

;; ===================== 向量工具 =====================

;; 向量单位化(零向量原样返回)
(defun dt:unit (v / l)
  (setq l (sqrt (+ (* (car v) (car v))
                   (* (cadr v) (cadr v))
                   (* (caddr v) (caddr v)))))
  (if (> l 1e-12)
    (list (/ (car v) l) (/ (cadr v) l) (/ (caddr v) l))
    v))

;; 点 + 方向向量 * 标量
(defun dt:pt+vec (p v s)
  (list (+ (car p) (* (car v) s))
        (+ (cadr p) (* (cadr v) s))
        (+ (caddr p) (* (caddr v) s))))

;; 反余弦 (AutoLISP 无内置 acos)
(defun dt:acos (c / cc)
  (setq cc c)
  (if (> cc 1.0) (setq cc 1.0))
  (if (< cc -1.0) (setq cc -1.0))
  (if (>= cc 1.0) 0.0
    (if (<= cc -1.0) pi
      (atan (sqrt (- 1.0 (* cc cc))) cc))))

;; 正切 (AutoLISP 无内置 tan)
(defun dt:tan (a)
  (/ (sin a) (cos a)))

;; 两个方向向量之间的夹角(弧度, 0 ~ pi)
(defun dt:angle-between (d1 d2 / l1 l2 dot)
  (setq l1 (sqrt (+ (* (car d1) (car d1))
                    (* (cadr d1) (cadr d1))
                    (* (caddr d1) (caddr d1))))
        l2 (sqrt (+ (* (car d2) (car d2))
                    (* (cadr d2) (cadr d2))
                    (* (caddr d2) (caddr d2))))
        dot (+ (* (car d1) (car d2))
               (* (cadr d1) (cadr d2))
               (* (caddr d1) (caddr d2))))
  (if (and (> l1 1e-12) (> l2 1e-12))
    (dt:acos (/ dot (* l1 l2)))
    0.0))

;; 判断两个方向是否不平行(夹角在 0.05 ~ pi-0.05 之外视为平行)
(defun dt:not-parallel (d1 d2 / ang)
  (setq ang (dt:angle-between d1 d2))
  (and (> ang 0.05) (< ang (- pi 0.05))))

;; 判断角度 am 是否落在从 a1 逆时针到 a2 的短弧内
(defun dt:arc-covers (a1 a2 am / sweep rel)
  (setq sweep (if (> a2 a1) (- a2 a1) (+ (- a2 a1) (* 2 pi)))
        rel   (if (> am a1) (- am a1) (+ (- am a1) (* 2 pi))))
  (< rel sweep))

;; 取曲线两端头信息: 返回 ((起点 起点指向主体方向) (终点 终点指向主体方向))
;; 方向均指向"曲线主体"内部, 用于圆角/倒角计算
(defun dt:end-infos (obj / sp ep sd ed)
  (setq sp (vlax-curve-getstartpoint obj)
        ep (vlax-curve-getendpoint obj)
        sd (dt:unit (vlax-curve-getfirstderiv obj (vlax-curve-getstartparam obj)))
        ed (dt:unit (vlax-curve-getfirstderiv obj (vlax-curve-getendparam obj))))
  ;; 终点处一阶导数指向曲线延伸方向, 取反使其指向主体
  (setq ed (list (- (car ed)) (- (cadr ed)) (- (caddr ed))))
  (list (list sp sd) (list ep ed)))

;; 把曲线的一个端头移动到新位置(直线改端点, 圆弧改角度, 多段线改顶点)
;; v7.11: 增加圆弧支持 —— 圆弧的 StartPoint/EndPoint 是只读属性,
;;  vla-put-startpoint 对 AcDbArc 无效(静默失败), 导致圆弧端头修剪失效,
;;  圆角弧"单独加上去"(残余线未剪)。改为设置 StartAngle/EndAngle。
(defun dt:set-endpoint (obj et pt / is-poly is-arc c r ang n)
  (setq is-poly (= (vla-get-objectname obj) "AcDbPolyline")
        is-arc  (= (vla-get-objectname obj) "AcDbArc"))
  (cond
    (is-poly
     (if (= et "S")
       (vla-put-coordinate obj 0 (vlax-3d-point pt))
       (progn
         (setq n (vla-get-numberofvertices obj))
         (vla-put-coordinate obj (1- n) (vlax-3d-point pt)))))
    (is-arc
     ;; 圆弧: 端头移动到"圆心指向 pt 的角度"处(在弧半径上)
     (setq c (vlax-safearray->list (vlax-variant-value (vla-get-center obj)))
           r (vla-get-radius obj)
           ang (angle (list (car c) (cadr c)) (list (car pt) (cadr pt))))
     (if (= et "S")
       (vla-put-startangle obj ang)
       (vla-put-endangle obj ang)))
    (T
     (if (= et "S")
       (vla-put-startpoint obj (vlax-3d-point pt))
       (vla-put-endpoint obj (vlax-3d-point pt))))))

;; 返回曲线上"从指定端头沿曲线向内走 dist 距离"的点(保证在曲线上!)
;; v7.16 关键修复: 圆角/倒角的切点必须用"沿曲线走"而非"切线方向外推"。
;;  对直线两者相同; 对圆弧, 切线方向外推的点不在弧上(vla-offset/裁剪后
;;  假体线常为弧), 导致修剪后的弧端头与圆角弧端点不重合 —— 圆角弧
;;  "单独加上去"、线头有残余。沿曲线走(弧长)则切点一定在曲线上。
;; obj = 曲线对象, et = "S"/"E", dist = 距离
(defun dt:endpoint-in (obj et dist / total)
  (setq total (vlax-curve-getdistatparam obj (vlax-curve-getendparam obj)))
  (if (= et "S")
    (vlax-curve-getpointatdist obj (min dist total))
    (vlax-curve-getpointatdist obj (max 0.0 (- total dist)))))

;; ============================================================================
;; 二、切割重建链 —— v3.0 建立, v9.1 统一
;; 区域裁剪(dt:trim-curve)与出线槽打断(dt:break-curve)共用同一驱动
;; dt:cut-curve: 把曲线按交点切成小段 -> 逐段过滤(裁剪=段中点落流道带状
;; 区域内则删; 打断=全保留) -> 保留段重建为新对象(放指定图层), 删原对象。
;; 切割参数: 直线=到起点距离, 圆弧=归一化角度差, 多段线=曲线参数。
;; (v7.9 起 layer 参数化: 重建段放入调用方指定的图层, 不再硬编码)
;; ============================================================================

;; 类型分发: 交点列表 -> 排序去重后的切割参数列表(首 0, 尾全长)
(defun dt:cut-params (obj others-pts / obj-type sp ep total center start-a end-param
                      cut)
  (setq obj-type (vla-get-objectname obj))
  (cond
    ((= obj-type "AcDbLine")
     (setq sp (vlax-safearray->list (vlax-variant-value (vla-get-startpoint obj)))
           ep (vlax-safearray->list (vlax-variant-value (vla-get-endpoint obj)))
           total (dt:dist sp ep))
     (append (list 0.0)
             (dt:uniq (vl-sort (mapcar '(lambda (p) (dt:dist p sp)) others-pts) '<) 1e-6)
             (list total)))
    ((= obj-type "AcDbArc")
     (setq center (vlax-safearray->list (vlax-variant-value (vla-get-center obj)))
           start-a (vla-get-startangle obj)
           end-param (vla-get-endangle obj))
     (if (< end-param start-a) (setq end-param (+ end-param (* 2 pi))))
     (setq cut (dt:uniq (vl-sort (mapcar '(lambda (p) (dt:norm-angle p center start-a))
                                         others-pts) '<) 1e-6)
           cut (mapcar '(lambda (a) (- a start-a)) cut))
     (append (list 0.0) cut (list (- end-param start-a))))
    (T ; 多段线: 参数 = 顶点索引 + 段内比例
     ;; v10.6: 交点浮点偏移曲线时 getparamatpoint 可能返回 nil(甚至抛错),
     ;;   先 catch 求值并剔除 nil 再排序 —— nil 进 vl-sort 报 bad argument
     (append (list 0.0)
             (dt:uniq (vl-sort
                        (vl-remove-if 'null
                          (mapcar '(lambda (p) (vl-catch-all-apply
                                                 'vlax-curve-getparamatpoint
                                                 (list obj p)))
                                  others-pts))
                        '<) 1e-6)
             (list (vlax-curve-getendparam obj))))))

;; 类型分发: 段中点(用于裁剪模式的区域判断)
(defun dt:seg-mid (obj t1 t2 / obj-type sp ep total center radius start-a m)
  (setq obj-type (vla-get-objectname obj))
  (cond
    ((= obj-type "AcDbLine")
     (setq sp (vlax-safearray->list (vlax-variant-value (vla-get-startpoint obj)))
           ep (vlax-safearray->list (vlax-variant-value (vla-get-endpoint obj)))
           total (dt:dist sp ep))
     (dt:point-on-line sp ep (/ (+ t1 t2) 2.0) total))
    ((= obj-type "AcDbArc")
     (setq center (vlax-safearray->list (vlax-variant-value (vla-get-center obj)))
           radius (vla-get-radius obj)
           start-a (vla-get-startangle obj)
           m (polar center (+ start-a (/ (+ t1 t2) 2.0)) radius))
     (list (car m) (cadr m) (caddr center)))
    (T (vlax-curve-getpointatparam obj (/ (+ t1 t2) 2.0)))))

;; 类型分发: 按参数区间 [t1, t2] 重建一段, 放入 layer(返回新对象或 nil)
(defun dt:rebuild-seg (obj t1 t2 layer / obj-type sp ep total p1 p2 center radius
                       start-a new-obj is-2d)
  (setq obj-type (vla-get-objectname obj)
        new-obj nil)
  (cond
    ((= obj-type "AcDbLine")
     (setq sp (vlax-safearray->list (vlax-variant-value (vla-get-startpoint obj)))
           ep (vlax-safearray->list (vlax-variant-value (vla-get-endpoint obj)))
           total (dt:dist sp ep)
           p1 (dt:point-on-line sp ep t1 total)
           p2 (dt:point-on-line sp ep t2 total))
     (setq new-obj (vla-addline (dt:ms) (vlax-3d-point p1) (vlax-3d-point p2))))
    ((= obj-type "AcDbArc")
     (setq center (vlax-safearray->list (vlax-variant-value (vla-get-center obj)))
           radius (vla-get-radius obj)
           start-a (vla-get-startangle obj))
     (setq new-obj (vla-addarc (dt:ms) (vlax-3d-point center) radius
                               (+ start-a t1) (+ start-a t2))))
    (T
     (setq is-2d (member obj-type '("AcDbLWPolyline" "AcDbPolyline")))
     (setq new-obj (dt:poly-rebuild obj t1 t2 (dt:poly-pts obj) is-2d))))
  (if new-obj (vla-put-layer new-obj layer))
  new-obj)

;; 通用切割驱动:
;;   mode = nil     打断模式: 所有段保留
;;   mode = "TRIM"  裁剪模式: 段中点落在任一中心线带状区域(center-lines,
;;                  宽 off-dist)内的段删除("伸进别人区域的段删掉")
;; 返回 T=已处理(整线保留/整线删除/重建), nil=跳过(无交点/闭合多段线/
;; 不支持类型)。原线仅在"确有段被删"时才删除重建。
(defun dt:cut-curve (obj others-pts layer center-lines off-dist mode /
                     obj-type cut t-end i t1 t2 keep-segs closed-p seg)
  (if (null layer) (setq layer "FLB"))
  (if (null others-pts)
    nil
    (progn
      (setq obj-type (vla-get-objectname obj))
      (cond
        ((not (member obj-type '("AcDbLine" "AcDbArc"
                                 "AcDbLWPolyline" "AcDbPolyline")))
         (princ (strcat "\n  跳过: " obj-type " 暂不支持切割处理。"))
         nil)
        ((and (member obj-type '("AcDbLWPolyline" "AcDbPolyline"))
              (progn
                (setq closed-p (vl-catch-all-apply 'vla-get-closed (list obj)))
                (and (not (vl-catch-all-error-p closed-p)) (< closed-p 0))))
         (princ "\n  跳过: 闭合多段线。")
         nil)
        (T
         (setq cut (dt:cut-params obj others-pts)
               t-end (last cut)
               keep-segs nil i 0)
         (while (< i (1- (length cut)))
           (setq t1 (nth i cut)
                 t2 (nth (1+ i) cut))
           (if (> (- t2 t1) 1e-9)
             (if (or (null mode)
                     (not (dt:in-zone (dt:seg-mid obj t1 t2)
                                      center-lines off-dist)))
               (setq keep-segs (cons (list t1 t2) keep-segs))))
           (setq i (1+ i)))
         (setq keep-segs (reverse keep-segs))
         (cond
          ;; 整条线都在区域内: 删除
          ((null keep-segs) (vla-delete obj) T)
          ;; 仅一段且覆盖全长: 保持原样
          ((and (= (length keep-segs) 1)
                (< (abs (caar keep-segs)) 1e-6)
                (< (abs (- (cadar keep-segs) t-end)) 1e-6))
           T)
          ;; 重建保留段, 删除原线
          (T
           (foreach seg keep-segs
             (dt:rebuild-seg obj (car seg) (cadr seg) layer))
           (vla-delete obj)
           T)))))))

;; 按参数区间 [t1, t2] 重建多段线
(defun dt:poly-rebuild (obj t1 t2 vtx is-2d / new-pts i nv flat ms pt)
  (setq new-pts (list (vlax-curve-getpointatparam obj t1))
        nv (length vtx)
        i 0)
  (while (< i nv)
    (if (and (> i (+ t1 1e-6)) (< i (- t2 1e-6)))
      (setq new-pts (append new-pts (list (nth i vtx)))))
    (setq i (1+ i)))
  (setq new-pts (append new-pts (list (vlax-curve-getpointatparam obj t2))))
  (setq flat nil)
  (foreach pt new-pts
    (if is-2d
      (setq flat (append flat (list (car pt) (cadr pt))))
      (setq flat (append flat (list (car pt) (cadr pt) (caddr pt))))))
  (setq ms (dt:ms))
  (if is-2d
    (vla-addlightweightpolyline
      ms
      (vlax-make-variant
        (vlax-safearray-fill
          (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length flat))))
          flat)
        (logior vlax-vbArray vlax-vbDouble)))
    (vla-addpolyline
      ms
      (vlax-make-variant
        (vlax-safearray-fill
          (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length flat))))
          flat)
        (logior vlax-vbArray vlax-vbDouble)))))

;; 区域裁剪分发(原名/签名不变, trim-all / slot-trim 调用)
(defun dt:trim-curve (obj others-pts center-lines off-dist layer)
  (dt:cut-curve obj others-pts layer center-lines off-dist "TRIM"))

;; 两包围盒 (minx miny maxx maxy) 是否相交(含接触);
;; 任一为 nil(取盒失败)时按相交处理, 不跳过求交 —— 保守不漏
;; (v10.6 新增, 与 slot/jrt 逐字一致; 取盒复用下方 dt:rect-bbox 双绑定兼容实现)
(defun dt:bbox-overlap-p (a b)
  (if (or (null a) (null b))
    T
    (and (<= (car a) (caddr b)) (>= (caddr a) (car b))
         (<= (cadr a) (cadddr b)) (>= (cadddr a) (cadr b)))))

;; 列表内所有线两两求交(不延伸), 返回 ((对象 该对象的交点列表) ...), 顺序与入序一致
;; v10.6: 包围盒预过滤 —— 每对象只取一次 boundingbox(dt:rect-bbox), 两盒
;;   不相交则跳过 COM 求交(bbox 不相交 ⇒ 两曲线必无交点, 结果不变);
;;   大图上把 O(n²) 次 intersectwith 降为相邻对数量级(压力场景提速)
(defun dt:cross-points (vla-list / pts-pairs pair rec obj b1 pts other o)
  (setq pts-pairs nil
        pair nil)
  (setq pair (mapcar '(lambda (o bb) (list o bb))
                     vla-list
                     (mapcar '(lambda (o) (dt:rect-bbox (list o))) vla-list)))
  (foreach rec pair
    (setq obj (car rec) b1 (cadr rec) pts nil)
    (foreach other pair
      (setq o (car other))
      (if (and (not (equal o obj))
               (dt:bbox-overlap-p b1 (cadr other)))
        (setq pts (append pts (dt:inters-pts obj o)))))
    (setq pts-pairs (cons (cons obj pts) pts-pairs)))
  (reverse pts-pairs))

;; 独立区域裁剪入口: 自动处理指定图层(layer)上的全部线条
;; layer 默认 "FLB" (v7.7 起参数化, 假体流程传 "JT")
(defun dt:trim-all (off-dist layer / center-lines vla-list pts-pairs pair
                    trim-count skip-count)
  (if (null off-dist) (setq off-dist 35.0))
  (if (null layer) (setq layer "FLB"))
  (setq center-lines (dt:curves-only (dt:layer-vlas "LD")))
  (if (null center-lines)
    (princ "\n【裁剪】未找到\"LD\"图层, 无法确定流道区域, 跳过裁剪。")
    (progn
      (setq vla-list (dt:curves-only (dt:layer-vlas layer)))
      (if (null vla-list)
        (princ (strcat "\n【裁剪】\"" layer "\"图层上没有对象, 无需裁剪。"))
        (progn
          (princ (strcat "\n【裁剪】\"LD\"图层 " (itoa (length center-lines))
                         " 条中心线, \"" layer "\"图层 " (itoa (length vla-list)) " 条线。"))
          (setq pts-pairs (dt:cross-points vla-list))
          (command "_.UNDO" "BE")
          (setq trim-count 0 skip-count 0)
          (foreach pair pts-pairs
            (if (dt:trim-curve (car pair) (cdr pair) center-lines off-dist layer)
              (setq trim-count (1+ trim-count))
              (setq skip-count (1+ skip-count))))
          (command "_.UNDO" "E")
          (princ (strcat "\n【裁剪】完成: 处理 " (itoa trim-count)
                         " 条线, 跳过 " (itoa skip-count) " 条。"))
          (princ "\n【裁剪】提示: 若想撤销本次裁剪, 输入 UNDO 回车即可。")))))
  (princ))

;; ============================================================================
;; 三、断口圆角 —— v4.0 (A方案: 连接相邻交叉线, 弧凸向交叉中心, 圆心在区域外)
;; ============================================================================

;; 处理一个断口对: 计算圆角几何, 递减半径, 方向验证, 修剪两线, 创建圆角弧, 必要时标注
;; h1/h2 = (对象 端类型" S"/"E" 端头点 指向主体方向)
;; layer = 圆角弧/标注文字所在图层(默认"FLB"; 出线槽 cx_runner 传"CX"等)
;; r-start = 圆角起始半径(v8.2 拆分: 分流板传 *dt-fillet-r*, 挖孔传 *dt-fillet-r-hole*)
;; nochk = T 时跳过圆心区域方向验证(v9.5 大圆角: 延长接头处两源线区域
;;         不重叠, 区域检查会误拒正确方向; b1 与小圆角同公式, 方向由
;;         两端头的主体方向唯一确定)
;; 返回: (实际半径 T) 表示成功, nil 表示失败(无法圆角或两个方向圆心都侵入区域)
(defun dt:fillet-pair (h1 h2 center-lines off-dist layer r-start nochk /
                       obj1 et1 p1 d1 obj2 et2 p2 d2
                       ang2 b1 b2 done r d-tan len1 len2 c t1 t2 m a1 a2
                       tmp arc txt txt-pt ms ok)
  (if (null layer) (setq layer "FLB"))
  (if (null r-start) (setq r-start *dt-fillet-r*))
  (setq obj1 (car h1) et1 (cadr h1) p1 (caddr h1) d1 (cadddr h1)
        obj2 (car h2) et2 (cadr h2) p2 (caddr h2) d2 (cadddr h2))
  ;; 两切线方向夹角的一半
  (setq ang2 (/ (dt:angle-between d1 d2) 2.0))
  ;; 圆心候选方向: b1 = 角平分线(指向两线主体夹角, 圆心在断口外侧=区域外, A方案)
  ;;               b2 = 补角平分线(备用, 方向反了时换用)
  (setq b1 (dt:unit (mapcar '+ d1 d2)))
  (setq b2 (dt:unit (mapcar '- d1 d2)))
  ;; 半径递减尝试: r-start -> 1, 要求切点不超出线的当前长度 (v8.0: 全局参数, v8.2: 按图层拆分)
  (setq done nil r r-start)
  (while (and (not done) (> r 0))
    (setq len1 (vlax-curve-getdistatparam obj1 (vlax-curve-getendparam obj1))
          len2 (vlax-curve-getdistatparam obj2 (vlax-curve-getendparam obj2))
          d-tan (/ r (dt:tan ang2)))
    (if (and (<= d-tan len1) (<= d-tan len2))
      (setq done T)
      (setq r (1- r))))
  (if (not done)
    nil
    (progn
      ;; 先按 b1 方向算圆心(区域外), 若侵入则换 b2。
      ;; nochk=T(大圆角)时直接用 b1, 不做区域验证(见函数头说明)
      (setq c (dt:pt+vec p1 b1 (/ r (sin ang2))))
      (if nochk
        (setq ok T)
        (if (dt:in-zone c center-lines off-dist)
          (progn
            (setq c (dt:pt+vec p1 b2 (/ r (sin ang2))))
            (if (dt:in-zone c center-lines off-dist)
              (setq ok nil)
              (setq ok T)))
          (setq ok T)))
      (if (null ok)
        nil
        (progn
          ;; 切点(v7.16: 沿曲线走 d-tan, 保证在线上——圆弧线也精确连接)
          (setq t1 (dt:endpoint-in obj1 et1 d-tan)
                t2 (dt:endpoint-in obj2 et2 d-tan)
                ;; 弧中点(圆心朝断口方向偏移 r)
                m (dt:pt+vec c (dt:unit (mapcar '- p1 c)) r))
          ;; 修剪两条线的端头到切点
          (dt:set-endpoint obj1 et1 t1)
          (dt:set-endpoint obj2 et2 t2)
          ;; 创建圆角弧: 保证从 a1 逆时针到 a2 的弧为劣弧(弧长<=180°)
          ;; v7.15 修复: 原 arc-covers 判断对斜线大夹角断口(夹角>90°)失效,
          ;;   a1/a2 反向组合时画成 200°+ 优弧(DXF 实测 202°~216°),
          ;;   视觉上"圆心方向反了"。修复: 先保证劣弧(弧长>pi 则交换),
          ;;   几何正确的圆角弧必然经过弧中点 am(凸向断口内侧), 无需 arc-covers。
          (setq ms (dt:ms)
                a1 (angle (list (car c) (cadr c)) (list (car t1) (cadr t1)))
                a2 (angle (list (car c) (cadr c)) (list (car t2) (cadr t2))))
          (if (> (if (> a2 a1) (- a2 a1) (+ (- a2 a1) (* 2 pi))) pi)
            (setq tmp a1 a1 a2 a2 tmp))
          (setq arc (vla-addarc ms (vlax-3d-point c) r a1 a2))
          (vla-put-layer arc layer)
          ;; 实际半径小于起始半径 r-start 时, 在圆角旁标注文字(字高 10, v7.15 由 20 改)
          (if (< r r-start)
            (progn
              (setq txt-pt (dt:pt+vec m b1 14.0))
              (setq txt (vla-addtext ms (strcat "R" (rtos r 2 0))
                                     (vlax-3d-point txt-pt) 10.0))
              (vla-put-height txt 10.0)
              (vla-put-layer txt layer)))
          (list r T))))))

;; 收集 VLA 列表内所有线端头(可按 eName 列表排除, 如出线槽源线):
;; 返回 ((对象 端类型"S"/"E" 端头点 指向主体方向) ...)
;; v10.6: 先按 dt:curve-p 过滤(文字等非曲线实体的端点查询会抛错)
(defun dt:collect-heads (vla-list exclude / heads infos obj)
  (setq heads nil)
  (foreach obj vla-list
    (if (and (not (dt:excluded-p obj exclude))
             (dt:curve-p obj))
      (progn
        (setq infos (dt:end-infos obj))
        (setq heads (append heads
          (list (list obj "S" (caar infos) (cadar infos))
                (list obj "E" (caadr infos) (cadadr infos))))))))
  heads)

;; 端头两两配对: 端头重合(<1e-3, 即断口) + 不同对象 + 切线方向不平行
(defun dt:pair-heads (heads / pairs i j h1 h2)
  (setq pairs nil i 0)
  (foreach h1 heads
    (setq j 0)
    (foreach h2 heads
      (if (> j i)
        (if (and (<= (dt:dist (caddr h1) (caddr h2)) 1e-3)
                 (not (equal (car h1) (car h2)))
                 (dt:not-parallel (cadddr h1) (cadddr h2)))
          (setq pairs (cons (list h1 h2) pairs))))
      (setq j (1+ j)))
    (setq i (1+ i)))
  pairs)

;; 断口圆角入口: 自动找出指定图层(layer)上所有断口并逐个圆角
;; layer 默认 "FLB" (v7.7 起参数化, 假体流程传 "JT")
;; v8.2: 圆角半径按图层拆分 —— 假体图层用 *dt-fillet-r-hole*, 其余用 *dt-fillet-r*
(defun dt:fillet-all (off-dist layer / center-lines vla-list heads pairs pair res
                      count-ok count-fail count-r15 r-start)
  (if (null off-dist) (setq off-dist 35.0))
  (if (null layer) (setq layer "FLB"))
  ;; v8.2: 按图层选圆角起始半径(假体用假体半径, 其他用分流板半径)
  (setq r-start (if (= layer "JT") *dt-fillet-r-hole* *dt-fillet-r*))
  (setq center-lines (dt:curves-only (dt:layer-vlas "LD")))
  (if (null center-lines)
    (princ "\n【圆角】未找到\"LD\"图层, 无法验证圆角方向, 跳过圆角处理。")
    (progn
      (setq vla-list (dt:curves-only (dt:layer-vlas layer)))
      (if (null vla-list)
        (princ (strcat "\n【圆角】\"" layer "\"图层上没有对象, 无需圆角。"))
        (progn
          ;; 收集端头 + 两两配对(端头重合 & 不同对象 & 切线不平行)
          (setq heads (dt:collect-heads vla-list nil)
                pairs (dt:pair-heads heads))
          ;; 逐个圆角
          (princ (strcat "\n【圆角】发现 " (itoa (length pairs)) " 处断口, 开始圆角..."))
          (command "_.UNDO" "BE")
          (setq count-ok 0 count-fail 0 count-r15 0)
          (foreach pair pairs
            (setq res (dt:fillet-pair (car pair) (cadr pair) center-lines off-dist layer r-start nil))
            (if res
              (progn
                (setq count-ok (1+ count-ok))
                (if (< (car res) r-start) (setq count-r15 (1+ count-r15))))
              (setq count-fail (1+ count-fail))))
          (command "_.UNDO" "E")
          (princ (strcat "\n【圆角】完成: 成功 " (itoa count-ok) " 处"
                         (if (> count-r15 0)
                           (strcat " (其中 " (itoa count-r15) " 处半径小于起始值, 已标注文字)")
                           "")
                         ", 失败 " (itoa count-fail) " 处。"))
          (princ "\n【圆角】提示: 若想撤销本次圆角, 输入 UNDO 回车即可。")))))
  (princ))

;; ============================================================================
;; 四、通道封口 —— v5.0 (封口线放"FBX"图层)
;; ============================================================================

;; 判断端点 pt 是否为"悬空端头": ends 中没有其他端头与它重合(距离<1e-3)
;; 通道开放端是悬空端头; 交叉区断口端/圆角弧端都连着别的线, 非悬空
;; me = 当前端点记录, ends = 全部端点记录
(defun dt:end-free (pt me ends / e)
  (not (vl-some
         '(lambda (e)
            (and (not (equal e me))
                 (<= (distance pt (car e)) 1e-3)))
         ends)))

;; 从按距离升序排列的候选中挑"两个不同对象的端点"
;; cand = ((距离 . 端点记录) ...), 端点记录 = (坐标 对象 端类型)
;; 返回: (端点记录1 端点记录2) 或 nil(找不到第二个不同对象的)
(defun dt:pick-pair (cand / a b c)
  (setq a (cdr (nth 0 cand))   ; 最近的一个
        b nil)
  (foreach c (cdr cand)
    (if (and (null b) (not (equal (cadr (cdr c)) (cadr a))))
      (setq b (cdr c))))
  (if b (list a b) nil))

;; 在端点列表中找"这条流道中心线在端点 P 处的两个偏移线端头"
;; 匹配条件(v8.5 综合修复):
;;   1) **欧氏距离** ≈ off-dist, 容差 tol 由调用方传入
;;      (v8.2 及之前用欧氏距离, H 形图纸验证正常; v8.3 改法向距离导致
;;       交叉区/远处端头误配(封口5处+崩溃), v8.4 加法向+悬空仍偏(封口3处)
;;       —— 恢复欧氏距离, 兼容延长由 close-channels 动态放宽容差解决)
;;   2) 端头必须**悬空**(图层内没有其他线端头与它重合 < 1e-3):
;;      通道开放端悬空; 交叉区断口端/圆角弧端连着别的线, 排除
;;   3) 选出的两个端点必须**不同对象**(dt:pick-pair): 防止"同一根线的
;;      两端"被误配成封口对(那样封口线连自己, 下游螺丝孔全跳过)
;; p = 中心线端点, ends = ((端点坐标 对象 端类型) ...)
;; 返回: ((端点1 对象1 端类型1) (端点2 对象2 端类型2)) 或 nil
(defun dt:close-pair (p ends off-dist tol / cand a e)
  (setq cand nil)
  (foreach e ends
    (setq a (distance p (car e)))
    (if (and (> a (- off-dist tol)) (< a (+ off-dist tol))
             (dt:end-free (car e) e ends))
      (setq cand (cons (cons a e) cand))))
  (if (>= (length cand) 2)
    (progn
      (setq cand (vl-sort cand '(lambda (x y) (< (car x) (car y)))))
      (dt:pick-pair cand))
    nil))

;; 判断两个封口对是否相同(端点坐标逐一比较, 含反向顺序; v8.6 支持反向)
(defun dt:same-pair (p1 p2)
  (or (and (<= (distance (caar p1) (caar p2)) 1e-3)
           (<= (distance (caadr p1) (caadr p2)) 1e-3))
      (and (<= (distance (caar p1) (caadr p2)) 1e-3)
           (<= (distance (caadr p1) (caar p2)) 1e-3))))

;; 用封口线连接一对端点(创建直线, 放入指定封口线图层 close-layer)
(defun dt:make-close-line (pair close-layer / ms p1 p2 ln)
  (if (null close-layer) (setq close-layer "FBX"))
  (setq ms (dt:ms)
        p1 (caar pair)
        p2 (caadr pair))
  (setq ln (vla-addline ms (vlax-3d-point p1) (vlax-3d-point p2)))
  (vla-put-layer ln close-layer)
  ln)

;; 通道封口入口: 自动找出指定图层(plate-layer)上所有通道的开放端并封口
;; plate-layer = 偏移线图层(默认"FLB"), close-layer = 封口线图层(默认"FBX")
(defun dt:close-channels (off-dist plate-layer close-layer / center-lines
                          vla-list ends obj res count-ok done-pairs cl tol)
  (if (null off-dist) (setq off-dist 35.0))
  (if (null plate-layer) (setq plate-layer "FLB"))
  (if (null close-layer) (setq close-layer "FBX"))
  (setq center-lines (dt:curves-only (dt:layer-vlas "LD")))
  (if (null center-lines)
    (princ "\n【封口】未找到\"LD\"图层, 跳过封口处理。")
    (progn
      (setq vla-list (dt:layer-vlas plate-layer))
      (if (null vla-list)
        (princ (strcat "\n【封口】\"" plate-layer "\"图层上没有对象, 无需封口。"))
        (progn
          ;; 收集偏移线所有端点(v10.2b: 只收线/弧 —— 圆角"半径递减"标注等
          ;; 文字对象不支持 vlax-curve 端点, 会报"参数值错误"中断封口)
          (setq ends nil)
          (foreach obj vla-list
            (if (member (vla-get-objectname obj)
                        '("AcDbLine" "AcDbArc" "AcDbLWPolyline" "AcDbPolyline"))
              (progn
                (setq ends (cons (list (vlax-curve-getstartpoint obj) obj "S") ends)
                      ends (cons (list (vlax-curve-getendpoint obj) obj "E") ends)))))
          ;; 对每条流道线的两端找封口对并封口
          (princ (strcat "\n【封口】\"LD\"图层 " (itoa (length center-lines))
                         " 条中心线, 开始封闭通道端部..."))
          (command "_.UNDO" "BE")
          (setq count-ok 0 done-pairs nil)
          ;; v8.5: 容差按图层区分 —— 假体端头延长后欧氏距离变大, 叠加覆盖量
          ;; 0.6*延长量(分流板无延长, 保持 15% off-dist 不变)
          (setq tol (if (= plate-layer "JT")
                      (max 1.0 (* off-dist 0.15) (* 0.6 *dt-hole-extend*))
                      (max 1.0 (* off-dist 0.15))))
          (foreach cl center-lines
            ;; 起点端
            (setq res (dt:close-pair (vlax-curve-getstartpoint cl) ends off-dist tol))
            (if (and res (not (vl-some '(lambda (p) (dt:same-pair p res)) done-pairs)))
              (progn
                (dt:make-close-line res close-layer)
                (setq count-ok (1+ count-ok)
                      done-pairs (cons res done-pairs))))
            ;; 终点端
            (setq res (dt:close-pair (vlax-curve-getendpoint cl) ends off-dist tol))
            (if (and res (not (vl-some '(lambda (p) (dt:same-pair p res)) done-pairs)))
              (progn
                (dt:make-close-line res close-layer)
                (setq count-ok (1+ count-ok)
                      done-pairs (cons res done-pairs)))))
          (command "_.UNDO" "E")
          (princ (strcat "\n【封口】完成: 共封闭 " (itoa count-ok) " 处通道端部"
                         " (封口线已放入\"" close-layer "\"图层)。"))
          (princ "\n【封口】提示: 若想撤销本次封口, 输入 UNDO 回车即可。")))))
  (princ))

;; ============================================================================
;; 五、封口倒角 —— v6.0
;; ============================================================================

;; 收集指定图层所有线的端点信息: ((端点坐标 对象 端类型 指向主体方向) ...)
;; layer 默认 "FLB" (v7.7 起参数化, 假体流程传 "JT")
(defun dt:collect-plate-ends (layer / ends infos obj)
  (if (null layer) (setq layer "FLB"))
  (setq ends nil)
  (foreach obj (dt:layer-vlas layer)
    ;; v10.2b: 跳过文字等非曲线对象(标注文字不支持 vlax-curve 端点)
    (if (member (vla-get-objectname obj)
                '("AcDbLine" "AcDbArc" "AcDbLWPolyline" "AcDbPolyline"))
      (progn
        (setq infos (dt:end-infos obj))
        (setq ends (cons (list (caar infos) obj "S" (cadar infos)) ends)
              ends (cons (list (caadr infos) obj "E" (cadadr infos)) ends)))))
  ends)

;; 在端点列表中找距点 P 最近的端点记录(用于建立"封口线-偏移线"连接关系)
;; 注: 封口线经倒角(距离5)后端点与偏移线端头不再精确重合(相距约7),
;;     故用"最近端点"匹配, 并设距离上限避免误配远处的无关端点。
;; 返回: (端点坐标 对象 端类型 指向主体方向) 或 nil
(defun dt:find-touch (p ends / best best-d e d)
  (setq best nil best-d 1e30)
  (foreach e ends
    (setq d (distance p (car e)))
    (if (< d best-d)
      (setq best-d d best e)))
  ;; 距离上限 15(倒角5时端点距约7, 留足余量)
  (if (<= best-d 15.0) best nil))

;; 热咀+点孔圆(v9.2~v9.4): 每条封口线代表一个封闭的通道端头, 在"封口线
;; 中点沿通道向内偏移 *dt-nozzle-offset*(默认40)"处画半径 *dt-nozzle-r*
;; (默认11.35)的热咀圆(→"RZ"层) + 同心半径 *dt-pin-r*(默认3, 设0不画)
;; 的点孔圆(→"DK"层)。不依赖流道线定位: 封口线两端与两条分流板线端头
;; 精确重合(封口逻辑保证), 内向方向 = 封口线的垂向, 符号由"相连分流板线
;; 中点"相对封口线中点的位置点积判定(与 offset-inward 同一套思路)。
;; 必须在倒角之前调用(此时"FBX"图层上只有封口线, 倒角后混入斜线)。
(defun dt:nozzle-circles (plate-layer close-layer / vla-list plate-ends cl p1 p2
                          mid dir nrm touch pm v sgn center c count)
  (if (null plate-layer) (setq plate-layer "FLB"))
  (if (null close-layer) (setq close-layer "FBX"))
  (setq vla-list (dt:curves-only (dt:layer-vlas close-layer))
        plate-ends (dt:collect-plate-ends plate-layer)
        count 0)
  (if (null vla-list)
    (princ "\n【热咀】没有封口线, 跳过热咀圆。")
    (progn
      (command "_.UNDO" "BE")
      (foreach cl vla-list
        (setq p1 (vlax-curve-getstartpoint cl)
              p2 (vlax-curve-getendpoint cl)
              mid (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2)
              dir (dt:unit (mapcar '- p2 p1))
              nrm (list (- (cadr dir)) (car dir) 0.0)
              touch (dt:find-touch p1 plate-ends)
              sgn nil)
        ;; 内向符号: 相连分流板线的中点必然位于通道内侧
        (if touch
          (progn
            (setq pm (vlax-curve-getpointatparam
                       (cadr touch) (/ (vlax-curve-getendparam (cadr touch)) 2.0))
                  v (mapcar '- pm mid)
                  sgn (if (> (+ (* (car v) (car nrm))
                                (* (cadr v) (cadr nrm))
                                (* (caddr v) (caddr nrm)))
                             0.0)
                        1.0 -1.0))))
        (if (null sgn)
          (progn
            (princ "\n【热咀】警告: 封口线端头未找到相连分流板线, 该端头跳过热咀圆。"))
          (progn
            (setq center (dt:pt+vec mid nrm (* sgn *dt-nozzle-offset*)))
            (setq c (vla-addcircle (dt:ms) (vlax-3d-point center) *dt-nozzle-r*))
            (vla-put-layer c "RZ")
            (setq count (1+ count))
            ;; 点孔圆(v9.3/v9.4): 与热咀圆同心, 半径 *dt-pin-r*; 设 0 不画
            (if (> *dt-pin-r* 1e-9)
              (progn
                (setq c (vla-addcircle (dt:ms) (vlax-3d-point center) *dt-pin-r*))
                (vla-put-layer c "DK"))))))
      (command "_.UNDO" "E")
      (princ (strcat "\n【热咀】完成: 共 " (itoa count) " 处热咀圆+点孔圆(偏移 "
                     (rtos *dt-nozzle-offset* 2 2) ", 热咀半径 " (rtos *dt-nozzle-r* 2 2)
                     ", 点孔半径 " (rtos *dt-pin-r* 2 2)
                     ") → \"RZ\"(热咀) + \"DK\"(点孔)图层。"))))
  (princ))

;; 创建一条线段并放入"FBX"图层(用于倒角斜线)
(defun dt:add-close-line (p1 p2 / ms ln)
  (setq ms (dt:ms))
  (setq ln (vla-addline ms (vlax-3d-point p1) (vlax-3d-point p2)))
  (vla-put-layer ln "FBX")
  ln)

;; 在失败位置标注文字(字高 10, 可指定消息与图层, 默认"倒角失败"/"FBX")
;; v7.13: vla-addtext 高度参数会被"固定高度"文字样式忽略(文字极小不可见),
;;  创建后强制 vla-put-height; 文字位置改为"端头外侧 20"(更远离线, 不压线)
;; v7.14: 增加诊断输出, 命令行打印文字创建坐标, 便于定位文字位置
;; v7.15: 字高 20 -> 10(用户要求所有文字标注大小改为 10)
(defun dt:mark-fail (p d msg layer / ms txt tp)
  (if (null msg) (setq msg "倒角失败"))
  (if (null layer) (setq layer "FBX"))
  (setq ms (dt:ms)
        tp (dt:pt+vec p d -20.0))  ; 沿端头外侧延伸 20, 远离线避免压线
  (setq txt (vla-addtext ms msg (vlax-3d-point tp) 10.0))
  (vla-put-height txt 10.0)        ; 强制字高 10(防文字样式固定高度覆盖)
  (vla-put-layer txt layer)
  (princ (strcat "\n  " msg " @ ("
                 (rtos (car tp) 2 1) "," (rtos (cadr tp) 2 1) ")"))
  txt)

;; 对一条封口线做两端倒角
;; cl = 封口线(VLA对象), chd = 倒角距离, ends = 分流板线端点信息列表
;; 返回: (成功端数 失败端数)
;; v10.2c 修计数: 此前正常路径返回 (n1 n2)=两端各自成功数, 而入口
;; chamfer-close 把第二个数当失败数累加 → 每条封口线虚报 1 个失败
;; (4 条封口线恒报"失败 4 端", v6.0 起的陈年计数 bug, flb_3 实测定案:
;;  8 端几何全成功但报 4+4)。统一为 (成功数, 失败数)。
;; 另: find-touch 找不到相连墙线的分支此前静默(不标注不计数), 补标注。
(defun dt:chamfer-one (cl chd ends / p1 p2 dl1 dl2 cl-len r1 r2
                       ln1 e1 d1 ln2 e2 d2 n1 n2)
  (setq p1 (vlax-curve-getstartpoint cl)
        p2 (vlax-curve-getendpoint cl)
        dl1 (dt:unit (vlax-curve-getfirstderiv cl (vlax-curve-getstartparam cl)))
        dl2 (dt:unit (vlax-curve-getfirstderiv cl (vlax-curve-getendparam cl)))
        ;; 终点方向取反, 指向封口线主体
        dl2 (list (- (car dl2)) (- (cadr dl2)) (- (caddr dl2)))
        cl-len (vlax-curve-getdistatparam cl (vlax-curve-getendparam cl))
        r1 (dt:find-touch p1 ends)
        r2 (dt:find-touch p2 ends)
        n1 0 n2 0)
  ;; 封口线自身长度不足以两端各切 5 -> 两端都失败并标注
  (if (< cl-len (* 2 chd))
    (progn
      (dt:mark-fail p1 dl1 "倒角失败" "FBX")
      (dt:mark-fail p2 dl2 "倒角失败" "FBX")
      (list 0 2))
    (progn
      ;; ===== 起点端倒角 =====
      (cond
        ((null r1)
         (dt:mark-fail p1 dl1 "倒角失败" "FBX"))
        (T
         (setq ln1 (cadr r1) e1 (caddr r1) d1 (cadddr r1))
         (if (>= (vlax-curve-getdistatparam ln1 (vlax-curve-getendparam ln1)) chd)
           (progn
             ;; 封口线端点缩进 + 偏移线端头缩进 + 斜线连接
             (dt:set-endpoint cl "S" (dt:pt+vec p1 dl1 chd))
             (dt:set-endpoint ln1 e1 (dt:pt+vec p1 d1 chd))
             (dt:add-close-line (dt:pt+vec p1 dl1 chd) (dt:pt+vec p1 d1 chd))
             (setq n1 1))
           (dt:mark-fail p1 dl1 "倒角失败" "FBX"))))
      ;; ===== 终点端倒角 =====
      (cond
        ((null r2)
         (dt:mark-fail p2 dl2 "倒角失败" "FBX"))
        (T
         (setq ln2 (cadr r2) e2 (caddr r2) d2 (cadddr r2))
         (if (>= (vlax-curve-getdistatparam ln2 (vlax-curve-getendparam ln2)) chd)
           (progn
             (dt:set-endpoint cl "E" (dt:pt+vec p2 dl2 chd))
             (dt:set-endpoint ln2 e2 (dt:pt+vec p2 d2 chd))
             (dt:add-close-line (dt:pt+vec p2 dl2 chd) (dt:pt+vec p2 d2 chd))
             (setq n2 1))
           (dt:mark-fail p2 dl2 "倒角失败" "FBX"))))
      ;; 返回: (成功端数 失败端数)
      (list (+ n1 n2) (- 2 (+ n1 n2))))))

;; 封口倒角入口: 处理"FBX"图层上的所有封口线
(defun dt:chamfer-close (off-dist / chd vla-list ends obj
                         res count-ok count-fail)
  (if (null off-dist) (setq off-dist 35.0))
  (setq chd *dt-chamfer-d*)  ; 倒角距离(由全局参数控制, 对话框 PARAM 可改)
  (setq vla-list (dt:curves-only (dt:layer-vlas "FBX")))
  (if (null vla-list)
    (princ "\n【倒角】\"FBX\"图层上没有封口线, 无需倒角。")
    (progn
      (setq ends (dt:collect-plate-ends "FLB"))
      (princ (strcat "\n【倒角】\"FBX\"图层 " (itoa (length vla-list))
                     " 条封口线, 倒角距离 " (rtos chd 2 0) " ..."))
      (command "_.UNDO" "BE")
      (setq count-ok 0 count-fail 0)
      (foreach obj vla-list
        (setq res (dt:chamfer-one obj chd ends))
        (setq count-ok (+ count-ok (car res))
              count-fail (+ count-fail (cadr res))))
      (command "_.UNDO" "E")
      (princ (strcat "\n【倒角】完成: 成功 " (itoa count-ok) " 端, "
                     "失败 " (itoa count-fail) " 端(已文字标注)。"))
      (princ "\n【倒角】提示: 若想撤销本次倒角, 输入 UNDO 回车即可。")))
  (princ))

;; 判断点 p 是否距某条流道中心线的起点/终点约 hole-dist(容差15%)
;; 返回 T/nil —— 命中 = 该端头是"会被封口线连接的通道开放端"
(defun dt:near-center-end (p cl-ends hole-dist / tol best e d)
  (setq tol (max 1.0 (* hole-dist 0.15))
        best nil)
  (foreach e cl-ends
    (setq d (distance p e))
    (if (or (null best) (< d best)) (setq best d)))
  (and best (<= (abs (- best hole-dist)) tol)))

;; 将指定图层上"会被封口线连接的端头"沿其方向延长 dist (v7.10 新增, v7.17 精确化)
;; 用途: 假体封闭线需比分流板封闭线向外偏移15 —— 只有与"JTFBX"
;;       连接的假体线端头才延长(方案B), 使封闭线落在"分流板封闭线向外15"处。
;; v7.17 修复(用户反馈): 原实现把图层上"所有线两端"都延长15, 导致交叉处断段、
;;   圆角弧、中间段等不需要延长的线也被拉长。正确做法: 只有"端头距某条流道
;;   中心线端点约 hole-dist"的端头(即通道开放端, 封口线会连接的那些端头)
;;   才延长, 其余端头保持原样。判定复用 close-channels 的封口配对逻辑。
;; 直线/多段线直接改端点; 圆弧用角度延长(v7.11 新增支持):
;;   起点延长 = startangle 减小 dist/radius, 终点延长 = endangle 增大 dist/radius。
;; 返回: 处理的对象数
(defun dt:extend-ends (layer dist hole-dist / vla-list obj sp ep sd ed
                       obj-type c r cl-ends cl n)
  (if (null layer) (setq layer "JT"))
  (if (null dist) (setq dist 15.0))
  (if (null hole-dist) (setq hole-dist 50.0))
  ;; 收集"LD"中心线全部起/终点, 作为"开放通道端"参考
  ;; (v10.6: curves-only 过滤 —— LD 层混入文字/块时端点查询会抛错)
  (setq cl-ends nil)
  (foreach cl (dt:curves-only (dt:layer-vlas "LD"))
    (setq cl-ends (cons (vlax-curve-getstartpoint cl) cl-ends)
          cl-ends (cons (vlax-curve-getendpoint cl) cl-ends)))
  (if (null cl-ends)
    0
    (progn
      (setq vla-list (dt:curves-only (dt:layer-vlas layer)))
      (if (null vla-list)
        0
        (progn
          (setq n 0)
          (foreach obj vla-list
            (setq obj-type (vla-get-objectname obj))
            (cond
              ((member obj-type '("AcDbLine" "AcDbLWPolyline" "AcDbPolyline"))
               (setq sp (vlax-curve-getstartpoint obj)
                     ep (vlax-curve-getendpoint obj)
                     sd (dt:unit (vlax-curve-getfirstderiv obj (vlax-curve-getstartparam obj)))
                     ed (dt:unit (vlax-curve-getfirstderiv obj (vlax-curve-getendparam obj))))
               ;; 只延长"距某中心线端点≈hole-dist"的端头(会被封口线连接的开放端)
               (if (dt:near-center-end sp cl-ends hole-dist)
                 (dt:set-endpoint obj "S" (dt:pt+vec sp sd (- dist))))
               (if (dt:near-center-end ep cl-ends hole-dist)
                 (dt:set-endpoint obj "E" (dt:pt+vec ep ed dist)))
               (setq n (1+ n)))
              ((= obj-type "AcDbArc")
               (setq c (vlax-safearray->list (vlax-variant-value (vla-get-center obj)))
                     r (vla-get-radius obj))
               (if (> r 1e-9)
                 (progn
                   (if (dt:near-center-end (vlax-curve-getstartpoint obj) cl-ends hole-dist)
                     (vla-put-startangle obj (- (vla-get-startangle obj) (/ dist r))))
                   (if (dt:near-center-end (vlax-curve-getendpoint obj) cl-ends hole-dist)
                     (vla-put-endangle obj (+ (vla-get-endangle obj) (/ dist r))))
                   (setq n (1+ n)))
                 (princ (strcat "\n  延长跳过: AcDbArc 半径过小。"))))
              (T
               (princ (strcat "\n  延长跳过: " obj-type " 暂不支持两端延长。")))))
          n)))))

;; ============================================================================
;; 五b、假体封口圆角 —— v7.7 新增
;; 假体流程最后一步: 对"JTFBX"图层的封口线两端做圆角(半径15),
;; 失败则文字标注"圆角失败"(字高 20)。与分流板的"倒角(45°斜线)"不同,
;; 这里用圆弧(R15)连接封口线与假体线。
;; ============================================================================

;; 对一条封口线的两端做圆角
;; cl = 封口线(VLA对象), r = 圆角半径, ends = 假体线端点信息列表
;; v7.14: 所有失败分支(封口线过短/假体线过短/找不到连接线)都标注"圆角失败"
;;   并正确计数(v7.12 之前 r1/r2 nil 分支静默跳过、长度不足分支不计数,
;;   导致"失败 N 端(已文字标注)"与实际标注不符)。
;; 返回: (成功端数 失败端数)
(defun dt:fillet-close-one (cl r ends / p1 p2 dl1 dl2 cl-len r1 r2
                            ln1 e1 d1 ln2 e2 d2 n-ok n-fail c t1 t2 m ms a1 a2 am
                            tmp arc)
  (setq p1 (vlax-curve-getstartpoint cl)
        p2 (vlax-curve-getendpoint cl)
        dl1 (dt:unit (vlax-curve-getfirstderiv cl (vlax-curve-getstartparam cl)))
        dl2 (dt:unit (vlax-curve-getfirstderiv cl (vlax-curve-getendparam cl)))
        ;; 终点方向取反, 指向封口线主体
        dl2 (list (- (car dl2)) (- (cadr dl2)) (- (caddr dl2)))
        cl-len (vlax-curve-getdistatparam cl (vlax-curve-getendparam cl))
        r1 (dt:find-touch p1 ends)
        r2 (dt:find-touch p2 ends)
        n-ok 0 n-fail 0
        ms (dt:ms))
  ;; 封口线自身长度不足以两端各 r -> 两端都失败并标注
  (if (< cl-len (* 2 r))
    (progn
      (dt:mark-fail p1 dl1 "圆角失败" "JTFBX")
      (dt:mark-fail p2 dl2 "圆角失败" "JTFBX")
      (list 0 2))
    (progn
      ;; ===== 起点端圆角(内角, 与分流板同侧) =====
      (if r1
        (progn
          (setq ln1 (cadr r1) e1 (caddr r1) d1 (cadddr r1))
          (if (>= (vlax-curve-getdistatparam ln1 (vlax-curve-getendparam ln1)) r)
            (progn
              ;; 切点 T1(封口线) T2(假体线), 圆心 C = P + dl*R + d*R
              ;; v7.16: 切点沿曲线走 r, 保证在线上(假体线为圆弧时也精确连接)
              (setq t1 (dt:endpoint-in cl "S" r)
                    t2 (dt:endpoint-in ln1 e1 r)
                    c  (dt:pt+vec t1 d1 r)
                    m  (dt:pt+vec c (dt:unit (mapcar '+ (mapcar '- t1 c)
                                                         (mapcar '- t2 c))) r))
              (dt:set-endpoint cl "S" t1)
              (dt:set-endpoint ln1 e1 t2)
              ;; 短弧方向: 用弧中点验证, 保证弧凸向角内
              (setq a1 (angle (list (car c) (cadr c)) (list (car t1) (cadr t1)))
                    a2 (angle (list (car c) (cadr c)) (list (car t2) (cadr t2)))
                    am (angle (list (car c) (cadr c)) (list (car m) (cadr m))))
              (if (not (dt:arc-covers a1 a2 am))
                (setq tmp a1 a1 a2 a2 tmp))
              (setq arc (vla-addarc ms (vlax-3d-point c) r a1 a2))
              (vla-put-layer arc "JTFBX")
              (setq n-ok (1+ n-ok)))
            (progn
              (dt:mark-fail p1 dl1 "圆角失败" "JTFBX")
              (setq n-fail (1+ n-fail)))))
        (progn
          (dt:mark-fail p1 dl1 "圆角失败" "JTFBX")
          (setq n-fail (1+ n-fail))))
      ;; ===== 终点端圆角(内角) =====
      (if r2
        (progn
          (setq ln2 (cadr r2) e2 (caddr r2) d2 (cadddr r2))
          (if (>= (vlax-curve-getdistatparam ln2 (vlax-curve-getendparam ln2)) r)
            (progn
              (setq t1 (dt:endpoint-in cl "E" r)
                    t2 (dt:endpoint-in ln2 e2 r)
                    c  (dt:pt+vec t1 d2 r)
                    m  (dt:pt+vec c (dt:unit (mapcar '+ (mapcar '- t1 c)
                                                         (mapcar '- t2 c))) r))
              (dt:set-endpoint cl "E" t1)
              (dt:set-endpoint ln2 e2 t2)
              (setq a1 (angle (list (car c) (cadr c)) (list (car t1) (cadr t1)))
                    a2 (angle (list (car c) (cadr c)) (list (car t2) (cadr t2)))
                    am (angle (list (car c) (cadr c)) (list (car m) (cadr m))))
              (if (not (dt:arc-covers a1 a2 am))
                (setq tmp a1 a1 a2 a2 tmp))
              (setq arc (vla-addarc ms (vlax-3d-point c) r a1 a2))
              (vla-put-layer arc "JTFBX")
              (setq n-ok (1+ n-ok)))
            (progn
              (dt:mark-fail p2 dl2 "圆角失败" "JTFBX")
              (setq n-fail (1+ n-fail)))))
        (progn
          (dt:mark-fail p2 dl2 "圆角失败" "JTFBX")
          (setq n-fail (1+ n-fail))))
      (list n-ok n-fail))))

;; 假体封口圆角入口: 处理"JTFBX"图层上的所有封口线
(defun dt:fillet-close (off-dist / fd vla-list ends obj res
                         count-ok count-fail)
  (if (null off-dist) (setq off-dist 35.0))
  (setq fd *dt-fillet-r-hole*)  ; 假体封口圆角半径(v8.2: 拆分独立参数, 与分流板圆角分开)
  (setq vla-list (dt:curves-only (dt:layer-vlas "JTFBX")))
  (if (null vla-list)
    (princ "\n【假体圆角】\"JTFBX\"图层上没有封口线, 无需圆角。")
    (progn
      (setq ends (dt:collect-plate-ends "JT"))
      (princ (strcat "\n【假体圆角】\"JTFBX\"图层 " (itoa (length vla-list))
                     " 条封口线, 圆角半径 " (rtos fd 2 0) " ..."))
      (command "_.UNDO" "BE")
      (setq count-ok 0 count-fail 0)
      (foreach obj vla-list
        (setq res (dt:fillet-close-one obj fd ends))
        (setq count-ok (+ count-ok (car res))
              count-fail (+ count-fail (cadr res))))
      (command "_.UNDO" "E")
      (princ (strcat "\n【假体圆角】完成: 成功 " (itoa count-ok) " 端, "
                     "失败 " (itoa count-fail) " 端(已文字标注)。"))
      (princ "\n【假体圆角】提示: 若想撤销本次圆角, 输入 UNDO 回车即可。")))
  (princ))

;; ============================================================================
;; 五c、假体包络法 —— v10.2 重构(工字形事故定案)
;; 旧流程(LD 偏移 hole-dist + 带状裁剪 + LD端点封口)在通道间距 < 2×hole-dist
;; 的板上(工字形实测 70≤D<100): 相向 JT 线互相落入对方带区、平行无交点
;; 被整线删除, 而封口只认"LD 端点附近"的开口救不回来 → JT 碎裂不封闭。
;; 新规则(手画答案 flb_1.dxf 数值实锤, 与矩形模板假体同一概念):
;;   JT = FLB 包络盒向外扩 (hole-dist - offset-dist) 的圆角矩形,
;;   四角 R = 假体圆角R(fillet_r_hole)。手画版四边/角点逐点吻合
;;   (x=封口帽-15, y=FLB壁+15), 任意通道布局一步封闭, 零失败分支。
;;   内部通道(如工字形竖流道, 不达板边)由假体盘直接桥过 —— 假体=毛坯盘。
;; ============================================================================

;; 总控: 成功返回统计串; FLB 为空/外扩量过小返回 nil(调用方回退旧五步)。
(defun dt:jt-build (hole-dist offset-dist hole-layer / d objs bb
                    x0 y0 x1 y1 r ms no)
  (setq d (- hole-dist offset-dist))
  ;; v10.8: curves-only 过滤 —— FLB 层并入了封口倒角失败标注文字
  ;; (chamfer-close 标注 FBX → merge-layer 并入 FLB), 文字也有 boundingbox,
  ;; 混入会把 JT 假体包络盒沿标注方向撑大(与 jrt dt:jrt2-neck 取边同规)
  (setq objs (dt:curves-only (dt:layer-vlas "FLB")))
  (cond
    ((or (<= d 1.0) (null objs)) nil)
    (T
     (progn
       ;; FLB 包络盒(v10.2b: 改用 dt:rect-bbox —— v9.8a 验证过的双绑定
       ;; 兼容实现; 此前内联 vla-getboundingbox 漏传两个引用参数, 恒失败)
       (setq bb (dt:rect-bbox objs))
       (if (null bb)
         nil
         (progn
           (setq x0 (- (car bb) d) y0 (- (cadr bb) d)
                 x1 (+ (caddr bb) d) y1 (+ (cadddr bb) d)
                 r *dt-fillet-r-hole*
                 ;; 圆角上限与 dt:rect-jt 同款(0.45 x 短边): 原写法只限制到
                 ;; "边长-1", 细长包络盒上四角弧会互相重叠/反向
                 r (min r (* 0.45 (min (- x1 x0) (- y1 y0))))
                 r (max r 0.0)
                 ms (dt:ms))
           (command "_.UNDO" "BE")
           (if (< r 0.5)
             (progn
               ;; 直角矩形(外扩量过小或板太小时圆角让位)
               (dt:jt-line x0 y0 x1 y0 hole-layer)
               (dt:jt-line x1 y0 x1 y1 hole-layer)
               (dt:jt-line x1 y1 x0 y1 hole-layer)
               (dt:jt-line x0 y1 x0 y0 hole-layer))
             (progn
               ;; 四边
               (dt:jt-line (+ x0 r) y0 (- x1 r) y0 hole-layer)
               (dt:jt-line x1 (+ y0 r) x1 (- y1 r) hole-layer)
               (dt:jt-line (- x1 r) y1 (+ x0 r) y1 hole-layer)
               (dt:jt-line x0 (- y1 r) x0 (+ y0 r) hole-layer)
               ;; 四角弧(v10.2c: 象限修正 —— 每角弧从"接右边/下边"的 0°/270°
               ;; 扫到"接上边/左边"的 90°/180°, 此前整体错转 90° 弧不接边)
               (setq no (vla-addarc ms (vlax-3d-point (list (- x1 r) (+ y0 r) 0.0)) r (* 1.5 pi) (* 2.0 pi)))
               (vla-put-layer no hole-layer)
               (setq no (vla-addarc ms (vlax-3d-point (list (- x1 r) (- y1 r) 0.0)) r 0.0 (/ pi 2.0)))
               (vla-put-layer no hole-layer)
               (setq no (vla-addarc ms (vlax-3d-point (list (+ x0 r) (- y1 r) 0.0)) r (/ pi 2.0) pi))
               (vla-put-layer no hole-layer)
               (setq no (vla-addarc ms (vlax-3d-point (list (+ x0 r) (+ y0 r) 0.0)) r pi (* 1.5 pi)))
               (vla-put-layer no hole-layer)))
           (command "_.UNDO" "E")
           (strcat "包络 " (rtos (- x1 x0) 2 0) "x" (rtos (- y1 y0) 2 0)
                   ", 外扩 " (rtos d 2 0)
                   ", 圆角R" (rtos r 2 0))))))))

;; 画线放入指定图层
(defun dt:jt-line (x1 y1 x2 y2 layer / ln)
  (setq ln (vla-addline (dt:ms)
                        (vlax-3d-point (list x1 y1 0.0))
                        (vlax-3d-point (list x2 y2 0.0))))
  (vla-put-layer ln layer)
  ln)
;; 确保图层存在: 不存在则创建并设颜色; 已存在则不改属性(返回新建对象或 nil)。
;; v9.5: AutoCAD 图层名不区分大小写 —— 若已存在图层与请求写法大小写不一致
;;       (如已有小写 "dp"), 自动改名为请求写法("DP"), 图上对象全部跟随。
(defun dt:ensure-layer (layers name color cname / obj ent actual)
  (setq ent (tblsearch "LAYER" name))
  (if (null ent)
    (progn
      (setq obj (vla-add layers name))
      (vla-put-color obj color)
      (princ (strcat "\n已创建新图层 \"" name "\" (" cname ")。"))
      obj)
    (progn
      (setq actual (cdr (assoc 2 ent)))
      (if (not (equal actual name))
        (progn
          (vl-catch-all-apply 'vla-put-name (list (vla-item layers actual) name))
          (princ (strcat "\n图层 \"" actual "\" 已改名为 \"" name "\"。"))))
      (princ (strcat "\n图层 \"" name "\" 已存在, 直接使用(不修改其属性)。"))
      nil)))

;; 删除指定图层上的所有对象(保留图层定义), 用于 OFF 重跑时清除上一轮产物
;; 返回删除的对象数量
(defun dt:purge-layer (lname / s n i obj)
  (setq s (ssget "X" (list (cons 8 lname))))
  (if s
    (progn
      (setq n (sslength s) i 0)
      (repeat n
        (setq obj (vlax-ename->vla-object (ssname s i)))
        (vl-catch-all-apply 'vla-delete (list obj))
        (setq i (1+ i)))
      n)
    0))

;; 把 from 图层全部对象移入 to 图层, 并删除已空的 from 图层定义。
;; 用于流程收尾(v9.1): 倒角后"FBX"并入"FLB"、圆角后
;; "JTFBX"并入"JT" —— 封闭线不作为独立图层保留。
;; 图层删除失败(如仍被块参照使用)时静默跳过, 对象已全部移动。
(defun dt:merge-layer (from to / ss i n obj layers lay)
  (setq ss (ssget "X" (list (cons 8 from)))
        n 0)
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq obj (vlax-ename->vla-object (ssname ss i))
              i   (1+ i))
        (if (not (vl-catch-all-error-p
                   (vl-catch-all-apply 'vla-put-layer (list obj to))))
          (setq n (1+ n))))))
  (setq layers (vla-get-layers (vla-get-activedocument (vlax-get-acad-object)))
        lay (vl-catch-all-apply 'vla-item (list layers from)))
  (if (not (vl-catch-all-error-p lay))
    (vl-catch-all-apply 'vla-delete (list lay)))
  (princ (strcat "\n【并层】\"" from "\" 并入 \"" to "\": 移动 " (itoa n)
                 " 个对象, \"" from "\"图层已移除。"))
  (princ))

;; 只偏移指定图元(eName 列表), 用于出线槽: 只偏移源线, 避免重跑 OFF 时
;; 把"CX"(出线槽)图层里上一次残留的通道壁/圆角弧再偏移一遍(重跑污染)。v8.14
;; v9.1: 偏移循环唯一化 —— dt:offset-layer = 全选图层后调本函数
(defun dt:offset-enames (enames new-layer dist / i ent ent-obj obj-type
                         r1 r2 o1 o2 new-obj ok skip)
  (setq ok 0 skip 0 i 0)
  (foreach ent enames
    (if (and ent (/= ent ""))
      (progn
        (setq ent-obj (vlax-ename->vla-object ent)
              obj-type (vla-get-objectname ent-obj))
        ;; 仅处理支持偏移的对象类型(直线/多段线/圆弧/圆/椭圆/样条)
        (if (member obj-type
                    '("AcDbLine" "AcDbLWPolyline" "AcDbPolyline"
                      "AcDbArc" "AcDbCircle" "AcDbEllipse" "AcDbSpline"))
          (progn
            ;; 分别用正/负距离向两侧偏移: 正值偏一侧, 负值偏另一侧
            (setq r1 (vl-catch-all-apply 'vla-offset (list ent-obj dist)))
            (setq r2 (vl-catch-all-apply 'vla-offset (list ent-obj (- dist))))
            (if (and (not (vl-catch-all-error-p r1))
                     (not (vl-catch-all-error-p r2)))
              (progn
                ;; 偏移成功: 取出两条新对象, 放入目标图层
                (setq o1 (vlax-safearray->list (vlax-variant-value r1))
                      o2 (vlax-safearray->list (vlax-variant-value r2)))
                (foreach new-obj (append o1 o2)
                  (vla-put-layer new-obj new-layer))
                (setq ok (1+ ok)))
              ;; 偏移失败(如圆弧半径过小等): 跳过并提示
              (progn
                (setq skip (1+ skip))
                (princ (strcat "\n  对象 #" (itoa i) " (" obj-type ") 偏移失败, 已跳过。")))))
          ;; 不支持的实体类型(文字/块/标注等): 跳过并提示
          (progn
            (setq skip (1+ skip))
            (princ (strcat "\n  对象 #" (itoa i) " (" obj-type ") 不是可偏移类型, 已跳过。"))))))
    (setq i (1+ i)))
  (princ (strcat "\n偏移完成: 成功 " (itoa ok) " 个, 跳过 " (itoa skip) " 个。"))
  (list ok skip))

;; 将指定源图层(src-layer)上所有可偏移对象向两侧各偏移 dist, 放入目标图层
;; (v7.7 抽出, 供分流板偏移与假体偏移两处复用)
;; 返回: (成功数 跳过数)
(defun dt:offset-layer (src-layer new-layer dist / ss)
  (setq ss (ssget "X" (list (cons 8 src-layer))))
  (if (null ss)
    (progn
      (princ (strcat "\n图层 \"" src-layer "\" 上没有任何对象, 无需偏移。"))
      (list 0 0))
    (dt:offset-enames (dt:ss->list ss) new-layer dist)))

;; ============================================================================
;; 六、螺丝孔定位 —— v7.0
;; 每条封口线与它连接的两条分流板线各自向通道内部偏移 10, 偏移后的封口线
;; 与两条偏移分流板线交于 2 点; 每个交点处画 1 个圆(螺丝孔R, v9.6 单圆),
;; 放入"LS"图层; 画完圆后删除偏移辅助线。
;; ============================================================================

;; 向内部偏移: 只偏移一次(v7.6 采纳用户建议, 不再生成向外的候选线)
;; obj = 曲线, dist = 偏移距离, ref = 内部参照点(指向内部方向)
;; 返回新 VLA 对象或 nil
;; 原理: ref 位于通道内部(两条偏移线中点连线的中点), 从 obj 中点指向
;;   ref 的方向就是"内部方向"。
;;   1) 取 obj 中点切向 T, vla-offset 正距离同侧法向 nplus=(-T.y,T.x,0),
;;      用"中点->ref"向量与 nplus 的点积符号决定偏移符号, 只偏移一次;
;;   2) 验证: 偏移后新线中点应比原线中点更靠近 ref, 否则说明该对象的
;;      vla-offset 正负约定与直线不同(如圆弧 +dist 使半径增大=向外),
;;      删除后反向重试一次。
;; 只生成一条偏移线, 从根本上消除了"被放弃候选线泄漏"的可能。
(defun dt:offset-inward (obj dist ref / mp tv v nplus sgn r n d-old d-new)
  (setq mp (/ (vlax-curve-getendparam obj) 2.0))
  (setq tv (dt:unit (vlax-curve-getfirstderiv obj mp)))
  (setq v (mapcar '- ref (vlax-curve-getpointatparam obj mp)))
  (setq nplus (list (- (cadr tv)) (car tv) 0.0))
  (setq sgn (if (> (apply '+ (mapcar '* v nplus)) 0.0) dist (- dist)))
  (setq r (vl-catch-all-apply 'vla-offset (list obj sgn)))
  (if (not (vl-catch-all-error-p r))
    (progn
      (setq n (car (vlax-safearray->list (vlax-variant-value r))))
      (setq d-old (distance (vlax-curve-getpointatparam obj mp) ref)
            d-new (distance (vlax-curve-getpointatparam
                              n (/ (vlax-curve-getendparam n) 2.0)) ref))
      (if (< d-new d-old)
        n
        (progn
          ;; 方向判断有误(对象正负约定不同), 删除并反向重试一次
          (vl-catch-all-apply 'vla-delete (list n))
          (setq r (vl-catch-all-apply 'vla-offset (list obj (- sgn))))
          (if (not (vl-catch-all-error-p r))
            (car (vlax-safearray->list (vlax-variant-value r)))
            nil))))
    nil))

;; 在一个交点处画 1 个圆(半径 *dt-screw-r*, 默认 4.25), 放入"LS"图层
;; v9.6: 原 R4.25+R7 双同心圆合并为单圆(用户要求), 半径单参数可调
(defun dt:add-screw (pt / ms c1)
  (setq ms (dt:ms))
  (setq c1 (vla-addcircle ms (vlax-3d-point pt) *dt-screw-r*))
  (vla-put-layer c1 "LS")
  T)

;; 螺丝孔定位入口: 处理"FBX"图层上的每条封口线
(defun dt:drill-holes (off-dist / in-dist vla-list plate-ends
                       p1 p2 r1 r2 ln1 ln2 m1 m2 cl ref
                       ofc of1 of2 ip1 ip2 count-pt count-skip)
  (if (null off-dist) (setq off-dist 35.0))
  (setq in-dist *dt-screw-in*)  ; 向内部偏移距离(v8.0: 由全局参数控制)
  (setq vla-list (dt:curves-only (dt:layer-vlas "FBX")))
  (if (null vla-list)
    (princ "\n【螺丝】\"FBX\"图层上没有封口线, 无法定位螺丝孔。")
    (progn
      (setq plate-ends (dt:collect-plate-ends "FLB"))
      (princ (strcat "\n【螺丝】" (itoa (length vla-list)) " 条封口线, "
                     "向内部偏移 " (rtos in-dist 2 0) " 定位螺丝孔..."))
      (command "_.UNDO" "BE")
          (setq count-pt 0 count-skip 0)
          (foreach cl vla-list
            ;; 找封口线两端连接的偏移线(最近端点匹配)
            (setq p1 (vlax-curve-getstartpoint cl)
                  p2 (vlax-curve-getendpoint cl)
                  r1 (dt:find-touch p1 plate-ends)
                  r2 (dt:find-touch p2 plate-ends))
            (if (and r1 r2 (not (equal (cadr r1) (cadr r2))))
              (progn
                (setq ln1 (cadr r1)
                      ln2 (cadr r2)
                      ;; 统一内部参照 ref = 两条偏移线中点连线的中点。
                      ;; ln1/ln2 是同一条流道中心线的两条偏移线(对称±35),
                      ;; 它们中点连线的中点天然位于通道内部(中心线附近),
                      ;; 三条线的"内部"方向都指向通道内, 不会出错。
                      ;; (不用"最近中心线"猜内部方向: 交叉区附近的中点常离
                      ;;  别的交叉中心线更近, 会把内部方向判反)
                      m1 (vlax-curve-getpointatparam ln1 (/ (vlax-curve-getendparam ln1) 2.0))
                      m2 (vlax-curve-getpointatparam ln2 (/ (vlax-curve-getendparam ln2) 2.0))
                      ref (list (/ (+ (car m1) (car m2)) 2.0)
                                 (/ (+ (cadr m1) (cadr m2)) 2.0)
                                 (/ (+ (caddr m1) (caddr m2)) 2.0)))
                ;; 三条线各自向内部偏移(统一参照 ref)
                (setq ofc (dt:offset-inward cl in-dist ref)
                      of1 (dt:offset-inward ln1 in-dist ref)
                      of2 (dt:offset-inward ln2 in-dist ref))
                (if (and ofc of1 of2)
                  (progn
                    ;; 偏移封口线与两条偏移分流板线的交点
                    (setq ip1 (dt:inters-pts ofc of1)
                          ip2 (dt:inters-pts ofc of2))
                    (if (and ip1 ip2)
                      (progn
                        (dt:add-screw (car ip1))
                        (dt:add-screw (car ip2))
                        (setq count-pt (+ count-pt 2)))
                      (setq count-skip (1+ count-skip))))
                  (setq count-skip (1+ count-skip)))
                ;; 无条件删除全部偏移辅助线(关键修复 v7.4):
                ;; 原逻辑删除代码只在 (and ofc of1 of2) 全成功分支内,
                ;; 只要任一条偏移失败, 已生成的那几条就会残留在"FLB"
                ;; 图层(vla-offset 新对象继承原图层), 被后续圆角/倒角
                ;; 步骤当作普通分流板线处理, 造成"区域外的偏移线带倒角"。
                ;; 现改为: 对每个成功生成的偏移辅助线无条件删除, 并包异常。
                (if ofc (vl-catch-all-apply 'vla-delete (list ofc)))
                (if of1 (vl-catch-all-apply 'vla-delete (list of1)))
                (if of2 (vl-catch-all-apply 'vla-delete (list of2))))
              (setq count-skip (1+ count-skip))))
          (command "_.UNDO" "E")
          (princ (strcat "\n【螺丝】完成: 共 " (itoa count-pt)
                         " 处螺丝孔(每处 1 个圆), 跳过 " (itoa count-skip)
                         " 条封口线。已放入\"LS\"图层。"))
          (princ "\n【螺丝】提示: 若想撤销本次操作, 输入 UNDO 回车即可。")))
  (princ))

;; ============================================================================
;; 六b、参数对话框 —— v8.0 新增, v8.1 增强(自动生成 dcl, 不再依赖外部文件)
;; 可视化界面: 输入 PARAM 弹出参数设置对话框(只改参数不执行);
;;           OFF 命令执行前也会弹出(确定则执行, 取消则中止)。
;; 依赖文件: 优先用外部 flb_runner.dcl(可自行修改界面布局);
;;           找不到时由本文件内置的 DCL 源文本自动生成(v8.1), 保证界面可用。
;; ============================================================================

;; 内置 DCL 源文本(总是覆盖生成, 保证界面 100% 可用)
;; v9.9: 参数框 edit_box 按当前模板的参数键动态生成(两个一行; 通用
;; 11 项 6 行 / 矩形 8 项 4 行), 顶部文本显示当前模板名
(defun dt:dcl-lines ( / keys lines row k1 k2)
  (setq keys (dt:flb-tpl-keys) lines nil)
  (while keys
    (setq k1 (car keys)
          k2 (cadr keys)
          row (list "    : row {"
                    (strcat "      : edit_box { key = \"" k1
                            "\"; label = \"" (cdr (assoc k1 dt:flb-param-labels))
                            "\"; edit_width = 10; }")))
    (if k2
      (setq row (append row
        (list (strcat "      : edit_box { key = \"" k2
                      "\"; label = \"" (cdr (assoc k2 dt:flb-param-labels))
                      "\"; edit_width = 10; }")))
            keys (cddr keys))
      (setq keys nil))
    (setq lines (append lines row (list "    }"))))
  (append
    (list
      "dt_param : dialog {"
      "  label = \"分流板参数设置\";"
      "  : text { key = \"tpl_name\"; label = \"当前模板\"; width = 40; }"
      "  : boxed_column {"
      "    label = \"分流板参数\";")
    lines
    (list
      "  }"
      "  : toggle { key = \"jt_envelope\"; label = \"假体用包络法(FLB外扩整体圆角矩形)\"; }"
      "  : row {"
      "    : button { key = \"reset\"; label = \"恢复默认\"; width = 10; }"
      "    spacer;"
      "    ok_button;"
      "    cancel_button;"
      "  }"
      "}")))

;; 把内置 DCL 源文本写入文件 path(返回 path; 失败返回 nil)
;; v9.8: 同时写入模板选择框(参数框 + 模板选择框两个对话框)
(defun dt:write-dcl (path / f ln)
  (setq f (open path "w"))
  (if f
    (progn
      ;; v10.6: 写中途异常也保证 close(半截 dcl 由对话框链的 catch 提示)
      (vl-catch-all-apply
        '(lambda ( )
           (foreach ln (append (dt:dcl-lines) (list "") (dt:flb-template-dcl-lines))
             (write-line ln f)))
        nil)
      (close f)
      path)
    nil))

;; 查找对话框文件路径: **确定性目录**——优先 dt_start 引导器注入的
;; *dt-script-dir*(vl-propagate 全文档可见), 无 dt_start 时写系统 TEMP。
;; v2.0 重写: 删除 9 层 findfile 候选链——多副本环境下 findfile 会命中
;; 支持路径里其它目录的同名旧副本, 是 dcl 定位错乱的根源。
;; 总是用内置源覆盖生成最新 dcl(界面参数永远与脚本同步)。
(defun dt:find-dcl ( / )
  (if (and *dt-script-dir* (/= *dt-script-dir* ""))
    (dt:write-dcl (strcat *dt-script-dir* "\\flb_runner.dcl"))
    (dt:write-dcl (strcat (getenv "TEMP") "\\flb_runner_tmp.dcl"))))

;; 读取编辑框数值: 空/非法输入时返回默认值 def
;; v10.2d: 原用 atof —— 它对垃圾串静默返回 0(如 "abc" -> 0.0), 参数会被
;;   悄悄改成 0(偏移距离=0 会画出退化几何)。改用 distof: 非法输入返回
;;   nil 可识别, 回退默认值(坑 #54)。0 是合法值, 靠"0 非 nil"区分。
(defun dt:get-num (key def / s v)
  (setq s (get_tile key)
        v (if (and s (/= s "")) (distof s) nil))
  (if v v def))

;; 恢复默认参数到对话框(恢复默认按钮回调; 只刷当前模板的键 —— 控件按
;; 模板动态生成, 键不存在 set_tile 会报错);
;; v10.1 = 恢复 ini 配置默认值(先重读配置, 改 ini 后点恢复默认立即生效)
(defun dt:param-reset ( / val p)
  (setq *dt-flb-cfg* (dt:flb-cfg-read (strcat (dt:flb-cfg-dir) "\\flb_runner.ini")))
  (foreach p dt:param-table
    (if (member (car p) (dt:flb-tpl-keys))
      (progn
        (setq val (dt:flb-param-default (car p)))
        (set_tile (car p) (rtos val 2 2)))))
  ;; v10.5: 勾选框同步恢复 ini 默认(注意 0 是合法值, 0 非 nil, 不能直接 if 值判)
  (setq val (dt:flb-cfg-get *dt-flb-cfg* "假体" "envelope"))
  (set_tile "jt_envelope" (if (and val (/= val 0.0)) "1" "0")))

;; 应用对话框值到全局参数(确定按钮回调; 只读当前模板的键, 其余参数
;; 保持不变; 空/非法输入回退当前值);
;; v10.1: 应用后自动保存记忆(取消不触发本回调, 天然"确定才记忆")
(defun dt:param-apply ( / p v)
  (foreach p dt:param-table
    (if (member (car p) (dt:flb-tpl-keys))
      (progn
        (setq v (dt:get-num (car p) (eval (cadr p))))
        ;; v10.6: 负值校验 —— 距离/半径类参数 <0 回退当前值(负值会画出退化几何)
        (if (< v 0.0) (setq v (eval (cadr p))))
        (set (cadr p) v))))
  (dt:flb-mem-save))

;; 弹出参数对话框
;; 返回: T=用户点"确定"(参数已应用到全局变量), nil=取消/加载失败
(defun dt:param-dialog ( / dcl-file dcl-id result p)
  (setq *dt-flb-cfg* (dt:flb-cfg-read (strcat (dt:flb-cfg-dir) "\\flb_runner.ini")))
  (setq dcl-file (dt:find-dcl))
  (if (null dcl-file)
    (progn
      (princ "\n【界面】无法生成对话框文件(磁盘权限不足?), 界面不可用。")
      nil)
    (progn
      ;; v10.6: load_dialog 对损坏 dcl 是抛错而非返回 nil, 包 catch;
      ;;   start_dialog 同理 —— 保证 unload_dialog 必被执行
      (setq dcl-id (vl-catch-all-apply 'load_dialog (list dcl-file)))
      (if (or (vl-catch-all-error-p dcl-id) (null dcl-id))
        (progn
          (princ "\n【界面】对话框文件加载失败。")
          nil)
        (progn
          (if (new_dialog "dt_param" dcl-id)
            (progn
              (set_tile "tpl_name"
                        (strcat "当前模板: " (nth 0 (dt:flb-template-row))))
              ;; 预填当前模板的参数值(键不存在 set_tile 会报错)
              (foreach p dt:param-table
                (if (member (car p) (dt:flb-tpl-keys))
                  (set_tile (car p) (rtos (eval (cadr p)) 2 2))))
              ;; v10.5: 包络法勾选框预填
              (set_tile "jt_envelope" (if *dt-jt-envelope* "1" "0"))
              ;; 控件回调
              (action_tile "reset" "(dt:param-reset)")
              (action_tile "jt_envelope"
                           "(setq *dt-jt-envelope* (= (get_tile \"jt_envelope\") \"1\"))")
              (action_tile "accept" "(dt:param-apply)(done_dialog 1)")
              (action_tile "cancel" "(done_dialog 0)")
              (setq result (vl-catch-all-apply 'start_dialog nil))
              (unload_dialog dcl-id)
              (if (and (not (vl-catch-all-error-p result)) (= result 1)) T nil))
            (progn
              (unload_dialog dcl-id)
              (princ "\n【界面】对话框初始化失败。")
              nil)))))))

;; 命令 PARAM: 弹出参数设置对话框(只修改参数, 不执行偏移);
;; 汇总按当前模板的参数键输出(v9.9 动态)

;; 兼容旧命令别名
(defun c:PARAM ( ) (c:FLBPARAM))
(defun c:FLBPARAM ( / p txt)
  (if (dt:param-dialog)
    (progn
      (setq txt (strcat "\n参数已保存(模板: " (nth 0 (dt:flb-template-row)) "):"))
      (foreach p (dt:flb-tpl-keys)
        (setq txt (strcat txt " " (cdr (assoc p dt:flb-param-labels)) " "
                          (rtos (eval (cadr (assoc p dt:param-table))) 2 2))))
      (princ (strcat txt "。")))
    (princ "\n已取消, 参数未修改。"))
  (princ))

;; ============================================================================
;; 六c、多模板框架 + 矩形分流板模板 (v9.8, 框架模式同 jrt_runner v9.8)
;; dt:flb-template-table 每行: (名称 说明 参数默认表 覆盖表);
;; 覆盖表含 (process . 函数) 时整个主流程由该函数自管(建层/清理/绘制/统计),
;; 不走内置偏移流程; 覆盖表 nil = 全部用内置流程(通用模板)。
;; 新增模板 = 表中加一行(必要时新增覆盖 defun)。函数/全局名全部带 off/rect
;; 前缀, 与 slot/jrt 同加载互不覆盖(坑 #46)。
;; ============================================================================

;; 参数默认表列出该模板用到的参数键(参数框按模板动态显示, v9.9 同 jrt);
;; 未列出的键在选择模板时重置为 dt:param-table 默认值。
(setq dt:flb-template-table
      (list
        (list "通用"
              "现状全流程: 偏移+裁剪+断口圆角+封口+螺丝+倒角+假体+热咀"
              '(("offset_dist" . 35.0) ("hole_dist" . 50.0)
                ("hole_extend" . 15.0) ("fillet_r" . 15.0)
                ("fillet_r_hole" . 15.0) ("chamfer_d" . 5.0)
                ("screw_in" . 10.0) ("screw_r" . 4.25)
                ("nozzle_offset" . 40.0) ("nozzle_r" . 11.35)
                ("pin_r" . 3.0) ("zjj_r" . 14.35))
              nil)
        (list "矩形"
              "LD范围向外扩矩形板边(四角倒角)+圆角矩形假体; 热咀拐点/预画RZ, 螺丝板边中点/预画LS"
              '(("offset_dist" . 35.0) ("hole_dist" . 50.0)
                ("fillet_r_hole" . 15.0) ("screw_in" . 15.0)
                ("screw_r" . 4.25) ("nozzle_r" . 11.35)
                ("pin_r" . 3.0) ("rect_chamfer" . 10.0)
                ("zjj_r" . 14.35))
              '((process . dt:rect-process)))))
(setq *dt-flb-template* 0)  ; 当前选中模板下标(选择框确定后更新)
(setq *dt-flb-tpl-pick* 0)  ; 选择框单选过程中的临时下标(回调写入)

;; 参数键 → 中文标签(动态参数框 edit_box 标签与命令行汇总共用, v9.9)
(setq dt:flb-param-labels
      '(("offset_dist"   . "分流板偏移距离:")
        ("hole_dist"     . "假体偏移距离:")
        ("hole_extend"   . "假体端头延长:")
        ("fillet_r"      . "分流板圆角R:")
        ("fillet_r_hole" . "假体圆角R:")
        ("chamfer_d"     . "封口倒角距离:")
        ("screw_in"      . "螺丝孔内偏:")
        ("screw_r"       . "螺丝孔R:")
        ("nozzle_offset" . "热咀偏移:")
        ("nozzle_r"      . "热咀半径R:")
        ("pin_r"         . "点孔半径R:")
        ("rect_chamfer"  . "板角倒角:")
        ("zjj_r"         . "主进胶R:")))

;; 当前模板用到的参数键列表(= 模板参数默认表的键序; v9.9 参数框动态化)
(defun dt:flb-tpl-keys ( / )
  (mapcar 'car (nth 2 (dt:flb-template-row))))

;; 当前模板行
(defun dt:flb-template-row ( / row)
  (setq row (nth *dt-flb-template* dt:flb-template-table))
  (if row row (nth 0 dt:flb-template-table)))

;; 采用指定模板: 设当前下标并把参数写入全局;
;; v10.1 值来源优先级: 该模板记忆值 → ini 配置节 → 模板内置默认表 → 表 caddr
;; quiet=T 静默(加载时恢复用), nil 打印(模板框切换用)
(defun dt:flb-apply-template (idx quiet / tpl params p v)
  (setq *dt-flb-template* idx
        tpl (nth idx dt:flb-template-table)
        params (nth 2 tpl))
  (foreach p dt:param-table
    (setq v (cond ((cdr (assoc (car p) (dt:flb-cfg-sec *dt-flb-mem* (car tpl)))))
                  ((dt:flb-cfg-get *dt-flb-cfg* (car tpl) (car p)))
                  ((cdr (assoc (car p) params)))
                  (T (caddr p))))
    (set (cadr p) v))
  (if (null quiet)
    (princ (strcat "\n【模板】已选择 \"" (nth 0 tpl) "\": " (nth 1 tpl) "。")))
  (princ))

;; 模板选择框 DCL 源文本(由注册表动态生成 radio_button 列表)
(defun dt:flb-template-dcl-lines ( / lines i tpl)
  (setq lines (list "flb_template_select : dialog {"
                    "  label = \"选择分流板模板\";"
                    "  : boxed_radio_column {"
                    "    label = \"模板\";")
        i 0)
  (foreach tpl dt:flb-template-table
    (setq lines (append lines
      (list (strcat "    : radio_button { key = \"otpl" (itoa i)
                    "\"; label = \"" (nth 0 tpl) " — " (nth 1 tpl) "\"; }")))
          i (1+ i)))
  (append lines
    (list "  }"
          "  : row {"
          "    spacer; ok_button; cancel_button;"
          "  }"
          "}")))

;; 独立模板选择框: 单选模板 → 确定=采用该模板, 取消=nil(中止流程)
;; v10.1: 打开前重读 ini 配置(改配置后切模板立即用新默认)
(defun dt:flb-template-dialog ( / dcl-file dcl-id result idx tpl)
  (setq *dt-flb-cfg* (dt:flb-cfg-read (strcat (dt:flb-cfg-dir) "\\flb_runner.ini")))
  (setq dcl-file (dt:find-dcl))
  (if (null dcl-file)
    (progn
      (princ "\n【模板】无法生成对话框文件(磁盘权限不足?), 界面不可用。")
      nil)
    (progn
      ;; v10.6: load_dialog 对损坏 dcl 是抛错而非返回 nil, 包 catch
      (setq dcl-id (vl-catch-all-apply 'load_dialog (list dcl-file)))
      (if (or (vl-catch-all-error-p dcl-id) (null dcl-id))
        (progn
          (princ "\n【模板】对话框文件加载失败。")
          nil)
        (progn
          (if (new_dialog "flb_template_select" dcl-id)
            (progn
              ;; 预选当前模板; 单选回调记录到 *dt-flb-tpl-pick*
              (setq *dt-flb-tpl-pick* *dt-flb-template*)
              (set_tile (strcat "otpl" (itoa *dt-flb-template*)) "1")
              (setq idx 0)
              (foreach tpl dt:flb-template-table
                (action_tile (strcat "otpl" (itoa idx))
                             (strcat "(setq *dt-flb-tpl-pick* " (itoa idx) ")"))
                (setq idx (1+ idx)))
              (action_tile "accept" "(done_dialog 1)")
              (action_tile "cancel" "(done_dialog 0)")
              (setq result (vl-catch-all-apply 'start_dialog nil))
              (unload_dialog dcl-id)
              (if (and (not (vl-catch-all-error-p result)) (= result 1))
                (progn (dt:flb-apply-template *dt-flb-tpl-pick* nil) T)
                nil))
            (progn
              (unload_dialog dcl-id)
              (princ "\n【模板】对话框初始化失败。")
              nil)))))))

;; ---------------------------------------------------------------------------
;; 矩形模板辅助函数 (全部带 dt:rect- 前缀, 新增不与 slot/jrt 冲突)
;; ---------------------------------------------------------------------------

;; 画线/画圆并放到指定图层
(defun dt:rect-addline (p1 p2 layer / ln)
  (setq ln (vla-addline (dt:ms) (vlax-3d-point p1) (vlax-3d-point p2)))
  (vla-put-layer ln layer)
  ln)

(defun dt:rect-addcircle (c r layer / o)
  (setq o (vla-addcircle (dt:ms) (vlax-3d-point c) r))
  (vla-put-layer o layer)
  o)

;; 收集图层上全部整圆的 ((圆心X 圆心Y 半径)...) 快照(仅 AcDbCircle, 弧不算)
;; —— 矩形模板清理前留存预画的 RZ/LS 圆, 清理后原样重画(手画优先)
(defun dt:rect-snap-circles (layer / out objs o c)
  (setq out nil objs (dt:layer-vlas layer))
  (foreach o objs
    (if (= (vla-get-ObjectName o) "AcDbCircle")
      (progn
        (setq c (vlax-safearray->list (vlax-variant-value (vla-get-center o))))
        (setq out (cons (list (car c) (cadr c) (vla-get-radius o)) out)))))
  (reverse out))

;; 把圆快照原样重画到图层
(defun dt:rect-restore-circles (snap layer / s)
  (foreach s snap
    (dt:rect-addcircle (list (car s) (cadr s) 0.0) (caddr s) layer)))

;; 检测 DP 图层上的圆并在其圆心创建主进胶圆 (R=*dt-zjj-r*, 默认 14.35, 图层 ZJJ, 颜色 210 紫色)
(defun dt:flb-process-zjj ( / doc layers ss i e obj cen c-obj zjj-count)
  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        layers (vla-get-layers doc)
        zjj-count 0)
  (dt:ensure-layer layers "ZJJ" 210 "紫色")
  (setq ss (ssget "X" '((8 . "DP") (0 . "CIRCLE"))))
  (if ss
    (progn
      (command "_.UNDO" "BE")
      ;; 清理旧 ZJJ 产物，避免重复重叠生成
      (dt:purge-layer "ZJJ")
      (repeat (setq i (sslength ss))
        (setq e (ssname ss (setq i (1- i)))
              obj (vlax-ename->vla-object e))
        (setq cen (vlax-safearray->list (vlax-variant-value (vla-get-center obj))))
        (setq c-obj (dt:rect-addcircle (list (car cen) (cadr cen) 0.0) *dt-zjj-r* "ZJJ"))
        (setq zjj-count (1+ zjj-count)))
      (command "_.UNDO" "E")
      (if (> zjj-count 0)
        (princ (strcat "\n【主进胶】检测到 DP 垫片圆 " (itoa zjj-count)
                       " 个，已在圆心创建主进胶圆(R" (rtos *dt-zjj-r* 2 2) "，图层 ZJJ)。")))))
  zjj-count)

;; boundingbox 输出解包: vla-getboundingbox 的输出参数有的版本绑定为
;; safearray 本体, 有的为 variant(内含 safearray) —— 统一容忍两种
;; (v9.8a 修复: variantp 类型错误)
(defun dt:rect-bb-pts (x)
  (if (= (type x) 'variant)
    (vlax-safearray->list (vlax-variant-value x))
    (vlax-safearray->list x)))

;; 对象列表整体范围: 返回 (minx miny maxx maxy), 全部失败返回 nil
(defun dt:rect-bbox (objs / o mn mx p minx miny maxx maxy)
  (foreach o objs
    (setq mn nil mx nil)
    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx))))
      (progn
        (setq p (dt:rect-bb-pts mn))
        (setq minx (if minx (min minx (car p)) (car p))
              miny (if miny (min miny (cadr p)) (cadr p)))
        (setq p (dt:rect-bb-pts mx))
        (setq maxx (if maxx (max maxx (car p)) (car p))
              maxy (if maxy (max maxy (cadr p)) (cadr p))))))
  (if (and minx miny maxx maxy) (list minx miny maxx maxy) nil))

;; 矩形板边: LD 范围外扩 plate-dist, 四角 45° 倒角(超出可倒范围自动取限值
;; 0.45x短边; 倒角 0 = 直角矩形)。画到 "FLB" 图层。返回实际倒角值。
(defun dt:rect-plate (bb plate-dist chamfer / x0 y0 x1 y1 c)
  (setq x0 (- (car bb) plate-dist)
        y0 (- (cadr bb) plate-dist)
        x1 (+ (caddr bb) plate-dist)
        y1 (+ (cadddr bb) plate-dist)
        c (max 0.0 (min chamfer (* 0.45 (min (- x1 x0) (- y1 y0))))))
  (if (> c 0.0)
    (progn
      (dt:rect-addline (list (+ x0 c) y1 0.0) (list (- x1 c) y1 0.0) "FLB")
      (dt:rect-addline (list (+ x0 c) y0 0.0) (list (- x1 c) y0 0.0) "FLB")
      (dt:rect-addline (list x0 (+ y0 c) 0.0) (list x0 (- y1 c) 0.0) "FLB")
      (dt:rect-addline (list x1 (+ y0 c) 0.0) (list x1 (- y1 c) 0.0) "FLB")
      (dt:rect-addline (list x0 (- y1 c) 0.0) (list (+ x0 c) y1 0.0) "FLB")
      (dt:rect-addline (list (- x1 c) y1 0.0) (list x1 (- y1 c) 0.0) "FLB")
      (dt:rect-addline (list x1 (+ y0 c) 0.0) (list (- x1 c) y0 0.0) "FLB")
      (dt:rect-addline (list (+ x0 c) y0 0.0) (list x0 (+ y0 c) 0.0) "FLB"))
    (progn
      (dt:rect-addline (list x0 y0 0.0) (list x1 y0 0.0) "FLB")
      (dt:rect-addline (list x1 y0 0.0) (list x1 y1 0.0) "FLB")
      (dt:rect-addline (list x1 y1 0.0) (list x0 y1 0.0) "FLB")
      (dt:rect-addline (list x0 y1 0.0) (list x0 y0 0.0) "FLB")))
  c)

;; 圆角矩形假体: LD 范围外扩 hole-dist, 四角圆角 r(超出可倒范围自动取限值
;; 0.45x短边; r=0 直角)。画到 "JT" 图层。返回实际圆角值。
(defun dt:rect-jt (bb hole-dist r / x0 y0 x1 y1 rr a)
  (setq x0 (- (car bb) hole-dist)
        y0 (- (cadr bb) hole-dist)
        x1 (+ (caddr bb) hole-dist)
        y1 (+ (cadddr bb) hole-dist)
        rr (max 0.0 (min r (* 0.45 (min (- x1 x0) (- y1 y0))))))
  (if (> rr 0.0)
    (progn
      (dt:rect-addline (list (+ x0 rr) y0 0.0) (list (- x1 rr) y0 0.0) "JT")
      (dt:rect-addline (list x1 (+ y0 rr) 0.0) (list x1 (- y1 rr) 0.0) "JT")
      (dt:rect-addline (list (- x1 rr) y1 0.0) (list (+ x0 rr) y1 0.0) "JT")
      (dt:rect-addline (list x0 (- y1 rr) 0.0) (list x0 (+ y0 rr) 0.0) "JT")
      (foreach a (list (list (+ x0 rr) (+ y0 rr) pi (* 1.5 pi))          ; 左下
                       (list (- x1 rr) (+ y0 rr) (* 1.5 pi) (* 2.0 pi))  ; 右下
                       (list (- x1 rr) (- y1 rr) 0.0 (* 0.5 pi))         ; 右上
                       (list (+ x0 rr) (- y1 rr) (* 0.5 pi) pi))         ; 左上
        (vla-put-layer (vla-addarc (dt:ms)
                                   (vlax-3d-point (list (car a) (cadr a) 0.0))
                                   rr (caddr a) (cadddr a))
                       "JT")))
    (progn
      (dt:rect-addline (list x0 y0 0.0) (list x1 y0 0.0) "JT")
      (dt:rect-addline (list x1 y0 0.0) (list x1 y1 0.0) "JT")
      (dt:rect-addline (list x1 y1 0.0) (list x0 y1 0.0) "JT")
      (dt:rect-addline (list x0 y1 0.0) (list x0 y0 0.0) "JT")))
  rr)

;; 流道拐点: 不同 LD 对象端点重合(容差 0.5)处(直线/弧端点、多段线端点);
;; 单条闭合多段线自身无端点重合 → 画成闭环 LD 请拆成多段线或手画 RZ。
;; 返回去重后的 (x y 0.0) 点列表。
(defun dt:rect-corners (objs / pairs o typ p pr q pts out)
  (setq pairs nil)
  (foreach o objs
    (setq typ (vla-get-ObjectName o))
    (cond
      ((or (= typ "AcDbLine") (= typ "AcDbArc"))
       (foreach p (list (vlax-safearray->list
                          (vlax-variant-value (vla-get-startpoint o)))
                        (vlax-safearray->list
                          (vlax-variant-value (vla-get-endpoint o))))
         (setq pairs (cons (list p (vla-get-Handle o)) pairs))))
      ((= typ "AcDbLWPolyline")
       (foreach p (dt:poly-pts o)
         (setq pairs (cons (list p (vla-get-Handle o)) pairs))))))
  (setq out nil)
  (foreach pr pairs
    (setq p (car pr) pts nil)
    (foreach q pairs
      (if (and (< (dt:dist p (car q)) 0.5)
               (not (member (cadr q) pts)))
        (setq pts (cons (cadr q) pts))))
    (if (and (>= (length pts) 2)
             (not (vl-some (function (lambda (c) (< (dt:dist p c) 0.5))) out)))
      (setq out (cons p out))))
  (mapcar (function (lambda (p) (list (car p) (cadr p) 0.0))) out))

;; ---------------------------------------------------------------------------
;; 矩形模板主流程 (v9.8, process 覆盖: 建层/清理/绘制/统计全自管)
;; 流程: 1) 建 13 层(同通用模板第 1 步)  2) LD 整体范围
;;       3) 快照预画 RZ/LS(手画优先) → 清理旧产物
;;       4) 板边 = LD 外扩 分流板偏移距离(默认35) 矩形, 四角倒角 板角倒角(默认10)
;;       5) 假体 = LD 外扩 假体偏移距离(默认50) 圆角矩形, 圆角 = 假体圆角R(默认15)
;;       6) 热咀 = 预画 RZ 照用(补同心点孔) 否则放流道拐点; 点孔=点孔半径R
;;       7) 螺丝 = 预画 LS 照用 否则左右板边中点向内 螺丝孔内偏(默认15)
;;       8) 删除 LD 源线(重跑需重画; 与画图同一撤销组, 一次 Ctrl+Z 找回)
;;       不走裁剪/封口/断口圆角(矩形板边不依赖流道拓扑)
;; ---------------------------------------------------------------------------
(defun dt:rect-process ( / doc layers ss objs bb total-purged rz-snap ls-snap
                           corners nl ls-count cham x0l x1r cy ld-del l c s)
  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        layers (vla-get-layers doc))
  ;; 1) 建全部 14 层(与通用模板一致, 空图跑一次也能建齐, 颜色无重复)
  (foreach l (list (list "LD" 7 "白色") (list "FLB" 1 "红色")
                   (list "FBX" 3 "绿色") (list "LS" 4 "青色")
                   (list "JT" 6 "洋红") (list "JTFBX" 70 "黄绿")
                   (list "RZ" 30 "橙色") (list "DK" 8 "灰色")
                   (list "DP" 5 "蓝色") (list "CX" 140 "天蓝")
                   (list "CXK" 150 "亮蓝") (list "JRT" 2 "黄色")
                   (list "JRTDW" 40 "橙黄") (list "ZJJ" 210 "紫色"))
    (dt:ensure-layer layers (car l) (cadr l) (caddr l)))
  (princ "\n【矩形】已预建全部 14 个图层(LD/FLB/FBX/LS/JT/JTFBX/RZ/DK/DP/CX/CXK/JRT/JRTDW/ZJJ)。")
  ;; 2) LD 对象与整体范围
  (setq ss (ssget "X" (list (cons 8 "LD"))))
  (if (null ss)
    (progn
      (dt:flb-process-zjj)
      (princ "\n【提示】图层 \"LD\" 没有任何对象, 请先画好流道中心线再运行。"))
    (progn
      (setq objs (mapcar 'vlax-ename->vla-object (dt:ss->list ss)))
      (setq bb (dt:rect-bbox objs))
      (if (null bb)
        (princ "\n【矩形】无法计算 LD 整体范围(对象类型不支持), 中止。")
        (progn
          ;; 3) 快照预画 RZ/LS(手画优先) → 清理旧产物(清单同通用模板)
          (setq rz-snap (dt:rect-snap-circles "RZ")
                ls-snap (dt:rect-snap-circles "LS"))
          (command "_.UNDO" "BE")
          (setq total-purged (+ (dt:purge-layer "FLB") (dt:purge-layer "FBX")
                                (dt:purge-layer "LS") (dt:purge-layer "JT")
                                (dt:purge-layer "JTFBX") (dt:purge-layer "RZ")
                                (dt:purge-layer "DK") (dt:purge-layer "ZJJ")))
          (command "_.UNDO" "E")
          (princ (strcat "\n已清理上一轮产物 " (itoa total-purged) " 个对象。"))
          (command "_.UNDO" "BE")
          ;; 4) 板边矩形 + 四角倒角
          (setq cham (dt:rect-plate bb *dt-offset-dist* *dt-rect-chamfer*))
          (if (< cham *dt-rect-chamfer*)
            (princ (strcat "\n【警告】板角倒角超出可倒范围, 已自动改为 "
                           (rtos cham 2 2) "。")))
          (princ (strcat "\n【矩形】板边: LD 外扩 " (rtos *dt-offset-dist* 2 2)
                         " → 矩形 FLB, 四角倒角 " (rtos cham 2 2) "。"))
          ;; 5) 假体圆角矩形
          (dt:rect-jt bb *dt-hole-dist* *dt-fillet-r-hole*)
          (princ (strcat "\n【假体】LD 外扩 " (rtos *dt-hole-dist* 2 2)
                         " → 圆角矩形 JT(圆角 R" (rtos *dt-fillet-r-hole* 2 2) ")。"))
          ;; 6) 热咀 + 点孔(手画优先, 没画放流道拐点)
          (setq nl 0)
          (if rz-snap
            (progn
              (dt:rect-restore-circles rz-snap "RZ")
              (foreach s rz-snap
                (if (> *dt-pin-r* 0.0)
                  (dt:rect-addcircle (list (car s) (cadr s) 0.0) *dt-pin-r* "DK")))
              (setq nl (length rz-snap))
              (princ (strcat "\n【热咀】采用预画 RZ 圆 " (itoa nl)
                             " 个(已按点孔半径R补同心点孔)。")))
            (progn
              (setq corners (dt:rect-corners objs))
              (foreach c corners
                (dt:rect-addcircle c *dt-nozzle-r* "RZ")
                (if (> *dt-pin-r* 0.0)
                  (dt:rect-addcircle c *dt-pin-r* "DK"))
                (setq nl (1+ nl)))
              (if (> nl 0)
                (princ (strcat "\n【热咀】流道拐点自动放热咀 " (itoa nl)
                               " 个(R" (rtos *dt-nozzle-r* 2 2) ", 同心点孔)。"))
                (princ "\n【警告】未找到流道拐点(不同 LD 线端点重合处); 可在 RZ 层手画热咀圆后重跑, 或检查 LD 是否闭环。"))))
          ;; 7) 螺丝(手画优先): 左右板边中点向内 螺丝孔内偏
          (setq ls-count 0)
          (if ls-snap
            (progn
              (dt:rect-restore-circles ls-snap "LS")
              (setq ls-count (length ls-snap))
              (princ (strcat "\n【螺丝】采用预画 LS 圆 " (itoa ls-count) " 个。")))
            (progn
              (setq x0l (- (car bb) *dt-offset-dist*)
                    x1r (+ (caddr bb) *dt-offset-dist*)
                    cy (* 0.5 (+ (cadr bb) (cadddr bb))))
              (dt:rect-addcircle (list (+ x0l *dt-screw-in*) cy 0.0) *dt-screw-r* "LS")
              (dt:rect-addcircle (list (- x1r *dt-screw-in*) cy 0.0) *dt-screw-r* "LS")
              (setq ls-count 2)
              (princ (strcat "\n【螺丝】左右板边中点向内 " (rtos *dt-screw-in* 2 2)
                             " 各放螺丝 1 个(R" (rtos *dt-screw-r* 2 2) ")。"))))
          ;; 8) 删除 LD 源线(slot v9.6 同款约定: 重跑需重画源线; 与画图
          ;;    同一撤销组, 一次 Ctrl+Z 连同源线一起找回)
          (setq ld-del (dt:purge-layer "LD"))
          ;; 8.5) 若有 DP 垫片圆，同步在圆心创建主进胶圆 (ZJJ)
          (dt:flb-process-zjj)
          (command "_.UNDO" "E")
          ;; 9) 统计
          (princ (strcat "\n【完成·矩形】热咀 " (itoa nl) " 个, 螺丝 " (itoa ls-count)
                         " 个; 已删除 LD 源线 " (itoa ld-del)
                         " 个(重跑需重画)。出线槽用 SLOT, 加热条用 JRT。"))
          T))))
  (princ))

;; ============================================================================
;; 七、主命令 c:OFF —— 在命令行输入 OFF 即可执行
;; ============================================================================

;; 兼容旧命令别名
(defun c:OFF ( ) (c:FLB))
(defun c:FLB ( / *error* doc layers src-layer new-layer close-layer screw-layer
               hole-layer hole-close-layer
               offset-dist hole-dist hole-extend
               ss total ok-count skip-count total-purged res-off l)

  ;; ---- 内部错误处理: 出错或按 ESC 中断时给出友好提示 ----
  ;; v10.9: 兜底闭合可能悬挂的 UNDO 组(无开放组时无副作用, catch 双保险)。
  ;; v10.9 改 COM EndUndoMark —— 坑#69(jrt v9.17 定案): *error* 内调
  ;; (command) 在部分版本抛"push-error-using-command 前无法调用"并被
  ;; catch 吞掉 → 兜底恰在出错场景失效、UNDO 组悬挂(jrt dt:jrt-undo-end 同款)
  (defun *error* (msg)
    (vl-catch-all-apply
      '(lambda ( )
         (vla-EndUndoMark (vla-get-activedocument (vlax-get-acad-object)))))
    (princ (strcat "\n程序已停止: " (if msg msg "用户按 ESC 取消")))
    (princ)
  )

  ;; v8.0: 先弹出参数对话框(确定后参数已应用; 取消则中止流程)
  ;; v8.2 修复: 参数设置必须在弹框之后执行 —— 原来 setq 在弹框前,
  ;; 读到的是上一轮的全局值, 本轮对话框修改要下一轮才生效(滞后一轮)
  ;; v9.8: 最前面先弹模板选择框(通用/矩形); 覆盖表含 process 的模板
  ;; (矩形)整个主流程自管(建层/清理/绘制/统计), 不进入下方内置流程。
  (if (null (dt:flb-template-dialog))
    (princ "\n已取消(未选模板), 未执行。")
    (if (null (dt:param-dialog))
      (princ "\n已取消, 未执行偏移。")
      (if (setq res-off (cdr (assoc 'process (nth 3 (dt:flb-template-row)))))
        (apply res-off nil)
        (progn
      ;; ================= 参数设置 (v8.0: 从全局变量读取, 对话框确定后已更新) =================
      (setq src-layer   "LD"      ; 源图层名: 待偏移对象所在的图层
            new-layer   "FLB"      ; 分流板偏移结果图层(红色)
            close-layer "FBX"      ; 分流板封口线/倒角斜线图层(绿色)
            screw-layer "LS"        ; 螺丝孔圆图层(青色)
            hole-layer  "JT"  ; 假体偏移线图层(洋红, v7.7新增)
            hole-close-layer "JTFBX" ; 假体封口线/圆角图层(黄色, v7.7新增)
            offset-dist *dt-offset-dist*  ; 分流板偏移距离(全局参数, 可对话框改)
            hole-dist   *dt-hole-dist*    ; 假体偏移距离(全局参数)
            hole-extend *dt-hole-extend*  ; 假体线端头延长量(全局参数)
      )
      ;; ------------------------------------------------------------------
      ;; 第 1 步: 创建全部图层(v9.7: 预建三脚本所有图层, 空图跑 OFF 也能
      ;; 一次建齐; 已存在则不改属性, 同名小写自动纠正为大写)。
      ;; 产物层: FLB(红)/LS(青)/JT(洋红)/RZ(橙)/DK(白);
      ;; 流程临时层: FBX(绿)/JTFBX(黄), 收尾并入目标层后移除;
      ;; 预留层: DP 垫片(蓝, 只建层不自动画, 不参与清理);
      ;; 源线层: LD 流道中心线(白, 用户画);
      ;; 跨脚本预建层: CX 出线槽(蓝, slot 源线层)/CXK 出线口(蓝, slot
       ;; 分流产物层)/JRT 加热条(黄)/JRTDW 加热条定位(黄, jrt 通用二
       ;; 出线口位置标记)。颜色与 slot/jrt 各自建层时一致, ensure-layer 对已
      ;; 存在图层不改任何属性, 与另两脚本谁先建都不冲突。
      ;; ------------------------------------------------------------------
      (setq doc    (vla-get-activedocument (vlax-get-acad-object))
            layers (vla-get-layers doc))
      (foreach l (list (list src-layer 7 "白色")
                       (list new-layer 1 "红色")
                       (list close-layer 3 "绿色")
                       (list screw-layer 4 "青色")
                       (list hole-layer 6 "洋红")
                       (list hole-close-layer 70 "黄绿")
                       (list "RZ" 30 "橙色")
                       (list "DK" 8 "灰色")
                       (list "DP" 5 "蓝色")
                       (list "CX" 140 "天蓝")
                       (list "CXK" 150 "亮蓝")
                       (list "JRT" 2 "黄色")
                       (list "JRTDW" 40 "橙黄")
                       (list "ZJJ" 210 "紫色"))
        (dt:ensure-layer layers (car l) (cadr l) (caddr l)))
      ;; ----------------------------------------------------------------
      ;; 第 2 步: 一次性选中"LD"图层上的全部对象(覆盖全图, 无需逐个选择)
      ;; ----------------------------------------------------------------
      (setq ss (ssget "X" (list (cons 8 src-layer))))
      (if (null ss)
        (progn
          (dt:flb-process-zjj)
          (princ (strcat "\n【提示】图层 \"" src-layer "\" 已就绪但没有任何对象, 请画好流道中心线后再运行 OFF。")))
        (progn

          ;; ------------------------------------------------------------
          ;; 第 3.5 步: 清理上一轮产物(重跑 OFF 时清除旧的分流板/封闭线/
          ;; 螺丝图层对象, 避免旧对象被本轮流程重复处理造成混乱)。
          ;; 注意: 历史上泄漏在"FBX"图层的偏移辅助线也会被清掉,
          ;; 否则倒角步骤会把它当成封口线, 产生"虚空倒角"。
          ;; ------------------------------------------------------------
          (command "_.UNDO" "BE")
          (setq total-purged (+ (dt:purge-layer new-layer)
                                (dt:purge-layer close-layer)
                                (dt:purge-layer screw-layer)
                                (dt:purge-layer hole-layer)
                                (dt:purge-layer hole-close-layer)
                                (dt:purge-layer "RZ")
                                (dt:purge-layer "DK")
                                (dt:purge-layer "ZJJ")))
          ;; 注意: DP(垫片)/CX(出线槽)/CXK(出线口)/JRT(加热条)/
          ;; JRTDW(加热条定位)均不清理 —— DP/JRTDW 留给用户手动绘制,
          ;; CX/CXK 归 cx_runner 脚本, JRT 归 jrt_runner 脚本(重跑各自自清)。
          (command "_.UNDO" "E")
          (princ (strcat "\n已清理上一轮产物 " (itoa total-purged)
                         " 个对象(FLB/FBX/LS/JT/JTFBX/RZ/DK 图层)。"))

          ;; ------------------------------------------------------------
          ;; 第 4 步: 遍历"LD"图层每个对象, 向两侧各偏移一次(放入"FLB")
          ;; ------------------------------------------------------------
          (setq total (sslength ss)   ; 流道线对象总数(第2步已选中)
                res-off (dt:offset-layer src-layer new-layer offset-dist)
                ok-count (car res-off)
                skip-count (cadr res-off))

          ;; ------------------------------------------------------------
          ;; 第 5 步: 区域裁剪 —— 移除伸进其他流道带状区域内的线
          ;; ------------------------------------------------------------
          (dt:trim-all offset-dist new-layer)

          ;; ------------------------------------------------------------
          ;; 第 6 步: 断口圆角 —— 用圆弧连接相邻断口, 半径15(不足则递减并标注)
          ;; ------------------------------------------------------------
          (dt:fillet-all offset-dist new-layer)

          ;; ------------------------------------------------------------
          ;; 第 7 步: 通道封口 —— 封上每条流道通道两端的开放口(封闭线图层)
          ;; ------------------------------------------------------------
          (dt:close-channels offset-dist new-layer close-layer)

          ;; ------------------------------------------------------------
          ;; 第 7.5 步: 热咀+点孔圆(v9.2~v9.4) —— 每条封口线 = 一个封闭
          ;; 通道端头, 在封口线中点沿通道向内偏移 *dt-nozzle-offset*
          ;; (默认40) 处画热咀半径(默认11.35)圆 → "RZ" + 同心点孔半径
          ;; (默认3)圆 → "DK"。
          ;; 必须在倒角(第9步)之前执行: 倒角后"FBX"图层混入斜线,
          ;; 无法再纯按图层识别封口线; 也不改任何轮廓几何。
          ;; ------------------------------------------------------------
          (dt:nozzle-circles new-layer close-layer)

          ;; ------------------------------------------------------------
          ;; 第 8 步: 螺丝孔定位 —— 向内偏移10, 交点画圆(螺丝孔R, 默认4.25)
          ;; 注意: 必须在封口倒角(第9步)之前执行! 因倒角会把封口线端点
          ;; 与偏移线端头各自缩进5并加斜线, 破坏端点重合关系, 导致螺丝
          ;; 孔定位找不到封口线连接的偏移线。先画圆(圆在"LS"图层,
          ;; 独立于封口线/偏移线), 再倒角(只改封口线与偏移线端点,
          ;; 不影响已画好的圆), 两者互不干扰。
          ;; ------------------------------------------------------------
          (dt:drill-holes offset-dist)

          ;; ------------------------------------------------------------
          ;; 第 9 步: 封口倒角 —— 封口线两端直角做倒角(距离5), 失败标注
          ;; ------------------------------------------------------------
          (dt:chamfer-close offset-dist)

          ;; ------------------------------------------------------------
          ;; 第 9.5 步: 封闭线收尾并层(v9.1) —— 封口线/倒角斜线全部移入
          ;; "FLB"图层并移除"FBX"图层。流程内部临时使用该图层是为
          ;; 了螺丝孔定位/倒角能按图层识别封口线, 收尾统一并入。
          ;; ------------------------------------------------------------
          (command "_.UNDO" "BE")
          (dt:merge-layer close-layer new-layer)
          (command "_.UNDO" "E")

          ;; ============================================================
          ;; 分流板假体流程 (v7.7 新增) —— 放在分流板全流程之后
          ;; 流道线再向两侧偏移 hole-dist(50) 生成假体轮廓, 与分流板流程
          ;; 相同的裁剪/圆角/封口, 最后一步为封口线两端圆角(半径15, 失败标注)
          ;; 顺序说明: 必须先完成分流板(小圈)再做假体(大圈)——假体线距
          ;; 分流板封口线端点恰为 15(偏移差), 若先做假体会干扰分流板的
          ;; 封口/倒角端点匹配; 先小圈后大圈互不干扰。
          ;; ============================================================
          (princ (strcat "\n\n【假体】开始分流板假体流程(偏移 " (rtos hole-dist 2 0)
                         ", 图层\"" hole-layer "\")..."))

          ;; ------------------------------------------------------------
          ;; 第 10~15.5 步: 分流板假体 (v10.5: 默认传统逐步, 参数框勾选包络法切换)
          ;; 传统(默认): LD偏移 hole-dist → 带状裁剪 → 断口圆角 → 延长15
          ;;   → 端点封口 → 封口圆角 → 并层(每步命令行有计数输出)
          ;; 包络(勾选): JT = FLB 包络盒外扩(hole-dist-offset-dist) 圆角矩形
          ;; 传统法已知局限(坑 #55): 通道间距 < 2×hole-dist 时 JT 互删碎裂
          ;; ------------------------------------------------------------
          (if *dt-jt-envelope*
            (progn
              (setq res-off (dt:jt-build hole-dist offset-dist hole-layer))
              (if res-off
                (progn
                  (princ (strcat "\n【假体】包络法完成(" res-off ")。"))
                  ;; 无封口线 —— "JTFBX" 为空层, 并入后删除层定义保持整洁
                  (command "_.UNDO" "BE")
                  (dt:merge-layer hole-close-layer hole-layer)
                  (vl-catch-all-apply
                    '(lambda ( )
                       (vla-delete (vla-item
                                     (vla-get-layers
                                       (vla-get-activedocument
                                         (vlax-get-acad-object)))
                                     hole-close-layer))))
                  (command "_.UNDO" "E"))
                ;; 勾选了包络但失败: 不静默回退传统(避免画出非预期形状), 明确提示
                (princ "\n【假体】包络法未执行(FLB 为空/外扩量过小), 本次无假体, 请自行处理。")))
            (progn
              (princ "\n【假体】传统逐步流程: 偏移50 → 裁剪 → 断口圆角 → 延长15 → 封口 → 封口圆角。")
              (dt:offset-layer src-layer hole-layer hole-dist)
              (dt:trim-all hole-dist hole-layer)
              (dt:fillet-all offset-dist hole-layer)
              (setq res-off (dt:extend-ends hole-layer hole-extend hole-dist))
              (princ (strcat "\n【假体】延长与封闭线连接的假体线端头 "
                             (rtos hole-extend 2 0) ", 共处理 "
                             (itoa res-off) " 条线。"))
              (dt:close-channels hole-dist hole-layer hole-close-layer)
              (dt:fillet-close hole-dist)
              (command "_.UNDO" "BE")
              (dt:merge-layer hole-close-layer hole-layer)
              (command "_.UNDO" "E")))

          ;; 步骤 16.5: 若有 DP 垫片圆，同步在圆心创建主进胶圆 (ZJJ)
          (dt:flb-process-zjj)

          ;; ------------------------------------------------------------
          ;; (v9.0 起: 出线槽流程已移至独立脚本 cx_runner, 命令 SLOT)
          ;; ------------------------------------------------------------

          ;; ------------------------------------------------------------
          ;; 第 17 步: 输出最终统计结果
          ;; ------------------------------------------------------------
          (princ (strcat "\n【完成】图层 \"" src-layer "\" 共处理 " (itoa total) " 个对象, "))
          (princ (strcat "成功偏移 " (itoa ok-count) " 个, 跳过 " (itoa skip-count) " 个。"))
          (princ (strcat "\n分流板\"" new-layer "\"(红), 螺丝孔\"" screw-layer "\"(青), "
                         "分流板假体\"" hole-layer "\"(洋红)。"
                         "封口线已分别并入分流板/假体图层(封闭线图层已移除)。"
                         "出线槽请用 cx_runner 脚本(CX 命令)。"))
        )
      )
      )
    )
  )
  )
  (princ)  ; 静默退出, 不打印返回结果
)

;;; 加载时在命令行输出提示
(dt:flb-cfg-boot)
(princ "\n流道线偏移+裁剪+圆角+封口+螺丝孔+倒角+假体+热咀工具 v10.6 已加载(分流板专用; 多模板 通用/矩形; 假体默认传统逐步, 参数框勾选「包络法」切换; 参数默认值外置 ini+记忆)。")
(princ "\n用法1: 输入 FLB 执行完整流程(弹出参数框, 确定后开始)。")
(princ "\n用法2: 输入 FLBPARAM 弹出参数设置对话框(只改参数不执行)。")
(princ "\n用法3: 输入 (dt:trim-all 35.0 \"FLB\") 只做区域裁剪。")
(princ "\n用法4: 输入 (dt:fillet-all 35.0 \"FLB\") 只做断口圆角。")
(princ "\n用法5: 输入 (dt:close-channels 35.0 \"FLB\" \"FBX\") 只做通道封口。")
(princ "\n用法6: 输入 (dt:chamfer-close) 只做封口倒角。")
(princ "\n用法7: 输入 (dt:drill-holes) 只做螺丝孔定位。")
(princ "\n用法8: 输入 (dt:fillet-close) 只做假体封口圆角。")
(princ "\n提示: 出线槽已独立为 cx_runner 脚本(APPLOAD cx_runner.lsp 后输入 CX 执行)。")
(princ)