#Requires AutoHotkey v2.0

class CursorOutputTip {
    static ui := ""
    static pending := ""
    static deadline := 0
    static visible := false
    static tick := ""

    static Show(text) {
        static flush := ObjBindMethod(CursorOutputTip, "_Flush")
        if (!this.tick)
            this.tick := ObjBindMethod(this, "_Tick")
        this.pending := String(text)
        ; Worker 消息和 XAML 事件回调都要先返回，再建窗。
        SetTimer(flush, -1)
    }

    static _Flush() {
        if (this.pending == "") {
            this._Close()
            return
        }
        if (!IsObject(this.ui)) {
            colors := MainSoftData.ThemeColors
            win := XAML_Generator("Window")
            win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
            win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
            win.WindowStyle("None").AllowsTransparency("True").Background("Transparent")
                .ShowInTaskbar("False").ShowActivated("False").Topmost("True").ResizeMode("NoResize")
                .WindowStartupLocation("Manual").Left(-20000).Top(-20000)
                .SizeToContent("WidthAndHeight").Opacity(0)
            border := win.Add("Border").Padding("8,4").CornerRadius(4).BorderThickness(1).MaxWidth(420)
                .Background(AppThemeUtil.ResolveColor(colors, "Win_InputBg"))
                .BorderBrush(AppThemeUtil.ResolveColor(colors, "Win_InputStroke"))
                .IsHitTestVisible("False")
            border.Add("TextBlock").Name("TipText").TextWrapping("Wrap")
                .Foreground(AppThemeUtil.ResolveColor(colors, "Win_InputText"))
                .FontFamily(MainSoftData.FontType).FontSize(XAMLHost.FontSize())
            this.ui := XAMLHost(win.ToString(), "", 0)
            this.ui.skipFontScale := true
            this.ui.Update("TipText", "Text", this.pending)
            try this.ui.Show()
            catch {
                this._Close()
                return
            }
        } else {
            this.ui.Update("TipText", "Text", this.pending)
        }
        this.deadline := A_TickCount + 5000
        SetTimer(this.tick, 16)
    }

    static _Tick() {
        if (A_TickCount >= this.deadline) {
            this._Close()
            return
        }
        hwnd := this.ui.wpfHwnd
        if (!hwnd)
            return
        if (!DllCall("user32\IsWindow", "Ptr", hwnd, "Int")) {
            this._Close()
            return
        }
        try WinGetPos(&winX, &winY, &width, &height, "ahk_id " hwnd)
        catch
            return
        if (width < 2 || height < 2)
            return
        point := Buffer(8)
        if (!DllCall("user32\GetCursorPos", "Ptr", point, "Int"))
            return
        x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
        monitor := DllCall("user32\MonitorFromPoint", "Int64", NumGet(point, "Int64"), "UInt", 2, "Ptr")
        info := Buffer(40, 0)
        NumPut("UInt", info.Size, info)
        if (!DllCall("user32\GetMonitorInfoW", "Ptr", monitor, "Ptr", info, "Int"))
            return
        left := NumGet(info, 20, "Int"), top := NumGet(info, 24, "Int")
        right := NumGet(info, 28, "Int"), bottom := NumGet(info, 32, "Int")
        targetX := x + 16 + width <= right ? x + 16 : x - width - 8
        targetY := y + 22 + height <= bottom ? y + 22 : y - height - 8
        targetX := Max(left, Min(right - width, targetX))
        targetY := Max(top, Min(bottom - height, targetY))
        if (winX != targetX || winY != targetY)
            DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", targetX, "Int", targetY,
                "Int", 0, "Int", 0, "UInt", 0x15)
        if (!this.visible) {
            WinSetExStyle("+0x080000A0", "ahk_id " hwnd) ; NOACTIVATE | TOOLWINDOW | TRANSPARENT
            this.ui.Update("Window", "Opacity", "1")
            this.visible := true
        }
    }

    static _Close() {
        SetTimer(this.tick, 0)
        if (IsObject(this.ui))
            try this.ui.Update("Window", "Close", "")
        this.ui := ""
        this.visible := false
    }
}
