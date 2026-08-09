#Requires AutoHotkey v2.0

; 兼容外部对 .Gui.Hwnd / .Hide / .Show 的调用
class CMDTipGuiFacade {
    __New(owner) {
        this._owner := owner
    }

    Hwnd {
        get => (IsObject(this._owner.ui) && this._owner.ui.HasProp("wpfHwnd")) ? this._owner.ui.wpfHwnd : 0
    }

    Show(opts := "") {
        this._owner._ShowWindow(opts)
    }

    Hide() {
        this._owner._HideWindowOnly()
    }
}

class CMDTipGui {
    __new() {
        this.ui := 0
        this.Gui := ""
        this.SureBtnAction := ""
        this.Data := ""
        this.isLoadParams := false
        this.ShowCount := 0
        this._wheelCb := ""
        this._textLen := 0
        this._viewPos := 0
        this._contentText := ""
        this.closed := true
        ; 日志输出（异步写入缓冲区）
        this._logFlushBuffer := ""
        this._logFlushTimer := ""
        this.LogToFile := false
        this.LogFilePath := ""
        ; 自动清理
        this.AutoClear := 0          ; 0=从不 1=每天 2=每周
        this._lastClearDate := ""
    }

    GetShowOptions() {
        return Format("NoActivate x{} y{} w{} h{}", this.PosX, this.PosY, this.Width, this.Height)
    }

    ShowGui(CMDStr) {
        if (!this.isLoadParams) {
            this.isLoadParams := true
            this.LoadParams()
        }

        if (this.closed || !IsObject(this.ui) || !XAMLHost.CanReuseWindow(this.ui.HasProp("wpfHwnd") ? this.ui.wpfHwnd : 0)) {
            this._BuildAndShow()
            this.OnToggleMacroWorkState()
        }
        else if (!this._IsVisible()) {
            this._ShowWindow()
            this.OnToggleMacroWorkState()
        }

        ; 自动清理检查
        this._AutoClearCheck()

        this.AddCMD(CMDStr)

        if (!this._wheelCb) {
            this._wheelCb := ObjBindMethod(this, "_OnWheel")
            WinHotkey.SubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.SubscribeMouse("WheelDown", this._wheelCb)
        }
    }

    LoadParams() {
        this.PosX := Integer(MainSoftData.CMDPosX)
        this.PosY := Integer(MainSoftData.CMDPosY)
        this.Width := Integer(MainSoftData.CMDWidth)
        this.Height := Integer(MainSoftData.CMDHeight)
        this.BGColor := this._ToRgb6(MainSoftData.CMDBGColor)
        this.RunBGColor := this._ToRgb6(MainSoftData.CMDRunBGColor)
        ; 配置：「背景透明度」0=不透明，100=完全透明 → 背景 Alpha 0~255
        this.BgAlpha := Integer((100 - MainSoftData.CMDTransparency) * 2.55)
        this.FontSize := MainSoftData.CMDFontSize
        this.FontColor := this._ToXamlColor(MainSoftData.CMDFontColor)
        ; 日志输出
        this.LogToFile := MainSoftData.HasProp("CMDLogToFile") ? MainSoftData.CMDLogToFile : false
        rawPath := MainSoftData.HasProp("CMDLogFilePath") ? MainSoftData.CMDLogFilePath : ""
        this.LogFilePath := (rawPath != "") ? rawPath : A_WorkingDir "\Log\CMDLog.txt"
        this.AutoClear := MainSoftData.HasProp("CMDLogAutoClear") ? MainSoftData.CMDLogAutoClear : 0
        if (this._lastClearDate == "")
            this._lastClearDate := FormatTime(A_Now, "yyyyMMdd")
    }

    _ToRgb6(c) {
        c := StrReplace(String(c), "#")
        if (StrLen(c) == 8)
            return SubStr(c, 3, 6)
        if (StrLen(c) == 6)
            return c
        return "FFFFFF"
    }

    _ToXamlColor(c) {
        return "#" this._ToRgb6(c)
    }

    ; 带透明度的背景色（文字保持不透明）
    _BgBrush(rgb6 := "") {
        if (rgb6 == "")
            rgb6 := this.BGColor
        return Format("#{:02X}{}", this.BgAlpha, rgb6)
    }

    ; 行内字符间插入零宽空格，使 TextWrapping 按字符填满一行再断行（避免在 & 等处提前截断）
    _ToDisplayText(s) {
        zw := Chr(0x200B)
        out := ""
        loop parse s, "`n", "`r" {
            if (A_Index > 1)
                out .= "`n"
            line := A_LoopField
            lineOut := ""
            loop parse line {
                if (A_Index > 1)
                    lineOut .= zw
                lineOut .= A_LoopField
            }
            out .= lineOut
        }
        return out
    }

    _SetDisplayText(text) {
        this.ui.Update("ContentCon", "Text", this._ToDisplayText(text))
        this._ScrollToEnd()
    }

    _ScrollToEnd() {
        try this.ui.Update("ContentCon", "ScrollToEnd", "")
        this._textLen := StrLen(this._ToDisplayText(this._contentText))
        this._viewPos := this._textLen
    }

    ApplySettings() {
        this.LoadParams()
        this.isLoadParams := true
        if (this.closed || !IsObject(this.ui))
            return

        savedText := this._contentText
        savedCount := this.ShowCount
        wasVisible := this._IsVisible()
        this._DestroyUi(false)
        if (!wasVisible)
            return

        this._BuildAndShow()
        this._contentText := savedText
        this.ShowCount := savedCount
        this._textLen := StrLen(savedText)
        this._viewPos := this._textLen
        if (IsObject(this.ui))
            this._SetDisplayText(savedText)
        this.OnToggleMacroWorkState()
    }

    ApplyThemeColors() {
        this.BGColor := this._ToRgb6(MainSoftData.CMDBGColor)
        this.RunBGColor := this._ToRgb6(MainSoftData.CMDRunBGColor)
        this.FontColor := this._ToXamlColor(MainSoftData.CMDFontColor)
        if (this.closed || !IsObject(this.ui))
            return
        try {
            this.ui.Update("ContentCon", "Foreground", this.FontColor)
            this.OnToggleMacroWorkState()
        }
    }

    _BuildAndShow() {
        this.closed := false
        bg := this._BgBrush(this.BGColor)
        fg := this.FontColor
        fs := String(this.FontSize)

        ; 无标题浮层：左上对齐；ZWSP 字符换行见 _ToDisplayText；穿透见 IsHitTestVisible
        main := XAML_Generator("Border").Name("RootBorder")
            .Background(bg).BorderThickness("0").CornerRadius("0")
            .IsHitTestVisible("False")
        main.Add("TextBox").Name("ContentCon")
            .Text("")
            .IsReadOnly("True")
            .AcceptsReturn("True")
            .TextWrapping("Wrap")
            .TextAlignment("Left")
            .HorizontalContentAlignment("Left")
            .VerticalContentAlignment("Top")
            .BorderThickness("0")
            .Background(bg)
            .Foreground(fg)
            .FontSize(fs)
            .FontFamily(MainSoftData.FontType)
            .Padding("6,4")
            .VerticalScrollBarVisibility("Auto")
            .HorizontalScrollBarVisibility("Disabled")
            .IsTabStop("False")
            .Focusable("False")
            .IsHitTestVisible("False")
            .CaretBrush("Transparent")

        ; 配置为物理像素；XAML Left/Top/Width/Height 使用 DIP
        dipX := PhysToDip(this.PosX)
        dipY := PhysToDip(this.PosY)
        dipW := PhysToDip(this.Width)
        dipH := PhysToDip(this.Height)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "0")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            Format('Title="CMDTip" ShowInTaskbar="False" Topmost="True" ShowActivated="False" Left="{}" Top="{}" Width="{}" Height="{}" Opacity="0"',
                dipX, dipY, dipW, dipH))
        this.ui.xaml := StrReplace(this.ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))

        this.Gui := CMDTipGuiFacade(this)
        this.ui.Show()

        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                this._ApplyWinStyles()
                this._ApplyContentColors()
                try this.ui.Update("Window", "Opacity", "1")
                this._ApplyClickThrough()  ; Opacity 后再设一次，避免被 WPF 冲掉
                break
            }
            Sleep(50)
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            this._ApplyWinStyles()
            this._ApplyContentColors()
        } finally {
            this.ui.Update("Window", "Opacity", "1")
            this._ApplyClickThrough()
        }
    }

    _ApplyContentColors() {
        if (!IsObject(this.ui) || this.closed)
            return
        rgb := MySoftData.IsMacroWorking ? this.RunBGColor : this.BGColor
        bg := this._BgBrush(rgb)
        try this.ui.Update("RootBorder", "Background", bg)
        try this.ui.Update("ContentCon", "Background", bg)
        try this.ui.Update("ContentCon", "Foreground", this.FontColor)
        try this.ui.Update("ContentCon", "FontSize", String(this.FontSize))
    }

    _ApplyWinStyles() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        try this.ui.Update("Window", "Left", String(PhysToDip(this.PosX)))
        try this.ui.Update("Window", "Top", String(PhysToDip(this.PosY)))
        try this.ui.Update("Window", "Width", String(PhysToDip(this.Width)))
        try this.ui.Update("Window", "Height", String(PhysToDip(this.Height)))
        this._ApplyClickThrough()
    }

    ; 对齐原版 +E0x20：点击穿透（不抢鼠标）
    _ApplyClickThrough() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        try WinSetExStyle("+0x20", "ahk_id " hwnd)          ; WS_EX_TRANSPARENT
        try WinSetExStyle("+0x80", "ahk_id " hwnd)          ; WS_EX_TOOLWINDOW
        try WinSetExStyle("+0x08000000", "ahk_id " hwnd)    ; WS_EX_NOACTIVATE
    }

    OnWindowClosing(state, ctrl, event) {
        this._DestroyUi(true)
    }

    _DestroyUi(clearWheel) {
        this.closed := true
        this.ui := ""
        this.Gui := ""
        if (clearWheel && this._wheelCb) {
            try WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            try WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }
    }

    AddCMD(CMDStr) {
        if (!IsObject(this.ui) || this.closed)
            return

        this.ShowCount++
        if (this._contentText == "")
            this._contentText := CMDStr
        else
            this._contentText .= Format("`n{}", CMDStr)

        if (this.ShowCount >= 100) {
            this.ShowCount--
            Pos := InStr(this._contentText, "`n")
            this._contentText := Pos ? SubStr(this._contentText, Pos + 1) : this._contentText
            this._SetDisplayText(this._contentText)
        } else if (this.ShowCount == 1) {
            this._SetDisplayText(this._contentText)
        } else {
            ; 新行同样做字符级可断点，AppendText 自带滚到底
            this.ui.Update("ContentCon", "AppendText", this._ToDisplayText(Format("`n{}", CMDStr)))
            this._textLen := StrLen(this._ToDisplayText(this._contentText))
            this._viewPos := this._textLen
        }

        ; 异步写日志文件（不阻塞主线程）
        if (this.LogToFile) {
            this._LogToFile(CMDStr)
        }
    }

    ; 写入日志文件（异步：积累缓冲，定时一次写入）
    _LogToFile(text) {
        if (this._logFlushTimer == "") {
            this._logFlushTimer := ObjBindMethod(this, "_FlushLog")
            SetTimer(this._logFlushTimer, -3000)  ; 3 秒后一次性写入
        } else {
            ; 已有定时器在等，刷新超时
            SetTimer(this._logFlushTimer, 0)
            SetTimer(this._logFlushTimer, -3000)
        }
        this._logFlushBuffer .= Format("`n{}", text)
    }

    _FlushLog() {
        buf := this._logFlushBuffer
        this._logFlushBuffer := ""
        this._logFlushTimer := ""
        if (buf == "")
            return
        ; 非阻塞写入：FileAppend 在 AHK v2 中是同步的，
        ; 但 3s 积累批量写入比每行写一次开销小很多
        try {
            SplitPath this.LogFilePath, , &logDir
            if (!DirExist(logDir))
                DirCreate(logDir)
            FileAppend buf, this.LogFilePath, "UTF-8-RAW"
        }
    }

    ; 自动清理旧日志
    _AutoClearCheck() {
        if (this.AutoClear == 0 || this._contentText == "")
            return
        shouldClear := false
        if (this.AutoClear == 1) {
            ; 每天：日期不同就清理
            shouldClear := FormatTime(A_Now, "yyyyMMdd") != this._lastClearDate
        } else if (this.AutoClear == 2) {
            ; 每周：跨周才清理
            ; ISO 年份+周数一体（YWeek 为 v2.0 原生令牌，含零填充）
            curWeek := FormatTime(A_Now, "YWeek")
            lastWeek := FormatTime(this._lastClearDate, "YWeek")
            shouldClear := curWeek != lastWeek
        }
        if (!shouldClear)
            return
        this._lastClearDate := FormatTime(A_Now, "yyyyMMdd")
        this.ShowCount := 0
        this._contentText := ""
        this._textLen := 0
        this._viewPos := 0
        if (IsObject(this.ui) && !this.closed)
            try this.ui.Update("ContentCon", "Text", "")
    }

    Hide() {
        if (this.closed || !IsObject(this.ui))
            return

        ; 刷新最后一波日志
        this._FlushLog()

        this.ShowCount := 0
        this._contentText := ""
        this._textLen := 0
        this._viewPos := 0
        try this.ui.Update("ContentCon", "Text", "")
        this._HideWindowOnly()

        if (this._wheelCb) {
            try WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            try WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }
    }

    _HideWindowOnly() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (hwnd)
            try WinHide("ahk_id " hwnd)
    }

    _ShowWindow(opts := "") {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        if (opts != "") {
            if RegExMatch(opts, "i)x\s*(-?\d+)", &mx)
                this.PosX := Integer(mx[1])
            if RegExMatch(opts, "i)y\s*(-?\d+)", &my)
                this.PosY := Integer(my[1])
            if RegExMatch(opts, "i)w\s*(-?\d+)", &mw)
                this.Width := Integer(mw[1])
            if RegExMatch(opts, "i)h\s*(-?\d+)", &mh)
                this.Height := Integer(mh[1])
        }
        this._ApplyWinStyles()
        try WinShow("ahk_id " hwnd)
    }

    _IsVisible() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return false
        try {
            style := WinGetStyle("ahk_id " hwnd)
            return !!(style & 0x10000000)
        }
        return false
    }

    _OnWheel(key, *) {
        this.OnScrollWheel(key)
    }

    OnToggleMacroWorkState() {
        if (this.closed || !IsObject(this.ui))
            return
        if (!this._IsVisible())
            return
        this._ApplyContentColors()
    }

    OnScrollWheel(key) {
        if (this.closed || !IsObject(this.ui))
            return
        if (!this._IsVisible())
            return

        ; 穿透窗口收不到原生滚轮，靠全局热键：指针在指令显示区域内时滚动内容
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        isOnWin := mouseX >= this.PosX && mouseY >= this.PosY
        isOnWin := isOnWin && mouseX <= this.PosX + this.Width && mouseY <= this.PosY + this.Height
        if (!isOnWin)
            return

        isDown := InStr(key, "Down", "Off") ? true : false
        ; 每次滚轮约 3 行，带动右侧滚动条
        loop 3 {
            if (isDown) {
                try this.ui.Update("ContentCon", "LineDown", "")
            } else {
                try this.ui.Update("ContentCon", "LineUp", "")
            }
        }
    }
}
