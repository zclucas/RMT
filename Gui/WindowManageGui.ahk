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
        this._positionPick := ""
        this.Data := ""
        this.SerialStr := ""

        this.ActionTypeArr := WindowCommandActions(this.CmdKey)
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

    _EscapeXml(s) => EscapeXamlXml(s)

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
        updates := this._batch
        this._batch := []
        if (IsObject(this.ui) && updates.Length > 0)
            this.ui.BatchUpdate(updates)
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
        isAdjust := this.CmdKey == "调整窗口"
        isInfo := this.CmdKey == "窗口信息"
        compactLayout := isAdjust || isInfo
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,16")
        body.Rows("36", "36", compactLayout ? "Auto" : "36", "Auto", "48")
        labelWidth := compactLayout ? Ceil(XAMLHost.FontSize() * (MainSoftData.Lang == "中文" ? 5 : 7)) : 108
        fieldCols := [labelWidth, "*", "16", labelWidth, "*"]
        pairCols := [labelWidth, "180", "8", "180"]
        body.Cols(fieldCols*)

        body.Add("TextBlock").Grid_Row(compactLayout ? 0 : 2).Grid_Column(0).Text(GetLang(compactLayout ? "类型：" : "操作类别：")).VerticalAlignment("Center")
        act := body.Add("ComboBox").Grid_Row(compactLayout ? 0 : 2).Grid_Column(1).Name("ActionTypeCon").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in this.ActionTypeArr
            act.Add("ComboBoxItem").Content(t)

        body.Add("TextBlock").Grid_Row(0).Grid_Column(compactLayout ? 3 : 0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(compactLayout ? 4 : 1).Grid_ColumnSpan(compactLayout ? 1 : 4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("窗口绑定：")).VerticalAlignment("Center")
        wiRow := body.Add("Grid").Grid_Row(1).Grid_Column(1).Grid_ColumnSpan(compactLayout ? 1 : 4)
        wiRow.Cols("*", "6", "28")
        wiRow.Add("TextBox").Grid_Column(0).Name("SearchValueCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        wiRow.Add("Button").Grid_Column(2).Name("WinInfoEditBtn").Content(Chr(0xE70F)).ToolTip(GetLang("编辑"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .Height(26).MinHeight(26).Padding("0").Cursor("Hand").VerticalAlignment("Center")

        if (compactLayout) {
            body.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("匹配方式：")).VerticalAlignment("Center")
            body.Add("ComboBox").Grid_Row(1).Grid_Column(4).Name("MatchModeCon").Height(26).MinHeight(26).VerticalAlignment("Center")
        }

        modeRow := body.Add("Grid").Grid_Row(2).Grid_Column(isAdjust ? 0 : 3).Grid_ColumnSpan(2).Name("WindowModeRow").Height(36).Visibility("Collapsed")
        modeRow.Cols(labelWidth, "*")
        modeRow.Add("TextBlock").Grid_Column(0).Text(GetLang("模式：")).VerticalAlignment("Center")
        modeRow.Add("ComboBox").Grid_Column(1).Name("WindowModeCon").Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 按操作类别显示参数
        extra := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(5)
        transRow := extra.Add("Grid").Name("TransparencyRelateRow").Height(36).Visibility("Collapsed")
        transRow.Cols(fieldCols*)
        transRow.Add("TextBlock").Grid_Column(0).Text(GetLang("透明度：")).VerticalAlignment("Center")
        transRow.Add("ComboBox").Grid_Column(1).Name("TransparencyCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        closeProcess := isAdjust
            ? body.Add("CheckBox").Grid_Row(2).Grid_Column(4)
            : extra.Add("CheckBox").Height(36).Margin("108,0,0,0")
        closeProcess.Name("CloseProcessCon").Content(GetLang("关闭进程")).Visibility("Collapsed")
            .ToolTip(GetLang("结束窗口所属进程及其所有窗口")).VerticalAlignment("Center")

        posRow := extra.Add("Grid").Name("PosRelateRow").Visibility("Collapsed")
        posRow.Rows("36")
        posRow.Cols(pairCols*)
        posRow.Add("TextBlock").Name("PositionLabel").Grid_Column(0).VerticalAlignment("Center")
        for i, axis in ["X", "Y"] {
            posRow.Add("ComboBox").Grid_Column(i == 1 ? 1 : 3).Name("Pos" axis "Con").Height(26).MinHeight(26)
                .ToolTip(axis).IsEditable("True").VerticalAlignment("Center")
        }

        resultRow := extra.Add("Grid").Name("ResultRelateRow").Visibility("Collapsed")
        resultRow.Rows("36")
        resultRow.Cols(fieldCols*)
        resultRow.Add("TextBlock").Grid_Column(0).Text(GetLang("宽度变量：")).VerticalAlignment("Center")
        resultRow.Add("ComboBox").Grid_Column(1).Name("WidthVarNameCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        resultRow.Add("TextBlock").Grid_Column(3).Text(GetLang("高度变量：")).VerticalAlignment("Center")
        resultRow.Add("ComboBox").Grid_Column(4).Name("HeightVarNameCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        sizeRow := extra.Add("Grid").Name("SizeRelateRow").Visibility("Collapsed")
        sizeRow.Rows("36")
        sizeRow.Cols(pairCols*)
        sizeRow.Add("TextBlock").Grid_Column(0).Text(GetLang("宽高：")).VerticalAlignment("Center")
        sizeRow.Add("ComboBox").Grid_Column(1).Name("WidthCon").Height(26).MinHeight(26).ToolTip(GetLang("宽度：")).IsEditable("True").VerticalAlignment("Center")
        sizeRow.Add("ComboBox").Grid_Column(3).Name("HeightCon").Height(26).MinHeight(26).ToolTip(GetLang("高度：")).IsEditable("True").VerticalAlignment("Center")

        titleRow := extra.Add("Grid").Name("TitleRelateRow").Visibility("Collapsed")
        titleRow.Rows("36")
        titleRow.Cols(fieldCols*)
        titleRow.Add("TextBlock").Grid_Column(0).Text(GetLang("新标题：")).VerticalAlignment("Center")
        titleRow.Add("ComboBox").Grid_Column(1).Grid_ColumnSpan(4).Name("NewTitleCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        results := extra.Add("Grid").Name("InfoResultsGrid").Visibility("Collapsed")
        results.Rows("Auto", "Auto", "Auto", "Auto").Cols("*", "16", "*")
        Loop 7 {
            row := results.Add("Grid").Name("InfoResultRow" A_Index).Grid_Row((A_Index - 1) // 2).Grid_Column(Mod(A_Index - 1, 2) * 2).Visibility("Collapsed")
            row.Rows("36").Cols(labelWidth, "*")
            row.Add("TextBlock").Name("InfoResultLabel" A_Index).Grid_Column(0).VerticalAlignment("Center")
            row.Add("ComboBox").ToolTip(GetLang("填写保存结果的变量名；留空则跳过")).Name("InfoResultCon" A_Index).Grid_Column(1).Height(26).MinHeight(26).MaxDropDownHeight(220).IsEditable("True").IsTextSearchEnabled("False").VerticalAlignment("Center")
        }
        extra.Add("TextBlock").Name("ActionHint").TextWrapping("Wrap").Margin("0,6,0,8").Opacity(0.75)

        ; 确定
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
        if (isAdjust)
            this.ui.OnEvent("BtnCmdTargeter", "Click", ObjBindMethod(this, "StartPositionPick"))
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
        if (this.CmdKey == "调整窗口" || this.CmdKey == "窗口信息") {
            matchMode := this.Data.HasProp("MatchMode") ? this.Data.MatchMode
                : this.CmdKey == "调整窗口" ? WindowDefaultMatchMode(this.Data.ActionType, InStr(this.Data.SearchValue, "❖")) : ""
            this._FillMatchModes(this.Data.ActionType, matchMode)
        }
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

    _FillMatchModes(action, selected := "") {
        isAdjust := this.CmdKey == "调整窗口"
        modes := WindowMatchModes(isAdjust || action == "匹配窗口列表")
        matchIndex := isAdjust ? 1 : 0
        this._ComboPush("MatchModeCon", "ClearItems", "")
        for i, mode in modes {
            this._ComboPush("MatchModeCon", "AddItem", GetLang(mode))
            if (mode == selected)
                matchIndex := i - 1
        }
        this._ComboPush("MatchModeCon", "SelectedIndex", String(matchIndex))
    }

    _FillModes(group, action := "") {
        this._modeGroup := group
        modes := WindowGroupModes(group)
        hasModes := modes.Length > 0
        this._ComboPush("WindowModeCon", "ClearItems", "")
        for mode in modes
            this._ComboPush("WindowModeCon", "AddItem", mode)
        this._ComboPush("WindowModeCon", "SelectedIndex", String(hasModes ? WindowModeIndex(action) : -1))
        this._ComboPush("WindowModeRow", "Visibility", hasModes ? "Visible" : "Collapsed")
    }

    _SelectedAction() {
        return WindowActionFromMode(GetLangKey(this.ui.Query("ActionTypeCon")), this.ui.Query("WindowModeCon"))
    }

    OnActionChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        groupChanged := false
        if (this._syncing) {
            actionKey := this.Data.ActionType
        } else {
            group := GetLangKey(this.ui.Query("ActionTypeCon"))
            groupChanged := this._modeGroup != group
            actionKey := groupChanged ? WindowGroupActions(group)[1] : WindowActionFromMode(group, this.ui.Query("WindowModeCon"))
            ; 回填模式也会触发 SelectionChanged，当前动作已渲染时跳过。
            if (!groupChanged && actionKey == this._resultAction)
                return
        }
        wasBatching := this._batching
        this._batching := true
        try {
            if (groupChanged)
                this._FillModes(group)
            this._RefreshAction(actionKey)
        } finally {
            if (!wasBatching)
                this._flushBatch()
        }
    }

    _RefreshAction(actionKey) {
        if (IsObject(this._positionPick) && this._positionPick.Action != actionKey)
            this._EndPositionPick()
        if (!this._syncing && this.CmdKey == "窗口信息" && ((this._resultAction == "匹配窗口列表") != (actionKey == "匹配窗口列表")))
            this._FillMatchModes(actionKey)
        if (!this._syncing && this._resultAction != actionKey && (this._resultAction == "窗口状态" || actionKey == "窗口状态")) {
            Loop 7 {
                name := "InfoResultCon" A_Index
                value := this.ui.Query(name)
                nextValue := WindowNextResultName(value, this._resultAction, actionKey, A_Index)
                if (A_Index == 1)
                    resultText := nextValue
                if (nextValue != value)
                    this._ComboPush(name, "Text", nextValue)
            }
        }
        this._resultAction := actionKey
        this._ComboPush("CloseProcessCon", "Visibility", actionKey == "关闭窗口" ? "Visible" : "Collapsed")
        isShowPos := actionKey == "移动窗口" || actionKey == "相对移动" || actionKey == "位置和宽高"
        isShowSize := actionKey == "调整宽高" || actionKey == "位置和宽高"
        isShowResult := actionKey == "获取窗口宽高"
        isShowTitle := actionKey == "修改标题"
        isShowTransparency := actionKey == "修改透明度"

        this._ComboPush("PositionLabel", "Text", GetLang(actionKey == "相对移动" ? "偏移值" : "坐标值") "：")
        if (this.CmdKey == "调整窗口") {
            this._ComboPush("BtnCmdTargeter", "Visibility", isShowPos ? "Visible" : "Collapsed")
            this._ComboPush("BtnCmdTargeter", "ToolTip", GetLang(actionKey == "相对移动" ? "选取偏移值" : "选取坐标"))
        }
        this._ComboPush("ActionHint", "Text", GetLang(WindowEditorHint(actionKey)))
        fields := WindowInfoFields(actionKey)
        this._ComboPush("InfoResultsGrid", "Visibility", fields.Length ? "Visible" : "Collapsed")
        if (fields.Length) {
            resultText := resultText ?? (this._syncing ? this.Data.ResultVar1 : this.ui.Query("InfoResultCon1"))
            this._SetCombo("InfoResultCon1", actionKey == "匹配窗口列表" ? GetGuiArrNameArr() : GetGuiVarArr(), resultText)
        }
        Loop 7 {
            this._ComboPush("InfoResultRow" A_Index, "Visibility", A_Index <= fields.Length ? "Visible" : "Collapsed")
            if (A_Index <= fields.Length) {
                suffix := this.CmdKey == "窗口信息" || actionKey == "匹配窗口列表" ? "：" : GetLang("变量：")
                this._ComboPush("InfoResultLabel" A_Index, "Text", GetLang(fields[A_Index]) suffix)
                this._ComboPush("InfoResultLabel" A_Index, "ToolTip", GetLang(WindowInfoFieldTip(actionKey, A_Index)))
            }
        }
        this.SetConArrState(this.PosRelateArrCon, false, isShowPos)
        this.SetConArrState(this.SizeRelateArrCon, false, isShowSize)
        this.SetConArrState(this.ResultRelateArrCon, false, isShowResult)
        this.SetConArrState(this.TitleRelateArrCon, false, isShowTitle)
        this.SetConArrState(this.TransparencyRelateArrCon, false, isShowTransparency)
    }

    StartPositionPick(*) {
        if (!IsObject(this.ui) || IsObject(this._positionPick) || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        action := this._SelectedAction()
        if (action != "移动窗口" && action != "相对移动" && action != "位置和宽高")
            return
        this._positionPick := {Action: action, Origin: ""}
        try {
            SetSystemCursor("CROSS")
            Hotkey("*LButton", ObjBindMethod(this, "_PickPosition"), "On")
            Hotkey("*RButton", ObjBindMethod(this, "_EndPositionPick"), "On")
            Hotkey("Escape", ObjBindMethod(this, "_EndPositionPick"), "On")
            prompt := action == "相对移动" ? "请点击偏移起点，右键或 Esc 取消" : "请点击选取坐标，右键或 Esc 取消"
            ToolTip(GetLang(prompt), , , 20)
        } catch {
            this._EndPositionPick()
        }
    }

    _PickPosition(*) {
        pick := this._positionPick
        if (!IsObject(pick))
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y, &hwnd)
        if (hwnd && DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") == this.Hwnd()) {
            this._EndPositionPick()
            return
        }
        if (pick.Action == "相对移动" && !IsObject(pick.Origin)) {
            pick.Origin := {X: x, Y: y}
            ToolTip(GetLang("请点击偏移终点，右键或 Esc 取消"), , , 20)
            return
        }
        this._EndPositionPick()
        if (IsObject(pick.Origin)) {
            x -= pick.Origin.X
            y -= pick.Origin.Y
        }
        this.ui.BatchUpdate([
            {ControlName: "PosXCon", PropertyName: "Text", Value: String(x)},
            {ControlName: "PosYCon", PropertyName: "Text", Value: String(y)}
        ])
    }

    _EndPositionPick(*) {
        if (!IsObject(this._positionPick))
            return
        this._positionPick := ""
        try Hotkey("*LButton", "Off")
        try Hotkey("*RButton", "Off")
        try Hotkey("Escape", "Off")
        try SetSystemCursor()
        ToolTip(, , , 20)
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
        if (this.CmdKey == "调整窗口" || this.CmdKey == "窗口信息")
            this.Data.MatchMode := GetLangKey(this.ui.Query("MatchModeCon"))
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
        this._EndPositionPick()
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
        this._EndPositionPick()
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
