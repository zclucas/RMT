#Requires AutoHotkey v2.0

; =====================================================================
; 后台鼠标编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class BGMouseGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.RefreshInfoAction := () => this.RefreshInfo()
        this.Data := ""
        this.SerialStr := ""
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
        title := this.ParentTile GetLang("后台鼠标编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏（F1 定位钮与移动指令同款）===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        ; 列：左标签90 / 左输入120 / 右标签110 / 右输入120；右列 label 再右移 15
        body := main.Add("Grid").Grid_Row(1).Margin("10,8,10,18")
        body.Rows("30", "34", "34", "34", "36", "*")
        body.Cols("90", "120", "110", "120")
        rightLabelMargin := "20,0,0,0"

        ; 行0：当前窗口坐标 + 备注（备注 label 与操作类型左对齐；输入框右缘与操作类型下拉对齐）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Grid_ColumnSpan(2).Name("CurPosCon")
            .Text(GetLang("当前窗口坐标:0,0")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkHost := body.Add("Grid").Grid_Row(0).Grid_Column(2).Grid_ColumnSpan(2)
        remarkHost.Cols("Auto", "*")
        remarkHost.Add("TextBlock").Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
            .Margin(rightLabelMargin).Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkHost.Add("TextBox").Grid_Column(1).Name("RemarkCon").Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("#FFFFFF")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：窗口信息
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("窗口绑定:")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12").ToolTip(this._BGHelpText())
        body.Add("TextBox").Grid_Row(1).Grid_Column(1).Grid_ColumnSpan(2).Name("TargetTitleCon").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("#FFFFFF")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("Button").Grid_Row(1).Grid_Column(3).Name("BtnEdit").Content(GetLang("编辑")).Height(26).MinHeight(26)
            .HorizontalAlignment("Left").Margin("6,0,0,0").Cursor("Hand")

        ; 行2：鼠标按键 + 操作类型
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("鼠标按键:")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        mt := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("MouseTypeCombo").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for m in GetLangArr(["左键", "中键", "右键", "滚轮"])
            mt.Add("ComboBoxItem").Content(m)
        body.Add("TextBlock").Grid_Row(2).Grid_Column(2).Name("OperateTipCon").Text(GetLang("操作类型:")).VerticalAlignment("Center")
            .HorizontalAlignment("Left").Margin(rightLabelMargin).Foreground("{DynamicResource TextMain}").FontSize("12")
        ot := body.Add("ComboBox").Grid_Row(2).Grid_Column(3).Name("OperateTypeCombo").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for o in GetLangArr(["点击", "双击", "按下", "松开"])
            ot.Add("ComboBoxItem").Content(o)

        ; 行3：窗口坐标 X/Y
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("窗口坐标X:")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(1).Name("PosVarX").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(3).Grid_Column(2).Text(GetLang("窗口坐标Y:")).VerticalAlignment("Center")
            .HorizontalAlignment("Left").Margin(rightLabelMargin).Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(3).Name("PosVarY").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行4：点击时间 / 垂直+水平滚动
        clickRow := body.Add("Grid").Grid_Row(4).Grid_ColumnSpan(4).Name("ClickTimeRow")
        clickRow.Cols("90", "120", "110", "120")
        clickRow.Add("TextBlock").Grid_Column(0).Text(GetLang("点击时间:")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        clickRow.Add("TextBox").Grid_Column(1).Name("ClickTimeCon").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("#FFFFFF")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        scrollRow := body.Add("Grid").Grid_Row(4).Grid_ColumnSpan(4).Name("ScrollRow").Visibility("Collapsed")
        scrollRow.Cols("90", "120", "110", "120")
        scrollRow.Add("TextBlock").Grid_Column(0).Text(GetLang("垂直滚动:")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        scrollRow.Add("TextBox").Grid_Column(1).Name("ScrollV").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("#FFFFFF")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        scrollRow.Add("TextBlock").Grid_Column(2).Text(GetLang("水平滚动:")).VerticalAlignment("Center")
            .HorizontalAlignment("Left").Margin(rightLabelMargin).Foreground("{DynamicResource TextMain}").FontSize("12")
        scrollRow.Add("TextBox").Grid_Column(3).Name("ScrollH").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("#FFFFFF")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行5：确定（下移 5px；底部留白使整体高度 +8）
        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(4).Orientation("Horizontal")
            .HorizontalAlignment("Center").VerticalAlignment("Top").Margin("0,5,0,0")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="480" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/21-后台鼠标", ObjBindMethod(this, "TriggerMacro"), "!l", "", ObjBindMethod(this, "OnF1"))
        try this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1:确定信息"))
        this.ui.OnEvent("MouseTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("OperateTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("BtnEdit", "Click", ObjBindMethod(this, "OnClickEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        try this.ToggleFunc(false)
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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        try this.ToggleFunc(false)
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

    _MouseValue() {
        v := IsObject(this.ui) ? this.ui.Query("MouseTypeCombo>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumMouseBtnNames())
    }
    _OperValue() {
        v := IsObject(this.ui) ? this.ui.Query("OperateTypeCombo>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumBgOperNames())
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("后台鼠标")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        this.ui.Update("TargetTitleCon", "Text", this.Data.TargetTitle != "" ? this.Data.TargetTitle : "")
        this.ui.Update("OperateTypeCombo", "SelectedIndex", String(CmdEnumIndex(this.Data.OperateType, CmdEnumBgOperNames())))
        this.ui.Update("MouseTypeCombo", "SelectedIndex", String(CmdEnumIndex(this.Data.MouseType, CmdEnumMouseBtnNames())))
        this.ui.Update("ClickTimeCon", "Text", this.Data.ClickTime)
        this._SetCombo("PosVarX", GetGuiVarArr(), GetLang(this.Data.PosVarX))
        this._SetCombo("PosVarY", GetGuiVarArr(), GetLang(this.Data.PosVarY))
        this.ui.Update("ScrollV", "Text", this.Data.ScrollV)
        this.ui.Update("ScrollH", "Text", this.Data.ScrollH)
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        isScroll := this._MouseValue() == "滚轮"
        this._Vis("OperateTipCon", !isScroll)
        this._Vis("OperateTypeCombo", !isScroll)
        this._Vis("ScrollRow", isScroll)
        isClickOrDClick := this._OperValue() == "点击" || this._OperValue() == "双击"
        showClickTime := !isScroll && isClickOrDClick
        this._Vis("ClickTimeRow", showClickTime)
    }

    _Vis(name, show) {
        if (IsObject(this.ui))
            this.ui.Update(name, "Visibility", show ? "Visible" : "Collapsed")
    }

    ToggleFunc(state) {
        if (state) {
            try SetTimer this.RefreshInfoAction, 100
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
            try Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            try SetTimer this.RefreshInfoAction, 0
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
            try Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    OnF1(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        CoordMode("Mouse", "Window")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }
            this.ui.Update("TargetTitleCon", "Text", title "⎖" className "⎖" process)
        }
        PosArr := GetCurWinPos()
        this.ui.Update("PosVarX", "Text", PosArr[1])
        this.ui.Update("PosVarY", "Text", PosArr[2])
    }

    RefreshInfo() {
        if (!IsObject(this.ui))
            return
        PosArr := GetCurWinPos()
        try this.ui.Update("CurPosCon", "Text", Format("{}{},{}", GetLang("当前窗口坐标:"), PosArr[1], PosArr[2]))
    }

    OnClickEditBtn(state := "", ctrl := "", event := "") {
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "TargetTitleCon"))
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveBGMouseData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this.ToggleFunc(false)
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        if (this.ui.Query("TargetTitleCon") == "") {
            RmtDialog.Info(GetLang("窗口绑定不能为空"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!IsNumber(this.ui.Query("PosVarX")) || !IsNumber(this.ui.Query("PosVarY"))) {
            RmtDialog.Info(GetLang("坐标中存在变量，无法在编辑器模式下执行指令"))
            return
        }
        this.SaveBGMouseData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    SaveBGMouseData() {
        this.Data.TargetTitle := this.ui.Query("TargetTitleCon")
        this.Data.OperateType := this._OperValue()
        this.Data.MouseType := this._MouseValue()
        this.Data.PosVarX := GetLangKey(this.ui.Query("PosVarX"))
        this.Data.PosVarY := GetLangKey(this.ui.Query("PosVarY"))
        this.Data.ClickTime := this.ui.Query("ClickTimeCon")
        this.Data.ScrollV := this.ui.Query("ScrollV")
        this.Data.ScrollH := this.ui.Query("ScrollH")
        SaveMacroCMDData(this.Data)
    }

    _BGHelpText() {
        str1 := GetLang("该指令需要管理员身份运行软件")
        str2 := GetLang("该指令部分窗口可能无效")
        str3 := GetLang("tip1:可通过对浏览器界面配置检测指令的正确性")
        str4 := GetLang("tip2:若浏览器界面正常，实际窗口无效，那就是该窗口不支持后台功能")
        return Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
    }
}
