#Requires AutoHotkey v2.0

; =====================================================================
; 按键检测编辑器 —— 键盘+鼠标布局与按键指令一致；不含手柄（见 JoyCheckGui）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
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
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("4,2,4,8")
        body.Rows("Auto", "Auto", "44", "48")
        body.Cols("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "*")

        ; 行0：键盘（按键指令同款）
        sv := body.Add("ScrollViewer").Grid_Row(0).Grid_ColumnSpan(11).Margin("0,4,0,0")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").ClipToBounds("True")
        kbHost := sv.Add("Grid")
        this._keyGrid := kbHost.Add("Canvas").Width("1109").Height("270").HorizontalAlignment("Center").VerticalAlignment("Top")

        ; 行1：鼠标（居中，按键指令同款）
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

        ; 行2：检测模式 / 检测类型 / 结果变量（居中）
        bottom := body.Add("StackPanel").Grid_Row(2).Grid_ColumnSpan(11).Orientation("Horizontal").HorizontalAlignment("Center").Margin("10,12,10,2").VerticalAlignment("Center")
        bottom.Add("TextBlock").Text(GetLang("检测模式:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        cc := bottom.Add("ComboBox").Name("CheckTypeCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["同时按下", "有一个按下"])
            cc.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Text(GetLang("检测类型:")).VerticalAlignment("Center").Margin("20,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        st := bottom.Add("ComboBox").Name("StateTypeCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["物理状态", "逻辑状态"])
            st.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Text(GetLang("结果变量：")).VerticalAlignment("Center").Margin("20,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("ComboBox").Name("VarNameCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行3：清空 / 确定（清空与确定同款，间距 300px）
        btnRow := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(11).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        clearBtn := btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(88).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
            .Margin("0,0,300,0")
        clearBtn.InjectResources(FrontInfoGui._OkBtnHoverStyle())
        AddCmdOkBtn(btnRow, "BtnOk")

        ; === 生成按键网格 ===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1130" Height="460"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件 ===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/24-按键检测")
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

    }

    ; ---------------- 按键网格（Canvas 绝对定位，与按键指令键盘布局一致）----------------

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
            this._PlaceKey(item[1], item[2], item[3], y, item[4])
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
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this._SetKeyBtnState(this.ConMap[value], false)
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
            this._SetKeyBtnState(name, false)

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this._SetKeyBtnState(this.ConMap[value], true)
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

        this.ui.Update("CheckTypeCon", "SelectedIndex", String(CmdEnumIndex(this.Data.CheckType, CmdEnumKeyCheckNames())))
        this.ui.Update("StateTypeCon", "SelectedIndex", String(CmdEnumIndex(this.Data.StateType, CmdEnumStateNames())))
        this._SetCombo("VarNameCon", this.DLVariableArr, this.Data.VarName != "" ? this.Data.VarName : "Var1")

        this.RefreshCheckCon(this.KeyStr)
    }

    CheckIfValid() {
        this.KeyStr := this.GetTriggerKey()
        if (this.KeyStr == "") {
            RmtDialog.Info(GetLang("请选择要检测的按键！"), , this.Hwnd())
            return false
        }

        varName := Trim(this.ui.Query("VarNameCon"))
        if (varName == "") {
            RmtDialog.Info(GetLang("请输入变量名！"))
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
        data.CheckType := CmdEnumFromIndex(IsObject(this.ui) ? this.ui.Query("CheckTypeCon>SelectedIndex") : "", CmdEnumKeyCheckNames())
        data.StateType := CmdEnumFromIndex(IsObject(this.ui) ? this.ui.Query("StateTypeCon>SelectedIndex") : "", CmdEnumStateNames())
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
        KeyPickerHook.Attach(this, false)
    }

    OnWindowClosing(state, ctrl, event) {
        KeyPickerHook.Detach(this)
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
