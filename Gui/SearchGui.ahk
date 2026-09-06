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
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "30", "30", "26", "86", "30", "30", "30", "28", "*", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 快捷方式/执行指令/备注 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,4")
        top.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        top.Add("TextBlock").Text("!l").VerticalAlignment("Center").Margin("4,0,0,0").Opacity("0.6")
        top.Add("Button").Name("BtnTrigger").Content(GetLang("执行指令")).Width(80).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("TextBox").Name("RemarkCon").Width(180).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; === F1/F2/F3 行（框选/截图/取色快捷方式 + 定位取色器）===
        fk := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,2")
        fk.Add("TextBlock").Text("F1").VerticalAlignment("Center").Opacity("0.6")
        fk.Add("CheckBox").Name("SelectToggleCon").Content(GetLang("左键框选搜索范围")).VerticalAlignment("Center").Margin("6,0,0,0")
        fk.Add("TextBlock").Text("F2").VerticalAlignment("Center").Margin("16,0,0,0").Opacity("0.6")
        fk.Add("TextBlock").Text(GetLang("截图")).VerticalAlignment("Center").Margin("6,0,0,0")
        fk.Add("TextBlock").Text("F3").VerticalAlignment("Center").Margin("16,0,0,0").Opacity("0.6")
        fk.Add("TextBlock").Text(GetLang("选取当前颜色")).VerticalAlignment("Center").Margin("6,0,0,0")
        fk.Add("Button").Name("BtnTargeter").Content(GetLang("定位取色器")).Height(26).MinHeight(26).Margin("16,0,0,0").Cursor("Hand")
        fk.Add("Button").Name("BtnTargeterHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1").Padding("0")

        ; === 鼠标信息行 ===
        mi := main.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").Margin("10,2")
        mi.Add("TextBlock").Name("MousePosCon").Text(GetLang("屏幕坐标：0,0")).VerticalAlignment("Center")
        mi.Add("TextBlock").Name("MouseColorCon").Text(GetLang("鼠标颜色：FFFFFF")).VerticalAlignment("Center").Margin("20,0,0,0")
        mi.Add("Border").Name("MouseColorTipCon").Width(16).Height(16).Background("#FF0000").VerticalAlignment("Center").Margin("6,0,0,0")

        ; === 搜索类型 + 图片预览 ===
        st := main.Add("Grid").Grid_Row(4).Margin("10,4,10,0")
        st.Cols("Auto", "Auto", "*", "Auto")
        st.Add("TextBlock").Text(GetLang("搜索类型：")).Grid_Column(0).VerticalAlignment("Center")
        stc := st.Add("ComboBox").Name("SearchTypeCon").Width(120).Height(26).MinHeight(26).Grid_Column(1).Margin("4,0,0,0")
        for t in GetLangArr(["屏幕图片", "屏幕颜色", "屏幕文本"])
            stc.Add("ComboBoxItem").Content(t)
        st.Add("Image").Name("ImageCon").Grid_Column(3).Width(80).Height(80).Stretch("Uniform").VerticalAlignment("Top")

        ; === 起始坐标 + 截图/颜色/文本（原生同区域叠加，按类型切换显隐）===
        r5 := main.Add("Grid").Grid_Row(5).Margin("10,2")
        r5.Cols("Auto", "Auto", "Auto", "Auto", "*")
        r5.Add("TextBlock").Text(GetLang("起始坐标X：")).Grid_Column(0).VerticalAlignment("Center")
        r5.Add("TextBox").Name("StartPosXCon").Width(50).Height(24).MinHeight(24).Grid_Column(1).Margin("4,0,8,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        r5.Add("TextBlock").Text(GetLang("起始坐标Y：")).Grid_Column(2).VerticalAlignment("Center")
        r5.Add("TextBox").Name("StartPosYCon").Width(50).Height(24).MinHeight(24).Grid_Column(3).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ov := r5.Add("Grid").Grid_Column(4).Margin("20,0,0,0")
        imgGrp := ov.Add("StackPanel").Orientation("Horizontal")
        imgGrp.Add("Button").Name("ImageShotBtn").Content(GetLang("截图")).Width(70).Height(28).MinHeight(28).Cursor("Hand")
        imgGrp.Add("Button").Name("ImageSelectBtn").Content(GetLang("选择图片")).Width(80).Height(28).MinHeight(28).Margin("6,0,0,0").Cursor("Hand")
        clrGrp := ov.Add("StackPanel").Orientation("Horizontal")
        clrGrp.Add("TextBlock").Name("ColorTipCon").Text(GetLang("搜索颜色：")).VerticalAlignment("Center")
        clrGrp.Add("TextBox").Name("HexColorCon").Text("FFFFFF").Width(120).Height(24).MinHeight(24).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        clrGrp.Add("Border").Name("HexColorTipCon").Width(16).Height(16).Background("#FF0000").VerticalAlignment("Center").Margin("6,0,0,0")
        txtGrp := ov.Add("StackPanel").Orientation("Horizontal")
        txtGrp.Add("TextBlock").Name("TextTipCon").Text(GetLang("搜索文本：")).VerticalAlignment("Center")
        txtGrp.Add("TextBox").Name("TextCon").Text(GetLang("检索文本")).Width(160).Height(24).MinHeight(24).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 终止坐标 ===
        r6 := main.Add("StackPanel").Grid_Row(6).Orientation("Horizontal").Margin("10,2")
        r6.Add("TextBlock").Text(GetLang("终止坐标X：")).VerticalAlignment("Center")
        r6.Add("TextBox").Name("EndPosXCon").Width(50).Height(24).MinHeight(24).Margin("4,0,8,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        r6.Add("TextBlock").Text(GetLang("终止坐标Y：")).VerticalAlignment("Center").Margin("30,0,0,0")
        r6.Add("TextBox").Name("EndPosYCon").Width(50).Height(24).MinHeight(24).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 鼠标动作 ===
        r7 := main.Add("StackPanel").Grid_Row(7).Orientation("Horizontal").Margin("10,2")
        r7.Add("TextBlock").Text(GetLang("鼠标动作：")).VerticalAlignment("Center")
        mac := r7.Add("ComboBox").Name("MouseActionTypeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["无动作", "移动至目标", "移动至目标点击1次", "移动至目标点击2次"])
            mac.Add("ComboBoxItem").Content(t)

        ; === 找到/未找到 指令标签 + 编辑按钮 ===
        r8 := main.Add("Grid").Grid_Row(8).Margin("10,6,10,0")
        r8.Cols("*", "*")
        f := r8.Add("StackPanel").Grid_Column(0).Orientation("Horizontal")
        f.Add("TextBlock").Text(GetLang("找到后的指令：（可选）")).VerticalAlignment("Center")
        f.Add("Button").Name("BtnEditFoundMacro").Content(GetLang("编辑指令")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        uf := r8.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").Margin("20,0,0,0")
        uf.Add("TextBlock").Text(GetLang("未找到后的指令：（可选）")).VerticalAlignment("Center")
        uf.Add("Button").Name("BtnEditUnFoundMacro").Content(GetLang("编辑指令")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")

        ; === 宏编辑框 ===
        r9 := main.Add("Grid").Grid_Row(9).Margin("10,2,10,0")
        r9.Cols("*", "*")
        r9.Add("TextBox").Name("TrueMacroCon").Grid_Column(0).Margin("0,0,8,0").AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
        r9.Add("TextBox").Name("FalseMacroCon").Grid_Column(1).Margin("8,0,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(10).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="720" Height="500" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTrigger", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("SearchTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeSearchType"))
        this.ui.OnEvent("SelectToggleCon", "Click", ObjBindMethod(this, "OnClickSelectToggle"))
        this.ui.OnEvent("ImageShotBtn", "Click", ObjBindMethod(this, "OnImageShotBtnClick"))
        this.ui.OnEvent("ImageSelectBtn", "Click", ObjBindMethod(this, "OnClickSetPicBtn"))
        this.ui.OnEvent("BtnTargeter", "Click", ObjBindMethod(this, "OnClickTargeterBtn"))
        this.ui.OnEvent("BtnTargeterHelp", "Click", ObjBindMethod(this, "OnClickTargeterHelpBtn"))
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
            this.ui.Update("MousePosCon", "Text", Format("{}{},{}", GetLang("屏幕坐标："), mouseX, mouseY))

            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            ColorText := StrReplace(Color, "0x", "")
            this.ui.Update("MouseColorCon", "Text", Format("{}{}", GetLang("鼠标颜色："), ColorText))
            this.ui.Update("MouseColorTipCon", "Background", "#" ColorText)
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
        this.ui.Update("HexColorTipCon", "Visibility", "Visible")
        this.ui.Update("HexColorTipCon", "Background", "#" ColorText)
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
        showColorTip := isColor && RegExMatch(this.ui.Query("HexColorCon"), "^([0-9A-Fa-f]{6})$")

        this.ui.Update("ImageShotBtn", "Visibility", isImage ? "Visible" : "Collapsed")
        this.ui.Update("ImageSelectBtn", "Visibility", isImage ? "Visible" : "Collapsed")
        this.ui.Update("ImageCon", "Visibility", isImage ? "Visible" : "Collapsed")

        this.ui.Update("HexColorCon", "Visibility", isColor ? "Visible" : "Collapsed")
        this.ui.Update("ColorTipCon", "Visibility", isColor ? "Visible" : "Collapsed")
        this.ui.Update("HexColorTipCon", "Visibility", showColorTip ? "Visible" : "Collapsed")
        if (showColorTip)
            this.ui.Update("HexColorTipCon", "Background", "#" this.ui.Query("HexColorCon"))

        loop this.TextArr.Length {
            this.ui.Update(this.TextArr[A_Index], "Visibility", isText ? "Visible" : "Collapsed")
        }
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
            TogSelectArea(true, this.SetAreaAction)
        else
            TogSelectArea(false)
    }

    OnF1() {
        this.ui.Update("SelectToggleCon", "IsChecked", "True")
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        this.ui.Update("SelectToggleCon", "IsChecked", "False")
        this.ui.Update("StartPosXCon", "Text", x1)
        this.ui.Update("StartPosYCon", "Text", y1)
        this.ui.Update("EndPosXCon", "Text", x2)
        this.ui.Update("EndPosYCon", "Text", y2)
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        this.ui.Update("SelectToggleCon", "IsChecked", "False")
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
        this.ui.Update("HexColorTipCon", "Visibility", "Visible")
        this.ui.Update("HexColorTipCon", "Background", "#" ColorText)
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
