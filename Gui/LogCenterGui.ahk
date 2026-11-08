#Requires AutoHotkey v2.0

; =====================================================================
; 日志中心（C 项阶段4：统一日志 GUI）
; 独立 XAML 窗口：系统日志 / 业务日志 两 tab + 级别筛选 + 复制/清空/刷新
; 数据源：Log\System.log / Log\Business.log（与 RMTLog 同路径规则）
; 刷新：只读文件尾部，避免把整份日志一次性灌进界面把软件卡死
; 入口：主界面设置区「日志中心」按钮（阶段4）；托盘菜单（后续）
; =====================================================================

class LogCenterGui {
    static instances := Map()
    static _opening := false

    __New() {
        this.ui := ""
        this.closed := true
        this._curTab := "System"        ; System / Business
        this._levelFilter := ""         ; 空=全部；debug/info/warn/error
        this._filterCurrent := ""
        this._filterTail := ""
        this._filePos := -1
        this._shown := ""
        this._maxChars := 60000         ; 界面只留最近一段，整文件（可达数 MB）会堵死 WPF 和主线程
        this._busy := false
        this._pendingFull := false
        this._ready := false
        this._timerCb := ""
        this._loadCb := ""
        this._kickCb := ""
    }

    static ShowGui() {
        if (LogCenterGui._opening)
            return
        key := "main"
        oldInst := LogCenterGui.instances.Get(key, 0)
        if (IsObject(oldInst) && !oldInst.closed && IsObject(oldInst.ui))
            return

        LogCenterGui._opening := true
        try {
            try XAMLHost.EnsureDaemonHealthy()
            inst := LogCenterGui()
            inst._BuildAndShow()
            if (!inst.closed)
                LogCenterGui.instances[key] := inst
        } finally {
            LogCenterGui._opening := false
        }
    }

    LogDir() {
        return CMDLogAppDir() "\Log"
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
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

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
        contentSv := contentBdr.Add("ScrollViewer").Name("LogScroll").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Auto")
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

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)) || this.closed) {
            this.closed := true
            return
        }

        ; 先让窗口能点，再异步读日志尾部。同步灌入整文件时 SendMessage 会把主线程和日志窗口一起卡住
        this._ready := true
        this._loadCb := ObjBindMethod(this, "_InitialLoad")
        SetTimer(this._loadCb, -50)
        this._notifyCb := ObjBindMethod(this, "_OnLogWritten")
        RMTLogSetNotify(this._notifyCb)
    }

    _InitialLoad() {
        if (this.closed || !IsObject(this.ui))
            return
        this._Reload(true)
        if (this.closed || this._timerCb)
            return
        this._timerCb := ObjBindMethod(this, "_PollTick")
        SetTimer(this._timerCb, 800)
    }

    ; 写入通知只做合并：连续日志不逐条读文件、不逐条刷新界面
    _OnLogWritten() {
        if (this.closed || !IsObject(this.ui) || this._kickCb)
            return
        this._kickCb := ObjBindMethod(this, "_KickRefresh")
        SetTimer(this._kickCb, -200)
    }

    _KickRefresh() {
        this._kickCb := ""
        if (this.closed || !IsObject(this.ui))
            return
        try FlushRMTLogAsync()
        this._Reload(false)
    }

    ; ============ 事件 ============

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        Critical "On"
        this.ui := ""
        this.closed := true
        if (LogCenterGui.instances.Get("main", 0) == this)
            LogCenterGui.instances.Delete("main")
        if (this.HasOwnProp("_notifyCb") && this._notifyCb) {
            RMTLogClearNotify(this._notifyCb)
            this._notifyCb := ""
        }
        if (this._loadCb)
            SetTimer(this._loadCb, 0)
        if (this._timerCb)
            SetTimer(this._timerCb, 0)
        if (this._kickCb)
            SetTimer(this._kickCb, 0)
        this._loadCb := ""
        this._timerCb := ""
        this._kickCb := ""
    }

    OnCloseClick(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }

    OnTabSys(state, ctrl, event) {
        if (!this._ready || this._curTab == "System")
            return
        this._curTab := "System"
        this._Reload(true)
    }

    OnTabBiz(state, ctrl, event) {
        if (!this._ready || this._curTab == "Business")
            return
        this._curTab := "Business"
        this._Reload(true)
    }

    OnLevelChanged(state, ctrl, event) {
        if (!this._ready || this.closed || !IsObject(this.ui))
            return
        idxRaw := this.ui.Query("CmbLevel>SelectedIndex")
        idx := IsNumber(idxRaw) ? Integer(idxRaw) : 0
        filter := idx <= 0 ? "" : ["debug", "info", "warn", "error"][idx]
        if (filter == this._levelFilter)
            return
        this._levelFilter := filter
        this._Reload(true)
    }

    OnRefresh(state, ctrl, event) {
        this._Reload(true)   ; 手动刷新：全量替换
    }

    OnCopy(state, ctrl, event) {
        if (this._shown != "") {
            A_Clipboard := this._shown
            Toast.Success(GetLang("已复制"))
        }
    }

    OnClear(state, ctrl, event) {
        ; 清空当前 tab 对应的日志文件（确认后）
        result := RmtDialog.Confirm(GetLang("确定清空当前日志文件？"), GetLang("日志中心"))
        if (!result)
            return
        path := this._curTab == "System" ? this._SysPath() : this._BizPath()
        try FileDelete(path)
        this._filePos := -1
        this._shown := ""
        this._Reload(true)
    }

    OnExport(state, ctrl, event) {
        txt := this._shown
        if (txt == "")
            return
        defName := this._curTab == "System" ? "System.log" : "Business.log"
        savePath := FileSelect("S16", defName, GetLang("导出日志"), "日志文件 (*.log)")
        if (savePath == "")
            return
        currentPath := this._curTab == "System" ? this._SysPath() : this._BizPath()
        if (ResolvePathNoDotDot(savePath) = ResolvePathNoDotDot(currentPath)) {
            Toast.Warning(GetLang("请选择不同于当前日志的导出文件"))
            return
        }
        try {
            output := FileOpen(savePath, "w", "UTF-8")
            try output.Write(txt)
            finally output.Close()
            Toast.Success(GetLang("已导出"))
        } catch as e {
            Toast.Error(e.Message)
        }
    }

    ; ============ 加载 ============

    _PollTick() {
        if (this.closed || !IsObject(this.ui))
            return
        this._Reload(false)
    }

    ; full=true：切换 / 筛选 / 初次打开，只取文件尾部
    ; full=false：按字节偏移追加新内容，不再整文件读入、也不再把文本框内容 Query 回来
    _Reload(full := false) {
        if (this.closed || !IsObject(this.ui))
            return
        if (this._busy) {
            if (full)
                this._pendingFull := true
            return
        }
        this._busy := true
        this._pendingFull := false
        try {
            path := this._curTab == "System" ? this._SysPath() : this._BizPath()
            if (!FileExist(path)) {
                this._filePos := 0
                this._filterCurrent := ""
                this._filterTail := ""
                if (this._shown != "") {
                    this._shown := ""
                    this.ui.Update("LogCon", "Text", "")
                }
                return
            }
            size := 0
            try size := FileGetSize(path)
            if (!full && this._filePos >= 0 && size == this._filePos)
                return
            ; 一次涨太多就改读尾部，避免把整段新内容再塞进界面
            if (!full && this._filePos >= 0 && size > this._filePos && (size - this._filePos) <= this._maxChars * 4) {
                added := this._ReadFrom(path, this._filePos, &pos)
                this._filePos := pos
                added := this._Filter(added, false)
                if (added == "")
                    return
                this._shown .= added
                trimmed := this._TrimShown(this._shown)
                if (trimmed != this._shown) {
                    this._shown := trimmed
                    this.ui.Update("LogCon", "Text", this._shown)
                } else {
                    this.ui.Update("LogCon", "AppendText", added)
                }
                try this.ui.Update("LogScroll", "ScrollToEnd", "")
                return
            }
            text := this._ReadTail(path, &pos)
            this._filePos := pos
            text := this._TrimShown(this._Filter(text))
            this._shown := text
            this.ui.Update("LogCon", "Text", text)
            try this.ui.Update("LogScroll", "ScrollToEnd", "")
        } catch {
        } finally {
            this._busy := false
            if (this._pendingFull && !this.closed && IsObject(this.ui))
                this._Reload(true)
        }
    }

    _ReadTail(path, &pos) {
        pos := 0
        f := ""
        try f := FileOpen(path, "r-wd", "UTF-8")
        catch
            return ""
        if (!IsObject(f))
            return ""
        try {
            size := f.Length
            budget := this._maxChars * 4
            if (size > budget) {
                f.Pos := size - budget
                try f.ReadLine()
            }
            text := f.Read()
            pos := f.Pos
            return text
        } finally {
            f.Close()
        }
    }

    _ReadFrom(path, fromPos, &pos) {
        pos := fromPos
        f := ""
        try f := FileOpen(path, "r-wd", "UTF-8")
        catch
            return ""
        if (!IsObject(f))
            return ""
        try {
            if (fromPos > f.Length)
                fromPos := 0
            f.Pos := fromPos
            text := f.Read()
            pos := f.Pos
            return text
        } finally {
            f.Close()
        }
    }

    _TrimShown(text) {
        if (StrLen(text) <= this._maxChars)
            return text
        text := SubStr(text, -this._maxChars)
        nl := InStr(text, "`n")
        if (nl)
            text := SubStr(text, nl + 1)
        return GetLang("仅显示最近日志") "`n" text
    }

    _Filter(content, reset := true) {
        if (reset) {
            this._filterCurrent := ""
            this._filterTail := ""
        }
        if (this._levelFilter == "")
            return content
        ; 只识别真正的日志头；匹配该条的级别后，保留所有续行和堆栈。
        ; 轮询可能读到尚未写完的一行，等下次补齐再解析。
        lines := StrSplit(this._filterTail content, "`n", "`r")
        this._filterTail := lines.Length ? lines.Pop() : ""
        filtered := ""
        VarSetStrCapacity(&filtered, StrLen(content))
        for line in lines {
            if (RegExMatch(line, "^\[.*\] \[\d+\] \[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[(debug|info|warn|error)\](?: |$)", &header))
                this._filterCurrent := header[1]
            if (this._filterCurrent == this._levelFilter)
                filtered .= line "`n"
        }
        return filtered
    }
}
