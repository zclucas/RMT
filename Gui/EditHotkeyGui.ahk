#Requires AutoHotkey v2.0

; =====================================================================
; 快捷方式编辑 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(ShowCon, KeyCon, OnlyTriggerKey) / AfterSureAction
; =====================================================================

class EditHotkeyGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.ShowCon := ""
        this.KeyCon := ""
        this.OnlyTriggerKey := false
        this.AfterSureAction := ""
    }

    ShowGui(ShowCon, KeyCon, OnlyTriggerKey) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        this.ShowCon := ShowCon
        this.KeyCon := KeyCon
        this.OnlyTriggerKey := OnlyTriggerKey
        if (IsObject(this.ui))
            this.ui.Update("BtnStr", "IsEnabled", !this.OnlyTriggerKey ? "True" : "False")
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
        title := GetLang("快捷方式编辑")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        btnRow := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnKey").Content(GetLang("快捷键")).Width(100).Height(50).MinHeight(50).Margin("0,0,30,0")
        btnRow.Add("Button").Name("BtnStr").Content(GetLang("字串")).Width(100).Height(50).MinHeight(50)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="420" Height="120" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnKey", "Click", (*) => this.OnEditHotKey(MyTriggerKeyGui))
        this.ui.OnEvent("BtnStr", "Click", (*) => this.OnEditHotKeyStr(MyTriggerStrGui))

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

    OnEditHotKey(gui) {
        triggerKey := this.KeyCon.Value
        gui.SureBtnAction := this.OnHotKeySureBtn.Bind(this)
        gui.ShowGui(triggerKey, 0, true)
        this._CloseWindow()
    }

    OnEditHotKeyStr(gui) {
        triggerStr := this.KeyCon.Value
        gui.SureBtnAction := this.OnHotStrSureBtn.Bind(this)
        gui.ShowGui(triggerStr, 0, true)
        this._CloseWindow()
    }

    OnHotKeySureBtn(sureTriggerStr, holdTime, *) {
        if (sureTriggerStr != "" && SubStr(sureTriggerStr, 1, 1) == "~") {
            sureTriggerStr := SubStr(sureTriggerStr, 2)
        }
        this.KeyCon.Value := sureTriggerStr
        this.KeyCon.Enabled := false
        this.KeyCon.Visible := true
        this.ShowCon.Visible := false
        try this.ShowCon.Value := sureTriggerStr
        if (this.AfterSureAction != "") {
            cb := this.AfterSureAction
            this.AfterSureAction := ""
            cb(sureTriggerStr)
        }
    }

    OnHotStrSureBtn(sureTriggerStr) {
        this.KeyCon.Value := sureTriggerStr
        this.KeyCon.Enabled := false
        this.KeyCon.Visible := true
        this.ShowCon.Visible := false
        try this.ShowCon.Value := sureTriggerStr
        if (this.AfterSureAction != "") {
            cb := this.AfterSureAction
            this.AfterSureAction := ""
            cb(sureTriggerStr)
        }
    }
}

OnOpenEditHotkeyGui(showCon, keyCon, OnlyTriggerKey, *) {
    MyEditHotkeyGui.ShowGui(showCon, keyCon, OnlyTriggerKey)
}
