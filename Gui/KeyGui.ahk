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
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("按键编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 内容：TabControl（常规 / 错误处理）===
        tc := main.Add("TabControl").Grid_Row(1).Margin("8,8,8,8").Name("MainTab")

        ; ---- Tab1 常规 ----
        ti1 := tc.Add("TabItem").Header(GetLang("常规"))
        body := ti1.Add("Grid").Margin("6,8,6,6")
        body.Rows("30", "36", "*", "34", "44")
        body.Cols("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "*")

        ; 行0：备注（放选项卡第一个位置）
        remarkRow := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(11).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        remarkRow.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        remarkRow.Add("TextBox").Name("RemarkCon").Width(240).Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 行1：顶部工具行
        top := body.Add("StackPanel").Grid_Row(1).Grid_ColumnSpan(11).Orientation("Horizontal").Margin("10,4")
        top.Add("Button").Name("BtnSim").Content(GetLang("模拟指令")).Height(28).MinHeight(28).Padding("14,0").Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
        top.Add("TextBlock").Text("F1").VerticalAlignment("Center").Margin("8,0,0,0").Opacity("0.6").Foreground("{DynamicResource TextMain}").FontSize("12")
        top.Add("TextBlock").Text(GetLang("键盘按键检测：")).VerticalAlignment("Center").Margin("18,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        top.Add("TextBox").Name("HotkeyCon").Width(100).Height(26).MinHeight(26).Margin("4,0,0,0").VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").IsReadOnly("True")
        top.Add("Button").Name("BtnDetect").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0").Margin("6,0,0,0").Cursor("Hand")

        ; 行2：按键网格（GroupBox + ScrollViewer）
        keyGroup := body.Add("GroupBox").Grid_Row(2).Grid_ColumnSpan(11).Header(GetLang("请从下面按钮中选择按键：")).Margin("8,2,8,4")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}")
            .ClipToBounds("True")
        sv := keyGroup.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Auto").ClipToBounds("True")
        this._keyGrid := sv.Add("Canvas").Width("1240").Height("410")

        ; 行3：底部参数行
        bottom := body.Add("StackPanel").Grid_Row(3).Grid_ColumnSpan(11).Orientation("Horizontal").Margin("10,2").VerticalAlignment("Center")
        ; 类型组：标签+下拉框合成盒子，提示挂盒子上（主界面 _ComboRow 同款）
        typeBox := bottom.Add("StackPanel").Name("TypeBox").Orientation("Horizontal").VerticalAlignment("Center").ToolTip(this._TypeHelpText())
        typeBox.Add("TextBlock").Text(GetLang("类型:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        kt := typeBox.Add("ComboBox").Name("KeyTypeCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["按下", "松开", "点击"])
            kt.Add("ComboBoxItem").Content(t)
        bottom.Add("TextBlock").Name("AxisValueTipCon").Text(GetLang("轴值:")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("AxisValueCon").Width(64).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("HoldTimeTipCon").Text(GetLang("点击时长:")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("HoldTimeCon").Width(60).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("KeyCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("KeyCountCon").Width(60).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("PerIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        bottom.Add("TextBox").Name("PerIntervalCon").Width(60).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0")
            .TextAlignment("Center").FontSize("11").Margin("6,0,0,0")
            .Foreground("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("CommandStrCon").Text(GetLang("当前指令：无")).VerticalAlignment("Center").Margin("15,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")

        ; 行4：底部按钮行
        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(11).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Height(28).MinHeight(28).Padding("14,0").Margin("4,0").Cursor("Hand")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0").Margin("4,0").Cursor("Hand")

        ; ---- Tab2 错误处理 ----
        ti2 := tc.Add("TabItem").Header(GetLang("错误处理"))
        body2 := ti2.Add("Grid").Margin("16,14,16,14")
        body2.Rows("34", "34", "34", "*")
        ehRow1 := body2.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        ehRow1.Add("TextBlock").Text(GetLang("错误处理：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ehCombo := ehRow1.Add("ComboBox").Name("EHModeCombo").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").SelectedIndex("0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ehCombo.Add("ComboBoxItem").Content(GetLang("停止运行")).Tag("stop")
        ehCombo.Add("ComboBoxItem").Content(GetLang("忽略错误并继续")).Tag("ignore")
        ehCombo.Add("ComboBoxItem").Content(GetLang("重试")).Tag("retry")

        ehRow2 := body2.Add("StackPanel").Name("EHRetryRow").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        ehRow2.Add("TextBlock").Text(GetLang("重试次数：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ehRow2.Add("TextBox").Name("EHRetryCount").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ehRow3 := body2.Add("StackPanel").Name("EHIntervalRow").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        ehRow3.Add("TextBlock").Text(GetLang("重试间隔(ms)：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        ehRow3.Add("TextBox").Name("EHRetryInterval").Width(60).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ehBtnRow := body2.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        ehBtnRow.Add("Button").Name("BtnOk2").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0")

        ; === 生成按键网格（加入 body，随后 main.ToString() 生效）===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1280" Height="640" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件（ui 已建）===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnSim", "Click", (*) => this.TriggerMacro())
        this.ui.OnEvent("HotkeyCon", "KeyCapture", ObjBindMethod(this, "OnKeyCapture"))
        this.ui.OnEvent("BtnDetect", "Click", ObjBindMethod(this, "OnSureHotkey"))
        this.ui.OnEvent("KeyTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("HoldTimeCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("KeyCountCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("PerIntervalCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("AxisValueCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("EHModeCombo", "SelectionChanged", ObjBindMethod(this, "OnEHModeChange"))
        this.ui.OnEvent("BtnOk2", "Click", ObjBindMethod(this, "OnSureBtnClick"))

        ; 类型初始值
        this.ui.Update("KeyTypeCon", "SelectedIndex", "2")   ; 默认 点击

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                if (this.OwnerHwnd != "")
                    try this.ui.Update("Window", "NativeOwner", String(this.OwnerHwnd))
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                try SetTimer((*) => this.ui.Update("Window", "Opacity", "1"), -10)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd)
            this._closed := true
    }

    ; ---------------- 按键网格（Canvas 绝对定位，复刻原版键盘布局）----------------

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
            value := item[1]
            display := item[2]
            x := item[3]
            width := item[4]
            this._PlaceKey(value, display, x, y, width)
        }
    }

    _BuildKeyGrid() {
        global MySoftData
        this._PlaceLabel(GetLang("键盘"), 20, 0)
        ; y 为 Canvas 内坐标（原版窗口坐标 - 60）
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
            ["JoyDpadNone",GetLang("无方向"),320,60],["JoyAxisLX","LX",395,64],["JoyAxisLY","LY",470,64],
            ["JoyAxisRX","RX",545,64],["JoyAxisRY","RY",620,64],["JoyAxisLT","LT",695,64],["JoyAxisRT","RT",770,64]], 380)
    }

    _RegisterKeyEvents() {
        for name, value in this._btnKeyMap
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnCheckedKey").Bind(value))
    }

    ; ---------------- 选项相关 ----------------

    ; 真轴键（带轴数值指令）：LX/LY/RX/RY 摇杆 -100..100；LT/RT 扳机 0..100
    _AxisKeyRange(key) {
        static ranges := Map(
            "JoyAxisLX", "-100..100", "JoyAxisLY", "-100..100", "JoyAxisRX", "-100..100", "JoyAxisRY", "-100..100",
            "JoyAxisLT", "0..100", "JoyAxisRT", "0..100")
        return ranges.Get(key, "")
    }
    _IsAxisKey(key) {
        return this._AxisKeyRange(key) != ""
    }
    _AxisMinMax(key) {
        if (key == "JoyAxisLT" || key == "JoyAxisRT")
            return [0, 100]
        return [-100, 100]
    }

    OnCheckedKey(key, *) {
        ; 互斥约束：轴键只能单独选一个；选了普通键就不能选轴键；选了轴键就清空其他所有选择
        if (this._IsAxisKey(key)) {
            isSelected := false
            arrayIndex := 0
            for index, value in this.CheckedArr {
                if (value == key) {
                    isSelected := true
                    arrayIndex := index
                    break
                }
            }
            ; 反选当前轴 -> 清空；正选 -> 仅保留该轴
            for index, value in this.CheckedArr {
                if (this.ConMap.Has(value))
                    this.ui.Update(this.ConMap[value], "Background", this.UnSelectColor)
            }
            if (isSelected) {
                this.CheckedArr := []
            } else {
                this.CheckedArr := [key]
                this.ui.Update(this.ConMap[key], "Background", this.SelectColor)
                ; 首次选轴给出默认轴值
                cur := IsObject(this.ui) ? this.ui.Query("AxisValueCon") : ""
                if (!IsNumber(cur) || cur == "")
                    this.ui.Update("AxisValueCon", "Text", "100")
            }
            this.Refresh()
            return
        }

        ; 普通键（含 Dpad/Joy按钮/键鼠）：不支持与轴键混选。若当前已选轴键，直接清掉轴再按普通键逻辑
        if (this.CheckedArr.Length > 0 && this._IsAxisKey(this.CheckedArr[1])) {
            for index, value in this.CheckedArr {
                if (this.ConMap.Has(value))
                    this.ui.Update(this.ConMap[value], "Background", this.UnSelectColor)
            }
            this.CheckedArr := []
        }

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

    _SelectedAxisKey() {
        if (this.CheckedArr.Length == 1 && this._IsAxisKey(this.CheckedArr[1]))
            return this.CheckedArr[1]
        return ""
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.UnSelectColor)
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
        if (!IsNumber(v) || Integer(v) < 0)
            return 3   ; 默认 点击：参数行可见
        return Integer(v) + 1
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

    OnKeyCapture(state, ctrl, event) {
        key := IsObject(state) && state.Has("KeyCapture") ? state["KeyCapture"] : ""
        if (key != "")
            this.ui.Update("HotkeyCon", "Text", key)
    }

    OnSureHotkey(state, ctrl, event) {
        triggerKey := this.ui.Query("HotkeyCon")
        triggerKey := StrReplace(triggerKey, ",", "逗号")
        triggerKey := StrReplace(triggerKey, "Insert", "Ins")
        this.RefreshCheckCon(triggerKey)

        this.Refresh()
    }

    Init(cmd) {
        ; 阶段5：指令配置化。新格式 按键<serial> 读配置文件；旧格式 按键_a_点击_100 兼容解析
        ; 兼容历史 |EH: 后缀（如有）：剥离，仅影响错误处理配置（Data 存 ErrMode 时优先 Data）
        eh := RMTParseErrHandle(cmd)
        cmd := eh.cmd
        this._ehCfg := eh.cfg

        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        ; 备注：指令串第二段（按键<serial>_备注 或 旧 按键_a_点击 均取第二段）
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            ; 新格式：读配置文件 Data
            this.Data := GetMacroCMDData(cmdArr[1])
            this.KeyStr := this.Data.KeyName
            this._SetKeyType(GetLangArr(["按下", "松开", "点击"])[this.Data.KeyType])
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
        this._InitEH()

        ; 轴指令回显：载入真轴 + 轴值
        this._InitAxisValueBox()
    }

    ; 回显轴指令的轴值与选中态（兼容 config 与旧明文 LX:75 两种来源）
    _InitAxisValueBox() {
        axisVal := ""
        axisName := ""
        if (IsObject(this.Data) && this.Data.IsAxis) {
            axisName := this.Data.KeyName
            axisVal := this.Data.HasOwnProp("AxisValue") ? this.Data.AxisValue : ""
        } else if (RegExMatch(this.KeyStr, "^(JoyAxisL[XY]|JoyAxisR[XY]|JoyAxisL[TR]|JoyAxisR[TR]):(-?[0-9]+)$", &m)) {
            axisName := m[1]
            axisVal := Integer(m[2])
        }
        if (axisName != "" && this._IsAxisKey(axisName) && this.ConMap.Has(axisName)) {
            ; 只保留该轴为唯一选中（若 KeyStr 含该轴则已由 RefreshCheckCon 高亮，这里兜底补全）
            if (this.CheckedArr.Length != 1 || this.CheckedArr[1] != axisName) {
                for k in this.CheckedArr
                    if (this.ConMap.Has(k))
                        this.ui.Update(this.ConMap[k], "Background", this.UnSelectColor)
                this.CheckedArr := [axisName]
                this.ui.Update(this.ConMap[axisName], "Background", this.SelectColor)
            }
            ; 缺省轴值一律给满值：摇杆 100（满偏）、扳机 100（满按），与 OnCheckedKey 的默认值一致
            if (axisVal == "")
                axisVal := 100
            this.ui.Update("AxisValueCon", "Text", axisVal)
        }
        this.Refresh()
    }

    ; ============ 错误处理（阶段5，影刀模式）============

    ; 初始化错误处理页
    _InitEH() {
        mode := this.Data.HasOwnProp("ErrMode") ? this.Data.ErrMode : "stop"
        if (IsObject(this._ehCfg))
            mode := this._ehCfg.mode
        idx := 0
        for i, m in ["stop", "ignore", "retry"] {
            if (m == mode) {
                idx := i - 1
                break
            }
        }
        if (IsObject(this.ui)) {
            this.ui.Update("EHModeCombo", "SelectedIndex", String(idx))
            this.ui.Update("EHRetryCount", "Text", this.Data.HasOwnProp("ErrRetryCount") ? this.Data.ErrRetryCount : "3")
            this.ui.Update("EHRetryInterval", "Text", this.Data.HasOwnProp("ErrRetryInterval") ? this.Data.ErrRetryInterval : "500")
            this.OnEHModeChange()
        }
    }

    _EHMode() {
        v := IsObject(this.ui) ? this.ui.Query("EHModeCombo>SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    OnEHModeChange(state := "", ctrl := "", event := "") {
        showRetry := this._EHMode() == 2
        if (IsObject(this.ui)) {
            this.ui.Update("EHRetryRow", "Visibility", showRetry ? "Visible" : "Collapsed")
            this.ui.Update("EHIntervalRow", "Visibility", showRetry ? "Visible" : "Collapsed")
        }
    }

    RefreshCheckCon(KeyArrStr) {
        this.CheckedArr := GetPressKeyArr(KeyArrStr)

        for key, name in this.ConMap
            this.ui.Update(name, "Background", this.UnSelectColor)

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.SelectColor)
        }
    }

    OnSureBtnClick(state, ctrl, event) {
        this.UpdateCommandStr()
        valid := this.CheckIfValid()
        if (!valid)
            return

        ; 选择手柄按键时检查 ViGEm 驱动是否已安装，未安装则弹出安装提示
        isJoy := InStr(this.KeyStr, "Joy")
        isInstalled := IsViGEmInstalled()
        JoyDebugLog(Format("KeyGui.OnSureBtnClick KeyStr='{}' IsJoy={} ViGEmInstalled={}"
            , this.KeyStr, isJoy, isInstalled), "vigeminstall")

        if (isJoy && !isInstalled) {
            ShowViGEmInstallTip()
            return
        }

        action := this.SureBtnAction
        action(this.GetCmdStr())
        this.OnGuiClose()
    }

    ; 阶段5：指令配置化——组装 Data 保存到配置文件，返回 按键<serial>_备注
    GetCmdStr() {
        ; 复用旧 CommandStr 的 UI 值解析（KeyStr 已在 UpdateCommandStr 刷新）
        cmdArr := SplitCommand(this.CommandStr)
        this.Data.KeyName := this.KeyStr
        axisKey := this._SelectedAxisKey()
        if (axisKey != "") {
            ; 轴指令：连续行为，无类型(按下/松开/点击)。KeyType 置固定 1(按下=设值保持)，
            ; 仅 AxisValue 表达目标值；回中由用户再发一条 AxisValue=0 实现。
            this.Data.KeyType := 1
            this.Data.IsAxis := 1
            this.Data.AxisValue := this._ReadAxisValue(axisKey)
        } else {
            this.Data.KeyType := this._KeyTypeIndex()          ; 1按下 2松开 3点击
            this.Data.IsAxis := 0
            this.Data.AxisValue := 0
        }
        this.Data.HoldTime := cmdArr.Length >= 4 ? cmdArr[4] : 100
        this.Data.Count := cmdArr.Length >= 5 ? cmdArr[5] : 1
        this.Data.IntervalTime := cmdArr.Length >= 6 ? cmdArr[6] : 0
        ; 错误处理（阶段5）
        this.Data.ErrMode := ["stop", "ignore", "retry"][this._EHMode() + 1]
        this.Data.ErrRetryCount := this.ui.Query("EHRetryCount")
        this.Data.ErrRetryInterval := this.ui.Query("EHRetryInterval")

        ; 生成序列码（首次保存分配，后续复用）
        if (this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("按键"))
        SaveMacroCMDData(this.Data)
        ; 备注：用户备注优先，为空则自动生成操作内容
        remark := Trim(this.ui.Query("RemarkCon"))
        if (remark == "") {
            remark := this.KeyStr
            if (axisKey != "")
                remark .= ":" this.Data.AxisValue
            else
                remark .= "_" this._KeyTypeText()
        }
        return CorrectRemark(this.Data.SerialStr, remark)
    }

    _ReadAxisValue(axisKey) {
        range := this._AxisMinMax(axisKey)
        v := this.ui.Query("AxisValueCon")
        if (!IsNumber(v))
            v := range[2]
        v := Integer(v)
        if (v < range[1])
            return range[1]
        if (v > range[2])
            return range[2]
        return v
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

        axisKey := this._SelectedAxisKey()
        isAxis := axisKey != ""
        ; 轴是连续行为（非按键），无按下/松开/点击类型：选轴时隐藏"类型"组与点击类参数，
        ; 仅保留"轴值"输入框（设到该值即保持，回中用数值0再发一条）。
        isShowType := !isAxis
        isShowHoldTime := !isAxis && this._KeyTypeIndex() == 3
        isShowCount := isShowHoldTime
        isShowInterval := isShowCount && this.ui.Query("KeyCountCon") != 1
        isShowAxisValue := isAxis

        ; 类型组（标签+下拉）整体显隐
        this.ui.Update("TypeBox", "Visibility", isShowType ? "Visible" : "Collapsed")
        this.ui.Update("AxisValueTipCon", "Visibility", isShowAxisValue ? "Visible" : "Collapsed")
        this.ui.Update("AxisValueCon", "Visibility", isShowAxisValue ? "Visible" : "Collapsed")
        this.ui.Update("HoldTimeTipCon", "Visibility", isShowHoldTime ? "Visible" : "Collapsed")
        this.ui.Update("HoldTimeCon", "Visibility", isShowHoldTime ? "Visible" : "Collapsed")
        this.ui.Update("KeyCountTipCon", "Visibility", isShowCount ? "Visible" : "Collapsed")
        this.ui.Update("KeyCountCon", "Visibility", isShowCount ? "Visible" : "Collapsed")
        this.ui.Update("PerIntervalTipCon", "Visibility", isShowInterval ? "Visible" : "Collapsed")
        this.ui.Update("PerIntervalCon", "Visibility", isShowInterval ? "Visible" : "Collapsed")

        this.ui.Update("CommandStrCon", "Text", Format("{}{}", GetLang("当前指令："), this.CommandStr))
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

    UpdateCommandStr() {
        axisKey := this._SelectedAxisKey()
        hasHoldTime := !axisKey && this._KeyTypeIndex() == 3
        hasCount := hasHoldTime && this.ui.Query("KeyCountCon") != 1
        hasInterval := hasCount && this.ui.Query("PerIntervalCon") != 0

        CommandStr := GetLang("按键")
        if (axisKey != "") {
            ; 轴指令（连续行为，无类型）：按键_LX:75
            CommandStr .= "_" axisKey ":" this._ReadAxisValue(axisKey)
        } else {
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
        }

        this.CommandStr := CommandStr
    }

    CheckIfValid() {
        if (this.KeyStr == "") {
            MsgBox(GetLang("请选择按键！"))
            return false
        }

        axisKey := this._SelectedAxisKey()
        if (axisKey != "") {
            ; 轴值校验（摇杆 -100..100，扳机 0..100）
            range := this._AxisMinMax(axisKey)
            v := this.ui.Query("AxisValueCon")
            if (!IsNumber(v) || Integer(v) < range[1] || Integer(v) > range[2]) {
                MsgBox(Format("轴值需为 {} 到 {} 的整数！", range[1], range[2]))
                return false
            }
        } else if (this.CheckedArr.Length > 0) {
            ; 非轴多键时不允许混入任何轴键（防异常态）
            for k in this.CheckedArr {
                if (this._IsAxisKey(k)) {
                    MsgBox(GetLang("轴键只能单独使用一个，且不能与其他按键组合！"))
                    return false
                }
            }
        }

        if (!IsInteger(this.ui.Query("KeyCountCon")) || Integer(this.ui.Query("KeyCountCon")) <= 0) {
            MsgBox(GetLang("按键次数必须为大于零的整数！"))
            return false
        }

        if (this._KeyTypeIndex() == 3) {
            if (IsFloat(this.ui.Query("HoldTimeCon")) || this.ui.Query("HoldTimeCon") < 0) {
                MsgBox(GetLang("按键时间请输入大于0的整数"))
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
            Hotkey("F1", this.TriggerAction, "On")
        }
        else {
            Hotkey("F1", this.TriggerAction, "Off")
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        } finally {
        }
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
