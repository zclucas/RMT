
    ; ============ Epic5 虚拟列表模板（注入 Window.Resources，VLTemplateSelector 按行类型取用） ============
    ; 复刻 _BuildItemRow / _BuildFoldTitleRow 列结构，字面值换 {Binding}，控件加 Tag 供容器级事件路由。
    _BuildVListTemplates() {
        keep := this._IsAiPanelOpen()
        this.aiAssistOpen := false
        normal := this._BuildVListTemplateSet("")
        this.aiAssistOpen := true
        compact := this._BuildVListTemplateSet("C")
        this.aiAssistOpen := keep
        return normal . compact
    }

    _BuildVListTemplateSet(suf) {
        row := '<DataTemplate x:Key="RmtMacroRow' suf '">'
            . this._BuildItemCardOpen()
            . '<Grid.ColumnDefinitions>' this._ItemInnerColDefs() '</Grid.ColumnDefinitions>'
            . this._BuildSeqNoXaml(true)
            . this._BuildItemRemarkFieldXaml(0, 0, "", true)
            . '<DockPanel Grid.Column="4" LastChildFill="True" HorizontalAlignment="Stretch">'
            . '<DockPanel.Style><Style TargetType="DockPanel"><Setter Property="Margin" Value="0"/><Setter Property="Visibility" Value="Visible"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding ImageConfigVis}" Value="Visible"><Setter Property="Margin" Value="45,0,-45,0"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding TKBtnEnabled}" Value="False"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
            . '</Style.Triggers></Style></DockPanel.Style>'
            . '<ContentControl><ContentControl.Style><Style TargetType="ContentControl">'
            . '<Style.Triggers><DataTrigger Binding="{Binding TKType}" Value="-1"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers>'
            . '</Style></ContentControl.Style>'
            . this._TriggerEntries('<Button Tag="TKBtn" IsEnabled="{Binding TKBtnEnabled}" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang("编辑") '">' this._BuildVirtualItemConfigBtnInnerXaml() '</Button>', true, "TKBtn")
            . '</ContentControl>'
            . '<ContentControl><ContentControl.Style><Style TargetType="ContentControl"><Setter Property="Visibility" Value="Collapsed"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding TKType}" Value="-1"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
            . '</Style></ContentControl.Style>' this._GestureEntries(true) '</ContentControl>'
            . '</DockPanel>'
            . '<Button Grid.Column="5" Tag="NetHelp" Visibility="{Binding NetHelpVis}" Style="{StaticResource RmtItemFieldBtn}" Width="24" HorizontalAlignment="Left" Margin="0,0,4,0" Content="&#xE946;" ToolTip="' GetLang("网络触发说明") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . '<ComboBox Grid.Column="5" Tag="TKType" SelectedIndex="{Binding TKType}" IsEnabled="{Binding TKTypeEnabled}" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBox.Style><Style TargetType="ComboBox" BasedOn="{StaticResource RmtItemCombo}"><Setter Property="Margin" Value="0"/><Setter Property="Visibility" Value="Visible"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding NetTypeVis}" Value="Collapsed"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding TKBtnEnabled}" Value="False"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
            . '</Style.Triggers></Style></ComboBox.Style>'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . this._BuildItemEditGroupWrap(true, 0
                , this._BuildItemEditBtnXaml(0, 0, "", true)
                . '<ComboBox Grid.Column="1" Tag="Loop" Text="{Binding LoopText}" IsEditable="True" IsEnabled="{Binding LoopEnabled}" Style="{StaticResource RmtItemCombo}" Margin="0,0,4,0" ToolTip="' GetLang("循环次数") '">'
                . '<ComboBoxItem Content="' GetLang("无限") '"/>'
                . '</ComboBox>'
                . '<Button Grid.Column="2" Tag="Setting" Style="{StaticResource RmtItemPrimaryBtn}" Margin="0" Content="&#xE713;" ToolTip="' GetLang("设置") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"/>')
            . '<StackPanel Grid.Column="11" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Tag="Copy" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE8C8;" ToolTip="' GetLang("复制") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . '<Button Tag="Share" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE898;" ToolTip="' GetLang("分享到论坛") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0,0,4,0"/>'
            . this._BuildItemForbidBtnXaml(0, 0, false, true)
            . '<Button Tag="Del" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE74D;" ToolTip="' GetLang("删除") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0"/>'
            . '</StackPanel>'
            . this._ItemCardClose() '</DataTemplate>'
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        fold := '<DataTemplate x:Key="RmtFoldHeader' suf '">'
            . this._BuildFoldCardBorderOpen()
            . '<StackPanel VerticalAlignment="Center" TextElement.FontSize="' foldFs '">'
            . '<StackPanel.Style><Style TargetType="StackPanel"><Setter Property="Opacity" Value="1"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Opacity" Value="' this._ForbidContentOpacity() '"/></DataTrigger></Style.Triggers></Style></StackPanel.Style>'
            . this._BuildFoldDividerXaml(true)
            . this._BuildFoldHeaderRowXaml(0, 0, "", true)
            . '<Grid Margin="0,4,0,0"><Grid.Style><Style TargetType="Grid"><Setter Property="Visibility" Value="{Binding ShowTKRowVisibility}"/><Style.Triggers><DataTrigger Binding="{Binding Folded}" Value="True"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers></Style></Grid.Style>'
            . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">'
            . this._TriggerEntries('<Button Tag="FoldTKEdit" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang("触发键") '">' this._BuildTKBtnInnerXaml("", true, "FoldTKStr") '</Button>', true, "FoldTKEdit")
            . this._GestureEntries(true, , , true)
            . '<ComboBox Tag="FoldTKType" SelectedIndex="{Binding FoldTKType}" IsEnabled="{Binding FoldTKTypeEnabled}" Style="{StaticResource RmtItemCombo}" Width="82" Margin="0" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>' this._BuildFoldPosBtnXaml(0, 0, true) '</StackPanel></Grid>'
            . '</StackPanel></Border></DataTemplate>'
        addFold := '<DataTemplate x:Key="RmtAddFold">'
            . '<Grid Height="72" HorizontalAlignment="Stretch">'
            . '<Button Tag="AddFold" Width="56" Height="56" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="-10,0,10,0" Cursor="Hand" ToolTip="' GetLang("新增模块") '">'
            . '<Button.Template><ControlTemplate TargetType="Button"><Grid>'
            . '<Ellipse x:Name="Bd" Stroke="{DynamicResource ControlBorder}" StrokeThickness="2" Fill="{DynamicResource ControlBg}"/>'
            . '<Grid Width="24" Height="24" IsHitTestVisible="False">'
            . '<Rectangle Width="24" Height="4" Fill="{DynamicResource TextMain}" RadiusX="1.5" RadiusY="1.5"/>'
            . '<Rectangle Width="4" Height="24" Fill="{DynamicResource TextMain}" RadiusX="1.5" RadiusY="1.5"/>'
            . '</Grid></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Fill" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Fill" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Button.Template></Button></Grid></DataTemplate>'
        return row . fold . (suf == "" ? addFold : "")
    }

    _BuildFoldIconBtn(tag, name, t, f, content, tip, vlMode, isIcon := true, last := false) {
        margin := last ? "" : ' Margin="0,0,4,0"'
        font := isIcon ? ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"' : ' FontSize="14"'
        attrs := ' Style="{StaticResource RmtFoldToolBtn}" Content="' content '" ToolTip="' tip '"' . font
        if (last)
            attrs .= ' Margin="0"'
        if (vlMode)
            return '<Button Tag="' tag '" ' attrs '/>'
        return '<Button Name="' name '_' t '_' f '" Tag="' tag '" ' attrs '/>'
    }

    ; 模块行工具按钮：新增宏 / 粘贴宏 / 分享到论坛 / 禁用 / 删除
    _BuildFoldToolbarXaml(t, f, forbidState, vlMode := false) {
        return this._BuildFoldIconBtn("FoldAddMacro", "FoldAddMacro", t, f, "+", GetLang("新增宏"), vlMode, false)
            . this._BuildFoldIconBtn("FoldPasteMacro", "FoldPasteMacro", t, f, "&#xE77F;", GetLang("粘贴宏"), vlMode)
            . this._BuildFoldIconBtn("FoldShare", "FoldShare", t, f, "&#xE898;", GetLang("分享到论坛"), vlMode)
            . this._BuildFoldForbidBtnXaml(t, f, forbidState, vlMode)
            . this._BuildFoldIconBtn("FoldDel", "FoldDel", t, f, "&#xE74D;", GetLang("删除模块"), vlMode, true, true)
    }

    ; 禁用：RmtFoldForbidBtn 悬停走主题 ActionHover；非 VL 由 SyncFoldForbidBtnUI 同步激活态
    _BuildFoldForbidBtnXaml(t, f, forbidState, vlMode) {
        icon := "&#xE25B;"
        tip := GetLang("禁用")
        dot := '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,2,0" IsHitTestVisible="False"/>'
        if (vlMode) {
            return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
                . '<Button Tag="FoldForbidBtn" Content="' icon '" ToolTip="' tip '" Style="{StaticResource RmtFoldForbidBtn}"/>'
                . '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,6,0" IsHitTestVisible="False">'
                . '<Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Ellipse.Style></Ellipse></Grid>'
        }
        actBg := forbidState ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}"
        actBr := forbidState ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}"
        actFg := forbidState ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}"
        dotVis := forbidState ? "Visible" : "Collapsed"
        return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
            . '<Button Name="FoldForbidBtn_' t '_' f '" Tag="FoldForbidBtn" Content="' icon '" ToolTip="' tip '" Style="{StaticResource RmtFoldToolBtn}"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
            . ' Background="' actBg '" BorderBrush="' actBr '" Foreground="' actFg '"/>'
            . '<Grid Name="FoldForbidDot_' t '_' f '" Visibility="' dotVis '">' dot '</Grid>'
            . '</Grid>'
    }

    SyncItemForbidBtnUI(t, i, forbidState) {
        if (!IsObject(this.ui))
            return
        if (forbidState) {
            this.ui.Update("Forbid_" t "_" i, "Background", "{DynamicResource ActionBg}")
            this.ui.Update("Forbid_" t "_" i, "BorderBrush", "{DynamicResource ActionStroke}")
            this.ui.Update("Forbid_" t "_" i, "Foreground", "{DynamicResource ActionText}")
            this.ui.Update("ForbidDot_" t "_" i, "Visibility", "Visible")
        } else {
            this.ui.Update("Forbid_" t "_" i, "Background", "{DynamicResource ControlBg}")
            this.ui.Update("Forbid_" t "_" i, "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update("Forbid_" t "_" i, "Foreground", "{DynamicResource TextMain}")
            this.ui.Update("ForbidDot_" t "_" i, "Visibility", "Collapsed")
        }
    }

    SyncFoldForbidBtnUI(t, f, forbidState) {
        if (!IsObject(this.ui))
            return
        if (forbidState) {
            this.ui.Update("FoldForbidBtn_" t "_" f, "Background", "{DynamicResource ActionBg}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "BorderBrush", "{DynamicResource ActionStroke}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "Foreground", "{DynamicResource ActionText}")
            this.ui.Update("FoldForbidDot_" t "_" f, "Visibility", "Visible")
        } else {
            this.ui.Update("FoldForbidBtn_" t "_" f, "Background", "{DynamicResource ControlBg}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "Foreground", "{DynamicResource TextMain}")
            this.ui.Update("FoldForbidDot_" t "_" f, "Visibility", "Collapsed")
        }
        this.ui.Update("FoldCard_" t "_" f, "Background", forbidState ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource FoldHeaderBg}")
        try this.ui.Update("FoldCardInner_" t "_" f, "Opacity", forbidState ? this._ForbidContentOpacity() : "1")
        tableItem := MySoftData.TableInfo[t]
        fold := tableItem.Folds[f]
        if (!fold)
            return
        for i, item in tableItem.Items {
            if (item.FoldID == fold.ID)
                this.RefreshItemRow(t, i)
        }
    }

    ; 行/折叠头共用 CheckBox（自定义勾选模板，Tag 兼作绑定路径）
    _VlCheckBox(tag, col) {
        colAttr := col == "" ? "" : ' Grid.Column="' col '"'
        return '<CheckBox' colAttr ' Tag="' tag '" Content="' GetLang("禁用") '" IsChecked="{Binding ' tag '}" HorizontalAlignment="Left" Margin="2,0,0,0" VerticalAlignment="Center">'
            . '<CheckBox.Template><ControlTemplate TargetType="CheckBox">'
            . '<BulletDecorator Background="Transparent" Cursor="Hand">'
            . '<BulletDecorator.Bullet><Border x:Name="Border" Width="18" Height="18" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3"><Path x:Name="CheckMark" Visibility="Collapsed" Data="M 4 9 L 7 12 L 13 5" Stroke="{DynamicResource Accent}" StrokeThickness="2" StrokeEndLineCap="Round" StrokeStartLineCap="Round" StrokeLineJoin="Round"/></Border></BulletDecorator.Bullet>'
            . '<ContentPresenter Margin="4,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" RecognizesAccessKey="True"/>'
            . '</BulletDecorator>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></CheckBox.Template></CheckBox>'
    }
