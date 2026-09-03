;;; ============================================================================
;;; 热流道自动化系统 - 尺寸数据测量工具 (size_runner.lsp)
;;;
;;; 功能:
;;;   1. 分流板(FLB)最长与最宽尺寸自动提取 (c:FLBSZ / c:FLBSIZE)
;;;      - 优先自动扫描 FLB 图层；未找到或未闭合时自动转入手动框选模式
;;;      - 双引擎闭合区域校验: 原生 ACIS Region 面域引擎 + 0.5mm 容差端点拓扑度数引擎
;;;      - AABB + OBB 最佳外包矩形算法，精准计算最长边(Length)与最宽边(Width)
;;;      - 测量结果自动写入 Windows 剪贴板 (如 "350x180"，可直接 Ctrl+V 粘贴进下料单)
;;;      - 交互式确认后在 FLB_BOX 图层绘制包络矩形与长宽标注(字高>=15)
;;;   2. 架构设计:
;;;      - 与 offset_runner / jrt_runner / slot_runner 并列的独立第 4 脚本
;;;      - 自包含基础几何库，支持单独 APPLOAD 运行
;;;      - 预留未来测量功能扩展槽位 (如出线槽测量 c:SLOTSZ)
;;;
;;; 版本: v1.0
;;; 平台: AutoCAD 2007 ~ 2026 (AutoLISP + COM ActiveX)
;;; ============================================================================

(vl-load-com)

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
;; 三、主命令与对外接口
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

(princ "\n热流道尺寸测量工具 size_runner v1.0 已加载。输入 FLBSZ 启动分流板尺寸测量。")
(princ)
