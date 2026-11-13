#Requires AutoHotkey v2.0

; =====================================================================
; RMT指令编辑器 —— XAML 迁移版（分类展开清单 + 搜索框样式）
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
        this._selectedBtnName := ""

        ; 分类结构定义：分类名、图标 Glyph (Segoe Fluent Icons)、该分类下的指令列表（中文）
        ; 删除了「全部」，直接展示各分类
        this.CategoryDefs := [
            {
                name: "图文",
                icon: Chr(0xE721),
                cmds: ["截图", "截图提取文本"]
            },
            {
                name: "输入控制",
                icon: Chr(0xE765),
                cmds: ["启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠", "启用鼠标加速", "禁用鼠标加速"]
            },
            {
                name: "宏控制",
                icon: Chr(0xE713),
                cmds: ["显示菜单", "关闭菜单", "打开界面窗口", "关闭界面窗口", "禁用模块", "取消禁用模块", "暂停所有宏", "恢复所有宏", "终止所有宏"]
            },
            {
                name: "调试",
                icon: Chr(0xEBE8),
                cmds: ["开启变量监视", "关闭变量监视", "开启指令显示", "关闭指令显示"]
            },
            {
                name: "软件自身",
                icon: Chr(0xE770),
                cmds: ["关闭软件", "休眠", "重载"]
            }
        ]

        ; 兼容保持 CategoriesArr 与 CategoriesMap（对外及宏逻辑读取）
        this.CategoriesArr := []
        this.CategoriesMap := Map()
        for cat in this.CategoryDefs {
            catLang := GetLang(cat.name)
            this.CategoriesArr.Push(catLang)
            cmdList := []
            for cmd in cat.cmds
                cmdList.Push(GetLang(cmd))
            this.CategoriesMap[catLang] := cmdList
        }

        ; 分类展开状态（默认全部展开）
        this._catExpand := Map()
        for cat in this.CategoryDefs
            this._catExpand[cat.name] := true
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

    ; 获取指令行按鈕的唯一控件 Name
    _CmdBtnName(catIdx, cmdIdx) => "CmdBtn_" catIdx "_" cmdIdx

    ; XAML 样式资源注入
    _BuildStyles() {
        bodyFs := XAMLHost.MacroBodyFontSize()
        sbThumb := '<ControlTemplate x:Key="RmtSbThumb" TargetType="Thumb">'
            . '<Border x:Name="bd" Background="{DynamicResource ControlBorder}" CornerRadius="3" Opacity="0.9" Margin="1"/>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Accent}"/><Setter TargetName="bd" Property="Opacity" Value="1"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate>'
        sbV := '<Style x:Key="RmtSbVertical" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Width" Value="6"/><Setter Property="MinWidth" Value="0"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="true">'
            . '<Track.Thumb><Thumb Template="{StaticResource RmtSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
        sbH := '<Style x:Key="RmtSbHorizontal" TargetType="ScrollBar">'
            . '<Setter Property="OverridesDefaultStyle" Value="True"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Height" Value="6"/><Setter Property="MinHeight" Value="0"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">'
            . '<Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="false">'
            . '<Track.Thumb><Thumb Template="{StaticResource RmtSbThumb}"/></Track.Thumb>'
            . '</Track></Grid></ControlTemplate></Setter.Value></Setter></Style>'
        svStyle := '<Style x:Key="RmtThemedScrollViewer" TargetType="ScrollViewer">'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollViewer"><Grid>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            . '<Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
            . '<ScrollContentPresenter x:Name="PART_ScrollContentPresenter" Grid.Column="0" Grid.Row="0" Margin="{TemplateBinding Padding}" Content="{TemplateBinding Content}" ContentTemplate="{TemplateBinding ContentTemplate}" CanContentScroll="{TemplateBinding CanContentScroll}"/>'
            . '<ScrollBar x:Name="PART_VerticalScrollBar" Width="6" MinWidth="0" Grid.Column="1" Grid.Row="0" Value="{TemplateBinding VerticalOffset}" Maximum="{TemplateBinding ScrollableHeight}" ViewportSize="{TemplateBinding ViewportHeight}" Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}" Style="{StaticResource RmtSbVertical}"/>'
            . '<ScrollBar x:Name="PART_HorizontalScrollBar" Height="6" MinHeight="0" Orientation="Horizontal" Grid.Column="0" Grid.Row="1" Value="{TemplateBinding HorizontalOffset}" Maximum="{TemplateBinding ScrollableWidth}" ViewportSize="{TemplateBinding ViewportWidth}" Visibility="{TemplateBinding ComputedHorizontalScrollBarVisibility}" Style="{StaticResource RmtSbHorizontal}"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter></Style>'
        cmdRow := '<Style x:Key="RmtCmdRowBtn" TargetType="Button">'
            . '<Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Left"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="3">'
            . '<ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>'
            . '</Border><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        catHead := '<Style x:Key="RmtCatHeadBtn" TargetType="Button">'
            . '<Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Stretch"/>'
            . '<Setter Property="Padding" Value="6,0,4,0"/>'
            . '<Setter Property="ClipToBounds" Value="False"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Grid Background="Transparent" ClipToBounds="False">'
            . '<Border Background="{TemplateBinding Background}" CornerRadius="3" Opacity="0.13" IsHitTestVisible="False"/>'
            . '<Border x:Name="Hover" BorderThickness="1" CornerRadius="3" IsHitTestVisible="False"/>'
            . '<ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Stretch" VerticalAlignment="Center" ClipToBounds="False"/>'
            . '</Grid><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Hover" Property="BorderBrush" Value="{DynamicResource OutlineStroke}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        return sbThumb sbV sbH svStyle cmdRow catHead
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("RMT指令编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        ; === 主内容区：上下布局 ===
        ; 行0: 搜索过滤框 (Height: Auto)
        ; 行1: 分类指令展开列表 (Height: *)
        ; 行2: 动态参数行 (MenuRow / TabRow / FoldRow) (Height: Auto)
        ; 行3: 底部确定按钮 (Height: Auto)
        body := main.Add("Grid").Grid_Row(1).Margin("14,8,14,12")
        body.Rows("Auto", "*", "Auto", "Auto")

        ; --- 搜索框 ---
        filterHost := body.Add("Grid").Grid_Row(0).Margin("0,0,0,8")
        filterHost.Add("TextBox").Name("CmdFilter").Height(28).MinHeight(28)
            .VerticalContentAlignment("Center").Padding("8,0")
            .FontSize(XAMLHost.FontSize())
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        filterHost.Add("TextBlock").Name("CmdFilterHint").Text(GetLang("筛选指令"))
            .IsHitTestVisible("False").VerticalAlignment("Center").Margin("10,0,0,0")
            .Foreground("{DynamicResource TextSub}").FontSize(XAMLHost.FontSize())

        ; --- 分类指令列表 (带滚动条，默认全部展开) ---
        sv := body.Add("ScrollViewer").Grid_Row(1).VerticalScrollBarVisibility("Auto")
            .HorizontalScrollBarVisibility("Disabled").Padding("0").Margin("0,0,0,8")
            .Style("{StaticResource RmtThemedScrollViewer}")
        panel := sv.Add("StackPanel").Margin("0,0,4,4")

        cPadL := 6
        cArrowW := 18
        cIconW := 18
        cGap := 6
        rowPadLeft := cPadL + cArrowW + cGap

        for catIdx, cat in this.CategoryDefs {
            expanded := this._catExpand.Get(cat.name, true)
            ; 分类头部按钮
            headBtn := panel.Add("Button").Name("CatToggle_" catIdx).Style("{StaticResource RmtCatHeadBtn}")
                .HorizontalAlignment("Stretch").Height(30).MinHeight(30).Cursor("Hand")
                .HorizontalContentAlignment("Left").Margin("0,2,0,2").ClipToBounds("False")
                .Background("{DynamicResource Accent}")
            gHead := headBtn.Add("Grid").HorizontalAlignment("Stretch").ClipToBounds("False")
            gHead.Cols(String(cArrowW), String(cGap), String(cIconW), String(cGap), "*", "Auto")

            iconFs := XAMLHost.FormatFontSize(XAMLHost.FontSize() + 1)
            gHead.Add("TextBlock").Name("CatArrow_" catIdx).Grid_Column(0).Text(expanded ? Chr(0xE70D) : Chr(0xE76C))
                .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(iconFs)
                .Width(cArrowW).Height(cArrowW)
                .VerticalAlignment("Center").HorizontalAlignment("Center").TextAlignment("Center")
                .Padding("0").Margin("0").Foreground("{DynamicResource TextMain}")
            gHead.Add("TextBlock").Grid_Column(2).Text(cat.icon)
                .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(iconFs)
                .Width(cIconW).Height(cIconW)
                .VerticalAlignment("Center").HorizontalAlignment("Center").TextAlignment("Center")
                .Padding("0").Margin("0").Foreground("{DynamicResource TextMain}")
            gHead.Add("TextBlock").Grid_Column(4).Text(GetLang(cat.name)).FontSize(XAMLHost.FontSize()).FontWeight("SemiBold")
                .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
                .TextTrimming("CharacterEllipsis")
            gHead.Add("TextBlock").Name("CatCount_" catIdx).Grid_Column(5).Text(String(cat.cmds.Length)).FontSize(10)
                .VerticalAlignment("Center").Margin("8,0,4,0").Foreground("{DynamicResource TextSub}")

            ; 分类下的指令列表容器
            catPanel := panel.Add("StackPanel").Name("CatPanel_" catIdx).Visibility(expanded ? "Visible" : "Collapsed")
            for cmdIdx, cmdName in cat.cmds {
                btnName := this._CmdBtnName(catIdx, cmdIdx)
                row := catPanel.Add("Grid").Name("CmdRow_" catIdx "_" cmdIdx).HorizontalAlignment("Stretch")
                b := row.Add("Button").Name(btnName).Height(28).MinHeight(28).Margin("0,1")
                    .HorizontalAlignment("Stretch").Cursor("Hand")
                    .Style("{StaticResource RmtCmdRowBtn}")
                    .Padding(rowPadLeft ",0,6,0")
                    .HorizontalContentAlignment("Left").VerticalContentAlignment("Center")
                sp := b.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center")
                sp.Add("TextBlock").Text(GetLang(cmdName)).FontSize(XAMLHost.FontSize()).VerticalAlignment("Center")
                    .TextTrimming("CharacterEllipsis").Foreground("{DynamicResource TextMain}")
            }
        }

        ; --- 动态参数区 ---
        paramArea := body.Add("StackPanel").Grid_Row(2).Margin("0,2,0,8")

        ; 显示菜单参数：菜单序号
        menuRow := paramArea.Add("Grid").Name("MenuRow").Margin("0,3").Visibility("Collapsed")
        menuRow.Cols("76", "*")
        menuRow.Add("TextBlock").Grid_Column(0).Text(GetLang("菜单序号：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        menuRow.Add("ComboBox").Grid_Column(1).Name("MenuDLCombo").Height(26).MinHeight(26).HorizontalAlignment("Stretch").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; 禁用模块参数：页签与模块
        tabRow := paramArea.Add("Grid").Name("TabRow").Margin("0,3").Visibility("Collapsed")
        tabRow.Cols("76", "*")
        tabRow.Add("TextBlock").Grid_Column(0).Text(GetLang("页签：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        tabRow.Add("ComboBox").Grid_Column(1).Name("TabCombo").Height(26).MinHeight(26).HorizontalAlignment("Stretch").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        foldRow := paramArea.Add("Grid").Name("FoldRow").Margin("0,3").Visibility("Collapsed")
        foldRow.Cols("76", "*")
        foldRow.Add("TextBlock").Grid_Column(0).Text(GetLang("模块：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        foldRow.Add("ComboBox").Grid_Column(1).Name("FoldCombo").Height(26).MinHeight(26).HorizontalAlignment("Stretch").VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; --- 底部确定按钮 ---
        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,2,0,0")
        AddCmdOkBtn(btnRow)

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="360" Height="480"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._BuildStyles())

        ; === 事件绑定 ===
        this.ui.OnEvent("Window", "Closing", this.OnWindowClosing.Bind(this, this.ui.id))
        this.ui.OnEvent("Window", "LoadedHwnd", this.OnWindowLoad.Bind(this, this.ui.id))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/20-RMT指令", ObjBindMethod(this, "TriggerMacro"), "!l")

        ; 搜索框与折叠
        this.ui.OnEvent("CmdFilter", "TextChanged", ObjBindMethod(this, "_OnCmdFilterChanged"))
        this.ui.Track("CmdFilter")
        for catIdx, cat in this.CategoryDefs {
            this.ui.OnEvent("CatToggle_" catIdx, "Click", this._OnToggleCat.Bind(this, catIdx))
            for cmdIdx, cmdName in cat.cmds {
                btnName := this._CmdBtnName(catIdx, cmdIdx)
                this.ui.OnEvent(btnName, "Click", this._OnCmdRowClick.Bind(this, cat.name, cmdName, btnName))
            }
        }

        this.ui.OnEvent("TabCombo", "SelectionChanged", ObjBindMethod(this, "OnTabComboChange"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnSureBtnClick"))
    }

    OnWindowLoad(id, *) {
        if (IsObject(this.ui) && this.ui.id == id)
            XamlWin.OnLoadTheme(this.ui)
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

    ; 点击分类标题折叠/展开
    _OnToggleCat(catIdx, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || catIdx < 1 || catIdx > this.CategoryDefs.Length)
            return
        cat := this.CategoryDefs[catIdx]
        expanded := !this._catExpand.Get(cat.name, true)
        this._catExpand[cat.name] := expanded
        try this.ui.Update("CatPanel_" catIdx, "Visibility", expanded ? "Visible" : "Collapsed")
        try this.ui.Update("CatArrow_" catIdx, "Text", expanded ? Chr(0xE70D) : Chr(0xE76C))
    }

    ; 点击具体的指令行
    _OnCmdRowClick(catName, cmdName, btnName, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this._SelectCmd(catName, cmdName, btnName)
    }

    ; 选中指令并高亮该指令行
    _SelectCmd(catName, cmdName, btnName) {
        if (this._selectedBtnName != "" && this._selectedBtnName != btnName) {
            try this.ui.Update(this._selectedBtnName, "Background", "Transparent")
        }
        this._selectedBtnName := btnName
        this._category := catName
        this._cmdType := cmdName
        if (btnName != "") {
            try this.ui.Update(btnName, "Background", "{DynamicResource EditHoverBg}")
        }
        this.OnCmdChange()
    }

    ; 搜索过滤框变化事件
    _OnCmdFilterChanged(state, ctrl := "", event := "") {
        q := ""
        if (IsObject(state) && state.Has("CmdFilter"))
            q := state["CmdFilter"]
        else if (IsObject(this.ui))
            q := this.ui.Query("CmdFilter")
        this._ApplyCmdFilter(q)
    }

    _CmdFilterMatch(name, q) {
        if (q == "")
            return true
        return InStr(name, q) || InStr(GetLang(name), q)
    }

    ; 执行指令筛选
    _ApplyCmdFilter(q := unset) {
        if (!IsObject(this.ui))
            return
        if (!IsSet(q))
            q := this.ui.Query("CmdFilter")
        q := Trim(String(q))
        try this.ui.Update("CmdFilterHint", "Visibility", q == "" ? "Visible" : "Collapsed")

        for catIdx, cat in this.CategoryDefs {
            cnt := 0
            for cmdIdx, cmdName in cat.cmds {
                match := this._CmdFilterMatch(cmdName, q)
                if (match)
                    cnt++
                try this.ui.Update("CmdRow_" catIdx "_" cmdIdx, "Visibility", match ? "Visible" : "Collapsed")
            }
            showCat := cnt > 0
            expanded := this._catExpand.Get(cat.name, true)
            try this.ui.Update("CatToggle_" catIdx, "Visibility", showCat ? "Visible" : "Collapsed")
            try this.ui.Update("CatPanel_" catIdx, "Visibility", (showCat && expanded) ? "Visible" : "Collapsed")
            try this.ui.Update("CatCount_" catIdx, "Text", String(cnt))
        }
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
            cmdCategory := cmdArr[2]
            cmdStr := cmdArr[3]
            menuDLIndex := (cmdStr == "显示菜单" || cmdStr == GetLang("显示菜单")) && cmdArr.Length >= 4 ? Integer(cmdArr[4]) : 1
        } else {
            cmdCategory := "图文"
            cmdStr := "截图"
            menuDLIndex := 1
        }

        ; 如果类别是旧版的「全部」或为空，则自动纠正为第一条指令对应的分类
        if (cmdCategory == "" || cmdCategory == "全部" || cmdCategory == GetLang("全部")) {
            for cat in this.CategoryDefs {
                for c in cat.cmds {
                    if (c == cmdStr || GetLang(c) == cmdStr) {
                        cmdCategory := cat.name
                        break 2
                    }
                }
            }
            if (cmdCategory == "" || cmdCategory == "全部" || cmdCategory == GetLang("全部"))
                cmdCategory := "图文"
        }

        ; 找到匹配的分类与指令，设置选中与高亮
        foundCatName := ""
        foundCmdName := ""
        foundBtnName := ""
        for catIdx, cat in this.CategoryDefs {
            if (cat.name == cmdCategory || GetLang(cat.name) == cmdCategory) {
                for cmdIdx, c in cat.cmds {
                    if (c == cmdStr || GetLang(c) == cmdStr) {
                        foundCatName := cat.name
                        foundCmdName := c
                        foundBtnName := this._CmdBtnName(catIdx, cmdIdx)
                        break 2
                    }
                }
            }
        }
        ; 若未精准匹配，兜底在所有分类中查找 cmdStr
        if (foundBtnName == "") {
            for catIdx, cat in this.CategoryDefs {
                for cmdIdx, c in cat.cmds {
                    if (c == cmdStr || GetLang(c) == cmdStr) {
                        foundCatName := cat.name
                        foundCmdName := c
                        foundBtnName := this._CmdBtnName(catIdx, cmdIdx)
                        break 2
                    }
                }
            }
        }
        if (foundBtnName == "") {
            foundCatName := this.CategoryDefs[1].name
            foundCmdName := this.CategoryDefs[1].cmds[1]
            foundBtnName := this._CmdBtnName(1, 1)
        }

        this._SelectCmd(foundCatName, foundCmdName, foundBtnName)

        ; 轮盘菜单下拉选项
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
        this._SetDDL("TabCombo", tabItems, "")
        this.ui.Update("TabCombo", "SelectedIndex", String(selectedIndex - 1))
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
        if (!IsObject(this.ui) || !IsObject(this._tabIDs))
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
        OnTriggerSepcialItemMacro(this.GetCmdStr())
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
        this.Data.Category := GetLang(this._category)
        this.Data.CmdStr := GetLang(this._cmdType)
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
            this.Data.SerialStr := GetCMDSerialStr(GetLang("RMT指令"))
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
