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
        case "音频":
            PromptPlayAudio(data.AudioPath)
        case "软件弹窗":
            MsgBoxContent(data.Text, GetLang("提示"))
        case "临时提示":
            if (data.TipMode == "图片")
                CursorOutputTip.Show(data.ImagePath, data.Duration, true, data.TemporaryImage)
            else
                CursorOutputTip.Show(data.Text, data.Duration)
        case "自由贴":
            center := data.HasProp("PastePosition") && (data.PastePosition == "固定位置" || data.PastePosition == "鼠标位置")
                && (data.PasteMode == "文本" || data.PasteMode == "图片") ? [data.PosX, data.PosY] : ""
            switch data.PasteMode {
                case "关闭", "关闭所有":
                    MyFreePasteGui.ClosePrompt(data.PasteMode == "关闭所有", data.PasteName)
                case "图片":
                    MyFreePasteGui.ShowPrompt(true, data.ImagePath, data.PasteName, data.TemporaryImage, center)
                case "文本":
                    if (data.Text != "")
                        MyFreePasteGui.ShowPrompt(false, data.Text, data.PasteName, false, center)
            }
        case "区域高亮":
            PromptRegionDisplay.Apply(data)
        case "屏幕边缘闪光":
            primary := MonitorGetPrimary()
            numbers := data.FlashMode == "自定义" ? PromptMonitorNumbers(data.Monitors) : []
            allScreens := data.FlashMode == "所有屏" || data.FlashMode == "主副屏"
            if (data.FlashMode != "自定义") {
                loop MonitorGetCount() {
                    if (allScreens || (A_Index == primary) == (data.FlashMode == "主屏"))
                        numbers.Push(A_Index)
                }
            }
            overlay := PromptEdgeFlash(data.Color, data.Thickness)
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

class PromptRegionDisplay {
    static Active := []

    static Apply(data) {
        name := data.HasProp("RegionName") ? data.RegionName : ""
        wasCritical := A_IsCritical
        Critical("On")
        try {
            if (data.HasProp("RegionMode") && data.RegionMode == "关闭") {
                this.Close(name)
                return
            }
            overlay := PromptOutline(data.Color, data.Thickness, this.Forget.Bind(this))
            try {
                overlay.AddRect(data.PosX, data.PosY, data.Width, data.Height)
                if (data.Text != "")
                    overlay.AddCaption(data.PosX, data.PosY, data.Width, data.Text)
                overlay.Show(data.Duration)
                if (name != "")
                    this.Close(name)
                this.Active.Push({Name: name, Overlay: overlay})
            } catch {
                overlay.Close()
                throw
            }
        } finally {
            Critical(wasCritical)
        }
    }

    static Close(name) {
        loop this.Active.Length {
            entry := this.Active[-A_Index]
            if (name == "" || entry.Name == name) {
                entry.Overlay.Close()
                return
            }
        }
    }

    static Forget(overlay) {
        for index, entry in this.Active {
            if (entry.Overlay == overlay) {
                this.Active.RemoveAt(index)
                return
            }
        }
    }
}

; 只创建边框和标签窗口，区域内部仍可正常操作。
class PromptOutline {
    __New(color, thickness, onClose := "") {
        this.color := color
        this.thickness := thickness
        this.windows := []
        this.timer := this.Tick.Bind(this)
        this.onClose := onClose
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
        timer := this.timer
        if (timer == "")
            return
        this.timer := ""
        SetTimer(timer, 0)
        if (this.onClose != "")
            this.onClose.Call(this)
        for item in this.windows
            try item.panel.Destroy()
        this.windows := []
    }
}

class PromptEdgeFlash extends PromptOutline {
    AddRect(x, y, w, h) {
        token := Gdip_Startup()
        if (!token)
            throw Error("GDI+ startup failed")
        hdc := 0, bitmap := 0, oldBitmap := 0, graphics := 0
        try {
            hdc := CreateCompatibleDC()
            bitmap := CreateDIBSection(w, h, hdc)
            if (!hdc || !bitmap)
                throw OSError()
            oldBitmap := SelectObject(hdc, bitmap)
            graphics := Gdip_GraphicsFromHDC(hdc)
            if (!oldBitmap || !graphics)
                throw Error("Could not create the screen flash surface")
            this.Paint(graphics, w, h)
            Gdip_DeleteGraphics(graphics)
            graphics := 0

            panel := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale")
            this.windows.Push({panel: panel, options: Format("NA x{} y{} w{} h{}", x, y, w, h)})
            if (!UpdateLayeredWindow(panel.Hwnd, hdc, x, y, w, h))
                throw OSError()
        } finally {
            if (graphics)
                Gdip_DeleteGraphics(graphics)
            if (oldBitmap)
                SelectObject(hdc, oldBitmap)
            if (bitmap)
                DeleteObject(bitmap)
            if (hdc)
                DeleteDC(hdc)
            Gdip_Shutdown(token)
        }
    }

    Paint(graphics, w, h) {
        rgb := Integer("0x" this.color)
        opaque := rgb | 0xFF000000
        ; 保留实色边框，渐变的透明终点距各边为对应屏幕尺寸的 10%。
        insetX := Min(this.thickness, Max(0, Floor(w * 0.1) - 1))
        insetY := Min(this.thickness, Max(0, Floor(h * 0.1) - 1))
        right := w - insetX, bottom := h - insetY
        innerWidth := right - insetX, innerHeight := bottom - insetY
        points := Buffer(32)
        NumPut("Float", insetX, "Float", insetY, "Float", right, "Float", insetY,
            "Float", right, "Float", bottom, "Float", insetX, "Float", bottom, points)

        gradient := 0, border := 0, colorCount := 1
        try {
            if (DllCall("gdiplus\GdipCreatePathGradient", "Ptr", points, "Int", 4, "Int", 4, "Ptr*", &gradient)
                || DllCall("gdiplus\GdipSetPathGradientCenterColor", "Ptr", gradient, "UInt", rgb)
                || DllCall("gdiplus\GdipSetPathGradientSurroundColorsWithCount", "Ptr", gradient, "UInt*", &opaque, "Int*", &colorCount)
                || DllCall("gdiplus\GdipSetPathGradientFocusScales", "Ptr", gradient,
                    "Float", w * 0.8 / innerWidth, "Float", h * 0.8 / innerHeight))
                throw Error("Could not create the screen flash gradient")
            Gdip_GraphicsClear(graphics, 0)
            if (Gdip_FillRectangle(graphics, gradient, insetX, insetY, innerWidth, innerHeight))
                throw Error("Could not paint the screen flash gradient")
            border := Gdip_BrushCreateSolid(opaque)
            if (insetY) {
                Gdip_FillRectangle(graphics, border, 0, 0, w, insetY)
                Gdip_FillRectangle(graphics, border, 0, bottom, w, insetY)
            }
            if (insetX) {
                Gdip_FillRectangle(graphics, border, 0, insetY, insetX, innerHeight)
                Gdip_FillRectangle(graphics, border, right, insetY, insetX, innerHeight)
            }
        } finally {
            if (gradient)
                Gdip_DeleteBrush(gradient)
            if (border)
                Gdip_DeleteBrush(border)
        }
    }
}
