#Requires AutoHotkey v2.0

; =====================================================================
; 浏览器按键选择器 (BrowserKeyPickerGui)
; 专门适配浏览器与网页输入场景，剔除系统亮度/系统音量/启动程序等无效按键
; =====================================================================

class BrowserKeyPickerGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true

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

    _EscapeXml(s) => EscapeXamlXml(s)

    ShowGui(initialKeys := "") {
        global MainSoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(initialKeys)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    _BuildAndShow() {
        global MainSoftData
        this._closed := false
        title := this.ParentTile GetLang("选择浏览器按键")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "Auto")

        ; === 标题栏 (仅保留关闭X按钮) ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 主键盘区 ===
        body := main.Add("Grid").Grid_Row(1).Margin("12,6,12,6")
        sv := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").ClipToBounds("True")
        kbHost := sv.Add("Grid")
        this._keyGrid := kbHost.Add("Canvas").Width("1109").Height("200").HorizontalAlignment("Center").VerticalAlignment("Top")

        ; === 底部按钮行 ===
        btnRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,10,0,12")
        clearBtn := btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(88).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
            .Margin("0,0,160,0")
        clearBtn.InjectResources(FrontInfoGui._OkBtnHoverStyle())
        AddCmdOkBtn(btnRow, "BtnOk")

        ; === 生成键盘按键网格 ===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1130" Height="310"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册事件 ===
        this._RegisterKeyEvents()
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnSureBtnClick"))
    }

    _PlaceKey(value, display, x, y, width) {
        this._keySeq += 1
        name := "KeyBtn_" this._keySeq
        btn := this._keyGrid.Add("Button").Name(name).Width(width).Height(25)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .Content(display).FontSize(11).Cursor("Hand").Padding("2,0").Tag("0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        btn.InjectResources(FrontInfoGui._KeyPickBtnStyle())
        this.ConMap.Set(value, name)
        this._btnKeyMap.Set(name, value)
    }

    _AddKeyRow(keys, y) {
        for item in keys
            this._PlaceKey(item[1], item[2], item[3], y, item[4])
    }

    _BuildKeyGrid() {
        nx := 768, nw := 45, ng := 8
        n1 := nx, n2 := nx + nw + ng, n3 := nx + 2 * (nw + ng)
        px := n3 + nw + 14, pw := 35, pg := 12
        p1 := px, p2 := px + pw + pg, p3 := px + 2 * (pw + pg), p4 := px + 3 * (pw + pg)

        ; 第一行: Esc + F1~F12 + PrtScr/Scroll/Pause
        this._AddKeyRow([
            ["Escape","Esc",20,40],["F1","F1",120,35],["F2","F2",170,35],["F3","F3",220,35],["F4","F4",270,35],
            ["F5","F5",345,35],["F6","F6",395,35],["F7","F7",445,35],["F8","F8",495,35],
            ["F9","F9",570,35],["F10","F10",620,35],["F11","F11",670,35],["F12","F12",720,35],
            ["PrintScreen","PrtScr",n1,nw],["ScrollLock","Scroll",n2,nw],["Pause","Pause",n3,nw]], 10)

        ; 第二行: ~ 1~0 - = Backspace + Ins/Home/PgUp + 数字小键盘
        this._AddKeyRow([
            ["``","~",20,35],["1","1",70,35],["2","2",120,35],["3","3",170,35],["4","4",220,35],
            ["5","5",270,35],["6","6",320,35],["7","7",370,35],["8","8",420,35],["9","9",470,35],
            ["0","0",520,35],["-","-",570,35],["=","=",620,35],["Backspace","Backspace",670,85],
            ["Insert","Ins",n1,nw],["Home","Home",n2,nw],["PageUp","PgUp",n3,nw],
            ["NumLock","Num",p1,pw],["NumpadDivide","/",p2,pw],["NumpadMultiply","*",p3,pw],["NumpadSubtract","-",p4,pw]], 40)

        ; 第三行: Tab Q~P [ ] \ + Del/End/PgDn + 数字小键盘 789+
        this._AddKeyRow([
            ["Tab","Tab",20,60],["KeyQ","Q",100,35],["KeyW","W",150,35],["KeyE","E",200,35],["KeyR","R",250,35],
            ["KeyT","T",300,35],["KeyY","Y",350,35],["KeyU","U",400,35],["KeyI","I",450,35],["KeyO","O",500,35],
            ["KeyP","P",550,35],["[","[",600,35],["]","]",650,35],["\","\",705,50],
            ["Delete","Del",n1,nw],["End","End",n2,nw],["PageDown","PgDn",n3,nw],
            ["Numpad7","7",p1,pw],["Numpad8","8",p2,pw],["Numpad9","9",p3,pw],["NumpadAdd","+",p4,pw]], 70)

        ; 第四行: CapsLock A~L ; ' Enter + 数字小键盘 456
        this._AddKeyRow([
            ["CapsLock","CapsLock",20,75],["KeyA","A",120,35],["KeyS","S",170,35],["KeyD","D",220,35],["KeyF","F",270,35],
            ["KeyG","G",320,35],["KeyH","H",370,35],["KeyJ","J",420,35],["KeyK","K",470,35],["KeyL","L",520,35],
            [";",";",570,35],["'","'",620,35],["Enter","Enter",680,75],
            ["Numpad4","4",p1,pw],["Numpad5","5",p2,pw],["Numpad6","6",p3,pw]], 100)

        ; 第五行: LShift Z~M , . / RShift + 方向上 + 小键盘 123 Enter
        this._AddKeyRow([
            ["ShiftLeft","LShift",20,85],["KeyZ","Z",130,35],["KeyX","X",180,35],["KeyC","C",230,35],["KeyV","V",280,35],
            ["KeyB","B",330,35],["KeyN","N",380,35],["KeyM","M",430,35],[",",",",480,35],[".",".",530,35],
            ["/","/",580,35],["ShiftRight","RShift",670,85],["ArrowUp","↑",n2,nw],
            ["Numpad1","1",p1,pw],["Numpad2","2",p2,pw],["Numpad3","3",p3,pw],["NumpadEnter","Enter",p4,pw]], 130)

        ; 第六行: Ctrl Alt Space Alt Ctrl + 方向左下右 + 小键盘 0 .
        this._AddKeyRow([
            ["ControlLeft","LCtrl",20,80],["AltLeft","LAlt",115,80],["Space","Space",210,340],
            ["AltRight","RAlt",565,80],["ControlRight","RCtrl",660,95],
            ["ArrowLeft","←",n1,nw],["ArrowDown","↓",n2,nw],["ArrowRight","→",n3,nw],
            ["Numpad0","0",p1,p2 + pw - p1],["NumpadDecimal",".",p3,pw]], 160)
    }

    _RegisterKeyEvents() {
        for name, value in this._btnKeyMap
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnCheckedKey").Bind(value))
    }

    OnCheckedKey(key, *) {
        con := this.ConMap.Get(key)
        foundIdx := 0
        for idx, val in this.CheckedArr {
            if (val == key) {
                foundIdx := idx
                break
            }
        }

        if (foundIdx > 0) {
            this._SetKeyBtnState(con, false)
            this.CheckedArr.RemoveAt(foundIdx)
        } else {
            this._SetKeyBtnState(con, true)
            this.CheckedArr.Push(key)
        }
    }

    _SetKeyBtnState(con, selected) {
        bg := selected ? this.SelectColor : this.UnSelectColor
        tagVal := selected ? "1" : "0"
        this.ui.Update(con, "Background", bg)
        this.ui.Update(con, "Tag", tagVal)
    }

    ClearCheckedArr() {
        for idx, val in this.CheckedArr {
            if (this.ConMap.Has(val))
                this._SetKeyBtnState(this.ConMap[val], false)
        }
        this.CheckedArr := []
    }

    Init(initialKeys) {
        this.CheckedArr := []
        for key, name in this.ConMap
            this._SetKeyBtnState(name, false)

        rawKeys := initialKeys is Array ? initialKeys : StrSplit(initialKeys, ["⎖", ","])
        for val in rawKeys {
            val := Trim(val)
            if (val == "")
                continue
            this.CheckedArr.Push(val)
            if (this.ConMap.Has(val))
                this._SetKeyBtnState(this.ConMap[val], true)
        }
    }

    OnSureBtnClick(state, ctrl, event) {
        if (this.SureBtnAction) {
            action := this.SureBtnAction
            action(this.CheckedArr.Clone())
        }
        this._CloseWindow()
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    OnWindowClosing(state, ctrl, event) {
        global MainSoftData
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    _CloseWindow() {
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
        this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }
}
