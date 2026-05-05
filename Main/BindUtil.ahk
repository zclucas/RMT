#Requires AutoHotkey v2.0

BindKey() {
    BindSuspendHotkey()
    BindShortcut(MySoftData.PauseHotkey, OnPauseHotKey)
    BindShortcut(MySoftData.KillMacroHotkey, OnKillAllMacro)
    BindShortcut(ToolCheckInfo.ToolCheckHotKey, OnToolCheckHotkey)
    BindShortcut(ToolCheckInfo.ToolTextFilterHotKey, OnToolTextFilterScreenShot)
    BindShortcut(ToolCheckInfo.ScreenShotHotKey, OnToolScreenShot)
    BindShortcut(ToolCheckInfo.FreePasteHotKey, OnToolFreePaste)
    BindShortcut(ToolCheckInfo.ToolRecordMacroHotKey, OnHotToolRecordMacro)
    InitTriggerKeyMap()
    BindSoftHotKey()
    BindMenuHotKey()
    BindTabHotKey()
    OnExit(OnExitSoft)
}

BindShortcut(triggerInfo, action) {
    if (triggerInfo == "")
        return

    isString := SubStr(triggerInfo, 1, 1) == ":"

    if (isString) {
        Hotstring(triggerInfo, action)
    }
    else {
        key := "$*~" triggerInfo
        Hotkey(key, action)
    }
}

BindSuspendHotkey() {
    global MySoftData
    if (MySoftData.SuspendHotkey != "") {
        key := "$*~" MySoftData.SuspendHotkey
        Hotkey(key, OnSuspendHotkey, "S")
    }
}

OnSuspendHotkey(*) {
    global MySoftData ; 访问全局变量
    MySoftData.IsSuspend := !MySoftData.IsSuspend
    MySoftData.SuspendToggleCtrl.Value := MySoftData.IsSuspend
    if (MySoftData.IsSuspend) {
        OnKillAllMacro()
        global MyTimingScheduler
        if (IsObject(MyTimingScheduler))
            MyTimingScheduler.Stop()
        A_TrayMenu.Check(GetLang("休眠"))
        TraySetIcon("Images\Soft\IcoPause.ico")
    }
    else {
        TimingCheck()
        A_TrayMenu.Uncheck(GetLang("休眠"))
        TraySetIcon("Images\Soft\rabit.ico")
    }

    tipStr := MySoftData.IsSuspend ? GetLang("软件休眠") : GetLang("取消软件休眠")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)

    try RmtPostState()
    Suspend(MySoftData.IsSuspend)
}

OnPauseHotKey(*) {
    MySoftData.IsPause := !MySoftData.IsPause
    MySoftData.PauseToggleCtrl.Value := MySoftData.IsPause

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        for index, value in tableItem.ModeArr {
            SetItemPauseState(tableItem.index, index, MySoftData.IsPause)
        }
    }

    tipStr := MySoftData.IsPause ? GetLang("暂停所有宏") : GetLang("取消所有暂停")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)

    MySoftData.SpecialTableItem.PauseArr[1] := MySoftData.IsPause
    try RmtPostState()
}

SetPauseState(state) {
    MySoftData.PauseToggleCtrl.Value := state
    MySoftData.IsPause := state

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        for index, value in tableItem.ModeArr {
            SetItemPauseState(tableItem.index, index, state)
        }
    }

    MySoftData.SpecialTableItem.PauseArr[1] := state
    try RmtPostState()
}

OnKillAllMacro(*) {
    global MySoftData ; 访问全局变量

    CloseMenuWheel()    ;关闭菜单按钮

    MySoftData.MacroRunningCount := 0   ;运行计数重置
    UpdateMacroRunningCount(0, 0)

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        KillSingleTableMacro(tableItem)
        for index, value in tableItem.ModeArr {
            WorkerIndex := tableItem.IsWorkIndexArr[index]
            if (WorkerIndex != 0) {
                workPath := MyWorkPool.GetWorkPath(WorkerIndex)
                MyWorkPool.PostMessage(WM_STOP_MACRO, workPath, tableItem.Index, index)
            }
        }
    }

    KillSingleTableMacro(MySoftData.SpecialTableItem)

    tipStr := GetLang("终止所有宏")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)
    try RmtPostState()
}

OnToolCheckHotkey(*) {
    global ToolCheckInfo
    ToolCheckInfo.IsToolCheck := !ToolCheckInfo.IsToolCheck
    ToolCheckInfo.ToolCheckCtrl.Value := ToolCheckInfo.IsToolCheck

    if (ToolCheckInfo.IsToolCheck) {
        ToolCheckInfo.MouseInfoTimer := Timer(SetToolCheckInfo, 100)
        ToolCheckInfo.MouseInfoTimer.On()
    }
    else
        ToolCheckInfo.MouseInfoTimer := ""
    try RmtPostState()
}

SetToolCheckInfo() {
    global ToolCheckInfo
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY, &winId
    try {
        ToolCheckInfo.PosStr := mouseX . "," . mouseY
        try {
            WinPID := WinGetPID("ahk_id " winId)
            ToolCheckInfo.ProcessName := ProcessGetName(WinPID)
        }
        catch {
            ToolCheckInfo.ProcessName := ""
        }
        ToolCheckInfo.ProcessTile := WinGetTitle(winId)
        ToolCheckInfo.ProcessPid := WinGetPID(winId)
        ToolCheckInfo.ProcessClass := WinGetClass(winId)
        ToolCheckInfo.ProcessId := winId
        ToolCheckInfo.Color := StrReplace(PixelGetColor(mouseX, mouseY, "Slow"), "0x", "")

        WinPosArr := GetCurWinPos()
        ToolCheckInfo.WinPosStr := WinPosArr[1] . "," . WinPosArr[2]
        RefreshToolUI()
    }
}

OnClickToolRecordSettingBtn(*) {
    MyToolRecordSettingGui.ShowGui()
}

OnToolTextFilterScreenShot(*) {
    if (MySoftData.ScreenShotTypeCtrl.Value == 1) {
        SetClipboard("")  ; 清空剪贴板
        Run("ms-screenclip:")
        SetTimer(OnToolTextCheckScreenShot, 500)  ; 每 500 毫秒检查一次剪贴板
    }
    else if (MySoftData.ScreenShotTypeCtrl.Value == 3) {
        RunScreenCapture(OnToolTextCheckScreenShot)
    }
    else {
        TogSelectArea(true, OnToolTextFilterGetArea)
    }
}

OnToolScreenShot(*) {
    if (MySoftData.ScreenShotTypeCtrl.Value == 1) {
        Run("ms-screenclip:")
    }
    else if (MySoftData.ScreenShotTypeCtrl.Value == 3) {
        scPath := A_WorkingDir "\Plugins\ScreenCapture\ScreenCapture.exe"
        if !FileExist(scPath)
            return
        SetClipboard("")
        Run('"' scPath '" --tool:"rect,ellipse,arrow,number,line,text,mosaic,eraser,|,undo,redo,|,pin,clipboard,save,close"'
        )
    }
    else {
        TogSelectArea(true, OnToolScreenShotGetArea)
    }
}

OnToolScreenShotGetArea(x1, y1, x2, y2) {
    width := X2 - X1
    height := Y2 - Y1
    pBitmap := Gdip_BitmapFromScreen(X1 "|" Y1 "|" width "|" height)
    Gdip_SetBitmapToClipboard(pBitmap)
    Gdip_DisposeImage(pBitmap)
}

RunScreenCapture(callback := "") {
    scPath := A_WorkingDir "\Plugins\ScreenCapture\ScreenCapture.exe"
    if !FileExist(scPath)
        return
    SetClipboard("")
    if (callback != "") {
        SetTimer(callback, 500)
    }
    Run('"' scPath '" --tool:"clipboard,close"')
}

OnToolFreePaste(*) {
    MyFreePasteGui.ShowGui()
}

OnHotToolRecordMacro(isHotkey, *) {
    action := OnToolRecordMacro.Bind(isHotkey)
    SetTimer(action, -1)
}

OnToolRecordMacro(isHotkey, *) {
    global ToolCheckInfo, MySoftData
    spacialKeyArr := ["NumpadEnter"]
    if (isHotkey) {
        LastState := ToolCheckInfo.ToolCheckRecordMacroCtrl.Value
        ToolCheckInfo.ToolCheckRecordMacroCtrl.Value := !LastState
    }
    state := ToolCheckInfo.ToolCheckRecordMacroCtrl.Value

    if (MySoftData.MacroEditGui != "") {
        MySoftData.RecordToggleCon.Value := state
    }

    if (state) {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        ToolCheckInfo.RecordMacroStr := ""
        ToolCheckInfo.RecordLastTime := GetCurMSec()
        ToolCheckInfo.RecordLastMousePos := [mouseX, mouseY]
    }

    StateSymbol := state ? "On" : "Off"
    RecordHotKey := ToolCheckInfo.ToolRecordMacroHotKey
    isSingleKey := !CheckIfHasModifyKey(RecordHotKey)
    loop 255 {
        if (isSingleKey && GetKeyVK(RecordHotKey) == A_Index)
            continue

        key := Format("$*~vk{:X}", A_Index)
        if (ToolCheckInfo.RecordSpecialKeyMap.Has(A_Index)) {
            keyName := GetKeyName(Format("vk{:X}", A_Index))
            key := Format("$*~sc{:X}", GetKeySC(keyName))
        }

        try {
            Hotkey(key, OnRecordMacroKeyDown, StateSymbol)
            Hotkey(key " Up", OnRecordMacroKeyUp, StateSymbol)
        }
        catch {
            continue
        }
    }

    loop spacialKeyArr.Length {
        if (isSingleKey && GetKeySC(RecordHotKey) == GetKeySC(spacialKeyArr[A_Index]))
            continue
        key := Format("$*~sc{:X}", GetKeySC(spacialKeyArr[A_Index]))
        Hotkey(key, OnRecordMacroKeyDown, StateSymbol)
        Hotkey(key " Up", OnRecordMacroKeyUp, StateSymbol)
    }

    if (state) {
        MySoftData.IsTogStartRecord := isHotkey == ""
        if (ToolCheckInfo.RecordJoy)
            RecordJoy()

        if (ToolCheckInfo.RecordMouse && ToolCheckInfo.RecordMouseTrail)
            RecordMouseTrail
    }
    else {
        MySoftData.IsTogEndRecord := isHotkey == ""
        OnFinishRecordMacro()
    }
}

RecordMouseTrail() {
    if (!ToolCheckInfo.ToolCheckRecordMacroCtrl.Value)
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY
    if (ToolCheckInfo.RecordLastMousePos[1] != mouseX || ToolCheckInfo.RecordLastMousePos[2] != mouseY) {   ;鼠标位置发生改变
        len := Abs(ToolCheckInfo.RecordLastMousePos[1] - mouseX)
        len += Abs(ToolCheckInfo.RecordLastMousePos[2] - mouseY)
        if (len <= ToolCheckInfo.RecordMouseTrailLen) {
            SetTimer(RecordMouseTrail, -ToolCheckInfo.RecordMouseTrailInterval)
            return
        }

        speed := ToolCheckInfo.RecordMouseTrailSpeed
        IsRelative := ToolCheckInfo.RecordMouseRelative
        symbol := IsRelative ? "_" speed "_1" : "_" speed
        targetX := mouseX
        targetY := mouseY
        if (IsRelative) {   ;相对位移，坐标变化
            targetX := mouseX - ToolCheckInfo.RecordLastMousePos[1]
            targetY := mouseY - ToolCheckInfo.RecordLastMousePos[2]
        }
        ToolCheckInfo.RecordMacroStr .= GetLang("移动") "_" targetX "_" targetY symbol ","
        ToolCheckInfo.RecordLastMousePos := [mouseX, mouseY]

        span := GetCurMSec() - ToolCheckInfo.RecordLastTime
        ToolCheckInfo.RecordLastTime := GetCurMSec()
        ToolCheckInfo.RecordMacroStr .= GetLang("间隔") "_" span ","
    }
    SetTimer(RecordMouseTrail, -ToolCheckInfo.RecordMouseTrailInterval)
}

OnRecordMacroKeyDown(*) {

    key := StrReplace(A_ThisHotkey, "$", "")
    key := StrReplace(key, "*~", "")
    keyName := GetKeyName(key)
    OnRecordAddMacroStr(keyName, true)
}

OnRecordMacroKeyUp(*) {
    key := StrReplace(A_ThisHotkey, "$", "")
    key := StrReplace(key, "*~", "")
    key := StrReplace(key, " Up", "")
    keyName := GetKeyName(key)
    OnRecordAddMacroStr(keyName, false)
}

OnRecordAddMacroStr(keyName, isDown) {
    if (keyName == "WheelUp" || keyName == "WheelDown") {
        ; 处理鼠标滚轮事件（暂时留空，根据需求补充）
    }
    ; 处理按键按下事件
    else if (isDown) {
        ; 如果已按下且不记录长按多次，则直接返回
        if (!ToolCheckInfo.RecordHoldMuti && ToolCheckInfo.RecordHoldKeyMap.Has(keyName))
            return
        ; 记录当前按键为按下状态
        ToolCheckInfo.RecordHoldKeyMap[keyName] := true
    }
    ; 处理按键释放事件（仅在存在记录时删除）
    else if (ToolCheckInfo.RecordHoldKeyMap.Has(keyName)) {
        ToolCheckInfo.RecordHoldKeyMap.Delete(keyName)
    }

    span := GetCurMSec() - ToolCheckInfo.RecordLastTime
    keySymbol := isDown ? GetLang("按下") : GetLang("松开")
    ToolCheckInfo.RecordLastTime := GetCurMSec()
    IsJoy := InStr(keyName, "Joy")
    IsMouse := keyName == "LButton" || keyName == "RButton" || keyName == "MButton"
    IsKeyboard := !IsMouse && !IsJoy

    if (IsJoy || (IsKeyboard && ToolCheckInfo.RecordKeyboard)) {
        keyName := keyName == "," ? GetLang("逗号") : keyName
        ToolCheckInfo.RecordMacroStr .= Format("{}_{},", GetLang("间隔"), span)
        ToolCheckInfo.RecordMacroStr .= Format("{}_{}_{},", GetLang("按键"), keyName, keySymbol)
    }

    if (IsMouse && ToolCheckInfo.RecordMouse && ToolCheckInfo.RecordMouseKeyPoint) {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        if (ToolCheckInfo.RecordLastMousePos[1] != mouseX || ToolCheckInfo.RecordLastMousePos[2] != mouseY) {   ;鼠标位置发生改变
            speed := Max(100 - Integer(span * 0.02), 90)
            speed := ToolCheckInfo.RecordMouseTrail ? 100 : speed
            IsRelative := ToolCheckInfo.RecordMouseRelative
            symbol := IsRelative ? "_" speed "_1" : "_" speed
            targetX := mouseX
            targetY := mouseY
            if (IsRelative) {   ;相对位移，坐标变化
                targetX := mouseX - ToolCheckInfo.RecordLastMousePos[1]
                targetY := mouseY - ToolCheckInfo.RecordLastMousePos[2]
            }
            ToolCheckInfo.RecordMacroStr .= GetLang("移动") "_" targetX "_" targetY symbol ","
            ToolCheckInfo.RecordLastMousePos := [mouseX, mouseY]
        }
        ToolCheckInfo.RecordMacroStr .= GetLang("间隔") "_" span ","
        ToolCheckInfo.RecordMacroStr .= GetLang("按键") "_" keyName "_" keySymbol ","
    }
}

OnFinishRecordMacro() {
    if (ToolCheckInfo.RecordAutoLoosen) {
        for Key, Value in ToolCheckInfo.RecordHoldKeyMap {
            keyName := Key == "," ? GetLang("逗号") : Key
            ToolCheckInfo.RecordMacroStr .= GetLang("按键") "_" keyName "_" GetLang("松开") ","
        }
    }
    macroStr := Trim(ToolCheckInfo.RecordMacroStr, ",")
    macroStr := SimpleRecordMacroStr(macroStr)
    macroStr := DiscardRecordTriggerKey(macroStr, true)
    macroStr := DiscardRecordTriggerKey(macroStr, false)

    if (MySoftData.MacroEditGui != "") {
        MySoftData.MacroEditGui.InitTreeView(macroStr)
        MySoftData.MacroEditGui.InitMacroText(MacroStr)
    }
    macroLineStr := StrReplace(macroStr, ",", "`n")
    ToolCheckInfo.ToolTextCtrl.Value := macroLineStr
    SetClipboard(macroLineStr)
}

OnClickKeyDownDownHelpBtn(*) {
    str1 := GetLang("当宏按键已经处于按下状态，再次触发按下指令时特别处理")
    str2 := GetLang("自动松开：再次按下前，先松开该按键（确保指令正常执行）")
    str3 := GetLang("忽略重复按下：保持按键之前的状态，忽略后续的按下指令")
    str4 := GetLang("允许重复按下：再次按下宏按键（罗技按键可能卡死）")
    str5 := GetLang("Tip1：按下时再次按下，真实键盘无法触发这个行为，这个行为通常是无效的")
    str6 := GetLang("Tip2：按下时再次按下，按键检测网站可能无法检测，但记事本中可以有效输出")

    str := Format("{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5)
    MsgBox(str, GetLang("按下时按下说明"))
}

;绑定热键
OnExitSoft(*) {
    global MyPToken, MyChineseOcr
    Gdip_Shutdown(MyPToken)
    IbSendDestroy()
    MyChineseOcr := ""
    MyEnglishOcr := ""
    MyWorkPool.Clear()

    IniWrite(MySoftData.MacroTotalCount, IniFile, IniSection, "MacroTotalCount")
}

BindMenuHotKey() {
    FoldInfo := MySoftData.TableInfo[3].FoldInfo
    for Index, IndexSpanStr in FoldInfo.IndexSpanArr {
        if (FoldInfo.ForbidStateArr[Index] || FoldInfo.TKArr[index] == "")
            continue

        oriKey := FoldInfo.TKArr[index]
        key := "$*" oriKey
        actionArr := GetBindMacroAction(oriKey)
        isJoyKey := RegExMatch(oriKey, "Joy")
        frontInfo := FoldInfo.FrontInfoArr[index]
        groupSymbolStr := "GroupFold_" index
        realFrontStr := GetParamsWinInfoStr(frontInfo, groupSymbolStr)

        if (realFrontStr != "") {
            HotIfWinActive(realFrontStr)
        }

        if (isJoyKey) {
            MyJoyMacro.AddMacro(oriKey, actionArr[1], frontInfo)
        }
        else {
            if (actionArr[1] != "")
                Hotkey(key, actionArr[1])

            if (actionArr[2] != "")
                Hotkey(key " up", actionArr[2])
        }

        if (realFrontStr != "") {
            HotIfWinActive
        }
    }
}

BindTabHotKey() {
    tableIndex := 0
    MyJoyMacro.MacroMap := Map()
    loop MySoftData.TabNameArr.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        tableIndex := A_Index
        canBind := tableIndex == 1 || tableIndex == 2 || tableIndex == 6
        if (!canBind)
            continue

        for index, value in tableItem.ModeArr {
            if (GetItemFoldForbidState(tableItem, index))
                continue

            if (tableItem.TKArr[index] == "" || tableItem.ForbidArr[index])
                continue

            if (tableItem.MacroArr[index] == "")
                continue

            key := "$*" tableItem.TKArr[index]
            actionArr := GetMacroAction(tableIndex, index)
            isJoyKey := RegExMatch(tableItem.TKArr[index], "Joy")
            isHotstring := SubStr(tableItem.TKArr[index], 1, 1) == ":"
            frontInfo := GetItemFrontInfo(tableItem, index)
            groupSymbolStr := "Group" tableIndex "_" index
            realFrontStr := GetParamsWinInfoStr(frontInfo, groupSymbolStr)

            if (realFrontStr != "") {
                HotIfWinActive(realFrontStr)
            }

            if (isJoyKey) {
                MyJoyMacro.AddMacro(tableItem.TKArr[index], actionArr[1], frontInfo)
            }
            else if (isHotstring) {
                Hotstring(tableItem.TKArr[index], actionArr[1])
            }
            else {
                if (actionArr[1] != "")
                    Hotkey(key, actionArr[1], "On")

                if (actionArr[2] != "")
                    Hotkey(key " up", actionArr[2], "On")
            }

            if (realFrontStr != "") {
                HotIfWinActive
            }
        }
    }
}

InitTriggerKeyMap() {
    MySoftData.TriggerKeyMap := Map()
    tableItem := MySoftData.TableInfo[1]
    for index, value in tableItem.ModeArr {
        if (GetItemFoldForbidState(tableItem, index))
            continue

        if (tableItem.TKArr[index] == "" || tableItem.ForbidArr[index])
            continue

        if (tableItem.MacroArr[index] == "")
            continue

        key := LTrim(tableItem.TKArr[index], "~")
        key := StrLower(key)
        if (!MySoftData.TriggerKeyMap.Has(key)) {
            MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
        }
        info := TriggerKeyInfo()
        info.macroType := 1
        info.tableIndex := tableItem.Index
        info.itemIndex := index
        MySoftData.TriggerKeyMap[key].AddData(info)
    }

    tableItem := MySoftData.TableInfo[3]
    FoldInfo := tableItem.FoldInfo
    for index, IndexSpanStr in FoldInfo.IndexSpanArr {
        if (FoldInfo.ForbidStateArr[index] || FoldInfo.TKArr[index] == "")
            continue
        key := LTrim(FoldInfo.TKArr[index], "~")
        key := StrLower(key)
        if (!MySoftData.TriggerKeyMap.Has(key)) {
            MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
        }
        info := TriggerKeyInfo()
        info.tableIndex := tableItem.Index
        info.macroType := 2
        info.foldIndex := index
        MySoftData.TriggerKeyMap[key].AddData(info)
    }

    for index, value in MySoftData.SoftHotKeyArr {
        key := LTrim(value, "~")
        key := StrLower(key)
        if (!MySoftData.TriggerKeyMap.Has(key)) {
            MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
        }
    }
}

GetMacroAction(tableIndex, index) {
    tableItem := MySoftData.TableInfo[tableIndex]
    macro := tableItem.MacroArr[index]
    tableSymbol := GetTableSymbol(tableIndex)
    actionDown := ""
    actionUp := ""

    if (tableSymbol == "Normal") {
        actionDown := OnTriggerKeyDown.Bind(tableIndex, index)
        actionUp := OnTriggerKeyUp.Bind(tableIndex, index)
    }
    else if (tableSymbol == "String") {
        actionDown := TriggerMacroHandler.Bind(tableIndex, index)
    }
    else if (tableSymbol == "Replace") {
        actionDown := OnReplaceDownKey.Bind(tableItem, macro, index)
        actionUp := OnReplaceUpKey.Bind(tableItem, macro, index)
    }
    return [actionDown, actionUp]
}

OnTriggerKeyDown(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    key := LTrim(tableItem.TKArr[itemIndex], "~")
    key := StrLower(key)

    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyDown()
}

;松开停止
OnTriggerKeyUp(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    key := LTrim(tableItem.TKArr[itemIndex], "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyUp()
}

BindSoftHotKey() {
    for index, value in MySoftData.SoftHotKeyArr {
        mapKey := Trim(value, "~")
        mapKey := StrLower(mapKey)
        isMenuBtnHotKey := CheckIfMenuBtnHotKey(mapKey)
        isOpenMenu := MySoftData.CurMenuWheelIndex != -1
        IsOnlySoftHotkey := MySoftData.TriggerKeyMap[mapKey].IsOnlySoftHotkey()

        key := "$*" value
        actionDown := OnBindKeyDown.Bind(value)
        actionUp := OnBindKeyUp.Bind(value)

        if (isMenuBtnHotKey && !isOpenMenu && IsOnlySoftHotkey) {
            Hotkey(key, actionDown, "Off")
            Hotkey(key " up", actionUp, "Off")
        }

        if (isMenuBtnHotKey && !isOpenMenu)
            continue

        Hotkey(key, actionDown, "On")
        Hotkey(key " up", actionUp, "On")
    }
}

GetBindMacroAction(key) {
    actionDown := OnBindKeyDown.Bind(key)
    actionUp := OnBindKeyUp.Bind(key)
    return [actionDown, actionUp]
}

OnBindKeyDown(key, *) {
    key := LTrim(key, "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyDown()
}

OnBindKeyUp(key, *) {
    key := LTrim(key, "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyUp()
}

OnToggleTriggerMacro(tableIndex, itemIndex) {
    tableItem := MySoftData.TableInfo[tableIndex]
    macro := tableItem.MacroArr[itemIndex]
    hasWorker := MyWorkPool.CheckHasFreeWorker()

    if (hasWorker) {
        SetTableItemState(tableItem.index, itemIndex, 1)
        workerPath := MyWorkPool.Get()
        workerIndex := MyWorkPool.GetWorkIndex(workerPath)
        tableItem.IsWorkIndexArr[itemIndex] := workerIndex
        MyWorkPool.PostMessage(WM_TR_MACRO, workerPath, tableIndex, itemIndex)
        return
    }

    isTrigger := tableItem.ToggleStateArr[itemIndex]
    if (!isTrigger) {
        tableItem.ToggleStateArr[itemIndex] := true
        SetTableItemState(tableItem.index, itemIndex, 1)
        action := OnTriggerMacroKeyAndInit.Bind(tableItem, macro, itemIndex)
        tableItem.ToggleActionArr[itemIndex] := action
        SetTimer(action, -1)
    }
    else {
        action := tableItem.ToggleActionArr[itemIndex]
        if (action == "")
            return

        KillTableItemMacro(tableItem, itemIndex)
        SetTimer(action, 0)
    }
}

TriggerMacroHandler(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    macro := tableItem.MacroArr[itemIndex]
    isWork := tableItem.IsWorkIndexArr[itemIndex]
    hasWork := MyWorkPool.CheckHasFreeWorker()
    if (isWork)
        return

    SetTableItemState(tableItem.index, itemIndex, 1)
    if (hasWork) {
        workPath := MyWorkPool.Get()
        workIndex := MyWorkPool.GetWorkIndex(workPath)
        tableItem.IsWorkIndexArr[itemIndex] := workIndex
        MyWorkPool.PostMessage(WM_TR_MACRO, workPath, tableIndex, itemIndex)
    }
    else {
        OnTriggerMacroKeyAndInit(tableItem, macro, itemIndex)
    }
}
