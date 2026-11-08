
    _BindTreeUiEvent(ctrlName, eventName, callback) {
        if (!IsObject(this.ui) || ctrlName == "")
            return
        this.ui.OnEvent(ctrlName, eventName, callback)
        ; 主窗口侧栏在 CREATE_WINDOW 之后才 Attach：必须补 BindEvent，否则引擎不挂 WPF 事件
        try this.ui.BindEventBatched(ctrlName, eventName)
    }

    _BindTreeInteractionEvents() {
        if (!IsObject(this.ui))
            return
        this._BindTreeUiEvent(this.treeName, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnTreePreviewLeftDown"))
        this._BindTreeUiEvent(this.treeName, "PreviewMouseRightButtonDown", ObjBindMethod(this, "_OnTreePreviewRightDown"))
        this._BindTreeUiEvent(this.treeName, "PreviewKeyDown", ObjBindMethod(this, "_OnTreePreviewKeyDown"))
        ; 拖拽（树内排序、左侧指令拖入）整段在引擎里跑：命中测试、插入线、跟手幽灵都不跨进程。
        ; 这里只把三件套控件名交给引擎，并登记它在松手/取消时回报的结果事件。
        this.ui.OnEvent(this.treeName, "TreeDrop", ObjBindMethod(this, "_OnTreeDropCommitted"))
        this.ui.OnEvent(this.treeName, "TreeDropExternal", ObjBindMethod(this, "_OnTreeDropExternal"))
        this.ui.OnEvent(this.treeName, "TreeDragStart", ObjBindMethod(this, "_OnTreeDragStartNative"))
        this.ui.OnEvent(this.treeName, "TreeDragCancel", ObjBindMethod(this, "_OnTreeDragCancelNative"))
        try this.ui.Update(this.treeName, "TreeDrag"
            , this.insertLineName "|" this.dragGhostName "|" this.dragGhostTxtName)
    }

    _BindTreeContextMenuEvents() {
        if (!IsObject(this.ui))
            return
        this._BindTreeUiEvent(this.menuEditName, "Click", (*) => this.ContentMenuHandler(GetLang("编辑")))
        this._BindTreeUiEvent(this.menuSkipName, "Click", (*) => this.ContentMenuHandler("Skip"))
        this._BindTreeUiEvent(this.menuDebugName, "Click", (*) => this.ContentMenuHandler("Debug"))
        this._BindTreeUiEvent(this.menuBpName, "Click", (*) => this.ContentMenuHandler("Bp"))
        this._BindTreeUiEvent(this.menuCopyName, "Click", (*) => this.ContentMenuHandler(GetLang("复制")))
        this._BindTreeUiEvent(this.menuPasteName, "Click", (*) => this.ContentMenuHandler(GetLang("粘贴")))
        this._BindTreeUiEvent(this.menuDeleteName, "Click", (*) => this.ContentMenuHandler(GetLang("删除")))
        this._BindTreeUiEvent(this.menuBranchDeleteName, "Click", (*) => this.ContentMenuHandler(GetLang("删除")))
        this._BindTreeUiEvent(this.menuBlankPasteName, "Click", (*) => this.ContentMenuHandler(GetLang("粘贴")))
        if (!this._sideMode) {
            this._BindTreeUiEvent("MenuBranchUndoCmd", "Click", (*) => this.Undo())
        }
        for index, value in this.CMDStrArr {
            this._BindTreeUiEvent(this.menuInsertPrePrefix index, "Click", this.ContentMenuHandler.Bind(this, "Pre_" value))
            this._BindTreeUiEvent(this.menuInsertNextPrefix index, "Click", this.ContentMenuHandler.Bind(this, "Next_" value))
            this._BindTreeUiEvent(this.menuBlankInsertPrefix index, "Click", this.ContentMenuHandler.Bind(this, "Root_" value))
            this._BindTreeUiEvent(this.menuBranchAddPrefix index, "Click", this.ContentMenuHandler.Bind(this, "Add_" value))
        }
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ; 支持子菜单的 MenuItem 模板（全局主题模板缺子菜单支持，与 MacroGraph 共用方案）
    ; 不写死 FontSize：继承 ContextMenu；打开前 _SyncCtxMenuFont 写入 PopupFontSize（主题×Viewbox）
    _MenuItemSubmenuStyle() {
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? this._EscapeXml(MainSoftData.FontType) : "微软雅黑"
        return ''
            . '<Style TargetType="MenuItem">'
            .   '<Setter Property="Background" Value="Transparent"/>'
            .   '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            .   '<Setter Property="FontFamily" Value="' ff '"/>'
            .   '<Setter Property="Padding" Value="10,8"/>'
            .   '<Setter Property="Template"><Setter.Value>'
            .     '<ControlTemplate TargetType="MenuItem">'
            .       '<Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="3">'
            .         '<Grid>'
            .           '<Grid.ColumnDefinitions>'
            .             '<ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>'
            .           '</Grid.ColumnDefinitions>'
            .           '<ContentPresenter ContentSource="Icon" Margin="0,0,8,0" VerticalAlignment="Center"/>'
            .           '<ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"'
            .             ' TextElement.FontSize="{TemplateBinding FontSize}"'
            .             ' TextElement.FontFamily="{TemplateBinding FontFamily}"/>'
            .           '<TextBlock Grid.Column="2" Text="{TemplateBinding InputGestureText}" Foreground="{DynamicResource TextSub}" Margin="15,0,0,0" VerticalAlignment="Center"'
            .             ' FontSize="{TemplateBinding FontSize}" FontFamily="{TemplateBinding FontFamily}"/>'
            .           '<Path Grid.Column="3" x:Name="ArrowPath" Data="M0,0 L4,4 L0,8 Z" Fill="{DynamicResource TextMain}" Margin="8,0,2,0" VerticalAlignment="Center" Visibility="Collapsed"/>'
            .           '<Popup x:Name="PART_Popup" AllowsTransparency="True" Placement="Right" HorizontalOffset="-3" PlacementTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Focusable="False">'
            .             '<Border FlowDirection="LeftToRight" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3" Padding="4,4,0,4" MinWidth="180">'
            .               '<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False" MaxHeight="400" Margin="0" Padding="0"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" Margin="0,0,4,0"/></ScrollViewer>'
            .             '</Border>'
            .           '</Popup>'
            .         '</Grid>'
            .       '</Border>'
            .       '<ControlTemplate.Triggers>'
            .         '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger>'
            .         '<Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger>'
            .         '<Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource TextSub}"/></Trigger>'
            .         '<Trigger Property="HasItems" Value="True"><Setter TargetName="ArrowPath" Property="Visibility" Value="Visible"/></Trigger>'
            .         '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="HasItems" Value="True"/></MultiTrigger.Conditions><Setter Property="IsSubmenuOpen" Value="True"/></MultiTrigger>'
            .       '</ControlTemplate.Triggers>'
            .     '</ControlTemplate>'
            .   '</Setter.Value></Setter>'
            . '</Style>'
    }

    ; 支持滚轮滑动的 ContextMenu 模板
    _ContextMenuScrollStyle() {
        return ''
            . '<Style TargetType="ContextMenu">'
            .   '<Setter Property="Template"><Setter.Value>'
            .     '<ControlTemplate TargetType="ContextMenu">'
            .       '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="4">'
            .         '<ScrollViewer VerticalScrollBarVisibility="Auto" CanContentScroll="False">'
            .           '<ItemsPresenter/>'
            .         '</ScrollViewer>'
            .       '</Border>'
            .     '</ControlTemplate>'
            .   '</Setter.Value></Setter>'
            . '</Style>'
    }

    _ApplyCtxMenuTheme(cm) {
        if (!IsObject(cm))
            return
        ; 字体族走主题；字号在打开菜单时用 PopupFontSize（主题×Viewbox，脱离 Viewbox 的 Popup 才能跟正文一致）
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑"
        cm.FontFamily(ff)
            .Background("{DynamicResource DropdownBg}")
            .BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1")
            .Foreground("{DynamicResource TextMain}")
    }

        ; 打开右键菜单前同步字号（与 RmtDialog 同理：按主题字号，再乘主窗 Viewbox）
    _SyncCtxMenuFont(menuName := "") {
        if (!IsObject(this.ui))
            return
        names := []
        if (menuName != "")
            names.Push(menuName)
        else {
            names.Push(this.ctxMenuName)
            names.Push(this.branchCtxMenuName)
            names.Push(this.blankCtxMenuName)
        }
        fs := XAMLHost.PopupFontSize()
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑"
        oldSkip := this.ui.HasProp("skipFontScale") ? this.ui.skipFontScale : false
        this.ui.skipFontScale := true
        try {
            for name in names {
                if (name == "")
                    continue
                try this.ui.Update(name, "FontSize", String(fs))
                try this.ui.Update(name, "FontFamily", ff)
            }
        } finally {
            this.ui.skipFontScale := oldSkip
        }
    }

    ; 构建期写入：声明字号经 ApplyFontSizeDelta 后等于 PopupFontSize
    _CtxMenuFontSizeAttr() {
        return XAMLHost.PopupFontSizeDeclared()
    }

    ; 指令子菜单项 + 图标
    _AddCmdMenuItems(parentMi, namePrefix) {
        for index, value in this.CMDStrArr {
            mi := parentMi.Add("MenuItem").Name(namePrefix index).Header(value)
            iconRel := this.CmdIconFileMap.Has(value) ? this.CmdIconFileMap[value] : ""
            if (iconRel != "") {
                full := StrReplace(A_WorkingDir "\" iconRel, "\", "/")
                if (FileExist(StrReplace(full, "/", "\")))
                    mi.Add("MenuItem.Icon").Add("Image").SetProp("Source", full).Width("16").Height("16")
            }
        }
    }
