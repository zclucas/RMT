#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 循环编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 内部 new MacroEditGui() 编辑循环体（引用保持）
; =====================================================================

class LoopGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.MacroGui := ""
        ; 原生 FocusCon 是「确定」按钮控件，供嵌套 MacroEditGui.SureFocusCon 关窗后 Focus；
        ; XAML 版无法持有原生控件，改用带 Focus() 的轻量 facade（聚焦 XAML 的 BtnSure）
        ; ⚠️ 闭包必须写成 (*) 变参：调用方是 facade.Focus() 方法式调用，AHK v2 会把 facade
        ;    自身作为首参传进来；ObjBindMethod 已绑定 this、不再吃参数
        ;    → 会报 "Too many parameters passed to function"（2026-09-10 实测修复）
        this.FocusCon := { Focus: (*) => this._FocusSureBtn() }
        this._closed := true
        this._title := ""

        this.Data := ""
        this.DLVariableArr := []
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
        title := this.ParentTile GetLang("循环编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Name("CmdRoot").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "86", this._CondiBoxRowH(), "Auto", "48")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 循环次数 / 条件类型 左对齐；备注 / 逻辑关系 右列对齐 ===
        head := main.Add("Grid").Grid_Row(1).Margin("16,8,16,6").ClipToBounds("False")
        head.Cols("Auto", "8", "150", "16", "Auto", "8", "*")
        head.Rows("36", "36")

        head.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("循环次数：")).VerticalAlignment("Center").HorizontalAlignment("Left").Foreground("{DynamicResource TextMain}").FontSize("12")
        head.Add("ComboBox").Grid_Row(0).Grid_Column(2).Name("CountCon").Height(28).MinHeight(28).VerticalAlignment("Center").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True").ClipToBounds("False")
        head.Add("TextBlock").Grid_Row(0).Grid_Column(4).Text(GetLang("备注：")).VerticalAlignment("Center").HorizontalAlignment("Right").Foreground("{DynamicResource TextMain}").FontSize("12")
        head.Add("TextBox").Grid_Row(0).Grid_Column(6).Name("RemarkCon").Height(28).MinHeight(28).VerticalAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").VerticalContentAlignment("Center").Padding("6,0")
            .SnapsToDevicePixels("True").ClipToBounds("False")

        head.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("条件类型:")).VerticalAlignment("Center").HorizontalAlignment("Left").Foreground("{DynamicResource TextMain}").FontSize("12")
        condiCon := head.Add("ComboBox").Grid_Row(1).Grid_Column(2).Name("CondiCon").Height(28).MinHeight(28).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True").ClipToBounds("False")
        for t in GetLangArr(["无", "继续条件", "退出条件"])
            condiCon.Add("ComboBoxItem").Content(t)
        head.Add("TextBlock").Grid_Row(1).Grid_Column(4).Text(GetLang("逻辑关系：")).VerticalAlignment("Center").HorizontalAlignment("Right").Foreground("{DynamicResource TextMain}").FontSize("12")
        logicCon := head.Add("ComboBox").Grid_Row(1).Grid_Column(6).Name("LogicCon").Width(70).Height(28).MinHeight(28)
            .HorizontalAlignment("Left").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .SnapsToDevicePixels("True").ClipToBounds("False")
        for t in GetLangArr(["且", "或"])
            logicCon.Add("ComboBoxItem").Content(t)

        ; === 条件边框（与「如果」一致：默认 2 条、可无限增加、4 行高度）===
        bd := main.Add("Border").Name("CondiBox").Grid_Row(2)
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
            .Padding("8,6,0,6").Margin("16,2,16,4").ClipToBounds("True")
        sv := bd.Add("ScrollViewer").Name("CondiScroll").Height(this._CondiViewH())
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
            .Padding("0").Margin("0").FocusVisualStyle("{x:Null}").Style("{StaticResource IfThemedSV}")
        condiHost := sv.Add("StackPanel")
        condiHost.Add("StackPanel").Name("CondiRowsPanel")
        plusRow := condiHost.Add("Grid").Name("BtnAddCondiRow").Margin("0,2,0,0")
        plusRow.Cols("28", "*", "8", "90", "8", "*", "28")
        plusRow.Add("Button").Name("BtnAddCondi").Grid_Column(3).Width(24).Height(24).MinHeight(24)
            .HorizontalAlignment("Center").VerticalAlignment("Center").Cursor("Hand").ToolTip(GetLang("添加"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").Content(Chr(0xE710))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("0")
            .FocusVisualStyle("{x:Null}").IsHitTestVisible("True")

        ; === 循环体 ===
        body := main.Add("StackPanel").Grid_Row(3).Orientation("Vertical").Margin("16,4,16,0")
        lbRow := body.Add("StackPanel").Orientation("Horizontal")
        lbRow.Add("TextBlock").Text(GetLang("循环体:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        lbRow.Add("Button").Name("BtnEditMacro").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("10,0,0,0").Padding("12,0").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        body.Add("TextBox").Name("LoopBodyCon").Height(80).Margin("0,4,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
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
        BindCmdEditorChrome(this.ui, "#指令手册/9-循环", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnEditMacro", "Click", ObjBindMethod(this, "OnEditMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("CondiCon", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("BtnAddCondi", "Click", ObjBindMethod(this, "OnAddCondi"))
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
        return Integer(XAMLHost.CmdTitleBarHeight()) + 86 + this._CondiBoxRowH() + 28 + 80 + 8 + 48
    }

    _EnsureCondiDataLen() {
        if (!IsObject(this.Data))
            this.Data := LoopData()
        if (this.Data.ToggleArr.Length == 0) {
            this.Data.ToggleArr := [1, 0]
            this.Data.NameArr := ["Var1", "Var2"]
            this.Data.CompareTypeArr := [1, 1]
            this.Data.VariableArr := ["Var1", "Var2"]
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
            . '<ComboBox Grid.Column="1" Name="NameCon_' i '" Height="26" MinHeight="26" IsEditable="True" VerticalContentAlignment="Center" SnapsToDevicePixels="True"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '<ComboBox Grid.Column="3" Name="CompareTypeCon_' i '" Height="26" MinHeight="26" VerticalContentAlignment="Center" SnapsToDevicePixels="True"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">' cmpItems '</ComboBox>'
            . '<ComboBox Grid.Column="5" Name="VariableCon_' i '" Height="26" MinHeight="26" IsEditable="True" VerticalContentAlignment="Center" SnapsToDevicePixels="True"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '<Button Grid.Column="6" Name="DelCondi_' i '" Width="24" Height="24" MinHeight="24" Padding="0" Cursor="Hand" FocusVisualStyle="{x:Null}" IsHitTestVisible="True"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Content="&#xE74D;" ToolTip="' tip '"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Grid>'
    }

    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        try this.ui.BindEventBatched(name, evt)
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
        this.SaveLoopData()
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
        this.SaveLoopData()
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

    ; Query 在窗口未加载（wpfHwnd 为 0）时返回空串（§4.2）：一律 IsNumber 保护再算术
    _CondiIndex() {
        v := IsObject(this.ui) ? this.ui.Query("CondiCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 0
        return Integer(v)
    }

    _LogicIndex() {
        v := IsObject(this.ui) ? this.ui.Query("LogicCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 0
        return Integer(v)
    }

    _CompareIndex(idx) {
        v := IsObject(this.ui) ? this.ui.Query("CompareTypeCon_" idx ">SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 0
        return Integer(v)
    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("循环")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        CountVariableArr := GetGuiVarArr(2)
        CountVariableArr.Push(GetLang("无限"))
        this._SetCombo("CountCon", CountVariableArr, this.Data.LoopCount == -1 ? GetLang("无限") : this.Data.LoopCount)

        ; 原生 DropDownList.Value 为 1-based，XAML SelectedIndex 为 0-based
        this.ui.Update("CondiCon", "SelectedIndex", String(CmdEnumIndex(this.Data.CondiType, CmdEnumCondiNames())))
        this.ui.Update("LogicCon", "SelectedIndex", String(CmdEnumIndex(this.Data.LogicType, CmdEnumLogicNames())))
        this.ui.Update("LoopBodyCon", "Text", GetLangMacro(this.Data.LoopBody, 1))
        this._RebuildRows()
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
            onlyOne := this.Data.ToggleArr.Length <= 1
            this.ui.Update("DelCondi_" i, "IsEnabled", onlyOne ? "False" : "True")
        }
    }

    OnEditMacroBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
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

        SureAction(command) {
            command := GetLangMacro(command, 1)
            this.ui.Update("LoopBodyCon", "Text", command)
        }

        this.MacroGui.SureBtnAction := SureAction
        this.MacroGui.ShowGui(this.ui.Query("LoopBodyCon"), false)
    }

    OnClickSureBtn(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveLoopData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this.OnGuiClose()
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    CheckIfValid() {
        return true
    }

    TriggerMacro(*) {
        this.SaveLoopData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    SaveLoopData() {
        this.Data.LoopCount := this.ui.Query("CountCon") == GetLang("无限") ? -1 : this.ui.Query("CountCon")
        this.Data.CondiType := CmdEnumFromIndex(this._CondiIndex(), CmdEnumCondiNames())
        this.Data.LogicType := CmdEnumFromIndex(this._LogicIndex(), CmdEnumLogicNames())
        this.Data.LoopBody := GetLangMacro(this.ui.Query("LoopBodyCon"), 2)
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
        SaveMacroCMDData(this.Data)
    }

    ; ---------------- 生命周期 ----------------

    _FocusSureBtn() {
        if (IsObject(this.ui))
            try this.ui.Update("BtnSure", "Focus", "True")
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._Bind("BtnAddCondi", "Click", ObjBindMethod(this, "OnAddCondi"))
        this._BindRowEvents()
        this.OnRefresh()
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
}
