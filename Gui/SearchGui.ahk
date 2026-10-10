#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 搜索编辑器 —— XAML 迁移版
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 截图/取色/框选联动（OnScreenShotGetArea / SetAreaAction / F1Action / OnSetSearchArea / OnGetArea）原样保留
; 数据读写（GetMacroCMDData / SaveSearchData / GetCommandStr）不变
; =====================================================================

class SearchGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this._closed := true
        this.PosAction := () => this.RefreshMouseInfo()
        this.F1Action := (x1, y1, x2, y2) => this.OnF1SetAreaAction(x1, y1, x2, y2)
        this.SetAreaAction := (x1, y1, x2, y2) => this.OnSetSearchArea(x1, y1, x2, y2)
        this.CheckClipboardAction := () => this.CheckClipboard()
        this.Data := ""
        this.MacroGui := ""
        ; 文本搜索显隐控件名数组（OnChangeSearchType 用）
        this.TextArr := ["TextTipCon", "TextCon"]
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
        title := this.ParentTile GetLang("搜索编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,10").ClipToBounds("False")
        body.Rows("28", "32", "Auto", "Auto", "40")
        body.Cols("*", "12", "*")

        ; 行0：屏幕坐标 | 鼠标颜色（颜色与备注左对齐，不随坐标位数左右挪）
        posLeft := body.Add("Grid").Grid_Row(0).Grid_Column(0)
        posLeft.Cols("78", "8", "96")
        posLeft.Add("TextBlock").Grid_Column(0).Text(GetLang("屏幕坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        posLeft.Add("TextBlock").Grid_Column(2).Name("MousePosCon").Text("0,0").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        colorRight := body.Add("Grid").Grid_Row(0).Grid_Column(2)
        colorRight.Cols("Auto", "8", "56", "8", "20")
        colorRight.Add("TextBlock").Grid_Column(0).Text(GetLang("鼠标颜色：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        colorRight.Add("TextBlock").Grid_Column(2).Name("MouseColorCon").Text("FFFFFF").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        colorRight.Add("Border").Grid_Column(4).Name("MouseColorTipCon").Width(20).Height(20).Background("#FF0000")
            .BorderBrush("#FF4B5563").BorderThickness("1").VerticalAlignment("Center")

        ; 行1：搜索类型 | 备注（备注与未找到指令左对齐）
        typeLeft := body.Add("Grid").Grid_Row(1).Grid_Column(0)
        typeLeft.Cols("78", "8", "130")
        typeLeft.Add("TextBlock").Grid_Column(0).Text(GetLang("搜索类型：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        stc := typeLeft.Add("ComboBox").Grid_Column(2).Name("SearchTypeCon").Width(130).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for t in GetLangArr(["屏幕图片", "屏幕颜色", "屏幕文本"])
            stc.Add("ComboBoxItem").Content(t)
        remarkRight := body.Add("Grid").Grid_Row(1).Grid_Column(2)
        remarkRight.Cols("Auto", "8", "160")
        remarkRight.Add("TextBlock").Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkRight.Add("TextBox").Grid_Column(2).Name("RemarkCon").Width(160).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 行2：坐标 | 图片/颜色/文本
        mid := body.Add("Grid").Grid_Row(2).Grid_ColumnSpan(3)
        mid.Cols("*", "12", "*")
        coord := mid.Add("Grid").Grid_Column(0)
        coord.Rows("32", "32", "32")
        coord.Cols("78", "8", "70", "8", "70", "52")
        coord.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("起始坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        coord.Add("TextBox").Grid_Row(0).Grid_Column(2).Name("StartPosXCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        coord.Add("TextBox").Grid_Row(0).Grid_Column(4).Name("StartPosYCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        coord.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("终止坐标：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        coord.Add("TextBox").Grid_Row(1).Grid_Column(2).Name("EndPosXCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        coord.Add("TextBox").Grid_Row(1).Grid_Column(4).Name("EndPosYCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        extra := mid.Add("Grid").Grid_Column(2).VerticalAlignment("Top")
        imgPanel := extra.Add("Grid").Name("ImagePanel")
        imgPanel.Rows("32", "80")
        imgPanel.Cols("80")
        imgBtns := imgPanel.Add("StackPanel").Grid_Row(0).Orientation("Horizontal")
        imgBtns.Add("Button").Name("ImageShotBtn").Width(28).Height(28).MinHeight(28).Padding("0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13").Content(Chr(0xE7A8))
            .ToolTip(GetLang("截图")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgBtns.Add("Button").Name("ImageSelectBtn").Width(28).Height(28).MinHeight(28).Padding("0").Margin("8,0,0,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13").Content(Chr(0xE8E5))
            .ToolTip(GetLang("选择图片")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgPrev := imgPanel.Add("Border").Grid_Row(1).Name("ImagePreviewHost")
            .Width(80).Height(80).MinWidth(80).MinHeight(80).MaxWidth(80).MaxHeight(80)
            .HorizontalAlignment("Left").VerticalAlignment("Top").ClipToBounds("True")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        imgPrev.Add("Image").Name("ImageCon").Stretch("UniformToFill")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch")

        clrPanel := extra.Add("StackPanel").Name("ColorPanel").Orientation("Horizontal").VerticalAlignment("Center").Visibility("Collapsed")
        clrPanel.Add("TextBlock").Name("ColorTipCon").Text(GetLang("搜索颜色：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        clrPanel.Add("TextBox").Name("HexColorCon").Text("FFFFFF").Width(90).Height(28).MinHeight(28).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("2,0").TextAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        clrPanel.Add("Border").Name("HexColorTipCon").Width(20).Height(20).Background("#FF0000")
            .BorderBrush("#FF4B5563").BorderThickness("1").VerticalAlignment("Center").Margin("8,0,0,0")

        txtPanel := extra.Add("Grid").Name("TextPanel").Visibility("Collapsed")
        txtPanel.Rows("22", "28")
        txtPanel.Add("TextBlock").Name("TextTipCon").Grid_Row(0).Text(GetLang("搜索文本：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        txtPanel.Add("TextBox").Name("TextCon").Grid_Row(1).Text(GetLang("检索文本")).Height(28).MinHeight(28)
            .HorizontalAlignment("Stretch").VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        coord.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("鼠标动作：")).VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        mac := coord.Add("ComboBox").Grid_Row(2).Grid_Column(2).Grid_ColumnSpan(4).Name("MouseActionTypeCon").Width(200).MaxWidth(200).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for t in GetLangArr(["无动作", "移动至目标", "移动至目标点击1次", "移动至目标点击2次"])
            mac.Add("ComboBoxItem").Content(t)

        ; 行3：找到 / 未找到（三行高 + 右上角悬浮编辑）
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
        missCol.Add("TextBlock").Grid_Row(0).Text(GetLang("未找到后的指令：（可选）")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        missHost := missCol.Add("Grid").Grid_Row(1)
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

        ; 行4：确定
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnSure", "4,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        winSize := 'Title="' this._EscapeXml(title) '" Width="640" SizeToContent="Height" Opacity="0"'
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', winSize)
        if (InStr(this.ui.xaml, 'Width="940"') || InStr(this.ui.xaml, 'Height="700"')) {
            cnt := 0
            this.ui.xaml := RegExReplace(this.ui.xaml, 'Width="[^"]+" Height="[^"]+"', winSize, &cnt, 1)
        }
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/3-搜索", (*) => this.TriggerMacro(), "!l"
            , ObjBindMethod(this, "OnClickTargeterBtn"), ObjBindMethod(this, "OnF1")
            , ObjBindMethod(this, "OnImageShotBtnClick"), ObjBindMethod(this, "SureColor"))
        try this.ui.Update("BtnCmdF1", "ToolTip", GetLang("F1：框选范围"))
        try this.ui.Update("BtnCmdTargeter", "ToolTip", GetLang("定位取色器"))
        this.ui.OnEvent("SearchTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeSearchType"))
        this.ui.OnEvent("HexColorCon", "TextChanged", ObjBindMethod(this, "OnHexColorChange"))
        this.ui.OnEvent("ImageShotBtn", "Click", ObjBindMethod(this, "OnImageShotBtnClick"))
        this.ui.OnEvent("ImageSelectBtn", "Click", ObjBindMethod(this, "OnClickSetPicBtn"))
        this.ui.OnEvent("BtnEditFoundMacro", "Click", ObjBindMethod(this, "OnEditFoundMacroBtnClick"))
        this.ui.OnEvent("BtnEditUnFoundMacro", "Click", ObjBindMethod(this, "OnEditUnFoundMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))

        ; 原生 AddGui 中 MouseActionTypeCon 默认 Value=2（移动至目标）；XAML 默认索引 0，这里先复位为索引 1
        ; （Init 会用 Data.MouseActionType 覆盖；数据校验失败提前 return 时也能保持原生默认）
        this.ui.Update("MouseActionTypeCon", "SelectedIndex", "1")

    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("搜索")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        if (!this.CheckIfDataValid())
            return

        st := (IsNumber(this.Data.SearchType) && this.Data.SearchType >= 1 && this.Data.SearchType <= 3) ? this.Data.SearchType : 1
        this.ui.Update("SearchTypeCon", "SelectedIndex", String(st - 1))
        this._SetImage(this.Data.SearchImagePath)
        this.ui.Update("HexColorCon", "Text", this.Data.SearchColor)
        this.ui.Update("TextCon", "Text", this.Data.SearchText)
        this.ui.Update("StartPosXCon", "Text", this.Data.StartPosX)
        this.ui.Update("StartPosYCon", "Text", this.Data.StartPosY)
        this.ui.Update("EndPosXCon", "Text", this.Data.EndPosX)
        this.ui.Update("EndPosYCon", "Text", this.Data.EndPosY)
        ma := (IsNumber(this.Data.MouseActionType) && this.Data.MouseActionType >= 1 && this.Data.MouseActionType <= 4) ? this.Data.MouseActionType : 2
        this.ui.Update("MouseActionTypeCon", "SelectedIndex", String(ma - 1))
        this.ui.Update("TrueMacroCon", "Text", GetLangMacro(this.Data.TrueMacro, 1))
        this.ui.Update("FalseMacroCon", "Text", GetLangMacro(this.Data.FalseMacro, 1))
        this.OnChangeSearchType()
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

        if (this.Data.SearchImagePath != "" && !FileExist(this.Data.SearchImagePath)) {
            MsgBox(Format("{} {}`n{}", this.Data.SearchImagePath, GetLang("图片不存在"), GetLang(
                "如果是软件位置发生改变，请点击若梦兔-配置管理-配置校准")))
            return false
        }
        return true
    }

    CheckIfValid() {
        sx := this.ui.Query("StartPosXCon")
        sy := this.ui.Query("StartPosYCon")
        ex := this.ui.Query("EndPosXCon")
        ey := this.ui.Query("EndPosYCon")

        if (!IsNumber(sx) || !IsNumber(sy) || !IsNumber(ex) || !IsNumber(ey)) {
            MsgBox(GetLang("坐标中请输入数字"))
            return false
        }

        if (Number(sx) > Number(ex) || Number(sy) > Number(ey)) {
            MsgBox(GetLang("起始坐标不能大于终止坐标"))
            return false
        }

        curType := this._TypeIndex()

        if (curType == 1 && this.Data.SearchImagePath == "") {
            MsgBox(GetLang("请设置搜索图片"))
            return false
        }

        if (curType == 1) {
            searchWidth := Number(ex) - Number(sx)
            searchHeight := Number(ey) - Number(sy)
            size := GetImageSize(this.Data.SearchImagePath)
            if (size[1] > searchWidth || size[2] > searchHeight) {
                MsgBox(GetLang("搜索范围不能小于图片大小"))
                return false
            }
        }

        if (curType == 2 && !RegExMatch(this.ui.Query("HexColorCon"), "^([0-9A-Fa-f]{6})$")) {
            MsgBox(GetLang("请输入正确的颜色值"))
            return false
        }

        if (curType == 3) {
            if (Number(sx) == Number(ex) || Number(sy) == Number(ey)) {
                MsgBox(GetLang("搜索文本时：搜索范围中起始坐标不能和终止坐标相同"))
                return false
            }
        }

        return true
    }

    SaveSearchData() {
        data := this.Data
        data.SearchType := this._TypeIndex()
        data.SearchColor := this.ui.Query("HexColorCon")
        data.SearchText := this.ui.Query("TextCon")
        data.StartPosX := this.ui.Query("StartPosXCon")
        data.StartPosY := this.ui.Query("StartPosYCon")
        data.EndPosX := this.ui.Query("EndPosXCon")
        data.EndPosY := this.ui.Query("EndPosYCon")
        mIdx := IsObject(this.ui) ? this.ui.Query("MouseActionTypeCon>SelectedIndex") : ""
        data.MouseActionType := (IsNumber(mIdx) && Integer(mIdx) >= 0) ? Integer(mIdx) + 1 : this.Data.MouseActionType
        data.TrueMacro := GetLangMacro(this.ui.Query("TrueMacroCon"), 2)
        data.FalseMacro := GetLangMacro(this.ui.Query("FalseMacroCon"), 2)
        SaveMacroCMDData(data)
    }

    _TypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("SearchTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return Integer(v) + 1
    }

    _SetImage(path) {
        if (IsObject(this.ui))
            this.ui.Update("ImageCon", "Source", StrReplace(path, "\", "/"))
    }

    ; ---------------- 快捷键/定时器 ----------------

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

            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            ColorText := StrReplace(Color, "0x", "")
            this.ui.Update("MouseColorCon", "Text", ColorText)
            this.ui.Update("MouseColorTipCon", "Background", "#" ColorText)
            this.ui.Update("MouseColorTipCon", "BorderBrush", this._SwatchContrastStroke(ColorText))
            this.ui.Update("MouseColorTipCon", "BorderThickness", "1")
        }
    }

    ; ---------------- 按钮/事件 ----------------

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
        curPath := this.Data.SearchImagePath
        path := FileSelect(1, curPath, GetLang("选择图片"), "PNG Files (*.png)")
        if (path != "") {
            this._SetImage(path)
            this.Data.SearchImagePath := path
        }
    }

    OnImageShotBtnClick(*) {
        if (MainSoftData.ScreenShotType == 1) {
            SetClipboard("")  ; 清空剪贴板
            Run("ms-screenclip:")
            SetTimer(this.CheckClipboardAction, 500)  ; 每 500 毫秒检查一次剪贴板
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
        ; 如果剪贴板中有图像
        if DllCall("IsClipboardFormatAvailable", "uint", 8)  ; 8 是 CF_BITMAP 格式
        {
            imageSerial := GetNextImageSerial()
            filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
            SaveClipToBitmap(filePath)
            this._SetImage(filePath)
            this.Data.SearchImagePath := filePath
            ; 停止监听
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

    OnSureTarget(PosX, PosY, Color) {
        ColorText := StrReplace(Color, "0x", "")
        this.ui.Update("HexColorCon", "Text", ColorText)
        this.HexColor := ColorText
        this._ApplyColorSwatch(ColorText)
        this.OnSetSearchArea(PosX, PosY, PosX, PosY)
    }

    OnClickTargeterBtn(*) {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(*) {
        str := Format("{}`n{}`n{}", GetLang("1.左键拖拽改变位置"), GetLang("2.上下左右方向键微调位置"), GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"
        ))
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnScreenShotGetArea(x1, y1, x2, y2) {
        ; 确保截图区域至少为1x1像素，避免单像素点点击导致截图无效
        if (x1 == x2)
            x2++
        if (y1 == y2)
            y2++

        imageSerial := GetNextImageSerial()
        filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"

        ScreenShot(x1, y1, x2, y2, filePath)
        this._SetImage(filePath)
        this.Data.SearchImagePath := filePath

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
            ; 原生传 this.MousePosCon（原生控件）；XAML 版无原生控件，给无操作焦点对象，
            ; 避免 MacroEditGui.OnSureBtnClick 对空值调用 .Focus() 抛错（MacroEditGui.ahk:707）
            this.MacroGui.SureFocusCon := {Focus: (*) => ""}

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
            ; 同 OnEditFoundMacroBtnClick：无操作焦点对象替代原生控件
            this.MacroGui.SureFocusCon := {Focus: (*) => ""}

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

    OnChangeSearchType(*) {
        curType := this._TypeIndex()
        isImage := curType == 1
        isColor := curType == 2
        isText := curType == 3
        this.ui.Update("ImagePanel", "Visibility", isImage ? "Visible" : "Collapsed")
        this.ui.Update("ColorPanel", "Visibility", isColor ? "Visible" : "Collapsed")
        this.ui.Update("TextPanel", "Visibility", isText ? "Visible" : "Collapsed")
        if (isColor)
            this._ApplyColorSwatch()
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
        this.ui.Update("StartPosXCon", "Text", x1)
        this.ui.Update("StartPosYCon", "Text", y1)
        this.ui.Update("EndPosXCon", "Text", x2)
        this.ui.Update("EndPosYCon", "Text", y2)
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        this.ui.Update("StartPosXCon", "Text", x1)
        this.ui.Update("StartPosYCon", "Text", y1)
        this.ui.Update("EndPosXCon", "Text", x2)
        this.ui.Update("EndPosYCon", "Text", y2)
    }

    SureColor() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY

        CoordMode("Pixel", "Screen")
        Color := PixelGetColor(mouseX, mouseY, "Slow")
        ColorText := StrReplace(Color, "0x", "")
        this.ui.Update("HexColorCon", "Text", ColorText)
        this.HexColor := ColorText
        this._ApplyColorSwatch(ColorText)
        this.OnSetSearchArea(mouseX, mouseY, mouseX, mouseY)
    }

    ; ---------------- 生命周期 ----------------

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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
