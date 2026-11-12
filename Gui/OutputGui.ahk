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
        ui := this.ui
        opened := XamlWin.Open(ui, "", XamlWin.Owner(this))
        if (this.ui != ui)
            return
        if (opened)
            this.ToggleFunc(true)
        else
            this._CloseWindow()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

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
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,12")
        body.Rows("36", "22", "*", "36", "36", "56")
        body.Cols("80", "150", "12", "80", "*")

        ; 行0：输出类型 + 备注（白底，内边距与下拉框一致）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("输出类型:")).VerticalAlignment("Center").Margin("8,0,0,0")
        ot := body.Add("ComboBox").Grid_Row(0).Grid_Column(1).Name("OutputTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        ; §21.4：字符变量类型已移除（改由 变量指令-字符 的「编辑」按钮构建）
        for t in GetLangArr(["发送内容", "粘贴内容", "悬浮显示", "指令窗口", "复制到剪切板"])
            ot.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(0).Grid_Column(3).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 隐藏：旧「保存变量」仍供 Init/Save 读写，字符变量类型已移除故不展示
        hidden := body.Add("StackPanel").Grid_Row(4).Name("VarNameRow").Visibility("Collapsed")
        hidden.Add("ComboBox").Name("VariableNameCombo").IsEditable("True")

        ; 行1-2：输出内容换行；标签右移，与文本框内文字左对齐（内容边距保持不变）
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("输出内容：")).VerticalAlignment("Bottom").Margin("8,0,0,0")
        body.Add("TextBox").Grid_Row(2).Grid_Column(0).Grid_ColumnSpan(5).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").HorizontalContentAlignment("Left").Padding("2,4").MinHeight(72).Margin("0,4,0,4")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 行3：变量数组（标签与输出类型对齐）
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("变量数组：")).VerticalAlignment("Center").Margin("8,0,0,0")
        varRow := body.Add("Grid").Grid_Row(3).Grid_Column(1).Grid_ColumnSpan(4)
        varRow.Cols("90", "8", "*", "8", "70", "8", "70")
        vt := varRow.Add("ComboBox").Grid_Column(0).Name("VarTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center").SelectedIndex("0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        varRow.Add("ComboBox").Grid_Column(2).Name("VariCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        varRow.Add("Button").Grid_Column(4).Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).VerticalAlignment("Center")
        varRow.Add("Button").Grid_Column(6).Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行 4：悬浮显示位置选择，其它输出类型下隐藏
        hudRow := body.Add("Grid").Grid_Row(4).Grid_ColumnSpan(5).Name("HudPosRow").Visibility("Collapsed")
        hudRow.Cols("80", "150", "12", "*")
        hudRow.Add("TextBlock").Grid_Column(0).Text(GetLang("显示位置：")).VerticalAlignment("Center").Margin("8,0,0,0")
        hp := hudRow.Add("ComboBox").Grid_Column(1).Name("HudPosCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in HudPosLabels()
            hp.Add("ComboBoxItem").Content(t)
        hudRow.Add("TextBlock").Grid_Column(3).Text(GetLang("运行中可直接拖动调整")).VerticalAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource TextSub}")

        ; 行 5：确定
        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Bottom").Margin("0,0,0,6")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="330"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/8-输出", XamlWin.BindCurrent(this, "TriggerMacro"))
        this.ui.OnEvent("OutputTypeCombo", "SelectionChanged", XamlWin.BindCurrent(this, "OnChangeOutputType"))
        this.ui.OnEvent("VarTypeCombo", "SelectionChanged", XamlWin.BindCurrent(this, "OnRefreshVarType"))
        this.ui.OnEvent("BtnAddName", "Click", XamlWin.BindCurrent(this, "OnClickAddVarNameBtn"))
        this.ui.OnEvent("BtnAddValue", "Click", XamlWin.BindCurrent(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(*) {
        this.ui := ""
        this._closed := true
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        ui := this.ui
        this.OnWindowClosing()
        if (IsObject(ui))
            try ui.Update("Window", "Close", "")
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
        this._SetDDL("OutputTypeCombo", GetLangArr(["发送内容", "粘贴内容", "悬浮显示", "指令窗口", "复制到剪切板"]), GetLang(this.Data.OutputType))
        this._SetDDL("HudPosCombo", HudPosLabels(), this.Data.HudPos)
        this._SetCombo("VariableNameCombo", GetGuiVarArr(), GetLang(this.Data.VariableName))
        this._SetDDL("VarTypeCombo", GetLangArr(["变量", "数组"]), GetLang("变量"))
        this._SetDDL("VariCombo", this.DLVariableArr, "")
        this.ui.Update("VariCombo", "SelectedIndex", "0")

        ; Init 阶段的批量更新尚未提交，Query 取不到刚设置的下拉值，直接按 Data 判断
        this.ui.Update("HudPosRow", "Visibility", this.Data.OutputType == "悬浮显示" ? "Visible" : "Collapsed")
    }

    ToggleFunc(state) {
        if (state)
            Hotkey("!l", XamlWin.BindCurrent(this, "TriggerMacro"), "On")
        else
            try Hotkey("!l", "Off")
    }

    OnRefreshVarType(state := "", ctrl := "", event := "") {
        ui := this.ui
        if (!IsObject(ui))
            return
        values := ui.Query("VarTypeCombo", "VariCombo")
        if (this.ui != ui || values.Count != 2)
            return
        IsResVar := values["VarTypeCombo"] == GetLang("变量")
        DLArr := IsResVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
        this._SetDDL("VariCombo", DLArr, values["VariCombo"])
    }

    OnChangeOutputType(state := "", ctrl := "", event := "") {
        ui := this.ui
        if (!IsObject(ui))
            return
        ; 仅悬浮显示需要选位置，其它输出类型无此配置
        isHud := GetLangKey(ui.Query("OutputTypeCombo")) == "悬浮显示"
        if (this.ui == ui)
            ui.Update("HudPosRow", "Visibility", isHud ? "Visible" : "Collapsed")
    }

    OnClickAddVarNameBtn(state, ctrl, event) {
        ui := this.ui
        values := ui.Query("TextCon", "VariCombo")
        if (this.ui == ui && values.Count == 2)
            ui.Update("TextCon", "Text", values["TextCon"] . values["VariCombo"])
    }

    OnClickAddVarValueBtn(state, ctrl, event) {
        ui := this.ui
        values := ui.Query("TextCon", "VarTypeCombo", "VariCombo")
        if (this.ui == ui && values.Count == 3) {
            ArraySymbol := values["VarTypeCombo"] == GetLang("变量") ? "" : "ε"
            ui.Update("TextCon", "Text", values["TextCon"] . "{" ArraySymbol values["VariCombo"] "}")
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        ui := this.ui
        if (!this.Hwnd())
            return
        action := this.SureBtnAction
        CommandStr := this.SaveOutputData()
        if (CommandStr == "" || this.ui != ui)
            return
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        ui := this.ui
        if (!this.Hwnd())
            return
        CommandStr := this.SaveOutputData()
        if (CommandStr != "" && this.ui == ui)
            OnTriggerSepcialItemMacro(CommandStr)
    }

    GetCommandStr(remark) {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, remark)
        return CommandStr
    }

    SaveOutputData() {
        ui := this.ui
        if (!IsObject(ui))
            return ""
        hwnd := ui.wpfHwnd
        values := ui.Query("TextCon", "OutputTypeCombo", "VariableNameCombo", "HudPosCombo", "RemarkCon")
        if (this.ui != ui || ui.wpfHwnd != hwnd || values.Count != 5)
            return ""
        this.Data.Text := GetLangStr(values["TextCon"], 2)
        this.Data.OutputType := GetLangKey(values["OutputTypeCombo"])
        this.Data.VariableName := GetVarName(values["VariableNameCombo"])
        this.Data.HudPos := values["HudPosCombo"]
        CommandStr := this.GetCommandStr(values["RemarkCon"])
        SaveMacroCMDData(this.Data)
        ; 配置已变更，需通知 Worker 丢弃缓存的 Data，否则它仍按旧的 OutputType 执行
        ; （例如改为「悬浮显示」后，Worker 仍走「发送内容」分支，不会发出 HO）
        try {
            if (IsSet(MyWorkPool) && IsObject(MyWorkPool))
                MyWorkPool.BroadcastConfigRefresh()
        } catch {
        }
        return CommandStr
    }
}
