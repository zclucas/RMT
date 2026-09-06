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

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("提取文本编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("15,10")
        body.Rows("Auto", "24", "*", "34", "34", "34", "34", "34", "34", "*")
        body.Cols("90", "100")

        tip1 := GetLang("源文本内容：请输入 提取范围 或 剪切板 的文本内容")
        tip2 := GetLang("提取内容：请输入你需要提取的变量内容")
        tip3 := GetLang("将根据 源文本内容 和 提取内容 自动生成提取文本")
        tip4 := GetLang("提示1：源文本内容空时，将提取所有内容到第一个变量中")
        tip5 := GetLang("提示2：源文本内容不需要太多，包含提取内容即可")
        body.Add("TextBlock").Grid_Row(0).Grid_ColumnSpan(2).Text(Format("{}`n{}`n{}`n{}`n{}", tip1, tip2, tip3, tip4, tip5))
            .TextWrapping("Wrap").Margin("0,0,0,6")

        body.Add("TextBlock").Grid_Row(1).Grid_ColumnSpan(2).Text(GetLang("源文本内容：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(2).Grid_ColumnSpan(2).Name("OriTextCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Margin("0,2,0,4")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 6 行提取内容
        loop 6 {
            r := A_Index + 2
            body.Add("TextBlock").Grid_Row(r).Grid_Column(0).Text(Format("{}" A_Index ":", GetLang("提取内容"))).VerticalAlignment("Center")
            body.Add("TextBox").Grid_Row(r).Grid_Column(1).Name("VarText" A_Index).Height(26).MinHeight(26)
                .VerticalContentAlignment("Center")
                .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
                .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        }

        btnRow := body.Add("StackPanel").Grid_Row(9).Grid_ColumnSpan(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="480" Height="378" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
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
                MsgBox(tipStr)
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
