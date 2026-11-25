#Requires AutoHotkey v2.0

class ClassifierCommandGui extends CommentGui {
    _pickAction := ""
    HasResultField := true
    HasErrorField := true
    HasTimeoutFields := true
    HelpTopic := ""
    F1Glyph := Chr(0xECAF)

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang(this.CmdKey)
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height, , , , , this.F1Glyph)
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
        BindCmdEditorChrome(this.ui, "#指令手册/" (this.HelpTopic == "" ? this.CmdKey : this.HelpTopic), this._PlayAction())
    }

    _PlayAction() => ""

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

    _Variable(body, label, name, column := 0, showTip := true) {
        labelGroup := column == 0 ? "CommandLabel" : "CommandRightLabel"
        row := this._Row(body, label, name, "Center", labelGroup).Grid_Column(column)
        combo := CmdEditorForm.Combo(row, name, true).Grid_Column(1)
        if (!showTip)
            combo.ToolTipService_IsEnabled("False")
    }

    _Choice(body, label) {
        name := this.ChoiceField
        combo := CmdEditorForm.Combo(this._Row(body, label, name), name).Grid_Column(1)
        for choice in this.Choices
            combo.Add("ComboBoxItem").Content(this._ChoiceLabel(choice))
    }

    _BindFields() {
    }

    Init(cmd) {
        parts := cmd == "" ? [] : StrSplit(cmd, "_")
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr(this.CmdKey)
        this.Data := GetMacroCMDData(this.SerialStr)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        resultFields := this.HasResultField ? ["ResultVar"] : []
        if (this.HasErrorField)
            resultFields.Push("ErrorVar")
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

    _ChoiceLabel(choice) => GetLang(choice)

    _ChoiceValue(text) {
        for choice in this.Choices
            if (this._ChoiceLabel(choice) == text)
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
        fields.Push(choiceField)
        if (this.HasResultField)
            fields.Push("ResultVar")
        if (this.HasErrorField)
            fields.Push("ErrorVar")
        state := this.ui.Query(fields*)
        for field in this.TextFields
            data.%field% := state[field]
        data.%choiceField% := this._ChoiceValue(state[choiceField])
        data.ResultVar := this.HasResultField ? GetVarName(Trim(state["ResultVar"])) : ""
        if (this.HasErrorField)
            data.ErrorVar := GetVarName(Trim(state["ErrorVar"]))
        if (this.HasTimeoutFields)
            CommandTimeoutFields.Read(this.ui, data)
        return data
    }

    CheckIfValid() {
        try {
            data := this._ReadData()
            if (this.HasTimeoutFields && !TimeoutPolicy.ValidMs(data.TimeoutMs))
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
        if (this.HasTimeoutFields && IsInteger(this.Data.TimeoutMs))
            this.Data.TimeoutMs := Integer(this.Data.TimeoutMs)
        this._PrepareSaveData()
        RegisterCommandResultVars(this.Data)
        SaveMacroCMDData(this.Data)
    }

    _PrepareSaveData() {
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
            failure := this._PickErrorMessage(e)
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

    _PickErrorMessage(error) => error.Message

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
    _autoRemark := ""
    _pickHotkeys := []
    F1Glyph := Chr(0xE707)
    CmdKey := "窗口控件"
    HelpTopic := "35-控件信息与操作"
    ChoiceField := "ActionType"
    Choices := WindowControl.Actions
    TextFields := ["Selector", "Argument"]

    _SavedChoice(value) => CmdEnumZh(WindowControl.NormalizeAction(value), this.Choices)

    _BuildHeaderFields(body) {
        header := body.Add("Grid").Cols("*", 16, "*")
        this._Choice(header, "操作：")
        row := this._Row(header, "备注：", "Remark").Grid_Column(2)
        this._TextBox(row, "Remark").Style("{StaticResource RmtSingleLineTextBox}").Padding("1.5,0").Grid_Column(1)
    }

    _Row(body, label, name, labelAlignment := "Center", labelGroup := "CommandLabel", labelTip := "") {
        labelWidth := 6 * XAMLHost.ScaleFontSize(XAMLHost.FontSize())
        row := body.Add("Grid").Name(name "Row").Margin("0,4").Cols(labelWidth, "*")
        caption := CmdEditorForm.Label(row, label).Name(name "Label").Margin("0").VerticalAlignment(labelAlignment)
        if (labelTip != "")
            caption.ToolTip(labelTip)
        return row
    }

    _PickArea(action) {
        overlay := WindowControlPickOverlay(this._ChoiceValue(this.ui.Query(this.ChoiceField)), this is ControlOperationGui)
        update := overlay.Update.Bind(overlay)
        keys := []
        this._pointPickDone := false
        MainSoftData.SelectAreaAction := action
        try {
            keys := WinHotkey.Register(["Enter"], this._ConfirmControlPick.Bind(this, action))
            if (!keys.Length)
                throw Error(GetLang("无法注册拾取确认热键。"))
            SetSystemCursor("CROSS")
            SetTimer(update, 40)
            while (!this._pointPickDone)
                Sleep(30)
        } finally {
            WinHotkey.UnregisterAll(keys)
            SetTimer(update, 0)
            overlay.Close()
            MainSoftData.SelectAreaAction := ""
            SetSystemCursor()
        }
    }

    _ConfirmControlPick(action, *) {
        if (this._pointPickDone)
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        action(x, y, x, y)
        this._pointPickDone := true
    }

    _CancelPick(*) {
        if (this._pickAction != "")
            this._pointPickDone := true
    }

    _BuildFields(body) {
        target := this._Row(body, "目标控件：", "TargetControl").Add("Grid").Grid_Column(1)
        target.Cols("*", 6, "Auto", 6, "Auto")
        CmdEditorForm.Combo(target, "TargetSummary", true).ToolTipService_IsEnabled("False")
        hint := target.Add("TextBlock").Name("TargetHint").Text(GetLang("请拾取控件或选择控件变量"))
            .Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("6,0,24,0")
            .TextTrimming("CharacterEllipsis").IsHitTestVisible("False")
        style := hint.Add("TextBlock.Style").Add("Style").TargetType("TextBlock")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        style.Add("Style.Triggers").Add("DataTrigger").Binding("{Binding Text, ElementName=TargetSummary}").Value("")
            .Add("Setter").Property("Visibility").Value("Visible")
        CmdEditorForm.IconButton(target, "BtnPick", 0xE707, "拾取窗口控件").Grid_Column(2)
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
            .InjectResources(FrontInfoGui._ToolBtnHoverStyle())
        CmdEditorForm.IconButton(target, "BtnSelectorDetails", 0xE946, "选择器详情").Grid_Column(4)
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
            .InjectResources(FrontInfoGui._ToolBtnHoverStyle())
        body.Add("TextBox").Name("Selector").Style("{StaticResource RmtMultiLineTextBox}").Visibility("Collapsed")
        this._BuildArgumentField(body)
    }

    _BuildArgumentField(body) => this._Field(body, "控件参数：", "Argument")

    _BuildResultFields(body) {
        results := body.Add("Grid")
        if (this.HasErrorField)
            results.Cols("*", 16, "*")
        this._Variable(results, "结果变量：", "ResultVar")
        if (this.HasErrorField)
            this._Variable(results, "错误变量：", "ErrorVar", 2)
        CommandTimeoutFields.Add(body, false, , , 6 * XAMLHost.ScaleFontSize(XAMLHost.FontSize()))
    }

    Init(cmd) {
        super.Init(cmd)
        this._autoRemark := ReadCommandAutoRemark(this.Data, this._GenerateRemark.Bind(this))
        if (this.HasTimeoutFields)
            CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs,
                InputField(this.Data, "TimeoutAction", TimeoutPolicy.DefaultAction),
                InputField(this.Data, "TimeoutStatusVar", TimeoutPolicy.DefaultStatusVar))
        this._ComboPush("TargetSummary", "ClearItems", "")
        if (MySoftData.HasOwnProp("ControlVarMap")) {
            for name in MySoftData.ControlVarMap
                this._ComboPush("TargetSummary", "AddItem", "{" name "}")
        }
        this._UpdateSelectorSummary(this.Data.Selector)
    }

    _GenerateRemark(data) => GenerateCommandAutoRemark(data)

    _PrepareSaveData() {
        FormatCommandAutoRemark(this.Data, this.ui.Query("Remark"), this._autoRemark, this._GenerateRemark.Bind(this), true)
    }

    GetCommandStr() {
        return FormatCommandAutoRemark(this.Data, this.ui.Query("Remark"), this._autoRemark, this._GenerateRemark.Bind(this), false)
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
        ; 通过运行时设置只读，兼容不接受 ComboBox.IsReadOnly 特性的 XAML 加载器。
        this.ui.Update("TargetSummary", "IsReadOnly", "True")
        this.ui.OnEvent("TargetSummary", "SelectionChanged", XamlWin.BindCurrent(this, "OnTargetControlChanged"))
        pick := XamlWin.BindCurrent(this, "OnPickControl")
        this.ui.OnEvent("BtnPick", "Click", pick)
        this.ui.OnEvent("BtnCmdF1", "Click", pick)
        for update in CmdEditorF1Updates("point")
            this.ui.Update(update.ControlName, update.PropertyName, update.Value)
        this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：拾取窗口控件"))
        this.ui.Update("BtnPick", "ToolTip", GetLang("F1：拾取窗口控件"))
        this.ui.OnEvent("BtnSelectorDetails", "Click", XamlWin.BindCurrent(this, "OnSelectorDetails"))
    }

    OnTargetControlChanged(*) {
        text := this.ui.Query("TargetSummary")
        if (!WindowControl.IsControlReference(text))
            return
        this._ComboPush("Selector", "Text", text)
        if (this is ControlOperationGui) {
            this._RefreshWriteFields()
            this._RefreshConditionFields()
        }
    }

    OnPickControl(*) {
        SetTimer(this._Pick.Bind(this, this.ui), -1)
    }

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        if (!this._pickHotkeys.Length && this.Hwnd())
            this._pickHotkeys := WinHotkey.Register(["F1"], XamlWin.BindCurrent(this, "OnPickControl"), this.Hwnd())
    }

    _UnregisterPickHotkeys() {
        WinHotkey.UnregisterAll(this._pickHotkeys)
        this._pickHotkeys := []
    }

    OnWindowClosing(state, ctrl, event) {
        this._UnregisterPickHotkeys()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        this._UnregisterPickHotkeys()
        super._CloseWindow()
    }

    OnSelectorDetails(*) {
        selector := this.ui.Query("Selector")
        if (WindowControl.IsControlReference(selector)) {
            try selector := WindowControl.ResolveTarget(selector)
            catch as e {
                RmtDialog.Info(e.Message, GetLang("选择器详情"), this.Hwnd())
                return
            }
        }
        RmtDialog.Info(Trim(selector) != "" ? selector : GetLang("未拾取控件"), GetLang("选择器详情"), this.Hwnd())
    }

    _UpdateSelectorSummary(text) {
        summary := ""
        if (WindowControl.IsControlReference(text))
            summary := text
        else if (Trim(text) != "") {
            try {
                selector := WindowControl.ParseSelector(text)
                ; 打开旧开关配置时，先按旧路径定位，再换算稳定类名下的序号。
                for part in selector["path"] {
                    if (part["class"] != WindowControl._StableClass(part["class"])) {
                        if (WindowControl.Find(selector, true)) {
                            text := JSON.stringify(selector, 2)
                            this._ComboPush("Selector", "Text", text)
                        }
                        break
                    }
                }
                part := selector["path"][-1]
                name := part["name"] != "" ? part["name"] : part["id"]
                summary := selector["exe"] "  /  " (name != "" ? name : part["class"])
            } catch {
                summary := GetLang("控件选择器无效，请重新拾取。")
            }
        }
        this._ComboPush("TargetSummary", "Text", summary)
    }

    _UpdateChoice(action) {
        if (this.HasTimeoutFields)
            this._ComboPush("CommandTimeoutRow", "Visibility", WindowControl.UsesTimeout(action) ? "Visible" : "Collapsed")
        this._ComboPush("ArgumentRow", "Visibility", WindowControl.UsesArgument(action) ? "Visible" : "Collapsed")
        label := action == "设置勾选" ? GetLang("勾选状态：")
            : GetLang(action == "设置范围值" ? "数值：" : "写入内容：")
        this._ComboPush("ArgumentLabel", "Text", label)
        this._ComboPush("ArgumentLabel", "ToolTip", action == "设置勾选" ? GetLang("勾选状态（0/1）：") : "")
    }

    _Validate(data) {
        if (!WindowControl.IsControlReference(data.Selector))
            WindowControl.ParseSelector(data.Selector)
    }

    _ApplyPick(ui, coords) {
        selector := WindowControl.FromPoint(coords[1], coords[2])
        text := JSON.stringify(selector, 2)
        ui.Update("Selector", "Text", text)
        this._UpdateSelectorSummary(text)
    }
}

class ControlInfoGui extends WindowControlGui {
    CmdKey := "控件信息"
    Choices := WindowControl.InfoActions
    HasErrorField := false
    HasTimeoutFields := false
    WindowBindingContext := ""
    _playHotkeys := []
    _testRunning := false

    _BuildResultFields(body) {
        position := body.Add("Grid").Name("InfoPositionRow").Cols("*", 16, "*")
        this._Variable(position, "屏幕坐标X：", "XVar")
        this._Variable(position, "屏幕坐标Y：", "YVar", 2)
        window := body.Add("Grid").Name("InfoWindowPositionRow").Cols("*", 16, "*")
        this._Variable(window, "窗口坐标X：", "WindowXVar")
        this._Variable(window, "窗口坐标Y：", "WindowYVar", 2)
        size := body.Add("Grid").Name("InfoSizeRow").Cols("*", 16, "*")
        this._Variable(size, "宽度变量：", "WidthVar")
        this._Variable(size, "高度变量：", "HeightVar", 2)
        results := body.Add("Grid").Cols("*", 16, "*")
        this._Variable(results, "结果变量：", "ResultVar", 0, false)
        this._Variable(results, "控件变量：", "ControlVar", 2, false)
        handles := body.Add("Grid").Name("InfoHandleRow").Cols("*", 16, "*")
        this._Variable(handles, "句柄ID变量：", "HwndVar", 0, false)
    }

    _SavedChoice(value) {
        action := WindowControl.NormalizeAction(value)
        return action == "读取控件信息" ? "检测控件存在" : action
    }

    Init(cmd) {
        super.Init(cmd)
        defaults := ControlInfoData()
        for field in ["ControlVar", "HwndVar", "XVar", "YVar", "WindowXVar", "WindowYVar", "WidthVar", "HeightVar"] {
            for name in GetGuiVarArr()
                this._ComboPush(field, "AddItem", name)
            this._ComboPush(field, "Text", this.Data.HasOwnProp(field) ? this.Data.%field% : defaults.%field%)
        }
    }

    _GenerateRemark(data) {
        remark := this._ChoiceLabel(WindowControl.NormalizeAction(data.ActionType))
        if (WindowControl.IsControlReference(data.Selector))
            remark .= "：" data.Selector
        try {
            selector := WindowControl.ParseSelector(data.Selector)
            part := selector["path"][-1]
            target := part["name"] != "" ? part["name"] : part["id"] != "" ? part["id"] : part["class"]
            if (target == "")
                target := selector["exe"]
            remark .= "：" SubStr(target, 1, 40)
        }
        if (data.ResultVar != "")
            remark .= " → " data.ResultVar
        else if (data.ActionType == "读取位置/宽高") {
            outputs := ""
            for field in WindowControl.PositionFields
                if (data.%field% != "")
                    outputs .= (outputs == "" ? "" : "、") data.%field%
            if (outputs != "")
                remark .= " → " outputs
        }
        return remark
    }

    _ValidateResultFields(data) {
        seen := Map()
        fields := data.ActionType == "读取位置/宽高" ? WindowControl.PositionFields : ["ResultVar"]
        if (data.ActionType == "检测控件存在") {
            fields.Push("ControlVar")
            fields.Push("HwndVar")
        }
        for field in fields {
            name := data.%field%
            if (name == "")
                continue
            if (!CheckVarNameIfValid(name))
                return false
            if (seen.Has(name)) {
                RmtDialog.Info(GetLang("保存结果的变量不能相同。"), GetLang(this.CmdKey), this.Hwnd())
                return false
            }
            seen[name] := true
        }
        return true
    }

    _PlayAction() => XamlWin.BindCurrent(this, "TriggerMacro")

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        if (!this._playHotkeys.Length && this.Hwnd())
            this._playHotkeys := WinHotkey.Register(["!l"], this._PlayAction(), this.Hwnd())
    }

    TriggerMacro(*) {
        if (this._testRunning || !this.CheckIfValid())
            return
        ui := this.ui
        this._testRunning := true
        try {
            this.SaveData()
            if (OnTriggerSepcialItemMacro(this.GetCommandStr(), false, this.WindowBindingContext) && this.ui == ui) {
                fields := this.Data.ActionType == "读取位置/宽高" ? WindowControl.PositionFields
                    : this.Data.ActionType == "检测控件存在" ? ["ResultVar", "ControlVar", "HwndVar"] : ["ResultVar"]
                message := ""
                for field in fields {
                    name := this.Data.%field%
                    if (name != "" && MySoftData.VariableMap.Has(name))
                        message .= (message == "" ? "" : "`n") name " = " MySoftData.VariableMap[name]
                }
                if (message != "")
                    RmtDialog.Info(message, GetLang(this.CmdKey), this.Hwnd())
            }
        } finally {
            this._testRunning := false
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this._UnregisterPlayHotkeys()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        this._UnregisterPlayHotkeys()
        super._CloseWindow()
    }

    _UnregisterPlayHotkeys() {
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
    }

    ; 仅调整显示名称，保留旧操作键及数字枚举，兼容已保存的宏。
    _ChoiceLabel(choice) => choice == "检测控件存在" ? GetLang("基础信息")
        : choice == "读取控件值" ? GetLang("控件值")
        : choice == "读取位置/宽高" ? GetLang("控件位置/宽高") : super._ChoiceLabel(choice)

    _UpdateChoice(action) {
        super._UpdateChoice(action)
        tip := action == "检测控件存在" ? GetLang("1存在，0不存在") : ""
        this._ComboPush("ResultVar", "ToolTip", "")
        this._ComboPush("ResultVarLabel", "ToolTip", tip)
        this._ComboPush("ResultVarLabel", "Text", GetLang(action == "检测控件存在" ? "存在变量：" : "结果变量："))
        position := action == "读取位置/宽高"
        this._ComboPush("ResultVarRow", "Visibility", position ? "Collapsed" : "Visible")
        this._ComboPush("InfoPositionRow", "Visibility", position ? "Visible" : "Collapsed")
        this._ComboPush("InfoWindowPositionRow", "Visibility", position ? "Visible" : "Collapsed")
        for field in ["XVarLabel", "YVarLabel"]
            this._ComboPush(field, "ToolTip", GetLang("控件中心点的屏幕坐标。"))
        for field in ["WindowXVarLabel", "WindowYVarLabel"]
            this._ComboPush(field, "ToolTip", GetLang("控件中心点相对所属主窗口客户区左上角的坐标。"))
        this._ComboPush("InfoSizeRow", "Visibility", position ? "Visible" : "Collapsed")
        this._ComboPush("InfoHandleRow", "Visibility", action == "检测控件存在" ? "Visible" : "Collapsed")
        this._ComboPush("HwndVar", "ToolTip", "")
        this._ComboPush("HwndVarLabel", "ToolTip", GetLang("控件自身的窗口句柄；不存在或没有独立句柄时为 0。"))
        this._ComboPush("ControlVar", "ToolTip", "")
        this._ComboPush("ControlVarLabel", "ToolTip", GetLang("保存目标控件，后续指令可通过此变量定位；不存在时清空。"))
        this._ComboPush("ControlVarRow", "Visibility", action == "检测控件存在" ? "Visible" : "Collapsed")
    }

    _ReadData() {
        data := super._ReadData()
        for field in ["TypeVar", "ClassVar"]
            data.%field% := ""
        data.ControlVar := data.ActionType == "检测控件存在" ? GetVarName(Trim(this.ui.Query("ControlVar"))) : ""
        data.HwndVar := data.ActionType == "检测控件存在" ? GetVarName(Trim(this.ui.Query("HwndVar"))) : ""
        for field in WindowControl.PositionFields
            data.%field% := data.ActionType == "读取位置/宽高" ? GetVarName(Trim(this.ui.Query(field))) : ""
        if (data.ActionType == "读取位置/宽高")
            data.ResultVar := ""
        data.ErrorVar := ""
        data.TimeoutAction := ""
        data.TimeoutStatusVar := ""
        data.TimeoutMs := TimeoutPolicy.DefaultMs
        return data
    }
}

class ControlOperationGui extends WindowControlGui {
    CmdKey := "控件操作"
    Choices := WindowControl.OperationActions
    HasResultField := false
    HasErrorField := false
    _writeKind := "text"
    _textBuilder := ""
    WindowBindingContext := ""
    _playHotkeys := []
    _targetRefreshTimer := ""
    _argumentChoicesKind := ""
    _conditionKind := "text"
    _conditionOperatorsKind := ""
    _conditionAllowsHalf := false
    _waitConditionCount := 1
    _waitLeftKinds := []
    _rebuildingWaitConditions := false
    _testRunning := false

    _PlayAction() => XamlWin.BindCurrent(this, "TriggerMacro")

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        this._RefreshConditionFields()
        if (!this._playHotkeys.Length && this.Hwnd())
            this._playHotkeys := WinHotkey.Register(["!l"], this._PlayAction(), this.Hwnd())
        if (!this._targetRefreshTimer) {
            this._targetRefreshTimer := XamlWin.BindCurrent(this, "OnVariableTargetTick")
            SetTimer(this._targetRefreshTimer, 600)
        }
    }

    TriggerMacro(*) {
        if (this._testRunning || !this.CheckIfValid())
            return
        this._testRunning := true
        try {
            this.SaveData()
            OnTriggerSepcialItemMacro(this.GetCommandStr(), false, this.WindowBindingContext)
        } finally {
            this._testRunning := false
        }
    }

    OnVariableTargetTick(*) {
        if (this._testRunning || this._pickAction != "" || !IsObject(this.ui))
            return
        try {
            action := this._ChoiceValue(this.ui.Query("ActionType"))
            if (WindowControl.IsControlReference(this.ui.Query("Selector")) && action == "写入控件值")
                this._RefreshWriteFields()
            if (action == "等待控件出现")
                this._RefreshConditionFields()
        }
    }

    _PreviewSelector(text) {
        seen := Map()
        while (WindowControl.IsControlReference(text)) {
            name := SubStr(text, 2, -1)
            if (seen.Has(name))
                throw Error(GetLang("控件变量引用循环。"))
            seen[name] := true
            try return WindowControl.ParseSelector(WindowControl.ResolveTarget(text))
            catch {
                if (!MySoftData.HasOwnProp("ControlVarMap") || !MySoftData.ControlVarMap.Has(name)
                    || Type(MySoftData.ControlVarMap[name]) != "String")
                    throw Error(GetLang("控件变量未就绪，执行时识别。"))
                text := MySoftData.ControlVarMap[name]
            }
        }
        return WindowControl.ParseSelector(text)
    }

    _StopOperationActions() {
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        if (this._targetRefreshTimer)
            SetTimer(this._targetRefreshTimer, 0)
        this._targetRefreshTimer := ""
    }

    _ChoiceLabel(choice) => choice == "等待控件出现" ? GetLang("等待")
        : choice == "写入控件值" ? GetLang("修改控件值") : super._ChoiceLabel(choice)

    _BuildResultFields(body) {
        CommandTimeoutFields.Add(body, false, , , 6 * XAMLHost.ScaleFontSize(XAMLHost.FontSize()))
    }

    _BuildArgumentField(body) {
        this._argumentChoicesKind := ""
        this._conditionKind := "text", this._conditionOperatorsKind := ""
        this._Row(body, "控件说明：", "WaitValueHint", "Top").Add("TextBlock").Name("WaitValueHint").Grid_Column(1)
            .TextWrapping("Wrap").Foreground("{DynamicResource TextSub}")
        this._Row(body, "控件说明：", "WriteHint", "Top").Add("TextBlock").Name("WriteHint").Grid_Column(1)
            .TextWrapping("Wrap").Foreground("{DynamicResource TextSub}")
        clicks := body.Add("Grid").Cols("*", 16, "*")
        this._OperationCombo(clicks, "点击类型：", "ClickType", WindowControl.ClickTypes)
        hold := this._Row(clicks, "长按时间：", "ClickHoldMs", , , GetLang("毫秒，支持自定义数值或 {变量}。")).Grid_Column(2)
        CmdEditorForm.Combo(hold, "ClickHoldMs", true).Grid_Column(1)
        this._OperationCombo(body, "点击位置：", "ClickPoint", WindowControl.ClickPoints)
        this._OperationCombo(body, "偏移值：", "ScrollOffset", ["0"], true, GetLang("正数向下、负数向上；像素偏移，Excel 按行折算。"))
        waits := body.Add("Grid").Name("WaitTypeRow").Cols("*", 16, "*")
        waitType := CmdEditorForm.Combo(this._Row(waits, "等待类型：", "WaitTypeChoice"), "WaitType").Grid_Column(1)
        for choice in WindowControl.WaitTypes
            waitType.Add("ComboBoxItem").Content(GetLang(choice))
        logic := this._Row(waits, "条件关系：", "WaitLogic", , "CommandRightLabel").Grid_Column(2)
        relation := CmdEditorForm.Combo(logic, "WaitLogic").Grid_Column(1)
        for choice in ["且", "或"]
            relation.Add("ComboBoxItem").Content(GetLang(choice))
        CmdEditorForm.ConditionPanel(body, "WaitConditionPanel", "WaitConditionScroll", "WaitConditions", "BtnAddWaitCondition")
        combo := CmdEditorForm.Combo(this._Row(body, "控件参数：", "Argument"), "Argument", true).Grid_Column(1)
            .Width("{Binding ActualWidth, ElementName=ActionType}").HorizontalAlignment("Left")
        for value in GetGuiVarReferences()
            CmdEditorForm.ComboItem(combo, value)
    }

    _OperationCombo(body, label, name, choices, editable := false, labelTip := "") {
        box := CmdEditorForm.Combo(this._Row(body, label, name, , , labelTip), name, editable).Grid_Column(1)
            .Width("{Binding ActualWidth, ElementName=ActionType}").HorizontalAlignment("Left")
        for choice in choices
            box.Add("ComboBoxItem").Content(GetLang(choice))
        return box
    }

    _SelectedOperationValue(name, choices, fallback := "") {
        index := this.ui.Query(name ">SelectedIndex")
        return IsInteger(index) && index >= 0 && index < choices.Length ? choices[Integer(index) + 1] : fallback
    }

    _BuildFields(body) {
        super._BuildFields(body)
        textRow := this._Row(body, "写入文本：", "ArgumentText", "Top")
        host := textRow.Add("Border").Grid_Column(1)
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness(1).CornerRadius(3)
            .Add("Grid")
        host.Cols("*", "Auto")
        host.Add("TextBox").Name("ArgumentText").Style("{StaticResource RmtMultiLineTextBox}")
            .Height(66).MinHeight(66).AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}").BorderThickness(0)
            .ScrollViewer_VerticalScrollBarVisibility("Auto").Padding("1.5,0,1.5,3")
        CmdEditorForm.IconButton(host, "BtnArgumentBuilder", 0xE70F, "文本构造")
            .Grid_Column(1).HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,3,3,0")
    }

    _BindFields() {
        super._BindFields()
        this.ui.OnEvent("ArgumentText", "TextChanged", XamlWin.BindCurrent(this, "OnArgumentTextChanged"))
        this.ui.OnEvent("BtnArgumentBuilder", "Click", XamlWin.BindCurrent(this, "OnArgumentBuilder"))
        this.ui.OnEvent("WaitType", "SelectionChanged", XamlWin.BindCurrent(this, "_RefreshConditionFields"))
        this.ui.OnEvent("BtnAddWaitCondition", "Click", XamlWin.BindCurrent(this, "OnAddWaitCondition"))
        this.ui.OnEvent("ClickType", "SelectionChanged", XamlWin.BindCurrent(this, "_RefreshClickFields"))
    }

    Init(cmd) {
        super.Init(cmd)
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs,
            InputField(this.Data, "TimeoutAction", TimeoutPolicy.DefaultAction),
            InputField(this.Data, "TimeoutStatusVar", TimeoutPolicy.DefaultStatusVar))
        this._writeKind := InputField(this.Data, "WriteKind", "text")
        this._ComboPush("WaitType", "SelectedIndex", CmdEnumIndex(InputField(this.Data, "WaitType", "等待出现"), WindowControl.WaitTypes))
        for field in ["ClickType", "ClickPoint"] {
            choices := field == "ClickType" ? WindowControl.ClickTypes : WindowControl.ClickPoints
            value := InputField(this.Data, field, "")
            if (field == "ClickType")
                value := WindowControl.NormalizeClickType(value)
            this._ComboPush(field, "SelectedIndex", Max(0, CmdEnumIndex(value, choices)))
        }
        this._ComboPush("ClickHoldMs", "ClearItems", "")
        for reference in GetGuiVarReferences()
            this._ComboPush("ClickHoldMs", "AddItem", reference)
        this._ComboPush("ClickHoldMs", "Text", String(WindowControl.ClickHoldValue(this.Data)))
        this._ComboPush("ClickPointLabel", "ToolTip", GetLang("区域随机在控件中心80%区域内取点。"))
        this._RefreshClickFields()
        for reference in GetGuiVarReferences()
            this._ComboPush("ScrollOffset", "AddItem", reference)
        this._ComboPush("ScrollOffset", "Text", String(InputField(this.Data, "ScrollOffset", 0)))
        this._conditionKind := InputField(this.Data, "WaitValueKind", "text")
        allowHalf := false
        try {
            if ((element := WindowControl.Find(this._PreviewSelector(this.Data.Selector)))
                && (profile := WindowControl.ProbeValue(element, true)).supported) {
                this._conditionKind := WindowControl.ValueKind(profile)
                allowHalf := this._conditionKind == "state" && InStr(profile.kind, "0.5")
            }
        }
        this._ComboPush("WaitLogic", "SelectedIndex", InputField(this.Data, "WaitLogic", "且") == "或" ? 1 : 0)
        this._RebuildWaitConditions(WindowControl.GetWaitConditions(this.Data), this._conditionKind, allowHalf)
        this._ComboPush("ArgumentText", "Text", this.Data.Argument)
        action := WindowControl.NormalizeAction(this.Data.ActionType)
        available := false
        for choice in this.Choices
            if (choice == action)
                available := true
        if (!available) {
            this._ComboPush("ActionType", "SelectedIndex", -1)
            this._ComboPush("WriteHintRow", "Visibility", "Visible")
            this._ComboPush("WriteHint", "Text", GetLang("此为旧版操作，原宏仍可执行；重新保存前请选择新操作。"))
        } else
            this._RefreshWriteFields(action)
    }

    _UpdateChoice(action) {
        this.HasTimeoutFields := WindowControl.UsesTimeout(action)
        ; 父类用 HasTimeoutFields 判断刷新，非等待时也必须主动收起。
        this._ComboPush("CommandTimeoutRow", "Visibility", this.HasTimeoutFields ? "Visible" : "Collapsed")
        this._ComboPush("WaitTypeRow", "Visibility", this.HasTimeoutFields ? "Visible" : "Collapsed")
        for field in ["ClickType", "ClickPoint"]
            this._ComboPush(field "Row", "Visibility", action == "点击控件" ? "Visible" : "Collapsed")
        this._RefreshClickFields()
        this._ComboPush("ScrollOffsetRow", "Visibility", action == "滚动到控件" ? "Visible" : "Collapsed")
        super._UpdateChoice(action)
        this._RefreshWriteFields(action)
        this._RefreshConditionFields()
    }

    _RefreshClickFields(*) {
        if (this._batching) {
            action := WindowControl.NormalizeAction(this.Data.ActionType)
            kind := WindowControl.NormalizeClickType(InputField(this.Data, "ClickType", ""))
        } else {
            action := this._ChoiceValue(this.ui.Query("ActionType"))
            kind := this._SelectedOperationValue("ClickType", WindowControl.ClickTypes, "左键单击")
        }
        this._ComboPush("ClickHoldMsRow", "Visibility", action == "点击控件" && InStr(kind, "长按") ? "Visible" : "Collapsed")
    }

    _WaitField(name, index) => index == 1 ? name : name "_" index

    _WaitConditionRow(index, canDelete) {
        row := XAML_Generator("Grid").Margin("0,2")
        row.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        row.Cols("*", 8, "*", 8, "*", 6, 28)
        ; 比较符两侧各让出 20px 给变量框，保留整行宽度与控件间距。
        CmdEditorForm.Combo(row, this._WaitField("WaitLeft", index), true).Margin("0,0,-20,0")
        CmdEditorForm.Combo(row, this._WaitField("WaitOperator", index)).Grid_Column(2).Margin("20,0,20,0")
        CmdEditorForm.Combo(row, this._WaitField("WaitValue", index), true).Grid_Column(4).Margin("-20,0,0,0")
        CmdEditorForm.IconButton(row, "BtnDeleteWaitCondition_" index, 0xE74D, "删除").Grid_Column(6)
            .IsEnabled(canDelete ? "True" : "False")
        return row.ToString()
    }

    _BindWaitConditionEvent(name, event, method, index) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(event))
            this.ui.events[name][event] := []
        this.ui.OnEvent(name, event, XamlWin.BindCurrent(this, method, index))
    }

    _RebuildWaitConditions(conditions, kind, allowHalf) {
        this._rebuildingWaitConditions := true
        try {
            this._waitConditionCount := conditions.Length
            this._ComboPush("WaitConditions", "ClearItems", "")
            for index, condition in conditions {
                this._ComboPush("WaitConditions", "AddXamlItem", this._WaitConditionRow(index, conditions.Length > 1))
                this._BindWaitConditionEvent(this._WaitField("WaitLeft", index), "SelectionChanged", "OnWaitConditionLeft", index)
                this._BindWaitConditionEvent(this._WaitField("WaitLeft", index), "LostKeyboardFocus", "OnWaitConditionLeft", index)
                this._BindWaitConditionEvent(this._WaitField("WaitOperator", index), "SelectionChanged", "OnWaitConditionOperator", index)
                this._BindWaitConditionEvent("BtnDeleteWaitCondition_" index, "Click", "OnDeleteWaitCondition", index)
            }
            this._FillConditionOptions(kind, allowHalf, conditions)
        } finally {
            this._rebuildingWaitConditions := false
        }
    }

    _ReadWaitConditions() {
        conditions := []
        loop this._waitConditionCount {
            index := A_Index
            left := this._WaitLeftValue(index)
            operator := GetLangKey(this.ui.Query(this._WaitField("WaitOperator", index)))
            value := this.ui.Query(this._WaitField("WaitValue", index))
            conditions.Push([operator, value, left])
        }
        return conditions
    }

    OnAddWaitCondition(*) {
        conditions := this._ReadWaitConditions()
        conditions.Push(["等于", "", "运行时控件值"])
        this._RebuildWaitConditions(conditions, this._conditionKind, this._conditionAllowsHalf)
        this.ui.Update("WaitConditionScroll", "ScrollToEnd", "")
    }

    OnDeleteWaitCondition(index, *) {
        if (this._waitConditionCount <= 1)
            return
        conditions := this._ReadWaitConditions()
        conditions.RemoveAt(index)
        this._RebuildWaitConditions(conditions, this._conditionKind, this._conditionAllowsHalf)
    }

    _WaitLeftValue(index) {
        left := this.ui.Query(this._WaitField("WaitLeft", index))
        return left == GetLang("运行时控件值") || left == "❖" GetLang("运行时控件值") ? "运行时控件值" : left
    }

    OnWaitConditionLeft(index, *) {
        if (this._batching || this._rebuildingWaitConditions || index > this._waitConditionCount || index > this._waitLeftKinds.Length)
            return
        left := this._WaitLeftValue(index)
        signature := WindowControl.IsRuntimeControlValue(left) ? "control" : "variable"
        if (this._waitLeftKinds[index] == signature)
            return
        this._FillConditionOptions(this._conditionKind, this._conditionAllowsHalf, this._ReadWaitConditions())
    }

    OnWaitConditionOperator(index, *) {
        if (!this._batching && !this._rebuildingWaitConditions && index <= this._waitConditionCount)
            this._RefreshWaitConditionValue(index)
    }

    _RefreshWaitConditionValue(index) {
        operator := GetLangKey(this.ui.Query(this._WaitField("WaitOperator", index)))
        this._SetWaitConditionValueVisibility(index, operator)
    }

    _SetWaitConditionValueVisibility(index, operator) {
        needsValue := operator != "为空" && operator != "不为空"
        this._ComboPush(this._WaitField("WaitValue", index), "Visibility", needsValue ? "Visible" : "Collapsed")
    }

    _RefreshConditionFields(*) {
        if (this._batching || this._rebuildingWaitConditions) {
            this._ComboPush("WaitConditionPanel", "Visibility", "Collapsed")
            this._ComboPush("WaitLogicRow", "Visibility", "Collapsed")
            this._ComboPush("WaitValueHintRow", "Visibility", "Collapsed")
            return
        }
        action := this._ChoiceValue(this.ui.Query("ActionType"))
        waitType := this._SelectedOperationValue("WaitType", WindowControl.WaitTypes, "等待出现")
        visible := action == "等待控件出现" && (waitType == "值满足条件" || waitType == "值不满足条件")
        this._ComboPush("WaitConditionPanel", "Visibility", visible ? "Visible" : "Collapsed")
        this._ComboPush("WaitLogicRow", "Visibility", visible ? "Visible" : "Collapsed")
        if (!visible) {
            this._ComboPush("WaitValueHintRow", "Visibility", "Collapsed")
            return
        }
        kind := this._conditionKind, hint := "", allowHalf := false
        try {
            if (element := WindowControl.Find(this._PreviewSelector(this.ui.Query("Selector")))) {
                result := WindowControl.ProbeValue(element, true)
                if (result.supported) {
                    kind := WindowControl.ValueKind(result)
                    allowHalf := kind == "state" && InStr(result.kind, "0.5")
                    hint := WindowControlPickOverlay.Prototype._ValueTip.Call({}, result)
                } else
                    hint := result.reason
            }
        }
        signature := kind "|" allowHalf
        this._conditionAllowsHalf := allowHalf
        if (this._conditionOperatorsKind != signature)
            this._FillConditionOptions(kind, allowHalf, this._ReadWaitConditions())
        loop this._waitConditionCount
            this._RefreshWaitConditionValue(A_Index)
        this._ComboPush("WaitValueHintRow", "Visibility", hint == "" ? "Collapsed" : "Visible")
        this._ComboPush("WaitValueHint", "Text", hint)
    }

    _FillConditionOptions(kind, allowHalf, conditions) {
        this._conditionKind := kind, this._conditionOperatorsKind := kind "|" allowHalf
        this._conditionAllowsHalf := allowHalf
        this._waitLeftKinds := []
        for index, condition in conditions {
            left := condition.Length >= 3 ? condition[3] : "运行时控件值"
            current := WindowControl.IsRuntimeControlValue(left)
            this._waitLeftKinds.Push(current ? "control" : "variable")
            operators := WindowControl.WaitConditionOperators(kind, left)
            leftField := this._WaitField("WaitLeft", index)
            this._ComboPush(leftField, "ClearItems", "")
            for reference in GetGuiVarReferences()
                this._ComboPush(leftField, "AddItem", reference)
            this._ComboPush(leftField, "AddItem", "❖" GetLang("运行时控件值"))
            this._ComboPush(leftField, "Text", current ? "❖" GetLang("运行时控件值") : left)
            operatorField := this._WaitField("WaitOperator", index)
            valueField := this._WaitField("WaitValue", index)
            this._ComboPush(operatorField, "ClearItems", "")
            for choice in operators
                this._ComboPush(operatorField, "AddItem", GetLang(choice))
            this._ComboPush(operatorField, "SelectedIndex", Max(0, CmdEnumIndex(condition[1], operators)))
            this._ComboPush(valueField, "ClearItems", "")
            if (current && kind == "state") {
                for state in ["0", "1"]
                    this._ComboPush(valueField, "AddItem", state)
                if (allowHalf)
                    this._ComboPush(valueField, "AddItem", "0.5")
            }
            for reference in GetGuiVarReferences()
                this._ComboPush(valueField, "AddItem", reference)
            this._ComboPush(valueField, "IsReadOnly", current && kind == "state" ? "True" : "False")
            this._ComboPush(valueField, "Text", condition[2])
            this._SetWaitConditionValueVisibility(index, CmdEnumIndex(condition[1], operators) >= 0 ? condition[1] : "等于")
        }
    }

    _RefreshWriteFields(action := "") {
        if (action == "")
            action := this._ChoiceValue(this.ui.Query("ActionType"))
        writing := action == "写入控件值"
        hint := "", stateType := ""
        if (writing) {
            try {
                selector := this._PreviewSelector(this.ui.Query("Selector"))
                if (element := WindowControl.Find(selector)) {
                    profile := WindowControl.ProbeWrite(element)
                    this._writeKind := profile.kind
                    stateType := profile.HasOwnProp("stateType") ? profile.stateType : ""
                    if (!profile.supported)
                        hint := profile.reason
                } else
                    hint := GetLang("未找到目标，执行时检查。")
            } catch as e {
                hint := WindowControl.IsControlReference(this.ui.Query("Selector")) ? GetLang("控件变量未就绪，执行时识别。") : e.Message
            }
            limits := Map("text", "文本或 {变量}，可用文本构造。", "state", "0/1 或 {变量}。",
                "index", "1～n 或 {变量}。", "ratio", "0～1 或 {变量}。")
            if (stateType == "expand")
                limits["state"] := "0折叠 / 1展开，支持 {变量}。"
            else if (stateType == "selection")
                limits["state"] := "0未选 / 1选中，支持 {变量}。"
            else if (stateType == "switch")
                limits["state"] := "0关闭 / 1开启，支持 {变量}。"
            else if (stateType == "toggle")
                limits["state"] := "0未勾 / 1勾选，支持 {变量}。"
            hint := (hint != "" ? hint " " : "") GetLang(limits.Get(this._writeKind, limits["text"]))
        }
        text := writing && this._writeKind == "text"
        if (writing && !text && this._argumentChoicesKind != this._writeKind) {
            value := this.ui.Query("Argument")
            this._ComboPush("Argument", "ClearItems", "")
            if (this._writeKind == "state") {
                for state in [0, 1]
                    this._ComboPush("Argument", "AddItem", String(state))
            }
            for reference in GetGuiVarReferences()
                this._ComboPush("Argument", "AddItem", reference)
            this._ComboPush("Argument", "Text", value)
            this._argumentChoicesKind := this._writeKind
        }
        this._ComboPush("ArgumentRow", "Visibility", writing && !text ? "Visible" : "Collapsed")
        this._ComboPush("ArgumentTextRow", "Visibility", text ? "Visible" : "Collapsed")
        this._ComboPush("WriteHintRow", "Visibility", hint == "" ? "Collapsed" : "Visible")
        this._ComboPush("WriteHint", "Text", hint)
        stateLabels := Map("expand", "展开状态：", "selection", "选中状态：", "switch", "开关状态：", "toggle", "勾选状态：")
        this._ComboPush("ArgumentLabel", "Text", GetLang(this._writeKind == "index" ? "选项序号：" : this._writeKind == "ratio" ? "写入比例：" : stateLabels.Get(stateType, "写入状态：")))
        this._ComboPush("ArgumentLabel", "ToolTip", hint)
        if (text && this.ui.Query("ArgumentText") != this.ui.Query("Argument"))
            this._ComboPush("ArgumentText", "Text", this.ui.Query("Argument"))
    }

    OnArgumentTextChanged(*) {
        this._ComboPush("Argument", "Text", this.ui.Query("ArgumentText"))
    }

    OnArgumentBuilder(*) {
        if (IsObject(this._textBuilder))
            this._textBuilder._CloseWindow()
        owner := this.ui
        builder := this._textBuilder := CharVarEditGui()
        builder.OwnerHwnd := this.Hwnd()
        builder.ParentTile := this.ParentTile
        builder.SureBtnAction := (text) => this.ui == owner ? this._SetArgumentText(text) : ""
        builder.ShowGui(this.ui.Query("Argument"))
    }

    _SetArgumentText(text) {
        this._ComboPush("Argument", "Text", text)
        this._ComboPush("ArgumentText", "Text", text)
    }

    _ApplyPick(ui, coords) {
        super._ApplyPick(ui, coords)
        this._RefreshWriteFields()
        this._RefreshConditionFields()
    }

    _ReadData() {
        if (Integer(this.ui.Query("ActionType>SelectedIndex")) < 0)
            throw Error(GetLang("请选择控件操作。"))
        data := super._ReadData()
        data.WriteKind := this._writeKind
        data.WaitType := WindowControl.UsesTimeout(data.ActionType) ? this._SelectedOperationValue("WaitType", WindowControl.WaitTypes, "等待出现") : "等待出现"
        data.ClickType := this._SelectedOperationValue("ClickType", WindowControl.ClickTypes, "左键单击")
        hold := Trim(this.ui.Query("ClickHoldMs"))
        data.ClickHoldMs := IsInteger(hold) ? Integer(hold) : hold
        data.ClickPoint := this._SelectedOperationValue("ClickPoint", WindowControl.ClickPoints, "中心点")
        data.ScrollOffset := Trim(this.ui.Query("ScrollOffset"))
        data.WaitLogic := this._SelectedOperationValue("WaitLogic", ["且", "或"], "且")
        data.WaitConditions := this._ReadWaitConditions()
        data.WaitOperator := data.WaitConditions[1][1]
        data.WaitValue := data.WaitConditions[1][2]
        data.WaitValueKind := this._conditionKind
        data.ErrorVar := ""
        if (!WindowControl.UsesTimeout(data.ActionType)) {
            data.TimeoutMs := TimeoutPolicy.DefaultMs
            data.TimeoutAction := ""
            data.TimeoutStatusVar := ""
        }
        return data
    }

    _Validate(data) {
        super._Validate(data)
        if (data.ActionType == "点击控件" && InStr(data.ClickType, "长按") && !TimeoutPolicy.IsVariable(data.ClickHoldMs))
            WindowControl.ResolveClickHoldMs(data.ClickHoldMs)
        if (data.ActionType == "写入控件值" && !RegExMatch(data.Argument, "\{[^{}]+\}"))
            WindowControl.ValidateWriteArgument(this._writeKind, data.Argument)
        if (data.ActionType == "滚动到控件" && !TimeoutPolicy.IsVariable(data.ScrollOffset)
            && (!IsInteger(data.ScrollOffset) || Abs(Number(data.ScrollOffset)) > 100000))
            throw Error(GetLang("偏移值应为 -100000～100000 的整数像素。"))
        if (data.ActionType == "等待控件出现" && (data.WaitType == "值满足条件" || data.WaitType == "值不满足条件")) {
            for condition in WindowControl.GetWaitConditions(data) {
                if (WindowControl.IsRuntimeControlValue(condition[3]))
                    this._ValidateWaitCondition(data.WaitValueKind, condition[2])
                else if (!TimeoutPolicy.IsVariable(condition[2]) && !TimeoutPolicy.IsVariable(condition[3]))
                    WindowControl.CompareValue(condition[3], condition[2], condition[1], WindowControl.WaitOperandKind(condition[1], condition[3], condition[2]))
            }
        }
    }

    _ValidateWaitCondition(kind, value) {
        if (kind != "text" && !TimeoutPolicy.IsVariable(value)) {
            if (!IsNumber(value))
                throw Error(GetLang("条件值必须为数字。"))
            if (kind == "state" && value != 0 && value != 1
                && !(this._conditionAllowsHalf && value == 0.5))
                throw Error(GetLang("状态条件值无效。"))
            if (kind == "ratio" && (value < 0 || value > 1))
                throw Error(GetLang("比例条件值应为 0～1。"))
            if (kind == "index" && (!IsInteger(value) || value < 0))
                throw Error(GetLang("序号条件值应为非负整数。"))
        }
    }

    _CloseBuilder() {
        if (IsObject(this._textBuilder))
            this._textBuilder._CloseWindow()
        this._textBuilder := ""
    }

    _CloseWindow() {
        this._StopOperationActions()
        this._CloseBuilder()
        super._CloseWindow()
    }

    OnWindowClosing(state, ctrl, event) {
        this._StopOperationActions()
        this._CloseBuilder()
        super.OnWindowClosing(state, ctrl, event)
    }
}

class WindowControlPickOverlay {
    __New(action := "", physicalClick := false) {
        this.action := action
        this.physicalClick := physicalClick
        ; 分层窗口穿透鼠标，不能成为 WindowFromPoint 的拾取结果。
        this.panel := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale")
        this.token := Gdip_Startup()
        this.lastRect := ""
        this._ShowTip()
    }

    Close() {
        CursorOutputTip.Show("")
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
            if (bounds && this._Draw(bounds)) {
                ; 降低跨进程文本读取频率，鼠标移动至其他控件时立即刷新。
                changed := !this.HasOwnProp("lastElement") || !WindowControl._Equals(bounds.element, this.lastElement)
                if (changed || !this.HasOwnProp("lastProbe") || A_TickCount - this.lastProbe >= 400) {
                    tip := ""
                    if (this.action == "点击控件") {
                        profile := WindowControl.ProbeClick(bounds.element, this.physicalClick)
                        tip .= GetLang(profile.supported ? "可以点击此控件。" : "此控件点击大概率无效。")
                    } else if (this.action == "展开/折叠") {
                        profile := WindowControl.ProbeExpand(bounds.element)
                        tip .= GetLang(profile.supported ? "适合展开/折叠：" : "不适合展开/折叠：") profile.reason
                    } else if (this.action == "写入控件值") {
                        profile := WindowControl.ProbeWrite(bounds.element)
                        kinds := Map("text", "文本", "state", "0/1 状态", "index", "1～n 选项序号", "ratio", "0～1 比例")
                        tip .= profile.supported ? GetLang("可写入值：") GetLang(kinds[profile.kind])
                            : GetLang("无法写入值：") profile.reason
                    } else if (this.action == "读取控件值") {
                        result := WindowControl.ProbeValue(bounds.element, true)
                        if (result.supported)
                            tip .= this._ValueTip(result)
                        else
                            tip .= GetLang("无法读取值：") result.reason
                    }
                    this._ShowTip(tip)
                    this.lastElement := bounds.element
                    this.lastProbe := A_TickCount
                }
                this._RaiseTip()
                return
            }
        }
        if (this.HasOwnProp("lastElement")) {
            this.DeleteProp("lastElement")
            this._ShowTip(this.action == "检测控件存在" || this.action == "读取控件信息" ? "" : GetLang("未找到可拾取控件。"))
        }
        if (this.lastRect != "") {
            this.panel.Hide()
            this.lastRect := ""
        }
    }

    _ShowTip(text := "") => CursorOutputTip.Show(text, 0x7FFFFFFF, false, false, true)

    _RaiseTip() {
        ; 遮罩重新显示后，将不激活、穿透鼠标的 XAML 提示置于其上。
        if (IsObject(CursorOutputTip.ui) && (hwnd := CursorOutputTip.ui.wpfHwnd))
            DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)
    }

    _ValueTip(result) {
        descriptions := Map(
            GetLang("开关状态（0/1）"), GetLang("开关状态，0关/1开"),
            GetLang("勾选状态（0/1，半选 0.5）"), GetLang("勾选状态，0未勾/1勾选/0.5半选"),
            GetLang("选中状态（0/1）"), GetLang("选中状态，0未选/1选中"),
            GetLang("展开状态（0/1）"), GetLang("展开状态，0折叠/1展开"),
            GetLang("范围比例（0～1）"), GetLang("比例，0～1"),
            GetLang("选项序号（1～n，未选 0）"), GetLang("选项序号，0未选/1～n"))
        preview := StrReplace(StrReplace(String(result.value), "`r", ""), "`n", " ↵ ")
        preview := preview == "" ? GetLang("空文本") : SubStr(preview, 1, 100)
        return GetLang("值：") preview "（" descriptions.Get(result.kind, result.kind) "）"
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
    _options := []
    _previewField := ""
    _previewTimer := 0
    _playHotkeys := []
    _testRunning := false

    __New() {
        super.__New()
        this._areaPreview := ScreenAreaPreview()
    }

    ShowGui(cmd) {
        if (A_IsCompiled && !AiAssist.IsConfigured())
            RmtDialog.Info(GetLang("请先在设置-AI中填写 API Key、API URL 与模型"), GetLang(this.CmdKey), this.OwnerHwnd)
        super.ShowGui(cmd)
    }

    _PlayAction() => XamlWin.BindCurrent(this, "TriggerMacro")

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        if (!this._playHotkeys.Length && this.Hwnd())
            this._playHotkeys := WinHotkey.Register(["!l"], this._PlayAction(), this.Hwnd())
    }

    TriggerMacro(*) {
        if (this._testRunning || !this.CheckIfValid())
            return
        ui := this.ui
        this._testRunning := true
        try {
            this.SaveData()
            resultVar := this.Data.ResultVar
            if (OnTriggerSepcialItemMacro(this.GetCommandStr(), false, this.WindowBindingContext)
                && this.ui == ui && MySoftData.VariableMap.Has(resultVar)) {
                value := MySoftData.VariableMap[resultVar]
                RmtDialog.Info(resultVar " = " value, GetLang(this.CmdKey), this.Hwnd())
            }
        } finally {
            this._testRunning := false
        }
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

        binding := this._Row(body, "窗口绑定：", "WinInfo").Visibility("Collapsed").Add("Grid").Grid_Column(1)
        binding.Cols("*", 6, "Auto")
        CmdEditorForm.WindowBindingCombo(binding, "WinInfo")
        CmdEditorForm.TextButton(binding, "BtnWinEdit", "编辑").Grid_Column(2)
        this._BuildRange(body, "Region")
        this._BuildRange(body, "WindowRegion")

        choices := this._Row(body, "候选选项：", "Options", "Top").Add("StackPanel").Grid_Column(1)
        border := choices.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(4)
        scroll := border.Add("ScrollViewer").Name("ChoicesScroll").Height(4 * 30)
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
        list := scroll.Add("StackPanel").Margin("6,0")
        list.Add("StackPanel").Name("ChoiceRows")
        add := list.Add("Button").Name("AddChoice").ToolTip(GetLang("添加选项"))
            .Width(28).Height(26).MinHeight(26).Padding("0").Cursor("Hand")
            .HorizontalAlignment("Center").Margin("0,2")
            .HorizontalContentAlignment("Center").VerticalContentAlignment("Center")
        add.Add("Path").Data("M 0,5 H 10 M 5,0 V 10").Width(12).Height(12).Stretch("Uniform")
            .Stroke("{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}").StrokeThickness(1.2)
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
                    .Height(28).MinHeight(28)
                for value in (field == "Region" ? GetGuiVarReferences(StrLower(axis)) : GetGuiVarReferences())
                    CmdEditorForm.ComboItem(combo, value)
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

    _Placeholder(parent, field, text, multiline := false) {
        label := parent.Add("TextBlock").Text(text).IsHitTestVisible("False")
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
            this._SetRange(this.ui, field, value == "" ? [0, 0, A_ScreenWidth, A_ScreenHeight] : StrSplit(value, ","))
        }
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs, TimeoutPolicy.Get(this.Data), TimeoutPolicy.StatusVar(this.Data))
        options := AiDecision.ParseOptions(this.Data.Options, false)
        if (!options.Length) {
            loop AiDecisionGui.OptionExamples.Length {
                value := String(A_Index)
                options.Push({Label: "", Value: value, DefaultValue: value})
            }
        }
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
            if (label == "" && (value == "" || value == InputField(option, "DefaultValue")))
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
        loop this._options.Length
            fields.Push("OptionLabel_" A_Index, "OptionValue_" A_Index)
        state := this.ui.Query(fields*)
        options := []
        for i, original in this._options {
            option := original.Clone()
            option.Label := state.Get("OptionLabel_" i, "")
            option.Value := state.Get("OptionValue_" i, "")
            options.Push(option)
        }
        return options
    }

    _RenderOptions(options) {
        this._options := options
        this._ComboPush("ChoiceRows", "ClearItems", "")
        for i, option in options {
            name := "DeleteChoice_" i
            row := XAML_Generator("Grid").Margin("0,2")
            row.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
            ; 两列平分剩余宽度，选项列多占 300，实际各增减 150。
            row.Cols(300, "*", 8, "*", 8, 28)
            this._TextBox(row, "OptionLabel_" i).Grid_ColumnSpan(2)
            this._TextBox(row, "OptionValue_" i).Grid_Column(3).ToolTip(GetLang("留空时保存选项名称"))
            if (AiDecisionGui.OptionExamples.Has(i))
                this._Placeholder(row, "OptionLabel_" i, GetLang(AiDecisionGui.OptionExamples[i]))
            CmdEditorForm.IconButton(row, name, 0xE74D, "删除").Grid_Column(5)
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

    _PickErrorMessage(error) {
        if (error is TargetError)
            return GetLang("未找到目标窗口。")
        if (error is ValueError)
            return GetLang("框选范围必须在窗口客户区内。")
        return GetLang("框选范围失败。")
    }

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
        this._UnregisterPlayHotkeys()
        this._CloseAreaPreview()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        this._UnregisterPlayHotkeys()
        this._CloseAreaPreview()
        super._CloseWindow()
    }

    _UnregisterPlayHotkeys() {
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
    }
}
