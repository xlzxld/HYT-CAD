;;; demo_recorder.lsp —— 演示记录器(手工操作日志工具, 工具菜单 DTDEMO 按需加载)
;;; v1.0 (2026-09-06) 首版
;;;
;;; 用途: 让 AI"看懂"你在 CAD 里手工做的操作。开启后挂命令级反应器,
;;;       把每个命令的开始/结束/取消、拾取点(LASTPOINT 跟踪)、新建实体的
;;;       类型/图层/关键几何, 逐行追加到日志文件。
;;;
;;; 用法: 菜单「工具>演示记录器」(=DTDEMO, 首次点击自动加载本文件并开始
;;;       录制, 再点一次结束) 或 APPLOAD 本文件后敲 DEMOREC/DEMOSTOP;
;;;       手工做一遍操作, 中途可用 DEMOMARK 打文字标注,
;;;       做完把日志文件 cad_demo_log.txt 发给 AI。
;;;       可反复 开始/结束, 同一日志按 SESSION 头分段。
;;;
;;; 记录范围与限制:
;;;   1) 只记录"新建实体"与拾取点; 移动/旋转/修剪等编辑不直接留痕,
;;;      但 AI 可凭命令名 + 拾取点序列 + 最终几何反推。
;;;   2) 视图/存盘类命令(ZOOM/PAN/SAVE 等)跳过不记录。
;;;   3) 日志主体为 ASCII; DEMOMARK 的中文标注按 CAD 默认编码写出。
;;;   4) 本工具不改图、不产生 UNDO 记录; 关闭 CAD 自动失效(需重加载)。
;;;   5) 坑 #65 模式: 所有 getvar 经 demo:gets 兜底, 取到后立刻判空。

(vl-load-com)

;; ---- 全局 ----
;; *demo-on* T=录制中; *demo-cmd-reactor* / *demo-sv-reactor* 反应器
;; *demo-log-path* 日志路径; *demo-cur-cmd* 当前命令
;; *demo-marker* 命令开始前最后实体的句柄; *demo-n-* 统计

;; getvar 兜底(参数化包装, 老版本静默返回 nil / 抛错均回退 fallback)
(defun demo:gets (var fallback / v)
  (setq v (vl-catch-all-apply 'getvar (list var)))
  (if (or (null v) (vl-catch-all-error-p v)) fallback v)
)

;; 命令名规范化: 大写, 去透明前缀 ' / _ / .
(defun demo:canon (s)
  (setq s (strcase s))
  (while (and (> (strlen s) 0) (member (substr s 1 1) (list "'" "_" ".")))
    (setq s (substr s 2))
  )
  s
)

;; 噪音命令跳过清单
(defun demo:skip-p (nm)
  (member nm (list "ZOOM" "PAN" "VIEW" "REDRAW" "REGEN" "REGENALL"
                   "QSAVE" "SAVE" "SAVEAS" "GRID" "ORTHO" "OSNAP"
                   "DEMOREC" "DEMOSTOP" "DEMOMARK"))
)

;; 写一行(每行即开即关, 中途崩溃不丢前文)
(defun demo:writeline (s / f)
  (if *demo-log-path*
    (progn
      (setq f (open *demo-log-path* "a"))
      (if f
        (progn (write-line s f) (close f))
        (princ (strcat "\n[DEMOREC] 日志写入失败: " *demo-log-path*))
      )
    )
  )
)

;; 点转字符串 "(x,y[,z])", 非法输入回退 "?"
(defun demo:pt-s (p)
  (if (and (listp p)
           (numberp (nth 0 p)) (numberp (nth 1 p)))
    (strcat "(" (rtos (nth 0 p) 2 2) "," (rtos (nth 1 p) 2 2)
            (if (numberp (nth 2 p)) (strcat "," (rtos (nth 2 p) 2 2)) "")
            ")")
    "?"
  )
)

;; 实体一行摘要
(defun demo:ent-info (e / ed tp ly hd fl g)
  (setq ed (entget e)
        tp (cdr (assoc 0 ed))
        ly (cdr (assoc 8 ed))
        hd (cdr (assoc 5 ed))
        g "")
  (cond
    ((= tp "LINE")
     (setq g (strcat " from=" (demo:pt-s (cdr (assoc 10 ed)))
                     " to=" (demo:pt-s (cdr (assoc 11 ed))))))
    ((or (= tp "CIRCLE") (= tp "ARC"))
     (setq g (strcat " c=" (demo:pt-s (cdr (assoc 10 ed)))
                     " r=" (rtos (cdr (assoc 40 ed)) 2 2)
                     (if (= tp "ARC")
                       (strcat " a=" (rtos (cdr (assoc 50 ed)) 2 1)
                               ".." (rtos (cdr (assoc 51 ed)) 2 1))
                       ""))))
    ((= tp "LWPOLYLINE")
     (setq fl (if (assoc 70 ed) (cdr (assoc 70 ed)) 0)
           g (strcat " verts="
                     (itoa (length (vl-remove-if-not
                                     '(lambda (x) (= (car x) 10)) ed)))
                     " closed=" (if (= 1 (logand fl 1)) "Y" "N")
                     " first=" (demo:pt-s (cdr (assoc 10 ed))))))
    ((= tp "TEXT")
     (setq g (strcat " at=" (demo:pt-s (cdr (assoc 10 ed)))
                     " h=" (rtos (cdr (assoc 40 ed)) 2 1)
                     " s=\"" (cdr (assoc 1 ed)) "\"")))
    ((= tp "MTEXT")
     (setq g (strcat " at=" (demo:pt-s (cdr (assoc 10 ed))))))
    ((= tp "INSERT")
     (setq g (strcat " blk=" (cdr (assoc 2 ed))
                     " at=" (demo:pt-s (cdr (assoc 10 ed))))))
  )
  (strcat "NEW " tp " layer=" (if ly ly "?") " h=" (if hd hd "?") g)
)

;; 从 marker 之后遍历并记录本次命令新建的实体, 返回数量
(defun demo:dump-new (/ e m n)
  (setq n 0)
  (if *demo-marker*
    (progn
      (setq m (handent *demo-marker*))
      (if m
        (setq e (entnext m))
        (progn
          (demo:writeline "MARKER-LOST (本命令新实体无法增量识别)")
          (setq e nil)
        )
      )
    )
    (setq e (entnext))
  )
  (while e
    (demo:writeline (demo:ent-info e))
    (setq n (1+ n))
    (setq e (entnext e))
  )
  (setq *demo-n-new* (+ *demo-n-new* n))
  n
)

;; ---- 反应器回调 ----
(defun demo:cmd-will-start (r args / nm)
  (setq nm (demo:canon (if args (car args) "?")))
  (if (demo:skip-p nm)
    (setq *demo-cur-cmd* nil)
    (progn
      (setq *demo-cur-cmd* nm
            *demo-marker* (if (entlast) (cdr (assoc 5 (entget (entlast)))) nil))
      (demo:writeline (strcat "CMD " nm " start"))
      (setq *demo-n-cmd* (1+ *demo-n-cmd*))
    )
  )
)

(defun demo:cmd-ended (r args / nm)
  (setq nm (demo:canon (if args (car args) "?")))
  (if (and *demo-cur-cmd* (= nm *demo-cur-cmd*))
    (progn
      (demo:writeline (strcat "CMD " nm " end"))
      (demo:dump-new)
      (setq *demo-cur-cmd* nil)
    )
  )
)

(defun demo:cmd-abort (r args / nm)
  (setq nm (demo:canon (if args (car args) "?")))
  (if *demo-cur-cmd*
    (progn
      (demo:writeline (strcat "CMD " nm " aborted"))
      (setq *demo-cur-cmd* nil)
    )
  )
)

;; LASTPOINT 跟踪: 每次指定点都会改写该变量
(defun demo:sv-changed (r args / nm pt)
  (if *demo-on*
    (progn
      (setq nm (if (and args (car args)) (strcase (car args)) "?"))
      (if (= nm "LASTPOINT")
        (progn
          (setq pt (demo:gets "LASTPOINT" nil))
          (if (listp pt)
            (progn
              (demo:writeline (strcat "PICK cmd=" (if *demo-cur-cmd* *demo-cur-cmd* "-")
                                      " pt=" (demo:pt-s pt)))
              (setq *demo-n-pt* (1+ *demo-n-pt*))
            )
          )
        )
      )
    )
  )
)

;; ---- 命令 ----
(defun c:DEMOREC (/ dir f)
  (if *demo-on*
    (princ "\n[DEMOREC] 已在录制中, 无需重复开启。")
    (progn
      (setq dir (demo:gets "DWGPREFIX" nil))
      (if (or (null dir) (= dir ""))
        (setq dir (demo:gets "TEMPPREFIX" nil))
      )
      (if (or (null dir) (= dir ""))
        (princ "\n[DEMOREC] 无法确定日志目录(无图纸且 TEMPPREFIX 不可用), 请先打开一张图纸。")
        (progn
          (setq *demo-log-path* (strcat dir "cad_demo_log.txt"))
          (setq f (open *demo-log-path* "a"))
          (if (null f)
            (princ (strcat "\n[DEMOREC] 日志文件无法创建: " *demo-log-path*))
            (progn
              (write-line (strcat "==== DEMO SESSION "
                                  (rtos (demo:gets "CDATE" 0.0) 2 8)
                                  " dwg=" (demo:gets "DWGNAME" "-") " ====") f)
              (close f)
              (if *demo-cmd-reactor* (vlr-remove *demo-cmd-reactor*))
              (if *demo-sv-reactor* (vlr-remove *demo-sv-reactor*))
              (setq *demo-cmd-reactor*
                    (vlr-command-reactor nil
                      '((:vlr-commandWillStart . demo:cmd-will-start)
                        (:vlr-commandEnded . demo:cmd-ended)
                        (:vlr-commandCancelled . demo:cmd-abort)
                        (:vlr-commandFailed . demo:cmd-abort))))
              (setq *demo-sv-reactor*
                    (vl-catch-all-apply
                      '(lambda ()
                         (vlr-sysvar-reactor
                           nil '((:vlr-sysVarChanged . demo:sv-changed))))))
              (setq *demo-on* T
                    *demo-n-cmd* 0
                    *demo-n-new* 0
                    *demo-n-pt* 0
                    *demo-cur-cmd* nil)
              (princ (strcat "\n[DEMOREC] 录制已开始, 日志: " *demo-log-path*))
              (princ "\n[DEMOREC] 现在手工做操作, 中途 DEMOMARK 打标注, 做完 DEMOSTOP。")
              (if (vl-catch-all-error-p *demo-sv-reactor*)
                (princ "\n[DEMOREC] 注意: 拾取点跟踪在本版 CAD 不可用(命令与实体仍记录)。")
              )
            )
          )
        )
      )
    )
  )
  (princ)
)

(defun c:DEMOSTOP ()
  (if *demo-on*
    (progn
      (if *demo-cmd-reactor* (vlr-remove *demo-cmd-reactor*))
      (if *demo-sv-reactor* (vlr-remove *demo-sv-reactor*))
      (demo:writeline "==== DEMO END ====")
      (setq *demo-on* nil)
      (princ (strcat "\n[DEMOSTOP] 录制结束: 命令 " (itoa *demo-n-cmd*)
                     " 条, 新实体 " (itoa *demo-n-new*)
                     " 个, 拾取点 " (itoa *demo-n-pt*) " 个。"))
      (princ (strcat "\n[DEMOSTOP] 把日志发给 AI: " *demo-log-path*))
    )
    (princ "\n[DEMOSTOP] 当前没有在录制。")
  )
  (princ)
)

(defun c:DEMOMARK (/ s)
  (if *demo-on*
    (progn
      (setq s (getstring T "\n[DEMOMARK] 标注文字: "))
      (demo:writeline (strcat "==== MARK: " s " ===="))
      (princ "\n[DEMOMARK] 已写入。")
    )
    (princ "\n[DEMOMARK] 请先 DEMOREC 开始录制。")
  )
  (princ)
)

(princ "\n[DEMOREC] 演示记录器 v1.0 已加载: DEMOREC=开始, DEMOSTOP=结束, DEMOMARK=标注。")
(princ)
