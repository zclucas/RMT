#Requires AutoHotkey v2.0

class MenuWheelGlobalSettingGui {
    static instances := Map()
    static _opening := false

    static ColorNames := ["NormalFill", "NormalStroke", "HoverFill", "HoverStroke", "SelectedFill", "SelectedStroke", "NormalText", "HoverText", "SelectedText", "SwipeLineColor"]

    static DefaultThemes := Map(
        "Default", {Name: "默认", NormalFill: "#FFFCFCFC", NormalStroke: "#FFC6DFFC", HoverFill: "#FFFDE8E8", HoverStroke: "#FFE81123", SelectedFill: "#FF0078D7", SelectedStroke: "#FFFFFFFF", NormalText: "#CC333333", HoverText: "#FFE81123", SelectedText: "#FFFFFFFF", SwipeLineColor: "#3A88F5"},
        "DarkNight", {Name: "暗夜", NormalFill: "#FF2D2D2D", NormalStroke: "#FF555555", HoverFill: "#FF3D3D3D", HoverStroke: "#FF00BFFF", SelectedFill: "#FF1A1A2E", SelectedStroke: "#FFFFFFFF", NormalText: "#CCAAAAAA", HoverText: "#FF00BFFF", SelectedText: "#FFFFFFFF", SwipeLineColor: "#FF00BFFF"},
        "Neon", {Name: "霓虹", NormalFill: "#FF0D0D0D", NormalStroke: "#FFFF00FF", HoverFill: "#FF1A0A2E", HoverStroke: "#FF00FF41", SelectedFill: "#FF16213E", SelectedStroke: "#FFFFFFFF", NormalText: "#CCDDDDDD", HoverText: "#FF00FF41", SelectedText: "#FFFFFFFF", SwipeLineColor: "#FF00FF41"},
        "Ocean", {Name: "海洋", NormalFill: "#FFF0F8FF", NormalStroke: "#FF4682B4", HoverFill: "#FFE0F0FF", HoverStroke: "#FF1E90FF", SelectedFill: "#FF0066CC", SelectedStroke: "#FFFFFFFF", NormalText: "#CC2C5282", HoverText: "#FF1E90FF", SelectedText: "#FFFFFFFF", SwipeLineColor: "#FF1E90FF"},
        "WarmSun", {Name: "暖阳", NormalFill: "#FFFFF8DC", NormalStroke: "#FFDAA520", HoverFill: "#FFFFE4B5", HoverStroke: "#FFFF6347", SelectedFill: "#FFFF8C00", SelectedStroke: "#FFFFFFFF", NormalText: "#CC8B4513", HoverText: "#FFFF6347", SelectedText: "#FFFFFFFF", SwipeLineColor: "#FFFF6347"}
    )

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this.Themes := Map()
        this.Colors := Map(
            "NormalFill", "#FFFCFCFC",
            "NormalStroke", "#FFC6DFFC",
            "HoverFill", "#FFFDE8E8",
            "HoverStroke", "#FFE81123",
            "SelectedFill", "#FF0078D7",
            "SelectedStroke", "#FFFFFFFF",
            "NormalText", "#CC333333",
            "HoverText", "#FFE81123",
            "SelectedText", "#FFFFFFFF",
            "SwipeLineColor", "#3A88F5"
        )
        this._fixedPos := false
        this._selectMode := 1
        this._showTooltip := true
        this._wheelScale := 100
        this._currentTheme := "Default"
    }

    static ShowGui() {
        key := "global"

        ; 检查已有实例，有则激活并返回
        if (MenuWheelGlobalSettingGui.instances.Has(key)) {
            oldInst := MenuWheelGlobalSettingGui.instances[key]
            if (!oldInst.closed && IsObject(oldInst.ui)) {
                try WinActivate("ahk_id " oldInst.ui.wpfHwnd)
                return
            }
            ; 实例已失效，清理
            if (!oldInst.closed)
                oldInst.Close()
            MenuWheelGlobalSettingGui.instances.Delete(key)
        }

        ; 防重入
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
        titleHeight := "36"

        this.LoadThemesFromIni()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Rows(titleHeight, "*")

        tb := main.Add("Border").Grid_Row(0).Background("Transparent").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")

        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")

        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness(0)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource ControlBg}")

        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        panel := scrollViewer.Add("StackPanel").Margin("30, 16, 30, 20")

        group1 := panel.Add("GroupBox").Header(GetLang("通用选项")).Margin("0,6,0,0")
        inner1 := group1.Add("StackPanel").Margin("14, 12")

        row1 := inner1.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        row1.Add("CheckBox").Name("FixedPosCon").Content(GetLang("固定位置（屏幕中下方）")).Foreground("{DynamicResource TextMain}").Margin("0,0,0,0")

        row2 := inner1.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row2.Add("TextBlock").Text(GetLang("选择模式")).Foreground("{DynamicResource TextSub}").FontSize(11).VerticalAlignment("Center").Width(70)
        modeCombo := row2.Add("ComboBox").Name("SelectModeCon").Width(140).Height(28).Margin("8,0,0,0")
        modeCombo.Add("ComboBoxItem").Content(GetLang("点击选择"))
        modeCombo.Add("ComboBoxItem").Content(GetLang("划线选择"))

        row3 := inner1.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row3.Add("CheckBox").Name("ShowTooltipCon").Content(GetLang("显示扇区名称提示")).Foreground("{DynamicResource TextMain}").Margin("0,0,0,0")

        row4 := inner1.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row4.Add("TextBlock").Text(GetLang("轮盘大小")).Foreground("{DynamicResource TextSub}").FontSize(11).VerticalAlignment("Center").Width(70)
        scaleSlider := row4.Add("Slider").Name("WheelScaleCon").Width(160).Height(28).Margin("8,0,8,0").Minimum(50).Maximum(200).Value(100).IsSnapToTickEnabled("True").TickFrequency("10").Tag("Throttle:50")
        scaleValText := row4.Add("TextBlock").Name("WheelScaleValText").Foreground("{DynamicResource TextMain}").FontSize(12).VerticalAlignment("Center").Width(40)

        group3 := panel.Add("GroupBox").Header(GetLang("主题预设")).Margin("0,16,0,0")
        inner3 := group3.Add("StackPanel").Margin("14, 10")

        selRow := inner3.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        selRow.Add("TextBlock").Text(GetLang("选择主题")).Foreground("{DynamicResource TextSub}").FontSize(11).VerticalAlignment("Center").Width(65)
        themeCombo := selRow.Add("ComboBox").Name("ThemeCombo").Width(160).Height(28).Margin("6,0,0,0")
        for themeKey, themeData in this.Themes
            themeCombo.Add("ComboBoxItem").Content(themeData.Name)

        previewRow := inner3.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Left").Margin("71,8,0,0")
        this._themePrevNames := []
        for name in MenuWheelGlobalSettingGui.ColorNames {
            prevKey := "ThemePrev_" name
            previewRow.Add("Border").Name(prevKey).Width(28).Height(14).CornerRadius("2").Margin("0,0,4,0").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Background("#FF333333")
            this._themePrevNames.Push(prevKey)
        }

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,10")
        revertBtn := btnRow.Add("Button").Name("BtnRevert").Content(GetLang("恢复默认")).Background("{DynamicResource Accent}").Foreground("White").FontWeight("Bold").BorderThickness(0).FontSize(13).Cursor("Hand").Width(80).Height(32).Margin("0,0,16,0")
        revertBtn.InjectResources(PrimaryBtnStyle)
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定")).Background("{DynamicResource Accent}").Foreground("White").FontWeight("Bold").BorderThickness(0).FontSize(13).Cursor("Hand").Width(80).Height(32)
        okBtn.InjectResources(PrimaryBtnStyle)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="420" Height="480"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')

        resourceInject := '<CornerRadius x:Key="PanelRadius">8</CornerRadius>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', resourceInject)

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.ui.Track("ThemeCombo")
        this.ui.OnEvent("ThemeCombo", "SelectionChanged", ObjBindMethod(this, "OnThemeSelectionChanged"))

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

        this.ui.Show()

        ; 等待窗口就绪后激活到最前，避免被主界面挡住
        loop 20 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                break
            }
            Sleep(50)
        }

        SetTimer(ObjBindMethod(this, "ApplyValuesToUI"), -100)
    }

    LoadThemesFromIni() {
        iniPath := A_WorkingDir "\Setting\WheelThemes.ini"
        if (!FileExist(iniPath)) {
            this.CreateDefaultIni(iniPath)
        }

        sections := IniRead(iniPath)
        if (sections == "")
            return

        Loop Parse, sections, "`n", "`r" {
            section := Trim(A_LoopField)
            if (section == "" || !InStr(section, "Theme_"))
                continue

            themeKey := StrReplace(section, "Theme_", "")
            themeData := IniRead(iniPath, section)
            dataObj := {}

            hasValidData := false
            Loop Parse, themeData, "`n", "`r" {
                line := Trim(A_LoopField)
                if (line == "")
                    continue
                parts := StrSplit(line, "=", " `t", 2)
                if (parts.Length != 2)
                    continue
                k := Trim(parts[1])
                v := Trim(parts[2])
                dataObj.%k% := v
                if (k == "NormalFill" || k == "Name")
                    hasValidData := true
            }

            if (hasValidData)
                this.Themes[themeKey] := dataObj
        }

        if (this.Themes.Count == 0) {
            for key, data in MenuWheelGlobalSettingGui.DefaultThemes
                this.Themes[key] := data
        }
    }

    CreateDefaultIni(iniPath) {
        for themeKey, data in MenuWheelGlobalSettingGui.DefaultThemes {
            section := "Theme_" themeKey
            IniWrite(data.Name, iniPath, section, "Name")
            for name in MenuWheelGlobalSettingGui.ColorNames {
                if (data.HasProp(name))
                    IniWrite(data.%name%, iniPath, section, name)
            }
        }
        this.LoadThemesFromIni()
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        MenuWheelGlobalSettingGui._opening := false
        if (this._instanceKey != "" && MenuWheelGlobalSettingGui.instances.Has(this._instanceKey))
            MenuWheelGlobalSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
    }

    OnWindowLoad(state, ctrl, event) {
        themeName := (IsSet(MySoftData) && MySoftData.HasProp("XAMLTheme")) ? MySoftData.XAMLTheme : "RMT Light"
        ApplyXamlTheme(this.ui, themeName)
    }

    LoadInitValues() {
        this._fixedPos := !!MySoftData.FixedMenuWheel
        this._selectMode := MySoftData.MenuWheelSelectMode
        this._showTooltip := !!MySoftData.MenuWheelShowTooltip
        this._wheelScale := MySoftData.MenuWheelScale

        iniPath := A_WorkingDir "\Setting\MainSettings.ini"
        savedTheme := IniRead(iniPath, "MenuWheel", "CurrentTheme", "Default")
        if (this.Themes.Has(savedTheme))
            this._currentTheme := savedTheme

        themeData := this.Themes.Has(this._currentTheme) ? this.Themes[this._currentTheme] : MenuWheelGlobalSettingGui.DefaultThemes["Default"]
        for name in MenuWheelGlobalSettingGui.ColorNames {
            this.Colors[name] := themeData.HasProp(name) ? themeData.%name% : ""
        }
    }

    ApplyValuesToUI() {
        this.ui.Update("FixedPosCon", "IsChecked", this._fixedPos ? "True" : "False")
        this.ui.Update("SelectModeCon", "SelectedIndex", String(this._selectMode - 1))
        this.ui.Update("ShowTooltipCon", "IsChecked", this._showTooltip ? "True" : "False")
        this.ui.Update("WheelScaleCon", "Value", String(this._wheelScale))
        this.ui.Update("WheelScaleValText", "Text", this._wheelScale "%")

        themeIdx := 0
        idx := 0
        for k in this.Themes {
            if (k == this._currentTheme)
                themeIdx := idx
            idx++
        }
        this.ui.Update("ThemeCombo", "SelectedIndex", String(themeIdx))

        if (this.Themes.Has(this._currentTheme))
            this.UpdateThemePreview(this.Themes[this._currentTheme])
    }

    OnFixedPosChanged(state, ctrl, event) {
        this._fixedPos := (event == "Checked")
    }

    OnSelectModeChanged(state, ctrl, event) {
        text := state.Has("SelectModeCon") ? state["SelectModeCon"] : ""
        this._selectMode := (text == GetLang("划线选择")) ? 2 : 1
    }

    OnShowTooltipChanged(state, ctrl, event) {
        this._showTooltip := (event == "Checked")
    }

    OnWheelScaleChanged(state, ctrl, event) {
        valStr := state.Has("WheelScaleCon") ? state["WheelScaleCon"] : ""
        this._wheelScale := Integer(valStr)
        this.ui.Update("WheelScaleValText", "Text", this._wheelScale "%")
    }

    OnThemeSelectionChanged(state, ctrl, event) {
        selText := state.Has("ThemeCombo") ? state["ThemeCombo"] : ""
        if (selText == "")
            return
        themeKey := ""
        for k, data in this.Themes {
            if (data.Name == selText) {
                themeKey := k
                break
            }
        }
        if (themeKey == "")
            return
        themeData := this.Themes[themeKey]
        for name in MenuWheelGlobalSettingGui.ColorNames {
            if (themeData.HasProp(name))
                this.Colors[name] := themeData.%name%
        }
        this.UpdateThemePreview(themeData)
        this._currentTheme := themeKey
    }

    UpdateThemePreview(themeData) {
        for i, name in MenuWheelGlobalSettingGui.ColorNames {
            prevKey := this._themePrevNames[i]
            if (themeData.HasProp(name))
                this.ui.Update(prevKey, "Background", themeData.%name%)
        }
    }

    OnRevertClick(state, ctrl, event) {
        defaultTheme := this.Themes.Has("Default") ? this.Themes["Default"] : MenuWheelGlobalSettingGui.DefaultThemes["Default"]
        for name in MenuWheelGlobalSettingGui.ColorNames {
            if (defaultTheme.HasProp(name))
                this.Colors[name] := defaultTheme.%name%
        }
        this.ui.Update("FixedPosCon", "IsChecked", "False")
        this.ui.Update("SelectModeCon", "SelectedIndex", "0")
        this.ui.Update("ShowTooltipCon", "IsChecked", "True")
        this.ui.Update("WheelScaleCon", "Value", "100")
        this.ui.Update("WheelScaleValText", "Text", "100%")
        this.ui.Update("ThemeCombo", "SelectedIndex", "0")
        this.UpdateThemePreview(defaultTheme)

        this._fixedPos := false
        this._selectMode := 1
        this._showTooltip := true
        this._wheelScale := 100
        this._currentTheme := "Default"
    }

    OnConfirmClick(state, ctrl, event) {
        this.SaveData()
        this.ui.Update("Window", "Close", "")
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try {
                this.ui.Update("Window", "Close", "")
            }
            this.ui := ""
        }
    }

    SaveData() {
        MySoftData.FixedMenuWheel := this._fixedPos
        MySoftData.MenuWheelSelectMode := this._selectMode
        MySoftData.MenuWheelShowTooltip := this._showTooltip
        MySoftData.MenuWheelScale := this._wheelScale

        global IniFile, IniSection
        iniPath := A_WorkingDir "\Setting\MainSettings.ini"
        IniWrite(MySoftData.FixedMenuWheel, IniFile, IniSection, "FixedMenuWheel")
        IniWrite(MySoftData.MenuWheelSelectMode, IniFile, IniSection, "MenuWheelSelectMode")
        IniWrite(MySoftData.MenuWheelShowTooltip, IniFile, IniSection, "MenuWheelShowTooltip")
        IniWrite(MySoftData.MenuWheelScale, IniFile, IniSection, "MenuWheelScale")

        IniWrite(this._currentTheme, iniPath, "MenuWheel", "CurrentTheme")
        for name in MenuWheelGlobalSettingGui.ColorNames
            IniWrite(this.Colors[name], iniPath, "MenuWheel", name)
    }
}
