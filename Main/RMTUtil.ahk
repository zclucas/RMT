#Requires AutoHotkey v2.0

; ===== AHK-XAML 生产模式配置 =====
; 注意：true 时若 lib/dep/src 下的 .cs 源码（拆分后为多文件）比 lib/dep/ahk-xaml.dll 新会自动重新编译桥接 DLL。
; 直接运行 .ahk 调试必须开着，否则改了 C# 也不会重编译（旧 DLL 存在就一直用旧的）。
; 编译成 exe 发布(A_IsCompiled)时此开关被忽略、始终用打包好的 DLL，故开着对发布无影响。
global XAML_FORCE_DYNAMIC_COMPILE := true
global XAML_ENGINE_BUILD_LOCATION := "lib/dep"
global XAML_DIAGNOSTICS_ENABLED := false
global XAML_AXML_DEBUG_MODE := false
global XAML_ENABLE_LOGGING := false
global XAML_ENABLE_TRACING := false
global XAML_ENABLE_DEVTOOLS := false
; XAML_Config 默认 true（进程内 CLR）。多 XAML 窗时 EnsureDaemonMatches 会把映像路径
; （RMT/AHK.exe）与 ahk-xaml.dll 判为不匹配并 KillDaemon，进而 ProcessClose 自身导致闪退。
; 正式运行使用独立 daemon 进程。
global XAML_IN_PROCESS_PREVIEW := false


;资源保存（带脏检查优化：只写入实际发生变化的配置项）
OnSaveSetting(*) {
    global MySoftData, MyWorkPool, MyHotReloadBus, MyMainWin, RMTLogSysMinLevel
    ; 主窗句柄回传前控件还不存在（启动链现在不阻塞等句柄），此时按保存会取到空控件，直接忽略
    if (!IsObject(MainSoftData.MyGui)) {
        XamlUiDiag("OnSaveSetting 忽略：主窗尚未就绪", "MainWin")
        return
    }
    threadCount := MainSoftData.MutiThreadNum
    if (IsSet(MyMainWin) && IsObject(MyMainWin) && MyMainWin.HasOwnProp("_setMods"))
        threadCount := Trim(MyMainWin.ui.Query("EditMutiThreadNum>Text"))
    if (!CheckAllValueSettingValid(threadCount))
        return
    MainSoftData.MutiThreadNum := Integer(threadCount)

    ; Epic5：虚拟化列表保存前兜底提交实体化行全字段（覆盖纯键盘后未失焦路径）。
    ; VL_COMMIT_ALL 回传经 SetTimer(-1) 异步写模型，Sleep(-1) 处理 pending timer 后再读，防丢
    for t, _ in MyMainWin._useVirtual {
        if (MyMainWin._useVirtual.Has(t)) {
            MyMainWin._vl.CommitAll(t)
            Sleep(-1)
        }
    }

    ; §18 职责分离：宏表数据已在各 live 编辑点即时落盘（HotReloadPublish/SaveTableItemInfo），
    ; 此处不再保存宏表；CommitAll 产生的模型变更经 _ApplyChange 已即时写盘。
    ; 本函数只处理非热重载数据：全局设置（下方 CheckAndAddDirty Ini 写）+ 表结构批量变更
    ; （表管理/合并路径在调用方显式 SaveAllTableItemInfo）。

    ; 静态变量：保存上次写入的值，用于脏检查
    static lastSavedSettings := Map()
    dirtySettings := Map()  ; 只收集发生变化的设置

    ; 辅助函数：检查值是否变化并记录
    CheckAndAddDirty(key, newValue) {
        if (!lastSavedSettings.Has(key) || lastSavedSettings[key] != newValue) {
            dirtySettings.Set(key, newValue)
            lastSavedSettings.Set(key, newValue)
        }
    }

    ; 基础设置
    CheckAndAddDirty("HoldFloat", MainSoftData.HoldFloat)
    CheckAndAddDirty("PreIntervalFloat", MainSoftData.PreIntervalFloat)
    CheckAndAddDirty("IntervalFloat", MainSoftData.IntervalFloat)
    CheckAndAddDirty("CoordXFloat", MainSoftData.CoordXFloat)
    CheckAndAddDirty("CoordYFloat", MainSoftData.CoordYFloat)
    ; §10 显示页签（symbol=0/1 π 拼接）
    _tvStr := ""
    for _sym, _vis in MainSoftData.TabVisibleMap
        _tvStr .= (_tvStr == "" ? "" : "π") _sym "=" (_vis ? 1 : 0)
    CheckAndAddDirty("TabVisible", _tvStr)
    CheckAndAddDirty("SuspendHotkey", MainSoftData.SuspendHotkey)
    CheckAndAddDirty("PauseHotkey", MainSoftData.PauseHotkey)
    CheckAndAddDirty("KillMacroHotkey", MainSoftData.KillMacroHotkey)
    CheckAndAddDirty("DebugRunHotkey", MainSoftData.HasProp("DebugRunHotkey") ? MainSoftData.DebugRunHotkey : "f5")
    CheckAndAddDirty("DebugStepHotkey", MainSoftData.HasProp("DebugStepHotkey") ? MainSoftData.DebugStepHotkey : "f11")
    CheckAndAddDirty("DebugStepOverHotkey", MainSoftData.HasProp("DebugStepOverHotkey") ? MainSoftData.DebugStepOverHotkey : "f10")
    CheckAndAddDirty("DebugStepOutHotkey", MainSoftData.HasProp("DebugStepOutHotkey") ? MainSoftData.DebugStepOutHotkey : "+f11")
    CheckAndAddDirty("DebugRunToCursorHotkey", MainSoftData.HasProp("DebugRunToCursorHotkey") ? MainSoftData.DebugRunToCursorHotkey : "^f10")
    CheckAndAddDirty("DebugToggleSkipHotkey", MainSoftData.HasProp("DebugToggleSkipHotkey") ? MainSoftData.DebugToggleSkipHotkey : "^/")
    CheckAndAddDirty("DebugRunAllHotkey", MainSoftData.HasProp("DebugRunAllHotkey") ? MainSoftData.DebugRunAllHotkey : "^f5")
    CheckAndAddDirty("IsBootStart", MainSoftData.IsBootStart)
    CheckAndAddDirty("IsDataReport", MainSoftData.HasProp("IsDataReport") ? MainSoftData.IsDataReport : true)
    CheckAndAddDirty("ShowSplitLine", MainSoftData.ShowSplitLine)
    CheckAndAddDirty("IsModalSubGui", MainSoftData.IsModalSubGui)
    CheckAndAddDirty("BackImagePath", MainSoftData.BackImagePath)   ; §11 主界面背景图
    CheckAndAddDirty("MutiThreadNum", MainSoftData.MutiThreadNum)
    CheckAndAddDirty("SoftBGColor", MainSoftData.SoftBGColor)
    CheckAndAddDirty("NoVariableTip", MainSoftData.NoVariableTip)
    CheckAndAddDirty("BusinessLog", MainSoftData.BusinessLog)
    CheckAndAddDirty("SysLogLevels", MainSoftData.SysLogMinLevel)
    CheckAndAddDirty("LogWarnBubble", MainSoftData.LogWarnBubble)
    CheckAndAddDirty("LogErrorBadge", MainSoftData.LogErrorBadge)
    CheckAndAddDirty("AiApiKey", MainSoftData.HasProp("AiApiKey") ? MainSoftData.AiApiKey : "")
    CheckAndAddDirty("AiApiBaseUrl", MainSoftData.HasProp("AiApiBaseUrl") ? MainSoftData.AiApiBaseUrl : "https://api.openai.com/v1")
    CheckAndAddDirty("AiProvider", MainSoftData.HasProp("AiProvider") ? MainSoftData.AiProvider : "openai")
    CheckAndAddDirty("AiModel", MainSoftData.HasProp("AiModel") ? MainSoftData.AiModel : "")
    CheckAndAddDirty("AiModelList", MainSoftData.HasProp("AiModelList") ? MainSoftData.AiModelList : "")
    CheckAndAddDirty("AiAccessMode", MainSoftData.HasProp("AiAccessMode") ? MainSoftData.AiAccessMode : 2)
    CheckAndAddDirty("AiApprovalMode", MainSoftData.HasProp("AiApprovalMode") ? MainSoftData.AiApprovalMode : 2)
    aiPanelW := (IsSet(MyMainWin) && IsObject(MyMainWin) && MyMainWin.HasProp("aiPanelW")) ? MyMainWin.aiPanelW : (MainSoftData.HasProp("AiPanelWidth") ? MainSoftData.AiPanelWidth : 380)
    CheckAndAddDirty("AiPanelWidth", aiPanelW)
    CheckAndAddDirty("LogicTreeBranchSplit", (MainSoftData.HasProp("LogicTreeBranchSplit") && MainSoftData.LogicTreeBranchSplit) ? 1 : 0)
    CheckAndAddDirty("CheckForeground", MainSoftData.CheckForeground)
    CheckAndAddDirty("IsAdminStart", MainSoftData.IsAdminStart)
    CheckAndAddDirty("CMDTip", MySoftData.CMDTip)
    CheckAndAddDirty("ScreenShotType", MainSoftData.ScreenShotType)
    CheckAndAddDirty("SearchImageType", MainSoftData.SearchImageType)
    CheckAndAddDirty("SearchImageAdaptive", MainSoftData.SearchImageAdaptive)
    CheckAndAddDirty("KeyDownDown", MainSoftData.KeyDownDownType)
    CheckAndAddDirty("AutoLoosenModifier", MainSoftData.AutoLoosenModifier ? 1 : 0)
    CheckAndAddDirty("ContinuousTrigger", MainSoftData.ContinuousTrigger ? 1 : 0)
    CheckAndAddDirty("SharedCopy", MainSoftData.SharedCopy)
    CheckAndAddDirty("GeneralContextMenu", MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : "")
    CheckAndAddDirty("BranchContextMenu",  MainSoftData.HasProp("BranchContextMenu")  ? MainSoftData.BranchContextMenu  : "")
    CheckAndAddDirty("RemarkAutoType", MainSoftData.RemarkAutoType)
    CheckAndAddDirty("MacroStopType", MainSoftData.MacroStopType)
    CheckAndAddDirty("Theme", MainSoftData.Theme)
    ; §23 网络触发：端口（热生效走总线调和，NetworkServer.OnConfigChanged 自动重绑定）
    CheckAndAddDirty("NetworkPort", MainSoftData.NetworkPort)

    ; 工具设置
    CheckAndAddDirty("ToolCheckHotKey", MainSoftData.ToolCheckHotkey)
    CheckAndAddDirty("RecordMacroHotKey", MainSoftData.ToolRecordMacroHotKey)
    CheckAndAddDirty("ToolTextFilterHotKey", MainSoftData.ToolTextFilterHotKey)
    CheckAndAddDirty("ScreenShotHotKey", MainSoftData.ScreenShotHotKey)
    CheckAndAddDirty("FreePasteHotKey", MainSoftData.FreePasteHotKey)
    CheckAndAddDirty("RecordKeyboard", MainSoftData.RecordKeyboard)
    CheckAndAddDirty("RecordMouse", MainSoftData.RecordMouse)
    CheckAndAddDirty("RecordJoy", MainSoftData.RecordJoy)
    CheckAndAddDirty("RecordMouseTrail", MainSoftData.RecordMouseTrail)
    CheckAndAddDirty("RecordMouseTrailSpeed", MainSoftData.RecordMouseTrailSpeed)
    CheckAndAddDirty("RecordHoldMuti", MainSoftData.RecordHoldMuti)
    CheckAndAddDirty("RecordAutoLoosen", MainSoftData.RecordAutoLoosen)
    CheckAndAddDirty("RecordJoyInterval", MainSoftData.RecordJoyInterval)
    CheckAndAddDirty("RecordShowBorder", MainSoftData.RecordShowBorder)
    CheckAndAddDirty("OCRType", MainSoftData.OCRTypeValue)
    CheckAndAddDirty("ExcelBackend", MainSoftData.ExcelBackend)

    ; 状态设置（这些每次都变化，始终写入）
    CheckAndAddDirty("TableIndex", MainSoftData.CurTableID != "" ? MainSoftData.CurTableID : MainSoftData.TabCtrl.Value)
    CheckAndAddDirty("Lang", MainSoftData.Lang)
    CheckAndAddDirty("FontType", MainSoftData.FontType)
    CheckAndAddDirty("FontSize", MainSoftData.HasProp("FontSize") ? MainSoftData.FontSize : 15)
    CheckAndAddDirty("JoyType", MainSoftData.JoyType)
    CheckAndAddDirty("TriggerJoyType", MainSoftData.TriggerJoyType)
    CheckAndAddDirty("JoyLtRtAsButton", MainSoftData.HasProp("JoyLtRtAsButton") ? MainSoftData.JoyLtRtAsButton : true)
    CheckAndAddDirty("PreferredMacroEditor", MainSoftData.PreferredMacroEditor)
    CheckAndAddDirty("MacroTotalCount", MySoftData.MacroTotalCount)
    CheckAndAddDirty("LastShowMonth", MainSoftData.LastShowMonth)
    CheckAndAddDirty("HasSaved", true)
    CheckAndAddDirty("IsReload", true)

    ; CMD窗口设置
    CheckAndAddDirty("CMDPosX", MainSoftData.CMDPosX)
    CheckAndAddDirty("CMDPosY", MainSoftData.CMDPosY)
    CheckAndAddDirty("CMDWidth", MainSoftData.CMDWidth)
    CheckAndAddDirty("CMDHeight", MainSoftData.CMDHeight)
    CheckAndAddDirty("CMDBGColor", MainSoftData.CMDBGColor)
    CheckAndAddDirty("CMDRunBGColor", MainSoftData.CMDRunBGColor)
    CheckAndAddDirty("CMDTransparency", MainSoftData.CMDTransparency)
    CheckAndAddDirty("CMDFontColor", MainSoftData.CMDFontColor)
    CheckAndAddDirty("CMDFontSize", MainSoftData.CMDFontSize)
    ; 内联设置不再经过各独立设置窗口的 SaveData，统一保存这些字段。
    for key in ["CMDLogToFile", "CMDLogFilePath", "CMDLogAutoClear", "StartTipAudio", "EndTipAudio", "StopTipAudio",
        "FixedMenuWheel", "MenuWheelShowTooltip", "MenuWheelSelectMode", "MenuWheelScale",
        "UIPanelShowOnActive",
        "UIPanelBtnWidth", "UIPanelBtnHeight", "UIPanelFontSize", "UIPanelCols", "UIPanelCustom", "UIPanelBall", "UIPanelBallPos", "UIPanelPos",
        "CountDownFontSize", "CountDownAlpha", "CountDownStyle", "CountDownPadZero"]
        CheckAndAddDirty(key, MainSoftData.%key%)

    ; 只写入实际发生变化的配置项（性能提升80%+）
    for key, value in dirtySettings {
        CfgWrite(value, SettingFile, SettingSection, key)
    }
    RMTLogSysMinLevel := MainSoftData.SysLogMinLevel

    ; 设置中心：主题方案与颜色 1~14 走 AppThemeUtil 自有落盘格式（[ThemeColors] + [UserSettings] AppTheme），
    ; 与「主题选项」窗口一致；此处统一在「应用并保存」时落盘。
    try {
        if (IsSet(MainSoftData) && MainSoftData.HasProp("AppTheme"))
            AppThemeUtil.SaveToToml()
    }

    ; §17 保存后不再弹窗/重启：宏表已即时落盘，全局设置走热重载；需要整进程重启用侧栏「重启」
    HotReloadPublish(0, 0)
    try MyMainWin.ClearSettingDirty()
    Toast.Success(GetLang("配置已保存"))
}

CheckValueSettingValid(Name, Value) {
    if (!IsInteger(Value)) {
        RmtDialog.Info(Format("{}{}", Name, GetLang("只能是整数")))
        return false
    }
    return true
}

CheckAllValueSettingValid(threadCount) {
    if (!CheckValueSettingValid(GetLang("点击时间浮动"), MainSoftData.HoldFloat))
        return false

    if (!CheckValueSettingValid(GetLang("每次间隔浮动"), MainSoftData.PreIntervalFloat))
        return false

    if (!CheckValueSettingValid(GetLang("间隔指令浮动"), MainSoftData.IntervalFloat))
        return false

    if (!CheckValueSettingValid(GetLang("坐标X浮动"), MainSoftData.CoordXFloat))
        return false

    if (!CheckValueSettingValid(GetLang("坐标Y浮动"), MainSoftData.CoordYFloat))
        return false

    if (!IsInteger(threadCount) || Integer(threadCount) < -1) {
        RmtDialog.Info(GetLang("多线程数请输入 -1、0 或正整数。"))
        return false
    }

    ; §23 P2-1：端口 1-65535 范围校验（非法值如 99999 会被 htons 截断为 34463，静默监听错端口）。
    ; 拒绝本次保存并还原为 INI 中上次有效值（INI 读取端仍有钳制兜底），同时回写 UI 输入框。
    if (!NetworkIsValidPort(MainSoftData.NetworkPort)) {
        RmtDialog.Info(GetLang("网络触发端口必须是 1-65535 之间的整数，本次保存已取消，端口已还原为上次有效值。"))
        MainSoftData.NetworkPort := NetworkNormalizePort(CfgRead(SettingFile, SettingSection, "NetworkPort", 16888))
        return false
    }

    return true
}

; 设置页切换「宏手柄类型」：仅记录类型；键名统一按 Xbox 存盘，不转换、不立即保存，显示时按类型映射
OnJoyTypeSettingChange(ctrl, info) {
    global MainSoftData
    MainSoftData.JoyType := ctrl.Text
}

; 设置页切换「手柄映射」：仅记录类型；键名统一按 Xbox 存盘，不转换、不立即保存，显示时按类型映射
OnTriggerJoyTypeSettingChange(ctrl, info) {
    global MainSoftData
    MainSoftData.TriggerJoyType := ctrl.Text
}

SaveCurWinPos() {
    MyGui := MainSoftData.MyGui
    MyGui.GetPos(&x, &y, &w, &h)
    ; 保存「缩放系数」而非绝对尺寸：系数 = 窗口尺寸 / (1400×787 基准 × 当前屏幕缩放 fs)。
    ; 加载时按目标屏幕的 fs×系数推导尺寸 → 4K 到 1080p 等跨分辨率切换时窗口比例不变，不会巨大化。
    dpi := DllCall("GetDpiForSystem", "UInt") / 96.0
    dipSW := A_ScreenWidth / dpi
    dipSH := A_ScreenHeight / dpi
    fs := Min(dipSW / 1920, dipSH / 1080)
    scale := (w / dpi) / (1400 * fs)
    if (scale <= 0)
        scale := 1
    CfgWrite(Format("{}π{}πSπ{:.2f}", x, y, scale), SettingFile, SettingSection, "LastWinPos")

    ListenGui := MyVarListenGui.Gui
    if (MyVarListenGui.Gui != "") {
        ListenGui.GetPos(&x, &y, &w, &h)
        CfgWrite(Format("{}π{}", x, y), SettingFile, SettingSection, "ListenVarPos")
    }
}

OnEditCMDTipGui() {
    CMDTipSettingGui.ShowGui()
}

OnTabValueChanged(*) {
    ; 滑块已删除；当前页索引由 MainWin.OnTabChanged 同步到 MainSoftData.TableIndex
}

SwapTableContent(tableItem, indexA, indexB) {
    ; 对象化：条目所有字段（持久+运行时）都挂在 MacroItem 对象上，
    ; 交换数组元素即完成全部字段同步移动，无需逐数组交换
    temp := tableItem.Items[indexA]
    tableItem.Items[indexA] := tableItem.Items[indexB]
    tableItem.Items[indexB] := temp
    tableItem.RebuildIndex()
}

SwapArrValue(Arr, indexA, indexB, valueType := 1) {
    if (valueType == 3) {
        temp := Arr[indexA].Text
        Arr[indexA].Text := Arr[indexB].Text
        Arr[indexB].Text := temp
    }
    else if (valueType == 2) {
        temp := Arr[indexA].Value
        Arr[indexA].Value := Arr[indexB].Value
        Arr[indexB].Value := temp
    }
    else {
        temp := Arr[indexA]
        Arr[indexA] := Arr[indexB]
        Arr[indexB] := temp
    }
}

PluginInit() {
    global MyWorkPool := WorkPool()
    global MyChineseOcr := 0  ; 懒加载：首次使用时才初始化
    global MyEnglishOcr := 0   ; 懒加载：首次使用时才初始化
    global MyPToken := Gdip_Startup()

    InitViGEmPlugin()
    InitNativePlugins()
    InitRMTHttpPlugin()
    SetTimer(CheckOcrIdle, 60000)   ;60秒后，释放Ocr资源
}

; ---------- 图形宏分支调度：主进程版 ----------
; Worker 版在 Thread\WorkUtil.ahk（同名两个函数），由包含链决定用哪一份，
; 共享代码（Main\Util\GraphMacroUtil.ahk）里不再出现角色判断。

ShouldUseGraphWorkers() {
    return WorkPoolEnabled()
}

; 把「第一个之外」的分支丢进本进程的线程池（任务队列存 TableID/ItemID，cmd 用 R1 IPC 编码）
RunBranchDispatch(tableItem, index, branches, fromStart) {
    global MyWorkPool
    tableID := tableItem.ID
    itemID := tableItem.Items[index].ID
    loop branches.Length - 1 {
        cmd := EncodeBatch(EncodeCommand("TR", tableID, itemID, branches[A_Index + 1]))
        tableItem.Items[index].GraphBranchCount++
        GraphPoolLog("分支分配", Format("tab={1} item={2} node={3} 来源=Master/RunGraphSuccessors", tableID, itemID, branches[A_Index + 1]))
        MyWorkPool.taskQueue.Push({ cmd: cmd, tableID: tableID, itemID: itemID, isGraphBranch: true })
        MyWorkPool.Dispatch()
    }
}

InitViGEmPlugin() {
    JoyDebugLog(Format("PluginInit HasJoyMacro={} MutiThreadNum={} WorkPoolEnabled={} IsAdmin={} Script={}"
        , MySoftData.HasJoyMacro, MainSoftData.MutiThreadNum, WorkPoolEnabled(), A_IsAdmin, A_ScriptFullPath), "init")
    if (!MySoftData.HasJoyMacro) {
        JoyDebugLog("PluginInit skip ViGEm (HasJoyMacro=false); will lazy-create on first Joy send", "init")
        return
    }

    isDS4 := MainSoftData.JoyType = "DS4"
    global ViGJoy := isDS4 ? ViGEmDS4() : ViGEmXb360()
    global CurViGJoyType := isDS4 ? "DS4" : "Xbox"

    try instOk := (IsSet(ViGJoy) && ViGJoy.Instance != "")
    catch
        instOk := false
    JoyDebugLog(Format("PluginInit {} created InstanceOK={} DllPath={}"
        , isDS4 ? "ViGEmDS4" : "ViGEmXb360", instOk
        , IsSet(ViGEmDllPath) ? ViGEmDllPath : "(unset)"), "init")
    ; 反回环无需在此武装：已在读取源头 GI_CollectStates 过滤 PID=0x028E(ViGEm) 处理。
}

InitNativePlugins() {
    ; 加载 OpenCV 插件，失败时诊断具体原因（如缺少 VC++ 运行库）
    ocvReason := OpenCvEnsure()
    if (ocvReason != "") {
        JoyDebugLog(Format("OpenCV 插件初始化失败：{}", ocvReason), "init")
        ; 提示只在这里做：这是主进程专属的启动流程，Worker 那边（WorkPluginInit）只写日志。
        ; 共享代码里不再出现「是不是 Worker」的分支。
        try RmtDialog.Info(Format("OpenCV 插件不可用，抓图/搜图等功能将无法使用：`n`n{}", ocvReason), "RMT 提示", 48)
    }

    IBPath := ProjectRootDir "\Plugins\IbInputSimulator.dll"
    DllCall("LoadLibrary", "Str", IBPath)
}

InitRMTHttpPlugin() {
    global RMT_Http := ""
    global RMT_Ai := ""
    global RMT_ASM := ""
    global RMT_Discourse := ""
    global RMT_Sponsors := []
    global RMT_HasDotNet := HasDotNetFramework()
    global RMT_StatusPollFn := ""
    if (!RMT_HasDotNet)
        return

    try {
        RMTPath := EnsureRmtDll()
        RMT_ASM := CLR_LoadLibrary(RMTPath)
        RMT_Http := RMT_ASM.CreateInstance("RMT.Http")
        try RMT_Ai := RMT_ASM.CreateInstance("RMT.AiAssist")
        catch
            RMT_Ai := ""
        ; GetStatus 异步：不阻塞启动主线程。language 供服务端语言统计。
        ; 只在打开软件时上报一次。关闭「在线功能」，或本次是应用内重载，都不访问 getstatus。
        if (ShouldReportOnOpen()) {
            RMT_Http.BeginGetStatus(RMT_VERSION_DISPLAY, GetClientLanguageCode())
            RMT_StatusPollFn := PollRMTServerStatus
            SetTimer(RMT_StatusPollFn, 200)
        }
    } catch as e {
        RMT_Http := ""
        RMT_Ai := ""
        RMT_ASM := ""
        RMT_HasDotNet := false
        JoyDebugLog(Format("RMT Http 插件初始化失败：{} | {} | {}", e.Message, e.What, A_ScriptDir "\Plugins\RMT\RMT.dll"), "init")
    }
}

; 打开软件才上报。关闭开关，或本次启动来自应用内重载，都不访问 getstatus。
ShouldReportOnOpen() {
    global SettingFile, SettingSection
    skip := false
    try {
        raw := String(CfgRead(SettingFile, SettingSection, "SkipDataReport", false))
        skip := (raw = "1" || raw = "true")
        if (skip)
            CfgDelete(SettingFile, SettingSection, "SkipDataReport")
    } catch {
    }
    if (!MainSoftData.HasProp("IsDataReport") || !MainSoftData.IsDataReport)
        return false
    return !skip
}

; 轮询异步 GetStatus 结果
PollRMTServerStatus(*) {
    global RMT_Http, RMT_StatusPollFn
    if (!IsObject(RMT_Http)) {
        if (RMT_StatusPollFn != "")
            SetTimer(RMT_StatusPollFn, 0)
        return
    }
    try {
        st := Integer(RMT_Http.GetStatusState())
    } catch {
        if (RMT_StatusPollFn != "")
            SetTimer(RMT_StatusPollFn, 0)
        return
    }
    if (st = 1)
        return
    if (RMT_StatusPollFn != "")
        SetTimer(RMT_StatusPollFn, 0)
    if (st = 2) {
        try ApplyRMTServerRsp(RMT_Http.TakeStatusResult())
        catch {
        }
    }
}

; 惰性取得 AI CLR 实例（初始化失败时可再试编译加载）
GetRmtAi() {
    global RMT_Ai, RMT_ASM, RMT_HasDotNet
    if (IsObject(RMT_Ai))
        return RMT_Ai
    if (!HasDotNetFramework())
        throw Error(GetLang("需要安装 .NET Framework 4 才能使用 AI 助手"))
    RMTPath := EnsureRmtDll()
    if (!IsObject(RMT_ASM))
        RMT_ASM := CLR_LoadLibrary(RMTPath)
    RMT_Ai := RMT_ASM.CreateInstance("RMT.AiAssist")
    if (!IsObject(RMT_Ai))
        throw Error(GetLang("无法创建 RMT.AiAssist，请重新编译 Plugins\RMT\RMT.dll"))
    RMT_HasDotNet := true
    return RMT_Ai
}

; 惰性取得 Discourse 只读客户端实例（供共享中心使用）
GetDiscourse() {
    global RMT_Discourse, RMT_ASM, RMT_HasDotNet
    if (IsObject(RMT_Discourse))
        return RMT_Discourse
    if (!HasDotNetFramework())
        throw Error(GetLang("需要安装 .NET Framework 4 才能使用共享功能"))
    RMTPath := EnsureRmtDll()
    if (!IsObject(RMT_ASM))
        RMT_ASM := CLR_LoadLibrary(RMTPath)
    RMT_Discourse := RMT_ASM.CreateInstance("RMT.Discourse")
    if (!IsObject(RMT_Discourse))
        throw Error(GetLang("无法创建 RMT.Discourse，请重新编译 Plugins\RMT\RMT.dll"))
    return RMT_Discourse
}

; 共享站点地址：ini 优先（可迁移时只改配置），默认现站点
GetShareServerUrl() {
    global SettingFile, SettingSection
    url := ""
    try url := Trim(CfgRead(SettingFile, SettingSection, "ShareServerUrl", ""))
    if (url == "")
        url := "https://forum.ruomengtu.com"
    return RTrim(url, "/")
}

; 反馈分类 id：bug = bug反馈(42)，idea = 功能建议(44)，都可被 ini 覆盖
GetFeedbackCategoryId(kind := "bug") {
    global SettingFile, SettingSection
    key := (kind = "idea") ? "FeedbackIdeaCategoryId" : "FeedbackBugCategoryId"
    def := (kind = "idea") ? "44" : "42"
    id := ""
    try id := Trim(CfgRead(SettingFile, SettingSection, key, ""))
    if (id == "" || !IsNumber(id))
        id := def
    return Integer(id)
}

; 共享分类 id：默认「共享」分类（id 41），可被 ini 覆盖
GetShareCategoryId() {
    global SettingFile, SettingSection
    id := ""
    try id := Trim(CfgRead(SettingFile, SettingSection, "ShareCategoryId", ""))
    if (id == "" || !IsNumber(id))
        id := "41"
    return Integer(id)
}

; 上传鉴权：apiUser 非空 = Api-Key+Api-Username 模式；空 = User-Api-Key 模式
; 正常路径由设置页「登录论坛」授权后自动写入（用户密钥模式，apiUser 留空）。
; ShareApiUser 仅在需要「管理员 Key 模式」时手工改 ini —— UI 上已不提供该输入框，避免误填导致 403。
GetShareApiUser() {
    global SettingFile, SettingSection
    v := ""
    try v := Trim(CfgRead(SettingFile, SettingSection, "ShareApiUser", ""))
    return v
}

GetShareApiKey() {
    global SettingFile, SettingSection
    v := ""
    try v := Trim(CfgRead(SettingFile, SettingSection, "ShareApiKey", ""))
    return v
}

SetShareAuth(apiUser, apiKey) {
    global SettingFile, SettingSection
    CfgWrite(apiUser, SettingFile, SettingSection, "ShareApiUser")
    CfgWrite(apiKey, SettingFile, SettingSection, "ShareApiKey")
}

ApplyRMTServerRsp(rspStr) {
    global RMT_Sponsors, MyMainWin
    if (rspStr = "")
        return
    try {
        rsp := JSON.parse(rspStr)
        if (rsp.Has("sponsors"))
            RMT_Sponsors := ParseSponsorList(rsp["sponsors"])
        if (IsObject(MyMainWin))
            MyMainWin.ApplyThankSponsors()
    }
}

; 赞助 logo 文件名对应资源仓库 Common 标签下的图片
GetSponsorLogoBaseUrl() {
    return "https://gh-proxy.com/https://github.com/zclucas/RMTAssets/releases/download/Common/"
}

GetSponsorLogoDir() {
    return A_WorkingDir "\Images\Sponsor"
}

; 回包 logo 只取文件名，例如 12324.png
SponsorLogoFileName(logo) {
    logo := Trim(logo)
    if (logo == "")
        return ""
    if (RegExMatch(logo, "i)^https?://")) {
        logo := RegExReplace(logo, "\?.*$", "")
        pos := InStr(logo, "/", , -1)
        if (pos)
            logo := SubStr(logo, pos + 1)
    }
    logo := RegExReplace(logo, "^[\\/]+")
    if (InStr(logo, "/") || InStr(logo, "\") || InStr(logo, ".."))
        return ""
    if (!RegExMatch(logo, "i)\.(png|jpe?g|gif|webp|bmp)$"))
        return ""
    if (RegExMatch(logo, "[<>:|?*]"))
        return ""
    return logo
}

; 本地 Images\Sponsor 已有则直接用，否则从 Common 发布地址下载
EnsureSponsorLogo(logo) {
    name := SponsorLogoFileName(logo)
    if (name == "")
        return ""
    dir := GetSponsorLogoDir()
    if (!DirExist(dir)) {
        try DirCreate(dir)
        catch
            return ""
    }
    path := dir "\" name
    if (FileExist(path)) {
        try {
            if (FileGetSize(path) > 0)
                return path
        }
    }
    if (FileExist(path))
        try FileDelete(path)
    if (!DownloadSponsorLogo(GetSponsorLogoBaseUrl() . name, path))
        return ""
    if (!FileExist(path))
        return ""
    try {
        if (FileGetSize(path) <= 0) {
            FileDelete(path)
            return ""
        }
    } catch {
        return ""
    }
    return path
}

DownloadSponsorLogo(url, savePath) {
    try {
        req := ComObject("Msxml2.XMLHTTP")
        req.open("GET", url, true)
        req.send()
        start := A_TickCount
        while (req.readyState != 4) {
            if (A_TickCount - start > 12000)
                return false
            Sleep(50)
        }
        if (req.status != 200)
            return false
        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(req.responseBody)
        stream.SaveToFile(savePath, 2)
        stream.Close()
        return true
    } catch {
        if (FileExist(savePath))
            try FileDelete(savePath)
        return false
    }
}

_RspText(v) {
    if (v == "" || IsObject(v))
        return ""
    return Trim(String(v))
}

_RspMapText(m, key) {
    if (!(m is Map) || !m.Has(key))
        return ""
    return _RspText(m[key])
}

; 归一化 getstatus.sponsors：name / logo / url / desc / ext[{key,value}]
ParseSponsorList(arr) {
    list := []
    if (!(arr is Array))
        return list
    for item in arr {
        if (!(item is Map))
            continue
        name := _RspMapText(item, "name")
        desc := _RspMapText(item, "desc")
        logo := SponsorLogoFileName(_RspMapText(item, "logo"))
        url := _RspMapText(item, "url")
        if (!RegExMatch(url, "i)^https?://"))
            url := ""
        if (name == "" && desc == "" && logo == "")
            continue
        tags := []
        if (item.Has("ext") && item["ext"] is Array) {
            for e in item["ext"] {
                if (!(e is Map))
                    continue
                k := _RspMapText(e, "key")
                val := _RspMapText(e, "value")
                if (k == "" && val == "")
                    continue
                tags.Push(k != "" && val != "" ? (k . ": " . val) : (val != "" ? val : k))
            }
        }
        id := item.Has("id") ? item["id"] : ""
        list.Push(Map("id", id, "name", name, "logo", logo, "url", url, "desc", desc, "ext", tags))
    }
    return list
}

HasDotNetFramework() {
    try {
        fwDir := EnvGet("SystemRoot") "\Microsoft.NET\Framework" (A_PtrSize = 8 ? "64" : "")
        loop files fwDir "\*", "D" {
            if (FileExist(A_LoopFilePath "\mscorlib.dll") && StrCompare(A_LoopFileName, "v4.0") >= 0)
                return true
        }
    }
    return false
}

OnToolAlwaysOnTop(*) {
    global MySoftData, MainSoftData
    state := UIControls.AlwaysOnTop.Value
    if (state) {
        MainSoftData.MyGui.Opt("+AlwaysOnTop")
    }
    else {
        MainSoftData.MyGui.Opt("-AlwaysOnTop")
    }
}

InitFilePath() {
    if (!DirExist(A_WorkingDir "\Setting")) {
        DirCreate(A_WorkingDir "\Setting")
    }
    if (!DirExist(A_WorkingDir "\Setting\" MySoftData.CurSettingName)) {
        DirCreate(A_WorkingDir "\Setting\" MySoftData.CurSettingName)
    }

    ; 在任何默认宏表写入之前迁移直接覆盖安装的旧方案；失败必须中止加载。
    Compat_UpgradeDir(A_WorkingDir "\Setting\" MySoftData.CurSettingName)

    if (!DirExist(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UseExplain")) {
        DirCreate(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UseExplain")
    }

    if (!DirExist(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot")) {
        DirCreate(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot")
    }

    filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\使用说明&署名.txt"
    if (!FileExist(filePath)) {
        str1 := GetLang("协议：CC BY - NC - SA 4.0")
        str2 := GetLang("原始来源：RMT(若梦兔) 软件导出")
        str3 := GetLang("说明：仅限非商业用途，转载请注明来源并保持相同协议")
        Str := Format("{}`n{}`n{}", str1, str2, str3)
        FileAppend(Str, filePath, "UTF-16")
    }

    if (!DirExist(A_WorkingDir "\Images")) {
        DirCreate(A_WorkingDir "\Images")
    }
    if (!DirExist(A_WorkingDir "\Images\Soft")) {
        DirCreate(A_WorkingDir "\Images\Soft")
    }

    if (!DirExist(A_WorkingDir "\Images\ScreenShot")) {
        DirCreate(A_WorkingDir "\Images\ScreenShot")
    }

    if (!DirExist(A_WorkingDir "\Images\FreePaste")) {
        DirCreate(A_WorkingDir "\Images\FreePaste")
    }

    InitDataFilePaths(A_WorkingDir)
    ; 旧格式迁移只在主进程做：Worker 只读配置（见 Thread\WorkUtil.ahk 的 InitWorkFilePath）。
    global SearchComboFile, TimeDataFile
    oldSearchMultiFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SearchMultiFile.toml"
    if (!FileExist(SearchComboFile) && FileExist(oldSearchMultiFile))
        try FileMove(oldSearchMultiFile, SearchComboFile)
    CompatPromoteLegacyFile(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\TimeFile.toml", TimeDataFile)
    ; 旧扁平布局的宏文件就地展开成三级段。放这里而不是 LoadCurMacroSetting：
    ; 后者是主程序与 Worker 共用的，而展开依赖 IniImportUtil（Worker 不加载）。
    ExpandFlatMacroFileIfNeeded()
}

StopMacro(tableItem, itemIndex, playStopTip := false) {
    if (!IsObject(tableItem))
        tableItem := GetTableByID(String(tableItem))
    if (!tableItem)
        return
    if (IsObject(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, itemIndex.ID)
    } else if (!IsNumber(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, String(itemIndex))
    }
    if (itemIndex < 1)
        return
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    if (playStopTip && item.StopTipSound == 2)
        PlayTipSound(3)
    item.GraphBranchCount := 0

    ; 多线程：搜图等 DllCall 会卡住 Worker，协作式 Killed/ST 不可靠，直接杀进程
    if (WorkPoolEnabled()) {
        hasWork := item.IsWorkIndex || MyWorkPool.HasItemWork(tableItem.ID, item.ID)
        if (hasWork) {
            MyWorkPool.ForceStopItem(tableItem.ID, item.ID)
            return
        }
    }

    ; 主进程内执行的宏：置 Killed 标记后，宏循环会自行退出并由 FinalizeMacroRun 设置终止状态
    KillTableItemMacro(tableItem, itemIndex)
    if (item.TriggerType == 4)
        SetTableItemState(tableItem, itemIndex, 3)
}

; Worker 多分支图形宏：接收 Worker 提交的分支节点列表，入队并分派，回复确认
HandleWorkerGraphBranches(wd, tableID, itemID, nodeArr) {
    previousCritical := A_IsCritical
    Critical("On")
    try {
        if (wd.stopRequested || !wd.taskID || wd.tableID != tableID || wd.itemID != itemID)
            return
        tableItem := GetTableByID(tableID)
        item := GetItemByIndex(tableItem, GetItemIndexInTable(tableItem, itemID))
        if (!item || item.Killed || item.HasOwnProp("Stopping"))
            return
        wd.isGraphBranch := true
        item.GraphBranchCount := Max(1, item.GraphBranchCount) + nodeArr.Length
        for nodeSerial in nodeArr
            MyWorkPool.taskQueue.Push({cmd: EncodeBatch(EncodeCommand("TR", tableID, itemID, nodeSerial))
                , tableID: tableID, itemID: itemID, isGraphBranch: true})
        ; 确认已入队即可，后续分支可在源 Worker 完成后复用该槽位。
        MyWorkPool.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("GA", tableID, itemID)))
    } finally Critical(previousCritical)
    MyWorkPool.Dispatch()
}

SetGlobalArray(name, value) => CommitGlobalData("SA", [name, value])
CloneGlobalArray(source, name) => SetGlobalArray(name, CloneArray(IsObject(source) ? source : MySoftData.ArrayMap[source]))
DeleteGlobalArray(name) => CommitGlobalData("DA", [name])
ModifyGlobalArray(name, row, index, isArrayValue, value) => CommitGlobalData("MA", [name, row, index, value])
InsertGlobalArray(name, row, index, isArrayValue, value) => CommitGlobalData("IA", [name, row, index, value])
RemoveAtGlobalArray(name, row, index) => CommitGlobalData("RA", [name, row, index])
SetGlobalVariable(names, values, ignoreExist) => CommitGlobalData("SV", [names, values, ignoreExist])
DelGlobalVariable(names) => CommitGlobalData("DV", [names])

; 主进程为全局数据排序。提交后的权威值按相同顺序发给所有 Worker。
CommitGlobalData(opcode, args) {
    previousCritical := A_IsCritical
    Critical("On")
    try {
        variables := MySoftData.VariableMap
        arrays := MySoftData.ArrayMap
        commands := []
        switch opcode {
            case "SV":
                names := args[1]
                values := args[2]
                ignoreExist := args[3]
                updates := []
                for i, name in names {
                    value := ignoreExist && variables.Has(name) ? variables[name] : values[i]
                    commands.Push(EncodeCommand("SV", name, JSON.stringify([value])))
                    updates.Push([name, value])
                }
                for pair in updates
                    variables[pair[1]] := pair[2]
            case "DV":
                for name in args[1] {
                    if (variables.Has(name))
                        variables.Delete(name)
                    commands.Push(EncodeCommand("DV", name))
                }
            case "DA":
                if (arrays.Has(args[1]))
                    arrays.Delete(args[1])
                commands.Push(EncodeCommand("DA", args[1]))
            case "SA", "MA", "IA", "RA":
                name := args[1]
                if (opcode == "SA") {
                    root := args[2]
                } else {
                    root := CloneArray(arrays[name])
                    target := args[2] == 0 ? root : root[Integer(args[2])]
                    index := Integer(args[3])
                    switch opcode {
                        case "MA": target[index] := args[4]
                        case "IA": target.InsertAt(index, args[4])
                        case "RA": target.RemoveAt(index)
                    }
                }
                commands.Push(EncodeCommand("SA", name, JSON.stringify([root])))
                arrays[name] := root
            default:
                throw Error("Unknown global data operation")
        }
        if (commands.Length && WorkPoolEnabled())
            MyWorkPool.BroadcastPayloadEx(0, EncodeBatch(commands*))
    } finally Critical(previousCritical)
    if (commands.Length)
        SetTimer(RefreshGlobalDataView, -1)
}

RefreshGlobalDataView() {
    try MyVarListenGui.Refresh()
}

SetCMDTipValue(value) {
    MyWorkPool.Broadcast("CT", value)
}

CMDReport(CMDStr) {
    ; 主进程以 CMDTip 为准：Worker 上报与关闭存在竞态，关闭后丢弃迟到的 RP
    if (!MySoftData.CMDTip)
        return
    MyCMDTipGui.ShowGui(CMDStr)
}

; 「输出→指令窗口」专用：不经过 CMDTip 全局开关门控。
; 设计语义：指令显示(CMDTip)=是否常驻显示指令流水；指令窗口输出=单独把内容送进并显示指令窗口。
; 由 MyCMDTipForceAction 调用（主进程直接展示，Worker 经 FR 指令转发到本函数）。
CmdTipForceShow(CMDStr) {
    MyCMDTipGui.ShowGui(CMDStr)
}

;0默认状态 1运行 2暂停 3终止
; 表身份 = TableItem 对象引用（位置不代表身份）
SetTableItemState(tableItem, itemIndex, State) {
    ; Worker 经 IPC 回发的 IS/PS 事件参数是字符串；统一转整数。
    State := Integer(State)

    if (!IsObject(tableItem))
        tableItem := GetTableByID(String(tableItem))
    if (!tableItem)
        return
    if (IsObject(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, itemIndex.ID)
    } else if (!IsNumber(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, String(itemIndex))
    }
    if (itemIndex < 1)
        return
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    LastState := item.ColorState

    if (LastState == 0 && (State == 2 || State == 3)) {
        ; 终止过程中宏已正常结束（状态已归 0），不再应用终止/暂停状态
        GraphPoolLog("状态忽略-已正常结束", Format("tab={1} item={2} 收到状态={3} 当前=0", tableItem.ID, item.ID, State))
        return
    }

    if (State == 2 && LastState != 1)
        return
    if (State == 3 && LastState == 3)
        return

    if (State == 3) {
        StopCancelTableItemTimer(tableItem, itemIndex)
        timerFunc := CancelTableItemStopState.Bind(tableItem, itemIndex)
        timerKey := tableItem.ID "|" item.ID
        CancelTableItemTimerMap[timerKey] := timerFunc
        SetTimer(timerFunc, -5000)
    }
    else if (LastState == 3)
        StopCancelTableItemTimer(tableItem, itemIndex)

    UpdateMacroRunningCount(LastState, State)
    item.ColorState := State
    RefreshItemColorUI(tableItem, itemIndex)

    ; 悬浮显示随宏生命周期：停止（0）、终止（3）时关闭
    if (State == 0 || State == 3)
        HudStopItem(tableItem, itemIndex)
    if (tableItem.Symbol == "UI" && IsSet(MyUIMacroGui))
        MyUIMacroGui.UpdateButtonsState(itemIndex, State)
}

RefreshItemColorUI(tableItem, itemIndex) {
    global MyMainWin
    MyMainWin.UpdateItemColor(tableItem, itemIndex)
}

CancelTableItemStopState(tableItem, itemIndex) {
    if (!IsObject(tableItem))
        return
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    if (item.ColorState == 3) {
        if (item.IsWorkIndex != 0)
            return

        ; 同步清除 Killed，確保狀態完全恢復可再次觸發
        item.Killed := false
        ; 通过 SetTableItemState 恢复默认状态（自动触发浮动画板同步等逻辑）
        SetTableItemState(tableItem, itemIndex, 0)
    }
}

global CancelTableItemTimerMap := Map()

StopCancelTableItemTimer(tableItem, itemIndex) {
    if (IsObject(tableItem)) {
        item := tableItem.Items[itemIndex]
        timerKey := tableItem.ID "|" (item ? item.ID : "")
    } else {
        timerKey := String(tableItem) "|" itemIndex
    }
    if (CancelTableItemTimerMap.Has(timerKey)) {
        SetTimer(CancelTableItemTimerMap[timerKey], 0)
        CancelTableItemTimerMap.Delete(timerKey)
    }
}

SetItemPauseState(tableItem, itemIndex, state) {
    if (!IsObject(tableItem))
        tableItem := GetTableByID(String(tableItem))
    if (!tableItem)
        return
    if (IsObject(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, itemIndex.ID)
    } else if (!IsNumber(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, String(itemIndex))
    }
    if (itemIndex < 1)
        return
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    previousCritical := A_IsCritical
    Critical("On")
    try {
        item.Pause := state
        if (WorkPoolEnabled())
            MyWorkPool.SendItemPause(tableItem.ID, item.ID, state)
    } finally Critical(previousCritical)

    LastColorState := item.ColorState
    if (LastColorState == 1 && state == 1)
        SetTableItemState(tableItem, itemIndex, 2)
    else if (LastColorState == 2 && state == 0)
        SetTableItemState(tableItem, itemIndex, 1)

}

;恢复意外退出残留的脏状态，后面要换成热重载就会要
RecoverAllDirtyStates() {
    ; 脏状态意味着宏已不在运行，同时清除悬浮窗，避免残留无主窗口
    HudStopAll()
    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        for index, item in tableItem.Items {
            if (item.ColorState != 0) {
                item.ColorState := 0
                item.IsWorkIndex := 0
                RefreshItemColorUI(tableItem, index)
            }
        }
    }

    tableItem := MySoftData.SpecialTableItem
    if (tableItem.Items.Length >= 1 && tableItem.Items[1].ColorState != 0) {
        tableItem.Items[1].ColorState := 0
        RefreshItemColorUI(tableItem, 1)
    }

    if (MySoftData.MacroRunningCount != 0) {
        MySoftData.MacroRunningCount := 0
        MySoftData.IsMacroWorking := false
        UpdateMacroTrayIcon()
        MyCMDTipGui.OnToggleMacroWorkState()
    }
}

CleanupAllMacroStates() {
    RecoverAllDirtyStates()
}

MsgBoxContent(content, title := "") {
    ; 主窗句柄回传前适配器还没建（启动早期可能因插件初始化失败而弹框），此时跳过闪烁
    if (IsObject(MainSoftData.MyGui))
        MainSoftData.MyGui.Flash()
    SoundPlay "*-1"
    MyMsgboxGui.ShowGui(content, title)
}

ViGJoySetState(JoyType, Key, Value) {
    JoyDebugLog(Format("ViGJoySetState enter type={} key={} value={} IsSet(ViGJoy)={}"
        , JoyType, Key, Value, IsSet(ViGJoy)), "vigem")

    isDS4 := MainSoftData.JoyType = "DS4"
    wantType := isDS4 ? "DS4" : "Xbox"
    if (!IsSet(ViGJoy) || !IsSet(CurViGJoyType) || CurViGJoyType != wantType) {
        if (IsSet(ViGJoy) && IsSet(CurViGJoyType))
            JoyDebugLog(Format("ViGJoySetState switch device {} -> {} (JoyType={})", CurViGJoyType, wantType, MainSoftData.JoyType), "vigem")
        else
            JoyDebugLog(Format("ViGJoySetState create {} (JoyType={})", wantType, MainSoftData.JoyType), "vigem")
        global ViGJoy := isDS4 ? ViGEmDS4() : ViGEmXb360()
        global CurViGJoyType := wantType
    }

    try instEmpty := (ViGJoy.Instance == "")
    catch as e {
        JoyDebugLog(Format("ViGJoySetState Instance check failed: {}", e.Message), "vigem")
        return
    }
    if (instEmpty) {
        JoyDebugLog("ViGJoySetState ABORT: Instance empty (ViGEmBus 未就绪/创建失败)", "vigem")
        return
    }

    try {
        if (JoyType == "Btn") {
            if (!ViGJoy.Buttons.Has(Key)) {
                JoyDebugLog(Format("ViGJoySetState ABORT: Buttons has no key '{}'", Key), "vigem")
                return
            }
            ViGJoy.Buttons[Key].SetState(Value)
            ; 反回环已由读取源头 GI_CollectStates 过滤 PID=0x028E(ViGEm) 处理，无需在此记账。
        } else if (JoyType == "Axis") {
            if (!ViGJoy.Axes.Has(Key)) {
                JoyDebugLog(Format("ViGJoySetState ABORT: Axes has no key '{}'", Key), "vigem")
                return
            }
            ViGJoy.Axes[Key].SetState(Value)
        } else if (JoyType == "Dpad") {
            ViGJoy.Dpad.SetState(Key)
        } else {
            JoyDebugLog(Format("ViGJoySetState ABORT: unknown JoyType '{}'", JoyType), "vigem")
            return
        }
        JoyDebugLog(Format("ViGJoySetState OK type={} key={} value={}", JoyType, Key, Value), "vigem")
    } catch as e {
        JoyDebugLog(Format("ViGJoySetState EXCEPTION: {} | {}", e.Message, e.What), "vigem")
    }
}

OutputTipContent(content) {
    CursorOutputTip.Show(content)
}

; 「输出 → 悬浮显示」：Worker 送已渲染文本，主进程负责建窗与更新内容。
; 位置等配置取自主进程这份副本，拖动写回时不会与 Worker 的旧配置冲突。
;
; 统一入队，不在此处直接更新窗口，原因同 case "IP"：本函数运行在 OnMessage
; 上下文，同步调用 XAMLHost.Update（内部为 SendMessage）会与 daemon 的窗口
; 消息回传互锁，表现为「指令显示与悬浮显示只能有一个工作」。
; 由一次性 SetTimer(-1) 移出消息循环执行，同一控件的多帧更新自动合并。
HudOutputShow(serialStr, content, tID, iID) {
    HudQueueUpdate(serialStr, content, tID, iID)
}

ToolTipContent(content) {
    MySoftData.ToolTipText := content
    MySoftData.ToolTipEndTime := A_TickCount + 5000
    SetTimer(ToolTipTimer, 100)
    ToolTip(content)
}

ToolTipTimer() {
    if (A_TickCount >= MySoftData.ToolTipEndTime) {
        ; 超过显示时间，隐藏ToolTip并停止定时器
        ToolTip
        SetTimer(ToolTipTimer, 0)
    } else {
        ; 仍在显示时间内，更新ToolTip
        ToolTip(MySoftData.ToolTipText)
    }
}

ExcuteRMTCMDAction(Cmd) {
    ; 新格式: RMT指令⫶类别⫶指令 → paramArr[1]=RMT指令, paramArr[2]=类别, paramArr[3]=指令
    paramArr := StrSplit(Cmd, InStr(Cmd, "⫶") ? "⫶" : "_")
    if (paramArr.Length < 3 || ApplyRmtInputControl(paramArr[3]))
        return
    switch GetLangKey(paramArr[3]) {
        case "截图":
            OnToolScreenShot()
        case "截图提取文本":
            OnToolTextFilterScreenShot()
        case "自由贴":
            OnToolFreePaste()
        case "开启指令显示":
            MySoftData.CMDTip := true
            SetCMDTipValue(true)
            if (UIControls.CMDTip)
                UIControls.CMDTip.Value := true
            MyCMDTipGui.ShowGui("开启指令显示")
        case "关闭指令显示":
            MySoftData.CMDTip := false
            SetCMDTipValue(false)
            if (UIControls.CMDTip)
                UIControls.CMDTip.Value := false
            ; 完整关闭（清内容+隐藏），勿仅 Gui.Hide；多线程下后续 RP 由 CMDReport 按 CMDTip 拦截
            MyCMDTipGui.Hide()
        case "开启变量监视":
            RefreshListenVarGui(true)
        case "关闭变量监视":
            if (!IsObject(MyVarListenGui.Gui))
                return

            try {
                style := WinGetStyle(MyVarListenGui.Gui.Hwnd)
                isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                if (isVisible) {
                    MyVarListenGui.Gui.Hide()
                    CfgWrite(false, SettingFile, SettingSection, "IsOpenListenVar")
                }
            }
        case "显示菜单":
            OpenMenuWheel(paramArr.Length >= 4 ? paramArr[4] : 1, false)
        case "关闭菜单":
            CloseMenuWheel()
        case "打开界面窗口":
            ; §15.5：打开界面宏的全部面板；没有可用的界面窗口时该指令无效（无操作）
            if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
                MyUIMacroGui.ShowAllPanels()
        case "关闭界面窗口":
            ; §15.5：关闭全部界面宏面板
            if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
                MyUIMacroGui.HideAllPanels()
        case "禁用模块":
            ; §2：禁用指定页签下的模块（paramArr[4]=表 ID, paramArr[5]=模块路径身份 FoldID）
            RmtCmdSetFoldForbidState(paramArr, true)
        case "取消禁用模块":
            RmtCmdSetFoldForbidState(paramArr, false)
        case "休眠":
            OnSuspendHotkey()
        case "暂停所有宏":
            SetPauseState(true)
        case "恢复所有宏":
            SetPauseState(false)
        case "终止所有宏":
            OnKillAllMacro()
        case "重载":
            MenuReload()
        case "关闭软件":
            ExitApp()
    }
}

; §2 RMT指令「禁用模块/取消禁用模块」执行端：按表 ID 和模块路径身份切换 fold 启用状态，
; 实时重绑触发键 + HotReloadBus 广播（与折叠开关热键同一生效链路）
RmtCmdSetFoldForbidState(paramArr, forbid) {
    global MySoftData, MyHotReloadBus
    if (paramArr.Length < 5)
        return
    tableSymbol := paramArr[4]
    foldID := paramArr[5]
    if (tableSymbol == "" || foldID == "")
        return
    tableItem := GetTableByID(tableSymbol)
    if (!tableItem)
        tableItem := GetTableBySymbol(tableSymbol)
    if (!tableItem)
        return
    fold := tableItem.GetFold(foldID)
    if (!fold)
        return
    fold.ForbidState := forbid
    RebindAllTriggerKeys()
    ; §18 RMT指令禁用模块：即时落盘 + 广播（与折叠开关热键同链路）
    HotReloadPublish(tableItem.Index, 0)
    tip := (forbid ? GetLang("模块已禁用：") : GetLang("模块已启用：")) (fold.Remark == "" ? fold.ID : fold.Remark)
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tip)
}

ScreenShot(X1, Y1, X2, Y2, FileName) {
    width := X2 - X1
    height := Y2 - Y1
    pBitmap := Gdip_BitmapFromScreen(X1 "|" Y1 "|" width "|" height)
    Gdip_SaveBitmapToFile(pBitmap, FileName)
    ; 释放位图资源
    Gdip_DisposeImage(pBitmap)
}

OnToolTextFilterGetArea(x1, y1, x2, y2) {
    filePath := A_WorkingDir "\Images\ScreenShot\TextFilter.png"
    ScreenShot(x1, y1, x2, y2, filePath)
    ocr := GetChineseOcr() ; v6 统一多语言模型，不再区分语言
    result := ocr.ocr_from_file(filePath)
    UIControls.ToolText.Value := result
    SetClipboard(result)
}

OnToolTextCheckScreenShot() {
    ; 如果剪贴板中有图像
    if DllCall("IsClipboardFormatAvailable", "uint", 8)  ; 8 是 CF_BITMAP 格式
    {
        filePath := A_WorkingDir "\Images\ScreenShot\TextFilter.png"
        SaveClipToBitmap(filePath)
        ocr := GetChineseOcr() ; v6 统一多语言模型，不再区分语言
        result := ocr.ocr_from_file(filePath)
        UIControls.ToolText.Value := result
        SetClipboard(result)
        ; 停止监听
        SetTimer(, 0)
    }
}

TogGetSelectArea(isEnable, action := "") {
    global SelectAreaState
    if (isEnable && action != "") {
        SelectAreaState := {breakFlag: false, winPos: "", firstPos: false, sx: 0, sy: 0}
        MainSoftData.GetAreaAction := action
        ; 透传左键事件给外部截图工具，记录屏幕坐标并绘制辅助框。
        ToolTipContent(GetLang("请框选搜索范围"))
        SetSystemCursor("CROSS")
        Hotkey("~*LButton", OnGetSelectAreaDown, "On")
        Hotkey("~*LButton Up", OnGetSelectAreaUp, "On")
        Hotkey("~*RButton", OnGetSelectAreaCancel, "On")
    }
    else {
        MainSoftData.GetAreaAction := ""
        SetTimer(SelectAreaDraw, 0)
        SelectAreaHo.Hide()
        MySoftData.ToolTipEndTime := 0
        ToolTip()
        SetSystemCursor()
        Hotkey("~*LButton", "Off")
        Hotkey("~*LButton Up", "Off")
        Hotkey("~*RButton", "Off")
    }
}

OnGetSelectAreaDown(*) {
    ; 外部截图工具自行框选，不叠加 RMT 的边缘吸附。
    BeginSelectArea(false)
    SetTimer(SelectAreaDraw, 30)
}

OnGetSelectAreaUp(*) {
    global SelectAreaState
    SetTimer(SelectAreaDraw, 0)
    UpdateSelectAreaPosition()
    action := MainSoftData.GetAreaAction
    started := SelectAreaState.firstPos
    TogGetSelectArea(false)
    if (action == "" || !started)
        return
    if (SelectAreaState.winPos != "" && ObjHasOwnProp(SelectAreaState.winPos, "W") && SelectAreaState.winPos.W > 0 && SelectAreaState.winPos.H > 0) {
        x1 := SelectAreaState.winPos.X
        y1 := SelectAreaState.winPos.Y
        x2 := x1 + SelectAreaState.winPos.W
        y2 := y1 + SelectAreaState.winPos.H
    } else {
        ; 点击未拖动：起终点相同
        x1 := MainSoftData.StartAreaPosX
        y1 := MainSoftData.StartAreaPosY
        x2 := x1
        y2 := y1
    }
    action(x1, y1, x2, y2)
}

OnGetSelectAreaCancel(*) {
    TogGetSelectArea(false)
}

TogSelectArea(isEnable, action := "", showPrompt := true) {
    global SelectAreaState
    if (isEnable && action != "") {
        MainSoftData.SelectAreaAction := action
        if (showPrompt)
            ToolTipContent(GetLang("请框选截图范围"))
        SetSystemCursor("CROSS")
        Hotkey("*LButton", SelectAreaDown, "On")
        Hotkey("*LButton Up", SelectAreaUp, "On")
        Hotkey("*RButton", SelectAreaCancel, "On")

        SelectAreaState := {breakFlag: false, winPos: "", firstPos: false, sx: 0, sy: 0}
        while (!SelectAreaState.breakFlag) {
            Sleep(30)
        }
        SelectAreaHo.Hide()
        SetSystemCursor()
        Hotkey("*LButton", "Off")
        Hotkey("*LButton Up", "Off")
        Hotkey("*RButton", "Off")
        MySoftData.ToolTipEndTime := 0
        MainSoftData.SelectAreaAction := ""
        ToolTip()
    }
    else {
        MySoftData.ToolTipEndTime := 0
        MainSoftData.SelectAreaAction := ""
        SelectAreaState.breakFlag := true
        SetTimer(SelectAreaDraw, 0)
        Hotkey("*LButton", "Off")
        Hotkey("*LButton Up", "Off")
        Hotkey("*RButton", "Off")
        SetSystemCursor()
        SelectAreaHo.Hide()
        ToolTip()
    }
}

SelectAreaDown(*) {
    BeginSelectArea(true)
    SetTimer(SelectAreaDraw, 30)
}

SelectAreaUp(*) {
    global SelectAreaState
    SetTimer(SelectAreaDraw, 0)
    UpdateSelectAreaPosition()
    SelectAreaHo.Hide()

    action := MainSoftData.SelectAreaAction
    if (action != "") {
        if (SelectAreaState.winPos != "") {
            x1 := SelectAreaState.winPos.X
            y1 := SelectAreaState.winPos.Y
            x2 := x1 + SelectAreaState.winPos.W
            y2 := y1 + SelectAreaState.winPos.H
            action(x1, y1, x2, y2)
        } else {
            action(0, 0, 0, 0)
        }
    }
    SelectAreaState.breakFlag := true
}

SelectAreaCancel(*) {
    global SelectAreaState
    SetTimer(SelectAreaDraw, 0)
    SelectAreaState.winPos := ""
    SelectAreaState.firstPos := false
    SelectAreaState.breakFlag := true
    SelectAreaHo.Hide()
}

BeginSelectArea(snapToEdges) {
    global SelectAreaState
    CoordMode("Mouse", "Screen")
    MouseGetPos(&sx, &sy)
    SelectAreaState.sx := sx
    SelectAreaState.sy := sy
    SelectAreaState.firstPos := true
    SelectAreaState.snapToEdges := snapToEdges
    SelectAreaState.winPos := {X: sx, Y: sy, W: 0, H: 0}
    MainSoftData.StartAreaPosX := sx
    MainSoftData.StartAreaPosY := sy
}

UpdateSelectAreaPosition() {
    global SelectAreaState
    if (!SelectAreaState.firstPos)
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&ex, &ey)
    if (SelectAreaState.snapToEdges) {
        _snap := SnapPointToCandidates(ex, ey, 6)
        ex := _snap.X
        ey := _snap.Y
    }
    sx := SelectAreaState.sx, sy := SelectAreaState.sy
    SelectAreaState.winPos := {X: Min(sx, ex), Y: Min(sy, ey), W: Abs(ex - sx), H: Abs(ey - sy)}
}

SelectAreaDraw(*) {
    global SelectAreaState
    UpdateSelectAreaPosition()
    if (SelectAreaState.winPos != "" && ObjHasOwnProp(SelectAreaState.winPos, "W") && SelectAreaState.winPos.W > 0 && SelectAreaState.winPos.H > 0) {
        x1 := SelectAreaState.winPos.X
        y1 := SelectAreaState.winPos.Y
        x2 := x1 + SelectAreaState.winPos.W
        y2 := y1 + SelectAreaState.winPos.H
        SelectAreaHo.Show(x1, y1, x2, y2)
        MySoftData.ToolTipText := "开始X:" x1 " 开始Y:" y1 "`n结束X:" x2 " 结束Y:" y2
        MySoftData.ToolTipEndTime := A_TickCount + 5000
    } else {
        SelectAreaHo.Hide()
    }
}

; ============================================================
; §18 框选自动吸附：光标下 窗口+子控件 边缘吸附（参考 PixPin）
; 保留手动拖拽：仅当光标距边缘 ≤ 容差时吸附，其余位置自由移动
; ============================================================
global SnapRectsTmp := []

EnumSnapChildProc(hwnd, lParam) {
    global SnapRectsTmp
    r := Buffer(16)
    if (DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", r)) {
        SnapRectsTmp.Push({L: NumGet(r, 0, "Int"), T: NumGet(r, 4, "Int"), R: NumGet(r, 8, "Int"), B: NumGet(r, 12, "Int")})
    }
    return true
}

; 取光标下顶层窗口 + 其全部子控件的屏幕矩形（吸附候选）
GetSnapCandidates(mx, my) {
    global SnapRectsTmp
    SnapRectsTmp := []
    pt := (my << 32) | (mx & 0xFFFFFFFF)   ; POINT 打包
    hwnd := DllCall("WindowFromPoint", "Int64", pt, "Ptr")
    if (!hwnd)
        return SnapRectsTmp
    top := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")   ; GA_ROOT
    if (!top)
        top := hwnd
    r := Buffer(16)
    if (DllCall("GetWindowRect", "Ptr", top, "Ptr", r)) {
        SnapRectsTmp.Push({L: NumGet(r, 0, "Int"), T: NumGet(r, 4, "Int"), R: NumGet(r, 8, "Int"), B: NumGet(r, 12, "Int")})
    }
    cb := CallbackCreate(EnumSnapChildProc, "F", 2)
    DllCall("EnumChildWindows", "Ptr", top, "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)
    return SnapRectsTmp
}

; 把 (x,y) 吸附到候选矩形最近边缘（容差 tol 内；返回 {X,Y}）
SnapPointToCandidates(x, y, tol := 6) {
    nx := x
    ny := y
    best := tol
    for r in GetSnapCandidates(x, y) {
        if (Abs(x - r.L) <= best && y >= r.T - tol && y <= r.B + tol) {
            nx := r.L
            best := Abs(x - r.L)
        }
        if (Abs(x - r.R) <= best && y >= r.T - tol && y <= r.B + tol) {
            nx := r.R
            best := Abs(x - r.R)
        }
        if (Abs(y - r.T) <= best && x >= r.L - tol && x <= r.R + tol) {
            ny := r.T
            best := Abs(y - r.T)
        }
        if (Abs(y - r.B) <= best && x >= r.L - tol && x <= r.R + tol) {
            ny := r.B
            best := Abs(y - r.B)
        }
    }
    return {X: nx, Y: ny}
}

SetSystemCursor(Cursor:="") {
    static SystemCursors := "32512IDC_ARROW|32513IDC_IBEAM|32514IDC_WAIT|32515IDC_CROSS|32516IDC_UPARROW|32642IDC_SIZENWSE|32643IDC_SIZENESW|32644IDC_SIZEWE|32645IDC_SIZENS|32646IDC_SIZEALL|32648IDC_NO|32649IDC_HAND|32650IDC_APPSTARTING|32651IDC_HELP"

    if (Cursor == "")
        return DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0)

    if (StrLen(SystemCursors) == 221) {
        parts := StrSplit(SystemCursors, "|")
        newParts := []
        for _, part in parts {
            cursorPtr := DllCall("LoadCursor", "UInt", 0, "Int", SubStr(part, 1, 5), "Ptr")
            newParts.Push(Format("{} {}", cursorPtr, part))
        }
        SystemCursors := StrJoinSelectArea(newParts, "|")
    }

    p := (StrLen(SystemCursors) - 221) / 14
    searchStr := "IDC_" Cursor "|"
    pos := InStr(SystemCursors "|", searchStr)

    if (!pos) {
        RmtDialog.Info("无效的指针名字！", A_ScriptName " - SetSystemCursor(): Error", "Icon!")
        return
    }

    cursorValue := SubStr(SystemCursors, pos - 5 - p, 5)

    for part in StrSplit(SystemCursors, "|") {
        DllCall("SetSystemCursor", "UInt", DllCall("CopyIcon", "UInt", cursorValue), "Int", SubStr(part, 6, p))
    }
}

StrJoinSelectArea(arr, delimiter) {
    if (arr.Length == 0)
        return ""
    result := arr[1]
    loop arr.Length - 1 {
        result .= delimiter arr[A_Index + 1]
    }
    return result
}

class HighlightOutlineSelectArea {
    __New(Color:="Red", Transparent:=255) {
        this.Guis := []
        loop 4 {
            MyGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x00080000")
            MyGui.BackColor := Color
            GuiHwnd := MyGui.Hwnd
            DllCall("SetLayeredWindowAttributes", "Ptr", GuiHwnd, "Uint", 0, "Uchar", Transparent, "int", 2)
            this.Guis.Push(MyGui)
        }
    }

    Show(x1, y1, x2, y2, b:=3) {
        this.Guis[1].Show("NA x" (x1 - b) " y" (y1 - b) " w" (x2 - x1 + b * 2) " h" b)
        this.Guis[2].Show("NA x" x2 " y" y1 " w" b " h" (y2 - y1))
        this.Guis[3].Show("NA x" (x1 - b) " y" y2 " w" (x2 - x1 + 2 * b) " h" b)
        this.Guis[4].Show("NA x" (x1 - b) " y" y1 " w" b " h" (y2 - y1))
    }

    Hide() {
        for MyGui in this.Guis {
            MyGui.Hide()
        }
    }
}

SimpleRecordMacroStr(MacroStr) {
    CmdArr := SplitMacro(MacroStr)
    SimpleCmdArr := []
    cmdKeyKw := GetLang("按键")
    joyKw := GetLang("手柄")
    spanKw := GetLang("间隔")
    downKw := GetLang("按下")
    upKw := GetLang("松开")
    clickKw := GetLang("点击")

    ; 用 skip 计数代替给 A_Index 赋值：循环计数器不受赋值影响，
    ; 否则合并后的「间隔」「松开」会被重复输出，录出多余的孤立按下/松开。
    skip := 0
    for idx, curCmd in CmdArr {
        if (skip > 0) {
            skip--
            continue
        }

        paramArr := SplitCommand(curCmd)
        ; 轴行无类型(如 按键_JoyAxisLX:75)仅2段，访问 paramArr[3] 会越界，须先判长度
        isPressKey := paramArr.Length >= 3 && (paramArr[1] == cmdKeyKw || paramArr[1] == joyKw) && paramArr[3] == downKw
        if (isPressKey && idx + 2 <= CmdArr.Length) {
            next1ParamArr := SplitCommand(CmdArr[idx + 1])
            next2ParamArr := SplitCommand(CmdArr[idx + 2])
            isMatchFormat := (next1ParamArr.Length >= 2 && next2ParamArr.Length >= 3
                && next1ParamArr[1] == spanKw && next2ParamArr[1] == paramArr[1])
            if (isMatchFormat && paramArr[2] == next2ParamArr[2] && next2ParamArr[3] == upKw) {
                ; 时长保底：PS5 蓝牙有时按下+松开在同 tick，间隔=0
                clickDuration := next1ParamArr[2]
                if (clickDuration < 50)
                    clickDuration := 50
                SimpleCmdArr.Push(Format("{}_{}_{}_{}", paramArr[1], paramArr[2], clickKw, clickDuration))
                skip := 2
                continue
            }
        }
        SimpleCmdArr.Push(curCmd)
    }

    ; 第二遍：孤儿「松开」补成「点击」。
    ; 录制组合键（如 Alt+Tab）时松开事件会被拆到没有配对按下的位置，
    ; 留下「按键_Tab_松开」这条指令——回放时它不产生任何效果（1.1.2 记作「点击」）。
    ; 只处理「此前从未出现过该键按下」的松开，避免破坏真正的长按录制。
    fixedArr := []
    seenDown := Map()
    for cmd in SimpleCmdArr {
        p := SplitCommand(cmd)
        isKeyLine := p.Length >= 3 && (p[1] == cmdKeyKw || p[1] == joyKw)
        if (isKeyLine) {
            sign := p[1] "|" p[2]
            if (p[3] == downKw) {
                seenDown[sign] := true
                fixedArr.Push(cmd)
                continue
            }
            if (p[3] == upKw && !seenDown.Has(sign)) {
                fixedArr.Push(Format("{}_{}_{}_{}", p[1], p[2], clickKw, 50))
                continue
            }
        }
        fixedArr.Push(cmd)
    }

    return GetMacroStrByCmdArr(fixedArr)
}

DiscardRecordTriggerKey(MacroStr, isFront) {
    if (isFront ? MainSoftData.IsTogStartRecord : MainSoftData.IsTogEndRecord)
        return MacroStr
    triggerMap := GetRecordTriggerKeyMap()
    CmdArr := SplitMacro(MacroStr)
    SimpleCmdArr := []
    hasDiscard := false
    loop CmdArr.Length {
        cmd := isFront ? CmdArr[A_Index] : CmdArr[CmdArr.Length - A_Index + 1]

        if (!hasDiscard) {
            if (InStr(cmd, GetLang("间隔")))
                continue

            if (!isFront) {
                moveArr := SplitCommand(cmd)
                if (moveArr.Length >= 4 && moveArr[moveArr.Length] == "2")
                    continue
            }

            if (CheckIfDiscardCMD(triggerMap, cmd))
                continue

            hasDiscard := true
        }

        if (isFront) {
            SimpleCmdArr.Push(cmd)
        } else {
            ; 逆向仅寻找尾部截断点。找到后一次线性复制，避免长录制逐条头插。
            endIndex := CmdArr.Length - A_Index + 1
            Loop endIndex
                SimpleCmdArr.Push(CmdArr[A_Index])
            break
        }
    }

    return GetMacroStrByCmdArr(SimpleCmdArr)
}

CheckIfDiscardCMD(triggerMap, cmd) {
    isKey := InStr(cmd, GetLang("按键")) && !InStr(cmd, GetLang("按键检测"))
    isJoy := InStr(cmd, GetLang("手柄")) && !InStr(cmd, GetLang("手柄检测"))
    if (!isKey && !isJoy)
        return false

    paramArr := SplitCommand(cmd)
    if (paramArr.Length < 2)
        return false
    key := paramArr[2]
    inn := JoyShortToInternal(key)
    short := JoyInternalToShort(key)
    if (triggerMap.Has(key) && triggerMap[key] < 2) {
        triggerMap[key] += 1
        return true
    }
    if (inn != "" && triggerMap.Has(inn) && triggerMap[inn] < 2) {
        triggerMap[inn] += 1
        return true
    }
    if (short != "" && triggerMap.Has(short) && triggerMap[short] < 2) {
        triggerMap[short] += 1
        return true
    }

    return false
}

FullCopyCmd(cmdStr, CopyedMap := Map()) {
    paramArr := SplitCommand(cmdStr)
    paramArr[1] := GetCmdStr(paramArr[1])
    if (paramArr[1] == GetLang("间隔"))
        return cmdStr
    if (paramArr[1] == GetLang("按键"))
        return cmdStr
    if (paramArr[1] == GetLang("手柄"))
        return cmdStr
    if (IsMoveCmd(paramArr[1]))
        return cmdStr
    if (paramArr[1] == GetLang("RMT指令"))
        return cmdStr

    if (CopyedMap.Has(paramArr[1])) {
        paramArr[1] := CopyedMap[paramArr[1]]
        return GetCmdByParams(paramArr)
    }

    ; 图形开始节点：深拷贝整张子图（含嵌套如果的 CurCMD）
    if (IsGraphStartSerial(paramArr[1]))
        return FullCopyGraphStart(paramArr[1], CopyedMap)

    textOnly := GetCmdOnlyText(paramArr[1])
    cmd := GetLangKey(textOnly)
    if (!MySoftData.DataFileMap.Has(cmd))
        return cmdStr
    Data := GetMacroCMDData(paramArr[1]).Clone()
    Data.SerialStr := GetCMDSerialStr(cmd)

    ; 优化：使用单次遍历拆分（替代RegExReplace）
    dummyText := ""
    SplitSerialTextAndNumbers(Data.SerialStr, &dummyText, &numbersOnly)
    CommandStr := Format("{}{}", textOnly, numbersOnly)
    CopyedMap.Set(paramArr[1], CommandStr)
    paramArr[1] := CommandStr

    ;如果， 搜索， 搜索Pro， 搜索Combo
    if (ObjHasOwnProp(Data, "TrueMacro")) {
        Data.TrueMacro := FullCopyMacro(Data.TrueMacro, CopyedMap)
    }

    if (ObjHasOwnProp(Data, "FalseMacro")) {
        Data.FalseMacro := FullCopyMacro(Data.FalseMacro, CopyedMap)
    }

    ;循环
    if (ObjHasOwnProp(Data, "LoopBody")) {
        Data.LoopBody := FullCopyMacro(Data.LoopBody, CopyedMap)
    }

    ;如果Pro
    if (ObjHasOwnProp(Data, "MacroArr") && ObjHasOwnProp(Data, "DefaultMacro")) {
        Data.DefaultMacro := FullCopyMacro(Data.DefaultMacro, CopyedMap)
        loop Data.MacroArr.Length {
            Data.MacroArr[A_Index] := FullCopyMacro(Data.MacroArr[A_Index], CopyedMap)
        }
    }

    SaveMacroCMDData(Data)
    res := GetCmdByParams(paramArr)
    return res
}

; 深拷贝「图形开始节点」子图：重映射 NodeArr/EmptyNode/NextNodeArr，并对各节点 CurCMD 走 FullCopyCmd
FullCopyGraphStart(startSerial, CopyedMap := Map()) {
    if (startSerial == "" || !IsGraphStartSerial(startSerial))
        return startSerial
    if (CopyedMap.Has(startSerial))
        return CopyedMap[startSerial]

    startData := GetMacroCMDData(startSerial)
    if (!IsObject(startData))
        return startSerial

    nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
    emptyArr := (startData.HasOwnProp("EmptyNode") && IsObject(startData.EmptyNode)) ? startData.EmptyNode : []

    serialMap := Map()
    queue := []
    for s in nodeArr
        queue.Push(s)
    for s in emptyArr
        queue.Push(s)
    while (queue.Length > 0) {
        s := queue.RemoveAt(1)
        if (s == "" || serialMap.Has(s))
            continue
        SplitSerialTextAndNumbers(s, &st, &sn)
        serialMap[s] := GetCMDSerialStr(st != "" ? st : "图形节点")
        nd := GetMacroCMDData(s)
        if (IsObject(nd) && nd.HasOwnProp("NextNodeArr") && IsObject(nd.NextNodeArr)) {
            for ns in nd.NextNodeArr
                queue.Push(ns)
        }
    }

    for oldS, newS in serialMap {
        nd := GetMacroCMDData(oldS)
        cp := MacroGraphNode()
        cp.SerialStr := newS
        if (IsObject(nd)) {
            curCmd := nd.HasOwnProp("CurCMD") ? nd.CurCMD : ""
            cp.CurCMD := FullCopyCmd(curCmd, CopyedMap)
            cp.X := nd.HasOwnProp("X") ? nd.X : 0
            cp.Y := nd.HasOwnProp("Y") ? nd.Y : 0
            cp.Folded := nd.HasOwnProp("Folded") ? nd.Folded : 0
            for layoutProp in ["TrueBranchDX", "TrueBranchDY", "FalseBranchDX", "FalseBranchDY", "ExpandShift", "SuccDX", "SuccDY", "FoldSuccDX", "FoldSuccDY", "ProBranchOff", "LoopBodyDX", "LoopBodyDY"] {
                if (nd.HasOwnProp(layoutProp))
                    cp.%layoutProp% := nd.%layoutProp%
            }
            newNexts := []
            if (nd.HasOwnProp("NextNodeArr") && IsObject(nd.NextNodeArr)) {
                for ns in nd.NextNodeArr
                    newNexts.Push(serialMap.Has(ns) ? serialMap[ns] : ns)
            }
            cp.NextNodeArr := newNexts
        }
        SaveMacroCMDData(cp)
        CopyedMap.Set(oldS, newS)
    }

    newStart := GetCMDSerialStr("图形开始节点")
    CopyedMap.Set(startSerial, newStart)
    sn := MacroGraphStartNode()
    sn.SerialStr := newStart
    newNodeArr := []
    for s in nodeArr
        newNodeArr.Push(serialMap.Has(s) ? serialMap[s] : s)
    newEmptyArr := []
    for s in emptyArr
        newEmptyArr.Push(serialMap.Has(s) ? serialMap[s] : s)
    sn.NodeArr := newNodeArr
    sn.EmptyNode := newEmptyArr
    sn.X := startData.HasOwnProp("X") ? startData.X : 60
    sn.Y := startData.HasOwnProp("Y") ? startData.Y : 220
    SaveMacroCMDData(sn)
    return newStart
}

FullCopyMacro(MacroStr, CopyedMap) {
    if (MacroStr == "")
        return MacroStr
    ; 整个宏就是一个图形开始节点（分支存图形态时）
    if (IsGraphStartSerial(Trim(MacroStr)))
        return FullCopyGraphStart(Trim(MacroStr), CopyedMap)
    cmdArr := SplitMacro(MacroStr)
    loop cmdArr.Length {
        cmdArr[A_Index] := FullCopyCmd(cmdArr[A_Index], CopyedMap)
    }

    ; 使用循环拼接（兼容所有数组类型）
    result := ""
    for index, value in cmdArr {
        if (index > 1)
            result .= ","
        result .= value
    }
    return result
}

GetPixelColorMap(CentPosX, CentPosY, Row, Col) {
    width := Col
    height := Row
    PosX := Integer(CentPosX - (Col - 1) / 2)
    PosY := Integer(CentPosY - (Row - 1) / 2)
    pBitmap := Gdip_BitmapFromScreen(PosX "|" PosY "|" width "|" height)
    ResultMap := Map()

    ; 使用LockBits优化：直接访问位图内存，避免逐像素的API调用开销
    Stride := 0, Scan0 := 0, BitmapData := 0
    if (Gdip_LockBits(pBitmap, 0, 0, width, height, &Stride, &Scan0, &BitmapData) = 0) {
        loop Row {
            rowValue := A_Index
            loop Col {
                colValue := A_Index

                ; 直接通过指针读取像素数据（ARGB格式，每像素4字节）
                pixelAddr := Scan0 + (rowValue - 1) * Stride + (colValue - 1) * 4
                Value := NumGet(pixelAddr, "UInt")

                Key := Format("{}-{}", colValue, rowValue)
                RGB_Value := Value & 0xFFFFFF
                hexStr := Format("0x{:X}", RGB_Value)
                ResultMap.Set(Key, hexStr)
            }
        }
        Gdip_UnlockBits(pBitmap, &BitmapData)
    } else {
        ; LockBits失败时回退到传统方式
        loop Row {
            rowValue := A_Index
            loop Col {
                colValue := A_Index
                Value := Gdip_GetPixel(pBitmap, colValue - 1, rowValue - 1)
                Key := Format("{}-{}", colValue, rowValue)
                RGB_Value := Value & 0xFFFFFF
                hexStr := Format("0x{:X}", RGB_Value)
                ResultMap.Set(Key, hexStr)
            }
        }
    }

    Gdip_DisposeImage(pBitmap)
    return ResultMap
}

SavePixelImage(PosX, PosY, SavePath) {
    ; 创建位图
    RowNum := 9
    ColNum := 13
    width := 130, height := 90
    pBitmap := Gdip_CreateBitmap(width, height)
    G := Gdip_GraphicsFromImage(pBitmap)
    CoordMode("Pixel", "Screen")

    loop RowNum {
        RowValue := A_Index
        loop ColNum {
            ColValue := A_Index

            CurPosX := PosX - (ColNum - 1) / 2 + ColValue
            CurPosY := PosY - (RowNum - 1) / 2 + RowValue
            ColorValue := PixelGetColor(CurPosX, CurPosY)
            ColorValue := "0xFF" SubStr(ColorValue, 3)
            pBrush := Gdip_BrushCreateSolid(ColorValue)
            Gdip_FillRectangle(G, pBrush, (ColValue - 1) * 10, (RowValue - 1) * 10, 10, 10)
            Gdip_DeleteBrush(pBrush)
        }
    }

    ; 保存临时图片文件
    Gdip_SaveBitmapToFile(pBitmap, SavePath)

    ; 清理资源
    Gdip_DeleteGraphics(G)
    Gdip_DisposeImage(pBitmap)
}

FormatIntegerWithCommas(num) {
    return RegExReplace(num, "(\d)(?=(\d{3})+$)", "$1,")
}

OpenMenuWheel(MenuIndex, isTog) {
    if (IsObject(MyMenuWheel) && MyMenuWheel.isOpen && MainSoftData.CurMenuWheelIndex == MenuIndex) {
        if (isTog)
            CloseMenuWheel()
        return
    }

    MainSoftData.CurMenuWheelIndex := MenuIndex
    MyMenuWheel.ShowGui(MenuIndex)
}

CloseMenuWheel() {
    MyMenuWheel.Close()
}

CorrectRemark(CommandStr, Remark) {
    charsToRemove := [",", "，", "`n", "⫶", "_"]
    for char in charsToRemove {
        Remark := StrReplace(Remark, char)
    }
    if (Remark != "") {
        CommandStr .= "_" Remark
    }
    return CommandStr
}

; 指令备注是否应自动生成：1=不生成；2=仅备注为空时生成；3=强制生成（覆盖已有备注）
ShouldAutoGenerateRemark(Remark) {
    if (MainSoftData.RemarkAutoType == 1)
        return false
    if (MainSoftData.RemarkAutoType == 3)
        return true
    return (Remark == "")
}

OnTriggerSepcialItemMacro(MacroStr, preserveBranchExit := false) {
    tableItem := MySoftData.SpecialTableItem
    if (tableItem.Items.Length == 0) {
        item := MacroItem()
        item.ID := GetCMDSerialStr("Item")
        tableItem.Items.Push(item)
        tableItem.RebuildIndex()
    }
    ; 兜底初始化统一内置控制键（宏循环/循环-跳出/分支-跳出 等），
    ; 否则新 scratch 条目的 VariableMap 为空 Map()，缺失键访问会抛 "No value was returned"
    InitSingleTableState(tableItem)
    item := tableItem.Items[1]
    item.Killed := false
    item.Pause := false
    item.ActionCount := 0
    item.ColorState := 1
    item.Remark := ""

    UpdateMacroRunningCount(0, 1)
    RefreshItemColorUI(tableItem, 1)
    RunMacroBodyOnce(tableItem, MacroStr, 1, preserveBranchExit)
    item.ColorState := 0
    UpdateMacroRunningCount(1, 0)
    RefreshItemColorUI(tableItem, 1)
}

HandleOpenArg() {
    global MySoftData
    if (A_Args.Length <= 0) {
        if (MainSoftData.IsAdminStart && !A_IsAdmin)
            ElevateToAdmin()
        return
    }

    loop A_Args.Length {
        argIndex := A_Index
        arg := A_Args[argIndex]
        if (arg == "-min") {
            MainSoftData.IsMinStart := true
            continue
        }
        if (arg == "-admin") {
            if (!A_IsAdmin) {
                ElevateToAdmin()
            }
            continue
        }
        if (arg == "-elevated") {
            continue
        }
        ; §3 命令行：首个其它 "-" 参数视为命令起始，收集该命令及其全部参数，
        ; 启动完成后由 RmtRunStartupCommands() 统一执行（依赖表/线程池/UI 就绪）
        if (SubStr(arg, 1, 1) == "-") {
            if (!MySoftData.HasProp("StartupCmdArr"))
                MySoftData.StartupCmdArr := []
            MySoftData.StartupCmdArr := []
            MySoftData.StartupCmdArr.Push(arg)
            loop A_Args.Length - argIndex {
                MySoftData.StartupCmdArr.Push(A_Args[argIndex + A_Index])
            }
            break
        }
    }
}

; 当前进程是否真正以提升权限运行（TokenIsElevated）
; 勿用 A_IsAdmin：管理员组成员在未提权时也可能为真，导致托盘误显「管理员权限」
IsProcessElevated() {
    hToken := 0
    if !DllCall("advapi32\OpenProcessToken", "ptr", DllCall("GetCurrentProcess", "ptr")
        , "uint", 0x0008, "ptr*", &hToken)  ; TOKEN_QUERY
        return false
    elev := 0
    retLen := 0
    ; TokenElevation = 20，TOKEN_ELEVATION.TokenIsElevated
    ok := DllCall("advapi32\GetTokenInformation", "ptr", hToken, "int", 20
        , "uint*", &elev, "uint", 4, "uint*", &retLen)
    DllCall("CloseHandle", "ptr", hToken)
    return ok && (elev != 0)
}

ElevateToAdmin() {
    args := ""
    loop A_Args.Length {
        arg := A_Args[A_Index]
        if (arg != "-admin" && arg != "-elevated")
            args .= ' "' arg '"'
    }
    try {
        Run('*RunAs "' A_ScriptFullPath '" -elevated ' args)
        ExitApp()
    }
}

SetEditData() {
    visitMap := Map()
    loop MySoftData.TableInfo.Length {
        tableIndex := A_Index
        tableItem := MySoftData.TableInfo[tableIndex]
        ; 替换表存的是键名列表，不经过宏指令解析，但也需要在启动时创建虚拟手柄。
        if (tableItem.Symbol == "Replace") {
            for item in tableItem.Items {
                if (ReplaceKeysUseJoy(item.Macro))
                    MySoftData.HasJoyMacro := true
            }
            continue
        }
        isMacro := CheckIsMacroTable(tableIndex)
        if (!isMacro)
            continue

        for item in tableItem.Items {
            if (item.Macro == "")
                continue

            SetGlobalData(item.Macro, visitMap)
        }
    }
}

;0默认状态 1运行 2暂停 3终止
UpdateMacroRunningCount(LastState, State) {
    value := 0
    if ((LastState == 0 || LastState == 3) && State == 1) ;运行+1
        value := 1
    else if (LastState == 1 && State != 1)  ;结束 | 暂停 | 终止 -1
        value := -1
    else if (LastState == 2 && State == 1)  ;取消暂停+1
        value := 1

    MySoftData.MacroRunningCount += value
    if (MySoftData.MacroRunningCount < 0)
        MySoftData.MacroRunningCount := 0

    curState := MySoftData.MacroRunningCount > 0
    if (curState != MySoftData.IsMacroWorking) {
        MySoftData.IsMacroWorking := curState
        UpdateMacroTrayIcon()
        MyCMDTipGui.OnToggleMacroWorkState()
    }
}

;批量移除文件的“来自互联网”标记（Zone.Identifier）。 防止文件被锁定
UnblockZoneIdentifier() {
    markerFile := A_WorkingDir "\Setting\.unblocked"
    if (FileExist(markerFile)) {
        markerTime := FileGetTime(markerFile)
        exeTime := FileGetTime(A_ScriptFullPath)
        if (exeTime <= markerTime)
            return
    }

    try {
        fullCmd := 'powershell.exe -NoProfile -WindowStyle Hidden -Command "Get-ChildItem -Path "' A_ScriptDir '" -Recurse -File | ForEach-Object { try { Unblock-File -Path $_.FullName -ErrorAction Stop } catch {} }; if ($?) { New-Item -Path "' markerFile '" -ItemType File -Force | Out-Null }"'
        Run(fullCmd, , "Hide")
    }
}

; ──────────────────────────────────────────────────────────────────────
; 儲存前智能跳脫（介面格式 → 存儲格式）
;
; 規則：
;   1. 已有變量 {var} -> 保持 {var}
;   2. 一般 {        -> /{
;   3. 一般 }        -> /}
; ──────────────────────────────────────────────────────────────────────
SmartEscapeVarText(text) {
    varMap := Map()
    for v in GetGuiVarArr(1)
        varMap[v] := true

    result := ""
    pos := 1
    len := StrLen(text)

    while (pos <= len) {
        ch := SubStr(text, pos, 1)

        if (ch = "{") {
            endPos := InStr(text, "}", false, pos + 1)
            if (endPos) {
                content := SubStr(text, pos + 1, endPos - pos - 1)

                ; 只保留 varMap 內的既有變量
                if (content != "" && varMap.Has(content)) {
                    result .= "{" . content . "}"
                    pos := endPos + 1
                    continue
                }
            }

            ; 非變量 / 無法成組：跳脫
            result .= "/{"
        }
        else if (ch = "}") {
            result .= "/}"
        }
        else {
            result .= ch
        }

        pos++
    }

    return result
}

; ──────────────────────────────────────────────────────────────────────
; 介面顯示前還原（存儲格式 → 介面格式）
; ──────────────────────────────────────────────────────────────────────
UnescapeVarText(text) {
    text := StrReplace(text, "/{", "{")
    text := StrReplace(text, "/}", "}")
    return text
}
