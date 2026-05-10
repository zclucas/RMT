#Requires AutoHotkey v2.0

class UIMacroSettingGui {
    __new() {
        this.Gui := ""
        this.CurrentMacroIndex := 0
        this.PreviewGui := ""
        this.CoordTimer := ""
        this.InfoAction := () => this.RefreshMouseInfo()
        this.SaveBtnAction := ""
        this.SureFocusCon := ""
    }

    ShowGui(tableItem, macroIndex) {
        if (this.Gui != "") {
            try {
                this.DestroyPreview()
                this.ToggleFunc(false)
                this.Gui.Destroy()
            }
        }
        this.CurrentMacroIndex := macroIndex

        MyGui := Gui(, GetLang("界面宏按钮配置"))
        this.Gui := MyGui
        MyGui.SetFont("S11 Q2", MySoftData.FontType)
        MyGui.OnEvent("Close", (*) => this.OnClose())

        PosX := 10
        PosY := 10

        ;第一行：工具栏（模仿前台信息编辑器）
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("窗口置顶"))
        con.OnEvent("Click", (*) => this.OnTopTogClick())
        this.TopTogCon := con

        PosX := 160
        con := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 30), "F1")
        con.Enabled := false
        PosX += 35
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("确定窗口"))

        PosX := 300
        con := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 30), "F2")
        con.Enabled := false
        PosX += 35
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("确定位置"))

        ;提示文字
        PosY += 32
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("留空则在屏幕上显示"))

        ;第二行：左侧目标窗口信息区域
        PosY += 28
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("当前鼠标下窗口信息："))

        PosY += 25
        this.CurWinInfoCon := MyGui.Add("Text", Format("x{} y{} w260 h80", PosX, PosY))

        ;复选框和输入框（垂直排列）
        PosY += 85
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("句柄ID"))
        con.Value := false
        con.OnEvent("Click", (*) => this.OnInfoTogClick())
        this.InfoTogArrCon := [con]
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w200", PosX, PosY - 3), "")
        con.Enabled := false
        this.InfoTextArrCon := [con]

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("标题"))
        con.Value := false
        con.OnEvent("Click", (*) => this.OnInfoTogClick())
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w200", PosX, PosY - 3), "")
        con.Enabled := false
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("类名"))
        con.Value := false
        con.OnEvent("Click", (*) => this.OnInfoTogClick())
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w200", PosX, PosY - 3), "")
        con.Enabled := false
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("进程名"))
        con.Value := false
        con.OnEvent("Click", (*) => this.OnInfoTogClick())
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w200", PosX, PosY - 3), "")
        con.Enabled := false
        this.InfoTextArrCon.Push(con)

        ;右侧：按钮位置区域
        PosY := 73
        PosX := 340
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("按钮位置(中心点)"))

        PosY += 28
        PosX := 340
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 60), "坐标X：")
        this.PosXEdit := MyGui.Add("Edit", Format("x{} y{} w55 Center", PosX + 60, PosY - 3),
            tableItem.HoldTimeArr.Has(macroIndex) ? tableItem.HoldTimeArr[macroIndex] : "500")
        MyGui.Add("Text", Format("x{} y{} w{}", PosX + 120, PosY, 60), "坐标Y：")
        this.PosYEdit := MyGui.Add("Edit", Format("x{} y{} w55 Center", PosX + 180, PosY - 3),
            tableItem.UIPosYArr.Has(macroIndex) ? tableItem.UIPosYArr[macroIndex] : "10")

        PosY += 35
        PosX := 340
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 60), GetLang("宽度："))
        this.BtnWidthEdit := MyGui.Add("Edit", Format("x{} y{} w55 Center", PosX + 60, PosY - 3),
            tableItem.UIBtnWidthArr.Has(macroIndex) ? tableItem.UIBtnWidthArr[macroIndex] : "100")
        MyGui.Add("Text", Format("x{} y{} w{}", PosX + 120, PosY, 60), GetLang("高度："))
        this.BtnHeightEdit := MyGui.Add("Edit", Format("x{} y{} w55 Center", PosX + 180, PosY - 3),
            tableItem.UIBtnHeightArr.Has(macroIndex) ? tableItem.UIBtnHeightArr[macroIndex] : "30")

        PosY += 38
        PosX := 340
        this.PreviewBtn := MyGui.Add("Button", Format("x{} y{} w70 h32", PosX, PosY), GetLang("预览"))
        this.PreviewBtn.OnEvent("Click", (*) => this.OnPreview())
        this.HidePreviewBtn := MyGui.Add("Button", Format("x{} y{} w70 h32", PosX + 82, PosY), GetLang("隐藏"))
        this.HidePreviewBtn.OnEvent("Click", (*) => this.DestroyPreview())

        PosY += 42
        PosX := 340
        this.ScreenCoordText := MyGui.Add("Text", Format("x{} y{} w170", PosX, PosY),
            Format(GetLang("屏幕: ({}, {})"), "---", "---"))

        ;底部按钮（居中）
        PosY := 330
        PosX := 200
        this.SaveBtn := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        this.SaveBtn.OnEvent("Click", (*) => this.OnSureBtnClick(tableItem))
        this.CancelBtn := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX + 115, PosY), GetLang("取消"))
        this.CancelBtn.OnEvent("Click", (*) => this.OnCancel())
        this.ApplySaveBtn := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX + 230, PosY), GetLang("应用并保存"))
        this.ApplySaveBtn.OnEvent("Click", (*) => this.OnSaveBtnClick(tableItem))

        MyGui.Show("w800 h390")

        frontValue := tableItem.UIWindowArr.Has(macroIndex) ? tableItem.UIWindowArr[macroIndex] : ""

        if (frontValue != "") {
            if (InStr(frontValue, "❖")) {
                idStr := StrReplace(frontValue, "❖", "")
                infoArr := [idStr, "", "", ""]
            } else {
                if (frontValue != "")
                    infoArr := StrSplit(frontValue, "⎖")
                if (frontValue == "" || infoArr.Length < 3)
                    infoArr := ["", "", ""]

                infoArr.InsertAt(1, "")
            }

            loop 4 {
                this.InfoTogArrCon[A_Index].Value := infoArr[A_Index] != ""
                this.InfoTextArrCon[A_Index].Value := infoArr[A_Index]
            }
        }

        this.OnInfoTogClick()

        this.TopTogCon.Value := true
        this.StartCoordMonitor()
        this.ToggleFunc(true)
    }

    OnTopTogClick() {
        try {
            alwaysOnTop := this.TopTogCon.Value ? "AlwaysOnTop" : ""
            this.Gui.Opt("+" alwaysOnTop)
        }
    }

    OnInfoTogClick() {
        for index, con in this.InfoTogArrCon {
            if (!con.Value && this.InfoTextArrCon[index].Enabled)
                this.InfoTextArrCon[index].Enabled := false
            else if (con.Value && !this.InfoTextArrCon[index].Enabled)
                this.InfoTextArrCon[index].Enabled := true
        }
    }

    ToggleFunc(state) {
        if (state) {
            SetTimer this.InfoAction, 100
            Hotkey("F1", (*) => this.OnF1(), "On")
            Hotkey("F2", (*) => this.OnF2(), "On")
        } else {
            SetTimer this.InfoAction, 0
            Hotkey("F1", "Off")
            Hotkey("F2", "Off")
        }
    }

    RefreshMouseInfo() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }

            tipStr := Format("{}{}`n{}{}`n{}{}`n{}{}", GetLang("句柄ID："), winId, GetLang("标题："), title,
                GetLang("窗口类："), className, GetLang("进程名："), process)
            this.CurWinInfoCon.Value := tipStr

            this.ScreenCoordText.Value := Format(GetLang("屏幕: ({}, {})"), mouseX, mouseY)
        }
    }

    OnF1() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }

            this.InfoTextArrCon[1].Value := winId
            this.InfoTextArrCon[2].Value := title
            this.InfoTextArrCon[3].Value := className
            this.InfoTextArrCon[4].Value := process

            this.InfoTogArrCon[1].Value := false
            this.InfoTogArrCon[2].Value := title != ""
            this.InfoTogArrCon[3].Value := className != ""
            this.InfoTogArrCon[4].Value := process != ""
            this.OnInfoTogClick()
        }
    }

    OnF2() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.PosXEdit.Value := mouseX
        this.PosYEdit.Value := mouseY
        this.OnPreview()
    }

    StartCoordMonitor() {
        if (this.CoordTimer != "")
            return
        this.CoordTimer := Timer(this.RefreshMouseInfo.Bind(this), 200)
        this.CoordTimer.On()
    }

    StopCoordMonitor() {
        if (this.CoordTimer != "") {
            this.CoordTimer.Off()
            this.CoordTimer := ""
        }
    }

    OnPreview() {
        this.DestroyPreview()

        try {
            centerX := Integer(this.PosXEdit.Value)
            centerY := Integer(this.PosYEdit.Value)
            btnW := Integer(this.BtnWidthEdit.Value)
            btnH := Integer(this.BtnHeightEdit.Value)

            posX := centerX - btnW // 2
            posY := centerY - btnH // 2

            frontValue := this.GetFrontInfo()
            targetHwnd := ""
            if (frontValue != "") {
                paramStr := GetParamsWinInfoStr(frontValue, "UIPreview")
                if (paramStr != "") {
                    hwndList := WinGetList(paramStr)
                    if (hwndList.Length > 0 && hwndList[1])
                        targetHwnd := hwndList[1]
                }
            }

            if (targetHwnd) {
                try {
                    this.PreviewGui := Gui("+Owner" targetHwnd " +AlwaysOnTop +ToolWindow -Caption")
                    this.PreviewGui.Opt("+Parent" targetHwnd)
                }
                catch as e {
                    this.PreviewGui := Gui("+AlwaysOnTop +ToolWindow -Caption +DPIScale")
                }
            } else {
                this.PreviewGui := Gui("+AlwaysOnTop +ToolWindow -Caption +DPIScale")
            }

            if (targetHwnd && this.PreviewGui.Hwnd) {
                try {
                    parentHwnd := DllCall("GetParent", "Ptr", this.PreviewGui.Hwnd, "Ptr")
                    if (parentHwnd != 0) {
                        WinGetPos(&winX, &winY, , , "ahk_id " targetHwnd)
                        posX -= winX
                        posY -= winY
                    }
                }
            }

            this.PreviewGui.SetFont("S11 W550", MySoftData.FontType)
            this.PreviewGui.BackColor := "4a90d9"
            WinSetTransColor("4a90d9", this.PreviewGui)

            remarkValue := ""
            tableItem := MySoftData.TableInfo[4]
            if (tableItem.RemarkArr.Has(this.CurrentMacroIndex))
                remarkValue := tableItem.RemarkArr[this.CurrentMacroIndex]
            btnText := remarkValue == "" ? GetLang("预览") : remarkValue

            this.PreviewGui.Add("Button", "x0 y0 w" btnW " h" btnH, btnText)
            this.PreviewGui.Show(Format("x{} y{} NA", posX, posY))
            this.PreviewGui.Move(, , btnW, btnH)
        }
        catch as e {
        }
    }

    DestroyPreview() {
        if (this.PreviewGui != "") {
            try {
                this.PreviewGui.Destroy()
            }
            this.PreviewGui := ""
        }
    }

    GetFrontInfo() {
        if (this.InfoTogArrCon[1].Value)
            return "❖" this.InfoTextArrCon[1].Value

        Str := ""
        loop 4 {
            if (A_Index == 1)
                continue
            if (this.InfoTogArrCon[A_Index].Value) {
                Str .= this.InfoTextArrCon[A_Index].Value
            }
            if (A_Index != 4)
                Str .= "⎖"
        }
        if (Str == "⎖⎖")
            return ""
        return Str
    }

    OnSureBtnClick(tableItem) {
        this.UpdateTableItem(tableItem)
        this.StopCoordMonitor()
        this.ToggleFunc(false)
        this.DestroyPreview()
        this.Gui.Hide()
        if (this.SureFocusCon != "")
            this.SureFocusCon.Focus()
    }

    OnSaveBtnClick(tableItem) {
        this.UpdateTableItem(tableItem)
        this.StopCoordMonitor()
        this.ToggleFunc(false)
        this.DestroyPreview()
        this.Gui.Hide()

        action := this.SaveBtnAction
        if (action != "")
            action()
        
        MyUIMacroGui.RefreshButtons()
        
        if (this.SureFocusCon != "")
            this.SureFocusCon.Focus()
    }

    UpdateTableItem(tableItem) {
        macroIndex := this.CurrentMacroIndex

        frontValue := this.GetFrontInfo()
        posXValue := Integer(this.PosXEdit.Value)
        posYValue := Integer(this.PosYEdit.Value)
        btnWidthValue := Integer(this.BtnWidthEdit.Value)
        btnHeightValue := Integer(this.BtnHeightEdit.Value)

        if (tableItem.UIWindowArr.Has(macroIndex))
            tableItem.UIWindowArr[macroIndex] := frontValue
        else
            tableItem.UIWindowArr.Push(frontValue)

        if (tableItem.HoldTimeArr.Has(macroIndex))
            tableItem.HoldTimeArr[macroIndex] := posXValue
        else
            tableItem.HoldTimeArr.Push(posXValue)

        if (tableItem.UIPosYArr.Has(macroIndex))
            tableItem.UIPosYArr[macroIndex] := posYValue
        else
            tableItem.UIPosYArr.Push(posYValue)

        if (tableItem.UIBtnWidthArr.Has(macroIndex))
            tableItem.UIBtnWidthArr[macroIndex] := btnWidthValue
        else
            tableItem.UIBtnWidthArr.Push(btnWidthValue)

        if (tableItem.UIBtnHeightArr.Has(macroIndex))
            tableItem.UIBtnHeightArr[macroIndex] := btnHeightValue
        else
            tableItem.UIBtnHeightArr.Push(btnHeightValue)
    }

    OnCancel() {
        this.StopCoordMonitor()
        this.ToggleFunc(false)
        this.DestroyPreview()
        this.Gui.Hide()
    }

    OnClose() {
        this.StopCoordMonitor()
        this.ToggleFunc(false)
        this.DestroyPreview()
        this.Gui := ""
    }
}