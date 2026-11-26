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
        this._diagnostics := FeedbackDiagnostics.Capture(this.Hwnd())
        this.ErrorList.Push(Desc)
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (IsObject(this.ui))
            this.ui.Update("TextCon", "Text", this.GetErrorText())
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    GetErrorText(includeContext := true) {
        text := ""
        for i, error in this.ErrorList {
            if (i > 1)
                text .= "`n" . "=" . "=" . "=" . "=" . "=" . "`n"
            text .= error
        }
        return includeContext ? text "`n`n" FeedbackDiagnostics.Report(this._diagnostics) : text
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("RMT错误")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClose")
        ; Cols 会新增定义，先替换标准标题栏原有的两列。
        chrome.Root._Children.RemoveAt(1)
        chrome.Root.Cols("Auto", "*", "Auto")
        chrome.Btns.Grid_Column(2)
        chrome.Root.Add("TextBlock").Grid_Column(1).Text(this._diagnostics.environment)
            .HorizontalAlignment("Right").VerticalAlignment("Center").Margin("18,0,10,0")
            .Foreground("{DynamicResource TextSub}").FontSize(11).FontWeight("Normal")
            .TextTrimming("CharacterEllipsis").ToolTip(this._diagnostics.environment)
        closeBtn := chrome.Close

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("*", "Auto", "42")
        body.Add("TextBox").Grid_Row(0).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        body.Add("TextBlock").Grid_Row(1).Text(GetLang("总是报错很烦恼吧，反馈试试吧，开发者帮您解决。"))
            .Foreground("{DynamicResource TextSub}").FontSize(12).TextAlignment("Center").TextWrapping("Wrap").Margin("0,8,0,0")
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnCopy", "0,0,50,0", GetLang("复制"))
        AddCmdOkBtn(btnRow, "BtnFeedback", "0,0,50,0", GetLang("反馈"))
            .ToolTip(GetLang("把这段报错带到论坛反馈窗口"))
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title "  " this._diagnostics.environment) '" Width="720" Height="420" MinWidth="600"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClose", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnCopy", "Click", ObjBindMethod(this, "OnCopyBtnClick"))
        this.ui.OnEvent("BtnFeedback", "Click", ObjBindMethod(this, "OnFeedbackClick"))
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

    ; 把这段报错原样带进反馈窗口，用户只需补复现步骤就能发帖
    OnFeedbackClick(state, ctrl, event) {
        txt := this.GetErrorText(false)
        this._CloseWindow()
        try FeedbackGui.ShowGui("bug", txt, this._diagnostics)
    }

}
