
    _LabelRow(label, controlXaml) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        if (label == "")
            return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4">' controlXaml '</StackPanel>'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4">'
            . '<TextBlock Text="' this._XmlEsc(label) '" Margin="0,0,6,0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . controlXaml
            . '</StackPanel>'
    }

    ; 两列行：label1+TextBox1 | label2+TextBox2，复刻旧布局「一行两列」
    _TwoColRow(ns, label1, name1, val1, label2, name2, val2) {
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,0,4">'
            . '<TextBlock Text="' this._XmlEsc(label1) '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name1 '" Text="' this._XmlEsc(val1) '" Width="220" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<TextBlock Text="' this._XmlEsc(label2) '" Width="120" Margin="16,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name2 '" Text="' this._XmlEsc(val2) '" Width="220" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
    }

    ; ============ 全局页：系统 / 宏 / 显示页签 / 界面 / AI 助手 ============
    BuildSettingTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Setting 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Setting")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'

        ; ============ 设置中心 ============
        ; 左侧 8 页导航 + 右侧卡片页，全部设置内联；控件沿用既有 Name 与 MainSoftData 字段；
        ; 落盘仍由主界面「应用并保存」统一处理（OnSaveSetting 的 CheckAndAddDirty 已覆盖这些键）。
        iconFont := 'Segoe Fluent Icons, Segoe MDL2 Assets'
        navStyle := '<Style x:Key="SetNavItem" TargetType="RadioButton">'
            . '<Setter Property="Height" Value="36"/><Setter Property="Margin" Value="0"/><Setter Property="Padding" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalAlignment" Value="Stretch"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">'
            . '<Border x:Name="Bd" Background="Transparent"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="3"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Rectangle x:Name="Bar" Grid.Column="0" Width="3" RadiusX="1.5" RadiusY="1.5" Fill="{DynamicResource TextMain}" Visibility="Collapsed" Margin="0,5,0,5"/>'
            . '<ContentPresenter Grid.Column="1" Margin="8,0,0,0" VerticalAlignment="Center"/></Grid></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListAltBg}"/></Trigger>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="Bar" Property="Visibility" Value="Visible"/><Setter Property="FontWeight" Value="Bold"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        switchStyle := '<Style x:Key="SetSwitch" TargetType="CheckBox"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="50"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border x:Name="Track" Width="42" Height="24" CornerRadius="12" Background="{DynamicResource ControlBorder}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><Grid><TextBlock x:Name="OffGlyph" Text="×" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource TextSub}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,7,1"/><Ellipse x:Name="Thumb" Width="18" Height="18" Fill="{DynamicResource ControlBg}" HorizontalAlignment="Left" Margin="2"/></Grid></Border><ContentPresenter Grid.Column="1" VerticalAlignment="Center"/></Grid><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="{DynamicResource ActionBg}"/><Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="OffGlyph" Property="Visibility" Value="Collapsed"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        fieldStyles := '<Style TargetType="TextBox"><Setter Property="Height" Value="33"/><Setter Property="MinHeight" Value="33"/><Setter Property="Padding" Value="10,0"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Foreground" Value="{DynamicResource InputText}"/><Setter Property="Background" Value="{DynamicResource InputBg}"/><Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/></Border></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="MinHeight" Value="30"/></Style>'
            . '<Style x:Key="SetTabButton" TargetType="ToggleButton"><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="Width" Value="85"/><Setter Property="Height" Value="32"/><Setter Property="Margin" Value="0,4,8,4"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton"><Border x:Name="Bd" CornerRadius="6" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"><Grid><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{TemplateBinding Foreground}"/><Ellipse x:Name="Dot" Visibility="Collapsed" Width="7" Height="7" Fill="{DynamicResource TextMain}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,5,6,0"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="Dot" Property="Visibility" Value="Visible"/><Setter Property="FontWeight" Value="Bold"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        ; ---------- 行/卡片构建 ----------
        ; 中文标签列预留 6 个 13 DIP 全角字及右侧留白。
        labelWidth := MainSoftData.Lang == "English" ? 112 : 84
        this._setHelpMap := Map()
        this._setHelpSeq := 0
        helpFnByLabel := Map()
        helpFnByLabel[GetLang("多线程数")] := OnClickMutiThreadHelpBtn
        helpFnByLabel[GetLang("模态子窗口")] := OnClickModalSubGuiHelpBtn
        helpFnByLabel[GetLang("仅前台运行宏")] := OnClickCheckForegroundHelpBtn
        helpFnByLabel[GetLang("管理员启动")] := OnClickAdminStartHelpBtn
        helpFnByLabel[GetLang("重复按下行为")] := OnClickKeyDownDownHelpBtn
        helpFnByLabel[GetLang("宏终止方式")] := OnClickMacroStopHelpBtn
        helpFnByLabel[GetLang("自动松开修饰键")] := OnClickAutoLoosenModifierHelpBtn
        helpFnByLabel[GetLang("连续触发")] := OnClickContinuousTriggerHelpBtn
        helpFnByLabel[GetLang("宏手柄类型")] := OnClickMacroJoyTypeHelpBtn
        helpFnByLabel[GetLang("手柄映射")] := OnClickTriggerJoyTypeHelpBtn
        dot(tip, title := "") {
            if (tip == "")
                return ""
            this._setHelpSeq += 1
            name := "BtnSetHelp_" this._setHelpSeq
            this._setHelpMap[name] := {title: title != "" ? title : GetLang("说明"), text: tip, fn: helpFnByLabel.Has(title) ? helpFnByLabel[title] : ""}
            return '<Button Grid.Column="1" Name="' name '" Content="?" Width="24" MinHeight="24" Padding="4,2" FontSize="11" FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Center" Cursor="Hand"/>'
        }
        afterHint(ctrl, hint, hintName := "") {
            hintAttr := (hintName == "" ? "" : ' Name="' hintName '"') ' Text="' this._XmlEsc(hint) '"'
            if (InStr(ctrl, "<Slider"))
                return '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
                    . ctrl
                    . '<TextBlock Grid.Column="1"' hintAttr ' MaxWidth="200" Margin="10,0,0,0" FontSize="12" Foreground="{DynamicResource TextSub}" TextWrapping="Wrap" VerticalAlignment="Center"/></Grid>'
            return '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . ctrl
                . '<TextBlock Grid.Column="1"' hintAttr ' Margin="10,0,0,0" FontSize="12" Foreground="{DynamicResource TextSub}" TextWrapping="Wrap" VerticalAlignment="Center"/></Grid>'
        }
        row(label, ctrl, tip := "", lblName := "", help := "") {
            if (help == "" && tip != "" && (helpFnByLabel.Has(label) || InStr(tip, "`n"))) {
                help := tip
                tip := ""
            }
            if (tip != "")
                ctrl := afterHint(ctrl, tip)
            helpBtn := dot(help, label)
            return '<Border MinHeight="48" Padding="0,5" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="0,0,0,0.5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="' labelWidth '"/><ColumnDefinition Width="36"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . '<TextBlock' (lblName == "" ? "" : ' Name="' lblName '"') ' Text="' this._XmlEsc(label) '" Margin="0,0,4,0" TextWrapping="Wrap" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource TextMain}" FontSize="13"/>' helpBtn
                . '<Grid Grid.Column="2" VerticalAlignment="Center">' ctrl '</Grid></Grid></Border>'
        }
        tog(label, name, val, tip := "") {
            return row(label, '<CheckBox Name="' name '" IsChecked="' (val ? "True" : "False") '" Style="{StaticResource SetSwitch}"/>', tip)
        }
        togI(label, name, val) {
            return '<CheckBox Name="' name '" Content="' this._XmlEsc(label) '" IsChecked="' (val ? "True" : "False") '" Style="{StaticResource SetTabButton}" ToolTip="' GetLang("隐藏的页签不影响宏触发，保存后重启生效。") '"/>'
        }
        cmb(label, name, items, sel, zero := false, tip := "", descriptions := [], width := 0, editable := false) {
            selIdx := ""
            itemsXaml := ""
            for k, it in items {
                isSel := IsInteger(sel) ? (k == Integer(sel) + (zero ? 1 : 0)) : (it == sel)
                if (isSel)
                    selIdx := k - 1
                descAttr := descriptions.Length ? ' Tag="' this._XmlEsc(GetLang(descriptions[k])) '"' : ""
                itemsXaml .= '<ComboBoxItem Content="' this._XmlEsc(it) '"' descAttr '/>'
            }
            selAttr := (selIdx == "") ? "" : ' SelectedIndex="' selIdx '"'
            if (editable)
                selAttr := ' IsEditable="True" IsTextSearchEnabled="False" Text="' this._XmlEsc(String(sel)) '"'
            widthAttr := width ? ' Width="' width '"' : ""
            ctrl := '<ComboBox Name="' name '" Height="33" MinHeight="33" Padding="10,0" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"' selAttr widthAttr '>' itemsXaml '</ComboBox>'
            if (descriptions.Length)
                ctrl := afterHint(ctrl, "{Binding SelectedItem.Tag, ElementName=" name "}")
            return row(label, ctrl, tip)
        }
        num(label, name, val, tip := "", help := "") {
            return row(label, '<TextBox Name="' name '" Text="' this._XmlEsc(String(val)) '" Height="33" MinHeight="33" Padding="10,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>', tip, , help)
        }
        sld(label, name, valName, val, mn, mx, tk, tip := "") {
            return row(label, '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="9"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Slider Name="' name '" Height="28" Minimum="' mn '" Maximum="' mx '" Value="' val '" TickFrequency="' tk '" IsSnapToTickEnabled="True" VerticalAlignment="Center" Cursor="Hand"/>'
                . '<TextBox Grid.Column="2" Name="' valName '" Text="' val '" TextAlignment="Center"/></Grid>', tip)
        }
        card(title, glyph, body, margin := "0", headerRight := "", modId := "") {
            ; 每张卡的最后一行不画下分隔线；前面的行保留，用于所有类别的统一布局。
            body := RegExReplace(body, 's)(.*)<Border([^>]*?)BorderThickness="0,0,0,0\.5"', '$1<Border$2BorderThickness="0"')
            g := glyph == "" ? "" : '<TextBlock Text="' glyph '" FontFamily="' iconFont '" Foreground="{DynamicResource TitleBarForeground}" FontSize="12" Margin="0,0,6,0" VerticalAlignment="Center"/>'
            if (modId != "")
                headerRight := '<Button Name="BtnSetReset_' modId '" Content="&#xE72C;" FontFamily="' iconFont '" FontSize="12" Width="22" Height="22" MinHeight="22" Padding="0" Margin="0,0,2,0" VerticalAlignment="Center" Cursor="Hand" ToolTip="' this._XmlEsc(GetLang("重置")) '" Visibility="Collapsed" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource TextSub}"/>' headerRight
            return '<Border Margin="' margin '" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="10" Padding="0">'
                . '<Grid><Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
                . '<Border Background="{DynamicResource TitleBarColor}" CornerRadius="10,10,0,0" Padding="10,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Orientation="Horizontal" VerticalAlignment="Center">' g '<TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" Foreground="{DynamicResource TitleBarForeground}" VerticalAlignment="Center"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">' headerRight '</StackPanel></Grid></Border>'
                . '<StackPanel Grid.Row="1" Margin="15,6,15,11">' body '</StackPanel></Grid></Border>'
        }
        twoCol(l, r) {
            ; 左右两列各自垂直堆叠，互不卡行高，避免中间断层。整行模块（如主题颜色）放在 twoCol 外面。
            return '<Grid VerticalAlignment="Top"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" VerticalAlignment="Top">' l '</StackPanel><StackPanel Grid.Column="2" VerticalAlignment="Top">' r '</StackPanel></Grid>'
        }
        navItem(id, glyph, text, checked := false) {
            return '<RadioButton Name="SetNav_' id '" GroupName="SetNav" Style="{StaticResource SetNavItem}"' (checked ? ' IsChecked="True"' : '') '><StackPanel Orientation="Horizontal" Margin="12,0,0,0"><TextBlock Text="' glyph '" FontFamily="' iconFont '" FontSize="14" Foreground="{DynamicResource TextMain}" Margin="0,0,9,0" VerticalAlignment="Center"/><TextBlock Name="SetNavText_' id '" Text="' this._XmlEsc(text) '" VerticalAlignment="Center" FontSize="13"/></StackPanel></RadioButton>'
        }
        pending(body) {
            return '<Expander Header="' GetLang("待确认的原有功能") '" IsExpanded="False" Margin="0,20,0,0" Foreground="{DynamicResource TextSub}"><StackPanel Margin="12">' body '</StackPanel></Expander>'
        }
        page(id, body, visible := false) {
            return '<StackPanel Name="SetPage_' id '"' (visible ? '' : ' Visibility="Collapsed"') '>'
                . '<StackPanel Margin="14,20,14,28">' body '</StackPanel></StackPanel>'
        }

        ; ---------- 公共片段 ----------
        tabsBody := '<WrapPanel>'
            . togI(GetLang("按键宏"), "TabVisible_Normal", this._TabVisibleVal("Normal")) . togI(GetLang("字串宏"), "TabVisible_String", this._TabVisibleVal("String")) . togI(GetLang("菜单宏"), "TabVisible_Menu", this._TabVisibleVal("Menu")) . togI(GetLang("界面宏"), "TabVisible_UI", this._TabVisibleVal("UI")) . togI(GetLang("语音宏"), "TabVisible_Voice", this._TabVisibleVal("Voice")) . togI(GetLang("定时宏"), "TabVisible_Timing", this._TabVisibleVal("Timing")) . togI(GetLang("宏"), "TabVisible_SubMacro", this._TabVisibleVal("SubMacro")) . togI(GetLang("按键替换"), "TabVisible_Replace", this._TabVisibleVal("Replace")) . togI(GetLang("网络宏"), "TabVisible_Network", this._TabVisibleVal("Network")) . '</WrapPanel>'
        appearanceBody := cmb(GetLang("软件字体"), "CmbFont", MainSoftData.FontList, MainSoftData.FontType, false, GetLang("软件界面使用的字体，修改后保存设置生效。"), , 160)
            . sld(GetLang("字体大小"), "ThemeFontSizeCon", "ThemeFontSizeVal", MainSoftData.FontSize, 0, 40, 1, GetLang("字号 0~40；保存后统一刷新界面。"))

        ; ---------- 页：系统（按参考稿逐行排列） ----------
        ltRtSwitch := '<CheckBox Name="ChkJoyLtRtAsButton" IsChecked="' (MainSoftData.JoyLtRtAsButton ? "True" : "False") '" Style="{StaticResource SetSwitch}"/>'
        behaviorPage := page("behavior"
            , twoCol(
                card(GetLang("软件"), "&#xE74C;", tog(GetLang("开机自启"), "ChkBootStart", MainSoftData.IsBootStart)
                    . tog(GetLang("管理员启动"), "ChkAdminStart", MainSoftData.IsAdminStart, GetLang("后台功能与部分按键类型需要管理员权限"))
                    . tog(GetLang("在线功能"), "ChkDataReport", MainSoftData.IsDataReport, GetLang("获取版本更新、AI 智能助手"))
                    . cmb(GetLang("语言"), "CmbLang", MainSoftData.LangArr, MainSoftData.Lang)
                    . cmb(GetLang("首选编辑器"), "CmbPreferredEditor", GetLangArr(["逻辑树", "图形节点"]), MainSoftData.PreferredMacroEditor)
                    . tog(GetLang("模态子窗口"), "ChkModalSubGui", MainSoftData.IsModalSubGui, GetLang("打开指令编辑等子窗口时禁用主窗口")), "0", "", "soft")
                . card(GetLang("显示页签"), "&#xE8A5;", tabsBody, "0,18,0,0", "", "tabs")
                , card(GetLang("通用"), "&#xE713;", cmb(GetLang("截图工具"), "CmbScreenShot", GetLangArr(["微软截图", "RMT截图", "SC截图"]), MainSoftData.ScreenShotType, false, ""
                        , ["调用 Windows 自带截图工具。", "内置框选截图，支持边缘吸附。", "支持标注、马赛克和贴图。"], 132)
                    . cmb(GetLang("OCR类型"), "CmbOCRType", ["RapidOCR", "Tesseract OCR"], MainSoftData.OCRTypeValue, false, ""
                        , ["默认引擎，使用 PP-OCRv6 识别中英文。", "使用 Tesseract 语言包识别中英文。"], 132)
                    . cmb(GetLang("Excel"), "CmbExcelBackend", GetLangArr(["C# DLL", "AHK（兼容）"]), MainSoftData.ExcelBackend, false, ""
                        , ["默认方式，优先连接已打开的工作簿。", "使用原有 AHK 读写方式。"], 132)
                    . cmb(GetLang("图片识别模型"), "CmbSearchImage", GetLangArr(["OpenCV", "RMT搜图"]), MainSoftData.SearchImageType, false, ""
                        , ["默认灰度匹配，支持颜色匹配和缩放自适应。", "使用 AHK 内置的图片搜索。"], 132)
                    . tog(GetLang("图片识别自适应"), "ChkSearchImageAdaptive", MainSoftData.SearchImageAdaptive, GetLang("仅 OpenCV 生效，匹配分辨率或 DPI 缩放变化后的图片"))
                    . cmb(GetLang("多线程数"), "EditMutiThreadNum", ["-1", "0"], MainSoftData.MutiThreadNum, false
                        , GetLang("-1：动态多线程；0：单线程；n：固定线程数（推荐 3~5）"), , , true)
                    . num(GetLang("网络宏端口"), "EditNetPort", MainSoftData.NetworkPort, GetLang("网络宏端口 1-65535，默认 16888；仅监听本机回环地址。"))
                    . cmb(GetLang("指令备注生成"), "CmbRemarkAuto", GetLangArr(["不生成", "自动生成", "覆盖生成"]), MainSoftData.RemarkAutoType), "0", "", "general")
                . card(GetLang("手柄"), "&#xE7FC;", cmb(GetLang("手柄映射"), "CmbTriggerJoyType", ["Xbox", "PS5"], MainSoftData.TriggerJoyType)
                    . cmb(GetLang("宏手柄类型"), "CmbJoyType", ["Xbox", "PS5"], MainSoftData.JoyType)
                    . row(this._JoyLtRtAsButtonLabel(), afterHint(ltRtSwitch, this._JoyLtRtAsButtonDesc(), "LblJoyLtRtAsButton_Desc"), "", "LblJoyLtRtAsButton"), "0,18,0,0", "", "joy"))
            , true)

        ; ---------- 页：宏 ----------
        floatOff := "`n`n" GetLang("填 0 时不浮动。")
        audioRows := row(GetLang("开始音效"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="58"/></Grid.ColumnDefinitions><TextBox Name="StartTipAudioCon" Text="' this._XmlEsc(MainSoftData.StartTipAudio) '" Padding="5,0"/><Button Grid.Column="1" Name="BtnStartTipBrowse" Content="' GetLang("浏览") '" Margin="6,0,0,0" Padding="4,0"/></Grid>')
            . row(GetLang("结束音效"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="58"/></Grid.ColumnDefinitions><TextBox Name="EndTipAudioCon" Text="' this._XmlEsc(MainSoftData.EndTipAudio) '" Padding="5,0"/><Button Grid.Column="1" Name="BtnEndTipBrowse" Content="' GetLang("浏览") '" Margin="6,0,0,0" Padding="4,0"/></Grid>')
            . row(GetLang("终止音效"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="58"/></Grid.ColumnDefinitions><TextBox Name="StopTipAudioCon" Text="' this._XmlEsc(MainSoftData.StopTipAudio) '" Padding="5,0"/><Button Grid.Column="1" Name="BtnStopTipBrowse" Content="' GetLang("浏览") '" Margin="6,0,0,0" Padding="4,0"/></Grid>')
        macroPage := page("macro", twoCol(
                card(GetLang("通用"), "&#xE8D4;", tog(GetLang("仅前台运行宏"), "ChkForeground", MainSoftData.CheckForeground, GetLang("窗口不匹配则终止运行的宏"))
                    . tog(GetLang("自动松开修饰键"), "ChkAutoLoosen", MainSoftData.AutoLoosenModifier, GetLang("组合键触发前先松开修饰键"))
                    . tog(GetLang("连续触发"), "ChkContinuous", MainSoftData.ContinuousTrigger, GetLang("按住触发键期间允许连续触发"))
                    . cmb(GetLang("宏终止方式"), "CmbMacroStop", GetLangArr(["智能终止", "强制终止"]), MainSoftData.MacroStopType)
                    . cmb(GetLang("重复按下行为"), "CmbKeyDownDown", GetLangArr(["自动松开", "忽略重复按下", "允许重复按下"]), MainSoftData.KeyDownDownType)
                    . tog(GetLang("无变量提醒"), "ChkNoVariable", MainSoftData.NoVariableTip, GetLang("变量为空时提示")), "0", "", "trig")
                , card(GetLang("随机浮动"), "&#xE823;", num(GetLang("点击时间浮动"), "EditHoldFloat", MainSoftData.HoldFloat
                        , GetLang("按键指令点击时的按住时长（%）")
                        , GetLang("按键指令点击时长为 100 ms。填 10，按住约 90～110 ms；填 -10，按住约 90～100 ms。") floatOff)
                    . num(GetLang("每次间隔浮动"), "EditPreIntervalFloat", MainSoftData.PreIntervalFloat
                        , GetLang("多次点击、搜索等操作的重复间隔（%）")
                        , GetLang("搜索重试间隔为 500 ms。填 10，下次重试前约等 450～550 ms；填 -10，约等 450～500 ms。") floatOff)
                    . num(GetLang("间隔指令浮动"), "EditIntervalFloat", MainSoftData.IntervalFloat
                        , GetLang("间隔指令的等待时长（%）")
                        , GetLang("间隔指令设为 1000 ms。填 10，约等 900～1100 ms；填 -10，约等 900～1000 ms。") floatOff)
                    . num(GetLang("坐标X浮动"), "EditCoordXFloat", MainSoftData.CoordXFloat
                        , GetLang("鼠标目标坐标的水平偏移（像素）")
                        , GetLang("鼠标绝对移动的目标 X 为 400。填 10，X 在 390～410 间随机；填 -10，只向左浮动，X 为 390～400。") floatOff)
                    . num(GetLang("坐标Y浮动"), "EditCoordYFloat", MainSoftData.CoordYFloat
                        , GetLang("鼠标目标坐标的垂直偏移（像素）")
                        , GetLang("鼠标绝对移动的目标 Y 为 300。填 10，Y 在 290～310 间随机；填 -10，只向上浮动，Y 为 290～300。") floatOff), "0", "", "float")
                    . card(GetLang("音频"), "&#xE767;", audioRows, "0,18,0,0", "", "audio")))

        ; ---------- 页：指令录制 ----------
        recordPage := page("record", twoCol(
            card(GetLang("通用"), "&#xE7C8;", tog(GetLang("录制显示边框"), "ShowBorderCon", MainSoftData.RecordShowBorder, GetLang("录制时显示范围边框"))
                . tog(GetLang("长按多次录制"), "HoldMutiCon", MainSoftData.RecordHoldMuti, GetLang("按住时连续录制"))
                . tog(GetLang("结束自动添加按键松开"), "AutoLoosenCon", MainSoftData.RecordAutoLoosen, GetLang("录制结束后补充松开指令")), "0", "", "recCommon")
            . card(GetLang("键盘"), "&#xE765;", tog(GetLang("键盘录制"), "KeyboardTogCon", MainSoftData.RecordKeyboard, GetLang("记录键盘操作")), "0,18,0,0", "", "recKey")
            , card(GetLang("鼠标"), "&#xE962;", tog(GetLang("鼠标录制"), "MouseTogCon", MainSoftData.RecordMouse, GetLang("记录鼠标操作"))
                . cmb(GetLang("鼠标轨迹"), "MouseTrailModeCon", GetLangArr(["不录制", "关键点位", "关键点相对位移", "全量"]), MainSoftData.RecordMouseTrail, true)
                . num(GetLang("速度 (0~100)"), "MouseTrailSpeedCon", MainSoftData.RecordMouseTrailSpeed), "0", "", "recMouse")
            . card(GetLang("手柄"), "&#xE7FC;", tog(GetLang("手柄录制"), "JoyTogCon", MainSoftData.RecordJoy, GetLang("记录手柄操作"))
                . num(GetLang("检测间隔 (ms)"), "JoyIntervalCon", MainSoftData.RecordJoyInterval), "0,18,0,0", "", "recJoy")))

        ; ---------- 页：快捷键 ----------
        hotkeyGroups := [
            {title: "全局与工具", glyph: "&#xE765;", defs: [
                {f: "SuspendHotkey", l: "软件休眠", t: true},
                {f: "PauseHotkey", l: "暂停宏", t: false},
                {f: "KillMacroHotkey", l: "终止宏", t: false},
                {f: "ToolRecordMacroHotKey", l: "指令录制", t: false},
                {f: "ToolTextFilterHotKey", l: "文本提取", t: false}]},
            {title: "截图与工具", glyph: "&#xE8D4;", defs: [
                {f: "ScreenShotHotKey", l: "屏幕截图", t: false},
                {f: "FreePasteHotKey", l: "自由贴", t: false},
                {f: "ToolCheckHotkey", l: "鼠标信息", t: false}]},
            {title: "调试", glyph: "&#xE76C;", defs: [
                {f: "DebugRunHotkey", l: "播放/继续", t: true},
                {f: "DebugStepOverHotkey", l: "步进", t: true},
                {f: "DebugStepHotkey", l: "步入", t: true},
                {f: "DebugStepOutHotkey", l: "步出", t: true},
                {f: "DebugRunToCursorHotkey", l: "运行到光标", t: true},
                {f: "DebugToggleSkipHotkey", l: "跳过指令", t: true},
                {f: "DebugRunAllHotkey", l: "运行", t: true}]}
        ]
        hotkeyCards := []
        for hi, hg in hotkeyGroups {
            hb := ""
            for hd in hg.defs {
                hv := MainSoftData.HasProp(hd.f) ? String(MainSoftData.%hd.f%) : ""
                hdisp := hv == "" ? GetLang("无") : FormatHotkeyDisplay(hv)
                hb .= row(GetLang(hd.l), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions><TextBox Name="Val_' hd.f '" Text="' this._XmlEsc(hdisp) '" IsReadOnly="True"/><Button Grid.Column="1" Name="BtnEdit_' hd.f '" Content="&#xE70F;" FontFamily="' iconFont '" ToolTip="' GetLang("录入快捷键") '" Margin="8,0,0,0" Padding="0"/></Grid>')
            }
            ; 左列放两张卡（全局 + 截图），第二张要和上面留出间距；右列只有一张，不用
            mg := (hi == 2) ? "0,18,0,0" : "0"
            hotkeyCards.Push(card(GetLang(hg.title), hg.glyph, hb, mg, "", "hk" hi))
        }
        ; 三张卡：左列「全局与工具 + 截图与工具」，右列「调试」（项多，单独占一列）
        hotkeyPage := page("hotkey", twoCol(hotkeyCards[1] . hotkeyCards[2], hotkeyCards[3]))

        ; ---------- 页：日志 ----------
        logLevels := [
            ["debug", "调试", "记录手柄按键输出、插件初始化等调试细节。"],
            ["info", "信息", "记录网络监听启动、配置导入等常规事件。"],
            ["warn", "警告", "只记录警告。"],
            ["error", "错误", "只记录错误。"]
        ]
        logLevelButtons := '<UniformGrid Columns="4">'
        logLevelHelp := GetLang("可同时勾选多个级别。系统日志只写入勾选的级别，全部取消则暂停写入。")
        for level in logLevels {
            description := GetLang(level[3])
            logLevelHelp .= "`n" GetLang(level[2]) " · " description
            logLevelButtons .= '<CheckBox Name="LogLevel_' level[1] '" Style="{StaticResource SetTabButton}" Width="Auto"'
                . ' IsChecked="' (RMTLogLevelEnabled(level[1], MainSoftData.SysLogMinLevel) ? "True" : "False") '" Content="' this._XmlEsc(GetLang(level[2])) '" ToolTip="' this._XmlEsc(description) '"/>'
        }
        logLevelButtons .= '</UniformGrid>'
        logPage := page("diagnostic", twoCol(
            card(GetLang("指令显示"), "&#xE8A5;", tog(GetLang("启用指令显示"), "ChkCMDTip", MySoftData.CMDTip, GetLang("在屏幕上显示宏运行状态"))
                . num(GetLang("显示位置 X"), "CmdTipPosXCon", MainSoftData.CMDPosX)
                . num(GetLang("显示位置 Y"), "CmdTipPosYCon", MainSoftData.CMDPosY)
                . sld(GetLang("显示宽度"), "CmdTipWidthCon", "CmdTipWidthVal", MainSoftData.CMDWidth, 80, 800, 5)
                . sld(GetLang("显示高度"), "CmdTipHeightCon", "CmdTipHeightVal", MainSoftData.CMDHeight, 40, 600, 5)
                . sld(GetLang("字体大小"), "CmdTipFontCon", "CmdTipFontVal", MainSoftData.CMDFontSize, 8, 36, 1)
                . sld(GetLang("背景透明度"), "CmdTipAlphaCon", "CmdTipAlphaVal", MainSoftData.CMDTransparency, 0, 100, 1)
                . tog(GetLang("输出到文件"), "CmdTipLogFileCon", MainSoftData.CMDLogToFile, GetLang("把指令显示内容写入日志文件")), "0", "", "cmdTip")
            , card(GetLang("日志与错误"), "&#xE81C;", row(GetLang("日志级别"), logLevelButtons, , , logLevelHelp)
                . tog(GetLang("警告气泡"), "ChkLogWarnBubble", MainSoftData.LogWarnBubble, GetLang("宏运行警告通过托盘气泡提醒"))
                . tog(GetLang("错误中心"), "ChkLogErrorBadge", MainSoftData.LogErrorBadge, GetLang("汇总宏运行错误，便于集中查看"))
                . row(GetLang("日志文件路径"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox Name="CmdTipLogPathCon" Padding="2,0" Text="' this._XmlEsc(CMDLogPathDisplay(MainSoftData.CMDLogFilePath)) '"/><Button Name="BtnCmdTipBrowse" Grid.Column="1" Content="' GetLang("浏览") ' ↗" Width="76" Height="33" Margin="8,0,0,0" Padding="6,0"/></Grid>'
                    , GetLang("这是指令显示输出到文件时使用的路径。") "`n" GetLang("默认是软件所在目录下的 Log。把整个 RMT 文件夹换个位置后，会自动改到新目录，不用重新选择。"))
                . cmb(GetLang("自动清理时间"), "CmdTipAutoClearCon", GetLangArr(["从不", "每天", "每周"]), MainSoftData.CMDLogAutoClear, true
                    , GetLang("仅清理指令显示日志文件。") "`n" GetLang("每天清理当天之前的文件；每周清理本周之前的文件。"))
                . row(GetLang("日志中心"), '<Button Name="BtnLogCenter" Content="' GetLang("打开日志中心") ' ↗" HorizontalAlignment="Left" Padding="10,0"/>'), "0", "", "logErr")))

        ; ---------- 页：界面 ----------
        ; 自定义界面：面板下拉的数据源（界面宏的折叠框）
        uiFoldNames := []
        try {
            uiTable := GetTableBySymbol("UI")
            if (uiTable) {
                for i, f in uiTable.Folds {
                    nm := Trim(String(f.Remark))
                    uiFoldNames.Push(nm == "" ? (GetLang("面板") " " i) : (i ". " nm))
                }
            }
        }
        if (uiFoldNames.Length == 0)
            uiFoldNames.Push(GetLang("面板") " 1")
        triggerPage := page("trigger"
            , twoCol(
                card(GetLang("菜单宏-轮盘"), "&#xE700;", tog(GetLang("固定位置"), "WheelFixedPosCon", MainSoftData.FixedMenuWheel, GetLang("固定在屏幕中下方"))
                    . tog(GetLang("显示扇区名称提示"), "WheelShowTooltipCon", MainSoftData.MenuWheelShowTooltip, GetLang("悬停显示扇区名称"))
                    . cmb(GetLang("选择模式"), "WheelSelectModeCon", GetLangArr(["点击选择", "划线选择"]), MainSoftData.MenuWheelSelectMode)
                    . sld(GetLang("轮盘大小"), "WheelScaleCon", "WheelScaleVal", MainSoftData.MenuWheelScale, 50, 200, 10), "0", "", "wheel")
                    . card(GetLang("时间-倒计时"), "&#xE916;", cmb(GetLang("样式"), "CountDownStyleCon", GetLangArr(["时分秒", "智能", "秒"]), MainSoftData.CountDownStyle)
                        . tog(GetLang("补零"), "CountDownPadCon", MainSoftData.CountDownPadZero, GetLang("如 1:30:9 显示为 01:30:09；仅秒不补"))
                        . sld(GetLang("透明度"), "CountDownAlphaCon", "CountDownAlphaVal", MainSoftData.CountDownAlpha, 0, 100, 1)
                        . sld(GetLang("字体大小"), "CountDownFontCon", "CountDownFontVal", MainSoftData.CountDownFontSize, 8, 72, 1), "0,18,0,0", "", "countdown")
                , card(GetLang("界面宏-浮窗"), "&#xE737;", sld(GetLang("按钮宽度"), "UIPanelBtnWidthCon", "UIPanelBtnWidthVal", MainSoftData.UIPanelBtnWidth, 40, 250, 5)
                    . sld(GetLang("按钮高度"), "UIPanelBtnHeightCon", "UIPanelBtnHeightVal", MainSoftData.UIPanelBtnHeight, 20, 60, 2)
                    . sld(GetLang("字体大小"), "UIPanelFontSizeCon", "UIPanelFontSizeVal", MainSoftData.UIPanelFontSize, 8, 24, 1)
                    . sld(GetLang("每行个数"), "UIPanelColsCon", "UIPanelColsVal", MainSoftData.UIPanelCols, 1, 6, 1)
                    . tog(GetLang("界面激活时显示"), "UIPanelShowOnActiveCon", MainSoftData.UIPanelShowOnActive)
                    . cmb(GetLang("自定义面板"), "UIPanelCustomFoldCon", uiFoldNames, 1)
                    . row(GetLang("自定义界面"), '<StackPanel Orientation="Horizontal"><Button Name="BtnEditUIPanelCustom" Content="' GetLang("界面编辑") '" HorizontalAlignment="Left" Padding="10,0"/><Button Name="BtnResetUIPanelCustom" Content="' GetLang("恢复自动") '" HorizontalAlignment="Left" Padding="10,0" Margin="8,0,0,0"/></StackPanel>'), "0", "", "uipanel")
            )
        )

        ; ---------- 页：主题 ----------
        tcMap := (MainSoftData.HasProp("ThemeColors") && IsObject(MainSoftData.ThemeColors)) ? MainSoftData.ThemeColors : AppThemeUtil.NewColorMapFromPreset(AppThemeUtil.GetDefaultPreset())
        themeNames := []
        for tp in AppThemeUtil.Presets
            themeNames.Push(GetLang(tp.Name))
        themeNames.Push(GetLang("自定义"))
        themeIdx := AppThemeUtil.Presets.Length
        for ti, tp in AppThemeUtil.Presets {
            if (tp.Key == MainSoftData.AppTheme) {
                themeIdx := ti - 1
                break
            }
        }
        paletteBody := '<UniformGrid Columns="3">'
        for slot, cd in AppThemeUtil.ColorDefs {
            col := tcMap.Has(cd.Key) ? tcMap[cd.Key] : "#FF000000"
            paletteBody .= '<Grid Margin="0,4,16,4"><Grid.ColumnDefinitions><ColumnDefinition Width="' labelWidth '"/><ColumnDefinition Width="*"/><ColumnDefinition Width="35"/></Grid.ColumnDefinitions><TextBlock Text="' this._XmlEsc(GetLang("颜色") " " slot) '" VerticalAlignment="Center" FontSize="13"/><TextBox Grid.Column="1" Name="PaletteText_' slot '" Text="' this._XmlEsc(col) '" IsReadOnly="True" Padding="7,0"/><Border Grid.Column="2" Name="PalettePreview_' slot '" Width="28" Height="28" CornerRadius="6" HorizontalAlignment="Right" Background="' this._XmlEsc(col) '" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" Cursor="Arrow"/></Grid>'
        }
        paletteBody .= '</UniformGrid>'
        themePage := page("appearance"
            , twoCol(
                card(GetLang("主题方案"), "&#xE790;", cmb(GetLang("选择主题"), "ThemePresetCon", themeNames, themeIdx, true)
                    . '<TextBlock Text="' this._XmlEsc(GetLang("选「自定义」后色块可点击取色；颜色与字体随「应用并保存」落盘。")) '" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,8,0,0" TextWrapping="Wrap"/>', "0", "", "theme")
                , card(GetLang("字体"), "&#xE8D2;", appearanceBody, "0", "", "font")
            )
            . card(GetLang("主题颜色"), "&#xE790;", paletteBody, "0,18,0,0", "", "palette")
        )

        ; ---------- 页：AI 助手 ----------
        aiProviderNames := []
        for ap in AiAssist.Providers
            aiProviderNames.Push(GetLang(ap["name"]))
        aiAccessNames := []
        for al in AiAssist.AccessLabels
            aiAccessNames.Push(GetLang(al))
        aiApprovalNames := []
        for al in AiAssist.ApprovalLabels
            aiApprovalNames.Push(GetLang(al))
        aiModelXaml := ""
        for mi in AiAssist.ModelListArr()
            aiModelXaml .= '<ComboBoxItem Content="' this._XmlEsc(String(mi)) '"/>'
        aiPage := page("ai"
            , twoCol(
                card(GetLang("大模型"), "&#xE99A;", cmb(GetLang("模型商"), "AiProviderCon", aiProviderNames, AiAssist.ProviderIndex(MainSoftData.AiProvider) - 1, true)
                    . row(GetLang("API URL"), '<TextBox Name="AiBaseUrlCon" Text="' this._XmlEsc(MainSoftData.AiApiBaseUrl) '" Height="33" MinHeight="33" Padding="6,0,18,0" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>')
                    . row(GetLang("API Key"), '<PasswordBox Name="AiApiKeyCon" Password="' this._XmlEsc(MainSoftData.AiApiKey) '" Height="33" MinHeight="33" Padding="6,0,18,0" VerticalContentAlignment="Center" FontSize="12" Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>')
                    . row(GetLang("模型列表"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox Name="AiModelCon" IsEditable="True" Text="' this._XmlEsc(MainSoftData.AiModel) '" Height="33" MinHeight="33" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1">' aiModelXaml '</ComboBox><Button Grid.Column="1" Name="BtnAiRefreshModels" Content="&#xE72C;" FontFamily="' iconFont '" FontSize="14" Width="33" Height="33" MinWidth="33" MinHeight="33" Padding="0" Margin="8,0,0,0" ToolTip="' this._XmlEsc(GetLang("刷新")) '"/></Grid>'), "0", "", "aiModel")
                , card(GetLang("权限"), "&#xE72E;", cmb(GetLang("写入权限"), "AiAccessCon", aiAccessNames, MainSoftData.AiAccessMode - 1, true, ""
                        , ["只能读取文件和配置。", "写入仅限软件目录。", "读写不限路径，可执行命令和脚本。"], 132)
                    . cmb(GetLang("指令审批"), "AiApprovalCon", aiApprovalNames, MainSoftData.AiApprovalMode - 1, true), "0", "", "aiPerm")
            )
        )

        ; ---------- 组装：左侧导航 + 右侧页面 ----------
        navDefs := [["behavior", "&#xE713;", "系统"], ["macro", "&#xE768;", "宏"], ["record", "&#xE7C8;", "指令录制"], ["trigger", "&#xE8D4;", "界面"], ["hotkey", "&#xE765;", "快捷键"], ["appearance", "&#xE790;", "主题"], ["ai", "&#xE99A;", "AI 助手"], ["diagnostic", "&#xE81C;", "日志"]]
        navSep := '<Border Height="1" Background="{DynamicResource OutlineStroke}"/>'
        navAll := navSep
        for ni, nd in navDefs {
            if (ni > 1)
                navAll .= navSep
            navAll .= navItem(nd[1], nd[2], GetLang(nd[3]), ni == 1)
        }
        navAll .= navSep
        pagesAll := behaviorPage . macroPage . recordPage . triggerPage . hotkeyPage . themePage . aiPage . logPage
        Add('<Grid ' ns '><Grid.Resources>' navStyle . switchStyle . fieldStyles '</Grid.Resources>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="153"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Border BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="0,0,1,0" SnapsToDevicePixels="True"><StackPanel>' navAll . '</StackPanel></Border>'
            . '<ScrollViewer Grid.Column="1" Margin="5,0,0,0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><Grid>' pagesAll . '</Grid></ScrollViewer>'
            . '</Grid>')

        ; ---- 事件 ----
        this._Bind("EditHoldFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "HoldFloat"))
        this._Bind("EditPreIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "PreIntervalFloat"))
        this._Bind("EditIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "IntervalFloat"))
        this._Bind("EditCoordXFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordXFloat"))
        this._Bind("EditCoordYFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordYFloat"))
        this._Bind("EditMutiThreadNum", "LostFocus", ObjBindMethod(this, "OnIntEdit", "MutiThreadNum"))
        this._Bind("EditMutiThreadNum", "SelectionChanged", ObjBindMethod(this, "OnIntEdit", "MutiThreadNum"))
        this._Bind("CmbFont", "SelectionChanged", ObjBindMethod(this, "OnComboText", "FontType"))
        this._Bind("ChkBootStart", "Click", OnBootStartChanged)
        this._Bind("ChkAdminStart", "Click", OnAdminStartChanged)
        this._Bind("ChkForeground", "Click", ObjBindMethod(this, "OnCheckEdit", "CheckForeground"))
        this._Bind("ChkAutoLoosen", "Click", ObjBindMethod(this, "OnCheckEdit", "AutoLoosenModifier"))
        this._Bind("ChkContinuous", "Click", ObjBindMethod(this, "OnCheckEdit", "ContinuousTrigger"))
        this._Bind("ChkNoVariable", "Click", ObjBindMethod(this, "OnCheckEdit", "NoVariableTip"))
        this._Bind("ChkModalSubGui", "Click", ObjBindMethod(this, "OnCheckEdit", "IsModalSubGui"))
        this._Bind("ChkDataReport", "Click", ObjBindMethod(this, "OnCheckEdit", "IsDataReport"))
        this._Bind("CmbLang", "SelectionChanged", ObjBindMethod(this, "OnComboText", "Lang"))
        this._Bind("CmbPreferredEditor", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "PreferredMacroEditor"))
        this._Bind("CmbScreenShot", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "ScreenShotType"))
        this._Bind("CmbOCRType", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "OCRTypeValue"))
        this._Bind("CmbExcelBackend", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "ExcelBackend"))
        this._Bind("CmbSearchImage", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "SearchImageType"))
        this._Bind("ChkSearchImageAdaptive", "Click", ObjBindMethod(this, "OnCheckEdit", "SearchImageAdaptive"))
        this._Bind("CmbTriggerJoyType", "SelectionChanged", ObjBindMethod(this, "OnTriggerJoyTypeChanged"))
        this._Bind("CmbJoyType", "SelectionChanged", ObjBindMethod(this, "OnComboText", "JoyType"))
        this._Bind("ChkJoyLtRtAsButton", "Click", ObjBindMethod(this, "OnCheckEdit", "JoyLtRtAsButton"))
        this._Bind("CmbKeyDownDown", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "KeyDownDownType"))
        this._Bind("CmbRemarkAuto", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "RemarkAutoType"))
        this._Bind("CmbMacroStop", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "MacroStopType"))
        this._Bind("BtnStartTipBrowse", "Click", ObjBindMethod(this, "OnSettingAudioBrowse", "StartTipAudio"))
        this._Bind("BtnEndTipBrowse", "Click", ObjBindMethod(this, "OnSettingAudioBrowse", "EndTipAudio"))
        this._Bind("BtnStopTipBrowse", "Click", ObjBindMethod(this, "OnSettingAudioBrowse", "StopTipAudio"))
        this._Bind("StartTipAudioCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "StartTipAudio"))
        this._Bind("EndTipAudioCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "EndTipAudio"))
        this._Bind("StopTipAudioCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "StopTipAudio"))
        ; §10 显示页签勾选
        for sym in ["Normal", "String", "Menu", "UI", "Voice", "Timing", "SubMacro", "Replace", "Network"]
            this._Bind("TabVisible_" sym, "Click", ObjBindMethod(this, "OnTabVisibleCheck", sym))
        ; ---- 设置中心：左侧导航 ----
        for pid in ["behavior", "macro", "record", "trigger", "hotkey", "appearance", "ai", "diagnostic"]
            this._Bind("SetNav_" pid, "Click", ObjBindMethod(this, "OnSettingNavClick", pid))

        ; ---- 设置中心：仅「日志中心」仍为独立查看窗口（非设置项）----
        this._Bind("BtnLogCenter", "Click", (*) => LogCenterGui.ShowGui())
        this._Bind("BtnEditUIPanelCustom", "Click", (*) => OpenUIPanelCustomDesigner(this))
        this._Bind("BtnResetUIPanelCustom", "Click", (*) => ResetUIPanelCustomSchema(this))

        ; ---- 设置中心：指令录制 ----
        this._Bind("ShowBorderCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordShowBorder"))
        this._Bind("HoldMutiCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordHoldMuti"))
        this._Bind("AutoLoosenCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordAutoLoosen"))
        this._Bind("KeyboardTogCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordKeyboard"))
        this._Bind("MouseTogCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordMouse"))
        this._Bind("MouseTrailModeCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex0", "RecordMouseTrail"))
        this._Bind("MouseTrailSpeedCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "RecordMouseTrailSpeed"))
        this._Bind("JoyTogCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordJoy"))
        this._Bind("JoyIntervalCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "RecordJoyInterval"))

        ; ---- 设置中心：快捷键（录入经既有 MyEditHotkeyGui 链路）----
        for hg in hotkeyGroups
            for hd in hg.defs
                this._Bind("BtnEdit_" hd.f, "Click", ObjBindMethod(this, "OnSettingEditHotkey", hd.f, hd.t))
        if (this.HasProp("_setHelpMap")) {
            for helpName, _ in this._setHelpMap
                this._Bind(helpName, "Click", ObjBindMethod(this, "OnSettingHelpClick", helpName))
        }

        ; ---- 设置中心：日志 ----
        for level in logLevels
            this._Bind("LogLevel_" level[1], "Click", ObjBindMethod(this, "OnLogLevelChanged", level[1]))
        this._Bind("ChkLogWarnBubble", "Click", ObjBindMethod(this, "OnCheckEdit", "LogWarnBubble"))
        this._Bind("ChkLogErrorBadge", "Click", ObjBindMethod(this, "OnCheckEdit", "LogErrorBadge"))

        ; ---- 设置中心：指令显示 ----
        this._Bind("ChkCMDTip", "Click", OnClickCMDTipToggle)
        this._Bind("CmdTipPosXCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CMDPosX"))
        this._Bind("CmdTipPosYCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CMDPosY"))
        this._Bind("CmdTipWidthCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDWidth", "CmdTipWidthVal", 80, 800))
        this._Bind("CmdTipWidthVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDWidth", "CmdTipWidthCon", 80, 800))
        this._Bind("CmdTipHeightCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDHeight", "CmdTipHeightVal", 40, 600))
        this._Bind("CmdTipHeightVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDHeight", "CmdTipHeightCon", 40, 600))
        this._Bind("CmdTipFontCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDFontSize", "CmdTipFontVal", 8, 36))
        this._Bind("CmdTipFontVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDFontSize", "CmdTipFontCon", 8, 36))
        this._Bind("CmdTipAlphaCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDTransparency", "CmdTipAlphaVal", 0, 100))
        this._Bind("CmdTipAlphaVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDTransparency", "CmdTipAlphaCon", 0, 100))
        this._Bind("CmdTipLogFileCon", "Click", ObjBindMethod(this, "OnCheckEdit", "CMDLogToFile"))
        this._Bind("BtnCmdTipBrowse", "Click", ObjBindMethod(this, "OnSettingLogBrowse"))
        this._Bind("CmdTipLogPathCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "CMDLogFilePath"))
        this._Bind("CmdTipAutoClearCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex0", "CMDLogAutoClear"))

        ; ---- 设置中心：界面 ----
        this._Bind("WheelFixedPosCon", "Click", ObjBindMethod(this, "OnCheckEdit", "FixedMenuWheel"))
        this._Bind("WheelShowTooltipCon", "Click", ObjBindMethod(this, "OnCheckEdit", "MenuWheelShowTooltip"))
        this._Bind("WheelSelectModeCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "MenuWheelSelectMode"))
        this._Bind("WheelScaleCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "MenuWheelScale", "WheelScaleVal", 50, 200))
        this._Bind("UIPanelBtnWidthCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelBtnWidth", "UIPanelBtnWidthVal", 40, 250))
        this._Bind("UIPanelBtnHeightCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelBtnHeight", "UIPanelBtnHeightVal", 20, 60))
        this._Bind("UIPanelFontSizeCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelFontSize", "UIPanelFontSizeVal", 8, 24))
        this._Bind("UIPanelColsCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelCols", "UIPanelColsVal", 1, 6))
        this._Bind("UIPanelShowOnActiveCon", "Click", ObjBindMethod(this, "OnCheckEdit", "UIPanelShowOnActive"))
        this._Bind("CountDownFontCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CountDownFontSize", "CountDownFontVal", 8, 72))
        this._Bind("CountDownAlphaCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CountDownAlpha", "CountDownAlphaVal", 0, 100))
        this._Bind("CountDownStyleCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "CountDownStyle"))
        this._Bind("CountDownPadCon", "Click", ObjBindMethod(this, "OnCheckEdit", "CountDownPadZero"))

        for spec in [["MenuWheelScale", "WheelScaleCon", "WheelScaleVal", 50, 200],
            ["UIPanelBtnWidth", "UIPanelBtnWidthCon", "UIPanelBtnWidthVal", 40, 250],
            ["UIPanelBtnHeight", "UIPanelBtnHeightCon", "UIPanelBtnHeightVal", 20, 60],
            ["UIPanelFontSize", "UIPanelFontSizeCon", "UIPanelFontSizeVal", 8, 24],
            ["UIPanelCols", "UIPanelColsCon", "UIPanelColsVal", 1, 6],
            ["CountDownFontSize", "CountDownFontCon", "CountDownFontVal", 8, 72],
            ["CountDownAlpha", "CountDownAlphaCon", "CountDownAlphaVal", 0, 100]]
            this._Bind(spec[3], "LostFocus", ObjBindMethod(this, "OnSettingNumText", spec[1], spec[2], spec[4], spec[5]))

        ; ---- 设置中心：主题字体大小 / AI 助手 ----
        this._Bind("ThemeFontSizeCon", "ValueChanged", ObjBindMethod(this, "OnSettingFontSize"))
        this._Bind("ThemeFontSizeVal", "LostFocus", ObjBindMethod(this, "OnSettingFontSizeText"))
        this._Bind("AiProviderCon", "SelectionChanged", ObjBindMethod(this, "OnAiProviderChanged"))
        this._Bind("AiBaseUrlCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "AiApiBaseUrl"))
        this._Bind("AiApiKeyCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "AiApiKey"))
        this._Bind("AiModelCon", "LostFocus", ObjBindMethod(this, "OnAiModelChanged"))
        this._Bind("AiAccessCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "AiAccessMode"))
        this._Bind("AiApprovalCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "AiApprovalMode"))
        this._Bind("BtnAiRefreshModels", "Click", ObjBindMethod(this, "OnAiRefreshModels"))

        ; ---- 设置中心：主题（预设 + 颜色 1~14）----
        this._Bind("ThemePresetCon", "SelectionChanged", ObjBindMethod(this, "OnSettingThemeChanged"))
        loop AppThemeUtil.ColorDefs.Length
            this._Bind("PalettePreview_" A_Index, "MouseLeftButtonDown", ObjBindMethod(this, "OnSettingPickColor", A_Index))
        this._RenderSettingPalette()

        UIControls.CMDTip := CtrlAdapter("ChkCMDTip", this.ui, "IsChecked")
        this.ui.Update("ChkCMDTip", "IsChecked", MySoftData.CMDTip ? "True" : "False")
        this._InitSettingModuleSpecs()
        this._BindSettingModuleResets()
        this._RefreshAllSettingModules()
    }
