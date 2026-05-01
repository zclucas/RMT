#Requires AutoHotkey v2.0

class RunGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.RemarkCon := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.PathTextCon := ""
        this.MouseProNameCon := ""
        this.BackPlayCon := ""
        this.VariCon := ""
        this.VariTipCon := ""

        this.RefreshAction := () => this.RefreshProcessName()
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

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 400), GetLang("F1：确定鼠标下进程"))

        PosX := 10
        PosY += 20
        this.MouseProNameCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 380, 20), GetLang(
            "鼠标下进程名:Zone.exe"))

        PosX := 10
        PosY += 30
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("路径："))

        PosX += 40
        this.PathTextCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 350))

        PosX += 355
        btnCon := MyGui.Add("Button", Format("x{} y{}", PosX, PosY - 5), GetLang("选择文件"))
        btnCon.OnEvent("Click", (*) => this.OnClickFileSelectBtn())

        PosY += 25
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("支持类别：进程、网址、文件等等"))

        PosY += 25
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("支持文件后缀：进程名、网址、exe、txt、bat、mp4、vbs、mp3等等"))

        PosX := 10
        PosY += 25
        this.BackPlayCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 400), GetLang("后台播放mp3文件"))

        PosY += 30
        PosX := 10
        this.VariTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 150), GetLang("变量"))

        PosX += 40
        this.VariCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 3, 130), [])

        PosX += 140
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 100, 30), GetLang("追加变量名"))
        btnCon.OnEvent("Click", (*) => this.OnClickAddVarNameBtn())

        PosX += 110
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 100, 30), GetLang("追加变量值"))
        btnCon.OnEvent("Click", (*) => this.OnClickAddVarValueBtn())

        PosY += 45
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 400, 20), GetLang("路径是进程时：该进程务必属于系统软件，或者有系统变量环境"))

        PosY += 35
        PosX := 200
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 500, 335))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运行")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        this.PathTextCon.Value := this.Data.RunPath
        this.BackPlayCon.Value := this.Data.BackPlay

        DLVariableArr := GetGuiVarArr(2)
        this.VariCon.Delete()
        this.VariCon.Add(DLVariableArr)
        this.VariCon.Value := 1
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
            SetTimer this.RefreshAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.SureProcessName(), "On")
        }
        else {
            SetTimer this.RefreshAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.SureProcessName(), "Off")
        }
    }

    RefreshProcessName() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            try {
                WinPID := WinGetPID("ahk_id " winId)
                processName := ProcessGetName(WinPID)
            }
            catch {
                processName := ""
            }
            this.MouseProNameCon.Value := Format(GetLang("当前鼠标下进程名:{}"), processName)
        }
    }

    SureProcessName() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            try {
                WinPID := WinGetPID("ahk_id " winId)
                processName := ProcessGetName(WinPID)
            }
            catch {
                processName := ""
            }
            this.PathTextCon.Value := processName
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
            MsgBox(GetLang("路径不能为空！"))
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
        this.Data.BackPlay := this.BackPlayCon.Value

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
