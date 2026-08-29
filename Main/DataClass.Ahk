; ============================================================
; 条目对象（MacroItem）—— 替代原 TableItem 内 20+ 平行数组
; 每条宏配置一个对象，字段即属性，跨表引用一律引用 ItemID
; ============================================================
class MacroItem {
    __New() {
        this.ID := ""           ;条目唯一 ID（复用 GetCMDSerialStr("Item") 机制，全局唯一）
        this.TK := ""           ;触发键
        this.Macro := ""        ;宏内容
        this.HoldTime := 500    ;时间参数（长按=长按时间，双击=双击间隔）
        this.UnorderedTrigger := false  ;顺序触发（勾选时只按顺序注册，不勾选则正反向都注册）
        this.Forbid := 0        ;禁止
        this.LoopCount := "1"   ;循环次数
        this.Remark := ""       ;备注
        this.TriggerType := 1   ;触发类型
        this.TimingSerial := "" ;定时配置序列码
        this.Mode := 1          ;按键模式   1.AHK Send 2.keybd_event 3.罗技 4.AHI
        this.StartTipSound := 1 ;开始提示音 1.无   2.触发提示  3.循环首次提示
        this.EndTipSound := 1   ;结束提示音 1.无   2.结束提示  3.循环结束提示
        this.IcoPath := ""      ;菜单宏ICO路径
        this.VoiceKeywords := "" ;语音触发关键词（多个用英文逗号 , 分隔）
        this.BindWindow := ""   ;§22 宏级窗口绑定：宏内所有窗口信息填「{绑定窗口}」时运行时替换为此值（一改全改）
        this.FoldID := ""       ;所属折叠框 ID（FoldInfo 的 ID 引用，替代 IndexSpanArr 范围）

        ; ===== 运行时状态（原平行数组） =====
        this.ColorState := 0            ;颜色状态
        this.IsWorkIndex := 0           ;work正在执行中（Worker 索引）
        this.GraphBranchCount := 0      ;图形宏并行分支 Worker 引用计数
        this.Killed := false            ;标记结束状态
        this.Pause := false             ;暂停
        this.ActionCount := 0           ;记录执行次数，用于循环次数判断
        this.HoldKey := Map()           ;记录当前按下的按键，以便结束时松开
        this.ToggleState := false       ;触发键开关状态
        this.ToggleAction := ""         ;触发键开关Action
        this.VariableMap := Map()       ;每条宏对应的变量映射:内置变量
    }
}

; ============================================================
; 折叠框对象（MacroFold）—— 替代 ItemFoldInfo 平行数组 + IndexSpanArr
; 每个折叠框一个对象，ID 全局唯一；条目通过 MacroItem.FoldID 归属
; ============================================================
class MacroFold {
    __New() {
        this.ID := ""               ;折叠框唯一 ID
        this.Remark := ""           ;折叠框备注
        this.FrontInfo := ""        ;折叠框前台信息
        this.ForbidState := false   ;禁用状态
        this.FoldState := false     ;折叠状态
        ;§2 模块独立开关：按下该快捷键切换本模块启用/禁用（实时经热键重绑 + HotReloadBus 生效）
        this.ForbidHotkey := ""     ;模块启用/禁用开关快捷键（自定义，空=不启用）
        ;菜单栏功能
        this.TKType := 4            ;触发类型
        this.TK := ""               ;触发按键，菜单栏功能
        this.HoldTime := 500        ;时间参数（长按=长按时间，双击=双击间隔）
        this.UnorderedTrigger := false  ;顺序触发
    }
}

; ============================================================
; 表对象（TableItem）—— 替代原表级平行数组 + MainSoftData.TabNameArr/TabSymbolArr
; 表集合动态化：ID 稳定唯一，Name 可改，Symbol 决定语义分派
; ============================================================
class TableItem {
    __New() {
        this.ID := ""           ;表身份：恒定等于 Symbol（Normal/String/...），不再用动态 t_xxx，彻底消除启动漂移
        this.Name := ""         ;表显示名（动态可改）
        this.Symbol := ""       ;表类型符号 Normal/String/Menu/UI/Voice/Timing/SubMacro/Replace/Tool/Setting/Help/Reward/Thank
        this.Order := 0         ;显示顺序（TabControl 排序用）
        this.PersistSeg := ""   ;存储段名：新格式段名=固定 Symbol(空=用 ID)；旧 t_xxx 数据迁移期的临时段名（迁移后清空）

        this.Items := []        ;MacroItem 对象数组（仅顺序）
        this.ItemMap := Map()   ;ItemID -> MacroItem 快速索引
        this.Folds := []        ;MacroFold 对象数组
        this.FoldMap := Map()   ;FoldID -> MacroFold 快速索引

        ; ===== UI 运行时状态 =====
        this.UnderPosY := 0         ; table的最大PosY
        this.SliderValue := 0       ;   滑动值
        this.OffSetPosY := 0        ;   偏移值
        this.AllConArr := []        ;   table中所有的con
        this.AllGroup := []         ; table中所有的group
        this.FoldOffsetArr := []    ;和初始状态的高度偏移值
        this.FoldBtnArr := []       ;折叠筐按钮
        this.ConIndexMap := Map()
        this.FoldInfo := ""         ; 旧格式折叠信息（迁移期临时字段，迁移后置空）
    }

    ; 便捷：按 ItemID 取条目（无则返回 ""）
    GetItem(itemID) {
        return this.ItemMap.Has(itemID) ? this.ItemMap[itemID] : ""
    }

    ; 便捷：按 FoldID 取折叠框（无则返回 ""）
    GetFold(foldID) {
        return this.FoldMap.Has(foldID) ? this.FoldMap[foldID] : ""
    }

    ; 显示顺序下标（1 基）：按 TableID 在 TableInfo 数组中的位置。
    ; 新体系表身份是 ID；Index 仅代表 UI 渲染顺序 / 跨进程索引（主进程与 Worker 加载同一配置，顺序一致）。
    Index => GetTableIndexByID(this.ID)

    ; 重建 ItemMap/FoldMap 索引（条目数组增删后调用）
    RebuildIndex() {
        this.ItemMap := Map()
        for item in this.Items {
            if (item.ID != "")
                this.ItemMap[item.ID] := item
        }
        this.FoldMap := Map()
        for fold in this.Folds {
            if (fold.ID != "")
                this.FoldMap[fold.ID] := fold
        }
    }
}

; ============================================================
; 旧版折叠信息（ItemFoldInfo）—— 保留类定义仅为迁移期读取旧 JSON
; 新体系使用 MacroFold；迁移完成后可删除
; ============================================================
class ItemFoldInfo {
    __New() {
        this.RemarkArr := []        ;折叠框备注
        this.FrontInfoArr := []     ;折叠框前台信息
        this.IndexSpanArr := []     ;范围索引
        this.ForbidStateArr := []   ;禁用状态
        this.FoldStateArr := []    ;折叠状态

        ;菜单栏功能
        this.TKTypeArr := []    ;触发类型
        this.TKArr := []        ;触发按键，菜单栏功能
        this.HoldTimeArr := []  ;时间参数（长按=长按时间，双击=双击间隔）
        this.UnorderedTriggerArr := []  ;顺序触发（勾选时只按顺序注册，不勾选则正反向都注册）
    }
}

class MacroItemInfo {
    __New(index, itemConInfo) {
        this.index := index
        this.itemConInfo := ItemConInfo
    }
}

class ItemConInfo {
    __New(Con, tableItem, FoldIndex) {
        this.Con := Con
        this.tableItem := tableItem
        this.FoldOffsetArr := tableItem.FoldOffsetArr
        this.FoldInfo := tableItem.FoldInfo
        this.FoldIndex := FoldIndex
        this.IsTitle := false
        this.IsDel := false
        this.Con.GetPos(&PosX, &PosY)
        this.OriPosX := PosX
        this.OriPosY := PosY
        this.SelfOffsetY := 0
    }

    UpdatePos(offsetPosY) {
        try {
            if (this.IsDel) {
                this.Con.Move(this.OriPosX, -10000)
                return
            }

            isFold := this.FoldInfo.FoldStateArr[this.FoldIndex]
            if ((isFold && !this.IsTitle)) {
                this.Con.Move(this.OriPosX, -10000)
                return
            }
            PosY := 0
            for index, value in this.FoldOffsetArr {
                if (index >= this.FoldIndex)
                    break
                PosY += value
            }

            PosY := PosY + this.OriPosY + this.SelfOffsetY - offsetPosY
            this.Con.Move(this.OriPosX, PosY)
        }
    }

    DelAfterOffset(offsetY) {
        this.SelfOffsetY -= offsetY
    }

    Hide() {
        this.IsDel := true
    }
}

; ============================================================
; MainSoftData — Master 进程专用数据
; 包含 GUI 配置、UI 面板、热键绑定、工具检测、录制、OCR 等
; Worker 线程不需要这些数据
; ============================================================
class MainConfig {
    __New() {
        ; ========== 全局对象引用（GUI 控件 / 函数绑定） ==========
        this.MyGui := {}                ; 软件主界面 GUI 句柄
        this.TabCtrl := {}              ; Tab3 页签控件
        this.BtnSave := ""              ; "应用并保存"按钮（供其他 GUI 获取焦点）
        this.MacroEditGui := ""         ; 当前活动的宏编辑器 GUI

        ; ========== 配置管理 ==========
        this.CurSettingName := ""       ; 当前配置方案名称
        this.SettingArrStr := ""        ; 所有配置方案名称列表（"π" 分隔字符串）
        this.HasSaved := false          ; 是否已执行保存
        this.IsReload := false          ; 是否正在重载软件
        this.AgreeAgreement := false    ; 是否已同意免责协议

        ; ========== 启动与窗口设置 ==========
        this.IsBootStart := false       ; 是否开机自启
        this.IsAdminStart := false      ; 是否以管理员权限启动
        this.IsMinStart := false        ; 是否最小化启动（常驻托盘）
        this.SoftBGColor := "f0f0f0"    ; 软件背景颜色 (6位HEX)
        this.BackImagePath := ""        ; §11 主界面背景图（全局配置，空=不启用；保存重启生效）
        this.Theme := "RMT_Light"       ; XAML 界面主题名称
        this.ShowSplitLine := false     ; 表格是否显示分割线
        this.IsModalSubGui := true      ; 子窗口是否模态（阻止主窗口操作）

        ; ========== Tab 页签 ==========
        ; 表集合动态化：表定义（ID/Symbol/Name/Order）存于 MySoftData.TableInfo + 配置文件 [Tables] 段，
        ; 不再使用固定 TabNameArr/TabSymbolArr 平行数组
        this.TableIndex := 1            ; 当前显示的 Tab 页索引（1 基，UI 槽位，运行时同步）
        this.CurTableID := ""           ; 当前显示的表 ID（身份，持久化用；空则回落 TableIndex）
        this.TabPosX := 0               ; Tab 组件左上角 X 坐标
        this.TabPosY := 0               ; Tab 组件左上角 Y 坐标
        ; §10 显示页签选项：symbol → 是否显示（隐藏仅显示效果，不影响触发）；非配置表恒显示
        this.TabVisibleMap := Map()

        ; ========== 热键绑定 ==========
        this.IsSuspend := false         ; 软件休眠状态
        this.SuspendHotkey := ""        ; 休眠快捷键（空则未绑定）
        this.IsPause := false           ; 暂停所有宏状态
        this.PauseHotkey := ""          ; 暂停快捷键（空则未绑定）
        this.KillMacroHotkey := ""      ; 终止所有宏快捷键（空则未绑定）

        ; ========== 数值浮动选项 ==========
        this.HoldFloat := 0             ; 点击持续时间浮动 (%)
        this.PreIntervalFloat := 0      ; 每次执行前间隔浮动 (%)
        this.IntervalFloat := 0         ; 指令间隔浮动 (%)
        this.CoordXFloat := 0           ; 坐标 X 浮动 (px)
        this.CoordYFloat := 0           ; 坐标 Y 浮动 (px)

        ; ========== 多线程设置 ==========
        this.MutiThreadNum := -1        ; 多线程数 (-1 = 动态调整)
        this.DynamicCorePoolSize := 3   ; 动态模式核心池大小
        this.ElasticTimeout := 30       ; 弹性 Worker 超时 (秒)
        this.MacroStopType := 1         ; 宏终止方式 (1=智能终止, 2=强制终止)

        ; ========== 按键选项 ==========
        this.KeyDownDownType := 1       ; 按下时按下处理 (1=自动松开, 2=忽略重复按下, 3=允许重复按下)
        this.AutoLoosenModifier := true ; 组合键触发前自动松开修饰键
        this.ContinuousTrigger := true  ; 按住触发键可连续触发（关则需松开后再触发）

        ; ========== 屏幕截图 ==========
        this.ScreenShotType := 3        ; 截图方式 (1=微软截图, 2=RMT截图, 3=SC截图)
        this.CheckForeground := false   ; 是否仅前台窗口运行宏

        ; ========== 字体/语言 ==========
        this.FontType := "微软雅黑"     ; 软件字体名称
        this.FontSize := 15             ; 主题字体大小（设计与默认均为 15）
        this.FontList := []             ; 系统可用字体列表
        this.Lang := "中文"             ; 当前语言
        this.LangArr := []              ; 可用语言列表

        ; ========== 手柄 ==========
        this.JoyType := "Xbox"          ; 宏手柄类型 (Xbox/DS4)，实际模拟输出到 ViGEm 虚拟手柄的类型
        this.TriggerJoyType := "Xbox"   ; 手柄映射 (Xbox/PS5)，触发键、按键指令、按键检测等所有手柄按键名称显示统一使用此设置

        ; ========== 宏编辑器 ==========
        ; 新建空宏时的首选编辑器：1=逻辑树，2=图形节点
        this.PreferredMacroEditor := 1
        this.SharedCopy := false        ; 逻辑树编辑器右键菜单显示「共享复制」（原样复制，不重新分配序列号）
        this.RemarkAutoType := 2        ; 指令备注自动生成 (1=不生成, 2=自动生成, 3=覆盖生成)
        ; §14.5 逻辑树调试热键（可在 设置→快捷键 中修改，不再固定 F5/F6）
        this.DebugRunHotkey := "f5"     ; 调试运行
        this.DebugStepHotkey := "f6"    ; 调试单步运行

        ; ========== 提示选项 ==========
        this.NoVariableTip := false     ; 未找到变量时是否弹窗提醒
        this.BusinessLog := false       ; 业务日志开关（统一日志 C 项：宏运行流水）

        ; ========== 日志与错误（C 项阶段5）==========
        this.SysLogMinLevel := "info"   ; 系统日志最低级别：debug/info/warn/error（debug 需显式开启）
        this.LogWarnBubble := true      ; warn 级托盘气泡（2s 自动消失）
        this.LogErrorBadge := true      ; error 级错误中心聚合

        ; ========== 菜单轮盘 ==========
        this.FixedMenuWheel := false    ; 是否固定菜单轮盘位置
        this.MenuWheelSelectMode := 2   ; 轮盘选择模式 (1=点击选择, 2=划线选择)
        this.MenuWheelShowTooltip := false  ; 是否显示扇区名称提示
        this.MenuWheelScale := 100      ; 轮盘大小 (百分比, 50~200)
        this.CurMenuWheelIndex := -1    ; 当前显示的菜单轮盘索引

        ; ========== 统一主题颜色（轮盘/浮窗/指令显示） ==========
        ; 扩展与缺键回退见 AppThemeUtil 文件头约定；DefaultThemeKey=Default
        this.AppTheme := "Default"
        this.ThemeColors := Map()       ; Key→#ARGB，加载后应含 ColorDefs 全部项

        ; ========== 界面浮窗 ==========
        this.UIPanelShowOnActive := true    ; 界面激活时默认显示浮窗
        this.UIPanelDefaultPos := 1         ; 浮窗出现位置锚点 (1=左上, 2=中上, 3=右上, 4=中左, 5=中心, 6=中右, 7=左下, 9=中下, 10=右下)
        this.UIPanelOffsetX := 100          ; 出现位置偏移 X (0~500)
        this.UIPanelOffsetY := 100          ; 出现位置偏移 Y (0~500)
        this.UIPanelTitleBg := "#FF8B4513"   ; 标题背景 (由主题同步)
        this.UIPanelTitleText := "#FFFFFFFF" ; 标题文本 (由主题同步)
        this.UIPanelBtnColor := "#FFDAA520"  ; 按钮背景 (由主题同步)
        this.UIPanelBtnText := "#FF5C3317"  ; 按钮文本 (由主题同步)
        this.UIPanelFontColor := "#FF5C3317" ; 兼容旧字段，等同按钮文本
        this.UIPanelBgColor := "#C0FFE4B5"   ; 内容背景 (由主题同步)
        this.UIPanelBtnHeight := 34          ; 按钮高度
        this.UIPanelFontSize := 12           ; 按钮字体大小
        this.UIPanelBtnWidth := 80           ; 按钮宽度
        this.UIPanelCols := 3                ; 每行按钮个数

        ; ========== CMD 指令提示窗口 ==========
        this.CMDTip := false            ; 是否显示指令提示
        this.CMDWidth := Round(225 * A_ScreenDPI / 96)  ; CMD 窗口宽度（按 DPI 缩放）
        this.CMDHeight := 300           ; CMD 窗口高度
        this.CMDPosX := A_ScreenWidth - this.CMDWidth  ; 默认靠右
        this.CMDPosY := 0               ; CMD 窗口 Y 坐标
        this.CMDBGColor := "FFF8DC"     ; CMD 窗口背景色 (6位RGB，由主题同步)
        this.CMDRunBGColor := "90CAF9"  ; CMD 运行中背景色 (由主题同步)
        this.CMDTransparency := 50      ; CMD 背景透明度 (0=不透明，100=完全透明)
        this.CMDFontSize := "12"        ; CMD 字体大小
        this.CMDFontColor := "5C3317"   ; CMD 字体颜色 (由主题同步)
        this.CMDLogToFile := false      ; 是否输出到日志文件
        this.CMDLogFilePath := ""       ; 日志文件路径（空=默认，自动使用 Log/CMDLog.txt）
        this.CMDLogAutoClear := 0       ; 自动清理 0=从不, 1=每天, 2=每周

        ; ========== 变量监视器 ==========
        this.VarListenTop := true       ; 变量监视器窗口是否置顶（默认置顶）
        this.VarListenWidth := 400      ; 监视器窗口宽度
        this.VarListenHeight := 420     ; 监视器窗口高度

        ; ========== 框选相关 ==========
        this.SelectAreaAction := ""     ; 框选完成回调（显示框选范围）
        this.GetAreaAction := ""        ; 获取区域回调（不显示框选范围，用于系统截图）
        this.StartAreaPosX := ""        ; 框选起点 X 坐标
        this.StartAreaPosY := ""        ; 框选起点 Y 坐标

        ; ========== 其他 ==========
        this.LastShowMonth := 0         ; 上次显示"打赏"Tab 的月份

        ; ============================================================
        ; 以下为原 ToolCheckInfo 字段 — 工具检测 / 录制 / OCR
        ; ============================================================

        ; ---------- 工具检测：热键 ----------
        this.ToolCheckHotKey := ""          ; 鼠标信息检测快捷键
        this.ToolRecordMacroHotKey := ""    ; 指令录制快捷键
        this.ToolTextFilterHotKey := ""     ; 文本提取快捷键
        this.ScreenShotHotKey := ""         ; 屏幕截图快捷键 (工具页)
        this.FreePasteHotKey := ""          ; 自由贴快捷键

        ; ---------- 工具检测：实时信息 ----------
        this.IsToolCheck := false       ; 鼠标信息检测开关
        this.PosStr := ""               ; 当前鼠标坐标字符串
        this.WinPosStr := ""            ; 当前窗口坐标字符串
        this.ProcessName := ""          ; 鼠标所在窗口进程名
        this.ProcessTile := ""          ; 鼠标所在窗口标题
        this.ProcessPid := ""           ; 鼠标所在窗口 PID
        this.ProcessClass := ""         ; 鼠标所在窗口类名
        this.ProcessId := ""            ; 鼠标所在窗口 ID (HWND)
        this.Color := ""                ; 鼠标所在像素颜色 (HEX)

        ; ---------- 录制 ----------
        this.IsToolRecord := false      ; 指令录制开关
        this.IsTogStartRecord := false  ; 是否正在触发开始录制 (区分快捷键触发)
        this.IsTogEndRecord := false    ; 是否正在触发结束录制
        this.RecordLastTime := ""       ; 上一条录制指令的时间戳
        this.RecordMacroStr := ""       ; 录制结果的宏指令字符串
        this.RecordHoldKeyMap := Map()  ; 录制中按住的按键映射
        this.RecordInitialHoldMap := Map()  ; 录制开始时即已按住的按键（预采样基线）
        this.RecordHoldMuti := true     ; 录制时是否合并按住的多键
        this.RecordAutoLoosen := true   ; 录制时是否自动松开按键
        this.RecordKeyboard := true     ; 是否录制键盘
        this.RecordMouse := true        ; 是否录制鼠标
        this.RecordMouseTrail := true   ; 鼠标轨迹录制 (0=不录制, 1=关键点位, 2=关键点相对位移, 3=全量)
        this.RecordMouseTrailSpeed := 1 ; 鼠标轨迹录制速度
        this.RecordJoy := false         ; 是否录制手柄
        this.RecordJoyInterval := 100   ; 手柄录制间隔 (ms)
        this.RecordShowBorder := true   ; 录制时是否显示边框 (0=关闭, 1=开启)

        ; ---------- OCR ----------
        this.OCRTypeValue := 1          ; OCR 引擎类型 (1=RapidOCR, ...)
    }
}

class SoftData {
    __New() {
        ; ========== Worker 标识与运行状态 ==========
        this.isWorker := false          ;子线程标识
        this.MacroRunningCount := 0     ;运行中的宏数量
        this.IsMacroWorking := false    ;宏正在运行

        ; ========== 外部库初始化状态 ==========
        this.IsLogitechInit := false    ;罗技按键初始化
        this.IsMouseControlInit := false ;MouseControl.dll 初始化

        ; ========== 临时提示 ==========
        this.ToolTipText := ""          ;临时提示文本
        this.ToolTipEndTime := ""       ;临时提示结束时间

        ; ========== 宏表格数据 ==========
        this.TableInfo := []            ;TableItem 表对象数组（顺序即显示顺序，元素为 TableItem）
        this.TableMap := Map()          ;TableID -> TableItem 快速索引（RebuildTableLocator 构建）
        this.GlobalItemMap := Map()     ;ItemID -> {TableID, Item} 全局条目索引（RebuildTableLocator 构建）

        ; ========== 按键映射 ==========
        ;特殊的按键，因为含有下划线，所有要特殊处理
        this.SpecialKeyMap := Map("Browser_Back", 0, "Browser_Forward", 0, "Browser_Refresh", 0, "Browser_Stop", 0,
            "Browser_Search", 0, "Browser_Favorites", 0, "Browser_Home", 0, "Volume_Mute", 0, "Volume_Down", 0,
            "Volume_Up", 0, "Media_Next", 0, "Media_Prev", 0, "Media_Stop", 0, "Media_Play_Pause", 0, "Launch_Mail", 0,
            "Launch_Media", 0, "Launch_App1", 0, "Launch_App2", 0, "Bright_Down", 0, "Bright_Up", 0)
        this.OnlyDownKeyMap := Map("WheelDown", 0, "WheelUp", 0, "Bright_Down", 0, "Bright_Up", 0, "None", 0)
        this.SpecialTableItem := TableItem()    ;特别的TableItem，用于编辑器模式测试指令

        ; ========== 连续触发按键 ==========
        ;这些按键不会重复触发按下的按键宏，特别标记特殊处理
        this.ContinueKeyMap := Map("LButton", "LButton", "~LButton", "LButton", "RButton", "RButton", "~RButton",
            "RButton", "MButton", "MButton", "~MButton", "MButton", "XButton1", "XButton1", "~XButton1", "XButton1",
            "XButton2", "XButton2", "~XButton2", "XButton2")
        this.ContinueIntervale := 50    ;连续触发间隔

        ; ========== 文件编码 ==========
        this.FileEncodingArr := ["ANSI", "GB2312", "GB18030", "BIG5", "UTF-8", "UTF-16"]

        ; ========== 数据缓存与变量 ==========
        this.DataCacheMap := Map()      ;指令缓存，减少读取文件的次数
        this.GlobalArrMap := Map()      ;UI下拉显示数组
        this.ArrayMap := Map()          ;真正的全局数组
        this.GlobalVariMap := Map()     ;UI下拉显示变量
        this.VariableMap := Map()       ;真正的全局变量
        this.DataFileMap := Map()       ;配置命令对应的文件路径
        this.DataClassMap := Map()      ;配置对应的数据类型

        ; ========== 指令提示（主进程与 Worker 共享） ==========
        this.CMDTip := false

        ; ========== 配置名称（Worker 用于文件路径解析） ==========
        this.CurSettingName := ""       ;当前配置名称

        ; ========== 热键绑定 ==========
        this.TriggerKeyMap := Map()     ;所有的按键宏，包括软件自身的快捷键

        ; ========== 手柄宏 ==========
        this.HasJoyMacro := false       ;含有手柄宏，手柄宏启动时需要初始化手柄（操作系统会提示，有点嘈）
        this.MacroTotalCount := 0       ;宏运行次数

        ; ========== 手柄映射 ==========
        this.JoyXboxToAhkMap := Map(
            "JoyA", "Joy1",
            "JoyB", "Joy2",
            "JoyX", "Joy3",
            "JoyY", "Joy4",
            "JoyLB", "Joy5",
            "JoyRB", "Joy6",
            "JoyLT", "JoyZMin",
            "JoyRT", "JoyZMax",
            "JoyLS", "Joy9",
            "JoyRS", "Joy10",
            "JoyBack", "Joy7",
            "JoyStart", "Joy8",
            "JoyPad", "Joy14",
            "JoyHome", "Joy13",
            "JoyDpadUp", "JoyPOV_0",
            "JoyDpadRight", "JoyPOV_9000",
            "JoyDpadDown", "JoyPOV_18000",
            "JoyDpadLeft", "JoyPOV_27000",
            "JoyAxisLXMin", "JoyXMin",
            "JoyAxisLXMax", "JoyXMax",
            "JoyAxisLYMin", "JoyYMin",
            "JoyAxisLYMax", "JoyYMax",
            "JoyAxisRXMin", "JoyUMin",
            "JoyAxisRXMax", "JoyUMax",
            "JoyAxisRYMin", "JoyRMin",
            "JoyAxisRYMax", "JoyRMax"
        )
        this.JoyPS5ToAhkMap := Map(
            "JoyA", "Joy1",      ; □ Square
            "JoyB", "Joy2",      ; × Cross
            "JoyX", "Joy3",      ; ○ Circle
            "JoyY", "Joy4",      ; △ Triangle
            "JoyLB", "Joy5",     ; L1
            "JoyRB", "Joy6",     ; R1
            "JoyLT", "JoyVMax",  ; PS5蓝牙L2在V轴     ; L2（数字按钮）
            "JoyRT", "JoyUMax",  ; PS5蓝牙R2在U轴     ; R2（数字按钮）
            "JoyLS", "Joy11",     ; 左摇杆按下（L3）
            "JoyRS", "Joy12",    ; 右摇杆按下（R3）
            "JoyBack", "Joy9",    ; Create
            "JoyStart", "Joy10",  ; Options
            "JoyPad", "Joy14",    ; 触摸板按压
            "JoyHome", "Joy13",   ; PS键
            "JoyDpadUp", "JoyPOV_0",
            "JoyDpadRight", "JoyPOV_9000",
            "JoyDpadDown", "JoyPOV_18000",
            "JoyDpadLeft", "JoyPOV_27000",
            "JoyAxisLXMin", "JoyXMin",
            "JoyAxisLXMax", "JoyXMax",
            "JoyAxisLYMin", "JoyYMin",
            "JoyAxisLYMax", "JoyYMax",
            "JoyAxisRXMin", "JoyUMin",
            "JoyAxisRXMax", "JoyUMax",
            "JoyAxisRYMin", "JoyRMin",
            "JoyAxisRYMax", "JoyRMax"
        )
        ; ========== 通用键名映射（与设备无关） ==========
        ; JoyN = 按物理位置编号的通用键名（与设备无关）
        ; Joy1=下, Joy2=右, Joy3=左, Joy4=上
        this.JoyToDispMap := Map(
            "Joy1", Map("Xbox", "A", "PS5", "×"),
            "Joy2", Map("Xbox", "B", "PS5", "○"),
            "Joy3", Map("Xbox", "X", "PS5", "□"),
            "Joy4", Map("Xbox", "Y", "PS5", "△"),
            "Joy5", Map("Xbox", "LB", "PS5", "L1"),
            "Joy6", Map("Xbox", "RB", "PS5", "R1"),
            "Joy7", Map("Xbox", "LT", "PS5", "L2"),
            "Joy8", Map("Xbox", "RT", "PS5", "R2"),
            "Joy9", Map("Xbox", "LS", "PS5", "L3"),
            "Joy10", Map("Xbox", "RS", "PS5", "R3"),
            "Joy11", Map("Xbox", "Back", "PS5", "Crt"),
            "Joy12", Map("Xbox", "Start", "PS5", "Opt"),
            "Joy13", Map("Xbox", "XBOX", "PS5", "PS"),
            "Joy14", Map("Xbox", "Map", "PS5", "白板"),
            "AxisLXMin", Map("Xbox", "L←", "PS5", "L←"),
            "AxisLXMax", Map("Xbox", "L→", "PS5", "L→"),
            "AxisLYMin", Map("Xbox", "L↑", "PS5", "L↑"),
            "AxisLYMax", Map("Xbox", "L↓", "PS5", "L↓"),
            "AxisRXMin", Map("Xbox", "R←", "PS5", "R←"),
            "AxisRXMax", Map("Xbox", "R→", "PS5", "R→"),
            "AxisRYMin", Map("Xbox", "R↑", "PS5", "R↑"),
            "AxisRYMax", Map("Xbox", "R↓", "PS5", "R↓"),
            "AxisLT", Map("Xbox", "LT", "PS5", "L2"),
            "AxisRT", Map("Xbox", "RT", "PS5", "R2"),
            "DpadUp", Map("Xbox", "↑", "PS5", "↑"),
            "DpadDown", Map("Xbox", "↓", "PS5", "↓"),
            "DpadLeft", Map("Xbox", "←", "PS5", "←"),
            "DpadRight", Map("Xbox", "→", "PS5", "→")
        )
        ; 物理原始键名 → 通用键名（Xbox）
        this.PhysToXboxJoyMap := Map(
            "Joy1", "Joy1",
            "Joy2", "Joy2",
            "Joy3", "Joy3",
            "Joy4", "Joy4",
            "Joy5", "Joy5",
            "Joy6", "Joy6",
            "Joy7", "Joy11",
            "Joy8", "Joy12",
            "Joy9", "Joy9",
            "Joy10", "Joy10",
            "Joy13", "Joy13",
            "Joy14", "Joy14",
            "JoyZMin", "AxisLT",
            "JoyZMax", "AxisRT",
            "JoyPOV_0", "DpadUp",
            "JoyPOV_9000", "DpadRight",
            "JoyPOV_18000", "DpadDown",
            "JoyPOV_27000", "DpadLeft",
            "JoyXMin", "AxisLXMin",
            "JoyXMax", "AxisLXMax",
            "JoyYMin", "AxisLYMin",
            "JoyYMax", "AxisLYMax",
            "JoyUMin", "AxisRXMin",
            "JoyUMax", "AxisRXMax",
            "JoyRMin", "AxisRYMin",
            "JoyRMax", "AxisRYMax"
        )
        ; 物理原始键名 → 通用键名（PS5 蓝牙/DI）
        ; 按物理位置映射：Joy1=下, Joy2=右, Joy3=左, Joy4=上
        this.PhysToPS5JoyMap := Map(
            "Joy1", "Joy3",   ; □(左) → 左位置
            "Joy2", "Joy1",   ; ×(下) → 下位置
            "Joy3", "Joy2",   ; ○(右) → 右位置
            "Joy4", "Joy4",   ; △(上) → 上位置
            "Joy5", "Joy5",
            "Joy6", "Joy6",
            "Joy7", "Joy7",
            "Joy8", "Joy8",
            "Joy9", "Joy11",
            "Joy10", "Joy12",
            "Joy11", "Joy9",
            "Joy12", "Joy10",
            "Joy13", "Joy13",
            "Joy14", "Joy14",
            "JoyPOV_0", "DpadUp",
            "JoyPOV_9000", "DpadRight",
            "JoyPOV_18000", "DpadDown",
            "JoyPOV_27000", "DpadLeft",
            "JoyXMin", "AxisLXMin",
            "JoyXMax", "AxisLXMax",
            "JoyYMin", "AxisLYMin",
            "JoyYMax", "AxisLYMax",
            "JoyZMin", "AxisRXMin",
            "JoyZMax", "AxisRXMax",
            "JoyRMin", "AxisRYMin",
            "JoyRMax", "AxisRYMax",
            "JoyUMin", "AxisRT",
            "JoyUMax", "AxisRT",
            "JoyVMin", "AxisLT",
            "JoyVMax", "AxisLT"
        )
        ; 通用键名 → 物理原始键名（Xbox，用于执行/绑定）
        this.JoyToXboxPhysMap := Map(
            "Joy1", "Joy1",   "Joy2", "Joy2",   "Joy3", "Joy3",   "Joy4", "Joy4",
            "Joy5", "Joy5",   "Joy6", "Joy6",   "Joy7", "JoyZMin", "Joy8", "JoyZMax",
            "Joy9", "Joy9",   "Joy10", "Joy10",  "Joy11", "Joy7",  "Joy12", "Joy8",
            "Joy13", "Joy13", "Joy14", "Joy14",
            "AxisLT", "JoyZMin", "AxisRT", "JoyZMax",
            "AxisLXMin", "JoyXMin", "AxisLXMax", "JoyXMax",
            "AxisLYMin", "JoyYMin", "AxisLYMax", "JoyYMax",
            "AxisRXMin", "JoyUMin", "AxisRXMax", "JoyUMax",
            "AxisRYMin", "JoyRMin", "AxisRYMax", "JoyRMax",
            "DpadUp", "JoyPOV_0", "DpadDown", "JoyPOV_18000",
            "DpadLeft", "JoyPOV_27000", "DpadRight", "JoyPOV_9000"
        )
        ; 通用键名 → 物理原始键名（PS5，用于执行/绑定）
        this.JoyToPS5PhysMap := Map(
            "Joy1", "Joy2",   "Joy2", "Joy3",   "Joy3", "Joy1",   "Joy4", "Joy4",
            "Joy5", "Joy5",   "Joy6", "Joy6",   "Joy7", "Joy7",   "Joy8", "Joy8",
            "Joy9", "Joy11",  "Joy10", "Joy12", "Joy11", "Joy9",  "Joy12", "Joy10",
            "Joy13", "Joy13", "Joy14", "Joy14",
            "AxisLT", "JoyVMin", "AxisRT", "JoyUMin",
            "AxisLXMin", "JoyXMin", "AxisLXMax", "JoyXMax",
            "AxisLYMin", "JoyYMin", "AxisLYMax", "JoyYMax",
            "AxisRXMin", "JoyZMin", "AxisRXMax", "JoyZMax",
            "AxisRYMin", "JoyRMin", "AxisRYMax", "JoyRMax",
            "DpadUp", "JoyPOV_0", "DpadDown", "JoyPOV_18000",
            "DpadLeft", "JoyPOV_27000", "DpadRight", "JoyPOV_9000"
        )

        ; 手柄按键统一按 Xbox 友好键名存盘；显示时按当前类型（宏手柄类型/手柄类型）映射显示名
        this.JoyBtnDisplayMap := Map(
            "JoyA", Map("Xbox", "A", "PS5", "×"),
            "JoyB", Map("Xbox", "B", "PS5", "○"),
            "JoyX", Map("Xbox", "X", "PS5", "□"),
            "JoyY", Map("Xbox", "Y", "PS5", "△"),
            "JoyLB", Map("Xbox", "LB", "PS5", "L1"),
            "JoyRB", Map("Xbox", "RB", "PS5", "R1"),
            "JoyLT", Map("Xbox", "LT", "PS5", "L2"),
            "JoyRT", Map("Xbox", "RT", "PS5", "R2"),
            "JoyLS", Map("Xbox", "LS", "PS5", "L3"),
            "JoyRS", Map("Xbox", "RS", "PS5", "R3"),
            "JoyBack", Map("Xbox", "Back", "PS5", "Crt"),
            "JoyStart", Map("Xbox", "Start", "PS5", "Opt"),
            "JoyPad", Map("Xbox", "Map", "PS5", "白板"),
            "JoyHome", Map("Xbox", "XBOX", "PS5", "PS"),
            "JoyDpadUp", Map("Xbox", "上", "PS5", "上"),
            "JoyDpadDown", Map("Xbox", "下", "PS5", "下"),
            "JoyDpadLeft", Map("Xbox", "左", "PS5", "左"),
            "JoyDpadRight", Map("Xbox", "右", "PS5", "右")
        )
        ; 手柄按钮统一存盘的 Xbox 友好键名列表（显示时按类型映射；无 Xbox 对应项时直接存原名）
        this.JoyBtnKeys := ["JoyA", "JoyB", "JoyX", "JoyY", "JoyLB", "JoyRB", "JoyLT", "JoyRT",
            "JoyLS", "JoyRS", "JoyBack", "JoyStart", "JoyHome", "JoyPad"]
        this.JoyAhkToXboxMap := Map(
            "Joy1", "JoyA",
            "Joy2", "JoyB",
            "Joy3", "JoyX",
            "Joy4", "JoyY",
            "Joy5", "JoyLB",
            "Joy6", "JoyRB",
            "JoyZMin", "JoyLT",
            "JoyZMax", "JoyRT",
            "Joy9", "JoyLS",
            "Joy10", "JoyRS",
            "Joy7", "JoyBack",
            "Joy8", "JoyStart",
            "JoyPOV_0", "JoyDpadUp",
            "JoyPOV_9000", "JoyDpadRight",
            "JoyPOV_18000", "JoyDpadDown",
            "JoyPOV_27000", "JoyDpadLeft",
            "JoyXMin", "JoyAxisLXMin",
            "JoyXMax", "JoyAxisLXMax",
            "JoyYMin", "JoyAxisLYMin",
            "JoyYMax", "JoyAxisLYMax",
            "JoyUMin", "JoyAxisRXMin",
            "JoyUMax", "JoyAxisRXMax",
            "JoyRMin", "JoyAxisRYMin",
            "JoyRMax", "JoyAxisRYMax"
        )
        ; PS5 原生 DI（蓝牙/有线）：和 Xbox 映射不同
        ; JoyZ/R=右摇杆, JoyU=R2扳机, JoyV=L2扳机
        this.JoyAhkToPS5Map := Map(
            "Joy1", "JoyX",
            "Joy2", "JoyA",
            "Joy3", "JoyB",
            "Joy4", "JoyY",
            "Joy5", "JoyLB",
            "Joy6", "JoyRB",
            "Joy7", "JoyLT",
            "Joy8", "JoyRT",
            "Joy9", "JoyBack",
            "Joy10", "JoyStart",
            "Joy11", "JoyLS",
            "Joy12", "JoyRS",
            "Joy13", "JoyHome",
            "Joy14", "JoyPad",
            "JoyPOV_0", "JoyDpadUp",
            "JoyPOV_9000", "JoyDpadRight",
            "JoyPOV_18000", "JoyDpadDown",
            "JoyPOV_27000", "JoyDpadLeft",
            "JoyXMin", "JoyAxisLXMin",
            "JoyXMax", "JoyAxisLXMax",
            "JoyYMin", "JoyAxisLYMin",
            "JoyYMax", "JoyAxisLYMax",
            "JoyZMin", "JoyAxisRXMin",
            "JoyZMax", "JoyAxisRXMax",
            "JoyRMin", "JoyAxisRYMin",
            "JoyRMax", "JoyAxisRYMax",
            "JoyUMin", "JoyRT",
            "JoyUMax", "JoyRT",
            "JoyVMin", "JoyLT",
            "JoyVMax", "JoyLT"
        )
    }

    ; 物理原始键名 → 通用键名
    GetPhysToJoyMap() {
        joyType := MainSoftData.JoyType
        if (joyType == "DS4")
            return this.PhysToPS5JoyMap
        return this.PhysToXboxJoyMap
    }

    ; 通用键名 → 物理原始键名（用于执行/绑定）
    GetJoyToPhysMap() {
        joyType := MainSoftData.JoyType
        if (joyType == "DS4")
            return this.JoyToPS5PhysMap
        return this.JoyToXboxPhysMap
    }

    ; 通用键名 → 显示名
    GetJoyNDisplayName(btnKey) {
        joyType := MainSoftData.TriggerJoyType
        if (this.JoyToDispMap.Has(btnKey)) {
            labelMap := this.JoyToDispMap[btnKey]
            return labelMap.Has(joyType) ? labelMap[joyType] : labelMap["Xbox"]
        }
        return btnKey
    }

    ; 旧映射保留兼容
    GetJoyToAhkMap() {
        joyType := MainSoftData.JoyType
        if (joyType == "DS4")
            return this.JoyPS5ToAhkMap
        return this.JoyXboxToAhkMap
    }

    ; 通用键名 → 友好键名（宏指令按键段统一转换：按钮/摇杆/方向键/扳机）
    GetJoyFriendlyKey(keyName) {
        static genericToFriendly := Map(
            "Joy1", "JoyA", "Joy2", "JoyB", "Joy3", "JoyX", "Joy4", "JoyY",
            "Joy5", "JoyLB", "Joy6", "JoyRB", "Joy7", "JoyLT", "Joy8", "JoyRT",
            "Joy9", "JoyLS", "Joy10", "JoyRS", "Joy11", "JoyBack", "Joy12", "JoyStart",
            "Joy13", "JoyHome", "Joy14", "JoyPad",
            "AxisLXMin", "JoyAxisLXMin", "AxisLXMax", "JoyAxisLXMax",
            "AxisLYMin", "JoyAxisLYMin", "AxisLYMax", "JoyAxisLYMax",
            "AxisRXMin", "JoyAxisRXMin", "AxisRXMax", "JoyAxisRXMax",
            "AxisRYMin", "JoyAxisRYMin", "AxisRYMax", "JoyAxisRYMax",
            "AxisLT", "JoyLT", "AxisRT", "JoyRT",
            "DpadUp", "JoyDpadUp", "DpadDown", "JoyDpadDown",
            "DpadLeft", "JoyDpadLeft", "DpadRight", "JoyDpadRight")
        return genericToFriendly.Has(keyName) ? genericToFriendly[keyName] : keyName
    }

    ; 指令字符串中的通用键名 → 友好键名（兼容旧 GUI）
    CmdJoyNToJoyFriendly(cmdStr) {
        if (cmdStr == "")
            return cmdStr
        paramArr := StrSplit(cmdStr, "_")
        if (paramArr.Length >= 2)
            paramArr[2] := this.GetJoyFriendlyKey(paramArr[2])
        result := ""
        for i, p in paramArr {
            if (i > 1)
                result .= "_"
            result .= p
        }
        return result
    }

    ; 旧：录制时 AHK 原始键名 → 友好名
    GetAhkToJoyMap() {
        joyType := MainSoftData.JoyType
        if (joyType == "DS4")
            return this.JoyAhkToPS5Map
        return this.JoyAhkToXboxMap
    }

    GetJoyDisplayName(joyKey, joyType := "") {
        if (joyType == "")
            joyType := MainSoftData.TriggerJoyType
        displayMap := this.JoyBtnDisplayMap
        if (displayMap.Has(joyKey)) {
            labelMap := displayMap[joyKey]
            name := labelMap.Has(joyType) ? labelMap[joyType] : labelMap["Xbox"]
            if (name != "")
                return name
        }
        return joyKey
    }

    ; 触发键显示/解析所需的手柄键名列表（按钮键 + 方向键/摇杆固定键名）
    GetJoyTriggerKeyList() {
        keys := ["JoyDpadUp", "JoyDpadDown", "JoyDpadLeft", "JoyDpadRight",
            "JoyAxisLXMin", "JoyAxisLXMax", "JoyAxisLYMin", "JoyAxisLYMax",
            "JoyAxisRXMin", "JoyAxisRXMax", "JoyAxisRYMin", "JoyAxisRYMax"]
        for k in this.JoyBtnKeys
            keys.Push(k)
        return keys
    }

    ; 将触发键字符串中的Joy键名转换为显示名（跟随手柄类型 TriggerJoyType）
    FormatJoyTriggerKey(triggerKey) {
        if (triggerKey == "")
            return ""
        result := triggerKey
        joyType := (MainSoftData.TriggerJoyType == "PS5" || MainSoftData.TriggerJoyType == "Xbox")
            ? MainSoftData.TriggerJoyType : "Xbox"
        ; 按键名称按词边界替换，避免 JoyA 命中 JoyAxisLXMin
        for key in this.GetJoyTriggerKeyList() {
            displayName := this.GetJoyDisplayName(key, joyType)
            if (displayName == key)
                continue
            needle := "(?<![A-Za-z0-9_])" RegExReplace(key, "([\\.^$|?*+()\[\]{}])", "\$1") "(?![A-Za-z0-9_])"
            result := RegExReplace(result, needle, displayName)
        }
        return result
    }

    ; 将显示名还原为内部Joy键名（反向映射，跟随手柄类型 TriggerJoyType）
    ParseJoyTriggerKey(displayStr) {
        if (displayStr == "")
            return ""
        result := displayStr
        joyType := (MainSoftData.TriggerJoyType == "PS5" || MainSoftData.TriggerJoyType == "Xbox")
            ? MainSoftData.TriggerJoyType : "Xbox"
        for key in this.GetJoyTriggerKeyList() {
            displayName := this.GetJoyDisplayName(key, joyType)
            if (displayName == key || displayName == "")
                continue
            result := StrReplace(result, displayName, key, , , 1)
        }
        return result
    }

    ; 格式化宏指令字符串中的 Joy 键名为 🎮× 格式（只替换第二个 _ 段）
    ; 格式化宏指令字符串中的 通用键名 为 🎮显示名 格式（只替换第二个 _ 段）
    FormatCmdJoyDisplay(cmdStr) {
        if (cmdStr == "")
            return cmdStr
        if InStr(cmdStr, "🎮")
            return cmdStr
        paramArr := StrSplit(cmdStr, "_")
        if (paramArr.Length >= 2) {
            keyPart := paramArr[2]
            ; 通用 JoyN / 轴名
            if (RegExMatch(keyPart, "^(Joy\d+|JoyAxisL?[XYZ]M(in|ax)|JoyAxisR[XYZ]M(in|ax)|JoyDpad(Up|Down|Left|Right|None)|AxisLT|AxisRT|AxisL?[XYZ]M(in|ax)|AxisR[XYZ]M(in|ax)|Dpad(Up|Down|Left|Right))$")) {
                displayName := this.GetJoyNDisplayName(keyPart)
                if (displayName != "" && displayName != keyPart)
                    keyPart := "🎮" displayName
            }
            ; 友好键名 JoyA / JoyO / JoyL1 等（宏按键指令）
            else if (InStr(keyPart, "Joy") == 1) {
                keys := StrSplit(keyPart, "⎖")
                newPart := ""
                for i, k in keys {
                    if (i > 1)
                        newPart .= "⎖"
                    label := this.GetJoyDisplayName(k)
                    if (label != "" && label != k)
                        newPart .= "🎮" label
                    else
                        newPart .= k
                }
                keyPart := newPart
            }
            paramArr[2] := keyPart
        }
        result := ""
        for i, p in paramArr {
            if (i > 1)
                result .= "_"
            result .= p
        }
        return result
    }

    ; 从 🎮显示名 格式还原为键名（只还原第二个 _ 段）
    ParseCmdJoyDisplay(displayStr) {
        if (displayStr == "")
            return displayStr
        if !InStr(displayStr, "🎮")
            return displayStr
        paramArr := StrSplit(displayStr, "_")
        if (paramArr.Length >= 2 && InStr(paramArr[2], "🎮")) {
            keyPart := paramArr[2]
            global MainSoftData
            joyType := MainSoftData.TriggerJoyType
            ; 优先：按钮友好键名（JoyA 等，按当前 JoyType 显示）
            for btnKey in this.JoyBtnKeys {
                disp := this.GetJoyDisplayName(btnKey, joyType)
                if (disp == "")
                    continue
                ; 词边界匹配，避免 "B" 命中 "Back"、"X" 命中 "XBOX" 等前缀误匹配
                needle := "🎮" RegExReplace(disp, "([\\.^$|?*+()\[\]{}])", "\$1") "(?![A-Za-z0-9])"
                if (RegExMatch(keyPart, needle)) {
                    keyPart := btnKey
                    break
                }
            }
            ; 回退：通用 JoyN 显示名
            if (InStr(keyPart, "🎮")) {
                for btnKey, labelMap in this.JoyToDispMap {
                    disp := labelMap.Has(joyType) ? labelMap[joyType] : labelMap["Xbox"]
                    if (disp == "")
                        continue
                    needle := "🎮" RegExReplace(disp, "([\\.^$|?*+()\[\]{}])", "\$1") "(?![A-Za-z0-9])"
                    if (RegExMatch(keyPart, needle)) {
                        keyPart := btnKey
                        break
                    }
                }
            }
            paramArr[2] := keyPart
        }
        result := ""
        for i, p in paramArr {
            if (i > 1)
                result .= "_"
            result .= p
        }
        return result
    }
}

class KeyboardData {
    __New() {
        this.NodeSerial := 0
        this.KeyName := ""
        this.StartTime := 0
        this.EndTime := 0
        this.StartPos := []
        this.EndPos := []
    }

    Span() {
        return this.EndTime - this.StartTime
    }
}

class RecordNodeData {
    __New() {
        this.StartTime := 0
        this.EndTime := 0
    }

    Span() {
        return this.EndTime - this.StartTime
    }
}

class MoveData {
    __New() {
        this.EndPosX := 0
        this.EndPosY := 0
        this.NodeSerial := 0
    }
}

class SearchData {
    __New() {
        this.SerialStr := ""
        this.ConfigName := Format("{}*{}_{}", A_ScreenWidth, A_ScreenHeight, GetLang("全屏"))
        this.SearchType := 1        ;1屏幕图片  2屏幕颜色  3屏幕文本 4窗口图片 5窗口颜色 6窗口文本
        this.WinInfo := ""          ;窗口信息
        this.SearchColor := "FFFFFF"
        this.SearchText := GetLang("检索文本")
        this.SearchImagePath := ""
        this.Similar := 90 ; 图片搜索模糊匹配度100  - 50
        this.OCRType := 1   ;1中文  2英文
        this.SearchImageType := 1 ; 1 opencv 2 rmt
        this.StartPosX := 0
        this.StartPosY := 0
        this.EndPosX := A_ScreenWidth
        this.EndPosY := A_ScreenHeight
        this.SearchCount := 1
        this.SearchInterval := 1000
        this.MouseActionType := 2   ;   1无动作 2移动到目标 3移动到目标点击
        this.Speed := 90
        this.ClickCount := 1
        this.ConfigArr := []    ;配置数组，不同的分辨率
        this.TrueMacro := ""
        this.FalseMacro := ""
        this.ResultToggle := 0
        this.ResultSaveName := GetLang("搜索结果")
        this.TrueValue := 1
        this.FalseValue := 0
        this.CoordToogle := 0
        this.CoordXName := GetLang("坐标X")
        this.CoordYName := GetLang("坐标Y")
        ; §15.1 多目标：-1=所有目标都满足，>=1=自定义满足个数
        this.SatisfyCount := -1
        ; §15.1 多目标数组（每项 = 单目标配置对象，字段同上方单目标字段）
        this.SearchTargetArr := []
    }

}

class ScreenShotData {
    __New() {
        this.SerialStr := ""
        this.ScreenShotType := 1        ;1屏幕抓图  2窗口抓图
        this.WinInfo := ""              ;窗口信息（窗口抓图时使用）
        this.StartPosX := 0
        this.StartPosY := 0
        this.EndPosX := A_ScreenWidth
        this.EndPosY := A_ScreenHeight
        this.NameType := 1              ;0默认（指令名+序号）  1固定名称
        this.FixedName := "Shot"            ;固定名称（NameType=1时使用）
        this.SavePath := ""             ;保存路径（默认为Temp_ScreenShot）
        this.ResultToggle := 0          ;是否保存结果到变量
        this.ResultSaveName := GetLang("图片路径")  ;结果变量名
    }

}

class CompareData {
    __New() {
        this.ToggleArr := [1, 0, 0, 0]
        this.NameArr := ["Var1", "Var2", "Var3", "Var4"]
        this.CompareTypeArr := [1, 1, 1, 1]  ;1大于 2大于等于 3等于 4小于等 5小于 6字符包含 7存在变量 8正则匹配
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4"]
        this.TrueControlType := "无"   ;流程控制：1无 2循环-跳过本轮 3循环-跳出 4分支-跳出
        this.FalseControlType := "无"   ;流程控制：1无 2循环-跳过本轮 3循环-跳出 4分支-跳出
        this.TrueMacro := ""
        this.FalseMacro := ""
        this.SaveToggle := 0
        this.SaveName := GetLang("结果")
        this.TrueValue := 1
        this.FalseValue := 0
        this.LogicalType := 1
    }
}

class CompareProData {
    __New() {
        this.VariNameArr := [["Var1"], ["Var2"]]
        this.CompareTypeArr := [[3], [3]]  ;1大于 2大于等于 3等于 4小于等于 5小于 6字符包含 7存在变量 8正则匹配（与 CompareData 一致）
        this.VariableArr := [["1"], ["2"]]
        this.LogicTypeArr := [1, 2]
        this.ControlTypeArr := ["无", "无"]
        this.MacroArr := ["按键_a_点击_100", "按键_b_点击_100"]
        this.DefaultControlType := "无"
        this.DefaultMacro := "按键_c_点击_100"
    }

    ;用于逻辑树展示
    static GetCondiStr(Data, itemIndex) {
        CommandStr := ""
        symbolStr := Data.LogicTypeArr[itemIndex] == 1 ? GetLang("且") : GetLang("或")
        CompareTypeStrArr := GetLangArr(["大于", "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"])

        loop Data.VariNameArr[itemIndex].Length {
            VariName := GetLang(Data.VariNameArr[itemIndex][A_Index])
            TypeStr := CompareTypeStrArr[Data.CompareTypeArr[itemIndex][A_Index]]
            Variable := GetLang(Data.VariableArr[itemIndex][A_Index])

            if (Data.CompareTypeArr[itemIndex][A_Index] != 7)
                CommandStr .= VariName " " TypeStr " " Variable " " symbolStr " "
            else
                CommandStr .= VariName " " TypeStr " " symbolStr " "
        }
        CommandStr := Trim(CommandStr, " ")
        CommandStr := Trim(CommandStr, symbolStr)
        CommandStr := Trim(CommandStr, " ")
        return CommandStr
    }
}

class MMProData {
    __New() {
        this.SerialStr := ""
        this.PosVarX := 100
        this.PosVarY := 100
        this.ActionType := 1          ;鼠标动作 1移动 2移动点击1次 3移动点击2次
        this.MouseMoveMode := 0      ;§20 移动模式 0=绝对移动 1=相对移动（旧值 2=游戏视角 已拆为「增量移动」指令，仅旧配置兼容执行）
        this.RefMode := 0            ;§20 坐标基准 0=屏幕 1=窗口（选窗口时配合 WinInfo）
        this.WinInfo := ""           ;§20 窗口信息（基准=窗口时的标题/类名等）
        this.Speed := 90           ;移动速度
    }
}

; §20 增量移动指令配置（原「移动Pro-游戏视角」拆分，mouse_event 相对位移）
class DeltaMoveData {
    __New() {
        this.SerialStr := ""
        this.DeltaX := 0            ;X 相对位移（支持 {变量}）
        this.DeltaY := 0            ;Y 相对位移（支持 {变量}）
        ; 错误处理（影刀模式，阶段5）
        this.ErrMode := "stop"
        this.ErrRetryCount := 3
        this.ErrRetryInterval := 500
    }
}

class RunData {
    __New() {
        this.SerialStr := ""
        this.Target := ""
        this.Mode := 1
        this.Option := 1
    }
}

class OutputData {
    __New() {
        this.SerialStr := ""
        this.Text := GetLang("将要输出的文本")
        this.OutputType := "发送内容"   ;sendtest  粘贴   粘贴
        this.VariableName := "Data"         ;字符变量时的变量名（默认 Data）
    }
}

class FileIOData {
    __New() {
        this.SerialStr := ""
        this.OperType := "读取Excel"    ;1读取Excel 2写入Excel 3读取文本文件 4写入文本文件
        this.Encoding := "UTF-8"        ;文本文件编码格式
        this.FilePath := ""

        ;读取Excel      "单元格", "指定行", "指定列", "指定区域-行", "指定区域-列"
        ;写入Excel      单元格    行号自增  列号自增  指定区域-行    指定区域-列
        ;读取文本文件   读取全部内容, 逐行读取, 指定行
        ;写入文本文件   "覆盖写入", "追加写入", "追加写入-行", "指定行", "行号自增"
        this.OperMode := "单元格"
        this.NameOrSerial := 1
        this.RowVar := 1
        this.ColVar := 1
        this.RowEndVar := 1
        this.ColEndVar := 1

        this.TextRowVar := 1        ;文本文件指令行号

        this.Content := "写入的内容" ;单元格时的写入内容
        this.ArrName := "Arr"       ;写入区域时的数组

        this.SaveType := "变量"     ;保存类型  变量或数组
        this.SaveName := "Data"
    }
}

class SubMacroData {
    __New() {
        this.SerialStr := ""
        this.MacroType := "按键宏"
        this.CallType := "触发"
        this.InsertCount := 1
        this.Index := 1
        this.MacroSerial := "-1"
    }
}

class LoopData {
    __New() {
        this.SerialStr := ""
        this.LoopCount := 10    ;循环次数
        this.CondiType := 1     ;条件类型 1：无 2：退出条件 3：继续条件
        this.LogicType := 1     ;逻辑关系  1：且    2：或
        this.ToggleArr := [1, 0, 0, 0]
        this.NameArr := ["Var1", "Var2", "Var3", "Var4"]
        this.CompareTypeArr := [1, 1, 1, 1]  ;1大于 2大于等于 3等于 4小于等 5小于 6字符包含 7存在变量
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4"]
        this.LoopBody := ""     ;循环体
    }

    ;用于逻辑树展示
    static GetCondiStr(Data) {
        CommandStr := ""
        symbolStr := Data.LogicType == 1 ? GetLang("且") : GetLang("或")
        CompareTypeStrArr := GetLangArr(["大于", "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"])

        loop 4 {
            if (!Data.ToggleArr[A_Index])
                continue

            VariName := GetLang(Data.NameArr[A_Index])
            TypeStr := CompareTypeStrArr[Data.CompareTypeArr[A_Index]]
            Variable := GetLang(Data.VariableArr[A_Index])
            if (Data.CompareTypeArr[A_Index] != 7)
                CommandStr .= VariName " " TypeStr " " Variable " " symbolStr " "
            else
                CommandStr .= VariName " " TypeStr " " symbolStr " "
        }

        CommandStr := Trim(CommandStr, " ")
        CommandStr := Trim(CommandStr, symbolStr)
        CommandStr := Trim(CommandStr, " ")
        return CommandStr
    }
}

class VariableData {
    __New() {
        this.SerialStr := ""
        this.IsIgnoreExist := 0
        this.ToggleArr := [1, 0, 0, 0]
        this.OperaTypeArr := [1, 1, 1, 1]   ;1赋值 2随机 3字符 4删除
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4"]
        this.CopyVariableArr := ["1", "0", "0", "0"]
        this.MinVariableArr := ["0", "0", "0", "0"]
        this.MaxVariableArr := ["10", "10", "10", "10"]
    }
}

class ExVariableData {
    __New() {
        this.SerialStr := ""
        this.IsIgnoreExist := 0
        this.ToggleArr := [1, 0, 0, 0, 0, 0]
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4", "Var5", "Var6"]
        this.ExtractStr := ""
        this.ExtractType := 1
        this.WinInfo := ""
        this.OCRType := 1
        this.StartPosX := 0
        this.StartPosY := 0
        this.EndPosX := A_ScreenWidth
        this.EndPosY := A_ScreenHeight
        this.SearchCount := 1
        this.SearchInterval := 1000
    }
}

class OperationData {
    __New() {
        this.SerialStr := ""
        this.ToggleArr := [1, 0, 0, 0]
        this.UpdateNameArr := ["Var1", "Var2", "Var3", "Var4"]
        this.ExpressionArr := ["", "", "", ""]    ;完整表达式字符串（用于支持括号和整体编辑）
    }
}

class BGMouseData {
    __New() {
        this.SerialStr := ""
        this.TargetTitle := ""
        this.OperateType := 1 ;点击 双击 按下 松开
        this.MouseType := 1 ;左键 中键 右键
        this.PosVarX := 100
        this.PosVarY := 100
        this.ScrollV := 1 ;水平滚动
        this.ScrollH := 0 ; 垂直滚动
        this.ClickTime := 50 ;点击时间跨度
    }
}

class BGKeyData {
    __New() {
        this.SerialStr := ""
        this.FrontStr := ""
        this.KeyArr := []
        this.Type := 1  ;1按下 2松开 3点击
        this.ClickTime := 100
        this.ClickCount := 1
        this.ClickInterval := 100
    }
}

class TimingData {
    __New() {
        this.SerialStr := ""
        this.StartStamp := DateDiff(A_Now, "19700101000000", "Seconds")  ; Unix timestamp
        this.EndStamp := 0                                                 ; 0 = no end, omitted in JSON
        this.Type := 1  ;1单次 2软件启动时 3自定义
        this.CustomInterval := "10"  ; only relevant when Type == 3
        this.CustomUnit := 2         ; 1:秒 2:分钟 3:小時 4:天 5:週 6:月
    }
}

; §16 等待指令：19 种「检测间隔+轮询」场景
class WaitData {
    __New() {
        this.SerialStr := ""
        ; 1变量值 2按键按下 3按键松开 4屏幕变化 5鼠标移动 6鼠标停止 7剪切板变化
        ; 8进程存在 9进程关闭 10窗口存在 11窗口激活 12窗口屏幕变化 13窗口大小变化
        ; 14窗口关闭 15窗口最小化 16文件存在 17文件删除 18文件变化 19日期
        this.WaitType := 1
        this.Interval := 500        ; 检测间隔（毫秒）
        this.Param1 := ""           ; 主参数：变量名/按键名/进程名/窗口信息/文件路径/日期值
        this.Param2 := ""           ; 次参数：期望值 / 日期单位（分钟|小时|天|具体时间|时间变量）
        this.Param3 := ""
        this.StartPosX := 0         ; 范围（屏幕/窗口变化类）
        this.StartPosY := 0
        this.EndPosX := A_ScreenWidth
        this.EndPosY := A_ScreenHeight
    }
}

class ArrayData {
    __New() {
        this.SerialStr := ""
        this.IsIgnoreExist := 0
        this.Type := "创建"
        this.Name := "Arr"
        this.InitArr := [1, 2, 3, 4, 5, 6, 7, 8, 9]
        this.MainIndex := 0
        this.ArgsIndex := 1
        this.ArgsType := "变量或值"
        this.ArgsName := "Var1"
        this.SaveType := "变量"
        this.SaveName := "Data"
    }
}

class RMTCMDData {
    __New() {
        this.SerialStr := ""
        this.Category := "全部"   ; 指令类别（全部/键鼠/菜单等）
        this.CmdStr := "截图"     ; 具体指令（截图/自由贴/显示菜单等）
        this.MenuIndex := 1       ; 显示菜单时的菜单序号
        ; §2 禁用模块/取消禁用模块 参数：目标表符号 + 目标模块路径身份（FoldID，如 Normal.Module1）
        this.TableSymbol := ""    ; 目标表符号（Normal/String/Menu/UI/Voice/Timing/SubMacro/Replace）
        this.FoldID := ""         ; 目标模块路径身份
        this.OperateType := 1 ; 旧字段兼容：1截图 2截图中提取文本 3自由贴 4开启指令显示 5关闭指令显示 6启用键鼠 7禁用键鼠 8休眠 9终止所有宏 10重载
        ; 错误处理（影刀模式，阶段5）
        this.ErrMode := "stop"
        this.ErrRetryCount := 3
        this.ErrRetryInterval := 500
    }
}

; 间隔指令配置（阶段5：纯文本指令迁移到配置文件模式）
class IntervalData {
    __New() {
        this.SerialStr := ""
        this.Type := 1            ; 1固定  2随机
        this.Time1 := "500"       ; 时间1（固定时为唯一时间）
        this.Time2 := "1000"      ; 时间2（随机范围上界）
        ; 错误处理（影刀模式，阶段5）
        this.ErrMode := "stop"    ; stop/ignore/retry
        this.ErrRetryCount := 3
        this.ErrRetryInterval := 500
    }
}

; 移动指令配置（阶段5：纯文本指令迁移到配置文件模式）
class MoveDataConfig {
    __New() {
        this.SerialStr := ""
        this.PosX := 0
        this.PosY := 0
        this.Speed := 90          ; 界面速度 0~100
        this.MoveMode := 0
        ; 错误处理（影刀模式，阶段5）
        this.ErrMode := "stop"
        this.ErrRetryCount := 3
        this.ErrRetryInterval := 500
    }
}

; 按键指令配置（阶段5：纯文本指令迁移到配置文件模式）
class KeyDataConfig {
    __New() {
        this.SerialStr := ""
        this.KeyName := ""        ; 按键名（含 Joy*/Axis 等）
        this.KeyType := 3         ; 1按下 2松开 3点击
        this.HoldTime := 100      ; 点击时长(ms)
        this.Count := 1           ; 点击次数
        this.IntervalTime := 0    ; 每次间隔(ms)
        ; 错误处理（影刀模式，阶段5）
        this.ErrMode := "stop"
        this.ErrRetryCount := 3
        this.ErrRetryInterval := 500
    }
}

class TextOpsData {
    __New() {
        this.SerialStr := ""
        this.Type := "文本分割" ; 1: 文本分割 2: 文本替换
        this.Name := "TextVar" ; 文本来源变量名
        this.ArgsType := "全部大写" ;参数类型
        this.ArgsName := ","        ;参数变量名或文本
        this.Search := "" ; 查找文本
        this.Replace := "" ; 替换文本
        this.MatchType := "普通文本"
        this.SaveType := "变量"     ;保存类型  变量或数组
        this.SaveName := "Data"     ;保存的变量名或数组名
    }
}

class MouseWinData {
    __New() {
        this.WinId := ""
        this.WinTitle := ""
        this.WinClass := ""
        this.WinProcess := ""
        this.HasError := false
    }

    UpdateInfo() {
        this.HasError := false
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            this.WinId := winId
            this.WinTitle := WinGetTitle(winId)
            this.WinClass := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                this.WinProcess := ProcessGetName(WinPID)
            }
            catch {
                this.WinProcess := ""
            }
        }
        catch as e {
            this.HasError := true
        }
    }

    CheckIfMatch(FrontInfoStr, isUpdate := false) {
        if (isUpdate)
            this.UpdateInfo()

        if (FrontInfoStr == "" || this.HasError)
            return false

        if (InStr(FrontInfoStr, "❖")) {
            FrontInfoStr := StrReplace(FrontInfoStr, "❖")
            hwndList := StrSplit(FrontInfoStr, "|")
            for index, hwnd in hwndList {
                if (this.WinId == hwnd)
                    return true
            }
            return false
        }

        infoArr := StrSplit(FrontInfoStr, "⎖")
        if (infoArr.Length != 3)
            return false

        title := infoArr[1]
        className := infoArr[2]
        process := infoArr[3]

        if (title != "" && !InStr(this.WinTitle, title, "Off"))
            return false

        if (className != "" && className != this.WinClass)
            return false

        if (process != "" && process != this.WinProcess)
            return false

        return true
    }
}

class SerialData {
    __New(Str) {
        this.Str := Str
        this.NumMap := Map()
        this.CurNum := 1
    }

    Refresh() {
        if (this.NumMap.Has(this.CurNum)) {
            this.NumMap.Delete(this.CurNum)
            this.CurNum++
            this.Refresh()
        }
    }
}

class InputData {
    __New() {
        this.SerialStr := ""
        this.Type := "弹窗"                 ;弹窗 状态 继续 继续&取消
        this.PauseType := "暂停当前宏"      ;交互时：不暂停 暂停当前宏  暂停所有宏
        this.CancelType := "终止当前宏"     ;取消时  终止当前宏  终止所有宏
        this.SaveName := "Data"             ;保存的变量名或数组名
    }
}

class WindowManageData {
    __New() {
        this.SerialStr := ""                 ;类型尽量使用中文 当做枚举使用  程序中有语义、也可以随时调整顺序
        this.ActionType := "激活窗口"        ;1激活窗口 2最大化窗口 3最小化窗口 4还原窗口 5关闭窗口 6移动窗口 7调整大小 8置顶窗口 9取消置顶 10修改标题 11修改透明度 12开启鼠标穿透 13关闭鼠标穿透
        this.SearchValue := ""              ;查找值（格式：标题⎖类名⎖进程名，空表示未选择）
        this.PosX := 0                      ;移动窗口X坐标（移动窗口时使用）
        this.PosY := 0                      ;移动窗口Y坐标（移动窗口时使用）
        this.Width := 0                     ;窗口宽度（调整大小时使用）
        this.Height := 0                    ;窗口高度（调整大小时使用）
        this.NewTitle := ""                 ;新标题（修改标题时使用）
        this.Transparency := "80%"           ;透明度值 0-100（修改透明度时使用，80表示80%不透明度）
    }
}

class KeyCheckData {
    __New() {
        this.SerialStr := ""
        this.KeyArr := []                   ;检测的按键数组
        this.CheckType := 1                 ;1同时按下 2有一个按下
        this.StateType := 1                 ;1物理状态 2逻辑状态
        this.VarName := ""                  ;变量名
    }
}

class CommentData {
    __New() {
        this.SerialStr := ""
        this.Content := GetLang("请输入注释内容")
    }
}

class MsgType {
    static TASK := 1    ;主线程 派发任务给 Worker
    static FINISH := 2  ;Worker 告知 主线程 任务结束
    static EVENT := 3   ;双向广播事件 例如Worker修改变量值后 告知主线程 主线程收到后 广播所有人
}

class MacroGraphNode{
    __New() {
        this.SerialStr := ""
        this.CurCMD := "间隔_50"                   ;当前节点指令
        this.NextNodeArr := []                     ;下一个节点指令数组（后继节点的 SerialStr）
        this.X := 0                                ;图形编辑器中节点的逻辑坐标X
        this.Y := 0                                ;图形编辑器中节点的逻辑坐标Y
        this.Folded := 0                           ;搜索等含分支的节点：是否折叠隐藏分支节点（0展开 1折叠）
        ;搜索类节点展开态布局信息（""=未设置，使用默认计算值）：
        this.TrueBranchDX := ""                    ;真分支节点相对本节点的X偏移
        this.TrueBranchDY := ""                    ;真分支节点相对本节点的Y偏移
        this.FalseBranchDX := ""                   ;假分支节点相对本节点的X偏移
        this.FalseBranchDY := ""                   ;假分支节点相对本节点的Y偏移
        this.ExpandShift := ""                     ;展开时为腾出分支空间对后继子树施加的横向位移（用于收起时精确还原）
        this.SuccDX := ""                          ;展开时「最近后继(下一个)节点」相对本节点的X偏移（收起→展开时按此精确还原后继位置）
        this.SuccDY := ""                          ;展开时「最近后继(下一个)节点」相对本节点的Y偏移
        this.FoldSuccDX := ""                      ;收起时「最近后继」相对本节点的X偏移（展开→收起时按此还原）
        this.FoldSuccDY := ""                      ;收起时「最近后继」相对本节点的Y偏移
        this.ProBranchOff := ""                   ;如果Pro：各分支相对偏移 "dx,dy;dx,dy;..."（与分支索引一一对应）
    }
}

class MacroGraphStartNode{
    __New() {
        this.SerialStr := ""
        this.NodeArr := []                          ;下一个节点指令数组（后续MacroGraphNode节点的 SerialStr）
        this.EmptyNode := []                        ;图形编辑器中空节点数组（没有前置节点MacroGraphNode节点的 SerialStr）
        this.X := 0                                ;图形编辑器中节点的逻辑坐标X
        this.Y := 0                                ;图形编辑器中节点的逻辑坐标Y
    }
}

; 预声明全局变量，实际赋值在 Main/GlobalUtil.ahk 中
; (DataClass.ahk 在 include 链中最先加载，需在此声明以消除 #Warn)
global MainSoftData

; MyMainWin 预声明（实际赋值在 Main/MainWindowXaml.ahk:1084）
; 消除 MacroUtil/RMTUtil/BindUtil 等先于 MainWindowXaml 解析的函数内
; global MyMainWin 声明触发的编译期 #Warn UseUnsetGlobal 警告
global MyMainWin