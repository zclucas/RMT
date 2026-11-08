#Requires AutoHotkey v2.0

; =====================================================================
; 宏操作编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class SubMacroGui {
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
        this._syncing := false
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
        try {
            this.Init(cmd)
            this.OnRefresh()
        } finally {
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
        title := this.ParentTile GetLang("宏操作编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,8")
        body.Rows("36", "36", "36", "24", "24", "56")
        body.Cols("96", "*", "12", "96", "190")

        ; 行0：备注（宽度与宏类型下拉一致）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：宏类型 + 宏序号（序号整体左移 20px，下拉加宽 50px）
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("宏类型：")).VerticalAlignment("Center")
        tc := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("TypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "语音宏", "定时宏", "宏", "网络宏"])
            tc.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("宏序号：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(4).Name("DropDownIndexCombo").Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行2：操作类型 + 调用次数（仅调用时显示在操作类型后）
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("操作类型:")).VerticalAlignment("Center")
        ct := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("CallTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for c in GetLangArr(["调用", "触发", "暂停", "取消暂停", "终止"])
            ct.Add("ComboBoxItem").Content(c)
        insertRow := body.Add("Grid").Name("InsertRow").Grid_Row(2).Grid_Column(3).Grid_ColumnSpan(2).Visibility("Collapsed")
        insertRow.Cols("96", "*")
        insertRow.Add("TextBlock").Grid_Column(0).Text(GetLang("调用次数：")).VerticalAlignment("Center")
        insertRow.Add("ComboBox").Grid_Column(1).Name("InsertCountCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行3-4：提示
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(5).Text(GetLang("调用：运行指定宏后，再执行后续指令")).VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(4).Grid_ColumnSpan(5).Text(GetLang("触发: 运行指定宏，指定宏和当前宏同时执行")).VerticalAlignment("Center")

        ; 行5：确定
        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="600" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/10-宏操作", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("CallTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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

    _SelIndex(comboName) {
        v := IsObject(this.ui) ? this.ui.Query(comboName ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    _TypeValue() => this._SelIndex("TypeCombo") + 1
    _CallValue() => this._SelIndex("CallTypeCombo") + 1

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("宏操作")
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(2)

        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "语音宏", "定时宏", "宏", "网络宏"])
        this._ComboPush("TypeCombo", "SelectedIndex", String(this._LangArrIndex(macroTypes, this.Data.MacroType) - 1))
        this._ComboPush("CallTypeCombo", "SelectedIndex", String(this._CallValueFromData() - 1))
        this._SetCombo("InsertCountCombo", this.DLVariableArr, GetLang(this.Data.InsertCount))
    }

    ToggleFunc(state) {
        if (state) {
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
        }
        else {
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
        }
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "语音宏", "定时宏", "宏", "网络宏"])
        if (this._syncing && IsObject(this.Data)) {
            typeValue := this._LangArrIndex(macroTypes, this.Data.MacroType)
            lastIndex := (IsNumber(this.Data.Index) && Integer(this.Data.Index) >= 1) ? Integer(this.Data.Index) : 1
            callValue := this._CallValueFromData()
        } else {
            typeValue := this._TypeValue()
            lastIndex := Max(1, this._SelIndex("DropDownIndexCombo") + 1)
            callValue := this._CallValue()
        }
        EnableIndex := typeValue != 1
        this._ComboPush("DropDownIndexCombo", "IsEnabled", EnableIndex ? "True" : "False")
        if (EnableIndex) {
            tableItem := this._TableByMacroType(macroTypes[typeValue])
            DropDownArr := []
            if (tableItem) {
                for i, item in tableItem.Items {
                    DropDownArr.Push(i ". " item.Remark)
                }
            }
            this._ComboPush("DropDownIndexCombo", "ClearItems", "")
            for it in DropDownArr
                this._ComboPush("DropDownIndexCombo", "AddItem", it)
            if (DropDownArr.Length >= lastIndex)
                this._ComboPush("DropDownIndexCombo", "SelectedIndex", String(lastIndex - 1))
            else if (DropDownArr.Length >= 1)
                this._ComboPush("DropDownIndexCombo", "SelectedIndex", "0")
        } else {
            this._ComboPush("DropDownIndexCombo", "ClearItems", "")
        }

        this._ComboPush("InsertRow", "Visibility", (callValue == 1) ? "Visible" : "Collapsed")
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveSubMacroData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this.ToggleFunc(false)
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        tableItem := this._TableByMacroType(this.ui.Query("TypeCombo"))
        itemArr := this._TypeValue() == 1 ? "" : (tableItem ? tableItem.Items : "")

        if (itemArr != "") {
            idx := this._SelIndex("DropDownIndexCombo") + 1
            if (idx > itemArr.Length || idx == 0) {
                RmtDialog.Info(GetLang("配置无效，序号不正确"))
                return false
            }
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveSubMacroData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            OperTipArr := GetLangArr(["调用", "触发", "暂停", "取消暂停", "终止"])
            IntervarlStr := MainSoftData.Lang == "中文" ? "" : " "
            MacroTypeArr := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "语音宏", "定时宏", "宏", "网络宏"])
            OperStr := OperTipArr[this._CallValue()]
            TypeStr := MacroTypeArr[this._TypeValue()]
            SerialStr := this._TypeValue() == 1 ? "" : (this._SelIndex("DropDownIndexCombo") + 1)
            Remark := OperStr IntervarlStr TypeStr SerialStr
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "语音宏", "定时宏", "宏", "网络宏"])
        callKeys := ["插入到当前宏", "触发", "暂停", "取消暂停", "终止"]
        this.Data.MacroType := GetLangKey(macroTypes[this._TypeValue()])
        this.Data.Index := this._SelIndex("DropDownIndexCombo") + 1
        this.Data.CallType := callKeys[this._CallValue()]
        this.Data.InsertCount := GetLangKey(this.ui.Query("InsertCountCombo"))

        tableItem := this._TableByMacroType(this.Data.MacroType)
        itemArr := this._TypeValue() == 1 ? "" : (tableItem ? tableItem.Items : "")
        this.Data.MacroSerial := itemArr != "" && this.Data.Index >= 1 && this.Data.Index <= itemArr.Length
            ? itemArr[this.Data.Index].ID : ""
        SaveMacroCMDData(this.Data)
    }

    _LangArrIndex(arr, langKey) {
        target := GetLang(langKey)
        loop arr.Length {
            if (arr[A_Index] == target)
                return A_Index
        }
        return 1
    }

    _CallValueFromData() {
        k := IsObject(this.Data) ? GetLangKey(this.Data.CallType) : ""
        if (k == "插入到当前宏" || k == "调用")
            return 1
        displayCall := GetLangArr(["调用", "触发", "暂停", "取消暂停", "终止"])
        return this._LangArrIndex(displayCall, k)
    }

    ; 宏类型语言键（按键宏/字串宏…）→ 表 Symbol（Normal/String…）
    _TableByMacroType(macroType) {
        k := GetLangKey(macroType)
        if (k == "" || k == "当前宏")
            return ""
        t := GetTableBySymbol(k)
        if (t)
            return t
        typeMap := Map("按键宏", "Normal", "字串宏", "String", "菜单宏", "Menu", "界面宏", "UI", "语音宏", "Voice", "定时宏", "Timing", "宏", "SubMacro", "网络宏", "Network")
        if (typeMap.Has(k)) {
            t := GetTableBySymbol(typeMap[k])
            if (t)
                return t
        }
        global MySoftData
        if (IsObject(MySoftData) && MySoftData.HasProp("TableInfo")) {
            for tableItem in MySoftData.TableInfo {
                if (tableItem.Name == k || GetLang(tableItem.Name) == GetLang(k))
                    return tableItem
            }
        }
        return ""
    }
}
