#Requires AutoHotkey v2.0

class UIMacroGui {
    __new() {
        this.GuiMap := Map()
        this.BtnInfoMap := Map()
        this.IsActive := false
        this.MonitorTimer := ""
        this.StartMonitor()
    }

    StartMonitor() {
        if (this.MonitorTimer != "")
            return
        this.MonitorTimer := Timer(this.CheckAndShowButtons.Bind(this), 1000)
        this.MonitorTimer.On()
    }

    StopMonitor() {
        if (this.MonitorTimer != "") {
            this.MonitorTimer.Off()
            this.MonitorTimer := ""
        }
        this.HideAllButtons()
    }

    CheckAndShowButtons() {
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

                this.ShowUIMacroButton(macroIndex, frontInfo, posX, posY)
            }
        }
    }

    ShowUIMacroButton(macroIndex, frontInfo, posX, posY) {
        try {
            guiKey := "UI_Btn_" macroIndex
            targetHwnd := ""

            if (frontInfo != "") {
                hwndList := GetHwndList(frontInfo)
                if (hwndList.Length == 0 || !hwndList[1] || !WinExist(hwndList[1]))
                    return
                targetHwnd := hwndList[1]
            } else {
                guiKey := "UI_Btn_" macroIndex "_Screen"
            }

            if (this.GuiMap.Has(guiKey) && this.GuiMap[guiKey].Gui.Visible)
                return

            tableItem := MySoftData.TableInfo[4]
            btnText := tableItem.RemarkArr[macroIndex]
            if (btnText == "")
                btnText := GetLang("按钮") macroIndex

            if (targetHwnd) {
                uiGui := Gui("+Owner" targetHwnd " +AlwaysOnTop +ToolWindow -Caption")
            } else {
                uiGui := Gui("+AlwaysOnTop +ToolWindow -Caption +DPIScale")
            }

            uiGui.SetFont("S10 W550", MySoftData.FontType)
            uiGui.BackColor := "4a90d9"
            WinSetTransColor("4a90d9", uiGui)

            con := uiGui.Add("Button", "x0 y0 w100 h30", btnText)
            con.OnEvent("Click", (*) => this.OnButtonClick(macroIndex))

            uiGui.OnEvent("Close", (*) => this.OnGuiClose(guiKey))

            guiX := posX
            guiY := posY

            uiGui.Show(Format("x{} y{} NA", guiX, guiY))
            uiGui.Move(, , 100, 30)

            this.GuiMap.Set(guiKey, { Gui: uiGui, Hwnd: targetHwnd })
        }
        catch as e {
        }
    }

    OnButtonClick(macroIndex) {
        try {
            tableItem := MySoftData.TableInfo[4]
            if (tableItem.ForbidArr.Has(macroIndex) && tableItem.ForbidArr[macroIndex])
                return

            if (!tableItem.MacroArr.Has(macroIndex) || tableItem.MacroArr[macroIndex] == "")
                return

            macroStr := tableItem.MacroArr[macroIndex]
            tableItem.KilledArr[macroIndex] := false
            tableItem.PauseArr[macroIndex] := false
            tableItem.ActionCount[macroIndex] := 0
            tableItem.VariableMapArr[macroIndex]["宏循环次数"] := 1
            tableItem.VariableMapArr[macroIndex]["循环次数"] := 0
            HandTipSound(tableItem, macroIndex, 1, true, true)
            OnTriggerMacroOnce(tableItem, macroStr, macroIndex)
            HandTipSound(tableItem, macroIndex, 2, true, true)
            OnFinishMacro(tableItem, macroStr, macroIndex)
        }
        catch as e {
        }
    }

    OnGuiClose(guiKey) {
        if (this.GuiMap.Has(guiKey)) {
            this.GuiMap.Delete(guiKey)
        }
    }

    HideAllButtons() {
        for key, guiInfo in this.GuiMap {
            try {
                guiInfo.Gui.Hide()
                guiInfo.Gui.Destroy()
            }
        }
        this.GuiMap.Clear()
    }

    RefreshButtons() {
        this.HideAllButtons()
        this.CheckAndShowButtons()
    }

    __Delete() {
        this.StopMonitor()
        this.HideAllButtons()
    }
}
