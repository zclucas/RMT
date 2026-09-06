#Requires AutoHotkey v2.0

; =====================================================================
; RMT 错误 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(Desc)
; =====================================================================

class ErrorMsgBoxGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.Desc := ""
        this.ErrorList := []
    }

    ShowGui(Desc) {
        this.ErrorList.Push(Desc)
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (IsObject(this.ui))
            this.ui.Update("TextCon", "Text", this.GetErrorText())
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    GetErrorText() {
        text := ""
        for i, error in this.ErrorList {
            if (i > 1)
                text .= "`n" . "=" . "=" . "=" . "=" . "=" . "`n"
            text .= error
        }
        return text
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
        title := GetLang("RMT错误")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClose")
        closeBtn := chrome.Close

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("*", "42")
        body.Add("TextBox").Grid_Row(0).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        btnRow := body.Add("Grid").Grid_Row(1).HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Cols("Auto", "300", "Auto")
        btnRow.Add("Button").Name("BtnCopy").Grid_Column(0).Content(GetLang("复制")).Width(80).Height(30).MinHeight(30)
        btnRow.Add("Button").Name("BtnOk").Grid_Column(2).Content(GetLang("确定")).Width(80).Height(30).MinHeight(30)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="325" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClose", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnCopy", "Click", ObjBindMethod(this, "OnCopyBtnClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnCancelClick"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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

    OnCopyBtnClick(state, ctrl, event) {
        if (IsObject(this.ui)) {
            try {
                txt := this.ui.Query("TextCon")
                if (txt != "") {
                    A_Clipboard := txt
                    Toast.Success(GetLang("已复制"))
                }
            }
        }
    }

}
