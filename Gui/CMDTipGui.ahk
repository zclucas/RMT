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
        ; 帧末批量提交：宏循环每秒可执行上千条指令，逐条同步 Update（内部 SendMessage）
        ; 会使主进程产生毫秒级阻塞，投递队列迅速达到 1 万条上限（PostMessage 返回 1816），
        ; 导致其他 Worker 的通知无法投递。改为帧末一次提交。
        this._pendingCmd := ""
        this._flushScheduled := false
        this._lastFlush := 0
        this._flushFn := ObjBindMethod(this, "_FlushCmd")
        ; 窗口可用标志：稳态下 ShowGui 仅读取该值，不做跨进程探测
        this._windowOK := false
        this._winCheckTick := 0
        this._autoClearTick := 0
        this._readyScheduled := false   ; 补主题与补样式仅调度一次（两个 LoadedHwnd 回调均汇入此处）
        ; 异步提交通道：指令流水走共享内存，不等待引擎回执。
        ; 指令流水与补样式共用 XAMLHost 的异步槽，此处不单独持有。
        this._buildScheduled := false
        ; 日志输出（异步写入缓冲区）
        this._logFlushBuffer := ""
        this._logFlushTimer := ""
        this.LogToFile := false
        this.LogFilePath := ""
        ; 自动清理：0=从不 1=每天 2=每周。按日志文件修改时间判断，不记在内存里
        this.AutoClear := 2
        ; §7 当前按下按键展示区
        this._keyTimer := ""         ; 按键轮询定时器（窗口可见时运行）
        this._lastKeys := ""         ; 上次展示的按键串（变化才刷新 UI，零 IPC 去抖）
        this._keyMap := CMDTipGui._BuildKeyNameMap()
        this._keySlots := 8          ; 固定槽位按钮数（组合键几乎不可能同时超过 8 个）
    }

    ; §7 虚拟键码 → 展示名映射（构建一次；显示顺序即 Map 插入顺序，修饰键在前）
    static _BuildKeyNameMap() {
        m := Map()
        ; 修饰键
        m[0xA0] := "LShift"
        m[0xA1] := "RShift"
        m[0xA2] := "LCtrl"
        m[0xA3] := "RCtrl"
        m[0xA4] := "LAlt"
        m[0xA5] := "RAlt"
        m[0x5B] := "LWin"
        m[0x5C] := "RWin"
        ; 字母（大写）
        loop 26 {
            vk := 0x41 + A_Index - 1
            m[vk] := Chr(0x41 + A_Index - 1)
        }
        ; 数字
        loop 10 {
            vk := 0x30 + A_Index - 1
            m[vk] := Chr(0x30 + A_Index - 1)
        }
        ; 功能键
        loop 24 {
            vk := 0x70 + A_Index - 1
            m[vk] := "F" A_Index
        }
        ; 导航/编辑
        m[0x1B] := "Esc"
        m[0x08] := "Backspace"
        m[0x09] := "Tab"
        m[0x0D] := "Enter"
        m[0x20] := "Space"
        m[0x14] := "CapsLock"
        m[0x2C] := "PrintScreen"
        m[0x2D] := "Insert"
        m[0x2E] := "Delete"
        m[0x24] := "Home"
        m[0x23] := "End"
        m[0x21] := "PgUp"
        m[0x22] := "PgDn"
        m[0x25] := "Left"
        m[0x26] := "Up"
        m[0x27] := "Right"
        m[0x28] := "Down"
        ; 标点
        m[0xBA] := ";"
        m[0xBB] := "="
        m[0xBC] := ","
        m[0xBD] := "-"
        m[0xBE] := "."
        m[0xBF] := "/"
        m[0xC0] := "``"
        m[0xDB] := "["
        m[0xDC] := "\"
        m[0xDD] := "]"
        m[0xDE] := "'"
        ; 小键盘
        m[0x90] := "NumLock"
        loop 10 {
            vk := 0x60 + A_Index - 1
            m[vk] := "Num" (A_Index - 1)
        }
        m[0x6A] := "Num*"
        m[0x6B] := "Num+"
        m[0x6D] := "Num-"
        m[0x6E] := "Num."
        m[0x6F] := "Num/"
        return m
    }

    GetShowOptions() {
        return Format("NoActivate x{} y{} w{} h{}", this.PosX, this.PosY, this.Width, this.Height)
    }

    ShowGui(CMDStr) {
        if (!this.isLoadParams) {
            this.isLoadParams := true
            this.LoadParams()
        }

        ; 窗口检查成本较高：CanReuseWindow 内含一次 SendMessageTimeout(WM_NULL)
        ; （跨进程、400ms 超时）；_IsVisible 需调用 WinGetStyle，_AutoClearCheck 需读取文件时间。
        ; 逐条执行时，两个宏并发即可阻塞主线程与引擎 daemon。
        ; 改为「失效时必查 + 每 2 秒兜底一次」，稳态下每行仅一次整数比较。
        ; 兜底检查不做深探测：深探测为同步跨进程调用，引擎排版或追加文本时
        ; 会一并阻塞主线程，表现为每 2 秒停顿一次。窗口失效可由
        ; _IsVisible/WinExist 等本地判断发现。
        now := A_TickCount
        if (!this._windowOK || now - this._winCheckTick >= 2000) {
            this._winCheckTick := now
            this._windowOK := this._EnsureWindow(!this._windowOK)
        }

        ; 自动清理降为分钟级：原先每行均执行 FileExist 与 FileGetTime
        if (!this._autoClearTick || now - this._autoClearTick >= 60000) {
            this._autoClearTick := now
            this._AutoClearCheck()
        }

        this.AddCMD(CMDStr)

        if (!this._wheelCb) {
            this._wheelCb := ObjBindMethod(this, "_OnWheel")
            WinHotkey.SubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.SubscribeMouse("WheelDown", this._wheelCb)
        }

        ; §7 启动按键轮询（常驻定时器，窗口不可见时自动跳过）
        if (!this._keyTimer) {
            this._keyTimer := ObjBindMethod(this, "_PollKeys")
            SetTimer(this._keyTimer, 50)
        }
    }

    ; 确保窗口存在且可见。返回 false 表示内容无法显示（窗口创建失败）。
    ; deep=true 时额外向引擎发起一次响应性探测（同步跨进程，仅在窗口状态未知时使用）。
    _EnsureWindow(deep := true) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (this.closed || !IsObject(this.ui) || !XAMLHost.CanReuseWindow(hwnd, deep)) {
            ; 建窗开销较大（XAML 构造、编码、daemon 创建），置于消息回调中会使
            ; 回调期间主线程完全阻塞。改由伪线程执行，先归还消息循环控制权；
            ; 期间内容累积在 _pendingCmd，建窗完成后统一发送。
            if (!this._buildScheduled) {
                this._buildScheduled := true
                SetTimer(ObjBindMethod(this, "_DeferredBuild"), -1)
            }
            return true
        }
        if (!this._IsVisible()) {
            this._ShowWindow()
            this.OnToggleMacroWorkState()
        }
        return true
    }

    ; 伪线程中执行建窗
    _DeferredBuild() {
        this._buildScheduled := false
        ; 此处不能判断 this.closed：其初始值为 true（表示尚无窗口），
        ; 该值在 _BuildAndShow 开头才被清除；提前判断会导致窗口永不创建。
        this._BuildAndShow()
        try this.OnToggleMacroWorkState()
        if (this._pendingCmd != "" && !this._flushScheduled) {
            this._flushScheduled := true
            SetTimer(this._flushFn, -1)
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
        ; 日志输出。空配置 = 软件所在目录\Log\CMDLog.txt，文件夹挪走后仍然指向新目录
        this.LogToFile := MainSoftData.HasProp("CMDLogToFile") ? MainSoftData.CMDLogToFile : false
        rawPath := MainSoftData.HasProp("CMDLogFilePath") ? MainSoftData.CMDLogFilePath : ""
        this.LogFilePath := CMDLogResolveFile(rawPath)
        this.AutoClear := MainSoftData.HasProp("CMDLogAutoClear") && IsNumber(MainSoftData.CMDLogAutoClear) ? Integer(MainSoftData.CMDLogAutoClear) : 2
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

    ; 显示文本与原始文本一致：不插入零宽空格，不做改写。
    ; （早期为配合 TextWrapping="Wrap" 在字符间插入 ZWSP；改为 NoWrap 后不再需要，
    ;  且会污染复制文本并增加一次全文正则开销。）
    _ToDisplayText(s) {
        return s
    }

    _SetDisplayText(text) {
        shown := this._ToDisplayText(text)
        ; 整体替换并滚动到底，单次投递两条命令
        payload := "ContentCon|Text|" this._CmdValue(shown) "`nContentCon|ScrollToEnd|"
        if (!this._PushAsync(payload))
            try this.ui.Update("ContentCon", "Text", shown)
        this._textLen := StrLen(this._contentText)
        this._viewPos := this._textLen
    }

    _ScrollToEnd() {
        try this.ui.Update("ContentCon", "ScrollToEnd", "")
        this._textLen := StrLen(this._contentText)
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

        ; 无标题浮层：左上对齐；穿透由 IsHitTestVisible 控制
        main := XAML_Generator("Border").Name("RootBorder")
            .Background(bg).BorderThickness("0").CornerRadius("0")
            .IsHitTestVisible("False")
        grid := main.Add("Grid")
        grid.Rows("*", "42")
        grid.Add("TextBox").Name("ContentCon").Grid_Row(0)
            .Text("")
            .IsReadOnly("True")
            .AcceptsReturn("True")
            ; 不能启用 Wrap：TextBox 自动换行后，每次追加文本都需重新计算全部行的折行位置
            ; （折点取决于可用宽度）。100 行内容每秒追加十余次即触发十余次全量重排，
            ; 全部落在 daemon 的单条 UI 线程上，并延后悬浮窗的渲染。
            ; 日志类文本无需折行，长行以横向滚动呈现。
            .TextWrapping("NoWrap")
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
            .HorizontalScrollBarVisibility("Auto")
            .IsTabStop("False")
            .Focusable("False")
            .IsHitTestVisible("False")
            .CaretBrush("Transparent")

        ; §7 当前按下按键展示区：固定 8 个槽位按钮（32×32，长键名宽度随内容自适应不截断），
        ; 只显示当前按下的按键；窗口点击穿透，纯展示无交互
        keysRow := grid.Add("WrapPanel").Name("KeysPanel").Grid_Row(1)
            .Orientation("Horizontal").VerticalAlignment("Center").Margin("6,2")
        loop this._keySlots {
            keysRow.Add("Button").Name("KeyBtn_" (A_Index - 1))
                .MinWidth(32).Height(32).Margin("2,0,0,0").Padding("6,0")
                .Content("").Visibility("Collapsed")
                .VerticalContentAlignment("Center").HorizontalContentAlignment("Center")
                .FontSize("11").Foreground(fg)
                .Background("Transparent").BorderThickness("1")
                .BorderBrush("#44FFFFFF").Cursor("Arrow").IsHitTestVisible("False").Focusable("False")
        }

        ; 配置为物理像素；XAML Left/Top/Width/Height 使用 DIP
        dipX := PhysToDip(this.PosX)
        dipY := PhysToDip(this.PosY)
        dipW := PhysToDip(this.Width)
        dipH := PhysToDip(this.Height)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "0")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        ; 建窗期间的更新由 _AfterWindowReady 统一接管，并入其 collect 一次投递；
        ; 不得在 LoadedHwnd 分支同步发送（实测 157ms 阻塞，会打断悬浮窗刷新节拍）。
        this.ui.skipQueueFlush := true
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            Format('Title="CMDTip" ShowInTaskbar="False" Topmost="True" ShowActivated="False" Left="{}" Top="{}" Width="{}" Height="{}"',
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
        this._ApplyContentColors()
        ; 至此已占用一整轮消息循环（XAML 构造 + XAMLHost 构造）。
        ; Show 推迟到下一个循环执行：悬浮窗节拍为 16ms，连续执行两步会跳过多帧。
        try SetTimer(ObjBindMethod(this, "_ShowDeferred"), -1)
    }

    ; 建窗第二步（伪线程）：仅执行 Show。
    ; 不使用 Open：其内部以 Sleep 轮询句柄（实测 200~700ms，最坏 2 秒）。
    ; 主题同样推迟（deferTheme=true）：该操作为约 30 条 Resource 的同步批量更新。
    _ShowDeferred() {
        if (this.closed || !IsObject(this.ui))
            return
        r := XamlWin.OpenNoWait(this.ui, "", "", true)
        if (!r) {
            this._windowOK := false
            return
        }
        this._windowOK := true
        try this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "_OnWindowLoaded"))
    }

    ; 两个 LoadedHwnd 回调（OnWindowLoad 与本回调）汇入同一入口，仅执行一次。
    ; 回调栈中不得同步刷新 XAML：引擎正在等待该事件回执，再发送会相互等待。
    _OnWindowLoaded(state, ctrlName, eventName) {
        this._QueueWindowReady()
    }

    OnWindowLoad(state, ctrl, event) {
        this._QueueWindowReady()
    }

    _QueueWindowReady() {
        if (this._readyScheduled)
            return
        this._readyScheduled := true
        ; 此时窗口尚未显示：引擎需等待 ContentRendered 后才显示首帧。
        ; 在该时机修改 EXSTYLE 与置顶不触发分层表面重建；若推迟到 _AfterWindowReady，
        ; 窗口已显示，单次 SetWindowLong 实测 25ms，会导致悬浮窗跳帧。
        ; 两者均为本地 Win32 调用，不经 IPC，故可置于事件回调中。
        try this._ApplyNativeStyles()
        try SetTimer(ObjBindMethod(this, "_AfterWindowReady"), -1)
    }

    ; 本地窗口样式（非 XAML）：穿透、不激活、工具窗口、置顶。
    ; 幂等：已符合目标值时不做修改。
    _ApplyNativeStyles() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
        ; WS_EX_TOPMOST 0x8：XAML 里写了 Topmost="True"，引擎建窗时通常已经设过
        if (!(ex & 0x8))
            try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        ; WS_EX_TRANSPARENT 0x20 | WS_EX_TOOLWINDOW 0x80 | WS_EX_NOACTIVATE 0x08000000
        want := ex | 0x20 | 0x80 | 0x08000000
        if (ex != want)
            try DllCall("user32\SetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr", want)
    }

    ; 窗口就绪后：补主题（建窗时推迟，以避免 Show 阻塞百余毫秒）、
    ; 补窗口样式与内容配色，并发送建窗期间累积的内容。
    ;
    ; 上述操作合计十余次 Update。逐条发送即十余次同步 IPC，每次均须等待 daemon 处理，
    ; 与悬浮窗 16ms 节拍冲突，故先合并再一次性投递：
    ; 优先使用共享内存异步通道，不可用时回退同步（合并后的 payload 仍优于逐条发送）。
    _AfterWindowReady() {
        this._readyScheduled := false
        if (this.closed || !IsObject(this.ui))
            return

        this.ui.BeginCollect()
        ; 先并入建窗期间的更新（配色、GMUIConfigure 等），
        ; 与下方主题、尺寸同属窗口初始化操作，合并为一次投递。
        try this.ui.FlushQueueNow()
        try XamlWin.QueueTheme(this.ui)
        try this._ApplyWinStyles()
        try this._ApplyContentColors()
        try this.ui.Update("Window", "Opacity", "1")
        cmds := this.ui.EndCollect()

        if (cmds != "") {
            if (!this._PushAsync(cmds))
                try this.ui.SendRaw(cmds)
        }

        if (this._pendingCmd != "" && !this._flushScheduled) {
            this._flushScheduled := true
            SetTimer(this._flushFn, -1)
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

    ; 仅设置位置与尺寸等 XAML 属性（在 _AfterWindowReady 中由 collect 包裹，一次异步投递）。
    ; 穿透与置顶等本地 EXSTYLE 由 _ApplyNativeStyles 处理：该时机窗口尚未显示，修改不触发表面重建。
    _ApplyWinStyles() {
        if (!IsObject(this.ui) || this.closed)
            return
        try this.ui.Update("Window", "Left", String(PhysToDip(this.PosX)))
        try this.ui.Update("Window", "Top", String(PhysToDip(this.PosY)))
        try this.ui.Update("Window", "Width", String(PhysToDip(this.Width)))
        try this.ui.Update("Window", "Height", String(PhysToDip(this.Height)))
    }

    OnWindowClosing(state, ctrl, event) {
        this._DestroyUi(true)
    }

    _DestroyUi(clearWheel) {
        this.closed := true
        this.ui := ""
        this.Gui := ""
        this._windowOK := false
        this._buildScheduled := false
        if (clearWheel && this._wheelCb) {
            try WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            try WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }
        if (this._keyTimer) {
            SetTimer(this._keyTimer, 0)
            this._keyTimer := ""
        }
        this._lastKeys := ""
    }

    ; §7 按键轮询：GetAsyncKeyState 检测当前按下键，状态变化才刷新槽位按钮（零 IPC 去抖）
    _PollKeys(*) {
        if (this.closed || !IsObject(this.ui))
            return
        if (!this._IsVisible()) {
            ; 窗口不可见：清空展示区
            if (this._lastKeys != "") {
                this._lastKeys := ""
                this._SetKeyButtons([])
            }
            return
        }
        keys := []
        for vk, name in this._keyMap {
            if (DllCall("GetAsyncKeyState", "Int", vk) & 0x8000)
                keys.Push(name)
        }
        keyStr := ""
        for k in keys
            keyStr .= k "|"
        if (keyStr == this._lastKeys)
            return
        this._lastKeys := keyStr
        this._SetKeyButtons(keys)
    }

    ; §7 刷新按键槽位按钮（固定槽位，一次批量 IPC）
    _SetKeyButtons(keys) {
        if (this.closed || !IsObject(this.ui))
            return
        batch := []
        loop this._keySlots {
            i := A_Index - 1
            if (i < keys.Length) {
                batch.Push({ControlName: "KeyBtn_" i, PropertyName: "Content", Value: keys[i + 1]})
                batch.Push({ControlName: "KeyBtn_" i, PropertyName: "Visibility", Value: "Visible"})
            } else {
                batch.Push({ControlName: "KeyBtn_" i, PropertyName: "Visibility", Value: "Collapsed"})
            }
        }
        try this.ui.BatchUpdate(batch)
    }

    AddCMD(CMDStr) {
        if (!IsObject(this.ui) || this.closed)
            return

        ; 累积到帧末统一提交，此处不直接 Update。
        ; 指令显示开启时每秒可达上千条，逐条同步更新会使主线程饱和。
        this._pendingCmd .= (this._pendingCmd == "" ? "" : "`n") CMDStr
        if (!this._flushScheduled) {
            ; 限速 80ms：内容已进入缓冲区，延迟提交不会丢行。
            ; 若不限速，flush 完成后立即再次排队，每秒产生数百次伪线程调度，
            ; SetTimer(-1) 会插入消息队列首部，延迟其他消息。
            ;
            ; 取值 80ms 而非更小的原因：主要成本在引擎侧 —— 每次 AppendText 都需
            ; 重新排版 TextBox 全部行，批次越密总成本越高。80ms 一次、每次数十行，
            ; 重排次数约为原来的三分之一。
            this._flushScheduled := true
            wait := 80 - (A_TickCount - this._lastFlush)
            if (wait < 1)
                wait := 1
            SetTimer(this._flushFn, -wait)
        }

        ; 异步写入日志文件，不阻塞主线程
        if (this.LogToFile) {
            this._LogToFile(CMDStr)
        }
    }

    ; 帧末提交：本帧累积的所有行由一次 Update 处理完毕。
    ; 异步提交：写共享内存 + 唤醒消息，不等待引擎回执。
    ;
    ; 原实现走 XAMLHost.Update（SendMessage），每次均须等待 daemon 处理完成。
    ; 引擎繁忙时该等待可达十余毫秒，且发生在主线程上，会阻塞悬浮窗的刷新节拍（SetTimer）。
    ; payload 以换行分隔多条命令，内容中的换行已转义为 &#x0A;。
    _PushAsync(payload) {
        if (!IsObject(this.ui) || this.closed)
            return false
        ; 统一使用 XAMLHost 的通道（每窗口一槽，仅挂接一次）。
        ; 不可另建槽：窗口仅使用最后挂接的槽，两个槽并存会相互覆盖。
        return this.ui.UpdateRawAsync(payload)
    }

    ; 命令参数转义：换行为命令分隔符，内容中的换行必须转义
    _CmdValue(s) {
        return StrReplace(StrReplace(s, "`r", "&#x0D;"), "`n", "&#x0A;")
    }

    _FlushCmd() {
        this._flushScheduled := false
        this._lastFlush := A_TickCount
        if (!IsObject(this.ui) || this.closed || this._pendingCmd == "")
            return

        batch := this._pendingCmd
        this._pendingCmd := ""

        wasEmpty := (this._contentText == "")
        this._contentText := wasEmpty ? batch : this._contentText "`n" batch
        lineCount := this._CountLines(this._contentText)
        this.ShowCount := lineCount

        if (lineCount > 100) {
            ; 超上限：裁剪至最近 100 行并整体重设（每帧至多一次，成本低于逐行裁剪）
            this._contentText := this._TakeTailLines(this._contentText, 100)
            this.ShowCount := 100
            this._SetDisplayText(this._contentText)
        } else if (wasEmpty) {
            this._SetDisplayText(this._contentText)
        } else {
            ; 新行同样经过字符级断点处理，AppendText 自带滚动到底
            shown := this._ToDisplayText("`n" batch)
            if (!this._PushAsync("ContentCon|AppendText|" this._CmdValue(shown)))
                try this.ui.Update("ContentCon", "AppendText", shown)
            this._textLen := StrLen(this._contentText)
            this._viewPos := this._textLen
        }
    }

    _CountLines(text) {
        n := 1
        pos := 1
        while (pos := InStr(text, "`n", , pos)) {
            n += 1
            pos += 1
        }
        return n
    }

    _TakeTailLines(text, maxLines) {
        lines := StrSplit(text, "`n")
        if (lines.Length <= maxLines)
            return text
        start := lines.Length - maxLines + 1
        out := ""
        loop maxLines {
            out .= (A_Index == 1 ? "" : "`n") lines[start + A_Index - 1]
        }
        return out
    }

    ; 写入日志文件：缓冲累积，定时批量写出
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
        ; FileAppend 在 AHK v2 中为同步调用；每 3 秒批量写入，
        ; 相比逐行写入可显著降低开销。
        try {
            ; 跨天/跨周先删旧文件，再写入这一批。判断依据是文件修改时间，重启后仍然有效
            CMDLogTryAutoClear(this.LogFilePath, this.AutoClear)
            SplitPath this.LogFilePath, , &logDir
            if (!DirExist(logDir))
                DirCreate(logDir)
            FileAppend buf, this.LogFilePath, "UTF-8-RAW"
        }
    }

    ; 到了清理周期：删掉过期日志文件，并清掉屏幕上还留着的旧指令
    _AutoClearCheck() {
        if (!CMDLogTryAutoClear(this.LogFilePath, this.AutoClear))
            return
        this._logFlushBuffer := ""
        this.ShowCount := 0
        this._contentText := ""
        this._pendingCmd := ""
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
        this._pendingCmd := ""
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
        ; 下次有内容时须重新检查并显示，不等待 2 秒兜底
        this._windowOK := false
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
        this._windowOK := true
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
