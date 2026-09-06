#Requires AutoHotkey v2.0

; =====================================================================
; 文本处理编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class TextOpsGui {
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
        this.ArgsNameOptions := []
        this.lastArgsNameConText := ""

        this.ArgsTypeMap := Map(
            GetLang("去除空格"), [GetLang("去除前空白字符"), GetLang("去除后空白字符"), GetLang("去除前后空白字符"), GetLang("去除所有空白字符")],
            GetLang("大小写转换"), [GetLang("全部大写"), GetLang("全部小写"), GetLang("首字母大写")],
            GetLang("文本统计"), [GetLang("字符数"), GetLang("单词数"), GetLang("行数")],
            GetLang("文本提取"), [GetLang("数字提取"), GetLang("字母提取"), GetLang("中文提取"), GetLang("正则匹配")],
            GetLang("文本分割"), [GetLang("内容分割"), GetLang("定长分割"), GetLang("正则匹配")],
            GetLang("文本替换"), [GetLang("普通文本"), GetLang("正则匹配")],
            GetLang("文本拼接"), [GetLang("拼接文本")])
        this.ArgsTipMap := Map(
            GetLang("内容分割"), GetLang("分割文本："),
            GetLang("定长分割"), GetLang("分割长度："),
            GetLang("正则匹配"), GetLang("正则表达式："),
            GetLang("拼接文本"), GetLang("拼接内容："))
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
        this.OnRefresh()
        this.lastArgsNameConText := ""
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
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
        title := this.ParentTile GetLang("文本处理编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "36", "Auto", "Auto", "*")
        body.Cols("85", "160", "85", "160")

        ; 行0：快捷方式
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：处理类型 + 文本来源
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("处理类型:")).VerticalAlignment("Center")
        tc := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("TypeCombo").Height(26).MinHeight(26)
        for t in GetLangArr(["文本分割", "文本提取", "文本替换", "去除空格", "大小写转换", "文本统计", "文本拼接"])
            tc.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(1).Grid_Column(2).Text(GetLang("文本来源:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(3).Name("NameCon").Height(26).MinHeight(26).IsEditable("True")

        ; 行2：处理参数 GroupBox
        pGroup := body.Add("GroupBox").Grid_Row(2).Grid_ColumnSpan(4).Header(GetLang("处理参数"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        p := pGroup.Add("Grid").Margin("10,6")
        p.Cols("85", "160", "85", "160")
        p.Rows("34", "34")
        p.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("类型选项:")).VerticalAlignment("Center")
        p.Add("ComboBox").Grid_Row(0).Grid_Column(1).Name("ArgsTypeCombo").Height(26).MinHeight(26)
        p.Add("TextBlock").Grid_Row(0).Grid_Column(2).Name("ArgsNameTip").Text(GetLang("类型参数:")).VerticalAlignment("Center")
        p.Add("ComboBox").Grid_Row(0).Grid_Column(3).Name("ArgsNameCon").Height(26).MinHeight(26).IsEditable("True")
        p.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("查找文本:")).VerticalAlignment("Center")
        p.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("SearchCon").Height(26).MinHeight(26).IsEditable("True")
        p.Add("TextBlock").Grid_Row(1).Grid_Column(2).Text(GetLang("替换文本:")).VerticalAlignment("Center")
        p.Add("ComboBox").Grid_Row(1).Grid_Column(3).Name("ReplaceCon").Height(26).MinHeight(26).IsEditable("True")

        ; 行3：结果保存 GroupBox
        rGroup := body.Add("GroupBox").Grid_Row(3).Grid_ColumnSpan(4).Header(GetLang("结果保存"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        r := rGroup.Add("StackPanel").Orientation("Horizontal").Margin("10,6")
        r.Add("TextBlock").Text(GetLang("结果：")).VerticalAlignment("Center")
        st := r.Add("ComboBox").Name("SaveTypeCombo").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0").IsEnabled("False")
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        r.Add("ComboBox").Name("SaveNameCon").Width(130).Height(26).MinHeight(26).Margin("10,0,0,0").IsEditable("True")

        ; 行4：确定
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="330" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("ArgsTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshArgsType"))
        this.ui.OnEvent("ArgsNameCon", "TextChanged", ObjBindMethod(this, "OnArgsNameConChange"))
        this.ui.OnEvent("SaveTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshDataType"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
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

    _SetDDL(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        for i, it in items {
            if (it == text) {
                this._ComboPush(comboName, "SelectedIndex", String(i - 1))
                return
            }
        }
        this._ComboPush(comboName, "SelectedIndex", "0")
    }

    _TypeText() => IsObject(this.ui) ? this.ui.Query("TypeCombo") : ""
    _ArgsTypeText() => IsObject(this.ui) ? this.ui.Query("ArgsTypeCombo") : ""

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("文本处理")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLArrayArr := GetGuiArrNameArr()
        ArgsNameArr := GetGuiVarArr(2)
        ArgsNameArr.InsertAt(1, GetLang("制表符"))
        this.ArgsNameOptions := ArgsNameArr.Clone()

        this._SetDDL("TypeCombo", GetLangArr(["文本分割", "文本提取", "文本替换", "去除空格", "大小写转换", "文本统计", "文本拼接"]), GetLang(this.Data.Type))
        this._SetCombo("NameCon", GetGuiVarArr(), this.Data.Name)
        this._SetCombo("ArgsNameCon", ArgsNameArr, this.Data.ArgsName)
        this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
        this._SetCombo("SearchCon", GetGuiVarArr(2), this.Data.Search)
        this._SetCombo("ReplaceCon", GetGuiVarArr(2), this.Data.Replace)
        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), GetLang(this.Data.SaveType))
        this._SetCombo("SaveNameCon", this.DLArrayArr, this.Data.SaveName)
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        typeText := this._TypeText()
        IsSplit := typeText == GetLang("文本分割")
        IsReplace := typeText == GetLang("文本替换")
        IsGetEx := typeText == GetLang("文本提取")
        IsSpace := typeText == GetLang("去除空格")
        IsUpLow := typeText == GetLang("大小写转换")
        IsStatistics := typeText == GetLang("文本统计")
        IsConcat := typeText == GetLang("文本拼接")
        IsGetExReg := IsGetEx && this._ArgsTypeText() == GetLang("正则匹配")

        ArgsDLArr := []
        if (this.ArgsTypeMap.Has(typeText)) {
            ArgsDLArr := this.ArgsTypeMap[typeText]
            idx := 1
            loop ArgsDLArr.Length {
                if (ArgsDLArr[A_Index] == GetLang(this.Data.ArgsType)) {
                    idx := A_Index
                    break
                }
            }
            this._SetDDL("ArgsTypeCombo", ArgsDLArr, GetLang(this.Data.ArgsType))
        }

        ShowArgsType := IsSplit || IsGetEx || IsUpLow || IsSpace || IsStatistics || IsConcat || IsReplace
        ShowArgsName := IsSplit || IsConcat || IsGetExReg
        this.ui.Update("ArgsTypeCombo", "IsEnabled", ShowArgsType ? "True" : "False")
        this.ui.Update("ArgsNameCon", "IsEnabled", ShowArgsName ? "True" : "False")
        this.ui.Update("SearchCon", "IsEnabled", IsReplace ? "True" : "False")
        this.ui.Update("ReplaceCon", "IsEnabled", IsReplace ? "True" : "False")

        OnlyResVar := IsReplace || IsSpace || IsUpLow || IsStatistics || IsConcat
        OnlyResArr := IsSplit || IsGetEx
        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), OnlyResVar ? GetLang("变量") : GetLang("数组"))
        this.OnRefreshArgsType()
        this.OnRefreshDataType()
    }

    OnRefreshArgsType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        tipText := GetLang("类型参数:")
        if (this.ArgsTipMap.Has(this._ArgsTypeText()))
            tipText := this.ArgsTipMap[this._ArgsTypeText()]
        this.ui.Update("ArgsNameTip", "Text", tipText)
        this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
        IsGetEx := this._TypeText() == GetLang("文本提取")
        IsGetExReg := IsGetEx && this._ArgsTypeText() == GetLang("正则匹配")
        if (IsGetEx) {
            this.ui.Update("ArgsNameCon", "IsEnabled", IsGetExReg ? "True" : "False")
        }
    }

    OnRefreshDataType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsResVar := this.ui.Query("SaveTypeCombo") == GetLang("变量")
        ResArr := IsResVar ? GetGuiVarArr() : this.DLArrayArr
        curText := this.ui.Query("SaveNameCon")
        this._SetCombo("SaveNameCon", ResArr, curText)
        this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
    }

    OnArgsNameConChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsConcat := this._TypeText() == GetLang("文本拼接")
        if (!IsConcat) {
            this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
            return
        }
        newText := this.ui.Query("ArgsNameCon")
        if (newText == "") {
            this.lastArgsNameConText := ""
            return
        }
        isFromDropdown := false
        loop this.ArgsNameOptions.Length {
            if (this.ArgsNameOptions[A_Index] == newText) {
                isFromDropdown := true
                break
            }
        }
        if (isFromDropdown && this.lastArgsNameConText != "" && newText != this.lastArgsNameConText) {
            this.ui.Update("ArgsNameCon", "Text", this.lastArgsNameConText "{" newText "}")
        }
        else if (isFromDropdown && (this.lastArgsNameConText == "" || newText == this.lastArgsNameConText)) {
            this.ui.Update("ArgsNameCon", "Text", "{" newText "}")
        }
        this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveTextOpsData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        if (this._TypeText() == GetLang("文本替换")) {
            if (this.ui.Query("SearchCon") == "") {
                MsgBox(GetLang("搜索文本不能为空"))
                return false
            }
        }
        if (this._TypeText() == GetLang("文本分割")) {
            if (this.ui.Query("ArgsNameCon") == "") {
                MsgBox(GetLang("类型参数不能为空"))
                return false
            }
        }
        if (this._TypeText() == GetLang("文本提取")) {
            if (this._ArgsTypeText() == GetLang("正则匹配") && this.ui.Query("ArgsNameCon") == "") {
                MsgBox(GetLang("正则表达式不能为空"))
                return false
            }
        }
        if (!CheckVarNameIfValid(this.ui.Query("SaveNameCon")))
            return false
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveTextOpsData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)
        Res := ""
        if (this.Data.SaveType == "变量" && MySoftData.VariableMap.Has(this.Data.SaveName))
            Res := MySoftData.VariableMap[this.Data.SaveName]
        if (this.Data.SaveType == "数组" && MySoftData.ArrayMap.Has(this.Data.SaveName))
            Res := GetArrayStr(MySoftData.ArrayMap[this.Data.SaveName])
        if (Res != "") {
            tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
            tip2 := Format(GetLang("值：{}"), Res)
            MsgBox(tip1 "`n" tip2)
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    SaveTextOpsData() {
        ArgsName := GetLangKey(this.ui.Query("ArgsNameCon"))
        ArgsName := ArgsName == "制表符" ? "`t" : ArgsName
        this.Data.Type := GetLangKey(this._TypeText())
        this.Data.Name := this.ui.Query("NameCon")
        this.Data.ArgsType := GetLangKey(this._ArgsTypeText())
        this.Data.ArgsName := ArgsName
        this.Data.Search := GetLangKey(this.ui.Query("SearchCon"))
        this.Data.Replace := GetLangKey(this.ui.Query("ReplaceCon"))
        this.Data.MatchType := GetLangKey(this._ArgsTypeText())
        this.Data.SaveType := GetLangKey(this.ui.Query("SaveTypeCombo"))
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        if (this.Data.SaveType == "变量")
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        if (this.Data.SaveType == "数组")
            MySoftData.GlobalArrMap[this.Data.SaveName] := true
        SaveMacroCMDData(this.Data)
    }
}
