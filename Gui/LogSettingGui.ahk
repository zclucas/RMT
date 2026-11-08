#Requires AutoHotkey v2.0

; =====================================================================
; 日志与错误设置（C 项阶段5）
; 独立窗口：日志级别 / warn 气泡开关 / error 错误中心开关
; 入口：主界面设置页「日志与错误」按钮
; 保存：即时写 MainSoftData + LogUtil global + CfgWrite 持久化
; =====================================================================

class LogSettingGui {
    static instances := Map()
    static _opening := false

    __New() {
        this.ui := ""
        this.closed := true
    }

    static ShowGui() {
        key := "main"
        if (LogSettingGui.instances.Has(key)) {
            oldInst := LogSettingGui.instances[key]
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    return  ; 已打开，不重复
            }
            LogSettingGui.instances.Delete(key)
        }

        try XAMLHost.EnsureDaemonHealthy()
        if (LogSettingGui._opening)
            return
        LogSettingGui._opening := true
        try {
            inst := LogSettingGui()
            inst._BuildAndShow()
            LogSettingGui.instances[key] := inst
        } finally {
            LogSettingGui._opening := false
        }
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        this.closed := false
        title := GetLang("日志与错误")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 主体 ===
        body := main.Add("Grid").Grid_Row(1).Margin("20,16,20,16")
        body.Rows("40", "40", "40", "*")

        ; 行0：日志级别
        row0 := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").VerticalAlignment("Center")
        row0.Add("TextBlock").Text(GetLang("日志级别：")).Width(110).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        labels := ["调试", "信息", "警告", "错误"]
        for i, level in RMTLogLevelKeys()
            row0.Add("CheckBox").Name("LogLevel_" level).Content(GetLang(labels[i])).Margin("4,0,6,0").VerticalAlignment("Center")
                .ToolTip(GetLang("可同时勾选多个级别。系统日志只写入勾选的级别，全部取消则暂停写入。"))

        ; 行1：warn 气泡
        row1 := body.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").VerticalAlignment("Center")
        row1.Add("TextBlock").Text(GetLang("warn 气泡：")).Width(110).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        chkBubble := row1.Add("CheckBox").Name("ChkLogWarnBubble").VerticalAlignment("Center").Margin("4,0,0,0")
            .ToolTip(GetLang("开启后：warn 级错误在托盘显示气泡通知（2 秒自动消失），不打断操作。")
                . "`n" GetLang("关闭后：warn 只写入 System.log，不弹气泡。"))

        ; 行2：error 错误中心
        row2 := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").VerticalAlignment("Center")
        row2.Add("TextBlock").Text(GetLang("错误中心：")).Width(110).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        chkBadge := row2.Add("CheckBox").Name("ChkLogErrorBadge").VerticalAlignment("Center").Margin("4,0,0,0")
            .ToolTip(GetLang("开启后：error 级错误在错误中心聚合显示（可复制/清空）。")
                . "`n" GetLang("关闭后：error 只写入 System.log，不打开错误中心。"))

        ; 行3：确定
        btnRow := body.Add("StackPanel").Grid_Row(3).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("14,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="360" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        for level in RMTLogLevelKeys()
            this.ui.OnEvent("LogLevel_" level, "Click", ObjBindMethod(this, "OnLevelChanged", level))
        this.ui.OnEvent("ChkLogWarnBubble", "Click", ObjBindMethod(this, "OnBubbleToggle"))
        this.ui.OnEvent("ChkLogErrorBadge", "Click", ObjBindMethod(this, "OnBadgeToggle"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnOkClick"))

        this._ApplyCurrent()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    _ApplyCurrent() {
        global RMTLogSysMinLevel
        selected := MainSoftData.HasOwnProp("SysLogMinLevel") ? MainSoftData.SysLogMinLevel : RMTLogSysMinLevel
        for level in RMTLogLevelKeys()
            this.ui.Update("LogLevel_" level, "IsChecked", RMTLogLevelEnabled(level, selected) ? "True" : "False")
        bubble := MainSoftData.HasOwnProp("LogWarnBubble") ? MainSoftData.LogWarnBubble : true
        badge := MainSoftData.HasOwnProp("LogErrorBadge") ? MainSoftData.LogErrorBadge : true
        this.ui.Update("ChkLogWarnBubble", "IsChecked", bubble ? "True" : "False")
        this.ui.Update("ChkLogErrorBadge", "IsChecked", badge ? "True" : "False")
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.ui := ""
        this.closed := true
        LogSettingGui.instances.Delete("main")
    }

    OnCloseClick(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }

    ; 日志级别：即时同步 LogUtil global + 持久化
    OnLevelChanged(level, state, ctrl, event) {
        global RMTLogSysMinLevel
        checked := this.ui.Query(ctrl) == "True"
        selected := RMTLogToggleLevel(MainSoftData.SysLogMinLevel, level, checked)
        MainSoftData.SysLogMinLevel := selected
        RMTLogSysMinLevel := selected
        CfgWrite(selected, SettingFile, SettingSection, "SysLogLevels")
    }

    ; warn 气泡开关
    OnBubbleToggle(state, ctrl, event) {
        MainSoftData.LogWarnBubble := this.ui.Query("ChkLogWarnBubble") == "True"
        CfgWrite(MainSoftData.LogWarnBubble, SettingFile, SettingSection, "LogWarnBubble")
    }

    ; error 错误中心开关
    OnBadgeToggle(state, ctrl, event) {
        MainSoftData.LogErrorBadge := this.ui.Query("ChkLogErrorBadge") == "True"
        CfgWrite(MainSoftData.LogErrorBadge, SettingFile, SettingSection, "LogErrorBadge")
    }

    ; 业务日志开关（同步 LogUtil global + 持久化）
    OnOkClick(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }
}
