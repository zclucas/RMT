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
        this.ConcatEditGui := ""
        this._concatEditClosed := true
        this._timestampDragFrom := 0
        this._timestampDragLabel := ""
        this._timestampDragTick := ObjBindMethod(this, "_FollowTimestampDrag")

        this.ArgsTypeMap := Map(
            GetLang("去除空格"), [GetLang("去除前空白字符"), GetLang("去除后空白字符"), GetLang("去除前后空白字符"), GetLang("去除所有空白字符")],
            GetLang("大小写转换"), [GetLang("全部大写"), GetLang("全部小写"), GetLang("首字母大写")],
            GetLang("文本统计"), [GetLang("字符数"), GetLang("单词数"), GetLang("行数")],
            GetLang("文本提取"), [GetLang("数字提取"), GetLang("字母提取"), GetLang("中文提取"), GetLang("正则匹配")],
            GetLang("文本分割"), [GetLang("内容分割"), GetLang("定长分割"), GetLang("正则匹配")],
            GetLang("文本替换"), [GetLang("普通文本"), GetLang("正则匹配")],
            GetLang("时间戳处理"), GetLangArr(TextOpsTimestampModes()),
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
            .Foreground("{DynamicResource TextMain}").FontSize("12").Margin(margin)
            .TextWrapping("NoWrap")
    }

    _StyleBox(el, width := "") {
        el.Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (width != "")
            el.Width(width)
        return el
    }

    _StyleCombo(el, width := "") {
        el.Height(26).MinHeight(26).VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
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

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
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
        top.Cols("90", "*", "10", "90", "*")

        this._AddLabel(top, GetLang("备注：")).Grid_Row(0).Grid_Column(0)
        this._StyleBox(top.Add("TextBox").Name("RemarkCon").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(4))

        this._AddLabel(top, GetLang("处理类型:")).Grid_Row(1).Grid_Column(0)
        tc := this._StyleCombo(top.Add("ComboBox").Name("TypeCombo").Grid_Row(1).Grid_Column(1))
        for t in GetLangArr(TextOpsTypeNames())
            tc.Add("ComboBoxItem").Content(t)
        this._AddLabel(top, GetLang("文本来源:")).Grid_Row(1).Grid_Column(3).Name("NameTip")
        this._StyleCombo(top.Add("ComboBox").Name("NameCon").Grid_Row(1).Grid_Column(4).IsEditable("True"))

        paramCard := body.Add("Border").Grid_Row(1).CornerRadius("8").Padding("12,8,12,8").Margin("0,0,0,8")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        param := paramCard.Add("Grid")
        param.Rows("36", "36", "12")
        param.Cols("90", "*", "10", "90", "*")

        argsGrid := param.Add("Grid").Name("ArgsGrid").Grid_Row(0).Grid_RowSpan(2).Grid_ColumnSpan(5)
        argsGrid.Rows("36", "36")
        argsGrid.Cols("90", "*", "10", "90", "*")
        this._AddLabel(argsGrid, GetLang("类型选项:")).Grid_Row(0).Grid_Column(0)
        this._StyleCombo(argsGrid.Add("ComboBox").Name("ArgsTypeCombo").Grid_Row(0).Grid_Column(1))
        this._AddLabel(argsGrid, GetLang("类型参数:")).Grid_Row(0).Grid_Column(3).Name("ArgsNameTip")
        this._StyleCombo(argsGrid.Add("ComboBox").Name("ArgsNameCon").Grid_Row(0).Grid_Column(4).IsEditable("True"))

        searchRow := argsGrid.Add("Grid").Name("SearchRow").Grid_Row(1).Grid_ColumnSpan(5).Visibility("Hidden")
        searchRow.Cols("90", "*", "10", "90", "*")
        this._AddLabel(searchRow, GetLang("查找文本:")).Grid_Column(0)
        this._StyleCombo(searchRow.Add("ComboBox").Name("SearchCon").Grid_Column(1).IsEditable("True"))
        this._AddLabel(searchRow, GetLang("替换文本:")).Grid_Column(3)
        this._StyleCombo(searchRow.Add("ComboBox").Name("ReplaceCon").Grid_Column(4).IsEditable("True"))

        this._AddLabel(argsGrid, GetLang("时间量：")).Grid_Column(3).Name("TimestampComponentLabel").Visibility("Collapsed")
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
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        concatRow.Add("Button").Name("BtnConcatEdit").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        res := body.Add("Grid").Grid_Row(2).Margin("12,0,12,0")
        res.Cols("90", "96", "10", "160")
        res.Rows("36")
        this._AddLabel(res, GetLang("结果：")).Grid_Column(0)
        st := this._StyleCombo(res.Add("ComboBox").Name("SaveTypeCombo").Grid_Column(1).IsEnabled("False"))
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        this._StyleCombo(res.Add("ComboBox").Name("SaveNameCon").Grid_Column(3).IsEditable("True"), "160")
            .HorizontalAlignment("Left")

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/18-文本处理", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("ArgsTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshArgsType"))
        this.ui.OnEvent("ArgsNameCon", "TextChanged", ObjBindMethod(this, "OnArgsNameConChange"))
        this.ui.OnEvent("BtnConcatEdit", "Click", ObjBindMethod(this, "OpenConcatEditor"))
        this.ui.OnEvent("TimestampFormatRow", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnTimestampFormatDown"))
        this.ui.OnEvent("TimestampFormatRow", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "_OnTimestampFormatUp"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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

    _ConcatDefaultText() {
        return "{当前年}{当前月}{当前日}"
    }

    _IsConcatPlaceholder(s) {
        s := Trim(s)
        return s == "" || s == ","
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("文本处理")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        ; 旧替换指令以 MatchType 为准，ArgsType 可能仍为旧默认值。
        if (this.Data.Type == "文本替换")
            this.Data.ArgsType := this.Data.MatchType
        this.DLArrayArr := GetGuiArrNameArr()
        ArgsNameArr := GetGuiVarArr("clipboard")
        ArgsNameArr.InsertAt(1, GetLang("制表符"))
        this.ArgsNameOptions := ArgsNameArr.Clone()

        this._SetDDL("TypeCombo", GetLangArr(TextOpsTypeNames()), GetLang(this.Data.Type))
        this._SetCombo("NameCon", GetGuiVarArr("text"), GetBuiltinVarName(this.Data.Name, true))
        concatArgs := this.Data.ArgsName
        if (cmd == "" && GetLang(this.Data.Type) == GetLang("文本拼接") && this._IsConcatPlaceholder(concatArgs))
            concatArgs := this._ConcatDefaultText()
        this._SetCombo("ArgsNameCon", ArgsNameArr, GetBuiltinVarName(concatArgs, true))
        this.ui.Update("ConcatCon", "Text", concatArgs)
        this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
        this._SetCombo("SearchCon", GetGuiVarArr("text"), GetBuiltinVarName(this.Data.Search, true))
        this._SetCombo("ReplaceCon", GetGuiVarArr("text"), GetBuiltinVarName(this.Data.Replace, true))
        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), GetLang(this.Data.SaveType))
        this._SetCombo("SaveNameCon", this.DLArrayArr, this.Data.SaveName)

        this._timestampParts := TextOpsTimestampFormatParts(this.Data)
        this._ShowTimestampParts()
        this._ComboPush("TimestampComponent", "SelectedIndex", TextOpsTimestampComponentIndex(this.Data.ArgsName))
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
        IsTimestamp := typeText == GetLang("时间戳处理")
        IsConcat := typeText == GetLang("文本拼接")

        ArgsDLArr := []
        if (this.ArgsTypeMap.Has(typeText)) {
            ArgsDLArr := this.ArgsTypeMap[typeText]
            selected := IsTimestamp && this.Data.Type != "时间戳处理" ? "自定义格式" : this.Data.ArgsType
            this._SetDDL("ArgsTypeCombo", ArgsDLArr, GetLang(selected))
        }

        ShowArgsType := IsSplit || IsGetEx || IsUpLow || IsSpace || IsStatistics || IsReplace || IsTimestamp
        this.ui.Update("NameTip", "Text", GetLang(IsTimestamp ? "时间戳：" : "文本来源:"))
        this._SetCombo("NameCon", IsTimestamp ? GetGuiVarArr("timestamp") : GetGuiVarArr("text"), this.ui.Query("NameCon"))
        this.ui.Update("ArgsTypeCombo", "IsEnabled", ShowArgsType ? "True" : "False")
        this._Vis("NameTip", !IsConcat, true)
        this._Vis("NameCon", !IsConcat, true)
        this._Vis("ArgsGrid", !IsConcat, true)
        this._Vis("ConcatRow", IsConcat, true)
        this._Vis("SearchRow", IsReplace, false)
        this.ui.Update("SearchCon", "IsEnabled", IsReplace ? "True" : "False")
        this.ui.Update("ReplaceCon", "IsEnabled", IsReplace ? "True" : "False")

        this.OnRefreshArgsType()
    }

    OnRefreshArgsType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        mode := this._ArgsTypeText()
        tipText := this.ArgsTipMap.Get(mode, GetLang("类型参数:"))
        this.ui.Update("ArgsNameTip", "Text", tipText)
        this.lastArgsNameConText := this.ui.Query("ArgsNameCon")
        typeText := this._TypeText()
        IsSplit := typeText == GetLang("文本分割")
        IsGetEx := typeText == GetLang("文本提取")
        IsGetExReg := IsGetEx && mode == GetLang("正则匹配")
        ShowArgsName := IsSplit || IsGetExReg
        this._Vis("ArgsNameTip", ShowArgsName, false)
        this._Vis("ArgsNameCon", ShowArgsName, false)
        this.ui.Update("ArgsNameCon", "IsEnabled", ShowArgsName ? "True" : "False")
        isTimestamp := typeText == GetLang("时间戳处理")
        showComponent := isTimestamp && mode == GetLang("提取时间量")
        this._Vis("TimestampComponentLabel", showComponent)
        this._Vis("TimestampComponent", showComponent)
        showFormat := isTimestamp && mode == GetLang("自定义格式")
        this._Vis("TimestampFormatRow", showFormat)
        if (!showFormat)
            this._EndTimestampDrag()
        modeKey := GetLangKey(mode)
        preset := isTimestamp ? TextOpsTimestampPresetFormat(modeKey) : ""
        this.ui.Update("TimestampPresetHint", "Text", preset)
        this._Vis("TimestampPresetHint", preset != "")
        resultType := TextOpsResultType(GetLangKey(typeText), modeKey)
        this._ComboPush("SaveTypeCombo", "SelectedIndex", resultType == "数组" ? "1" : "0")
        this.OnRefreshDataType()
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
        if (this.ConcatEditGui.Query("ConcatEditVarTypeCombo") == "")
            this.ConcatEditGui.Update("ConcatEditVarTypeCombo", "SelectedIndex", "0")
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

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,8").ClipToBounds("False")
        body.Rows("Auto", "6", "32", "48")

        body.Add("TextBox").Grid_Row(0).Name("ConcatEditCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2,3").FontSize("11")
            .Height("95").MinHeight("95")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        row1 := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        row1.Cols("88", "80", "8", "200", "8", "70", "8", "70")
        row1.Add("TextBlock").Grid_Column(0).Text(GetLang("变量数组：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
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
        if (!IsObject(this.ConcatEditGui) || this._concatEditClosed)
            return
        isVar := this.ConcatEditGui.Query("ConcatEditVarTypeCombo") == GetLang("变量")
        items := isVar ? GetGuiVarArr("all") : GetGuiArrNameArr()
        cur := this.ConcatEditGui.Query("ConcatEditVariCombo")
        this.ConcatEditGui.Update("ConcatEditVariCombo", "ClearItems", "")
        for v in items {
            if (v != "")
                this.ConcatEditGui.Update("ConcatEditVariCombo", "AddItem", v)
        }
        found := false
        loop items.Length {
            if (items[A_Index] == cur) {
                this.ConcatEditGui.Update("ConcatEditVariCombo", "SelectedIndex", String(A_Index - 1))
                found := true
                break
            }
        }
        if (!found && items.Length > 0)
            this.ConcatEditGui.Update("ConcatEditVariCombo", "SelectedIndex", "0")
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
        OnTriggerSepcialItemMacro(CommandStr)
        Res := ""
        if (this.Data.SaveType == "变量" && MySoftData.VariableMap.Has(this.Data.SaveName))
            Res := MySoftData.VariableMap[this.Data.SaveName]
        if (this.Data.SaveType == "数组" && MySoftData.ArrayMap.Has(this.Data.SaveName))
            Res := GetArrayStr(MySoftData.ArrayMap[this.Data.SaveName])
        if (Res != "") {
            tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
            tip2 := Format(GetLang("值：{}"), Res)
            RmtDialog.Info(tip1 "`n" tip2)
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
        isConcat := this._TypeText() == GetLang("文本拼接")
        if (isConcat) {
            ArgsName := this.ui.Query("ConcatCon")
        } else {
            ArgsName := this.ui.Query("ArgsNameCon")
            ArgsName := ArgsName == GetLang("制表符") ? "`t" : ArgsName
        }
        this.Data.Type := GetLangKey(this._TypeText())
        this.Data.Name := isConcat ? "" : GetBuiltinVarName(this.ui.Query("NameCon"))
        this.Data.ArgsType := isConcat ? "拼接文本" : GetLangKey(this._ArgsTypeText())
        if (this.Data.Type == "时间戳处理" && this.Data.ArgsType == "提取时间量") {
            componentIndex := this.ui.Query("TimestampComponent>SelectedIndex")
            ArgsName := TextOpsTimestampComponents()[Integer(componentIndex) + 1][1]
        }
        if (this.Data.Type == "时间戳处理" && this.Data.ArgsType == "自定义格式") {
            this.Data.TimestampFormatParts := []
            for part in this._timestampParts
                this.Data.TimestampFormatParts.Push(part.Clone())
        }
        this.Data.ArgsName := isConcat ? ArgsName : GetBuiltinVarName(ArgsName)
        this.Data.Search := GetBuiltinVarName(this.ui.Query("SearchCon"))
        this.Data.Replace := GetBuiltinVarName(this.ui.Query("ReplaceCon"))
        this.Data.MatchType := GetLangKey(this._ArgsTypeText())
        this.Data.SaveType := TextOpsResultType(this.Data.Type, this.Data.ArgsType)
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        if (this.Data.SaveType == "变量")
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        if (this.Data.SaveType == "数组")
            MySoftData.GlobalArrMap[this.Data.SaveName] := true
        SaveMacroCMDData(this.Data)
    }
}
