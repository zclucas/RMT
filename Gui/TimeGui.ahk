#Requires AutoHotkey v2.0

; =====================================================================
; 时间编辑器 —— XAML 界面（独立实现）
; 支持 4 种子模式：指定时刻等待、时间区间判断、时间获取、时间计算
; =====================================================================

class TimeGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this.Data := ""
        this.SerialStr := ""
        this.ModeKeys := ["指定时刻等待", "时间区间判断", "获取时间变量", "获取时间字符串", "时间计算"]
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)
        this.OnModeChange()
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
        title := this.ParentTile GetLang("时间编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("12,6,12,6")
        body.Rows("32", "*", "42")
        body.Cols("*")

        ; 行0：备注 + 模式
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
        row0.Add("TextBox").Name("RemarkCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        row0.Add("TextBlock").Text(GetLang("时间模式：")).VerticalAlignment("Center").Margin("16,0,0,0")
        tm := row0.Add("ComboBox").Name("TimeModeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(this.ModeKeys)
            tm.Add("ComboBoxItem").Content(t)

        ; 行1：参数 GroupBox
        pg := body.Add("GroupBox").Grid_Row(1).Header(GetLang("参数设置："))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,6,0,2")
        pStack := pg.Add("StackPanel").Margin("10,8")

        ; 面板1：指定时刻等待 (WaitPanel)
        p1 := pStack.Add("StackPanel").Name("WaitPanel")
        p1Row1 := p1.Add("StackPanel").Orientation("Horizontal")
        p1Row1.Add("TextBlock").Text(GetLang("目标时间/时长：")).VerticalAlignment("Center")
        p1Row1.Add("TextBox").Name("WaitValCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        p1Row1.Add("TextBlock").Text(GetLang("单位/类型：")).VerticalAlignment("Center").Margin("12,0,0,0")
        wunit := p1Row1.Add("ComboBox").Name("WaitUnitCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
        for u in GetLangArr(["具体时间", "秒", "分钟", "小时", "天", "时间变量"])
            wunit.Add("ComboBoxItem").Content(u)

        p1Row2 := p1.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        p1Row2.Add("TextBlock").Text(GetLang("超时时间(ms)：")).VerticalAlignment("Center")
        p1Row2.Add("TextBox").Name("TimeoutCon").Width(80).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        p1Row2.Add("TextBlock").Text(GetLang("轮询间隔(ms)：")).VerticalAlignment("Center").Margin("16,0,0,0")
        p1Row2.Add("TextBox").Name("CheckIntervalCon").Width(80).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; 面板2：时间区间判断 (WindowPanel)
        p2 := pStack.Add("StackPanel").Name("WindowPanel").Visibility("Collapsed")
        p2Row1 := p2.Add("StackPanel").Orientation("Horizontal")
        p2Row1.Add("TextBlock").Text(GetLang("开始时间：")).VerticalAlignment("Center")
        p2Row1.Add("TextBox").Name("StartTimeCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        p2Row1.Add("TextBlock").Text(GetLang("结束时间：")).VerticalAlignment("Center").Margin("12,0,0,0")
        p2Row1.Add("TextBox").Name("EndTimeCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        p2Row2 := p2.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        p2Row2.Add("TextBlock").Text(GetLang("允许星期：")).VerticalAlignment("Center")
        p2Row2.Add("TextBox").Name("DaysCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        p2Row2.Add("TextBlock").Text(GetLang("不满足时：")).VerticalAlignment("Center").Margin("12,0,0,0")
        act := p2Row2.Add("ComboBox").Name("MismatchActionCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
        for a in GetLangArr(["跳过", "等待", "停止"])
            act.Add("ComboBoxItem").Content(a)

        ; 面板3：获取时间变量 (GetVarPanel)
        p3 := pStack.Add("StackPanel").Name("GetVarPanel").Visibility("Collapsed")
        p3Row1 := p3.Add("StackPanel").Orientation("Horizontal")
        p3Row1.Add("TextBlock").Text(GetLang("时间变量名：")).VerticalAlignment("Center")
        p3Row1.Add("ComboBox").Name("GetTimeVarCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        p3Row1.Add("TextBlock").Text(GetLang("来源时间(可选)：")).VerticalAlignment("Center").Margin("12,0,0,0")
        p3Row1.Add("ComboBox").Name("GetTimeVarSrcCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")

        ; 面板4：获取时间字符串 (GetStrPanel)
        p4 := pStack.Add("StackPanel").Name("GetStrPanel").Visibility("Collapsed")
        p4Row1 := p4.Add("StackPanel").Orientation("Horizontal")
        p4Row1.Add("TextBlock").Text(GetLang("目标变量名：")).VerticalAlignment("Center")
        p4Row1.Add("ComboBox").Name("GetStrVarCon").Width(130).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        p4Row1.Add("TextBlock").Text(GetLang("时间源(可选)：")).VerticalAlignment("Center").Margin("10,0,0,0")
        p4Row1.Add("ComboBox").Name("GetStrSrcCon").Width(120).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")

        p4Row2 := p4.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        p4Row2.Add("TextBlock").Text(GetLang("格式化模板：")).VerticalAlignment("Center")
        gfmt := p4Row2.Add("ComboBox").Name("GetStrFormatCon").Width(200).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        for f in ["yyyy-MM-dd HH:mm:ss", "UnixTimestamp", "HH:mm:ss", "yyyyMMdd", "yyyy/MM/dd HH:mm:ss", "EEEE", "EEE", "E"]
            gfmt.Add("ComboBoxItem").Content(f)

        ; 面板5：时间计算 (MathPanel)
        p5 := pStack.Add("StackPanel").Name("MathPanel").Visibility("Collapsed")
        p5Row1 := p5.Add("StackPanel").Orientation("Horizontal")
        p5Row1.Add("TextBlock").Text(GetLang("时间变量1：")).VerticalAlignment("Center")
        p5Row1.Add("ComboBox").Name("MathSrc1Con").Width(130).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        p5Row1.Add("TextBlock").Text(GetLang("操作：")).VerticalAlignment("Center").Margin("10,0,0,0")
        mop := p5Row1.Add("ComboBox").Name("MathOpCon").Width(85).Height(24).MinHeight(24).Margin("4,0,0,0")
        for o in GetLangArr(["差值", "增加", "减少"])
            mop.Add("ComboBoxItem").Content(o)
        p5Row1.Add("TextBlock").Text(GetLang("时间变量2/偏移：")).VerticalAlignment("Center").Margin("10,0,0,0")
        p5Row1.Add("ComboBox").Name("MathSrc2Con").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")

        p5Row2 := p5.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        p5Row2.Add("TextBlock").Text(GetLang("保存变量：")).VerticalAlignment("Center")
        p5Row2.Add("ComboBox").Name("MathTargetCon").Width(130).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        p5Row2.Add("TextBlock").Text(GetLang("单位/格式：")).VerticalAlignment("Center").Margin("16,0,0,0")
        munit := p5Row2.Add("ComboBox").Name("MathUnitCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        for u in GetLangArr(["秒", "毫秒", "分钟", "小时", "天", "HH:mm:ss"])
            munit.Add("ComboBoxItem").Content(u)

        ; 行2：确定 / 取消 按钮
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("SureBtn").Content(GetLang("确定")).Width(80).Height(26).MinHeight(26).Margin("0,0,16,0").Cursor("Hand")
        btnRow.Add("Button").Name("CancelBtn").Content(GetLang("取消")).Width(80).Height(26).MinHeight(26).Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="280" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClickCancelBtn"))
        this.ui.OnEvent("SureBtn", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("CancelBtn", "Click", ObjBindMethod(this, "OnClickCancelBtn"))
        this.ui.OnEvent("TimeModeCon", "SelectionChanged", ObjBindMethod(this, "OnModeChange"))
    }

    _ShowWindow() {
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
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

    OnClickCancelBtn(state := "", ctrl := "", event := "") {
        this._CloseWindow()
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

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("时间")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")

        modeIdx := Integer(this.Data.SubMode)
        if (modeIdx < 1 || modeIdx > 5)
            modeIdx := 1
        this.ui.Update("TimeModeCon", "SelectedIndex", modeIdx - 1)

        ; 模式1参数
        this.ui.Update("WaitValCon", "Text", this.Data.Param1 != "" ? this.Data.Param1 : "14:30:00")
        unit := this.Data.Param2 != "" ? this.Data.Param2 : "具体时间"
        this.ui.Update("WaitUnitCon", "Text", GetLang(unit))
        this.ui.Update("TimeoutCon", "Text", String(this.Data.Timeout))
        this.ui.Update("CheckIntervalCon", "Text", String(this.Data.CheckInterval))

        ; 模式2参数
        this.ui.Update("StartTimeCon", "Text", this.Data.Param1 != "" ? this.Data.Param1 : "09:00:00")
        this.ui.Update("EndTimeCon", "Text", this.Data.Param2 != "" ? this.Data.Param2 : "18:00:00")
        this.ui.Update("DaysCon", "Text", this.Data.Param3 != "" ? this.Data.Param3 : "1,2,3,4,5,6,7")
        this.ui.Update("MismatchActionCon", "Text", GetLang(this.Data.Param4 != "" ? this.Data.Param4 : "跳过"))

        ; 模式3参数 (获取时间变量)
        this._SetCombo("GetTimeVarCon", GetGuiVarArr(), this.Data.Param1 != "" ? this.Data.Param1 : "TimeVar1")
        this._SetCombo("GetTimeVarSrcCon", GetGuiVarArr(1), this.Data.Param2 != "" ? this.Data.Param2 : "")

        ; 模式4参数 (获取时间字符串)
        this._SetCombo("GetStrVarCon", GetGuiVarArr(), this.Data.Param1 != "" ? this.Data.Param1 : "TimeStr1")
        this._SetCombo("GetStrSrcCon", GetGuiVarArr(1), this.Data.Param2 != "" ? this.Data.Param2 : "")
        this.ui.Update("GetStrFormatCon", "Text", this.Data.Param3 != "" ? this.Data.Param3 : "yyyy-MM-dd HH:mm:ss")

        ; 模式5参数 (时间计算)
        this._SetCombo("MathSrc1Con", GetGuiVarArr(1), this.Data.Param1)
        this._SetCombo("MathSrc2Con", GetGuiVarArr(1), this.Data.Param2)
        this.ui.Update("MathOpCon", "Text", GetLang(this.Data.Param3 != "" ? this.Data.Param3 : "差值"))
        this._SetCombo("MathTargetCon", GetGuiVarArr(), this.Data.Param4 != "" ? this.Data.Param4 : "TimeRes")
        this.ui.Update("MathUnitCon", "Text", GetLang(this.Data.Param5 != "" ? this.Data.Param5 : "秒"))
    }

    OnModeChange(state := "", ctrl := "", event := "") {
        m := this._ModeValue()
        panelMap := Map(1, "WaitPanel", 2, "WindowPanel", 3, "GetVarPanel", 4, "GetStrPanel", 5, "MathPanel")
        show := panelMap.Has(m) ? panelMap[m] : "WaitPanel"
        batch := []
        for name in ["WaitPanel", "WindowPanel", "GetVarPanel", "GetStrPanel", "MathPanel"] {
            batch.Push({ControlName: name, PropertyName: "Visibility", Value: (name == show) ? "Visible" : "Collapsed"})
        }
        this.ui.BatchUpdate(batch)
    }

    _ModeValue() {
        v := IsObject(this.ui) ? this.ui.Query("TimeModeCon>SelectedIndex") : ""
        return (IsNumber(v) && v >= 0) ? (Integer(v) + 1) : 1
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
        this.SaveTimeData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        m := this._ModeValue()
        switch m {
            case 1:
                if (this.ui.Query("WaitValCon") == "") {
                    MsgBox(GetLang("请输入目标时间或时长"))
                    return false
                }
            case 2:
                if (this.ui.Query("StartTimeCon") == "" || this.ui.Query("EndTimeCon") == "") {
                    MsgBox(GetLang("请输入开始与结束时间"))
                    return false
                }
            case 3:
                varName := GetVarName(this.ui.Query("GetTimeVarCon"))
                if (!CheckVarNameIfValid(varName))
                    return false
            case 4:
                varName := GetVarName(this.ui.Query("GetStrVarCon"))
                if (!CheckVarNameIfValid(varName))
                    return false
            case 5:
                varName := GetVarName(this.ui.Query("MathTargetCon"))
                if (this.ui.Query("MathSrc1Con") == "" || !CheckVarNameIfValid(varName))
                    return false
        }
        return true
    }

    SaveTimeData() {
        m := this._ModeValue()
        this.Data.SubMode := m

        switch m {
            case 1:
                this.Data.Param1 := this.ui.Query("WaitValCon")
                this.Data.Param2 := GetLangKey(this.ui.Query("WaitUnitCon"))
                this.Data.Timeout := Integer(this.ui.Query("TimeoutCon") != "" ? this.ui.Query("TimeoutCon") : 0)
                this.Data.CheckInterval := Integer(this.ui.Query("CheckIntervalCon") != "" ? this.ui.Query("CheckIntervalCon") : 500)
            case 2:
                this.Data.Param1 := this.ui.Query("StartTimeCon")
                this.Data.Param2 := this.ui.Query("EndTimeCon")
                this.Data.Param3 := this.ui.Query("DaysCon")
                this.Data.Param4 := GetLangKey(this.ui.Query("MismatchActionCon"))
            case 3:
                this.Data.Param1 := GetVarName(this.ui.Query("GetTimeVarCon"))
                this.Data.Param2 := GetVarName(this.ui.Query("GetTimeVarSrcCon"))
            case 4:
                this.Data.Param1 := GetVarName(this.ui.Query("GetStrVarCon"))
                this.Data.Param2 := GetVarName(this.ui.Query("GetStrSrcCon"))
                this.Data.Param3 := this.ui.Query("GetStrFormatCon")
            case 5:
                this.Data.Param1 := this.ui.Query("MathSrc1Con")
                this.Data.Param2 := this.ui.Query("MathSrc2Con")
                this.Data.Param3 := GetLangKey(this.ui.Query("MathOpCon"))
                this.Data.Param4 := GetVarName(this.ui.Query("MathTargetCon"))
                this.Data.Param5 := GetLangKey(this.ui.Query("MathUnitCon"))
        }

        SaveMacroCMDData(this.Data)
    }
}
