#Requires AutoHotkey v2.0
#Include BrowserKeyPickerGui.ahk

; ==============================================================================
; 浏览器编辑器 (BrowserGui)
; ==============================================================================

class BrowserGui extends CommentGui {
    static SelectorTypes := ["CSS", "XPath"]
    static Conditions := ["出现", "消失", "可见"]
    static LoadStates := ["完全加载", "DOM加载", "网络空闲"]
    static MouseButtons := ["左键", "右键", "中键"]
    static StorageTypes := ["Local", "Session"]

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

        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")
        this._Field(body, "备注：", "Remark", false)

        actions := body.Add("Grid")
        actions.Cols("*", 16, "*")
        category := CmdEditorForm.Row(actions, "类别：")
        operation := CmdEditorForm.Row(actions, "操作：", "", "CommandRightLabel").Grid_Column(2)
        groupNames := []
        for group in BrowserActions.Groups
            groupNames.Push(group.name)
        this._Choice(category, "ActionGroup", groupNames).Grid_Column(1)
        this._Choice(operation, "ActionType", BrowserActions.Groups[1].actions).Grid_Column(1)

        this._Choice(this._Row(body, "浏览器：", "BrowserRow"), "BrowserType", []).Grid_Column(1)
        this._Choice(this._Row(body, "浏览器：", "CloseBrowserRow"), "CloseBrowserType", BrowserActions.CloseBrowserTypes).Grid_Column(1)
        this._Field(body, "浏览器路径：", "BrowserPath", false, 26, "BrowserPathRow")
        this._Choice(this._Row(body, "页签范围：", "CloseScopeRow"), "CloseScope", BrowserActions.CloseScopes).Grid_Column(1)
        targetRefRow := this._Row(body, "目标分页：", "TargetRefRow", , GetLang("支持直接输入索引(1开始)、TargetID、标题/URL关键词，或选择变量 {变量名}"))
        CmdEditorForm.Combo(targetRefRow, "TargetRef", true).Grid_Column(1)
        urlRow := this._Row(body, "网址：", "UrlRow")
        this._TextBox(urlRow, "Url").Grid_Column(1).TextWrapping("NoWrap")
            .ScrollViewer_HorizontalScrollBarVisibility("Hidden")

        selector := this._Row(body, "网页元素：", "SelectorRow", ,
            GetLang("左侧选择类型，右侧填写选择器。")).Add("Grid").Grid_Column(1)
        selector.Cols("Auto", 6, "*", 6, "Auto")
        this._Choice(selector, "SelectorType", BrowserGui.SelectorTypes).Grid_Column(0)
        this._TextBox(selector, "Selector").Grid_Column(2).HorizontalScrollBarVisibility("Hidden")
        CmdEditorForm.TextButton(selector, "BtnPickSelector", "拾取", "拾取网页元素").Grid_Column(4)

        this._Choice(this._Row(body, "等待状态：", "ConditionRow"), "Condition", BrowserGui.Conditions).Grid_Column(1)
        this._Choice(this._Row(body, "加载状态：", "LoadStateRow"), "LoadState", BrowserGui.LoadStates).Grid_Column(1)
        textRow := this._Row(body, "", "TextRow", "TextLabel")
        textInputGrid := textRow.Add("Grid").Grid_Column(1)
        textInputGrid.Cols("*", "Auto")
        this._TextBox(textInputGrid, "Text").Grid_Column(0)
        CmdEditorForm.IconButton(textInputGrid, "BtnPickKey", 0xE92E, "打开按键选择器挑选键位")
            .Grid_Column(1).Margin("6,0,0,0")

        for option in [
            ["ClearBefore", "清空输入框"],
            ["Checked", "勾选(取消则不勾)"],
            ["FullPage", "全页完整截图"],
            ["IncludeTag", "包含元素标签"],
            ["Incognito", "独立会话(无痕模式)"]
        ] {
            row := this._Row(body, "选项设置：", option[1] "Row")
            row.Add("CheckBox").Name(option[1]).Grid_Column(1).Content(GetLang(option[2])).VerticalAlignment("Center")
                .Foreground("{DynamicResource TextMain}")
        }

        ; 坐标行 (X, Y)
        coordRow := this._Row(body, "坐标 (X, Y)：", "CoordRow", "CoordLabel")
        coordGrid := coordRow.Add("Grid").Grid_Column(1)
        coordGrid.Cols("*", 8, "*")
        this._TextBox(coordGrid, "CoordX").Grid_Column(0)
        this._TextBox(coordGrid, "CoordY").Grid_Column(2)

        ; 按键修饰键/鼠标按键行
        this._Choice(this._Row(body, "按键类型：", "MouseBtnRow"), "MouseBtn", BrowserGui.MouseButtons).Grid_Column(1)
        this._Choice(this._Row(body, "存储类型：", "StorageTypeRow"), "StorageType", BrowserGui.StorageTypes).Grid_Column(1)

        this._Field(body, "JS 脚本：", "JsCode", true, 78, "JsCodeRow")
        this._Field(body, "属性名称：", "AttrName", false, 26, "AttrNameRow")
        this._Field(body, "截图路径：", "SavePath", false, 26, "SavePathRow")

        saveRow := this._Row(body, "结果变量：", "SaveVarRow", , GetLang("留空时不保存结果"))
        CmdEditorForm.Combo(saveRow, "SaveVar", true).Grid_Column(1)
        CommandTimeoutFields.Add(body)
        CmdEditorForm.Footer(body)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
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
        this.ui.OnEvent("BtnPickKey", "Click", (*) => SetTimer(this._OpenKeyPicker.Bind(this), -1))

        BindCmdEditorChrome(this.ui, "#指令手册/浏览器")
    }

    _Row(body, label, rowName := "", labelName := "", labelTip := "") {
        return CmdEditorForm.Row(body, label, rowName, "CommandLabel", "Center", labelName, labelTip)
    }

    _Field(body, label, name, multiline, height := 26, rowName := "") {
        row := this._Row(body, label, rowName, name "Label")
        if (!multiline) {
            this._TextBox(row, name, height).Grid_Column(1)
            return
        }
        host := row.Add("Grid").Grid_Column(1)
        host.Cols("*", 6, "Auto")
        this._TextBox(host, name, height)
        CmdEditorForm.IconButton(host, "BtnEdit" name, 0xE70F, "编辑").Grid_Column(2).VerticalAlignment("Top")
    }

    _TextBox(parent, name, height := 26) => CmdEditorForm.TextBox(parent, name, height)

    _Choice(parent, name, values) {
        box := CmdEditorForm.Combo(parent, name).SelectedIndex(0)
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
        index := this.ui.Query("ActionGroup>SelectedIndex")
        if (!IsInteger(index) || index < 0 || index >= BrowserActions.Groups.Length)
            return
        actions := BrowserActions.Groups[index + 1].actions
        if (actions == this._activeActions)
            return
        this._activeActions := actions
        batch := [{ControlName: "ActionType", PropertyName: "ClearItems", Value: ""}]
        for action in actions
            batch.Push({ControlName: "ActionType", PropertyName: "AddItem", Value: GetLang(action)})
        batch.Push({ControlName: "ActionType", PropertyName: "SelectedIndex", Value: 0})
        this._updatingActions := true
        try this.ui.BatchUpdate(batch)
        finally this._updatingActions := false
        this.OnFieldsChanged()
    }

    OnActionTypeChanged(*) {
        if (!this._updatingActions)
            this.OnFieldsChanged()
    }

    _Action(ui) {
        index := ui.Query("ActionType>SelectedIndex")
        return IsInteger(index) && index >= 0 && index < this._activeActions.Length
            ? this._activeActions[index + 1] : this._activeActions[1]
    }

    OnFieldsChanged(*) {
        state := this.ui.Query("BrowserType", "CloseBrowserType")
        action := this._Action(this.ui)
        browser := action == "关闭"
            ? CmdEnumZh(state.Get("CloseBrowserType", ""), BrowserActions.CloseBrowserTypes)
            : CmdEnumZh(state.Get("BrowserType", ""), this._browserNames)
        this._UpdateFieldVisibilities(action, browser)
    }

    _UpdateFieldVisibilities(action, browser) {
        textLabels := Map(
            "输入", GetLang("输入内容："),
            "等待文字", GetLang("匹配文字："),
            "选择下拉", GetLang("选项值："),
            "按键输入", GetLang("按键名称："),
            "Cookie操作", GetLang("操作 (get/set/clear)："),
            "Storage操作", GetLang("操作 (get/set)：")
        )
        attrLabels := Map(
            "提取属性", GetLang("属性名称："),
            "Cookie操作", GetLang("Cookie名称："),
            "Storage操作", GetLang("键名 (Key)：")
        )
        isOpen := action == "打开网址"
        isClose := action == "关闭"
        isMouseCoord := action == "鼠标移动" || action == "鼠标点击" || action == "鼠标滚轮"
        hasSelector := BrowserActions.UsesSelector(action)
        rows := Map(
            "BrowserRow", isOpen, "CloseBrowserRow", isClose, "CloseScopeRow", isClose,
            "BrowserPathRow", (isOpen && browser == "自定义路径") || (isClose && browser == "自定义"),
            "UrlRow", isOpen || action == "当前页跳转" || action == "新建分页",
            "TargetRefRow", action == "切换分页" || action == "关闭分页" || BrowserActions.UsesTarget(action),
            "SelectorRow", hasSelector, "ConditionRow", action == "等待元素",
            "LoadStateRow", action == "等待加载", "TextRow", textLabels.Has(action),
            "ClearBeforeRow", action == "输入", "CheckedRow", action == "勾选",
            "FullPageRow", action == "网页截图", "IncludeTagRow", action == "提取HTML",
            "IncognitoRow", isOpen,
            "CoordRow", isMouseCoord,
            "MouseBtnRow", action == "鼠标点击",
            "StorageTypeRow", action == "Storage操作",
            "JsCodeRow", action == "执行JS" || action == "Cookie操作" || action == "Storage操作",
            "AttrNameRow", attrLabels.Has(action),
            "SavePathRow", action == "网页截图", "CommandTimeoutRow", BrowserActions.UsesTimeout(action),
            "SaveVarRow", !BrowserActions.IsCloseAction(action))
        for name, visible in rows
            this._ComboPush(name, "Visibility", visible ? "Visible" : "Collapsed")
        if (attrLabels.Has(action))
            this._ComboPush("AttrNameLabel", "Text", attrLabels[action])
        this._ComboPush("JsCodeLabel", "Text", action == "执行JS" ? GetLang("JS 脚本：") : GetLang("值："))
        if (textLabels.Has(action))
            this._ComboPush("TextLabel", "Text", textLabels[action])
        this._ComboPush("BtnPickKey", "Visibility", action == "按键输入" ? "Visible" : "Collapsed")
        if (isMouseCoord) {
            coordLabel := (action == "鼠标滚轮") ? GetLang("滚轮增量 (dX, dY)：") : GetLang("坐标 (X, Y)：")
            this._ComboPush("CoordLabel", "Text", coordLabel)
        }
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
            action := this._Action(ui)
            preferControl := action == "点击" || action == "输入" || action == "清空"
                || action == "选择下拉" || action == "勾选" || action == "提取控件值"
            BrowserUtil.StartElementPicker(this._pickerToken, selectorType, preferControl)
            this._pickTimer := this._PollPicker.Bind(this, ui, this._pickerToken, selectorType)
            SetTimer(this._pickTimer, 150)
            ui.Update("BtnPickSelector", "Content", GetLang("取消拾取"))
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

    _OpenKeyPicker(*) {
        if (!IsObject(this.ui))
            return
        picker := BrowserKeyPickerGui()
        text := this.ui.Query("Text")
        keyArr := []
        for k in StrSplit(text, ["⎖", ","]) {
            k := Trim(k)
            if (k != "")
                keyArr.Push(k)
        }
        picker.OwnerHwnd := this.Hwnd()
        id := this.ui.id
        picker.SureBtnAction := (keys) => (IsObject(this.ui) && this.ui.id == id && this._AcceptPickedKeys(keys))
        this._keyPicker := picker
        picker.ShowGui(keyArr)
    }

    _AcceptPickedKeys(keyArr) {
        if (!IsObject(this.ui))
            return
        keys := ""
        for key in keyArr
            keys .= (keys == "" ? "" : "⎖") key
        this.ui.Update("Text", "Text", keys)
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

        timeoutAction := TimeoutPolicy.Get(this.Data)
        defaults := BrowserData()
        for name, value in defaults.OwnProps()
            if (!this.Data.HasOwnProp(name) && name != "TimeoutAction" && name != "TimeoutStatusVar")
                this.Data.%name% := value
        actionType := CmdEnumZh(this.Data.ActionType, BrowserActions.Names)
        if (actionType == "关闭标签")
            actionType := "关闭分页"

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
        closeBrowserType := BrowserActions.GetCloseBrowserType(browserType)
        if (browserType == "自定义")
            browserType := "自定义路径"
        if (parts.Length && browserType != "" && browserType != "自定义路径" && browserType != "所有浏览器" && !seen.Has(browserType))
            this._browserNames.Push(browserType)
        this._browserNames.Push("自定义路径")
        for name in this._browserNames
            this._ComboPush("BrowserType", "AddItem", GetLang(name))

        for varName in GetGuiVarArr() {
            if (varName != "") {
                this._ComboPush("SaveVar", "AddItem", varName)
                this._ComboPush("TargetRef", "AddItem", "{" varName "}")
            }
        }
        for name in ["Url", "TargetRef", "Selector", "JsCode", "AttrName", "BrowserPath", "CoordX", "CoordY"]
            this._ComboPush(name, "Text", String(this.Data.%name%))
        this._ComboPush("SaveVar", "Text", GetLang(this.Data.SaveVar))
        this._ComboPush(actionType == "网页截图" ? "SavePath" : "Text", "Text", String(this.Data.Text))
        this._ComboPush("ClearBefore", "IsChecked", this.Data.ClearBefore ? "True" : "False")
        this._ComboPush("Checked", "IsChecked", this.Data.Checked ? "True" : "False")
        this._ComboPush("Incognito", "IsChecked", (this.Data.HasOwnProp("Incognito") && this.Data.Incognito) ? "True" : "False")
        this._ComboPush("FullPage", "IsChecked", actionType == "网页截图" && this.Data.OuterHtml ? "True" : "False")
        this._ComboPush("IncludeTag", "IsChecked", actionType != "提取HTML" || this.Data.OuterHtml ? "True" : "False")

        for groupIndex, group in BrowserActions.Groups {
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
            "LoadState", BrowserGui.LoadStates, "BrowserType", this._browserNames, "MouseBtn", BrowserGui.MouseButtons, "StorageType", BrowserGui.StorageTypes)
            this._ComboPush(name, "SelectedIndex", CmdEnumIndex((name == "BrowserType" ? browserType : this.Data.%name%), values))
        if (timeoutAction == "") {
            onError := GetLangKey(this.Data.OnError)
            timeoutAction := onError
            if (onError == "重试") {
                retries := IsInteger(this.Data.RetryCount) ? Max(0, Integer(this.Data.RetryCount) - 1) : ""
                timeoutAction := TimeoutPolicy.LegacyRetryAction(retries)
            }
        }
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs, timeoutAction,
            InputField(this.Data, "TimeoutStatusVar", TimeoutPolicy.DefaultStatusVar))
        this._ComboPush("CloseBrowserType", "SelectedIndex", CmdEnumIndex(closeBrowserType, BrowserActions.CloseBrowserTypes))
        this._ComboPush("CloseScope", "SelectedIndex", CmdEnumIndex(this.Data.CloseScope, BrowserActions.CloseScopes))
        this._UpdateFieldVisibilities(actionType, actionType == "关闭"
            ? CmdEnumZh(closeBrowserType, BrowserActions.CloseBrowserTypes) : CmdEnumZh(browserType, this._browserNames))
    }

    _ReadData() {
        data := this.Data.Clone()
        state := this.ui.Query("BrowserType", "CloseBrowserType", "CloseScope", "BrowserPath", "TargetRef", "Url",
            "SelectorType", "Selector", "Condition", "LoadState", "Text", "SavePath", "ClearBefore",
            "Checked", "FullPage", "IncludeTag", "Incognito", "JsCode", "AttrName", "SaveVar",
            "CoordX", "CoordY", "MouseBtn", "StorageType")
        data.ActionType := this._Action(this.ui)
        if (data.ActionType == "关闭") {
            data.BrowserType := CmdEnumZh(state["CloseBrowserType"], BrowserActions.CloseBrowserTypes)
            data.CloseScope := CmdEnumZh(state["CloseScope"], BrowserActions.CloseScopes)
            data.BrowserPath := data.BrowserType == "自定义" ? state["BrowserPath"] : ""
            data.OnError := "忽略"
            data.SaveVar := ""
            return data
        }
        for name, values in Map("SelectorType", BrowserGui.SelectorTypes, "Condition", BrowserGui.Conditions,
            "LoadState", BrowserGui.LoadStates, "BrowserType", this._browserNames, "MouseBtn", BrowserGui.MouseButtons, "StorageType", BrowserGui.StorageTypes)
            data.%name% := CmdEnumZh(state[name], values)
        if (BrowserActions.UsesTimeout(data.ActionType))
            CommandTimeoutFields.Read(this.ui, data)
        for name in ["Url", "TargetRef", "Selector", "JsCode", "AttrName", "BrowserPath", "CoordX", "CoordY"]
            data.%name% := state[name]
        data.Text := state[data.ActionType == "网页截图" ? "SavePath" : "Text"]
        data.ClearBefore := state["ClearBefore"] == "True"
        data.Checked := state["Checked"] == "True"
        data.Incognito := state["Incognito"] == "True"
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
        } else if (BrowserActions.UsesTimeout(data.ActionType)
            && !TimeoutPolicy.ValidMs(data.TimeoutMs, 2147483647))
            message := GetLang("超时必须是正整数。")
        else if ((data.ActionType == "打开网址" || data.ActionType == "当前页跳转") && Trim(data.Url) == "")
            message := GetLang("网址不能为空。")
        else if (data.ActionType == "打开网址" && data.BrowserType == "自定义路径" && Trim(data.BrowserPath) == "")
            message := GetLang("浏览器路径不能为空。")
        else if (BrowserActions.UsesSelector(data.ActionType) && data.ActionType != "等待文字" && data.ActionType != "提取文本"
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
        if (data.SaveVar != "" && !CheckVarNameIfValid(data.SaveVar))
            return false
        if (!BrowserActions.UsesTimeout(data.ActionType))
            return true
        results := []
        if (data.SaveVar != "")
            for suffix in ["", "_Success", "_Error", "_ElapsedMs"]
                results.Push(data.SaveVar suffix)
        return CommandTimeoutFields.ValidateStatus(data, results*)
    }

    SaveData() {
        this.Data := this._ReadData()
        if (BrowserActions.UsesTimeout(this.Data.ActionType))
            TimeoutPolicy.RegisterStatus(this.Data)
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
