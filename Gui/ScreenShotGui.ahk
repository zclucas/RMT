#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk
#Include WinRuleGui.ahk

; =====================================================================
; 抓图编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class ScreenShotGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this._syncing := false
        this.PosAction := () => this.RefreshMouseInfo()
        this.F1Action := (x1, y1, x2, y2) => this.OnF1SetAreaAction(x1, y1, x2, y2)
        this.Data := ""
        this.SerialStr := ""
        this.MacroGui := ""
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._syncing := true
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
        title := this.ParentTile GetLang("抓图编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,0,16,16")
        body.Rows("36", "36", "36", "36", "36", "36", "48")
        body.Cols("108", "*", "16", "108", "*")

        ; 行0：备注（白底，内边距与下拉框一致）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：抓图类型 + 屏幕/窗口坐标（整体跟在类型后面）
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("抓图类型：")).VerticalAlignment("Center")
        st := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("ScreenShotTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        st.Add("ComboBoxItem").Content(GetLang("屏幕抓图")).Tag("1")
        st.Add("ComboBoxItem").Content(GetLang("窗口抓图")).Tag("2")
        posGroup := body.Add("StackPanel").Grid_Row(1).Grid_Column(3).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        screenPos := posGroup.Add("StackPanel").Name("ScreenPosGroup").Orientation("Horizontal").VerticalAlignment("Center")
        screenPos.Add("TextBlock").Text(GetLang("屏幕坐标：")).VerticalAlignment("Center")
        screenPos.Add("TextBlock").Name("MousePosCon").Text("0,0").VerticalAlignment("Center")
        winPos := posGroup.Add("StackPanel").Name("WinPosGroup").Orientation("Horizontal").VerticalAlignment("Center").Visibility("Collapsed")
        winPos.Add("TextBlock").Text(GetLang("窗口坐标：")).VerticalAlignment("Center")
        winPos.Add("TextBlock").Name("MouseWinPosCon").Text("0,0").VerticalAlignment("Center")

        ; 行2：窗口信息（屏幕抓图时 Hidden 占位，避免下面行上移）
        winRow := body.Add("Grid").Name("WinInfoRow").Grid_Row(2).Grid_ColumnSpan(5).Visibility("Hidden")
        winRow.Cols("108", "*", "8", "70")
        winRow.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口绑定:")).VerticalAlignment("Center")
        winRow.Add("TextBox").Grid_Column(1).Name("WinInfoCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        winRow.Add("Button").Grid_Column(3).Name("BtnWinEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行3-4：起始/终止坐标
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("起始坐标X：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(1).Name("StartPosX").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(3).Grid_Column(3).Text(GetLang("起始坐标Y：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(4).Name("StartPosY").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(4).Grid_Column(0).Text(GetLang("终止坐标X：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(4).Grid_Column(1).Name("EndPosX").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(4).Grid_Column(3).Text(GetLang("终止坐标Y：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(4).Grid_Column(4).Name("EndPosY").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行5：固定名称（终止坐标X下）+ 结果变量（终止坐标Y下）
        body.Add("CheckBox").Grid_Row(5).Grid_Column(0).Name("NameType").Content(GetLang("固定名称：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(5).Grid_Column(1).Name("FixedNameCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("CheckBox").Grid_Row(5).Grid_Column(3).Name("ResultToggle").Content(GetLang("结果变量：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(5).Grid_Column(4).Name("ResultSaveNameCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行6：确定
        btnRow := body.Add("StackPanel").Grid_Row(6).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/26-抓图", ObjBindMethod(this, "TriggerMacro"), "!l", "", ObjBindMethod(this, "OnF1"))
        try this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：框选范围"))
        this.ui.OnEvent("ScreenShotTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("NameType", "Click", ObjBindMethod(this, "OnChangeNameType"))
        this.ui.OnEvent("ResultToggle", "Click", ObjBindMethod(this, "OnChangeResultToggle"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._syncing := false
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

    _ShotType() {
        v := IsObject(this.ui) ? this.ui.Query("ScreenShotTypeCombo>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumShotNames())
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("抓图")
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        if (!this.CheckIfDataValid())
            return

        this.ui.Update("ScreenShotTypeCombo", "SelectedIndex", String(CmdEnumIndex(this.Data.ScreenShotType, CmdEnumShotNames())))
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)
        this.ui.Update("NameType", "IsChecked", (this.Data.NameType == "固定名称" || this.Data.NameType == 1 || this.Data.NameType == "1") ? "True" : "False")
        this.ui.Update("FixedNameCon", "Text", this.Data.FixedName)
        this.ui.Update("ResultToggle", "IsChecked", this.Data.ResultToggle ? "True" : "False")
        this._SetCombo("ResultSaveNameCombo", this.DLVariableArr, this.Data.ResultSaveName)

        this.OnChangeType()
        this.OnChangeNameType()
        this.OnChangeResultToggle()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    OnClickWinEditBtn(state := "", ctrl := "", event := "") {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    CheckIfDataValid() {
        return true
    }

    CheckIfValid() {
        isWin := this._ShotType() == "窗口抓图"
        if (IsNumber(this.ui.Query("StartPosX")) && IsNumber(this.ui.Query("StartPosY")) && IsNumber(this.ui.Query("EndPosX")) && IsNumber(this.ui.Query("EndPosY"))) {
            if (Number(this.ui.Query("StartPosX")) > Number(this.ui.Query("EndPosX")) || Number(this.ui.Query("StartPosY")) > Number(this.ui.Query("EndPosY"))) {
                RmtDialog.Info(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }
        if (isWin && this.ui.Query("WinInfoCon") == "") {
            RmtDialog.Info(GetLang("窗口绑定不能为空"))
            return false
        }
        if (this.ui.Query("NameType") == "True" && this.ui.Query("FixedNameCon") == "") {
            RmtDialog.Info(GetLang("固定名称不能为空"))
            return false
        }
        if (this.ui.Query("ResultToggle") == "True") {
            if (!CheckVarNameIfValid(this.ui.Query("ResultSaveNameCombo")))
                return false
        }
        return true
    }

    ToggleFunc(state) {
        if (state) {
            try SetTimer this.PosAction, 100
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
            try Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            try SetTimer this.PosAction, 0
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
            try Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    RefreshMouseInfo() {
        if (!IsObject(this.ui))
            return
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            this.ui.Update("MousePosCon", "Text", Format("{},{}", mouseX, mouseY))
            PosArr := GetCurWinPos()
            this.ui.Update("MouseWinPosCon", "Text", Format("{},{}", PosArr[1], PosArr[2]))
        }
    }

    OnChangeType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        isWin := this._ShotType() == "窗口抓图"
        for name in ["StartPosX", "StartPosY", "EndPosX", "EndPosY"] {
            items := isWin ? GetGuiVarReferences() : GetGuiVarReferences(StrLower(SubStr(name, -1)))
            value := this._syncing ? TranslateBuiltinVarReferences(this.Data.%name%, true) : this.ui.Query(name)
            this._SetCombo(name, items, value)
        }
        this._ComboPush("WinInfoRow", "Visibility", isWin ? "Visible" : "Hidden")
        this._ComboPush("ScreenPosGroup", "Visibility", isWin ? "Collapsed" : "Visible")
        this._ComboPush("WinPosGroup", "Visibility", isWin ? "Visible" : "Collapsed")
    }

    OnChangeNameType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        this._ComboPush("FixedNameCon", "IsEnabled", (this.ui.Query("NameType") == "True") ? "True" : "False")
    }

    OnChangeResultToggle(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        isSave := this.ui.Query("ResultToggle") == "True"
        this._ComboPush("ResultSaveNameCombo", "IsEnabled", isSave ? "True" : "False")
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnF1(state := "", ctrl := "", event := "") {
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        if (!IsObject(this.ui))
            return
        curType := this._ShotType()
        isWin := curType == "窗口抓图"
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]
        this.ui.Update("StartPosX", "Text", Point1[1])
        this.ui.Update("StartPosY", "Text", Point1[2])
        this.ui.Update("EndPosX", "Text", Point2[1])
        this.ui.Update("EndPosY", "Text", Point2[2])
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this.ToggleFunc(false)
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    SaveData() {
        data := this.Data
        data.ScreenShotType := this._ShotType()
        data.WinInfo := this.ui.Query("WinInfoCon")
        data.StartPosX := TranslateBuiltinVarReferences(this.ui.Query("StartPosX"))
        data.StartPosY := TranslateBuiltinVarReferences(this.ui.Query("StartPosY"))
        data.EndPosX := TranslateBuiltinVarReferences(this.ui.Query("EndPosX"))
        data.EndPosY := TranslateBuiltinVarReferences(this.ui.Query("EndPosY"))
        data.NameType := this.ui.Query("NameType") == "True" ? "固定名称" : "默认"
        data.FixedName := this.ui.Query("FixedNameCon")
        data.ResultToggle := this.ui.Query("ResultToggle") == "True" ? 1 : 0
        data.ResultSaveName := GetVarName(this.ui.Query("ResultSaveNameCombo"))
        if (data.ResultToggle)
            MySoftData.GlobalVariMap[data.ResultSaveName] := true
        SaveMacroCMDData(data)
    }
}
