
    ; ============ 工具页 ============
    BuildToolTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Tool 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Tool")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)

        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        iconFont := 'Segoe Fluent Icons, Segoe MDL2 Assets'
        field(label, glyph, name, value) {
            return '<Grid Margin="0,0,16,10"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto" MinWidth="116" SharedSizeGroup="MonitorLabel"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="' glyph '" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" Margin="0,0,6,0" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(label) '：" VerticalAlignment="Center"/></StackPanel>'
                . '<TextBox Grid.Column="1" Name="' name '" Text="' this._XmlEsc(value) '" Height="26" MinHeight="26" Padding="6,0" VerticalContentAlignment="Center" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/></Grid>'
        }
        card(title, glyph, body, margin := "0", headerRight := "") {
            glyphXaml := glyph == "" ? "" : '<TextBlock Text="' glyph '" FontFamily="' iconFont '" Foreground="{DynamicResource TitleBarForeground}" FontSize="13" Margin="0,0,7,0" VerticalAlignment="Center"/>'
            return '<Border Margin="' margin '" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" TextElement.Foreground="{DynamicResource TextMain}" BorderThickness="1.25" CornerRadius="7" Padding="0">'
                . '<Grid><Grid.RowDefinitions><RowDefinition Height="38"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
                . '<Border Background="{DynamicResource TitleBarColor}" CornerRadius="7,7,0,0" Padding="12,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Orientation="Horizontal" VerticalAlignment="Center">' glyphXaml '<TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" Foreground="{DynamicResource TitleBarForeground}" VerticalAlignment="Center"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">' headerRight '</StackPanel></Grid></Border>'
                . '<Grid Grid.Row="1" Margin="14,12,14,14">' body '</Grid></Grid></Border>'
        }
        openBtn(name, glyph, text, primary := false, margin := "0") {
            bg := primary ? '{DynamicResource ActionBg}' : '{DynamicResource ControlBg}'
            fg := primary ? '{DynamicResource ActionText}' : '{DynamicResource TextMain}'
            br := primary ? '{DynamicResource ActionStroke}' : '{DynamicResource ControlBorder}'
            return '<Button Name="' name '" Height="28" MinHeight="28" Padding="10,0" Margin="' margin '" Background="' bg '" Foreground="' fg '" BorderBrush="' br '" BorderThickness="1" Cursor="Hand">'
                . '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/></Grid.ColumnDefinitions><TextBlock Text="' glyph '" FontFamily="' iconFont '" VerticalAlignment="Center" Margin="0,0,6,0"/><TextBlock Grid.Column="1" Text="' this._XmlEsc(text) '" VerticalAlignment="Center"/><TextBlock Grid.Column="2" Text="↗" FontSize="8" VerticalAlignment="Top" HorizontalAlignment="Right"/></Grid></Button>'
        }
        actionRow(title, detail, hotkey, buttonXaml) {
            return '<Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" CornerRadius="5" Padding="10,7" Margin="0,0,0,8"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
                . '<StackPanel><StackPanel Orientation="Horizontal"><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold"/><TextBlock Text="' this._XmlEsc(hotkey) '" Opacity="0.65" Margin="7,0,0,0"/></StackPanel><TextBlock Text="' this._XmlEsc(detail) '" FontSize="11" Opacity="0.7" Margin="0,3,0,0"/></StackPanel>'
                . '<StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">' buttonXaml '</StackPanel></Grid></Border>'
        }
        iconBtn(name, glyph, tip, action := false) {
            bg := action ? '{DynamicResource ActionBg}' : '{DynamicResource ControlBg}'
            fg := action ? '{DynamicResource ActionText}' : '{DynamicResource TextMain}'
            br := action ? '{DynamicResource ActionStroke}' : '{DynamicResource ControlBorder}'
            return '<Button Name="' name '" Content="' glyph '" ToolTip="' this._XmlEsc(tip) '" FontFamily="' iconFont '" FontSize="12" Width="30" Height="28" MinHeight="28" Padding="0" Margin="0,0,6,0" Background="' bg '" Foreground="' fg '" BorderBrush="' br '" BorderThickness="1" Cursor="Hand"/>'
        }

        monitorBody := '<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">' openBtn("BtnOpenVarListen", "&#xE7B3;", GetLang("变量监视器"), true) '</StackPanel>'
            . '<StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,12,0,12" VerticalAlignment="Center"><TextBlock Text="&#xE962;" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" Margin="0,0,7,0" VerticalAlignment="Center"/><TextBlock Text="' GetLang("鼠标信息：") '" FontWeight="Bold" VerticalAlignment="Center"/><TextBlock Name="TxtToolCheckKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolCheckHotkey) '" Opacity="0.65" Margin="9,0,8,0" VerticalAlignment="Center"/><CheckBox Name="ChkToolCheck" Content="' GetLang("开关") '" Style="{StaticResource ToolSwitch}"/> </StackPanel>'
            . '<Grid Grid.Row="2" Grid.IsSharedSizeScope="True"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel>'
            . field("屏幕坐标", "&#xE81D;", "TxtMousePos", MainSoftData.PosStr)
            . field("窗口位置", "&#xE7B7;", "TxtWinOrigin", MainSoftData.WinOriginStr)
            . field("窗口标题", "&#xE8A5;", "TxtProcessTile", MainSoftData.ProcessTile)
            . field("窗口类", "&#xE8D7;", "TxtProcessClass", MainSoftData.ProcessClass)
            . field("句柄 Id", "&#xE71B;", "TxtProcessId", MainSoftData.ProcessId) '</StackPanel><StackPanel Grid.Column="1">'
            . field("窗口客户区坐标", "&#xE7F4;", "TxtWinPos", MainSoftData.WinPosStr)
            . field("窗口宽高", "&#xE740;", "TxtWinSize", MainSoftData.WinSizeStr)
            . field("进程名", "&#xE9D9;", "TxtProcessName", MainSoftData.ProcessName)
            . field("进程 PID", "&#xE950;", "TxtProcessPid", MainSoftData.ProcessPid)
            . field("位置颜色", "&#xE790;", "TxtColor", MainSoftData.Color) '</StackPanel></Grid></Grid>'

        auxiliaryBody := '<StackPanel><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="&#xE840;" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" Margin="0,0,7,0"/><TextBlock Text="' GetLang("窗口置顶") '" FontWeight="Bold" VerticalAlignment="Center"/><CheckBox Name="ChkAlwaysOnTop" Content="' GetLang("保持 RMT 主窗口在最前") '" Style="{StaticResource ToolSwitch}" Margin="12,0,0,0"/></StackPanel>'
            . '<StackPanel Orientation="Horizontal" Margin="0,12,0,0">' openBtn("BtnFileCheck", "&#xE8B7;", GetLang("文件校验"), true)
            . '<Button Name="BtnFileCheckHelp" Content="?" ToolTip="' GetLang("文件校验说明") '" Width="28" Height="28" MinHeight="28" Padding="0" Margin="8,0,0,0"/>'
            . openBtn("BtnVoiceExtension", "&#xE896;", GetLang("语音扩展"), true, "208,0,0,0") '</StackPanel></StackPanel>'
        recordBody := '<StackPanel>'
            . actionRow(GetLang("指令录制"), GetLang("记录鼠标与键盘操作"), FormatHotkeyDisplay(MainSoftData.ToolRecordMacroHotKey), '<CheckBox Name="ChkToolCheckRecord" Content="&#xE7C8;" ToolTip="' GetLang("开始或停止录制") '" Style="{StaticResource ToolRecordSwitch}"/>')
            . actionRow(GetLang("图片提取文本"), GetLang("从截图或本地图片识别文本"), FormatHotkeyDisplay(MainSoftData.ToolTextFilterHotKey), iconBtn("BtnTextShot", "&#xE7A8;", GetLang("截图提取文本")) iconBtn("BtnTextImage", "&#xE8B7;", GetLang("从图片提取文本")))
            . actionRow(GetLang("语音提取文本"), GetLang("打开语音识别窗口并写入输出区"), "", openBtn("BtnStt", "&#xE720;", GetLang("打开"), true)) '</StackPanel>'
        outputBody := '<TextBox Name="TxtToolText" Text="" Height="200" AcceptsReturn="True" VerticalContentAlignment="Top" TextWrapping="Wrap" Padding="8,6" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
        clearToolTextBtn := '<Button Name="BtnClearToolText" Content="&#xE74D;" ToolTip="' GetLang("清空内容") '" FontFamily="' iconFont '" Width="28" Height="26" MinHeight="26" Padding="0"/>'

    toolXaml := '<Grid ' ns ' Margin="2,2,3,10"><Grid.Resources>'
            . '<Style x:Key="ToolSwitch" TargetType="CheckBox"><Setter Property="Margin" Value="0"/><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><StackPanel Orientation="Horizontal"><Border x:Name="Track" Width="34" Height="18" CornerRadius="9" Background="{DynamicResource ControlBorder}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><Ellipse x:Name="Thumb" Width="12" Height="12" Fill="{DynamicResource ControlBg}" HorizontalAlignment="Left" Margin="2"/></Border><ContentPresenter Margin="7,0,0,0" VerticalAlignment="Center"/></StackPanel><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="{DynamicResource ActionBg}"/><Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style x:Key="ToolRecordSwitch" TargetType="CheckBox"><Setter Property="Width" Value="30"/><Setter Property="Height" Value="28"/><Setter Property="Padding" Value="0"/><Setter Property="FontFamily" Value="' iconFont '"/><Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="Background" Value="{DynamicResource ControlBg}"/><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="HorizontalContentAlignment" Value="Center"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionBg}"/><Setter Property="Foreground" Value="{DynamicResource ActionText}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
            . '</Grid.Resources><Grid.ColumnDefinitions><ColumnDefinition Width="Auto" MinWidth="420"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="14"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<StackPanel Grid.Column="0">' card(GetLang("辅助操作"), "&#xE713;", auxiliaryBody) card(GetLang("录制与提取"), "&#xE7C8;", recordBody, "0,14,0,0") '</StackPanel>'
            . '<Border Grid.Column="2">' card(GetLang("监视"), "&#xE7B3;", monitorBody) '</Border><Border Grid.Row="2" Grid.ColumnSpan="3">' card(GetLang("录制指令或提取文本内容"), "", outputBody, "0", clearToolTextBtn) '</Border></Grid>'
        Add(toolXaml)
        this.RefreshVoiceExtensionButton()

        this._Bind("BtnOpenVarListen", "Click", (*) => MyVarListenGui.ShowGui())
        this._Bind("BtnFileCheck", "Click", (*) => SelfCheckMissingFiles())
        this._Bind("BtnFileCheckHelp", "Click", OnClickFileCheckHelpBtn)
        this._Bind("BtnVoiceExtension", "Click", (*) => SttGui.DownloadVoiceExtension())
        this._Bind("ChkToolCheck", "Click", OnToolCheckHotkey)
        this._Bind("ChkAlwaysOnTop", "Click", OnToolAlwaysOnTop)
        this._Bind("ChkToolCheckRecord", "Click", OnClickToolRecordMacro.Bind(false))
        this._Bind("BtnTextShot", "Click", OnToolTextFilterScreenShot)
        this._Bind("BtnTextImage", "Click", OnToolTextFilterSelectImage)
        this._Bind("BtnStt", "Click", (*) => SttGui.ShowGui())
        this._Bind("BtnClearToolText", "Click", OnClearToolText)

        UIControls.ToolCheck := CtrlAdapter("ChkToolCheck", this.ui, "IsChecked")
        UIControls.AlwaysOnTop := CtrlAdapter("ChkAlwaysOnTop", this.ui, "IsChecked")
        UIControls.ToolCheckRecord := CtrlAdapter("ChkToolCheckRecord", this.ui, "IsChecked")
        UIControls.ToolText := CtrlAdapter("TxtToolText", this.ui, "Text")
        MainSoftData.ToolMousePosCtrl := CtrlAdapter("TxtMousePos", this.ui, "Text")
        MainSoftData.ToolMouseWinPosCtrl := CtrlAdapter("TxtWinPos", this.ui, "Text")
        MainSoftData.ToolWinOriginCtrl := CtrlAdapter("TxtWinOrigin", this.ui, "Text")
        MainSoftData.ToolProcessTileCtrl := CtrlAdapter("TxtProcessTile", this.ui, "Text")
        MainSoftData.ToolProcessNameCtrl := CtrlAdapter("TxtProcessName", this.ui, "Text")
        MainSoftData.ToolProcessClassCtrl := CtrlAdapter("TxtProcessClass", this.ui, "Text")
        MainSoftData.ToolProcessPidCtrl := CtrlAdapter("TxtProcessPid", this.ui, "Text")
        MainSoftData.ToolProcessIdCtrl := CtrlAdapter("TxtProcessId", this.ui, "Text")
        MainSoftData.ToolWinSizeCtrl := CtrlAdapter("TxtWinSize", this.ui, "Text")
        MainSoftData.ToolColorCtrl := CtrlAdapter("TxtColor", this.ui, "Text")

        this.ui.Update("ChkToolCheck", "IsChecked", MainSoftData.IsToolCheck ? "True" : "False")
        this.ui.Update("ChkToolCheckRecord", "IsChecked", MainSoftData.IsToolRecord ? "True" : "False")
        this.ui.Update("ChkAlwaysOnTop", "IsChecked", "False")
    }

    RefreshVoiceExtensionButton() {
        this.ui.Update("BtnVoiceExtension", "Visibility", SttGui.MissingVoiceExtensionFiles().Length ? "Visible" : "Collapsed")
    }
