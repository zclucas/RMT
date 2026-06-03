#Requires AutoHotkey v2.0
#Include ExVariableEditGui.ahk

class ExVariableGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.SetAreaAction := (x1, y1, x2, y2) => this.OnSetSearchArea(x1, y1, x2, y2)

        this.IsIgnoreExistCon := ""
        this.ToggleConArr := []
        this.VariableConArr := []
        this.WinInfoArr := []
        this.Data := ""

        this.OCROptConArr := []
        this.MyEditGui := ExVariableEditGui()
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
        this.OnTypeChange()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("变量提取编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80, 20), GetLang("快捷方式："))
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

        PosY += 35
        PosX := 20
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 3, 75), GetLang("提取来源："))
        this.ExtractTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 75, PosY - 2, 75), GetLangArr([
            "屏幕", "剪切板", "窗口"]))
        this.ExtractTypeCon.OnEvent("Change", this.OnTypeChange.Bind(this))
        this.ExtractTypeCon.Value := 1

        PosX := 200
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口信息:"))
        this.WinInfoArr.Push(con)
        PosX += 80
        this.WinInfoCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 150), "")
        this.WinInfoArr.Push(this.WinInfoCon)
        PosX += 160
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 50, 27), GetLang("编辑"))
        btnCon.OnEvent("Click", this.OnClickWinEditBtn.Bind(this))
        this.WinInfoArr.Push(btnCon)

        PosX := 20
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("提取文本："))
        this.ExtractStrCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX + 75, PosY - 3, 335), "")
        con := MyGui.Add("Button", Format("x{} y{} w{}", PosX + 420, PosY - 4, 50), "编辑")
        con.OnEvent("Click", this.OnClickExtractBtn.Bind(this))

        PosX := 20
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("提取次数:"))
        PosX += 75
        this.SearchCountCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 75))

        PosX += 105
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("每次间隔："))
        this.SearchIntervalCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 75, PosY - 5, 75))

        PosX := 10
        PosY += 30
        con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 540, 95), GetLang("提取选项:"))

        PosX := 20
        PosY += 25
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY, 25), "F1")
        con.Enabled := false
        PosX += 30
        this.SelectToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{} h{} Left", PosX, PosY, 150, 25),
        GetLang("左键框选搜索范围"))
        this.SelectToggleCon.OnEvent("Click", (*) => this.OnClickSelectToggle())
        this.OCROptConArr.Push(this.SelectToggleCon)

        PosX := 200
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标X："))
        this.OCROptConArr.Push(con)
        PosX += 80
        this.StartPosXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.OCROptConArr.Push(this.StartPosXCon)

        PosX += 105
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标Y："))
        this.OCROptConArr.Push(con)
        PosX += 80
        this.StartPosYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.OCROptConArr.Push(this.StartPosYCon)

        PosX := 20
        PosY += 35
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 3, 75), GetLang("识别模型："))
        this.OCROptConArr.Push(con)
        PosX += 75
        this.OCRTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} Center", PosX, PosY - 2, 75), GetLangArr(["中文",
            "英文"]))
        this.OCRTypeCon.Value := 1
        this.OCROptConArr.Push(this.OCRTypeCon)

        PosX := 200
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标X："))
        this.OCROptConArr.Push(con)
        PosX += 80
        this.EndPosXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.OCROptConArr.Push(this.EndPosXCon)

        PosX += 105
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标Y："))
        this.OCROptConArr.Push(con)
        PosX += 80
        this.EndPosYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.OCROptConArr.Push(this.EndPosYCon)

        PosX := 10
        PosY += 40
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 540, 145), GetLang("结果保存选项:"))

        PosX := 40
        PosY += 20
        this.IsIgnoreExistCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 180), GetLang("如果变量存在则不改变数值"))

        PosX := 30
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("开关      变量名"))

        PosX := 20
        PosY += 20
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), "1.")
        PosX += 20
        con := MyGui.Add("Checkbox", Format("x{} y{} -Wrap w15", PosX, PosY + 3), "")
        this.ToggleConArr.Push(con)

        PosX += 20
        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 100), [])
        this.VariableConArr.Push(con)

        PosX += 150
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), "2.")
        PosX += 20
        con := MyGui.Add("Checkbox", Format("x{} y{} -Wrap w15", PosX, PosY + 3), "")
        this.ToggleConArr.Push(con)

        PosX += 20
        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 100), [])
        this.VariableConArr.Push(con)

        PosX += 150
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), "3.")
        PosX += 20
        con := MyGui.Add("Checkbox", Format("x{} y{} -Wrap w15", PosX, PosY + 3), "")
        this.ToggleConArr.Push(con)

        PosX += 20
        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 100), [])
        this.VariableConArr.Push(con)

        PosX := 20
        PosY += 35
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), "4.")
        PosX += 20
        con := MyGui.Add("Checkbox", Format("x{} y{} -Wrap w15", PosX, PosY + 3), "")
        this.ToggleConArr.Push(con)

        PosX += 20
        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 100), [])
        this.VariableConArr.Push(con)

        PosX += 150
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), "5.")
        PosX += 20
        con := MyGui.Add("Checkbox", Format("x{} y{} -Wrap w15", PosX, PosY + 3), "")
        this.ToggleConArr.Push(con)

        PosX += 20
        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 100), [])
        this.VariableConArr.Push(con)

        PosX += 150
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), "6.")
        PosX += 20
        con := MyGui.Add("Checkbox", Format("x{} y{} -Wrap w15", PosX, PosY + 3), "")
        this.ToggleConArr.Push(con)

        PosX += 20
        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 100), [])
        this.VariableConArr.Push(con)

        PosY += 45
        PosX := 210
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{} Center", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(560, 450)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 560, 450))
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("变量提取")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        if (this.Data.ToggleArr.Length == 4) {
            this.Data.ToggleArr.Push(false)
            this.Data.ToggleArr.Push(false)
            this.Data.VariableArr.Push("Num5")
            this.Data.VariableArr.Push("Num6")
        }

        loop this.Data.ToggleArr.Length {
            this.ToggleConArr[A_Index].Value := this.Data.ToggleArr[A_Index]
            this.VariableConArr[A_Index].Delete()
            this.VariableConArr[A_Index].Add(GetGuiVarArr())
            this.VariableConArr[A_Index].Text := this.Data.VariableArr[A_Index]
        }
        this.IsIgnoreExistCon.Value := this.Data.IsIgnoreExist
        this.ExtractStrCon.Value := this.Data.ExtractStr
        this.ExtractTypeCon.Value := this.Data.ExtractType
        this.WinInfoCon.Value := this.Data.WinInfo
        this.OCRTypeCon.Value := this.Data.OCRType

        this.StartPosXCon.Delete()
        this.StartPosXCon.Add(GetGuiVarArr())
        this.StartPosYCon.Delete()
        this.StartPosYCon.Add(GetGuiVarArr())
        this.EndPosXCon.Delete()
        this.EndPosXCon.Add(GetGuiVarArr())
        this.EndPosYCon.Delete()
        this.EndPosYCon.Add(GetGuiVarArr())
        this.StartPosXCon.Text := this.Data.StartPosX
        this.StartPosYCon.Text := this.Data.StartPosY
        this.EndPosXCon.Text := this.Data.EndPosX
        this.EndPosYCon.Text := this.Data.EndPosY
        this.SearchCountCon.Delete()
        this.SearchCountCon.Add([GetLang("无限")])
        this.SearchCountCon.Text := this.Data.SearchCount == -1 ? GetLang("无限") : this.Data.SearchCount
        this.SearchIntervalCon.Value := this.Data.SearchInterval
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    OnTypeChange(*) {
        IsOcr := this.ExtractTypeCon.Value == 1 || this.ExtractTypeCon.Value == 3
        isWin := this.ExtractTypeCon.Value == 3
        for index, value in this.OCROptConArr {
            value.Enabled := IsOcr
        }

        for index, value in this.WinInfoArr {
            value.Enabled := isWin
        }
    }

    OnClickWinEditBtn(*) {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(this.WinInfoCon)
    }

    OnClickExtractBtn(*) {
        this.MyEditGui.SureAction := this.OnSureExtractAction.Bind(this)
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.MyEditGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.MyEditGui.OwnerHwnd := ""
        }
        this.MyEditGui.ShowGui(this.ExtractStrCon.Value)
    }

    OnSureExtractAction(ExtractStr, VariNum) {
        this.ExtractStrCon.Value := ExtractStr
        loop this.ToggleConArr.Length {
            isTog := VariNum >= A_Index
            this.ToggleConArr[A_Index].Value := isTog
        }
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveExVariableData()
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

    OnClickSelectToggle() {
        state := this.SelectToggleCon.Value
        if (state == 1)
            TogSelectArea(true, this.SetAreaAction)
        else
            TogSelectArea(false)
    }

    OnF1() {
        this.SelectToggleCon.Value := 1
        TogSelectArea(true, this.SetAreaAction)
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        this.SelectToggleCon.Value := 0
        isWin := this.ExtractTypeCon.Value == 3
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]

        this.StartPosXCon.Text := Point1[1]
        this.StartPosYCon.Text := Point1[2]
        this.EndPosXCon.Text := Point2[1]
        this.EndPosYCon.Text := Point2[2]
    }

    CheckIfValid() {
        if (this.ExtractTypeCon.Value == 3 && this.WinInfoCon.Value == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (!InStr(this.ExtractStrCon.Value, "&x") && !InStr(this.ExtractStrCon.Value, "&c")) {
            if (this.ExtractStrCon.Value != "") {
                MsgBox(GetLang("提取文本：不包含&x 或 &c 无法提取内容到变量中"))
                return false
            }
        }

        ToggleArr := []
        loop this.ToggleConArr.Length {
            ToggleArr.Push(this.ToggleConArr[A_Index].Value)
            if (this.ToggleConArr[A_Index].Value) {
                if (IsNumber(this.VariableConArr[A_Index].Text)) {
                    MsgBox(Format(GetLang("{}. 变量名不规范：变量名不能是纯数字"), A_Index))
                    return false
                }

                if (InStr(this.VariableConArr[A_Index].Text, "_")) {
                    MsgBox(Format(GetLang("{}. 变量名不规范：变量名不能包含下划线"), A_Index))
                    return false
                }
            }
        }

        ActiveLength := GetExVariableActiveLength(ToggleArr)
        if (ActiveLength > 1) {
            ExtractStr := this.ExtractStrCon.Value
            ExtractStr := StrReplace(ExtractStr, "&x", "", true, &XCount)
            ExtractStr := StrReplace(ExtractStr, "&c", "", true, &YCount)
            if (XCount + YCount < ActiveLength) {
                MsgBox(Format(GetLang("提取文本中包含的&x和&c个数少于结果保存变量中勾选的个数")))
                return false
            }
        }

        return true
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveExVariableData()
        CommandStr := this.GetCommandStr()
        tableItem := MySoftData.SpecialTableItem
        tableItem.KilledArr[1] := false
        tableItem.PauseArr[1] := 0
        tableItem.ActionCount[1] := 0
        tableItem.index := 1

        this.TestExVariable(this.Data)
    }

    TestExVariable(Data) {
        tableItem := MySoftData.SpecialTableItem
        HasX1 := TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
        HasY1 := TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
        HasX2 := TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
        HasY2 := TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
        if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
            return

        if (Data.ExtractType == 1) {
            TextObjs := GetScreenTextObjArr(X1, Y1, X2, Y2, Data.OCRType)
            TextObjs := TextObjs == "" ? [] : TextObjs
        }
        else if (Data.ExtractType == 2) {
            TextObjs := []
            if (!IsClipboardText())
                return

            obj := Object()
            obj.Text := A_Clipboard
            TextObjs.Push(obj)
        }
        else if (Data.ExtractType == 3) {
            HasX1 := TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
            HasY1 := TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
            HasX2 := TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
            HasY2 := TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
            if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
                return
            TextObjs := []
            hwndList := GetHwndList(Data.WinInfo)
            loop hwndList.Length {
                CurWinTextObjs := GetWinTextObjArr(hwndList[A_Index], X1, Y1, X2, Y2, Data.OCRType)
                if (CurWinTextObjs != "")
                    TextObjs.Push(CurWinTextObjs*)
            }
        }

        allText := ""
        for _, value in TextObjs {
            allText .= value.text "`n"
        }
        allText := Trim(allText)

        NameArr := []
        ValueArr := []
        ExtractStr := this.GetReplaceVarText(Data.ExtractStr)
        for _, value in TextObjs {
            VariableValueArr := ExtractVariable(value.Text, ExtractStr)
            VariableValueArr := ExtractStr == "" && allText != "" ? [allText] : VariableValueArr
            if (VariableValueArr == "")
                continue
            if (GetExVariableActiveLength(Data.ToggleArr) > VariableValueArr.Length)
                continue

            loop VariableValueArr.Length {
                if (Data.ToggleArr[A_Index]) {
                    NameArr.Push(Data.VariableArr[A_Index])
                    ValueArr.Push(VariableValueArr[A_Index])
                }
            }
            break
        }

        if (NameArr.Length == 0) {
            MsgBox(GetLang("变量提取失败"))
        }
        else {
            tipStr := GetLang("已提取以下变量") "`n"
            loop NameArr.Length {
                tipStr .= NameArr[A_Index] " = " ValueArr[A_Index] "`n"
            }
            MsgBox(tipStr)
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    SaveExVariableData() {
        this.Data.ExtractStr := this.ExtractStrCon.Value
        this.Data.ExtractType := this.ExtractTypeCon.Value
        this.Data.WinInfo := this.WinInfoCon.Value
        this.Data.OCRType := this.OCRTypeCon.Value
        this.Data.StartPosX := this.StartPosXCon.Text
        this.Data.StartPosY := this.StartPosYCon.Text
        this.Data.EndPosX := this.EndPosXCon.Text
        this.Data.EndPosY := this.EndPosYCon.Text
        this.Data.SearchCount := this.SearchCountCon.Text == GetLang("无限") ? -1 : this.SearchCountCon.Text
        this.Data.SearchInterval := this.SearchIntervalCon.Value
        this.Data.IsIgnoreExist := this.IsIgnoreExistCon.Value
        loop this.Data.ToggleArr.Length {
            this.Data.ToggleArr[A_Index] := this.ToggleConArr[A_Index].Value
            this.Data.VariableArr[A_Index] := GetVarName(this.VariableConArr[A_Index].Text)
        }

        ; 添加全局变量，方便下拉选取
        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.VariableArr[A_Index]] := true
        }

        SaveMacroCMDData(this.Data)
    }

    GetReplaceVarText(text) {
        matches := []  ; 初始化空数组
        pos := 1  ; 从字符串开头开始搜索

        while (pos := RegExMatch(text, "\{(.*?)\}", &match, pos)) {
            matches.Push(match[1])  ; 把花括号内的内容存入数组
            pos += match.Len  ; 移动到匹配结束位置，继续搜索
        }

        Content := text
        for index, value in matches {
            hasValue := this.TryGetVariableValue(&variValue, value, false)
            if (hasValue)
                Content := StrReplace(Content, "{" value "}", variValue)
        }
        return Content
    }

    TryGetVariableValue(&Value, variableName, variTip := true) {
        if (IsNumber(variableName)) {
            Value := variableName
            return true
        }

        if (variableName == GetLang("当前鼠标坐标X") || variableName == GetLang("当前鼠标坐标Y")) {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            Value := variableName == GetLang("当前鼠标坐标X") ? mouseX : mouseY
            return true
        }

        GlobalVariableMap := MySoftData.VariableMap
        if (GlobalVariableMap.Has(variableName)) {
            Value := GlobalVariableMap[variableName]
            return true
        }

        if (variTip)
            ShowNoVariableTip(variableName)
        return false
    }
}
