#Requires AutoHotkey v2.0

; =====================================================================
; 变量编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class VariableGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this.Data := ""
        this.SerialStr := ""
        this._charEditGui := ""      ; §21.3 字符变量编辑窗实例
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)      ; 在 Show 前设值（wpfHwnd 未建，BatchUpdate 入队，窗口创建时一起应用）
        this.OnRefresh()
        this._ShowWindow()
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
        title := this.ParentTile GetLang("变量编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("32", "Auto", "*")
        body.Cols("*")

        ; 行0：备注 + IsIgnoreExist + 帮助
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")
        row0.Add("CheckBox").Name("IsIgnoreExist").Content(GetLang("如果变量存在则不改变数值")).VerticalAlignment("Center").Margin("20,0,0,0")
        row0.Add("Button").Name("BtnHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("8,0,0,0")

        ; 行1：变量 GroupBox（§15.2 滚动区：行数不限，动态增删）
        vg := body.Add("GroupBox").Grid_Row(1).Header(GetLang("变量："))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        vGrid := vg.Add("Grid").Margin("8,4")
        ; §21.3：第5列「编辑」按钮（字符类型用）；§15.2：第6列「删除」按钮
        vGrid.Cols("45", "105", "75", "90", "40", "40", "90", "90")
        vGrid.Rows("26", "190")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("开关")).HorizontalAlignment("Center").VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(1).Text(GetLang("变量名")).VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(2).Text(GetLang("变量类型")).VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(3).Text(GetLang("选择/输入")).VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(4).Text(GetLang("编辑")).HorizontalAlignment("Center").VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(5).Text(GetLang("删除")).HorizontalAlignment("Center").VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(6).Text(GetLang("最小值选择/输入")).VerticalAlignment("Center")
        vGrid.Add("TextBlock").Grid_Row(0).Grid_Column(7).Text(GetLang("最大值选择/输入")).VerticalAlignment("Center")
        ; 行区：ScrollViewer + 命名 StackPanel，行由 _VarRowXml 动态注入（AddXamlItem）
        sv := vGrid.Add("ScrollViewer").Grid_Row(1).Grid_ColumnSpan(8)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        sv.Add("StackPanel").Name("VarRowsPanel")

        ; 行2：添加 + 确定
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnAddVar").Content(GetLang("添加变量")).Width(90).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36).Margin("8,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="720" Height="360" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("BtnAddVar", "Click", ObjBindMethod(this, "OnAddVarRow"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        ; 行区事件在 _RebuildRows 动态绑定（OpType/EditChar/DelRow 每行）
    }

    _ShowWindow() {
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
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
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    ; 批量设置 ComboBox（把 ClearItems/AddXamlItem/Text 合并进 batch，最后一次性 BatchUpdate）
    _BatchSetCombo(batch, comboName, items, text) {
        batch.Push({ControlName: comboName, PropertyName: "ClearItems", Value: ""})
        for it in items {
            if (it == "")
                continue
            batch.Push({ControlName: comboName, PropertyName: "AddItem", Value: it})
        }
        batch.Push({ControlName: comboName, PropertyName: "Text", Value: text})
    }

    _OpTypeValue(i) {
        v := IsObject(this.ui) ? this.ui.Query("OpType" i ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) + 1 : 1
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("变量")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        this._EnsureVarDataLen()
        this._RebuildRows()
        batch := []
        batch.Push({ControlName: "RemarkCon", PropertyName: "Text", Value: cmdArr.Length >= 2 ? cmdArr[2] : ""})
        batch.Push({ControlName: "IsIgnoreExist", PropertyName: "IsChecked", Value: this.Data.IsIgnoreExist ? "True" : "False"})
        this.ui.BatchUpdate(batch)
    }

    ; ---------- §15.2 动态行区 ----------

    ; 保证 6 个并行数组长度一致且至少 1 行（兼容旧配置 4 行/缺字段）
    _EnsureVarDataLen() {
        if (!IsObject(this.Data)) {
            this.Data := VariableData()
            this.Data.SerialStr := this.SerialStr
        }
        if (this.Data.ToggleArr.Length == 0) {
            this.Data.ToggleArr := [1]
            this.Data.OperaTypeArr := [1]
            this.Data.VariableArr := ["Var1"]
            this.Data.CopyVariableArr := ["1"]
            this.Data.MinVariableArr := ["0"]
            this.Data.MaxVariableArr := ["10"]
        }
        n := this.Data.ToggleArr.Length
        while (this.Data.OperaTypeArr.Length < n)
            this.Data.OperaTypeArr.Push(1)
        while (this.Data.VariableArr.Length < n)
            this.Data.VariableArr.Push("Var" (this.Data.VariableArr.Length + 1))
        while (this.Data.CopyVariableArr.Length < n)
            this.Data.CopyVariableArr.Push("0")
        while (this.Data.MinVariableArr.Length < n)
            this.Data.MinVariableArr.Push("0")
        while (this.Data.MaxVariableArr.Length < n)
            this.Data.MaxVariableArr.Push("10")
        while (this.Data.OperaTypeArr.Length > n)
            this.Data.OperaTypeArr.RemoveAt(this.Data.OperaTypeArr.Length)
        while (this.Data.VariableArr.Length > n)
            this.Data.VariableArr.RemoveAt(this.Data.VariableArr.Length)
        while (this.Data.CopyVariableArr.Length > n)
            this.Data.CopyVariableArr.RemoveAt(this.Data.CopyVariableArr.Length)
        while (this.Data.MinVariableArr.Length > n)
            this.Data.MinVariableArr.RemoveAt(this.Data.MinVariableArr.Length)
        while (this.Data.MaxVariableArr.Length > n)
            this.Data.MaxVariableArr.RemoveAt(this.Data.MaxVariableArr.Length)
    }

    ; 每行 XAML（对齐表头 8 列）
    _VarRowXml(i) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        opItems := ""
        for t in GetLangArr(["数值", "随机数值", "字符", "系统", "删除"])
            opItems .= '<ComboBoxItem Content="' t '"/>'
        return '<Grid ' ns ' Margin="0,2">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="45"/><ColumnDefinition Width="105"/><ColumnDefinition Width="75"/>'
            . '<ColumnDefinition Width="90"/><ColumnDefinition Width="40"/><ColumnDefinition Width="40"/>'
            . '<ColumnDefinition Width="90"/><ColumnDefinition Width="90"/>'
            . '</Grid.ColumnDefinitions>'
            . '<CheckBox Grid.Column="0" Name="Tog' i '" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '<ComboBox Grid.Column="1" Name="Var' i '" Height="24" MinHeight="24" IsEditable="True" Margin="0,0,4,0" VerticalContentAlignment="Center"/>'
            . '<ComboBox Grid.Column="2" Name="OpType' i '" Height="24" MinHeight="24" Margin="0,0,4,0">' opItems '</ComboBox>'
            . '<ComboBox Grid.Column="3" Name="Copy' i '" Height="24" MinHeight="24" IsEditable="True" Margin="0,0,4,0" VerticalContentAlignment="Center"/>'
            . '<Button Grid.Column="4" Name="EditChar' i '" Content="✎" Height="22" MinHeight="22" Padding="0" Margin="0,0,4,0" Cursor="Hand" Visibility="Collapsed"/>'
            . '<Button Grid.Column="5" Name="DelRow' i '" Content="×" Height="22" MinHeight="22" Padding="0" Margin="0,0,4,0" Cursor="Hand" FontSize="14" ToolTip="' GetLang("删除该变量") '"/>'
            . '<ComboBox Grid.Column="6" Name="Min' i '" Height="24" MinHeight="24" IsEditable="True" Margin="0,0,4,0" VerticalContentAlignment="Center"/>'
            . '<ComboBox Grid.Column="7" Name="Max' i '" Height="24" MinHeight="24" IsEditable="True" VerticalContentAlignment="Center"/>'
            . '</Grid>'
    }

    ; 重建全部行：ClearItems + 注入 + 绑定事件 + 填值
    _RebuildRows() {
        if (!IsObject(this.ui))
            return
        this._EnsureVarDataLen()
        batch := []
        batch.Push({ControlName: "VarRowsPanel", PropertyName: "ClearItems", Value: ""})
        loop this.Data.ToggleArr.Length
            batch.Push({ControlName: "VarRowsPanel", PropertyName: "AddXamlItem", Value: this._VarRowXml(A_Index)})
        this.ui.BatchUpdate(batch)
        this._BindRowEvents()
        this._FillRows()
    }

    ; 动态注入控件的行事件：清旧回调再挂（AddXamlItem 之后才可绑定）
    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.Update(name, "BindEvent", evt)
    }

    _BindRowEvents() {
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this._Bind("OpType" i, "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
            this._Bind("EditChar" i, "Click", ObjBindMethod(this, "OnClickEditChar", i))
            this._Bind("DelRow" i, "Click", ObjBindMethod(this, "OnDelVarRow", i))
        }
    }

    _FillRows() {
        if (!IsObject(this.ui))
            return
        batch := []
        loop this.Data.ToggleArr.Length {
            i := A_Index
            batch.Push({ControlName: "Tog" i, PropertyName: "IsChecked", Value: this.Data.ToggleArr[i] ? "True" : "False"})
            this._BatchSetCombo(batch, "Var" i, GetGuiVarArr(), GetLang(this.Data.VariableArr[i]))
            batch.Push({ControlName: "OpType" i, PropertyName: "SelectedIndex", Value: String(this.Data.OperaTypeArr[i] - 1)})
            this._BatchSetCombo(batch, "Copy" i, this.GetGuiVarArrByType(this.Data.OperaTypeArr[i]), GetLang(this.Data.CopyVariableArr[i]))
            this._BatchSetCombo(batch, "Min" i, GetGuiVarArr(), GetLang(this.Data.MinVariableArr[i]))
            this._BatchSetCombo(batch, "Max" i, GetGuiVarArr(), GetLang(this.Data.MaxVariableArr[i]))
        }
        this.ui.BatchUpdate(batch)
    }

    ; 添加一行（先保存当前 UI 值再扩展数组，重建后值不丢）
    OnAddVarRow(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this.SaveVariableData()
        n := this.Data.ToggleArr.Length + 1
        this.Data.ToggleArr.Push(1)
        this.Data.OperaTypeArr.Push(1)
        this.Data.VariableArr.Push("Var" n)
        this.Data.CopyVariableArr.Push("0")
        this.Data.MinVariableArr.Push("0")
        this.Data.MaxVariableArr.Push("10")
        this._RebuildRows()
        this.OnRefresh()
    }

    OnDelVarRow(n, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        if (this.Data.ToggleArr.Length <= 1) {
            MsgBox(GetLang("至少保留一个变量"))
            return
        }
        this.SaveVariableData()
        this.Data.ToggleArr.RemoveAt(n)
        this.Data.OperaTypeArr.RemoveAt(n)
        this.Data.VariableArr.RemoveAt(n)
        this.Data.CopyVariableArr.RemoveAt(n)
        this.Data.MinVariableArr.RemoveAt(n)
        this.Data.MaxVariableArr.RemoveAt(n)
        this._RebuildRows()
        this.OnRefresh()
    }

    GetGuiVarArrByType(type) {
        switch type {
            case 1:
                return GetGuiVarArr()
            case 2:
                return []
            case 3:
                return []
            case 4:
                return GetSystemVarArr()
            case 5:
                return []
        }
        return []
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        batch := []
        loop this.Data.ToggleArr.Length {
            i := A_Index
            OperaTypeValue := this._OpTypeValue(i)
            EnableCopy := OperaTypeValue == 1 || OperaTypeValue == 3 || OperaTypeValue == 4
            EnableMinMax := OperaTypeValue == 2
            batch.Push({ControlName: "Copy" i, PropertyName: "IsEnabled", Value: EnableCopy ? "True" : "False"})
            batch.Push({ControlName: "Min" i, PropertyName: "IsEnabled", Value: EnableMinMax ? "True" : "False"})
            batch.Push({ControlName: "Max" i, PropertyName: "IsEnabled", Value: EnableMinMax ? "True" : "False"})
            ; §21.3：字符类型时显示「编辑」按钮
            batch.Push({ControlName: "EditChar" i, PropertyName: "Visibility", Value: OperaTypeValue == 3 ? "Visible" : "Collapsed"})
            CurValue := GetLang(this.ui.Query("Copy" i))
            DLArr := this.GetGuiVarArrByType(OperaTypeValue)
            this._BatchSetCombo(batch, "Copy" i, DLArr, CurValue)
        }
        this.ui.BatchUpdate(batch)
    }

    ; §21.3 字符变量「编辑」按钮：打开构建窗，确定后写回该行「选择/输入」
    OnClickEditChar(rowIdx, state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        if (this._charEditGui == "")
            this._charEditGui := CharVarEditGui()
        this._charEditGui.OwnerHwnd := this.Hwnd()
        this._charEditGui.ParentTile := StrReplace(this._title, GetLang("变量编辑器"), "") "-"
        this._charEditGui.SureBtnAction := (text) => this._OnCharEditSure(rowIdx, text)
        this._charEditGui.ShowGui(this.ui.Query("Copy" rowIdx))
    }

    _OnCharEditSure(rowIdx, text) {
        if (IsObject(this.ui))
            this.ui.Update("Copy" rowIdx, "Text", text)
        if (this._charEditGui != "")
            this._charEditGui.OwnerHwnd := ""
    }

    OnClickTypeHelpBtn(state := "", ctrl := "", event := "") {
        str1 := GetLang("循环次数：如指令上级存在 循环 指令，则该变量为该循环体执行的次数")
        str2 := GetLang("宏循环次数：配置整体执行的次数")
        str3 := GetLang("句柄ID：实时获取当前鼠标窗口句柄ID")
        str4 := GetLang("当前鼠标颜色：实时获取当前鼠标指针下颜色（形如EEFF44）")
        str5 := GetLang("当前鼠标坐标X：实时获取当前鼠标X")
        str6 := GetLang("当前鼠标坐标Y：实时获取当前鼠标Y")
        str7 := GetLang("当前日期：实时获取当前日期（形如2026-04-12）")
        str8 := GetLang("当前时间戳：当前Unix时间戳（秒）")
        str9 := GetLang("当前年：当前年份（形如2026）")
        str10 := GetLang("当前月：当前月份（形如4）")
        str11 := GetLang("当前日：当前日（形如12）")
        str12 := GetLang("当前时：当前小时（形如19）")
        str13 := GetLang("当前分：当前分钟（形如46）")
        str14 := GetLang("当前秒：当前秒（形如58）")
        str15 := GetLang("当前星期几：形如1-7，1代表周一")
        str16 := GetLang("当前剪切板：当前剪切板文本，非文本时为「空」")
        str := Format("{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6, str7, str8, str9, str10, str11, str12, str13, str14, str15, str16)
        MsgBox(str, GetLang("系统变量说明"), "Owner" this.Hwnd())
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveVariableData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        loop this.Data.ToggleArr.Length {
            if (this.ui.Query("Tog" A_Index) == "True" && !CheckVarNameIfValid(this.ui.Query("Var" A_Index)))
                return false
        }
        return true
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            Remark := ""
            loop this.Data.ToggleArr.Length {
                i := A_Index
                if (this.ui.Query("Tog" i) == "True") {
                    CurVarRemark := this.ui.Query("Var" i)
                    if (this._OpTypeValue(i) == 1) {
                        if (IsNumber(this.ui.Query("Copy" i))) {
                            CurVarRemark .= "=" this.ui.Query("Copy" i)
                        }
                    }
                    else if (this._OpTypeValue(i) == 2) {
                        CurVarRemark .= GetLang("随机")
                        isNumSpan := IsNumber(this.ui.Query("Min" i)) && IsNumber(this.ui.Query("Max" i))
                        if (isNumSpan)
                            CurVarRemark .= this.ui.Query("Min" i) "~" this.ui.Query("Max" i)
                    }
                    else if (this._OpTypeValue(i) == 5) {
                        CurVarRemark .= GetLang("删除")
                    }
                    Remark .= CurVarRemark "&"
                }
            }
            Remark := RTrim(Remark, "&")
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveVariableData() {
        this.Data.IsIgnoreExist := this.ui.Query("IsIgnoreExist") == "True" ? 1 : 0
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.Data.ToggleArr[i] := this.ui.Query("Tog" i) == "True" ? 1 : 0
            this.Data.VariableArr[i] := GetLangKey(this.ui.Query("Var" i))
            this.Data.OperaTypeArr[i] := this._OpTypeValue(i)
            this.Data.CopyVariableArr[i] := GetLangKey(this.ui.Query("Copy" i))
            this.Data.MinVariableArr[i] := GetLangKey(this.ui.Query("Min" i))
            this.Data.MaxVariableArr[i] := GetLangKey(this.ui.Query("Max" i))
        }
        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.VariableArr[A_Index]] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
