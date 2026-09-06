#Requires AutoHotkey v2.0

; =====================================================================
; RMT 免责声明 —— XAML 版（首次启动阻塞等待用户同意）
; 公开接口：AgreementGui.ShowAndWait() -> true=同意 false=拒绝/关闭
; =====================================================================

class AgreementGui {
    __new() {
        this.ui := ""
        this._closed := true
        this._result := ""
    }

    static ShowAndWait() {
        inst := AgreementGui()
        return inst._ShowAndWait()
    }

    _ShowAndWait() {
        this._BuildAndShow()
        ; 阻塞等待用户点击 同意/不同意 或窗口关闭（XAML 事件经 daemon 回调，Sleep 即可收到）
        while (this._result == "" && !this._closed) {
            Sleep(100)
        }
        return (this._result == "Agree")
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("免责声明")
        this._title := title
        titleHeight := "30"

        ; 组装条款文本（与旧 MsgBox 一致）
        Agreement1 := GetLang('1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。')
        Agreement2 := GetLang("2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。")
        Agreement3 := GetLang("3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。")
        Agreement4 := GetLang("4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。")
        Agreement5 := GetLang("若不同意上述条款，请立即停止使用本软件。")
        AgreeAgreementStr := Format("{}`n`n{}`n`n{}`n`n{}`n`n{}", Agreement1, Agreement2, Agreement3, Agreement4, Agreement5)

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容：条款文本 + 按钮 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("*", "44")
        body.Add("TextBox").Grid_Row(0).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top").Padding("8,6")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        btnRow := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnDisagree").Content(GetLang("不同意")).Width(100).Height(30).MinHeight(30).Margin("0,0,24,0")
        btnRow.Add("Button").Name("BtnAgree").Content(GetLang("同意")).Width(100).Height(30).MinHeight(30)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="300" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnDisagreeClick"))
        this.ui.OnEvent("BtnDisagree", "Click", ObjBindMethod(this, "OnDisagreeClick"))
        this.ui.OnEvent("BtnAgree", "Click", ObjBindMethod(this, "OnAgreeClick"))

        if (IsObject(this.ui))
            this.ui.Update("TextCon", "Text", AgreeAgreementStr)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.ui := ""
        this._closed := true
        if (this._result == "")
            this._result := "Disagree"
    }

    OnAgreeClick(state, ctrl, event) {
        this._result := "Agree"
        this._CloseWindow()
    }

    OnDisagreeClick(state, ctrl, event) {
        this._result := "Disagree"
        this._CloseWindow()
    }

    _CloseWindow() {
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }
}
