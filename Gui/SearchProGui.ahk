#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk
#Include WinRuleGui.ahk

; =====================================================================
; 搜索Pro编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 屏幕级功能（预览框/取色器/截图/鼠标跟踪/F1-F3热键）沿用原生全局函数，仅控件读写改 ui.Query/Update
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

        this.ConfigDLArr := []
        this.DLVariableArr := []
        ; 显隐/启停控件名数组（SetConArrState 用）
        this.ImageVariArr := ["SearchImageTypeTipCon", "SearchImageTypeCon", "ImageCon", "ScreenshotBtn", "ImageSelectBtn", "SearchImagePathTipCon", "ImagePathCon"]
        this.ColorArr := ["ColorLabelCon", "HexColorCon", "HexColorTipCon"]
        this.TextArr := ["TextTipCon", "TextCon"]
        this.SimilarArr := ["SimilarTipCon", "SimilarCon"]
        this.WinInfoArr := ["WinInfoTipCon", "WinInfoCon", "WinInfoEditBtn"]
        this.FalseConArr := ["FalseMacroTipCon", "FalseMacroEditBtn", "FalseMacroCon"]
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
        main.Rows(titleHeight, "30", "24", "30", "30", "*", "44")

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

        ; === 搜索类型行 ===
        st := main.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").Margin("10,2")
        st.Add("TextBlock").Text(GetLang("搜索类型：")).VerticalAlignment("Center")
        stc := st.Add("ComboBox").Name("SearchTypeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"])
            stc.Add("ComboBoxItem").Content(t)
        st.Add("Button").Name("BtnTypeHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1").Padding("0")

        ; === 屏幕规格行 ===
        sc := main.Add("StackPanel").Grid_Row(4).Orientation("Horizontal").Margin("10,2")
        sc.Add("TextBlock").Text(GetLang("屏幕规格：")).VerticalAlignment("Center")
        sc.Add("ComboBox").Name("ConfigDLCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
        sc.Add("Button").Name("BtnEditScreenRule").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")
        sc.Add("Button").Name("BtnWinRuleHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1").Padding("0")

        ; === 主体两列 ===
        body := main.Add("Grid").Grid_Row(5).Margin("10,2,10,0")
        body.Cols("*", "*")
        body.Rows("*", "Auto", "Auto")

        ; ---- 左列 ----
        left := body.Add("StackPanel").Grid_Column(0).Orientation("Vertical").Margin("0,0,8,0")
        coordGrid := left.Add("Grid")
        coordGrid.Cols("Auto", "Auto", "Auto", "Auto")
        coordGrid.Rows("28", "28")
        this._AddCoordRow(coordGrid, 0, "StartPosXCon", "StartPosYCon", GetLang("起始坐标X："), GetLang("起始坐标Y："))
        this._AddCoordRow(coordGrid, 1, "EndPosXCon", "EndPosYCon", GetLang("终止坐标X："), GetLang("终止坐标Y："))

        sr := left.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        sr.Add("TextBlock").Text(GetLang("搜索次数：")).VerticalAlignment("Center")
        sr.Add("ComboBox").Name("SearchCountCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        sr.Add("TextBlock").Name("SearchIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("12,0,0,0")
        sr.Add("TextBox").Name("SearchIntervalCon").Width(80).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ma := left.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        ma.Add("TextBlock").Text(GetLang("鼠标动作：")).VerticalAlignment("Center")
        mac := ma.Add("ComboBox").Name("MouseActionTypeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
            mac.Add("ComboBoxItem").Content(t)

        ms := left.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        ms.Add("TextBlock").Name("SpeedTipCon").Text(GetLang("移动速度：")).VerticalAlignment("Center")
        ms.Add("TextBox").Name("SpeedCon").Width(80).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ms.Add("TextBlock").Name("ClickCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").Margin("12,0,0,0")
        ms.Add("TextBox").Name("ClickCountCon").Width(80).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; ---- 右列 ----
        right := body.Add("StackPanel").Grid_Column(1).Orientation("Vertical").Margin("8,0,0,0")
        wi := right.Add("StackPanel").Orientation("Horizontal")
        wi.Add("TextBlock").Name("WinInfoTipCon").Text(GetLang("窗口信息:")).VerticalAlignment("Center")
        wi.Add("TextBox").Name("WinInfoCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        wi.Add("Button").Name("WinInfoEditBtn").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")

        sim := right.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        sim.Add("TextBlock").Name("SimilarTipCon").Text(GetLang("相似度(%)：")).VerticalAlignment("Center")
        sim.Add("TextBox").Name("SimilarCon").Width(80).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 图片搜索区域
        imgRow := right.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        imgRow.Add("TextBlock").Name("SearchImageTypeTipCon").Text(GetLang("识别模型：")).VerticalAlignment("Center")
        sit := imgRow.Add("ComboBox").Name("SearchImageTypeCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
        sit.Add("ComboBoxItem").Content("OpenCV")
        sit.Add("ComboBoxItem").Content("RMT识图")
        right.Add("Image").Name("ImageCon").Width(100).Height(100).Margin("0,4,0,0").Stretch("Uniform")
        imgBtn := right.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        imgBtn.Add("Button").Name("ScreenshotBtn").Content(GetLang("截图")).Width(70).Height(28).MinHeight(28).Cursor("Hand")
        imgBtn.Add("Button").Name("ImageSelectBtn").Content(GetLang("选择图片")).Width(80).Height(28).MinHeight(28).Margin("6,0,0,0").Cursor("Hand")
        imgPath := right.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        imgPath.Add("TextBlock").Name("SearchImagePathTipCon").Text(GetLang("图片路径：")).VerticalAlignment("Center")
        imgPath.Add("ComboBox").Name("ImagePathCon").Width(220).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 颜色搜索区域
        cl := right.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        cl.Add("TextBlock").Name("ColorLabelCon").Text(GetLang("搜索颜色：")).VerticalAlignment("Center")
        cl.Add("ComboBox").Name("HexColorCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        cl.Add("Border").Name("HexColorTipCon").Width(16).Height(16).Background("#FF0000").VerticalAlignment("Center").Margin("6,0,0,0")

        ; 文本搜索区域
        tx := right.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        tx.Add("TextBlock").Name("TextTipCon").Text(GetLang("搜索文本：")).VerticalAlignment("Center")
        tx.Add("ComboBox").Name("TextCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; === 找到/未找到后的指令（共享行，左右对齐）===
        macroRow := body.Add("Grid").Grid_Row(1).Grid_ColumnSpan(2).Margin("0,8,0,0")
        macroRow.Cols("*", "*")

        foundCol := macroRow.Add("StackPanel").Grid_Column(0).Orientation("Vertical").Margin("0,0,8,0")
        ft := foundCol.Add("StackPanel").Orientation("Horizontal")
        ft.Add("TextBlock").Text(GetLang("找到后的指令：（可选）")).VerticalAlignment("Center")
        ft.Add("Button").Name("BtnEditFoundMacro").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        foundCol.Add("TextBox").Name("TrueMacroCon").Height(50).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        unfoundCol := macroRow.Add("StackPanel").Grid_Column(1).Orientation("Vertical").Margin("8,0,0,0")
        ft2 := unfoundCol.Add("StackPanel").Orientation("Horizontal")
        ft2.Add("TextBlock").Name("FalseMacroTipCon").Text(GetLang("未找到后的指令：（可选）")).VerticalAlignment("Center")
        ft2.Add("Button").Name("FalseMacroEditBtn").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        unfoundCol.Add("TextBox").Name("FalseMacroCon").Height(50).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        ; === 底部保存区（左右对齐）===
        saveRow := body.Add("Grid").Grid_Row(2).Grid_ColumnSpan(2).Margin("0,6,0,0")
        saveRow.Cols("*", "*")

        rg := saveRow.Add("GroupBox").Grid_Column(0).Header(GetLang("结果保存")).Margin("0,0,8,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("6,4")
        rgGrid := rg.Add("Grid")
        rgGrid.Cols("Auto", "Auto", "Auto", "Auto")
        rgGrid.Rows("28", "28")
        rgGrid.Add("CheckBox").Name("ResultToggleCon").Content(GetLang("开关")).Grid_Row(0).Grid_Column(0).VerticalAlignment("Center")
        rgGrid.Add("TextBlock").Name("ResultVarTipCon").Text(GetLang("变量名")).Grid_Row(0).Grid_Column(1).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("ComboBox").Name("ResultSaveNameCon").Width(120).Height(24).MinHeight(24).Grid_Row(0).Grid_Column(2).Margin("4,0,0,0").IsEditable("True")
        rgGrid.Add("TextBlock").Name("TrueValueTipCon").Text(GetLang("真值")).Grid_Row(1).Grid_Column(0).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("TextBox").Name("TrueValueCon").Width(70).Height(24).MinHeight(24).Grid_Row(1).Grid_Column(1).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        rgGrid.Add("TextBlock").Name("FalseValueTipCon").Text(GetLang("假值")).Grid_Row(1).Grid_Column(2).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("TextBox").Name("FalseValueCon").Width(70).Height(24).MinHeight(24).Grid_Row(1).Grid_Column(3).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        cg := saveRow.Add("GroupBox").Grid_Column(1).Header(GetLang("目标点保存")).Margin("8,0,0,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("6,4")
        cgGrid := cg.Add("Grid")
        cgGrid.Cols("Auto", "Auto", "Auto", "Auto")
        cgGrid.Rows("28")
        cgGrid.Add("CheckBox").Name("CoordToogleCon").Content(GetLang("开关")).Grid_Row(0).Grid_Column(0).VerticalAlignment("Center")
        cgGrid.Add("TextBlock").Name("CoordXTipCon").Text(GetLang("坐标X变量名")).Grid_Row(0).Grid_Column(1).VerticalAlignment("Center").Margin("10,0,0,0")
        cgGrid.Add("ComboBox").Name("CoordXNameCon").Width(100).Height(24).MinHeight(24).Grid_Row(0).Grid_Column(2).Margin("4,0,0,0").IsEditable("True")
        cgGrid.Add("TextBlock").Name("CoordYTipCon").Text(GetLang("坐标Y变量名")).Grid_Row(0).Grid_Column(3).VerticalAlignment("Center").Margin("10,0,0,0")
        cgGrid.Add("ComboBox").Name("CoordYNameCon").Width(100).Height(24).MinHeight(24).Grid_Row(0).Grid_Column(4).Margin("4,0,0,0").IsEditable("True")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(6).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="860" Height="660" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTrigger", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnTargeter", "Click", ObjBindMethod(this, "OnClickTargeterBtn"))
        this.ui.OnEvent("BtnTargeterHelp", "Click", ObjBindMethod(this, "OnClickTargeterHelpBtn"))
        this.ui.OnEvent("BtnTypeHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("BtnWinRuleHelp", "Click", ObjBindMethod(this, "OnClickWinRuleHelpBtn"))
        this.ui.OnEvent("BtnEditScreenRule", "Click", ObjBindMethod(this, "OnEditScreenRule"))
        this.ui.OnEvent("SearchTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("ConfigDLCon", "SelectionChanged", ObjBindMethod(this, "OnChangeConfig"))
        this.ui.OnEvent("StartPosXCon", "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("StartPosYCon", "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("EndPosXCon", "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("EndPosYCon", "TextChanged", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("PreviewAreaCon", "Click", ObjBindMethod(this, "OnClickPreviewArea"))
        this.ui.OnEvent("SelectToggleCon", "Click", ObjBindMethod(this, "OnClickSelectToggle"))
        this.ui.OnEvent("MouseActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("ResultToggleCon", "Click", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("CoordToogleCon", "Click", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("BtnEditFoundMacro", "Click", ObjBindMethod(this, "OnEditFoundMacroBtnClick"))
        this.ui.OnEvent("FalseMacroEditBtn", "Click", ObjBindMethod(this, "OnEditUnFoundMacroBtnClick"))
        this.ui.OnEvent("ScreenshotBtn", "Click", ObjBindMethod(this, "OnScreenShotBtnClick"))
        this.ui.OnEvent("ImageSelectBtn", "Click", ObjBindMethod(this, "OnClickSetPicBtn"))
        this.ui.OnEvent("WinInfoEditBtn", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
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

    _AddCoordRow(grid, row, nameX, nameY, labelX, labelY) {
        grid.Add("TextBlock").Text(labelX).Grid_Row(row).Grid_Column(0).VerticalAlignment("Center")
        grid.Add("ComboBox").Name(nameX).Width(80).Height(24).MinHeight(24).Grid_Row(row).Grid_Column(1).Margin("4,0,0,0").IsEditable("True")
        grid.Add("TextBlock").Text(labelY).Grid_Row(row).Grid_Column(2).VerticalAlignment("Center").Margin("12,0,0,0")
        grid.Add("ComboBox").Name(nameY).Width(80).Height(24).MinHeight(24).Grid_Row(row).Grid_Column(3).Margin("4,0,0,0").IsEditable("True")
    }

    ; ---------------- 数据读写辅助 ----------------

    _SetCombo(comboName, items, text) {
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    _TypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("SearchTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return Integer(v) + 1
    }

    _ToggleInt(v) {
        return (v == 1 || v == "1" || v == true || v == "True") ? 1 : 0
    }

    _SetImage(path) {
        if (IsObject(this.ui))
            this.ui.Update("ImageCon", "Source", StrReplace(path, "\", "/"))
    }

    SetConArrState(ConArr, isEnabled, state) {
        prop := isEnabled ? "IsEnabled" : "Visibility"
        val := isEnabled ? (state ? "True" : "False") : (state ? "Visible" : "Collapsed")
        for name in ConArr
            this.ui.Update(name, prop, val)
    }

    ; ---------------- 数据 ----------------

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    OnClickWinEditBtn(*) {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    RefreshConfigDLArr() {
        Arr := []
        Arr.Push(this.Data.ConfigName)
        loop this.Data.ConfigArr.Length {
            CurConfigData := this.Data.ConfigArr[A_Index]
            if (ObjHasOwnProp(CurConfigData, "ConfigName"))
                Arr.Push(CurConfigData.ConfigName)
        }
        this.ConfigDLArr := Arr

        this._SetCombo("ConfigDLCon", this.ConfigDLArr, this.Data.ConfigName)
    }

    OnEditScreenRule(con, *) {
        if (this.RuleMenu == "") {
            this.ContextMenu := Menu()
            this.ContextMenu.Add(GetLang("修改"), (*) => this.OnRuleMenuHandler(GetLang("修改")))
            this.ContextMenu.Add(GetLang("增加"), (*) => this.OnRuleMenuHandler(GetLang("增加")))
            this.ContextMenu.Add(GetLang("删除"), (*) => this.OnRuleMenuHandler(GetLang("删除")))
        }
        this.ContextMenu.Show()
    }

    OnRuleMenuHandler(Str) {
        if (Str == GetLang("修改")) {
            if (!ObjHasOwnProp(this, "WinRuleGui")) {
                this.WinRuleGui := WinRuleGui()
            }
            SureAction(width, height, remark) {
                ConfigName := Format("{}*{}", width, height)
                if (remark != "")
                    ConfigName := Format("{}*{}_{}", width, height, remark)
                if (ConfigName == this.Data.ConfigName)
                    return
                loop this.ConfigDLArr.Length {
                    if (this.ConfigDLArr[A_Index] == ConfigName) {
                        MsgBox(Format("{} 配置已存在，修改失败", ConfigName))
                        return
                    }
                }

                this.Data.ConfigName := ConfigName
                this.RefreshConfigDLArr()
                saveStr := JSON.stringify(this.Data, 0)
                IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
                MsgBox(GetLang("修改成功"))
            }
            this.WinRuleGui.SureAction := SureAction
            if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
                this.WinRuleGui.OwnerHwnd := this.Hwnd()
            }
            else {
                this.WinRuleGui.OwnerHwnd := ""
            }
            this.WinRuleGui.ShowGui()
        }
        else if (Str == GetLang("增加"))
            this.OnAddConfig()
        else if (Str == GetLang("删除"))
            this.OnRemoveConfig()
    }

    OnAddConfig() {
        if (!ObjHasOwnProp(this, "WinRuleGui")) {
            this.WinRuleGui := WinRuleGui()
        }
        SureAction(width, height, remark) {
            ConfigName := Format("{}*{}", width, height)
            if (remark != "")
                ConfigName := Format("{}*{}_{}", width, height, remark)
            loop this.ConfigDLArr.Length {
                if (this.ConfigDLArr[A_Index] == ConfigName) {
                    MsgBox(Format("{} 配置已存在，无法重复添加", ConfigName))
                    return
                }
            }

            LastConfig := Object()
            LastConfig.ConfigName := this.Data.ConfigName
            LastConfig.SearchType := this._TypeIndex()
            LastConfig.SearchColor := this.ui.Query("HexColorCon")
            LastConfig.SearchText := this.ui.Query("TextCon")
            LastConfig.SearchImagePath := this.Data.SearchImagePath
            LastConfig.Similar := this.ui.Query("SimilarCon")
            LastConfig.OCRType := 1 ; v6 统一多语言模型，不再区分
            LastConfig.SearchImageType := this.ui.Query("SearchImageTypeCon>SelectedIndex") + 1
            LastConfig.StartPosX := this.ui.Query("StartPosXCon")
            LastConfig.StartPosY := this.ui.Query("StartPosYCon")
            LastConfig.EndPosX := this.ui.Query("EndPosXCon")
            LastConfig.EndPosY := this.ui.Query("EndPosYCon")
            LastConfig.SearchCount := this.ui.Query("SearchCountCon") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCon")
            LastConfig.SearchInterval := this.ui.Query("SearchIntervalCon")
            LastConfig.MouseActionType := this.ui.Query("MouseActionTypeCon>SelectedIndex") + 1
            LastConfig.Speed := this.ui.Query("SpeedCon")
            LastConfig.ClickCount := this.ui.Query("ClickCountCon")
            this.Data.ConfigArr.Push(LastConfig)

            this.Data.ConfigName := ConfigName
            this.RefreshConfigDLArr()
            saveStr := JSON.stringify(this.Data, 0)
            IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
            MsgBox(Format("{} 配置添加成功", ConfigName))
        }
        this.WinRuleGui.SureAction := SureAction
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            this.WinRuleGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.WinRuleGui.OwnerHwnd := ""
        }
        this.WinRuleGui.ShowGui()
    }

    OnRemoveConfig() {
        if (this.ConfigDLArr.Length <= 1) {
            MsgBox("最后选项不可删除！！！")
            return
        }

        result := MsgBox(Format(GetLang("是否删除 {} 配置"), this.ui.Query("ConfigDLCon")), GetLang("提示"), 1)
        if (result == "Cancel")
            return

        ConfigData := this.Data.ConfigArr[1]
        this.Data.ConfigArr.RemoveAt(1)
        this.Data.ConfigName := ConfigData.ConfigName
        this.Data.SearchType := ConfigData.SearchType
        this.Data.SearchColor := ConfigData.SearchColor
        this.Data.SearchText := ConfigData.SearchText
        this.Data.SearchImagePath := ConfigData.SearchImagePath
        this.Data.Similar := ConfigData.Similar
        this.Data.OCRType := ConfigData.OCRType
        this.Data.SearchImageType := ConfigData.SearchImageType
        this.Data.StartPosX := ConfigData.StartPosX
        this.Data.StartPosY := ConfigData.StartPosY
        this.Data.EndPosX := ConfigData.EndPosX
        this.Data.EndPosY := ConfigData.EndPosY
        this.Data.SearchCount := ConfigData.SearchCount
        this.Data.SearchInterval := ConfigData.SearchInterval
        this.Data.MouseActionType := ConfigData.MouseActionType
        this.Data.Speed := ConfigData.Speed
        this.Data.ClickCount := ConfigData.ClickCount
        saveStr := JSON.stringify(this.Data, 0)
        IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)

        CMDStr := this.GetCommandStr()
        this.Init(CMDStr)
    }

    OnChangeConfig(*) {
        ; 值守卫：程序化 _SetCombo 触发的 SelectionChanged 异步到达时选中项==当前配置，直接返回，避免重复保存/递归 Init
        if (this.ui.Query("ConfigDLCon") == this.Data.ConfigName)
            return
        LastConfig := Object()
        LastConfig.ConfigName := this.Data.ConfigName
        LastConfig.SearchType := this._TypeIndex()
        LastConfig.SearchColor := this.ui.Query("HexColorCon")
        LastConfig.SearchText := this.ui.Query("TextCon")
        LastConfig.SearchImagePath := this.Data.SearchImagePath
        LastConfig.Similar := this.ui.Query("SimilarCon")
        LastConfig.OCRType := 1 ; v6 统一多语言模型，不再区分
        LastConfig.SearchImageType := this.ui.Query("SearchImageTypeCon>SelectedIndex") + 1
        LastConfig.StartPosX := this.ui.Query("StartPosXCon")
        LastConfig.StartPosY := this.ui.Query("StartPosYCon")
        LastConfig.EndPosX := this.ui.Query("EndPosXCon")
        LastConfig.EndPosY := this.ui.Query("EndPosYCon")
        LastConfig.SearchCount := this.ui.Query("SearchCountCon") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCon")
        LastConfig.SearchInterval := this.ui.Query("SearchIntervalCon")
        LastConfig.MouseActionType := this.ui.Query("MouseActionTypeCon>SelectedIndex") + 1
        LastConfig.Speed := this.ui.Query("SpeedCon")
        LastConfig.ClickCount := this.ui.Query("ClickCountCon")
        this.Data.ConfigArr.Push(LastConfig)

        ConfigData := ""
        loop this.ConfigDLArr.Length {
            if (this.ui.Query("ConfigDLCon") == this.Data.ConfigArr[A_Index].ConfigName) {
                ConfigData := this.Data.ConfigArr.RemoveAt(A_Index)
                break
            }
        }

        if (ConfigData == "")
            return

        this.Data.ConfigName := ConfigData.ConfigName
        this.Data.SearchType := ConfigData.SearchType
        this.Data.SearchColor := ConfigData.SearchColor
        this.Data.SearchText := ConfigData.SearchText
        this.Data.SearchImagePath := ConfigData.SearchImagePath
        this.Data.Similar := ConfigData.Similar
        this.Data.OCRType := ConfigData.OCRType
        this.Data.SearchImageType := ConfigData.SearchImageType
        this.Data.StartPosX := ConfigData.StartPosX
        this.Data.StartPosY := ConfigData.StartPosY
        this.Data.EndPosX := ConfigData.EndPosX
        this.Data.EndPosY := ConfigData.EndPosY
        this.Data.SearchCount := ConfigData.SearchCount
        this.Data.SearchInterval := ConfigData.SearchInterval
        this.Data.MouseActionType := ConfigData.MouseActionType
        this.Data.Speed := ConfigData.Speed
        this.Data.ClickCount := ConfigData.ClickCount
        saveStr := JSON.stringify(this.Data, 0)
        IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
        CMDStr := this.GetCommandStr()
        this.Init(CMDStr)
    }

    CheckIfDataValid() {
        if (!ObjHasOwnProp(this.Data, "SearchImagePath")) {
            MsgBox(GetLang("这条指令不完整，请删除"))
            return false
        }
        return true
    }

    CheckIfValid() {
        curType := this._TypeIndex()
        isImage := curType == 1 || curType == 4
        isColor := curType == 2 || curType == 5
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6

        this.Data.SearchImagePath := this.ui.Query("ImagePathCon")
        if (IsNumber(this.ui.Query("StartPosXCon")) && IsNumber(this.ui.Query("StartPosYCon")) && IsNumber(this.ui.Query("EndPosXCon"))
        && IsNumber(this.ui.Query("EndPosYCon"))) {
            if (Number(this.ui.Query("StartPosXCon")) > Number(this.ui.Query("EndPosXCon")) || Number(this.ui.Query("StartPosYCon")) >
            Number(this.ui.Query("EndPosYCon"))) {
                MsgBox(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }

        if (this.ui.Query("SearchCountCon") == GetLang("无限")) {

        }
        else if (!IsNumber(this.ui.Query("SearchCountCon")) || Number(this.ui.Query("SearchCountCon")) <= 0) {
            MsgBox(GetLang("搜索次数请输入大于0的数字"))
            return false
        }

        if (isImage && this.Data.SearchImagePath == "") {
            MsgBox(GetLang("请设置搜索图片"))
            return false
        }

        if (isImage) {
            if (IsNumber(this.ui.Query("StartPosXCon")) && IsNumber(this.ui.Query("StartPosYCon"))
            && IsNumber(this.ui.Query("EndPosXCon")) && IsNumber(this.ui.Query("EndPosYCon"))
            && this.Data.SearchImagePath != "" && FileExist(this.Data.SearchImagePath)) {
                searchWidth := this.ui.Query("EndPosXCon") - this.ui.Query("StartPosXCon")
                searchHeight := this.ui.Query("EndPosYCon") - this.ui.Query("StartPosYCon")
                size := GetImageSize(this.Data.SearchImagePath)
                if (size[1] > searchWidth || size[2] > searchHeight) {
                    MsgBox(GetLang("搜索范围不能小于图片大小"))
                    return false
                }
            }
        }

        if (isText) {
            if (IsNumber(this.ui.Query("StartPosXCon")) && IsNumber(this.ui.Query("StartPosYCon"))
            && IsNumber(this.ui.Query("EndPosXCon")) && IsNumber(this.ui.Query("EndPosYCon"))) {
                if (this.ui.Query("StartPosXCon") == this.ui.Query("EndPosXCon") ||
                this.ui.Query("StartPosYCon") == this.ui.Query("EndPosYCon")) {
                    MsgBox(GetLang("搜索文本时：搜索范围中起始坐标不能和终止坐标相同"))
                    return false
                }
            }
        }

        if (isWin && this.ui.Query("WinInfoCon") == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (this.ui.Query("ResultToggleCon") == "True") {
            if (!CheckVarNameIfValid(this.ui.Query("ResultSaveNameCon")))
                return false
        }

        if (this.ui.Query("MouseActionTypeCon>SelectedIndex") + 1 != 1 && !isWin) {
            if (!IsNumber(this.ui.Query("SpeedCon")) || this.ui.Query("SpeedCon") < 0 || this.ui.Query("SpeedCon") > 100) {
                MsgBox(GetLang("移动速度请输入0~100的数字"))
                return false
            }
        }

        return true
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
            Hotkey("F2", (*) => this.OnScreenShotBtnClick(), "On")
            Hotkey("F3", (*) => this.SureColor(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
            Hotkey("F2", (*) => this.OnScreenShotBtnClick(), "Off")
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
        ColorText := StrReplace(Color, "0x", "")
        this.ui.Update("HexColorCon", "Text", ColorText)
        this.HexColor := ColorText
        this.ui.Update("HexColorTipCon", "Visibility", "Visible")
        this.ui.Update("HexColorTipCon", "Background", "#" ColorText)
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

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("屏幕搜索：在屏幕搜索目标")
        str2 := GetLang("窗口搜索：在符合目标的窗口搜索目标(支持后台，最小化)")
        str3 := GetLang("tip1：图片搜索：推荐32*32px，截取目标特征即可，不要包含会变化的背景")
        str4 := GetLang("tip2：文本搜索：支持正则表达式，推荐32*32px以上和多文本，单字符识别不准")
        str5 := GetLang("tip3：SC截图后如果调整大小，搜索范围需要手动选取")
        str6 := GetLang("tip4：窗口搜索时：搜索范围需要手动选取")
        str := Format("{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6)
        MsgBox(str, GetLang("搜索类型说明"))
    }

    OnClickWinRuleHelpBtn(*) {
        str1 := GetLang("此功能用于不同分辨率使用相同指令")
        str2 := GetLang("新设备和原设备分辨率不同时，可以增加屏幕规格选项，然后设置新的搜索目标和搜索范围进行适配")
        str3 := GetLang("tip1：个人使用请忽略这个功能选项")
        str4 := GetLang("tip2：导入他人配置时，建议新增屏幕规格后重新设置搜索目标、搜索范围")
        str := Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
        MsgBox(str, GetLang("屏幕规格功能说明"))
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

    OnClickSetPicBtn(*) {
        curPath := this.ui.Query("ImagePathCon")
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
            this._SetImage(path)
            this.Data.SearchImagePath := path
            this.ui.Update("ImagePathCon", "Text", path)
        }
    }

    OnScreenShotBtnClick(*) {
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
            imageSerial := GetNextImageSerial()
            filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
            SaveClipToBitmap(filePath)
            this._SetImage(filePath)
            this.Data.SearchImagePath := filePath
            this.ui.Update("ImagePathCon", "Text", filePath)
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

        imageSerial := GetNextImageSerial()
        filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
        ScreenShot(x1, y1, x2, y2, filePath)
        this._SetImage(filePath)
        this.Data.SearchImagePath := filePath
        this.ui.Update("ImagePathCon", "Text", filePath)
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

    OnChangeType(*) {
        curType := this._TypeIndex()
        isImage := curType == 1 || curType == 4
        isColor := curType == 2 || curType == 5
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6
        isInfinite := this.ui.Query("SearchCountCon") == GetLang("无限")
        showColorTip := isColor && RegExMatch(this.ui.Query("HexColorCon"), "^([0-9A-Fa-f]{6})$")

        this.SetConArrState(this.ImageVariArr, false, isImage)
        this.SetConArrState(this.ColorArr, false, isColor)
        this.ui.Update("HexColorTipCon", "Visibility", showColorTip ? "Visible" : "Collapsed")
        if (showColorTip)
            this.ui.Update("HexColorTipCon", "Background", "#" this.ui.Query("HexColorCon"))
        this.SetConArrState(this.TextArr, false, isText)

        this.SetConArrState(this.SimilarArr, false, !isText)
        this.SetConArrState(this.WinInfoArr, false, isWin)
        this.SetConArrState(this.FalseConArr, true, !isInfinite)

        if (!this.LastIsWin && isWin) {
            this.ui.Update("MouseActionTypeCon", "ClearItems", "")
            for it in GetLangArr(["无动作", "后台鼠标至目标点击", "后台鼠标至目标双击"])
                this.ui.Update("MouseActionTypeCon", "AddItem", it)
            this.ui.Update("MouseActionTypeCon", "SelectedIndex", "0")
        }
        if (this.LastIsWin && !isWin) {
            this.ui.Update("MouseActionTypeCon", "ClearItems", "")
            for it in GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
                this.ui.Update("MouseActionTypeCon", "AddItem", it)
            this.ui.Update("MouseActionTypeCon", "SelectedIndex", "0")
        }

        CountValue := this.ui.Query("SearchCountCon") == GetLang("无限") ? -1 : this.ui.Query("SearchCountCon")
        isCount := IsNumber(CountValue) && (CountValue == -1 || CountValue > 1)
        this.SetConArrState(this.CountTogArr, false, isCount)

        ; Query 在窗口未加载（wpfHwnd 为 0）时返回空串：Init 阶段 OnChangeType 会先跑一次，
        ; 加载后 Update 队列应用会触发 SelectionChanged 再跑一次修正，故此处需 IsNumber 保护（同 _TypeIndex）
        mouseAction := this.ui.Query("MouseActionTypeCon>SelectedIndex")
        isMouseSpeed := IsNumber(mouseAction) && mouseAction + 1 != 1 && !isWin
        this.SetConArrState(this.MouseSpeedArr, false, isMouseSpeed)

        isMouseClick := IsNumber(mouseAction) && mouseAction + 1 == 3 && !isWin
        this.SetConArrState(this.MouseClickArr, false, isMouseClick)

        isSaveResult := this.ui.Query("ResultToggleCon") == "True"
        this.SetConArrState(this.ResultTogArr, true, isSaveResult)

        isCoord := this.ui.Query("CoordToogleCon") == "True"
        this.SetConArrState(this.CoordTogArr, true, isCoord)

        this.LastIsWin := isWin
        this.RefreshPreviewArea()
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
        curType := this._TypeIndex()
        isWin := curType == 4 || curType == 5 || curType == 6
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]
        this.ui.Update("StartPosXCon", "Text", Point1[1])
        this.ui.Update("StartPosYCon", "Text", Point1[2])
        this.ui.Update("EndPosXCon", "Text", Point2[1])
        this.ui.Update("EndPosYCon", "Text", Point2[2])
        ; 程序化 Update 填数字不触发 TextChanged，需显式刷新预览（框选/取色后立即可见）
        this.RefreshPreviewArea()
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        this.ui.Update("SelectToggleCon", "IsChecked", "False")
        this.ui.Update("StartPosXCon", "Text", x1)
        this.ui.Update("StartPosYCon", "Text", y1)
        this.ui.Update("EndPosXCon", "Text", x2)
        this.ui.Update("EndPosYCon", "Text", y2)
        this.RefreshPreviewArea()
    }

    SureColor() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        CoordMode("Pixel", "Screen")
        Color := PixelGetColor(mouseX, mouseY, "Slow")
        ColorText := StrReplace(Color, "0x", "")
        this.ui.Update("HexColorCon", "Text", ColorText)
        this.HexColor := ColorText
        this.ui.Update("HexColorTipCon", "Visibility", "Visible")
        this.ui.Update("HexColorTipCon", "Background", "#" ColorText)
        this.OnSetSearchArea(mouseX, mouseY, mouseX, mouseY)
    }

    SaveSearchData() {
        data := this.Data
        data.SearchImagePath := this.ui.Query("ImagePathCon")
        data.Similar := this.ui.Query("SimilarCon")
        data.OCRType := 1 ; v6 统一多语言模型，不再区分
        data.SearchImageType := this.ui.Query("SearchImageTypeCon>SelectedIndex") + 1
        data.SearchType := this._TypeIndex()
        data.WinInfo := this.ui.Query("WinInfoCon")
        data.SearchColor := this.ui.Query("HexColorCon")
        data.SearchText := this.ui.Query("TextCon")
        data.StartPosX := this.ui.Query("StartPosXCon")
        data.StartPosY := this.ui.Query("StartPosYCon")
        data.EndPosX := this.ui.Query("EndPosXCon")
        data.EndPosY := this.ui.Query("EndPosYCon")
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
        startX := this.ui.Query("StartPosXCon")
        startY := this.ui.Query("StartPosYCon")
        endX := this.ui.Query("EndPosXCon")
        endY := this.ui.Query("EndPosYCon")

        if (!IsNumber(startX) || !IsNumber(startY) || !IsNumber(endX) || !IsNumber(endY)) {
            this.StopPreviewFollow()
            this.HidePreviewRect()
            return
        }

        startX := Number(startX)
        startY := Number(startY)
        endX := Number(endX)
        endY := Number(endY)

        curType := this._TypeIndex()
        isWin := curType == 4 || curType == 5 || curType == 6
        if (isWin) {
            hwndList := GetHwndList(this.ui.Query("WinInfoCon"))
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

        dataOk := this.CheckIfDataValid()
        this.RefreshConfigDLArr()
        this.ui.Update("SearchTypeCon", "SelectedIndex", String(Integer(ObjHasOwnProp(this.Data, "SearchType") ? this.Data.SearchType : 1) - 1))
        this.ui.Update("SimilarCon", "Text", this.Data.Similar)
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)
        this.ui.Update("SearchImageTypeCon", "SelectedIndex", String((this.Data.SearchImageType ? this.Data.SearchImageType : 1) - 1))
        this._SetCombo("ImagePathCon", this.DLVariableArr, this.Data.SearchImagePath)
        this._SetImage(this.Data.SearchImagePath)
        this._SetCombo("HexColorCon", this.DLVariableArr, this.Data.SearchColor)
        this._SetCombo("TextCon", this.DLVariableArr, this.Data.SearchText)
        this._SetCombo("StartPosXCon", this.DLVariableArr, this.Data.StartPosX)
        this._SetCombo("StartPosYCon", this.DLVariableArr, this.Data.StartPosY)
        this._SetCombo("EndPosXCon", this.DLVariableArr, this.Data.EndPosX)
        this._SetCombo("EndPosYCon", this.DLVariableArr, this.Data.EndPosY)
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

        curType := this._TypeIndex()
        isWin := curType == 4 || curType == 5 || curType == 6
        this.LastIsWin := isWin
        MouseDLArr := isWin ? GetLangArr(["无动作", "后台鼠标至目标点击", "后台鼠标至目标双击"]) : GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
        this.ui.Update("MouseActionTypeCon", "ClearItems", "")
        for it in MouseDLArr
            this.ui.Update("MouseActionTypeCon", "AddItem", it)
        this.ui.Update("MouseActionTypeCon", "SelectedIndex", String((this.Data.MouseActionType ? this.Data.MouseActionType : 2) - 1))
        this.OnChangeType()
        if (!dataOk)
            return
    }
}
