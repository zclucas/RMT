#Requires AutoHotkey v2.0

class BGKeyGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.OwnerHwnd := ""

        this.SerialStr := ""
        this.Data := ""

        this.HotkeyCon := ""
        this.FrontCon := ""
        this.RemarkCon := ""
        this.CheckedArr := []
        this.ConMap := Map()
        this.ConHwndMap := Map()

        this.TriggerAction := (*) => this.TriggerMacro()
        this.MouseMoveAction := this.OnMouseMove.Bind(this)
        this.HoverCon := ""

        this.SelectColor := "Background19c930"
        this.UnSelectColor := "-Background"
        this.SelectHoverColor := "Background169727"
        this.UnSelectHoverColor := "Backgrounddadada"
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
            for key, value in this.ConMap {
                this.ConHwndMap.Set(value.Hwnd, value)
            }
        }

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.Init(cmd)
        this.Refresh()
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("后台按键编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 20
        PosY := 10
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 25), "F1")
        con.Enabled := false

        PosX += 30
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("模拟指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 200
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("键盘按键检测："))

        PosX += 120
        this.HotkeyCon := MyGui.Add("Hotkey", Format("x{} y{} w140", PosX, PosY - 3))

        PosX += 150
        con := MyGui.Add("Button", Format("x{} y{}", PosX, PosY - 5), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureHotkey())

        PosX += 90
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口信息:"))
        PosX += 75
        this.FrontCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 190), "")

        PosX += 200
        btnCon := MyGui.Add("Button", Format("x{} y{}", PosX, PosY - 5), GetLang("编辑"))
        btnCon.OnEvent("Click", this.OnClickEditBtn.Bind(this))

        PosX += 100
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 30
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 1230, 265), GetLang("请从下面按钮中选择按键："))
        PosX := 20
        PosY += 20
        {
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 40, 25), "Esc")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Esc"))
            this.ConMap.Set("Esc", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F1")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F1"))
            this.ConMap.Set("F1", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F2")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F2"))
            this.ConMap.Set("F2", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F3")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F3"))
            this.ConMap.Set("F3", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F4")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F4"))
            this.ConMap.Set("F4", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F5")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F5"))
            this.ConMap.Set("F5", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F6")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F6"))
            this.ConMap.Set("F6", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F7")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F7"))
            this.ConMap.Set("F7", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F8")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F8"))
            this.ConMap.Set("F8", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F9")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F9"))
            this.ConMap.Set("F9", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F10")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F10"))
            this.ConMap.Set("F10", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F11")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F11"))
            this.ConMap.Set("F11", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F12")
            con.OnEvent("Click", (*) => this.OnCheckedKey("F12"))
            this.ConMap.Set("F12", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "PrtScr")
            con.OnEvent("Click", (*) => this.OnCheckedKey("PrintScreen"))
            this.ConMap.Set("PrintScreen", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "Scroll")
            con.OnEvent("Click", (*) => this.OnCheckedKey("ScrollLock"))
            this.ConMap.Set("ScrollLock", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "Pause")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Pause"))
            this.ConMap.Set("Pause", con)

            PosY += 30
            PosX := 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "~")
            con.OnEvent("Click", (*) => this.OnCheckedKey("``"))
            this.ConMap.Set("``", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "1")
            con.OnEvent("Click", (*) => this.OnCheckedKey("1"))
            this.ConMap.Set("1", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "2")
            con.OnEvent("Click", (*) => this.OnCheckedKey("2"))
            this.ConMap.Set("2", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "3")
            con.OnEvent("Click", (*) => this.OnCheckedKey("3"))
            this.ConMap.Set("3", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "4")
            con.OnEvent("Click", (*) => this.OnCheckedKey("4"))
            this.ConMap.Set("4", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "5")
            con.OnEvent("Click", (*) => this.OnCheckedKey("5"))
            this.ConMap.Set("5", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "6")
            con.OnEvent("Click", (*) => this.OnCheckedKey("6"))
            this.ConMap.Set("6", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "7")
            con.OnEvent("Click", (*) => this.OnCheckedKey("7"))
            this.ConMap.Set("7", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "8")
            con.OnEvent("Click", (*) => this.OnCheckedKey("8"))
            this.ConMap.Set("8", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "9")
            con.OnEvent("Click", (*) => this.OnCheckedKey("9"))
            this.ConMap.Set("9", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "0")
            con.OnEvent("Click", (*) => this.OnCheckedKey("0"))
            this.ConMap.Set("0", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "-")
            con.OnEvent("Click", (*) => this.OnCheckedKey("-"))
            this.ConMap.Set("-", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "=")
            con.OnEvent("Click", (*) => this.OnCheckedKey("="))
            this.ConMap.Set("=", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 85, 25), "Backspace")
            con.OnEvent("Click", (*) => this.OnCheckedKey("BS"))
            this.ConMap.Set("BS", con)

            PosX += 125
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "Ins")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Ins"))
            this.ConMap.Set("Ins", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "Home")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Home"))
            this.ConMap.Set("Home", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "PgUp")
            con.OnEvent("Click", (*) => this.OnCheckedKey("PgUp"))
            this.ConMap.Set("PgUp", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "Num")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumLock"))
            this.ConMap.Set("NumLock", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "/")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumpadDiv"))
            this.ConMap.Set("NumpadDiv", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "*")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumpadMult"))
            this.ConMap.Set("NumpadMult", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "-")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumpadSub"))
            this.ConMap.Set("NumpadSub", con)

            PosY += 30
            PosX := 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Tab")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Tab"))
            this.ConMap.Set("Tab", con)

            PosX += 80
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "Q")
            con.OnEvent("Click", (*) => this.OnCheckedKey("q"))
            this.ConMap.Set("q", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "W")
            con.OnEvent("Click", (*) => this.OnCheckedKey("w"))
            this.ConMap.Set("w", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "E")
            con.OnEvent("Click", (*) => this.OnCheckedKey("e"))
            this.ConMap.Set("e", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "R")
            con.OnEvent("Click", (*) => this.OnCheckedKey("r"))
            this.ConMap.Set("r", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "T")
            con.OnEvent("Click", (*) => this.OnCheckedKey("t"))
            this.ConMap.Set("t", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "Y")
            con.OnEvent("Click", (*) => this.OnCheckedKey("y"))
            this.ConMap.Set("y", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "U")
            con.OnEvent("Click", (*) => this.OnCheckedKey("u"))
            this.ConMap.Set("u", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "I")
            con.OnEvent("Click", (*) => this.OnCheckedKey("i"))
            this.ConMap.Set("i", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "O")
            con.OnEvent("Click", (*) => this.OnCheckedKey("o"))
            this.ConMap.Set("o", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "P")
            con.OnEvent("Click", (*) => this.OnCheckedKey("p"))
            this.ConMap.Set("p", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "[")
            con.OnEvent("Click", (*) => this.OnCheckedKey("["))
            this.ConMap.Set("[", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "]")
            con.OnEvent("Click", (*) => this.OnCheckedKey("]"))
            this.ConMap.Set("]", con)

            PosX += 55
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 50, 25), "\")
            con.OnEvent("Click", (*) => this.OnCheckedKey("\"))
            this.ConMap.Set("\", con)

            PosX += 90
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "Del")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Del"))
            this.ConMap.Set("Del", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "End")
            con.OnEvent("Click", (*) => this.OnCheckedKey("End"))
            this.ConMap.Set("End", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "PgDn")
            con.OnEvent("Click", (*) => this.OnCheckedKey("PgDn"))
            this.ConMap.Set("PgDn", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "7")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad7"))
            this.ConMap.Set("Numpad7", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "8")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad8"))
            this.ConMap.Set("Numpad8", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "9")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad9"))
            this.ConMap.Set("Numpad9", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "+")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumpadAdd"))
            this.ConMap.Set("NumpadAdd", con)

            PosY += 30
            PosX := 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 75, 25), "CapsLock")
            con.OnEvent("Click", (*) => this.OnCheckedKey("CapsLock"))
            this.ConMap.Set("CapsLock", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "A")
            con.OnEvent("Click", (*) => this.OnCheckedKey("a"))
            this.ConMap.Set("a", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "S")
            con.OnEvent("Click", (*) => this.OnCheckedKey("s"))
            this.ConMap.Set("s", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "D")
            con.OnEvent("Click", (*) => this.OnCheckedKey("d"))
            this.ConMap.Set("d", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "F")
            con.OnEvent("Click", (*) => this.OnCheckedKey("f"))
            this.ConMap.Set("f", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "G")
            con.OnEvent("Click", (*) => this.OnCheckedKey("g"))
            this.ConMap.Set("g", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "H")
            con.OnEvent("Click", (*) => this.OnCheckedKey("h"))
            this.ConMap.Set("h", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "J")
            con.OnEvent("Click", (*) => this.OnCheckedKey("j"))
            this.ConMap.Set("j", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "K")
            con.OnEvent("Click", (*) => this.OnCheckedKey("k"))
            this.ConMap.Set("k", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "L")
            con.OnEvent("Click", (*) => this.OnCheckedKey("l"))
            this.ConMap.Set("l", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), ";")
            con.OnEvent("Click", (*) => this.OnCheckedKey(";"))
            this.ConMap.Set(";", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "'")
            con.OnEvent("Click", (*) => this.OnCheckedKey("'"))
            this.ConMap.Set("'", con)

            PosX += 60
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 75, 25), "Enter")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Enter"))
            this.ConMap.Set("Enter", con)

            PosX += 365
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "4")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad4"))
            this.ConMap.Set("Numpad4", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "5")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad5"))
            this.ConMap.Set("Numpad5", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "6")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad6"))
            this.ConMap.Set("Numpad6", con)

            PosY += 30
            PosX := 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 85, 25), "LShift")
            con.OnEvent("Click", (*) => this.OnCheckedKey("LShift"))
            this.ConMap.Set("LShift", con)

            PosX += 110
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "Z")
            con.OnEvent("Click", (*) => this.OnCheckedKey("z"))
            this.ConMap.Set("z", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "X")
            con.OnEvent("Click", (*) => this.OnCheckedKey("x"))
            this.ConMap.Set("x", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "C")
            con.OnEvent("Click", (*) => this.OnCheckedKey("c"))
            this.ConMap.Set("c", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "V")
            con.OnEvent("Click", (*) => this.OnCheckedKey("v"))
            this.ConMap.Set("v", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "B")
            con.OnEvent("Click", (*) => this.OnCheckedKey("b"))
            this.ConMap.Set("b", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "N")
            con.OnEvent("Click", (*) => this.OnCheckedKey("n"))
            this.ConMap.Set("n", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "M")
            con.OnEvent("Click", (*) => this.OnCheckedKey("m"))
            this.ConMap.Set("m", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), ",")
            con.OnEvent("Click", (*) => this.OnCheckedKey("逗号"))
            this.ConMap.Set("逗号", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), ".")
            con.OnEvent("Click", (*) => this.OnCheckedKey("."))
            this.ConMap.Set(".", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "/")
            con.OnEvent("Click", (*) => this.OnCheckedKey("/"))
            this.ConMap.Set("/", con)

            PosX += 90
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 85, 25), "RShift")
            con.OnEvent("Click", (*) => this.OnCheckedKey("RShift"))
            this.ConMap.Set("RShift", con)

            PosX += 200
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "↑")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Up"))
            this.ConMap.Set("Up", con)

            PosX += 175
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "1")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad1"))
            this.ConMap.Set("Numpad1", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "2")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad2"))
            this.ConMap.Set("Numpad2", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "3")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad3"))
            this.ConMap.Set("Numpad3", con)

            PosX += 50
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "Enter")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumpadEnter"))
            this.ConMap.Set("NumpadEnter", con)

            PosY += 30
            PosX := 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LCtrl")
            con.OnEvent("Click", (*) => this.OnCheckedKey("LCtrl"))
            this.ConMap.Set("LCtrl", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LWin")
            con.OnEvent("Click", (*) => this.OnCheckedKey("LWin"))
            this.ConMap.Set("LWin", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LAlt")
            con.OnEvent("Click", (*) => this.OnCheckedKey("LAlt"))
            this.ConMap.Set("LAlt", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 210, 25), "Space")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Space"))
            this.ConMap.Set("Space", con)

            PosX += 225
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RAlt")
            con.OnEvent("Click", (*) => this.OnCheckedKey("RAlt"))
            this.ConMap.Set("RAlt", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RWin")
            con.OnEvent("Click", (*) => this.OnCheckedKey("RWin"))
            this.ConMap.Set("RWin", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "AppsKey")
            con.OnEvent("Click", (*) => this.OnCheckedKey("AppsKey"))
            this.ConMap.Set("AppsKey", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RCtrl")
            con.OnEvent("Click", (*) => this.OnCheckedKey("RCtrl"))
            this.ConMap.Set("RCtrl", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "←")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Left"))
            this.ConMap.Set("Left", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "↓")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Down"))
            this.ConMap.Set("Down", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 45, 25), "→")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Right"))
            this.ConMap.Set("Right", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "0")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Numpad0"))
            this.ConMap.Set("Numpad0", con)

            PosX += 100
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 35, 25), "Del")
            con.OnEvent("Click", (*) => this.OnCheckedKey("NumpadDot"))
            this.ConMap.Set("NumpadDot", con)

            PosY += 30
            PosX := 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Ctrl")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Ctrl"))
            this.ConMap.Set("Ctrl", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Shift")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Shift"))
            this.ConMap.Set("Shift", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Alt")
            con.OnEvent("Click", (*) => this.OnCheckedKey("Alt"))
            this.ConMap.Set("Alt", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("后退"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Back"))
            this.ConMap.Set("Browser_Back", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("前进"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Forward"))
            this.ConMap.Set("Browser_Forward", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("刷新"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Refresh"))
            this.ConMap.Set("Browser_Refresh", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("停止"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Stop"))
            this.ConMap.Set("Browser_Stop", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("搜索"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Search"))
            this.ConMap.Set("Browser_Search", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("收藏夹"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Favorites"))
            this.ConMap.Set("Browser_Favorites", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("主页"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Browser_Home"))
            this.ConMap.Set("Browser_Home", con)

            PosX += 92
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("静音"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Volume_Mute"))
            this.ConMap.Set("Volume_Mute", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("调低音量"
            ))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Volume_Down"))
            this.ConMap.Set("Volume_Down", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("增加音量"
            ))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Volume_Up"))
            this.ConMap.Set("Volume_Up", con)

            PosX += 108
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("降低亮度"
            ))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Bright_Down"))
            this.ConMap.Set("Bright_Down", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("提高亮度"
            ))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Bright_Up"))
            this.ConMap.Set("Bright_Up", con)

            PosX := 20
            PosY += 30
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("此电脑"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Launch_App1"))
            this.ConMap.Set("Launch_App1", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("计算器"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Launch_App2"))
            this.ConMap.Set("Launch_App2", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("下一首"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Media_Next"))
            this.ConMap.Set("Media_Next", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("上一首"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Media_Prev"))
            this.ConMap.Set("Media_Prev", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("停止"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Media_Stop"))
            this.ConMap.Set("Media_Stop", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 80, 25), GetLang(
                "播放/暂停"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("Media_Play_Pause"))
            this.ConMap.Set("Media_Play_Pause", con)
        }

        PosY += 55
        PosX := 240
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("类型:"))
        PosX += 50
        this.KeyTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} h{}", PosX, PosY - 3, 80, 100), GetLangArr([
            "按下",
            "松开", "点击"]))
        this.KeyTypeCon.OnEvent("Change", (*) => this.OnChangeEditValue())
        this.KeyTypeCon.Value := 1

        PosX += 130
        this.HoldTimeTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 90), GetLang("点击时长:"))
        PosX += 70
        this.HoldTimeCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50), 50)
        this.HoldTimeCon.OnEvent("Change", (*) => this.OnChangeEditValue())

        PosX += 130
        this.KeyCountTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 90), GetLang("点击次数："))
        PosX += 70
        this.KeyCountCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50), 1)
        this.KeyCountCon.OnEvent("Change", (*) => this.OnChangeEditValue())

        PosX += 130
        this.PerIntervalTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 90), GetLang("每次间隔："))
        PosX += 70
        this.PerIntervalCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50), 100)
        this.PerIntervalCon.OnEvent("Change", (*) => this.OnChangeEditValue())

        PosY += 40
        PosX := 310
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("清空"))
        btnCon.OnEvent("Click", (*) => this.ClearCheckedArr())

        PosX += 450
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnSureBtnClick())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 1260, 420))
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("后台按键")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        this.FrontCon.Value := this.Data.FrontStr != "" ? this.Data.FrontStr : this.FrontCon.Value
        this.CheckedArr := this.Data.KeyArr
        this.KeyTypeCon.Value := this.Data.type
        this.HoldTimeCon.Value := this.Data.ClickTime
        this.KeyCountCon.Value := this.Data.ClickCount
        this.PerIntervalCon.Value := this.Data.ClickInterval

        this.RefreshCheckCon()
        this.Refresh()
    }

    ToggleFunc(state) {
        WM_MOUSEMOVE := 0x200
        if (state) {
            Hotkey("F1", this.TriggerAction, "On")
            OnMessage(WM_MOUSEMOVE, this.MouseMoveAction)
        }
        else {
            Hotkey("F1", this.TriggerAction, "Off")
            OnMessage(WM_MOUSEMOVE, this.MouseMoveAction, 0)
        }
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveBGKeyData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    CheckIfValid() {
        if (this.FrontCon.Value == "" || this.FrontCon.Value == "⎖⎖⎖") {
            MsgBox(GetLang("请编辑窗口信息"))
            return false
        }

        if (this.CheckedArr == "" || this.CheckedArr.Length == 0) {
            MsgBox(GetLang("请选择按键！"))
            return false
        }

        if (!IsInteger(this.KeyCountCon.Value) || Integer(this.KeyCountCon.Value) <= 0) {
            MsgBox(GetLang("按键次数必须为大于零的整数！"))
            return false
        }

        return true
    }

    Refresh() {
        isShowHoldTime := this.KeyTypeCon.Value == 3
        isShowCount := isShowHoldTime
        isShowInterval := isShowCount && this.KeyCountCon.Value != 1

        this.HoldTimeTipCon.Visible := isShowHoldTime
        this.HoldTimeCon.Visible := isShowHoldTime
        this.KeyCountTipCon.Visible := isShowCount
        this.KeyCountCon.Visible := isShowCount
        this.PerIntervalTipCon.Visible := isShowInterval
        this.PerIntervalCon.Visible := isShowInterval
    }

    RefreshCheckCon() {
        for key, value in this.ConMap {
            value.State := 0
            value.Opt(this.UnSelectColor)
            value.Redraw()
        }

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value)) {
                con := this.ConMap.Get(value)
                con.State := 1
                con.Opt(this.SelectColor)
                con.Redraw()
            }
        }
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value)) {
                con := this.ConMap.Get(value)
                con.State := 0
                con.Opt(this.UnSelectColor)
                con.Redraw()
            }
        }
        this.CheckedArr := []
        this.Refresh()
    }

    OnChangeEditValue() {
        this.Refresh()
    }

    OnSureHotkey() {
        triggerKey := this.HotkeyCon.Value
        triggerKey := StrReplace(triggerKey, ",", "逗号")
        triggerKey := StrReplace(triggerKey, "Insert", "Ins")

        this.CheckedArr := GetComboKeyArr(triggerKey)
        this.RefreshCheckCon()
        this.Refresh()
    }

    OnClickEditBtn(*) {
        MyFrontInfoGui.ShowGui(this.FrontCon)
    }

    ;选项相关
    OnCheckedKey(key) {
        isSelected := false
        arrayIndex := 0
        con := this.ConMap.Get(key)
        for index, value in this.CheckedArr {
            if (value == key) {
                isSelected := true
                arrayIndex := index
                break
            }
        }

        if (isSelected) {
            con.State := 0
            con.Opt(this.UnSelectColor)
            con.Redraw()
            this.CheckedArr.RemoveAt(arrayIndex)
        }
        else {
            con.State := 1
            con.Opt(this.SelectColor)
            con.Redraw()
            this.CheckedArr.Push(key)
        }

        this.Refresh()
    }

    ;按钮点击回调
    OnSureBtnClick() {
        isValid := this.CheckIfValid()
        if (!isValid) {
            return false
        }

        this.SaveBGKeyData()
        action := this.SureBtnAction
        action(this.GetCommandStr())

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    SaveBGKeyData() {
        this.Data.FrontStr := this.FrontCon.Value
        this.Data.KeyArr := this.CheckedArr
        this.Data.Type := this.KeyTypeCon.Value
        this.Data.ClickTime := this.HoldTimeCon.Value
        this.Data.ClickCount := this.KeyTypeCon.Value == 3 ? this.KeyCountCon.Value : 1
        this.Data.ClickInterval := this.PerIntervalCon.Value

        SaveMacroCMDData(this.Data)
    }

    OnMouseMove(wParam, lParam, msg, hwnd) {
        IsLeven := this.HoverCon != "" && !this.ConHwndMap.Has(hwnd)
        IsUpdate := this.ConHwndMap.Has(hwnd) && this.ConHwndMap.Get(hwnd) != this.HoverCon
        if ((IsLeven || IsUpdate) && this.HoverCon != "") {
            ColorStr := this.HoverCon.State ? this.SelectColor : this.UnSelectColor
            this.HoverCon.Opt(ColorStr)
            this.HoverCon.Redraw()
            this.HoverCon := IsLeven ? "" : this.ConHwndMap.Get(hwnd)
        }

        if (IsUpdate) {
            this.HoverCon := this.ConHwndMap.Get(hwnd)
            ColorStr := this.HoverCon.State ? this.SelectHoverColor : this.UnSelectHoverColor
            this.HoverCon.Opt(ColorStr)
            this.HoverCon.Redraw()
        }
    }
}
