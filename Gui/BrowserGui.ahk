#Requires AutoHotkey v2.0

; ==============================================================================
; 浏览器编辑器 (BrowserGui)
; ==============================================================================

class BrowserGui extends CommentGui {
    ; 分组结构定义
    static Groups := [
        {
            name: "页签",
            actions: ["打开网址", "当前页跳转", "新建分页", "切换分页", "关闭分页", "刷新", "后退", "前进", "关闭"]
        },
        {
            name: "等待条件",
            actions: ["等待元素", "等待文字", "等待加载"]
        },
        {
            name: "元素互动",
            actions: ["点击", "输入", "清空", "选择下拉", "勾选", "滚动至元素", "悬停"]
        },
        {
            name: "数据提取",
            actions: ["提取文本", "提取控件值", "提取属性", "提取HTML", "元素数量", "获取网址", "获取标题", "获取分页列表"]
        },
        {
            name: "页面工具",
            actions: ["网页截图", "执行JS"]
        }
    ]

    static SelectorTypes := ["CSS", "XPath"]
    static Conditions := ["出现", "消失", "可见"]
    static LoadStates := ["完全加载", "DOM加载", "网络空闲"]
    static CompactInputWidth := 168

    _textEditor := ""
    _picking := false
    _updatingActions := false

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("浏览器")
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)

        body := main.Add("StackPanel").Grid_Row(1).Margin("16,10")
        this._Field(body, "备注：", "Remark", false)

        actions := this._Row(body, "动作类型：").Add("Grid").Grid_Column(1)
        this._GridWidths(actions, "*", 8, "*")
        groupNames := []
        for group in BrowserGui.Groups
            groupNames.Push(group.name)
        this._Choice(actions, "ActionGroup", groupNames)
        this._Choice(actions, "ActionType", BrowserGui.Groups[1].actions).Grid_Column(2)

        this._Choice(this._Row(body, "浏览器：", "BrowserRow"), "BrowserType", []).Grid_Column(1)
        this._Choice(this._Row(body, "浏览器：", "CloseBrowserRow"), "CloseBrowserType", BrowserUtil.CloseBrowserTypes).Grid_Column(1)
        this._Field(body, "浏览器路径：", "BrowserPath", false, 28, "BrowserPathRow")
        this._Choice(this._Row(body, "页签范围：", "CloseScopeRow"), "CloseScope", BrowserUtil.CloseScopes).Grid_Column(1)
        this._Field(body, "目标分页：", "TargetRef", false, 28, "TargetRefRow")
        urlRow := this._Row(body, "网址：", "UrlRow")
        this._TextBox(urlRow, "Url").Grid_Column(1).TextWrapping("NoWrap")
            .ScrollViewer_HorizontalScrollBarVisibility("Hidden")
            .ToolTip("{Binding Text, RelativeSource={RelativeSource Self}}")

        selector := this._Row(body, "元素选择器：", "SelectorRow").Add("Grid").Grid_Column(1)
        this._GridWidths(selector, 88, 6, "*", 6, "Auto")
        this._Choice(selector, "SelectorType", BrowserGui.SelectorTypes).ToolTip(GetLang("选择器类型：")).Grid_Column(0)
        this._TextBox(selector, "Selector").Grid_Column(2).HorizontalScrollBarVisibility("Hidden")
        selector.Add("Button").Name("BtnPickSelector").Grid_Column(4).Height(28).MinHeight(28)
            .Padding("10,0").Cursor("Hand").Content(GetLang("拾取")).ToolTip(GetLang("拾取网页元素"))

        this._Choice(this._Row(body, "等待状态：", "ConditionRow"), "Condition", BrowserGui.Conditions).Grid_Column(1)
        this._Choice(this._Row(body, "加载状态：", "LoadStateRow"), "LoadState", BrowserGui.LoadStates).Grid_Column(1)
        textRow := body.Add("Grid").Name("TextRow").Margin("0,3")
        this._Columns(textRow)
        textRow.Add("TextBlock").Name("TextLabel").VerticalAlignment("Center").Margin("0,0,8,0")
            .TextWrapping("Wrap").Foreground("{DynamicResource TextMain}")
        this._TextBox(textRow, "Text").Grid_Column(1)

        for option in [
            ["ClearBefore", "清空输入框"],
            ["Checked", "勾选(取消则不勾)"],
            ["FullPage", "全页完整截图"],
            ["IncludeTag", "包含元素标签"]
        ] {
            row := this._Row(body, "选项设置：", option[1] "Row")
            row.Add("CheckBox").Name(option[1]).Grid_Column(1).Content(GetLang(option[2])).VerticalAlignment("Center")
                .Foreground("{DynamicResource TextMain}")
        }

        this._Field(body, "JS 脚本：", "JsCode", true, 78, "JsCodeRow")
        this._Field(body, "属性名称：", "AttrName", false, 28, "AttrNameRow")
        this._Field(body, "截图路径：", "SavePath", false, 28, "SavePathRow")

        execution := body.Add("Grid")
        execution.Cols("*", 18, "*")
        timeout := this._Row(execution, "超时(ms)：", "TimeoutRow")
        this._TextBox(timeout, "TimeoutMs").Grid_Column(1).Width(BrowserGui.CompactInputWidth).HorizontalAlignment("Left")
        timeoutAction := this._Row(execution, "超时处理：", "TimeoutActionRow").Grid_Column(2)
        this._Choice(timeoutAction, "TimeoutAction", TimeoutPolicy.Actions).Grid_Column(1)

        saveRow := this._Row(body, "结果变量：", "SaveVarRow")
        saveRow.Add("ComboBox").Name("SaveVar").Grid_Column(1)
            .Width(BrowserGui.CompactInputWidth).HorizontalAlignment("Left")
            .Height(28).MinHeight(28).IsEditable("True").Padding("5,0,21,0")
            .ToolTip(GetLang("留空时不保存结果"))

        buttons := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,8,0,0")
        AddCmdOkBtn(buttons)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnEditJsCode", "Click", ObjBindMethod(this, "_QueueTextEditor", "JsCode"))
        this.ui.OnEvent("ActionGroup", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionGroupChanged"))
        this.ui.OnEvent("ActionType", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionTypeChanged"))
        for name in ["BrowserType", "CloseBrowserType"]
            this.ui.OnEvent(name, "SelectionChanged", XamlWin.BindCurrent(this, "OnFieldsChanged"))
        this.ui.OnEvent("BtnPickSelector", "Click", (*) => SetTimer(this._PickSelector.Bind(this, this.ui), -1))

        BindCmdEditorChrome(this.ui, "#指令手册/浏览器")
    }

    _Row(body, label, rowName := "") {
        row := body.Add("Grid").Margin("0,3")
        if (rowName != "")
            row.Name(rowName)
        this._Columns(row)
        row.Add("TextBlock").Text(GetLang(label)).VerticalAlignment("Center").Margin("0,0,8,0")
            .TextWrapping("Wrap").Foreground("{DynamicResource TextMain}")
        return row
    }

    _GridWidths(grid, widths*) {
        columns := grid.Add("Grid.ColumnDefinitions")
        for width in widths
            columns.Add("ColumnDefinition").Width(width)
    }

    _Columns(grid) {
        labelWidth := Ceil(XAMLHost.GetThemeFontSize() * 6) + 8
        grid.Cols(labelWidth, "*")
    }

    _Field(body, label, name, multiline, height := 28, rowName := "") {
        row := this._Row(body, label, rowName)
        if (!multiline) {
            this._TextBox(row, name, height).Grid_Column(1)
            return
        }
        host := row.Add("Grid").Grid_Column(1)
        this._TextBox(host, name, height).AcceptsReturn("True").TextWrapping("Wrap").Padding("2,3,15,3")
            .VerticalContentAlignment("Top").ScrollViewer_VerticalScrollBarVisibility("Auto")
        host.Add("Button").Name("BtnEdit" name).Width(22).Height(22).MinHeight(22).Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12).Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
    }

    _TextBox(parent, name, height := 28) {
        return parent.Add("TextBox").Name(name).Height(height).MinHeight(height).VerticalContentAlignment("Center")
            .Padding("2,0,2,0").Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
    }

    _Choice(parent, name, values) {
        box := parent.Add("ComboBox").Name(name).Height(28).MinHeight(28).Padding("7,0,23,0").SelectedIndex(0)
        for value in values
            box.Add("ComboBoxItem").Content(GetLang(value)).Tag(value)
        return box
    }

    _QueueTextEditor(name, *) {
        SetTimer(ObjBindMethod(this, "_OpenTextEditor", this.ui, name), -1)
    }

    _OpenTextEditor(ui, name) {
        if (this.ui != ui)
            return
        if (!IsObject(this._textEditor))
            this._textEditor := CharVarEditGui()
        this._textEditor.OwnerHwnd := this.Hwnd()
        this._textEditor.ParentTile := this.ParentTile
        this._textEditor.SureBtnAction := (text) => this.ui == ui ? ui.Update(name, "Text", text) : ""
        this._textEditor.ShowGui(ui.Query(name))
    }

    OnActionGroupChanged(*) {
        if (this._updatingActions)
            return
        groupName := this.ui.Query("ActionGroup")
        for group in BrowserGui.Groups {
            if (GetLang(group.name) != groupName)
                continue
            actions := group.actions
            if (actions == this._activeActions)
                return
            this._activeActions := actions
            this._updatingActions := true
            try {
                this.ui.Update("ActionType", "ClearItems", "")
                for action in actions
                    this.ui.Update("ActionType", "AddItem", GetLang(action))
                this.ui.Update("ActionType", "SelectedIndex", 0)
            } finally this._updatingActions := false
            break
        }
        this.OnFieldsChanged()
    }

    OnActionTypeChanged(*) {
        if (!this._updatingActions)
            this.OnFieldsChanged()
    }

    _Action(displayValue) {
        for action in this._activeActions
            if (GetLang(action) == displayValue)
                return action
        return this._activeActions[1]
    }

    OnFieldsChanged(*) {
        state := this.ui.Query("ActionType", "BrowserType", "CloseBrowserType")
        action := this._Action(state.Get("ActionType", ""))
        browser := action == "关闭"
            ? CmdEnumZh(state.Get("CloseBrowserType", ""), BrowserUtil.CloseBrowserTypes)
            : CmdEnumZh(state.Get("BrowserType", ""), this._browserNames)
        this._UpdateFieldVisibilities(action, browser)
    }

    _UpdateFieldVisibilities(action, browser) {
        textLabels := Map("输入", GetLang("输入内容："), "等待文字", GetLang("匹配文字："),
                          "选择下拉", GetLang("选项值："))
        isOpen := action == "打开网址"
        isClose := action == "关闭"
        hasSelector := this._UsesSelector(action)
        hasTimeout := isOpen || action == "当前页跳转" || action == "等待加载"
            || (hasSelector && action != "元素数量")
        rows := Map(
            "BrowserRow", isOpen, "CloseBrowserRow", isClose, "CloseScopeRow", isClose,
            "BrowserPathRow", (isOpen && browser == "自定义路径") || (isClose && browser == "自定义"),
            "UrlRow", isOpen || action == "当前页跳转" || action == "新建分页",
            "TargetRefRow", action == "切换分页" || action == "关闭分页",
            "SelectorRow", hasSelector, "ConditionRow", action == "等待元素",
            "LoadStateRow", action == "等待加载", "TextRow", textLabels.Has(action),
            "ClearBeforeRow", action == "输入", "CheckedRow", action == "勾选",
            "FullPageRow", action == "网页截图", "IncludeTagRow", action == "提取HTML",
            "JsCodeRow", action == "执行JS", "AttrNameRow", action == "提取属性",
            "SavePathRow", action == "网页截图", "TimeoutRow", hasTimeout,
            "TimeoutActionRow", !isClose, "SaveVarRow", !isClose)
        for name, visible in rows
            this._ComboPush(name, "Visibility", visible ? "Visible" : "Collapsed")
        if (textLabels.Has(action))
            this._ComboPush("TextLabel", "Text", textLabels[action])
    }

    _UsesSelector(action) {
        static actions := Map("等待元素", true, "等待文字", true, "点击", true, "输入", true,
            "清空", true, "选择下拉", true, "勾选", true, "滚动至元素", true, "悬停", true,
            "元素数量", true, "提取文本", true, "提取控件值", true, "提取属性", true, "提取HTML", true)
        return actions.Has(action)
    }

    _PickSelector(ui) {
        if (this.ui != ui)
            return
        if (this._picking) {
            this._FinishPicker()
            return
        }
        this._picking := true
        try {
            tabs := JSON.parse(BrowserUtil.GetTabs())
            if (!tabs.Length)
                throw Error(GetLang("没有可拾取的网页。"))
            pages := []
            for candidate in tabs
                if (RegExMatch(candidate["url"], "i)^(https?|file)://"))
                    pages.Push(candidate)
            tab := pages.Length ? pages[1] : tabs[1]
            url := ""
            if (pages.Length != 1) {
                tabs := pages.Length ? pages : tabs
                prompt := GetLang("输入分页编号或要打开的网页网址。")
                for i, candidate in tabs
                    prompt .= "`n" i ". " SubStr(candidate["title"] != "" ? candidate["title"] : candidate["url"], 1, 72)
                result := RmtDialog.Input(prompt, GetLang("拾取网页元素"), pages.Length ? "1" : "", this.Hwnd())
                if (result.Result != "OK" || this.ui != ui || !this._picking)
                    return
                value := Trim(result.Value)
                if (IsInteger(value) && Integer(value) >= 1 && Integer(value) <= tabs.Length)
                    tab := tabs[Integer(value)]
                else if (RegExMatch(value, "i)^(https?|file)://"))
                    url := value
                else
                    throw Error(GetLang("请输入有效的分页编号或网址。"))
            }
            BrowserUtil.SwitchTab(tab["targetId"])
            if (url != "")
                BrowserUtil.Navigate(url)
            if (!RegExMatch(BrowserUtil.GetUrl(), "i)^(https?|file)://"))
                throw Error(GetLang("请先打开要拾取的网页。"))

            this._pickerToken := "__rmtPick_" DllCall("GetCurrentProcessId", "UInt") "_" A_TickCount
            selectorType := CmdEnumZh(ui.Query("SelectorType"), BrowserGui.SelectorTypes)
            action := this._Action(ui.Query("ActionType"))
            preferControl := action == "点击" || action == "输入" || action == "清空"
                || action == "选择下拉" || action == "勾选" || action == "提取控件值"
            BrowserUtil.StartElementPicker(this._pickerToken, selectorType, preferControl)
            this._pickTimer := this._PollPicker.Bind(this, ui, this._pickerToken, selectorType)
            SetTimer(this._pickTimer, 150)
            ui.Update("BtnPickSelector", "Content", GetLang("取消"))
            ui.Update("BtnPickSelector", "ToolTip", GetLang("取消拾取"))
            Toast.Info(GetLang("在网页上单击选取，按 Esc 取消。"))
        } catch as e {
            if (this.ui == ui)
                RmtDialog.Info(GetLang(e.Message), GetLang("拾取网页元素"), this.Hwnd())
        } finally {
            if (!this.HasOwnProp("_pickTimer") && this._picking)
                this._FinishPicker()
        }
    }

    _PollPicker(ui, token, selectorType) {
        if (this.ui != ui || this._pickerToken != token)
            return
        try {
            state := BrowserUtil.Evaluate("window." token "?.result ?? 'missing'")
            if (state == "pending")
                return
            if (SubStr(state, 1, 7) == "picked:") {
                ui.Update("SelectorType", "SelectedIndex", CmdEnumIndex(selectorType, BrowserGui.SelectorTypes))
                ui.Update("Selector", "Text", SubStr(state, 8))
            } else if (state != "cancelled") {
                Toast.Info(GetLang("网页已切换或关闭，请重新拾取。"))
            }
        } catch {
            Toast.Info(GetLang("网页已切换或关闭，请重新拾取。"))
        }
        this._FinishPicker()
        try WinActivate(this.Hwnd())
    }

    _FinishPicker() {
        if (this.HasOwnProp("_pickTimer")) {
            SetTimer(this._pickTimer, 0)
            this.DeleteProp("_pickTimer")
        }
        if (this.HasOwnProp("_pickerToken")) {
            try BrowserUtil.Evaluate("window." this._pickerToken "?.stop()")
            this.DeleteProp("_pickerToken")
        }
        this._picking := false
        if (IsObject(this.ui)) {
            this.ui.Update("BtnPickSelector", "Content", GetLang("拾取"))
            this.ui.Update("BtnPickSelector", "ToolTip", GetLang("拾取网页元素"))
        }
    }

    OnWindowClosing(state, ctrl, event) {
        if (this._picking)
            this._FinishPicker()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        if (this._picking)
            this._FinishPicker()
        super._CloseWindow()
    }

    Init(cmd) {
        parts := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr("浏览器")
        this.Data := GetMacroCMDData(this.SerialStr).Clone()
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")

        defaults := BrowserData()
        for name, value in defaults.OwnProps()
            if (!this.Data.HasOwnProp(name))
                this.Data.%name% := value
        actionType := CmdEnumZh(this.Data.ActionType, BrowserUtil.Actions)
        if (actionType == "关闭标签")
            actionType := "关闭分页"
        else if (actionType == "关闭浏览器")
            actionType := "关闭"

        this._browserNames := []
        seen := Map()
        for browser in BrowserUtil.GetInstalledBrowsers() {
            if (!seen.Has(browser.name))
                this._browserNames.Push(browser.name)
            seen[browser.name] := true
        }
        if (!this._browserNames.Length) {
            this._browserNames := ["Chrome", "Edge"]
            seen["Chrome"] := seen["Edge"] := true
        }
        browserType := GetLangKey(this.Data.BrowserType)
        closeBrowserType := BrowserUtil.GetCloseBrowserType(browserType)
        if (browserType == "自定义")
            browserType := "自定义路径"
        if (parts.Length && browserType != "" && browserType != "自定义路径" && browserType != "所有浏览器" && !seen.Has(browserType))
            this._browserNames.Push(browserType)
        this._browserNames.Push("自定义路径")
        for name in this._browserNames
            this._ComboPush("BrowserType", "AddItem", GetLang(name))

        for varName in GetGuiVarArr()
            if (varName != "")
                this._ComboPush("SaveVar", "AddItem", varName)
        for name in ["Url", "TargetRef", "Selector", "JsCode", "AttrName", "TimeoutMs", "BrowserPath"]
            this._ComboPush(name, "Text", String(this.Data.%name%))
        this._ComboPush("SaveVar", "Text", GetLang(this.Data.SaveVar))
        this._ComboPush(actionType == "网页截图" ? "SavePath" : "Text", "Text", String(this.Data.Text))
        this._ComboPush("ClearBefore", "IsChecked", this.Data.ClearBefore ? "True" : "False")
        this._ComboPush("Checked", "IsChecked", this.Data.Checked ? "True" : "False")
        this._ComboPush("FullPage", "IsChecked", actionType == "网页截图" && this.Data.OuterHtml ? "True" : "False")
        this._ComboPush("IncludeTag", "IsChecked", actionType != "提取HTML" || this.Data.OuterHtml ? "True" : "False")

        for groupIndex, group in BrowserGui.Groups {
            for actionIndex, action in group.actions {
                if (action == actionType) {
                    this._activeActions := group.actions
                    this._ComboPush("ActionGroup", "SelectedIndex", groupIndex - 1)
                    this._ComboPush("ActionType", "ClearItems", "")
                    for name in group.actions
                        this._ComboPush("ActionType", "AddItem", GetLang(name))
                    this._ComboPush("ActionType", "SelectedIndex", actionIndex - 1)
                    break 2
                }
            }
        }
        for name, values in Map("SelectorType", BrowserGui.SelectorTypes, "Condition", BrowserGui.Conditions,
            "LoadState", BrowserGui.LoadStates, "BrowserType", this._browserNames)
            this._ComboPush(name, "SelectedIndex", CmdEnumIndex((name == "BrowserType" ? browserType : this.Data.%name%), values))
        timeoutAction := this.Data.TimeoutAction
        if (timeoutAction == "") {
            onError := GetLangKey(this.Data.OnError)
            timeoutAction := onError
            if (onError == "重试") {
                retries := IsInteger(this.Data.RetryCount) ? Max(0, Integer(this.Data.RetryCount) - 1) : ""
                timeoutAction := TimeoutPolicy.LegacyRetryAction(retries)
            }
        }
        this._ComboPush("TimeoutAction", "SelectedIndex", timeoutAction == "" ? -1 : CmdEnumIndex(timeoutAction, TimeoutPolicy.Actions))
        if (timeoutAction == "")
            this._ComboPush("TimeoutAction", "ToolTip", GetLang("选择超时处理方式前，保留旧重试设置。"))
        this._ComboPush("CloseBrowserType", "SelectedIndex", CmdEnumIndex(closeBrowserType, BrowserUtil.CloseBrowserTypes))
        this._ComboPush("CloseScope", "SelectedIndex", CmdEnumIndex(this.Data.CloseScope, BrowserUtil.CloseScopes))
        this._UpdateFieldVisibilities(actionType, actionType == "关闭"
            ? CmdEnumZh(closeBrowserType, BrowserUtil.CloseBrowserTypes) : CmdEnumZh(browserType, this._browserNames))
    }

    _ReadData() {
        data := this.Data.Clone()
        state := this.ui.Query("ActionType", "BrowserType", "CloseBrowserType", "CloseScope", "BrowserPath", "TargetRef", "Url",
            "SelectorType", "Selector", "Condition", "LoadState", "Text", "SavePath", "ClearBefore",
            "Checked", "FullPage", "IncludeTag", "JsCode", "AttrName", "SaveVar", "TimeoutMs", "TimeoutAction")
        data.ActionType := this._Action(state["ActionType"])
        if (data.ActionType == "关闭") {
            data.BrowserType := CmdEnumZh(state["CloseBrowserType"], BrowserUtil.CloseBrowserTypes)
            data.CloseScope := CmdEnumZh(state["CloseScope"], BrowserUtil.CloseScopes)
            data.BrowserPath := data.BrowserType == "自定义" ? state["BrowserPath"] : ""
            data.OnError := "忽略"
            data.SaveVar := ""
            return data
        }
        for name, values in Map("SelectorType", BrowserGui.SelectorTypes, "Condition", BrowserGui.Conditions,
            "LoadState", BrowserGui.LoadStates, "BrowserType", this._browserNames)
            data.%name% := CmdEnumZh(state[name], values)
        data.TimeoutAction := GetLangKey(state["TimeoutAction"])
        for name in ["Url", "TargetRef", "Selector", "JsCode", "AttrName", "BrowserPath", "TimeoutMs"]
            data.%name% := state[name]
        data.Text := state[data.ActionType == "网页截图" ? "SavePath" : "Text"]
        data.ClearBefore := state["ClearBefore"] == "True"
        data.Checked := state["Checked"] == "True"
        data.OuterHtml := state[data.ActionType == "网页截图" ? "FullPage" : "IncludeTag"] == "True"
        data.SaveVar := GetVarName(Trim(state["SaveVar"]))
        return data
    }

    CheckIfValid() {
        data := this._ReadData()
        message := ""
        if (data.ActionType == "关闭") {
            if (data.BrowserType == "自定义" && Trim(data.BrowserPath) == "")
                message := GetLang("浏览器路径不能为空。")
        } else if (!IsInteger(data.TimeoutMs) || Integer(data.TimeoutMs) < 1 || Integer(data.TimeoutMs) > 2147483647)
            message := GetLang("超时必须是正整数。")
        else if ((data.ActionType == "打开网址" || data.ActionType == "当前页跳转") && Trim(data.Url) == "")
            message := GetLang("网址不能为空。")
        else if (data.ActionType == "打开网址" && data.BrowserType == "自定义路径" && Trim(data.BrowserPath) == "")
            message := GetLang("浏览器路径不能为空。")
        else if (this._UsesSelector(data.ActionType) && data.ActionType != "等待文字" && data.ActionType != "提取文本"
            && data.ActionType != "提取HTML" && Trim(data.Selector) == "")
            message := GetLang("元素选择器不能为空。")
        else if (data.ActionType == "提取属性" && Trim(data.AttrName) == "")
            message := GetLang("属性名称不能为空。")
        else if (data.ActionType == "执行JS" && Trim(data.JsCode) == "")
            message := GetLang("JavaScript 脚本不能为空。")
        if (message != "") {
            RmtDialog.Info(message, GetLang("浏览器"), this.Hwnd())
            return false
        }
        return data.SaveVar == "" || CheckVarNameIfValid(data.SaveVar)
    }

    SaveData() {
        this.Data := this._ReadData()
        if (this.Data.ActionType != "关闭")
            this.Data.TimeoutMs := Integer(this.Data.TimeoutMs)
        if (this.Data.SaveVar != "") {
            for suffix in ["", "_Success", "_Error", "_ElapsedMs"]
                MySoftData.GlobalVariMap[this.Data.SaveVar suffix] := true
        }
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang("浏览器") RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }
}
