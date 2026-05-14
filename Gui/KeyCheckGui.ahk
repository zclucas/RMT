#Requires AutoHotkey v2.0

class KeyCheckGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.OwnerHwnd := ""

        this.CheckedArr := []
        this.ConMap := Map()
        this.ConHwndMap := Map()

        this.MouseMoveAction := this.OnMouseMove.Bind(this)
        this.HoverCon := ""

        this.SelectColor := "Background19c930"
        this.UnSelectColor := "-Background"
        this.SelectHoverColor := "Background169727"
        this.UnSelectHoverColor := "Backgrounddadada"
    }

    OnSureHotkey() {
        triggerKey := this.HotkeyCon.Value
        triggerKey := StrReplace(triggerKey, ",", "逗号")
        triggerKey := StrReplace(triggerKey, "Insert", "Ins")
        this.RefreshCheckCon(triggerKey)
        this.Refresh()
    }

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

    GetTriggerKey() {
        triggerKey := ""
        for index, value in this.CheckedArr {
            triggerKey .= value "⎖"
        }
        triggerKey := RTrim(triggerKey, "⎖")
        return triggerKey
    }

    OnSureBtnClick() {
        this.UpdateCommandStr()
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveKeyCheckData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.ToggleFunc(false)

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

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("按键检测"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosY := 10
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 1240, 450), GetLang("请从下面按钮中选择要检测的按键："))
        PosX := 20
        PosY += 20
        {

            MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 25), GetLang("键盘"))
            PosX := 20
            PosY += 20
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
            con.OnEvent("Click", (*) => this.OnCheckedKey(","))
            this.ConMap.Set(",", con)

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

            PosY += 30
            PosX := 20
            MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 25), GetLang("鼠标"))

            PosY += 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("左键"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("LButton"))
            this.ConMap.Set("LButton", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("中键"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("MButton"))
            this.ConMap.Set("MButton", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("右键"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("RButton"))
            this.ConMap.Set("RButton", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("下滚轮"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("WheelDown"))
            this.ConMap.Set("WheelDown", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("上滚轮"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("WheelUp"))
            this.ConMap.Set("WheelUp", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("滚轮左键"
            ))
            con.OnEvent("Click", (*) => this.OnCheckedKey("WheelLeft"))
            this.ConMap.Set("WheelLeft", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("滚轮右键"
            ))
            con.OnEvent("Click", (*) => this.OnCheckedKey("WheelRight"))
            this.ConMap.Set("WheelRight", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("侧键1"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("XButton1"))
            this.ConMap.Set("XButton1", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("侧键2"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("XButton2"))
            this.ConMap.Set("XButton2", con)

            PosY += 30
            PosX := 20
            MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 25), GetLang("手柄-按键"))
            PosY += 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "A")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyA"))
            this.ConMap.Set("JoyA", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "B")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyB"))
            this.ConMap.Set("JoyB", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "X")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyX"))
            this.ConMap.Set("JoyX", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Y")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyY"))
            this.ConMap.Set("JoyY", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LB")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyLB"))
            this.ConMap.Set("JoyLB", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RB")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyRB"))
            this.ConMap.Set("JoyRB", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LT")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyLT"))
            this.ConMap.Set("JoyLT", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RT")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyRT"))
            this.ConMap.Set("JoyRT", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LS")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyLS"))
            this.ConMap.Set("JoyLS", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RS")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyRS"))
            this.ConMap.Set("JoyRS", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Back")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyBack"))
            this.ConMap.Set("JoyBack", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "Start")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyStart"))
            this.ConMap.Set("JoyStart", con)

            PosY += 30
            PosX := 20
            MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 25), GetLang("手柄-方向键、摇杆"))
            PosY += 20
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("上"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyDpadUp"))
            this.ConMap.Set("JoyDpadUp", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("下"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyDpadDown"))
            this.ConMap.Set("JoyDpadDown", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("左"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyDpadLeft"))
            this.ConMap.Set("JoyDpadLeft", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), GetLang("右"))
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyDpadRight"))
            this.ConMap.Set("JoyDpadRight", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LXMin")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisLXMin"))
            this.ConMap.Set("JoyAxisLXMin", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LXMax")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisLXMax"))
            this.ConMap.Set("JoyAxisLXMax", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LYMin")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisLYMin"))
            this.ConMap.Set("JoyAxisLYMin", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "LYMax")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisLYMax"))
            this.ConMap.Set("JoyAxisLYMax", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RXMin")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisRXMin"))
            this.ConMap.Set("JoyAxisRXMin", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RXMax")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisRXMax"))
            this.ConMap.Set("JoyAxisRXMax", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RYMin")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisRYMin"))
            this.ConMap.Set("JoyAxisRYMin", con)

            PosX += 75
            con := MyGui.Add("Text", Format("x{} y{} w{} h{} Border Center +0x200", PosX, PosY, 60, 25), "RYMax")
            con.OnEvent("Click", (*) => this.OnCheckedKey("JoyAxisRYMax"))
            this.ConMap.Set("JoyAxisRYMax", con)
        }

        PosY += 60
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("检测模式:"))
        PosX += 80
        this.CheckTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} h{}", PosX, PosY - 3, 120, 100), GetLangArr([
            "同时按下",
            "有一个按下"]))
        this.CheckTypeCon.Value := 1
        this.CheckTypeCon.OnEvent("Change", (*) => this.Refresh())

        PosX += 200
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("检测类型:"))
        PosX += 80
        this.StateTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} h{}", PosX, PosY - 3, 120, 100), GetLangArr([
            "物理状态",
            "逻辑状态"]))
        this.StateTypeCon.Value := 1
        this.StateTypeCon.OnEvent("Change", (*) => this.Refresh())

        PosX := 20
        PosY += 40
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 400, 75), GetLang("结果保存"))

        PosY += 22
        PosX := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))
        PosX += 50
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("变量名"))
        PosX += 130
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("真值"))
        PosX += 85
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("假值"))

        PosY += 25
        PosX := 25
        this.SaveToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.SaveToggleCon.Value := 1
        this.VarNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.TrueValueCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 165, PosY - 4, 70), "1")
        this.FalseValueCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 250, PosY - 4, 70), "0")

        PosY += 50
        PosX := 300
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("清空"))
        btnCon.OnEvent("Click", (*) => this.ClearCheckedArr())

        PosX += 450
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnSureBtnClick())
        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 1280, 665))
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

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("按键检测")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        this.KeyStr := ""
        if (this.Data.KeyArr.Length > 0) {
            for k in this.Data.KeyArr
                this.KeyStr .= k "⎖"
            this.KeyStr := RTrim(this.KeyStr, "⎖")
        }
        if (cmdArr.Length >= 2)
            this.KeyStr := cmdArr[2]
        this.CheckTypeCon.Value := this.Data.CheckType ? this.Data.CheckType : 1
        this.StateTypeCon.Value := this.Data.StateType ? this.Data.StateType : 1
        this.SaveToggleCon.Value := this.Data.SaveToggle != "" ? this.Data.SaveToggle : true
        this.VarNameCon.Delete()
        this.VarNameCon.Add(this.DLVariableArr)
        this.VarNameCon.Text := this.Data.VarName != "" ? this.Data.VarName : "Var1"
        this.TrueValueCon.Value := this.Data.TrueValue != "" ? this.Data.TrueValue : "1"
        this.FalseValueCon.Value := this.Data.FalseValue != "" ? this.Data.FalseValue : "0"

        this.RefreshCheckCon(this.KeyStr)
    }

    RefreshCheckCon(KeyArrStr) {
        this.CheckedArr := GetPressKeyArr(KeyArrStr)

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

    ToggleFunc(state) {
        WM_MOUSEMOVE := 0x200
        if (state) {
            OnMessage(WM_MOUSEMOVE, this.MouseMoveAction)
        }
        else {
            OnMessage(WM_MOUSEMOVE, this.MouseMoveAction, 0)
        }
    }

    CheckIfValid() {
        if (this.KeyStr == "") {
            MsgBox(GetLang("请选择要检测的按键！"))
            return false
        }

        varName := Trim(this.VarNameCon.Text)
        if (varName == "") {
            MsgBox(GetLang("请输入变量名！"))
            return false
        }

        return true
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        return CommandStr
    }

    SaveKeyCheckData() {
        data := this.Data
        data.KeyArr := this.CheckedArr.Clone()
        data.CheckType := this.CheckTypeCon.Value
        data.StateType := this.StateTypeCon.Value
        data.SaveToggle := this.SaveToggleCon.Value
        data.VarName := GetVarName(this.VarNameCon.Text)
        data.TrueValue := this.TrueValueCon.Value
        data.FalseValue := this.FalseValueCon.Value

        if (data.SaveToggle)
            MySoftData.GlobalVariMap[data.VarName] := true

        SaveMacroCMDData(data)
    }

    UpdateCommandStr() {
        checkTypeStr := this.CheckTypeCon.Value == 1 ? "1" : "2"
        stateTypeStr := this.StateTypeCon.Value == 1 ? "1" : "2"
        CommandStr := GetLang("按键检测")
        CommandStr .= "_" this.KeyStr
        CommandStr .= "_" checkTypeStr
        CommandStr .= "_" stateTypeStr
        CommandStr .= "_" this.VarNameCon.Text
        CommandStr .= "_" this.TrueValueCon.Value
        CommandStr .= "_" this.FalseValueCon.Value

        this.CommandStr := CommandStr
    }

    Refresh() {
        this.KeyStr := this.GetTriggerKey()
        this.UpdateCommandStr()
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