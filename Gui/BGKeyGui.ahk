#Requires AutoHotkey v2.0

; =====================================================================
; 后台按键编辑器 —— XAML 迁移版（独立实现，照 KeyGui 模式）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 与 KeyGui 差异：仅键盘键位（无鼠标/手柄）；多窗口信息(FrontCon)+备注(RemarkCon)；跳过悬停高亮
; =====================================================================

class BGKeyGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true

        this.SerialStr := ""
        this.Data := ""

        this.CheckedArr := []
        this.ConMap := Map()          ; key → 按键按钮控件名
        this._btnKeyMap := Map()      ; 控件名 → key
        this._keySeq := 0

        this.TriggerAction := (*) => this.TriggerMacro()

        this.SelectColor := "#19C930"
        this.UnSelectColor := "{DynamicResource InputBg}"
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
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)
        this.Refresh()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        ; 实例复用：重建前清空按键映射，避免 _btnKeyMap/_keySeq 累积导致事件重复绑定
        this.ConMap := Map()
        this._btnKeyMap := Map()
        this._keySeq := 0
        title := this.ParentTile GetLang("后台按键编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "30", "30", "*", "34", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 顶部行1：模拟/检测/窗口信息 ===
        top := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").Margin("10,4")
        top.Add("Button").Name("BtnSim").Content(GetLang("模拟指令")).Width(80).Height(26).MinHeight(26).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
        top.Add("Button").Name("BtnHelp").Content("?").Width(30).Height(26).MinHeight(26).Margin("4,0,0,0").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1").Padding("0")
        top.Add("TextBlock").Text(GetLang("键盘按键检测：")).VerticalAlignment("Center").Margin("10,0,0,0")
        top.Add("TextBox").Name("HotkeyCon").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        top.Add("Button").Name("BtnDetect").Content(GetLang("确定")).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")
        top.Add("TextBlock").Text(GetLang("窗口信息:")).VerticalAlignment("Center").Margin("12,0,0,0")
        top.Add("TextBox").Name("FrontCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        top.Add("Button").Name("BtnEdit").Content(GetLang("编辑")).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")

        ; === 顶部行2：备注 ===
        remarkRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,2")
        remarkRow.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
        remarkRow.Add("TextBox").Name("RemarkCon").Width(400).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; === 按键网格 ===
        keyGroup := main.Add("GroupBox").Grid_Row(3).Header(GetLang("请从下面按钮中选择按键：")).Margin("8,2,8,4")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}")
            .ClipToBounds("True")
        sv := keyGroup.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").ClipToBounds("True")
        this._keyGrid := sv.Add("Canvas").Width("1240").Height("270")

        ; === 底部参数行 ===
        bottom := main.Add("StackPanel").Grid_Row(4).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        bottom.Add("TextBlock").Text(GetLang("类型:")).VerticalAlignment("Center")
        kt := bottom.Add("ComboBox").Name("KeyTypeCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["按下", "松开", "点击"])
            kt.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Name("HoldTimeTipCon").Text(GetLang("点击时长:")).VerticalAlignment("Center").Margin("15,0,0,0")
        bottom.Add("TextBox").Name("HoldTimeCon").Width(60).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("KeyCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").Margin("15,0,0,0")
        bottom.Add("TextBox").Name("KeyCountCon").Width(60).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("PerIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("15,0,0,0")
        bottom.Add("TextBox").Name("PerIntervalCon").Width(60).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; === 底部按钮行 ===
        btnRow := main.Add("StackPanel").Grid_Row(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 生成按键网格（加入 main，随后 main.ToString() 生效）===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1280" Height="470" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件（ui 已建）===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnSim", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnClickHelpBtn"))
        this.ui.OnEvent("BtnDetect", "Click", ObjBindMethod(this, "OnSureHotkey"))
        this.ui.OnEvent("BtnEdit", "Click", ObjBindMethod(this, "OnClickEditBtn"))
        this.ui.OnEvent("KeyTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("HoldTimeCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("KeyCountCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("PerIntervalCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

        ; 类型默认「点击」
        this.ui.Update("KeyTypeCon", "SelectedIndex", "2")

    }

    ; ---------------- 按键网格（Canvas 绝对定位，复刻键盘布局）----------------

    _PlaceKey(value, display, x, y, width) {
        this._keySeq += 1
        name := "KeyBtn_" this._keySeq
        btn := this._keyGrid.Add("Button").Name(name).Width(width).Height(25)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .Content(display).FontSize(11).Cursor("Hand").Padding("2,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        this.ConMap.Set(value, name)
        this._btnKeyMap.Set(name, value)
    }

    _AddKeyRow(keys, y) {
        for item in keys {
            this._PlaceKey(item[1], item[2], item[3], y, item[4])
        }
    }

    _BuildKeyGrid() {
        this._AddKeyRow([
            ["Esc","Esc",20,40],["F1","F1",120,35],["F2","F2",170,35],["F3","F3",220,35],["F4","F4",270,35],
            ["F5","F5",345,35],["F6","F6",395,35],["F7","F7",445,35],["F8","F8",495,35],
            ["F9","F9",570,35],["F10","F10",620,35],["F11","F11",670,35],["F12","F12",720,35],
            ["PrintScreen","PrtScr",795,45],["ScrollLock","Scroll",870,45],["Pause","Pause",945,45]], 20)
        this._AddKeyRow([
            ["``","~",20,35],["1","1",70,35],["2","2",120,35],["3","3",170,35],["4","4",220,35],
            ["5","5",270,35],["6","6",320,35],["7","7",370,35],["8","8",420,35],["9","9",470,35],
            ["0","0",520,35],["-","-",570,35],["=","=",620,35],["BS","Backspace",670,85],
            ["Ins","Ins",795,45],["Home","Home",870,45],["PgUp","PgUp",945,45],
            ["NumLock","Num",1045,35],["NumpadDiv","/",1095,35],["NumpadMult","*",1145,35],["NumpadSub","-",1195,35]], 50)
        this._AddKeyRow([
            ["Tab","Tab",20,60],["q","Q",100,35],["w","W",150,35],["e","E",200,35],["r","R",250,35],
            ["t","T",300,35],["y","Y",350,35],["u","U",400,35],["i","I",450,35],["o","O",500,35],
            ["p","P",550,35],["[","[",600,35],["]","]",650,35],["\","\",705,50],
            ["Del","Del",795,45],["End","End",870,45],["PgDn","PgDn",945,45],
            ["Numpad7","7",1045,35],["Numpad8","8",1095,35],["Numpad9","9",1145,35],["NumpadAdd","+",1195,35]], 80)
        this._AddKeyRow([
            ["CapsLock","CapsLock",20,75],["a","A",120,35],["s","S",170,35],["d","D",220,35],["f","F",270,35],
            ["g","G",320,35],["h","H",370,35],["j","J",420,35],["k","K",470,35],["l","L",520,35],
            [";",";",570,35],["'","'",620,35],["Enter","Enter",680,75],
            ["Numpad4","4",1045,35],["Numpad5","5",1095,35],["Numpad6","6",1145,35]], 110)
        this._AddKeyRow([
            ["LShift","LShift",20,85],["z","Z",130,35],["x","X",180,35],["c","C",230,35],["v","V",280,35],
            ["b","B",330,35],["n","N",380,35],["m","M",430,35],["逗号",",",480,35],[".",".",530,35],
            ["/","/",580,35],["RShift","RShift",670,85],["Up","↑",870,45],
            ["Numpad1","1",1045,35],["Numpad2","2",1095,35],["Numpad3","3",1145,35],["NumpadEnter","Enter",1195,35]], 140)
        this._AddKeyRow([
            ["LCtrl","LCtrl",20,60],["LWin","LWin",95,60],["LAlt","LAlt",170,60],["Space","Space",245,210],
            ["RAlt","RAlt",470,60],["RWin","RWin",545,60],["AppsKey","AppsKey",620,60],["RCtrl","RCtrl",695,60],
            ["Left","←",795,45],["Down","↓",870,45],["Right","→",945,45],["Numpad0","0",1045,35],["NumpadDot","Del",1145,35]], 170)
        this._AddKeyRow([
            ["Ctrl","Ctrl",20,60],["Shift","Shift",95,60],["Alt","Alt",170,60],
            ["Browser_Back",GetLang("后退"),245,60],["Browser_Forward",GetLang("前进"),320,60],
            ["Browser_Refresh",GetLang("刷新"),395,60],["Browser_Stop",GetLang("停止"),470,60],
            ["Browser_Search",GetLang("搜索"),545,60],["Browser_Favorites",GetLang("收藏夹"),620,60],
            ["Browser_Home",GetLang("主页"),695,60],["Volume_Mute",GetLang("静音"),770,60],
            ["Volume_Down",GetLang("调低音量"),845,60],["Volume_Up",GetLang("增加音量"),920,60],
            ["Bright_Down",GetLang("降低亮度"),1028,60],["Bright_Up",GetLang("提高亮度"),1103,60]], 200)
        this._AddKeyRow([
            ["Launch_App1",GetLang("此电脑"),20,60],["Launch_App2",GetLang("计算器"),95,60],
            ["Media_Next",GetLang("下一首"),170,60],["Media_Prev",GetLang("上一首"),245,60],
            ["Media_Stop",GetLang("停止"),320,60],["Media_Play_Pause",GetLang("播放/暂停"),395,80]], 230)
    }

    _RegisterKeyEvents() {
        for name, value in this._btnKeyMap
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnCheckedKey").Bind(value))
    }

    ; ---------------- 选项相关 ----------------

    OnCheckedKey(key, *) {
        isSelected := false
        arrayIndex := 0
        con := this.ConMap.Get(key)

        for index, value in this.CheckedArr {
            if (value == key) {
                isSelected := true
                arrayIndex := index
                break
            }
        }

        if (isSelected) {
            this.ui.Update(con, "Background", this.UnSelectColor)
            this.CheckedArr.RemoveAt(arrayIndex)
        }
        else {
            this.ui.Update(con, "Background", this.SelectColor)
            this.CheckedArr.Push(key)
        }

        this.Refresh()
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.UnSelectColor)
        }
        this.CheckedArr := []
        this.Refresh()
    }

    RefreshCheckCon() {
        for key, name in this.ConMap
            this.ui.Update(name, "Background", this.UnSelectColor)

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.SelectColor)
        }
    }

    OnSureHotkey(state, ctrl, event) {
        triggerKey := this.ui.Query("HotkeyCon")
        triggerKey := StrReplace(triggerKey, ",", "逗号")
        triggerKey := StrReplace(triggerKey, "Insert", "Ins")
        this.CheckedArr := GetComboKeyArr(triggerKey)
        this.RefreshCheckCon()
        this.Refresh()
    }

    OnClickEditBtn(*) {
        if (MainSoftData.IsModalSubGui && this.Hwnd() != 0) {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "FrontCon"))
    }

    ; ---------------- 数据 ----------------

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("后台按键")
        this.Data := GetMacroCMDData(this.SerialStr)

        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.ui.Update("FrontCon", "Text", this.Data.FrontStr)
        this.CheckedArr := this.Data.KeyArr
        this.ui.Update("KeyTypeCon", "SelectedIndex", String(this.Data.Type - 1))
        this.ui.Update("HoldTimeCon", "Text", this.Data.ClickTime)
        this.ui.Update("KeyCountCon", "Text", this.Data.ClickCount)
        this.ui.Update("PerIntervalCon", "Text", this.Data.ClickInterval)

        this.RefreshCheckCon()
        this.Refresh()
    }

    _KeyTypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("KeyTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 3   ; 默认 点击
        return Integer(v) + 1
    }

    Refresh() {
        isShowHoldTime := this._KeyTypeIndex() == 3
        isShowCount := isShowHoldTime
        isShowInterval := isShowCount && this.ui.Query("KeyCountCon") != 1

        this.ui.Update("HoldTimeTipCon", "Visibility", isShowHoldTime ? "Visible" : "Collapsed")
        this.ui.Update("HoldTimeCon", "Visibility", isShowHoldTime ? "Visible" : "Collapsed")
        this.ui.Update("KeyCountTipCon", "Visibility", isShowCount ? "Visible" : "Collapsed")
        this.ui.Update("KeyCountCon", "Visibility", isShowCount ? "Visible" : "Collapsed")
        this.ui.Update("PerIntervalTipCon", "Visibility", isShowInterval ? "Visible" : "Collapsed")
        this.ui.Update("PerIntervalCon", "Visibility", isShowInterval ? "Visible" : "Collapsed")
    }

    OnChangeEditValue(state, ctrl, event) {
        this.Refresh()
    }

    CheckIfValid() {
        if (this.ui.Query("FrontCon") == "" || this.ui.Query("FrontCon") == "⎖⎖⎖") {
            MsgBox(GetLang("请编辑窗口信息"))
            return false
        }

        if (this.CheckedArr == "" || this.CheckedArr.Length == 0) {
            MsgBox(GetLang("请选择按键！"))
            return false
        }

        if (!IsInteger(this.ui.Query("KeyCountCon")) || Integer(this.ui.Query("KeyCountCon")) <= 0) {
            MsgBox(GetLang("按键次数必须为大于零的整数！"))
            return false
        }

        return true
    }

    SaveBGKeyData() {
        this.Data.FrontStr := this.ui.Query("FrontCon")
        this.Data.KeyArr := this.CheckedArr
        this.Data.Type := this._KeyTypeIndex()
        this.Data.ClickTime := this.ui.Query("HoldTimeCon")
        this.Data.ClickCount := this._KeyTypeIndex() == 3 ? this.ui.Query("KeyCountCon") : 1
        this.Data.ClickInterval := this.ui.Query("PerIntervalCon")

        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    OnSureBtnClick(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveBGKeyData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.OnGuiClose()
    }

    TriggerMacro(*) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveBGKeyData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    ToggleFunc(state) {
        if (state) {
            Hotkey("F1", this.TriggerAction, "On")
        }
        else {
            Hotkey("F1", this.TriggerAction, "Off")
        }
    }

    OnClickHelpBtn(*) {
        str1 := GetLang("该指令需要管理员身份运行软件")
        str2 := GetLang("该指令部分窗口可能无效")
        str3 := GetLang("tip1:可通过对浏览器界面配置检测指令的正确性")
        str4 := GetLang("tip2:若浏览器界面正常，实际窗口无效，那就是该窗口不支持后台功能")
        str := Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
        MsgBox(str, GetLang("后台操作说明"))
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
