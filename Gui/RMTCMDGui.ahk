#Requires AutoHotkey v2.0

; =====================================================================
; RMT指令编辑器 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; =====================================================================

class RMTCMDGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.CategoriesArr := [GetLang("全部"), GetLang("图文"), GetLang("输入控制"),
        GetLang("宏控制"), GetLang("调试"), GetLang("软件自身")]
        this.CategoriesMap := Map(
            GetLang("图文"), [
                GetLang("截图"),
                GetLang("截图提取文本"),
                GetLang("自由贴")
            ],
            GetLang("输入控制"), [
                GetLang("启用鼠标"),
                GetLang("启用键盘"),
                GetLang("启用键鼠"),
                GetLang("禁用鼠标"),
                GetLang("禁用键盘"),
                GetLang("禁用键鼠"),
                GetLang("启用鼠标加速"),
                GetLang("禁用鼠标加速")
            ],
            GetLang("宏控制"), [
                GetLang("显示菜单"),
                GetLang("关闭菜单"),
                GetLang("打开界面窗口"),
                GetLang("关闭界面窗口"),
                GetLang("禁用模块"),
                GetLang("取消禁用模块"),
                GetLang("暂停所有宏"),
                GetLang("恢复所有宏"),
                GetLang("终止所有宏")
            ],
            GetLang("调试"), [
                GetLang("开启变量监视"),
                GetLang("关闭变量监视"),
                GetLang("开启指令显示"),
                GetLang("关闭指令显示"),
            ],
            GetLang("软件自身"), [
                GetLang("关闭软件"),
                GetLang("休眠"),
                GetLang("重载")
            ],
        )
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
        this.OnCmdChange()
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
        title := this.ParentTile GetLang("RMT指令编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容：TabControl（常规 / 错误处理）===
        tc := main.Add("TabControl").Grid_Row(1).Margin("8,8,8,8").Name("MainTab")

        ; ---- Tab1 常规 ----
        ti1 := tc.Add("TabItem").Header(GetLang("常规"))
        body := ti1.Add("Grid").Margin("15,14,15,14")
        body.Rows("40", "40", "40", "40", "40", "*")
        body.Cols("80", "*")

        ; 备注（放选项卡第一个位置）
        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Name("RemarkCon").Width(180).Height(26).MinHeight(26).HorizontalAlignment("Left")
            .VerticalContentAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("类别：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        cat := body.Add("ComboBox").Grid_Row(1).Grid_Column(1).Name("CategoryCombo").Width(180).Height(26).MinHeight(26).HorizontalAlignment("Left")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for c in this.CategoriesArr
            cat.Add("ComboBoxItem").Content(c)

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("指令：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Name("CmdTypeCombo").Width(180).Height(26).MinHeight(26).HorizontalAlignment("Left")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        menuRow := body.Add("StackPanel").Name("MenuRow").Grid_Row(3).Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        menuRow.Add("TextBlock").Text(GetLang("菜单序号：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        menuRow.Add("ComboBox").Name("MenuDLCombo").Width(120).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; §2 禁用模块/取消禁用模块：目标页签 + 目标模块 两个下拉（指令选中时显示）
        foldParamRow := body.Add("StackPanel").Name("FoldParamRow").Grid_Row(4).Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        foldParamRow.Add("TextBlock").Text(GetLang("页签：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        foldParamRow.Add("ComboBox").Name("TabCombo").Width(110).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        foldParamRow.Add("TextBlock").Text(GetLang("模块：")).VerticalAlignment("Center").Margin("10,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        foldParamRow.Add("ComboBox").Name("FoldCombo").Width(150).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        btnRow := body.Add("StackPanel").Grid_Row(5).Grid_ColumnSpan(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0")

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

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="310" SizeToContent="Height" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("CategoryCombo", "SelectionChanged", ObjBindMethod(this, "OnTypeChane"))
        this.ui.OnEvent("CmdTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnCmdChange"))
        this.ui.OnEvent("TabCombo", "SelectionChanged", ObjBindMethod(this, "OnTabComboChange"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("EHModeCombo", "SelectionChanged", ObjBindMethod(this, "OnEHModeChange"))
        this.ui.OnEvent("BtnOk2", "Click", ObjBindMethod(this, "OnSureBtnClick"))

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

    _SetDDL(comboName, items, text) {
        if (!IsObject(this.ui))
            return
        this._ComboPush(comboName, "ClearItems", "")
        for it in items {
            if (it == "")
                continue
            this._ComboPush(comboName, "AddItem", it)
        }
        for i, it in items {
            if (it == text) {
                this._ComboPush(comboName, "SelectedIndex", String(i - 1))
                return
            }
        }
        this._ComboPush(comboName, "SelectedIndex", "0")
    }

    Init(cmd) {
        ; 阶段5：指令配置化。新格式 RMT指令<serial> 读配置文件；旧格式 RMT指令_类别_指令[_序号] 兼容
        eh := RMTParseErrHandle(cmd)
        cmd := eh.cmd
        this._ehCfg := eh.cfg
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        ; 统一初始化 Data（旧格式/新建也赋值，错误处理页可读写）
        this.Data := RMTCMDData()
        ; 备注：指令串第二段（RMT指令<serial>_备注 或 旧 RMT指令_类别_指令 取第二段）
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            ; 新格式：读配置文件 Data
            this.Data := GetMacroCMDData(cmdArr[1])
            cmdCategory := this.Data.Category
            cmdStr := this.Data.CmdStr
            menuDLIndex := this.Data.HasOwnProp("MenuIndex") ? this.Data.MenuIndex : 1
        } else if (cmdArr.Length >= 4) {
            cmdCategory := cmdArr[2]
            cmdStr := cmdArr[3]
            menuDLIndex := cmdStr == GetLang("显示菜单") && cmdArr.Length >= 5 ? Integer(cmdArr[4]) : 1
        } else if (cmdArr.Length >= 3) {
            cmdCategory := cmdArr[2]
            cmdStr := cmdArr[3]
            menuDLIndex := 1
        } else {
            cmdCategory := GetLang("全部")
            cmdStr := GetLang("截图")
            menuDLIndex := 1
        }

        this.InitCategoriesMap()
        Category := cmdCategory
        CmdStrArr := this.CategoriesMap[Category]

        this._SetDDL("CategoryCombo", this.CategoriesArr, Category)
        this._SetDDL("CmdTypeCombo", CmdStrArr, cmdStr)

        tableItem := GetTableBySymbol("Menu")
        DropDownArr := []
        if (tableItem) {
            for f, fold in tableItem.Folds {
                DropDownArr.Push(f ". " fold.Remark)
            }
        }
        this.ui.Update("MenuDLCombo", "ClearItems", "")
        for it in DropDownArr
            this.ui.Update("MenuDLCombo", "AddItem", it)
        this.ui.Update("MenuDLCombo", "SelectedIndex", String(menuDLIndex - 1))

        ; §2 禁用模块/取消禁用模块：页签+模块 回显
        this._tabSymbols := this._FoldTabSymbols()
        tabItems := []
        for symbol in this._tabSymbols {
            t := GetTableBySymbol(symbol)
            tabItems.Push(t ? GetLang(t.Name) : symbol)
        }
        this._SetDDL("TabCombo", tabItems, tabItems.Length >= 1 ? tabItems[1] : "")
        selSymbol := (this.Data.HasOwnProp("TableSymbol") && this.Data.TableSymbol != "") ? this.Data.TableSymbol : (this._tabSymbols.Length >= 1 ? this._tabSymbols[1] : "")
        selTable := GetTableBySymbol(selSymbol)
        this._SetDDL("TabCombo", tabItems, selTable ? GetLang(selTable.Name) : (tabItems.Length >= 1 ? tabItems[1] : ""))
        foldItems := []
        if (selTable) {
            for f, fold in selTable.Folds
                foldItems.Push(f ". " fold.Remark)
        }
        foldSelText := ""
        if (this.Data.HasOwnProp("FoldID") && this.Data.FoldID != "" && selTable) {
            for f, fd in selTable.Folds {
                if (fd.ID == this.Data.FoldID) {
                    foldSelText := f ". " fd.Remark
                    break
                }
            }
        }
        this._SetDDL("FoldCombo", foldItems, foldSelText != "" ? foldSelText : (foldItems.Length >= 1 ? foldItems[1] : ""))
        this._InitEH()
    }

    ; ============ 错误处理（阶段5，影刀模式）============

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

    OnTypeChane(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        Category := this.ui.Query("CategoryCombo")
        CmdStrArr := this.CategoriesMap[Category]
        this._SetDDL("CmdTypeCombo", CmdStrArr, CmdStrArr.Length >= 1 ? CmdStrArr[1] : "")
        this.OnCmdChange()
    }

    ; 操作类型 DropDownList Change 处理
    OnCmdChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        CmdStr := this.ui.Query("CmdTypeCombo")
        IsShowMenuDL := CmdStr == GetLang("显示菜单")
        this.ui.Update("MenuRow", "Visibility", IsShowMenuDL ? "Visible" : "Collapsed")
        ; §2 禁用模块/取消禁用模块：显示目标页签+模块参数行
        IsShowFoldParam := CmdStr == GetLang("禁用模块") || CmdStr == GetLang("取消禁用模块")
        this.ui.Update("FoldParamRow", "Visibility", IsShowFoldParam ? "Visible" : "Collapsed")
    }

    ; §2 页签下拉切换：刷新模块下拉为该页签下的模块列表
    OnTabComboChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || !IsObject(this._tabSymbols))
            return
        tabIdx := Integer(this.ui.Query("TabCombo>SelectedIndex")) + 1
        if (tabIdx < 1 || tabIdx > this._tabSymbols.Length)
            return
        tableItem := GetTableBySymbol(this._tabSymbols[tabIdx])
        items := []
        if (tableItem) {
            for f, fold in tableItem.Folds {
                items.Push(f ". " fold.Remark)
            }
        }
        this._SetDDL("FoldCombo", items, items.Length >= 1 ? items[1] : "")
    }

    ; 列出可选「禁用模块」的页签（宏相关表，排除非配置表）
    _FoldTabSymbols() {
        global MySoftData
        symbols := []
        for tableItem in MySoftData.TableInfo {
            switch tableItem.Symbol {
                case "Tool", "Setting", "Help", "Reward", "Thank":
                    continue
            }
            symbols.Push(tableItem.Symbol)
        }
        return symbols
    }

    OnSureBtnClick(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        CommandStr := this.GetCmdStr()
        this.SureBtnAction.Call(CommandStr)
        this._CloseWindow()
    }

    ; 阶段5：指令配置化——组装 Data 保存到配置文件，返回 RMT指令<serial>_备注
    GetCmdStr() {
        if (!IsObject(this.Data))
            this.Data := RMTCMDData()
        this.Data.Category := this.ui.Query("CategoryCombo")
        this.Data.CmdStr := this.ui.Query("CmdTypeCombo")
        this.Data.OperateType := 0   ; 旧字段占位（保留兼容）
        this.Data.MenuIndex := this.ui.Query("CmdTypeCombo") == GetLang("显示菜单")
            ? (Integer(this.ui.Query("MenuDLCombo>SelectedIndex")) + 1) : 1
        ; §2 禁用模块/取消禁用模块：保存目标页签符号 + 模块路径身份
        if (this.Data.CmdStr == GetLang("禁用模块") || this.Data.CmdStr == GetLang("取消禁用模块")) {
            tabIdx := Integer(this.ui.Query("TabCombo>SelectedIndex")) + 1
            foldIdx := Integer(this.ui.Query("FoldCombo>SelectedIndex")) + 1
            if (IsObject(this._tabSymbols) && tabIdx >= 1 && tabIdx <= this._tabSymbols.Length) {
                selTable := GetTableBySymbol(this._tabSymbols[tabIdx])
                this.Data.TableSymbol := this._tabSymbols[tabIdx]
                this.Data.FoldID := (selTable && foldIdx >= 1 && foldIdx <= selTable.Folds.Length) ? selTable.Folds[foldIdx].ID : ""
            }
        }
        ; 错误处理（阶段5）
        this.Data.ErrMode := ["stop", "ignore", "retry"][this._EHMode() + 1]
        this.Data.ErrRetryCount := this.ui.Query("EHRetryCount")
        this.Data.ErrRetryInterval := this.ui.Query("EHRetryInterval")

        if (this.Data.SerialStr == "")
            this.Data.SerialStr := GetCMDSerialStr(GetLang("RMT指令"))
        SaveMacroCMDData(this.Data)
        ; 备注：用户备注优先，为空则自动生成操作内容
        remark := Trim(this.ui.Query("RemarkCon"))
        if (remark == "")
            remark := this.Data.CmdStr
        return CorrectRemark(this.Data.SerialStr, remark)
    }

    CheckIfValid() {
        cmd := this.ui.Query("CmdTypeCombo")
        if (cmd == GetLang("禁用键鼠") || cmd == GetLang("禁用鼠标") || cmd == GetLang("禁用键盘")) {
            if (cmd == GetLang("禁用鼠标"))
                tipBody := GetLang("此操作将 立即禁用鼠标输入，您将无法通过鼠标操作计算机！")
            else if (cmd == GetLang("禁用键盘"))
                tipBody := GetLang("此操作将 立即禁用键盘输入，您将无法通过键盘操作计算机！")
            else
                tipBody := GetLang("此操作将 立即禁用键盘和鼠标输入，您将无法通过键鼠操作计算机！")
            tipStr := Format("{}`n{}`n{}`n{}`n{}", tipBody, GetLang("重要须知："), GetLang(
                "- 以管理员身份运行本软件，否则该指令无效。"), GetLang("- 务必后续执行对应的启用指令，否则输入设备将保持禁用状态！"), GetLang("是否确认禁用？"))
            title := cmd == GetLang("禁用鼠标") ? GetLang("禁用鼠标（需管理员权限）")
                : (cmd == GetLang("禁用键盘") ? GetLang("禁用键盘（需管理员权限）") : GetLang("禁用键鼠（需管理员权限）"))
            if (MsgBox(tipStr, title, "4") == "No")
                return false
        }

        if (cmd == GetLang("启用键鼠") || cmd == GetLang("启用鼠标") || cmd == GetLang("启用键盘")) {
            title := cmd == GetLang("启用鼠标") ? GetLang("启用鼠标（需管理员权限）")
                : (cmd == GetLang("启用键盘") ? GetLang("启用键盘（需管理员权限）") : GetLang("启用键鼠（需管理员权限）"))
            MsgBox(GetLang("- 必须 以管理员身份运行本软件，否则该指令无效。"), title)
        }
        return true
    }

    GetCommandStr() {
        ; CMD格式: RMT指令_类别_指令 或 RMT指令_类别_指令_序号
        CommandStr := Format("{}_{}_{}", GetLang("RMT指令"), this.ui.Query("CategoryCombo"), this.ui.Query("CmdTypeCombo"))
        if (this.ui.Query("CmdTypeCombo") == GetLang("显示菜单")) {
            idx := Integer(this.ui.Query("MenuDLCombo>SelectedIndex")) + 1
            CommandStr .= "_" idx
        }
        return CommandStr
    }

    InitCategoriesMap() {
        if (this.CategoriesMap.Has(GetLang("全部")))
            return

        AllCmdArr := []
        for Index, Value in this.CategoriesArr {
            if (this.CategoriesMap.Has(Value)) {
                CmdStrArr := this.CategoriesMap[Value]
                AllCmdArr.Push(CmdStrArr*)
            }
        }
        this.CategoriesMap.Set(GetLang("全部"), AllCmdArr)
    }
}
