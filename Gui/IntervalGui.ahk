#Requires AutoHotkey v2.0

; =====================================================================
; 间隔编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class IntervalGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._batching := true
        try this.Init(cmd)
        finally {
            this._flushBatch()
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ; batching 中入队，_flushBatch 一次性 BatchUpdate（合并 Init 的多次 Update 为一次 IPC）
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
        title := this.ParentTile GetLang("间隔编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,12,16,16")
        body.Rows("Auto", "Auto", "Auto")

        card := body.Add("Border").Grid_Row(0).CornerRadius("6").Padding("14,12")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        form := card.Add("Grid")
        form.Rows("34", "34", "34", "34")
        form.Cols("80", "*")

        form.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        form.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("RemarkCon").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        form.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("类型：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        combo := form.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("TypeCombo").Height(26).MinHeight(26).SelectedIndex("0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        combo.Add("ComboBoxItem").Content(GetLang("固定")).Tag("1")
        combo.Add("ComboBoxItem").Content(GetLang("随机")).Tag("2")

        form.Add("TextBlock").Grid_Row(2).Grid_Column(0).Name("TimeTip1").Text(GetLang("时间A：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        form.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("TimeVarCon1").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        timeRow2 := form.Add("Grid").Name("TimeRow2").Grid_Row(3).Grid_ColumnSpan(2).Visibility("Collapsed")
        timeRow2.Cols("80", "*")
        timeRow2.Add("TextBlock").Grid_Column(0).Text(GetLang("时间B：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        timeRow2.Add("ComboBox").Grid_Column(1).Name("TimeVarCon2").Height(26).MinHeight(26).IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(1).Margin("2,6,2,0").Text(GetLang("单位：毫秒"))
            .Foreground("{DynamicResource TextSub}").FontSize("11")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Top").Margin("0,4,0,8")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="380" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/1-间隔")
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
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

    ; 设置可编辑 ComboBox 候选项 + 当前文本
    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        this._ComboPush(comboName, "Text", text)
    }

    _TypeValue() {
        v := IsObject(this.ui) ? this.ui.Query("TypeCombo>SelectedIndex") : ""
        return CmdEnumFromIndex(v, CmdEnumIntervalNames())
    }

    Init(cmd) {
        global MySoftData
        cmd := RMTParseErrHandle(cmd).cmd
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVarArr := GetGuiVarArr()
        this.Data := IntervalData()
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "" && MySoftData.DataFileMap.Has(textOnly)) {
            this.Data := GetMacroCMDData(cmdArr[1])
            this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
            this.ui.Update("TypeCombo", "SelectedIndex", CmdEnumZh(this.Data.Type, CmdEnumIntervalNames()) == "随机" ? "1" : "0")
            this._SetCombo("TimeVarCon1", DLVarArr, this.Data.Time1)
            this._SetCombo("TimeVarCon2", DLVarArr, this.Data.Time2)
        } else if (cmdArr.Length <= 1) {
            this.ui.Update("RemarkCon", "Text", "")
            this.ui.Update("TypeCombo", "SelectedIndex", "0")
            this._SetCombo("TimeVarCon1", DLVarArr, "500")
            this._SetCombo("TimeVarCon2", DLVarArr, "1000")
        } else {
            ; 间隔_时间A_备注  /  间隔_时间A~时间B_备注
            timePart := cmdArr[2]
            remark := ""
            if (cmdArr.Length >= 3) {
                remark := cmdArr[3]
                loop cmdArr.Length - 3
                    remark .= "_" cmdArr[A_Index + 3]
            }
            this.ui.Update("RemarkCon", "Text", remark)
            TimeArr := StrSplit(timePart, "~")
            if (TimeArr.Length <= 1) {
                this.ui.Update("TypeCombo", "SelectedIndex", "0")
                this._SetCombo("TimeVarCon1", DLVarArr, timePart)
                this._SetCombo("TimeVarCon2", DLVarArr, "1000")
            } else {
                this.ui.Update("TypeCombo", "SelectedIndex", "1")
                this._SetCombo("TimeVarCon1", DLVarArr, TimeArr[1])
                this._SetCombo("TimeVarCon2", DLVarArr, TimeArr[2])
            }
        }
        this.OnTypeChange()
    }

    ; 间隔_时间A_备注  /  间隔_时间A~时间B_备注
    GetCmdStr() {
        time1 := this.ui.Query("TimeVarCon1")
        timePart := this._TypeValue() == "随机" ? time1 "~" this.ui.Query("TimeVarCon2") : time1
        return CorrectRemark(GetLang("间隔") "_" timePart, Trim(this.ui.Query("RemarkCon")))
    }

    OnTypeChange(state := "", ctrl := "", event := "") {
        showTime2 := this._TypeValue() == "随机"
        if (IsObject(this.ui))
            this.ui.Update("TimeRow2", "Visibility", showTime2 ? "Visible" : "Collapsed")
    }

    OnClickSureBtn(state, ctrl, event) {
        if (this.SureBtnAction == "")
            return

        timeText := this.ui.Query("TimeVarCon1")
        if (IsNumber(timeText)) {
            if (IsFloat(timeText) || timeText < 0) {
                RmtDialog.Info(GetLang("请输入大于0的整数"))
                return
            }
        }

        if (this._TypeValue() == "随机") {
            timeText := this.ui.Query("TimeVarCon2")
            if (IsNumber(timeText)) {
                if (IsFloat(timeText) || timeText < 0) {
                    RmtDialog.Info(GetLang("请输入大于0的整数"))
                    return
                }
            }

            if (IsNumber(this.ui.Query("TimeVarCon1")) && IsNumber(this.ui.Query("TimeVarCon2"))) {
                if (this.ui.Query("TimeVarCon1") >= this.ui.Query("TimeVarCon2")) {
                    RmtDialog.Info(GetLang("时间A 需要小于 时间B"))
                    return
                }
            }
        }

        action := this.SureBtnAction
        action(this.GetCmdStr())
        this._CloseWindow()
    }
}
