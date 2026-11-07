#Requires AutoHotkey v2.0

; =====================================================================
; 按键编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class KeyGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true

        this.CheckedArr := []
        this.ConMap := Map()          ; key → 按键按钮控件名
        this._btnKeyMap := Map()      ; 控件名 → key
        this._keySeq := 0

        this.TriggerAction := (*) => this.TriggerMacro()

        this.SelectColor := "{DynamicResource ActionBg}"
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
        title := this.ParentTile GetLang("按键编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("4,2,4,8")
        body.Rows("Auto", "Auto", "Auto", "48")
        body.Cols("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "*")

        ; 行0：按键网格
        sv := body.Add("ScrollViewer").Grid_Row(0).Grid_ColumnSpan(11).Margin("0,4,0,0")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").ClipToBounds("True")
        kbHost := sv.Add("Grid")
        this._keyGrid := kbHost.Add("Canvas").Width("1109").Height("270").HorizontalAlignment("Center").VerticalAlignment("Top")

        ; 行1：鼠标（居中，上收贴近键盘）
        mouseBlock := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(11).HorizontalAlignment("Center").Margin("0,5,0,2")
        mouseBlock.Add("TextBlock").Text(GetLang("鼠标")).FontWeight("SemiBold").FontSize(12)
            .HorizontalAlignment("Center").Foreground("{DynamicResource TextMain}").Margin("0,0,0,6")
        mouseKeys := mouseBlock.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
        mouseDefs := [
            ["LButton", GetLang("左键"), 60], ["MButton", GetLang("中键"), 60], ["RButton", GetLang("右键"), 60],
            ["WheelDown", GetLang("下滚轮"), 60], ["WheelUp", GetLang("上滚轮"), 60],
            ["WheelLeft", GetLang("滚轮左键"), 70], ["WheelRight", GetLang("滚轮右键"), 70],
            ["XButton1", GetLang("侧键1"), 60], ["XButton2", GetLang("侧键2"), 60]]
        loop mouseDefs.Length {
            this._PlaceFlowKey(mouseKeys, mouseDefs[A_Index][1], mouseDefs[A_Index][2], mouseDefs[A_Index][3], A_Index < mouseDefs.Length)
        }

        ; 行2：类型/时长/次数/间隔固定居中；当前指令单独一行，左对齐类型 label
        optWrap := body.Add("Grid").Grid_Row(2).Grid_ColumnSpan(11).HorizontalAlignment("Center").Margin("10,12,10,2")
        optWrap.Rows("Auto", "Auto")
        bottom := optWrap.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").HorizontalAlignment("Left").VerticalAlignment("Center")
        typeBox := bottom.Add("StackPanel").Name("TypeBox").Orientation("Horizontal").VerticalAlignment("Center").ToolTip(this._TypeHelpText())
        typeBox.Add("TextBlock").Text(GetLang("类型:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        kt := typeBox.Add("ComboBox").Name("KeyTypeCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["按下", "松开", "点击"])
            kt.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Name("HoldTimeTipCon").Text(GetLang("点击时长:")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("HoldTimeCon").Width(60).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .Tag("NumOnly|NoIME|MaxLen:5")
        bottom.Add("TextBlock").Name("KeyCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("KeyCountCon").Width(60).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .Tag("NumOnly|NoIME|MaxLen:5")
        bottom.Add("TextBlock").Name("PerIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("PerIntervalCon").Width(60).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .Tag("NumOnly|NoIME|MaxLen:5")
        optWrap.Add("TextBlock").Name("CommandStrCon").Grid_Row(1).Text(GetLang("当前指令：无"))
            .HorizontalAlignment("Left").VerticalAlignment("Center").Margin("0,8,0,0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行3：底部按钮行
        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(11).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        clearBtn := btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(88).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
            .Margin("0,0,300,0")
        clearBtn.InjectResources(FrontInfoGui._OkBtnHoverStyle())
        AddCmdOkBtn(btnRow, "BtnOk")

        ; === 生成按键网格（加入 body，随后 main.ToString() 生效）===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1130" Height="500"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件（ui 已建）===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/2-按键", ObjBindMethod(this, "TriggerMacro"), "F1")
        this.ui.OnEvent("KeyTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("HoldTimeCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("KeyCountCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("PerIntervalCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

        ; 类型初始值
        this.ui.Update("KeyTypeCon", "SelectedIndex", "2")   ; 默认 点击

    }

    ; ---------------- 按键网格（Canvas 绝对定位，复刻原版键盘布局）----------------

    _PlaceLabel(text, x, y) {
        this._keyGrid.Add("TextBlock").Text(text).FontWeight("SemiBold").FontSize(12)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
    }

    _SetKeyBtnState(con, selected) {
        this.ui.Update(con, "Background", selected ? this.SelectColor : this.UnSelectColor)
        this.ui.Update(con, "Tag", selected ? "1" : "0")
    }

    _PlaceKey(value, display, x, y, width) {
        this._keySeq += 1
        name := "KeyBtn_" this._keySeq
        btn := this._keyGrid.Add("Button").Name(name).Width(width).Height(25)
            .SetProp("Canvas.Left", String(x - 10)).SetProp("Canvas.Top", String(y))
            .Content(display).FontSize(11).Cursor("Hand").Padding("2,0").Tag("0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        btn.InjectResources(FrontInfoGui._KeyPickBtnStyle())
        this.ConMap.Set(value, name)
        this._btnKeyMap.Set(name, value)
    }

    _AddKeyRow(keys, y) {
        for item in keys {
            value := item[1]
            display := item[2]
            x := item[3]
            width := item[4]
            this._PlaceKey(value, display, x, y, width)
        }
    }

    _PlaceFlowKey(parent, value, display, width, hasGap) {
        this._keySeq += 1
        name := "KeyBtn_" this._keySeq
        btn := parent.Add("Button").Name(name).Width(width).Height(25)
            .Content(display).FontSize(11).Cursor("Hand").Padding("2,0").Tag("0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        btn.InjectResources(FrontInfoGui._KeyPickBtnStyle())
        if (hasGap)
            btn.Margin("0,0,15,0")
        this.ConMap.Set(value, name)
        this._btnKeyMap.Set(name, value)
    }

    _BuildKeyGrid() {
        nx := 768, nw := 45, ng := 8
        n1 := nx, n2 := nx + nw + ng, n3 := nx + 2 * (nw + ng)
        px := n3 + nw + 14, pw := 35, pg := 12
        p1 := px, p2 := px + pw + pg, p3 := px + 2 * (pw + pg), p4 := px + 3 * (pw + pg)

        this._AddKeyRow([
            ["F13","F13",120,35],["F14","F14",170,35],["F15","F15",220,35],["F16","F16",270,35],
            ["F17","F17",345,35],["F18","F18",395,35],["F19","F19",445,35],["F20","F20",495,35],
            ["F21","F21",570,35],["F22","F22",620,35],["F23","F23",670,35],["F24","F24",720,35]], 0)
        this._AddKeyRow([
            ["Esc","Esc",20,40],["F1","F1",120,35],["F2","F2",170,35],["F3","F3",220,35],["F4","F4",270,35],
            ["F5","F5",345,35],["F6","F6",395,35],["F7","F7",445,35],["F8","F8",495,35],
            ["F9","F9",570,35],["F10","F10",620,35],["F11","F11",670,35],["F12","F12",720,35],
            ["PrintScreen","PrtScr",n1,nw],["ScrollLock","Scroll",n2,nw],["Pause","Pause",n3,nw]], 30)
        this._AddKeyRow([
            ["``","~",20,35],["1","1",70,35],["2","2",120,35],["3","3",170,35],["4","4",220,35],
            ["5","5",270,35],["6","6",320,35],["7","7",370,35],["8","8",420,35],["9","9",470,35],
            ["0","0",520,35],["-","-",570,35],["=","=",620,35],["BS","Backspace",670,85],
            ["Ins","Ins",n1,nw],["Home","Home",n2,nw],["PgUp","PgUp",n3,nw],
            ["NumLock","Num",p1,pw],["NumpadDiv","/",p2,pw],["NumpadMult","*",p3,pw],["NumpadSub","-",p4,pw]], 60)
        this._AddKeyRow([
            ["Tab","Tab",20,60],["q","Q",100,35],["w","W",150,35],["e","E",200,35],["r","R",250,35],
            ["t","T",300,35],["y","Y",350,35],["u","U",400,35],["i","I",450,35],["o","O",500,35],
            ["p","P",550,35],["[","[",600,35],["]","]",650,35],["\","\",705,50],
            ["Del","Del",n1,nw],["End","End",n2,nw],["PgDn","PgDn",n3,nw],
            ["Numpad7","7",p1,pw],["Numpad8","8",p2,pw],["Numpad9","9",p3,pw],["NumpadAdd","+",p4,pw]], 90)
        this._AddKeyRow([
            ["CapsLock","CapsLock",20,75],["a","A",120,35],["s","S",170,35],["d","D",220,35],["f","F",270,35],
            ["g","G",320,35],["h","H",370,35],["j","J",420,35],["k","K",470,35],["l","L",520,35],
            [";",";",570,35],["'","'",620,35],["Enter","Enter",680,75],
            ["Numpad4","4",p1,pw],["Numpad5","5",p2,pw],["Numpad6","6",p3,pw]], 120)
        this._AddKeyRow([
            ["LShift","LShift",20,85],["z","Z",130,35],["x","X",180,35],["c","C",230,35],["v","V",280,35],
            ["b","B",330,35],["n","N",380,35],["m","M",430,35],["逗号",",",480,35],[".",".",530,35],
            ["/","/",580,35],["RShift","RShift",670,85],["Up","↑",n2,nw],
            ["Numpad1","1",p1,pw],["Numpad2","2",p2,pw],["Numpad3","3",p3,pw],["NumpadEnter","Enter",p4,pw]], 150)
        this._AddKeyRow([
            ["LCtrl","LCtrl",20,60],["LWin","LWin",95,60],["LAlt","LAlt",170,60],["Space","Space",245,210],
            ["RAlt","RAlt",470,60],["RWin","RWin",545,60],["AppsKey","AppsKey",620,60],["RCtrl","RCtrl",695,60],
            ["Left","←",n1,nw],["Down","↓",n2,nw],["Right","→",n3,nw],["Numpad0","0",p1,p2 + pw - p1],["NumpadDot","Del",p3,pw]], 180)
        this._AddKeyRow([
            ["Ctrl","Ctrl",20,60],["Shift","Shift",95,60],["Alt","Alt",170,60],
            ["Browser_Back",GetLang("后退"),245,60],["Browser_Forward",GetLang("前进"),320,60],
            ["Browser_Refresh",GetLang("刷新"),395,60],["Browser_Stop",GetLang("停止"),470,60],
            ["Browser_Search",GetLang("搜索"),545,60],["Browser_Favorites",GetLang("收藏夹"),620,60],
            ["Browser_Home",GetLang("主页"),695,60],
            ["Volume_Mute",GetLang("静音"),n1,nw],["Volume_Down",GetLang("音量-"),n2,nw],["Volume_Up",GetLang("音量+"),n3,nw]], 210)
        this._AddKeyRow([
            ["Launch_App1",GetLang("此电脑"),20,60],["Launch_App2",GetLang("计算器"),95,60],
            ["Media_Next",GetLang("下一首"),170,60],["Media_Prev",GetLang("上一首"),245,60],
            ["Media_Stop",GetLang("停止"),320,60],["Media_Play_Pause",GetLang("播放/暂停"),395,80],
            ["Bright_Down",GetLang("亮度-"),545,60],["Bright_Up",GetLang("亮度+"),620,60]], 240)
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
            this._SetKeyBtnState(con, false)
            this.CheckedArr.RemoveAt(arrayIndex)
        }
        else {
            this._SetKeyBtnState(con, true)
            this.CheckedArr.Push(key)
        }

        this.Refresh()
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this._SetKeyBtnState(this.ConMap[value], false)
        }
        this.CheckedArr := []
        this.Refresh()
    }

    GetTriggerKey() {
        triggerKey := ""
        for index, value in this.CheckedArr
            triggerKey .= value "⎖"
        triggerKey := RTrim(triggerKey, "⎖")
        return triggerKey
    }

    _KeyTypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("KeyTypeCon>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumKeyActNames(), "点击")
    }

    _KeyTypeText() {
        return IsObject(this.ui) ? this.ui.Query("KeyTypeCon") : ""
    }

    _SetKeyType(text) {
        items := GetLangArr(["按下", "松开", "点击"])
        idx := 3
        for i, it in items
            if (it == text)
                idx := i
        this.ui.Update("KeyTypeCon", "SelectedIndex", String(idx - 1))
    }

    Init(cmd) {
        cmd := RMTParseErrHandle(cmd).cmd

        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            ; 旧序列号格式：读配置文件 Data，保存时改写为内联 按键_按键名_...
            this.Data := GetMacroCMDData(cmdArr[1])
            this.KeyStr := this.Data.KeyName
            this._SetKeyType(GetLang(CmdEnumKeyAct(this.Data.KeyType)))
            this.ui.Update("HoldTimeCon", "Text", this.Data.HoldTime)
            this.ui.Update("KeyCountCon", "Text", this.Data.Count)
            this.ui.Update("PerIntervalCon", "Text", this.Data.IntervalTime)
        } else {
            this.Data := KeyDataConfig()
            this.KeyStr := cmdArr.Length >= 2 ? cmdArr[2] : ""
            this._SetKeyType(cmdArr.Length >= 3 ? cmdArr[3] : GetLang("点击"))
            this.ui.Update("HoldTimeCon", "Text", cmdArr.Length >= 4 ? cmdArr[4] : 100)
            this.ui.Update("KeyCountCon", "Text", cmdArr.Length >= 5 ? cmdArr[5] : 1)
            this.ui.Update("PerIntervalCon", "Text", cmdArr.Length >= 6 ? cmdArr[6] : 200)
        }

        this.RefreshCheckCon(this.KeyStr)
        this.Refresh()
    }

    RefreshCheckCon(KeyArrStr) {
        this.CheckedArr := GetPressKeyArr(KeyArrStr)

        for key, name in this.ConMap
            this._SetKeyBtnState(name, false)

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this._SetKeyBtnState(this.ConMap[value], true)
        }
    }

    OnSureBtnClick(state, ctrl, event) {
        this.UpdateCommandStr()
        valid := this.CheckIfValid()
        if (!valid)
            return

        action := this.SureBtnAction
        action(this.GetCmdStr())
        this.OnGuiClose()
    }

    GetCmdStr() {
        return this.CommandStr
    }

    ; 按键类型帮助提示（主界面样式：ToolTip 挂标签，不用问号按钮）
    _TypeHelpText() {
        str1 := GetLang("按下，松开是不消耗时间的，可以理解为瞬发")
        str2 := GetLang("指令按下a，不是连续不间断的输入a（物理键盘上长按a，系统会经过处理，不断的松开，然后再按下）")
        str3 := GetLang("按下后建议搭配一个松开，如果不松开再次按下，后续按下指令可能无效（卡键）")
        str4 := GetLang("点击时间小于200表现为点击， 大于250表现为长按")
        str5 := GetLang("点击消耗的时间：（点击时间+每次间隔）*点击次数 - 每次间隔")
        return Format("{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5)
    }

    OnChangeEditValue(state, ctrl, event) {
        this.Refresh()
    }

    Refresh() {
        this.KeyStr := this.GetTriggerKey()
        this.UpdateCommandStr()

        this.ui.Update("TypeBox", "Visibility", "Visible")
        this.ui.Update("HoldTimeTipCon", "Visibility", "Visible")
        this.ui.Update("HoldTimeCon", "Visibility", "Visible")
        this.ui.Update("KeyCountTipCon", "Visibility", "Visible")
        this.ui.Update("KeyCountCon", "Visibility", "Visible")
        this.ui.Update("PerIntervalTipCon", "Visibility", "Visible")
        this.ui.Update("PerIntervalCon", "Visibility", "Visible")
        this.ui.Update("CommandStrCon", "Text", Format("{}{}", GetLang("当前指令："), this.CommandStr))
    }

    UpdateCommandStr() {
        hasHoldTime := this._KeyTypeIndex() == "点击"
        hasCount := hasHoldTime && this.ui.Query("KeyCountCon") != 1
        hasInterval := hasCount && this.ui.Query("PerIntervalCon") != 0

        CommandStr := GetLang("按键")
        CommandStr .= "_" this.KeyStr
        CommandStr .= "_" this._KeyTypeText()
        if (hasHoldTime) {
            CommandStr .= "_" this.ui.Query("HoldTimeCon")
        }
        if (hasCount) {
            CommandStr .= "_" this.ui.Query("KeyCountCon")
        }
        if (hasInterval) {
            CommandStr .= "_" this.ui.Query("PerIntervalCon")
        }

        this.CommandStr := CommandStr
    }

    CheckIfValid() {
        if (this.KeyStr == "") {
            RmtDialog.Info(GetLang("请选择按键！"), , this.Hwnd())
            return false
        }

        return this._KeyTypeIndex() != "点击" || KeyGui.CheckClickParameters(this.ui)
    }

    static CheckClickParameters(ui) {
        count := ui.Query("KeyCountCon")
        hold := ui.Query("HoldTimeCon")
        if (!IsInteger(count) || count < 1) {
            RmtDialog.Info(GetLang("按键次数必须为大于零的整数！"))
            return false
        }
        if (!IsInteger(hold) || hold < 0) {
            RmtDialog.Info(GetLang("按键时间请输入大于0的整数"))
            return false
        }
        if (count > 1) {
            interval := ui.Query("PerIntervalCon")
            if (!IsInteger(interval) || interval < 0) {
                RmtDialog.Info(GetLang("每次间隔时间只能是整数！！"))
                return false
            }
        }

        return true
    }

    TriggerMacro(*) {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.UpdateCommandStr()
        OnTriggerSepcialItemMacro(this.CommandStr)
    }

    ToggleFunc(state) {
        if (state) {
            try Hotkey("F1", this.TriggerAction, "On")
        }
        else {
            try Hotkey("F1", this.TriggerAction, "Off")
        }
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        KeyPickerHook.Attach(this, true)
    }

    OnWindowClosing(state, ctrl, event) {
        KeyPickerHook.Detach(this)
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
        KeyPickerHook.Detach(this)
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
