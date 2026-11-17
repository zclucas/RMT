#Requires AutoHotkey v2.0

; ==============================================================================
; 浏览器操作编辑器 (BrowserGui)
; ==============================================================================

class BrowserGui extends CommentGui {
    ; 分组结构定义
    static Groups := [
        {
            name: "分页控制",
            actions: ["打开网址", "新建分页", "切换分页", "关闭分页", "获取分页列表"]
        },
        {
            name: "等待条件",
            actions: ["等待元素", "等待文字", "等待加载"]
        },
        {
            name: "元素互动",
            actions: ["点击", "输入", "清空", "选择下拉", "勾选", "滚动至元素", "悬停", "元素数量"]
        },
        {
            name: "资料撷取",
            actions: ["提取文本", "提取属性", "提取HTML", "执行JS", "获取网址", "获取标题", "网页截图"]
        },
        {
            name: "常规导航",
            actions: ["刷新", "后退", "前进", "关闭浏览器"]
        }
    ]

    static SelectorTypes := ["CSS", "XPath"]
    static Conditions := ["出现", "消失", "可见"]
    static LoadStates := ["完全加载", "DOM加载", "网络空闲"]
    static OnErrors := ["停止", "忽略", "重试"]

    _textEditor := ""
    _installedBrowsers := []

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("浏览器操作编辑器")
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)

        body := main.Add("StackPanel").Grid_Row(1).Margin("16,10").Grid_IsSharedSizeScope("True")
        this._Field(body, "备注：", "Remark", false)

        ; 动作类型（双级级联下拉：分组 + 具体动作）
        actionRow := this._Row(body, "动作类型：")
        actionPanel := actionRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal")
        
        ; 分组下拉
        groupNames := []
        for g in BrowserGui.Groups
            groupNames.Push(g.name)
        this._Choice(actionPanel, "ActionGroup", groupNames).Width(110).Margin("0,0,8,0")
        
        ; 具体动作下拉
        firstGroupActions := BrowserGui.Groups[1].actions
        this._Choice(actionPanel, "ActionType", firstGroupActions).Width(150)

        ; 浏览器选择行（针对「打开网址」）
        browserRow := body.Add("Grid").Name("BrowserRow").Margin("0,3")
        this._Columns(browserRow)
        browserRow.Add("TextBlock").Text(GetLang("浏览器：")).VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        box := browserRow.Add("ComboBox").Name("BrowserType").Grid_Column(1).Height(28).MinHeight(28).Padding("7,0,23,0").HorizontalAlignment("Left").Width(220)

        ; 自定义浏览器路径
        this._Field(body, "浏览器路径：", "BrowserPath", false, 28, "BrowserPathRow")

        ; 分页目标选择（索引/标题/URL）
        this._Field(body, "目标分页：", "TargetRef", false, 28, "TargetRefRow")

        ; 网址 (URL)
        this._Field(body, "网址 (URL)：", "Url", false, 28, "UrlRow")

        ; 元素选择器类型 + 选择器
        selTypeRow := body.Add("Grid").Name("SelectorTypeRow").Margin("0,3")
        this._Columns(selTypeRow)
        selTypeRow.Add("TextBlock").Text(GetLang("选择器类型：")).VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        this._Choice(selTypeRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal"), "SelectorType", BrowserGui.SelectorTypes).Width(120)

        this._Field(body, "元素选择器：", "Selector", false, 28, "SelectorRow")

        ; 等待条件选项
        condRow := body.Add("Grid").Name("ConditionRow").Margin("0,3")
        this._Columns(condRow)
        condRow.Add("TextBlock").Text(GetLang("等待状态：")).VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        this._Choice(condRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal"), "Condition", BrowserGui.Conditions).Width(140)

        ; 页面加载等待选项
        loadRow := body.Add("Grid").Name("LoadStateRow").Margin("0,3")
        this._Columns(loadRow)
        loadRow.Add("TextBlock").Text(GetLang("加载状态：")).VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        this._Choice(loadRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal"), "LoadState", BrowserGui.LoadStates).Width(140)

        ; 输入文本 / 匹配文本 / 下拉值
        this._Field(body, "输入内容：", "Text", false, 28, "TextRow")

        ; 选项勾选行（清空 / 勾选状态 / 全页截图）
        cbRow := body.Add("Grid").Name("OptionsRow").Margin("0,3")
        this._Columns(cbRow)
        cbRow.Add("TextBlock").Text(GetLang("选项设置：")).VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        optPanel := cbRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        optPanel.Add("CheckBox").Name("ClearBefore").Content(GetLang("清空输入框")).Margin("0,0,12,0").Foreground("{DynamicResource TextMain}")
        optPanel.Add("CheckBox").Name("Checked").Content(GetLang("勾选(取消则不勾)")).Margin("0,0,12,0").Foreground("{DynamicResource TextMain}")
        optPanel.Add("CheckBox").Name("FullPage").Content(GetLang("全页完整截图")).Margin("0,0,12,0").Foreground("{DynamicResource TextMain}")

        ; JavaScript 脚本
        this._Field(body, "JavaScript 脚本：", "JsCode", true, 75, "JsCodeRow")

        ; 属性名称
        this._Field(body, "属性名称：", "AttrName", false, 28, "AttrNameRow")

        ; 截图保存路径
        this._Field(body, "截图保存路径：", "SavePath", false, 28, "SavePathRow")

        ; 变量保存（独立一行）
        this._Field(body, "保存结果变量：", "SaveVar", false, 28, "SaveVarRow")

        ; 折叠进阶设置 (Expander)
        exp := body.Add("Expander").Margin("0,8,0,0").Header(GetLang("进阶设置（超时与异常重试）")).Foreground("{DynamicResource TextMain}")
        expPanel := exp.Add("StackPanel").Margin("0,6")

        ; 超时配置
        this._Field(expPanel, "超时（毫秒）：", "TimeoutMs", false, 28, "TimeoutRow")

        ; 失败处理方式
        errRow := expPanel.Add("Grid").Name("OnErrorRow").Margin("0,3")
        this._Columns(errRow)
        errRow.Add("TextBlock").Text(GetLang("失败处理：")).VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        errStack := errRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal")
        this._Choice(errStack, "OnError", BrowserGui.OnErrors).Width(120)
        errStack.Add("TextBlock").Text(GetLang("重试次数：")).VerticalAlignment("Center").Margin("16,0,8,0").Foreground("{DynamicResource TextMain}")
        this._TextBox(errStack, "RetryCount", 28).Width(60)

        buttons := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,14,0,0")
        AddCmdOkBtn(buttons)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="640" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnEditJsCode", "Click", ObjBindMethod(this, "_QueueTextEditor", "JsCode"))
        this.ui.OnEvent("ActionGroup", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionGroupChanged"))
        this.ui.OnEvent("ActionType", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionTypeChanged"))
        this.ui.OnEvent("BrowserType", "SelectionChanged", XamlWin.BindCurrent(this, "OnBrowserTypeChanged"))

        BindCmdEditorChrome(this.ui, "#指令手册/浏览器")
    }

    _Row(body, label, rowName := "") {
        row := body.Add("Grid").Margin("0,3")
        if (rowName != "")
            row.Name(rowName)
        this._Columns(row)
        row.Add("TextBlock").Text(GetLang(label)).VerticalAlignment("Center").Margin("0,0,8,0")
            .Foreground("{DynamicResource TextMain}")
        return row
    }

    _Columns(grid, paired := false) {
        columns := grid.Add("Grid.ColumnDefinitions")
        columns.Add("ColumnDefinition").Width("Auto").SharedSizeGroup("BrowserLabel")
        columns.Add("ColumnDefinition").Width("*")
        if (paired) {
            columns.Add("ColumnDefinition").Width(20)
            columns.Add("ColumnDefinition").Width("Auto")
            columns.Add("ColumnDefinition").Width("*")
        }
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
            .Padding("2,2").Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
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

    ; 当切换分组时，动态刷新「ActionType」下拉列表中的选项
    OnActionGroupChanged(*) {
        grp := this.ui.Query("ActionGroup")
        curAction := this.ui.Query("ActionType")
        
        targetActions := []
        for g in BrowserGui.Groups {
            if (g.name == grp) {
                targetActions := g.actions
                break
            }
        }
        if (targetActions.Length == 0)
            targetActions := BrowserGui.Groups[1].actions

        ; 更新 ActionType 下拉框
        this.ui.Update("ActionType", "ClearItems", "")
        newIdx := 0
        for i, act in targetActions {
            this.ui.Update("ActionType", "AddItem", GetLang(act))
            if (act == curAction)
                newIdx := i - 1
        }
        this.ui.Update("ActionType", "SelectedIndex", newIdx)
        this._UpdateFieldVisibilities()
    }

    OnActionTypeChanged(*) {
        this._UpdateFieldVisibilities()
    }

    OnBrowserTypeChanged(*) {
        this._UpdateFieldVisibilities()
    }

    _UpdateFieldVisibilities() {
        action := this.ui.Query("ActionType")
        bType := this.ui.Query("BrowserType")

        isNav := (action == "打开网址")
        this.ui.Update("BrowserRow", "Visibility", isNav ? "Visible" : "Collapsed")
        this.ui.Update("BrowserPathRow", "Visibility", (isNav && bType == "自定义路径") ? "Visible" : "Collapsed")

        isNewTab := (action == "新建分页")
        this.ui.Update("UrlRow", "Visibility", (isNav || isNewTab) ? "Visible" : "Collapsed")

        isSwitchTab := (action == "切换分页" || action == "关闭分页")
        this.ui.Update("TargetRefRow", "Visibility", isSwitchTab ? "Visible" : "Collapsed")

        isWaitElem := (action == "等待元素")
        isWaitText := (action == "等待文字")
        isWaitLoad := (action == "等待加载")

        isClick := (action == "点击")
        isType := (action == "输入")
        isClear := (action == "清空")
        isSelect := (action == "选择下拉")
        isCheck := (action == "勾选")
        isScroll := (action == "滚动至元素")
        isHover := (action == "悬停")
        isCount := (action == "元素数量")

        isExtractText := (action == "提取文本")
        isExtractAttr := (action == "提取属性")
        isExtractHtml := (action == "提取HTML")
        isJs := (action == "执行JS")
        isScreenshot := (action == "网页截图")

        needSelector := (isWaitElem || isWaitText || isClick || isType || isClear || isSelect || isCheck || isScroll || isHover || isCount || isExtractText || isExtractAttr || isExtractHtml)
        this.ui.Update("SelectorTypeRow", "Visibility", needSelector ? "Visible" : "Collapsed")
        this.ui.Update("SelectorRow", "Visibility", needSelector ? "Visible" : "Collapsed")

        this.ui.Update("ConditionRow", "Visibility", isWaitElem ? "Visible" : "Collapsed")
        this.ui.Update("LoadStateRow", "Visibility", isWaitLoad ? "Visible" : "Collapsed")

        showText := (isWaitText || isType || isSelect)
        this.ui.Update("TextRow", "Visibility", showText ? "Visible" : "Collapsed")

        ; 选项面板子项显示
        this.ui.Update("OptionsRow", "Visibility", (isType || isCheck || isScreenshot) ? "Visible" : "Collapsed")
        this.ui.Update("ClearBefore", "Visibility", isType ? "Visible" : "Collapsed")
        this.ui.Update("Checked", "Visibility", isCheck ? "Visible" : "Collapsed")
        this.ui.Update("FullPage", "Visibility", isScreenshot ? "Visible" : "Collapsed")

        this.ui.Update("JsCodeRow", "Visibility", isJs ? "Visible" : "Collapsed")
        this.ui.Update("AttrNameRow", "Visibility", isExtractAttr ? "Visible" : "Collapsed")
        this.ui.Update("SavePathRow", "Visibility", isScreenshot ? "Visible" : "Collapsed")

        ; 保存变量行
        hasSaveVar := (isJs || isExtractText || isExtractAttr || isExtractHtml || isCount || action == "获取网址" || action == "获取标题" || action == "获取分页列表")
        this.ui.Update("SaveVarRow", "Visibility", hasSaveVar ? "Visible" : "Collapsed")
    }

    Init(cmd) {
        parts := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr("浏览器")
        this.Data := GetMacroCMDData(this.SerialStr)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")

        ; 动态检测系统中安装的浏览器
        this._installedBrowsers := BrowserUtil.GetInstalledBrowsers()
        browserNames := []
        for b in this._installedBrowsers {
            browserNames.Push(b.name)
        }
        if (browserNames.Length == 0) {
            browserNames.Push("Chrome")
            browserNames.Push("Edge")
        }
        browserNames.Push("自定义路径")

        for bName in browserNames {
            this._ComboPush("BrowserType", "AddItem", GetLang(bName))
        }

        for varName in GetGuiVarArr() {
            if (varName != "")
                this._ComboPush("SaveVar", "AddItem", varName)
        }

        for name in ["Url", "TargetRef", "Selector", "Text", "JsCode", "AttrName", "SaveVar", "TimeoutMs", "BrowserPath", "RetryCount"] {
            if (this.Data.HasOwnProp(name))
                this._ComboPush(name, "Text", String(this.Data.%name%))
        }

        if (this.Data.HasOwnProp("ActionType") && this.Data.ActionType == "网页截图") {
            this._ComboPush("SavePath", "Text", String(this.Data.Text))
        }

        if (this.Data.HasOwnProp("ClearBefore"))
            this._ComboPush("ClearBefore", "IsChecked", this.Data.ClearBefore ? "True" : "False")

        if (this.Data.HasOwnProp("Checked"))
            this._ComboPush("Checked", "IsChecked", this.Data.Checked ? "True" : "False")

        if (this.Data.HasOwnProp("OuterHtml"))
            this._ComboPush("FullPage", "IsChecked", this.Data.OuterHtml ? "True" : "False")

        ; 查找 ActionType 所属的 Group
        targetAct := this.Data.ActionType
        targetGroupIdx := 0
        targetActionIdx := 0
        found := false

        for gIdx, g in BrowserGui.Groups {
            for aIdx, act in g.actions {
                if (act == targetAct) {
                    targetGroupIdx := gIdx - 1
                    targetActionIdx := aIdx - 1
                    found := true
                    break 2
                }
            }
        }

        ; 如果动作是旧版的或未分类，默认归在第1组
        if (!found) {
            targetGroupIdx := 0
            targetActionIdx := 0
        }

        ; 初始化 ActionGroup
        this._ComboPush("ActionGroup", "SelectedIndex", targetGroupIdx)

        ; 依据所在组初始化 ActionType 的下拉列表项
        activeActions := BrowserGui.Groups[targetGroupIdx + 1].actions
        this._ComboPush("ActionType", "ClearItems", "")
        for act in activeActions {
            this._ComboPush("ActionType", "AddItem", GetLang(act))
        }
        this._ComboPush("ActionType", "SelectedIndex", targetActionIdx)

        ; 选择下拉初始化
        setChoice(ctrlName, listArr, currentVal) {
            valIdx := 0
            for i, val in listArr {
                if (val == currentVal) {
                    valIdx := i - 1
                    break
                }
            }
            this._ComboPush(ctrlName, "SelectedIndex", valIdx)
        }

        setChoice("SelectorType", BrowserGui.SelectorTypes, this.Data.HasOwnProp("SelectorType") ? this.Data.SelectorType : "CSS")
        setChoice("Condition", BrowserGui.Conditions, this.Data.HasOwnProp("Condition") ? this.Data.Condition : "出现")
        setChoice("LoadState", BrowserGui.LoadStates, this.Data.HasOwnProp("LoadState") ? this.Data.LoadState : "完全加载")
        setChoice("OnError", BrowserGui.OnErrors, this.Data.HasOwnProp("OnError") ? this.Data.OnError : "停止")

        selectedIdx := 0
        currentBType := this.Data.HasOwnProp("BrowserType") ? this.Data.BrowserType : ""
        for i, val in browserNames {
            if (val == currentBType) {
                selectedIdx := i - 1
                break
            }
        }
        this._ComboPush("BrowserType", "SelectedIndex", selectedIdx)

        SetTimer(() => this._UpdateFieldVisibilities(), -50)
    }

    _ReadData() {
        data := BrowserData()
        data.SerialStr := this.Data.SerialStr
        data.ActionType := this.ui.Query("ActionType")
        data.BrowserType := this.ui.Query("BrowserType")
        data.BrowserPath := this.ui.Query("BrowserPath")
        data.TargetRef := this.ui.Query("TargetRef")
        data.Url := this.ui.Query("Url")
        data.SelectorType := this.ui.Query("SelectorType")
        data.Selector := this.ui.Query("Selector")
        data.Condition := this.ui.Query("Condition")
        data.LoadState := this.ui.Query("LoadState")
        data.Text := (data.ActionType == "网页截图") ? this.ui.Query("SavePath") : this.ui.Query("Text")
        data.ClearBefore := (this.ui.Query("ClearBefore") == "True") ? 1 : 0
        data.Checked := (this.ui.Query("Checked") == "True") ? 1 : 0
        data.OuterHtml := (this.ui.Query("FullPage") == "True") ? 1 : 0
        data.JsCode := this.ui.Query("JsCode")
        data.AttrName := this.ui.Query("AttrName")
        data.SaveVar := GetVarName(Trim(this.ui.Query("SaveVar")))
        data.TimeoutMs := Integer(this.ui.Query("TimeoutMs") || 10000)
        data.OnError := this.ui.Query("OnError")
        data.RetryCount := Integer(this.ui.Query("RetryCount") || 3)
        return data
    }

    CheckIfValid() {
        data := this._ReadData()
        if (data.SaveVar != "" && !CheckVarNameIfValid(data.SaveVar))
            return false
        return true
    }

    SaveData() {
        this.Data := this._ReadData()
        if (this.Data.SaveVar != "") {
            MySoftData.GlobalVariMap[this.Data.SaveVar] := true
            MySoftData.GlobalVariMap[this.Data.SaveVar "_Success"] := true
            MySoftData.GlobalVariMap[this.Data.SaveVar "_Error"] := true
            MySoftData.GlobalVariMap[this.Data.SaveVar "_ElapsedMs"] := true
        }
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang("浏览器") RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }
}
