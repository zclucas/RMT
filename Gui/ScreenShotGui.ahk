#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk
#Include WinRuleGui.ahk

; =====================================================================
; 抓图编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class ScreenShotGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.PosAction := () => this.RefreshMouseInfo()
        this.F1Action := (x1, y1, x2, y2) => this.OnF1SetAreaAction(x1, y1, x2, y2)
        this.Data := ""
        this.SerialStr := ""
        this.MacroGui := ""
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
        title := this.ParentTile GetLang("抓图编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "30", "34", "34", "34", "34", "Auto", "*")
        body.Cols("90", "120", "100", "130")

        ; 行0：快捷方式 + 执行指令 + 备注
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：F1 框选 + 坐标
        row1 := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBox").Width(25).Height(22).MinHeight(22).Text("F1").IsReadOnly("True")
        row1.Add("CheckBox").Name("SelectToggle").Content(GetLang("左键框选截图范围")).VerticalAlignment("Center").Margin("4,0,0,0")
        row1.Add("TextBlock").Name("MousePosCon").Text(GetLang("屏幕坐标：0,0")).VerticalAlignment("Center").Margin("12,0,0,0")
        row1.Add("TextBlock").Name("MouseWinPosCon").Text(GetLang("窗口坐标：0,0")).VerticalAlignment("Center").Margin("12,0,0,0")

        ; 行2：抓图类型 + 固定名称
        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("抓图类型：")).VerticalAlignment("Center")
        st := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("ScreenShotTypeCombo").Height(26).MinHeight(26)
        st.Add("ComboBoxItem").Content(GetLang("屏幕抓图")).Tag("1")
        st.Add("ComboBoxItem").Content(GetLang("窗口抓图")).Tag("2")
        body.Add("CheckBox").Grid_Row(2).Grid_Column(2).Name("NameType").Content(GetLang("固定名称：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(2).Grid_Column(3).Name("FixedNameCon").Height(24).MinHeight(24).VerticalContentAlignment("Center")

        ; 行3：窗口信息
        winRow := body.Add("StackPanel").Name("WinInfoRow").Grid_Row(3).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        winRow.Add("TextBlock").Text(GetLang("窗口信息:")).VerticalAlignment("Center").Width(75)
        winRow.Add("TextBox").Name("WinInfoCon").Width(275).Height(24).MinHeight(24)
        winRow.Add("Button").Name("BtnWinEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行4-5：起始/终止坐标
        body.Add("TextBlock").Grid_Row(4).Grid_Column(0).Text(GetLang("起始坐标X：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(4).Grid_Column(1).Name("StartPosX").Height(26).MinHeight(26).IsEditable("True")
        body.Add("TextBlock").Grid_Row(4).Grid_Column(2).Text(GetLang("起始坐标Y：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(4).Grid_Column(3).Name("StartPosY").Height(26).MinHeight(26).IsEditable("True")
        body.Add("TextBlock").Grid_Row(5).Grid_Column(0).Text(GetLang("终止坐标X：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(5).Grid_Column(1).Name("EndPosX").Height(26).MinHeight(26).IsEditable("True")
        body.Add("TextBlock").Grid_Row(5).Grid_Column(2).Text(GetLang("终止坐标Y：")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(5).Grid_Column(3).Name("EndPosY").Height(26).MinHeight(26).IsEditable("True")

        ; 行6：结果保存 GroupBox
        rGroup := body.Add("GroupBox").Name("ResultGroup").Grid_Row(6).Grid_ColumnSpan(4).Header(GetLang("结果保存"))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,2,0,2")
        r := rGroup.Add("Grid").Margin("10,6")
        r.Cols("30", "*")
        r.Rows("30")
        r.Add("CheckBox").Grid_Row(0).Grid_Column(0).Name("ResultToggle").VerticalAlignment("Center")
        r.Add("ComboBox").Grid_Row(0).Grid_Column(1).Name("ResultSaveNameCombo").Width(200).Height(24).MinHeight(24).HorizontalAlignment("Left").IsEditable("True")

        ; 行7：确定
        btnRow := body.Add("StackPanel").Grid_Row(7).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" Height="360" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("ScreenShotTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("NameType", "Click", ObjBindMethod(this, "OnChangeNameType"))
        this.ui.OnEvent("ResultToggle", "Click", ObjBindMethod(this, "OnChangeResultToggle"))
        this.ui.OnEvent("SelectToggle", "Click", ObjBindMethod(this, "OnClickSelectToggle"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        try this.ToggleFunc(false)
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

    _ShotType() {
        v := IsObject(this.ui) ? this.ui.Query("ScreenShotTypeCombo") : ""
        return IsNumber(v) ? Integer(v) : 1
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("抓图")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        if (!this.CheckIfDataValid())
            return

        this.ui.Update("ScreenShotTypeCombo", "SelectedIndex", String(this.Data.ScreenShotType - 1))
        this.ui.Update("WinInfoCon", "Text", this.Data.WinInfo)
        this._SetCombo("StartPosX", this.DLVariableArr, this.Data.StartPosX)
        this._SetCombo("StartPosY", this.DLVariableArr, this.Data.StartPosY)
        this._SetCombo("EndPosX", this.DLVariableArr, this.Data.EndPosX)
        this._SetCombo("EndPosY", this.DLVariableArr, this.Data.EndPosY)
        this.ui.Update("NameType", "IsChecked", this.Data.NameType ? "True" : "False")
        this.ui.Update("FixedNameCon", "Text", this.Data.FixedName)
        this.ui.Update("ResultToggle", "IsChecked", this.Data.ResultToggle ? "True" : "False")
        this._SetCombo("ResultSaveNameCombo", this.DLVariableArr, this.Data.ResultSaveName)

        this.OnChangeType()
        this.OnChangeNameType()
        this.OnChangeResultToggle()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    OnClickWinEditBtn(state := "", ctrl := "", event := "") {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    CheckIfDataValid() {
        return true
    }

    CheckIfValid() {
        isWin := this._ShotType() == 2
        if (IsNumber(this.ui.Query("StartPosX")) && IsNumber(this.ui.Query("StartPosY")) && IsNumber(this.ui.Query("EndPosX")) && IsNumber(this.ui.Query("EndPosY"))) {
            if (Number(this.ui.Query("StartPosX")) > Number(this.ui.Query("EndPosX")) || Number(this.ui.Query("StartPosY")) > Number(this.ui.Query("EndPosY"))) {
                MsgBox(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }
        if (isWin && this.ui.Query("WinInfoCon") == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }
        if (this.ui.Query("NameType") == "True" && this.ui.Query("FixedNameCon") == "") {
            MsgBox(GetLang("固定名称不能为空"))
            return false
        }
        if (this.ui.Query("ResultToggle") == "True") {
            if (!CheckVarNameIfValid(this.ui.Query("ResultSaveNameCombo")))
                return false
        }
        return true
    }

    ToggleFunc(state) {
        if (state) {
            try SetTimer this.PosAction, 100
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
            try Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            try SetTimer this.PosAction, 0
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
            try Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    RefreshMouseInfo() {
        if (!IsObject(this.ui))
            return
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            this.ui.Update("MousePosCon", "Text", Format("{}{},{}", GetLang("屏幕坐标："), mouseX, mouseY))
            PosArr := GetCurWinPos()
            this.ui.Update("MouseWinPosCon", "Text", Format("{}{},{}", GetLang("窗口坐标："), PosArr[1], PosArr[2]))
        }
    }

    OnChangeType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        isWin := this._ShotType() == 2
        this.ui.Update("WinInfoRow", "IsEnabled", isWin ? "True" : "False")
    }

    OnChangeNameType(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this.ui.Update("FixedNameCon", "IsEnabled", (this.ui.Query("NameType") == "True") ? "True" : "False")
    }

    OnChangeResultToggle(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        isSave := this.ui.Query("ResultToggle") == "True"
        this.ui.Update("ResultSaveNameCombo", "IsEnabled", isSave ? "True" : "False")
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnClickSelectToggle(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        state := this.ui.Query("SelectToggle") == "True"
        if (state)
            TogSelectArea(true, this.F1Action)
        else
            TogSelectArea(false)
    }

    OnF1() {
        if (IsObject(this.ui))
            this.ui.Update("SelectToggle", "IsChecked", "True")
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        if (!IsObject(this.ui))
            return
        this.ui.Update("SelectToggle", "IsChecked", "False")
        curType := this._ShotType()
        isWin := curType == 2
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]
        this.ui.Update("StartPosX", "Text", Point1[1])
        this.ui.Update("StartPosY", "Text", Point1[2])
        this.ui.Update("EndPosX", "Text", Point2[1])
        this.ui.Update("EndPosY", "Text", Point2[2])
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this.ToggleFunc(false)
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    SaveData() {
        data := this.Data
        data.ScreenShotType := this._ShotType()
        data.WinInfo := this.ui.Query("WinInfoCon")
        data.StartPosX := this.ui.Query("StartPosX")
        data.StartPosY := this.ui.Query("StartPosY")
        data.EndPosX := this.ui.Query("EndPosX")
        data.EndPosY := this.ui.Query("EndPosY")
        data.NameType := this.ui.Query("NameType") == "True" ? 1 : 0
        data.FixedName := this.ui.Query("FixedNameCon")
        data.ResultToggle := this.ui.Query("ResultToggle") == "True" ? 1 : 0
        data.ResultSaveName := GetVarName(this.ui.Query("ResultSaveNameCombo"))
        if (data.ResultToggle)
            MySoftData.GlobalVariMap[data.ResultSaveName] := true
        SaveMacroCMDData(data)
    }
}
