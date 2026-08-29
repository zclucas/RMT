#Requires AutoHotkey v2.0

; =====================================================================
; 等待编辑器（§16）—— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 19 种等待类型共用「检测间隔 + 轮询」骨架，参数区按类型显隐
; =====================================================================

class WaitGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this.Data := ""
        this.SerialStr := ""
        this.DLVariableArr := []
        ; 类型中文键（执行端 WaitData.WaitType 数字对应）
        this.WaitTypeKeys := ["等待变量值", "等待按键按下", "等待按键松开", "等待屏幕变化", "等待鼠标移动",
            "等待鼠标停止移动", "等待剪切板变化", "等待进程存在", "等待进程关闭", "等待窗口存在",
            "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口关闭", "等待窗口最小化",
            "等待文件存在", "等待文件删除", "等待文件变化", "等待日期"]
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
        this._ShowWindow()
        this.OnTypeChange()
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

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("等待编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "34", "Auto", "40")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,8")
        body.Rows("34", "Auto", "40")
        body.Cols("*")

        ; 行0：备注 + 等待类型
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("备注：")).VerticalAlignment("Center")
        row0.Add("TextBox").Name("RemarkCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        row0.Add("TextBlock").Text(GetLang("等待类型：")).VerticalAlignment("Center").Margin("16,0,0,0")
        wt := row0.Add("ComboBox").Name("WaitTypeCon").Width(160).Height(26).MinHeight(26).Margin("4,0,0,0")
        for t in GetLangArr(this.WaitTypeKeys)
            wt.Add("ComboBoxItem").Content(t)

        ; 行1：参数 GroupBox（各类型面板显隐切换）
        pg := body.Add("GroupBox").Grid_Row(1).Header(GetLang("等待参数："))
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}").Margin("0,6,0,2")
        pStack := pg.Add("StackPanel").Margin("10,8")

        ; 变量值面板：变量名 + 期望值
        vp := pStack.Add("StackPanel").Name("VarPanel").Orientation("Horizontal")
        vp.Add("TextBlock").Text(GetLang("变量名：")).VerticalAlignment("Center")
        vp.Add("ComboBox").Name("VarNameCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        vp.Add("TextBlock").Text(GetLang("期望值：")).VerticalAlignment("Center").Margin("14,0,0,0")
        vp.Add("ComboBox").Name("VarValCon").Width(140).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")

        ; 按键面板
        kp := pStack.Add("StackPanel").Name("KeyPanel").Orientation("Horizontal").Visibility("Collapsed")
        kp.Add("TextBlock").Text(GetLang("按键：")).VerticalAlignment("Center")
        kp.Add("TextBox").Name("KeyCon").Width(160).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; 范围面板：起始X/Y、终止X/Y
        rp := pStack.Add("StackPanel").Name("RangePanel").Visibility("Collapsed")
        rangeRowA := rp.Add("StackPanel").Orientation("Horizontal")
        rangeRowA.Add("TextBlock").Text(GetLang("起始坐标X：")).VerticalAlignment("Center")
        rangeRowA.Add("ComboBox").Name("StartPosX").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowA.Add("TextBlock").Text(GetLang("起始坐标Y：")).VerticalAlignment("Center").Margin("12,0,0,0")
        rangeRowA.Add("ComboBox").Name("StartPosY").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowB := rp.Add("StackPanel").Orientation("Horizontal").Margin("0,6,0,0")
        rangeRowB.Add("TextBlock").Text(GetLang("终止坐标X：")).VerticalAlignment("Center")
        rangeRowB.Add("ComboBox").Name("EndPosX").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")
        rangeRowB.Add("TextBlock").Text(GetLang("终止坐标Y：")).VerticalAlignment("Center").Margin("12,0,0,0")
        rangeRowB.Add("ComboBox").Name("EndPosY").Width(90).Height(24).MinHeight(24).Margin("4,0,0,0").IsEditable("True")

        ; 进程面板
        pp := pStack.Add("StackPanel").Name("ProcPanel").Orientation("Horizontal").Visibility("Collapsed")
        pp.Add("TextBlock").Text(GetLang("进程名：")).VerticalAlignment("Center")
        pp.Add("TextBox").Name("ProcCon").Width(200).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")

        ; 窗口面板
        wp := pStack.Add("StackPanel").Name("WinPanel").Orientation("Horizontal").Visibility("Collapsed")
        wp.Add("TextBlock").Text(GetLang("窗口信息：")).VerticalAlignment("Center")
        wp.Add("TextBox").Name("WinInfoCon").Width(220).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        wp.Add("Button").Name("BtnWinEdit").Content(GetLang("编辑")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")

        ; 文件面板
        fp := pStack.Add("StackPanel").Name("FilePanel").Orientation("Horizontal").Visibility("Collapsed")
        fp.Add("TextBlock").Text(GetLang("文件路径：")).VerticalAlignment("Center")
        fp.Add("TextBox").Name("FilePathCon").Width(240).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        fp.Add("Button").Name("BtnFileBrowse").Content(GetLang("浏览")).Height(24).MinHeight(24).Margin("6,0,0,0").Cursor("Hand")

        ; 日期面板：值 + 单位
        dp := pStack.Add("StackPanel").Name("DatePanel").Orientation("Horizontal").Visibility("Collapsed")
        dp.Add("TextBlock").Text(GetLang("日期值：")).VerticalAlignment("Center")
        dp.Add("TextBox").Name("DateValCon").Width(180).Height(24).MinHeight(24).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        dp.Add("TextBlock").Text(GetLang("单位：")).VerticalAlignment("Center").Margin("12,0,0,0")
        dunit := dp.Add("ComboBox").Name("DateUnitCon").Width(110).Height(24).MinHeight(24).Margin("4,0,0,0")
        for t in GetLangArr(["分钟", "小时", "天", "具体时间", "时间变量"])
            dunit.Add("ComboBoxItem").Content(t)

        ; 行2：检测间隔 + 确定
        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("TextBlock").Text(GetLang("检测间隔(ms)：")).VerticalAlignment("Center")
        btnRow.Add("TextBox").Name("IntervalCon").Width(80).Height(24).MinHeight(24).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(34).MinHeight(34).Margin("16,0,0,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="700" Height="300" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("WaitTypeCon", "SelectionChanged", ObjBindMethod(this, "OnTypeChange"))
        this.ui.OnEvent("BtnWinEdit", "Click", ObjBindMethod(this, "OnClickWinEdit"))
        this.ui.OnEvent("BtnFileBrowse", "Click", ObjBindMethod(this, "OnClickFileBrowse"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    _ShowWindow() {
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

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        } finally {
        }
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
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    _SetCombo(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this.ui.Update(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this.ui.Update(comboName, "AddItem", it)
        }
        this.ui.Update(comboName, "Text", text)
    }

    _TypeValue() {
        v := IsObject(this.ui) ? this.ui.Query("WaitTypeCon>SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) + 1 : 1
    }

    Init(cmd) {
        cmdArr := cmd != "" ? SplitCommand(cmd) : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("等待")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)

        batch := []
        batch.Push({ControlName: "RemarkCon", PropertyName: "Text", Value: cmdArr.Length >= 2 ? cmdArr[2] : ""})
        batch.Push({ControlName: "WaitTypeCon", PropertyName: "SelectedIndex", Value: String(this.Data.WaitType - 1)})
        batch.Push({ControlName: "IntervalCon", PropertyName: "Text", Value: this.Data.Interval})
        batch.Push({ControlName: "VarNameCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "VarValCon", PropertyName: "Text", Value: this.Data.Param2})
        batch.Push({ControlName: "KeyCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "ProcCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "WinInfoCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "FilePathCon", PropertyName: "Text", Value: this.Data.Param1})
        batch.Push({ControlName: "DateValCon", PropertyName: "Text", Value: this.Data.Param1})
        this.ui.BatchUpdate(batch)
        ; 坐标与下拉数据
        this._SetCombo("StartPosX", GetGuiVarArr(), this.Data.StartPosX)
        this._SetCombo("StartPosY", GetGuiVarArr(), this.Data.StartPosY)
        this._SetCombo("EndPosX", GetGuiVarArr(), this.Data.EndPosX)
        this._SetCombo("EndPosY", GetGuiVarArr(), this.Data.EndPosY)
        this._SetCombo("VarNameCon", this.DLVariableArr, this.Data.Param1)
        this._SetCombo("VarValCon", this.DLVariableArr, this.Data.Param2)
        ; 日期单位（Param2 存中文键）
        unitKey := GetLangKey(this.Data.Param2)
        unitIdx := 0
        for k, key in ["分钟", "小时", "天", "具体时间", "时间变量"] {
            if (key == unitKey) {
                unitIdx := k - 1
                break
            }
        }
        if (IsObject(this.ui))
            this.ui.Update("DateUnitCon", "SelectedIndex", String(unitIdx))
    }

    ; 按类型显隐参数面板
    OnTypeChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        t := this._TypeValue()
        panelMap := Map(
            1, "VarPanel", 2, "KeyPanel", 3, "KeyPanel", 4, "RangePanel",
            5, "", 6, "", 7, "",
            8, "ProcPanel", 9, "ProcPanel",
            10, "WinPanel", 11, "WinPanel", 12, "WinPanel", 13, "WinPanel", 14, "WinPanel", 15, "WinPanel",
            16, "FilePanel", 17, "FilePanel", 18, "FilePanel",
            19, "DatePanel"
        )
        show := panelMap.Has(t) ? panelMap[t] : ""
        batch := []
        for name in ["VarPanel", "KeyPanel", "RangePanel", "ProcPanel", "WinPanel", "FilePanel", "DatePanel"] {
            batch.Push({ControlName: name, PropertyName: "Visibility", Value: (name == show) ? "Visible" : "Collapsed"})
        }
        this.ui.BatchUpdate(batch)
    }

    OnClickWinEdit(state := "", ctrl := "", event := "") {
        if (MainSoftData.IsModalSubGui && this.ui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Hwnd()
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "WinInfoCon"))
    }

    OnClickFileBrowse(state := "", ctrl := "", event := "") {
        path := FileSelect(1, this.ui.Query("FilePathCon"), GetLang("选择文件"))
        if (path != "")
            this.ui.Update("FilePathCon", "Text", path)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.ui.Query("RemarkCon"))
        return CommandStr
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveWaitData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        this._CloseWindow()
        if (action != "")
            action(CommandStr)
    }

    CheckIfValid() {
        t := this._TypeValue()
        switch t {
            case 1:    ; 变量值
                if (!CheckVarNameIfValid(this.ui.Query("VarNameCon")))
                    return false
            case 2, 3:    ; 按键
                if (this.ui.Query("KeyCon") == "") {
                    MsgBox(GetLang("请输入等待的按键"))
                    return false
                }
            case 8, 9:    ; 进程
                if (this.ui.Query("ProcCon") == "") {
                    MsgBox(GetLang("请输入进程名"))
                    return false
                }
            case 10, 11, 12, 13, 14, 15:    ; 窗口
                if (this.ui.Query("WinInfoCon") == "") {
                    MsgBox(GetLang("目标窗口信息不能为空"))
                    return false
                }
            case 16, 17, 18:    ; 文件
                if (this.ui.Query("FilePathCon") == "") {
                    MsgBox(GetLang("请输入文件路径"))
                    return false
                }
            case 19:    ; 日期
                if (this.ui.Query("DateValCon") == "") {
                    MsgBox(GetLang("请输入日期值"))
                    return false
                }
        }
        interval := this.ui.Query("IntervalCon")
        if (!IsNumber(interval) || Number(interval) <= 0) {
            MsgBox(GetLang("检测间隔请输入大于0的数字（毫秒）"))
            return false
        }
        return true
    }

    SaveWaitData() {
        this.Data.WaitType := this._TypeValue()
        this.Data.Interval := this.ui.Query("IntervalCon")
        t := this._TypeValue()
        switch t {
            case 1:    ; 变量值
                this.Data.Param1 := GetVarName(this.ui.Query("VarNameCon"))
                this.Data.Param2 := GetLangKey(this.ui.Query("VarValCon"))
            case 2, 3:
                this.Data.Param1 := this.ui.Query("KeyCon")
                this.Data.Param2 := ""
            case 4:
                this.Data.StartPosX := this.ui.Query("StartPosX")
                this.Data.StartPosY := this.ui.Query("StartPosY")
                this.Data.EndPosX := this.ui.Query("EndPosX")
                this.Data.EndPosY := this.ui.Query("EndPosY")
                this.Data.Param1 := ""
                this.Data.Param2 := ""
            case 5, 6, 7:
                this.Data.Param1 := ""
                this.Data.Param2 := ""
            case 8, 9:
                this.Data.Param1 := this.ui.Query("ProcCon")
                this.Data.Param2 := ""
            case 10, 11, 12, 13, 14, 15:
                this.Data.Param1 := this.ui.Query("WinInfoCon")
                this.Data.Param2 := ""
            case 16, 17, 18:
                this.Data.Param1 := this.ui.Query("FilePathCon")
                this.Data.Param2 := ""
            case 19:
                this.Data.Param1 := this.ui.Query("DateValCon")
                this.Data.Param2 := GetLangKey(this.ui.Query("DateUnitCon"))
        }
        SaveMacroCMDData(this.Data)
    }
}
