global RMT_ThemeFontSizeMin := 15
global RMT_ThemeFontSizeMax := 20

; 主题资源文件（XAML Resource_* / Window_DWM / 字体）路径
GetThemesPath() {
    if (IsSet(ThemesPath) && ThemesPath != "")
        return ThemesPath
    return A_WorkingDir "\Setting\themes.toml"
}

; persist=true 时写入 MainSettings（权威）并同步 themes.toml
ApplyUserFontSize(fs, persist := true) {
    global XAML_FontSizeDelta, XAML_FontSizeBase, XAML_FontSizeDefault
    baseFs := IsSet(XAML_FontSizeBase) ? XAML_FontSizeBase : 15
    defFs := IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15
    if (!IsNumber(fs))
        fs := defFs
    fs := Max(RMT_ThemeFontSizeMin, Min(RMT_ThemeFontSizeMax, Round(Number(fs))))
    MainSoftData.FontSize := fs
    XAML_FontSizeDelta := fs - baseFs
    if (persist) {
        try CfgWrite(fs, SettingFile, SettingSection, "FontSize")
        try CfgWrite(fs, GetThemesPath(), MainSoftData.Theme, "FontSize")
    }
    return fs
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
    CfgWrite("#FFEBEBEB", iniPath, "RMT_Light", "Resource_TitleBarColor")
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
