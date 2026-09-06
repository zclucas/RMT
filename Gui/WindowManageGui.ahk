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

        this.ActionTypeArr := [
            GetLang("激活窗口"), GetLang("最大化窗口"), GetLang("最小化窗口"), GetLang("还原窗口"), GetLang("关闭窗口"),
            GetLang("移动窗口"), GetLang("调整大小"), GetLang("置顶窗口"), GetLang("取消置顶"), GetLang("修改标题"),
            GetLang("修改透明度"), GetLang("开启鼠标穿透"), GetLang("关闭鼠标穿透")
        ]
        ; 显隐联动行容器名（OnActionChange 用，对应原生 RelateArrCon 控件组）
        this.PosRelateArrCon := ["PosRelateRow"]
        this.SizeRelateArrCon := ["SizeRelateRow"]
        this.TitleRelateArrCon := ["TitleRelateRow"]
        this.TransparencyRelateArrCon := ["TransparencyRelateRow"]
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
        this.OnActionChange()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("窗口管理编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "32", "32", "34", "30", "30", "30", "30", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 快捷方式 / 执行指令 / 备注 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        top.Add("TextBlock").Text(GetLang("快捷方式：")).VerticalAlignment("Center")
        top.Add("TextBox").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0").Text("!l").IsReadOnly("True").VerticalContentAlignment("Center").FontSize(11).Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        top.Add("Button").Name("BtnExecute").Content(GetLang("执行指令")).Height(28).MinHeight(28).Padding("14,0").Margin("14,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Margin("14,0,0,0")
        top.Add("TextBox").Name("RemarkCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").VerticalContentAlignment("Center").FontSize(11).Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 操作类型 ===
        atRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        atRow.Add("TextBlock").Text(GetLang("操作类型：")).VerticalAlignment("Center")
        act := atRow.Add("ComboBox").Name("ActionTypeCon").Width(200).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in this.ActionTypeArr
            act.Add("ComboBoxItem").Content(t)

        ; === 窗口信息 ===
        wiRow := main.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        wiRow.Add("TextBlock").Text(GetLang("窗口信息:")).VerticalAlignment("Center").Width(75)
        wiRow.Add("TextBox").Name("SearchValueCon").Width(340).Height(26).MinHeight(26).Margin("4,0,0,0").VerticalContentAlignment("Center").FontSize(11).Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        wiRow.Add("Button").Name("WinInfoEditBtn").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")

        ; === 移动窗口：坐标X / 坐标Y ===
        posRow := main.Add("StackPanel").Name("PosRelateRow").Grid_Row(4).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        posRow.Add("TextBlock").Text(GetLang("坐标X：")).VerticalAlignment("Center").Width(70)
        posRow.Add("ComboBox").Name("PosXCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        posRow.Add("TextBlock").Text(GetLang("坐标Y：")).VerticalAlignment("Center").Width(70).Margin("20,0,0,0")
        posRow.Add("ComboBox").Name("PosYCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 调整大小：宽度 / 高度 ===
        sizeRow := main.Add("StackPanel").Name("SizeRelateRow").Grid_Row(5).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        sizeRow.Add("TextBlock").Text(GetLang("宽度：")).VerticalAlignment("Center").Width(70)
        sizeRow.Add("ComboBox").Name("WidthCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        sizeRow.Add("TextBlock").Text(GetLang("高度：")).VerticalAlignment("Center").Width(70).Margin("20,0,0,0")
        sizeRow.Add("ComboBox").Name("HeightCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 修改标题：新标题 ===
        titleRow := main.Add("StackPanel").Name("TitleRelateRow").Grid_Row(6).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        titleRow.Add("TextBlock").Text(GetLang("新标题：")).VerticalAlignment("Center").Width(70)
        titleRow.Add("ComboBox").Name("NewTitleCon").Width(340).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 修改透明度：透明度 ===
        transRow := main.Add("StackPanel").Name("TransparencyRelateRow").Grid_Row(7).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        transRow.Add("TextBlock").Text(GetLang("透明度：")).VerticalAlignment("Center").Width(70)
        transRow.Add("ComboBox").Name("TransparencyCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize(11).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(8).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="560" Height="310" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnExecute", "Click", ObjBindMethod(this, "TriggerMacro"))
        this.ui.OnEvent("ActionTypeCon", "SelectionChanged", ObjBindMethod(this, "OnActionChange"))
        this.ui.OnEvent("WinInfoEditBtn", "Click", ObjBindMethod(this, "OnClickWinEditBtn"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))

    }

    ; ---------------- 数据填充辅助 ----------------

    _SetCombo(comboName, items, text) {
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    SetConArrState(ConArr, isEnabled, state) {
        prop := isEnabled ? "IsEnabled" : "Visibility"
        val := isEnabled ? (state ? "True" : "False") : (state ? "Visible" : "Collapsed")
        for name in ConArr
            this.ui.Update(name, prop, val)
    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVariableArr := GetGuiVarArr()
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("窗口管理")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)

        ; 操作类型：按 GetLangKey 匹配选中项（兼容非中文语言）；无匹配保持未选中（与原生 DDL.Text 行为一致）
        actIdx := -1
        for i, it in this.ActionTypeArr {
            if (GetLangKey(it) == this.Data.ActionType) {
                actIdx := i - 1
                break
            }
        }
        this.ui.Update("ActionTypeCon", "SelectedIndex", String(actIdx))
        this.ui.Update("SearchValueCon", "Text", this.Data.SearchValue)
        this._SetCombo("PosXCon", DLVariableArr, this.Data.PosX)
        this._SetCombo("PosYCon", DLVariableArr, this.Data.PosY)
        this._SetCombo("WidthCon", DLVariableArr, this.Data.Width)
        this._SetCombo("HeightCon", DLVariableArr, this.Data.Height)
        this._SetCombo("NewTitleCon", DLVariableArr, this.Data.NewTitle)
        this._SetCombo("TransparencyCon", DLVariableArr, this.Data.Transparency)
        ; 透明度：原生在变量项之后追加 0%~100% 列表
        for p in ["0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"]
            this.ui.Update("TransparencyCon", "AddItem", p)
    }

    OnActionChange(*) {
        ; Query 在窗口未加载时返回空串：空串与任何 GetLang 均不相等，行全部收起；
        ; 加载后程序化 SelectedIndex 触发的 SelectionChanged 会再跑一次修正（同 SearchProGui.OnChangeType）
        actionType := IsObject(this.ui) ? this.ui.Query("ActionTypeCon") : ""
        isShowPos := (actionType == GetLang("移动窗口"))
        isShowSize := (actionType == GetLang("调整大小"))
        isShowTitle := (actionType == GetLang("修改标题"))
        isShowTransparency := (actionType == GetLang("修改透明度"))

        this.SetConArrState(this.PosRelateArrCon, false, isShowPos)
        this.SetConArrState(this.SizeRelateArrCon, false, isShowSize)
        this.SetConArrState(this.TitleRelateArrCon, false, isShowTitle)
        this.SetConArrState(this.TransparencyRelateArrCon, false, isShowTransparency)
    }

    CheckIfValid() {
        actionType := IsObject(this.ui) ? this.ui.Query("ActionTypeCon") : ""
        if (this.ui.Query("SearchValueCon") == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (actionType == GetLang("修改标题")) {
            if (this.ui.Query("NewTitleCon") == "") {
                MsgBox(GetLang("新标题不能为空！"), "", "Owner" this.Hwnd())
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
