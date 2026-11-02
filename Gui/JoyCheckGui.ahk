#Requires AutoHotkey v2.0

; =====================================================================
; 手柄检测编辑器 —— 手柄图与手柄指令相同；底部为检测模式/检测类型/结果变量
; 序列号指令：手柄检测N，数据与 KeyCheckData 同结构，存 JoyCheckFile.toml
; =====================================================================

class JoyCheckGui extends JoyGui {
    __new() {
        super.__new()
        this.SerialStr := ""
        this.Data := ""
        this.TriggerAction := (*) => ""
        this._comboAnalog := ""
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        this._analogVis := "Hidden"
        this._btnDefBg := Map()
        this._btnDefBd := Map()
        this._btnKeyMap := Map()
        this._padBtnLayout := Map()
        this._stickLayout := Map()
        this._stickDrag := ""
        this._trigClick := ""
        this._pendingPadClick := ""
        try SetTimer(this._stickTick, 0)
        title := this.ParentTile GetLang("手柄检测")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("14")
        body.Rows("*", "Auto", "48")

        padCard := body.Add("Border").Grid_Row(0).CornerRadius("10").Padding("12")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        vb := padCard.Add("Viewbox").Stretch("Uniform").Margin("0,0,0,16")
        padHost := vb.Add("Grid").Width("640").Height("340")
        this._pad := padHost.Add("Canvas").Name("JoyPadCanvas").Width("640").Height("340").Background("Transparent")
        this._BuildPad()

        paramCard := body.Add("Border").Grid_Row(1).CornerRadius("8").Padding("12").Margin("0,14,0,0")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        param := paramCard.Add("StackPanel")

        check := param.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").MinHeight("26")
        check.Add("TextBlock").Text(GetLang("检测模式:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        cc := check.Add("ComboBox").Name("CheckTypeCon").Width(140).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["同时按下", "有一个按下"])
            cc.Add("ComboBoxItem").Content(t)
        check.Add("TextBlock").Text(GetLang("检测类型:")).VerticalAlignment("Center").Margin("14,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        st := check.Add("ComboBox").Name("StateTypeCon").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["物理状态", "逻辑状态"])
            st.Add("ComboBoxItem").Content(t)
        check.Add("TextBlock").Text(GetLang("结果变量：")).VerticalAlignment("Center").Margin("14,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        check.Add("ComboBox").Name("VarNameCon").Width(130).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        analogRow := param.Add("StackPanel").Name("AnalogRow").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,8,0,0").MinHeight("26").Height("26").Visibility("Hidden")
        analogRow.Add("TextBlock").Name("AxisTip1").Text("LX").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12").Width("28")
        analogRow.Add("Slider").Name("AxisSlider1").Width("180").Height("26").Minimum("-100").Maximum("100").Value("100").IsMoveToPointEnabled("True").VerticalAlignment("Center")
        analogRow.Add("TextBox").Name("AxisVal1").Width("48").Height(26).MinHeight(26).Margin("6,0,16,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        analogRow.Add("TextBlock").Name("AxisTip2").Text("LY").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12").Width("28")
        analogRow.Add("Slider").Name("AxisSlider2").Width("180").Height("26").Minimum("-100").Maximum("100").Value("0").IsMoveToPointEnabled("True").VerticalAlignment("Center")
        analogRow.Add("TextBox").Name("AxisVal2").Width("48").Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        clearBtn := btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(88).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
            .Margin("0,0,250,0")
        clearBtn.InjectResources(FrontInfoGui._OkBtnHoverStyle())
        AddCmdOkBtn(btnRow, "BtnOk")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="720" Height="590"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this._RegisterPadEvents()
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/29-手柄检测")
        this.ui.OnEvent("JoyPadCanvas", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnPadMouseDown"))
        this.ui.OnEvent("JoyPadCanvas", "PreviewMouseMove", ObjBindMethod(this, "OnPadMouseMove"))
        this.ui.OnEvent("JoyPadCanvas", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnPadMouseUp"))
        this.ui.OnEvent("AxisSlider1", "ValueChanged", ObjBindMethod(this, "OnAxisSlider", 1))
        this.ui.OnEvent("AxisSlider2", "ValueChanged", ObjBindMethod(this, "OnAxisSlider", 2))
        this.ui.OnEvent("AxisVal1", "TextChanged", ObjBindMethod(this, "OnAxisText", 1))
        this.ui.OnEvent("AxisVal2", "TextChanged", ObjBindMethod(this, "OnAxisText", 2))
        this.ui.OnEvent("AxisVal1", "LostFocus", ObjBindMethod(this, "OnAxisTextCommit", 1))
        this.ui.OnEvent("AxisVal2", "LostFocus", ObjBindMethod(this, "OnAxisTextCommit", 2))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearAll())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.Update("CheckTypeCon", "SelectedIndex", "0")
        this.ui.Update("StateTypeCon", "SelectedIndex", "0")
    }

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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("手柄检测")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.Mode := "digital"
        this.CheckedArr := []
        this.AxisMap := Map()
        this._axisGroup := ""
        this._comboAnalog := ""

        if (IsObject(this.Data) && this.Data.HasOwnProp("KeyArr")) {
            for k in this.Data.KeyArr {
                if (RegExMatch(k, "^JoyAxis(L[XY]|R[XY]|LT|RT):(-?[0-9]+)$", &m)) {
                    this.AxisMap[m[1]] := Integer(m[2])
                    continue
                }
                short := JoyInternalToShort(k)
                this.CheckedArr.Push(short != "" ? short : k)
            }
        }

        this._ApplyLtRtMode()
        if (this.AxisMap.Count > 0) {
            this.CheckedArr := []
            if (this.AxisMap.Has("LX") || this.AxisMap.Has("LY"))
                this._axisGroup := "AxisLS"
            else if (this.AxisMap.Has("RX") || this.AxisMap.Has("RY"))
                this._axisGroup := "AxisRS"
            else if (this.AxisMap.Has("LT"))
                this._axisGroup := "AxisLT"
            else if (this.AxisMap.Has("RT"))
                this._axisGroup := "AxisRT"
            this._NormalizeStickPair("")
            this._SyncAxisControls()
        }

        analog := this.AxisMap.Count > 0
        ct := this.Data.CheckType ? Integer(this.Data.CheckType) : 1
        this._FillCheckTypeCombo(analog, ct - 1)
        this.ui.Update("StateTypeCon", "SelectedIndex", String((this.Data.StateType ? this.Data.StateType : 1) - 1))
        this._SetCombo("VarNameCon", GetGuiVarArr(), this.Data.VarName != "" ? this.Data.VarName : "Var1")
        this._RefreshPadHighlight()
        this.Refresh()
    }

    _AnalogCheckItems() {
        return GetLangArr(["大于设定值", "大于等于", "等于设定值", "小于等于", "小于设定值"])
    }

    _DigitalCheckItems() {
        return GetLangArr(["同时按下", "有一个按下"])
    }

    _FillCheckTypeCombo(analog, idx) {
        items := analog ? this._AnalogCheckItems() : this._DigitalCheckItems()
        this.ui.Update("CheckTypeCon", "ClearItems", "")
        for it in items
            this.ui.Update("CheckTypeCon", "AddItem", it)
        maxIdx := items.Length - 1
        if (!IsNumber(idx) || Integer(idx) < 0 || Integer(idx) > maxIdx)
            idx := 0
        this.ui.Update("CheckTypeCon", "SelectedIndex", String(Integer(idx)))
        this._comboAnalog := analog
    }

    _EnsureCheckModeCombo() {
        analog := this.AxisMap.Count > 0
        if (this._comboAnalog != "" && this._comboAnalog == analog)
            return
        try this._FillCheckTypeCombo(analog, 0)
    }

    _OnLiveAnalogPicked() {
        this.CheckedArr := []
    }

    OnPadClick(id, *) {
        if (this._IsAnalogId(id)) {
            this.CheckedArr := []
        } else if (this.AxisMap.Count > 0 && !this._AnalogSelected(id)) {
            this.AxisMap := Map()
            this._axisGroup := ""
        }
        super.OnPadClick(id)
    }

    _ApplyAnalogFromPoint(id, px, py) {
        if (this.CheckedArr.Length > 0)
            this.CheckedArr := []
        super._ApplyAnalogFromPoint(id, px, py)
        this._EnsureCheckModeCombo()
    }

    UpdateCommandStr() {
        this.CommandStr := ""
    }

    _ShowCommandStr() {
    }

    Refresh() {
        this._JoyLog("JoyCheck Refresh begin")
        try this._EnsureCheckModeCombo()
        catch as e
            this._JoyLog("JoyCheck combo FAIL " e.Message " L" e.Line)
        this._SyncAnalogRowVis()
        this._UpdateAnalogVisuals()
        this._JoyLog("JoyCheck Refresh end")
    }

    CheckIfValid() {
        if (this.AxisMap.Count == 0 && this.CheckedArr.Length == 0) {
            RmtDialog.Info(GetLang("请选择要检测的手柄按键！"))
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
        return Format("{}{}", GetLang(textOnly), numbersOnly)
    }

    SaveJoyCheckData() {
        data := this.Data
        data.KeyArr := []
        for v in this.CheckedArr {
            inn := JoyShortToInternal(v)
            data.KeyArr.Push(inn != "" ? inn : v)
        }
        order := ["LX", "LY", "RX", "RY", "LT", "RT"]
        for name in order {
            if (this.AxisMap.Has(name))
                data.KeyArr.Push("JoyAxis" name ":" this.AxisMap[name])
        }
        data.CheckType := IsObject(this.ui) ? (Integer(this.ui.Query("CheckTypeCon>SelectedIndex")) + 1) : 1
        data.StateType := IsObject(this.ui) ? (Integer(this.ui.Query("StateTypeCon>SelectedIndex")) + 1) : 1
        data.VarName := GetVarName(this.ui.Query("VarNameCon"))
        MySoftData.GlobalVariMap[data.VarName] := true
        SaveMacroCMDData(data)
    }

    OnSureBtnClick(*) {
        if (!this.CheckIfValid())
            return
        this.SaveJoyCheckData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.OnGuiClose()
    }

    ToggleFunc(state) {
    }

    TriggerMacro(*) {
    }
}
