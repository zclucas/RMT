#Requires AutoHotkey v2.0

; 跳转指令仅选择动作；以 流程跳转_动作 保存，不分配序列号。
class FlowJumpGui {
    __New() {
        this.ParentTile := ""
        this.OwnerHwnd := ""
        this.SureBtnAction := ""
        this.ui := ""
        this._closed := true
    }

    Hwnd() {
        return IsObject(this.ui) ? this.ui.wpfHwnd : 0
    }

    ShowGui(cmd) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        selected := cmd == "" ? FlowJumpActions()[1] : FlowJumpAction(cmd)
        this._closed := false
        titleHeight := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "48")
        XAMLHost.AddCmdTitleBar(main, this.ParentTile GetLang("跳转编辑器"), titleHeight)
        combo := main.Add("ComboBox").Grid_Row(1).Name("ActionCon").Height(28).MinHeight(28)
            .Margin("16,14").VerticalAlignment("Center").VerticalContentAlignment("Center")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        selectedIndex := 0
        for i, action in FlowJumpActions() {
            combo.Add("ComboBoxItem").Content(GetLang(action))
            if (action == selected)
                selectedIndex := i - 1
        }
        combo.SelectedIndex(String(selectedIndex))
        buttons := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(buttons)
        template := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(template, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Width="330" Height="150"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancel"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSure"))
        BindCmdEditorChrome(this.ui, "#指令手册/跳转")
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui)
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.OnWindowClosing()
    }

    OnWindowLoad(*) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(*) {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui)
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        this._closed := true
    }

    _CloseWindow() {
        if (IsObject(this.ui))
            this.ui.Update("Window", "Close", "")
        this.OnWindowClosing()
        this.ui := ""
    }

    OnCancel(*) {
        this._CloseWindow()
    }

    GetCommandStr() {
        selected := this.ui.Query("ActionCon>SelectedIndex")
        actions := FlowJumpActions()
        if (!IsNumber(selected) || Integer(selected) < 0 || Integer(selected) >= actions.Length)
            throw Error("Invalid flow jump selection")
        return "流程跳转_" actions[Integer(selected) + 1]
    }

    OnSure(*) {
        cmd := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(cmd)
    }
}
