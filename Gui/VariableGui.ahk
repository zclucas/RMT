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

    _VarScrollStyles() {
        return '<ControlTemplate x:Key="VarSbThumb" TargetType="Thumb">'
            . '<Border x:Name="bd" Background="{DynamicResource ControlBorder}" CornerRadius="3" Opacity="0.7" Margin="1"/>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Accent}"/><Setter TargetName="bd" Property="Opacity" Value="1"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate>'
            . '<Style x:Key="VarSbVertical" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="true">'
            . '<Track.Thumb><Thumb Template="{StaticResource VarSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style x:Key="VarThemedSV" TargetType="ScrollViewer">'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollViewer"><Grid>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions>'
            . '<ScrollContentPresenter x:Name="PART_ScrollContentPresenter" Grid.Column="0" Margin="{TemplateBinding Padding}" Content="{TemplateBinding Content}" ContentTemplate="{TemplateBinding ContentTemplate}" CanContentScroll="{TemplateBinding CanContentScroll}"/>'
            . '<ScrollBar x:Name="PART_VerticalScrollBar" Width="8" MinWidth="8" Grid.Column="1" Value="{TemplateBinding VerticalOffset}" Maximum="{TemplateBinding ScrollableHeight}" ViewportSize="{TemplateBinding ViewportHeight}" Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}" Style="{StaticResource VarSbVertical}"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter></Style>'
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
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,12")
        body.Rows("36", "22", "168", "40")

        ; 行0：备注 + 存在则不改 + 帮助
        top := body.Add("Grid").Grid_Row(0)
        top.Cols("48", "200", "Auto", "28")
        top.Add("TextBlock").Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontWeight("Bold")
        top.Add("TextBox").Grid_Column(1).Name("RemarkCon").Width(200).Height(26).MinHeight(26).VerticalAlignment("Center")
            .HorizontalAlignment("Left").VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        top.Add("CheckBox").Grid_Column(2).Name("IsIgnoreExist").Content(GetLang("如果变量存在则不改变数值"))
            .VerticalAlignment("Center").Margin("12,0,8,0").Foreground("{DynamicResource TextMain}")
        top.Add("Button").Grid_Column(3).Name("BtnHelp").Width(22).Height(22).MinHeight(22).Padding("0")
            .VerticalAlignment("Center").Cursor("Hand").ToolTip(GetLang("系统变量说明"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Content(Chr(0xE946))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 行1：列标题（边框上方，非粗体）
        lab := body.Add("Grid").Grid_Row(1).Margin("1,0,9,0").HorizontalAlignment("Center")
        lab.Cols("100", "8", "90", "8", "110", "8", "80", "8", "80", "8", "22")
        lab.Add("TextBlock").Grid_Column(0).Text(GetLang("新变量")).HorizontalAlignment("Center").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        lab.Add("TextBlock").Grid_Column(2).Text(GetLang("类型")).HorizontalAlignment("Center").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        lab.Add("TextBlock").Grid_Column(4).Text(GetLang("值")).HorizontalAlignment("Center").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        lab.Add("TextBlock").Grid_Column(6).Name("LabMin").Text(GetLang("最小值")).HorizontalAlignment("Center").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        lab.Add("TextBlock").Grid_Column(8).Name("LabMax").Text(GetLang("最大值")).HorizontalAlignment("Center").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")

        ; 行2：变量框（固定 6 行可视高度，可无限增删）
        box := body.Add("Border").Grid_Row(2).Padding("0,4")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
            .Background("{DynamicResource ControlBg}").SnapsToDevicePixels("True")
        sv := box.Add("ScrollViewer").MinHeight("0")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
            .Style("{StaticResource VarThemedSV}")
        sv.Add("StackPanel").Name("VarRowsPanel").HorizontalAlignment("Center")

        ; 行3：确定
        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnOk")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="600" Height="330" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._VarScrollStyles())

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/11-变量")
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        ; 行区事件在 _RebuildRows 动态绑定（OpType/EditChar/DelRow/BtnAddVar）
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

    ; 旧 OperaType 7（时间类别）在界面上按「时间」(5) 显示
    _UiOpType(i) {
        ot := this.Data.OperaTypeArr[i]
        return ot == 7 ? 5 : ot
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
            this.Data.CopyVariableArr := ["0"]
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

    _FlatBtnTemplate() {
        return '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"'
            . ' BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"'
            . ' SnapsToDevicePixels="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Button.Template>'
    }

    _IconBtnXml(name, glyph, tip, vis := "Visible", col := "", margin := "") {
        colAttr := col != "" ? ' Grid.Column="' col '"' : ""
        marAttr := margin != "" ? ' Margin="' margin '"' : ""
        return '<Button Name="' name '"' colAttr marAttr ' Width="22" Height="22" MinHeight="22" Padding="0" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Content="' glyph '"'
            . ' ToolTip="' this._EscapeXml(tip) '" Visibility="' vis '"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center">'
            . this._FlatBtnTemplate()
            . '</Button>'
    }

    ; 每行 XAML（对齐边框上方列标题）
    _VarRowXml(i) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        opItems := ""
        for t in GetLangArr(["数值", "随机数值", "字符", "系统", "时间", "删除"])
            opItems .= '<ComboBoxItem Content="' t '"/>'
        combo := ' Height="26" MinHeight="26" VerticalContentAlignment="Center"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"'
        ot := (IsObject(this.Data) && this.Data.HasOwnProp("OperaTypeArr") && this.Data.OperaTypeArr.Length >= i) ? this.Data.OperaTypeArr[i] : 1
        if (ot == 7)
            ot := 5
        copyOn := ot == 1 || ot == 3 || ot == 4 || ot == 5
        mmOn := ot == 2
        copyEn := copyOn ? "True" : "False"
        copyOp := copyOn ? "1" : "0.45"
        mmEn := mmOn ? "True" : "False"
        mmOp := mmOn ? "1" : "0.45"
        return '<Grid ' ns ' Height="28" HorizontalAlignment="Center">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="100"/><ColumnDefinition Width="8"/><ColumnDefinition Width="90"/>'
            . '<ColumnDefinition Width="8"/><ColumnDefinition Width="110"/><ColumnDefinition Width="8"/>'
            . '<ColumnDefinition Width="80"/><ColumnDefinition Width="8"/><ColumnDefinition Width="80"/>'
            . '<ColumnDefinition Width="8"/><ColumnDefinition Width="22"/>'
            . '</Grid.ColumnDefinitions>'
            . '<ComboBox Grid.Column="0" Name="Var' i '" IsEditable="True"' combo '/>'
            . '<ComboBox Grid.Column="2" Name="OpType' i '"' combo '>' opItems '</ComboBox>'
            . '<Grid Grid.Column="4">'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            . '<ComboBox Grid.Column="0" Name="Copy' i '" IsEditable="True" IsEnabled="' copyEn '" Opacity="' copyOp '"' combo '/>'
            . this._IconBtnXml("EditChar" i, "&#xE70F;", GetLang("编辑"), "Collapsed", "1", "8,0,0,0")
            . '</Grid>'
            . '<ComboBox Grid.Column="6" Name="Min' i '" IsEditable="True" IsEnabled="' mmEn '" Opacity="' mmOp '"' combo '/>'
            . '<ComboBox Grid.Column="8" Name="Max' i '" IsEditable="True" IsEnabled="' mmEn '" Opacity="' mmOp '"' combo '/>'
            . this._IconBtnXml("DelRow" i, "&#xE74D;", GetLang("删除该变量"), "Visible", "10")
            . '</Grid>'
    }

    _AddVarBtnXml() {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Height="28" Margin="0,2,0,0" HorizontalAlignment="Center">'
            . this._IconBtnXml("BtnAddVar", "&#xE710;", GetLang("添加变量"))
            . '</StackPanel>'
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
        batch.Push({ControlName: "VarRowsPanel", PropertyName: "AddXamlItem", Value: this._AddVarBtnXml()})
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
        this._Bind("BtnAddVar", "Click", ObjBindMethod(this, "OnAddVarRow"))
    }

    _FillRows() {
        if (!IsObject(this.ui))
            return
        batch := []
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this._BatchSetCombo(batch, "Var" i, GetGuiVarArr(), GetLang(this.Data.VariableArr[i]))
            batch.Push({ControlName: "OpType" i, PropertyName: "SelectedIndex", Value: String(this._UiOpType(i) - 1)})
            copyVal := this.Data.CopyVariableArr[i]
            if (copyVal == "" && this._UiOpType(i) == 1)
                copyVal := "0"
            this._BatchSetCombo(batch, "Copy" i, this.GetGuiVarArrByType(this._UiOpType(i)), GetLang(copyVal))
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
                return GetTimeCategoryVarArr()
            case 6:
                return []               ; 删除：无需源值
            case 7:
                return GetTimeCategoryVarArr()   ; 旧时间类别
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
            EnableCopy := OperaTypeValue == 1 || OperaTypeValue == 3 || OperaTypeValue == 4 || OperaTypeValue == 5
            EnableMinMax := OperaTypeValue == 2
            batch.Push({ControlName: "Copy" i, PropertyName: "IsEnabled", Value: EnableCopy ? "True" : "False"})
            batch.Push({ControlName: "Copy" i, PropertyName: "Opacity", Value: EnableCopy ? "1" : "0.45"})
            batch.Push({ControlName: "Min" i, PropertyName: "IsEnabled", Value: EnableMinMax ? "True" : "False"})
            batch.Push({ControlName: "Max" i, PropertyName: "IsEnabled", Value: EnableMinMax ? "True" : "False"})
            batch.Push({ControlName: "Min" i, PropertyName: "Opacity", Value: EnableMinMax ? "1" : "0.45"})
            batch.Push({ControlName: "Max" i, PropertyName: "Opacity", Value: EnableMinMax ? "1" : "0.45"})
            ; 字符类型时显示「编辑」按钮（叠在「值」框右侧，不占列间距）
            batch.Push({ControlName: "EditChar" i, PropertyName: "Visibility", Value: OperaTypeValue == 3 ? "Visible" : "Collapsed"})
            CurValue := GetLang(this.ui.Query("Copy" i))
            if ((CurValue == "" || CurValue == "True" || CurValue == "False") && OperaTypeValue == 1)
                CurValue := "0"
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
        str5 := GetLang("当前坐标X：实时获取当前鼠标X")
        str6 := GetLang("当前坐标Y：实时获取当前鼠标Y")
        str7 := GetLang("当前剪切板：仅剪切板是文本时有效，否则变量值为「空」")
        str7b := GetLang("当前时间戳：当前Unix时间戳（秒）")
        str8 := GetLang("当前年：当前年份（形如2026）")
        str9 := GetLang("当前月：当前月份（形如4）")
        str10 := GetLang("当前周：当前是一年中的第几周（形如41）")
        str11 := GetLang("当前星期：形如1-7，1代表周一")
        str12 := GetLang("当前日：当前日（形如12）")
        str13 := GetLang("当前时：当前小时（形如19）")
        str14 := GetLang("当前分：当前分钟（形如46）")
        str15 := GetLang("当前秒：当前秒（形如58）")
        str := Format("{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6, str7, str7b, str8, str9, str10, str11, str12, str13, str14, str15)
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
            if (!CheckVarNameIfValid(this.ui.Query("Var" A_Index)))
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
                    CurVarRemark .= GetLang("时间")
                }
                else if (this._OpTypeValue(i) == 6) {
                    CurVarRemark .= GetLang("删除")
                }
                Remark .= CurVarRemark "&"
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
            this.Data.ToggleArr[i] := 1
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
