#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

; =====================================================================
; 如果编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 内部 new MacroEditGui() 编辑真/假分支指令（引用保持）
; =====================================================================

class CompareGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.MacroGui := ""
        ; 原生 FocusCon 是「备注」标签控件，供嵌套 MacroEditGui.SureFocusCon 关窗后 Focus；
        ; XAML 版无法持有原生控件，改用带 Focus() 的轻量 facade（聚焦 XAML 的 RemarkCon）
        this.FocusCon := { Focus: ObjBindMethod(this, "_FocusRemark") }
        this._closed := true
        this._title := ""

        this.Data := ""
        this.DLVariableArr := []
        ; 控件名数组（XAML 版不持有原生控件对象，按名 Query/Update）
        this.ToggleConArr := ["ToggleCon_1", "ToggleCon_2", "ToggleCon_3", "ToggleCon_4"]
        this.NameConArr := ["NameCon_1", "NameCon_2", "NameCon_3", "NameCon_4"]
        this.CompareTypeConArr := ["CompareTypeCon_1", "CompareTypeCon_2", "CompareTypeCon_3", "CompareTypeCon_4"]
        this.VariableConArr := ["VariableCon_1", "VariableCon_2", "VariableCon_3", "VariableCon_4"]
        ; 结果保存组内可编辑控件名（SaveToggle 关闭时禁用；与原生 ResultConArr 顺序一致：
        ; 「选择/输入」「真值」「假值」标签 + SaveNameCon/TrueValueCon/FalseValueCon）
        this.ResultConArr := ["ResultLabelNameCon", "ResultLabelTrueCon", "ResultLabelFalseCon", "SaveNameCon", "TrueValueCon", "FalseValueCon"]
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
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "30", "30", "34", "34", "34", "34", "82", "30", "92", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 顶部工具行：快捷方式 + 执行指令 + 备注 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,4")
        top.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        top.Add("TextBlock").Text("!l").VerticalAlignment("Center").Margin("4,0,0,0").Opacity("0.6")
        top.Add("Button").Name("BtnTrigger").Content(GetLang("执行指令")).Width(80).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("TextBox").Name("RemarkCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; === 逻辑关系行 ===
        logicRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,2")
        logicRow.Add("TextBlock").Text(GetLang("逻辑关系：")).VerticalAlignment("Center")
        logicCon := logicRow.Add("ComboBox").Name("LogicalTypeCon").Width(70).Height(26).MinHeight(26).Margin("4,0,0,0").SelectedIndex("0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["且", "或"])
            logicCon.Add("ComboBoxItem").Content(t)
        logicRow.Add("Button").Name("BtnTypeHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1").Padding("0")

        ; === 条件行 1-4（Toggle + 变量名 + 比较类型 + 比较值）===
        loop 4
            this._AddCompareRow(main, A_Index + 2, A_Index)

        ; === 真/假 分支指令（共享行，左右对齐）===
        macroRow := main.Add("Grid").Grid_Row(7).Margin("10,4,10,0")
        macroRow.Cols("*", "*")

        foundCol := macroRow.Add("StackPanel").Grid_Column(0).Orientation("Vertical").Margin("0,0,8,0")
        ft := foundCol.Add("StackPanel").Orientation("Horizontal")
        ft.Add("TextBlock").Text(GetLang("真-分支指令:（可选）")).VerticalAlignment("Center")
        ft.Add("Button").Name("BtnTrueEdit").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        foundCol.Add("TextBox").Name("TrueMacroCon").Height(48).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        unfoundCol := macroRow.Add("StackPanel").Grid_Column(1).Orientation("Vertical").Margin("8,0,0,0")
        ft2 := unfoundCol.Add("StackPanel").Orientation("Horizontal")
        ft2.Add("TextBlock").Text(GetLang("假-分支指令:（可选）")).VerticalAlignment("Center")
        ft2.Add("Button").Name("BtnFalseEdit").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        unfoundCol.Add("TextBox").Name("FalseMacroCon").Height(48).Margin("0,2,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 真/假 流程控制 ===
        ctrlRow := main.Add("Grid").Grid_Row(8).Margin("10,2,10,0")
        ctrlRow.Cols("*", "*")
        lc := ctrlRow.Add("StackPanel").Grid_Column(0).Orientation("Horizontal").VerticalAlignment("Center")
        lc.Add("TextBlock").Text(GetLang("真-流程控制：")).VerticalAlignment("Center")
        tcc := lc.Add("ComboBox").Name("TrueControlCon").Width(125).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["无", "循环-跳过本轮", "循环-跳出", "分支-跳出"])
            tcc.Add("ComboBoxItem").Content(t)
        rc := ctrlRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        rc.Add("TextBlock").Text(GetLang("假-流程控制：")).VerticalAlignment("Center")
        fcc := rc.Add("ComboBox").Name("FalseControlCon").Width(125).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["无", "循环-跳过本轮", "循环-跳出", "分支-跳出"])
            fcc.Add("ComboBoxItem").Content(t)

        ; === 结果保存 GroupBox ===
        rg := main.Add("GroupBox").Grid_Row(9).Margin("10,2,10,0").Header(GetLang("结果保存"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("8,4")
        rgGrid := rg.Add("Grid")
        rgGrid.Cols("Auto", "Auto", "Auto", "Auto")
        rgGrid.Rows("28", "28")
        rgGrid.Add("TextBlock").Text(GetLang("开关")).Grid_Row(0).Grid_Column(0).VerticalAlignment("Center")
        rgGrid.Add("TextBlock").Name("ResultLabelNameCon").Text(GetLang("选择/输入")).Grid_Row(0).Grid_Column(1).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("TextBlock").Name("ResultLabelTrueCon").Text(GetLang("真值")).Grid_Row(0).Grid_Column(2).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("TextBlock").Name("ResultLabelFalseCon").Text(GetLang("假值")).Grid_Row(0).Grid_Column(3).VerticalAlignment("Center").Margin("10,0,0,0")
        rgGrid.Add("CheckBox").Name("SaveToggleCon").Grid_Row(1).Grid_Column(0).VerticalAlignment("Center")
        rgGrid.Add("ComboBox").Name("SaveNameCon").Width(120).Height(26).MinHeight(26).Grid_Row(1).Grid_Column(1).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        rgGrid.Add("TextBox").Name("TrueValueCon").Width(70).Height(26).MinHeight(26).Grid_Row(1).Grid_Column(2).Margin("10,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        rgGrid.Add("TextBox").Name("FalseValueCon").Width(70).Height(26).MinHeight(26).Grid_Row(1).Grid_Column(3).Margin("10,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(10).Orientation("Horizontal").HorizontalAlignment("Right").VerticalAlignment("Center").Margin("0,0,18,0")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(90).Height(32).MinHeight(32).Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="500" Height="480" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTrigger", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnTypeHelp", "Click", ObjBindMethod(this, "OnClickTypeHelpBtn"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnTrueEdit", "Click", ObjBindMethod(this, "OnTrueBtnClick"))
        this.ui.OnEvent("BtnFalseEdit", "Click", ObjBindMethod(this, "OnFalseBtnClick"))
        this.ui.OnEvent("SaveToggleCon", "Click", ObjBindMethod(this, "OnRefresh"))
        loop 4 {
            this.ui.OnEvent(this.ToggleConArr[A_Index], "Click", ObjBindMethod(this, "OnRefresh"))
            this.ui.OnEvent(this.CompareTypeConArr[A_Index], "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        }

    }

    _AddCompareRow(parent, rowIdx, idx) {
        row := parent.Add("StackPanel").Grid_Row(rowIdx).Orientation("Horizontal").VerticalAlignment("Center").Margin("8,0,0,0")
        row.Add("CheckBox").Name(this.ToggleConArr[idx]).Width(28).VerticalAlignment("Center").IsChecked("True")
        row.Add("ComboBox").Name(this.NameConArr[idx]).Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        cc := row.Add("ComboBox").Name(this.CompareTypeConArr[idx]).Width(90).Height(26).MinHeight(26).Margin("8,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["大于", "大于等于", "等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配"])
            cc.Add("ComboBoxItem").Content(t)
        row.Add("ComboBox").Name(this.VariableConArr[idx]).Width(140).Height(26).MinHeight(26).Margin("8,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
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
        v := IsObject(this.ui) ? this.ui.Query(this.CompareTypeConArr[idx] ">SelectedIndex") : ""
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
        this.DLVariableArr := GetGuiVarArr(1)

        ; 原生 DropDownList.Value 为 1-based，XAML SelectedIndex 为 0-based
        this._SetComboByText("TrueControlCon", GetLangArr(["无", "循环-跳过本轮", "循环-跳出", "分支-跳出"]), GetLang(ObjHasOwnProp(this.Data, "TrueControlType") ? this.Data.TrueControlType : "无"))
        this._SetComboByText("FalseControlCon", GetLangArr(["无", "循环-跳过本轮", "循环-跳出", "分支-跳出"]), GetLang(ObjHasOwnProp(this.Data, "FalseControlType") ? this.Data.FalseControlType : "无"))
        this.ui.Update("TrueMacroCon", "Text", GetLangMacro(ObjHasOwnProp(this.Data, "TrueMacro") ? this.Data.TrueMacro : "", 1))
        this.ui.Update("FalseMacroCon", "Text", GetLangMacro(ObjHasOwnProp(this.Data, "FalseMacro") ? this.Data.FalseMacro : "", 1))
        this.ui.Update("SaveToggleCon", "IsChecked", this._ToggleInt(ObjHasOwnProp(this.Data, "SaveToggle") ? this.Data.SaveToggle : 0) ? "True" : "False")
        this._SetCombo("SaveNameCon", GetGuiVarArr(), GetLang(ObjHasOwnProp(this.Data, "SaveName") ? this.Data.SaveName : ""))
        this.ui.Update("TrueValueCon", "Text", ObjHasOwnProp(this.Data, "TrueValue") ? this.Data.TrueValue : 1)
        this.ui.Update("FalseValueCon", "Text", ObjHasOwnProp(this.Data, "FalseValue") ? this.Data.FalseValue : 0)
        logical := ObjHasOwnProp(this.Data, "LogicalType") ? this.Data.LogicalType : 1
        this.ui.Update("LogicalTypeCon", "SelectedIndex", String(Integer(logical ? logical : 1) - 1))

        loop this.Data.ToggleArr.Length {
            i := A_Index
            this.ui.Update(this.ToggleConArr[i], "IsChecked", this.Data.ToggleArr[i] ? "True" : "False")
            this._SetCombo(this.NameConArr[i], this.DLVariableArr, GetLang(this.Data.NameArr[i]))
            ct := this.Data.CompareTypeArr[i]
            if (!IsNumber(ct) || Integer(ct) < 1 || Integer(ct) > 8)
                ct := 1
            this.ui.Update(this.CompareTypeConArr[i], "SelectedIndex", String(Integer(ct) - 1))
            this._SetCombo(this.VariableConArr[i], this.DLVariableArr, GetLang(this.Data.VariableArr[i]))
        }
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

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("循环-跳过本轮：跳过后续循环体指令，继续上层循环")
        str2 := GetLang("循环-跳出：跳出上层循环")
        str3 := GetLang("分支-跳出：跳出上层分支")

        str := Format("{}`n{}`n{}", str1, str2, str3)
        MsgBox(str, GetLang("流程控制说明"))
    }

    OnRefresh(*) {
        if (!IsObject(this.ui))
            return
        loop 4 {
            i := A_Index
            isEnable := this.ui.Query(this.ToggleConArr[i]) == "True"

            this.ui.Update(this.NameConArr[i], "IsEnabled", isEnable ? "True" : "False")
            this.ui.Update(this.CompareTypeConArr[i], "IsEnabled", isEnable ? "True" : "False")
            ; 原生 CompareTypeCon.Value 1-based，7 存在变量（0-based index 6）时变量列禁用
            enableVari := this._CompareIndex(i) != 6 && isEnable
            this.ui.Update(this.VariableConArr[i], "IsEnabled", enableVari ? "True" : "False")
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
        this.MacroGui.ShowGui(this.ui.Query("TrueMacroCon"), false)
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
        this.MacroGui.ShowGui(this.ui.Query("FalseMacroCon"), false)
    }

    TriggerMacro(*) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveCompareData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveCompareData() {
        this.Data.TrueControlType := GetLangKey(this.ui.Query("TrueControlCon"))
        this.Data.FalseControlType := GetLangKey(this.ui.Query("FalseControlCon"))
        this.Data.TrueMacro := GetLangMacro(this.ui.Query("TrueMacroCon"), 2)
        this.Data.FalseMacro := GetLangMacro(this.ui.Query("FalseMacroCon"), 2)
        this.Data.SaveToggle := this.ui.Query("SaveToggleCon") == "True" ? 1 : 0
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        this.Data.TrueValue := this.ui.Query("TrueValueCon")
        this.Data.FalseValue := this.ui.Query("FalseValueCon")
        this.Data.LogicalType := this._LogicalIndex() + 1
        loop 4 {
            i := A_Index
            this.Data.ToggleArr[i] := this.ui.Query(this.ToggleConArr[i]) == "True" ? 1 : 0
            this.Data.NameArr[i] := GetLangKey(this.ui.Query(this.NameConArr[i]))
            this.Data.CompareTypeArr[i] := this._CompareIndex(i) + 1
            this.Data.VariableArr[i] := GetLangKey(this.ui.Query(this.VariableConArr[i]))
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
