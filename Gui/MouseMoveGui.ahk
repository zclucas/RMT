#Requires AutoHotkey v2.0

class MouseMoveGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.PosAction := () => this.RefreshMousePos()

        this.PosXCon := ""
        this.PosYCon := ""
        this.SpeedCon := ""
        this.IsRelativeCon := ""
        this.IsRawInputCon := ""
        this.CommandStrCon := ""
        this.MousePosCon := ""
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
        MyGui := Gui(, this.ParentTile GetLang("移动编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 20), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 120
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), GetLang("F1:选取当前坐标"))

        PosX += 200
        Con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("定位取色器"))
        Con.OnEvent("Click", this.OnClickTargeterBtn.Bind(this))
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX + 102, PosY), "?")
        Con.OnEvent("Click", this.OnClickTargeterHelpBtn.Bind(this))

        PosX := 10
        PosY += 30
        this.MousePosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 380, 20), GetLang("当前鼠标位置:0,0"))

        PosY += 30
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("坐标位置X:"))
        PosX += 80
        this.PosXCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 70))
        this.PosXCon.OnEvent("Change", (*) => this.OnChangeEditValue())

        PosX += 120
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("坐标位置Y:"))
        PosX += 80
        this.PosYCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 70))
        this.PosYCon.OnEvent("Change", (*) => this.OnChangeEditValue())

        PosY += 40
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("移动速度："))
        PosX += 80
        this.SpeedCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 70), "90")
        this.SpeedCon.OnEvent("Change", (*) => this.OnChangeEditValue())

        PosX += 120
        this.IsRelativeCon := MyGui.Add("Checkbox", Format("x{} y{} w{} h{}", PosX, PosY, 100, 20), GetLang("相对位移"))
        this.IsRelativeCon.OnEvent("Click", (*) => this.OnChangeEditValue())

        PosX += 110
        this.IsRawInputCon := MyGui.Add("Checkbox", Format("x{} y{} w{} h{}", PosX, PosY, 100, 20), GetLang("原始输入"))
        this.IsRawInputCon.OnEvent("Click", (*) => this.OnChangeEditValue())

        PosY += 25
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 350), GetLang("移动速度0~100，100为瞬移"))

        PosY += 40
        PosX := 10
        this.CommandStrCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 350), GetLang("当前指令：移动"))

        PosY += 25
        PosX += 150
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 500, 280))
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
        PosX := cmdArr.Length >= 2 ? cmdArr[2] : 0
        PosY := cmdArr.Length >= 3 ? cmdArr[3] : 0
        Speed := cmdArr.Length >= 4 ? cmdArr[4] : 90
        IsRelative := cmdArr.Length >= 5 ? cmdArr[5] : 0
        IsRawInput := cmdArr.Length >= 6 ? cmdArr[6] : (ToolCheckInfo.RecordMouseRawInput ? 1 : 0)

        this.PosXCon.Value := PosX
        this.PosYCon.Value := PosY
        this.SpeedCon.Value := Speed
        this.IsRelativeCon.Value := IsRelative
        this.IsRawInputCon.Value := IsRawInput
        this.UpdateCommandStr()
    }

    CheckIfValid() {
        if (!IsNumber(this.PosXCon.Value)) {
            MsgBox(GetLang("坐标X请输入数字"))
            return false
        }

        if (!IsNumber(this.PosYCon.Value)) {
            MsgBox(GetLang("坐标Y请输入数字"))
            return false
        }

        if (!IsInteger(this.SpeedCon.Value)) {
            MsgBox(GetLang("移动速度请输入整数"))
            return false
        }

        return true
    }

    UpdateCommandStr() {
        showRelative := this.IsRelativeCon.Value == 1
        showRawInput := this.IsRawInputCon.Value == 1
        showSpeed := true

        CommandStr := GetLang("移动")
        CommandStr .= "_" this.PosXCon.Value
        CommandStr .= "_" this.PosYCon.Value

        if (showSpeed) {
            CommandStr .= "_" this.SpeedCon.Value
        }
        if (showRelative) {
            CommandStr .= "_" this.IsRelativeCon.Value
        }
        if (showRawInput) {
            CommandStr .= "_" this.IsRawInputCon.Value
        }

        this.CommandStrCon.Value := CommandStr
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.SureCoord(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.SureCoord(), "Off")
        }
    }

    RefreshMousePos() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.MousePosCon.Value := Format("{}{},{}", GetLang("当前鼠标位置:"), mouseX, mouseY)
    }

    OnChangeEditValue() {
        this.UpdateCommandStr()
    }

    OnSureTarget(PosX, PosY, Color) {
        this.PosXCon.Value := PosX
        this.PosYCon.Value := PosY
        this.UpdateCommandStr()
    }

    OnClickTargeterBtn(*) {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(*) {
        str := Format("{}`n{}`n{}", "1.左键拖拽改变位置", "2.上下左右方向键微调位置", "3.左键双击或回车键关闭取色器，同时确定点位信息")
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.UpdateCommandStr()
        action := this.SureBtnAction
        action(this.CommandStrCon.Value)
        this.ToggleFunc(false)

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.UpdateCommandStr()
        OnTriggerSepcialItemMacro(this.CommandStrCon.Value)
    }

    SureCoord() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.PosXCon.Value := mouseX
        this.PosYCon.Value := mouseY
        this.UpdateCommandStr()
    }

}
