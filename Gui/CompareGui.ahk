#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

class CompareGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.FocusCon := ""
        this.MacroGui := ""

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
        this.ToggleFunc(true)
        this.OnRefresh()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("如果编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 90
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 30), GetLang("逻辑关系："))
        this.LogicalTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 80, PosY - 3, 70), GetLangArr([
            "且", "或"]))

        PosX := 400
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX, PosY - 5), "?")
        Con.OnEvent("Click", this.OnClickTypeHelpBtn.Bind(this))

        PosY += 30
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        con.OnEvent("Click", this.OnRefresh.Bind(this))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 150), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 190, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 285, PosY - 3, 150), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.OnEvent("Click", this.OnRefresh.Bind(this))
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 150), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 190, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 285, PosY - 3, 150), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.OnEvent("Click", this.OnRefresh.Bind(this))
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 150), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 190, PosY - 3, 90), GetLangArr(GetLangArr(["大于",
            "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"])))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 285, PosY - 3, 150), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.OnEvent("Click", this.OnRefresh.Bind(this))
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 150), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 190, PosY - 3, 90), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 285, PosY - 3, 150), [])
        this.VariableConArr.Push(con)

        PosY += 45
        PosX := 10
        SplitPosY := PosY
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 150, 20), GetLang("真-分支指令:（可选）"))

        PosX += 155
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 60, 28), GetLang("编辑"))
        btnCon.OnEvent("Click", (*) => this.OnTrueBtnClick())

        PosY += 25
        PosX := 10
        this.TrueMacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 215, 60), "")

        PosY := SplitPosY
        PosX := 235
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 150, 20), GetLang("假-分支指令:（可选）"))

        PosX += 155
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 60, 28), GetLang("编辑"))
        btnCon.OnEvent("Click", (*) => this.OnFalseBtnClick())

        PosY += 25
        PosX := 235
        this.FalseMacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 215, 60), "")

        PosY += 65
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), GetLang("真-流程控制："))
        PosX += 90
        this.TrueControlCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY, 125), GetLangArr(["无",
            "循环-跳过本轮", "循环-跳出", "分支-跳出"]))
        this.TrueControlCon.Value := 1

        PosX := 235
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), GetLang("假-流程控制："))
        PosX += 90
        this.FalseControlCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY, 125), GetLangArr(["无",
            "循环-跳过本轮", "循环-跳出", "分支-跳出"]))
        this.FalseControlCon.Value := 1

        PosY += 40
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 340, 90), GetLang("结果保存"))

        PosX := 15
        PosY += 30
        this.ResultConArr := []
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))

        PosX += 50
        Con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("选择/输入"))
        this.ResultConArr.Push(Con)

        PosX += 140
        Con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("真值"))
        this.ResultConArr.Push(Con)

        PosX += 80
        Con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("假值"))
        this.ResultConArr.Push(Con)

        PosY += 25
        PosX := 20
        this.SaveToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.SaveToggleCon.OnEvent("Click", this.OnRefresh.Bind(this))
        this.SaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.TrueValueCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 165, PosY - 4, 70), 0)
        this.FalseValueCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 245, PosY - 4, 70), 0)
        this.ResultConArr.Push(this.SaveNameCon)
        this.ResultConArr.Push(this.TrueValueCon)
        this.ResultConArr.Push(this.FalseValueCon)

        PosY -= 30
        PosX := 360
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 90, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())
        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(480, 450)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 480, 450))
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("如果")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        this.TrueControlCon.Text := GetLang(this.Data.TrueControlType)
        this.FalseControlCon.Text := GetLang(this.Data.FalseControlType)
        this.TrueMacroCon.Value := GetLangMacro(this.Data.TrueMacro, 1)
        this.FalseMacroCon.Value := GetLangMacro(this.Data.FalseMacro, 1)
        this.SaveToggleCon.Value := this.Data.SaveToggle
        this.SaveNameCon.Delete()
        this.SaveNameCon.Add(GetGuiVarArr())
        this.SaveNameCon.Text := GetLang(this.Data.SaveName)
        this.TrueValueCon.Value := this.Data.TrueValue
        this.FalseValueCon.Value := this.Data.FalseValue
        this.LogicalTypeCon.Value := this.Data.LogicalType
        loop this.Data.ToggleArr.Length {
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

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    CheckIfValid() {
        if (this.SaveToggleCon.Value && !CheckVarNameIfValid(this.SaveNameCon.Text))
            return false

        return true
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

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("无：不进行任何流程控制操作")
        str1 := GetLang("循环-跳过本轮：跳过后续循环体指令，继续上层循环")
        str2 := GetLang("循环-跳出：跳出上层循环")
        str3 := GetLang("分支-跳出：跳出上层分支")

        str := Format("{}`n{}`n{}", str1, str2, str3)
        MsgBox(str, GetLang("流程控制说明"))
    }

    OnRefresh(*) {
        loop 4 {
            isEnable := this.ToggleConArr[A_Index].Value

            this.NameConArr[A_Index].Enabled := isEnable
            this.CompareTypeConArr[A_Index].Enabled := isEnable
            OperaTypeValue := this.CompareTypeConArr[A_Index].Value
            EnableVari := OperaTypeValue != 7 && isEnable
            this.VariableConArr[A_Index].Enabled := EnableVari
        }

        canEditResult := this.SaveToggleCon.Value
        loop this.ResultConArr.Length {
            this.ResultConArr[A_Index].Enabled := canEditResult
        }
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveCompareData()
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

    OnTrueSure(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.TrueMacroCon.Value := CommandStr
    }

    OnFalseSure(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.FalseMacroCon.Value := CommandStr
    }

    OnTrueBtnClick() {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
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

        this.MacroGui.SureBtnAction := (command) => this.OnTrueSure(command)
        this.MacroGui.ShowGui(this.TrueMacroCon.Value, false)
    }

    OnFalseBtnClick() {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
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

        this.MacroGui.SureBtnAction := (command) => this.OnFalseSure(command)
        this.MacroGui.ShowGui(this.FalseMacroCon.Value, false)
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveCompareData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveCompareData() {
        this.Data.TrueControlType := GetLangKey(this.TrueControlCon.Text)
        this.Data.FalseControlType := GetLangKey(this.FalseControlCon.Text)
        this.Data.TrueMacro := GetLangMacro(this.TrueMacroCon.Value, 2)
        this.Data.FalseMacro := GetLangMacro(this.FalseMacroCon.Value, 2)
        this.Data.SaveToggle := this.SaveToggleCon.Value
        this.Data.SaveName := GetVarName(this.SaveNameCon.Text)
        this.Data.TrueValue := this.TrueValueCon.Value
        this.Data.FalseValue := this.FalseValueCon.Value
        this.Data.LogicalType := this.LogicalTypeCon.Value
        loop 4 {
            this.Data.ToggleArr[A_Index] := this.ToggleConArr[A_Index].Value
            this.Data.NameArr[A_Index] := GetLangKey(this.NameConArr[A_Index].Text)
            this.Data.CompareTypeArr[A_Index] := this.CompareTypeConArr[A_Index].Value
            this.Data.VariableArr[A_Index] := GetLangKey(this.VariableConArr[A_Index].Text)
        }

        ; 添加全局变量，方便下拉选取
        if (this.Data.SaveToggle) {
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        }

        SaveMacroCMDData(this.Data)
    }
}
