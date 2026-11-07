#Requires AutoHotkey v2.0

; =====================================================================
; 窗口绑定编辑器：互斥来源与按层级可用的父级引用
; ShowGui(winInfoCon, isFront, scope) / OwnerHwnd / HideAction / SureAction
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
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    static _OkBtnHoverStyle() {
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    ; 键盘按键格：Tag=1 选中 / Tag=0 未选中；hover 分别贴近选中色与未选中色
    static _KeyPickBtnStyle() {
        return '<Style TargetType="Button"><Setter Property="Tag" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="0"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></MultiTrigger>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="1"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></MultiTrigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ShowGui(winInfoCon, isFront := false, scope := "command") {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this.scope := isFront ? "module" : scope
        this.isFront := isFront
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(winInfoCon)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("窗口绑定编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto", "*")

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

        ; === 顶部行：F1 键帽 + 确定窗口信息 ===
        top := main.Add("StackPanel").Name("CapturePanel").Grid_Row(1).Orientation("Horizontal").Margin("10,6,10,0").VerticalAlignment("Center")
        box := FrontInfoGui._SnapBox()
        f1Cap := top.Add("Border").CornerRadius("3").BorderThickness("1.25").Padding("8,0")
            .Height(box).MinHeight(box)
            .BorderBrush("{DynamicResource ControlBorder}").Background("{DynamicResource ControlBg}")
            .VerticalAlignment("Center").SnapsToDevicePixels("True").UseLayoutRounding("True")
            .ToolTip(GetLang("按 F1 抓取当前鼠标下窗口信息"))
        f1Cap.Add("TextBlock").Text(FormatHotkeyDisplay("F1")).FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Foreground("{DynamicResource TextMain}")
        top.Add("TextBlock").Text(GetLang("确定窗口信息")).VerticalAlignment("Center").Margin("8,0,0,0")
        toolHover := FrontInfoGui._ToolBtnHoverStyle()
        okStyle := FrontInfoGui._OkBtnHoverStyle()

        ; === 主体 ===
        body := main.Add("Grid").Grid_Row(2).Margin("10,4,10,12")
        body.Cols("90", "*")
        body.Rows("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "*", "Auto")
        body.Add("TextBlock").Name("CurWinLabel").Text(GetLang("当前鼠标下窗口信息：")).Grid_Row(0).Grid_ColumnSpan(2).VerticalAlignment("Center")
        body.Add("TextBox").Name("CurWinInfoCon").Grid_Row(1).Grid_ColumnSpan(2).Height(97).Margin("0,2,0,4").IsReadOnly("True")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .AcceptsReturn("True").TextWrapping("NoWrap")
            .HorizontalScrollBarVisibility("Auto").VerticalScrollBarVisibility("Disabled")

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("绑定来源：")).VerticalAlignment("Center").Margin("0,8,0,8")
        source := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("SourceCombo").Width(240).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").Margin("0,8,0,8")
        ; 显示顺序固定：窗口信息、句柄、当前窗口、所有窗口、模块窗口绑定、宏设置窗口绑定。
        ; 宏设置不提供“当前窗口”，避免把一次性鼠标取窗误当成宏级绑定。
        this.sources := ["窗口信息", "句柄"]
        this.sourceModes := [2, 1]
        if (this.scope != "macro") {
            this.sources.Push("当前窗口")
            this.sourceModes.Push(0)
        }
        this.sources.Push("所有窗口")
        this.sourceModes.Push(3)
        if (this.scope != "module") {
            this.sources.Push("模块窗口绑定")
            this.sourceModes.Push(4)
        }
        if (this.scope == "command") {
            this.sources.Push("宏设置窗口绑定")
            this.sourceModes.Push(5)
        }
        for label in this.sources
            source.Add("ComboBoxItem").Content(GetLang(label))
        this._AddInfoRow(body, 3, 2, GetLang("句柄ID："))
        varRow := body.Add("StackPanel").Name("VarRow").Grid_Row(4).Grid_Column(1).Orientation("Horizontal")
            .HorizontalAlignment("Right").Margin("0,4,0,0")
        varRow.Add("TextBlock").Name("VariTipCon").Text(GetLang("变量:")).VerticalAlignment("Center")
        varRow.Add("ComboBox").Name("VariCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        addVarBtn := varRow.Add("Button").Name("BtnAddVar").Content(GetLang("追加变量值")).Width(110).Height(26).MinHeight(26).Padding("12,0").Margin("6,0,0,0").Cursor("Hand")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1.25")
            .Foreground("{DynamicResource TextMain}")
        addVarBtn.InjectResources(toolHover)
        this._AddInfoRow(body, 5, 3, GetLang("标题"))
        this._AddInfoRow(body, 6, 4, GetLang("窗口类"))
        this._AddInfoRow(body, 7, 5, GetLang("进程名"))
        body.Add("TextBlock").Name("SourceHint").Grid_Row(8).Grid_ColumnSpan(2).TextWrapping("Wrap")
            .Foreground("{DynamicResource TextMain}").Margin("0,10,0,4").MaxWidth(430).TextAlignment("Center")
        btnRow := body.Add("StackPanel").Grid_Row(9).Grid_ColumnSpan(2).Orientation("Horizontal")
            .HorizontalAlignment("Center").Margin("0,10,0,4")
        sureBtn := btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(80).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
        sureBtn.InjectResources(okStyle)
        cancelBtn := btnRow.Add("Button").Name("BtnCancel").Content(GetLang("取消")).Width(80).Height(32).MinHeight(32).Margin("10,0,0,0").Cursor("Hand")
            .Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        cancelBtn.InjectResources(toolHover)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="480" Height="400"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
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
        this.ui.OnEvent("BtnAddVar", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("SourceCombo", "SelectionChanged", ObjBindMethod(this, "OnSourceChange"))
        for i in [3, 4, 5] {
            name := "Tog" i
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnTogClick").Bind(i))
        }

    }

    _AddInfoRow(parent, row, idx, label) {
        labelCon := parent.Add(idx == 2 ? "TextBlock" : "CheckBox").Name("Tog" idx).Grid_Row(row).Grid_Column(0)
            .VerticalAlignment("Center").Margin("0,4,8,0")
        if (idx == 2)
            labelCon.Text(label)
        else
            labelCon.Content(label)
        box := parent.Add("Border").Name("InfoBorder" idx).Grid_Row(row).Grid_Column(1).Margin("0,4,0,0")
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
        value := winInfoCon.Value
        mode := this.scope == "module" ? 4 : (this.scope == "macro" ? 5 : 5)
        if (value == "" || value == "{所有窗口}")
            mode := 3
        fields := ["", "", ""]
        handle := ""
        if (value == "{模块窗口绑定}")
            mode := 4
        else if (value == "{宏设置窗口绑定}" || value == "{绑定窗口}" || value == GetLang("{绑定窗口}"))
            mode := 5
        else if (InStr(value, "❖") == 1) {
            handle := SubStr(value, 2)
            mode := (handle == "{句柄ID}" || handle == "{" GetLang("句柄ID") "}") ? 0 : 1
        } else if (value != "") {
            mode := 2
            parts := StrSplit(value, "⎖")
            if (parts.Length == 3)
                fields := parts
            else
                fields[1] := value
        }
        selected := 1
        for i, sourceMode in this.sourceModes {
            if (sourceMode == mode) {
                selected := i - 1
                break
            }
        }
        this.ui.Update("InfoText2", "Text", mode <= 1 ? handle : "")
        loop 3 {
            i := A_Index + 2
            this.ui.Update("InfoText" i, "Text", fields[A_Index])
            this.ui.Update("Tog" i, "IsChecked", fields[A_Index] != "" ? "True" : "False")
        }
        this.ui.Update("VariCon", "ClearItems", "")
        for value in GetGuiVarArr(4) {
            if (value != "")
                this.ui.Update("VariCon", "AddItem", value)
        }
        this.ui.Update("VariCon", "SelectedIndex", "0")
        this.ui.Update("SourceCombo", "SelectedIndex", String(selected))
        this.OnSourceChange()
    }

    SourceIndex() {
        value := this.ui.Query("SourceCombo>SelectedIndex")
        return IsNumber(value) ? Integer(value) : 2
    }

    SourceMode() {
        index := this.SourceIndex() + 1
        return (index <= this.sourceModes.Length) ? this.sourceModes[index] : 2
    }

    OnSourceChange(*) {
        mode := this.SourceMode()
        for i in [2, 3, 4, 5] {
            visible := (i == 2 ? mode == 1 : mode == 2) ? "Visible" : "Collapsed"
            this.ui.Update("Tog" i, "Visibility", visible)
            this.ui.Update("InfoBorder" i, "Visibility", visible)
        }
        this.ui.Update("VarRow", "Visibility", mode == 1 ? "Visible" : "Collapsed")
        hints := ["窗口信息中的标题、窗口类和进程名共同参与匹配。",
            "句柄支持多个 ID，用 | 分隔。",
            "运行时绑定鼠标所在的窗口。",
            "本模块不限制窗口。",
            "引用所属模块的窗口绑定。修改模块后自动生效；模块未绑定时没有可用目标。",
            "引用当前宏设置的窗口绑定，并跟随其对模块的继承。修改父级后自动生效。"]
        if (mode >= 0 && mode < hints.Length)
            this.ui.Update("SourceHint", "Text", GetLang(hints[mode + 1]))
        this.OnTogClick(3)
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
        catch {
            ; 窗口已关 / 目标窗口刚销毁都属正常情况，100ms 定时刷新不该抛错刷日志
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
        mode := this.SourceMode()
        if (mode == 1) {
            value := Trim(this.ui.Query("InfoText2"))
            if (value == "") {
                RmtDialog.Info(GetLang("句柄ID内容不能为空"), "", "Owner" this.Hwnd())
                return false
            }
            if (this.isFront && InStr(value, "{")) {
                RmtDialog.Info(GetLang("模块窗口绑定的句柄ID不能使用变量"), "", "Owner" this.Hwnd())
                return false
            }
        }
        if (mode == 2) {
            for i in [3, 4, 5] {
                if (this.ui.Query("Tog" i) == "True" && Trim(this.ui.Query("InfoText" i)) == "") {
                    RmtDialog.Info(GetLang("勾选的窗口信息不能为空"), "", "Owner" this.Hwnd())
                    return false
                }
            }
        }
        return true
    }

    GetInfoStr() {
        switch this.SourceMode() {
            case 0: return "❖{句柄ID}"
            case 1: return "❖" Trim(this.ui.Query("InfoText2"))
            case 3: return this.scope == "macro" ? "{所有窗口}" : ""
            case 4: return "{模块窗口绑定}"
            case 5: return "{宏设置窗口绑定}"
        }
        value := ""
        for i in [3, 4, 5] {
            value .= (i == 3 ? "" : "⎖") (this.ui.Query("Tog" i) == "True" ? this.ui.Query("InfoText" i) : "")
        }
        return value == "⎖⎖" ? "" : value
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
        for i in [3, 4, 5]
            this.ui.Update("InfoText" i, "IsEnabled", this.ui.Query("Tog" i) == "True" ? "True" : "False")
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

            mode := this.SourceMode()
            if (mode != 1 && mode != 2)
                return
            this.ui.Update("Tog3", "IsChecked", title != "" ? "True" : "False")
            this.ui.Update("Tog4", "IsChecked", className != "" ? "True" : "False")
            this.ui.Update("Tog5", "IsChecked", process != "" ? "True" : "False")

            this.ui.Update("InfoText2", "Text", winId)
            this.ui.Update("InfoText3", "Text", title)
            this.ui.Update("InfoText4", "Text", className)
            this.ui.Update("InfoText5", "Text", process)
            this.OnTogClick(3)
        }
    }

    OnClickAddVarValueBtn(state, ctrl, event) {
        cur := this.ui.Query("InfoText2")
        Symbol := cur == "" ? "" : "|"
        VarStr := "{" this.ui.Query("VariCon") "}"
        if (this.ui.Query("VariCon") == "") {
            RmtDialog.Info("请勿添加空字符变量", "", "Owner" this.Hwnd())
            return
        }
        if (InStr(cur, VarStr)) {
            RmtDialog.Info("请勿重复添加变量", "", "Owner" this.Hwnd())
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
