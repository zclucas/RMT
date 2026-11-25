; 百分比档位仅改变界面整体缩放，设计字号保持不变。
global RMT_UiScalePresets := [80, 90, 100, 110, 125, 150]

NormalizeUiScale(value) {
    if (!IsNumber(value))
        return 100
    value := Number(value)
    if (value <= RMT_UiScalePresets[1])
        return RMT_UiScalePresets[1]
    if (value >= RMT_UiScalePresets[-1])
        return RMT_UiScalePresets[-1]
    nearest := 100
    for percent in RMT_UiScalePresets {
        if (Abs(percent - value) < Abs(nearest - value))
            nearest := percent
    }
    return nearest
}

UiScaleIndex(value) {
    value := NormalizeUiScale(value)
    for i, percent in RMT_UiScalePresets {
        if (percent == value)
            return i
    }
    return 3
}

UiScaleLabels() {
    labels := []
    for percent in RMT_UiScalePresets
        labels.Push(percent "%")
    return labels
}

; 刻度滑块：一条横线 + 六档短线刻度 + 选中档圆形滑块，下方标「小 / 默认 / 大」。
; 用 RadioButton 承载刻度：点击即切档，且程序同步 IsChecked 不会触发 Click，
; 避免异步回传把旧档位再写回控件。
UiScaleSelectorXaml(name, value, width := 300, groupId := "", showToolTips := true) {
    percent := NormalizeUiScale(value)
    ; WPF 的 GroupName 按线程全局注册，同名组会在多个窗口实例间互相取消选中；
    ; 主题窗口可能有多个实例，因此用唯一组名隔离。
    group := (groupId == "") ? name : name "_" groupId
    cell := Round(width / RMT_UiScalePresets.Length, 1)
    half := Round(cell / 2, 1)
    labels := Map(1, GetLang("小"), 3, GetLang("默认"), RMT_UiScalePresets.Length, GetLang("大"))
    xaml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Orientation="Horizontal">'
        . '<Grid Name="' name '" Width="' width '" VerticalAlignment="Center">'
        . '<Grid.Resources><Style x:Key="RmtUiScaleTick" TargetType="RadioButton">'
        . '<Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>'
        . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">'
        . '<Border x:Name="Hit" Background="Transparent">'
        . '<Grid Height="18">'
        . '<Border x:Name="Tick" Width="1" Height="5" Background="{DynamicResource ControlBorder}" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
        . '<Border x:Name="Thumb" Width="9" Height="15" CornerRadius="4.5" Background="{DynamicResource TextMain}" BorderBrush="{DynamicResource BgColor}" BorderThickness="1.5" Visibility="Collapsed" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
        . '</Grid></Border>'
        . '<ControlTemplate.Triggers>'
        . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Tick" Property="Background" Value="{DynamicResource Accent}"/></Trigger>'
        . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="Thumb" Property="Visibility" Value="Visible"/><Setter TargetName="Tick" Property="Background" Value="{DynamicResource Accent}"/><Setter TargetName="Tick" Property="Height" Value="7"/></Trigger>'
        . '<Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Tick" Property="Background" Value="{DynamicResource Accent}"/></Trigger>'
        . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Grid.Resources>'
        . '<Grid.ColumnDefinitions>'
    loop RMT_UiScalePresets.Length
        xaml .= '<ColumnDefinition Width="*"/>'
    xaml .= '</Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="18"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
        . '<Border Grid.Row="0" Grid.ColumnSpan="' RMT_UiScalePresets.Length '" Height="1" Margin="' half ',0,' half ',0" VerticalAlignment="Center" Background="{DynamicResource ControlBorder}"/>'
    for i, preset in RMT_UiScalePresets {
        xaml .= '<RadioButton Grid.Row="0" Grid.Column="' (i - 1) '" Name="' name '_' preset '" GroupName="' group
            . '" Style="{StaticResource RmtUiScaleTick}" IsChecked="' (preset == percent ? "True" : "False")
            . '" AutomationProperties.Name="' preset '%"' (showToolTips ? ' ToolTip="' preset '%"' : '') '/>'
        if labels.Has(i)
            xaml .= '<TextBlock Grid.Row="1" Grid.Column="' (i - 1) '" Text="' labels[i] '" FontSize="11" HorizontalAlignment="Center" Margin="0,3,0,0" Foreground="{DynamicResource TextSub}"/>'
    }
    xaml .= '</Grid><TextBlock Name="' name 'Val" Text="' percent '%" MinWidth="42" Margin="10,0,0,0" VerticalAlignment="Center" FontSize="12" Foreground="{DynamicResource TextMain}"/></StackPanel>'
    return xaml
}

SyncUiScaleSelector(ui, name, value) {
    percent := NormalizeUiScale(value)
    ui.Update(name '_' percent, "IsChecked", "True")
    ui.Update(name "Val", "Text", percent "%")
}

; 旧字号只参与一次迁移；新配置存在时绝不重复换算。
UiScaleFromLegacyFontSize(value) {
    return NormalizeUiScale(IsNumber(value) ? Max(15, Min(20, Number(value))) / 15 * 100 : 100)
}

; 主题资源文件（XAML Resource_* / Window_DWM / 字体）路径
GetThemesPath() {
    if (IsSet(ThemesPath) && ThemesPath != "")
        return ThemesPath
    return A_WorkingDir "\Setting\themes.toml"
}

; 设置页暂存、主题窗口确定后落盘；字体与控件共用一个缩放因子。
ApplyUserUiScale(value, persist := true) {
    global XAML_FontSizeDelta, XAML_FontSizeBase
    percent := NormalizeUiScale(value)
    MainSoftData.UiScale := percent
    MainSoftData.FontSize := IsSet(XAML_FontSizeBase) ? XAML_FontSizeBase : 15
    XAML_FontSizeDelta := 0
    if (persist)
        CfgWrite(percent, SettingFile, SettingSection, "UiScale")
    return percent
}

EnsureXAMLThemesToml() {
    static done := false
    if (done)
        return
    iniPath := GetThemesPath()
    if (FileExist(iniPath)) {
        done := true
        return
    }
    ; 目录取 iniPath 自身所在目录：编译版 Worker 里 A_ScriptDir 是 Thread\，
    ; 用 A_ScriptDir "\Setting" 会在 Thread\ 下造出一个无用的 Setting 空目录
    SplitPath iniPath, , &themeDir
    if (themeDir != "" && !DirExist(themeDir))
        DirCreate(themeDir)
    CfgWrite("2,0", iniPath, "RMT_Light", "Window_DWM")
    CfgWrite("15", iniPath, "RMT_Light", "FontSize")   ; 主题字体大小（软件默认 15）
    CfgWrite("400", iniPath, "RMT_Light", "FontWeight")
    CfgWrite("1", iniPath, "RMT_Light", "FontClarity")
    CfgWrite("CornerRadius:8", iniPath, "RMT_Light", "Resource_WindowRadius")
    CfgWrite("#FFF0F0F0", iniPath, "RMT_Light", "Resource_BgColor")
    CfgWrite(AppThemeUtil.GetDefaultColor("Win_TitleBg"), iniPath, "RMT_Light", "Resource_TitleBarColor")
    CfgWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_TitleBarForeground")
    CfgWrite("#20E0E0E0", iniPath, "RMT_Light", "Resource_SidebarColor")
    CfgWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_TextMain")
    CfgWrite("#FF666666", iniPath, "RMT_Light", "Resource_TextSub")
    CfgWrite("#FFF0F0F0", iniPath, "RMT_Light", "Resource_ControlBg")
    CfgWrite("#FF999999", iniPath, "RMT_Light", "Resource_ControlBorder")
    CfgWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_InputBg")
    CfgWrite("#FFCCCCCC", iniPath, "RMT_Light", "Resource_InputStroke")
    CfgWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_InputText")
    CfgWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_EditBg")
    CfgWrite("#FFCCCCCC", iniPath, "RMT_Light", "Resource_EditStroke")
    CfgWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_EditText")
    CfgWrite("#FFE3F2FD", iniPath, "RMT_Light", "Resource_EditHoverBg")
    CfgWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_EditHoverStroke")
    CfgWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ActionBg")
    CfgWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ActionStroke")
    CfgWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_ActionText")
    CfgWrite("#FF106EBE", iniPath, "RMT_Light", "Resource_ActionHoverBg")
    CfgWrite("#FF106EBE", iniPath, "RMT_Light", "Resource_ActionHoverStroke")
    CfgWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ProgressBar")
    CfgWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_DropdownBg")
    CfgWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_Accent")
    CfgWrite("Double:8", iniPath, "RMT_Light", "Resource_ScrollBarWidth")
    CfgWrite("CornerRadius:3", iniPath, "RMT_Light", "Resource_ScrollBarRadius")
    CfgWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ScrollBarHover")

    CfgWrite("2,1", iniPath, "RMT_Dark", "Window_DWM")
    CfgWrite("15", iniPath, "RMT_Dark", "FontSize")   ; 主题字体大小（软件默认 15）
    CfgWrite("400", iniPath, "RMT_Dark", "FontWeight")
    CfgWrite("1", iniPath, "RMT_Dark", "FontClarity")
    CfgWrite("CornerRadius:8", iniPath, "RMT_Dark", "Resource_WindowRadius")
    CfgWrite("#FF1E1E1E", iniPath, "RMT_Dark", "Resource_BgColor")
    CfgWrite("#20000000", iniPath, "RMT_Dark", "Resource_SidebarColor")
    CfgWrite("#FFFFFFFF", iniPath, "RMT_Dark", "Resource_TextMain")
    CfgWrite("#FFAAAAAA", iniPath, "RMT_Dark", "Resource_TextSub")
    CfgWrite("#15252525", iniPath, "RMT_Dark", "Resource_ControlBg")
    CfgWrite("#20333333", iniPath, "RMT_Dark", "Resource_ControlBorder")
    CfgWrite("#FF252525", iniPath, "RMT_Dark", "Resource_DropdownBg")
    CfgWrite("#FF0A84FF", iniPath, "RMT_Dark", "Resource_Accent")
    CfgWrite("Double:8", iniPath, "RMT_Dark", "Resource_ScrollBarWidth")
    CfgWrite("CornerRadius:3", iniPath, "RMT_Dark", "Resource_ScrollBarRadius")
    CfgWrite("#FF0A84FF", iniPath, "RMT_Dark", "Resource_ScrollBarHover")
    done := true
}

; 字体粗细名称 → 数值（100-900），兼容旧配置里的 Normal/Bold 等名称
FontWeightToNum(w) {
    switch w {
        case "Thin", "100":
            return "100"
        case "ExtraLight", "200":
            return "200"
        case "Light", "300":
            return "300"
        case "Normal", "Regular", "400", "":
            return "400"
        case "Medium", "500":
            return "500"
        case "SemiBold", "600":
            return "600"
        case "Bold", "700":
            return "700"
        case "ExtraBold", "800":
            return "800"
        case "Black", "Heavy", "900":
            return "900"
    }
    if (IsNumber(w) && w >= 100 && w <= 900)
        return w
    return "400"
}

SetFontList() {
    fontList := []
    hdc := DllCall("user32\GetDC", "ptr", 0, "ptr")
    if (hdc) {
        callback := CallbackCreate(EnumFontFamilies)
        try DllCall("gdi32\EnumFontFamiliesW", "ptr", hdc, "ptr", 0, "ptr", callback, "ptr", 0)
        finally {
            CallbackFree(callback)
            DllCall("user32\ReleaseDC", "ptr", 0, "ptr", hdc)
        }
    }
    MainSoftData.FontList := fontList
    MainSoftData.FontType := ResolveUiFont(fontList, MainSoftData.FontType)

    EnumFontFamilies(lpelf, lpntm, FontType, lP) {
        family := StrGet(lpelf + 28, "UTF-16") ; LOGFONTW.lfFaceName
        if (family != "" && SubStr(family, 1, 1) != "@")
            fontList.Push(family)
        return 1
    }
}

ResolveUiFont(fontList, configuredFont := "") {
    installed := Map()
    installed.CaseSense := "Off"
    for family in fontList
        installed[family] := family

    configuredFont := Trim(configuredFont)
    if (installed.Has(configuredFont))
        return installed[configuredFont]

    ; 按优先级尝试中文字体及其英文名称，再尝试常见 Windows 字体。
    for family in ["微软雅黑", "Microsoft YaHei", "微软雅黑 UI", "Microsoft YaHei UI",
        "等线", "DengXian", "宋体", "SimSun", "黑体", "SimHei", "新宋体", "NSimSun",
        "微軟正黑體", "Microsoft JhengHei", "Noto Sans CJK SC", "思源黑体", "Source Han Sans SC",
        "Segoe UI", "Arial", "Tahoma", "Meiryo", "Dotum", "Consolas"] {
        if (installed.Has(family))
            return installed[family]
    }
    return "Global User Interface" ; WPF 内置复合字体，按字符选择系统字体。
}
