#Requires AutoHotkey v2.0

; 功能选项「指令录制」：XAML 录制选项编辑器

class ToolRecordSettingGui {
    static instances := Map()
    static _opening := false

    static TrailModes := ["不录制", "关键点位", "关键点相对位移", "全量"]

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._syncing := false
        this._autoLoosen := true
        this._holdMuti := false
        this._keyboard := true
        this._mouse := true
        this._trailMode := 1      ; 0~3
        this._trailSpeed := 95
        this._joy := false
        this._joyInterval := 50
        this._showBorder := true
    }

    ; 兼容旧入口 MyToolRecordSettingGui.ShowGui()
    ShowGui() {
        ToolRecordSettingGui.ShowGui()
    }

    static ShowGui() {
        key := "global"
        if (ToolRecordSettingGui.instances.Has(key)) {
            oldInst := ToolRecordSettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            ToolRecordSettingGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (ToolRecordSettingGui._opening)
            return
        ToolRecordSettingGui._opening := true
        try {
            inst := ToolRecordSettingGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            ToolRecordSettingGui.instances[key] := inst
        } finally {
            ToolRecordSettingGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("录制选项")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        panel := scrollViewer.Add("StackPanel").Margin("18, 8, 18, 10")

        labelFg := "{DynamicResource TextMain}"
        labelFs := 13

        ; ===== 通用选项 =====
        gCommon := panel.Add("GroupBox").Header(GetLang("通用选项")).Margin("0,0,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground(labelFg)
        commonInner := gCommon.Add("StackPanel").Margin("12, 8")
        rowCommon1 := commonInner.Add("StackPanel").Orientation("Horizontal").Margin("0,2,0,0")
        rowCommon1.Add("CheckBox").Name("ShowBorderCon").Content(GetLang("录制显示边框"))
            .Foreground(labelFg).FontSize(labelFs).Width(230)
        rowCommon1.Add("CheckBox").Name("HoldMutiCon").Content(GetLang("长按多次录制"))
            .Foreground(labelFg).FontSize(labelFs)
        commonInner.Add("CheckBox").Name("AutoLoosenCon").Content(GetLang("录制结束自动添加按键松开指令"))
            .Foreground(labelFg).FontSize(labelFs).Margin("0,10,0,0")

        ; ===== 键盘选项 =====
        gKey := panel.Add("GroupBox").Header(GetLang("键盘选项")).Margin("0,8,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground(labelFg)
        keyInner := gKey.Add("StackPanel").Margin("12, 8")
        keyInner.Add("CheckBox").Name("KeyboardTogCon").Content(GetLang("录制开关"))
            .Foreground(labelFg).FontSize(labelFs)

        ; ===== 鼠标选项 =====
        gMouse := panel.Add("GroupBox").Header(GetLang("鼠标选项")).Margin("0,8,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground(labelFg)
        mouseInner := gMouse.Add("StackPanel").Margin("12, 8")
        rowMouse1 := mouseInner.Add("StackPanel").Orientation("Horizontal").Margin("0,2,0,0")
        rowMouse1.Add("CheckBox").Name("MouseTogCon").Content(GetLang("录制开关"))
            .Foreground(labelFg).FontSize(labelFs).Width(110).VerticalAlignment("Center")
        rowMouse1.Add("TextBlock").Name("TrailSpeedTipCon").Text(GetLang("速度(0~100)："))
            .Foreground(labelFg).FontSize(labelFs).VerticalAlignment("Center").Margin("120,0,0,0")
        rowMouse1.Add("TextBox").Name("MouseTrailSpeedCon")
            .Width(60).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11).Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        rowMouse2 := mouseInner.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        rowMouse2.Add("TextBlock").Text(GetLang("鼠标轨迹") "：")
            .Foreground(labelFg).FontSize(labelFs).VerticalAlignment("Center")
        trailCombo := rowMouse2.Add("ComboBox").Name("MouseTrailModeCon").Width(140).Height(26).MinHeight(26).Margin("6,0,0,0")
        for modeName in ToolRecordSettingGui.TrailModes
            trailCombo.Add("ComboBoxItem").Content(GetLang(modeName))

        ; ===== 手柄选项 =====
        gJoy := panel.Add("GroupBox").Header(GetLang("手柄选项")).Margin("0,8,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground(labelFg)
        joyInner := gJoy.Add("StackPanel").Margin("12, 8")
        rowJoy := joyInner.Add("StackPanel").Orientation("Horizontal").Margin("0,2,0,0")
        rowJoy.Add("CheckBox").Name("JoyTogCon").Content(GetLang("录制开关"))
            .Foreground(labelFg).FontSize(labelFs).Width(110).VerticalAlignment("Center")
        rowJoy.Add("TextBlock").Name("JoyIntervalTipCon").Text(GetLang("检测间隔(ms)："))
            .Foreground(labelFg).FontSize(labelFs).VerticalAlignment("Center").Margin("120,0,0,0")
        rowJoy.Add("TextBox").Name("JoyIntervalCon")
            .Width(60).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11).Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,16,0,6")
        revertBtn := btnRow.Add("Button").Name("BtnRevert").Content(GetLang("恢复默认"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(90).Height(32).Margin("0,0,16,0")
            .IsDefault("False").IsCancel("False")
        revertBtn.InjectResources(PrimaryBtnStyle)
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(80).Height(32)
            .IsDefault("False").IsCancel("False")
        okBtn.InjectResources(PrimaryBtnStyle)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="480" Height="450" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnRevert", "Click", ObjBindMethod(this, "OnRevertClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.ui.Track("AutoLoosenCon")
        this.ui.Track("HoldMutiCon")
        this.ui.Track("KeyboardTogCon")
        this.ui.Track("MouseTogCon")
        this.ui.Track("MouseTrailModeCon")
        this.ui.Track("MouseTrailSpeedCon")
        this.ui.Track("JoyTogCon")
        this.ui.Track("JoyIntervalCon")
        this.ui.Track("ShowBorderCon")

        this.ui.OnEvent("MouseTogCon", "Checked", ObjBindMethod(this, "OnMouseTogChanged"))
        this.ui.OnEvent("MouseTogCon", "Unchecked", ObjBindMethod(this, "OnMouseTogChanged"))
        this.ui.OnEvent("JoyTogCon", "Checked", ObjBindMethod(this, "OnJoyTogChanged"))
        this.ui.OnEvent("JoyTogCon", "Unchecked", ObjBindMethod(this, "OnJoyTogChanged"))
        this.ui.OnEvent("MouseTrailModeCon", "SelectionChanged", ObjBindMethod(this, "OnTrailModeChanged"))
        this.ui.OnEvent("MouseTrailSpeedCon", "TextChanged", ObjBindMethod(this, "OnTrailSpeedTextChanged"))
        this.ui.OnEvent("JoyIntervalCon", "TextChanged", ObjBindMethod(this, "OnJoyIntervalTextChanged"))
        this.ui.OnEvent("AutoLoosenCon", "Checked", ObjBindMethod(this, "OnAutoLoosenChanged"))
        this.ui.OnEvent("AutoLoosenCon", "Unchecked", ObjBindMethod(this, "OnAutoLoosenChanged"))
        this.ui.OnEvent("HoldMutiCon", "Checked", ObjBindMethod(this, "OnHoldMutiChanged"))
        this.ui.OnEvent("HoldMutiCon", "Unchecked", ObjBindMethod(this, "OnHoldMutiChanged"))
        this.ui.OnEvent("KeyboardTogCon", "Checked", ObjBindMethod(this, "OnKeyboardTogChanged"))
        this.ui.OnEvent("KeyboardTogCon", "Unchecked", ObjBindMethod(this, "OnKeyboardTogChanged"))
        this.ui.OnEvent("ShowBorderCon", "Checked", ObjBindMethod(this, "OnShowBorderChanged"))
        this.ui.OnEvent("ShowBorderCon", "Unchecked", ObjBindMethod(this, "OnShowBorderChanged"))

        this.LoadInitValues()
        this.ApplyValuesToUI()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    LoadInitValues() {
        this._autoLoosen := !!MainSoftData.RecordAutoLoosen
        this._holdMuti := !!MainSoftData.RecordHoldMuti
        this._keyboard := !!MainSoftData.RecordKeyboard
        this._mouse := !!MainSoftData.RecordMouse
        this._trailMode := Max(0, Min(3, Integer(MainSoftData.RecordMouseTrail)))
        this._trailSpeed := Max(0, Min(100, Integer(MainSoftData.RecordMouseTrailSpeed)))
        this._joy := !!MainSoftData.RecordJoy
        this._joyInterval := Max(1, Integer(MainSoftData.RecordJoyInterval))
        this._showBorder := !!MainSoftData.RecordShowBorder
    }

    ApplyValuesToUI() {
        if (!IsObject(this.ui))
            return
        this._syncing := true
        try {
            this.ui.Update("AutoLoosenCon", "IsChecked", this._autoLoosen ? "True" : "False")
            this.ui.Update("HoldMutiCon", "IsChecked", this._holdMuti ? "True" : "False")
            this.ui.Update("KeyboardTogCon", "IsChecked", this._keyboard ? "True" : "False")
            this.ui.Update("MouseTogCon", "IsChecked", this._mouse ? "True" : "False")
            this.ui.Update("MouseTrailModeCon", "SelectedIndex", String(this._trailMode))
            this.ui.Update("MouseTrailSpeedCon", "Text", String(this._trailSpeed))
            this.ui.Update("JoyTogCon", "IsChecked", this._joy ? "True" : "False")
            this.ui.Update("JoyIntervalCon", "Text", String(this._joyInterval))
            this.ui.Update("ShowBorderCon", "IsChecked", this._showBorder ? "True" : "False")
            this._RefreshEnabled()
        } finally {
            this._syncing := false
        }
    }

    _RefreshEnabled() {
        if (!IsObject(this.ui))
            return
        isKeyPointTrail := (this._trailMode == 1 || this._trailMode == 2)
        trailSpeedOn := this._mouse && isKeyPointTrail
        this.ui.Update("MouseTrailModeCon", "IsEnabled", this._mouse ? "True" : "False")
        this.ui.Update("MouseTrailSpeedCon", "IsEnabled", trailSpeedOn ? "True" : "False")
        this.ui.Update("TrailSpeedTipCon", "IsEnabled", trailSpeedOn ? "True" : "False")
        this.ui.Update("JoyIntervalCon", "IsEnabled", this._joy ? "True" : "False")
        this.ui.Update("JoyIntervalTipCon", "IsEnabled", this._joy ? "True" : "False")
    }

    OnAutoLoosenChanged(state, ctrl, event) {
        if (this._syncing)
            return
        this._autoLoosen := (event == "Checked")
    }

    OnHoldMutiChanged(state, ctrl, event) {
        if (this._syncing)
            return
        this._holdMuti := (event == "Checked")
    }

    OnKeyboardTogChanged(state, ctrl, event) {
        if (this._syncing)
            return
        this._keyboard := (event == "Checked")
    }

    OnMouseTogChanged(state, ctrl, event) {
        if (this._syncing)
            return
        this._mouse := (event == "Checked")
        this._RefreshEnabled()
    }

    OnJoyTogChanged(state, ctrl, event) {
        if (this._syncing)
            return
        this._joy := (event == "Checked")
        this._RefreshEnabled()
    }

    OnShowBorderChanged(state, ctrl, event) {
        if (this._syncing)
            return
        this._showBorder := (event == "Checked")
    }

    OnTrailModeChanged(state, ctrl, event) {
        if (this._syncing)
            return
        text := state.Has("MouseTrailModeCon") ? state["MouseTrailModeCon"] : ""
        for i, name in ToolRecordSettingGui.TrailModes {
            if (text == GetLang(name) || text == name) {
                this._trailMode := i - 1
                break
            }
        }
        this._RefreshEnabled()
    }

    OnTrailSpeedTextChanged(state, ctrl, event) {
        if (this._syncing)
            return
        text := state.Has("MouseTrailSpeedCon") ? state["MouseTrailSpeedCon"] : ""
        if (text == "" || !IsNumber(text))
            return
        this._trailSpeed := Max(0, Min(100, Integer(Round(Number(text)))))
    }

    OnJoyIntervalTextChanged(state, ctrl, event) {
        if (this._syncing)
            return
        text := state.Has("JoyIntervalCon") ? state["JoyIntervalCon"] : ""
        if (text == "" || !IsNumber(text))
            return
        this._joyInterval := Max(1, Integer(Round(Number(text))))
    }

    OnRevertClick(state, ctrl, event) {
        this._autoLoosen := true
        this._holdMuti := false
        this._keyboard := true
        this._mouse := true
        this._trailMode := 1
        this._trailSpeed := 95
        this._joy := false
        this._joyInterval := 50
        this._showBorder := true
        this.ApplyValuesToUI()
    }

    OnConfirmClick(state, ctrl, event) {
        this.SaveData()
        this.ui.Update("Window", "Close", "")
    }

    OnCancelClick(state, ctrl, event) {
        this.ui.Update("Window", "Close", "")
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        ToolRecordSettingGui._opening := false
        if (this._instanceKey != "" && ToolRecordSettingGui.instances.Has(this._instanceKey))
            ToolRecordSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            XamlWin.OnLoadTheme(this.ui)
            this.ApplyValuesToUI()
        } finally {
            this.ui.Update("Window", "Opacity", "1")
        }
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    SaveData() {
        MainSoftData.RecordAutoLoosen := this._autoLoosen
        MainSoftData.RecordHoldMuti := this._holdMuti
        MainSoftData.RecordKeyboard := this._keyboard
        MainSoftData.RecordMouse := this._mouse
        MainSoftData.RecordMouseTrail := this._trailMode
        MainSoftData.RecordMouseTrailSpeed := this._trailSpeed
        MainSoftData.RecordJoy := this._joy
        MainSoftData.RecordJoyInterval := this._joyInterval
        MainSoftData.RecordShowBorder := this._showBorder

        IniWrite(MainSoftData.RecordAutoLoosen, IniFile, IniSection, "RecordAutoLoosen")
        IniWrite(MainSoftData.RecordHoldMuti, IniFile, IniSection, "RecordHoldMuti")
        IniWrite(MainSoftData.RecordKeyboard, IniFile, IniSection, "RecordKeyboard")
        IniWrite(MainSoftData.RecordMouse, IniFile, IniSection, "RecordMouse")
        IniWrite(MainSoftData.RecordMouseTrail, IniFile, IniSection, "RecordMouseTrail")
        IniWrite(MainSoftData.RecordMouseTrailSpeed, IniFile, IniSection, "RecordMouseTrailSpeed")
        IniWrite(MainSoftData.RecordJoy, IniFile, IniSection, "RecordJoy")
        IniWrite(MainSoftData.RecordJoyInterval, IniFile, IniSection, "RecordJoyInterval")
        IniWrite(MainSoftData.RecordShowBorder, IniFile, IniSection, "RecordShowBorder")
    }
}
