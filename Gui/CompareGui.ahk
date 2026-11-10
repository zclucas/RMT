#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 如果编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 内部 new MacroEditGui() 编辑真/假分支指令（引用保持）
; =====================================================================

class CompareGui {
    __new() {
        this.WindowBindingContext := ""
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.MacroGui := ""
        ; 原生 FocusCon 是「备注」标签控件，供嵌套 MacroEditGui.SureFocusCon 关窗后 Focus；
        ; XAML 版无法持有原生控件，改用带 Focus() 的轻量 facade（聚焦 XAML 的 RemarkCon）
        ; ⚠️ 闭包必须写成 (*) 变参：调用方是 facade.Focus() 方法式调用，AHK v2 会把 facade
        ;    自身作为首参传进来；ObjBindMethod 已绑定 this、不再吃参数
        ;    → 会报 "Too many parameters passed to function"（2026-09-10 实测修复）
        this.FocusCon := { Focus: (*) => this._FocusRemark() }
        this._closed := true
        this._title := ""

        this.Data := ""
        this.DLVariableArr := []
        this.ResultConArr := ["ResultSaveLabel", "SaveNameCon", "ResultLabelTrueCon", "TrueValueCon", "ResultLabelFalseCon", "FalseValueCon"]
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)   ; XAML 窗口不支持隐藏复用：关旧重建
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)
        this.OnRefresh()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("如果编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Name("CmdRoot").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,14")
        body.Rows("34", this._CondiBoxRowH(), "88", "34", "48")
        body.Cols("28", "*", "8", "90", "8", "*", "28")

        ; === 逻辑关系 + 备注（备注与比较下拉左对齐）===
        top := body.Add("Grid").Grid_Row(0).Grid_ColumnSpan(7)
        top.Cols("28", "*", "8", "90", "8", "*", "28")
        logicSp := top.Add("StackPanel").Grid_Column(0).Grid_ColumnSpan(2).Orientation("Horizontal").VerticalAlignment("Center")
        logicSp.Add("TextBlock").Text(GetLang("逻辑关系：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        logicCon := logicSp.Add("ComboBox").Name("LogicalTypeCon").Width(70).Height(26).MinHeight(26).Margin("4,0,0,0").SelectedIndex("0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["且", "或"])
            logicCon.Add("ComboBoxItem").Content(t)
        top.Add("TextBlock").Grid_Column(3).Text(GetLang("备注：")).VerticalAlignment("Center").HorizontalAlignment("Left").Foreground("{DynamicResource TextMain}").FontSize("12")
        top.Add("TextBox").Grid_Column(5).Grid_ColumnSpan(2).Name("RemarkCon").Height(26).MinHeight(26).VerticalAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; === 条件边框：默认 4 行高度，右侧固定预留主题滚动条 ===
        bd := body.Add("Border").Name("CondiBox").Grid_Row(1).Grid_ColumnSpan(7)
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
            .Padding("8,6,0,6").Margin("0,4,0,4").ClipToBounds("True")
        sv := bd.Add("ScrollViewer").Name("CondiScroll").Height(this._CondiViewH())
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
            .Padding("0").Margin("0").Style("{StaticResource IfThemedSV}")
        condiHost := sv.Add("StackPanel")
        condiHost.Add("StackPanel").Name("CondiRowsPanel")
        plusRow := condiHost.Add("Grid").Name("BtnAddCondiRow").Margin("0,2,0,0")
        plusRow.Cols("28", "*", "8", "90", "8", "*", "28")
        plusRow.Add("Button").Name("BtnAddCondi").Grid_Column(3).Width(24).Height(24).MinHeight(24)
            .HorizontalAlignment("Center").VerticalAlignment("Center").Cursor("Hand").ToolTip(GetLang("添加"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE710))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("0")

        ; === 真/假 分支指令 ===
        macroRow := body.Add("Grid").Grid_Row(2).Grid_ColumnSpan(7)
        macroRow.Cols("*", "8", "*")

        foundCol := macroRow.Add("StackPanel").Grid_Column(0).Orientation("Vertical")
        ft := foundCol.Add("StackPanel").Orientation("Horizontal")
        ft.Add("TextBlock").Text(GetLang("真-分支指令:（可选）")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ft.Add("Button").Name("BtnTrueEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        foundCol.Add("TextBox").Name("TrueMacroCon").Height(46).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        unfoundCol := macroRow.Add("StackPanel").Grid_Column(2).Orientation("Vertical")
        ft2 := unfoundCol.Add("StackPanel").Orientation("Horizontal")
        ft2.Add("TextBlock").Text(GetLang("假-分支指令:（可选）")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ft2.Add("Button").Name("BtnFalseEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        unfoundCol.Add("TextBox").Name("FalseMacroCon").Height(46).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 结果保存 ===
        saveRow := body.Add("Grid").Grid_Row(3).Grid_ColumnSpan(7).VerticalAlignment("Center")
        saveRow.Cols("*", "8", "*")
        saveLeft := saveRow.Add("Grid").Grid_Column(0)
        saveLeft.Cols("Auto", "*")
        saveHead := saveLeft.Add("StackPanel").Grid_Column(0).Orientation("Horizontal").VerticalAlignment("Center")
        saveHead.Add("CheckBox").Name("SaveToggleCon").VerticalAlignment("Center")
        saveHead.Add("TextBlock").Name("ResultSaveLabel").Text(GetLang("结果保存")).VerticalAlignment("Center").Margin("6,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        saveLeft.Add("ComboBox").Grid_Column(1).Name("SaveNameCon").Height(26).MinHeight(26).Margin("8,0,0,0").IsEditable("True")
            .HorizontalAlignment("Stretch").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        saveRight := saveRow.Add("StackPanel").Grid_Column(2).Orientation("Horizontal").VerticalAlignment("Center").HorizontalAlignment("Right")
        saveRight.Add("TextBlock").Name("ResultLabelTrueCon").Text(GetLang("真值")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        saveRight.Add("TextBox").Name("TrueValueCon").Width(70).Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        saveRight.Add("TextBlock").Name("ResultLabelFalseCon").Text(GetLang("假值")).VerticalAlignment("Center").Margin("12,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        saveRight.Add("TextBox").Name("FalseValueCon").Width(70).Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 底部按钮 ===
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(7).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnSure")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="540" Height="' this._FitHeight() '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._CondiScrollStyles())

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/13-如果", ObjBindMethod(this, "TriggerMacro"), "!l")
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnTrueEdit", "Click", ObjBindMethod(this, "OnTrueBtnClick"))
        this.ui.OnEvent("BtnFalseEdit", "Click", ObjBindMethod(this, "OnFalseBtnClick"))
        this.ui.OnEvent("BtnAddCondi", "Click", ObjBindMethod(this, "OnAddCondi"))
        this.ui.OnEvent("SaveToggleCon", "Click", ObjBindMethod(this, "OnRefresh"))
    }

    _CondiScrollStyles() {
        return '<ControlTemplate x:Key="IfSbThumb" TargetType="Thumb">'
            . '<Border x:Name="bd" Background="{DynamicResource ControlBorder}" CornerRadius="3" Opacity="0.7" Margin="1"/>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Accent}"/><Setter TargetName="bd" Property="Opacity" Value="1"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate>'
            . '<Style x:Key="IfSbVertical" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="true">'
            . '<Track.Thumb><Thumb Template="{StaticResource IfSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style x:Key="IfThemedSV" TargetType="ScrollViewer">'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollViewer"><Grid>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions>'
            . '<ScrollContentPresenter x:Name="PART_ScrollContentPresenter" Grid.Column="0" Margin="{TemplateBinding Padding}" Content="{TemplateBinding Content}" ContentTemplate="{TemplateBinding ContentTemplate}" CanContentScroll="{TemplateBinding CanContentScroll}"/>'
            . '<ScrollBar x:Name="PART_VerticalScrollBar" Width="8" MinWidth="8" Grid.Column="1" Value="{TemplateBinding VerticalOffset}" Maximum="{TemplateBinding ScrollableHeight}" ViewportSize="{TemplateBinding ViewportHeight}" Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}" Style="{StaticResource IfSbVertical}"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _CondiViewH() {
        return 30 * 4
    }

    _CondiBoxRowH() {
        return 8 + 2 + 12 + this._CondiViewH()
    }

    _FitHeight() {
        return Integer(XAMLHost.CmdTitleBarHeight()) + 10 + 14 + 34 + this._CondiBoxRowH() + 88 + 34 + 48
    }

    _EnsureCondiDataLen() {
        if (!IsObject(this.Data))
            this.Data := CompareData()
        if (this.Data.ToggleArr.Length == 0) {
            this.Data.ToggleArr := [1]
            this.Data.NameArr := ["Var1"]
            this.Data.CompareTypeArr := [1]
            this.Data.VariableArr := ["Var1"]
        }
        n := this.Data.ToggleArr.Length
        while (this.Data.NameArr.Length < n)
            this.Data.NameArr.Push("Var" (this.Data.NameArr.Length + 1))
        while (this.Data.CompareTypeArr.Length < n)
            this.Data.CompareTypeArr.Push(1)
        while (this.Data.VariableArr.Length < n)
            this.Data.VariableArr.Push("Var" (this.Data.VariableArr.Length + 1))
        while (this.Data.NameArr.Length > n)
            this.Data.NameArr.RemoveAt(this.Data.NameArr.Length)
        while (this.Data.CompareTypeArr.Length > n)
            this.Data.CompareTypeArr.RemoveAt(this.Data.CompareTypeArr.Length)
        while (this.Data.VariableArr.Length > n)
            this.Data.VariableArr.RemoveAt(this.Data.VariableArr.Length)
    }

    _CondiRowXml(i) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        cmpItems := ""
        for t in GetCompareTypeLangArr()
            cmpItems .= '<ComboBoxItem Content="' this._EscapeXml(t) '"/>'
        tip := this._EscapeXml(GetLang("删除"))
        return '<Grid ' ns ' Margin="0,2">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/>'
            . '<ColumnDefinition Width="90"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/>'
            . '</Grid.ColumnDefinitions>'
            . '<CheckBox Grid.Column="0" Name="ToggleCon_' i '" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . '<ComboBox Grid.Column="1" Name="NameCon_' i '" Height="26" MinHeight="26" IsEditable="True" VerticalContentAlignment="Center"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<ComboBox Grid.Column="3" Name="CompareTypeCon_' i '" Height="26" MinHeight="26" VerticalContentAlignment="Center"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1">' cmpItems '</ComboBox>'
            . '<ComboBox Grid.Column="5" Name="VariableCon_' i '" Height="26" MinHeight="26" IsEditable="True" VerticalContentAlignment="Center"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Grid.Column="6" Name="DelCondi_' i '" Width="24" Height="24" MinHeight="24" Padding="0" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Content="&#xE74D;" ToolTip="' tip '"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Grid>'
    }

    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.BindEventBatched(name, evt)
    }

    _BindRowEvents() {
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this._Bind("ToggleCon_" i, "Click", ObjBindMethod(this, "OnRefresh"))
            this._Bind("CompareTypeCon_" i, "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
            this._Bind("DelCondi_" i, "Click", ObjBindMethod(this, "OnDelCondi", i))
        }
    }

    _BatchSetCombo(batch, comboName, items, text) {
        batch.Push({ControlName: comboName, PropertyName: "ClearItems", Value: ""})
        for it in items {
            if (it == "")
                continue
            batch.Push({ControlName: comboName, PropertyName: "AddItem", Value: it})
        }
        batch.Push({ControlName: comboName, PropertyName: "Text", Value: text})
    }

    _RebuildRows() {
        if (!IsObject(this.ui))
            return
        this._EnsureCondiDataLen()
        batch := []
        batch.Push({ControlName: "CondiRowsPanel", PropertyName: "ClearItems", Value: ""})
        loop this.Data.ToggleArr.Length
            batch.Push({ControlName: "CondiRowsPanel", PropertyName: "AddXamlItem", Value: this._CondiRowXml(A_Index)})
        this.ui.BatchUpdate(batch)
        this._BindRowEvents()
        this._FillRows()
    }

    _FillRows() {
        if (!IsObject(this.ui))
            return
        batch := []
        loop this.Data.ToggleArr.Length {
            i := A_Index
            tog := this.Data.ToggleArr[i] ? "True" : "False"
            batch.Push({ControlName: "ToggleCon_" i, PropertyName: "IsChecked", Value: tog})
            this._BatchSetCombo(batch, "NameCon_" i, this.DLVariableArr, GetLang(this.Data.NameArr[i]))
            ct := this.Data.CompareTypeArr[i]
            batch.Push({ControlName: "CompareTypeCon_" i, PropertyName: "SelectedIndex", Value: String(CompareTypeToComboIndex(ct))})
            this._BatchSetCombo(batch, "VariableCon_" i, this.DLVariableArr, GetLang(this.Data.VariableArr[i]))
            onlyOne := this.Data.ToggleArr.Length <= 1
            batch.Push({ControlName: "DelCondi_" i, PropertyName: "IsEnabled", Value: onlyOne ? "False" : "True"})
        }
        this.ui.BatchUpdate(batch)
    }

    OnAddCondi(*) {
        if (!IsObject(this.ui))
            return
        this.SaveCompareData()
        n := this.Data.ToggleArr.Length + 1
        this.Data.ToggleArr.Push(1)
        this.Data.NameArr.Push("Var" n)
        this.Data.CompareTypeArr.Push(1)
        this.Data.VariableArr.Push("Var" n)
        this._RebuildRows()
        try this.ui.Update("CondiScroll", "ScrollToEnd", "")
        this.OnRefresh()
    }

    OnDelCondi(n, *) {
        if (!IsObject(this.ui))
            return
        if (this.Data.ToggleArr.Length <= 1) {
            RmtDialog.Info(GetLang("至少保留一个条件"), , "Owner" this.Hwnd())
            return
        }
        this.SaveCompareData()
        this.Data.ToggleArr.RemoveAt(n)
        this.Data.NameArr.RemoveAt(n)
        this.Data.CompareTypeArr.RemoveAt(n)
        this.Data.VariableArr.RemoveAt(n)
        this._RebuildRows()
        this.OnRefresh()
    }

    ; ---------------- 数据读写辅助 ----------------

    _SetCombo(comboName, items, text) {
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    ; 非编辑 ComboBox 按文本匹配设置 SelectedIndex（等价原生 DropDownList.Text 赋值）
    _SetComboByText(comboName, items, text) {
        idx := 0
        for i, it in items {
            if (it == text) {
                idx := i - 1
                break
            }
        }
        this.ui.Update(comboName, "SelectedIndex", String(idx))
    }

    _ToggleInt(v) {
        return (v == 1 || v == "1" || v == true || v == "True") ? 1 : 0
    }

    ; Query 在窗口未加载（wpfHwnd 为 0）时返回空串（§4.2）：一律 IsNumber 保护再算术
    _CompareIndex(idx) {
        v := IsObject(this.ui) ? this.ui.Query("CompareTypeCon_" idx ">SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 0
        return Integer(v)
    }

    _LogicalIndex() {
        v := IsObject(this.ui) ? this.ui.Query("LogicalTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 0
        return Integer(v)
    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("如果")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.Data.SerialStr := this.SerialStr
        this.DLVariableArr := GetGuiVarArr(1)

        ; 原生 DropDownList.Value 为 1-based，XAML SelectedIndex 为 0-based
        this.ui.Update("TrueMacroCon", "Text", GetLangMacro(ObjHasOwnProp(this.Data, "TrueMacro") ? this.Data.TrueMacro : "", 1))
        this.ui.Update("FalseMacroCon", "Text", GetLangMacro(ObjHasOwnProp(this.Data, "FalseMacro") ? this.Data.FalseMacro : "", 1))
        this.ui.Update("SaveToggleCon", "IsChecked", this._ToggleInt(ObjHasOwnProp(this.Data, "SaveToggle") ? this.Data.SaveToggle : 0) ? "True" : "False")
        this._SetCombo("SaveNameCon", GetGuiVarArr(), GetLang(ObjHasOwnProp(this.Data, "SaveName") ? this.Data.SaveName : ""))
        this.ui.Update("TrueValueCon", "Text", ObjHasOwnProp(this.Data, "TrueValue") ? this.Data.TrueValue : 1)
        this.ui.Update("FalseValueCon", "Text", ObjHasOwnProp(this.Data, "FalseValue") ? this.Data.FalseValue : 0)
        logical := ObjHasOwnProp(this.Data, "LogicalType") ? this.Data.LogicalType : "且"
        this.ui.Update("LogicalTypeCon", "SelectedIndex", String(CmdEnumIndex(logical, CmdEnumLogicNames())))
        this._RebuildRows()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    CheckIfValid() {
        if (this.ui.Query("SaveToggleCon") == "True" && !CheckVarNameIfValid(this.ui.Query("SaveNameCon")))
            return false

        return true
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            Hotkey("!l", MacroAction, "On")
        }
        else {
            Hotkey("!l", MacroAction, "Off")
        }
    }

    OnRefresh(*) {
        if (!IsObject(this.ui))
            return
        loop this.Data.ToggleArr.Length {
            i := A_Index
            isEnable := this.ui.Query("ToggleCon_" i) == "True"
            this.ui.Update("NameCon_" i, "IsEnabled", isEnable ? "True" : "False")
            this.ui.Update("CompareTypeCon_" i, "IsEnabled", isEnable ? "True" : "False")
            enableVari := !IsCompareExistVar(ComboIndexToCompareType(this._CompareIndex(i))) && isEnable
            this.ui.Update("VariableCon_" i, "IsEnabled", enableVari ? "True" : "False")
        }

        canEditResult := this.ui.Query("SaveToggleCon") == "True"
        for name in this.ResultConArr
            this.ui.Update(name, "IsEnabled", canEditResult ? "True" : "False")
    }

    OnClickSureBtn(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveCompareData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.OnGuiClose()
    }

    OnTrueSure(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.ui.Update("TrueMacroCon", "Text", CommandStr)
    }

    OnFalseSure(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.ui.Update("FalseMacroCon", "Text", CommandStr)
    }

    OnTrueBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.SureFocusCon := this.FocusCon

            ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            this.MacroGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        this.MacroGui.SureBtnAction := (command) => this.OnTrueSure(command)
        this.MacroGui.ShowGui(this.ui.Query("TrueMacroCon"), false, this.WindowBindingContext)
    }

    OnFalseBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.SureFocusCon := this.FocusCon

            ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            this.MacroGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        this.MacroGui.SureBtnAction := (command) => this.OnFalseSure(command)
        this.MacroGui.ShowGui(this.ui.Query("FalseMacroCon"), false, this.WindowBindingContext)
    }

    TriggerMacro(*) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveCompareData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveCompareData() {
        this.Data.TrueMacro := GetLangMacro(this.ui.Query("TrueMacroCon"), 2)
        this.Data.FalseMacro := GetLangMacro(this.ui.Query("FalseMacroCon"), 2)
        this.Data.SaveToggle := this.ui.Query("SaveToggleCon") == "True" ? 1 : 0
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        this.Data.TrueValue := this.ui.Query("TrueValueCon")
        this.Data.FalseValue := this.ui.Query("FalseValueCon")
        this.Data.LogicalType := CmdEnumFromIndex(this._LogicalIndex(), CmdEnumLogicNames())
        n := this.Data.ToggleArr.Length
        this.Data.ToggleArr := []
        this.Data.NameArr := []
        this.Data.CompareTypeArr := []
        this.Data.VariableArr := []
        loop n {
            i := A_Index
            this.Data.ToggleArr.Push(this.ui.Query("ToggleCon_" i) == "True" ? 1 : 0)
            this.Data.NameArr.Push(GetLangKey(this.ui.Query("NameCon_" i)))
            this.Data.CompareTypeArr.Push(ComboIndexToCompareType(this._CompareIndex(i)))
            this.Data.VariableArr.Push(GetLangKey(this.ui.Query("VariableCon_" i)))
        }

        ; 添加全局变量，方便下拉选取
        if (this.Data.SaveToggle) {
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        }

        SaveMacroCMDData(this.Data)
    }

    ; ---------------- 生命周期 ----------------

    _FocusRemark() {
        if (IsObject(this.ui))
            try this.ui.Update("RemarkCon", "Focus", "True")
    }

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
