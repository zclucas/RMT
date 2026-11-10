#Requires AutoHotkey v2.0

QueuePromptDisplay(payload) {
    static queue := []
    static flush := FlushPromptDisplay.Bind(queue)
    queue.Push(payload)
    SetTimer(flush, -1)
    return true
}

FlushPromptDisplay(queue) {
    static running := false
    if (running)
        return
    running := true
    try {
        while (queue.Length) {
            try ShowPromptDisplay(JSON.parse(queue.RemoveAt(1), , false))
            catch as err
                RMTLogSys(RMT_LV_ERROR, "Prompt", err.Message)
        }
    } finally {
        running := false
        if (queue.Length)
            SetTimer(FlushPromptDisplay.Bind(queue), -1)
    }
}

ShowPromptDisplay(data) {
    switch data.Type {
        case "软件弹窗":
            MsgBoxContent(data.Text, GetLang("提示"))
        case "临时提示":
            if (data.TipMode == "图片")
                CursorOutputTip.Show(data.ImagePath, data.Duration, true, data.TemporaryImage)
            else
                CursorOutputTip.Show(data.Text, data.Duration)
        case "自由贴":
            switch data.PasteMode {
                case "关闭", "关闭所有":
                    MyFreePasteGui.ClosePrompt(data.PasteMode == "关闭所有", data.PasteName)
                case "图片":
                    MyFreePasteGui.ShowPrompt(true, data.ImagePath, data.PasteName, data.TemporaryImage)
                case "文本":
                    if (data.Text != "")
                        MyFreePasteGui.ShowPrompt(false, data.Text, data.PasteName)
            }
        case "区域高亮":
            overlay := PromptOutline(data.Color, data.Thickness)
            try {
                overlay.AddRect(data.PosX, data.PosY, data.Width, data.Height)
                if (data.Text != "")
                    overlay.AddCaption(data.PosX, data.PosY, data.Width, data.Text)
                overlay.Show(data.Duration)
            } catch {
                overlay.Close()
                throw
            }
        case "屏幕边缘闪光":
            overlay := PromptOutline(data.Color, data.Thickness)
            primary := MonitorGetPrimary()
            numbers := data.FlashMode == "自定义" ? PromptMonitorNumbers(data.Monitors) : []
            if (data.FlashMode != "自定义") {
                loop MonitorGetCount() {
                    if (data.FlashMode == "主副屏" || (A_Index == primary) == (data.FlashMode == "主屏"))
                        numbers.Push(A_Index)
                }
            }
            try {
                for number in numbers {
                    if (MonitorGet(number, &left, &top, &right, &bottom))
                        overlay.AddRect(left, top, right - left, bottom - top)
                }
                overlay.Show(data.FlashDuration, data.FlashCount)
            } catch {
                overlay.Close()
                throw
            }
    }
}

; 只创建边框和标签窗口，区域内部仍可正常操作。
class PromptOutline {
    __New(color, thickness) {
        this.color := color
        this.thickness := thickness
        this.windows := []
        this.timer := this.Tick.Bind(this)
    }

    AddRect(x, y, w, h) {
        t := Min(this.thickness, w, h)
        this.AddWindow(x, y, w, t)
        if (h > t)
            this.AddWindow(x, y + h - t, w, t)
        if (h > 2 * t) {
            this.AddWindow(x, y + t, t, h - 2 * t)
            if (w > t)
                this.AddWindow(x + w - t, y + t, t, h - 2 * t)
        }
    }

    AddCaption(x, y, width, label) {
        this.AddWindow(x, y, Max(120, Min(width, 360)), 32, label)
    }

    AddWindow(x, y, w, h, label := "") {
        panel := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale")
        DllCall("user32\SetLayeredWindowAttributes", "Ptr", panel.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2)
        panel.BackColor := this.color
        if (label != "") {
            rgb := Integer("0x" this.color)
            light := ((rgb >> 16) * 299 + ((rgb >> 8) & 255) * 587 + (rgb & 255) * 114) >= 128000
            panel.SetFont(light ? "s10 cBlack" : "s10 cWhite", "Segoe UI")
            panel.AddText("x6 y0 w" (w - 12) " h" h " +0x8200", label)
        }
        this.windows.Push({panel: panel, options: Format("NA x{} y{} w{} h{}", x, y, w, h)})
    }

    Show(duration, count := 1) {
        if (!this.windows.Length)
            return
        this.remaining := count
        this.duration := duration
        this.visible := false
        this.Tick()
    }

    Tick() {
        if (this.visible) {
            if (--this.remaining == 0) {
                this.Close()
                return
            }
            for item in this.windows
                item.panel.Hide()
        } else {
            for item in this.windows
                item.panel.Show(item.options)
        }
        this.visible := !this.visible
        SetTimer(this.timer, -this.duration)
    }

    Close() {
        SetTimer(this.timer, 0)
        for item in this.windows
            try item.panel.Destroy()
        this.windows := []
        this.timer := ""
    }
}
