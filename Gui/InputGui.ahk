#Requires AutoHotkey v2.0

; =====================================================================
; 输入编辑器 —— XAML 迁移版（独立实现）
; 类型：弹窗 / 状态 / 选择 / 多选（旧 继续 / 继续&取消 仍可打开已存指令）
; =====================================================================

class InputGui {
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

    _TypeKeys() {
        keys := ["弹窗", "状态", "选择", "多选"]
        if (IsObject(this.Data)) {
            cur := this.Data.Type
            if (cur == "继续" || cur == "继续&取消")
                keys.Push(cur)
        }
        return keys
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("输入编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,12")
        body.Rows("36", "36", "36", "36", "36", "36", "56")
        body.Cols("80", "150", "12", "80", "150")

        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        cancelRow := body.Add("Grid").Grid_Row(0).Grid_Column(3).Grid_ColumnSpan(2).Name("CancelRow").Visibility("Collapsed")
        cancelRow.Cols("80", "150")
        cancelRow.Add("TextBlock").Grid_Column(0).Text(GetLang("取消时:")).VerticalAlignment("Center")
        ct := cancelRow.Add("ComboBox").Grid_Column(1).Name("CancelTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["终止当前宏", "终止所有宏"])
            ct.Add("ComboBoxItem").Content(t)

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("输入类型:")).VerticalAlignment("Center")
        tc := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("TypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["弹窗", "状态", "选择", "多选"])
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

        optRow := body.Add("Grid").Grid_Row(3).Grid_ColumnSpan(5).Name("OptionsRow")
        optRow.Cols("80", "*")
        optRow.Add("TextBlock").Grid_Column(0).Text(GetLang("选项：")).VerticalAlignment("Center")
        optRow.Add("TextBox").Grid_Column(1).Name("OptionsCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .ToolTip(GetLang("逗号分隔选项"))
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        defRow := body.Add("Grid").Grid_Row(4).Grid_ColumnSpan(5).Name("DefaultRow")
        defRow.Cols("80", "150", "12", "80", "150")
        resultRow := defRow.Add("Grid").Grid_Column(0).Grid_ColumnSpan(2).Name("ResultRow")
        resultRow.Cols("80", "150")
        resultRow.Add("TextBlock").Grid_Column(0).Text(GetLang("结果变量：")).VerticalAlignment("Center")
        resultRow.Add("ComboBox").Grid_Column(1).Name("SaveNameCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        defRow.Add("TextBlock").Grid_Column(3).Name("DefaultLabel").Text(GetLang("默认值：")).VerticalAlignment("Center")
        defRow.Add("TextBox").Grid_Column(4).Name("DefaultCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(5).Grid_Column(0).Text(GetLang("超时(ms)：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(5).Grid_Column(1).Name("TimeoutCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(5).Grid_Column(3).Text(GetLang("超时后:")).VerticalAlignment("Center")
        ta := body.Add("ComboBox").Grid_Row(5).Grid_Column(4).Name("TimeoutActionCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["无", "用默认值", "保持原值", "终止当前宏", "终止所有宏"])
            ta.Add("ComboBoxItem").Content(t)

        btnRow := body.Add("StackPanel").Grid_Row(6).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Bottom").Margin("0,0,0,4")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="540" Height="348"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/7-输入", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshType"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("输入")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        EnsureInputData(this.Data)
        this.DLVariableArr := GetGuiVarArr(1)
        this.DLArrayArr := GetGuiArrNameArr()

        this._SetDDL("TypeCombo", GetLangArr(this._TypeKeys()), GetLang(this.Data.Type))
        this._SetDDL("PauseTypeCombo", GetLangArr(["暂停当前宏", "暂停所有宏"]), GetLang(this.Data.PauseType))
        this._SetDDL("CancelTypeCombo", GetLangArr(["终止当前宏", "终止所有宏"]), GetLang(this.Data.CancelType))
        this._SetDDL("TimeoutActionCombo", GetLangArr(["无", "用默认值", "保持原值", "终止当前宏", "终止所有宏"]), GetLang(this.Data.TimeoutAction))
        this._SetCombo("SaveNameCombo", GetGuiVarArr(), this.Data.SaveName)
        prompt := this.Data.Prompt
        if (prompt == "")
            prompt := InputDefaultPrompt()
        opts := this.Data.Options
        if (opts == "")
            opts := InputDefaultOptions()
        this._ComboPush("PromptCon", "Text", prompt)
        this._ComboPush("OptionsCon", "Text", opts)
        this._ComboPush("DefaultCon", "Text", this.Data.DefaultValue)
        this._ComboPush("TimeoutCon", "Text", this.Data.TimeoutMs)
    }

    OnRefreshType(state := "", ctrl := "", event := "") {
        this.RefreshConVisable()
    }

    RefreshConVisable() {
        if (!IsObject(this.ui))
            return
        typeText := this.ui.Query("TypeCombo")
        IsPopUp := typeText == GetLang("弹窗")
        IsState := typeText == GetLang("状态")
        IsChoice := typeText == GetLang("选择")
        IsMulti := typeText == GetLang("多选")
        IsGoOnAndCancel := typeText == GetLang("继续&取消")

        HasOptions := IsChoice || IsMulti
        HasDefault := IsPopUp || IsState || IsChoice || IsMulti
        HasRes := IsPopUp || IsState || IsChoice || IsMulti
        if (this.ui.Query("PromptCon") == "")
            this.ui.Update("PromptCon", "Text", InputDefaultPrompt())
        if (HasOptions && this.ui.Query("OptionsCon") == "")
            this.ui.Update("OptionsCon", "Text", InputDefaultOptions())
        if (IsState && this.ui.Query("DefaultCon") == "")
            this.ui.Update("DefaultCon", "Text", "1")

        this.ui.Update("OptionsRow", "Visibility", HasOptions ? "Visible" : "Collapsed")
        this.ui.Update("DefaultRow", "Visibility", (HasDefault || HasRes) ? "Visible" : "Collapsed")
        this.ui.Update("DefaultLabel", "Visibility", HasDefault ? "Visible" : "Collapsed")
        this.ui.Update("DefaultCon", "Visibility", HasDefault ? "Visible" : "Collapsed")
        this.ui.Update("ResultRow", "Visibility", HasRes ? "Visible" : "Collapsed")
        this.ui.Update("CancelRow", "Visibility", IsGoOnAndCancel ? "Visible" : "Collapsed")
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
        if (this.ui.Query("ResultRow>Visibility") != "Collapsed") {
            if (!CheckVarNameIfValid(this.ui.Query("SaveNameCombo")))
                return false
        }
        timeout := this.ui.Query("TimeoutCon")
        if (timeout != "" && (!IsNumber(timeout) || Number(timeout) < 0)) {
            RmtDialog.Info(GetLang("超时请输入大于等于0的数字（毫秒）"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)

        typeText := this.ui.Query("TypeCombo")
        HasRes := typeText == GetLang("弹窗") || typeText == GetLang("状态") || typeText == GetLang("选择") || typeText == GetLang("多选")
        if (HasRes) {
            Res := ""
            if (MySoftData.VariableMap.Has(this.Data.SaveName))
                Res := MySoftData.VariableMap[this.Data.SaveName]

            if (Res != "") {
                tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
                tip2 := Format(GetLang("值：{}"), Res)
                RmtDialog.Info(tip1 "`n" tip2)
            }
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            Remark := this.ui.Query("TypeCombo")
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveData() {
        this.Data.Type := GetLangKey(this.ui.Query("TypeCombo"))
        this.Data.PauseType := GetLangKey(this.ui.Query("PauseTypeCombo"))
        this.Data.CancelType := GetLangKey(this.ui.Query("CancelTypeCombo"))
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCombo"))
        this.Data.Prompt := this.ui.Query("PromptCon")
        if (this.Data.Prompt == "")
            this.Data.Prompt := "提示文本"
        this.Data.Options := this.ui.Query("OptionsCon")
        if (this.Data.Options == "")
            this.Data.Options := "选项一，选项二，选项三"
        this.Data.DefaultValue := this.ui.Query("DefaultCon")
        if (this.Data.Type == "状态" && this.Data.DefaultValue == "")
            this.Data.DefaultValue := "1"
        timeout := this.ui.Query("TimeoutCon")
        this.Data.TimeoutMs := IsNumber(timeout) ? Integer(timeout) : 0
        this.Data.TimeoutAction := GetLangKey(this.ui.Query("TimeoutActionCombo"))

        if (this.ui.Query("ResultRow>Visibility") != "Collapsed") {
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
