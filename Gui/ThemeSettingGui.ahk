#Requires AutoHotkey v2.0

class ThemeSettingGui {
    static instances := Map()
    static _opening := false

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._themeKey := AppThemeUtil.DefaultThemeKey
        this._colors := Map()
        this._applyingTheme := false
    }

    static ShowGui() {
        key := "global"
        XamlUiDiag("ShowGui enter _opening=" ThemeSettingGui._opening " hasInst=" ThemeSettingGui.instances.Has(key), "Theme")
        XamlUiDiagDaemon("Theme.pre")
        if (ThemeSettingGui.instances.Has(key)) {
            oldInst := ThemeSettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            reuse := (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd))
            XamlUiDiag(Format("oldInst closed={} hwnd={} reuse={}", oldInst.closed, hwnd, reuse), "Theme")
            XamlUiDiagWindow(hwnd, "Theme.oldInst", false)
            if (reuse) {
                try WinActivate("ahk_id " hwnd)
                XamlUiDiag("reuse existing window + Activate", "Theme")
                XamlUiDiagWindow(hwnd, "Theme.reuse", true)
                return
            }
            ; 窗口已失效/卡死但实例残留：清理后重建
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            ThemeSettingGui.instances.Delete(key)
            XamlUiDiag("deleted stale instance", "Theme")
        }

        t0 := A_TickCount
        XAMLHost.EnsureDaemonHealthy()
        XamlUiDiag("EnsureDaemonHealthy cost=" (A_TickCount - t0) "ms", "Theme")
        XamlUiDiagDaemon("Theme.afterHealthy")
        if (ThemeSettingGui._opening) {
            XamlUiDiag("ABORT: _opening=true (reentry)", "Theme")
            return
        }
        ThemeSettingGui._opening := true
        try {
            inst := ThemeSettingGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            ThemeSettingGui.instances[key] := inst
            XamlUiDiag("ShowGui done hwnd=" (IsObject(inst.ui) && inst.ui.HasProp("wpfHwnd") ? inst.ui.wpfHwnd : 0), "Theme")
        } catch as e {
            XamlUiDiag("ShowGui EXCEPTION: " e.Message " @ " e.File ":" e.Line, "Theme")
        } finally {
            ThemeSettingGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("主题选项")
        titleHeight := "30"
        uiScale := XAMLHost.GetMainViewboxScale()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        if (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
            main.TextElement_FontFamily(MainSoftData.FontType)
        main.TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        ; 左边距 +15，左右对称，内容按两列色块宽度居中
        panel := scrollViewer.Add("StackPanel").Margin("29, 6, 29, 10")

        ; 颜色值用 Border+TextBlock 显示，避免 WPF TextBox 默认 MinHeight 导致高度调不动
        ; 主题界面字号与主题「字体大小」一致（默认 15）
        ; 色块行宽 = labelW + boxW + previewMargin + previewW，字体大小右侧与该宽度对齐
        uiFs := XAMLHost.FontSize()
        this._colorUi := {
            labelFg: "{DynamicResource TextMain}", labelFs: uiFs, labelW: 100,
            boxW: 110, boxH: 26, boxFs: uiFs,
            previewW: 26, previewH: 26, previewMargin: 6, colGap: "50,0,0,0"
        }
        this._colorUi.itemW := this._colorUi.labelW + this._colorUi.boxW + this._colorUi.previewMargin + this._colorUi.previewW
        this._colorUi.colGapW := 50
        this._colorUi.twoColW := this._colorUi.itemW * 2 + this._colorUi.colGapW
        this._colorUi.comboW := this._colorUi.itemW - this._colorUi.labelW
        this._colorUi.themeComboW := this._colorUi.twoColW - this._colorUi.labelW
        designW := 29 + 29 + 12 + 12 + 4 + this._colorUi.twoColW + 30
        designH := 760
        main.Width(designW).Height(designH)

        ; ===== 字体（在主题预设上面，其他内容顺延）=====
        fontGroup := panel.Add("GroupBox").Header(GetLang("字体")).Margin("0,0,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground("{DynamicResource TextMain}")
        fontInner := fontGroup.Add("StackPanel").Margin("12, 8")

        defFs := (IsSet(MainSoftData) && MainSoftData.HasProp("FontSize") && IsNumber(MainSoftData.FontSize))
            ? Integer(MainSoftData.FontSize)
            : (IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15)
        fontRow := fontInner.Add("Grid").Margin("0,2,0,0").Width(this._colorUi.twoColW)
        fontRow.Cols(String(this._colorUi.itemW), String(this._colorUi.itemW + this._colorUi.colGapW))

        familyCol := fontRow.Add("Grid").Grid_Column(0).HorizontalAlignment("Left").Width(this._colorUi.itemW)
        familyCol.Cols(String(this._colorUi.labelW), "*")
        familyCol.Add("TextBlock").Grid_Column(0).Text(GetLang("软件字体") "：")
            .Foreground(this._colorUi.labelFg).FontSize(this._colorUi.labelFs)
            .VerticalAlignment("Center")
        fontCombo := familyCol.Add("ComboBox").Grid_Column(1).Name("FontFamilyCon")
            .Height(this._colorUi.boxH).MinHeight(this._colorUi.boxH).HorizontalAlignment("Stretch")
            .VerticalContentAlignment("Center").FontSize(this._colorUi.labelFs)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (IsObject(MainSoftData.FontList)) {
            for font in MainSoftData.FontList
                fontCombo.Add("ComboBoxItem").Content(font)
        }

        sizeCol := fontRow.Add("Grid").Grid_Column(1).Width(this._colorUi.itemW).HorizontalAlignment("Left").Margin(this._colorUi.colGap)
        sizeCol.Cols(String(this._colorUi.labelW), "*", "32")
        sizeCol.Add("TextBlock").Grid_Column(0).Text(GetLang("字体大小") "：")
            .Foreground(this._colorUi.labelFg).FontSize(this._colorUi.labelFs)
            .VerticalAlignment("Center")
        sizeSlider := sizeCol.Add("Slider").Grid_Column(1).Name("FontSizeCon").Height(this._colorUi.boxH).MinHeight(this._colorUi.boxH).Margin("2,0,4,0")
            .Minimum("0").Maximum("40").Value(String(defFs)).IsMoveToPointEnabled("True")
            .VerticalAlignment("Center")
        sizeVal := sizeCol.Add("TextBlock").Grid_Column(2).Name("FontSizeVal").Text(String(defFs))
            .FontSize(this._colorUi.labelFs).Foreground("{DynamicResource TextMain}")
            .VerticalAlignment("Center").HorizontalAlignment("Right")

        ; ===== 顶部：主题下拉 =====
        themeGroup := panel.Add("GroupBox").Header(GetLang("主题预设")).Margin("0,10,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground("{DynamicResource TextMain}")
        themeInner := themeGroup.Add("StackPanel").Margin("12, 8")
        themeRow := themeInner.Add("Grid").Margin("0,2,0,0").Width(this._colorUi.twoColW)
        themeRow.Cols(String(this._colorUi.labelW), "*")
        themeRow.Add("TextBlock").Grid_Column(0).Text(GetLang("选择主题") "：")
            .Foreground(this._colorUi.labelFg).FontSize(this._colorUi.labelFs)
            .VerticalAlignment("Center")
        themeCombo := themeRow.Add("ComboBox").Grid_Column(1).Name("ThemeCombo")
            .Height(this._colorUi.boxH).MinHeight(this._colorUi.boxH).HorizontalAlignment("Stretch")
            .VerticalContentAlignment("Center").FontSize(this._colorUi.labelFs)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for item in AppThemeUtil.Presets
            themeCombo.Add("ComboBoxItem").Content(GetLang(item.Name))
        themeCombo.Add("ComboBoxItem").Content(GetLang("自定义"))

        ; ===== 下方：可滚动颜色组（分组与行布局由 ColorDefs 自动生成，便于后续扩展）=====
        groups := AppThemeUtil.GetGroupNames()
        for gi, groupName in groups {
            groupBox := panel.Add("GroupBox").Header(GetLang(groupName)).Margin(gi == 1 ? "0,10,0,0" : "0,8,0,0")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
                .Foreground("{DynamicResource TextMain}")
            inner := groupBox.Add("StackPanel").Margin("12, 8")
            rowKeys := this._GetGroupRowKeys(groupName)
            for ri, keys in rowKeys {
                ; 双列 Grid：第二列与字体行第二列统一左对齐
                row := inner.Add("Grid").Margin(ri == 1 ? "0,4,0,0" : "0,6,0,0").Width(this._colorUi.twoColW)
                row.Cols(String(this._colorUi.itemW), String(this._colorUi.itemW + this._colorUi.colGapW))
                this._AddColorItem(row, this._FindColorDef(keys[1]), 0)
                if (keys.Length >= 2)
                    this._AddColorItem(row, this._FindColorDef(keys[2]), 1)
            }
        }

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,10")
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定")).Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).Cursor("Hand").Width(80).Height(32)
        okBtn.InjectResources(PrimaryBtnStyle)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        winW := Round(designW * uiScale)
        winH := Round(designH * uiScale)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="' winW '" Height="' winH '" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        groupBoxStyle := '<Style TargetType="GroupBox"><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/></Style>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius><SolidColorBrush x:Key="GroupStroke" Color="#999999"/>' groupBoxStyle)

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.Track("ThemeCombo")
        this.ui.Track("FontSizeCon")
        this.ui.OnEvent("FontSizeCon", "ValueChanged", ObjBindMethod(this, "OnFontSizeChanged"))
        this.ui.OnEvent("ThemeCombo", "SelectionChanged", ObjBindMethod(this, "OnThemeSelectionChanged"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))

        for def in AppThemeUtil.ColorDefs
            this.ui.OnEvent(def.Key "_Preview", "MouseLeftButtonDown", ObjBindMethod(this, "OnPickColor", def.Key, def.Label))

        this._applyingTheme := true
        this.LoadInitValues()
        this.ApplyValuesToUI()
        if (!XamlWin.Open(this.ui)) {
            XamlUiDiag("FAIL: no wpfHwnd after wait (LoadedHwnd missing?)", "Theme")
            XamlUiDiagDaemon("Theme.noHwnd")
        }
    }

    ; 按 ColorDefs 顺序收集该组 Key，两两一行（新增颜色项无需改此处）
    _GetGroupRowKeys(groupName) {
        keys := []
        for def in AppThemeUtil.ColorDefs {
            if (def.Group == groupName)
                keys.Push(def.Key)
        }
        rows := []
        i := 1
        while (i <= keys.Length) {
            if (i + 1 <= keys.Length) {
                rows.Push([keys[i], keys[i + 1]])
                i += 2
            } else {
                rows.Push([keys[i]])
                i += 1
            }
        }
        return rows
    }

    _FindColorDef(key) {
        for def in AppThemeUtil.ColorDefs {
            if (def.Key == key)
                return def
        }
        return {Key: key, Group: "", Label: key}
    }

    _AddColorItem(row, def, col) {
        ui := this._colorUi
        item := row.Add("Grid").Grid_Column(col)
            .VerticalAlignment("Center").HorizontalAlignment("Left").Width(ui.itemW)
        if (col == 1)
            item.Margin(ui.colGap)
        item.Cols(String(ui.labelW), String(ui.boxW), "Auto")
        item.Add("TextBlock").Grid_Column(0).Text(GetLang(def.Label) "：")
            .Foreground(ui.labelFg).FontSize(ui.labelFs)
            .VerticalAlignment("Center")
        ; 只读色值展示：Border + TextBlock，高度可控
        box := item.Add("Border").Grid_Column(1).Width(ui.boxW).Height(ui.boxH).CornerRadius("3")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .VerticalAlignment("Center").HorizontalAlignment("Left")
        box.Add("TextBlock").Name(def.Key "_Text")
            .Text("#FF000000").FontSize(ui.boxFs)
            .Foreground("{DynamicResource InputText}")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        item.Add("Border").Grid_Column(2).Name(def.Key "_Preview")
            .Width(ui.previewW).Height(ui.previewH).CornerRadius("3").Margin(ui.previewMargin ",0,0,0")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .Background("#FF000000").Cursor("Hand").VerticalAlignment("Center")
    }

    LoadInitValues() {
        this._themeKey := MainSoftData.HasProp("AppTheme") ? MainSoftData.AppTheme : AppThemeUtil.DefaultThemeKey
        if (this._themeKey == "" || !AppThemeUtil.IsPresetKey(this._themeKey))
            this._themeKey := AppThemeUtil.DefaultThemeKey
        ; CloneColorMap 会以默认主题补齐缺失 Key，兼容版本升级后的自定义主题
        if (IsObject(MainSoftData.ThemeColors))
            this._colors := AppThemeUtil.CloneColorMap(MainSoftData.ThemeColors)
        else
            this._colors := AppThemeUtil.NewColorMapFromPreset(AppThemeUtil.FindPreset(this._themeKey))
    }

    ApplyValuesToUI() {
        wasApplying := this._applyingTheme
        this._applyingTheme := true
        try {
            themeIdx := AppThemeUtil.Presets.Length  ; 自定义
            for i, item in AppThemeUtil.Presets {
                if (item.Key == this._themeKey) {
                    themeIdx := i - 1
                    break
                }
            }
            this.ui.Update("ThemeCombo", "SelectedIndex", String(themeIdx))
            this.RefreshColorRows()
            defFs := IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15
            fsz := MainSoftData.HasProp("FontSize") ? Integer(MainSoftData.FontSize) : defFs
            this._previewFontSize := fsz
            this.ui.Update("FontSizeCon", "Value", String(fsz))
            this.ui.Update("FontSizeVal", "Text", String(fsz))
            fIdx := 0
            if (IsObject(MainSoftData.FontList)) {
                for i, f in MainSoftData.FontList {
                    if (f == MainSoftData.FontType) {
                        fIdx := i - 1
                        break
                    }
                }
            }
            this.ui.Update("FontFamilyCon", "SelectedIndex", String(fIdx))
        } finally {
            ; 开窗入队期间保持抑制：SelectionChanged/ValueChanged 是异步的，立刻清会在揭盖后再刷一遍主题
            if (!wasApplying)
                this._applyingTheme := false
        }
    }

    RefreshColorRows() {
        for def in AppThemeUtil.ColorDefs {
            color := AppThemeUtil.ResolveColor(this._colors, def.Key)
            this.ui.Update(def.Key "_Preview", "Background", color)
            this.ui.Update(def.Key "_Text", "Text", color)
        }
    }

    OnThemeSelectionChanged(state, ctrl, event) {
        if (this._applyingTheme)
            return
        selText := state.Has("ThemeCombo") ? state["ThemeCombo"] : ""
        if (selText == "" || selText == GetLang("自定义")) {
            this._themeKey := "Custom"
            return
        }
        preset := AppThemeUtil.FindPresetByName(selText)
        if (!IsObject(preset))
            return
        this._themeKey := preset.Key
        this._colors := AppThemeUtil.NewColorMapFromPreset(preset)
        this.RefreshColorRows()
        AppThemeUtil.ApplyWinThemeToXaml(this.ui, this._colors)
    }

    OnFontSizeChanged(state, ctrl, event) {
        v := (IsObject(state) && state.Has("FontSizeCon")) ? state["FontSizeCon"] : ""
        if (v == "")
            return
        fs := Integer(v)
        try this.ui.Update("FontSizeVal", "Text", String(fs))
        if (this._applyingTheme)
            return
        old := this.HasProp("_previewFontSize") ? this._previewFontSize : fs
        change := fs - old
        if (change == 0)
            return
        try this.ui.Update("Window", "ApplyFonts", XAMLHost.BuildApplyFontsPayload(change, fs))
        this._previewFontSize := fs
        ApplyUserFontSize(fs, false)
    }

    OnPickColor(colorKey, labelKey, state, ctrl, event) {
        cur := AppThemeUtil.ResolveColor(this._colors, colorKey)
        result := XColorPicker.Show({
            Title: GetLang(labelKey),
            DefaultColor: cur,
            Owner: this.ui.wpfHwnd,
            Modal: true
        })
        if (result.Status != "OK")
            return
        this._colors[colorKey] := result.Color
        this.ui.Update(colorKey "_Preview", "Background", result.Color)
        this.ui.Update(colorKey "_Text", "Text", result.Color)
        if (InStr(colorKey, "Win_") == 1)
            AppThemeUtil.ApplyWinThemeToXaml(this.ui, this._colors)
        this._themeKey := "Custom"
        this._applyingTheme := true
        try this.ui.Update("ThemeCombo", "SelectedIndex", String(AppThemeUtil.Presets.Length))
        finally this._applyingTheme := false
    }

    OnConfirmClick(state, ctrl, event) {
        this.SaveData()
        this.ui.Update("Window", "Close", "")
    }

    OnCancelClick(state, ctrl, event) {
        this.ui.Update("Window", "Close", "")
    }

    SaveData() {
        if (this._themeKey == "" || !AppThemeUtil.IsPresetKey(this._themeKey))
            this._themeKey := AppThemeUtil.DefaultThemeKey
        MainSoftData.AppTheme := this._themeKey
        ; 补齐缺失项后再落盘，保证后续新增 ColorDefs 写入默认主题色
        MainSoftData.ThemeColors := AppThemeUtil.CloneColorMap(this._colors)
        AppThemeUtil.ApplyToRuntime(MainSoftData.ThemeColors)
        AppThemeUtil.SaveToIni()
        global XAML_FontSizeDelta, XAML_FontSizeBase, XAML_FontWeight, XAML_TextClarity
        try {
            try {
                sel := this.ui.Query("FontFamilyCon")
                if (sel != "" && IsObject(MainSoftData.FontList) && MainSoftData.FontList.Has(sel)) {
                    MainSoftData.FontType := sel
                    IniWrite(sel, IniFile, IniSection, "FontType")
                }
            }
            oldDelta := XAML_FontSizeDelta
            defFs := IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15
            fs := this.HasProp("_previewFontSize") ? this._previewFontSize : defFs
            try {
                q := this.ui.Query("FontSizeCon")
                if (q != "" && IsNumber(q))
                    fs := Integer(q)
            }
            fs := ApplyUserFontSize(fs, true)
            change := XAML_FontSizeDelta - oldDelta
            MainSoftData.FontClarity := "1"
            XAML_TextClarity := 1
            this._previewFontSize := fs
            XAMLHost.ApplyFontsToAllWindows(change, fs, this.ui)
            try this.ui.Update("Window", "ApplyFonts", XAMLHost.BuildApplyFontsPayload(0, fs))
        }
        ; 已打开的全部界面同步「通用窗口」色与业务浮层色
        AppThemeUtil.RefreshAllOpenWindows()
    }

    OnWindowClosing(state, ctrl, event) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        XamlUiDiag("OnWindowClosing hwnd=" hwnd, "Theme")
        XamlUiDiagWindow(hwnd, "Theme.closing", false)
        this.closed := true
        ThemeSettingGui._opening := false
        if (this._instanceKey != "" && ThemeSettingGui.instances.Has(this._instanceKey))
            ThemeSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        ; 仅清理已退出的句柄；卡死检测放在下次 ShowGui / 发送消息时处理
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
        XamlUiDiagDaemon("Theme.afterClose")
    }

    OnWindowLoad(state, ctrl, event) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        XamlUiDiag("OnWindowLoad enter hwnd=" hwnd, "Theme")
        ; 主题/色值已在 Show 前入队，LoadedHwnd 揭盖前已刷完。这里再 ApplyXamlTheme 会后补描边、滚动条和阴影。
        if (this._applyingTheme)
            SetTimer(ObjBindMethod(this, "_ReleaseApplyingGuard"), -200)
        try this.ui.Update("Window", "Opacity", "1")
        XamlUiDiagWindow(hwnd, "Theme.loaded", true)
    }

    _ReleaseApplyingGuard(*) {
        this._applyingTheme := false
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }
}
