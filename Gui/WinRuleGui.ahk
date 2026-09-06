#Requires AutoHotkey v2.0

; =====================================================================
; 窗口规格编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui() / SureAction / OwnerHwnd
; =====================================================================

class WinRuleGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.SureAction := ""
    }

    ShowGui() {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        if (IsObject(this.ui)) {
            this.ui.Update("WidthCon", "Text", A_ScreenWidth)
            this.ui.Update("HeightCon", "Text", A_ScreenHeight)
            this.ui.Update("RemarkCon", "Text", GetLang("全屏"))
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
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
        title := GetLang("窗口规格编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,14")
        body.Rows("36", "36", "36", "*")
        body.Cols("100", "100")

        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("屏幕宽度：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("WidthCon").Height(26).MinHeight(26).VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("屏幕高度：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(1).Grid_Column(1).Name("HeightCon").Height(26).MinHeight(26).VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(2).Grid_Column(1).Name("RemarkCon").Height(26).MinHeight(26).VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(80).Height(32).MinHeight(32)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="230" Height="185" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnSureBtnClick(state, ctrl, event) {
        if (!IsNumber(this.ui.Query("WidthCon")) || !IsNumber(this.ui.Query("HeightCon"))) {
            MsgBox(GetLang("屏幕宽高需要输入数字"))
            return
        }

        action := this.SureAction
        if (action != "") {
            RemarkText := Trim(this.ui.Query("RemarkCon"))
            RemarkText := Trim(RemarkText, "`n")
            action(this.ui.Query("WidthCon"), this.ui.Query("HeightCon"), RemarkText)
            this.SureAction := ""
        }
        this._CloseWindow()
    }
}
