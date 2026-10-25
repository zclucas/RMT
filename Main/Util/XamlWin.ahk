#Requires AutoHotkey v2.0

; =============================================================================
; XamlWin — 所有 XAML 子窗统一开窗：先入队主题/内容，再 Show，hwnd 后揭盖
;
; 不闪原因（AI 设置同款）：
;   1. 窗口 XAML 带 Opacity="0"，引擎离屏创建
;   2. Show 前 ApplyXamlTheme + 填表，Update 进 _updateQueue
;   3. LoadedHwnd 一次刷入队列，再 Opacity=1
;   4. OnWindowLoad 不再二次 ApplyXamlTheme（后补描边/滚动条会闪）
;
; 用法：
;   建好 ui、绑事件后：
;     XamlWin.Open(this.ui, () => this.Init(cmd), this.OwnerHwnd)
;   OnWindowLoad 里只写：
;     XamlWin.OnLoadTheme(this.ui)
; =============================================================================

class XamlWin {
    ; Small business dialogs share the same chrome, theme and GM-UI registration.
    static Create(title, content, width, height, fluidContent := false) {
        visualScale := fluidContent ? XAMLHost.GetMainViewboxScale() : 1
        bodyFont := fluidContent ? XAMLHost.VisualFontSizeDeclared() : XAMLHost.FontSize()
        titleHeight := fluidContent ? XAMLHost.FormatFontSize(30 * visualScale) : "30"
        main := XAML_Generator("Grid").Name("RmtDialogRoot").Background("{DynamicResource BgColor}")
            .TextElement_FontFamily(MainSoftData.FontType).TextElement_FontSize(bodyFont)
        main.Rows(titleHeight, "*")
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClosePanel", "DialogTitle")
        if (fluidContent) {
            try chrome.Title.FontSize(XAMLHost.VisualFontSizeDeclared(2))
        }
        body := main.Add("Border").Grid_Row(1)
        body._Children.Push(content)
        content._Parent := body
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()))
        safeTitle := StrReplace(StrReplace(StrReplace(title, "&", "&amp;"), '"', "&quot;"), "<", "&lt;")
        ; Emit design DIP sizes. ApplyDialogVisualScale enlarges the window and pins the root
        ; so EngineHost's Viewbox matches the main UI. Pre-multiplying here would double-scale.
        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" ShowInTaskbar="False" Width="' Round(width * visualScale) '" Height="' Round(height * visualScale) '" Opacity="0"')
        ; Window chrome corners sit outside the title row. Paint them with TitleBarColor so a
        ; Viewbox letterbox cannot show the default white/BgColor strip above the title.
        winEnd := InStr(ui.xaml, ">")
        if (winEnd) {
            head := SubStr(ui.xaml, 1, winEnd)
            head := StrReplace(head, 'Background="Transparent"', 'Background="{DynamicResource TitleBarColor}"')
            ui.xaml := head SubStr(ui.xaml, winEnd + 1)
        }
        resources := fluidContent ? '<Boolean xmlns="clr-namespace:System;assembly=mscorlib" x:Key="RmtFluidDialogLayout">True</Boolean>' : ""
        ui.xaml := StrReplace(ui.xaml, "%resources%", resources)
        ui.OnEvent("BtnClosePanel", "Click", (*) => ui.Update("Window", "Close", ""))
        ui.OnEvent("Window", "LoadedHwnd", (*) => XamlWin.OnLoadTheme(ui))
        return ui
    }

    static Owner(obj) {
        if (!IsObject(obj))
            return ""
        if (obj.HasProp("OwnerHwnd") && obj.OwnerHwnd != "")
            return obj.OwnerHwnd
        if (obj.HasProp("ParentHwnd") && obj.ParentHwnd != "")
            return obj.ParentHwnd
        return ""
    }

    ; 弹窗该挂哪个窗口当属主：优先当前前台窗口（必须是本进程、可见、非透明浮层/工具窗），
    ; 否则退回主窗口。固定挂主窗口会让「从配置管理点导出」的弹窗最后把主窗口顶上来，
    ; 反而把配置管理压到最底下。
    static ActiveOwner() {
        fg := 0
        try fg := DllCall("user32\GetForegroundWindow", "Ptr")
        if (fg) {
            pid := 0
            try DllCall("user32\GetWindowThreadProcessId", "Ptr", fg, "UInt*", &pid)
            ex := 0
            try ex := DllCall("user32\GetWindowLongPtrW", "Ptr", fg, "Int", -20, "Ptr")
            ; WS_EX_LAYERED：轮盘、提示、悬浮信息这类透明浮层，不做属主
            isOverlay := (ex & 0x80000) ? true : false
            if (pid && pid == ProcessExist() && !isOverlay && DllCall("user32\IsWindowVisible", "Ptr", fg, "Int"))
                return fg
        }
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.wpfHwnd)
                return MyMainWin.ui.wpfHwnd
        }
        return 0
    }

    static QueueTheme(ui) {
        if (!IsObject(ui))
            return
        ui._xamlThemeQueued := true
        try {
            themeName := "RMT_Light"
            if (IsSet(MainSoftData) && IsObject(MainSoftData) && MainSoftData.HasProp("Theme") && MainSoftData.Theme != "")
                themeName := MainSoftData.Theme
            ApplyXamlTheme(ui, themeName)
        } catch {
        }
    }

    ; OnWindowLoad：开窗已入队则跳过，避免揭盖后再刷主题
    static OnLoadTheme(ui) {
        if (!IsObject(ui))
            return
        if (ui.HasProp("_xamlThemeQueued") && ui._xamlThemeQueued)
            return
        XamlWin.QueueTheme(ui)
    }

    static Reveal(ui) {
        if (!IsObject(ui))
            return
        try ui.Update("Window", "Opacity", "1")
    }

    ; 算窗口落点写进 XAML 的 Left/Top —— 引擎揭盖时会照 XAML 里的 Left/Top 定位
    ; （没写时它按 SizeToContent 窗口的高 600 兜底算，小窗就会明显偏上）。
    ; 尺寸仍由 SizeToContent 决定，这里的高度只用来算落点，估偏了只差几像素，不会裁内容。
    ; 入参是设计尺寸（DIP，未乘主界面缩放），返回 DIP —— 引擎揭盖时会再乘一次 DPI 缩放。
    static PresetPos(designW, designH, refHwnd := 0) {
        uiScale := 1.0
        try uiScale := XAMLHost.GetMainViewboxScale()
        if (!(uiScale > 1.001))
            uiScale := 1.0
        dpi := 96
        try dpi := A_ScreenDPI
        scale := dpi / 96

        l := 0, t := 0, r := 0, b := 0
        ref := (refHwnd && DllCall("user32\IsWindow", "Ptr", refHwnd, "Int")) ? refHwnd : 0
        mon := DllCall("user32\MonitorFromWindow", "Ptr", ref, "UInt", 2, "Ptr")
        if (mon) {
            mi := Buffer(40, 0)
            NumPut("UInt", 40, mi, 0)
            if (DllCall("user32\GetMonitorInfoW", "Ptr", mon, "Ptr", mi, "Int")) {
                l := NumGet(mi, 20, "Int"), t := NumGet(mi, 24, "Int")
                r := NumGet(mi, 28, "Int"), b := NumGet(mi, 32, "Int")
            }
        }
        if (r <= l || b <= t)
            return ""
        wPhys := designW * uiScale * scale
        hPhys := designH * uiScale * scale
        x := l + (r - l - wPhys) / 2
        y := t + (b - t - hPhys) / 2
        return { Left: Round(x / scale, 1), Top: Round(y / scale, 1) }
    }

    ; 把 PresetPos 结果拼成 XAML 属性片段；算不出来就返回空串（退回引擎默认落点）
    static PosAttr(designW, designH, refHwnd := 0) {
        pos := XamlWin.PresetPos(designW, designH, refHwnd)
        if (!IsObject(pos))
            return ""
        return ' Left="' pos.Left '" Top="' pos.Top '"'
    }

    ; 揭盖后校验：落点与目标偏差超过 tol 才纠正。
    ; tol 给 40px 是有意的 —— 估算高度总会差几十 DIP，对应落点偏移只有一半，
    ; 落在容差内就不动（不动 = 打开即到位，没有可见的重新定位）；只有 DPI/缩放算错这种大偏差才纠正。
    static NudgeIfOff(ui, refHwnd := 0, tol := 40) {
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd)
            return
        hwnd := ui.wpfHwnd
        rc := Buffer(16, 0)
        if (!DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc, "Int"))
            return
        w := NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int")
        h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")
        l := NumGet(rc, 0, "Int"), t := NumGet(rc, 4, "Int")
        ; 目标 = 参考窗口所在显示器工作区居中
        ref := (refHwnd && DllCall("user32\IsWindow", "Ptr", refHwnd, "Int")) ? refHwnd : hwnd
        mon := DllCall("user32\MonitorFromWindow", "Ptr", ref, "UInt", 2, "Ptr")
        if (!mon)
            return
        mi := Buffer(40, 0)
        NumPut("UInt", 40, mi, 0)
        if (!DllCall("user32\GetMonitorInfoW", "Ptr", mon, "Ptr", mi, "Int"))
            return
        wl := NumGet(mi, 20, "Int"), wt := NumGet(mi, 24, "Int")
        wr := NumGet(mi, 28, "Int"), wb := NumGet(mi, 32, "Int")
        tx := wl + (wr - wl - w) // 2
        ty := wt + (wb - wt - h) // 2
        if (Abs(tx - l) <= tol && Abs(ty - t) <= tol)
            return
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", tx, "Int", ty
            , "Int", 0, "Int", 0, "UInt", 0x0001 | 0x0004)
    }

    ; fill：Show 前入队内容的回调（Func / BoundFunc / 有 Call 的对象）
    static Open(ui, fill := "", ownerHwnd := "", activate := true) {
        if (!IsObject(ui))
            return false
        XamlWin.QueueTheme(ui)
        if (fill != "") {
            try {
                if (HasMethod(fill, "Call"))
                    fill.Call()
            } catch {
            }
        }
        ; Set the native owner in CREATE_WINDOW, before the hidden window is shown.
        ; Applying it after reveal changes z-order/activation and produces visible flashes.
        if (ownerHwnd != "")
            ui.ownerHwnd := ownerHwnd
        ui.Show()
        return XamlWin.WaitHwnd(ui, ownerHwnd, activate)
    }

    static WaitHwnd(ui, ownerHwnd := "", activate := true) {
        if (!IsObject(ui))
            return false
        ; 属主标记：_EnforceIndependent 靠它判断「这窗有属主，别清」。
        ; 弹窗（ShowInTaskbar="False"）以前不设这个标记，2 秒后就被当成独立窗清掉属主并
        ; hide/show 一遍，看起来就是「窗口闪一下、慢半拍」。所有窗口一律记上。
        ui._modalOwner := ownerHwnd
        ; 探 HWND：头部密一点（窗口多半这时已建好），之后放宽，总上限仍是 2 秒
        loop 80 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
                popup := InStr(ui.xaml, 'ShowInTaskbar="False"')
                if (!popup) {
                    owner := DllCall("user32\GetWindowLongPtrW", "Ptr", ui.wpfHwnd, "Int", -8, "Ptr")
                    if (ownerHwnd != "") {
                        ; 模态窗口：保留/补设属主（永远压在主窗口上方）
                        if (owner == 0)
                            try ui.Update("Window", "NativeOwner", String(ownerHwnd))
                    } else if (owner != 0) {
                        ; 非模态：解除属主（daemon 创建时可能已设），成为独立顶级窗口
                        DllCall("user32\SetWindowLongPtrW", "Ptr", ui.wpfHwnd, "Int", -8, "Ptr", 0)
                        DllCall("user32\ShowWindow", "Ptr", ui.wpfHwnd, "Int", 0)
                        DllCall("user32\ShowWindow", "Ptr", ui.wpfHwnd, "Int", 8)
                    }
                    ; 有属主 + APPWINDOW = 既有自己的任务栏按钮/Alt+Tab，又保持压主窗口上方；
                    ; 无属主 + APPWINDOW = 独立窗口的任务栏按钮确定性存在
                    ; daemon 现在在 Show 之前就打好了这个位（ApplyTaskbarExStyle），走到这里通常
                    ; 是引擎没升级的兜底：补位后必须 hide/show 才生效，这一步实测要 125ms。
                    ex := DllCall("user32\GetWindowLongPtrW", "Ptr", ui.wpfHwnd, "Int", -20, "Ptr")
                    if (!(ex & 0x40000)) {
                        DllCall("user32\SetWindowLongPtrW", "Ptr", ui.wpfHwnd, "Int", -20, "Ptr", ex | 0x40000)
                        DllCall("user32\SetWindowPos", "Ptr", ui.wpfHwnd, "Ptr", 0
                            , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x37)
                        DllCall("user32\ShowWindow", "Ptr", ui.wpfHwnd, "Int", 0)
                        DllCall("user32\ShowWindow", "Ptr", ui.wpfHwnd, "Int", 8)
                    }
                }
                ; 揭盖：不透明窗（Opacity="0"）已由 LoadedHwnd 在「更新队列+字号刷完」后揭过，
                ; 这里只给非自动揭盖窗口兜底；_skipAutoReveal（最小化启动等刻意隐藏）不揭
                autoReveal := InStr(ui.xaml, 'Opacity="0"') && !InStr(ui.xaml, 'AllowsTransparency="True"')
                skipReveal := ui.HasOwnProp("_skipAutoReveal") && ui._skipAutoReveal
                if (!autoReveal && !skipReveal)
                    XamlWin.Reveal(ui)
                if (activate) {
                    ; daemon 的 Show 自己就会激活窗口，此刻窗口已经在屏上。AHK 再同步调一次
                    ; SetForegroundWindow / WinActivate 是重复动作，而且跨进程这一步要等 125ms。
                    ; 改成返回之后再看一眼：已经是前台就什么都不做，不是才补一次。
                    XamlWin._DeferActivate(ui)
                }
                ; 前2秒每200ms重申 Opacity=1：防 daemon 异步应用 XAML 里的 Opacity="0"
                ; 覆盖揭盖（win32 全绿但窗口看不见时的最后嫌疑人）
                stompFn := ObjBindMethod(XamlWin, "_StompOpacity", ui)
                ui._stompFn := stompFn
                SetTimer(stompFn, 200)
                ; 兜底：daemon 若事后异步改属主，2s/5s 后自动反制（一次性）
                SetTimer(() => XamlWin._EnforceIndependent(ui), -2000)
                SetTimer(() => XamlWin._EnforceIndependent(ui), -5000)
                return true
            }
            ; 前 40 轮 5ms、之后 20ms：Sleep 的实际粒度常被系统 timer 分辨率拉到 15ms 以上，
            ; 而窗口句柄通常在 200~700ms 才由 daemon 回传，密集探测能省掉「多睡一轮」的延迟
            Sleep(A_Index <= 40 ? 5 : 20)
        }
        return false
    }

    ; 开窗不在这里同步激活，交给消息循环下一轮再看（见 WaitHwnd 里的说明）。
    static _DeferActivate(ui) {
        SetTimer(ObjBindMethod(XamlWin, "_DoDeferActivate", ui), -1)
    }

    static _DoDeferActivate(ui) {
        try {
            if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd)
                return
            hw := ui.wpfHwnd
            if (DllCall("user32\GetForegroundWindow", "Ptr") == hw)
                return
            ; 不用 WinActivate：它内部「等窗口真的变前台」的循环粒度很粗，实测恒定 125ms。
            ; 自己每 5ms 探一次，拿到前台立刻返回（实测 16ms）。
            t := A_TickCount
            DllCall("user32\SetForegroundWindow", "Ptr", hw)
            while (A_TickCount - t < 400) {
                if (DllCall("user32\GetForegroundWindow", "Ptr") == hw)
                    break
                Sleep(5)
            }
        }
    }

    ; 窗口是否已经在屏上且完全不透明（layered 窗口读 LWA_ALPHA）
    static _IsOpaqueVisible(hwnd) {
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd, "Int"))
            return false
        if (!DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int"))
            return false
        ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
        if (!(ex & 0x80000))          ; WS_EX_LAYERED：没分层就是全不透明
            return true
        alpha := 255, flags := 0, crKey := 0
        if (DllCall("user32\GetLayeredWindowAttributes", "Ptr", hwnd, "UInt*", &crKey, "UChar*", &alpha, "UInt*", &flags)) {
            if (flags & 0x2)          ; LWA_ALPHA
                return alpha >= 250
        }
        return true
    }

    ; 前2秒重申 Opacity=1（次数到或窗口已正常显示就自停）
    ; 每次都发同步 IPC：若前一个窗口的定时器还在跑，碰上 daemon 正在建新窗口就会把
    ; AHK 主线程卡住几百毫秒（表现就是「开窗慢半拍」）。所以先廉价查一次窗口状态，
    ; 已经可见且不透明就立刻收手，一次 IPC 都不发。
    static _StompOpacity(ui) {
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd) {
            if (IsObject(ui) && ui.HasProp("_stompFn"))
                SetTimer(ui._stompFn, 0)
            return
        }
        n := 0
        try n := Integer(ui._stompN) + 1
        ui._stompN := n
        if (XamlWin._IsOpaqueVisible(ui.wpfHwnd) || n >= 6) {
            SetTimer(ui._stompFn, 0)
            return
        }
        try ui.Update("Window", "Opacity", "1")
    }

    ; 开窗后的状态兜底：非模态窗口保持独立身份（属主被异步设回则解除）；
    ; 模态窗口保留属主（压主窗口上方）。两种都恢复独立任务栏按钮，
    ; 反制引擎 RmtTaskbarGroup 的 DeleteTab/RegisterTab 折叠。
    static _EnforceIndependent(ui) {
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd)
            return
        try {
            hwnd := ui.wpfHwnd
            ; 重申渲染层状态，防 daemon 异步覆盖（已正常显示就不发，省两次同步 IPC）
            if (!XamlWin._IsOpaqueVisible(hwnd)) {
                try ui.Update("Window", "Opacity", "1")
                try ui.Update("Window", "Visibility", "Visible")
            }
            modal := ui.HasProp("_modalOwner") && ui._modalOwner != ""
            owner := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -8, "Ptr")
            if (!modal && owner != 0) {
                DllCall("user32\SetWindowLongPtrW", "Ptr", hwnd, "Int", -8, "Ptr", 0)
                DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 0)
                DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 8)
                try WinActivate("ahk_id " hwnd)
            }
            ; 引擎 RmtTaskbarGroup 会在窗口 Loaded 后把非主窗口 DeleteTab 并 RegisterTab
            ; 成主窗口按钮下的标签页（预览挂主按钮下、无自身按钮、Alt+Tab 缺席）。
            ; 反向操作：DeleteTab 撤销标签注册 + AddTab 恢复独立任务栏按钮。
            if (!InStr(ui.xaml, 'ShowInTaskbar="False"')) {
                XamlWin._TabOp(hwnd, 5)   ; ITaskbarList::DeleteTab
                XamlWin._TabOp(hwnd, 4)   ; ITaskbarList::AddTab
            }
        }
    }

    ; ITaskbarList 薄封装：slot 3=HrInit 4=AddTab 5=DeleteTab
    static _tl := 0
    static _TabOp(hwnd, slot) {
        try {
            if (!XamlWin._tl) {
                clsid := Buffer(16), iid := Buffer(16)
                DllCall("ole32\CLSIDFromString", "WStr", "{56FDF344-FD6D-11d0-958A-006097C9A090}", "Ptr", clsid)
                DllCall("ole32\IIDFromString", "WStr", "{56FDF342-FD6D-11d0-958A-006097C9A090}", "Ptr", iid)
                p := 0
                hr := DllCall("ole32\CoCreateInstance", "Ptr", clsid, "Ptr", 0, "UInt", 1, "Ptr", iid, "Ptr*", &p, "HRESULT")
                if (hr != 0 || !p)
                    return
                v := NumGet(NumGet(p, "Ptr"), 3 * A_PtrSize, "Ptr")
                DllCall(v, "Ptr", p, "HRESULT")
                XamlWin._tl := p
            }
            v := NumGet(NumGet(XamlWin._tl, "Ptr"), slot * A_PtrSize, "Ptr")
            DllCall(v, "Ptr", XamlWin._tl, "Ptr", hwnd, "HRESULT")
        }
    }
}
