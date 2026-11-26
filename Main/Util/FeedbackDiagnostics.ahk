#Requires AutoHotkey v2.0

; 反馈上下文：只在内存保留最近十步，不读取控件值、窗口标题或玩家命名。
class FeedbackDiagnostics {
    static Steps := []
    static SettingNames := Map(
        "CmbFont", "软件字体",
        "ChkBootStart", "开机自启",
        "ChkAdminStart", "管理员启动",
        "ChkDataReport", "在线功能",
        "CmbLang", "语言",
        "CmbPreferredEditor", "首选编辑器",
        "ChkModalSubGui", "模态子窗口",
        "CmbScreenShot", "截图工具",
        "CmbOCRType", "OCR类型",
        "CmbExcelBackend", "Excel",
        "CmbSearchImage", "图片识别模型",
        "ChkSearchImageAdaptive", "图片识别自适应",
        "EditMutiThreadNum", "多线程数",
        "EditTranslateTimeout", "翻译超时(ms)",
        "EditNetPort", "网络宏端口",
        "CmbRemarkAuto", "指令备注",
        "CmbTriggerJoyType", "手柄映射",
        "CmbJoyType", "宏手柄类型",
        "ChkForeground", "仅前台运行宏",
        "ChkAutoLoosen", "自动松开修饰键",
        "ChkContinuous", "连续触发",
        "CmbMacroStop", "宏终止方式",
        "CmbKeyDownDown", "重复按下行为",
        "ChkNoVariable", "无变量提醒",
        "EditHoldFloat", "点击时间浮动",
        "EditPreIntervalFloat", "每次间隔浮动",
        "EditIntervalFloat", "间隔指令浮动",
        "EditCoordXFloat", "坐标X浮动",
        "EditCoordYFloat", "坐标Y浮动",
        "ShowBorderCon", "录制显示边框",
        "HoldMutiCon", "长按多次录制",
        "AutoLoosenCon", "结束自动添加按键松开",
        "KeyboardTogCon", "键盘录制",
        "MouseTogCon", "鼠标录制",
        "MouseTrailModeCon", "鼠标轨迹",
        "MouseTrailSpeedCon", "速度 (0~100)",
        "JoyTogCon", "手柄录制",
        "JoyIntervalCon", "检测间隔 (ms)",
        "ChkCMDTip", "启用指令显示",
        "CmdTipPosXCon", "显示位置 X",
        "CmdTipPosYCon", "显示位置 Y",
        "CmdTipWidthCon", "显示宽度",
        "CmdTipHeightCon", "显示高度",
        "CmdTipFontCon", "字体大小",
        "CmdTipAlphaCon", "背景透明度",
        "CmdTipLogFileCon", "输出到文件",
        "ChkLogWarnBubble", "警告气泡",
        "ChkLogErrorBadge", "错误中心",
        "CmdTipAutoClearCon", "自动清理时间",
        "WheelFixedPosCon", "固定位置",
        "WheelShowTooltipCon", "显示扇区名称提示",
        "WheelSelectModeCon", "选择模式",
        "WheelScaleCon", "轮盘大小",
        "CountDownStyleCon", "样式",
        "CountDownPadCon", "补零",
        "CountDownAlphaCon", "透明度",
        "CountDownFontCon", "字体大小",
        "UIPanelBtnWidthCon", "按钮宽度",
        "UIPanelBtnHeightCon", "按钮高度",
        "UIPanelFontSizeCon", "字体大小",
        "UIPanelColsCon", "每行个数",
        "UIPanelShowOnActiveCon", "界面激活时显示",
        "UIPanelCustomFoldCon", "自定义面板",
        "ThemePresetCon", "选择主题",
        "AiProviderCon", "模型商",
        "AiAccessCon", "写入权限",
        "AiApprovalCon", "指令审批")
    static WindowNames := Map(
        "MainWin", "主", "MacroEditGui", "宏指令编辑", "MacroGraphGui", "宏流程图",
        "SettingMgrGui", "配置管理", "MacroSettingGui", "宏设置", "TriggerKeyGui", "触发按键",
        "TriggerStrGui", "触发字串", "TimingGui", "定时设置", "GestureGui", "手势设置",
        "KeyGui", "按键编辑", "BGKeyGui", "后台按键", "BGMouseGui", "后台鼠标",
        "MouseMoveGui", "鼠标移动", "MMProGui", "鼠标移动Pro", "DeltaMoveGui", "相对移动",
        "CompareGui", "如果编辑", "CompareProGui", "如果Pro", "CompareProEditItemGui", "条件编辑",
        "LoopGui", "循环编辑", "WaitGui", "等待编辑", "IntervalGui", "间隔编辑",
        "SearchGui", "搜索编辑", "SearchProGui", "搜索Pro", "SearchAllGui", "搜索All",
        "SearchComboGui", "搜索Combo", "VariableGui", "变量编辑", "ArrayGui", "数组编辑",
        "OperationGui", "运算编辑", "OperationSubGui", "运算子项", "InputGui", "输入编辑",
        "OutputGui", "输出编辑", "FileIOGui", "文件读写", "BrowserGui", "浏览器编辑",
        "WindowControlGui", "窗口操作", "ControlInfoGui", "控件信息", "ControlOperationGui", "控件操作",
        "ClassifierCommandGui", "指令编辑",
        "CommentGui", "备注编辑", "HttpRequestGui", "网络请求", "RunProGui", "运行Pro",
        "AiDecisionGui", "AI判断", "AiSettingGui", "AI设置", "AiHistoryGui", "AI历史",
        "ThemeSettingGui", "主题设置", "HotkeySettingGui", "快捷键设置", "EditHotkeyGui", "快捷键编辑",
        "MenuWheelGlobalSettingGui", "轮盘设置", "MenuWheelGui", "菜单轮", "MenuMacroSettingGui", "轮盘宏设置",
        "UIMacroGui", "自定义界面", "UIMacroDesignerGui", "界面设计", "UIMacroSettingGui", "界面宏设置",
        "ShareCenterGui", "共享中心", "ShareUploadGui", "共享上传", "ConfigMergeGui", "配置合并",
        "LogCenterGui", "日志中心", "LogSettingGui", "日志设置", "DownloadManagerGui", "下载管理",
        "VarListenGui", "变量监听", "TargetGui", "目标选择", "ColorPanelGui", "颜色选择",
        "FreePasteGui", "自由粘贴", "ReplaceKeyGui", "按键替换", "RightClickMenuSettingGui", "右键菜单设置",
        "ToolRecordSettingGui", "录制设置", "UseExplainGui", "使用说明", "CMDTipSettingGui", "指令提示设置",
        "ExVariableGui", "变量提取", "ExVariableEditGui", "提取内容编辑", "CharVarEditGui", "文本构造",
        "JoyGui", "手柄编辑", "JoyCheckGui", "手柄判断", "KeyCheckGui", "按键判断",
        "BrowserKeyPickerGui", "浏览器按键", "ImageProcessGui", "图像处理", "FrontInfoGui", "前台信息",
        "TableMgrGui", "页签管理", "VoiceGui", "语音设置", "SttGui", "语音识别", "TimeGui", "时间编辑",
        "AgreementGui", "用户协议", "CustomInputGui", "输入交互", "CustomMsgBoxGui", "消息提示",
        "InputBtnXamlGui", "交互按钮", "ErrorMsgBoxGui", "", "FeedbackGui", "")
    static ControlNames := Map(
        "BtnOk", "确定", "BtnCancel", "取消", "BtnSave", "保存", "BtnApply", "应用",
        "BtnClose", "关闭", "BtnClosePanel", "关闭", "BtnWinClose", "关闭",
        "BtnMinimize", "最小化", "BtnMaximize", "最大化", "BtnPin", "置顶",
        "BtnConfig", "配置管理", "BtnSuspend", "禁用宏", "BtnSuspendActive", "禁用宏",
        "BtnPause", "暂停宏", "BtnPauseActive", "暂停宏", "BtnKill", "终止所有宏",
        "BtnReload", "重载", "BtnHelp", "帮助", "BtnAdd", "新增", "BtnDelete", "删除",
        "BtnCopy", "复制", "BtnPaste", "粘贴", "BtnEdit", "编辑", "BtnTest", "测试",
        "BtnRun", "运行", "BtnStop", "停止", "BtnRecord", "录制", "BtnImport", "导入",
        "BtnExport", "导出", "BtnClear", "清空", "BtnSearch", "搜索", "BtnBrowse", "浏览",
        "BtnUp", "上移", "BtnDown", "下移", "BtnUndo", "撤销", "BtnRedo", "重做",
        "BtnToggleHotkeyHint", "快捷键提示", "StatusDownloads", "下载管理", "StatusNotifications", "通知",
        "TypeCombo", "类型", "ModeCombo", "模式", "ActionCombo", "动作", "CompareCombo", "比较方式",
        "CbType", "类型", "CbMode", "模式", "CbAction", "动作", "CheckDebug", "调试",
        "TabControl", "页签", "EditMode", "编辑模式",
        "BtnSure", "确定", "BtnConfirm", "确定", "Confirm", "确定", "Cancel", "取消", "Reset", "重置",
        "BtnRevert", "恢复默认", "BtnCmdF1", "指令说明", "BtnTypeHelp", "类型说明",
        "BtnTrueEdit", "真分支编辑", "BtnFalseEdit", "假分支编辑", "BtnAddCondi", "添加条件",
        "BtnEditMacro", "编辑宏", "BtnWinEdit", "窗口编辑", "BtnPreviewArea", "区域预览",
        "ImageShotBtn", "截图", "ImageSelectBtn", "选择图片", "BtnEditFoundMacro", "找到分支编辑",
        "BtnEditUnFoundMacro", "未找到分支编辑", "BtnSelectFile", "选择文件", "BtnContentEdit", "内容编辑",
        "BtnInitEdit", "初始值编辑", "BtnInitOk", "确定", "BtnPick", "拾取", "BtnPickSelector", "拾取选择器",
        "BtnPickKey", "拾取按键", "BtnArgumentBuilder", "文本构造", "BtnSelectorDetails", "选择器详情",
        "BtnEditJsCode", "脚本编辑", "BtnAddWaitCondition", "添加等待条件", "BtnNewChat", "新建对话",
        "BtnRefreshModels", "刷新模型", "BtnOpenDownloadFolder", "打开下载目录", "BtnExtractEdit", "提取内容编辑",
        "KeyTypeCon", "按键类型", "MouseTypeCombo", "鼠标类型", "OperateTypeCombo", "操作类型",
        "OperTypeCombo", "操作类型", "OperModeCombo", "操作模式", "SearchTypeCon", "搜索类型",
        "ArgsTypeCon", "参数类型", "SaveTypeCon", "保存类型", "VarTypeCombo", "变量类型",
        "ExtractTypeCombo", "提取类型", "WinInfoCon", "窗口信息", "WaitType", "等待类型",
        "ClickType", "点击类型", "ActionGroup", "动作分类", "ActionType", "动作类型",
        "CmbAiProvider", "AI服务", "AutoClearCon", "自动清空", "LogToFileCon", "日志写入文件",
        "RemarkCon", "备注", "HoldTimeCon", "长按时间", "KeyCountCon", "点击次数", "PerIntervalCon", "每次间隔",
        "TimeVarCon1", "时间下限", "TimeVarCon2", "时间上限", "TimeWaitOutsideCon", "等待时间",
        "PosXCon", "X坐标", "PosYCon", "Y坐标", "SpeedCon", "移动速度", "MouseMoveModeCombo", "移动模式",
        "X", "X坐标", "Y", "Y坐标", "DX", "X偏移", "DY", "Y偏移", "Speed", "速度", "Time", "时间",
        "Key", "按键", "Count", "次数", "Interval", "间隔", "Value", "变量值", "Name", "变量名",
        "TextCon", "文本", "ImageCon", "图片", "HexColorCon", "颜色", "MouseActionTypeCon", "鼠标动作",
        "TrueMacroCon", "找到分支", "FalseMacroCon", "未找到分支", "CommandStrCon", "指令文本",
        "DateValCon", "日期", "DateUnitCon", "时间单位", "ArgsNameCon", "变量名", "ArgsValueCon", "变量值",
        "MinCon", "最小值", "MaxCon", "最大值", "VarNameCon", "变量名", "VarValueCon", "变量值",
        "Var", "变量名", "Copy", "变量值", "Min", "最小值", "Max", "最大值", "OpType", "赋值类型",
        "IfLeft", "左侧条件", "IfRight", "右侧条件", "TimeoutCon", "超时时间", "LoopCountCon", "循环次数")

    static Init() {
        XAMLHost.ActivityObserver := ObjBindMethod(this, "Observe")
        if (this.HasOwnProp("_moveHook"))
            return
        this._moveCallback := CallbackCreate(ObjBindMethod(this, "OnMoveEnd"), , 7)
        ; 系统移动结束事件：一次拖动记一步，也覆盖键盘移动；无需逐帧查询界面。
        this._moveHook := DllCall("user32\SetWinEventHook", "UInt", 0xA, "UInt", 0xB,
            "Ptr", 0, "Ptr", this._moveCallback, "UInt", 0, "UInt", 0, "UInt", 0, "Ptr")
        OnExit(ObjBindMethod(this, "Dispose"))
    }

    static Dispose(*) {
        if (this._moveHook)
            DllCall("user32\UnhookWinEvent", "Ptr", this._moveHook)
        CallbackFree(this._moveCallback)
    }

    static OnMoveEnd(hook, event, hwnd, objectId, childId, threadId, time) {
        for id, ui in XAMLHost._instances {
            if (ui.wpfHwnd == hwnd && ui.HasOwnProp("feedbackWindow") && ui.feedbackWindow != "") {
                try {
                    WinGetPos(&x, &y, , , "ahk_id " hwnd)
                    if (event == 0xA)
                        ui.feedbackMoveStart := [x, y]
                    else if (ui.HasOwnProp("feedbackMoveStart")) {
                        start := ui.DeleteProp("feedbackMoveStart")
                        if (x != start[1] || y != start[2])
                            this.Record("移动" ui.feedbackWindow "界面")
                    }
                }
                break
            }
        }
    }

    static Record(description, mergeKey := "") {
        wasCritical := A_IsCritical
        Critical("On")
        try {
            step := {time: FormatTime(, "HH:mm:ss"), text: description, key: mergeKey, tick: A_TickCount}
            n := this.Steps.Length
            ; 同一次拖动/同一控件的连续变化只占一步；普通重复点击仍独立记录。
            if (n && mergeKey != "" && this.Steps[n].key == mergeKey && A_TickCount - this.Steps[n].tick < 1000)
                this.Steps[n] := step
            else
                this.Steps.Push(step)
            while (this.Steps.Length > 10)
                this.Steps.RemoveAt(1)
        } finally {
            Critical(wasCritical)
        }
    }

    static StepsText() {
        text := ""
        for step in this.Steps.Clone()
            text .= (text == "" ? "" : "`n") step.time "  " step.text
        return text == "" ? "暂无操作记录" : text
    }

    static Capture(hwnd := 0) {
        return {environment: this.Environment(hwnd), steps: this.StepsText()}
    }

    static Report(context) {
        return "最近操作（最多10步）：`n" context.steps "`n`n环境信息：`n" context.environment
    }

    static Environment(hwnd := 0) {
        key := "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        product := "", release := ""
        try product := RegRead(key, "ProductName")
        try release := RegRead(key, "DisplayVersion")
        if (release == "")
            try release := RegRead(key, "ReleaseId")
        if (RegExMatch(product, "i)^Windows Server (\d+)", &m))
            system := "WinServer" m[1]
        else if (RegExMatch(A_OSVersion, "^10\.0\.(\d+)", &m))
            system := Integer(m[1]) >= 22000 ? "Win11" : "Win10"
        else if (RegExMatch(product, "i)^Windows (\d+(?:\.\d+)?)", &m))
            system := "Win" m[1]
        else
            system := "Win" A_OSVersion
        system .= (release != "" ? "_" release : "") "_" (A_Is64bitOS ? "x64" : "x86")
        width := A_ScreenWidth, height := A_ScreenHeight, dpi := A_ScreenDPI
        ; 分辨率与缩放来自同一块屏幕：优先报错/反馈所在窗口，否则当前前台窗口。
        try {
            if (!hwnd)
                hwnd := DllCall("user32\GetForegroundWindow", "Ptr")
            monitor := DllCall("user32\MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
            info := Buffer(40, 0)
            NumPut("UInt", 40, info)
            if (DllCall("user32\GetMonitorInfoW", "Ptr", monitor, "Ptr", info)) {
                width := NumGet(info, 12, "Int") - NumGet(info, 4, "Int")
                height := NumGet(info, 16, "Int") - NumGet(info, 8, "Int")
            }
            dx := 0, dy := 0
            if (DllCall("shcore\GetDpiForMonitor", "Ptr", monitor, "Int", 0, "UInt*", &dx, "UInt*", &dy, "Int") == 0 && dx)
                dpi := dx
            ; WPF 窗口按显示器感知 DPI；优先使用窗口的实际缩放。
            try {
                windowDpi := DllCall("user32\GetDpiForWindow", "Ptr", hwnd, "UInt")
                if (windowDpi)
                    dpi := windowDpi
            }
        }
        return "RMTv" RMT_VERSION " · " system " · " width "*" height " · " Round(dpi * 100 / 96) "%"
    }

    static TableLabel(table) {
        static pages := Map("Tool", "工具", "Setting", "设置", "Help", "帮助", "Reward", "支持我们", "Thank", "特别感谢")
        if (pages.Has(table.Symbol))
            return pages[table.Symbol]
        label := "宏"
        for def in MacroCategoryDefs() {
            if (table.Symbol == def[1]) {
                label := def[2]
                break
            }
        }
        return label
    }

    static Source(stack := "") {
        if (stack == "")
            stack := Error().Stack
        static sources := [
            ["RmtCmd", "命令行"], ["Network", "网络"], ["Voice", "语音"], ["Timing", "定时"],
            ["Gesture", "手势"], ["MenuWheelGui", "轮盘"], ["UIMacroGui|UIMacroRenderer", "自定义界面"],
            ["WorkPool|MacroUtil|InputUtil", "宏指令"], ["TriggerKeyData", "快捷键"],
            ["MacroDebug|MenuHandler|OnSideDebug", "调试"], ["OnCopyData|_RunEditorCallback|MainWin|Gui\.", "界面按钮"]]
        for entry in sources {
            if (RegExMatch(stack, entry[1]))
                return entry[2]
        }
        return A_ThisHotkey != "" ? "快捷键" : "程序调用"
    }

    static Macro(table, index, action := "触发", source := "") {
        if (action != "触发" && RegExMatch(Error().Stack, "\[(?:OnKillAllMacro|OnPauseHotKey|SetPauseState)\]"))
            return ; 批量运行控制只记整体操作，不让每条宏挤满十步。
        static sources := Map("命令行", 1, "网络", 1, "语音", 1, "定时", 1, "手势", 1, "轮盘", 1,
            "自定义界面", 1, "宏指令", 1, "快捷键", 1, "手柄", 1, "调试", 1, "界面按钮", 1, "程序调用", 1)
        if (!sources.Has(source))
            source := ""
        if (source == "")
            source := this.Source()
        this.Record(action this.TableLabel(table) "页签-第" index "个宏（" source "）")
    }

    static Edit(action, graph := false) {
        this.Record((graph ? "宏流程图" : "宏指令编辑") "界面-" action)
    }

    static RecordTreeEdit(stack) {
        static actions := Map("OnAddCmd", "新增指令", "OnSubNodeAddCmd", "新增分支指令",
            "OnModifyCmd", "修改指令", "OnDeleteCmd", "删除指令", "Backspace", "删除末尾指令",
            "ClearStr", "清空指令", "OnPreMoveCmd", "上移指令", "OnNextMoveCmd", "下移指令",
            "OnSwitchCmd", "移动指令", "OnPreInsertCmd", "向前插入指令",
            "OnNextInsertCmd", "向后插入指令", "PasteClipboardCommands", "粘贴指令", "PasteIntoContainer", "粘贴分支指令",
            "MoveTreeViewItem", "拖动指令", "ToggleSkipSelected", "切换跳过指令", "OnCopy", "复制指令")
        for method, label in actions {
            if (InStr(stack, "." method "]") || InStr(stack, "." method "(")) {
                this.Edit(label)
                return
            }
        }
        this.Edit("修改指令")
    }

    static OnValueChanged(ui, state, *) {
        if (!state.Has("UserValueChanged") || ui.feedbackWindow == "")
            return
        parts := StrSplit(state["UserValueChanged"], "|", , 2)
        if (parts.Length != 2)
            return
        control := parts[2]
        if (control == "MacroText") {
            static textActions := Map("text", "修改文本指令", "copy", "复制文本指令", "paste", "粘贴文本指令",
                "cut", "剪切文本指令", "undo", "撤销文本编辑", "redo", "重做文本编辑")
            this.Edit(textActions.Has(parts[1]) ? textActions[parts[1]] : "修改文本指令")
            return
        }
        if (parts[1] == "copy")
            return
        if (control == "OperSettingCon")
            return ; 由配置管理的业务校验后记录。
        name := this.ControlLabel(control)
        isText := RegExMatch(parts[1], "^(text|paste|cut|undo|redo)$")
        this.Record((isText ? "修改" : "设置") ui.feedbackWindow "界面-" name (isText ? "值" : "选项"), ui.id "-value-" control)
    }

    static ControlLabel(control) {
        if (this.SettingNames.Has(control))
            return this.SettingNames[control]
        if (this.ControlNames.Has(control))
            return this.ControlNames[control]
        ; 节点/行的数字后缀只用于识别固定字段，不读取其内容。
        base := RegExReplace(RegExReplace(control, "_.*$", ""), "\d+$", "")
        if (this.ControlNames.Has(base))
            return this.ControlNames[base]
        return "参数"
    }

    static ListAction(table, action, setting := false) {
        static labels := Map("TKBtn", "编辑触发", "TKBtnR", "自定义触发", "TKBtnKeyboard", "键盘触发",
            "TKBtnJoy", "手柄触发", "GestureMouse", "鼠标手势", "GestureTouch", "触屏手势",
            "Setting", "宏设置", "Edit", "宏编辑", "Forbid", "禁用宏", "Copy", "复制宏",
            "Share", "分享宏", "Del", "删除宏", "NetHelp", "网络触发说明", "Select", "选择宏",
            "SelectDbl", "展开逻辑树", "FoldBtn", "展开模块", "FoldFrontBtn", "模块前台设置",
            "FoldFrontHelp", "模块前台说明", "FoldTKEdit", "模块触发", "FoldTKEditKeyboard", "模块键盘触发",
            "FoldTKEditJoy", "模块手柄触发", "FoldPos", "模块位置", "FoldAddMacro", "新增宏",
            "FoldPasteMacro", "粘贴宏", "FoldShare", "分享模块", "FoldForbidBtn", "禁用模块", "FoldDel", "删除模块",
            "FoldGestureMouse", "模块鼠标手势", "FoldGestureTouch", "模块触屏手势",
            "Name", "名称", "Remark", "备注", "RunCount", "运行次数", "Mode", "模式", "Trigger", "触发方式")
        name := labels.Has(action) ? labels[action] : (setting ? "宏参数" : "宏操作")
        page := this.TableLabel(table) "页签"
        this.Record((setting ? "设置" : "点击") page "-" name (setting ? "选项" : "按钮"),
            setting ? page "-" name : "")
    }

    static Observe(ui, control, event, stack := "") {
        if (event == "Created") {
            ; 调用栈只用于匹配固定的类名，不保存路径、动态标题或控件内容。
            ; 未登记的后台提示/自动浮层不属于玩家操作，不能挤占最近十步。
            ui.feedbackWindow := ""
            pos := 1
            while (pos := RegExMatch(stack, "\[([\w]+)\.[^\]]*\]", &m, pos)) {
                if (this.WindowNames.Has(m[1])) {
                    ui.feedbackWindow := this.WindowNames[m[1]]
                    break
                }
                pos += StrLen(m[0])
            }
            if (ui.feedbackWindow != "")
                ui.OnEvent("Window", "UserValueChanged", ObjBindMethod(this, "OnValueChanged", ui))
            return
        }
        if (!ui.HasOwnProp("feedbackWindow") || ui.feedbackWindow == "")
            return
        ; 主页签在业务层过滤初始化/冒泡事件后，用固定分类名称记录。
        if (ui.feedbackWindow == "主" && control == "TabControl" && event == "SelectionChanged")
            return
        ; 配置列表初始化会反复选中当前配置；业务层的 _applyingUI 负责区分用户选择。
        if (ui.feedbackWindow == "配置管理" && control == "OperSettingCon" && event == "SelectionChanged")
            return
        window := ui.feedbackWindow "界面"
        if (event == "LoadedHwnd") {
            this.Record("打开" window)
            return
        }
        ; 选项/文本由引擎只上报实际用户改值，避免初始化及联动刷新污染记录。
        if (event != "Click")
            return
        if (!ui.wpfHwnd || !WinActive("ahk_id " ui.wpfHwnd))
            return
        static businessControls := Map("BtnUndo", 1, "BtnRedo", 1, "BtnModeTree", 1, "BtnModeText", 1,
            "SaveBtn", 1, "BtnSave", 1, "BtnPause", 1, "BtnPauseActive", 1, "BtnKill", 1)
        if (businessControls.Has(control))
            return ; 由实际业务入口记录，覆盖按钮和快捷键，避免同一步记两次。
        name := this.ControlNames.Has(control) ? this.ControlNames[control] : ""
        if (ui.feedbackWindow == "配置管理") {
            static configActions := Map("BtnUnpack", "导入配置", "BtnPack", "导出配置", "BtnMerge", "合并导入",
                "BtnLoad", "加载配置", "BtnRename", "重命名配置", "BtnAdd", "新增配置", "BtnDel", "删除配置",
                "BtnRepair", "配置校准", "BtnReplace", "升级配置")
            if (configActions.Has(control))
                name := configActions[control]
        }
        ; 未登记的控件使用固定用途，不回退到玩家可编辑的 Content/Text。
        if (name == "")
            name := event == "Click" ? "操作" : "参数"
        if (event == "Click")
            this.Record("点击" window "-" name "按钮")
        else
            this.Record("设置" window "-" name "选项", ui.id "-" control)
    }
}
