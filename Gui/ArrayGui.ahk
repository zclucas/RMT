#Requires AutoHotkey v2.0

; =====================================================================
; 数组编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class ArrayGui {
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
        this.OnRefresh()
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
        title := this.ParentTile GetLang("数组编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Cols("70", "120", "90", "160")

        ; 行0：备注 + IsIgnoreExist
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")
        row0.Add("CheckBox").Name("IsIgnoreExist").Content(GetLang("如果变量存在则不改变数据")).VerticalAlignment("Center").Margin("20,0,0,0")

        ; 行1：类型 + 数组名 + 子索引
        row1 := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("类型：")).VerticalAlignment("Center")
        tc := row1.Add("ComboBox").Name("TypeCombo").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"])
            tc.Add("ComboBoxItem").Content(t)
        row1.Add("TextBlock").Text(GetLang("数组名：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row1.Add("ComboBox").Name("NameCon").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        mainIndexRow := row1.Add("StackPanel").Name("MainIndexRow").Orientation("Horizontal").Margin("14,0,0,0")
        mainIndexRow.Add("TextBlock").Text(GetLang("子索引：")).VerticalAlignment("Center")
        mainIndexRow.Add("ComboBox").Name("MainIndexCon").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        mainIndexRow.Add("Button").Name("BtnIndexHelp").Content("?").Width(28).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行2：创建参数 + 类型参数（两个 GroupBox 并排）
        body.Rows("34", "38", "Auto", "Auto", "40", "*")
        createGroup := body.Add("GroupBox").Grid_Row(2).Grid_ColumnSpan(4).Name("CreateGroup").Header(GetLang("创建参数"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        cr := createGroup.Add("StackPanel").Orientation("Horizontal").Margin("10,6")
        cr.Add("TextBlock").Text(GetLang("初始数据：")).VerticalAlignment("Center")
        cr.Add("TextBox").Name("InitArrCon").Width(400).Height(26).MinHeight(26).Margin("4,0,0,0").Text("1, 2, 3")
        cr.Add("Button").Name("BtnInitHelp").Content("?").Width(28).Height(26).MinHeight(26).Margin("4,0,0,0")

        argsGroup := body.Add("GroupBox").Grid_Row(3).Grid_ColumnSpan(4).Name("ArgsGroup").Header(GetLang("类型参数"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        ar := argsGroup.Add("StackPanel").Orientation("Horizontal").Margin("10,6")
        argsIndexRow := ar.Add("StackPanel").Name("ArgsIndexRow").Orientation("Horizontal")
        argsIndexRow.Add("TextBlock").Text(GetLang("索引：")).VerticalAlignment("Center")
        argsIndexRow.Add("ComboBox").Name("ArgsIndexCon").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        argsDataRow := ar.Add("StackPanel").Name("ArgsDataRow").Orientation("Horizontal").Margin("14,0,0,0")
        argsDataRow.Add("TextBlock").Text(GetLang("数据：")).VerticalAlignment("Center")
        at := argsDataRow.Add("ComboBox").Name("ArgsTypeCon").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0")
        at.Add("ComboBoxItem").Content(GetLang("变量或值"))
        at.Add("ComboBoxItem").Content(GetLang("数组"))
        argsDataRow.Add("ComboBox").Name("ArgsNameCon").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; 行4：结果
        resRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Name("ResultRow").Orientation("Horizontal").VerticalAlignment("Center")
        resRow.Add("TextBlock").Text(GetLang("结果：")).VerticalAlignment("Center")
        st := resRow.Add("ComboBox").Name("SaveTypeCon").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0")
        st.Add("ComboBoxItem").Content(GetLang("变量"))
        st.Add("ComboBoxItem").Content(GetLang("数组"))
        resRow.Add("ComboBox").Name("SaveNameCon").Width(130).Height(26).MinHeight(26).Margin("10,0,0,0").IsEditable("True")

        ; 行5：确定
        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="600" Height="290" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("ArgsTypeCon", "SelectionChanged", ObjBindMethod(this, "OnRefreshDataType"))
        this.ui.OnEvent("SaveTypeCon", "SelectionChanged", ObjBindMethod(this, "OnRefreshDataType"))
        this.ui.OnEvent("BtnIndexHelp", "Click", ObjBindMethod(this, "OnClickIndexHelpBtn"))
        this.ui.OnEvent("BtnInitHelp", "Click", ObjBindMethod(this, "OnClickInitHelpBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
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

    _SetDDL(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        for i, it in items {
            if (it == text) {
                this._ComboPush(comboName, "SelectedIndex", String(i - 1))
                return
            }
        }
        this._ComboPush(comboName, "SelectedIndex", "0")
    }

    _Vis(name, show) {
        if (IsObject(this.ui))
            this.ui.Update(name, "Visibility", show ? "Visible" : "Collapsed")
    }

    _TypeText() => IsObject(this.ui) ? this.ui.Query("TypeCombo") : ""

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("数组")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        this.DLArrayArr := GetGuiArrNameArr()

        this._SetDDL("TypeCombo", GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"]), GetLang(this.Data.Type))
        this.ui.Update("IsIgnoreExist", "IsChecked", this.Data.IsIgnoreExist ? "True" : "False")
        this._SetCombo("NameCon", this.DLArrayArr, this.Data.Name)
        this._SetCombo("MainIndexCon", GetGuiVarArr(2), this.Data.MainIndex)
        this.ui.Update("InitArrCon", "Text", GetArrayStr(this.Data.InitArr))
        this._SetCombo("ArgsIndexCon", GetGuiVarArr(2), this.Data.ArgsIndex)
        this._SetDDL("ArgsTypeCon", GetLangArr(["变量或值", "数组"]), GetLang(this.Data.ArgsType))
        this._SetCombo("ArgsNameCon", this.DLVariableArr, this.Data.ArgsName)
        this._SetDDL("SaveTypeCon", GetLangArr(["变量", "数组"]), GetLang(this.Data.SaveType))
        this._SetCombo("SaveNameCon", this.DLVariableArr, this.Data.SaveName)
    }

    OnRefresh(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        t := this._TypeText()
        IsCreate := t == GetLang("创建")
        IsClone := t == GetLang("克隆")
        IsDelete := t == GetLang("删除")
        IsContain := t == GetLang("包含")
        IsGet := t == GetLang("取值")
        IsSetValue := t == GetLang("赋值")
        IsInsert := t == GetLang("插入")
        IsAdd := t == GetLang("追加")
        IsRemove := t == GetLang("移除")
        IsRemoveLast := t == GetLang("移除最后")
        IsReverse := t == GetLang("反转")
        IsLength := t == GetLang("长度")
        OnlyResVar := IsLength || IsContain
        OnlyResArr := IsClone || IsReverse
        OnlyArgsIndex := IsGet || IsRemove
        OnlyArgsData := IsAdd || IsContain
        IsShowRusult := IsGet || IsLength || IsClone || IsRemove || IsRemoveLast || IsContain || IsReverse
        IsShowMainIndex := !IsCreate && !IsDelete
        IsShowArgs := IsGet || IsSetValue || IsInsert || IsAdd || IsRemove || IsContain

        this._Vis("IsIgnoreExist", IsCreate)
        this._Vis("MainIndexRow", IsShowMainIndex)
        this._Vis("ResultRow", IsShowRusult)
        this._Vis("CreateGroup", IsCreate)
        this._Vis("ArgsGroup", IsShowArgs)
        this._Vis("ArgsIndexRow", IsShowArgs && !OnlyArgsData)
        this._Vis("ArgsDataRow", IsShowArgs && !OnlyArgsIndex)

        if (OnlyResVar || OnlyResArr) {
            this._SetDDL("SaveTypeCon", GetLangArr(["变量", "数组"]), OnlyResVar ? GetLang("变量") : GetLang("数组"))
            this.ui.Update("SaveTypeCon", "IsEnabled", "False")
        }
        else {
            this.ui.Update("SaveTypeCon", "IsEnabled", "True")
        }
        this.OnRefreshDataType()
    }

    OnRefreshDataType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        IsArgsVar := this.ui.Query("ArgsTypeCon") == GetLang("变量或值")
        IsResVar := this.ui.Query("SaveTypeCon") == GetLang("变量")
        ArgsArr := IsArgsVar ? this.DLVariableArr : this.DLArrayArr
        ResArr := IsResVar ? GetGuiVarArr(0) : this.DLArrayArr
        curArgs := this.ui.Query("ArgsNameCon")
        curSave := this.ui.Query("SaveNameCon")
        this._SetCombo("ArgsNameCon", ArgsArr, curArgs)
        this._SetCombo("SaveNameCon", ResArr, curSave)
    }

    OnClickIndexHelpBtn(state := "", ctrl := "", event := "") {
        str1 := GetLang("数组支持二维，该参数可控制数组或子数组进行调度")
        str2 := GetLang("一维数组时，保持默认值0即可")
        str3 := GetLang("0. 数组本身")
        str4 := GetLang("N. 对应索引的子数组")
        MsgBox(Format("{}`n{}`n{}`n{}", str1, str2, str3, str4))
    }

    OnClickInitHelpBtn(state := "", ctrl := "", event := "") {
        str1 := GetLang("1. 逗号分割数据")
        str2 := GetLang("案例数据：1,2,文本,4")
        str3 := GetLang('数组-1→1、数组-2→2、数组-3→"文本"、数组-4→4')
        str4 := GetLang("2. 中括号表示数组数据")
        str5 := GetLang('案例数据：1,"文本",[2, 5, 7],8')
        str6 := GetLang('数组-1→1、数组-2→"文本"、数组-3→2, 5, 7、数组-4→8')
        str7 := GetLang("3. 数据中使用\符号，表示原本的功能")
        str8 := GetLang("案例数据1,我的\,世界,\[若梦兔\],4")
        str9 := GetLang('数组-1→1、数组-2→"我的,世界"、数组-3→"[若梦兔]"、数组-4→4')
        MsgBox(Format("{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6, str7, str8, str9))
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveSubMacroData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        if (!CheckVarNameIfValid(this.ui.Query("SaveNameCon")))
            return false
        return true
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.ui.Query("RemarkCon")
        if (ShouldAutoGenerateRemark(Remark)) {
            switch this.Data.Type {
                case "创建":
                    Remark := Format(GetLang("创建{}"), this.Data.Name)
                case "克隆":
                    Remark := Format(GetLang("克隆{}到{}"), this.Data.Name, this.Data.SaveName)
                case "删除":
                    Remark := Format(GetLang("删除{}"), this.Data.Name)
                case "包含":
                    tip1 := Format(GetLang("{}包含数据{}"), this.Data.Name, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}包含数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "取值":
                    tip1 := Format(GetLang("取值{}-{}到{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.SaveName)
                    tip2 := Format(GetLang("取值{}-{}-{}到{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex, this.Data.SaveName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "赋值":
                    tip1 := Format(GetLang("{}-{}赋值为{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}-{}赋值为{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "插入":
                    tip1 := Format(GetLang("{}-{}插入数据{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}-{}插入数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "追加":
                    tip1 := Format(GetLang("{}追加数据{}"), this.Data.Name, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}追加数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "移除":
                    tip1 := Format(GetLang("移除{}-{}"), this.Data.Name, this.Data.ArgsIndex)
                    tip2 := Format(GetLang("移除{}-{}-{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "移除最后":
                    tip1 := Format(GetLang("移除{}-最后数据"), this.Data.Name)
                    tip2 := Format(GetLang("移除{}-{}最后数据"), this.Data.Name, this.Data.MainIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "长度":
                    tip1 := Format(GetLang("{}长度"), this.Data.Name)
                    tip2 := Format(GetLang("{}-{}长度"), this.Data.Name, this.Data.MainIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
            }
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        isCreate := this._TypeText() == GetLang("创建")
        this.Data.IsIgnoreExist := isCreate ? (this.ui.Query("IsIgnoreExist") == "True") : 0
        this.Data.Type := GetLangKey(this._TypeText())
        this.Data.Name := this.ui.Query("NameCon")
        this.Data.InitArr := GetArray(this.ui.Query("InitArrCon"))
        this.Data.MainIndex := GetLangKey(this.ui.Query("MainIndexCon"))
        this.Data.ArgsIndex := GetLangKey(this.ui.Query("ArgsIndexCon"))
        this.Data.ArgsType := GetLangKey(this.ui.Query("ArgsTypeCon"))
        this.Data.ArgsName := GetLangKey(this.ui.Query("ArgsNameCon"))
        this.Data.SaveType := GetLangKey(this.ui.Query("SaveTypeCon"))
        this.Data.SaveName := GetVarName(this.ui.Query("SaveNameCon"))
        SetArrayDataNewArr(this.Data)
        SetArrayDataNewVar(this.Data)
        SaveMacroCMDData(this.Data)
    }
}
