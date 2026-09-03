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

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("*", "42")
        body.Add("TextBox").Grid_Row(0).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        btnRow := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnCopy").Content(GetLang("复制")).Width(80).Height(30).MinHeight(30).Margin("0,0,10,0")
        btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(80).Height(30).MinHeight(30).Margin("0,0,10,0")
        btnRow.Add("Button").Name("BtnClose").Content(GetLang("关闭")).Width(80).Height(30).MinHeight(30)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="325" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnCopy", "Click", ObjBindMethod(this, "OnCopyBtnClick"))
        this.ui.OnEvent("BtnClear", "Click", ObjBindMethod(this, "OnClearBtnClick"))
        this.ui.OnEvent("BtnClose", "Click", ObjBindMethod(this, "OnCloseBtnClick"))

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                try SetTimer((*) => (IsObject(this.ui) ? this.ui.Update("Window", "Opacity", "1") : ""), -10)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd)
            this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        } finally {
        }
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

    OnClearBtnClick(state, ctrl, event) {
        this.ErrorList := []
        if (IsObject(this.ui))
            this.ui.Update("TextCon", "Text", "")
    }

    OnCloseBtnClick(state, ctrl, event) {
        this._CloseWindow()
    }
}
