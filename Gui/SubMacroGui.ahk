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
        title := this.ParentTile GetLang("宏操作编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8")
        body.Rows("34", "36", "36", "26", "26", "*")
        body.Cols("80", "120", "80", "200")

        ; 行0：快捷方式 + 执行指令 + 备注
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：宏类型 + 宏序号
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("宏类型：")).VerticalAlignment("Center")
        tc := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("TypeCombo").Height(26).MinHeight(26)
        for t in GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "定时宏", "宏"])
            tc.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(1).Grid_Column(2).Text(GetLang("宏序号：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(3).Name("DropDownIndexCombo").Height(26).MinHeight(26)

        ; 行2：操作类型 + 插入次数
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("操作类型:")).VerticalAlignment("Center")
        ct := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("CallTypeCombo").Height(26).MinHeight(26)
        for c in GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
            ct.Add("ComboBoxItem").Content(c)
        insertRow := body.Add("StackPanel").Name("InsertRow").Grid_Row(2).Grid_Column(2).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        insertRow.Add("TextBlock").Text(GetLang("插入次数：")).VerticalAlignment("Center")
        insertRow.Add("ComboBox").Name("InsertCountCombo").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 行3-4：提示
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(4).Text(GetLang("插入到当前宏: 指定宏 按插入次数 插入到当前宏")).VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(4).Grid_ColumnSpan(4).Text(GetLang("触发: 运行指定宏，指定宏和当前宏同时执行")).VerticalAlignment("Center")

        ; 行5：确定
        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="500" Height="235" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("CallTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
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

    _SelIndex(comboName) {
        v := IsObject(this.ui) ? this.ui.Query(comboName ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    _TypeValue() => this._SelIndex("TypeCombo") + 1
    _CallValue() => this._SelIndex("CallTypeCombo") + 1

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("宏操作")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(2)

        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "定时宏", "宏"])
        callTypes := GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        this.ui.Update("TypeCombo", "SelectedIndex", String(this._LangArrIndex(macroTypes, this.Data.MacroType) - 1))
        this.ui.Update("CallTypeCombo", "SelectedIndex", String(this._LangArrIndex(callTypes, this.Data.CallType) - 1))
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
        if (!IsObject(this.ui))
            return
        this._syncing := true
        try {
            macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "定时宏", "宏"])
            typeValue := this._TypeValue()
            EnableIndex := typeValue != 1
            this.ui.Update("DropDownIndexCombo", "IsEnabled", EnableIndex ? "True" : "False")
            if (EnableIndex) {
                lastIndex := Max(1, this._SelIndex("DropDownIndexCombo") + 1)
                tableItem := GetTableBySymbol(GetLangKey(macroTypes[typeValue]))
                DropDownArr := []
                if (tableItem) {
                    for i, item in tableItem.Items {
                        DropDownArr.Push(i ". " item.Remark)
                    }
                }
                this.ui.Update("DropDownIndexCombo", "ClearItems", "")
                for it in DropDownArr
                    this.ui.Update("DropDownIndexCombo", "AddItem", it)
                if (DropDownArr.Length >= lastIndex)
                    this.ui.Update("DropDownIndexCombo", "SelectedIndex", String(lastIndex - 1))
                else if (DropDownArr.Length >= 1)
                    this.ui.Update("DropDownIndexCombo", "SelectedIndex", "0")
            } else {
                this.ui.Update("DropDownIndexCombo", "ClearItems", "")
            }

            ShowInsert := this._CallValue() == 1
            this.ui.Update("InsertRow", "Visibility", ShowInsert ? "Visible" : "Collapsed")
        } finally {
            this._syncing := false
        }
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
        tableItem := GetTableBySymbol(GetLangKey(this.ui.Query("TypeCombo")))
        itemArr := this._TypeValue() == 1 ? "" : (tableItem ? tableItem.Items : "")

        if (itemArr != "") {
            idx := this._SelIndex("DropDownIndexCombo") + 1
            if (idx > itemArr.Length || idx == 0) {
                MsgBox(GetLang("配置无效，序号不正确"))
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
            OperTipArr := GetLangArr(["插入", "触发", "暂停", "取消暂停", "终止"])
            IntervarlStr := MainSoftData.Lang == "中文" ? "" : " "
            MacroTypeArr := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "定时宏", "宏"])
            OperStr := OperTipArr[this._CallValue()]
            TypeStr := MacroTypeArr[this._TypeValue()]
            SerialStr := this._TypeValue() == 1 ? "" : (this._SelIndex("DropDownIndexCombo") + 1)
            Remark := OperStr IntervarlStr TypeStr SerialStr
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "界面宏", "定时宏", "宏"])
        callTypes := GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        this.Data.MacroType := GetLangKey(macroTypes[this._TypeValue()])
        this.Data.Index := this._SelIndex("DropDownIndexCombo") + 1
        this.Data.CallType := GetLangKey(callTypes[this._CallValue()])
        this.Data.InsertCount := GetLangKey(this.ui.Query("InsertCountCombo"))

        tableItem := GetTableBySymbol(this.Data.MacroType)
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
}
