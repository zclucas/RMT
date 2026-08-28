#Requires AutoHotkey v2.0

; =====================================================================
; 宏高级设置 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(tableIndex, itemIndex) / OwnerHwnd
; =====================================================================

class MacroSettingGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.tableItem := ""
        this.itemIndex := ""
    }

    ; 表身份 = TableItem 对象（位置不代表身份）
    ShowGui(tableItem, itemIndex) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(tableItem, itemIndex)
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
        title := GetLang("宏高级设置")
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
        body := main.Add("Grid").Grid_Row(1).Margin("15,14")
        body.Rows("40", "40", "40", "*")
        body.Cols("90", "160")

        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("按键类型：")).VerticalAlignment("Center")
        tkRow := body.Add("StackPanel").Grid_Row(0).Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        tk := tkRow.Add("ComboBox").Name("TKTypeCombo").Width(140).Height(26).MinHeight(26)
        for t in GetLangArr(["AHK Send", "keybd_event", "罗技", "AHI"])
            tk.Add("ComboBoxItem").Content(t)
        tkRow.Add("Button").Name("BtnHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("6,0,0,0")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("开始提示音：")).VerticalAlignment("Center")
        st := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("StartTipCombo").Width(140).Height(26).MinHeight(26).HorizontalAlignment("Left")
        for t in GetLangArr(["无", "触发提示", "循环首次提示"])
            st.Add("ComboBoxItem").Content(t)

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("结束提示音：")).VerticalAlignment("Center")
        et := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("EndTipCombo").Width(140).Height(26).MinHeight(26).HorizontalAlignment("Left")
        for t in GetLangArr(["无", "结束提示", "循环结束提示"])
            et.Add("ComboBoxItem").Content(t)

        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="300" Height="200" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickModeHelpBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                if (this.OwnerHwnd != "")
                    try this.ui.Update("Window", "NativeOwner", String(this.OwnerHwnd))
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

    _SelIndex(comboName) {
        v := IsObject(this.ui) ? this.ui.Query(comboName ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    Init(tableItem, itemIndex) {
        this.tableItem := tableItem
        this.itemIndex := itemIndex
        item := this.tableItem.Items[itemIndex]
        this.ui.Update("TKTypeCombo", "SelectedIndex", String(item.Mode - 1))
        this.ui.Update("StartTipCombo", "SelectedIndex", String(item.StartTipSound - 1))
        this.ui.Update("EndTipCombo", "SelectedIndex", String(item.EndTipSound - 1))
    }

    OnClickModeHelpBtn(state, ctrl, event) {
        str1 := GetLang("AHK Send：通用方式，适合办公软件与大多数游戏（管理员权限可以让更多游戏有效）。")
        str2 := GetLang("keybd_event：调用 Win 系统接口模拟按键，适用比较旧的软件或游戏（需管理员权限）。")
        str3 := GetLang("罗技：调用罗技驱动模拟按键（需管理员权限，并使用 G HUB 2022.2.1154 及以前版本）。")
        str4 := GetLang("AHI：调用 Interception 驱动模拟按键（需安装 Interception 驱动）。")
        str5 := GetLang("Tip:罗技按键类型（含键盘与鼠标）仅支持 G HUB 2022.2.1154 及以前版本") "`n" GetLang(
            "Tip:AHI驱动需要安装Interception驱动并以管理员权限运行")
        str6 := GetLang("**keybd_event、罗技、AHI 的按键可以作为宏的触发按键，切勿自己触发自己导致死循环**")
        str := Format("{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6)
        MsgBox(str)
    }

    OnSureBtnClick(state, ctrl, event) {
        mode := this._SelIndex("TKTypeCombo") + 1
        ; 改成罗技(3)/AHI(4)时检查对应驱动是否已安装，未安装则弹出安装提示（运行时检测逻辑保持不变）
        if (mode == 3) {
            InitLogitechGHubNew()
        } else if (mode == 4) {
            if (!IsInterceptionInstalled())
                ShowInterceptionInstallTip()
        }
        item := this.tableItem.Items[this.itemIndex]
        item.Mode := mode
        item.StartTipSound := this._SelIndex("StartTipCombo") + 1
        item.EndTipSound := this._SelIndex("EndTipCombo") + 1
        this._CloseWindow()
    }
}
