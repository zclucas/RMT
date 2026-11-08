
    _BuildItemCardOpen(ns := "", t := 0, i := 0, forbid := false, rowSel := false) {
        nsAttr := ns != "" ? " " ns : ""
        nameAttr := t > 0 ? ' Name="ItemCard_' t '_' i '"' : ""
        defBg := rowSel ? "{DynamicResource TabSelBg}" : ((t > 0 && forbid) ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource ControlBg}")
        ; 宏行最小高度 30；内容随主题字号加高，外层必须同步扩展以免裁掉控件底边。
        return '<Border' nsAttr nameAttr ' BorderBrush="{DynamicResource OutlineStroke}" ClipToBounds="False"' this._BorderSnap() '>'
            . '<Border.Style><Style TargetType="Border">'
            . '<Setter Property="CornerRadius" Value="0"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Padding" Value="4,3,6,3"/>'
            . '<Setter Property="Background" Value="' defBg '"/>'
            . '<Setter Property="MinHeight" Value="30"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding IsAltRow}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowAltBg}"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding Forbid}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowForbidBg}"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowForbidBg}"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding RowSel}" Value="True"><Setter Property="Background" Value="{DynamicResource TabSelBg}"/></DataTrigger>'
            . '</Style.Triggers></Style></Border.Style>'
            . '<Grid MinHeight="24" VerticalAlignment="Center"' this._ItemForbidOpacityAttrs(t == 0, t, i, forbid) '>'
            . this._ItemForbidOpacityStyle(t == 0)
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="' this._ItemDragColW() '"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Grid Grid.Column="0" VerticalAlignment="Stretch" HorizontalAlignment="Stretch" ClipToBounds="False">'
            . this._BuildRowSelDotXaml(t == 0, t, i, rowSel)
            . this._BuildRowSelIconXaml(t == 0, t, i, rowSel)
            . '<Grid VerticalAlignment="Center" HorizontalAlignment="Left" Margin="12,0,2,0">' this._BuildDragHandleXaml() '</Grid>'
            . '</Grid>'
            . '<Grid Grid.Column="1" MinHeight="24">'
    }

    _ItemCardClose() {
        return '</Grid></Grid></Border>'
    }

    ; 禁用时内容整体变淡（边框/文字一起暗淡），不靠深色底
    _ItemForbidOpacityAttrs(vlMode, t := 0, i := 0, forbid := false) {
        if (vlMode)
            return ""
        return ' Name="ItemCardInner_' t '_' i '" Opacity="' (forbid ? this._ForbidContentOpacity() : "1") '"'
    }

    _ForbidContentOpacity() {
        return "0.42"
    }

    _ItemForbidOpacityStyle(vlMode) {
        if (!vlMode)
            return ""
        op := this._ForbidContentOpacity()
        return '<Grid.Style><Style TargetType="Grid"><Setter Property="Opacity" Value="1"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding Forbid}" Value="True"><Setter Property="Opacity" Value="' op '"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Opacity" Value="' op '"/></DataTrigger>'
            . '</Style.Triggers></Style></Grid.Style>'
    }

    _BuildRowSelDotXaml(vlMode, t := 0, i := 0, rowSel := false) {
        if (vlMode) {
            return '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-3,-3,0,0" IsHitTestVisible="False">'
                . '<Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding RowSel}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Ellipse.Style></Ellipse>'
        }
        vis := rowSel ? "Visible" : "Collapsed"
        return '<Grid Name="RowSelDot_' t '_' i '" Visibility="' vis '" HorizontalAlignment="Left" VerticalAlignment="Top" IsHitTestVisible="False">'
            . '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" Margin="-3,-3,0,0"/>'
            . '</Grid>'
    }

    _BuildRowSelIconXaml(vlMode, t := 0, i := 0, rowSel := false) {
        body := CmdKeyRightIconXaml("{DynamicResource Accent}", 15, 12, "2.1")
        if (vlMode) {
            return '<Grid HorizontalAlignment="Left" VerticalAlignment="Center">'
                . '<Grid.Style><Style TargetType="Grid"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding RowSel}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Grid.Style>' body '</Grid>'
        }
        vis := rowSel ? "Visible" : "Collapsed"
        return '<Grid Name="RowSelMark_' t '_' i '" Visibility="' vis '" HorizontalAlignment="Left" VerticalAlignment="Center">' body '</Grid>'
    }

    _BuildSeqNoXaml(vlMode, t := 0, i := 0, rowSel := false) {
        seqText := vlMode ? "{Binding SeqNo}" : (i ".")
        nameBtn := vlMode ? ' Tag="Seq"' : ' Name="SeqBtn_' t '_' i '" Tag="Seq"'
        btn := '<Button' nameBtn ' Cursor="Hand" Focusable="False" HorizontalAlignment="Left" VerticalAlignment="Center" Background="Transparent" BorderThickness="0" Padding="0">'
            . '<Button.Template><ControlTemplate TargetType="Button"><Border Background="Transparent" Padding="2,0,4,0"><ContentPresenter VerticalAlignment="Center"/></Border></ControlTemplate></Button.Template>'
            . '<TextBlock Text="' seqText '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '</Button>'
        return '<Grid Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="-15,0,0,0">'
            . btn
            . '</Grid>'
    }

    _BuildFoldDividerXaml(vlMode, isFirst := false) {
        ; 左右缩进的浅色细线，避开输入框上下边，避免三条线叠在一起。
        rect := '<Rectangle Height="1" Margin="10,2,10,8" Fill="{DynamicResource FoldDivider}" SnapsToDevicePixels="True"'
        if (vlMode) {
            return rect . '>'
                . '<Rectangle.Style><Style TargetType="Rectangle">'
                . '<Setter Property="Visibility" Value="Visible"/>'
                . '<Style.Triggers>'
                . '<DataTrigger Binding="{Binding IsFirstFold}" Value="True"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
                . '</Style.Triggers></Style></Rectangle.Style></Rectangle>'
        }
        if (isFirst)
            return ""
        return rect . '/>'
    }

    _BuildFoldCardBorderOpen() {
        return '<Border BorderBrush="{DynamicResource OutlineStroke}" ClipToBounds="False"' this._BorderSnap() '>'
            . '<Border.Style><Style TargetType="Border">'
            . '<Setter Property="Background" Value="{DynamicResource FoldHeaderBg}"/>'
            . '<Setter Property="CornerRadius" Value="0"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Padding" Value="8,6,8,6"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowForbidBg}"/></DataTrigger>'
            . '</Style.Triggers></Style></Border.Style>'
    }

    _TriggerEntries(field, virtual, id, text := "") {
        field := RegExReplace(field, '<TextBlock Text="&#xE92E;"[^>]*/>', "")
        visibility := virtual ? "{Binding TKGlyphVis}" : (text == "" ? "Visible" : "Collapsed")
        result := '<Grid Width="124">' field '<StackPanel ' (virtual ? '' : 'Name="' id '_Entries" ') 'Orientation="Horizontal" Visibility="' visibility '">'
        for entry in [["Keyboard", "&#xE92E;", "按键触发键"], ["Joy", "&#xE7FC;", "手柄触发键"]] {
            attr := virtual ? 'Tag="' id entry[1] '"' : 'Name="' id '_' entry[1] '"'
            result .= '<Button ' attr ' Style="{StaticResource RmtItemFieldBtn}" Width="58" Margin="0,0,4,0" ToolTip="' GetLang(entry[3]) '">'
                . '<TextBlock Text="' entry[2] '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/></Button>'
        }
        return result '</StackPanel></Grid>'
    }

    _BuildTKBtnInnerXaml(tkStr, vlMode, bindingName := "TKStr") {
        kb := '&#xE92E;'
        if (vlMode) {
            ; 可见性由数据侧直接给 TKTextVis / TKGlyphVis（VListRow / VListFold 均有），
            ; 内联 DataTrigger 在注入模板中不生效，不能靠它切换
            binding := "{Binding " bindingName "}"
            return '<Grid>'
                . '<Viewbox Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Stretch" VerticalAlignment="Center" Visibility="{Binding TKTextVis}">'
                . '<TextBlock Text="' binding '" TextWrapping="NoWrap" TextAlignment="Center" FontSize="14"/>'
                . '</Viewbox>'
                . '<TextBlock Text="' kb '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="{Binding TKGlyphVis}"/>'
                . '</Grid>'
        }
        if (tkStr == "")
            return '<TextBlock Text="' kb '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
        return '<Viewbox Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Stretch" VerticalAlignment="Center">'
            . '<TextBlock Text="' this._XmlEsc(tkStr) '" TextWrapping="NoWrap" TextAlignment="Center" FontSize="14"/>'
            . '</Viewbox>'
    }

    ; 定时宏「宏配置」：未编辑=时钟 E121；已保存=秒表 E916
    _BuildTimingConfigBtnInnerXaml(vlMode, t := 0, i := 0, configured := false) {
        clock := '&#xE121;'
        timer := '&#xE916;'
        font := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"'
        if (vlMode) {
            return '<Grid ClipToBounds="False" IsHitTestVisible="False">'
                . '<TextBlock Text="' clock '" Visibility="{Binding ClockVis}"' font '/>'
                . '<TextBlock Text="' timer '" Visibility="{Binding TimerVis}"' font '/>'
                . '</Grid>'
        }
        emptyVis := configured ? "Collapsed" : "Visible"
        setVis := configured ? "Visible" : "Collapsed"
        return '<Grid ClipToBounds="False" IsHitTestVisible="False">'
            . '<TextBlock Name="TimingCfgEmpty_' t '_' i '" Text="' clock '" Visibility="' emptyVis '"' font '/>'
            . '<TextBlock Name="TimingCfgSet_' t '_' i '" Text="' timer '" Visibility="' setVis '"' font '/>'
            . '</Grid>'
    }

    ; 菜单宏/界面宏的“触发键”位置实际用于图片配置：未配置显示通用图片图标，
    ; 已配置则直接显示对应图片的缩略图。
    _BuildImageConfigBtnInnerXaml(vlMode, t := 0, i := 0, imagePath := "") {
        photo := '&#xE91B;'
        font := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource TextMain}"'
        if (vlMode) {
            return '<Grid Width="24" Height="20" IsHitTestVisible="False">'
                . '<TextBlock Text="' photo '" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="{Binding PhotoVis}"' font '/>'
                . '<Image Source="{Binding ConfigImagePath}" Width="20" Height="20" Stretch="UniformToFill" Visibility="{Binding TKThumbVis}"/>'
                . '</Grid>'
        }
        configured := imagePath != ""
        iconVis := configured ? "Collapsed" : "Visible"
        imageVis := configured ? "Visible" : "Collapsed"
        src := this._XmlEsc(StrReplace(imagePath, "\", "/"))
        return '<Grid Width="24" Height="20" IsHitTestVisible="False">'
            . '<TextBlock Name="ImageCfgGlyph_' t '_' i '" Text="' photo '" Visibility="' iconVis '" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"' font '/>'
            . '<Image Name="ImageCfgThumb_' t '_' i '" Source="' src '" Visibility="' imageVis '" Width="20" Height="20" Stretch="UniformToFill"/>'
            . '</Grid>'
    }

    _BuildVirtualItemConfigBtnInnerXaml() {
        return '<Grid>'
            . '<Grid Visibility="{Binding KeyInputVis}">' this._BuildTKBtnInnerXaml("", true) '</Grid>'
            . '<Grid Visibility="{Binding ImageConfigVis}">' this._BuildImageConfigBtnInnerXaml(true) '</Grid>'
            . '<Grid Visibility="{Binding TimingConfigVis}">' this._BuildTimingConfigBtnInnerXaml(true) '</Grid>'
            . '</Grid>'
    }

    _GetItemConfigImagePath(t, item) {
        path := item.IcoPath
        if (path == "" || path == "0")
            return ""
        if (FileExist(path))
            return path
        dirName := GetTableSymbol(t) == "UI" ? "UIIcon" : "MenuIcon"
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\" dirName "\" path
        return FileExist(fullPath) ? fullPath : ""
    }

    _BuildFoldRemarkFieldXaml(t, f, remark, vlMode) {
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        ph := this._XmlEsc(GetLang("请输入备注信息"))
        fw := this._foldFieldW
        box := this._FoldFieldBoxAttrs()
        if (vlMode) {
            ; 占位符绑 TextBox.Text（模板内局部名），按键即隐；不绑 FoldRemark（LostFocus 才回写）
            return '<Grid Width="' fw '" MinHeight="24">'
                . '<TextBox Name="FoldRemarkBox" Tag="FoldRemark" Text="{Binding FoldRemark}"' box '/>'
                . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
                . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=FoldRemarkBox}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></TextBlock.Style></TextBlock></Grid>'
        }
        return '<Grid Width="' fw '" MinHeight="24">'
            . '<TextBox Name="FoldRemark_' t '_' f '" Text="' this._XmlEsc(remark) '"' box '/>'
            . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
            . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=FoldRemark_' t '_' f '}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
            . '</Style></TextBlock.Style></TextBlock></Grid>'
    }

    _BuildItemRemarkFieldXaml(t, i, remark, vlMode) {
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        ph := this._XmlEsc(GetLang("请输入备注信息"))
        box := this._FoldFieldBoxAttrs(' ToolTip="' GetLang("备注") '"')
        if (vlMode) {
            ; 占位符绑 TextBox.Text（模板内局部名），按键即隐；不绑 Remark（LostFocus 才回写）
            return '<Grid Grid.Column="2" MinHeight="24" Margin="-5,0,0,0">'
                . '<TextBox Name="RemarkBox" Tag="Remark" Text="{Binding Remark}"' box '/>'
                . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
                . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=RemarkBox}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></TextBlock.Style></TextBlock></Grid>'
        }
        return '<Grid Grid.Column="2" MinHeight="24" Margin="-5,0,0,0">'
            . '<TextBox Name="Remark_' t '_' i '" Text="' this._XmlEsc(remark) '"' box '/>'
            . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
            . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=Remark_' t '_' i '}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
            . '</Style></TextBlock.Style></TextBlock></Grid>'
    }

    ; 宏页签不展示模块前台；虚拟列表用绑定，实体行按表类型折叠
    _FoldFrontVisAttr(t, vlMode) {
        if (vlMode)
            return ' Visibility="{Binding ShowFrontVisibility}"'
        if (t > 0 && CheckIsSubMacroTable(t))
            return ' Visibility="Collapsed"'
        return ""
    }

    _BuildFoldFrontCenterXaml(t, f, frontInfo, vlMode) {
        fw := this._foldFrontW
        box := this._FoldFieldBoxAttrs(' IsReadOnly="True" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled"')
        iconFont := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
        frontIcon := '<TextBlock Text="&#xE7F4;" Width="20" MinWidth="20" TextAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"' iconFont ' Margin="0,0,6,0" ToolTip="' GetLang("窗口绑定") '"/>'
        if (vlMode) {
            return frontIcon
                . '<TextBox Tag="FoldFront" Text="{Binding FoldFront}" Width="' fw '"' box '/>'
                . '<Button Tag="FoldFrontBtn" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE70F;" ToolTip="' GetLang("编辑") '"' iconFont ' Margin="4,0,0,0"/>'
                . '<Button Tag="FoldFrontHelp" Style="{StaticResource RmtFoldToolBtn}" Content="?" ToolTip="' GetLang("窗口绑定说明") '" FontSize="11" Margin="4,0,0,0"/>'
        }
        return frontIcon
            . '<TextBox Name="FoldFront_' t '_' f '" Text="' this._XmlEsc(frontInfo) '" Width="' fw '"' box '/>'
            . '<Button Name="FoldFrontBtn_' t '_' f '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE70F;" ToolTip="' GetLang("编辑") '"' iconFont ' Margin="4,0,0,0"/>'
            . '<Button Name="FoldFrontHelp_' t '_' f '" Style="{StaticResource RmtFoldToolBtn}" Content="?" ToolTip="' GetLang("窗口绑定说明") '" FontSize="11" Margin="4,0,0,0"/>'
    }

    _BuildItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        item := tableItem.Items[i]
        isMacro := CheckIsMacroTable(t)
        isNormal := CheckIsNormalTable(t)
        isTriggerStr := CheckIsStringMacroTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isSubMacro := CheckIsSubMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isVoice := GetTableSymbol(t) == "Voice"
        isNetwork := GetTableSymbol(t) == "Network"
        canEditTKType := isNormal || isTriggerStr

        if (isVoice) {
            ; 语音宏：触发键列显示唤醒词
            tkStr := item.VoiceKeywords
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        } else if (isNetwork) {
            ; §23 网络宏：触发键列显示「复制链接」，点击/右键=直接复制单次 URL
            tkStr := item.ID == "" ? GetLang("编辑") : GetLang("复制链接")
        } else if (isTiming) {
            tkStr := ""
        } else {
            tkStr := FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        }
        loopStr := item.LoopCount == "-1" ? GetLang("无限") : item.LoopCount
        colorState := item.ColorState
        colorHex := colorState == 1 ? "#2E7D32" : colorState == 2 ? "#F9A825" : colorState == 3 ? "#C62828" : "Transparent"
        tkTypeIdx := item.TriggerType - 1
        if (isUI)
            tkTypeIdx := 3

        if ((isNormal || GetTableSymbol(t) == "Replace") && tkStr == GetLang("编辑"))
            tkStr := ""
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        rowSel := this._sideTreeSel.Has(t) && this._sideTreeSel[t] == item.ID
        triggerField := '<Button Name="TKBtn_' t '_' i '" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang((isMenu || isUI) ? "编辑" : (isTiming ? "定时" : "触发键")) '" IsEnabled="' (isSubMacro ? "False" : "True") '">' ((isMenu || isUI) ? this._BuildImageConfigBtnInnerXaml(false, t, i, this._GetItemConfigImagePath(t, item)) : (isTiming ? this._BuildTimingConfigBtnInnerXaml(false, t, i, HasTimingConfig(item)) : this._BuildTKBtnInnerXaml(tkStr, false))) '</Button>'
        xaml := this._BuildItemCardOpen(ns, t, i, item.Forbid || GetItemFoldForbidState(tableItem, i), rowSel)
            . '<Grid.ColumnDefinitions>' this._ItemInnerColDefs() '</Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Name="Color_' t '_' i '" Width="12" Height="12" CornerRadius="6" Background="' colorHex '" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . this._BuildSeqNoXaml(false, t, i, rowSel)
            . this._BuildItemRemarkFieldXaml(t, i, item.Remark, false)
            . '<DockPanel Grid.Column="4" LastChildFill="True" HorizontalAlignment="Stretch" Visibility="' (isSubMacro ? "Collapsed" : "Visible") '" Margin="' ((isMenu || isUI) ? "45,0,-45,0" : "0") '">'
            . ((isNormal || GetTableSymbol(t) == "Replace") ? this._TriggerEntries(triggerField, false, "TKBtn_" t "_" i, tkStr) : triggerField)
            . '</DockPanel>'
            . (isNetwork ? '<Button Grid.Column="5" Name="NetHelp_' t '_' i '" Style="{StaticResource RmtItemFieldBtn}" Width="24" HorizontalAlignment="Left" Margin="0,0,4,0" Content="&#xE946;" ToolTip="' GetLang("网络触发说明") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>' : '')
            . '<ComboBox Grid.Column="5" Name="TKType_' t '_' i '" Style="{StaticResource RmtItemCombo}" Margin="0" SelectedIndex="' tkTypeIdx '" IsEnabled="' (canEditTKType ? "True" : "False") '" Visibility="' ((isSubMacro || isNetwork || isMenu || isUI || isVoice || isTiming) ? "Collapsed" : "Visible") '" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . this._BuildItemEditGroupWrap(false, t
                , this._BuildItemEditBtnXaml(t, i, item, false)
                . '<ComboBox Grid.Column="1" Name="Loop_' t '_' i '" Style="{StaticResource RmtItemCombo}" Margin="0,0,4,0" IsEditable="True" IsEnabled="' (isMacro ? "True" : "False") '" ToolTip="' GetLang("循环次数") '">'
                . '<ComboBoxItem Content="' GetLang("无限") '"/>'
                . '</ComboBox>'
                . '<Button Grid.Column="2" Name="Setting_' t '_' i '" Style="{StaticResource RmtItemPrimaryBtn}" Margin="0" Content="&#xE713;" ToolTip="' GetLang("设置") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"/>')
            . '<StackPanel Grid.Column="11" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Name="Copy_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE8C8;" ToolTip="' GetLang("复制") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . '<Button Name="Share_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE898;" ToolTip="' GetLang("分享到论坛") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0,0,4,0"/>'
            . this._BuildItemForbidBtnXaml(t, i, item.Forbid, false)
            . '<Button Name="Del_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE74D;" ToolTip="' GetLang("删除") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0"/>'
            . '</StackPanel>'
            . this._ItemCardClose()
        return xaml
    }

    _BuildItemEditBtnInnerXaml(vlMode, t := 0, i := 0, kind := 0) {
        iconAttr := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"'
        x := '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
            . '<TextBlock Text="&#xE945;"' iconAttr '/>'
            . '<TextBlock Text="&#xE72C;" Margin="1,0,0,0"' iconAttr '/>'
        if (vlMode) {
            x .= '<TextBlock' iconAttr '>'
                . '<TextBlock.Style><Style TargetType="TextBlock">'
                . '<Setter Property="Visibility" Value="Collapsed"/>'
                . '<Setter Property="Margin" Value="2,0,0,0"/>'
                . '<Style.Triggers>'
                . '<DataTrigger Binding="{Binding EditKind}" Value="1">'
                . '<Setter Property="Visibility" Value="Visible"/>'
                . '<Setter Property="Text" Value="&#xE71D;"/>'
                . '<Setter Property="Margin" Value="2,0,0,0"/>'
                . '</DataTrigger>'
                . '<DataTrigger Binding="{Binding EditKind}" Value="2">'
                . '<Setter Property="Visibility" Value="Visible"/>'
                . '<Setter Property="Text" Value="&#xE8F1;"/>'
                . '<Setter Property="Margin" Value="3,0,0,0"/>'
                . '</DataTrigger>'
                . '</Style.Triggers></Style></TextBlock.Style></TextBlock>'
        } else {
            vis := kind = 0 ? "Collapsed" : "Visible"
            glyph := kind = 2 ? "&#xE8F1;" : "&#xE71D;"
            gap := kind = 2 ? "3,0,0,0" : "2,0,0,0"
            x .= '<TextBlock Name="EditGlyph3_' t '_' i '" Text="' glyph '" Visibility="' vis '" Margin="' gap '"' iconAttr '/>'
        }
        return x . '</StackPanel>'
    }

    _BuildItemEditBtnXaml(t, i, item, vlMode) {
        tip := GetLang("编辑")
        col := ' Grid.Column="0"'
        if (vlMode)
            return '<Button' col ' Tag="Edit" Style="{StaticResource RmtItemEditBtn}" ToolTip="' tip '">' this._BuildItemEditBtnInnerXaml(true) '</Button>'
        kind := GetMacroEditKind(item.Macro)
        return '<Button' col ' Name="Edit_' t '_' i '" Style="{StaticResource RmtItemEditBtn}" ToolTip="' tip '">' this._BuildItemEditBtnInnerXaml(false, t, i, kind) '</Button>'
    }

    ; 宏编辑器 / 循环次数 / 设置：原列宽不变。宏页签挂到模块「前台」同列，右侧压缩时一起动。
    _BuildItemEditGroupWrap(vlMode, t, inner) {
        body := this._BuildItemEditGroupBody(inner)
        if (!vlMode) {
            if (t > 0 && CheckIsSubMacroTable(t))
                return this._BuildItemEditOverlayHost(body, "")
            return this._BuildItemEditNormalHost(body, "")
        }
        return this._BuildItemEditNormalHost(body, this._EditGroupHostVis(true))
            . this._BuildItemEditOverlayHost(body, this._EditGroupHostVis(false))
    }

    _BuildItemEditGroupBody(inner) {
        L := this._ItemLayoutWide()
        return '<Grid HorizontalAlignment="Left" VerticalAlignment="Stretch">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="' L["edit"] '"/>'
            . '<ColumnDefinition Width="' L["loop"] '"/>'
            . '<ColumnDefinition Width="' L["setting"] '"/>'
            . '</Grid.ColumnDefinitions>'
            . inner
            . '</Grid>'
    }

    _BuildItemEditNormalHost(body, visStyle) {
        return '<Grid Grid.Column="7" Grid.ColumnSpan="3" HorizontalAlignment="Left" VerticalAlignment="Stretch">'
            . visStyle
            . body
            . '</Grid>'
    }

    _BuildItemEditOverlayHost(body, visStyle) {
        return '<Grid Grid.Column="0" Grid.ColumnSpan="13" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="' this._SubMacroOverlayMargin() '" ClipToBounds="False">'
            . visStyle
            . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
            . '<Grid Grid.Column="2" HorizontalAlignment="Left" VerticalAlignment="Stretch" Margin="' this._SubMacroFrontOffset() ',0,0,0">'
            . body
            . '</Grid></Grid>'
    }

    ; 宏页签：Visible 当无触发键（TKBtnEnabled=False）；其它页签相反
    _EditGroupHostVis(showWhenHasTK) {
        defVis := showWhenHasTK ? "Visible" : "Collapsed"
        altVis := showWhenHasTK ? "Collapsed" : "Visible"
        return '<Grid.Style><Style TargetType="Grid"><Setter Property="Visibility" Value="' defVis '"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding TKBtnEnabled}" Value="False">'
            . '<Setter Property="Visibility" Value="' altVis '"/>'
            . '</DataTrigger></Style.Triggers></Style></Grid.Style>'
    }

    ; 宏行内容区相对模块头内边距的差：把覆盖层原点对齐到模块头
    _SubMacroOverlayMargin() {
        itemPad := 4, foldPad := 8
        return (foldPad - itemPad - this._ItemDragColW()) ",0,0,0"
    }

    ; 宽布局下「宏编辑器」相对模块前台左缘的间距；压缩时沿用此值，相对位置不变
    _SubMacroFrontOffset() {
        L := this._ItemLayoutWide()
        itemLeft := 4 + this._ItemDragColW()
        editLeft := itemLeft + L["color"] + L["seq"] + L["remark"] + L["spacerTK"] + L["tk"] + L["type"] + L["spacerEdit"]
        remarkGroupW := 24 + 6 + this._foldFieldW
        frontLeft := 8 + remarkGroupW + 8 + this._foldFrontShift
        return editLeft - this._subMacroEditShift - frontLeft
    }

    _BuildItemForbidBtnXaml(t, i, forbidState, vlMode) {
        if (vlMode) {
            return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
                . '<Button Tag="Forbid" Content="&#xE25B;" ToolTip="' GetLang("禁用") '" Style="{StaticResource RmtItemForbidBtn}"/>'
                . '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,6,0" IsHitTestVisible="False">'
                . '<Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Forbid}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Ellipse.Style></Ellipse></Grid>'
        }
        actBg := forbidState ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}"
        actBr := forbidState ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}"
        actFg := forbidState ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}"
        dotVis := forbidState ? "Visible" : "Collapsed"
        return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
            . '<Button Name="Forbid_' t '_' i '" Tag="Forbid" Content="&#xE25B;" ToolTip="' GetLang("禁用") '" Style="{StaticResource RmtFoldToolBtn}"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
            . ' Background="' actBg '" BorderBrush="' actBr '" Foreground="' actFg '"/>'
            . '<Grid Name="ForbidDot_' t '_' i '" Visibility="' dotVis '"><Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,2,0" IsHitTestVisible="False"/></Grid>'
            . '</Grid>'
    }

    _BindItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        isMacro := CheckIsMacroTable(t)
        isTriggerStr := CheckIsStringMacroTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isNetwork := GetTableSymbol(t) == "Network"

        editTK := isTriggerStr ? OnItemEditTriggerStr : OnItemEditTriggerKey
        editTK := isTiming ? OnItemEditTiming : editTK
        editTK := isMenu ? OnItemMenuMacroSettingClick : editTK
        editMacro := isMacro ? OnItemEditMacro : OnItemEditReplaceKey
        if (isUI)
            editTK := OnUIMacroSettingClick
        else if (isNetwork)
            editTK := (*) => OnItemNetworkCopyUrl(tableItem, i)   ; §23 网络宏：触发键列点击 → 直接复制单次 URL
        else if (GetTableSymbol(t) == "Voice")
            ; 与虚拟列表路径一致：离开 XAML 点击回调后再创建语音编辑窗口。
            editTK := ObjBindMethod(this, "_DeferVoiceTrigger")

        loopStr := tableItem.Items[i].LoopCount == "-1" ? GetLang("无限") : tableItem.Items[i].LoopCount
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)

        this._Bind("SeqBtn_" t "_" i, "Click", ObjBindMethod(this, "SelectSideTreeItem", t, i))
        this._Bind("TKBtn_" t "_" i, "Click", editTK.Bind(tableItem, i))
        if (CheckIsNormalTable(t) || GetTableSymbol(t) == "Replace") {
            this._Bind("TKBtn_" t "_" i "_Keyboard", "Click", OnTriggerEntry.Bind(tableItem, i, false, "keyboard"))
            this._Bind("TKBtn_" t "_" i "_Joy", "Click", OnTriggerEntry.Bind(tableItem, i, false, "joy"))
        }
        ; §23 网络宏：右键同为直接复制单次 URL；其余表保持自定义触发串
        this._Bind("TKBtn_" t "_" i, "MouseRightButtonUp", isNetwork ? ((*) => OnItemNetworkCopyUrl(tableItem, i)) : OnItemCustomEditTriggerStr.Bind(tableItem, i))
        ; §23 网络宏：触发键左侧「?」按钮 → 网络触发说明弹窗（仅网络表行存在该按钮）
        if (isNetwork)
            this._Bind("NetHelp_" t "_" i, "Click", OnItemNetworkHelp.Bind(tableItem, i))
        this._Bind("Setting_" t "_" i, "Click", OnItemEditMacroSetting.Bind(tableItem, i))
        this._Bind("Edit_" t "_" i, "Click", editMacro.Bind(tableItem, i))
        this._Bind("Forbid_" t "_" i, "Click", OnItemForbidToggle.Bind(tableItem, i))
        this._Bind("Copy_" t "_" i, "Click", OnItemCopyMacroBtnClick.Bind(tableItem, i))
        this._Bind("Del_" t "_" i, "Click", OnItemDelMacroBtnClick.Bind(tableItem, i))
    }

    ; 旧的实体行路径也复用虚拟列表宿主的安全调度，避免在 XAML 点击回调中重入开窗。
    _DeferVoiceTrigger(tableItem, index, *) {
        if (IsObject(this._vl)) {
            this._vl._DeferDialog("VoiceTrigger", OnItemVoiceTriggerSetting.Bind(tableItem, index))
            return
        }
        ; 仅作为初始化早期兜底；正常主窗口生命周期总会先建立 _vl。
        this._voiceDlgFn := OnItemVoiceTriggerSetting.Bind(tableItem, index)
        SetTimer(this._voiceDlgFn, -50)
    }

    ; 从引擎事件回调里弹 XAML 窗会起不来（回调还压在 WM_COPYDATA 里），统一延到独立伪线程。
    ; 只包需要弹窗的回调；纯改属性/展开折叠这类直接调即可。
    _DeferClick(fn) {
        return (*) => SetTimer(fn, -50)
    }

    _BindFoldRows(t) {
        tableItem := MySoftData.TableInfo[t]
        for f, fold in tableItem.Folds {
            ; 会弹 XAML 窗的按钮必须延迟：这些回调正运行在引擎发来的消息里，
            ; 在里面建窗会起不来（表现就是点了没反应）。
            this._Bind("FoldFrontBtn_" t "_" f, "Click", this._DeferClick(OnFoldFrontInfoEdit.Bind(tableItem, f)))
            this._Bind("FoldFrontHelp_" t "_" f, "Click", this._DeferClick(OnFoldFrontHelp.Bind(tableItem, f)))
            this._Bind("FoldBtn_" t "_" f, "Click", OnFoldBtnClick.Bind(tableItem, f))
            if (GetTableSymbol(t) == "UI")
                this._Bind("FoldPosBtn_" t "_" f, "Click", this._DeferClick(OnFoldPosSetting.Bind(tableItem, f)))
            this._Bind("FoldTKEdit_" t "_" f, "Click", this._DeferClick(OnFlodTKEditClick.Bind(tableItem, f)))
            this._Bind("FoldTKEdit_" t "_" f "_Keyboard", "Click", this._DeferClick(OnTriggerEntry.Bind(tableItem, f, true, "keyboard")))
            this._Bind("FoldTKEdit_" t "_" f "_Joy", "Click", this._DeferClick(OnTriggerEntry.Bind(tableItem, f, true, "joy")))
            this._Bind("FoldAddMacro_" t "_" f, "Click", OnItemAddMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldPasteMacro_" t "_" f, "Click", OnItemPasteMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldShare_" t "_" f, "Click", OnFoldShareBtnClick.Bind(tableItem, f))
            this._Bind("FoldForbidBtn_" t "_" f, "Click", OnFoldForbidToggleClick.Bind(tableItem, f))
            this._Bind("FoldDel_" t "_" f, "Click", OnItemDelFoldBtnClick.Bind(tableItem, f))
        }
    }

    ; 本地登记回调 + 让引擎挂上真实 WPF 事件（动态注入控件必须在 AddXamlItem 之后调用）
    ; 重建前先清同名旧回调，避免重复触发（同 ConfigMergeGui.PopulateListView 做法）
    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.BindEventBatched(name, evt)
    }

    ; 表身份 = tableItem 对象；t 仅作控件命名显示顺序槽位（内部解析）
    UpdateItemColor(tableItem, i) {
        if (!IsObject(tableItem))
            tableItem := GetTableByID(String(tableItem))
        if (!tableItem)
            return
        t := tableItem.Index
        if (this._useVirtual.Has(t)) {
            this._vl.UpdateColor(t, i)
            return
        }
        if (!this._IsRendered(t, i))
            return
        item := tableItem.Items[i]
        state := item ? item.ColorState : 0
        colorHex := state == 1 ? "#2E7D32" : state == 2 ? "#F9A825" : state == 3 ? "#C62828" : "Transparent"
        this.ui.Update("Color_" t "_" i, "Background", colorHex)
    }

    ; 增量刷新单行显示值：结构操作（上/下移）后只刷被交换两行，不整列表重建（滚动位置自然保留）。
    ; 槽位不变、事件绑 (tableItem, index) 闭包不重建，故仅更新各控件值即可。
    RefreshItemRow(t, i) {
        if (this._useVirtual.Has(t)) {
            this._vl.RefreshRow(t, i)
            this._RefreshSideTreeIfItem(t, i)
            return
        }
        if (!this._IsRendered(t, i))
            return
        tableItem := MySoftData.TableInfo[t]
        item := tableItem.Items[i]
        if (!item)
            return
        isTiming := CheckIsTimingMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isVoice := GetTableSymbol(t) == "Voice"
        if (isVoice) {
            ; 语音宏：触发键列显示唤醒词（无按键）
            tkStr := item.VoiceKeywords
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        } else if (isTiming) {
            tkStr := ""
        } else {
            tkStr := FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        }
        loopStr := item.LoopCount == "-1" ? GetLang("无限") : item.LoopCount
        tkTypeIdx := item.TriggerType - 1
        if (isUI)
            tkTypeIdx := 3
        this.ui.Update("Remark_" t "_" i, "Text", item.Remark)
        if ((CheckIsNormalTable(t) || GetTableSymbol(t) == "Replace") && tkStr == GetLang("编辑"))
            tkStr := ""
        if (isMenu || isUI) {
            imagePath := this._GetItemConfigImagePath(t, item)
            configured := imagePath != ""
            this.ui.Update("ImageCfgGlyph_" t "_" i, "Visibility", configured ? "Collapsed" : "Visible")
            this.ui.Update("ImageCfgThumb_" t "_" i, "Source", StrReplace(imagePath, "\", "/"))
            this.ui.Update("ImageCfgThumb_" t "_" i, "Visibility", configured ? "Visible" : "Collapsed")
        } else if (isTiming) {
            configured := HasTimingConfig(item)
            this.ui.Update("TimingCfgEmpty_" t "_" i, "Visibility", configured ? "Collapsed" : "Visible")
            this.ui.Update("TimingCfgSet_" t "_" i, "Visibility", configured ? "Visible" : "Collapsed")
        } else if (tkStr == "") {
            this.ui.Update("TKBtn_" t "_" i, "Content", Chr(0xE92E))
            this.ui.Update("TKBtn_" t "_" i, "FontFamily", "Segoe Fluent Icons, Segoe MDL2 Assets")
        } else {
            this.ui.Update("TKBtn_" t "_" i, "Content", tkStr)
        }
        if (CheckIsNormalTable(t) || GetTableSymbol(t) == "Replace") {
            this.ui.Update("TKBtn_" t "_" i "_Entries", "Visibility", item.TK == "" ? "Visible" : "Collapsed")
            this.ui.Update("TKBtn_" t "_" i, "FontFamily", MainSoftData.FontType)
        }
        this.ui.Update("TKType_" t "_" i, "SelectedIndex", String(tkTypeIdx))
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)
        this.SyncItemForbidBtnUI(t, i, item.Forbid)
        rowSel := this._sideTreeSel.Has(t) && this._sideTreeSel[t] == item.ID
        cardBg := rowSel ? "{DynamicResource TabSelBg}" : ((item.Forbid || GetItemFoldForbidState(tableItem, i)) ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource ControlBg}")
        this.ui.Update("ItemCard_" t "_" i, "Background", cardBg)
        try this.ui.Update("ItemCardInner_" t "_" i, "Opacity", (item.Forbid || GetItemFoldForbidState(tableItem, i)) ? this._ForbidContentOpacity() : "1")
        this.ui.Update("RowSelDot_" t "_" i, "Visibility", rowSel ? "Visible" : "Collapsed")
        this.ui.Update("RowSelMark_" t "_" i, "Visibility", rowSel ? "Visible" : "Collapsed")
        this.UpdateItemColor(t, i)
        this._RefreshItemEditGlyph(t, i, item.Macro)
        this._RefreshSideTreeIfItem(t, i)
    }

    _RefreshSideTreeIfItem(t, i) {
        if (this._suppressSideTreeRefresh)
            return
        if (!this._sideTreeSel.Has(t))
            return
        tableItem := MySoftData.TableInfo[t]
        if (i < 1 || i > tableItem.Items.Length)
            return
        item := tableItem.Items[i]
        if (item && item.ID == this._sideTreeSel[t])
            this.RefreshSideTree(t)
    }

    _RefreshItemEditGlyph(t, i, macroStr) {
        kind := GetMacroEditKind(macroStr)
        if (kind = 0) {
            this.ui.Update("EditGlyph3_" t "_" i, "Visibility", "Collapsed")
            return
        }
        this.ui.Update("EditGlyph3_" t "_" i, "Visibility", "Visible")
        this.ui.Update("EditGlyph3_" t "_" i, "Text", kind = 2 ? Chr(0xE8F1) : Chr(0xE71D))
        this.ui.Update("EditGlyph3_" t "_" i, "Margin", kind = 2 ? "3,0,0,0" : "2,0,0,0")
    }

    _XmlEsc(s) {
        s := EscapeXamlXml(s)
        s := StrReplace(s, "`r`n", "&#10;")
        s := StrReplace(s, "`n", "&#10;")
        s := StrReplace(s, "`r", "&#10;")
        return s
    }
