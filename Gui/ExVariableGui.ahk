#Requires AutoHotkey v2.0
#Include ExVariableEditGui.ahk

; =====================================================================
; 变量提取编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class ExVariableGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.Data := ""
        this.SerialStr := ""
        this.SetAreaAction := (x1, y1, x2, y2) => this.OnSetSearchArea(x1, y1, x2, y2)
        this.MyEditGui := ExVariableEditGui()
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._batching := true
        try this.Init(cmd)
        finally {
            this._flushBatch()
        }
        this.ToggleFunc(true)
        this.OnTypeChange()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ; batching 中入队，_flushBatch 一次性 BatchUpdate（合并 Init 的多次 Update 为一次 IPC）
    _ComboPush(comboName, propertyName, value) {
        if (this._batching)
            this._batch.Push({ControlName: comboName, PropertyName: propertyName, Value: value})
        else
            this.ui.Update(comboName, propertyName, value)
    }

    _flushBatch() {
        this._batching := false
        if (IsObject(this.ui) && this._batch.Length > 0) {
            this.ui.BatchUpdate(this._batch)
            this._batch := []
        }
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("变量提取编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "34", "34", "32", "Auto", "Auto", "*")

        ; 行0：快捷方式
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：提取来源 + 窗口信息
        row1 := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("提取来源：")).VerticalAlignment("Center")
        et := row1.Add("ComboBox").Name("ExtractTypeCombo").Width(70).Height(26).MinHeight(26).Margin("4,0,0,0")
        et.Add("ComboBoxItem").Content(GetLang("屏幕")).Tag("1")
        et.Add("ComboBoxItem").Content(GetLang("剪切板")).Tag("2")
        et.Add("ComboBoxItem").Content(GetLang("窗口")).Tag("3")
        winRow := row1.Add("StackPanel").Name("WinInfoRow").Orientation("Horizontal").Margin("12,0,0,0")
        winRow.Add("TextBlock").Text(GetLang("窗口信息:")).VerticalAlignment("Center")
        winRow.Add("TextBox").Name("WinInfoCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")
        winRow.Add("Button").Name("BtnWinEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行2：提取文本
        row2 := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        row2.Add("TextBlock").Text(GetLang("提取文本：")).VerticalAlignment("Center")
        row2.Add("TextBox").Name("ExtractStrCon").Width(335).Height(24).MinHeight(24).Margin("4,0,0,0")
        row2.Add("Button").Name("BtnExtractEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行3：提取次数 + 每次间隔
        row3 := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").VerticalAlignment("Center")
        row3.Add("TextBlock").Text(GetLang("提取次数:")).VerticalAlignment("Center")
        row3.Add("ComboBox").Name("SearchCountCombo").Width(70).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        row3.Add("TextBlock").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("12,0,0,0")
        row3.Add("TextBox").Name("SearchIntervalCon").Width(70).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行4：提取选项 GroupBox
        optGroup := body.Add("GroupBox").Grid_Row(4).Name("OptGroup").Header(GetLang("提取选项:"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        ocr := optGroup.Add("Grid").Name("OCRPanel").Margin("8,6")
        ocr.Cols("25", "175", "80", "85", "80", "85")
        ocr.Rows("30", "30")
        ocr.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text("F1").VerticalAlignment("Center")
        ocr.Add("CheckBox").Grid_Row(0).Grid_Column(1).Name("SelectToggle").Content(GetLang("左键框选搜索范围")).VerticalAlignment("Center")
        ocr.Add("TextBlock").Grid_Row(0).Grid_Column(2).Text(GetLang("起始坐标X：")).VerticalAlignment("Center")
        ocr.Add("ComboBox").Grid_Row(0).Grid_Column(3).Name("StartPosX").Height(24).MinHeight(24).IsEditable("True")
        ocr.Add("TextBlock").Grid_Row(0).Grid_Column(4).Text(GetLang("起始坐标Y：")).VerticalAlignment("Center")
        ocr.Add("ComboBox").Grid_Row(0).Grid_Column(5).Name("StartPosY").Height(24).MinHeight(24).IsEditable("True")
        ocr.Add("TextBlock").Grid_Row(1).Grid_Column(0).Grid_ColumnSpan(2).Text(GetLang("终止坐标X：")).VerticalAlignment("Center")
        ocr.Add("ComboBox").Grid_Row(1).Grid_Column(2).Name("EndPosX").Height(24).MinHeight(24).IsEditable("True")
        ocr.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("终止坐标Y：")).VerticalAlignment("Center")
        endY := ocr.Add("StackPanel").Grid_Row(1).Grid_Column(5).Orientation("Horizontal")
        endY.Add("ComboBox").Name("EndPosY").Width(85).Height(24).MinHeight(24).IsEditable("True")

        ; 行5：结果保存选项 GroupBox
        resGroup := body.Add("GroupBox").Grid_Row(5).Name("ResultGroup").Header(GetLang("结果保存选项:"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        res := resGroup.Add("Grid").Margin("8,6")
        res.Rows("28", "26", "30", "30")
        res.Cols("20", "140", "40", "140", "40", "140")
        res.Add("CheckBox").Grid_Row(0).Grid_ColumnSpan(6).Name("IsIgnoreExist").Content(GetLang("如果变量存在则不改变数值")).VerticalAlignment("Center")
        res.Add("TextBlock").Grid_Row(1).Grid_Column(1).Text(GetLang("开关      变量名")).VerticalAlignment("Center")
        loop 6 {
            row := (A_Index <= 3) ? 2 : 3
            col := Mod((A_Index - 1), 3) * 2
            res.Add("TextBlock").Grid_Row(row).Grid_Column(col).Text(A_Index ".").VerticalAlignment("Center")
            res.Add("CheckBox").Grid_Row(row).Grid_Column(col + 1).Name("Tog" A_Index).VerticalAlignment("Center")
            res.Add("ComboBox").Grid_Row(row).Grid_Column(col + 2).Name("Var" A_Index).Width(120).Height(24).MinHeight(24).IsEditable("True").HorizontalAlignment("Left")
        }

        ; 行6：确定
        btnRow := body.Add("StackPanel").Grid_Row(6).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="520" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("ExtractTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnExtractEdit", "Click", ObjBindMethod(this, "OnClickExtractBtn"))
        this.ui.OnEvent("SelectToggle", "Click", ObjBindMethod(this, "OnClickSelectToggle"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                if (this.OwnerHwnd != "")
                    try this.ui.Update("Window", "NativeOwner", String(this.OwnerHwnd))
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                try SetTimer((*) => this.ui.Update("Window", "Opacity", "1"), -10)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd)
            this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        } finally {
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        this._ComboPush(comboName, "Text", text)
    }

    _TypeValue() {
        v := IsObject(this.ui) ? this.ui.Query("ExtractTypeCombo") : ""
        return IsNumber(v) ? Integer(v) : 1
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("变量提取")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        if (this.Data.ToggleArr.Length == 4) {
            this.Data.ToggleArr.Push(false)
            this.Data.ToggleArr.Push(false)
            this.Data.VariableArr.Push("Num5")
            this.Data.VariableArr.Push("Num6")
        }

        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.ui.Update("Tog" i, "IsChecked", this.Data.ToggleArr[i] ? "True" : "False")
            this._SetCombo("Var" i, GetGuiVarArr(), this.Data.VariableArr[i])
        }
        this.ui.Update("IsIgnoreExist", "IsChecked", this.Data.IsIgnoreExist ? "True" : "False")
        this.ui.Update("ExtractStrCon", "Text", this.Data.ExtractStr)
        this.ui.Update("ExtractTypeCombo", "SelectedIndex", String(this.Data.ExtractType - 1))
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)

        this._SetCombo("StartPosX", GetGuiVarArr(), this.Data.StartPosX)
        this._SetCombo("StartPosY", GetGuiVarArr(), this.Data.StartPosY)
        this._SetCombo("EndPosX", GetGuiVarArr(), this.Data.EndPosX)
        this._SetCombo("EndPosY", GetGuiVarArr(), this.Data.EndPosY)
        this._SetCombo("SearchCountCombo", [GetLang("无限")], this.Data.SearchCount == -1 ? GetLang("无限") : this.Data.SearchCount)
        this.ui.Update("SearchIntervalCon", "Text", this.Data.SearchInterval)
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

    OnTypeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        t := this._TypeValue()
        IsOcr := t == 1 || t == 3
        isWin := t == 3
        this.ui.Update("OCRPanel", "IsEnabled", IsOcr ? "True" : "False")
        this.ui.Update("WinInfoRow", "IsEnabled", isWin ? "True" : "False")
    }

    OnClickWinEditBtn(state := "", ctrl := "", event := "") {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        ; 传值桥接（原生 FrontInfoGui 读写 .Value），不传字符串
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    OnClickExtractBtn(state := "", ctrl := "", event := "") {
        this.MyEditGui.SureAction := this.OnSureExtractAction.Bind(this)
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            this.MyEditGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.MyEditGui.OwnerHwnd := ""
        }
        this.MyEditGui.ShowGui(this.ui.Query("ExtractStrCon"))
    }

    OnSureExtractAction(ExtractStr, VariNum) {
        if (IsObject(this.ui))
            this.ui.Update("ExtractStrCon", "Text", ExtractStr)
        loop 6 {
            isTog := VariNum >= A_Index
            this.ui.Update("Tog" A_Index, "IsChecked", isTog ? "True" : "False")
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveExVariableData()
        this.ToggleFunc(false)
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this._CloseWindow()
    }

    OnClickSelectToggle(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        state := this.ui.Query("SelectToggle") == "True"
        if (state)
            TogSelectArea(true, this.SetAreaAction)
        else
            TogSelectArea(false)
    }

    OnF1() {
        if (IsObject(this.ui))
            this.ui.Update("SelectToggle", "IsChecked", "True")
        TogSelectArea(true, this.SetAreaAction)
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        if (!IsObject(this.ui))
            return
        this.ui.Update("SelectToggle", "IsChecked", "False")
        isWin := this._TypeValue() == 3
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]

        this.ui.Update("StartPosX", "Text", Point1[1])
        this.ui.Update("StartPosY", "Text", Point1[2])
        this.ui.Update("EndPosX", "Text", Point2[1])
        this.ui.Update("EndPosY", "Text", Point2[2])
    }

    CheckIfValid() {
        if (this._TypeValue() == 3 && this.ui.Query("WinInfoCon") == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (!InStr(this.ui.Query("ExtractStrCon"), "&x") && !InStr(this.ui.Query("ExtractStrCon"), "&c")) {
            if (this.ui.Query("ExtractStrCon") != "") {
                MsgBox(GetLang("提取文本：不包含&x 或 &c 无法提取内容到变量中"))
                return false
            }
        }

        ToggleArr := []
        loop 6 {
            isOn := this.ui.Query("Tog" A_Index) == "True"
            ToggleArr.Push(isOn)
            if (isOn) {
                varText := this.ui.Query("Var" A_Index)
                if (IsNumber(varText)) {
                    MsgBox(Format(GetLang("{}. 变量名不规范：变量名不能是纯数字"), A_Index))
                    return false
                }
                if (InStr(varText, "_")) {
                    MsgBox(Format(GetLang("{}. 变量名不规范：变量名不能包含下划线"), A_Index))
                    return false
                }
            }
        }

        ActiveLength := GetExVariableActiveLength(ToggleArr)
        if (ActiveLength > 1) {
            ExtractStr := this.ui.Query("ExtractStrCon")
            ExtractStr := StrReplace(ExtractStr, "&x", "", true, &XCount)
            ExtractStr := StrReplace(ExtractStr, "&c", "", true, &YCount)
            if (XCount + YCount < ActiveLength) {
                MsgBox(Format(GetLang("提取文本中包含的&x和&c个数少于结果保存变量中勾选的个数")))
                return false
            }
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
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
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    SaveExVariableData() {
        this.Data.ExtractStr := this.ui.Query("ExtractStrCon")
        this.Data.ExtractType := this._TypeValue()
        this.Data.WinInfo := this.ui.Query("WinInfoCon")
        this.Data.OCRType := 1 ; v6 统一多语言模型，不再区分
        this.Data.StartPosX := this.ui.Query("StartPosX")
        this.Data.StartPosY := this.ui.Query("StartPosY")
        this.Data.EndPosX := this.ui.Query("EndPosX")
        this.Data.EndPosY := this.ui.Query("EndPosY")
        this.Data.SearchCount := this.ui.Query("SearchCountCombo") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCombo")
        this.Data.SearchInterval := this.ui.Query("SearchIntervalCon")
        this.Data.IsIgnoreExist := this.ui.Query("IsIgnoreExist") == "True"
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.Data.ToggleArr[i] := this.ui.Query("Tog" i) == "True"
            this.Data.VariableArr[i] := GetVarName(this.ui.Query("Var" i))
        }

        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.VariableArr[A_Index]] := true
        }
        SaveMacroCMDData(this.Data)
    }

    GetReplaceVarText(text) {
        matches := []
        pos := 1
        while (pos := RegExMatch(text, "\{(.*?)\}", &match, pos)) {
            matches.Push(match[1])
            pos += match.Len
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
