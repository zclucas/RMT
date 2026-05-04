#Requires AutoHotkey v2.0

class OutputGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.FilePathConArr := []
        this.ExcelConArr := []
        this.Data := ""
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
        MyGui := Gui(, this.ParentTile GetLang("输出编辑器"))
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

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 20), GetLang("输出类型:"))
        PosX += 80
        this.OutputTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 150), GetLangArr(["发送内容",
            "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板"]))
        this.OutputTypeCon.Value := 1

        PosX := 10
        PosY += 30
        this.TextTipCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 20), GetLang("输出内容："))
        PosX += 80
        this.TextCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 370, 50))

        PosX := 10
        PosY += 55
        this.VariTipCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 350, 20), GetLang("变量数组："))
        PosX += 80
        this.VarTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY, 85), GetLangArr(["变量",
            "数组"]))
        this.VarTypeCon.Value := 1
        this.VarTypeCon.OnEvent("Change", this.OnRefreshVarType.Bind(this))
        PosX += 90
        this.VariCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R10", PosX, PosY, 130), [])
        this.VarNameBtn := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 135, PosY - 1, 70, 29), GetLang("追加名"))
        this.VarNameBtn.OnEvent("Click", (*) => this.OnClickAddVarNameBtn())
        this.VarValueBtn := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 210, PosY - 1, 70, 29), GetLang("追加值"))
        this.VarValueBtn.OnEvent("Click", (*) => this.OnClickAddVarValueBtn())

        PosY += 40
        PosX := 200
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 500, 240))
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("输出")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        this.TextCon.Value := GetLangStr(this.Data.Text, 1)
        this.OutputTypeCon.Text := GetLang(this.Data.OutputType)
        this.VariCon.Delete()
        this.VariCon.Add(this.DLVariableArr)
        this.VariCon.Value := 1
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

    OnRefreshVarType(*) {
        IsResVar := this.VarTypeCon.Text == GetLang("变量")
        DLArr := IsResVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
        SetDLConValue(this.VariCon, DLArr, this.VariCon.Text)
    }

    OnClickAddVarNameBtn() {
        this.TextCon.Value .= this.VariCon.Text
    }

    OnClickAddVarValueBtn() {
        ArraySymbol := this.VarTypeCon.Text == GetLang("变量") ? "" : "ε"
        this.TextCon.Value .= "{" ArraySymbol this.VariCon.Text "}"
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveOutputData()
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

    CheckIfValid() {
        return true
    }

    TriggerMacro() {
        this.SaveOutputData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    SaveOutputData() {
        this.Data.Text := GetLangStr(this.TextCon.Value, 2)
        this.Data.OutputType := GetLangKey(this.OutputTypeCon.Text)
        SaveMacroCMDData(this.Data)
    }
}
