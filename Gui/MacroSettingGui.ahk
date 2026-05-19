#Requires AutoHotkey v2.0

class MacroSettingGui {
    __new() {
        this.Gui := ""
        this.OwnerHwnd := ""
        this.tableItem := ""
        this.itemIndex := ""

        this.TKTypeCon := ""
        this.StartTipCon := ""
        this.EndTipCon := ""
    }

    ShowGui(tableIndex, itemIndex) {
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

        this.Init(tableIndex, itemIndex)
    }

    Init(tableIndex, itemIndex) {
        this.tableItem := MySoftData.TableInfo[tableIndex]
        this.itemIndex := itemIndex

        this.TKTypeCon.Value := this.tableItem.ModeArr[this.itemIndex]
        this.StartTipCon.Value := this.tableItem.StartTipSoundArr[this.itemIndex]
        this.EndTipCon.Value := this.tableItem.EndTipSoundArr[this.itemIndex]
    }

    AddGui() {
        MyGui := Gui(, GetLang("宏高级设置"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 15
        PosY := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("按键类型："))
        PosX += 90
        this.TKTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w150", PosX, PosY - 3), GetLangArr(["AHK Send",
            "keybd_event", "罗技", "AHI"]))
        Con := MyGui.Add("Button", Format("x{} y{} w30 h29", PosX + 155, PosY - 4), "?")
        Con.OnEvent("Click", this.OnClickModeHelpBtn.Bind(this))

        PosX := 15
        PosY += 40
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开始提示音："))
        PosX += 90
        this.StartTipCon := MyGui.Add("DropDownList", Format("x{} y{} w150", PosX, PosY - 3), GetLangArr(["无", "触发提示",
            "循环首次提示"]))

        PosX := 15
        PosY += 40
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("结束提示音："))
        PosX += 90
        this.EndTipCon := MyGui.Add("DropDownList", Format("x{} y{} w150", PosX, PosY - 3), GetLangArr(["无", "结束提示",
            "循环结束提示"]))

        PosX := 105
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())
        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 300, 190))
    }

    OnGuiClose() {
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnClickModeHelpBtn(*) {
        str1 := GetLang("AHK Send：通用方式，适合办公软件与大多数游戏（管理员权限可以让更多游戏有效）。")
        str2 := GetLang("keybd_event：调用 Win 系统接口模拟按键，适用比较旧的软件或游戏（需管理员权限）。")
        str3 := GetLang("罗技：调用 罗技驱动 模拟按键（需管理员权限并且运行过G HUB）。")
        str4 := GetLang("AHI：调用 Interception 驱动模拟按键（需安装 Interception 驱动）。")
        str5 := GetLang("Tip:罗技的鼠标功能需要使用旧G HUB版本（2022.2.1154及以前版本）") "`n" GetLang(
            "Tip:AHI驱动需要安装Interception驱动并以管理员权限运行")
        str6 := GetLang("**keybd_event、罗技、AHI 的按键可以作为宏的触发按键，切勿自己触发自己导致死循环**")

        str := Format("{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6)
        MsgBox(str)
    }

    OnSureBtnClick() {
        this.tableItem.ModeArr[this.itemIndex] := this.TKTypeCon.Value
        this.tableItem.StartTipSoundArr[this.itemIndex] := this.StartTipCon.Value
        this.tableItem.EndTipSoundArr[this.itemIndex] := this.EndTipCon.Value
        this.OnGuiClose()
    }
}
