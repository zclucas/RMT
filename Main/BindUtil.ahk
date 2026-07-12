#Requires AutoHotkey v2.0

BindKey() {
    BindSuspendHotkey()
    BindShortcut(MainSoftData.PauseHotkey, OnPauseHotKey)
    BindShortcut(MainSoftData.KillMacroHotkey, OnKillAllMacro)
    BindShortcut(MainSoftData.ToolCheckHotKey, OnToolCheckHotkey)
    BindShortcut(MainSoftData.ToolTextFilterHotKey, OnToolTextFilterScreenShot)
    BindShortcut(MainSoftData.ScreenShotHotKey, OnToolScreenShot)
    BindShortcut(MainSoftData.FreePasteHotKey, OnToolFreePaste)
    BindShortcut(MainSoftData.ToolRecordMacroHotKey, OnHotToolRecordMacro)
    InitTriggerKeyMap()
    BindMenuHotKey()
    BindUIPanelHotKey()
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
        isCombo := IsComboKey(triggerInfo)
        mapKey := StrLower(Trim(triggerInfo, "~"))
        if (isCombo) {
            key := triggerInfo
        }
        else {
            key := "$*~" triggerInfo
        }
        try {
            Hotkey(key, action)
        }
        catch as e {
        }
    }
}

BindSuspendHotkey() {
    global MySoftData
    if (MainSoftData.SuspendHotkey != "") {
        isCombo := IsComboKey(MainSoftData.SuspendHotkey)
        if (isCombo) {
            key := MainSoftData.SuspendHotkey
        }
        else {
            key := "$*~" MainSoftData.SuspendHotkey
        }
        try {
            Hotkey(key, OnSuspendHotkey, "S")
        }
        catch as e {
        }
    }
}

OnSuspendHotkey(*) {
    global MySoftData
    MainSoftData.IsSuspend := !MainSoftData.IsSuspend
    UIControls.SuspendToggle.Value := MainSoftData.IsSuspend
    if (MainSoftData.IsSuspend) {
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

    tipStr := MainSoftData.IsSuspend ? GetLang("软件休眠") : GetLang("取消软件休眠")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)

    Suspend(MainSoftData.IsSuspend)
}

OnPauseHotKey(*) {
    MainSoftData.IsPause := !MainSoftData.IsPause
    UIControls.PauseToggle.Value := MainSoftData.IsPause

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        for index, value in tableItem.ModeArr {
            SetItemPauseState(tableItem.index, index, MainSoftData.IsPause)
        }
    }

    tipStr := MainSoftData.IsPause ? GetLang("暂停所有宏") : GetLang("取消所有暂停")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)

    MySoftData.SpecialTableItem.PauseArr[1] := MainSoftData.IsPause
}

SetPauseState(state) {
    UIControls.PauseToggle.Value := state
    MainSoftData.IsPause := state

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        for index, value in tableItem.ModeArr {
            SetItemPauseState(tableItem.index, index, state)
        }
    }

    MySoftData.SpecialTableItem.PauseArr[1] := state
}

OnKillAllMacro(*) {
    global MySoftData, MyWorkPool

    CloseMenuWheel()

    MySoftData.MacroRunningCount := 0
    UpdateMacroRunningCount(0, 0)

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        loop tableItem.ColorStateArr.Length {
            if (tableItem.ColorStateArr[A_Index] == 1 || tableItem.ColorStateArr[A_Index] == 2) {
                MyStopMacro(tableItem.Index, A_Index)
            }
        }
    }

    KillSingleTableMacro(MySoftData.SpecialTableItem)

    tipStr := GetLang("终止所有宏")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)
}

OnToolCheckHotkey(*) {
    global MainSoftData
    MainSoftData.IsToolCheck := !MainSoftData.IsToolCheck
    UIControls.ToolCheck.Value := MainSoftData.IsToolCheck

    if (MainSoftData.IsToolCheck) {
        SetTimer SetToolCheckInfo, 100
    }
    else
        SetTimer SetToolCheckInfo, 0
}

SetToolCheckInfo() {
    global MainSoftData
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY, &winId
    try {
        MainSoftData.PosStr := mouseX . "," . mouseY
        try {
            WinPID := WinGetPID("ahk_id " winId)
            MainSoftData.ProcessName := ProcessGetName(WinPID)
        }
        catch {
            MainSoftData.ProcessName := ""
        }
        MainSoftData.ProcessTile := WinGetTitle(winId)
        MainSoftData.ProcessPid := WinGetPID(winId)
        MainSoftData.ProcessClass := WinGetClass(winId)
        MainSoftData.ProcessId := winId
        MainSoftData.Color := StrReplace(PixelGetColor(mouseX, mouseY, "Slow"), "0x", "")

        WinPosArr := GetCurWinPos()
        MainSoftData.WinPosStr := WinPosArr[1] . "," . WinPosArr[2]
        RefreshToolUI()
    }
}

OnClickToolRecordSettingBtn(*) {
    MyToolRecordSettingGui.ShowGui()
}

OnToolTextFilterScreenShot(*) {
    if (MainSoftData.ScreenShotType == 1) {
        SetClipboard("")
        Run("ms-screenclip:")
        SetTimer(OnToolTextCheckScreenShot, 500)
    }
    else if (MainSoftData.ScreenShotType == 3) {
        RunScreenCapture(OnToolTextCheckScreenShot)
    }
    else {
        TogSelectArea(true, OnToolTextFilterGetArea)
    }
}

OnToolScreenShot(*) {
    if (MainSoftData.ScreenShotType == 1) {
        Run("ms-screenclip:")
    }
    else if (MainSoftData.ScreenShotType == 3) {
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

OnClickMutiThreadHelpBtn(*) {
    str1 := GetLang("设置若梦兔最大线程数量")
    str2 := GetLang("-1：动态多线程，线程闲置时回收（30秒），不足时创建新的线程")
    str3 := GetLang("0：单线程")
    str4 := GetLang("n：固定线程为指定n（推荐3~5）")
    str5 := GetLang("提示：动态多线程采用固定线程3+动态多线程池最大16")

    str := Format("{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5)
    MsgBox(str, GetLang("多线程说明"))
}

OnClickKeyDownDownHelpBtn(*) {
    str1 := GetLang("当宏按键已经处于按下状态，再次触发按下指令时特别处理")
    str2 := GetLang("自动松开：再次按下前，先松开该按键（确保指令正常执行）")
    str3 := GetLang("忽略重复按下：保持按键之前的状态，忽略后续的按下指令")
    str4 := GetLang("允许重复按下：再次按下宏按键（罗技按键可能卡死）")
    str5 := GetLang("Tip1：按下时再次按下，真实键盘无法触发这个行为，这个行为通常是无效的")
    str6 := GetLang("Tip2：按下时再次按下，按键检测网站可能无法检测，但记事本中可以有效输出")

    str := Format("{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6)
    MsgBox(str, GetLang("按下时按下说明"))
}

OnExitSoft(*) {
    global MyPToken, MyChineseOcr, MyUIMacroGui, MyWorkPool
    Gdip_Shutdown(MyPToken)
    IbSendDestroy()
    MyChineseOcr := ""
    MyEnglishOcr := ""
    CleanupAllMacroStates()

    if (MyWorkPool != "") {
        MyWorkPool.Clear()
        MyWorkPool := ""
    }
    if (IsSet(MyUIMacroGui) && MyUIMacroGui != "")
        MyUIMacroGui.StopMonitor()

    IniWrite(MySoftData.MacroTotalCount, IniFile, IniSection, "MacroTotalCount")
}

BindMenuHotKey() {
    FoldInfo := MySoftData.TableInfo[3].FoldInfo
    for Index, IndexSpanStr in FoldInfo.IndexSpanArr {
        if (FoldInfo.ForbidStateArr[Index] || FoldInfo.TKArr[index] == "")
            continue

        oriKey := FoldInfo.TKArr[index]
        isCombo := IsComboKey(oriKey)
        if (isCombo) {
            key := oriKey
        }
        else {
            key := "$*" oriKey
        }
        actionArr := GetBindMacroAction(oriKey)
        isJoyKey := RegExMatch(oriKey, "Joy")
        frontInfo := FoldInfo.FrontInfoArr[index]
        realFrontStr := GetParamsWinInfoStr(frontInfo)

        if (realFrontStr != "") {
            HotIfWinActive(realFrontStr)
        }

        if (isJoyKey) {
            MyJoyMacro.AddMacro(oriKey, actionArr[1], frontInfo, actionArr[2])
        }
        else {
            try {
                if (actionArr[1] != "")
                    Hotkey(key, actionArr[1])

                if (actionArr[2] != "" && !isCombo)
                    Hotkey(key " up", actionArr[2])

                ; 顺序触发（默认无序）：注册反向组合键；勾选顺序时不注册
                if (isCombo && !FoldInfo.UnorderedTriggerArr[index]) {
                    reversedKey := GetReversedComboKey(oriKey)
                    if (reversedKey != "") {
                        try {
                            Hotkey(reversedKey, actionArr[1])
                            if (actionArr[2] != "" && !isCombo)
                                Hotkey(reversedKey " up", actionArr[2])
                        }
                        catch as e {
                        }
                    }
                }
            }
            catch as e {
            }
        }

        if (realFrontStr != "") {
            HotIfWinActive
        }
    }
}

; 界面宏模块级触发键：切换悬浮面板显示/隐藏
BindUIPanelHotKey() {
    tableItem := MySoftData.TableInfo[4]
    if (!tableItem || !tableItem.FoldInfo)
        return

    FoldInfo := tableItem.FoldInfo
    for Index, IndexSpanStr in FoldInfo.IndexSpanArr {
        if (FoldInfo.ForbidStateArr[Index] || FoldInfo.TKArr[Index] == "")
            continue

        oriKey := FoldInfo.TKArr[Index]

        key := "$*" oriKey
        foldIndex := Index

        ; 界面宏触发类型固定为"开关"：按下时切换面板
        try Hotkey(key, (*) => MyUIMacroGui.TogglePanel(foldIndex))
    }
}

BindTabHotKey() {
    tableIndex := 0
    MyJoyMacro.MacroMap := Map()
    MyJoyMacro.ComboMacroMap := Map()
    registerMsg := "=== Registered Hotkeys ===`n"

    ; 预计算缓存Map（避免重复的字符串处理和正则匹配）
    keyCache := Map()

    loop MainSoftData.TabNameArr.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        tableIndex := A_Index
        canBind := tableIndex == 1 || tableIndex == 2 || tableIndex == 7
        if (!canBind)
            continue

        for index, value in tableItem.ModeArr {
            ; 优化：一次调用获取所有Fold信息（避免重复遍历IndexSpanArr）
            foldData := GetItemFoldData(tableItem, index)
            if (foldData.forbidState)
                continue

            if (tableItem.TKArr[index] == "" || tableItem.ForbidArr[index])
                continue

            if (tableItem.MacroArr[index] == "")
                continue

            rawKey := tableItem.TKArr[index]

            ; 使用缓存避免重复计算
            cacheKey := rawKey "|" tableIndex "|" index
            if (!keyCache.Has(cacheKey)) {
                cacheData := {
                    isCombo: IsComboKey(rawKey),
                    isJoy: !!RegExMatch(rawKey, "Joy"),
                    isHotstring: SubStr(rawKey, 1, 1) == ":",
                    firstChar: SubStr(rawKey, 1, 1),
                    keyPrefix: (SubStr(rawKey, 1, 1) == "~" || !IsComboKey(rawKey)) ? "$*" : "",
                    frontInfo: foldData.frontInfo,
                    realFrontStr: ""
                }

                if (cacheData.frontInfo != "")
                    cacheData.realFrontStr := GetParamsWinInfoStr(cacheData.frontInfo)

                keyCache.Set(cacheKey, cacheData)
            }
            cache := keyCache[cacheKey]

            key := cache.isCombo ? rawKey : cache.keyPrefix rawKey
            actionArr := GetMacroAction(tableIndex, index)

            registerMsg .= "rawKey: '" rawKey "' → key: '" key "' (isCombo=" cache.isCombo ")`n"

            if (cache.realFrontStr != "") {
                HotIfWinActive(cache.realFrontStr)
            }

            if (cache.isJoy) {
                MyJoyMacro.AddMacro(rawKey, actionArr[1], cache.frontInfo, actionArr[2])
            }
            else if (cache.isHotstring) {
                Hotstring(rawKey, actionArr[1])
            }
            else {
                try {
                    if (actionArr[1] != "") {
                        Hotkey(key, actionArr[1], "On")
                    }

                    if (actionArr[2] != "" && !cache.isCombo)
                        Hotkey(key " up", actionArr[2], "On")

                    ; 顺序触发（默认无序）：注册反向组合键；勾选顺序时不注册
                    if (cache.isCombo && !tableItem.UnorderedTriggerArr[index]) {
                        reversedKey := GetReversedComboKey(rawKey)
                        if (reversedKey != "") {
                            try {
                                Hotkey(reversedKey, actionArr[1], "On")
                                if (actionArr[2] != "" && !cache.isCombo)
                                    Hotkey(reversedKey " up", actionArr[2], "On")
                                registerMsg .= "  ↩ Reversed: '" reversedKey "'`n"
                            }
                            catch as e {
                                registerMsg .= "  ❌ Unordered Failed: " e.Message "`n"
                            }
                        }
                    }
                }
                catch as e {
                    registerMsg .= "❌ Failed: " e.Message "`n"
                }
            }

            if (cache.realFrontStr != "") {
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

        ; 顺序触发（默认无序）：将反向组合键也加入映射；勾选顺序时不加
        if (!tableItem.UnorderedTriggerArr[index]) {
            reversedRaw := GetReversedComboKey(tableItem.TKArr[index])
            if (reversedRaw != "") {
                reversedKey := LTrim(reversedRaw, "~")
                reversedKey := StrLower(reversedKey)
                if (!MySoftData.TriggerKeyMap.Has(reversedKey)) {
                    MySoftData.TriggerKeyMap[reversedKey] := MySoftData.TriggerKeyMap[key]
                }
            }
        }
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

        ; 顺序触发（默认无序）：将反向组合键也加入映射；勾选顺序时不加
        if (!FoldInfo.UnorderedTriggerArr[index]) {
            reversedRaw := GetReversedComboKey(FoldInfo.TKArr[index])
            if (reversedRaw != "") {
                reversedKey := LTrim(reversedRaw, "~")
                reversedKey := StrLower(reversedKey)
                if (!MySoftData.TriggerKeyMap.Has(reversedKey)) {
                    MySoftData.TriggerKeyMap[reversedKey] := MySoftData.TriggerKeyMap[key]
                }
            }
        }
    }

    ; 界面宏(TableIndex==4)的Fold触发键（悬浮面板切换）
    tableItem := MySoftData.TableInfo[4]
    if (tableItem && tableItem.FoldInfo) {
        uiFoldInfo := tableItem.FoldInfo
        for index, IndexSpanStr in uiFoldInfo.IndexSpanArr {
            if (uiFoldInfo.ForbidStateArr[index] || uiFoldInfo.TKArr[index] == "")
                continue
            key := LTrim(uiFoldInfo.TKArr[index], "~")
            key := StrLower(key)
            if (!MySoftData.TriggerKeyMap.Has(key)) {
                MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
            }
            info := TriggerKeyInfo()
            info.tableIndex := tableItem.Index
            info.macroType := 3  ; 界面宏面板类型
            info.foldIndex := index
            MySoftData.TriggerKeyMap[key].AddData(info)
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
    rawTK := tableItem.TKArr[itemIndex]
    key := LTrim(rawTK, "~")
    key := StrLower(key)

    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyDown()
}

OnTriggerKeyUp(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    key := LTrim(tableItem.TKArr[itemIndex], "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyUp()
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

    if (MainSoftData.SelectAreaAction != "")
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

    if (WorkPoolEnabled()) {
        SetTableItemState(tableItem.Index, itemIndex, 1)
        MyWorkPool.PrepareItemRun(tableIndex, itemIndex)
        GraphPoolLog("宏触发", Format("tab={1} item={2} 来源=开关", tableIndex, itemIndex))
        cmd := JSON.stringify(["TR_MACRO", tableIndex, itemIndex])
        MyWorkPool.Submit(cmd, tableIndex, itemIndex)
        tableItem.IsWorkIndexArr[itemIndex] := true
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
        SetTableItemState(tableItem.index, itemIndex, 3)
        SetTimer(action, 0)
    }
}

TriggerMacroHandler(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    macro := tableItem.MacroArr[itemIndex]
    isWork := tableItem.IsWorkIndexArr[itemIndex]
    if (isWork && MyWorkPool != "" && IsObject(MyWorkPool) && MyWorkPool.HasItemWork(tableIndex, itemIndex))
        return

    SetTableItemState(tableItem.Index, itemIndex, 1)
    if (WorkPoolEnabled()) {
        if (isWork)
            GraphPoolLog("宏触发恢复", Format("tab={1} item={2} 清理上次残留", tableIndex, itemIndex))
        MyWorkPool.PrepareItemRun(tableIndex, itemIndex)
        GraphPoolLog("宏触发", Format("tab={1} item={2}", tableIndex, itemIndex))
        cmd := JSON.stringify(["TR_MACRO", tableIndex, itemIndex])
        MyWorkPool.Submit(cmd, tableIndex, itemIndex)
        tableItem.IsWorkIndexArr[itemIndex] := true
        return
    }
    OnTriggerMacroKeyAndInit(tableItem, macro, itemIndex)
}

GetReversedComboKey(comboKey) {
    if (!InStr(comboKey, " & "))
        return ""

    parts := StrSplit(comboKey, " & ")
    if (parts.Length != 2)
        return ""

    part1 := Trim(parts[1])
    part2 := Trim(parts[2])

    hasTilde1 := SubStr(part1, 1, 1) == "~"
    hasTilde2 := SubStr(part2, 1, 1) == "~"

    key1 := hasTilde1 ? SubStr(part1, 2) : part1
    key2 := hasTilde2 ? SubStr(part2, 2) : part2

    prefix1 := hasTilde2 ? "~" : ""
    prefix2 := hasTilde1 ? "~" : ""

    return prefix1 key2 " & " prefix2 key1
}
