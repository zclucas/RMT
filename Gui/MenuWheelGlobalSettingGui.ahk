#Requires AutoHotkey v2.0

class MenuWheelGlobalSettingGui {
    static instances := Map()
    static _opening := false

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._fixedPos := false
        this._selectMode := 2
        this._showTooltip := false
        this._wheelScale := 100
        this._applyingUI := false
    }

    static ShowGui() {
        key := "global"
        if (MenuWheelGlobalSettingGui.instances.Has(key)) {
            oldInst := MenuWheelGlobalSettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            MenuWheelGlobalSettingGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (MenuWheelGlobalSettingGui._opening)
            return
        MenuWheelGlobalSettingGui._opening := true
        try {
            inst := MenuWheelGlobalSettingGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            MenuWheelGlobalSettingGui.instances[key] := inst
        } finally {
            MenuWheelGlobalSettingGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("轮盘选项")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        panel := scrollViewer.Add("StackPanel").Margin("30, 6, 30, 12")

        row3 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        row3.Add("CheckBox").Name("ShowTooltipCon").Content(GetLang("显示扇区名称提示")).Foreground("{DynamicResource TextMain}").FontSize(13)

        row1 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row1.Add("CheckBox").Name("FixedPosCon").Content(GetLang("固定位置（屏幕中下方）")).Foreground("{DynamicResource TextMain}").FontSize(13)

        row2 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row2.Add("TextBlock").Text(GetLang("选择模式") "：").Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center").Width(70)
        modeCombo := row2.Add("ComboBox").Name("SelectModeCon").Width(140).Height(26).MinHeight(26).Margin("8,0,0,0")
        modeCombo.Add("ComboBoxItem").Content(GetLang("点击选择"))
        modeCombo.Add("ComboBoxItem").Content(GetLang("划线选择"))

        row4 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row4.Add("TextBlock").Text(GetLang("轮盘大小") "：").Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center").Width(70)
        row4.Add("Slider").Name("WheelScaleCon").Width(160).Height(28).Margin("8,0,8,0").Minimum(50).Maximum(200).Value(100).IsSnapToTickEnabled("True").TickFrequency("10").Tag("Throttle:50")
        row4.Add("TextBlock").Name("WheelScaleValText").Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center").Width(40)

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,10")
        revertBtn := btnRow.Add("Button").Name("BtnRevert").Content(GetLang("恢复默认"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(80).Height(32).Margin("0,0,16,0")
        revertBtn.InjectResources(PrimaryBtnStyle)
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(80).Height(32)
        okBtn.InjectResources(PrimaryBtnStyle)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="340" Height="250" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.Track("FixedPosCon")
        this.ui.Track("SelectModeCon")
        this.ui.Track("ShowTooltipCon")
        this.ui.Track("WheelScaleCon")
        this.ui.OnEvent("FixedPosCon", "Checked", ObjBindMethod(this, "OnFixedPosChanged"))
        this.ui.OnEvent("FixedPosCon", "Unchecked", ObjBindMethod(this, "OnFixedPosChanged"))
        this.ui.OnEvent("SelectModeCon", "SelectionChanged", ObjBindMethod(this, "OnSelectModeChanged"))
        this.ui.OnEvent("ShowTooltipCon", "Checked", ObjBindMethod(this, "OnShowTooltipChanged"))
        this.ui.OnEvent("ShowTooltipCon", "Unchecked", ObjBindMethod(this, "OnShowTooltipChanged"))
        this.ui.OnEvent("WheelScaleCon", "ValueChanged", ObjBindMethod(this, "OnWheelScaleChanged"))
        this.ui.OnEvent("BtnRevert", "Click", ObjBindMethod(this, "OnRevertClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.LoadInitValues()
        this.ApplyValuesToUI()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        MenuWheelGlobalSettingGui._opening := false
        if (this._instanceKey != "" && MenuWheelGlobalSettingGui.instances.Has(this._instanceKey))
            MenuWheelGlobalSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    LoadInitValues() {
        this._fixedPos := !!MainSoftData.FixedMenuWheel
        this._selectMode := MainSoftData.MenuWheelSelectMode
        this._showTooltip := !!MainSoftData.MenuWheelShowTooltip
        this._wheelScale := MainSoftData.MenuWheelScale
    }

    ApplyValuesToUI() {
        this._applyingUI := true
        try {
            this.ui.Update("FixedPosCon", "IsChecked", this._fixedPos ? "True" : "False")
            this.ui.Update("SelectModeCon", "SelectedIndex", String(this._selectMode - 1))
            this.ui.Update("ShowTooltipCon", "IsChecked", this._showTooltip ? "True" : "False")
            this.ui.Update("WheelScaleCon", "Value", String(this._wheelScale))
            this.ui.Update("WheelScaleValText", "Text", this._wheelScale "%")
        } finally {
            this._applyingUI := false
        }
    }

    OnFixedPosChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        this._fixedPos := (event == "Checked")
    }

    OnSelectModeChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("SelectModeCon") ? state["SelectModeCon"] : ""
        this._selectMode := (text == GetLang("划线选择")) ? 2 : 1
    }

    OnShowTooltipChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        this._showTooltip := (event == "Checked")
    }

    OnWheelScaleChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("WheelScaleCon") ? state["WheelScaleCon"] : ""
        this._wheelScale := Integer(valStr)
        this.ui.Update("WheelScaleValText", "Text", this._wheelScale "%")
    }

    OnRevertClick(state, ctrl, event) {
        this.ui.Update("FixedPosCon", "IsChecked", "False")
        this.ui.Update("SelectModeCon", "SelectedIndex", "1")
        this.ui.Update("ShowTooltipCon", "IsChecked", "False")
        this.ui.Update("WheelScaleCon", "Value", "100")
        this.ui.Update("WheelScaleValText", "Text", "100%")
        this._fixedPos := false
        this._selectMode := 2
        this._showTooltip := false
        this._wheelScale := 100
    }

    OnConfirmClick(state, ctrl, event) {
        this.SaveData()
        this.ui.Update("Window", "Close", "")
    }

    OnCancelClick(state, ctrl, event) {
        this.ui.Update("Window", "Close", "")
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    SaveData() {
        MainSoftData.FixedMenuWheel := this._fixedPos
        MainSoftData.MenuWheelSelectMode := this._selectMode
        MainSoftData.MenuWheelShowTooltip := this._showTooltip
        MainSoftData.MenuWheelScale := this._wheelScale
        IniWrite(MainSoftData.FixedMenuWheel, IniFile, IniSection, "FixedMenuWheel")
        IniWrite(MainSoftData.MenuWheelSelectMode, IniFile, IniSection, "MenuWheelSelectMode")
        IniWrite(MainSoftData.MenuWheelShowTooltip, IniFile, IniSection, "MenuWheelShowTooltip")
        IniWrite(MainSoftData.MenuWheelScale, IniFile, IniSection, "MenuWheelScale")
    }
}
