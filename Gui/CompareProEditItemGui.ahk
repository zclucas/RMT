#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 如果Pro分支编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(EditType, DataArr, logicStr, macro, controlType)
;              / MacroEditShowGui(CommandStr, CondiNumber) / SureBtnAction
;              / OwnerHwnd / ParentTile / IsSubMacroEdit / DLVariableArr / SureFocusCon
; 调用方：CompareProGui.ahk:221 OnEditItem（原生，ShowGui 后设 SureBtnAction）
;         MacroEditGui.ahk:1166 OnDoubleClick（XAML，IsSubMacroEdit + MacroEditShowGui）
; =====================================================================

class CompareProEditItemGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.FocusCon := ""
        this.MacroGui := ""
        this._closed := true
        this._title := ""

        this.IsSubMacroEdit := false
        this.Data := ""
        this.CondiNumber := 1

        this.EditType := 1  ;1正常分支 2兜底分支
        this.ToggleArr := [1, 0]
        this.NameArr := ["Var1", "Var2"]
        this.CompareTypeArr := [1, 1]
        this.VariableArr := ["Var1", "Var2"]
        this.LogicalTypeCon := "LogicalTypeCon"
        this.MacroCon := "MacroCon"
        this.SureFocusCon := ""      ; 外部（CompareProGui:224）可能赋值；内部不使用
        this.DLVariableArr := []
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

    MacroEditShowGui(CommandStr, CondiNumber) {
        paramArr := StrSplit(CommandStr, "_")
        Data := GetMacroCMDData(paramArr[1])
        this.Data := Data
        this.CondiNumber := CondiNumber
        EditType := CondiNumber <= Data.VariNameArr.Length ? 1 : 2
        if (EditType == 2) {
            this.ShowGui(EditType, [[], [], []], GetLang("且"), Data.DefaultMacro, Data.DefaultControlType)
            return
        }

        DataArr := []
        DataArr.Push(Data.VariNameArr[CondiNumber])
        DataArr.Push(Data.CompareTypeArr[CondiNumber])
        DataArr.Push(Data.VariableArr[CondiNumber])
        logicStr := CmdEnumLogic(Data.LogicTypeArr[CondiNumber]) == "且" ? GetLang("且") : GetLang("或")
        macro := Data.MacroArr[CondiNumber]
        controlType := Data.ControlTypeArr[CondiNumber]
        this.ShowGui(EditType, DataArr, logicStr, macro, controlType)
    }

    ShowGui(EditType, DataArr, logicStr, macro, controlType) {
        global MySoftData
        ; XAML 窗口不支持隐藏复用：已打开的实例先关掉再重建
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(EditType, DataArr, logicStr, macro, controlType)
        this.OnRefresh()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("分支")
        this._title := title
        this.Gui := CompareProEditItemGuiFacade(this)
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容区 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,8")
        body.Rows("34", this._CondiBoxRowH(), "28", "*")

        ; 行0：逻辑关系
        logicRow := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        logicRow.Add("TextBlock").Text(GetLang("逻辑关系：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        lc := logicRow.Add("ComboBox").Name("LogicalTypeCon").Width(70).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["且", "或"])
            lc.Add("ComboBoxItem").Content(t)

        ; 行1：条件（与「如果」编辑器一致：任意数量、删除、加号、4 行高度）
        bd := body.Add("Border").Name("CondiBox").Grid_Row(1)
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

        ; 行2：分支指令 + 编辑按钮
        macroLabelRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        macroLabelRow.Add("TextBlock").Text(GetLang("分支指令:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        macroLabelRow.Add("Button").Name("BtnEditMacro").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("10,0,0,0").Padding("12,0").Cursor("Hand")

        ; 行3：分支指令内容（多行）
        body.Add("TextBox").Name("MacroCon").Grid_Row(3).AcceptsReturn("True").TextWrapping("Wrap").FontSize("11")
            .VerticalContentAlignment("Top").Padding("4,2").Margin("0,2,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnSure", "4,0")

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
        this.ui.OnEvent("BtnAddCondi", "Click", ObjBindMethod(this, "OnAddCondi"))
        this.ui.OnEvent("BtnEditMacro", "Click", ObjBindMethod(this, "OnEditMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        return 30 + 10 + 8 + 34 + this._CondiBoxRowH() + 28 + 88 + 48
    }

    _EnsureCondiDataLen() {
        if (this.ToggleArr.Length == 0) {
            this.ToggleArr := [1]
            this.NameArr := ["Var1"]
            this.CompareTypeArr := [1]
            this.VariableArr := ["Var1"]
        }
        n := this.ToggleArr.Length
        while (this.NameArr.Length < n)
            this.NameArr.Push("Var" (this.NameArr.Length + 1))
        while (this.CompareTypeArr.Length < n)
            this.CompareTypeArr.Push(1)
        while (this.VariableArr.Length < n)
            this.VariableArr.Push("Var" (this.VariableArr.Length + 1))
        while (this.NameArr.Length > n)
            this.NameArr.RemoveAt(this.NameArr.Length)
        while (this.CompareTypeArr.Length > n)
            this.CompareTypeArr.RemoveAt(this.CompareTypeArr.Length)
        while (this.VariableArr.Length > n)
            this.VariableArr.RemoveAt(this.VariableArr.Length)
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
        this.ui.Update(name, "BindEvent", evt)
    }

    _BindRowEvents() {
        loop this.ToggleArr.Length {
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
        loop this.ToggleArr.Length
            batch.Push({ControlName: "CondiRowsPanel", PropertyName: "AddXamlItem", Value: this._CondiRowXml(A_Index)})
        this.ui.BatchUpdate(batch)
        this._BindRowEvents()
        this._FillRows()
    }

    _FillRows() {
        if (!IsObject(this.ui))
            return
        batch := []
        canEdit := this.EditType == 1
        loop this.ToggleArr.Length {
            i := A_Index
            tog := this.ToggleArr[i] ? "True" : "False"
            batch.Push({ControlName: "ToggleCon_" i, PropertyName: "IsChecked", Value: tog})
            this._BatchSetCombo(batch, "NameCon_" i, this.DLVariableArr, GetLang(this.NameArr[i]))
            ct := this.CompareTypeArr[i]
            if (!IsNumber(ct) || Integer(ct) < 1 || Integer(ct) > 9)
                ct := 1
            batch.Push({ControlName: "CompareTypeCon_" i, PropertyName: "SelectedIndex", Value: String(CompareTypeToComboIndex(ct))})
            this._BatchSetCombo(batch, "VariableCon_" i, this.DLVariableArr, GetLang(this.VariableArr[i]))
            onlyOne := this.ToggleArr.Length <= 1
            batch.Push({ControlName: "DelCondi_" i, PropertyName: "IsEnabled", Value: (canEdit && !onlyOne) ? "True" : "False"})
            batch.Push({ControlName: "ToggleCon_" i, PropertyName: "IsEnabled", Value: canEdit ? "True" : "False"})
        }
        batch.Push({ControlName: "BtnAddCondi", PropertyName: "IsEnabled", Value: canEdit ? "True" : "False"})
        this.ui.BatchUpdate(batch)
    }

    _SaveCondiFromUi() {
        n := this.ToggleArr.Length
        this.ToggleArr := []
        this.NameArr := []
        this.CompareTypeArr := []
        this.VariableArr := []
        loop n {
            i := A_Index
            this.ToggleArr.Push(this.ui.Query("ToggleCon_" i) == "True" ? 1 : 0)
            this.NameArr.Push(GetLangKey(this.ui.Query("NameCon_" i)))
            this.CompareTypeArr.Push(this._CompareTypeIndex(i))
            this.VariableArr.Push(GetLangKey(this.ui.Query("VariableCon_" i)))
        }
    }

    OnAddCondi(*) {
        if (!IsObject(this.ui) || this.EditType != 1)
            return
        this._SaveCondiFromUi()
        n := this.ToggleArr.Length + 1
        this.ToggleArr.Push(1)
        this.NameArr.Push("Var" n)
        this.CompareTypeArr.Push(1)
        this.VariableArr.Push("Var" n)
        this._RebuildRows()
        try this.ui.Update("CondiScroll", "ScrollToEnd", "")
        this.OnRefresh()
    }

    OnDelCondi(n, *) {
        if (!IsObject(this.ui) || this.EditType != 1)
            return
        if (this.ToggleArr.Length <= 1) {
            RmtDialog.Info(GetLang("至少保留一个条件"), , "Owner" this.Hwnd())
            return
        }
        this._SaveCondiFromUi()
        this.ToggleArr.RemoveAt(n)
        this.NameArr.RemoveAt(n)
        this.CompareTypeArr.RemoveAt(n)
        this.VariableArr.RemoveAt(n)
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

    _LogicalTypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("LogicalTypeCon>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumLogicNames())
    }

    _CompareTypeIndex(i) {
        v := IsObject(this.ui) ? this.ui.Query("CompareTypeCon_" i ">SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return ComboIndexToCompareType(Integer(v))
    }

    Init(EditType, DataArr, logicStr, macro, controlType) {
        this.EditType := EditType
        this.ui.Update("LogicalTypeCon", "Text", logicStr == "" ? GetLang("且") : logicStr)
        this.ui.Update("MacroCon", "Text", macro)
        this.LegacyControlType := controlType ; 只保留旧配置的执行语义，不再提供流程下拉
        this.DLVariableArr := GetGuiVarArr(1)

        VariNameArr := DataArr[1]
        CompareTypeArr := DataArr[2]
        VariableArr := DataArr[3]
        if (VariNameArr.Length == 0) {
            this.ToggleArr := [1, 0]
            this.NameArr := ["Var1", "Var2"]
            this.CompareTypeArr := [1, 1]
            this.VariableArr := ["Var1", "Var2"]
        }
        else {
            this.ToggleArr := []
            this.NameArr := []
            this.CompareTypeArr := []
            this.VariableArr := []
            loop VariNameArr.Length {
                this.ToggleArr.Push(1)
                this.NameArr.Push(VariNameArr[A_Index])
                this.CompareTypeArr.Push(CompareTypeArr.Length >= A_Index ? CompareTypeArr[A_Index] : 1)
                this.VariableArr.Push(VariableArr.Length >= A_Index ? VariableArr[A_Index] : "Var" A_Index)
            }
        }
        this._RebuildRows()

        isEnabled := EditType == 1
        this.ui.Update("LogicalTypeCon", "IsEnabled", isEnabled ? "True" : "False")
        ; 程序化填值不触发 SelectionChanged，需显式刷新联动（§4.3）
        this.OnRefresh()
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        canEdit := this.EditType == 1
        loop this.ToggleArr.Length {
            i := A_Index
            isEnable := canEdit && this.ui.Query("ToggleCon_" i) == "True"
            this.ui.Update("NameCon_" i, "IsEnabled", isEnable ? "True" : "False")
            this.ui.Update("CompareTypeCon_" i, "IsEnabled", isEnable ? "True" : "False")
            enableVari := isEnable && !IsCompareExistVar(this._CompareTypeIndex(i))
            this.ui.Update("VariableCon_" i, "IsEnabled", enableVari ? "True" : "False")
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        global MySoftData
        action := this.SureBtnAction
        if (this.IsSubMacroEdit) {
            if (this.EditType == 2) {
                this.Data.DefaultMacro := GetLangStr(this.ui.Query("MacroCon"), 2)
                this.Data.DefaultControlType := GetLangKey(this.LegacyControlType)
            }
            else {
                this._SaveCondiFromUi()
                VariNameArr := []
                CompareTypeArr := []
                VariableArr := []
                loop this.ToggleArr.Length {
                    if (!this.ToggleArr[A_Index])
                        continue
                    VariNameArr.Push(this.NameArr[A_Index])
                    CompareTypeArr.Push(this.CompareTypeArr[A_Index])
                    VariableArr.Push(this.VariableArr[A_Index])
                }
                this.Data.VariNameArr[this.CondiNumber] := GetLangKeyArr(VariNameArr)
                this.Data.CompareTypeArr[this.CondiNumber] := GetLangKeyArr(CompareTypeArr)
                this.Data.VariableArr[this.CondiNumber] := GetLangKeyArr(VariableArr)
                this.Data.LogicTypeArr[this.CondiNumber] := this._LogicalTypeIndex()
                this.Data.MacroArr[this.CondiNumber] := GetLangStr(this.ui.Query("MacroCon"), 2)
                this.Data.ControlTypeArr[this.CondiNumber] := GetLangKey(this.LegacyControlType)
            }
            saveStr := JSON.stringify(this.Data, 0)
            CfgWrite(saveStr, CompareProFile, SettingSection, this.Data.SerialStr)
            if (MySoftData.DataCacheMap.Has(this.Data.SerialStr)) {
                MySoftData.DataCacheMap.Delete(this.Data.SerialStr)
            }
            action(this.ui.Query("MacroCon"))
        }
        else if (this.EditType == 1) {
            this._SaveCondiFromUi()
            condiStr := ""
            loop this.ToggleArr.Length {
                i := A_Index
                if (!this.ToggleArr[i])
                    continue
                if (this.ui.Query("CompareTypeCon_" i) != GetLang("变量存在")) {
                    condiStr .= this.ui.Query("NameCon_" i) " " this.ui.Query("CompareTypeCon_" i) " " this.ui.Query("VariableCon_" i)
                }
                else {
                    condiStr .= this.ui.Query("NameCon_" i) " " this.ui.Query("CompareTypeCon_" i)
                }
                condiStr .= "⎖"
            }
            condiStr := Trim(condiStr, "⎖")
            logicStr := this.ui.Query("LogicalTypeCon")
            macro := this.ui.Query("MacroCon")
            controlType := GetLangKey(this.LegacyControlType)
            action(condiStr, logicStr, macro, controlType)
        }
        else {
            controlType := GetLangKey(this.LegacyControlType)
            action(GetLang("以上都不是"), "", this.ui.Query("MacroCon"), controlType)
        }

        this.SureBtnAction := ""
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this._CloseWindow()
    }

    OnMacroBtnClick(CommandStr) {
        this.ui.Update("MacroCon", "Text", GetLangMacro(CommandStr, 1))
    }

    OnEditMacroBtnClick(*) {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            ; MacroEditGui 关闭确定后会调用 SureFocusCon.Focus()：传 XAML 焦点 facade
            this.MacroGui.SureFocusCon := CompareProEditFocusCon(this, "LogicalTypeCon")

            ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MainSoftData.IsModalSubGui && this.Gui != "") {
            this.MacroGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        this.MacroGui.SureBtnAction := (command) => this.OnMacroBtnClick(command)
        this.MacroGui.ShowGui(this.ui.Query("MacroCon"), false)
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this.Gui := ""
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
        this.Gui := ""
        this._closed := true
    }

    OnGuiClose() {
        this._CloseWindow()
    }
}

; 兼容外部对 .Gui.Hwnd / .Gui.Title / .Gui.Hide 的调用（同 MacroEditGuiFacade 模式）
class CompareProEditItemGuiFacade {
    __New(owner) {
        this._owner := owner
    }

    Hwnd {
        get => (IsObject(this._owner.ui) && this._owner.ui.HasProp("wpfHwnd")) ? this._owner.ui.wpfHwnd : 0
    }

    Title {
        get => this._owner._title
    }

    Hide() {
        this._owner._CloseWindow()
    }
}

; MacroEditGui 关闭确定后调用 SureFocusCon.Focus()：把焦点转成 XAML Update 命令
class CompareProEditFocusCon {
    __New(owner, ctrlName) {
        this._owner := owner
        this._ctrlName := ctrlName
    }

    Focus() {
        if (IsObject(this._owner.ui))
            this._owner.ui.Update(this._ctrlName, "Focus", "True")
    }
}
