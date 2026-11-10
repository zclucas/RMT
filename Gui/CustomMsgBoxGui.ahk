#Requires AutoHotkey v2.0

; =====================================================================
; RMT 输出弹窗 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(Desc)
; =====================================================================

class CustomMsgBoxGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.Desc := ""
    }

    ShowGui(Desc, title := "") {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow(title)
        this.Desc := Desc
        if (IsObject(this.ui))
            this.ui.Update("TextCon", "Text", Desc)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow(title) {
        global MySoftData
        this._closed := false
        if (title == "")
            title := GetLang("RMT输出弹窗")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("*", "48")
        body.Add("TextBox").Grid_Row(0).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        btnRow := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="365" Height="225"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing", this.ui))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad", this.ui))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

    }

    OnWindowLoad(ui, *) {
        if (this.ui == ui)
            XamlWin.OnLoadTheme(ui)
    }

    OnWindowClosing(ui, *) {
        if (this.ui != ui)
            return
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnSureBtnClick(state, ctrl, event) {
        this._CloseWindow()
    }
}
