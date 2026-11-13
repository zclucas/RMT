#Requires AutoHotkey v2.0
#Include CompareProEditItemGui.ahk

; =====================================================================
; 如果Pro编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 卡片阶梯：ScrollViewer + BranchPanel，每张卡包含条件、分支指令和编辑操作；
;   行模型 this.LVRowArr（[condiStr, logicStr, macro, controlType]），最后一行永远是兜底。
; 与 CompareProEditItemGui（分支编辑器）联动契约不变：ShowGui(EditType, DataArr, logicStr, macro, controlType) /
;   SureBtnAction(condiStr, logicStr, macro, controlType) / ParentTile / OwnerHwnd。
; =====================================================================

class CompareProGui {
    __new() {
        this.WindowBindingContext := ""
        this.ParentTile := ""
        this.Gui := ""          ; 原生 Gui 对象占位（XAML 版不再使用，保留成员）
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""    ; 原生 Edit 占位（XAML 版控件名 RemarkCon）
        this.MacroGui := ""
        this.FocusCon := ""     ; 原生确定按钮占位（XAML 版无原生控件可传，见 OnEditItem）
        this.ItemEditGui := ""
        this.ContextMenu := ""
        this.LVCon := ""        ; 兼容占位
        this._closed := true
        this._syncing := false
        this._title := ""

        this.LVRowArr := []     ; [condiStr, logicStr, macro, controlType]
        this.CurItme := 0       ; 右键目标行（保留原生拼写）

        this.CompareTypeStrArr := GetLangArr(["大于", "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配", "不等于"])

        this.CompareTypeStrMap := GetCompareTypeStrMap()

        this.Data := ""
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
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("如果Pro编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,12")
        body.Rows("*", "44")

        ; 全部分支包在同一边框内；备注放进框顶，避免和外框错位
        box := body.Add("Border").Grid_Row(0).Margin("0,4,0,4").Padding("10,10")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
            .Background("{DynamicResource ControlBg}")
            .SnapsToDevicePixels("True").UseLayoutRounding("True")
        inner := box.Add("Grid")
        inner.Rows("Auto", "*")

        meta := inner.Add("Grid").Grid_Row(0).Margin("0,0,0,8")
        meta.Cols("48", "*")
        meta.Add("TextBlock").Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        ; TextBox 默认模板会裁掉上下边，用外层 Border 画四边
        remarkBd := meta.Add("Border").Grid_Column(1).Height("28").MinHeight("28").VerticalAlignment("Center")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource ControlBorder}")
            .BorderThickness("1").CornerRadius("3")
            .SnapsToDevicePixels("True").UseLayoutRounding("True")
        remarkBd.Add("TextBox").Name("RemarkCon").BorderThickness("0").Background("Transparent")
            .Foreground("{DynamicResource InputText}").VerticalContentAlignment("Center").Padding("4,0")
            .VerticalAlignment("Stretch")

        sv := inner.Add("ScrollViewer").Grid_Row(1).MinHeight("0").VerticalAlignment("Stretch")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        sv.Add("StackPanel").Name("BranchPanel")

        btnRow := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow, "BtnSure", "4,0")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="640" Height="540"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/14-如果Pro", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnSure", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
    }

    ; ---------------- 卡片阶梯 ----------------

    _IsFinally(i) {
        if (i < 1 || i > this.LVRowArr.Length)
            return false
        return this.LVRowArr[i][1] == GetLang("以上都不是") || i == this.LVRowArr.Length
    }

    _RowControlType(i) {
        row := this.LVRowArr[i]
        if (row.Length >= 4 && row[4] != "")
            return row[4]
        return "无"
    }

    _DefaultBranchRow() {
        return [GetLang("Var1 大于 Var1"), GetLang("且"), "", "无"]
    }

    _ParseChipCondi(itemStr) {
        itemStr := Trim(itemStr)
        for op in this.CompareTypeStrArr {
            needle := " " op " "
            p := InStr(itemStr, needle)
            if (p) {
                return [Trim(SubStr(itemStr, 1, p - 1)), op, Trim(SubStr(itemStr, p + StrLen(needle)))]
            }
        }
        parts := StrSplit(itemStr, " ")
        name := parts.Length >= 1 ? parts[1] : itemStr
        op := parts.Length >= 2 ? parts[2] : ""
        val := parts.Length >= 3 ? parts[3] : ""
        return [name, op, val]
    }

    _FlatBtnTemplate() {
        return '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"'
            . ' BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"'
            . ' SnapsToDevicePixels="True" UseLayoutRounding="True">'
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
            . '<Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Button.Template>'
    }

    _ChipXml(name, op := "", val := "", hideVal := false) {
        xml := '<Border Margin="0,0,4,2" Padding="3,1" CornerRadius="3" BorderThickness="1"'
            . ' BorderBrush="{DynamicResource ControlBorder}" Background="{DynamicResource InputBg}"'
            . ' SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<StackPanel Orientation="Horizontal">'
            . '<TextBlock Text="' this._EscapeXml(name) '"'
            . ' Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/>'
        if (op != "")
            xml .= '<TextBlock Text="' this._EscapeXml(op) '" Foreground="{DynamicResource Accent}"'
                . ' Margin="4,0,0,0" VerticalAlignment="Center"/>'
        if (!hideVal && val != "")
            xml .= '<TextBlock Text="' this._EscapeXml(val) '"'
                . ' Foreground="{DynamicResource TextMain}" Margin="4,0,0,0" VerticalAlignment="Center"/>'
        xml .= '</StackPanel></Border>'
        return xml
    }

    _JoinXml(i, j, logicStr) {
        return '<Button Name="BtnJoin' i '_' j '" Content="' this._EscapeXml(logicStr) '"'
            . ' Height="20" MinHeight="20" Padding="6,0" Margin="0,0,4,2" Cursor="Hand"'
            . ' FontWeight="Bold" Foreground="{DynamicResource Accent}"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . this._FlatBtnTemplate()
            . '</Button>'
    }

    _InsertCondiXml() {
        return this._IconBtnXml("BtnInsertCondi", "&#xE710;", GetLang("插入条件"))
    }

    _CondiPanelXml(i, condiStr, logicStr, isFinally) {
        if (isFinally)
            return this._ChipXml(GetLang("以上都不是"))
        xml := ""
        parts := StrSplit(condiStr, "⎖")
        loop parts.Length {
            j := A_Index
            item := Trim(parts[j])
            if (item == "")
                continue
            parsed := this._ParseChipCondi(item)
            hideVal := this.CompareTypeStrMap.Has(parsed[2]) && IsCompareExistVar(this.CompareTypeStrMap[parsed[2]])
            xml .= this._ChipXml(parsed[1], parsed[2], parsed[3], hideVal)
            if (j < parts.Length)
                xml .= this._JoinXml(i, j, logicStr)
        }
        if (xml == "")
            xml := this._ChipXml(GetLang("条件"))
        return xml
    }

    _IconBtnXml(name, glyph, tip, enabled := true) {
        en := enabled ? "True" : "False"
        return '<Button Name="' name '" Width="22" Height="22" MinHeight="22" Padding="0" Margin="4,0,0,0" Cursor="Hand"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Content="' glyph '"'
            . ' ToolTip="' this._EscapeXml(tip) '" IsEnabled="' en '"'
            . ' Foreground="{DynamicResource TextMain}" Background="{DynamicResource ControlBg}"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center">'
            . this._FlatBtnTemplate()
            . '</Button>'
    }

    _OpsXml(i) {
        xml := ""
        if (i != 1)
            xml .= this._IconBtnXml("BtnUp" i, "&#xE74A;", GetLang("上移"))
        if (i < this.LVRowArr.Length - 1)
            xml .= this._IconBtnXml("BtnDown" i, "&#xE74B;", GetLang("下移"))
        xml .= this._IconBtnXml("BtnDel" i, "&#xE74D;", GetLang("删除"))
        return xml
    }

    _CardXml(i) {
        row := this.LVRowArr[i]
        isFinally := this._IsFinally(i)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        macro := row[3]
        actionText := (macro == "") ? GetLang("（未填写指令）") : macro
        editBtn := this._IconBtnXml("BtnEdit" i, "&#xE70F;", GetLang("编辑"), true)
        branchOps := editBtn . (isFinally ? "" : this._OpsXml(i))
        cardPad := isFinally ? "0" : "0,0,0,8"
        return '<Border ' ns ' Margin="' cardPad '" Padding="8,6" CornerRadius="4" BorderThickness="1"'
            . ' BorderBrush="{DynamicResource ControlBorder}" Background="{DynamicResource ControlBg}"'
            . ' SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<Grid>'
            . '<Grid.RowDefinitions>'
            . '<RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>'
            . '</Grid.RowDefinitions>'
            . '<Grid Grid.Row="0">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="40"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>'
            . '</Grid.ColumnDefinitions>'
            . '<TextBlock Text="' this._EscapeXml(GetLang("条件")) '"'
            . ' Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/>'
            . '<WrapPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">'
            . this._CondiPanelXml(i, row[1], row[2], isFinally)
            . '</WrapPanel>'
            . (isFinally ? '<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="8,0,0,0">' this._InsertCondiXml() '</StackPanel>' : "")
            . '</Grid>'
            . '<Grid Grid.Row="1" Margin="0,4,0,0">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="40"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>'
            . '</Grid.ColumnDefinitions>'
            . '<TextBlock Text="' this._EscapeXml(GetLang("指令")) '"'
            . ' Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/>'
            . '<Border Grid.Column="1" MinHeight="26" MaxHeight="40" Padding="6,4" CornerRadius="3"'
            . ' Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"'
            . ' SnapsToDevicePixels="True" UseLayoutRounding="True" ToolTip="' this._EscapeXml(actionText) '">'
            . '<TextBlock Text="' this._EscapeXml(actionText) '" TextWrapping="Wrap" TextTrimming="CharacterEllipsis"'
            . ' Foreground="{DynamicResource InputText}" TextAlignment="Left" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="6,0,0,0">'
            . branchOps
            . '</StackPanel>'
            . '</Grid>'
            . '</Grid></Border>'
    }

    _RebuildCards() {
        if (!IsObject(this.ui))
            return
        this._syncing := true
        batch := []
        batch.Push({ControlName: "BranchPanel", PropertyName: "ClearItems", Value: ""})
        loop this.LVRowArr.Length
            batch.Push({ControlName: "BranchPanel", PropertyName: "AddXamlItem", Value: this._CardXml(A_Index)})
        this.ui.BatchUpdate(batch)
        this._BindCardEvents()
        this._syncing := false
    }

    _RefreshLV() {
        this._RebuildCards()
    }

    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        try this.ui.BindEventBatched(name, evt)
    }

    _BindCardEvents() {
        loop this.LVRowArr.Length {
            i := A_Index
            this._Bind("BtnEdit" i, "Click", ObjBindMethod(this, "OnActionClick", i))
            if (this._IsFinally(i)) {
                this._Bind("BtnInsertCondi", "Click", ObjBindMethod(this, "OnAddBranch"))
                continue
            }
            if (i != 1)
                this._Bind("BtnUp" i, "Click", ObjBindMethod(this, "OnMoveUp", i))
            if (i < this.LVRowArr.Length - 1)
                this._Bind("BtnDown" i, "Click", ObjBindMethod(this, "OnMoveDown", i))
            this._Bind("BtnDel" i, "Click", ObjBindMethod(this, "OnDelBranch", i))
            parts := StrSplit(this.LVRowArr[i][1], "⎖")
            loop parts.Length - 1
                this._Bind("BtnJoin" i "_" A_Index, "Click", ObjBindMethod(this, "OnJoinToggle", i))
        }
    }

    OnAddBranch(*) {
        this.LVRowArr.InsertAt(this.LVRowArr.Length, this._DefaultBranchRow())
        this._RebuildCards()
    }

    OnActionClick(i, *) {
        this.OnEditItem(i)
    }

    OnJoinToggle(i, *) {
        if (this._IsFinally(i))
            return
        this.LVRowArr[i][2] := this.LVRowArr[i][2] == GetLang("且") ? GetLang("或") : GetLang("且")
        this._RebuildCards()
    }

    OnMoveUp(i, *) {
        if (this._IsFinally(i) || i <= 1)
            return
        row := this.LVRowArr.RemoveAt(i)
        this.LVRowArr.InsertAt(i - 1, row)
        this._RebuildCards()
    }

    OnMoveDown(i, *) {
        if (this._IsFinally(i) || i >= this.LVRowArr.Length - 1)
            return
        row := this.LVRowArr.RemoveAt(i)
        this.LVRowArr.InsertAt(i + 1, row)
        this._RebuildCards()
    }

    OnDelBranch(i, *) {
        if (this._IsFinally(i)) {
            RmtDialog.Info(GetLang("最后的分支不能删除，若无需该分支请清空分支指令"), , this.Hwnd())
            return
        }
        if (!RmtDialog.Confirm(GetLang("确定删除该分支？"), GetLang("提示"), this.Hwnd()))
            return
        this.LVRowArr.RemoveAt(i)
        this._RebuildCards()
    }

    OnGuiClose() {
        this._CloseWindow()
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("如果Pro")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        this.LVRowArr := []
        loop this.Data.MacroArr.Length {
            condiStr := ""
            ItemIndex := A_Index
            loop this.Data.VariNameArr[ItemIndex].Length {
                condiStr .= GetLang(this.Data.VariNameArr[ItemIndex][A_Index]) " " GetCompareTypeName(this.Data.CompareTypeArr[
                    ItemIndex][A_Index]) " " GetLang(this.Data.VariableArr[ItemIndex][A_Index])
                condiStr .= "⎖"
            }
            condiStr := Trim(condiStr, "⎖")
            logicStr := CmdEnumLogic(this.Data.LogicTypeArr[A_Index]) == "且" ? GetLang("且") : GetLang("或")
            macro := GetLangMacro(this.Data.MacroArr[A_Index], 1)
            controlType := (this.Data.ControlTypeArr.Length >= A_Index) ? this.Data.ControlTypeArr[A_Index] : "无"
            this.LVRowArr.Push([condiStr, logicStr, macro, controlType])
        }
        defCtl := this.Data.HasProp("DefaultControlType") && this.Data.DefaultControlType != "" ? this.Data.DefaultControlType : "无"
        this.LVRowArr.Push([GetLang("以上都不是"), "", GetLangMacro(this.Data.DefaultMacro, 1), defCtl])
        this._RebuildCards()
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

    ShowContextMenu(ctrl, item, isRightClick, x, y) {
        if (item == 0)
            return

        if (this.ContextMenu == "") {
            this.ContextMenu := Menu()
            this.ContextMenu.Add(GetLang("编辑"), (*) => this.MenuHandler(GetLang("编辑")))
            this.ContextMenu.Add()  ; 分隔线
            this.ContextMenu.Add(GetLang("向上插入分支"), (*) => this.MenuHandler(GetLang("向上插入分支")))
            this.ContextMenu.Add(GetLang("向下插入分支"), (*) => this.MenuHandler(GetLang("向下插入分支")))
            this.ContextMenu.Add()  ; 分隔线
            this.ContextMenu.Add(GetLang("向上移动"), (*) => this.MenuHandler(GetLang("向上移动")))
            this.ContextMenu.Add(GetLang("向下移动"), (*) => this.MenuHandler(GetLang("向下移动")))
            this.ContextMenu.Add()  ; 分隔线
            this.ContextMenu.Add(GetLang("删除"), (*) => this.MenuHandler(GetLang("删除")))
        }
        this.CurItme := item
        MouseGetPos(&mx, &my)
        this.ContextMenu.Show(mx, my)
    }

    OnDoubleClick(ctrl, item) {
        if (item == 0)
            return
        this.OnEditItem(item)
    }

    MenuHandler(cmdStr) {
        isFinally := this._IsFinally(this.CurItme)
        switch cmdStr {
            case GetLang("编辑"):
            {
                this.OnEditItem(this.CurItme)
            }
            case GetLang("向上插入分支"):
            {
                this.LVRowArr.InsertAt(this.CurItme, this._DefaultBranchRow())
                this._RebuildCards()
            }
            case GetLang("向下插入分支"):
            {
                if (isFinally) {
                    RmtDialog.Info(GetLang("不可向最后的分支插入"))
                    return
                }
                this.LVRowArr.InsertAt(this.CurItme + 1, this._DefaultBranchRow())
                this._RebuildCards()
            }
            case GetLang("向上移动"):
            {
                this.OnMoveUp(this.CurItme)
            }
            case GetLang("向下移动"):
            {
                this.OnMoveDown(this.CurItme)
            }
            case GetLang("删除"):
            {
                this.OnDelBranch(this.CurItme)
            }
        }
    }

    OnEditItem(item) {
        if (this.ItemEditGui == "") {
            this.ItemEditGui := CompareProEditItemGui()
            this.ItemEditGui.SureFocusCon := this.FocusCon
        }
        ParentTile := StrReplace(this._title, GetLang("编辑器"), "")
        this.ItemEditGui.ParentTile := ParentTile "-"

        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            this.ItemEditGui.OwnerHwnd := this.Hwnd()
        }
        else {
            this.ItemEditGui.OwnerHwnd := ""
        }

        NumberIndex := item
        EditType := this._IsFinally(item) ? 2 : 1
        DataArr := this.GetCondiStrDataArr(this.LVRowArr[item][1])
        logicStr := this.LVRowArr[item][2]
        macro := this.LVRowArr[item][3]
        controlType := this._RowControlType(NumberIndex)
        this.ItemEditGui.WindowBindingContext := this.WindowBindingContext
        this.ItemEditGui.ShowGui(EditType, DataArr, logicStr, macro, controlType)
        this.ItemEditGui.SureBtnAction := this.OnSureEditItem.Bind(this, item)
    }

    OnSureEditItem(item, condiStr, logicStr, macro, controlType) {
        this.LVRowArr[item] := [condiStr, logicStr, macro, controlType]
        this._RebuildCards()
        NumberIndex := item
        EditType := this._IsFinally(item) ? 2 : 1
        if (EditType == 1)
            this.Data.ControlTypeArr[NumberIndex] := controlType
        else
            this.Data.DefaultControlType := controlType
    }

    OnClickSureBtn(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveCompareProData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this._CloseWindow()
    }

    CheckIfValid() {
        return true
    }

    TriggerMacro() {
        this.SaveCompareProData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        remark := IsObject(this.ui) ? this.ui.Query("RemarkCon") : ""
        CommandStr := CorrectRemark(CommandStr, remark)
        return CommandStr
    }

    GetItemNumber(nodeItemID) {
        if (!IsNumber(nodeItemID))
            return 1
        n := Integer(nodeItemID)
        if (n < 1)
            return 1
        if (n > this.LVRowArr.Length)
            return this.LVRowArr.Length
        return n
    }

    GetCondiStrDataArr(condiStr) {
        condiStrArr := StrSplit(condiStr, "⎖")
        VariNameArr := []
        CompareTypeArr := []
        VariableArr := []
        if (condiStr != GetLang("以上都不是")) {
            loop condiStrArr.Length {
                parsed := this._ParseChipCondi(condiStrArr[A_Index])
                Variable := parsed[3]
                VariNameArr.Push(parsed[1])
                if (this.CompareTypeStrMap.Has(parsed[2]))
                    CompareTypeArr.Push(this.CompareTypeStrMap[parsed[2]])
                else
                    CompareTypeArr.Push(3)
                VariableArr.Push(Variable)
            }
        }

        return [VariNameArr, CompareTypeArr, VariableArr]
    }

    SaveCompareProData() {
        this.Data.VariNameArr := []
        this.Data.CompareTypeArr := []
        this.Data.VariableArr := []
        this.Data.LogicTypeArr := []
        this.Data.MacroArr := []
        this.Data.ControlTypeArr := []
        loop this.LVRowArr.Length {
            if (A_Index == this.LVRowArr.Length) {
                this.Data.DefaultMacro := GetLangMacro(this.LVRowArr[A_Index][3], 2)
                this.Data.DefaultControlType := GetLangKey(this._RowControlType(A_Index))
                break
            }
            CondiDataArr := this.GetCondiStrDataArr(this.LVRowArr[A_Index][1])
            LogicType := this.LVRowArr[A_Index][2] == GetLang("且") ? 1 : 2
            this.Data.VariNameArr.Push(GetLangKey(CondiDataArr[1]))
            this.Data.CompareTypeArr.Push(CondiDataArr[2])
            this.Data.VariableArr.Push(GetLangKey(CondiDataArr[3]))
            this.Data.LogicTypeArr.Push(LogicType)
            this.Data.MacroArr.Push(GetLangMacro(this.LVRowArr[A_Index][3], 2))
            this.Data.ControlTypeArr.Push(GetLangKey(this._RowControlType(A_Index)))
        }

        SaveMacroCMDData(this.Data)
    }
}
