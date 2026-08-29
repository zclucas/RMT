#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 搜索Pro编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; §15.1 多目标重构：左侧目标列表（ListBox + AddXamlItem 动态注入目标卡片，单选高亮），
;   每个目标独立配置 搜索类型/窗口信息/坐标/图片/颜色/文本/相似度；
;   右侧整体设置（搜索次数/间隔/满足个数/鼠标动作/结果保存/目标点保存/找到/未找到指令）。
; §19 合并决策：移除「屏幕规格」行（ConfigDLCon/ConfigArr 不再在 GUI 管理，旧配置字段保留无害）。
; 屏幕级功能（预览框/取色器/截图/鼠标跟踪/F1-F3热键）沿用原生全局函数，作用于当前选中目标。
; =====================================================================

class SearchProGui {
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
        this.CountTogArr := ["SearchIntervalTipCon", "SearchIntervalCon"]
        this.MouseSpeedArr := ["SpeedTipCon", "SpeedCon"]
        this.MouseClickArr := ["ClickCountTipCon", "ClickCountCon"]
        this.ResultTogArr := ["ResultVarTipCon", "ResultSaveNameCon", "TrueValueTipCon", "TrueValueCon", "FalseValueTipCon", "FalseValueCon"]
        this.CoordTogArr := ["CoordXTipCon", "CoordXNameCon", "CoordYTipCon", "CoordYNameCon"]

        this.PreviewBorderArr := []
        this.PreviewFollowTimer := 0
        this.PreviewFollowing := false
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
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("搜索Pro编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "30", "24", "*", "44")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 顶部工具行 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,4")
        top.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        top.Add("TextBlock").Text("!l").VerticalAlignment("Center").Margin("4,0,0,0").Opacity("0.6")
        top.Add("Button").Name("BtnTrigger").Content(GetLang("执行指令")).Width(80).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("TextBox").Name("RemarkCon").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        top.Add("CheckBox").Name("PreviewAreaCon").Content(GetLang("预览框选范围")).VerticalAlignment("Center").Margin("16,0,0,0")
        top.Add("CheckBox").Name("SelectToggleCon").Content(GetLang("左键框选搜索范围")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("Button").Name("BtnTargeter").Content(GetLang("定位取色器")).Height(26).MinHeight(26).Margin("12,0,0,0").Cursor("Hand")
        top.Add("Button").Name("BtnTargeterHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1").Padding("0")

        ; === 鼠标信息行 ===
        mi := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,0")
        mi.Add("TextBlock").Name("MousePosCon").Text(GetLang("屏幕坐标：0,0")).VerticalAlignment("Center")
        mi.Add("TextBlock").Name("MouseWinPosCon").Text(GetLang("窗口坐标：0,0")).VerticalAlignment("Center").Margin("20,0,0,0")
        mi.Add("TextBlock").Name("MouseColorCon").Text(GetLang("鼠标颜色：FFFFFF")).VerticalAlignment("Center").Margin("20,0,0,0")
        mi.Add("Border").Name("MouseColorTipCon").Width(16).Height(16).Background("#FF0000").VerticalAlignment("Center").Margin("6,0,0,0")

        ; === 主体两列 ===
        body := main.Add("Grid").Grid_Row(3).Margin("10,2,10,0")
        body.Cols("*", "235")
        body.Rows("*", "Auto")

        ; ---- 左列：目标列表（ListBox + 动态注入目标卡片） ----
        left := body.Add("Grid").Grid_Column(0).Margin("0,0,8,0")
        left.Rows("*", "Auto")
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/></Style>'
        left.Add("ListBox").Grid_Row(0).Name("TargetList")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .VirtualizingPanel_IsVirtualizing("False")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled").ScrollViewer_VerticalScrollBarVisibility("Auto")
            .InjectResources(lbStyle)
        addRow := left.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,6,0,0")
        addRow.Add("Button").Name("BtnAddTarget").Content(GetLang("+ 添加目标")).Width(100).Height(28).MinHeight(28).Cursor("Hand")

        ; ---- 右列：整体设置（滚动） ----
        right := body.Add("ScrollViewer").Grid_Column(1)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        rightPanel := right.Add("StackPanel").Margin("0,0,0,0")

        ; 满足个数
        scRow := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,2,0,0")
        scRow.Add("TextBlock").Text(GetLang("满足个数：")).VerticalAlignment("Center")
        scRow.Add("ComboBox").Name("SatisfyCountCon").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 搜索次数 + 每次间隔
        sr := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        sr.Add("TextBlock").Text(GetLang("搜索次数：")).VerticalAlignment("Center")
        sr.Add("ComboBox").Name("SearchCountCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        sr.Add("TextBlock").Name("SearchIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("8,0,0,0")
        sr.Add("TextBox").Name("SearchIntervalCon").Width(60).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 鼠标动作
        ma := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        ma.Add("TextBlock").Text(GetLang("鼠标动作：")).VerticalAlignment("Center")
        mac := ma.Add("ComboBox").Name("MouseActionTypeCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
            mac.Add("ComboBoxItem").Content(t)

        ms := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        ms.Add("TextBlock").Name("SpeedTipCon").Text(GetLang("移动速度：")).VerticalAlignment("Center")
        ms.Add("TextBox").Name("SpeedCon").Width(80).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ms.Add("TextBlock").Name("ClickCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").Margin("12,0,0,0")
        ms.Add("TextBox").Name("ClickCountCon").Width(60).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 找到/未找到指令
        ft := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,10,0,0")
        ft.Add("TextBlock").Text(GetLang("找到后的指令：（可选）")).VerticalAlignment("Center")
        ft.Add("Button").Name("BtnEditFoundMacro").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        rightPanel.Add("TextBox").Name("TrueMacroCon").Height(44).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        ft2 := rightPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        ft2.Add("TextBlock").Name("FalseMacroTipCon").Text(GetLang("未找到后的指令：（可选）")).VerticalAlignment("Center")
        ft2.Add("Button").Name("FalseMacroEditBtn").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        rightPanel.Add("TextBox").Name("FalseMacroCon").Height(44).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        ; 结果保存
        rg := rightPanel.Add("GroupBox").Margin("0,8,0,0").Header(GetLang("结果保存"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("6,4")
        rgGrid := rg.Add("Grid")
        rgGrid.Cols("Auto", "Auto", "Auto", "Auto")
        rgGrid.Rows("28", "28")
        rgGrid.Add("CheckBox").Name("ResultToggleCon").Content(GetLang("开关")).Grid_Row(0).Grid_Column(0).VerticalAlignment("Center")
        rgGrid.Add("TextBlock").Name("ResultVarTipCon").Text(GetLang("变量名")).Grid_Row(0).Grid_Column(1).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("ComboBox").Name("ResultSaveNameCon").Width(100).Height(24).MinHeight(24).Grid_Row(0).Grid_Column(2).Margin("4,0,0,0").IsEditable("True")
        rgGrid.Add("TextBlock").Name("TrueValueTipCon").Text(GetLang("真值")).Grid_Row(1).Grid_Column(0).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("TextBox").Name("TrueValueCon").Width(60).Height(24).MinHeight(24).Grid_Row(1).Grid_Column(1).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        rgGrid.Add("TextBlock").Name("FalseValueTipCon").Text(GetLang("假值")).Grid_Row(1).Grid_Column(2).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("TextBox").Name("FalseValueCon").Width(60).Height(24).MinHeight(24).Grid_Row(1).Grid_Column(3).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 目标点保存
        cg := rightPanel.Add("GroupBox").Margin("0,6,0,0").Header(GetLang("目标点保存"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("6,4")
        cgGrid := cg.Add("Grid")
        cgGrid.Cols("Auto", "Auto", "Auto", "Auto", "Auto")
        cgGrid.Rows("28")
        cgGrid.Add("CheckBox").Name("CoordToogleCon").Content(GetLang("开关")).Grid_Row(0).Grid_Column(0).VerticalAlignment("Center")
        cgGrid.Add("TextBlock").Name("CoordXTipCon").Text(GetLang("坐标X变量名")).Grid_Row(0).Grid_Column(1).VerticalAlignment("Center").Margin("10,0,0,0")
        cgGrid.Add("ComboBox").Name("CoordXNameCon").Width(80).Height(24).MinHeight(24).Grid_Row(0).Grid_Column(2).Margin("4,0,0,0").IsEditable("True")
        cgGrid.Add("TextBlock").Name("CoordYTipCon").Text(GetLang("坐标Y变量名")).Grid_Row(0).Grid_Column(3).VerticalAlignment("Center").Margin("10,0,0,0")
        cgGrid.Add("ComboBox").Name("CoordYNameCon").Width(80).Height(24).MinHeight(24).Grid_Row(0).Grid_Column(4).Margin("4,0,0,0").IsEditable("True")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="880" Height="680" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTrigger", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnTargeter", "Click", ObjBindMethod(this, "OnClickTargeterBtn"))
        this.ui.OnEvent("BtnTargeterHelp", "Click", ObjBindMethod(this, "OnClickTargeterHelpBtn"))
        this.ui.OnEvent("BtnAddTarget", "Click", ObjBindMethod(this, "OnAddTarget"))
        this.ui.OnEvent("TargetList", "SelectionChanged", ObjBindMethod(this, "OnTargetSelected"))
        this.ui.OnEvent("PreviewAreaCon", "Click", ObjBindMethod(this, "OnClickPreviewArea"))
        this.ui.OnEvent("SelectToggleCon", "Click", ObjBindMethod(this, "OnClickSelectToggle"))
        this.ui.OnEvent("SatisfyCountCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("SearchCountCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("SearchIntervalCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("MouseActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("SpeedCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("ClickCountCon", "TextChanged", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("ResultToggleCon", "Click", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("CoordToogleCon", "Click", ObjBindMethod(this, "OnOverallChange"))
        this.ui.OnEvent("BtnEditFoundMacro", "Click", ObjBindMethod(this, "OnEditFoundMacroBtnClick"))
        this.ui.OnEvent("FalseMacroEditBtn", "Click", ObjBindMethod(this, "OnEditUnFoundMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
            SearchImageType: ObjHasOwnProp(Data, "SearchImageType") ? Data.SearchImageType : 1,
            StartPosX: ObjHasOwnProp(Data, "StartPosX") ? Data.StartPosX : 0,
            StartPosY: ObjHasOwnProp(Data, "StartPosY") ? Data.StartPosY : 0,
            EndPosX: ObjHasOwnProp(Data, "EndPosX") ? Data.EndPosX : A_ScreenWidth,
            EndPosY: ObjHasOwnProp(Data, "EndPosY") ? Data.EndPosY : A_ScreenHeight
        }
        return [t]
    }

    ; 目标卡片 XAML（每目标独立配置）
    _TargetCardXml(n, t) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        typeItems := ""
        for tt in GetLangArr(["屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"])
            typeItems .= '<ComboBoxItem Content="' tt '"/>'
        modelItems := '<ComboBoxItem Content="OpenCV"/><ComboBoxItem Content="' GetLang("RMT识图") '"/>'

        xaml := '<ListBoxItem ' ns ' Tag="' n '">'
            . '<Border Margin="0,1" Padding="8,6" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" CornerRadius="4" Background="{DynamicResource DropdownBg}">'
            . '<StackPanel>'
            ; 标题行：目标序号 + 类型 + 删除
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
            . '<TextBlock Text="' GetLang("目标") ' ' n '" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'
            . '<TextBlock Text="' GetLang("搜索类型：") '" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "Type") '" Width="110" Height="24" MinHeight="24" Margin="4,0,0,0">' typeItems '</ComboBox>'
            . '<Button Name="' this._TN(n, "DelBtn") '" Content="' GetLang("删除目标") '" Height="24" MinHeight="24" Padding="8,0" Margin="10,0,0,0" Cursor="Hand"/>'
            . '</StackPanel>'
            ; 窗口信息行
            . '<StackPanel Name="' this._TN(n, "WinInfoRow") '" Orientation="Horizontal" Margin="0,6,0,0">'
            . '<TextBlock Text="' GetLang("窗口信息:") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Name="' this._TN(n, "WinInfo") '" Width="150" Height="24" MinHeight="24" Margin="4,0,0,0"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" VerticalContentAlignment="Center" Padding="4,0"/>'
            . '<Button Name="' this._TN(n, "WinInfoEditBtn") '" Content="' GetLang("编辑") '" Height="24" MinHeight="24" Margin="6,0,0,0" Cursor="Hand"/>'
            . '</StackPanel>'
            ; 坐标行
            . '<StackPanel Orientation="Horizontal" Margin="0,6,0,0">'
            . '<TextBlock Text="' GetLang("起始坐标X：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "StartPosX") '" Width="70" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '<TextBlock Text="' GetLang("起始坐标Y：") '" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "StartPosY") '" Width="70" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '<TextBlock Text="' GetLang("终止坐标X：") '" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "EndPosX") '" Width="70" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '<TextBlock Text="' GetLang("终止坐标Y：") '" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "EndPosY") '" Width="70" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '</StackPanel>'
            ; 图片区
            . '<StackPanel Name="' this._TN(n, "ImageRow") '" Orientation="Horizontal" Margin="0,6,0,0">'
            . '<TextBlock Text="' GetLang("识别模型：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "ImageType") '" Width="80" Height="24" MinHeight="24" Margin="4,0,0,0">' modelItems '</ComboBox>'
            . '<Button Name="' this._TN(n, "ScreenshotBtn") '" Content="' GetLang("截图") '" Height="24" MinHeight="24" Margin="10,0,0,0" Cursor="Hand"/>'
            . '<Button Name="' this._TN(n, "ImageSelectBtn") '" Content="' GetLang("选择图片") '" Height="24" MinHeight="24" Margin="6,0,0,0" Cursor="Hand"/>'
            . '</StackPanel>'
            . '<StackPanel Name="' this._TN(n, "ImagePathRow") '" Orientation="Horizontal" Margin="0,4,0,0">'
            . '<TextBlock Text="' GetLang("图片路径：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "ImagePath") '" Width="250" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '<Image Name="' this._TN(n, "Image") '" Width="40" Height="40" Margin="8,0,0,0" Stretch="Uniform" VerticalAlignment="Center"/>'
            . '</StackPanel>'
            ; 颜色区
            . '<StackPanel Name="' this._TN(n, "ColorRow") '" Orientation="Horizontal" Margin="0,6,0,0">'
            . '<TextBlock Text="' GetLang("搜索颜色：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "Color") '" Width="110" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '<Border Name="' this._TN(n, "ColorTip") '" Width="16" Height="16" Background="#FF0000" VerticalAlignment="Center" Margin="6,0,0,0"/>'
            . '</StackPanel>'
            ; 文本区
            . '<StackPanel Name="' this._TN(n, "TextRow") '" Orientation="Horizontal" Margin="0,6,0,0">'
            . '<TextBlock Text="' GetLang("搜索文本：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Name="' this._TN(n, "Text") '" Width="200" Height="24" MinHeight="24" Margin="4,0,0,0" IsEditable="True"/>'
            . '</StackPanel>'
            ; 相似度
            . '<StackPanel Name="' this._TN(n, "SimilarRow") '" Orientation="Horizontal" Margin="0,6,0,0">'
            . '<TextBlock Text="' GetLang("相似度(%)：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Name="' this._TN(n, "Similar") '" Width="80" Height="24" MinHeight="24"'
            . ' VerticalContentAlignment="Center" Padding="4,0" TextAlignment="Center" FontSize="11" Margin="4,0,0,0"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
            . '</StackPanel></Border></ListBoxItem>'
        return xaml
    }

    ; 重建目标列表：ClearItems + 注入全部卡片 + 绑定事件 + 填值
    _RebuildTargetList() {
        if (!IsObject(this.ui))
            return
        batch := []
        batch.Push({ControlName: "TargetList", PropertyName: "ClearItems", Value: ""})
        loop this.TargetList.Length
            batch.Push({ControlName: "TargetList", PropertyName: "AddXamlItem", Value: this._TargetCardXml(A_Index, this.TargetList[A_Index])})
        this.ui.BatchUpdate(batch)
        loop this.TargetList.Length
            this._BindTargetCard(A_Index)
        loop this.TargetList.Length
            this._FillTargetCard(A_Index)
        this.ui.Update("TargetList", "SelectedIndex", String(this.CurTarget - 1))
    }

    _BindTargetCard(n) {
        this._Bind(this._TN(n, "Type"), "SelectionChanged", ObjBindMethod(this, "OnTargetTypeChanged", n))
        this._Bind(this._TN(n, "DelBtn"), "Click", ObjBindMethod(this, "OnDelTarget", n))
        this._Bind(this._TN(n, "WinInfoEditBtn"), "Click", ObjBindMethod(this, "OnClickWinEditBtn", n))
        this._Bind(this._TN(n, "StartPosX"), "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "StartPosY"), "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "EndPosX"), "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "EndPosY"), "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this._Bind(this._TN(n, "ScreenshotBtn"), "Click", ObjBindMethod(this, "OnScreenShotBtnClick", n))
        this._Bind(this._TN(n, "ImageSelectBtn"), "Click", ObjBindMethod(this, "OnClickSetPicBtn", n))
    }

    _FillTargetCard(n) {
        if (!IsObject(this.ui) || n > this.TargetList.Length)
            return
        t := this.TargetList[n]
        this.ui.Update(this._TN(n, "Type"), "SelectedIndex", String(Integer(t.SearchType ? t.SearchType : 1) - 1))
        this.ui.Update(this._TN(n, "WinInfo"), "Text", t.WinInfo)
        this._SetCombo(this._TN(n, "StartPosX"), this.DLVariableArr, t.StartPosX)
        this._SetCombo(this._TN(n, "StartPosY"), this.DLVariableArr, t.StartPosY)
        this._SetCombo(this._TN(n, "EndPosX"), this.DLVariableArr, t.EndPosX)
        this._SetCombo(this._TN(n, "EndPosY"), this.DLVariableArr, t.EndPosY)
        this.ui.Update(this._TN(n, "ImageType"), "SelectedIndex", String((t.SearchImageType ? t.SearchImageType : 1) - 1))
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
        if (IsNumber(idx) && Integer(idx) >= 0 && Integer(idx) < this.TargetList.Length) {
            this.CurTarget := Integer(idx) + 1
            this.RefreshPreviewArea()
        }
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
        this.ui.Update(tn "WinInfoRow", "Visibility", isWin ? "Visible" : "Collapsed")
        this.ui.Update(tn "ImageRow", "Visibility", isImage ? "Visible" : "Collapsed")
        this.ui.Update(tn "ImagePathRow", "Visibility", isImage ? "Visible" : "Collapsed")
        this.ui.Update(tn "ColorRow", "Visibility", isColor ? "Visible" : "Collapsed")
        this.ui.Update(tn "TextRow", "Visibility", isText ? "Visible" : "Collapsed")
        this.ui.Update(tn "SimilarRow", "Visibility", isText ? "Collapsed" : "Visible")
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
    }

    FalseConArr2() {
        if (!ObjHasOwnProp(this, "_FalseConArr")) {
            this._FalseConArr := ["FalseMacroTipCon", "FalseMacroEditBtn", "FalseMacroCon"]
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
            this.ui.Update("MousePosCon", "Text", Format("{}{},{}", GetLang("屏幕坐标："), mouseX, mouseY))
            PosArr := GetCurWinPos()
            this.ui.Update("MouseWinPosCon", "Text", Format("{}{},{}", GetLang("窗口坐标："), PosArr[1], PosArr[2]))
            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            ColorText := StrReplace(Color, "0x", "")
            this.ui.Update("MouseColorCon", "Text", Format("{}{}", GetLang("鼠标颜色："), ColorText))
            this.ui.Update("MouseColorTipCon", "Background", "#" ColorText)
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
        if DllCall("IsClipboardFormatAvailable", "uint", 8) {
            n := this._CurTarget()
            imageSerial := GetNextImageSerial()
            filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
            SaveClipToBitmap(filePath)
            this._SetImage(n, filePath)
            this.TargetList[n].SearchImagePath := filePath
            this.ui.Update(this._TN(n, "ImagePath"), "Text", filePath)
            SetTimer(, 0)
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

    OnClickSelectToggle(*) {
        state := this.ui.Query("SelectToggleCon") == "True"
        if (state)
            TogSelectArea(true, this.F1Action)
        else
            TogSelectArea(false)
    }

    OnF1() {
        this.ui.Update("SelectToggleCon", "IsChecked", "True")
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        this.ui.Update("SelectToggleCon", "IsChecked", "False")
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
        this.ui.Update("SelectToggleCon", "IsChecked", "False")
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

    OnClickPreviewArea(*) {
        this.RefreshPreviewArea()
    }

    RefreshPreviewArea(*) {
        if (this.ui.Query("PreviewAreaCon") != "True") {
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
        if (this.ui.Query("PreviewAreaCon") != "True") {
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
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        }
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("搜索Pro")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()

        this.TargetList := this._TargetListOf(this.Data)
        if (this.TargetList.Length == 0) {
            this.TargetList := [this._TargetListOf(this.Data)[1]]
        }
        this.CurTarget := 1

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
