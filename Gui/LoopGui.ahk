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
        this.FocusCon := { Focus: ObjBindMethod(this, "_FocusSureBtn") }
        this._closed := true
        this._title := ""

        this.Data := ""
        this.DLVariableArr := []
        ; 控件名数组（XAML 版不持有原生控件对象，按名 Query/Update）
        this.ToggleConArr := ["ToggleCon_1", "ToggleCon_2", "ToggleCon_3", "ToggleCon_4"]
        this.NameConArr := ["NameCon_1", "NameCon_2", "NameCon_3", "NameCon_4"]
        this.CompareTypeConArr := ["CompareTypeCon_1", "CompareTypeCon_2", "CompareTypeCon_3", "CompareTypeCon_4"]
        this.VariableConArr := ["VariableCon_1", "VariableCon_2", "VariableCon_3", "VariableCon_4"]
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
        title := this.ParentTile GetLang("循环编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "34", "32", "*", "Auto", "48")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 顶部工具行：快捷方式 + 执行指令 + 备注 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,4")
        top.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        top.Add("TextBlock").Text("!l").VerticalAlignment("Center").Margin("4,0,0,0").Opacity("0.6")
        top.Add("Button").Name("BtnTrigger").Content(GetLang("执行指令")).Width(80).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("TextBox").Name("RemarkCon").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; === 循环次数行 ===
        countRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,2")
        countRow.Add("TextBlock").Text(GetLang("循环次数：")).VerticalAlignment("Center")
        countRow.Add("ComboBox").Name("CountCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 循环条件 GroupBox ===
        cg := main.Add("GroupBox").Grid_Row(3).Margin("10,2,10,6").Header(GetLang("循环条件:"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("6,4")
        condiGrid := cg.Add("Grid")
        condiGrid.Cols("Auto", "Auto", "Auto", "Auto", "*")
        condiGrid.Rows("30", "30", "30", "30", "30")

        hd := condiGrid.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(5).Orientation("Horizontal").VerticalAlignment("Center")
        hd.Add("TextBlock").Text(GetLang("类型:")).VerticalAlignment("Center")
        condiCon := hd.Add("ComboBox").Name("CondiCon").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["无", "继续条件", "退出条件"])
            condiCon.Add("ComboBoxItem").Content(t)
        hd.Add("TextBlock").Text(GetLang("条件逻辑关系:")).VerticalAlignment("Center").Margin("14,0,0,0")
        logicCon := hd.Add("ComboBox").Name("LogicCon").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["且", "或"])
            logicCon.Add("ComboBoxItem").Content(t)

        loop 4
            this._AddCondiRow(condiGrid, A_Index)

        ; === 循环体 ===
        body := main.Add("StackPanel").Grid_Row(4).Orientation("Vertical").Margin("10,4,10,0")
        lbRow := body.Add("StackPanel").Orientation("Horizontal")
        lbRow.Add("TextBlock").Text(GetLang("循环体:")).VerticalAlignment("Center")
        lbRow.Add("Button").Name("BtnEditMacro").Content(GetLang("编辑")).Width(70).Height(26).MinHeight(26).Margin("10,0,0,0").Cursor("Hand")
        body.Add("TextBox").Name("LoopBodyCon").Height(90).Margin("0,4,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("4,2").FontSize(11)
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="480" Height="520" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnTrigger", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnEditMacro", "Click", ObjBindMethod(this, "OnEditMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("CondiCon", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        loop 4
            this.ui.OnEvent(this.CompareTypeConArr[A_Index], "SelectionChanged", ObjBindMethod(this, "OnRefresh"))

    }

    _AddCondiRow(grid, idx) {
        grid.Add("CheckBox").Name(this.ToggleConArr[idx]).Grid_Row(idx).Grid_Column(0).VerticalAlignment("Center")
        grid.Add("ComboBox").Name(this.NameConArr[idx]).Grid_Row(idx).Grid_Column(1).Width(140).Height(26).MinHeight(26).Margin("8,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        cc := grid.Add("ComboBox").Name(this.CompareTypeConArr[idx]).Grid_Row(idx).Grid_Column(2).Width(90).Height(26).MinHeight(26).Margin("8,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["大于", "大于等于", "等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配"])
            cc.Add("ComboBoxItem").Content(t)
        grid.Add("ComboBox").Name(this.VariableConArr[idx]).Grid_Row(idx).Grid_Column(3).Width(140).Height(26).MinHeight(26).Margin("8,0,0,0").IsEditable("True")
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
        v := IsObject(this.ui) ? this.ui.Query(this.CompareTypeConArr[idx] ">SelectedIndex") : ""
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
        this.ui.Update("CondiCon", "SelectedIndex", String(this.Data.CondiType - 1))
        this.ui.Update("LogicCon", "SelectedIndex", String(this.Data.LogicType - 1))
        this.ui.Update("LoopBodyCon", "Text", GetLangMacro(this.Data.LoopBody, 1))

        loop 4 {
            this.ui.Update(this.ToggleConArr[A_Index], "IsChecked", this.Data.ToggleArr[A_Index] ? "True" : "False")
            this._SetCombo(this.NameConArr[A_Index], this.DLVariableArr, GetLang(this.Data.NameArr[A_Index]))
            this.ui.Update(this.CompareTypeConArr[A_Index], "SelectedIndex", String(this.Data.CompareTypeArr[A_Index] - 1))
            this._SetCombo(this.VariableConArr[A_Index], this.DLVariableArr, GetLang(this.Data.VariableArr[A_Index]))
        }
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
        showCondi := this._CondiIndex() != 0
        this.ui.Update("LogicCon", "IsEnabled", showCondi ? "True" : "False")

        loop 4 {
            ; 原生 CompareTypeCon.Value 1-based，7 存在变量（0-based index 6）时变量列禁用
            enableVari := this._CompareIndex(A_Index) != 6

            this.ui.Update(this.ToggleConArr[A_Index], "IsEnabled", showCondi ? "True" : "False")
            this.ui.Update(this.NameConArr[A_Index], "IsEnabled", showCondi ? "True" : "False")
            this.ui.Update(this.CompareTypeConArr[A_Index], "IsEnabled", showCondi ? "True" : "False")
            this.ui.Update(this.VariableConArr[A_Index], "IsEnabled", (enableVari && showCondi) ? "True" : "False")
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
        this.Data.CondiType := this._CondiIndex() + 1
        this.Data.LogicType := this._LogicIndex() + 1
        this.Data.LoopBody := GetLangMacro(this.ui.Query("LoopBodyCon"), 2)

        loop 4 {
            this.Data.ToggleArr[A_Index] := this.ui.Query(this.ToggleConArr[A_Index]) == "True" ? 1 : 0
            this.Data.NameArr[A_Index] := GetLangKey(this.ui.Query(this.NameConArr[A_Index]))
            this.Data.CompareTypeArr[A_Index] := this._CompareIndex(A_Index) + 1
            this.Data.VariableArr[A_Index] := GetLangKey(this.ui.Query(this.VariableConArr[A_Index]))
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
