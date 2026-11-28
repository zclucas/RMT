#Requires AutoHotkey v2.0

; =====================================================================
; 文本处理编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class TextOpsGui {
    _autoRemark := ""
    _playHotkeys := []
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
        this.ConcatEditGui := ""
        this._concatEditClosed := true
        this._timestampDragFrom := 0
        this._timestampDragLabel := ""
        this._timestampDragTick := ObjBindMethod(this, "_FollowTimestampDrag")

        this.ArgsTipMap := Map(
            GetLang("内容分割"), GetLang("分割文本："),
            GetLang("定长分割"), GetLang("分割长度："),
            GetLang("正则匹配"), GetLang("正则表达式："))
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

    _AddLabel(parent, text, margin := "0,0,0,0") {
        return parent.Add("TextBlock").Text(text).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize(CmdEditorForm.FontSize()).Margin(margin)
            .TextWrapping("NoWrap")
    }

    _StyleBox(el, width := "") {
        el.Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize(CmdEditorForm.FontSize()).Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (width != "")
            el.Width(width)
        return el
    }

    _StyleCombo(el, width := "") {
        el.Height(26).MinHeight(26).VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize(CmdEditorForm.FontSize())
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (width != "")
            el.Width(width)
        return el
    }

    _Vis(name, show, collapse := true) {
        vis := show ? "Visible" : (collapse ? "Collapsed" : "Hidden")
        this._ComboPush(name, "Visibility", vis)
    }

    static TimestampSlotWidth := 70
    static TimestampButtonWidth := 40
    static TimestampMillisecondsWidth := 45

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("文本处理编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(CmdEditorForm.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容：统一 90 / * / 10 / 90 / * ===
        body := main.Add("Grid").Grid_Row(1).Margin("12,8,12,10")
        body.Rows("Auto", "Auto", "Auto", "48")

        topCard := body.Add("Border").Grid_Row(0).CornerRadius("8").Padding("12,10,12,12").Margin("0,0,0,8")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        top := topCard.Add("Grid")
        top.Rows("36", "36")
        top.Cols(CmdEditorForm.PairColumns()*)

        this._AddLabel(top, GetLang("备注：")).Grid_Row(0).Grid_Column(0)
        this._StyleBox(top.Add("TextBox").Name("RemarkCon").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(4))

        this._AddLabel(top, GetLang("处理类型:")).Grid_Row(1).Grid_Column(0)
        tc := this._StyleCombo(top.Add("ComboBox").Name("TypeCombo").Grid_Row(1).Grid_Column(1))
        for t in GetLangArr(TextOpsTypeNames())
            tc.Add("ComboBoxItem").Content(t)
        this._AddLabel(top, GetLang("文本来源:")).Grid_Row(1).Grid_Column(3).Name("NameTip")
        this._StyleCombo(top.Add("ComboBox").Name("NameCon").Grid_Row(1).Grid_Column(4).IsEditable("True"))
        concatSource := this._StyleCombo(top.Add("ComboBox").Name("ConcatSource").Grid_Row(1).Grid_Column(4))
        for mode in GetLangArr(TextOpsModes("文本拼接"))
            concatSource.Add("ComboBoxItem").Content(mode)

        paramCard := body.Add("Border").Grid_Row(1).CornerRadius("8").Padding("12,8,12,8").Margin("0,0,0,8")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        param := paramCard.Add("Grid")
        param.Rows("36", "36", "12")
        param.Cols(CmdEditorForm.PairColumns()*)

        argsGrid := param.Add("Grid").Name("ArgsGrid").Grid_Row(0).Grid_RowSpan(2).Grid_ColumnSpan(5)
        argsGrid.Rows("36", "36")
        argsGrid.Cols(CmdEditorForm.PairColumns()*)
        this._AddLabel(argsGrid, GetLang("类型选项:")).Grid_Row(0).Grid_Column(0)
        this._StyleCombo(argsGrid.Add("ComboBox").Name("ArgsTypeCombo").Grid_Row(0).Grid_Column(1))
        this._AddLabel(argsGrid, GetLang("类型参数:")).Grid_Row(0).Grid_Column(3).Name("ArgsNameTip")
        this._StyleCombo(argsGrid.Add("ComboBox").Name("ArgsNameCon").Grid_Row(0).Grid_Column(4).IsEditable("True"))

        searchRow := argsGrid.Add("Grid").Name("SearchRow").Grid_Row(1).Grid_ColumnSpan(5).Visibility("Hidden")
        searchRow.Cols(CmdEditorForm.PairColumns()*)
        this._AddLabel(searchRow, GetLang("查找文本:")).Grid_Column(0)
        this._StyleCombo(searchRow.Add("ComboBox").Name("SearchCon").Grid_Column(1).IsEditable("True"))
        this._AddLabel(searchRow, GetLang("替换文本:")).Grid_Column(3)
        this._StyleCombo(searchRow.Add("ComboBox").Name("ReplaceCon").Grid_Column(4).IsEditable("True"))

        this._AddLabel(argsGrid, GetLang("时间量：")).ToolTip(GetLang("选择要从时间戳中提取的部分，例如年或月。")).Grid_Column(3).Name("TimestampComponentLabel").Visibility("Collapsed")
        componentCombo := this._StyleCombo(argsGrid.Add("ComboBox").Name("TimestampComponent").Grid_Column(4).Visibility("Collapsed"))
        for label in TextOpsTimestampComponentLabels()
            componentCombo.Add("ComboBoxItem").Content(label)
        componentCombo.SelectedIndex(0)
        this._AddLabel(argsGrid, "").Name("TimestampPresetHint").Grid_Column(3).Grid_ColumnSpan(2).Visibility("Collapsed")

        formatRow := param.Add("StackPanel").Name("TimestampFormatRow").Grid_Row(1).Grid_ColumnSpan(5)
            .Orientation("Horizontal").HorizontalAlignment("Center").Background("Transparent")
            .Visibility("Collapsed").InjectResources(XamlTabOptionStyle(false))
        for i, component in TextOpsTimestampComponents() {
            pair := formatRow.Add("StackPanel").Name("TimestampPair" i).Orientation("Horizontal")
            pair.Add("ToggleButton").Name("TimestampField" i).Content(component[2]).Width(TextOpsGui.TimestampButtonWidth).Height("26")
                .Margin("0,0,2,0").VerticalAlignment("Center").Style("{StaticResource SetTabButton}")
            this._StyleBox(pair.Add("TextBox").Name("TimestampSuffix" i), "25")
                .Padding("0").TextAlignment("Center").Visibility("Collapsed")
                .ToolTip(GetLang("此时间量后的文本"))
        }

        concatRow := param.Add("Grid").Name("ConcatRow").Grid_Row(0).Grid_RowSpan(3).Grid_ColumnSpan(5).Visibility("Collapsed")
        concatRow.Add("TextBox").Name("ConcatCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch").MinHeight("84")
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize(CmdEditorForm.FontSize())
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        concatRow.Add("Button").Name("BtnConcatEdit").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        concatArrayRow := param.Add("Grid").Name("ConcatArrayRow").Grid_Row(0).Grid_ColumnSpan(5).Visibility("Collapsed")
        concatArrayRow.Cols(CmdEditorForm.PairColumns()*)
        this._AddLabel(concatArrayRow, GetLang("数组名：")).Grid_Column(0)
        this._StyleCombo(concatArrayRow.Add("ComboBox").Name("ConcatArrayName").Grid_Column(1).IsEditable("True"))
        this._AddLabel(concatArrayRow, GetLang("拼接符号：")).Grid_Column(3)
        this._StyleCombo(concatArrayRow.Add("ComboBox").Name("ConcatSeparator").Grid_Column(4).IsEditable("True"))

        res := body.Add("Grid").Grid_Row(2).Margin("13,0,13,0")
        res.Cols(CmdEditorForm.LabelWidth(), 96, 16, "*")
        res.Rows("36")
        this._AddLabel(res, GetLang("结果：")).Grid_Column(0)
        st := this._StyleCombo(res.Add("ComboBox").Name("SaveTypeCombo").Grid_Column(1).IsEnabled("False"))
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        this._StyleCombo(res.Add("ComboBox").Name("SaveNameCon").Grid_Column(3).IsEditable("True"))
            .HorizontalAlignment("Left")

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="' CmdEditorForm.Width '" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/18-文本处理", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("ArgsTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshArgsType"))
        this.ui.OnEvent("ConcatSource", "SelectionChanged", ObjBindMethod(this, "OnRefreshConcatSource"))
        this.ui.OnEvent("BtnConcatEdit", "Click", ObjBindMethod(this, "OpenConcatEditor"))
        this.ui.OnEvent("TimestampFormatRow", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnTimestampFormatDown"))
        this.ui.OnEvent("TimestampFormatRow", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "_OnTimestampFormatUp"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._playHotkeys := WinHotkey.Register(["!l"], XamlWin.BindCurrent(this, "TriggerMacro"), this.Hwnd())
    }

    OnWindowClosing(state, ctrl, event) {
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        this._EndTimestampDrag()
        this._CloseConcatEditor()
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
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        this._EndTimestampDrag()
        this._CloseConcatEditor()
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
        text := GetVariableComboText(items, text)
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

    _SetArgsNameCombo(value) {
        items := this.ArgsNameOptions.Clone()
        if (this._activeType == "文本分割" && this._activeMode == "内容分割") {
            for i, option in TextOpsSeparatorOptions()
                items.InsertAt(i, GetLang(option[1]))
            value := TextOpsSeparatorText(value, true)
        } else if (value == "`t") {
            value := GetLang("制表符")
        }
        this._SetCombo("ArgsNameCon", items, GetBuiltinVarName(value, true))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : AllocateCommandSerial("文本处理")
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this._autoRemark := ReadCommandAutoRemark(this.Data, GenerateCommandAutoRemark)
        ; 旧替换指令以 MatchType 为准，ArgsType 可能仍为旧默认值。
        if (this.Data.Type == "文本替换")
            this.Data.ArgsType := this.Data.MatchType
        this.DLArrayArr := GetArrayVariableNames()
        this.ArgsNameOptions := GetGuiVarArr("clipboard")
        this._activeType := this.Data.Type
        this._activeMode := this.Data.ArgsType
        isConcat := this._activeType == "文本拼接"
        this._concatMode := isConcat && this.Data.ArgsType == "数组" ? "数组" : "自定义"
        isArray := this._concatMode == "数组"
        this._concatPrefix := isConcat && !isArray ? this.Data.Name : ""

        this._SetDDL("TypeCombo", GetLangArr(TextOpsTypeNames()), GetLang(this.Data.Type))
        this._SetTextSource(this.Data.Name)
        this._SetArgsNameCombo(this.Data.ArgsName)
        this._ComboPush("ConcatSource", "SelectedIndex", isArray ? "1" : "0")
        this._ComboPush("ConcatCon", "Text", isConcat && !isArray ? this.Data.ArgsName : TextOpsDefaultArgs("文本拼接", "自定义"))
        this._SetCombo("ConcatArrayName", this.DLArrayArr, isArray ? this.Data.Name : "")
        this._SetCombo("ConcatSeparator", TextOpsSeparatorChoices(),
            isArray ? TextOpsSeparatorText(this.Data.ArgsName, true) : TextOpsDefaultArgs("文本拼接", "数组"))
        this._SetCombo("SearchCon", GetGuiVarArr("text"), GetBuiltinVarName(this.Data.Search, true))
        this._SetCombo("ReplaceCon", GetGuiVarArr("text"), GetBuiltinVarName(this.Data.Replace, true))
        this._timestampParts := TextOpsTimestampFormatParts(this.Data)
        this._ShowTimestampParts()
        this._ComboPush("TimestampComponent", "SelectedIndex", TextOpsTimestampComponentIndex(this.Data.ArgsName))
        this._RefreshTypeControls()
        this._RefreshModeControls(this.Data.SaveName)
    }

    _ShowTimestampParts() {
        components := TextOpsTimestampComponents()
        labels := TextOpsTimestampComponentLabels()
        batch := []
        for i, part in this._timestampParts {
            field := "TimestampField" i
            batch.Push({ControlName: field, PropertyName: "Content", Value: components[part.Index][2]})
            batch.Push({ControlName: field, PropertyName: "ToolTip", Value: labels[part.Index]})
            batch.Push({ControlName: field, PropertyName: "IsChecked", Value: part.Enabled ? "True" : "False"})
            suffix := "TimestampSuffix" i
            width := this._TimestampPartWidth(part)
            batch.Push({ControlName: "TimestampPair" i, PropertyName: "Width", Value: width})
            batch.Push({ControlName: suffix, PropertyName: "Text", Value: part.Suffix})
            batch.Push({ControlName: suffix, PropertyName: "Visibility", Value: width == TextOpsGui.TimestampMillisecondsWidth ? "Collapsed" : "Visible"})
        }
        if (this._batching) {
            for update in batch
                this._batch.Push(update)
        } else {
            this.ui.BatchUpdate(batch)
        }
    }

    _ReadTimestampParts() {
        names := []
        loop this._timestampParts.Length
            names.Push("TimestampField" A_Index, "TimestampSuffix" A_Index)
        state := this.ui.Query(names*)
        for i, part in this._timestampParts {
            part.Enabled := state["TimestampField" i] == "True"
            part.Suffix := state["TimestampSuffix" i]
        }
    }

    _TimestampPartWidth(part) {
        return part.Index == TextOpsTimestampComponents().Length ? TextOpsGui.TimestampMillisecondsWidth : TextOpsGui.TimestampSlotWidth
    }

    _TimestampSlotAt(state, buttonOnly := false) {
        coords := StrSplit(state.Get("TimestampFormatRow", ""), ",")
        if (coords.Length != 2)
            return 0
        x := Integer(coords[1]), y := Integer(coords[2])
        if (x < 0 || y < 0 || y >= 36)
            return 0
        for i, part in this._timestampParts {
            width := this._TimestampPartWidth(part)
            if (x < width)
                return !buttonOnly || x < TextOpsGui.TimestampButtonWidth ? i : 0
            x -= width
        }
        return 0
    }

    _OnTimestampFormatDown(state, *) {
        this._EndTimestampDrag()
        slot := this._TimestampSlotAt(state, true)
        if (!slot || !IsObject(this.ui))
            return
        this._timestampDragFrom := slot
        CoordMode("Mouse", "Screen")
        MouseGetPos(&startX, &startY)
        this._timestampDragStart := {X: startX, Y: startY}
        SetTimer(this._timestampDragTick, 16)
    }

    _FollowTimestampDrag() {
        Critical()
        if (!GetKeyState("LButton", "P")) {
            ; 松手后立即收起浮标，落点仍由 XAML 的抬起事件处理。
            SetTimer(this._timestampDragTick, 0)
            this._DestroyTimestampDragLabel()
            return
        }
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        start := this._timestampDragStart
        if (!IsObject(this._timestampDragLabel)) {
            if (Max(Abs(x - start.X), Abs(y - start.Y)) < 5)
                return
            component := TextOpsTimestampComponents()[this._timestampParts[this._timestampDragFrom].Index]
            colors := MainSoftData.ThemeColors
            bg := AppThemeUtil.ArgbToRgb6(AppThemeUtil.ResolveColor(colors, "Win_ActionBg"))
            fg := AppThemeUtil.ArgbToRgb6(AppThemeUtil.ResolveColor(colors, "Win_ActionText"))
            label := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x08000020")
            label.BackColor := bg
            label.MarginX := 0
            label.MarginY := 0
            label.SetFont("s10 Bold c" fg, MainSoftData.FontType)
            label.AddText("w40 h24 Center +0x200", component[2])
            this._timestampDragLabel := label
            WinSetTransparent(240, label.Hwnd)
            label.Show("Hide AutoSize")
        }
        ; 屏幕坐标直接交给 Win32，避免原生 GUI 把坐标再次按 DPI 缩放。
        DllCall("user32\SetWindowPos", "Ptr", this._timestampDragLabel.Hwnd, "Ptr", -1,
            "Int", x + 12, "Int", y + 16, "Int", 0, "Int", 0, "UInt", 0x0051)
    }

    _DestroyTimestampDragLabel() {
        if (IsObject(this._timestampDragLabel)) {
            this._timestampDragLabel.Destroy()
            this._timestampDragLabel := ""
        }
    }

    _EndTimestampDrag() {
        SetTimer(this._timestampDragTick, 0)
        this._timestampDragFrom := 0
        this._DestroyTimestampDragLabel()
    }

    _OnTimestampFormatUp(state, *) {
        from := this._timestampDragFrom
        this._EndTimestampDrag()
        if (!from || !IsObject(this.ui))
            return
        target := this._TimestampSlotAt(state)
        if (!target || target == from)
            return
        this._ReadTimestampParts()
        part := this._timestampParts[from]
        this._timestampParts[from] := this._timestampParts[target]
        this._timestampParts[target] := part
        this._ShowTimestampParts()
    }

    OnRefresh(*) {
        if (!IsObject(this.ui))
            return
        type := GetLangKey(this._TypeText())
        if (type == "" || type == this._activeType)
            return
        saveName := this.ui.Query("SaveNameCon")
        this._activeType := type
        this._activeMode := TextOpsDefaultMode(type)
        this._SetTextSource(TextOpsDefaultSource(type))
        this._SetArgsNameCombo(TextOpsDefaultArgs(type, this._activeMode))
        this._RefreshTypeControls()
        this._RefreshModeControls(saveName)
    }

    _SetTextSource(value) {
        options := this._activeType == "时间戳处理" ? GetGuiVarArr("timestamp") : GetGuiVarArr("text")
        this._SetCombo("NameCon", options, GetBuiltinVarName(value, true))
    }

    _RefreshTypeControls() {
        type := this._activeType
        isConcat := type == "文本拼接"
        isReplace := type == "文本替换"
        if (!isConcat)
            this._SetDDL("ArgsTypeCombo", GetLangArr(TextOpsModes(type)), GetLang(this._activeMode))
        this._ComboPush("NameTip", "Text", GetLang(type == "时间戳处理" ? "时间戳：" : "文本来源:"))
        this._Vis("NameCon", !isConcat)
        this._Vis("ConcatSource", isConcat)
        this._Vis("ArgsGrid", !isConcat)
        this._Vis("SearchRow", isReplace, false)
        this._RefreshConcatSource()
    }

    OnRefreshConcatSource(*) {
        if (!IsObject(this.ui))
            return
        this._concatMode := GetLangKey(this.ui.Query("ConcatSource"))
        this._RefreshConcatSource()
    }

    _RefreshConcatSource() {
        isConcat := this._activeType == "文本拼接"
        isArray := this._concatMode == "数组"
        this._Vis("ConcatRow", isConcat && !isArray)
        this._Vis("ConcatArrayRow", isConcat && isArray)
    }

    OnRefreshArgsType(*) {
        if (!IsObject(this.ui) || this._activeType == "文本拼接")
            return
        mode := GetLangKey(this._ArgsTypeText())
        if (mode == "" || mode == this._activeMode)
            return
        this._activeMode := mode
        this._SetArgsNameCombo(TextOpsDefaultArgs(this._activeType, mode))
        this._RefreshModeControls(this.ui.Query("SaveNameCon"))
    }

    _RefreshModeControls(saveName) {
        type := this._activeType
        mode := this._activeMode
        this._ComboPush("ArgsNameTip", "Text", this.ArgsTipMap.Get(GetLang(mode), GetLang("类型参数:")))
        showArgs := type == "文本分割" || (type == "文本提取" && mode == "正则匹配")
        this._Vis("ArgsNameTip", showArgs, false)
        this._Vis("ArgsNameCon", showArgs, false)
        isTimestamp := type == "时间戳处理"
        showComponent := isTimestamp && mode == "提取时间量"
        this._Vis("TimestampComponentLabel", showComponent)
        this._Vis("TimestampComponent", showComponent)
        showFormat := isTimestamp && mode == "自定义格式"
        this._Vis("TimestampFormatRow", showFormat)
        if (!showFormat)
            this._EndTimestampDrag()
        preset := isTimestamp ? TextOpsTimestampPresetFormat(mode) : ""
        this._ComboPush("TimestampPresetHint", "Text", preset)
        this._Vis("TimestampPresetHint", preset != "")
        isArray := TextOpsResultType(type, mode) == "数组"
        this._ComboPush("SaveTypeCombo", "SelectedIndex", isArray ? "1" : "0")
        this._SetCombo("SaveNameCon", isArray ? this.DLArrayArr : GetGuiVarArr(), saveName)
    }

    _CloseConcatEditor() {
        if (IsObject(this.ConcatEditGui) && !this._concatEditClosed) {
            try this.ConcatEditGui.Update("Window", "Close", "")
            this.ConcatEditGui := ""
            this._concatEditClosed := true
        }
    }

    OpenConcatEditor(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ConcatEditGui) || this._concatEditClosed)
            this._BuildConcatEditor()
        this._FillConcatEditNameCombo()
        curText := IsObject(this.ui) ? this.ui.Query("ConcatCon") : ""
        this.ConcatEditGui.Update("ConcatEditCon", "Text", curText)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        if (!XamlWin.Open(this.ConcatEditGui, "", owner))
            this._concatEditClosed := true
    }

    _BuildConcatEditor() {
        global MySoftData
        this._CloseConcatEditor()
        this._concatEditClosed := false
        title := this.ParentTile GetLang("文本构造")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(CmdEditorForm.FontSize())
        main.Rows(titleHeight, "*")
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,8").ClipToBounds("False")
        body.Rows("Auto", "6", "32", "48")

        body.Add("TextBox").Grid_Row(0).Name("ConcatEditCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2,3").FontSize(CmdEditorForm.FontSize())
            .Height("95").MinHeight("95")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        row1 := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        row1.Cols("88", "80", "8", "200", "8", "70", "8", "70")
        row1.Add("TextBlock").Grid_Column(0).Text(GetLang("变量数组：")).ToolTip(GetLang("追加名插入名称，追加值在执行时取值。")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize(CmdEditorForm.FontSize())
        vt := row1.Add("ComboBox").Grid_Column(1).Name("ConcatEditVarTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center").SelectedIndex("0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        row1.Add("ComboBox").Grid_Column(3).Name("ConcatEditVariCombo").Width("200").Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left").IsEditable("True")
        row1.Add("Button").Grid_Column(5).Name("BtnConcatAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).VerticalAlignment("Center")
        row1.Add("Button").Grid_Column(7).Name("BtnConcatAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).VerticalAlignment("Center")

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnConcatOk")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        this.ConcatEditGui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        this.ConcatEditGui.xaml := StrReplace(this.ConcatEditGui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="580" SizeToContent="Height"')
        this.ConcatEditGui.xaml := StrReplace(this.ConcatEditGui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ConcatEditGui.xaml := StrReplace(this.ConcatEditGui.xaml, '%resources%', '')

        this.ConcatEditGui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnConcatEditClosing"))
        this.ConcatEditGui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnConcatEditLoad"))
        this.ConcatEditGui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnConcatEditClose"))
        this.ConcatEditGui.OnEvent("ConcatEditVarTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnConcatEditVarTypeChange"))
        this.ConcatEditGui.OnEvent("BtnConcatAddName", "Click", ObjBindMethod(this, "OnConcatEditAddName"))
        this.ConcatEditGui.OnEvent("BtnConcatAddValue", "Click", ObjBindMethod(this, "OnConcatEditAddValue"))
        this.ConcatEditGui.OnEvent("ConcatEditCon", "TextChanged", ObjBindMethod(this, "OnConcatEditChange"))
        this.ConcatEditGui.OnEvent("BtnConcatOk", "Click", ObjBindMethod(this, "OnConcatEditClose"))
    }

    OnConcatEditLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ConcatEditGui)
    }

    OnConcatEditClosing(state, ctrl, event) {
        this._concatEditClosed := true
        this.ConcatEditGui := ""
    }

    OnConcatEditChange(state := "", ctrl := "", event := "") {
        if (IsObject(this.ConcatEditGui) && !this._concatEditClosed && IsObject(this.ui))
            this.ui.Update("ConcatCon", "Text", this.ConcatEditGui.Query("ConcatEditCon"))
    }

    _FillConcatEditNameCombo() {
        if (!this._concatEditClosed)
            CharVarEditGui.RefreshNameCombo(this.ConcatEditGui, "ConcatEditVarTypeCombo", "ConcatEditVariCombo")
    }

    OnConcatEditVarTypeChange(state := "", ctrl := "", event := "") {
        this._FillConcatEditNameCombo()
    }

    OnConcatEditAddName(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ConcatEditGui) || this._concatEditClosed)
            return
        varName := this.ConcatEditGui.Query("ConcatEditVariCombo")
        if (varName != "") {
            this.ConcatEditGui.Update("ConcatEditCon", "InsertText", varName)
            this.OnConcatEditChange()
        }
    }

    OnConcatEditAddValue(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ConcatEditGui) || this._concatEditClosed)
            return
        varName := this.ConcatEditGui.Query("ConcatEditVariCombo")
        if (varName != "") {
            arrMark := this.ConcatEditGui.Query("ConcatEditVarTypeCombo") == GetLang("变量") ? "" : "ε"
            this.ConcatEditGui.Update("ConcatEditCon", "InsertText", "{" arrMark varName "}")
            this.OnConcatEditChange()
        }
    }

    OnConcatEditClose(state := "", ctrl := "", event := "") {
        this._CloseConcatEditor()
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
        if (this._TypeText() == GetLang("文本拼接") && this.ui.Query("ConcatSource") == GetLang("数组")) {
            if (Trim(this.ui.Query("ConcatArrayName")) == "") {
                RmtDialog.Info(GetLang("数组名不能为空"))
                return false
            }
        }
        if (this._TypeText() == GetLang("文本替换")) {
            if (this.ui.Query("SearchCon") == "") {
                RmtDialog.Info(GetLang("搜索文本不能为空"))
                return false
            }
        }
        if (this._TypeText() == GetLang("文本分割")) {
            if (this.ui.Query("ArgsNameCon") == "") {
                RmtDialog.Info(GetLang("类型参数不能为空"))
                return false
            }
        }
        if (this._TypeText() == GetLang("文本提取")) {
            if (this._ArgsTypeText() == GetLang("正则匹配") && this.ui.Query("ArgsNameCon") == "") {
                RmtDialog.Info(GetLang("正则表达式不能为空"))
                return false
            }
        }
        if (this._TypeText() == GetLang("时间戳处理")) {
            if (Trim(this.ui.Query("NameCon")) == "") {
                RmtDialog.Info(GetLang("时间戳不能为空"))
                return false
            }
            if (this._ArgsTypeText() == GetLang("自定义格式")) {
                this._ReadTimestampParts()
                enabled := false
                for part in this._timestampParts
                    enabled := enabled || part.Enabled
                if (!enabled) {
                    RmtDialog.Info(GetLang("请至少选择一个时间量"))
                    return false
                }
            }
        }
        if (!CheckVarNameIfValid(this.ui.Query("SaveNameCon")))
            return false
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.SaveTextOpsData()
        CommandStr := this.GetCommandStr()
        RunEditorMacroPreview(CommandStr)
        Res := ""
        if (this.Data.SaveType == "变量" && MySoftData.VariableMap.Has(this.Data.SaveName))
            Res := MySoftData.VariableMap[this.Data.SaveName]
        if (this.Data.SaveType == "数组" && MySoftData.ArrayMap.Has(this.Data.SaveName))
            Res := FormatArrayText(MySoftData.ArrayMap[this.Data.SaveName])
        if (Res != "") {
            tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
            tip2 := Format(GetLang("值：{}"), Res)
            RmtDialog.Info(tip1 "`n" tip2)
        }
    }

    GetCommandStr() {
        return FormatCommandAutoRemark(this.Data, this.ui.Query("RemarkCon"), this._autoRemark, GenerateCommandAutoRemark, false)
    }

    SaveTextOpsData() {
        this.Data.Type := GetLangKey(this._TypeText())
        if (this.Data.Type == "文本拼接") {
            if (this.ui.Query("ConcatSource") == GetLang("数组")) {
                this.Data.ArgsType := "数组"
                this.Data.Name := Trim(this.ui.Query("ConcatArrayName"))
                ArgsName := TextOpsSeparatorText(this.ui.Query("ConcatSeparator"))
            } else {
                this.Data.ArgsType := "拼接文本"
                this.Data.Name := this._concatPrefix
                ArgsName := this.ui.Query("ConcatCon")
            }
        } else {
            this.Data.ArgsType := GetLangKey(this._ArgsTypeText())
            this.Data.Name := GetBuiltinVarName(this.ui.Query("NameCon"))
            ArgsName := GetBuiltinVarName(this.ui.Query("ArgsNameCon"))
            if (this.Data.Type == "文本分割" && this.Data.ArgsType == "内容分割")
                ArgsName := TextOpsSeparatorText(ArgsName)
        }
        if (this.Data.Type == "时间戳处理" && this.Data.ArgsType == "提取时间量") {
            componentIndex := this.ui.Query("TimestampComponent>SelectedIndex")
            ArgsName := TextOpsTimestampComponents()[Integer(componentIndex) + 1][1]
        }
        if (this.Data.Type == "时间戳处理" && this.Data.ArgsType == "自定义格式") {
            this.Data.TimestampFormatParts := []
            for part in this._timestampParts
                this.Data.TimestampFormatParts.Push(part.Clone())
        }
        this.Data.ArgsName := ArgsName
        this.Data.Search := GetBuiltinVarName(this.ui.Query("SearchCon"))
        this.Data.Replace := GetBuiltinVarName(this.ui.Query("ReplaceCon"))
        if (this.Data.Type == "文本替换")
            this.Data.MatchType := this.Data.ArgsType
        this.Data.SaveType := TextOpsResultType(this.Data.Type, this.Data.ArgsType)
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        if (this.Data.SaveType == "变量")
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        if (this.Data.SaveType == "数组")
            MySoftData.GlobalArrMap[this.Data.SaveName] := true
        FormatCommandAutoRemark(this.Data, this.ui.Query("RemarkCon"), this._autoRemark, GenerateCommandAutoRemark, true)
        SaveMacroCMDData(this.Data)
    }
}
