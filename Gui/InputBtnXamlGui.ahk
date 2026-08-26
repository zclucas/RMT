#Requires AutoHotkey v2.0

; =====================================================================
; 输入按钮条 —— XAML 迁移版（复用主进程共享 daemon，与 CustomInputGui 同构）
; 公开接口保持：ShowGui(Type) / TrueAction / FalseAction / ContinueAction
;               / CancelAction / HideAction
; Type: 1 真值/假值  2 继续  3 继续&取消
; 多实例：每请求独立实例（WorkPool._ShowInputDialog 每请求 new），互不阻塞
; =====================================================================

class InputBtnXamlGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this.Type := 0
        this.TrueAction := ""
        this.FalseAction := ""
        this.ContinueAction := ""
        this.CancelAction := ""
        this.HideAction := ""
        this.CheckHotKeyAction := this.CheckHotKey.Bind(this)
    }

    ;1 真值 假值  2 继续  3 继续&取消
    ShowGui(Type) {
        this.Type := Integer(Type)
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        SetTimer(this.CheckHotKeyAction, 30)
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
        title := GetLang("输入按钮")
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

        ; === 按钮区 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        btnRow := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        switch this.Type {
            case 1:
                btnRow.Add("Button").Name("BtnTrue").Content(GetLang("真值")).Width(80).Height(30).MinHeight(30).Margin("8,0")
                btnRow.Add("Button").Name("BtnFalse").Content(GetLang("假值")).Width(80).Height(30).MinHeight(30).Margin("8,0")
            case 2:
                btnRow.Add("Button").Name("BtnContinue").Content(GetLang("继续")).Width(80).Height(30).MinHeight(30)
            case 3:
                btnRow.Add("Button").Name("BtnContinue").Content(GetLang("继续")).Width(80).Height(30).MinHeight(30).Margin("8,0")
                btnRow.Add("Button").Name("BtnCancel").Content(GetLang("取消")).Width(80).Height(30).MinHeight(30).Margin("8,0")
        }

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="300" Height="150" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        switch this.Type {
            case 1:
                this.ui.OnEvent("BtnTrue", "Click", ObjBindMethod(this, "OnTrueBtnClick"))
                this.ui.OnEvent("BtnFalse", "Click", ObjBindMethod(this, "OnFalseBtnClick"))
            case 2:
                this.ui.OnEvent("BtnContinue", "Click", ObjBindMethod(this, "OnContinueBtnClick"))
            case 3:
                this.ui.OnEvent("BtnContinue", "Click", ObjBindMethod(this, "OnContinueBtnClick"))
                this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelBtnClick"))
        }

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                try SetTimer((*) => this.ui.Update("Window", "Opacity", "1"), -10)
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
        SetTimer(this.CheckHotKeyAction, 0)
    }

    _CloseWindow() {
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
        SetTimer(this.CheckHotKeyAction, 0)
    }

    ; Enter/Esc 快捷键（按实例 Type 分发；多实例下不能用 static Map 绑 this）
    CheckHotKey() {
        if (GetKeyState("Enter", "P")) {
            switch this.Type {
                case 1: this.OnTrueBtnClick()
                case 2, 3: this.OnContinueBtnClick()
            }
        }
        if (GetKeyState("Esc", "P")) {
            switch this.Type {
                case 1: this.OnFalseBtnClick()
                case 3: this.OnCancelBtnClick()
            }
        }
    }

    OnTrueBtnClick(*) {
        this.OnTrue()
        this.OnHide()
        this._CloseWindow()
    }

    OnFalseBtnClick(*) {
        this.OnFalse()
        this.OnHide()
        this._CloseWindow()
    }

    OnContinueBtnClick(*) {
        this.OnContinue()
        this.OnHide()
        this._CloseWindow()
    }

    OnCancelBtnClick(*) {
        this.OnCancel()
        this.OnHide()
        this._CloseWindow()
    }

    OnCancelClick(state, ctrl, event) {
        ; 标题栏关闭按钮：按取消处理（回传 cancel，避免 Worker 等待超时）
        this.OnCancel()
        this.OnHide()
        this._CloseWindow()
    }

    OnTrue() {
        if (this.TrueAction != "") {
            Action := this.TrueAction
            Action()
            this.TrueAction := ""
        }
    }

    OnFalse() {
        if (this.FalseAction != "") {
            Action := this.FalseAction
            Action()
            this.FalseAction := ""
        }
    }

    OnContinue() {
        if (this.ContinueAction != "") {
            Action := this.ContinueAction
            Action()
            this.ContinueAction := ""
        }
    }

    OnCancel() {
        if (this.CancelAction != "") {
            Action := this.CancelAction
            Action()
            this.CancelAction := ""
        }
    }

    OnHide() {
        if (this.HideAction != "") {
            Action := this.HideAction
            Action()
            this.HideAction := ""
        }
        SetTimer(this.CheckHotKeyAction, 0)
    }
}
