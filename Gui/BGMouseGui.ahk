#Requires AutoHotkey v2.0

class BGMouseGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.RefreshInfoAction := () => this.RefreshInfo()

        this.CurTitleCon := ""
        this.CurPosCon := ""

        this.TargetTitleCon := ""
        this.OperateTypeCon := ""
        this.MouseTypeCon := ""
        this.PosXCon := ""
        this.PosYCon := ""
        this.PosVarXCon := ""
        this.PosVarYCon := ""
        this.ScrollVCon := ""
        this.ScrollHCon := ""
        this.ClickTimeCon := ""
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
        this.OnRefresh()
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("后台鼠标编辑器"))
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

        PosX += 80
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX + 82, PosY - 5), "?")
        Con.OnEvent("Click", (*) => this.OnClickHelpBtn())

        PosX += 120
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 25
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 500), GetLang("F1:确定信息"))

        PosX := 10
        PosY += 20
        this.CurTitleCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 450, 40), GetLang("当前窗口信息:RMT"))
        PosX := 10
        PosY += 40
        this.CurPosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 380, 20), GetLang("当前窗口坐标:0,0"))

        PosX := 10
        PosY += 30
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口信息:"))
        PosX += 80
        this.TargetTitleCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 220), "")

        PosX += 230
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 100), GetLang("编辑"))
        btnCon.OnEvent("Click", this.OnClickEditBtn.Bind(this))

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("鼠标按键:"))
        PosX += 80
        this.MouseTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 100), GetLangArr(["左键",
            "中键", "右键",
            "滚轮"]))
        this.MouseTypeCon.OnEvent("Change", (*) => this.OnRefresh())

        PosX += 150
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("操作类型:"))
        PosX += 80
        this.OperateTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 100), GetLangArr(["点击",
            "双击", "按下",
            "松开"]))

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口坐标X:"))
        PosX += 80
        this.PosVarXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 3, 100), [])

        PosX += 150
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口坐标Y:"))
        PosX += 80
        this.PosVarYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 3, 100), [])

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("垂直滚动:"))
        PosX += 80
        this.ScrollVCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 100), "")
        PosX += 150
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("水平滚动"))
        PosX += 80
        this.ScrollHCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 100), "")

        PosX := 10
        PosY += 40
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("点击时间:"))
        con.Visible := false
        PosX += 80
        this.ClickTimeCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 70), "")
        this.ClickTimeCon.Visible := false

        ; PosY += 100
        PosX := 200
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(500, 335)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 500, 335))
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("后台鼠标")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        this.TargetTitleCon.Value := this.Data.TargetTitle != "" ? this.Data.TargetTitle : this.TargetTitleCon.Value
        this.OperateTypeCon.Value := this.Data.OperateType
        this.MouseTypeCon.Value := this.Data.MouseType
        this.ClickTimeCon.Value := this.Data.ClickTime
        this.PosVarXCon.Delete()
        this.PosVarXCon.Add(GetGuiVarArr(0))
        this.PosVarXCon.Text := GetLang(this.Data.PosVarX)
        this.PosVarYCon.Delete()
        this.PosVarYCon.Add(GetGuiVarArr(0))
        this.PosVarYCon.Text := GetLang(this.Data.PosVarY)
        this.ScrollVCon.Value := this.Data.ScrollV
        this.ScrollHCon.Value := this.Data.ScrollH
    }

    OnRefresh() {
        isScroll := this.MouseTypeCon.Value == 4    ;滚轮
        this.OperateTypeCon.Enabled := !isScroll
        this.ScrollVCon.Enabled := isScroll
        this.ScrollHCon.Enabled := isScroll
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.RefreshInfoAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            SetTimer this.RefreshInfoAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    OnF1() {
        CoordMode("Mouse", "Window")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " WinID)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }
            this.TargetTitleCon.Value := title "⎖" className "⎖" process
        }

        PosArr := GetCurWinPos()
        this.PosVarXCon.Text := PosArr[1]
        this.PosVarYCon.Text := PosArr[2]
    }

    RefreshInfo() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &oriId
        PosArr := GetCurWinPos()
        try {
            this.CurPosCon.Value := GetLang("当前窗口坐标: ") PosArr[1] "," PosArr[2]
            this.CurPosCon.Value := Format("{}{},{}", GetLang("当前窗口坐标:"), PosArr[1], PosArr[2])

            title := WinGetTitle(oriId)
            className := WinGetClass(oriId)
            try {
                WinPID := WinGetPID("ahk_id " oriId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }

            this.CurTitleCon.Value := Format("{}{}⎖{}⎖{}", GetLang("当前窗口信息:"), title, className, process)
        }
    }

    OnClickEditBtn(*) {
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(this.TargetTitleCon)
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveBGMouseData()
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
        if (this.TargetTitleCon.Value == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }
        return true
    }

    TriggerMacro() {
        if (!IsNumber(this.PosVarXCon.Text) || !IsNumber(this.PosVarYCon.Text)) {
            MsgBox(GetLang("坐标中存在变量，无法在编辑器模式下执行指令"))
            return false
        }

        this.SaveBGMouseData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    SaveBGMouseData() {
        this.Data.TargetTitle := this.TargetTitleCon.Value
        this.Data.OperateType := this.OperateTypeCon.Value
        this.Data.MouseType := this.MouseTypeCon.Value
        this.Data.PosVarX := GetLangKey(this.PosVarXCon.Text)
        this.Data.PosVarY := GetLangKey(this.PosVarYCon.Text)
        this.Data.ClickTime := this.ClickTimeCon.Value
        this.Data.ScrollV := this.ScrollVCon.Value
        this.Data.ScrollH := this.ScrollHCon.Value

        SaveMacroCMDData(this.Data)
    }

    OnClickHelpBtn() {
        str1 := GetLang("该指令需要管理员身份运行软件")
        str2 := GetLang("该指令部分窗口可能无效")
        str3 := GetLang("tip1:可通过对浏览器界面配置检测指令的正确性")
        str4 := GetLang("tip2:若浏览器界面正常，实际窗口无效，那就是该窗口不支持后台功能")

        str := Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
        MsgBox(str, GetLang("后台操作说明"))
    }
}
