#Requires AutoHotkey v2.0

; =====================================================================
; 输出编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class OutputGui {
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
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
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
        title := this.ParentTile GetLang("输出编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8")
        body.Rows("30", "30", "82", "34", "*")
        body.Cols("80", "150", "90", "150")

        ; 行0：快捷方式 + 执行指令 + 备注
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        hk := row0.Add("TextBox").Name("HotkeyText").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(130).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：输出类型 + 保存变量
        row1 := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("输出类型:")).VerticalAlignment("Center")
        ot := row1.Add("ComboBox").Name("OutputTypeCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0")
        ; §21.4：字符变量类型已移除（改由 变量指令-字符 的「编辑」按钮构建）
        for t in GetLangArr(["发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板"])
            ot.Add("ComboBoxItem").Content(t)
        varNameRow := row1.Add("StackPanel").Name("VarNameRow").Orientation("Horizontal").Margin("12,0,0,0").Visibility("Collapsed")
        varNameRow.Add("TextBlock").Text(GetLang("保存变量") "：").VerticalAlignment("Center")
        varNameRow.Add("ComboBox").Name("VariableNameCombo").Width(110).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 行2：输出内容
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("输出内容：")).VerticalAlignment("Top").Margin("0,4,0,0")
        body.Add("TextBox").Grid_Row(2).Grid_Column(1).Grid_ColumnSpan(3).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Margin("4,2,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 行3：变量数组
        row3 := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row3.Add("TextBlock").Text(GetLang("变量数组：")).VerticalAlignment("Center")
        vt := row3.Add("ComboBox").Name("VarTypeCombo").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        row3.Add("ComboBox").Name("VariCombo").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
        row3.Add("Button").Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).Margin("8,0,0,0")
        row3.Add("Button").Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行4：确定
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="500" Height="252" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("OutputTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeOutputType"))
        this.ui.OnEvent("VarTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshVarType"))
        this.ui.OnEvent("BtnAddName", "Click", ObjBindMethod(this, "OnClickAddVarNameBtn"))
        this.ui.OnEvent("BtnAddValue", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
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

    ; 非编辑 ComboBox：设置候选项 + 按文本选中
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

    ; 可编辑 ComboBox：候选项 + 当前文本
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("输出")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        if (this.Data.VariableName == "")
            this.Data.VariableName := "Data"

        this.ui.Update("TextCon", "Text", GetLangStr(this.Data.Text, 1))
        this._SetDDL("OutputTypeCombo", GetLangArr(["发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板"]), GetLang(this.Data.OutputType))
        this._SetCombo("VariableNameCombo", GetGuiVarArr(), GetLang(this.Data.VariableName))
        this._SetDDL("VariCombo", this.DLVariableArr, "")
        this.ui.Update("VariCombo", "SelectedIndex", "0")

        this.OnChangeOutputType()
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state)
            Hotkey("!l", MacroAction, "On")
        else
            Hotkey("!l", MacroAction, "Off")
    }

    OnRefreshVarType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsResVar := this.ui.Query("VarTypeCombo") == GetLang("变量")
        DLArr := IsResVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
        curText := this.ui.Query("VariCombo")
        this._SetDDL("VariCombo", DLArr, curText)
    }

    OnChangeOutputType(state := "", ctrl := "", event := "") {
        ; §21.4：字符变量类型已移除，无需再控制保存变量行显隐
        return
    }

    OnClickAddVarNameBtn(state, ctrl, event) {
        this.ui.Update("TextCon", "Text", this.ui.Query("TextCon") . this.ui.Query("VariCombo"))
    }

    OnClickAddVarValueBtn(state, ctrl, event) {
        ArraySymbol := this.ui.Query("VarTypeCombo") == GetLang("变量") ? "" : "ε"
        this.ui.Update("TextCon", "Text", this.ui.Query("TextCon") . "{" ArraySymbol this.ui.Query("VariCombo") "}")
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveOutputData()
        this.ToggleFunc(false)
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this._CloseWindow()
    }

    CheckIfValid() {
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveOutputData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    SaveOutputData() {
        this.Data.Text := GetLangStr(this.ui.Query("TextCon"), 2)
        this.Data.OutputType := GetLangKey(this.ui.Query("OutputTypeCombo"))
        this.Data.VariableName := GetVarName(this.ui.Query("VariableNameCombo"))
        SaveMacroCMDData(this.Data)
    }
}
