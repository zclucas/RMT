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
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        ShowMousePreviewButton(this.ui)
        this.ToggleFunc(true)
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("移动编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("8,8,8,13")
        body.Rows("26", "36", "36", "34", "*")
        body.Cols("82", "92", "100", "110")
        speedTip := GetLang("移动速度0~100，100为瞬移")

        ; 行0：鼠标位置
        body.Add("TextBlock").Grid_Row(0).Grid_ColumnSpan(4).Name("MousePosCon").Text(GetLang("当前鼠标位置:0,0")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行1：坐标位置X/Y
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Name("PosXLabel").Text(GetLang("坐标位置X:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(1).Grid_Column(1).Name("PosXCon").Height(26).MinHeight(26).VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Tag("Int|NoIME|MaxLen:6")
        body.Add("TextBlock").Grid_Row(1).Grid_Column(2).Name("PosYLabel").Text(GetLang("坐标位置Y:")).VerticalAlignment("Center").Margin("10,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(1).Grid_Column(3).Name("PosYCon").Height(26).MinHeight(26).Margin("10,0,0,0").VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Tag("Int|NoIME|MaxLen:6")

        ; 行2：移动速度 + 移动方式
        spdHost := body.Add("Border").Grid_Row(2).Grid_Column(0).Background("Transparent").VerticalAlignment("Center").ToolTip(speedTip)
        spdHost.Add("TextBlock").Text(GetLang("移动速度：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(2).Grid_Column(1).Name("SpeedCon").Height(26).MinHeight(26).VerticalContentAlignment("Center").FontSize("11").Padding("4,0").Text("90")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").ToolTip(speedTip).Tag("NumOnly|NoIME|MaxLen:3")
        body.Add("TextBlock").Grid_Row(2).Grid_Column(2).Text(GetLang("移动方式：")).VerticalAlignment("Center").Margin("10,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        mm := body.Add("ComboBox").Grid_Row(2).Grid_Column(3).Name("MouseMoveModeCombo").Height(26).MinHeight(26).Margin("10,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for m in GetLangArr(["绝对移动", "相对移动"])
            mm.Add("ComboBoxItem").Content(m)

        ; 行3：当前指令
        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(4).Name("CommandStrCon").Text(GetLang("当前指令：移动")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行4：确定
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="420" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/5-移动", ObjBindMethod(this, "TriggerMacro"), "!l", ObjBindMethod(this, "OnClickTargeterBtn"), ObjBindMethod(this, "SureCoord"))
        this.ui.OnEvent("PosXCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("PosYCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("SpeedCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("MouseMoveModeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeEditValue"))
        BindMouseMovePreview(this.ui, "move")
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        return CmdEnumFromIndex(v, ["绝对移动", "相对移动"], "绝对移动")
    }

    Init(cmd) {
        ; 阶段5：指令配置化。新格式 移动<serial> 读配置文件；旧格式 移动_X_Y_Speed_MoveMode 兼容
        cmd := RMTParseErrHandle(cmd).cmd
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
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
            MoveMode := cmdArr.Length >= 5 ? cmdArr[5] : "绝对移动"
        }

        this.ui.Update("PosXCon", "Text", PosX)
        this.ui.Update("PosYCon", "Text", PosY)
        this.ui.Update("SpeedCon", "Text", Speed)
        this.ui.Update("MouseMoveModeCombo", "SelectedIndex", String(CmdEnumIndex(MoveMode, ["绝对移动", "相对移动"], 0)))
        this.OnMoveModeChange()
        this.UpdateCommandStr()
    }

    CheckIfValid() {
        if (!IsNumber(this.ui.Query("PosXCon"))) {
            RmtDialog.Info(GetLang("坐标X请输入数字"))
            return false
        }
        if (!IsNumber(this.ui.Query("PosYCon"))) {
            RmtDialog.Info(GetLang("坐标Y请输入数字"))
            return false
        }
        if (!IsInteger(this.ui.Query("SpeedCon"))) {
            RmtDialog.Info(GetLang("移动速度请输入整数"))
            return false
        }
        return true
    }

    UpdateCommandStr() {
        if (!IsObject(this.ui))
            return
        MoveMode := this._MoveMode()
        this.ui.Update("PosXLabel", "Text", GetLang(MoveMode == "相对移动" ? "偏移值X:" : "坐标位置X:"))
        this.ui.Update("PosYLabel", "Text", GetLang(MoveMode == "相对移动" ? "偏移值Y:" : "坐标位置Y:"))
        CommandStr := GetLang("移动")
        CommandStr .= "_" this.ui.Query("PosXCon")
        CommandStr .= "_" this.ui.Query("PosYCon")
        CommandStr .= "_" this.ui.Query("SpeedCon")
        if (MoveMode != "绝对移动")
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
        if (MoveMode == "游戏视角") {
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
        ; 命令串要在关窗前取：_CloseWindow 会把 this.ui 置空，GetCmdStr 里还要读控件
        cmdStr := this.GetCmdStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(cmdStr)
    }

    ; 阶段5：指令配置化——组装 Data 保存到配置文件，返回 移动<serial>_备注
    GetCmdStr() {
        this.Data.PosX := this.ui.Query("PosXCon")
        this.Data.PosY := this.ui.Query("PosYCon")
        this.Data.Speed := this.ui.Query("SpeedCon")
        this.Data.MoveMode := this._MoveMode()

        if (this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("移动"))
        SaveMacroCMDData(this.Data)
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
        if (!IsObject(this.ui))
            return
        if (this._MoveMode() == "相对移动") {
            curX := this.ui.Query("PosXCon")
            curY := this.ui.Query("PosYCon")
            curX := IsNumber(curX) ? Number(curX) : 0
            curY := IsNumber(curY) ? Number(curY) : 0
            mouseX := mouseX - curX
            mouseY := mouseY - curY
        }
        this.ui.Update("PosXCon", "Text", mouseX)
        this.ui.Update("PosYCon", "Text", mouseY)
        this.UpdateCommandStr()
    }
}
