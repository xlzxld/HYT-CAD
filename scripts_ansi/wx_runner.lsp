;;; ============================================================================
;;; 热流道自动化系统 - 外协加工与尺寸数据测量工具 (wx_runner.lsp)
;;;
;;; 功能:
;;;   1. 分流板(FLB)最长与最宽尺寸自动提取 (c:FLBSZ / c:FLBSIZE)
;;;      - 优先自动扫描 FLB 图层；未找到或未闭合时自动转入手动框选模式
;;;      - 双引擎闭合区域校验: 原生 ACIS Region 面域引擎 + 0.5mm 容差端点拓扑度数引擎
;;;      - AABB + OBB 最佳外包矩形算法，精准计算最长边(Length)与最宽边(Width)
;;;      - 测量结果自动写入 Windows 剪贴板 (如 "350x180"，可直接 Ctrl+V 粘贴进下料单)
;;;      - 交互式确认后在 FLB_BOX 图层绘制包络矩形与长宽标注(字高>=15)
;;;   2. 线切割外协出图 (c:XQG)
;;;      - 自动提取闭合 FLB 轮廓，未闭合转手动框选并校验闭合度
;;;      - 跨图纸复制到新建或追加汇总 DWG，自动 AABB 向右平铺(安全间距 50mm)防覆盖
;;;      - 工件上方自动标注原图纸文件名(字高 20，宋体/仿宋/黑体/Standard)
;;;   3. 精雕外协出图 (c:JD)
;;;      - 自动提取除 JT 和 CX 以外的所有加工曲线，无指定图层则手动框选
;;;      - 跨图纸复制到目标 DWG 并自动平铺防覆盖，上方标注图纸文件名(字高 20)
;;;   4. 数据图纸生成 (c:SJTZ)
;;;      - 提取加工曲线，支持鼠标自由拖动或输入位移交互式复制
;;;      - 图形最右侧 +30 位置自动生成规范化双列信息文本块(客户/模具/中心距/分流板/热咀/出线/日期)
;;;      - 日期全自动读取系统时间生成，各字段支持记忆与 CAD 双击编辑
;;;
;;; 版本: v2.0
;;; 平台: AutoCAD 2007 ~ 2026 (AutoLISP + COM ActiveX)
;;; ============================================================================

(vl-load-com)

;; 会话级全局记忆
(setq *dt-outsource-target-dwg* nil) ;; 目标汇总图纸通用记忆
(setq *dt-xqg-target-dwg* nil)       ;; 线切割目标图纸路径记忆
(setq *dt-jd-target-dwg* nil)        ;; 精雕目标图纸路径记忆
(setq *dt-sjtz-kh* nil)              ;; 数据图纸客户名称记忆
(setq *dt-sjtz-mj* nil)              ;; 数据图纸模具编号记忆
(setq *dt-sjtz-zxj* nil)             ;; 数据图纸中心距记忆
(setq *dt-sjtz-flb* nil)             ;; 数据图纸分流板规格记忆
(setq *dt-sjtz-rz* nil)              ;; 数据图纸热咀规格记忆
(setq *dt-sjtz-cx* nil)              ;; 数据图纸出线记忆

;; ============================================================================
;; 一、公共几何与环境基础函数 (自包含库, 跨脚本同名逐字一致, 坑 #46)
;; ============================================================================

;; 当前文档模型空间(集中获取, 避免各函数重复拼 vla-get 链)
(defun dt:ms ()
  (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object))))

;; 选择集 -> 图元名列表
(defun dt:ss->list (ss / i lst)
  (setq i 0 lst nil)
  (repeat (sslength ss)
    (setq lst (cons (ssname ss i) lst)
          i (1+ i)))
  (reverse lst))

;; 保证图层存在, 若不存在则创建; 若大小写不一致则自动纠正(坑 #29)
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

;; vla-getboundingbox 在不同 CAD 版本/运行上下文下, 传出值可能是 variant
;; 也可能是 raw safearray(v10.0 踩坑: 2024 上是 variant, variant-value 解出
;; safearray; 低版本或纯 LISP 环境下可能已是 safearray)。
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

;; 曲线类型判定(支持 LINE/ARC/LWPOLYLINE/POLYLINE/SPLINE/CIRCLE/ELLIPSE)
(defun dt:sz-curve-p (obj / typ oname)
  (if (= (type obj) 'ENAME)
    (setq typ (cdr (assoc 0 (entget obj))))
    (progn
      (setq oname (vl-catch-all-apply 'vla-get-objectname (list obj)))
      (if (vl-catch-all-error-p oname)
        (setq typ nil)
        (setq typ (cond
                    ((= oname "AcDbLine") "LINE")
                    ((= oname "AcDbArc") "ARC")
                    ((= oname "AcDbPolyline") "LWPOLYLINE")
                    ((= oname "AcDb2dPolyline") "POLYLINE")
                    ((= oname "AcDbSpline") "SPLINE")
                    ((= oname "AcDbCircle") "CIRCLE")
                    ((= oname "AcDbEllipse") "ELLIPSE")
                    (T nil))))))
  (and typ (member typ '("LINE" "ARC" "LWPOLYLINE" "POLYLINE" "SPLINE" "CIRCLE" "ELLIPSE"))))

;; 过滤纯曲线图元列表(统一转为 VLA 对象)
(defun dt:sz-curves-only (ents / e o r)
  (setq r nil)
  (foreach e ents
    (setq o (if (= (type e) 'ENAME) (vlax-ename->vla-object e) e))
    (if (dt:sz-curve-p o)
      (setq r (cons o r))))
  (reverse r))

;; ============================================================================
;; 二、分流板尺寸提取与闭合分析核心
;; ============================================================================

;; Windows 剪贴板写入: 优先 ActiveX htmlfile, 失败回退原生 clip.exe
(defun dt:sz-copy-clip (str / html r)
  (setq r (vl-catch-all-apply
            '(lambda ( / html)
               (setq html (vlax-create-object "htmlfile"))
               (if html
                 (progn
                   (vlax-invoke
                     (vlax-get (vlax-get html 'ParentWindow) 'ClipBoardData)
                     'SetData "Text" str)
                   (vlax-release-object html)
                   T)
                 nil))
            nil))
  (if (or (vl-catch-all-error-p r) (null r))
    (vl-catch-all-apply
      '(lambda ( )
         (startapp (strcat "cmd.exe /c <nul set /p=\"" str "\" | clip")))
      nil))
  T)

;; 曲线采样点提取(用于 OBB/AABB 包络范围计算)
(defun dt:sz-curve-sample-pts (o / oname pts sp ep len)
  (setq pts nil
        oname (vla-get-objectname o))
  (cond
    ((or (= oname "AcDbLine") (= oname "AcDbPolyline"))
     (setq sp (vlax-curve-getstartpoint o)
           ep (vlax-curve-getendpoint o))
     (setq pts (list (list (car sp) (cadr sp))
                     (list (car ep) (cadr ep)))))
    (T
     (setq len (vl-catch-all-apply 'vlax-curve-getdistatparam
                                  (list o (vlax-curve-getendparam o))))
     (if (and (not (vl-catch-all-error-p len)) (numberp len) (> len 0.0))
       (setq pts (list (vlax-curve-getstartpoint o)
                       (vlax-curve-getpointatdist o (* len 0.25))
                       (vlax-curve-getpointatdist o (* len 0.5))
                       (vlax-curve-getpointatdist o (* len 0.75))
                       (vlax-curve-getendpoint o))
             pts (mapcar '(lambda (p) (list (car p) (cadr p))) pts))
       (progn
         (setq sp (vlax-curve-getstartpoint o)
               ep (vlax-curve-getendpoint o))
         (setq pts (list (list (car sp) (cadr sp))
                         (list (car ep) (cadr ep))))))))
  pts)

;; 提取直线的方向角(归一化到 [0, pi/2))
(defun dt:sz-curve-angle (o / sp ep dx dy a)
  (if (= (vla-get-objectname o) "AcDbLine")
    (progn
      (setq sp (vlax-curve-getstartpoint o)
            ep (vlax-curve-getendpoint o)
            dx (- (car ep) (car sp))
            dy (- (cadr ep) (cadr sp))
            a  (atan dy dx))
      (while (< a 0.0) (setq a (+ a pi)))
      (while (>= a (/ pi 2.0)) (setq a (- a (/ pi 2.0))))
      a)
    nil))

;; 角度列表容差去重
(defun dt:sz-uniq-angles (angs / r a found x)
  (setq r nil)
  (foreach a angs
    (setq found nil)
    (foreach x r
      (if (< (abs (- a x)) 0.01) (setq found T)))
    (if (null found) (setq r (cons a r))))
  (reverse r))

;; 2D 点旋转
(defun dt:sz-rot-pt (pt ang / ca sa x y)
  (setq ca (cos ang) sa (sin ang)
        x  (car pt)   y  (cadr pt))
  (list (- (* x ca) (* y sa))
        (+ (* x sa) (* y ca))))

;; 双引擎闭合区域判定: Engine 1 (Region 面域) + Engine 2 (端点容差拓扑度数)
(defun dt:sz-check-closed (cands / o oname sa res regs is-closed pts sp ep p clus found r)
  (setq is-closed nil)
  (cond
    ((null cands) nil)
    ;; 单图元分支
    ((= (length cands) 1)
     (setq o (car cands)
           oname (vla-get-objectname o))
     (cond
       ((vl-position oname '("AcDbCircle" "AcDbEllipse"))
        T)
       (T
        (setq res (vl-catch-all-apply 'vla-get-closed (list o)))
        (and (not (vl-catch-all-error-p res))
             (or (= res :vlax-true) (= res -1) (< res 0))))))
    ;; 多图元分支
    (T
     ;; 引擎 1: AutoCAD 原生 Region 面域建模引擎
     (setq sa (vlax-make-safearray vlax-vbObject (cons 0 (1- (length cands)))))
     (vlax-safearray-fill sa cands)
     (setq res (vl-catch-all-apply 'vla-addregion (list (dt:ms) sa)))
     (if (and (not (vl-catch-all-error-p res)) res)
       (progn
         (setq regs (vlax-safearray->list (vlax-variant-value res)))
         (if (and regs (> (length regs) 0))
           (progn
             (foreach r regs (vl-catch-all-apply 'vla-delete (list r)))
             (setq is-closed T)))))
     ;; 引擎 2: 容差端点拓扑度数判定(0.5mm 容差缝隙匹配)
     (if (null is-closed)
       (progn
         (setq pts nil)
         (foreach o cands
           (setq sp (vl-catch-all-apply 'vlax-curve-getstartpoint (list o)))
           (if (not (vl-catch-all-error-p sp))
             (setq pts (cons (list (car sp) (cadr sp)) pts)))
           (setq ep (vl-catch-all-apply 'vlax-curve-getendpoint (list o)))
           (if (not (vl-catch-all-error-p ep))
             (setq pts (cons (list (car ep) (cadr ep)) pts))))
         (if (and pts (>= (length pts) 4) (= (rem (length pts) 2) 0))
           (progn
             (setq clus nil)
             (foreach p pts
               (setq found nil)
               (setq clus
                     (mapcar
                       '(lambda (c)
                          (if (and (null found) (<= (distance p (car c)) 0.5))
                            (progn (setq found T) (list (car c) (1+ (cadr c))))
                            c))
                       clus))
               (if (null found)
                 (setq clus (cons (list p 1) clus))))
             (setq is-closed T)
             (foreach c clus
               (if (< (cadr c) 2)
                 (setq is-closed nil)))))))
     is-closed)))

;; 包络尺寸计算(兼顾正交与倾斜最佳 OBB 包络盒)
(defun dt:sz-calc-box (cands / all-pts angs a pt rpt minx miny maxx maxy
                               dx dy area best-area best-ang best-box
                               aabb-area aabb-box rx0 ry0 rx1 ry1 len wid
                               p1 p2 p3 p4 o)
  (setq all-pts nil
        angs (list 0.0))
  (foreach o cands
    (setq all-pts (append (dt:sz-curve-sample-pts o) all-pts))
    (setq a (dt:sz-curve-angle o))
    (if a (setq angs (cons a angs))))
  (setq angs (dt:sz-uniq-angles angs))

  (setq best-area nil
        best-ang  0.0
        best-box  nil
        aabb-area nil
        aabb-box  nil)

  (foreach a angs
    (setq minx nil miny nil maxx nil maxy nil)
    (foreach pt all-pts
      (setq rpt (if (< (abs a) 1e-4) pt (dt:sz-rot-pt pt (- a))))
      (setq minx (if minx (min minx (car rpt)) (car rpt))
            miny (if miny (min miny (cadr rpt)) (cadr rpt)))
      (setq maxx (if maxx (max maxx (car rpt)) (car rpt))
            maxy (if maxy (max maxy (cadr rpt)) (cadr rpt))))
    (if (and minx miny maxx maxy)
      (progn
        (setq dx (- maxx minx)
              dy (- maxy miny)
              area (* dx dy))
        (if (< (abs a) 1e-4)
          (setq aabb-area area
                aabb-box (list dx dy minx miny maxx maxy 0.0)))
        (if (or (null best-area) (< area best-area))
          (setq best-area area
                best-ang  a
                best-box  (list dx dy minx miny maxx maxy a))))))

  ;; 若 AABB 面积与最佳 OBB 面积相差在 1% 以内，优先采用正交(0.0)
  (if (and aabb-box best-box
           (<= aabb-area (* (car aabb-box) (cadr aabb-box) 1.01)))
    (setq best-box aabb-box))

  (if best-box
    (progn
      (setq dx   (car best-box)
            dy   (cadr best-box)
            rx0  (caddr best-box)
            ry0  (cadddr best-box)
            rx1  (nth 4 best-box)
            ry1  (nth 5 best-box)
            a    (nth 6 best-box)
            len  (max dx dy)
            wid  (min dx dy))
      (if (< (abs a) 1e-4)
        (setq p1 (list rx0 ry0 0.0)
              p2 (list rx1 ry0 0.0)
              p3 (list rx1 ry1 0.0)
              p4 (list rx0 ry1 0.0))
        (setq p1 (append (dt:sz-rot-pt (list rx0 ry0) a) '(0.0))
              p2 (append (dt:sz-rot-pt (list rx1 ry0) a) '(0.0))
              p3 (append (dt:sz-rot-pt (list rx1 ry1) a) '(0.0))
              p4 (append (dt:sz-rot-pt (list rx0 ry1) a) '(0.0))))
      (list len wid p1 p2 p3 p4 a))
    nil))

;; 数值格式化(整数去小数点)
(defun dt:sz-fmt-num (val)
  (if (equal val (float (fix (+ val 1e-6))) 1e-3)
    (itoa (fix (+ val 1e-6)))
    (rtos val 2 2)))

;; 在 "FLB_BOX" 图层绘制外包矩形及长宽标注(字高>=15)
(defun dt:sz-draw-box-dim (p1 p2 p3 p4 / ms acad doc layers
                                         pts pl d12 d23
                                         pt-dim1 pt-dim2
                                         dim1 dim2 txt1 txt2)
  (setq acad   (vlax-get-acad-object)
        doc    (vla-get-activedocument acad)
        layers (vla-get-layers doc)
        ms     (vla-get-modelspace doc))
  ;; 1) 保证 FLB_BOX 图层存在(青色 4)
  (dt:ensure-layer layers "FLB_BOX" 4 "青色")

  ;; 2) 绘制包络矩形(轻量多段线)
  (setq pts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill pts (list (car p1) (cadr p1)
                                 (car p2) (cadr p2)
                                 (car p3) (cadr p3)
                                 (car p4) (cadr p4)))
  (setq pl (vl-catch-all-apply 'vla-addlightweightpolyline (list ms pts)))
  (if (and (not (vl-catch-all-error-p pl)) pl)
    (progn
      (vla-put-closed pl :vlax-true)
      (vla-put-layer pl "FLB_BOX"))
    (progn
      (vla-put-layer (vla-addline ms (vlax-3d-point p1) (vlax-3d-point p2)) "FLB_BOX")
      (vla-put-layer (vla-addline ms (vlax-3d-point p2) (vlax-3d-point p3)) "FLB_BOX")
      (vla-put-layer (vla-addline ms (vlax-3d-point p3) (vlax-3d-point p4)) "FLB_BOX")
      (vla-put-layer (vla-addline ms (vlax-3d-point p4) (vlax-3d-point p1)) "FLB_BOX")))

  ;; 3) 标注两边尺寸(字高 15.0)
  (setq d12 (distance p1 p2)
        d23 (distance p2 p3))

  ;; 边1 (p1 -> p2): 尺寸线置于外侧
  (if (> d12 1e-3)
    (progn
      (setq pt-dim1 (list (- (/ (+ (car p1) (car p2)) 2.0)
                             (* (- (cadr p2) (cadr p1)) (/ (max 30.0 (* 0.15 d23)) d12)))
                          (+ (/ (+ (cadr p1) (cadr p2)) 2.0)
                             (* (- (car p2) (car p1)) (/ (max 30.0 (* 0.15 d23)) d12)))
                          0.0))
      (setq dim1 (vl-catch-all-apply
                   'vla-adddimaligned
                   (list ms (vlax-3d-point p1) (vlax-3d-point p2) (vlax-3d-point pt-dim1))))
      (if (and (not (vl-catch-all-error-p dim1)) dim1)
        (progn
          (vla-put-layer dim1 "FLB_BOX")
          (vl-catch-all-apply 'vla-put-textheight (list dim1 15.0))
          (vl-catch-all-apply 'vla-put-arrowheadsize (list dim1 8.0)))
        (progn
          (setq txt1 (vl-catch-all-apply
                       'vla-addtext
                       (list ms (rtos d12 2 2) (vlax-3d-point pt-dim1) 15.0)))
          (if (and (not (vl-catch-all-error-p txt1)) txt1)
            (vla-put-layer txt1 "FLB_BOX"))))))

  ;; 边2 (p2 -> p3): 尺寸线置于外侧
  (if (> d23 1e-3)
    (progn
      (setq pt-dim2 (list (+ (/ (+ (car p2) (car p3)) 2.0)
                             (* (- (cadr p3) (cadr p2)) (/ (max 30.0 (* 0.15 d12)) d23)))
                          (- (/ (+ (cadr p2) (cadr p3)) 2.0)
                             (* (- (car p3) (car p2)) (/ (max 30.0 (* 0.15 d12)) d23)))
                          0.0))
      (setq dim2 (vl-catch-all-apply
                   'vla-adddimaligned
                   (list ms (vlax-3d-point p2) (vlax-3d-point p3) (vlax-3d-point pt-dim2))))
      (if (and (not (vl-catch-all-error-p dim2)) dim2)
        (progn
          (vla-put-layer dim2 "FLB_BOX")
          (vl-catch-all-apply 'vla-put-textheight (list dim2 15.0))
          (vl-catch-all-apply 'vla-put-arrowheadsize (list dim2 8.0)))
        (progn
          (setq txt2 (vl-catch-all-apply
                       'vla-addtext
                       (list ms (rtos d23 2 2) (vlax-3d-point pt-dim2) 15.0)))
          (if (and (not (vl-catch-all-error-p txt2)) txt2)
            (vla-put-layer txt2 "FLB_BOX"))))))
  T)

;; ============================================================================
;; 三、外协加工通用引擎 (目标图纸管理、AABB 自动平铺防覆盖、字体降级与图纸克隆)
;; ============================================================================

;; 系统变量安全读取(避免 nil 泄漏, 坑 #65)
(defun dt:sz-gets (name / r)
  (setq r (vl-catch-all-apply 'getvar (list name)))
  (cond
    ((vl-catch-all-error-p r) "")
    ((null r) "")
    ((= (type r) 'STR) r)
    (T (vl-prin1-to-string r))))

;; 全自动提取当前系统日期, 格式如 "2026.9.4" (无空格)
(defun dt:sz-get-date-str ( / cd s y m d)
  (setq cd (vl-catch-all-apply 'getvar (list "CDATE")))
  (if (and (not (vl-catch-all-error-p cd)) (numberp cd))
    (progn
      (setq s (rtos cd 2 6)
            y (substr s 1 4)
            m (itoa (atoi (substr s 5 2)))
            d (itoa (atoi (substr s 7 2))))
      (strcat y "." m "." d))
    "2026.9.4"))

;; 字符串按分隔符切分
(defun dt:sz-split (str del / pos res)
  (setq res nil)
  (while (setq pos (vl-string-search del str))
    (setq res (cons (substr str 1 pos) res)
          str (substr str (+ pos (1+ (strlen del))))))
  (setq res (cons str res))
  (reverse res))

;; 递归创建目录
(defun dt:sz-mkdir-p (dir / parts cur i)
  (setq dir (vl-string-translate "/" "\\" dir))
  (setq parts (dt:sz-split dir "\\"))
  (if parts
    (progn
      (setq cur (car parts)
            i 1)
      (while (< i (length parts))
        (setq cur (strcat cur "\\" (nth i parts)))
        (if (and (/= cur "") (null (findfile cur)))
          (vl-mkdir cur))
        (setq i (1+ i))))))

;; 从 wx_runner.ini (或 size_runner.ini 兼容) 读取配置节数值
(defun dt:sz-cfg-get (section key def-val / path res sec f ln p k vs)
  (setq path (findfile "wx_runner.ini"))
  (if (null path) (setq path (findfile "size_runner.ini")))
  (if (null path)
    (setq path (strcat (if (and (boundp '*dt-script-dir*) *dt-script-dir*)
                         *dt-script-dir*
                         "C:\\CAD")
                       "\\wx_runner.ini")))
  (setq res nil sec nil)
  (if (and path (findfile path))
    (vl-catch-all-apply
      '(lambda ( )
         (setq f (open path "r"))
         (if f
           (progn
             (while (and (null res) (setq ln (read-line f)))
               (setq ln (vl-string-trim " \t\r" ln))
               (cond
                 ((= ln "") nil)
                 ((member (substr ln 1 1) '(";" "#")) nil)
                 ((= (substr ln 1 1) "[")
                  (setq sec (vl-string-trim " \t[]" (substr ln 2))))
                 ((and sec (equal (strcase sec) (strcase section)))
                  (setq p (vl-string-search "=" ln))
                  (if p
                    (progn
                      (setq k (vl-string-trim " \t" (substr ln 1 p)))
                      (if (equal (strcase k) (strcase key))
                        (setq vs (vl-string-trim " \t" (substr ln (+ p 2)))
                              res vs)))))))
             (close f)
             (setq f nil))))))
  (if f (progn (vl-catch-all-apply 'close (list f)) (setq f nil)))
  (if (or (null res) (= res "")) def-val res))

;; 自动检测下一个可用递增文件名 (如 09.04_1.dwg, 09.04_2.dwg)
(defun dt:sz-next-avail-name (month-dir base-name / idx fname full)
  (setq idx 1
        fname (strcat base-name "_" (itoa idx) ".dwg")
        full  (strcat month-dir "\\" fname))
  (while (findfile full)
    (setq idx (1+ idx)
          fname (strcat base-name "_" (itoa idx) ".dwg")
          full  (strcat month-dir "\\" fname)))
  fname)

;; 全自动计算外协目标图纸全路径并创建对应年份和月份目录
;; 规则: {root}\{YY}\{MM}\{MM}.{DD}.dwg
;; 若已存在 09.04.dwg，命令行直接回车默认追加平铺；输入 N 则自动递增创建 09.04_1.dwg 并设为后续目标
(defun dt:sz-auto-target-path (branch-name / def-root root cd s yy mm dd
                                           year-dir month-dir base-name def-path
                                           cur-mem next-fname choice target)
  (setq def-root (strcat "C:\\Users\\5600\\Documents\\CAD\\" branch-name))
  (setq root (dt:sz-cfg-get branch-name "root" def-root))
  ;; 若 ini 中配置的路径盘符不存在，则自动降级到当前用户文档目录
  (if (and (wcmatch (strcase root) "*:*")
           (null (findfile (substr root 1 3))))
    (setq root (strcat (if (getenv "USERPROFILE") (getenv "USERPROFILE") "C:\\CAD")
                       "\\Documents\\CAD\\" branch-name)))
  (setq cd (vl-catch-all-apply 'getvar (list "CDATE")))
  (if (and (not (vl-catch-all-error-p cd)) (numberp cd))
    (setq s  (rtos cd 2 6)
          yy (substr s 3 2)
          mm (substr s 5 2)
          dd (substr s 7 2))
    (setq yy "26" mm "09" dd "04"))
  (setq year-dir  (strcat root "\\" yy)
        month-dir (strcat year-dir "\\" mm))
  ;; 自动补全各级目录
  (dt:sz-mkdir-p month-dir)

  (setq base-name (strcat mm "." dd)
        def-path  (strcat month-dir "\\" base-name ".dwg"))

  ;; 检查当前分支会话目标记忆
  (setq cur-mem (if (equal branch-name "线切割")
                  *dt-xqg-target-dwg*
                  *dt-jd-target-dwg*))

  (cond
    ;; 情况 1: 09.04.dwg 尚不存在，且当前无有效会话目标，直接作为首选目标 (零提示直接新建)
    ((and (null (findfile def-path)) (or (null cur-mem) (null (findfile cur-mem))))
      (setq target def-path))

    ;; 情况 2: 图纸已存在，提供命令行选项: 回车默认追加已有图纸，输入 N 自动递增新建
    (T
      (if (or (null cur-mem) (null (findfile cur-mem)))
        (setq cur-mem def-path))
      (setq next-fname (dt:sz-next-avail-name month-dir base-name))
      (initget "A N")
      (setq choice (getkword (strcat "\n【" branch-name "】目标图纸已存在: "
                                     (vl-filename-base cur-mem) ".dwg"
                                     "\n[追加(A)/新建为" next-fname "(N)] <A>: ")))
      (if (and choice (= (strcase choice) "N"))
        (setq target (strcat month-dir "\\" next-fname))
        (setq target cur-mem))))

  ;; 绑定并持久化到当前会话
  (if (equal branch-name "线切割")
    (setq *dt-xqg-target-dwg* target)
    (setq *dt-jd-target-dwg* target))
  target)

;; 智能将长文件名格式化为多行文字 (遇 -、_、+、空格 或超长时自动拆分并以 \P 换行连接)
(defun dt:sz-format-multiline (s / max-len len lines cur i ch l)
  (setq max-len 12) ; 每行建议字数
  (setq len (strlen s))
  (if (or (null s) (<= len max-len))
    s
    (progn
      (setq lines nil cur "" i 1)
      (while (<= i len)
        (setq ch (substr s i 1))
        (setq cur (strcat cur ch))
        (if (and (>= (strlen cur) 8) (member ch '("-" "_" "+" " " "/")))
          (progn
            (setq lines (cons cur lines))
            (setq cur ""))
          (if (>= (strlen cur) max-len)
            (progn
              (setq lines (cons cur lines))
              (setq cur ""))))
        (setq i (1+ i)))
      (if (/= cur "") (setq lines (cons cur lines)))
      (setq lines (reverse lines))
      (setq s "")
      (foreach l lines
        (setq s (if (= s "") l (strcat s "\\P" l))))
      s)))

;; 系统字体探测: 宋体 > 仿宋 > 黑体 依次降级
(defun dt:sz-get-font-face ( / windir)
  (setq windir (getenv "windir"))
  (if (null windir) (setq windir "C:\\Windows"))
  (cond
    ((findfile (strcat windir "\\Fonts\\simsun.ttc")) "宋体")
    ((findfile (strcat windir "\\Fonts\\simfang.ttf")) "仿宋")
    ((findfile (strcat windir "\\Fonts\\simhei.ttf")) "黑体")
    (T "宋体")))

;; 确保指定文档中存在外协专用文字样式 "DT_WX_STYLE" (带字体降级保护)
(defun dt:sz-ensure-style (doc / st-col st face err)
  (setq st-col (vla-get-textstyles doc))
  (setq st (vl-catch-all-apply 'vla-item (list st-col "DT_WX_STYLE")))
  (if (or (vl-catch-all-error-p st) (null st))
    (setq st (vl-catch-all-apply 'vla-add (list st-col "DT_WX_STYLE"))))
  (if (and (not (vl-catch-all-error-p st)) st)
    (progn
      (setq face (dt:sz-get-font-face))
      ;; 优先使用 COM 原生 vla-setfont 绑定系统中文字体(宋体/仿宋/黑体, 字符集 134=GB2312, 34=变宽)
      ;; 严禁使用 vla-put-fontfile 绑定 .ttc/.ttf 路径，否则 AutoCAD 会误作为形文件(.shx)解析并报「读取形文件出错」
      (setq err (vl-catch-all-apply 'vla-setfont (list st face :vlax-false :vlax-false 134 34)))
      (if (vl-catch-all-error-p err)
        (setq err (vl-catch-all-apply 'vla-setfont (list st "宋体" :vlax-false :vlax-false 134 34))))
      (if (vl-catch-all-error-p err)
        (setq err (vl-catch-all-apply 'vla-setfont (list st "SimSun" :vlax-false :vlax-false 134 34))))
      ;; 安全兜底：若系统无 TrueType 中文字体，回退至 AutoCAD 内置国标大字体
      (if (vl-catch-all-error-p err)
        (progn
          (vl-catch-all-apply 'vla-put-fontfile (list st "txt.shx"))
          (vl-catch-all-apply 'vla-put-bigfontfile (list st "gbcbig.shx"))))))
  "DT_WX_STYLE")

;; 在当前已打开的文档集合中按路径查找文档
(defun dt:sz-find-open-doc (path / acad docs full found p1 p2 d)
  (setq acad  (vlax-get-acad-object)
        docs  (vla-get-documents acad)
        p1    (strcase (vl-string-translate "/" "\\" path))
        found nil)
  (vlax-for d docs
    (setq full (vl-catch-all-apply 'vla-get-fullname (list d)))
    (if (and (not (vl-catch-all-error-p full)) full (/= full ""))
      (progn
        (setq p2 (strcase (vl-string-translate "/" "\\" full)))
        (if (= p1 p2) (setq found d)))))
  found)

;; 探测目标图纸中已有全部图元的总体外包盒 (用于计算向右平铺落点)
(defun dt:sz-doc-ms-bbox (doc / ms mn mx p minx miny maxx maxy o)
  (setq ms (vla-get-modelspace doc)
        minx nil miny nil maxx nil maxy nil)
  (vlax-for o ms
    (setq mn nil mx nil)
    (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx))))
      (progn
        (setq p (dt:rect-bb-pts mn))
        (setq minx (if minx (min minx (car p)) (car p))
              miny (if miny (min miny (cadr p)) (cadr p)))
        (setq p (dt:rect-bb-pts mx))
        (setq maxx (if maxx (max maxx (car p)) (car p))
              maxy (if maxy (max maxy (cadr p)) (cadr p))))))
  (if (and minx miny maxx maxy) (list minx miny maxx maxy) nil))

;; 提取热流道脚本自动化生成的有效加工曲线 (严格限定在 FLB, LS, RZ, DK, JRT 白名单)
(defun dt:sz-collect-auto-curves ( / ss ents cands e lay)
  (setq cands nil)
  (setq ss (ssget "X" '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
  (if ss
    (progn
      (setq ents (dt:ss->list ss))
      (foreach e ents
        (setq lay (strcase (cdr (assoc 8 (entget e)))))
        (if (member lay '("FLB" "LS" "RZ" "DK" "JRT"))
          (setq cands (cons (vlax-ename->vla-object e) cands))))
      (setq cands (reverse cands))))
  cands)

;; 将所选曲线克隆并输出到目标 DWG (自动向右平铺排版 + 多行文字宽度限制自动折行)
(defun dt:sz-export-to-dwg (cands title target-layer /
                            cur-doc acad docs target-path tgt-doc was-closed
                            ms-tgt existing-bb ins-x src-bb s-minx s-miny s-maxx s-maxy
                            off-x off-y sa r copied-objs new-obj tmp-dir tmp-dwg
                            w-res blk exp-res src-fname src-multiline part-w title-cx title-cy
                            title-w txt-obj)
  (setq cur-doc (vla-get-activedocument (vlax-get-acad-object))
        acad    (vlax-get-acad-object)
        docs    (vla-get-documents acad))

  ;; 1) 全自动计算并定位目标图纸全路径 (免弹窗选择)
  (setq target-path (dt:sz-auto-target-path title))
  (if (or (null target-path) (= target-path ""))
    (progn
      (princ (strcat "\n【" title "】未获取到有效目标图纸路径，操作已取消。"))
      nil)
    (progn
      ;; 2) 打开或创建目标文档
      (setq tgt-doc (dt:sz-find-open-doc target-path)
            was-closed nil)
      (if (null tgt-doc)
        (if (findfile target-path)
          (progn
            (setq tgt-doc (vl-catch-all-apply 'vla-open (list docs target-path))
                  was-closed T))
          (progn
            (setq tgt-doc (vl-catch-all-apply 'vla-add (list docs))
                  was-closed T)
            (if (and (not (vl-catch-all-error-p tgt-doc)) tgt-doc)
              (vl-catch-all-apply 'vla-saveas (list tgt-doc target-path))))))

      (if (or (null tgt-doc) (vl-catch-all-error-p tgt-doc))
        (progn
          (princ (strcat "\n【错误】无法打开或创建目标图纸: " target-path))
          nil)
        (progn
          (setq ms-tgt (vla-get-modelspace tgt-doc))
          ;; 确保文字样式存在
          (dt:sz-ensure-style tgt-doc)
          ;; 3) 扫描目标图纸现有图元包络盒(实现向右安全平铺，间距 150mm)
          (setq existing-bb (dt:sz-doc-ms-bbox tgt-doc))
          (if existing-bb
            (setq ins-x (+ (caddr existing-bb) 150.0)) ; 已有图形 maxX + 150.0
            (setq ins-x 0.0))

          ;; 4) 源图元包络盒与平移量计算
          (setq src-bb (dt:rect-bbox cands)
                s-minx (car src-bb)
                s-miny (cadr src-bb)
                s-maxx (caddr src-bb)
                s-maxy (cadddr src-bb)
                off-x  (- ins-x s-minx)
                off-y  (- 0.0 s-miny))

          ;; 5) 跨图纸克隆图元 (优先 CopyObjects, 异常回退 WBLOCK)
          (setq sa (vlax-make-safearray vlax-vbObject (cons 0 (1- (length cands)))))
          (vlax-safearray-fill sa cands)
          (setq r (vl-catch-all-apply 'vla-copyobjects (list cur-doc sa ms-tgt))
                copied-objs nil)
          (if (and (not (vl-catch-all-error-p r)) r)
            (setq copied-objs (vlax-safearray->list (vlax-variant-value r)))
            (progn
              ;; 回退方案: 临时 WBLOCK 导入后炸开
              (setq tmp-dir (getenv "TEMP"))
              (if (null tmp-dir) (setq tmp-dir "C:\\TEMP"))
              (setq tmp-dwg (strcat tmp-dir "\\_dt_wx_tmp.dwg"))
              (vl-catch-all-apply 'vl-file-delete (list tmp-dwg))
              (setq w-res (vl-catch-all-apply 'vla-wblock (list cur-doc tmp-dwg sa)))
              (if (and (not (vl-catch-all-error-p w-res)) (findfile tmp-dwg))
                (progn
                  (setq blk (vl-catch-all-apply
                              'vla-insertblock
                              (list ms-tgt (vlax-3d-point 0 0 0) tmp-dwg 1.0 1.0 1.0 0.0)))
                  (if (and (not (vl-catch-all-error-p blk)) blk)
                    (progn
                      (setq exp-res (vl-catch-all-apply 'vla-explode (list blk)))
                      (vl-catch-all-apply 'vla-delete (list blk))
                      (if (not (vl-catch-all-error-p exp-res))
                        (setq copied-objs (vlax-safearray->list (vlax-variant-value exp-res))))))
                  (vl-catch-all-apply 'vl-file-delete (list tmp-dwg))))))

          (if (null copied-objs)
            (progn
              (princ "\n【错误】跨图纸克隆图元失败，请确认图纸未被写保护。")
              nil)
            (progn
              ;; 平移新克隆图元至计算出的安全排版落点
              (foreach new-obj copied-objs
                (vl-catch-all-apply
                  'vla-move
                  (list new-obj (vlax-3d-point 0 0 0) (vlax-3d-point off-x off-y 0)))
                (if target-layer
                  (progn
                    (dt:ensure-layer (vla-get-layers tgt-doc) target-layer 4 "青色")
                    (vl-catch-all-apply 'vla-put-layer (list new-obj target-layer)))))

              ;; 6) 在工件上方居中标注原图纸文件名 (字高 15，智能断句为多行，底部居中对齐)
              (setq src-fname (vl-filename-base (dt:sz-gets "DWGNAME")))
              (if (or (null src-fname) (= src-fname "")) (setq src-fname "未命名工件"))
              (setq src-multiline (dt:sz-format-multiline src-fname))
              (setq part-w   (- s-maxx s-minx)
                    title-cx (+ ins-x (* 0.5 part-w))
                    title-cy (+ (- s-maxy s-miny) 15.0)
                    title-w  (max 80.0 (min part-w 220.0)))
              (dt:ensure-layer (vla-get-layers tgt-doc) "外协文字" 7 "白色")
              (setq txt-obj (vl-catch-all-apply
                              'vla-addmtext
                              (list ms-tgt (vlax-3d-point (list title-cx title-cy 0.0)) title-w src-multiline)))
              (if (and (not (vl-catch-all-error-p txt-obj)) txt-obj)
                (progn
                  (vl-catch-all-apply 'vla-put-height (list txt-obj 15.0))
                  ;; 8 = acAttachmentPointBottomCenter (底部居中对齐，向上生长且水平严格居中)
                  (vl-catch-all-apply 'vla-put-attachmentpoint (list txt-obj 8))
                  (vl-catch-all-apply 'vla-put-insertionpoint (list txt-obj (vlax-3d-point (list title-cx title-cy 0.0))))
                  (vl-catch-all-apply 'vla-put-linespacingfactor (list txt-obj 1.2))
                  (vl-catch-all-apply 'vla-put-layer (list txt-obj "外协文字"))
                  (vl-catch-all-apply 'vla-put-stylename (list txt-obj "DT_WX_STYLE"))))

              ;; 7) 保存目标图纸并提示
              (vl-catch-all-apply 'vla-save (list tgt-doc))
              (if was-closed
                (vl-catch-all-apply 'vla-close (list tgt-doc :vlax-false)))

              (princ "\n------------------------------------------------------------")
              (princ (strcat "\n【" title "】工件已成功输出并排版至: " target-path))
              (princ (strcat "\n【" title "】排版起点 X = " (rtos ins-x 2 2)
                             " (自动避开已有图形, 安全间距 150mm, 上方已标注文件名)"))
              (princ "\n------------------------------------------------------------")
              T)))))))

;; ============================================================================
;; 四、主命令与对外接口
;; ============================================================================

;; 测量分流板主命令 (c:FLBSZ / c:FLBSIZE)
(defun c:FLBSZ ( / *error* ss cands closed-p box len wid p1 p2 p3 p4 ang
                   clip-str msg choice)
  (defun *error* (msg)
    (vl-catch-all-apply '(lambda () (command "_.UNDO" "E")))
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【分流板尺寸】错误: " msg)))
    (princ))

  (princ "\n【分流板尺寸】正在检测分流板(FLB)...")
  (setq cands nil)

  ;; 步骤 1: 优先检查 FLB 图层
  (if (tblsearch "LAYER" "FLB")
    (progn
      (setq ss (ssget "X" '((8 . "FLB") (0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if ss
        (setq cands (dt:sz-curves-only (dt:ss->list ss))))))

  ;; 步骤 2: 检验 FLB 图层是否构成闭合区域
  (setq closed-p (if cands (dt:sz-check-closed cands) nil))

  ;; 若未找到 FLB 或 FLB 未闭合，提示并转入手动选择
  (if (null closed-p)
    (progn
      (if (null cands)
        (princ "\n【分流板尺寸】提示: 图层 FLB 未找到有效轮廓线，请手动选择边界曲线。")
        (princ "\n【分流板尺寸】提示: 图层 FLB 未构成闭合区域，请手动选择闭合边界曲线。"))
      (princ "\n请选择分流板边界曲线(支持框选/多选，选完按回车或右键确认): ")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (progn
          (princ "\n【分流板尺寸】未选择图元，命令已取消。")
          (setq cands nil))
        (progn
          (setq cands (dt:sz-curves-only (dt:ss->list ss)))
          (setq closed-p (if cands (dt:sz-check-closed cands) nil))
          (if (null closed-p)
            (progn
              (alert "【提示】您手动选择的曲线未能构成封闭区域！\n\n请检查曲线端点是否全部吻合相接。\n命令已取消。")
              (princ "\n【分流板尺寸】所选曲线未构成封闭区域，命令已取消。")
              (setq cands nil)))))))

  ;; 步骤 3: 若已确认闭合，计算尺寸并输出
  (if (and cands closed-p)
    (progn
      (setq box (dt:sz-calc-box cands))
      (if (null box)
        (princ "\n【分流板尺寸】计算包络尺寸失败。")
        (progn
          (setq len (car box)
                wid (cadr box)
                p1  (caddr box)
                p2  (cadddr box)
                p3  (nth 4 box)
                p4  (nth 5 box)
                ang (nth 6 box))
          (setq clip-str (strcat (dt:sz-fmt-num len) "x" (dt:sz-fmt-num wid)))
          ;; 自动写入 Windows 剪贴板
          (dt:sz-copy-clip clip-str)

          ;; 命令行输出
          (princ "\n------------------------------------------------------------")
          (princ (strcat "\n【分流板尺寸】测量完成: 最长边 = " (rtos len 2 2)
                         " mm , 最宽边 = " (rtos wid 2 2) " mm"))
          (princ (strcat "\n包络规格: " clip-str " (已自动复制到剪贴板，可直接 Ctrl+V 粘贴)"))
          (princ "\n------------------------------------------------------------")

          ;; 弹窗提醒
          (setq msg (strcat "【分流板尺寸测量结果】\n\n"
                            "最长边(Length) : " (rtos len 2 2) " mm\n"
                            "最宽边(Width)  : " (rtos wid 2 2) " mm\n\n"
                            "包络规格: " clip-str "\n"
                            "(已自动复制到系统剪贴板，可直接粘贴)\n"))
          (alert msg)

          ;; 交互式询问是否绘制到 FLB_BOX 图层
          (initget "Y N")
          (setq choice (getkword "\n是否在 FLB_BOX 图层绘制包络矩形与长宽标注(字高15)? [是(Y)/否(N)] <Y>: "))
          (if (or (null choice) (= (strcase choice) "Y"))
            (progn
              (command "_.UNDO" "BE")
              (dt:sz-draw-box-dim p1 p2 p3 p4)
              (command "_.UNDO" "E")
              (princ "\n【分流板尺寸】已在图层 \"FLB_BOX\" 绘制包络框与长宽标注(字高15)。")))))))
  (princ)
)

(defun c:FLBSIZE ( ) (c:FLBSZ))
(defun c:SZ ( ) (c:FLBSZ))
(defun c:WXSZ ( ) (c:FLBSZ))

;; 线切割主命令 (c:XQG)
(defun c:XQG ( / *error* ss cands closed-p)
  (defun *error* (msg)
    (vl-catch-all-apply '(lambda () (command "_.UNDO" "E")))
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【线切割】错误: " msg)))
    (princ))

  (princ "\n【线切割】正在检测分流板(FLB)...")
  (setq cands nil)

  ;; 步骤 1: 优先检查 FLB 图层
  (if (tblsearch "LAYER" "FLB")
    (progn
      (setq ss (ssget "X" '((8 . "FLB") (0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if ss
        (setq cands (dt:sz-curves-only (dt:ss->list ss))))))

  ;; 步骤 2: 检验 FLB 图层是否构成闭合区域
  (setq closed-p (if cands (dt:sz-check-closed cands) nil))

  ;; 若未找到 FLB 或 FLB 未闭合，提示并转入手动选择
  (if (null closed-p)
    (progn
      (if (null cands)
        (princ "\n【线切割】提示: 图层 FLB 未找到有效轮廓线，请手动选择闭合曲线。")
        (princ "\n【线切割】提示: 图层 FLB 未构成闭合区域，请手动选择闭合边界曲线。"))
      (princ "\n请选择闭合轮廓线(支持框选/多选，选完按回车或右键确认): ")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (progn
          (princ "\n【线切割】未选择图元，命令已取消。")
          (setq cands nil))
        (progn
          (setq cands (dt:sz-curves-only (dt:ss->list ss)))
          (setq closed-p (if cands (dt:sz-check-closed cands) nil))
          (if (null closed-p)
            (progn
              (alert "【提示】您手动选择的曲线未能构成封闭区域！\n\n请检查曲线端点是否全部吻合相接。\n命令已取消。")
              (princ "\n【线切割】所选曲线未构成封闭区域，命令已取消。")
              (setq cands nil)))))))

  ;; 步骤 3: 复制并输出到目标图纸 (自动平铺排版防覆盖, 上方标注文件名)
  (if (and cands closed-p)
    (dt:sz-export-to-dwg cands "线切割" "FLB"))
  (princ)
)

;; 精雕主命令 (c:JD)
(defun c:JD ( / *error* ss cands)
  (defun *error* (msg)
    (vl-catch-all-apply '(lambda () (command "_.UNDO" "E")))
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【精雕】错误: " msg)))
    (princ))

  (princ "\n【精雕】正在提取热流道加工曲线...")
  (setq cands (dt:sz-collect-auto-curves))

  ;; 若自动化图层未找到有效曲线，提示并转入手动框选
  (if (null cands)
    (progn
      (princ "\n【精雕】未在自动化图层(FLB/LS/RZ/DK/JRT)找到曲线，请手动框选加工曲线:")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (princ "\n【精雕】未选择图元，命令已取消。")
        (setq cands (dt:sz-curves-only (dt:ss->list ss))))))

  ;; 输出到自动路径的精雕图纸
  (if cands
    (dt:sz-export-to-dwg cands "精雕" nil))
  (princ)
)

;; 数据图纸主命令 (c:SJTZ)
(defun c:SJTZ ( / *error* ss cands o bb p0 p1 dx dy new-objs new-o new-bb
                   minx miny maxx maxy date-str def-mj def-flb flb-ss
                   flb-cands flb-box mtxt-str doc ms x-label y-top th mtxt-obj)
  (defun *error* (msg)
    (vl-catch-all-apply '(lambda () (command "_.UNDO" "E")))
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【数据图纸】错误: " msg)))
    (princ))

  (princ "\n【数据图纸】正在提取热流道加工曲线...")
  (setq cands (dt:sz-collect-auto-curves))

  ;; 若未找到则转入手动框选
  (if (null cands)
    (progn
      (princ "\n【数据图纸】未在自动化图层(FLB/LS/RZ/DK/JRT)找到曲线，请手动框选曲线:")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (princ "\n【数据图纸】未选择图元，命令已取消。")
        (setq cands (dt:sz-curves-only (dt:ss->list ss))))))

  ;; 步骤 2: 交互式复制与自由移动
  (if (and cands (> (length cands) 0))
    (progn
      (setq bb (dt:rect-bbox cands)
            p0 (list (* 0.5 (+ (car bb) (caddr bb)))
                     (* 0.5 (+ (cadr bb) (cadddr bb)))
                     0.0))
      (initget 1)
      (setq p1 (getpoint p0 "\n【数据图纸】请在图中指定复制放置目标点或输入相对位移: "))
      (if (null p1)
        (princ "\n【数据图纸】未指定放置点，命令已取消。")
        (progn
          (setq dx (- (car p1) (car p0))
                dy (- (cadr p1) (cadr p0)))

          (command "_.UNDO" "BE")

          ;; 克隆图元并移动至目标位置
          (setq new-objs nil)
          (foreach o cands
            (setq new-o (vl-catch-all-apply 'vla-copy (list o)))
            (if (and (not (vl-catch-all-error-p new-o)) new-o)
              (progn
                (vl-catch-all-apply
                  'vla-move
                  (list new-o (vlax-3d-point 0 0 0) (vlax-3d-point dx dy 0)))
                (setq new-objs (cons new-o new-objs)))))

          (setq new-bb (dt:rect-bbox new-objs))
          (if (null new-bb)
            (progn
              (command "_.UNDO" "E")
              (princ "\n【数据图纸】未能计算新图形范围。"))
            (progn
              (setq minx (car new-bb)
                    miny (cadr new-bb)
                    maxx (caddr new-bb)
                    maxy (cadddr new-bb))

              ;; 步骤 3: 提取/预填各项参数值
              ;; 步骤 3: 提取参数值 (自动生成当前无空格日期、文件名及分流板长宽，其余留空不弹窗打扰)
              (setq date-str (dt:sz-get-date-str))

              (setq def-mj (vl-filename-base (dt:sz-gets "DWGNAME")))
              (if (or (null def-mj) (= def-mj "")) (setq def-mj "1031-02"))

              ;; 自动探测分流板尺寸 (仅最长*最宽，不拼接厚度)
              (setq def-flb "")
              (setq flb-ss (ssget "X" '((8 . "FLB") (0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
              (if flb-ss
                (progn
                  (setq flb-cands (dt:sz-curves-only (dt:ss->list flb-ss))
                        flb-box (if flb-cands (dt:sz-calc-box flb-cands) nil))
                  (if flb-box
                    (setq def-flb (strcat (dt:sz-fmt-num (car flb-box))
                                          "*"
                                          (dt:sz-fmt-num (cadr flb-box)))))))

              ;; 步骤 4: 在图形最右侧 +30 绘制单一整体多行文字区域 (用户双击可一次性编辑整块)
              (setq mtxt-str
                    (strcat "客户：\\P"
                            "模具编号：" def-mj "\\P"
                            "中心距：\\P"
                            "分流板：" def-flb "\\P"
                            "热咀：\\P"
                            "出线：\\P"
                            "日期：" date-str))

              (setq doc (vla-get-activedocument (vlax-get-acad-object))
                    ms  (vla-get-modelspace doc))
              (dt:sz-ensure-style doc)
              (dt:ensure-layer (vla-get-layers doc) "外协文字" 7 "白色")

              (setq x-label (+ maxx 30.0)
                    y-top   maxy
                    th      13.0)

              (setq mtxt-obj (vl-catch-all-apply
                               'vla-addmtext
                               (list ms (vlax-3d-point (list x-label y-top 0.0)) 220.0 mtxt-str)))
              (if (and (not (vl-catch-all-error-p mtxt-obj)) mtxt-obj)
                (progn
                  (vl-catch-all-apply 'vla-put-height (list mtxt-obj th))
                  ;; 1 = acAttachmentPointTopLeft (左上对齐)
                  (vl-catch-all-apply 'vla-put-attachmentpoint (list mtxt-obj 1))
                  (vl-catch-all-apply 'vla-put-insertionpoint (list mtxt-obj (vlax-3d-point (list x-label y-top 0.0))))
                  (vl-catch-all-apply 'vla-put-linespacingfactor (list mtxt-obj 1.6))
                  (vl-catch-all-apply 'vla-put-layer (list mtxt-obj "外协文字"))
                  (vl-catch-all-apply 'vla-put-stylename (list mtxt-obj "DT_WX_STYLE"))))

              (command "_.UNDO" "E")
              (princ "\n【数据图纸】图形复制与右侧信息文字区域生成完成。")))))))
  (princ)
)

(princ "\n热流道外协与测量工具 wx_runner v2.0 已加载。可用命令: FLBSZ(测量) / XQG(线切割) / JD(精雕) / SJTZ(数据图纸)。")
(princ)
