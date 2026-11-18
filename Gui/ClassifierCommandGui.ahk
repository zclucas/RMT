#Requires AutoHotkey v2.0

class ClassifierCommandGui extends CommentGui {
    _pickAction := ""

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang(this.CmdKey)
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")
        this._Field(body, "备注：", "Remark")
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
        this.ui.OnEvent("BtnPick", "Click", (*) => SetTimer(this._Pick.Bind(this, this.ui), -1))
        this.ui.OnEvent(this.ChoiceField, "SelectionChanged", XamlWin.BindCurrent(this, "OnChoiceChanged"))
        this._BindFields()
        BindCmdEditorChrome(this.ui, "#指令手册/" this.CmdKey)
    }

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
        return CmdEditorForm.TextBox(this._Row(body, label, name), name, height).Grid_Column(1)
    }

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

    _PickerField(body, label, name, tip) {
        inner := this._Row(body, label, name).Add("Grid").Grid_Column(1)
        inner.Cols("*", 6, "Auto")
        CmdEditorForm.TextBox(inner, name)
        CmdEditorForm.IconButton(inner, "BtnPick", 0xECAF, tip).Grid_Column(2)
    }

    _BindFields() {
    }

    Init(cmd) {
        parts := cmd == "" ? [] : StrSplit(cmd, "_")
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr(this.CmdKey)
        this.Data := GetMacroCMDData(this.SerialStr)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        for varName in GetGuiVarArr() {
            for field in ["ResultVar", "ErrorVar"]
                this._ComboPush(field, "AddItem", varName)
        }
        for field in this.TextFields
            this._ComboPush(field, "Text", String(this.Data.%field%))
        for field in ["ResultVar", "ErrorVar", "TimeoutMs"]
            this._ComboPush(field, "Text", String(this.Data.%field%))
        choiceField := this.ChoiceField
        choice := CmdEnumZh(this.Data.%choiceField%, this.Choices)
        this._ComboPush(this.ChoiceField, "SelectedIndex", CmdEnumIndex(choice, this.Choices))
        this._UpdateChoice(choice)
    }

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
        fields.Push(choiceField, "ResultVar", "ErrorVar", "TimeoutMs")
        state := this.ui.Query(fields*)
        for field in this.TextFields
            data.%field% := state[field]
        data.%choiceField% := this._ChoiceValue(state[choiceField])
        data.ResultVar := GetVarName(Trim(state["ResultVar"]))
        data.ErrorVar := GetVarName(Trim(state["ErrorVar"]))
        data.TimeoutMs := Trim(state["TimeoutMs"])
        return data
    }

    CheckIfValid() {
        try {
            data := this._ReadData()
            if (!IsInteger(data.TimeoutMs) || data.TimeoutMs < 1 || data.TimeoutMs > 3600000)
                throw Error(GetLang("超时时间应为 1～3600000 毫秒。"))
            if (data.ResultVar != "" && data.ResultVar = data.ErrorVar)
                throw Error(GetLang("结果变量和错误变量不能相同。"))
            this._Validate(data)
        } catch as e {
            RmtDialog.Info(e.Message, GetLang(this.CmdKey), this.Hwnd())
            return false
        }
        for name in [data.ResultVar, data.ErrorVar]
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
        CommandTimeoutFields.Read(this.ui, data)
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
    TextFields := ["Question", "Text", "Region"]
    _optionCount := 0

    _BuildFields(body) {
        source := body.Add("Grid")
        source.Cols("*", 16, "*")
        this._Choice(source, "判断依据：")
        timeout := this._Row(source, "超时（毫秒）：", "TimeoutMs", "Center", "CommandRightLabel", GetLang("本次操作最多等待的毫秒数。")).Grid_Column(2)
        CmdEditorForm.TextBox(timeout, "TimeoutMs").Grid_Column(1)
        this._Field(body, "判断问题：", "Question", 64)
        this._PickerField(body, "屏幕范围：", "Region", "框选范围")
        this._Field(body, "输入内容：", "Text", 64)
        choices := this._Row(body, "候选选项：", "Options", "Top").Add("StackPanel").Grid_Column(1)
        header := choices.Add("Grid").Margin("0,0,0,2")
        this._OptionColumns(header)
        header.Add("TextBlock").Text(GetLang("选项名称")).Foreground("{DynamicResource TextMain}")
        header.Add("TextBlock").Grid_Column(2).Text(GetLang("保存值")).ToolTip(GetLang("留空时保存选项名称"))
            .Foreground("{DynamicResource TextMain}")
        list := choices.Add("ScrollViewer").Name("ChoicesScroll").MaxHeight(132)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        list.Add("StackPanel").Name("ChoiceRows")
        CmdEditorForm.IconButton(choices, "AddChoice", 0xE710, "添加选项")
            .HorizontalAlignment("Left").Margin("0,4,0,0")
    }

    _BindFields() {
        this.ui.OnEvent("AddChoice", "Click", XamlWin.BindCurrent(this, "OnAddChoice"))
    }

    Init(cmd) {
        super.Init(cmd)
        this._RenderOptions(AiDecision.ParseOptions(this.Data.Options, false))
    }

    _ReadData() {
        data := super._ReadData()
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
            CmdEditorForm.TextBox(row, "OptionLabel_" i).ToolTip(GetLang("选项名称"))
            CmdEditorForm.TextBox(row, "OptionValue_" i).Grid_Column(2).ToolTip(GetLang("留空时保存选项名称"))
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
        this._ComboPush("RegionRow", "Visibility", source == "屏幕文字" ? "Visible" : "Collapsed")
    }

    _Validate(data) {
        if (Trim(data.Question) == "")
            throw Error(GetLang("判断问题不能为空。"))
        if (data.ResultVar == "")
            throw Error(GetLang("请填写结果变量。"))
        AiDecision.ParseOptions(data.Options)
        if (data.Source == "屏幕文字")
            AiDecision.ParseRegion(data.Region)
    }

    _ApplyPick(ui, coords) {
        if (coords[1] != coords[3] && coords[2] != coords[4])
            ui.Update("Region", "Text", Format("{1},{2},{3},{4}", coords*))
    }
}
