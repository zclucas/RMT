#Requires AutoHotkey v2.0

; =====================================================================
; 时间编辑器 —— XAML 界面（独立实现）
; 支持 3 种子模式：等待、区间判断、倒计时
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
        this.ModeKeys := ["等待", "区间判断", "倒计时"]
        this._syncing := false
        this._labW := 96
        this._fldW := 152  ; 与「时+：+分」同宽，右缘对齐分下拉
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("时间")
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)
        this.OnModeChange()
        this._ShowWindow()
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

    _Lab(parent, text, width := "", margin := "0") {
        if (width == "")
            width := this._labW
        return parent.Add("TextBlock").Text(GetLang(text)).Width(String(width)).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12").Margin(margin)
    }

    _Edit(parent, name, width := "") {
        el := parent.Add("TextBox").Name(name).Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left")
            .VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (width != "")
            el.Width(width)
        return el
    }

    _Combo(parent, name, editable := true, width := "") {
        el := parent.Add("ComboBox").Name(name).Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (editable)
            el.IsEditable("True")
        if (width != "")
            el.Width(width)
        return el
    }

    _AddHms(parent, prefix) {
        this._Combo(parent, prefix "HourCon", true, 68).ToolTip(GetLang("时")).Tag("NumOnly|NoIME|MaxLen:2")
        parent.Add("TextBlock").Text("：").Width("16").HorizontalAlignment("Center").TextAlignment("Center")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        this._Combo(parent, prefix "MinCon", true, 68).ToolTip(GetLang("分")).Tag("NumOnly|NoIME|MaxLen:2")
        parent.Add("TextBlock").Text("：").Width("16").HorizontalAlignment("Center").TextAlignment("Center")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        this._Combo(parent, prefix "SecCon", true, 68).ToolTip(GetLang("秒")).Tag("NumOnly|NoIME|MaxLen:2")
    }

    _PairCols(g) {
        ; 与备注、目标时间共用标签宽度，避免剩余空间将类型行居中。
        g.HorizontalAlignment("Left").Cols(String(this._labW), String(this._fldW), "108", String(this._fldW))
        return g
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("时间编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,8")
        body.Rows("Auto", "Auto", "Auto", "Auto")
        body.Cols("*")

        r0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center").Margin("0,0,0,8")
        this._Lab(r0, "备注：")
        this._Edit(r0, "RemarkCon").Width(420).TextAlignment("Left")

        r1 := this._PairCols(body.Add("Grid").Grid_Row(1).VerticalAlignment("Center").Margin("0,0,0,4"))
        this._Lab(r1, "类型：").Grid_Column(0)
        tm := this._Combo(r1, "TimeModeCon", false, this._fldW).Grid_Column(1)
        for t in GetLangArr(this.ModeKeys)
            tm.Add("ComboBoxItem").Content(t)
        this._Lab(r1, "模式：").Grid_Column(2)
        wunit := this._Combo(r1, "WaitUnitCon", false, this._fldW).Grid_Column(3)
        for u in GetLangArr(TimeGui.WaitUnitKeys)
            wunit.Add("ComboBoxItem").Content(u)
        wkind := this._Combo(r1, "WinKindCon", false, this._fldW).Grid_Column(3).Visibility("Collapsed")
        for u in GetLangArr(TimeGui.WindowKindKeys)
            wkind.Add("ComboBoxItem").Content(u)
        ckind := this._Combo(r1, "CdKindCon", false, this._fldW).Grid_Column(3).Visibility("Collapsed")
        for u in GetLangArr(TimeGui.WaitUnitKeys)
            ckind.Add("ComboBoxItem").Content(u)

        pStack := body.Add("StackPanel").Grid_Row(2).Margin("0,4,0,0")

        p1 := pStack.Add("StackPanel").Name("WaitPanel")
        p1Time := p1.Add("StackPanel").Name("WaitTimeRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center")
        this._Lab(p1Time, "目标时间：")
        this._AddHms(p1Time, "Wait")

        p1Dur := p1.Add("StackPanel").Name("WaitDurRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center").Visibility("Collapsed")
        this._Lab(p1Dur, "时长：")
        this._AddHms(p1Dur, "")

        p1Var := p1.Add("StackPanel").Name("WaitVarRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center").Visibility("Collapsed")
        this._Lab(p1Var, "时间戳：")
        this._Combo(p1Var, "WaitVarCon", true, 220)

        p2 := pStack.Add("StackPanel").Name("WindowPanel").Visibility("Collapsed")
        p2r1 := p2.Add("StackPanel").Name("WinTimeRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center")
        this._Lab(p2r1, "开始时间：")
        this._AddHms(p2r1, "Start")

        p2r1b := p2.Add("StackPanel").Name("WinTimeRow2").Orientation("Horizontal").Height("32").VerticalAlignment("Center")
        this._Lab(p2r1b, "结束时间：")
        this._AddHms(p2r1b, "End")

        p2Var := p2.Add("StackPanel").Name("WinVarRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center").Visibility("Collapsed")
        this._Lab(p2Var, "开始时间：")
        this._Combo(p2Var, "StartVarCon", true, 220)

        p2Var2 := p2.Add("StackPanel").Name("WinVarRow2").Orientation("Horizontal").Height("32").VerticalAlignment("Center").Visibility("Collapsed")
        this._Lab(p2Var2, "结束时间：")
        this._Combo(p2Var2, "EndVarCon", true, 220)

        p2r3 := p2.Add("StackPanel").Orientation("Horizontal").Height("32").VerticalAlignment("Center")
        this._Lab(p2r3, "动作：")
        act := this._Combo(p2r3, "MismatchActionCon", false, this._fldW)
        for a in GetLangArr(TimeGui.MismatchActionKeys)
            act.Add("ComboBoxItem").Content(a)

        p3 := pStack.Add("StackPanel").Name("CountDownPanel").Visibility("Collapsed")
        p3Time := p3.Add("StackPanel").Name("CdTimeRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center").Visibility("Collapsed")
        this._Lab(p3Time, "目标时间：")
        this._AddHms(p3Time, "CdWait")

        p3r1 := p3.Add("StackPanel").Name("CdDurRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center")
        this._Lab(p3r1, "时长：")
        this._AddHms(p3r1, "Cd")

        p3Var := p3.Add("StackPanel").Name("CdVarRow").Orientation("Horizontal").Height("32").VerticalAlignment("Center").Visibility("Collapsed")
        this._Lab(p3Var, "时间戳：")
        this._Combo(p3Var, "CdVarCon", true, 220)

        p3r2 := p3.Add("StackPanel").Orientation("Horizontal").Height("32").VerticalAlignment("Center")
        this._Lab(p3r2, "显示位置：")
        this._Combo(p3r2, "CdPosXCon", true, 68)
        this._Combo(p3r2, "CdPosYCon", true, 68).Margin("8,0,0,0")

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,12,0,4")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="280" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClickCancelBtn"))
        BindCmdEditorChrome(this.ui, "#指令手册/27-时间", (*) => this.TriggerMacro(), "!l", "", ObjBindMethod(this, "OnF1"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("TimeModeCon", "SelectionChanged", ObjBindMethod(this, "OnModeChange"))
        this.ui.OnEvent("WaitUnitCon", "SelectionChanged", ObjBindMethod(this, "OnWaitTypeChange"))
        this.ui.OnEvent("WinKindCon", "SelectionChanged", ObjBindMethod(this, "OnWinTypeChange"))
        this.ui.OnEvent("CdKindCon", "SelectionChanged", ObjBindMethod(this, "OnCdTypeChange"))
    }

    _ShowWindow() {
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    ToggleFunc(state) {
        try Hotkey("!l", (*) => this.TriggerMacro(), state ? "On" : "Off")
        try Hotkey("F1", (*) => this.OnF1(), state ? "On" : "Off")
    }

    _CloseWindow() {
        this.ToggleFunc(false)
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
        this.ToggleFunc(false)
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

    static WaitUnitKeys := ["时刻", "时长", "时间戳"]
    static WindowKindKeys := ["时刻", "时间戳"]
    static MismatchActionKeys := ["跳过", "等待", "终止", "不满足时跳过", "不满足时等待", "不满足时终止"]

    _GetSelectedKey(comboName, keysArray) {
        if (!IsObject(this.ui))
            return keysArray[1]
        try {
            idx := Integer(this.ui.Query(comboName ">SelectedIndex"))
            if (idx >= 0 && idx < keysArray.Length)
                return keysArray[idx + 1]
        }
        text := this.ui.Query(comboName)
        return GetLangKey(text)
    }

    _SetSelectedByKey(comboName, key, keysArray) {
        engKey := GetLangKey(key)
        for i, k in keysArray {
            if (k == engKey) {
                this.ui.Update(comboName, "SelectedIndex", i - 1)
                return
            }
        }
        this.ui.Update(comboName, "Text", GetLang(key))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("时间")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")

        modeIdx := this._CmdIsCountDown() ? 3 : TimeSubModeIndex(this.Data)
        this.ui.Update("TimeModeCon", "SelectedIndex", modeIdx - 1)

        vars := GetGuiVarArr()
        param1 := ObjHasOwnProp(this.Data, "Param1") ? this.Data.Param1 : ""
        param2 := ObjHasOwnProp(this.Data, "Param2") ? this.Data.Param2 : ""
        param4 := ObjHasOwnProp(this.Data, "Param4") ? this.Data.Param4 : ""
        subMode := TimeNormSubMode(this.Data)
        waitType := TimeNormWaitType(param2 != "" ? param2 : "时刻")
        this._SetSelectedByKey("WaitUnitCon", waitType, TimeGui.WaitUnitKeys)
        this._SetCombo("WaitVarCon", vars, waitType == "时间戳" ? param1 : "")
        wh := 14, wm := 30, ws := 0
        this._ParseClockToHMS(waitType == "时刻" ? param1 : "", 14, 30, 0, &wh, &wm, &ws)
        this._SetCombo("WaitHourCon", vars, wh)
        this._SetCombo("WaitMinCon", vars, wm)
        this._SetCombo("WaitSecCon", vars, ws)
        h := 0, m := 0, s := 10
        this._ParseDurationToHMS(param1, param2, &h, &m, &s)
        this._SetCombo("HourCon", vars, h)
        this._SetCombo("MinCon", vars, m)
        this._SetCombo("SecCon", vars, s)

        param5 := ObjHasOwnProp(this.Data, "Param5") ? this.Data.Param5 : ""
        winKind := (subMode == "区间判断") ? TimeNormWindowType(param5) : "时刻"
        this._SetSelectedByKey("WinKindCon", winKind, TimeGui.WindowKindKeys)
        sh := 9, sm := 0, ss := 0
        this._ParseClockToHMS(subMode == "区间判断" && winKind == "时刻" ? param1 : "", 9, 0, 0, &sh, &sm, &ss)
        this._SetCombo("StartHourCon", vars, sh)
        this._SetCombo("StartMinCon", vars, sm)
        this._SetCombo("StartSecCon", vars, ss)
        eh := 18, em := 0, es := 0
        this._ParseClockToHMS(subMode == "区间判断" && winKind == "时刻" ? param2 : "", 18, 0, 0, &eh, &em, &es)
        this._SetCombo("EndHourCon", vars, eh)
        this._SetCombo("EndMinCon", vars, em)
        this._SetCombo("EndSecCon", vars, es)
        this._SetCombo("StartVarCon", vars, subMode == "区间判断" && winKind == "时间戳" ? param1 : "")
        this._SetCombo("EndVarCon", vars, subMode == "区间判断" && winKind == "时间戳" ? param2 : "")
        mismatch := param4 != "" ? param4 : "跳过"
        this._SetSelectedByKey("MismatchActionCon", mismatch, TimeGui.MismatchActionKeys)
        this._InitCountDownFields(vars)
        this.OnWaitTypeChange()
        this.OnWinTypeChange()
        this.OnCdTypeChange()
    }

    _CmdIsCountDown() {
        key := GetLangKey(RegExReplace(this.SerialStr, "\d+"))
        return key == "倒计时"
    }

    _InitCountDownFields(vars) {
        h := ObjHasOwnProp(this.Data, "Hour") ? this.Data.Hour : ""
        m := ObjHasOwnProp(this.Data, "Min") ? this.Data.Min : ""
        s := ObjHasOwnProp(this.Data, "Sec") ? this.Data.Sec : ""
        if (h == "" && m == "" && s == "") {
            sec := (ObjHasOwnProp(this.Data, "Seconds") && IsNumber(this.Data.Seconds)) ? Integer(this.Data.Seconds) : 10
            if (sec < 0)
                sec := 0
            h := Floor(sec / 3600)
            m := Floor(Mod(sec, 3600) / 60)
            s := Mod(sec, 60)
        }
        this._SetCombo("CdHourCon", vars, h)
        this._SetCombo("CdMinCon", vars, m)
        this._SetCombo("CdSecCon", vars, s)
        cdKind := CountDownKind(this.Data)
        this._SetSelectedByKey("CdKindCon", cdKind, TimeGui.WaitUnitKeys)
        this._SetCombo("CdVarCon", vars, cdKind == "时间戳" ? (ObjHasOwnProp(this.Data, "Param1") ? this.Data.Param1 : "") : "")
        cwh := 14, cwm := 30, cws := 0
        this._ParseClockToHMS(cdKind == "时刻" && ObjHasOwnProp(this.Data, "Param1") ? this.Data.Param1 : "", 14, 30, 0, &cwh, &cwm, &cws)
        if (cdKind == "时刻" && cwh == 14 && cwm == 30 && cws == 0 && (h != "" || m != "" || s != "")) {
            cwh := h, cwm := m, cws := s
        }
        this._SetCombo("CdWaitHourCon", vars, cwh)
        this._SetCombo("CdWaitMinCon", vars, cwm)
        this._SetCombo("CdWaitSecCon", vars, cws)
        this._SetCombo("CdPosXCon", vars, ObjHasOwnProp(this.Data, "PosX") ? this.Data.PosX : 200)
        this._SetCombo("CdPosYCon", vars, ObjHasOwnProp(this.Data, "PosY") ? this.Data.PosY : 200)
    }

    OnModeChange(state := "", ctrl := "", event := "") {
        m := this._ModeValue()
        panelMap := Map(1, "WaitPanel", 2, "WindowPanel", 3, "CountDownPanel")
        show := panelMap.Has(m) ? panelMap[m] : "WaitPanel"
        batch := []
        for name in ["WaitPanel", "WindowPanel", "CountDownPanel"] {
            batch.Push({ControlName: name, PropertyName: "Visibility", Value: (name == show) ? "Visible" : "Collapsed"})
        }
        batch.Push({ControlName: "WaitUnitCon", PropertyName: "Visibility", Value: (m == 1) ? "Visible" : "Collapsed"})
        batch.Push({ControlName: "WinKindCon", PropertyName: "Visibility", Value: (m == 2) ? "Visible" : "Collapsed"})
        batch.Push({ControlName: "CdKindCon", PropertyName: "Visibility", Value: (m == 3) ? "Visible" : "Collapsed"})
        this.ui.BatchUpdate(batch)
        try this.ui.Update("BtnCmdF1", "Visibility", m == 3 ? "Visible" : "Collapsed")
        if (m == 1)
            this.OnWaitTypeChange()
        if (m == 2)
            this.OnWinTypeChange()
        if (m == 3)
            this.OnCdTypeChange()
    }

    OnWaitTypeChange(state := "", ctrl := "", event := "") {
        t := this._GetSelectedKey("WaitUnitCon", TimeGui.WaitUnitKeys)
        t := TimeNormWaitType(t)
        this.ui.Update("WaitTimeRow", "Visibility", t == "时刻" ? "Visible" : "Collapsed")
        this.ui.Update("WaitDurRow", "Visibility", t == "时长" ? "Visible" : "Collapsed")
        this.ui.Update("WaitVarRow", "Visibility", t == "时间戳" ? "Visible" : "Collapsed")
    }

    OnWinTypeChange(state := "", ctrl := "", event := "") {
        t := TimeNormWindowType(this._GetSelectedKey("WinKindCon", TimeGui.WindowKindKeys))
        this.ui.Update("WinTimeRow", "Visibility", t == "时刻" ? "Visible" : "Collapsed")
        this.ui.Update("WinTimeRow2", "Visibility", t == "时刻" ? "Visible" : "Collapsed")
        this.ui.Update("WinVarRow", "Visibility", t == "时间戳" ? "Visible" : "Collapsed")
        this.ui.Update("WinVarRow2", "Visibility", t == "时间戳" ? "Visible" : "Collapsed")
    }

    OnCdTypeChange(state := "", ctrl := "", event := "") {
        t := TimeNormWaitType(this._GetSelectedKey("CdKindCon", TimeGui.WaitUnitKeys))
        this.ui.Update("CdTimeRow", "Visibility", t == "时刻" ? "Visible" : "Collapsed")
        this.ui.Update("CdDurRow", "Visibility", t == "时长" ? "Visible" : "Collapsed")
        this.ui.Update("CdVarRow", "Visibility", t == "时间戳" ? "Visible" : "Collapsed")
    }

    TriggerMacro(*) {
        if (!this.CheckIfValid())
            return
        this.SaveTimeData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    _ModeValue() {
        v := IsObject(this.ui) ? this.ui.Query("TimeModeCon>SelectedIndex") : ""
        return (IsNumber(v) && v >= 0) ? (Integer(v) + 1) : 1
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (this._ModeValue() == 3 && ShouldAutoGenerateRemark(Remark)) {
            sec := this.Data.Seconds
            Remark := CountDownFormatText(sec)
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    OnF1(*) {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        if (!IsObject(this.ui))
            return
        this.ui.Update("CdPosXCon", "Text", mouseX)
        this.ui.Update("CdPosYCon", "Text", mouseY)
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

    _ParseClockToHMS(raw, defH, defM, defS, &h, &m, &s) {
        h := defH, m := defM, s := defS
        raw := Trim(String(raw))
        if (raw == "")
            return
        arr := StrSplit(raw, ":")
        if (arr.Length >= 6) {
            h := arr[4], m := arr[5], s := arr[6]
            return
        }
        if (RegExMatch(raw, "(\d{1,2}):(\d{1,2}):(\d{1,2})\s*$", &mt)) {
            h := Integer(mt[1]), m := Integer(mt[2]), s := Integer(mt[3])
            return
        }
        if (arr.Length >= 3) {
            h := arr[1], m := arr[2], s := arr[3]
            return
        }
        if (arr.Length == 2) {
            h := arr[1], m := arr[2], s := 0
        }
    }

    _ReadHms(hName, mName, sName) {
        return this.ui.Query(hName) ":" this.ui.Query(mName) ":" this.ui.Query(sName)
    }

    _HmsEmpty(hName, mName, sName) {
        return Trim(this.ui.Query(hName)) == "" && Trim(this.ui.Query(mName)) == "" && Trim(this.ui.Query(sName)) == ""
    }

    _ParseDurationToHMS(param1, unit, &h, &m, &s) {
        h := 0, m := 0, s := 10
        u := TimeNormWaitType(unit)
        raw := Trim(String(param1))
        if (u != "时长")
            return
        nu := GetLangKey(unit)
        if (nu == "Minutes" || nu == "分钟") {
            if (IsNumber(raw)) {
                tot := Integer(raw) * 60
                h := Floor(tot / 3600), m := Floor(Mod(tot, 3600) / 60), s := Mod(tot, 60)
            }
            return
        }
        if (nu == "Hours" || nu == "小时") {
            if (IsNumber(raw)) {
                tot := Integer(raw) * 3600
                h := Floor(tot / 3600), m := Floor(Mod(tot, 3600) / 60), s := Mod(tot, 60)
            }
            return
        }
        if (nu == "Days" || nu == "天") {
            if (IsNumber(raw)) {
                tot := Integer(raw) * 86400
                h := Floor(tot / 3600), m := Floor(Mod(tot, 3600) / 60), s := Mod(tot, 60)
            }
            return
        }
        if (RegExMatch(raw, "^(\d+):(\d+):(\d+)$", &mt)) {
            h := Integer(mt[1]), m := Integer(mt[2]), s := Integer(mt[3])
            return
        }
        if (IsNumber(raw)) {
            tot := Integer(raw)
            h := Floor(tot / 3600), m := Floor(Mod(tot, 3600) / 60), s := Mod(tot, 60)
        }
    }

    CheckIfValid() {
        m := this._ModeValue()
        switch m {
            case 1:
                t := TimeNormWaitType(this._GetSelectedKey("WaitUnitCon", TimeGui.WaitUnitKeys))
                if (t == "时刻" && this._HmsEmpty("WaitHourCon", "WaitMinCon", "WaitSecCon")) {
                    RmtDialog.Info(GetLang("请输入目标时间或时长"))
                    return false
                }
                if (t == "时长") {
                    hh := this.ui.Query("HourCon"), mm := this.ui.Query("MinCon"), ss := this.ui.Query("SecCon")
                    if (IsNumber(hh) && IsNumber(mm) && IsNumber(ss) && Number(hh) * 3600 + Number(mm) * 60 + Number(ss) <= 0) {
                        RmtDialog.Info(GetLang("时长请输入大于0的秒数"))
                        return false
                    }
                }
                if (t == "时间戳" && this.ui.Query("WaitVarCon") == "") {
                    RmtDialog.Info(GetLang("请输入目标时间或时长"))
                    return false
                }
            case 2:
                wt := TimeNormWindowType(this._GetSelectedKey("WinKindCon", TimeGui.WindowKindKeys))
                if (wt == "时间戳") {
                    if (this.ui.Query("StartVarCon") == "" || this.ui.Query("EndVarCon") == "") {
                        RmtDialog.Info(GetLang("请输入开始与结束时间"))
                        return false
                    }
                } else if (this._HmsEmpty("StartHourCon", "StartMinCon", "StartSecCon") || this._HmsEmpty("EndHourCon", "EndMinCon", "EndSecCon")) {
                    RmtDialog.Info(GetLang("请输入开始与结束时间"))
                    return false
                }
            case 3:
                ck := TimeNormWaitType(this._GetSelectedKey("CdKindCon", TimeGui.WaitUnitKeys))
                if (ck == "时间戳") {
                    if (this.ui.Query("CdVarCon") == "") {
                        RmtDialog.Info(GetLang("请输入目标时间或时长"))
                        return false
                    }
                } else if (ck == "时刻") {
                    if (this._HmsEmpty("CdWaitHourCon", "CdWaitMinCon", "CdWaitSecCon")) {
                        RmtDialog.Info(GetLang("请输入目标时间或时长"))
                        return false
                    }
                } else {
                    hh := this.ui.Query("CdHourCon"), mm := this.ui.Query("CdMinCon"), ss := this.ui.Query("CdSecCon")
                    if (IsNumber(hh) && IsNumber(mm) && IsNumber(ss) && (Number(hh) < 0 || Number(mm) < 0 || Number(ss) < 0 || Number(hh) * 3600 + Number(mm) * 60 + Number(ss) <= 0)) {
                        RmtDialog.Info(GetLang("时长请输入大于0的秒数"))
                        return false
                    }
                }
        }
        return true
    }

    SaveTimeData() {
        m := this._ModeValue()
        if (this.Data.SerialStr == "")
            this.Data.SerialStr := this.SerialStr
        if (this._CmdIsCountDown() && m != 3) {
            this.SerialStr := GetCMDSerialStr("时间")
            this.Data := TimeData()
            this.Data.SerialStr := this.SerialStr
        }
        if (!this._CmdIsCountDown())
            this.Data.SubMode := this.ModeKeys[m]
        this._StripUnusedTimeFields()

        switch m {
            case 1:
                t := TimeNormWaitType(this._GetSelectedKey("WaitUnitCon", TimeGui.WaitUnitKeys))
                this.Data.Param2 := t
                if (t == "时长")
                    this.Data.Param1 := this._ReadHms("HourCon", "MinCon", "SecCon")
                else if (t == "时间戳")
                    this.Data.Param1 := this.ui.Query("WaitVarCon")
                else
                    this.Data.Param1 := this._ReadHms("WaitHourCon", "WaitMinCon", "WaitSecCon")
                ; 不再展示高级轮询选项；保留已加载的兼容参数，新指令沿用 TimeData 默认值。
            case 2:
                wt := TimeNormWindowType(this._GetSelectedKey("WinKindCon", TimeGui.WindowKindKeys))
                this.Data.Param5 := wt
                if (wt == "时间戳") {
                    this.Data.Param1 := this.ui.Query("StartVarCon")
                    this.Data.Param2 := this.ui.Query("EndVarCon")
                } else {
                    this.Data.Param1 := this._ReadHms("StartHourCon", "StartMinCon", "StartSecCon")
                    this.Data.Param2 := this._ReadHms("EndHourCon", "EndMinCon", "EndSecCon")
                }
                this.Data.Param4 := this._GetSelectedKey("MismatchActionCon", TimeGui.MismatchActionKeys)
            case 3:
                ck := TimeNormWaitType(this._GetSelectedKey("CdKindCon", TimeGui.WaitUnitKeys))
                this.Data.Param2 := ck
                if (ck == "时间戳") {
                    this.Data.Param1 := this.ui.Query("CdVarCon")
                } else if (ck == "时刻") {
                    this.Data.Param1 := this._ReadHms("CdWaitHourCon", "CdWaitMinCon", "CdWaitSecCon")
                    this.Data.Hour := this.ui.Query("CdWaitHourCon")
                    this.Data.Min := this.ui.Query("CdWaitMinCon")
                    this.Data.Sec := this.ui.Query("CdWaitSecCon")
                } else {
                    h := this.ui.Query("CdHourCon")
                    m2 := this.ui.Query("CdMinCon")
                    s := this.ui.Query("CdSecCon")
                    this.Data.Hour := h
                    this.Data.Min := m2
                    this.Data.Sec := s
                    this.Data.Param1 := this._ReadHms("CdHourCon", "CdMinCon", "CdSecCon")
                    if (IsNumber(h) && IsNumber(m2) && IsNumber(s))
                        this.Data.Seconds := Integer(h) * 3600 + Integer(m2) * 60 + Integer(s)
                }
                this.Data.WaitEnd := "不等待"
                this.Data.PosX := this.ui.Query("CdPosXCon")
                this.Data.PosY := this.ui.Query("CdPosYCon")
        }

        SaveMacroCMDData(this.Data)
    }

    _StripUnusedTimeFields() {
        for k in ["FontSize", "Alpha", "Param3"] {
            if (ObjHasOwnProp(this.Data, k))
                this.Data.DeleteProp(k)
        }
    }
}
