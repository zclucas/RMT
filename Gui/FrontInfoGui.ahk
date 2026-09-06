#Requires AutoHotkey v2.0

; =====================================================================
; 前台信息编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(winInfoCon, isFront) / OwnerHwnd / HideAction / SureAction
; winInfoCon 用 XamlValueBridge（含 .Value 读写），F1 取窗 + 鼠标信息定时器沿用原生
; =====================================================================

class FrontInfoGui {
    __new() {
        this.Gui := ""
        this.ui := ""
        this.OwnerHwnd := ""
        this.InfoAction := () => this.RefreshMouseInfo()
        this.HideAction := ""
        this.SureAction := ""
        this.winInfoCon := ""
        this.isFront := false
        this._closed := true
        this._topOn := true

        ; 控件名数组（索引 1..5 对应 运行时鼠标下窗口/句柄ID/标题/窗口类/进程名）
        this.InfoTogArrCon := ["Tog1", "Tog2", "Tog3", "Tog4", "Tog5"]
        this.InfoTextArrCon := ["InfoText1", "InfoText2", "InfoText3", "InfoText4", "InfoText5"]
        this.VarConArr := ["VariTipCon", "VariCon", "BtnAddVar"]
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    ; 24 在 100/125/150/200% DPI 都是整数物理像素。26×125%=32.5，窗口取整会裁掉底边，边框粗细就会不均。
    static _SnapBox() {
        return 24
    }

    ; 方形问号：宽高锁定同一像素，避免默认 Button 内边距 / 字号适配把高度撑高
    static _AddSquareHelpBtn(parent, name := "BtnHelp", tip := "") {
        box := FrontInfoGui._SnapBox()
        btn := parent.Add("Button").Name(name).Content("?")
            .Width(box).Height(box).MinWidth(box).MinHeight(box).MaxWidth(box).MaxHeight(box)
            .FontSize(11).Padding("0").Margin("6,0,0,0")
            .VerticalAlignment("Center").HorizontalAlignment("Center")
            .Cursor("Hand")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground("{DynamicResource TextMain}")
            .SnapsToDevicePixels("True").UseLayoutRounding("False")
        if (tip != "")
            btn.ToolTip(tip)
        return btn
    }

    static _ToolBtnHoverStyle() {
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="False"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    static _OkBtnHoverStyle() {
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="False"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ShowGui(winInfoCon, isFront := false) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.isFront := isFront
        this.Init(winInfoCon)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("前台信息编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "28", "Auto")

        chrome := XAMLHost.AddTitleBarChrome(main, title)
        BtnGroup := chrome.Btns
        pinHost := BtnGroup.Add("Grid").Width(30).ClipToBounds("False").VerticalAlignment("Stretch")
        pinBtn := pinHost.Add("Button").Name("BtnTop")
            .Style("{StaticResource FrontPinBtn}")
            .WindowChrome_IsHitTestVisibleInChrome("True")
            .Width(30).Height(titleHeight).MinHeight(titleHeight).Padding("0").Cursor("Hand")
            .VerticalAlignment("Stretch")
            .ToolTip(GetLang("窗口置顶"))
            .Background("Transparent").BorderBrush("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TitleBarForeground}")
        pinBtn.Add("TextBlock").Text(Chr(0xE840)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
            .FontSize(12).VerticalAlignment("Center").HorizontalAlignment("Center")
        pinDot := pinHost.Add("Grid").Name("BtnTopDot").Visibility("Collapsed")
        pinDot.Add("Ellipse").Width(6).Height(6).Fill("{DynamicResource Accent}")
            .HorizontalAlignment("Right").VerticalAlignment("Top")
            .Margin("0,2,2,0").IsHitTestVisible("False")
        XAMLHost.AddTitleCloseBtn(BtnGroup, "BtnClosePanel", titleHeight)

        ; === 顶部行：F1 键帽 + 确定信息 + 问号 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,2,10,0").VerticalAlignment("Center")
        box := FrontInfoGui._SnapBox()
        f1Cap := top.Add("Border").CornerRadius("3").BorderThickness("1.25").Padding("8,0")
            .Height(box).MinHeight(box)
            .BorderBrush("{DynamicResource ControlBorder}").Background("{DynamicResource ControlBg}")
            .VerticalAlignment("Center").SnapsToDevicePixels("True").UseLayoutRounding("False")
            .ToolTip(GetLang("按 F1 抓取当前鼠标下窗口信息"))
        f1Cap.Add("TextBlock").Text(FormatHotkeyDisplay("F1")).FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Foreground("{DynamicResource TextMain}")
        top.Add("TextBlock").Text(GetLang("确定信息")).VerticalAlignment("Center").Margin("8,0,0,0")
        toolHover := FrontInfoGui._ToolBtnHoverStyle()
        okStyle := FrontInfoGui._OkBtnHoverStyle()
        helpBtn := FrontInfoGui._AddSquareHelpBtn(top, "BtnHelp", GetLang("窗口信息说明"))
        helpBtn.InjectResources(toolHover)

        ; === 主体 ===
        body := main.Add("Grid").Grid_Row(2).Margin("10,4,10,0")
        body.Cols("Auto", "*")
        body.Rows("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto")
        body.Add("TextBlock").Text(GetLang("当前鼠标下窗口信息：")).Grid_Row(0).Grid_ColumnSpan(2).VerticalAlignment("Center")
        body.Add("TextBox").Name("CurWinInfoCon").Grid_Row(1).Grid_ColumnSpan(2).Height(97).Margin("0,2,0,4").IsReadOnly("True")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .AcceptsReturn("True").TextWrapping("NoWrap")
            .HorizontalScrollBarVisibility("Auto").VerticalScrollBarVisibility("Disabled")

        this._AddInfoRow(body, 2, 1, GetLang("运行时鼠标下窗口"), true)
        this._AddInfoRow(body, 3, 2, GetLang("句柄ID"), false)
        varRow := body.Add("StackPanel").Grid_Row(4).Grid_Column(1).Orientation("Horizontal")
            .HorizontalAlignment("Right").Margin("0,4,0,0")
        varRow.Add("TextBlock").Name("VariTipCon").Text(GetLang("变量:")).VerticalAlignment("Center")
        varRow.Add("ComboBox").Name("VariCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        addVarBtn := varRow.Add("Button").Name("BtnAddVar").Content(GetLang("追加变量值")).Width(110).Height(26).MinHeight(26).Padding("12,0").Margin("6,0,0,0").Cursor("Hand")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1.25")
            .Foreground("{DynamicResource TextMain}")
        addVarBtn.InjectResources(toolHover)
        this._AddInfoRow(body, 5, 3, GetLang("标题"), false)
        this._AddInfoRow(body, 6, 4, GetLang("窗口类"), false)
        this._AddInfoRow(body, 7, 5, GetLang("进程名"), false)
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(2).Orientation("Horizontal")
            .HorizontalAlignment("Center").Margin("0,10,0,4")
        sureBtn := btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(80).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
        sureBtn.InjectResources(okStyle)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="460" Height="425" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        pinStyle := '<Style x:Key="FrontPinBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/><Setter Property="MinHeight" Value="30"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TitleBarForeground}"/>'
            . '<Setter Property="FocusVisualStyle" Value="{x:Null}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', pinStyle)

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTop", "Click", ObjBindMethod(this, "OnTopTogClick"))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("BtnAddVar", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        for i in [1, 2, 3, 4, 5] {
            name := "Tog" i
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnTogClick").Bind(i))
        }

    }

    _AddInfoRow(parent, row, idx, label, hideText) {
        if (hideText) {
            parent.Add("CheckBox").Name("Tog" idx).Content(label).Grid_Row(row).Grid_Column(0).Grid_ColumnSpan(2)
                .VerticalAlignment("Center").Margin("0,4,0,0")
            return
        }
        parent.Add("CheckBox").Name("Tog" idx).Content(label).Grid_Row(row).Grid_Column(0)
            .VerticalAlignment("Center").Margin("0,4,8,0")
        box := parent.Add("Border").Grid_Row(row).Grid_Column(1).Margin("0,4,0,0")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1").CornerRadius("3").Height(28).MinHeight(28).Padding("0")
            .SnapsToDevicePixels("True")
        box.Add("TextBox").Name("InfoText" idx)
            .Height(26).MinHeight(26).BorderThickness("0").Background("Transparent")
            .Foreground("{DynamicResource InputText}").VerticalContentAlignment("Center").Padding("4,1")
            .HorizontalScrollBarVisibility("Disabled").VerticalScrollBarVisibility("Disabled")
    }

    Init(winInfoCon) {
        this.winInfoCon := winInfoCon
        this._topOn := true
        this._SyncTopBtn()
        infoStr := winInfoCon.Value
        if (InStr(infoStr, "❖")) {
            idStr := StrReplace(infoStr, "❖", "")
            infoArr := ["", idStr, "", "", ""]
        }
        else {
            infoArr := ["", "", ""]
            if (infoStr != "") {
                tmp := StrSplit(infoStr, "⎖")
                if (tmp.Length == 3)
                    infoArr := tmp
            }
            infoArr.InsertAt(1, "")
            infoArr.InsertAt(1, "")
        }

        loop 5 {
            this.ui.Update(this.InfoTogArrCon[A_Index], "IsChecked", infoArr[A_Index] != "" ? "True" : "False")
            this.ui.Update(this.InfoTextArrCon[A_Index], "Text", infoArr[A_Index])
        }

        DLVariableArr := GetGuiVarArr(4)
        this.ui.Update("VariCon", "ClearItems", "")
        for it in DLVariableArr {
            if (it == "")
                continue
            this.ui.Update("VariCon", "AddItem", it)
        }
        this.ui.Update("VariCon", "SelectedIndex", "0")

        loop 5 {
            if (this.ui.Query(this.InfoTogArrCon[A_Index]) == "True") {
                this.OnTogClick(A_Index)
                break
            }
        }
    }

    RefreshMouseInfo() {
        static labels := ""
        if (labels == "") {
            labels := {
                hwnd: GetLang("句柄ID："),
                title: GetLang("标题："),
                class: GetLang("窗口类："),
                process: GetLang("进程名：")
            }
        }

        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }

            tipStr := labels.hwnd winId "`n" labels.title title "`n" labels.class className "`n" labels.process process
            this.ui.Update("CurWinInfoCon", "Text", tipStr)
        }
    }

    ToggleFunc(state) {
        if (state) {
            SetTimer this.InfoAction, 100
            Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            SetTimer this.InfoAction, 0
            Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    CheckIfValid() {
        if (this.ui.Query("Tog2") == "True" && this.ui.Query("InfoText2") == "") {
            MsgBox(GetLang("勾选句柄ID后，句柄ID内容不能为空"), "", "Owner" this.Hwnd())
            return false
        }

        if (this.ui.Query("Tog3") == "True" && this.ui.Query("InfoText3") == "") {
            MsgBox(GetLang("勾选标题后，标题内容不能为空"), "", "Owner" this.Hwnd())
            return false
        }

        if (this.ui.Query("Tog4") == "True" && this.ui.Query("InfoText4") == "") {
            MsgBox(GetLang("勾选窗口类后，窗口类内容不能为空"), "", "Owner" this.Hwnd())
            return false
        }

        if (this.ui.Query("Tog5") == "True" && this.ui.Query("InfoText5") == "") {
            MsgBox(GetLang("勾选进程名后，进程名内容不能为空"), "", "Owner" this.Hwnd())
            return false
        }

        if (this.isFront && this.ui.Query("Tog2") == "True") {
            if (InStr(this.ui.Query("InfoText2"), "{")) {
                MsgBox(GetLang("前台窗口信息句柄ID不能使用变量"), "", "Owner" this.Hwnd())
                return false
            }
        }

        return true
    }

    GetInfoStr() {
        if (this.ui.Query("Tog2") == "True")
            return "❖" this.ui.Query("InfoText2")

        Str := ""
        loop 5 {
            if (A_Index == 1 || A_Index == 2)
                continue
            if (this.ui.Query("Tog" A_Index) == "True") {
                Str .= this.ui.Query("InfoText" A_Index)
            }
            if (A_Index != 5)
                Str .= "⎖"
        }
        if (Str == "⎖⎖")
            return ""
        return Str
    }

    OnSureBtnClick(state, ctrl, event) {
        isValid := this.CheckIfValid()
        if (!isValid)
            return

        this.winInfoCon.Value := this.GetInfoStr()
        this._CloseWindow()
        if (this.HideAction != "") {
            action := this.HideAction
            action()
            this.HideAction := ""
        }
        if (this.SureAction != "") {
            action := this.SureAction
            action()
            this.SureAction := ""
        }
    }

    OnTopTogClick(state, ctrl, event) {
        this._topOn := !this._topOn
        this._SyncTopBtn()
    }

    _SyncTopBtn() {
        if (!IsObject(this.ui))
            return
        on := !!this._topOn
        if (on) {
            try this.ui.Update("BtnTop", "Background", "{DynamicResource ActionBg}")
            try this.ui.Update("BtnTop", "BorderBrush", "{DynamicResource ActionStroke}")
            try this.ui.Update("BtnTop", "BorderThickness", "1")
            try this.ui.Update("BtnTop", "Foreground", "{DynamicResource ActionText}")
            try this.ui.Update("BtnTopDot", "Visibility", "Visible")
        } else {
            try this.ui.Update("BtnTop", "Background", "Transparent")
            try this.ui.Update("BtnTop", "BorderBrush", "Transparent")
            try this.ui.Update("BtnTop", "BorderThickness", "0")
            try this.ui.Update("BtnTop", "Foreground", "{DynamicResource TitleBarForeground}")
            try this.ui.Update("BtnTopDot", "Visibility", "Collapsed")
        }
        try this.ui.Update("Window", "Topmost", on ? "True" : "False")
        hwnd := this.Hwnd()
        if (hwnd) {
            topVal := on ? 1 : 0
            try WinSetAlwaysOnTop(topVal, "ahk_id " hwnd)
        }
    }

    OnTogClick(index, *) {
        isOn := this.ui.Query("Tog" index) == "True"
        if (!isOn)
            return

        switch (index) {
            case 1:
            {
                loop 5 {
                    this.ui.Update("Tog" A_Index, "IsChecked", "False")
                }
                this.ui.Update("Tog1", "IsChecked", "True")
                this.ui.Update("Tog2", "IsChecked", "True")
                this.ui.Update("InfoText2", "Text", "{" GetLang("句柄ID") "}")
                this.ui.Update("InfoText2", "IsEnabled", "False")
                for name in this.VarConArr
                    this.ui.Update(name, "IsEnabled", "False")
                this.ui.Update("InfoText3", "IsEnabled", "False")
                this.ui.Update("InfoText4", "IsEnabled", "False")
                this.ui.Update("InfoText5", "IsEnabled", "False")
            }
            case 2:
            {
                loop 5 {
                    this.ui.Update("Tog" A_Index, "IsChecked", "False")
                }
                this.ui.Update("Tog2", "IsChecked", "True")
                this.ui.Update("InfoText2", "IsEnabled", "True")
                for name in this.VarConArr
                    this.ui.Update(name, "IsEnabled", "True")
                this.ui.Update("InfoText3", "IsEnabled", "False")
                this.ui.Update("InfoText4", "IsEnabled", "False")
                this.ui.Update("InfoText5", "IsEnabled", "False")
            }
            default:
            {
                this.ui.Update("Tog1", "IsChecked", "False")
                this.ui.Update("Tog2", "IsChecked", "False")
                this.ui.Update("InfoText2", "IsEnabled", "False")
                for name in this.VarConArr
                    this.ui.Update(name, "IsEnabled", "False")
                this.ui.Update("InfoText3", "IsEnabled", "True")
                this.ui.Update("InfoText4", "IsEnabled", "True")
                this.ui.Update("InfoText5", "IsEnabled", "True")
            }
        }
    }

    OnF1() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }

            this.ui.Update("Tog3", "IsChecked", "True")
            this.ui.Update("Tog4", "IsChecked", "True")
            this.ui.Update("Tog5", "IsChecked", "True")
            this.ui.Update("Tog2", "IsChecked", "False")
            this.ui.Update("InfoText2", "IsEnabled", "False")
            for name in this.VarConArr
                this.ui.Update(name, "IsEnabled", "False")

            this.ui.Update("InfoText2", "Text", winId)
            this.ui.Update("InfoText3", "Text", title)
            this.ui.Update("InfoText4", "Text", className)
            this.ui.Update("InfoText5", "Text", process)
            this.OnTogClick(3)
        }
    }

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("优先级：句柄ID > 标题 + 窗口类 + 进程名")
        str2 := GetLang("句柄ID支持多ID任意适配")
        str := Format("{}`n{}", str1, str2)
        RmtDialog.Info(str, GetLang("窗口信息说明"))
    }

    OnClickAddVarValueBtn(state, ctrl, event) {
        cur := this.ui.Query("InfoText2")
        Symbol := cur == "" ? "" : "|"
        VarStr := "{" this.ui.Query("VariCon") "}"
        if (this.ui.Query("VariCon") == "") {
            MsgBox("请勿添加空字符变量", "", "Owner" this.Hwnd())
            return
        }
        if (InStr(cur, VarStr)) {
            MsgBox("请勿重复添加变量", "", "Owner" this.Hwnd())
            return
        }

        this.ui.Update("InfoText2", "Text", cur Symbol VarStr)
    }

    OnClose(*) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (this.HideAction != "") {
            action := this.HideAction
            action()
            this.HideAction := ""
        }
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._SyncTopBtn()
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (this.HideAction != "") {
            action := this.HideAction
            action()
            this.HideAction := ""
        }
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }
}
