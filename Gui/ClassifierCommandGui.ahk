#Requires AutoHotkey v2.0

class ClassifierCommandGui extends CommentGui {
    _pickAction := ""
    HasErrorField := true
    HelpTopic := ""

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang(this.CmdKey)
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")
        this._BuildHeaderFields(body)
        this._BuildFields(body)
        this._BuildResultFields(body)
        CmdEditorForm.Footer(body)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' this._EscapeXml(title) '" Width="620" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent(this.ChoiceField, "SelectionChanged", XamlWin.BindCurrent(this, "OnChoiceChanged"))
        this._BindFields()
        BindCmdEditorChrome(this.ui, "#指令手册/" (this.HelpTopic == "" ? this.CmdKey : this.HelpTopic))
    }

    _BuildHeaderFields(body) => this._Field(body, "备注：", "Remark")

    _BuildResultFields(body) {
        results := body.Add("Grid")
        results.Cols("*", 16, "*")
        this._Variable(results, "保存结果变量：", "ResultVar")
        this._Variable(results, "错误信息变量：", "ErrorVar", 2)
    }

    _Row(body, label, name, labelAlignment := "Center", labelGroup := "CommandLabel", labelTip := "") {
        return CmdEditorForm.Row(body, label, name "Row", labelGroup, labelAlignment, name "Label", labelTip)
    }

    _Field(body, label, name, height := 26) {
        return this._TextBox(this._Row(body, label, name), name, height).Grid_Column(1)
    }

    _TextBox(parent, name, height := 26) => CmdEditorForm.TextBox(parent, name, height)

    _Variable(body, label, name, column := 0) {
        labelGroup := column == 0 ? "CommandLabel" : "CommandRightLabel"
        row := this._Row(body, label, name, "Center", labelGroup).Grid_Column(column)
        CmdEditorForm.Combo(row, name, true).Grid_Column(1)
    }

    _Choice(body, label) {
        name := this.ChoiceField
        combo := CmdEditorForm.Combo(this._Row(body, label, name), name).Grid_Column(1)
        for choice in this.Choices
            combo.Add("ComboBoxItem").Content(GetLang(choice))
    }

    _BindFields() {
    }

    Init(cmd) {
        parts := cmd == "" ? [] : StrSplit(cmd, "_")
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr(this.CmdKey)
        this.Data := GetMacroCMDData(this.SerialStr)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        resultFields := this.HasErrorField ? ["ResultVar", "ErrorVar"] : ["ResultVar"]
        for varName in GetGuiVarArr() {
            for field in resultFields
                this._ComboPush(field, "AddItem", varName)
        }
        for field in this.TextFields
            this._ComboPush(field, "Text", String(this.Data.%field%))
        for field in resultFields
            this._ComboPush(field, "Text", String(this.Data.%field%))
        choiceField := this.ChoiceField
        choice := this._SavedChoice(this.Data.%choiceField%)
        this._ComboPush(this.ChoiceField, "SelectedIndex", CmdEnumIndex(choice, this.Choices))
        this._UpdateChoice(choice)
    }

    _SavedChoice(value) => CmdEnumZh(value, this.Choices)

    _ChoiceValue(text) {
        for choice in this.Choices
            if (GetLang(choice) == text)
                return choice
        return this.Choices[1]
    }

    OnChoiceChanged(*) {
        this._UpdateChoice(this._ChoiceValue(this.ui.Query(this.ChoiceField)))
    }

    _ReadData() {
        data := this.Data.Clone()
        choiceField := this.ChoiceField
        fields := this.TextFields.Clone()
        fields.Push(choiceField, "ResultVar")
        if (this.HasErrorField)
            fields.Push("ErrorVar")
        state := this.ui.Query(fields*)
        for field in this.TextFields
            data.%field% := state[field]
        data.%choiceField% := this._ChoiceValue(state[choiceField])
        data.ResultVar := GetVarName(Trim(state["ResultVar"]))
        if (this.HasErrorField)
            data.ErrorVar := GetVarName(Trim(state["ErrorVar"]))
        CommandTimeoutFields.Read(this.ui, data)
        return data
    }

    CheckIfValid() {
        try {
            data := this._ReadData()
            if (!IsInteger(data.TimeoutMs) || data.TimeoutMs < 1 || data.TimeoutMs > 3600000)
                throw Error(GetLang("超时时间应为 1～3600000 毫秒。"))
            if (data.ResultVar != "" && data.HasOwnProp("ErrorVar") && data.ResultVar = data.ErrorVar)
                throw Error(GetLang("结果变量和错误变量不能相同。"))
            this._Validate(data)
        } catch as e {
            RmtDialog.Info(e.Message, GetLang(this.CmdKey), this.Hwnd())
            return false
        }
        for name in (this.HasErrorField ? [data.ResultVar, data.ErrorVar] : [data.ResultVar])
            if (name != "" && !CheckVarNameIfValid(name))
                return false
        return this._ValidateResultFields(data)
    }

    _ValidateResultFields(data) => true

    SaveData() {
        this.Data := this._ReadData()
        this.Data.TimeoutMs := Integer(this.Data.TimeoutMs)
        RegisterCommandResultVars(this.Data)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang(this.CmdKey) RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }

    _Pick(ui) {
        if (this.ui != ui || this._pickAction != "" || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        while (GetKeyState("LButton", "P") && this.ui == ui)
            Sleep(15)
        if (this.ui != ui || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        result := []
        action := (x1, y1, x2, y2) => result.Push(x1, y1, x2, y2)
        this._pickAction := action
        keys := WinHotkey.Register(["Escape"], this._CancelPick.Bind(this))
        title := "ahk_id " this.Hwnd()
        failure := ""
        try {
            WinHide(title)
            this._PickArea(action)
            if (this.ui == ui && result.Length)
                this._ApplyPick(ui, result)
        } catch as e {
            failure := e.Message
        } finally {
            WinHotkey.UnregisterAll(keys)
            this._pickAction := ""
            if (this.ui == ui) {
                wasDetectingHidden := A_DetectHiddenWindows
                DetectHiddenWindows(true)
                try WinShow(title)
                finally DetectHiddenWindows(wasDetectingHidden)
                try WinActivate(title)
            }
        }
        if (this.ui == ui && failure != "")
            RmtDialog.Info(failure, GetLang(this.CmdKey), this.Hwnd())
    }

    _PickArea(action) {
        TogSelectArea(true, action)
    }

    _CancelPick(*) {
        if (this._pickAction != "" && MainSoftData.SelectAreaAction == this._pickAction)
            TogSelectArea(false)
    }

    OnWindowClosing(state, ctrl, event) {
        this._CancelPick()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        this._CancelPick()
        super._CloseWindow()
    }
}

class WindowControlGui extends ClassifierCommandGui {
    CmdKey := "窗口控件"
    HelpTopic := "35-控件"
    ChoiceField := "ActionType"
    Choices := WindowControl.Actions
    TextFields := ["Selector", "Argument"]

    _PickArea(action) {
        overlay := WindowControlPickOverlay()
        update := overlay.Update.Bind(overlay)
        try {
            SetTimer(update, 40)
            TogSelectArea(true, action, true, true)
        } finally {
            SetTimer(update, 0)
            overlay.Close()
        }
    }

    _BuildFields(body) {
        this._Choice(body, "操作：")
        target := this._Row(body, "目标控件：", "TargetControl", , , GetLang("匹配到多个窗口，请在选择器中填写标题关键词。")).Add("Grid").Grid_Column(1)
        target.Cols("*", 6, "Auto")
        target.Add("Border").Height(26).Padding("4,0")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness(1)
            .Add("TextBlock").Name("TargetSummary").VerticalAlignment("Center").TextTrimming("CharacterEllipsis")
            .Foreground("{DynamicResource TextMain}")
        CmdEditorForm.TextButton(target, "BtnPick", "拾取", "拾取窗口控件").Grid_Column(2)
        detail := this._Row(body, "", "SelectorDetail").Add("StackPanel").Grid_Column(1)
        detail.Add("CheckBox").Name("ShowSelectorDetails").Content(GetLang("选择器详情"))
            .Foreground("{DynamicResource TextMain}")
        box := CmdEditorForm.TextBox(detail, "Selector", 84).FontFamily("Consolas").Margin("0,6,0,0")
        style := box.Add("TextBox.Style").Add("Style").TargetType("TextBox").BasedOn("{StaticResource {x:Type TextBox}}")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        style.Add("Style.Triggers").Add("DataTrigger").Binding("{Binding IsChecked, ElementName=ShowSelectorDetails}").Value("True")
            .Add("Setter").Property("Visibility").Value("Visible")
        this._Field(body, "控件参数：", "Argument")
    }

    _BuildResultFields(body) {
        super._BuildResultFields(body)
        CommandTimeoutFields.Add(body)
    }

    Init(cmd) {
        super.Init(cmd)
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs,
            InputField(this.Data, "TimeoutAction", TimeoutPolicy.DefaultAction),
            InputField(this.Data, "TimeoutStatusVar", TimeoutPolicy.DefaultStatusVar))
        this._UpdateSelectorSummary(this.Data.Selector)
    }

    _ReadData() {
        data := super._ReadData()
        if (!WindowControl.UsesTimeout(data.ActionType))
            data.TimeoutMs := this.Data.TimeoutMs
        return data
    }

    _ValidateResultFields(data) {
        return !WindowControl.UsesTimeout(data.ActionType)
            || CommandTimeoutFields.ValidateStatus(data, data.ResultVar, data.ErrorVar)
    }

    SaveData() {
        super.SaveData()
        if (WindowControl.UsesTimeout(this.Data.ActionType))
            TimeoutPolicy.RegisterStatus(this.Data)
    }

    _BindFields() {
        this.ui.OnEvent("BtnPick", "Click", (*) => SetTimer(this._Pick.Bind(this, this.ui), -1))
        this.ui.OnEvent("Selector", "LostFocus", XamlWin.BindCurrent(this, "OnSelectorChanged"))
    }

    OnSelectorChanged(*) {
        this._UpdateSelectorSummary(this.ui.Query("Selector"))
    }

    _UpdateSelectorSummary(text) {
        summary := GetLang("未拾取控件")
        if (Trim(text) != "") {
            try {
                selector := WindowControl.ParseSelector(text)
                part := selector["path"][-1]
                name := part["name"] != "" ? part["name"] : part["id"]
                summary := selector["exe"] "  /  " (name != "" ? name : part["class"])
            } catch {
                summary := GetLang("控件选择器无效，请重新拾取。")
            }
        }
        this._ComboPush("TargetSummary", "Text", summary)
        this._ComboPush("TargetSummary", "ToolTip", summary)
    }

    _UpdateChoice(action) {
        this._ComboPush("CommandTimeoutRow", "Visibility", WindowControl.UsesTimeout(action) ? "Visible" : "Collapsed")
        this._ComboPush("ArgumentRow", "Visibility", WindowControl.UsesArgument(action) ? "Visible" : "Collapsed")
        label := action == "设置勾选" ? GetLang("勾选状态（0/1）：")
            : GetLang(action == "设置范围值" ? "数值：" : "写入内容：")
        this._ComboPush("ArgumentLabel", "Text", label)
    }

    _Validate(data) {
        WindowControl.ParseSelector(data.Selector)
    }

    _ApplyPick(ui, coords) {
        selector := WindowControl.FromPoint(coords[1], coords[2])
        text := JSON.stringify(selector, 2)
        ui.Update("Selector", "Text", text)
        this._UpdateSelectorSummary(text)
    }
}

class WindowControlPickOverlay {
    __New() {
        ; 分层窗口穿透鼠标，不能成为 WindowFromPoint 的拾取结果。
        this.panel := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale")
        this.token := Gdip_Startup()
        this.lastRect := ""
    }

    Close() {
        this.panel.Destroy()
        if (this.token)
            Gdip_Shutdown(this.token)
    }

    Update(*) {
        if (!this.token)
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        try {
            bounds := WindowControl.HoverBounds(x, y)
            if (bounds && this._Draw(bounds))
                return
        }
        if (this.lastRect != "") {
            this.panel.Hide()
            this.lastRect := ""
        }
    }

    _Draw(bounds) {
        window := bounds.window, target := bounds.target, parent := bounds.parent
        screenX := SysGet(76), screenY := SysGet(77)
        x := Max(window.left, screenX), y := Max(window.top, screenY)
        w := Min(window.right, screenX + SysGet(78)) - x
        h := Min(window.bottom, screenY + SysGet(79)) - y
        left := Max(0, target.left - x), top := Max(0, target.top - y)
        right := Min(w, target.right - x), bottom := Min(h, target.bottom - y)
        if (left >= right || top >= bottom)
            return false
        pl := Max(0, parent.left - x), pt := Max(0, parent.top - y)
        pr := Min(w, parent.right - x), pb := Min(h, parent.bottom - y)
        rect := Format("{},{},{},{},{},{},{},{},{},{},{},{}", x, y, w, h, left, top, right, bottom, pl, pt, pr, pb)
        if (rect == this.lastRect)
            return true

        dc := 0, bitmap := 0, oldBitmap := 0, graphics := 0, fill := 0, border := 0, guide := 0
        try {
            dc := CreateCompatibleDC()
            bitmap := CreateDIBSection(w, h, dc)
            if (!dc || !bitmap)
                return false
            oldBitmap := SelectObject(dc, bitmap)
            graphics := Gdip_GraphicsFromHDC(dc)
            if (!oldBitmap || !graphics)
                return false

            Gdip_GraphicsClear(graphics, 0x600C1422)
            fill := Gdip_BrushCreateSolid(0x382C90EF)
            Gdip_SetCompositingMode(graphics, 1) ; SourceCopy，目标内用蓝色替换暗色遮罩。
            Gdip_FillRectangle(graphics, fill, left, top, right - left, bottom - top)
            Gdip_SetCompositingMode(graphics, 0)
            guide := Gdip_CreatePen(0xE69BD5FF, 1)
            DllCall("gdiplus\GdipSetPenDashStyle", "Ptr", guide, "Int", 1)
            for edge in [left, right - 1] {
                if (pt < top)
                    Gdip_DrawLine(graphics, guide, edge, top, edge, pt)
                if (pb > bottom)
                    Gdip_DrawLine(graphics, guide, edge, bottom - 1, edge, pb - 1)
            }
            for edge in [top, bottom - 1] {
                if (pl < left)
                    Gdip_DrawLine(graphics, guide, left, edge, pl, edge)
                if (pr > right)
                    Gdip_DrawLine(graphics, guide, right - 1, edge, pr - 1, edge)
            }
            border := Gdip_CreatePen(0xFF55B5FF, 1)
            Gdip_DrawRectangle(graphics, border, left, top, right - left - 1, bottom - top - 1)
            Gdip_DeleteGraphics(graphics)
            graphics := 0
            if (!UpdateLayeredWindow(this.panel.Hwnd, dc, x, y, w, h))
                return false
            if (this.lastRect == "")
                DllCall("ShowWindow", "Ptr", this.panel.Hwnd, "Int", 4) ; SW_SHOWNOACTIVATE
            this.lastRect := rect
            return true
        } finally {
            if (guide)
                Gdip_DeletePen(guide)
            if (border)
                Gdip_DeletePen(border)
            if (fill)
                Gdip_DeleteBrush(fill)
            if (graphics)
                Gdip_DeleteGraphics(graphics)
            if (oldBitmap)
                SelectObject(dc, oldBitmap)
            if (bitmap)
                DeleteObject(bitmap)
            if (dc)
                DeleteDC(dc)
        }
    }
}

class AiDecisionGui extends ClassifierCommandGui {
    CmdKey := "AI判断"
    ChoiceField := "Source"
    Choices := AiDecision.Sources
    TextFields := ["Question"]
    HasErrorField := false
    WindowBindingContext := ""
    static OptionExamples := ["星期一", "星期二", "其他"]
    static CoordFields := ["StartX", "StartY", "EndX", "EndY"]
    _optionCount := 0
    _previewField := ""
    _previewTimer := 0

    __New() {
        super.__New()
        this._areaPreview := ScreenAreaPreview()
    }

    ShowGui(cmd) {
        if (A_IsCompiled && !AiAssist.IsConfigured())
            RmtDialog.Info(GetLang("请先在 AI 设置中填写 API Key、API URL 与模型"), GetLang(this.CmdKey), this.OwnerHwnd)
        super.ShowGui(cmd)
    }

    _BuildHeaderFields(body) {
        header := body.Add("Grid")
        header.Cols("*", 16, "*")
        this._Choice(header, "判断依据：")
        remark := this._Row(header, "备注：", "Remark", , "CommandRightLabel").Grid_Column(2)
        this._TextBox(remark, "Remark").Grid_Column(1)
    }

    _BuildFields(body) {
        question := this._Row(body, "判断问题：", "Question").Add("Grid").Grid_Column(1)
        this._TextBox(question, "Question", 64)
        this._Placeholder(question, "Question", GetLang("今天星期几？"), true)

        this._BuildRange(body, "Region")
        this._BuildRange(body, "WindowRegion")
        binding := this._Row(body, "窗口绑定：", "WinInfo").Visibility("Collapsed").Add("Grid").Grid_Column(1)
        binding.Cols("*", 6, "Auto")
        CmdEditorForm.WindowBindingCombo(binding, "WinInfo")
        CmdEditorForm.TextButton(binding, "BtnWinEdit", "编辑").Grid_Column(2)

        choices := this._Row(body, "候选选项：", "Options", "Top").Add("StackPanel").Grid_Column(1)
        border := choices.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(4)
        grid := border.Add("Grid")
        grid.Rows("Auto", "Auto")
        grid.Cols("*", "Auto")
        header := grid.Add("Grid").Margin("6,4,6,2")
        this._OptionColumns(header)
        header.Add("TextBlock").Text(GetLang("选项名称")).Foreground("{DynamicResource TextMain}")
        header.Add("TextBlock").Grid_Column(2).Text(GetLang("保存值")).ToolTip(GetLang("留空时保存选项名称"))
            .Foreground("{DynamicResource TextMain}")
        scroll := grid.Add("ScrollViewer").Name("ChoicesScroll").Grid_Row(1).Grid_ColumnSpan(2).Height(4 * 30)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        template := scroll.Add("ScrollViewer.Template").Add("ControlTemplate").TargetType("ScrollViewer")
        viewport := template.Add("Grid")
        viewport.Cols("*", "Auto")
        viewport.Add("ScrollContentPresenter").Name("PART_ScrollContentPresenter")
        viewport.Add("ScrollBar").Name("PART_VerticalScrollBar").Grid_Column(1).Margin("0,2,2,2")
            .Width("{DynamicResource ScrollBarWidth}")
            .Style("{DynamicResource VerticalScrollBarStyle}").Visibility("Hidden")
            .Value("{TemplateBinding VerticalOffset}").Maximum("{TemplateBinding ScrollableHeight}")
            .ViewportSize("{TemplateBinding ViewportHeight}")
        template.Add("ControlTemplate.Triggers").Add("Trigger").Property("ComputedVerticalScrollBarVisibility").Value("Visible")
            .Add("Setter").TargetName("PART_VerticalScrollBar").Property("Visibility").Value("Visible")
        grid.Add("Border").Grid_Column(1).Width("{DynamicResource ScrollBarWidth}").Margin("0,0,2,0")
        list := scroll.Add("StackPanel").Margin("6,0")
        list.Add("StackPanel").Name("ChoiceRows")
        CmdEditorForm.IconButton(list, "AddChoice", 0xE710, "添加选项")
            .HorizontalAlignment("Center").Margin("0,2")
    }

    _BuildRange(body, field) {
        range := body.Add("Grid").Name(field "Panel").Visibility("Collapsed").Margin("0,4")
        range.Rows(32, 32)
        columns := range.Add("Grid.ColumnDefinitions")
        columns.Add("ColumnDefinition").Width("Auto").SharedSizeGroup("CommandLabel")
        for width in [120, 8, 120]
            columns.Add("ColumnDefinition").Width(width)
        preview := range.Add("Button").Name(field "Preview").Grid_RowSpan(2)
            .Margin("-7,0,8,0").Cursor("Hand").Focusable("False").Tag("0").ToolTip(GetLang("框选范围预览"))
            .HorizontalContentAlignment("Left").VerticalContentAlignment("Stretch")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
        preview.InjectResources(ScreenAreaPreview.ButtonStyle())
        labels := preview.Add("Grid").IsHitTestVisible("False")
        labels.Rows("*", "*")
        for i, endpoint in ["起始坐标", "终止坐标"] {
            labels.Add("TextBlock").Grid_Row(i - 1).Text(GetLang(endpoint "："))
                .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
            for j, axis in ["X", "Y"] {
                name := field AiDecisionGui.CoordFields[2 * (i - 1) + j]
                combo := CmdEditorForm.Combo(range, name, true).Grid_Row(i - 1).Grid_Column(2 * j - 1)
                    .Height(28).MinHeight(28).ToolTip(GetLang(endpoint axis "："))
                for value in (field == "Region" ? GetGuiVarReferences(StrLower(axis)) : GetGuiVarReferences())
                    combo.Add("ComboBoxItem").Content(value)
            }
        }
    }

    _BuildResultFields(body) {
        results := body.Add("Grid")
        results.Cols("*", 16, "*")
        this._Variable(results, "结果变量：", "ResultVar")
        CommandTimeoutFields.Add(body)
    }

    _TextBox(parent, name, height := 26) {
        box := super._TextBox(parent, name, height)
        if (height > 26)
            return box.Style("{StaticResource RmtMultiLineTextBox}").Padding("1.5,0.5,1.5,3")
        return box.Style("{StaticResource RmtSingleLineTextBox}").Padding("1.5,0")
    }

    _Placeholder(parent, field, text, multiline := false, column := 0) {
        label := parent.Add("TextBlock").Grid_Column(column).Text(text).IsHitTestVisible("False")
            .Margin(multiline ? "6,2,6,0" : "6,0,6,0")
            .VerticalAlignment(multiline ? "Top" : "Center").Foreground("{DynamicResource TextSub}").Opacity("0.65")
        style := label.Add("TextBlock.Style").Add("Style").TargetType("TextBlock")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        style.Add("Style.Triggers").Add("DataTrigger").Binding("{Binding Text, ElementName=" field "}").Value("")
            .Add("Setter").Property("Visibility").Value("Visible")
    }

    _BindFields() {
        this.ui.OnEvent("AddChoice", "Click", XamlWin.BindCurrent(this, "OnAddChoice"))
        this.ui.OnEvent("BtnWinEdit", "Click", XamlWin.BindCurrent(this, "OnEditWindowBinding"))
        this.ui.OnEvent("BtnCmdF1", "Click", (*) => SetTimer(this._Pick.Bind(this, this.ui), -1))
        for field in ["Region", "WindowRegion"] {
            this.ui.OnEvent(field "Preview", "Click", XamlWin.BindCurrent(this, "ToggleAreaPreview", field))
            for name in AiDecisionGui.CoordFields
                this.ui.OnEvent(field name, "LostFocus", XamlWin.BindCurrent(this, "RefreshAreaPreview"))
        }
        for update in CmdEditorF1Updates("area")
            this.ui.Update(update.ControlName, update.PropertyName, update.Value)
        this.ui.Update("BtnCmdF1", "ToolTip", GetLang("框选范围"))
    }

    Init(cmd) {
        super.Init(cmd)
        this._ComboPush("WinInfo", "Text", InputField(this.Data, "WinInfo", "{宏设置窗口绑定}"))
        for field in ["Region", "WindowRegion"] {
            value := InputField(this.Data, field, "")
            this._SetRange(this.ui, field, value == "" ? [] : StrSplit(value, ","))
        }
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs, TimeoutPolicy.Get(this.Data), TimeoutPolicy.StatusVar(this.Data))
        options := AiDecision.ParseOptions(this.Data.Options, false)
        if (!options.Length)
            loop AiDecisionGui.OptionExamples.Length
                options.Push({Label: "", Value: ""})
        this._RenderOptions(options)
    }

    _SavedChoice(value) => AiDecision.SourceName(value)

    _ReadRange(field) {
        fields := []
        for name in AiDecisionGui.CoordFields
            fields.Push(field name)
        coords := this.ui.Query(fields*)
        text := Format("{},{},{},{}", Trim(coords[fields[1]]), Trim(coords[fields[2]]),
            Trim(coords[fields[3]]), Trim(coords[fields[4]]))
        return text == ",,," ? "" : TranslateBuiltinVarReferences(text)
    }

    _ReadData() {
        data := super._ReadData()
        data.WinInfo := Trim(this.ui.Query("WinInfo"))
        for field in ["Region", "WindowRegion"]
            data.%field% := this._ReadRange(field)
        text := ""
        for option in this._ReadOptions() {
            label := Trim(option.Label)
            value := Trim(option.Value)
            if (label == "" && value == "")
                continue
            if (InStr(label, "|"))
                throw Error(GetLang("选项名称不能包含竖线。"))
            line := value == "" ? label : label " | " value
            text .= (text == "" ? "" : "`n") line
        }
        data.Options := text
        return data
    }

    _ReadOptions() {
        fields := []
        loop this._optionCount
            fields.Push("OptionLabel_" A_Index, "OptionValue_" A_Index)
        state := this.ui.Query(fields*)
        options := []
        loop this._optionCount
            options.Push({Label: state.Get("OptionLabel_" A_Index, ""), Value: state.Get("OptionValue_" A_Index, "")})
        return options
    }

    _OptionColumns(grid) => grid.Cols("*", 8, "*", 8, 28)

    _RenderOptions(options) {
        this._optionCount := options.Length
        this._ComboPush("ChoiceRows", "ClearItems", "")
        for i, option in options {
            name := "DeleteChoice_" i
            row := XAML_Generator("Grid").Margin("0,2")
            row.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
            this._OptionColumns(row)
            this._TextBox(row, "OptionLabel_" i)
            this._TextBox(row, "OptionValue_" i).Grid_Column(2)
            if (AiDecisionGui.OptionExamples.Has(i)) {
                this._Placeholder(row, "OptionLabel_" i, GetLang(AiDecisionGui.OptionExamples[i]))
                this._Placeholder(row, "OptionValue_" i, String(i), false, 2)
            }
            CmdEditorForm.IconButton(row, name, 0xE74D, "删除").Grid_Column(4)
                .IsEnabled(options.Length > 2 ? "True" : "False")
            this._ComboPush("ChoiceRows", "AddXamlItem", row.ToString())
            this._ComboPush("OptionLabel_" i, "Text", option.Label)
            this._ComboPush("OptionValue_" i, "Text", option.Value)
            if (this.ui.events.Has(name) && this.ui.events[name].Has("Click"))
                this.ui.events[name]["Click"] := []
            this.ui.OnEvent(name, "Click", this.OnDeleteChoice.Bind(this, i))
        }
    }

    OnAddChoice(*) {
        options := this._ReadOptions()
        options.Push({Label: "", Value: ""})
        this._RenderOptions(options)
        this.ui.Update("ChoicesScroll", "ScrollToEnd", "")
        this.ui.Update("OptionLabel_" options.Length, "Focus", "")
    }

    OnDeleteChoice(index, *) {
        options := this._ReadOptions()
        if (options.Length <= 2 || !options.Has(index))
            return
        options.RemoveAt(index)
        this._RenderOptions(options)
    }

    _UpdateChoice(source) {
        this._CloseAreaPreview()
        isWindow := AiDecision.IsWindowSource(source)
        this._ComboPush("RegionPanel", "Visibility", AiDecision.IsScreenSource(source) ? "Visible" : "Collapsed")
        this._ComboPush("WindowRegionPanel", "Visibility", isWindow ? "Visible" : "Collapsed")
        this._ComboPush("WinInfoRow", "Visibility", isWindow ? "Visible" : "Collapsed")
        this._ComboPush("BtnCmdF1", "Visibility", AiDecision.UsesRegion(source) ? "Visible" : "Collapsed")
    }

    OnEditWindowBinding(*) {
        MyFrontInfoGui.OwnerHwnd := MainSoftData.IsModalSubGui ? this.Hwnd() : ""
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfo"))
    }

    _Validate(data) {
        if (Trim(data.Question) == "")
            throw Error(GetLang("判断问题不能为空。"))
        if (data.ResultVar == "")
            throw Error(GetLang("请填写结果变量。"))
        AiDecision.ParseOptions(data.Options)
        if (AiDecision.IsWindowSource(data.Source)) {
            if (data.WinInfo == "")
                throw Error(GetLang("窗口绑定不能为空"))
            AiDecision.ParseRegion(data.WindowRegion, true, true)
        } else if (AiDecision.IsScreenSource(data.Source))
            AiDecision.ParseRegion(data.Region, false, true)
    }

    _ValidateResultFields(data) {
        errorVar := data.HasOwnProp("ErrorVar") ? data.ErrorVar : ""
        return CommandTimeoutFields.ValidateStatus(data, data.ResultVar, errorVar)
    }

    SaveData() {
        super.SaveData()
        TimeoutPolicy.RegisterStatus(this.Data)
    }

    _PickArea(action) {
        this._CloseAreaPreview()
        if (AiDecision.IsWindowSource(this._ChoiceValue(this.ui.Query("Source")))) {
            info := this._ResolveEditorWindow()
            if (!IsMouseWindowBinding(info))
                WinActivate(AiDecision.FindWindow(info))
        }
        super._PickArea(action)
    }

    _ResolveEditorWindow() => ResolveEditorBindWindow(this.WindowBindingContext, Trim(this.ui.Query("WinInfo")))

    _ApplyPick(ui, coords) {
        source := this._ChoiceValue(ui.Query("Source"))
        if (!AiDecision.UsesRegion(source) || coords[1] == coords[3] || coords[2] == coords[4])
            return
        if (AiDecision.IsWindowSource(source)) {
            hwnd := AiDecision.FindWindow(this._ResolveEditorWindow())
            WinGetClientPos(&x, &y, &w, &h, hwnd)
            coords := [coords[1] - x, coords[2] - y, coords[3] - x, coords[4] - y]
            AiDecision.CheckWindowRegion(coords, w, h)
            this._SetRange(ui, "WindowRegion", coords)
        } else
            this._SetRange(ui, "Region", coords)
    }

    _SetRange(ui, field, coords) {
        for i, name in AiDecisionGui.CoordFields {
            value := coords.Has(i) ? TranslateBuiltinVarReferences(String(coords[i]), true) : ""
            if (this._batching)
                this._ComboPush(field name, "Text", value)
            else
                ui.Update(field name, "Text", value)
        }
    }

    ToggleAreaPreview(field, *) {
        wasOpen := this._previewField == field
        this._CloseAreaPreview()
        if (wasOpen)
            return
        this._previewField := field
        this.ui.Update(field "Preview", "Tag", "1")
        this.RefreshAreaPreview()
        if (field == "WindowRegion") {
            this._previewTimer := this.RefreshAreaPreview.Bind(this)
            SetTimer(this._previewTimer, 100)
        }
    }

    RefreshAreaPreview(*) {
        field := this._previewField
        if (field == "" || !IsObject(this.ui) || this._areaPreview.IsDragging())
            return
        isWindow := field == "WindowRegion"
        try {
            coords := AiDecision.ParseRegion(this._ReadRange(field), isWindow)
            hwnd := 0, x := 0, y := 0
            if (isWindow) {
                hwnd := this._areaPreview.FindTargetWindow(this._ResolveEditorWindow())
                if (!hwnd || !WinExist("ahk_id " hwnd) || WinGetMinMax(hwnd) == -1) {
                    this._areaPreview.Hide()
                    return
                }
                WinGetClientPos(&x, &y, &w, &h, hwnd)
                AiDecision.CheckWindowRegion(coords, w, h)
            }
            this._areaPreview.Show(x + coords[1], y + coords[2], coords[3] - coords[1], coords[4] - coords[2],
                this._ApplyPreviewRange.Bind(this, field, hwnd), hwnd, field)
        } catch {
            this._areaPreview.Hide()
        }
    }

    _ApplyPreviewRange(field, hwnd, coords*) {
        if (this._previewField != field || !IsObject(this.ui))
            return
        try {
            if (hwnd) {
                WinGetClientPos(,, &w, &h, hwnd)
                AiDecision.CheckWindowRegion(coords, w, h)
            }
            this._SetRange(this.ui, field, coords)
        }
        this.RefreshAreaPreview()
    }

    _CloseAreaPreview() {
        if (this._previewField == "")
            return
        field := this._previewField
        this._previewField := ""
        if (this._previewTimer) {
            SetTimer(this._previewTimer, 0)
            this._previewTimer := 0
        }
        this._areaPreview.Hide()
        if (IsObject(this.ui))
            this.ui.Update(field "Preview", "Tag", "0")
    }

    OnWindowClosing(state, ctrl, event) {
        this._CloseAreaPreview()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        this._CloseAreaPreview()
        super._CloseWindow()
    }
}
