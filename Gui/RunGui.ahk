#Requires AutoHotkey v2.0

; =====================================================================
; 运行编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class RunGui {
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
        this.ActiveEdit := ""

        this.StdInEditGui := ""
        this._stdInClosed := true
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
        this.ToggleFunc(true)
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
        title := this.ParentTile GetLang("运行编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "34", "34", "34", "30", "30", "66", "24", "*")

        ; 行0：快捷方式
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：模式 + 选项
        row1 := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("模式：")).VerticalAlignment("Center")
        rm := row1.Add("ComboBox").Name("RunModeCombo").Width(110).Height(26).MinHeight(26).Margin("4,0,0,0")
        for m in [GetLang("不等待"), GetLang("等待+返回值"), GetLang("不等待+输入"), GetLang("等待+输入输出")]
            rm.Add("ComboBoxItem").Content(m)
        row1.Add("TextBlock").Text(GetLang("选项：")).VerticalAlignment("Center").Margin("14,0,0,0")
        opt := row1.Add("ComboBox").Name("OptionCombo").Width(110).Height(26).MinHeight(26).Margin("4,0,0,0")
        for o in GetLangArr(["后台", "默认", "最小化", "最大化"])
            opt.Add("ComboBoxItem").Content(o)

        ; 行2：变量
        row2 := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        row2.Add("TextBlock").Text(GetLang("变量：")).VerticalAlignment("Center")
        row2.Add("ComboBox").Name("VariCombo").Width(110).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        row2.Add("Button").Name("BtnAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).Margin("8,0,0,0")
        row2.Add("Button").Name("BtnAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行3：目标
        row3 := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").VerticalAlignment("Center")
        row3.Add("TextBlock").Text(GetLang("目标：")).VerticalAlignment("Center")
        row3.Add("TextBox").Name("PathTextCon").Width(430).Height(24).MinHeight(24).Margin("4,0,0,0")
        row3.Add("Button").Name("BtnSelectFile").Content(GetLang("选择文件")).Height(26).MinHeight(26).Margin("6,0,0,0")

        ; 行4：返回值/输出/错误
        snRow := body.Add("StackPanel").Grid_Row(4).Orientation("Horizontal").VerticalAlignment("Center")
        sn1 := snRow.Add("StackPanel").Name("SaveName1Row").Orientation("Horizontal")
        sn1.Add("TextBlock").Name("SaveNameTip1").Text(GetLang("返回值：")).VerticalAlignment("Center").Width(66)
        sn1.Add("ComboBox").Name("SaveName1").Width(100).Height(24).MinHeight(24).IsEditable("True")
        sn2 := snRow.Add("StackPanel").Name("SaveName2Row").Orientation("Horizontal").Margin("16,0,0,0")
        sn2.Add("TextBlock").Name("SaveNameTip2").Text(GetLang("输出：")).VerticalAlignment("Center").Width(66)
        sn2.Add("ComboBox").Name("SaveName2").Width(100).Height(24).MinHeight(24).IsEditable("True")
        sn3 := snRow.Add("StackPanel").Name("SaveName3Row").Orientation("Horizontal").Margin("16,0,0,0")
        sn3.Add("TextBlock").Name("SaveNameTip3").Text(GetLang("错误：")).VerticalAlignment("Center").Width(66)
        sn3.Add("ComboBox").Name("SaveName3").Width(100).Height(24).MinHeight(24).IsEditable("True")

        ; 行5：编码
        encRow := body.Add("StackPanel").Grid_Row(5).Orientation("Horizontal").VerticalAlignment("Center")
        ei := encRow.Add("StackPanel").Name("EncInRow").Orientation("Horizontal")
        ei.Add("TextBlock").Name("EncInTip").Text(GetLang("输入编码：")).VerticalAlignment("Center").Width(66)
        ei.Add("ComboBox").Name("EncIn").Width(100).Height(24).MinHeight(24).IsEditable("True")
        eo := encRow.Add("StackPanel").Name("EncOutRow").Orientation("Horizontal").Margin("16,0,0,0")
        eo.Add("TextBlock").Name("EncOutTip").Text(GetLang("输出编码：")).VerticalAlignment("Center").Width(66)
        eo.Add("ComboBox").Name("EncOut").Width(100).Height(24).MinHeight(24).IsEditable("True")
        ee := encRow.Add("StackPanel").Name("EncErrRow").Orientation("Horizontal").Margin("16,0,0,0")
        ee.Add("TextBlock").Name("EncErrTip").Text(GetLang("错误编码：")).VerticalAlignment("Center").Width(66)
        ee.Add("ComboBox").Name("EncErr").Width(100).Height(24).MinHeight(24).IsEditable("True")

        ; 行6：输入
        stdRow := body.Add("StackPanel").Grid_Row(6).Orientation("Horizontal").VerticalAlignment("Center")
        stdRow.Add("TextBlock").Text(GetLang("输入：")).VerticalAlignment("Top").Margin("0,20,0,0")
        stdRow.Add("TextBox").Name("StdInCon").Width(390).Height(60).MinHeight(60).Margin("4,0,0,0").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        stdRow.Add("Button").Name("BtnStdInEdit").Content(GetLang("编辑")).Width(100).Height(60).MinHeight(60).Margin("6,0,0,0")

        ; 行7：提示
        body.Add("TextBlock").Grid_Row(7).Text(GetLang("支持启动程序（如.exe、.bat）、打开文件（如.txt、.mp4）或网址等等")).VerticalAlignment("Center")

        ; 行8：确定
        btnRow := body.Add("StackPanel").Grid_Row(8).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="600" Height="400" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("RunModeCombo", "SelectionChanged", ObjBindMethod(this, "OnModeChange"))
        this.ui.OnEvent("BtnAddName", "Click", ObjBindMethod(this, "OnClickAddVarNameBtn"))
        this.ui.OnEvent("BtnAddValue", "Click", ObjBindMethod(this, "OnClickAddVarValueBtn"))
        this.ui.OnEvent("PathTextCon", "GotKeyboardFocus", (*) => this.ActiveEdit := "PathTextCon")
        this.ui.OnEvent("StdInCon", "GotKeyboardFocus", (*) => this.ActiveEdit := "StdInCon")
        this.ui.OnEvent("BtnSelectFile", "Click", ObjBindMethod(this, "OnClickFileSelectBtn"))
        this.ui.OnEvent("BtnStdInEdit", "Click", ObjBindMethod(this, "OpenStdInEditor"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    _CloseStdInEditor() {
        if (IsObject(this.StdInEditGui) && !this._stdInClosed) {
            try this.StdInEditGui.Update("Window", "Close", "")
            this.StdInEditGui := ""
            this._stdInClosed := true
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
        this._CloseStdInEditor()
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
        this.ToggleFunc(false)
        this._CloseStdInEditor()
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

    _SelIndex(comboName) {
        v := IsObject(this.ui) ? this.ui.Query(comboName ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运行")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        ; 還原跳脫的花括號供介面顯示（{{xxx}} → {xxx}）
        this.ui.Update("PathTextCon", "Text", UnescapeVarText(this.Data.Target))

        DLVariableArr := GetGuiVarArr(1)
        this._SetCombo("VariCombo", DLVariableArr, "")

        this.ui.Update("RunModeCombo", "SelectedIndex", String(this.Data.Mode - 1))
        this.ui.Update("OptionCombo", "SelectedIndex", String((ObjHasOwnProp(this.Data, "Option") ? this.Data.Option + 1 : 2) - 1))
        this.ui.Update("StdInCon", "Text", ObjHasOwnProp(this.Data, "StdIn") ? UnescapeVarText(this.Data.StdIn) : "")

        ; Load encoding - default to UTF-8
        this._SetCombo("EncIn", ["UTF-8", "UTF-16", "CP0"], (ObjHasOwnProp(this.Data, "Encoding") && ObjHasOwnProp(this.Data.Encoding, "In")) ? this.Data.Encoding.In : "UTF-8")
        this._SetCombo("EncOut", ["UTF-8", "UTF-16", "CP0"], (ObjHasOwnProp(this.Data, "Encoding") && ObjHasOwnProp(this.Data.Encoding, "Out")) ? this.Data.Encoding.Out : "UTF-8")
        this._SetCombo("EncErr", ["UTF-8", "UTF-16", "CP0"], (ObjHasOwnProp(this.Data, "Encoding") && ObjHasOwnProp(this.Data.Encoding, "Err")) ? this.Data.Encoding.Err : "UTF-8")

        loop 3 {
            if (ObjHasOwnProp(this.Data, "SaveNameArr") && this.Data.SaveNameArr.Length >= A_Index)
                saveText := this.Data.SaveNameArr[A_Index]
            else
                saveText := (A_Index == 1 ? "ExitCode" : (A_Index == 2 ? "StdOut" : "StdErr"))
            this._SetCombo("SaveName" A_Index, GetGuiVarArr(0), saveText)
        }
        this.OnModeChange()
    }

    GetCommandStr() {
        textOnly := RTrim(this.Data.SerialStr, "0123456789")
        numbersOnly := SubStr(this.Data.SerialStr, StrLen(textOnly) + 1)
        commandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        commandStr := CorrectRemark(commandStr, this.ui.Query("RemarkCon"))
        return commandStr
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        Hotkey("!l", MacroAction, state ? "On" : "Off")
    }

    _Vis(name, vis) {
        if (IsObject(this.ui))
            this.ui.Update(name, "Visibility", vis ? "Visible" : "Collapsed")
    }

    OnModeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        val := this._SelIndex("RunModeCombo") + 1
        showSN1 := val == 2 || val == 4
        showSN23 := val == 4
        showStdIn := val == 3 || val == 4
        showEncIn := val == 3 || val == 4
        showEncOutErr := val == 4
        this._Vis("SaveName1Row", showSN1)
        this._Vis("SaveName2Row", showSN23)
        this._Vis("SaveName3Row", showSN23)
        this._Vis("EncInRow", showEncIn)
        this._Vis("EncOutRow", showEncOutErr)
        this._Vis("EncErrRow", showEncOutErr)
        this._Vis("StdInRow", showStdIn)
    }

    OnClickFileSelectBtn(state := "", ctrl := "", event := "") {
        fileString := FileSelect("S1", "", GetLang("选择要运行的文件"))
        if (fileString == "")
            return
        this.ui.Update("PathTextCon", "Text", '"' fileString '"')
    }

    OpenStdInEditor(state := "", ctrl := "", event := "") {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed) {
            this.AddStdInEditorGui()
        }
        vars := GetGuiVarArr(1)
        this.StdInEditGui.Update("StdInEditVariCombo", "ClearItems", "")
        for v in vars {
            if (v != "")
                this.StdInEditGui.Update("StdInEditVariCombo", "AddItem", v)
        }
        if (vars.Length > 0)
            this.StdInEditGui.Update("StdInEditVariCombo", "SelectedIndex", "0")

        curText := IsObject(this.ui) ? this.ui.Query("StdInCon") : ""
        this.StdInEditGui.Update("StdInEditCon", "Text", curText)

        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        if (!XamlWin.Open(this.StdInEditGui, "", owner))
            this._stdInClosed := true
    }

    AddStdInEditorGui() {
        global MySoftData
        this._CloseStdInEditor()
        this._stdInClosed := false
        title := this.ParentTile GetLang("输入编辑器")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8")
        body.Rows("32", "*", "38")

        ; 行0：变量 + 追加名 + 追加值
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("变量：")).VerticalAlignment("Center")
        row0.Add("ComboBox").Name("StdInEditVariCombo").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
        row0.Add("Button").Name("BtnStdInAddName").Content(GetLang("追加名")).Height(26).MinHeight(26).Margin("8,0,0,0")
        row0.Add("Button").Name("BtnStdInAddValue").Content(GetLang("追加值")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行1：文本框
        body.Add("TextBox").Grid_Row(1).Name("StdInEditCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Margin("0,6,0,6")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 行2：确定
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnStdInOk").Content(GetLang("确定")).Width(90).Height(30).MinHeight(30)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        owner := (this.Hwnd() ? this.Hwnd() : this.OwnerHwnd)
        this.StdInEditGui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        this.StdInEditGui.xaml := StrReplace(this.StdInEditGui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="700" Height="420" Opacity="0"')
        this.StdInEditGui.xaml := StrReplace(this.StdInEditGui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.StdInEditGui.xaml := StrReplace(this.StdInEditGui.xaml, '%resources%', '')

        ; === 事件 ===
        this.StdInEditGui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnStdInWindowClosing"))
        this.StdInEditGui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnStdInWindowLoad"))
        this.StdInEditGui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClickStdInEditorClose"))
        this.StdInEditGui.OnEvent("BtnStdInAddName", "Click", ObjBindMethod(this, "OnClickStdInEditorAddVarNameBtn"))
        this.StdInEditGui.OnEvent("BtnStdInAddValue", "Click", ObjBindMethod(this, "OnClickStdInEditorAddVarValueBtn"))
        this.StdInEditGui.OnEvent("StdInEditCon", "TextChanged", ObjBindMethod(this, "OnStdInEditChange"))
        this.StdInEditGui.OnEvent("StdInEditCon", "GotKeyboardFocus", (*) => this.ActiveEdit := "StdInEditCon")
        this.StdInEditGui.OnEvent("BtnStdInOk", "Click", ObjBindMethod(this, "OnClickStdInEditorClose"))
    }

    OnStdInWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.StdInEditGui)
    }

    OnStdInWindowClosing(state, ctrl, event) {
        this._stdInClosed := true
        this.StdInEditGui := ""
    }

    OnStdInEditChange(state := "", ctrl := "", event := "") {
        if (IsObject(this.StdInEditGui) && !this._stdInClosed && IsObject(this.ui)) {
            val := this.StdInEditGui.Query("StdInEditCon")
            this.ui.Update("StdInCon", "Text", val)
        }
    }

    OnClickStdInEditorAddVarNameBtn(state := "", ctrl := "", event := "") {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed)
            return
        varName := this.StdInEditGui.Query("StdInEditVariCombo")
        if (varName != "") {
            this.StdInEditGui.Update("StdInEditCon", "InsertText", varName)
            this.OnStdInEditChange()
        }
    }

    OnClickStdInEditorAddVarValueBtn(state := "", ctrl := "", event := "") {
        if (!IsObject(this.StdInEditGui) || this._stdInClosed)
            return
        varName := this.StdInEditGui.Query("StdInEditVariCombo")
        if (varName != "") {
            this.StdInEditGui.Update("StdInEditCon", "InsertText", "{" varName "}")
            this.OnStdInEditChange()
        }
    }

    OnClickStdInEditorClose(state := "", ctrl := "", event := "") {
        this._CloseStdInEditor()
    }

    OnClickSureBtn(state, ctrl, event) {
        ; ----- 编码提示（仅当模式为“等待+输入输出”时）-----
        if (this._SelIndex("RunModeCombo") + 1 == 3) {
            for enc in [this.ui.Query("EncIn"), this.ui.Query("EncOut")] {
                if (enc != "UTF-8" && enc != "UTF-16" && (SubStr(enc, 1, 2) != "CP")) {
                    MsgBox(Format("不支持{}编码", enc))
                    return
                }
            }
        }

        if (!this.CheckIfValid())
            return
        this.SaveRunData()
        this.ToggleFunc(false)
        action := this.SureBtnAction
        action(this.GetCommandStr())

        this._CloseWindow()
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    CheckIfValid() {
        if (this.ui.Query("PathTextCon") == "") {
            MsgBox(GetLang("目标不能为空！"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveRunData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveRunData() {
        this.Data.Target := SmartEscapeVarText(GetLangStr(this.ui.Query("PathTextCon"), 2))
        this.Data.Mode := this._SelIndex("RunModeCombo") + 1
        this.Data.Option := this._SelIndex("OptionCombo")

        if (this.Data.Mode == 1) {
            if (ObjHasOwnProp(this.Data, "StdIn"))
                this.Data.DeleteProp("StdIn")
            if (ObjHasOwnProp(this.Data, "SaveNameArr"))
                this.Data.DeleteProp("SaveNameArr")
            if (ObjHasOwnProp(this.Data, "Encoding"))
                this.Data.DeleteProp("Encoding")
        } else if (this.Data.Mode == 2) {
            if (ObjHasOwnProp(this.Data, "StdIn"))
                this.Data.DeleteProp("StdIn")
            this.Data.SaveNameArr := [this.ui.Query("SaveName1")]
            if (ObjHasOwnProp(this.Data, "Encoding"))
                this.Data.DeleteProp("Encoding")
        } else if (this.Data.Mode == 3) {
            this.Data.StdIn := SmartEscapeVarText(this.ui.Query("StdInCon"))
            if (ObjHasOwnProp(this.Data, "SaveNameArr"))
                this.Data.DeleteProp("SaveNameArr")
            enc := {}
            enc.In := this.ui.Query("EncIn")
            this.Data.Encoding := enc
        } else if (this.Data.Mode == 4) {
            this.Data.StdIn := SmartEscapeVarText(this.ui.Query("StdInCon"))
            this.Data.SaveNameArr := [this.ui.Query("SaveName1"), this.ui.Query("SaveName2"), this.ui.Query("SaveName3")]
            enc := {}
            enc.In := this.ui.Query("EncIn")
            enc.Out := this.ui.Query("EncOut")
            enc.Err := this.ui.Query("EncErr")
            this.Data.Encoding := enc
        }
        SaveMacroCMDData(this.Data)
    }

    OnClickAddVarNameBtn(state := "", ctrl := "", event := "") {
        target := this._ActiveEditTarget()
        this.InsertIntoEdit(target, this.ui.Query("VariCombo"))
    }

    OnClickAddVarValueBtn(state := "", ctrl := "", event := "") {
        if (this.ui.Query("VariCombo") != "") {
            target := this._ActiveEditTarget()
            this.InsertIntoEdit(target, "{" this.ui.Query("VariCombo") "}")
        }
    }

    _ActiveEditTarget() {
        ; ActiveEdit 是控件名（PathTextCon / StdInCon / StdInEditCon），只读/不可见时回退 PathTextCon
        name := this.ActiveEdit
        if (name == "StdInEditCon")
            return "StdInEditCon"
        if (name == "StdInCon" && IsObject(this.ui) && this.ui.Query("StdInCon>Visibility") == "Visible")
            return "StdInCon"
        return "PathTextCon"
    }

    InsertIntoEdit(target, text) {
        if (target == "StdInEditCon") {
            if (IsObject(this.StdInEditGui) && !this._stdInClosed) {
                this.StdInEditGui.Update("StdInEditCon", "InsertText", text)
                this.OnStdInEditChange()
            }
            return
        }
        if (IsObject(this.ui))
            this.ui.Update(target, "InsertText", text)
    }
}
