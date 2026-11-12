#Requires AutoHotkey v2.0

; =====================================================================
; 增量移动编辑器 —— §20 原「移动Pro-游戏视角」拆出（mouse_event 相对位移）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class DeltaMoveGui {
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
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        ShowMousePreviewButton(this.ui)
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

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("增量移动编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        ; 备注独占一行；坐标偏移X/Y 同行；偏移次数/每次间隔 同行
        body := main.Add("Grid").Grid_Row(1).Margin("15,14,15,14")
        body.Rows("36", "36", "36", "28", "40")
        body.Cols("88", "110", "88", "110")

        ; 行0：备注
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(3).Name("RemarkCon").Height(26).MinHeight(26).HorizontalAlignment("Stretch")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：坐标偏移X / 坐标偏移Y（可编辑下拉，支持变量）
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("偏移值X:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("DeltaXCon").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(1).Grid_Column(2).Text(GetLang("偏移值Y:")).VerticalAlignment("Center").Margin("10,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(1).Grid_Column(3).Name("DeltaYCon").Height(26).MinHeight(26).Margin("10,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行2：偏移次数 / 每次间隔（可编辑下拉，支持变量）
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("偏移次数：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("CountCon").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(2).Grid_Column(2).Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("10,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(2).Grid_Column(3).Name("IntervalCon").Height(26).MinHeight(26).Margin("10,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行3：提示
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(4).Text(GetLang("可调整部分游戏视角")).VerticalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize("11")

        ; 行4：确定按钮
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="460" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/增量移动", ObjBindMethod(this, "TriggerMacro"), "!l")
        BindMouseMovePreview(this.ui, "delta")
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnSureBtnClick"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        MouseMovePreview.Clear(this.ui)
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
        MouseMovePreview.Clear(this.ui)
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

    ToggleFunc(state) {
        if (state) {
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
        } else {
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
        }
    }

    Init(cmd) {
        cmd := RMTParseErrHandle(cmd).cmd
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.Data := DeltaMoveData()
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        DLVarArr := GetGuiVarArr()
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            this.Data := GetMacroCMDData(cmdArr[1])
            dX := this.Data.DeltaX
            dY := this.Data.DeltaY
            cnt := ObjHasOwnProp(this.Data, "Count") ? this.Data.Count : 1
            iv := ObjHasOwnProp(this.Data, "Interval") ? this.Data.Interval : 0
        } else {
            dX := cmdArr.Length >= 2 ? cmdArr[2] : 0
            dY := cmdArr.Length >= 3 ? cmdArr[3] : 0
            cnt := cmdArr.Length >= 4 ? cmdArr[4] : 1
            iv := cmdArr.Length >= 5 ? cmdArr[5] : 0
        }
        this._SetCombo("DeltaXCon", DLVarArr, dX)
        this._SetCombo("DeltaYCon", DLVarArr, dY)
        this._SetCombo("CountCon", DLVarArr, cnt)
        this._SetCombo("IntervalCon", DLVarArr, iv)
    }

    CheckIfValid() {
        cnt := this.ui.Query("CountCon")
        if (IsNumber(cnt) && Integer(cnt) <= 0) {
            RmtDialog.Info(GetLang("偏移次数请输入正整数"))
            return false
        }
        iv := this.ui.Query("IntervalCon")
        if (IsNumber(iv) && Number(iv) < 0) {
            RmtDialog.Info(GetLang("每次间隔不能为负数"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        if (!IsNumber(this.ui.Query("DeltaXCon"))) {
            RmtDialog.Info(GetLang("坐标X是变量时，编辑模式下无法执行"))
            return
        }
        if (!IsNumber(this.ui.Query("DeltaYCon"))) {
            RmtDialog.Info(GetLang("坐标Y是变量时，编辑模式下无法执行"))
            return
        }
        if (!IsNumber(this.ui.Query("CountCon"))) {
            RmtDialog.Info(GetLang("偏移次数是变量时，编辑模式下无法执行"))
            return
        }
        if (!IsNumber(this.ui.Query("IntervalCon"))) {
            RmtDialog.Info(GetLang("每次间隔是变量时，编辑模式下无法执行"))
            return
        }
        CommandStr := this.GetCmdStr()
        OnTriggerSepcialItemMacro(CommandStr)
    }

    OnSureBtnClick(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        CommandStr := this.GetCmdStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    ; 阶段5：指令配置化——组装 Data 保存到配置文件，返回 增量移动<serial>_备注
    GetCmdStr() {
        this.Data.DeltaX := this.ui.Query("DeltaXCon")
        this.Data.DeltaY := this.ui.Query("DeltaYCon")
        this.Data.Count := this.ui.Query("CountCon")
        this.Data.Interval := this.ui.Query("IntervalCon")

        if (this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("增量移动"))
        SaveMacroCMDData(this.Data)
        remark := Trim(this.ui.Query("RemarkCon"))
        if (remark == "")
            remark := this.Data.DeltaX " " this.Data.DeltaY
        return CorrectRemark(this.Data.SerialStr, remark)
    }
}
