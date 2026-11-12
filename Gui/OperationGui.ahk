#Requires AutoHotkey v2.0
#Include OperationSubGui.ahk

; =====================================================================
; 运算编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class OperationGui {
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
        this.OperationSubGui := ""
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

    _OpViewH() {
        return 30 * 6
    }

    _OpBoxRowH() {
        ; 边框上下 padding + 表头 + 滚动区（6 行）
        return 8 + 2 + 12 + 22 + this._OpViewH()
    }

    _FitHeight() {
        return Integer(XAMLHost.CmdTitleBarHeight()) + 10 + 14 + 34 + this._OpBoxRowH() + 48
    }

    _OpScrollStyles() {
        return '<ControlTemplate x:Key="OpSbThumb" TargetType="Thumb">'
            . '<Border x:Name="bd" Background="{DynamicResource ControlBorder}" CornerRadius="3" Opacity="0.7" Margin="1"/>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Accent}"/><Setter TargetName="bd" Property="Opacity" Value="1"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate>'
            . '<Style x:Key="OpSbVertical" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="true">'
            . '<Track.Thumb><Thumb Template="{StaticResource OpSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style x:Key="OpThemedSV" TargetType="ScrollViewer">'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollViewer"><Grid>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions>'
            . '<ScrollContentPresenter x:Name="PART_ScrollContentPresenter" Grid.Column="0" Margin="{TemplateBinding Padding}" Content="{TemplateBinding Content}" ContentTemplate="{TemplateBinding ContentTemplate}" CanContentScroll="{TemplateBinding CanContentScroll}"/>'
            . '<ScrollBar x:Name="PART_VerticalScrollBar" Width="8" MinWidth="8" Grid.Column="1" Value="{TemplateBinding VerticalOffset}" Maximum="{TemplateBinding ScrollableHeight}" ViewportSize="{TemplateBinding ViewportHeight}" Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}" Style="{StaticResource OpSbVertical}"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("运算编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,14")
        body.Rows("34", this._OpBoxRowH(), "48")

        ; 行0：备注
        remarkRow := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        remarkRow.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkRow.Add("TextBox").Name("RemarkCon").Width(180).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：边框包裹运算列表（表头 + 默认可视 6 行，超出右侧主题滚动条）
        bd := body.Add("Border").Name("OpBox").Grid_Row(1)
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
            .Padding("8,6,0,6").Margin("0,2,0,4").ClipToBounds("True")
        bdInner := bd.Add("Grid")
        bdInner.Rows("Auto", "*")
        head := bdInner.Add("Grid").Grid_Row(0).Margin("0,0,8,4")
        head.Cols("*", "55", "8", "120", "28")
        head.Add("TextBlock").Grid_Column(0).Text(GetLang("运算表达式")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        head.Add("TextBlock").Grid_Column(3).Text(GetLang("结果保存变量")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        sv := bdInner.Add("ScrollViewer").Name("OpScroll").Grid_Row(1).Height(this._OpViewH())
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
            .Padding("0").Margin("0").Style("{StaticResource OpThemedSV}")
        opHost := sv.Add("StackPanel")
        opHost.Add("StackPanel").Name("OpRowsPanel")
        plusRow := opHost.Add("Grid").Name("BtnAddOpRow").Margin("0,2,0,0")
        plusRow.Cols("*", "Auto", "*")
        plusRow.Add("Button").Name("BtnAddOp").Grid_Column(1).Width(24).Height(24).MinHeight(24)
            .HorizontalAlignment("Center").VerticalAlignment("Center").Cursor("Hand").ToolTip(GetLang("添加"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("14").Content(Chr(0xE710))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("0")
            .HorizontalContentAlignment("Center").VerticalContentAlignment("Center")

        ; 行2：确定
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnOk")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="' this._FitHeight() '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._OpScrollStyles())

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/15-运算")
        this.ui.OnEvent("BtnAddOp", "Click", ObjBindMethod(this, "OnAddOpRow"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._SyncOpIconFonts()
    }

    ; ApplyFonts 可能改掉图标钮字体；重建行后也需重新钉回 Fluent 字号
    _SyncOpIconFonts() {
        if (!IsObject(this.ui))
            return
        iconFont := "Segoe Fluent Icons, Segoe MDL2 Assets"
        n := (IsObject(this.Data) && this.Data.HasProp("ToggleArr")) ? this.Data.ToggleArr.Length : 0
        loop n {
            try this.ui.Update("DelOpRow" A_Index, "FontFamily", iconFont)
            try this.ui.Update("DelOpRow" A_Index, "FontSize", "14")
        }
        try this.ui.Update("BtnAddOp", "FontFamily", iconFont)
        try this.ui.Update("BtnAddOp", "FontSize", "14")
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运算")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := JSON.parse(JSON.stringify(GetMacroCMDData(this.SerialStr)), , false)
        this.DLVariableArr := GetGuiVarArr()

        this._EnsureOpDataLen()
        this._RebuildOpRows()
    }

    ; ---------- 动态行区 ----------

    _EnsureOpDataLen() {
        if (!IsObject(this.Data)) {
            this.Data := OperationData()
            this.Data.SerialStr := this.SerialStr
        }
        ; 旧配置只保留已启用行，至少提供一条草稿行。
        this._CompactOpData()
        if (this.Data.ToggleArr.Length == 0) {
            this.Data.ToggleArr := [1]
            this.Data.UpdateNameArr := ["Var1"]
            this.Data.ExpressionArr := [""]
        }
        n := this.Data.ToggleArr.Length
        while (this.Data.UpdateNameArr.Length < n)
            this.Data.UpdateNameArr.Push("Var" (this.Data.UpdateNameArr.Length + 1))
        while (this.Data.UpdateNameArr.Length > n)
            this.Data.UpdateNameArr.RemoveAt(this.Data.UpdateNameArr.Length)
        while (this.Data.ExpressionArr.Length < n)
            this.Data.ExpressionArr.Push("")
        while (this.Data.ExpressionArr.Length > n)
            this.Data.ExpressionArr.RemoveAt(this.Data.ExpressionArr.Length)
        loop n
            this.Data.ToggleArr[A_Index] := 1
    }

    _CompactOpData() {
        if (!IsObject(this.Data) || this.Data.ToggleArr.Length == 0)
            return
        newTog := [], newName := [], newExpr := []
        loop this.Data.ToggleArr.Length {
            i := A_Index
            expr := (this.Data.ExpressionArr.Length >= i) ? this.Data.ExpressionArr[i] : ""
            name := (this.Data.UpdateNameArr.Length >= i) ? this.Data.UpdateNameArr[i] : ("Var" i)
            if (this.Data.ToggleArr[i]) {
                newTog.Push(1)
                newName.Push(name)
                newExpr.Push(expr)
            }
        }
        if (newTog.Length == 0) {
            newTog := [1]
            newName := ["Var1"]
            newExpr := [""]
        }
        this.Data.ToggleArr := newTog
        this.Data.UpdateNameArr := newName
        this.Data.ExpressionArr := newExpr
    }

    _OpRowXml(i) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tip := this._EscapeXml(GetLang("删除该运算"))
        return '<Grid ' ns ' Margin="0,2">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="*"/><ColumnDefinition Width="55"/><ColumnDefinition Width="8"/>'
            . '<ColumnDefinition Width="120"/><ColumnDefinition Width="28"/>'
            . '</Grid.ColumnDefinitions>'
            . '<TextBox Grid.Column="0" Name="Expr' i '" Height="26" MinHeight="26" Margin="0,0,4,0" IsReadOnly="True" VerticalContentAlignment="Center"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Grid.Column="1" Name="EditBtn' i '" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Cursor="Hand"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"/>'
            . '<ComboBox Grid.Column="3" Name="UpdateName' i '" Height="26" MinHeight="26" IsEditable="True" VerticalContentAlignment="Center"'
            . ' Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Grid.Column="4" Name="DelOpRow' i '" Width="24" Height="24" MinHeight="24" Padding="0" Cursor="Hand" ToolTip="' tip '"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Content="&#xE74D;"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"'
            . ' HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>'
            . '</Grid>'
    }

    ; 重建全部行：ClearItems + 注入 + 绑定事件 + 填值（加号行在 OpRowsPanel 外，不受影响）
    _RebuildOpRows() {
        if (!IsObject(this.ui))
            return
        this._EnsureOpDataLen()
        batch := []
        batch.Push({ControlName: "OpRowsPanel", PropertyName: "ClearItems", Value: ""})
        loop this.Data.ToggleArr.Length
            batch.Push({ControlName: "OpRowsPanel", PropertyName: "AddXamlItem", Value: this._OpRowXml(A_Index)})
        this.ui.BatchUpdate(batch)
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this._BindOp("EditBtn" i, "Click", this.OnEditVariableBtnClick.Bind(this, i))
            this._BindOp("DelOpRow" i, "Click", ObjBindMethod(this, "OnDelOpRow", i))
            this.ui.Update("Expr" i, "Text", TranslateOperationExpression(this.Data.ExpressionArr[i], true))
            this._SetCombo("UpdateName" i, this.DLVariableArr, GetLang(this.Data.UpdateNameArr[i]))
        }
        this._BindOp("BtnAddOp", "Click", ObjBindMethod(this, "OnAddOpRow"))
        this._SyncOpIconFonts()
    }

    _BindOp(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.BindEventBatched(name, evt)
    }

    OnAddOpRow(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this._ReadOperationRows()
        n := this.Data.ToggleArr.Length + 1
        this.Data.ToggleArr.Push(1)
        this.Data.UpdateNameArr.Push("Var" n)
        this.Data.ExpressionArr.Push("")
        this._RebuildOpRows()
    }

    OnDelOpRow(n, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        if (this.Data.ToggleArr.Length <= 1) {
            RmtDialog.Info(GetLang("至少保留一个运算"))
            return
        }
        this._ReadOperationRows()
        this.Data.ToggleArr.RemoveAt(n)
        this.Data.UpdateNameArr.RemoveAt(n)
        this.Data.ExpressionArr.RemoveAt(n)
        this._RebuildOpRows()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            Remark := GetLang("更新")
            loop this.Data.ToggleArr.Length {
                name := this.ui.Query("UpdateName" A_Index)
                if (name != "")
                    Remark .= name "&"
            }
            Remark := RTrim(Remark, "&")
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    OnEditVariableBtnClick(Index, state := "", ctrl := "", event := "") {
        if (this.OperationSubGui == "") {
            this.OperationSubGui := OperationSubGui()
        }

        ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
        this.OperationSubGui.ParentTile := ParentTile "-"

        if (MainSoftData.IsModalSubGui && this.ui != "") {
            this.OperationSubGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.OperationSubGui.OwnerHwnd := ""
        }

        this.OperationSubGui.SureBtnAction := (Index, ExpressStr) => this.OnSureOperationBtnClick(
            Index, ExpressStr)

        this.OperationSubGui.ShowGui(Index, this.ui.Query("Expr" Index))
    }

    OnSureOperationBtnClick(Index, ExpressStr) {
        if (IsObject(this.ui))
            this.ui.Update("Expr" Index, "Text", ExpressStr)
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveOperationData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this._CloseWindow()
    }

    CheckIfValid() {
        loop this.Data.ToggleArr.Length {
            if (!CheckVarNameIfValid(this.ui.Query("UpdateName" A_Index)))
                return false
        }
        return true
    }

    _ReadOperationRows() {
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.Data.ExpressionArr[i] := TranslateOperationExpression(this.ui.Query("Expr" i), false)
            this.Data.UpdateNameArr[i] := GetVarName(this.ui.Query("UpdateName" i))
        }
    }

    SaveOperationData() {
        this._ReadOperationRows()
        loop this.Data.ToggleArr.Length
            MySoftData.GlobalVariMap[this.Data.UpdateNameArr[A_Index]] := true
        SaveMacroCMDData(this.Data)
    }
}
