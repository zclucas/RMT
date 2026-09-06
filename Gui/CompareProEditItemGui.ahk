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
        ; 控件名数组（XAML 控件以名字字符串访问）
        this.ToggleConArr := ["ToggleCon1", "ToggleCon2", "ToggleCon3", "ToggleCon4"]
        this.NameConArr := ["NameCon1", "NameCon2", "NameCon3", "NameCon4"]
        this.CompareTypeConArr := ["CompareTypeCon1", "CompareTypeCon2", "CompareTypeCon3", "CompareTypeCon4"]
        this.VariableConArr := ["VariableCon1", "VariableCon2", "VariableCon3", "VariableCon4"]
        this.LogicalTypeCon := "LogicalTypeCon"
        this.ControlTypeCon := "ControlTypeCon"
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
        logicStr := Data.LogicTypeArr[CondiNumber] == 1 ? GetLang("且") : GetLang("或")
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
        title := this.ParentTile GetLang("如果Pro分支编辑器")
        this._title := title
        this.Gui := CompareProEditItemGuiFacade(this)
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容区 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,4,10,0")
        body.Rows("30", "24", "34", "34", "34", "34", "28", "*", "34")

        ; 行0：逻辑关系
        logicRow := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        logicRow.Add("TextBlock").Text(GetLang("逻辑关系：")).VerticalAlignment("Center")
        lc := logicRow.Add("ComboBox").Name("LogicalTypeCon").Width(80).Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["且", "或"])
            lc.Add("ComboBoxItem").Content(t)

        ; 行1：列头（开关 / 选择/输入 / 选择/输入）
        hdr := body.Add("Grid").Grid_Row(1)
        hdr.Cols("Auto", "Auto", "Auto", "Auto")
        hdr.Add("TextBlock").Text(GetLang("开关")).Grid_Column(0).VerticalAlignment("Center")
        hdr.Add("TextBlock").Text(GetLang("选择/输入")).Grid_Column(1).VerticalAlignment("Center").Margin("8,0,0,0")
        hdr.Add("TextBlock").Text(GetLang("选择/输入")).Grid_Column(3).VerticalAlignment("Center").Margin("8,0,0,0")

        ; 行2-5：四个条件行
        loop 4 {
            row := body.Add("Grid").Grid_Row(A_Index + 1)
            row.Cols("Auto", "Auto", "Auto", "Auto")
            row.Add("CheckBox").Name("ToggleCon" A_Index).Grid_Column(0).Width(30).VerticalAlignment("Center")
            row.Add("ComboBox").Name("NameCon" A_Index).Grid_Column(1).Width(120).Height(26).MinHeight(26).Margin("8,0,0,0").IsEditable("True")
                .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
                .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            ct := row.Add("ComboBox").Name("CompareTypeCon" A_Index).Grid_Column(2).Width(80).Height(26).MinHeight(26).Margin("8,0,0,0")
                .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
                .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            for t in GetLangArr(["大于", "大于等于", "等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配"])
                ct.Add("ComboBoxItem").Content(t)
            row.Add("ComboBox").Name("VariableCon" A_Index).Grid_Column(3).Width(120).Height(26).MinHeight(26).Margin("8,0,0,0").IsEditable("True")
                .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
                .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        }

        ; 行6：分支指令 + 编辑按钮
        macroLabelRow := body.Add("StackPanel").Grid_Row(6).Orientation("Horizontal").VerticalAlignment("Center")
        macroLabelRow.Add("TextBlock").Text(GetLang("分支指令:")).VerticalAlignment("Center")
        macroLabelRow.Add("Button").Name("BtnEditMacro").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("10,0,0,0").Padding("12,0").Cursor("Hand")

        ; 行7：分支指令内容（多行）
        body.Add("TextBox").Name("MacroCon").Grid_Row(7).AcceptsReturn("True").TextWrapping("Wrap").FontSize("11")
            .VerticalContentAlignment("Top").Padding("4,2")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行8：流程控制
        ctrlRow := body.Add("StackPanel").Grid_Row(8).Orientation("Horizontal").VerticalAlignment("Center")
        ctrlRow.Add("TextBlock").Text(GetLang("流程控制：")).VerticalAlignment("Center")
        cc := ctrlRow.Add("ComboBox").Name("ControlTypeCon").Width(150).Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["无", "循环-跳过本轮", "循环-跳出", "分支-跳出"])
            cc.Add("ComboBoxItem").Content(t)

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="440" Height="430" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        loop 4
            this.ui.OnEvent("CompareTypeCon" A_Index, "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("BtnEditMacro", "Click", ObjBindMethod(this, "OnEditMacroBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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

    ; 逻辑关系下拉 1=且 2=或（原生 DropDownList.Value 为 1-based 索引）
    _LogicalTypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("LogicalTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return Integer(v) + 1
    }

    ; 比较类型下拉 1-8（原生 DropDownList.Value 为 1-based 索引）
    _CompareTypeIndex(i) {
        v := IsObject(this.ui) ? this.ui.Query("CompareTypeCon" i ">SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 1
        return Integer(v) + 1
    }

    Init(EditType, DataArr, logicStr, macro, controlType) {
        this.EditType := EditType
        this.ui.Update("LogicalTypeCon", "Text", logicStr == "" ? GetLang("且") : logicStr)
        this.ui.Update("MacroCon", "Text", macro)
        this.ui.Update("ControlTypeCon", "Text", GetLang(controlType))
        this.DLVariableArr := GetGuiVarArr(1)

        VariNameArr := DataArr[1]
        CompareTypeArr := DataArr[2]
        VariableArr := DataArr[3]
        loop 4 {
            this.ui.Update("ToggleCon" A_Index, "IsChecked", VariNameArr.Length >= A_Index ? "True" : "False")
            this._SetCombo("NameCon" A_Index, this.DLVariableArr, VariNameArr.Length >= A_Index ? VariNameArr[A_Index] : "Var" A_Index)
            this.ui.Update("CompareTypeCon" A_Index, "SelectedIndex", String((CompareTypeArr.Length >= A_Index ? CompareTypeArr[A_Index] : 1) - 1))
            this._SetCombo("VariableCon" A_Index, this.DLVariableArr, VariableArr.Length >= A_Index ? VariableArr[A_Index] : "Var" A_Index)
        }

        isEnabled := EditType == 1
        this.ui.Update("LogicalTypeCon", "IsEnabled", isEnabled ? "True" : "False")
        loop 4 {
            this.ui.Update("ToggleCon" A_Index, "IsEnabled", isEnabled ? "True" : "False")
            this.ui.Update("NameCon" A_Index, "IsEnabled", isEnabled ? "True" : "False")
            this.ui.Update("CompareTypeCon" A_Index, "IsEnabled", isEnabled ? "True" : "False")
            this.ui.Update("VariableCon" A_Index, "IsEnabled", isEnabled ? "True" : "False")
        }
        ; 程序化填值不触发 SelectionChanged，需显式刷新联动（§4.3）
        this.OnRefresh()
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        loop 4 {
            OperaTypeValue := this._CompareTypeIndex(A_Index)
            EnableVari := OperaTypeValue != 7 && this.EditType == 1
            this.ui.Update("VariableCon" A_Index, "IsEnabled", EnableVari ? "True" : "False")
        }
    }

    OnClickSureBtn(state, ctrl, event) {
        global MySoftData
        action := this.SureBtnAction
        if (this.IsSubMacroEdit) {
            if (this.EditType == 2) {
                this.Data.DefaultMacro := GetLangStr(this.ui.Query("MacroCon"), 2)
                this.Data.DefaultControlType := GetLangKey(this.ui.Query("ControlTypeCon"))
            }
            else {
                VariNameArr := []
                CompareTypeArr := []
                VariableArr := []
                loop 4 {
                    if (this.ui.Query("ToggleCon" A_Index) == "True") {
                        VariNameArr.Push(this.ui.Query("NameCon" A_Index))
                        CompareTypeArr.Push(this._CompareTypeIndex(A_Index))
                        VariableArr.Push(this.ui.Query("VariableCon" A_Index))
                    }
                }
                this.Data.VariNameArr[this.CondiNumber] := GetLangKeyArr(VariNameArr)
                this.Data.CompareTypeArr[this.CondiNumber] := GetLangKeyArr(CompareTypeArr)
                this.Data.VariableArr[this.CondiNumber] := GetLangKeyArr(VariableArr)
                this.Data.LogicTypeArr[this.CondiNumber] := this._LogicalTypeIndex()
                this.Data.MacroArr[this.CondiNumber] := GetLangStr(this.ui.Query("MacroCon"), 2)
                this.Data.ControlTypeArr[this.CondiNumber] := GetLangKey(this.ui.Query("ControlTypeCon"))
            }
            saveStr := JSON.stringify(this.Data, 0)
            IniWrite(saveStr, CompareProFile, IniSection, this.Data.SerialStr)
            if (MySoftData.DataCacheMap.Has(this.Data.SerialStr)) {
                MySoftData.DataCacheMap.Delete(this.Data.SerialStr)
            }
            action(this.ui.Query("MacroCon"))
        }
        else if (this.EditType == 1) {
            condiStr := ""
            loop 4 {
                if (this.ui.Query("ToggleCon" A_Index) == "True") {
                    if (this.ui.Query("CompareTypeCon" A_Index) != GetLang("变量存在")) {
                        condiStr .= this.ui.Query("NameCon" A_Index) " " this.ui.Query("CompareTypeCon" A_Index) " " this.ui.Query(
                            "VariableCon" A_Index)
                    }
                    else {
                        condiStr .= this.ui.Query("NameCon" A_Index) " " this.ui.Query("CompareTypeCon" A_Index)
                    }

                    condiStr .= "⎖"
                }
            }
            condiStr := Trim(condiStr, "⎖")
            logicStr := this.ui.Query("LogicalTypeCon")
            macro := this.ui.Query("MacroCon")
            controlType := GetLangKey(this.ui.Query("ControlTypeCon"))
            action(condiStr, logicStr, macro, controlType)
        }
        else {
            controlType := GetLangKey(this.ui.Query("ControlTypeCon"))
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
