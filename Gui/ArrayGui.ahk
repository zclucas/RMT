#Requires AutoHotkey v2.0

; =====================================================================
; 数组编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class ArrayGui {
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
        this.InitEditGui := ""
        this._initEditClosed := true
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

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("数组编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容：固定标签列，所有下拉从同一竖线起 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,10").ClipToBounds("False")
        body.Rows("32", "32", "Auto", "Auto", "Auto", "Auto", "40")
        ; 右标签列固定宽度，避免嵌套 Auto 把备注/子索引/数据/结果错开
        body.Cols("78", "8", "130", "16", "60", "8", "160")

        ; 行0：类型 + 备注
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("类型：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        tc := body.Add("ComboBox").Grid_Row(0).Grid_Column(2).Name("TypeCombo").Width(130).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        for t in GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"])
            tc.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(0).Grid_Column(4).Text(GetLang("备注：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(6).Name("RemarkCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")

        ; 行1：数组名 + 子索引 / 创建勾选
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("数组名：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(2).Name("NameCon").Width(130).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        mainIndexRow := body.Add("Grid").Name("MainIndexRow").Grid_Row(1).Grid_Column(4).Grid_ColumnSpan(3).Visibility("Collapsed")
        mainIndexRow.Cols("60", "8", "160")
        mainIndexRow.Add("TextBlock").Grid_Column(0).Text(GetLang("子索引：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
            .ToolTip(GetLang("0 表示整个数组；N 表示第 N 项子数组"))
        mainIndexRow.Add("ComboBox").Grid_Column(2).Name("MainIndexCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")
            .ToolTip(GetLang("0 表示整个数组；N 表示第 N 项子数组"))
        body.Add("CheckBox").Grid_Row(1).Grid_Column(4).Grid_ColumnSpan(3).Name("IsIgnoreExist")
            .Content(GetLang("如果数组存在则不改变数据")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")

        ; 行2：初始数据（两行输入 + 右上角悬浮编辑，左缘与上方下拉对齐）
        body.Add("TextBlock").Name("InitArrLabel").Grid_Row(2).Grid_Column(0).Text(GetLang("初始数据："))
            .VerticalAlignment("Top").Margin("0,8,0,0").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
            .ToolTip(GetLang("逗号分割；[ ] 表示子数组；\\ 表示原义字符"))
        initHost := body.Add("Grid").Name("InitArrHost").Grid_Row(2).Grid_Column(2).Grid_ColumnSpan(5).Margin("0,2,0,2")
        initHost.Rows("56")
        initHost.Add("TextBox").Name("InitArrCon").AcceptsReturn("True").TextWrapping("Wrap").Text("1, 2, 3")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch").MinHeight("56")
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
            .ToolTip(GetLang("逗号分割；[ ] 表示子数组；\\ 表示原义字符"))
        initHost.Add("Button").Name("BtnInitEdit").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 行3：索引
        argsIndexRow := body.Add("Grid").Name("ArgsIndexRow").Grid_Row(3).Grid_ColumnSpan(7).Margin("0,2,0,2").Visibility("Collapsed")
        argsIndexRow.Cols("78", "8", "130", "16", "60", "8", "160")
        argsIndexRow.Add("TextBlock").Grid_Column(0).Text(GetLang("索引：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        argsIndexRow.Add("ComboBox").Grid_Column(2).Name("ArgsIndexCon").Width(130).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")

        ; 行4：数据
        argsDataRow := body.Add("Grid").Name("ArgsDataRow").Grid_Row(4).Grid_ColumnSpan(7).Margin("0,2,0,2").Visibility("Collapsed")
        argsDataRow.Cols("78", "8", "130", "16", "60", "8", "160")
        argsDataRow.Add("TextBlock").Grid_Column(0).Text(GetLang("数据：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        at := argsDataRow.Add("ComboBox").Grid_Column(2).Name("ArgsTypeCon").Width(130).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")
        at.Add("ComboBoxItem").Content(GetLang("变量或值"))
        at.Add("ComboBoxItem").Content(GetLang("数组"))
        argsDataRow.Add("ComboBox").Grid_Column(4).Grid_ColumnSpan(3).Name("ArgsNameCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")

        ; 行5：结果
        resRow := body.Add("Grid").Name("ResultRow").Grid_Row(5).Grid_ColumnSpan(7).Margin("0,2,0,2").Visibility("Collapsed")
        resRow.Cols("78", "8", "130", "16", "60", "8", "160")
        resRow.Add("TextBlock").Grid_Column(0).Text(GetLang("结果：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        st := resRow.Add("ComboBox").Grid_Column(2).Name("SaveTypeCon").Width(130).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        resRow.Add("ComboBox").Grid_Column(4).Grid_ColumnSpan(3).Name("SaveNameCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").SnapsToDevicePixels("True")

        ; 行6：确定（放进内容网格，避免主网格多一行把窗口撑高）
        btnRow := body.Add("StackPanel").Grid_Row(6).Grid_ColumnSpan(7).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        winSize := 'Title="' this._EscapeXml(title) '" Width="520" SizeToContent="Height"'
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', winSize)
        if (InStr(this.ui.xaml, 'Width="940"') || InStr(this.ui.xaml, 'Height="700"')) {
            cnt := 0
            this.ui.xaml := RegExReplace(this.ui.xaml, 'Width="[^"]+" Height="[^"]+"', winSize, &cnt, 1)
        }
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/19-数组")
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("ArgsTypeCon", "SelectionChanged", ObjBindMethod(this, "OnRefreshDataType"))
        this.ui.OnEvent("SaveTypeCon", "SelectionChanged", ObjBindMethod(this, "OnRefreshDataType"))
        this.ui.OnEvent("BtnInitEdit", "Click", ObjBindMethod(this, "OpenInitEditor"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this.OnRefresh()
    }

    OnWindowClosing(state, ctrl, event) {
        this._CloseInitEditor()
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
        this._CloseInitEditor()
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

    _Vis(name, show) {
        if (IsObject(this.ui))
            this.ui.Update(name, "Visibility", show ? "Visible" : "Collapsed")
    }

    _TypeText() => IsObject(this.ui) ? this.ui.Query("TypeCombo") : ""

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("数组")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        this.DLArrayArr := GetGuiArrNameArr()

        this._SetDDL("TypeCombo", GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"]), GetLang(this.Data.Type))
        this.ui.Update("IsIgnoreExist", "IsChecked", this.Data.IsIgnoreExist ? "True" : "False")
        this._SetCombo("NameCon", this.DLArrayArr, this.Data.Name)
        this._SetCombo("MainIndexCon", GetGuiVarArr(2), this.Data.MainIndex)
        this.ui.Update("InitArrCon", "Text", GetArrayStr(this.Data.InitArr))
        this._SetCombo("ArgsIndexCon", GetGuiVarArr(2), this.Data.ArgsIndex)
        this._SetDDL("ArgsTypeCon", GetLangArr(["变量或值", "数组"]), GetLang(this.Data.ArgsType))
        this._SetCombo("ArgsNameCon", this.DLVariableArr, this.Data.ArgsName)
        this._SetDDL("SaveTypeCon", GetLangArr(["变量", "数组"]), GetLang(this.Data.SaveType))
        this._SetCombo("SaveNameCon", this.DLVariableArr, this.Data.SaveName)
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        t := this._TypeText()
        IsCreate := t == GetLang("创建")
        IsClone := t == GetLang("克隆")
        IsDelete := t == GetLang("删除")
        IsContain := t == GetLang("包含")
        IsGet := t == GetLang("取值")
        IsSetValue := t == GetLang("赋值")
        IsInsert := t == GetLang("插入")
        IsAdd := t == GetLang("追加")
        IsRemove := t == GetLang("移除")
        IsRemoveLast := t == GetLang("移除最后")
        IsReverse := t == GetLang("反转")
        IsLength := t == GetLang("长度")
        OnlyResVar := IsLength || IsContain
        OnlyResArr := IsClone || IsReverse
        OnlyArgsIndex := IsGet || IsRemove
        OnlyArgsData := IsAdd || IsContain
        IsShowRusult := IsGet || IsLength || IsClone || IsRemove || IsRemoveLast || IsContain || IsReverse
        IsShowMainIndex := !IsCreate && !IsDelete
        IsShowArgs := IsGet || IsSetValue || IsInsert || IsAdd || IsRemove || IsContain

        this._Vis("MainIndexRow", IsShowMainIndex)
        this._Vis("IsIgnoreExist", IsCreate)
        this._Vis("InitArrLabel", IsCreate)
        this._Vis("InitArrHost", IsCreate)
        this._Vis("ArgsIndexRow", IsShowArgs && !OnlyArgsData)
        this._Vis("ArgsDataRow", IsShowArgs && !OnlyArgsIndex)
        this._Vis("ResultRow", IsShowRusult)

        if (OnlyResVar || OnlyResArr) {
            this._SetDDL("SaveTypeCon", GetLangArr(["变量", "数组"]), OnlyResVar ? GetLang("变量") : GetLang("数组"))
            this.ui.Update("SaveTypeCon", "IsEnabled", "False")
        }
        else {
            this.ui.Update("SaveTypeCon", "IsEnabled", "True")
        }
        this.OnRefreshDataType()
    }

    OnRefreshDataType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsArgsVar := this.ui.Query("ArgsTypeCon") == GetLang("变量或值")
        IsResVar := this.ui.Query("SaveTypeCon") == GetLang("变量")
        ArgsArr := IsArgsVar ? this.DLVariableArr : this.DLArrayArr
        ResArr := IsResVar ? GetGuiVarArr(0) : this.DLArrayArr
        curArgs := this.ui.Query("ArgsNameCon")
        curSave := this.ui.Query("SaveNameCon")
        this._SetCombo("ArgsNameCon", ArgsArr, curArgs)
        this._SetCombo("SaveNameCon", ResArr, curSave)
    }

    _CloseInitEditor() {
        if (IsObject(this.InitEditGui) && !this._initEditClosed) {
            try this.InitEditGui.Update("Window", "Close", "")
            this.InitEditGui := ""
        }
        this._initEditClosed := true
    }

    OpenInitEditor(state := "", ctrl := "", event := "") {
        if (!IsObject(this.InitEditGui) || this._initEditClosed)
            this._BuildInitEditor()
        curText := IsObject(this.ui) ? this.ui.Query("InitArrCon") : ""
        this.InitEditGui.Update("InitEditCon", "Text", curText)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        if (!XamlWin.Open(this.InitEditGui, "", owner))
            this._initEditClosed := true
    }

    _BuildInitEditor() {
        global MySoftData
        this._CloseInitEditor()
        this._initEditClosed := false
        title := this.ParentTile GetLang("初始数据：")
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,8").ClipToBounds("False")
        body.Rows("*", "Auto", "48")

        body.Add("TextBox").Grid_Row(0).Name("InitEditCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("8,6").FontSize("11").MinHeight("140")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        tip := body.Add("StackPanel").Grid_Row(1).Orientation("Vertical").Margin("0,8,0,0")
        tip.Add("TextBlock").Text(GetLang("1. 逗号分割数据")).Foreground("{DynamicResource TextSub}").FontSize("11").TextWrapping("Wrap")
        tip.Add("TextBlock").Text(GetLang("2. 中括号表示数组数据")).Foreground("{DynamicResource TextSub}").FontSize("11").TextWrapping("Wrap").Margin("0,2,0,0")
        tip.Add("TextBlock").Text(GetLang("3. 数据中使用\\符号，表示原本的功能")).Foreground("{DynamicResource TextSub}").FontSize("11").TextWrapping("Wrap").Margin("0,2,0,0")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnInitOk")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        this.InitEditGui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        this.InitEditGui.xaml := StrReplace(this.InitEditGui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="320"')
        this.InitEditGui.xaml := StrReplace(this.InitEditGui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.InitEditGui.xaml := StrReplace(this.InitEditGui.xaml, '%resources%', '')

        this.InitEditGui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnInitEditClosing"))
        this.InitEditGui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnInitEditLoad"))
        this.InitEditGui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnInitEditClose"))
        this.InitEditGui.OnEvent("InitEditCon", "TextChanged", ObjBindMethod(this, "OnInitEditChange"))
        this.InitEditGui.OnEvent("BtnInitOk", "Click", ObjBindMethod(this, "OnInitEditClose"))
    }

    OnInitEditLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.InitEditGui)
    }

    OnInitEditClosing(state, ctrl, event) {
        this._initEditClosed := true
        this.InitEditGui := ""
    }

    OnInitEditClose(state := "", ctrl := "", event := "") {
        this._CloseInitEditor()
    }

    OnInitEditChange(state := "", ctrl := "", event := "") {
        if (IsObject(this.InitEditGui) && !this._initEditClosed && IsObject(this.ui))
            this.ui.Update("InitArrCon", "Text", this.InitEditGui.Query("InitEditCon"))
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveSubMacroData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        t := this._TypeText()
        showResult := t == GetLang("取值") || t == GetLang("长度") || t == GetLang("克隆")
            || t == GetLang("移除") || t == GetLang("移除最后") || t == GetLang("包含") || t == GetLang("反转")
        if (showResult && !CheckVarNameIfValid(this.ui.Query("SaveNameCon")))
            return false
        try GetArray(this.ui.Query("InitArrCon"))
        catch ValueError as e {
            RMTErrorShow(e.Message, RMT_LV_WARN, "数组")
            return false
        }
        return true
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            switch this.Data.Type {
                case "创建":
                    Remark := Format(GetLang("创建{}"), this.Data.Name)
                case "克隆":
                    Remark := Format(GetLang("克隆{}到{}"), this.Data.Name, this.Data.SaveName)
                case "删除":
                    Remark := Format(GetLang("删除{}"), this.Data.Name)
                case "包含":
                    tip1 := Format(GetLang("{}包含数据{}"), this.Data.Name, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}包含数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "取值":
                    tip1 := Format(GetLang("取值{}-{}到{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.SaveName)
                    tip2 := Format(GetLang("取值{}-{}-{}到{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex, this.Data.SaveName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "赋值":
                    tip1 := Format(GetLang("{}-{}赋值为{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}-{}赋值为{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "插入":
                    tip1 := Format(GetLang("{}-{}插入数据{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}-{}插入数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "追加":
                    tip1 := Format(GetLang("{}追加数据{}"), this.Data.Name, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}追加数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "移除":
                    tip1 := Format(GetLang("移除{}-{}"), this.Data.Name, this.Data.ArgsIndex)
                    tip2 := Format(GetLang("移除{}-{}-{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "移除最后":
                    tip1 := Format(GetLang("移除{}-最后数据"), this.Data.Name)
                    tip2 := Format(GetLang("移除{}-{}最后数据"), this.Data.Name, this.Data.MainIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "长度":
                    tip1 := Format(GetLang("{}长度"), this.Data.Name)
                    tip2 := Format(GetLang("{}-{}长度"), this.Data.Name, this.Data.MainIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
            }
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        isCreate := this._TypeText() == GetLang("创建")
        this.Data.IsIgnoreExist := isCreate ? (this.ui.Query("IsIgnoreExist") == "True") : 0
        this.Data.Type := GetLangKey(this._TypeText())
        this.Data.Name := this.ui.Query("NameCon")
        this.Data.InitArr := GetArray(this.ui.Query("InitArrCon"))
        this.Data.MainIndex := GetLangKey(this.ui.Query("MainIndexCon"))
        this.Data.ArgsIndex := GetLangKey(this.ui.Query("ArgsIndexCon"))
        this.Data.ArgsType := GetLangKey(this.ui.Query("ArgsTypeCon"))
        this.Data.ArgsName := GetLangKey(this.ui.Query("ArgsNameCon"))
        this.Data.SaveType := GetLangKey(this.ui.Query("SaveTypeCon"))
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        SetArrayDataNewArr(this.Data)
        SetArrayDataNewVar(this.Data)
        SaveMacroCMDData(this.Data)
    }
}
