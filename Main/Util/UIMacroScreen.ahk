#Requires AutoHotkey v2.0

; 跨进程坐标统一为屏幕物理像素。仅在 Win32 调用期间切换线程 DPI，
; 不改变原生界面或其他指令的 DPI 感知，异常时也恢复原上下文。
class UIMacroScreen {
    static _PointBits(x, y) => (Round(x) & 0xFFFFFFFF) | ((Round(y) & 0xFFFFFFFF) << 32)

    static _Enter() {
        previous := 0
        try previous := DllCall("user32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
        if (!previous)
            try previous := DllCall("user32\SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")
        return previous
    }

    static _Leave(previous) {
        if (previous)
            DllCall("user32\SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
    }

    static Rect(hwnd) {
        previous := this._Enter()
        try {
            rect := Buffer(16, 0)
            if (!DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect))
                throw OSError()
            return Map("left", NumGet(rect, 0, "Int"), "top", NumGet(rect, 4, "Int")
                , "right", NumGet(rect, 8, "Int"), "bottom", NumGet(rect, 12, "Int"))
        } finally {
            this._Leave(previous)
        }
    }

    static Move(hwnd, x, y) {
        previous := this._Enter()
        try return DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", x, "Int", y, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010)
        finally this._Leave(previous)
    }

    static GetPos(hwnd, &x, &y) {
        rect := this.Rect(hwnd)
        x := rect["left"], y := rect["top"]
    }

    static Cursor(&x, &y) {
        point := Buffer(8, 0)
        if (!DllCall("user32\GetPhysicalCursorPos", "Ptr", point))
            throw OSError()
        x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
    }

    static WindowAt(x, y) => DllCall("user32\WindowFromPhysicalPoint"
        , "Int64", this._PointBits(x, y), "Ptr")

    static PrimarySize(&w, &h) {
        previous := this._Enter()
        try {
            w := DllCall("user32\GetSystemMetrics", "Int", 0)
            h := DllCall("user32\GetSystemMetrics", "Int", 1)
        } finally {
            this._Leave(previous)
        }
    }

    static DpiAt(x, y) {
        previous := this._Enter()
        probe := 0
        try {
            ; 不能用目标游戏的 GetDpiForWindow（游戏可能只感知 96 DPI），也不能
            ; 从主屏 DPI 推算副屏。创建一个不显示的 PM 窗口，直接查询目标屏 DPI。
            if (previous) {
                probe := DllCall("user32\CreateWindowExW", "UInt", 0x80, "Str", "Static", "Str", ""
                    , "UInt", 0x88000000, "Int", x, "Int", y, "Int", 1, "Int", 1
                    , "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
                if (probe) {
                    dpi := DllCall("user32\GetDpiForWindow", "Ptr", probe, "UInt")
                    if (dpi > 0)
                        return dpi
                }
            }
            monitor := DllCall("user32\MonitorFromPoint", "Int64", this._PointBits(x, y), "UInt", 2, "Ptr")
            dx := 0, dy := 0
            try {
                if (DllCall("shcore\GetDpiForMonitor", "Ptr", monitor, "Int", 0, "UInt*", &dx, "UInt*", &dy) == 0 && dx > 0)
                    return dx
            }
            return A_ScreenDPI
        } finally {
            if (probe)
                DllCall("user32\DestroyWindow", "Ptr", probe)
            this._Leave(previous)
        }
    }

    static VirtualRect() {
        previous := this._Enter()
        try {
            x := DllCall("user32\GetSystemMetrics", "Int", 76) ; SM_XVIRTUALSCREEN
            y := DllCall("user32\GetSystemMetrics", "Int", 77) ; SM_YVIRTUALSCREEN
            w := DllCall("user32\GetSystemMetrics", "Int", 78) ; SM_CXVIRTUALSCREEN
            h := DllCall("user32\GetSystemMetrics", "Int", 79) ; SM_CYVIRTUALSCREEN
            return {x:x, y:y, w:w, h:h}
        } finally {
            this._Leave(previous)
        }
    }

    static MonitorRectAt(x, y) {
        previous := this._Enter()
        try {
            monitor := DllCall("user32\MonitorFromPoint", "Int64", this._PointBits(x, y), "UInt", 2, "Ptr")
            info := Buffer(40, 0)
            NumPut("UInt", 40, info)
            if (!DllCall("user32\GetMonitorInfoW", "Ptr", monitor, "Ptr", info))
                throw OSError()
            return Map("left", NumGet(info, 4, "Int"), "top", NumGet(info, 8, "Int")
                , "right", NumGet(info, 12, "Int"), "bottom", NumGet(info, 16, "Int"))
        } finally {
            this._Leave(previous)
        }
    }
}
