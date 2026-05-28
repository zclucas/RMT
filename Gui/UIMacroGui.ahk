#Requires AutoHotkey v2.0

class UIMacroGui {
    static STATE_DEFAULT := 0    ; 默认/空闲（隐藏色块）
    static STATE_RUNNING := 1    ; 运行中（绿色 GreenColor.png）
    static STATE_PAUSED := 2     ; 暂停中（黄色 YellowColor.png）
    static STATE_STOPPED := 3    ; 停止/终止（红色 RedColor.png，5秒后自动恢复）

    __new() {
        this.GuiMap := Map()
        this.CreateQueue := []
        this.IsCreating := false
        this.MonitorTimer := ""
        this.RunningMap := Map()
        this.RecoverTimers := Map()
        this.StartMonitor()
    }

    StartMonitor() {
        if (this.MonitorTimer != "")
            return
        this.MonitorTimer := Timer(this.CheckAllButtons.Bind(this), 800)
        this.MonitorTimer.On()

        SetTimer(this.ProcessCreateQueue.Bind(this), 100)
    }

    StopMonitor() {
        if (this.MonitorTimer != "") {
            this.MonitorTimer.Off()
            this.MonitorTimer := ""
        }
        SetTimer(this.ProcessCreateQueue.Bind(this), 0)
        this.HideAllButtons()
        this.CreateQueue := []
        this.IsCreating := false
    }

    ProcessCreateQueue() {
        if (this.IsCreating || this.CreateQueue.Length == 0)
            return

        task := this.CreateQueue[1]
        this.CreateQueue.RemoveAt(1)

        this.IsCreating := true

        try {
            this.DoCreateButton(task.guiKey, task.macroIndex, task.targetHwnd,
                task.posX, task.posY)
        }
        catch as e {
        }

        this.IsCreating := false
    }

    QueueCreateButton(guiKey, macroIndex, targetHwnd, posX, posY) {
        for index, task in this.CreateQueue {
            if (task.guiKey == guiKey) {
                return
            }
        }

        if (this.GuiMap.Has(guiKey)) {
            btnInfo := this.GuiMap[guiKey]

            if (btnInfo.Hwnd) {
                try {
                    targetExists := WinExist("ahk_id " btnInfo.Hwnd)

                    if (!targetExists) {
                        this.RemoveButton(guiKey)
                    }
                    else {
                        isValid := false
                        guiHwnd := 0
                        if (btnInfo.Gui && btnInfo.Gui.Hwnd) {
                            try {
                                guiHwnd := btnInfo.Gui.Hwnd
                                guiExists := WinExist(guiHwnd)
                                if (guiExists)
                                    isValid := true
                            }
                        }

                        if (isValid) {
                            return
                        }
                        else {
                            this.RemoveButton(guiKey)
                        }
                    }
                }
                catch as e {
                    return
                }
            }
            else {
                isValid := false
                if (btnInfo.Gui && btnInfo.Gui.Hwnd) {
                    try {
                        guiHwnd := btnInfo.Gui.Hwnd
                        if (WinExist(guiHwnd))
                            isValid := true
                    }
                }

                if (isValid) {
                    return
                }
                else {
                    this.RemoveButton(guiKey)
                }
            }
        }

        this.CreateQueue.Push({
            guiKey: guiKey,
            macroIndex: macroIndex,
            targetHwnd: targetHwnd,
            posX: posX,
            posY: posY
        })
    }

    DoCreateButton(guiKey, macroIndex, targetHwnd, posX, posY) {
        if (targetHwnd) {
            if (!WinExist("ahk_id " targetHwnd)) {
                throw Error("目标窗口已关闭或无效: hwnd=" targetHwnd)
            }
        }

        tableItem := MySoftData.TableInfo[4]
        btnText := tableItem.RemarkArr[macroIndex]
        if (btnText == "")
            btnText := GetLang("按钮") macroIndex

        btnW := (tableItem.UIBtnWidthArr.Has(macroIndex) && tableItem.UIBtnWidthArr[macroIndex] != "")
            ? Integer(tableItem.UIBtnWidthArr[macroIndex]) : 100
        btnH := (tableItem.UIBtnHeightArr.Has(macroIndex) && tableItem.UIBtnHeightArr[macroIndex] != "")
            ? Integer(tableItem.UIBtnHeightArr[macroIndex]) : 30
        colorW := 22
        btnTextW := btnW - colorW

        if (targetHwnd) {
            try {
                uiGui := Gui("+Owner" targetHwnd " +AlwaysOnTop +ToolWindow -Caption")
                uiGui.Opt("+Parent" targetHwnd)
            }
            catch as e {
                uiGui := Gui("+AlwaysOnTop +ToolWindow -Caption +DPIScale")
            }
        } else {
            uiGui := Gui("+AlwaysOnTop +ToolWindow -Caption +DPIScale")
        }

        uiGui.SetFont("S10 W550", MySoftData.FontType)
        uiGui.BackColor := "4a90d9"
        WinSetTransColor("4a90d9", uiGui)

        colorCon := uiGui.Add("Pic", "x0 y0 w" colorW " h" btnH " Hidden")

        con := uiGui.Add("Button", "x" colorW " y0 w" btnTextW " h" btnH, btnText)
        con.OnEvent("Click", (*) => this.OnButtonClick(macroIndex))

        showX := posX - btnW // 2
        showY := posY - btnH // 2
        if (!targetHwnd) {
        }
        else {
            try {
                isChild := false
                if (uiGui.Hwnd) {
                    parentHwnd := DllCall("GetParent", "Ptr", uiGui.Hwnd, "Ptr")
                    isChild := (parentHwnd != 0)
                }
                if (!isChild) {
                    WinGetPos(&winX, &winY, , , "ahk_id " targetHwnd)
                    showX += winX
                    showY += winY
                }
            }
        }

        uiGui.Show(Format("x{} y{} NA", showX, showY))
        uiGui.Move(, , btnW, btnH)

        this.GuiMap.Set(guiKey, {
            Gui: uiGui,
            BtnCon: con,
            ColorCon: colorCon,
            Hwnd: targetHwnd,
            MacroIndex: macroIndex
        })

        if (tableItem.ColorStateArr.Has(macroIndex) && tableItem.ColorStateArr[macroIndex] != 0)
            this.UpdateButtonsState(macroIndex, tableItem.ColorStateArr[macroIndex])
    }

    CheckAllButtons() {
        tableItem := MySoftData.TableInfo[4]
        if (!tableItem || !tableItem.FoldInfo)
            return

        foldInfo := tableItem.FoldInfo
        for foldIndex, remark in foldInfo.RemarkArr {
            if (foldInfo.ForbidStateArr[foldIndex])
                continue

            indexSpanStr := foldInfo.IndexSpanArr[foldIndex]
            indexSpan := StrSplit(indexSpanStr, "-")
            if (!IsInteger(indexSpan[1]) || !IsInteger(indexSpan[2]))
                continue

            startIndex := Integer(indexSpan[1])
            endIndex := Integer(indexSpan[2])
            if (startIndex < 1 || endIndex < startIndex)
                continue

            Loop (endIndex - startIndex + 1) {
                macroIndex := startIndex + A_Index - 1
                if (macroIndex > tableItem.RemarkArr.Length)
                    continue
                if (tableItem.ForbidArr.Has(macroIndex) && tableItem.ForbidArr[macroIndex])
                    continue

                frontInfo := ""
                if (tableItem.UIWindowArr.Has(macroIndex))
                    frontInfo := tableItem.UIWindowArr[macroIndex]

                posX := 10
                posY := 10
                if (tableItem.HoldTimeArr.Has(macroIndex) && tableItem.HoldTimeArr[macroIndex] != "")
                    posX := Integer(tableItem.HoldTimeArr[macroIndex])
                if (tableItem.UIPosYArr.Has(macroIndex) && tableItem.UIPosYArr[macroIndex] != "")
                    posY := Integer(tableItem.UIPosYArr[macroIndex])

                if (frontInfo != "") {
                    paramStr := GetParamsWinInfoStr(frontInfo)
                    hwndList := []
                    if (paramStr != "") {
                        hwndList := WinGetList(paramStr)
                    }

                    existingKeys := []
                    for key in this.GuiMap {
                        if (InStr(key, "UI_Btn_" macroIndex "_"))
                            existingKeys.Push(key)
                    }

                    for task in this.CreateQueue {
                        if (InStr(task.guiKey, "UI_Btn_" macroIndex "_"))
                            existingKeys.Push(task.guiKey)
                    }

                    if (hwndList.Length > 0) {
                        for idx, targetHwnd in hwndList {
                            if (!targetHwnd)
                                continue

                            guiKey := "UI_Btn_" macroIndex "_" targetHwnd

                            this.QueueCreateButton(guiKey, macroIndex, targetHwnd, posX, posY)
                        }

                        for key in existingKeys {
                            stillValid := false
                            for idx, targetHwnd in hwndList {
                                checkKey := "UI_Btn_" macroIndex "_" targetHwnd
                                if (key == checkKey) {
                                    stillValid := true
                                    break
                                }
                            }

                            if (!stillValid && this.GuiMap.Has(key)) {
                                btnInfo := this.GuiMap[key]
                                shouldRemove := true

                                if (btnInfo.Hwnd) {
                                    try {
                                        targetExists := WinExist("ahk_id " btnInfo.Hwnd)
                                        if (targetExists)
                                            shouldRemove := false
                                    }
                                    catch as e {
                                    }
                                }

                                if (shouldRemove) {
                                    if (this.IsMacroRunning(btnInfo.MacroIndex))
                                        this.StopMacro(btnInfo.MacroIndex)
                                    this.RemoveButton(key)
                                }
                            }
                        }
                    } else {
                        for key in existingKeys {
                            if (this.GuiMap.Has(key)) {
                                btnInfo := this.GuiMap[key]
                                if (this.IsMacroRunning(btnInfo.MacroIndex))
                                    this.StopMacro(btnInfo.MacroIndex)
                                this.RemoveButton(key)
                            }
                        }
                    }
                } else {
                    guiKey := "UI_Btn_" macroIndex "_Screen"

                    this.QueueCreateButton(guiKey, macroIndex, "", posX, posY)
                }
            }
        }
    }

    OnButtonClick(macroIndex) {
        try {
            tableItem := MySoftData.TableInfo[4]
            if (tableItem.ForbidArr.Has(macroIndex) && tableItem.ForbidArr[macroIndex])
                return

            if (!tableItem.MacroArr.Has(macroIndex) || tableItem.MacroArr[macroIndex] == "")
                return

            if (this.IsMacroRunning(macroIndex)) {
                this.StopMacro(macroIndex)
            } else {
                this.StartMacro(macroIndex)
            }
        }
        catch as e {
        }
    }

    IsMacroRunning(macroIndex) {
        return (this.RunningMap.Has(macroIndex)
            && this.RunningMap[macroIndex].IsRunning)
    }

    StartMacro(macroIndex) {
        if (this.IsMacroRunning(macroIndex))
            return

        tableItem := MySoftData.TableInfo[4]
        macroStr := tableItem.MacroArr[macroIndex]

        this.CancelRecoverTimer(macroIndex)

        actionObj := this
        action := (*) => (
            OnTriggerMacroKeyAndInit(tableItem, macroStr, macroIndex),
            SetTimer(() => actionObj.OnMacroComplete(macroIndex), -10)
        )

        this.RunningMap[macroIndex] := {IsRunning: true, TimerAction: action}
        SetTimer(action, -1)
        MySetTableItemState(4, macroIndex, UIMacroGui.STATE_RUNNING)
    }

    StopMacro(macroIndex) {
        tableItem := MySoftData.TableInfo[4]

        this.CancelRecoverTimer(macroIndex)

        tableItem.KilledArr[macroIndex] := true
        tableItem.PauseArr[macroIndex] := false

        if (this.RunningMap.Has(macroIndex))
            this.RunningMap.Delete(macroIndex)

        MySetTableItemState(4, macroIndex, UIMacroGui.STATE_STOPPED)
    }

    OnMacroComplete(macroIndex) {
        if (this.IsMacroRunning(macroIndex)) {
            this.RunningMap.Delete(macroIndex)
            this.CancelRecoverTimer(macroIndex)
            MySetTableItemState(4, macroIndex, UIMacroGui.STATE_DEFAULT)
        }
    }

    UpdateButtonsState(macroIndex, state) {
        for guiKey, btnInfo in this.GuiMap {
            if (btnInfo.MacroIndex != macroIndex)
                continue

            if (!btnInfo.ColorCon || !btnInfo.Gui)
                continue

            try {
                colorValue := GetItemColorValue(state)
                isVisible := (state != UIMacroGui.STATE_DEFAULT)

                btnInfo.ColorCon.Value := colorValue
                btnInfo.ColorCon.Visible := isVisible

                if (state == UIMacroGui.STATE_PAUSED) {
                    btnInfo.BtnCon.Enabled := false
                } else {
                    btnInfo.BtnCon.Enabled := true
                }

                if (state == UIMacroGui.STATE_STOPPED) {
                    this.CancelRecoverTimer(macroIndex)
                    recoverAction := this.UpdateButtonsState.Bind(this, macroIndex, UIMacroGui.STATE_DEFAULT)
                    timer := SetTimer(recoverAction, -5000)
                    this.RecoverTimers[macroIndex] := timer
                }
            }
            catch as e {
            }
        }
    }

    CancelRecoverTimer(macroIndex) {
        if (this.RecoverTimers.Has(macroIndex)) {
            oldTimer := this.RecoverTimers[macroIndex]
            if (oldTimer)
                SetTimer(oldTimer, 0)
            this.RecoverTimers.Delete(macroIndex)
        }
    }

    RemoveButton(guiKey) {
        try {
            if (this.GuiMap.Has(guiKey)) {
                btnInfo := this.GuiMap[guiKey]
                if (btnInfo.Gui) {
                    try {
                        btnInfo.Gui.Hide()
                        btnInfo.Gui.Destroy()
                    }
                }
                this.GuiMap.Delete(guiKey)
            }
        }
        catch as e {
        }
    }

    HideAllButtons() {
        for macroIndex in this.RunningMap {
            this.StopMacro(macroIndex)
        }
        for macroIndex in this.RecoverTimers {
            this.CancelRecoverTimer(macroIndex)
        }
        for key, guiInfo in this.GuiMap {
            try {
                guiInfo.Gui.Hide()
                guiInfo.Gui.Destroy()
            }
        }
        this.GuiMap.Clear()
        this.CreateQueue := []
        this.IsCreating := false
    }

    RefreshButtons() {
        this.HideAllButtons()
    }

    __Delete() {
        this.StopMonitor()
    }
}
