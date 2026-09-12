;;; ============================================================================
;;; dt_start.lsp  v3.6 —— 一键加载 / 自启动引导器 + 顶部菜单(名字固定, 不带版本号)
;;; 用途: 与 flb_runner / cx_runner / jrt_runner / wx_runner / demo_recorder 脚本同目录,
;;;       APPLOAD 本文件一次 → 输 DTINSTALL → 以后开 CAD 自动全部就位。
;;; 命令:
;;;   DTINSTALL   安装自启(写 acaddoc.lsp 钩子 + 加入支持/受信任路径), 装完立即可用
;;;   DTRELOAD    换了新版本脚本后, 不重启 CAD 立即重新扫描加载最新版(顺带重挂菜单)
;;;   DTUNINSTALL 彻底卸载(摘菜单 + 删钩子 + 移出支持/受信任路径), CAD 配置恢复原样
;;;   DTDBG       对话框链路逐步诊断(定位 stringp 类错误)
;;;   DTDEMO      演示记录器(v3.1): 按需加载 demo_recorder.lsp 并开/关录制
;;; 菜单(v2.1): 顶栏「热流道自动化(R)」, 二级分组(分流板/加热条/出线槽/工具/关于);
;;;   COM 内存构建不落盘、不动主 CUI, 每次引导加载成功后自动挂出。
;;; v2.7 要点: 菜单二级顺序调整 —— 加热条挪到出线槽上面(用户频率排序);
;;;   家族表行序即菜单序, 加载顺序同表调换(三脚本自包含互不影响)。
;;; v2.8 要点: 文件句柄异常兜底 —— acaddoc.lsp 读/写中途出错时也保证
;;;   close(句柄滞留可能令后续同路径写打开失败); 与 offset v10.6 /
;;;   slot v10.3 / jrt v9.14 同期的健壮性统一收尾, 其余逻辑零变化。
;;; v2.9 要点: 低版本(2007~2015)DTINSTALL 报「参数类型错误: stringp nil」的
;;;   根因修复 —— v2.6 只兜住了"getvar 抛异常"这半边, 漏了"getvar 返回 nil"
;;;   这半边: 老版本上访问本版本没有的系统变量(TRUSTEDPATHS; 极老版本/国产
;;;   CAD 的 ROAMABLEROOTPREFIX; 无图纸打开时的 DWGPREFIX)时 getvar 静默
;;;   返回 nil 而非报错, nil 直接喂进 strcat/strlen 就冒成 stringp nil。对策:
;;;   1) 新增 dt:st-gets(安全取系统变量, 不可用一律返回 "")与 dt:st-hasvar
;;;      (变量是否存在), 从源头掐断 nil 外泄;
;;;   2) dt:st-support-root: ROAMABLEROOTPREFIX -> LOCALROOTPREFIX -> 都取不到
;;;      则走"acaddoc.lsp 写进脚本目录"的兜底路径(安装时同步把该目录顶到
;;;      支持路径最前, 保证 AutoCAD 能搜到它 —— 它只加载搜到的第一个);
;;;   3) dt:st-trusted-add/-del 补 null 判断(老版本无安全拦截机制 -> 跳过);
;;;   4) DTDBG 增环境探测段: ACADVER + 各系统变量可用性 + acaddoc.lsp 落点。
;;; v3.1 要点: 工具子菜单新增「演示记录器」—— c:DTDEMO 按需加载
;;;   scripts\demo_recorder.lsp(不随启动加载: 反应器工具常驻无必要)并
;;;   开/关录制, 把手工操作的命令/拾取点/新建实体录成日志给 AI 改逻辑用;
;;;   dt:st-about 命令清单同步。版本串 v2.9→v3.1(README/AGENTS_CAD 已按
;;;   v3.0 记账, 磁盘版本串本次一并对齐)。
;;; v3.2  : boot/DTRELOAD 增逐家族加载验证 —— 每个家族脚本加载后检查其
;;;   主命令是否已定义, 缺失 = 半加载/旧会话残留(坑 #49 变体: 用户实测
;;;   jrt_runner 半加载后运行报 no function definition), 明确警告请完全
;;;   关闭 CAD 重开, 不再让错误潜伏到运行期。
;;; v3.3  : 加载横幅并为一行并引用 dt:st-version(版本单一来源, 根治横幅
;;;   版本号与头注脱节); 升级安装提示从加载横幅移至 DTINSTALL 完成输出。
;;; v3.4  : 外协加工子菜单新增「测量加热条长度(JRTSZ)」(wx v2.15 配套,
;;;   与测量分流板同级); dt:st-about 命令清单同步。
;;; v3.5  : 外协加工子菜单项重新排定顺序(用户指定, 自上而下):
;;;   测量加热条长度 → 测量分流板 → 数据图纸 → 线切割 → 精雕。
;;;   仅调索引位次, 标签/热键/宏三者绑定关系与其余子菜单零变化。
;;; v3.6  : 体检修复: c:DTDEMO 移除入口守卫 (null demo:gets) —— defun 只设
;;;   函数槽不设值槽, 把函数名当变量求值恒为 nil, 该守卫恒真且使后面的
;;;   (T (c:DEMOREC)) 成死代码(坑 #72, jrt v9.20 同款清除)。行为零变化:
;;;   本来就每次都走"定位→加载→开录"链路(load 幂等), 只是把恒真条件与
;;;   死分支清掉。
;;; 版本规则: 正式版文件名无版本后缀(flb_runner.lsp 等)时**优先加载**;
;;;           无正式版才取"v+数字"最大的开发版。换版本只需替换文件。
;;; v2.1 要点(顶部菜单):
;;;   1) 家族表扩展为 (前缀 中文名 主命令 参数命令), 加载与菜单共用一张表,
;;;      新增脚本家族只加一行, 加载 + 菜单同时生效;
;;;   2) dt:st-menu-ensure 幂等挂菜单(先摘旧组再建新), boot 加载成功后自动调用,
;;;      DTRELOAD 顺带重挂(工作区切换挤掉菜单后一键找回);
;;;   3) 菜单构建全程 vl-catch-all 保护, 失败仅无菜单, 脚本命令不受影响。
;;; v2.2 要点(菜单修复): 本机 2024 实测 MenuGroups.Add 自建组被拒绝(v2.1 就栽
;;;   在这, 且错误信息被吞)。改为双路径: 自建 DTTOOLS 组失败时自动改把 popup
;;;   塞进 ACAD 主菜单组(老牌工具箱在 2024 上验证可行); 摘除逻辑同时覆盖两条
;;;   路径; 各步原始 Automation 错误信息照实打印, 发回即可定位。
;;; v2.3 要点(菜单复用, 本机实测定案): 2024 类型库已移除 MenuGroups.Add
;;;   ("未知名称: Add", 硬封); ACAD 组 PopupMenus.Add 可用(菜单实际建出过);
;;;   但建后删除被拒(Delete 静默失败), 会话内重跑即报"已存在"。对策:
;;;   1) 会话内只完整构建一次(*dt-st-menu-done*), 之后 ensure 只重挂到菜单栏;
;;;   2) 构建前先 vla-item 按名查同名 popup, 存在则直接复用不再新建;
;;;   3) 自建组尝试每会话仅一次, 避免每次 boot 刷"被拒"提示。
;;;   ACAD 组 popup 本就不跨会话持久, 重启 CAD 天然干净。
;;; v2.4 要点(宏修复, 本机实测定案): COM 通道的宏字符串不经 MNU/CUI 文件
;;;   解析器, "^C^C" 记号不会被翻译, 点击时整串字面量进命令行(实测
;;;   "未知命令 ^C^C(...)")。对策: 1) 取消码用真控制字符(chr 3);
;;;   2) 全部菜单项宏统一包成 LISP 表达式 (c:命令名)/(辅助函数), 闭合括号
;;;   即求值, 不依赖回车/尾空格语义; 3) 复用残留菜单前抽查宏格式,
;;;   旧格式("^"开头)提示重启 CAD 让新版重建。
;;; v2.5 要点(补回车): COM 菜单宏播放器不在宏尾自动补回车(实测: 点击后
;;;   "(c:OFF)" 停在命令行, 需手动回车才执行)。宏尾统一补一个空格
;;;   (菜单宏语法: 空格=回车), 点击即执行; 残留检查同时识别"宏尾无空格"
;;;   的 v2.4 菜单。
;;; v2.6 要点(老版本兼容, 原 old\dt_start.lsp 独有改动已并入正式版):
;;;   TRUSTEDPATHS/SECURELOAD 是 AutoCAD 2016 才引入的安全机制 —— 2007~2015
;;;   getvar/setvar 直接报错会中断 DTINSTALL/DTUNINSTALL。改为 catch 包裹,
;;;   老版本静默跳过(无拦截机制即无需信任路径)。至此正式版与 old 副本合并
;;;   为一份: 全版本通用, 不再需要按 CAD 版本挑文件。
;;; v2.0 要点(重构, 治"stringp T"/多副本定位错乱):
;;;   1) 钩子格式升级: acaddoc.lsp 里显式 (dt:st-init "<目录>") 注入确定性
;;;      路径, 开图加载不再依赖 findfile 猜目录(多副本环境下会命中旧副本);
;;;   2) 引导时把 *dt-script-dir* 注入并 vl-propagate, 三个脚本的 find-dcl
;;;      优先用它生成 dcl(各脚本侧已同步重写为极简版);
;;;   3) 横幅输出实际加载的文件名; DTDBG 增强目录/选版信息。
;;; 兼容: 旧格式钩子(load + boot)照常工作(boot 自行定位)。
;;; 说明: 本文件必须 UTF-8 with BOM 编码; 纯文件/COM 操作, 无几何逻辑。
;;; ============================================================================

(vl-load-com)

;; 家族定义: (文件名前缀 中文名 主命令 参数命令 子菜单热键) —— 新增脚本家族在此加一行,
;; 加载(boot)与顶部菜单(menu-build)共用本表; 热键字母在顶栏下拉内不可重复
;; v2.7: 加热条挪到出线槽上面(用户使用频率排序)
(setq dt:st-families
      (list (list "flb_runner" "分流板" "FLB" "FLBPARAM" "F")
            (list "jrt_runner" "加热条" "JRT" "JRTPARAM" "J")
            (list "cx_runner" "出线槽" "CX" "CXPARAM" "C")
            (list "wx_runner" "外协加工" "FLBSZ" nil "W")))

(setq dt:st-version "v3.6")     ;; 本文件版本(关于框/横幅用)
(setq dt:st-menugroup "DTTOOLS")          ;; 菜单组名(卸载/重挂按名定位)
(setq dt:st-menutitle "热流道自动化(&R)") ;; 顶栏标题(热键 Alt+R, R 未被内置菜单占用)
(setq *dt-st-menu-done* nil)  ;; 会话级: 菜单本会话已完整建成(重挂走捷径)
(setq dt:st-popmain nil)      ;; 顶栏主 popup 对象(重挂用)
(setq *dt-st-mg-add-tried* nil) ;; 会话级: MenuGroups.Add 已试过(2024 被移除, 只提示一次)

(setq dt:st-dir nil)          ;; 本目录缓存(会话内)
(setq *dt-st-loaded* nil)     ;; 会话守卫: 防每开一张图重复加载
(setq *dt-script-dir* nil)    ;; 确定性脚本目录(注入给各脚本的 find-dcl 用)

;; ---------------------------------------------------------------------------
;; 低版本兼容底座(v2.9) —— 治「参数类型错误: stringp nil」的总闸。
;; 老版本 AutoCAD(2007~2015)上访问本版本不存在的系统变量时, getvar 大多
;; 不抛异常而是**静默返回 nil**(少数环境/变量才抛异常)。v2.6 只 catch 了
;; 抛异常那半边, nil 漏出来后进了 strcat/strlen 就成了 stringp nil。
;; 下面两个函数把"抛错 / 返回 nil / 非字符串"三种情况统一收敛:
;;   dt:st-gets   —— 取字符串型系统变量, 不可用一律返回 ""(绝不给 nil)
;;   dt:st-hasvar —— 该变量在本版本是否可用(存在且有值即 T)
;; ---------------------------------------------------------------------------
(defun dt:st-gets (name / r)
  (setq r (vl-catch-all-apply 'getvar (list name)))
  (cond
    ((vl-catch-all-error-p r) "")   ; 该版本没有此变量(抛错型)
    ((null r) "")                   ; 该版本没有此变量(静默 nil 型)—— v2.9 关键
    ((= (type r) 'STR) r)
    (T (vl-prin1-to-string r))))    ; 数值/表等: 转成串, 保证调用方拿到的必是串

(defun dt:st-hasvar (name / r)
  (setq r (vl-catch-all-apply 'getvar (list name)))
  (not (or (vl-catch-all-error-p r) (null r))))

;; acaddoc.lsp 该落在哪个"Support 根"(返回时结尾自带反斜杠):
;;   ROAMABLEROOTPREFIX(2006+) -> LOCALROOTPREFIX(2006+) -> ""(都取不到,
;;   由调用方走"写进脚本目录"兜底; 国产 CAD / 2005 及更早会遇到)
(defun dt:st-support-root ( / r)
  (cond
    ((/= (setq r (dt:st-gets "ROAMABLEROOTPREFIX")) "") r)
    ((/= (setq r (dt:st-gets "LOCALROOTPREFIX")) "") r)
    (T "")))

;; ---------------------------------------------------------------------------
;; 注入确定性脚本目录(v2.0): 钩子/DTINSTALL/引导调用。
;; 各脚本的 find-dcl 优先用 *dt-script-dir*, 彻底摆脱 findfile 在多副本
;; 环境下命中其它目录同名旧副本的不确定性。返回 dir。
;; ---------------------------------------------------------------------------
(defun dt:st-init (dir)
  (setq dt:st-dir dir
        *dt-script-dir* dir)
  (vl-propagate '*dt-script-dir*)
  dir)

;; ---------------------------------------------------------------------------
;; 定位本文件所在目录(返回目录串, 失败 nil):
;;   1) 缓存/钩子注入(dt:st-init 已调用)
;;   2) findfile 自身名(目录已在支持路径——安装后/DTRELOAD 时的常规路径)
;;   3) 当前图纸同目录(v2.9: DWGPREFIX 走 dt:st-gets —— 老版本无图纸打开时
;;      该变量会返回 nil, 直接 strcat 就是 stringp nil)
;;   4) getfiled 让用户选一次本目录任意 .lsp(坑: findfile 不搜 APPLOAD 目录)
;; 注意: 机器上若有多份 dt_start.lsp 副本(如旧目录), findfile 可能命中
;;       旧副本 —— 请保证机器上只留一份在用的(坑 #35)。
;; ---------------------------------------------------------------------------
(defun dt:st-locate ( / f d )
  (cond
    (dt:st-dir dt:st-dir)
    ((setq f (findfile "dt_start.lsp"))
     (setq dt:st-dir (vl-filename-directory f)))
    ((and (/= (setq d (dt:st-gets "DWGPREFIX")) "")
          (findfile (strcat d "dt_start.lsp")))
     (setq dt:st-dir d))
    (T
     (setq f (getfiled "定位脚本目录: 选择该目录里任意一个 .lsp 文件" "" "lsp" 4))
     (if f (setq dt:st-dir (vl-filename-directory f))))))

;; ---------------------------------------------------------------------------
;; 版本号解析(纪元感知, 约定见 AGENTS_CAD.md 版本命名):
;;   文件名 = 前缀 + "_v" + 纯数字 + ".lsp"
;;   一位 "v8"=8.0; 两位 90-99 "v96"=9.6; 两位 20-89 "v75"=7.5/"v85"=8.5;
;;   两位 10-19 "v10"=10.0(v10+ 纪元); 三位首位非1 "v816"=8.16;
;;   三位首位1 "v101"=10.1(未来兼容)。编码=主*1000+次, 直接比大小。
;;   "_v9x" 等非纯数字/无版本号 → nil
;; ---------------------------------------------------------------------------
(defun dt:st-digits (fname prefix / L s)
  (setq L (strlen fname) s (strlen prefix))
  (if (and (> L (+ s 6))
           (= (strcase (substr fname 1 s)) (strcase prefix))
           (= (strcase (substr fname (1+ s) 2)) "_V")
           (= (strcase (substr fname (- L 3))) ".LSP"))
    (substr fname (+ s 3) (- L s 6))
    nil))

(defun dt:st-vernum (fname prefix / d n)
  (setq d (dt:st-digits fname prefix))
  (cond
    ((null d) nil)
    ((= (strlen d) 1) (* (atoi d) 1000))
    ((= (strlen d) 2)
     (setq n (atoi d))
     (cond
       ((and (>= n 90) (<= n 99)) (+ 9000 (- n 90)))
       ((and (>= n 10) (<= n 19)) (* n 1000))
       (T (+ (* (atoi (substr d 1 1)) 1000) (atoi (substr d 2 1))))))
    ((= (strlen d) 3)
     (if (= (substr d 1 1) "1")
       (+ (* (atoi (substr d 1 2)) 1000) (atoi (substr d 3 1)))
       (+ (* (atoi (substr d 1 1)) 1000) (atoi (substr d 2 2)))))
    (T nil)))

;; 家族选版: 目录内该前缀的文件, **无版本后缀的正式版(如 flb_runner.lsp)
;; 优先**; 没有正式版才取"v+数字"最大者(无则 nil)
(defun dt:st-pick (dir prefix / best bestn f v exact)
  (setq exact (strcat prefix ".lsp"))
  (if (vl-position exact (vl-directory-files dir "*.lsp" 1))
    exact
    (progn
      (setq best nil bestn -1)
      (foreach f (vl-directory-files dir "*.lsp" 1)
        (setq v (dt:st-vernum f prefix))
        (if (and v (> v bestn))
          (setq bestn v best f)))
      best)))

;; 字符串列表用分隔符连接(汇总打印用)
(defun dt:st-join (lst sep / r x)
  (setq r "")
  (foreach x lst (setq r (if (= r "") x (strcat r sep x))))
  r)

;; ---------------------------------------------------------------------------
;; 引导: 注入确定性目录 → 扫描加载每个家族(正式版优先);
;; force=T 强制(忽略会话守卫, DTRELOAD 用)
;; ---------------------------------------------------------------------------
(defun dt:st-boot (force / dir fam prefix name loaded)
  (if (and (null force) *dt-st-loaded*)
    (princ)
    (progn
      (setq dir (dt:st-locate))
      (cond
        ((null dir)
         (princ "\n【自启】未定位到脚本目录, 跳过。"))
        (T
         ;; v2.0: 确定性目录注入(各脚本 find-dcl 依赖它)
         (dt:st-init dir)
         (setq loaded nil)
         (foreach fam dt:st-families
           (setq prefix (car fam)
                 name (dt:st-pick dir prefix))
           (if name
             (progn
               (if (vl-catch-all-error-p
                     (vl-catch-all-apply 'load (list (strcat dir "\\" name))))
                 (princ (strcat "\n【自启】警告: " name " 加载失败(语法错误?), 已跳过。"))
                 (progn
                   (setq loaded (cons (strcat (cadr fam) "=" name) loaded))
                   ;; v3.2: 逐家族加载验证 —— 主命令缺失 = 半加载/旧会话残留
                   (if (null (vl-catch-all-apply
                               '(lambda (cmd) (eval (read (strcat "c:" cmd))))
                                 (list (caddr fam))))
                     (princ (strcat "\n【自启】严重警告: " name " 加载后缺少主命令 c:"
                                    (caddr fam) " —— 请完全关闭 CAD 所有窗口后重开!"))))))))
         (if loaded
           (progn
             (princ (strcat "\n【自启】已加载 " (dt:st-join (reverse loaded) " / ")
                            "  (目录: " dir ")"))
             (dt:st-menu-ensure))
           (princ "\n【自启】目录里没有找到任何脚本家族文件。"))))
      (setq *dt-st-loaded* T)
      (vl-propagate '*dt-st-loaded*)))
  (princ))

;; ---------------------------------------------------------------------------
;; acaddoc.lsp 钩子管理(幂等): 标记块之间是我们写的内容, 重装只更新路径
;; ---------------------------------------------------------------------------
;; acaddoc.lsp 落点(v2.9): 优先 <支持根>Support\acaddoc.lsp; 老版本取不到支持
;; 根时兜底写脚本目录 —— DTINSTALL 会同步把该目录顶到支持路径最前, 因为
;; AutoCAD 只加载搜索路径里"第一个" acaddoc.lsp, 排在后面的不生效。
;; dir 可传 nil(卸载时退回 dt:st-dir); 连脚本目录都定位不到则返回 nil,
;; 由调用方明确报"写入失败", 不再让 nil 流进 strcat。
(defun dt:st-acadoc-path (dir / root)
  (setq root (dt:st-support-root))
  (cond
    ((/= root "") (strcat root "Support\\acaddoc.lsp"))
    ((and dir (/= dir "")) (strcat dir "\\acaddoc.lsp"))
    (dt:st-dir (strcat dt:st-dir "\\acaddoc.lsp"))
    (T nil)))

;; 目录串里的 \ 翻倍(生成会被再读取的 LISP 字符串字面量)
(defun dt:st-2bs (s / i c r)
  (setq i 1 r "")
  (repeat (strlen s)
    (setq c (substr s i 1)
          r (if (= c "\\") (strcat r "\\\\") (strcat r c))
          i (1+ i)))
  r)

;; 读现有 acaddoc.lsp, 剥掉旧标记块后追加新块(路径=dir); 失败返回 nil
;; v2.0 钩子格式: load 本文件 → dt:st-init 显式注入目录 → boot
(defun dt:st-write-hook (dir / path lines f ln skipping block r root)
  (setq path (dt:st-acadoc-path dir)
        lines nil)
  (cond
    ((null path) nil)          ; 连兜底目录都定位不到 -> 明确失败
    (T
     (setq root (dt:st-support-root))
     ;; 只在 Support 根可用时建目录(兜底模式下脚本目录本就存在);
     ;; vl-mkdir 同样 catch 保护 —— 权限/只读目录不应中断安装
     (if (/= root "")
       (vl-catch-all-apply 'vl-mkdir (list (strcat root "Support"))))
     (if (setq f (open path "r"))
       (progn
         ;; v2.8: 读行中途异常也保证 close(句柄不滞留)
         (vl-catch-all-apply
           '(lambda ( )
              (while (setq ln (read-line f))
                (if (= ln ";;; ==== DT-TOOLS START ====") (setq skipping T))
                (if (null skipping) (setq lines (cons ln lines)))
                (if (= ln ";;; ==== DT-TOOLS END ====") (setq skipping nil))))
           nil)
         (close f)
         (setq lines (reverse lines))))
     (setq block (list
                   ";;; ==== DT-TOOLS START ===="
                   (strcat "(load \"" (dt:st-2bs dir) "\\\\dt_start.lsp\")")
                   (strcat "(dt:st-init \"" (dt:st-2bs dir) "\")")
                   "(dt:st-boot nil)"
                   ";;; ==== DT-TOOLS END ===="))
     (setq r (vl-catch-all-apply
               '(lambda ( / f)
                  (setq f (open path "w"))
                  (if f
                    (progn
                      ;; v2.8: 写中途异常也保证 close
                      (vl-catch-all-apply
                        '(lambda ( ) (foreach ln (append lines block) (write-line ln f)))
                        nil)
                      (close f)
                      T)
                    nil))
               nil))
     (if (vl-catch-all-error-p r) nil r))))

;; 删除钩子: 剥掉标记块回写; 剩空则删文件。成功 T
;; v2.9: 路径同样走 dt:st-acadoc-path(支持根不可用时指向脚本目录那份)
(defun dt:st-remove-hook (dir / path lines f ln skipping n r)
  (setq path (dt:st-acadoc-path dir)
        lines nil)
  (cond
    ((null path) T)            ; 无从定位 -> 视为"本就没有钩子"
    ((null (setq f (open path "r"))) T)
    (T
      ;; v2.8: 读行中途异常也保证 close(句柄不滞留)
      (vl-catch-all-apply
        '(lambda ( )
           (while (setq ln (read-line f))
             (if (= ln ";;; ==== DT-TOOLS START ====") (setq skipping T))
             (if (null skipping) (setq lines (cons ln lines)))
             (if (= ln ";;; ==== DT-TOOLS END ====") (setq skipping nil))))
        nil)
      (close f)
      (setq lines (reverse lines) n 0)
      (foreach ln lines (if (/= ln "") (setq n (1+ n))))
      (cond
        ((= n 0) (vl-file-delete path) T)
        (T
         (setq r (vl-catch-all-apply
                   '(lambda ( / f)
                      (setq f (open path "w"))
                      (if f
                        (progn
                          ;; v2.8: 写中途异常也保证 close
                          (vl-catch-all-apply
                            '(lambda ( ) (foreach ln lines (write-line ln f)))
                            nil)
                          (close f)
                          T)
                        nil))
                   nil))
         (if (vl-catch-all-error-p r) nil r))))))

;; ---------------------------------------------------------------------------
;; 支持路径 / 受信任路径管理(均幂等, catch 保护)
;; ---------------------------------------------------------------------------
(defun dt:st-path-list (s / r p)
  (setq r nil)
  (foreach p (dt:st-split s ";") (if (/= p "") (setq r (cons p r))))
  (reverse r))

(defun dt:st-split (s sep / r i c cur)
  (if (null s)
    nil                       ; v2.9: 老版本系统变量返回 nil 时不再 (strlen nil)
    (progn
      (setq r nil cur "" i 1)
      (repeat (strlen s)
        (setq c (substr s i 1))
        (if (= c sep)
          (setq r (cons cur r) cur "")
          (setq cur (strcat cur c)))
        (setq i (1+ i)))
      (if (/= cur "") (setq r (cons cur r)))
      (reverse r))))

;; dir 加入支持文件搜索路径(重复自动跳过); front=T 时插到最前面。
;; v2.9: front 用于"acaddoc.lsp 兜底写进脚本目录"的场景 —— AutoCAD 只加载
;;   搜索路径里第一个 acaddoc.lsp, 兜底那份必须排在最前才会生效。
;;   old 为 nil 时按 "" 处理(个别环境读不到该属性, 不能让它流进 strcat)。
(defun dt:st-add-support (dir front / r)
  (setq r (vl-catch-all-apply
            '(lambda ( / prefs old items new)
               (setq prefs (vla-get-files
                             (vla-get-preferences (vlax-get-acad-object)))
                     old (vla-get-supportpath prefs))
               (if (null old) (setq old ""))
               (setq items (dt:st-path-list old))
               (if (vl-position (strcase dir) (mapcar 'strcase items))
                 T
                 (progn
                   (setq new (if front
                               (strcat dir (if (= old "") "" ";") old)
                               (strcat old (if (= old "") "" ";") dir)))
                   (vla-put-supportpath prefs new)
                   T)))
            nil))
  (not (vl-catch-all-error-p r)))

;; dir 移出支持文件搜索路径
(defun dt:st-del-support (dir / r)
  (setq r (vl-catch-all-apply
            '(lambda ( / prefs old items keep p)
               (setq prefs (vla-get-files
                             (vla-get-preferences (vlax-get-acad-object)))
                     old (vla-get-supportpath prefs))
               (if (null old) (setq old ""))
               (setq items (dt:st-path-list old)
                     keep nil)
               (foreach p items
                 (if (/= (strcase p) (strcase dir)) (setq keep (cons p keep))))
               (vla-put-supportpath prefs (dt:st-join (reverse keep) ";"))
               T)
            nil))
  (not (vl-catch-all-error-p r)))

;; dir 加入/移出 TRUSTEDPATHS(持久系统变量, 防 SECURELOAD 拦截);
;; v2.6 老版本兼容: TRUSTEDPATHS/SECURELOAD 是 AutoCAD 2016 才引入的 ——
;; 2007~2015 无此变量, getvar/setvar 直接报错会中断 DTINSTALL/DTUNINSTALL。
;; v2.9 关键修复: 老版本上 getvar 对本版本没有的变量**大多静默返回 nil 而非
;;   抛错**, v2.6 只判断了 vl-catch-all-error-p, nil 漏过去后
;;   (dt:st-path-list nil) -> (dt:st-split nil ";") -> (strlen nil) 就炸成
;;     ; 错误: 参数类型错误: stringp nil
;;   这正是低版本 DTINSTALL 报错的根因。现在"抛错 + nil + 非字符串"三种情况
;;   一律视为"该版本无安全拦截机制", 静默跳过(无拦截即无需信任路径)。
(defun dt:st-trusted-add (dir / old r)
  (setq old (vl-catch-all-apply 'getvar (list "TRUSTEDPATHS")))
  (cond
    ((vl-catch-all-error-p old) T)          ; 抛错型: 该版本无此变量
    ((null old) T)                          ; 静默 nil 型: 该版本无此变量(v2.9)
    ((/= (type old) 'STR) T)                ; 非字符串: 不认识, 跳过
    ((vl-position (strcase dir) (mapcar 'strcase (dt:st-path-list old))) T)
    (T (setq r (vl-catch-all-apply
                 'setvar
                 (list "TRUSTEDPATHS" (strcat old (if (= old "") "" ";") dir))))
       (not (vl-catch-all-error-p r)))))

(defun dt:st-trusted-del (dir / old items keep p)
  (setq old (vl-catch-all-apply 'getvar (list "TRUSTEDPATHS")))
  (if (or (vl-catch-all-error-p old) (null old) (/= (type old) 'STR))
    T                                       ; 该版本无此变量 -> 无需清理
    (progn
      (setq items (dt:st-path-list old) keep nil)
      (foreach p items
        (if (/= (strcase p) (strcase dir)) (setq keep (cons p keep))))
      (vl-catch-all-apply
        'setvar (list "TRUSTEDPATHS" (dt:st-join (reverse keep) ";")))
      T)))

;; ---------------------------------------------------------------------------
;; 顶部菜单模块(v2.1): COM 内存构建局部菜单组, 不落盘、不动主 CUI。
;; 结构(二级分组, 燕秀风格):
;;   热流道自动化(&R)
;;   ├ 分流板> 画分流板(OFF) / 分流板参数(PARAM)
;;   ├ 出线槽> 画出线槽(SLOT) / 出线槽参数(SLOTPARAM)
;;   ├ 加热条> 画加热条(JRT) / 加热条参数(JRTPARAM)
;;   ├ 工具> 重载脚本/诊断/安装自启/卸载工具箱/打开脚本目录/演示记录器
;;   └ 关于...
;; 全程 vl-catch-all 保护: 菜单失败只降级为无菜单, 脚本命令不受影响。
;; ---------------------------------------------------------------------------

;; 打开脚本目录(菜单项用)
(defun dt:st-open-dir ( )
  (if dt:st-dir
    (startapp "explorer.exe" (strcat "\"" dt:st-dir "\""))
    (princ "\n【目录】脚本目录未定位, 请先运行 DTRELOAD 或 DTINSTALL。"))
  (princ))

;; 关于框(菜单项用)
(defun dt:st-about ( / fam s)
  (setq s (strcat "热流道自动化工具箱  dt_start " dt:st-version
                  "\n\n脚本目录: "
                  (if dt:st-dir dt:st-dir "(未定位)")
                  "\n\n命令清单:"))
  (foreach fam dt:st-families
    (if (cadddr fam)
      (setq s (strcat s "\n  " (cadr fam) ": " (caddr fam) " 画图 / " (cadddr fam) " 参数"))
      (setq s (strcat s "\n  " (cadr fam) ": " (caddr fam) " 测量分流板 / JRTSZ 测量加热条长度 / XQG·JD·SJTZ 外协出图"))))
  (setq s (strcat s "\n  工具: DTRELOAD 刷新 / DTINSTALL 安装 / DTUNINSTALL 卸载 / DTDBG 诊断 / DTDEMO 演示记录"))
  (alert s)
  (princ))

;; 摘除菜单(幂等, 双路径都清): 1) 自建 DTTOOLS 组 → 组内 popup 移出菜单栏 +
;; Detach 整组; 2) 备用路径塞在 ACAD 组里的同名顶栏 popup → 移出 + Delete。
;; 全部 catch 静默 —— 组不存在/重复调用都不报错
(defun dt:st-menu-remove ( / mgs mg pops i)
  (vl-load-com)
  (setq mgs (vla-get-menugroups (vlax-get-acad-object)))
  ;; 1) 自建 DTTOOLS 组
  (setq mg (vl-catch-all-apply 'vla-item (list mgs dt:st-menugroup)))
  (if (not (vl-catch-all-error-p mg))
    (progn
      (vl-catch-all-apply
        '(lambda ( )
           (setq pops (vla-get-menus mg) i 0)
           (repeat (vla-get-count pops)
             (vl-catch-all-apply 'vla-removefrommenubar (list (vla-item pops i)))
             (setq i (1+ i)))))
      (vl-catch-all-apply 'vla-detach (list mg))))
  ;; 2) ACAD 组内我们的同名顶栏 popup(倒序遍历, 边删边移安全)
  (vl-catch-all-apply
    '(lambda ( / ag n pp)
       (setq ag (vla-item mgs "ACAD")
             pops (vla-get-menus ag)
             n (vla-get-count pops))
       (while (> n 0)
         (setq n (1- n) pp (vla-item pops n))
         (if (= (strcase (vla-get-name pp)) (strcase dt:st-menutitle))
           (progn
             (vl-catch-all-apply 'vla-removefrommenubar (list pp))
             (vl-catch-all-apply 'vla-delete (list pp)))))))
  (princ))

;; 菜单宏构造(v2.5): 真控制字符 chr 3(^C, 两个=取消两极) + LISP 表达式
;; + 尾部空格(菜单宏语法: 空格=回车; 实测 COM 宏播放器不自动补回车)。
;; COM 通道宏不经文件解析器, "^C^C" 文本不会被翻译(实测) —— 必须用 chr 3;
;; 命令统一包成 (c:XXX), 点击后由尾部空格提交执行。
(defun dt:st-macro (expr)
  (strcat (chr 3) (chr 3) expr " "))

;; 构建 + 挂出菜单(每会话只走一次)。v2.3 实测定案:
;;   2024 已移除 MenuGroups.Add → 直接用 ACAD 主菜单组放 popup;
;;   同名 popup 已存在(删除被拒的残留)→ 直接复用, 不再新建。
;; 成功返回 T, 失败返回 nil(错误信息照实打印)
(defun dt:st-menu-build ( / acads mgs mg pops popMain fresh idx fam zh mc pc hk sub)
  (setq acads (vlax-get-acad-object)
        mgs (vla-get-menugroups acads))
  (dt:st-menu-remove)
  ;; 自建组尝试每会话一次(2024 报"未知名称: Add", 提示一次即可)
  (setq mg nil)
  (if (null *dt-st-mg-add-tried*)
    (progn
      (setq *dt-st-mg-add-tried* T
            mg (vl-catch-all-apply 'vla-add (list mgs dt:st-menugroup)))
      (if (vl-catch-all-error-p mg)
        (princ (strcat "\n【菜单】自建菜单组不可用(" (vl-catch-all-error-message mg)
                       "), 使用 ACAD 主菜单组。"))
        (princ "\n【菜单】使用自建菜单组 DTTOOLS。"))))
  (if (or (null mg) (vl-catch-all-error-p mg))
    (setq mg (vl-catch-all-apply 'vla-item (list mgs "ACAD"))))
  (cond
    ((or (null mg) (vl-catch-all-error-p mg))
     (princ "\n【菜单】ACAD 主菜单组定位失败, 菜单跳过(脚本命令仍可用)。")
     nil)
    (T
     (setq pops (vla-get-menus mg))
     ;; 同名 popup 已存在(上次删除被拒的残留)→ 复用; 不存在 → 新建并填内容
     (setq popMain (vl-catch-all-apply 'vla-item (list pops dt:st-menutitle))
           fresh (vl-catch-all-error-p popMain))
     (if fresh
       (progn
         (setq popMain (vla-add pops dt:st-menutitle)
               idx 0)
         ;; 各脚本家族: 二级子菜单(分流板/加热条/出线槽/外协加工)
         (foreach fam dt:st-families
           (setq zh (cadr fam) mc (caddr fam) pc (cadddr fam) hk (nth 4 fam))
           (setq sub (vla-addsubmenu popMain idx (strcat zh "(&" hk ")")))
           (if pc
             (progn
               (vla-addmenuitem sub 0 (strcat "画" zh "(&D)") (dt:st-macro (strcat "(c:" mc ")")))
               (vla-addmenuitem sub 1 (strcat zh "参数(&P)") (dt:st-macro (strcat "(c:" pc ")"))))
             (progn
               ;; 外协加工三级项(v3.5 顺序 = 用户指定使用频率):
               ;;   测量加热条长度 / 测量分流板 / 数据图纸 / 线切割 / 精雕
               (vla-addmenuitem sub 0 "测量加热条长度(&C)" (dt:st-macro "(c:JRTSZ)"))
               (vla-addmenuitem sub 1 "测量分流板(&F)" (dt:st-macro (strcat "(c:" mc ")")))
               (vla-addmenuitem sub 2 "数据图纸(&D)" (dt:st-macro "(c:SJTZ)"))
               (vla-addmenuitem sub 3 "线切割(&W)" (dt:st-macro "(c:XQG)"))
               (vla-addmenuitem sub 4 "精雕(&J)" (dt:st-macro "(c:JD)"))))
           (setq idx (1+ idx)))
         ;; 工具子菜单
         (vla-addseparator popMain idx)
         (setq idx (1+ idx))
         (setq sub (vla-addsubmenu popMain idx "工具(&T)"))
         (vla-addmenuitem sub 0 "重载脚本(&R)" (dt:st-macro "(c:DTRELOAD)"))
         (vla-addmenuitem sub 1 "诊断(&G)" (dt:st-macro "(c:DTDBG)"))
         (vla-addmenuitem sub 2 "安装自启(&I)" (dt:st-macro "(c:DTINSTALL)"))
         (vla-addmenuitem sub 3 "卸载工具箱(&U)" (dt:st-macro "(c:DTUNINSTALL)"))
         (vla-addmenuitem sub 4 "打开脚本目录(&O)" (dt:st-macro "(dt:st-open-dir)"))
         (vla-addmenuitem sub 5 "演示记录器(&M)" (dt:st-macro "(c:DTDEMO)"))
         (setq idx (1+ idx))
         ;; 关于
         (vla-addseparator popMain idx)
         (setq idx (1+ idx))
         (vla-addmenuitem popMain idx "关于(&A)..." (dt:st-macro "(dt:st-about)")))
       (progn
         ;; 复用残留前抽查宏格式: "^"开头(字面量坏宏)或尾无空格(缺回车)
         ;; 均为旧版坏菜单 —— 提示重启 CAD 让新版重建
         (vl-catch-all-apply
           '(lambda ( / mac)
              (setq mac (vla-get-macro
                          (vla-item (vla-get-submenu (vla-item popMain 0)) 0)))
              (if (or (= (substr mac 1 1) "^")
                      (/= (substr mac (strlen mac)) " "))
                (princ "\n【菜单】残留菜单是旧格式(宏失效), 请重启 CAD 让新版自动重建。"))))
         (princ "\n【菜单】发现残留菜单, 直接复用。")))
     (setq dt:st-popmain popMain
           *dt-st-menu-done* T)
     ;; 挂到菜单栏(帮助项前); 已在栏上时插入报错无妨(顶栏已显示即正常)
     (setq idx (vl-catch-all-apply
                 'vla-insertinmenubar
                 (list popMain (max 0 (1- (vla-get-count (vla-get-menubar acads)))))))
     (if (vl-catch-all-error-p idx)
       (princ (strcat "\n【菜单】插入菜单栏返回: " (vl-catch-all-error-message idx)
                      "(若顶栏已显示菜单则为正常)。")))
     T)))

;; 幂等挂菜单(boot/DTRELOAD 调用): 本会话已建成则只重挂到菜单栏(工作区切换
;; 挤掉后找回), 未建成才走完整构建。失败只提示, 不影响脚本。
(defun dt:st-menu-ensure ( / r)
  (if *dt-st-menu-done*
    (progn
      (setq r (vl-catch-all-apply
                'vla-insertinmenubar
                (list dt:st-popmain
                      (max 0 (1- (vla-get-count
                                   (vla-get-menubar (vlax-get-acad-object))))))))
      (if (vl-catch-all-error-p r)
        (princ (strcat "\n【菜单】重挂返回: " (vl-catch-all-error-message r)
                       "(顶栏已有菜单则为正常)"))))
    (progn
      (setq r (vl-catch-all-apply 'dt:st-menu-build nil))
      (cond
        ((vl-catch-all-error-p r)
         (princ (strcat "\n【菜单】挂载失败: " (vl-catch-all-error-message r))))
        (r (princ "\n【菜单】顶部菜单已挂出: 热流道自动化(R)")))))
  (princ))

;; ---------------------------------------------------------------------------
;; 命令
;; ---------------------------------------------------------------------------
(defun c:DTINSTALL ( / dir ok root fb p)
  (setq dir (dt:st-locate))
  (cond
    ((null dir) (princ "\n【安装】未定位到目录, 已取消。"))
    (T
     (setq root (dt:st-support-root)
           fb (= root ""))     ; T = 兜底模式: acaddoc.lsp 只能写进脚本目录
     (princ (strcat "\n【安装】ACADVER=" (dt:st-gets "ACADVER")
                    "  Support 根=" (if fb "(本版本取不到, 改用脚本目录兜底)" root)))
     (princ (strcat "\n【安装】系统变量可用性: TRUSTEDPATHS="
                    (if (dt:st-hasvar "TRUSTEDPATHS") "有" "无(老版本, 跳过)")
                    "  SECURELOAD=" (if (dt:st-hasvar "SECURELOAD") "有" "无(老版本, 跳过)")))
     ;; v2.9: 先加支持路径(兜底模式要顶到最前, 否则脚本目录里的 acaddoc.lsp
     ;; 排在后面, AutoCAD 根本不会加载它), 再写钩子
     (dt:st-add-support dir fb)
     (setq ok (dt:st-write-hook dir))
     (if ok (dt:st-trusted-add dir))
     (if ok
       (progn
         (setq p (dt:st-acadoc-path dir))
         (princ "\n【安装】完成: 钩子已写入 acaddoc.lsp(含确定性目录注入), 目录已加入支持/受信任路径。")
         (princ (strcat "\n【安装】钩子文件: " (if p p "(未定位)")))
         (princ "\n【安装】以后开 CAD 自动加载全部脚本并挂出顶部菜单「热流道自动化(R)」; 本次会话已生效:")
         (princ "\n【安装】提示: 升级旧版本请先 DTUNINSTALL 清旧钩子再 DTINSTALL。"))
       (princ "\n【安装】警告: acaddoc.lsp 写入失败(权限?), 自启未生效; 本次会话仍可用。"))
     (dt:st-boot T)))
  (princ))

(defun c:DTRELOAD ( )
  (princ "\n【刷新】重新扫描加载最新版本...")
  (dt:st-boot T))

;; 演示记录器(v3.1): 按需加载 scripts\demo_recorder.lsp 并 开/关 录制。
;; 不进家族表不随启动加载(反应器工具常驻无必要); 文件缺失时明确提示。
(defun c:DTDEMO ( / dir f)
  ;; v3.6: 不再判 (null demo:gets) —— defun 只设函数槽不设值槽, 函数名当
  ;;   变量求值恒为 nil(坑 #72), 该守卫恒真; 一律走"定位→加载→开录"。
  (cond
    (*demo-on* (c:DEMOSTOP))
    (T
     (setq dir (dt:st-locate))
     (cond
       ((null dir)
        (princ "\n【演示】未定位到脚本目录, 无法加载 demo_recorder.lsp。"))
       ((null (setq f (dt:st-pick dir "demo_recorder")))
        (princ "\n【演示】脚本目录里没有 demo_recorder.lsp。"))
       ((vl-catch-all-error-p (vl-catch-all-apply 'load (list (strcat dir "\\" f))))
        (princ "\n【演示】demo_recorder.lsp 加载失败, 报错见命令行。"))
       (T (c:DEMOREC)))))
  (princ))

;; 诊断命令(v2.0): 打印目录/选版信息 + 逐步执行 offset 参数对话框链路,
;; 定位"stringp"类错误的确切位置。
(defun c:DTDBG ( / r dcl-file dcl-id nd p v f ln fam sv)
  (princ "\n【DTDBG】=== 目录/选版/对话框链路 逐步诊断 ===")
  ;; 0z) 运行环境探测(v2.9): 直接点名 stringp nil 的三处高发系统变量
  (princ (strcat "\n[0z] ACADVER=" (dt:st-gets "ACADVER")
                 "  Support 根=" (vl-prin1-to-string (dt:st-support-root))))
  (foreach sv (list "DWGPREFIX" "ROAMABLEROOTPREFIX" "LOCALROOTPREFIX"
                    "TRUSTEDPATHS" "SECURELOAD")
    (princ (strcat "\n     " sv " = "
                   (if (dt:st-hasvar sv)
                     (dt:st-gets sv)
                     "**本版本无此变量(getvar 返回 nil)**"))))
  (princ (strcat "\n[0z] acaddoc.lsp 落点 = "
                 (vl-prin1-to-string (dt:st-acadoc-path (dt:st-locate)))))
  ;; 0a) 目录注入状态(核心: 各脚本 find-dcl 依赖 *dt-script-dir*)
  (princ (strcat "\n[0a] *dt-script-dir*=" (vl-prin1-to-string *dt-script-dir*)
                 "  dt:st-dir=" (vl-prin1-to-string dt:st-dir)))
  ;; 0b) 各家族实际选中的文件
  (foreach fam dt:st-families
    (princ (strcat "\n[0b] " (cadr fam) " → "
                   (vl-prin1-to-string
                     (if *dt-script-dir*
                       (dt:st-pick *dt-script-dir* (car fam))
                       nil)))))
  ;; 0c) 参数全局变量当前值(任何一项是 T/nil 都会致病)
  (princ "\n[0c] 参数表当前值:")
  (foreach p dt:param-table
    (princ (strcat " " (car p) "=" (vl-prin1-to-string (eval (cadr p))))))
  ;; 1) find-dcl
  (setq r (vl-catch-all-apply 'dt:find-dcl nil))
  (if (vl-catch-all-error-p r)
    (princ (strcat "\n[1] dt:find-dcl 错误: " (vl-catch-all-error-message r)))
    (progn
      (setq dcl-file r)
      (princ (strcat "\n[1] dt:find-dcl → " (vl-prin1-to-string dcl-file)))
      ;; 2) 写出的 dcl 文件首行(应为 "dt_param : dialog {")
      (if (and dcl-file (setq f (open dcl-file "r")))
        (progn
          (setq ln (read-line f))
          (close f)
          (princ (strcat "\n[2] dcl 文件首行 → " (vl-prin1-to-string ln))))
        (princ "\n[2] dcl 文件无法读取"))
      ;; 3) load_dialog
      (setq r (vl-catch-all-apply 'load_dialog (list dcl-file)))
      (if (vl-catch-all-error-p r)
        (princ (strcat "\n[3] load_dialog 错误: " (vl-catch-all-error-message r)))
        (progn
          (setq dcl-id r)
          (princ (strcat "\n[3] load_dialog → " (vl-prin1-to-string dcl-id)))
          ;; 4) new_dialog
          (setq nd (vl-catch-all-apply 'new_dialog (list "dt_param" dcl-id)))
          (if (vl-catch-all-error-p nd)
            (princ (strcat "\n[4] new_dialog 错误: " (vl-catch-all-error-message nd)))
            (progn
              (princ (strcat "\n[4] new_dialog → " (vl-prin1-to-string nd)))
              ;; 5) 逐 key 预填(哪一行报错即是哪个参数/哪类调用出错)
              (foreach p dt:param-table
                (setq v (vl-catch-all-apply
                          '(lambda (q / s)
                             (setq s (rtos (eval (cadr q)) 2 2))
                             (set_tile (car q) s)
                             s)
                          (list p)))
                (princ (strcat "\n    [5] set_tile " (car p) " → "
                               (if (vl-catch-all-error-p v)
                                 (strcat "错误: " (vl-catch-all-error-message v))
                                 "OK"))))
              ;; 6) start_dialog(会弹出真实对话框, 点确定/取消均可)
              (setq r (vl-catch-all-apply 'start_dialog nil))
              (princ (strcat "\n[6] start_dialog → "
                             (if (vl-catch-all-error-p r)
                               (strcat "错误: " (vl-catch-all-error-message r))
                               (vl-prin1-to-string r))))
              (vl-catch-all-apply 'unload_dialog (list dcl-id))))))))
  (princ "\n【DTDBG】=== 诊断结束, 请把以上全部输出发回 ===")
  (princ))

(defun c:DTUNINSTALL ( / dir)
  (setq dir (dt:st-locate))
  (dt:st-menu-remove)
  (dt:st-remove-hook dir)
  (if dir
    (progn
      (dt:st-del-support dir)
      (dt:st-trusted-del dir)))
  (setq *dt-st-loaded* nil
        *dt-script-dir* nil
        *dt-st-menu-done* nil
        dt:st-popmain nil
        *dt-st-mg-add-tried* nil)
  (vl-propagate '*dt-st-loaded*)
  (vl-propagate '*dt-script-dir*)
  (princ "\n【卸载】完成: 自启动钩子/支持路径/受信任路径已移除, CAD 配置恢复原样。")
  (princ "\n【卸载】顶部菜单已摘除(若 CAD 限制未删净, 重启 CAD 后自然消失)。")
  (princ "\n【卸载】脚本文件本身未删除; 本会话已加载的命令仍可用直至关闭 CAD。")
  (princ))

;;; 加载提示
(princ (strcat "\ndt_start 已加载 " dt:st-version
               ": DTINSTALL=安装自启 / DTRELOAD=刷新 / DTUNINSTALL=卸载 / DTDBG=诊断 / DTDEMO=演示。"))
(princ)
