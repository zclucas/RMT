#Requires AutoHotkey v2.0

class MenuWheelGlobalSettingGui {
    static instances := Map()

    static ColorNames := ["NormalFill", "NormalStroke", "HoverFill", "HoverStroke", "SelectedFill", "SelectedStroke"]

    static DefaultThemes := Map(
        "Default", {Name: "默认", NormalFill: "#FFFCFCFC", NormalStroke: "#FFC6DFFC", HoverFill: "#FFFDE8E8", HoverStroke: "#FFE81123", SelectedFill: "#FF0078D7", SelectedStroke: "#FFFFFFFF"},
        "DarkNight", {Name: "暗夜", NormalFill: "#FF2D2D2D", NormalStroke: "#FF555555", HoverFill: "#FF3D3D3D", HoverStroke: "#FF00BFFF", SelectedFill: "#FF1A1A2E", SelectedStroke: "#FFFFFFFF"},
        "Neon", {Name: "霓虹", NormalFill: "#FF0D0D0D", NormalStroke: "#FFFF00FF", HoverFill: "#FF1A0A2E", HoverStroke: "#FF00FF41", SelectedFill: "#FF16213E", SelectedStroke: "#FFFFFFFF"},
        "Ocean", {Name: "海洋", NormalFill: "#FFF0F8FF", NormalStroke: "#FF4682B4", HoverFill: "#FFE0F0FF", HoverStroke: "#FF1E90FF", SelectedFill: "#FF0066CC", SelectedStroke: "#FFFFFFFF"},
        "WarmSun", {Name: "暖阳", NormalFill: "#FFFFF8DC", NormalStroke: "#FFDAA520", HoverFill: "#FFFFE4B5", HoverStroke: "#FFFF6347", SelectedFill: "#FFFF8C00", SelectedStroke: "#FFFFFFFF"}
    )

    __new() {
        this.app := 0
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
            "SelectedStroke", "#FFFFFFFF"
        )
        this._fixedPos := false
        this._selectMode := 1
        this._showTooltip := true
        this._currentTheme := "Default"
    }

    static ShowGui() {
        key := "global"
        if (MenuWheelGlobalSettingGui.instances.Has(key)) {
            oldInst := MenuWheelGlobalSettingGui.instances[key]
            if (!oldInst.closed)
                oldInst.Close()
            MenuWheelGlobalSettingGui.instances.Delete(key)
        }
        inst := MenuWheelGlobalSettingGui()
        inst._instanceKey := key
        inst._BuildAndShow()
        MenuWheelGlobalSettingGui.instances[key] := inst
    }

    _BuildAndShow() {
        this.closed := false

        title := GetLang("轮盘选项")
        this.app := XAML_GUI(title, { Sidebar: false, BurgerMenu: false, AppIcon: false, Width: 420, Height: 400 })
        this.app.tabs.Visibility("Collapsed")

        this.LoadThemesFromIni()
        this.BuildContent()

        this.ui := this.app.Compile()
        this.ui.OnEvent("Window", "Closed", ObjBindMethod(this, "OnWindowClosed"))

        this.ui.OnEvent("ThemeCombo", "SelectionChanged", ObjBindMethod(this, "OnThemeSelectionChanged"))
        this.ui.Track("ThemeCombo")

        this.ui.Track("FixedPosCon")
        this.ui.Track("SelectModeCon")
        this.ui.Track("ShowTooltipCon")

        this.ui.OnEvent("FixedPosCon", "Checked", ObjBindMethod(this, "OnFixedPosChanged"))
        this.ui.OnEvent("FixedPosCon", "Unchecked", ObjBindMethod(this, "OnFixedPosChanged"))
        this.ui.OnEvent("SelectModeCon", "SelectionChanged", ObjBindMethod(this, "OnSelectModeChanged"))
        this.ui.OnEvent("ShowTooltipCon", "Checked", ObjBindMethod(this, "OnShowTooltipChanged"))
        this.ui.OnEvent("ShowTooltipCon", "Unchecked", ObjBindMethod(this, "OnShowTooltipChanged"))

        this.ui.OnEvent("BtnRevert", "Click", ObjBindMethod(this, "OnRevertClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.LoadInitValues()

        this.app.Show()

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

    OnWindowClosed(state, ctrl, event) {
        this.closed := true
        if (this._instanceKey != "" && MenuWheelGlobalSettingGui.instances.Has(this._instanceKey))
            MenuWheelGlobalSettingGui.instances.Delete(this._instanceKey)
        if IsObject(this.ui) {
            this.ui.Dispose()
            this.ui := ""
        }
        this.app := ""
    }

    BuildContent() {
        panel := this.app.main.Add("StackPanel").Margin("30, 20")

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

        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,0")
        revertBtn := btnRow.Add("Button").Name("BtnRevert").Content(GetLang("恢复默认")).Use("PrimaryBtn").Width(80).Height(32).Margin("0,0,16,0")
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定")).Use("PrimaryBtn").Width(80).Height(32)
    }

    LoadInitValues() {
        this._fixedPos := !!MySoftData.FixedMenuWheel
        this._selectMode := MySoftData.MenuWheelSelectMode
        this._showTooltip := !!MySoftData.MenuWheelShowTooltip

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
        this.ui.Update("ThemeCombo", "SelectedIndex", "0")
        this.UpdateThemePreview(defaultTheme)

        this._fixedPos := false
        this._selectMode := 1
        this._showTooltip := true
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
            this.ui.Dispose()
            this.ui := ""
        }
        this.app := ""
    }

    SaveData() {
        MySoftData.FixedMenuWheel := this._fixedPos
        MySoftData.MenuWheelSelectMode := this._selectMode
        MySoftData.MenuWheelShowTooltip := this._showTooltip

        global IniFile, IniSection
        iniPath := A_WorkingDir "\Setting\MainSettings.ini"
        IniWrite(MySoftData.FixedMenuWheel, IniFile, IniSection, "FixedMenuWheel")
        IniWrite(MySoftData.MenuWheelSelectMode, IniFile, IniSection, "MenuWheelSelectMode")
        IniWrite(MySoftData.MenuWheelShowTooltip, IniFile, IniSection, "MenuWheelShowTooltip")

        IniWrite(this._currentTheme, iniPath, "MenuWheel", "CurrentTheme")
        for name in MenuWheelGlobalSettingGui.ColorNames
            IniWrite(this.Colors[name], iniPath, "MenuWheel", name)
    }
}
