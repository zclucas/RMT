#Requires AutoHotkey v2.0

; =====================================================================
; 运行Pro编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class RunProGui {
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
        this.ActiveEdit := ""

        this.StdInEditGui := ""
        this._stdInClosed := true
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
        this.ToggleFunc(true)
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
        title := this.ParentTile GetLang("运行Pro编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容：统一列，返回值/输入编码、输出/输出编码分别左对齐 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,12")
        body.Rows("34", "34", "34", "34", "34", "34", "52", "22", "40")
        body.Cols("88", "*", "16", "80", "*", "12", "80", "*")

        ; 行0：备注
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(3).Name("RemarkCon").Height(26).MinHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：模式 + 选项
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("模式：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        rm := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("RunModeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for m in [GetLang("不等待"), GetLang("等待+返回值"), GetLang("不等待+输入"), GetLang("等待+输入输出")]
            rm.Add("ComboBoxItem").Content(m)
        body.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("选项：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        opt := body.Add("ComboBox").Grid_Row(1).Grid_Column(4).Name("OptionCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for o in GetLangArr(["后台", "默认", "最小化", "最大化"])
            opt.Add("ComboBoxItem").Content(o)

        ; 行2：变量
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("变量：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("VariCombo").Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        varBtns := body.Add("StackPanel").Grid_Row(2).Grid_Column(3).Grid_ColumnSpan(5).Orientation("Horizontal").VerticalAlignment("Center")
        varBtns.Add("Button").Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).Cursor("Hand")
        varBtns.Add("Button").Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")

        ; 行3：目标
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("目标：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(3).Grid_Column(1).Grid_ColumnSpan(6).Name("PathTextCon").Height(26).MinHeight(26).VerticalAlignment("Center").Margin("0,0,8,0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("Button").Grid_Row(3).Grid_Column(7).Name("BtnSelectFile").Content(GetLang("选择文件")).Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Stretch").Cursor("Hand")

        ; 行4：返回值 / 输出 / 错误
        sn1 := body.Add("Grid").Name("SaveName1Row").Grid_Row(4).Grid_Column(0).Grid_ColumnSpan(2)
        sn1.Cols("88", "*")
        sn1.Add("TextBlock").Name("SaveNameTip1").Grid_Column(0).Text(GetLang("返回值：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        sn1.Add("ComboBox").Name("SaveName1").Grid_Column(1).Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        sn2 := body.Add("Grid").Name("SaveName2Row").Grid_Row(4).Grid_Column(3).Grid_ColumnSpan(2)
        sn2.Cols("80", "*")
        sn2.Add("TextBlock").Name("SaveNameTip2").Grid_Column(0).Text(GetLang("输出：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        sn2.Add("ComboBox").Name("SaveName2").Grid_Column(1).Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        sn3 := body.Add("Grid").Name("SaveName3Row").Grid_Row(4).Grid_Column(6).Grid_ColumnSpan(2)
        sn3.Cols("80", "*")
        sn3.Add("TextBlock").Name("SaveNameTip3").Grid_Column(0).Text(GetLang("错误：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        sn3.Add("ComboBox").Name("SaveName3").Grid_Column(1).Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行5：输入编码 / 输出编码 / 错误编码
        ei := body.Add("Grid").Name("EncInRow").Grid_Row(5).Grid_Column(0).Grid_ColumnSpan(2)
        ei.Cols("88", "*")
        ei.Add("TextBlock").Name("EncInTip").Grid_Column(0).Text(GetLang("输入编码：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ei.Add("ComboBox").Name("EncIn").Grid_Column(1).Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        eo := body.Add("Grid").Name("EncOutRow").Grid_Row(5).Grid_Column(3).Grid_ColumnSpan(2)
        eo.Cols("80", "*")
        eo.Add("TextBlock").Name("EncOutTip").Grid_Column(0).Text(GetLang("输出编码：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        eo.Add("ComboBox").Name("EncOut").Grid_Column(1).Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ee := body.Add("Grid").Name("EncErrRow").Grid_Row(5).Grid_Column(6).Grid_ColumnSpan(2)
        ee.Cols("80", "*")
        ee.Add("TextBlock").Name("EncErrTip").Grid_Column(0).Text(GetLang("错误编码：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ee.Add("ComboBox").Name("EncErr").Grid_Column(1).Height(26).MinHeight(26).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行6：输入（白底框 + 右上角悬浮编辑，打开文本构造）
        stdRow := body.Add("Grid").Name("StdInRow").Grid_Row(6).Grid_ColumnSpan(8)
        stdRow.Cols("88", "*")
        stdRow.Add("TextBlock").Grid_Column(0).Text(GetLang("输入：")).VerticalAlignment("Top").Margin("0,6,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        stdHost := stdRow.Add("Grid").Grid_Column(1)
        stdHost.Add("TextBox").Name("StdInCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch").MinHeight("44")
            .VerticalContentAlignment("Top").FontSize("11").Padding("4,3,26,3")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        stdHost.Add("Button").Name("BtnStdInEdit").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 行7：提示
        body.Add("TextBlock").Grid_Row(7).Grid_ColumnSpan(8).Text(GetLang("支持启动程序（如.exe、.bat）、打开文件（如.txt、.mp4）或网址等等")).VerticalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize("11").TextWrapping("NoWrap")

        ; 行8：确定
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(8).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="680" Height="370"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/16-运行Pro", ObjBindMethod(this, "TriggerMacro"), "!l")
        this.ui.OnEvent("RunModeCombo", "SelectionChanged", ObjBindMethod(this, "OnModeChange"))
        this.ui.OnEvent("BtnAddName", "Click", ObjBindMethod(this, "OnClickAddVarNameBtn"))
        this.ui.OnEvent("BtnAddValue", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("PathTextCon", "GotKeyboardFocus", (*) => this.ActiveEdit := "PathTextCon")
        this.ui.OnEvent("StdInCon", "GotKeyboardFocus", (*) => this.ActiveEdit := "StdInCon")
        this.ui.OnEvent("BtnSelectFile", "Click", ObjBindMethod(this, "OnClickFileSelectBtn"))
        this.ui.OnEvent("BtnStdInEdit", "Click", ObjBindMethod(this, "OpenStdInEditor"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    _CloseStdInEditor() {
        if (IsObject(this.StdInEditGui) && !this._stdInClosed) {
            try this.StdInEditGui.Update("Window", "Close", "")
            this.StdInEditGui := ""
            this._stdInClosed := true
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
        this._CloseStdInEditor()
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
        this.ToggleFunc(false)
        this._CloseStdInEditor()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
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

    _SelIndex(comboName) {
        v := IsObject(this.ui) ? this.ui.Query(comboName ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运行Pro")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        ; 還原跳脫的花括號供介面顯示（{{xxx}} → {xxx}）
        this.ui.Update("PathTextCon", "Text", UnescapeVarText(this.Data.Target))

        DLVariableArr := GetGuiVarArr(1)
        this._SetCombo("VariCombo", DLVariableArr, "")

        this.ui.Update("RunModeCombo", "SelectedIndex", String(CmdEnumIndex(this.Data.Mode, CmdEnumRunModeNames())))
        this.ui.Update("OptionCombo", "SelectedIndex", String(CmdEnumIndex(ObjHasOwnProp(this.Data, "Option") ? this.Data.Option : "默认", CmdEnumRunOptionNames(), 0)))
        this.ui.Update("StdInCon", "Text", ObjHasOwnProp(this.Data, "StdIn") ? UnescapeVarText(this.Data.StdIn) : "")

        ; Load encoding - default to UTF-8
        this._SetCombo("EncIn", ["UTF-8", "UTF-16", "CP0"], (ObjHasOwnProp(this.Data, "Encoding") && ObjHasOwnProp(this.Data.Encoding, "In")) ? this.Data.Encoding.In : "UTF-8")
        this._SetCombo("EncOut", ["UTF-8", "UTF-16", "CP0"], (ObjHasOwnProp(this.Data, "Encoding") && ObjHasOwnProp(this.Data.Encoding, "Out")) ? this.Data.Encoding.Out : "UTF-8")
        this._SetCombo("EncErr", ["UTF-8", "UTF-16", "CP0"], (ObjHasOwnProp(this.Data, "Encoding") && ObjHasOwnProp(this.Data.Encoding, "Err")) ? this.Data.Encoding.Err : "UTF-8")

        loop 3 {
            if (ObjHasOwnProp(this.Data, "SaveNameArr") && this.Data.SaveNameArr.Length >= A_Index)
                saveText := this.Data.SaveNameArr[A_Index]
            else
                saveText := (A_Index == 1 ? "ExitCode" : (A_Index == 2 ? "StdOut" : "StdErr"))
            this._SetCombo("SaveName" A_Index, GetGuiVarArr(0), saveText)
        }
        this.OnModeChange()
    }

    GetCommandStr() {
        textOnly := RTrim(this.Data.SerialStr, "0123456789")
        numbersOnly := SubStr(this.Data.SerialStr, StrLen(textOnly) + 1)
        commandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        commandStr := CorrectRemark(commandStr, this.ui.Query("RemarkCon"))
        return commandStr
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        Hotkey("!l", MacroAction, state ? "On" : "Off")
    }

    _Vis(name, vis) {
        if (IsObject(this.ui))
            this.ui.Update(name, "Visibility", vis ? "Visible" : "Collapsed")
    }

    OnModeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        val := CmdEnumFromIndex(this._SelIndex("RunModeCombo"), CmdEnumRunModeNames())
        showSN1 := val == "等待+返回值" || val == "等待+输入输出"
        showSN23 := val == "等待+输入输出"
        showStdIn := val == "不等待+输入" || val == "等待+输入输出"
        showEncIn := val == "不等待+输入" || val == "等待+输入输出"
        showEncOutErr := val == "等待+输入输出"
        this._Vis("SaveName1Row", showSN1)
        this._Vis("SaveName2Row", showSN23)
        this._Vis("SaveName3Row", showSN23)
        this._Vis("EncInRow", showEncIn)
        this._Vis("EncOutRow", showEncOutErr)
        this._Vis("EncErrRow", showEncOutErr)
        this._Vis("StdInRow", showStdIn)
    }

    OnClickFileSelectBtn(state := "", ctrl := "", event := "") {
        fileString := FileSelect("S1", "", GetLang("选择要运行的文件"))
        if (fileString == "")
            return
        this.ui.Update("PathTextCon", "Text", '"' fileString '"')
    }

    OpenStdInEditor(state := "", ctrl := "", event := "") {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed) {
            this.AddStdInEditorGui()
        }
        if (this.StdInEditGui.Query("StdInEditVarTypeCombo") == "")
            this.StdInEditGui.Update("StdInEditVarTypeCombo", "SelectedIndex", "0")
        this._FillStdInEditNameCombo()

        curText := IsObject(this.ui) ? this.ui.Query("StdInCon") : ""
        this.StdInEditGui.Update("StdInEditCon", "Text", curText)

        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        if (!XamlWin.Open(this.StdInEditGui, "", owner))
            this._stdInClosed := true
    }

    AddStdInEditorGui() {
        global MySoftData
        this._CloseStdInEditor()
        this._stdInClosed := false
        title := this.ParentTile GetLang("文本构造")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8").ClipToBounds("False")
        body.Rows("Auto", "6", "32", "48")

        ; 行0：内容框
        body.Add("TextBox").Grid_Row(0).Name("StdInEditCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2,3").FontSize("11")
            .Height("95").MinHeight("95")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 行2：变量数组 + 变量/数组 + 名称 + 追加名 + 追加值
        row1 := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        row1.Cols("88", "80", "8", "200", "8", "70", "8", "70")
        row1.Add("TextBlock").Grid_Column(0).Text(GetLang("变量数组：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        vt := row1.Add("ComboBox").Grid_Column(1).Name("StdInEditVarTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center").SelectedIndex("0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        row1.Add("ComboBox").Grid_Column(3).Name("StdInEditVariCombo").Width("200").Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left").IsEditable("True")
        row1.Add("Button").Grid_Column(5).Name("BtnStdInAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).VerticalAlignment("Center")
        row1.Add("Button").Grid_Column(7).Name("BtnStdInAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行3：确定
        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnStdInOk")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        this.StdInEditGui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        this.StdInEditGui.xaml := StrReplace(this.StdInEditGui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="580" SizeToContent="Height"')
        this.StdInEditGui.xaml := StrReplace(this.StdInEditGui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.StdInEditGui.xaml := StrReplace(this.StdInEditGui.xaml, '%resources%', '')

        ; === 事件 ===
        this.StdInEditGui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnStdInWindowClosing"))
        this.StdInEditGui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnStdInWindowLoad"))
        this.StdInEditGui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClickStdInEditorClose"))
        this.StdInEditGui.OnEvent("StdInEditVarTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnStdInEditVarTypeChange"))
        this.StdInEditGui.OnEvent("BtnStdInAddName", "Click", ObjBindMethod(this, "OnClickStdInEditorAddVarNameBtn"))
        this.StdInEditGui.OnEvent("BtnStdInAddValue", "Click", ObjBindMethod(this, "OnClickStdInEditorAddVarValueBtn"))
        this.StdInEditGui.OnEvent("StdInEditCon", "TextChanged", ObjBindMethod(this, "OnStdInEditChange"))
        this.StdInEditGui.OnEvent("StdInEditCon", "GotKeyboardFocus", (*) => this.ActiveEdit := "StdInEditCon")
        this.StdInEditGui.OnEvent("BtnStdInOk", "Click", ObjBindMethod(this, "OnClickStdInEditorClose"))
    }

    OnStdInWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.StdInEditGui)
    }

    OnStdInWindowClosing(state, ctrl, event) {
        this._stdInClosed := true
        this.StdInEditGui := ""
    }

    OnStdInEditChange(state := "", ctrl := "", event := "") {
        if (IsObject(this.StdInEditGui) && !this._stdInClosed && IsObject(this.ui)) {
            val := this.StdInEditGui.Query("StdInEditCon")
            this.ui.Update("StdInCon", "Text", val)
        }
    }

    _FillStdInEditNameCombo() {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed)
            return
        isVar := this.StdInEditGui.Query("StdInEditVarTypeCombo") == GetLang("变量")
        items := isVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
        cur := this.StdInEditGui.Query("StdInEditVariCombo")
        this.StdInEditGui.Update("StdInEditVariCombo", "ClearItems", "")
        for v in items {
            if (v != "")
                this.StdInEditGui.Update("StdInEditVariCombo", "AddItem", v)
        }
        found := false
        loop items.Length {
            if (items[A_Index] == cur) {
                this.StdInEditGui.Update("StdInEditVariCombo", "SelectedIndex", String(A_Index - 1))
                found := true
                break
            }
        }
        if (!found && items.Length > 0)
            this.StdInEditGui.Update("StdInEditVariCombo", "SelectedIndex", "0")
    }

    OnStdInEditVarTypeChange(state := "", ctrl := "", event := "") {
        this._FillStdInEditNameCombo()
    }

    OnClickStdInEditorAddVarNameBtn(state := "", ctrl := "", event := "") {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed)
            return
        varName := this.StdInEditGui.Query("StdInEditVariCombo")
        if (varName != "") {
            this.StdInEditGui.Update("StdInEditCon", "InsertText", varName)
            this.OnStdInEditChange()
        }
    }

    OnClickStdInEditorAddVarValueBtn(state := "", ctrl := "", event := "") {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed)
            return
        varName := this.StdInEditGui.Query("StdInEditVariCombo")
        if (varName != "") {
            arrMark := this.StdInEditGui.Query("StdInEditVarTypeCombo") == GetLang("变量") ? "" : "ε"
            this.StdInEditGui.Update("StdInEditCon", "InsertText", "{" arrMark varName "}")
            this.OnStdInEditChange()
        }
    }

    OnClickStdInEditorClose(state := "", ctrl := "", event := "") {
        this._CloseStdInEditor()
    }

    OnClickSureBtn(state, ctrl, event) {
        ; ----- 编码提示（仅当模式为“等待+输入输出”时）-----
        if (CmdEnumFromIndex(this._SelIndex("RunModeCombo"), CmdEnumRunModeNames()) == "不等待+输入") {
            for enc in [this.ui.Query("EncIn"), this.ui.Query("EncOut")] {
                if (enc != "UTF-8" && enc != "UTF-16" && (SubStr(enc, 1, 2) != "CP")) {
                    RmtDialog.Info(Format("不支持{}编码", enc))
                    return
                }
            }
        }

        if (!this.CheckIfValid())
            return
        this.SaveRunData()
        this.ToggleFunc(false)
        action := this.SureBtnAction
        action(this.GetCommandStr())

        this._CloseWindow()
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    CheckIfValid() {
        if (this.ui.Query("PathTextCon") == "") {
            RmtDialog.Info(GetLang("目标不能为空！"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveRunData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveRunData() {
        this.Data.Target := SmartEscapeVarText(GetLangStr(this.ui.Query("PathTextCon"), 2))
        this.Data.Mode := CmdEnumFromIndex(this._SelIndex("RunModeCombo"), CmdEnumRunModeNames())
        this.Data.Option := CmdEnumFromIndex(this._SelIndex("OptionCombo"), CmdEnumRunOptionNames())

        if (this.Data.Mode == "不等待") {
            if (ObjHasOwnProp(this.Data, "StdIn"))
                this.Data.DeleteProp("StdIn")
            if (ObjHasOwnProp(this.Data, "SaveNameArr"))
                this.Data.DeleteProp("SaveNameArr")
            if (ObjHasOwnProp(this.Data, "Encoding"))
                this.Data.DeleteProp("Encoding")
        } else if (this.Data.Mode == "等待+返回值") {
            if (ObjHasOwnProp(this.Data, "StdIn"))
                this.Data.DeleteProp("StdIn")
            this.Data.SaveNameArr := [this.ui.Query("SaveName1")]
            if (ObjHasOwnProp(this.Data, "Encoding"))
                this.Data.DeleteProp("Encoding")
        } else if (this.Data.Mode == "不等待+输入") {
            this.Data.StdIn := SmartEscapeVarText(this.ui.Query("StdInCon"))
            if (ObjHasOwnProp(this.Data, "SaveNameArr"))
                this.Data.DeleteProp("SaveNameArr")
            enc := {}
            enc.In := this.ui.Query("EncIn")
            this.Data.Encoding := enc
        } else if (this.Data.Mode == "等待+输入输出") {
            this.Data.StdIn := SmartEscapeVarText(this.ui.Query("StdInCon"))
            this.Data.SaveNameArr := [this.ui.Query("SaveName1"), this.ui.Query("SaveName2"), this.ui.Query("SaveName3")]
            enc := {}
            enc.In := this.ui.Query("EncIn")
            enc.Out := this.ui.Query("EncOut")
            enc.Err := this.ui.Query("EncErr")
            this.Data.Encoding := enc
        }
        SaveMacroCMDData(this.Data)
    }

    OnClickAddVarNameBtn(state := "", ctrl := "", event := "") {
        target := this._ActiveEditTarget()
        this.InsertIntoEdit(target, this.ui.Query("VariCombo"))
    }

    OnClickAddVarValueBtn(state := "", ctrl := "", event := "") {
        if (this.ui.Query("VariCombo") != "") {
            target := this._ActiveEditTarget()
            this.InsertIntoEdit(target, "{" this.ui.Query("VariCombo") "}")
        }
    }

    _ActiveEditTarget() {
        ; ActiveEdit 是控件名（PathTextCon / StdInCon / StdInEditCon），只读/不可见时回退 PathTextCon
        name := this.ActiveEdit
        if (name == "StdInEditCon")
            return "StdInEditCon"
        if (name == "StdInCon" && IsObject(this.ui) && this.ui.Query("StdInCon>Visibility") == "Visible")
            return "StdInCon"
        return "PathTextCon"
    }

    InsertIntoEdit(target, text) {
        if (target == "StdInEditCon") {
            if (IsObject(this.StdInEditGui) && !this._stdInClosed) {
                this.StdInEditGui.Update("StdInEditCon", "InsertText", text)
                this.OnStdInEditChange()
            }
            return
        }
        if (IsObject(this.ui))
            this.ui.Update(target, "InsertText", text)
    }
}
