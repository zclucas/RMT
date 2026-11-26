#Requires AutoHotkey v2.0

; =====================================================================
; RMT指令编辑器 —— 类别、指令与按需参数的紧凑表单
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
        this._cmdType := ""
        this._category := ""
        this._filterCategory := "全部"
        this._categoryKeys := ["全部"]
        this._commandKeys := []
        this._tabIDs := []
        this._foldTab := ""

        ; 保留当前指令集合；「全部」只用于筛选，实际保存指令所属分类。
        this.CategoryDefs := [
            {
                name: "图文",
                cmds: ["截图", "截图提取文本"]
            },
            {
                name: "输入控制",
                cmds: ["启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠", "启用鼠标加速", "禁用鼠标加速"]
            },
            {
                name: "宏控制",
                cmds: ["显示菜单", "关闭菜单", "打开界面窗口", "关闭界面窗口", "禁用模块", "取消禁用模块", "暂停所有宏", "恢复所有宏", "终止所有宏"]
            },
            {
                name: "调试",
                cmds: ["开启变量监视", "关闭变量监视", "开启指令显示", "关闭指令显示"]
            },
            {
                name: "软件自身",
                cmds: ["关闭软件", "休眠", "重载"]
            }
        ]

        ; 兼容保持 CategoriesArr 与 CategoriesMap（对外及宏逻辑读取）
        this.CategoriesArr := [GetLang("全部")]
        allCommands := []
        this.CategoriesMap := Map()
        for cat in this.CategoryDefs {
            catLang := GetLang(cat.name)
            this.CategoriesArr.Push(catLang)
            this._categoryKeys.Push(cat.name)
            cmdList := []
            for cmd in cat.cmds
                cmdList.Push(GetLang(cmd))
            this.CategoriesMap[catLang] := cmdList
            allCommands.Push(cmdList*)
        }

        this.CategoriesMap[GetLang("全部")] := allCommands
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
        else
            this.ToggleFunc(true)
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

    ; 五个中文字加全角冒号；按主题实际字号计算，所有参数共用同一起点。
    _AddChoiceRow(parent, label, rowName, controlName, visible := true) {
        row := parent.Add("Grid").Name(rowName).Margin("0,5")
        row.Visibility(visible ? "Visible" : "Collapsed")
        row.Cols(String(6 * XAMLHost.ScaleFontSize(XAMLHost.FontSize())), "*")
        CmdEditorForm.Label(row, label).Name(rowName "Label").Grid_Column(0).Margin("0")
        return CmdEditorForm.Combo(row, controlName).Grid_Column(1)
            .Height(30).MinHeight(30).HorizontalAlignment("Stretch")
    }

    _BuildForm(parent) {
        body := parent.Add("StackPanel").Margin("16,10,16,14")
        category := this._AddChoiceRow(body, "类别：", "CategoryRow", "CategoryCombo")
        for label in this.CategoriesArr
            this._DecorateChoice(category.Add("ComboBoxItem").Tag("{}" label).Content(label), label)
        this._AddChoiceRow(body, "指令：", "CommandRow", "CmdTypeCombo").MaxDropDownHeight(360)
        this._AddChoiceRow(body, "菜单序号：", "MenuRow", "MenuDLCombo", false)
        this._AddChoiceRow(body, "页签：", "TabRow", "TabCombo", false)
        this._AddChoiceRow(body, "模块：", "FoldRow", "FoldCombo", false)
        buttons := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,14,0,0")
        AddCmdOkBtn(buttons)
        return body
    }

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("RMT指令编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, titleHeight)
        this._BuildForm(main).Grid_Row(1)

        template := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(template, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' this._EscapeXml(title) '" Width="400" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"',
            'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", this.OnWindowClosing.Bind(this, this.ui.id))
        this.ui.OnEvent("Window", "LoadedHwnd", this.OnWindowLoad.Bind(this, this.ui.id))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/20-RMT指令", ObjBindMethod(this, "TriggerMacro"), "!l")
        this.ui.OnEvent("CategoryCombo", "SelectionChanged", ObjBindMethod(this, "OnCategoryChange"))
        this.ui.OnEvent("CmdTypeCombo", "SelectionChanged", ObjBindMethod(this, "OnCmdChange"))
        this.ui.OnEvent("TabCombo", "SelectionChanged", ObjBindMethod(this, "OnTabComboChange"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnSureBtnClick"))
    }

    OnWindowLoad(id, *) {
        if (IsObject(this.ui) && this.ui.id == id) {
            XamlWin.OnLoadTheme(this.ui)
        }
    }

    OnWindowClosing(id, *) {
        if (!IsObject(this.ui) || this.ui.id != id)
            return
        this.ToggleFunc(false)
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
        this.ToggleFunc(false)
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
            if (comboName == "CategoryCombo" || comboName == "CmdTypeCombo")
                this._ComboPush(comboName, "AddXamlItem", this._ChoiceItemXml(it))
            else
                this._ComboPush(comboName, "AddItem", it)
        }
        for i, it in items {
            if (it == text) {
                this._ComboPush(comboName, "SelectedIndex", String(i - 1))
                return
            }
        }
        this._ComboPush(comboName, "SelectedIndex", items.Length ? "0" : "-1")
    }

    _DecorateChoice(item, label) {
        key := GetLangKey(label)
        static glyphs := Map(
            "全部", 0xE71D, "图文", 0xE91B, "输入控制", 0xE765,
            "宏控制", 0xE768, "调试", 0xE890, "软件自身", 0xE713,
            "截图", 0xE722, "截图提取文本", 0xE8A5,
            "启用鼠标", 0xE962, "禁用鼠标", 0xE962,
            "启用键盘", 0xE765, "禁用键盘", 0xE765,
            "启用键鼠", 0xE961, "禁用键鼠", 0xE961,
            "启用鼠标加速", 0xE945, "禁用鼠标加速", 0xE945,
            "显示菜单", 0xE700, "关闭菜单", 0xE700,
            "打开界面窗口", 0xE737, "关闭界面窗口", 0xE737,
            "禁用模块", 0xE8A9, "取消禁用模块", 0xE8A9,
            "暂停所有宏", 0xE769, "恢复所有宏", 0xE768, "终止所有宏", 0xE71A,
            "开启变量监视", 0xE890, "关闭变量监视", 0xE890,
            "开启指令显示", 0xE756, "关闭指令显示", 0xE756,
            "关闭软件", 0xE7E8, "休眠", 0xE708, "重载", 0xE72C)
        if (!glyphs.Has(key))
            return item
        negated := InStr(key, "禁用") == 1 || (InStr(key, "关闭") == 1 && key != "关闭软件")
        item.Tag("{}" label).TextSearch_Text("{}" label)
        ; 复用下拉项专用模板：右侧灰色图标，收起后仍只显示文字。
        CmdEditorForm.DecorateCompareItem(item, label, label, Chr(glyphs[key]), negated)
        return item
    }

    _ChoiceItemXml(label) {
        item := XAML_Generator("ComboBoxItem").SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
            .Tag("{}" label).Content(label)
        return this._DecorateChoice(item, label).ToString()
    }

    _CommandCategory(command) {
        for category in this.CategoryDefs
            for key in category.cmds
                if (key == command)
                    return category.name
        return ""
    }

    _SetCommandChoices(categoryKey, preferredCommand := "") {
        commands := [], labels := []
        for category in this.CategoryDefs {
            if (categoryKey != "全部" && categoryKey != category.name)
                continue
            for command in category.cmds {
                commands.Push(command)
                labels.Push(GetLang(command))
            }
        }
        selectedCommand := commands[1]
        for command in commands
            if (command == preferredCommand) {
                selectedCommand := command
                break
            }
        this._filterCategory := categoryKey
        this._commandKeys := commands
        this._cmdType := selectedCommand
        this._category := this._CommandCategory(selectedCommand)
        this._SetDDL("CmdTypeCombo", labels, GetLang(selectedCommand))
        this.OnCmdChange()
    }

    OnCategoryChange(*) {
        if (!IsObject(this.ui) || this._batching)
            return
        category := GetConfigKey(this.ui.Query("CategoryCombo"), this._categoryKeys)
        if (!this.CategoriesMap.Has(GetLang(category)))
            return
        this._SetCommandChoices(category, this._cmdType)
    }

    Init(cmd) {
        ; 指令配置化。新格式 RMT指令<serial> 读配置文件；旧格式 RMT指令_类别_指令[_序号] 兼容
        cmd := RMTParseErrHandle(cmd).cmd
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.Data := RMTCMDData()
        ; 备注：指令串第二段
        SplitSerialTextAndNumbers(cmdArr.Length >= 1 ? cmdArr[1] : "", &textOnly, &numbersOnly)
        if (numbersOnly != "") {
            ; 新格式：读配置文件 Data
            this.Data := GetMacroCMDData(cmdArr[1])
            cmdCategory := this.Data.Category
            cmdStr := this.Data.CmdStr
            menuDLIndex := this.Data.HasOwnProp("MenuIndex") ? this.Data.MenuIndex : 1
        } else if (cmdArr.Length >= 3) {
            cmdCategory := RmtCommandCategoryKey(cmdArr[2])
            cmdStr := RmtCommandActionKey(cmdArr[3])
            menuDLIndex := (cmdStr == "显示菜单" || cmdStr == GetLang("显示菜单")) && cmdArr.Length >= 4 ? Integer(cmdArr[4]) : 1
        } else {
            cmdCategory := "全部"
            cmdStr := "截图"
            menuDLIndex := 1
        }

        cmdStr := RmtCommandActionKey(cmdStr)
        actualCategory := this._CommandCategory(cmdStr)
        if (actualCategory == "") {
            cmdStr := "截图"
            actualCategory := "图文"
        }
        categoryKey := GetConfigKey(cmdCategory, this._categoryKeys)
        if (categoryKey != "全部" && categoryKey != actualCategory)
            categoryKey := actualCategory
        this._SetDDL("CategoryCombo", this.CategoriesArr, GetLang(categoryKey))
        this._SetCommandChoices(categoryKey, cmdStr)

        ; 轮盘菜单下拉选项
        tableItem := GetTableBySymbol("Menu")
        DropDownArr := []
        if (tableItem) {
            for f, fold in tableItem.Folds {
                DropDownArr.Push(f ". " fold.Remark)
            }
        }
        this._ComboPush("MenuDLCombo", "ClearItems", "")
        for it in DropDownArr
            this._ComboPush("MenuDLCombo", "AddItem", it)
        this._ComboPush("MenuDLCombo", "SelectedIndex", String(menuDLIndex - 1))

        ; 禁用模块/取消禁用模块：页签+模块 回显
        this._tabIDs := this._FoldTabIDs()
        tabItems := []
        targetID := this.Data.HasOwnProp("TableSymbol") ? this.Data.TableSymbol : ""
        targetTable := GetTableByID(targetID)
        if (!targetTable)
            targetTable := GetTableBySymbol(targetID)
        selectedIndex := 0
        for i, tableID in this._tabIDs {
            t := GetTableByID(tableID)
            tabItems.Push(GetLang(t.Name))
            if (targetTable && targetTable.ID == tableID)
                selectedIndex := i
        }
        if (!selectedIndex && this._tabIDs.Length)
            selectedIndex := 1
        this._foldTab := selectedIndex ? this._tabIDs[selectedIndex] : ""
        selTable := GetTableByID(this._foldTab)
        ; 选项和选中项使用同一批更新，避免默认项覆盖原先页签。
        this._SetDDL("TabCombo", tabItems, "")
        this._ComboPush("TabCombo", "SelectedIndex", String(selectedIndex - 1))
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
    }

    ; 操作类型变更处理：刷新参数行可见性
    OnCmdChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        if (ctrl == "CmdTypeCombo" && !this._batching) {
            command := GetConfigKey(this.ui.Query("CmdTypeCombo"), this._commandKeys)
            category := this._CommandCategory(command)
            if (category != "") {
                this._cmdType := command
                this._category := category
            }
        }
        CmdStr := this._cmdType
        IsShowMenuDL := (CmdStr == "显示菜单" || CmdStr == GetLang("显示菜单"))
        this.ui.Update("MenuRow", "Visibility", IsShowMenuDL ? "Visible" : "Collapsed")

        ; 禁用模块/取消禁用模块：显示目标页签+模块参数行
        IsShowFoldParam := (CmdStr == "禁用模块" || CmdStr == GetLang("禁用模块") || CmdStr == "取消禁用模块" || CmdStr == GetLang("取消禁用模块"))
        vis := IsShowFoldParam ? "Visible" : "Collapsed"
        this.ui.Update("TabRow", "Visibility", vis)
        this.ui.Update("FoldRow", "Visibility", vis)
    }

    ; 页签下拉切换：刷新模块下拉为该页签下的模块列表
    OnTabComboChange(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || this._batching || !IsObject(this._tabIDs))
            return
        tabIdx := Integer(this.ui.Query("TabCombo>SelectedIndex")) + 1
        if (tabIdx < 1 || tabIdx > this._tabIDs.Length)
            return
        tableID := this._tabIDs[tabIdx]
        if (tableID == this._foldTab)
            return
        this._foldTab := tableID
        tableItem := GetTableByID(tableID)
        items := []
        if (tableItem) {
            for f, fold in tableItem.Folds {
                items.Push(f ". " fold.Remark)
            }
        }
        this._SetDDL("FoldCombo", items, items.Length >= 1 ? items[1] : "")
    }

    ; 列出可选「禁用模块」的页签（宏相关表，排除非配置表）
    _FoldTabIDs() {
        global MySoftData
        ids := []
        for tableItem in MySoftData.TableInfo {
            if (IsItemSymbol(tableItem.Symbol))
                ids.Push(tableItem.ID)
        }
        return ids
    }

    ToggleFunc(state) {
        if (state) {
            try Hotkey("!l", (*) => this.TriggerMacro(), "On")
        } else {
            try Hotkey("!l", (*) => this.TriggerMacro(), "Off")
        }
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || (this.HasProp("_closed") && this._closed))
            return
        if (!this.CheckIfValid())
            return
        RunEditorMacroPreview(this.GetCmdStr())
    }

    OnSureBtnClick(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        CommandStr := this.GetCmdStr()
        this.SureBtnAction.Call(CommandStr)
        this._CloseWindow()
    }

    ; 指令配置化——组装 Data 保存到配置文件，返回 RMT指令<serial>_备注
    GetCmdStr() {
        if (!IsObject(this.Data))
            this.Data := RMTCMDData()
        this.Data.Category := this._category
        this.Data.CmdStr := this._cmdType
        this.Data.MenuIndex := (this._cmdType == "显示菜单" || this._cmdType == GetLang("显示菜单"))
            ? (Integer(this.ui.Query("MenuDLCombo>SelectedIndex")) + 1) : 1
        ; 禁用模块/取消禁用模块：保存目标页签符号 + 模块路径身份
        if (this._cmdType == "禁用模块" || this._cmdType == GetLang("禁用模块")
            || this._cmdType == "取消禁用模块" || this._cmdType == GetLang("取消禁用模块")) {
            tabIdx := Integer(this.ui.Query("TabCombo>SelectedIndex")) + 1
            foldIdx := Integer(this.ui.Query("FoldCombo>SelectedIndex")) + 1
            if (IsObject(this._tabIDs) && tabIdx >= 1 && tabIdx <= this._tabIDs.Length) {
                selTable := GetTableByID(this._tabIDs[tabIdx])
                this.Data.TableSymbol := this._tabIDs[tabIdx]
                this.Data.FoldID := (selTable && foldIdx >= 1 && foldIdx <= selTable.Folds.Length) ? selTable.Folds[foldIdx].ID : ""
            }
        }

        if (this.Data.SerialStr == "")
            this.Data.SerialStr := AllocateCommandSerial("RMT指令")
        SaveMacroCMDData(this.Data)
        remark := this.Data.CmdStr
        return CorrectRemark(this.Data.SerialStr, remark)
    }

    CheckIfValid() {
        cmd := this._cmdType
        if (cmd == "禁用键鼠" || cmd == GetLang("禁用键鼠") || cmd == "禁用鼠标" || cmd == GetLang("禁用鼠标") || cmd == "禁用键盘" || cmd == GetLang("禁用键盘")) {
            if (cmd == "禁用鼠标" || cmd == GetLang("禁用鼠标"))
                tipBody := GetLang("此操作将 立即禁用鼠标输入，您将无法通过鼠标操作计算机！")
            else if (cmd == "禁用键盘" || cmd == GetLang("禁用键盘"))
                tipBody := GetLang("此操作将 立即禁用键盘输入，您将无法通过键盘操作计算机！")
            else
                tipBody := GetLang("此操作将 立即禁用键盘和鼠标输入，您将无法通过键鼠操作计算机！")
            tipStr := Format("{}`n{}`n{}`n{}`n{}", tipBody, GetLang("重要须知："), GetLang(
                "- 以管理员身份运行本软件，否则该指令无效。"), GetLang("- 务必后续执行对应的启用指令，否则输入设备将保持禁用状态！"), GetLang("是否确认禁用？"))
            title := (cmd == "禁用鼠标" || cmd == GetLang("禁用鼠标")) ? GetLang("禁用鼠标（需管理员权限）")
                : ((cmd == "禁用键盘" || cmd == GetLang("禁用键盘")) ? GetLang("禁用键盘（需管理员权限）") : GetLang("禁用键鼠（需管理员权限）"))
            if (!RmtDialog.Confirm(tipStr, title))
                return false
        }

        if (cmd == "启用键鼠" || cmd == GetLang("启用键鼠") || cmd == "启用鼠标" || cmd == GetLang("启用鼠标") || cmd == "启用键盘" || cmd == GetLang("启用键盘")) {
            title := (cmd == "启用鼠标" || cmd == GetLang("启用鼠标")) ? GetLang("启用鼠标（需管理员权限）")
                : ((cmd == "启用键盘" || cmd == GetLang("启用键盘")) ? GetLang("启用键盘（需管理员权限）") : GetLang("启用键鼠（需管理员权限）"))
            RmtDialog.Info(GetLang("- 必须 以管理员身份运行本软件，否则该指令无效。"), title)
        }
        return true
    }

    GetCommandStr() {
        ; CMD格式: RMT指令_类别_指令 或 RMT指令_类别_指令_序号
        CommandStr := Format("{}_{}_{}", GetLang("RMT指令"), GetLang(this._category), GetLang(this._cmdType))
        if (this._cmdType == "显示菜单" || this._cmdType == GetLang("显示菜单")) {
            idx := Integer(this.ui.Query("MenuDLCombo>SelectedIndex")) + 1
            CommandStr .= "_" idx
        }
        return CommandStr
    }
}
