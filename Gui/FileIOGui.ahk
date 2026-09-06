#Requires AutoHotkey v2.0

; =====================================================================
; 文件读写编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class FileIOGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.Data := ""
        this.SerialStr := ""
        this.OperModeMap := Map(
            GetLang("读取Excel"),
            GetLangArr(["单元格", "指定行", "指定列", "指定区域-行", "指定区域-列"]),
            GetLang("写入Excel"),
            GetLangArr(["单元格", "行号自增", "列号自增", "指定区域-行", "指定区域-列"]),
            GetLang("读取文本文件"),
            GetLangArr(["读取全部内容", "逐行读取", "指定行"]),
            GetLang("写入文本文件"),
            GetLangArr(["覆盖写入", "追加写入", "追加写入-行", "指定行", "行号自增"])
        )
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._batching := true
        try this.Init(cmd)
        finally {
            this._flushBatch()
        }
        this.RefreshConVisable()
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

    ; batching 中入队，_flushBatch 一次性 BatchUpdate（合并 Init 的多次 Update 为一次 IPC）
    _ComboPush(comboName, propertyName, value) {
        if (this._batching)
            this._batch.Push({ControlName: comboName, PropertyName: propertyName, Value: value})
        else
            this.ui.Update(comboName, propertyName, value)
    }

    _flushBatch() {
        this._batching := false
        if (IsObject(this.ui) && this._batch.Length > 0) {
            this.ui.BatchUpdate(this._batch)
            this._batch := []
        }
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("文件读写编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "34", "34", "34", "34", "34", "Auto", "Auto", "*")
        body.Cols("90", "150", "90", "150")

        ; 行0：快捷方式
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：操作类型 + 文件编码
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("操作类型:")).VerticalAlignment("Center")
        ot := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("OperTypeCombo").Height(26).MinHeight(26)
        for t in GetLangArr(["读取Excel", "写入Excel", "读取文本文件", "写入文本文件"])
            ot.Add("ComboBoxItem").Content(t)
        encRow := body.Add("StackPanel").Name("EncodingRow").Grid_Row(1).Grid_Column(2).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        encRow.Add("TextBlock").Text(GetLang("文件编码:")).VerticalAlignment("Center")
        encRow.Add("ComboBox").Name("EncodingCombo").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行2：文件路径
        row2 := body.Add("StackPanel").Grid_Row(2).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row2.Add("TextBlock").Text(GetLang("文件路径:")).VerticalAlignment("Center").Width(80)
        row2.Add("ComboBox").Name("FilePathCombo").Width(320).Height(26).MinHeight(26).IsEditable("True")
        row2.Add("Button").Name("BtnSelectFile").Content(GetLang("选择文件")).Height(26).MinHeight(26).Margin("6,0,0,0")

        ; 行3：操作模式 + 行号
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("操作模式:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(1).Name("OperModeCombo").Height(26).MinHeight(26)
        textRow := body.Add("StackPanel").Name("TextRowRow").Grid_Row(3).Grid_Column(2).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        textRow.Add("TextBlock").Text(GetLang("行号:")).VerticalAlignment("Center")
        textRow.Add("ComboBox").Name("TextRowCombo").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 行4：表名或序号 + 表格行号 + 表格列号
        excelRow := body.Add("StackPanel").Name("ExcelRow").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        excelRow.Add("TextBlock").Text(GetLang("表名或序号:")).VerticalAlignment("Center")
        excelRow.Add("ComboBox").Name("NameOrSerialCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        excelRow.Add("TextBlock").Text(GetLang("表格行号:")).VerticalAlignment("Center").Margin("14,0,0,0")
        excelRow.Add("ComboBox").Name("RowCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        excelRow.Add("TextBlock").Text(GetLang("表格列号:")).VerticalAlignment("Center").Margin("14,0,0,0")
        excelRow.Add("ComboBox").Name("ColCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 行5：终止行号 + 终止列号
        regionRow := body.Add("StackPanel").Name("RegionRow").Grid_Row(5).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        regionRow.Add("TextBlock").Text(GetLang("终止行号:")).VerticalAlignment("Center")
        regionRow.Add("ComboBox").Name("RowEndCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        regionRow.Add("TextBlock").Text(GetLang("终止列号:")).VerticalAlignment("Center").Margin("14,0,0,0")
        regionRow.Add("ComboBox").Name("ColEndCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 行6：结果保存 GroupBox
        resGroup := body.Add("GroupBox").Name("ResultGroup").Grid_Row(6).Grid_ColumnSpan(4).Header(GetLang("结果保存"))
            .Margin("0,2,0,2").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}")
        res := resGroup.Add("StackPanel").Orientation("Horizontal").Margin("10,6")
        res.Add("TextBlock").Text(GetLang("结果：")).VerticalAlignment("Center")
        st := res.Add("ComboBox").Name("SaveTypeCombo").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0")
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        res.Add("ComboBox").Name("SaveNameCombo").Width(150).Height(26).MinHeight(26).Margin("10,0,0,0").IsEditable("True")

        ; 行7：写入内容 / 写入数组
        writeRow := body.Add("StackPanel").Name("WriteContentRow").Grid_Row(7).Grid_ColumnSpan(4).Orientation("Vertical")
        w1 := writeRow.Add("StackPanel").Orientation("Horizontal")
        w1.Add("TextBlock").Text(GetLang("输出内容：")).VerticalAlignment("Top").Margin("0,16,0,0")
        w1.Add("TextBox").Name("ContentCon").Width(370).Height(50).MinHeight(50).Margin("4,0,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        w2 := writeRow.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        w2.Add("TextBlock").Text(GetLang("变量数组：")).VerticalAlignment("Center").Width(80)
        wvt := w2.Add("ComboBox").Name("WriteVarTypeCombo").Width(80).Height(26).MinHeight(26)
        wvt.Add("ComboBoxItem").Content(GetLang("变量"))
        wvt.Add("ComboBoxItem").Content(GetLang("数组"))
        w2.Add("ComboBox").Name("WriteVarCombo").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        w2.Add("Button").Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).Margin("6,0,0,0")
        w2.Add("Button").Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).Margin("4,0,0,0")
        writeArrRow := body.Add("StackPanel").Name("WriteArrRow").Grid_Row(7).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        writeArrRow.Add("TextBlock").Text(GetLang("写入数组：")).VerticalAlignment("Center").Width(80)
        writeArrRow.Add("ComboBox").Name("WriteArrCombo").Width(130).Height(26).MinHeight(26).IsEditable("True")

        ; 行8：确定
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="430" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("OperTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshType"))
        this.ui.OnEvent("OperModeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshOperMode"))
        this.ui.OnEvent("WriteVarTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshContentVarType"))
        this.ui.OnEvent("BtnSelectFile", "Click", ObjBindMethod(this, "OnSelectPathBtnClick"))
        this.ui.OnEvent("BtnAddName", "Click", ObjBindMethod(this, "OnClickAddVarNameBtn"))
        this.ui.OnEvent("BtnAddValue", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        this._ComboPush(comboName, "Text", text)
    }

    _SetDDL(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        for i, it in items {
            if (it == text) {
                this._ComboPush(comboName, "SelectedIndex", String(i - 1))
                return
            }
        }
        this._ComboPush(comboName, "SelectedIndex", "0")
    }

    _Vis(name, show) {
        if (IsObject(this.ui))
            this.ui.Update(name, "Visibility", show ? "Visible" : "Collapsed")
    }

    _TypeText() => IsObject(this.ui) ? this.ui.Query("OperTypeCombo") : ""
    _ModeText() => IsObject(this.ui) ? this.ui.Query("OperModeCombo") : ""

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("文件读写")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLAllVarArr := GetGuiVarArr(1)
        this.DLVarArr := GetGuiVarArr(2)
        this.DLArrayArr := GetGuiArrNameArr()

        this._SetDDL("OperTypeCombo", GetLangArr(["读取Excel", "写入Excel", "读取文本文件", "写入文本文件"]), GetLang(this.Data.OperType))
        this._SetDDL("EncodingCombo", GetLangArr(MySoftData.FileEncodingArr), GetShowEncoding(this.Data.Encoding))
        this._SetCombo("FilePathCombo", GetGuiVarArr(2), this.Data.FilePath)
        this.ui.Update("ContentCon", "Text", GetLangStr(this.Data.Content, 1))
        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), GetLang(this.Data.SaveType))
        this._SetCombo("SaveNameCombo", this.DLVarArr, this.Data.SaveName)

        ModeArr := this.OperModeMap[GetLang(this.Data.OperType)]
        this._SetDDL("OperModeCombo", ModeArr, GetLang(this.Data.OperMode))
        this._SetCombo("TextRowCombo", this.DLVarArr, this.Data.TextRowVar)
        this._SetCombo("NameOrSerialCombo", this.DLVarArr, this.Data.NameOrSerial)
        this._SetCombo("RowCombo", this.DLVarArr, this.Data.RowVar)
        this._SetCombo("ColCombo", this.DLVarArr, this.Data.ColVar)
        this._SetCombo("RowEndCombo", this.DLVarArr, this.Data.RowEndVar)
        this._SetCombo("ColEndCombo", this.DLVarArr, this.Data.ColEndVar)
        this._SetCombo("WriteVarCombo", this.DLAllVarArr, "")
        this._SetCombo("WriteArrCombo", this.DLArrayArr, this.Data.ArrName)
    }

    OnRefreshType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        ModeArr := this.OperModeMap[this._TypeText()]
        this._SetDDL("OperModeCombo", ModeArr, this._ModeText())
        this.RefreshConVisable()
    }

    OnRefreshOperMode(state := "", ctrl := "", event := "") {
        this.RefreshConVisable()
    }

    RefreshConVisable() {
        if (!IsObject(this.ui))
            return
        CurType := this._TypeText()
        CurMode := this._ModeText()
        IsRead := CurType == GetLang("读取Excel") || CurType == GetLang("读取文本文件")
        IsWrite := !IsRead
        IsExcel := CurType == GetLang("读取Excel") || CurType == GetLang("写入Excel")
        IsText := CurType == GetLang("读取文本文件") || CurType == GetLang("写入文本文件")

        IsExcelRange := IsExcel && (CurMode == GetLang("指定行") || CurMode == GetLang("指定列") || CurMode == GetLang("指定区域-行") || CurMode == GetLang("指定区域-列"))
        IsTextRange := IsText && CurMode == GetLang("逐行读取")
        IsExcelResOnlyVar := IsRead && IsExcel && CurMode == GetLang("单元格")
        IsTextResOnlyVar := IsRead && IsText && (CurMode == GetLang("读取全部内容") || CurMode == GetLang("指定行"))
        IsResOnlyVar := IsExcelResOnlyVar || IsTextResOnlyVar

        HasEncoding := IsText
        HasTextRow := IsText && (CurMode == GetLang("指定行") || CurMode == GetLang("逐行读取") || CurMode == GetLang("行号自增"))
        HasExcel := IsExcel
        HasExcelRegion := IsRead && (CurMode == GetLang("指定区域-行") || CurMode == GetLang("指定区域-列"))
        HasRes := IsRead
        HasWriteArr := IsWrite && IsExcelRange
        HasWriteContent := IsWrite && !HasWriteArr

        this._Vis("EncodingRow", HasEncoding)
        this._Vis("TextRowRow", HasTextRow)
        this._Vis("ExcelRow", HasExcel)
        this._Vis("RegionRow", HasExcelRegion)
        this._Vis("ResultGroup", HasRes)
        this._Vis("WriteContentRow", HasWriteContent)
        this._Vis("WriteArrRow", HasWriteArr)

        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), IsResOnlyVar ? GetLang("变量") : GetLang("数组"))
        ResArr := IsResOnlyVar ? GetGuiVarArr() : this.DLArrayArr
        curSave := this.ui.Query("SaveNameCombo")
        this._SetCombo("SaveNameCombo", ResArr, curSave)
    }

    OnSelectPathBtnClick(state := "", ctrl := "", event := "") {
        CurType := this._TypeText()
        IsExcel := CurType == GetLang("读取Excel") || CurType == GetLang("写入Excel")
        IsText := CurType == GetLang("读取文本文件") || CurType == GetLang("写入文本文件")
        SymbolStr := IsExcel ? "Excel Files(*.xlsx; *.xls)" : ""
        SymbolStr := IsText ? "Text Files(*.txt)" : SymbolStr
        path := FileSelect(1, , GetLang("选择输入的源文件"), SymbolStr)
        if (path != "")
            this.ui.Update("FilePathCombo", "Text", path)
    }

    OnRefreshContentVarType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsResVar := this.ui.Query("WriteVarTypeCombo") == GetLang("变量")
        DLArr := IsResVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
        curText := this.ui.Query("WriteVarCombo")
        this._SetCombo("WriteVarCombo", DLArr, curText)
    }

    OnClickAddVarNameBtn(state := "", ctrl := "", event := "") {
        this.ui.Update("ContentCon", "Text", this.ui.Query("ContentCon") . this.ui.Query("WriteVarCombo"))
    }

    OnClickAddVarValueBtn(state := "", ctrl := "", event := "") {
        ArraySymbol := this.ui.Query("WriteVarTypeCombo") == GetLang("变量") ? "" : "ε"
        this.ui.Update("ContentCon", "Text", this.ui.Query("ContentCon") . "{" ArraySymbol this.ui.Query("WriteVarCombo") "}")
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        if (this.ui.Query("FilePathCombo") == "") {
            MsgBox("文件路径不能为空")
            return false
        }
        if (!CheckVarNameIfValid(this.ui.Query("SaveNameCombo")))
            return false

        CurType := this._TypeText()
        CurMode := this._ModeText()
        IsRead := CurType == GetLang("读取Excel") || CurType == GetLang("读取文本文件")
        HasExcelRegion := IsRead && (CurMode == GetLang("指定区域-行") || CurMode == GetLang("指定区域-列"))
        if (HasExcelRegion) {
            err := CheckExcelRegionBounds(this.ui.Query("RowCombo"), this.ui.Query("ColCombo"), this.ui.Query("RowEndCombo"), this.ui.Query("ColEndCombo"))
            if (err != "") {
                MsgBox(err)
                return false
            }
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)

        CurType := this._TypeText()
        IsRead := CurType == GetLang("读取Excel") || CurType == GetLang("读取文本文件")
        if (IsRead) {
            Res := ""
            if (this.Data.SaveType == "变量" && MySoftData.VariableMap.Has(this.Data.SaveName))
                Res := MySoftData.VariableMap[this.Data.SaveName]
            if (this.Data.SaveType == "数组" && MySoftData.ArrayMap.Has(this.Data.SaveName))
                Res := GetArrayStr(MySoftData.ArrayMap[this.Data.SaveName])
            if (Res != "") {
                tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
                tip2 := Format(GetLang("值：{}"), Res)
                MsgBox(tip1 "`n" tip2)
            }
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            Remark := this._TypeText()
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveData() {
        this.Data.OperType := GetLangKey(this._TypeText())
        this.Data.Encoding := GetSoftEncoding(this.ui.Query("EncodingCombo"))
        this.Data.FilePath := this.ui.Query("FilePathCombo")
        this.Data.OperMode := GetLangKey(this._ModeText())
        this.Data.TextRowVar := GetLangKey(this.ui.Query("TextRowCombo"))
        this.Data.NameOrSerial := GetLangKey(this.ui.Query("NameOrSerialCombo"))
        this.Data.RowVar := GetLangKey(this.ui.Query("RowCombo"))
        this.Data.ColVar := GetLangKey(this.ui.Query("ColCombo"))
        this.Data.RowEndVar := GetLangKey(this.ui.Query("RowEndCombo"))
        this.Data.ColEndVar := GetLangKey(this.ui.Query("ColEndCombo"))

        this.Data.Content := GetLangStr(this.ui.Query("ContentCon"), 2)
        this.Data.ArrName := this.ui.Query("WriteArrCombo")

        this.Data.SaveType := GetLangKey(this.ui.Query("SaveTypeCombo"))
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCombo"))

        if (this.ui.Query("ResultGroup>Visibility") != "Collapsed") {
            if (this.Data.SaveType == "变量")
                MySoftData.GlobalVariMap[this.Data.SaveName] := true
            if (this.Data.SaveType == "数组")
                MySoftData.GlobalArrMap[this.Data.SaveName] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
