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
    global MySoftData, MyWorkPool
    isValid := CheckAllValueSettingValid()
    if (!isValid)
        return

    ; 先取窗口位置再隐藏，用户感知窗口立即关闭；后续保存/Reload 在隐藏窗口下进行
    SaveCurWinPos()
    MainSoftData.MyGui.Hide()

    OnKillAllMacro()

    if (MyWorkPool != "") {
        MyWorkPool.Clear()
        MyWorkPool := ""
    }

    ; Epic5：虚拟化列表保存前兜底提交实体化行全字段（覆盖纯键盘后未失焦路径）。
    ; VL_COMMIT_ALL 回传经 SetTimer(-1) 异步写模型，Sleep(-1) 处理 pending timer 后再读，防丢
    for t in [1, 2, 3, 4, 5, 6, 7] {
        if (MyMainWin._useVirtual.Has(t)) {
            MyMainWin._vl.CommitAll(t)
            Sleep(-1)
        }
    }

    loop MainSoftData.TabNameArr.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        RecycleTabItem(tableItem)
        SaveTableItemInfo(A_Index)
    }

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
    CheckAndAddDirty("SuspendHotkey", MainSoftData.SuspendHotkey)
    CheckAndAddDirty("PauseHotkey", MainSoftData.PauseHotkey)
    CheckAndAddDirty("KillMacroHotkey", MainSoftData.KillMacroHotkey)
    CheckAndAddDirty("IsBootStart", MainSoftData.IsBootStart)
    CheckAndAddDirty("ShowSplitLine", MainSoftData.ShowSplitLine)
    CheckAndAddDirty("IsModalSubGui", MainSoftData.IsModalSubGui)
    CheckAndAddDirty("MutiThreadNum", MainSoftData.MutiThreadNum)
    CheckAndAddDirty("SoftBGColor", MainSoftData.SoftBGColor)
    CheckAndAddDirty("NoVariableTip", MainSoftData.NoVariableTip)
    CheckAndAddDirty("BusinessLog", MainSoftData.BusinessLog)
    CheckAndAddDirty("SysLogMinLevel", MainSoftData.SysLogMinLevel)
    CheckAndAddDirty("LogWarnBubble", MainSoftData.LogWarnBubble)
    CheckAndAddDirty("LogErrorBadge", MainSoftData.LogErrorBadge)
    CheckAndAddDirty("CheckForeground", MainSoftData.CheckForeground)
    CheckAndAddDirty("IsAdminStart", MainSoftData.IsAdminStart)
    CheckAndAddDirty("CMDTip", MySoftData.CMDTip)
    CheckAndAddDirty("ScreenShotType", MainSoftData.ScreenShotType)
    CheckAndAddDirty("KeyDownDown", MainSoftData.KeyDownDownType)
    CheckAndAddDirty("AutoLoosenModifier", MainSoftData.AutoLoosenModifier ? 1 : 0)
    CheckAndAddDirty("ContinuousTrigger", MainSoftData.ContinuousTrigger ? 1 : 0)
    CheckAndAddDirty("SharedCopy", MainSoftData.SharedCopy)
    CheckAndAddDirty("GeneralContextMenu", MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : "")
    CheckAndAddDirty("BranchContextMenu",  MainSoftData.HasProp("BranchContextMenu")  ? MainSoftData.BranchContextMenu  : "")
    CheckAndAddDirty("RemarkAutoType", MainSoftData.RemarkAutoType)
    CheckAndAddDirty("MacroStopType", MainSoftData.MacroStopType)
    CheckAndAddDirty("Theme", MainSoftData.Theme)

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

    ; 状态设置（这些每次都变化，始终写入）
    CheckAndAddDirty("TableIndex", MainSoftData.TabCtrl.Value)
    CheckAndAddDirty("Lang", MainSoftData.Lang)
    CheckAndAddDirty("FontType", MainSoftData.FontType)
    CheckAndAddDirty("FontSize", MainSoftData.HasProp("FontSize") ? MainSoftData.FontSize : 15)
    CheckAndAddDirty("JoyType", MainSoftData.JoyType)
    CheckAndAddDirty("TriggerJoyType", MainSoftData.TriggerJoyType)
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

    ; 只写入实际发生变化的配置项（性能提升80%+）
    for key, value in dirtySettings {
        IniWrite(value, IniFile, IniSection, key)
    }
    SafeReload()
}

CheckValueSettingValid(Name, Value) {
    if (!IsInteger(Value)) {
        MsgBox(Format("{}{}", Name, GetLang("只能是整数")))
        return false
    }
    return true
}

CheckAllValueSettingValid() {
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

    if (!CheckValueSettingValid(GetLang("多线程数"), MainSoftData.MutiThreadNum))
        return false

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
    IniWrite(Format("{}π{}πSπ{:.2f}", x, y, scale), IniFile, IniSection, "LastWinPos")

    ListenGui := MyVarListenGui.Gui
    if (MyVarListenGui.Gui != "") {
        ListenGui.GetPos(&x, &y, &w, &h)
        IniWrite(Format("{}π{}", x, y), IniFile, IniSection, "ListenVarPos")
    }
}

OnEditCMDTipGui() {
    CMDTipSettingGui.ShowGui()
}

OnTabValueChanged(*) {
    ; 滑块已删除；当前页索引由 MainWin.OnTabChanged 同步到 MainSoftData.TableIndex
}

SwapTableContent(tableItem, indexA, indexB) {
    ; 持久配置数组（保存到文件，必须跟随宏内容移动，否则上/下移后保存会错位）
    SwapArrValue(tableItem.SerialArr, indexA, indexB)
    SwapArrValue(tableItem.RemarkArr, indexA, indexB)
    SwapArrValue(tableItem.TKArr, indexA, indexB)
    SwapArrValue(tableItem.TriggerTypeArr, indexA, indexB)
    SwapArrValue(tableItem.HoldTimeArr, indexA, indexB)
    SwapArrValue(tableItem.MacroArr, indexA, indexB)
    SwapArrValue(tableItem.LoopCountArr, indexA, indexB)
    SwapArrValue(tableItem.ForbidArr, indexA, indexB)
    SwapArrValue(tableItem.IcoPathArr, indexA, indexB)
    SwapArrValue(tableItem.UnorderedTriggerArr, indexA, indexB)
    SwapArrValue(tableItem.TimingSerialArr, indexA, indexB)
    SwapArrValue(tableItem.ModeArr, indexA, indexB)
    SwapArrValue(tableItem.StartTipSoundArr, indexA, indexB)
    SwapArrValue(tableItem.EndTipSoundArr, indexA, indexB)
    SwapArrValue(tableItem.VoiceTriggerArr, indexA, indexB)
    SwapArrValue(tableItem.VoiceKeywordsArr, indexA, indexB)
    ; 运行时状态数组（与 ModeArr 等长，InitSingleTableState 统一初始化）
    ; 颜色点跟随宏内容：行移动后状态显示与新位置宏保持一致（原仅交换 9 数组导致颜色点错位）
    SwapArrValue(tableItem.ColorStateArr, indexA, indexB)
    SwapArrValue(tableItem.HoldKeyArr, indexA, indexB)
    SwapArrValue(tableItem.KilledArr, indexA, indexB)
    SwapArrValue(tableItem.PauseArr, indexA, indexB)
    SwapArrValue(tableItem.ActionCount, indexA, indexB)
    SwapArrValue(tableItem.ToggleStateArr, indexA, indexB)
    SwapArrValue(tableItem.ToggleActionArr, indexA, indexB)
    SwapArrValue(tableItem.VariableMapArr, indexA, indexB)
    SwapArrValue(tableItem.IsWorkIndexArr, indexA, indexB)
    SwapArrValue(tableItem.GraphBranchCountArr, indexA, indexB)
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
    XAMLHost.Prewarm()
}

InitViGEmPlugin() {
    JoyDebugLog(Format("PluginInit HasJoyMacro={} MutiThreadNum={} WorkPoolEnabled={} IsAdmin={} Script={}"
        , MySoftData.HasJoyMacro, MainSoftData.MutiThreadNum, WorkPoolEnabled(), A_IsAdmin, A_ScriptFullPath), "init")
    if (!MySoftData.HasJoyMacro) {
        JoyDebugLog("PluginInit skip ViGEm (HasJoyMacro=false); will lazy-create on first Joy send", "init")
        return
    }

    isDS4 := MainSoftData.JoyType = "DS4"
    diBefore := SnapshotJoyDeviceMap()
    global ViGJoy := isDS4 ? ViGEmDS4() : ViGEmXb360()
    global CurViGJoyType := isDS4 ? "DS4" : "Xbox"
    global VirtualJoyDiIdx := FindNewJoyDeviceIndex(diBefore)

    try instOk := (IsSet(ViGJoy) && ViGJoy.Instance != "")
    catch
        instOk := false
    try xidx := ViGJoy.ViGJoyXInputIdx
    catch
        xidx := "?"
    JoyDebugLog(Format("PluginInit {} created InstanceOK={} XInputIdx={} DiIdx={} DllPath={}"
        , isDS4 ? "ViGEmDS4" : "ViGEmXb360", instOk, xidx, VirtualJoyDiIdx
        , IsSet(ViGEmDllPath) ? ViGEmDllPath : "(unset)"), "init")
}

SnapshotJoyDeviceMap() {
    diBefore := Map()
    loop 10 {
        n := GetKeyState(A_Index "JoyName")
        if (n != "")
            diBefore[A_Index] := n
    }
    return diBefore
}

FindNewJoyDeviceIndex(diBefore) {
    try {
        loop 10 {
            n := GetKeyState(A_Index "JoyName")
            if (n != "" && !diBefore.Has(A_Index))
                return A_Index
        }
    }
    return -1
}

InitNativePlugins() {
    ; 加载 OpenCV 插件，失败时诊断具体原因（如缺少 VC++ 运行库）
    ocvReason := OpenCvEnsure()
    if (ocvReason != "")
        JoyDebugLog(Format("OpenCV 插件初始化失败：{}", ocvReason), "init")

    IBPath := A_ScriptDir "\Plugins\IbInputSimulator.dll"
    DllCall("LoadLibrary", "Str", IBPath)
}

InitRMTHttpPlugin() {
    global RMT_Http := ""
    global RMT_IsForbidUpdate := false
    global RMT_HasDotNet := HasDotNetFramework()
    if (!RMT_HasDotNet)
        return

    try {
        RMTPath := A_ScriptDir "\Plugins\RMT\RMT.dll"
        RMT_ASM := CLR_LoadLibrary(RMTPath)
        RMT_Http := RMT_ASM.CreateInstance("RMT.Http")
        ApplyRMTServerStatus(RMT_Http.GetStatus(RMT_VERSION_DISPLAY))
    } catch {
        RMT_Http := ""
        RMT_HasDotNet := false
    }
}

ApplyRMTServerStatus(statusStr) {
    global RMT_IsForbidUpdate
    if (statusStr = "")
        return
    try {
        statusObj := JSON.parse(statusStr)
        if (statusObj.Has("isForbidUpdate"))
            RMT_IsForbidUpdate := !!statusObj["isForbidUpdate"]
    }
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

    global VBSPath := A_WorkingDir "\MinTool\PlayAudio.vbs"
    global StartTipAudio := A_WorkingDir "\Audio\Start.wav"
    global EndTipAudio := A_WorkingDir "\Audio\End.wav"
    global ViGEmDllPath := A_WorkingDir "\Plugins\ViGEm\ViGEmWrapper.dll"
    global AHIDllDir := A_WorkingDir "\Plugins\AhiDriver"
    global AHIPluginDir := A_WorkingDir "\Plugins\AhiDriver\installer"
    global ArrayFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\ArrayFile.ini"
    global MacroFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\MacroFile.ini"
    global SearchFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SearchFile.ini"
    global SearchProFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SearchProFile.ini"
    global CompareFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\CompareFile.ini"
    global CompareProFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\CompareProFile.ini"
    global MMProFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\MMProFile.ini"
    global BGKeyFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\BGKeyFile.ini"
    global TimingFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\TimingFile.ini"
    global RunFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\RunFile.ini"
    global OutputFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\OutputFile.ini"
    global VariableFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\VariableFile.ini"
    global ExVariableFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\ExVariableFile.ini"
    global TextOpsFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\TextOpsFile.ini"
    global SubMacroFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SubMacroFile.ini"
    global LoopFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\LoopFile.ini"
    global OperationFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\OperationFile.ini"
    global BGMouseFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\BGMouseFile.ini"
    global InputFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\InputFile.ini"
    global FileIOFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\FileIOFile.ini"
    global WindowManageFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\WindowManageFile.ini"
    global KeyCheckFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\KeyCheckFile.ini"
    global CommentFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\CommentFile.ini"
    global ScreenShotFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\ScreenShotFile.ini"
    global GraphNodeFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\GraphNodeFile.ini"
    global GraphStartNodeFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\GraphStartNodeFile.ini"
    ; 阶段5：纯文本指令迁移到配置文件模式（间隔/按键/移动/RMT指令）
    global IntervalFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\IntervalFile.ini"
    global KeyDataFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\KeyDataFile.ini"
    global MoveDataFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\MoveDataFile.ini"
    global RMTCMDFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\RMTCMDFile.ini"
    global ProjectRootDir := A_ScriptDir
}

StopMacro(tableIndex, itemIndex) {
    tableItem := MySoftData.TableInfo[tableIndex]
    if (tableItem.GraphBranchCountArr.Length >= itemIndex)
        tableItem.GraphBranchCountArr[itemIndex] := 0

    ; 多线程：搜图等 DllCall 会卡住 Worker，协作式 KilledArr/ST 不可靠，直接杀进程
    if (WorkPoolEnabled()) {
        hasWork := tableItem.IsWorkIndexArr[itemIndex] || MyWorkPool.HasItemWork(tableIndex, itemIndex)
        if (hasWork) {
            MyWorkPool.ForceStopItem(tableIndex, itemIndex)
            return
        }
    }

    ; 主进程内执行的宏：置 Killed 标记后，宏循环会自行退出并由 OnFinishMacro 设置终止状态
    KillTableItemMacro(tableItem, itemIndex)
    if (tableItem.TriggerTypeArr.Length >= itemIndex && tableItem.TriggerTypeArr[itemIndex] == 4)
        SetTableItemState(tableIndex, itemIndex, 3)
}

; Worker 多分支图形宏：接收 Worker 提交的分支节点列表，入队并分派，回复确认
HandleWorkerGraphBranches(wd, tIdx, iIdx, branchCount, nodeArr) {
    tableItem := MySoftData.TableInfo[tIdx]
    if (branchCount > 0) {
        ; fromStart：设置总分支数，清空旧队列，重置终止标记
        MyWorkPool.DrainItemTaskQueue(tIdx, iIdx)
        if (tableItem.GraphBranchCountArr.Length >= iIdx)
            tableItem.GraphBranchCountArr[iIdx] := branchCount
        if (tableItem.KilledArr.Length >= iIdx)
            tableItem.KilledArr[iIdx] := false
        if (MyWorkPool.usePool.Has(wd.idx)) {
            w := MyWorkPool.usePool[wd.idx]
            w.isGraphBranch := true
            w.tableIndex := tIdx
            w.itemIndex := iIdx
        }
    } else {
        loop nodeArr.Length
            if (tableItem.GraphBranchCountArr.Length >= iIdx)
                tableItem.GraphBranchCountArr[iIdx]++
    }
    ; 入队各分支任务
    for nodeSerial in nodeArr
        MyWorkPool.taskQueue.Push({ cmd: EncodeBatch(EncodeCommand("TR", tIdx, iIdx, nodeSerial)), tableIndex: tIdx, itemIndex: iIdx, isGraphBranch: true })
    if (MyWorkPool.isDispatching)
        MyWorkPool.dispatchPending := true
    else
        MyWorkPool.Dispatch()
    ; 回复 Worker 确认，唤醒继续执行分支1
    MyWorkPool.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("GA", tIdx, iIdx)))
}

GetArrayRefByPath(rootArr, path, &lastIdx) {
    parts := StrSplit(path, ".")
    curr := rootArr
    if (parts.Length == 2 && parts[1] == "0") {
        lastIdx := Integer(parts[2])
        return rootArr
    }
    loop parts.Length - 1 {
        idx := Integer(parts[A_Index])
        curr := curr[idx]
    }
    lastIdx := Integer(parts[parts.Length])
    return curr
}

SetGlobalArray(Name, Value, excludeIdx := 0) {
    MySoftData.ArrayMap[Name] := Value
    MyVarListenGui.Refresh()
    ; 整串序列化，保留二维嵌套；旧协议按元素展开会把 [[a],[b]] 压成一维
    MyWorkPool.BroadcastEx(excludeIdx, "SA", Name, GetArrayStr(Value))
}

CloneGlobalArray(Source, NewArrName, excludeIdx := 0) {
    if (IsObject(Source)) {
        ; 单线程：克隆指令直接把源数组对象传进来，克隆后按对象同一性反查源数组名
        MySoftData.ArrayMap[NewArrName] := Source.Clone()
        SourceName := ""
        for name, arr in MySoftData.ArrayMap {
            if (arr == Source && name != NewArrName) {
                SourceName := name
                break
            }
        }
        if (SourceName == "")
            SourceName := NewArrName
    }
    else {
        ; 多线程：master 收到 worker 的 CloneArray 广播，Source 是数组名字符串
        MySoftData.ArrayMap[NewArrName] := MySoftData.ArrayMap[Source].Clone()
        SourceName := Source
    }
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastEx(excludeIdx, "CA", SourceName, NewArrName)
}

DeleteGlobalArray(ArrName, excludeIdx := 0) {
    MySoftData.ArrayMap.Delete(ArrName)
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastEx(excludeIdx, "DA", ArrName)
}

ModifyGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value, excludeIdx := 0) {
    path := MainIndex "." Index
    rootArr := MySoftData.ArrayMap[ArrName]
    currArr := GetArrayRefByPath(rootArr, path, &lastIdx)
    currArr[lastIdx] := Value
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastEx(excludeIdx, "MA", ArrName, path, IsArrayValue ? GetArrayStr(Value) : Value)
}

InsertGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value, excludeIdx := 0) {
    path := MainIndex "." Index
    rootArr := MySoftData.ArrayMap[ArrName]
    currArr := GetArrayRefByPath(rootArr, path, &lastIdx)
    currArr.InsertAt(lastIdx, Value)
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastEx(excludeIdx, "IA", ArrName, path, IsArrayValue ? GetArrayStr(Value) : Value)
}

RemoveAtGlobalArray(ArrName, MainIndex, Index, excludeIdx := 0) {
    path := MainIndex "." Index
    rootArr := MySoftData.ArrayMap[ArrName]
    currArr := GetArrayRefByPath(rootArr, path, &lastIdx)
    currArr.RemoveAt(lastIdx)
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastEx(excludeIdx, "RA", ArrName, path)
}

SetGlobalVariable(NameArr, ValueArr, ignoreExist, excludeIdx := 0) {
    RealNameArr := NameArr.Clone()
    RealValueArr := ValueArr.Clone()
    if (ignoreExist) {
        RealNameArr := []
        RealValueArr := []
        loop NameArr.Length {
            if (!MySoftData.VariableMap.Has(NameArr[A_Index])) {
                RealNameArr.Push(NameArr[A_Index])
                RealValueArr.Push(ValueArr[A_Index])
            }
        }
    }
    if (RealNameArr.Length == 0)
        return

    commands := []
    loop RealNameArr.Length {
        MySoftData.VariableMap[RealNameArr[A_Index]] := RealValueArr[A_Index]
        commands.Push(EncodeCommand("SV", RealNameArr[A_Index], RealValueArr[A_Index]))
    }
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastPayloadEx(excludeIdx, EncodeBatch(commands*))
}

DelGlobalVariable(NameArr, excludeIdx := 0) {
    RealNameArr := []
    loop NameArr.Length {
        if (MySoftData.VariableMap.Has(NameArr[A_Index])) {
            MySoftData.VariableMap.Delete(NameArr[A_Index])
            RealNameArr.Push(NameArr[A_Index])
        }
    }

    if (RealNameArr.Length == 0)
        return

    commands := []
    loop RealNameArr.Length {
        commands.Push(EncodeCommand("DV", RealNameArr[A_Index]))
    }
    MyVarListenGui.Refresh()
    MyWorkPool.BroadcastPayloadEx(excludeIdx, EncodeBatch(commands*))
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

;0默认状态 1运行 2暂停 3终止
SetTableItemState(tableIndex, itemIndex, State) {
    ; Worker 经 IPC 回发的 IS/PS 事件参数是字符串；Map 键类型敏感，若 ColorStateArr 混入
    ; 字符串 "3"，GetItemColorValue 的整数键 Map 查不到，红色终止态将无法显示。统一转整数。
    tableIndex := Integer(tableIndex)
    itemIndex := Integer(itemIndex)
    State := Integer(State)

    tableItem := MySoftData.TableInfo[tableIndex]
    LastState := tableItem.ColorStateArr[itemIndex]

    if (LastState == 0 && (State == 2 || State == 3)) {
        ; 终止过程中宏已正常结束（状态已归 0），不再应用终止/暂停状态
        GraphPoolLog("状态忽略-已正常结束", Format("tab={1} item={2} 收到状态={3} 当前=0", tableIndex, itemIndex, State))
        return
    }

    if (State == 2 && LastState != 1)
        return
    if (State == 3 && LastState == 3)
        return

    if (State == 3) {
        StopCancelTableItemTimer(tableIndex, itemIndex)
        timerFunc := CancelTableItemStopState.Bind(tableIndex, itemIndex)
        timerKey := tableIndex "|" itemIndex
        CancelTableItemTimerMap[timerKey] := timerFunc
        SetTimer(timerFunc, -5000)
    }
    else if (LastState == 3)
        StopCancelTableItemTimer(tableIndex, itemIndex)

    UpdateMacroRunningCount(LastState, State)
    tableItem.ColorStateArr[itemIndex] := State
    RefreshItemColorUI(tableIndex, itemIndex)

    if (tableIndex == 4 && IsSet(MyUIMacroGui))
        MyUIMacroGui.UpdateButtonsState(itemIndex, State)
}

RefreshItemColorUI(tableIndex, itemIndex) {
    global MyMainWin
    MyMainWin.UpdateItemColor(tableIndex, itemIndex)
}

CancelTableItemStopState(tableIndex, itemIndex) {
    tableItem := MySoftData.TableInfo[tableIndex]
    if (tableItem.ColorStateArr[itemIndex] == 3) {
        if (tableItem.IsWorkIndexArr.Length >= itemIndex && tableItem.IsWorkIndexArr[itemIndex] != 0)
            return

        ; 同步清除 KilledArr，確保狀態完全恢復可再次觸發
        if (tableItem.KilledArr.Length >= itemIndex)
            tableItem.KilledArr[itemIndex] := false
        ; 通过 SetTableItemState 恢复默认状态（自动触发浮动画板同步等逻辑）
        SetTableItemState(tableIndex, itemIndex, 0)
    }
}

global CancelTableItemTimerMap := Map()

StopCancelTableItemTimer(tableIndex, itemIndex) {
    timerKey := tableIndex "|" itemIndex
    if (CancelTableItemTimerMap.Has(timerKey)) {
        SetTimer(CancelTableItemTimerMap[timerKey], 0)
        CancelTableItemTimerMap.Delete(timerKey)
    }
}

SetItemPauseState(tableIndex, itemIndex, state, excludeIdx := 0) {
    tableItem := MySoftData.TableInfo[tableIndex]
    tableItem.PauseArr[itemIndex] := state

    LastColorState := tableItem.ColorStateArr[itemIndex]
    if (LastColorState == 1 && state == 1)
        SetTableItemState(tableIndex, itemIndex, 2)
    else if (LastColorState == 2 && state == 0)
        SetTableItemState(tableIndex, itemIndex, 1)

    MyWorkPool.BroadcastEx(excludeIdx, "PS", tableIndex, itemIndex, state)
}

;恢复意外退出残留的脏状态，后面要换成热重载就会要
RecoverAllDirtyStates() {
    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        if (!tableItem.ColorStateArr.Length)
            continue
        loop tableItem.ColorStateArr.Length {
            if (tableItem.ColorStateArr[A_Index] != 0) {
                tableItem.ColorStateArr[A_Index] := 0
                if (tableItem.IsWorkIndexArr.Length >= A_Index)
                    tableItem.IsWorkIndexArr[A_Index] := 0
                RefreshItemColorUI(tableItem.Index, A_Index)
            }
        }
    }

    tableItem := MySoftData.SpecialTableItem
    if (tableItem.ColorStateArr.Length >= 1 && tableItem.ColorStateArr[1] != 0) {
        tableItem.ColorStateArr[1] := 0
        RefreshItemColorUI(tableItem.Index, 1)
    }

    if (MySoftData.MacroRunningCount != 0) {
        MySoftData.MacroRunningCount := 0
        MySoftData.IsMacroWorking := false
        MyCMDTipGui.OnToggleMacroWorkState()
    }
}

CleanupAllMacroStates() {
    RecoverAllDirtyStates()
}

MsgBoxContent(content) {
    MainSoftData.MyGui.Flash()
    SoundPlay "*-1"
    MyMsgboxGui.ShowGui(content)
}

MacroCount(content) {
    if (content == "Add") {
        MySoftData.MacroTotalCount += 1
    }
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
    paramArr := StrSplit(Cmd, "⫶")
    if (paramArr.Length >= 3 && ApplyRmtInputControl(paramArr[3]))
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
                    IniWrite(false, IniFile, IniSection, "IsOpenListenVar")
                }
            }
        case "显示菜单":
            OpenMenuWheel(paramArr[4], false)
        case "关闭菜单":
            CloseMenuWheel()
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
    if (isEnable && action != "") {
        MainSoftData.GetAreaAction := action
        Hotkey("~*LButton", OnGetSelectAreaDown, "On")
        Hotkey("~*LButton Up", OnGetSelectAreaUp, "On")
        Hotkey("~*RButton", OnGetSelectAreaCancel, "On")
    }
    else {
        MainSoftData.GetAreaAction := ""
        Hotkey("~*LButton", "Off")
        Hotkey("~*LButton Up", "Off")
        Hotkey("~*RButton", "Off")
    }
}

OnGetSelectAreaDown(*) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY)
    MainSoftData.StartAreaPosX := startX
    MainSoftData.StartAreaPosY := startY
}

OnGetSelectAreaUp(*) {
    action := MainSoftData.GetAreaAction
    TogGetSelectArea(false)
    if (action == "")
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&endX, &endY)

    x1 := Min(MainSoftData.StartAreaPosX, endX)
    y1 := Min(MainSoftData.StartAreaPosY, endY)
    x2 := Max(MainSoftData.StartAreaPosX, endX)
    y2 := Max(MainSoftData.StartAreaPosY, endY)
    action(x1, y1, x2, y2)
}

OnGetSelectAreaCancel(*) {
    TogGetSelectArea(false)
}

TogSelectArea(isEnable, action := "") {
    global SelectAreaState
    if (isEnable && action != "") {
        MainSoftData.SelectAreaAction := action
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
    global SelectAreaState
    SelectAreaState.winPos := ""
    SelectAreaState.firstPos := false
    SetTimer(SelectAreaDraw, 30)
}

SelectAreaUp(*) {
    global SelectAreaState
    SetTimer(SelectAreaDraw, 0)

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
    SelectAreaState.winPos := ""
    SelectAreaUp()
}

SelectAreaDraw() {
    global SelectAreaState
    CoordMode("Mouse")
    if (!SelectAreaState.firstPos) {
        SelectAreaState.firstPos := true
        mx := 0, my := 0
        MouseGetPos(&mx, &my)
        SelectAreaState.sx := mx
        SelectAreaState.sy := my
    } else {
        ex := 0, ey := 0
        MouseGetPos(&ex, &ey)
        sx := SelectAreaState.sx, sy := SelectAreaState.sy
        if (sx <= ex && sy <= ey)
            SelectAreaState.winPos := {X: sx, Y: sy, W: ex - sx, H: ey - sy}
        else if (sx > ex && sy <= ey)
            SelectAreaState.winPos := {X: ex, Y: sy, W: sx - ex, H: ey - sy}
        else if (sx <= ex && sy > ey)
            SelectAreaState.winPos := {X: sx, Y: ey, W: ex - sx, H: sy - ey}
        else if (sx > ex && sy > ey)
            SelectAreaState.winPos := {X: ex, Y: ey, W: sx - ex, H: ey - sy}
    }
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
        MsgBox("无效的指针名字！", A_ScriptName " - SetSystemCursor(): Error", "Icon!")
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
    loop CmdArr.Length {
        paramArr := SplitCommand(CmdArr[A_Index])
        isPressKey := paramArr[1] == GetLang("按键") && paramArr[3] == GetLang("按下")
        if (isPressKey && A_Index + 1 < CmdArr.Length) {
            next1ParamArr := SplitCommand(CmdArr[A_Index + 1])
            next2ParamArr := SplitCommand(CmdArr[A_Index + 2])
            isMatchFormat := next1ParamArr[1] == GetLang("间隔") && next2ParamArr[1] == GetLang("按键")
            if (isMatchFormat && paramArr[2] == next2ParamArr[2] && next2ParamArr[3] == "松开") {
                ; 时长保底：PS5 蓝牙有时按下+松开在同 tick，间隔=0
                clickDuration := next1ParamArr[2]
                if (clickDuration < 50)
                    clickDuration := 50
                SimpleCmdStr := Format("{}_{}_{}_{}", GetLang("按键"), paramArr[2], GetLang("点击"), clickDuration)
                SimpleCmdArr.Push(SimpleCmdStr)
                A_Index := A_Index + 2
                continue
            }
        }
        SimpleCmdArr.Push(CmdArr[A_Index])
    }

    return GetMacroStrByCmdArr(SimpleCmdArr)
}

DiscardRecordTriggerKey(MacroStr, isFront) {
    triggerMap := GetRecordTriggerKeyMap()
    CmdArr := SplitMacro(MacroStr)
    SimpleCmdArr := []
    hasDiscard := false
    loop CmdArr.Length {
        cmd := isFront ? CmdArr[A_Index] : CmdArr[CmdArr.Length - A_Index + 1]

        if (!hasDiscard) {
            if (isFront && MainSoftData.IsTogStartRecord) {
                hasDiscard := true
            }
            else if (!isFront && MainSoftData.IsTogEndRecord) {
                hasDiscard := true
            }
            else {
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
        }

        if (isFront)
            SimpleCmdArr.Push(cmd)
        else
            SimpleCmdArr.InsertAt(1, cmd)
    }

    return GetMacroStrByCmdArr(SimpleCmdArr)
}

CheckIfDiscardCMD(triggerMap, cmd) {
    if (!InStr(cmd, GetLang("按键")) || InStr(cmd, GetLang("按键检测")))
        return false

    paramArr := SplitCommand(cmd)
    if (triggerMap.Has(paramArr[2]) && triggerMap[paramArr[2]] < 2) {
        triggerMap[paramArr[2]] += 1
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
    if (paramArr[1] == GetLang("移动"))
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

    ;如果， 搜索， 搜索Pro
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

OnTriggerSepcialItemMacro(MacroStr) {
    tableItem := MySoftData.SpecialTableItem
    tableItem.KilledArr[1] := false
    tableItem.PauseArr[1] := 0
    tableItem.ActionCount[1] := 0
    tableItem.index := 1
    tableItem.ColorStateArr[1] := 1
    ; F5 单跑无备注，占位空值（业务日志读取需有该下标）。
    ; SpecialTableItem 的 RemarkArr 未被 InitSingleTableState 填充（空数组），
    ; AHK v2 不允许越界下标赋值（Invalid index），需先 Push 扩容
    if (tableItem.RemarkArr.Length < 1)
        tableItem.RemarkArr.Push("")
    else
        tableItem.RemarkArr[1] := ""

    UpdateMacroRunningCount(0, 1)
    RefreshItemColorUI(tableItem.Index, 1)
    OnTriggerMacroOnce(tableItem, MacroStr, 1)
    tableItem.ColorStateArr[1] := 0
    UpdateMacroRunningCount(1, 0)
    RefreshItemColorUI(tableItem.Index, 1)
}

HandleOpenArg() {
    if (A_Args.Length <= 0) {
        if (MainSoftData.IsAdminStart && !A_IsAdmin)
            ElevateToAdmin()
        return
    }

    loop A_Args.Length {
        arg := A_Args[A_Index]
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
    loop MainSoftData.TabNameArr.Length {
        tableIndex := A_Index
        tableItem := MySoftData.TableInfo[tableIndex]
        isMacro := CheckIsMacroTable(tableIndex)
        if (!isMacro)
            continue

        for index, value in tableItem.ModeArr {
            if (tableItem.MacroArr.Length < index || tableItem.MacroArr[index] == "")
                continue

            macroStr := tableItem.MacroArr[index]
            SetGlobalData(macroStr, visitMap)
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
