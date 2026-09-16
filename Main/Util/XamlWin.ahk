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
        loop 40 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
                XamlWin._DbgState(ui, "found")
                popup := InStr(ui.xaml, 'ShowInTaskbar="False"')
                if (!popup) {
                    ui._modalOwner := ownerHwnd
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
                    ex := DllCall("user32\GetWindowLongPtrW", "Ptr", ui.wpfHwnd, "Int", -20, "Ptr")
                    if (!(ex & 0x40000)) {
                        DllCall("user32\SetWindowLongPtrW", "Ptr", ui.wpfHwnd, "Int", -20, "Ptr", ex | 0x40000)
                        DllCall("user32\SetWindowPos", "Ptr", ui.wpfHwnd, "Ptr", 0
                            , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x37)
                        DllCall("user32\ShowWindow", "Ptr", ui.wpfHwnd, "Int", 0)
                        DllCall("user32\ShowWindow", "Ptr", ui.wpfHwnd, "Int", 8)
                    }
                    XamlWin._DbgState(ui, "after-owner-clear")
                }
                ; 揭盖：不透明窗（Opacity="0"）已由 LoadedHwnd 在「更新队列+字号刷完」后揭过，
                ; 这里只给非自动揭盖窗口兜底；_skipAutoReveal（最小化启动等刻意隐藏）不揭
                autoReveal := InStr(ui.xaml, 'Opacity="0"') && !InStr(ui.xaml, 'AllowsTransparency="True"')
                skipReveal := ui.HasOwnProp("_skipAutoReveal") && ui._skipAutoReveal
                if (!autoReveal && !skipReveal)
                    XamlWin.Reveal(ui)
                if (activate)
                    try WinActivate("ahk_id " ui.wpfHwnd)
                XamlWin._DbgState(ui, "after-reveal")
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
            Sleep(50)
        }
        return false
    }

    ; 前2秒重申 Opacity=1（10次后自停）
    static _StompOpacity(ui) {
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd) {
            if (IsObject(ui) && ui.HasProp("_stompFn"))
                SetTimer(ui._stompFn, 0)
            return
        }
        try ui.Update("Window", "Opacity", "1")
        n := 0
        try n := Integer(ui._stompN) + 1
        ui._stompN := n
        if (n >= 10)
            SetTimer(ui._stompFn, 0)
    }

    ; 开窗后的状态兜底：非模态窗口保持独立身份（属主被异步设回则解除）；
    ; 模态窗口保留属主（压主窗口上方）。两种都恢复独立任务栏按钮，
    ; 反制引擎 RmtTaskbarGroup 的 DeleteTab/RegisterTab 折叠。
    static _EnforceIndependent(ui) {
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd)
            return
        try {
            hwnd := ui.wpfHwnd
            ; 重申渲染层状态，防 daemon 异步覆盖
            try ui.Update("Window", "Opacity", "1")
            try ui.Update("Window", "Visibility", "Visible")
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
            XamlWin._DbgState(ui, "enforce")
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

    ; 诊断用：记录窗口可见性/属主/样式/位置/DWM裁剪/前台/主窗口状态快照
    static _DbgState(ui, tag) {
        try {
            hwnd := ui.wpfHwnd
            vis := DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int")
            owner := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -8, "Ptr")
            ex := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
            iconic := DllCall("user32\IsIconic", "Ptr", hwnd, "Int")
            cloak := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "Int", 14, "Int*", &cloak := 0, "Int", 4)  ; DWMWA_CLOAKED
            rect := Buffer(16)
            DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
            l := NumGet(rect, 0, "Int"), t := NumGet(rect, 4, "Int")
            r := NumGet(rect, 8, "Int"), b := NumGet(rect, 12, "Int")
            fg := DllCall("user32\GetForegroundWindow", "Ptr")
            ; 主窗口快照：是否置顶/可见/位置，判断子窗是否被压在主窗后面
            mainInfo := "n/a"
            try {
                if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.wpfHwnd) {
                    mh := MyMainWin.ui.wpfHwnd
                    mex := DllCall("user32\GetWindowLongPtrW", "Ptr", mh, "Int", -20, "Ptr")
                    mvis := DllCall("user32\IsWindowVisible", "Ptr", mh, "Int")
                    mrect := Buffer(16)
                    DllCall("user32\GetWindowRect", "Ptr", mh, "Ptr", mrect)
                    mainInfo := Format("hwnd={1:#x} top={2} vis={3} rect=({4},{5})-({6},{7})",
                        mh, (mex & 0x8) ? 1 : 0, mvis,
                        NumGet(mrect, 0, "Int"), NumGet(mrect, 4, "Int"), NumGet(mrect, 8, "Int"), NumGet(mrect, 12, "Int"))
                }
            }
            RMTLogSys(RMT_LV_INFO, "XamlWin", Format("[{1}] vis={2} owner={3:#x} ex={4:#x} iconic={5} cloak={6} fg={7:#x} rect=({8},{9})-({10},{11}) main[{12}]",
                tag, vis, owner, ex, iconic, cloak, fg, l, t, r, b, mainInfo))
        } catch as e {
            try RMTLogSys(RMT_LV_INFO, "XamlWin", "[" tag "] 日志失败: " e.Message)
        }
    }
}
