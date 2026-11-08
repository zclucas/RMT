#Requires AutoHotkey v2.0

; =====================================================================
; 等待编辑器（§16）—— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 七类等待共用条件编辑入口，时间等待与区间判断复用时间执行逻辑。
; =====================================================================

class WaitGui {
    static MinScreenAreaSize := 4
    static ProcessTargetTypes := ["进程名", "PID"]
    static ConfirmModes := ["继续", "继续&终止&暂停"]
    static ConfirmOptions := [
        ["PauseType", "交互时:", ["暂停当前宏", "暂停所有宏"]],
        ["TimeoutAction", "超时后:", ["无", "自动继续", "自动终止", "自动暂停"]],
        ["TerminateType", "终止时:", ["终止当前宏", "终止所有宏"]],
        ["PauseBtnType", "暂停时:", ["暂停当前宏", "暂停所有宏"]]
    ]

    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this.Data := ""
        this.SerialStr := ""
        this.DLVariableArr := []
        this.WaitTypeKeys := []
        this._currentGroup := ""
        this._loading := false
        this._areaPreview := ScreenAreaPreview(WaitGui.MinScreenAreaSize)
        this._previewShowing := false
        this._areaAction := ""
        this._confirmHotkeys := []
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._loading := true
        try this.Init(cmd)
        finally this._loading := false
        this.OnTypeChange()
        this._ShowWindow()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        if (this.HasProp("_timeRange"))
            this.DeleteProp("_timeRange")
        title := this.ParentTile GetLang("等待编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,12,16,16")
        body.Rows("Auto", "Auto", "Auto", "Auto")
        body.Cols("Auto", "Auto", "*")

        ; 行0：类型 + 条件 + 备注
        typeGroup := body.Add("StackPanel").Grid_Row(0).Grid_Column(0).Orientation("Horizontal").Margin("0,0,12,8")
        typeGroup.Add("TextBlock").Text(GetLang("类型：")).VerticalAlignment("Center")
        wt := typeGroup.Add("ComboBox").Name("WaitTypeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
            .BorderThickness("1").BorderBrush("{DynamicResource InputStroke}")
        for t in GetLangArr(WaitGroupNames())
            wt.Add("ComboBoxItem").Content(t)
        conditionGroup := body.Add("StackPanel").Grid_Row(0).Grid_Column(1).Orientation("Horizontal").Margin("0,0,16,8")
        conditionGroup.Add("TextBlock").Name("WaitConditionLabel").Text(GetLang("条件：")).VerticalAlignment("Center")
        conditionGroup.Add("ComboBox").Name("WaitConditionCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
            .BorderThickness("1").BorderBrush("{DynamicResource InputStroke}")
        remarkGroup := body.Add("Grid").Grid_Row(0).Grid_Column(2).Margin("0,0,24,8")
        remarkGroup.Cols("Auto", "*")
        remarkGroup.Add("TextBlock").Name("WaitRemarkLabel").Text(GetLang("备注：")).VerticalAlignment("Center")
        remarkGroup.Add("TextBox").Grid_Column(1).Name("RemarkCon").Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        ; 行1：参数直接排版，不显示分组标题或外框。
        pStack := body.Add("Grid").Grid_Row(1).Grid_ColumnSpan(3).Margin("0,6,0,2")

        vp := pStack.Add("StackPanel").Name("VarPanel").Visibility("Collapsed")
        logicRow := vp.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,6")
        logicRow.Add("TextBlock").Text(GetLang("条件关系：")).VerticalAlignment("Center")
        this._Choice(logicRow, "VarLogicCon", CmdEnumLogicNames(), 80).Margin("4,0,0,0")
        listBorder := vp.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .CornerRadius("4").Padding("8,4")
        list := listBorder.Add("StackPanel")
        scroll := list.Add("ScrollViewer").Name("VarScroll").Height(120)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        scroll.Add("StackPanel").Name("VarRows")
        this._ConditionButton(list, "BtnAddVar", 0xE710, "添加").Margin("0,2")

        ; 按键面板
        kp := pStack.Add("StackPanel").Name("KeyPanel").HorizontalAlignment("Center").Visibility("Collapsed")
        keyRow := kp.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
        keyRow.Add("TextBlock").Text(GetLang("按键：")).VerticalAlignment("Center")
        keyRow.Add("TextBox").Name("KeyCon").Width(240).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        ; 与主界面触发键入口使用相同的字形。
        for entry in [["BtnPickKey", 0xE92E, "键盘按键选择"], ["BtnPickJoy", 0xE7FC, "手柄按键选择"]] {
            keyRow.Add("Button").Name(entry[1]).Content(Chr(entry[2])).ToolTip(GetLang(entry[3]))
                .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(18)
                .Width(42).Height(26).MinHeight(26).Margin("6,0,0,0").Padding("0").Cursor("Hand")
        }
        keyOptions := kp.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,8,0,0")
        keyOptions.Add("TextBlock").Text(GetLang("检测模式:")).VerticalAlignment("Center")
        this._Choice(keyOptions, "KeyCheckTypeCon", [], 140).Margin("4,0,0,0")
        keyOptions.Add("TextBlock").Text(GetLang("检测类型:")).VerticalAlignment("Center").Margin("14,0,0,0")
        this._Choice(keyOptions, "KeyStateTypeCon", CmdEnumStateNames(), 120).Margin("4,0,0,0")

        ; 范围面板：起始X/Y、终止X/Y
        rp := pStack.Add("Grid").Name("RangePanel").HorizontalAlignment("Center").Visibility("Collapsed")
        rp.Rows("30", "30")
        rp.Cols("Auto", "Auto", "Auto")
        preview := rp.Add("Button").Name("BtnPreviewArea").Grid_RowSpan(2).Cursor("Hand")
            .ToolTip(GetLang("框选范围预览")).Padding("6,0").Margin("0,0,8,0")
            .HorizontalContentAlignment("Left").VerticalContentAlignment("Stretch")
            .Tag("0").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        preview.InjectResources(ScreenAreaPreview.ButtonStyle())
        labels := preview.Add("Grid").IsHitTestVisible("False")
        labels.Rows("*", "*")
        labels.Add("TextBlock").Text(GetLang("起始坐标：")).VerticalAlignment("Center")
        labels.Add("TextBlock").Grid_Row(1).Text(GetLang("终止坐标：")).VerticalAlignment("Center")
        for i, endpoint in ["Start", "End"] {
            for j, axis in ["X", "Y"] {
                rp.Add("ComboBox").Grid_Row(i - 1).Grid_Column(j).Name(endpoint "Pos" axis)
                    .Width(120).Height(26).MinHeight(26).VerticalAlignment("Center")
                    .Margin(j == 2 ? "8,0,0,0" : "0").IsEditable("True")
                    .ToolTip(GetLang((i == 1 ? "起始坐标" : "终止坐标") axis "："))
            }
        }

        ; 进程面板
        pp := pStack.Add("Grid").Name("ProcPanel").HorizontalAlignment("Center").Visibility("Collapsed")
        pp.Cols("Auto", "124", "8", "240")
        pp.Add("TextBlock").Text(GetLang("匹配方式：")).VerticalAlignment("Center").Margin("0,0,4,0")
        this._Choice(pp, "ProcTargetTypeCon", WaitGui.ProcessTargetTypes, 124).Grid_Column(1)
        pp.Add("ComboBox").Grid_Column(3).Name("ProcCon").Height(26).MinHeight(26)
            .IsEditable("True").IsTextSearchEnabled("False")
        pp.Add("ComboBox").Grid_Column(3).Name("ProcPidCon").Height(26).MinHeight(26)
            .IsEditable("True").IsTextSearchEnabled("False").Visibility("Collapsed")

        ; 窗口面板
        wp := pStack.Add("StackPanel").Name("WinPanel").Orientation("Horizontal").HorizontalAlignment("Center").Visibility("Collapsed")
        wp.Add("TextBlock").Text(GetLang("窗口绑定：")).VerticalAlignment("Center")
        wp.Add("TextBox").Name("WinInfoCon").Width(314).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        wp.Add("Button").Name("BtnWinEdit").Content(Chr(0xE70F)).ToolTip(GetLang("编辑"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .Width(28).Height(26).MinHeight(26).Margin("6,0,0,0").Padding("0").Cursor("Hand")

        ; 文件面板
        fp := pStack.Add("StackPanel").Name("FilePanel").Orientation("Horizontal").HorizontalAlignment("Center").Visibility("Collapsed")
        fp.Add("TextBlock").Text(GetLang("文件路径：")).VerticalAlignment("Center")
        fp.Add("TextBox").Name("FilePathCon").Width(240).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        fp.Add("Button").Name("BtnFileBrowse").Content(GetLang("浏览")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")

        hint := pStack.Add("TextBlock").Name("HintPanel").TextWrapping("Wrap").Visibility("Collapsed")
            .Foreground("{DynamicResource TextMain}").HorizontalAlignment("Center").VerticalAlignment("Center").TextAlignment("Center")

        tp := pStack.Add("StackPanel").Name("TimePanel").Width(532).HorizontalAlignment("Center").Visibility("Collapsed")
        timeCols := ["56", "168", "16", "56", "168"]
        tr := tp.Add("Grid").HorizontalAlignment("Center")
        tr.Cols(timeCols*)
        tr.Add("TextBlock").Name("TimeModeLabel").Text(GetLang("模式：")).VerticalAlignment("Center")
        this._Choice(tr, "TimeKindCon", [], 168).Grid_Column(1)
        targetRow := tr.Add("Grid").Name("TimeTargetFields").Grid_Column(3).Grid_ColumnSpan(2)
        targetRow.Cols("Auto", "*")
        targetRow.Add("TextBlock").Name("TimeValueLabel").Text(GetLang("目标：")).VerticalAlignment("Center").Margin("0,0,4,0")
        targetRow.Add("ComboBox").Grid_Column(1).Name("TimeValueCon").Height(26).MinHeight(26).IsEditable("True")
        tr.Add("CheckBox").Grid_Column(3).Grid_ColumnSpan(2).Name("TimeWaitOutsideCon")
            .Content(GetLang("在区间外继续")).VerticalAlignment("Center").Visibility("Collapsed")
        rangeRow := tp.Add("Grid").Name("TimeRangeFields").HorizontalAlignment("Center").Margin("0,6,0,0")
        rangeRow.Cols(timeCols*)
        rangeRow.Add("TextBlock").Name("TimeStartLabel").Text(GetLang("开始：")).VerticalAlignment("Center")
        rangeRow.Add("ComboBox").Grid_Column(1).Name("TimeStartCon").Height(26).MinHeight(26).IsEditable("True")
        rangeRow.Add("TextBlock").Grid_Column(3).Name("TimeEndLabel").Text(GetLang("结束：")).VerticalAlignment("Center")
        rangeRow.Add("ComboBox").Grid_Column(4).Name("TimeEndCon").Height(26).MinHeight(26).IsEditable("True")
        tp.Add("TextBlock").Name("TimeHintCon").TextWrapping("Wrap").TextAlignment("Center").MinHeight(22).Margin("0,6,0,0")

        confirm := pStack.Add("StackPanel").Name("ConfirmPanel").Width(540).HorizontalAlignment("Center").Visibility("Collapsed")
        promptRow := confirm.Add("Grid").Margin("0,0,0,8")
        promptRow.Cols("112", "*")
        promptRow.Add("TextBlock").Text(GetLang("提示：")).VerticalAlignment("Center")
        promptRow.Add("TextBox").Name("ConfirmPrompt").Grid_Column(1).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for i, option in WaitGui.ConfirmOptions {
            if (Mod(i, 2)) {
                options := confirm.Add("Grid")
                options.Cols("112", "150", "16", "112", "150")
                if (i == 3)
                    options.Name("ConfirmExtra").Margin("0,8,0,0")
            }
            column := Mod(i, 2) ? 0 : 3
            options.Add("TextBlock").Grid_Column(column).Text(GetLang(option[2])).VerticalAlignment("Center")
            this._Choice(options, "Confirm" option[1], option[3], 150).Grid_Column(column + 1)
        }

        ; 日期面板：仅用于读取旧字段，新编辑统一使用时间面板
        dp := pStack.Add("StackPanel").Name("DatePanel").Orientation("Horizontal").Visibility("Collapsed")
        dp.Add("TextBlock").Name("DateValLabel").Text(GetLang("数值：")).VerticalAlignment("Center")
        dp.Add("ComboBox").Name("DateValCon").Width(180).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        dp.Add("TextBlock").Text(GetLang("单位：")).VerticalAlignment("Center").Margin("12,0,0,0")
        dunit := dp.Add("ComboBox").Name("DateUnitCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
        for t in GetLangArr(["分钟", "小时", "天", "具体时间", "时间变量"])
            dunit.Add("ComboBoxItem").Content(t)

        ; 行2：检测间隔 + 超时 + 状态变量
        intervalGroup := body.Add("StackPanel").Name("WaitIntervalGroup").Grid_Row(2).Grid_Column(0).Orientation("Horizontal").Margin("0,14,12,0")
        intervalGroup.Add("TextBlock").Text(GetLang("检测间隔(ms)：")).VerticalAlignment("Center")
        intervalGroup.Add("TextBox").Name("IntervalCon").Width(72).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Tag("NumOnly|NoIME|MaxLen:6")
        timeoutGroup := body.Add("StackPanel").Grid_Row(2).Grid_Column(1).Orientation("Horizontal").Margin("0,14,16,0")
        timeoutGroup.Add("TextBlock").Name("WaitTimeoutLabel").Text(GetLang("超时(ms)：")).VerticalAlignment("Center").Margin("0,0,4,0")
        this._Choice(timeoutGroup, "TimeoutCon", ["不限时", "10000"], 115)
            .IsEditable("True").IsTextSearchEnabled("False").Tag("AllowPassive")
        statusGroup := body.Add("Grid").Grid_Row(2).Grid_Column(2).Margin("0,14,0,0")
        statusGroup.Cols("Auto", "*", "46", "46")
        statusGroup.Add("TextBlock").Name("WaitStatusLabel").Text(GetLang("状态变量：")).VerticalAlignment("Center").Margin("0,0,4,0")
        statusGroup.Add("ComboBox").Grid_Column(1).Name("TimeoutStatusCon").Height(26).MinHeight(26)
            .IsEditable("True").ToolTip(GetLang("变量名"))
        for field in [["WaitCompletedValueCon", "不超时", 2], ["WaitTimedOutValueCon", "超时", 3], ["WaitUnlimitedValueCon", "不超时", 2]] {
            valueBox := statusGroup.Add("TextBox").Grid_Column(field[3]).Name(field[1]).Height(26).MinHeight(26).Margin("6,0,0,0")
                .VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").ToolTip(GetLang(field[2]))
                .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
                .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            if (field[1] == "WaitUnlimitedValueCon")
                valueBox.Text("0").IsReadOnly("True")
            else
                valueBox.Visibility("Collapsed")
        }
        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(3).HorizontalAlignment("Center").Margin("0,12,0,0")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="760" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing", this.ui.id))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad", this.ui.id))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/等待", this.TriggerConfirmation.Bind(this), "!l", "", this.OnClickPickArea.Bind(this))
        this.ui.Update("BtnCmdF1", "ToolTip", GetLang("框选范围"))
        this.ui.OnEvent("WaitTypeCon", "SelectionChanged", ObjBindMethod(this, "OnGroupChange"))
        this.ui.OnEvent("WaitConditionCon", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("ProcTargetTypeCon", "SelectionChanged", this.OnProcessTargetChange.Bind(this))
        this.ui.Track("TimeoutCon")
        this.ui.OnEvent("TimeoutCon", "TextChanged", ObjBindMethod(this, "OnTimeoutChange"))
        this.ui.OnEvent("TimeKindCon", "SelectionChanged", ObjBindMethod(this, "OnTimeKindChange"))
        this.ui.OnEvent("BtnAddVar", "Click", ObjBindMethod(this, "OnAddCondition"))
        this.ui.Track("KeyCon")
        this.ui.OnEvent("KeyCon", "TextChanged", ObjBindMethod(this, "OnKeyTextChange"))
        this.ui.OnEvent("DateUnitCon", "SelectionChanged", ObjBindMethod(this, "OnDateUnitChange"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEdit"))
        this.ui.OnEvent("BtnFileBrowse", "Click", ObjBindMethod(this, "OnClickFileBrowse"))
        this.ui.OnEvent("BtnPickKey", "Click", ObjBindMethod(this, "OnClickPickKey", false))
        this.ui.OnEvent("BtnPickJoy", "Click", ObjBindMethod(this, "OnClickPickKey", true))
        this.ui.OnEvent("BtnPreviewArea", "Click", this.OnPreviewArea.Bind(this))
        for name in ["StartPosX", "StartPosY", "EndPosX", "EndPosY"]
            this.ui.OnEvent(name, "LostFocus", this.RefreshAreaPreview.Bind(this))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    _ShowWindow() {
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    OnWindowLoad(id, *) {
        if (!IsObject(this.ui) || this.ui.id != id)
            return
        XamlWin.OnLoadTheme(this.ui)
        this.OnTypeChange()
        this._RefreshTimeout(this.ui.Query("TimeoutCon"))
        this._SyncDateUnit()
        this._RebuildConditions(this._initialConditions)
    }

    OnWindowClosing(id, *) {
        if (!IsObject(this.ui) || this.ui.id != id)
            return
        this._BindConfirmHotkey(false)
        this._ClearAreaInteraction()
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
        this._BindConfirmHotkey(false)
        this._ClearAreaInteraction()
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        batch := []
        this._QueueCombo(batch, comboName, items, text)
        this.ui.BatchUpdate(batch)
    }

    _QueueCombo(batch, comboName, items, text) {
        batch.Push({ControlName: comboName, PropertyName: "ClearItems", Value: ""})
        for it in items {
            if (it == "")
                continue
            batch.Push({ControlName: comboName, PropertyName: "AddItem", Value: it})
        }
        batch.Push({ControlName: comboName, PropertyName: "Text", Value: text})
    }

    _TypeValue() {
        v := IsObject(this.ui) ? this.ui.Query("WaitConditionCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0 || Integer(v) >= this.WaitTypeKeys.Length)
            return ""
        if (this._currentGroup == "确定")
            return "等待确定"
        return CmdEnumFromIndex(v, this.WaitTypeKeys)
    }

    _PanelOf(t) {
        switch t {
            case "等待变量值":
                return "VarPanel"
            case "等待按键按下", "等待按键松开":
                return "KeyPanel"
            case "等待屏幕变化":
                return "RangePanel"
            case "等待鼠标移动", "等待鼠标停止移动", "等待剪切板变化":
                return "HintPanel"
            case "等待进程存在", "等待进程关闭":
                return "ProcPanel"
            case "等待窗口存在", "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口移动", "等待窗口关闭", "等待窗口最小化":
                return "WinPanel"
            case "等待文件存在", "等待文件删除", "等待文件变化":
                return "FilePanel"
            case "等待时间", "等待时间区间", "等待日期":
                return "TimePanel"
            case "等待确定":
                return "ConfirmPanel"
        }
        return ""
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("等待")
        this.Data := GetMacroCMDData(this.SerialStr)
        sourceKey := GetLangKey(RegExReplace(this.SerialStr, "\d+"))
        if (sourceKey == "时间") {
            old := this.Data
            this.Data := WaitData()
            this.Data.WaitType := TimeNormSubMode(old) == "区间判断" ? "等待时间区间" : "等待时间"
            this.Data.TimeConfig := JSON.parse(JSON.stringify(old), , false)
            this.Data.Interval := old.HasOwnProp("CheckInterval") ? old.CheckInterval : this.Data.Interval
            if (this.Data.WaitType == "等待时间" && old.HasOwnProp("Timeout"))
                this.Data.TimeoutMs := old.Timeout
            if (this.Data.WaitType == "等待时间区间")
                this.Data.TimeConfig.Param4 := TimeNormMismatch(old.HasProp("Param4") ? old.Param4 : "跳过")
            this.SerialStr := GetCMDSerialStr("等待")
            this.Data.SerialStr := this.SerialStr
        } else if (sourceKey == "等待确定") {
            old := this.Data
            this.Data := WaitData()
            this.Data.WaitType := "等待确定"
            this.Data.TimeoutMs := InputField(old, "TimeoutMs", 0)
            this.Data.ConfirmConfig.Type := InputField(old, "Type", "继续")
            this.Data.ConfirmConfig.Prompt := InputField(old, "Prompt", "")
            for option in WaitGui.ConfirmOptions {
                property := option[1]
                this.Data.ConfirmConfig.%property% := InputField(old, property, option[3][1])
            }
            this.SerialStr := GetCMDSerialStr("等待")
            this.Data.SerialStr := this.SerialStr
        }
        WaitEnsureData(this.Data)
        if (CmdEnumWait(this.Data.WaitType) == "等待日期") {
            this.Data.WaitType := "等待时间"
            unit := WaitNormDateUnit(this.Data.Param2)
            this.Data.TimeConfig.Param1 := this.Data.Param1
            this.Data.TimeConfig.Param2 := unit == "具体时间" ? "时刻" : (unit == "时间变量" ? "时间戳" : unit)
        }
        this.DLVariableArr := GetGuiVarArr(1)

        batch := []
        batch.Push({ControlName: "RemarkCon", PropertyName: "Text", Value: cmdArr.Length >= 2 ? cmdArr[2] : ""})
        confirm := this.Data.ConfirmConfig
        this._confirmMode := InputField(confirm, "Type", "继续")
        this._SelectType(CmdEnumWait(this.Data.WaitType))
        batch.Push({ControlName: "ConfirmPrompt", PropertyName: "Text", Value: InputField(confirm, "Prompt", "")})
        for option in WaitGui.ConfirmOptions {
            selected := InputField(confirm, option[1], option[3][1])
            batch.Push({ControlName: "Confirm" option[1], PropertyName: "SelectedIndex", Value: CmdEnumIndex(selected, option[3])})
        }
        batch.Push({ControlName: "IntervalCon", PropertyName: "Text", Value: this.Data.Interval})
        timeout := this.Data.TimeoutMs > 0 ? String(this.Data.TimeoutMs) : GetLang("不限时")
        batch.Push({ControlName: "TimeoutCon", PropertyName: "Text", Value: timeout})
        batch.Push({ControlName: "WaitCompletedValueCon", PropertyName: "Text", Value: this.Data.WaitCompletedValue})
        batch.Push({ControlName: "WaitTimedOutValueCon", PropertyName: "Text", Value: this.Data.WaitTimedOutValue})
        resultName := this.Data.ResultSaveName == "" ? GetLang("超时状态") : this.Data.ResultSaveName
        this._QueueCombo(batch, "TimeoutStatusCon", GetGuiVarArr(), resultName)
        keyWait := this._PanelOf(CmdEnumWait(this.Data.WaitType)) == "KeyPanel"
        this._pickedKeyText := keyWait ? this.Data.Param1 : ""
        this._pickedKeys := keyWait ? this.Data.KeyOptions.KeyArr : []
        this._keyDevice := keyWait ? this.Data.KeyDevice : "键盘"
        this._keyModes := []
        this._keyModeLabels := []
        batch.Push({ControlName: "KeyCon", PropertyName: "Text", Value: this._pickedKeyText})
        procWait := this._PanelOf(CmdEnumWait(this.Data.WaitType)) == "ProcPanel"
        processMode := procWait ? this.Data.ProcessTargetType : "进程名"
        name := procWait && processMode == "进程名" && this.Data.Param1 != "" ? this.Data.Param1 : "notepad.exe"
        pid := procWait && processMode == "PID" ? this.Data.Param1 : ""
        this._QueueCombo(batch, "ProcCon", this.DLVariableArr, name)
        this._QueueCombo(batch, "ProcPidCon", this.DLVariableArr, pid)
        batch.Push({ControlName: "ProcTargetTypeCon", PropertyName: "SelectedIndex",
            Value: CmdEnumIndex(processMode, WaitGui.ProcessTargetTypes)})
        winWait := this._PanelOf(CmdEnumWait(this.Data.WaitType)) == "WinPanel"
        batch.Push({ControlName: "WinInfoCon", PropertyName: "Text", Value: this.Data.Param1 == "" && !winWait ? "{宏设置窗口绑定}" : this.Data.Param1})
        batch.Push({ControlName: "FilePathCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "DateValCon", PropertyName: "Text", Value: this.Data.Param1})
        this.ui.BatchUpdate(batch)
        this._RefreshTimeout(timeout)
        ; 坐标与下拉数据
        this._SetCombo("StartPosX", GetGuiVarArr(), this.Data.StartPosX)
        this._SetCombo("StartPosY", GetGuiVarArr(), this.Data.StartPosY)
        this._SetCombo("EndPosX", GetGuiVarArr(), this.Data.EndPosX)
        this._SetCombo("EndPosY", GetGuiVarArr(), this.Data.EndPosY)
        ; 日期单位（Param2 存中文键）
        unitKey := GetLangKey(this.Data.Param2)
        unitIdx := 0
        for k, key in ["分钟", "小时", "天", "具体时间", "时间变量"] {
            if (key == unitKey) {
                unitIdx := k - 1
                break
            }
        }
        if (IsObject(this.ui))
            this.ui.Update("DateUnitCon", "SelectedIndex", String(unitIdx))
        this._initialConditions := this.Data.Conditions
        if (!this._initialConditions.Length) {
            varWait := CmdEnumWait(this.Data.WaitType) == "等待变量值"
            this._initialConditions := [{Variable: varWait ? this.Data.Param1 : "", Operator: "等于", Value: varWait ? this.Data.Param2 : ""}]
        }
        this._Choose("VarLogicCon", this.Data.ConditionLogic, CmdEnumLogicNames())
        cfg := this.Data.TimeConfig
        range := CmdEnumWait(this.Data.WaitType) == "等待时间区间"
        legacyUnit := GetLangKey(cfg.Param2)
        kind := range ? TimeNormWindowType(cfg.Param5) : ((legacyUnit == "分钟" || legacyUnit == "小时" || legacyUnit == "天") ? legacyUnit : TimeNormWaitType(cfg.Param2 == "" ? "时长" : cfg.Param2))
        this._FillTimeKinds(range, kind)
        this._timeValues := Map()
        this._timeValueKey := ""
        saved := []
        if (cfg.Param1 != "")
            saved.Push(kind == "时间戳" ? this._NormalizeTimestampText(cfg.Param1) : cfg.Param1)
        second := range ? cfg.Param2 : InputField(cfg, "RandomMaxMs", "")
        if ((range || kind == "毫秒-随机") && second != "") {
            saved.Length := 2
            saved[2] := kind == "时间戳" ? this._NormalizeTimestampText(second) : second
        }
        if (saved.Length)
            this._timeValues[(range ? "区间" : "等待") kind] := saved
        for name in ["TimeValueCon", "TimeStartCon", "TimeEndCon"]
            this._SetCombo(name, GetGuiVarArr(), "")
        this.ui.Update("TimeWaitOutsideCon", "IsChecked", InputField(cfg, "WaitOutside", false) ? "True" : "False")
        this._RefreshTimeTarget(range, kind)
        this._FillKeyModes(this._pickedKeyText, keyWait ? this.Data.KeyOptions.CheckType : "")
        this._Choose("KeyStateTypeCon", keyWait ? this.Data.KeyOptions.StateType : "物理状态", CmdEnumStateNames())
    }

    ; 按类型显隐参数面板
    OnTypeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || this._loading)
            return
        t := this._TypeValue()
        show := this._PanelOf(t)
        batch := []
        for name in ["VarPanel", "KeyPanel", "RangePanel", "ProcPanel", "WinPanel", "FilePanel", "DatePanel", "HintPanel", "TimePanel", "ConfirmPanel"] {
            reserve := (name == "RangePanel" && this._currentGroup == "屏幕与鼠标")
                || (name == "FilePanel" && this._currentGroup == "文件与剪切板")
            batch.Push({ControlName: name, PropertyName: "Visibility", Value: name == show ? "Visible" : (reserve ? "Hidden" : "Collapsed")})
        }
        confirmation := t == "等待确定"
        if (confirmation)
            this._confirmMode := GetLangKey(this.ui.Query("WaitConditionCon"))
        batch.Push({ControlName: "ConfirmExtra", PropertyName: "Visibility", Value: this._confirmMode == "继续&终止&暂停" ? "Visible" : "Hidden"})
        batch.Push({ControlName: "BtnCmdPlay", PropertyName: "Visibility", Value: confirmation ? "Visible" : "Collapsed"})
        batch.Push({ControlName: "BtnCmdF1", PropertyName: "Visibility", Value: show == "RangePanel" ? "Visible" : "Collapsed"})
        hint := WaitHintText(t)
        if (hint != "")
            batch.Push({ControlName: "HintPanel", PropertyName: "Text", Value: GetLang(hint)})
        this.ui.BatchUpdate(batch)
        this._BindConfirmHotkey(confirmation)
        if (show != "RangePanel")
            this._ClearAreaInteraction()
        if (show == "KeyPanel")
            this._FillKeyModes(this.ui.Query("KeyCon"))
        if (show == "ProcPanel")
            this.OnProcessTargetChange()
        if (show == "TimePanel") {
            range := t == "等待时间区间"
            kind := GetLangKey(this.ui.Query("TimeKindCon"))
            this._FillTimeKinds(range, kind)
            this.OnTimeKindChange()
        }
    }

    OnDateUnitChange(state := "", ctrl := "", event := "") {
        this._SyncDateUnit()
    }

    _ProcessTargetType() {
        return CmdEnumFromIndex(this.ui.Query("ProcTargetTypeCon>SelectedIndex"), WaitGui.ProcessTargetTypes)
    }

    OnProcessTargetChange(*) {
        if (!IsObject(this.ui) || this._loading)
            return
        byPid := this._ProcessTargetType() == "PID"
        this.ui.BatchUpdate([
            {ControlName: "ProcCon", PropertyName: "Visibility", Value: byPid ? "Collapsed" : "Visible"},
            {ControlName: "ProcPidCon", PropertyName: "Visibility", Value: byPid ? "Visible" : "Collapsed"}
        ])
    }

    _SyncDateUnit() {
        if (!IsObject(this.ui))
            return
        unit := WaitNormDateUnit(GetLangKey(this.ui.Query("DateUnitCon")))
        label := "数值："
        items := []
        if (unit == "具体时间")
            label := "日期时间："
        else if (unit == "时间变量") {
            label := "时间变量："
            items := this._DateVarItems()
        }
        cur := this.ui.Query("DateValCon")
        this.ui.Update("DateValLabel", "Text", GetLang(label))
        this._SetCombo("DateValCon", items, cur)
    }

    _DateVarItems() {
        seen := Map()
        items := []
        for src in [GetTimeVarArr(), GetGuiVarArr(1)] {
            for name in src {
                if (name != "" && !seen.Has(name)) {
                    seen[name] := true
                    items.Push(name)
                }
            }
        }
        return items
    }

    OnClickWinEdit(state := "", ctrl := "", event := "") {
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    OnClickFileBrowse(state := "", ctrl := "", event := "") {
        path := FileSelect(1, this.ui.Query("FilePathCon"), GetLang("选择文件"))
        if (path != "")
            this.ui.Update("FilePathCon", "Text", path)
    }

    OnClickPickKey(joy := false, *) {
        SetTimer(this._OpenKeyPicker.Bind(this, joy), -1)
    }

    _OpenKeyPicker(joy) {
        if (!IsObject(this.ui))
            return
        picker := joy ? JoyCheckGui() : KeyCheckGui()
        text := this.ui.Query("KeyCon")
        sameDevice := this._KeyDeviceFor(text) == (joy ? "手柄" : "键盘")
        picker.SelectionData := {KeyArr: sameDevice ? this._KeysFor(text) : []}
        picker.OwnerHwnd := this.Hwnd()
        id := this.ui.id
        picker.SureBtnAction := (*) => IsObject(this.ui) && this.ui.id == id && this._AcceptKeys(picker, joy)
        this._keyPicker := picker
        picker.ShowGui("")
    }

    _AcceptKeys(picker, joy) {
        if (!IsObject(this.ui))
            return
        keys := ""
        for key in picker.Data.KeyArr
            keys .= (keys == "" ? "" : "⎖") key
        this._keyDevice := joy ? "手柄" : "键盘"
        this._pickedKeyText := keys
        this._pickedKeys := picker.Data.KeyArr
        this.ui.Update("KeyCon", "Text", keys)
        this._FillKeyModes(keys)
    }

    _KeyDeviceFor(text) {
        if (text == this._pickedKeyText)
            return this._keyDevice
        return RegExMatch(text, "i)(?:^|⎖)[1-4]?Joy") || WaitKeysHaveAxis(GetPressKeyArr(text)) ? "手柄" : "键盘"
    }

    _KeysFor(text) {
        if (text == this._pickedKeyText && this._pickedKeys.Length)
            return this._pickedKeys.Clone()
        keys := []
        for key in GetPressKeyArr(text)
            if (Trim(key) != "")
                keys.Push(Trim(key))
        return keys
    }

    OnKeyTextChange(state, *) {
        if (IsObject(this.ui) && !this._loading && IsObject(state) && state.Has("KeyCon"))
            this._FillKeyModes(state["KeyCon"])
    }

    _FillKeyModes(text, selected := "") {
        analog := this._KeyDeviceFor(text) == "手柄" && WaitKeysHaveAxis(this._KeysFor(text))
        modes := analog ? CmdEnumJoyAnalogNames() : CmdEnumKeyCheckNames()
        release := !analog && this._TypeValue() == "等待按键松开"
        labels := release ? ["全部松开", "有一个松开"] : modes
        if (this._keyModeLabels.Length && this._keyModeLabels[1] == labels[1])
            return
        if (selected == "" && this._keyModes.Length)
            selected := CmdEnumFromIndex(this.ui.Query("KeyCheckTypeCon>SelectedIndex"), this._keyModes)
        this._keyModes := modes
        this._keyModeLabels := labels
        this.ui.Update("KeyCheckTypeCon", "ClearItems", "")
        for label in labels
            this.ui.Update("KeyCheckTypeCon", "AddItem", GetLang(label))
        this._Choose("KeyCheckTypeCon", selected, modes)
    }

    OnClickPickArea(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || this._TypeValue() != "等待屏幕变化" || IsObject(this._areaAction))
            return
        id := this.ui.id
        while (GetKeyState("LButton", "P"))
            Sleep(15)
        if (!IsObject(this.ui) || this.ui.id != id || this._TypeValue() != "等待屏幕变化")
            return
        action := this.OnAreaPicked.Bind(this, id)
        this._areaAction := action
        try TogSelectArea(true, action)
        finally {
            if (this._areaAction == action)
                this._areaAction := ""
        }
    }

    OnAreaPicked(id, x1, y1, x2, y2) {
        if (!IsObject(this.ui) || this.ui.id != id || this._TypeValue() != "等待屏幕变化")
            return
        if (Abs(x2 - x1) < WaitGui.MinScreenAreaSize || Abs(y2 - y1) < WaitGui.MinScreenAreaSize)
            return
        this._SetPreviewArea(x1, y1, x2, y2)
    }

    _SetPreviewArea(x1, y1, x2, y2) {
        this.ui.Update("StartPosX", "Text", x1)
        this.ui.Update("StartPosY", "Text", y1)
        this.ui.Update("EndPosX", "Text", x2)
        this.ui.Update("EndPosY", "Text", y2)
        this.RefreshAreaPreview()
    }

    OnPreviewArea(*) {
        if (this._TypeValue() != "等待屏幕变化")
            return
        this._previewShowing := !this._previewShowing
        this.ui.Update("BtnPreviewArea", "Tag", this._previewShowing ? "1" : "0")
        this.RefreshAreaPreview()
    }

    RefreshAreaPreview(*) {
        if (!this._previewShowing) {
            this._areaPreview.Hide()
            return
        }
        x1 := this.ui.Query("StartPosX"), y1 := this.ui.Query("StartPosY")
        x2 := this.ui.Query("EndPosX"), y2 := this.ui.Query("EndPosY")
        if (IsNumber(x1) && IsNumber(y1) && IsNumber(x2) && IsNumber(y2) && x1 != x2 && y1 != y2)
            this._areaPreview.Show(Min(x1, x2), Min(y1, y2), Abs(x2 - x1), Abs(y2 - y1), this._SetPreviewArea.Bind(this))
        else
            this._areaPreview.Hide()
    }

    _ClearAreaInteraction() {
        if (IsObject(this._areaAction) && MainSoftData.SelectAreaAction == this._areaAction)
            TogSelectArea(false)
        if (this._previewShowing && IsObject(this.ui))
            this.ui.Update("BtnPreviewArea", "Tag", "0")
        this._previewShowing := false
        this._areaPreview.Hide()
    }

    _BindConfirmHotkey(enable) {
        if (enable && !this._confirmHotkeys.Length && this.Hwnd())
            this._confirmHotkeys := WinHotkey.Register(["!l"], this.TriggerConfirmation.Bind(this), this.Hwnd())
        else if (!enable && this._confirmHotkeys.Length) {
            WinHotkey.UnregisterAll(this._confirmHotkeys)
            this._confirmHotkeys := []
        }
    }

    TriggerConfirmation(*) {
        if (this._TypeValue() == "等待确定" && this.CheckIfValid()) {
            this.SaveWaitData()
            OnTriggerSepcialItemMacro(this.GetCommandStr())
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        remark := this.ui.Query("RemarkCon")
        if (this._TypeValue() == "等待确定" && ShouldAutoGenerateRemark(remark))
            remark := this.ui.Query("WaitConditionCon")
        CommandStr := CorrectRemark(CommandStr, remark)
        return CommandStr
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveWaitData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        t := this._TypeValue()
        if (t == "") {
            RmtDialog.Info(GetLang("请选择等待条件"))
            return false
        }
        switch t {
            case "等待变量值":
                for condition in this._ReadConditions() {
                    if (!CheckVarNameIfValid(condition.Variable))
                        return false
                }
            case "等待按键按下", "等待按键松开":
                if (!this._KeysFor(Trim(this.ui.Query("KeyCon"))).Length) {
                    RmtDialog.Info(GetLang("请输入等待的按键"))
                    return false
                }
            case "等待进程存在", "等待进程关闭":
                byPid := this._ProcessTargetType() == "PID"
                target := Trim(this.ui.Query(byPid ? "ProcPidCon" : "ProcCon"))
                if (byPid && (target == "" || (IsNumber(target) && !WaitParsePid(target)))) {
                    RmtDialog.Info(GetLang("请输入有效的 PID 或变量名"))
                    return false
                }
                if (target == "") {
                    RmtDialog.Info(GetLang("请输入进程名"))
                    return false
                }
            case "等待窗口存在", "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口移动", "等待窗口关闭", "等待窗口最小化":
                if (this.ui.Query("WinInfoCon") == "") {
                    RmtDialog.Info(GetLang("窗口绑定不能为空"))
                    return false
                }
            case "等待文件存在", "等待文件删除", "等待文件变化":
                if (this.ui.Query("FilePathCon") == "") {
                    RmtDialog.Info(GetLang("请输入文件路径"))
                    return false
                }
            case "等待屏幕变化":
                if (!this._AreaOk())
                    return false
            case "等待时间", "等待时间区间":
                if (!this._ValidateTime())
                    return false
            case "等待日期":
                if (this.ui.Query("DateValCon") == "") {
                    RmtDialog.Info(GetLang("请输入日期值"))
                    return false
                }
                if (!this._DateOk())
                    return false
        }
        interval := this.ui.Query("IntervalCon")
        if (t != "等待确定" && (!IsNumber(interval) || Number(interval) <= 0)) {
            RmtDialog.Info(GetLang("检测间隔请输入大于0的数字（毫秒）"))
            return false
        }
        if (this._ParseTimeoutMs(this.ui.Query("TimeoutCon")) < 0) {
            RmtDialog.Info(GetLang("超时请输入 0 到 4294967295 的整数（毫秒）"))
            return false
        }
        return CheckVarNameIfValid(this.ui.Query("TimeoutStatusCon"))
    }

    OnTimeoutChange(state, *) {
        if (IsObject(this.ui) && IsObject(state) && state.Has("TimeoutCon"))
            this._RefreshTimeout(state["TimeoutCon"])
    }

    _RefreshTimeout(text) {
        unlimited := this._ParseTimeoutMs(text) == 0
        this.ui.BatchUpdate([
            {ControlName: "WaitUnlimitedValueCon", PropertyName: "Visibility", Value: unlimited ? "Visible" : "Collapsed"},
            {ControlName: "WaitCompletedValueCon", PropertyName: "Visibility", Value: unlimited ? "Collapsed" : "Visible"},
            {ControlName: "WaitTimedOutValueCon", PropertyName: "Visibility", Value: unlimited ? "Collapsed" : "Visible"}
        ])
    }

    _ParseTimeoutMs(text) {
        text := Trim(text)
        if (text == "" || text = GetLang("不限时"))
            return 0
        return WaitParseMilliseconds(text)
    }

    SaveWaitData() {
        this.Data.WaitType := this._TypeValue()
        this.Data.Interval := this.ui.Query("IntervalCon")
        this.Data.TimeoutMs := this._ParseTimeoutMs(this.ui.Query("TimeoutCon"))
        this.Data.ResultSaveName := GetVarName(this.ui.Query("TimeoutStatusCon"))
        this.Data.WaitCompletedValue := this.ui.Query("WaitCompletedValueCon")
        this.Data.WaitTimedOutValue := this.ui.Query("WaitTimedOutValueCon")
        t := this._TypeValue()
        switch t {
            case "等待确定":
                cfg := this.Data.ConfirmConfig
                cfg.Type := GetLangKey(this.ui.Query("WaitConditionCon"))
                cfg.Prompt := this.ui.Query("ConfirmPrompt")
                for option in WaitGui.ConfirmOptions {
                    property := option[1]
                    cfg.%property% := GetLangKey(this.ui.Query("Confirm" property))
                }
            case "等待变量值":
                this.Data.Conditions := this._ReadConditions()
                this.Data.Param1 := this.Data.Conditions[1].Variable
                this.Data.Param2 := this.Data.Conditions[1].Value
                this.Data.ConditionLogic := CmdEnumLogic(this.ui.Query("VarLogicCon"))
            case "等待按键按下", "等待按键松开":
                this.Data.Param1 := Trim(this.ui.Query("KeyCon"))
                this.Data.KeyDevice := this._KeyDeviceFor(this.Data.Param1)
                this.Data.KeyOptions := {
                    KeyArr: this._KeysFor(this.Data.Param1),
                    CheckType: CmdEnumFromIndex(this.ui.Query("KeyCheckTypeCon>SelectedIndex"), this._keyModes),
                    StateType: CmdEnumFromIndex(this.ui.Query("KeyStateTypeCon>SelectedIndex"), CmdEnumStateNames())
                }
                this.Data.Param2 := ""
            case "等待屏幕变化":
                this.Data.StartPosX := this.ui.Query("StartPosX")
                this.Data.StartPosY := this.ui.Query("StartPosY")
                this.Data.EndPosX := this.ui.Query("EndPosX")
                this.Data.EndPosY := this.ui.Query("EndPosY")
                this.Data.Param1 := ""
                this.Data.Param2 := ""
            case "等待鼠标移动", "等待鼠标停止移动", "等待剪切板变化":
                this.Data.Param1 := ""
                this.Data.Param2 := ""
            case "等待进程存在", "等待进程关闭":
                this.Data.ProcessTargetType := this._ProcessTargetType()
                this.Data.Param1 := Trim(this.ui.Query(this.Data.ProcessTargetType == "PID" ? "ProcPidCon" : "ProcCon"))
                this.Data.Param2 := ""
            case "等待窗口存在", "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口移动", "等待窗口关闭", "等待窗口最小化":
                this.Data.Param1 := this.ui.Query("WinInfoCon")
                this.Data.Param2 := ""
            case "等待文件存在", "等待文件删除", "等待文件变化":
                this.Data.Param1 := this.ui.Query("FilePathCon")
                this.Data.Param2 := ""
            case "等待时间", "等待时间区间":
                cfg := this.Data.TimeConfig
                cfg.SubMode := t == "等待时间区间" ? "区间判断" : "等待"
                kind := GetLangKey(this.ui.Query("TimeKindCon"))
                if (t == "等待时间区间") {
                    cfg.Param1 := this.ui.Query("TimeStartCon")
                    cfg.Param2 := this.ui.Query("TimeEndCon")
                    if (kind == "时间戳") {
                        cfg.Param1 := this._NormalizeTimestampText(cfg.Param1)
                        cfg.Param2 := this._NormalizeTimestampText(cfg.Param2)
                    }
                    cfg.Param5 := kind
                    cfg.WaitOutside := this.ui.Query("TimeWaitOutsideCon") == "True" ? 1 : 0
                    cfg.Param4 := "等待"
                } else {
                    cfg.Param1 := this.ui.Query(kind == "毫秒-随机" ? "TimeStartCon" : "TimeValueCon")
                    if (kind == "时间戳")
                        cfg.Param1 := this._NormalizeTimestampText(cfg.Param1)
                    if (kind == "毫秒-随机")
                        cfg.RandomMaxMs := this.ui.Query("TimeEndCon")
                    cfg.Param2 := kind
                }
                cfg.CheckInterval := this.Data.Interval
            case "等待日期":
                this.Data.Param1 := this.ui.Query("DateValCon")
                this.Data.Param2 := GetLangKey(this.ui.Query("DateUnitCon"))
        }
        SaveMacroCMDData(this.Data)
        MySoftData.GlobalVariMap[this.Data.ResultSaveName] := true
    }

    _AreaOk() {
        vals := []
        for n in ["StartPosX", "StartPosY", "EndPosX", "EndPosY"] {
            v := Trim(this.ui.Query(n))
            if (v == "") {
                RmtDialog.Info(GetLang("屏幕范围过小"))
                return false
            }
            if (!IsNumber(v))
                return true
            vals.Push(Integer(v))
        }
        if (Abs(vals[3] - vals[1]) < WaitGui.MinScreenAreaSize || Abs(vals[4] - vals[2]) < WaitGui.MinScreenAreaSize) {
            RmtDialog.Info(GetLang("屏幕范围过小"))
            return false
        }
        return true
    }

    _DateOk() {
        unit := WaitNormDateUnit(GetLangKey(this.ui.Query("DateUnitCon")))
        val := Trim(this.ui.Query("DateValCon"))
        if (unit == "分钟" || unit == "小时" || unit == "天") {
            if (IsNumber(val) && Number(val) < 0) {
                RmtDialog.Info(GetLang("日期值无法识别"))
                return false
            }
            if (!IsNumber(val) && !InStr(val, "{") && (val == "" || InStr(val, " "))) {
                RmtDialog.Info(GetLang("日期值无法识别"))
                return false
            }
            return true
        }
        if (unit == "具体时间" && !InStr(val, "{") && WaitParseDateTime(val) == "") {
            RmtDialog.Info(GetLang("日期值无法识别"))
            return false
        }
        return true
    }
    static CompareKeys := ["大于", "大于等于", "等于", "不等于", "小于等于", "小于", "包含", "变量存在", "变量不存在"]

    _Choice(parent, name, keys, width) {
        combo := parent.Add("ComboBox").Name(name).Width(width).Height(26).MinHeight(26)
        for key in keys
            combo.Add("ComboBoxItem").Content(GetLang(key))
        return combo
    }

    _Choose(name, value, keys) {
        this.ui.Update(name, "SelectedIndex", String(CmdEnumIndex(value, keys)))
    }

    _SelectType(type) {
        for index, group in WaitGroupNames() {
            for key in WaitGroupTypes(group) {
                if (key == type) {
                    this.ui.Update("WaitTypeCon", "SelectedIndex", index - 1)
                    this._FillTypes(group, type)
                    return
                }
            }
        }
        this.ui.Update("WaitTypeCon", "SelectedIndex", CmdEnumIndex("时间", WaitGroupNames()))
        this._FillTypes("时间", "等待时间")
    }

    _FillTypes(group, selected := "") {
        this._currentGroup := group
        this.WaitTypeKeys := group == "确定" ? WaitGui.ConfirmModes : WaitGroupTypes(group)
        this.ui.Update("WaitConditionCon", "ClearItems", "")
        for key in this.WaitTypeKeys {
            label := group == "确定" ? key : (key == "等待时间" ? "等待" : (key == "等待时间区间" ? "区间判断" : SubStr(key, 3)))
            this.ui.Update("WaitConditionCon", "AddItem", GetLang(label))
        }
        index := group == "确定" ? CmdEnumIndex(this._confirmMode, WaitGui.ConfirmModes) : CmdEnumIndex(selected, this.WaitTypeKeys)
        this.ui.Update("WaitConditionCon", "SelectedIndex", index)
    }

    OnGroupChange(*) {
        if (this._loading || !IsObject(this.ui))
            return
        index := this.ui.Query("WaitTypeCon>SelectedIndex")
        groups := WaitGroupNames()
        if (!IsNumber(index) || index < 0 || index >= groups.Length)
            return
        group := groups[index + 1]
        if (this._currentGroup != group)
            this._FillTypes(group)
        this.OnTypeChange()
    }

    _FillTimeKinds(range, selected) {
        keys := range ? ["时刻", "时间戳"] : ["毫秒", "毫秒-随机", "时间戳", "时长", "时刻"]
        if (!range && (selected == "分钟" || selected == "小时" || selected == "天"))
            keys.Push(selected)
        if (this.HasProp("_timeRange") && this._timeRange == range)
            return
        this._timeRange := range
        this.ui.Update("TimeKindCon", "ClearItems", "")
        for key in keys
            this.ui.Update("TimeKindCon", "AddItem", GetLang(key))
        this._Choose("TimeKindCon", selected, keys)
    }

    OnTimeKindChange(*) {
        if (!IsObject(this.ui) || this._loading)
            return
        kind := GetLangKey(this.ui.Query("TimeKindCon"))
        if (kind == "")
            return
        range := this._timeRange
        random := kind == "毫秒-随机"
        pair := range || random
        this._RefreshTimeTarget(range, kind)
        label := kind == "毫秒" ? "目标(ms)：" : "目标："
        this.ui.Update("TimeValueLabel", "Text", GetLang(label))
        this.ui.Update("TimeStartLabel", "Text", GetLang(random ? "最短：" : "开始："))
        this.ui.Update("TimeEndLabel", "Text", GetLang(random ? "最长：" : "结束："))
        this.ui.Update("TimeTargetFields", "Visibility", pair ? "Collapsed" : "Visible")
        this.ui.Update("TimeRangeFields", "Visibility", pair ? "Visible" : "Hidden")
        this.ui.Update("TimeWaitOutsideCon", "Visibility", range ? "Visible" : "Collapsed")
        hint := kind == "时长" ? "格式：时:分:秒，例如 00:01:30；支持变量。" : (kind == "时刻" ? "格式：时:分:秒，例如 14:30:00；区间支持跨午夜。" : "填写毫秒时间戳或选择时间变量。")
        if (random)
            hint := "从最短与最长毫秒数之间随机等待，支持变量。"
        else if (kind == "毫秒")
            hint := "输入毫秒数或选择变量，例如 500。"
        else if (kind == "分钟" || kind == "小时" || kind == "天")
            hint := "旧配置时长单位：" kind "，支持数值或变量。"
        this.ui.Update("TimeHintCon", "Text", GetLang(hint))
    }

    _RefreshTimeTarget(range, kind) {
        key := (range ? "区间" : "等待") kind
        if (key == this._timeValueKey)
            return
        if (this._timeValueKey != "") {
            edited := []
            edited.Length := this._timeTargetControls.Length
            changed := false
            for i, name in this._timeTargetControls {
                current := this.ui.Query(name)
                if (current != this._timeDefaults[i]) {
                    edited[i] := current
                    changed := true
                }
            }
            if (changed)
                this._timeValues[this._timeValueKey] := edited
            else if (this._timeValues.Has(this._timeValueKey))
                this._timeValues.Delete(this._timeValueKey)
        }
        this._timeValueKey := key
        if (range) {
            this._timeTargetControls := ["TimeStartCon", "TimeEndCon"]
            today := SubStr(A_Now, 1, 8)
            this._timeDefaults := kind == "时间戳"
                ? [String(TimeStrToStamp(today "060000")), String(TimeStrToStamp(today "180000"))]
                : ["09:00:00", "18:00:00"]
        } else if (kind == "毫秒-随机") {
            this._timeTargetControls := ["TimeStartCon", "TimeEndCon"]
            this._timeDefaults := ["500", "1000"]
        } else {
            this._timeTargetControls := ["TimeValueCon"]
            switch kind {
                case "时长": this._timeDefaults := ["00:00:10"]
                case "毫秒": this._timeDefaults := ["500"]
                case "时间戳": this._timeDefaults := [String(UnixNow() + 60000)]
                default: this._timeDefaults := ["14:30:00"]
            }
        }
        saved := this._timeValues.Get(key, [])
        for i, name in this._timeTargetControls
            this.ui.Update(name, "Text", saved.Has(i) ? saved[i] : this._timeDefaults[i])
    }

    _NormalizeTimestampText(value) {
        ms := TimeEpochMilliseconds(value)
        return ms == "" ? value : String(ms)
    }

    _ConditionButton(parent, name, glyph, tip) {
        return parent.Add("Button").Name(name).Content(Chr(glyph)).ToolTip(GetLang(tip))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .Width(24).Height(24).MinHeight(24).Padding("0").HorizontalAlignment("Center").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
    }

    _ConditionRow(i, canDelete) {
        row := XAML_Generator("Grid").Margin("0,2")
        row.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        row.Cols("*", "8", "128", "8", "*", "32")
        row.Add("ComboBox").Grid_Column(0).Name("VarName_" i).Height(26).MinHeight(26)
            .IsEditable("True").ToolTip(GetLang("变量名："))
        this._Choice(row, "VarCompare_" i, WaitGui.CompareKeys, 128).Grid_Column(2)
        row.Add("ComboBox").Grid_Column(4).Name("VarValue_" i).Height(26).MinHeight(26).IsEditable("True")
        this._ConditionButton(row, "BtnDeleteVar_" i, 0xE74D, "删除").Grid_Column(5)
            .IsEnabled(canDelete ? "True" : "False")
        return row.ToString()
    }

    _RebuildConditions(conditions) {
        this._conditionCount := conditions.Length
        this.ui.Update("VarRows", "ClearItems", "")
        for i, condition in conditions {
            batch := [{ControlName: "VarRows", PropertyName: "AddXamlItem", Value: this._ConditionRow(i, conditions.Length > 1)}]
            this._QueueCombo(batch, "VarName_" i, this.DLVariableArr, condition.Variable)
            this._QueueCombo(batch, "VarValue_" i, this.DLVariableArr, condition.Value)
            batch.Push({ControlName: "VarCompare_" i, PropertyName: "SelectedIndex",
                Value: CmdEnumIndex(condition.Operator, WaitGui.CompareKeys)})
            this.ui.BatchUpdate(batch)
            this._RefreshConditionValue(i, condition.Operator)
            this._BindConditionEvent("VarCompare_" i, "SelectionChanged", this.OnConditionOperator.Bind(this, i))
            this._BindConditionEvent("BtnDeleteVar_" i, "Click", this.OnDeleteCondition.Bind(this, i))
        }
    }

    _BindConditionEvent(name, event, handler) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(event))
            this.ui.events[name][event] := []
        this.ui.OnEvent(name, event, handler)
    }

    _ReadConditions() {
        conditions := []
        loop this._conditionCount {
            i := A_Index
            operator := GetLangKey(this.ui.Query("VarCompare_" i))
            conditions.Push({Variable: GetVarName(this.ui.Query("VarName_" i)),
                Operator: operator, Value: this.ui.Query("VarValue_" i)})
        }
        return conditions
    }

    OnAddCondition(*) {
        conditions := this._ReadConditions()
        conditions.Push({Variable: "", Operator: "等于", Value: ""})
        this._RebuildConditions(conditions)
        this.ui.Update("VarScroll", "ScrollToEnd", "")
    }

    OnDeleteCondition(i, *) {
        if (this._conditionCount <= 1)
            return
        conditions := this._ReadConditions()
        conditions.RemoveAt(i)
        this._RebuildConditions(conditions)
    }

    OnConditionOperator(i, *) {
        this._RefreshConditionValue(i, GetLangKey(this.ui.Query("VarCompare_" i)))
    }

    _RefreshConditionValue(i, operator) {
        existsTest := operator == "变量存在" || operator == "变量不存在"
        this.ui.Update("VarValue_" i, "Visibility", existsTest ? "Collapsed" : "Visible")
    }

    _ValidateTime() {
        range := this._TypeValue() == "等待时间区间"
        kind := GetLangKey(this.ui.Query("TimeKindCon"))
        random := kind == "毫秒-随机"
        value := Trim(this.ui.Query(range || random ? "TimeStartCon" : "TimeValueCon"))
        end := range || random ? Trim(this.ui.Query("TimeEndCon")) : ""
        if (random && (value == "" || end == "" || (IsNumber(end) && WaitParseMilliseconds(end) < 0)
            || (IsNumber(value) && IsNumber(end) && Number(value) >= Number(end)))) {
            RmtDialog.Info(GetLang("最短时间必须小于最长时间，均可使用变量"))
            return false
        }
        if (value == "" || (range && end == "")) {
            RmtDialog.Info(GetLang("请输入目标时间或区间起止时间"))
            return false
        }
        if ((kind == "毫秒" || random) && IsNumber(value) && WaitParseMilliseconds(value) < 0) {
            RmtDialog.Info(GetLang("请输入有效的毫秒整数或变量名"))
            return false
        }
        if (kind == "时长" && RegExMatch(value, "^[0-9:. ]+$") && TimeParseDurationSecs(value, "时长") <= 0) {
            RmtDialog.Info(GetLang("时长必须大于0"))
            return false
        }
        return true
    }

}
