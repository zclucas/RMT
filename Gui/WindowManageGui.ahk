#Requires AutoHotkey v2.0
#Include WinRuleGui.ahk

; =====================================================================
; 窗口管理编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile / Hwnd()
; 数据流：GetMacroCMDData / SaveMacroCMDData / this.Data.* 与原生一致
; 联动：操作类型下拉切换 坐标/大小/标题/透明度 行显隐（原生 OnActionChange 等价迁移）
; =====================================================================

class WindowManageGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.MyFrontInfoGui := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this._syncing := false
        this.Data := ""
        this.SerialStr := ""

        this.ActionTypeArr := [
            GetLang("激活窗口"), GetLang("最大化窗口"), GetLang("最小化窗口"), GetLang("还原窗口"), GetLang("关闭窗口"),
            GetLang("移动窗口"), GetLang("调整大小"), GetLang("置顶窗口"), GetLang("取消置顶"), GetLang("修改标题"),
            GetLang("修改透明度"), GetLang("开启鼠标穿透"), GetLang("关闭鼠标穿透"), GetLang("获取窗口信息")
        ]
        ; 显隐联动行容器名（OnActionChange 用，对应原生 RelateArrCon 控件组）
        this.PosRelateArrCon := ["PosRelateRow"]
        this.SizeRelateArrCon := ["SizeRelateRow"]
        this.TitleRelateArrCon := ["TitleRelateRow"]
        this.TransparencyRelateArrCon := ["TransparencyRelateRow"]
        this.GetInfoRelateArrCon := ["GetInfoRelateRow"]
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
        this._syncing := true
        this._batching := true
        try {
            this.Init(cmd)
            this.OnActionChange()
        } finally {
            this._flushBatch()
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

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
        title := this.ParentTile GetLang("窗口管理编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("16,8,16,36")
        body.Rows("36", "36", "Auto", "48")
        body.Cols("108", "*", "16", "80", "*")

        ; 行0：操作类型 + 备注（白底，内边距与下拉框一致）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("操作类型：")).VerticalAlignment("Center")
        act := body.Add("ComboBox").Grid_Row(0).Grid_Column(1).Name("ActionTypeCon").Height(26).MinHeight(26).VerticalAlignment("Center")
        for t in this.ActionTypeArr
            act.Add("ComboBoxItem").Content(t)
        body.Add("TextBlock").Grid_Row(0).Grid_Column(3).Text(GetLang("备注：")).VerticalAlignment("Center")
        body.Add("TextBox").Grid_Row(0).Grid_Column(4).Name("RemarkCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：窗口信息
        wiRow := body.Add("Grid").Grid_Row(1).Grid_ColumnSpan(5)
        wiRow.Cols("108", "*", "8", "70")
        wiRow.Add("TextBlock").Grid_Column(0).Text(GetLang("窗口绑定:")).VerticalAlignment("Center")
        wiRow.Add("TextBox").Grid_Column(1).Name("SearchValueCon").Height(26).MinHeight(26).MaxHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        wiRow.Add("Button").Grid_Column(3).Name("WinInfoEditBtn").Content(GetLang("编辑")).Height(26).MinHeight(26).VerticalAlignment("Center")

        ; 行2：按操作类型顺序展开的附加项（Collapsed 后不占位）
        extra := body.Add("StackPanel").Grid_Row(2).Grid_ColumnSpan(5)

        posRow := extra.Add("Grid").Name("PosRelateRow").Visibility("Collapsed")
        posRow.Rows("36")
        posRow.Cols("108", "*", "16", "108", "*")
        posRow.Add("TextBlock").Grid_Column(0).Text(GetLang("坐标X：")).VerticalAlignment("Center")
        posRow.Add("ComboBox").Grid_Column(1).Name("PosXCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        posRow.Add("TextBlock").Grid_Column(3).Text(GetLang("坐标Y：")).VerticalAlignment("Center")
        posRow.Add("ComboBox").Grid_Column(4).Name("PosYCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        sizeRow := extra.Add("Grid").Name("SizeRelateRow").Visibility("Collapsed")
        sizeRow.Rows("36")
        sizeRow.Cols("108", "*", "16", "108", "*")
        sizeRow.Add("TextBlock").Grid_Column(0).Text(GetLang("宽度：")).VerticalAlignment("Center")
        sizeRow.Add("ComboBox").Grid_Column(1).Name("WidthCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")
        sizeRow.Add("TextBlock").Grid_Column(3).Text(GetLang("高度：")).VerticalAlignment("Center")
        sizeRow.Add("ComboBox").Grid_Column(4).Name("HeightCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        titleRow := extra.Add("Grid").Name("TitleRelateRow").Visibility("Collapsed")
        titleRow.Rows("36")
        titleRow.Cols("108", "*", "16", "108", "*")
        titleRow.Add("TextBlock").Grid_Column(0).Text(GetLang("新标题：")).VerticalAlignment("Center")
        titleRow.Add("ComboBox").Grid_Column(1).Grid_ColumnSpan(4).Name("NewTitleCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        transRow := extra.Add("Grid").Name("TransparencyRelateRow").Visibility("Collapsed")
        transRow.Rows("36")
        transRow.Cols("108", "*", "16", "108", "*")
        transRow.Add("TextBlock").Grid_Column(0).Text(GetLang("透明度：")).VerticalAlignment("Center")
        transRow.Add("ComboBox").Grid_Column(1).Name("TransparencyCon").Height(26).MinHeight(26).IsEditable("True").VerticalAlignment("Center")

        ; 获取窗口信息：四个接收变量（左上角 X/Y、宽/高）压缩在**一行**。
        ; 重要：窗口用 SizeToContent="Height"，只在开窗时测量一次，展开高度超出预留就会把下方「确定」按钮挤出可视区，
        ; 所以这里必须和其它操作类型一样只占一行（36），不能拆成两行。
        getInfoRow := extra.Add("Grid").Name("GetInfoRelateRow").Visibility("Collapsed")
        getInfoRow.Rows("36")
        getInfoRow.Cols("70", "14", "*", "6", "14", "*", "6", "14", "*", "6", "14", "*")
        getInfoRow.Add("TextBlock").Grid_Column(0).Text(GetLang("存入变量：")).VerticalAlignment("Center")
        ; ToolTip 必须用「完整句子」做键：中文下 GetLang 直接原样返回传入的键，传短键会把键名显示给用户
        this._AddVarSlot(getInfoRow, 1, "X", "GetPosXVarCon", GetLang("获取窗口信息X存入提示：窗口左上角的 X 坐标写入该变量，留空则不获取"))
        this._AddVarSlot(getInfoRow, 4, "Y", "GetPosYVarCon", GetLang("获取窗口信息Y存入提示：窗口左上角的 Y 坐标写入该变量，留空则不获取"))
        this._AddVarSlot(getInfoRow, 7, "W", "GetWidthVarCon", GetLang("获取窗口信息宽度存入提示：窗口宽度写入该变量，留空则不获取"))
        this._AddVarSlot(getInfoRow, 10, "H", "GetHeightVarCon", GetLang("获取窗口信息高度存入提示：窗口高度写入该变量，留空则不获取"))

        ; 行3：确定
        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="540" SizeToContent="Height" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/23-窗口管理", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("ActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnActionChange"))
        this.ui.OnEvent("WinInfoEditBtn", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))

    }

    ; ---------------- 数据填充辅助 ----------------

    _SetCombo(comboName, items, text) {
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        this._ComboPush(comboName, "Text", text)
    }

    SetConArrState(ConArr, isEnabled, state) {
        prop := isEnabled ? "IsEnabled" : "Visibility"
        val := isEnabled ? (state ? "True" : "False") : (state ? "Visible" : "Collapsed")
        for name in ConArr
            this._ComboPush(name, prop, val)
    }

    ; 旧配置保存的 WindowManageData 没有「获取窗口信息」的变量名字段，按空处理避免报错
    _DataField(name, defaultValue := "") {
        return (IsObject(this.Data) && this.Data.HasOwnProp(name)) ? this.Data.%name% : defaultValue
    }

    ; 单行内的「标签 + 变量下拉」一格：labelCol 放标签，labelCol+1 放下拉
    _AddVarSlot(rowGrid, labelCol, label, comboName, tip) {
        rowGrid.Add("TextBlock").Grid_Column(labelCol).Text(label).VerticalAlignment("Center")
            .HorizontalAlignment("Center")
        rowGrid.Add("ComboBox").Grid_Column(labelCol + 1).Name(comboName).Height(26).MinHeight(26)
            .IsEditable("True").VerticalAlignment("Center").ToolTip(tip)
    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVariableArr := GetGuiVarArr()
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("窗口管理")
        this._ComboPush("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        ; 操作类型：按 GetLangKey 匹配选中项（兼容非中文语言）；无匹配保持未选中（与原生 DDL.Text 行为一致）
        actIdx := -1
        for i, it in this.ActionTypeArr {
            if (GetLangKey(it) == this.Data.ActionType) {
                actIdx := i - 1
                break
            }
        }
        this._ComboPush("ActionTypeCon", "SelectedIndex", String(actIdx))
        this._ComboPush("SearchValueCon", "Text", this.Data.SearchValue)
        this._SetCombo("PosXCon", DLVariableArr, this.Data.PosX)
        this._SetCombo("PosYCon", DLVariableArr, this.Data.PosY)
        this._SetCombo("WidthCon", DLVariableArr, this.Data.Width)
        this._SetCombo("HeightCon", DLVariableArr, this.Data.Height)
        this._SetCombo("NewTitleCon", DLVariableArr, this.Data.NewTitle)
        this._SetCombo("TransparencyCon", DLVariableArr, this.Data.Transparency)
        this._SetCombo("GetPosXVarCon", DLVariableArr, this._DataField("GetPosXVar"))
        this._SetCombo("GetPosYVarCon", DLVariableArr, this._DataField("GetPosYVar"))
        this._SetCombo("GetWidthVarCon", DLVariableArr, this._DataField("GetWidthVar"))
        this._SetCombo("GetHeightVarCon", DLVariableArr, this._DataField("GetHeightVar"))
        ; 透明度：原生在变量项之后追加 0%~100% 列表
        for p in ["0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"]
            this._ComboPush("TransparencyCon", "AddItem", p)
    }

    OnActionChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this._syncing && state != ""))
            return
        ; 同步阶段 Query 可能尚未生效，改用 Data；加载后 SelectionChanged 再按控件值刷新
        if (this._syncing && IsObject(this.Data) && this.Data.ActionType != "")
            actionType := GetLang(this.Data.ActionType)
        else
            actionType := this.ui.Query("ActionTypeCon")
        isShowPos := (actionType == GetLang("移动窗口"))
        isShowSize := (actionType == GetLang("调整大小"))
        isShowTitle := (actionType == GetLang("修改标题"))
        isShowTransparency := (actionType == GetLang("修改透明度"))
        isShowGetInfo := (actionType == GetLang("获取窗口信息"))

        this.SetConArrState(this.PosRelateArrCon, false, isShowPos)
        this.SetConArrState(this.SizeRelateArrCon, false, isShowSize)
        this.SetConArrState(this.TitleRelateArrCon, false, isShowTitle)
        this.SetConArrState(this.TransparencyRelateArrCon, false, isShowTransparency)
        this.SetConArrState(this.GetInfoRelateArrCon, false, isShowGetInfo)
    }

    CheckIfValid() {
        actionType := IsObject(this.ui) ? this.ui.Query("ActionTypeCon") : ""
        if (this.ui.Query("SearchValueCon") == "") {
            RmtDialog.Info(GetLang("窗口绑定不能为空"))
            return false
        }

        if (actionType == GetLang("修改标题")) {
            if (this.ui.Query("NewTitleCon") == "") {
                RmtDialog.Info(GetLang("新标题不能为空！"), "", "Owner" this.Hwnd())
                return false
            }
        }

        return true
    }

    SaveData() {
        this.Data.ActionType := GetLangKey(this.ui.Query("ActionTypeCon"))
        this.Data.SearchValue := this.ui.Query("SearchValueCon")
        this.Data.PosX := this.ui.Query("PosXCon")
        this.Data.PosY := this.ui.Query("PosYCon")
        this.Data.Width := this.ui.Query("WidthCon")
        this.Data.Height := this.ui.Query("HeightCon")
        this.Data.NewTitle := this.ui.Query("NewTitleCon")
        this.Data.Transparency := StrReplace(this.ui.Query("TransparencyCon"), "%")
        this.Data.GetPosXVar := this.ui.Query("GetPosXVarCon")
        this.Data.GetPosYVar := this.ui.Query("GetPosYVarCon")
        this.Data.GetWidthVar := this.ui.Query("GetWidthVarCon")
        this.Data.GetHeightVar := this.ui.Query("GetHeightVarCon")
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)
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

    OnClickSureBtn(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveData()
        this.ToggleFunc(false)
        action := this.SureBtnAction
        if (action != "")
            action(this.GetCommandStr())
        this.OnGuiClose()
    }

    OnClickWinEditBtn(state := "", ctrl := "", event := "") {
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "SearchValueCon"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        this._syncing := false
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
