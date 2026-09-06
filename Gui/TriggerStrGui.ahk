#Requires AutoHotkey v2.0

; =====================================================================
; 字串触发编辑器 —— XAML 迁移版
; 公开接口保持：ShowGui(triggerKey, holdTime, IsToolEdit) / SureBtnAction / SaveBtnAction / SureFocusCon
; 调用方：Gui/TabItemUIUtil.ahk:221-223（编辑宏触发字串）、Gui/EditHotkeyGui.ahk:130-133（快捷方式-字串）
; =====================================================================

class TriggerStrGui {
    __new() {
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.SureFocusCon := ""
        this._closed := true

        this.ConMap := Map()
        this.IsEndChar := true
        this.IsSubStr := true
        this.IsDelete := true
        this.Str := ""
        this.SaveBtnCtrl := "SaveBtnCtrl"
        this.showSaveBtn := false
        this.SettingTipCon := "SettingTipCon"
        this.IsEndCharCon := "IsEndCharCon"
        this.IsSubStrCon := "IsSubStrCon"
        this.IsDeleteCon := "IsDeleteCon"

        ; 字符按钮行（与原生布局一致：x 起点 20、步进 75；行 y 起点 40、步进 40）
        this._charRows := [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "+", "-", "*", "/"],
            ["!", "@", "#", "$", "%", "^", "(", ")", "<", ">", "[", "]", "{", "}", "|"],
            ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "?", "_", ";", ",", "."],
            ["A", "S", "D", "F", "G", "H", "J", "K", "L", "'", '"', "\"],
            ["Z", "X", "C", "V", "B", "N", "M"]
        ]
        this._charSeq := 0
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

    ;UI相关
    ShowGui(triggerKey, holdTime, IsToolEdit) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        showSaveBtn := !IsToolEdit
        this.Init(triggerKey, showSaveBtn)
        this.Refresh()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := GetLang("字串触发编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "280", "34", "30", "30", "30", "32", "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 字符区（GroupBox + Canvas 绝对定位，复刻原生布局）===
        gb := main.Add("GroupBox").Grid_Row(1).Header(GetLang("请从下面字符中组合你想要触发宏的字串：")).Margin("10,2,10,0")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Padding("10,4")
        this._charGrid := gb.Add("Canvas").Width("1120").Height("240")
        this._BuildCharGrid()

        ; === 选项行 ===
        chkRow := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center").Margin("20,0,0,0")
        chkRow.Add("CheckBox").Name("IsEndCharCon").Content(GetLang("终止符")).Width(120).VerticalAlignment("Center")
        chkRow.Add("CheckBox").Name("IsSubStrCon").Content(GetLang("允许子字串")).Margin("80,0,0,0").VerticalAlignment("Center")
        chkRow.Add("CheckBox").Name("IsDeleteCon").Content(GetLang("删除触发字串")).Width(150).Margin("110,0,0,0").VerticalAlignment("Center")

        ; === 说明文本 ===
        main.Add("TextBlock").Grid_Row(3).Text(GetLang("终止符说明：当输入字串时，需要输入一个终止符触发。终止符包含：-()[]{}':;/\,.?! Enter Space Tab以及引号")).Margin("20,2,20,0").TextWrapping("Wrap")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        main.Add("TextBlock").Grid_Row(4).Text(GetLang("子字串说明:字串在另一个单词中也会被触发,例如输入Word会触发rd、ord、word。如果非子字串,只会触发word。")).Margin("20,2,20,0").TextWrapping("Wrap")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        main.Add("TextBlock").Grid_Row(5).Text(GetLang("备注：字串长度必须大于0,但不能超过40, 鼠标点击会重置字串识别器")).Margin("20,2,20,0").TextWrapping("Wrap")
            .Foreground("{DynamicResource TextMain}").FontSize("12")

        ; === 当前配置提示 ===
        main.Add("TextBlock").Name("SettingTipCon").Grid_Row(6).Text(GetLang("当前配置的触发键：无")).Margin("20,2,20,0").TextWrapping("Wrap")
            .Foreground("{DynamicResource TextMain}").FontSize("12")

        ; === 底部按钮 ===
        btnRow := main.Add("StackPanel").Grid_Row(7).Orientation("Horizontal").VerticalAlignment("Center").Margin("50,0,0,0")
        btnRow.Add("Button").Name("BtnBackspace").Content(GetLang("退格")).Width(100).Height(40).MinHeight(40).Cursor("Hand")
        btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空字串")).Width(100).Height(40).MinHeight(40).Margin("140,0,0,0").Cursor("Hand")
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(100).Height(40).MinHeight(40).Margin("140,0,0,0").Cursor("Hand")
        btnRow.Add("Button").Name("SaveBtnCtrl").Content(GetLang("应用并保存")).Width(100).Height(40).MinHeight(40).Margin("140,0,0,0").Cursor("Hand")

        ; === 创建 XAMLHost ===
        pos := GetCenterPosOnActiveMonitor(1150, 500)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1150" Height="500" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual" Left="' pos.x '" Top="' pos.y '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        localUi := this.ui
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing").Bind(localUi))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this._RegisterCharEvents()
        this.ui.OnEvent("IsEndCharCon", "Click", ObjBindMethod(this, "OnClickNoEndCharCon"))
        this.ui.OnEvent("IsSubStrCon", "Click", ObjBindMethod(this, "OnClickSubStrCon"))
        this.ui.OnEvent("IsDeleteCon", "Click", ObjBindMethod(this, "OnClickNoDeleteCon"))
        this.ui.OnEvent("BtnBackspace", "Click", (*) => this.Backspace())
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearStr())
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("SaveBtnCtrl", "Click", ObjBindMethod(this, "OnSaveBtnClick"))
    }

    _BuildCharGrid() {
        rowY := 40
        for row in this._charRows {
            posX := 20
            for ch in row {
                this._AddCharBtn(ch, posX, rowY)
                posX += 75
            }
            rowY += 40
        }
    }

    _AddCharBtn(ch, x, y) {
        this._charSeq += 1
        name := "CharBtn_" this._charSeq
        btn := this._charGrid.Add("Button").Name(name).Width(45).Height(30)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .Content(ch).FontSize(12).Cursor("Hand").Padding("0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        this.ConMap.Set(ch, name)
    }

    _RegisterCharEvents() {
        for ch, name in this.ConMap
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnCharBtnClick").Bind(ch))
    }

    ;字串相关
    OnCharBtnClick(char, *) {
        this.Str .= char

        this.Refresh()
    }

    Refresh() {
        if (this.SettingTipCon == "" || !IsObject(this.ui))
            return

        tipStr := GetLang("当前配置的触发字串为：")
        tipStr .= this.GetTriggerStr()
        this.ui.Update("SettingTipCon", "Text", tipStr)
        this.ui.Update("IsEndCharCon", "IsChecked", this.IsEndChar ? "True" : "False")
        this.ui.Update("IsSubStrCon", "IsChecked", this.IsSubStr ? "True" : "False")
        this.ui.Update("IsDeleteCon", "IsChecked", this.IsDelete ? "True" : "False")
        this.ui.Update("SaveBtnCtrl", "Visibility", this.showSaveBtn ? "Visible" : "Collapsed")
    }

    GetTriggerStr() {
        triggerStr := ""

        triggerStr .= ":"
        if (this.IsSubStr) {
            triggerStr .= "?"
        }
        if (!this.IsEndChar) {
            triggerStr .= "*"
        }
        if (!this.IsDelete) {
            triggerStr .= "B0"
        }

        triggerStr .= ":"
        triggerStr .= this.Str

        if (this.Str == "")
            triggerStr := ""

        return triggerStr
    }

    Backspace() {
        str := SubStr(this.Str, 1, StrLen(this.Str) - 1)
        this.Str := str
        this.Refresh()
    }

    ClearStr() {
        this.Str := ""
        this.Refresh()
    }

    ;按钮点击回调
    OnSureBtnClick(*) {
        isValid := this.CheckConfigValid()
        if (!isValid)
            return

        triggerStr := this.GetTriggerStr()
        action := this.SureBtnAction
        action(triggerStr)
        this._CloseWindow()
        if (this.SureFocusCon != "")
            this.SureFocusCon.Focus()
    }

    OnSaveBtnClick(*) {
        isValid := this.CheckConfigValid()
        if (!isValid)
            return

        triggerStr := this.GetTriggerStr()
        action := this.SureBtnAction
        action(triggerStr)

        action := this.SaveBtnAction
        action()
        this._CloseWindow()
        if (this.SureFocusCon != "")
            this.SureFocusCon.Focus()
    }

    OnClickNoEndCharCon(*) {
        this.IsEndChar := !this.IsEndChar
        this.Refresh()
    }

    OnClickSubStrCon(*) {
        this.IsSubStr := !this.IsSubStr
        this.Refresh()
    }

    OnClickNoDeleteCon(*) {
        this.IsDelete := !this.IsDelete
        this.Refresh()
    }

    ;数据交互
    Init(triggerStr, showSaveBtn) {
        isValid := SubStr(triggerStr, 1, 1) == ":"
        splitPos := 2
        IsNoEndChar := true
        IsSubStr := true
        IsNoDelete := true
        Str := ""

        if (isValid) {
            splitPos := InStr(triggerStr, ":", false, 2)
            isValid := splitPos != 0 && splitPos <= 6
        }

        if (isValid) {
            pos := InStr(triggerStr, "*", false, 2)
            IsNoEndChar := pos != 0 && pos < splitPos

            pos := InStr(triggerStr, "?", false, 2)
            IsSubStr := pos != 0 && pos < splitPos

            pos := InStr(triggerStr, "B0", false, 2)
            IsNoDelete := pos != 0 && pos < splitPos

            Str := SubStr(triggerStr, splitPos + 1)
        }

        this.Str := Str
        this.IsEndChar := !IsNoEndChar
        this.IsSubStr := IsSubStr
        this.IsDelete := !IsNoDelete
        this.showSaveBtn := showSaveBtn
        return
    }

    CheckConfigValid() {
        len := StrLen(this.Str)
        if (len >= 40) {
            MsgBox(GetLang("字串长度不能超过40,有异议请联系UP: 浮生若梦的兔子。"))
            return false
        }

        return true
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(ui, state, ctrl, event) {
        ; ui 参数防止关旧重建时旧窗口的 Closing 异步回调误清新窗口的 this.ui
        if (this.ui == ui) {
            this.ui := ""
            this._closed := true
        }
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
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
