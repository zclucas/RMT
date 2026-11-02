#Requires AutoHotkey v2.0

; =====================================================================
; 等待确定编辑器 —— 流程控制 / 等待 下方
; 类型：继续 / 继续&终止&暂停
; =====================================================================

class WaitConfirmGui {
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
        this.RefreshConVisable()
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
        title := this.ParentTile GetLang("等待确定编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,12")
        body.Rows("36", "36", "36", "36", "36", "56")
        body.Cols("80", "150", "12", "80", "150")

        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("类型:")).VerticalAlignment("Center")
        tc := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("TypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["继续", "继续&终止&暂停"])
            tc.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("交互时:")).VerticalAlignment("Center")
        pt := body.Add("ComboBox").Grid_Row(1).Grid_Column(4).Name("PauseTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["暂停当前宏", "暂停所有宏"])
            pt.Add("ComboBoxItem").Content(t)

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("提示：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(2).Grid_Column(1).Grid_ColumnSpan(4).Name("PromptCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("超时(ms)：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(3).Grid_Column(1).Name("TimeoutCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(3).Grid_Column(3).Text(GetLang("超时后:")).VerticalAlignment("Center")
        ta := body.Add("ComboBox").Grid_Row(3).Grid_Column(4).Name("TimeoutActionCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["无", "自动继续", "自动终止", "自动暂停"])
            ta.Add("ComboBoxItem").Content(t)

        extra := body.Add("Grid").Grid_Row(4).Grid_ColumnSpan(5).Name("ExtraRow")
        extra.Cols("80", "150", "12", "80", "150")
        extra.Add("TextBlock").Grid_Column(0).Text(GetLang("终止时:")).VerticalAlignment("Center")
        tt := extra.Add("ComboBox").Grid_Column(1).Name("TerminateTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["终止当前宏", "终止所有宏"])
            tt.Add("ComboBoxItem").Content(t)
        extra.Add("TextBlock").Grid_Column(3).Text(GetLang("暂停时:")).VerticalAlignment("Center")
        pb := extra.Add("ComboBox").Grid_Column(4).Name("PauseBtnTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["暂停当前宏", "暂停所有宏"])
            pb.Add("ComboBoxItem").Content(t)

        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Bottom").Margin("0,0,0,4")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="540" Height="300"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/等待确定", (*) => this.TriggerMacro(), "!l")
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshType"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("等待确定")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        this._SetDDL("TypeCombo", GetLangArr(["继续", "继续&终止&暂停"]), GetLang(this.Data.Type))
        this._SetDDL("PauseTypeCombo", GetLangArr(["暂停当前宏", "暂停所有宏"]), GetLang(this.Data.PauseType))
        this._SetDDL("TimeoutActionCombo", GetLangArr(["无", "自动继续", "自动终止", "自动暂停"]), GetLang(this.Data.TimeoutAction))
        this._SetDDL("TerminateTypeCombo", GetLangArr(["终止当前宏", "终止所有宏"]), GetLang(this.Data.TerminateType))
        this._SetDDL("PauseBtnTypeCombo", GetLangArr(["暂停当前宏", "暂停所有宏"]), GetLang(this.Data.PauseBtnType))
        this._ComboPush("PromptCon", "Text", this.Data.Prompt)
        this._ComboPush("TimeoutCon", "Text", this.Data.TimeoutMs)
    }

    OnRefreshType(state := "", ctrl := "", event := "") {
        this.RefreshConVisable()
    }

    RefreshConVisable() {
        if (!IsObject(this.ui))
            return
        isTriple := this.ui.Query("TypeCombo") == GetLang("继续&终止&暂停")
        this.ui.Update("ExtraRow", "Visibility", isTriple ? "Visible" : "Collapsed")
    }

    ToggleFunc(state) {
        try Hotkey("!l", (*) => this.TriggerMacro(), state ? "On" : "Off")
    }

    TriggerMacro(*) {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this._CloseWindow()
    }

    CheckIfValid() {
        timeout := this.ui.Query("TimeoutCon")
        if (timeout != "" && (!IsNumber(timeout) || Number(timeout) < 0)) {
            RmtDialog.Info(GetLang("超时请输入大于等于0的数字（毫秒）"))
            return false
        }
        return true
    }

    GetCommandStr() {
        serial := this.Data.SerialStr
        if (serial == "")
            serial := this.SerialStr
        textOnly := RegExReplace(serial, "\d+")
        numbersOnly := RegExReplace(serial, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            Remark := this.ui.Query("TypeCombo")
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveData() {
        if (this.Data.SerialStr == "")
            this.Data.SerialStr := this.SerialStr
        this.Data.Type := GetLangKey(this.ui.Query("TypeCombo"))
        this.Data.PauseType := GetLangKey(this.ui.Query("PauseTypeCombo"))
        this.Data.Prompt := this.ui.Query("PromptCon")
        timeout := this.ui.Query("TimeoutCon")
        this.Data.TimeoutMs := IsNumber(timeout) ? Integer(timeout) : 0
        this.Data.TimeoutAction := GetLangKey(this.ui.Query("TimeoutActionCombo"))
        this.Data.TerminateType := GetLangKey(this.ui.Query("TerminateTypeCombo"))
        this.Data.PauseBtnType := GetLangKey(this.ui.Query("PauseBtnTypeCombo"))
        SaveMacroCMDData(this.Data)
    }
}
