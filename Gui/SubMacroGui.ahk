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
        this._callKeys := []
        this._targetIDs := []
        this._targetType := ""
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
        this._callKeys := []
        this._targetType := ""
        try {
            this.Init(cmd)
            this.OnRefresh()
        } finally {
            this._flushBatch()
        }
        ui := this.ui
        opened := XamlWin.Open(ui, "", XamlWin.Owner(this))
        if (this.ui != ui)
            return
        if (opened)
            this.ToggleFunc(true)
        else
            this._CloseWindow()
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
        for t in GetLangArr(SubMacroGui.MacroTypes())
            tc.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("宏序号：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(4).Name("DropDownIndexCombo").Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行2：操作类型 + 调用次数（仅调用时显示在操作类型后）
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("操作类型:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("CallTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
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
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/33-宏操作", XamlWin.BindCurrent(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", XamlWin.BindCurrent(this, "OnRefresh"))
        this.ui.OnEvent("CallTypeCombo", "SelectionChanged", XamlWin.BindCurrent(this, "RefreshCallCount"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._syncing := false
    }

    OnWindowClosing(*) {
        this.ui := ""
        this._closed := true
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        ui := this.ui
        this.OnWindowClosing()
        if (IsObject(ui))
            try ui.Update("Window", "Close", "")
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

    _CallKey(selectedIndex) {
        index := Integer(selectedIndex) + 1
        return this._callKeys.Has(index) ? this._callKeys[index] : ""
    }

    static MacroTypes() {
        types := ["当前宏"]
        for def in MacroCategoryDefs() {
            if (def[1] != "Replace")
                types.Push(def[2])
        }
        return types
    }

    static Targets(macroType) {
        targets := []
        tables := GetTablesBySymbol(MacroTypeSymbol(macroType))
        for tableItem in tables {
            prefix := tables.Length > 1 ? GetLang(tableItem.Name) " · " : ""
            for i, item in tableItem.Items {
                label := prefix i ". " item.Remark
                if (tableItem.Symbol == "Gesture" && item.TK != "")
                    label .= " [" GestureDisplay(item.TK) "]"
                targets.Push({ID: item.ID, Label: label})
            }
        }
        return targets
    }

    static CallKeys(currentMacro) {
        return currentMacro
            ? ["循环-跳过本轮", "循环-跳出", "分支-跳出", "插入到当前宏", "暂停", "终止"]
            : ["插入到当前宏", "触发", "暂停", "取消暂停", "终止"]
    }

    static CallLabel(key) {
        switch key {
            case "插入到当前宏": return GetLang("调用")
            case "循环-跳过本轮": return GetLang("循环-跳出本轮")
            case "分支-跳出": return GetLang("分支跳出")
            default: return GetLang(key)
        }
    }

    static CallIndex(macroType, callKey) {
        for i, key in this.CallKeys(macroType == "当前宏") {
            if (key == callKey)
                return i - 1
        }
        return -1
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("宏操作")
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr("count")

        macroTypes := GetLangArr(SubMacroGui.MacroTypes())
        this._ComboPush("TypeCombo", "SelectedIndex", String(this._LangArrIndex(macroTypes, this.Data.MacroType) - 1))
        this._SetCombo("InsertCountCombo", this.DLVariableArr, GetLang(this.Data.InsertCount))
    }

    ToggleFunc(state) {
        if (state) {
            try Hotkey("!l", XamlWin.BindCurrent(this, "TriggerMacro"), "On")
        } else {
            try Hotkey("!l", "Off")
        }
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        ui := this.ui
        if (!IsObject(ui) || (this._syncing && state != ""))
            return
        macroTypes := SubMacroGui.MacroTypes()
        if (this._syncing && IsObject(this.Data)) {
            typeValue := this._LangArrIndex(GetLangArr(macroTypes), this.Data.MacroType)
            callKey := GetLangKey(this.Data.CallType)
            if (callKey == "调用")
                callKey := "插入到当前宏"
        } else {
            values := ui.Query("TypeCombo>SelectedIndex", "CallTypeCombo>SelectedIndex")
            if (this.ui != ui || values.Count != 2)
                return
            typeValue := Max(1, Integer(values["TypeCombo>SelectedIndex"]) + 1)
            callKey := this._CallKey(values["CallTypeCombo>SelectedIndex"])
        }
        currentMacro := typeValue == 1
        if (!this._callKeys.Length || currentMacro != this._currentMacro) {
            this._currentMacro := currentMacro
            this._callKeys := SubMacroGui.CallKeys(currentMacro)
            selectedIndex := this._syncing ? -1 : 0
            this._ComboPush("CallTypeCombo", "ClearItems", "")
            for i, key in this._callKeys {
                this._ComboPush("CallTypeCombo", "AddItem", SubMacroGui.CallLabel(key))
                if (key == callKey)
                    selectedIndex := i - 1
            }
            this._ComboPush("CallTypeCombo", "SelectedIndex", String(selectedIndex))
        }
        macroType := macroTypes[typeValue]
        if (this._targetType != macroType) {
            this._targetType := macroType
            this._targetIDs := []
            this._ComboPush("DropDownIndexCombo", "IsEnabled", currentMacro ? "False" : "True")
            this._ComboPush("DropDownIndexCombo", "ClearItems", "")
            selectedIndex := -1
            targetID := this._syncing && this.Data.HasOwnProp("MacroSerial") ? this.Data.MacroSerial : ""
            for i, item in SubMacroGui.Targets(macroType) {
                this._targetIDs.Push(item.ID)
                this._ComboPush("DropDownIndexCombo", "AddItem", item.Label)
                if (item.ID == targetID)
                    selectedIndex := i - 1
            }
            this._ComboPush("DropDownIndexCombo", "SelectedIndex", String(selectedIndex))
        }

        if (this._syncing)
            this._ComboPush("InsertRow", "Visibility", (callKey == "插入到当前宏") ? "Visible" : "Collapsed")
        else
            this.RefreshCallCount()
    }

    RefreshCallCount(*) {
        ui := this.ui
        if (!IsObject(ui) || this._syncing)
            return
        index := ui.Query("CallTypeCombo>SelectedIndex")
        if (this.ui == ui && IsInteger(index))
            this._ComboPush("InsertRow", "Visibility", (this._CallKey(index) == "插入到当前宏") ? "Visible" : "Collapsed")
    }

    OnClickSureBtn(state, ctrl, event) {
        ui := this.ui
        if (!this.Hwnd())
            return
        action := this.SureBtnAction
        CommandStr := this.SaveSubMacroData()
        if (CommandStr == "" || this.ui != ui)
            return
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid(macroType, callKey, targetIndex, &target) {
        target := ""
        if (this._targetType != macroType || SubMacroGui.CallIndex(macroType, callKey) < 0) {
            RmtDialog.Info(GetLang("请选择操作类型"))
            return false
        }
        if (macroType != "当前宏") {
            if (this._targetIDs.Has(targetIndex)) {
                targetID := this._targetIDs[targetIndex]
                tableItem := GetMacroTypeTargetTable(macroType, targetID)
                if (tableItem)
                    target := ResolveMacroItem(tableItem.ID, targetID)
            }
            if (!target) {
                RmtDialog.Info(GetLang("宏不存在"))
                return false
            }
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        ui := this.ui
        if (!this.Hwnd())
            return
        CommandStr := this.SaveSubMacroData()
        if (CommandStr != "" && this.ui == ui)
            OnTriggerSepcialItemMacro(CommandStr)
    }

    GetCommandStr(Remark) {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        if (ShouldAutoGenerateRemark(Remark)) {
            IntervarlStr := MainSoftData.Lang == "简中" ? "" : " "
            OperStr := SubMacroGui.CallLabel(this.Data.CallType)
            TypeStr := GetLang(this.Data.MacroType)
            SerialStr := this.Data.MacroType == "当前宏" ? "" : this.Data.Index
            Remark := OperStr IntervarlStr TypeStr SerialStr
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        ui := this.ui
        if (!IsObject(ui))
            return ""
        hwnd := ui.wpfHwnd
        values := ui.Query("TypeCombo>SelectedIndex", "CallTypeCombo>SelectedIndex", "DropDownIndexCombo>SelectedIndex", "InsertCountCombo", "RemarkCon")
        if (this.ui != ui || ui.wpfHwnd != hwnd || values.Count != 5)
            return ""
        macroType := SubMacroGui.MacroTypes()[Max(1, Integer(values["TypeCombo>SelectedIndex"]) + 1)]
        callKey := this._CallKey(values["CallTypeCombo>SelectedIndex"])
        targetIndex := Integer(values["DropDownIndexCombo>SelectedIndex"]) + 1
        if (!this.CheckIfValid(macroType, callKey, targetIndex, &target))
            return ""
        this.Data.MacroType := macroType
        this.Data.Index := target ? target.Index : 0
        this.Data.CallType := callKey
        this.Data.InsertCount := GetLangKey(values["InsertCountCombo"])

        this.Data.MacroSerial := target ? target.Item.ID : ""
        CommandStr := this.GetCommandStr(values["RemarkCon"])
        SaveMacroCMDData(this.Data)
        return CommandStr
    }

    _LangArrIndex(arr, langKey) {
        target := GetLang(langKey)
        loop arr.Length {
            if (arr[A_Index] == target)
                return A_Index
        }
        return 1
    }

}
