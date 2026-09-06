#Requires AutoHotkey v2.0
#Include CompareProEditItemGui.ahk

; =====================================================================
; 如果Pro编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 原生 ListView（三列：条件/关系/指令）→ ListBox 行模型 this.LVRowArr（[condiStr, logicStr, macro]），
;   每行 AddXamlItem 注入 ListBoxItem（Tag=行号，Grid 三列 TextBlock），行命中用桥接 ListBox HitTest；
;   双击/右键经 PreviewMouseLeft/RightButtonDown + 延迟处理（同 UseExplainGui 模式）。
; 与 CompareProEditItemGui（分支编辑器）联动契约不变：ShowGui(EditType, DataArr, logicStr, macro, controlType) /
;   SureBtnAction(condiStr, logicStr, macro, controlType) / DLVariableArr / ParentTile / OwnerHwnd。
; =====================================================================

class CompareProGui {
    __new() {
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
        this.LVCon := ""        ; 原生 ListView 占位（XAML 版为 ListBox 控件名 "LVCon"）
        this._closed := true

        this.LVRowArr := []     ; 列表行模型：[condiStr, logicStr, macro]
        this.CurItme := 0       ; 右键目标行（保留原生拼写）
        this._clickCoord := ""
        this._rightClickCoord := ""

        this.CompareTypeStrArr := GetLangArr(["大于", "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"])

        this.CompareTypeStrMap := Map(GetLang("大于"), 1, GetLang("大于等于"), 2, GetLang("等于"), 3, GetLang("小于等于"),
        4, GetLang("小于"), 5, GetLang("字符包含"), 6, GetLang("变量存在"), 7, GetLang("正则匹配"), 8)

        this.Data := ""
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
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "38", "*", "52")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 顶部工具行 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,5")
        top.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        top.Add("TextBlock").Text("!l").VerticalAlignment("Center").Margin("4,0,0,0").Opacity("0.6")
        top.Add("Button").Name("BtnTrigger").Content(GetLang("执行指令")).Width(80).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("TextBox").Name("RemarkCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; === 条件列表（三列：条件/关系/指令）===
        lvWrap := main.Add("Grid").Grid_Row(2).Margin("10,2,10,0")
        ; 去 ListBoxItem 默认内边距/外边距，内容横向拉伸（保留默认选中高亮）
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/></Style>'
        lvWrap.Add("ListBox").Name("LVCon")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .VirtualizingPanel_IsVirtualizing("False")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled").ScrollViewer_VerticalScrollBarVisibility("Auto")
            .InjectResources(lbStyle)

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(34).MinHeight(34).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="540" Height="440" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTrigger", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        ; 列表行：双击编辑、右键菜单（桥接 ListBox HitTest 命中行，Tag=行号）
        this.ui.OnEvent("LVCon", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnLVLeftDown"))
        this.ui.OnEvent("LVCon", "PreviewMouseRightButtonDown", ObjBindMethod(this, "_OnLVRightDown"))

    }

    ; ---------------- 列表行模型（等价原生 ListView） ----------------

    _RefreshLV() {
        if (!IsObject(this.ui))
            return
        this.ui.Update("LVCon", "ClearItems", "")
        loop this.LVRowArr.Length {
            row := this.LVRowArr[A_Index]
            this.ui.Update("LVCon", "AddXamlItem", this._LVRowXml(A_Index, row[1], row[2], row[3]))
        }
    }

    _LVRowXml(index, condiStr, logicStr, macro) {
        return '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
            . ' Tag="' index '" HorizontalContentAlignment="Stretch">'
            . '<Grid Margin="8,2">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="250"/>'
            . '<ColumnDefinition Width="50"/>'
            . '<ColumnDefinition Width="*"/>'
            . '</Grid.ColumnDefinitions>'
            . '<TextBlock Grid.Column="0" Text="' this._EscapeXml(condiStr) '" TextTrimming="CharacterEllipsis"'
            . ' ToolTip="' this._EscapeXml(condiStr) '" VerticalAlignment="Center" FontSize="12"/>'
            . '<TextBlock Grid.Column="1" Text="' this._EscapeXml(logicStr) '" HorizontalAlignment="Center"'
            . ' VerticalAlignment="Center" FontSize="12"/>'
            . '<TextBlock Grid.Column="2" Text="' this._EscapeXml(macro) '" TextTrimming="CharacterEllipsis"'
            . ' ToolTip="' this._EscapeXml(macro) '" VerticalAlignment="Center" FontSize="12" Margin="8,0,0,0"/>'
            . '</Grid></ListBoxItem>'
    }

    ; ---------------- 列表行命中测试（桥接 ListBox HitTest） ----------------

    _EventCoord(state, ctrlName) {
        coord := ""
        if (IsObject(state) && state.Has(ctrlName))
            coord := state[ctrlName]
        if (coord == "")
            return ""
        parts := StrSplit(coord, ",")
        if (parts.Length != 2)
            return ""
        return Trim(parts[1]) ";" Trim(parts[2])
    }

    _HitTest(ctrlName, coord) {
        if (!IsObject(this.ui) || coord == "")
            return ""
        return this.ui.Query(ctrlName ">HitTest:" coord)
    }

    _OnLVLeftDown(state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        clickCount := 1
        if (IsObject(state) && state.Has("ClickCount")) {
            cc := state["ClickCount"]
            if (IsNumber(cc))
                clickCount := Integer(cc)
        }
        if (clickCount < 2)
            return
        this._clickCoord := this._EventCoord(state, "LVCon")
        SetTimer(ObjBindMethod(this, "_ProcessLVLeftClick"), -20)
    }

    _ProcessLVLeftClick() {
        if (!IsObject(this.ui))
            return
        coord := this._clickCoord
        this._clickCoord := ""
        if (coord == "")
            return
        tagSlot := this._HitTest("LVCon", coord)
        if (tagSlot == "")
            return
        row := StrSplit(tagSlot, "|")[1]
        if (!IsNumber(row) || Integer(row) < 1)
            return
        this.OnDoubleClick("", Integer(row))
    }

    _OnLVRightDown(state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        this._rightClickCoord := this._EventCoord(state, "LVCon")
        SetTimer(ObjBindMethod(this, "_ProcessLVRightClick"), -20)
    }

    _ProcessLVRightClick() {
        if (!IsObject(this.ui))
            return
        coord := this._rightClickCoord
        this._rightClickCoord := ""
        if (coord == "")
            return
        tagSlot := this._HitTest("LVCon", coord)
        if (tagSlot == "")
            return
        row := StrSplit(tagSlot, "|")[1]
        if (!IsNumber(row) || Integer(row) < 1)
            return
        this.ShowContextMenu("", Integer(row), true, 0, 0)
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
        this.DLVariableArr := GetGuiVarArr(1)

        this.LVRowArr := []
        loop this.Data.MacroArr.Length {
            condiStr := ""
            ItemIndex := A_Index
            loop this.Data.VariNameArr[ItemIndex].Length {
                condiStr .= GetLang(this.Data.VariNameArr[ItemIndex][A_Index]) " " this.CompareTypeStrArr[this.Data.CompareTypeArr[
                    ItemIndex][A_Index]] " " GetLang(this.Data.VariableArr[ItemIndex][A_Index])
                condiStr .= "⎖"
            }
            condiStr := Trim(condiStr, "⎖")
            logicStr := this.Data.LogicTypeArr[A_Index] == 1 ? GetLang("且") : GetLang("或")
            macro := GetLangMacro(this.Data.MacroArr[A_Index], 1)

            this.LVRowArr.Push([condiStr, logicStr, macro])
        }
        this.LVRowArr.Push([GetLang("以上都不是"), "", GetLangMacro(this.Data.DefaultMacro, 1)])
        this._RefreshLV()
        ; 原生 Init 末尾 LVCon.Focus() 用于解决原生 ListView 第一次双击无效；
        ; XAML 版双击走 PreviewMouseLeftButtonDown + ClickCount 命中，不依赖焦点，省略。
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
        ; 原生 ListView ContextMenu 事件给屏幕坐标；XAML 版右键事件只有控件相对坐标，
        ; 用当前鼠标位置（右键按下时即点击点）作为菜单坐标，等价。
        MouseGetPos(&mx, &my)
        this.ContextMenu.Show(mx, my)
    }

    OnDoubleClick(ctrl, item) {
        if (item == 0)
            return
        this.OnEditItem(item)
    }

    MenuHandler(cmdStr) {
        isFinally := this.LVRowArr[this.CurItme][1] == GetLang("以上都不是")
        switch cmdStr {
            case GetLang("编辑"):
            {
                this.OnEditItem(this.CurItme)
            }
            case GetLang("向上插入分支"):
            {
                this.Data.ControlTypeArr.InsertAt(this.CurItme, "无")
                this.LVRowArr.InsertAt(this.CurItme, [GetLang("Var1 大于 Var1"), GetLang("且"), ""])
                this._RefreshLV()
            }
            case GetLang("向下插入分支"):
            {
                if (isFinally) {
                    MsgBox(GetLang("不可向最后的分支插入"))
                    return
                }
                this.Data.ControlTypeArr.InsertAt(this.CurItme + 1, "无")
                this.LVRowArr.InsertAt(this.CurItme + 1, [GetLang("Var1 大于 Var1"), GetLang("且"), ""])
                this._RefreshLV()
            }
            case GetLang("向上移动"):
            {
                if (isFinally) {
                    MsgBox(GetLang("最后的分支不能变更顺序"))
                    return
                }
                if (this.CurItme == 1) {
                    MsgBox(GetLang("第一个分支不能上移"))
                    return
                }
                row := this.LVRowArr.RemoveAt(this.CurItme)
                this.LVRowArr.InsertAt(this.CurItme - 1, row)
                this._RefreshLV()
            }
            case GetLang("向下移动"):
            {
                if (isFinally || this.LVRowArr.Length == this.CurItme + 1) {
                    MsgBox(GetLang("最后的分支不能变更顺序"))
                    return
                }

                row := this.LVRowArr.RemoveAt(this.CurItme)
                this.LVRowArr.InsertAt(this.CurItme + 1, row)
                this._RefreshLV()
            }
            case GetLang("删除"):
            {
                if (isFinally) {
                    MsgBox(GetLang("最后的分支不能删除，若无需该分支请清空分支指令"))
                    return
                }
                this.LVRowArr.RemoveAt(this.CurItme)
                this._RefreshLV()
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

        this.ItemEditGui.DLVariableArr := this.DLVariableArr
        NumberIndex := item
        EditType := this.LVRowArr[item][1] == GetLang("以上都不是") ? 2 : 1
        DataArr := this.GetCondiStrDataArr(this.LVRowArr[item][1])
        logicStr := this.LVRowArr[item][2]
        macro := this.LVRowArr[item][3]
        controlType := EditType == 1 ? this.Data.ControlTypeArr[NumberIndex] : this.Data.DefaultControlType
        this.ItemEditGui.ShowGui(EditType, DataArr, logicStr, macro, controlType)
        this.ItemEditGui.SureBtnAction := this.OnSureEditItem.Bind(this, item)
    }

    OnSureEditItem(item, condiStr, logicStr, macro, controlType) {
        this.LVRowArr[item] := [condiStr, logicStr, macro]
        this._RefreshLV()
        NumberIndex := item
        EditType := this.LVRowArr[item][1] == GetLang("以上都不是") ? 2 : 1
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
        ; 原生基于 ListView.GetPrev 逐行上溯（NoSort 下行号即行数）；
        ; XAML 版行模型按索引等价，保留接口。
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
                itemCondiArr := StrSplit(condiStrArr[A_Index], " ")
                Variable := itemCondiArr.Length >= 3 ? itemCondiArr[3] : ""
                VariNameArr.Push(itemCondiArr[1])
                CompareTypeArr.Push(this.CompareTypeStrMap[itemCondiArr[2]])
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
        loop this.LVRowArr.Length {
            if (A_Index == this.LVRowArr.Length) {
                this.Data.DefaultMacro := GetLangMacro(this.LVRowArr[A_Index][3], 2)
                break
            }
            CondiDataArr := this.GetCondiStrDataArr(this.LVRowArr[A_Index][1])
            LogicType := this.LVRowArr[A_Index][2] == GetLang("且") ? 1 : 2
            this.Data.VariNameArr.Push(GetLangKey(CondiDataArr[1]))
            this.Data.CompareTypeArr.Push(CondiDataArr[2])
            this.Data.VariableArr.Push(GetLangKey(CondiDataArr[3]))
            this.Data.LogicTypeArr.Push(LogicType)
            this.Data.MacroArr.Push(GetLangMacro(this.LVRowArr[A_Index][3], 2))
        }

        SaveMacroCMDData(this.Data)
    }
}
