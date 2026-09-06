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

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

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
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "26", "40", "22", "34", "34", "36", "36", "34", "*")
        body.Cols("90", "120", "90", "120")

        ; 行0：快捷方式 + 执行指令 + 备注
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("6,0,0,0")
        row0.Add("Button").Name("BtnHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("12,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：F1
        body.Add("TextBlock").Grid_Row(1).Grid_ColumnSpan(4).Text(GetLang("F1:确定信息")).VerticalAlignment("Center")

        ; 行2-3：当前信息
        body.Add("TextBlock").Grid_Row(2).Grid_ColumnSpan(4).Name("CurTitleCon").Text(GetLang("当前窗口信息:RMT")).VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(4).Name("CurPosCon").Text(GetLang("当前窗口坐标:0,0")).VerticalAlignment("Center")

        ; 行4：窗口信息
        row4 := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row4.Add("TextBlock").Text(GetLang("窗口信息:")).VerticalAlignment("Center").Width(70)
        row4.Add("TextBox").Name("TargetTitleCon").Width(240).Height(24).MinHeight(24)
        row4.Add("Button").Name("BtnEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行5：鼠标按键 + 操作类型
        body.Add("TextBlock").Grid_Row(5).Grid_Column(0).Text(GetLang("鼠标按键:")).VerticalAlignment("Center")
        mt := body.Add("ComboBox").Grid_Row(5).Grid_Column(1).Name("MouseTypeCombo").Height(26).MinHeight(26)
        for m in GetLangArr(["左键", "中键", "右键", "滚轮"])
            mt.Add("ComboBoxItem").Content(m)
        operRow := body.Add("StackPanel").Name("OperateRow").Grid_Row(5).Grid_Column(2).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        operRow.Add("TextBlock").Text(GetLang("操作类型:")).VerticalAlignment("Center")
        ot := operRow.Add("ComboBox").Name("OperateTypeCombo").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0")
        for o in GetLangArr(["点击", "双击", "按下", "松开"])
            ot.Add("ComboBoxItem").Content(o)

        ; 行6：坐标X/Y
        body.Add("TextBlock").Grid_Row(6).Grid_Column(0).Text(GetLang("窗口坐标X:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(6).Grid_Column(1).Name("PosVarX").Height(26).MinHeight(26).IsEditable("True")
        body.Add("TextBlock").Grid_Row(6).Grid_Column(2).Text(GetLang("窗口坐标Y:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(6).Grid_Column(3).Name("PosVarY").Height(26).MinHeight(26).IsEditable("True")

        ; 行7：滚动
        scrollRow := body.Add("StackPanel").Grid_Row(7).Grid_ColumnSpan(4).Name("ScrollRow").Orientation("Horizontal").VerticalAlignment("Center")
        scrollRow.Add("TextBlock").Text(GetLang("垂直滚动:")).VerticalAlignment("Center").Width(70)
        scrollRow.Add("TextBox").Name("ScrollV").Width(90).Height(24).MinHeight(24)
        scrollRow.Add("TextBlock").Text(GetLang("水平滚动:")).VerticalAlignment("Center").Margin("14,0,0,0")
        scrollRow.Add("TextBox").Name("ScrollH").Width(90).Height(24).MinHeight(24)

        ; 行8：点击时间
        clickRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(4).Name("ClickTimeRow").Orientation("Horizontal").VerticalAlignment("Center")
        clickRow.Add("TextBlock").Text(GetLang("点击时间:")).VerticalAlignment("Center").Width(70)
        clickRow.Add("TextBox").Name("ClickTimeCon").Width(70).Height(24).MinHeight(24)

        ; 行9：确定
        btnRow := body.Add("StackPanel").Grid_Row(9).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="350" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickHelpBtn"))
        this.ui.OnEvent("MouseTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("OperateTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("BtnEdit", "Click", ObjBindMethod(this, "OnClickEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        return IsNumber(v) ? Integer(v) + 1 : 1
    }
    _OperValue() {
        v := IsObject(this.ui) ? this.ui.Query("OperateTypeCombo>SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) + 1 : 1
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("后台鼠标")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        this.ui.Update("TargetTitleCon", "Text", this.Data.TargetTitle != "" ? this.Data.TargetTitle : "")
        this.ui.Update("OperateTypeCombo", "SelectedIndex", String(this.Data.OperateType - 1))
        this.ui.Update("MouseTypeCombo", "SelectedIndex", String(this.Data.MouseType - 1))
        this.ui.Update("ClickTimeCon", "Text", this.Data.ClickTime)
        this._SetCombo("PosVarX", GetGuiVarArr(0), GetLang(this.Data.PosVarX))
        this._SetCombo("PosVarY", GetGuiVarArr(0), GetLang(this.Data.PosVarY))
        this.ui.Update("ScrollV", "Text", this.Data.ScrollV)
        this.ui.Update("ScrollH", "Text", this.Data.ScrollH)
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        isScroll := this._MouseValue() == 4
        this._Vis("OperateRow", !isScroll)
        this._Vis("ScrollRow", isScroll)
        isClickOrDClick := this._OperValue() == 1 || this._OperValue() == 2
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

    OnF1() {
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
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &oriId
        PosArr := GetCurWinPos()
        try {
            this.ui.Update("CurPosCon", "Text", Format("{}{},{}", GetLang("当前窗口坐标:"), PosArr[1], PosArr[2]))
            title := WinGetTitle(oriId)
            className := WinGetClass(oriId)
            try {
                WinPID := WinGetPID("ahk_id " oriId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }
            this.ui.Update("CurTitleCon", "Text", Format("{}{}⎖{}⎖{}", GetLang("当前窗口信息:"), title, className, process))
        }
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
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!IsNumber(this.ui.Query("PosVarX")) || !IsNumber(this.ui.Query("PosVarY"))) {
            MsgBox(GetLang("坐标中存在变量，无法在编辑器模式下执行指令"))
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

    OnClickHelpBtn(state := "", ctrl := "", event := "") {
        str1 := GetLang("该指令需要管理员身份运行软件")
        str2 := GetLang("该指令部分窗口可能无效")
        str3 := GetLang("tip1:可通过对浏览器界面配置检测指令的正确性")
        str4 := GetLang("tip2:若浏览器界面正常，实际窗口无效，那就是该窗口不支持后台功能")
        str := Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
        MsgBox(str, GetLang("后台操作说明"))
    }
}
