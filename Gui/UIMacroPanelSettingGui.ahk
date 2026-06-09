#Requires AutoHotkey v2.0

class UIMacroPanelSettingGui {
    static instances := Map()
    static _opening := false

    ; 位置选项映射（与 UIPanelDefaultPos 数值对应）
    static PosOptions := [
        {id: 1, label: "左上"},
        {id: 2, label: "中上"},
        {id: 3, label: "右上"},
        {id: 4, label: "中左"},
        {id: 5, label: "中心"},
        {id: 6, label: "中右"},
        {id: 7, label: "左下"},
        {id: 8, label: "鼠标位置"}
    ]

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._showOnActive := true
        this._defaultPos := 8
        this._btnColor := "#FF333333"
        this._bgColor := "#40FFB6C1"
        this._fontColor := "#FFDDDDDD"
        this._btnHeight := 34
        this._btnWidth := 80
        this._cols := 3
    }

    static ShowGui() {
        key := "global"

        ; 检查已有实例，有则激活并返回
        if (UIMacroPanelSettingGui.instances.Has(key)) {
            oldInst := UIMacroPanelSettingGui.instances[key]
            if (!oldInst.closed && IsObject(oldInst.ui) && oldInst.ui.wpfHwnd) {
                try WinActivate("ahk_id " oldInst.ui.wpfHwnd)
                return
            }
            ; 实例已失效，清理
            if (!oldInst.closed)
                oldInst.Close()
            UIMacroPanelSettingGui.instances.Delete(key)
        }

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
        tb := main.Add("Border").Grid_Row(0).Background("Transparent").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")

        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")

        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness(0)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; 内容区
        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource ControlBg}")

        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        panel := scrollViewer.Add("StackPanel").Margin("30, 16, 30, 20")

        ; ====== 通用选项 ======
        group1 := panel.Add("GroupBox").Header(GetLang("通用选项")).Margin("0,6,0,0")
        inner1 := group1.Add("StackPanel").Margin("14, 12")

        ; 选择框：界面激活时默认显示
        row1 := inner1.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        row1.Add("CheckBox").Name("ShowOnActiveCon")
            .Content(GetLang("界面激活时显示"))
            .Foreground("{DynamicResource TextMain}").Margin("0,0,0,0")

        ; 下拉框：浮窗默认出现位置
        row2 := inner1.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row2.Add("TextBlock").Text(GetLang("默认出现位置"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(90)
        posCombo := row2.Add("ComboBox").Name("DefaultPosCon")
            .Width(140).Height(28).Margin("8,0,0,0")
        for opt in UIMacroPanelSettingGui.PosOptions
            posCombo.Add("ComboBoxItem").Content(opt.label)

        ; ====== 外观设置 ======
        group2 := panel.Add("GroupBox").Header(GetLang("外观")).Margin("0,16,0,0")
        inner2 := group2.Add("StackPanel").Margin("14, 12")

        ; 按钮颜色：标签 + #ARGB文本 + 预览块(点击打开选择器)
        row3 := inner2.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        row3.Add("TextBlock").Text(GetLang("按钮颜色"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(70)
        row3.Add("TextBox").Name("BtnColorText")
            .Width(110).Height(26).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(10)
            .Foreground("{DynamicResource TextSub}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .IsReadOnly("True").Text("#FF333333")
        btnColorPrev := row3.Add("Border").Name("BtnColorPreview")
            .Width(28).Height(26).CornerRadius("3").Margin("8,0,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Background("#FF333333").Cursor("Hand")

        ; 背景颜色：标签 + #ARGB文本 + 预览块(点击打开选择器)
        row4 := inner2.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row4.Add("TextBlock").Text(GetLang("背景颜色"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(70)
        row4.Add("TextBox").Name("BgColorText")
            .Width(110).Height(26).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(10)
            .Foreground("{DynamicResource TextSub}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .IsReadOnly("True").Text("#40FFB6C1")
        bgColorPrev := row4.Add("Border").Name("BgColorPreview")
            .Width(28).Height(26).CornerRadius("3").Margin("8,0,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Background("#40FFB6C1").Cursor("Hand")

        ; 字体颜色：标签 + #ARGB文本 + 预览块(点击打开选择器)
        row5 := inner2.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        row5.Add("TextBlock").Text(GetLang("字体颜色"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(70)
        row5.Add("TextBox").Name("FontColorText")
            .Width(110).Height(26).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(10)
            .Foreground("{DynamicResource TextSub}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .IsReadOnly("True").Text("#FFDDDDDD")
        fontColorPrev := row5.Add("Border").Name("FontColorPreview")
            .Width(28).Height(26).CornerRadius("3").Margin("8,0,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Background("#FFDDDDDD").Cursor("Hand")

        ; ====== 尺寸设置 ======
        group3 := panel.Add("GroupBox").Header(GetLang("尺寸")).Margin("0,16,0,0")
        inner3 := group3.Add("StackPanel").Margin("14, 12")

        ; 按钮高度
        row6 := inner3.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        row6.Add("TextBlock").Text(GetLang("按钮高度"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(70)
        heightSlider := row6.Add("Slider").Name("BtnHeightCon")
            .Width(140).Height(28).Margin("8,0,8,0")
            .Minimum(20).Maximum(60).Value(34)
            .IsSnapToTickEnabled("True").TickFrequency("2")
            .Tag("Throttle:50")
        heightValBox := row6.Add("TextBox").Name("BtnHeightValText")
            .Width(50).Height(26).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Margin("2,0,0,0")
            .Text("{Binding Value, ElementName=BtnHeightCon}")

        ; 按钮宽度
        row6b := inner3.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row6b.Add("TextBlock").Text(GetLang("按钮宽度"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(70)
        widthSlider := row6b.Add("Slider").Name("BtnWidthCon")
            .Width(140).Height(28).Margin("8,0,8,0")
            .Minimum(40).Maximum(250).Value(80)
            .IsSnapToTickEnabled("True").TickFrequency("5")
            .Tag("Throttle:50")
        widthValBox := row6b.Add("TextBox").Name("BtnWidthValText")
            .Width(50).Height(26).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Margin("2,0,0,0")
            .Text("{Binding Value, ElementName=BtnWidthCon}")

        ; 按钮每行最大个数
        row7 := inner3.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        row7.Add("TextBlock").Text(GetLang("每行个数"))
            .Foreground("{DynamicResource TextSub}").FontSize(11)
            .VerticalAlignment("Center").Width(70)
        colsSlider := row7.Add("Slider").Name("ColsCon")
            .Width(140).Height(28).Margin("8,0,8,0")
            .Minimum(1).Maximum(6).Value(3)
            .IsSnapToTickEnabled("True").TickFrequency("1")
            .Tag("Throttle:50")
        colsValBox := row7.Add("TextBox").Name("ColsValText")
            .Width(50).Height(26).VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Margin("2,0,0,0")
            .Text("{Binding Value, ElementName=ColsCon}")

        ; 底部按钮行
        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,10")
        revertBtn := btnRow.Add("Button").Name("BtnRevert").Content(GetLang("恢复默认")).Background("{DynamicResource Accent}").Foreground("White").FontWeight("Bold").BorderThickness(0).FontSize(13).Cursor("Hand").Width(80).Height(32).Margin("0,0,16,0")
        revertBtn.InjectResources(PrimaryBtnStyle)
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定")).Background("{DynamicResource Accent}").Foreground("White").FontWeight("Bold").BorderThickness(0).FontSize(13).Cursor("Hand").Width(80).Height(32)
        okBtn.InjectResources(PrimaryBtnStyle)

        ; 编译 XAML
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="420" Height="630"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MySoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')

        resourceInject := '<CornerRadius x:Key="PanelRadius">8</CornerRadius>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', resourceInject)

        ; 事件绑定
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnConfirmClick"))

        this.ui.Track("ShowOnActiveCon")
        this.ui.Track("DefaultPosCon")
        this.ui.Track("BtnHeightCon")
        this.ui.Track("BtnWidthCon")
        this.ui.Track("ColsCon")
        this.ui.Track("BtnHeightValText")
        this.ui.Track("BtnWidthValText")
        this.ui.Track("ColsValText")

        this.ui.OnEvent("ShowOnActiveCon", "Checked", ObjBindMethod(this, "OnShowOnActiveChanged"))
        this.ui.OnEvent("ShowOnActiveCon", "Unchecked", ObjBindMethod(this, "OnShowOnActiveChanged"))
        this.ui.OnEvent("DefaultPosCon", "SelectionChanged", ObjBindMethod(this, "OnDefaultPosChanged"))
        this.ui.OnEvent("BtnHeightCon", "ValueChanged", ObjBindMethod(this, "OnBtnHeightChanged"))
        this.ui.OnEvent("BtnWidthCon", "ValueChanged", ObjBindMethod(this, "OnBtnWidthChanged"))
        this.ui.OnEvent("ColsCon", "ValueChanged", ObjBindMethod(this, "OnColsChanged"))
        ; 文本框输入 → 同步到滑动条
        this.ui.OnEvent("BtnHeightValText", "TextChanged", ObjBindMethod(this, "OnBtnHeightTextChanged"))
        this.ui.OnEvent("BtnWidthValText", "TextChanged", ObjBindMethod(this, "OnBtnWidthTextChanged"))
        this.ui.OnEvent("ColsValText", "TextChanged", ObjBindMethod(this, "OnColsTextChanged"))

        ; 预览块点击 → 打开 XColorPicker
        this.ui.OnEvent("BtnColorPreview", "MouseLeftButtonDown", ObjBindMethod(this, "OnPickBtnColor"))
        this.ui.OnEvent("BgColorPreview", "MouseLeftButtonDown", ObjBindMethod(this, "OnPickBgColor"))
        this.ui.OnEvent("FontColorPreview", "MouseLeftButtonDown", ObjBindMethod(this, "OnPickFontColor"))

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

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        UIMacroPanelSettingGui._opening := false
        if (this._instanceKey != "" && UIMacroPanelSettingGui.instances.Has(this._instanceKey))
            UIMacroPanelSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
    }

    OnWindowLoad(state, ctrl, event) {
        themeName := (IsSet(MySoftData) && MySoftData.HasProp("Theme")) ? MySoftData.Theme : "RMT_Light"
        ApplyXamlTheme(this.ui, themeName)
    }

    LoadInitValues() {
        this._showOnActive := !!MySoftData.UIPanelShowOnActive
        this._defaultPos := MySoftData.UIPanelDefaultPos
        this._btnColor := MySoftData.UIPanelBtnColor
        this._bgColor := MySoftData.UIPanelBgColor
        this._fontColor := MySoftData.UIPanelFontColor
        this._btnHeight := MySoftData.UIPanelBtnHeight
        w := MySoftData.UIPanelBtnWidth
        this._btnWidth := (w < 40) ? 80 : w
        this._cols := MySoftData.UIPanelCols
    }

    ApplyValuesToUI() {
        this.ui.Update("ShowOnActiveCon", "IsChecked", this._showOnActive ? "True" : "False")

        posIdx := Max(0, this._defaultPos - 1)
        this.ui.Update("DefaultPosCon", "SelectedIndex", String(posIdx))

        this.ui.Update("BtnColorPreview", "Background", this._btnColor)
        this.ui.Update("BtnColorText", "Text", this._btnColor)
        this.ui.Update("BgColorPreview", "Background", this._bgColor)
        this.ui.Update("BgColorText", "Text", this._bgColor)
        this.ui.Update("FontColorPreview", "Background", this._fontColor)
        this.ui.Update("FontColorText", "Text", this._fontColor)

        this.ui.Update("BtnHeightCon", "Value", String(this._btnHeight))

        this.ui.Update("BtnWidthCon", "Value", String(this._btnWidth))

        this.ui.Update("ColsCon", "Value", String(this._cols))
    }

    OnShowOnActiveChanged(state, ctrl, event) {
        this._showOnActive := (event == "Checked")
    }

    OnDefaultPosChanged(state, ctrl, event) {
        text := state.Has("DefaultPosCon") ? state["DefaultPosCon"] : ""
        for opt in UIMacroPanelSettingGui.PosOptions {
            if (opt.label == text) {
                this._defaultPos := opt.id
                return
            }
        }
    }

    OnBtnHeightChanged(state, ctrl, event) {
        valStr := state.Has("BtnHeightCon") ? state["BtnHeightCon"] : ""
        this._btnHeight := Integer(valStr)
    }

    OnBtnWidthChanged(state, ctrl, event) {
        valStr := state.Has("BtnWidthCon") ? state["BtnWidthCon"] : ""
        this._btnWidth := Integer(valStr)
    }

    OnColsChanged(state, ctrl, event) {
        valStr := state.Has("ColsCon") ? state["ColsCon"] : ""
        this._cols := Integer(valStr)
    }

    ; 文本框输入 → 校验并同步到滑动条
    OnBtnHeightTextChanged(state, ctrl, event) {
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

    OnBtnWidthTextChanged(state, ctrl, event) {
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

    OnPickBtnColor(state, ctrl, event) {
        result := XColorPicker.Show({ Title: GetLang("按钮颜色"), DefaultColor: this._btnColor, Owner: this.ui.wpfHwnd, Modal: true })
        if (result.Status == "OK") {
            this._btnColor := result.Color
            this.ui.Update("BtnColorPreview", "Background", result.Color)
            this.ui.Update("BtnColorText", "Text", result.Color)
        }
    }

    OnPickBgColor(state, ctrl, event) {
        result := XColorPicker.Show({ Title: GetLang("背景颜色"), DefaultColor: this._bgColor, Owner: this.ui.wpfHwnd, Modal: true })
        if (result.Status == "OK") {
            this._bgColor := result.Color
            this.ui.Update("BgColorPreview", "Background", result.Color)
            this.ui.Update("BgColorText", "Text", result.Color)
        }
    }

    OnPickFontColor(state, ctrl, event) {
        result := XColorPicker.Show({ Title: GetLang("字体颜色"), DefaultColor: this._fontColor, Owner: this.ui.wpfHwnd, Modal: true })
        if (result.Status == "OK") {
            this._fontColor := result.Color
            this.ui.Update("FontColorPreview", "Background", result.Color)
            this.ui.Update("FontColorText", "Text", result.Color)
        }
    }

    OnRevertClick(state, ctrl, event) {
        this.ui.Update("ShowOnActiveCon", "IsChecked", "True")
        this.ui.Update("DefaultPosCon", "SelectedIndex", "7")  ; 鼠标位置
        this.ui.Update("BtnColorPreview", "Background", "#FF333333")
        this.ui.Update("BtnColorText", "Text", "#FF333333")
        this.ui.Update("BgColorPreview", "Background", "#40FFB6C1")
        this.ui.Update("BgColorText", "Text", "#40FFB6C1")
        this.ui.Update("FontColorPreview", "Background", "#FFDDDDDD")
        this.ui.Update("FontColorText", "Text", "#FFDDDDDD")
        this.ui.Update("BtnHeightCon", "Value", "34")
        this.ui.Update("BtnWidthCon", "Value", "80")
        this.ui.Update("ColsCon", "Value", "3")

        this._showOnActive := true
        this._defaultPos := 8
        this._btnColor := "#FF333333"
        this._bgColor := "#40FFB6C1"
        this._fontColor := "#FFDDDDDD"
        this._btnHeight := 34
        this._btnWidth := 80
        this._cols := 3
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

        MySoftData.UIPanelShowOnActive := this._showOnActive
        MySoftData.UIPanelDefaultPos := this._defaultPos
        MySoftData.UIPanelBtnColor := this._btnColor
        MySoftData.UIPanelBgColor := this._bgColor
        MySoftData.UIPanelFontColor := this._fontColor
        MySoftData.UIPanelBtnHeight := this._btnHeight
        MySoftData.UIPanelBtnWidth := this._btnWidth
        MySoftData.UIPanelCols := this._cols

        iniPath := A_WorkingDir "\Setting\MainSettings.ini"
        IniWrite(MySoftData.UIPanelShowOnActive, IniFile, IniSection, "UIPanelShowOnActive")
        IniWrite(MySoftData.UIPanelDefaultPos, IniFile, IniSection, "UIPanelDefaultPos")
        IniWrite(MySoftData.UIPanelBtnColor, IniFile, IniSection, "UIPanelBtnColor")
        IniWrite(MySoftData.UIPanelBgColor, IniFile, IniSection, "UIPanelBgColor")
        IniWrite(MySoftData.UIPanelFontColor, IniFile, IniSection, "UIPanelFontColor")
        IniWrite(MySoftData.UIPanelBtnHeight, IniFile, IniSection, "UIPanelBtnHeight")
        IniWrite(MySoftData.UIPanelBtnWidth, IniFile, IniSection, "UIPanelBtnWidth")
        IniWrite(MySoftData.UIPanelCols, IniFile, IniSection, "UIPanelCols")
    }
}
