#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

class LoopGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.MacroGui := ""
        this.FocusCon := ""

        this.Data := ""
        this.ToggleConArr := []
        this.NameConArr := []
        this.CompareTypeConArr := []
        this.VariableConArr := []
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
        this.OnRefresh()
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("循环编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("快捷方式："))
        PosX += 70
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 90
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosX := 20
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY - 2, 80, 20), GetLang("循环次数："))

        PosX += 80
        this.CountCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 5, 150), [])

        PosX := 10
        PosY += 30
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 445, 200), GetLang("循环条件:"))

        PosX := 20
        PosY += 25
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("类型:"))

        PosX += 45
        this.CondiCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 140), GetLangArr(["无", "继续条件",
            "退出条件"]))
        this.CondiCon.OnEvent("Change", (*) => this.OnRefresh())

        PosX += 220
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 100, 20), GetLang("条件逻辑关系:"))
        PosX += 100
        this.LogicCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 60), GetLangArr(["且", "或"]))

        PosY += 30
        PosX := 30
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 140), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 180, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 275, PosY - 3, 140), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 30
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 140), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 180, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 275, PosY - 3, 140), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 30
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 140), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 180, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 275, PosY - 3, 140), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 30
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 140), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 180, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 275, PosY - 3, 140), [])
        this.VariableConArr.Push(con)

        PosY += 45
        PosX := 20
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 5), GetLang("循环体:"))
        PosX += 60
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 1, 70, 30), GetLang("编辑"))
        con.OnEvent("Click", this.OnEditMacroBtnClick.Bind(this))
        PosY += 30
        PosX := 10
        this.LoopBodyCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 450, 100), "")

        PosY += 110
        PosX := 190
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())
        this.FocusCon := btnCon

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(470, 470)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 470, 470))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("循环")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        CountVariableArr := GetGuiVarArr(2)
        CountVariableArr.Push(GetLang("无限"))
        this.CountCon.Delete()
        this.CountCon.Add(CountVariableArr)
        this.CountCon.Text := this.Data.LoopCount == -1 ? GetLang("无限") : this.Data.LoopCount

        this.CondiCon.Value := this.Data.CondiType
        this.LogicCon.Value := this.Data.LogicType
        this.LoopBodyCon.Value := GetLangMacro(this.Data.LoopBody, 1)

        loop 4 {
            this.ToggleConArr[A_Index].Value := this.Data.ToggleArr[A_Index]
            this.NameConArr[A_Index].Delete()
            this.NameConArr[A_Index].Add(this.DLVariableArr)
            this.NameConArr[A_Index].Text := GetLang(this.Data.NameArr[A_Index])
            this.CompareTypeConArr[A_Index].Value := this.Data.CompareTypeArr[A_Index]
            this.VariableConArr[A_Index].Delete()
            this.VariableConArr[A_Index].Add(this.DLVariableArr)
            this.VariableConArr[A_Index].Text := GetLang(this.Data.VariableArr[A_Index])
        }
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            Hotkey("!l", MacroAction, "On")
        }
        else {
            Hotkey("!l", MacroAction, "Off")
        }
    }

    OnRefresh() {
        showCondi := this.CondiCon.Value != 1
        this.LogicCon.Enabled := showCondi

        loop 4 {
            OperaTypeValue := this.CompareTypeConArr[A_Index].Value
            EnableVari := OperaTypeValue != 7

            this.ToggleConArr[A_Index].Enabled := showCondi
            this.NameConArr[A_Index].Enabled := showCondi
            this.CompareTypeConArr[A_Index].Enabled := showCondi
            this.VariableConArr[A_Index].Enabled := EnableVari && showCondi
        }
    }

    OnEditMacroBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            this.MacroGui.SureFocusCon := this.FocusCon

            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.MacroGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        SureAction(command) {
            command := GetLangMacro(command, 1)
            this.LoopBodyCon.Value := command
        }

        this.MacroGui.SureBtnAction := SureAction
        this.MacroGui.ShowGui(this.LoopBodyCon.Value, false)
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveLoopData()
        this.ToggleFunc(false)
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)

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

    CheckIfValid() {

        return true
    }

    TriggerMacro() {
        this.SaveLoopData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    SaveLoopData() {
        this.Data.LoopCount := this.CountCon.Text == GetLang("无限") ? -1 : this.CountCon.Text
        this.Data.CondiType := this.CondiCon.Value
        this.Data.LogicType := this.LogicCon.Value
        this.Data.LoopBody := GetLangMacro(this.LoopBodyCon.Value, 2)

        loop 4 {
            this.Data.ToggleArr[A_Index] := this.ToggleConArr[A_Index].Value
            this.Data.NameArr[A_Index] := GetLangKey(this.NameConArr[A_Index].Text)
            this.Data.CompareTypeArr[A_Index] := this.CompareTypeConArr[A_Index].Value
            this.Data.VariableArr[A_Index] := GetLangKey(this.VariableConArr[A_Index].Text)
        }
        SaveMacroCMDData(this.Data)
    }
}
