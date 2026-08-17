#Requires AutoHotkey v2.0

class UIMacroPanelSettingGui {
    static instances := Map()
    static _opening := false

    ; 位置选项映射（id 与 UIPanelDefaultPos 数值对应；数组顺序即下拉显示顺序）
    static PosOptions := [
        {id: 8, label: "鼠标位置"},
        {id: 1, label: "左上"},
        {id: 2, label: "中上"},
        {id: 3, label: "右上"},
        {id: 4, label: "中左"},
        {id: 5, label: "中心"},
        {id: 6, label: "中右"},
        {id: 7, label: "左下"},
        {id: 9, label: "中下"},
        {id: 10, label: "右下"}
    ]

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._showOnActive := true
        this._defaultPos := 1
        this._offsetX := 100
        this._offsetY := 100
        this._btnHeight := 34
        this._fontSize := 12
        this._btnWidth := 80
        this._cols := 3
        this._applyingUI := false
    }

    static ShowGui() {
        key := "global"

        ; 检查已有实例，有则激活并返回
        if (UIMacroPanelSettingGui.instances.Has(key)) {
            oldInst := UIMacroPanelSettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                try WinActivate("ahk_id " hwnd)
                return
            }
            ; 实例已失效/卡死，清理后重建
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            UIMacroPanelSettingGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        ; 防重入
        if (UIMacroPanelSettingGui._opening)
            return
        UIMacroPanelSettingGui._opening := true

        try {
            inst := UIMacroPanelSettingGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            UIMacroPanelSettingGui.instances[key] := inst
        } finally {
            UIMacroPanelSettingGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false

        title := GetLang("界面浮窗")
        titleHeight := "36"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Rows(titleHeight, "*")

        ; 标题栏
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")

        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")

        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; 内容区（内容固定高度，无需滚动条；滚动条会挤压右侧数值框导致右边框被裁切）
        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        panel := body.Add("StackPanel").Margin("24, 6, 24, 8")
        labelStyle := { fg: "{DynamicResource TextMain}", fs: 13, w: 90 }
        sliderW := 136
        valBoxW := 50

        ; 选择框：界面激活时默认显示
        row1 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        row1.Add("CheckBox").Name("ShowOnActiveCon")
            .Content(GetLang("界面激活时显示"))
            .Foreground("{DynamicResource TextMain}").FontSize(13).Margin("0,0,0,0")

        ; 下拉框：浮窗出现位置
        row2 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row2.Add("TextBlock").Text(GetLang("出现位置") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        posCombo := row2.Add("ComboBox").Name("DefaultPosCon")
            .Width(140).Height(26).MinHeight(26).Margin("8,0,0,0")
        for opt in UIMacroPanelSettingGui.PosOptions
            posCombo.Add("ComboBoxItem").Content(GetLang(opt.label))

        ; 位置偏移 X / Y
        rowOffX := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        rowOffX.Add("TextBlock").Text(GetLang("位置偏移X") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        rowOffX.Add("Slider").Name("OffsetXCon")
            .Width(sliderW).Height(28).Margin("8,0,8,0")
            .Minimum(0).Maximum(500).Value(100)
            .IsSnapToTickEnabled("True").TickFrequency("5")
        rowOffX.Add("TextBox").Name("OffsetXValText")
            .Width(valBoxW).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SetMarkup("Text", "{Binding Value, ElementName=OffsetXCon}")

        rowOffY := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        rowOffY.Add("TextBlock").Text(GetLang("位置偏移Y") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        rowOffY.Add("Slider").Name("OffsetYCon")
            .Width(sliderW).Height(28).Margin("8,0,8,0")
            .Minimum(0).Maximum(500).Value(100)
            .IsSnapToTickEnabled("True").TickFrequency("5")
        rowOffY.Add("TextBox").Name("OffsetYValText")
            .Width(valBoxW).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SetMarkup("Text", "{Binding Value, ElementName=OffsetYCon}")

        ; 按钮宽度
        row6b := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row6b.Add("TextBlock").Text(GetLang("按钮宽度") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        widthSlider := row6b.Add("Slider").Name("BtnWidthCon")
            .Width(sliderW).Height(28).Margin("8,0,8,0")
            .Minimum(40).Maximum(250).Value(80)
            .IsSnapToTickEnabled("True").TickFrequency("5")
        widthValBox := row6b.Add("TextBox").Name("BtnWidthValText")
            .Width(valBoxW).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SetMarkup("Text", "{Binding Value, ElementName=BtnWidthCon}")

        ; 按钮高度
        row6 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row6.Add("TextBlock").Text(GetLang("按钮高度") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        heightSlider := row6.Add("Slider").Name("BtnHeightCon")
            .Width(sliderW).Height(28).Margin("8,0,8,0")
            .Minimum(20).Maximum(60).Value(34)
            .IsSnapToTickEnabled("True").TickFrequency("2")
        heightValBox := row6.Add("TextBox").Name("BtnHeightValText")
            .Width(valBoxW).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SetMarkup("Text", "{Binding Value, ElementName=BtnHeightCon}")

        ; 按钮字体大小
        rowFont := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        rowFont.Add("TextBlock").Text(GetLang("字体大小") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        rowFont.Add("Slider").Name("FontSizeCon")
            .Width(sliderW).Height(28).Margin("8,0,8,0")
            .Minimum(8).Maximum(24).Value(12)
            .IsSnapToTickEnabled("True").TickFrequency("1")
        rowFont.Add("TextBox").Name("FontSizeValText")
            .Width(valBoxW).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SetMarkup("Text", "{Binding Value, ElementName=FontSizeCon}")

        ; 按钮每行最大个数
        row7 := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row7.Add("TextBlock").Text(GetLang("每行个数") "：")
            .Foreground(labelStyle.fg).FontSize(labelStyle.fs)
            .VerticalAlignment("Center").Width(labelStyle.w)
        colsSlider := row7.Add("Slider").Name("ColsCon")
            .Width(sliderW).Height(28).Margin("8,0,8,0")
            .Minimum(1).Maximum(6).Value(3)
            .IsSnapToTickEnabled("True").TickFrequency("1")
        colsValBox := row7.Add("TextBox").Name("ColsValText")
            .Width(valBoxW).Height(24).MinHeight(24).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SetMarkup("Text", "{Binding Value, ElementName=ColsCon}")

        ; 底部按钮行
        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,14,0,4")
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

        ; 编译 XAML
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="370" Height="400" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')

        resourceInject := '<CornerRadius x:Key="PanelRadius">8</CornerRadius>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', resourceInject)

        ; 事件绑定
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.ui.Track("ShowOnActiveCon")
        this.ui.Track("DefaultPosCon")
        this.ui.Track("OffsetXCon")
        this.ui.Track("OffsetYCon")
        this.ui.Track("BtnHeightCon")
        this.ui.Track("FontSizeCon")
        this.ui.Track("BtnWidthCon")
        this.ui.Track("ColsCon")
        this.ui.Track("OffsetXValText")
        this.ui.Track("OffsetYValText")
        this.ui.Track("BtnHeightValText")
        this.ui.Track("FontSizeValText")
        this.ui.Track("BtnWidthValText")
        this.ui.Track("ColsValText")

        this.ui.OnEvent("ShowOnActiveCon", "Checked", ObjBindMethod(this, "OnShowOnActiveChanged"))
        this.ui.OnEvent("ShowOnActiveCon", "Unchecked", ObjBindMethod(this, "OnShowOnActiveChanged"))
        this.ui.OnEvent("DefaultPosCon", "SelectionChanged", ObjBindMethod(this, "OnDefaultPosChanged"))
        this.ui.OnEvent("OffsetXCon", "ValueChanged", ObjBindMethod(this, "OnOffsetXChanged")).Limit(20, false)
        this.ui.OnEvent("OffsetYCon", "ValueChanged", ObjBindMethod(this, "OnOffsetYChanged")).Limit(20, false)
        this.ui.OnEvent("BtnHeightCon", "ValueChanged", ObjBindMethod(this, "OnBtnHeightChanged")).Limit(20, false)
        this.ui.OnEvent("FontSizeCon", "ValueChanged", ObjBindMethod(this, "OnFontSizeChanged")).Limit(20, false)
        this.ui.OnEvent("BtnWidthCon", "ValueChanged", ObjBindMethod(this, "OnBtnWidthChanged")).Limit(20, false)
        this.ui.OnEvent("ColsCon", "ValueChanged", ObjBindMethod(this, "OnColsChanged")).Limit(20, false)
        ; 文本框输入 → 同步到滑动条
        this.ui.OnEvent("OffsetXValText", "TextChanged", ObjBindMethod(this, "OnOffsetXTextChanged"))
        this.ui.OnEvent("OffsetYValText", "TextChanged", ObjBindMethod(this, "OnOffsetYTextChanged"))
        this.ui.OnEvent("BtnHeightValText", "TextChanged", ObjBindMethod(this, "OnBtnHeightTextChanged"))
        this.ui.OnEvent("FontSizeValText", "TextChanged", ObjBindMethod(this, "OnFontSizeTextChanged"))
        this.ui.OnEvent("BtnWidthValText", "TextChanged", ObjBindMethod(this, "OnBtnWidthTextChanged"))
        this.ui.OnEvent("ColsValText", "TextChanged", ObjBindMethod(this, "OnColsTextChanged"))

        this.ui.OnEvent("BtnRevert", "Click", ObjBindMethod(this, "OnRevertClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.LoadInitValues()
        this.ApplyValuesToUI()
        this.ui.Show()

        ; 等待窗口就绪后激活到最前，避免被主界面挡住
        loop 20 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                break
            }
            Sleep(50)
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        UIMacroPanelSettingGui._opening := false
        if (this._instanceKey != "" && UIMacroPanelSettingGui.instances.Has(this._instanceKey))
            UIMacroPanelSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
            this.ApplyValuesToUI()
        } finally {
            this.ui.Update("Window", "Opacity", "1")
        }
    }

    LoadInitValues() {
        this._showOnActive := !!MainSoftData.UIPanelShowOnActive
        this._defaultPos := MainSoftData.UIPanelDefaultPos
        this._offsetX := Max(0, Min(500, Integer(MainSoftData.UIPanelOffsetX)))
        this._offsetY := Max(0, Min(500, Integer(MainSoftData.UIPanelOffsetY)))
        this._btnHeight := MainSoftData.UIPanelBtnHeight
        this._fontSize := Max(8, Min(24, Integer(MainSoftData.UIPanelFontSize)))
        w := MainSoftData.UIPanelBtnWidth
        this._btnWidth := (w < 40) ? 80 : w
        this._cols := MainSoftData.UIPanelCols
    }

    ApplyValuesToUI() {
        this._applyingUI := true
        try {
            this.ui.Update("ShowOnActiveCon", "IsChecked", this._showOnActive ? "True" : "False")

            posIdx := 0
            for i, opt in UIMacroPanelSettingGui.PosOptions {
                if (opt.id == this._defaultPos) {
                    posIdx := i - 1
                    break
                }
            }
            this.ui.Update("DefaultPosCon", "SelectedIndex", String(posIdx))
            this.ui.Update("OffsetXCon", "Value", String(this._offsetX))
            this.ui.Update("OffsetYCon", "Value", String(this._offsetY))
            this.ui.Update("BtnHeightCon", "Value", String(this._btnHeight))
            this.ui.Update("FontSizeCon", "Value", String(this._fontSize))
            this.ui.Update("BtnWidthCon", "Value", String(this._btnWidth))
            this.ui.Update("ColsCon", "Value", String(this._cols))
        } finally {
            this._applyingUI := false
        }
    }

    OnShowOnActiveChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        this._showOnActive := (event == "Checked")
    }

    OnDefaultPosChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("DefaultPosCon") ? state["DefaultPosCon"] : ""
        for opt in UIMacroPanelSettingGui.PosOptions {
            if (opt.label == text || GetLang(opt.label) == text) {
                this._defaultPos := opt.id
                return
            }
        }
    }

    OnOffsetXChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("OffsetXCon") ? state["OffsetXCon"] : ""
        this._offsetX := Integer(valStr)
    }

    OnOffsetYChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("OffsetYCon") ? state["OffsetYCon"] : ""
        this._offsetY := Integer(valStr)
    }

    OnOffsetXTextChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("OffsetXValText") ? state["OffsetXValText"] : ""
        if (text == "" || !IsNumber(text))
            return
        val := Max(0, Min(500, Integer(Number(text))))
        if (val != this._offsetX) {
            this._offsetX := val
            this.ui.Update("OffsetXCon", "Value", String(val))
        }
    }

    OnOffsetYTextChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("OffsetYValText") ? state["OffsetYValText"] : ""
        if (text == "" || !IsNumber(text))
            return
        val := Max(0, Min(500, Integer(Number(text))))
        if (val != this._offsetY) {
            this._offsetY := val
            this.ui.Update("OffsetYCon", "Value", String(val))
        }
    }

    OnBtnHeightChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("BtnHeightCon") ? state["BtnHeightCon"] : ""
        this._btnHeight := Integer(valStr)
    }

    OnFontSizeChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("FontSizeCon") ? state["FontSizeCon"] : ""
        this._fontSize := Integer(valStr)
    }

    OnBtnWidthChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("BtnWidthCon") ? state["BtnWidthCon"] : ""
        this._btnWidth := Integer(valStr)
    }

    OnColsChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        valStr := state.Has("ColsCon") ? state["ColsCon"] : ""
        this._cols := Integer(valStr)
    }

    ; 文本框输入 → 校验并同步到滑动条
    OnBtnHeightTextChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("BtnHeightValText") ? state["BtnHeightValText"] : ""
        if (text == "" || !IsNumber(text))
            return
        val := Integer(Number(text))
        val := Max(20, Min(60, val))  ; 限制在 20~60 范围
        if (val != this._btnHeight) {
            this._btnHeight := val
            this.ui.Update("BtnHeightCon", "Value", String(val))
        }
    }

    OnFontSizeTextChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("FontSizeValText") ? state["FontSizeValText"] : ""
        if (text == "" || !IsNumber(text))
            return
        val := Max(8, Min(24, Integer(Number(text))))
        if (val != this._fontSize) {
            this._fontSize := val
            this.ui.Update("FontSizeCon", "Value", String(val))
        }
    }

    OnBtnWidthTextChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("BtnWidthValText") ? state["BtnWidthValText"] : ""
        if (text == "" || !IsNumber(text))
            return
        val := Integer(Number(text))
        val := Max(40, Min(250, val))  ; 限制在 40~250 范围
        if (val != this._btnWidth) {
            this._btnWidth := val
            this.ui.Update("BtnWidthCon", "Value", String(val))
        }
    }

    OnColsTextChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        text := state.Has("ColsValText") ? state["ColsValText"] : ""
        if (text == "" || !IsNumber(text))
            return
        val := Integer(Number(text))
        val := Max(1, Min(6, val))  ; 限制在 1~6 范围
        if (val != this._cols) {
            this._cols := val
            this.ui.Update("ColsCon", "Value", String(val))
        }
    }

    OnRevertClick(state, ctrl, event) {
        this._showOnActive := true
        this._defaultPos := 1
        this._offsetX := 100
        this._offsetY := 100
        this._btnHeight := 34
        this._fontSize := 12
        this._btnWidth := 80
        this._cols := 3
        this.ApplyValuesToUI()
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
        global IniFile, IniSection

        MainSoftData.UIPanelShowOnActive := this._showOnActive
        MainSoftData.UIPanelDefaultPos := this._defaultPos
        MainSoftData.UIPanelOffsetX := this._offsetX
        MainSoftData.UIPanelOffsetY := this._offsetY
        MainSoftData.UIPanelBtnHeight := this._btnHeight
        MainSoftData.UIPanelFontSize := this._fontSize
        MainSoftData.UIPanelBtnWidth := this._btnWidth
        MainSoftData.UIPanelCols := this._cols

        IniWrite(MainSoftData.UIPanelShowOnActive, IniFile, IniSection, "UIPanelShowOnActive")
        IniWrite(MainSoftData.UIPanelDefaultPos, IniFile, IniSection, "UIPanelDefaultPos")
        IniWrite(MainSoftData.UIPanelOffsetX, IniFile, IniSection, "UIPanelOffsetX")
        IniWrite(MainSoftData.UIPanelOffsetY, IniFile, IniSection, "UIPanelOffsetY")
        IniWrite(MainSoftData.UIPanelBtnHeight, IniFile, IniSection, "UIPanelBtnHeight")
        IniWrite(MainSoftData.UIPanelFontSize, IniFile, IniSection, "UIPanelFontSize")
        IniWrite(MainSoftData.UIPanelBtnWidth, IniFile, IniSection, "UIPanelBtnWidth")
        IniWrite(MainSoftData.UIPanelCols, IniFile, IniSection, "UIPanelCols")
    }
}
