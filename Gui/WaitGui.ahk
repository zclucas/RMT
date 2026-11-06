#Requires AutoHotkey v2.0

; =====================================================================
; 等待编辑器（§16）—— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 七类等待共用条件编辑入口，时间等待与区间判断复用时间执行逻辑。
; =====================================================================

class WaitGui {
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

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

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
        body.Rows("Auto", "Auto", "Auto")
        body.Cols("*")

        ; 行0：类型 + 备注
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center").Margin("0,0,0,8")
        row0.Add("TextBlock").Text(GetLang("类型：")).VerticalAlignment("Center")
        wt := row0.Add("ComboBox").Name("WaitTypeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
            .BorderThickness("0").BorderBrush("Transparent")
        for t in GetLangArr(WaitGroupNames())
            wt.Add("ComboBoxItem").Content(t)
        row0.Add("TextBlock").Text(GetLang("条件：")).VerticalAlignment("Center").Margin("12,0,0,0")
        row0.Add("ComboBox").Name("WaitConditionCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0").BorderThickness("0").BorderBrush("Transparent")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("16,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        ; 行1：参数直接排版，不显示分组标题或外框。
        pStack := body.Add("StackPanel").Grid_Row(1).Margin("0,6,0,2")

        ; 变量值面板：变量名 + 期望值
        vp := pStack.Add("StackPanel").Name("VarPanel").Orientation("Horizontal")
        vp.Add("TextBlock").Text(GetLang("变量名：")).VerticalAlignment("Center")
        vp.Add("ComboBox").Name("VarNameCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        this._Choice(vp, "VarCompareCon", WaitGui.CompareKeys, 100).Margin("10,0,0,0")
        vp.Add("ComboBox").Name("VarValCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")

        vp2 := pStack.Add("StackPanel").Name("VarPanel2").Orientation("Horizontal").Margin("0,8,0,0")
        this._Choice(vp2, "VarLogicCon", ["单个条件", "且", "或"], 100)
        vp2.Add("ComboBox").Name("VarName2Con").Width(140).Height(24).MinHeight(24).Margin("8,0,0,0").IsEditable("True").ToolTip(GetLang("留空时使用第一条条件的变量"))
        this._Choice(vp2, "VarCompare2Con", WaitGui.CompareKeys, 100).Margin("8,0,0,0")
        vp2.Add("ComboBox").Name("VarVal2Con").Width(140).Height(24).MinHeight(24).Margin("8,0,0,0").IsEditable("True")

        ; 按键面板
        kp := pStack.Add("StackPanel").Name("KeyPanel").Orientation("Horizontal").Visibility("Collapsed")
        kp.Add("TextBlock").Text(GetLang("按键：")).VerticalAlignment("Center")
        kp.Add("TextBox").Name("KeyCon").Width(160).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        kp.Add("Button").Name("BtnPickKey").Content(GetLang("键盘按键")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")
        kp.Add("Button").Name("BtnPickJoy").Content(GetLang("手柄按键")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")
        kp.Add("TextBlock").Name("KeySummaryCon").VerticalAlignment("Center").Margin("8,0,0,0").TextWrapping("Wrap")

        ; 范围面板：起始X/Y、终止X/Y
        rp := pStack.Add("StackPanel").Name("RangePanel").Visibility("Collapsed")
        rangeRowA := rp.Add("StackPanel").Orientation("Horizontal")
        rangeRowA.Add("TextBlock").Text(GetLang("起始坐标X：")).VerticalAlignment("Center")
        rangeRowA.Add("ComboBox").Name("StartPosX").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowA.Add("TextBlock").Text(GetLang("起始坐标Y：")).VerticalAlignment("Center").Margin("12,0,0,0")
        rangeRowA.Add("ComboBox").Name("StartPosY").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowB := rp.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        rangeRowB.Add("TextBlock").Text(GetLang("终止坐标X：")).VerticalAlignment("Center")
        rangeRowB.Add("ComboBox").Name("EndPosX").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowB.Add("TextBlock").Text(GetLang("终止坐标Y：")).VerticalAlignment("Center").Margin("12,0,0,0")
        rangeRowB.Add("ComboBox").Name("EndPosY").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowB.Add("Button").Name("BtnPickArea").Content(GetLang("框选范围")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")

        ; 进程面板
        pp := pStack.Add("StackPanel").Name("ProcPanel").Orientation("Horizontal").Visibility("Collapsed")
        pp.Add("TextBlock").Text(GetLang("进程名：")).VerticalAlignment("Center")
        pp.Add("TextBox").Name("ProcCon").Width(200).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; 窗口面板
        wp := pStack.Add("StackPanel").Name("WinPanel").Orientation("Horizontal").Visibility("Collapsed")
        wp.Add("TextBlock").Text(GetLang("窗口绑定：")).VerticalAlignment("Center")
        wp.Add("TextBox").Name("WinInfoCon").Width(220).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        wp.Add("Button").Name("BtnWinEdit").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")

        ; 文件面板
        fp := pStack.Add("StackPanel").Name("FilePanel").Orientation("Horizontal").Visibility("Collapsed")
        fp.Add("TextBlock").Text(GetLang("文件路径：")).VerticalAlignment("Center")
        fp.Add("TextBox").Name("FilePathCon").Width(240).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        fp.Add("Button").Name("BtnFileBrowse").Content(GetLang("浏览")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")

        hint := pStack.Add("TextBlock").Name("HintPanel").TextWrapping("Wrap").Visibility("Collapsed")
            .Foreground("{DynamicResource TextMain}").Margin("0,2,0,0")

        tp := pStack.Add("StackPanel").Name("TimePanel").Visibility("Collapsed")
        tr := tp.Add("StackPanel").Orientation("Horizontal")
        tr.Add("TextBlock").Text(GetLang("模式：")).VerticalAlignment("Center")
        this._Choice(tr, "TimeKindCon", ["时长", "时刻", "时间戳"], 100)
        tr.Add("TextBlock").Name("TimeValueLabel").Text(GetLang("目标：")).VerticalAlignment("Center").Margin("12,0,0,0")
        tr.Add("ComboBox").Name("TimeValueCon").Width(250).Height(26).MinHeight(26).IsEditable("True")
        ter := tp.Add("StackPanel").Name("TimeEndRow").Orientation("Horizontal").Margin("0,8,0,0")
        ter.Add("TextBlock").Text(GetLang("结束：")).VerticalAlignment("Center")
        ter.Add("ComboBox").Name("TimeEndCon").Width(250).Height(26).MinHeight(26).IsEditable("True")
        ter.Add("TextBlock").Text(GetLang("不满足时：")).VerticalAlignment("Center").Margin("12,0,0,0")
        this._Choice(ter, "TimeActionCon", ["等待", "跳过", "终止"], 100)
        tp.Add("TextBlock").Name("TimeHintCon").TextWrapping("Wrap").Margin("0,8,0,0")

        ; 日期面板：仅用于读取旧字段，新编辑统一使用时间面板
        dp := pStack.Add("StackPanel").Name("DatePanel").Orientation("Horizontal").Visibility("Collapsed")
        dp.Add("TextBlock").Name("DateValLabel").Text(GetLang("数值：")).VerticalAlignment("Center")
        dp.Add("ComboBox").Name("DateValCon").Width(180).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        dp.Add("TextBlock").Text(GetLang("单位：")).VerticalAlignment("Center").Margin("12,0,0,0")
        dunit := dp.Add("ComboBox").Name("DateUnitCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
        for t in GetLangArr(["分钟", "小时", "天", "具体时间", "时间变量"])
            dunit.Add("ComboBoxItem").Content(t)

        ; 行2：检测间隔 + 确定
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,14,0,0")
        btnRow.Add("TextBlock").Text(GetLang("检测间隔(ms)：")).VerticalAlignment("Center")
        btnRow.Add("TextBox").Name("IntervalCon").Width(80).Height(24).MinHeight(24).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Tag("NumOnly|NoIME|MaxLen:6")
        AddCmdOkBtn(btnRow, "BtnOk", "16,0,0,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="760" Height="340"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/等待")
        this.ui.OnEvent("WaitTypeCon", "SelectionChanged", ObjBindMethod(this, "OnGroupChange"))
        this.ui.OnEvent("WaitConditionCon", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("TimeKindCon", "SelectionChanged", ObjBindMethod(this, "OnTimeKindChange"))
        this.ui.OnEvent("VarLogicCon", "SelectionChanged", ObjBindMethod(this, "OnVarLogicChange"))
        this.ui.OnEvent("DateUnitCon", "SelectionChanged", ObjBindMethod(this, "OnDateUnitChange"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEdit"))
        this.ui.OnEvent("BtnFileBrowse", "Click", ObjBindMethod(this, "OnClickFileBrowse"))
        this.ui.OnEvent("BtnPickKey", "Click", ObjBindMethod(this, "OnClickPickKey", false))
        this.ui.OnEvent("BtnPickJoy", "Click", ObjBindMethod(this, "OnClickPickKey", true))
        this.ui.OnEvent("BtnPickArea", "Click", ObjBindMethod(this, "OnClickPickArea"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    _ShowWindow() {
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this.OnTypeChange()
        this._SyncDateUnit()
    }

    OnWindowClosing(state, ctrl, event) {
        WaitEndKeyCapture()
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
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    _TypeValue() {
        v := IsObject(this.ui) ? this.ui.Query("WaitConditionCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0 || Integer(v) >= this.WaitTypeKeys.Length)
            return ""
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
            case "等待窗口存在", "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口关闭", "等待窗口最小化":
                return "WinPanel"
            case "等待文件存在", "等待文件删除", "等待文件变化":
                return "FilePanel"
            case "等待时间", "等待时间区间", "等待日期":
                return "TimePanel"
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
            if (this.Data.WaitType == "等待时间区间")
                this.Data.TimeConfig.Param4 := TimeNormMismatch(old.HasProp("Param4") ? old.Param4 : "跳过")
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
        this._SelectType(CmdEnumWait(this.Data.WaitType))
        batch.Push({ControlName: "IntervalCon", PropertyName: "Text", Value: this.Data.Interval})
        batch.Push({ControlName: "VarNameCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "VarValCon", PropertyName: "Text", Value: this.Data.Param2})
        batch.Push({ControlName: "KeyCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "ProcCon", PropertyName: "Text", Value: this.Data.Param1})
        winWait := this._PanelOf(CmdEnumWait(this.Data.WaitType)) == "WinPanel"
        batch.Push({ControlName: "WinInfoCon", PropertyName: "Text", Value: this.Data.Param1 == "" && !winWait ? "{宏设置窗口绑定}" : this.Data.Param1})
        batch.Push({ControlName: "FilePathCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "DateValCon", PropertyName: "Text", Value: this.Data.Param1})
        this.ui.BatchUpdate(batch)
        ; 坐标与下拉数据
        this._SetCombo("StartPosX", GetGuiVarArr(), this.Data.StartPosX)
        this._SetCombo("StartPosY", GetGuiVarArr(), this.Data.StartPosY)
        this._SetCombo("EndPosX", GetGuiVarArr(), this.Data.EndPosX)
        this._SetCombo("EndPosY", GetGuiVarArr(), this.Data.EndPosY)
        this._SetCombo("VarNameCon", this.DLVariableArr, this.Data.Param1)
        this._SetCombo("VarValCon", this.DLVariableArr, this.Data.Param2)
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
        conditions := this.Data.Conditions
        a := conditions.Length ? conditions[1] : {Variable: this.Data.Param1, Operator: "等于", Value: this.Data.Param2}
        b := conditions.Length > 1 ? conditions[2] : {Variable: "", Operator: "小于", Value: ""}
        this._SetCombo("VarNameCon", this.DLVariableArr, a.Variable)
        this._SetCombo("VarValCon", this.DLVariableArr, a.Value)
        this._SetCombo("VarName2Con", this.DLVariableArr, b.Variable == "" ? a.Variable : b.Variable)
        this._SetCombo("VarVal2Con", this.DLVariableArr, b.Value)
        this._Choose("VarCompareCon", a.Operator, WaitGui.CompareKeys)
        this._Choose("VarCompare2Con", b.Operator, WaitGui.CompareKeys)
        this._Choose("VarLogicCon", conditions.Length > 1 ? this.Data.ConditionLogic : "单个条件", ["单个条件", "且", "或"])
        cfg := this.Data.TimeConfig
        range := CmdEnumWait(this.Data.WaitType) == "等待时间区间"
        legacyUnit := GetLangKey(cfg.Param2)
        kind := range ? TimeNormWindowType(cfg.Param5) : ((legacyUnit == "分钟" || legacyUnit == "小时" || legacyUnit == "天") ? legacyUnit : TimeNormWaitType(cfg.Param2 == "" ? "时长" : cfg.Param2))
        this._FillTimeKinds(range, kind)
        value := cfg.Param1
        if (value == "")
            value := range ? "09:00:00" : (kind == "时长" ? "00:00:10" : "14:30:00")
        this._SetCombo("TimeValueCon", GetGuiVarArr(), value)
        this._SetCombo("TimeEndCon", GetGuiVarArr(), range && cfg.Param2 != "" ? cfg.Param2 : "18:00:00")
        this._Choose("TimeActionCon", cfg.Param4 == "" ? "等待" : TimeNormMismatch(cfg.Param4), ["等待", "跳过", "终止"])
        this._RefreshKeySummary()
    }

    ; 按类型显隐参数面板
    OnTypeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || this._loading)
            return
        t := this._TypeValue()
        show := this._PanelOf(t)
        batch := []
        for name in ["VarPanel", "KeyPanel", "RangePanel", "ProcPanel", "WinPanel", "FilePanel", "DatePanel", "HintPanel", "TimePanel"] {
            batch.Push({ControlName: name, PropertyName: "Visibility", Value: (name == show) ? "Visible" : "Collapsed"})
        }
        batch.Push({ControlName: "VarPanel2", PropertyName: "Visibility", Value: show == "VarPanel" ? "Visible" : "Collapsed"})
        hint := WaitHintText(t)
        if (hint != "")
            batch.Push({ControlName: "HintPanel", PropertyName: "Text", Value: GetLang(hint)})
        this.ui.BatchUpdate(batch)
        if (show == "TimePanel") {
            range := t == "等待时间区间"
            kind := GetLangKey(this.ui.Query("TimeKindCon"))
            this._FillTimeKinds(range, kind)
            this.ui.Update("TimeEndRow", "Visibility", range ? "Visible" : "Collapsed")
            this.ui.Update("TimeValueLabel", "Text", GetLang(range ? "开始：" : "目标："))
            this.OnTimeKindChange()
        }
        this.OnVarLogicChange()
    }

    OnDateUnitChange(state := "", ctrl := "", event := "") {
        this._SyncDateUnit()
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
        picker := joy ? JoyCheckGui() : KeyCheckGui()
        options := this.Data.KeyDevice == (joy ? "手柄" : "键盘") ? this.Data.KeyOptions : {KeyArr: [], CheckType: "同时按下", StateType: "物理状态"}
        picker.SelectionData := JSON.parse(JSON.stringify(options), , false)
        picker.SelectionData.VarName := ""
        if (!joy && !picker.SelectionData.KeyArr.Length && this.ui.Query("KeyCon") != "")
            picker.SelectionData.KeyArr := GetPressKeyArr(this.ui.Query("KeyCon"))
        picker.OwnerHwnd := this.Hwnd()
        picker.SureBtnAction := (*) => this._AcceptKeys(picker, joy)
        this._keyPicker := picker
        picker.ShowGui("")
    }

    _AcceptKeys(picker, joy) {
        this.Data.KeyDevice := joy ? "手柄" : "键盘"
        this.Data.KeyOptions := picker.Data
        keys := ""
        for key in picker.Data.KeyArr
            keys .= (keys == "" ? "" : "⎖") key
        this.ui.Update("KeyCon", "Text", keys)
        this._RefreshKeySummary()
    }

    _RefreshKeySummary() {
        options := this.Data.KeyOptions
        mode := CmdEnumZh(options.CheckType, CmdEnumKeyCheckNames()) == "有一个按下" ? "任一按键" : "全部按键"
        for key in options.KeyArr
            if (InStr(key, "JoyAxis") == 1)
                mode := options.CheckType
        text := options.KeyArr.Length ? this.Data.KeyDevice " · " GetLang(mode) : ""
        this.ui.Update("KeySummaryCon", "Text", text)
    }

    _OnKeyPicked(key) {
        if (IsObject(this.ui))
            this.ui.Update("KeyCon", "Text", key)
    }

    OnClickPickArea(state := "", ctrl := "", event := "") {
        while (GetKeyState("LButton", "P"))
            Sleep(15)
        TogSelectArea(true, this.OnAreaPicked.Bind(this))
    }

    OnAreaPicked(x1, y1, x2, y2) {
        if (!IsObject(this.ui))
            return
        if (Abs(x2 - x1) < 4 || Abs(y2 - y1) < 4)
            return
        this.ui.Update("StartPosX", "Text", x1)
        this.ui.Update("StartPosY", "Text", y1)
        this.ui.Update("EndPosX", "Text", x2)
        this.ui.Update("EndPosY", "Text", y2)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
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
                if (!CheckVarNameIfValid(this.ui.Query("VarNameCon")))
                    return false
                if (GetLangKey(this.ui.Query("VarLogicCon")) != "单个条件" && this.ui.Query("VarName2Con") != "" && !CheckVarNameIfValid(this.ui.Query("VarName2Con")))
                    return false
            case "等待按键按下", "等待按键松开":
                if (this.ui.Query("KeyCon") == "") {
                    RmtDialog.Info(GetLang("请输入等待的按键"))
                    return false
                }
            case "等待进程存在", "等待进程关闭":
                if (this.ui.Query("ProcCon") == "") {
                    RmtDialog.Info(GetLang("请输入进程名"))
                    return false
                }
            case "等待窗口存在", "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口关闭", "等待窗口最小化":
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
        if (!IsNumber(interval) || Number(interval) <= 0) {
            RmtDialog.Info(GetLang("检测间隔请输入大于0的数字（毫秒）"))
            return false
        }
        return true
    }

    SaveWaitData() {
        this.Data.WaitType := this._TypeValue()
        this.Data.Interval := this.ui.Query("IntervalCon")
        t := this._TypeValue()
        switch t {
            case "等待变量值":
                this.Data.Param1 := GetVarName(this.ui.Query("VarNameCon"))
                this.Data.Param2 := this.ui.Query("VarValCon")
                this.Data.Conditions := [{Variable: this.Data.Param1, Operator: GetLangKey(this.ui.Query("VarCompareCon")), Value: this.Data.Param2}]
                logic := GetLangKey(this.ui.Query("VarLogicCon"))
                this.Data.ConditionLogic := logic == "或" ? "或" : "且"
                if (logic != "单个条件") {
                    variable2 := this.ui.Query("VarName2Con")
                    this.Data.Conditions.Push({Variable: variable2 == "" ? this.Data.Param1 : GetVarName(variable2), Operator: GetLangKey(this.ui.Query("VarCompare2Con")), Value: this.ui.Query("VarVal2Con")})
                }
            case "等待按键按下", "等待按键松开":
                this.Data.Param1 := this.ui.Query("KeyCon")
                ; 仍允许直接填写键名；一旦修改文本就按当前文本重建键数组。
                keyText := ""
                for key in this.Data.KeyOptions.KeyArr
                    keyText .= (keyText == "" ? "" : "⎖") key
                if (keyText != this.Data.Param1) {
                    this.Data.KeyDevice := "键盘"
                    this.Data.KeyOptions := {KeyArr: GetPressKeyArr(this.Data.Param1), CheckType: "同时按下", StateType: "物理状态"}
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
                this.Data.Param1 := this.ui.Query("ProcCon")
                this.Data.Param2 := ""
            case "等待窗口存在", "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口关闭", "等待窗口最小化":
                this.Data.Param1 := this.ui.Query("WinInfoCon")
                this.Data.Param2 := ""
            case "等待文件存在", "等待文件删除", "等待文件变化":
                this.Data.Param1 := this.ui.Query("FilePathCon")
                this.Data.Param2 := ""
            case "等待时间", "等待时间区间":
                cfg := this.Data.TimeConfig
                cfg.SubMode := t == "等待时间区间" ? "区间判断" : "等待"
                cfg.Param1 := this.ui.Query("TimeValueCon")
                kind := GetLangKey(this.ui.Query("TimeKindCon"))
                if (t == "等待时间区间") {
                    cfg.Param2 := this.ui.Query("TimeEndCon")
                    cfg.Param5 := kind
                    cfg.Param4 := GetLangKey(this.ui.Query("TimeActionCon"))
                } else
                    cfg.Param2 := kind
                cfg.CheckInterval := this.Data.Interval
            case "等待日期":
                this.Data.Param1 := this.ui.Query("DateValCon")
                this.Data.Param2 := GetLangKey(this.ui.Query("DateUnitCon"))
        }
        SaveMacroCMDData(this.Data)
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
        if (Abs(vals[3] - vals[1]) < 4 || Abs(vals[4] - vals[2]) < 4) {
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
    static CompareKeys := ["大于", "大于等于", "等于", "不等于", "小于等于", "小于", "包含"]

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
        this.ui.Update("WaitTypeCon", "SelectedIndex", 3)
        this._FillTypes("变量", "等待变量值")
    }

    _FillTypes(group, selected := "") {
        this._currentGroup := group
        this.WaitTypeKeys := WaitGroupTypes(group)
        this.ui.Update("WaitConditionCon", "ClearItems", "")
        for key in this.WaitTypeKeys {
            label := key == "等待时间" ? "等待" : (key == "等待时间区间" ? "区间判断" : SubStr(key, 3))
            this.ui.Update("WaitConditionCon", "AddItem", GetLang(label))
        }
        this.ui.Update("WaitConditionCon", "SelectedIndex", selected == "" ? 0 : CmdEnumIndex(selected, this.WaitTypeKeys))
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
        keys := range ? ["时刻", "时间戳"] : ["时长", "时刻", "时间戳"]
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
        kind := GetLangKey(this.ui.Query("TimeKindCon"))
        hint := kind == "时长" ? "格式：时:分:秒，例如 00:01:30；支持变量。" : (kind == "时刻" ? "格式：时:分:秒，例如 14:30:00；区间支持跨午夜。" : "填写时间戳或时间变量，支持具体日期时间。")
        if (kind == "分钟" || kind == "小时" || kind == "天")
            hint := "旧配置时长单位：" kind "，支持数值或变量。"
        this.ui.Update("TimeHintCon", "Text", GetLang(hint))
    }

    OnVarLogicChange(*) {
        if (!IsObject(this.ui))
            return
        visibility := GetLangKey(this.ui.Query("VarLogicCon")) == "单个条件" ? "Collapsed" : "Visible"
        for name in ["VarName2Con", "VarCompare2Con", "VarVal2Con"]
            this.ui.Update(name, "Visibility", visibility)
    }

    _ValidateTime() {
        value := Trim(this.ui.Query("TimeValueCon"))
        range := this._TypeValue() == "等待时间区间"
        if (value == "" || (range && Trim(this.ui.Query("TimeEndCon")) == "")) {
            RmtDialog.Info(GetLang("请输入目标时间或区间起止时间"))
            return false
        }
        kind := GetLangKey(this.ui.Query("TimeKindCon"))
        if (kind == "时长" && RegExMatch(value, "^[0-9:. ]+$") && TimeParseDurationSecs(value, "时长") <= 0) {
            RmtDialog.Info(GetLang("时长必须大于0"))
            return false
        }
        return true
    }

}
