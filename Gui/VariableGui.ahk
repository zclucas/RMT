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

    _EscapeXml(s) => EscapeXamlXml(s)

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
        top.Cols("*", "*")
        remark := top.Add("Grid").Grid_Column(0).Cols("48", "200")
        remark.Add("TextBlock").Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontWeight("Bold")
        remark.Add("TextBox").Grid_Column(1).Name("RemarkCon").Width(200).Height(26).MinHeight(26).VerticalAlignment("Center")
            .HorizontalAlignment("Left").VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        ; 值列起点为内容中线左侧 19，与居中的 602 宽变量行保持一致。
        options := top.Add("Grid").Grid_Column(1).Margin("-19,0,0,0").HorizontalAlignment("Left").Cols("Auto", "28")
        ignore := options.Add("CheckBox").Grid_Column(0).Name("IsIgnoreExist").Content(GetLang("如果变量存在则不改变数值"))
            .VerticalAlignment("Center").Margin("0,0,8,0").Padding("0").Foreground("{DynamicResource TextMain}")
        ignore.InjectResources(this._IgnoreExistStyle())
        help := options.Add("Button").Grid_Column(1).Name("BtnHelp").Width(22).Height(22).MinHeight(22).Padding("0")
            .VerticalAlignment("Center").Cursor("Hand").ToolTip(GetLang("系统变量说明"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Content(Chr(0xE946))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        helpTemplate := help.Add("Button.Template").Add("ControlTemplate").TargetType("Button")
        helpTemplate.Add("Border").Name("HelpBg").Background("{TemplateBinding Background}")
            .BorderBrush("{TemplateBinding BorderBrush}").BorderThickness("1").CornerRadius("3")
            .Add("ContentPresenter").HorizontalAlignment("Center").VerticalAlignment("Center")
        hover := helpTemplate.Add("ControlTemplate.Triggers").Add("Trigger").Property("IsMouseOver").Value("True")
        hover.Add("Setter").TargetName("HelpBg").Property("Background").Value("{DynamicResource EditHoverBg}")
        hover.Add("Setter").TargetName("HelpBg").Property("BorderBrush").Value("{DynamicResource Accent}")

        ; 列标题放在外框上方，与滚动区预留的滚动条宽度对齐。
        body.Add("StackPanel").Grid_Row(1).Name("VarHeaderPanel").Margin("1,0,9,0").HorizontalAlignment("Center")

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
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="660" Height="330"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._VarScrollStyles())

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/11-变量")
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
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

    ; 批量设置 ComboBox（把 ClearItems/AddXamlItem/Text 合并进 batch，最后一次性 BatchUpdate）
    _BatchSetCombo(batch, comboName, items, text) {
        text := GetVariableComboText(items, text)
        batch.Push({ControlName: comboName, PropertyName: "ClearItems", Value: ""})
        for it in items {
            if (it == "")
                continue
            batch.Push(CmdEditorForm.ComboItemUpdate(comboName, it))
        }
        batch.Push({ControlName: comboName, PropertyName: "Text", Value: text})
    }

    _OpTypeValue(i) {
        v := IsObject(this.ui) ? this.ui.Query("OpType" i ">SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumVariableNames())
    }

    _UiOpIndex(i) {
        ot := (IsObject(this.Data) && this.Data.OperaTypeArr.Length >= i) ? this.Data.OperaTypeArr[i] : "赋值"
        return CmdEnumIndex(CmdEnumOpera(ot), CmdEnumVariableNames())
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : AllocateCommandSerial("变量")
        this.Data := JSON.parse(JSON.stringify(GetMacroCMDData(this.SerialStr)), , false)

        this._EnsureVarDataLen()
        rows := this.Data.ToggleArr.Length
        Loop rows {
            row := rows - A_Index + 1
            if (!this.Data.ToggleArr[row])
                this._RemoveVarRow(row)
        }
        this._EnsureVarDataLen()
        this._autoRemark := ReadCommandAutoRemark(this.Data, this._GenerateRemark.Bind(this))
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
            this.Data.OperaTypeArr := ["赋值"]
            this.Data.VariableArr := ["Data1"]
            this.Data.CopyVariableArr := ["0"]
            this.Data.MinVariableArr := ["0"]
            this.Data.MaxVariableArr := ["10"]
        }
        n := this.Data.ToggleArr.Length
        while (this.Data.OperaTypeArr.Length < n)
            this.Data.OperaTypeArr.Push("赋值")
        while (this.Data.VariableArr.Length < n)
            this.Data.VariableArr.Push("Data" (this.Data.VariableArr.Length + 1))
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

    _IgnoreExistStyle() {
        return '<Style TargetType="CheckBox"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">'
            . '<StackPanel Orientation="Horizontal" Background="Transparent">'
            . '<Border x:Name="Box" Width="17" Height="17" CornerRadius="3" BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" Background="{DynamicResource InputBg}">'
            . '<TextBlock x:Name="Check" Text="&#xE73E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" Foreground="{DynamicResource ActionText}"/></Border>'
            . '<ContentPresenter Margin="4,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True"/></StackPanel>'
            . '<ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Check" Property="Visibility" Value="Visible"/><Setter TargetName="Box" Property="Background" Value="{DynamicResource ActionBg}"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _VarColumnsXml() {
        return '<Grid.ColumnDefinitions><ColumnDefinition Width="180"/><ColumnDefinition Width="8"/>'
            . '<ColumnDefinition Width="90"/><ColumnDefinition Width="8"/>'
            . '<ColumnDefinition Width="139"/><ColumnDefinition Width="8"/><ColumnDefinition Width="139"/>'
            . '<ColumnDefinition Width="8"/><ColumnDefinition Width="22"/></Grid.ColumnDefinitions>'
    }

    ; 标题只取决于第一行；各行独立切换值或随机范围，共用相同总宽度。
    _VarHeaderXml(random) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        label := ' TextAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'
        xml := '<Grid ' ns ' Height="22">' this._VarColumnsXml()
            . '<TextBlock Grid.Column="0" Text="' GetLang("新变量") '"' label
            . '<TextBlock Grid.Column="2" Text="' GetLang("类型") '"' label
        if (random)
            xml .= '<TextBlock Grid.Column="4" Text="' GetLang("最小值") '"' label
                . '<TextBlock Grid.Column="6" Text="' GetLang("最大值") '"' label
        else
            xml .= '<TextBlock Grid.Column="4" Grid.ColumnSpan="3" Text="' GetLang("值") '"' label
        return xml '</Grid>'
    }

    _VarRowXml(i) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        opItems := ""
        for type in GetLangArr(CmdEnumVariableNames())
            opItems .= '<ComboBoxItem Content="' this._EscapeXml(type) '"/>'
        combo := ' Height="26" MinHeight="26" VerticalAlignment="Center" VerticalContentAlignment="Center"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"'
        type := CmdEnumOpera(this.Data.OperaTypeArr[i])
        random := type == "随机数值"
        copyOn := type == "赋值" || type == "系统" || type == "时间"
        randomVisibility := random ? "Visible" : "Collapsed"
        ; 跨列值区域随列宽伸展，右侧留出布局取整余量，避免边框裁切。
        return '<Grid ' ns ' Height="32" HorizontalAlignment="Center">' this._VarColumnsXml()
            . '<Grid Grid.Column="0" Name="VarCell' i '">'
            . '<ComboBox Name="Var' i '" IsEditable="True"' combo '/></Grid>'
            . '<ComboBox Grid.Column="2" Name="OpType' i '"' combo '>' opItems '</ComboBox>'
            . '<Grid Grid.Column="4" Name="CopyCell' i '" Grid.ColumnSpan="3" Margin="0,0,1,0" Visibility="' (random ? "Collapsed" : "Visible") '">'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            . '<ComboBox Name="Copy' i '" IsEditable="True" Visibility="' (copyOn ? "Visible" : "Hidden") '"' combo '/>'
            . '<TextBlock Name="HintCopy' i '" Text="—" Visibility="' (copyOn ? "Hidden" : "Visible") '" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . this._IconBtnXml("EditChar" i, "&#xE70F;", GetLang("编辑"), type == "赋值" ? "Visible" : "Collapsed", "1", "8,0,0,0")
            . '</Grid>'
            . '<Grid Grid.Column="4" Name="MinCell' i '" Visibility="' randomVisibility '">'
            . '<ComboBox Name="Min' i '" IsEditable="True"' combo '/></Grid>'
            . '<Grid Grid.Column="6" Name="MaxCell' i '" Visibility="' randomVisibility '">'
            . '<ComboBox Name="Max' i '" IsEditable="True"' combo '/></Grid>'
            . this._IconBtnXml("DelRow" i, "&#xE74D;", GetLang("删除该变量"), "Visible", "8")
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
        NormalizeVariableAssignmentRows(this.Data)
        random := CmdEnumOpera(this.Data.OperaTypeArr[1]) == "随机数值"
        batch := []
        batch.Push({ControlName: "VarHeaderPanel", PropertyName: "ClearItems", Value: ""})
        batch.Push({ControlName: "VarHeaderPanel", PropertyName: "AddXamlItem", Value: this._VarHeaderXml(random)})
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
        this.ui.BindEventBatched(name, evt)
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
            batch.Push({ControlName: "OpType" i, PropertyName: "SelectedIndex", Value: String(this._UiOpIndex(i))})
            copyVal := this.Data.CopyVariableArr[i]
            this._BatchSetCombo(batch, "Copy" i, this.GetGuiVarArrByType(CmdEnumFromIndex(this._UiOpIndex(i), CmdEnumVariableNames())), TranslateBuiltinVarReferences(copyVal, true))
            this._BatchSetCombo(batch, "Min" i, GetGuiVarArr("number"), GetLang(this.Data.MinVariableArr[i]))
            this._BatchSetCombo(batch, "Max" i, GetGuiVarArr("number"), GetLang(this.Data.MaxVariableArr[i]))
        }
        this.ui.BatchUpdate(batch)
    }

    ; 添加一行（先保存当前 UI 值再扩展数组，重建后值不丢）
    OnAddVarRow(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this._ReadVariableRows()
        n := this.Data.ToggleArr.Length + 1
        this.Data.ToggleArr.Push(1)
        this.Data.OperaTypeArr.Push("赋值")
        this.Data.VariableArr.Push("Data" n)
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
            RmtDialog.Info(GetLang("至少保留一个变量"))
            return
        }
        this._ReadVariableRows()
        this._RemoveVarRow(n)
        this._RebuildRows()
        this.OnRefresh()
    }

    _RemoveVarRow(n) {
        this.Data.ToggleArr.RemoveAt(n)
        this.Data.OperaTypeArr.RemoveAt(n)
        this.Data.VariableArr.RemoveAt(n)
        this.Data.CopyVariableArr.RemoveAt(n)
        this.Data.MinVariableArr.RemoveAt(n)
        this.Data.MaxVariableArr.RemoveAt(n)
    }

    GetGuiVarArrByType(type) {
        switch CmdEnumOpera(type) {
            case "赋值":
                return GetGuiVarReferences("all")
            case "系统":
                return GetSystemVarArr()
            case "时间":
                return GetTimeCategoryVarArr()
            case "随机数值", "删除":
                return []
        }
        return []
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        firstRandom := this._OpTypeValue(1) == "随机数值"
        batch := []
        batch.Push({ControlName: "VarHeaderPanel", PropertyName: "ClearItems", Value: ""})
        batch.Push({ControlName: "VarHeaderPanel", PropertyName: "AddXamlItem", Value: this._VarHeaderXml(firstRandom)})
        loop this.Data.ToggleArr.Length {
            i := A_Index
            type := this._OpTypeValue(i)
            random := type == "随机数值"
            copyOn := type == "赋值" || type == "系统" || type == "时间"
            batch.Push({ControlName: "CopyCell" i, PropertyName: "Visibility", Value: random ? "Collapsed" : "Visible"})
            for cell in ["MinCell", "MaxCell"]
                batch.Push({ControlName: cell i, PropertyName: "Visibility", Value: random ? "Visible" : "Collapsed"})
            batch.Push({ControlName: "Copy" i, PropertyName: "Visibility", Value: copyOn ? "Visible" : "Hidden"})
            batch.Push({ControlName: "HintCopy" i, PropertyName: "Visibility", Value: copyOn ? "Hidden" : "Visible"})
            batch.Push({ControlName: "EditChar" i, PropertyName: "Visibility", Value: type == "赋值" ? "Visible" : "Collapsed"})
            value := this.ui.Query("Copy" i)
            this._BatchSetCombo(batch, "Copy" i, this.GetGuiVarArrByType(type), value)
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
        RmtDialog._Show("", GetLang("系统变量说明"), [GetLang("确定")], Chr(0xE946),
            "{DynamicResource Accent}", this.Hwnd(), "", ObjBindMethod(this, "_SystemHelpBody"))
    }

    _SystemHelpBody(panel) {
        entries := [
            "循环次数：如指令上级存在 循环 指令，则该变量为该循环体执行的次数",
            "宏循环次数：配置整体执行的次数",
            "运行时句柄ID：实时获取当前鼠标窗口句柄ID",
            "运行时鼠标颜色：实时获取当前鼠标指针下颜色（形如EEFF44）",
            "运行时坐标X：实时获取当前鼠标X",
            "运行时坐标Y：实时获取当前鼠标Y",
            "运行时剪切板：仅剪切板是文本时有效，否则变量值为「空」",
            "运行时时间戳：当前Unix时间戳（毫秒）",
            "运行时年：当前年份（形如2026）",
            "运行时月：当前月份（形如4）",
            "运行时周：当前是一年中的第几周（形如41）",
            "运行时星期：形如1-7，1代表周一",
            "运行时日：当前日（形如12）",
            "运行时时：当前小时（形如19）",
            "运行时分：当前分钟（形如46）",
            "运行时秒：当前秒（形如58）",
            "运行时窗口坐标X：鼠标相对所在窗口客户区的X坐标",
            "运行时窗口坐标Y：鼠标相对所在窗口客户区的Y坐标"
        ]
        entries.Push("日期文本：当前日期，格式为 yyyy-MM-dd（如 2026-04-12）",
            "时分文本：当前时分，格式为 HH:mm（如 19:46）",
            "时分秒文本：当前时分秒，格式为 HH:mm:ss（如 19:46:58）")
        tabs := panel.Add("TabControl").Name("SystemHelpTabs").SelectedIndex(0)
            .Background("{DynamicResource BgColor}").BorderThickness("0")
        tabs.InjectResources(this._SystemHelpTabStyles())
        timeNames := Map()
        for name in GetTimeCategoryVarArr()
            timeNames[GetBuiltinVarName(name)] := true
        for category in ["系统", "时间"] {
            tab := tabs.Add("TabItem").Header(GetLang(category))
            selected := []
            for entry in entries {
                name := StrSplit(entry, "：", , 2)[1]
                if (timeNames.Has(name) == (category == "时间"))
                    selected.Push(entry)
            }
            this._SystemHelpTable(tab, selected)
        }
    }

    _SystemHelpTabStyles() {
        return '<Style TargetType="TabControl"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TabControl">'
            . '<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
            . '<TabPanel IsItemsHost="True" Margin="0,0,0,8"/>'
            . '<ContentPresenter Grid.Row="1" ContentSource="SelectedContent"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style TargetType="TabItem"><Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TabItem">'
            . '<Border x:Name="TabBg" Padding="18,7" Margin="0,0,6,0" CornerRadius="4" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . '<ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="TabBg" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger>'
            . '<Trigger Property="IsSelected" Value="True"><Setter TargetName="TabBg" Property="Background" Value="{DynamicResource ActionBg}"/><Setter TargetName="TabBg" Property="BorderBrush" Value="{DynamicResource ActionStroke}"/><Setter Property="Foreground" Value="{DynamicResource ActionText}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _SystemHelpTable(parent, entries) {
        scroll := parent.Add("ScrollViewer").MaxHeight(440).VerticalScrollBarVisibility("Auto")
            .HorizontalScrollBarVisibility("Disabled")
        table := scroll.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Background("{DynamicResource InputBg}").TextElement_Foreground("{DynamicResource TextMain}")
            .Add("Grid").Cols("Auto", "*")
        heights := []
        for entry in entries
            heights.Push("Auto")
        table.Rows(heights*)
        for index, entry in entries {
            parts := StrSplit(entry, "：", , 2)
            translated := GetLang(entry)
            description := RegExReplace(translated, "^[^：:]+[：:]\s*", "")
            bottom := index == entries.Length ? "0" : "1"
            table.Add("Border").Grid_Row(index - 1).Padding("8,6")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,0,1," bottom)
                .Add("TextBlock").Text(GetLang(parts[1])).VerticalAlignment("Center")
            detail := table.Add("Border").Grid_Row(index - 1).Grid_Column(1).Padding("8,6")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,0,0," bottom)
                .Add("Grid").Cols("24", "*")
            detail.Add("TextBlock").Text(GetBuiltinVariableIcon(parts[1]))
                .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Foreground("{DynamicResource TextSub}")
                .HorizontalAlignment("Left").Margin("0,2,0,0")
            detail.Add("TextBlock").Grid_Column(1).Text(description).TextWrapping("Wrap")
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        CommandStr := this.SaveVariableData()
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

    _GenerateRemark(data) {
        remark := ""
        loop data.ToggleArr.Length {
            i := A_Index
            part := GetLang(data.VariableArr[i])
            switch CmdEnumOpera(data.OperaTypeArr[i]) {
                case "赋值":
                    value := data.CopyVariableArr[i]
                    if (IsNumber(value))
                        part .= "=" value
                case "随机数值":
                    part .= GetLang("随机")
                    min := data.MinVariableArr[i], max := data.MaxVariableArr[i]
                    if (IsNumber(min) && IsNumber(max))
                        part .= min "~" max
                case "时间":
                    part .= GetLang("时间")
                case "删除":
                    part .= GetLang("删除")
            }
            remark .= part "&"
        }
        return RTrim(remark, "&")
    }

    _ReadVariableRows() {
        this.Data.IsIgnoreExist := this.ui.Query("IsIgnoreExist") == "True" ? 1 : 0
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.Data.ToggleArr[i] := 1
            this.Data.VariableArr[i] := GetVarName(this.ui.Query("Var" i))
            this.Data.OperaTypeArr[i] := this._OpTypeValue(i)
            this.Data.CopyVariableArr[i] := this.Data.OperaTypeArr[i] == "赋值"
                ? TranslateBuiltinVarReferences(this.ui.Query("Copy" i)) : GetLangKey(this.ui.Query("Copy" i))
            this.Data.MinVariableArr[i] := GetLangKey(this.ui.Query("Min" i))
            this.Data.MaxVariableArr[i] := GetLangKey(this.ui.Query("Max" i))
        }
    }

    SaveVariableData() {
        this._ReadVariableRows()
        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.VariableArr[A_Index]] := true
        }
        CommandStr := FormatCommandAutoRemark(this.Data, this.ui.Query("RemarkCon"), this._autoRemark
            , this._GenerateRemark.Bind(this), true)
        SaveMacroCMDData(this.Data)
        return CommandStr
    }
}
