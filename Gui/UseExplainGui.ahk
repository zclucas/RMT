#Requires AutoHotkey v2.0

; =====================================================================
; 使用说明编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(SettingPath) / Mode / ModeAction
; ListView 图片列表迁 ListBox（缩略图 + 文件名，双击打开、右键删除，用桥接 ListBox 命中测试）
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
        this.Mode := 1  ;1查看模式  2上传确认模式
        this.HasChange := false
        this.ModeAction := ""
        this.RowNumber := 0
        this._closed := true
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

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 主体 ===
        body := main.Add("StackPanel").Grid_Row(1).Orientation("Vertical").Margin("10,4")

        nameRow := body.Add("StackPanel").Orientation("Horizontal")
        nameRow.Add("TextBlock").Text(GetLang("配置名称：")).VerticalAlignment("Center")
        nameRow.Add("TextBlock").Text(MySoftData.CurSettingName).VerticalAlignment("Center").Margin("4,0,0,0")

        authorRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        authorRow.Add("TextBlock").Text(GetLang("作者：")).Width(80).VerticalAlignment("Center")
        authorRow.Add("TextBox").Name("AuthorCon").Width(480).Height(26).MinHeight(26)
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        effectRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        effectRow.Add("TextBlock").Text(GetLang("配置作用：")).Width(80).VerticalAlignment("Top")
        effectRow.Add("TextBox").Name("EffectCon").Width(480).Height(60).AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        operRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        operRow.Add("TextBlock").Text(GetLang("操作说明：")).Width(80).VerticalAlignment("Top")
        operRow.Add("TextBox").Name("OperCon").Width(480).Height(140).AcceptsReturn("True").TextWrapping("Wrap")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Top").Padding("4,2").FontSize(11)

        lvRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        lvRow.Add("TextBlock").Text(GetLang("图片备注：")).Width(80).VerticalAlignment("Top")
        lvRow.Add("ListBox").Name("LVCon").Width(480).Height(120)
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .VirtualizingPanel_IsVirtualizing("False")

        btnRow := body.Add("StackPanel").Orientation("Horizontal").Margin("80,6,0,0")
        btnRow.Add("Button").Name("BtnSelectImage").Content(GetLang("选择图片")).Width(80).Height(28).MinHeight(28).Cursor("Hand")
        btnRow.Add("Button").Name("BtnScreenShot").Content(GetLang("截图")).Width(80).Height(28).MinHeight(28).Margin("20,0,0,0").Cursor("Hand")

        ; === 底部按钮 ===
        bottom := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        bottom.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" Height="560" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("AuthorCon", "TextChanged", ObjBindMethod(this, "OnValueChange"))
        this.ui.OnEvent("EffectCon", "TextChanged", ObjBindMethod(this, "OnValueChange"))
        this.ui.OnEvent("OperCon", "TextChanged", ObjBindMethod(this, "OnValueChange"))
        this.ui.OnEvent("BtnSelectImage", "Click", ObjBindMethod(this, "OnSelectImage"))
        this.ui.OnEvent("BtnScreenShot", "Click", ObjBindMethod(this, "OnScreenShot"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        ; 图片列表：双击打开，右键删除
        this.ui.OnEvent("LVCon", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnLVLeftDown"))
        this.ui.OnEvent("LVCon", "PreviewMouseRightButtonDown", ObjBindMethod(this, "_OnLVRightClick"))

    }

    ; ---------------- 图片列表命中测试 ----------------

    _EventCoord(state, ctrlName) {
        coord := ""
        if (IsObject(state) && state.Has(ctrlName))
            coord := state[ctrlName]
        if (coord == "")
            return ""
        parts := StrSplit(coord, ",")
        if (parts.Length != 2)
            return ""
        return Trim(parts[1]) ";" Trim(parts[2])
    }

    _HitTest(ctrlName, coord) {
        if (!IsObject(this.ui) || coord == "")
            return ""
        return this.ui.Query(ctrlName ">HitTest:" coord)
    }

    _OnLVLeftDown(state, ctrl, event) {
        clickCount := 1
        if (IsObject(state) && state.Has("ClickCount")) {
            cc := state["ClickCount"]
            if (IsNumber(cc))
                clickCount := Integer(cc)
        }
        if (clickCount >= 2)
            this._OnLVDoubleClick(state, ctrl, event)
    }

    _OnLVDoubleClick(state, ctrl, event) {
        coord := this._EventCoord(state, "LVCon")
        if (coord == "")
            return
        tagSlot := this._HitTest("LVCon", coord)
        if (tagSlot == "")
            return
        path := StrSplit(tagSlot, "|")[1]
        this.OnValueChange()
        run path
    }

    _OnLVRightClick(state, ctrl, event) {
        coord := this._EventCoord(state, "LVCon")
        if (coord == "")
            return
        tagSlot := this._HitTest("LVCon", coord)
        if (tagSlot == "")
            return
        path := StrSplit(tagSlot, "|")[1]
        this.OnValueChange()
        this.RowNumber := 0
        for i, p in this.ImagePathArr {
            if (p == path) {
                this.RowNumber := i
                break
            }
        }
        if (this.RowNumber == 0)
            return
        if (this.ContextMenu == "") {
            this.ContextMenu := Menu()
            this.ContextMenu.Add(GetLang("删除"), (*) => this.MenuHandler(GetLang("删除")))
        }
        this.ContextMenu.Show()
    }

    RefreshLV() {
        this.ui.Update("LVCon", "ClearItems", "")
        for path in this.ImagePathArr {
            SplitPath path, &name
            xml := '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
                . ' Tag="' this._EscapeXml(path) '" Background="Transparent" HorizontalContentAlignment="Stretch">'
                . '<StackPanel Orientation="Horizontal" Margin="2,2,2,2">'
                . '<Image Source="' this._EscapeXml(StrReplace(path, "\", "/")) '" Width="32" Height="32" Margin="0,0,6,0"/>'
                . '<TextBlock Text="' this._EscapeXml(name) '" VerticalAlignment="Center" FontSize="11"/>'
                . '</StackPanel></ListBoxItem>'
            this.ui.Update("LVCon", "AddXamlItem", xml)
        }
    }

    Init(SettingPath) {
        this.SettingPath := SettingPath
        this.ImagePathArr := []
        this.HasChange := false
        OperFilePath := SettingPath "\使用说明&署名.txt"
        IniSection := "Instructions for Use & Attribution"
        AuthorText := IniRead(OperFilePath, IniSection, "Author", "")
        EffectText := IniRead(OperFilePath, IniSection, "Effect", "")
        OperText := IniRead(OperFilePath, IniSection, "Operation", "")
        AuthorText := StrReplace(AuthorText, "⫶", "`n")
        EffectText := StrReplace(EffectText, "⫶", "`n")
        OperText := StrReplace(OperText, "⫶", "`n")
        this.ui.Update("AuthorCon", "Text", AuthorText)
        this.ui.Update("EffectCon", "Text", EffectText)
        this.ui.Update("OperCon", "Text", OperText)

        ImagesfolderPath := SettingPath "\Images\UseExplain"
        loop files ImagesfolderPath "\*.png" {
            this.AllImagePathMap.Set(A_LoopFileFullPath, true)
            this.ImagePathArr.Push(A_LoopFileFullPath)
        }
        this.RefreshLV()
    }

    OnSelectImage(state, ctrl, event) {
        path := FileSelect(1, , GetLang("选择图片"), "PNG Files (*.png)")
        if (path == "")
            return

        this.OnValueChange()
        SplitPath path, &name, &dir, &ext, &name_no_ext, &drive
        newPath := this.SettingPath "\Images\UseExplain\" name
        if (FileExist(newPath)) {
            MsgBox(GetLang("该图片已添加，请勿重复添加！！！"))
            return
        }

        FileCopy(path, newPath)
        this.AllImagePathMap.Set(newPath, true)
        this.ImagePathArr.Push(newPath)
        this.RefreshLV()
    }

    OnScreenShot(state, ctrl, event) {
        this.OnValueChange()
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
        if DllCall("IsClipboardFormatAvailable", "uint", 8) {
            CurrentDateTime := FormatTime(, "HHmmss")
            filePath := this.SettingPath "\Images\UseExplain\" CurrentDateTime ".png"
            SaveClipToBitmap(filePath)

            this.AllImagePathMap.Set(filePath, true)
            this.ImagePathArr.Push(filePath)
            this.RefreshLV()
            SetTimer(, 0)
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
        this.RefreshLV()
    }

    CheckIfValid() {
        if (this.Mode == 1)
            return true

        if (Trim(this.ui.Query("AuthorCon")) == "") {
            MsgBox(GetLang("请完善作者信息，若不想留名请输入匿名"))
            return false
        }

        if (Trim(this.ui.Query("EffectCon")) == "") {
            MsgBox(GetLang("请完善配置作用信息，简要的介绍配置的作用"))
            return false
        }

        if (Trim(this.ui.Query("OperCon")) == "") {
            MsgBox(GetLang("请完善操作说明信息，详细说明配置对应的操作"))
            return false
        }

        return true
    }

    OnValueChange(*) {
        this.HasChange := true
    }

    OnTriggerModeAction(isSure, isChange) {
        if (this.ModeAction == "")
            return
        action := this.ModeAction
        action(isSure, isChange)
        this.ModeAction := ""
    }

    OnClickSureBtn(state, ctrl, event) {
        isValid := this.CheckIfValid()
        if (!isValid)
            return

        OperFilePath := this.SettingPath "\使用说明&署名.txt"
        IniSection := "Instructions for Use & Attribution"
        AuthorText := StrReplace(this.ui.Query("AuthorCon"), "`n", "⫶")
        EffectText := StrReplace(this.ui.Query("EffectCon"), "`n", "⫶")
        OperText := StrReplace(this.ui.Query("OperCon"), "`n", "⫶")
        IniWrite(AuthorText, OperFilePath, IniSection, "Author")
        IniWrite(EffectText, OperFilePath, IniSection, "Effect")
        IniWrite(OperText, OperFilePath, IniSection, "Operation")

        this.OnTriggerModeAction(true, this.HasChange)
        this._CloseWindow()
    }

    MenuHandler(cmdStr, *) {
        switch cmdStr {
            case GetLang("删除"):
            {
                imagePath := this.ImagePathArr[this.RowNumber]
                this.ImagePathArr.RemoveAt(this.RowNumber)
                if (FileExist(imagePath))
                    FileDelete(imagePath)
                this.RefreshLV()
            }
        }
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
