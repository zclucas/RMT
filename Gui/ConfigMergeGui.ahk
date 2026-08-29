#Requires AutoHotkey v2.0
#Include ..\Main\Util\MergeUtil.ahk

class ConfigMergeGui {
    static instances := Map()
    static _opening := false

    __New() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._btnStyle := ""
        this._applyingUI := false
        this.TreeRoot := ""
        this.SourceType := "file"
        this.SourcePath := ""
        this.SourceName := ""
        this.ItemNodeMap := Map()
        this.IsFromRmt := false
        this._localSettings := []
        this._srcCtrlW := 200
    }

    ; 兼容旧入口 MyConfigMergeGui.ShowGui()
    ShowGui() {
        ConfigMergeGui.ShowGui()
    }

    static ShowGui() {
        key := "global"
        if (ConfigMergeGui.instances.Has(key)) {
            oldInst := ConfigMergeGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                try WinActivate("ahk_id " hwnd)
                oldInst.RefreshLocalConfigList()
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            ConfigMergeGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (ConfigMergeGui._opening)
            return
        ConfigMergeGui._opening := true
        try {
            inst := ConfigMergeGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            ConfigMergeGui.instances[key] := inst
        } finally {
            ConfigMergeGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("合并导入")
        titleHeight := "36"
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Rows(titleHeight, "*")

        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")

        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        root := body.Add("Grid").Margin("14, 8, 14, 10")
        root.Rows("Auto", "Auto", "*", "Auto", "Auto")

        ; 源配置选择：两行，右侧控件右对齐且同宽
        srcGroup := root.Add("GroupBox").Header(GetLang("源配置选择")).Grid_Row(0)
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Foreground("{DynamicResource TextMain}")
        srcInner := srcGroup.Add("StackPanel").Margin("12, 8, 12, 10")

        fileRow := srcInner.Add("Grid").Margin("0,2,0,0")
        fileRow.Cols("*", "Auto")
        fileRow.Add("TextBlock").Text(GetLang("本地文件导入（.rmt）"))
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Grid_Column(0)
        this._AddBtn(fileRow, "SelectFileBtn", GetLang("选择文件"), this._srcCtrlW)
            .Grid_Column(1).HorizontalAlignment("Right").Margin("0,0,50,0")

        localRow := srcInner.Add("Grid").Margin("0,10,0,0")
        localRow.Cols("*", "Auto")
        localRow.Add("TextBlock").Text(GetLang("本地配置导入"))
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Grid_Column(0)
        localRow.Add("ComboBox").Name("LocalConfigDDL")
            .Width(this._srcCtrlW).Height(26).MinHeight(26)
            .Grid_Column(1).HorizontalAlignment("Right").Margin("0,0,50,0")

        ; 已选择
        countRow := root.Add("StackPanel").Orientation("Horizontal").Grid_Row(1).Margin("2,10,0,6")
        countRow.Add("TextBlock").Text(GetLang("已选择") ":")
            .Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center")
        countRow.Add("TextBlock").Name("SelectedCountText").Text("0")
            .Foreground("{DynamicResource TextSub}").FontSize(13).FontWeight("SemiBold")
            .VerticalAlignment("Center").Margin("6,0,0,0")

        ; 列表区
        listBorder := root.Add("Border").Grid_Row(2)
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Background("{DynamicResource InputBg}").CornerRadius("3")
        listGrid := listBorder.Add("Grid")
        listGrid.Rows("Auto", "*")

        header := listGrid.Add("Grid").Grid_Row(0).Height(30)
            .Background("{DynamicResource TitleBarColor}")
        header.Cols("*", "150")
        headerLeft := header.Add("StackPanel").Orientation("Horizontal").Grid_Column(0)
            .VerticalAlignment("Center").Margin("8,0,0,0")
        headerLeft.Add("TextBlock").Text(GetLang("选择"))
            .Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold")
            .VerticalAlignment("Center").Width("40")
        headerLeft.Add("TextBlock").Text(GetLang("宏名称"))
            .Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold")
            .VerticalAlignment("Center").Margin("8,0,0,0")
        header.Add("TextBlock").Text(GetLang("触发键/类型")).Grid_Column(1)
            .Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold")
            .HorizontalAlignment("Center").VerticalAlignment("Center")

        scroll := listGrid.Add("ScrollViewer").Grid_Row(1)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        scroll.Add("StackPanel").Name("MergeListPanel").Margin("4, 4, 4, 4")

        ; 说明
        root.Add("TextBlock").Grid_Row(3).Margin("2,8,2,0")
            .Text(GetLang("合并说明:合并的宏将按原模块结构创建新模块"))
            .Foreground("{DynamicResource TextSub}").FontSize(12).TextWrapping("Wrap")

        ; 底部按钮居中：开始合并导入、取消
        btnRow := root.Add("StackPanel").Orientation("Horizontal").Grid_Row(4)
            .HorizontalAlignment("Center").Margin("0,12,0,2")
        this._AddBtn(btnRow, "ExecuteBtn", GetLang("开始合并导入"), 110).Margin("0,0,162,0")
        this._AddBtn(btnRow, "CancelBtn", GetLang("取消"), 90)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="620" Height="680" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        groupBoxStyle := '<Style TargetType="GroupBox"><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/></Style>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>' groupBoxStyle)

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("CancelBtn", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("ExecuteBtn", "Click", ObjBindMethod(this, "OnExecuteMerge"))
        this.ui.OnEvent("SelectFileBtn", "Click", ObjBindMethod(this, "OnSelectFile"))
        this.ui.Track("LocalConfigDDL")
        this.ui.OnEvent("LocalConfigDDL", "SelectionChanged", ObjBindMethod(this, "OnLocalConfigChange"))

        this.RefreshLocalConfigList()
        this.ui.Show()
        loop 20 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                try this.ui.Update("Window", "Opacity", "1")
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                break
            }
            Sleep(50)
        }
    }

    _AddBtn(parent, name, content, width) {
        btn := parent.Add("Button").Name(name).Content(content)
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(12).Cursor("Hand").Width(width).Height(28)
        btn.InjectResources(this._btnStyle)
        return btn
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        ConfigMergeGui._opening := false
        if (this._instanceKey != "" && ConfigMergeGui.instances.Has(this._instanceKey))
            ConfigMergeGui.instances.Delete(this._instanceKey)
        this.ui := ""
        MergeUtil.CleanupTemp()
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
            this.RefreshLocalConfigList()
        } finally {
            this.ui.Update("Window", "Opacity", "1")
        }
    }

    OnCancelClick(state := unset, ctrl := unset, event := unset) {
        if IsObject(this.ui)
            this.ui.Update("Window", "Close", "")
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
        MergeUtil.CleanupTemp()
    }

    OnClose() {
        this.Close()
    }

    RefreshLocalConfigList() {
        settingList := StrSplit(MainSoftData.SettingArrStr, "π")
        this._localSettings := []
        for name in settingList {
            if (name != "" && name != MySoftData.CurSettingName)
                this._localSettings.Push(name)
        }
        if (!IsObject(this.ui))
            return

        this._applyingUI := true
        try {
            this.ui.Update("LocalConfigDDL", "ClearItems", "")
            for name in this._localSettings {
                this.ui.Update("LocalConfigDDL", "AddItem", name)
            }
        } finally {
            this._applyingUI := false
        }
    }

    OnSelectFile(state := unset, ctrl := unset, event := unset) {
        selectedFile := FileSelect(1, , GetLang("选择要合并导入的 RMT 文件"), "RMT Files (*.rmt)")
        if (selectedFile == "")
            return

        SplitPath selectedFile, &fileName, , &fileExt, &fileNameNoExt
        if (fileExt != "rmt") {
            MsgBox(GetLang("请选择 .rmt 文件！"), GetLang("错误"), 0x10)
            return
        }

        this.SourceType := "file"
        this.SourcePath := selectedFile
        this.SourceName := fileNameNoExt
        this.IsFromRmt := true

        try {
            tempDir := MergeUtil.PrepareTempFromRmt(selectedFile)
            this.LoadSourceConfig(tempDir)
        } catch as e {
            MsgBox(GetLang("解包失败: ") e.Message, GetLang("错误"), 0x10)
        }
    }

    OnLocalConfigChange(state := unset, ctrl := unset, event := unset) {
        if (this._applyingUI)
            return
        configName := ""
        if (IsSet(state) && IsObject(state) && state.Has("LocalConfigDDL"))
            configName := state["LocalConfigDDL"]
        if (configName == "")
            return

        this.SourceType := "local"
        this.SourceName := configName
        this.SourcePath := A_WorkingDir "\Setting\" configName
        this.IsFromRmt := false
        this.LoadSourceConfig(this.SourcePath)
    }

    LoadSourceConfig(settingDir) {
        this.TreeRoot := MergeUtil.ParseSourceConfig(settingDir)
        this._InitExpandState(this.TreeRoot)
        this.PopulateListView()
    }

    _InitExpandState(root) {
        if (!root || !root.Children)
            return
        for tabNode in root.Children {
            tabNode.IsExpanded := true
            for moduleNode in tabNode.Children
                moduleNode.IsExpanded := true
        }
    }

    PopulateListView() {
        if (!IsObject(this.ui))
            return

        ; 清理旧动态事件，避免重复绑定
        toDel := []
        for key, _ in this.ui.events {
            if (InStr(key, "MergeChk_") == 1 || InStr(key, "MergeFold_") == 1)
                toDel.Push(key)
        }
        for key in toDel
            this.ui.events.Delete(key)

        this.ui.Update("MergeListPanel", "ClearItems", "")
        this.ItemNodeMap := Map()

        if (!this.TreeRoot || !this.TreeRoot.Children) {
            this.ui.Update("SelectedCountText", "Text", "0")
            return
        }

        row := 0
        for tabNode in this.TreeRoot.Children {
            if (!tabNode.HasOwnProp("IsExpanded"))
                tabNode.IsExpanded := true
            tabRow := ++row
            tabNode.ListViewRow := tabRow
            tabNode.IsTabNode := true
            this.ItemNodeMap[tabRow] := tabNode
            this._AddListRow(tabRow, tabNode.DisplayName, "", MergeUtil.HasAnyCheckedItem(tabNode), 0, true, true, tabNode.IsExpanded)
            isMenuTab := (tabNode.TabIndex == 3)
            if (!tabNode.IsExpanded)
                continue

            for moduleNode in tabNode.Children {
                if (!moduleNode.HasOwnProp("IsExpanded"))
                    moduleNode.IsExpanded := true
                moduleRow := ++row
                moduleNode.ListViewRow := moduleRow
                moduleNode.IsModuleNode := true
                this.ItemNodeMap[moduleRow] := moduleNode
                this._AddListRow(moduleRow, moduleNode.DisplayName, "", MergeUtil.HasAnyCheckedItem(moduleNode), 1, false, true, moduleNode.IsExpanded)

                if (!isMenuTab && moduleNode.IsExpanded) {
                    for itemNode in moduleNode.Children {
                        itemRow := ++row
                        triggerDisplay := itemNode.TriggerKey != "" ? itemNode.TriggerKey : GetLang("无触发键")
                        this.ItemNodeMap[itemRow] := itemNode
                        itemNode.ListViewRow := itemRow
                        this._AddListRow(itemRow, itemNode.DisplayName, triggerDisplay, itemNode.IsChecked, 2, false, false, true)
                    }
                }
            }
        }

        this.RefreshAllStates()
    }

    _AddListRow(rowId, nameText, triggerText, checked, indentLevel, isBold, showFold, expanded) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        chkName := "MergeChk_" rowId
        foldName := "MergeFold_" rowId
        ; 三角+选框+名称整体缩进（每级 22px）
        indent := indentLevel * 22
        weight := isBold ? "SemiBold" : "Normal"
        checkedStr := checked ? "True" : "False"
        ; Segoe 箭头：展开 ChevronDown、折叠 ChevronRight（比实心 ▼/▶ 更宽、更均衡）
        foldGlyph := expanded ? "&#xE70D;" : "&#xE76C;"
        foldTip := this._XmlEsc(expanded ? GetLang("收起") : GetLang("展开"))
        iconFont := "Segoe Fluent Icons, Segoe MDL2 Assets"

        ; 无三角的叶子行保留同宽占位，使同级选框竖直对齐
        if (showFold) {
            foldXaml := '<Button Name="' foldName '" Width="20" Height="20" Padding="0" Cursor="Hand"'
                . ' Background="Transparent" BorderThickness="0" VerticalAlignment="Center"'
                . ' ToolTip="' foldTip '">'
                . '<TextBlock Text="' foldGlyph '" FontFamily="' iconFont '" FontSize="12"'
                . ' Foreground="{DynamicResource TextMain}"'
                . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
                . '</Button>'
        } else {
            foldXaml := '<Border Width="20" Height="20" Background="Transparent"/>'
        }

        xaml := '<Grid ' ns ' Height="28" Margin="0,1,0,0">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="*"/>'
            . '<ColumnDefinition Width="150"/>'
            . '</Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Orientation="Horizontal"'
            . ' Margin="' indent ',0,4,0" VerticalAlignment="Center">'
            . foldXaml
            . '<CheckBox Name="' chkName '" IsChecked="' checkedStr '"'
            . ' VerticalAlignment="Center" Margin="4,0,0,0"'
            . ' Foreground="{DynamicResource TextMain}"/>'
            . '<TextBlock Text="' this._XmlEsc(nameText) '"'
            . ' Foreground="{DynamicResource TextMain}" FontSize="12" FontWeight="' weight '"'
            . ' VerticalAlignment="Center" Margin="6,0,0,0" TextTrimming="CharacterEllipsis"/>'
            . '</StackPanel>'
            . '<TextBlock Grid.Column="1" Text="' this._XmlEsc(triggerText) '"'
            . ' Foreground="{DynamicResource TextSub}" FontSize="12"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Grid>'

        this.ui.Update("MergeListPanel", "AddXamlItem", xaml)
        this.ui.OnEvent(chkName, "Checked", ObjBindMethod(this, "OnRowCheck", rowId))
        this.ui.OnEvent(chkName, "Unchecked", ObjBindMethod(this, "OnRowCheck", rowId))
        this.ui.Update(chkName, "BindEvent", "Checked")
        this.ui.Update(chkName, "BindEvent", "Unchecked")
        if (showFold) {
            this.ui.OnEvent(foldName, "Click", ObjBindMethod(this, "OnFoldClick", rowId))
            this.ui.Update(foldName, "BindEvent", "Click")
        }
    }

    OnFoldClick(rowId, state := unset, ctrl := unset, event := unset) {
        if (!this.ItemNodeMap.Has(rowId))
            return
        node := this.ItemNodeMap[rowId]
        if (node.Type != "Tab" && node.Type != "Module")
            return
        node.IsExpanded := !(node.HasOwnProp("IsExpanded") ? node.IsExpanded : true)
        this.PopulateListView()
    }

    OnRowCheck(rowId, state, ctrl, event) {
        if (this._applyingUI)
            return
        if (!this.ItemNodeMap.Has(rowId))
            return

        node := this.ItemNodeMap[rowId]
        newState := (event == "Checked")
        node.IsChecked := newState

        if (node.Type == "Tab") {
            for moduleNode in node.Children {
                moduleNode.IsChecked := newState
                MergeUtil.SetChildrenChecked(moduleNode, newState)
            }
        }
        else if (node.Type == "Module") {
            MergeUtil.SetChildrenChecked(node, newState)
        }

        this.RefreshAllStates()
    }

    RefreshAllStates() {
        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Module" && node.IsModuleNode) {
                allChecked := true
                anyChecked := false
                hasChildren := false
                for child in node.Children {
                    hasChildren := true
                    if (child.IsChecked)
                        anyChecked := true
                    else
                        allChecked := false
                }
                if (hasChildren)
                    node.IsChecked := anyChecked
            }
        }

        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Tab" && node.IsTabNode) {
                allModulesChecked := true
                anyModuleChecked := false
                hasChildren := false
                for moduleNode in node.Children {
                    hasChildren := true
                    moduleAllChecked := true
                    moduleAnyChecked := false
                    for item in moduleNode.Children {
                        if (item.IsChecked)
                            moduleAnyChecked := true
                        else
                            moduleAllChecked := false
                    }
                    if (moduleAnyChecked)
                        anyModuleChecked := true
                    if (!moduleAllChecked || !moduleAnyChecked)
                        allModulesChecked := false
                }
                if (hasChildren)
                    node.IsChecked := anyModuleChecked
            }
        }

        count := this._CountCheckedItems(this.TreeRoot)
        this._applyingUI := true
        try {
            for rowNum, node in this.ItemNodeMap
                this.ui.Update("MergeChk_" rowNum, "IsChecked", node.IsChecked ? "True" : "False")
            this.ui.Update("SelectedCountText", "Text", count "")
        } finally {
            this._applyingUI := false
        }
    }

    _CountCheckedItems(node) {
        if (!node)
            return 0
        count := (node.Type == "Item" && node.IsChecked) ? 1 : 0
        if (node.HasOwnProp("Children")) {
            for child in node.Children
                count += this._CountCheckedItems(child)
        }
        return count
    }

    _CollectCheckedItems(node, arr) {
        if (!node)
            return
        if (node.Type == "Item" && node.IsChecked)
            arr.Push(node)
        if (node.HasOwnProp("Children")) {
            for child in node.Children
                this._CollectCheckedItems(child, arr)
        }
    }

    OnExecuteMerge(state := unset, ctrl := unset, event := unset) {
        if (!this.TreeRoot) {
            MsgBox(GetLang("请先选择源配置"), GetLang("提示"), 0x40)
            return
        }

        checkedItems := []
        this._CollectCheckedItems(this.TreeRoot, checkedItems)

        if (checkedItems.Length == 0) {
            MsgBox(GetLang("请至少选择一个宏进行导入"), GetLang("提示"), 0x40)
            return
        }

        sourceDir := this.IsFromRmt ? MergeUtil.TempMergeDir : this.SourcePath

        serialReplaceMap := MergeUtil.PreviewSerialReplaceMap(checkedItems, sourceDir)
        if (GetObjectCount(serialReplaceMap) > 0) {
            tipStr := GetLang("检测到以下资源序列号与当前配置存在冲突，将自动重命名：") "`n`n"
            shown := 0
            for oldSerial, newSerial in serialReplaceMap {
                tipStr .= "  - " oldSerial " → " newSerial "`n"
                shown++
                if (shown >= 30) {
                    tipStr .= "  ...`n"
                    break
                }
            }
            MsgBox(tipStr, GetLang("资源冲突提示"), 0x0)
        }

        varReplaceMap := MergeUtil.PreviewVarReplaceMap(checkedItems, sourceDir)
        if (GetObjectCount(varReplaceMap) > 0) {
            tipStr := GetLang("检测到以下变量名与当前配置存在冲突，将仅在导入侧自动重命名：") "`n`n"
            shown := 0
            for oldName, newName in varReplaceMap {
                tipStr .= "  - " oldName " → " newName "`n"
                shown++
                if (shown >= 30) {
                    tipStr .= "  ...`n"
                    break
                }
            }
            MsgBox(tipStr, GetLang("变量冲突提示"), 0x0)
        }

        moduleCount := MergeUtil.GetModuleCountFromItems(checkedItems)
        resultMsg := Format("{}: {}`n{}: {}`n{}: {}",
            GetLang("来源配置"), this.SourceName,
            GetLang("导入模块数"), moduleCount,
            GetLang("导入宏数"), checkedItems.Length)

        confirmResult := MsgBox(resultMsg, GetLang("确认合并导入"), 0x24 | 0x40)
        if (confirmResult != "Yes")
            return

        try {
            result := MergeUtil.ExecuteMerge(checkedItems, this.SourceName)

            successMsg := GetLang("合并导入成功") "!`n`n"
            successMsg .= Format("{}: {}`n", GetLang("创建模块数"), result.ModuleCount)
            successMsg .= Format("{}: {}`n", GetLang("导入宏数"), checkedItems.Length)
            successMsg .= Format("{}: {}", GetLang("来源配置"), result.SourceName)

            if (result.RenamedResources.Length > 0)
                successMsg .= "`n" Format("{}: {}", GetLang("重命名资源"), result.RenamedResources.Length)
            if (result.RenamedVariables.Length > 0)
                successMsg .= "`n" Format("{}: {}", GetLang("重命名变量"), result.RenamedVariables.Length)
            if (result.CopiedImages.Length > 0)
                successMsg .= "`n" Format("{}: {}", GetLang("复制图片"), result.CopiedImages.Length)

            MsgBox(successMsg, GetLang("成功"), 0x0)
            this.OnClose()
            ; §18 合并导入改内存宏表：不依赖「应用并保存」，此处显式落盘全部表+表集合
            SaveAllTableItemInfo(MySoftData.TableInfo)
            OnSaveSetting()
        } catch as e {
            MsgBox(GetLang("合并导入失败: ") e.Message, GetLang("错误"), 0x10)
        }
    }

    _XmlEsc(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }
}
