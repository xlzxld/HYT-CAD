;;; ============================================================================
;;; 程序名 : 出线槽绘制工具 (cx_runner.lsp)  v11.9
;;; v11.9  : 体检修复: dt:cx-process 源线收集补 dt:curves-only 过滤 —— CX 层
;;;          混入文字/标注/块时, vlax-curve-* 系列(dt:cx-trim/fillet-all/
;;;          join/close/yxb-plan)会抛"参数类型错误"中断流程, 留下半成品
;;;          (flb/jrt 同场景早有防护, 唯 cx 漏网)。偏移环节 dt:offset-enames
;;;          自带类型跳过, 不受影响。
;;; v11.8  : 全图层配色重排(用户需求, 与 flb v10.11 同批): CXK 150→122
;;;          (青绿), YXB 4→84(深绿, 与 LS 青 4 区分); 两处内联建层对已
;;;          存在图层也把颜色校正为登记值(老图重跑自动换新色)。几何零变化。
;;;          新增回归 tools/check_layer_colors.py(全脚本图层色唯一且色差达标)。
;;; v11.7  : 压线板两项修复(用户实测 1/2.dxf+png):
;;;          ①左壁畸形根治: dt:cx-yxb-draw 的本地映射(+X→外法向 nrm,
;;;            +Y→壁向 u)在左壁侧(nrm=rot90ccw(u), 外法向未翻转)是
;;;            左手系(镜像), 而弧角按纯旋转 +a1 处理 → 两条 R4.3 过渡弧
;;;            各偏 90°, 接不上上下边线, 板全数断开(右壁恰好右手系
;;;            无事, 故"左壁畸形/右壁正常")。镜像系(hand=nrm×u<0)下
;;;            弧角区间反向 [s,e]→[a1-e, a1-s]。
;;;          ②新增内壁/外壁取侧: 曲折出线槽的左/右壁随各源线绘制方向
;;;            漂移(同一圈一半内一半外)。选 Inner/Outer 时按"相连源线
;;;            (相交或端头距离≤1.2×偏移)中点多数侧=内侧"整圈一致取侧;
;;;            左/右壁语义保留(直线出线槽沿用)。
;;; v11.6  : 加载横幅 7 行精简为一行(命令教学移出加载期, 工作流规则已载
;;;          README_CAD.md) + 新增 *dt-cx-ver* 版本单一来源(根治横幅版本
;;;          号长期滞后, 本次 v11.3 → v11.6 追平)。
;;; v11.5  : 体检B-07/B-10: ①dt:cx-yxb-segs-of 的 member 表含无效类名
;;;          "AcDbLWPolyline"(死项)且缺 "AcDb3dPolyline" → 3D 折线落入
;;;          (T nil) 被静默忽略, 与头注"3D 折线按直段处理"矛盾; 表改
;;;          三个真实类名(getbulge 已有 catch, 3D 折线天然按直段)。
;;;          ②dt:cx-join 的 T 接打断前补 host 存活复检 —— 同一宿主壁
;;;          两端各命中 T 接时, 第二处循环的 host 已被首次打断删除,
;;;          对已删实体求几何会抛错中断整个收头/大圆角阶段; 失效则
;;;          跳过该处打断(下游"未找到配对断头"自然计入 count-fail)。
;;; v11.4  : 体检A-02根治(与 flb v10.7 / jrt v9.30 同期): LWPolyline 的
;;;          ObjectName 实为 "AcDbPolyline", dt:poly-pts/dt:seg-rebuild
;;;          的 is-2d 单名 "(= ... \"AcDbLWPolyline\")" 判定恒 nil →
;;;          多段线重建时 2D 平铺坐标按 3 元素错位切分、误建 3D 多段线。
;;;          两处改双名 member; dt:set-endpoint 同款死子句清除。
;;;          新增回归 tools/check_audit_fixes.py。
;;; v11.3  : 用户实测修复(v11.2 仍"两侧都放不出板"):
;;;          ①根因 = find-wall 只认 AcDbLine, 源线用 PL 多段线画时通道壁
;;;            也是多段线(偏移产物), 恒被判"非直线"跳过 → 新增
;;;            dt:cx-yxb-segs-of 按曲线参数逐段拆壁实体(LWPolyline/2dPolyline/
;;;            3DPolyline 直段参与、凸度≠0 弧段与 AcDbArc 按 v11.2 定案跳过),
;;;            find-walls 收集全部匹配直段, plan 逐段规划(一条壁可产多段);
;;;          ②无直段时打印自诊断: 弧段数/不平行数/侧不符数/垂距不符数 +
;;;            最近中点垂距偏差 —— 失败原因一眼可见, 不再只说"未找到"。
;;; v11.2  : 压线板三项根治(用户定案, 新图样=更新后 tools\1.dxf):
;;;          ①卡死根因确诊并修复: dt:cx-yxb-find-wall 的 entnext 全库扫描
;;;            中, 唯一的推进语句误置于"实体是壁层直线"判断的 if 内 ——
;;;            库内只要存在任一非该层直线实体(文字/块/其他层线), e 永不
;;;            前进 → while 死循环(CPU 满载假死, 与碰撞检测无关, 故 v10.7
;;;            移除碰撞后仍卡死)。改为 dt:layer-vlas 逐壁层实体遍历(有界
;;;            foreach, 结构上不可能死循环), 且不再扫无关实体(提速);
;;;          ②图样更新: 按用户新画 1.dxf 重做模板 —— D 形 6 件(重合线16.6
;;;            /上下边11/右边15.3/右端 R4.3 过渡弧×2), 删除旧模板照录的
;;;            2 条碎线与中部 R5.75 圆(旧图已不存在, 用户判"完全不对");
;;;          ③定位更新: 定位点 = 白线(通道源线)与重合线的交界点 = 重合线
;;;            中点(v10.x 误以重合线起点为基准, 整幅沿壁偏 8.3mm); 放置
;;;            = 重合线中点沿选定壁按 cx_yxb_gap 均匀分布且整组关于壁居中
;;;            (两端留白相等, 图5 参考); 斜槽随壁方向 u/n 旋转贴合(原样保留)。
;;; v11.1  : 修复 v11.0 进度打印 strcat 混入字面 + 号(stringp SUBR 报错)。
;;; v11.0  : 压线板卡死防御(用户实测 CX 卡死/CPU 满): 间距 <10 视为误填
;;;          按 125 处理; 每壁上限 100 幅(超限截断并警告); 规划/放置阶段
;;;          打印进度 —— 卡死时可从输出定位阶段。
;;; v10.8  : 修复压线板"函数错误: LAMBDA" —— dt:cx-yxb-place 局部计数器 n
;;;          与 dt:cx-yxb-draw 参数 n 撞名(AutoLISP 大小写不敏感 + 动态作用
;;;          域, 外层局部污染内层 lambda 自由变量), 分别改名 n-old / nrm。
;;; v10.7  : 压线板简化(用户定案): 移除碰撞判断(cands/clash/wall 三函数
;;;          删除), 改为按 cx_yxb_gap 沿选定侧壁无条件均匀放置; 流程拆成
;;;          删源线前的 dt:cx-yxb-plan(用源线判外侧方向, 只收数据)与删源
;;;          线后的 dt:cx-yxb-place(纯放置, 异常不再影响源线清理)——
;;;          同时修复 v10.6 压线板阶段卡死问题。
;;; v10.6  : 修复压线板碰撞检测卡死/CPU 飙高: 候选实体 bbox 一次缓存,
;;;          每次滑动尝试先用实例包络盒(约 20x17mm)做 bbox 级预过滤,
;;;          只对命中候选做 COM 求交 —— 每墙求交从万级降到百级以内;
;;;          cx_yxb_gap <= 0 时跳过压线板(防异常配置死循环)。
;;; v10.5  : 新增出线槽压线板(用户需求, 模板取自 tools\1.dxf 的 YXB 图层):
;;;          生成出线槽时在选定侧壁线上每隔 cx_yxb_gap(默认125, 进参数框)
;;;          放置一幅压线板 —— 重合线与壁线完全重合(斜壁同步旋转贴合),
;;;          主体朝通道外侧延伸; 其余曲线与图中任何实体相交即算碰撞,
;;;          沿壁滑动让位(步进10, 上限半间距), 无位可让跳过该处。
;;;          YXB 层青色 4, 脚本独占(每次运行先清旧实例); 重复弧只画一次。
;;;          运行时询问贴左壁/右壁(initget L/R)。另: 坑 #69 根除 —— 本文件
;;;          全部 (command "_.UNDO" "BE"/"E") 改 COM 撤销标记(同 jrt v9.17)。
;;; v10.3  : 健壮性修复(与 offset v10.6 / jrt v9.14 / dt_start v2.8 同期,
;;;          几何行为零变化):
;;;          1) 补回 v10.2 随整版回退而丢失的"标注文字类型防护" ——
;;;             collect-heads/collect-ends 及各图层收集统一按类型过滤,
;;;             小圆角半径递减写入 CX 层的"Rn"标注文字不再使后续延长/
;;;             大圆角/封闭步骤对文字对象求端点而崩溃;
;;;          2) dt:fillet-pair 改名 dt:cx-fillet-pair, 缺省层/缺省半径
;;;             回退值改为本脚本的 "CX"/slot 小圆角(原缺省引用主脚本
;;;             offset 的层与全局 *dt-fillet-r*, slot 单独加载时潜伏
;;;             报错; 同名不同体一律改名隔离, 坑 #46 同款);
;;;          3) cut-params 多段线分支 getparamatpoint 返回 nil 时剔除再
;;;             排序(nil 进 vl-sort 报 bad argument type);
;;;          4) 对话框 load_dialog/start_dialog 包 catch 且保证
;;;             unload_dialog 执行; ini/dcl 文件句柄异常兜底关闭;
;;;          5) c:SLOT 的 *error* 兜底闭合 UNDO 组;
;;;          6) 参数应用增加负值校验(负值回退当前值);
;;;          7) cross-points 加包围盒预过滤(bbox 不相交跳过 COM 求交,
;;;             结果不变, 大图提速);
;;;          8) 删除重复注释块。
;;; v10.1  : 全面审查定稿版(与 offset v10.5 / jrt v9.13 / dt_start v2.7
;;;          同期): 1) 参数框数值读取 atof→distof(垃圾输入不再被静默当成 0,
;;;          坑 #54); 2) INI 节名解析改用"截到行尾再裁方括号", 修复 AutoCAD
;;;          2021 之前中文节名残留 "]" 导致配置节永远匹配不上的问题;
;;;          3) 补声明全部遗漏的 foreach/setq 局部变量; 4) 闭合多段线判定补
;;;          vl-catch-all-error-p; 5) 敞口封闭去重改为双向比较(反向命中不再
;;;          画重复封闭线); 6) 延长收头的存活检查失败时不再整批跳过;
;;;          7) ini 默认值配置补中文注释(与 offset/jrt 格式一致); 删除未使用
;;;          的 exclude 形参与死局部。
;;; v10.0  : 参数默认值外置 cx_runner.ini(记事本可改, 弹框即生效, 无需重载);
;;;          参数记忆 cx_runner_mem.ini(确定参数框时自动保存, 上次值下次自动
;;;          预填, 跨会话); 恢复默认按钮 = 恢复 ini 里的默认值。文件在脚本目录
;;;          (无 dt_start 引导器时 TEMP); 解析只认"键 = 数值"行, 损坏自动回退。
;;; 适用   : AutoCAD 2024 (AutoCAD 2007 及以上版本均可)
;;; 功能   : "CX"图层上的源线向两侧各偏移 slot-dist(默认 17.5)生成通道壁
;;;          (源线保留同图层, 不删除); 相交的通道壁区域裁剪让行 + 小圆角
;;;          (R小, 默认15); 悬空端头沿切线固定延长 slot-extend(默认 50),
;;;          与其他壁相交处打断 + 大圆角(R大, 默认30), 仍不相交的端头复原;
;;;          暂不做两端封口(v8.13 起约定)。
;;; 来源   : 自 flb_runner v9.x 的出线槽链独立而来(几何逻辑与 v8.16 起
;;;          一脉相承, 零改动), 可与主脚本(分流板)分开单独加载, 同时加载
;;;          互不影响(参数表/对话框/dcl 文件/回调函数均已改名隔离)。
;;; 图层   : "CX" = 出线槽(源线 + 通道壁同层, 浅蓝 161); 源线由用户绘制,
;;;          脚本不删。v9.1 起图层名由中文"出线槽"改为拼音缩写 "CX"。
;;; 加载   : APPLOAD 选择本文件加载(cx_runner.dcl 由脚本自动生成)。
;;; 命令   : SLOT      —— 弹出参数框, 确定后执行出线槽全流程(取消中止)
;;;          SLOTPARAM —— 只弹出参数框改参数, 不执行
;;; 已知限制: 与主脚本一致(多段线重建丢凸度/闭合多段线跳过等, 见 AGENTS_CAD.md)。
;;; 说明   : 本文件必须 UTF-8 with BOM 编码(中文注释); 自动生成的
;;;          cx_runner.dcl 为 ANSI/GBK(系统代码页)。
;;; ============================================================================

(vl-load-com)  ; 加载 Visual LISP 扩展, 使 vla-* 系列函数可用

;; 版本单一来源: 发版时与头注同行更新; 加载横幅引用本值(防两处手抄脱节)
(setq *dt-cx-ver* "v11.9")

;; ============================================================================
;; 出线槽参数 —— 由 dt:cx-param-table 驱动(默认值/预填/应用/恢复默认),
;; 与主脚本 flb_runner 的参数表相互独立, 两脚本同时加载互不影响。
;; ============================================================================
(setq dt:cx-param-table
      (list
        (list "cx_dist" '*dt-cx-dist* 17.5) ; 出线槽偏移距离
        (list "cx_extend" '*dt-cx-extend* 50.0) ; 悬空端头固定延长距离
        (list "cx_fillet_r_small" '*dt-cx-fillet-r-small* 15.0) ; 相交断口小圆角半径
        (list "cx_fillet_r_large" '*dt-cx-fillet-r-large* 30.0) ; 延长交会处大圆角半径
        (list "cx_yxb_gap" '*dt-cx-yxb-gap* 125.0))) ; 压线板放置间距(v10.5)
(foreach p dt:cx-param-table (set (cadr p) (caddr p)))

;; 参数键 → 中文标签(v10.1: 与 offset/jrt 对齐 —— 生成 ini 时写中文注释行)
(setq dt:cx-param-labels
      '(("cx_dist"            . "出线槽偏移:")
        ("cx_extend"          . "出线槽延长:")
        ("cx_fillet_r_small"  . "出线槽小圆角R:")
        ("cx_fillet_r_large"  . "出线槽大圆角R:")
        ("cx_yxb_gap"         . "压线板间距:")))

;; ============================================================================
;; 参数配置与记忆(v10.0): 默认值外置 cx_runner.ini(用户记事本可改, 弹框前
;; 重读=随时生效); 上次值记忆 cx_runner_mem.ini(确定对话框时自动保存,
;; 下次打开自动预填)。解析只认"键 = 数值"行, 注释/空行/未知键跳过;
;; 全程 vl-catch-all 保护, 文件缺失/损坏静默回退代码内置默认。
;; 命名带 dt:cx- 前缀与 offset/jrt 同名库隔离(坑 #46); boot 在文件尾调用。
;; ============================================================================
(setq *dt-cx-cfg* nil   ; 配置(默认值) ((节 (键 . 值)...) ...)
      *dt-cx-mem* nil)  ; 记忆(上次值)   同结构, 固定节 "参数"

;; 配置/记忆文件目录: 优先 dt_start 注入的脚本目录, 无则 TEMP(与 find-dcl 同规则)
(defun dt:cx-cfg-dir ( / )
  (if (and *dt-script-dir* (/= *dt-script-dir* ""))
    *dt-script-dir*
    (getenv "TEMP")))

;; 单行 "键 = 数值" → (键 . 值); 无等号/空值/非数值返回 nil(distof 校验, 0 合法)
(defun dt:cx-cfg-kv (ln / p k vs n)
  (setq p (vl-string-search "=" ln))
  (if p
    (progn
      (setq k (vl-string-trim " \t" (substr ln 1 p))
            vs (vl-string-trim " \t" (substr ln (+ p 2)))
            n (if (= vs "") nil (distof vs)))
      (if (and (/= k "") n (numberp n)) (cons k n) nil))
    nil))

;; 读 INI → ((节名 (键 . 值)...) ...); 文件不存在/读失败返回 nil
(defun dt:cx-cfg-read (path / f ln sec ent tmp secs)
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
                ;; v10.1: 原用 (- (strlen ln) 2) 取长度 —— AutoCAD 2021 之前
                ;;   strlen 按字节计而 substr 按字符计, 中文节名(如 "[参数]")
                ;;   会连带尾部 "]"(变成 "参数]")导致配置节永远匹配不上。
                (setq sec (vl-string-trim " \t[]" (substr ln 2))))
               ((setq ent (dt:cx-cfg-kv ln))
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
  ;; v10.3: 异常兜底关闭 —— 读行中途出错时句柄不再滞留(读句柄滞留可能
  ;;   令后续同路径写打开失败); 正常路径已在闭包内关闭并置 nil
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (reverse secs))

;; 数据 → 指定节的键值表(无该节 nil)
(defun dt:cx-cfg-sec (data sec / e)
  (if (and data (setq e (assoc sec data))) (cdr e)))

;; 节内取键值(无该键 nil; 值可为 0, 0 非 nil 仍算"有")
(defun dt:cx-cfg-get (data sec key)
  (cdr (assoc key (dt:cx-cfg-sec data sec))))

;; 参数默认值: 配置节"参数" → 代码表 caddr
(defun dt:cx-param-default (key / v alt)
  (setq alt (cond ((= key "cx_dist") "slot_dist")
                  ((= key "cx_extend") "slot_extend")
                  ((= key "cx_fillet_r_small") "slot_fillet_r_small")
                  ((= key "cx_fillet_r_large") "slot_fillet_r_large")
                  (T key)))
  (cond ((setq v (dt:cx-cfg-get *dt-cx-cfg* "参数" key)) v)
        ((setq v (dt:cx-cfg-get *dt-cx-cfg* "参数" alt)) v)
        (T (caddr (assoc key dt:cx-param-table)))))

;; 首次自动生成配置文件(带中文注释)
(defun dt:cx-cfg-gen (path / f p lbl)
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "w"))
       (if f
         (progn
           (write-line "; cx_runner 参数默认值配置(首次运行自动生成, 记事本可改)" f)
           (write-line "; 改数值保存后, 下次打开参数窗口即生效(无需重载脚本/重启CAD)" f)
           (write-line "; 恢复默认按钮 = 本文件的值; 删除本文件 = 回代码内置默认" f)
           (write-line "; 上次填的值在 cx_runner_mem.ini(程序自动维护, 一般不用管)" f)
           (write-line "" f)
           (write-line "[参数]" f)
           (foreach p dt:cx-param-table
             (setq lbl (cdr (assoc (car p) dt:cx-param-labels)))
             (if lbl (write-line (strcat "; " lbl) f))
             (write-line (strcat (car p) " = " (rtos (caddr p) 2 4)) f))
           (close f)
           (setq f nil))))
    nil)
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  T)

;; 确定参数框后保存上次值(供下次打开预填)
(defun dt:cx-mem-save ( / path f p)
  (setq *dt-cx-mem*
        (list (cons "参数"
                    (mapcar '(lambda (q) (cons (car q) (eval (cadr q))))
                            dt:cx-param-table)))
        path (strcat (dt:cx-cfg-dir) "\\cx_runner_mem.ini"))
  (vl-catch-all-apply
    '(lambda ( )
       (setq f (open path "w"))
       (if f
         (progn
           (write-line "; cx_runner 参数记忆(确定参数窗口时自动更新, 可删除)" f)
           (write-line "" f)
           (write-line "[参数]" f)
           (foreach p dt:cx-param-table
             (write-line (strcat (car p) " = " (rtos (eval (cadr p)) 2 4)) f))
           (close f)
           (setq f nil))))
    nil)
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (princ))

;; 加载末尾调用: 生成缺失配置 + 把上次值恢复进全局变量(预填即上次状态)
(defun dt:cx-cfg-boot ( / path kv row)
  (vl-catch-all-apply
    '(lambda ( )
       (setq path (strcat (dt:cx-cfg-dir) "\\cx_runner.ini"))
       (setq *dt-cx-cfg* (dt:cx-cfg-read path))
       (if (null *dt-cx-cfg*)
         (progn
           (dt:cx-cfg-gen path)
           (setq *dt-cx-cfg* (dt:cx-cfg-read path))))
       (setq *dt-cx-mem*
             (dt:cx-cfg-read (strcat (dt:cx-cfg-dir) "\\cx_runner_mem.ini")))
       (foreach kv (dt:cx-cfg-sec *dt-cx-mem* "参数")
         (setq row (assoc (car kv) dt:cx-param-table))
         (if row (set (cadr row) (cdr kv)))))
    nil)
  (princ))

;; 坑 #69(v10.5): 撤销组统一走 COM 标记 —— *error* 与普通代码都不再碰
;; (command); 无开放标记时 EndUndoMark 无副作用, 双重 catch 兜底
(defun dt:cx-undo-mark ( )
  (vl-catch-all-apply
    '(lambda ( )
       (vla-StartUndoMark (vla-get-activedocument (vlax-get-acad-object))))))

(defun dt:cx-undo-end ( )
  (vl-catch-all-apply
    '(lambda ( )
       (vla-EndUndoMark (vla-get-activedocument (vlax-get-acad-object))))))

;; ============================================================================
;; 一、工具函数(与主脚本 flb_runner 逐字一致)
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

;; v10.3: 实体是否为可求端点/曲线参数的曲线(直线/弧/多段线) —— 文字/块等
;; 混入图层时 vlax-curve 系列会抛"参数类型错误"中断流程(坑: v10.2 的
;; slot-curve-p 防护随整版回退丢失), 收集/迭代前一律先过本判定
(defun dt:curve-p (obj / tp)
  (setq tp (vl-catch-all-apply 'vla-get-objectname (list obj)))
  (if (vl-catch-all-error-p tp)
    nil
    (member tp '("AcDbLine" "AcDbArc" "AcDbLWPolyline" "AcDbPolyline"))))

;; v10.3: 列表过滤, 只留 dt:curve-p 为真的实体
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
;;  挖孔线常为弧), 导致修剪后的弧端头与圆角弧端点不重合 —— 圆角弧
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
     ;; v10.3: 交点浮点偏移曲线时 getparamatpoint 可能返回 nil(甚至抛错),
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

;; boundingbox 输出解包: vla-getboundingbox 的输出参数有的版本绑定为
;; safearray 本体, 有的为 variant(内含 safearray) —— 统一容忍两种
;; (v9.8a 修复: variantp 类型错误; 与 flb_runner 逐字一致)
(defun dt:rect-bb-pts (x)
  (if (= (type x) 'variant)
    (vlax-safearray->list (vlax-variant-value x))
    (vlax-safearray->list x)))

;; 对象列表整体范围: 返回 (minx miny maxx maxy), 全部失败返回 nil
;; (与 flb_runner 逐字一致; v10.3 供 cross-points 包围盒预过滤用)
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
;; v10.3: 包围盒预过滤 —— 每对象只取一次 boundingbox, 两盒不相交则跳过
;;   COM 求交(bbox 不相交 => 两曲线必无交点, 结果不变); 大图上把 O(n^2) 次
;;   intersectwith 降为相邻对数量级(压力场景提速)
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
;; 二、断口圆角(小圆角/大圆角共用 dt:cx-fillet-pair)
;; ============================================================================
;; 处理一个断口对: 计算圆角几何, 递减半径, 方向验证, 修剪两线, 创建圆角弧, 必要时标注
;; h1/h2 = (对象 端类型" S"/"E" 端头点 指向主体方向)
;; layer = 圆角弧/标注文字所在图层(缺省"CX")
;; r-start = 圆角起始半径(缺省 slot 小圆角 *dt-cx-fillet-r-small*)
;; nochk = T 时跳过圆心区域方向验证(v9.5 大圆角: 延长接头处两源线区域
;;         不重叠, 区域检查会误拒正确方向; b1 与小圆角同公式, 方向由
;;         两端头的主体方向唯一确定)
;; 返回: (实际半径 T) 表示成功, nil 表示失败(无法圆角或两个方向圆心都侵入区域)
;; v10.3: 原名 dt:fillet-pair 与主脚本同名, 但缺省层/缺省半径引用的是主
;;   脚本 offset 的 "FLB"/全局 *dt-fillet-r* —— slot 单独加载时以 nil 调用
;;   会因 *dt-fillet-r* 无绑定报错(隐藏跨脚本耦合)。凡同名不同体一律改名
;;   隔离(坑 #46 同款, jrt 侧 dt:jrt-fillet-pair 先例), 缺省值改用本脚本
;;   的 "CX"/slot 小圆角。
(defun dt:cx-fillet-pair (h1 h2 center-lines off-dist layer r-start nochk /
                       obj1 et1 p1 d1 obj2 et2 p2 d2
                       ang2 b1 b2 done r d-tan len1 len2 c t1 t2 m a1 a2
                       tmp arc txt txt-pt ms ok)
  (if (null layer) (setq layer "CX"))
  (if (null r-start) (setq r-start *dt-cx-fillet-r-small*))
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
;; v10.3: 先按 dt:curve-p 过滤 —— 图层里的"Rn"标注文字等非曲线实体会让
;;   vlax-curve 端点查询抛错中断流程(v10.2 防护随整版回退丢失, 此处补回)
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

;; 判断端点 pt 是否为"悬空端头": ends 中没有其他端头与它重合(距离<1e-3)
;; 通道开放端是悬空端头; 交叉区断口端/圆角弧端都连着别的线, 非悬空
;; me = 当前端点记录, ends = 全部端点记录
(defun dt:end-free (pt me ends / e)
  (not (vl-some
         '(lambda (e)
            (and (not (equal e me))
                 (<= (distance pt (car e)) 1e-3)))
         ends)))

;; 只偏移指定图元(eName 列表), 用于出线槽: 只偏移源线, 避免重跑 OFF 时
;; 把"CX"图层里上一次残留的通道壁/圆角弧再偏移一遍(重跑污染)。v8.14
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

;; ============================================================================
;; 出线槽流程 —— v8.6 新增, 自 flb_runner 独立(逻辑零改动)
;; 需求: "CX"图层上的线向两侧偏移 slot-dist(默认17.5)生成通道壁,
;;       源线保留; 相交的裁剪+小圆角, 分离的悬空端头固定延长+相交大圆角。
;; 图层: "CX"(源线+通道壁同层, v8.9)
;; ============================================================================

;; 收集 vla-list 所有线端点: ((坐标 对象 端类型) ...)
;; v10.3: 按 dt:curve-p 过滤(文字等非曲线实体的端点查询会抛错)
(defun dt:collect-ends (vla-list / ends obj)
  (setq ends nil)
  (foreach obj vla-list
    (if (dt:curve-p obj)
      (progn
        (setq ends (cons (list (vlax-curve-getstartpoint obj) obj "S") ends)
              ends (cons (list (vlax-curve-getendpoint obj) obj "E") ends)))))
  ends)

;; 打断分发(原名/签名不变, slot-ext-check 调用): 所有段保留, 与区域裁剪
;; 共用 dt:cut-curve 驱动(v9.1 统一, 原 break-line/arc/poly 三个函数已并入)
(defun dt:break-curve (obj others-pts layer)
  (dt:cut-curve obj others-pts layer nil nil nil))

;; 出线槽区域裁剪(v8.7): 以"CX"源线为基准, 每条源线 ± slot-dist 构成
;; 带状区域, 伸进"其他源线带状区域"内的通道壁整段删除(与分流板区域裁剪
;; 逻辑完全一致; 主脚本以"LD"图层为基准, 出线槽以"CX"图层为基准)。
;; 裁剪后交叉处断开, 断口由 slot-fillet-all 圆角连接。
;; v8.14: 加 exclude 参数(源线 eName 字符串列表) —— 源线与通道壁同图层,
;;   收集通道壁时必须跳过源线, 防止源线被当作通道壁裁剪(源线未保留)。
(defun dt:cx-trim (center-lines slot-layer slot-dist exclude / all vla-list
                     pts-pairs pair trim-count skip-count)
  (if (null center-lines)
    (princ "\n【出线槽】没有源线基准, 无法裁剪。")
    (progn
      (setq all (dt:curves-only (dt:layer-vlas slot-layer)))
      (cond
        ((null all)
         (princ "\n【出线槽】没有通道壁, 跳过裁剪。"))
        ;; v8.14: 跳过源线(与通道壁同图层, 源线不参与裁剪)
        ((null (setq vla-list (vl-remove-if
                                '(lambda (o) (dt:excluded-p o exclude))
                                all)))
         (princ "\n【出线槽】图层内只有源线, 没有通道壁, 跳过裁剪。"))
        (T
         (progn
           (setq pts-pairs (dt:cross-points vla-list))
           (dt:cx-undo-mark)
           (setq trim-count 0 skip-count 0)
           (foreach pair pts-pairs
             (if (dt:trim-curve (car pair) (cdr pair) center-lines slot-dist slot-layer)
               (setq trim-count (1+ trim-count))
               (setq skip-count (1+ skip-count))))
           (dt:cx-undo-end)
           (princ (strcat "\n【出线槽】裁剪: 处理 " (itoa trim-count)
                          " 条, 跳过 " (itoa skip-count) " 条。"))))))))

;; 出线槽断口圆角: 断口配对 → dt:cx-fillet-pair(center-lines = 出线槽源线,
;; slot-dist 做 in-zone 方向验证 —— 与分流板断口圆角完全一致, 圆心必须在
;; 源线带状区域外, 弧凸向交叉中心/断口内侧)
;; v8.13: 加 exclude 参数(源线对象列表) —— 源线不再移走/删除,
;; 与通道壁同图层, 收集端头时必须跳过源线, 防止源线被误配对圆角。
;; v8.14: exclude 改为 eName 字符串列表比较 —— 原 vla-object equal 比较
;; 对不同实例恒不成立, 排除失效导致源线参与配对(误删相连线)。
(defun dt:cx-fillet-all (layer r center-lines slot-dist exclude / vla-list
                           heads pairs pair res count-ok count-fail)
  (if (null layer) (setq layer "CX"))
  (if (null r) (setq r *dt-cx-fillet-r-small*))
  (if (null slot-dist) (setq slot-dist *dt-cx-dist*))
  (setq vla-list (dt:curves-only (dt:layer-vlas layer)))
  (if (null vla-list)
    (princ (strcat "\n【出线槽】\"" layer "\"图层没有线, 跳过圆角。"))
    (progn
      ;; 收集端头 + 配对(源线按 eName 排除, 不参与圆角配对; v8.14)
      (setq heads (dt:collect-heads vla-list exclude)
            pairs (dt:pair-heads heads))
      (dt:cx-undo-mark)
      (setq count-ok 0 count-fail 0)
      (foreach pair pairs
        (setq res (dt:cx-fillet-pair (car pair) (cadr pair) center-lines slot-dist layer r nil))
        (if res
          (setq count-ok (1+ count-ok))
          (setq count-fail (1+ count-fail))))
      (dt:cx-undo-end)
      (princ (strcat "\n【出线槽】圆角: 成功 " (itoa count-ok) " 处, 失败 "
                     (itoa count-fail) " 处。")))))

;; ============================================================================
;; 出线槽固定延长 + 收头 + 大圆角(v9.3 重构):
;;   悬空端头沿切线**固定延长** *dt-cx-extend*(默认 50);
;;   每条延长的壁沿延长方向找**第一个交点**, 把端头**收回交点**
;;   (等效 AutoCAD FILLET 自带修剪, 消除 v8.15 版"冲过头"缺陷);
;;   未命中的端头复原。
;;   交点处圆角分两形态:
;;     * 转角相接: 双方端头收至同一交点而重合 → 与小圆角完全同一套
;;       fillet-pair 配对机制做 R大;
;;     * T形相接: 端头落在宿主壁内部 → 切线弧圆角, 宿主壁不切断。
;;   注意: 两端都可能命中 → 两端各自独立处理。
;; ============================================================================

;; 找延长方向上的第一个交点(v9.3): 与其余壁求实际交点(不延伸),
;; 过滤"沿延长方向且不超过延长长度+1"者取离原端头最近的一个;
;; 无实际交点时兜底"端头贴壁"(最近距离≤0.5, 沿用 v8.16 双判定容差)。
;; 返回 (宿主壁 交点) 或 nil
(defun dt:cx-first-cross (obj orig newp vla-list exclude /
                            dir len o p pts dp best best-d cp)
  (setq dir (dt:unit (mapcar '- newp orig))
        len (distance orig newp)
        best nil best-d 1e30)
  (foreach o vla-list
    (if (and (not (equal o obj))
             (not (dt:excluded-p o exclude)))
      (progn
        (setq pts (dt:inters-pts obj o))
        (foreach p pts
          (setq dp (+ (* (- (car p) (car orig)) (car dir))
                      (* (- (cadr p) (cadr orig)) (cadr dir))
                      (* (- (caddr p) (caddr orig)) (caddr dir))))
          (if (and (> dp 1e-6)
                   (<= (distance orig p) (+ len 1.0)))
            (if (< (distance orig p) best-d)
              (setq best-d (distance orig p) best (list o p))))))))
  (if best
    best
    ;; 兜底: 端头贴壁(取最近者)
    (progn
      (foreach o vla-list
        (if (and (not (equal o obj))
                 (not (dt:excluded-p o exclude)))
          (progn
            (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list o newp)))
            (if (and (not (vl-catch-all-error-p cp))
                     (<= (distance newp cp) 0.5)
                     (< (distance newp cp) best-d))
              (setq best-d (distance newp cp) best (list o cp))))))
      best)))

;; 出线槽固定延长(v8.15): 对图层内每条通道壁的悬空端头(端头处无其他端头
;; 重合), 沿切线向外固定延长 dist(默认 *dt-cx-extend*=50, 用户方案)。
;; 不找交点, 直接延长固定距离; 收头与圆角交给 dt:cx-join 处理(v9.3)。
;; 方向: S 端 -sd(指向起点外侧), E 端原始切向(指向终点外侧)。
;; 返回: ((obj 端类型" S"/"E" 原端头 新端头) ...)
(defun dt:cx-extend-fixed (layer dist exclude / vla-list ends obj sp ep sd ed
                             h newp ret)
  (if (null layer) (setq layer "CX"))
  (if (null dist) (setq dist *dt-cx-extend*))
  (setq vla-list (dt:curves-only (dt:layer-vlas layer)))
  (if (null vla-list)
    (princ "\n【出线槽】没有通道线, 跳过延长。")
    (progn
      (setq ends (dt:collect-ends vla-list)
            ret nil)
      (dt:cx-undo-mark)
      (foreach obj vla-list
        ;; 跳过源线(与通道壁同图层, 源线不参与延长; eName 比较)
        (if (not (vl-some
                   '(lambda (x) (equal x (vlax-vla-object->ename obj)))
                   exclude))
          (progn
            (setq sp (vlax-curve-getstartpoint obj)
                  ep (vlax-curve-getendpoint obj)
                  sd (dt:unit (vlax-curve-getfirstderiv obj (vlax-curve-getstartparam obj)))
                  ed (dt:unit (vlax-curve-getfirstderiv obj (vlax-curve-getendparam obj))))
            (foreach h (list (list sp (list (- (car sd)) (- (cadr sd)) (- (caddr sd))) "S")
                             (list ep ed "E"))
              ;; 悬空端头才延长(端头处无其他端头重合)
              (if (dt:end-free (car h) (list (car h) obj (caddr h)) ends)
                (progn
                  (setq newp (dt:pt+vec (car h) (cadr h) dist))
                  (dt:set-endpoint obj (caddr h) newp)
                  (setq ret (cons (list obj (caddr h) (car h) newp) ret))))))))
      (dt:cx-undo-end)
      (princ (strcat "\n【出线槽】固定延长: 共延长 " (itoa (length ret))
                     " 个悬空端头(延长 " (rtos dist 2 0) ")。"))
      ret)))

;; 延长收头 + 交点大圆角入口(v9.3, 替代 v8.15 的 slot-ext-check +
;; slot-fillet-ext): 两遍处理 ——
;;   Pass1: 先在未收头的原始延长几何上逐条求第一个交点(消除处理顺序
;;          依赖), 再统一收头: 命中 → set-endpoint 收至交点(=FILLET 自带
;;          修剪, 修复"冲过头"缺陷); 未命中 → 复原到原端头。
;;   Pass2: 逐交点圆角(同一交点多条记录只处理一次; 端头实时重收集,
;;          避免前一个圆角移动端头后用到旧数据, 坑#23):
;;            重合端头≥2(转角相接) → 与小圆角完全同一套 dt:cx-fillet-pair,
;;              仅半径为 R大(v9.5: nochk=T 关闭圆心区域方向验证 ——
;;              延长接头处两源线区域不重叠, 该验证会误拒正确方向,
;;              这就是 v9.3/v9.4 方向错误的根源);
;;            仅1个(T形相接) → 交点处打断宿主壁产生重合断头, 取与
;;              宿主源线前进方向同侧的断头, 同一套 fillet-pair 配对。
(defun dt:cx-join (layer r center-lines slot-dist exclude ext-rec /
                     vla-list rec obj et orig newp hit ep hits misses
                     cp host done-cps heads h res count-ok count-fail
                     i j h1 h2 fwd hh pick host-alive)
  (if (null layer) (setq layer "CX"))
  (if (null r) (setq r *dt-cx-fillet-r-large*))
  (setq vla-list (dt:curves-only (dt:layer-vlas layer)))
  (if (null vla-list)
    (princ "\n【出线槽】没有通道线, 跳过延长收头。")
    (progn
      ;; Pass1a: 原始延长几何上逐条求第一个交点
      (setq hits nil misses nil)
      (foreach rec ext-rec
        (setq obj (nth 0 rec) et (nth 1 rec)
              orig (nth 2 rec) newp (nth 3 rec))
        ;; v10.1: 存活检查本身失败(不同版本对 vla-object/ename 的支持差异)
        ;;   时不应整批跳过 —— 那会让"收头+大圆角"整体静默失效。无法判断
        ;;   即视为仍有效, 继续处理(后续几何调用本身有 catch 保护)。
        (setq ep (vl-catch-all-apply 'vlax-erased-p (list obj)))
        (if (and (not (vl-catch-all-error-p ep)) ep)
          (princ "\n【出线槽】延长记录对象已失效, 跳过该记录。")
          (progn
            (setq hit (dt:cx-first-cross obj orig newp vla-list exclude))
            (if hit
              (setq hits (cons (list obj et (cadr hit) (car hit)) hits))
              (setq misses (cons (list obj et orig) misses))))))
      ;; Pass1b: 统一收头(命中收至交点, 未命中复原)
      (dt:cx-undo-mark)
      (foreach rec hits
        (dt:set-endpoint (nth 0 rec) (nth 1 rec) (nth 2 rec)))
      (foreach rec misses
        (dt:set-endpoint (nth 0 rec) (nth 1 rec) (nth 2 rec)))
      (dt:cx-undo-end)
      (princ (strcat "\n【出线槽】延长收头: " (itoa (length hits))
                     " 处命中交点, " (itoa (length misses)) " 处复原。"))
      ;; Pass2: 交点圆角
      (setq count-ok 0 count-fail 0 done-cps nil)
      (dt:cx-undo-mark)
      (foreach rec hits
        (setq cp (nth 2 rec) host (nth 3 rec))
        (if (not (vl-some '(lambda (q) (<= (distance q cp) 1e-3)) done-cps))
          (progn
            (setq done-cps (cons cp done-cps))
            ;; 实时重收集与 cp 重合的端头
            (setq heads nil)
            (foreach h (dt:collect-heads (dt:layer-vlas layer) exclude)
              (if (<= (dt:dist (caddr h) cp) 1e-3)
                (setq heads (cons h heads))))
            (cond
              ((>= (length heads) 2)
               ;; 转角相接(v9.5): 双方端头收至同一交点而重合 → 与小圆角
               ;; 完全同一套 fillet-pair, 仅半径为 R大; nochk=T 关闭圆心
               ;; 区域方向验证(延长接头处两源线区域不重叠, 该验证会误拒
               ;; 正确方向 —— v9.3/v9.4 方向错误的根源)
               (setq i 0)
               (foreach h1 heads
                 (setq j 0)
                 (foreach h2 heads
                   (if (> j i)
                     (if (and (not (equal (car h1) (car h2)))
                              (dt:not-parallel (cadddr h1) (cadddr h2)))
                       (progn
                         (setq res (dt:cx-fillet-pair h1 h2 center-lines slot-dist
                                                   layer r T))
                         (if res
                           (setq count-ok (1+ count-ok))
                           (setq count-fail (1+ count-fail))))))
                   (setq j (1+ j)))
                 (setq i (1+ i))))
              ((= (length heads) 1)
               ;; T形相接(v9.5): 端头落在宿主壁内部 → 在交点处打断宿主壁
               ;; 使其产生重合断头, 取主体方向与宿主源线前进方向同侧者,
               ;; 同一套 fillet-pair(nochk=T), 宿主壁另一侧保持延续
               (setq fwd (dt:near-src-fwd cp center-lines))
               (if (null fwd)
                 (progn
                   (princ "\n【出线槽】警告: 交点附近找不到两条源线, 跳过该处圆角。")
                   (setq count-fail (1+ count-fail)))
                 (progn
                   ;; v11.5: host 存活复检 —— 同一宿主壁两端各命中 T 接时,
                   ;; 第二处循环的 host 已被首次 break-curve(删旧建新)删除,
                   ;; 对已删实体求几何会抛错中断整个收头/大圆角阶段; 复检
                   ;; 失败视为仍有效(与上方 v10.1 ext-rec 惯用法一致), 跳过
                   ;; 打断后由下方"未找到配对断头"路径自然计入 count-fail
                   (setq host-alive (vl-catch-all-apply 'vlax-erased-p (list host)))
                   (if (and (not (vl-catch-all-error-p host-alive)) host-alive)
                     (princ "\n【出线槽】警告: 宿主壁已失效(同壁多处T接), 跳过该处打断。")
                     (dt:break-curve host (list cp) layer))
                   ;; 重收集交点处端头(打断后宿主产生两个新断头)
                   (setq hh nil)
                   (foreach h (dt:collect-heads (dt:layer-vlas layer) exclude)
                     (if (<= (dt:dist (caddr h) cp) 1e-3)
                       (setq hh (cons h hh))))
                   (setq h1 (car heads) pick nil)
                   (foreach h hh
                     (if (and (not (equal (car h) (car h1)))
                              (> (+ (* (car (cadddr h)) (car (cadr fwd)))
                                    (* (cadr (cadddr h)) (cadr (cadr fwd))))
                                 0.0))
                       (setq pick h)))
                   (if pick
                     (progn
                       (setq res (dt:cx-fillet-pair h1 pick center-lines slot-dist
                                                 layer r T))
                       (if res
                         (setq count-ok (1+ count-ok))
                         (setq count-fail (1+ count-fail))))
                     (progn
                       (princ "\n【出线槽】警告: T形接头未找到配对断头, 跳过该处圆角。")
                       (setq count-fail (1+ count-fail)))))))
              (t
               (princ "\n【出线槽】警告: 交点处未找到端头, 跳过该处圆角。")
               (setq count-fail (1+ count-fail)))))))
      (dt:cx-undo-end)
      (princ (strcat "\n【出线槽】大圆角: 成功 " (itoa count-ok) " 处, 失败 "
                     (itoa count-fail) " 处(半径 " (rtos r 2 1) ")。"))))
  (princ))


(defun dt:near-src-fwd (cp center-lines / s dd b1 b2 d1 d2)
  (setq b1 nil b2 nil d1 1e30 d2 1e30)
  (foreach s center-lines
    (setq dd (vl-catch-all-apply 'vlax-curve-getclosestpointto (list s cp)))
    (if (and (not (vl-catch-all-error-p dd)) dd)
      (progn
        (setq dd (distance cp dd))
        (cond
          ((< dd d1) (setq d2 d1 b2 b1 d1 dd b1 s))
          ((< dd d2) (setq d2 dd b2 s))))))
  (if (and b1 b2)
    (list (dt:unit (mapcar '- (vlax-curve-getendpoint b1)
                           (vlax-curve-getstartpoint b1)))
          (dt:unit (mapcar '- (vlax-curve-getendpoint b2)
                           (vlax-curve-getstartpoint b2))))))

;; 出线槽敞口封闭(v9.6, v9.7 修数据格式, v9.9 加 CXK 分流): 每条源线的
;; 悬空端(未参与转角接头的端头)是通道敞口 —— 两壁端头悬空在距源线端点
;; ≈ slot-dist 处, 用一条封闭线连接(垂直于通道, 放本层)。端点记录用
;; dt:collect-ends 的 (坐标 对象 端类型)格式 —— 与主脚本封口线同款数据流;
;; v9.6 误用圆角的 (对象 端类型 坐标 方向)格式, dt:end-free 把圆弧对象
;; 当点用导致崩溃。参与了接头的壁端头已被延长/收头/圆角移动(距源线端点
;; ≥22, 实测), 不满足距离条件, 自然不会被误封。
;; v9.9: 收尾调 dt:cx-cxk —— 距 DP(垫片)层对象最远的一条封闭线移入
;; "CXK"图层(青绿 122, 供下游区分出线口)。
(defun dt:cx-close (layer center-lines slot-dist /
                      ends P cand e a pair p1 p2 done-pairs ln count tol closers
                      cl)
  (if (null layer) (setq layer "CX"))
  (if (null slot-dist) (setq slot-dist *dt-cx-dist*))
  (setq tol (max 1.0 (* slot-dist 0.15))
        ends (dt:collect-ends (dt:layer-vlas layer))
        done-pairs nil
        count 0
        closers nil)
  (if (null ends)
    (princ "\n【出线槽】没有通道壁, 跳过封闭。")
    (progn
      (dt:cx-undo-mark)
      (foreach cl center-lines
        (foreach P (list (vlax-curve-getstartpoint cl)
                         (vlax-curve-getendpoint cl))
          ;; 候选: 距源线端点 ≈ slot-dist 的悬空壁端头
          ;; (源线自身端点距离为 0, 天然被窗口过滤)
          (setq cand nil)
          (foreach e ends
            (setq a (distance P (car e)))
            (if (and (> a (- slot-dist tol))
                     (< a (+ slot-dist tol))
                     (dt:end-free (car e) e ends))
              (setq cand (cons (cons a e) cand))))
          (setq cand (vl-sort cand '(lambda (x y) (< (car x) (car y)))))
          ;; 取最近的两条不同对象端头为封口对(与主脚本 pick-pair 同判)
          (setq pair nil)
          (if (>= (length cand) 2)
            (progn
              (setq p1 (cdr (nth 0 cand)) p2 nil)
              (foreach e (cdr cand)
                (if (and (null p2)
                         (not (equal (cadr (cdr e)) (cadr p1))))
                  (setq p2 (cdr e))))
              (if p2 (setq pair (list p1 p2)))))
          ;; 去重后画封闭线
          ;; v10.1: 去重改为双向比较 —— 同一对端头若以相反顺序命中
          ;;   (两条源线共享一个敞口时会出现), 旧写法判不出重复会画两次
          (if (and pair
                   (not (vl-some
                          '(lambda (q)
                             (or (and (<= (distance (car q) (car p1)) 1e-3)
                                      (<= (distance (cadr q) (car p2)) 1e-3))
                                 (and (<= (distance (car q) (car p2)) 1e-3)
                                      (<= (distance (cadr q) (car p1)) 1e-3))))
                          done-pairs)))
            (progn
              (setq ln (vla-addline (dt:ms)
                                    (vlax-3d-point (car p1))
                                    (vlax-3d-point (car p2)))
                    done-pairs (cons (list (car p1) (car p2)) done-pairs)
                    count (1+ count)
                    closers (cons ln closers))
              (vla-put-layer ln layer)))))
      (princ (strcat "\n【出线槽】封闭: 共封闭 " (itoa count)
                     " 处通道敞口(封闭线已放\"" layer "\"图层)。"))
      ;; v9.9: 距 DP(垫片)层对象最远的一条封闭线移入 CXK 图层(同一 UNDO 组内)
      (dt:cx-cxk closers)
      (dt:cx-undo-end)))
  (princ))

;; CXK 分流(v9.9): 封闭线中距 DP(垫片)层对象**最远的一条**移入新图层
;; "CXK"(青绿 122, 供下游区分出线口)。距离 = 封闭线 3 采样点
;; (起点/中点/终点)到各 DP 对象最近点的最小值(几何边缘距离, 圆/线/弧
;; 通用)。DP 层不存在或为空 → 提示并跳过(全部封闭线留在 CX, SLOT 可
;; 独立运行); 只有 1 条封闭线时规则照常成立(它即最远, 仍移入)。
(defun dt:cx-cxk (closers / ss dps ln sp mp ep dpo q cp dmin best best-d
                    layers lay)
  (cond
    ((null closers)
     (princ))
    ((null (setq ss (ssget "X" (list (cons 8 "DP")))))
     (princ "\n【出线槽】\"DP\"(垫片)层没有对象, 封闭线全部留在\"CX\"层(画好垫片后重跑 SLOT 可分流 CXK)。"))
    (T
     (setq dps (mapcar 'vlax-ename->vla-object (dt:ss->list ss))
           best nil
           best-d -1.0)
     (foreach ln closers
       (setq sp (vlax-curve-getstartpoint ln)
             mp (vlax-curve-getpointatparam ln (/ (vlax-curve-getendparam ln) 2.0))
             ep (vlax-curve-getendpoint ln)
             dmin 1e30)
       (foreach dpo dps
         (foreach q (list sp mp ep)
           (setq cp (vl-catch-all-apply 'vlax-curve-getclosestpointto (list dpo q)))
           (if (and (not (vl-catch-all-error-p cp)) cp)
             (setq dmin (min dmin (distance q cp))))))
       (if (and (< dmin 1e29) (> dmin best-d))
         (setq best-d dmin best ln)))
     (if (null best)
       (princ "\n【出线槽】警告: 垫片对象无法测距, 封闭线全部留在\"CX\"层。")
       (progn
         ;; 创建 CXK 图层(已存在则把颜色校正为登记值 122, v11.8 配色统一)
         (setq layers (vla-get-layers (vla-get-activedocument (vlax-get-acad-object))))
         (if (null (tblsearch "LAYER" "CXK"))
           (progn
             (setq lay (vla-add layers "CXK"))
             (vla-put-color lay 122)
             (princ "\n【出线槽】已创建新图层 \"CXK\" (青绿, 放距 DP 最远的封闭线)。"))
           (progn
             (setq lay (vla-item layers "CXK"))
             (if (/= (vla-get-color lay) 122)
               (vla-put-color lay 122))))
         (vla-put-layer best "CXK")
         (princ (strcat "\n【出线槽】距 DP 最远的封闭线(距离 " (rtos best-d 2 2)
                        ")已移入\"CXK\"图层。"))))))
  (princ))



;; 出线槽完整流程(v9.6): 偏移 → 区域裁剪(相交线让行) → 小圆角 →
;; 固定延长悬空端头 → 收头(命中交点/复原) → 交点大圆角 → 通道封闭
;; → 删除源线。
;; 关键(v8.10 用户确认 + v9.3/v9.5/v9.6 用户要求):
;;   * 相交的线: 裁剪(伸进对方源线区域内的段删除, 与分流板一致) + 小圆角 R小
;;   * 未相交的线: 悬空端头**固定延长** *dt-cx-extend*(默认50); 延长后
;;     沿方向找第一个交点并**收头**(=FILLET 自带修剪); 交点处大圆角
;;     R大 —— 与小圆角同一套 fillet-pair(仅半径不同, v9.5)
;;   * 大小圆角方向均与分流板一致: 弧凸向交点
;;   * v9.6: 通道敞口(源线悬空端)用封闭线封上(放本层); 流程末尾**删除
;;     全部源线** —— 重跑 SLOT 需重新绘制源线, 旧通道壁仍需先手动清理。
(defun dt:cx-process (src-layer slot-layer slot-dist yxb-side
                        / ss src-enames center-lines res ext-rec n-del r en yxb-plans)
  (if (null slot-dist) (setq slot-dist *dt-cx-dist*))
  (if (null yxb-side) (setq yxb-side "Left"))
  (setq ss (ssget "X" (list (cons 8 src-layer))))
  (if (null ss)
    (princ (strcat "\n【出线槽】\"" src-layer "\"图层没有线, 跳过。"))
    (progn
      ;; 0) 记录源线 eName(排除基准, v8.14 用字符串比较可靠) + 源线 vla
      ;;    (裁剪/圆角方向验证用); 只对源线偏移生成通道壁(源线保留在
      ;;    "CX"图层, 不移走不删除; v8.14 用 dt:offset-enames 避免
      ;;    重跑时把旧通道壁再偏移一遍)
      ;;    v11.9: center-lines 补 dt:curves-only —— CX 层混入文字/标注/块
      ;;    时 vlax-curve-* 会抛"参数类型错误"中断流程(v10.3 规约: 收集前
      ;;    一律先过本判定); eName 列表不滤, 偏移/排除环节各自有防护。
      (setq src-enames (dt:ss->list ss)
            center-lines (dt:curves-only (mapcar 'vlax-ename->vla-object src-enames)))
      (setq res (dt:offset-enames src-enames slot-layer slot-dist))
      (if (> (car res) 0)
        (progn
          ;; 1) 区域裁剪: 相交处伸进对方源线区域内的段整段删除(与分流板一致;
          ;;    v8.14 传 src-enames 排除源线, 源线不参与裁剪)
          (dt:cx-trim center-lines slot-layer slot-dist src-enames)
          ;; 2) 小圆角: 连接相交断口(圆心在源线区域外, 与分流板断口圆角一致;
          ;;    v8.14 传 src-enames, 源线不参与圆角配对)
          (dt:cx-fillet-all slot-layer *dt-cx-fillet-r-small* center-lines slot-dist src-enames)
          ;; 3) 固定延长悬空端头(v8.15): 悬空端头沿切线向外固定延长
          ;;    *dt-cx-extend*(默认50), 返回 ((obj 端类型 原端头 新端头) ...);
          ;;    源线不参与延长(eName 排除)
          (setq ext-rec (dt:cx-extend-fixed slot-layer *dt-cx-extend* src-enames))
          ;; 4) 收头 + 大圆角(v9.5): 每条延长的壁沿方向找第一个交点并收头
          ;;    (=FILLET 自带修剪); 交点处与小圆角同一套 fillet-pair,
          ;;    仅半径 R大; 未命中则复原。
          (dt:cx-join slot-layer *dt-cx-fillet-r-large* center-lines slot-dist src-enames ext-rec)
          ;; 5) 通道封闭(v9.6): 每个敞口(源线悬空端的两壁端头, 距源线
          ;;    端点 ≈ slot-dist 的悬空端头对)连一条封闭线(垂直于通道,
          ;;    放本层)。必须在删除源线之前执行(用源线端点定位敞口)。
          (dt:cx-close slot-layer center-lines slot-dist)
          ;; 5.5) 压线板规划(v11.2): 每条源线选定侧的直壁收集放置数据 ——
          ;;      重合线贴壁(斜壁随壁旋转), 主体朝通道外侧; 定位点 = 重合线
          ;;      中点(与白线/源线交界)。必须在删除源线之前规划(用源线
          ;;      判定通道外侧方向)。
          (setq yxb-plans (dt:cx-yxb-plan center-lines slot-layer src-enames yxb-side slot-dist))
          ;; 6) 删除源线(v9.6, 用户要求): 偏移用的源线全部删除, 图面
          ;;    只留通道壁/圆弧/封闭线。注意: 重跑 SLOT 需重新绘制源线;
          ;;    旧通道壁仍需先手动清理(既有约定)。
          (dt:cx-undo-mark)
          (setq n-del 0)
          (foreach en src-enames
            (setq r (vl-catch-all-apply
                      '(lambda (e / o)
                         (setq o (vlax-ename->vla-object e))
                         (if o (vla-delete o) T))
                      (list en)))
            (if (not (vl-catch-all-error-p r))
              (setq n-del (1+ n-del))))
          (dt:cx-undo-end)
          (princ (strcat "\n【出线槽】已删除源线 " (itoa n-del)
                         " 条(重跑 SLOT 需重新绘制源线)。"))
          ;; 6.5) v10.7 压线板放置(源线已删, 异常不再影响清理)
          (dt:cx-yxb-place yxb-plans *dt-cx-yxb-gap*))
        (princ "\n【出线槽】偏移失败(无通道壁生成)。")))))

;; ============================================================================
;; 出线槽压线板(v11.2/3): 模板取自用户更新后 tools\1.dxf 的 D 形图样(见
;; dt:cx-yxb-tpl) —— 重合线(左壁竖线, 长 16.6)贴出线槽一侧壁线, 主体朝通道
;; 外侧延伸 15.3mm(上下边 11 + 右端 R4.3 过渡弧×2, 旧模板的 2 条碎线与
;; 中部 R5.75 圆已删, 新图样不再有)。定位点 = 白线(通道源线)与重合线的
;; 交界点 = 重合线中点。规则: 重合线与壁线完全重合(斜壁同步旋转贴合);
;; 重合线中点沿壁按 cx_yxb_gap 均匀分布, 整组关于壁居中(两端留白相等);
;; 壁候选=壁层直线与多段线直段(v11.3), 弧段暂跳过并计入自诊断;
;; 不做碰撞判断(v10.7 用户定案)。YXB 层青色 4, 由脚本独占: 每次运行先清
;; 空旧实例再重排。
;; ============================================================================

;; 压线板模板(本地坐标: 重合线 = (0,0)-(0,16.6), +Y 沿通道方向, +X 朝外侧;
;; 定位点 = 重合线中点 (0,8.3)) —— 逐尺寸取自 1.dxf 层"1"的 D 形图样
(defun dt:cx-yxb-tpl ( )
  (list
    (list "LINE"   0.0  0.0    0.0 16.6)        ; 重合线(贴壁)
    (list "LINE"   0.0  0.0   11.0  0.0)        ; 下边
    (list "LINE"   0.0 16.6   11.0 16.6)        ; 上边
    (list "LINE"  15.3  4.3   15.3 12.3)        ; 右侧直边
    (list "ARC"   11.0  4.3    4.3 270.0 360.0) ; 右下过渡弧
    (list "ARC"   11.0 12.3    4.3   0.0  90.0))) ; 右上过渡弧

;; 模板实例绘制: o = 重合线起点(壁上), u = 壁方向单位向量, n = 外侧法向单位
;; 向量(本地 +Y→u, +X→n; 弧角度随旋转平移)。返回新建实体 vla 列表(YXB 层)
(defun dt:cx-yxb-map-pt (lx ly o u nrm)
  (list (+ (car o) (* (car u) ly) (* (car nrm) lx))
        (+ (cadr o) (* (cadr u) ly) (* (cadr nrm) lx))
        0.0))

(defun dt:cx-yxb-draw (o u nrm layer / a1 hand ents e t1 t2)
  ;; v11.7: 本地系(+X→nrm, +Y→u)在 nrm=rot90ccw(u)(左壁侧, 外法向未翻转)
  ;; 是左手系(det=-1, 镜像) —— 直线镜像后仍精确, 但弧角按纯旋转 +a1 会各
  ;; 偏 90°, 两条 R4.3 过渡弧接不上上下边线(1.dxf 实测 42/42 板全数断开;
  ;; 右壁 nrm=rot90cw(u) 恰好右手系, 故仅左壁畸形)。镜像系下弧角区间须
  ;; 反向: CCW [s,e] → CCW [a1-e, a1-s]; hand = nrm×u 的 z 分量, <0 即镜像。
  (setq a1 (angle '(0.0 0.0 0.0) nrm)
        hand (- (* (nth 0 nrm) (nth 1 u)) (* (nth 1 nrm) (nth 0 u)))
        ents nil)
  (foreach e (dt:cx-yxb-tpl)
    (setq t1 (dt:cx-yxb-map-pt (nth 1 e) (nth 2 e) o u nrm))
    (cond
      ((= (car e) "LINE")
       (setq t2 (dt:cx-yxb-map-pt (nth 3 e) (nth 4 e) o u nrm)
             ents (cons (vla-addline (dt:ms) (vlax-3d-point t1) (vlax-3d-point t2))
                        ents)))
      ((= (car e) "ARC")
       (setq ents (cons (vla-addarc (dt:ms)
                          (vlax-3d-point t1)
                          (nth 3 e)
                          (if (< hand 0.0)
                            (- a1 (* pi (/ (nth 5 e) 180.0)))
                            (+ a1 (* pi (/ (nth 4 e) 180.0))))
                          (if (< hand 0.0)
                            (- a1 (* pi (/ (nth 4 e) 180.0)))
                            (+ a1 (* pi (/ (nth 5 e) 180.0)))))
                        ents)))
      ((= (car e) "CIRCLE")
       (setq ents (cons (vla-addcircle (dt:ms) (vlax-3d-point t1) (nth 3 e)) ents)))))
  (foreach ent ents (vla-put-layer ent layer))
  (reverse ents))

;; 内/外壁侧解析(v11.7, 用户需求: 曲折出线槽的左/右壁随各源线绘制方向
;; 漂移, 同一圈会出现一半内一半外, 须整圈一致): 只对 "Inner"/"Outer"
;; 生效, "Left"/"Right" 原样返回(直线出线槽沿用旧语义)。
;; 判定: 与本源线"相连"的其他源线 —— 相交(dt:inters-pts 非空, 拐角画法)
;; 或任一端头到对方曲线距离 ≤ 1.2×偏移(T 接画法; 平行的相邻通道 ≥ 2×
;; 偏移不误入)。相连源线中点落在本源线哪一侧(Left/Right)投票, 多数侧 =
;; 内壁侧(围合区/曲率中心一侧)。平票或无邻居(孤立直线, 内外无定义):
;; 按内=左/外=右兜底并打印提示。返回 "Left"/"Right" 供 find-walls 使用。
(defun dt:cx-yxb-resolve-side (all-lines src side slot-dist /
                               ss2 ee2 oj mj sidev left right)
  (if (not (member (strcase side) '("INNER" "OUTER")))
    side
    (progn
      (setq ss2 (vlax-curve-getstartpoint src)
            ee2 (vlax-curve-getendpoint src)
            ss2 (list (nth 0 ss2) (nth 1 ss2) 0.0)
            ee2 (list (nth 0 ee2) (nth 1 ee2) 0.0)
            left 0 right 0)
      (foreach oj all-lines
        (if (and (/= (vla-get-handle oj) (vla-get-handle src))
                 (or (dt:inters-pts src oj)
                     (<= (min (distance ss2 (vlax-curve-getclosestpointto oj ss2))
                              (distance ee2 (vlax-curve-getclosestpointto oj ee2))
                              (distance (vlax-curve-getstartpoint oj)
                                        (vlax-curve-getclosestpointto
                                          src (vlax-curve-getstartpoint oj)))
                              (distance (vlax-curve-getendpoint oj)
                                        (vlax-curve-getclosestpointto
                                          src (vlax-curve-getendpoint oj))))
                          (* 1.2 slot-dist))))
          (progn
            (setq mj (vlax-curve-getpointatparam oj
                       (/ (+ (vlax-curve-getstartparam oj)
                             (vlax-curve-getendparam oj)) 2.0))
                  sidev (- (* (- (nth 0 ee2) (nth 0 ss2)) (- (nth 1 mj) (nth 1 ss2)))
                           (* (- (nth 1 ee2) (nth 1 ss2)) (- (nth 0 mj) (nth 0 ss2)))))
            (cond
              ((< (abs sidev) 1e-6) nil)   ; 共线邻居(重复画线)不投票
              ((> sidev 0.0) (setq left (1+ left)))
              (T (setq right (1+ right)))))))
      (cond
        ((and (= left 0) (= right 0))
         (princ (strcat "\n【压线板】源线无相连源线, 内/外壁未定义, 按"
                        (if (= (strcase side) "INNER") "左" "右") "壁处理。")))
        ((= left right)
         (princ "\n【压线板】内/外壁投票平票, 按内=左/外=右处理。")))
      (if (= (strcase side) "INNER")
        (if (>= left right) "Left" "Right")
        (if (< left right) "Left" "Right")))))

;; 规划(v10.7 引入, v11.3 改逐直段): 每条源线选定侧的壁直段 -> (sp u n0 L)
;; 数据(一条壁可产多段)。sp = 段起点(与源线同向化后), u = 段方向单位向量,
;; n0 = 外侧法向, L = 段长。只收集数据不动图元; 放置在删源线后由
;; dt:cx-yxb-place 执行。无直段时打印自诊断(弧段/不平行/侧不符计数与
;; 最近垂距偏差 —— 一眼看出差在哪个条件)。v11.7: side 为 Inner/Outer 时
;; 先经 dt:cx-yxb-resolve-side 逐源线解析成 Left/Right(整圈一致), 见上。
(defun dt:cx-yxb-plan (center-lines slot-layer src-enames side slot-dist /
                       plans src side-r res pieces n-arc n-notpar n-side n-dist dmin
                       p sp ep u n0 pA pB ss2 ee2 ds dl L tmp nsrc)
  (setq nsrc 0)
  (foreach src center-lines
    (setq nsrc (1+ nsrc)
          side-r (dt:cx-yxb-resolve-side center-lines src side slot-dist)
          res (dt:cx-yxb-find-walls src slot-layer src-enames side-r slot-dist)
          pieces (nth 0 res) n-arc (nth 1 res) n-notpar (nth 2 res)
          n-side (nth 3 res) n-dist (nth 4 res) dmin (nth 5 res))
    (if pieces
      (foreach p pieces
        (setq sp (nth 0 p) ep (nth 1 p)
              sp (list (nth 0 sp) (nth 1 sp) 0.0)
              ep (list (nth 0 ep) (nth 1 ep) 0.0)
              L  (distance sp ep)
              ss2 (vlax-curve-getstartpoint src)
              ee2 (vlax-curve-getendpoint src)
              ds  (list (- (nth 0 ee2) (nth 0 ss2)) (- (nth 1 ee2) (nth 1 ss2)) 0.0)
              dl  (sqrt (+ (* (nth 0 ds) (nth 0 ds)) (* (nth 1 ds) (nth 1 ds)))))
        (if (> dl 1e-8)
          (progn
            (setq ds (list (/ (nth 0 ds) dl) (/ (nth 1 ds) dl) 0.0))
            (if (< (+ (* (nth 0 ds) (- (nth 0 ep) (nth 0 sp)))
                      (* (nth 1 ds) (- (nth 1 ep) (nth 1 sp)))) 0.0)
              (setq tmp sp sp ep ep tmp))
            (setq u  (list (/ (- (nth 0 ep) (nth 0 sp)) L)
                           (/ (- (nth 1 ep) (nth 1 sp)) L) 0.0)
                  n0 (list (- (nth 1 u)) (nth 0 u) 0.0)
                  pA (list (+ (nth 0 sp) (* (nth 0 u) (* 0.5 L)) (* (nth 0 n0) 1.0))
                           (+ (nth 1 sp) (* (nth 1 u) (* 0.5 L)) (* (nth 1 n0) 1.0)) 0.0)
                  pB (list (+ (nth 0 sp) (* (nth 0 u) (* 0.5 L)) (- (nth 0 n0)))
                           (+ (nth 1 sp) (* (nth 1 u) (* 0.5 L)) (- (nth 1 n0))) 0.0))
            ;; 外侧法向 = 离源线更远的方向
            (if (< (dt:cx-yxb-pt-line-dist pA ss2 ds)
                   (dt:cx-yxb-pt-line-dist pB ss2 ds))
              (setq n0 (list (- (nth 0 n0)) (- (nth 1 n0)) 0.0)))
            (setq plans (cons (list sp u n0 L) plans))
            )
          (princ "\n【压线板】源线零长, 跳过。"))
      (princ (strcat "\n【压线板】源线 " (itoa nsrc) " 该侧无直壁段: "
                     "弧段 " (itoa n-arc) " 个(弧形段暂不放置), "
                     "与源线不平行 " (itoa n-notpar) " 段, "
                     "不在选定侧 " (itoa n-side) " 段, "
                     "垂距不符 " (itoa n-dist) " 段"
                     (if dmin
                       (strcat "(最近中点垂距偏差 " (rtos dmin 2 2)
                               "mm, 容差 0.5; 偏差大请核对 出线槽偏移 参数)")
                       "(壁层无非零长直段: 检查 CX 层是否已生成通道壁)"))))
    )
  )
  (reverse plans))

;; 放置(v11.2, 删源线后调用): 重合线中点(定位点 = 与白线/源线的交界点)
;; 沿壁按 gap 均匀分布, 整组关于壁居中(两端留白相等, 图5 参考排布);
;; 不做碰撞判断(v10.7 用户定案)。plans = ((sp u n0 L) ...), 返回放置总数。
(defun dt:cx-yxb-place (plans gap / doc lay o n-old placed pn sp u n0 L
                            span n margin i d p-base)
  ;; 间距 <10 视为误填按 125 处理(防异常配置死循环); 每壁上限 100 幅。
  ;; 卡死根因已在 v11.2 于 find-wall 处根治, 此处 while 为纯算术有界循环。
  (if (or (null gap) (< gap 10.0))
    (progn (princ "\n【压线板】间距参数无效, 已按 125mm 处理。")
           (setq gap 125.0)))
  (setq placed 0)
  (cond
    ((null plans)
     (princ "\n【压线板】无可放置的壁(规划为空)。"))
    (T
     (setq doc (vla-get-activedocument (vlax-get-acad-object)))
     ;; v11.2: 内联建层(原调 dt:ensure-layer —— 本文件并未定义该函数,
     ;;        单独 APPLOAD cx_runner 运行到此必报 no function definition)
     ;; v11.8: 颜色 4→84(深绿, 与 LS 青 4 区分); 已存在也校正为登记值
     (if (null (tblsearch "LAYER" "YXB"))
       (progn
         (setq lay (vla-add (vla-get-layers doc) "YXB"))
         (vla-put-color lay 84))
       (progn
         (setq lay (vla-item (vla-get-layers doc) "YXB"))
         (if (/= (vla-get-color lay) 84)
           (vla-put-color lay 84))))
     (setq n-old 0)
     (foreach o (dt:layer-vlas "YXB")
       (vl-catch-all-apply 'vla-delete (list o))
       (setq n-old (1+ n-old)))
     (if (> n-old 0) (princ (strcat "\n【压线板】已清理旧实例 " (itoa n-old) " 个。")))
     (princ (strcat "\n【压线板】开始放置: 壁 " (itoa (length plans))
                    " 条, 间距 " (rtos gap 2 1) "mm..."))
     (foreach pn plans
       (setq sp (car pn) u (cadr pn) n0 (caddr pn) L (cadddr pn)
             span (- L 16.6))          ; 重合线中点可行程(两端各让 8.3)
       (cond
         ((<= span 0.0)
          (princ (strcat "\n【压线板】壁长 " (rtos L 2 1) " < 板高 16.6, 跳过。")))
         (T
          (setq n (1+ (fix (/ span gap))))
          (if (> n 100)
            (progn
              (setq n 100)
              (princ "\n【压线板】警告: 该壁已达 100 幅上限, 剩余截断。")))
          ;; 整组居中: 首末中点距壁两端留白相等
          (setq margin (/ (- span (* (1- n) gap)) 2.0))
          (if (< margin 0.0) (setq margin 0.0))
          (setq i 0)
          (while (< i n)
            (setq d (+ margin (* i gap))   ; 重合线起点距壁起点
                  p-base (list (+ (nth 0 sp) (* (nth 0 u) d))
                               (+ (nth 1 sp) (* (nth 1 u) d)) 0.0))
            (dt:cx-yxb-draw p-base u n0 "YXB")
            (setq placed (1+ placed) i (1+ i))))))
     (princ (strcat "\n【压线板】完成: 共放置 " (itoa placed) " 幅(中点间距 "
                    (rtos gap 2 1) "mm, 整组居中, 无碰撞判断)。"))))
  placed)
;; 点到无限直线的距离(lp = 线上一点, ld = 单位方向)
(defun dt:cx-yxb-pt-line-dist (pt lp ld / vx vy t-)
  (setq vx (- (nth 0 pt) (nth 0 lp))
        vy (- (nth 1 pt) (nth 1 lp))
        t- (+ (* vx (nth 0 ld)) (* vy (nth 1 ld))))
  (sqrt (+ (* (- vx (* t- (nth 0 ld))) (- vx (* t- (nth 0 ld))))
           (* (- vy (* t- (nth 1 ld))) (- vy (* t- (nth 1 ld)))))))

;; 壁实体 → 段候选列表 ((sp ep is-arc) ...)(v11.3):
;;   AcDbLine = 整条一段(直); AcDbArc = 一段标弧; LWPolyline/2dPolyline/
;;   3D Polyline = 按曲线参数逐段拆(endparam 即段数), 凸度≠0 段标弧,
;;   3D 折线 getbulge 抛错 → 按直段处理(与 wx 采样函数同款双判惯用法)
(defun dt:cx-yxb-segs-of (o / oname ep n i p0 p1 b out)
  (setq oname (vl-catch-all-apply 'vla-get-objectname (list o)))
  (cond
    ((vl-catch-all-error-p oname) nil)
    ((= oname "AcDbLine")
     (list (list (vlax-curve-getstartpoint o) (vlax-curve-getendpoint o) nil)))
    ((= oname "AcDbArc")
     (list (list (vlax-curve-getstartpoint o) (vlax-curve-getendpoint o) T)))
    ((member oname '("AcDb2dPolyline" "AcDbPolyline" "AcDb3dPolyline"))
     (setq ep (vl-catch-all-apply 'vlax-curve-getendparam (list o)))
     (cond
       ((or (vl-catch-all-error-p ep) (not (numberp ep))) nil)
       (T
        (setq n (fix (+ ep 1e-4)) i 0 out nil)
        (while (< i n)
          (setq p0 (vl-catch-all-apply 'vlax-curve-getpointatparam (list o (float i)))
                p1 (vl-catch-all-apply 'vlax-curve-getpointatparam
                       (list o (+ (float i) 1.0))))
          (if (and (not (vl-catch-all-error-p p0)) p0
                   (not (vl-catch-all-error-p p1)) p1)
            (progn
              (setq b (vl-catch-all-apply 'vla-getbulge (list o i)))
              (setq out (cons (list p0 p1
                              (if (and (not (vl-catch-all-error-p b)) (numberp b)
                                       (> (abs b) 1e-9))
                                T nil))
                        out))))
          (setq i (1+ i)))
        out)))
    (T nil)))

;; 找源线选定侧的壁直段(v11.3, 替代 v11.2 find-wall):
;;   扫描壁层实体并拆段(PL 多段线画的直壁自本版起支持); 直段条件不变:
;;   与源线弦向平行、中点垂距 ≈ slot-dist、中点在选定侧(Left/Right 按
;;   源线 S→E, 排除源线自身)。
;;   返回 (直段列表 弧段数 不平行数 侧不符数 垂距不符数 垂距最小偏差)
(defun dt:cx-yxb-find-walls (src slot-layer src-enames side slot-dist /
                             ss2 ee2 ds dl o segs sp ep m vd vl dd dderr
                             sidev pieces n-arc n-notpar n-side n-dist dmin)
  (setq ss2 (vlax-curve-getstartpoint src)
        ee2 (vlax-curve-getendpoint src)
        ss2 (list (nth 0 ss2) (nth 1 ss2) 0.0)
        ee2 (list (nth 0 ee2) (nth 1 ee2) 0.0)
        ds  (list (- (nth 0 ee2) (nth 0 ss2)) (- (nth 1 ee2) (nth 1 ss2)) 0.0)
        dl  (sqrt (+ (* (nth 0 ds) (nth 0 ds)) (* (nth 1 ds) (nth 1 ds))))
        pieces nil n-arc 0 n-notpar 0 n-side 0 n-dist 0 dmin nil)
  (if (> dl 1e-8)
    (progn
      (setq ds (list (/ (nth 0 ds) dl) (/ (nth 1 ds) dl) 0.0))
      (foreach o (dt:layer-vlas slot-layer)
        (if (not (dt:excluded-p o src-enames))
          (foreach seg (dt:cx-yxb-segs-of o)
            (cond
              ((caddr seg) (setq n-arc (1+ n-arc)))
              (T
               (setq sp (list (nth 0 (car seg)) (nth 1 (car seg)) 0.0)
                     ep (list (nth 0 (cadr seg)) (nth 1 (cadr seg)) 0.0)
                     m  (list (* 0.5 (+ (nth 0 sp) (nth 0 ep)))
                              (* 0.5 (+ (nth 1 sp) (nth 1 ep))) 0.0)
                     vd (list (- (nth 0 ep) (nth 0 sp)) (- (nth 1 ep) (nth 1 sp)) 0.0)
                     vl (sqrt (+ (* (nth 0 vd) (nth 0 vd)) (* (nth 1 vd) (nth 1 vd)))))
               (if (> vl 1e-8)
                 (progn
                   (setq vd (list (/ (nth 0 vd) vl) (/ (nth 1 vd) vl) 0.0)
                         dd (- (* (nth 0 ds) (nth 1 vd)) (* (nth 1 ds) (nth 0 vd))))
                   (cond
                     ;; 不平行
                     ((>= (abs dd) 1e-4) (setq n-notpar (1+ n-notpar)))
                     (T
                      ;; 选定侧
                      (setq sidev (- (* (nth 0 ds) (- (nth 1 m) (nth 1 ss2)))
                                     (* (nth 1 ds) (- (nth 0 m) (nth 0 ss2)))))
                      (cond
                        ((not (or (and (= (strcase side) "LEFT")  (> sidev 0.0))
                                  (and (= (strcase side) "RIGHT") (< sidev 0.0))))
                         (setq n-side (1+ n-side)))
                        (T
                         ;; 中点垂距 ≈ slot-dist
                         (setq dderr (abs (- (dt:cx-yxb-pt-line-dist m ss2 ds) slot-dist)))
                         (if (or (null dmin) (< dderr dmin)) (setq dmin dderr))
                         (cond
                           ((< dderr 0.5) (setq pieces (cons (list sp ep) pieces)))
                            (T (setq n-dist (1+ n-dist)))))))))))))))))
  (list pieces n-arc n-notpar n-side n-dist dmin))


;; ============================================================================
;; 参数对话框 —— 与主脚本 flb_runner 的对话框相互独立:
;; 对话框名 dt_cx_param / dcl 文件 cx_runner.dcl / 回调函数均不同名,
;; 两脚本同时加载互不覆盖。
;; ============================================================================

;; 内置 DCL 源文本(自动生成 cx_runner.dcl, 保证界面 100% 可用)
(defun dt:cx-dcl-lines ( / )
  (list
    "dt_cx_param : dialog {"
    "  label = \"出线槽参数设置\";"
    "  : boxed_column {"
    "    label = \"基本设置\";"
    "    : row {"
    "      : edit_box { key = \"cx_dist\"; label = \"出线槽偏移:\"; edit_width = 10; }"
    "      : edit_box { key = \"cx_extend\"; label = \"出线槽延长:\"; edit_width = 10; }"
    "    }"
    "    : row {"
    "      : edit_box { key = \"cx_fillet_r_small\"; label = \"出线槽小圆角R:\"; edit_width = 10; }"
    "      : edit_box { key = \"cx_fillet_r_large\"; label = \"出线槽大圆角R:\"; edit_width = 10; }"
    "    }"
    "    : row {"
    "      : edit_box { key = \"cx_yxb_gap\"; label = \"压线板间距:\"; edit_width = 10; }"
    "    }"
    "  }"
    "  : row {"
    "    : button { key = \"reset\"; label = \"恢复默认\"; width = 10; }"
    "    spacer;"
    "    ok_button;"
    "    cancel_button;"
    "  }"
    "}"))

;; 把内置 DCL 源文本写入文件 path(返回 path; 失败返回 nil)
;; v9.8: 由 dt:write-dcl 改名 dt:cx-write-dcl —— 与主脚本同名函数体不同
;; (此处写出本脚本的 dt:cx-dcl-lines 源), 三脚本同加载时同名不同体的
;; 函数互相覆盖会导致主脚本对话框写错内容(坑#46 同类)
(defun dt:cx-write-dcl (path / f ln)
  (setq f (open path "w"))
  (if f
    (progn
      ;; v10.3: 写中途异常也保证 close(半截 dcl 由对话框链的 catch 提示,
      ;;   不滞留句柄)
      (vl-catch-all-apply
        '(lambda ( ) (foreach ln (dt:cx-dcl-lines) (write-line ln f)))
        nil)
      (close f)
      path)
    nil))

;; 查找对话框文件路径: **确定性目录**——优先 dt_start 注入的 *dt-script-dir*,
;; 无 dt_start 时写 TEMP。v2.0 重写: 删除 findfile 候选链(多副本环境下会
;; 命中其它目录的同名旧副本)。总是覆盖生成最新 cx_runner.dcl。
(defun dt:cx-find-dcl ( / )
  (if (and *dt-script-dir* (/= *dt-script-dir* ""))
    (dt:cx-write-dcl (strcat *dt-script-dir* "\\cx_runner.dcl"))
    (dt:cx-write-dcl (strcat (getenv "TEMP") "\\cx_runner_tmp.dcl"))))

;; 读取编辑框数值: 空/非法输入时返回默认值 def
;; v10.1: atof 对垃圾串静默返回 0(如 "abc" -> 0.0), 参数会被悄悄改成 0;
;;        改用 distof —— 非法输入返回 nil 可识别, 回退默认值(坑 #54)
(defun dt:get-num (key def / s v)
  (setq s (get_tile key)
        v (if (and s (/= s "")) (distof s) nil))
  (if v v def))

;; 恢复默认参数到对话框(恢复默认按钮回调; v10.0 = 恢复 ini 配置的默认值,
;; 先重读配置实现"改 ini 后点恢复默认立即生效"; 只刷控件, 确定才生效)
(defun dt:cx-param-reset ( / p)
  (setq *dt-cx-cfg* (dt:cx-cfg-read (strcat (dt:cx-cfg-dir) "\\cx_runner.ini")))
  (foreach p dt:cx-param-table
    (set_tile (car p) (rtos (dt:cx-param-default (car p)) 2 2))))

;; 应用对话框值到全局参数(确定按钮回调; 空/非法输入回退当前值);
;; v10.0: 应用后自动保存记忆(取消不会触发本回调, 天然"确定才记忆")
(defun dt:cx-param-apply ( / p v)
  (foreach p dt:cx-param-table
    (setq v (dt:get-num (car p) (eval (cadr p))))
    ;; v10.3: 负值校验 —— 距离/半径类参数 <0 回退当前值(负值会画出退化几何)
    (if (< v 0.0) (setq v (eval (cadr p))))
    (set (cadr p) v))
  (dt:cx-mem-save))

;; 弹出出线槽参数对话框
;; 返回: T=用户点"确定"(参数已应用到全局变量), nil=取消/加载失败
(defun dt:cx-param-dialog ( / dcl-file dcl-id result p)
  (setq *dt-cx-cfg* (dt:cx-cfg-read (strcat (dt:cx-cfg-dir) "\\cx_runner.ini")))
  (setq dcl-file (dt:cx-find-dcl))
  (if (null dcl-file)
    (progn
      (princ "\n【界面】无法生成对话框文件(磁盘权限不足?), 界面不可用。")
      nil)
    (progn
      ;; v10.3: load_dialog 对损坏 dcl 是抛错而非返回 nil, 包 catch;
      ;;   start_dialog 同理 —— 保证 unload_dialog 必被执行(对话框句柄不滞留)
      (setq dcl-id (vl-catch-all-apply 'load_dialog (list dcl-file)))
      (if (or (vl-catch-all-error-p dcl-id) (null dcl-id))
        (progn
          (princ "\n【界面】对话框文件加载失败。")
          nil)
        (progn
          (if (new_dialog "dt_cx_param" dcl-id)
            (progn
              ;; 预填当前参数值
              (foreach p dt:cx-param-table
                (set_tile (car p) (rtos (eval (cadr p)) 2 2)))
              ;; 控件回调
              (action_tile "reset" "(dt:cx-param-reset)")
              (action_tile "accept" "(dt:cx-param-apply)(done_dialog 1)")
              (action_tile "cancel" "(done_dialog 0)")
              (setq result (vl-catch-all-apply 'start_dialog nil))
              (unload_dialog dcl-id)
              (if (and (not (vl-catch-all-error-p result)) (= result 1)) T nil))
            (progn
              (unload_dialog dcl-id)
              (princ "\n【界面】对话框初始化失败。")
              nil)))))))

;; 命令 SLOTPARAM: 弹出参数设置对话框(只修改参数, 不执行)
(defun c:CXPARAM ( / )
  (if (dt:cx-param-dialog)
    (princ (strcat "\n出线槽参数已保存: 偏移 " (rtos *dt-cx-dist* 2 2)
                   ", 延长 " (rtos *dt-cx-extend* 2 2)
                   ", 小圆角 " (rtos *dt-cx-fillet-r-small* 2 2)
                   ", 大圆角 " (rtos *dt-cx-fillet-r-large* 2 2) "。"))
    (princ "\n已取消, 参数未修改。"))
  (princ))

;; ============================================================================
;; 主命令 SLOT —— 在命令行输入 SLOT 即可执行
;; ============================================================================


;; 兼容旧命令别名
(defun c:SLOTPARAM ( ) (c:CXPARAM))
(defun c:SLOT ( ) (c:CX))
(defun c:CX ( / *error* cx-dist yxb-side)
  ;; ---- 内部错误处理: 出错或按 ESC 中断时给出友好提示 ----
  ;; v10.3: 兜底闭合可能悬挂的 UNDO 组(流程中多处 UNDO BE/E, 出错时
  ;;   End 分支可能未走到; 无开放组时该调用无副作用, catch 双保险)
  (defun *error* (msg)
    (vl-catch-all-apply '(lambda ( ) (dt:cx-undo-end)))
    (princ (strcat "\n程序已停止: " (if msg msg "用户按 ESC 取消")))
    (princ))
  ;; 先弹参数框(确定后参数已应用; 取消则中止; 弹框后再读参数, 防滞后一轮)
  (if (null (dt:cx-param-dialog))
    (princ "\n已取消, 未执行出线槽。")
    (progn
      (setq cx-dist *dt-cx-dist*)
      (if (null (tblsearch "LAYER" "CX"))
        (princ "\n【提示】图层 \"CX\" 不存在, 请先在该图层画好出线槽源线再运行。")
        (progn
          ;; v10.5: 压线板贴壁侧选择(每次运行时询问)
          ;; v11.7: 增内壁(I)/外壁(O) —— 曲折出线槽按相连源线投票整圈一致
          ;; 取侧; 左/右壁仍按单条源线方向(直线出线槽沿用)
          (initget "Inner Outer Left Right")
          (setq yxb-side (getkword "\n压线板贴出线槽哪一侧? [内壁(I)/外壁(O)/左壁(L)/右壁(R)] <左壁>: "))
          (if (null yxb-side) (setq yxb-side "Left"))
          (dt:cx-process "CX" "CX" cx-dist yxb-side)
          (princ "\n【完成】出线槽流程结束。")))))
  (princ))  ; 静默退出, 不打印返回结果

;;; 加载时在命令行输出提示
(dt:cx-cfg-boot)
(princ (strcat "\n出线槽工具已加载 " *dt-cx-ver* ": CX=执行 / CXPARAM=参数。"))
(princ)
