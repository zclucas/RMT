#Requires AutoHotkey v2.0
#Include BrowserKeyPickerGui.ahk
#Include ..\Main\Util\BrowserPageInfo.ahk

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
    _playHotkeys := []
    _pickHotkeys := []
    _testRunning := false
    WindowBindingContext := ""

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("浏览器")
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(CmdEditorForm.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height, "BtnClosePanel", "", "", "", Chr(0xE707))

        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")
        this._Field(body, "备注：", "Remark", false)

        actions := body.Add("Grid")
        actions.Cols("*", 16, "*")
        category := this._Row(actions, "类别：")
        operation := this._Row(actions, "操作：").Grid_Column(2)
        groupNames := []
        for group in BrowserActions.Groups
            groupNames.Push(group.name)
        this._Choice(category, "ActionGroup", groupNames).Grid_Column(1)
        this._Choice(operation, "ActionType", BrowserActions.Groups[1].actions).Grid_Column(1)

        browserGrid := body.Add("Grid").Cols("*", 16, "*")
        this._Choice(this._Row(browserGrid, "浏览器：", "BrowserRow", , GetLang("未勾选 CDP 时复用普通浏览器；勾选后打开可供浏览器指令操作的 CDP 窗口。")), "BrowserType", []).Grid_Column(1)
        openModeRow := this._Row(browserGrid, "选项设置：", "OpenModeRow", , GetLang("默认复用对应窗口；新窗口始终另开窗口；无痕模式复用对应无痕窗口。")).Grid_Column(2)
        this._Choice(openModeRow, "OpenMode", BrowserActions.OpenModes).Grid_Column(1)
        pageSourceGrid := body.Add("Grid").Name("PageSourceRow").Cols("*", 16, "*")
        this._Choice(this._Row(pageSourceGrid, "匹配方式：", , , GetLang("网址和标题精确匹配；元素匹配按CSS或XPath检查元素是否存在，需要CDP。查找时短暂切换标签页，结束后恢复。")), "PageSource", BrowserPageInfo.Sources).Grid_Column(1)
        currentRow := body.Add("Grid").Name("CurrentTabActionRow").Cols("*", 16, "*")
        tabAction := this._Choice(this._Row(currentRow, "标签操作：", , , GetLang("刷新、后退、前进与关闭无需 CDP；清空缓存需要 CDP，清理后刷新当前标签页。")), "CurrentTabAction", BrowserActions.CurrentTabActions).Grid_Column(1)
        this._CurrentTabActionStyle(tabAction)
        matchGrid := body.Add("Grid").Name("TabMatchOptions").Cols("*", 16, "*")
        this._Choice(this._Row(matchGrid, "匹配方式："), "TabMatchMode", BrowserActions.TabMatchModes).Grid_Column(1)
        matchValueRow := this._Row(matchGrid, "匹配值：", "TabMatchValueRow", , GetLang("ID、网址与标题精确匹配，支持正则表达式和变量 {变量名}。" )).Grid_Column(2)
        CmdEditorForm.Combo(matchValueRow, "TabMatchValue", true).Grid_Column(1)
        targetRefRow := this._Row(body, "目标标签页：", "TargetRefRow", , GetLang("支持直接输入索引(1开始)、TargetID、标题/URL关键词，或选择变量 {变量名}"))
        CmdEditorForm.Combo(targetRefRow, "TargetRef", true).Grid_Column(1)
        selector := this._Row(body, "网页元素：", "SelectorRow", ,
            GetLang("左侧选择CSS或XPath，右侧填写选择器。元素匹配查找当前CDP连接中包含该元素的标签页。")).Add("Grid").Grid_Column(1)
        selector.Cols("Auto", 6, "*", 6, "Auto", 6, "Auto")
        this._Choice(selector, "SelectorType", BrowserGui.SelectorTypes).Grid_Column(0).Width(77)
        CmdEditorForm.Combo(selector, "Selector", true).Grid_Column(2)
        CmdEditorForm.IconButton(selector, "BtnPickSelector", 0xE707, "F1：拾取网页元素").Grid_Column(4)
        CmdEditorForm.IconButton(selector, "BtnSelectorDetails", 0xE946, "选择器详情").Grid_Column(6)
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
            .InjectResources(FrontInfoGui._ToolBtnHoverStyle())
        closeOptions := body.Add("Grid").Name("TabCloseModeRow").Cols("*", 16, "*")
        this._Choice(this._Row(closeOptions, "关闭方式："), "TabCloseMode", BrowserActions.TabCloseModes).Grid_Column(1)
        this._Field(body, "浏览器路径：", "BrowserPath", false, 26, "BrowserPathRow")
        urlRow := this._Row(body, "网址：", "UrlRow", "UrlLabel")
        urlInput := urlRow.Add("Grid").Grid_Column(1).Cols("*", 6, "Auto")
        CmdEditorForm.Combo(urlInput, "Url", true)
        CmdEditorForm.IconButton(urlInput, "BtnEditUrl", 0xE70F, "文本构造").Grid_Column(2)
        cdpRow := this._Row(body, "调试连接：", "CdpOptionRow", "CdpOptionLabel",
            GetLang("开发者工具协议（CDP）：勾选后，浏览器指令才可以选取操作网页控件、执行脚本等"))
        cdpRow.Add("CheckBox").Name("UseCDP").Grid_Column(1).Content(GetLang("CDP（浏览器开发者工具协议）")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")

        outputsGrid := body.Add("Grid").Name("PageOutputs").Cols("*", 16, "*").Rows("Auto", "Auto")
        for index, field in BrowserPageInfo.Fields {
            name := BrowserPageInfo.Outputs[field]
            label := field
            tip := field == "加载状态" ? "返回不可访问、加载中、可交互、加载完成；需要 CDP，留空不获取。"
                : field == "标签页ID" ? "填写变量以保存标签页ID；需要 CDP，留空不获取。" : "填写变量以保存信息，留空不获取。"
            outputRow := this._Row(outputsGrid, label "：", name "Row", , GetLang(tip))
                .Grid_Row((index - 1) // 2).Grid_Column(Mod(index - 1, 2) * 2)
            CmdEditorForm.Combo(outputRow, name, true).Grid_Column(1)
            if (field != "标签页ID")
                CmdEditorForm.OutputVariablePlaceholder(outputRow, name,
                    field == "网址" ? "Url" : field == "标题" ? "Title" : "State", 1)
        }

        for action in ["元素信息", "元素位置/宽高"] {
            elementOutputs := body.Add("Grid").Name(action == "元素信息" ? "ElementInfoOutputs" : "ElementPositionOutputs").Cols("*", 16, "*")
            fields := BrowserElementInfo.Outputs(action), index := 0, rows := []
            loop (fields.Count + 1) // 2
                rows.Push("Auto")
            elementOutputs.Rows(rows*)
            labels := action == "元素信息" ? ["存在变量", "元素值变量", "元素变量", "标签页ID", "元素状态", "HTML变量"] : ["视口X变量", "视口Y变量", "页面X变量", "页面Y变量", "宽度变量", "高度变量"]
            for label in labels {
                name := fields[label]
                tip := name == "ElementExistsVar" ? "1存在，0不存在；检测时不等待元素出现。"
                    : name == "ElementValueVar" ? "表单读取当前值，勾选框返回0/1，其他元素读取文本。"
                    : name == "ElementRefVar" ? "保存元素选择器，后续网页元素可填写 {变量名}，保持相同CSS或XPath类型；不存在时清空。"
                    : name == "ElementTabIdVar" ? "保存匹配元素所在标签页ID；未找到时清空，留空不获取。"
                    : name == "ElementHtmlVar" ? "保存完整元素HTML，包含标签与属性；留空不获取。"
                    : name == "ElementStateVar" ? "返回交互-可见状态，如可交互-可见；未找到为不可见。"
                    : InStr(name, "Page") ? "元素中心点相对整张网页左上角的坐标，单位为CSS像素。"
                    : (name == "ElementXVar" || name == "ElementYVar") ? "元素中心点相对网页可视区域左上角的坐标，单位为CSS像素。"
                    : "元素边界框尺寸，包含内边距与边框，单位为CSS像素。"
                row := this._Row(elementOutputs, label "：", , , GetLang(tip)).Grid_Row(index // 2).Grid_Column(Mod(index, 2) * 2)
                CmdEditorForm.Combo(row, name, true).Grid_Column(1)
                if (name == "ElementTabIdVar" || name == "ElementStateVar" || name == "ElementHtmlVar")
                    CmdEditorForm.OutputVariablePlaceholder(row, name, name == "ElementTabIdVar" ? "TabId" : name == "ElementHtmlVar" ? "ElHtml" : "ElState", 1)
                index++
            }
        }

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
            ["FullPage", "全页完整截图"]
        ] {
            row := this._Row(body, "选项设置：", option[1] "Row")
            row.Add("CheckBox").Name(option[1]).Grid_Column(1).Content(GetLang(option[2])).VerticalAlignment("Center")
                .Foreground("{DynamicResource TextMain}")
        }

        ; 坐标行 (X, Y)
        coordRow := this._Row(body, "坐标：", "CoordRow", "CoordLabel", GetLang("从左到右填写 X、Y。"))
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
        CommandTimeoutFields.Add(body, false, , , CmdEditorForm.LabelWidth())
        notice := body.Add("StackPanel").Name("CdpNotice").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,6,0,0").Visibility("Collapsed")
        notice.Add("TextBlock").Text(GetLang("该指令需要 ")).Foreground("#D32F2F").VerticalAlignment("Center")
        link := notice.Add("Button").Name("BtnCdpHelp").Padding(0).MinWidth(0).MinHeight(0)
            .BorderThickness(0).Background("Transparent").Foreground("#D32F2F").Cursor("Hand").ToolTip(GetLang("查看 CDP 说明"))
        link.Add("Button.Template").Add("ControlTemplate").TargetType("Button").Add("ContentPresenter")
        link.Add("TextBlock").Text("CDP").TextDecorations("Underline").Foreground("#D32F2F").VerticalAlignment("Center")
        notice.Add("TextBlock").Text(GetLang(" 支持")).Foreground("#D32F2F").VerticalAlignment("Center")
        CmdEditorForm.Footer(body)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="' CmdEditorForm.Width '" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnEditJsCode", "Click", ObjBindMethod(this, "_QueueTextEditor", "JsCode"))
        this.ui.OnEvent("BtnEditUrl", "Click", ObjBindMethod(this, "_QueueTextEditor", "Url"))
        this.ui.OnEvent("ActionGroup", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionGroupChanged"))
        this.ui.OnEvent("ActionType", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionTypeChanged"))
        for name in ["BrowserType", "PageSource", "PageIdVar", "PageStateVar", "CurrentTabAction", "TabMatchMode", "TabCloseMode"]
            this.ui.OnEvent(name, "SelectionChanged", XamlWin.BindCurrent(this, "OnFieldsChanged"))
        for name in ["PageIdVar", "PageStateVar"]
            this.ui.OnEvent(name, "TextChanged", XamlWin.BindCurrent(this, "OnFieldsChanged"))
        this.ui.OnEvent("BtnCdpHelp", "Click", XamlWin.BindCurrent(this, "ShowCDPHelp"))
        this.ui.OnEvent("BtnPickSelector", "Click", XamlWin.BindCurrent(this, "OnPickSelector"))
        this.ui.OnEvent("BtnSelectorDetails", "Click", XamlWin.BindCurrent(this, "OnSelectorDetails"))
        this.ui.OnEvent("BtnCmdF1", "Click", XamlWin.BindCurrent(this, "OnPickSelector"))
        this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：拾取网页元素"))
        this.ui.OnEvent("BtnPickKey", "Click", (*) => SetTimer(this._OpenKeyPicker.Bind(this), -1))

        BindCmdEditorChrome(this.ui, "#指令手册/浏览器", XamlWin.BindCurrent(this, "TriggerMacro"), "!l")
    }

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        if (!this._playHotkeys.Length)
            this._playHotkeys := WinHotkey.Register(["!l"], XamlWin.BindCurrent(this, "TriggerMacro"), this.Hwnd())
        if (!this._pickHotkeys.Length)
            this._pickHotkeys := WinHotkey.Register(["F1"], XamlWin.BindCurrent(this, "OnPickSelector"), this.Hwnd())
    }

    TriggerMacro(*) {
        if (this._testRunning || !this.CheckIfValid())
            return
        this._testRunning := true
        try {
            this.SaveData()
            RunEditorMacroPreview(this.GetCommandStr(), false, this.WindowBindingContext)
        } finally {
            this._testRunning := false
        }
    }

    _UnregisterPlayHotkeys() {
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        WinHotkey.UnregisterAll(this._pickHotkeys)
        this._pickHotkeys := []
    }

    _FillTabMatchModes(action, selected := "") {
        if (selected == "")
            selected := this.ui.Query("TabMatchMode")
        modes := BrowserActions.MatchModes(action)
        this._tabMatchAction := action
        this._updatingMatchModes := true
        try {
            this._ComboPush("TabMatchMode", "ClearItems", "")
            for mode in modes
                this._ComboPush("TabMatchMode", "AddItem", GetLang(mode))
            this._ComboPush("TabMatchMode", "SelectedIndex", BrowserActions.ChoiceIndex(selected, modes))
        } finally this._updatingMatchModes := false
    }

    _CurrentTabActionStyle(combo) {
        template := '<DataTemplate><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            . '<TextBlock Text="{Binding}" VerticalAlignment="Center"/>'
            . '<TextBlock x:Name="TabActionGlyph" Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource TextSub}"/>'
            . '</Grid><DataTemplate.Triggers>'
        icons := ["E72C", "E72B", "E72A", "E711", "E74D"]
        for index, action in BrowserActions.CurrentTabActions
            template .= '<DataTrigger Binding="{Binding}" Value="' EscapeXamlXml(GetLang(action)) '"><Setter TargetName="TabActionGlyph" Property="Text" Value="&#x' icons[index] ';"/></DataTrigger>'
        template .= '</DataTemplate.Triggers></DataTemplate>'
        combo.InjectResources('<Style x:Key="BrowserTabActionItem" TargetType="ComboBoxItem" BasedOn="{StaticResource {x:Type ComboBoxItem}}"><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="ContentTemplate"><Setter.Value>' template '</Setter.Value></Setter></Style>')
        combo.SetProp("ItemContainerStyle", "{DynamicResource BrowserTabActionItem}")
    }

    _Row(body, label, rowName := "", labelName := "", labelTip := "") {
        row := body.Add("Grid").Margin("0,4").Cols(CmdEditorForm.LabelWidth(), "*")
        if (rowName != "")
            row.Name(rowName)
        caption := CmdEditorForm.Label(row, label).Margin("0")
        if (labelName != "")
            caption.Name(labelName)
        if (labelTip != "")
            caption.ToolTip(labelTip)
        return row
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
            batch.Push({ControlName: "ActionType", PropertyName: "AddItem", Value: this._ActionLabel(action)})
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

    _ActionLabel(action) => GetLang(action == "元素信息" ? "基础信息" : action == "元素位置/宽高" ? "位置/宽高" : action)

    OnFieldsChanged(*) {
        if (this.HasOwnProp("_updatingMatchModes") && this._updatingMatchModes)
            return
        action := this._Action(this.ui)
        browser := BrowserActions._Choice(this.ui.Query("BrowserType"), this._browserNames)
        this._UpdateFieldVisibilities(action, browser)
    }

    _UpdateFieldVisibilities(action, browser, pageSource := "", pageField := "") {
        action := BrowserActions.Action(action)
        textLabels := Map(
            "输入", GetLang("输入内容："),
            "等待文字", GetLang("匹配文字："),
            "选择下拉", GetLang("选项值："),
            "按键输入", GetLang("按键名称："),
            "Cookie操作", GetLang("操作："),
            "Storage操作", GetLang("操作：")
        )
        attrLabels := Map(
            "Cookie操作", GetLang("Cookie名称："),
            "Storage操作", GetLang("键名：")
        )
        isOpen := action == "打开网址"
        isTab := BrowserActions.IsTabAction(action)
        isInfo := action == "标签页信息"
        isMatching := action == "切换标签页" || action == "关闭标签页"
        if (isMatching && (!this.HasOwnProp("_tabMatchAction") || this._tabMatchAction != action))
            this._FillTabMatchModes(action)
        matchMode := isMatching ? BrowserActions._Choice(this.ui.Query("TabMatchMode"), BrowserActions.MatchModes(action)) : ""
        source := isInfo ? (pageSource != "" ? pageSource : BrowserActions._Choice(this.ui.Query("PageSource"), BrowserPageInfo.Sources)) : ""
        isMouseCoord := action == "鼠标移动" || action == "鼠标点击" || action == "鼠标滚轮"
        elementMatch := (isInfo && source == "元素匹配") || (isMatching && matchMode == "元素匹配")
        hasSelector := BrowserActions.UsesSelector(action) || elementMatch
        rows := Map(
            "BrowserRow", isOpen,
            "BrowserPathRow", isOpen && browser == "自定义路径",
            "CdpOptionRow", isOpen, "PageSourceRow", isInfo, "PageOutputs", isInfo,
            "CurrentTabActionRow", action == "当前标签页", "TabMatchOptions", isMatching,
            "ElementInfoOutputs", action == "元素信息", "ElementPositionOutputs", action == "元素位置/宽高",
            "TabMatchValueRow", isMatching && matchMode != "当前标签页" && !elementMatch, "TabCloseModeRow", action == "关闭标签页",
            "UrlRow", isOpen || (isInfo && BrowserPageInfo.UsesMatchValue(source)),
            "TargetRefRow", BrowserActions.UsesTarget(action),
            "SelectorRow", hasSelector, "ConditionRow", action == "等待元素",
            "LoadStateRow", action == "等待加载", "TextRow", textLabels.Has(action),
            "ClearBeforeRow", action == "输入", "CheckedRow", action == "勾选",
            "FullPageRow", action == "网页截图",
            "OpenModeRow", isOpen,
            "CoordRow", isMouseCoord,
            "MouseBtnRow", action == "鼠标点击",
            "StorageTypeRow", action == "Storage操作",
            "JsCodeRow", action == "执行JS" || action == "Cookie操作" || action == "Storage操作",
            "AttrNameRow", attrLabels.Has(action),
            "SavePathRow", action == "网页截图", "CommandTimeoutRow", !isTab && BrowserActions.UsesTimeout(action),
            "SaveVarRow", !isTab && !BrowserElementInfo.IsRead(action))
        for field, name in BrowserPageInfo.Outputs
            rows[name "Row"] := isInfo
        for name, visible in rows
            this._ComboPush(name, "Visibility", visible ? "Visible" : "Collapsed")
        this._ComboPush("BtnCmdF1", "Visibility", hasSelector ? "Visible" : "Collapsed")
        if (!hasSelector && this._picking)
            this._FinishPicker()
        field := isInfo ? (pageField != "" ? pageField
            : (this.ui.Query("PageIdVar") != "" || this.ui.Query("PageStateVar") != "") ? "标签页ID" : "") : (action == "当前标签页" ? BrowserActions._Choice(this.ui.Query("CurrentTabAction"), BrowserActions.CurrentTabActions) : "")
        closeMode := BrowserActions._Choice(this.ui.Query("TabCloseMode"), BrowserActions.TabCloseModes)
        this._ComboPush("CdpNotice", "Visibility", BrowserActions.RequiresCDP(action, field, isInfo ? source : matchMode, closeMode) ? "Visible" : "Collapsed")
        this._ComboPush("UrlLabel", "Text", GetLang(isInfo && BrowserPageInfo.MatchesTitle(source) ? "标题：" : "网址："))
        if (attrLabels.Has(action))
            this._ComboPush("AttrNameLabel", "Text", attrLabels[action])
        this._ComboPush("JsCodeLabel", "Text", action == "执行JS" ? GetLang("JS 脚本：") : GetLang("值："))
        if (textLabels.Has(action))
            this._ComboPush("TextLabel", "Text", textLabels[action])
        this._ComboPush("TextLabel", "ToolTip", action == "Cookie操作" ? GetLang("支持 get、set、clear。")
            : action == "Storage操作" ? GetLang("支持 get、set。") : "")
        this._ComboPush("BtnPickKey", "Visibility", action == "按键输入" ? "Visible" : "Collapsed")
        if (isMouseCoord) {
            coordLabel := (action == "鼠标滚轮") ? GetLang("滚轮增量：") : GetLang("坐标：")
            this._ComboPush("CoordLabel", "Text", coordLabel)
            this._ComboPush("CoordLabel", "ToolTip", GetLang(action == "鼠标滚轮" ? "从左到右填写 dX、dY。" : "从左到右填写 X、Y。"))
        }
    }

    OnSelectorDetails(*) {
        selector := this.ui.Query("Selector")
        if (RegExMatch(Trim(selector), "^\{([^{}\r\n]+)\}$", &reference)) {
            if (!TryGetVarValue(&value, reference[1], false, Map(), false)) {
                RmtDialog.Info(GetLang("元素变量尚未赋值：") reference[1], GetLang("选择器详情"), this.Hwnd())
                return
            }
            selector := String(value)
        }
        RmtDialog.Info(Trim(selector) != "" ? selector : GetLang("未拾取元素"), GetLang("选择器详情"), this.Hwnd())
    }

    OnPickSelector(*) {
        if (IsObject(this.ui) && (this._picking || this.ui.Query("SelectorRow>Visibility") == "Visible"))
            SetTimer(this._PickSelector.Bind(this, this.ui), -1)
    }

    _HasPickerBrowser() {
        for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1")
            if (BrowserPageInfo.IsBrowser(hwnd) && IsObject(BrowserUtil.ManagedSessionForWindow(hwnd)))
                return true
        return false
    }

    _PickerSourceWindow() {
        ; 按窗口前后顺序选择最近使用的浏览器，读取其当前标签页。
        for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1")
            if (BrowserPageInfo.IsBrowser(hwnd) && DllCall("IsWindowVisible", "Ptr", hwnd))
                return hwnd
        return 0
    }

    _EnsurePickerBrowser() {
        if (this._HasPickerBrowser())
            return true
        sourceWindow := this._PickerSourceWindow()
        prompt := sourceWindow ? "只能拾取CDP窗口元素`n当前标签页用打开受控浏览器窗口"
            : "只能拾取CDP窗口元素，打开受控浏览器窗口"
        if (!RmtDialog.Confirm(GetLang(prompt), GetLang("拾取网页元素"), this.Hwnd()))
            return false
        url := sourceWindow ? BrowserPageInfo.ReadWindow(sourceWindow).url : "about:blank"
        BrowserUtil.OpenUrl(url, "默认浏览器", "", false, 0, "", 9222, 10000, true, true)
        return true
    }

    _PickSelector(ui) {
        if (this.ui != ui || (!this._picking && ui.Query("SelectorRow>Visibility") != "Visible"))
            return
        if (this._picking) {
            this._FinishPicker()
            return
        }
        if (MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        this._picking := true
        try {
            if (!this._EnsurePickerBrowser() || this.ui != ui || !this._picking)
                return
            this._pickerSelectorType := BrowserActions._Choice(ui.Query("SelectorType"), BrowserGui.SelectorTypes)
            this._pickerKeys := WinHotkey.Register(["Enter", "Escape"], this._PickerKey.Bind(this, ui))
            if (this._pickerKeys.Length != 2)
                throw Error(GetLang("无法注册拾取确认热键。"))
            this._pickerWindow := 0
            this._pickerTab := ""
            this._pickerLastProbe := 0
            WinHide("ahk_id " this.Hwnd())
            this._pickerHidden := true
            SetSystemCursor("CROSS")
            CursorOutputTip.Show("", 0x7FFFFFFF, false, false, true, "移动鼠标拾取元素")
            this._pickTimer := this._PollPicker.Bind(this, ui)
            SetTimer(this._pickTimer, 100)
            ui.Update("BtnPickSelector", "Content", Chr(0xE711))
            ui.Update("BtnPickSelector", "ToolTip", GetLang("F1：取消拾取"))
            ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：取消拾取"))
        } catch as e {
            this._FinishPicker()
            if (this.ui == ui)
                RmtDialog.Info(GetLang(e.Message), GetLang("拾取网页元素"), this.Hwnd())
        } finally {
            if (!this.HasOwnProp("_pickTimer") && this._picking)
                this._FinishPicker()
        }
    }

    _PickerKey(ui, key, *) {
        Critical("On")
        if (!this._picking || this.ui != ui)
            return
        if (key == "Escape") {
            this._FinishPicker()
            return
        }
        failure := ""
        try {
            if (!this._UpdatePickerTarget(true))
                throw Error(GetLang("非CDP窗口无法拾取元素"))
            result := BrowserUtil.Evaluate("window." this._pickerToken "?.confirm() ?? ''")
            if (SubStr(result, 1, 7) != "picked:")
                throw Error(GetLang("请将鼠标移到可拾取的网页元素上。"))
            ui.Update("SelectorType", "SelectedIndex", BrowserActions.ChoiceIndex(this._pickerSelectorType, BrowserGui.SelectorTypes))
            ui.Update("Selector", "Text", SubStr(result, 8))
        } catch as e {
            failure := e.Message
        } finally {
            this._FinishPicker()
        }
        Critical("Off")
        if (failure != "" && this.ui == ui)
            RmtDialog.Info(failure, GetLang("拾取网页元素"), this.Hwnd())
    }

    _PickerMouseWindow() {
        CoordMode("Mouse", "Screen")
        MouseGetPos(, , &hwnd)
        return hwnd ? DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") : 0
    }

    _UpdatePickerTarget(force := false) {
        hwnd := this._PickerMouseWindow()
        session := hwnd && BrowserPageInfo.IsBrowser(hwnd) ? BrowserUtil.ManagedSessionForWindow(hwnd) : ""
        if (!IsObject(session)) {
            this._StopPickerPage()
            this._pickerWindow := 0
            return false
        }
        if (!force && hwnd == this._pickerWindow && A_TickCount - this._pickerLastProbe < 400)
            return true
        if (hwnd != this._pickerWindow)
            this._StopPickerPage()
        info := BrowserPageInfo.Snapshot(hwnd)
        tab := BrowserPageInfo.TargetId(info, session["port"])
        this._pickerLastProbe := A_TickCount
        if (hwnd == this._pickerWindow && tab == this._pickerTab && this.HasOwnProp("_pickerToken"))
            return true
        this._StopPickerPage()
        BrowserUtil.SwitchTab(tab)
        this._pickerWindow := hwnd
        this._pickerTab := tab
        this._pickerToken := "__rmtPick_" DllCall("GetCurrentProcessId", "UInt") "_" A_TickCount
        action := this._Action(this.ui)
        preferControl := action == "点击" || action == "输入" || action == "清空"
            || action == "选择下拉" || action == "勾选"
        BrowserUtil.StartElementPicker(this._pickerToken, this._pickerSelectorType, preferControl)
        return true
    }

    _StopPickerPage() {
        if (this.HasOwnProp("_pickerToken")) {
            try BrowserUtil.Evaluate("window." this._pickerToken "?.stop()")
            this.DeleteProp("_pickerToken")
        }
    }

    ShowCDPHelp(*) {
        text := GetLang("CDP（Chrome DevTools Protocol）是 Chrome、Edge 提供的浏览器调试协议，RMT 通过它读取标签页ID、定位网页元素、执行 JavaScript 等。")
            . "`n`n" GetLang("该指令仅对通过「浏览器指令 → 网页 → 打开网址」勾选「CDP」后打开的窗口网页有效。")
            . "`n`n" GetLang("未勾选 CDP 时按普通浏览器方式打开，不能用于需要 CDP 的操作。")
        RmtDialog.Info(text, GetLang("CDP 说明"), this.Hwnd())
    }

    _PollPicker(ui) {
        Critical("On")
        if (this.ui != ui || !this._picking)
            return
        try {
            if (!this._UpdatePickerTarget())
                return
            state := BrowserUtil.Evaluate("window." this._pickerToken "?.result ?? 'missing'")
            if (state == "missing") {
                this._StopPickerPage()
                this._pickerWindow := 0
            } else if (state != "pending")
                this._FinishPicker()
        } catch {
            ; 浏览器切页、加载时重新注入，保留全局确认和取消热键。
            this._StopPickerPage()
            this._pickerWindow := 0
        }
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
        if (this.HasOwnProp("_pickerKeys")) {
            WinHotkey.UnregisterAll(this._pickerKeys)
            this.DeleteProp("_pickerKeys")
        }
        this._StopPickerPage()
        if (this.HasOwnProp("_pickerHidden") && this._pickerHidden) {
            this._pickerHidden := false
            CursorOutputTip.Show("")
            SetSystemCursor()
            if (IsObject(this.ui)) {
                wasDetectingHidden := A_DetectHiddenWindows
                DetectHiddenWindows(true)
                try WinShow("ahk_id " this.Hwnd())
                finally DetectHiddenWindows(wasDetectingHidden)
                try WinActivate("ahk_id " this.Hwnd())
            }
        }
        this._picking := false
        if (IsObject(this.ui)) {
            this.ui.Update("BtnPickSelector", "Content", Chr(0xE707))
            this.ui.Update("BtnPickSelector", "ToolTip", GetLang("F1：拾取网页元素"))
            this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：拾取网页元素"))
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this._UnregisterPlayHotkeys()
        if (this._picking)
            this._FinishPicker()
        super.OnWindowClosing(state, ctrl, event)
    }

    _CloseWindow() {
        this._UnregisterPlayHotkeys()
        if (this._picking)
            this._FinishPicker()
        super._CloseWindow()
    }

    Init(cmd) {
        parts := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := parts.Length ? parts[1] : AllocateCommandSerial("浏览器")
        this.Data := GetMacroCMDData(this.SerialStr).Clone()
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")

        actionType := BrowserActions.Action(this.Data.ActionType)
        this._browserNames := BrowserActions.BrowserTypes.Clone()
        this._browserNames.Pop() ; 自定义路径保留在列表末尾。
        seen := Map()
        for name in this._browserNames
            seen[name] := true
        for browser in BrowserUtil.GetInstalledBrowsers() {
            if (!seen.Has(browser.name))
                this._browserNames.Push(browser.name)
            seen[browser.name] := true
        }
        browserType := BrowserActions.BrowserType(this.Data.BrowserType)
        if (parts.Length && browserType != "" && browserType != "自定义路径" && !seen.Has(browserType))
            this._browserNames.Push(browserType)
        this._browserNames.Push("自定义路径")
        for name in this._browserNames
            this._ComboPush("BrowserType", "AddItem", GetLang(name))

        for varName in GetGuiVarArr() {
            if (varName != "") {
                this._ComboPush("SaveVar", "AddItem", varName)
                for field, name in BrowserPageInfo.Outputs
                    this._ComboPush(name, "AddItem", varName)
                this._ComboPush("TargetRef", "AddItem", "{" varName "}")
                this._ComboPush("TabMatchValue", "AddItem", "{" varName "}")
                this._ComboPush("Url", "AddItem", "{" varName "}")
                this._ComboPush("Selector", "AddItem", "{" varName "}")
            }
        }
        for name in ["Url", "TargetRef", "Selector", "JsCode", "AttrName", "BrowserPath", "CoordX", "CoordY"]
            this._ComboPush(name, "Text", String(this.Data.%name%))
        this._ComboPush("SaveVar", "Text", GetLang(this.Data.SaveVar))
        this._ComboPush("TabMatchValue", "Text", this.Data.TargetRef)
        this._FillTabMatchModes(actionType, this.Data.TabMatchMode)
        this._ComboPush("TabCloseMode", "SelectedIndex", BrowserActions.ChoiceIndex(BrowserActions.TabCloseMode(this.Data.TabCloseMode), BrowserActions.TabCloseModes))
        this._ComboPush("CurrentTabAction", "SelectedIndex", BrowserActions.ChoiceIndex(this.Data.CurrentTabAction, BrowserActions.CurrentTabActions))
        for field, name in BrowserPageInfo.Outputs
            this._ComboPush(name, "Text", this.Data.%name%)
        for action in ["元素信息", "元素位置/宽高"]
            for label, name in BrowserElementInfo.Outputs(action)
                this._ComboPush(name, "Text", this.Data.%name%)
        this._ComboPush(actionType == "网页截图" ? "SavePath" : "Text", "Text", String(this.Data.Text))
        this._ComboPush("ClearBefore", "IsChecked", this.Data.ClearBefore ? "True" : "False")
        this._ComboPush("Checked", "IsChecked", this.Data.Checked ? "True" : "False")
        this._ComboPush("UseCDP", "IsChecked", this.Data.UseCDP ? "True" : "False")
        this._ComboPush("OpenMode", "SelectedIndex", BrowserActions.ChoiceIndex(this.Data.OpenMode, BrowserActions.OpenModes))
        this._ComboPush("PageSource", "SelectedIndex", BrowserActions.ChoiceIndex(this.Data.PageSource, BrowserPageInfo.Sources))
        this._ComboPush("FullPage", "IsChecked", this.Data.FullPage ? "True" : "False")

        actionFound := false
        for groupIndex, group in BrowserActions.Groups {
            for actionIndex, action in group.actions {
                if (action == actionType) {
                    actionFound := true
                    this._activeActions := group.actions
                    this._ComboPush("ActionGroup", "SelectedIndex", groupIndex - 1)
                    this._ComboPush("ActionType", "ClearItems", "")
                    for name in group.actions
                        this._ComboPush("ActionType", "AddItem", this._ActionLabel(name))
                    this._ComboPush("ActionType", "SelectedIndex", actionIndex - 1)
                    break 2
                }
            }
        }
        if (!actionFound)
            throw ValueError(GetLang("不支持的浏览器操作：") actionType)
        for name, values in Map("SelectorType", BrowserGui.SelectorTypes, "Condition", BrowserGui.Conditions,
            "LoadState", BrowserGui.LoadStates, "BrowserType", this._browserNames, "MouseBtn", BrowserGui.MouseButtons, "StorageType", BrowserGui.StorageTypes)
            this._ComboPush(name, "SelectedIndex", BrowserActions.ChoiceIndex((name == "BrowserType" ? browserType : this.Data.%name%), values))
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs, this.Data.TimeoutAction, this.Data.TimeoutStatusVar)
        this._UpdateFieldVisibilities(actionType, browserType, this.Data.PageSource,
            this.Data.PageIdVar != "" || this.Data.PageStateVar != "" ? "标签页ID" : "")
    }

    _ReadData() {
        data := this.Data.Clone()
        state := this.ui.Query("BrowserType", "BrowserPath", "TargetRef", "Url",
            "SelectorType", "Selector", "Condition", "LoadState", "Text", "SavePath", "ClearBefore",
            "Checked", "FullPage", "OpenMode", "JsCode", "AttrName", "SaveVar",
            "CoordX", "CoordY", "MouseBtn", "StorageType", "PageSource", "UseCDP", "PageIdVar", "PageUrlVar", "PageTitleVar", "PageStateVar",
            "TabMatchMode", "TabMatchValue", "CurrentTabAction", "TabCloseMode")
        data.ActionType := this._Action(this.ui)
        for action in ["元素信息", "元素位置/宽高"]
            for label, name in BrowserElementInfo.Outputs(action)
                data.%name% := data.ActionType == action ? GetVarName(Trim(this.ui.Query(name))) : ""
        data.CurrentTabAction := BrowserActions._Choice(state["CurrentTabAction"], BrowserActions.CurrentTabActions)
        data.TabMatchMode := BrowserActions._Choice(state["TabMatchMode"], BrowserActions.MatchModes(data.ActionType))
        data.TabCloseMode := BrowserActions._Choice(state["TabCloseMode"], BrowserActions.TabCloseModes)
        data.OpenMode := BrowserActions._Choice(state["OpenMode"], BrowserActions.OpenModes)
        data.UseCDP := state["UseCDP"] == "True"
        data.PageSource := BrowserActions._Choice(state["PageSource"], BrowserPageInfo.Sources)
        for field, name in BrowserPageInfo.Outputs
            data.%name% := data.ActionType == "标签页信息" ? GetVarName(Trim(state[name])) : ""
        for name, values in Map("SelectorType", BrowserGui.SelectorTypes, "Condition", BrowserGui.Conditions,
            "LoadState", BrowserGui.LoadStates, "BrowserType", this._browserNames, "MouseBtn", BrowserGui.MouseButtons, "StorageType", BrowserGui.StorageTypes)
            data.%name% := BrowserActions._Choice(state[name], values)
        isTab := BrowserActions.IsTabAction(data.ActionType)
        if (isTab || !BrowserActions.UsesTimeout(data.ActionType)) {
            ; 不读取隐藏的超时参数，避免切换操作后沿用变量超时或重试设置。
            data.TimeoutMs := TimeoutPolicy.DefaultMs
            data.TimeoutAction := isTab ? TimeoutPolicy.DefaultAction : "停止"
            data.TimeoutStatusVar := ""
        } else if (BrowserActions.UsesTimeout(data.ActionType))
            CommandTimeoutFields.Read(this.ui, data)
        for name in ["Url", "TargetRef", "Selector", "JsCode", "AttrName", "BrowserPath", "CoordX", "CoordY"]
            data.%name% := state[name]
        if (data.ActionType == "切换标签页" || data.ActionType == "关闭标签页")
            data.TargetRef := Trim(state["TabMatchValue"])
        if (BrowserElementInfo.IsRead(data.ActionType))
            data.TargetRef := ""
        data.Text := state[data.ActionType == "网页截图" ? "SavePath" : "Text"]
        data.ClearBefore := state["ClearBefore"] == "True"
        data.Checked := state["Checked"] == "True"
        data.FullPage := state["FullPage"] == "True"
        data.SaveVar := isTab || BrowserElementInfo.IsRead(data.ActionType) ? "" : GetVarName(Trim(state["SaveVar"]))
        return data
    }

    CheckIfValid() {
        data := this._ReadData()
        message := ""
        if (data.ActionType == "标签页信息") {
            if (data.PageSource == "元素匹配" && Trim(data.Selector) == "")
                message := GetLang("元素选择器不能为空。")
            else if (BrowserPageInfo.UsesMatchValue(data.PageSource) && Trim(data.Url) == "")
                message := GetLang("请填写标签页匹配值。")
            else {
                selected := false, names := Map()
                for field, name in BrowserPageInfo.Outputs {
                    value := data.%name%
                    if (value == "")
                        continue
                    if (!CheckVarNameIfValid(value))
                        return false
                    if (names.Has(value))
                        message := GetLang("各信息请使用不同的变量名。")
                    names[value] := true
                    selected := true
                }
                if (!selected)
                    message := GetLang("请至少填写一个信息变量。")
                if (BrowserPageInfo.IsRegex(data.PageSource)) {
                    try RegExMatch("", data.Url)
                    catch
                        message := GetLang("正则表达式无效。")
                }
            }
        } else if (data.ActionType == "切换标签页" || data.ActionType == "关闭标签页") {
            if (data.TabMatchMode == "元素匹配" && Trim(data.Selector) == "")
                message := GetLang("元素选择器不能为空。")
            else if (data.TabMatchMode != "当前标签页" && data.TabMatchMode != "元素匹配" && data.TargetRef == "")
                message := GetLang("请填写标签页匹配值。")
            else if (data.TabMatchMode == "序号" && !InStr(data.TargetRef, "{") && (!IsInteger(data.TargetRef) || data.TargetRef < 1))
                message := GetLang("标签页序号必须为正整数。")
            else if (BrowserPageInfo.IsRegex(data.TabMatchMode)) {
                try RegExMatch("", data.TargetRef)
                catch
                    message := GetLang("正则表达式无效。")
            }
        } else if (BrowserActions.UsesTimeout(data.ActionType)
            && !TimeoutPolicy.ValidMs(data.TimeoutMs, 2147483647))
            message := GetLang("超时必须是正整数。")
        else if (data.ActionType == "打开网址" && Trim(data.Url) == "")
            message := GetLang("网址不能为空。")
        else if (data.ActionType == "打开网址" && data.BrowserType == "自定义路径" && Trim(data.BrowserPath) == "")
            message := GetLang("浏览器路径不能为空。")
        else if (BrowserActions.UsesSelector(data.ActionType) && data.ActionType != "等待文字" && Trim(data.Selector) == "")
            message := GetLang("元素选择器不能为空。")
        else if (data.ActionType == "执行JS" && Trim(data.JsCode) == "")
            message := GetLang("JavaScript 脚本不能为空。")
        if (message != "") {
            RmtDialog.Info(message, GetLang("浏览器"), this.Hwnd())
            return false
        }
        if (BrowserElementInfo.IsRead(data.ActionType)) {
            selected := false, names := Map()
            for label, name in BrowserElementInfo.Outputs(data.ActionType) {
                value := data.%name%
                if (value == "")
                    continue
                selected := true
                if (!CheckVarNameIfValid(value))
                    return false
                if (names.Has(value)) {
                    RmtDialog.Info(GetLang("各信息请使用不同的变量名。"), GetLang("浏览器"), this.Hwnd())
                    return false
                }
                names[value] := true
            }
            if (!selected) {
                RmtDialog.Info(GetLang("请至少填写一个信息变量。"), GetLang("浏览器"), this.Hwnd())
                return false
            }
        }
        if (data.SaveVar != "" && !CheckVarNameIfValid(data.SaveVar))
            return false
        if (!BrowserActions.UsesTimeout(data.ActionType))
            return true
        results := []
        if (BrowserElementInfo.IsRead(data.ActionType))
            for label, name in BrowserElementInfo.Outputs(data.ActionType)
                if (data.%name% != "")
                    results.Push(data.%name%)
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
        if (this.Data.ActionType == "标签页信息")
            for field, name in BrowserPageInfo.Outputs
                if (this.Data.%name% != "")
                    MySoftData.GlobalVariMap[this.Data.%name%] := true
        if (BrowserElementInfo.IsRead(this.Data.ActionType))
            for label, name in BrowserElementInfo.Outputs(this.Data.ActionType)
                if (this.Data.%name% != "")
                    MySoftData.GlobalVariMap[this.Data.%name%] := true
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang("浏览器") RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }
}
