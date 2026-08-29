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
        title := this.ParentTile GetLang("增量移动编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 内容：TabControl（常规 / 错误处理）===
        tc := main.Add("TabControl").Grid_Row(1).Margin("8,8,8,8").Name("MainTab")

        ; ---- Tab1 常规 ----
        ti1 := tc.Add("TabItem").Header(GetLang("常规"))
        body := ti1.Add("Grid").Margin("15,14,15,14")
        body.Rows("40", "40", "34", "30", "*")
        body.Cols("110", "*")

        ; 备注
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("RemarkCon").Width(220).Height(26).MinHeight(26).HorizontalAlignment("Left")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; X 偏移
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("X偏移：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(1).Grid_Column(1).Name("DeltaXCon").Width(160).Height(26).MinHeight(26).HorizontalAlignment("Left").Text("0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; Y 偏移
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("Y偏移：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(2).Grid_Column(1).Name("DeltaYCon").Width(160).Height(26).MinHeight(26).HorizontalAlignment("Left").Text("0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 提示
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(2).Text(GetLang("相对位移（鼠标增量移动），固定走 mouse_event，与按键类型无关；支持 {变量}。")).VerticalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize("11")

        ; ---- Tab2 错误处理 ----
        ti2 := tc.Add("TabItem").Header(GetLang("错误处理"))
        body2 := ti2.Add("Grid").Margin("16,14,16,14")
        body2.Rows("34", "34", "34", "*")
        ehRow1 := body2.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        ehRow1.Add("TextBlock").Text(GetLang("错误处理：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ehCombo := ehRow1.Add("ComboBox").Name("EHModeCombo").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").SelectedIndex("0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ehCombo.Add("ComboBoxItem").Content(GetLang("停止运行")).Tag("stop")
        ehCombo.Add("ComboBoxItem").Content(GetLang("忽略错误并继续")).Tag("ignore")
        ehCombo.Add("ComboBoxItem").Content(GetLang("重试")).Tag("retry")

        ehRow2 := body2.Add("StackPanel").Name("EHRetryRow").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        ehRow2.Add("TextBlock").Text(GetLang("重试次数：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ehRow2.Add("TextBox").Name("EHRetryCount").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ehRow3 := body2.Add("StackPanel").Name("EHIntervalRow").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        ehRow3.Add("TextBlock").Text(GetLang("重试间隔(ms)：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ehRow3.Add("TextBox").Name("EHRetryInterval").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ehBtnRow := body2.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        ehBtnRow.Add("Button").Name("BtnOk2").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0")

        ; 常规 Tab 确定按钮
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="380" SizeToContent="Height" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("EHModeCombo", "SelectionChanged", ObjBindMethod(this, "OnEHModeChange"))
        this.ui.OnEvent("BtnOk2", "Click", ObjBindMethod(this, "OnSureBtnClick"))

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                if (this.OwnerHwnd != "")
                    try this.ui.Update("Window", "NativeOwner", String(this.OwnerHwnd))
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                try SetTimer((*) => this.ui.Update("Window", "Opacity", "1"), -10)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd)
            this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        } finally {
        }
    }

    OnWindowClosing(state, ctrl, event) {
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
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    Init(cmd) {
        eh := RMTParseErrHandle(cmd)
        cmd := eh.cmd
        this._ehCfg := eh.cfg
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.Data := DeltaMoveData()
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            this.Data := GetMacroCMDData(cmdArr[1])
            dX := this.Data.DeltaX
            dY := this.Data.DeltaY
        } else {
            dX := cmdArr.Length >= 2 ? cmdArr[2] : 0
            dY := cmdArr.Length >= 3 ? cmdArr[3] : 0
        }
        this.ui.Update("DeltaXCon", "Text", dX)
        this.ui.Update("DeltaYCon", "Text", dY)
        this._InitEH()
    }

    ; ============ 错误处理（阶段5，影刀模式）============

    _InitEH() {
        mode := this.Data.HasOwnProp("ErrMode") ? this.Data.ErrMode : "stop"
        if (IsObject(this._ehCfg))
            mode := this._ehCfg.mode
        idx := 0
        for i, m in ["stop", "ignore", "retry"] {
            if (m == mode) {
                idx := i - 1
                break
            }
        }
        if (IsObject(this.ui)) {
            this.ui.Update("EHModeCombo", "SelectedIndex", String(idx))
            this.ui.Update("EHRetryCount", "Text", this.Data.HasOwnProp("ErrRetryCount") ? this.Data.ErrRetryCount : "3")
            this.ui.Update("EHRetryInterval", "Text", this.Data.HasOwnProp("ErrRetryInterval") ? this.Data.ErrRetryInterval : "500")
            this.OnEHModeChange()
        }
    }

    _EHMode() {
        v := IsObject(this.ui) ? this.ui.Query("EHModeCombo>SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    OnEHModeChange(state := "", ctrl := "", event := "") {
        showRetry := this._EHMode() == 2
        if (IsObject(this.ui)) {
            this.ui.Update("EHRetryRow", "Visibility", showRetry ? "Visible" : "Collapsed")
            this.ui.Update("EHIntervalRow", "Visibility", showRetry ? "Visible" : "Collapsed")
        }
    }

    CheckIfValid() {
        return true
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
        this.Data.ErrMode := ["stop", "ignore", "retry"][this._EHMode() + 1]
        this.Data.ErrRetryCount := this.ui.Query("EHRetryCount")
        this.Data.ErrRetryInterval := this.ui.Query("EHRetryInterval")

        if (this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("增量移动"))
        SaveMacroCMDData(this.Data)
        remark := Trim(this.ui.Query("RemarkCon"))
        if (remark == "")
            remark := this.Data.DeltaX " " this.Data.DeltaY
        return CorrectRemark(this.Data.SerialStr, remark)
    }
}
