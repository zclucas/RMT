#Requires AutoHotkey v2.0
#Include VarModifyGui.ahk

; 兼容外部对 .Gui.Hwnd / .Show / .Hide / .GetPos 的调用
class VarListenGuiFacade {
    __New(owner) {
        this._owner := owner
    }

    Hwnd {
        get => (IsObject(this._owner.ui) && this._owner.ui.HasProp("wpfHwnd")) ? this._owner.ui.wpfHwnd : 0
    }

    Show(opts := "") {
        this._owner._ShowExisting(opts)
    }

    Hide() {
        this._owner._HideWindow()
    }

    GetPos(&x := 0, &y := 0, &w := 0, &h := 0) {
        hwnd := this.Hwnd
        if (!hwnd) {
            x := 0, y := 0, w := 0, h := 0
            return
        }
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    }
}

class VarListenGui {
    static instances := Map()
    static _opening := false

    __new() {
        this.ui := 0
        this.Gui := ""
        this.closed := true
        this.ModifyGui := VarModifyGui()
        this._topOn := false
        this._applyingUI := false
        this._rowKeys := []          ; 当前列表顺序对应的 key（数组前缀 ε）
        this._btnStyle := ""
        this._lastClickTick := 0
        this._lastClickRow := 0
        this._initX := ""            ; 物理像素；建窗前写入，避免先居中再跳位
        this._initY := ""
    }

    ; x/y 为物理像素（与 ListenVarPos / 旧 AHK Gui 一致）；省略则居中
    ShowGui(x := "", y := "") {
        this._initX := (x != "" && IsNumber(x)) ? Integer(x) : ""
        this._initY := (y != "" && IsNumber(y)) ? Integer(y) : ""

        if (!this.closed && IsObject(this.ui) && XAMLHost.CanReuseWindow(this.ui.HasProp("wpfHwnd") ? this.ui.wpfHwnd : 0)) {
            opts := ""
            if (this._initX != "" && this._initY != "")
                opts := Format("x{} y{}", this._initX, this._initY)
            this._ShowExisting(opts)
            this._topOn := !!MainSoftData.VarListenTop
            this._ApplyTopMost()
            this.Refresh()
            return
        }

        XAMLHost.EnsureDaemonHealthy()
        if (VarListenGui._opening)
            return
        VarListenGui._opening := true
        this._topOn := !!MainSoftData.VarListenTop
        try {
            this._BuildAndShow()
        } finally {
            VarListenGui._opening := false
        }

        this._ApplyTopMost()
        IniWrite(true, IniFile, IniSection, "IsOpenListenVar")
        this.Refresh()
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("变量监视器")
        titleHeight := "30"
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        ; 配置/WinGetPos 为物理像素，XAML 宽高为 DIP
        winW := PhysToDip(Integer(MainSoftData.VarListenWidth))
        winH := PhysToDip(Integer(MainSoftData.VarListenHeight))
        minW := PhysToDip(400)
        minH := PhysToDip(420)
        if (winW < minW)
            winW := minW
        if (winH < minH)
            winH := minH

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto", "*")

        ; 标题栏
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; 置顶
        topRow := main.Add("StackPanel").Orientation("Horizontal").Grid_Row(1).Margin("14, 8, 14, 4")
        topRow.Add("CheckBox").Name("TopCon").Content(GetLang("窗口置顶"))
            .Foreground("{DynamicResource TextMain}").FontSize(13)

        ; 列表
        listBorder := main.Add("Border").Grid_Row(2).Margin("14, 4, 14, 12")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Background("{DynamicResource InputBg}").CornerRadius("3")
        listGrid := listBorder.Add("Grid")
        listGrid.Rows("Auto", "*")
        listGrid.IsSharedSizeScope("True")

        ; 表头：变量名/类型/值，列间插入 GridSplitter 以便拖动调整列宽
        header := listGrid.Add("Grid").Grid_Row(0).Height(28).Background("{DynamicResource TitleBarColor}")
        hColDefs := header.Add("Grid.ColumnDefinitions")
        hColDefs.Add("ColumnDefinition").Name("VarHeaderCol0").Width("120")
        hColDefs.Add("ColumnDefinition").Width("7")
        hColDefs.Add("ColumnDefinition").Name("VarHeaderCol1").Width("60")
        hColDefs.Add("ColumnDefinition").Width("7")
        hColDefs.Add("ColumnDefinition").Name("VarHeaderCol2").Width("*")
        header.Add("TextBlock").Text(GetLang("变量名")).Grid_Column(0)
            .Foreground("{DynamicResource TitleBarForeground}").FontSize(XAMLHost.TitleFontSize()).FontWeight("Bold")
            .VerticalAlignment("Center").Margin("8,0,0,0")
        header.Add("Border").Grid_Column(1).Width(1).HorizontalAlignment("Center")
            .Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
        header.Add("GridSplitter").Grid_Column(1).Width(7).HorizontalAlignment("Center").VerticalAlignment("Stretch")
            .Background("Transparent").Cursor("SizeWE").ResizeBehavior("PreviousAndNext")
        header.Add("TextBlock").Text(GetLang("类型")).Grid_Column(2)
            .Foreground("{DynamicResource TitleBarForeground}").FontSize(XAMLHost.TitleFontSize()).FontWeight("Bold")
            .VerticalAlignment("Center").HorizontalAlignment("Center")
        header.Add("Border").Grid_Column(3).Width(1).HorizontalAlignment("Center")
            .Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
        header.Add("GridSplitter").Grid_Column(3).Width(7).HorizontalAlignment("Center").VerticalAlignment("Stretch")
            .Background("Transparent").Cursor("SizeWE").ResizeBehavior("PreviousAndNext")
        header.Add("TextBlock").Text(GetLang("值")).Grid_Column(4)
            .Foreground("{DynamicResource TitleBarForeground}").FontSize(XAMLHost.TitleFontSize()).FontWeight("Bold")
            .VerticalAlignment("Center").Margin("8,0,0,0")

        ; 隐藏代理网格：把表头显式列宽桥接进 SharedSizeGroup，让行宽跟随表头拖拽（修复 GridSplitter 无法带动共享列宽的问题）
        dummy := listGrid.Add("Grid").Grid_Row(0).Height(0).IsHitTestVisible("False")
        dColDefs := dummy.Add("Grid.ColumnDefinitions")
        dColDefs.Add("ColumnDefinition").Width("{Binding ElementName=VarHeaderCol0, Path=Width}").SharedSizeGroup("VCol1")
        dColDefs.Add("ColumnDefinition").Width("{Binding ElementName=VarHeaderCol1, Path=Width}").SharedSizeGroup("VCol2")

        ; 列表改用 ListBox：自带选中高亮，点击反馈明显
        lb := listGrid.Add("ListBox").Grid_Row(1).Name("VarList")
            .Background("Transparent").BorderThickness("0")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
            .HorizontalContentAlignment("Stretch")
            .VirtualizingPanel_IsVirtualizing("False")
        lb.InjectResources('<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="{TemplateBinding Background}" SnapsToDevicePixels="True"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBg}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#400078D7"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' title '" ShowInTaskbar="True" Width="' winW '" Height="' winH '" MinWidth="' minW '" MinHeight="' minH '" Opacity="0"')
        ; 有保存坐标时建窗即定位，避免先 CenterScreen 再跳转闪烁
        if (this._initX != "" && this._initY != "") {
            this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"',
                Format('Left="{}" Top="{}" WindowStartupLocation="Manual"', PhysToDip(this._initX), PhysToDip(this._initY)))
        }
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%',
            '<CornerRadius x:Key="PanelRadius">8</CornerRadius><SolidColorBrush x:Key="ListAltBg" Color="#40000000" />')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("Window", "SizeChanged", ObjBindMethod(this, "OnWindowSize"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.Track("TopCon")
        this.ui.OnEvent("TopCon", "Checked", ObjBindMethod(this, "OnTogTop"))
        this.ui.OnEvent("TopCon", "Unchecked", ObjBindMethod(this, "OnTogTop"))

        this.Gui := VarListenGuiFacade(this)
        this._applyingUI := true
        try this.ui.Update("TopCon", "IsChecked", this._topOn ? "True" : "False")
        finally this._applyingUI := false
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            hIcon := LoadPicture("Images\Soft\rabit.ico", "Icon1", &ImageType := 1)
            if (hIcon)
                this.ui.Update("Window", "Icon", "HICON:" hIcon)
        }
        XamlWin.OnLoadTheme(this.ui)
        this._ApplyTopMost()
    }

    OnWindowClosing(state, ctrl, event) {
        this._OnClosed()
    }

    OnCloseClick(state := unset, ctrl := unset, event := unset) {
        if IsObject(this.ui)
            this.ui.Update("Window", "Close", "")
    }

    _OnClosed() {
        this.closed := true
        VarListenGui._opening := false
        this.ui := ""
        this.Gui := ""
        this._rowKeys := []
        if (MainSoftData.MacroEditGui != "" && MainSoftData.MacroEditGui.Gui != "") {
            try {
                style := WinGetStyle("ahk_id " MainSoftData.MacroEditGui.Gui.Hwnd)
                if (style & 0x10000000)
                    MainSoftData.MacroEditGui.ToolMenu.Uncheck(GetLang("变量监视"))
            }
        }
        IniWrite(false, IniFile, IniSection, "IsOpenListenVar")
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowSize(state := unset, ctrl := unset, event := unset) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        WinGetPos(, , &w, &h, "ahk_id " hwnd)
        if (w > 0 && h > 0) {
            MainSoftData.VarListenWidth := w
            MainSoftData.VarListenHeight := h
            IniWrite(w, IniFile, IniSection, "VarListenWidth")
            IniWrite(h, IniFile, IniSection, "VarListenHeight")
        }
    }

    OnTogTop(state := unset, ctrl := unset, event := unset) {
        if (this._applyingUI)
            return
        if (IsSet(event))
            this._topOn := (event == "Checked")
        else if (IsSet(state) && IsObject(state) && state.Has("TopCon"))
            this._topOn := (state["TopCon"] = "True" || state["TopCon"] = 1)
        this._ApplyTopMost()
        IniWrite(this._topOn, IniFile, IniSection, "VarListenTop")
        MainSoftData.VarListenTop := this._topOn
    }

    _ApplyTopMost() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("Window", "Topmost", this._topOn ? "True" : "False")
        hwnd := this.ui.HasProp("wpfHwnd") ? this.ui.wpfHwnd : 0
        if (hwnd)
            try WinSetAlwaysOnTop(this._topOn ? 1 : 0, "ahk_id " hwnd)
    }

    _ShowExisting(opts := "") {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        if (opts != "") {
            ; Show("x.. y..") 传入的是物理像素（与旧 AHK Gui / ListenVarPos 一致）
            if RegExMatch(opts, "i)x\s*(-?\d+)", &mx)
                try this.ui.Update("Window", "Left", String(PhysToDip(mx[1])))
            if RegExMatch(opts, "i)y\s*(-?\d+)", &my)
                try this.ui.Update("Window", "Top", String(PhysToDip(my[1])))
        }
        try WinShow("ahk_id " hwnd)
        try WinActivate("ahk_id " hwnd)
    }

    _HideWindow() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (hwnd)
            try WinHide("ahk_id " hwnd)
    }

    _IsVisible() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return false
        try {
            style := WinGetStyle("ahk_id " hwnd)
            return !!(style & 0x10000000)
        }
        return false
    }

    Refresh() {
        if (!IsObject(this.ui) || this.closed || !this._IsVisible())
            return

        ; 清理旧行事件
        toDel := []
        for key, _ in this.ui.events {
            if (InStr(key, "VarRow_") == 1)
                toDel.Push(key)
        }
        for key in toDel
            this.ui.events.Delete(key)

        this.ui.Update("VarList", "ClearItems", "")
        this._rowKeys := []

        for key, value in MySoftData.VariableMap {
            this._rowKeys.Push(key)
            this._AddRow(this._rowKeys.Length, key, GetLang("值"), String(value), false)
        }
        for key, value in MySoftData.ArrayMap {
            this._rowKeys.Push("ε" key)
            this._AddRow(this._rowKeys.Length, key, GetLang("数组"), GetArrayStr(value), true)
        }
    }

    _AddRow(rowId, name, typeText, valueText, isArray) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        rowName := "VarRow_" rowId
        ; 偶数行用主题 ListAltBg（标题色半透明），奇数行透明；背景放在 ListBoxItem 上便于选中高亮覆盖
        bg := (Mod(rowId, 2) == 0) ? "{DynamicResource ListAltBg}" : "Transparent"
        xaml := '<ListBoxItem ' ns ' Name="' rowName '" Background="' bg '" Cursor="Hand">'
            . '<Grid Height="28" Margin="0,0,0,1">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="0" SharedSizeGroup="VCol1"/>'
            . '<ColumnDefinition Width="7"/>'
            . '<ColumnDefinition Width="0" SharedSizeGroup="VCol2"/>'
            . '<ColumnDefinition Width="7"/>'
            . '<ColumnDefinition Width="*"/>'
            . '</Grid.ColumnDefinitions>'
            . '<TextBlock Grid.Column="0" Text="' this._XmlEsc(name) '" Foreground="{DynamicResource TextMain}"'
            . ' FontSize="12" VerticalAlignment="Center" Margin="8,0,4,0" TextTrimming="CharacterEllipsis"/>'
            . '<TextBlock Grid.Column="2" Text="' this._XmlEsc(typeText) '" Foreground="{DynamicResource TextSub}"'
            . ' FontSize="12" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . '<TextBlock Grid.Column="4" Text="' this._XmlEsc(valueText) '" Foreground="{DynamicResource TextMain}"'
            . ' FontSize="12" VerticalAlignment="Center" Margin="8,0,8,0" TextTrimming="CharacterEllipsis"/>'
            . '</Grid>'
            . '</ListBoxItem>'

        this.ui.Update("VarList", "AddXamlItem", xaml)
        ; 双击用间隔识别（原逻辑），ListBoxItem 原生支持选中高亮
        this.ui.OnEvent(rowName, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnRowClick", rowId))
        this.ui.Update(rowName, "BindEvent", "PreviewMouseLeftButtonDown")
    }

    OnRowClick(rowId, state := unset, ctrl := unset, event := unset) {
        if (A_TickCount - this._lastClickTick < 400 && this._lastClickRow == rowId) {
            this._lastClickTick := 0
            this._lastClickRow := 0
            this.OnRowDoubleClick(rowId)
            return
        }
        this._lastClickTick := A_TickCount
        this._lastClickRow := rowId
    }

    OnRowDoubleClick(rowId, state := unset, ctrl := unset, event := unset) {
        if (rowId < 1 || rowId > this._rowKeys.Length)
            return
        rawKey := this._rowKeys[rowId]
        isArray := (SubStr(rawKey, 1, 1) == "ε")
        varName := LTrim(rawKey, "ε")
        curValue := ""
        if (isArray && MySoftData.ArrayMap.Has(varName))
            curValue := GetArrayStr(MySoftData.ArrayMap[varName])
        else if (MySoftData.VariableMap.Has(varName))
            curValue := String(MySoftData.VariableMap[varName])

        SureAction := this.OnModifySureAction.Bind(this, isArray)
        this.ModifyGui.ParentHwnd := this.Gui.Hwnd
        this.ModifyGui.SureAction := SureAction
        this.ModifyGui.ShowGui(varName, curValue)
    }

    OnModifySureAction(isArray, Name, Value) {
        if (isArray) {
            if (Value == "")
                DeleteGlobalArray(Name)
            else
                SetGlobalArray(Name, GetArray(Value))
        }
        else {
            if (Value == "")
                DelGlobalVariable([Name])
            else
                SetGlobalVariable([Name], [Value], false)
        }
    }

    _XmlEsc(s) {
        s := StrReplace(String(s), "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }
}
