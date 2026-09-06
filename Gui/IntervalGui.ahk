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

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

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
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容：TabControl（常规 / 错误处理）===
        tc := main.Add("TabControl").Grid_Row(1).Margin("12,10,12,8").Name("MainTab")

        ; ---- Tab1 常规 ----
        ti1 := tc.Add("TabItem").Header(GetLang("常规"))
        body := ti1.Add("Grid").Margin("16,14,16,14")
        body.Rows("34", "34", "34", "34", "*")
        ; 备注（阶段5）：放选项卡第一个位置
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("备注：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        row0.Add("TextBox").Name("RemarkCon").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        row1 := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("类型：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        combo := row1.Add("ComboBox").Name("TypeCombo").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").SelectedIndex("0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        combo.Add("ComboBoxItem").Content(GetLang("固定")).Tag("1")
        combo.Add("ComboBoxItem").Content(GetLang("随机")).Tag("2")

        row2 := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        row2.Add("TextBlock").Text(GetLang("时间(毫秒)：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        row2.Add("ComboBox").Name("TimeVarCon1").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        row3 := body.Add("StackPanel").Name("TimeRow2").Grid_Row(3).Orientation("Horizontal").VerticalAlignment("Center")
        row3.Add("TextBlock").Text(GetLang("时间(毫秒)：")).Width(92).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        row3.Add("ComboBox").Name("TimeVarCon2").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0").IsEditable("True")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        btnRow := body.Add("StackPanel").Grid_Row(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

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
        ehBtnRow.Add("Button").Name("BtnOk2").Content(GetLang("确定")).Width(100).Height(36).MinHeight(36)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="340" Height="330" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("TypeCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("EHModeCombo", "SelectionChanged", ObjBindMethod(this, "OnEHModeChange"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnOk2", "Click", ObjBindMethod(this, "OnClickSureBtn"))

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
        v := IsObject(this.ui) ? this.ui.Query("TypeCombo") : ""
        return IsNumber(v) ? Integer(v) : 1
    }

    Init(cmd) {
        ; 阶段5：指令改为配置文件模式（间隔<serial> → Ini JSON）。
        ; 兼容旧格式 间隔_500（无序列号）：解析参数填充，点确定保存时才生成序列码
        ; 兼容历史 |EH: 后缀（如有）：剥离后作为错误处理初值
        eh := RMTParseErrHandle(cmd)
        cmd := eh.cmd
        this._ehCfg := eh.cfg

        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        DLVarArr := GetGuiVarArr()
        ; 备注：指令串第二段（间隔<serial>_备注 或 旧 间隔_时间 均取第二段）
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")

        this.Data := IntervalData()
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            ; 新格式：间隔<serial> → 读配置文件
            this.Data := GetMacroCMDData(cmdArr[1])
            this._InitFromData()
        } else if (cmdArr.Length <= 1) {
            this.ui.Update("TypeCombo", "SelectedIndex", "0")
            this._SetCombo("TimeVarCon1", DLVarArr, "500")
            this._SetCombo("TimeVarCon2", DLVarArr, "1000")
        } else {
            ; 旧格式：间隔_500 或 间隔_100~200
            TimeArr := StrSplit(cmdArr[2], "~")
            if (TimeArr.Length <= 1) {
                this.ui.Update("TypeCombo", "SelectedIndex", "0")
                this._SetCombo("TimeVarCon1", DLVarArr, cmdArr[2])
                this._SetCombo("TimeVarCon2", DLVarArr, "1000")
            } else {
                this.ui.Update("TypeCombo", "SelectedIndex", "1")
                this._SetCombo("TimeVarCon1", DLVarArr, TimeArr[1])
                this._SetCombo("TimeVarCon2", DLVarArr, TimeArr[2])
            }
        }
        this.OnTypeChange()
        this._InitEH()
    }

    ; 从 Data 回填 UI（新格式读取）
    _InitFromData() {
        DLVarArr := GetGuiVarArr()
        this.ui.Update("TypeCombo", "SelectedIndex", this.Data.Type == 2 ? "1" : "0")
        this._SetCombo("TimeVarCon1", DLVarArr, this.Data.Time1)
        this._SetCombo("TimeVarCon2", DLVarArr, this.Data.Time2)
    }

    ; 初始化错误处理页（阶段5：错误处理配置存 Data，随指令配置文件持久化）
    _InitEH() {
        mode := this.Data.HasOwnProp("ErrMode") ? this.Data.ErrMode : "stop"
        ; 历史 |EH: 后缀优先（兼容旧数据）
        if (IsObject(this._ehCfg))
            mode := this._ehCfg.mode
        idx := 0
        for i, m in ["stop", "ignore", "retry"] {
            if (m == mode) {
                idx := i - 1
                break
            }
        }
        this.ui.Update("EHModeCombo", "SelectedIndex", String(idx))
        this.ui.Update("EHRetryCount", "Text", this.Data.HasOwnProp("ErrRetryCount") ? this.Data.ErrRetryCount : "3")
        this.ui.Update("EHRetryInterval", "Text", this.Data.HasOwnProp("ErrRetryInterval") ? this.Data.ErrRetryInterval : "500")
        this.OnEHModeChange()
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

    ; 组装 Data 并保存到配置文件，返回 间隔<serial>_备注 指令字符串（阶段5）
    GetCmdStr() {
        this.Data.Type := this._TypeValue()
        this.Data.Time1 := this.ui.Query("TimeVarCon1")
        this.Data.Time2 := this.ui.Query("TimeVarCon2")
        ; 错误处理
        this.Data.ErrMode := ["stop", "ignore", "retry"][this._EHMode() + 1]
        this.Data.ErrRetryCount := this.ui.Query("EHRetryCount")
        this.Data.ErrRetryInterval := this.ui.Query("EHRetryInterval")

        ; 生成序列码（首次保存分配，后续复用）
        if (!this.Data.HasOwnProp("SerialStr") || this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("间隔"))
        SaveMacroCMDData(this.Data)
        ; 备注：用户备注优先，为空则自动生成操作内容
        remark := Trim(this.ui.Query("RemarkCon"))
        if (remark == "")
            remark := this.Data.Type == 2
                ? this.Data.Time1 "~" this.Data.Time2
                : this.Data.Time1
        return CorrectRemark(this.Data.SerialStr, remark)
    }

    OnTypeChange(state := "", ctrl := "", event := "") {
        showTime2 := this._TypeValue() == 2
        if (IsObject(this.ui))
            this.ui.Update("TimeRow2", "Visibility", showTime2 ? "Visible" : "Collapsed")
    }

    OnClickSureBtn(state, ctrl, event) {
        if (this.SureBtnAction == "")
            return

        timeText := this.ui.Query("TimeVarCon1")
        if (IsNumber(timeText)) {
            if (IsFloat(timeText) || timeText < 0) {
                MsgBox(GetLang("请输入大于0的整数"))
                return
            }
        }

        if (this._TypeValue() == 2) {
            timeText := this.ui.Query("TimeVarCon2")
            if (IsNumber(timeText)) {
                if (IsFloat(timeText) || timeText < 0) {
                    MsgBox(GetLang("请输入大于0的整数"))
                    return
                }
            }

            if (IsNumber(this.ui.Query("TimeVarCon1")) && IsNumber(this.ui.Query("TimeVarCon2"))) {
                if (this.ui.Query("TimeVarCon1") >= this.ui.Query("TimeVarCon2")) {
                    MsgBox(GetLang("上面的时间需要小于下面的时间"))
                    return
                }
            }
        }

        action := this.SureBtnAction
        action(this.GetCmdStr())
        this._CloseWindow()
    }
}
