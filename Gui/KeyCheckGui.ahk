#Requires AutoHotkey v2.0

; =====================================================================
; 按键检测编辑器 —— XAML 迁移版（独立实现，照 KeyGui 模式）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 与 KeyGui 差异：无模拟/F1；底部为检测模式/检测类型/结果变量；跳过悬停高亮
; =====================================================================

class KeyCheckGui {
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
        this.KeyStr := ""

        this.CheckedArr := []
        this.ConMap := Map()          ; key → 按键按钮控件名
        this._btnKeyMap := Map()      ; 控件名 → key
        this._keySeq := 0

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
        title := this.ParentTile GetLang("按键检测")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "34", "44")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 按键网格（GroupBox + ScrollViewer）===
        keyGroup := main.Add("GroupBox").Grid_Row(1).Header(GetLang("请从下面按钮中选择要检测的按键：")).Margin("8,2,8,4")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}")
            .ClipToBounds("True")
        sv := keyGroup.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").ClipToBounds("True")
        this._keyGrid := sv.Add("Canvas").Width("1240").Height("410")

        ; === 底部参数行 ===
        bottom := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        bottom.Add("TextBlock").Text(GetLang("检测模式:")).VerticalAlignment("Center")
        cc := bottom.Add("ComboBox").Name("CheckTypeCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["同时按下", "有一个按下"])
            cc.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Text(GetLang("检测类型:")).VerticalAlignment("Center").Margin("20,0,0,0")
        st := bottom.Add("ComboBox").Name("StateTypeCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(["物理状态", "逻辑状态"])
            st.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Text(GetLang("结果变量：")).VerticalAlignment("Center").Margin("20,0,0,0")
        bottom.Add("ComboBox").Name("VarNameCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")

        ; === 底部按钮行 ===
        btnRow := main.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0").Cursor("Hand")

        ; === 生成按键网格 ===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1280" Height="555" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件 ===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

    }

    ; ---------------- 按键网格（Canvas 绝对定位，复刻 KeyGui 键盘+鼠标+手柄布局）----------------

    _PlaceLabel(text, x, y) {
        this._keyGrid.Add("TextBlock").Text(text).FontWeight("SemiBold").FontSize(12)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
    }

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
        global MySoftData
        this._PlaceLabel(GetLang("键盘"), 20, 0)
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

        this._PlaceLabel(GetLang("鼠标"), 20, 260)
        this._AddKeyRow([
            ["LButton",GetLang("左键"),20,60],["MButton",GetLang("中键"),95,60],["RButton",GetLang("右键"),170,60],
            ["WheelDown",GetLang("下滚轮"),245,60],["WheelUp",GetLang("上滚轮"),320,60],
            ["WheelLeft",GetLang("滚轮左键"),395,60],["WheelRight",GetLang("滚轮右键"),470,60],
            ["XButton1",GetLang("侧键1"),545,60],["XButton2",GetLang("侧键2"),620,60]], 280)

        this._PlaceLabel(GetLang("手柄-按键"), 20, 310)
        this._AddKeyRow([
            ["JoyA",MySoftData.GetJoyDisplayName("JoyA"),20,60],["JoyB",MySoftData.GetJoyDisplayName("JoyB"),95,60],
            ["JoyX",MySoftData.GetJoyDisplayName("JoyX"),170,60],["JoyY",MySoftData.GetJoyDisplayName("JoyY"),245,60],
            ["JoyLB",MySoftData.GetJoyDisplayName("JoyLB"),320,60],["JoyRB",MySoftData.GetJoyDisplayName("JoyRB"),395,60],
            ["JoyLT",MySoftData.GetJoyDisplayName("JoyLT"),470,60],["JoyRT",MySoftData.GetJoyDisplayName("JoyRT"),545,60],
            ["JoyLS",MySoftData.GetJoyDisplayName("JoyLS"),620,60],["JoyRS",MySoftData.GetJoyDisplayName("JoyRS"),695,60],
            ["JoyBack",MySoftData.GetJoyDisplayName("JoyBack"),770,60],["JoyStart",MySoftData.GetJoyDisplayName("JoyStart"),845,60],
            ["JoyHome",MySoftData.GetJoyDisplayName("JoyHome"),920,60],["JoyPad",MySoftData.GetJoyDisplayName("JoyPad"),995,60]], 330)

        this._PlaceLabel(GetLang("手柄-方向键、摇杆"), 20, 360)
        this._AddKeyRow([
            ["JoyDpadUp",GetLang("上"),20,60],["JoyDpadDown",GetLang("下"),95,60],
            ["JoyDpadLeft",GetLang("左"),170,60],["JoyDpadRight",GetLang("右"),245,60],
            ["JoyDpadNone",GetLang("无方向"),320,60],["JoyAxisLXMin","LXMin",395,60],["JoyAxisLXMax","LXMax",470,60],
            ["JoyAxisLYMin","LYMin",545,60],["JoyAxisLYMax","LYMax",620,60],["JoyAxisRXMin","RXMin",695,60],
            ["JoyAxisRXMax","RXMax",770,60],["JoyAxisRYMin","RYMin",845,60],["JoyAxisRYMax","RYMax",920,60]], 380)
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
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.UnSelectColor)
        }
        this.CheckedArr := []
    }

    GetTriggerKey() {
        triggerKey := ""
        for index, value in this.CheckedArr {
            triggerKey .= value "⎖"
        }
        triggerKey := RTrim(triggerKey, "⎖")
        return triggerKey
    }

    RefreshCheckCon(KeyArrStr) {
        this.CheckedArr := GetPressKeyArr(KeyArrStr)

        for key, name in this.ConMap
            this.ui.Update(name, "Background", this.UnSelectColor)

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.SelectColor)
        }

        this.UpdateJoyBtnDisplay()
    }

    UpdateJoyBtnDisplay() {
        global MySoftData
        joyBtnKeys := ["JoyA", "JoyB", "JoyX", "JoyY", "JoyLB", "JoyRB", "JoyLT", "JoyRT",
            "JoyLS", "JoyRS", "JoyBack", "JoyStart", "JoyPad", "JoyHome"]
        for key in joyBtnKeys {
            if (this.ConMap.Has(key))
                this.ui.Update(this.ConMap[key], "Content", MySoftData.GetJoyDisplayName(key))
        }
    }

    ; ---------------- 数据 ----------------

    _SetCombo(comboName, items, text) {
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("按键检测")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        this.KeyStr := ""
        if (this.Data.KeyArr.Length > 0) {
            for k in this.Data.KeyArr
                this.KeyStr .= k "⎖"
            this.KeyStr := RTrim(this.KeyStr, "⎖")
        }
        if (cmdArr.Length >= 2)
            this.KeyStr := cmdArr[2]

        this.ui.Update("CheckTypeCon", "SelectedIndex", String((this.Data.CheckType ? this.Data.CheckType : 1) - 1))
        this.ui.Update("StateTypeCon", "SelectedIndex", String((this.Data.StateType ? this.Data.StateType : 1) - 1))
        this._SetCombo("VarNameCon", this.DLVariableArr, this.Data.VarName != "" ? this.Data.VarName : "Var1")

        this.RefreshCheckCon(this.KeyStr)
    }

    CheckIfValid() {
        this.KeyStr := this.GetTriggerKey()
        if (this.KeyStr == "") {
            MsgBox(GetLang("请选择要检测的按键！"))
            return false
        }

        varName := Trim(this.ui.Query("VarNameCon"))
        if (varName == "") {
            MsgBox(GetLang("请输入变量名！"))
            return false
        }

        return true
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        return CommandStr
    }

    SaveKeyCheckData() {
        data := this.Data
        data.KeyArr := this.CheckedArr.Clone()
        data.CheckType := IsObject(this.ui) ? (Integer(this.ui.Query("CheckTypeCon>SelectedIndex")) + 1) : 1
        data.StateType := IsObject(this.ui) ? (Integer(this.ui.Query("StateTypeCon>SelectedIndex")) + 1) : 1
        data.VarName := GetVarName(this.ui.Query("VarNameCon"))
        MySoftData.GlobalVariMap[data.VarName] := true

        SaveMacroCMDData(data)
    }

    OnSureBtnClick(state, ctrl, event) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveKeyCheckData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.OnGuiClose()
    }

    ToggleFunc(state) {
        ; 无 F1 热键；悬停高亮已跳过（桥接无通用 MouseEnter/MouseLeave）
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
