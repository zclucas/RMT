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
        title := GetLang("宏高级设置")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        ; 边距：左/右 15，上 4（相对原 14 上移 10），下 10（相对原 14 略收）
        body := main.Add("Grid").Grid_Row(1).Margin("15,4,15,10")
        body.Rows("36", "36", "36", "*")

        ; 按键类型
        tkRow := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        tkRow.Add("TextBlock").Text(GetLang("按键类型：")).Width(90).VerticalAlignment("Center")
        tk := tkRow.Add("ComboBox").Name("TKTypeCombo").Width(125).Height(26).MinHeight(26)
        for t in GetLangArr(["AHK Send", "keybd_event", "罗技", "AHI"])
            tk.Add("ComboBoxItem").Content(t)
        toolHover := FrontInfoGui._ToolBtnHoverStyle()
        okStyle := FrontInfoGui._OkBtnHoverStyle()
        helpBtn := FrontInfoGui._AddSquareHelpBtn(tkRow, "BtnHelp")
        helpBtn.InjectResources(toolHover)

        ; 结束提示音右推：下拉右缘与下方「编辑」右缘对齐
        tipGrid := body.Add("Grid").Grid_Row(1).VerticalAlignment("Center")
        tipGrid.Cols("90", "125", "*", "90", "125")
        tipGrid.Add("TextBlock").Grid_Column(0).Text(GetLang("开始提示音：")).VerticalAlignment("Center")
        st := tipGrid.Add("ComboBox").Grid_Column(1).Name("StartTipCombo").Height(26).MinHeight(26)
        for t in GetLangArr(["无", "触发提示", "循环首次提示"])
            st.Add("ComboBoxItem").Content(t)
        tipGrid.Add("TextBlock").Grid_Column(3).Text(GetLang("结束提示音：")).VerticalAlignment("Center").HorizontalAlignment("Right").Margin("0,0,8,0")
        et := tipGrid.Add("ComboBox").Grid_Column(4).Name("EndTipCombo").Height(26).MinHeight(26).HorizontalAlignment("Stretch")
        for t in GetLangArr(["无", "结束提示", "循环结束提示"])
            et.Add("ComboBoxItem").Content(t)

        ; §22 窗口绑定：文本框吃剩余宽度，编辑按钮 Auto，避免右侧被裁
        bwGrid := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        bwGrid.Cols("90", "*", "Auto")
        bwGrid.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口绑定：")).VerticalAlignment("Center")
        bwGrid.Add("TextBox").Grid_Column(1).Name("BindWindowCon").Height(26).MinHeight(26).Margin("0,0,6,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        editBtn := bwGrid.Add("Button").Grid_Column(2).Name("BtnBindWinEdit").Content(GetLang("编辑")).Width(56).Height(26).MinHeight(26).Padding("12,0").Cursor("Hand")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1.25")
            .Foreground("{DynamicResource TextMain}")
        editBtn.InjectResources(toolHover)

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        okBtn := btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(80).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
        okBtn.InjectResources(okStyle)

        ; === 创建 XAMLHost ===
        ; 宽约 15+90+125+12+90+125+15 ≈ 472，取 480；提示音并排后高度可收
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="480" Height="200" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickModeHelpBtn"))
        this.ui.OnEvent("BtnBindWinEdit", "Click", ObjBindMethod(this, "OnClickBindWinEdit"))
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
        ; §22 窗口绑定（旧配置无此字段时回退空）
        this.ui.Update("BindWindowCon", "Text", ObjHasOwnProp(item, "BindWindow") ? item.BindWindow : "")
    }

    ; §22 窗口绑定编辑：复用 FrontInfoGui 选窗
    OnClickBindWinEdit(state := "", ctrl := "", event := "") {
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "BindWindowCon"))
    }

    OnClickModeHelpBtn(state, ctrl, event) {
        str1 := GetLang("AHK Send：通用方式，适合办公软件与大多数游戏（管理员权限可以让更多游戏有效）。")
        str2 := GetLang("keybd_event：调用 Win 系统接口模拟按键，适用比较旧的软件或游戏（需管理员权限）。")
        str3 := GetLang("罗技：调用罗技驱动模拟按键（需管理员权限，并使用 G HUB 2022.2.1154 及以前版本）。")
        str4 := GetLang("AHI：调用 Interception 驱动模拟按键（需安装 Interception 驱动）。")
        str5 := GetLang("Tip:罗技按键类型（含键盘与鼠标）仅支持 G HUB 2022.2.1154 及以前版本") "`n" GetLang(
            "Tip:AHI驱动需要安装Interception驱动并以管理员权限运行")
        str6 := GetLang("**keybd_event、罗技、AHI 的按键可以作为宏的触发按键，切勿自己触发自己导致死循环**")
        str := Format("{}`n`n{}`n`n{}`n`n{}`n`n{}`n`n{}", str1, str2, str3, str4, str5, str6)
        RmtDialog.Info(str, GetLang("按键类型"))
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
        ; §22 窗口绑定保存
        item.BindWindow := this.ui.Query("BindWindowCon")
        this._CloseWindow()
        ; §18 宏高级设置即时持久化 + Worker 热重载（Mode/提示音/BindWindow 影响执行语义）
        HotReloadPublish(this.tableItem.Index, 0)
    }
}
