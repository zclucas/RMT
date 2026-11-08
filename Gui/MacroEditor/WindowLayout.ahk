
    _EditLayoutStyles() {
        bodyFs := XAMLHost.MacroBodyFontSize()
        fold := '<Style x:Key="RmtFoldToolBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="31"/><Setter Property="Height" Value="31"/><Setter Property="MinHeight" Value="31"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter Property="BorderThickness" Value="1.5"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid>'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border><Rectangle x:Name="BottomLine" Height="1.5" VerticalAlignment="Bottom" Margin="3,0,3,0" Fill="{TemplateBinding BorderBrush}" IsHitTestVisible="False"/>'
            . '</Grid><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="BottomLine" Property="Fill" Value="{DynamicResource Accent}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="BottomLine" Property="Fill" Value="{DynamicResource Accent}"/></Trigger>'
            . MacroDebugToolbar.ActiveTrigger()
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        okBtn := '<Style x:Key="RmtEditOkBtn" TargetType="Button">'
            . '<Setter Property="Height" Value="31"/><Setter Property="MinHeight" Value="31"/><Setter Property="MinWidth" Value="72"/>'
            . '<Setter Property="Padding" Value="12,0"/><Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource Accent}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '<Setter Property="BorderThickness" Value="1.5"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource ActionText}"/>'
            . '<Setter Property="FontSize" Value="' bodyFs '"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.92"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        modeTab := '<Style x:Key="RmtEditModeTab" TargetType="Button">'
            . '<Setter Property="Height" Value="36"/><Setter Property="MinHeight" Value="36"/><Setter Property="MaxHeight" Value="36"/>'
            . '<Setter Property="Padding" Value="12,0"/><Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Grid ClipToBounds="False">'
            . '<Border x:Name="Bd" Background="Transparent" BorderThickness="0" Padding="{TemplateBinding Padding}" Cursor="Hand">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource TextMain}" TextElement.FontSize="' bodyFs '" TextElement.FontWeight="SemiBold"/>'
            . '</Border>'
            . '<Ellipse x:Name="SelDot" Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,3,3,0" Visibility="Collapsed" IsHitTestVisible="False"/>'
            . '</Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="Tag" Value="first"><Setter TargetName="Bd" Property="CornerRadius" Value="2,0,0,2"/></Trigger>'
            . '<Trigger Property="Tag" Value="last"><Setter TargetName="Bd" Property="CornerRadius" Value="0,2,2,0"/></Trigger>'
            . '<Trigger Property="Tag" Value="sel-first"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/><Setter TargetName="Bd" Property="CornerRadius" Value="2,0,0,2"/><Setter TargetName="SelDot" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="Tag" Value="sel-last"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/><Setter TargetName="Bd" Property="CornerRadius" Value="0,2,2,0"/><Setter TargetName="SelDot" Property="Visibility" Value="Visible"/></Trigger>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="sel-first"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/></MultiTrigger>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="sel-last"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/></MultiTrigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        graphFloat := '<Style x:Key="RmtEditGraphFloat" TargetType="Button">'
            . '<Setter Property="Height" Value="31"/><Setter Property="MinHeight" Value="31"/><Setter Property="MinWidth" Value="72"/>'
            . '<Setter Property="Padding" Value="12,0"/><Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Opacity" Value="0.94"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter Property="BorderThickness" Value="1.5"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource TextMain}" TextElement.FontSize="' bodyFs '"/>'
            . '</Border><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter Property="Opacity" Value="1"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
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
        svImplicit := StrReplace(svStyle, 'x:Key="RmtThemedScrollViewer" ', '')
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
        return fold okBtn modeTab graphFloat sbThumb sbV sbH svStyle svImplicit cmdRow catHead
    }

    _AddEditFoldBtn(bar, name, glyph, tip, isToggle := false) {
        host := bar.Add("Grid").Margin("0,0,7,0").ClipToBounds("False")
        btn := host.Add("Button").Name(name).Style("{StaticResource RmtFoldToolBtn}")
            .Width(31).Height(31).MinHeight(31)
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14)
            .ToolTip(tip)
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}")
            .BorderThickness("1.5")
            .Foreground("{DynamicResource TextMain}")
        if (glyph != "")
            btn.Content(glyph)
        if (isToggle) {
            dotHost := host.Add("Grid").Name(name "Dot").Visibility("Collapsed").IsHitTestVisible("False")
            dotHost.Add("Ellipse").Width(7).Height(7).Fill("{DynamicResource Accent}")
                .HorizontalAlignment("Right").VerticalAlignment("Top")
                .Margin("0,1,1,0").IsHitTestVisible("False")
        }
        return btn
    }

    _AddEditVSplit(bar) {
        bar.Add("Rectangle").Width(1).Height(20).Fill("{DynamicResource ControlBorder}")
            .VerticalAlignment("Center").Margin("8,0,12,0").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")
    }

    _AddEditModeSeg(bar) {
        seg := bar.Add("Border").Height(36).MinHeight(36).Margin("0,0,8,0").VerticalAlignment("Center")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1.5").CornerRadius("3")
            .SnapsToDevicePixels("True")
        inner := seg.Add("Grid")
        inner.Cols("Auto", "Auto", "Auto")
        this._AddEditModeBtn(inner, "BtnModeTree", GetLang("逻辑树"), 92, "sel-first").Grid_Column(0)
        inner.Add("Rectangle").Grid_Column(1).Width("1.5").Fill("{DynamicResource ControlBorder}")
            .VerticalAlignment("Stretch").Margin("0,7,0,7").IsHitTestVisible("False").SnapsToDevicePixels("True")
        this._AddEditModeBtn(inner, "BtnModeText", GetLang("文本"), 68, "last").Grid_Column(2)
        return seg
    }

    _AddEditModeBtn(parent, name, text, w, tag) {
        return parent.Add("Button").Name(name).Style("{StaticResource RmtEditModeTab}")
            .Content(text).Width(w).MinWidth(w).MaxWidth(w).Height(36).MinHeight(36).MaxHeight(36).Tag(tag)
            .Foreground("{DynamicResource TextMain}")
    }

    _SyncModeSeg(mode) {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("BtnModeTree", "Tag", Integer(mode) == 1 ? "sel-first" : "first")
        try this.ui.Update("BtnModeText", "Tag", Integer(mode) == 2 ? "sel-last" : "last")
    }

    _SyncFoldToggle(btn, on) {
        if (!IsObject(this.ui) || btn == "")
            return
        if (on) {
            try this.ui.Update(btn, "Background", "{DynamicResource ActionBg}")
            try this.ui.Update(btn, "BorderBrush", "{DynamicResource ActionStroke}")
            try this.ui.Update(btn, "Foreground", "{DynamicResource ActionText}")
            try this.ui.Update(btn "Dot", "Visibility", "Visible")
        } else {
            try this.ui.Update(btn, "Background", "{DynamicResource ControlBg}")
            try this.ui.Update(btn, "BorderBrush", "{DynamicResource ControlBorder}")
            try this.ui.Update(btn, "Foreground", "{DynamicResource TextMain}")
            try this.ui.Update(btn "Dot", "Visibility", "Collapsed")
        }
    }

    _SyncToolToggleDots() {
        if (!IsObject(this.ui) || this._sideMode)
            return
        rec := false
        try rec := this.RecordMacroCon.Value
        this._SyncFoldToggle("BtnRecord", rec)
        varOn := IsObject(this.ToolMenu) && this.ToolMenu.HasMethod("IsChecked") && this.ToolMenu.IsChecked(GetLang("变量监视"))
        tipOn := IsObject(this.ToolMenu) && this.ToolMenu.HasMethod("IsChecked") && this.ToolMenu.IsChecked(GetLang("指令显示"))
        this._SyncFoldToggle("BtnVarListen", varOn)
        this._SyncFoldToggle("BtnCmdTip", tipOn)
        this._SyncFoldToggle("BtnTopMost", this._topOn)
    }

    _OnModeTreeClick(*) {
        this._SetEditMode(1)
    }

    _OnModeTextClick(*) {
        this._SetEditMode(2)
    }

    _SetEditMode(mode) {
        if (IsObject(this.EditModeCon) && this.EditModeCon.Value == mode) {
            this._SyncModeSeg(mode)
            return
        }
        this._suppressModeChange := true
        try this.EditModeCon.Value := mode
        this._suppressModeChange := false
        this.OnChangeEditMode(Map("EditModeCombo", String(mode)), "", "")
    }

    _OnClickRecordBtn(*) {
        if (IsObject(this.RecordMacroCon))
            this.RecordMacroCon.Value := !this.RecordMacroCon.Value
        this._SyncFoldToggle("BtnRecord", IsObject(this.RecordMacroCon) && this.RecordMacroCon.Value)
        this.OnClickRecordTog()
    }

    _OnToggleZoom(*) {
        if (this._allExpanded)
            this.CollapseAll()
        else
            this.ExpandAll()
        this._allExpanded := !this._allExpanded
    }

    _BuildAndShow(CommandStr, ShowSaveBtn) {
        global MySoftData
        this._closed := false
        this.Gui := MacroEditGuiFacade(this)
        title := this.ParentTile GetLang("宏指令编辑器")
        this._title := title
        titleHeight := XAMLHost.MacroTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.VisualFontSizeDeclared())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddMacroTitleBar(main, title)

        ; === 主体：左指令列表贯穿全高，右为工具栏 + 树 ===
        body := main.Add("Grid").Grid_Row(1)

        ; 隐藏菜单宿主（调试/工具/树右键/指令收藏）
        menuHost := body.Add("Grid").Name("EditMenuHost").Width("0").Height("0").Visibility("Collapsed")
        combo := menuHost.Add("ComboBox").Name("EditModeCombo").SelectedIndex("0").Visibility("Collapsed")
        combo.Add("ComboBoxItem").Content(GetLang("逻辑树")).Tag("1")
        combo.Add("ComboBoxItem").Content(GetLang("文本")).Tag("2")
        menuHost.Add("CheckBox").Name("RecordTog").Visibility("Collapsed")
        menuHost.Add("Button").Name("SaveBtn").Visibility("Collapsed")
        dbgHost := menuHost.Add("Border").Name("MenuDebugHost")
        dbgCM := dbgHost.Add("Border.ContextMenu").Add("ContextMenu").Name("MenuDebugCM").MinWidth("160").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Foreground("{DynamicResource TextMain}").InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        dbgCM.Add("MenuItem").Name("MenuContinue").Header(this._ContinueLabel())
        dbgCM.Add("MenuItem").Name("MenuStepOver").Header(this._StepOverLabel())
        dbgCM.Add("MenuItem").Name("MenuStepInto").Header(this._StepIntoLabel())
        dbgCM.Add("MenuItem").Name("MenuStepOut").Header(this._StepOutLabel())
        dbgCM.Add("MenuItem").Name("MenuRunToCursor").Header(this._RunToCursorLabel())
        dbgCM.Add("Separator")
        dbgCM.Add("MenuItem").Name("MenuToggleSkip").Header(this._ToggleSkipLabel())
        dbgCM.Add("MenuItem").Name("MenuDebugRun").Header(this._DebugRunLabel())
        dbgCM.Add("Separator")
        dbgCM.Add("MenuItem").Name("MenuKill").Header(GetLang("终止"))
        toolHost := menuHost.Add("Border").Name("MenuToolHost")
        toolCM := toolHost.Add("Border.ContextMenu").Add("ContextMenu").Name("MenuToolCM").MinWidth("160").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Foreground("{DynamicResource TextMain}").InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        toolCM.Add("MenuItem").Name("MenuVarListen").Header(GetLang("变量监视")).IsCheckable("True")
        toolCM.Add("MenuItem").Name("MenuCmdTip").Header(GetLang("指令显示")).IsCheckable("True")
        toolCM.Add("MenuItem").Name("MenuTopMost").Header(GetLang("窗口置顶")).IsCheckable("True")
        favCtxHost := menuHost.Add("Border").Name("CmdFavHost")
        favCM := favCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("CmdFavCM").MinWidth("120").Placement("MousePoint")
            .InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        this._ApplyCtxMenuTheme(favCM)
        favCM.Add("MenuItem").Name("MenuFavToggle").Header(GetLang("收藏"))

        ; 树右键菜单（普通指令 / 分支容器 / 空白区），挂在 0 尺寸隐藏 Border 上，Placement=MousePoint
        treeCtxHost := menuHost.Add("Border").Name("TreeCtxHost")
        treeCtx := treeCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("TreeCtxMenu").MinWidth("180").Placement("MousePoint")
            .InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        this._ApplyCtxMenuTheme(treeCtx)
        ; 编辑 | 复制、粘贴 | 上插、下插 | 跳过、调试起点 | 删除
        treeCtx.Add("MenuItem").Name("MenuEditCmd").Header(GetLang("编辑"))
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("MenuCopyCmd").Header(GetLang("复制"))
        treeCtx.Add("MenuItem").Name("MenuPasteCmd").Header(GetLang("粘贴"))
        treeCtx.Add("Separator")
        miInsertPre := treeCtx.Add("MenuItem").Name("MenuInsertPreCmd").Header(GetLang("上插指令"))
        this._AddCmdMenuItems(miInsertPre, "MenuInsertPre_")
        miInsertNext := treeCtx.Add("MenuItem").Name("MenuInsertNextCmd").Header(GetLang("下插指令"))
        this._AddCmdMenuItems(miInsertNext, "MenuInsertNext_")
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("MenuSkipCmd").Header(GetLang("跳过指令"))
        treeCtx.Add("MenuItem").Name("MenuDebugCmd").Header(GetLang("调试起点"))
        ; F3：仅在宿主已接线断点持久化时才显示（子集子编辑器默认隐藏，避免误设后静默丢失）
        treeCtx.Add("MenuItem").Name("MenuBpCmd").Header(GetLang("断点")).Visibility(this._bpAllowed ? "Visible" : "Collapsed")
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("MenuDeleteCmd").Header(GetLang("删除"))

        branchCtxHost := menuHost.Add("Border").Name("BranchCtxHost")
        branchCtx := branchCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("BranchCtxMenu").MinWidth("180").Placement("MousePoint")
            .InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        this._ApplyCtxMenuTheme(branchCtx)
        miAdd := branchCtx.Add("MenuItem").Name("MenuBranchAddCmd").Header(GetLang("添加指令"))
        this._AddCmdMenuItems(miAdd, "MenuBranchAdd_")
        branchCtx.Add("Separator")
        branchCtx.Add("MenuItem").Name("MenuBranchDelete").Header(GetLang("删除"))
        branchCtx.Add("MenuItem").Name("MenuBranchUndoCmd").Header(GetLang("撤销一步"))

        blankCtxHost := menuHost.Add("Border").Name("TreeBlankCtxHost")
        blankCtx := blankCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("TreeBlankCtxMenu").MinWidth("180").Placement("MousePoint")
            .InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        this._ApplyCtxMenuTheme(blankCtx)
        miBlankIns := blankCtx.Add("MenuItem").Name("MenuBlankInsertCmd").Header(GetLang("插入指令"))
        this._AddCmdMenuItems(miBlankIns, "MenuBlankInsert_")
        blankCtx.Add("MenuItem").Name("MenuBlankPasteCmd").Header(GetLang("粘贴"))

        content := body.Add("Grid")
        content.Cols("228", "*")
        content.Rows("56", "*")

        ; 左侧指令面板（无左边框，右边框作分割线）
        left := content.Add("Border").Grid_Column(0).Grid_RowSpan(2)
            .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness("0,0,1.5,0")
            .Padding("4,4,0,0").Background("Transparent")
        this._BuildCmdPanel(left)

        ; 顶部工具条（仅覆盖树区域）
        toolWrap := content.Add("Border").Grid_Column(1).Grid_Row(0)
            .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness("0,0,0,1.5")
        toolRow := toolWrap.Add("Grid")
        toolRow.Cols("*", "Auto")
        recTip := GetLang("指令录制")
        try recTip := recTip "  " FormatHotkeyDisplay(MainSoftData.ToolRecordMacroHotKey)

        leftTools := toolRow.Add("StackPanel").Grid_Column(0).Orientation("Horizontal").VerticalAlignment("Center").Margin("8,0,0,0")
        this._AddEditModeSeg(leftTools)
        this._AddEditVSplit(leftTools)

        this._AddEditFoldBtn(leftTools, "BtnRecord", Chr(0xE7C8), recTip, true)
        this._AddEditFoldBtn(leftTools, "BtnExpand", Chr(0xE73F), GetLang("缩放"))
        this._AddEditFoldBtn(leftTools, "BtnUndo", Chr(0xE7A7), GetLang("撤销")).IsEnabled("False")
        this._AddEditFoldBtn(leftTools, "BtnRedo", Chr(0xE7A6), GetLang("恢复")).IsEnabled("False")
        this._AddEditFoldBtn(leftTools, "BtnBack", Chr(0xE750), GetLang("删除末尾"))
        this._AddEditFoldBtn(leftTools, "BtnClear", Chr(0xE74D), GetLang("清空"))
        this._AddEditVSplit(leftTools)

        this._AddEditFoldBtn(leftTools, "BtnDebugToolbar", Chr(0xEBE8), GetLang("调试"), true)
        this._AddEditVSplit(leftTools)

        this._AddEditFoldBtn(leftTools, "BtnVarListen", Chr(0xE7B3), GetLang("变量监视"), true)
        tipBtn := this._AddEditFoldBtn(leftTools, "BtnCmdTip", "", GetLang("指令显示"), true)
        tipG := tipBtn.Add("Grid").Width(16).Height(14).HorizontalAlignment("Center").VerticalAlignment("Center")
        tipG.Add("Rectangle").Width("1.8").Height(14).Fill("{DynamicResource TextMain}").HorizontalAlignment("Left").RadiusX("0.6").RadiusY("0.6")
        tipLines := tipG.Add("StackPanel").Orientation("Vertical").HorizontalAlignment("Right").VerticalAlignment("Center").Margin("3,0,0,0")
        loop 3
            tipLines.Add("Rectangle").Width(11).Height("1.8").Fill("{DynamicResource TextMain}").RadiusX("0.6").RadiusY("0.6").Margin(A_Index < 3 ? "0,0,0,2" : "0")
        this._AddEditFoldBtn(leftTools, "BtnTopMost", Chr(0xE840), GetLang("窗口置顶"), true)

        rightTools := toolRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center").Margin("0,0,8,0")
        rightTools.Add("Button").Name("BtnOk").Content(GetLang("确定")).Style("{StaticResource RmtEditOkBtn}")
            .Height(31).MinHeight(31).Padding("12,0")

        view := content.Add("Grid").Grid_Column(1).Grid_Row(1)
        ; 关虚拟化（注入真实 ListBoxItem，虚拟化会导致插入后滚动条复位）+ 去 ListBoxItem 默认内边距/选中高亮
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="Transparent" SnapsToDevicePixels="True"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>'
        view.Add("ListBox").Name("MacroTree").Background("{DynamicResource BgColor}").Foreground("{DynamicResource TextMain}")
            .FontSize(XAMLHost.MacroBodyFontSize())
            .BorderThickness("0").Padding("0")
            .VirtualizingPanel_IsVirtualizing("False")
            .ScrollViewer_HorizontalScrollBarVisibility("Auto").ScrollViewer_VerticalScrollBarVisibility("Auto")
            .InjectResources(lbStyle)
        ; 拖拽插入指示线（覆盖在树上，拖拽时定位，不重建树）
        view.Add("Border").Name("DragInsertLine").Height(2).HorizontalAlignment("Stretch").VerticalAlignment("Top")
            .Background("{DynamicResource Accent}").BorderThickness(0)
            .SetProp("Panel.ZIndex", "10").Visibility("Collapsed").IsHitTestVisible("False")
        ; 拖拽幽灵（跟鼠标，仅显示指令文本，风格对齐宏配置 VL 拖拽）
        ghostPop := view.Add("Popup").Name("DragGhost").Placement("Absolute").AllowsTransparency("True")
            .IsHitTestVisible("False").IsOpen("False")
        ghostBd := ghostPop.Add("Border").CornerRadius("3").BorderThickness("1").Padding("10,5")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource Accent}").Opacity("0.94")
        ghostBd.Add("TextBlock").Name("DragGhostTxt").MaxWidth("280").TextTrimming("CharacterEllipsis")
            .Foreground("{DynamicResource TextMain}").FontSize(XAMLHost.MacroBodyFontSize())
        view.Add("TextBox").Name("MacroText").AcceptsReturn("True").FontSize(XAMLHost.MacroBodyFontSize()).Visibility("Collapsed")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("0")
            .ScrollViewer_HorizontalScrollBarVisibility("Auto").ScrollViewer_VerticalScrollBarVisibility("Auto")
        view.Add("Button").Name("BtnGraphNode").Content(GetLang("图形节点"))
            .Style("{StaticResource RmtEditGraphFloat}")
            .Height(31).MinHeight(31)
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,8,8,0")
            .SetProp("Panel.ZIndex", "20")
            .ToolTip(GetLang("图形节点"))

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1400" Height="867"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._EditLayoutStyles())

        ; === 控件适配器 ===
        this.MacroTreeViewCon := MacroTreeAdapter(this.ui, this.treeName)
        this.MacroTreeViewCon.rootSlot := 14
        this.MacroTreeViewCon.cardPad := "0,0,4,0"
        this.MacroTreeViewCon.SetIconMap(this.IconFileByNumber)
        this.MacroEditTextCon := MacroTextBox(this.ui, "MacroText")
        this.EditModeCon := MacroCombo(this.ui, "EditModeCombo")
        this.RecordMacroCon := MacroCheckBox(this.ui, "RecordTog")
        this.SaveBtnCtrl := MacroButton(this.ui, "SaveBtn")
        this.ToolMenu := MacroMenuAdapter(this.ui)

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        ; §8 帮助/视频占位
        this.ui.OnEvent("BtnCmdHelp", "Click", ObjBindMethod(this, "OnCmdHelpClick"))
        this.ui.OnEvent("BtnCmdVideo", "Click", ObjBindMethod(this, "OnCmdVideoClick"))
        this.ui.OnEvent("EditModeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeEditMode"))
        this.ui.OnEvent("RecordTog", "Click", ObjBindMethod(this, "OnClickRecordTog"))
        this.ui.OnEvent("BtnModeTree", "Click", ObjBindMethod(this, "_OnModeTreeClick"))
        this.ui.OnEvent("BtnModeText", "Click", ObjBindMethod(this, "_OnModeTextClick"))
        this.ui.OnEvent("BtnGraphNode", "Click", ObjBindMethod(this, "OnSwitchToGraphEditor"))
        this.ui.OnEvent("BtnRecord", "Click", ObjBindMethod(this, "_OnClickRecordBtn"))
        this.ui.OnEvent("BtnBack", "Click", (*) => this.Backspace())
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearStr())
        this.ui.OnEvent("BtnUndo", "Click", (*) => this.Undo())
        this.ui.OnEvent("BtnRedo", "Click", (*) => this.Redo())
        this.ui.OnEvent("BtnOk", "Click", (*) => this.OnSureBtnClick())
        this.ui.OnEvent("SaveBtn", "Click", (*) => this.OnSaveBtnClick())
        this.ui.OnEvent("BtnExpand", "Click", ObjBindMethod(this, "_OnToggleZoom"))
        this._debugToolbar := MacroDebugToolbar(this.ui, "BtnDebugToolbar", "BtnDebugToolbarDot"
            , this.treeName, this, ObjBindMethod(MacroDebugToolbar, "Run", this))
        this.ui.OnEvent("BtnVarListen", "Click", (*) => this.MenuHandler(GetLang("变量监视")))
        this.ui.OnEvent("BtnCmdTip", "Click", (*) => this.MenuHandler(GetLang("指令显示")))
        this.ui.OnEvent("BtnTopMost", "Click", (*) => this.MenuHandler(GetLang("窗口置顶")))
        this.ui.OnEvent("MenuContinue", "Click", (*) => this.MenuHandler(this._ContinueLabel()))
        this.ui.OnEvent("MenuStepOver", "Click", (*) => this.MenuHandler(this._StepOverLabel()))
        this.ui.OnEvent("MenuStepInto", "Click", (*) => this.MenuHandler(this._StepIntoLabel()))
        this.ui.OnEvent("MenuStepOut", "Click", (*) => this.MenuHandler(this._StepOutLabel()))
        this.ui.OnEvent("MenuRunToCursor", "Click", (*) => this.MenuHandler(this._RunToCursorLabel()))
        this.ui.OnEvent("MenuToggleSkip", "Click", (*) => this.MenuHandler(this._ToggleSkipLabel()))
        this.ui.OnEvent("MenuDebugRun", "Click", (*) => this.MenuHandler(this._DebugRunLabel()))
        this.ui.OnEvent("MenuKill", "Click", (*) => this.MenuHandler(GetLang("终止")))
        this.ui.OnEvent("MenuVarListen", "Click", (*) => this.MenuHandler(GetLang("变量监视")))
        this.ui.OnEvent("MenuCmdTip", "Click", (*) => this.MenuHandler(GetLang("指令显示")))
        this.ui.OnEvent("MenuTopMost", "Click", (*) => this.MenuHandler(GetLang("窗口置顶")))

        this._BindTreeInteractionEvents()
        this._BindTreeContextMenuEvents()

        for config in this.SubGuiConfig {
            guiInstance := this.%config.propName%
            btnName := "CmdBtn_" config.propName
            this.ui.OnEvent(btnName, "Click", CreateSubGuiClickHandler(this, guiInstance))
            this.ui.OnEvent(btnName, "PreviewMouseLeftButtonDown", this._OnPanelDragStart.Bind(this, guiInstance, GetLang(config.name)))
            ; §13 收藏区行（同名指令按钮，点击/拖拽同分类区）
            this.ui.OnEvent("CmdBtnFav_" config.propName, "Click", CreateSubGuiClickHandler(this, guiInstance))
            this.ui.OnEvent("CmdBtnFav_" config.propName, "PreviewMouseLeftButtonDown", this._OnPanelDragStart.Bind(this, guiInstance, GetLang(config.name)))
            this.ui.OnEvent(btnName, "PreviewMouseRightButtonDown", this._OnCmdRowRightClick.Bind(this, config.propName))
            this.ui.OnEvent("CmdBtnFav_" config.propName, "PreviewMouseRightButtonDown", this._OnCmdRowRightClick.Bind(this, config.propName))
        }
        for idx, cat in this.CmdCategory {
            this.ui.OnEvent("CatToggle_" idx, "Click", this._OnToggleCat.Bind(this, idx))
        }
        this.ui.OnEvent("FavToggle", "Click", ObjBindMethod(this, "_OnToggleFavSection"))
        this.ui.OnEvent("MenuFavToggle", "Click", ObjBindMethod(this, "_OnMenuFavToggle"))
        this.ui.OnEvent("CmdFilter", "TextChanged", ObjBindMethod(this, "_OnCmdFilterChanged"))

        this.ui.Track("EditModeCombo")
        this.ui.Track("MacroText")
        this.ui.Track("CmdFilter")
        this.ui.Track(this.treeName)

        ; WPF ComboBox 默认 SelectedIndex=-1（不自动选第一项），强制选中「逻辑树」
        ; 构建期抑制 SelectionChanged：否则会先 InitTreeView(空) 再被灌树刷第二次 → 闪一下
        this._suppressModeChange := true
        ; ===== 主题/快捷键同款：先填充内容（Show 前入队，LoadedHwnd 时一次刷入）=====
        try {
            this.Init(CommandStr, ShowSaveBtn)
        } catch {
        }
        this.ui.Update("EditModeCombo", "SelectedIndex", "0")
        try this.EditModeCon._value := 1
        this._SyncModeSeg(1)

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        ; 等待循环已消费 LoadedHwnd 刷入触发的 SelectionChanged，此时解除抑制
        this._suppressModeChange := false
    }
