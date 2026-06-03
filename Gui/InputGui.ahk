#Requires AutoHotkey v2.0

class InputGui {
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
        this.RefreshConVisable()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("输入编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80, 20), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 120
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosX := 20
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("输入类型:"))
        PosX += 80
        TypeArr := GetLangArr(["弹窗", "状态", "继续", "继续&取消"])
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 130), TypeArr)
        this.TypeCon.OnEvent("Change", this.OnRefreshType.Bind(this))

        PosX := 20
        PosY += 40
        this.InterConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("交互时:"))
        this.InterConArr.Push(con)
        PosX += 80
        TypeArr := GetLangArr(["暂停当前宏", "暂停所有宏"])
        this.PauseTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 130), TypeArr)
        this.InterConArr.Push(this.PauseTypeCon)

        PosX := 280
        this.CancelConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("取消时:"))
        this.CancelConArr.Push(con)
        PosX += 80
        TypeArr := GetLangArr(["终止当前宏", "终止所有宏"])
        this.CancelTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 3, 130), TypeArr)
        this.CancelConArr.Push(this.CancelTypeCon)

        PosX := 10
        PosY += 40
        this.ResultConArr := []
        Con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 490, 70), GetLang("结果保存"))
        this.ResultConArr.Push(Con)

        PosX := 20
        PosY += 35
        Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("变量："))
        this.ResultConArr.Push(Con)

        PosX += 50
        this.SaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 130), [])
        this.ResultConArr.Push(this.SaveNameCon)

        PosY += 50
        PosX := 210
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{} Center", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(510, 275)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 510, 275))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("输入")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        this.DLArrayArr := GetGuiArrNameArr()

        this.TypeCon.Text := GetLang(this.Data.Type)
        this.PauseTypeCon.Text := GetLang(this.Data.PauseType)
        this.CancelTypeCon.Text := GetLang(this.Data.CancelType)
        this.SaveNameCon.Text := this.Data.SaveName
        SetDLConValue(this.SaveNameCon, GetGuiVarArr(), this.SaveNameCon.Text)
    }

    OnRefreshType(*) {
        this.RefreshConVisable()
    }

    RefreshConVisable() {
        IsPopUp := this.TypeCon.Text == GetLang("弹窗")
        IsState := this.TypeCon.Text == GetLang("状态")
        IsGoOn := this.TypeCon.Text == GetLang("继续")
        IsGoOnAndCancel := this.TypeCon.Text == GetLang("继续&取消")

        HasInter := IsPopUp || IsState || IsGoOn || IsGoOnAndCancel
        HasCancel := IsGoOnAndCancel
        HasRes := IsPopUp || IsState

        this.SetConArrVisible(this.InterConArr, HasInter)
        this.SetConArrVisible(this.CancelConArr, HasCancel)
        this.SetConArrVisible(this.ResultConArr, HasRes)
    }

    SetConArrVisible(ConArr, Visible) {
        loop ConArr.Length {
            ConArr[A_Index].Visible := Visible
        }
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
        if (!CheckVarNameIfValid(this.SaveNameCon.Text))
            return false

        return true
    }

    TriggerMacro() {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)

        IsPopUp := this.TypeCon.Text == GetLang("弹窗")
        IsState := this.TypeCon.Text == GetLang("状态")
        HasRes := IsPopUp || IsState
        if (HasRes) {
            Res := ""
            if (MySoftData.VariableMap.Has(this.Data.SaveName))
                Res := MySoftData.VariableMap[this.Data.SaveName]

            if (Res != "") {
                tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
                tip2 := Format(GetLang("值：{}"), Res)
                MsgBox(tip1 "`n" tip2)
            }
        }

    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.RemarkCon.Value
        if (Remark == "") {
            Remark := this.TypeCon.Text
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveData() {
        this.Data.Type := GetLangKey(this.TypeCon.Text)
        this.Data.PauseType := GetLangKey(this.PauseTypeCon.Text)
        this.Data.CancelType := GetLangKey(this.CancelTypeCon.Text)
        this.Data.SaveName := GetVarName(this.SaveNameCon.Text)

        if (this.SaveNameCon.Visible) {
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
