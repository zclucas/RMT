#Requires AutoHotkey v2.0

; 变量监视器双击修改值：XAML，颜色跟随通用主题
class VarModifyGui {
    static _opening := false

    __new() {
        this.ui := 0
        this.Gui := ""
        this.ParentHwnd := ""
        this.SureAction := ""
        this.closed := true
        this._origValue := ""
        this._editValue := ""
        this._name := ""
    }

    ShowGui(Name, Value) {
        this._name := String(Name)
        this._origValue := String(Value)
        this._editValue := String(Value)

        if (!this.closed && IsObject(this.ui) && XAMLHost.CanReuseWindow(this.ui.HasProp("wpfHwnd") ? this.ui.wpfHwnd : 0)) {
            this._ApplyValuesToUI()
            this._ShowExisting()
            return
        }

        XAMLHost.EnsureDaemonHealthy()
        if (VarModifyGui._opening)
            return
        VarModifyGui._opening := true
        try {
            this._BuildAndShow()
        } finally {
            VarModifyGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("修改")
        titleHeight := "30"
        winW := 400
        winH := 280

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "Auto")

        ; 标题栏
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("StackPanel").Grid_Row(1).Margin("20, 12, 20, 8")
        nameRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,12")
        nameRow.Add("TextBlock").Text(GetLang("变量名：")).Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center")
        nameRow.Add("TextBlock").Name("NameCon").Text("")
            .Foreground("{DynamicResource TextMain}").FontSize(13).FontWeight("SemiBold")
            .TextWrapping("Wrap").VerticalAlignment("Center")

        body.Add("TextBlock").Text(GetLang("值：")).Foreground("{DynamicResource TextMain}").FontSize(13).Margin("0,0,0,4")
        body.Add("TextBox").Name("ValueCon")
            .Text("")
            .AcceptsReturn("True")
            .TextWrapping("Wrap")
            .TextAlignment("Left")
            .HorizontalContentAlignment("Left")
            .VerticalContentAlignment("Top")
            .VerticalScrollBarVisibility("Auto")
            .HorizontalScrollBarVisibility("Disabled")
            .Height(100)
            .FontSize(13)
            .FontFamily(MainSoftData.FontType)
            .Background("{DynamicResource InputBg}")
            .Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1")
            .Padding("6,4")

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        btnRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,4,0,16")
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(90).Height(32)
        okBtn.InjectResources(PrimaryBtnStyle)

        pos := GetCenterPosOnActiveMonitor(winW, winH)
        dipX := PhysToDip(pos.x)
        dipY := PhysToDip(pos.y)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            Format('Title="{}" ShowInTaskbar="False" Width="{}" Height="{}" Left="{}" Top="{}" Opacity="0"',
                title, winW, winH, dipX, dipY))
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.Track("ValueCon")
        this.ui.OnEvent("ValueCon", "TextChanged", ObjBindMethod(this, "OnValueTextChanged"))

        this.Gui := this  ; 兼容：若外部读 .Gui，指向自身（含 Hwnd）
        this._ApplyValuesToUI()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    Hwnd {
        get => (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        VarModifyGui._opening := false
        this.ui := ""
        this.Gui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnCloseClick(state := unset, ctrl := unset, event := unset) {
        this._HideWindow()
    }

    _ApplyOwner() {
        if (!IsObject(this.ui) || !this.ParentHwnd)
            return
        try this.ui.Update("Window", "NativeOwner", String(this.ParentHwnd))
    }

    _ApplyValuesToUI() {
        if (!IsObject(this.ui) || this.closed)
            return
        this._editValue := this._origValue
        try this.ui.Update("NameCon", "Text", this._name)
        try this.ui.Update("ValueCon", "Text", this._origValue)
    }

    OnValueTextChanged(state := unset, ctrl := unset, event := unset) {
        if (IsSet(state) && IsObject(state) && state.Has("ValueCon"))
            this._editValue := String(state["ValueCon"])
    }

    _ShowExisting() {
        hwnd := this.Hwnd
        if (!hwnd)
            return
        this._ApplyOwner()
        try WinShow("ahk_id " hwnd)
        try WinActivate("ahk_id " hwnd)
    }

    _HideWindow() {
        hwnd := this.Hwnd
        if (hwnd)
            try WinHide("ahk_id " hwnd)
    }

    OnSureBtnClick(state := unset, ctrl := unset, event := unset) {
        if (!IsObject(this.ui) || this.closed)
            return

        newValue := this._editValue
        if (IsSet(state) && IsObject(state) && state.Has("ValueCon"))
            newValue := String(state["ValueCon"])

        if (newValue == this._origValue) {
            this._HideWindow()
            return
        }

        if (this.SureAction != "") {
            action := this.SureAction
            action(this._name, newValue)
        }
        this._origValue := newValue
        this._editValue := newValue
        this._HideWindow()
    }
}
