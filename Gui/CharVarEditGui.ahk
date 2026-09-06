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

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("字符变量编辑")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("Auto", "*", "Auto", "Auto")
        body.Cols("Auto", "*", "*", "*")

        ; 行1：输出内容
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("字符内容：")).VerticalAlignment("Top").Margin("0,4,0,0")
        body.Add("TextBox").Grid_Row(1).Grid_Column(1).Grid_ColumnSpan(3).Name("TextCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Margin("4,2,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 行2：变量数组（追加名/追加值，同输出指令）
        row3 := body.Add("StackPanel").Grid_Row(2).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center").Margin("0,4,0,0")
        row3.Add("TextBlock").Text(GetLang("变量数组：")).VerticalAlignment("Center")
        vt := row3.Add("ComboBox").Name("VarTypeCombo").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        row3.Add("ComboBox").Name("VariCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0")
        row3.Add("Button").Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).Margin("8,0,0,0")
        row3.Add("Button").Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行3：确定/取消
        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,10,0,0")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0")
        btnRow.Add("Button").Name("BtnCancel").Content(GetLang("取消")).Width(80).Height(32).MinHeight(32).Margin("4,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="230" Opacity="0"')
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
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelClick"))
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
        DLArr := IsResVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
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
