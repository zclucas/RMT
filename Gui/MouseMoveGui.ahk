#Requires AutoHotkey v2.0

; =====================================================================
; 移动编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class MouseMoveGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this.PosAction := () => this.RefreshMousePos()
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

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("鼠标移动编辑器")
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
        body := ti1.Add("Grid").Margin("10,10,10,10")
        body.Rows("30", "34", "30", "26", "36", "36", "24", "34", "*")
        body.Cols("90", "100", "90", "130")

        ; 行0：备注（放选项卡第一个位置）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(3).Name("RemarkCon").Height(26).MinHeight(26).Margin("0,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：快捷方式 + 执行指令
        row0 := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        row0.Add("TextBox").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0").Text("!l").IsReadOnly("True").VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(28).MinHeight(28).Padding("14,0").Margin("14,0,0,0").Cursor("Hand")

        ; 行2：F1 + 定位取色器
        row1 := body.Add("StackPanel").Grid_Row(2).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("F1:选取当前坐标")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ; 定位取色器组：按钮+说明提示挂盒子（主界面 _LabelRow 同款）
        tgtBox := row1.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center").Margin("14,0,0,0").ToolTip("1.左键拖拽改变位置`n2.上下左右方向键微调位置`n3.左键双击或回车键关闭取色器，同时确定点位信息")
        tgtBox.Add("Button").Name("BtnTargeter").Content(GetLang("定位取色器")).Width(100).Height(28).MinHeight(28).Padding("14,0").Cursor("Hand")

        ; 行3：鼠标位置
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(4).Name("MousePosCon").Text(GetLang("当前鼠标位置:0,0")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行4：坐标位置X/Y
        body.Add("TextBlock").Grid_Row(4).Grid_Column(0).Text(GetLang("坐标位置X:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(4).Grid_Column(1).Name("PosXCon").Height(26).MinHeight(26).VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(4).Grid_Column(2).Text(GetLang("坐标位置Y:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(4).Grid_Column(3).Name("PosYCon").Height(26).MinHeight(26).VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行5：移动速度 + 移动方式（§20 去「游戏视角」，已拆为增量移动指令）
        body.Add("TextBlock").Grid_Row(5).Grid_Column(0).Text(GetLang("移动速度：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(5).Grid_Column(1).Name("SpeedCon").Height(26).MinHeight(26).VerticalContentAlignment("Center").FontSize("11").Padding("4,0").Text("90")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(5).Grid_Column(2).Text(GetLang("移动方式：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        mm := body.Add("ComboBox").Grid_Row(5).Grid_Column(3).Name("MouseMoveModeCombo").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for m in GetLangArr(["绝对移动", "相对移动"])
            mm.Add("ComboBoxItem").Content(m)

        ; 行6：提示
        body.Add("TextBlock").Grid_Row(6).Grid_ColumnSpan(4).Text(GetLang("移动速度0~100，100为瞬移")).VerticalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize("11")

        ; 行7：当前指令
        body.Add("TextBlock").Grid_Row(7).Grid_ColumnSpan(4).Name("CommandStrCon").Text(GetLang("当前指令：鼠标移动")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行8：确定
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0")

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

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="500" SizeToContent="Height" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("PosXCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("PosYCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("SpeedCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("MouseMoveModeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("BtnTargeter", "Click", ObjBindMethod(this, "OnClickTargeterBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("EHModeCombo", "SelectionChanged", ObjBindMethod(this, "OnEHModeChange"))
        this.ui.OnEvent("BtnOk2", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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

    _MoveMode() {
        v := IsObject(this.ui) ? this.ui.Query("MouseMoveModeCombo>SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    Init(cmd) {
        ; 阶段5：指令配置化。新格式 移动<serial> 读配置文件；旧格式 移动_X_Y_Speed_MoveMode 兼容
        eh := RMTParseErrHandle(cmd)
        cmd := eh.cmd
        this._ehCfg := eh.cfg
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        ; 备注：指令串第二段（移动<serial>_备注 或 旧 移动_X_Y 均取第二段）
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            ; 新格式：读配置文件 Data
            this.Data := GetMacroCMDData(cmdArr[1])
            PosX := this.Data.PosX
            PosY := this.Data.PosY
            Speed := this.Data.Speed
            MoveMode := this.Data.MoveMode
        } else {
            this.Data := MoveDataConfig()
            PosX := cmdArr.Length >= 2 ? cmdArr[2] : 0
            PosY := cmdArr.Length >= 3 ? cmdArr[3] : 0
            Speed := cmdArr.Length >= 4 ? cmdArr[4] : 90
            MoveMode := cmdArr.Length >= 5 ? Integer(cmdArr[5]) : 0
        }

        this.ui.Update("PosXCon", "Text", PosX)
        this.ui.Update("PosYCon", "Text", PosY)
        this.ui.Update("SpeedCon", "Text", Speed)
        this.ui.Update("MouseMoveModeCombo", "SelectedIndex", String(MoveMode))
        this.OnMoveModeChange()
        this.UpdateCommandStr()
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
        if (!IsNumber(this.ui.Query("PosXCon"))) {
            MsgBox(GetLang("坐标X请输入数字"))
            return false
        }
        if (!IsNumber(this.ui.Query("PosYCon"))) {
            MsgBox(GetLang("坐标Y请输入数字"))
            return false
        }
        if (!IsInteger(this.ui.Query("SpeedCon"))) {
            MsgBox(GetLang("移动速度请输入整数"))
            return false
        }
        return true
    }

    UpdateCommandStr() {
        if (!IsObject(this.ui))
            return
        MoveMode := this._MoveMode()
        CommandStr := GetLang("鼠标移动")
        CommandStr .= "_" this.ui.Query("PosXCon")
        CommandStr .= "_" this.ui.Query("PosYCon")
        CommandStr .= "_" this.ui.Query("SpeedCon")
        if (MoveMode != 0)
            CommandStr .= "_" MoveMode
        this.ui.Update("CommandStrCon", "Text", CommandStr)
    }

    ToggleFunc(state) {
        if (state) {
            try SetTimer this.PosAction, 100
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
            try Hotkey("F1", (*) => this.SureCoord(), "On")
        }
        else {
            try SetTimer this.PosAction, 0
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
            try Hotkey("F1", (*) => this.SureCoord(), "Off")
        }
    }

    RefreshMousePos() {
        static posLabel := ""
        if (posLabel == "")
            posLabel := GetLang("当前鼠标位置:")
        if (!IsObject(this.ui))
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.ui.Update("MousePosCon", "Text", posLabel mouseX "," mouseY)
    }

    OnChangeEditValue(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this.OnMoveModeChange()
        this.UpdateCommandStr()
    }

    OnMoveModeChange() {
        if (!IsObject(this.ui))
            return
        MoveMode := this._MoveMode()
        if (MoveMode == 2) {
            this.ui.Update("SpeedCon", "Text", "100")
            this.ui.Update("SpeedCon", "IsEnabled", "False")
        }
        else {
            this.ui.Update("SpeedCon", "IsEnabled", "True")
        }
    }

    OnSureTarget(PosX, PosY, Color) {
        if (IsObject(this.ui)) {
            this.ui.Update("PosXCon", "Text", PosX)
            this.ui.Update("PosYCon", "Text", PosY)
            this.UpdateCommandStr()
        }
    }

    OnClickTargeterBtn(state := "", ctrl := "", event := "") {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.UpdateCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(this.GetCmdStr())
    }

    ; 阶段5：指令配置化——组装 Data 保存到配置文件，返回 移动<serial>_备注
    GetCmdStr() {
        this.Data.PosX := this.ui.Query("PosXCon")
        this.Data.PosY := this.ui.Query("PosYCon")
        this.Data.Speed := this.ui.Query("SpeedCon")
        this.Data.MoveMode := this._MoveMode()
        ; 错误处理（阶段5）
        this.Data.ErrMode := ["stop", "ignore", "retry"][this._EHMode() + 1]
        this.Data.ErrRetryCount := this.ui.Query("EHRetryCount")
        this.Data.ErrRetryInterval := this.ui.Query("EHRetryInterval")

        if (this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("鼠标移动"))
        SaveMacroCMDData(this.Data)
        ; 备注：用户备注优先，为空则自动生成操作内容（CorrectRemark 会剔除逗号，故用空格分隔）
        remark := Trim(this.ui.Query("RemarkCon"))
        if (remark == "")
            remark := this.Data.PosX " " this.Data.PosY
        return CorrectRemark(this.Data.SerialStr, remark)
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.UpdateCommandStr()
        OnTriggerSepcialItemMacro(this.ui.Query("CommandStrCon"))
    }

    SureCoord() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        if (IsObject(this.ui)) {
            this.ui.Update("PosXCon", "Text", mouseX)
            this.ui.Update("PosYCon", "Text", mouseY)
            this.UpdateCommandStr()
        }
    }
}
