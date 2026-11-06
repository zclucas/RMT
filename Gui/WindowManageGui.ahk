#Requires AutoHotkey v2.0
#Include WinRuleGui.ahk

; =====================================================================
; 窗口管理编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 数据流：GetMacroCMDData / SaveMacroCMDData / this.Data.* 与原生一致
; 联动：操作类型下拉切换 坐标/大小/标题/透明度 行显隐（原生 OnActionChange 等价迁移）
; =====================================================================

class WindowManageGui {
    __new() {
        this.CmdKey := "窗口管理"
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.MyFrontInfoGui := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this._syncing := false
        this.Data := ""
        this.SerialStr := ""

        this.ActionTypeArr := WindowCommandActions(this.CmdKey)
        this._updatingMode := false
        ; 显隐联动行容器名（OnActionChange 用，对应原生 RelateArrCon 控件组）
        this.PosRelateArrCon := ["PosRelateRow"]
        this.SizeRelateArrCon := ["SizeRelateRow"]
        this.ResultRelateArrCon := ["ResultRelateRow"]
        this.TitleRelateArrCon := ["TitleRelateRow"]
        this.TransparencyRelateArrCon := ["TransparencyRelateRow"]
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

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)   ; XAML 窗口不支持隐藏复用：关旧重建
            this._CloseWindow()
        this.ActionTypeArr := WindowCommandActions(this.CmdKey)
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._syncing := true
        this._batching := true
        try {
            this.Init(cmd)
            this.OnActionChange()
        } finally {
            this._flushBatch()
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
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
        title := this.ParentTile GetLang(this.CmdKey) GetLang("编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,36")
        body.Rows("36", "36", "Auto", "36", "48")
        body.Cols("108", "*", "16", "80", "*")

        ; 行0：操作类型 + 备注（白底，内边距与下拉框一致）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang(this.CmdKey == "窗口信息" ? "查询类别：" : "操作类别：")).VerticalAlignment("Center")
        act := body.Add("ComboBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(4).Name("ActionTypeCon").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in this.ActionTypeArr
            act.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(3).Grid_Column(1).Grid_ColumnSpan(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：窗口信息
        wiRow := body.Add("Grid").Grid_Row(1).Grid_ColumnSpan(5)
        wiRow.Cols("108", "*", "8", "70")
        wiRow.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口绑定:")).VerticalAlignment("Center")
        wiRow.Add("TextBox").Grid_Column(1).Name("SearchValueCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        wiRow.Add("Button").Grid_Column(3).Name("WinInfoEditBtn").Content(GetLang("选择窗口")).Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行2：按操作类型顺序展开的附加项（Collapsed 后不占位）
        extra := body.Add("StackPanel").Grid_Row(2).Grid_ColumnSpan(5)

        modeRow := extra.Add("Grid").Name("WindowModeRow").Visibility("Collapsed")
        modeRow.Rows("36").Cols("108", "*")
        modeRow.Add("TextBlock").Grid_Column(0).Text(GetLang("模式：")).VerticalAlignment("Center")
        modeRow.Add("ComboBox").Grid_Column(1).Name("WindowModeCon").Height(26).MinHeight(26).VerticalAlignment("Center")

        closeRow := extra.Add("StackPanel").Name("CloseProcessRow").Visibility("Collapsed").Margin("0,6,0,6")
        closeRow.Add("TextBlock").Text(GetLang("勾选后结束所属进程及其所有窗口")).TextWrapping("Wrap").Margin("0,0,0,5")
        closeRow.Add("CheckBox").Name("CloseProcessCon").Content(GetLang("关闭进程")).ToolTip(GetLang("结束窗口所属进程及其所有窗口"))

        posRow := extra.Add("Grid").Name("PosRelateRow").Visibility("Collapsed")
        posRow.Rows("36")
        posRow.Cols("108", "*", "16", "108", "*")
        posRow.Add("TextBlock").Name("PosXLabel").Grid_Column(0).Text(GetLang("坐标X：")).VerticalAlignment("Center")
        posRow.Add("ComboBox").Grid_Column(1).Name("PosXCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        posRow.Add("TextBlock").Name("PosYLabel").Grid_Column(3).Text(GetLang("坐标Y：")).VerticalAlignment("Center")
        posRow.Add("ComboBox").Grid_Column(4).Name("PosYCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        resultRow := extra.Add("Grid").Name("ResultRelateRow").Visibility("Collapsed")
        resultRow.Rows("36")
        resultRow.Cols("108", "*", "16", "108", "*")
        resultRow.Add("TextBlock").Grid_Column(0).Text(GetLang("宽度变量：")).VerticalAlignment("Center")
        resultRow.Add("ComboBox").Grid_Column(1).Name("WidthVarNameCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        resultRow.Add("TextBlock").Grid_Column(3).Text(GetLang("高度变量：")).VerticalAlignment("Center")
        resultRow.Add("ComboBox").Grid_Column(4).Name("HeightVarNameCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        sizeRow := extra.Add("Grid").Name("SizeRelateRow").Visibility("Collapsed")
        sizeRow.Rows("36")
        sizeRow.Cols("108", "*", "16", "108", "*")
        sizeRow.Add("TextBlock").Grid_Column(0).Text(GetLang("宽度：")).VerticalAlignment("Center")
        sizeRow.Add("ComboBox").Grid_Column(1).Name("WidthCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        sizeRow.Add("TextBlock").Grid_Column(3).Text(GetLang("高度：")).VerticalAlignment("Center")
        sizeRow.Add("ComboBox").Grid_Column(4).Name("HeightCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        titleRow := extra.Add("Grid").Name("TitleRelateRow").Visibility("Collapsed")
        titleRow.Rows("36")
        titleRow.Cols("108", "*", "16", "108", "*")
        titleRow.Add("TextBlock").Grid_Column(0).Text(GetLang("新标题：")).VerticalAlignment("Center")
        titleRow.Add("ComboBox").Grid_Column(1).Grid_ColumnSpan(4).Name("NewTitleCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        transRow := extra.Add("Grid").Name("TransparencyRelateRow").Visibility("Collapsed")
        transRow.Rows("36")
        transRow.Cols("108", "*", "16", "108", "*")
        transRow.Add("TextBlock").Grid_Column(0).Text(GetLang("透明度：")).VerticalAlignment("Center")
        transRow.Add("ComboBox").Grid_Column(1).Name("TransparencyCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        extra.Add("TextBlock").Name("ActionHint").TextWrapping("Wrap").Margin("0,6,0,8").Opacity(0.75)
        results := extra.Add("Grid").Name("InfoResultsGrid").Visibility("Collapsed")
        results.Rows("Auto", "Auto", "Auto", "Auto").Cols("*", "16", "*")
        Loop 7 {
            row := results.Add("Grid").Name("InfoResultRow" A_Index).Grid_Row((A_Index - 1) // 2).Grid_Column(Mod(A_Index - 1, 2) * 2).Visibility("Collapsed")
            row.Rows("36").Cols("108", "*")
            row.Add("TextBlock").Name("InfoResultLabel" A_Index).Grid_Column(0).VerticalAlignment("Center")
            row.Add("ComboBox").ToolTip(GetLang("填写保存结果的变量名；留空则跳过")).Name("InfoResultCon" A_Index).Grid_Column(1).Height(26).MinHeight(26).MaxDropDownHeight(220).IsEditable("True").IsTextSearchEnabled("False").VerticalAlignment("Center")
        }

        ; 行3：确定
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="640" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/23-窗口管理", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("WindowModeCon", "SelectionChanged", ObjBindMethod(this, "OnActionChange"))
        this.ui.OnEvent("ActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnActionChange"))
        this.ui.OnEvent("WinInfoEditBtn", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

    }

    ; ---------------- 数据填充辅助 ----------------

    _SetCombo(comboName, items, text) {
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        this._ComboPush(comboName, "Text", text)
    }

    SetConArrState(ConArr, isEnabled, state) {
        prop := isEnabled ? "IsEnabled" : "Visibility"
        val := isEnabled ? (state ? "True" : "False") : (state ? "Visible" : "Collapsed")
        for name in ConArr
            this._ComboPush(name, prop, val)
    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVariableArr := GetGuiVarArr()
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr(this.CmdKey)
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        WindowEnsureResults(this.Data)
        this._resultAction := this.Data.ActionType
        this._ComboPush("CloseProcessCon", "IsChecked", this.Data.CloseProcess ? "True" : "False")
        Loop 7 {
            prop := "ResultVar" A_Index
            this._SetCombo("InfoResultCon" A_Index, DLVariableArr, this.Data.%prop%)
        }
        ; 操作类型：按 GetLangKey 匹配选中项（兼容非中文语言）；无匹配保持未选中（与原生 DDL.Text 行为一致）
        actIdx := -1
        for i, it in this.ActionTypeArr {
            if (GetLangKey(it) == WindowActionGroup(this.Data.ActionType)) {
                actIdx := i - 1
                break
            }
        }
        this._ComboPush("ActionTypeCon", "SelectedIndex", String(actIdx))
        this._FillModes(WindowActionGroup(this.Data.ActionType), this.Data.ActionType)
        this._ComboPush("SearchValueCon", "Text", this.Data.SearchValue)
        this._SetCombo("PosXCon", DLVariableArr, this.Data.PosX)
        this._SetCombo("PosYCon", DLVariableArr, this.Data.PosY)
        this._SetCombo("WidthCon", DLVariableArr, this.Data.Width)
        this._SetCombo("HeightCon", DLVariableArr, this.Data.Height)
        this._SetCombo("WidthVarNameCon", DLVariableArr, this.Data.WidthVarName)
        this._SetCombo("HeightVarNameCon", DLVariableArr, this.Data.HeightVarName)
        this._SetCombo("NewTitleCon", DLVariableArr, this.Data.NewTitle)
        this._SetCombo("TransparencyCon", DLVariableArr, this.Data.Transparency)
        ; 透明度：原生在变量项之后追加 0%~100% 列表
        for p in ["0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"]
            this._ComboPush("TransparencyCon", "AddItem", p)
    }

    _FillModes(group, action := "") {
        this._updatingMode := true
        this._modeGroup := group
        try {
            modes := WindowGroupModes(group)
            this._ComboPush("WindowModeCon", "ClearItems", "")
            for mode in modes
                this._ComboPush("WindowModeCon", "AddItem", mode)
            this._ComboPush("WindowModeCon", "SelectedIndex", String(action == "" ? 0 : WindowModeIndex(action)))
            this._ComboPush("WindowModeRow", "Visibility", modes.Length ? "Visible" : "Collapsed")
        } finally {
            this._updatingMode := false
        }
    }

    _SelectedAction() {
        return WindowActionFromMode(GetLangKey(this.ui.Query("ActionTypeCon")), this.ui.Query("WindowModeCon"))
    }

    OnActionChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || this._updatingMode || (this._syncing && state != ""))
            return
        ; 同步阶段 Query 可能尚未生效，改用 Data；加载后 SelectionChanged 再按控件值刷新
        if (this._syncing && IsObject(this.Data) && this.Data.ActionType != "")
            actionType := GetLang(this.Data.ActionType)
        else {
            group := GetLangKey(this.ui.Query("ActionTypeCon"))
            if (ctrl == "ActionTypeCon" && (!this.HasOwnProp("_modeGroup") || this._modeGroup != group)) {
                this._FillModes(group)
                actionType := GetLang(WindowGroupActions(group)[1])
            } else
                actionType := GetLang(this._SelectedAction())
        }
        actionKey := GetLangKey(actionType)
        if (!this._syncing && this.HasOwnProp("_resultAction") && this._resultAction != actionKey) {
            Loop 7 {
                name := "InfoResultCon" A_Index
                value := this.ui.Query(name)
                nextValue := WindowNextResultName(value, this._resultAction, actionKey, A_Index)
                if (nextValue != value)
                    this._ComboPush(name, "Text", nextValue)
            }
        }
        this._resultAction := actionKey
        this._ComboPush("CloseProcessRow", "Visibility", actionType == GetLang("关闭窗口") ? "Visible" : "Collapsed")
        isShowPos := (actionType == GetLang("移动窗口") || actionType == GetLang("相对移动") || actionType == GetLang("位置和宽高"))
        isShowSize := (actionType == GetLang("调整宽高") || actionType == GetLang("位置和宽高"))
        isShowResult := (actionType == GetLang("获取窗口宽高"))
        isShowTitle := (actionType == GetLang("修改标题"))
        isShowTransparency := (actionType == GetLang("修改透明度"))

        this._ComboPush("PosXLabel", "Text", actionType == GetLang("相对移动") ? GetLang("偏移X：") : GetLang("坐标X："))
        this._ComboPush("PosYLabel", "Text", actionType == GetLang("相对移动") ? GetLang("偏移Y：") : GetLang("坐标Y："))
        this._ComboPush("ActionHint", "Text", GetLang(WindowEditorHint(GetLangKey(actionType))))
        fields := WindowInfoFields(GetLangKey(actionType))
        this._ComboPush("InfoResultsGrid", "Visibility", fields.Length ? "Visible" : "Collapsed")
        if (fields.Length) {
            resultText := this._syncing ? this.Data.ResultVar1 : this.ui.Query("InfoResultCon1")
            this._SetCombo("InfoResultCon1", GetLangKey(actionType) == "匹配窗口列表" ? GetGuiArrNameArr() : GetGuiVarArr(), resultText)
        }
        Loop 7 {
            this._ComboPush("InfoResultRow" A_Index, "Visibility", A_Index <= fields.Length ? "Visible" : "Collapsed")
            if (A_Index <= fields.Length) {
                this._ComboPush("InfoResultLabel" A_Index, "Text", GetLang(fields[A_Index]) (GetLangKey(actionType) == "匹配窗口列表" ? "：" : GetLang("变量：")))
                this._ComboPush("InfoResultLabel" A_Index, "ToolTip", GetLang(WindowInfoFieldTip(actionKey, A_Index)))
            }
        }
        this.SetConArrState(this.PosRelateArrCon, false, isShowPos)
        this.SetConArrState(this.SizeRelateArrCon, false, isShowSize)
        this.SetConArrState(this.ResultRelateArrCon, false, isShowResult)
        this.SetConArrState(this.TitleRelateArrCon, false, isShowTitle)
        this.SetConArrState(this.TransparencyRelateArrCon, false, isShowTransparency)
    }

    CheckIfValid() {
        actionType := IsObject(this.ui) ? GetLang(this._SelectedAction()) : ""
        if (this.ui.Query("SearchValueCon") == "") {
            RmtDialog.Info(GetLang("窗口绑定不能为空"))
            return false
        }

        if (actionType == GetLang("获取窗口宽高")
            && (Trim(this.ui.Query("WidthVarNameCon")) == "" || Trim(this.ui.Query("HeightVarNameCon")) == "")) {
            RmtDialog.Info(GetLang("请输入变量名！"), "", "Owner" this.Hwnd())
            return false
        }
        fields := WindowInfoFields(GetLangKey(actionType))
        hasResult := false
        usedNames := Map()
        for i, label in fields {
            name := GetVarName(this.ui.Query("InfoResultCon" i))
            if (name != "") {
                hasResult := true
                if (usedNames.Has(name)) {
                    RmtDialog.Info(GetLang("不同结果请使用不同的变量名"), "", "Owner" this.Hwnd())
                    return false
                }
                usedNames[name] := true
            }
        }
        if (fields.Length && !hasResult) {
            RmtDialog.Info(GetLang("请至少填写一个结果变量"), "", "Owner" this.Hwnd())
            return false
        }
        numericFields := Map()
        if (actionType == GetLang("移动窗口") || actionType == GetLang("相对移动") || actionType == GetLang("位置和宽高")) {
            numericFields["PosXCon"] := "坐标X"
            numericFields["PosYCon"] := "坐标Y"
        }
        if (actionType == GetLang("调整宽高") || actionType == GetLang("位置和宽高")) {
            numericFields["WidthCon"] := "宽度"
            numericFields["HeightCon"] := "高度"
        }
        if (actionType == GetLang("修改透明度"))
            numericFields["TransparencyCon"] := "透明度"
        for control, label in numericFields {
            value := Trim(this.ui.Query(control))
            errorText := WindowNumericInputError(label, value)
            if (errorText != "") {
                RmtDialog.Info(GetLang(errorText), "", "Owner" this.Hwnd())
                return false
            }
        }
        if (actionType == GetLang("修改标题")) {
            if (this.ui.Query("NewTitleCon") == "") {
                RmtDialog.Info(GetLang("新标题不能为空！"), "", "Owner" this.Hwnd())
                return false
            }
        }

        return true
    }

    SaveData() {
        this.Data.ActionType := this._SelectedAction()
        this.Data.CloseProcess := this.ui.Query("CloseProcessCon") == "True"
        Loop 7 {
            prop := "ResultVar" A_Index
            this.Data.%prop% := GetVarName(this.ui.Query("InfoResultCon" A_Index))
        }
        WindowRegisterResults(this.Data)
        this.Data.SearchValue := this.ui.Query("SearchValueCon")
        this.Data.PosX := this.ui.Query("PosXCon")
        this.Data.PosY := this.ui.Query("PosYCon")
        this.Data.Width := this.ui.Query("WidthCon")
        this.Data.Height := this.ui.Query("HeightCon")
        this.Data.WidthVarName := GetVarName(this.ui.Query("WidthVarNameCon"))
        this.Data.HeightVarName := GetVarName(this.ui.Query("HeightVarNameCon"))
        if (this.Data.ActionType == "获取窗口宽高") {
            if (this.Data.WidthVarName != "")
                MySoftData.GlobalVariMap[this.Data.WidthVarName] := true
            if (this.Data.HeightVarName != "")
                MySoftData.GlobalVariMap[this.Data.HeightVarName] := true
        }
        this.Data.NewTitle := this.ui.Query("NewTitleCon")
        this.Data.Transparency := StrReplace(this.ui.Query("TransparencyCon"), "%")
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            Hotkey("!l", MacroAction, "On")
        }
        else {
            Hotkey("!l", MacroAction, "Off")
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveData()
        this.ToggleFunc(false)
        action := this.SureBtnAction
        if (action != "")
            action(this.GetCommandStr())
        this.OnGuiClose()
    }

    OnClickWinEditBtn(state := "", ctrl := "", event := "") {
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "SearchValueCon"))
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
        try this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnGuiClose() {
        this._CloseWindow()
    }
}

WindowCommandActions(key) {
    info := ["位置与宽高", "标题类名句柄", "进程信息", "窗口状态", "匹配窗口列表"]
    actions := ["窗口操作", "移动窗口", "调整尺寸", "显示状态", "置顶", "修改标题", "修改透明度", "鼠标穿透"]
    if (key == "窗口信息")
        return GetLangArr(info)
    if (key == "窗口管理") {
        for action in info
            actions.Push(action)
    }
    return GetLangArr(actions)
}
