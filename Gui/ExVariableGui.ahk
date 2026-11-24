#Requires AutoHotkey v2.0
#Include ExVariableEditGui.ahk

; =====================================================================
; 变量提取编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class ExVariableGui {
    static AreaFields := ["StartPosX", "StartPosY", "EndPosX", "EndPosY"]

    __new() {
        this.ParentTile := ""
        this.WindowBindingContext := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.Data := ""
        this.SerialStr := ""
        this.AreaPreview := ScreenAreaPreview()
        this.PreviewShowing := false
        this.PreviewFollowAction := this.RefreshPreviewArea.Bind(this)
        this.SetAreaAction := this.OnSetSearchArea.Bind(this)
        this._pickAction := ""
        this._f1Hotkeys := []
        this.MyEditGui := ExVariableEditGui()
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
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this))) {
            this._CloseWindow()
            return
        }
        this.ToggleFunc(true)
        this.OnTypeChange()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _AddLabel(parent, text, margin := "0,0,0,0") {
        return parent.Add("TextBlock").Text(text).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Margin(margin)
    }

    _StyleBox(el, width := "") {
        el.Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (width != "")
            el.Width(width)
        return el
    }

    _StyleCombo(el, width := "") {
        el.Height(26).MinHeight(26).VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (width != "")
            el.Width(width)
        return el
    }

    _AddVarSlot(parent, i, row, col) {
        g := parent.Add("Grid").Grid_Row(row).Grid_Column(col).Margin("0,4").VerticalAlignment("Center")
        g.Cols("22", "28", "*")
        this._AddLabel(g, i ".").Grid_Column(0).HorizontalAlignment("Right")
        g.Add("CheckBox").Name("Tog" i).Grid_Column(1).HorizontalAlignment("Left").VerticalAlignment("Center").Margin("6,0,0,0")
        this._StyleCombo(g.Add("ComboBox").Name("Var" i).Grid_Column(2).Margin("4,0,0,0").IsEditable("True"))
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
        title := this.ParentTile GetLang("变量提取编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("14,8,14,10")
        body.Rows("Auto", "Auto", "48")

        paramCard := body.Add("Border").Grid_Row(0).CornerRadius("8").Padding("12,10,12,8").Margin("0,0,0,8")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        param := paramCard.Add("Grid")
        labelWidth := String(XAMLHost.FontSize() * 6)
        param.Rows("36", "36", "36", "36", "36", "36", "12")
        param.Cols(labelWidth, "*", "12", labelWidth, "*", "12", labelWidth, "*")

        this._AddLabel(param, GetLang("提取来源：")).Grid_Row(0).Grid_Column(0)
        et := this._StyleCombo(param.Add("ComboBox").Name("ExtractTypeCombo").Grid_Row(0).Grid_Column(1), "96")
        et.HorizontalAlignment("Left")
        et.Add("ComboBoxItem").Content(GetLang("屏幕")).Tag("1")
        et.Add("ComboBoxItem").Content(GetLang("剪切板")).Tag("2")
        et.Add("ComboBoxItem").Content(GetLang("窗口")).Tag("3")
        this._AddLabel(param, GetLang("备注：")).Grid_Row(0).Grid_Column(3)
        this._StyleBox(param.Add("TextBox").Name("RemarkCon").Grid_Row(0).Grid_Column(4).Grid_ColumnSpan(4))

        winRow := param.Add("Grid").Name("WinInfoRow").Grid_Row(1).Grid_ColumnSpan(8).Visibility("Hidden")
        winRow.Cols(labelWidth, "*", "8", "28")
        this._AddLabel(winRow, GetLang("窗口绑定：")).Grid_Column(0)
        this._StyleCombo(CmdEditorForm.WindowBindingCombo(winRow, "WinInfoCon").Grid_Column(1))
        CmdEditorForm.IconButton(winRow, "BtnWinEdit", 0xE70F, "编辑").Grid_Column(3)

        extRow := param.Add("Grid").Grid_Row(2).Grid_ColumnSpan(8)
        extRow.Cols(labelWidth, "*", "8", "28")
        this._AddLabel(extRow, GetLang("提取文本：")).ToolTip(GetLang("源文本留空则全部写入第一个变量；只需包含要提取的片段即可。")).Grid_Column(0)
        this._StyleBox(extRow.Add("TextBox").Name("ExtractStrCon").Grid_Column(1))
        CmdEditorForm.IconButton(extRow, "BtnExtractEdit", 0xE70F, "编辑").Grid_Column(3)

        this._AddLabel(param, GetLang("提取次数:")).Grid_Row(3).Grid_Column(0)
        this._StyleCombo(param.Add("ComboBox").Name("SearchCountCombo").Grid_Row(3).Grid_Column(1).IsEditable("True"), "80")
            .HorizontalAlignment("Left")
        this._AddLabel(param, GetLang("每次间隔：")).ToolTip(GetLang("两次操作之间等待的毫秒数。")).Grid_Row(4).Grid_Column(0)
        this._StyleBox(param.Add("TextBox").Name("SearchIntervalCon").Grid_Row(4).Grid_Column(1), "80")
            .TextAlignment("Center").HorizontalAlignment("Left")

        area := param.Add("Grid").Name("AreaRow").Grid_Row(3).Grid_RowSpan(2).Grid_Column(3).Grid_ColumnSpan(5)
        area.Rows("*", "*")
        area.Cols(labelWidth, "0", "*", "8", "*")
        areaBtn := area.Add("Button").Name("BtnPreviewArea").Grid_RowSpan(2).Cursor("Hand").Focusable("False")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch")
            .Tag("0").ToolTip(GetLang("搜索范围"))
            .HorizontalContentAlignment("Left").VerticalContentAlignment("Stretch")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        areaBtn.InjectResources(ScreenAreaPreview.ButtonStyle())
        areaLabels := areaBtn.Add("Grid")
        areaLabels.Rows("*", "*")
        this._AddLabel(areaLabels, GetLang("起始坐标：")).Grid_Row(0).IsHitTestVisible("False")
        this._AddLabel(areaLabels, GetLang("终止坐标：")).Grid_Row(1).IsHitTestVisible("False")
        for i, name in ExVariableGui.AreaFields {
            this._StyleCombo(area.Add("ComboBox").Name(name).Grid_Row((i - 1) // 2)
                .Grid_Column(Mod(i - 1, 2) ? 4 : 2).IsEditable("True").SetProp("Panel.ZIndex", "2"))
        }
        ocrRow := param.Add("Grid").Name("OcrEngineRow").Grid_Row(5).Grid_ColumnSpan(8)
        ocrRow.Cols(labelWidth, "*")
        this._AddLabel(ocrRow, GetLang("OCR模型："))
        this._StyleCombo(CmdEditorForm.OcrCombo(ocrRow, "OcrEngineCon").Grid_Column(1))

        resCard := body.Add("Border").Grid_Row(1).Name("ResultGroup").CornerRadius("8").Padding("12,6,12,18")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        res := resCard.Add("Grid")
        res.Rows("26", "Auto")
        res.Add("CheckBox").Grid_Row(0).Name("IsIgnoreExist").Content(GetLang("如果变量存在则不改变数值"))
            .HorizontalAlignment("Center").VerticalAlignment("Center").Margin("10,0,0,0").Foreground("{DynamicResource TextMain}")
        varGrid := res.Add("Grid").Grid_Row(1)
        varGrid.Cols("*", "10", "*", "10", "*")
        varGrid.Rows("36", "36")
        this._AddVarSlot(varGrid, 1, 0, 0)
        this._AddVarSlot(varGrid, 2, 0, 2)
        this._AddVarSlot(varGrid, 3, 0, 4)
        this._AddVarSlot(varGrid, 4, 1, 0)
        this._AddVarSlot(varGrid, 5, 1, 2)
        this._AddVarSlot(varGrid, 6, 1, 4)

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="680" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/12-变量提取", XamlWin.BindCurrent(this, "TriggerMacro"), "!l", "", XamlWin.BindCurrent(this, "OnF1"))
        this.ui.OnEvent("ExtractTypeCombo", "SelectionChanged", XamlWin.BindCurrent(this, "OnTypeChange"))
        this.ui.OnEvent("BtnWinEdit", "Click", XamlWin.BindCurrent(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnExtractEdit", "Click", XamlWin.BindCurrent(this, "OnClickExtractBtn"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnPreviewArea", "Click", XamlWin.BindCurrent(this, "OnClickPreviewArea"))
        refresh := XamlWin.BindCurrent(this, "RefreshPreviewArea")
        this.ui.OnEvent("WinInfoCon", "TextChanged", refresh)
        this.ui.OnEvent("WinInfoCon", "SelectionChanged", refresh)
        for name in ExVariableGui.AreaFields
            this.ui.OnEvent(name, "LostFocus", refresh)
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
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

    _TypeValue() {
        v := IsObject(this.ui) ? this.ui.Query("ExtractTypeCombo>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumExtractNames())
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("变量提取")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        this._EnsureExVarDataLen()
        this._FillExVars()
        this.ui.Update("IsIgnoreExist", "IsChecked", this.Data.IsIgnoreExist ? "True" : "False")
        this.ui.Update("ExtractStrCon", "Text", this.Data.ExtractStr)
        this.ui.Update("ExtractTypeCombo", "SelectedIndex", String(CmdEnumIndex(this.Data.ExtractType, CmdEnumExtractNames())))
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)
        this.ui.Update("OcrEngineCon", "SelectedIndex", String(OcrEngineIndex(OcrEngineValue(this.Data))))

        this._ComboPush("StartPosX", "Text", GetLang(this.Data.StartPosX))
        this._ComboPush("StartPosY", "Text", GetLang(this.Data.StartPosY))
        this._ComboPush("EndPosX", "Text", GetLang(this.Data.EndPosX))
        this._ComboPush("EndPosY", "Text", GetLang(this.Data.EndPosY))
        this._SetCombo("SearchCountCombo", [GetLang("无限")], this.Data.SearchCount == -1 ? GetLang("无限") : this.Data.SearchCount)
        this.ui.Update("SearchIntervalCon", "Text", this.Data.SearchInterval)
    }

    ; 固定 6 路结果变量
    _EnsureExVarDataLen() {
        if (!IsObject(this.Data)) {
            this.Data := ExVariableData()
            this.Data.SerialStr := this.SerialStr
        }
        if (this.Data.ToggleArr.Length == 0) {
            this.Data.ToggleArr := [1, 0, 0, 0, 0, 0]
            this.Data.VariableArr := ["Text1", "Text2", "Text3", "Text4", "Text5", "Text6"]
        }
        while (this.Data.ToggleArr.Length < 6)
            this.Data.ToggleArr.Push(false)
        while (this.Data.VariableArr.Length < 6)
            this.Data.VariableArr.Push("Text" (this.Data.VariableArr.Length + 1))
        while (this.Data.ToggleArr.Length > 6)
            this.Data.ToggleArr.RemoveAt(this.Data.ToggleArr.Length)
        while (this.Data.VariableArr.Length > 6)
            this.Data.VariableArr.RemoveAt(this.Data.VariableArr.Length)
    }

    _FillExVars() {
        if (!IsObject(this.ui))
            return
        this._EnsureExVarDataLen()
        vars := GetGuiVarArr()
        loop 6 {
            i := A_Index
            this.ui.Update("Tog" i, "IsChecked", this.Data.ToggleArr[i] ? "True" : "False")
            this._SetCombo("Var" i, vars, this.Data.VariableArr[i])
        }
    }

    ToggleFunc(state) {
        if (state) {
            Hotkey("!l", (*) => this.TriggerMacro(), "On")
        }
        else {
            try Hotkey("!l", "Off")
            WinHotkey.UnregisterAll(this._f1Hotkeys)
            this._f1Hotkeys := []
            this._CancelPick()
            this.PreviewShowing := false
            SetTimer(this.PreviewFollowAction, 0)
            this.AreaPreview.Hide()
        }
    }

    OnTypeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        type := this._TypeValue()
        isWin := type == "窗口"
        for name in ExVariableGui.AreaFields {
            items := isWin ? GetGuiVarArr() : GetGuiVarArr(StrLower(SubStr(name, -1)))
            this._SetCombo(name, items, this.ui.Query(name))
        }
        this.ui.Update("WinInfoRow", "Visibility", isWin ? "Visible" : "Hidden")
        hasArea := type != "剪切板"
        this.ui.Update("AreaRow", "IsEnabled", hasArea ? "True" : "False")
        this.ui.Update("OcrEngineRow", "Visibility", hasArea ? "Visible" : "Hidden")
        this.ui.BatchUpdate(CmdEditorF1Updates(hasArea ? "area" : ""))
        if (hasArea && this.Hwnd() && !this._f1Hotkeys.Length)
            this._f1Hotkeys := WinHotkey.Register(["F1"], this.OnF1.Bind(this), this.Hwnd())
        else if (!hasArea) {
            WinHotkey.UnregisterAll(this._f1Hotkeys)
            this._f1Hotkeys := []
            this._CancelPick()
            this.PreviewShowing := false
        }
        this._SyncPreviewArea(type)
    }

    OnClickWinEditBtn(state := "", ctrl := "", event := "") {
        MyFrontInfoGui.HideAction := XamlWin.BindCurrent(this, "RefreshPreviewArea")
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        ; 传值桥接（原生 FrontInfoGui 读写 .Value），不传字符串
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    OnClickExtractBtn(state := "", ctrl := "", event := "") {
        this.MyEditGui.SureAction := this.OnSureExtractAction.Bind(this)
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            this.MyEditGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.MyEditGui.OwnerHwnd := ""
        }
        this.MyEditGui.ShowGui(this.ui.Query("ExtractStrCon"))
    }

    OnSureExtractAction(ExtractStr, VariNum) {
        if (IsObject(this.ui))
            this.ui.Update("ExtractStrCon", "Text", ExtractStr)
        this.SaveExVariableData()
        this._EnsureExVarDataLen()
        if (!IsNumber(VariNum) || Integer(VariNum) < 0)
            VariNum := 0
        VariNum := Integer(VariNum)
        if (VariNum > 6)
            VariNum := 6
        loop 6 {
            isTog := VariNum >= A_Index
            this.ui.Update("Tog" A_Index, "IsChecked", isTog ? "True" : "False")
            this.Data.ToggleArr[A_Index] := isTog
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveExVariableData()
        this.ToggleFunc(false)
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this._CloseWindow()
    }

    OnF1(*) {
        if (!IsObject(this.ui) || this._pickAction != "" || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        ui := this.ui
        type := this._TypeValue()
        if (type == "剪切板")
            return

        isWin := type == "窗口"
        info := isWin ? this._ResolveWindowBinding(ui.Query("WinInfoCon")) : ""
        followsMouse := isWin && IsMouseWindowBinding(info)
        hwnd := isWin && !followsMouse ? this._FindTargetWindow(info) : 0
        if (isWin && !followsMouse && !hwnd) {
            RmtDialog.Info(GetLang("未找到目标窗口。"), "", this.Hwnd())
            return
        }

        coords := []
        action := (x1, y1, x2, y2) => coords.Push(x1, y1, x2, y2)
        this._pickAction := action
        this.AreaPreview.Hide()
        try TogSelectArea(true, action)
        finally {
            try this._CancelPick()
            this._pickAction := ""
        }
        if (this.ui != ui)
            return
        if (this._TypeValue() != type || !coords.Length || coords[1] == coords[3] || coords[2] == coords[4]) {
            this.RefreshPreviewArea()
            return
        }
        if (isWin) {
            if (followsMouse)
                hwnd := this._FindTargetWindow(info)
            if (!this._TryGetClientOrigin(hwnd, &clientX, &clientY)) {
                this.RefreshPreviewArea()
                RmtDialog.Info(GetLang("未找到目标窗口。"), "", this.Hwnd())
                return
            }
            coords := [coords[1] - clientX, coords[2] - clientY, coords[3] - clientX, coords[4] - clientY]
        }
        this.OnSetSearchArea(coords*)
    }

    _CancelPick() {
        if (this._pickAction != "" && MainSoftData.SelectAreaAction == this._pickAction)
            TogSelectArea(false)
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        if (!IsObject(this.ui))
            return
        values := [x1, y1, x2, y2]
        updates := []
        for i, name in ExVariableGui.AreaFields
            updates.Push({ControlName: name, PropertyName: "Text", Value: String(values[i])})
        this.ui.BatchUpdate(updates)
        this.RefreshPreviewArea()
    }

    _ResolveWindowBinding(info) => ResolveEditorBindWindow(this.WindowBindingContext, Trim(info))

    _FindTargetWindow(info) {
        try return this.AreaPreview.FindTargetWindow(info, false)
        return 0
    }

    _TryGetClientOrigin(hwnd, &x, &y) {
        root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
        if (!root)
            return false
        try {
            if (WinGetMinMax(root) == -1)
                return false
            WinGetClientPos(&x, &y, , , root)
            return true
        }
        return false
    }

    OnClickPreviewArea(*) {
        type := this._TypeValue()
        if (type == "剪切板")
            return
        this.PreviewShowing := !this.PreviewShowing
        this._SyncPreviewArea(type)
    }

    _SyncPreviewArea(type) {
        this.ui.Update("BtnPreviewArea", "Tag", this.PreviewShowing ? "1" : "0")
        SetTimer(this.PreviewFollowAction, this.PreviewShowing && type == "窗口" ? 100 : 0)
        this.RefreshPreviewArea()
    }

    RefreshPreviewArea(*) {
        if (!IsObject(this.ui) || !this.PreviewShowing || this._pickAction != "") {
            this.AreaPreview.Hide()
            return
        }
        if (this.AreaPreview.IsDragging())
            return

        ui := this.ui
        state := ui.Query("ExtractTypeCombo>SelectedIndex", "WinInfoCon", ExVariableGui.AreaFields*)
        if (this.ui != ui || !this.PreviewShowing || this._pickAction != "" || this.AreaPreview.IsDragging())
            return
        type := CmdEnumFromIndex(state.Get("ExtractTypeCombo>SelectedIndex", ""), CmdEnumExtractNames())
        coords := []
        for name in ExVariableGui.AreaFields {
            value := state.Get(name, "")
            if (!IsNumber(value)) {
                this.AreaPreview.Hide()
                return
            }
            coords.Push(Number(value))
        }
        width := Abs(coords[3] - coords[1]), height := Abs(coords[4] - coords[2])
        if (type == "剪切板" || !width || !height) {
            this.AreaPreview.Hide()
            return
        }

        targetHwnd := 0
        x := Min(coords[1], coords[3]), y := Min(coords[2], coords[4])
        if (type == "窗口") {
            targetHwnd := this._FindTargetWindow(this._ResolveWindowBinding(state.Get("WinInfoCon", "")))
            if (!this._TryGetClientOrigin(targetHwnd, &clientX, &clientY)) {
                this.AreaPreview.Hide()
                return
            }
            x += clientX, y += clientY
        }
        this.AreaPreview.Show(x, y, width, height, this.SetAreaAction, targetHwnd, type)
    }

    CheckIfValid() {
        if (this._TypeValue() == "窗口" && this.ui.Query("WinInfoCon") == "") {
            RmtDialog.Info(GetLang("窗口绑定不能为空"))
            return false
        }

        if (!InStr(this.ui.Query("ExtractStrCon"), "&x") && !InStr(this.ui.Query("ExtractStrCon"), "&c")) {
            if (this.ui.Query("ExtractStrCon") != "") {
                RmtDialog.Info(GetLang("提取文本：不包含&x 或 &c 无法提取内容到变量中"))
                return false
            }
        }

        ToggleArr := []
        loop this.Data.ToggleArr.Length {
            isOn := this.ui.Query("Tog" A_Index) == "True"
            ToggleArr.Push(isOn)
            if (isOn) {
                varText := this.ui.Query("Var" A_Index)
                if (IsNumber(varText)) {
                    RmtDialog.Info(Format(GetLang("{}. 变量名不规范：变量名不能是纯数字"), A_Index))
                    return false
                }
                if (InStr(varText, "_")) {
                    RmtDialog.Info(Format(GetLang("{}. 变量名不规范：变量名不能包含下划线"), A_Index))
                    return false
                }
            }
        }

        ActiveLength := GetLastEnabledExtractRow(ToggleArr)
        if (ActiveLength > 1) {
            ExtractStr := this.ui.Query("ExtractStrCon")
            ExtractStr := StrReplace(ExtractStr, "&x", "", true, &XCount)
            ExtractStr := StrReplace(ExtractStr, "&c", "", true, &YCount)
            if (XCount + YCount < ActiveLength) {
                RmtDialog.Info(Format(GetLang("提取文本中包含的&x和&c个数少于结果保存变量中勾选的个数")))
                return false
            }
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.SaveExVariableData()
        CommandStr := this.GetCommandStr()
        tableItem := MySoftData.SpecialTableItem
        if (tableItem.Items.Length == 0) {
            item := MacroItem()
            item.ID := GetCMDSerialStr("Item")
            tableItem.Items.Push(item)
            tableItem.RebuildIndex()
        }
        item := tableItem.Items[1]
        item.Killed := false
        item.Pause := false
        item.ActionCount := 0
        this.TestExVariable(this.Data)
    }

    TestExVariable(Data) {
        tableItem := MySoftData.SpecialTableItem
        extractType := CmdEnumZh(Data.ExtractType, CmdEnumExtractNames())
        TextObjs := []
        if (extractType == "剪切板") {
            if (!IsClipboardText())
                return
            TextObjs.Push({Text: A_Clipboard})
        } else {
            if (!TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
                || !TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
                || !TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
                || !TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
                || !IsNumber(X1) || !IsNumber(Y1) || !IsNumber(X2) || !IsNumber(Y2)
                || X2 <= X1 || Y2 <= Y1) {
                RmtDialog.Info(GetLang("请先设置有效的提取范围"))
                return
            }
            try {
                if (extractType == "屏幕") {
                    result := GetScreenTextObjArr(X1, Y1, X2, Y2, Data.OCRType, OcrEngineValue(Data))
                    if (IsObject(result))
                        TextObjs := result
                } else if (extractType == "窗口") {
                    for hwnd in GetHwndList(this._ResolveWindowBinding(Data.WinInfo)) {
                        result := GetWinTextObjArr(hwnd, X1, Y1, X2, Y2, Data.OCRType, OcrEngineValue(Data))
                        if (IsObject(result))
                            TextObjs.Push(result*)
                    }
                }
            } catch as err {
                RmtDialog.Info(GetLang("变量提取失败") "`n" err.Message)
                return
            }
        }

        allText := ""
        for _, value in TextObjs {
            allText .= value.text "`n"
        }
        allText := Trim(allText)

        NameArr := []
        ValueArr := []
        ExtractStr := this.GetReplaceVarText(Data.ExtractStr)
        for _, value in TextObjs {
            VariableValueArr := ExtractVariable(value.Text, ExtractStr)
            VariableValueArr := ExtractStr == "" && allText != "" ? [allText] : VariableValueArr
            if (VariableValueArr == "")
                continue
            if (GetLastEnabledExtractRow(Data.ToggleArr) > VariableValueArr.Length)
                continue

            for i, enabled in Data.ToggleArr {
                if (enabled) {
                    NameArr.Push(Data.VariableArr[i])
                    ValueArr.Push(VariableValueArr[i])
                }
            }
            break
        }

        if (NameArr.Length == 0) {
            RmtDialog.Info(GetLang("变量提取失败"))
        }
        else {
            tipStr := GetLang("已提取以下变量") "`n"
            loop NameArr.Length {
                tipStr .= NameArr[A_Index] " = " ValueArr[A_Index] "`n"
            }
            RmtDialog.Info(tipStr)
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    SaveExVariableData() {
        this.Data.ExtractStr := this.ui.Query("ExtractStrCon")
        this.Data.ExtractType := this._TypeValue()
        this.Data.WinInfo := this.ui.Query("WinInfoCon")
        this.Data.OCRType := 1 ; v6 统一多语言模型，不再区分
        this.Data.OcrEngine := OcrEngineFromIndex(this.ui.Query("OcrEngineCon>SelectedIndex"))
        this.Data.StartPosX := GetVarName(this.ui.Query("StartPosX"))
        this.Data.StartPosY := GetVarName(this.ui.Query("StartPosY"))
        this.Data.EndPosX := GetVarName(this.ui.Query("EndPosX"))
        this.Data.EndPosY := GetVarName(this.ui.Query("EndPosY"))
        this.Data.SearchCount := this.ui.Query("SearchCountCombo") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCombo")
        this.Data.SearchInterval := this.ui.Query("SearchIntervalCon")
        this.Data.IsIgnoreExist := this.ui.Query("IsIgnoreExist") == "True"
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.Data.ToggleArr[i] := this.ui.Query("Tog" i) == "True"
            this.Data.VariableArr[i] := GetVarName(this.ui.Query("Var" i))
        }

        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.VariableArr[A_Index]] := true
        }
        SaveMacroCMDData(this.Data)
    }

    GetReplaceVarText(text) {
        matches := []
        pos := 1
        while (pos := RegExMatch(text, "\{(.*?)\}", &match, pos)) {
            matches.Push(match[1])
            pos += match.Len
        }
        Content := text
        for index, value in matches {
            hasValue := this.TryGetVariableValue(&variValue, value, false)
            if (hasValue)
                Content := StrReplace(Content, "{" value "}", variValue)
        }
        return Content
    }

    TryGetVariableValue(&Value, variableName, variTip := true) {
        key := GetBuiltinVarName(variableName)
        if (key == "运行时窗口坐标X" || key == "运行时窗口坐标Y")
            return TryGetVarValue(&Value, key, variTip)
        if (IsNumber(variableName)) {
            Value := variableName
            return true
        }
        if (variableName == GetLang("运行时坐标X") || variableName == GetLang("运行时坐标Y")) {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            Value := variableName == GetLang("运行时坐标X") ? mouseX : mouseY
            return true
        }
        GlobalVariableMap := MySoftData.VariableMap
        if (GlobalVariableMap.Has(variableName)) {
            Value := GlobalVariableMap[variableName]
            return true
        }
        if (variTip)
            ShowNoVariableTip(variableName)
        return false
    }
}
