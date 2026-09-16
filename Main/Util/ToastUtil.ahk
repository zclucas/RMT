#Requires AutoHotkey v2.0

; ============================================================
; 通用右下角提示窗口（Toast）
; 基于 AHK-XAML，在屏幕右下角显示一段信息，停留后向右移动并渐隐消失。
;
; 用法：
;   Toast.Show("已复制")              ; info 类型，默认停留 1.5 秒
;   Toast.Show("已复制", "success")   ; 指定类别（success / info / warning / error）
;   Toast.Show("已复制", "success", 2000) ; 指定类别 + 停留 2 秒
;   Toast.Show("已复制", 2000)        ; 兼容旧用法：纯数字视为 holdMs
;
;   Toast.Success("操作成功")         ; 绿色成功提示
;   Toast.Info("提示信息")            ; 蓝色信息提示（默认）
;   Toast.Warning("请注意")           ; 黄色警告提示
;   Toast.Error("发生错误")           ; 红色错误提示
;
;   Toast.HoldMs := 2000              ; 修改默认停留时长（毫秒）
; ============================================================
class Toast {
    static HoldMs := 1500    ; 默认停留时长（毫秒）
    static _inst := ""       ; 当前活动实例
    static _pending := ""    ; 延后开窗任务（避免 XAML Click 回调里同步 CREATE_WINDOW）

    ; ── 分类快捷方法 ──────────────────────────────────────────
    static Show(msg, typeOrHold := "", holdMs := 0) {
        ; 兼容：Toast.Show(msg) / Toast.Show(msg, "success") / Toast.Show(msg, 2000) / Toast.Show(msg, "error", 2000)
        if (IsNumber(typeOrHold)) {
            Toast._ShowTyped(msg, "info", Integer(typeOrHold))
            return
        }
        type := (typeOrHold == "") ? "info" : String(typeOrHold)
        Toast._ShowTyped(msg, type, holdMs)
    }
    static Success(msg, holdMs := 0) {
        Toast._ShowTyped(msg, "success", holdMs)
    }
    static Info(msg, holdMs := 0) {
        Toast._ShowTyped(msg, "info", holdMs)
    }
    static Warning(msg, holdMs := 0) {
        Toast._ShowTyped(msg, "warning", holdMs)
    }
    static Error(msg, holdMs := 0) {
        Toast._ShowTyped(msg, "error", holdMs)
    }

    ; ── 内部统一入口 ─────────────────────────────────────────
    static _ShowTyped(msg, type := "info", holdMs := 0) {
        msg := Trim(String(msg))
        if (msg == "")
            return
        ; 不能在 XAML Click/SendMessage 回调里同步 CREATE_WINDOW：会嵌套死锁，
        ; _SendToEngine 超时后 KillDaemon，表现为点按钮闪退。
        Toast._pending := { msg: msg, type: type, holdMs: holdMs }
        SetTimer(ObjBindMethod(Toast, "_FlushPending"), -1)
    }

    static _FlushPending(*) {
        job := Toast._pending
        Toast._pending := ""
        if (!IsObject(job))
            return
        ; 关闭仍在显示的旧提示，避免叠加
        if (IsObject(Toast._inst)) {
            try Toast._inst.Close()
            Toast._inst := ""
        }
        inst := Toast.Instance(job.msg, job.type, job.holdMs > 0 ? job.holdMs : Toast.HoldMs)
        Toast._inst := inst
        inst.Start()
    }

    ; ── 单个提示实例 ──────────────────────────────────────────
    class Instance {
        ui := ""
        msg := ""
        type := "info"       ; success / info / warning / error
        holdMs := 1500
        phase := ""          ; fadein / hold / fadeout
        phaseTick := 0
        gen := 0
        closed := false
        buildTick := 0
        curLeft := 0.0
        startLeft := 0.0
        lastW := 0
        lastH := 0
        restoreHwnd := 0     ; 提示出现前处于前台的活动窗口，展示后抢回焦点
        ownerHwnd := 0       ; 提示所属的编辑器窗口（定位跟随时使用），展示后不再复用 restoreHwnd
        _tickFn := ""
        fadeInMs := 120
        fadeOutMs := 320
        slideDIP := 48       ; 右移距离（逻辑像素）

        __New(msg, type, holdMs) {
            this.msg := msg
            this.type := (type == "") ? "info" : type
            this.holdMs := Max(1000, Min(3000, Integer(holdMs)))
        }

        ; 根据 type 返回 [icon前缀, fill, stroke, text] 四元素
        _TypeStyle() {
            switch this.type {
            case "success":
                return ["✔ ", "#FFF6FFED", "#FF95DE64", "#FF389E0D"]
            case "warning":
                return ["⚠ ", "#FFFFFBE6", "#FFE8D080", "#FFD46B08"]
            case "error":
                return ["✖ ", "#FFFFF2F0", "#FFFFCCC7", "#FFCF1322"]
            default: ; info
                return ["ℹ ", "", "", ""]   ; 空字符串 → 使用主题色
            }
        }

        Start() {
            style := this._TypeStyle()
            icon   := style[1]
            fillOv := style[2]
            strkOv := style[3]
            textOv := style[4]

            ; info 类型使用应用主题色，其他类型使用固定语义色
            fill   := (fillOv != "") ? fillOv : AppThemeUtil.GetWheelColor("NormalFill",   "#FFF0F7FF")
            stroke := (strkOv != "") ? strkOv : AppThemeUtil.GetWheelColor("NormalStroke", "#FF90CAF9")
            text   := (textOv != "") ? textOv : AppThemeUtil.GetWheelColor("NormalText",   "#CC1A365D")

            displayMsg := icon . this.msg

            win := XAML_Generator("Window")
            win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
            win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
            ; 先放到屏幕外，等尺寸稳定后再定位到右下角
            win.Left(-20000).Top(-20000)
            win.WindowStyle("None").AllowsTransparency("True").Background("{x:Null}")
            win.ShowInTaskbar("False").Topmost("True").ResizeMode("NoResize")
            win.ShowActivated("False").SizeToContent("WidthAndHeight")
            win.WindowStartupLocation("Manual").Opacity(0)

            border := win.Add("Border")
            border.CornerRadius(8).Background(fill).BorderBrush(stroke).BorderThickness(1)
            border.Padding("16,10,16,10").MaxWidth(380)
            border.IsHitTestVisible("False")

            ; 柔和投影
            eff := border.Add("Border.Effect").Add("DropShadowEffect")
            eff.BlurRadius(10).ShadowDepth(1).Opacity(0.35).SetProp("Color", "#66000000")

            lbl := border.Add("TextBlock")
            lbl.Text(displayMsg).TextWrapping("Wrap").Foreground(text)
            lbl.FontFamily("Segoe UI Variable Display, Segoe UI, Microsoft YaHei UI, sans-serif")
            lbl.FontSize(14)

            ; 记录展示前的前台窗口（通常是逻辑树编辑器），展示后抢回焦点
            this.restoreHwnd := WinGetID("A")
            if (this.restoreHwnd && !DllCall("user32\IsWindow", "Ptr", this.restoreHwnd, "Int"))
                this.restoreHwnd := 0
            ; 定位跟随用：保存编辑器窗口句柄，供 _Position 依据窗口所在屏幕定位（而不是鼠标所在屏幕）
            this.ownerHwnd := this.restoreHwnd
            XamlUiDiag("Toast.Start capture active=" WinGetID("A") " title=" WinGetTitle("A") " restore=" this.restoreHwnd, "focus")

            try {
                ; 将提示窗挂到展示前的前台窗口（如逻辑树编辑器）下，作为其 owner。
                ; 这样 WPF 用 ShowActivated=False 显示时不抢前台，关闭时桥接层也会把焦点还给 owner，
                ; 彻底避免每次粘贴时主界面短暂盖过编辑器造成闪烁。
                this.ui := XAMLHost(win.ToString(), "", this.restoreHwnd)
                this.ui.skipFontScale := true
                this.ui.Show()
            } catch as e {
                try {
                    dir := A_WorkingDir "\Log"
                    if !DirExist(dir)
                        DirCreate(dir)
                    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " Toast " e.Message "`n" e.Stack "`n`n", dir "\RmtDialog.log", "UTF-8")
                }
                this.ui := ""
                this.closed := true
                return
            }

            XamlUiDiag("Toast.Start after Show active=" WinGetID("A") " title=" WinGetTitle("A"), "focus")

            ; 展示后立刻抢回焦点（若被提示窗抢走），尽量缩短主界面盖过编辑器的时间，减少闪烁
            this._RestoreFocus()
            XamlUiDiag("Toast.Start after RestoreFocus active=" WinGetID("A") " title=" WinGetTitle("A"), "focus")

            this.buildTick := A_TickCount
            this.gen += 1
            SetTimer(ObjBindMethod(this, "_WaitHwnd", this.gen), -20)
        }

        ; 异步轮询 WPF 窗口句柄，就绪后定位并开始动画
        _WaitHwnd(gen) {
            if (gen != this.gen || this.closed)
                return
            if (!IsObject(this.ui))
                return
            ; 超时保护：引擎异常时静默清理
            if (A_TickCount - this.buildTick > 5000) {
                this.Close()
                return
            }
            if (!this.ui.wpfHwnd) {
                SetTimer(ObjBindMethod(this, "_WaitHwnd", gen), -20)
                return
            }
            XamlUiDiag("WaitHwnd wpfHwnd=" this.ui.wpfHwnd " active=" WinGetID("A") " title=" WinGetTitle("A"), "focus")
            ; 防止抢焦点 / 出现在 Alt-Tab 列表
            try {
                WinSetExStyle("+0x08000000", "ahk_id " this.ui.wpfHwnd) ; WS_EX_NOACTIVATE
                WinSetExStyle("+0x00000080", "ahk_id " this.ui.wpfHwnd) ; WS_EX_TOOLWINDOW
            }
            ; 兜底：若提示窗稍后才异步抢走焦点，再把焦点还给之前的前台窗口（如逻辑树编辑器）
            this._RestoreFocus()
            this._Position()
            this.phase := "fadein"
            this.phaseTick := A_TickCount
            this._tickFn := ObjBindMethod(this, "_Tick")
            SetTimer(this._tickFn, 16)
        }

        _Tick() {
            if (this.closed || !IsObject(this.ui) || !this.ui.wpfHwnd)
                return
            now := A_TickCount
            switch this.phase {
            case "fadein":
                ; SizeToContent 尺寸可能晚一帧稳定，尺寸变化时重新定位
                this._Position()
                t := (now - this.phaseTick) / this.fadeInMs
                if (t >= 1) {
                    this._SetOpacity(1)
                    this.phase := "hold"
                    this.phaseTick := now
                } else {
                    this._SetOpacity(t * t * (3 - 2 * t)) ; smoothstep 缓入
                }
            case "hold":
                if (now - this.phaseTick >= this.holdMs) {
                    this.phase := "fadeout"
                    this.phaseTick := now
                    this.startLeft := this.curLeft
                }
            case "fadeout":
                t := (now - this.phaseTick) / this.fadeOutMs
                if (t >= 1) {
                    this.Close()
                    return
                }
                e := t * t * (3 - 2 * t) ; smoothstep 缓动
                this._SetOpacity(1 - e)
                try this.ui.Update("Window", "Left", String(Round(this.startLeft + e * this.slideDIP, 1)))
            }
        }

        ; 抢回提示窗可能抢走的前台焦点。仅当焦点确实被抢走（当前前台不是原窗口）才激活原窗口，
        ; 避免每次粘贴都强制激活原窗口造成界面闪烁。
        _RestoreFocus() {
            if (!this.restoreHwnd)
                return
            XamlUiDiag("RestoreFocus restore=" this.restoreHwnd " active=" WinGetID("A") " title=" WinGetTitle("A"), "focus")
            try {
                if (WinGetID("A") != this.restoreHwnd) {
                    ; 用 SetForegroundWindow 直接抢回焦点。WinActivate 内部有约百毫秒的焦点抢占 hack 开销，
                    ; 会造成主界面短暂盖过编辑器（闪烁）。脚本进程本身持有前台时，此调用即时生效。
                    if (!DllCall("SetForegroundWindow", "Ptr", this.restoreHwnd))
                        WinActivate("ahk_id " this.restoreHwnd)
                }
            }
            this.restoreHwnd := 0
        }

        ; 定位到编辑器窗口所在屏幕的工作区右下角（跟随编辑器窗口所在屏幕，而非鼠标所在屏幕）
        _Position() {
            ; 防御：this.ui 可能因 Close()/Show() 失败被置为 ""（String），访问 wpfHwnd 会报错
            if (!IsObject(this.ui) || !this.ui.wpfHwnd)
                return
            ; 优先用 owner 窗口（逻辑树编辑器）中心点判断所在屏幕；取不到时退回鼠标位置
            px := 0, py := 0
            hasRef := false
            if (this.ownerHwnd) {
                try {
                    WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " this.ownerHwnd)
                    px := ox + ow // 2
                    py := oy + oh // 2
                    hasRef := true
                } catch {
                    hasRef := false
                }
            }
            if (!hasRef)
                MouseGetPos(&px, &py)

            monCount := MonitorGetCount()
            targetL := 0, targetT := 0, targetR := 0, targetB := 0
            found := false
            Loop monCount {
                MonitorGet(A_Index, &mL, &mT, &mR, &mB)
                if (px >= mL && px < mR && py >= mT && py < mB) {
                    MonitorGetWorkArea(A_Index, &targetL, &targetT, &targetR, &targetB)
                    found := true
                    break
                }
            }
            ; 兜底：未命中任意屏幕（极端情况）时用主屏
            if (!found)
                MonitorGetWorkArea(1, &targetL, &targetT, &targetR, &targetB)

            dpi := this._GetDpiScale((targetL + targetR) // 2, (targetT + targetB) // 2)
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " this.ui.wpfHwnd)
            if (ww <= 0 || wh <= 0)
                return
            if (ww == this.lastW && wh == this.lastH)
                return
            this.lastW := ww
            this.lastH := wh
            left := (targetR / dpi) - (ww / dpi) - 16
            top  := (targetB / dpi) - (wh / dpi) - 16
            try this.ui.Update("Window", "Left", String(Round(left, 1)))
            try this.ui.Update("Window", "Top", String(Round(top, 1)))
            this.curLeft := left
        }

        _GetDpiScale(x, y) {
            pt := Buffer(8, 0)
            NumPut("Int", x, pt, 0)
            NumPut("Int", y, pt, 4)
            hMon := DllCall("user32\MonitorFromPoint", "Ptr", pt, "UInt", 2, "Ptr")
            dpiX := 0, dpiY := 0
            DllCall("shcore\GetDpiForMonitor", "Ptr", hMon, "Int", 0, "UInt*", &dpiX, "UInt*", &dpiY)
            return (dpiX > 0) ? (dpiX / 96.0) : (A_ScreenDPI / 96.0)
        }

        _SetOpacity(o) {
            o := Max(0.0, Min(1.0, o))
            try this.ui.Update("Window", "Opacity", String(Round(o, 3)))
        }

        Close() {
            if (this.closed)
                return
            this.closed := true
            this.gen += 1
            if (this._tickFn) {
                SetTimer(this._tickFn, 0)
                this._tickFn := ""
            }
            if (IsObject(this.ui)) {
                try this.ui.Update("Window", "Close", "")
            }
            this.ui := ""
            if (Toast._inst == this)
                Toast._inst := ""
        }
    }
}