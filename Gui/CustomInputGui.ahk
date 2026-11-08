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
        this._rec := false
        title := GetLang("输入-弹窗")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("28", "*", "48")
        body.Add("TextBlock").Grid_Row(0).Name("LabelCon").Text("").VerticalAlignment("Center")

        ; 输入区：左右内边距与 ComboBox 一致（约 6px），上下略加大；语音按钮叠在右下角不占布局
        inputHost := body.Add("Grid").Grid_Row(1).Margin("0,8,0,8")
        inputHost.Add("TextBox").Name("ContentCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("6,8,6,8").Margin("0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        inputHost.Add("Button").Name("BtnMic").Width(26).Height(26).MinHeight(26).MinWidth(26)
            .HorizontalAlignment("Right").VerticalAlignment("Bottom").Margin("0,0,6,6")
            .Background("Transparent").BorderThickness("0").Cursor("Hand")
            .Content(Chr(0xE720)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .Foreground("{DynamicResource TextSub}").ToolTip(GetLang("语音输入"))
            .SetProp("Panel.ZIndex", "2")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="365" Height="252"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("BtnMic", "Click", ObjBindMethod(this, "OnMicClick"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
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
        if (this._rec) {
            this._StopRec(true)
            return
        }
        if (!IsSet(InitSttEngine))
            return
        engine := InitSttEngine()
        if (IsObject(engine) && !engine.IsDllReady())
            engine._TryLoadDll()
        if (!IsObject(engine) || !engine.IsDllReady()) {
            try Toast.Warning(GetLang("语音引擎未就绪"))
            return
        }
        if (!engine.IsStreamReady()) {
            SttGui.RequestModelDownload()
            return
        }
        if (!engine.StreamBegin()) {
            try Toast.Error(GetLang("开始录音失败：") engine._ErrText(engine.StreamGetLastError()))
            return
        }
        this._rec := true
        this._recBase := ""
        try this._recBase := this.ui.Query("ContentCon")
        this._recLive := ""
        try this.ui.Update("ContentCon", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("BtnMic", "Foreground", "{DynamicResource Accent}")
        try this.ui.Update("BtnMic", "ToolTip", GetLang("停止录音"))
        SetTimer(this._sttTick, 150)
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
        if (!this._rec) {
            SetTimer(this._sttTick, 0)
            return
        }
        this._rec := false
        SetTimer(this._sttTick, 0)
        try this.ui.Update("BtnMic", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("BtnMic", "ToolTip", GetLang("语音输入"))
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
