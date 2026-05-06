#Include ..\Plugins\WebViewToo\Lib\WebViewToo.ahk

RMT_WEBVIEW_VERSION := "RMTv2.0.2"

class RmtWebViewGui extends WebViewGui {
    Submit(Hide := true) {
        return {}
    }
}

class RmtWebValueControl {
    __New(Value := "", Text := unset) {
        this.Value := Value
        this.Text := IsSet(Text) ? Text : Value
        this.Visible := true
        this.Enabled := true
    }

    Focus(*) {
    }

    Move(*) {
    }

    Redraw(*) {
    }

    OnEvent(*) {
    }

    SetFont(*) {
    }

    Delete(*) {
    }

    Add(*) {
    }

    Hide(*) {
        this.Visible := false
    }

    Show(*) {
        this.Visible := true
    }

    Opt(*) {
    }

    GetPos(&x?, &y?, &w?, &h?) {
        try x := 0
        try y := 0
        try w := 0
        try h := 0
    }
}

class RmtWebTabControl extends RmtWebValueControl {
    UseTab(*) {
    }
}

;窗口&UI刷新
InitUI() {
    global MySoftData, RMT_WEBVIEW_VERSION
    MyGui := RmtWebViewGui("+Resize -Caption", RMT_WEBVIEW_VERSION, , RmtGetWebViewSettings())
    MyGui.Title := RMT_WEBVIEW_VERSION
    MySoftData.MyGui := MyGui
    RmtInitWebStateControls()
    RegisterRmtWebCallbacks(MyGui)
    MyGui.BrowseFolder(A_WorkingDir)
    MyGui.Navigate("WebViewApp/dist/index.html")
    CustomTrayMenu()
    OnOpen()

}

OnOpen() {
    global MySoftData
    if (!MySoftData.AgreeAgreement) {
        Agreement1 := GetLang('1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。')
        Agreement2 := GetLang("2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。")
        Agreement3 := GetLang("3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。")
        Agreement4 := GetLang("4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。")
        Agreement5 := GetLang("若不同意上述条款，请立即停止使用本软件。")
        AgreeAgreementStr := Format("{}`n{}`n{}`n{}`n{}", Agreement1, Agreement2, Agreement3, Agreement4, Agreement5)
        result := MsgBox(AgreeAgreementStr, GetLang("免责声明"), "4")
        if (result == "No")
            ExitApp()
        IniWrite(true, IniFile, IniSection, "AgreeAgreement")
    }

    if (MySoftData.IsMinStart) {
        MySoftData.IsMinStart := false
        MySoftData.MyGui.Hide()
        return
    }

    RefreshGui()
}

RefreshGui() {
    LastWinPosStr := IniRead(IniFile, IniSection, "LastWinPos", "")
    WinPosArr := StrSplit(LastWinPosStr, "π")
    IniWrite(false, IniFile, IniSection, "IsReload")

    if (WinPosArr.Length == 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        isXValid := WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth
        isYValid := WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight
        if (isXValid && isYValid) {
            MySoftData.MyGui.Show(Format("x{} y{} w{} h{}", WinPosArr[1], WinPosArr[2], 1070, 590))
            RefreshListenVarGui()
            return
        }
    }

    if (MySoftData.LastShowMonth != A_Mon) {
        MySoftData.TabCtrl.Value := 9
        MySoftData.LastShowMonth := A_Mon
        IniWrite(MySoftData.LastShowMonth, IniFile, IniSection, "LastShowMonth")
    }

    MySoftData.MyGui.Show(Format("w{} h{}", 1070, 590))
    RefreshListenVarGui()
}

RefreshListenVarGui(isForce := false) {
    IsOenListVar := IniRead(IniFile, IniSection, "IsOpenListenVar", false)
    if (!isForce && !IsOenListVar)
        return

    LastPosStr := IniRead(IniFile, IniSection, "ListenVarPos", "")
    WinPosArr := StrSplit(LastPosStr, "π")
    if (WinPosArr.Length == 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        isXValid := WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth
        isYValid := WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight
        if (isXValid && isYValid) {
            MyVarListenGui.ShowGui()
            MyVarListenGui.Gui.Show(Format("x{} y{}", WinPosArr[1], WinPosArr[2]))
            return
        }
    }

    MyVarListenGui.ShowGui()
}

RefreshToolUI() {
    global ToolCheckInfo

    ToolCheckInfo.ToolMousePosCtrl.Value := ToolCheckInfo.PosStr
    ToolCheckInfo.ToolProcessNameCtrl.Value := ToolCheckInfo.ProcessName
    ToolCheckInfo.ToolProcessTileCtrl.Value := ToolCheckInfo.ProcessTile
    ToolCheckInfo.ToolProcessPidCtrl.Value := ToolCheckInfo.ProcessPid
    ToolCheckInfo.ToolProcessClassCtrl.Value := ToolCheckInfo.ProcessClass
    ToolCheckInfo.ToolProcessIdCtrl.Value := ToolCheckInfo.ProcessId
    ToolCheckInfo.ToolColorCtrl.Value := ToolCheckInfo.Color
    ToolCheckInfo.ToolMouseWinPosCtrl.Value := ToolCheckInfo.WinPosStr
}

RmtGetWebViewSettings() {
    settings := { DefaultWidth: 1070, DefaultHeight: 590 }
    dllPath := A_WorkingDir "\Plugins\WebViewToo\Lib\" (A_PtrSize * 8) "bit\WebView2Loader.dll"
    if (FileExist(dllPath)) {
        settings.DllPath := dllPath
    }
    else if (A_IsCompiled) {
        try {
            WebViewCtrl.CreateFileFromResource((A_PtrSize * 8) "bit\WebView2Loader.dll", WebViewCtrl.TempDir)
            settings.DllPath := WebViewCtrl.TempDir "\" (A_PtrSize * 8) "bit\WebView2Loader.dll"
        }
    }
    return settings
}

RmtInitWebStateControls() {
    global MySoftData, ToolCheckInfo, MyTriggerKeyGui, MyTriggerStrGui, MyReplaceKeyGui
    global ItemFreeConPoolMap, ItemUseConPoolMap

    MySoftData.TabCtrl := RmtWebTabControl(MySoftData.TableIndex)
    MySoftData.BtnSave := RmtWebValueControl("")
    MySoftData.SuspendToggleCtrl := RmtWebValueControl(MySoftData.IsSuspend)
    MySoftData.PauseToggleCtrl := RmtWebValueControl(MySoftData.IsPause)
    MySoftData.HoldFloatCtrl := RmtWebValueControl(MySoftData.HoldFloat)
    MySoftData.PreIntervalFloatCtrl := RmtWebValueControl(MySoftData.PreIntervalFloat)
    MySoftData.IntervalFloatCtrl := RmtWebValueControl(MySoftData.IntervalFloat)
    MySoftData.CoordXFloatCon := RmtWebValueControl(MySoftData.CoordXFloat)
    MySoftData.CoordYFloatCon := RmtWebValueControl(MySoftData.CoordYFloat)
    MySoftData.SuspendHotkeyCtrl := RmtWebValueControl(MySoftData.SuspendHotkey)
    MySoftData.PauseHotkeyCtrl := RmtWebValueControl(MySoftData.PauseHotkey)
    MySoftData.KillMacroHotkeyCtrl := RmtWebValueControl(MySoftData.KillMacroHotkey)
    MySoftData.BootStartCtrl := RmtWebValueControl(MySoftData.IsBootStart)
    MySoftData.SplitLineCtrl := RmtWebValueControl(MySoftData.ShowSplitLine)
    MySoftData.HiddenTopButtonIndexesCtrl := RmtWebValueControl(MySoftData.HiddenTopButtonIndexes)
    MySoftData.ColorPresetIdCtrl := RmtWebValueControl(MySoftData.ColorPresetId)
    MySoftData.FixedMenuWheelCtrl := RmtWebValueControl(MySoftData.FixedMenuWheel)
    MySoftData.MutiThreadNumCtrl := RmtWebValueControl(MySoftData.MutiThreadNum)
    MySoftData.SoftBGColorCon := RmtWebValueControl(MySoftData.SoftBGColor)
    MySoftData.NoVariableTipCtrl := RmtWebValueControl(MySoftData.NoVariableTip)
    MySoftData.CMDTipCtrl := RmtWebValueControl(MySoftData.CMDTip)
    MySoftData.ScreenShotTypeCtrl := RmtWebValueControl(MySoftData.ScreenShotType)
    MySoftData.KeyDownDownCon := RmtWebValueControl(MySoftData.KeyDownDownType)
    MySoftData.LangCtrl := RmtWebValueControl(MySoftData.Lang, MySoftData.Lang)
    MySoftData.FontTypeCtrl := RmtWebValueControl(MySoftData.FontType, MySoftData.FontType)
    MySoftData.RecordToggleCon := RmtWebValueControl(false)

    ToolCheckInfo.AlwaysOnTopCtrl := RmtWebValueControl(false)
    ToolCheckInfo.ToolCheckCtrl := RmtWebValueControl(ToolCheckInfo.IsToolCheck)
    ToolCheckInfo.ToolCheckHotKeyCtrl := RmtWebValueControl(ToolCheckInfo.ToolCheckHotKey)
    ToolCheckInfo.ToolMousePosCtrl := RmtWebValueControl(ToolCheckInfo.PosStr)
    ToolCheckInfo.ToolMouseWinPosCtrl := RmtWebValueControl(ToolCheckInfo.WinPosStr)
    ToolCheckInfo.ToolProcessNameCtrl := RmtWebValueControl(ToolCheckInfo.ProcessName)
    ToolCheckInfo.ToolProcessTileCtrl := RmtWebValueControl(ToolCheckInfo.ProcessTile)
    ToolCheckInfo.ToolProcessPidCtrl := RmtWebValueControl(ToolCheckInfo.ProcessPid)
    ToolCheckInfo.ToolProcessClassCtrl := RmtWebValueControl(ToolCheckInfo.ProcessClass)
    ToolCheckInfo.ToolProcessIdCtrl := RmtWebValueControl(ToolCheckInfo.ProcessId)
    ToolCheckInfo.ToolColorCtrl := RmtWebValueControl(ToolCheckInfo.Color)
    ToolCheckInfo.ToolTextFilterHotKeyCtrl := RmtWebValueControl(ToolCheckInfo.ToolTextFilterHotKey)
    ToolCheckInfo.ToolTextCtrl := RmtWebValueControl("")
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl := RmtWebValueControl(ToolCheckInfo.ToolRecordMacroHotKey)
    ToolCheckInfo.ToolCheckRecordMacroCtrl := RmtWebValueControl(ToolCheckInfo.IsToolRecord)
    ToolCheckInfo.ScreenShotHotKeyCtrl := RmtWebValueControl(ToolCheckInfo.ScreenShotHotKey)
    ToolCheckInfo.FreePasteHotKeyCtrl := RmtWebValueControl(ToolCheckInfo.FreePasteHotKey)
    ToolCheckInfo.OCRTypeCtrl := RmtWebValueControl(ToolCheckInfo.OCRTypeValue)

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        tableItem.AllConArr := []
        tableItem.AllGroup := []
        tableItem.FoldBtnArr := []
        tableItem.FoldOffsetArr := []
        if (IsObject(tableItem.FoldInfo)) {
            loop tableItem.FoldInfo.IndexSpanArr.Length {
                tableItem.FoldOffsetArr.Push(0)
            }
        }
        tableItem.ConIndexMap := Map()
        ItemFreeConPoolMap.Set(A_Index, [])
        ItemUseConPoolMap.Set(A_Index, Map())
    }

    MyTriggerKeyGui.SureFocusCon := MySoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MySoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MySoftData.BtnSave
}

RegisterRmtWebCallbacks(MyGui) {
    MyGui.AddCallbackToScript("RmtAction", RmtWebAction)
}

RmtWebAction(WebView, JsonText) {
    try {
        action := JSON.parse(JsonText, false, false)
        actionType := RmtGet(action, "type", "")
        payload := RmtGet(action, "payload", {})
        message := RmtDispatchWebAction(actionType, payload)
        return RmtWebResult(true, message)
    }
    catch as e {
        return RmtWebResult(false, e.Message)
    }
}

RmtDispatchWebAction(actionType, payload) {
    global MySoftData
    switch actionType {
        case "getState":
            return ""
        case "setTab":
            tabIndex := RmtInt(RmtGet(payload, "tabIndex", 1), 1)
            RmtSetActiveTab(tabIndex)
            return ""
        case "toggleSuspend":
            OnSuspendHotkey()
            return ""
        case "togglePause":
            OnPauseHotKey()
            return ""
        case "killAll":
            OnKillAllMacro()
            return ""
        case "save":
            OnSaveSetting()
            return ""
        case "reload":
            MenuReload()
            return ""
        case "openHelp":
            Run(A_WorkingDir "\index.html")
            return ""
        case "openUrl":
            url := RmtGet(payload, "url", "")
            if (url ~= "i)^https?://")
                Run(url)
            return ""
        case "openVarMonitor":
            MyVarListenGui.ShowGui()
            return ""
        case "openSettingManager":
            MySettingMgrGui.ShowGui()
            return ""
        case "openToolRecordSetting":
            OnClickToolRecordSettingBtn()
            return ""
        case "editCmdTip":
            OnEditCMDTipGui()
            return ""
        case "openFreePaste":
            OnToolFreePaste()
            return ""
        case "toggleToolCheck":
            RmtToggleToolCheck()
            return ""
        case "toggleToolRecord":
            RmtToggleToolRecord()
            return ""
        case "toolTextFilterScreenShot":
            OnToolTextFilterScreenShot()
            return ""
        case "toolTextFilterSelectImage":
            OnToolTextFilterSelectImage()
            return ""
        case "clearToolText":
            OnClearToolText()
            RmtPostState()
            return ""
        case "copyDiagnostics":
            return RmtCopyDiagnostics()
        case "openHotkeyEditor":
            RmtOpenHotkeyEditorAction(payload)
            return ""
        case "keyDownHelp":
            OnClickKeyDownDownHelpBtn()
            return ""
        case "minimize":
            WinMinimize("ahk_id " MySoftData.MyGui.Hwnd)
            return ""
        case "maximize":
            if (WinGetMinMax("ahk_id " MySoftData.MyGui.Hwnd) == 1)
                WinRestore("ahk_id " MySoftData.MyGui.Hwnd)
            else
                WinMaximize("ahk_id " MySoftData.MyGui.Hwnd)
            return ""
        case "close":
            ExitApp()
            return ""
        case "updateSetting":
            RmtUpdateSetting(RmtGet(payload, "field", ""), RmtGet(payload, "value", ""))
            return ""
        case "updateTool":
            RmtUpdateTool(RmtGet(payload, "field", ""), RmtGet(payload, "value", ""))
            return ""
        case "updateItem":
            RmtUpdateItem(payload)
            return ""
        case "updateFold":
            RmtUpdateFold(payload)
            return ""
        case "toggleFold":
            RmtToggleFold(payload)
            return ""
        case "addItem":
            RmtAddItemAction(payload)
            return ""
        case "deleteItem":
            RmtDeleteItemAction(payload)
            return ""
        case "moveItem":
            RmtMoveItemAction(payload)
            return ""
        case "addFold":
            RmtAddFoldAction(payload)
            return ""
        case "deleteFold":
            RmtDeleteFoldAction(payload)
            return ""
        case "openTriggerEditor":
            RmtOpenTriggerEditorAction(payload)
            return ""
        case "openMacroEditor":
            RmtOpenMacroEditorAction(payload)
            return ""
    }
    throw Error("不支持的 WebView 操作：" actionType)
}

RmtWebResult(ok, message := "") {
    result := Map()
    result["ok"] := RmtJsonBool(ok)
    result["message"] := message
    try {
        result["state"] := RmtBuildState()
    }
    catch {
        result["state"] := Map()
    }
    return JSON.stringify(result, 0)
}

RmtPostState(*) {
    global MySoftData
    try {
        stateJson := JSON.stringify(RmtBuildState(), 0)
        MySoftData.MyGui.ExecuteScriptAsync("window.__rmtReceiveState && window.__rmtReceiveState(" stateJson ");")
    }
}

RmtBuildState() {
    global MySoftData, RMT_WEBVIEW_VERSION
    state := Map()
    state["version"] := RMT_WEBVIEW_VERSION
    state["currentSettingName"] := MySoftData.CurSettingName
    state["activeTabIndex"] := RmtInt(RmtControlValue(MySoftData.TabCtrl, MySoftData.TableIndex), 1)
    state["isSuspend"] := RmtJsonBool(MySoftData.IsSuspend)
    state["isPause"] := RmtJsonBool(MySoftData.IsPause)
    state["isMacroWorking"] := RmtJsonBool(MySoftData.IsMacroWorking)
    state["macroRunningCount"] := RmtInt(MySoftData.MacroRunningCount, 0)
    state["macroTotalCount"] := RmtInt(MySoftData.MacroTotalCount, 0)
    state["tabs"] := RmtBuildTabs()
    state["settings"] := RmtBuildSettings()
    state["tools"] := RmtBuildTools()
    return state
}

RmtBuildTabs() {
    global MySoftData
    tabs := []
    loop MySoftData.TabNameArr.Length {
        tab := Map()
        tab["index"] := A_Index
        tab["name"] := MySoftData.TabNameArr[A_Index]
        tab["symbol"] := MySoftData.TabSymbolArr[A_Index]
        tab["kind"] := RmtGetTabKind(A_Index)
        if (CheckIsItemTable(A_Index))
            tab["table"] := RmtBuildTable(A_Index)
        tabs.Push(tab)
    }
    return tabs
}

RmtBuildTable(index) {
    global MySoftData
    tableItem := MySoftData.TableInfo[index]
    table := Map()
    table["index"] := index
    table["symbol"] := GetTableSymbol(index)
    table["name"] := MySoftData.TabNameArr[index]
    table["isMacroTable"] := RmtJsonBool(CheckIsMacroTable(index))
    table["isMenuTable"] := RmtJsonBool(CheckIsMenuMacroTable(index))
    table["isTimingTable"] := RmtJsonBool(CheckIsTimingMacroTable(index))
    table["isStringTable"] := RmtJsonBool(CheckIsStringMacroTable(index))
    table["isReplaceTable"] := RmtJsonBool(GetTableSymbol(index) == "Replace")
    table["folds"] := RmtBuildFolds(tableItem)
    return table
}

RmtBuildFolds(tableItem) {
    folds := []
    foldInfo := tableItem.FoldInfo
    for foldIndex, indexSpan in foldInfo.IndexSpanArr {
        fold := Map()
        fold["index"] := foldIndex
        fold["remark"] := RmtArrayGet(foldInfo.RemarkArr, foldIndex, "")
        fold["frontInfo"] := RmtArrayGet(foldInfo.FrontInfoArr, foldIndex, "")
        fold["indexSpan"] := indexSpan
        fold["forbid"] := RmtJsonBool(RmtArrayGet(foldInfo.ForbidStateArr, foldIndex, false))
        fold["collapsed"] := RmtJsonBool(RmtArrayGet(foldInfo.FoldStateArr, foldIndex, false))
        fold["triggerType"] := RmtInt(RmtArrayGet(foldInfo.TKTypeArr, foldIndex, 1), 1)
        fold["trigger"] := RmtArrayGet(foldInfo.TKArr, foldIndex, "")
        fold["holdTime"] := RmtInt(RmtArrayGet(foldInfo.HoldTimeArr, foldIndex, 500), 500)
        fold["items"] := RmtBuildFoldItems(tableItem, indexSpan)
        folds.Push(fold)
    }
    return folds
}

RmtBuildFoldItems(tableItem, indexSpan) {
    items := []
    span := StrSplit(indexSpan, "-")
    if (span.Length != 2 || !IsInteger(span[1]) || !IsInteger(span[2]))
        return items

    startIndex := Integer(span[1])
    endIndex := Integer(span[2])
    loop endIndex - startIndex + 1 {
        itemIndex := startIndex + A_Index - 1
        items.Push(RmtBuildItem(tableItem, itemIndex))
    }
    return items
}

RmtBuildItem(tableItem, itemIndex) {
    item := Map()
    item["index"] := itemIndex
    item["serial"] := RmtArrayGet(tableItem.SerialArr, itemIndex, "")
    item["colorState"] := RmtInt(RmtArrayGet(tableItem.ColorStateArr, itemIndex, 0), 0)
    if (CheckIsTimingMacroTable(tableItem.Index))
        item["trigger"] := RmtArrayGet(tableItem.TimingSerialArr, itemIndex, "")
    else
        item["trigger"] := RmtArrayGet(tableItem.TKArr, itemIndex, "")
    item["triggerType"] := RmtInt(RmtArrayGet(tableItem.TriggerTypeArr, itemIndex, 1), 1)
    item["macro"] := RmtArrayGet(tableItem.MacroArr, itemIndex, "")
    item["mode"] := RmtInt(RmtArrayGet(tableItem.ModeArr, itemIndex, 1), 1)
    item["forbid"] := RmtJsonBool(RmtArrayGet(tableItem.ForbidArr, itemIndex, false))
    item["remark"] := RmtArrayGet(tableItem.RemarkArr, itemIndex, "")
    item["loopCount"] := String(RmtArrayGet(tableItem.LoopCountArr, itemIndex, "1"))
    item["holdTime"] := RmtInt(RmtArrayGet(tableItem.HoldTimeArr, itemIndex, 500), 500)
    item["timingSerial"] := RmtArrayGet(tableItem.TimingSerialArr, itemIndex, "")
    item["startTipSound"] := RmtInt(RmtArrayGet(tableItem.StartTipSoundArr, itemIndex, 1), 1)
    item["endTipSound"] := RmtInt(RmtArrayGet(tableItem.EndTipSoundArr, itemIndex, 1), 1)
    item["pause"] := RmtJsonBool(RmtArrayGet(tableItem.PauseArr, itemIndex, false))
    return item
}

RmtBuildSettings() {
    global MySoftData
    settings := Map()
    settings["holdFloat"] := String(RmtControlValue(MySoftData.HoldFloatCtrl, MySoftData.HoldFloat))
    settings["preIntervalFloat"] := String(RmtControlValue(MySoftData.PreIntervalFloatCtrl, MySoftData.PreIntervalFloat))
    settings["intervalFloat"] := String(RmtControlValue(MySoftData.IntervalFloatCtrl, MySoftData.IntervalFloat))
    settings["coordXFloat"] := String(RmtControlValue(MySoftData.CoordXFloatCon, MySoftData.CoordXFloat))
    settings["coordYFloat"] := String(RmtControlValue(MySoftData.CoordYFloatCon, MySoftData.CoordYFloat))
    settings["suspendHotkey"] := RmtControlValue(MySoftData.SuspendHotkeyCtrl, MySoftData.SuspendHotkey)
    settings["pauseHotkey"] := RmtControlValue(MySoftData.PauseHotkeyCtrl, MySoftData.PauseHotkey)
    settings["killMacroHotkey"] := RmtControlValue(MySoftData.KillMacroHotkeyCtrl, MySoftData.KillMacroHotkey)
    settings["bootStart"] := RmtJsonBool(RmtControlValue(MySoftData.BootStartCtrl, MySoftData.IsBootStart))
    settings["showSplitLine"] := RmtJsonBool(RmtControlValue(MySoftData.SplitLineCtrl, MySoftData.ShowSplitLine))
    settings["hiddenTopButtonIndexes"] := RmtCloneArray(RmtControlValue(MySoftData.HiddenTopButtonIndexesCtrl, MySoftData.HiddenTopButtonIndexes))
    settings["colorPresetId"] := RmtControlValue(MySoftData.ColorPresetIdCtrl, MySoftData.ColorPresetId)
    settings["fixedMenuWheel"] := RmtJsonBool(RmtControlValue(MySoftData.FixedMenuWheelCtrl, MySoftData.FixedMenuWheel))
    settings["mutiThreadNum"] := String(RmtControlValue(MySoftData.MutiThreadNumCtrl, MySoftData.MutiThreadNum))
    settings["softBGColor"] := RmtControlValue(MySoftData.SoftBGColorCon, MySoftData.SoftBGColor)
    settings["noVariableTip"] := RmtJsonBool(RmtControlValue(MySoftData.NoVariableTipCtrl, MySoftData.NoVariableTip))
    settings["cmdTip"] := RmtJsonBool(RmtControlValue(MySoftData.CMDTipCtrl, MySoftData.CMDTip))
    settings["screenShotType"] := RmtInt(RmtControlValue(MySoftData.ScreenShotTypeCtrl, MySoftData.ScreenShotType), 3)
    settings["keyDownDownType"] := RmtInt(RmtControlValue(MySoftData.KeyDownDownCon, MySoftData.KeyDownDownType), 1)
    settings["lang"] := RmtControlText(MySoftData.LangCtrl, MySoftData.Lang)
    settings["fontType"] := RmtControlText(MySoftData.FontTypeCtrl, MySoftData.FontType)
    settings["langOptions"] := RmtCloneArray(MySoftData.LangArr)
    settings["fontOptions"] := RmtCloneArray(MySoftData.FontList)
    return settings
}

RmtBuildTools() {
    global ToolCheckInfo
    tools := Map()
    tools["toolCheckHotKey"] := RmtControlValue(ToolCheckInfo.ToolCheckHotKeyCtrl, ToolCheckInfo.ToolCheckHotKey)
    tools["toolRecordMacroHotKey"] := RmtControlValue(ToolCheckInfo.ToolRecordMacroHotKeyCtrl, ToolCheckInfo.ToolRecordMacroHotKey)
    tools["toolTextFilterHotKey"] := RmtControlValue(ToolCheckInfo.ToolTextFilterHotKeyCtrl, ToolCheckInfo.ToolTextFilterHotKey)
    tools["screenShotHotKey"] := RmtControlValue(ToolCheckInfo.ScreenShotHotKeyCtrl, ToolCheckInfo.ScreenShotHotKey)
    tools["freePasteHotKey"] := RmtControlValue(ToolCheckInfo.FreePasteHotKeyCtrl, ToolCheckInfo.FreePasteHotKey)
    tools["isToolCheck"] := RmtJsonBool(ToolCheckInfo.IsToolCheck)
    tools["isToolRecord"] := RmtJsonBool(RmtControlValue(ToolCheckInfo.ToolCheckRecordMacroCtrl, ToolCheckInfo.IsToolRecord))
    tools["alwaysOnTop"] := RmtJsonBool(RmtControlValue(ToolCheckInfo.AlwaysOnTopCtrl, false))
    tools["ocrType"] := RmtInt(RmtControlValue(ToolCheckInfo.OCRTypeCtrl, ToolCheckInfo.OCRTypeValue), 1)
    tools["mousePos"] := RmtControlValue(ToolCheckInfo.ToolMousePosCtrl, ToolCheckInfo.PosStr)
    tools["mouseWinPos"] := RmtControlValue(ToolCheckInfo.ToolMouseWinPosCtrl, ToolCheckInfo.WinPosStr)
    tools["processTitle"] := RmtControlValue(ToolCheckInfo.ToolProcessTileCtrl, ToolCheckInfo.ProcessTile)
    tools["processName"] := RmtControlValue(ToolCheckInfo.ToolProcessNameCtrl, ToolCheckInfo.ProcessName)
    tools["processClass"] := RmtControlValue(ToolCheckInfo.ToolProcessClassCtrl, ToolCheckInfo.ProcessClass)
    tools["processPid"] := String(RmtControlValue(ToolCheckInfo.ToolProcessPidCtrl, ToolCheckInfo.ProcessPid))
    tools["processId"] := String(RmtControlValue(ToolCheckInfo.ToolProcessIdCtrl, ToolCheckInfo.ProcessId))
    tools["color"] := RmtControlValue(ToolCheckInfo.ToolColorCtrl, ToolCheckInfo.Color)
    tools["toolText"] := RmtControlValue(ToolCheckInfo.ToolTextCtrl, "")
    return tools
}

RmtCopyDiagnostics() {
    global MySoftData, RMT_WEBVIEW_VERSION
    A_Clipboard := RmtBuildDiagnosticsText()
    return "诊断信息已复制到剪贴板"
}

RmtBuildDiagnosticsText() {
    global MySoftData, RMT_WEBVIEW_VERSION
    webViewIndex := A_WorkingDir "\WebViewApp\dist\index.html"
    loaderPath := A_WorkingDir "\Plugins\WebViewToo\Lib\" (A_PtrSize * 8) "bit\WebView2Loader.dll"
    settingsDir := A_WorkingDir "\Setting"
    workExe := A_WorkingDir "\Thread\Work1.exe"

    text := "RMT Diagnostics`r`n"
    text .= "GeneratedAt: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`r`n"
    text .= "Version: " RMT_WEBVIEW_VERSION "`r`n"
    text .= "AutoHotkeyVersion: " A_AhkVersion "`r`n"
    text .= "Compiled: " (A_IsCompiled ? "true" : "false") "`r`n"
    text .= "Bitness: " (A_PtrSize * 8) "`r`n"
    text .= "OSVersion: " A_OSVersion "`r`n"
    text .= "WorkingDir: " A_WorkingDir "`r`n"
    text .= "ScriptPath: " A_ScriptFullPath "`r`n"
    text .= "CurrentSetting: " MySoftData.CurSettingName "`r`n"
    text .= "ActiveTabIndex: " MySoftData.TableIndex "`r`n"
    text .= "MacroRunningCount: " MySoftData.MacroRunningCount "`r`n"
    text .= "MacroTotalCount: " MySoftData.MacroTotalCount "`r`n"
    text .= "IsSuspend: " (MySoftData.IsSuspend ? "true" : "false") "`r`n"
    text .= "IsPause: " (MySoftData.IsPause ? "true" : "false") "`r`n"
    text .= "IsMacroWorking: " (MySoftData.IsMacroWorking ? "true" : "false") "`r`n"
    text .= "WebViewIndex: " RmtFileStatus(webViewIndex) " - " webViewIndex "`r`n"
    text .= "WebView2Loader: " RmtFileStatus(loaderPath) " - " loaderPath "`r`n"
    text .= "SettingsDir: " RmtFileStatus(settingsDir) " - " settingsDir "`r`n"
    text .= "WorkExe: " RmtFileStatus(workExe) " - " workExe "`r`n"
    return text
}

RmtFileStatus(path) {
    return FileExist(path) ? "present" : "missing"
}

RmtGetTabKind(index) {
    symbol := GetTableSymbol(index)
    switch symbol {
        case "Tool":
            return "tool"
        case "Setting":
            return "settings"
        case "Help":
            return "help"
        case "Reward":
            return "reward"
        case "Thank":
            return "thanks"
    }
    return "macro"
}

RmtSetActiveTab(tabIndex) {
    global MySoftData
    if (tabIndex < 1 || tabIndex > MySoftData.TabNameArr.Length)
        throw Error("无效的标签页序号：" tabIndex)

    MySoftData.TabCtrl.Value := tabIndex
    MySoftData.TableIndex := tabIndex
}

RmtUpdateSetting(field, value) {
    global MySoftData
    switch field {
        case "holdFloat":
            MySoftData.HoldFloat := value
            RmtSetControl(MySoftData.HoldFloatCtrl, value)
        case "preIntervalFloat":
            MySoftData.PreIntervalFloat := value
            RmtSetControl(MySoftData.PreIntervalFloatCtrl, value)
        case "intervalFloat":
            MySoftData.IntervalFloat := value
            RmtSetControl(MySoftData.IntervalFloatCtrl, value)
        case "coordXFloat":
            MySoftData.CoordXFloat := value
            RmtSetControl(MySoftData.CoordXFloatCon, value)
        case "coordYFloat":
            MySoftData.CoordYFloat := value
            RmtSetControl(MySoftData.CoordYFloatCon, value)
        case "suspendHotkey":
            MySoftData.SuspendHotkey := value
            RmtSetControl(MySoftData.SuspendHotkeyCtrl, value)
        case "pauseHotkey":
            MySoftData.PauseHotkey := value
            RmtSetControl(MySoftData.PauseHotkeyCtrl, value)
        case "killMacroHotkey":
            MySoftData.KillMacroHotkey := value
            RmtSetControl(MySoftData.KillMacroHotkeyCtrl, value)
        case "bootStart":
            MySoftData.IsBootStart := RmtBool(value)
            RmtSetControl(MySoftData.BootStartCtrl, MySoftData.IsBootStart)
            try OnBootStartChanged()
        case "showSplitLine":
            MySoftData.ShowSplitLine := RmtBool(value)
            RmtSetControl(MySoftData.SplitLineCtrl, MySoftData.ShowSplitLine)
        case "hiddenTopButtonIndexes":
            MySoftData.HiddenTopButtonIndexes := RmtNormalizeIndexArray(value, MySoftData.TabNameArr.Length)
            RmtSetControl(MySoftData.HiddenTopButtonIndexesCtrl, MySoftData.HiddenTopButtonIndexes)
        case "colorPresetId":
            MySoftData.ColorPresetId := value
            RmtSetControl(MySoftData.ColorPresetIdCtrl, value)
        case "fixedMenuWheel":
            MySoftData.FixedMenuWheel := RmtBool(value)
            RmtSetControl(MySoftData.FixedMenuWheelCtrl, MySoftData.FixedMenuWheel)
        case "mutiThreadNum":
            MySoftData.MutiThreadNum := value
            RmtSetControl(MySoftData.MutiThreadNumCtrl, value)
        case "softBGColor":
            MySoftData.SoftBGColor := value
            RmtSetControl(MySoftData.SoftBGColorCon, value)
        case "noVariableTip":
            MySoftData.NoVariableTip := RmtBool(value)
            RmtSetControl(MySoftData.NoVariableTipCtrl, MySoftData.NoVariableTip)
        case "cmdTip":
            MySoftData.CMDTip := RmtBool(value)
            RmtSetControl(MySoftData.CMDTipCtrl, MySoftData.CMDTip)
        case "screenShotType":
            MySoftData.ScreenShotType := RmtInt(value, 3)
            RmtSetControl(MySoftData.ScreenShotTypeCtrl, MySoftData.ScreenShotType)
        case "keyDownDownType":
            MySoftData.KeyDownDownType := RmtInt(value, 1)
            RmtSetControl(MySoftData.KeyDownDownCon, MySoftData.KeyDownDownType)
        case "lang":
            MySoftData.Lang := value
            RmtSetControl(MySoftData.LangCtrl, value, value)
        case "fontType":
            MySoftData.FontType := value
            RmtSetControl(MySoftData.FontTypeCtrl, value, value)
    }
}

RmtUpdateTool(field, value) {
    global ToolCheckInfo
    switch field {
        case "toolCheckHotKey":
            ToolCheckInfo.ToolCheckHotKey := value
            RmtSetControl(ToolCheckInfo.ToolCheckHotKeyCtrl, value)
        case "toolRecordMacroHotKey":
            ToolCheckInfo.ToolRecordMacroHotKey := value
            RmtSetControl(ToolCheckInfo.ToolRecordMacroHotKeyCtrl, value)
        case "toolTextFilterHotKey":
            ToolCheckInfo.ToolTextFilterHotKey := value
            RmtSetControl(ToolCheckInfo.ToolTextFilterHotKeyCtrl, value)
        case "screenShotHotKey":
            ToolCheckInfo.ScreenShotHotKey := value
            RmtSetControl(ToolCheckInfo.ScreenShotHotKeyCtrl, value)
        case "freePasteHotKey":
            ToolCheckInfo.FreePasteHotKey := value
            RmtSetControl(ToolCheckInfo.FreePasteHotKeyCtrl, value)
        case "isToolCheck":
            ToolCheckInfo.IsToolCheck := RmtBool(value)
            RmtSetControl(ToolCheckInfo.ToolCheckCtrl, ToolCheckInfo.IsToolCheck)
        case "isToolRecord":
            ToolCheckInfo.IsToolRecord := RmtBool(value)
            RmtSetControl(ToolCheckInfo.ToolCheckRecordMacroCtrl, ToolCheckInfo.IsToolRecord)
        case "alwaysOnTop":
            RmtSetControl(ToolCheckInfo.AlwaysOnTopCtrl, RmtBool(value))
            OnToolAlwaysOnTop()
        case "ocrType":
            ToolCheckInfo.OCRTypeValue := RmtInt(value, 1)
            RmtSetControl(ToolCheckInfo.OCRTypeCtrl, ToolCheckInfo.OCRTypeValue)
    }
}

RmtToggleToolCheck() {
    OnToolCheckHotkey()
}

RmtToggleToolRecord() {
    global ToolCheckInfo
    nextState := !RmtBool(RmtControlValue(ToolCheckInfo.ToolCheckRecordMacroCtrl, ToolCheckInfo.IsToolRecord))
    ToolCheckInfo.IsToolRecord := nextState
    RmtSetControl(ToolCheckInfo.ToolCheckRecordMacroCtrl, nextState)
    OnToolRecordMacro(false)
    RmtPostState()
}

RmtOpenHotkeyEditorAction(payload) {
    global MySoftData, ToolCheckInfo, MyEditHotkeyGui
    target := RmtGet(payload, "target", "")
    onlyTriggerKey := false

    switch target {
        case "suspendHotkey":
            keyCon := MySoftData.SuspendHotkeyCtrl
            currentValue := RmtControlValue(keyCon, MySoftData.SuspendHotkey)
            onlyTriggerKey := true
        case "pauseHotkey":
            keyCon := MySoftData.PauseHotkeyCtrl
            currentValue := RmtControlValue(keyCon, MySoftData.PauseHotkey)
        case "killMacroHotkey":
            keyCon := MySoftData.KillMacroHotkeyCtrl
            currentValue := RmtControlValue(keyCon, MySoftData.KillMacroHotkey)
        case "toolCheckHotKey":
            keyCon := ToolCheckInfo.ToolCheckHotKeyCtrl
            currentValue := RmtControlValue(keyCon, ToolCheckInfo.ToolCheckHotKey)
        case "toolRecordMacroHotKey":
            keyCon := ToolCheckInfo.ToolRecordMacroHotKeyCtrl
            currentValue := RmtControlValue(keyCon, ToolCheckInfo.ToolRecordMacroHotKey)
        case "toolTextFilterHotKey":
            keyCon := ToolCheckInfo.ToolTextFilterHotKeyCtrl
            currentValue := RmtControlValue(keyCon, ToolCheckInfo.ToolTextFilterHotKey)
        case "screenShotHotKey":
            keyCon := ToolCheckInfo.ScreenShotHotKeyCtrl
            currentValue := RmtControlValue(keyCon, ToolCheckInfo.ScreenShotHotKey)
        case "freePasteHotKey":
            keyCon := ToolCheckInfo.FreePasteHotKeyCtrl
            currentValue := RmtControlValue(keyCon, ToolCheckInfo.FreePasteHotKey)
        default:
            throw Error("不支持的热键目标：" target)
    }

    showCon := RmtWebValueControl(currentValue)
    MyEditHotkeyGui.ShowGui(showCon, keyCon, onlyTriggerKey)
}

RmtUpdateItem(payload) {
    tableIndex := RmtInt(RmtGet(payload, "tableIndex", 0), 0)
    itemIndex := RmtInt(RmtGet(payload, "itemIndex", 0), 0)
    field := RmtGet(payload, "field", "")
    value := RmtGet(payload, "value", "")
    tableItem := RmtGetTableItem(tableIndex)
    RmtValidateItemIndex(tableItem, itemIndex)

    switch field {
        case "trigger":
            if (CheckIsTimingMacroTable(tableIndex))
                tableItem.TimingSerialArr[itemIndex] := value
            else
                tableItem.TKArr[itemIndex] := value
        case "triggerType":
            tableItem.TriggerTypeArr[itemIndex] := RmtInt(value, 1)
        case "macro":
            tableItem.MacroArr[itemIndex] := value
        case "mode":
            tableItem.ModeArr[itemIndex] := RmtInt(value, 1)
        case "forbid":
            tableItem.ForbidArr[itemIndex] := RmtBool(value)
        case "remark":
            tableItem.RemarkArr[itemIndex] := value
        case "loopCount":
            tableItem.LoopCountArr[itemIndex] := value
        case "holdTime":
            tableItem.HoldTimeArr[itemIndex] := RmtInt(value, 500)
        case "timingSerial":
            tableItem.TimingSerialArr[itemIndex] := value
        case "startTipSound":
            tableItem.StartTipSoundArr[itemIndex] := RmtInt(value, 1)
        case "endTipSound":
            tableItem.EndTipSoundArr[itemIndex] := RmtInt(value, 1)
    }
}

RmtUpdateFold(payload) {
    tableIndex := RmtInt(RmtGet(payload, "tableIndex", 0), 0)
    foldIndex := RmtInt(RmtGet(payload, "foldIndex", 0), 0)
    field := RmtGet(payload, "field", "")
    value := RmtGet(payload, "value", "")
    tableItem := RmtGetTableItem(tableIndex)
    foldInfo := tableItem.FoldInfo
    RmtValidateFoldIndex(foldInfo, foldIndex)

    switch field {
        case "remark":
            foldInfo.RemarkArr[foldIndex] := value
        case "frontInfo":
            foldInfo.FrontInfoArr[foldIndex] := value
        case "forbid":
            foldInfo.ForbidStateArr[foldIndex] := RmtBool(value)
        case "collapsed":
            foldInfo.FoldStateArr[foldIndex] := RmtBool(value)
        case "triggerType":
            foldInfo.TKTypeArr[foldIndex] := RmtInt(value, 1)
        case "trigger":
            foldInfo.TKArr[foldIndex] := value
        case "holdTime":
            foldInfo.HoldTimeArr[foldIndex] := RmtInt(value, 500)
    }
}

RmtToggleFold(payload) {
    tableItem := RmtGetTableItem(RmtInt(RmtGet(payload, "tableIndex", 0), 0))
    foldIndex := RmtInt(RmtGet(payload, "foldIndex", 0), 0)
    RmtValidateFoldIndex(tableItem.FoldInfo, foldIndex)
    tableItem.FoldInfo.FoldStateArr[foldIndex] := !tableItem.FoldInfo.FoldStateArr[foldIndex]
}

RmtAddItemAction(payload) {
    tableIndex := RmtInt(RmtGet(payload, "tableIndex", 0), 0)
    foldIndex := RmtInt(RmtGet(payload, "foldIndex", 0), 0)
    RmtAddItem(tableIndex, foldIndex)
}

RmtDeleteItemAction(payload) {
    tableItem := RmtGetTableItem(RmtInt(RmtGet(payload, "tableIndex", 0), 0))
    itemIndex := RmtInt(RmtGet(payload, "itemIndex", 0), 0)
    foldIndex := GetItemFoldIndex(tableItem, itemIndex)
    if (!foldIndex)
        throw Error("找不到宏条目所属模块：" itemIndex)
    RmtRemoveItem(tableItem, itemIndex, foldIndex)
}

RmtMoveItemAction(payload) {
    tableItem := RmtGetTableItem(RmtInt(RmtGet(payload, "tableIndex", 0), 0))
    itemIndex := RmtInt(RmtGet(payload, "itemIndex", 0), 0)
    direction := RmtInt(RmtGet(payload, "direction", 0), 0)
    targetIndex := itemIndex + direction
    RmtValidateItemIndex(tableItem, itemIndex)
    RmtValidateItemIndex(tableItem, targetIndex)
    SwapTableContent(tableItem, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.ColorStateArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.TimingSerialArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.StartTipSoundArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.EndTipSoundArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.IsWorkIndexArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.KilledArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.PauseArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.ActionCount, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.HoldKeyArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.ToggleStateArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.ToggleActionArr, itemIndex, targetIndex)
    RmtSwapArrayValue(tableItem.VariableMapArr, itemIndex, targetIndex)
}

RmtAddFoldAction(payload) {
    tableIndex := RmtInt(RmtGet(payload, "tableIndex", 0), 0)
    afterFoldIndex := RmtInt(RmtGet(payload, "afterFoldIndex", 0), 0)
    tableItem := RmtGetTableItem(tableIndex)
    foldInfo := tableItem.FoldInfo
    insertIndex := Min(Max(afterFoldIndex + 1, 1), foldInfo.IndexSpanArr.Length + 1)
    foldInfo.RemarkArr.InsertAt(insertIndex, "")
    foldInfo.FrontInfoArr.InsertAt(insertIndex, "")
    foldInfo.IndexSpanArr.InsertAt(insertIndex, RmtEmptySpan())
    foldInfo.ForbidStateArr.InsertAt(insertIndex, false)
    foldInfo.FoldStateArr.InsertAt(insertIndex, false)
    foldInfo.TKTypeArr.InsertAt(insertIndex, 1)
    foldInfo.TKArr.InsertAt(insertIndex, "")
    foldInfo.HoldTimeArr.InsertAt(insertIndex, 500)
    tableItem.FoldOffsetArr.InsertAt(insertIndex, CheckIsMenuMacroTable(tableIndex) ? 85 : 55)
    if (CheckIsMenuMacroTable(tableIndex)) {
        loop 8 {
            RmtAddItem(tableIndex, insertIndex, 0)
        }
    }
}

RmtDeleteFoldAction(payload) {
    tableItem := RmtGetTableItem(RmtInt(RmtGet(payload, "tableIndex", 0), 0))
    foldIndex := RmtInt(RmtGet(payload, "foldIndex", 0), 0)
    foldInfo := tableItem.FoldInfo
    RmtValidateFoldIndex(foldInfo, foldIndex)
    if (foldInfo.IndexSpanArr.Length == 1)
        throw Error("不能删除最后一个模块。")

    span := StrSplit(foldInfo.IndexSpanArr[foldIndex], "-")
    if (span.Length == 2 && IsInteger(span[1]) && IsInteger(span[2])) {
        endIndex := Integer(span[2])
        loop endIndex - Integer(span[1]) + 1 {
            RmtRemoveItem(tableItem, endIndex - A_Index + 1, foldIndex)
        }
    }
    foldInfo.RemarkArr.RemoveAt(foldIndex)
    foldInfo.FrontInfoArr.RemoveAt(foldIndex)
    foldInfo.IndexSpanArr.RemoveAt(foldIndex)
    foldInfo.ForbidStateArr.RemoveAt(foldIndex)
    foldInfo.FoldStateArr.RemoveAt(foldIndex)
    foldInfo.TKTypeArr.RemoveAt(foldIndex)
    foldInfo.TKArr.RemoveAt(foldIndex)
    foldInfo.HoldTimeArr.RemoveAt(foldIndex)
    if (tableItem.FoldOffsetArr.Length >= foldIndex)
        tableItem.FoldOffsetArr.RemoveAt(foldIndex)
}

RmtOpenMacroEditorAction(payload) {
    global MySoftData, MyMacroGui, MyReplaceKeyGui, MyTimingGui
    tableIndex := RmtInt(RmtGet(payload, "tableIndex", 0), 0)
    itemIndex := RmtInt(RmtGet(payload, "itemIndex", 0), 0)
    tableItem := RmtGetTableItem(tableIndex)
    if (itemIndex < 1) {
        MyMacroGui.SureFocusCon := MySoftData.BtnSave
        MyMacroGui.SaveBtnAction := OnSaveSetting
        MyMacroGui.ShowGui("", true)
        return
    }

    RmtValidateItemIndex(tableItem, itemIndex)
    if (CheckIsTimingMacroTable(tableIndex)) {
        MyTimingGui.ShowGui(tableItem.TimingSerialArr[itemIndex])
        return
    }
    if (GetTableSymbol(tableIndex) == "Replace") {
        SureReplace(sureMacro) {
            tableItem.MacroArr[itemIndex] := sureMacro
            RmtPostState()
        }
        MyReplaceKeyGui.SureBtnAction := SureReplace
        MyReplaceKeyGui.ShowGui(tableItem.MacroArr[itemIndex])
        return
    }

    SureMacro(sureMacro) {
        tableItem.MacroArr[itemIndex] := sureMacro
        RmtPostState()
    }

    MySoftData.SpecialTableItem.ModeArr[1] := tableItem.ModeArr[itemIndex]
    if (MyMacroGui.Gui != "") {
        style := WinGetStyle(MyMacroGui.Gui.Hwnd)
        isVisible := (style & 0x10000000)
        if (isVisible) {
            MacroGui := MacroEditGui()
            MacroGui.SureFocusCon := MySoftData.BtnSave
            MacroGui.SureBtnAction := SureMacro
            MacroGui.SaveBtnAction := OnSaveSetting
            MacroGui.ShowGui(tableItem.MacroArr[itemIndex], true)
            return
        }
    }
    MyMacroGui.SureFocusCon := MySoftData.BtnSave
    MyMacroGui.SureBtnAction := SureMacro
    MyMacroGui.SaveBtnAction := OnSaveSetting
    MyMacroGui.ShowGui(tableItem.MacroArr[itemIndex], true)
}

RmtOpenTriggerEditorAction(payload) {
    global MySoftData, MyTriggerKeyGui, MyTriggerStrGui, MyTimingGui
    tableIndex := RmtInt(RmtGet(payload, "tableIndex", 0), 0)
    tableItem := RmtGetTableItem(tableIndex)
    foldIndex := RmtInt(RmtGet(payload, "foldIndex", 0), 0)
    itemIndex := RmtInt(RmtGet(payload, "itemIndex", 0), 0)

    if (foldIndex > 0) {
        foldInfo := tableItem.FoldInfo
        RmtValidateFoldIndex(foldInfo, foldIndex)

        SureFoldTrigger(sureTriggerKey, holdTime) {
            foldInfo.TKArr[foldIndex] := sureTriggerKey
            foldInfo.HoldTimeArr[foldIndex] := holdTime
            RmtPostState()
        }

        MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
        MyTriggerKeyGui.SureBtnAction := SureFoldTrigger
        MyTriggerKeyGui.SureFocusCon := MySoftData.BtnSave
        MyTriggerKeyGui.ShowGui(foldInfo.TKArr[foldIndex], foldInfo.HoldTimeArr[foldIndex], false)
        return
    }

    RmtValidateItemIndex(tableItem, itemIndex)
    if (CheckIsTimingMacroTable(tableIndex)) {
        MyTimingGui.ShowGui(tableItem.TimingSerialArr[itemIndex])
        return
    }

    if (CheckIsStringMacroTable(tableIndex)) {
        SureStringTrigger(sureTriggerKey) {
            tableItem.TKArr[itemIndex] := sureTriggerKey
            RmtPostState()
        }

        MyTriggerStrGui.SaveBtnAction := OnSaveSetting
        MyTriggerStrGui.SureBtnAction := SureStringTrigger
        MyTriggerStrGui.SureFocusCon := MySoftData.BtnSave
        MyTriggerStrGui.ShowGui(tableItem.TKArr[itemIndex], 0, false)
        return
    }

    SureKeyTrigger(sureTriggerKey, holdTime) {
        tableItem.TKArr[itemIndex] := sureTriggerKey
        tableItem.HoldTimeArr[itemIndex] := holdTime
        RmtPostState()
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureKeyTrigger
    MyTriggerKeyGui.SureFocusCon := MySoftData.BtnSave
    MyTriggerKeyGui.ShowGui(tableItem.TKArr[itemIndex], tableItem.HoldTimeArr[itemIndex], false)
}

RmtAddItem(tableIndex, foldIndex, tipSound := 1) {
    global MySoftData
    tableItem := RmtGetTableItem(tableIndex)
    foldInfo := tableItem.FoldInfo
    RmtValidateFoldIndex(foldInfo, foldIndex)
    addIndex := GetFoldAddItemIndex(foldInfo, foldIndex)
    UpdateFoldIndexInfo(foldInfo, addIndex, foldIndex, true)
    foldInfo.FoldStateArr[foldIndex] := false
    tableItem.ColorStateArr.InsertAt(addIndex, 0)
    tableItem.TKArr.InsertAt(addIndex, "")
    tableItem.TriggerTypeArr.InsertAt(addIndex, 1)
    tableItem.MacroArr.InsertAt(addIndex, "")
    tableItem.ModeArr.InsertAt(addIndex, 1)
    tableItem.ForbidArr.InsertAt(addIndex, 0)
    tableItem.RemarkArr.InsertAt(addIndex, "")
    tableItem.LoopCountArr.InsertAt(addIndex, "1")
    tableItem.HoldTimeArr.InsertAt(addIndex, 500)
    tableItem.SerialArr.InsertAt(addIndex, GetCMDSerialStr("Item"))
    tableItem.TimingSerialArr.InsertAt(addIndex, GetCMDSerialStr("Timing"))
    tableItem.StartTipSoundArr.InsertAt(addIndex, tipSound)
    tableItem.EndTipSoundArr.InsertAt(addIndex, tipSound)
    tableItem.IsWorkIndexArr.InsertAt(addIndex, 0)
    tableItem.HoldKeyArr.InsertAt(addIndex, Map())
    tableItem.KilledArr.InsertAt(addIndex, false)
    tableItem.PauseArr.InsertAt(addIndex, MySoftData.IsPause)
    tableItem.ActionCount.InsertAt(addIndex, 0)
    tableItem.ToggleStateArr.InsertAt(addIndex, false)
    tableItem.ToggleActionArr.InsertAt(addIndex, "")
    tableItem.VariableMapArr.InsertAt(addIndex, RmtCreateVariableMap())
}

RmtRemoveItem(tableItem, itemIndex, foldIndex) {
    RmtValidateItemIndex(tableItem, itemIndex)
    UpdateFoldIndexInfo(tableItem.FoldInfo, itemIndex, foldIndex, false)
    RmtRemoveArrayAt(tableItem.ColorStateArr, itemIndex)
    RmtRemoveArrayAt(tableItem.SerialArr, itemIndex)
    RmtRemoveArrayAt(tableItem.TKArr, itemIndex)
    RmtRemoveArrayAt(tableItem.MacroArr, itemIndex)
    RmtRemoveArrayAt(tableItem.LoopCountArr, itemIndex)
    RmtRemoveArrayAt(tableItem.ModeArr, itemIndex)
    RmtRemoveArrayAt(tableItem.ForbidArr, itemIndex)
    RmtRemoveArrayAt(tableItem.HoldTimeArr, itemIndex)
    RmtRemoveArrayAt(tableItem.RemarkArr, itemIndex)
    RmtRemoveArrayAt(tableItem.TriggerTypeArr, itemIndex)
    RmtRemoveArrayAt(tableItem.TimingSerialArr, itemIndex)
    RmtRemoveArrayAt(tableItem.StartTipSoundArr, itemIndex)
    RmtRemoveArrayAt(tableItem.EndTipSoundArr, itemIndex)
    RmtRemoveArrayAt(tableItem.IsWorkIndexArr, itemIndex)
    RmtRemoveArrayAt(tableItem.HoldKeyArr, itemIndex)
    RmtRemoveArrayAt(tableItem.KilledArr, itemIndex)
    RmtRemoveArrayAt(tableItem.PauseArr, itemIndex)
    RmtRemoveArrayAt(tableItem.ActionCount, itemIndex)
    RmtRemoveArrayAt(tableItem.ToggleStateArr, itemIndex)
    RmtRemoveArrayAt(tableItem.ToggleActionArr, itemIndex)
    RmtRemoveArrayAt(tableItem.VariableMapArr, itemIndex)
}

RmtCreateVariableMap() {
    variableMap := Map()
    variableMap["宏循环次数"] := 0
    variableMap["循环-跳过本轮"] := false
    variableMap["循环-跳出"] := false
    variableMap["分支-跳出"] := false
    return variableMap
}

RmtGetTableItem(tableIndex) {
    global MySoftData
    if (tableIndex < 1 || tableIndex > MySoftData.TableInfo.Length)
        throw Error("无效的表格序号：" tableIndex)
    return MySoftData.TableInfo[tableIndex]
}

RmtValidateFoldIndex(foldInfo, foldIndex) {
    if (foldIndex < 1 || foldIndex > foldInfo.IndexSpanArr.Length)
        throw Error("无效的模块序号：" foldIndex)
}

RmtValidateItemIndex(tableItem, itemIndex) {
    if (itemIndex < 1 || itemIndex > tableItem.ModeArr.Length)
        throw Error("无效的宏条目序号：" itemIndex)
}

RmtRemoveArrayAt(arr, index) {
    if (arr.Length >= index)
        arr.RemoveAt(index)
}

RmtSwapArrayValue(arr, indexA, indexB) {
    if (arr.Length < indexA || arr.Length < indexB)
        return
    temp := arr[indexA]
    arr[indexA] := arr[indexB]
    arr[indexB] := temp
}

RmtSetControl(control, value, text := unset) {
    control.Value := value
    control.Text := IsSet(text) ? text : value
}

RmtControlValue(control, fallback := "") {
    try return control.Value
    return fallback
}

RmtControlText(control, fallback := "") {
    try return control.Text
    return fallback
}

RmtArrayGet(arr, index, fallback := "") {
    try return arr[index]
    return fallback
}

RmtCloneArray(arr) {
    clone := []
    for index, value in arr {
        clone.Push(value)
    }
    return clone
}

RmtNormalizeIndexArray(value, maxIndex := 0) {
    if (value is Array)
        return RmtFilterIndexArray(value, maxIndex)
    return RmtParseIndexList(value, maxIndex)
}

RmtFilterIndexArray(values, maxIndex := 0) {
    indexes := []
    seen := Map()
    for _, value in values {
        if (!IsInteger(value))
            continue
        index := Integer(value)
        if (index < 1 || index == 8 || (maxIndex > 0 && index > maxIndex) || seen.Has(index))
            continue
        seen[index] := true
        indexes.Push(index)
    }
    return indexes
}

RmtGet(obj, key, fallback := "") {
    if (!IsObject(obj))
        return fallback
    if (obj is Map)
        return obj.Has(key) ? obj[key] : fallback
    if (ObjHasOwnProp(obj, key))
        return obj.%key%
    return fallback
}

RmtInt(value, fallback := 0) {
    try {
        if (IsInteger(value))
            return Integer(value)
    }
    return fallback
}

RmtBool(value) {
    if (value is String) {
        value := StrLower(value)
        return value == "true" || value == "1"
    }
    return !!value
}

RmtJsonBool(value) {
    return RmtBool(value) ? JSON.true : JSON.false
}

RmtEmptySpan() {
    return "无-无"
}

; 添加控件到表格中，自动记录位置信息
AddTableControl(Type, Options, Text, tableItem, FoldIndex := 1) {
    global MySoftData
    con := MySoftData.MyGui.Add(Type, Options, Text)
    conInfo := ItemConInfo(con, tableItem, FoldIndex)
    tableItem.AllConArr.Push(conInfo)
    return con
}

;UI元素相关函数
AddUI() {
    global MySoftData
    MyGui := MySoftData.MyGui
    AddOperBtnUI()
    MySoftData.TabPosY := 10
    MySoftData.TabPosX := 130
    MySoftData.TabCtrl := MyGui.Add("Tab3", Format("x{} y{} w{} Choose{}", MySoftData.TabPosX, MySoftData.TabPosY, 910,
        MySoftData.TableIndex), GetLangArr(MySoftData.TabNameArr))

    loop MySoftData.TabNameArr.Length {
        MySoftData.TabCtrl.UseTab(A_Index)
        func := GetUIAddFunc(A_Index)
        func(A_Index)
    }
    MySoftData.TabCtrl.UseTab()
    MySoftData.TabCtrl.Move(MySoftData.TabPosX, MySoftData.TabPosY, 920, 570)
    MySoftData.TabCtrl.OnEvent("Change", OnTabValueChanged)
    AddSliderUI()
}

AddSliderUI() {
    MyGui := MySoftData.MyGui
    areaCon := MyGui.Add("Pic", Format("x{} y{} w{} h{} +Background0x{}", 1045, 37, 15, 541, "d1d1d1"), "")
    barCon := MyGui.Add("Text", Format("x{} y{} w{} h{} +Background0x{}", 1045, 37, 15, 250, "9f9f9f"), "")
    tableItem := MySoftData.TableInfo[MySoftData.TableIndex]
    MySlider.SetSliderCon(areaCon, barCon)
    MySlider.SetStyleParams(2, 2)
    MySlider.SwitchTab(tableItem)
}

AddOperBtnUI() {
    MyGui := MySoftData.MyGui
    posY := 10
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{} center", 10, posY, 110, 110), GetLang("当前配置"))

    ; 当前配置
    posY += 25
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} Center", 15, posY, 100, 45), MySoftData.CurSettingName)
    posY += 45
    con := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("配置管理"))
    con.OnEvent("Click", (*) => MySettingMgrGui.ShowGui())

    posY += 45
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{} center", 10, posY, 110, 455), GetLang("全局操作"))

    posY += 25
    ; 休眠
    MySoftData.SuspendToggleCtrl := MyGui.Add("CheckBox", Format("x{} y{} w{} h{}", 15, posY, 100, 20), GetLang("休眠"))
    MySoftData.SuspendToggleCtrl.Value := MySoftData.IsSuspend
    MySoftData.SuspendToggleCtrl.OnEvent("Click", OnSuspendHotkey)
    posY += 20
    CtrlType := GetHotKeyCtrlType(MySoftData.SuspendHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MySoftData.SuspendHotkey)
    con.Enabled := false
    posY += 40

    ; 暂停
    MySoftData.PauseToggleCtrl := MyGui.Add("CheckBox", Format("x{} y{} w{} h{}", 15, posY, 100, 20), GetLang("暂停"))
    MySoftData.PauseToggleCtrl.Value := MySoftData.IsPause
    MySoftData.PauseToggleCtrl.OnEvent("Click", OnPauseHotKey)
    posY += 20
    CtrlType := GetHotKeyCtrlType(MySoftData.PauseHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MySoftData.PauseHotkey)
    con.Enabled := false
    posY += 40

    ;终止模块
    con := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("终止所有宏"))
    con.OnEvent("Click", OnKillAllMacro)
    posY += 31
    CtrlType := GetHotKeyCtrlType(MySoftData.KillMacroHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MySoftData.KillMacroHotkey)
    con.Enabled := false
    posY += 40

    ReloadBtnCtrl := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("重载"))
    ReloadBtnCtrl.OnEvent("Click", MenuReload)
    posY += 40

    posY := 505
    btnHelp := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("RMT文档"))
    btnHelp.OnEvent("Click", (*) => Run(A_WorkingDir "\index.html"))

    posY := 540
    MySoftData.BtnSave := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("应用并保存"))
    MySoftData.BtnSave.OnEvent("Click", OnSaveSetting)

    MyTriggerKeyGui.SureFocusCon := MySoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MySoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MySoftData.BtnSave
}

GetUIAddFunc(index) {
    UIAddFuncArr := [LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold,
        AddToolUI, AddSettingUI, AddHelpUI, AddRewardUI, AddThankUI]
    return UIAddFuncArr[index]
}

;工具
AddToolUI(index) {
    global ToolCheckInfo

    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX
    ; 配置规则说明
    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("变量监视器："), tableItem)
    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 120, posY - 3, 130), GetLang("打开监视器"), tableItem)
    con.OnEvent("Click", (*) => MyVarListenGui.ShowGui())

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("鼠标信息："), tableItem)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolCheckHotkey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolCheckHotkey,
    tableItem).Enabled := false

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"), tableItem)
    ToolCheckInfo.ToolCheckCtrl := con
    ToolCheckInfo.ToolCheckCtrl.Value := ToolCheckInfo.IsToolCheck
    ToolCheckInfo.ToolCheckCtrl.OnEvent("Click", OnToolCheckHotkey)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 400, posY, 60), GetLang("窗口置顶"), tableItem)
    ToolCheckInfo.AlwaysOnTopCtrl := con
    ToolCheckInfo.AlwaysOnTopCtrl.Value := false
    ToolCheckInfo.AlwaysOnTopCtrl.OnEvent("Click", OnToolAlwaysOnTop)

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("屏幕坐标："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.PosStr, tableItem)
    ToolCheckInfo.ToolMousePosCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("窗口坐标："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.WinPosStr, tableItem)
    ToolCheckInfo.ToolMouseWinPosCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口标题："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessTile, tableItem)
    ToolCheckInfo.ToolProcessTileCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程名："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.ProcessName, tableItem)
    ToolCheckInfo.ToolProcessNameCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口类："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessClass, tableItem)
    ToolCheckInfo.ToolProcessClassCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程PID:"), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.ProcessPid, tableItem)
    ToolCheckInfo.ToolProcessPidCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("句柄Id:"), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessId, tableItem)
    ToolCheckInfo.ToolProcessIdCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("位置颜色："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.Color, tableItem)
    ToolCheckInfo.ToolColorCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("指令录制："), tableItem)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolRecordMacroHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolRecordMacroHotKey,
    tableItem).Enabled := false

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"), tableItem)
    ToolCheckInfo.ToolCheckRecordMacroCtrl := con
    ToolCheckInfo.ToolCheckRecordMacroCtrl.Value := ToolCheckInfo.IsToolRecord
    ToolCheckInfo.ToolCheckRecordMacroCtrl.OnEvent("Click", OnHotToolRecordMacro.Bind(false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("图片文本提取："), tableItem)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolTextFilterHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolTextFilterHotKey,
    tableItem).Enabled := false

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 260, posY - 5, 100), GetLang("截图提取文本"), tableItem)
    con.OnEvent("Click", OnToolTextFilterScreenShot)

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 400, posY - 5, 120), GetLang("从图片提取文本"), tableItem)
    con.OnEvent("Click", OnToolTextFilterSelectImage)

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("相关选项："), tableItem)

    AddTableControl("Text", Format("x{} y{} w{}", PosX + 120, PosY, 110), GetLang("文本识别模型："), tableItem)

    con := AddTableControl("DropDownList", Format("x{} y{} w{}", PosX + 260, PosY - 5, 100), GetLangArr(["中文", "英文"]),
    tableItem)
    ToolCheckInfo.OCRTypeCtrl := con
    ToolCheckInfo.OCRTypeCtrl.Value := ToolCheckInfo.OCRTypeValue

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("录制的指令或提取的文本内容："), tableItem)

    con := AddTableControl("Button", Format("x{} y{} w{} h{}", posX + 260, posY - 5, 80, 25), GetLang("清空内容"),
    tableItem)
    con.OnEvent("Click", OnClearToolText)

    posY += 25
    con := ToolCheckInfo.ToolTextCtrl := AddTableControl("Edit", Format("x{} y{} w{} h{}", posX + 20, posY, 800, 140),
    "", tableItem)

    posY += 100
    MySoftData.TableInfo[index].underPosY := posY
}

;设置
AddSettingUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX

    posY += 30
    posX := MySoftData.TabPosX
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("快捷键修改"), tableItem)
    tableItem.AllGroup.Push(con)

    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件休眠："), tableItem)
    CtrlType := GetHotKeyCtrlType(MySoftData.SuspendHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), MySoftData.SuspendHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), MySoftData.SuspendHotkey, tableItem)
    MySoftData.SuspendHotkeyCtrl := con
    MySoftData.SuspendHotkeyCtrl.Visible := false

    con := AddTableControl("Button", Format("x{} y{} w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.SuspendHotkeyCtrl, true))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("暂停宏："), tableItem)
    CtrlType := GetHotKeyCtrlType(MySoftData.PauseHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), MySoftData.PauseHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), MySoftData.PauseHotkey, tableItem)
    MySoftData.PauseHotkeyCtrl := con
    MySoftData.PauseHotkeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.PauseHotkeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 605, posY), GetLang("终止宏："), tableItem)
    CtrlType := GetHotKeyCtrlType(MySoftData.KillMacroHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), MySoftData.KillMacroHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 680, posY), MySoftData.KillMacroHotkey, tableItem)
    MySoftData.KillMacroHotkeyCtrl := con
    MySoftData.KillMacroHotkeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.KillMacroHotkeyCtrl, false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("指令录制："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolRecordMacroHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), ToolCheckInfo.ToolRecordMacroHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), ToolCheckInfo.ToolRecordMacroHotKey,
    tableItem)
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl := con
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolRecordMacroHotKeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("文本提取："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolTextFilterHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), ToolCheckInfo.ToolTextFilterHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), ToolCheckInfo.ToolTextFilterHotKey,
    tableItem)
    ToolCheckInfo.ToolTextFilterHotKeyCtrl := con
    ToolCheckInfo.ToolTextFilterHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolTextFilterHotKeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 605, posY), GetLang("屏幕截图："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ScreenShotHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), ToolCheckInfo.ScreenShotHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 680, posY), ToolCheckInfo.ScreenShotHotKey, tableItem)
    ToolCheckInfo.ScreenShotHotKeyCtrl := con
    ToolCheckInfo.ScreenShotHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ScreenShotHotKeyCtrl, false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("自由贴："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.FreePasteHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), ToolCheckInfo.FreePasteHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), ToolCheckInfo.FreePasteHotKey, tableItem)
    ToolCheckInfo.FreePasteHotKeyCtrl := con
    ToolCheckInfo.FreePasteHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.FreePasteHotKeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("鼠标信息："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolCheckHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), ToolCheckInfo.ToolCheckHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), ToolCheckInfo.ToolCheckHotkey, tableItem)
    ToolCheckInfo.ToolCheckHotKeyCtrl := con
    ToolCheckInfo.ToolCheckHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolCheckHotKeyCtrl, false))

    posY += 40
    posX := MySoftData.TabPosX
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("数值选项"), tableItem)
    tableItem.AllGroup.Push(con)
    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("点击时间浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.HoldFloat, tableItem
    )
    MySoftData.HoldFloatCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("每次间隔浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MySoftData.PreIntervalFloat,
    tableItem)
    MySoftData.PreIntervalFloatCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("间隔指令浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.IntervalFloat,
    tableItem)
    MySoftData.IntervalFloatCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("坐标X浮动(px)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.CoordXFloat,
    tableItem)
    MySoftData.CoordXFloatCon := con

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("坐标Y浮动(px)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MySoftData.CoordYFloat,
    tableItem)
    MySoftData.CoordYFloatCon := con

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("多线程数(-1~10)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.MutiThreadNum, tableItem)
    MySoftData.MutiThreadNumCtrl := con

    ; posY += 40
    ; AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("核心池大小(1~10)："), tableItem)
    ; con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.DynamicCorePoolSize, tableItem)
    ; MySoftData.DynamicCorePoolSizeCtrl := con

    ; posY += 40
    ; AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("弹性超时(秒)："), tableItem)
    ; con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.ElasticTimeout, tableItem)
    ; MySoftData.ElasticTimeoutCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件背景颜色："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.SoftBGColor,
    tableItem)
    MySoftData.SoftBGColorCon := con

    posY += 40
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h150", posX + 10, posY), GetLang("开关选项"), tableItem)
    tableItem.AllGroup.Push(con)
    posY += 30

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("开机自启"), tableItem)
    MySoftData.BootStartCtrl := con
    MySoftData.BootStartCtrl.Value := MySoftData.IsBootStart
    MySoftData.BootStartCtrl.OnEvent("Click", OnBootStartChanged)

    con := AddTableControl("CheckBox", Format("x{} y{} -Wrap w15", posX + 315, posY), "", tableItem)
    MySoftData.CMDTipCtrl := con
    MySoftData.CMDTipCtrl.Value := MySoftData.CMDTip
    con := AddTableControl("Button", Format("x{} y{}", posX + 315 + 15, posY - 5), GetLang("指令显示"), tableItem)
    con.OnEvent("Click", (*) => OnEditCMDTipGui())

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 635, posY - 5, 100), GetLang("录制选项"), tableItem)
    con.OnEvent("Click", OnClickToolRecordSettingBtn)

    posY += 40
    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("无变量提醒"), tableItem)
    MySoftData.NoVariableTipCtrl := con
    MySoftData.NoVariableTipCtrl.Value := MySoftData.NoVariableTip

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 315, posY), GetLang("菜单轮位置固定"), tableItem)
    MySoftData.FixedMenuWheelCtrl := con
    MySoftData.FixedMenuWheelCtrl.Value := MySoftData.FixedMenuWheel
    MySoftData.FixedMenuWheelCtrl.OnEvent("Click", OnMenuWheelPosChanged)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 635, posY), GetLang("分割线"), tableItem)
    MySoftData.SplitLineCtrl := con
    MySoftData.SplitLineCtrl.Value := MySoftData.ShowSplitLine

    posY += 40
    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("模态子窗口"), tableItem)
    MySoftData.ModalSubGuiCtrl := con
    MySoftData.ModalSubGuiCtrl.Value := MySoftData.IsModalSubGui

    posY += 40
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h100", posX + 10, posY), GetLang("下拉框选项"), tableItem)
    tableItem.AllGroup.Push(con)

    ;语言/Lang： 如果外国人打开中文的话，或者中国人打开英语，方便都能找到调整的选项
    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), "语言/Lang：", tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 110, posY - 4), [], tableItem)
    MySoftData.LangCtrl := con
    MySoftData.LangCtrl.Delete()
    MySoftData.LangCtrl.Add(MySoftData.LangArr)
    MySoftData.LangCtrl.Text := MySoftData.Lang

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("软件字体："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w180", posX + 390, posY - 4), [], tableItem)
    MySoftData.FontTypeCtrl := con
    MySoftData.FontTypeCtrl.Delete()
    MySoftData.FontTypeCtrl.Add(MySoftData.FontList)
    MySoftData.FontTypeCtrl.Text := MySoftData.FontType

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("截图方式："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 710, posY - 4), GetLangArr(["微软截图",
        "RMT截图", "SC截图"]), tableItem)
    MySoftData.ScreenShotTypeCtrl := con
    MySoftData.ScreenShotTypeCtrl.Value := MySoftData.ScreenShotType

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("按下时按下："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 110, posY - 4), GetLangArr(["自动松开", "忽略重复按下",
        "允许重复按下"]), tableItem)
    MySoftData.KeyDownDownCon := con
    MySoftData.KeyDownDownCon.Value := MySoftData.KeyDownDownType
    Con := AddTableControl("Button", Format("x{} y{} h27", posX + 231, posY - 4), "?", tableItem)
    Con.OnEvent("Click", OnClickKeyDownDownHelpBtn)

    posY += 30
    tableItem.UnderPosY := posY
}

;帮助
AddHelpUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX

    posY += 40
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 25), GetLang("免责声明"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 14, 600, 2)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 35), GetLang(
        "本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 10, 600, 0)))

    posY += 40
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        '1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。'), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        "2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        "3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 50), GetLang(
        "4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 50
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 800, 35), GetLang(
        "若不同意上述条款，请立即停止使用本软件。"), tableItem)
    con.SetFont((Format("cRed  S{} W{} Q{}", 12, 600, 0)))

    posY += 50
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("更新视频合集："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format(
        '<a href="https://www.bilibili.com/video/BV1oWVRzaEzk">{}</a>', GetLang("版本更新视频，直播交流问答")), tableItem).SetFont((
            Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    LinkStr := A_WorkingDir "\index.html"
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("操作说明文档："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format('<a href="{}">{}</a>', LinkStr,
        GetLang("快速上手，指令手册、常见问题、常见报错、更新日志等")), tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("配置共享仓库："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format(
        '<a href="https://zclucas.github.io/RMT-Setting/">{}</a>', GetLang("案例学习、获取他人分享的宏配置（支持下载导入）")), tableItem).SetFont((
            Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("国内开源网址："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://gitee.com/fateman/RMT">https://gitee.com/fateman/RMT</a>', tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("国外开源网址："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://github.com/zclucas/RMT">https://github.com/zclucas/RMT</a>', tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件检查更新："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), GetLang("浏览开源网址，查看右侧发行版处即可知道软件最新版本"),
    tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件交流渠道："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30),
    '<a href="https://qm.qq.com/q/DgpDumEPzq">QQ群（837661891）</a>、<a href="https://pd.qq.com/s/5wyjvj7zw">QQ频道</a>、<a href="https://github.com/zclucas/RMT/discussions">GitHub 论坛</a>、<a href="https://discord.gg/m8ewvgtzat">Discord</a>',
    tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件反馈表格："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    str1 := Format('<a href="https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj">{}</a>', GetLang("bug文档"))
    str2 := Format('<a href="https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo">{}</a>', GetLang("需求文档"))
    str3 := Format('<a href="https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2">{}</a>', GetLang("使用备注"))
    str4 := GetLang("（仅交流群成员有编辑权限）")
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30), Format("{}、{}、{}{}", str1, str2, str3,
        str4), tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件开源协议："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), "AGPL-3.0", tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    ; posY += 35
    tableItem.underPosY := posY
}

;打赏
AddRewardUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX

    posY += 40
    posX += 15
    countStr := FormatIntegerWithCommas(MySoftData.MacroTotalCount)
    str1 := GetLang("若梦兔（RMT）—— 这款完全免费的开源软件，始终陪在你身边。")
    str2 := Format(GetLang("至今已为您执行 {:} 次宏指令。"), countStr)
    str3 := GetLang("诚邀本月打赏成为若梦兔的 “守护者”，一起让若梦兔走得更远。")
    str := Format("{}`n{}`n{}", str1, str2, str3)
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 80), str, tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 100
    posX := MySoftData.TabPosX + 100
    AddTableControl("Picture", Format("x{} y{} w{} h{} center", posX, posY, 220, 220), "Images\Soft\WeiXin.png",
    tableItem)
    AddTableControl("Text", Format("x{} y{} w{} h{} center", posX, posY + 230, 220, 50), GetLang("微信打赏"), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    posX += 450
    AddTableControl("Picture", Format("x{} y{} w{} h{} center", posX, posY, 220, 220), "Images\Soft\ZhiFuBao.png",
    tableItem)
    AddTableControl("Text", Format("x{} y{} w{} h{} center", posX, posY + 230, 220, 50), GetLang("支付宝打赏"), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 300
    posX := MySoftData.TabPosX + 15
    str := Format("{}`n{}", GetLang("当然，如果你暂时不方便，分享给朋友也是很棒的支持~"), GetLang("开发不易，感谢你的每一份温暖！"))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 860, 80), str, tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 35
    tableItem.underPosY := posY
}

; 系统托盘优化
CustomTrayMenu() {
    loop 30 {
        if (WinExist("ahk_class Shell_TrayWnd")) {
            break
        }
        Sleep(1000)
    }
    tipStr := MySoftData.MyGui.Title
    if (A_IsAdmin)
        tipStr .= "`n" GetLang("管理员权限")
    
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("显示窗口"), (*) => RefreshGui())
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("休眠"), (*) => OnSuspendHotkey())
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Delete("&Suspend Hotkeys")
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Default := GetLang("显示窗口")
    A_IconTip := tipStr  ; 鼠标悬停时显示此内容
    A_IconHidden := 0   ;0(可见) 和 1(隐藏)
    TraySetIcon("Images\Soft\rabit.ico")
}
