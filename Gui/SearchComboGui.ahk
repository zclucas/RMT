#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 搜索Combo编辑器 —— XAML 迁移版（原搜索Pro多目标）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; §15.1 多目标重构：左侧目标列表（ListBox + AddXamlItem 动态注入目标卡片，单选高亮），
;   每个目标独立配置 搜索类型/窗口信息/坐标/图片/颜色/文本/相似度；
;   右侧整体设置（搜索次数/间隔/满足个数/鼠标动作/结果保存/目标点保存/找到/未找到指令）。
; §19 合并决策：移除「屏幕规格」行（ConfigDLCon/ConfigArr 不再在 GUI 管理，旧配置字段保留无害）。
; 屏幕级功能（预览框/取色器/截图/鼠标跟踪/F1-F3热键）沿用原生全局函数，作用于当前选中目标。
; =====================================================================

class SearchComboGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this.PosAction := () => this.RefreshMouseInfo()
        this.F1Action := (x1, y1, x2, y2) => this.OnF1SetAreaAction(x1, y1, x2, y2)
        this.CheckClipboardAction := () => this.CheckClipboard()
        this.Data := ""
        this.LastIsWin := ""
        this.MacroGui := ""
        this.CurTarget := 1           ; 当前选中目标（工具行/预览/框选/取色作用于它）
        this.TargetList := []          ; 目标数组（= Data.SearchTargetArr 或旧配置构造）

        this.DLVariableArr := []
        this.ImageVariArr := []
        this.ColorArr := []
        this.TextArr := []
        this.SimilarArr := []
        this.WinInfoArr := []
        this.CountTogArr := ["SearchIntervalHost"]
        this.MouseSpeedArr := ["SpeedTipCon", "SpeedCon"]
        this.MouseClickArr := ["ClickCountCon"]
        this.ResultTogArr := ["ResultSaveNameCon", "TrueValueCon", "FalseValueCon"]
        this.CoordTogArr := ["CoordXNameCon", "CoordYNameCon"]

        this.PreviewBorderArr := []
        this.PreviewFollowTimer := 0
        this.PreviewFollowing := false
        this.PreviewShowing := false
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

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("搜索Combo编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "32", "*", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 顶部：与主体同列 —— 左：备注/屏幕坐标 + 窗口坐标；右：鼠标颜色（与窗口坐标同行） ===
        top := main.Add("Grid").Grid_Row(1).Margin("10,4,10,0")
        top.Cols("*", "8", "300")
        leftTop := top.Add("Grid").Grid_Column(0).Margin("10,0,8,0")
        leftTop.Cols("72", "4", "110", "12", "72", "8", "140", "8", "*")
        remarkPos := leftTop.Add("StackPanel").Grid_ColumnSpan(7).Orientation("Horizontal").HorizontalAlignment("Left").VerticalAlignment("Center")
        remarkPos.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkPos.Add("TextBox").Name("RemarkCon").Width(140).Height(26).MinHeight(26).Margin("8,0,0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        remarkPos.Add("TextBlock").Text(GetLang("屏幕坐标：")).VerticalAlignment("Center").Margin("16,0,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkPos.Add("TextBlock").Name("MousePosCon").Text("0,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        winG := leftTop.Add("StackPanel").Grid_Column(8).Orientation("Horizontal").HorizontalAlignment("Left").VerticalAlignment("Center")
        winG.Add("TextBlock").Text(GetLang("窗口坐标：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        winG.Add("TextBlock").Name("MouseWinPosCon").Text("0,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        clrG := top.Add("StackPanel").Grid_Column(2).Orientation("Horizontal").VerticalAlignment("Center")
        clrG.Add("TextBlock").Text(GetLang("鼠标颜色：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        clrG.Add("TextBlock").Name("MouseColorCon").Text("FFFFFF").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        clrG.Add("Border").Name("MouseColorTipCon").Width(16).Height(16).Background("#FF0000")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").VerticalAlignment("Center").Margin("6,0,0,0")

        ; === 主体两列 ===
        body := main.Add("Grid").Grid_Row(2).Margin("10,2,10,0")
        body.Cols("*", "300")
        body.InjectResources(this._ThemedScrollXaml())

        ; ---- 左列：目标列表（ListBox + 动态注入目标卡片） ----
        left := body.Add("Grid").Grid_Column(0).Margin("0,0,8,0")
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Background" Value="Transparent"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="0" SnapsToDevicePixels="True"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBg}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsSelected" Value="True"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/></MultiTrigger><Trigger Property="Tag" Value="add"><Setter TargetName="Bd" Property="Background" Value="Transparent"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        left.Add("ListBox").Name("TargetList")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .Padding("0,2,2,2")
            .VirtualizingPanel_IsVirtualizing("False")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled").ScrollViewer_VerticalScrollBarVisibility("Visible")
            .InjectResources(lbStyle)

        ; ---- 右列：整体设置（滚动） ----
        right := body.Add("ScrollViewer").Grid_Column(1)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        rightPanel := right.Add("StackPanel").Margin("0,0,0,0")

        ; 满足个数
        scRow := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,2,0,0")
        scRow.Add("TextBlock").Text(GetLang("满足个数：")).VerticalAlignment("Center")
        scRow.Add("ComboBox").Name("SatisfyCountCon").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 搜索次数 + 每次间隔（间隔叠 ms，与搜索Pro 相同）
        sr := rightPanel.Add("Grid").Margin("0,8,0,0")
        sr.Cols("Auto", "8", "*", "8", "*")
        sr.Add("TextBlock").Grid_Column(0).Text(GetLang("搜索次数：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        sr.Add("ComboBox").Grid_Column(2).Name("SearchCountCon").Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center")
            .IsEditable("True").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        intervalHost := sr.Add("Grid").Grid_Column(4).Name("SearchIntervalHost").ToolTip(GetLang("每次间隔"))
        intervalHost.Add("TextBox").Name("SearchIntervalCon").Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center")
            .Padding("2,0").TextAlignment("Center").FontSize("11")
            .ToolTip(GetLang("每次间隔"))
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        intervalHost.Add("TextBlock").Text("ms").FontSize("7").IsHitTestVisible("False")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,1,3,0")
            .Foreground("{DynamicResource TextSub}")

        ; 鼠标动作
        ma := rightPanel.Add("Grid").Margin("0,8,0,0")
        ma.Cols("Auto", "8", "*")
        ma.Add("TextBlock").Grid_Column(0).Text(GetLang("鼠标动作：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        mac := ma.Add("ComboBox").Grid_Column(2).Name("MouseActionTypeCon").Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for t in GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
            mac.Add("ComboBoxItem").Content(t)

        ms := rightPanel.Add("Grid").Margin("0,8,0,0")
        ms.Cols("Auto", "8", "*", "8", "*")
        ms.Add("TextBlock").Grid_Column(0).Name("SpeedTipCon").Text(GetLang("移动速度：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        ms.Add("TextBox").Grid_Column(2).Name("SpeedCon").Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center")
            .Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        ms.Add("TextBox").Grid_Column(4).Name("ClickCountCon").Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center")
            .Padding("2,0").TextAlignment("Center").FontSize("11")
            .ToolTip(GetLang("鼠标点击次数"))
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 找到 / 未找到（编辑按钮叠在输入框右上角）
        rightPanel.Add("TextBlock").Text(GetLang("找到后的指令：（可选）")).Margin("0,10,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        foundHost := rightPanel.Add("Grid").Margin("0,2,0,0")
        foundHost.Add("TextBox").Name("TrueMacroCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").Height(86).MinHeight(86)
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        foundHost.Add("Button").Name("BtnEditFoundMacro").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        rightPanel.Add("TextBlock").Name("FalseMacroTipCon").Text(GetLang("未找到后的指令：（可选）")).Margin("0,6,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        missHost := rightPanel.Add("Grid").Name("FalseMacroHost").Margin("0,2,0,0")
        missHost.Add("TextBox").Name("FalseMacroCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").Height(86).MinHeight(86)
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        missHost.Add("Button").Name("BtnEditUnFoundMacro").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 结果保存 / 目标点保存
        resCol := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0").VerticalAlignment("Center")
        resCol.Add("CheckBox").Name("ResultToggleCon").VerticalAlignment("Center").Margin("0,0,2,0")
            .ToolTip(GetLang("结果保存"))
        this._AddTipField(resCol, "ResultSaveNameCon", "ResultSaveNameTipHost", "ComboBox", 96, GetLang("变量名"), "0,0,6,0")
        this._AddTipField(resCol, "TrueValueCon", "TrueValueTipHost", "TextBox", 48, GetLang("真值"), "0,0,6,0")
        this._AddTipField(resCol, "FalseValueCon", "FalseValueTipHost", "TextBox", 48, GetLang("假值"), "")
        coordCol := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0").VerticalAlignment("Center")
        coordCol.Add("CheckBox").Name("CoordToogleCon").VerticalAlignment("Center").Margin("0,0,2,0")
            .ToolTip(GetLang("目标点保存"))
        this._AddTipField(coordCol, "CoordXNameCon", "CoordXTipHost", "ComboBox", 110, GetLang("坐标X变量名"), "0,0,6,0")
        this._AddTipField(coordCol, "CoordYNameCon", "CoordYTipHost", "ComboBox", 110, GetLang("坐标Y变量名"), "")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnSure", "4,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="920" Height="680" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/4-搜索Combo", (*) => this.TriggerMacro(), "!l"
            , "", (*) => this.OnF1()
            , (*) => this.OnScreenShotBtnClick(this._CurTarget()), (*) => this.SureColor())
        try this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：框选范围"))
        this.ui.OnEvent("TargetList", "SelectionChanged", ObjBindMethod(this, "OnTargetSelected"))
        this.ui.OnEvent("SatisfyCountCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("SearchCountCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("SearchIntervalCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("MouseActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("SpeedCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("ClickCountCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("ResultToggleCon", "Click", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("CoordToogleCon", "Click", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("BtnEditFoundMacro", "Click", ObjBindMethod(this, "OnEditFoundMacroBtnClick"))
        this.ui.OnEvent("BtnEditUnFoundMacro", "Click", ObjBindMethod(this, "OnEditUnFoundMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this._RefreshSaveTips()

    }

    _SaveTipText(name) {
        tips := Map("ResultSaveNameCon", GetLang("变量名"), "TrueValueCon", GetLang("真值"), "FalseValueCon", GetLang("假值")
            , "CoordXNameCon", GetLang("坐标X变量名"), "CoordYNameCon", GetLang("坐标Y变量名")
            , "ResultSaveNameTipHost", GetLang("变量名"), "TrueValueTipHost", GetLang("真值"), "FalseValueTipHost", GetLang("假值")
            , "CoordXTipHost", GetLang("坐标X变量名"), "CoordYTipHost", GetLang("坐标Y变量名"))
        return tips.Has(name) ? tips[name] : ""
    }

    _AddTipField(parent, name, hostName, kind, width, tip, margin) {
        wrap := parent.Add("Grid").Name(hostName).Width(width).Height(28).MinHeight(28)
            .VerticalAlignment("Center").Background("Transparent").ToolTip(tip)
        if (margin != "")
            wrap.Margin(margin)
        c := wrap.Add(kind).Name(name).Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        if (kind == "TextBox")
            c.Padding("2,0").TextAlignment("Center").ToolTip(tip)
        else
            c.IsEditable("True")
    }

    _RefreshSaveTips() {
        if (!IsObject(this.ui))
            return
        for cn in ["ResultSaveNameTipHost", "TrueValueTipHost", "FalseValueTipHost", "CoordXTipHost", "CoordYTipHost"
            , "ResultSaveNameCon", "TrueValueCon", "FalseValueCon", "CoordXNameCon", "CoordYNameCon"] {
            tip := this._SaveTipText(cn)
            if (tip != "")
                try this.ui.Update(cn, "ToolTip", tip)
        }
    }

    ; ---------------- 数据读写辅助 ----------------

    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    ; 目标控件名前缀
    _TN(n, base) {
        return "Tgt_" n "_" base
    }

    _ThemedScrollXaml() {
        thumb := '<ControlTemplate x:Key="RmtSbThumb" TargetType="Thumb">'
            . '<Border x:Name="bd" Background="{DynamicResource ControlBorder}" CornerRadius="3" Opacity="0.85" Margin="1"/>'
            . '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource Accent}"/>'
            . '<Setter TargetName="bd" Property="Opacity" Value="1"/>'
            . '</Trigger></ControlTemplate.Triggers></ControlTemplate>'
        sbV := '<Style x:Key="RmtSbVertical" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="0"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="true">'
            . '<Track.Thumb><Thumb Template="{StaticResource RmtSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
        sbH := '<Style x:Key="RmtSbHorizontal" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Height" Value="8"/><Setter Property="MinHeight" Value="0"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="false">'
            . '<Track.Thumb><Thumb Template="{StaticResource RmtSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
        sv := '<Style TargetType="ScrollViewer"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollViewer"><Grid>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            . '<Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
            . '<ScrollContentPresenter x:Name="PART_ScrollContentPresenter" Grid.Column="0" Grid.Row="0" Margin="{TemplateBinding Padding}" Content="{TemplateBinding Content}" ContentTemplate="{TemplateBinding ContentTemplate}" CanContentScroll="{TemplateBinding CanContentScroll}"/>'
            . '<ScrollBar x:Name="PART_VerticalScrollBar" Width="8" MinWidth="0" Grid.Column="1" Grid.Row="0" Value="{TemplateBinding VerticalOffset}" Maximum="{TemplateBinding ScrollableHeight}" ViewportSize="{TemplateBinding ViewportHeight}" Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}" Style="{StaticResource RmtSbVertical}"/>'
            . '<ScrollBar x:Name="PART_HorizontalScrollBar" Height="8" MinHeight="0" Orientation="Horizontal" Grid.Column="0" Grid.Row="1" Value="{TemplateBinding HorizontalOffset}" Maximum="{TemplateBinding ScrollableWidth}" ViewportSize="{TemplateBinding ViewportWidth}" Visibility="{TemplateBinding ComputedHorizontalScrollBarVisibility}" Style="{StaticResource RmtSbHorizontal}"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter></Style>'
        return thumb sbV sbH sv
    }

    _ThemeHoverBtnStyle() {
        return '<Button.Style><Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/>'
            . '<Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/>'
            . '</Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Button.Style>'
    }

    _AreaPreviewBtnStyle() {
        return '<Button.Style><Style TargetType="Button"><Setter Property="Tag" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="0"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></MultiTrigger>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="1"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></MultiTrigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Button.Style>'
    }

    _AreaComboXml(name, row, col) {
        return '<ComboBox Name="' name '" Grid.Row="' row '" Grid.Column="' col '" Width="110" Height="28" MinHeight="28"'
            . ' HorizontalAlignment="Left" VerticalAlignment="Center" VerticalContentAlignment="Center" FontSize="' XAMLHost.FontSize() '"'
            . ' IsEditable="True" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
    }

    _ToggleInt(v) {
        return (v == 1 || v == "1" || v == true || v == "True") ? 1 : 0
    }

    _SetImage(n, path) {
        if (IsObject(this.ui))
            this.ui.Update(this._TN(n, "Image"), "Source", StrReplace(path, "\", "/"))
    }

    SetConArrState(ConArr, isEnabled, state) {
        prop := isEnabled ? "IsEnabled" : "Visibility"
        val := isEnabled ? (state ? "True" : "False") : (state ? "Visible" : "Collapsed")
        for name in ConArr
            this.ui.Update(name, prop, val)
    }

    ; 动态注入控件的事件绑定（AddXamlItem 之后调用；清旧回调再挂，幂等）
    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.Update(name, "BindEvent", evt)
    }

    ; ---------------- 目标列表（§15.1 多目标） ----------------

    ; 兼容取目标数组：新配置用 SearchTargetArr；旧配置由顶层字段构造单目标
    _TargetListOf(Data) {
        if (ObjHasOwnProp(Data, "SearchTargetArr") && IsObject(Data.SearchTargetArr) && Data.SearchTargetArr.Length > 0)
            return Data.SearchTargetArr
        t := {
            SearchType: ObjHasOwnProp(Data, "SearchType") ? Data.SearchType : 1,
            WinInfo: ObjHasOwnProp(Data, "WinInfo") ? Data.WinInfo : "",
            SearchColor: ObjHasOwnProp(Data, "SearchColor") ? Data.SearchColor : "FFFFFF",
            SearchText: ObjHasOwnProp(Data, "SearchText") ? Data.SearchText : GetLang("检索文本"),
            SearchImagePath: ObjHasOwnProp(Data, "SearchImagePath") ? Data.SearchImagePath : "",
            Similar: ObjHasOwnProp(Data, "Similar") ? Data.Similar : 90,
            OCRType: ObjHasOwnProp(Data, "OCRType") ? Data.OCRType : 1,
            SearchImageType: ObjHasOwnProp(Data, "SearchImageType") ? Data.SearchImageType : SearchImageDefaultType(),
            Adaptive: ObjHasOwnProp(Data, "Adaptive") ? Data.Adaptive : 0,
            Remark: ObjHasOwnProp(Data, "Remark") ? Data.Remark : "",
            StartPosX: ObjHasOwnProp(Data, "StartPosX") ? Data.StartPosX : 0,
            StartPosY: ObjHasOwnProp(Data, "StartPosY") ? Data.StartPosY : 0,
            EndPosX: ObjHasOwnProp(Data, "EndPosX") ? Data.EndPosX : A_ScreenWidth,
            EndPosY: ObjHasOwnProp(Data, "EndPosY") ? Data.EndPosY : A_ScreenHeight
        }
        return [t]
    }

    ; 目标卡片 XAML（固定行高，各搜索类型卡片等高；删除按钮叠在右上角）
    _TargetCardXml(n, t) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        typeItems := ""
        for tt in GetLangArr(["屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"])
            typeItems .= '<ComboBoxItem Content="' tt '"/>'
        modelItems := '<ComboBoxItem Content="OpenCV"/><ComboBoxItem Content="' GetLang("RMT识图") '"/>'
        delIcon := Chr(0xE74D)

        lastN := this.TargetList.Length
        fs := XAMLHost.FontSize()
        xaml := '<ListBoxItem ' ns ' Tag="' n '">'
            . '<Border Margin="0,1,0,1" Padding="8,6,8,6" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" CornerRadius="4" Background="Transparent">'
            . '<Grid>'
            . '<Grid>'
            . '<Grid.RowDefinitions>'
            . '<RowDefinition Height="28"/>'
            . '<RowDefinition Height="32"/>'
            . '<RowDefinition Height="64"/>'
            . '<RowDefinition Height="32"/>'
            . '</Grid.RowDefinitions>'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="72"/>'
            . '<ColumnDefinition Width="4"/>'
            . '<ColumnDefinition Width="*"/>'
            . '<ColumnDefinition Width="8"/>'
            . '<ColumnDefinition Width="64" MinWidth="64"/>'
            . '</Grid.ColumnDefinitions>'
            . '<Grid Grid.Row="0" Grid.ColumnSpan="5" Margin="0,0,78,0">'
            . '<TextBlock Text="' n '." FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">'
            . '<TextBlock Text="' GetLang("备注：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<TextBox Name="' this._TN(n, "Remark") '" Width="140" Height="24" MinHeight="24" Margin="4,0,0,0" VerticalAlignment="Center" VerticalContentAlignment="Center" Padding="4,0" FontSize="' fs '"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
            . '</Grid>'
            . '<TextBlock Grid.Row="1" Grid.Column="0" Text="' GetLang("搜索类型：") '" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<Grid Grid.Row="1" Grid.Column="2">'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="12"/><ColumnDefinition Width="72"/><ColumnDefinition Width="8"/><ColumnDefinition Width="140"/><ColumnDefinition Width="8"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>'
            . '<ComboBox Name="' this._TN(n, "Type") '" Grid.Column="0" Width="110" Height="28" MinHeight="28" VerticalAlignment="Center" VerticalContentAlignment="Center" FontSize="' fs '">' typeItems '</ComboBox>'
            . '<Grid Name="' this._TN(n, "WinInfoRow") '" Grid.Column="2" Grid.ColumnSpan="5" VerticalAlignment="Center">'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="72"/><ColumnDefinition Width="8"/><ColumnDefinition Width="140"/><ColumnDefinition Width="8"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>'
            . '<TextBlock Grid.Column="0" Text="' GetLang("窗口信息:") '" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<TextBox Name="' this._TN(n, "WinInfo") '" Grid.Column="2" Width="140" Height="28" MinHeight="28" FontSize="' fs '"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" VerticalContentAlignment="Center" Padding="4,0"/>'
            . '<Button Name="' this._TN(n, "WinInfoEditBtn") '" Grid.Column="4" Width="28" Height="28" MinHeight="28" Padding="0" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' fs '" Content="' Chr(0xE70F) '"'
            . ' ToolTip="' GetLang("编辑") '" Foreground="{DynamicResource TextMain}"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . this._ThemeHoverBtnStyle()
            . '</Button>'
            . '</Grid>'
            . '</Grid>'
            . '<Button Name="' this._TN(n, "PreviewBtn") '" Grid.Row="2" Grid.Column="0"'
            . ' HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Cursor="Hand" Focusable="False"'
            . ' Margin="-6,0,0,0" Padding="6,0,0,0" Tag="0" ToolTip="' GetLang("搜索范围") '"'
            . ' HorizontalContentAlignment="Left" VerticalContentAlignment="Stretch"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . this._AreaPreviewBtnStyle()
            . '<Grid HorizontalAlignment="Stretch" VerticalAlignment="Stretch">'
            . '<Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="32"/></Grid.RowDefinitions>'
            . '<TextBlock Grid.Row="0" Text="' GetLang("起始坐标：") '" VerticalAlignment="Center" HorizontalAlignment="Left"'
            . ' Foreground="{DynamicResource TextMain}" FontSize="' fs '" IsHitTestVisible="False"/>'
            . '<TextBlock Grid.Row="1" Text="' GetLang("终止坐标：") '" VerticalAlignment="Center" HorizontalAlignment="Left"'
            . ' Foreground="{DynamicResource TextMain}" FontSize="' fs '" IsHitTestVisible="False"/>'
            . '</Grid></Button>'
            . '<Grid Grid.Row="2" Grid.Column="2" HorizontalAlignment="Stretch" ClipToBounds="False">'
            . '<Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="32"/></Grid.RowDefinitions>'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="110"/><ColumnDefinition Width="8"/><ColumnDefinition Width="110"/>'
            . '<ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="6"/><ColumnDefinition Width="*" MinWidth="80"/>'
            . '</Grid.ColumnDefinitions>'
            . this._AreaComboXml(this._TN(n, "StartPosX"), 0, 0)
            . this._AreaComboXml(this._TN(n, "StartPosY"), 0, 2)
            . this._AreaComboXml(this._TN(n, "EndPosX"), 1, 0)
            . this._AreaComboXml(this._TN(n, "EndPosY"), 1, 2)
            . '<TextBlock Name="' this._TN(n, "SimilarRow") '" Grid.Row="0" Grid.Column="4" Text="' GetLang("相似度(%)：") '"'
            . ' VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<TextBox Name="' this._TN(n, "Similar") '" Grid.Row="0" Grid.Column="6" Height="28" MinHeight="28" MinWidth="80"'
            . ' HorizontalAlignment="Stretch" VerticalContentAlignment="Center" Padding="2,0" TextAlignment="Center" FontSize="' fs '"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '<TextBlock Name="' this._TN(n, "ImageTypeTip") '" Grid.Row="1" Grid.Column="4" Text="' GetLang("识别模型：") '"'
            . ' VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<ComboBox Name="' this._TN(n, "ImageType") '" Grid.Row="1" Grid.Column="6" Height="28" MinHeight="28" MinWidth="80"'
            . ' HorizontalAlignment="Stretch" VerticalAlignment="Center" VerticalContentAlignment="Center" FontSize="' fs '">' modelItems '</ComboBox>'
            . '</Grid>'
            . '<Border Name="' this._TN(n, "ImagePreviewHost") '" Grid.Row="2" Grid.Column="4" Width="64" Height="64" MinWidth="64" MinHeight="64" MaxWidth="64" MaxHeight="64"'
            . ' HorizontalAlignment="Left" VerticalAlignment="Center" ClipToBounds="True"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . '<Image Name="' this._TN(n, "Image") '" Stretch="Uniform" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>'
            . '</Border>'
            . '<Button Name="' this._TN(n, "AdaptiveBtn") '" Grid.Row="3" Grid.Column="4" Width="64" Height="28" MinHeight="28"'
            . ' Padding="0" VerticalAlignment="Center" HorizontalAlignment="Stretch" Cursor="Hand" FontSize="' fs '"'
            . ' Content="' GetLang("自适应") '" Tag="0"'
            . ' ToolTip="' GetLang("自适应匹配：分辨率或缩放比例变了也能找到") '"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . this._ThemeHoverBtnStyle()
            . '</Button>'
            . '<TextBlock Name="' this._TN(n, "ImagePathTip") '" Grid.Row="3" Grid.Column="0" Text="' GetLang("图片路径：") '" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<Grid Name="' this._TN(n, "ImagePathRow") '" Grid.Row="3" Grid.Column="2" Width="228" HorizontalAlignment="Left">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="28"/><ColumnDefinition Width="8"/><ColumnDefinition Width="28"/>'
            . '</Grid.ColumnDefinitions>'
            . '<ComboBox Name="' this._TN(n, "ImagePath") '" Grid.Column="0" Height="28" MinHeight="28" VerticalAlignment="Center" HorizontalAlignment="Stretch" IsEditable="True" FontSize="' fs '"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '<Button Name="' this._TN(n, "ScreenshotBtn") '" Grid.Column="2" Width="28" Height="28" MinHeight="28" Padding="0" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' fs '" Content="' Chr(0xE7A8) '"'
            . ' ToolTip="' GetLang("截图") '" Foreground="{DynamicResource TextMain}"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '<Button Name="' this._TN(n, "ImageSelectBtn") '" Grid.Column="4" Width="28" Height="28" MinHeight="28" Padding="0" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' fs '" Content="' Chr(0xE8E5) '"'
            . ' ToolTip="' GetLang("选择图片") '" Foreground="{DynamicResource TextMain}"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '</Grid>'
            . '<TextBlock Name="' this._TN(n, "ColorTipLabel") '" Grid.Row="3" Grid.Column="0" Text="' GetLang("搜索颜色：") '" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<Grid Name="' this._TN(n, "ColorRow") '" Grid.Row="3" Grid.Column="2" Width="228" HorizontalAlignment="Left">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="20"/>'
            . '</Grid.ColumnDefinitions>'
            . '<ComboBox Name="' this._TN(n, "Color") '" Grid.Column="0" Height="28" MinHeight="28" HorizontalAlignment="Stretch" VerticalAlignment="Center" VerticalContentAlignment="Center" FontSize="' fs '" IsEditable="True"/>'
            . '<Border Name="' this._TN(n, "ColorTip") '" Grid.Column="2" Width="20" Height="20" Background="#FF0000" VerticalAlignment="Center"/>'
            . '</Grid>'
            . '<TextBlock Name="' this._TN(n, "TextTipLabel") '" Grid.Row="3" Grid.Column="0" Text="' GetLang("搜索文本：") '" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource TextMain}" FontSize="' fs '"/>'
            . '<Grid Name="' this._TN(n, "TextRow") '" Grid.Row="3" Grid.Column="2" Width="228" HorizontalAlignment="Left">'
            . '<ComboBox Name="' this._TN(n, "Text") '" Height="28" MinHeight="28" HorizontalAlignment="Stretch" VerticalAlignment="Center" VerticalContentAlignment="Center" FontSize="' fs '" IsEditable="True"/>'
            . '</Grid>'
            . '</Grid>'
            . '<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,1,0">'
        if (n > 1)
            xaml .= this._OverlayIconBtnXml(this._TN(n, "UpBtn"), Chr(0xE74A), GetLang("上移"), "0,0,4,0")
        if (n < lastN)
            xaml .= this._OverlayIconBtnXml(this._TN(n, "DownBtn"), Chr(0xE74B), GetLang("下移"), "0,0,4,0")
        xaml .= this._OverlayIconBtnXml(this._TN(n, "DelBtn"), delIcon, GetLang("删除目标"), "0")
            . '</StackPanel>'
            . '</Grid></Border></ListBoxItem>'
        return xaml
    }

    _OverlayIconBtnXml(name, icon, tip, margin) {
        return '<Button Name="' name '" Width="22" Height="22" MinHeight="22" Padding="0" Margin="' margin '" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' XAMLHost.FontSize() '" Content="' icon '"'
            . ' ToolTip="' tip '" Foreground="{DynamicResource TextMain}" UseLayoutRounding="True" SnapsToDevicePixels="True"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . '<Button.Style><Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"'
            . ' BorderThickness="1" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/>'
            . '<Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/>'
            . '</Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Button.Style>'
            . '</Button>'
    }

    _AddTargetItemXml() {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        addIcon := Chr(0xE710)
        return '<ListBoxItem ' ns ' Tag="add" Focusable="False">'
            . '<Button Name="BtnAddTarget" Width="28" Height="28" MinHeight="28" Margin="0,6,0,8"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center" Cursor="Hand" Padding="0"'
            . ' ToolTip="' GetLang("添加") '"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' XAMLHost.FontSize() '" Content="' addIcon '"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . this._ThemeHoverBtnStyle()
            . '</Button>'
            . '</ListBoxItem>'
    }

    ; 重建目标列表：ClearItems + 注入全部卡片 + 绑定事件 + 填值
    _RebuildTargetList() {
        if (!IsObject(this.ui))
            return
        batch := []
        batch.Push({ControlName: "TargetList", PropertyName: "ClearItems", Value: ""})
        loop this.TargetList.Length
            batch.Push({ControlName: "TargetList", PropertyName: "AddXamlItem", Value: this._TargetCardXml(A_Index, this.TargetList[A_Index])})
        batch.Push({ControlName: "TargetList", PropertyName: "AddXamlItem", Value: this._AddTargetItemXml()})
        this.ui.BatchUpdate(batch)
        loop this.TargetList.Length
            this._BindTargetCard(A_Index)
        this._Bind("BtnAddTarget", "Click", ObjBindMethod(this, "OnAddTarget"))
        loop this.TargetList.Length
            this._FillTargetCard(A_Index)
        this.ui.Update("TargetList", "SelectedIndex", String(this.CurTarget - 1))
        this._ApplyAreaPreviewChrome()
    }

    _BindTargetCard(n) {
        this._Bind(this._TN(n, "Type"), "SelectionChanged", ObjBindMethod(this, "OnTargetTypeChanged", n))
        ; 识别模型切换时刷新「自适应」按钮的显隐
        this._Bind(this._TN(n, "ImageType"), "SelectionChanged", ObjBindMethod(this, "OnTargetTypeChanged", n))
        this._Bind(this._TN(n, "DelBtn"), "Click", ObjBindMethod(this, "OnDelTarget", n))
        if (n > 1)
            this._Bind(this._TN(n, "UpBtn"), "Click", ObjBindMethod(this, "OnMoveTarget", n, -1))
        if (n < this.TargetList.Length)
            this._Bind(this._TN(n, "DownBtn"), "Click", ObjBindMethod(this, "OnMoveTarget", n, 1))
        this._Bind(this._TN(n, "WinInfoEditBtn"), "Click", ObjBindMethod(this, "OnClickWinEditBtn", n))
        this._Bind(this._TN(n, "PreviewBtn"), "Click", ObjBindMethod(this, "OnClickPreviewArea", n))
        this._Bind(this._TN(n, "StartPosX"), "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "StartPosY"), "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "EndPosX"), "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "EndPosY"), "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "ScreenshotBtn"), "Click", ObjBindMethod(this, "OnScreenShotBtnClick", n))
        this._Bind(this._TN(n, "ImageSelectBtn"), "Click", ObjBindMethod(this, "OnClickSetPicBtn", n))
        this._Bind(this._TN(n, "AdaptiveBtn"), "Click", ObjBindMethod(this, "OnToggleAdaptive", n))
    }

    ; 自适应匹配开关：只在图片类搜索上显示；关掉时行为与老版本完全一致
    OnToggleAdaptive(n, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || n > this.TargetList.Length)
            return
        cur := ObjHasOwnProp(this.TargetList[n], "Adaptive") ? this.TargetList[n].Adaptive : 0
        on := (cur == 1 || cur == "1" || cur == true)
        this.TargetList[n].Adaptive := on ? 0 : 1
        this._SyncAdaptiveBtn(n, !on)
    }

    _SyncAdaptiveBtn(n, on) {
        if (!IsObject(this.ui))
            return
        btn := this._TN(n, "AdaptiveBtn")
        on := (on == true || on == 1 || on == "1" || on == "true")
        try this.ui.Update(btn, "Tag", on ? "1" : "0")
        if (on) {
            try this.ui.Update(btn, "Background", "{DynamicResource ActionBg}")
            try this.ui.Update(btn, "BorderBrush", "{DynamicResource ActionStroke}")
            try this.ui.Update(btn, "Foreground", "{DynamicResource ActionText}")
        } else {
            try this.ui.Update(btn, "Background", "{DynamicResource ControlBg}")
            try this.ui.Update(btn, "BorderBrush", "{DynamicResource ControlBorder}")
            try this.ui.Update(btn, "Foreground", "{DynamicResource TextMain}")
        }
    }

    _FillTargetCard(n) {
        if (!IsObject(this.ui) || n > this.TargetList.Length)
            return
        t := this.TargetList[n]
        this.ui.Update(this._TN(n, "Type"), "SelectedIndex", String(Integer(t.SearchType ? t.SearchType : 1) - 1))
        this.ui.Update(this._TN(n, "Remark"), "Text", ObjHasOwnProp(t, "Remark") ? t.Remark : "")
        this.ui.Update(this._TN(n, "WinInfo"), "Text", t.WinInfo)
        this._SetCombo(this._TN(n, "StartPosX"), this.DLVariableArr, t.StartPosX)
        this._SetCombo(this._TN(n, "StartPosY"), this.DLVariableArr, t.StartPosY)
        this._SetCombo(this._TN(n, "EndPosX"), this.DLVariableArr, t.EndPosX)
        this._SetCombo(this._TN(n, "EndPosY"), this.DLVariableArr, t.EndPosY)
        this.ui.Update(this._TN(n, "ImageType"), "SelectedIndex", String((t.SearchImageType ? t.SearchImageType : 1) - 1))
        this._SyncAdaptiveBtn(n, ObjHasOwnProp(t, "Adaptive") ? t.Adaptive : 0)
        this._SetImage(n, t.SearchImagePath)
        this._SetCombo(this._TN(n, "ImagePath"), this.DLVariableArr, t.SearchImagePath)
        this._SetCombo(this._TN(n, "Color"), this.DLVariableArr, t.SearchColor)
        this.ui.Update(this._TN(n, "ColorTip"), "Visibility", RegExMatch(t.SearchColor, "^([0-9A-Fa-f]{6})$") ? "Visible" : "Collapsed")
        if (RegExMatch(t.SearchColor, "^([0-9A-Fa-f]{6})$"))
            this.ui.Update(this._TN(n, "ColorTip"), "Background", "#" t.SearchColor)
        this._SetCombo(this._TN(n, "Text"), this.DLVariableArr, t.SearchText)
        this.ui.Update(this._TN(n, "Similar"), "Text", t.Similar)
        this.OnTargetTypeChanged(n)
    }

    ; 当前选中目标
    _CurTarget() {
        if (this.CurTarget < 1 || this.CurTarget > this.TargetList.Length)
            this.CurTarget := 1
        return this.CurTarget
    }

    OnTargetSelected(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        idx := this.ui.Query("TargetList>SelectedIndex")
        if (!IsNumber(idx) || Integer(idx) < 0)
            return
        idx := Integer(idx)
        if (idx >= this.TargetList.Length) {
            this.ui.Update("TargetList", "SelectedIndex", String(this._CurTarget() - 1))
            return
        }
        this.CurTarget := idx + 1
        this._ApplyAreaPreviewChrome()
        this.RefreshPreviewArea()
    }

    OnAddTarget(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this.SaveSearchData()
        ; SaveSearchData 重建了 Data.SearchTargetArr，重绑 TargetList 到新数组（元素值来自 UI 最新输入）
        this.TargetList := this.Data.SearchTargetArr
        last := this.TargetList[this.TargetList.Length]
        t := {
            SearchType: last.SearchType,
            WinInfo: last.WinInfo,
            SearchColor: last.SearchColor,
            SearchText: last.SearchText,
            SearchImagePath: last.SearchImagePath,
            Similar: last.Similar,
            OCRType: last.OCRType,
            SearchImageType: last.SearchImageType,
            Adaptive: ObjHasOwnProp(last, "Adaptive") ? last.Adaptive : 0,
            Remark: ObjHasOwnProp(last, "Remark") ? last.Remark : "",
            StartPosX: last.StartPosX, StartPosY: last.StartPosY,
            EndPosX: last.EndPosX, EndPosY: last.EndPosY
        }
        this.TargetList.Push(t)
        this.CurTarget := this.TargetList.Length
        this._RebuildTargetList()
    }

    OnDelTarget(n, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        if (this.TargetList.Length <= 1) {
            MsgBox(GetLang("至少保留一个搜索目标"))
            return
        }
        this.SaveSearchData()
        this.TargetList := this.Data.SearchTargetArr
        this.TargetList.RemoveAt(n)
        if (this.CurTarget > this.TargetList.Length)
            this.CurTarget := this.TargetList.Length
        this._RebuildTargetList()
    }

    OnMoveTarget(n, dir, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        newIdx := n + dir
        if (newIdx < 1 || newIdx > this.TargetList.Length)
            return
        this.SaveSearchData()
        this.TargetList := this.Data.SearchTargetArr
        tmp := this.TargetList[n]
        this.TargetList[n] := this.TargetList[newIdx]
        this.TargetList[newIdx] := tmp
        this.CurTarget := newIdx
        this._RebuildTargetList()
    }

    ; 单目标类型切换：显隐该卡片区域
    OnTargetTypeChanged(n, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || n > this.TargetList.Length)
            return
        curType := this._TargetType(n)
        isImage := curType == 1 || curType == 4
        isColor := curType == 2 || curType == 5
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6
        tn := this._TN(n, "")
        this.ui.Update(tn "WinInfoRow", "Visibility", isWin ? "Visible" : "Hidden")
        this.ui.Update(tn "ImagePathTip", "Visibility", isImage ? "Visible" : "Hidden")
        this.ui.Update(tn "ImagePathRow", "Visibility", isImage ? "Visible" : "Hidden")
        this.ui.Update(tn "ImageTypeTip", "Visibility", isImage ? "Visible" : "Hidden")
        this.ui.Update(tn "ImageType", "Visibility", isImage ? "Visible" : "Hidden")
        this.ui.Update(tn "ImagePreviewHost", "Visibility", isImage ? "Visible" : "Hidden")
        ; 自适应只对 OpenCV 识别有效，RMT识图 那条路没有缩放能力
        modelIdx := this.ui.Query(tn "ImageType>SelectedIndex")
        isOcv := isImage && (!IsNumber(modelIdx) || Integer(modelIdx) <= 0)
        this.ui.Update(tn "AdaptiveBtn", "Visibility", isOcv ? "Visible" : "Hidden")
        this.ui.Update(tn "ColorTipLabel", "Visibility", isColor ? "Visible" : "Hidden")
        this.ui.Update(tn "ColorRow", "Visibility", isColor ? "Visible" : "Hidden")
        this.ui.Update(tn "TextTipLabel", "Visibility", isText ? "Visible" : "Hidden")
        this.ui.Update(tn "TextRow", "Visibility", isText ? "Visible" : "Hidden")
        this.ui.Update(tn "SimilarRow", "Visibility", isText ? "Hidden" : "Visible")
        this.ui.Update(tn "Similar", "Visibility", isText ? "Hidden" : "Visible")
        if (n == this.CurTarget)
            this.RefreshPreviewArea()
    }

    _TargetType(n) {
        if (!IsObject(this.ui))
            return 1
        v := this.ui.Query(this._TN(n, "Type") ">SelectedIndex")
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return Integer(v) + 1
    }

    ; 目标行控件名（当前目标）
    _CT(base) {
        return this._TN(this._CurTarget(), base)
    }

    ; ---------------- 整体设置（右侧） ----------------

    OnOverallChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        ; 满足个数下拉：程序化 _SetCombo 也会触发 TextChanged，用值守卫
        ; 搜索次数无限时隐藏「未找到后的指令」
        isInfinite := this.ui.Query("SearchCountCon") == GetLang("无限")
        this.SetConArrState(this.FalseConArr2(), false, !isInfinite)

        CountValue := this.ui.Query("SearchCountCon") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCon")
        isCount := IsNumber(CountValue) && (CountValue == -1 || CountValue > 1)
        this.SetConArrState(this.CountTogArr, false, isCount)

        mouseAction := this.ui.Query("MouseActionTypeCon>SelectedIndex")
        isMouseSpeed := IsNumber(mouseAction) && mouseAction + 1 != 1
        this.SetConArrState(this.MouseSpeedArr, false, isMouseSpeed)
        isMouseClick := IsNumber(mouseAction) && mouseAction + 1 == 3
        this.SetConArrState(this.MouseClickArr, false, isMouseClick)

        isSaveResult := this.ui.Query("ResultToggleCon") == "True"
        this.SetConArrState(this.ResultTogArr, true, isSaveResult)

        isCoord := this.ui.Query("CoordToogleCon") == "True"
        this.SetConArrState(this.CoordTogArr, true, isCoord)
        this._RefreshSaveTips()
    }

    FalseConArr2() {
        if (!ObjHasOwnProp(this, "_FalseConArr")) {
            this._FalseConArr := ["FalseMacroTipCon", "FalseMacroHost"]
        }
        return this._FalseConArr
    }

    ; ---------------- 数据 ----------------

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    OnClickWinEditBtn(n, *) {
        this.CurTarget := n
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, this._TN(n, "WinInfo")))
    }

    CheckIfDataValid() {
        if (this.TargetList.Length == 0) {
            MsgBox(GetLang("这条指令不完整，请删除"))
            return false
        }
        return true
    }

    CheckIfValid() {
        ; 校验每个目标
        loop this.TargetList.Length {
            n := A_Index
            curType := this._TargetType(n)
            isImage := curType == 1 || curType == 4
            isText := curType == 3 || curType == 6
            isWin := curType == 4 || curType == 5 || curType == 6
            tn := this._TN(n, "")

            if (IsNumber(this.ui.Query(tn "StartPosX")) && IsNumber(this.ui.Query(tn "StartPosY")) && IsNumber(this.ui.Query(tn "EndPosX"))
            && IsNumber(this.ui.Query(tn "EndPosY"))) {
                if (Number(this.ui.Query(tn "StartPosX")) > Number(this.ui.Query(tn "EndPosX")) || Number(this.ui.Query(tn "StartPosY")) >
                Number(this.ui.Query(tn "EndPosY"))) {
                    MsgBox(Format(GetLang("目标{}：起始坐标不能大于终止坐标"), n))
                    return false
                }
            }

            if (isImage && this.ui.Query(tn "ImagePath") == "") {
                MsgBox(Format(GetLang("目标{}：请设置搜索图片"), n))
                return false
            }

            if (isImage) {
                imgPath := this.ui.Query(tn "ImagePath")
                if (IsNumber(this.ui.Query(tn "StartPosX")) && IsNumber(this.ui.Query(tn "StartPosY"))
                && IsNumber(this.ui.Query(tn "EndPosX")) && IsNumber(this.ui.Query(tn "EndPosY"))
                && imgPath != "" && FileExist(imgPath)) {
                    searchWidth := this.ui.Query(tn "EndPosX") - this.ui.Query(tn "StartPosX")
                    searchHeight := this.ui.Query(tn "EndPosY") - this.ui.Query(tn "StartPosY")
                    size := GetImageSize(imgPath)
                    if (size[1] > searchWidth || size[2] > searchHeight) {
                        MsgBox(Format(GetLang("目标{}：搜索范围不能小于图片大小"), n))
                        return false
                    }
                }
            }

            if (isText) {
                if (IsNumber(this.ui.Query(tn "StartPosX")) && IsNumber(this.ui.Query(tn "StartPosY"))
                && IsNumber(this.ui.Query(tn "EndPosX")) && IsNumber(this.ui.Query(tn "EndPosY"))) {
                    if (this.ui.Query(tn "StartPosX") == this.ui.Query(tn "EndPosX") ||
                    this.ui.Query(tn "StartPosY") == this.ui.Query(tn "EndPosY")) {
                        MsgBox(Format(GetLang("目标{}：搜索文本时搜索范围中起始坐标不能和终止坐标相同"), n))
                        return false
                    }
                }
            }

            if (isWin && this.ui.Query(tn "WinInfo") == "") {
                MsgBox(Format(GetLang("目标{}：目标窗口信息不能为空"), n))
                return false
            }
        }

        if (this.ui.Query("SearchCountCon") == GetLang("无限")) {

        }
        else if (!IsNumber(this.ui.Query("SearchCountCon")) || Number(this.ui.Query("SearchCountCon")) <= 0) {
            MsgBox(GetLang("搜索次数请输入大于0的数字"))
            return false
        }

        ; 满足个数校验
        if (this.ui.Query("SatisfyCountCon") != GetLang("所有")) {
            sv := this.ui.Query("SatisfyCountCon")
            if (!IsNumber(sv) || Number(sv) < 1) {
                MsgBox(GetLang("满足个数请输入大于0的数字，或选择「所有」"))
                return false
            }
        }

        if (this.ui.Query("ResultToggleCon") == "True") {
            if (!CheckVarNameIfValid(this.ui.Query("ResultSaveNameCon")))
                return false
        }

        if (this.ui.Query("MouseActionTypeCon>SelectedIndex") + 1 != 1) {
            if (!IsNumber(this.ui.Query("SpeedCon")) || this.ui.Query("SpeedCon") < 0 || this.ui.Query("SpeedCon") > 100) {
                MsgBox(GetLang("移动速度请输入0~100的数字"))
                return false
            }
        }

        return true
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        F2Action := (*) => this.OnScreenShotBtnClick(this._CurTarget())
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
            Hotkey("F2", F2Action, "On")
            Hotkey("F3", (*) => this.SureColor(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
            Hotkey("F2", F2Action, "Off")
            Hotkey("F3", (*) => this.SureColor(), "Off")
        }
    }

    RefreshMouseInfo() {
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            this.ui.Update("MousePosCon", "Text", Format("{},{}", mouseX, mouseY))
            PosArr := GetCurWinPos()
            this.ui.Update("MouseWinPosCon", "Text", Format("{},{}", PosArr[1], PosArr[2]))
            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            ColorText := StrReplace(Color, "0x", "")
            this.ui.Update("MouseColorCon", "Text", ColorText)
            this.ui.Update("MouseColorTipCon", "Background", "#" ColorText)
        }
        catch {
            ; 鼠标越界 / 窗口已关 / 取色失败都属正常情况，定时刷新不该抛错刷日志
        }
    }

    OnSureTarget(PosX, PosY, Color) {
        this.ToggleFunc(true)
        n := this._CurTarget()
        ColorText := StrReplace(Color, "0x", "")
        this.ui.Update(this._TN(n, "Color"), "Text", ColorText)
        this.ui.Update(this._TN(n, "ColorTip"), "Visibility", "Visible")
        this.ui.Update(this._TN(n, "ColorTip"), "Background", "#" ColorText)
        this.OnSetSearchArea(PosX, PosY, PosX, PosY)
    }

    OnClickTargeterBtn(*) {
        ; 停止鼠标信息定时器 + F1-F3 热键，避免干扰取色器拖动
        this.ToggleFunc(false)
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(*) {
        str := Format("{}`n{}`n{}",
            GetLang("1.左键拖拽改变位置"),
            GetLang("2.上下左右方向键微调位置"),
            GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"))
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnClickSureBtn(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveSearchData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.OnGuiClose()
    }

    OnClickSetPicBtn(n, *) {
        this.CurTarget := n
        tn := this._TN(n, "")
        curPath := this.ui.Query(tn "ImagePath")
        path := FileSelect(1, curPath, GetLang("选择图片"), "PNG Files (*.png)")
        if (path != "") {
            SplitPath path, &name, &dir, &ext, &name_no_ext, &drive
            newPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" name
            if (path != newPath) {
                if (FileExist(newPath)) {
                    imageSerial := GetNextImageSerial()
                    newPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
                }
                FileCopy(path, newPath)
                path := newPath
            }
            this._SetImage(n, path)
            this.TargetList[n].SearchImagePath := path
            this.ui.Update(tn "ImagePath", "Text", path)
        }
    }

    OnScreenShotBtnClick(n, *) {
        this.CurTarget := n
        if (MainSoftData.ScreenShotType == 1) {
            SetClipboard("")
            Run("ms-screenclip:")
            SetTimer(this.CheckClipboardAction, 500)
            TogGetSelectArea(true, this.OnGetArea.Bind(this))
        }
        else if (MainSoftData.ScreenShotType == 3) {
            RunScreenCapture(this.CheckClipboardAction)
            TogGetSelectArea(true, this.OnGetArea.Bind(this))
        }
        else {
            TogSelectArea(true, this.OnScreenShotGetArea.Bind(this))
        }
    }

    CheckClipboard() {
        ; 窗口已关掉（this.ui 被置空）时先停监听再返回，否则定时器会一直报错
        if (!IsObject(this.ui)) {
            SetTimer(this.CheckClipboardAction, 0)
            return
        }
        if DllCall("IsClipboardFormatAvailable", "uint", 8) {
            n := this._CurTarget()
            imageSerial := GetNextImageSerial()
            filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
            SaveClipToBitmap(filePath)
            this._SetImage(n, filePath)
            this.TargetList[n].SearchImagePath := filePath
            this.ui.Update(this._TN(n, "ImagePath"), "Text", filePath)
            SetTimer(this.CheckClipboardAction, 0)
        }
    }

    OnGetArea(x1, y1, x2, y2) {
        AreaX1 := Max(0, x1 - 20)
        AreaX2 := Min(A_ScreenWidth, x2 + 20)
        AreaY1 := Max(0, y1 - 20)
        AreaY2 := Min(A_ScreenHeight, y2 + 20)
        this.OnSetSearchArea(AreaX1, AreaY1, AreaX2, AreaY2)
    }

    OnScreenShotGetArea(x1, y1, x2, y2) {
        if (x1 == x2)
            x2++
        if (y1 == y2)
            y2++

        n := this._CurTarget()
        imageSerial := GetNextImageSerial()
        filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
        ScreenShot(x1, y1, x2, y2, filePath)
        this._SetImage(n, filePath)
        this.TargetList[n].SearchImagePath := filePath
        this.ui.Update(this._TN(n, "ImagePath"), "Text", filePath)
        this.OnGetArea(x1, y1, x2, y2)
    }

    OnSureFoundMacroBtnClick(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.ui.Update("TrueMacroCon", "Text", CommandStr)
    }

    OnSureUnFoundMacroBtnClick(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.ui.Update("FalseMacroCon", "Text", CommandStr)
    }

    OnEditFoundMacroBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            this.MacroGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }
        this.MacroGui.SureBtnAction := (command) => this.OnSureFoundMacroBtnClick(command)
        this.MacroGui.ShowGui(this.ui.Query("TrueMacroCon"), false)
    }

    OnEditUnFoundMacroBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            this.MacroGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }
        this.MacroGui.SureBtnAction := (command) => this.OnSureUnFoundMacroBtnClick(command)
        this.MacroGui.ShowGui(this.ui.Query("FalseMacroCon"), false)
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveSearchData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnF1() {
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        n := this._CurTarget()
        curType := this._TargetType(n)
        isWin := curType == 4 || curType == 5 || curType == 6
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]
        this.ui.Update(this._TN(n, "StartPosX"), "Text", Point1[1])
        this.ui.Update(this._TN(n, "StartPosY"), "Text", Point1[2])
        this.ui.Update(this._TN(n, "EndPosX"), "Text", Point2[1])
        this.ui.Update(this._TN(n, "EndPosY"), "Text", Point2[2])
        ; 程序化 Update 填数字不触发 TextChanged，需显式刷新预览（框选/取色后立即可见）
        this.RefreshPreviewArea()
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        n := this._CurTarget()
        this.ui.Update(this._TN(n, "StartPosX"), "Text", x1)
        this.ui.Update(this._TN(n, "StartPosY"), "Text", y1)
        this.ui.Update(this._TN(n, "EndPosX"), "Text", x2)
        this.ui.Update(this._TN(n, "EndPosY"), "Text", y2)
        this.RefreshPreviewArea()
    }

    SureColor() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        CoordMode("Pixel", "Screen")
        Color := PixelGetColor(mouseX, mouseY, "Slow")
        ColorText := StrReplace(Color, "0x", "")
        n := this._CurTarget()
        this.ui.Update(this._TN(n, "Color"), "Text", ColorText)
        this.ui.Update(this._TN(n, "ColorTip"), "Visibility", "Visible")
        this.ui.Update(this._TN(n, "ColorTip"), "Background", "#" ColorText)
        this.OnSetSearchArea(mouseX, mouseY, mouseX, mouseY)
    }

    SaveSearchData() {
        data := this.Data
        ; 收集目标数组
        data.SearchTargetArr := []
        loop this.TargetList.Length {
            n := A_Index
            tn := this._TN(n, "")
            t := {
                SearchType: this._TargetType(n),
                WinInfo: this.ui.Query(tn "WinInfo"),
                SearchColor: this.ui.Query(tn "Color"),
                SearchText: this.ui.Query(tn "Text"),
                SearchImagePath: this.ui.Query(tn "ImagePath"),
                Similar: this.ui.Query(tn "Similar"),
                OCRType: 1,   ; v6 统一多语言模型，不再区分
                SearchImageType: Integer(this.ui.Query(tn "ImageType>SelectedIndex")) + 1,
                Adaptive: ObjHasOwnProp(this.TargetList[n], "Adaptive") ? this.TargetList[n].Adaptive : 0,
                Remark: this.ui.Query(tn "Remark"),
                StartPosX: this.ui.Query(tn "StartPosX"),
                StartPosY: this.ui.Query(tn "StartPosY"),
                EndPosX: this.ui.Query(tn "EndPosX"),
                EndPosY: this.ui.Query(tn "EndPosY")
            }
            data.SearchTargetArr.Push(t)
            if (n == 1) {
                ; 顶层字段同步第一个目标（兼容旧读法/旧配置回退）
                data.SearchType := t.SearchType
                data.WinInfo := t.WinInfo
                data.SearchColor := t.SearchColor
                data.SearchText := t.SearchText
                data.SearchImagePath := t.SearchImagePath
                data.Similar := t.Similar
                data.OCRType := t.OCRType
                data.SearchImageType := t.SearchImageType
                data.Adaptive := t.Adaptive
                data.StartPosX := t.StartPosX
                data.StartPosY := t.StartPosY
                data.EndPosX := t.EndPosX
                data.EndPosY := t.EndPosY
            }
        }
        data.SatisfyCount := this.ui.Query("SatisfyCountCon") == GetLang("所有") ? -1 : this.ui.Query("SatisfyCountCon")
        data.SearchCount := this.ui.Query("SearchCountCon") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCon")
        data.SearchInterval := this.ui.Query("SearchIntervalCon")
        data.MouseActionType := this.ui.Query("MouseActionTypeCon>SelectedIndex") + 1
        data.ClickCount := this.ui.Query("ClickCountCon")
        data.Speed := this.ui.Query("SpeedCon")
        data.TrueMacro := GetLangMacro(this.ui.Query("TrueMacroCon"), 2)
        data.FalseMacro := GetLangMacro(this.ui.Query("FalseMacroCon"), 2)
        data.ResultToggle := this.ui.Query("ResultToggleCon") == "True" ? 1 : 0
        data.ResultSaveName := GetVarName(this.ui.Query("ResultSaveNameCon"))
        data.TrueValue := this.ui.Query("TrueValueCon")
        data.FalseValue := this.ui.Query("FalseValueCon")
        data.CoordToogle := this.ui.Query("CoordToogleCon") == "True" ? 1 : 0
        data.CoordXName := this.ui.Query("CoordXNameCon")
        data.CoordYName := this.ui.Query("CoordYNameCon")

        if (data.ResultToggle)
            MySoftData.GlobalVariMap[data.ResultSaveName] := true

        if (data.CoordToogle) {
            MySoftData.GlobalVariMap[data.CoordXName] := true
            MySoftData.GlobalVariMap[data.CoordYName] := true
        }

        SaveMacroCMDData(data)
    }

    OnClickPreviewArea(n, *) {
        if (this.CurTarget == n)
            this.PreviewShowing := !this.PreviewShowing
        else {
            this.CurTarget := n
            this.PreviewShowing := true
            try this.ui.Update("TargetList", "SelectedIndex", String(n - 1))
        }
        this._ApplyAreaPreviewChrome()
        this.RefreshPreviewArea()
    }

    _ApplyAreaPreviewChrome() {
        if (!IsObject(this.ui))
            return
        loop this.TargetList.Length {
            on := this.PreviewShowing && A_Index == this.CurTarget
            name := this._TN(A_Index, "PreviewBtn")
            try this.ui.Update(name, "Tag", on ? "1" : "0")
            try this.ui.Update(name, "Background", on ? "{DynamicResource Accent}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", on ? "{DynamicResource Accent}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "BorderThickness", on ? "2" : "1")
        }
    }

    RefreshPreviewArea(*) {
        if (!IsObject(this.ui) || !this.PreviewShowing) {
            this.StopPreviewFollow()
            this.HidePreviewRect()
            return
        }
        n := this._CurTarget()
        tn := this._TN(n, "")
        startX := this.ui.Query(tn "StartPosX")
        startY := this.ui.Query(tn "StartPosY")
        endX := this.ui.Query(tn "EndPosX")
        endY := this.ui.Query(tn "EndPosY")

        if (!IsNumber(startX) || !IsNumber(startY) || !IsNumber(endX) || !IsNumber(endY)) {
            this.StopPreviewFollow()
            this.HidePreviewRect()
            return
        }

        startX := Number(startX)
        startY := Number(startY)
        endX := Number(endX)
        endY := Number(endY)

        curType := this._TargetType(n)
        isWin := curType == 4 || curType == 5 || curType == 6
        if (isWin) {
            hwndList := GetHwndList(this.ui.Query(tn "WinInfo"))
            if (hwndList.Length == 0) {
                this.StopPreviewFollow()
                this.HidePreviewRect()
                return
            }
            targetHwnd := hwndList[1]
            startPt := this.WinToScreen(targetHwnd, startX, startY)
            endPt := this.WinToScreen(targetHwnd, endX, endY)
            startX := startPt[1]
            startY := startPt[2]
            endX := endPt[1]
            endY := endPt[2]
        }

        x := Min(startX, endX)
        y := Min(startY, endY)
        w := Abs(endX - startX)
        h := Abs(endY - startY)

        if (w == 0 || h == 0) {
            this.StopPreviewFollow()
            this.HidePreviewRect()
            return
        }

        this.ShowPreviewRect(x, y, w, h)

        if (isWin && !this.PreviewFollowing) {
            this.PreviewFollowing := true
            this.PreviewFollowTimer := SetTimer(this.PreviewFollowTick.Bind(this), 100)
        }
        else if (!isWin && this.PreviewFollowing) {
            this.StopPreviewFollow()
        }
    }

    StopPreviewFollow() {
        if (this.PreviewFollowTimer != 0) {
            try {
                SetTimer(this.PreviewFollowTimer, 0)
            }
            this.PreviewFollowTimer := 0
        }
        this.PreviewFollowing := false
    }

    PreviewFollowTick() {
        if (!this.PreviewShowing) {
            this.StopPreviewFollow()
            return
        }
        this.RefreshPreviewArea()
    }

    WinToScreen(hwnd, winX, winY) {
        DllCall("SetProcessDPIAware")
        GA_ROOT := 2
        rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", GA_ROOT, "ptr")
        pt := Buffer(8, 0)
        NumPut("int", winX, pt, 0)
        NumPut("int", winY, pt, 4)
        DllCall("User32\ClientToScreen", "ptr", rootHwnd, "ptr", pt)
        screenX := NumGet(pt, 0, "int")
        screenY := NumGet(pt, 4, "int")
        return [screenX, screenY]
    }

    ShowPreviewRect(x, y, w, h) {
        borderW := 2
        borderColor := "Red"

        if (this.PreviewBorderArr.Length == 0) {
            topGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x20 -DPIScale")
            topGui.BackColor := borderColor
            topGui.Show("NA x" x " y" y " w" w " h" borderW)
            this.PreviewBorderArr.Push(topGui)

            bottomGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x20 -DPIScale")
            bottomGui.BackColor := borderColor
            bottomGui.Show("NA x" x " y" (y + h - borderW) " w" w " h" borderW)
            this.PreviewBorderArr.Push(bottomGui)

            leftGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x20 -DPIScale")
            leftGui.BackColor := borderColor
            leftGui.Show("NA x" x " y" y " w" borderW " h" h)
            this.PreviewBorderArr.Push(leftGui)

            rightGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x20 -DPIScale")
            rightGui.BackColor := borderColor
            rightGui.Show("NA x" (x + w - borderW) " y" y " w" borderW " h" h)
            this.PreviewBorderArr.Push(rightGui)
        }
        else {
            this.PreviewBorderArr[1].Move(x, y, w, borderW)
            this.PreviewBorderArr[2].Move(x, y + h - borderW, w, borderW)
            this.PreviewBorderArr[3].Move(x, y, borderW, h)
            this.PreviewBorderArr[4].Move(x + w - borderW, y, borderW, h)
        }
    }

    HidePreviewRect() {
        for gui in this.PreviewBorderArr {
            try {
                gui.Destroy()
            }
        }
        this.PreviewBorderArr := []
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.StopPreviewFollow()
        this.HidePreviewRect()
        try this.ToggleFunc(false)
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
        this.StopPreviewFollow()
        this.HidePreviewRect()
        try this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("搜索Combo")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()

        this.TargetList := this._TargetListOf(this.Data)
        if (this.TargetList.Length == 0) {
            this.TargetList := [this._TargetListOf(this.Data)[1]]
        }
        this.CurTarget := 1
        this.PreviewShowing := false

        this._RebuildTargetList()

        ; 整体设置（SatisfyCount 为新字段，旧配置缺失时回退 -1=所有）
        satVal := ObjHasOwnProp(this.Data, "SatisfyCount") ? this.Data.SatisfyCount : -1
        this._SetCombo("SatisfyCountCon", [GetLang("所有")], satVal == -1 ? GetLang("所有") : satVal)
        this._SetCombo("SearchCountCon", [GetLang("无限")], this.Data.SearchCount == -1 ? GetLang("无限") : this.Data.SearchCount)
        this.ui.Update("SearchIntervalCon", "Text", this.Data.SearchInterval)
        this.ui.Update("SpeedCon", "Text", this.Data.Speed)
        this.ui.Update("ClickCountCon", "Text", this.Data.ClickCount)
        this.ui.Update("TrueMacroCon", "Text", GetLangMacro(this.Data.TrueMacro, 1))
        this.ui.Update("FalseMacroCon", "Text", GetLangMacro(this.Data.FalseMacro, 1))
        this.ui.Update("ResultToggleCon", "IsChecked", this._ToggleInt(ObjHasOwnProp(this.Data, "ResultToggle") ? this.Data.ResultToggle : 0) ? "True" : "False")
        this._SetCombo("ResultSaveNameCon", this.DLVariableArr, this.Data.ResultSaveName)
        this.ui.Update("TrueValueCon", "Text", this.Data.TrueValue)
        this.ui.Update("FalseValueCon", "Text", this.Data.FalseValue)
        this.ui.Update("CoordToogleCon", "IsChecked", this._ToggleInt(ObjHasOwnProp(this.Data, "CoordToogle") ? this.Data.CoordToogle : 0) ? "True" : "False")
        this._SetCombo("CoordXNameCon", this.DLVariableArr, this.Data.CoordXName)
        this._SetCombo("CoordYNameCon", this.DLVariableArr, this.Data.CoordYName)

        MouseDLArr := GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
        this.ui.Update("MouseActionTypeCon", "ClearItems", "")
        for it in MouseDLArr
            this.ui.Update("MouseActionTypeCon", "AddItem", it)
        this.ui.Update("MouseActionTypeCon", "SelectedIndex", String((this.Data.MouseActionType ? this.Data.MouseActionType : 2) - 1))
        this.OnOverallChange()
    }
}
