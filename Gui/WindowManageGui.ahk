#Requires AutoHotkey v2.0
#Include WinRuleGui.ahk

class WindowManageGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.MyFrontInfoGui := ""

        this.ActionTypeArr := [
            GetLang("激活窗口"), GetLang("最大化窗口"), GetLang("最小化窗口"), GetLang("还原窗口"), GetLang("关闭窗口"),
            GetLang("移动窗口"), GetLang("调整大小"), GetLang("置顶窗口"), GetLang("取消置顶"), GetLang("修改标题"),
            GetLang("修改透明度")
        ]
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
        this.OnActionChange()
        this.ToggleFunc(true)
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVariableArr := GetGuiVarArr()
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("窗口管理")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        this.ActionTypeCon.Text := this.Data.ActionType
        SetDLConValue(this.PosXCon, DLVariableArr, this.Data.PosX)
        SetDLConValue(this.PosYCon, DLVariableArr, this.Data.PosY)
        SetDLConValue(this.WidthCon, DLVariableArr, this.Data.Width)
        SetDLConValue(this.HeightCon, DLVariableArr, this.Data.Height)
        SetDLConValue(this.NewTitleCon, DLVariableArr, this.Data.NewTitle)
        SetDLConValue(this.TransparencyCon, DLVariableArr, this.Data.Transparency)
        this.TransparencyCon.Add(["0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"])
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("窗口管理编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

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

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("操作类型："))
        PosX += 80
        this.ActionTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w130 R10", PosX, PosY - 3), this.ActionTypeArr)
        this.ActionTypeCon.OnEvent("Change", this.OnActionChange.Bind(this))

        PosX := 10
        PosY += 35
        this.WinInfoConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口信息:"))
        this.WinInfoConArr.Push(con)
        PosX += 80
        this.SearchValueCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 370), "")
        this.WinInfoConArr.Push(this.SearchValueCon)
        PosX += 380
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 4, 50, 29), GetLang("编辑"))
        btnCon.OnEvent("Click", this.OnClickWinEditBtn.Bind(this))
        this.WinInfoConArr.Push(btnCon)

        PosX := 10
        PosY += 35
        SplitPosY := PosY
        this.PosRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("坐标X："))
        this.PosRelateArrCon.Push(con)
        PosX += 80
        this.PosXCon := MyGui.Add("ComboBox", Format("x{} y{} w130 R8", PosX, PosY - 3), [])
        this.PosRelateArrCon.Push(this.PosXCon)

        PosX := 250
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("坐标Y："))
        this.PosRelateArrCon.Push(con)
        PosX += 80
        this.PosYCon := MyGui.Add("ComboBox", Format("x{} y{} w130 R8", PosX, PosY - 3), [])
        this.PosRelateArrCon.Push(this.PosYCon)

        PosX := 10
        PosY := SplitPosY
        this.SizeRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("宽度："))
        this.SizeRelateArrCon.Push(con)
        PosX += 80
        this.WidthCon := MyGui.Add("ComboBox", Format("x{} y{} w130 R8", PosX, PosY - 3), [])
        this.SizeRelateArrCon.Push(this.WidthCon)

        PosX := 250
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("高度："))
        this.SizeRelateArrCon.Push(con)
        PosX += 80
        this.HeightCon := MyGui.Add("ComboBox", Format("x{} y{} w130 R8", PosX, PosY - 3), [])
        this.SizeRelateArrCon.Push(this.HeightCon)

        PosX := 10
        PosY := SplitPosY
        this.TitleRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("新标题："))
        this.TitleRelateArrCon.Push(con)
        PosX += 80
        this.NewTitleCon := MyGui.Add("ComboBox", Format("x{} y{} w370 R8", PosX, PosY - 3), [])
        this.TitleRelateArrCon.Push(this.NewTitleCon)

        PosX := 10
        PosY := SplitPosY
        this.TransparencyRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("透明度："))
        this.TransparencyRelateArrCon.Push(con)
        PosX += 80
        this.TransparencyCon := MyGui.Add(
            "ComboBox",
            Format("x{} y{} w130 R8", PosX, PosY - 3),
            []
        )
        this.TransparencyRelateArrCon.Push(this.TransparencyCon)

        PosY := SplitPosY + 42
        PosX := 220
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnClickSureBtn())
        MyGui.OnEvent("Close", (*) => this.OnClose())
        pos := GetCenterPosOnActiveMonitor(530, 215)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 530, 215))
    }

    OnActionChange(*) {
        actionType := this.ActionTypeCon.Text
        isShowPos := (actionType == GetLang("移动窗口"))
        isShowSize := (actionType == GetLang("调整大小"))
        isShowTitle := (actionType == GetLang("修改标题"))
        isShowTransparency := (actionType == GetLang("修改透明度"))

        for _, con in this.PosRelateArrCon
            con.Visible := isShowPos

        for _, con in this.SizeRelateArrCon
            con.Visible := isShowSize

        for _, con in this.TitleRelateArrCon
            con.Visible := isShowTitle

        for _, con in this.TransparencyRelateArrCon
            con.Visible := isShowTransparency
    }

    OnClose(*) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnClickSureBtn() {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        this.ToggleFunc(false)
        CommandStr := this.GetCommandStr()
        this.SureBtnAction.Call(CommandStr)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.OnClose()
    }

    CheckIfValid() {
        actionType := this.ActionTypeCon.Text
        if (this.SearchValueCon.Value == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (actionType == GetLang("修改标题")) {
            if (this.NewTitleCon.Value == "") {
                MsgBox(GetLang("新标题不能为空！"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }

        return true
    }

    SaveData() {
        this.Data.ActionType := GetLangKey(this.ActionTypeCon.Text)
        this.Data.SearchValue := this.SearchValueCon.Value
        this.Data.PosX := this.PosXCon.Value
        this.Data.PosY := this.PosYCon.Value
        this.Data.Width := this.WidthCon.Value
        this.Data.Height := this.HeightCon.Value
        this.Data.NewTitle := this.NewTitleCon.Text
        this.Data.Transparency := StrReplace(this.TransparencyCon.Text, "%")
        SaveMacroCMDData(this.Data)
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

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    TriggerMacro() {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)
    }

    OnClickWinEditBtn(*) {
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(this.SearchValueCon)
    }
}
