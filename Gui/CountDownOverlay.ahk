#Requires AutoHotkey v2.0

; 仅主进程加载。Worker 通过 CD/CDR 消息管理浮层，不加载界面依赖。
global XamlCountDownWindows := Map()
global XamlCountDownCancelled := Map()

StartXamlCountDown(token, total, x, y, done, workerPid := 0) {
    global XamlCountDownWindows, XamlCountDownCancelled
    if (XamlCountDownCancelled.Has(token)) {
        XamlCountDownCancelled.Delete(token)
        done.Call()
        return
    }
    posKey := CountDownPosKey(x, y)
    previous := []
    for id, overlay in XamlCountDownWindows
        if (overlay.posKey == posKey)
            previous.Push(overlay)
    for overlay in previous
        overlay.Close()
    overlay := XamlCountDownOverlay(token, posKey, total, x, y, done)
    overlay.workerPid := workerPid
    XamlCountDownWindows[token] := overlay
    try overlay.Show()
    catch {
        overlay.Close()
        throw
    }
}

CloseXamlCountDownForWorker(pid) {
    global XamlCountDownWindows
    if (!pid)
        return
    overlays := []
    for token, overlay in XamlCountDownWindows
        if (overlay.workerPid == pid)
            overlays.Push(overlay)
    for overlay in overlays
        overlay.Close()
}

CloseXamlCountDown(token) {
    global XamlCountDownWindows, XamlCountDownCancelled
    if (XamlCountDownWindows.Has(token))
        XamlCountDownWindows[token].Close()
    else {
        ; start 与 stop 可能在建窗期间相遇，取消后不得迟到重开。
        XamlCountDownCancelled[token] := true
        SetTimer(() => ForgetXamlCountDownCancellation(token), -30000)
    }
}

ForgetXamlCountDownCancellation(token) {
    global XamlCountDownCancelled
    if (XamlCountDownCancelled.Has(token))
        XamlCountDownCancelled.Delete(token)
}

class XamlCountDownOverlay {
    __New(token, posKey, total, x, y, done) {
        this.token := token
        this.posKey := posKey
        this.total := total
        this.x := x, this.y := y
        this.done := done
        this.closed := false
        this.ui := ""
        this.timer := ObjBindMethod(this, "Tick")
        this.deadline := A_TickCount + total * 1000
    }

    Show() {
        size := CountDownOverlaySize(CountDownFormatMode(this.total))
        title := CountDownWinTitle(this.posKey)
        textColor := CountDownThemeRgb("text"), bg := CountDownThemeRgb("bg")
        fontSize := CountDownStyleFontSize()
        alpha := CountDownUiAlpha(CountDownStyleAlpha()) / 100
        xaml := '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
            . ' Title="' title '" Width="' size[1] '" Height="' size[2] '" Left="' this.x '" Top="' this.y '"'
            . ' WindowStartupLocation="Manual" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent"'
            . ' Topmost="True" ShowInTaskbar="False" ShowActivated="False" Focusable="False" Opacity="' alpha '">'
            . '<Border Background="#' bg '" CornerRadius="5" Padding="4">'
            . '<TextBlock x:Name="CountDownText" Text="' CountDownFormatText(this.total) '" FontFamily="Consolas" FontSize="' fontSize '"'
            . ' Foreground="#' textColor '" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></Window>'
        this.ui := XAMLHost(xaml)
        this.ui.skipFontScale := true
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnLoaded"))
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnClosing"))
        this.ui.Show()
        SetTimer(this.timer, 100)
    }

    OnLoaded(*) {
        if (this.closed) {
            try this.ui.Update("Window", "Close", "")
            return
        }
        hwnd := this.ui.wpfHwnd
        if (hwnd) {
            WinSetExStyle("+0x080000A0", "ahk_id " hwnd) ; 不激活、工具窗、鼠标穿透
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)
        }
        this.Tick()
    }

    Tick(*) {
        if (this.closed)
            return
        remaining := Max(0, Ceil((this.deadline - A_TickCount) / 1000))
        if (A_TickCount >= this.deadline + 1000) {
            this.Close()
            return
        }
        if (this.HasProp("lastSecond") && this.lastSecond == remaining)
            return
        this.lastSecond := remaining
        size := CountDownOverlaySize(CountDownFormatMode(remaining))
        ; 按字号扩展，避免大字号被固定尺寸裁切。
        width := Max(size[1], StrLen(CountDownFormatText(remaining)) * CountDownStyleFontSize() * 0.65 + 16)
        height := Max(size[2], CountDownStyleFontSize() * 1.5 + 12)
        this.ui.BatchUpdate([
            {ControlName: "CountDownText", PropertyName: "Text", Value: CountDownFormatText(remaining)},
            {ControlName: "Window", PropertyName: "Width", Value: width},
            {ControlName: "Window", PropertyName: "Height", Value: height}])
    }

    OnClosing(*) {
        this.Close(false)
    }

    Close(closeWindow := true, *) {
        global XamlCountDownWindows
        if (this.closed)
            return
        this.closed := true
        SetTimer(this.timer, 0)
        if (closeWindow && IsObject(this.ui))
            try this.ui.Update("Window", "Close", "")
        if (XamlCountDownWindows.Has(this.token))
            XamlCountDownWindows.Delete(this.token)
        this.done.Call()
    }
}
