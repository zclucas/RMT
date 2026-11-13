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
        this._syncing := false
        this.Data := ""
        this.SerialStr := ""
        this.ContentEditGui := ""
        this._contentEditClosed := true
        this.CmdKey := "文件读写"
        textModes := GetLangArr(["读取全部内容", "逐行读取", "指定行"])
        writeModes := GetLangArr(["覆盖写入", "追加写入", "追加写入-行", "指定行", "行号自增"])
        this.OperModeMap := Map(
            GetLang("读取Excel"),
            GetLangArr(["单元格", "指定行", "指定列", "指定区域-行", "指定区域-列"]),
            GetLang("写入Excel"),
            GetLangArr(["单元格", "行号自增", "列号自增", "指定区域-行", "指定区域-列"]),
            GetLang("读取文件"), textModes,
            GetLang("写入文件"), writeModes,
            GetLang("读取文本文件"), textModes,
            GetLang("写入文本文件"), writeModes
        )
    }

    ShowGui(cmd) {
        global MySoftData
        this._ApplyCmdKeyFromCmd(cmd)
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._syncing := true
        this._batching := true
        try {
            this.Init(cmd)
            this.RefreshConVisable()
        } finally {
            this._flushBatch()
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

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
        title := this.ParentTile GetLang(this.CmdKey == "Excel" ? "Excel编辑器" : "文件读写编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,33")
        body.Rows("36", "36", "36", "36", "Auto", "Auto", "Auto", "Auto", "48")
        body.Cols("96", "*", "16", "96", "*")

        ; 行0：备注（白底，内边距与下拉框一致）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：操作类型 + 文件编码
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("操作类型:")).VerticalAlignment("Center")
        ot := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("OperTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in this._OperTypes()
            ot.Add("ComboBoxItem").Content(t)
        encRow := body.Add("Grid").Name("EncodingRow").Grid_Row(1).Grid_Column(3).Grid_ColumnSpan(2).Visibility("Collapsed")
        encRow.Cols("96", "*")
        encRow.Add("TextBlock").Grid_Column(0).Text(GetLang("文件编码:")).VerticalAlignment("Center")
        encRow.Add("ComboBox").Grid_Column(1).Name("EncodingCombo").Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行2：文件路径 + 选择文件
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("文件路径:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Grid_ColumnSpan(3).Name("FilePathCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        body.Add("Button").Grid_Row(2).Grid_Column(4).Name("BtnSelectFile").Content(GetLang("选择文件")).Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left").Margin("8,0,0,0")

        ; 行3：操作模式 + 行号
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("操作模式:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(1).Name("OperModeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        textRow := body.Add("Grid").Name("TextRowRow").Grid_Row(3).Grid_Column(3).Grid_ColumnSpan(2).Visibility("Collapsed")
        textRow.Cols("96", "*")
        textRow.Add("TextBlock").Grid_Column(0).Text(GetLang("行号:")).VerticalAlignment("Center")
        textRow.Add("ComboBox").Grid_Column(1).Name("TextRowCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行4：表名或序号 / 表格行号 / 表格列号（两行，避免裁切）
        excelRow := body.Add("Grid").Name("ExcelRow").Grid_Row(4).Grid_ColumnSpan(5)
        excelRow.Rows("36", "36")
        excelRow.Cols("96", "*", "16", "96", "*")
        excelRow.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("表名或序号:")).VerticalAlignment("Center")
        excelRow.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("NameOrSerialCon").Height(26).MinHeight(26).VerticalAlignment("Center")
        excelRow.Add("TextBlock").Grid_Row(0).Grid_Column(3).Text(GetLang("表格行号:")).VerticalAlignment("Center")
        excelRow.Add("ComboBox").Grid_Row(0).Grid_Column(4).Name("RowCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        excelRow.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("表格列号:")).VerticalAlignment("Center")
        excelRow.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("ColCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行5：终止行号 + 终止列号
        regionRow := body.Add("Grid").Name("RegionRow").Grid_Row(5).Grid_ColumnSpan(5).Visibility("Collapsed")
        regionRow.Rows("36")
        regionRow.Cols("96", "*", "16", "96", "*")
        regionRow.Add("TextBlock").Grid_Column(0).Text(GetLang("终止行号:")).VerticalAlignment("Center")
        regionRow.Add("ComboBox").Grid_Column(1).Name("RowEndCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        regionRow.Add("TextBlock").Grid_Column(3).Text(GetLang("终止列号:")).VerticalAlignment("Center")
        regionRow.Add("ComboBox").Grid_Column(4).Name("ColEndCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行6：结果（去掉结果保存标题和边框）
        resultRow := body.Add("Grid").Name("ResultRow").Grid_Row(6).Grid_ColumnSpan(5)
        resultRow.Rows("36")
        resultRow.Cols("96", "80", "16", "150", "*")
        resultRow.Add("TextBlock").Grid_Column(0).Text(GetLang("结果：")).VerticalAlignment("Center")
        st := resultRow.Add("ComboBox").Grid_Column(1).Name("SaveTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center")
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        resultRow.Add("ComboBox").Grid_Column(3).Name("SaveNameCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行7：写入内容（白底框 + 右上角悬浮编辑，打开文本构造）/ 写入数组
        writeRow := body.Add("Grid").Name("WriteContentRow").Grid_Row(7).Grid_ColumnSpan(5).Visibility("Collapsed")
        writeRow.Rows("64")
        writeRow.Add("TextBox").Name("ContentCon").AcceptsReturn("True").TextWrapping("Wrap")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch").MinHeight("64")
            .VerticalContentAlignment("Top").Padding("4,3,26,3").FontSize("11")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
        writeRow.Add("Button").Name("BtnContentEdit").Width("22").Height("22").MinHeight("22").Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        writeArrRow := body.Add("Grid").Name("WriteArrRow").Grid_Row(7).Grid_ColumnSpan(5).Visibility("Collapsed")
        writeArrRow.Rows("36")
        writeArrRow.Cols("96", "*", "16", "96", "*")
        writeArrRow.Add("TextBlock").Grid_Column(0).Text(GetLang("写入数组：")).VerticalAlignment("Center")
        writeArrRow.Add("ComboBox").Grid_Column(1).Name("WriteArrCombo").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 行8：确定
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="580" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, this.CmdKey == "Excel" ? "#指令手册/Excel" : "#指令手册/17-文件读写", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("OperTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshType"))
        this.ui.OnEvent("OperModeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefreshOperMode"))
        this.ui.OnEvent("BtnSelectFile", "Click", ObjBindMethod(this, "OnSelectPathBtnClick"))
        this.ui.OnEvent("BtnContentEdit", "Click", ObjBindMethod(this, "OpenContentEditor"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._syncing := false
    }

    OnWindowClosing(state, ctrl, event) {
        this._CloseContentEditor()
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
        this._CloseContentEditor()
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
        this._ComboPush(name, "Visibility", show ? "Visible" : "Collapsed")
    }

    _TypeText() => IsObject(this.ui) ? this.ui.Query("OperTypeCombo") : ""
    _ModeText() => IsObject(this.ui) ? this.ui.Query("OperModeCombo") : ""

    _ApplyCmdKeyFromCmd(cmd) {
        if (cmd == "")
            return
        param := StrSplit(cmd, "_")[1]
        SplitSerialTextAndNumbers(param, &textOnly, &dummy)
        key := GetLangKey(textOnly)
        if (key == "Excel")
            this.CmdKey := "Excel"
        else if (key == "文件读写")
            this.CmdKey := "文件读写"
    }

    _OperTypes() {
        extra := IsObject(this.Data) ? this.Data.OperType : ""
        return FileIOOperTypes(this.CmdKey == "Excel" ? "excel" : "file", extra)
    }

    _EnsureDefaultOper() {
        if (this.CmdKey == "Excel") {
            if (!FileIOIsExcelType(this.Data.OperType)) {
                this.Data.OperType := "读取Excel"
                this.Data.OperMode := "单元格"
            }
        } else if (!FileIOIsTextType(this.Data.OperType)) {
            this.Data.OperType := "读取文件"
            this.Data.OperMode := "读取全部内容"
        }
    }

    Init(cmd) {
        this._ApplyCmdKeyFromCmd(cmd)
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr(this.CmdKey)
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        if (cmd == "")
            this._EnsureDefaultOper()
        this.DLVarArr := GetGuiVarArr("count")
        this.DLArrayArr := GetGuiArrNameArr()

        this._SetDDL("OperTypeCombo", this._OperTypes(), GetLang(this.Data.OperType))
        this._SetDDL("EncodingCombo", GetLangArr(MySoftData.FileEncodingArr), GetEncodingDisplayName(this.Data.Encoding))
        ; 路径下拉给的是 {变量} 形式：选中即得到可被 GetReplaceVarText 解析的完整占位符
        this._SetCombo("FilePathCombo", GetGuiVarReferences("clipboard"), TranslateBuiltinVarReferences(this.Data.FilePath, true))
        this._ComboPush("ContentCon", "Text", GetLangStr(this.Data.Content, 1))
        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), GetLang(this.Data.SaveType))
        this._SetCombo("SaveNameCombo", GetGuiVarArr(), this.Data.SaveName)

        ModeArr := this.OperModeMap[GetLang(this.Data.OperType)]
        this._SetDDL("OperModeCombo", ModeArr, GetLang(this.Data.OperMode))
        this._SetCombo("TextRowCombo", this.DLVarArr, GetLang(this.Data.TextRowVar))
        this._ComboPush("NameOrSerialCon", "Text", this.Data.NameOrSerial)
        this._SetCombo("RowCombo", this.DLVarArr, GetLang(this.Data.RowVar))
        this._SetCombo("ColCombo", this.DLVarArr, GetLang(this.Data.ColVar))
        this._SetCombo("RowEndCombo", this.DLVarArr, GetLang(this.Data.RowEndVar))
        this._SetCombo("ColEndCombo", this.DLVarArr, GetLang(this.Data.ColEndVar))
        this._SetCombo("WriteArrCombo", this.DLArrayArr, this.Data.ArrName)
    }

    OnRefreshType(state := "", ctrl := "", event := "") {
        if (this._syncing || !IsObject(this.ui))
            return
        ModeArr := this.OperModeMap[this._TypeText()]
        this._SetDDL("OperModeCombo", ModeArr, this._ModeText())
        this.RefreshConVisable()
    }

    OnRefreshOperMode(state := "", ctrl := "", event := "") {
        if (this._syncing || !IsObject(this.ui))
            return
        this.RefreshConVisable()
    }

    RefreshConVisable() {
        if (!IsObject(this.ui))
            return
        ; 开窗同步期控件尚未落地，用 Data 判断显隐，避免 Query 到默认项后再闪一次
        if (this._syncing && IsObject(this.Data)) {
            CurType := GetLang(this.Data.OperType)
            CurMode := GetLang(this.Data.OperMode)
        } else {
            CurType := this._TypeText()
            CurMode := this._ModeText()
        }
        IsRead := FileIOIsReadType(CurType)
        IsWrite := !IsRead
        IsExcel := FileIOIsExcelType(CurType)
        IsText := FileIOIsTextType(CurType)

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
        this._Vis("ResultRow", HasRes)
        this._Vis("WriteContentRow", HasWriteContent)
        this._Vis("WriteArrRow", HasWriteArr)

        this._SetDDL("SaveTypeCombo", GetLangArr(["变量", "数组"]), IsResOnlyVar ? GetLang("变量") : GetLang("数组"))
        ResArr := IsResOnlyVar ? GetGuiVarArr() : this.DLArrayArr
        curSave := (this._syncing && IsObject(this.Data)) ? this.Data.SaveName : this.ui.Query("SaveNameCombo")
        this._SetCombo("SaveNameCombo", ResArr, curSave)
    }

    OnSelectPathBtnClick(state := "", ctrl := "", event := "") {
        CurType := this._TypeText()
        IsExcel := FileIOIsExcelType(CurType)
        SymbolStr := IsExcel ? "Excel Files(*.xlsx; *.xls)" : ""
        path := FileSelect(1, , GetLang("选择输入的源文件"), SymbolStr)
        if (path != "")
            this.ui.Update("FilePathCombo", "Text", path)
    }

    _CloseContentEditor() {
        if (IsObject(this.ContentEditGui) && !this._contentEditClosed) {
            try this.ContentEditGui.Update("Window", "Close", "")
            this.ContentEditGui := ""
            this._contentEditClosed := true
        }
    }

    OpenContentEditor(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ContentEditGui) || this._contentEditClosed)
            this._BuildContentEditor()
        if (this.ContentEditGui.Query("ContentEditVarTypeCombo") == "")
            this.ContentEditGui.Update("ContentEditVarTypeCombo", "SelectedIndex", "0")
        this._FillContentEditNameCombo()
        curText := IsObject(this.ui) ? this.ui.Query("ContentCon") : ""
        this.ContentEditGui.Update("ContentEditCon", "Text", curText)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        if (!XamlWin.Open(this.ContentEditGui, "", owner))
            this._contentEditClosed := true
    }

    _BuildContentEditor() {
        global MySoftData
        this._CloseContentEditor()
        this._contentEditClosed := false
        title := this.ParentTile GetLang("文本构造")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,8").ClipToBounds("False")
        body.Rows("Auto", "6", "32", "48")

        body.Add("TextBox").Grid_Row(0).Name("ContentEditCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("2,3").FontSize("11")
            .Height("95").MinHeight("95")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        row1 := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        row1.Cols("88", "80", "8", "200", "8", "70", "8", "70")
        row1.Add("TextBlock").Grid_Column(0).Text(GetLang("变量数组：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        vt := row1.Add("ComboBox").Grid_Column(1).Name("ContentEditVarTypeCombo").Height(26).MinHeight(26).VerticalAlignment("Center").SelectedIndex("0")
        vt.Add("ComboBoxItem").Content(GetLang("变量"))
        vt.Add("ComboBoxItem").Content(GetLang("数组"))
        row1.Add("ComboBox").Grid_Column(3).Name("ContentEditVariCombo").Width("200").Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Left").IsEditable("True")
        row1.Add("Button").Grid_Column(5).Name("BtnContentAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).VerticalAlignment("Center")
        row1.Add("Button").Grid_Column(7).Name("BtnContentAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).VerticalAlignment("Center")

        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnContentOk")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        this.ContentEditGui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        this.ContentEditGui.xaml := StrReplace(this.ContentEditGui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="580" SizeToContent="Height"')
        this.ContentEditGui.xaml := StrReplace(this.ContentEditGui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ContentEditGui.xaml := StrReplace(this.ContentEditGui.xaml, '%resources%', '')

        this.ContentEditGui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnContentEditClosing"))
        this.ContentEditGui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnContentEditLoad"))
        this.ContentEditGui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnContentEditClose"))
        this.ContentEditGui.OnEvent("ContentEditVarTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnContentEditVarTypeChange"))
        this.ContentEditGui.OnEvent("BtnContentAddName", "Click", ObjBindMethod(this, "OnContentEditAddName"))
        this.ContentEditGui.OnEvent("BtnContentAddValue", "Click", ObjBindMethod(this, "OnContentEditAddValue"))
        this.ContentEditGui.OnEvent("ContentEditCon", "TextChanged", ObjBindMethod(this, "OnContentEditChange"))
        this.ContentEditGui.OnEvent("BtnContentOk", "Click", ObjBindMethod(this, "OnContentEditClose"))
    }

    OnContentEditLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ContentEditGui)
    }

    OnContentEditClosing(state, ctrl, event) {
        this._contentEditClosed := true
        this.ContentEditGui := ""
    }

    OnContentEditChange(state := "", ctrl := "", event := "") {
        if (IsObject(this.ContentEditGui) && !this._contentEditClosed && IsObject(this.ui))
            this.ui.Update("ContentCon", "Text", this.ContentEditGui.Query("ContentEditCon"))
    }

    _FillContentEditNameCombo() {
        if (!IsObject(this.ContentEditGui) || this._contentEditClosed)
            return
        isVar := this.ContentEditGui.Query("ContentEditVarTypeCombo") == GetLang("变量")
        items := isVar ? GetGuiVarArr("all") : GetGuiArrNameArr()
        cur := this.ContentEditGui.Query("ContentEditVariCombo")
        this.ContentEditGui.Update("ContentEditVariCombo", "ClearItems", "")
        for v in items {
            if (v != "")
                this.ContentEditGui.Update("ContentEditVariCombo", "AddItem", v)
        }
        found := false
        loop items.Length {
            if (items[A_Index] == cur) {
                this.ContentEditGui.Update("ContentEditVariCombo", "SelectedIndex", String(A_Index - 1))
                found := true
                break
            }
        }
        if (!found && items.Length > 0)
            this.ContentEditGui.Update("ContentEditVariCombo", "SelectedIndex", "0")
    }

    OnContentEditVarTypeChange(state := "", ctrl := "", event := "") {
        this._FillContentEditNameCombo()
    }

    OnContentEditAddName(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ContentEditGui) || this._contentEditClosed)
            return
        varName := this.ContentEditGui.Query("ContentEditVariCombo")
        if (varName != "") {
            this.ContentEditGui.Update("ContentEditCon", "InsertText", varName)
            this.OnContentEditChange()
        }
    }

    OnContentEditAddValue(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ContentEditGui) || this._contentEditClosed)
            return
        varName := this.ContentEditGui.Query("ContentEditVariCombo")
        if (varName != "") {
            arrMark := this.ContentEditGui.Query("ContentEditVarTypeCombo") == GetLang("变量") ? "" : "ε"
            this.ContentEditGui.Update("ContentEditCon", "InsertText", "{" arrMark varName "}")
            this.OnContentEditChange()
        }
    }

    OnContentEditClose(state := "", ctrl := "", event := "") {
        this._CloseContentEditor()
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
            RmtDialog.Info("文件路径不能为空")
            return false
        }
        if (this.ui.Query("ResultRow>Visibility") != "Collapsed") {
            if (!CheckVarNameIfValid(this.ui.Query("SaveNameCombo")))
                return false
        }

        CurType := this._TypeText()
        CurMode := this._ModeText()
        IsRead := FileIOIsReadType(CurType)
        HasExcelRegion := IsRead && (CurMode == GetLang("指定区域-行") || CurMode == GetLang("指定区域-列"))
        if (HasExcelRegion) {
            err := CheckExcelRegionBounds(this.ui.Query("RowCombo"), this.ui.Query("ColCombo"), this.ui.Query("RowEndCombo"), this.ui.Query("ColEndCombo"))
            if (err != "") {
                RmtDialog.Info(err)
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
        IsRead := FileIOIsReadType(CurType)
        if (IsRead) {
            Res := ""
            if (this.Data.SaveType == "变量" && MySoftData.VariableMap.Has(this.Data.SaveName))
                Res := MySoftData.VariableMap[this.Data.SaveName]
            if (this.Data.SaveType == "数组" && MySoftData.ArrayMap.Has(this.Data.SaveName))
                Res := GetArrayStr(MySoftData.ArrayMap[this.Data.SaveName])
            if (Res != "") {
                tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
                tip2 := Format(GetLang("值：{}"), Res)
                RmtDialog.Info(tip1 "`n" tip2)
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
        this.Data.OperType := FileIONormType(this._TypeText())
        this.Data.Encoding := GetAhkEncodingName(this.ui.Query("EncodingCombo"))
        this.Data.FilePath := TranslateBuiltinVarReferences(this.ui.Query("FilePathCombo"))
        this.Data.OperMode := GetLangKey(this._ModeText())
        this.Data.TextRowVar := GetLangKey(this.ui.Query("TextRowCombo"))
        this.Data.NameOrSerial := this.ui.Query("NameOrSerialCon")
        this.Data.RowVar := GetLangKey(this.ui.Query("RowCombo"))
        this.Data.ColVar := GetLangKey(this.ui.Query("ColCombo"))
        this.Data.RowEndVar := GetLangKey(this.ui.Query("RowEndCombo"))
        this.Data.ColEndVar := GetLangKey(this.ui.Query("ColEndCombo"))

        this.Data.Content := GetLangStr(this.ui.Query("ContentCon"), 2)
        this.Data.ArrName := this.ui.Query("WriteArrCombo")

        this.Data.SaveType := GetLangKey(this.ui.Query("SaveTypeCombo"))
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCombo"))

        if (this.ui.Query("ResultRow>Visibility") != "Collapsed") {
            if (this.Data.SaveType == "变量")
                MySoftData.GlobalVariMap[this.Data.SaveName] := true
            if (this.Data.SaveType == "数组")
                MySoftData.GlobalArrMap[this.Data.SaveName] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
