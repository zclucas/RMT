#Requires AutoHotkey v2.0

class CommentGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
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
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("注释编辑器"))
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

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("注释内容："))

        PosY += 25
        this.ContentCon := MyGui.Add("Edit", Format("x{} y{} w{} h{} Multi VScroll", PosX, PosY, 480, 120), "")

        PosY += 140
        PosX := 210
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{} Center", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 510, 275))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("注释")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.ContentCon.Value := this.Data.Content
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveData()
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
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    CheckIfValid() {
        if (Trim(this.ContentCon.Value) == "") {
            MsgBox(GetLang("注释内容不能为空"), "", "Owner" this.Gui.Hwnd)
            return false
        }
        return true
    }

    TriggerMacro() {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.Data.Content
        if (StrLen(Remark) > 20) {
            Remark := SubStr(Remark, 1, 20) "..."
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveData() {
        this.Data.Content := Trim(this.ContentCon.Value)
        SaveMacroCMDData(this.Data)
    }
}
