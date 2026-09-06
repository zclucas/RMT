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
        title := this.ParentTile GetLang("运算编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8")
        body.Rows("32", "26", "185", "34")
        body.Cols("40", "290", "55", "120", "36")

        ; 行0：备注
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(5).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：表头
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("开关")).VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(1).Grid_Column(1).Text(GetLang("运算表达式")).VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(1).Grid_Column(3).Text(GetLang("结果保存变量")).VerticalAlignment("Center")
        body.Add("TextBlock").Grid_Row(1).Grid_Column(4).Text(GetLang("删除")).HorizontalAlignment("Center").VerticalAlignment("Center")

        ; 行2：表达式滚动区（§15.4 行数不限，动态增删）
        opSv := body.Add("ScrollViewer").Grid_Row(2).Grid_ColumnSpan(5)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        opSv.Add("StackPanel").Name("OpRowsPanel")

        ; 行3：添加 + 确定
        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnAddOp").Content(GetLang("添加运算")).Width(90).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36).Margin("8,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" Height="380" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnAddOp", "Click", ObjBindMethod(this, "OnAddOpRow"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        ; 行区事件（EditBtn/DelOpRow 每行）在 _RebuildOpRows 动态绑定

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
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()

        this._EnsureOpDataLen()
        this._RebuildOpRows()
    }

    ; ---------- §15.4 动态行区 ----------

    _EnsureOpDataLen() {
        if (!IsObject(this.Data)) {
            this.Data := OperationData()
            this.Data.SerialStr := this.SerialStr
        }
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
    }

    _OpRowXml(i) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        return '<Grid ' ns ' Margin="0,2">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="40"/><ColumnDefinition Width="290"/><ColumnDefinition Width="55"/><ColumnDefinition Width="120"/><ColumnDefinition Width="36"/>'
            . '</Grid.ColumnDefinitions>'
            . '<CheckBox Grid.Column="0" Name="Toggle' i '" VerticalAlignment="Center"/>'
            . '<TextBox Grid.Column="1" Name="Expr' i '" Height="26" MinHeight="26" Margin="0,0,4,0" IsReadOnly="True" VerticalContentAlignment="Center"'
            . ' Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Grid.Column="2" Name="EditBtn' i '" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Margin="4,0,0,0" Cursor="Hand"/>'
            . '<ComboBox Grid.Column="3" Name="UpdateName' i '" Height="26" MinHeight="26" Margin="4,0,0,0" IsEditable="True" VerticalContentAlignment="Center"/>'
            . '<Button Grid.Column="4" Name="DelOpRow' i '" Content="×" Height="22" MinHeight="22" Padding="0" Cursor="Hand" FontSize="14" ToolTip="' GetLang("删除该运算") '"/>'
            . '</Grid>'
    }

    ; 重建全部行：ClearItems + 注入 + 绑定事件 + 填值
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
            this.ui.Update("Toggle" i, "IsChecked", this.Data.ToggleArr[i] ? "True" : "False")
            this.ui.Update("Expr" i, "Text", GetLangStr(this.Data.ExpressionArr[i], 1))
            this._SetCombo("UpdateName" i, this.DLVariableArr, GetLang(this.Data.UpdateNameArr[i]))
        }
    }

    _BindOp(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.Update(name, "BindEvent", evt)
    }

    OnAddOpRow(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this.SaveOperationData()
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
            MsgBox(GetLang("至少保留一个运算"))
            return
        }
        this.SaveOperationData()
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
                if (this.ui.Query("Toggle" A_Index) == "True") {
                    Remark .= this.ui.Query("UpdateName" A_Index) "&"
                }
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
            IsOn := this.ui.Query("Toggle" A_Index) == "True"
            if (IsOn && !CheckVarNameIfValid(this.ui.Query("UpdateName" A_Index))) {
                return false
            }
        }
        return true
    }

    SaveOperationData() {
        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.Data.ToggleArr[i] := this.ui.Query("Toggle" i) == "True"
            this.Data.ExpressionArr[i] := GetLangStr(this.ui.Query("Expr" i), 2)
            this.Data.UpdateNameArr[i] := GetVarName(this.ui.Query("UpdateName" i))
        }

        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.UpdateNameArr[A_Index]] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
