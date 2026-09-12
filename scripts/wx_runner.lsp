;;; ============================================================================
;;; 热流道自动化系统 - 外协加工与尺寸数据测量工具 (wx_runner.lsp)
;;;
;;; 功能:
;;;   1. 分流板(FLB)最长与最宽尺寸自动提取 (c:FLBSZ / c:FLBSIZE)
;;;      - 优先自动扫描 FLB 图层；未找到或未闭合时自动转入手动框选模式
;;;      - 双引擎闭合区域校验: 原生 ACIS Region 面域引擎 + 0.5mm 容差端点拓扑度数引擎
;;;      - AABB + OBB 最佳外包矩形算法，精准计算最长边(Length)与最宽边(Width)
;;;      - 测量结果自动写入 Windows 剪贴板 (如 "350*180"，可直接 Ctrl+V 粘贴进下料单)
;;;      - 交互式确认后在 FLB_BOX 图层绘制包络矩形与长宽标注(字高>=15)
;;;   1b. 加热条(JRT)长度测量 (c:JRTSZ)
;;;      - 自动识别 JRT 图层加热条(空间聚类分条)，多条时列出清单点选、可连续测量
;;;      - 长度 = 嵌套轮廓线长度中位数(等价"总长/条数"，对个别短链更稳健)
;;;      - 自动排除破口封闭线: 优先 JRTFBX 定位副本精确匹配，无副本时几何识别
;;;      - 检测不到/仅1条开口线/端点断口 0.01~2mm → 弹窗提示并取消，不降级手动选择
;;;      - 结果自动写入 Windows 剪贴板
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
;;; 版本: v2.18
;;; v2.18 : 体检修复五项(几何零变化):
;;;         ①dt:sz-export-to-dwg 加局部 *error* 兜底: 中途抛错关闭悬挂的
;;;           UNDO 组并清理临时克隆(沿用 c:FLBSZ 的 undo-started 惯用法),
;;;           不再残留 front/back/txt 临时实体;
;;;         ②dt:sz-copy-clip 回退路径改"写临时文件 + clip < 文件": 不再把
;;;           内容拼进 cmd 命令行, 消除元字符命令注入面;
;;;         ③WBLOCK 回退临时名改 vl-filename-mktemp 唯一生成: 固定名
;;;           _dt_wx_tmp.dwg 双开 CAD 并发导出时互删对方中间文件;
;;;         ④dt:sz-cfg-get 定位顺序改确定性优先: 先取 *dt-script-dir* 旁
;;;           的 wx_runner.ini, 才 findfile 全局 —— 多副本环境不再命中
;;;           支持路径里其它目录的同名旧副本(flb dcl 同款坑);
;;;         ⑤排版四项 ini 值 atof 换 dt:sz-num-or(distof 校验): 垃圾串
;;;           不再静默变 0.0 画出贴死排版(坑 #54 口径)。
;;; v2.17 : 归堆间距可配(用户需求): wx_runner.ini 新 [测量加热条] 节
;;;         strip_gap(默认 15.0) —— 全部 JRT 曲线按"最小间距 <= strip_gap"
;;;         归成一根根加热条; 误填 <1 按默认 15 处理(防把一根条的嵌套线
;;;         拆散)。逻辑零变化(默认值与 v2.16 一致)。
;;; v2.16 : 修 v2.15(未交付, 用户实测后废弃其识别方案)实测缺陷: 结果成了
;;;         "三层线加一起没除" —— 几何识别兜底在用户图上没认出封闭线,
;;;         三层线被封闭线连成一串后被当成"一条线"量了总长。按用户定案
;;;         重做封闭线排除: "生成时怎么画封闭线, 测量时就怎么认" ——
;;;         · 只剔封闭线本身, 圆弧一律不再连带剔除(v2.15 的相切弧带出废除);
;;;         · 几何复核 = 生成规则的反推: 生成时封闭线就是把最外层与最内层
;;;           线头连起来的短直线(两头各一根), 反推 = 条内"两头都接在别的
;;;           线上"的短直线当候选, 试着剔除 —— 剔掉后其余线恰能分成"几条
;;;           长度几乎一样"的线链(嵌套轮廓该有的样子)才确认; 剔掉后线链
;;;           长短反而更乱的(普通轮廓短段被误去的样子)一律不动。封闭线
;;;           两头成对, 单根不见分晓时自动改试"成对剔除"(只试最短 12 根
;;;           候选, 防组合爆炸); v2.15 的"连通分量数不增加就整体放弃"与
;;;           "近垂直横档切向过滤"一并废除;
;;;         · 每条都跑几何复核(不再只在无 JRTFBX 时启用) —— JRTFBX 只匹配
;;;           到一半时剩下的那根也能补剔;
;;;         · 结果输出加"各层线长"明细与"各层长度差异偏大请人工核对"警告;
;;;         · 圆帽整圆(无端点)与侧线切点补"端点贴线身"相接判定(通用一
;;;           圆帽条此前会被拆散成侧线+整圆各算一条);
;;;         · 输出措辞改大白话("N 层嵌套线各量一遍取中间值")。
;;; v2.15 : 新增测量加热条长度 (c:JRTSZ, 菜单「外协加工▸测量加热条长度」,
;;;         与测量分流板同级, 用户需求): 长度=各层嵌套线取中间值; 封闭线
;;;         排除 = JRTFBX 副本精确匹配 + 几何识别兜底; 多条列表点选连测;
;;;         检测不到/仅 1 条开口线/端点断口 0.01~2mm → 弹窗取消不降级;
;;;         结果写剪贴板; 只读测量不建图层。(其几何识别方案被 v2.16 替换)
;;; v2.14 : 修 v2.13 实测缺陷(用户截图: 同一行各幅 Y 乱飘 + 永不换行):
;;;         根因 = v2.13 用"目标图里 MText 的 boundingbox"算行顶/行右缘, 而
;;;         AutoCAD 对**非活动文档**中刚 CopyObjects 过去的 MText, 实体范围
;;;         (boundingbox)不可靠(与本项目已知的"非活动文档图层色/字体不即时
;;;         生效"同一类坑) —— 实测把行顶算低 86mm: 每幅 Y 偏移 → 下一幅文字
;;;         插入点 Y 与上一幅差 >1mm → 行判定失效(grid-col 恒 1) → 永不换行,
;;;         6 幅全挤一行且 Y 乱跳。
;;;         修法: 排版基准只取"可靠源" ——
;;;           · 行判定 / 行内容顶: "外协文字"插入点(属性直读, 可靠;
;;;             插入点 = 文字底边 = 内容顶 + text_gap)
;;;           · 行右缘 / 内容最底缘: 内容实体 bbox(线框数据, 可靠)
;;;           · 单元盒尺寸: 在当前图量(可靠, 见 4f)
;;;         并把"换行起点"由固定 x=0 改为对齐已有内容左缘(往任何图里追加
;;;         都不会出现阶梯错位)。头注以下 v2.13 条目保留作版本账。
;;; v2.13 : 排版间距根治(用户需求, 四项):
;;;         ①精雕包络盒间距四向统一 —— 旧版盒定义不对称(左/下 20, 上=文字顶
;;;           +20), 实测横向净距 = box_gap-20、纵向 = 50+文字高-box_gap(略
;;;           重叠)。改为"单元包络盒 = (图形 ∪ 本幅文字) 外扩 box_margin",
;;;           行内追加取上一幅盒右缘 + box_gap, 换行取内容最底缘下方 box_gap
;;;           —— 四向净距恒 = box_gap;
;;;         ②线切割间距偶发不一致根治 —— 旧版会话游标缺失(新开 CAD/换目标图
;;;           后的首幅)时回退用"文字 maxx"作基准, 文字居中且宽钳 <=220, 比
;;;           工件窄 → 首幅间距偏大(实测 10 幅里 1 幅不同)。改为缺游标时由
;;;           几何反推本行单元盒右缘(dt:sz-row-right);
;;;         ③文字与图形的距离可配 —— 旧版硬编码 50, 新增 [排版] text_gap;
;;;           基准 = "图形最小包络盒"顶边(摆正后的最小外包盒, 等价于测量
;;;           分流板命令的 AABB/OBB 算法; 不实际生成包络盒, 仅作基准);
;;;         ④[排版] 四项全部可配: box_gap / per_row / text_gap / box_margin。
;;;         实现要点: 文字改在"当前图"临时生成并量出真实包围盒(与图形合成
;;;         单元盒), 随工件一起拷入目标图 —— 无需事后回填位置。
;;; v2.12 : 精雕图改黄 + 包络盒改绿(用户需求): JD 层色 101→2(黄), 且精雕
;;;         正反面实体统一置黄 2(覆盖 v2.7~v2.11 的逐实体保色); 外协包络盒
;;;         222→3(绿, 层色与盒实体色同步)。精雕输出是独立 dwg, 与主图
;;;         JRT(黄 2)/FBX(绿 3)同色不构成同图歧义 —— check_layer_colors.py
;;;         对 JD/外协包络盒 豁免唯一性与色差校验(登记核对与字面量白名单仍查)。
;;;         逻辑零变化。
;;; v2.11 : 全图层配色重排(用户需求, 与 flb v10.11 同批): FLB_BOX 130→42
;;;         (赭黄), 数据图纸 7→63(橄榄绿), 外协文字 7→144(深青), JD 7→101
;;;         (薄荷绿), 外协包络盒 3→222(紫红), ZJJ 210→193(灰紫); ensure-
;;;         layer 已存在图层也校正为登记色(老图重跑自动换新色)。逻辑零变化。
;;;         新增回归 tools/check_layer_colors.py。(注: JD 与 外协包络盒 的色
;;;         已于 v2.12 再改 —— 见上)
;;; v2.10 : 加载横幅精简为一行 + 新增 *dt-wx-ver* 版本单一来源(根治横幅
;;;         版本号长期滞后, 本次 v2.8 → v2.10 追平)。
;;; v2.9  : 体检B-01/B-02/B-05/B-06/B-11/B-12 六项修复:
;;;         ①精雕保色实参改 cur-doc —— flatten-layer 查 ByLayer 实体的
;;;           "原图层色"必须查源侧, 传 tgt-doc 查到的是目标图 ensure 过
;;;           的固定层色, 原色保留落空(v2.7 注释失实);
;;;         ②兜底根目录 C:\Users\5600\... 改 USERPROFILE 推导(换机不炸);
;;;         ③行内排版定位改会话级真实右缘游标 *dt-wx-last-right*(按目标
;;;           图纸键控) —— 标题文字宽钳 <=220 且居中, 工件宽>180 时文字
;;;           maxx 落在工件包络内, 旧写法两幅重叠; 跨会话回退文字 maxx;
;;;         ④FLBSZ *error* 补 undo-started 兜底闭合包络框 UNDO 组;
;;;         ⑤SJTZ 的 (command "_.UNDO" "E") 改 COM endundomark(归一坑#69);
;;;         ⑥删除死全局 *dt-outsource-target-dwg* 与死函数 dt:sz-norm-ang
;;;           (体检 grep 全库零引用取证)。
;;; v2.8  : 修复精雕图层合并未生效 + 层名改英文(用户实测反馈):
;;;         ①根因 = 临时实体在 cur-doc 而 v2.7 只在 tgt 建"精雕"层,
;;;           put-layer 因层不存在静默失败 —— 两个文档都 ensure JD 层;
;;;         ②层名 "精雕" → "JD"(用户要求不用中文);
;;;         ③copyobjects 后把目标图中 FLB/LS/RZ/DK/JRT/DP/ZJJ 残留实体
;;;           全部移入 JD 层并删除这些原图层(dt:sz-migrate-layers);
;;;         ④线切割撤销 v2.7 的 flatten(目标本就单层, 用户确认无需处理)。
;;; v2.7  : 曲线合并单图层保色 + 换行数量参数化(用户需求):
;;;         ①精雕: 正反面各自合并到单一图层"精雕"(层色白), 逐实体保留
;;;           原色 —— ByLayer(0) 的先转存原图层 ACI 色再换层(dt:sz-flatten-layer);
;;;         ②线切割: 置入 FLB 层同样走 flatten 保色(原 put-layer 丢色);
;;;         ③每行幅数参数化: ini [排版] per_row(默认 4), 改 5 即 5 幅一行。
;;; v2.6  : 修复追加报 numberp nil + 包络盒内部边距(用户实测反馈):
;;;         ①grid-col 漏初始化 —— 首幅(无既有文字)不进计数循环所以
;;;           成功, 追加时 (1+ nil) 抛 numberp: nil, 补 setq grid-col 0;
;;;         ②盒与内容之间恢复 20mm 内边距(v2.5 误改为 0, 用户只要求
;;;           盒与盒之间间距统一), 行内锚定/换行补偿 20mm 保持盒间净距
;;;           = box_gap。
;;; v2.5  : 修复行内漂移 + 包络盒间距统一 + 剪贴板分隔符(用户实测反馈):
;;;         ①行内追加 x 参照从"图纸整体 maxx"改为"当前行文字 bbox 的
;;;           maxx + box_gap" —— 整体 maxx 会命中上一行末尾图形(行向下
;;;           堆叠), 正是漂移根因;
;;;         ②包络盒边距归零(盒=内容精确 bbox), 行/列/盒间距统一为 ini
;;;           单参数 [排版] box_gap(默认 100mm), 上下左右恒定; 移除
;;;           col_gap/row_gap;
;;;         ③剪贴板分隔符 "x" → "*" (用户下料单格式)。
;;; v2.4  : 修复排版网格重叠/乱飘 + 包络盒首幅颜色(用户实测反馈):
;;;         ①排版游标弃用跨文档系统变量(USERI5/USERR5 在非活动文档上
;;;           读写不可靠 —— 重叠/乱飘根因), 改纯几何推导: 以目标图
;;;           "外协文字"层 MText 为单位标记(每幅 1 个), 当前行 = 插入点
;;;           Y 最小的行, 行内 <4 幅行内追加(与行顶对齐), 满 4 幅向下
;;;           换行; 对旧图纸/跨会话天然正确;
;;;         ②包络盒实体级 vla-put-color 3(图层色在非活动文档不即时
;;;           生效 —— 首幅显示灰/黑根因), 首幅即显绿色。
;;;         新增 dt:sz-doc-texts; 移除 dt:sz-sysvar-get/set。
;;; v2.3  : 精雕/线切割排版改版(用户需求): ①精雕镜像改在本体右侧(竖直镜像轴,
;;;          正反面间隔仍 75mm); ②精雕每幅(本体+镜像+文字)整体包络盒框住,
;;;          独立图层"外协包络盒"(绿色 3), 文字生成后取实际 bbox 精确包络;
;;;          ③排版改网格: 每行最多 4 幅, 行满向下追加(1234/5678), 列距/行距
;;;          走 wx_runner.ini [排版] col_gap/row_gap(默认各 100mm); 排版游标
;;;          存目标图纸 USERI5(幅数)/USERR5(上幅 Y 基线), 跨会话可靠续排,
;;;          旧图纸无游标时自动从现有内容右侧续排; ④线切割仅改网格布局
;;;          (不加包络盒)。新增 dt:sz-sysvar-get/set, dt:sz-mirror-in-curdoc
;;;          签名改为任意轴两点。
;;; 平台: AutoCAD 2007 ~ 2026 (AutoLISP + COM ActiveX)
;;; ============================================================================

(vl-load-com)

;; 版本单一来源: 发版时与头注同行更新; 加载横幅引用本值(防两处手抄脱节)
(setq *dt-wx-ver* "v2.18")

;; 会话级全局记忆
(setq *dt-xqg-target-dwg* nil)       ;; 线切割目标图纸路径记忆
(setq *dt-jd-target-dwg* nil)        ;; 精雕目标图纸路径记忆
(setq *dt-sz-multi-regions* nil)     ;; 多连通域检测状态
(setq *dt-sjtz-kh* nil)              ;; 数据图纸客户名称记忆
(setq *dt-sjtz-mj* nil)              ;; 数据图纸模具编号记忆
(setq *dt-sjtz-zxj* nil)             ;; 数据图纸中心距记忆
(setq *dt-sjtz-flb* nil)             ;; 数据图纸分流板规格记忆
(setq *dt-wx-last-right* nil)        ;; v2.9 上一幅排版真实右缘 X(会话级)
(setq *dt-wx-last-right-path* nil)   ;; 右缘游标对应的目标图纸路径(换图即失效)
(setq *dt-sjtz-rz* nil)              ;; 数据图纸热咀规格记忆
(setq *dt-sjtz-cx* nil)              ;; 数据图纸出线记忆

;; ============================================================================
;; 一、公共几何与环境基础函数 (自包含库, 跨脚本同名逐字一致, 坑 #46)
;; ============================================================================

;; AutoLISP 环境补丁: stringp 函数垫片 (原生 AutoLISP 无此函数, 坑 #68)
(if (null (boundp 'stringp)) (defun stringp (x) (= (type x) 'STR)))

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
;; v2.11: 已存在图层也把颜色校正为登记值(全图层配色重排, 老图自动刷新)。
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
      (setq obj (vl-catch-all-apply 'vla-item (list layers name)))
      (if (and (not (vl-catch-all-error-p obj)) obj
               (/= (vl-catch-all-apply 'vla-get-color (list obj)) color))
        (vla-put-color obj color))
      (princ (strcat "\n图层 \"" name "\" 已存在, 颜色已对齐登记值(" cname ")。"))
      nil)))

;; vla-getboundingbox 在不同 CAD 版本/运行上下文下, 传出值可能是 variant
;; 也可能是 raw safearray(v10.0 踩坑: 2024 上是 variant, variant-value 解出
;; safearray; 低版本或纯 LISP 环境下可能已是 safearray)。
(defun dt:rect-bb-pts (x)
  (if (= (type x) 'variant)
    (vlax-safearray->list (vlax-variant-value x))
    (vlax-safearray->list x)))

;; 安全解包 variant/safearray/list 坐标点列表
(defun dt:sz-safe-pts (x)
  (cond
    ((null x) nil)
    ((listp x) x)
    ((= (type x) 'variant)
     (vlax-safearray->list (vlax-variant-value x)))
    ((= (type x) 'safearray)
     (vlax-safearray->list x))
    (T nil)))

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
                    ((or (= oname "AcDb2dPolyline") (= oname "AcDb3dPolyline")) "POLYLINE")
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
;; v2.18: 回退路径不再把 str 拼进 cmd 命令行 —— 改写临时文件后 clip < 文件,
;;   内容里的 " & | ^ 等元字符不再有命令注入面(现在只传数字串, 防患未然)。
(defun dt:sz-copy-clip (str / html r tmp f)
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
         (setq tmp (vl-filename-mktemp "_dt_clip_.txt"))
         (if tmp
           (progn
             (setq f (open tmp "w"))
             (princ str f) ; write-line 会附加换行, 粘贴进下料单多一个空行
             (close f)
             ;; startapp 是异步的: cmd/clip 需几十毫秒才读文件, 立即删除会让
             ;; 剪贴板内容丢失 —— 临时文件留在 %TEMP% 由系统清理, 不再删除
             (startapp (strcat "cmd.exe /c clip <\"" tmp "\"")))))
      nil))
  T)

;; 曲线采样点提取(用于 OBB/AABB 包络范围计算)
(defun dt:sz-curve-sample-pts (o / oname pts sp ep n i pt b cen r)
  (setq pts nil
        oname (vl-catch-all-apply 'vla-get-objectname (list o)))
  (if (and (not (vl-catch-all-error-p oname)) (= (type oname) 'STR))
    (cond
      ((= oname "AcDbLine")
       (setq sp (vl-catch-all-apply 'vlax-curve-getstartpoint (list o))
             ep (vl-catch-all-apply 'vlax-curve-getendpoint (list o)))
       (if (and (not (vl-catch-all-error-p sp)) sp
                (not (vl-catch-all-error-p ep)) ep)
         (setq pts (list (list (car sp) (cadr sp))
                         (list (car ep) (cadr ep))))))

      ((= oname "AcDbCircle")
       (setq cen (vl-catch-all-apply 'vla-get-center (list o))
             r   (vl-catch-all-apply 'vla-get-radius (list o)))
       (if (and (not (vl-catch-all-error-p cen)) cen
                (not (vl-catch-all-error-p r)) (numberp r))
         (progn
           (setq cen (dt:sz-safe-pts cen))
           (if (and cen (listp cen) (>= (length cen) 2))
             (setq pts (list (list (- (car cen) r) (cadr cen))
                             (list (+ (car cen) r) (cadr cen))
                             (list (car cen) (- (cadr cen) r))
                             (list (car cen) (+ (cadr cen) r))))))))

      ((= oname "AcDbArc")
       (setq sp (vl-catch-all-apply 'vlax-curve-getstartpoint (list o))
             ep (vl-catch-all-apply 'vlax-curve-getendpoint (list o)))
       (if (and (not (vl-catch-all-error-p sp)) sp
                (not (vl-catch-all-error-p ep)) ep)
         (setq pts (list (list (car sp) (cadr sp))
                         (list (car ep) (cadr ep))))))

      ((or (= oname "AcDbPolyline") (= oname "AcDb2dPolyline"))
       (setq n (vl-catch-all-apply 'vlax-curve-getendparam (list o)))
       (if (and (not (vl-catch-all-error-p n)) (numberp n))
         (progn
           (setq n (fix (+ n 1e-4)) i 0)
           (while (<= i n)
             (setq pt (vl-catch-all-apply 'vlax-curve-getpointatparam (list o i)))
             (if (and (not (vl-catch-all-error-p pt)) pt)
               (setq pts (cons (list (car pt) (cadr pt)) pts)))
             ;; 若当前段是圆弧(bulge != 0)，补充采样圆弧中点保证弧顶包络准确
             (if (< i n)
               (progn
                 (setq b (vl-catch-all-apply 'vla-getbulge (list o i)))
                 (if (and (not (vl-catch-all-error-p b)) (numberp b) (> (abs b) 1e-4))
                   (progn
                     (setq pt (vl-catch-all-apply 'vlax-curve-getpointatparam (list o (+ (float i) 0.5))))
                     (if (and (not (vl-catch-all-error-p pt)) pt)
                       (setq pts (cons (list (car pt) (cadr pt)) pts)))))))
             (setq i (1+ i)))
           (setq pts (reverse pts)))))

      (T
       (setq sp (vl-catch-all-apply 'vlax-curve-getstartpoint (list o))
             ep (vl-catch-all-apply 'vlax-curve-getendpoint (list o)))
       (if (and (not (vl-catch-all-error-p sp)) sp
                (not (vl-catch-all-error-p ep)) ep)
         (setq pts (list (list (car sp) (cadr sp))
                         (list (car ep) (cadr ep))))))))
  pts)

;; 提取曲线中所有有效直线段的方向角(归一化到 [0, pi/2))
(defun dt:sz-curve-angles (o / oname angs p1 p2 dx dy a n i b)
  (setq angs nil
        oname (vl-catch-all-apply 'vla-get-objectname (list o)))
  (if (and (not (vl-catch-all-error-p oname)) (= (type oname) 'STR))
    (cond
      ((= oname "AcDbLine")
       (setq p1 (vl-catch-all-apply 'vlax-curve-getstartpoint (list o))
             p2 (vl-catch-all-apply 'vlax-curve-getendpoint (list o)))
       (if (and (not (vl-catch-all-error-p p1)) p1
                (not (vl-catch-all-error-p p2)) p2)
         (progn
           (setq dx (- (car p2) (car p1))
                 dy (- (cadr p2) (cadr p1)))
           (if (> (+ (* dx dx) (* dy dy)) 1.0)
             (progn
               (setq a (atan dy dx))
               (while (< a 0.0) (setq a (+ a pi)))
               (while (>= a (/ pi 2.0)) (setq a (- a (/ pi 2.0))))
               (setq angs (list a)))))))
      ((or (= oname "AcDbPolyline") (= oname "AcDb2dPolyline"))
       (setq n (vl-catch-all-apply 'vlax-curve-getendparam (list o)))
       (if (and (not (vl-catch-all-error-p n)) (numberp n))
         (progn
           (setq n (fix n) i 0)
           (while (< i n)
             (setq b (vl-catch-all-apply 'vla-getbulge (list o i)))
             (if (or (vl-catch-all-error-p b) (< (abs b) 1e-4))
               (progn
                 (setq p1 (vl-catch-all-apply 'vlax-curve-getpointatparam (list o i))
                       p2 (vl-catch-all-apply 'vlax-curve-getpointatparam (list o (1+ i))))
                 (if (and (not (vl-catch-all-error-p p1)) p1
                          (not (vl-catch-all-error-p p2)) p2)
                   (progn
                     (setq dx (- (car p2) (car p1))
                           dy (- (cadr p2) (cadr p1)))
                     (if (> (+ (* dx dx) (* dy dy)) 1.0)
                       (progn
                         (setq a (atan dy dx))
                         (while (< a 0.0) (setq a (+ a pi)))
                         (while (>= a (/ pi 2.0)) (setq a (- a (/ pi 2.0))))
                         (setq angs (cons a angs))))))))
             (setq i (1+ i))))))))
  angs)

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
(defun dt:sz-check-closed (cands / o oname sa res regs is-closed pts sp ep p clus found r c)
  (setq is-closed nil
        *dt-sz-multi-regions* nil)
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
             (if (> (length regs) 1)
               (setq *dt-sz-multi-regions* (length regs)))
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
                               dx dy area best-area best-box
                               aabb-area aabb-box rx0 ry0 rx1 ry1 len wid
                               p1 p2 p3 p4 o)
  (setq all-pts nil
        angs (list 0.0))
  (foreach o cands
    (setq all-pts (append (dt:sz-curve-sample-pts o) all-pts))
    (setq angs (append (dt:sz-curve-angles o) angs)))
  (setq angs (dt:sz-uniq-angles angs))

  (setq best-area nil
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
                best-box  (list dx dy minx miny maxx maxy a))))))

  ;; 若 AABB 面积与最佳 OBB 面积相差在 1% 以内，优先采用正交(0.0)
  (if (and aabb-box best-box
           (<= aabb-area (* best-area 1.01)))
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

;; 检测图形集合(优先分流板 FLB 轮廓)的倾斜角 (归一化在 [0, pi/2), 0.0 表示正交平行/垂直)
(defun dt:sz-detect-tilt-angle (cands / flb-cands box a lay)
  (setq flb-cands (vl-remove-if-not
                    '(lambda (o / lay)
                       (setq lay (vl-catch-all-apply 'vla-get-layer (list o)))
                       (and (not (vl-catch-all-error-p lay))
                            (= (type lay) 'STR)
                            (equal (strcase lay) "FLB")))
                    cands))
  (if (null flb-cands) (setq flb-cands cands))
  (setq box (vl-catch-all-apply 'dt:sz-calc-box (list flb-cands)))
  (if (and (not (vl-catch-all-error-p box)) box (listp box) (>= (length box) 7))
    (setq a (nth 6 box))
    (setq a 0.0))
  (if (or (null a) (not (numberp a)) (< (abs a) 1e-3))
    0.0
    a))

;; 统一将一组图元绕其包络盒中心整体旋转摆正 (rot-ang > 0 时顺时针旋转 rot-ang, 即 vla-rotate -rot-ang)
(defun dt:sz-straighten-objs (objs rot-ang / bb cen o)
  (if (and objs (> (length objs) 0) rot-ang (> (abs rot-ang) 1e-3))
    (progn
      (setq bb (dt:rect-bbox objs))
      (if bb
        (progn
          (setq cen (list (* 0.5 (+ (car bb) (caddr bb)))
                          (* 0.5 (+ (cadr bb) (cadddr bb)))
                          0.0))
          (foreach o objs
            (vl-catch-all-apply 'vla-rotate (list o (vlax-3d-point cen) (- rot-ang))))))))
  objs)

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
  ;; 1) 保证 FLB_BOX 图层存在(赭黄 42, v2.11 重排避免与螺丝孔青 4 相近)
  (dt:ensure-layer layers "FLB_BOX" 42 "赭黄")

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
;; 二.5、加热条(JRT)长度测量核心 (v2.16)
;;   口径: 一根加热条 = 若干层嵌套轮廓线(生成时是一条轮廓向内偏移 N 次画
;;         出来的), 各层长度天生几乎相等 —— 每层各量一遍, 取**中间值**作
;;         为这根加热条的长度。
;;   封闭线排除(双通道, 用户定案: 只剔封闭线本身, 圆弧一律不动):
;;     (1) JRTFBX 副本精确匹配(优先): v9.36 起通用二破口封闭线本体在 JRT、
;;         同几何定位副本在 JRTFBX —— JRT 直线与副本直线两端点均重合(<0.5)
;;         即剔除;
;;     (2) 几何复核(生成规则的反推): 生成时封闭线 = 把最外层与最内层的
;;         线头连起来的短直线(两头各一根)。反推 = 条内"两头都接在别的
;;         线上"的短直线先当候选, 试着剔除 —— 剔掉后其余线恰能分成
;;         "几条长度几乎一样"的线链(嵌套轮廓该有的样子)才确认; 剔掉后
;;         线链长短反而更乱的(普通轮廓短段被误去的样子)一律不动。
;;   分条(归堆): 全部曲线按最小间距归堆(可配: wx_runner.ini [测量加热条]
;;         strip_gap, 默认 15, 误填 <1 按默认处理) —— 同一根条的三层线彼此
;;         只差一步长(默认 4), 必归一堆; 不同加热条之间隔得远, 各归各堆。
;;   完整性(异常→弹窗取消, 不降级手动选择): 检测不到 JRT 曲线 / 仅 1 条
;;         开口线 / 端点间距 0.01~2mm 的断口。
;; ============================================================================

;; 曲线长度(端参数处距离; 失败返回 0)
(defun dt:sz-jrt-curve-len (e / r p)
  (setq r (vl-catch-all-apply
            '(lambda ( )
               (setq p (vlax-curve-getendparam e))
               (vlax-curve-getdistatparam e p))
            nil))
  (if (or (vl-catch-all-error-p r) (null r) (not (numberp r)))
    0.0
    r))

;; 曲线端点表 (起点 终点); 整圆/闭合多段线(起终点重合)返回 nil(视为无端点)
(defun dt:sz-jrt-ends (e / s r)
  (setq s (vl-catch-all-apply 'vlax-curve-getstartpoint (list e))
        r (vl-catch-all-apply 'vlax-curve-getendpoint (list e)))
  (if (and (not (vl-catch-all-error-p s)) (not (vl-catch-all-error-p r)) s r
           (> (distance s r) 0.01))
    (list s r)
    nil))

;; 两曲线是否相接(模型用, 端点已缓存于 rec 行): 端点重合(<tol)即相接;
;; 一方"无端点"(整圆/闭合多段线)时, 对方端点落在其线身上(<tol)也算相接
;; —— 通用一圆帽整圆与侧线的切点连接靠这条; 嵌套层间距=步长(默认4)
;; 远大于 tol, 不会误连。rec 行 = (ename 端点表 长度 是否直线)
(defun dt:sz-jrt-adj-p (ri rj tol / touch a b q)
  (setq touch nil)
  (foreach a (nth 1 ri)
    (foreach b (nth 1 rj)
      (if (< (distance a b) tol) (setq touch T))))
  (if (null touch)
    (cond
      ((null (nth 1 rj))
       (foreach a (nth 1 ri)
         (if (null touch)
           (progn
             (setq q (vl-catch-all-apply 'vlax-curve-getclosestpointto
                                         (list (car rj) a)))
             (if (and (not (vl-catch-all-error-p q)) q
                      (< (distance a q) tol))
               (setq touch T))))))
      ((null (nth 1 ri))
       (foreach b (nth 1 rj)
         (if (null touch)
           (progn
             (setq q (vl-catch-all-apply 'vlax-curve-getclosestpointto
                                         (list (car ri) b)))
             (if (and (not (vl-catch-all-error-p q)) q
                      (< (distance b q) tol))
               (setq touch T))))))))
  touch)

;; 下标连通分量: 按邻接表聚合(skip 中的下标不参与); 返回下标列表的列表
(defun dt:sz-jrt-comps-i (n adj skip / labels changed i j li lj lab out seen g)
  (setq labels nil
        i 0)
  (while (< i n)
    (setq labels (cons (if (member i skip) -1 i) labels)
          i (1+ i)))
  (setq labels (reverse labels)
        changed T)
  (while changed
    (setq changed nil
          i 0)
    (while (< i n)
      (setq li (nth i labels))
      (if (/= li -1)
        (foreach j (nth i adj)
          (setq lj (nth j labels))
          (if (and (/= lj -1) (/= lj li))
            (progn
              (setq lab (min li lj))
              (setq labels (mapcar
                             '(lambda (L)
                                (if (or (= L li) (= L lj)) lab L))
                             labels))
              (setq li lab)
              (setq changed T)))))
      (setq i (1+ i))))
  (setq out nil
        seen nil
        i 0)
  (while (< i n)
    (setq lab (nth i labels))
    (if (and (/= lab -1) (not (member lab seen)))
      (progn
        (setq seen (cons lab seen)
              g nil
              j 0)
        (while (< j n)
          (if (= (nth j labels) lab)
            (setq g (cons j g)))
          (setq j (1+ j)))
        (setq out (cons (reverse g) out))))
    (setq i (1+ i)))
  (reverse out))

;; 给定剔除表 skip, 算各线链的长度表
(defun dt:sz-jrt-lens-at (recs adj n skip / comps lens l comp i)
  (setq comps (dt:sz-jrt-comps-i n adj skip)
        lens nil)
  (foreach comp comps
    (setq l 0.0)
    (foreach i comp
      (setq l (+ l (nth 2 (nth i recs)))))
    (setq lens (cons l lens)))
  (reverse lens))

;; 线链"整齐度": 各链长度相对中间值的极差。单链=1(还没分出嵌套层),
;; 空=2(异常); 嵌套轮廓各层长度天生几乎相等 → 越接近 0 越像"几层嵌套线"。
(defun dt:sz-jrt-spread (lens / mn mx med)
  (cond
    ((null lens) 2.0)
    ((= (length lens) 1) 1.0)
    (T
     (setq med (dt:sz-jrt-median lens)
           mn (apply 'min lens)
           mx (apply 'max lens))
     (if (and med (> med 1e-6))
       (/ (- mx mn) med)
       2.0))))

;; 候选资格: 直线两头各自都与其他曲线的端点重合 —— 生成时封闭线就是
;; 接在最外层/最内层的"线头"(自由端)上, 中间层的线头由它跨过不接触
(defun dt:sz-jrt-joined-p (rec recs / ends p ok r q e2)
  (setq ends (nth 1 rec)
        ok (and ends (= (length ends) 2)))
  (foreach p ends
    (setq r nil)
    (foreach q recs
      (if (and (null r) (not (equal (car q) (car rec))))
        (foreach e2 (nth 1 q)
          (if (and (null r) (< (distance p e2) 0.5))
            (setq r T)))))
    (if (null r)
      (setq ok nil)))
  ok)

;; 两曲线最小间距(双向各 5 个等参采样点向对方曲线投影求最近)
(defun dt:sz-jrt-min-dist (e1 e2 / r pair np i par p q)
  (setq r 1e99)
  (foreach pair (list (list e1 e2) (list e2 e1))
    (setq np (vl-catch-all-apply 'vlax-curve-getendparam (list (car pair))))
    (if (and (not (vl-catch-all-error-p np)) (numberp np))
      (progn
        (setq i 0)
        (while (<= i 4)
          (setq par (* np i 0.25)
                p (vl-catch-all-apply 'vlax-curve-getpointatparam
                                      (list (car pair) par)))
          (if (and (not (vl-catch-all-error-p p)) p)
            (progn
              (setq q (vl-catch-all-apply 'vlax-curve-getclosestpointto
                                          (list (cadr pair) p)))
              (if (and (not (vl-catch-all-error-p q)) q)
                (if (< (distance p q) r) (setq r (distance p q))))))
          (setq i (1+ i))))))
  r)

;; 单实体包围盒 (minx miny maxx maxy); 失败返回 nil
(defun dt:sz-jrt-obj-bbox (e / o mn mx r p q)
  (setq o (vlax-ename->vla-object e)
        mn nil
        mx nil)
  (setq r (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx)))
  (if (and (not (vl-catch-all-error-p r)) mn mx)
    (progn
      (setq p (dt:rect-bb-pts mn)
            q (dt:rect-bb-pts mx))
      (list (car p) (cadr p) (car q) (cadr q)))
    nil))

;; 两包围盒间距(不相交为正的欧氏距离, 相交/含套为 0)
(defun dt:sz-jrt-bb-gap (b1 b2 / dx dy)
  (setq dx (max (- (car b1) (nth 2 b2)) (- (car b2) (nth 2 b1)) 0.0)
        dy (max (- (cadr b1) (nth 3 b2)) (- (cadr b2) (nth 3 b1)) 0.0))
  (sqrt (+ (* dx dx) (* dy dy))))

;; 空间单链聚类: 曲线间最小间距<=gap 归为同一条加热条(嵌套层间距=步长,
;; 远小于 gap; 不同加热条物理间距远大于 gap)。返回 ename 列表的列表。
(defun dt:sz-jrt-strips (objs gap / n labels bbs changed i j li lj lab out seen g
                                b1 b2)
  (setq n (length objs)
        labels nil
        bbs nil
        i 0)
  (while (< i n)
    (setq labels (cons i labels)
          bbs (cons (dt:sz-jrt-obj-bbox (nth i objs)) bbs)
          i (1+ i)))
  (setq labels (reverse labels)
        bbs (reverse bbs)
        changed T)
  (while changed
    (setq changed nil
          i 0)
    (while (< i n)
      (setq j (1+ i))
      (while (< j n)
        (setq li (nth i labels)
              lj (nth j labels)
              b1 (nth i bbs)
              b2 (nth j bbs))
        (if (and (/= li lj) b1 b2
                 (<= (dt:sz-jrt-bb-gap b1 b2) gap)
                 (<= (dt:sz-jrt-min-dist (nth i objs) (nth j objs)) gap))
          (progn
            (setq lab (min li lj))
            (setq labels (mapcar
                           '(lambda (L)
                              (if (or (= L li) (= L lj)) lab L))
                           labels))
            (setq changed T)))
        (setq j (1+ j)))
      (setq i (1+ i))))
  (setq out nil
        seen nil
        i 0)
  (while (< i n)
    (setq lab (nth i labels))
    (if (not (member lab seen))
      (progn
        (setq seen (cons lab seen)
              g nil
              j 0)
        (while (< j n)
          (if (= (nth j labels) lab)
            (setq g (cons (nth j objs) g)))
          (setq j (1+ j)))
        (setq out (cons (reverse g) out))))
    (setq i (1+ i)))
  (reverse out))

;; JRT 直线与 JRTFBX 副本直线两端点(无序)均重合(<0.5) → 视为破口封闭线本体。
;; 返回 JRT 侧应剔除的 ename 列表。
(defun dt:sz-jrt-fbx-match (objs fbx / out e hit a b f c d)
  (setq out nil)
  (foreach e objs
    (if (= (cdr (assoc 0 (entget e))) "LINE")
      (progn
        (setq a (vlax-curve-getstartpoint e)
              b (vlax-curve-getendpoint e)
              hit nil)
        (foreach f fbx
          (if (and (null hit) (= (cdr (assoc 0 (entget f))) "LINE"))
            (progn
              (setq c (vlax-curve-getstartpoint f)
                    d (vlax-curve-getendpoint f))
              (if (or (and (< (distance a c) 0.5) (< (distance b d) 0.5))
                      (and (< (distance a d) 0.5) (< (distance b c) 0.5)))
                (setq hit T)))))
        (if hit (setq out (cons e out)))))
  out))

;; 找破口封闭线(生成规则的反推, 用户定案: 只剔封闭线本身, 圆弧一律不动):
;;   生成时封闭线 = 把最外层与最内层的线头连起来的短直线(一头一根);
;;   反推 = 条内"两头都接在别的线上"的短直线先当候选, 试着剔除 ——
;;   剔掉后其余线恰能分成"几条长度几乎一样"的线链(生成就是一条轮廓向内
;;   偏移 N 次, 各层长度天生几乎相等)才确认; 剔掉后线链长短反而更乱的
;;   (普通轮廓短段被误去的样子)一律不动。封闭线两头成对, 所以单根不见
;;   分晓时再试"成对剔除"。
;; recs/adj/n 见 dt:sz-jrt-strip-rec; 返回应剔除的下标表(可能为 nil)
(defun dt:sz-jrt-close-pick (recs adj n / total lim cands i r skip cur s
                                  trial improved p1 p2 j kmax lens)
  (setq total 0.0)
  (foreach r recs
    (setq total (+ total (nth 2 r))))
  ;; 候选: 直线 + 两头都接在别的线上 + 短(封闭线只跨"层距×层数", 占全条
  ;; 零头; 上限 max(6%全条长, 40) 保证层数/步长参数不同也罩得住)
  (setq lim (max (* 0.06 total) 40.0)
        cands nil
        i 0)
  (while (< i n)
    (setq r (nth i recs))
    (if (and (nth 3 r)
             (> (nth 2 r) 0.01)
             (< (nth 2 r) lim)
             (dt:sz-jrt-joined-p r recs))
      (setq cands (cons i cands)))
    (setq i (1+ i)))
  (setq cands (reverse cands))
  (if (null cands)
    nil
    (progn
      (setq skip nil
            cur (dt:sz-jrt-spread (dt:sz-jrt-lens-at recs adj n nil))
            improved T)
      (while improved
        (setq improved nil)
        ;; 单根试剔(JRTFBX 已剔一根时, 剩下那根单剔就见分晓)
        (setq i 0)
        (while (and (null improved) (< i (length cands)))
          (setq r (nth i cands))
          (if (not (member r skip))
            (progn
              (setq trial (cons r skip)
                    lens (dt:sz-jrt-lens-at recs adj n trial)
                    s (dt:sz-jrt-spread lens))
              (if (and lens
                       (< s (- cur 0.01))
                       (>= (/ (apply 'min lens) (apply 'max lens)) 0.8))
                (setq skip trial
                      cur s
                      improved T))))
          (setq i (1+ i)))
        ;; 成对试剔(封闭线两头各一根, 必须一起去掉才见分晓; 只试最短的
        ;; 12 根候选 —— 封闭线必是其中之一, 免得组合爆炸)
        (if (null improved)
          (progn
            (setq kmax (min 12 (length cands))
                  i 0)
            (while (and (null improved) (< i kmax))
              (setq j (1+ i))
              (while (and (null improved) (< j kmax))
                (setq p1 (nth i cands)
                      p2 (nth j cands))
                (if (and (not (member p1 skip)) (not (member p2 skip)))
                  (progn
                    (setq trial (cons p1 (cons p2 skip))
                          lens (dt:sz-jrt-lens-at recs adj n trial)
                          s (dt:sz-jrt-spread lens))
                    (if (and lens
                             (< s (- cur 0.01))
                             (>= (/ (apply 'min lens) (apply 'max lens)) 0.45))
                      (setq skip trial
                            cur s
                            improved T))))
                (setq j (1+ j)))
              (setq i (1+ i))))))
      skip)))

;; 断口检测: 不同曲线端点对间距落在 (0.01, 2.0] 的对数(健康产物应为 0;
;; 上界 2.0 取嵌套层端头最小步距之下, 防相邻层端头误报)
(defun dt:sz-jrt-nearmiss (objs / r i j e f a b d)
  (setq r 0
        i 0)
  (while (< i (length objs))
    (setq j (1+ i))
    (while (< j (length objs))
      (setq e (nth i objs)
            f (nth j objs))
      (foreach a (dt:sz-jrt-ends e)
        (foreach b (dt:sz-jrt-ends f)
          (setq d (distance a b))
          (if (and (> d 0.01) (<= d 2.0)) (setq r (1+ r)))))
      (setq j (1+ j)))
    (setq i (1+ i)))
  r)

;; 链是否闭合: 链内每个端点都能在链内其他曲线上找到相接端点(<0.5);
;; 无端点实体(整圆/闭合多段线)视为闭合
(defun dt:sz-jrt-chain-closed-p (chain / r o e cnt f fe)
  (setq r T)
  (foreach o chain
    (foreach e (dt:sz-jrt-ends o)
      (setq cnt 0)
      (foreach f chain
        (if (not (eq f o))
          (foreach fe (dt:sz-jrt-ends f)
            (if (< (distance e fe) 0.5) (setq cnt (1+ cnt))))))
      (if (= cnt 0) (setq r nil))))
  r)

;; 数值列表中位数(偶数个取中间两数均值)
(defun dt:sz-jrt-median (nums / s n)
  (setq s (vl-sort nums '<)
        n (length s))
  (cond
    ((= n 0) nil)
    ((= 0 (rem n 2)) (/ (+ (nth (- (/ n 2) 1) s) (nth (/ n 2) s)) 2.0))
    (T (nth (/ n 2) s))))

;; 单条加热条 -> 测量记录 (曲线数 线数 封闭线数 总长 长度 整圆数
;;                        各线长表 链表 计入实体表 原条实体表)
;; 流程: 先扣掉 JRTFBX 精确命中的封闭线 → 剩余曲线建模型(缓存端点/邻接)
;;       → 几何复核剔除(生成规则反推, dt:sz-jrt-close-pick) → 剩下的线按
;;       "头碰头"分成各层嵌套线 → 各层长度取中间值
(defun dt:sz-jrt-strip-rec (strip excl-global / exc recs adj n row i j r skip
                                  kept chains ch lens l total med ncirc e comp)
  (setq exc nil)
  (foreach e excl-global
    (if (member e strip) (setq exc (cons e exc))))
  ;; 模型: 剩余曲线逐条 (ename 端点表 长度 是否直线)
  (setq recs nil)
  (foreach e strip
    (if (not (member e exc))
      (setq recs (cons (list e
                             (dt:sz-jrt-ends e)
                             (dt:sz-jrt-curve-len e)
                             (= (cdr (assoc 0 (entget e))) "LINE"))
                       recs))))
  (setq recs (reverse recs)
        n (length recs))
  ;; 邻接表: 谁跟谁头碰头
  (setq adj nil
        i 0)
  (while (< i n)
    (setq row nil
          j 0)
    (while (< j n)
      (if (and (/= j i)
               (dt:sz-jrt-adj-p (nth i recs) (nth j recs) 0.5))
        (setq row (cons j row)))
      (setq j (1+ j)))
    (setq adj (cons (reverse row) adj)
          i (1+ i)))
  (setq adj (reverse adj))
  ;; 几何复核剔除(生成规则反推)
  (setq skip (dt:sz-jrt-close-pick recs adj n))
  (foreach r skip
    (setq exc (cons (nth 0 (nth r recs)) exc)))
  ;; 计入测量的曲线 + 整圆计数
  (setq kept nil
        ncirc 0
        i 0)
  (foreach r recs
    (if (not (member i skip))
      (progn
        (setq kept (cons (car r) kept))
        (if (= (cdr (assoc 0 (entget (car r)))) "CIRCLE")
          (setq ncirc (1+ ncirc)))))
    (setq i (1+ i)))
  (setq kept (reverse kept))
  ;; 线链(下标分量 -> ename 分组)
  (setq chains nil)
  (foreach comp (dt:sz-jrt-comps-i n adj skip)
    (setq ch nil)
    (foreach i comp
      (setq ch (cons (nth 0 (nth i recs)) ch)))
    (setq chains (cons (reverse ch) chains)))
  (setq chains (reverse chains)
        lens (dt:sz-jrt-lens-at recs adj n skip)
        total 0.0)
  (foreach l lens
    (setq total (+ total l)))
  (setq med (dt:sz-jrt-median lens))
  (list (length strip) (length chains) (length exc) total med ncirc
        lens chains kept strip))

;; 单条加热条完整性与结果输出; 通过返回 T, 取消/异常返回 nil
(defun dt:sz-jrt-report (rec / nobjs nch nexcl total med ncirc lens chains kept
                              nmiss minl clip l)
  (setq nobjs (nth 0 rec)
        nch (nth 1 rec)
        nexcl (nth 2 rec)
        total (nth 3 rec)
        med (nth 4 rec)
        ncirc (nth 5 rec)
        lens (nth 6 rec)
        chains (nth 7 rec)
        kept (nth 8 rec))
  ;; 完整性(1): 仅 1 条线 —— 闭合单线按单层计, 开口单线视为不完整取消
  (if (= nch 1)
    (if (dt:sz-jrt-chain-closed-p (car chains))
      (princ "\n【加热条长度】注意: 仅 1 条闭合线(单层), 按该线长度计。")
      (progn
        (alert "【提示】加热条不完整!\n\n仅识别到 1 条开口线, 无法计算加热条长度。\n(正常加热条为多条嵌套线)\n命令已取消。")
        (princ "\n【加热条长度】仅识别到 1 条开口线, 命令已取消。")
        (setq med nil))))
  (if (<= nch 0)
    (progn
      (alert "【提示】加热条不完整!\n\n未能识别出有效嵌套线。\n命令已取消。")
      (princ "\n【加热条长度】未能识别出有效嵌套线, 命令已取消。")
      (setq med nil)))
  ;; 完整性(2): 端点断口
  (if med
    (progn
      (setq nmiss (dt:sz-jrt-nearmiss kept))
      (if (> nmiss 0)
        (progn
          (alert (strcat "【提示】加热条疑似破损!\n\n检测到 " (itoa nmiss)
                         " 处断口(线端点间距 0.01~2mm)。\n请检查图形完整性后重试。\n命令已取消。"))
          (princ (strcat "\n【加热条长度】检测到 " (itoa nmiss)
                         " 处疑似断口, 命令已取消。"))
          (setq med nil)))))
  (if med
    (progn
      ;; 提示(不取消): 明显短链 / 整圆 / 各层长度差异偏大
      (setq minl (apply 'min lens))
      (if (and (> nch 1) (< minl (* 0.5 med)))
        (princ (strcat "\n【加热条长度】注意: 存在明显短链(最短 "
                       (rtos minl 2 2) " mm), 已按中间值估计。")))
      (if (> ncirc 0)
        (princ (strcat "\n【加热条长度】注意: 含整圆 " (itoa ncirc)
                       " 个, 已按轮廓线计入长度(若为通用一圆帽端帽, 请人工核对)。")))
      (if (and (> nch 1) (> (- (apply 'max lens) minl) (* 0.2 med)))
        (princ "\n【加热条长度】注意: 各层长度差异偏大, 结果请人工核对。"))
      ;; 结果输出 + 剪贴板
      (setq clip (dt:sz-fmt-num med))
      (dt:sz-copy-clip clip)
      (princ "\n------------------------------------------------------------")
      (princ (strcat "\n【加热条长度】测量完成: 长度 = " (rtos med 2 2) " mm"
                     " (" (itoa nch) " 层嵌套线各量一遍取中间值; 总长 "
                     (rtos total 2 2) " mm; 剔除封闭线 " (itoa nexcl) " 根)"))
      (if (and lens (<= (length lens) 8))
        (progn
          (princ "\n各层线长:")
          (foreach l lens
            (princ (strcat " " (rtos l 2 1))))))
      (princ (strcat "\n" clip " 已复制到剪贴板, 可直接 Ctrl+V 粘贴。"))
      (princ "\n------------------------------------------------------------")
      (alert (strcat "【加热条长度测量结果】\n\n"
                     "长度: " (rtos med 2 2) " mm\n"
                     "(" (itoa nch) " 层嵌套线各量一遍, 取中间值)\n"
                     "剔除封闭线: " (itoa nexcl) " 根\n\n"
                     clip " 已复制到剪贴板。"))
      T)))

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
;; v2.18: 定位顺序改为确定性优先 —— 先取 dt_start 注入的脚本目录(*dt-script-dir*)
;;   下的同名 ini, 找不到才 findfile 全局搜索。多副本环境下 findfile 会命中
;;   支持路径里其它目录的同名旧副本(flb v2.0 dcl 定位错乱的同一坑), 脚本
;;   目录旁的配置才是"这一份"脚本的配置。
(defun dt:sz-cfg-get (section key def-val / path res sec f ln p k vs)
  (if (and (boundp '*dt-script-dir*) *dt-script-dir*
           (setq path (findfile (strcat *dt-script-dir* "\\wx_runner.ini"))))
    path
    (progn
      (setq path (findfile "wx_runner.ini"))
      (if (null path) (setq path (findfile "size_runner.ini")))
      (if (null path)
        (setq path (strcat (if (and (boundp '*dt-script-dir*) *dt-script-dir*)
                             *dt-script-dir*
                             "C:\\CAD")
                           "\\wx_runner.ini")))
      path))
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

;; v2.18: ini 值 -> 数值(distof 校验), 空/垃圾串回退默认 def —— atof 对
;;   垃圾串静默返回 0.0, 会把间距类参数悄悄改成 0 画出退化排版(坑 #54 口径,
;;   与 flb dt:get-num 同规)。0 是合法值, 靠"distof 非 nil"区分。
(defun dt:sz-num-or (s def / v)
  (setq v (if (and (= (type s) 'STR) (/= s "")) (distof s) nil))
  (if v v def))

;; 扫描磁盘，寻找当天存在的最高序号图纸文件 (如 09.04.dwg, 09.04_1.dwg, 09.04_2.dwg...)
;; 若 09.04_2.dwg 被删除，则自动返回 09.04_1.dwg；若都无，返回 nil
(defun dt:sz-get-latest-target (month-dir base-name / latest idx full)
  (setq latest nil)
  (if (findfile (strcat month-dir "\\" base-name ".dwg"))
    (setq latest (strcat month-dir "\\" base-name ".dwg")))
  (setq idx 1)
  (while (findfile (setq full (strcat month-dir "\\" base-name "_" (itoa idx) ".dwg")))
    (setq latest full
          idx (1+ idx)))
  latest)

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
;; 若已存在 09.04_1.dwg，默认追加目标自动跟进为 09.04_1.dwg，输入 N 则递增为 09.04_2.dwg
(defun dt:sz-auto-target-path (branch-name / def-root root cd s yy mm dd
                                           year-dir month-dir base-name def-path
                                           cur-mem latest-exist next-fname choice target)
  ;; v2.9: 兜底根目录改 USERPROFILE 推导 —— 旧值硬编码本机用户名路径,
  ;; 换机即往错误位置建目录; 下方盘符降级分支本就用同一 USERPROFILE 惯用法
  (setq def-root (strcat (if (getenv "USERPROFILE")
                           (getenv "USERPROFILE")
                           "C:\\CAD")
                         "\\Documents\\CAD\\" branch-name))
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
  ;; 若记忆中的文件已在磁盘被删除，则重置记忆为 nil
  (if (and cur-mem (null (findfile cur-mem)))
    (setq cur-mem nil))

  ;; 扫描磁盘获取当天已存在的最新图纸文件 (如 09.04_1.dwg)
  (setq latest-exist (dt:sz-get-latest-target month-dir base-name))

  ;; 优先以磁盘上存在的最高序号文件作为当前追加目标基准 (若 _2 被删则自动回退到 _1)
  (if latest-exist
    (setq cur-mem latest-exist))

  (cond
    ;; 情况 1: 当天尚未生成任何图纸 (连 09.04.dwg 都不存在)，直接作为首选目标 (零提示直接新建)
    ((null latest-exist)
      (setq target def-path))

    ;; 情况 2: 图纸已存在，提供命令行选项: 回车默认追加已有最新图纸，输入 N 自动递增新建
    (T
      (setq next-fname (dt:sz-next-avail-name month-dir base-name))
      (initget "A N")
      (setq choice (getkword (strcat "\n【" branch-name "】目标图纸已存在: "
                                     (if cur-mem (vl-filename-base cur-mem) base-name) ".dwg"
                                     "\n[追加(A)/新建为" next-fname "(N)] <A>: ")))
      (if (and choice (= (strcase choice) "N"))
        (setq target (strcat month-dir "\\" next-fname))
        (setq target (if cur-mem cur-mem def-path)))))

  ;; 绑定并持久化到当前会话
  (if (equal branch-name "线切割")
    (setq *dt-xqg-target-dwg* target)
    (setq *dt-jd-target-dwg* target))
  target)

;; 智能将长文件名格式化为多行文字 (遇 -、_、+、空格 或超长时自动拆分并以 \P 换行连接)
(defun dt:sz-format-multiline (s / max-len len lines cur i ch l)
  (setq max-len 12) ; 每行建议字数
  ;; nil 判定在前(or 短路), strlen 不再对 nil 求值 —— 此前先 (strlen s) 后判
  ;; nil, s 为 nil 直接抛 bad argument type
  (if (or (null s) (<= (setq len (strlen s)) max-len))
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

;; 确保指定文档中存在指定图层(直接访问目标文档 layers 集合, 彻底脱钩当前活动的 tblsearch)
(defun dt:sz-ensure-doc-layer (doc name color / layers lay)  (setq layers (vla-get-layers doc))
  (setq lay (vl-catch-all-apply 'vla-item (list layers name)))
  (if (or (vl-catch-all-error-p lay) (null lay))
    (setq lay (vl-catch-all-apply 'vla-add (list layers name))))
  (if (and (not (vl-catch-all-error-p lay)) lay (numberp color))
    (vl-catch-all-apply 'vla-put-color (list lay color)))
  lay)

;; v2.7: 把一组实体合并到单一图层并保留原色 —— 实体色为 ByLayer(0) 的,
;; 先转存其原图层 ACI 色再换层(换层后 ByLayer 会跟随新层色而丢色);
;; 原色为显式色的直接保留。返回 objs。
(defun dt:sz-flatten-layer (doc objs new-layer / o c lyr-col)
  (foreach o objs
    (vl-catch-all-apply
      '(lambda ( )
         (setq c (vla-get-color o))
         (if (= c 0)
           (progn
             (setq lyr-col 7)
             (vl-catch-all-apply
               '(lambda ( )
                  (setq lyr-col (vla-get-color
                                  (vla-item (vla-get-layers doc) (vla-get-layer o))))))
             (vla-put-color o lyr-col))))
      nil))
  (foreach o objs (vl-catch-all-apply 'vla-put-layer (list o new-layer)))
  objs)

;; v2.8: 目标图纸中把 src-layers 图层上的所有模型空间实体移入 dst-layer,
;; 然后删除这些原图层(空层才能删, 删不掉 catch 跳过)。
(defun dt:sz-migrate-layers (doc dst-layer src-layers / ms n i o lay done ln)
  (setq ms (vla-get-modelspace doc)
        n  (vla-get-count ms)
        i  0
        done 0)
  (while (< i n)
    (setq o (vla-item ms i)
          i (1+ i))
    (setq lay (vl-catch-all-apply 'vla-get-layer (list o)))
    (if (and (not (vl-catch-all-error-p lay)) lay
             (member (strcase lay) (mapcar 'strcase src-layers)))
      (progn
        (vl-catch-all-apply 'vla-put-layer (list o dst-layer))
        (setq done (1+ done)))))
  (foreach ln src-layers
    (vl-catch-all-apply 'vla-delete
      (list (vl-catch-all-apply 'vla-item
              (list (vla-get-layers doc) ln)))))
  done)

;; 在当前已打开的文档集合中按路径查找文档
;; v2.4: 收集目标图纸指定图层上的 MText 实体(排版网格的单位标记:
;; 每幅输出的工件恰好带 1 个文件名标注文字)
(defun dt:sz-doc-texts (doc layer / ms i n o out)
  (setq ms (vla-get-modelspace doc)
        n  (vla-get-count ms)
        i  0
        out nil)
  (while (< i n)
    (setq o (vla-item ms i))
    (if (and (= (vla-get-objectname o) "AcDbMText")
             (= (strcase (vla-get-layer o)) (strcase layer)))
      (setq out (cons o out)))
    (setq i (1+ i)))
  (reverse out))

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

;; 探测目标图纸中已有图元的总体外包盒 (计算平铺落点用)
;; v2.13: 新增可选 excl-layers —— 排除这些图层后求"内容"外包盒(排版基准用:
;;        排除 外协文字/外协包络盒, 免得文字或盒把基准撑大); 省略=nil=全部图元。
(defun dt:sz-doc-ms-bbox (doc excl-layers / ms mn mx p minx miny maxx maxy o lay)
  (setq ms (vla-get-modelspace doc)
        minx nil miny nil maxx nil maxy nil)
  (vlax-for o ms
    (setq lay (vl-catch-all-apply 'vla-get-layer (list o)))
    (if (and (not (vl-catch-all-error-p lay)) lay
             (not (and excl-layers
                       (member (strcase lay)
                               (mapcar 'strcase excl-layers)))))
      (progn
        (setq mn nil mx nil)
        (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx))))
          (progn
            (setq p (dt:rect-bb-pts mn))
            (setq minx (if minx (min minx (car p)) (car p))
                  miny (if miny (min miny (cadr p)) (cadr p)))
            (setq p (dt:rect-bb-pts mx))
            (setq maxx (if maxx (max maxx (car p)) (car p))
                  maxy (if maxy (max maxy (cadr p)) (cadr p))))))))
  (if (and minx miny maxx maxy) (list minx miny maxx maxy) nil))

;; v2.13 起: 由内容几何反推"当前行"单元盒右缘 —— 本次会话首幅 / 换目标图后无
;; 会话游标时的定位兜底。基准 = 本行内容的 maxX + box_margin(只取内容实体,
;; 不读文字 bbox —— 见 v2.14 头注: 非活动文档里 MText 的 boundingbox 不可靠)。
;; ctop = 本行"内容顶"(由本行文字插入点 Y - text_gap 得到, 可靠):
;; bbox maxY <= ctop 即本行内容 —— 行上方各幅的内容底边必高于本行内容顶
;; (相隔 box_gap + 2×box_margin), 故该过滤恰为本行, 与图形高度无关。
;; 根治 v2.11 缺陷: 旧兜底拿"文字 maxx"当基准, 文字居中且宽钳 <=220, 比工件
;; 窄时基准偏小 → 相邻两幅间距忽大忽小(实测 10 幅里 1 幅不同)。
;; 注: 文字比工件宽时本估计会略小(仅影响无游标的那一幅), 属已知取舍。
(defun dt:sz-row-right (doc ctop margin / ms n i o lay bb right)
  (setq ms (vla-get-modelspace doc)
        n  (vla-get-count ms)
        i  0
        right nil)
  (while (< i n)
    (setq o (vla-item ms i)
          i (1+ i))
    (setq lay (vl-catch-all-apply 'vla-get-layer (list o)))
    (if (and (not (vl-catch-all-error-p lay)) lay
             (not (member (strcase lay) '("外协文字" "外协包络盒"))))
      (progn
        (setq bb (dt:rect-bbox (list o)))
        (if (and bb (<= (cadddr bb) (+ ctop 1.0)))
          (setq right (if right (max right (caddr bb)) (caddr bb)))))))
  (if right (+ right margin) nil))

;; 提取热流道脚本自动化生成的有效加工曲线 (严格限定在 FLB, LS, RZ, DK, JRT, DP, ZJJ 白名单)
(defun dt:sz-collect-auto-curves ( / ss ents cands e ed lay obj)
  (setq cands nil)
  ;; 限制仅在模型空间 (410 . "Model") 提取曲线，彻底排除布局视口和图框干扰
  (setq ss (ssget "X" '((410 . "Model") (0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
  (if ss
    (progn
      (setq ents (dt:ss->list ss))
      (foreach e ents
        (setq ed (entget e))
        (if (and ed
                 (setq lay (cdr (assoc 8 ed)))
                 (= (type lay) 'STR)
                 (member (strcase lay) '("FLB" "LS" "RZ" "DK" "JRT" "DP" "ZJJ")))
          (progn
            (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list e)))
            (if (and (not (vl-catch-all-error-p obj)) obj)
              (setq cands (cons obj cands))))))
      (setq cands (reverse cands))))
  cands)

;; 在当前活动图纸中执行原生镜像 (优先 vla-mirror, 保底原生 _.MIRROR 命令)
;; v2.3: 镜像轴由调用方以任意两点 p1/p2 给出 (精雕用竖直轴实现右侧镜像)
(defun dt:sz-mirror-in-curdoc (objs p1 p2 / m-objs new-o ss last-e e o)
  (setq m-objs nil)
  ;; 1) 优先通过 COM vla-mirror 镜像 (当前文档具备完整 UCS 和视口, 速度极快)
  (foreach o objs
    (setq new-o (vl-catch-all-apply 'vla-mirror (list o p1 p2)))
    (if (and (not (vl-catch-all-error-p new-o)) new-o)
      (setq m-objs (cons new-o m-objs))))
  (if (= (length m-objs) (length objs))
    (reverse m-objs)
    ;; 2) 若个别复杂图元(如特殊样条曲线) vla-mirror 受限，使用 AutoCAD 原生 _.MIRROR 命令 100% 批量保底
    (progn
      (foreach o m-objs (vl-catch-all-apply 'vla-delete (list o)))
      (setq ss (ssadd))
      (foreach o objs
        (setq e (vlax-vla-object->ename o))
        (if e (setq ss (ssadd e ss))))
      ;; command-s/vl-cmdf 把命令发给"当前活动文档": 目标图纸被 vla-open 激活
      ;; 后活动文档已非本函数图元所在文档, 跨文档执行会改错图 —— 先激活再保底
      (vl-catch-all-apply 'vla-activate
        (list (vla-get-document (car objs))))
      (setq last-e (entlast))
      (if (boundp 'command-s)
        (command-s "_.MIRROR" ss "" p1 p2 "_N")
        (vl-cmdf "_.MIRROR" ss "" p1 p2 "_N"))
      (setq m-objs nil)
      (while (setq last-e (entnext last-e))
        (setq m-objs (cons (vlax-ename->vla-object last-e) m-objs)))
      (reverse m-objs))))

;; v2.13: 按统一规格在指定文档生成幅标题 MText, 返回对象(nil=失败)。
;; 调用方须先确保该文档已有文字样式 DT_WX_STYLE 与图层 外协文字。
;; 规格: 字高 15 / 行距系数 1.2 / 底边居中(向上生长) / 外协文字层。
(defun dt:sz-make-title (doc cx cy width text / ms o)
  (setq ms (vla-get-modelspace doc)
        o  (vl-catch-all-apply
             'vla-addmtext
             (list ms (vlax-3d-point (list cx cy 0.0)) width text)))
  (if (or (vl-catch-all-error-p o) (null o))
    nil
    (progn
      (vl-catch-all-apply 'vla-put-height (list o 15.0))
      ;; 8 = acAttachmentPointBottomCenter (底部居中, 向上生长且水平严格居中)
      (vl-catch-all-apply 'vla-put-attachmentpoint (list o 8))
      (vl-catch-all-apply 'vla-put-insertionpoint (list o (vlax-3d-point (list cx cy 0.0))))
      (vl-catch-all-apply 'vla-put-linespacingfactor (list o 1.2))
      (vl-catch-all-apply 'vla-put-layer (list o "外协文字"))
      (vl-catch-all-apply 'vla-put-stylename (list o "DT_WX_STYLE"))
      o)))

;; 将所选曲线排版并输出到目标 DWG (当前文档原生处理 + 原子级传输 + 防覆盖平铺 + 文字标注)
;; is-auto: T=自动提取图层, nil=手动框选(手动模式 100% 全保留)
(defun dt:sz-export-to-dwg (cands title target-layer is-auto /
                            *error* undo-marked cur-doc acad docs target-path tgt-doc
                            ms-tgt existing-bb rot-ang
                            front-objs back-objs export-objs o c
                            src-bb s-minx s-miny s-maxx s-maxy part-w part-h
                            off-x off-y sa r
                            tmp-dwg w-res blk exp-res
                            keep-front keep-back lay-name
                            src-fname src-multiline title-cx title-cy title-w txt-obj save-res
                            box-gap per-row text-gap box-margin
                            grid-n grid-col txt-list txt-infos txt-min-y ip-t ti migrated
                            unit-w ax unit-bb ub-w ub-h row-ctop
                            first-p x0 by0 bx1 by1 bx2 by2 dx dy box-obj)
  ;; v2.18: 局部 *error* 兜底 —— 中途抛错时关闭悬挂的 UNDO 组并清理
  ;;   当前图里的临时克隆(沿用 c:FLBSZ 的 undo-started 收口惯用法), 避免
  ;;   出错后 UNDO 组悬挂、front/back/txt 临时实体残留图面。
  (defun *error* (msg)
    (if undo-marked
      (vl-catch-all-apply 'vla-endundomark (list cur-doc)))
    (foreach o (append (if export-objs export-objs nil)
                       (if front-objs front-objs nil)
                       (if back-objs back-objs nil)
                       (if txt-obj (list txt-obj) nil)
                       (if box-obj (list box-obj) nil))
      (vl-catch-all-apply 'vla-delete (list o)))
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【" title "】导出错误: " msg)))
    (princ))
  (setq cur-doc (vla-get-activedocument (vlax-get-acad-object))
        acad    (vlax-get-acad-object)
        docs    (vla-get-documents acad)
        ;; v2.13: [排版] 四项全部可配(wx_runner.ini, 缺项回退下列默认值) ——
        ;;   box_gap    相邻输出单元之间的净间距(精雕=包络盒↔包络盒; 线切割=
        ;;              "图形+文字"合成盒↔合成盒)。上下左右四向同一值。
        ;;   per_row    每行幅数(排版满该数后向下换行); <=0 回退 4
        ;;   text_gap   文字底边距"图形最小包络盒"顶边的距离
        ;;   box_margin 单元包络盒相对内容的外扩内边距(精雕会画出该盒;
        ;;              线切割只用它作排版基准, 不画盒)
        ;;   v2.18: atof 换 dt:sz-num-or(distof 校验) —— ini 误填垃圾串时
        ;;   atof 静默回 0.0(box_gap=0 会排出贴死的退化排版, 坑 #54 同款)
        box-gap (dt:sz-num-or (dt:sz-cfg-get "排版" "box_gap" "100.0") 100.0)
        per-row (max 1 (atoi (dt:sz-cfg-get "排版" "per_row" "4")))
        text-gap (dt:sz-num-or (dt:sz-cfg-get "排版" "text_gap" "50.0") 50.0)
        box-margin (dt:sz-num-or (dt:sz-cfg-get "排版" "box_margin" "20.0") 20.0))

  ;; 0) 预先探测源图形的整体倾斜角 (用于后续正交旋转摆正)
  (setq rot-ang (dt:sz-detect-tilt-angle cands))

  ;; 1) 全自动计算并定位目标图纸全路径 (免弹窗选择)
  (setq target-path (dt:sz-auto-target-path title))
  ;; v2.9: 右缘游标按目标图纸键控 —— 换图即失效, 防止把 A 图的右缘
  ;; 用到 B 图(两图互不相干)
  (if (not (equal target-path *dt-wx-last-right-path*))
    (setq *dt-wx-last-right* nil
          *dt-wx-last-right-path* target-path))
  (if (or (null target-path) (= target-path ""))
    (progn
      (princ (strcat "\n【" title "】未获取到有效目标图纸路径，操作已取消。"))
      nil)
    (progn
      ;; 2) 打开或创建目标文档
      (setq tgt-doc (dt:sz-find-open-doc target-path))
      (if (null tgt-doc)
        (if (findfile target-path)
          (setq tgt-doc (vl-catch-all-apply 'vla-open (list docs target-path)))
          (progn
            (setq tgt-doc (vl-catch-all-apply 'vla-add (list docs)))
            (if (and (not (vl-catch-all-error-p tgt-doc)) tgt-doc)
              (vl-catch-all-apply 'vla-saveas (list tgt-doc target-path))))))

      (if (or (null tgt-doc) (vl-catch-all-error-p tgt-doc))
        (progn
          (princ (strcat "\n【错误】无法打开或创建目标图纸: " target-path))
          nil)
        (progn
          (setq ms-tgt (vla-get-modelspace tgt-doc))
          ;; 确保文字样式与专用图层在目标图纸中准确就绪
          (dt:sz-ensure-style tgt-doc)
          (dt:sz-ensure-doc-layer tgt-doc "外协文字" 144)
          (if target-layer
            (dt:sz-ensure-doc-layer tgt-doc target-layer 1)
            (progn
              (dt:sz-ensure-doc-layer tgt-doc "FLB" 1)
              (dt:sz-ensure-doc-layer tgt-doc "LS" 4)
              (dt:sz-ensure-doc-layer tgt-doc "RZ" 30)
              (dt:sz-ensure-doc-layer tgt-doc "DK" 8)
              (dt:sz-ensure-doc-layer tgt-doc "JRT" 2)
              (dt:sz-ensure-doc-layer tgt-doc "DP" 5)
              (dt:sz-ensure-doc-layer tgt-doc "ZJJ" 193)))

          ;; 3) v2.14 排版基准 —— 只取"可靠源"(非活动目标文档里 MText 的
          ;;    boundingbox 不可靠, 见头注 v2.14):
          ;;      · 行判定 / 行内容顶: "外协文字"插入点(属性直读, 可靠;
          ;;        插入点 = 文字底边 = 内容顶 + text_gap)
          ;;      · 行右缘 / 内容最底缘: 内容实体 bbox(线框数据, 可靠)
          ;;      · 单元盒尺寸: 在当前图里量(可靠, 见 4f)
          (setq txt-list (dt:sz-doc-texts tgt-doc "外协文字")
                grid-n   (length txt-list)
                grid-col 0
                txt-infos nil
                txt-min-y 1e99)
          (foreach o txt-list
            (setq ip-t (vlax-safearray->list
                         (vlax-variant-value (vla-get-insertionpoint o))))
            (setq txt-infos (cons (cadr ip-t) txt-infos))
            (if (< (cadr ip-t) txt-min-y) (setq txt-min-y (cadr ip-t))))
          (foreach ti txt-infos
            (if (< (abs (- ti txt-min-y)) 1.0)
              (setq grid-col (1+ grid-col))))
          (setq first-p (= grid-n 0)
                row-ctop (if first-p 0.0 (- txt-min-y text-gap)))   ; 本行"内容顶"

          ;; 4) 在当前活动图纸 (cur-doc) 中原生构建正面工件与反面镜像 (开启 Undo 保护)
          (vla-startundomark cur-doc)
          (setq undo-marked T)   ; v2.18: *error* 兜底标记(各收口点清零)

          ;; 4a. 克隆 cands 生成正面临时图元 front-objs
          (setq front-objs nil)
          (foreach o cands
            (setq c (vl-catch-all-apply 'vla-copy (list o)))
            (if (and (not (vl-catch-all-error-p c)) c)
              (setq front-objs (cons c front-objs))))
          (setq front-objs (reverse front-objs))

          (if (null front-objs)
            (progn
              (vla-endundomark cur-doc)
              (setq undo-marked nil)
              (princ "\n【错误】克隆源图元失败。")
              nil)
            (progn
              ;; 若指定目标图层(如线切割置入 FLB)，统一设置
              (if target-layer
                (foreach o front-objs
                  (vl-catch-all-apply 'vla-put-layer (list o target-layer))))

              ;; 4b. 旋转摆正: 若源工件倾斜，所有正面曲线一起旋转摆正
              (if (and rot-ang (> (abs rot-ang) 1e-3))
                (dt:sz-straighten-objs front-objs rot-ang))

              ;; 4c. 计算包络盒并将正面工件归一化平移至原点 (X=0, Y=0)
              (setq src-bb (dt:rect-bbox front-objs))
              (if (or (null src-bb) (/= (length src-bb) 4))
                (progn
                  (foreach o front-objs (vl-catch-all-apply 'vla-delete (list o)))
                  (vla-endundomark cur-doc)
                  (setq undo-marked nil)
                  (princ "\n【错误】计算正面工件包络盒失败。")
                  nil)
                (progn
                  (setq s-minx (car src-bb)
                        s-miny (cadr src-bb)
                        s-maxx (caddr src-bb)
                        s-maxy (cadddr src-bb)
                        part-w (- s-maxx s-minx)
                        part-h (- s-maxy s-miny)
                        off-x  (- 0.0 s-minx)
                        off-y  (- 0.0 s-miny))
                  (foreach o front-objs
                    (vla-move o (vlax-3d-point '(0 0 0)) (vlax-3d-point (list off-x off-y 0.0))))

                  ;; 4d. 精雕正反面镜像 (v2.3: 镜像改在本体右侧, 竖直镜像轴, 间隔 75mm)
                  (setq back-objs nil)
                  (if (equal title "精雕")
                    (progn
                      (setq ax (+ part-w 37.5))
                      (setq back-objs (dt:sz-mirror-in-curdoc
                                        front-objs
                                        (vlax-3d-point (list ax 0.0 0.0))
                                        (vlax-3d-point (list ax 100.0 0.0))))
                      ;; 图层分离规则:
                      (if is-auto
                        (progn
                          ;; 自动模式: 正面排除 RZ, DP
                          (setq keep-front nil)
                          (foreach o front-objs
                            (setq lay-name (strcase (vla-get-layer o)))
                            (if (member lay-name '("RZ" "DP"))
                              (vl-catch-all-apply 'vla-delete (list o))
                              (setq keep-front (cons o keep-front))))
                          (setq front-objs (reverse keep-front))

                          ;; 自动模式: 反面排除 ZJJ, DK
                          (setq keep-back nil)
                          (foreach o back-objs
                            (setq lay-name (strcase (vla-get-layer o)))
                            (if (member lay-name '("ZJJ" "DK"))
                              (vl-catch-all-apply 'vla-delete (list o))
                              (setq keep-back (cons o keep-back))))
                          (setq back-objs (reverse keep-back)))
                        ;; 手动框选模式: 100% 全部保留，正反面均不执行任何删除
                        nil)))

                  ;; 4d+. v2.8 精雕: 正反面合并到单一图层"JD"。
                  ;; 注意: 临时实体在 cur-doc —— put-layer 前两个文档都必须
                  ;; 已有 JD 层(v2.7 只建了 tgt 侧, cur-doc 无层致 put-layer
                  ;; 静默失败 = "图形没移动"根因)
                  ;; v2.12: JD 层色改黄 2, 且精雕正反面实体统一置黄(用户需求:
                  ;;   精雕图整幅为黄) —— v2.7~v2.11 的"逐实体保留原色"在此
                  ;;   被统一覆盖。精雕输出为独立 dwg, 与主图 JRT 黄 2 同色
                  ;;   不构成同图歧义(用户定案)。
                  (if (equal title "精雕")
                    (progn
                      (dt:sz-ensure-doc-layer tgt-doc "JD" 2)
                      (dt:sz-ensure-doc-layer cur-doc "JD" 2)
                      ;; v2.9: 实参改 cur-doc —— 实体此刻还是 cur-doc 的临时
                      ;; 克隆(CopyObjects 在 4e 步才发生), 查 ByLayer 实体的
                      ;; "原图层色"必须查源侧; 传 tgt-doc 查到的是目标图刚被
                      ;; ensure 成固定色的同名层, 原色保留落空(v2.7 注释失实)
                      (dt:sz-flatten-layer cur-doc front-objs "JD")
                      (dt:sz-flatten-layer cur-doc back-objs "JD")
                      (foreach o (append front-objs back-objs)
                        (vl-catch-all-apply 'vla-put-color (list o 2)))))

                  ;; 4e. 单元宽度: 精雕 = 本体 + 75 镜像间隔 + 反面
                  (setq unit-w (if (equal title "精雕")
                                 (+ (* 2.0 part-w) 75.0)
                                 part-w))

                  ;; 4f. v2.13 文字先在"当前图"临时生成并量出真实包围盒, 与图形
                  ;;     合成"单元最小包络盒" —— 排版间距以它为准(精雕据此画盒;
                  ;;     线切割只用它作基准、不画盒)。文字底边距图形最小包络盒
                  ;;     顶边 = text_gap(可配)。测完随工件一起拷入目标图。
                  (dt:sz-ensure-style cur-doc)
                  (dt:sz-ensure-doc-layer cur-doc "外协文字" 144)
                  (setq src-fname (vl-filename-base (dt:sz-gets "DWGNAME")))
                  (if (or (null src-fname) (= src-fname "")) (setq src-fname "未命名工件"))
                  (setq src-multiline (dt:sz-format-multiline src-fname)
                        title-w (max 80.0 (min unit-w 220.0))
                        title-cx (* 0.5 unit-w)
                        title-cy (+ part-h text-gap))
                  (setq txt-obj (dt:sz-make-title cur-doc title-cx title-cy title-w src-multiline))
                  (if (null txt-obj)
                    (princ (strcat "\n【" title "】标注文字生成失败, 本幅按无文字排版。")))
                  (setq unit-bb (dt:rect-bbox (append front-objs back-objs
                                                      (if txt-obj (list txt-obj) nil))))
                  (if (or (null unit-bb) (/= (length unit-bb) 4))
                    (setq unit-bb (list 0.0 0.0 unit-w part-h)))
                  (setq ub-w (+ (- (caddr unit-bb) (car unit-bb)) (* 2.0 box-margin))
                        ub-h (+ (- (cadddr unit-bb) (cadr unit-bb)) (* 2.0 box-margin)))

                  ;; 4g. 排版落点 = 单元盒左下角 (x0, by0)
                  ;;     首幅: 盒左下 =(0,0);
                  ;;     行内追加: 盒左 = 上一幅盒右 + box_gap(无会话游标时由
                  ;;               内容几何反推本行盒右缘); 盒顶 = 本行内容顶 +
                  ;;               (文字高 + text_gap) + box_margin;
                  ;;     换行: 盒左对齐已有内容左缘(避免阶梯错位), 盒顶落在
                  ;;           已有内容最底缘下方 box_gap。
                  (cond
                    (first-p
                     (setq x0 0.0 by0 0.0))
                    ((< grid-col per-row)
                     (if (null *dt-wx-last-right*)
                       (setq *dt-wx-last-right*
                             (dt:sz-row-right tgt-doc row-ctop box-margin)))
                     (setq x0 (+ (if *dt-wx-last-right* *dt-wx-last-right* 0.0) box-gap)
                           by0 (- (+ row-ctop (- (cadddr unit-bb) part-h) box-margin)
                                  ub-h)))
                    (T
                     (setq existing-bb (dt:sz-doc-ms-bbox tgt-doc '("外协文字" "外协包络盒"))
                           x0 (- (if existing-bb (car existing-bb) 0.0) box-margin)
                           by0 (- (if existing-bb (cadr existing-bb) 0.0)
                                  box-margin box-gap ub-h))))

                  ;; 4h. 图形与文字整体平移, 使单元盒左下角落在 (x0, by0)
                  (setq export-objs (append front-objs back-objs
                                            (if txt-obj (list txt-obj) nil))
                        dx (- (+ x0 box-margin) (car unit-bb))
                        dy (- (+ by0 box-margin) (cadr unit-bb)))
                  (if (or (/= dx 0.0) (/= dy 0.0))
                    (foreach o export-objs
                      (vla-move o (vlax-3d-point '(0 0 0)) (vlax-3d-point (list dx dy 0.0)))))

                  ;; 5) 原子级跨图纸深拷贝 (CopyObjects, 异常回退 WBLOCK)
                  (setq sa (vlax-make-safearray vlax-vbObject (cons 0 (1- (length export-objs)))))
                  (vlax-safearray-fill sa export-objs)
                  (setq r (vl-catch-all-apply 'vla-copyobjects (list cur-doc sa ms-tgt)))
                  (if (vl-catch-all-error-p r)
                    (progn
                      ;; 回退 WBLOCK (v2.18: 临时名用 vl-filename-mktemp 唯一
                      ;; 生成 —— 固定名 _dt_wx_tmp.dwg 在双开 CAD 同时导出时
                      ;; 会互删对方的中间文件)
                      (setq tmp-dwg (vl-catch-all-apply
                                      'vl-filename-mktemp
                                      (list "_dt_wx_" (getenv "TEMP") ".dwg")))
                      (if (or (vl-catch-all-error-p tmp-dwg) (null tmp-dwg))
                        (setq tmp-dwg (strcat (if (getenv "TEMP") (getenv "TEMP") "C:\\TEMP")
                                              "\\_dt_wx_tmp.dwg")))
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
                              (vl-catch-all-apply 'vla-delete (list blk))))
                          (vl-catch-all-apply 'vl-file-delete (list tmp-dwg))))))

                  ;; 6) 彻底清理当前图纸临时图元并关闭 Undo
                  (foreach o export-objs
                    (vl-catch-all-apply 'vla-delete (list o)))
                  (vla-endundomark cur-doc)
                  (setq undo-marked nil)
                  ;; 6.5) v2.8 精雕: 目标图中原 FLB 系图层实体并入 JD 层并删原层
                  (if (equal title "精雕")
                    (progn
                      (dt:sz-ensure-doc-layer tgt-doc "JD" 2)
                      (setq migrated (dt:sz-migrate-layers
                                       tgt-doc "JD"
                                       (list "FLB" "LS" "RZ" "DK" "JRT" "DP" "ZJJ")))
                      (if (> migrated 0)
                        (princ (strcat "
【精雕】已将 " (itoa migrated)
                                       " 个实体并入 JD 图层, 原图层已移除。")))))

                  ;; 7) v2.13: 标注文字已在 4f 生成并随工件一并拷入目标图 ——
                  ;;    因排版间距要用"图形 ∪ 文字"的真实单元盒, 必须先量后放,
                  ;;    不能再像旧版那样拷完再补文字。

                  ;; 7.5) v2.3 精雕: 本体+镜像+文字 整体包络盒(独立图层"外协包络盒", 绿 3; v2.12 改色)
                  (if (equal title "精雕")
                    (progn
                      (dt:sz-ensure-doc-layer tgt-doc "外协包络盒" 3)
                      ;; v2.13: 盒 = 4f/4g 已算定的单元包络盒 —— 与间距同源,
                      ;; 相邻两盒四向净距恒等于 box_gap
                      (setq bx1 x0
                            by1 by0
                            bx2 (+ x0 ub-w)
                            by2 (+ by0 ub-h))
                      (setq box-obj (vl-catch-all-apply
                                      'vla-addlightweightpolyline
                                      (list ms-tgt
                                            (vlax-make-variant
                                              (vlax-safearray-fill
                                                (vlax-make-safearray vlax-vbDouble (cons 0 7))
                                                (list bx1 by1 bx2 by1 bx2 by2 bx1 by2))
                                              (logior vlax-vbArray vlax-vbDouble)))))
                      (if (and box-obj (not (vl-catch-all-error-p box-obj)))
                        (progn
                          (vla-put-closed box-obj :vlax-true)
                          ;; v2.4: 实体级颜色 —— 非活动文档的图层色显示不即时生效(同字体坑),
                          ;; 实体色优先(绿 3), 首幅即显
                          (vla-put-color box-obj 3)
                          (vla-put-layer box-obj "外协包络盒"))
                        (princ "\n【精雕】包络盒生成警告(工件本身不受影响)。"))))

                  ;; 8) 保存目标图纸并刷新
                  (setq save-res (vl-catch-all-apply 'vla-save (list tgt-doc)))
                  (if (vl-catch-all-error-p save-res)
                    (setq save-res (vl-catch-all-apply 'vla-saveas (list tgt-doc target-path))))
                  (if (vl-catch-all-error-p save-res)
                    (princ (strcat "\n【" title "】保存目标图纸警告: " (vl-catch-all-error-message save-res))))
                  (vl-catch-all-apply 'vla-regen (list tgt-doc :vlax-acallviewports))

                  (princ "\n------------------------------------------------------------")
                  (princ (strcat "\n【" title "】工件已成功输出并排版至: " target-path))
                  (princ (strcat "\n【" title "】排版位置: 第 " (itoa (1+ grid-n))
                                 " 幅 (单元盒左下 X=" (rtos x0 2 2)
                                 " Y=" (rtos by0 2 2) ", 间距 " (rtos box-gap 2 0) "mm"
                                 ", 单元盒 " (rtos ub-w 2 1) "x" (rtos ub-h 2 1)
                                 (if (equal title "精雕") ", 镜像在右侧 75mm" "")
                                 ", 上方已标注文件名)"))
                  (princ "\n------------------------------------------------------------")
                  ;; v2.13: 记录本幅单元盒右缘, 下一幅行内追加直接以它为基准(见 4g)
                  (setq *dt-wx-last-right* (+ x0 ub-w))
                  T)))))))))

;; ============================================================================
;; 四、主命令与对外接口
;; ============================================================================

;; 测量分流板主命令 (c:FLBSZ / c:FLBSIZE)
(defun c:FLBSZ ( / *error* ss cands closed-p box len wid p1 p2 p3 p4 ang
                   clip-str msg choice undo-started)
  (defun *error* (msg)
    ;; v2.9: 包络框绘制的 UNDO 组(command BE)在出错路径也要闭合,
    ;; 惯用法与 c:SJTZ 一致(标记 + vla-endundomark 收口, catch 双保险)
    (if undo-started
      (vl-catch-all-apply 'vla-endundomark
                          (list (vla-get-activedocument (vlax-get-acad-object)))))
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

  ;; 防御保护: 若 FLB 图层包含多个独立封闭图形(例如旧版本图纸遗留的复制件)，主动提示并降级手动框选
  (if (and cands closed-p (boundp '*dt-sz-multi-regions*) *dt-sz-multi-regions* (> *dt-sz-multi-regions* 1))
    (progn
      (princ (strcat "\n【分流板尺寸】提示: 图层 \"FLB\" 检测到 "
                     (itoa *dt-sz-multi-regions*)
                     " 个独立封闭图形(可能包含旧数据图纸复制件)。"))
      (princ "\n为避免多份包络造成尺寸误差，请手动框选需要测量的分流板: ")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (progn
          (princ "\n【分流板尺寸】未选择图元，命令已取消。")
          (setq cands nil closed-p nil))
        (progn
          (setq cands (dt:sz-curves-only (dt:ss->list ss)))
          (setq closed-p (if cands (dt:sz-check-closed cands) nil))))))

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
          (setq clip-str (strcat (dt:sz-fmt-num len) "*" (dt:sz-fmt-num wid)))
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
              (setq undo-started T)
              (command "_.UNDO" "BE")
              (dt:sz-draw-box-dim p1 p2 p3 p4)
              (command "_.UNDO" "E")
              (princ "\n【分流板尺寸】已在图层 \"FLB_BOX\" 绘制包络框与长宽标注(字高15)。")))))))
  (princ)
)

(defun c:FLBSIZE ( ) (c:FLBSZ))
(defun c:SZ ( ) (c:FLBSZ))
(defun c:WXSZ ( ) (c:FLBSZ))

;; 测量加热条长度主命令 (c:JRTSZ) —— 与测量分流板(FLBSZ)同级的只读测量:
;; 自动识别 JRT 图层加热条, 长度 = 各层嵌套线取中间值; 多条加热条
;; 列表点选、可连续测量; 检测不到/不完整 → 弹窗提示并取消(不降级手动选择)。
;; 封闭线排除: 优先 JRTFBX 定位副本精确匹配; 几何复核(生成规则反推)兜底。
(defun c:JRTSZ ( / *error* ss e objs fbx-ss fbx excl strips recs rec pick
                   best best-d d q i k bb loop strip-gap)
  (defun *error* (msg)
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【加热条长度】错误: " msg)))
    (princ))

  (princ "\n【加热条长度】正在检测加热条(JRT)...")

  ;; 步骤 1: 提取 JRT 图层曲线(检测不到 → 弹窗取消, 不转手动选择)
  (setq objs nil)
  (if (tblsearch "LAYER" "JRT")
    (progn
      (setq ss (ssget "X" '((8 . "JRT")
                            (0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if ss
        (foreach e (dt:ss->list ss)
          (if (dt:sz-curve-p e) (setq objs (cons e objs)))))))
  (if (null objs)
    (progn
      (alert "【提示】未检测到加热条!\n\n图层 \"JRT\" 不存在或图层上没有曲线。\n请先运行 JRT 生成加热条后再测量。\n命令已取消。")
      (princ "\n【加热条长度】未检测到加热条(JRT 图层无曲线), 命令已取消。"))
    (progn
      ;; 步骤 2: JRTFBX 定位副本(有实体且匹配上 → 精确剔除封闭线本体;
      ;;         剩余的由步骤 3 的几何复核兜底)
      (setq fbx nil)
      (if (tblsearch "LAYER" "JRTFBX")
        (progn
          (setq fbx-ss (ssget "X" '((8 . "JRTFBX") (0 . "LINE"))))
          (if fbx-ss (setq fbx (dt:ss->list fbx-ss)))))
      (setq excl (if fbx (dt:sz-jrt-fbx-match objs fbx) nil))
      (if (and excl (> (length excl) 0))
        (princ (strcat "\n【加热条长度】已按 JRTFBX 定位副本标记封闭线 "
                       (itoa (length excl)) " 条。")))
      ;; 步骤 3: 归堆 + 逐条测量
      ;; (JRTFBX 精确剔除先行; 几何复核按生成规则反推, 每条都跑一遍兜底)
      ;; 归堆间距可配: wx_runner.ini [测量加热条] strip_gap(默认 15;
      ;; 误填 <1 按默认处理, 防把一根条的嵌套线拆散)
      (setq strip-gap (dt:sz-num-or (dt:sz-cfg-get "测量加热条" "strip_gap" "15.0") 15.0))
      (if (< strip-gap 1.0) (setq strip-gap 15.0))
      (setq strips (dt:sz-jrt-strips objs strip-gap)
            recs nil)
      (foreach rec strips
        (setq recs (cons (dt:sz-jrt-strip-rec rec excl) recs)))
      (setq recs (reverse recs))
      ;; 步骤 4: 输出 —— 单条自动测; 多条列表点选、可连续测量
      (cond
        ((null recs)
         (alert "【提示】未检测到加热条!\n\n未能从 JRT 图层识别出加热条。\n命令已取消。")
         (princ "\n【加热条长度】未能识别出加热条, 命令已取消。"))
        ((= 1 (length recs))
         (princ (strcat "\n【加热条长度】检测到 1 条加热条("
                        (itoa (nth 0 (car recs))) " 段曲线), 自动测量。"))
         (dt:sz-jrt-report (car recs)))
        (T
         (princ (strcat "\n【加热条长度】检测到 " (itoa (length recs))
                        " 条加热条:"))
         (setq i 1)
         (foreach rec recs
           (setq bb (dt:rect-bbox (mapcar 'vlax-ename->vla-object
                                          (nth 9 rec))))
           (if bb
             (princ (strcat "\n  第" (itoa i) "条: " (itoa (nth 0 rec))
                            " 段曲线 / " (itoa (nth 1 rec)) " 条嵌套线, 中心("
                            (rtos (* 0.5 (+ (car bb) (nth 2 bb))) 2 1) ", "
                            (rtos (* 0.5 (+ (cadr bb) (nth 3 bb))) 2 1) ")"))
             (princ (strcat "\n  第" (itoa i) "条: " (itoa (nth 0 rec))
                            " 段曲线 / " (itoa (nth 1 rec)) " 条嵌套线")))
           (setq i (1+ i)))
         (setq loop T)
         (while loop
           (setq pick (getpoint "\n请点选要测量的加热条: "))
           (if (null pick)
             (setq loop nil)
             (progn
               ;; 就近匹配点选位置的那条加热条
               (setq best nil
                     best-d 1e99)
               (foreach rec recs
                 (foreach e (nth 9 rec)
                   (setq q (vl-catch-all-apply 'vlax-curve-getclosestpointto
                                               (list e pick)))
                   (if (and (not (vl-catch-all-error-p q)) q)
                     (setq d (distance pick q))
                     (setq d 1e99))
                   (if (< d best-d)
                     (setq best-d d
                           best rec))))
               (if best (dt:sz-jrt-report best))
               (initget "Y N")
               (setq k (getkword "\n继续测量其他加热条? [是(Y)/否(N)] <N>: "))
               (if (not (and k (= (strcase k) "Y"))) (setq loop nil)))))))
      (princ))))

;; 线切割主命令 (c:XQG)
(defun c:XQG ( / *error* ss cands closed-p)
  (defun *error* (msg)
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
    (dt:sz-export-to-dwg cands "线切割" "FLB" nil))
  (princ)
)

;; 精雕主命令 (c:JD)
(defun c:JD ( / *error* ss cands is-auto)
  (defun *error* (msg)
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【精雕】错误: " msg)))
    (princ))

  (princ "\n【精雕】正在提取热流道加工曲线...")
  (setq cands (dt:sz-collect-auto-curves))
  (if (and cands (> (length cands) 0))
    (setq is-auto T)
    (progn
      (setq is-auto nil)
      (princ "\n【精雕】未在自动化图层(FLB/LS/RZ/DK/JRT/DP/ZJJ)找到曲线，请手动框选加工曲线:")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (princ "\n【精雕】未选择图元，命令已取消。")
        (setq cands (dt:sz-curves-only (dt:ss->list ss))))))

  ;; 输出到自动路径的精雕图纸 (含 75mm 间隔上下镜像正反面排版)
  (if cands
    (dt:sz-export-to-dwg cands "精雕" nil is-auto))
  (princ)
)

;; 数据图纸主命令 (c:SJTZ)
(defun c:SJTZ ( / *error* ss cands o bb p0 p1 dx dy new-objs new-o new-bb
                   minx miny maxx maxy date-str def-mj def-flb flb-ss
                   flb-cands flb-box mtxt-str doc ms x-label y-top th mtxt-obj
                   rot-ang undo-started)
  (defun *error* (msg)
    (if undo-started
      (vl-catch-all-apply 'vla-endundomark (list (vla-get-activedocument (vlax-get-acad-object)))))
    (if (and msg
             (not (wcmatch (strcase msg t) "*cancel*,*exit*,*abort*,*取消*")))
      (princ (strcat "\n【数据图纸】错误: " msg)))
    (princ))

  (princ "\n【数据图纸】正在提取热流道加工曲线...")
  (setq cands (dt:sz-collect-auto-curves))

  ;; 若未找到则转入手动框选
  (if (null cands)
    (progn
      (princ "\n【数据图纸】未在自动化图层(FLB/LS/RZ/DK/JRT/DP/ZJJ)找到曲线，请手动框选曲线:")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE,SPLINE,CIRCLE,ELLIPSE"))))
      (if (null ss)
        (princ "\n【数据图纸】未选择图元，命令已取消。")
        (setq cands (dt:sz-curves-only (dt:ss->list ss))))))

  ;; 步骤 2: 交互式复制与自由移动
  (if (and cands (> (length cands) 0))
    (progn
      ;; 探测加工曲线(优先分流板)的整体倾斜角
      (setq rot-ang (dt:sz-detect-tilt-angle cands))

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

          (setq doc (vla-get-activedocument (vlax-get-acad-object))
                ms  (vla-get-modelspace doc))
          (setq undo-started T)
          (vl-catch-all-apply 'vla-startundomark (list doc))

          ;; 确保专用隔离图层 "数据图纸" 存在(橄榄绿 63, v2.11 重排避免与 LD 白 7 同色)
          (dt:ensure-layer (vla-get-layers doc) "数据图纸" 63 "橄榄绿")

          ;; 克隆图元并移动至目标位置，全部置入新图层 "数据图纸" (防止干扰 FLB 尺寸测量)
          (setq new-objs nil)
          (foreach o cands
            (setq new-o (vl-catch-all-apply 'vla-copy (list o)))
            (if (and (not (vl-catch-all-error-p new-o)) new-o)
              (progn
                (vl-catch-all-apply
                  'vla-move
                  (list new-o (vlax-3d-point 0 0 0) (vlax-3d-point dx dy 0)))
                (vl-catch-all-apply 'vla-put-layer (list new-o "数据图纸"))
                (setq new-objs (cons new-o new-objs)))))

          ;; 图形摆正: 若分流板倾斜，将复制出来的所有图形曲线整体一起旋转摆正(垂直或平行)
          (if (and rot-ang (> (abs rot-ang) 1e-3))
            (dt:sz-straighten-objs new-objs rot-ang))

          (setq new-bb (dt:rect-bbox new-objs))
          (if (null new-bb)
            (progn
              ;; v2.9: 1507 用 vla-startundomark 开组, 这里也用 COM 收口
              ;; (原 command "_.UNDO" "E" 属 API 混用, 与坑#69 全 COM 化相悖)
              (vl-catch-all-apply 'vla-endundomark (list doc))
              (princ "\n【数据图纸】未能计算新图形范围。"))
            (progn
              (setq minx (car new-bb)
                    miny (cadr new-bb)
                    maxx (caddr new-bb)
                    maxy (cadddr new-bb))

              ;; 步骤 3: 提取参数值 (自动生成当前无空格日期、文件名及母件分流板长宽)
              (setq date-str (dt:sz-get-date-str))

              (setq def-mj (vl-filename-base (dt:sz-gets "DWGNAME")))
              (if (or (null def-mj) (= def-mj "")) (setq def-mj "1031-02"))

              ;; 自动探测分流板尺寸 (复制图元已入 "数据图纸"，FLB 图层仅剩母件，准确无双重包络)
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

              (dt:sz-ensure-style doc)
              (dt:ensure-layer (vla-get-layers doc) "外协文字" 144 "深青")

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

              (if undo-started (vl-catch-all-apply 'vla-endundomark (list doc)))
              (princ "\n【数据图纸】图形已克隆至图层 \"数据图纸\"(倾斜已摆正)，右侧信息文字生成完成。")))))))
  (princ)
)

(princ (strcat "\n外协测量工具已加载 " *dt-wx-ver*
               ": FLBSZ=测量分流板 / JRTSZ=加热条长度 / XQG=线切割 / JD=精雕 / SJTZ=数据图纸。"))
(princ)
