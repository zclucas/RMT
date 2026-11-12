
    ; ============ 宏列表渲染 ============
    ReadTabValues(tableItem) {
        t := tableItem.Index
        if (this._useVirtual.Has(t))
            return  ; Epic5：VL_CHANGE 已逐字段写回模型，此处 no-op
        ; 收集所有需读取的控件名，单次批量 Query（一次 daemon 往返），替代逐项轮询
        names := []
        for f, fold in tableItem.Folds {
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                if (!this._IsRendered(t, i))
                    continue
                names.Push("Remark_" t "_" i)
                names.Push("TKType_" t "_" i ">SelectedIndex")
                names.Push("Loop_" t "_" i)
            }
            names.Push("FoldRemark_" t "_" f)
            names.Push("FoldFront_" t "_" f)
            names.Push("FoldTKType_" t "_" f ">SelectedIndex")
        }
        if (names.Length == 0)
            return
        state := this.ui.Query(names*)

        for f, fold in tableItem.Folds {
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                if (!this._IsRendered(t, i))
                    continue
                if (state.Has("Remark_" t "_" i))
                    try item.Remark := state["Remark_" t "_" i]
                if (state.Has("TKType_" t "_" i ">SelectedIndex"))
                    try item.TriggerType := Integer(state["TKType_" t "_" i ">SelectedIndex"]) + 1
                if (state.Has("Loop_" t "_" i))
                    try item.LoopCount := (state["Loop_" t "_" i] == GetLang("无限")) ? "-1" : state["Loop_" t "_" i]
            }
            if (state.Has("FoldRemark_" t "_" f))
                try fold.Remark := state["FoldRemark_" t "_" f]
            if (state.Has("FoldFront_" t "_" f))
                try fold.FrontInfo := state["FoldFront_" t "_" f]
            if (state.Has("FoldTKType_" t "_" f ">SelectedIndex"))
                try fold.TKType := Integer(state["FoldTKType_" t "_" f ">SelectedIndex"]) + 1
        }
    }

    _IsRendered(t, i) {
        return this.RenderedItems.Has(t) && this.RenderedItems[t].Has(i)
    }

    RenderTab(tableItem) {
        t := tableItem.Index
        ; 非宏表（Tool/Setting/Help/Reward/Thank）用专用 Panel_ 构建，不走 FoldList 渲染
        if (!this._useVirtual.Has(t) && !CheckIsItemTable(t))
            return
        if (this._useVirtual.Has(t)) {
            ; Epic5：1 次 VL_INIT 填充虚拟列表（模型已由 VL_CHANGE 保持，视图全量重建成本 O(1) IPC）
            this._vl.Init(t, tableItem)
            if (this._IsAiPanelOpen())
                this._vl.SetCompact(t, true)
            return
        }
        this.RenderedItems[t] := Map()
        listName := "FoldList_" t
        this.ui.Update(listName, "ClearItems", "")
        ; B: 每模块 1 次 AddXamlItem 批量渲染（整组一个根 StackPanel），不再逐行 N 次桥接往返。
        ;    注意不能增量逐批加子项：StackPanel 每加一个子项就全量重测量（增量 = O(n²)），整组一次加 = O(n)。
        ; A: 折叠行也全渲染进 FoldItems_<t>_<f> 子容器，折叠切换只切容器 Visibility 不重建（千条级折叠/展开瞬间，滚动位置保留）
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        for f, fold in tableItem.Folds {
            vis := fold.FoldState ? ' Visibility="Collapsed"' : ""
            xaml := '<StackPanel ' ns '>'
                . this._BuildFoldTitleRow(t, f, f == 1)
                . '<StackPanel Name="FoldItems_' t '_' f '"' vis '>'
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                xaml .= this._BuildItemRow(t, i)
                this.RenderedItems[t][i] := true
            }
            xaml .= '</StackPanel></StackPanel>'
            this.ui.Update(listName, "AddXamlItem", xaml)
        }
        ; 绑定须在 AddXamlItem 之后（控件已存在）
        ; 折叠态行隐藏且事件不可达：跳过 BindEvent（千条级折叠组省 ~9×N 次桥接往返），
        ; 展开折叠时由 OnFoldBtnClick 补绑（_Bind 清旧再挂，幂等）
        for f, fold in tableItem.Folds {
            if (fold.FoldState)
                continue
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                this._BindItemRow(t, i)
            }
        }
        this._BindFoldRows(t)
    }

    ; 界面宏触发类型右侧的浮窗位置。虚拟列表里菜单宏触发类型可编辑，用该状态把按钮收起。
    _BuildFoldPosBtnXaml(t, f, vlMode) {
        tip := GetLang("浮窗位置")
        icon := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="4,0,0,0" Content="&#xE713;" ToolTip="' tip '"'
        if (vlMode) {
            return '<Button Tag="FoldPos"' icon '>'
                . '<Button.Style><Style TargetType="Button" BasedOn="{StaticResource RmtFoldToolBtn}">'
                . '<Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding FoldTKTypeEnabled}" Value="False">'
                . '<Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Button.Style></Button>'
        }
        if (t < 1 || GetTableSymbol(t) != "UI")
            return ""
        return '<Button Name="FoldPosBtn_' t '_' f '" Style="{StaticResource RmtFoldToolBtn}"' icon '/>'
    }

    _BuildFoldTitleRow(t, f, isFirst := false) {
        fold := MySoftData.TableInfo[t].Folds[f]
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        foldBg := fold.ForbidState ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource FoldHeaderBg}"
        xaml := '<Border ' ns ' Name="FoldCard_' t '_' f '" CornerRadius="0" BorderThickness="0" BorderBrush="{DynamicResource OutlineStroke}" Background="' foldBg '" Margin="0" Padding="8,6,8,6" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<StackPanel Name="FoldCardInner_' t '_' f '" Opacity="' (fold.ForbidState ? this._ForbidContentOpacity() : "1") '" VerticalAlignment="Center" TextElement.FontSize="' XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11)) '">'
            . this._BuildFoldDividerXaml(false, isFirst)
            . this._BuildFoldHeaderRowXaml(t, f, fold, false)
        if (isMenu || isUI) {
            tkStr := FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(fold.TK))
            xaml .= '<Grid Margin="0,4,0,0" Visibility="' (fold.FoldState ? "Collapsed" : "Visible") '">'
                . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
                . '<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">'
                . this._TriggerEntries('<Button Name="FoldTKEdit_' t '_' f '" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang("触发键") '">' this._BuildTKBtnInnerXaml(tkStr, false) '</Button>', false, "FoldTKEdit_" t "_" f, tkStr)
                . this._GestureEntries(false, "FoldGesture_" t "_" f "_", , true)
                . '<ComboBox Name="FoldTKType_' t '_' f '" Style="{StaticResource RmtItemCombo}" Width="82" Margin="0" SelectedIndex="' (fold.TKType - 1) '" IsEnabled="' (isUI ? "False" : "True") '" ToolTip="' GetLang("触发类型") '">'
                . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
                . '</ComboBox>' this._BuildFoldPosBtnXaml(t, f, false) '</StackPanel></Grid>'
        }
        xaml .= '</StackPanel></Border>'
        return xaml
    }

    _BuildFoldLayoutColDefs() {
        gap := this._FoldGroupGap()
        if (this._IsAiPanelOpen()) {
            wideGap := 8 + this._foldFrontShift
            gapCol := '<ColumnDefinition Width="100*" MinWidth="' this._AiPanelGapMin() '" MaxWidth="' wideGap '"/>'
            lastCol := '<ColumnDefinition Width="*"/>'
        } else {
            gapCol := '<ColumnDefinition Width="' gap '"/>'
            lastCol := '<ColumnDefinition Width="*"/>'
        }
        remarkGroupW := 24 + 6 + this._foldFieldW
        frontGroupW := 20 + 6 + this._foldFrontW + 4 + 24 + 4 + 24
        ; 四个带右间距的按钮 + 最右侧删除按钮，防止删除被列宽裁掉。
        toolbarW := 4 * (24 + 4) + 24
        return '<ColumnDefinition Width="' remarkGroupW '"/>' gapCol
            . '<ColumnDefinition Width="' frontGroupW '"/>' gapCol
            . '<ColumnDefinition Width="' toolbarW '"/>' lastCol
    }

    ; 模块头主行：备注 | 间距 | 前台 | 同距 | 操作按钮 | 剩余
    _BuildFoldHeaderRowXaml(t, f, fold, vlMode) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        folded := vlMode ? false : fold.FoldState
        remark := vlMode ? "" : fold.Remark
        frontInfo := vlMode ? "" : fold.FrontInfo
        forbidState := vlMode ? false : fold.ForbidState
        return '<Grid ' ns ' VerticalAlignment="Center">'
            . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">' this._BuildFoldCollapseBtnXaml(t, f, folded, vlMode) this._BuildFoldRemarkFieldXaml(t, f, remark, vlMode) '</StackPanel>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center"' this._FoldFrontVisAttr(t, vlMode) '>' this._BuildFoldFrontCenterXaml(t, f, frontInfo, vlMode) '</StackPanel>'
            . '<StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center">' this._BuildFoldToolbarXaml(t, f, forbidState, vlMode) '</StackPanel>'
            . '</Grid>'
    }

    _BuildFoldCollapseBtnXaml(t, f, folded, vlMode) {
        iconStyle := ' Style="{StaticResource RmtIconBtn}"'
        if (vlMode) {
            return '<Button Tag="FoldBtn" Width="24" MinHeight="24" Margin="0,0,6,0" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12">'
                . '<Button.Style><Style TargetType="Button" BasedOn="{StaticResource RmtIconBtn}">'
                . '<Setter Property="Content" Value="&#xE70D;"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Folded}" Value="True"><Setter Property="Content" Value="&#xE76C;"/></DataTrigger></Style.Triggers>'
                . '</Style></Button.Style></Button>'
        }
        foldGlyph := folded ? "&#xE76C;" : "&#xE70D;"
        return '<Button Name="FoldBtn_' t '_' f '" Width="24" MinHeight="24" Margin="0,0,6,0"' iconStyle '>'
            . '<TextBlock Name="FoldGlyph_' t '_' f '" Text="' foldGlyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Button>'
    }

    ; 模块头专用样式：输入框左内边距与占位符对齐；工具按钮悬停跟主题色
    _BuildFoldRowStyles() {
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        fieldBox := '<Style x:Key="RmtFoldFieldBox" TargetType="TextBox">'
            . '<Setter Property="FontSize" Value="' foldFs '"/>'
            . '<Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Height" Value="24"/>'
            . '<Setter Property="Padding" Value="1,0,1,0"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="TextAlignment" Value="Left"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Grid UseLayoutRounding="False" ClipToBounds="False">'
            . '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1"' this._BorderSnap() '>'
            . '<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Stretch" HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>'
            . '</Border></Grid></ControlTemplate></Setter.Value></Setter>'
            . '<Style.Triggers>'
            . '<Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="1"/><Setter Property="FontSize" Value="' foldFs '"/></Trigger>'
            . '<Trigger Property="IsReadOnly" Value="True"><Setter Property="FontSize" Value="' foldFs '"/></Trigger>'
            . '</Style.Triggers></Style>'
        chatBox := '<Style x:Key="RmtAiChatBox" TargetType="TextBox">'
            . '<Setter Property="FontSize" Value="' this._AiChatBodyFontSize() '"/>'
            . '<Setter Property="MinHeight" Value="' (this._AiInputLineH() - 2) '"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="TextWrapping" Value="Wrap"/>'
            . '<Setter Property="AcceptsReturn" Value="True"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="TextAlignment" Value="Left"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="VerticalScrollBarVisibility" Value="Hidden"/>'
            . '<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">'
            . '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="' this._AiInputRadius() '"' this._BorderSnap() '>'
            . '<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Stretch" HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>'
            . '</Border></ControlTemplate></Setter.Value></Setter></Style>'
        aiIconBtn := '<Style x:Key="RmtAiIconBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="22"/><Setter Property="Height" Value="22"/><Setter Property="MinHeight" Value="22"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextSub}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="3" Width="22" Height="22">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBgHover}"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        aiMsgBox := '<Style x:Key="RmtAiMsgBox" TargetType="RichTextBox">'
            . '<Setter Property="FontSize" Value="' this._AiChatBodyFontSize() '"/>'
            . '<Setter Property="IsReadOnly" Value="True"/>'
            . '<Setter Property="IsDocumentEnabled" Value="True"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="VerticalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="IsUndoEnabled" Value="False"/>'
            . '<Setter Property="CaretBrush" Value="Transparent"/>'
            . '<Setter Property="Cursor" Value="IBeam"/>'
            . '<Setter Property="Tag" Value="PassScroll"/>'
            . '</Style>'
        toolBtn := '<Style x:Key="RmtFoldToolBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="24"/><Setter Property="Height" Value="24"/><Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0,0,4,0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid UseLayoutRounding="False" ClipToBounds="False">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border></Grid>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd") MacroDebugToolbar.ActiveTrigger() '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        primaryBtn := StrReplace(toolBtn, 'x:Key="RmtFoldToolBtn"', 'x:Key="RmtItemPrimaryBtn"')
        primaryBtn := StrReplace(primaryBtn, 'Width" Value="24"', 'Width" Value="48"')
        editBtn := StrReplace(toolBtn, 'x:Key="RmtFoldToolBtn"', 'x:Key="RmtItemEditBtn"')
        editBtn := StrReplace(editBtn, 'Width" Value="24"', 'Width" Value="64"')
        forbidBtn := '<Style x:Key="RmtFoldForbidBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="24"/><Setter Property="Height" Value="24"/><Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0,0,4,0"/>'
            . '<Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>'
            . '<Setter Property="FontSize" Value="12"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid UseLayoutRounding="False" ClipToBounds="False">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="False"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsMouseOver}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</MultiDataTrigger>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="False"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsPressed}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</MultiDataTrigger>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True">'
            . '<Setter Property="Foreground" Value="{DynamicResource ActionText}"/>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionStroke}"/>'
            . '</DataTrigger>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="True"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsMouseOver}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</MultiDataTrigger>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="True"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsPressed}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionPressBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</MultiDataTrigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        itemForbid := StrReplace(forbidBtn, 'x:Key="RmtFoldForbidBtn"', 'x:Key="RmtItemForbidBtn"')
        itemForbid := StrReplace(itemForbid, 'Binding="{Binding FoldForbid}"', 'Binding="{Binding Forbid}"')
        itemFieldBtn := '<Style x:Key="RmtItemFieldBtn" TargetType="Button">'
            . '<Setter Property="Height" Value="24"/><Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Padding" Value="4,0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="SnapsToDevicePixels" Value="False"/>'
            . '<Setter Property="UseLayoutRounding" Value="False"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid UseLayoutRounding="False" ClipToBounds="False">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1" Padding="{TemplateBinding Padding}"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>'
            . '</Border></Grid>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd") '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        itemCombo := '<Style x:Key="RmtItemCombo" TargetType="ComboBox">'
            . '<Style.Resources><Style TargetType="TextBox">'
            . '<Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="MinHeight" Value="0"/><Setter Property="MinWidth" Value="0"/>'
            . '<Setter Property="VerticalAlignment" Value="Center"/><Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">'
            . '<ScrollViewer x:Name="PART_ContentHost" Background="Transparent" VerticalAlignment="Center" Margin="0"/>'
            . '</ControlTemplate></Setter.Value></Setter></Style></Style.Resources>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="MinHeight" Value="24"/><Setter Property="Height" Value="24"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Padding" Value="4,0,20,0"/>'
            . '<Setter Property="SnapsToDevicePixels" Value="False"/>'
            . '<Setter Property="UseLayoutRounding" Value="False"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">'
            . '<Grid UseLayoutRounding="False" ClipToBounds="False">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1"' this._BorderSnap() '/>'
            . '<ToggleButton Background="Transparent" BorderThickness="0" Focusable="False" ClickMode="Press" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">'
            . '<ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent">'
            . '<Path Fill="{DynamicResource TextMain}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0" Data="M 0 0 L 4 4 L 8 0 Z"/>'
            . '</Border></ControlTemplate></ToggleButton.Template></ToggleButton>'
            . '<ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"/>'
            . '<TextBox x:Name="PART_EditableTextBox" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="{TemplateBinding Padding}" Focusable="True" Background="Transparent" Foreground="{TemplateBinding Foreground}" BorderThickness="0" Visibility="Hidden" IsReadOnly="{TemplateBinding IsReadOnly}"/>'
            . '<Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">'
            . '<Border x:Name="DropDownBorder" Background="{DynamicResource DropdownBg}" BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="3" Margin="0,4,0,0" Width="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="350">'
            . '<ScrollViewer Margin="0" SnapsToDevicePixels="True" Tag="ContainScroll"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>'
            . '</Border></Popup></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsEditable" Value="True"><Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/><Setter TargetName="ContentSite" Property="Visibility" Value="Hidden"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        railHoverW := this._AiRailHoverW()
        tabW := this._AiTabW()
        aiRail := '<Style x:Key="RmtAiRailBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="' railHoverW '"/><Setter Property="MinWidth" Value="' railHoverW '"/>'
            . '<Setter Property="MaxWidth" Value="' railHoverW '"/>'
            . '<Setter Property="Height" Value="200"/>'
            . '<Setter Property="MinHeight" Value="200"/><Setter Property="MaxHeight" Value="200"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Grid>'
            . '<Path x:Name="Bd" Data="M 18,0 L 18,200 L 0,176 L 0,24 Z" Stretch="Fill"'
            . ' Fill="{DynamicResource ControlBg}" Stroke="{DynamicResource OutlineStroke}" StrokeThickness="1.5"'
            . ' StrokeLineJoin="Round" SnapsToDevicePixels="True"/>'
            . '<ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>'
            . '</Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Fill" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Fill" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        sideModeTab := '<Style x:Key="RmtSideModeTab" TargetType="Button">'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="5,4"/>'
            . '<Setter Property="Width" Value="' tabW '"/>'
            . '<Setter Property="MinWidth" Value="' tabW '"/>'
            . '<Setter Property="MaxWidth" Value="' tabW '"/>'
            . '<Setter Property="Height" Value="28"/>'
            . '<Setter Property="MinHeight" Value="28"/>'
            . '<Setter Property="MaxHeight" Value="28"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Grid Height="28" ClipToBounds="True">'
            . '<Border x:Name="Bd" Background="Transparent" BorderThickness="0" Padding="{TemplateBinding Padding}" Cursor="Hand" CornerRadius="0">'
            . '<Grid>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource TextMain}" TextElement.FontSize="14" TextElement.FontWeight="SemiBold"/>'
            . '<Ellipse x:Name="SelDot" Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-3,-1,-3" Visibility="Collapsed" IsHitTestVisible="False"/>'
            . '</Grid></Border></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="Tag" Value="first"><Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/></Trigger>'
            . '<Trigger Property="Tag" Value="last"><Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/></Trigger>'
            . '<Trigger Property="Tag" Value="sel-first"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/><Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/><Setter TargetName="SelDot" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="Tag" Value="sel-last"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/><Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/><Setter TargetName="SelDot" Property="Visibility" Value="Visible"/></Trigger>'
            . '<MultiTrigger><MultiTrigger.Conditions>'
            . '<Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="sel-first"/>'
            . '</MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/>'
            . '<Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/>'
            . '</MultiTrigger>'
            . '<MultiTrigger><MultiTrigger.Conditions>'
            . '<Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="sel-last"/>'
            . '</MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/>'
            . '<Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/>'
            . '</MultiTrigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        sideTreeItem := '<Style x:Key="RmtSideTreeItem" TargetType="ListBoxItem">'
            . '<Setter Property="Height" Value="28"/><Setter Property="MinHeight" Value="28"/>'
            . '<Setter Property="Padding" Value="8,0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Stretch"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" Height="28">'
            . '<TextBlock Text="{Binding}" VerticalAlignment="Center" FontSize="12" TextTrimming="CharacterEllipsis" Foreground="{TemplateBinding Foreground}"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="ItemsControl.AlternationIndex" Value="1"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListRowAltBg}"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        return fieldBox . chatBox . aiIconBtn . aiMsgBox . toolBtn . primaryBtn . editBtn . forbidBtn . itemForbid . itemFieldBtn . itemCombo . aiRail . sideModeTab . sideTreeItem
    }

    ; 模块头输入框：RmtFoldFieldBox 覆盖全局 TextBox Padding=12，保证与占位符左对齐
    _FoldFieldBoxAttrs(extra := "") {
        return ' Style="{StaticResource RmtFoldFieldBox}"' extra
    }

    _BuildDragHandleXaml() {
        dot := '<Ellipse Width="3" Height="3" Fill="{DynamicResource TextSub}" Opacity="0.7" Margin="1"/>'
        return '<Button Tag="DragHandle" Style="{StaticResource RmtIconBtn}" Width="22" MinHeight="24" ToolTip="' GetLang("拖拽调整顺序") '" VerticalAlignment="Center" HorizontalAlignment="Center" Cursor="Arrow">'
            . '<UniformGrid Rows="3" Columns="2" Width="10" Height="14" IsHitTestVisible="False">'
            . dot dot dot dot dot dot
            . '</UniformGrid></Button>'
    }

    _ItemDragColW() {
        return 38
    }

    ; 24 DIP 在 100%、125%、150%、200% DPI 下均为整数物理像素。
    _CtrlH() {
        return 24
    }

    _BorderSnap() {
        return ' SnapsToDevicePixels="True" UseLayoutRounding="True"'
    }

    _IsAiPanelOpen() {
        return this.HasOwnProp("aiAssistOpen") && this.aiAssistOpen
    }

    _FoldGroupGap() {
        return this._IsAiPanelOpen() ? this._AiPanelGapMin() : (8 + this._foldFrontShift)
    }

    ; 宏行列宽：备注右缘对齐模块备注；触发键对齐「语音宏」左分割线；组间距统一用备注→触发键间距
    _ItemLayoutWide() {
        tabW := 80
        toTab := 2
        inner0 := 4 + this._ItemDragColW()
        colorW := 20
        seqW := 22
        remarkW := (8 + 24 + 6 + this._foldFieldW) - inner0 - colorW - seqW
        tkW := 125
        typeW := 82
        editCol := 68
        loopCol := 86
        settingCol := 48
        tkLeft := tabW * 4 - toTab - inner0
        spacerTK := tkLeft - (colorW + seqW + remarkW)
        if (spacerTK < 0)
            spacerTK := 0
        spacerTK += 35
        return Map("color", colorW, "seq", seqW, "remark", remarkW
            , "spacerTK", spacerTK, "tk", tkW, "type", typeW
            , "spacerEdit", spacerTK, "edit", editCol, "loop", loopCol, "setting", settingCol
            , "spacerCopy", spacerTK)
    }

    _ItemLayout() {
        L := this._ItemLayoutWide()
        if (this._IsAiPanelOpen()) {
            g := this._AiPanelGapMin()
            L["spacerTK"] := g
            L["spacerEdit"] := g
            L["spacerCopy"] := g
        }
        return L
    }

    _ItemInnerColDefs() {
        L := this._ItemLayoutWide()
        if (this._IsAiPanelOpen()) {
            minG := this._AiPanelGapMin()
            maxG := L["spacerTK"]
            sp := '<ColumnDefinition Width="100*" MinWidth="' minG '" MaxWidth="' maxG '"/>'
            return '<ColumnDefinition Width="' L["color"] '"/><ColumnDefinition Width="' L["seq"] '"/><ColumnDefinition Width="' L["remark"] '"/>'
                . sp . '<ColumnDefinition Width="' L["tk"] '"/><ColumnDefinition Width="' L["type"] '"/>'
                . sp . '<ColumnDefinition Width="' L["edit"] '"/><ColumnDefinition Width="' L["loop"] '"/><ColumnDefinition Width="' L["setting"] '"/>'
                . sp . '<ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>'
        }
        return '<ColumnDefinition Width="' L["color"] '"/><ColumnDefinition Width="' L["seq"] '"/><ColumnDefinition Width="' L["remark"] '"/>'
            . '<ColumnDefinition Width="' L["spacerTK"] '"/><ColumnDefinition Width="' L["tk"] '"/><ColumnDefinition Width="' L["type"] '"/>'
            . '<ColumnDefinition Width="' L["spacerEdit"] '"/><ColumnDefinition Width="' L["edit"] '"/><ColumnDefinition Width="' L["loop"] '"/><ColumnDefinition Width="' L["setting"] '"/>'
            . '<ColumnDefinition Width="' L["spacerCopy"] '"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>'
    }
