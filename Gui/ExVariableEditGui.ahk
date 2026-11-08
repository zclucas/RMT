#Requires AutoHotkey v2.0

; =====================================================================
; 提取文本编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(ExtractStr) / SureAction / OwnerHwnd
; =====================================================================

class ExVariableEditGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this.OwnerHwnd := ""
        this.SureAction := ""
        this._closed := true
        this._batch := []
        this._batching := false
    }

    ShowGui(ExtractStr) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(ExtractStr)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("提取文本编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("14,8,14,10")
        body.Rows("Auto", "Auto", "48")

        tip1 := GetLang("填写源文本和要取出的内容，确定后自动生成提取模板。")
        tip2 := GetLang("源文本留空则全部写入第一个变量；只需包含要提取的片段即可。")
        body.Add("TextBlock").Grid_Row(0).Text(Format("{}`n{}", tip1, tip2))
            .TextWrapping("Wrap").FontSize("11").Foreground("{DynamicResource TextSub}").Margin("2,0,2,8")

        content := body.Add("Grid").Grid_Row(1)
        content.Rows("Auto", "Auto")

        src := content.Add("Grid").Grid_Row(0).Margin("0,0,0,8")
        src.Rows("24", "Auto")
        src.Add("TextBlock").Grid_Row(0).Text(GetLang("源文本内容：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        src.Add("TextBox").Grid_Row(1).Name("OriTextCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2,2").FontSize("11").Height("71").MinHeight("71")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        extCard := content.Add("Border").Grid_Row(1).CornerRadius("8").Padding("12,10,12,12")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        ext := extCard.Add("Grid")
        ext.Cols("100", "*", "12", "100", "*")
        ext.Rows("32", "32", "32")
        loop 6 {
            i := A_Index
            r := (i - 1) // 2
            c := Mod(i - 1, 2) * 3
            ext.Add("TextBlock").Grid_Row(r).Grid_Column(c).Text(Format("{}{}：", GetLang("提取内容"), i))
                .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
            ext.Add("TextBox").Grid_Row(r).Grid_Column(c + 1).Name("VarText" i).Height(26).MinHeight(26)
                .VerticalAlignment("Center").VerticalContentAlignment("Center").Padding("2,0").FontSize("11")
                .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
                .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        }

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="600" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
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
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    Init(ExtractStr) {
        CurPos := 1
        NextText := InStr(ExtractStr, "&c", true, CurPos)
        NextNum := InStr(ExtractStr, "&x", true, CurPos)
        TextConArr := []
        while (NextNum || NextText) {
            Text := GetLang("<内容>")
            CurPos := NextText + 1
            if (NextNum > 0 && (NextNum < NextText || NextText == 0)) {
                Text := GetLang("<数字>")
                CurPos := NextNum + 1
            }
            TextConArr.Push(Text)
            NextText := InStr(ExtractStr, "&c", true, CurPos)
            NextNum := InStr(ExtractStr, "&x", true, CurPos)
        }
        ExtractStr := StrReplace(ExtractStr, "&c", GetLang("<内容>"))
        ExtractStr := StrReplace(ExtractStr, "&x", GetLang("<数字>"))
        this.ui.Update("OriTextCon", "Text", ExtractStr)
        loop 6 {
            val := (TextConArr.Length >= A_Index) ? TextConArr[A_Index] : ""
            this.ui.Update("VarText" A_Index, "Text", val)
        }
    }

    CheckIfValid() {
        ExtractStr := this.ui.Query("OriTextCon")
        loop 6 {
            conVal := this.ui.Query("VarText" A_Index)
            if (conVal == "")
                break
            isContain := InStr(ExtractStr, conVal)
            ExtractStr := StrReplace(ExtractStr, conVal, "", true, &OutputVarCount, 1)
            if (!isContain) {
                tipStr := Format("{}{}:{}", GetLang("提取内容"), A_Index, GetLang("未在源文本内容中出现，请修改"))
                RmtDialog.Info(tipStr)
                return false
            }
        }
        return true
    }

    GetExtractStr() {
        ExtractStr := this.ui.Query("OriTextCon")
        if (this.ui.Query("VarText1") == "")
            return ""
        loop 6 {
            text := this.ui.Query("VarText" A_Index)
            if (text == "")
                break
            isNum := IsNumber(text) || text == GetLang("<数字>")
            replaceStr := isNum ? "&x" : "&c"
            ExtractStr := StrReplace(ExtractStr, text, replaceStr, true, &OutputVarCount, 1)
        }
        return ExtractStr
    }

    GetVariNum() {
        if (this.ui.Query("VarText1") == "")
            return 1
        Count := 0
        loop 6 {
            if (this.ui.Query("VarText" A_Index) != "") {
                Count++
                continue
            }
            break
        }
        return Count
    }

    OnSureBtnClick(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        Action := this.SureAction
        ExtractStr := this.GetExtractStr()
        VariableNum := this.GetVariNum()
        Action(ExtractStr, VariableNum)
        this._CloseWindow()
    }
}
