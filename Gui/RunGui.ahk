#Requires AutoHotkey v2.0

class RunGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.RemarkCon := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.PathTextCon := ""
        this.VariCon := ""
        this.VariTipCon := ""
        this.RunModeCon := ""
        this.SaveNameConArr := []
        this.SaveNameTipConArr := []

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
        MyGui := Gui(, this.ParentTile GetLang("运行编辑器"))
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
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("模式："))

        PosX += 40
        ModeArr := [GetLang("不等待"), GetLang("等待+返回值"), GetLang("等待+完整输出")]
        this.RunModeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R3", PosX, PosY - 3, 110), ModeArr)
        this.RunModeCon.OnEvent("Change", (*) => this.OnModeChange())

        PosX += 120
        tip1 := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("返回值"))
        this.SaveNameTipConArr.Push(tip1)
        PosX += 50
        con1 := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 3, 80), [])
        this.SaveNameConArr.Push(con1)

        PosX += 90
        tip2 := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 40), GetLang("输出"))
        this.SaveNameTipConArr.Push(tip2)
        PosX += 40
        con2 := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 3, 80), [])
        this.SaveNameConArr.Push(con2)

        PosX += 90
        tip3 := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 40), GetLang("错误"))
        this.SaveNameTipConArr.Push(tip3)
        PosX += 40
        con3 := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 3, 80), [])
        this.SaveNameConArr.Push(con3)

        PosY += 35
        PosX := 10
        this.VariTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 150), GetLang("变量："))

        PosX += 40
        this.VariCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 3, 110), [])

        PosX += 120
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 60, 25), GetLang("追加名"))
        btnCon.OnEvent("Click", (*) => this.OnClickAddVarNameBtn())

        PosX += 70
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 60, 25), GetLang("追加值"))
        btnCon.OnEvent("Click", (*) => this.OnClickAddVarValueBtn())

        PosX := 10
        PosY += 35
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("目标："))

        PosX += 40
        this.PathTextCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 440))

        PosX += 445
        btnCon := MyGui.Add("Button", Format("x{} y{}", PosX, PosY - 5), GetLang("选择文件"))
        btnCon.OnEvent("Click", (*) => this.OnClickFileSelectBtn())

        PosY += 25
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("支持类别：CMD指令、网址、文件等等"))

        PosY += 25
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("支持文件后缀：exe、txt、bat、vbs、mp4、mp3、py等等"))

        PosY += 35
        PosX := 240
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 580, 260))
    }

    OnModeChange() {
        val := this.RunModeCon.Value
        if (val == 1) {
            loop 3 {
                this.SaveNameTipConArr[A_Index].Visible := false
                this.SaveNameConArr[A_Index].Visible := false
            }
        } else if (val == 2) {
            this.SaveNameTipConArr[1].Visible := true
            this.SaveNameConArr[1].Visible := true
            loop 2 {
                this.SaveNameTipConArr[A_Index + 1].Visible := false
                this.SaveNameConArr[A_Index + 1].Visible := false
            }
        } else {
            loop 3 {
                this.SaveNameTipConArr[A_Index].Visible := true
                this.SaveNameConArr[A_Index].Visible := true
            }
        }
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运行")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        this.PathTextCon.Value := this.Data.RunPath

        DLVariableArr := GetGuiVarArr(1)
        this.VariCon.Delete()
        this.VariCon.Add(DLVariableArr)
        this.VariCon.Value := 1

        this.RunModeCon.Value := this.Data.RunMode
        loop 3 {
            this.SaveNameConArr[A_Index].Delete()
            this.SaveNameConArr[A_Index].Add(GetGuiVarArr(0))
            this.SaveNameConArr[A_Index].Text := this.Data.SaveNameArr[A_Index]
        }
        this.OnModeChange()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
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

    OnClickFileSelectBtn() {
        fileString := FileSelect("S1", "", GetLang("选择要运行的文件"))
        if (fileString == "")
            return

        this.PathTextCon.Value := fileString
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveRunData()
        this.ToggleFunc(false)
        action := this.SureBtnAction
        action(this.GetCommandStr())

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
        if (this.PathTextCon.Value == "") {
            MsgBox(GetLang("目标不能为空！"))
            return false
        }
        return true
    }

    TriggerMacro() {
        this.SaveRunData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveRunData() {
        this.Data.RunPath := GetLangStr(this.PathTextCon.Value, 2)
        this.Data.RunMode := this.RunModeCon.Value
        loop 3 {
            this.Data.SaveNameArr[A_Index] := this.SaveNameConArr[A_Index].Text
        }

        SaveMacroCMDData(this.Data)
    }

    OnClickAddVarNameBtn() {
        this.PathTextCon.Value .= this.VariCon.Text
    }

    OnClickAddVarValueBtn() {
        if (this.VariCon.Text != "")
            this.PathTextCon.Value .= "{" this.VariCon.Text "}"
    }
}
