#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk
#Include WinRuleGui.ahk

class ScreenShotGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.PosAction := () => this.RefreshMouseInfo()
        this.F1Action := (x1, y1, x2, y2) => this.OnF1SetAreaAction(x1, y1, x2, y2)
        this.Data := ""
        this.MacroGui := ""

        this.WinInfoArr := []
        this.ResultTogArr := []
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            if (this.OwnerHwnd != "") {
                this.Gui.Opt("+Owner" this.OwnerHwnd)
            }
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.Init(cmd)
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("抓图编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 90
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 35
        PosX := 10
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY, 25), "F1")
        con.Enabled := false

        PosX += 30
        this.SelectToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{} h{} Left", PosX, PosY, 150, 25), GetLang(
            "左键框选截图范围"))
        this.SelectToggleCon.OnEvent("Click", (*) => this.OnClickSelectToggle())

        PosX := 10
        PosY += 35
        this.MousePosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 200, 20), GetLang("屏幕坐标：0,0"))
        PosX += 200
        this.MouseWinPosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 200, 20), GetLang("窗口坐标：0,0"))

        PosX := 10
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("抓图类型："))
        PosX += 80
        this.ScreenShotTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R2", PosX, PosY - 3, 160), GetLangArr([
            "屏幕抓图", "窗口抓图"]))
        this.ScreenShotTypeCon.OnEvent("Change", (*) => this.OnChangeType())
        this.ScreenShotTypeCon.Value := 1

        PosX := 10
        PosY += 35
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口信息:"))
        this.WinInfoArr.Push(con)
        PosX += 80
        this.WinInfoCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 200), "")
        this.WinInfoArr.Push(this.WinInfoCon)
        PosX += 210
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 50, 27), GetLang("编辑"))
        btnCon.OnEvent("Click", this.OnClickWinEditBtn.Bind(this))
        this.WinInfoArr.Push(btnCon)

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标X："))
        PosX += 80
        this.StartPosXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosX := 180
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标Y："))
        PosX += 80
        this.StartPosYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标X："))
        PosX += 80
        this.EndPosXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosX := 180
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标Y："))
        PosX += 80
        this.EndPosYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("命名方式："))
        PosX += 80
        this.NameTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R2", PosX, PosY - 3, 160), GetLangArr([
            "默认", "固定名称"]))
        this.NameTypeCon.OnEvent("Change", (*) => this.OnChangeNameType())
        this.NameTypeCon.Value := 1

        PosX := 10
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("固定名称："))
        PosX += 80
        this.FixedNameCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 250), "")
        this.FixedNameCon.Enabled := false

        PosY += 35
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 480, 75), GetLang("结果保存"))

        PosY += 20
        PosX := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))
        PosX += 50
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("变量名"))
        this.ResultTogArr.Push(con)

        PosY += 25
        PosX := 20
        this.ResultToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ResultToggleCon.OnEvent("Click", (*) => this.OnChangeResultToggle())
        this.ResultSaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 30, PosY - 3, 200), [])
        this.ResultTogArr.Push(this.ResultSaveNameCon)

        PosY += 35
        PosX := 220
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())
        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 500, 460))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("抓图")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        if (!this.CheckIfDataValid())
            return

        this.ScreenShotTypeCon.Value := this.Data.ScreenShotType
        this.WinInfoCon.Value := this.Data.WinInfo
        this.StartPosXCon.Delete()
        this.StartPosXCon.Add(this.DLVariableArr)
        this.StartPosYCon.Delete()
        this.StartPosYCon.Add(this.DLVariableArr)
        this.EndPosXCon.Delete()
        this.EndPosXCon.Add(this.DLVariableArr)
        this.EndPosYCon.Delete()
        this.EndPosYCon.Add(this.DLVariableArr)
        this.StartPosXCon.Text := this.Data.StartPosX
        this.StartPosYCon.Text := this.Data.StartPosY
        this.EndPosXCon.Text := this.Data.EndPosX
        this.EndPosYCon.Text := this.Data.EndPosY
        this.NameTypeCon.Value := this.Data.NameType
        this.FixedNameCon.Value := this.Data.FixedName
        this.ResultToggleCon.Value := this.Data.ResultToggle
        this.ResultSaveNameCon.Delete()
        this.ResultSaveNameCon.Add(this.DLVariableArr)
        this.ResultSaveNameCon.Text := this.Data.ResultSaveName

        this.OnChangeType()
        this.OnChangeNameType()
        this.OnChangeResultToggle()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    OnClickWinEditBtn(*) {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(this.WinInfoCon)
    }

    CheckIfDataValid() {
        return true
    }

    CheckIfValid() {
        isWin := this.ScreenShotTypeCon.Value == 2

        if (IsNumber(this.StartPosXCon.Text) && IsNumber(this.StartPosYCon.Text) && IsNumber(this.EndPosXCon.Text) && IsNumber(this.EndPosYCon.Text)) {
            if (Number(this.StartPosXCon.Text) > Number(this.EndPosXCon.Text) || Number(this.StartPosYCon.Text) > Number(this.EndPosYCon.Text)) {
                MsgBox(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }

        if (isWin && this.WinInfoCon.Value == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (this.NameTypeCon.Value == 2 && this.FixedNameCon.Value == "") {
            MsgBox(GetLang("固定名称不能为空"))
            return false
        }

        if (this.ResultToggleCon.Value) {
            if (!CheckVarNameIfValid(this.ResultSaveNameCon.Text))
                return false
        }

        return true
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    RefreshMouseInfo() {
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            this.MousePosCon.Value := Format("{}{},{}", GetLang("屏幕坐标："), mouseX, mouseY)
            PosArr := GetCurWinPos()
            this.MouseWinPosCon.Value := Format("{}{},{}", GetLang("窗口坐标："), PosArr[1], PosArr[2])
        }
    }

    OnChangeType(*) {
        curType := this.ScreenShotTypeCon.Value
        isWin := curType == 2
        this.SetConArrState(this.WinInfoArr, false, isWin)
        this.MousePosCon.Focus()
    }

    OnChangeNameType(*) {
        nameType := this.NameTypeCon.Value
        this.FixedNameCon.Enabled := (nameType == 2)
        if (nameType == 1)
            this.FixedNameCon.Value := ""
    }

    OnChangeResultToggle(*) {
        isSave := this.ResultToggleCon.Value
        this.SetConArrState(this.ResultTogArr, true, isSave)
    }

    SetConArrState(ConArr, isEnabled, state) {
        for Value in ConArr {
            if (isEnabled)
                Value.Enabled := state
            else
                Value.Visible := state
        }
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnClickSelectToggle() {
        state := this.SelectToggleCon.Value
        if (state == 1)
            TogSelectArea(true, this.F1Action)
        else
            TogSelectArea(false)
    }

    OnF1() {
        this.SelectToggleCon.Value := 1
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        this.SelectToggleCon.Value := 0
        curType := this.ScreenShotTypeCon.Value
        isWin := curType == 2
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]

        this.StartPosXCon.Text := Point1[1]
        this.StartPosYCon.Text := Point1[2]
        this.EndPosXCon.Text := Point2[1]
        this.EndPosYCon.Text := Point2[2]
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.ToggleFunc(false)

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnGuiClose() {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    SaveData() {
        data := this.Data
        data.ScreenShotType := this.ScreenShotTypeCon.Value
        data.WinInfo := this.WinInfoCon.Value
        data.StartPosX := this.StartPosXCon.Text
        data.StartPosY := this.StartPosYCon.Text
        data.EndPosX := this.EndPosXCon.Text
        data.EndPosY := this.EndPosYCon.Text
        data.NameType := this.NameTypeCon.Value
        data.FixedName := this.FixedNameCon.Value
        data.ResultToggle := this.ResultToggleCon.Value
        data.ResultSaveName := GetVarName(this.ResultSaveNameCon.Text)

        if (data.ResultToggle)
            MySoftData.GlobalVariMap[data.ResultSaveName] := true

        SaveMacroCMDData(data)
    }
}
