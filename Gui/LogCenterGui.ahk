#Requires AutoHotkey v2.0

; =====================================================================
; 日志中心（C 项阶段4：统一日志 GUI）
; 独立 XAML 窗口：系统日志 / 业务日志 两 tab + 级别筛选 + 复制/清空/刷新
; 数据源：Log\System.log / Log\Business.log（与 RMTLog 同路径规则）
; 刷新：打开期间 5s 轮询文件增量
; 入口：主界面设置区「日志中心」按钮（阶段4）；托盘菜单（后续）
; =====================================================================

class LogCenterGui {
    static instances := Map()
    static _opening := false
    static _refreshTimer := 0

    __New() {
        this.ui := ""
        this.closed := true
        this._curTab := "System"        ; System / Business
        this._levelFilter := ""         ; 空=全部；debug/info/warn/error
        this._lastSysLen := 0
        this._lastBizLen := 0
        this._timerCb := ""
    }

    static ShowGui() {
        key := "main"
        if (LogCenterGui.instances.Has(key)) {
            oldInst := LogCenterGui.instances[key]
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    return  ; 已打开，不重复
            }
            LogCenterGui.instances.Delete(key)
        }

        try XAMLHost.EnsureDaemonHealthy()
        if (LogCenterGui._opening)
            return
        LogCenterGui._opening := true
        try {
            inst := LogCenterGui()
            inst._BuildAndShow()
            LogCenterGui.instances[key] := inst
        } finally {
            LogCenterGui._opening := false
        }
    }

    LogDir() {
        return (IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker)
            ? (A_ScriptDir "\..\Log") : (A_WorkingDir "\Log")
    }

    _SysPath() {
        return this.LogDir() "\System.log"
    }
    _BizPath() {
        return this.LogDir() "\Business.log"
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("日志中心")
        titleHeight := "36"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 主体 ===
        body := main.Add("Grid").Grid_Row(1).Margin("10,6,10,10")
        body.Rows("Auto", "*")
        body.Cols("*", "Auto", "Auto")

        ; 顶栏：tab 切换 + 级别筛选 + 操作按钮
        topBar := body.Add("StackPanel").Grid_Row(0).Grid_ColumnSpan(3).Orientation("Horizontal").VerticalAlignment("Center").Margin("0,0,0,6")

        tabSys := topBar.Add("RadioButton").Name("TabSys").Content(GetLang("系统日志")).IsChecked("True").VerticalAlignment("Center").Margin("0,0,16,0").GroupName("LogTab")
        tabBiz := topBar.Add("RadioButton").Name("TabBiz").Content(GetLang("业务日志")).IsChecked("False").VerticalAlignment("Center").Margin("0,0,16,0").GroupName("LogTab")

        topBar.Add("TextBlock").Text(GetLang("级别：")).VerticalAlignment("Center").Margin("8,0,4,0").Foreground("{DynamicResource TextSub}")
        lvCombo := topBar.Add("ComboBox").Name("CmbLevel").Width(90).Height(26).MinHeight(26).VerticalContentAlignment("Center").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalAlignment("Center").Margin("0,0,12,0")
        lvCombo.Add("ComboBoxItem").Content(GetLang("全部"))
        lvCombo.Add("ComboBoxItem").Content("debug")
        lvCombo.Add("ComboBoxItem").Content("info")
        lvCombo.Add("ComboBoxItem").Content("warn")
        lvCombo.Add("ComboBoxItem").Content("error")
        lvCombo.SelectedIndex("0")

        btnRefresh := topBar.Add("Button").Name("BtnRefresh").Content(GetLang("刷新")).Height(28).MinHeight(28).Padding("14,0").Margin("0,4,8,4")
        btnCopy := topBar.Add("Button").Name("BtnCopy").Content(GetLang("复制")).Height(28).MinHeight(28).Padding("14,0").Margin("0,4,8,4")
        btnClear := topBar.Add("Button").Name("BtnClear").Content(GetLang("清空")).Height(28).MinHeight(28).Padding("14,0").Margin("0,4,8,4")
        btnExport := topBar.Add("Button").Name("BtnExport").Content(GetLang("导出")).Height(28).MinHeight(28).Padding("14,0").Margin("0,4,0,4")

        ; 日志内容区
        ; 外层 Border 提供背景/边框；内层 ScrollViewer 管理滚动，滚动条固定在外层 ScrollViewer 底部/右侧
        ; （即文本框控件区域的边缘，属于控件本身、不随内容滚动）；内层 TextBox 仅承载文本、禁用内部滚动
        contentBdr := body.Add("Border").Grid_Row(1).Grid_ColumnSpan(3)
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        contentSv := contentBdr.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Auto")
        this._content := contentSv.Add("TextBox").Name("LogCon")
            .AcceptsReturn("True").TextWrapping("NoWrap").IsReadOnly("True")
            .VerticalContentAlignment("Top").HorizontalAlignment("Left").VerticalAlignment("Top")
            .FontFamily("Consolas").FontSize("11")
            .Background("Transparent").Foreground("{DynamicResource InputText}")
            .BorderThickness("0").Padding("4,4,4,4")
            .ScrollViewer_VerticalScrollBarVisibility("Disabled")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" Width="760" Height="480"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("TabSys", "Click", ObjBindMethod(this, "OnTabSys"))
        this.ui.OnEvent("TabBiz", "Click", ObjBindMethod(this, "OnTabBiz"))
        this.ui.OnEvent("CmbLevel", "SelectionChanged", ObjBindMethod(this, "OnLevelChanged"))
        this.ui.OnEvent("BtnRefresh", "Click", ObjBindMethod(this, "OnRefresh"))
        this.ui.OnEvent("BtnCopy", "Click", ObjBindMethod(this, "OnCopy"))
        this.ui.OnEvent("BtnClear", "Click", ObjBindMethod(this, "OnClear"))
        this.ui.OnEvent("BtnExport", "Click", ObjBindMethod(this, "OnExport"))

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd) {
            this.closed := true
            return
        }

        ; 初次加载 + 启动轮询（绑定实例的闭包，确保 this 正确）
        this._Reload(true)   ; 全量显示
        this._timerCb := () => this._PollTick()
        if (!LogCenterGui._refreshTimer)
            LogCenterGui._refreshTimer := SetTimer(this._timerCb, 1000)
        ; 写入即通知：主进程日志（System/Business）一写入就立即刷新
        ; （Worker 进程的业务日志无法事件驱动，靠 1s 轮询兜底）
        this._notifyCb := () => this._OnLogWritten()
        RMTLogSetNotify(this._notifyCb)
    }

    ; 写入即通知回调：先强制落盘（日志还在内存缓冲），再增量追加
    _OnLogWritten() {
        if (this.closed || !IsObject(this.ui))
            return
        try FlushRMTLogAsync()
        this._Reload(false)
    }

    ; ============ 事件 ============

    OnWindowLoad(state, ctrl, event) {
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this.ui := ""
        this.closed := true
        LogCenterGui.instances.Delete("main")
        ; 注销写入通知 + 停轮询
        if (this.HasOwnProp("_notifyCb") && this._notifyCb)
            RMTLogClearNotify()
        if (this.HasOwnProp("_timerCb") && this._timerCb) {
            SetTimer(this._timerCb, 0)
            LogCenterGui._refreshTimer := 0   ; 复位，下次打开重新起轮询
        }
    }

    OnCloseClick(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }

    OnTabSys(state, ctrl, event) {
        this._curTab := "System"
        this._Reload(true)   ; 全量替换
    }

    OnTabBiz(state, ctrl, event) {
        this._curTab := "Business"
        this._Reload(true)   ; 全量替换
    }

    OnLevelChanged(state, ctrl, event) {
        idx := Integer(this.ui.Query("CmbLevel>SelectedIndex"))
        this._levelFilter := idx <= 0 ? "" : ["debug", "info", "warn", "error"][idx]
        this._Reload(true)   ; 筛选变化：全量替换
    }

    OnRefresh(state, ctrl, event) {
        this._Reload(true)   ; 手动刷新：全量替换
    }

    OnCopy(state, ctrl, event) {
        txt := this.ui.Query("LogCon")
        if (txt != "") {
            A_Clipboard := txt
            try ToolTip(GetLang("已复制"), , , 2)
        }
    }

    OnClear(state, ctrl, event) {
        ; 清空当前 tab 对应的日志文件（确认后）
        result := MsgBox(GetLang("确定清空当前日志文件？"), GetLang("日志中心"), "YesNo")
        if (result == "No")
            return
        path := this._curTab == "System" ? this._SysPath() : this._BizPath()
        try FileDelete(path)
        this._lastSysLen := 0
        this._lastBizLen := 0
        this._Reload()
    }

    OnExport(state, ctrl, event) {
        txt := this.ui.Query("LogCon")
        if (txt == "")
            return
        defName := this._curTab == "System" ? "System.log" : "Business.log"
        savePath := FileSelect("S", defName, GetLang("导出日志"), "日志文件 (*.log)")
        if (savePath != "") {
            try FileAppend(txt, savePath, "UTF-8")
            try ToolTip(GetLang("已导出"), , , 2)
        }
    }

    ; ============ 加载 ============

    ; 轮询回调（实例绑定闭包触发）：增量追加新日志
    _PollTick() {
        if (this.closed || !IsObject(this.ui))
            return
        this._Reload(false)
    }

    ; full=true 切换 tab/筛选/初次：全量替换显示当前 tab 内容
    ; full=false 轮询刷新：仅追加文件增量（不动已显示内容）
    _Reload(full := false) {
        if (this.closed || !IsObject(this.ui))
            return
        path := this._curTab == "System" ? this._SysPath() : this._BizPath()
        if (!FileExist(path)) {
            this.ui.Update("LogCon", "Text", "")
            return
        }
        try {
            content := FileRead(path, "UTF-8")
        } catch {
            content := ""
        }
        rawLen := StrLen(content)

        if (full) {
            ; 全量替换（切换/筛选/初次）
            shown := this._Filter(content)
            this.ui.Update("LogCon", "Text", shown)
        } else {
            ; 增量追加（轮询/写入通知）：只显示自上次记录以来新增的部分
            lastLen := this._curTab == "System" ? this._lastSysLen : this._lastBizLen
            if (rawLen > lastLen) {
                added := SubStr(content, lastLen + 1)
                added := this._Filter(added)
                if (added != "") {
                    cur := this.ui.Query("LogCon")
                    this.ui.Update("LogCon", "Text", cur . added)
                }
            } else if (rawLen < lastLen) {
                ; 文件被轮转 .old / 清空重建：上次长度失效，全量替换（否则新内容永不显示）
                shown := this._Filter(content)
                this.ui.Update("LogCon", "Text", shown)
            }
        }
        if (this._curTab == "System")
            this._lastSysLen := rawLen
        else
            this._lastBizLen := rawLen
    }

    _Filter(content) {
        if (this._levelFilter == "")
            return content
        filtered := ""
        for line in StrSplit(content, "`n", "`r") {
            if (InStr(line, "[" this._levelFilter "]"))
                filtered .= line "`n"
        }
        return filtered
    }
}
