#Requires AutoHotkey v2.0

; =====================================================================
; 输入弹窗 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(Label, Content) / SureAction / HideAction / CloseAction
; =====================================================================

class CustomInputGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.HideAction := ""
        this.SureAction := ""
        this.CloseAction := ""
        this._rec := false
        this._recStarting := false
        this._recBase := ""
        this._recLive := ""
        this._sttTick := ObjBindMethod(this, "_PollStt")
    }

    ShowGui(Label, Content) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (IsObject(this.ui)) {
            this.ui.Update("LabelCon", "Text", Label)
            this.ui.Update("ContentCon", "Text", Content)
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        this._submitting := false
        this._rec := false
        title := GetLang("输入-弹窗")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,6,10,12")
        body.Rows("Auto", "*", "48")
        prompt := body.Add("StackPanel").Grid_Row(0)
        prompt.Add("TextBlock").Name("LabelCon").Text("").Margin("0,0,0,5")
        prompt.Add("TextBlock").Name("MicStatus").Visibility("Collapsed").TextWrapping("Wrap")
            .Foreground("{DynamicResource TextSub}").Margin("0,0,0,5")

        ; 主题在滚动容器内外各应用一次 Padding，边框另占 1。
        body.Add("TextBox").Grid_Row(1).Name("ContentCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2.5,3").Margin("0,0,0,8")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        mic := body.Add("Button").Grid_Row(2).Name("BtnMic").Width(30).Height(30)
            .HorizontalAlignment("Right").VerticalAlignment("Bottom").Padding("0")
            .Content(Chr(0xE720)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14)
            .ToolTip(GetLang("语音输入"))
        mic.InjectResources(this._MicButtonStyle())

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="365" Height="252"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("Window", "PreviewKeyDown:Return", XamlWin.BindCurrent(this, "OnEnter"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("BtnMic", "Click", ObjBindMethod(this, "OnMicClick"))
    }

    _MicButtonStyle() {
        return '
        (
        <Style TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource EditText}"/>
            <Setter Property="FocusVisualStyle" Value="{DynamicResource GlobalFocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Surface" Background="{DynamicResource EditBg}"
                                BorderBrush="{DynamicResource EditStroke}" BorderThickness="1" CornerRadius="6">
                            <Grid>
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                <Ellipse x:Name="RecordingDot" Width="7" Height="7" Fill="#E53935"
                                         Stroke="White" StrokeThickness="1" Margin="0,2,2,0"
                                         HorizontalAlignment="Right" VerticalAlignment="Top"
                                         IsHitTestVisible="False" Visibility="Collapsed"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Surface" Property="Background" Value="{DynamicResource EditHoverBg}"/>
                                <Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/>
                            </Trigger>
                            <Trigger Property="Tag" Value="Recording">
                                <Setter TargetName="Surface" Property="Background" Value="{DynamicResource ActionBg}"/>
                                <Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource ActionStroke}"/>
                                <Setter TargetName="RecordingDot" Property="Visibility" Value="Visible"/>
                                <Setter Property="Foreground" Value="{DynamicResource ActionText}"/>
                            </Trigger>
                            <Trigger Property="Tag" Value="Starting">
                                <Setter TargetName="Surface" Property="Background" Value="{DynamicResource EditHoverBg}"/>
                                <Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/>
                                <Setter Property="Cursor" Value="Wait"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="Tag" Value="Recording"/>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="Surface" Property="Background" Value="{DynamicResource ActionHoverBg}"/>
                                <Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        )'
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this.ui.Update("ContentCon", "Focus", "True")
    }

    OnEnter(state, ctrl, event) {
        if (this._closed || this._submitting)
            return
        mods := state.Has("KeyModifiers") ? state["KeyModifiers"] : ""
        if (mods == "Shift") {
            if (state.Has("KeyFromEditable")) {
                ; PreviewKeyDown:Return 已拦截原生换行，替换选区并将光标移到下一行。
                start := this.ui.Query("ContentCon>SelectionStart")
                if (!IsInteger(start))
                    return
                this.ui.Update("ContentCon", "SelectedText", "`r`n")
                this.ui.Update("ContentCon", "CaretIndex", start + 2)
            }
        } else if (mods == "") {
            this.OnSureBtnClick(state, ctrl, event)
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this._StopRec(false)
        this.OnClose()
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._StopRec(false)
        this.OnClose()
        this._CloseWindow()
    }

    _CloseWindow() {
        this._StopRec(false)
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnSureBtnClick(state, ctrl, event) {
        if (this._closed || this._submitting)
            return
        this._submitting := true
        this._StopRec(true)
        this.OnSure()
        this.OnHide()
        this._CloseWindow()
    }

    OnCloseBtnClick(state, ctrl, event) {
        this._StopRec(false)
        this.OnClose()
        this.OnHide()
        this._CloseWindow()
    }

    OnSure() {
        if (this.SureAction != "") {
            Action := this.SureAction
            Action(this.ui.Query("ContentCon"))
            this.SureAction := ""
        }
    }

    OnClose() {
        if (this.CloseAction != "") {
            Action := this.CloseAction
            Action()
            this.CloseAction := ""
        }
    }

    OnHide() {
        if (this.HideAction != "") {
            Action := this.HideAction
            Action()
            this.HideAction := ""
        }
    }

    OnMicClick(*) {
        if (this._closed || this._submitting)
            return
        if (this._rec || this._recStarting) {
            this._StopRec(true)
            return
        }
        language := SttEngine.DefaultLanguage()
        if (!SttGui.RequestModelDownload(language))
            return
        engine := InitSttEngine()
        this._recStarting := true
        status := engine.streamLoaded && engine.streamLanguage == language
            ? GetLang("准备录音…") : GetLang("正在加载识别模型…")
        this._SetMicStatus("Starting", status, status)
        engine.StreamStartAsync(language, ObjBindMethod(this, "_OnMicStarted"))
    }

    _OnMicStarted(ok, errorText) {
        this._recStarting := false
        if (!ok) {
            try this._SetMicStatus("", GetLang("语音输入"))
            try Toast.Error(GetLang("开始录音失败：") InitSttEngine()._ErrText(errorText))
            return
        }
        this._rec := true
        this._recBase := ""
        try this._recBase := this.ui.Query("ContentCon")
        this._recLive := ""
        try this.ui.Update("ContentCon", "Foreground", "{DynamicResource TextSub}")
        try this._SetMicStatus("Recording", GetLang("停止录音"), GetLang("模型加载完成 · 录音中"))
        SetTimer(this._sttTick, 150)
    }

    _SetMicStatus(tag, tooltip, status := "") {
        this.ui.BatchUpdate([
            {ControlName: "BtnMic", PropertyName: "Tag", Value: tag},
            {ControlName: "BtnMic", PropertyName: "ToolTip", Value: tooltip},
            {ControlName: "MicStatus", PropertyName: "Text", Value: status},
            {ControlName: "MicStatus", PropertyName: "Visibility", Value: status == "" ? "Collapsed" : "Visible"}
        ])
    }

    _PollStt() {
        if (!this._rec) {
            SetTimer(this._sttTick, 0)
            return
        }
        if (!IsSet(InitSttEngine))
            return
        engine := InitSttEngine()
        live := ""
        try live := engine.StreamPoll()
        if (Trim(live) != "" && live != this._recLive)
            this._ApplyVoiceText(live)
    }

    _ApplyVoiceText(text) {
        this._recLive := text
        base := this._recBase
        sep := (base != "" && !RegExMatch(base, "\s$")) ? " " : ""
        if (IsObject(this.ui))
            this.ui.Update("ContentCon", "Text", base sep text)
    }

    _StopRec(commit := true) {
        if (this._recStarting) {
            this._recStarting := false
            InitSttEngine().StreamCancelStart()
            try this._SetMicStatus("", GetLang("语音输入"))
        }
        if (!this._rec) {
            SetTimer(this._sttTick, 0)
            return
        }
        this._rec := false
        SetTimer(this._sttTick, 0)
        try this._SetMicStatus("", GetLang("语音输入"))
        try this.ui.Update("ContentCon", "Foreground", "{DynamicResource InputText}")
        if (!IsSet(InitSttEngine))
            return
        engine := InitSttEngine()
        if (!IsObject(engine))
            return
        if (!engine.StreamEnd(0))
            return
        if (!commit)
            return
        loop 40 {
            st := engine.StreamGetState()
            if (st == 3 || st == 4)
                break
            Sleep(50)
        }
        result := Trim(engine.StreamGetResult())
        if (result != "" && result != this._recLive)
            this._ApplyVoiceText(result)
    }
}
