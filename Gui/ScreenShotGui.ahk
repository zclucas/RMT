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
        this.WindowBindingContext := ""
        this.AreaPreview := ScreenAreaPreview()
        this.PreviewShowing := false
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
        CmdEditorForm.NormalizeComboItem(&propertyName, &value)
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

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(CmdEditorForm.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,0,16,16")
        body.Rows("36", "36", "36", "Auto", "0", "36", "48")
        body.Cols(CmdEditorForm.PairColumns()*)

        ; 行0：坐标信息 | 备注。
        posGroup := body.Add("Grid").Grid_Row(0).Grid_Column(0).Grid_ColumnSpan(2)
        screenPos := posGroup.Add("Grid").Name("ScreenPosGroup")
        screenPos.Cols(CmdEditorForm.LabelWidth(), "*")
        screenPos.Add("TextBlock").Grid_Column(0).Text(GetLang("屏幕坐标：")).VerticalAlignment("Center")
        screenPos.Add("TextBlock").Grid_Column(1).Name("MousePosCon").Text("0,0").VerticalAlignment("Center")
        winPos := posGroup.Add("Grid").Name("WinPosGroup").Visibility("Collapsed")
        winPos.Cols(CmdEditorForm.LabelWidth(), "*")
        winPos.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口坐标：")).VerticalAlignment("Center")
        winPos.Add("TextBlock").Grid_Column(1).Name("MouseWinPosCon").Text("0,0").VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(0).Grid_Column(3).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .Style("{StaticResource RmtSingleLineTextBox}")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：截图类型 | 保存到剪切板。
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Name("ShotTypeLabel").Text(GetLang("抓图类型：")).VerticalAlignment("Center")
        st := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("ScreenShotTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        st.Add("ComboBoxItem").Content(GetLang("屏幕抓图")).Tag("1")
        st.Add("ComboBoxItem").Content(GetLang("窗口抓图")).Tag("2")
        st.Add("ComboBoxItem").Content(GetLang("自定义截图")).Tag("3")
        body.Add("CheckBox").Grid_Row(1).Grid_Column(3).Grid_ColumnSpan(2).Name("ToClipboardCon")
            .Content(GetLang("截图保存到剪切板")).VerticalAlignment("Center")

        ; 行2：窗口信息（屏幕抓图时 Hidden 占位，避免下面行上移）
        winRow := body.Add("Grid").Name("WinInfoRow").Grid_Row(2).Grid_ColumnSpan(5).Visibility("Hidden")
        winRow.Cols(CmdEditorForm.LabelWidth(), "*", 8, 70)
        winRow.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口绑定:")).ToolTip(GetLang("指定这条指令要操作的窗口。")).VerticalAlignment("Center")
        CmdEditorForm.WindowBindingCombo(winRow, "WinInfoCon").Grid_Column(1).MaxHeight(26)
        winRow.Add("Button").Grid_Column(3).Name("BtnWinEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 与搜索 Pro 一样：起始/终止各一行，同行填写 X、Y，标签可切换范围预览。
        area := body.Add("Grid").Name("ShotAreaRow").Grid_Row(3).Grid_ColumnSpan(5)
        area.Rows("32", "32")
        area.Cols(CmdEditorForm.LabelWidth(), "120", "8", "120", "*")
        areaBtn := area.Add("Button").Name("BtnPreviewArea").Grid_RowSpan(2).Grid_Column(0)
            .HorizontalAlignment("Left").VerticalAlignment("Stretch").Cursor("Hand").Focusable("False")
            .Tag("0").ToolTip(GetLang("截图范围"))
            .HorizontalContentAlignment("Left").VerticalContentAlignment("Stretch")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        areaBtn.InjectResources(ScreenAreaPreview.ButtonStyle())
        labels := areaBtn.Add("Grid").VerticalAlignment("Stretch")
        labels.Rows("*", "*")
        labels.Add("TextBlock").Grid_Row(0).Text(GetLang("起始坐标：")).VerticalAlignment("Center").IsHitTestVisible("False")
        labels.Add("TextBlock").Grid_Row(1).Text(GetLang("终止坐标：")).VerticalAlignment("Center").IsHitTestVisible("False")
        for name, pos in Map("StartPosX", [0, 1], "StartPosY", [0, 3], "EndPosX", [1, 1], "EndPosY", [1, 3])
            area.Add("ComboBox").Grid_Row(pos[1]).Grid_Column(pos[2]).Name(name).Height(28).MinHeight(28)
                .IsEditable("True").VerticalAlignment("Center").VerticalContentAlignment("Center")

        ; 命名方式与结果变量。
        body.Add("TextBlock").Grid_Row(5).Grid_Column(0).Text(GetLang("命名方式：")).VerticalAlignment("Center")
        naming := body.Add("ComboBox").Grid_Row(5).Grid_Column(1).Name("NameTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for name in ["固定", "序号自增"]
            naming.Add("ComboBoxItem").Content(GetLang(name))
        body.Add("TextBlock").Grid_Row(5).Grid_Column(3).Name("ResultLabel").Text(GetLang("结果变量："))
            .ToolTip(GetLang("截图保存路径，留空时只保存截图，不写入变量。")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(5).Grid_Column(4).Name("ResultSaveNameCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行6：确定
        btnRow := body.Add("StackPanel").Grid_Row(6).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="' CmdEditorForm.Width '" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/26-抓图", ObjBindMethod(this, "TriggerMacro"), "!l", "", ObjBindMethod(this, "OnF1"))
        this.ui.BatchUpdate(CmdEditorF1Updates("area"))
        this.ui.OnEvent("ScreenShotTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("BtnPreviewArea", "Click", ObjBindMethod(this, "OnClickPreviewArea"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._syncing := false
    }

    OnWindowClosing(state, ctrl, event) {
        this.PreviewShowing := false
        this.AreaPreview.Hide()
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
        this.PreviewShowing := false
        this.AreaPreview.Hide()
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
        text := GetVariableComboText(items, text)
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : AllocateCommandSerial("抓图")
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        if (!this.CheckIfDataValid())
            return

        this.ui.Update("ScreenShotTypeCombo", "SelectedIndex", String(CmdEnumIndex(this.Data.ScreenShotType, CmdEnumShotNames())))
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)
        this.ui.Update("ToClipboardCon", "IsChecked", this.Data.ToClipboard ? "True" : "False")
        this.ui.Update("NameTypeCombo", "SelectedIndex", CmdEnumNameType(this.Data.NameType) == "固定名称" ? "0" : "1")
        this._SetCombo("ResultSaveNameCombo", this.DLVariableArr, this.Data.ResultSaveName)

        this.OnChangeType()
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
        if (this._ShotType() != "自定义截图" && IsNumber(this.ui.Query("StartPosX")) && IsNumber(this.ui.Query("StartPosY")) && IsNumber(this.ui.Query("EndPosX")) && IsNumber(this.ui.Query("EndPosY"))) {
            if (Number(this.ui.Query("StartPosX")) > Number(this.ui.Query("EndPosX")) || Number(this.ui.Query("StartPosY")) > Number(this.ui.Query("EndPosY"))) {
                RmtDialog.Info(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }
        if (isWin && this.ui.Query("WinInfoCon") == "") {
            RmtDialog.Info(GetLang("窗口绑定不能为空"))
            return false
        }
        resultName := Trim(this.ui.Query("ResultSaveNameCombo"))
        if (resultName != "" && !CheckVarNameIfValid(resultName))
            return false
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
            PosArr := GetMouseWindowClientPosition()
            this.ui.Update("MouseWinPosCon", "Text", Format("{},{}", PosArr[1], PosArr[2]))
            this.RefreshPreviewArea()
        }
    }

    OnChangeType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        isWin := this._ShotType() == "窗口抓图"
        isCustom := this._ShotType() == "自定义截图"
        this._ComboPush("ShotTypeLabel", "ToolTip", isCustom ? GetLang("该类型只进入截图状态，需要运行时手动框选范围。") : "")
        this._ComboPush("ShotAreaRow", "Visibility", isCustom ? "Collapsed" : "Visible")
        for name in ["StartPosX", "StartPosY", "EndPosX", "EndPosY"] {
            items := isWin ? GetGuiVarReferences() : GetGuiVarReferences(StrLower(SubStr(name, -1)))
            value := this._syncing ? TranslateBuiltinVarReferences(this.Data.%name%, true) : this.ui.Query(name)
            this._SetCombo(name, items, value)
        }
        this._ComboPush("WinInfoRow", "Visibility", isWin ? "Visible" : "Hidden")
        this._ComboPush("ScreenPosGroup", "Visibility", isWin ? "Collapsed" : "Visible")
        this._ComboPush("WinPosGroup", "Visibility", isWin ? "Visible" : "Collapsed")
        if (isCustom) {
            this.PreviewShowing := false
            this.AreaPreview.Hide()
            this._ComboPush("BtnPreviewArea", "Tag", "0")
        }
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        RunEditorMacroPreview(this.GetCommandStr())
    }

    OnF1(state := "", ctrl := "", event := "") {
        if (this._ShotType() == "自定义截图")
            return
        TogSelectArea(true, this.F1Action)
    }

    OnClickPreviewArea(*) {
        this.PreviewShowing := !this.PreviewShowing
        this.ui.Update("BtnPreviewArea", "Tag", this.PreviewShowing ? "1" : "0")
        this.RefreshPreviewArea()
    }

    RefreshPreviewArea(*) {
        if (!this.PreviewShowing || !IsObject(this.ui) || this._ShotType() == "自定义截图") {
            this.AreaPreview.Hide()
            return
        }
        values := []
        for name in ["StartPosX", "StartPosY", "EndPosX", "EndPosY"] {
            value := this.ui.Query(name)
            if (!IsNumber(value)) {
                this.AreaPreview.Hide()
                return
            }
            values.Push(Number(value))
        }
        target := 0
        if (this._ShotType() == "窗口抓图") {
            target := this.AreaPreview.FindTargetWindow(ResolveEditorBindWindow(this.WindowBindingContext, this.ui.Query("WinInfoCon")))
            if (!target) {
                this.AreaPreview.Hide()
                return
            }
            loop 2 {
                offset := (A_Index - 1) * 2
                pt := Buffer(8, 0)
                NumPut("Int", values[offset + 1], "Int", values[offset + 2], pt)
                DllCall("User32\ClientToScreen", "Ptr", target, "Ptr", pt)
                values[offset + 1] := NumGet(pt, 0, "Int"), values[offset + 2] := NumGet(pt, 4, "Int")
            }
        }
        w := values[3] - values[1], h := values[4] - values[2]
        if (w <= 0 || h <= 0) {
            this.AreaPreview.Hide()
            return
        }
        this.AreaPreview.Show(values[1], values[2], w, h, this.F1Action, target, this._ShotType())
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        if (!IsObject(this.ui))
            return
        curType := this._ShotType()
        isWin := curType == "窗口抓图"
        target := isWin ? this.AreaPreview.FindTargetWindow(ResolveEditorBindWindow(this.WindowBindingContext, this.ui.Query("WinInfoCon"))) : 0
        if (isWin && !target)
            return
        Point1 := isWin ? ScreenPointToWindowClient(x1, y1, target) : [x1, y1]
        Point2 := isWin ? ScreenPointToWindowClient(x2, y2, target) : [x2, y2]
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
        data.ToClipboard := this.ui.Query("ToClipboardCon") == "True" ? 1 : 0
        data.WinInfo := this.ui.Query("WinInfoCon")
        data.StartPosX := TranslateBuiltinVarReferences(this.ui.Query("StartPosX"))
        data.StartPosY := TranslateBuiltinVarReferences(this.ui.Query("StartPosY"))
        data.EndPosX := TranslateBuiltinVarReferences(this.ui.Query("EndPosX"))
        data.EndPosY := TranslateBuiltinVarReferences(this.ui.Query("EndPosY"))
        data.NameType := this.ui.Query("NameTypeCombo>SelectedIndex") == "0" ? "固定名称" : "默认"
        data.ResultSaveName := GetVarName(Trim(this.ui.Query("ResultSaveNameCombo")))
        if (data.ResultSaveName != "")
            MySoftData.GlobalVariMap[data.ResultSaveName] := true
        SaveMacroCMDData(data)
    }
}
