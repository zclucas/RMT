#Requires AutoHotkey v2.0

; =====================================================================
; 使用说明编辑器 —— XAML 迁移版（独立实现）
; 公开接口：ShowGui(SettingPath)
; 标题栏选择图片/截图；预览条在操作说明下方，高度 80，可水平滚动，单张右上角关闭。
; =====================================================================

class UseExplainGui {
    __new() {
        this.Gui := ""
        this.ui := ""
        this.ContextMenu := ""
        this.AuthorCon := ""
        this.EffectCon := ""
        this.OperCon := ""
        this.LVCon := ""
        this.AllImagePathMap := Map()
        this.ImagePathArr := []
        this.CheckClipboardAction := () => this.CheckClipboard()
        this.SettingPath := ""
        this._imgBound := Map()
        this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ShowGui(SettingPath) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        this.Init(SettingPath)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("使用说明")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "44")

        chrome := XAMLHost.AddTitleBarChrome(main, title)
        pickBtn := XAMLHost.AddTitleChromeBtn(chrome.Btns, "BtnSelectImage", titleHeight, Chr(0xE8B7), "Visible", "{StaticResource TitleBarChromeButton}", "42", "14")
        pickBtn.ToolTip(GetLang("选择图片"))
        shotBtn := XAMLHost.AddTitleChromeBtn(chrome.Btns, "BtnScreenShot", titleHeight, Chr(0xE7A8), "Visible", "{StaticResource TitleBarChromeButton}", "42", "14")
        shotBtn.ToolTip(GetLang("截图"))
        chrome.Close := XAMLHost.AddTitleCloseBtn(chrome.Btns, "BtnClosePanel", titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("12,8,12,4")
        body.Cols("80", "*")
        body.Rows("26", "32", "60", "*", "Auto")

        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("配置名称：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        body.Add("TextBlock").Grid_Row(0).Grid_Column(1).Text(MySoftData.CurSettingName).VerticalAlignment("Center").Margin("4,0,0,0")
            .Foreground("{DynamicResource TextMain}")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("作者：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        authorHost := body.Add("Grid").Grid_Row(1).Grid_Column(1).Margin("0,3,0,3")
        authorHost.Add("TextBox").Name("AuthorCon").Height(26).MinHeight(26)
            .Style("{StaticResource RmtSingleLineTextBox}").Padding("6,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center")
        this._Placeholder(authorHost, "AuthorCon", GetLang("请填写作者名称"))

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("配置作用：")).VerticalAlignment("Top").Margin("0,4,0,0")
            .Foreground("{DynamicResource TextMain}")
        effectHost := body.Add("Grid").Grid_Row(2).Grid_Column(1).Margin("0,0,0,6")
        effectHost.Add("TextBox").Name("EffectCon")
            .AcceptsReturn("True").TextWrapping("Wrap").VerticalScrollBarVisibility("Auto")
            .Style("{StaticResource RmtMultiLineTextBox}").Padding("6,4,6,4")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top")
        this._Placeholder(effectHost, "EffectCon", GetLang("请简要说明配置用途"), true)

        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("操作说明：")).VerticalAlignment("Top").Margin("0,4,0,0")
            .Foreground("{DynamicResource TextMain}")
        operHost := body.Add("Grid").Grid_Row(3).Grid_Column(1).Margin("0,0,0,8")
        operHost.Add("TextBox").Name("OperCon")
            .AcceptsReturn("True").TextWrapping("Wrap").VerticalScrollBarVisibility("Auto")
            .Style("{StaticResource RmtMultiLineTextBox}").Padding("6,4,6,4")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top")
        this._Placeholder(operHost, "OperCon", GetLang("请填写操作步骤或注意事项"), true)

        imgHost := body.Add("Border").Grid_Row(4).Grid_ColumnSpan(2).Name("ImageHost").Height(80).Margin("0,0,0,0")
            .Visibility("Collapsed").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").CornerRadius("3")
        imgSv := imgHost.Add("ScrollViewer").HorizontalScrollBarVisibility("Auto").VerticalScrollBarVisibility("Disabled")
        imgSv.Add("StackPanel").Name("ImageStrip").Orientation("Horizontal").VerticalAlignment("Center").Margin("4,0")

        bottom := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        bottom.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" Height="520"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnSelectImage", "Click", ObjBindMethod(this, "OnSelectImage"))
        this.ui.OnEvent("BtnScreenShot", "Click", ObjBindMethod(this, "OnScreenShot"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    _Placeholder(parent, field, text, multiline := false) {
        label := parent.Add("TextBlock").Text(text).IsHitTestVisible("False")
            .Margin(multiline ? "6,4,6,0" : "6,0,6,0")
            .VerticalAlignment(multiline ? "Top" : "Center").Foreground("{DynamicResource TextSub}").Opacity("0.65")
        style := label.Add("TextBlock.Style").Add("Style").TargetType("TextBlock")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        style.Add("Style.Triggers").Add("DataTrigger").Binding("{Binding Text, ElementName=" field "}").Value("")
            .Add("Setter").Property("Visibility").Value("Visible")
    }

    _ExplainLoad(text) {
        text := StrReplace(String(text), "⫶", "`n")
        return StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
    }

    _ExplainSave(text) {
        return StrReplace(StrReplace(String(text), "`r`n", "`n"), "`r", "`n")
    }

    _ImageSrc(path) {
        src := StrReplace(path, "\", "/")
        if (!InStr(src, ":") && SubStr(src, 1, 1) != "/")
            src := StrReplace(A_WorkingDir "\" path, "\", "/")
        if (!RegExMatch(src, "i)^[a-z][a-z0-9+.-]*:"))
            src := "file:///" src
        return src
    }

    _ImageCardXml(index, path) {
        src := this._EscapeXml(this._ImageSrc(path))
        id := String(index)
        return '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Height="80" Margin="0,0,8,0">'
            . '<Image Height="80" Stretch="Uniform" VerticalAlignment="Center">'
            . '<Image.Source><BitmapImage UriSource="' src '" CacheOption="OnLoad" CreateOptions="IgnoreImageCache"/></Image.Source>'
            . '</Image>'
            . '<Button Name="BtnImgClose_' id '" Width="22" Height="22" HorizontalAlignment="Right" VerticalAlignment="Top"'
            . ' Margin="0,2,2,0" Padding="0" Cursor="Hand" Background="#99000000" BorderThickness="0"'
            . ' Foreground="#FFFFFF" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10"'
            . ' Content="' Chr(0xE711) '" ToolTip="' this._EscapeXml(GetLang("删除")) '"/>'
            . '</Grid>'
    }

    RefreshImages() {
        if (!IsObject(this.ui))
            return
        hasImg := this.ImagePathArr.Length > 0
        this.ui.Update("ImageHost", "Visibility", hasImg ? "Visible" : "Collapsed")
        updates := [{ControlName: "ImageStrip", PropertyName: "ClearItems", Value: ""}]
        for i, path in this.ImagePathArr
            updates.Push({ControlName: "ImageStrip", PropertyName: "AddXamlItem", Value: this._ImageCardXml(i, path)})
        this.ui.BatchUpdate(updates)
        for i, path in this.ImagePathArr {
            btn := "BtnImgClose_" i
            if (!this._imgBound.Has(btn)) {
                this._imgBound[btn] := true
                this.ui.OnEvent(btn, "Click", this._ImgCloseHandler(i))
            }
            this.ui.BindEventBatched(btn, "Click")
        }
    }

    _ImgCloseHandler(index) {
        return (*) => this.RemoveImage(index)
    }

    RemoveImage(index) {
        if (index < 1 || index > this.ImagePathArr.Length)
            return
        imagePath := this.ImagePathArr[index]
        this.ImagePathArr.RemoveAt(index)
        if (this.AllImagePathMap.Has(imagePath))
            this.AllImagePathMap.Delete(imagePath)
        this.RefreshImages()
        this._TryDeleteImage(imagePath)
    }

    _TryDeleteImage(imagePath) {
        if (imagePath == "" || !FileExist(imagePath))
            return
        loop 8 {
            try {
                FileDelete(imagePath)
                return
            }
            Sleep 30
        }
    }

    Init(SettingPath) {
        this.SettingPath := SettingPath
        this.ImagePathArr := []
        this.AllImagePathMap := Map()
        this._imgBound := Map()
        this.ui.Update("AuthorCon", "Text", this._ReadExplain("Author"))
        this.ui.Update("EffectCon", "Text", this._ReadExplain("Effect"))
        this.ui.Update("OperCon", "Text", this._ReadExplain("Operation"))

        ImagesfolderPath := SettingPath "\Images\UseExplain"
        if (!DirExist(ImagesfolderPath))
            DirCreate(ImagesfolderPath)
        loop files ImagesfolderPath "\*.*" {
            ext := StrLower(A_LoopFileExt)
            if (ext != "png" && ext != "jpg" && ext != "jpeg" && ext != "bmp" && ext != "gif" && ext != "webp")
                continue
            this.AllImagePathMap.Set(A_LoopFileFullPath, true)
            this.ImagePathArr.Push(A_LoopFileFullPath)
        }
        this.RefreshImages()
    }

    OnSelectImage(state, ctrl, event) {
        path := FileSelect(1, , GetLang("选择图片"), "Image Files (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp)")
        if (path == "")
            return

        SplitPath path, &name, &dir, &ext, &name_no_ext, &drive
        destDir := this.SettingPath "\Images\UseExplain"
        if (!DirExist(destDir))
            DirCreate(destDir)
        newPath := destDir "\" name
        if (FileExist(newPath)) {
            RmtDialog.Info(GetLang("该图片已添加，请勿重复添加！！！"), GetLang("提示"), this.Hwnd())
            return
        }

        FileCopy(path, newPath)
        this.AllImagePathMap.Set(newPath, true)
        this.ImagePathArr.Push(newPath)
        this.RefreshImages()
    }

    OnScreenShot(state, ctrl, event) {
        if (MainSoftData.ScreenShotType == 1) {
            SetClipboard("")
            Run("ms-screenclip:")
            SetTimer(this.CheckClipboardAction, 500)
        }
        else if (MainSoftData.ScreenShotType == 3) {
            RunScreenCapture(this.CheckClipboardAction)
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
            CurrentDateTime := FormatTime(, "HHmmss")
            filePath := this.SettingPath "\Images\UseExplain\" CurrentDateTime ".png"
            SaveClipToBitmap(filePath)

            this.AllImagePathMap.Set(filePath, true)
            this.ImagePathArr.Push(filePath)
            this.RefreshImages()
            SetTimer(this.CheckClipboardAction, 0)
        }
    }

    OnScreenShotGetArea(x1, y1, x2, y2) {
        if (x1 == x2)
            x2++
        if (y1 == y2)
            y2++

        CurrentDateTime := FormatTime(, "HHmmss")
        filePath := this.SettingPath "\Images\UseExplain\" CurrentDateTime ".png"
        ScreenShot(x1, y1, x2, y2, filePath)

        this.AllImagePathMap.Set(filePath, true)
        this.ImagePathArr.Push(filePath)
        this.RefreshImages()
    }

    _ReadExplain(key) {
        path := this.SettingPath "\使用说明&署名.txt"
        section := "Instructions for Use & Attribution"
        val := CfgRead(path, section, key, "")
        if (val != "")
            return this._ExplainLoad(val)
        try val := IniRead(path, section, key, "")
        catch
            val := ""
        if (val == "" || val == "ERROR")
            return ""
        if (SubStr(val, 1, 1) == '"' && SubStr(val, -1) == '"')
            val := SubStr(val, 2, StrLen(val) - 2)
        return this._ExplainLoad(val)
    }

    OnClickSureBtn(state, ctrl, event) {
        OperFilePath := this.SettingPath "\使用说明&署名.txt"
        ExplainSection := "Instructions for Use & Attribution"
        CfgWrite(this._ExplainSave(this.ui.Query("AuthorCon")), OperFilePath, ExplainSection, "Author")
        CfgWrite(this._ExplainSave(this.ui.Query("EffectCon")), OperFilePath, ExplainSection, "Effect")
        CfgWrite(this._ExplainSave(this.ui.Query("OperCon")), OperFilePath, ExplainSection, "Operation")
        Cfg_FlushFile(OperFilePath)
        this._CloseWindow()
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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
        this.ui := ""
        this._closed := true
    }
}
