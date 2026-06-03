#Requires AutoHotkey v2.0

class TriggerStrGui {
    __new() {
        this.Gui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.SureFocusCon := ""

        this.ConMap := Map()
        this.IsEndChar := true
        this.IsSubStr := true
        this.IsDelete := true
        this.Str := ""
        this.SaveBtnCtrl := {}
        this.showSaveBtn := false
        this.SettingTipCon := ""
        this.IsEndCharCon := {}
        this.IsSubStrCon := {}
        this.IsDeleteCon := {}
    }

    ;字串相关
    OnCharBtnClick(char) {
        this.Str .= char

        this.Refresh()
    }

    Refresh() {
        if (this.SettingTipCon == "")
            return

        tipStr := GetLang("当前配置的触发字串为：")
        tipStr .= this.GetTriggerStr()
        this.SettingTipCon.Value := tipStr
        this.IsEndCharCon.Value := this.IsEndChar
        this.IsSubStrCon.Value := this.IsSubStr
        this.IsDeleteCon.Value := this.IsDelete
        this.SaveBtnCtrl.Visible := this.showSaveBtn
    }

    GetTriggerStr() {
        triggerStr := ""

        triggerStr .= ":"
        if (this.IsSubStr) {
            triggerStr .= "?"
        }
        if (!this.IsEndChar) {
            triggerStr .= "*"
        }
        if (!this.IsDelete) {
            triggerStr .= "B0"
        }

        triggerStr .= ":"
        triggerStr .= this.Str
    
        if (this.Str == "")
            triggerStr := ""

        return triggerStr
    }

    Backspace() {
        str := SubStr(this.Str, 1, StrLen(this.Str) - 1)
        this.Str := str
        this.Refresh()
    }

    ClearStr() {
        this.Str := ""
        this.Refresh()
    }

    ;UI相关
    ShowGui(triggerKey, holdTime, IsToolEdit) {

        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        showSaveBtn := !IsToolEdit
        this.Init(triggerKey, showSaveBtn)
        this.Refresh()
    }

    AddGui() {
        {
            MyGui := Gui(, GetLang("字串触发编辑器"))
            this.Gui := MyGui
            MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)
            MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", 10, 10, 1120, 230), GetLang("请从下面字符中组合你想要触发宏的字串："))

            PosX := 20
            PosY := 40
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "1")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("1"))
            this.ConMap.Set("1", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "2")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("2"))
            this.ConMap.Set("2", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "3")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("3"))
            this.ConMap.Set("3", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "4")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("4"))
            this.ConMap.Set("4", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "5")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("5"))
            this.ConMap.Set("5", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "6")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("6"))
            this.ConMap.Set("6", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "7")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("7"))
            this.ConMap.Set("7", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "8")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("8"))
            this.ConMap.Set("8", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "9")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("9"))
            this.ConMap.Set("9", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "0")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("0"))
            this.ConMap.Set("0", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "+")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("+"))
            this.ConMap.Set("+", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "-")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("-"))
            this.ConMap.Set("-", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "*")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("*"))
            this.ConMap.Set("*", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "/")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("/"))
            this.ConMap.Set("/", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "=")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("="))
            this.ConMap.Set("=", con)

            PosY += 40
            PosX := 20
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "!")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("!"))
            this.ConMap.Set("!", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "@")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("@"))
            this.ConMap.Set("@", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "#")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("#"))
            this.ConMap.Set("#", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "$")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("$"))
            this.ConMap.Set("$", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "%")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("%"))
            this.ConMap.Set("%", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "^")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("^"))
            this.ConMap.Set("^", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "(")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("("))
            this.ConMap.Set("(", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), ")")
            con.OnEvent("Click", (*) => this.OnCharBtnClick(")"))
            this.ConMap.Set(")", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "<")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("<"))
            this.ConMap.Set("<", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), ">")
            con.OnEvent("Click", (*) => this.OnCharBtnClick(">"))
            this.ConMap.Set(">", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "[")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("["))
            this.ConMap.Set("[", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "]")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("]"))
            this.ConMap.Set("]", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "{")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("{"))
            this.ConMap.Set("{", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "}")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("}"))
            this.ConMap.Set("}", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "|")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("|"))
            this.ConMap.Set("|", con)

            PosY += 40
            PosX := 20
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "Q")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("Q"))
            this.ConMap.Set("Q", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "W")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("W"))
            this.ConMap.Set("W", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "E")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("E"))
            this.ConMap.Set("E", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "R")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("R"))
            this.ConMap.Set("R", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "T")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("T"))
            this.ConMap.Set("T", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "Y")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("Y"))
            this.ConMap.Set("Y", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "U")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("U"))
            this.ConMap.Set("U", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "I")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("I"))
            this.ConMap.Set("I", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "O")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("O"))
            this.ConMap.Set("O", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "P")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("P"))
            this.ConMap.Set("P", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "?")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("?"))
            this.ConMap.Set("?", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "_")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("_"))
            this.ConMap.Set("_", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), ";")
            con.OnEvent("Click", (*) => this.OnCharBtnClick(";"))
            this.ConMap.Set(";", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), ",")
            con.OnEvent("Click", (*) => this.OnCharBtnClick(","))
            this.ConMap.Set(",", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), ".")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("."))
            this.ConMap.Set(".", con)

            PosY += 40
            PosX := 20
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "A")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("A"))
            this.ConMap.Set("A", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "S")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("S"))
            this.ConMap.Set("S", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "D")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("D"))
            this.ConMap.Set("D", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "F")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("F"))
            this.ConMap.Set("F", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "G")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("G"))
            this.ConMap.Set("G", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "H")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("H"))
            this.ConMap.Set("H", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "J")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("J"))
            this.ConMap.Set("J", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "K")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("K"))
            this.ConMap.Set("K", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "L")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("L"))
            this.ConMap.Set("L", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "'")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("'"))
            this.ConMap.Set("'", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "`"")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("`""))
            this.ConMap.Set("`"", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "\")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("\"))
            this.ConMap.Set("\", con)

            PosY += 40
            PosX := 20
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "Z")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("Z"))
            this.ConMap.Set("Z", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "X")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("X"))
            this.ConMap.Set("X", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "C")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("C"))
            this.ConMap.Set("C", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "V")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("V"))
            this.ConMap.Set("V", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "B")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("B"))
            this.ConMap.Set("B", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "N")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("N"))
            this.ConMap.Set("N", con)

            PosX += 75
            con := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 45), "M")
            con.OnEvent("Click", (*) => this.OnCharBtnClick("M"))
            this.ConMap.Set("M", con)

        }

        PosY += 50
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{} h{} w{}", PosX, PosY, 20, 120), GetLang("终止符"))
        con.OnEvent("Click", (*) => this.OnClickNoEndCharCon())
        this.IsEndCharCon := con

        PosX += 200
        con := MyGui.Add("Checkbox", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("允许子字串"))
        con.OnEvent("Click", (*) => this.OnClickSubStrCon())
        this.IsSubStrCon := con

        PosX += 200
        con := MyGui.Add("Checkbox", Format("x{} y{} h{} w{}", PosX, PosY, 20, 150), GetLang("删除触发字串"))
        con.OnEvent("Click", (*) => this.OnClickNoDeleteCon())
        this.IsDeleteCon := con

        PosY += 40
        PosX := 20
        con := MyGui.Add("Text", Format("x{} y{} h{} w{}", PosX, PosY, 20, 1000),
        GetLang("终止符说明：当输入字串时，需要输入一个终止符触发。终止符包含：-()[]{}':;/\,.?! Enter Space Tab以及引号"))

        PosY += 25
        PosX := 20
        con := MyGui.Add("Text", Format("x{} y{} h{} w{}", PosX, PosY, 20, 1000),
        GetLang("子字串说明:字串在另一个单词中也会被触发,例如输入Word会触发rd、ord、word。如果非子字串,只会触发word。"))

        PosY += 25
        PosX := 20
        con := MyGui.Add("Text", Format("x{} y{} h{} w{}", PosX, PosY, 20, 1000), GetLang(
            "备注：字串长度必须大于0,但不能超过40, 鼠标点击会重置字串识别器"))

        PosY += 30
        PosX := 20
        con := MyGui.Add("Text", Format("x{} y{} h{} w{}", PosX, PosY, 20, 1000), GetLang("当前配置的触发键：无"))
        this.SettingTipCon := con

        PosY += 30
        PosX := 50
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("退格"))
        btnCon.OnEvent("Click", (*) => this.Backspace())

        PosX += 240
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("清空字串"))
        btnCon.OnEvent("Click", (*) => this.ClearStr())

        PosX += 240
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnSureBtnClick())

        PosX += 240
        this.SaveBtnCtrl := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("应用并保存"))
        this.SaveBtnCtrl.OnEvent("Click", (*) => this.OnSaveBtnClick())

        pos := GetCenterPosOnActiveMonitor(1150, 460)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 1150, 460))
    }

    ;按钮点击回调
    OnSureBtnClick() {
        isValid := this.CheckConfigValid()
        if (!isValid)
            return

        triggerStr := this.GetTriggerStr()
        action := this.SureBtnAction
        action(triggerStr)
        this.Gui.Hide()
        this.SureFocusCon.Focus()
    }

    OnSaveBtnClick() {
        isValid := this.CheckConfigValid()
        if (!isValid) 
            return

        triggerStr := this.GetTriggerStr()
        action := this.SureBtnAction
        action(triggerStr)

        action := this.SaveBtnAction
        action()
        this.Gui.Hide()
        this.SureFocusCon.Focus()
    }

    OnClickNoEndCharCon() {
        this.IsEndChar := !this.IsEndChar
        this.Refresh()
    }

    OnClickSubStrCon() {
        this.IsSubStr := !this.IsSubStr
        this.Refresh()
    }

    OnClickNoDeleteCon() {
        this.IsDelete := !this.IsDelete
        this.Refresh()
    }

    ;数据交互
    Init(triggerStr, showSaveBtn) {
        isValid := SubStr(triggerStr, 1, 1) == ":"
        splitPos := 2
        IsNoEndChar := true
        IsSubStr := true
        IsNoDelete := true
        Str := ""

        if (isValid) {
            splitPos := InStr(triggerStr, ":", false, 2)
            isValid := splitPos != 0 && splitPos <= 6
        }

        if (isValid) {
            pos := InStr(triggerStr, "*", false, 2)
            IsNoEndChar := pos != 0 && pos < splitPos

            pos := InStr(triggerStr, "?", false, 2)
            IsSubStr := pos != 0 && pos < splitPos

            pos := InStr(triggerStr, "B0", false, 2)
            IsNoDelete := pos != 0 && pos < splitPos

            Str := SubStr(triggerStr, splitPos + 1)
        }

        this.Str := Str
        this.IsEndChar := !IsNoEndChar
        this.IsSubStr := IsSubStr
        this.IsDelete := !IsNoDelete
        this.showSaveBtn := showSaveBtn
        return
    }

    CheckConfigValid() {
        len := StrLen(this.Str)
        if (len >= 40) {
            MsgBox(GetLang("字串长度不能超过40,有异议请联系UP: 浮生若梦的兔子。"))
            return false
        }

        return true
    }
}
