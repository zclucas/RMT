#Requires AutoHotkey v2.0
#Include WinRuleGui.ahk

; =====================================================================
; 移动Pro编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class MMProGui {
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
        this.PosAction := () => this.RefreshMousePos()
        this._syncing := false   ; 程序初始化/刷新配置时抑制 SelectionChanged/Click 递归
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
        title := this.ParentTile GetLang("鼠标移动Pro编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6")
        body.Rows("34", "30", "24", "32", "34", "32", "32", "24", "*")
        body.Cols("80", "130", "80", "130")

        ; 行0：快捷方式
        row0 := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        row0.Add("TextBox").Width(60).Height(24).MinHeight(24).Margin("4,0,0,0").Text("!l").IsReadOnly("True")
        row0.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(26).MinHeight(26).Margin("10,0,0,0")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(24).MinHeight(24).Margin("4,0,0,0")

        ; 行1：F1 + 定位取色器
        row1 := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("F1:选取当前坐标")).VerticalAlignment("Center")
        row1.Add("Button").Name("BtnTargeter").Content(GetLang("定位取色器")).Width(100).Height(26).MinHeight(26).Margin("14,0,0,0")
        row1.Add("Button").Name("BtnTargeterHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0")

        ; 行2：鼠标位置
        body.Add("TextBlock").Grid_Row(2).Grid_ColumnSpan(4).Name("MousePosCon").Text(GetLang("当前鼠标位置:0,0")).VerticalAlignment("Center")

        ; 行3：坐标位置X/Y
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("坐标位置X:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(1).Name("PosVarX").Height(26).MinHeight(26).IsEditable("True")
        body.Add("TextBlock").Grid_Row(3).Grid_Column(2).Text(GetLang("坐标位置Y:")).VerticalAlignment("Center")
        body.Add("ComboBox").Grid_Row(3).Grid_Column(3).Name("PosVarY").Height(26).MinHeight(26).IsEditable("True")

        ; 行4：移动速度 + 鼠标动作
        body.Add("TextBlock").Grid_Row(4).Grid_Column(0).Text(GetLang("移动速度：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(4).Grid_Column(1).Name("SpeedCon").Height(24).MinHeight(24).VerticalContentAlignment("Center").Text("90")
        body.Add("TextBlock").Grid_Row(4).Grid_Column(2).Text(GetLang("鼠标动作：")).VerticalAlignment("Center")
        act := body.Add("ComboBox").Grid_Row(4).Grid_Column(3).Name("ActionTypeCombo").Height(26).MinHeight(26)
        for a in GetLangArr(["移动", "移动点击1次", "移动点击2次"])
            act.Add("ComboBoxItem").Content(a)

        ; 行5：坐标基准（§20 屏幕/窗口）+ 移动模式（绝对/相对）+ 拟真轨迹
        row5 := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        row5.Add("TextBlock").Text(GetLang("坐标基准：")).VerticalAlignment("Center")
        ref := row5.Add("ComboBox").Name("RefCombo").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0")
        for r in GetLangArr(["屏幕", "窗口"])
            ref.Add("ComboBoxItem").Content(r)
        row5.Add("TextBlock").Text(GetLang("移动方式：")).VerticalAlignment("Center").Margin("14,0,0,0")
        mm := row5.Add("ComboBox").Name("MouseMoveModeCombo").Width(90).Height(26).MinHeight(26).Margin("4,0,0,0")
        for m in GetLangArr(["绝对移动", "相对移动"])
            mm.Add("ComboBoxItem").Content(m)
        row5.Add("CheckBox").Name("HumanMouseTog").Content(GetLang("启用拟真轨迹")).VerticalAlignment("Center").Margin("14,0,0,0")

        ; 行6：窗口信息（坐标基准=窗口时显示；标题/类名，可 FrontInfoGui 选窗）
        winRow := body.Add("StackPanel").Name("WinInfoRow").Grid_Row(6).Grid_ColumnSpan(4).Orientation("Horizontal").VerticalAlignment("Center")
        winRow.Add("TextBlock").Text(GetLang("窗口信息：")).VerticalAlignment("Center")
        winRow.Add("TextBox").Name("WinInfoCon").Width(240).Height(24).MinHeight(24).Margin("4,0,0,0").VerticalContentAlignment("Center")
        winRow.Add("Button").Name("BtnWinInfoEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("6,0,0,0")

        ; 行7：提示
        body.Add("TextBlock").Grid_Row(7).Grid_ColumnSpan(4).Text(GetLang("坐标基准=窗口时，坐标按所选窗口左上角偏移计算（绝对移动）。")).VerticalAlignment("Center")

        ; 行8：确定
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="500" Height="380" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("RefCombo", "SelectionChanged", ObjBindMethod(this, "OnRefChange"))
        this.ui.OnEvent("BtnWinInfoEdit", "Click", ObjBindMethod(this, "OnWinInfoEdit"))
        this.ui.OnEvent("MouseMoveModeCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("HumanMouseTog", "Click", ObjBindMethod(this, "OnHumanMouseTogClick"))
        this.ui.OnEvent("BtnTargeter", "Click", ObjBindMethod(this, "OnClickTargeterBtn"))
        this.ui.OnEvent("BtnTargeterHelp", "Click", ObjBindMethod(this, "OnClickTargeterHelpBtn"))
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
        ; 先关窗（PostMessage WM_CLOSE），再清理——任何清理异常都不阻断关闭
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

    _SelIndex(comboName) {
        v := IsObject(this.ui) ? this.ui.Query(comboName ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    _TypeValue() => this._SelIndex("ActionTypeCombo") + 1
    _MoveMode() => this._SelIndex("MouseMoveModeCombo")
    _RefMode() => this._SelIndex("RefCombo")

    Init(cmd) {
        
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("鼠标移动Pro")
        
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()

        
        this._SetCombo("PosVarX", this.DLVariableArr, GetLang(this.Data.PosVarX))
        this._SetCombo("PosVarY", this.DLVariableArr, GetLang(this.Data.PosVarY))
        this.ui.Update("ActionTypeCombo", "SelectedIndex", String(this.Data.ActionType - 1))

        MoveMode := 0
        if (ObjHasOwnProp(this.Data, "MouseMoveMode"))
            MoveMode := this.Data.MouseMoveMode
        ; §20 旧配置兼容：旧「游戏视角」(值2) 在下拉只剩 绝对/相对 时回退为绝对移动（执行端仍兼容旧值）
        if (MoveMode > 1)
            MoveMode := 0
        this.ui.Update("MouseMoveModeCombo", "SelectedIndex", String(MoveMode))

        RefMode := ObjHasOwnProp(this.Data, "RefMode") ? Integer(this.Data.RefMode) : 0
        this.ui.Update("RefCombo", "SelectedIndex", String(RefMode))
        this.ui.Update("WinInfoCon", "Text", ObjHasOwnProp(this.Data, "WinInfo") ? this.Data.WinInfo : "")

        this.ui.Update("SpeedCon", "Text", this.Data.Speed)
        this.ui.Update("HumanMouseTog", "IsChecked", (ObjHasOwnProp(this.Data, "IsHumanMouse") ? this.Data.IsHumanMouse : 0) ? "True" : "False")

        this.OnTypeChange()
        this.OnHumanMouseTogClick()
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        if (!IsNumber(this.ui.Query("PosVarX"))) {
            MsgBox(GetLang("坐标X是变量时，编辑模式下无法执行"))
            return
        }
        if (!IsNumber(this.ui.Query("PosVarY"))) {
            MsgBox(GetLang("坐标Y是变量时，编辑模式下无法执行"))
            return
        }
        this.SaveMMProData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    ; §20 坐标基准切换：选「窗口」时显示窗口信息编辑行
    OnRefChange(state := "", ctrl := "", event := "") {
        if (this._syncing || !IsObject(this.ui))
            return
        isWin := this._RefMode() == 1
        this.ui.Update("WinInfoRow", "Visibility", isWin ? "Visible" : "Collapsed")
    }

    ; §20 窗口信息编辑：复用 FrontInfoGui 选窗（标题/类名）
    OnWinInfoEdit(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        frontCtrl := CtrlAdapter("WinInfoCon", this.ui, "Text")
        MyFrontInfoGui.SureAction := () => this.OnRefChange()
        MyFrontInfoGui.ShowGui(frontCtrl, true)
    }

    CheckIfValid() {
        return true
    }

    RefreshMousePos() {
        
        if (!IsObject(this.ui))
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.ui.Update("MousePosCon", "Text", Format("{}{},{}", GetLang("当前鼠标位置:"), mouseX, mouseY))
        
    }

    ToggleFunc(state) {
        ; 全部 try/catch：任何热键/定时器异常都不能阻断开关流程（否则窗口无法关闭）
        if (state) {
            try SetTimer this.PosAction, 100
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
            try Hotkey("F1", (*) => this.SureMMPro(), "On")
        }
        else {
            try SetTimer this.PosAction, 0
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
            try Hotkey("F1", (*) => this.SureMMPro(), "Off")
        }
    }

    OnTypeChange(state := "", ctrl := "", event := "") {
        if (this._syncing || !IsObject(this.ui))
            return
        ; §20 移动模式仅剩 绝对/相对（旧「游戏视角」已拆为增量移动指令），无需联动禁用
    }

    OnSureTarget(PosX, PosY, Color) {
        if (IsObject(this.ui)) {
            this.ui.Update("PosVarX", "Text", PosX)
            this.ui.Update("PosVarY", "Text", PosY)
        }
    }

    OnClickTargeterBtn(state := "", ctrl := "", event := "") {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(state := "", ctrl := "", event := "") {
        str := Format("{}`n{}`n{}", GetLang("1.左键拖拽改变位置"), GetLang("2.上下左右方向键微调位置"), GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"))
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnClickSureBtn(state, ctrl, event) {
        
        if (!this.CheckIfValid())
            return
        this.SaveMMProData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()           ; 先关窗，回调即使抛异常也不阻断关闭
        if (action != "")
            action(CommandStr)
    }

    SureMMPro() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        if (IsObject(this.ui)) {
            this.ui.Update("PosVarX", "Text", mouseX)
            this.ui.Update("PosVarY", "Text", mouseY)
        }
    }

    OnHumanMouseTogClick(state := "", ctrl := "", event := "") {
        if (this._syncing || !IsObject(this.ui))
            return
        isEnabled := this.ui.Query("HumanMouseTog") == "True"
        if (isEnabled) {
            if (this._MoveMode() == 2) {
                this.ui.Update("MouseMoveModeCombo", "SelectedIndex", "0")
                this.OnTypeChange()
            }
            if (this._TypeValue() != 1)
                this.ui.Update("ActionTypeCombo", "SelectedIndex", "0")
            this.ui.Update("ActionTypeCombo", "IsEnabled", "False")
            this.ui.Update("MouseMoveModeCombo", "IsEnabled", "False")
        }
        else {
            this.ui.Update("ActionTypeCombo", "IsEnabled", "True")
            this.ui.Update("MouseMoveModeCombo", "IsEnabled", "True")
        }
    }

    SaveMMProData() {
        this.Data.PosVarX := GetLangKey(this.ui.Query("PosVarX"))
        this.Data.PosVarY := GetLangKey(this.ui.Query("PosVarY"))
        this.Data.ActionType := this._TypeValue()
        this.Data.MouseMoveMode := this._MoveMode()
        ; §20 坐标基准 + 窗口信息
        this.Data.RefMode := this._RefMode()
        this.Data.WinInfo := GetLangKey(this.ui.Query("WinInfoCon"))
        this.Data.Speed := this.ui.Query("SpeedCon")
        this.Data.IsHumanMouse := this.ui.Query("HumanMouseTog") == "True" ? 1 : 0
        SaveMacroCMDData(this.Data)
    }
}
