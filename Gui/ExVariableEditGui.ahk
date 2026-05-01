#Requires AutoHotkey v2.0

class ExVariableEditGui {
    __new() {
        this.Gui := ""
        this.OwnerHwnd := ""
        this.SureAction := ""

        this.OriTextCon := ""
        this.VarTextConArr := []
    }

    ShowGui(ExtractStr) {
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

        this.Init(ExtractStr)
    }

    Init(ExtractStr) {
        CurPos := 1
        NextText := InStr(ExtractStr, "&c", true, CurPos)
        NextNum := InStr(ExtractStr, "&x", true, CurPos)
        TextConArr := []
        while (NextNum || NextText) {
            Text := GetLang("<内容>")
            CurPos := NextText + 1
            if (NextNum > 0 && (NextNum < NextText || NextText == 0)) {
                Text := GetLang("<数字>")
                CurPos := NextNum + 1
            }

            TextConArr.Push(Text)
            NextText := InStr(ExtractStr, "&c", true, CurPos)
            NextNum := InStr(ExtractStr, "&x", true, CurPos)
        }
        ExtractStr := StrReplace(ExtractStr, "&c", GetLang("<内容>"))
        ExtractStr := StrReplace(ExtractStr, "&x", GetLang("<数字>"))
        this.OriTextCon.Value := ExtractStr
        for index, TextCon in this.VarTextConArr {
            TextCon.Value := ""
            if (TextConArr.Length >= index)
                TextCon.Value := TextConArr[index]
        }
    }

    AddGui() {
        MyGui := Gui(, GetLang("提取文本编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 15
        PosY := 10
        tip1 := GetLang("源文本内容：请输入 提取范围 或 剪切板 的文本内容")
        tip2 := GetLang("提取内容：请输入你需要提取的变量内容")
        tip3 := GetLang("将根据 源文本内容 和 提取内容 自动生成提取文本")
        tip4 := GetLang("提示1：源文本内容空时，将提取所有内容到第一个变量中")
        tip5 := GetLang("提示2：源文本内容不需要太多，包含提取内容即可")
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), Format("{}`n{}`n{}`n{}`n{}", tip1, tip2, tip3, tip4, tip5))
        PosY += 110
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("源文本内容："))
        PosY += 25
        this.OriTextCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 430, 50), "")

        PosY += 60
        PosX := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 2), Format("{}1:", GetLang("提取内容")))
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 85, PosY, 100), "")
        this.VarTextConArr.Push(con)

        PosX += 245
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 2), Format("{}2:", GetLang("提取内容")))
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 85, PosY, 100), "")
        this.VarTextConArr.Push(con)

        PosY += 35
        PosX := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 2), Format("{}3:", GetLang("提取内容")))
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 85, PosY, 100), "")
        this.VarTextConArr.Push(con)

        PosX += 245
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 2), Format("{}4:", GetLang("提取内容")))
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 85, PosY, 100), "")
        this.VarTextConArr.Push(con)

        PosY += 35
        PosX := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 2), Format("{}5:", GetLang("提取内容")))
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 85, PosY, 100), "")
        this.VarTextConArr.Push(con)

        PosX += 245
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 2), Format("{}6:", GetLang("提取内容")))
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 85, PosY, 100), "")
        this.VarTextConArr.Push(con)

        PosX := 190
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())
        MyGui.OnEvent("Close", (*) => this.OnClose())
        MyGui.Show(Format("w{} h{}", 480, 370))
    }

    OnClose(*) {
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    CheckIfValid() {
        ExtractStr := this.OriTextCon.Value
        for index, con in this.VarTextConArr {
            if (con.Value == "")
                break

            isContain := InStr(ExtractStr, con.Value)
            ExtractStr := StrReplace(ExtractStr, con.Value, "", true, &OutputVarCount, 1)
            if (!isContain) {
                tipStr := Format("{}{}:{}", GetLang("提取内容"), index, GetLang("未在源文本内容中出现，请修改"))
                MsgBox(tipStr)
                return false
            }
        }
        return true
    }

    GetExtractStr() {
        ExtractStr := this.OriTextCon.Value
        if (this.VarTextConArr[1].Value == "")
            return ""

        for index, con in this.VarTextConArr {
            text := con.Value
            isNum := IsNumber(text) || text == GetLang("<数字>")
            replaceStr := isNum ? "&x" : "&c"

            ExtractStr := StrReplace(ExtractStr, con.Value, replaceStr, true, &OutputVarCount, 1)
        }
        return ExtractStr
    }

    GetVariNum() {
        if (this.VarTextConArr[1].Value == "")
            return 1
        Count := 0
        for index, con in this.VarTextConArr {
            if (con.Value != "") {
                Count++
                continue
            }
            break
        }
        return Count
    }

    OnSureBtnClick() {
        isValid := this.CheckIfValid()
        if (!isValid)
            return

        Action := this.SureAction
        ExtractStr := this.GetExtractStr()
        VariableNum := this.GetVariNum()
        Action(ExtractStr, VariableNum)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }
}
