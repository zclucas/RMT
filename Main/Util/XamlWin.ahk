#Requires AutoHotkey v2.0

; =============================================================================
; XamlWin — 所有 XAML 子窗统一开窗：先入队主题/内容，再 Show
;
; 主题、内容和首帧绘制完成后才显示窗口：
;   1. Show 前 ApplyXamlTheme + 填表，Update 进 _updateQueue
;   2. Show 将排队的最终主题色写进 XAML，首帧即使用当前配色
;   3. LoadedHwnd 一次刷入其余更新、字号和回调内容，然后通知引擎初始化完成
;   4. 引擎等 WPF 绘制完成后揭示窗口；OnWindowLoad 不再重复 ApplyXamlTheme
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
        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" ShowInTaskbar="False" Width="' Round(width * visualScale) '" Height="' Round(height * visualScale) '"')
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

    ; 弹窗该挂哪个窗口当属主：当前用户正在用的那一层（搜索 Pro / 宏编辑 / 主窗口）。
    ; XAML 窗口在引擎进程里，不能只认本进程，否则会退回主窗口。
    ; 属主一旦是主窗口，系统显示弹窗时会把主窗口和它直接拥有的宏编辑一起抬上来，
    ; 更深一层（搜索 Pro）就被压到主窗口下面。
    static ActiveOwner() {
        fg := 0
        try fg := DllCall("user32\GetForegroundWindow", "Ptr")
        if (XamlWin._IsStackWindow(fg))
            return fg
        for hwnd in XamlWin.AppZOrder() {
            ex := 0
            try ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
            if (ex & 0x8)   ; WS_EX_TOPMOST：悬浮面板，不当普通弹窗的属主
                continue
            return hwnd
        }
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.wpfHwnd)
                return MyMainWin.ui.wpfHwnd
        }
        return 0
    }

    ; 调用方传了更底层的属主（常见是主窗口）时，改挂当前最上面的业务窗口。
    ; 这样禁用属主、关闭后激活属主，都回到用户正在编辑的那一层。
    static ModalOwner(requested := 0) {
        if (Type(requested) = "String") {
            if (requested = "" || requested = "0" || !IsInteger(requested))
                requested := 0
            else
                requested := Integer(requested)
        }
        top := XamlWin.ActiveOwner()
        if (!requested || !DllCall("user32\IsWindow", "Ptr", requested, "Int"))
            return top ? top : 0
        ; 调用方给的属主已经在更底层（例如主窗口），弹窗仍挂到当前最上面的编辑窗
        if (top && requested != top && XamlWin._IsAbove(top, requested))
            return top
        return requested
    }

    static _IsAbove(above, below) {
        if (!above || !below || above = below)
            return false
        hwnd := DllCall("user32\GetTopWindow", "Ptr", 0, "Ptr")
        seen := Map()
        loop 400 {
            if (!hwnd || seen.Has(hwnd))
                return false
            seen[hwnd] := true
            if (hwnd = above)
                return true
            if (hwnd = below)
                return false
            hwnd := DllCall("user32\GetWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        }
        return false
    }

    ; 自上而下的业务窗口（不含置顶浮层）。弹窗出现前记一笔，用来把被系统打乱的层级压回去。
    static AppZOrder() {
        list := []
        hwnd := DllCall("user32\GetTopWindow", "Ptr", 0, "Ptr")
        seen := Map()
        loop 400 {
            if (!hwnd || seen.Has(hwnd))
                break
            seen[hwnd] := true
            if (XamlWin._IsOrderWindow(hwnd))
                list.Push(hwnd)
            hwnd := DllCall("user32\GetWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        }
        return list
    }

    static _DaemonPid() {
        hwnd := 0
        try {
            if (IsSet(XAMLHost) && XAMLHost.daemonHwnd)
                hwnd := XAMLHost.daemonHwnd
        }
        if (!hwnd)
            return 0
        pid := 0
        DllCall("user32\GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
        return pid
    }

    static _IsAppPid(pid) {
        if (!pid)
            return false
        if (pid == ProcessExist())
            return true
        daemon := XamlWin._DaemonPid()
        return daemon && pid == daemon
    }

    static _IsCloaked(hwnd) {
        try {
            cloaked := 0
            hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4, "Int")
            return hr = 0 && cloaked
        } catch {
            return false
        }
    }

    ; 可参与层级记录的窗口：本程序或 XAML 引擎的可见顶级窗，排除透明浮层和工具窗。
    static _IsStackWindow(hwnd) {
        if (!hwnd || !DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int") || XamlWin._IsCloaked(hwnd))
            return false
        ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
        if (ex & 0x80000)   ; WS_EX_LAYERED
            return false
        if (ex & 0x80)      ; WS_EX_TOOLWINDOW
            return false
        rc := Buffer(16, 0)
        if (!DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rc, "Int"))
            return false
        if (NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int") < 8 || NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int") < 8)
            return false
        pid := 0
        DllCall("user32\GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
        return XamlWin._IsAppPid(pid)
    }

    ; 参与「压回原顺序」的窗口。置顶浮层保持原样，避免被摘掉置顶。
    static _IsOrderWindow(hwnd) {
        if (!XamlWin._IsStackWindow(hwnd))
            return false
        ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
        return !(ex & 0x8)
    }

    static _IsPopupUi(ui) {
        if (!IsObject(ui) || !ui.HasProp("xaml"))
            return false
        return InStr(ui.xaml, 'ShowInTaskbar="False"') && !InStr(ui.xaml, 'Topmost="True"')
    }

    ; 弹窗上方若还有「不属于这次打开前那叠窗口」的普通窗（别的程序，或后开的弹窗），就不要抢层级。
    static _BlockedByOutsider(dialog, stack) {
        mine := Map()
        if (dialog)
            mine[dialog] := true
        if (IsObject(stack)) {
            for hwnd in stack
                mine[hwnd] := true
        }
        hwnd := DllCall("user32\GetTopWindow", "Ptr", 0, "Ptr")
        seen := Map()
        loop 400 {
            if (!hwnd || seen.Has(hwnd))
                return false
            seen[hwnd] := true
            if (dialog && hwnd = dialog)
                return false
            if (XamlWin._IsPlainTop(hwnd) && !mine.Has(hwnd))
                return true
            hwnd := DllCall("user32\GetWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        }
        return false
    }

    static _IsPlainTop(hwnd) {
        if (!hwnd || !DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int") || XamlWin._IsCloaked(hwnd))
            return false
        ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
        return !(ex & 0x80088)   ; TOPMOST | TOOLWINDOW | LAYERED
    }

    static _OrderOk(dialog, stack) {
        expected := []
        if (dialog && DllCall("user32\IsWindow", "Ptr", dialog, "Int") && DllCall("user32\IsWindowVisible", "Ptr", dialog, "Int"))
            expected.Push(dialog)
        if (IsObject(stack)) {
            for hwnd in stack {
                if (!hwnd || hwnd = dialog)
                    continue
                if (!DllCall("user32\IsWindow", "Ptr", hwnd, "Int") || !DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int"))
                    continue
                if (!XamlWin._IsOrderWindow(hwnd))
                    continue
                expected.Push(hwnd)
            }
        }
        if (expected.Length < 2)
            return true
        need := Map()
        for h in expected
            need[h] := true
        got := []
        hwnd := DllCall("user32\GetTopWindow", "Ptr", 0, "Ptr")
        seen := Map()
        loop 400 {
            if (!hwnd || seen.Has(hwnd) || got.Length >= expected.Length)
                break
            seen[hwnd] := true
            if (need.Has(hwnd))
                got.Push(hwnd)
            hwnd := DllCall("user32\GetWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        }
        if (got.Length != expected.Length)
            return false
        loop got.Length
            if (got[A_Index] != expected[A_Index])
                return false
        return true
    }

    ; 弹窗打开后系统会激活属主链，把宏编辑/主窗口插到当前编辑窗前面。这里按打开前的顺序压回去：
    ; 弹窗、当时最前面的编辑窗、再往下的各层。
    static HoldModalOrder(dialog, stack) {
        if (!dialog || !DllCall("user32\IsWindow", "Ptr", dialog, "Int"))
            return
        if (XamlWin._BlockedByOutsider(dialog, stack))
            return
        if (XamlWin._OrderOk(dialog, stack))
            return
        ; NOSIZE | NOMOVE | NOACTIVATE | NOOWNERZORDER | NOCOPYBITS
        flags := 0x0313
        DllCall("user32\SetWindowPos", "Ptr", dialog, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", flags)
        prev := dialog
        if (!IsObject(stack))
            return
        for hwnd in stack {
            if (!hwnd || hwnd = dialog)
                continue
            if (!DllCall("user32\IsWindow", "Ptr", hwnd, "Int") || !DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int"))
                continue
            if (!XamlWin._IsOrderWindow(hwnd))
                continue
            DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", prev, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", flags)
            prev := hwnd
        }
    }

    static _ArmModalGuard(ui) {
        if (!IsObject(ui))
            return
        fn := ObjBindMethod(XamlWin, "_ModalGuardTick", ui)
        ui._modalGuardFn := fn
        SetTimer(fn, 50)
        XamlWin._ModalGuardTick(ui)
    }

    static _ModalGuardTick(ui) {
        if (!IsObject(ui) || !ui.HasProp("_modalGuardFn"))
            return
        hwnd := (ui.HasProp("wpfHwnd") && ui.wpfHwnd) ? ui.wpfHwnd : 0
        ; 句柄销毁才停。揭盖前窗口会短暂不可见，这时停掉定时器，后面的层级就没人管了。
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd, "Int")) {
            fn := ui._modalGuardFn
            ui._modalGuardFn := ""
            SetTimer(fn, 0)
            return
        }
        if (!DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int"))
            return
        stack := ui.HasProp("_modalStack") ? ui._modalStack : []
        XamlWin.HoldModalOrder(hwnd, stack)
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
        ; 只有提示/确认这种短弹窗打 _holdZOrder。界面浮窗同样不进任务栏，不能拿来锁整叠窗口。
        ; 本身已经置顶的弹窗不再改层级，避免把置顶标志清掉。
        xaml := ui.HasProp("xaml") ? ui.xaml : ""
        if (ui.HasProp("_holdZOrder") && ui._holdZOrder && !InStr(xaml, 'Topmost="True"')) {
            ownerHwnd := XamlWin.ModalOwner(ownerHwnd)
            ui._modalStack := XamlWin.AppZOrder()
        }
        ; Set the native owner in CREATE_WINDOW, before the hidden window is shown.
        ; Applying it after reveal changes z-order/activation and produces visible flashes.
        if (ownerHwnd != "")
            ui.ownerHwnd := ownerHwnd
        ui.Show()
        ok := XamlWin.WaitHwnd(ui, ownerHwnd, activate)
        if (ok && ui.HasProp("_modalStack"))
            XamlWin._ArmModalGuard(ui)
        return ok
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
                if (activate) {
                    ; daemon 的 Show 自己就会激活窗口，此刻窗口已经在屏上。AHK 再同步调一次
                    ; SetForegroundWindow / WinActivate 是重复动作，而且跨进程这一步要等 125ms。
                    ; 改成返回之后再看一眼：已经是前台就什么都不做，不是才补一次。
                    XamlWin._DeferActivate(ui)
                }
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

    ; 开窗后的状态兜底：非模态窗口保持独立身份（属主被异步设回则解除）；
    ; 模态窗口保留属主（压主窗口上方）。两种都恢复独立任务栏按钮，
    ; 反制引擎 RmtTaskbarGroup 的 DeleteTab/RegisterTab 折叠。
    static _EnforceIndependent(ui) {
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd)
            return
        try {
            hwnd := ui.wpfHwnd
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
