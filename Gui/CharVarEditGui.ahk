#Requires AutoHotkey v2.0

; =====================================================================
; 字符变量编辑窗（§21.3）：变量指令「字符」类型的构建入口，
; 复用输出指令的「变量数组 追加名/追加值」组合方式构建字符内容。
; 公开接口保持：ShowGui(initialText) / SureBtnAction(text) / OwnerHwnd / ParentTile
; =====================================================================

class CharVarEditGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._initialText := ""
    }

    ShowGui(initialText := "") {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._initialText := initialText
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.ui.Update("TextCon", "Text", this._initialText)
        this.ui.Update("VariCombo", "SelectedIndex", "0")
        this._ShowWindow()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("文本构造")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容（与文件读写 / 运行Pro 的文本构造一致）===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8").ClipToBounds("False")
        body.Rows("Auto", "6", "32", "48")

        body.Add("TextBox").Grid_Row(0).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2,3").FontSize("11")
            .Height("95").MinHeight("95")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        row1 := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        row1.Cols("88", "80", "8", "200", "8", "70", "8", "70")
        row1.Add("TextBlock").Grid_Column(0).Text(GetLang("变量数组：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        vt := row1.Add("ComboBox").Grid_Column(1).Name("VarTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center").SelectedIndex("0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        variables := row1.Add("ComboBox").Grid_Column(3).Name("VariCombo").Width("200").Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left").IsEditable("True")
        for name in GetGuiVarArr("all") {
            if (name != "")
                variables.Add("ComboBoxItem").Content(name)
        }
        row1.Add("Button").Grid_Column(5).Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).VerticalAlignment("Center")
        row1.Add("Button").Grid_Column(7).Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).VerticalAlignment("Center")

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnOk")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="580" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("VarTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshVarType"))
        this.ui.OnEvent("BtnAddName", "Click", ObjBindMethod(this, "OnClickAddVarNameBtn"))
        this.ui.OnEvent("BtnAddValue", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    _ShowWindow() {
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    OnRefreshVarType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsResVar := this.ui.Query("VarTypeCombo") == GetLang("变量")
        DLArr := IsResVar ? GetGuiVarArr("all") : GetGuiArrNameArr()
        curText := this.ui.Query("VariCombo")
        this.ui.Update("VariCombo", "ClearItems", "")
        for it in DLArr {
            if (it == "")
                continue
            this.ui.Update("VariCombo", "AddItem", it)
        }
        if (curText != "")
            this.ui.Update("VariCombo", "Text", curText)
        else
            this.ui.Update("VariCombo", "SelectedIndex", "0")
    }

    OnClickAddVarNameBtn(state, ctrl, event) {
        this.ui.Update("TextCon", "Text", this.ui.Query("TextCon") . this.ui.Query("VariCombo"))
    }

    OnClickAddVarValueBtn(state, ctrl, event) {
        ArraySymbol := this.ui.Query("VarTypeCombo") == GetLang("变量") ? "" : "ε"
        this.ui.Update("TextCon", "Text", this.ui.Query("TextCon") . "{" ArraySymbol this.ui.Query("VariCombo") "}")
    }

    OnClickSureBtn(state, ctrl, event) {
        content := this.ui.Query("TextCon")
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(content)
    }
}
