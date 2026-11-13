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
        this._posTarget := "PosVar"
        this._syncing := false   ; 程序初始化/刷新配置时抑制 SelectionChanged/Click 递归
        this._actionMode := -1   ; 动作下拉已构建的移动方式，避免每次 SelectionChanged 重建导致闪烁
    }

    ShowGui(cmd) {
        global MySoftData
        
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        this._actionMode := -1
        
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
        ShowMousePreviewButton(this.ui)
        this.ToggleFunc(true)
        
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

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
        title := this.ParentTile GetLang("移动Pro编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8,10,18")
        ; 为拖拽坐标预留行高，避免引擎首次测量后展开新行将确定按钮挤出窗口。
        body.Rows("32", "36", "36", "36", "36", "36", "36", "24", "40")
        body.Cols("90", "130", "110", "150")

        ; 行0：当前鼠标位置 + 备注（备注与坐标Y左对齐，输入右对齐下方下拉）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Grid_ColumnSpan(2).Name("MousePosCon")
            .Text(GetLang("当前鼠标位置:0,0")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBlock").Grid_Row(0).Grid_Column(2).Text(GetLang("备注：")).VerticalAlignment("Center").Margin("20,0,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(3).Name("RemarkCon").Height(26).MinHeight(26).Margin("-45,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：坐标基准 + 拟真轨迹
        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("坐标基准：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        ref := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("RefCombo").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for r in GetLangArr(["屏幕", "窗口"])
            ref.Add("ComboBoxItem").Content(r)
        body.Add("CheckBox").Grid_Row(1).Grid_Column(2).Grid_ColumnSpan(2).Name("HumanMouseTog")
            .Content(GetLang("拟真轨迹")).Margin("20,0,0,0").VerticalAlignment("Center")

        ; 行2：窗口信息（坐标基准=窗口时显示）
        winRow := body.Add("Grid").Name("WinInfoRow").Grid_Row(2).Grid_ColumnSpan(4).Visibility("Hidden")
        winRow.Cols("90", "130", "110", "150")
        winRow.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口绑定：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        winRow.Add("TextBox").Grid_Column(1).Grid_ColumnSpan(2).Name("WinInfoCon").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        winRow.Add("Button").Grid_Column(3).Name("BtnWinInfoEdit").Content(GetLang("编辑")).Height(26).MinHeight(26)
            .Margin("20,0,0,0").HorizontalAlignment("Left").VerticalAlignment("Center")

        ; 行3：移动方式 + 鼠标动作
        body.Add("TextBlock").Grid_Row(3).Grid_Column(0).Text(GetLang("移动方式：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        mm := body.Add("ComboBox").Grid_Row(3).Grid_Column(1).Name("MouseMoveModeCombo").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for m in GetLangArr(["绝对移动", "相对移动"])
            mm.Add("ComboBoxItem").Content(m)
        body.Add("TextBlock").Grid_Row(3).Grid_Column(2).Text(GetLang("鼠标动作：")).VerticalAlignment("Center").Margin("20,0,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        act := body.Add("ComboBox").Grid_Row(3).Grid_Column(3).Name("ActionTypeCombo").Height(26).MinHeight(26).Margin("20,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for a in GetLangArr(["移动", "移动后单击", "移动后双击", "拖拽", "A到B拖拽"])
            act.Add("ComboBoxItem").Content(a)

        ; 行4：坐标X/Y（绝对=坐标位置，相对=坐标偏移）
        body.Add("TextBlock").Grid_Row(4).Grid_Column(0).Name("PosXLabel").Text(GetLang("坐标位置X:")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(4).Grid_Column(1).Name("PosVarX").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("TextBlock").Grid_Row(4).Grid_Column(2).Name("PosYLabel").Text(GetLang("坐标位置Y:")).VerticalAlignment("Center").Margin("20,0,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(4).Grid_Column(3).Name("PosVarY").Width(130).HorizontalAlignment("Left").Height(26).MinHeight(26).Margin("20,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 绝对拖拽终止坐标；其他动作折叠此行。
        endRow := body.Add("Grid").Grid_Row(5).Grid_ColumnSpan(4).Name("EndPosRow").Visibility("Collapsed").Height(36)
        endRow.Cols("90", "130", "110", "150")
        endRow.Add("TextBlock").Grid_Column(0).Text(GetLang("终止点")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        endRow.Add("ComboBox").Grid_Column(1).Name("EndPosVarX").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        endRow.Add("TextBlock").Grid_Column(2).Text("").VerticalAlignment("Center").Margin("20,0,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        endRow.Add("ComboBox").Grid_Column(3).Name("EndPosVarY").Width(130).HorizontalAlignment("Left").Height(26).MinHeight(26).Margin("-90,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行5：移动速度
        spdHost := body.Add("Border").Grid_Row(6).Grid_Column(0).Background("Transparent").VerticalAlignment("Center")
            .ToolTip(GetLang("移动速度0~100，100为瞬移"))
        spdHost.Add("TextBlock").Text(GetLang("移动速度：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(6).Grid_Column(1).Name("SpeedCon").Height(26).MinHeight(26).VerticalContentAlignment("Center")
            .FontSize("11").Padding("4,0").Text("90")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行6：提示
        body.Add("TextBlock").Grid_Row(7).Grid_ColumnSpan(4).Text(GetLang("坐标基准=窗口时，坐标按所选窗口左上角偏移计算（绝对移动）。")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextSub}").FontSize("11")

        ; 行7：确定（水平居中）
        btnRow := body.Add("StackPanel").Grid_Row(8).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="520" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", this.OnWindowClosing.Bind(this, this.ui.id))
        this.ui.OnEvent("Window", "LoadedHwnd", this.OnWindowLoad.Bind(this, this.ui.id))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/6-移动Pro", ObjBindMethod(this, "TriggerMacro"), "!l", ObjBindMethod(this, "OnClickTargeterBtn"), ObjBindMethod(this, "SureMMPro"))
        this.ui.OnEvent("RefCombo", "SelectionChanged", ObjBindMethod(this, "OnRefChange"))
        this.ui.OnEvent("BtnWinInfoEdit", "Click", ObjBindMethod(this, "OnWinInfoEdit"))
        this.ui.OnEvent("MouseMoveModeCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("ActionTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        for field in ["PosVarX", "PosVarY"]
            this.ui.OnEvent(field, "GotKeyboardFocus", (*) => this._posTarget := "PosVar")
        for field in ["EndPosVarX", "EndPosVarY"]
            this.ui.OnEvent(field, "GotKeyboardFocus", (*) => this._posTarget := "EndPosVar")
        this.ui.OnEvent("HumanMouseTog", "Click", ObjBindMethod(this, "OnHumanMouseTogClick"))
        BindMouseMovePreview(this.ui, "pro")
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))

    }

    OnWindowLoad(id, *) {
        if (IsObject(this.ui) && this.ui.id == id)
            XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(id, *) {
        if (!IsObject(this.ui) || this.ui.id != id)
            return
        MouseMovePreview.Clear(this.ui)
        
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
        MouseMovePreview.Clear(this.ui)
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

    _TypeValue() {
        idx := this._SelIndex("ActionTypeCombo")
        items := this._MoveMode() == "相对移动"
            ? ["移动", "移动后单击", "移动后双击", "拖拽"]
            : ["移动", "移动后单击", "移动后双击", "拖拽", "A到B拖拽"]
        return CmdEnumFromIndex(idx, items, "移动")
    }
    _MoveMode() => CmdEnumFromIndex(this._SelIndex("MouseMoveModeCombo"), ["绝对移动", "相对移动"], "绝对移动")
    _RefMode() => CmdEnumFromIndex(this._SelIndex("RefCombo"), CmdEnumRefNames(), "屏幕")

    Init(cmd) {
        this._screenCoordinateItems := -1
        
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("移动Pro")
        
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        
        this.Data := GetMacroCMDData(this.SerialStr)

        
        this._RefreshActionItems(this.Data.ActionType)

        MoveMode := ObjHasOwnProp(this.Data, "MouseMoveMode") ? CmdEnumMoveMode(this.Data.MouseMoveMode) : "绝对移动"
        if (MoveMode == "游戏视角")
            MoveMode := "绝对移动"
        this.ui.Update("MouseMoveModeCombo", "SelectedIndex", String(MoveMode == "相对移动" ? 1 : 0))

        RefMode := ObjHasOwnProp(this.Data, "RefMode") ? this.Data.RefMode : "屏幕"
        this.ui.Update("RefCombo", "SelectedIndex", String(CmdEnumIndex(RefMode, CmdEnumRefNames(), 0)))
        this.ui.Update("WinInfoCon", "Text", ObjHasOwnProp(this.Data, "WinInfo") ? this.Data.WinInfo : "")
        this._RefreshCoordinateItems(true)
        this.OnRefChange()

        this.ui.Update("SpeedCon", "Text", this.Data.Speed)
        this.ui.Update("HumanMouseTog", "IsChecked", (ObjHasOwnProp(this.Data, "IsHumanMouse") ? this.Data.IsHumanMouse : 0) ? "True" : "False")

        this.OnTypeChange()
        this.OnHumanMouseTogClick()
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!this.CheckIfValid())
            return
        if (!IsNumber(this.ui.Query("PosVarX"))) {
            RmtDialog.Info(GetLang("坐标X是变量时，编辑模式下无法执行"))
            return
        }
        if (!IsNumber(this.ui.Query("PosVarY"))) {
            RmtDialog.Info(GetLang("坐标Y是变量时，编辑模式下无法执行"))
            return
        }
        if (this._TypeValue() == "A到B拖拽" && this._MoveMode() == "绝对移动"
            && (!IsNumber(this.ui.Query("EndPosVarX")) || !IsNumber(this.ui.Query("EndPosVarY")))) {
            RmtDialog.Info(GetLang("终止坐标是变量时，编辑模式下无法执行"))
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
        isWin := this._RefMode() == "窗口"
        this._RefreshCoordinateItems()
        this.ui.Update("WinInfoRow", "Visibility", isWin ? "Visible" : "Hidden")
    }

    ; §20 窗口信息编辑：复用 FrontInfoGui 选窗（标题/类名）
    OnWinInfoEdit(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        frontCtrl := CtrlAdapter("WinInfoCon", this.ui, "Text")
        MyFrontInfoGui.SureAction := () => this.OnRefChange()
        MyFrontInfoGui.ShowGui(frontCtrl)
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
        isRel := this._MoveMode() == "相对移动"
        this._RefreshCoordinateItems()
        action := this._TypeValue()
        isABDrag := action == "A到B拖拽" && !isRel
        isTargetPoint := !isRel && !isABDrag
        this._RefreshActionItems(action)
        this.ui.Update("EndPosRow", "Visibility", isABDrag ? "Visible" : "Collapsed")
        ; A 到 B 拖拽显示起点和终点；其他绝对移动统一显示目标点 X/Y。
        this.ui.Update("PosVarY", "Margin", "-90,0,0,0")
        if (!isABDrag && !isTargetPoint)
            this._posTarget := "PosVar"
        this.ui.Update("PosXLabel", "Text", GetLang(isRel ? "偏移值" : (isABDrag ? "起始点" : "目标点：")))
        this.ui.Update("PosYLabel", "Text", "")
    }

    _RefreshCoordinateItems(initial := false) {
        useScreen := this._MoveMode() == "绝对移动" && this._RefMode() != "窗口"
        if (this._screenCoordinateItems == useScreen)
            return
        this._screenCoordinateItems := useScreen
        for name in ["PosVarX", "PosVarY", "EndPosVarX", "EndPosVarY"] {
            items := useScreen ? GetGuiVarArr(StrLower(SubStr(name, -1))) : GetGuiVarArr()
            value := initial ? GetLang(this.Data.HasOwnProp(name) ? this.Data.%name% : 200) : this.ui.Query(name)
            this._SetCombo(name, items, value)
        }
    }

    _RefreshActionItems(action := "移动") {
        if (!IsObject(this.ui))
            return
        isRel := this._MoveMode() == "相对移动"
        modeKey := isRel ? 1 : 0
        items := isRel ? ["移动", "移动后单击", "移动后双击", "拖拽"] : ["移动", "移动后单击", "移动后双击", "拖拽", "A到B拖拽"]
        action := CmdEnumMMAction(action)
        if (isRel && action == "A到B拖拽")
            action := "拖拽"
        idx := 0
        for i, it in items
            if (it == action)
                idx := i - 1
        if (this._actionMode == modeKey) {
            if (this.ui.Query("ActionTypeCombo>SelectedIndex") != String(idx))
                this.ui.Update("ActionTypeCombo", "SelectedIndex", String(idx))
            return
        }
        this._actionMode := modeKey
        this._syncing := true
        try {
            this.ui.Update("ActionTypeCombo", "ClearItems", "")
            for it in GetLangArr(items)
                this.ui.Update("ActionTypeCombo", "AddItem", it)
            this.ui.Update("ActionTypeCombo", "SelectedIndex", String(idx))
        } finally {
            this._syncing := false
        }
    }

    OnSureTarget(PosX, PosY, Color) {
        if (IsObject(this.ui)) {
            this.ui.Update(this._posTarget "X", "Text", PosX)
            this.ui.Update(this._posTarget "Y", "Text", PosY)
        }
    }

    OnClickTargeterBtn(*) {
        ; 关闭路径预览/双点编辑，避免定位器打开期间旧 Timer 继续访问编辑器控件。
        MouseMovePreview.Clear(this.ui)
        MyTargetGui.ShowGui(XamlWin.BindCurrent(this, "OnSureTarget"))
    }

    OnClickTargeterHelpBtn(state := "", ctrl := "", event := "") {
        str := Format("{}`n{}`n{}", GetLang("1.左键拖拽改变位置"), GetLang("2.上下左右方向键微调位置"), GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"))
        RmtDialog.Info(str, GetLang("定位取色器操作说明"))
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

    SureMMPro(*) {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        if (!IsObject(this.ui))
            return
        if (this._MoveMode() == "相对移动") {
            curX := this.ui.Query("PosVarX")
            curY := this.ui.Query("PosVarY")
            curX := IsNumber(curX) ? Number(curX) : 0
            curY := IsNumber(curY) ? Number(curY) : 0
            mouseX := mouseX - curX
            mouseY := mouseY - curY
        }
        this.ui.Update(this._posTarget "X", "Text", mouseX)
        this.ui.Update(this._posTarget "Y", "Text", mouseY)
    }

    OnHumanMouseTogClick(state := "", ctrl := "", event := "") {
        if (this._syncing || !IsObject(this.ui))
            return
        isEnabled := this.ui.Query("HumanMouseTog") == "True"
        if (isEnabled) {
            if (this._MoveMode() == "游戏视角") {
                this.ui.Update("MouseMoveModeCombo", "SelectedIndex", "0")
                this.OnTypeChange()
            }
            if (this._TypeValue() != "移动")
                this.ui.Update("ActionTypeCombo", "SelectedIndex", "0")
            this.OnTypeChange()
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
        this.Data.EndPosVarX := GetLangKey(this.ui.Query("EndPosVarX"))
        this.Data.EndPosVarY := GetLangKey(this.ui.Query("EndPosVarY"))
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
