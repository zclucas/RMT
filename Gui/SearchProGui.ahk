#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 搜索Pro编辑器 —— 1.2.2 单目标界面的 XAML 版
; 去掉窗口/屏幕规格；公开接口：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
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
        this.SetAreaAction := (x1, y1, x2, y2) => this.OnSetSearchArea(x1, y1, x2, y2)
        this.CheckClipboardAction := () => this.CheckClipboard()
        this.Data := ""
        this.LastIsWin := ""
        this.MacroGui := ""
        this.DLVariableArr := []
        this.PreviewBorderArr := []
        this.PreviewFollowTimer := 0
        this.PreviewFollowing := false
        this.CountTogArr := ["SearchIntervalTipCon", "SearchIntervalCon"]
        this.MouseSpeedArr := ["SpeedTipCon", "SpeedCon"]
        this.MouseClickArr := ["ClickCountTipCon", "ClickCountCon"]
        this.ResultTogArr := ["ResultVarTipCon", "ResultSaveNameCon", "TrueValueTipCon", "TrueValueCon", "FalseValueTipCon", "FalseValueCon"]
        this.CoordTogArr := ["CoordXTipCon", "CoordXNameCon", "CoordYTipCon", "CoordYNameCon"]
        this.WinInfoArr := ["WinInfoPanel"]
        this.ImageVariArr := ["ImagePanel"]
        this.ColorArr := ["ColorPanel"]
        this.TextArr := ["TextPanel"]
        this.SimilarArr := ["SimilarTipCon", "SimilarCon"]
        this.FalseConArr := ["FalseMacroTipCon", "FalseMacroHost"]
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
        title := this.ParentTile GetLang("搜索Pro编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,10").ClipToBounds("False")
        body.Rows("28", "32", "Auto", "Auto", "Auto", "40")
        body.Cols("*", "12", "*")

        ; 行0：屏幕/窗口坐标 | 鼠标颜色
        posLeft := body.Add("Grid").Grid_Row(0).Grid_Column(0)
        posLeft.Cols("78", "8", "96", "16", "78", "8", "96")
        posLeft.Add("TextBlock").Grid_Column(0).Text(GetLang("屏幕坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        posLeft.Add("TextBlock").Grid_Column(2).Name("MousePosCon").Text("0,0").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        posLeft.Add("TextBlock").Grid_Column(4).Text(GetLang("窗口坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        posLeft.Add("TextBlock").Grid_Column(6).Name("MouseWinPosCon").Text("0,0").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        colorRight := body.Add("Grid").Grid_Row(0).Grid_Column(2)
        colorRight.Cols("Auto", "8", "56", "8", "20")
        colorRight.Add("TextBlock").Grid_Column(0).Text(GetLang("鼠标颜色：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        colorRight.Add("TextBlock").Grid_Column(2).Name("MouseColorCon").Text("FFFFFF").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        colorRight.Add("Border").Grid_Column(4).Name("MouseColorTipCon").Width(20).Height(20).Background("#FF0000")
            .BorderBrush("#FF4B5563").BorderThickness("1").VerticalAlignment("Center")

        ; 行1：搜索类型 | 备注 + 预览
        typeLeft := body.Add("Grid").Grid_Row(1).Grid_Column(0)
        typeLeft.Cols("78", "8", "160", "8", "28")
        typeLeft.Add("TextBlock").Grid_Column(0).Text(GetLang("搜索类型：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        stc := typeLeft.Add("ComboBox").Grid_Column(2).Name("SearchTypeCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for t in GetLangArr(["屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"])
            stc.Add("ComboBoxItem").Content(t)
        typeLeft.Add("Button").Grid_Column(4).Name("BtnTypeHelp").Width(28).Height(28).MinHeight(28).Padding("0").Cursor("Hand")
            .Content("?").FontSize("12").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        remarkRight := body.Add("Grid").Grid_Row(1).Grid_Column(2)
        remarkRight.Cols("Auto", "8", "160", "8", "Auto")
        remarkRight.Add("TextBlock").Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkRight.Add("TextBox").Grid_Column(2).Name("RemarkCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        remarkRight.Add("CheckBox").Grid_Column(4).Name("PreviewAreaCon").Content(GetLang("预览框选范围")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行2：坐标/次数/动作 | 图片/颜色/文本/窗口
        mid := body.Add("Grid").Grid_Row(2).Grid_ColumnSpan(3)
        mid.Cols("*", "12", "*")
        coord := mid.Add("Grid").Grid_Column(0)
        coord.Rows("32", "32", "32", "32", "32")
        coord.Cols("78", "8", "70", "8", "70", "52")
        coord.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("起始坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(coord, "StartPosXCon", 0, 2, 70)
        this._AddEditCombo(coord, "StartPosYCon", 0, 4, 70)
        coord.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("终止坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(coord, "EndPosXCon", 1, 2, 70)
        this._AddEditCombo(coord, "EndPosYCon", 1, 4, 70)
        coord.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("搜索次数：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(coord, "SearchCountCon", 2, 2, 70)
        intervalCell := coord.Add("StackPanel").Grid_Row(2).Grid_Column(4).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        intervalCell.Add("TextBlock").Name("SearchIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("0,0,6,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        intervalCell.Add("TextBox").Name("SearchIntervalCon").Width(56).Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        coord.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("鼠标动作：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        mac := coord.Add("ComboBox").Grid_Row(3).Grid_Column(2).Grid_ColumnSpan(4).Name("MouseActionTypeCon").Width(200).MaxWidth(200).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for t in GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
            mac.Add("ComboBoxItem").Content(t)
        coord.Add("TextBlock").Grid_Row(4).Grid_Column(0).Name("SpeedTipCon").Text(GetLang("移动速度：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        coord.Add("TextBox").Grid_Row(4).Grid_Column(2).Name("SpeedCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        coord.Add("TextBlock").Grid_Row(4).Grid_Column(4).Name("ClickCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        coord.Add("TextBox").Grid_Row(4).Grid_Column(5).Name("ClickCountCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        extra := mid.Add("Grid").Grid_Column(2).VerticalAlignment("Top")
        extra.Rows("Auto", "Auto")

        winPanel := extra.Add("Grid").Name("WinInfoPanel").Grid_Row(0).Margin("0,0,0,6").Visibility("Collapsed")
        winPanel.Cols("78", "8", "*", "8", "50")
        winPanel.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口信息:")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        winPanel.Add("TextBox").Grid_Column(2).Name("WinInfoCon").Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        winPanel.Add("Button").Grid_Column(4).Name("BtnWinEdit").Width(50).Height(28).MinHeight(28).Padding("0").Cursor("Hand")
            .Content(GetLang("编辑")).FontSize("11").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        typeHost := extra.Add("Grid").Grid_Row(1)
        imgPanel := typeHost.Add("Grid").Name("ImagePanel")
        imgPanel.Rows("32", "32", "80")
        imgPanel.Cols("78", "8", "80", "8", "80", "8", "*")
        imgPanel.Add("TextBlock").Grid_Row(0).Grid_Column(0).Name("SimilarTipCon").Text(GetLang("相似度(%)：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        imgPanel.Add("TextBox").Grid_Row(0).Grid_Column(2).Name("SimilarCon").Width(80).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgBtns := imgPanel.Add("StackPanel").Grid_Row(0).Grid_Column(4).Grid_ColumnSpan(3).Orientation("Horizontal").VerticalAlignment("Center")
        imgBtns.Add("Button").Name("ImageShotBtn").Width(28).Height(28).MinHeight(28).Padding("0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13").Content(Chr(0xE7A8))
            .ToolTip(GetLang("截图")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgBtns.Add("Button").Name("ImageSelectBtn").Width(28).Height(28).MinHeight(28).Padding("0").Margin("8,0,0,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13").Content(Chr(0xE8E5))
            .ToolTip(GetLang("选择图片")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgPanel.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("识别模型：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        imgModel := imgPanel.Add("ComboBox").Grid_Row(1).Grid_Column(2).Name("SearchImageTypeCon").Width(80).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgModel.Add("ComboBoxItem").Content("OpenCV")
        imgModel.Add("ComboBoxItem").Content(GetLang("RMT识图"))
        imgPrev := imgPanel.Add("Border").Grid_Row(2).Grid_Column(0).Grid_ColumnSpan(3).Name("ImagePreviewHost")
            .Width(80).Height(80).MinWidth(80).MinHeight(80).MaxWidth(80).MaxHeight(80)
            .HorizontalAlignment("Left").VerticalAlignment("Top").ClipToBounds("True")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgPrev.Add("Image").Name("ImageCon").Stretch("UniformToFill")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch")
        imgPanel.Add("ComboBox").Grid_Row(2).Grid_Column(4).Grid_ColumnSpan(3).Name("ImagePathCon").Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Top").IsEditable("True").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        clrPanel := typeHost.Add("StackPanel").Name("ColorPanel").Orientation("Horizontal").VerticalAlignment("Center").Visibility("Collapsed")
        clrPanel.Add("TextBlock").Text(GetLang("搜索颜色：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        clrPanel.Add("ComboBox").Name("HexColorCon").Width(90).Height(28).MinHeight(28).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        clrPanel.Add("Border").Name("HexColorTipCon").Width(20).Height(20).Background("#FF0000")
            .BorderBrush("#FF4B5563").BorderThickness("1").VerticalAlignment("Center").Margin("8,0,0,0")

        txtPanel := typeHost.Add("Grid").Name("TextPanel").Visibility("Collapsed")
        txtPanel.Rows("32", "32")
        txtPanel.Cols("78", "8", "*")
        txtPanel.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("搜索文本：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        txtPanel.Add("ComboBox").Grid_Row(0).Grid_Column(2).Name("TextCon").Height(28).MinHeight(28).IsEditable("True")
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        txtPanel.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("识别模型：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        ocr := txtPanel.Add("ComboBox").Grid_Row(1).Grid_Column(2).Name("OCRTypeCon").Width(120).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for t in GetLangArr(["中文", "英文"])
            ocr.Add("ComboBoxItem").Content(t)

        ; 行3：找到 / 未找到
        macroRow := body.Add("Grid").Grid_Row(3).Grid_ColumnSpan(3).Margin("0,4,0,0")
        macroRow.Cols("*", "12", "*")
        foundCol := macroRow.Add("Grid").Grid_Column(0)
        foundCol.Rows("22", "66")
        foundCol.Add("TextBlock").Grid_Row(0).Text(GetLang("找到后的指令：（可选）")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        foundHost := foundCol.Add("Grid").Grid_Row(1)
        foundHost.Rows("66")
        foundHost.Add("TextBox").Name("TrueMacroCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch").MinHeight("66")
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        foundHost.Add("Button").Name("BtnEditFoundMacro").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        missCol := macroRow.Add("Grid").Grid_Column(2)
        missCol.Rows("22", "66")
        missCol.Add("TextBlock").Grid_Row(0).Name("FalseMacroTipCon").Text(GetLang("未找到后的指令：（可选）")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        missHost := missCol.Add("Grid").Grid_Row(1).Name("FalseMacroHost")
        missHost.Rows("66")
        missHost.Add("TextBox").Name("FalseMacroCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch").MinHeight("66")
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        missHost.Add("Button").Name("BtnEditUnFoundMacro").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 行4：结果保存 | 目标点保存
        saveRow := body.Add("Grid").Grid_Row(4).Grid_ColumnSpan(3).Margin("0,6,0,0")
        saveRow.Cols("*", "12", "*")
        resCol := saveRow.Add("Grid").Grid_Column(0)
        resCol.Rows("24", "28")
        resCol.Cols("Auto", "8", "Auto", "8", "120", "8", "Auto", "8", "60", "8", "Auto", "8", "60")
        resCol.Add("CheckBox").Grid_Row(0).Grid_Column(0).Name("ResultToggleCon").Content(GetLang("结果保存")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        resCol.Add("TextBlock").Grid_Row(1).Grid_Column(0).Name("ResultVarTipCon").Text(GetLang("变量名")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(resCol, "ResultSaveNameCon", 1, 4, 120)
        resCol.Add("TextBlock").Grid_Row(1).Grid_Column(6).Name("TrueValueTipCon").Text(GetLang("真值")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        resCol.Add("TextBox").Grid_Row(1).Grid_Column(8).Name("TrueValueCon").Width(60).Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        resCol.Add("TextBlock").Grid_Row(1).Grid_Column(10).Name("FalseValueTipCon").Text(GetLang("假值")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        resCol.Add("TextBox").Grid_Row(1).Grid_Column(12).Name("FalseValueCon").Width(60).Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        coordCol := saveRow.Add("Grid").Grid_Column(2)
        coordCol.Rows("24", "28")
        coordCol.Cols("Auto", "8", "Auto", "8", "100", "8", "Auto", "8", "100")
        coordCol.Add("CheckBox").Grid_Row(0).Grid_Column(0).Name("CoordToogleCon").Content(GetLang("目标点保存")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        coordCol.Add("TextBlock").Grid_Row(1).Grid_Column(0).Name("CoordXTipCon").Text(GetLang("坐标X变量名")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(coordCol, "CoordXNameCon", 1, 4, 100)
        coordCol.Add("TextBlock").Grid_Row(1).Grid_Column(6).Name("CoordYTipCon").Text(GetLang("坐标Y变量名")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(coordCol, "CoordYNameCon", 1, 8, 100)

        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnSure", "4,0")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        winSize := 'Title="' this._EscapeXml(title) '" Width="720" SizeToContent="Height" Opacity="0"'
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', winSize)
        if (InStr(this.ui.xaml, 'Width="940"') || InStr(this.ui.xaml, 'Height="700"')) {
            cnt := 0
            this.ui.xaml := RegExReplace(this.ui.xaml, 'Width="[^"]+" Height="[^"]+"', winSize, &cnt, 1)
        }
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/4-搜索Pro", (*) => this.TriggerMacro(), "!l"
            , ObjBindMethod(this, "OnClickTargeterBtn"), ObjBindMethod(this, "OnF1")
            , ObjBindMethod(this, "OnImageShotBtnClick"), ObjBindMethod(this, "SureColor"))
        try this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：框选范围"))
        try this.ui.Update("BtnCmdTargeter", "ToolTip", GetLang("定位取色器"))
        this.ui.OnEvent("SearchTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("BtnTypeHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("PreviewAreaCon", "Click", ObjBindMethod(this, "OnClickPreviewArea"))
        this.ui.OnEvent("SearchCountCon", "LostFocus", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("MouseActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("ResultToggleCon", "Click", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("CoordToogleCon", "Click", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("HexColorCon", "TextChanged", ObjBindMethod(this, "OnHexColorChange"))
        this.ui.OnEvent("ImageShotBtn", "Click", ObjBindMethod(this, "OnImageShotBtnClick"))
        this.ui.OnEvent("ImageSelectBtn", "Click", ObjBindMethod(this, "OnClickSetPicBtn"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnEditFoundMacro", "Click", ObjBindMethod(this, "OnEditFoundMacroBtnClick"))
        this.ui.OnEvent("BtnEditUnFoundMacro", "Click", ObjBindMethod(this, "OnEditUnFoundMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("StartPosXCon", "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("StartPosYCon", "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("EndPosXCon", "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.OnEvent("EndPosYCon", "LostFocus", ObjBindMethod(this, "RefreshPreviewArea"))
        this.ui.Update("MouseActionTypeCon", "SelectedIndex", "1")
    }

    _AddEditCombo(parent, name, row, col, width) {
        parent.Add("ComboBox").Grid_Row(row).Grid_Column(col).Name(name).Width(width).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center")
            .IsEditable("True").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
    }

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

    _ToggleInt(v) {
        return (v == 1 || v == "1" || v == true || v == "True") ? 1 : 0
    }

    _IsChecked(name) {
        v := IsObject(this.ui) ? this.ui.Query(name) : ""
        return v == "True" || v == "1" || v == 1
    }

    _TypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("SearchTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return Integer(v) + 1
    }

    _SetImage(path) {
        if (IsObject(this.ui))
            this.ui.Update("ImageCon", "Source", path != "" ? StrReplace(path, "\", "/") : "")
    }

    SetConArrState(ConArr, isEnabled, state) {
        prop := isEnabled ? "IsEnabled" : "Visibility"
        val := isEnabled ? (state ? "True" : "False") : (state ? "Visible" : "Collapsed")
        for name in ConArr
            this.ui.Update(name, prop, val)
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("搜索Pro")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        this._SyncFromFirstTarget()
        if (!this.CheckIfDataValid())
            return

        st := (IsNumber(this.Data.SearchType) && this.Data.SearchType >= 1 && this.Data.SearchType <= 6) ? Integer(this.Data.SearchType) : 1
        this.ui.Update("SearchTypeCon", "SelectedIndex", String(st - 1))
        this.ui.Update("SimilarCon", "Text", this.Data.Similar)
        this.ui.Update("OCRTypeCon", "SelectedIndex", String(Max(0, Integer(this.Data.OCRType) - 1)))
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)
        this.ui.Update("SearchImageTypeCon", "SelectedIndex", String(Max(0, Integer(this.Data.SearchImageType) - 1)))
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
        this.ui.Update("ResultToggleCon", "IsChecked", this._ToggleInt(this.Data.ResultToggle) ? "True" : "False")
        this._SetCombo("ResultSaveNameCon", this.DLVariableArr, this.Data.ResultSaveName)
        this.ui.Update("TrueValueCon", "Text", this.Data.TrueValue)
        this.ui.Update("FalseValueCon", "Text", this.Data.FalseValue)
        this.ui.Update("CoordToogleCon", "IsChecked", this._ToggleInt(this.Data.CoordToogle) ? "True" : "False")
        this._SetCombo("CoordXNameCon", this.DLVariableArr, this.Data.CoordXName)
        this._SetCombo("CoordYNameCon", this.DLVariableArr, this.Data.CoordYName)

        isWin := st == 4 || st == 5 || st == 6
        this.LastIsWin := isWin
        this._ApplyMouseActionItems(isWin, this.Data.MouseActionType)
        this.OnChangeType()
    }

    _SyncFromFirstTarget() {
        data := this.Data
        if (!ObjHasOwnProp(data, "SearchTargetArr") || !IsObject(data.SearchTargetArr) || data.SearchTargetArr.Length < 1)
            return
        t := data.SearchTargetArr[1]
        for key in ["SearchType", "WinInfo", "SearchColor", "SearchText", "SearchImagePath", "Similar", "OCRType", "SearchImageType", "StartPosX", "StartPosY", "EndPosX", "EndPosY"] {
            if (ObjHasOwnProp(t, key))
                data.%key% := t.%key%
        }
    }

    _ApplyMouseActionItems(isWin, sel) {
        items := isWin ? GetLangArr(["无动作", "后台鼠标至目标点击", "后台鼠标至目标双击"]) : GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
        this.ui.Update("MouseActionTypeCon", "ClearItems", "")
        for t in items
            this.ui.Update("MouseActionTypeCon", "AddItem", t)
        idx := (IsNumber(sel) && Integer(sel) >= 1) ? Integer(sel) - 1 : 1
        this.ui.Update("MouseActionTypeCon", "SelectedIndex", String(Max(0, Min(2, idx))))
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    CheckIfDataValid() {
        if (!ObjHasOwnProp(this.Data, "SearchImagePath")) {
            MsgBox(GetLang("这条指令不完整，请删除"))
            return false
        }
        return true
    }

    CheckIfValid() {
        sx := this.ui.Query("StartPosXCon")
        sy := this.ui.Query("StartPosYCon")
        ex := this.ui.Query("EndPosXCon")
        ey := this.ui.Query("EndPosYCon")
        curType := this._TypeIndex()
        isImage := curType == 1 || curType == 4
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6

        if (IsNumber(sx) && IsNumber(sy) && IsNumber(ex) && IsNumber(ey)) {
            if (Number(sx) > Number(ex) || Number(sy) > Number(ey)) {
                MsgBox(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }

        countText := this.ui.Query("SearchCountCon")
        if (countText != GetLang("无限") && (!IsNumber(countText) || Number(countText) <= 0)) {
            MsgBox(GetLang("搜索次数请输入大于0的数字"))
            return false
        }

        imgPath := this.ui.Query("ImagePathCon")
        if (isImage && imgPath == "") {
            MsgBox(GetLang("请设置搜索图片"))
            return false
        }
        if (isImage && IsNumber(sx) && IsNumber(sy) && IsNumber(ex) && IsNumber(ey) && imgPath != "" && FileExist(imgPath)) {
            size := GetImageSize(imgPath)
            if (size[1] > Number(ex) - Number(sx) || size[2] > Number(ey) - Number(sy)) {
                MsgBox(GetLang("搜索范围不能小于图片大小"))
                return false
            }
        }
        if (isText && IsNumber(sx) && IsNumber(sy) && IsNumber(ex) && IsNumber(ey)) {
            if (Number(sx) == Number(ex) || Number(sy) == Number(ey)) {
                MsgBox(GetLang("搜索文本时：搜索范围中起始坐标不能和终止坐标相同"))
                return false
            }
        }
        if (isWin && this.ui.Query("WinInfoCon") == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }
        if (this._IsChecked("ResultToggleCon") && !CheckVarNameIfValid(this.ui.Query("ResultSaveNameCon")))
            return false

        mIdx := this.ui.Query("MouseActionTypeCon>SelectedIndex")
        ma := (IsNumber(mIdx) && Integer(mIdx) >= 0) ? Integer(mIdx) + 1 : 1
        if (ma != 1 && !isWin) {
            spd := this.ui.Query("SpeedCon")
            if (!IsNumber(spd) || Number(spd) < 0 || Number(spd) > 100) {
                MsgBox(GetLang("移动速度请输入0~100的数字"))
                return false
            }
        }
        return true
    }

    SaveSearchData() {
        data := this.Data
        data.SearchImagePath := this.ui.Query("ImagePathCon")
        data.Similar := this.ui.Query("SimilarCon")
        ocr := this.ui.Query("OCRTypeCon>SelectedIndex")
        data.OCRType := (IsNumber(ocr) && Integer(ocr) >= 0) ? Integer(ocr) + 1 : 1
        imgType := this.ui.Query("SearchImageTypeCon>SelectedIndex")
        data.SearchImageType := (IsNumber(imgType) && Integer(imgType) >= 0) ? Integer(imgType) + 1 : 1
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
        mIdx := this.ui.Query("MouseActionTypeCon>SelectedIndex")
        data.MouseActionType := (IsNumber(mIdx) && Integer(mIdx) >= 0) ? Integer(mIdx) + 1 : 1
        data.ClickCount := this.ui.Query("ClickCountCon")
        data.Speed := this.ui.Query("SpeedCon")
        data.TrueMacro := GetLangMacro(this.ui.Query("TrueMacroCon"), 2)
        data.FalseMacro := GetLangMacro(this.ui.Query("FalseMacroCon"), 2)
        data.ResultToggle := this._IsChecked("ResultToggleCon") ? 1 : 0
        data.ResultSaveName := GetVarName(this.ui.Query("ResultSaveNameCon"))
        data.TrueValue := this.ui.Query("TrueValueCon")
        data.FalseValue := this.ui.Query("FalseValueCon")
        data.CoordToogle := this._IsChecked("CoordToogleCon") ? 1 : 0
        data.CoordXName := this.ui.Query("CoordXNameCon")
        data.CoordYName := this.ui.Query("CoordYNameCon")
        data.SearchTargetArr := []
        if (data.ResultToggle)
            MySoftData.GlobalVariMap[data.ResultSaveName] := true
        if (data.CoordToogle) {
            MySoftData.GlobalVariMap[data.CoordXName] := true
            MySoftData.GlobalVariMap[data.CoordYName] := true
        }
        SaveMacroCMDData(data)
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
            Hotkey("F2", (*) => this.OnImageShotBtnClick(), "On")
            Hotkey("F3", (*) => this.SureColor(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            try TogSelectArea(false)
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
            Hotkey("F2", (*) => this.OnImageShotBtnClick(), "Off")
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
            this.ui.Update("MouseColorTipCon", "BorderBrush", this._SwatchContrastStroke(ColorText))
            this.ui.Update("MouseColorTipCon", "BorderThickness", "1")
        }
    }

    OnChangeType(*) {
        curType := this._TypeIndex()
        isImage := curType == 1 || curType == 4
        isColor := curType == 2 || curType == 5
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6
        isInfinite := this.ui.Query("SearchCountCon") == GetLang("无限")
        this.SetConArrState(this.ImageVariArr, false, isImage)
        this.SetConArrState(this.ColorArr, false, isColor)
        this.SetConArrState(this.TextArr, false, isText)
        this.SetConArrState(this.SimilarArr, false, !isText)
        this.SetConArrState(this.WinInfoArr, false, isWin)
        this.SetConArrState(this.FalseConArr, true, !isInfinite)
        if (isColor)
            this._ApplyColorSwatch()
        if (this.LastIsWin != "" && this.LastIsWin != isWin)
            this._ApplyMouseActionItems(isWin, 1)
        countText := this.ui.Query("SearchCountCon")
        countValue := countText == GetLang("无限") ? -1 : countText
        this.SetConArrState(this.CountTogArr, false, IsNumber(countValue) && (countValue == -1 || countValue > 1))
        mIdx := this.ui.Query("MouseActionTypeCon>SelectedIndex")
        ma := (IsNumber(mIdx) && Integer(mIdx) >= 0) ? Integer(mIdx) + 1 : 1
        this.SetConArrState(this.MouseSpeedArr, false, ma != 1 && !isWin)
        this.SetConArrState(this.MouseClickArr, false, ma == 3 && !isWin)
        this.SetConArrState(this.ResultTogArr, true, this._IsChecked("ResultToggleCon"))
        this.SetConArrState(this.CoordTogArr, true, this._IsChecked("CoordToogleCon"))
        this.LastIsWin := isWin
        this.RefreshPreviewArea()
    }

    OnHexColorChange(*) {
        this._ApplyColorSwatch()
    }

    _ApplyColorSwatch(hex := "") {
        if (!IsObject(this.ui))
            return
        if (hex == "")
            hex := this.ui.Query("HexColorCon")
        hex := StrReplace(StrReplace(hex, "#", ""), "0x", "")
        if (!RegExMatch(hex, "^([0-9A-Fa-f]{6})$")) {
            this.ui.Update("HexColorTipCon", "Visibility", "Collapsed")
            return
        }
        this.ui.Update("HexColorTipCon", "Visibility", "Visible")
        this.ui.Update("HexColorTipCon", "Background", "#" hex)
        this.ui.Update("HexColorTipCon", "BorderBrush", this._SwatchContrastStroke(hex))
        this.ui.Update("HexColorTipCon", "BorderThickness", "1")
    }

    _SwatchContrastStroke(hex) {
        r := Integer("0x" SubStr(hex, 1, 2))
        g := Integer("0x" SubStr(hex, 3, 2))
        b := Integer("0x" SubStr(hex, 5, 2))
        luma := 0.299 * r + 0.587 * g + 0.114 * b
        bgLuma := 245
        try {
            theme := ""
            if (IsSet(MainSoftData) && IsObject(MainSoftData) && MainSoftData.HasProp("Theme"))
                theme := MainSoftData.Theme
            if (InStr(theme, "Dark") || InStr(theme, "暗"))
                bgLuma := 40
        }
        if (Abs(luma - bgLuma) >= 80)
            return luma >= 128 ? "#FFD1D5DB" : "#FF6B7280"
        return luma >= 140 ? "#FF334155" : "#FFE2E8F0"
    }

    OnClickTypeHelpBtn(*) {
        str := Format("{}`n{}`n{}`n{}`n{}`n{}", GetLang("屏幕搜索：在屏幕搜索目标"), GetLang("窗口搜索：在符合目标的窗口搜索目标(支持后台，最小化)")
            , GetLang("tip1：图片搜索：推荐32*32px，截取目标特征即可，不要包含会变化的背景")
            , GetLang("tip2：文本搜索：支持正则表达式，推荐32*32px以上和多文本，单字符识别不准")
            , GetLang("tip3：SC截图后如果调整大小，搜索范围需要手动选取")
            , GetLang("tip4：窗口搜索时：搜索范围需要手动选取"))
        MsgBox(str, GetLang("搜索类型说明"))
    }

    OnClickWinEditBtn(*) {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0)
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        else
            MyFrontInfoGui.OwnerHwnd := ""
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveSearchData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.OnGuiClose()
    }

    OnClickSetPicBtn(*) {
        curPath := this.ui.Query("ImagePathCon")
        path := FileSelect(1, curPath, GetLang("选择图片"), "PNG Files (*.png)")
        if (path == "")
            return
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

    OnImageShotBtnClick(*) {
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
        this.OnSetSearchArea(Max(0, x1 - 20), Max(0, y1 - 20), Min(A_ScreenWidth, x2 + 20), Min(A_ScreenHeight, y2 + 20))
    }

    OnSureTarget(PosX, PosY, Color) {
        ColorText := StrReplace(Color, "0x", "")
        this.ui.Update("HexColorCon", "Text", ColorText)
        this._ApplyColorSwatch(ColorText)
        this.OnSetSearchArea(PosX, PosY, PosX, PosY)
    }

    OnClickTargeterBtn(*) {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
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
        this.ui.Update("TrueMacroCon", "Text", GetLangMacro(CommandStr, 1))
    }

    OnSureUnFoundMacroBtnClick(CommandStr) {
        this.ui.Update("FalseMacroCon", "Text", GetLangMacro(CommandStr, 1))
    }

    OnEditFoundMacroBtnClick(*) {
        this._OpenMacroEditor(true)
    }

    OnEditUnFoundMacroBtnClick(*) {
        this._OpenMacroEditor(false)
    }

    _OpenMacroEditor(isFound) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            this.MacroGui.SureFocusCon := {Focus: (*) => ""}
            this.MacroGui.ParentTile := StrReplace(this._title, GetLang("编辑器"), "") "-"
        }
        this.MacroGui.OwnerHwnd := (MainSoftData.IsModalSubGui && this.Hwnd() != 0) ? this.Hwnd() : ""
        this.MacroGui.SureBtnAction := isFound ? (command) => this.OnSureFoundMacroBtnClick(command) : (command) => this.OnSureUnFoundMacroBtnClick(command)
        this.MacroGui.ShowGui(this.ui.Query(isFound ? "TrueMacroCon" : "FalseMacroCon"), false)
    }

    TriggerMacro() {
        if (!this.CheckIfValid())
            return
        this.SaveSearchData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnF1() {
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        isWin := this._TypeIndex() >= 4
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]
        this.OnSetSearchArea(Point1[1], Point1[2], Point2[1], Point2[2])
    }

    OnSetSearchArea(x1, y1, x2, y2) {
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
        this._ApplyColorSwatch(ColorText)
        this.OnSetSearchArea(mouseX, mouseY, mouseX, mouseY)
    }

    OnClickPreviewArea(*) {
        this.RefreshPreviewArea()
    }

    RefreshPreviewArea(*) {
        if (!IsObject(this.ui) || this.ui.Query("PreviewAreaCon") != "True") {
            this.StopPreviewFollow()
            this.HidePreviewRect()
            return
        }
        startX := this.ui.Query("StartPosXCon"), startY := this.ui.Query("StartPosYCon")
        endX := this.ui.Query("EndPosXCon"), endY := this.ui.Query("EndPosYCon")
        if (!IsNumber(startX) || !IsNumber(startY) || !IsNumber(endX) || !IsNumber(endY)) {
            this.StopPreviewFollow()
            this.HidePreviewRect()
            return
        }
        startX := Number(startX), startY := Number(startY), endX := Number(endX), endY := Number(endY)
        isWin := this._TypeIndex() >= 4
        if (isWin) {
            hwndList := GetHwndList(this.ui.Query("WinInfoCon"))
            if (hwndList.Length == 0) {
                this.StopPreviewFollow()
                this.HidePreviewRect()
                return
            }
            startPt := this.WinToScreen(hwndList[1], startX, startY)
            endPt := this.WinToScreen(hwndList[1], endX, endY)
            startX := startPt[1], startY := startPt[2], endX := endPt[1], endY := endPt[2]
        }
        x := Min(startX, endX), y := Min(startY, endY), w := Abs(endX - startX), h := Abs(endY - startY)
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
        else if (!isWin && this.PreviewFollowing)
            this.StopPreviewFollow()
    }

    StopPreviewFollow() {
        if (this.PreviewFollowTimer != 0) {
            try SetTimer(this.PreviewFollowTimer, 0)
            this.PreviewFollowTimer := 0
        }
        this.PreviewFollowing := false
    }

    PreviewFollowTick() {
        if (!IsObject(this.ui) || this.ui.Query("PreviewAreaCon") != "True") {
            this.StopPreviewFollow()
            return
        }
        this.RefreshPreviewArea()
    }

    WinToScreen(hwnd, winX, winY) {
        DllCall("SetProcessDPIAware")
        rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
        pt := Buffer(8, 0)
        NumPut("int", winX, pt, 0)
        NumPut("int", winY, pt, 4)
        DllCall("User32\ClientToScreen", "ptr", rootHwnd, "ptr", pt)
        return [NumGet(pt, 0, "int"), NumGet(pt, 4, "int")]
    }

    ShowPreviewRect(x, y, w, h) {
        borderW := 2
        if (this.PreviewBorderArr.Length == 0) {
            for item in [[x, y, w, borderW], [x, y + h - borderW, w, borderW], [x, y, borderW, h], [x + w - borderW, y, borderW, h]] {
                g := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x20 -DPIScale")
                g.BackColor := "Red"
                g.Show("NA x" item[1] " y" item[2] " w" item[3] " h" item[4])
                this.PreviewBorderArr.Push(g)
            }
        }
        else {
            this.PreviewBorderArr[1].Move(x, y, w, borderW)
            this.PreviewBorderArr[2].Move(x, y + h - borderW, w, borderW)
            this.PreviewBorderArr[3].Move(x, y, borderW, h)
            this.PreviewBorderArr[4].Move(x + w - borderW, y, borderW, h)
        }
    }

    HidePreviewRect() {
        for g in this.PreviewBorderArr {
            try g.Destroy()
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
}
