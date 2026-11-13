ReadMacroTotalCount(file, fallback := 0) {
    count := CfgRead(file, "UserSettings", "MacroTotalCount")
    if (IsInteger(count) && count >= 0)
        return Integer(count)
    return fallback
}

LoadMainSetting() {
    global MainSoftData, MySoftData
    global SettingSection := "UserSettings"
    MySoftData.CurSettingName := CfgRead(SettingFile, SettingSection, "CurSettingName", "RMT默认配置")
    MainSoftData.SettingArrStr := CfgRead(SettingFile, SettingSection, "SettingArrStr", "RMT默认配置")
    MainSoftData.HasSaved := CfgRead(SettingFile, SettingSection, "HasSaved", false)
    MainSoftData.IsReload := CfgRead(SettingFile, SettingSection, "IsReload", false)
    MySoftData.NormalPeriod := CfgRead(SettingFile, SettingSection, "NormalPeriod", 50)
    MainSoftData.HoldFloat := CfgRead(SettingFile, SettingSection, "HoldFloat", 0)
    MainSoftData.PreIntervalFloat := CfgRead(SettingFile, SettingSection, "PreIntervalFloat", 0)
    MainSoftData.IntervalFloat := CfgRead(SettingFile, SettingSection, "IntervalFloat", 0)
    MainSoftData.CoordXFloat := CfgRead(SettingFile, SettingSection, "CoordXFloat", 0)
    MainSoftData.CoordYFloat := CfgRead(SettingFile, SettingSection, "CoordYFloat", 0)
    MainSoftData.SuspendHotkey := CfgRead(SettingFile, SettingSection, "SuspendHotkey", "!p")
    MainSoftData.PauseHotkey := CfgRead(SettingFile, SettingSection, "PauseHotkey", "!i")
    MainSoftData.KillMacroHotkey := CfgRead(SettingFile, SettingSection, "KillMacroHotkey", "!k")
    ; §14.5 / IDE 式调试：逻辑树调试热键（默认 继续=F5 / 步入=F11，可在设置→快捷键修改）
    MainSoftData.DebugRunHotkey := CfgRead(SettingFile, SettingSection, "DebugRunHotkey", "f5")
    MainSoftData.DebugStepHotkey := CfgRead(SettingFile, SettingSection, "DebugStepHotkey", "f11")
    MainSoftData.DebugStepOverHotkey := CfgRead(SettingFile, SettingSection, "DebugStepOverHotkey", "f10")
    MainSoftData.DebugStepOutHotkey := CfgRead(SettingFile, SettingSection, "DebugStepOutHotkey", "+f11")
    MainSoftData.DebugRunToCursorHotkey := CfgRead(SettingFile, SettingSection, "DebugRunToCursorHotkey", "^f10")
    MainSoftData.DebugToggleSkipHotkey := CfgRead(SettingFile, SettingSection, "DebugToggleSkipHotkey", "^/")
    MainSoftData.DebugRunAllHotkey := CfgRead(SettingFile, SettingSection, "DebugRunAllHotkey", "^f5")
    MainSoftData.IsToolCheck := CfgRead(SettingFile, SettingSection, "IsToolCheck", false)
    MainSoftData.ToolCheckHotKey := CfgRead(SettingFile, SettingSection, "ToolCheckHotKey", "!o")
    MainSoftData.ToolRecordMacroHotKey := CfgRead(SettingFile, SettingSection, "RecordMacroHotKey", "!r")
    MainSoftData.ToolTextFilterHotKey := CfgRead(SettingFile, SettingSection, "ToolTextFilterHotKey", "")
    MainSoftData.ScreenShotHotKey := CfgRead(SettingFile, SettingSection, "ScreenShotHotKey", "")
    MainSoftData.FreePasteHotKey := CfgRead(SettingFile, SettingSection, "FreePasteHotKey", "")
    MainSoftData.RecordKeyboard := CfgRead(SettingFile, SettingSection, "RecordKeyboard", true)
    MainSoftData.RecordMouse := CfgRead(SettingFile, SettingSection, "RecordMouse", true)
    MainSoftData.RecordJoy := CfgRead(SettingFile, SettingSection, "RecordJoy", false)
    MainSoftData.RecordMouseTrail := CfgRead(SettingFile, SettingSection, "RecordMouseTrail", 1)
    MainSoftData.RecordMouseTrailSpeed := CfgRead(SettingFile, SettingSection, "RecordMouseTrailSpeed", 95)
    MainSoftData.RecordHoldMuti := CfgRead(SettingFile, SettingSection, "RecordHoldMuti", false)
    MainSoftData.RecordAutoLoosen := CfgRead(SettingFile, SettingSection, "RecordAutoLoosen", true)
    MainSoftData.RecordJoyInterval := CfgRead(SettingFile, SettingSection, "RecordJoyInterval", 50)
    MainSoftData.RecordShowBorder := CfgRead(SettingFile, SettingSection, "RecordShowBorder", true)
    MainSoftData.OCRTypeValue := CfgRead(SettingFile, SettingSection, "OCRType", 1) == 2 ? 2 : 1
    MainSoftData.ExcelBackend := CfgRead(SettingFile, SettingSection, "ExcelBackend", 1) == 2 ? 2 : 1
    MainSoftData.IsBootStart := CfgRead(SettingFile, SettingSection, "IsBootStart", false)
    if (MainSoftData.IsBootStart == 1 || MainSoftData.IsBootStart == 2)
        MainSoftData.IsBootStart := true
    else if (MainSoftData.IsBootStart == "false" || MainSoftData.IsBootStart == 0)
        MainSoftData.IsBootStart := false
    else
        MainSoftData.IsBootStart := !!MainSoftData.IsBootStart
    MainSoftData.IsAdminStart := CfgRead(SettingFile, SettingSection, "IsAdminStart", false)
    if (MainSoftData.IsAdminStart == 1 || MainSoftData.IsAdminStart == "true")
        MainSoftData.IsAdminStart := true
    else if (MainSoftData.IsAdminStart == "false" || MainSoftData.IsAdminStart == 0)
        MainSoftData.IsAdminStart := false
    else
        MainSoftData.IsAdminStart := !!MainSoftData.IsAdminStart
    reportRaw := String(CfgRead(SettingFile, SettingSection, "IsDataReport", true))
    MainSoftData.IsDataReport := !(reportRaw = "0" || reportRaw = "false")
    MainSoftData.ShowSplitLine := CfgRead(SettingFile, SettingSection, "ShowSplitLine", false)
    MainSoftData.FixedMenuWheel := CfgRead(SettingFile, SettingSection, "FixedMenuWheel", false)
    MainSoftData.MenuWheelSelectMode := CfgRead(SettingFile, SettingSection, "MenuWheelSelectMode", 2)
    MainSoftData.MenuWheelShowTooltip := CfgRead(SettingFile, SettingSection, "MenuWheelShowTooltip", false)
    MainSoftData.MenuWheelScale := CfgRead(SettingFile, SettingSection, "MenuWheelScale", 100)
    MainSoftData.Theme := CfgRead(SettingFile, SettingSection, "Theme", "RMT_Light")
    ; 主题字体：大小与 FontType 一样落在用户设置；用户设置缺失时回退主题文件 themes.toml
    global XAML_FontSizeDelta, XAML_FontSizeBase, XAML_FontSizeDefault, XAML_FontWeight, XAML_TextClarity
    defFs := IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15
    fs := CfgRead(SettingFile, SettingSection, "FontSize", "")
    if (fs == "" || !IsNumber(fs)) {
        themeFile := GetThemesPath()
        fs := CfgRead(themeFile, MainSoftData.Theme, "FontSize", defFs)
    }
    ApplyUserFontSize(fs, false)
    try {
        themeFile := GetThemesPath()
        MainSoftData.FontWeight := FontWeightToNum(CfgRead(themeFile, MainSoftData.Theme, "FontWeight", "400"))
        XAML_FontWeight := MainSoftData.FontWeight
        MainSoftData.FontClarity := "1"   ; 文字清晰度固定 1（标准平滑）
        XAML_TextClarity := 1
    }
    ; 界面浮窗配置（非颜色）
    MainSoftData.UIPanelShowOnActive := CfgRead(SettingFile, SettingSection, "UIPanelShowOnActive", true)
    MainSoftData.UIPanelBtnHeight := CfgRead(SettingFile, SettingSection, "UIPanelBtnHeight", 34)
    MainSoftData.UIPanelFontSize := CfgRead(SettingFile, SettingSection, "UIPanelFontSize", 12)
    MainSoftData.UIPanelBtnWidth := CfgRead(SettingFile, SettingSection, "UIPanelBtnWidth", 80)
    MainSoftData.UIPanelCols := CfgRead(SettingFile, SettingSection, "UIPanelCols", 3)
    MainSoftData.UIPanelBall := CfgRead(SettingFile, SettingSection, "UIPanelBall", "")
    MainSoftData.UIPanelBallPos := CfgRead(SettingFile, SettingSection, "UIPanelBallPos", "")
    MainSoftData.UIPanelPos := CfgRead(SettingFile, SettingSection, "UIPanelPos", "")
    MainSoftData.CountDownFontSize := CfgRead(SettingFile, SettingSection, "CountDownFontSize", 15)
    MainSoftData.CountDownAlpha := CfgRead(SettingFile, SettingSection, "CountDownAlpha", 70)
    MainSoftData.CountDownStyle := Integer(CfgRead(SettingFile, SettingSection, "CountDownStyle", 2))
    if (MainSoftData.CountDownStyle < 1 || MainSoftData.CountDownStyle > 3)
        MainSoftData.CountDownStyle := 2
    MainSoftData.CountDownPadZero := CfgRead(SettingFile, SettingSection, "CountDownPadZero", true)
    ; 主题文件由主进程在 LoadMainSetting 之前补齐（见 GlobalUtil）；这里只读不建。
    ; 统一主题颜色（轮盘/浮窗/指令显示），不兼容旧分散颜色配置
    AppThemeUtil.LoadFromToml()
    MainSoftData.IsModalSubGui := CfgRead(SettingFile, SettingSection, "IsModalSubGui", true)
    MainSoftData.MutiThreadNum := CfgRead(SettingFile, SettingSection, "MutiThreadNum", -1)
    MainSoftData.DynamicCorePoolSize := CfgRead(SettingFile, SettingSection, "DynamicCorePoolSize", 2)
    MainSoftData.ElasticTimeout := CfgRead(SettingFile, SettingSection, "ElasticTimeout", 30)
    MainSoftData.MacroStopType := Integer(CfgRead(SettingFile, SettingSection, "MacroStopType", 1))
    if (MainSoftData.MacroStopType != 1 && MainSoftData.MacroStopType != 2)
        MainSoftData.MacroStopType := 1
    MainSoftData.SearchImageAdaptive := CfgRead(SettingFile, SettingSection, "SearchImageAdaptive", false)
    MainSoftData.SearchImageType := Integer(CfgRead(SettingFile, SettingSection, "SearchImageType", 1))
    if (MainSoftData.SearchImageType != 1 && MainSoftData.SearchImageType != 2)
        MainSoftData.SearchImageType := 1
    MainSoftData.SoftBGColor := CfgRead(SettingFile, SettingSection, "SoftBGColor", "f0f0f0")
    ; §11 主界面背景图（全局配置，空=不启用）
    MainSoftData.BackImagePath := CfgRead(SettingFile, SettingSection, "BackImagePath", "")
    MainSoftData.NoVariableTip := CfgRead(SettingFile, SettingSection, "NoVariableTip", true)
    ; 业务日志开关（统一日志 C 项阶段3）：默认关，开启后 Worker 写 Business.log 流水
    global RMTLogBusinessEnabled
    MainSoftData.BusinessLog := CfgRead(SettingFile, SettingSection, "BusinessLog", false)
    RMTLogBusinessEnabled := MainSoftData.BusinessLog
    ; 日志与错误（C 项阶段5）
    global RMTLogSysMinLevel
    MainSoftData.SysLogMinLevel := CfgRead(SettingFile, SettingSection, "SysLogLevels", "warn,error")
    RMTLogSysMinLevel := MainSoftData.SysLogMinLevel
    ; AI 助手（OpenAI 兼容）
    MainSoftData.AiApiKey := CfgRead(SettingFile, SettingSection, "AiApiKey", "")
    MainSoftData.AiApiBaseUrl := CfgRead(SettingFile, SettingSection, "AiApiBaseUrl", "https://api.openai.com/v1")
    MainSoftData.AiProvider := CfgRead(SettingFile, SettingSection, "AiProvider", "openai")
    MainSoftData.AiModel := CfgRead(SettingFile, SettingSection, "AiModel", "")
    MainSoftData.AiModelList := CfgRead(SettingFile, SettingSection, "AiModelList", "")
    MainSoftData.AiAccessMode := Integer(CfgRead(SettingFile, SettingSection, "AiAccessMode", 2))
    MainSoftData.AiApprovalMode := Integer(CfgRead(SettingFile, SettingSection, "AiApprovalMode", 2))
    if (MainSoftData.AiAccessMode < 1 || MainSoftData.AiAccessMode > 3)
        MainSoftData.AiAccessMode := 2
    if (MainSoftData.AiApprovalMode < 1 || MainSoftData.AiApprovalMode > 3)
        MainSoftData.AiApprovalMode := 2
    rawPanelW := CfgRead(SettingFile, SettingSection, "AiPanelWidth", 380)
    MainSoftData.AiPanelWidth := IsNumber(rawPanelW) ? Integer(rawPanelW) : 380
    MainSoftData.LogicTreeBranchSplit := !!CfgRead(SettingFile, SettingSection, "LogicTreeBranchSplit", false)
    MainSoftData.LogWarnBubble := CfgRead(SettingFile, SettingSection, "LogWarnBubble", true)
    MainSoftData.LogErrorBadge := CfgRead(SettingFile, SettingSection, "LogErrorBadge", true)
    ; §23 网络触发：监听端口（默认 16888，NetworkNormalizePort 钳制 1-65535）
    MainSoftData.NetworkPort := NetworkNormalizePort(CfgRead(SettingFile, SettingSection, "NetworkPort", 16888))
    MySoftData.CMDTip := CfgRead(SettingFile, SettingSection, "CMDTip", false)
    MainSoftData.CheckForeground := CfgRead(SettingFile, SettingSection, "CheckForeground", false)
    MainSoftData.ScreenShotType := CfgRead(SettingFile, SettingSection, "ScreenShotType", 3)
    MainSoftData.KeyDownDownType := CfgRead(SettingFile, SettingSection, "KeyDownDown", 1)
    MainSoftData.AutoLoosenModifier := !!CfgRead(SettingFile, SettingSection, "AutoLoosenModifier", true)
    MainSoftData.ContinuousTrigger := !!CfgRead(SettingFile, SettingSection, "ContinuousTrigger", true)
    MainSoftData.AgreeAgreement := CfgRead(SettingFile, SettingSection, "AgreeAgreement", false)
    MySoftData.WinPosX := CfgRead(SettingFile, SettingSection, "WinPosX", 0)
    MySoftData.WinPosY := CfgRead(SettingFile, SettingSection, "WinPosY", 0)
    MainSoftData.TableIndex := CfgRead(SettingFile, SettingSection, "TableIndex", 1)
    MainSoftData.CurTableID := IsNumber(MainSoftData.TableIndex) ? "" : MainSoftData.TableIndex
    ; 宏相关页签可见性（隐藏不影响触发）；静态页签恒显示
    MainSoftData.TabVisibleMap := Map()
    rawTabVis := CfgRead(SettingFile, SettingSection, "TabVisible", "")
    for def in MacroCategoryDefs()
        MainSoftData.TabVisibleMap[def[1]] := true
    if (rawTabVis != "") {
        for seg in StrSplit(rawTabVis, "π") {
            p := StrSplit(seg, "=")
            if (p.Length == 2 && MainSoftData.TabVisibleMap.Has(p[1]))
                MainSoftData.TabVisibleMap[p[1]] := (p[2] == "1")
        }
    }
    MainSoftData.Lang := CfgRead(SettingFile, SettingSection, "Lang", "简中")
    MainSoftData.FontType := CfgRead(SettingFile, SettingSection, "FontType", "微软雅黑")
    MainSoftData.JoyType := CfgRead(SettingFile, SettingSection, "JoyType", "Xbox")
    MainSoftData.TriggerJoyType := CfgRead(SettingFile, SettingSection, "TriggerJoyType", "Xbox")
    rawLtRt := CfgRead(SettingFile, SettingSection, "JoyLtRtAsButton", true)
    MainSoftData.JoyLtRtAsButton := !(rawLtRt == 0 || rawLtRt == "0" || rawLtRt == "false" || rawLtRt == "False")
    MainSoftData.PreferredMacroEditor := Integer(CfgRead(SettingFile, SettingSection, "PreferredMacroEditor", 1))
    MainSoftData.SharedCopy := !!CfgRead(SettingFile, SettingSection, "SharedCopy", false)
    MainSoftData.GeneralContextMenu := CfgRead(SettingFile, SettingSection, "GeneralContextMenu", "")
    MainSoftData.BranchContextMenu  := CfgRead(SettingFile, SettingSection, "BranchContextMenu",  "")
    if (MainSoftData.PreferredMacroEditor != 1 && MainSoftData.PreferredMacroEditor != 2)
        MainSoftData.PreferredMacroEditor := 1
    MainSoftData.RemarkAutoType := Integer(CfgRead(SettingFile, SettingSection, "RemarkAutoType", 2))
    if (MainSoftData.RemarkAutoType != 1 && MainSoftData.RemarkAutoType != 2 && MainSoftData.RemarkAutoType != 3)
        MainSoftData.RemarkAutoType := 2
    ; CMD 默认：宽按 DPI 缩放，高 300，X = 屏幕宽 - 显示宽（物理像素 / -DPIScale）
    defCMDWidth := GetDefaultCMDTipWidth()
    MainSoftData.CMDWidth := CfgRead(SettingFile, SettingSection, "CMDWidth", defCMDWidth)
    MainSoftData.CMDHeight := CfgRead(SettingFile, SettingSection, "CMDHeight", 300)
    MainSoftData.CMDPosX := CfgRead(SettingFile, SettingSection, "CMDPosX", A_ScreenWidth - Integer(MainSoftData.CMDWidth))
    MainSoftData.CMDPosY := CfgRead(SettingFile, SettingSection, "CMDPosY", 0)
    MainSoftData.CMDTransparency := CfgRead(SettingFile, SettingSection, "CMDTransparency", 50)
    MainSoftData.CMDFontSize := CfgRead(SettingFile, SettingSection, "CMDFontSize", 12)
    MainSoftData.CMDLogToFile := CfgRead(SettingFile, SettingSection, "CMDLogToFile", false)
    rawLogPath := CfgRead(SettingFile, SettingSection, "CMDLogFilePath", "")
    MainSoftData.CMDLogFilePath := CMDLogCalibrateStored(rawLogPath)
    ; 旧的绝对路径（上次安装目录\Log）在内存里已收成相对路径，回写由主进程统一做
    ; （EnsureMainSettingPersisted）；本函数只读，Worker 也走这一份。
    rawClear := CfgRead(SettingFile, SettingSection, "CMDLogAutoClear", 2)
    MainSoftData.CMDLogAutoClear := IsNumber(rawClear) ? Integer(rawClear) : 2
    if (MainSoftData.CMDLogAutoClear < 0 || MainSoftData.CMDLogAutoClear > 2)
        MainSoftData.CMDLogAutoClear := 2
    MainSoftData.StartTipAudio := CfgRead(SettingFile, SettingSection, "StartTipAudio", A_WorkingDir "\Audio\Start.wav")
    MainSoftData.EndTipAudio := CfgRead(SettingFile, SettingSection, "EndTipAudio", A_WorkingDir "\Audio\End.wav")
    MainSoftData.StopTipAudio := CfgRead(SettingFile, SettingSection, "StopTipAudio", MainSoftData.EndTipAudio)
    MainSoftData.VarListenTop := CfgRead(SettingFile, SettingSection, "VarListenTop", 1)
    MainSoftData.VarListenWidth := CfgRead(SettingFile, SettingSection, "VarListenWidth", 400)
    MainSoftData.VarListenHeight := CfgRead(SettingFile, SettingSection, "VarListenHeight", 420)
    MySoftData.MacroTotalCount := ReadMacroTotalCount(SettingFile)
    MainSoftData.LastShowMonth := CfgRead(SettingFile, SettingSection, "LastShowMonth", A_Mon)

    MySoftData.TableInfo := CreateTableItemArr()
    SetFontList()
    LangInitSetting()
    LangKeysInit()
}

; ============================================================
; 主进程专用：把 LoadMainSetting 里算出的「校正结果 / 兜底默认值」落定。
; 单独成一步，是为了让 LoadMainSetting 保持纯读——Worker 也调用它，
; 而 Worker 只该拿着配置去执行宏，不该回写任何文件。
; ============================================================
EnsureMainSettingPersisted() {
    global MainSoftData
    ; 旧安装目录留下的绝对日志路径 → 相对路径，换文件夹后不用再手选
    rawLog := CfgRead(SettingFile, SettingSection, "CMDLogFilePath", "")
    if (MainSoftData.CMDLogFilePath != CMDLogNorm(rawLog) && !(MainSoftData.CMDLogFilePath == "" && Trim(rawLog) == ""))
        try CfgWrite(MainSoftData.CMDLogFilePath, SettingFile, SettingSection, "CMDLogFilePath")
    ; 首次安装：把算出来的兜底字号落定，之后启动直接读到，不必每次走兜底分支
    if (CfgRead(SettingFile, SettingSection, "FontSize", "") == "")
        try CfgWrite(MainSoftData.FontSize, SettingFile, SettingSection, "FontSize")
    ; 启动维护：日志按配置自动清理。属于主进程的启动动作，不再塞在 LoadMainSetting 里
    ; 靠「是不是 Worker」去关。
    try CMDLogTryAutoClear(CMDLogResolveFile(MainSoftData.CMDLogFilePath), MainSoftData.CMDLogAutoClear)
}


; 把路径里的 \..\ 消掉（GetFullPathName 只做字符串规整，不要求路径存在）。
ResolvePathNoDotDot(p) {
    p := RTrim(String(p), "\")
    if (!InStr(p, ".."))
        return p
    buf := Buffer(65536 * 2, 0)
    n := DllCall("GetFullPathNameW", "Str", p, "UInt", 65536, "Ptr", buf, "Ptr", 0)
    return (n > 0) ? StrGet(buf, n) : p
}

; ============================================================
; 数据文件路径表：主进程与 Worker 共用这一份定义。
; rootDir = 软件根目录（主进程传 A_WorkingDir，Worker 传 A_WorkingDir "\.."）。
; 以前主进程和 Worker 各抄一份 37 项的表，新增配置文件漏改一边不会报错，
; 只会让 Worker 静默读到空路径。
; 这里只算路径：建目录、旧格式迁移、展开扁平宏都是主进程启动时的事（见 InitFilePath）。
; ============================================================
InitDataFilePaths(rootDir) {
    global ProjectRootDir := ResolvePathNoDotDot(rootDir)
    global VBSPath := ProjectRootDir "\MinTool\PlayAudio.vbs"
    global StartTipAudio := (MainSoftData.StartTipAudio != "" && FileExist(MainSoftData.StartTipAudio)) ? MainSoftData.StartTipAudio : ProjectRootDir "\Audio\Start.wav"
    global EndTipAudio := (MainSoftData.EndTipAudio != "" && FileExist(MainSoftData.EndTipAudio)) ? MainSoftData.EndTipAudio : ProjectRootDir "\Audio\End.wav"
    global StopTipAudio := (MainSoftData.StopTipAudio != "" && FileExist(MainSoftData.StopTipAudio)) ? MainSoftData.StopTipAudio : EndTipAudio
    global ViGEmDllPath := ProjectRootDir "\Plugins\ViGEm\ViGEmWrapper.dll"
    global AHIDllDir := ProjectRootDir "\Plugins\AhiDriver"
    global AHIPluginDir := ProjectRootDir "\Plugins\AhiDriver\installer"

    cfgDir := ProjectRootDir "\Setting\" MySoftData.CurSettingName
    global ArrayFile := cfgDir "\ArrayFile.toml"
    global MacroFile := cfgDir "\MacroFile.toml"
    global SearchFile := cfgDir "\SearchFile.toml"
    global SearchAllFile := cfgDir "\SearchAllFile.toml"
    global SearchProFile := cfgDir "\SearchProFile.toml"
    global SearchComboFile := cfgDir "\SearchComboFile.toml"
    global CompareFile := cfgDir "\CompareFile.toml"
    global CompareProFile := cfgDir "\CompareProFile.toml"
    global MMProFile := cfgDir "\MMProFile.toml"
    global BGKeyFile := cfgDir "\BGKeyFile.toml"
    global TimingFile := cfgDir "\TimingFile.toml"
    global RunFile := cfgDir "\RunFile.toml"
    global OutputFile := cfgDir "\OutputFile.toml"
    global PromptFile := cfgDir "\PromptFile.toml"
    global VariableFile := cfgDir "\VariableFile.toml"
    global ExVariableFile := cfgDir "\ExVariableFile.toml"
    global TextOpsFile := cfgDir "\TextOpsFile.toml"
    global SubMacroFile := cfgDir "\SubMacroFile.toml"
    global LoopFile := cfgDir "\LoopFile.toml"
    global OperationFile := cfgDir "\OperationFile.toml"
    global BGMouseFile := cfgDir "\BGMouseFile.toml"
    global InputFile := cfgDir "\InputFile.toml"
    global HttpRequestFile := cfgDir "\HttpRequestFile.toml"
    global FileIOFile := cfgDir "\FileIOFile.toml"
    global WindowManageFile := cfgDir "\WindowManageFile.toml"
    global KeyCheckFile := cfgDir "\KeyCheckFile.toml"
    global JoyCheckFile := cfgDir "\JoyCheckFile.toml"
    global CommentFile := cfgDir "\CommentFile.toml"
    global ScreenShotFile := cfgDir "\ScreenShotFile.toml"
    global GraphNodeFile := cfgDir "\GraphNodeFile.toml"
    global GraphStartNodeFile := cfgDir "\GraphStartNodeFile.toml"
    ; 阶段5：纯文本指令迁移到配置文件模式（间隔/按键/移动/RMT指令）
    global IntervalFile := cfgDir "\IntervalFile.toml"
    global KeyDataFile := cfgDir "\KeyDataFile.toml"
    global MoveDataFile := cfgDir "\MoveDataFile.toml"
    global RMTCMDFile := cfgDir "\RMTCMDFile.toml"
    global WaitFile := cfgDir "\WaitFile.toml"
    global WaitConfirmFile := cfgDir "\WaitConfirmFile.toml"
    global DeltaMoveFile := cfgDir "\DeltaMoveFile.toml"
    global TimeDataFile := cfgDir "\TimeDataFile.toml"
    global CountDownFile := cfgDir "\CountDownFile.toml"
}

; ---------- §23 网络触发：端口工具（P2-1：保存校验与启动钳制共用）----------
; 放在本文件（主进程与 Worker 共同 include）；不能放 NetworkHttpUtil.ahk（仅主进程 include），
; 否则 Worker 加载 LoadMainSetting 时函数名无法解析（AHK #Warn）。

; 端口合法性：必须是 1-65535 的整数（99999 这类值经 htons 截断会静默监听错端口）。
; 用 IsInteger 值检查而非 `is Integer` 类型检查：CfgRead 返回字符串，"16890" 也须视为合法。
NetworkIsValidPort(v) {
    if (!IsInteger(v))
        return false
    return (v >= 1 && v <= 65535)
}

; 归一化端口：非法/越界一律回退默认 16888（启动/调和路径防御，避免 Integer() 抛异常）
NetworkNormalizePort(v) {
    return NetworkIsValidPort(v) ? Integer(v) : 16888
}
