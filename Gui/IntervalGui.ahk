#Requires AutoHotkey v2.0

class IntervalGui {
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVarArr := GetGuiVarArr()
        if (cmdArr.Length <= 1) {
            this.TypeCon.Value := 1
            SetDLConValue(this.TimeVarCon1, DLVarArr, "500")
            SetDLConValue(this.TimeVarCon2, DLVarArr, "1000")
        }
        else {
            TimeArr := StrSplit(cmdArr[2], "~")
            if (TimeArr.Length <= 1) {
                this.TypeCon.Value := 1
                SetDLConValue(this.TimeVarCon1, DLVarArr, cmdArr[2])
                SetDLConValue(this.TimeVarCon2, DLVarArr, "1000")
            }
            else {
                this.TypeCon.Value := 2
                SetDLConValue(this.TimeVarCon1, DLVarArr, TimeArr[1])
                SetDLConValue(this.TimeVarCon2, DLVarArr, TimeArr[2])
            }
        }
        this.OnTypeChange()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("间隔编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 35
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 90, 20), GetLang("类型："))
        PosX += 90
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 150), GetLangArr(["固定",
            "随机"]))
        this.TypeCon.OnEvent("Change", this.OnTypeChange.Bind(this))

        PosX := 35
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 90, 20), GetLang("时间(毫秒)："))
        PosX += 90
        this.TimeVarCon1 := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 150), [])

        PosX := 35
        PosY += 35
        this.TimeVarArrCon2 := []
        con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 90, 20), GetLang("时间(毫秒)："))
        this.TimeVarArrCon2.Push(con)
        PosX += 90
        this.TimeVarCon2 := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 150), [])
        this.TimeVarArrCon2.Push(this.TimeVarCon2)

        PosY += 40
        PosX := 110
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(320, 170)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 320, 170))
    }

    OnGuiClose() {
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnTypeChange(*) {
        showTime2 := this.TypeCon.Value == 2
        loop this.TimeVarArrCon2.Length {
            this.TimeVarArrCon2[A_Index].Visible := showTime2
        }
    }

    OnClickSureBtn() {
        if (this.SureBtnAction == "")
            return

        timeText := this.TimeVarCon1.Text
        if (IsNumber(timeText)) {
            if (IsFloat(timeText) || timeText < 0) {
                MsgBox(GetLang("请输入大于0的整数"))
                return
            }
        }

        if (this.TypeCon.Value == 2) {
            timeText := this.TimeVarCon2.Text
            if (IsNumber(timeText)) {
                if (IsFloat(timeText) || timeText < 0) {
                    MsgBox(GetLang("请输入大于0的整数"))
                    return
                }
            }

            if (IsNumber(this.TimeVarCon1.Text) && IsNumber(this.TimeVarCon2.Text)) {
                if (this.TimeVarCon1.Text >= this.TimeVarCon2.Text) {
                    MsgBox(GetLang("上面的时间需要小于下面的时间"))
                    return
                }
            }
        }

        action := this.SureBtnAction
        action(this.GetCmdStr())
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    GetCmdStr() {
        if (this.TypeCon.Value == 1) {
            return Format("{}_{}", GetLang("间隔"), this.TimeVarCon1.Text)
        }
        return Format("{}_{}~{}", GetLang("间隔"), this.TimeVarCon1.Text, this.TimeVarCon2.Text)
    }
}
