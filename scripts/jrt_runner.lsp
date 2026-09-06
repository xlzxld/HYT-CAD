;;; ============================================================================
;;; 程序名 : 加热条自动绘制工具 (jrt_runner.lsp)  v9.19
;;; v9.17  : 修复 v9.16 运行报「调用(*push-error-using-command*)前无法从
;;;          *error* 调用(command)」(坑 #69 在本文件的残留): ①根因 = 出线口
;;;          交点解析误用 cadr 取 dt:cross-points 的返回对 (obj . pts) ——
;;;          cadr 拿到的是首个交点(裸点), foreach 对其坐标数字求 distance
;;;          抛类型错误, 异常传入 *error* 后其 (dt:jrt-undo-end) 非法
;;;          调用掩盖了真错。改为 cdr 取交点列表 + cross-points 加 catch;
;;;          ②本文件全部 (command "_.UNDO" "BE"/"E") 改 COM 撤销标记
;;;          (dt:jrt-undo-mark/-end, 同 wx v2.2 坑 #69 定案), *error* 不再
;;;          碰 (command); 用户建议的 command-s 会破坏 2007~2011 兼容故未采。
;;; v9.16  : 通用二「单线自动补边」按用户截图定稿重写(v9.15 把出线口误判为
;;;          "端部喇叭", 生成几何不符, 已废弃): 用户只画 ①外壁整圈(JRT 层;
;;;          请用直线/圆弧/开放多段线, 勿用闭合多段线) ②JRTDW 定位短线
;;;          (每处出线口一条, 贴着外壁指向板边)。脚本自动完成旧手工三步:
;;;            偏移 = JRTDW 朝两边偏 jrt2_half_w → 出线通道两壁线(JRT 层);
;;;            裁剪 = 外壁在通道处开口(切口到过渡弧切点为止);
;;;            圆角 = 外壁断头↔通道线过渡弧 jrt2_end_r(钝/锐角按 r/tan(α/2)
;;;                   解析, 直角即 R12)。
;;;          生成件(通道线/过渡弧/切口后壁段)为持久源线, 不入重跑清理表,
;;;          与手画产物同权; 重跑幂等(已开处自动跳过); 之后走原嵌套引擎。
;;; v9.15  : (已被 v9.16 取代) 首版单线补边——把出线口误判为"端部喇叭",
;;;          生成几何与用户需求不符, 未交付使用。
;;; v9.14  : 健壮性修复(与 offset v10.6 / slot v10.3 / dt_start v2.8 同期,
;;;          几何行为零变化):
;;;          1) LD 源图层混入文字/块等非曲线实体时不再崩溃 —— c:JRT 取
;;;             LD 后统一按 dt:curve-p 过滤(原 dt:jrt-touch-p/jrt-free-ends
;;;             对全量对象直接求端点, 无 catch 无过滤, 会抛"参数类型错误"
;;;             中断); jrt-trim/jrt-fillet 的 LD 引用同步过滤;
;;;          2) cut-params 多段线分支 getparamatpoint 返回 nil 时剔除再
;;;             排序(nil 进 vl-sort 报 bad argument type);
;;;          3) 对话框 load_dialog/start_dialog 包 catch 且保证
;;;             unload_dialog 执行; ini/dcl 文件句柄异常兜底关闭;
;;;          4) c:JRT 的 *error* 兜底闭合 UNDO 组;
;;;          5) 参数应用增加负值校验(负值回退当前值);
;;;          6) cross-points 加包围盒预过滤(补 dt:rect-bbox 双绑定兼容
;;;             库副本, bbox 不相交跳过 COM 求交, 结果不变, 大图提速)。
;;; v9.13  : 全面审查定稿版(与 offset v10.5 / slot v10.1 / dt_start v2.7
;;;          同期): 1) 参数框数值读取 atof→distof(垃圾输入不再被静默当成 0,
;;;          坑 #54); 2) INI 节名解析改用"截到行尾再裁方括号", 修复 AutoCAD
;;;          2021 之前中文节名(如"[通用一]")残留 "]" 导致配置节永远匹配不上
;;;          的问题; 3) 记忆文件不再重复写出第二个 [模板] 节; 4) 补声明全部
;;;          遗漏的 foreach/setq 局部变量(dt:jrt-decide 的 o、dt:jrt2-neck 的
;;;          p/sgn/wx 等此前泄漏为全局); 5) 闭合多段线判定补
;;;          vl-catch-all-error-p; 6) 移除出线口相交处的遗留【调试】输出。
;;; v9.12  : 参数默认值外置 jrt_runner.ini(按模板分节, 记事本可改, 弹框即生效);
;;;          参数记忆 jrt_runner_mem.ini(按模板各一套, 确定参数框自动保存,
;;;          上次模板+上次值跨会话恢复); 恢复默认 = ini 配置的默认值。
;;; v9.11b : dt:jrt-find-dcl 弃用旧 findfile 候选链(v95~v98 文件名已不存在),
;;;          统一为 *dt-script-dir* 确定性模式(与 offset/slot 一致,
;;;          由 dt_start v2.1 引导器注入目录)。
;;; 适用   : AutoCAD 2024 (AutoCAD 2007 及以上版本均可)
;;; 多模板 : v9.8 起支持多套规则模板(dt:jrt-template-table 内置注册)。
;;;          JRT 执行时先弹独立模板选择框(单选列表), 确定后采用该模板
;;;          的参数默认值并按其规则生成; 主流程(偏移/裁剪/多层递进)共用,
;;;          模板通过"环节覆盖表"替换个别环节, 可覆盖 5 个环节:
;;;            decide     端帽判定  (默认 dt:jrt-decide, 签名 (ld-vlas matched))
;;;            cap-circle 圆帽几何  (默认 dt:jrt-cap-circle, 签名 (plan ents hw))
;;;            cap-line   直线帽几何(默认 dt:jrt-cap-line, 签名 (plan ents hw inset capr))
;;;            build      单层全流程(默认 dt:jrt-build, 签名 (hw inset r capr plans))
;;;            process    主流程整体(v9.9 新增, 无默认函数; 签名无参, 覆盖后
;;;                       整个流程由该函数自管, 不再走内置 LD/RZ 流程)
;;;          新增模板 = 在 dt:jrt-template-table 加一行(名称/说明/参数默认表/
;;;          覆盖表), 需要不同环节时新增覆盖函数 defun 并在覆盖表登记,
;;;          交付新版本文件; 覆盖函数签名须与默认函数完全一致(process 无默认
;;;          函数)。参数默认表只列该模板用到的参数键, 参数框按模板动态显示。
;;; 功能   : "LD"图层中心线向两侧各偏移 流道线偏移距离(默认29) → "JRT"图层
;;;          (黄色), 生成多层完整嵌套的加热条半成品轮廓(外层+内向偏移
;;;          jrt-inner-count 次(默认2), 每次向内收 jrt-inner-step(默认4)):
;;;          1) 区域裁剪: 侵入其他流道带状区域(±半宽)的段删除, 交叉处断开;
;;;          2) 断口圆角: 断口两线圆弧连接(R=圆角半径, 不足相切自动递减;
;;;             内层圆角逐层 +步长 递增, 默认 19→23→27, 与端帽圆 29/25/21
;;;             同为同心嵌套弧: 交汇肩部圆心=(半宽+R)处, 内层半宽收 step、
;;;             圆角加 step, 圆心不动);
;;;          3) 通道端帽(每层同款):
;;;             端帽形式按"相邻通道条带内壁间距"判定(全端头统一在第一层
;;;             判定一次, 各层共用同一形式):
;;;             - 间距≈偏移值(29) 且端头匹配到 RZ 热咀圆 → 圆帽: 在 RZ 圆心
;;;               处画整圆 R=半宽(与两条偏移线相切), 侧线端头修到切点;
;;;             - 间距超过偏移值 / 无相邻通道 / 无 RZ → 直线帽(v9.6 重构):
;;;               按"原封闭线平面=LD 端点平面(test.dxf 实测)"向通道内偏移
;;;               封闭线内偏移距离(默认11) 确定封闭线位置, 封闭线与两条相接
;;;               偏移线圆弧衔接 —— 封闭线圆角半径R(默认29) >= 半宽 时直接
;;;               替换为一个与两测线相切的圆弧(圆心=帽线中点向内偏半宽,
;;;               默认参数下 40-11=29 恰为 RZ 圆心, 与圆帽外轮廓一致);
;;;               < 半宽 时画直线封闭线+两端解析法圆角, 侧线端头修到切点,
;;;               裁掉端点平面方向多余的线段。
;;;          "通用二"模板(v9.9, v9.10 扩展出线口): 源线="JRT"图层手画曲线
;;;          (非 LD), 参数= 向内偏移步长/内向偏移次数/出线颈线长度/出线
;;;          颈线偏移/出线封口圆角R/出线相交圆角R; 第 k 层把每段源线向
;;;          "JRTDW" 定位层一侧内偏 k×步长(锚段=离定位线最近的段朝定位
;;;          线选边, 其余沿轮廓链传播); 不裁剪/不倒角/不端帽 —— 出线的
;;;          每个"头"用一条直线把最外侧与最内侧端头连起来(两头各一条)
;;;          成闭环; 源线保留, 上一轮产物按句柄记忆在重跑时先删。
;;;          出线口(v9.10): JRTDW 一端与 "FLB" 相交, 从交点沿 JRTDW 方向
;;;          画构图颈线 → ±35 偏移成两壁(构图颈线随即删除) → 远端封闭线
;;;          封口+两角 R15 圆角 → 两壁与原 JT 线相交处裁掉走廊内多余 JT
;;;          线段, 相交处 R15 圆角(弧向与 JRT 出线处一致); 逻辑复用分流
;;;          板裁剪链; 单条 JT 线裁剪失败仅跳过并告警不中断。
;;; 版本   : v9.5 = 首版(三层嵌套轮廓/交汇裁剪+圆角/端帽按相邻通道内壁
;;;          间距判定 RZ 整圆帽/直线帽, 命令 JRT/JRTPARAM)。
;;;          v9.6 = 直线帽重构: 封闭线与两条相接偏移线圆弧衔接(半径
;;;          >=半宽时整弧替换); 参数改名 流道线偏移距离/封闭线内偏移距离;
;;;          新增 封闭线圆角半径R / 内向偏移次数(层数参数化)。
;;;          v9.7 = 圆角半径默认 29→19; 内层圆角改为逐层 +步长 递增
;;;          (19→23→27, 同心嵌套弧; 原为递减 19→15→11, 方向错误)。
;;;          v9.8 = 多模板框架: 模板注册表 + 独立选择框 + 环节覆盖分发
;;;          (dt:jrt-stage); 现有逻辑登记为内置"通用"模板。
;;;          v9.9 = 新增"两点式"模板(JRT 源线朝 JRTDW 定位线内偏嵌套 +
;;;          出线两头各一线连最内最外成闭环); 参数框按模板动态显示参数
;;;          项; 环节覆盖新增 process(主流程整体); 产物按句柄记忆重跑先删。
;;;          v9.10 = 模板更名: 通用→通用一、两点式→通用二; 通用二新增
;;;          出线口(JRTDW×FLB 颈线/双壁/远端封口圆角/裁走廊内 JT 线/
;;;          相交圆角, 新增 4 参数: 颈线长度65/颈线偏移35/封口R15/相交R15);
;;;          通用二消息前缀【两点式】→【通用二】。
;;;          v9.11 = 出线口修正: 壁裁剪侧改为保留 cap 侧/裁 pint 侧;
;;;          相交圆角改专用 dt:jrt2-junction —— 壁切点沿朝 cap 方向、
;;;          JT 保留段沿远离走廊方向, 弧倒掉走廊口尖角, 与
;;;          JRT 出线处圆弧同向(v9.10 弧向做反); 修 snapshot ename 误用
;;;          handent 的 stringp 崩溃。
;;; 来源   : 仿 cx_runner 先例的独立脚本(助手函数自 flb_runner v9.5
;;;          逐字复制, 专属逻辑全部 dt:jrt-* 前缀), 可与主脚本/出线槽脚本
;;;          同时加载互不影响(参数表/对话框/dcl/回调均已改名隔离;
;;;          fillet-pair/cut-curve 因 slot 版签名不同也改名隔离)。
;;; 前提   : 先运行 FLB(flb_runner)使 "RZ" 图层存在; 运行本脚本时
;;;          "FBX" 封闭线图层已被 OFF 收尾并层移除 —— 本脚本不读 FBX,
;;;          端帽平面直接取 LD 端点平面推导。
;;; 图层   : "JRT" = 加热条(黄色 2, 产物同层; 通用一模板=纯产物层重跑全清;
;;;          通用二模板=源线层不清理, 上一轮产物按句柄记忆重跑先删)。
;;;          "JRTDW" = 加热条定位图层(通用二向内方向基准: 偏移朝向它、
;;;          以它为中心, 每条加热条画一个定位标记, 一端与 FLB 相交)。
;;;          "JT" = 分流板假体(OFF 产物); 通用二出线口会把颈线/两壁/
;;;          封口线画上 JT, 并裁掉走廊带内的原 JT 线段。
;;; 加载   : APPLOAD 选择本文件加载(jrt_runner.dcl 由脚本自动生成)。
;;; 命令   : JRT      —— 弹出参数框, 确定后执行加热条全流程(取消中止)
;;;          JRTPARAM —— 只弹出参数框改参数, 不执行
;;; 已知限制: 与主脚本一致(多段线重建丢凸度/闭合多段线跳过等);
;;;          端头落在其他通道带状区域内时该端侧壁可能已被裁掉, 跳过端帽
;;;          并告警; RZ 圆心不在任何 LD 轴线上(垂距>0.5)时该圆不参与匹配。
;;; 说明   : 本文件必须 UTF-8 with BOM 编码(中文注释); 自动生成的
;;;          jrt_runner.dcl 为 ANSI/GBK(系统代码页)。
;;; ============================================================================

(vl-load-com)  ; 加载 Visual LISP 扩展, 使 vla-* 系列函数可用

;; 坑 #69(v9.17): 撤销组统一走 COM 标记 —— *error* 与普通代码都不再碰
;; (command); 无开放标记时 EndUndoMark 无副作用, 双重 catch 兜底
(defun dt:jrt-undo-mark ( )
  (vl-catch-all-apply
    '(lambda ( )
       (vla-StartUndoMark (vla-get-activedocument (vlax-get-acad-object))))))

(defun dt:jrt-undo-end ( )
  (vl-catch-all-apply
    '(lambda ( )
       (vla-EndUndoMark (vla-get-activedocument (vlax-get-acad-object))))))

;; ============================================================================
;; 加热条参数 —— 由 dt:jrt-param-table 驱动(默认值/预填/应用/恢复默认),
;; 与 flb_runner / cx_runner 的参数表相互独立, 同时加载互不影响。
;; ============================================================================
(setq dt:jrt-param-table
      (list
        (list "jrt_offset"      '*jrt-offset*      29.0) ; 流道线偏移距离(半宽, 通用一)
        (list "jrt_cap_inset"   '*jrt-cap-inset*   11.0) ; 封闭线内偏移距离(通用一)
        (list "jrt_fillet_r"    '*jrt-fillet-r*    19.0) ; 圆角半径(交汇断口, 通用一)
        (list "jrt_cap_r"       '*jrt-cap-r*       29.0) ; 封闭线圆角半径R(通用一)
        (list "jrt_inner_step"  '*jrt-inner-step*  4.0)  ; 向内偏移步长(通用一/二)
        (list "jrt_inner_count" '*jrt-inner-count* 2.0)  ; 内向偏移次数(通用一/二)
        (list "jrt2_neck_len"   '*jrt2-neck-len*   65.0) ; 出线颈线长度(通用二)
        (list "jrt2_neck_off"   '*jrt2-neck-off*   35.0) ; 出线颈线偏移(通用二)
        (list "jrt2_close_r"    '*jrt2-close-r*    15.0) ; 出线封口圆角R(通用二)
        (list "jrt2_trim_r"     '*jrt2-trim-r*     15.0) ; 出线相交圆角R(通用二)
        (list "jrt2_half_w"     '*jrt2-half-w*     16.5) ; 单线补边: 壁线距定位线半宽(通用二)
        (list "jrt2_end_r"      '*jrt2-end-r*      12.0))) ; 单线补边: 端部喇叭R(通用二)
(foreach p dt:jrt-param-table (set (cadr p) (caddr p)))

;; ============================================================================
;; 参数配置与记忆(v9.12): 默认值外置 jrt_runner.ini(按模板分节, 记事本可改,
;; 每次弹框前重读=随时生效); 上次值记忆 jrt_runner_mem.ini(按模板各一套,
;; 确定参数框时自动保存, 上次模板+上次值跨会话恢复)。
;; 解析只认"键 = 数值"行, 注释/空行/未知键跳过; 全程 vl-catch-all 保护,
;; 文件缺失/损坏静默回退代码内置默认。命名带 dt:jrt- 前缀防同加载覆盖(坑 #46)。
;; 函数在此定义, 启动 (dt:jrt-cfg-boot) 在文件尾调用(定义须先于执行)。
;; ============================================================================
(setq *jrt-cfg* nil   ; 配置(默认值) ((节 (键 . 值)...) ...) 节=模板名
      *jrt-mem* nil)  ; 记忆(上次值)   同结构 + [模板] template=下标

;; 配置/记忆文件目录: 优先 dt_start 注入的脚本目录, 无则 TEMP(与 find-dcl 同规则)
(defun dt:jrt-cfg-dir ( / )
  (if (and *dt-script-dir* (/= *dt-script-dir* ""))
    *dt-script-dir*
    (getenv "TEMP")))

;; 单行 "键 = 数值" → (键 . 值); 无等号/空值/非数值返回 nil(distof 校验, 0 合法)
(defun dt:jrt-cfg-kv (ln / p k vs n)
  (setq p (vl-string-search "=" ln))
  (if p
    (progn
      (setq k (vl-string-trim " \t" (substr ln 1 p))
            vs (vl-string-trim " \t" (substr ln (+ p 2)))
            n (if (= vs "") nil (distof vs)))
      (if (and (/= k "") n (numberp n)) (cons k n) nil))
    nil))

;; 读 INI → ((节名 (键 . 值)...) ...); 文件不存在/读失败返回 nil
(defun dt:jrt-cfg-read (path / f ln sec ent tmp secs)
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
                ;; v9.13: 原用 (- (strlen ln) 2) 取长度 —— AutoCAD 2021 之前
                ;;   strlen 按字节计而 substr 按字符计, 中文节名(如 "[通用一]")
                ;;   会连带尾部 "]"(变成 "通用一]")导致配置节永远匹配不上。
                (setq sec (vl-string-trim " \t[]" (substr ln 2))))
               ((setq ent (dt:jrt-cfg-kv ln))
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
  ;; v9.14: 异常兜底关闭 —— 读行中途出错时句柄不再滞留
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (reverse secs))

;; 数据 → 指定节的键值表(无该节 nil)
(defun dt:jrt-cfg-sec (data sec / e)
  (if (and data (setq e (assoc sec data))) (cdr e)))

;; 节内取键值(无该键 nil; 值可为 0, 0 非 nil 仍算"有")
(defun dt:jrt-cfg-get (data sec key)
  (cdr (assoc key (dt:jrt-cfg-sec data sec))))

;; 当前模板的参数默认值: ini 配置节 → 模板内置默认表 → dt:jrt-param-table caddr
(defun dt:jrt-param-default (key / tpl v)
  (setq tpl (dt:jrt-template-row))
  (cond ((setq v (dt:jrt-cfg-get *jrt-cfg* (car tpl) key)) v)
        ((cdr (assoc key (nth 2 tpl))))
        (T (caddr (assoc key dt:jrt-param-table)))))

;; 首次自动生成配置文件(按模板分节 + 中文注释标签)
(defun dt:jrt-cfg-gen (path / f tpl kv lbl)
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "w"))
       (if f
         (progn
           (write-line "; jrt_runner 参数默认值配置(首次运行自动生成, 记事本可改)" f)
           (write-line "; 按模板分节; 改数值保存后, 下次打开模板/参数窗口即生效(无需重载)" f)
           (write-line "; 恢复默认按钮 = 本文件的值; 删除本文件 = 回代码内置默认" f)
           (write-line "; 上次填的值在 jrt_runner_mem.ini(程序自动维护, 一般不用管)" f)
           (write-line "" f)
           (foreach tpl dt:jrt-template-table
             (write-line (strcat "[" (car tpl) "]") f)
             (foreach kv (nth 2 tpl)
               (setq lbl (cdr (assoc (car kv) dt:jrt-param-labels)))
               (if lbl (write-line (strcat "; " lbl) f))
               (write-line (strcat (car kv) " = " (rtos (cdr kv) 2 4)) f))
             (write-line "" f))
           (close f)
           (setq f nil))))
    nil)
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  T)

;; 确定参数框后保存当前模板的上次值(每模板各一套; 只存该模板可见键)
(defun dt:jrt-mem-save ( / name keys vals path sc f kv)
  (setq name (car (dt:jrt-template-row))
        keys (dt:jrt-tpl-keys)
        vals (mapcar '(lambda (k) (cons k (eval (cadr (assoc k dt:jrt-param-table)))))
                     keys))
  (setq *jrt-mem* (cons (cons name vals)
                        (vl-remove (assoc name *jrt-mem*) *jrt-mem*))
        path (strcat (dt:jrt-cfg-dir) "\\jrt_runner_mem.ini"))
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "w"))
       (if f
         (progn
           (write-line "; jrt_runner 参数记忆(确定参数窗口时自动更新, 可删除)" f)
           (write-line "[模板]" f)
           (write-line (strcat "template = " (itoa *jrt-template*)) f)
           (write-line "" f)
           (foreach sc *jrt-mem*
             ;; v9.13: 跳过 "[模板]" 节(上方已单独写出)—— 否则会重复写出
             (if (/= (car sc) "模板")
               (progn
                 (write-line (strcat "[" (car sc) "]") f)
                 (foreach kv (cdr sc)
                   (write-line (strcat (car kv) " = " (rtos (cdr kv) 2 4)) f))
                 (write-line "" f))))
           (close f)
           (setq f nil))))
    nil)
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (princ))

;; 加载末尾调用: 生成缺失配置 + 恢复上次模板与该模板的上次参数值
(defun dt:jrt-cfg-boot ( / path idx)
  (vl-catch-all-apply
    '(lambda ( )
       (setq path (strcat (dt:jrt-cfg-dir) "\\jrt_runner.ini"))
       (setq *jrt-cfg* (dt:jrt-cfg-read path))
       (if (null *jrt-cfg*)
         (progn
           (dt:jrt-cfg-gen path)
           (setq *jrt-cfg* (dt:jrt-cfg-read path))))
       (setq *jrt-mem*
             (dt:jrt-cfg-read (strcat (dt:jrt-cfg-dir) "\\jrt_runner_mem.ini")))
       (setq idx (dt:jrt-cfg-get *jrt-mem* "模板" "template"))
       (if (and idx (numberp idx)
                (>= (fix idx) 0) (< (fix idx) (length dt:jrt-template-table)))
         (progn
           (setq *jrt-template* (fix idx)
                 *jrt-tpl-pick* (fix idx))
           (dt:jrt-apply-template (fix idx) T))))
    nil)
  (princ))

;; ============================================================================
;; 加热条模板注册表(v9.8, v9.9 扩展) —— 多套规则模板, JRT 执行时先弹独立选择框
;; 每行: (名称 说明 参数默认表 环节覆盖表)
;;   参数默认表: 该模板用到的参数键点对表(键为字符串, 与参数框控件同名;
;;               v9.9 由符号改字符串 —— 原符号键使 apply-template 的
;;               assoc 永远失配, 模板参数默认从未生效; 选择模板时写入
;;               全局变量, 参数框只显示这些键, "恢复默认"也回退这张表)
;;   环节覆盖表: 可覆盖 4 个环节 + 1 个主流程, 形如 ((decide . 函数)
;;               (cap-circle . 函数) (cap-line . 函数) (build . 函数)
;;               (process . 函数)); 前四者覆盖函数签名须与默认函数完全一致;
;;               process 覆盖后整个主流程由该函数自管(无参, 不走内置 LD
;;               流程, c:JRT 内直接调用); nil = 全部用默认环节
;; 新增模板: 在表中加一行(必要时新增覆盖函数 defun), 交付新版本。
;; ============================================================================
(setq dt:jrt-template-table
      (list
        (list "通用一"
              "端帽按相邻通道内壁间距判定(RZ整圆帽/封闭线圆弧帽)"
              '(("jrt_offset" . 29.0) ("jrt_cap_inset" . 11.0) ("jrt_fillet_r" . 19.0)
                ("jrt_cap_r" . 29.0) ("jrt_inner_step" . 4.0) ("jrt_inner_count" . 2.0))
              nil)
        (list "通用二"
              "JRT外壁整圈+JRTDW短线自动开出线口→朝JRTDW内嵌套(步长*次数); 多段源线按手画轮廓处理"
              '(("jrt2_half_w" . 16.5) ("jrt2_end_r" . 12.0)
                ("jrt_inner_step" . 4.0) ("jrt_inner_count" . 2.0)
                ("jrt2_neck_len" . 65.0) ("jrt2_neck_off" . 35.0)
                ("jrt2_close_r" . 15.0) ("jrt2_trim_r" . 15.0))
              '((process . dt:jrt2-process)))))
(setq *jrt-template* 0)   ; 当前选中模板下标(选择框确定后更新)
(setq *jrt-tpl-pick* 0)   ; 选择框单选过程中的临时下标(回调写入)
(setq *jrt2-made* nil)    ; 两点式上一轮产物句柄表(重跑先删; 句柄跨存盘有效)

;; ============================================================================
;; 一、工具函数(与主脚本 flb_runner v9.5 逐字一致)
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
        is-2d   (= (vla-get-objectname obj) "AcDbLWPolyline"))
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

;; v9.14: 实体是否为可求端点/曲线参数的曲线(直线/弧/多段线) —— 文字/块等
;; 混入源图层时 vlax-curve 系列会抛"参数类型错误"中断流程, 收集/迭代前
;; 一律先过本判定
(defun dt:curve-p (obj / tp)
  (setq tp (vl-catch-all-apply 'vla-get-objectname (list obj)))
  (if (vl-catch-all-error-p tp)
    nil
    (member tp '("AcDbLine" "AcDbArc" "AcDbLWPolyline" "AcDbPolyline"))))

;; v9.14: 列表过滤, 只留 dt:curve-p 为真的实体
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

;; 取曲线两端头信息: 返回 ((起点 起点指向主体方向) (终点 终点指向主体方向))
;; 方向均指向"曲线主体"内部, 用于圆角计算
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
  (setq is-poly (or (= (vla-get-objectname obj) "AcDbLWPolyline")
                    (= (vla-get-objectname obj) "AcDbPolyline"))
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
(defun dt:endpoint-in (obj et dist / total)
  (setq total (vlax-curve-getdistatparam obj (vlax-curve-getendparam obj)))
  (if (= et "S")
    (vlax-curve-getpointatdist obj (min dist total))
    (vlax-curve-getpointatdist obj (max 0.0 (- total dist)))))

;; ============================================================================
;; 二、切割重建链(与主脚本逐字一致; cut-curve/trim-curve 改名 dt:jrt-*:
;; cx_runner 的 dt:cut-curve 默认图层不同, 三脚本同时加载时避免互相覆盖)
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
     ;; v9.14: 交点浮点偏移曲线时 getparamatpoint 可能返回 nil(甚至抛错),
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
     (setq is-2d (= obj-type "AcDbLWPolyline"))
     (setq new-obj (dt:poly-rebuild obj t1 t2 (dt:poly-pts obj) is-2d))))
  (if new-obj (vla-put-layer new-obj layer))
  new-obj)

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

;; 通用切割驱动(裁剪模式; 主体与主脚本一致):
;;   把曲线按交点切成小段 -> 段中点落流道带状区域内(center-lines, 宽
;;   off-dist)的段删除 -> 保留段重建为新对象(放指定图层), 删原对象。
(defun dt:jrt-cut-curve (obj others-pts layer center-lines off-dist mode /
                     obj-type cut t-end i t1 t2 keep-segs closed-p seg)
  (if (null layer) (setq layer "JRT"))
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

;; 区域裁剪分发(改名隔离, 见 dt:jrt-cut-curve 说明)
(defun dt:jrt-trim-curve (obj others-pts center-lines off-dist layer)
  (dt:jrt-cut-curve obj others-pts layer center-lines off-dist "TRIM"))

;; boundingbox 输出解包: vla-getboundingbox 的输出参数有的版本绑定为
;; safearray 本体, 有的为 variant(内含 safearray) —— 统一容忍两种
;; (与 flb_runner 逐字一致; v9.14 供 cross-points 包围盒预过滤用)
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

;; 两包围盒 (minx miny maxx maxy) 是否相交(含接触);
;; 任一为 nil(取盒失败)时按相交处理, 不跳过求交 —— 保守不漏
(defun dt:bbox-overlap-p (a b)
  (if (or (null a) (null b))
    T
    (and (<= (car a) (caddr b)) (>= (caddr a) (car b))
         (<= (cadr a) (cadddr b)) (>= (cadddr a) (cadr b)))))

;; 列表内所有线两两求交(不延伸), 返回 ((对象 该对象的交点列表) ...), 顺序与入序一致
;; v9.14: 包围盒预过滤 —— 每对象只取一次 boundingbox(dt:rect-bbox), 两盒
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

;; ============================================================================
;; 三、断口圆角(主体与主脚本逐字一致, 改名 dt:jrt-fillet-pair:
;; cx_runner 的 dt:cx-fillet-pair 多一个 nochk 第7参, 三脚本同时加载时
;; 6/7 参定义互相覆盖会报参数数量错误)
;; ============================================================================

;; 处理一个断口对: 计算圆角几何, 递减半径, 方向验证, 修剪两线, 创建圆角弧, 必要时标注
;; h1/h2 = (对象 端类型"S"/"E" 端头点 指向主体方向)
;; layer = 圆角弧/标注文字所在图层
;; r-start = 圆角起始半径
;; 返回: (实际半径 T) 表示成功, nil 表示失败
(defun dt:jrt-fillet-pair (h1 h2 center-lines off-dist layer r-start / obj1 et1 p1 d1 obj2 et2 p2 d2
                       ang2 b1 b2 done r d-tan len1 len2 c t1 t2 m a1 a2
                       tmp arc txt txt-pt ms ok)
  (if (null layer) (setq layer "JRT"))
  (if (null r-start) (setq r-start *jrt-fillet-r*))
  (setq obj1 (car h1) et1 (cadr h1) p1 (caddr h1) d1 (cadddr h1)
        obj2 (car h2) et2 (cadr h2) p2 (caddr h2) d2 (cadddr h2))
  ;; 两切线方向夹角的一半
  (setq ang2 (/ (dt:angle-between d1 d2) 2.0))
  ;; 圆心候选方向: b1 = 角平分线(圆心在断口外侧=区域外, A方案)
  ;;               b2 = 补角平分线(备用, 方向反了时换用)
  (setq b1 (dt:unit (mapcar '+ d1 d2)))
  (setq b2 (dt:unit (mapcar '- d1 d2)))
  ;; 半径递减尝试: r-start -> 1, 要求切点不超出线的当前长度
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
      ;; 先按 b1 方向算圆心(区域外), 若侵入则换 b2
      (setq c (dt:pt+vec p1 b1 (/ r (sin ang2))))
      (if (dt:in-zone c center-lines off-dist)
        (progn
          (setq c (dt:pt+vec p1 b2 (/ r (sin ang2))))
          (if (dt:in-zone c center-lines off-dist)
            (setq ok nil)
            (setq ok T)))
        (setq ok T))
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
          (setq ms (dt:ms)
                a1 (angle (list (car c) (cadr c)) (list (car t1) (cadr t1)))
                a2 (angle (list (car c) (cadr c)) (list (car t2) (cadr t2))))
          (if (> (if (> a2 a1) (- a2 a1) (+ (- a2 a1) (* 2 pi))) pi)
            (setq tmp a1 a1 a2 a2 tmp))
          (setq arc (vla-addarc ms (vlax-3d-point c) r a1 a2))
          (vla-put-layer arc layer)
          ;; 实际半径小于起始半径 r-start 时, 在圆角旁标注文字(字高 10)
          (if (< r r-start)
            (progn
              (setq txt-pt (dt:pt+vec m b1 14.0))
              (setq txt (vla-addtext ms (strcat "R" (rtos r 2 0))
                                     (vlax-3d-point txt-pt) 10.0))
              (vla-put-height txt 10.0)
              (vla-put-layer txt layer)))
          (list r T))))))

;; 收集 VLA 列表内所有线端头(可按 eName 列表排除):
;; 返回 ((对象 端类型"S"/"E" 端头点 指向主体方向) ...)
;; v9.14: 先按 dt:curve-p 过滤(文字等非曲线实体的端点查询会抛错)
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

;; ============================================================================
;; 四、图层与偏移(与主脚本逐字一致)
;; ============================================================================

;; 确保图层存在: 不存在则创建并设颜色; 已存在则不改属性(返回新建对象或 nil)。
;; v9.5: AutoCAD 图层名不区分大小写 —— 若已存在图层与请求写法大小写不一致
;;       (如已有小写 "jrt"), 自动改名为请求写法("JRT"), 图上对象全部跟随。
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

;; 删除指定图层上的所有对象(保留图层定义), 用于重跑时清除上一轮产物
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
(defun dt:offset-layer (src-layer new-layer dist / ss)
  (setq ss (ssget "X" (list (cons 8 src-layer))))
  (if (null ss)
    (progn
      (princ (strcat "\n图层 \"" src-layer "\" 上没有任何对象, 无需偏移。"))
      (list 0 0))
    (dt:offset-enames (dt:ss->list ss) new-layer dist)))

;; ============================================================================
;; 五、加热条专属逻辑(dt:jrt-* 前缀, 不与主脚本/出线槽脚本冲突)
;; ============================================================================

;; 图层 eName 快照(用于差集跟踪单层构建的新产物)
(defun dt:jrt-snapshot (layer / ss)
  (setq ss (ssget "X" (list (cons 8 layer))))
  (if ss (dt:ss->list ss) nil))

;; 快照之后新增的 eName 列表(= 当前图上 JRT 对象 - 快照)
(defun dt:jrt-diff (old / cur out e)
  (setq cur (dt:jrt-snapshot "JRT") out nil)
  (foreach e cur
    (if (not (member e old)) (setq out (cons e out))))
  (reverse out))

;; 曲线采样点(参数 0/0.25/0.5/0.75/1) —— 用于两条曲线最小距离估算
;; (直线=精确; 折线/弧为近似, 判定容差 1.0 足够)
(defun dt:jrt-sample-pts (obj / e out k)
  (setq e (vlax-curve-getendparam obj) out nil k 0)
  (while (<= k 4)
    (setq out (cons (vlax-curve-getpointatparam obj (* e 0.25 k)) out)
          k (1+ k)))
  (reverse out))

;; 两曲线最小距离(双向采样求最近点)
(defun dt:jrt-curve-dist (o1 o2 / d cp p)
  (setq d 1e30)
  (foreach p (dt:jrt-sample-pts o1)
    (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list o2 p)))
    (if (not (vl-catch-all-error-p cp))
      (setq d (min d (distance p cp)))))
  (foreach p (dt:jrt-sample-pts o2)
    (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list o1 p)))
    (if (not (vl-catch-all-error-p cp))
      (setq d (min d (distance p cp)))))
  d)

;; 两曲线是否相交或端头搭在对方身上(T接/交叉), 容差 0.5
(defun dt:jrt-touch-p (o1 o2 / hit p)
  (or (dt:inters-pts o1 o2)
      (progn
        (setq hit nil)
        (foreach p (list (vlax-curve-getstartpoint o1)
                         (vlax-curve-getendpoint o1))
          (if (< (distance p (vlax-curve-getclosestpointto o2 p)) 0.5)
            (setq hit T)))
        (foreach p (list (vlax-curve-getstartpoint o2)
                         (vlax-curve-getendpoint o2))
          (if (< (distance p (vlax-curve-getclosestpointto o1 p)) 0.5)
            (setq hit T)))
        hit)))

;; 收集 LD 曲线的自由端头(排除"端点落在其他 LD 曲线上"的交汇端)
;; 返回 ((obj 端类型"S"/"E" 端点 另一端点) ...)
(defun dt:jrt-free-ends (ld-vlas / ends obj o others et pt opt junction cp)
  (setq ends nil)
  (foreach obj ld-vlas
    (setq others nil)
    (foreach o ld-vlas
      (if (not (equal (vlax-vla-object->ename o)
                      (vlax-vla-object->ename obj)))
        (setq others (cons o others))))
    (foreach et '("S" "E")
      (setq pt (if (= et "S") (vlax-curve-getstartpoint obj)
                 (vlax-curve-getendpoint obj))
            opt (if (= et "S") (vlax-curve-getendpoint obj)
                  (vlax-curve-getstartpoint obj))
            junction nil)
      (foreach o others
        (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list o pt)))
        (if (and (not (vl-catch-all-error-p cp))
                 (< (distance pt cp) 0.5))
          (setq junction T)))
      (if (not junction)
        (setq ends (cons (list obj et pt opt) ends)))))
  (reverse ends))

;; RZ 热咀圆 ↔ 自由端头匹配:
;; 圆心落在端头所在 LD 曲线近旁(垂距<0.5)且到本端点比到另一端点近 → 匹配
;; 返回 ((obj 端类型 端点 另一端点 圆心) ...), 未匹配的端头圆心为 nil
(defun dt:jrt-match-rz (free-ends rz-vlas / out rec obj et pt opt c o cp best)
  (setq out nil)
  (foreach rec free-ends
    (setq obj (nth 0 rec) et (nth 1 rec) pt (nth 2 rec) opt (nth 3 rec)
          best nil)
    (foreach o rz-vlas
      ;; 只处理圆(RZ 图层理论上只有热咀圆, 防用户手画其他实体)
      (if (= (vla-get-objectname o) "AcDbCircle")
        (progn
          (setq c (vlax-safearray->list (vlax-variant-value (vla-get-center o))))
          (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list obj c)))
          (if (and (not (vl-catch-all-error-p cp))
                   (< (distance c cp) 0.5)
                   (< (distance c pt) (distance c opt)))
            ;; 多个候选时取离端点最近者
            (if (or (null best) (< (distance c pt) (distance (nth 4 best) pt)))
              (setq best (list obj et pt opt c)))))))
    (if best
      (setq out (cons best out))
      (setq out (cons (list obj et pt opt nil) out))))
  (reverse out))

;; 端头帽形式判定(全部端头在此统一判定一次, 三层共用):
;; gap = 端头所在 LD 曲线与其他"不相交/T接"LD 曲线的最小轴线距 - 2×偏移值
;;   |gap - 偏移值| <= 1.0 且有匹配 RZ → "circle"(RZ 处整圆帽)
;;   gap > 偏移值 或 无相邻/无 RZ       → "line"(直线帽)
;;   gap < 偏移值 - 1.0                 → 告警 + "line"
;; 返回 ((obj 端类型 端点 另一端点 圆心 形式 gap 内向方向) ...)
(defun dt:jrt-decide (ld-vlas matched / plans rec obj et pt opt c inward gap d style
                      e-obj o)
  (setq plans nil)
  (foreach rec matched
    (setq obj (nth 0 rec) et (nth 1 rec) pt (nth 2 rec)
          opt (nth 3 rec) c (nth 4 rec))
    ;; 内向方向: 有 RZ 用"端点→圆心", 无 RZ 用"端点→另一端点"(指向通道内部)
    (setq inward (if c (dt:unit (mapcar '- c pt)) (dt:unit (mapcar '- opt pt))))
    ;; 相邻通道内壁间距
    (setq gap nil e-obj (vlax-vla-object->ename obj))
    (foreach o ld-vlas
      (if (not (equal (vlax-vla-object->ename o) e-obj))
        (if (not (dt:jrt-touch-p obj o))
          (setq d (dt:jrt-curve-dist obj o)
                gap (if gap (min gap d) d)))))
    (if gap (setq gap (- gap (* 2.0 *jrt-offset*))))
    ;; 判定
    (setq style "line")
    (cond
      ((and c gap (< (abs (- gap *jrt-offset*)) 1.0))
       (setq style "circle"))
      ((and c gap (< gap (- *jrt-offset* 1.0)))
       (princ (strcat "\n【端帽】警告: 端头(" (rtos (car pt) 2 1) "," (rtos (cadr pt) 2 1)
                      ") 相邻通道内壁间距 " (rtos gap 2 2) " 过近, 改用直线帽。")))
      ((and c gap)
       ;; gap > 偏移值: 正常直线帽
       )
      ((and c (null gap))
       (princ (strcat "\n【端帽】提示: 端头(" (rtos (car pt) 2 1) "," (rtos (cadr pt) 2 1)
                      ") 无相邻通道, 使用直线帽。")))
      (t
       (princ (strcat "\n【端帽】警告: 端头(" (rtos (car pt) 2 1) "," (rtos (cadr pt) 2 1)
                      ") 未匹配到 RZ 热咀圆, 使用直线帽。"))))
    (princ (strcat "\n【端帽】端头(" (rtos (car pt) 2 1) "," (rtos (cadr pt) 2 1) "): "
                   (if gap (strcat "相邻通道内壁间距 " (rtos gap 2 2)) "无相邻通道")
                   " → " (if (= style "circle") "RZ处整圆帽" "直线帽") "。"))
    (setq plans (cons (list obj et pt opt c style gap inward) plans)))
  (reverse plans))

;; 找端头的两条侧壁线(本层实体中, 端头点距 LD 端点≈半宽的线端)
;; 返回 ((obj 端类型 端头点) ...)
(defun dt:jrt-head-walls (ents pt hw / walls e obj sp ep)
  (setq walls nil)
  (foreach e ents
    (setq obj (vlax-ename->vla-object e))
    (if (= (vla-get-objectname obj) "AcDbLine")
      (progn
        (setq sp (vlax-curve-getstartpoint obj)
              ep (vlax-curve-getendpoint obj))
        (if (< (abs (- (distance sp pt) hw)) 0.6)
          (setq walls (cons (list obj "S" sp) walls)))
        (if (< (abs (- (distance ep pt) hw)) 0.6)
          (setq walls (cons (list obj "E" ep) walls))))))
  walls)

;; 圆帽: 在 RZ 圆心处画整圆 R=半宽(与两测线相切), 侧线端头修到切点
;; plan = (obj et pt opt c style gap inward)
(defun dt:jrt-cap-circle (plan ents hw / et pt c inward nrm walls wall wallpt
                          sign tang len ms new-c cnt)
  (setq et (nth 1 plan) pt (nth 2 plan)
        c (nth 4 plan) inward (nth 7 plan)
        nrm (list (- (cadr inward)) (car inward) 0.0)
        walls (dt:jrt-head-walls ents pt hw)
        cnt 0)
  (foreach wall walls
    (setq wallpt (nth 2 wall)
          sign (if (>= (apply '+ (mapcar '* (mapcar '- wallpt pt) nrm)) 0.0) 1.0 -1.0)
          tang (dt:pt+vec c nrm (* sign hw))
          len (vlax-curve-getdistatparam (car wall)
                (vlax-curve-getendparam (car wall))))
    ;; 切点必须在侧线当前长度内(侧线另一端要长于轴向距离)
    (if (> len (+ (distance pt c) 1.0))
      (progn (dt:set-endpoint (car wall) (cadr wall) tang) (setq cnt (1+ cnt)))
      (princ "\n【端帽】警告: 侧壁过短, 圆帽切点超出侧线, 该侧线未修剪。")))
  (setq ms (dt:ms)
        new-c (vla-addcircle ms (vlax-3d-point c) hw))
  (vla-put-layer new-c "JRT")
  cnt)

;; 直线帽(v9.6 重构): 封闭线与两条相接的偏移线圆弧衔接 ——
;;   - 封闭线圆角半径R >= 半宽(默认 29=29): 封闭线直接替换为一个圆弧:
;;     圆心 = 帽线中点沿通道向内偏半宽, 半径 = 半宽, 与两测线相切,
;;     半圆凸向端点平面, 侧线端头修到切点;
;;   - 封闭线圆角半径R < 半宽: 端点平面向内偏 inset 画直线封闭线,
;;     两端与测线解析法圆角(半径 = 封闭线圆角半径R), 侧线端头修到切点,
;;     裁掉端点平面方向多余段。
;; plan = (obj et pt opt c style gap inward)
(defun dt:jrt-cap-line (plan ents hw inset capr / et pt inward nrm walls wall
                        wallpt sign target cap-mid center tan1 tan2 p1 p2 ucap q1
                        q2 s1 s2 o1 o2 a1 a2 am ms ln arc sw rel tmp sq2 cnt pair)
  (setq et (nth 1 plan) pt (nth 2 plan)
        inward (nth 7 plan)
        nrm (list (- (cadr inward)) (car inward) 0.0)
        walls (dt:jrt-head-walls ents pt hw)
        cnt 0
        ms (dt:ms))
  (if (>= capr (- hw 0.01))
    ;; ===== 圆弧替换模式: 封闭线 = 一个与两测线相切的圆弧 =====
    (progn
      (setq cap-mid (dt:pt+vec pt inward inset)
            center  (dt:pt+vec cap-mid inward hw))
      (foreach wall walls
        (setq wallpt (nth 2 wall)
              sign (if (>= (apply '+ (mapcar '* (mapcar '- wallpt pt) nrm)) 0.0)
                     1.0 -1.0)
              target (dt:pt+vec center nrm (* sign hw)))
        (dt:set-endpoint (car wall) (cadr wall) target)
        (setq cnt (1+ cnt)))
      ;; 半圆弧: 两切点之间经过帽线中点(凸向端点平面)
      (setq tan1 (dt:pt+vec center nrm (- hw))
            tan2 (dt:pt+vec center nrm hw)
            a1 (angle (list (car center) (cadr center))
                      (list (car tan1) (cadr tan1)))
            a2 (angle (list (car center) (cadr center))
                      (list (car tan2) (cadr tan2)))
            am (angle (list (car center) (cadr center))
                      (list (car cap-mid) (cadr cap-mid)))
            sw (if (> a2 a1) (- a2 a1) (+ (- a2 a1) (* 2 pi)))
            rel (if (> am a1) (- am a1) (+ (- am a1) (* 2 pi))))
      (if (>= rel sw)
        (setq tmp a1 a1 a2 a2 tmp))
      (setq arc (vla-addarc ms (vlax-3d-point center) hw a1 a2))
      (vla-put-layer arc "JRT"))
    ;; ===== 直线 + 两端圆角模式 =====
    (progn
      (setq p1 (dt:pt+vec (dt:pt+vec pt inward inset) nrm (- hw))
            p2 (dt:pt+vec (dt:pt+vec pt inward inset) nrm hw)
            ucap (dt:unit (mapcar '- p2 p1)))
      ;; 侧线端头从端点平面修到圆角切点(角点沿通道向内 capr)
      (foreach wall walls
        (setq wallpt (nth 2 wall)
              sign (if (>= (apply '+ (mapcar '* (mapcar '- wallpt pt) nrm)) 0.0)
                     1.0 -1.0)
              target (dt:pt+vec (dt:pt+vec (dt:pt+vec pt inward inset)
                                           nrm (* sign hw))
                                inward capr))
        (dt:set-endpoint (car wall) (cadr wall) target)
        (setq cnt (1+ cnt)))
      (if (< capr 0.01)
        ;; 半径≈0: 直角直接相接
        (progn
          (setq ln (vla-addline ms (vlax-3d-point p1) (vlax-3d-point p2)))
          (vla-put-layer ln "JRT"))
        (progn
          (setq sq2 (* capr (sqrt 2.0))
                q1 (dt:pt+vec p1 ucap capr)
                q2 (dt:pt+vec p2 (mapcar '- ucap) capr)
                s1 (dt:pt+vec p1 inward capr)
                s2 (dt:pt+vec p2 inward capr)
                o1 (dt:pt+vec p1 (dt:unit (mapcar '+ ucap inward)) sq2)
                o2 (dt:pt+vec p2 (dt:unit (mapcar '- ucap inward)) sq2))
          ;; 直线封闭线只画到两切点之间
          (setq ln (vla-addline ms (vlax-3d-point q1) (vlax-3d-point q2)))
          (vla-put-layer ln "JRT")
          ;; 两端 90° 圆角弧(劣弧)
          (foreach pair (list (list o1 q1 s1) (list o2 q2 s2))
            (setq a1 (angle (list (car (car pair)) (cadr (car pair)))
                            (list (car (cadr pair)) (cadr (cadr pair))))
                  a2 (angle (list (car (car pair)) (cadr (car pair)))
                            (list (car (caddr pair)) (cadr (caddr pair)))))
            (if (> (if (> a2 a1) (- a2 a1) (+ (- a2 a1) (* 2 pi))) pi)
              (setq tmp a1 a1 a2 a2 tmp))
            (setq arc (vla-addarc ms (vlax-3d-point (car pair)) capr a1 a2))
            (vla-put-layer arc "JRT"))))))
  (if (< cnt 2)
    (princ (strcat "\n【端帽】警告: 端头(" (rtos (car pt) 2 1) "," (rtos (cadr pt) 2 1)
                   ") 只找到 " (itoa cnt) " 条侧壁, 帽线可能悬空。")))
  cnt)

;; 区域裁剪(dt:jrt-trim): 对本层实体做 LD ±hw 带状裁剪(逻辑同主脚本 trim-all,
;; 但对象限定在传入的 eName 列表, 三层互不干扰)
(defun dt:jrt-trim (ents hw / ld vla-list pts-pairs pair trim-count skip-count)
  (setq ld (dt:curves-only (dt:layer-vlas "LD")))
  (if (null ld)
    (princ "\n【裁剪】未找到\"LD\"图层, 无法确定流道区域, 跳过裁剪。")
    (progn
      (setq vla-list (mapcar 'vlax-ename->vla-object ents))
      (if (null vla-list)
        (princ "\n【裁剪】本层没有对象, 无需裁剪。")
        (progn
          (setq pts-pairs (dt:cross-points vla-list))
          (dt:jrt-undo-mark)
          (setq trim-count 0 skip-count 0)
          (foreach pair pts-pairs
            (if (dt:jrt-trim-curve (car pair) (cdr pair) ld hw "JRT")
              (setq trim-count (1+ trim-count))
              (setq skip-count (1+ skip-count))))
          (dt:jrt-undo-end)
          (princ (strcat "\n【裁剪】完成: 处理 " (itoa trim-count)
                         " 条线, 跳过 " (itoa skip-count) " 条。"))))))
  (princ))

;; 统一断口圆角(dt:jrt-fillet): 交汇断口与直线帽直角交汇一并处理
;; (端头重合配对后逐个圆角, r-start=本层圆角半径)
(defun dt:jrt-fillet (ents hw r / ld e obj-type vla-list heads pairs pair res
                      count-ok count-fail count-dec)
  (setq ld (dt:curves-only (dt:layer-vlas "LD")))
  (if (null ld)
    (princ "\n【圆角】未找到\"LD\"图层, 无法验证圆角方向, 跳过圆角处理。")
    (progn
      ;; 只对直线/弧/多段线收集端头(排除帽圆)
      (setq vla-list nil)
      (foreach e ents
        (setq obj-type (vla-get-objectname (vlax-ename->vla-object e)))
        (if (member obj-type '("AcDbLine" "AcDbArc"
                               "AcDbLWPolyline" "AcDbPolyline"))
          (setq vla-list (cons (vlax-ename->vla-object e) vla-list))))
      (setq vla-list (reverse vla-list))
      (if (null vla-list)
        (princ "\n【圆角】本层没有可圆角的线。")
        (progn
          (setq heads (dt:collect-heads vla-list nil)
                pairs (dt:pair-heads heads))
          (dt:jrt-undo-mark)
          (setq count-ok 0 count-fail 0 count-dec 0)
          (foreach pair pairs
            (setq res (dt:jrt-fillet-pair (car pair) (cadr pair) ld hw "JRT" r))
            (if res
              (progn
                (setq count-ok (1+ count-ok))
                (if (< (car res) r) (setq count-dec (1+ count-dec))))
              (setq count-fail (1+ count-fail))))
          (dt:jrt-undo-end)
          (princ (strcat "\n【圆角】发现 " (itoa (length pairs)) " 处断口: 成功 "
                         (itoa count-ok) " 处, 失败 " (itoa count-fail) " 处"
                         (if (> count-dec 0)
                           (strcat " (其中 " (itoa count-dec) " 处半径递减, 已标注)")
                           "")
                         "。"))))))
  (princ))

;; 零长线清理: 圆角恰好消化整条帽线时, 帽线两端切点重合留下零长残段
(defun dt:jrt-zero-clean (ents / e obj sp ep)
  (foreach e ents
    (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list e)))
    (if (not (vl-catch-all-error-p obj))
      (progn
        (if (= (vl-catch-all-apply 'vla-get-objectname (list obj)) "AcDbLine")
          (progn
            (setq sp (vl-catch-all-apply 'vla-get-startpoint (list obj))
                  ep (vl-catch-all-apply 'vla-get-endpoint (list obj)))
            (if (and (listp sp) (listp ep)
                     (< (distance sp ep) 1e-6))
              (vl-catch-all-apply 'vla-delete (list obj))))))))
  (princ))

;; 取当前模板行(下标越界回退第 1 个)
(defun dt:jrt-template-row ( / row)
  (setq row (nth *jrt-template* dt:jrt-template-table))
  (if row row (nth 0 dt:jrt-template-table)))

;; 环节覆盖分发(v9.8): 查当前模板覆盖表, 有覆盖则调覆盖函数, 否则调默认函数
;; stage = 'decide / 'cap-circle / 'cap-line / 'build
;; ('process 为 v9.9 新增的主流程环节, 不经本分发 —— 由 c:JRT 直接调用)
(defun dt:jrt-stage (stage default-fn args / ov)
  (setq ov (assoc stage (nth 3 (dt:jrt-template-row))))
  (apply (if ov (cdr ov) default-fn) args))

;; 单层构建: 偏移 → 裁剪 → 端帽 → 断口圆角 → 零长清理
;; plans 来自 decide 环节(各层共用同一端帽形式)
;; 返回 (圆帽数 直线帽数)
(defun dt:jrt-build (hw inset r capr plans / snap ents plan cnt-circle cnt-line)
  (setq snap (dt:jrt-snapshot "JRT"))
  ;; 1) 偏移 LD → JRT(半宽 hw)
  (dt:offset-layer "LD" "JRT" hw)
  (setq ents (dt:jrt-diff snap))
  ;; 2) 交汇区域裁剪(裁剪会删除重建对象 → 差集刷新实体列表)
  (dt:jrt-trim ents hw)
  (setq ents (dt:jrt-diff snap))
  ;; 3) 端帽(圆帽/直线帽, 按 decide 环节的判定; 先建帽线/帽圆再修侧壁端头)
  (dt:jrt-undo-mark)
  (setq cnt-circle 0 cnt-line 0)
  (foreach plan plans
    (if (= (nth 5 plan) "circle")
      (progn (dt:jrt-stage 'cap-circle 'dt:jrt-cap-circle (list plan ents hw))
             (setq cnt-circle (1+ cnt-circle)))
      (progn (dt:jrt-stage 'cap-line 'dt:jrt-cap-line (list plan ents hw inset capr))
             (setq cnt-line (1+ cnt-line)))))
  (dt:jrt-undo-end)
  ;; 4) 统一断口圆角(交汇断口 + 直线帽两端直角交汇)
  (setq ents (dt:jrt-diff snap))
  (dt:jrt-fillet ents hw r)
  ;; 5) 零长残段清理
  (dt:jrt-zero-clean (dt:jrt-diff snap))
  (princ (strcat "\n【加热条】半宽 " (rtos hw 2 1) " 层完成: 圆帽 "
                 (itoa cnt-circle) " 处, 直线帽 " (itoa cnt-line) " 处。"))
  (list cnt-circle cnt-line))

;; ============================================================================
;; 五.5、两点式模板(dt:jrt2-*, v9.9) —— 源线="JRT"图层曲线, 第 k 层把每段
;;      源线朝 "JRTDW"(加热条定位)实体方向偏 k×步长; 出线的每个"头"用一条
;;      直线把最外侧与最内侧端头连起来(中间层端头由线跨过)成闭环;
;;      无裁剪/端帽/圆角; 源线保留, 上一轮产物按句柄记忆重跑先删。
;; ============================================================================

;; obj 与组内任一曲线端点相接(<tol)?
(defun dt:jrt2-grp-touch (obj g tol / r p1 p2 o2)
  (setq p1 (vlax-curve-getstartpoint obj)
        p2 (vlax-curve-getendpoint obj)
        r nil)
  (foreach o2 g
    (if (not r)
      (if (or (< (distance p1 (vlax-curve-getstartpoint o2)) tol)
              (< (distance p1 (vlax-curve-getendpoint o2)) tol)
              (< (distance p2 (vlax-curve-getstartpoint o2)) tol)
              (< (distance p2 (vlax-curve-getendpoint o2)) tol))
        (setq r T))))
  r)

;; 源线按端点相接(<tol)并组成"条"(连通分量); 返回 (vla列表 ...) 的列表
(defun dt:jrt2-group (srcs tol / groups g hit1 hit2 obj)
  (foreach obj srcs
    (setq hit1 nil hit2 nil)
    (foreach g groups
      (if (dt:jrt2-grp-touch obj g tol)
        (if (null hit1) (setq hit1 g) (setq hit2 g))))
    (cond
      ((null hit1) (setq groups (cons (list obj) groups)))
      ((null hit2) (setq groups (cons (append hit1 (list obj))
                                      (vl-remove hit1 groups))))
      (T (setq groups (cons (append hit1 hit2 (list obj))
                            (vl-remove hit2 (vl-remove hit1 groups)))))))
  groups)

;; 单段源线 ±dist 各试偏一次, 返回成功创建的候选 vla 列表(0~2 个, 已置
;; layer 层; 选边由 dt:jrt2-layer 传播完成, 本函数不做方向判断)
(defun dt:jrt2-cands (obj dist layer / r lst v sgn)
  (setq lst nil)
  (foreach sgn (list dist (- dist))
    (setq r (vl-catch-all-apply 'vla-offset (list obj sgn)))
    (if (not (vl-catch-all-error-p r))
      (progn
        (setq v (car (vlax-safearray->list (vlax-variant-value r))))
        (vla-put-layer v layer)
        (setq lst (cons v lst)))))
  lst)

;; 曲线 3 个采样点到实体集(dw-vlas)的最小距离;
;; 采样点/最近点计算全部捕获异常 —— dw-vlas 里混入文字等无曲线实体时
;; getclosestpointto 会返回 nil, 跳过该实体而非崩掉(坑: 二维/三维点 nil)
(defun dt:jrt2-min-dist (obj dw-vlas / fr m cp d best dw)
  (setq best 1e99)
  (foreach fr '(0.25 0.5 0.75)
    (setq m (vl-catch-all-apply 'vlax-curve-getpointatparam
              (list obj (* (vlax-curve-getendparam obj) fr))))
    (if (not (vl-catch-all-error-p m))
      (foreach dw dw-vlas
        (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto
                   (list dw m)))
        (if (not (vl-catch-all-error-p cp))
          (progn
            (setq d (distance m cp))
            (if (< d best) (setq best d)))))))
  best)

;; 候选列表中取离 JRTDW 最近者
(defun dt:jrt2-pick-near (cands dw-vlas / best bd c d)
  (setq best nil bd 1e99)
  (foreach c cands
    (setq d (dt:jrt2-min-dist c dw-vlas))
    (if (< d bd) (setq bd d best c)))
  best)

;; 在 recs 中按 obj 取最新 rec(rec=(obj 候选列表 已选) )
(defun dt:jrt2-rec-of (recs obj / r rec)
  (foreach rec recs
    (if (and (not r) (equal (car rec) obj)) (setq r rec)))
  r)

;; 一条源线的单层内偏选边(v9.9):
;;   锚段 = 源线中离 JRTDW(加热条定位)最近的一段, 其候选取离 JRTDW 近的
;;   一侧(定位线画在哪, 哪侧就是内);
;;   其余段沿端点相接的轮廓链传播: 每段取"候选端头与已定邻段候选端头
;;   最近"的一侧 —— 切线接头处同侧候选端点精确重合(距离0), 尖角处同侧
;;   pair 的间距也必小于内外混搭, 传播结果与轮廓走向一致;
;;   传播不到的孤立段回退按距 JRTDW 距离选边。
;; 删除全部未选中候选, 返回选中 vla 对象列表(已置于 layer 层)
(defun dt:jrt2-layer (bar dist layer dw-vlas / recs anchor ad d best queue
                          curobj cur ch e-s e-e ref-pt obj2 rec2 s2 e2
                          cnb dnb out obj c pt rec)
  ;; 1) 生成候选(每段 ±dist)
  (setq recs nil)
  (foreach obj bar
    (setq recs (cons (list obj (dt:jrt2-cands obj dist layer) nil) recs)))
  ;; 2) 锚段(离 JRTDW 最近的源线段)按距 JRTDW 就近选边
  (setq anchor nil ad 1e99)
  (foreach rec recs
    (setq d (dt:jrt2-min-dist (car rec) dw-vlas))
    (if (< d ad)
      (setq ad d anchor rec)))
  (if anchor
    (progn
      (setq best (dt:jrt2-pick-near (cadr anchor) dw-vlas)
            recs (subst (list (car anchor) (cadr anchor) best) anchor recs)
            queue (list (car anchor)))
      ;; 3) 沿端点相接链传播选边
      (while queue
        (setq curobj (car queue)
              queue (cdr queue)
              cur (dt:jrt2-rec-of recs curobj)
              ch (nth 2 cur))
        (if ch
          (foreach pt (list (vlax-curve-getstartpoint curobj)
                            (vlax-curve-getendpoint curobj))
            ;; 已选候选在本端点侧的端头 = 传播参考点
            (setq e-s (vlax-curve-getstartpoint ch)
                  e-e (vlax-curve-getendpoint ch)
                  ref-pt (if (< (distance pt e-s) (distance pt e-e)) e-s e-e))
            (foreach obj2 (mapcar 'car recs)
              (setq rec2 (dt:jrt2-rec-of recs obj2))
              (if (and (not (nth 2 rec2))
                       (not (equal obj2 curobj)))
                (progn
                  (setq s2 (vlax-curve-getstartpoint obj2)
                        e2 (vlax-curve-getendpoint obj2))
                  (if (or (< (distance s2 pt) 0.5) (< (distance e2 pt) 0.5))
                    (progn
                      ;; 取其候选端头离参考点最近者
                      (setq cnb nil dnb 1e99)
                      (foreach c (nth 1 rec2)
                        (setq e-s (vlax-curve-getstartpoint c)
                              e-e (vlax-curve-getendpoint c)
                              d (min (distance ref-pt e-s)
                                     (distance ref-pt e-e)))
                        (if (< d dnb)
                          (setq dnb d cnb c)))
                      (if cnb
                        (progn
                          (setq recs (subst (list obj2 (nth 1 rec2) cnb)
                                            rec2 recs)
                                queue (append queue (list obj2)))))))))))))))
  ;; 4) 收集选中(孤立未达段回退按距 JRTDW 选边), 删除未选中候选
  (setq out nil)
  (foreach rec recs
    (setq ch (nth 2 rec))
    (if (null ch)
      (setq ch (dt:jrt2-pick-near (nth 1 rec) dw-vlas)))
    (if ch
      (setq out (cons ch out))
      (princ "\n【警告】两点式: 该段源线偏移失败, 已跳过。"))
    (foreach c (nth 1 rec)
      (if (not (equal c ch))
        (vl-catch-all-apply 'vla-delete (list c)))))
  out)

;; 收集曲线列表的自由端头: 端点在 tol 内无其他曲线端点与之重合(切线接头
;; 端点重合, 不计); 闭合曲线(首尾端点重合)不计端头。
;; 返回 ends 格式: (端点坐标 对象 "S"/"E") —— 端点格式勿混用(坑#31)
(defun dt:jrt2-free-ends (curves tol / pts out rec obj pt et ok o2)
  (setq pts nil)
  (foreach obj curves
    (if (>= (distance (vlax-curve-getstartpoint obj)
                      (vlax-curve-getendpoint obj)) tol)
      (foreach et '("S" "E")
        (setq pts (cons (list (if (= et "S")
                                (vlax-curve-getstartpoint obj)
                                (vlax-curve-getendpoint obj))
                              obj et)
                        pts)))))
  (setq out nil)
  (foreach rec pts
    (setq pt (car rec) ok T)
    (foreach o2 pts
      (if (and (not (equal (cadr o2) (cadr rec)))
               (< (distance pt (car o2)) tol))
        (setq ok nil)))
    (if ok (setq out (cons rec out))))
  out)

;; 破口封闭(v9.9 规则: 出线的每个"头"一条线): 源线(最外侧, k=0)的每个
;; 自由端头, 与最近的"最内层"(k=最大层号)自由端头连一条直线 —— 中间层
;; 端头由该线跨过, 不管一头有多少破口都只此一条; 贪心最近配对保证两头
;; 各连各的。ends=(端点 对象 端类型), kmap=((对象 . 层号k)); 返回新建封闭线
(defun dt:jrt2-close (ends kmap layer / rec e r k kmax srcs inns
                          s i d dd s1 i1 pairs p ln out)
  (setq rec nil)
  (foreach e ends
    (setq k (cdr (assoc (cadr e) kmap)))
    (setq rec (cons (list (car e) k) rec)))
  (setq kmax 0)
  (foreach r rec
    (if (> (cadr r) kmax) (setq kmax (cadr r))))
  (if (< kmax 1)
    (progn
      (princ "\n【通用二】无内向偏移层, 跳过破口封闭。")
      nil)
    (progn
      (setq srcs nil inns nil)
      (foreach r rec
        (cond ((= (cadr r) 0) (setq srcs (cons (car r) srcs)))
              ((= (cadr r) kmax) (setq inns (cons (car r) inns)))))
      ;; 贪心最近配对: 最外侧端头 ↔ 最内侧端头
      (setq pairs nil)
      (while (and srcs inns)
        (setq s nil i nil d 1e99)
        (foreach s1 srcs
          (foreach i1 inns
            (setq dd (distance s1 i1))
            (if (< dd d)
              (setq d dd s s1 i i1))))
        (if s
          (progn
            (setq pairs (cons (list s i) pairs)
                  srcs (vl-remove s srcs)
                  inns (vl-remove i inns)))))
      ;; 画封闭线
      (setq out nil)
      (foreach p pairs
        (setq ln (vla-addline (dt:ms)
                              (vlax-3d-point (car p)) (vlax-3d-point (cadr p))))
        (vla-put-layer ln layer)
        (setq out (cons ln out)))
      out)))

;; 两点式主流程(process 环节覆盖, c:JRT 内直接调用):
;;   1) JRT 层源线检查 + JRTDW 定位层检查(缺则中止)
;;   2) 按句柄记忆删除上一轮产物(只删仍在 JRT 层的; 源线永不删)
;;   3) 源线过滤(可偏移类型, 跳过零长线头)并按端点相接组成"条"
;;   4) 每条第 k 层(k=1..内向偏移次数)每段朝 JRTDW 偏 k×步长
;;   5) 每条收集全部自由端头(带层号)→ 每个头一条线连最外↔最内
;;   6) 记忆本轮产物句柄 + 统计输出
;; ---------------------------------------------------------------------------
;; 单线自动补边(v9.16, 按用户截图定稿): 用户只画 ①外壁整圈(JRT 层, 闭合轮廓;
;; 请用直线/圆弧/开放多段线, 勿用闭合多段线) ②JRTDW 定位短线(每处出线口一条,
;; 贴着外壁指向板边)。脚本自动完成旧手工三步:
;;   偏移 = JRTDW 朝两边偏 jrt2_half_w → 出线通道两壁线(JRT 层, 持久源线);
;;   裁剪 = 外壁在通道处开口(切口到过渡弧切点为止, 中间段删除);
;;   圆角 = 外壁断头↔通道线过渡弧 jrt2_end_r(任意夹角按 r/tan(α/2) 解析,
;;          直角即 R12, 与手画 FILLET 一致)。
;; 生成件(通道线/过渡弧/切口后壁段)为持久源线, 不入重跑清理表 —— 与手画
;; 产物同权, 之后走原嵌套引擎(嵌套/破口封闭/出线口颈线不变)。
;; 重跑幂等: 该定位短线处已有通道壁线(平行/垂直距≈halfw/有重叠)即跳过。
;; ---------------------------------------------------------------------------

;; 直线单侧偏移(返回偏移实体并放 layer; 失败 nil)
(defun dt:jrt2-offset-line (ln dist layer / r v)
  (setq r (vl-catch-all-apply 'vla-offset (list ln dist)))
  (if (vl-catch-all-error-p r)
    nil
    (progn
      (setq v (car (vlax-safearray->list (vlax-variant-value r))))
      (vla-put-layer v layer)
      v)))

;; 重跑幂等检查: 该定位短线处是否已有通道壁线 —— 源线中存在与 stub 平行
;; (|叉积|<1e-4)、垂直距 ≈ halfw(±0.5)的直线即视为已开过
(defun dt:jrt2-ch-exist (stub srcs halfw / sa ea d ul found s e v vl dd n)
  (setq sa (vlax-curve-getstartpoint stub)
        ea (vlax-curve-getendpoint stub)
        sa (list (nth 0 sa) (nth 1 sa) 0.0)
        ea (list (nth 0 ea) (nth 1 ea) 0.0)
        d  (list (- (nth 0 ea) (nth 0 sa)) (- (nth 1 ea) (nth 1 sa)) 0.0)
        ul (sqrt (+ (* (nth 0 d) (nth 0 d)) (* (nth 1 d) (nth 1 d))))
        found nil)
  (if (> ul 1e-8)
    (progn
      (setq d (list (/ (nth 0 d) ul) (/ (nth 1 d) ul) 0.0))
      (foreach s srcs
        (if (and (null found)
                 (= (vla-get-objectname s) "AcDbLine"))
          (progn
            (setq e (vlax-curve-getstartpoint s)
                  e (list (nth 0 e) (nth 1 e) 0.0)
                  v (vlax-curve-getendpoint s)
                  v (list (nth 0 v) (nth 1 v) 0.0)
                  v (list (- (nth 0 v) (nth 0 e)) (- (nth 1 v) (nth 1 e)) 0.0)
                  vl (sqrt (+ (* (nth 0 v) (nth 0 v)) (* (nth 1 v) (nth 1 v)))))
            (if (> vl 1e-8)
              (progn
                (setq v  (list (/ (nth 0 v) vl) (/ (nth 1 v) vl) 0.0)
                      dd (- (* (nth 0 d) (nth 1 v)) (* (nth 1 d) (nth 0 v))))
                (if (< (abs dd) 1e-4)
                  (progn
                    (setq n  (list (- (nth 0 e) (nth 0 sa)) (- (nth 1 e) (nth 1 sa)) 0.0)
                          dd (- (* (nth 0 n) (nth 1 d)) (* (nth 1 n) (nth 0 d))))
                    (if (< (abs (- (abs dd) halfw)) 0.5)
                      (setq found T))))))))))
  found)

;; 曲线与直线实体的交点列表(取该曲线一侧; 无交点 nil)
;; v9.17: dt:cross-points 每对为 (obj . pts) —— 交点列表用 cdr 取(此前误用
;; cadr 拿到首个交点裸点, foreach 对坐标数字求 distance 抛类型错误); 整体
;; 加 catch, 求交异常按"无交点"降级跳过
(defun dt:jrt2-line-x-curve (curve line / res pts)
  (setq res (vl-catch-all-apply 'dt:cross-points (list (list curve line)))
        pts (if (and res (not (vl-catch-all-error-p res)))
              (cdr (nth 0 res))))
  (if (and pts (not (listp (car pts)))) (setq pts (list pts)))
  (if (and pts (> (length pts) 0)) pts nil))

;; 曲线上 pt 处的单位切向(有限差分, 避开 getparamatpoint 浮点坑; 失败 nil)
(defun dt:jrt2-wall-tan (curve pt / dist p1 p2 v ul)
  (setq dist (vl-catch-all-apply 'vlax-curve-getdistatpoint (list curve pt)))
  (if (or (vl-catch-all-error-p dist) (null dist))
    nil
    (progn
      (setq p1 (vl-catch-all-apply 'vlax-curve-getpointatdist
                 (list curve (max 0.0 (- dist 0.01))))
            p2 (vl-catch-all-apply 'vlax-curve-getpointatdist
                 (list curve (+ dist 0.01)))
            v  (list (- (nth 0 p2) (nth 0 p1)) (- (nth 1 p2) (nth 1 p1)) 0.0)
            ul (sqrt (+ (* (nth 0 v) (nth 0 v)) (* (nth 1 v) (nth 1 v)))))
      (if (< ul 1e-9)
        nil
        (list (/ (nth 0 v) ul) (/ (nth 1 v) ul) 0.0)))))

;; 交点列表里取离指定点最近者
(defun dt:jrt2-near-pt (pts ref / best bd p dd)
  (setq best nil bd 1e99)
  (foreach p pts
    (setq dd (distance p ref))
    (if (< dd bd) (setq bd dd best p)))
  best)

;; 过渡弧(两相交直线在角点 p 的圆角, 解析法): w = 沿外壁远离开口的单位向量,
;; d = 沿定位线指向板边的单位向量。切点距 t = r/tan(α/2)(直角时 t=r),
;; 切点 T = p + t·w(壁上) / F = p + t·d(通道线上), 弧心 = T + n·r
;; (n = w 的垂直方向上指向 d 一侧)。返回 (弧 T F) 或 nil(两线近平行)。
(defun dt:jrt2-hook-arc (p w d r layer / ms dot n nl t-len tp fp c
                            a1 a2 sw tmp arc)
  (setq dot (+ (* (nth 0 d) (nth 0 w)) (* (nth 1 d) (nth 1 w))))
  (if (> (abs dot) 0.9999)
    (progn (princ "\n【通用二】出线口: 定位线与外壁近平行, 该处跳过。") nil)
    (progn
      (setq n  (list (- (nth 1 w)) (nth 0 w) 0.0)
            nl (sqrt (+ (* (nth 0 n) (nth 0 n)) (* (nth 1 n) (nth 1 n))))
            n  (list (/ (nth 0 n) nl) (/ (nth 1 n) nl) 0.0))
      (if (< (+ (* (nth 0 d) (nth 0 n)) (* (nth 1 d) (nth 1 n))) 0.0)
        (setq n (list (- (nth 0 n)) (- (nth 1 n)) 0.0)))
      (setq t-len (/ (* r (+ 1.0 dot))
                     (sqrt (- 1.0 (* dot dot))))
            tp (list (+ (nth 0 p) (* t-len (nth 0 w)))
                     (+ (nth 1 p) (* t-len (nth 1 w))) 0.0)
            fp (list (+ (nth 0 p) (* t-len (nth 0 d)))
                     (+ (nth 1 p) (* t-len (nth 1 d))) 0.0)
            c  (list (+ (nth 0 tp) (* r (nth 0 n)))
                     (+ (nth 1 tp) (* r (nth 1 n))) 0.0)
            a1 (angle '(0.0 0.0 0.0) (mapcar '- tp c))
            a2 (angle '(0.0 0.0 0.0) (mapcar '- fp c))
            sw (- a2 a1))
      (if (< sw 0.0) (setq sw (+ sw (* 2.0 pi))))
      (if (> sw pi) (setq tmp a1 a1 a2 a2 tmp))
      (setq ms  (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object)))
            arc (vla-addarc ms (vlax-3d-point c) r a1 a2))
      (vla-put-layer arc layer)
      (list arc tp fp))))

;; 把通道线裁到过渡弧切点: 保留 keepfrom → 远端(距 innerpt 较远的原端点),
;; 删原线返回新线(放 JRT 层)
(defun dt:jrt2-trim-line (line keepfrom innerpt / s e newobj)
  (setq s (vlax-curve-getstartpoint line)
        e (vlax-curve-getendpoint line)
        s (list (nth 0 s) (nth 1 s) 0.0)
        e (list (nth 0 e) (nth 1 e) 0.0)
        keepfrom (list (nth 0 keepfrom) (nth 1 keepfrom) 0.0))
  (if (> (distance s innerpt) (distance e innerpt))
    (setq e s))
  (vla-delete line)
  (setq newobj (vla-addline (dt:ms) (vlax-3d-point keepfrom) (vlax-3d-point e)))
  (vla-put-layer newobj "JRT")
  newobj)

;; 单条定位短线 → 在其外壁上开 S 形出线口。返回更新后的 srcs(失败原样)。
;; 流程: 通道线 = stub 朝两边偏 halfw → 找两线都穿过的外壁 → 角点/切向 →
;;       过渡弧×2 → 外壁在两切点间开口(保留段重建, 原线删) → 通道线裁到切点。
(defun dt:jrt2-hook-one (stub srcs halfw r / typ sa ea d ul ch1 ch2 wall pu pl
                            w1 w2 r1 r2 arc1 arc2 tu tl fp1 fp2 cutp pa pb pe
                            p1 p2 nch1 nch2 out)
  (setq typ (vla-get-objectname stub))
  (cond
    ((/= typ "AcDbLine")
     (princ "\n【通用二】出线口: JRTDW 定位线含非直线实体, 该处跳过。")
     srcs)
    ((dt:jrt2-ch-exist stub srcs halfw)
     srcs)
    (T
     (setq sa (vlax-curve-getstartpoint stub)
           ea (vlax-curve-getendpoint stub)
           sa (list (nth 0 sa) (nth 1 sa) 0.0)
           ea (list (nth 0 ea) (nth 1 ea) 0.0)
           d  (list (- (nth 0 ea) (nth 0 sa)) (- (nth 1 ea) (nth 1 sa)) 0.0)
           ul (sqrt (+ (* (nth 0 d) (nth 0 d)) (* (nth 1 d) (nth 1 d)))))
     (cond
       ((< ul 1e-8)
        (princ "\n【通用二】出线口: JRTDW 定位线零长, 跳过。")
        srcs)
       (T
        (setq d   (list (/ (nth 0 d) ul) (/ (nth 1 d) ul) 0.0)
              ch1 (dt:jrt2-offset-line stub halfw "JRT")
              ch2 (dt:jrt2-offset-line stub (- 0.0 halfw) "JRT"))
        (cond
          ((or (null ch1) (null ch2))
           (foreach o (append (if ch1 (list ch1) nil) (if ch2 (list ch2) nil))
             (vla-delete o))
           (princ "\n【通用二】出线口: 通道线偏移失败, 该处跳过。")
           srcs)
          (T
           (setq wall nil pu nil pl nil)
           (foreach s srcs
             (if (null wall)
               (progn
                 (setq pu (dt:jrt2-near-pt (dt:jrt2-line-x-curve s ch1) sa)
                       pl (dt:jrt2-near-pt (dt:jrt2-line-x-curve s ch2) sa))
                 (if (and pu pl) (setq wall s) (setq pu nil pl nil)))))
           (cond
             ((null wall)
              (foreach o (list ch1 ch2) (vla-delete o))
              (princ "\n【通用二】出线口: 通道线未与外壁相交(定位线未贴外壁或该处已开口), 跳过。")
              srcs)
             (T
              (setq w1 (dt:jrt2-wall-tan wall pu)
                    w2 (dt:jrt2-wall-tan wall pl))
              (cond
                ((or (null w1) (null w2))
                 (foreach o (list ch1 ch2) (vla-delete o))
                 (princ "\n【通用二】出线口: 外壁切向求解失败, 该处跳过。")
                 srcs)
                (T
                 ;; 切向取"背离另一条通道线"的方向
                 (if (< (+ (* (nth 0 (mapcar '- pu pl)) (nth 0 w1))
                           (* (nth 1 (mapcar '- pu pl)) (nth 1 w1))) 0.0)
                   (setq w1 (list (- (nth 0 w1)) (- (nth 1 w1)) 0.0)))
                 (if (< (+ (* (nth 0 (mapcar '- pl pu)) (nth 0 w2))
                           (* (nth 1 (mapcar '- pl pu)) (nth 1 w2))) 0.0)
                   (setq w2 (list (- (nth 0 w2)) (- (nth 1 w2)) 0.0)))
                 ;; d 取指向板边方向(定位线上远离外壁角点的一端)
                 (if (< (distance ea pu) (distance sa pu))
                   (setq d (list (- (nth 0 d)) (- (nth 1 d)) 0.0)))
                 (setq r1 (dt:jrt2-hook-arc pu w1 d r "JRT")
                       r2 (dt:jrt2-hook-arc pl w2 d r "JRT"))
                 (cond
                   ((or (null r1) (null r2))
                    (foreach o (append (if r1 (list (car r1)) nil)
                                       (if r2 (list (car r2)) nil)
                                       (list ch1 ch2))
                      (vla-delete o))
                    (princ "\n【通用二】出线口: 过渡弧生成失败, 半成品已清理, 该处跳过。")
                    srcs)
                   (T
                    (setq arc1 (car r1) tu (cadr r1) fp1 (caddr r1)
                          arc2 (car r2) tl (cadr r2) fp2 (caddr r2)
                          cutp (dt:cut-params wall (list tu tl))
                          pa   (nth 1 cutp)
                          pb   (nth 2 cutp)
                          pe   (last cutp))
                    (if (or (null pa) (null pb) (< (- pb pa) 1e-6))
                      (progn
                        (foreach o (list arc1 arc2 ch1 ch2) (vla-delete o))
                        (princ "\n【通用二】出线口: 开口区间异常, 该处跳过。")
                        srcs)
                      (progn
                        (if (> pa 1e-6)
                          (setq p1 (dt:rebuild-seg wall 0.0 pa "JRT")))
                        (if (> (- pe pb) 1e-6)
                          (setq p2 (dt:rebuild-seg wall pb pe "JRT")))
                        (vla-delete wall)
                        (setq nch1 (dt:jrt2-trim-line ch1 fp1 pu)
                              nch2 (dt:jrt2-trim-line ch2 fp2 pl))
                        (setq out (vl-remove wall srcs))
                        (if p1 (setq out (cons p1 out)))
                        (if p2 (setq out (cons p2 out)))
                        (setq out (append out (list arc1 arc2 nch1 nch2)))
                        (princ (strcat "\n【通用二】出线口已开: 通道偏移 ±"
                                       (rtos halfw 2 1) " + 过渡弧 R"
                                       (rtos r 2 1) "。"))
                        out))))))))))))))))

;; 出线口总控(v9.16): 对每条 JRTDW 直线定位短线, 在其外壁上开 S 形出线口。
;; 返回更新后的 srcs(生成件/切口段均为持久源线)。
(defun dt:jrt2-hooks (srcs dw-vlas / stub)
  (foreach stub dw-vlas
    (setq srcs (dt:jrt2-hook-one stub srcs *jrt2-half-w* *jrt2-end-r*)))
  srcs)

(defun dt:jrt2-process ( / doc layers srcs bars dw-all dw-vlas bar-made made ents
                           kmap neck-ents obj obj-type len ends clns h
                           nbar nlayers nclose k kmax d bar)
  ;; ---- 1) 源线与 JRTDW 定位层检查 ----
  (setq srcs (if (tblsearch "LAYER" "JRT") (dt:layer-vlas "JRT")))
  (if (null srcs)
    (princ "\n【提示】图层 \"JRT\" 上没有任何源线, 请先在 JRT 图层绘制加热条源线。")
    (progn
      (setq dw-all (if (tblsearch "LAYER" "JRTDW") (dt:layer-vlas "JRTDW"))
            dw-vlas nil)
      (foreach obj dw-all
        (if (member (vla-get-objectname obj)
                    '("AcDbLine" "AcDbLWPolyline" "AcDbPolyline"
                      "AcDbArc" "AcDbCircle" "AcDbEllipse" "AcDbSpline"))
          (setq dw-vlas (cons obj dw-vlas))))
      (if (null dw-vlas)
        (princ "\n【提示】图层 \"JRTDW\" 上没有可用的曲线实体 —— 两点式以 JRTDW(加热条定位)为向内基准, 请在该层画定位线(直线/弧等)再运行。")
        (progn
          (setq doc    (vla-get-activedocument (vlax-get-acad-object))
                layers (vla-get-layers doc))
          (dt:ensure-layer layers "JRT" 2 "黄色")
          ;; ---- 2) 删除上一轮产物(句柄记忆) ----
          (dt:jrt-undo-mark)
          (foreach h *jrt2-made*
            (if (handent h)
              (progn
                (setq obj (vlax-ename->vla-object (handent h)))
                (if (equal (vl-catch-all-apply 'vla-get-layer (list obj)) "JRT")
                  (vl-catch-all-apply 'vla-delete (list obj))))))
          (dt:jrt-undo-end)
          ;; ---- 3) 源线过滤并组成"条" ----
          (setq srcs nil)
          (foreach obj (dt:layer-vlas "JRT")
            (setq obj-type (vla-get-objectname obj))
            (if (member obj-type
                        '("AcDbLine" "AcDbLWPolyline" "AcDbPolyline"
                          "AcDbArc" "AcDbCircle" "AcDbEllipse" "AcDbSpline"))
              (progn
                (setq len (vlax-curve-getdistatparam
                            obj (vlax-curve-getendparam obj)))
                (if (> len 0.001)
                  (setq srcs (cons obj srcs))))
              (princ (strcat "\n【警告】JRT 层存在不可偏移类型("
                             obj-type "), 已跳过。"))))
          ;; v9.16 单线补边: 每条 JRTDW 定位短线处自动开 S 形出线口
          ;; (偏移通道线 + 外壁开口 + 过渡圆角; 生成件为持久源线, 重跑幂等)
          (setq srcs (dt:jrt2-hooks srcs dw-vlas))
          (setq bars (dt:jrt2-group srcs 0.5))
          (princ (strcat "\n【通用二】JRT 源线 " (itoa (length srcs))
                         " 段, 并为 " (itoa (length bars)) " 条。"))
          ;; ---- 4)+5) 逐条: 逐层内偏 + 破口封闭 ----
          (setq made nil kmap nil nbar 0 nlayers 0 nclose 0)
          (foreach bar bars
            (setq nbar (1+ nbar))
            (dt:jrt-undo-mark)
            (setq bar-made nil
                  k 1
                  kmax (max 0 (fix *jrt-inner-count*)))
            (while (<= k kmax)
              (setq d (* k *jrt-inner-step*))
              (if (> d 0.0)
                (progn
                  (setq ents (dt:jrt2-layer bar d "JRT" dw-vlas))
                  (if ents
                    (progn
                      (setq bar-made (append bar-made ents)
                            kmap (append (mapcar '(lambda (o) (cons o k)) ents)
                                         kmap))))
                  (setq nlayers (1+ nlayers))
                  (princ (strcat "\n【通用二】条 " (itoa nbar) " 第 " (itoa k)
                                 " 层(偏移 " (rtos d 2 2) "): 成功 "
                                 (itoa (length ents)) " / "
                                 (itoa (length bar)) " 段。")))
                (princ "\n【警告】向内偏移步长<=0, 忽略本层。"))
              (setq k (1+ k)))
            ;; 源线 = 最外侧(k=0); 每个头一条封闭线连最外↔最内
            (setq kmap (append (mapcar '(lambda (o) (cons o 0)) bar) kmap)
                  ends (dt:jrt2-free-ends (append bar bar-made) 0.5)
                  clns (dt:jrt2-close ends kmap "JRT")
                  bar-made (append bar-made clns)
                  made (append made bar-made)
                  nclose (+ nclose (length clns)))
            (princ (strcat "\n【通用二】条 " (itoa nbar) ": 破口封闭 "
                           (itoa (length clns)) " 条(两头各连最外↔最内)。"))
            (dt:jrt-undo-end))
          ;; ---- 5.5) 出线口: JRTDW×FLB 颈线(通用二) ----
          (setq neck-ents (dt:jrt2-neck dw-vlas))
          (if neck-ents
            (progn
              (setq made (append made neck-ents))
              (princ (strcat "\n【通用二】出线口已生成 "
                             (itoa (length neck-ents)) " 个对象(\"JT\"图层)。"))))
          ;; ---- 6) 记忆本轮产物句柄 + 统计 ----
          (setq *jrt2-made*
                 (mapcar '(lambda (o) (vla-get-handle o)) made))
          (princ (strcat "\n【完成】通用二加热条已生成 → \"JRT\"图层(黄色): "
                         (itoa nbar) " 条, 共 " (itoa nlayers) " 层 / "
                         (itoa (length made)) " 个对象, 破口封闭 "
                         (itoa nclose) " 条; 源线未改动。模板: "
                         (nth 0 (dt:jrt-template-row)) "。"))
          ))))
  (princ))

;; 两直线在公共端点处的圆角(解析法, v9.10 出线口用):
;; 圆心取两保留段方向(角点→各自另一端)的角平分线上, 切点回修两线,
;; 加劣弧; 半径放不下时按 1 递减(最低 1)。仅支持直线(弧段返回 nil)。
;; 返回圆弧 vla 对象(失败 nil)
(defun dt:jrt2-fillet2 (ln1 ln2 r layer / p1a p1b p2a p2b pc o1 o2 u1 u2
                            cosv ang2 ok r0 tt t1 t2 bis c a1 a2 dd arc pa pb)
  (setq p1a (vlax-curve-getstartpoint ln1)
        p1b (vlax-curve-getendpoint ln1)
        p2a (vlax-curve-getstartpoint ln2)
        p2b (vlax-curve-getendpoint ln2)
        pc nil)
  ;; 找公共端点(角点)
  (foreach pa (list p1a p1b)
    (foreach pb (list p2a p2b)
      (if (and (not pc) (< (distance pa pb) 0.01))
        (setq pc pa))))
  (if pc
    (progn
      (setq o1 (if (< (distance p1a pc) 0.01) p1b p1a)
            o2 (if (< (distance p2a pc) 0.01) p2b p2a)
            u1 (dt:unit (mapcar '- o1 pc))
            u2 (dt:unit (mapcar '- o2 pc))
            cosv (+ (* (car u1) (car u2)) (* (cadr u1) (cadr u2))))
      (if (< (abs cosv) 0.999)
        (progn
          (setq ang2 (/ (dt:acos cosv) 2.0)
                r0 r
                ok nil)
          ;; 半径递减: 切点不得超出线段
          (while (and (not ok) (>= r0 1.0))
            (setq tt (/ r0 (dt:tan ang2)))
            (if (and (<= tt (distance pc o1)) (<= tt (distance pc o2)))
              (setq ok T)
              (setq r0 (1- r0))))
          (if ok
            (progn
              (setq t1 (dt:pt+vec pc u1 tt)
                    t2 (dt:pt+vec pc u2 tt)
                    bis (dt:unit (mapcar '+ u1 u2))
                    c (dt:pt+vec pc bis (/ r0 (sin ang2)))
                    a1 (angle (list (car c) (cadr c)) (list (car t1) (cadr t1)))
                    a2 (angle (list (car c) (cadr c)) (list (car t2) (cadr t2)))
                    dd (- a2 a1))
              (if (< dd 0.0) (setq dd (+ dd (* 2.0 pi))))
              ;; 劣弧: 逆时针跨度超过半圆则反向画
              (if (> dd pi)
                (setq arc (vla-addarc (dt:ms) (vlax-3d-point c) r0 a2 a1))
                (setq arc (vla-addarc (dt:ms) (vlax-3d-point c) r0 a1 a2)))
              (vla-put-layer arc layer)
              ;; 两线端头回修到切点(弧向随保留段, 与 JRT 出线处一致)
              (dt:set-endpoint ln1 (if (< (distance p1a pc) 0.01) "S" "E") t1)
              (dt:set-endpoint ln2 (if (< (distance p2a pc) 0.01) "S" "E") t2)
              arc)))))))

;; 相交处圆角(v9.11 修正弧向): 颈壁与原 JT 线相交于 pt-x。切点:
;; 壁上 t1 = pt-x 沿 dirv(朝 cap/走廊内)走 tt; 原JT线保留段上
;; t2 = pt-x 沿其保留方向(远离走廊)走 tt; 圆心 = t1 + 法向*r。
;; 弧倒掉 pt-x 处尖角, 与 JRT 出线处圆弧同向。
;; wall/piece 均需为 LINE; 返回圆弧 vla(失败 nil)
(defun dt:jrt2-junction (wall pt-x pint dirv piece r layer /
                         w-s w-e w-cap p-s p-e p-o u1 u2 dotv ang2 ok r0 tt
                         t1 t2 n1 n c a1 a2 dd arc)
  (setq w-s (vlax-curve-getstartpoint wall)
        w-e (vlax-curve-getendpoint wall)
        w-cap (if (< (distance pint w-s) (distance pint w-e)) w-e w-s)
        u1  (dt:unit dirv)                        ; 壁上朝 cap/走廊内方向
        p-s (vlax-curve-getstartpoint piece)
        p-e (vlax-curve-getendpoint piece)
        p-o (if (> (distance pint p-s) (distance pint p-e)) p-s p-e)
        u2  (dt:unit (mapcar '- p-o pt-x))
        dotv (+ (* (car u1) (car u2)) (* (cadr u1) (cadr u2))))
  (cond
    ((>= (abs dotv) 0.999)
     (princ (strcat "\n【警告】出线口: 相交处两线近共线(dot=" (rtos dotv 2 3) "), 暂不圆角。"))
     nil)
    (T
     (setq ang2 (/ (dt:acos dotv) 2.0)
           ok nil
           r0 r)
     (while (and (not ok) (>= r0 1.0))
       (setq tt (/ r0 (dt:tan ang2)))
       (if (and (<= tt (distance pt-x w-cap))
                (<= tt (distance pt-x p-o)))
         (setq ok T)
         (setq r0 (1- r0))))
     (if (null ok)
       (progn
         (princ (strcat "\n【警告】出线口: 圆角R放不下(壁可用"
                        (rtos (distance pt-x w-cap) 2 1)
                        ", JT段可用" (rtos (distance pt-x p-o) 2 1) "), 暂不圆角。"))
         nil)
       (progn
         (setq t1 (dt:pt+vec pt-x u1 tt)
               t2 (dt:pt+vec pt-x u2 tt)
               n1 (list (- (cadr u1)) (car u1) 0.0)
               n  (if (> (+ (* (car n1) (car u2)) (* (cadr n1) (cadr u2))) 0.0)
                    n1
                    (list (- (car n1)) (- (cadr n1)) 0.0))
               c  (dt:pt+vec t1 n r0)
               a1 (angle (list (car c) (cadr c)) (list (car t1) (cadr t1)))
               a2 (angle (list (car c) (cadr c)) (list (car t2) (cadr t2)))
               dd (- a2 a1))
         (if (< dd 0.0) (setq dd (+ dd (* 2.0 pi))))
         ;; 劣弧: 逆时针跨度超过半圆则反向画
         (if (> dd pi)
           (setq arc (vla-addarc (dt:ms) (vlax-3d-point c) r0 a2 a1))
           (setq arc (vla-addarc (dt:ms) (vlax-3d-point c) r0 a1 a2)))
         (vla-put-layer arc layer)
         ;; 两线回修到切点(壁修靠 pint 侧端, JT线修 pt-x 侧端)
         (dt:set-endpoint wall (if (< (distance pint w-s) (distance pint w-e)) "S" "E") t1)
         (dt:set-endpoint piece
           (if (< (distance pt-x p-s) (distance pt-x p-e)) "S" "E") t2)
         arc)))))

;; 出线口(v9.10, 通用二): JRTDW 定位线一端与 FLB 相交, 从交点沿 JRTDW
;; 方向画颈线(JT 层, 长 jrt2-neck-len), ±jrt2-neck-off 偏移成两壁;
;; 远端画封闭线封口, 两角 R=jrt2-close-r 圆角; 两壁与原 JT 线相交处:
;; 裁掉走廊带内(距 JRTDW 轴线<neck-off)的原 JT 线段与壁伸入 JT 区域的
;; 多余段, 相交处 R=jrt2-trim-r 圆角(弧向随保留段, 与 JRT 出线处一致)。
;; 返回本功能新建对象 vla 列表
(defun dt:jrt2-neck (dw-vlas / out flb jt-snap dwc p-s p-e pint pt f2 cp
                          xpts far dirv r clen walls w ws we wf wends cl arc
                          e2 cutc wall-x pt-x fresh out-e pc partner rr p sgn wx)
  (setq out nil)
  (setq flb (if (tblsearch "LAYER" "FLB") (dt:layer-vlas "FLB")))
  (if (null flb)
    (princ "\n【提示】图层 \"FLB\" 不存在, 跳过出线口绘制。")
    (progn
      (setq jt-snap (dt:jrt-snapshot "JT"))   ; 原 JT 线快照(只裁这些)
      (dt:jrt-undo-mark)
      (foreach dwc dw-vlas
        (setq p-s (vlax-curve-getstartpoint dwc)
              p-e (vlax-curve-getendpoint dwc)
              pint nil)
        ;; 相交点 = JRTDW 端头落在 FLB 上(容差 0.5)
        (foreach pt (list p-s p-e)
          (if (null pint)
            (foreach f2 flb
              (if (null pint)
                (progn
                  (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto
                             (list f2 pt)))
                  (if (and (not (vl-catch-all-error-p cp))
                           (< (distance pt cp) 0.5))
                    (setq pint pt)))))))
        ;; 兜底: 与 FLB 实际求交
        (if (null pint)
          (foreach f2 flb
            (if (null pint)
              (progn
                (setq xpts (dt:inters-pts dwc f2))
                (if xpts (setq pint (car xpts)))))))
        (if pint
          (progn
            (setq far (if (< (distance pint p-s) (distance pint p-e))
                        p-e p-s)
                  dirv (dt:unit (mapcar '- far pint)))
            ;; 1) 颈线(构图线, JT 层): 偏移出两壁后即删除不保留
            (setq clen (vla-addline (dt:ms)
                         (vlax-3d-point pint)
                         (vlax-3d-point (dt:pt+vec pint dirv *jrt2-neck-len*))))
            (vla-put-layer clen "JT")
            ;; 2) 两壁(±jrt2-neck-off)
            (setq walls nil)
            (foreach sgn (list *jrt2-neck-off* (- *jrt2-neck-off*))
              (setq r (vl-catch-all-apply 'vla-offset (list clen sgn)))
              (if (not (vl-catch-all-error-p r))
                (progn
                  (setq w (car (vlax-safearray->list (vlax-variant-value r))))
                  (vla-put-layer w "JT")
                  (setq out (cons w out)
                        walls (cons w walls)))))
            (vl-catch-all-apply 'vla-delete (list clen))
            (if (< (length walls) 2)
              (princ "\n【警告】出线口: 颈线偏移失败, 跳过该出线口。")
              (progn
                ;; 3) 远端封闭线(两壁离交点较远的端头相连)
                (setq wends nil)
                (foreach w walls
                  (setq ws (vlax-curve-getstartpoint w)
                        we (vlax-curve-getendpoint w)
                        wf (if (< (distance pint ws) (distance pint we))
                             we ws))
                  (setq wends (cons wf wends)))
                (setq cl (vla-addline (dt:ms)
                           (vlax-3d-point (car wends))
                           (vlax-3d-point (cadr wends))))
                (vla-put-layer cl "JT")
                (setq out (cons cl out))
                ;; 4) 封口两角 R=jrt2-close-r
                (foreach w walls
                  (setq arc (dt:jrt2-fillet2 w cl *jrt2-close-r* "JT"))
                  (if arc (setq out (cons arc out))))
                ;; 5) 各壁与原 JT 线的第一交点(裁剪前计算)
                ;;    注意: dt:jrt-snapshot 返回的是图元名 ename 而非句柄
                (setq wall-x nil)
                (foreach w walls
                  (setq xpts nil)
                  (foreach e2 jt-snap
                    (setq cutc (vlax-ename->vla-object e2))
                    (setq xpts (append xpts (dt:inters-pts w cutc))))
                  (if xpts
                    (progn
                      (setq pt-x (car xpts))
                      (foreach p xpts
                        (if (< (distance p pint) (distance pt-x pint))
                          (setq pt-x p)))
                      (setq wall-x (cons (list w pt-x) wall-x)))))
                ;; 6) 裁掉走廊带内(距 JRTDW 轴线<neck-off)的原 JT 线段
                ;;    逐条保护: 一条裁剪失败只跳过该条并打印原因
                (foreach e2 jt-snap
                  (setq cutc (vlax-ename->vla-object e2))
                  (setq xpts (append (dt:inters-pts cutc (nth 0 walls))
                                     (dt:inters-pts cutc (nth 1 walls))))
                  (if xpts
                    (progn
                      (setq rr (vl-catch-all-apply 'dt:jrt-cut-curve
                                 (list cutc xpts "JT" dw-vlas *jrt2-neck-off* "TRIM")))
                      (if (vl-catch-all-error-p rr)
                        (princ (strcat "\n【警告】出线口: 一条 JT 线裁剪失败已跳过: "
                                       (vl-catch-all-error-message rr)))))))
                ;; 7) 相交处 R=jrt2-trim-r 圆角(壁裁 pint 侧至切点, 弧向随
                ;;    保留段, 与 JRT 出线处一致)
                (setq out-e (mapcar 'vlax-vla-object->ename out))
                (foreach wx wall-x
                  (setq w (car wx)
                        pt-x (cadr wx)
                        fresh (dt:jrt-snapshot "JT")
                        partner nil)
                  (foreach e2 fresh
                    (if (and (not partner)
                             (not (member e2 out-e)))
                      (progn
                        (setq pc (vlax-ename->vla-object e2))
                        (if (and (= (vla-get-objectname pc) "AcDbLine")
                                 (or (< (distance (vlax-curve-getstartpoint pc) pt-x) 0.01)
                                     (< (distance (vlax-curve-getendpoint pc) pt-x) 0.01)))
                          (setq partner pc)))))
                  (if partner
                    (progn
                      (setq rr (vl-catch-all-apply 'dt:jrt2-junction
                                 (list w pt-x pint dirv partner *jrt2-trim-r* "JT")))
                      (if (vl-catch-all-error-p rr)
                        (princ "\n【警告】出线口: 相交处圆角失败, 暂不圆角。")
                        (progn
                          (setq arc rr
                                out (cons arc out)
                                out-e (cons (vlax-vla-object->ename arc) out-e)))))
                    (princ "\n【警告】出线口: 相交处为弧段或未找到相接段, 暂不圆角。"))))))))
      (if (null out)
        (princ "\n【提示】JRTDW 与 FLB 无相交点, 跳过出线口绘制。"))
      (dt:jrt-undo-end)
      out)))

;; ============================================================================
;; 六、参数对话框(结构与主脚本一致, 回调/文件名改名隔离)
;; ============================================================================

;; 参数键 → 中文标签(参数框 edit_box 标签; 动态生成与命令行汇总共用)
(setq dt:jrt-param-labels
      '(("jrt_offset"      . "流道线偏移距离:")
        ("jrt_cap_inset"   . "封闭线内偏移距离:")
        ("jrt_fillet_r"    . "圆角半径R:")
        ("jrt_cap_r"       . "封闭线圆角半径R:")
        ("jrt_inner_step"  . "向内偏移步长:")
        ("jrt_inner_count" . "内向偏移次数:")
        ("jrt2_neck_len"   . "出线颈线长度:")
        ("jrt2_neck_off"   . "出线颈线偏移:")
        ("jrt2_close_r"    . "出线封口圆角R:")
        ("jrt2_trim_r"     . "出线相交圆角R:")
        ("jrt2_half_w"     . "出线口通道半宽:")
        ("jrt2_end_r"      . "出线口过渡圆角R:")))

;; 当前模板用到的参数键列表(= 模板参数默认表的键序; v9.9 起参数框动态化)
(defun dt:jrt-tpl-keys ( / )
  (mapcar 'car (nth 2 (dt:jrt-template-row))))

;; 内置 DCL 源文本(外部 jrt_runner.dcl 不存在时自动生成, 总是覆盖保证同步)
;; 参数框 edit_box 按当前模板的参数键动态生成(两个一行; 通用一 6 项/通用二 8 项)
(defun dt:jrt-dcl-lines ( / keys lines row k1 k2)
  (setq keys (dt:jrt-tpl-keys) lines nil)
  (while keys
    (setq k1 (car keys)
          k2 (cadr keys)
          row (list "    : row {"
                    (strcat "      : edit_box { key = \"" k1
                            "\"; label = \"" (cdr (assoc k1 dt:jrt-param-labels))
                            "\"; edit_width = 10; }")))
    (if k2
      (setq row (append row
        (list (strcat "      : edit_box { key = \"" k2
                      "\"; label = \"" (cdr (assoc k2 dt:jrt-param-labels))
                      "\"; edit_width = 10; }")))
            keys (cddr keys))
      (setq keys nil))
    (setq lines (append lines row (list "    }"))))
  (append
    (list
      "jrt_param : dialog {"
      "  label = \"加热条参数设置\";"
      "  : text { key = \"tpl_name\"; label = \"当前模板\"; width = 40; }"
      "  : boxed_column {"
      "    label = \"加热条参数\";")
    lines
    (list
      "  }"
      "  : row {"
      "    : button { key = \"reset\"; label = \"恢复默认\"; width = 10; }"
      "    spacer;"
      "    ok_button;"
      "    cancel_button;"
      "  }"
      "}")))

;; 模板选择框 DCL 源文本(v9.8, 由注册表动态生成 radio_button 列表)
(defun dt:jrt-template-dcl-lines ( / lines i tpl)
  (setq lines (list "jrt_template_select : dialog {"
                    "  label = \"选择加热条模板\";"
                    "  : boxed_radio_column {"
                    "    label = \"模板\";")
        i 0)
  (foreach tpl dt:jrt-template-table
    (setq lines (append lines
      (list (strcat "    : radio_button { key = \"tpl" (itoa i)
                    "\"; label = \"" (nth 0 tpl) " — " (nth 1 tpl) "\"; }")))
          i (1+ i)))
  (append lines
    (list "  }"
          "  : row {"
          "    spacer; ok_button; cancel_button;"
          "  }"
          "}")))

;; 把内置 DCL 源文本写入文件 path(参数框 + 模板选择框两个对话框)
(defun dt:jrt-write-dcl (path / f ln)
  (setq f (open path "w"))
  (if f
    (progn
      ;; v9.14: 写中途异常也保证 close(半截 dcl 由对话框链的 catch 提示)
      (vl-catch-all-apply
        '(lambda ( )
           (foreach ln (append (dt:jrt-dcl-lines) (list "") (dt:jrt-template-dcl-lines))
             (write-line ln f)))
        nil)
      (close f)
      path)
    nil))

;; 查找对话框文件路径: **确定性目录**——优先 dt_start 引导器注入的
;; *dt-script-dir*(vl-propagate 全文档可见), 无 dt_start 时写系统 TEMP。
;; v9.11b 重写: 删除旧 findfile 候选链(v95~v98 文件名均已不存在)——多副本
;; 环境下 findfile 会命中支持路径里其它目录的同名旧副本, 与 offset/slot 统一。
;; 总是用内置源覆盖生成最新 dcl(界面参数永远与脚本同步)。
(defun dt:jrt-find-dcl ( / )
  (if (and *dt-script-dir* (/= *dt-script-dir* ""))
    (dt:jrt-write-dcl (strcat *dt-script-dir* "\\jrt_runner.dcl"))
    (dt:jrt-write-dcl (strcat (getenv "TEMP") "\\jrt_runner_tmp.dcl"))))

;; 读取编辑框数值: 空/非法输入时返回默认值 def
;; v9.13: atof 对垃圾串静默返回 0(如 "abc" -> 0.0), 参数会被悄悄改成 0;
;;        改用 distof —— 非法输入返回 nil 可识别, 回退默认值(坑 #54)
(defun dt:jrt-get-num (key def / s v)
  (setq s (get_tile key)
        v (if (and s (/= s "")) (distof s) nil))
  (if v v def))

;; 恢复默认参数到对话框(恢复默认按钮回调; 只刷当前模板的键 —— 控件按
;; 模板动态生成, 键不存在 set_tile 会报错);
;; v9.12 = 恢复 ini 配置默认值(先重读配置, 改 ini 后点恢复默认立即生效)
(defun dt:jrt-param-reset ( / val p)
  (setq *jrt-cfg* (dt:jrt-cfg-read (strcat (dt:jrt-cfg-dir) "\\jrt_runner.ini")))
  (foreach p dt:jrt-param-table
    (if (member (car p) (dt:jrt-tpl-keys))
      (progn
        (setq val (dt:jrt-param-default (car p)))
        (set_tile (car p) (rtos val 2 2))))))

;; 应用对话框值到全局参数(确定按钮回调; 空/非法输入回退当前值;
;; 只读当前模板的键, 其余参数保持不变);
;; v9.12: 应用后自动保存记忆(取消不触发本回调, 天然"确定才记忆")
(defun dt:jrt-param-apply ( / p v)
  (foreach p dt:jrt-param-table
    (if (member (car p) (dt:jrt-tpl-keys))
      (progn
        (setq v (dt:jrt-get-num (car p) (eval (cadr p))))
        ;; v9.14: 负值校验 —— 距离/半径类参数 <0 回退当前值(负值会画出退化几何)
        (if (< v 0.0) (setq v (eval (cadr p))))
        (set (cadr p) v))))
  (dt:jrt-mem-save))

;; 弹出参数对话框
;; 返回: T=用户点"确定"(参数已应用到全局变量), nil=取消/加载失败
(defun dt:jrt-param-dialog ( / dcl-file dcl-id result p)
  (setq *jrt-cfg* (dt:jrt-cfg-read (strcat (dt:jrt-cfg-dir) "\\jrt_runner.ini")))
  (setq dcl-file (dt:jrt-find-dcl))
  (if (null dcl-file)
    (progn
      (princ "\n【界面】无法生成对话框文件(磁盘权限不足?), 界面不可用。")
      nil)
    (progn
      ;; v9.14: load_dialog 对损坏 dcl 是抛错而非返回 nil, 包 catch;
      ;;   start_dialog 同理 —— 保证 unload_dialog 必被执行
      (setq dcl-id (vl-catch-all-apply 'load_dialog (list dcl-file)))
      (if (or (vl-catch-all-error-p dcl-id) (null dcl-id))
        (progn
          (princ "\n【界面】对话框文件加载失败。")
          nil)
        (progn
          (if (new_dialog "jrt_param" dcl-id)
            (progn
              (set_tile "tpl_name"
                        (strcat "当前模板: " (nth 0 (dt:jrt-template-row))))
              (foreach p dt:jrt-param-table
                (if (member (car p) (dt:jrt-tpl-keys))
                  (set_tile (car p) (rtos (eval (cadr p)) 2 2))))
              (action_tile "reset" "(dt:jrt-param-reset)")
              (action_tile "accept" "(dt:jrt-param-apply)(done_dialog 1)")
              (action_tile "cancel" "(done_dialog 0)")
              (setq result (vl-catch-all-apply 'start_dialog nil))
              (unload_dialog dcl-id)
              (if (and (not (vl-catch-all-error-p result)) (= result 1)) T nil))
            (progn
              (unload_dialog dcl-id)
              (princ "\n【界面】对话框初始化失败。")
              nil)))))))

;; 采用指定模板: 设当前下标并把参数写入全局变量;
;; v9.12 值来源优先级: 该模板记忆值 → ini 配置节 → 模板内置默认表 → 表 caddr
;; quiet=T 静默(加载时恢复用), nil 打印(模板框切换用)
(defun dt:jrt-apply-template (idx quiet / tpl params p v)
  (setq *jrt-template* idx
        tpl (nth idx dt:jrt-template-table)
        params (nth 2 tpl))
  (foreach p dt:jrt-param-table
    (setq v (cond ((cdr (assoc (car p) (dt:jrt-cfg-sec *jrt-mem* (car tpl)))))
                  ((dt:jrt-cfg-get *jrt-cfg* (car tpl) (car p)))
                  ((cdr (assoc (car p) params)))
                  (T (caddr p))))
    (set (cadr p) v))
  (if (null quiet)
    (princ (strcat "\n【模板】已选择 \"" (nth 0 tpl) "\": " (nth 1 tpl) "。")))
  (princ))

;; 独立模板选择框(v9.8): 单选模板 → 确定=采用该模板, 取消=nil(中止流程)
;; v9.12: 打开前重读 ini 配置(改配置后切模板立即用新默认)
(defun dt:jrt-template-dialog ( / dcl-file dcl-id result idx tpl)
  (setq *jrt-cfg* (dt:jrt-cfg-read (strcat (dt:jrt-cfg-dir) "\\jrt_runner.ini")))
  (setq dcl-file (dt:jrt-find-dcl))
  (if (null dcl-file)
    (progn
      (princ "\n【模板】无法生成对话框文件(磁盘权限不足?), 界面不可用。")
      nil)
    (progn
      ;; v9.14: load_dialog 对损坏 dcl 是抛错而非返回 nil, 包 catch
      (setq dcl-id (vl-catch-all-apply 'load_dialog (list dcl-file)))
      (if (or (vl-catch-all-error-p dcl-id) (null dcl-id))
        (progn
          (princ "\n【模板】对话框文件加载失败。")
          nil)
        (progn
          (if (new_dialog "jrt_template_select" dcl-id)
            (progn
              ;; 预选当前模板; 单选回调记录到 *jrt-tpl-pick*
              (setq *jrt-tpl-pick* *jrt-template*)
              (set_tile (strcat "tpl" (itoa *jrt-template*)) "1")
              (setq idx 0)
              (foreach tpl dt:jrt-template-table
                (action_tile (strcat "tpl" (itoa idx))
                             (strcat "(setq *jrt-tpl-pick* " (itoa idx) ")"))
                (setq idx (1+ idx)))
              (action_tile "accept" "(done_dialog 1)")
              (action_tile "cancel" "(done_dialog 0)")
              (setq result (vl-catch-all-apply 'start_dialog nil))
              (unload_dialog dcl-id)
              (if (and (not (vl-catch-all-error-p result)) (= result 1))
                (progn (dt:jrt-apply-template *jrt-tpl-pick* nil) T)
                nil))
            (progn
              (unload_dialog dcl-id)
              (princ "\n【模板】对话框初始化失败。")
              nil)))))))

;; 命令 JRTPARAM: 弹出参数设置对话框(只修改参数, 不执行);
;; 汇总按当前模板的参数键输出(v9.9 动态)
(defun c:JRTPARAM ( / p txt)
  (if (dt:jrt-param-dialog)
    (progn
      (setq txt (strcat "\n参数已保存(模板: " (nth 0 (dt:jrt-template-row)) "):"))
      (foreach p (dt:jrt-tpl-keys)
        (setq txt (strcat txt " " (cdr (assoc p dt:jrt-param-labels)) " "
                          (rtos (eval (cadr (assoc p dt:jrt-param-table))) 2 2))))
      (princ (strcat txt "。")))
    (princ "\n已取消, 参数未修改。"))
  (princ))

;; ============================================================================
;; 七、主命令 c:JRT —— 在命令行输入 JRT 即可执行
;; ============================================================================
(defun c:JRT ( / *error* doc layers ld rz plans matched total k kmax hw inset r capr proc)

  ;; ---- 内部错误处理: 出错或按 ESC 中断时给出友好提示 ----
  ;; v9.14: 兜底闭合可能悬挂的 UNDO 组(无开放组时无副作用, catch 双保险)
  (defun *error* (msg)
    ;; v9.17 坑 #69: *error* 内禁止 (command) —— 改用 COM 撤销标记收尾
    (dt:jrt-undo-end)
    (princ (strcat "\n程序已停止: " (if msg msg "用户按 ESC 取消")))
    (princ)
  )

  ;; v9.18: 会话版本守卫 —— 旧会话/半加载缺少出线口函数时明确提示并中止
  ;; (不再让运行期抛 no function definition)
  (if (null dt:jrt2-hook-one)
    (progn
      (princ "\n【错误】当前会话的 jrt_runner 为旧版本或不完整(缺少出线口函数)。")
      (princ "\n【错误】请完全关闭 AutoCAD 所有窗口后重新打开, 再运行本命令。"))
    (if (null (dt:jrt-template-dialog))
      (princ "\n已取消(未选模板), 未执行加热条绘制。")
    (if (null (dt:jrt-param-dialog))
      (princ "\n已取消, 未执行加热条绘制。")
      (if (setq proc (cdr (assoc 'process (nth 3 (dt:jrt-template-row)))))
        ;; 模板自管主流程(当前为 "通用二", v9.9 引入): 源图层检查/清理旧产物/偏移/
        ;; 封口/统计全部在覆盖函数内完成, 不走下方内置 LD 流程
        (apply proc nil)
        (progn
      ;; 第 1 步: 检查源图层
      (if (null (tblsearch "LAYER" "LD"))
        (princ "\n【提示】图层 \"LD\" 不存在, 请先绘制流道中心线(LD 图层)或运行 OFF 后重试。")
        (progn
          (setq ld (dt:curves-only (dt:layer-vlas "LD")))
          (if (null ld)
            (princ "\n【提示】图层 \"LD\" 上没有任何对象, 无法绘制加热条。")
            (progn
              ;; 第 2 步: 建层 + 清理上一轮产物
              (setq doc    (vla-get-activedocument (vlax-get-acad-object))
                    layers (vla-get-layers doc))
              (dt:ensure-layer layers "JRT" 2 "黄色")
              (dt:jrt-undo-mark)
              (setq total (dt:purge-layer "JRT"))
              (dt:jrt-undo-end)
              (princ (strcat "\n已清理上一轮产物 " (itoa total)
                             " 个对象(\"JRT\"图层)。"))
              ;; 第 3 步: RZ 热咀圆检查(圆帽依赖; 缺失则全部直线帽)
              (setq rz (dt:layer-vlas "RZ"))
              (if (null rz)
                (princ "\n【警告】未找到 \"RZ\" 图层(请先运行 OFF), 全部端头将使用直线帽。")
                (princ (strcat "\n找到 \"RZ\" 热咀圆 " (itoa (length rz)) " 个。")))
              ;; 第 4 步: 端头收集 + RZ 匹配 + 帽形式判定(decide 环节,
              ;;          各层共用; 模板可覆盖判定规则)
              (setq matched (dt:jrt-match-rz (dt:jrt-free-ends ld) rz))
              (setq plans (dt:jrt-stage 'decide 'dt:jrt-decide (list ld matched)))
              ;; 第 5 步: 多层完整轮廓(外层 + 内向偏移 inner-count 次, 每次收 inner-step)
              (setq kmax 0)
              (if (> *jrt-inner-step* 0.0)
                (setq kmax (min (max 0 (fix *jrt-inner-count*))
                                (fix (/ (- *jrt-offset* 1.0) *jrt-inner-step*))))
                (if (> (fix *jrt-inner-count*) 0)
                  (princ "\n【警告】向内偏移步长<=0, 忽略内向偏移次数。")))
              (setq k 0)
              (while (<= k kmax)
                (setq hw    (- *jrt-offset* (* k *jrt-inner-step*))
                      inset (+ *jrt-cap-inset* (* k *jrt-inner-step*))
                      ;; 内层圆角逐层 +步长: 与外层交汇肩部圆弧同心嵌套(19→23→27)
                      r     (max 1.0 (+ *jrt-fillet-r* (* k *jrt-inner-step*)))
                      capr  (+ *jrt-cap-r* (* k *jrt-inner-step*)))
                (dt:jrt-stage 'build 'dt:jrt-build (list hw inset r capr plans))
                (setq k (1+ k)))
              (if (< kmax (max 0 (fix *jrt-inner-count*)))
                (princ "\n【提示】部分内层因半宽过小未生成。"))
              ;; 第 6 步: 统计输出
              (princ (strcat "\n【完成】加热条半成品已生成 → \"JRT\"图层(黄色)。"
                             "共 " (itoa (1+ kmax)) " 层完整轮廓, LD 源线未改动。"
                             "模板: " (nth 0 (dt:jrt-template-row)) "。"))
            )
          )
        )
      )
    )
      )
    )
  ))
  (princ)  ; 静默退出, 不打印返回结果
)
;;; 加载时在命令行输出提示
(dt:jrt-cfg-boot)
;; v9.19: 加载完整性自检(atoms-family 检测函数定义, 打印缺失名单供定位根因)
;; 同时校验"只存在于文件后半部分"的函数 —— 半加载的特征正是后半缺失
(setq *jrt-load-check* nil)
(foreach f '(dt:jrt2-hooks dt:jrt2-hook-one dt:jrt2-process dt:jrt2-neck
             dt:jrt2-close dt:jrt-param-dialog dt:jrt-cfg-boot)
  (if (not (member f (atoms-family 1)))
    (setq *jrt-load-check* (cons (vl-symbol-name f) *jrt-load-check*))))
(if *jrt-load-check*
  (progn
    (princ "\n【严重】jrt_runner 加载不完整, 缺失函数:")
    (foreach nm *jrt-load-check*
      (princ (strcat " " nm)))
    (princ "\n【严重】请完全关闭 AutoCAD 所有窗口后重新打开, 勿仅 DTRELOAD!")))
(princ "\n加热条自动绘制工具 v9.19 已加载(多模板: 通用一/通用二; 参数默认值外置 jrt_runner.ini 可记事本修改, 上次值自动记忆)。")
(princ "\n用法1: 输入 JRT → 先选模板再确认参数后执行(通用一需 OFF 的 RZ; 通用二画外壁整圈 + JRTDW 定位短线即可, 出线口自动开出; 需 FLB)。")
(princ "\n用法2: 输入 JRTPARAM 弹出参数设置对话框(只改参数不执行)。")
(princ)
