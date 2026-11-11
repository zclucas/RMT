; 精确式触控板通过 Raw Input 报告触点，和普通鼠标的按键、滚轮输入分开。
class GestureTouchpad {
    static Devices := Map()
    static Listening := false
    static InputCallback := ObjBindMethod(GestureTouchpad, "OnInput")
    static DeviceCallback := ObjBindMethod(GestureTouchpad, "OnDeviceChange")

    static Start() {
        if (this.Listening)
            return true
        if (!this.Register(0x2100, A_ScriptHwnd)) ; INPUTSINK | DEVNOTIFY
            return false
        OnMessage(0xFF, this.InputCallback)
        OnMessage(0xFE, this.DeviceCallback)
        this.Listening := true
        return true
    }

    static Stop() {
        if (this.Listening) {
            OnMessage(0xFF, this.InputCallback, 0)
            OnMessage(0xFE, this.DeviceCallback, 0)
            this.Register(1, 0) ; REMOVE
            this.Listening := false
        }
        this.Devices := Map()
    }

    static Register(flags, hwnd) {
        device := Buffer(8 + A_PtrSize)
        NumPut("UShort", 0x0D, "UShort", 0x05, "UInt", flags, "Ptr", hwnd, device)
        return DllCall("RegisterRawInputDevices", "Ptr", device, "UInt", 1, "UInt", device.Size)
    }

    static OnDeviceChange(wParam, device, msg, hwnd) {
        if (hwnd == A_ScriptHwnd && GestureTouchpad.Devices.Has(device))
            GestureTouchpad.Devices.Delete(device)
    }

    static OnInput(wParam, lParam, msg, hwnd) {
        if (hwnd != A_ScriptHwnd)
            return
        static headerSize := 8 + 2 * A_PtrSize, raw := Buffer(512)
        size := raw.Size
        bytes := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", raw,
            "UInt*", &size, "UInt", headerSize, "UInt")
        if (bytes == 0xFFFFFFFF && size > raw.Size) {
            raw := Buffer(size)
            bytes := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", raw,
                "UInt*", &size, "UInt", headerSize, "UInt")
        }
        if (bytes == 0xFFFFFFFF || bytes < headerSize + 8 || NumGet(raw, "UInt") != 2)
            return
        handle := NumGet(raw, 8, "Ptr")
        if (!handle)
            return
        devices := GestureTouchpad.Devices
        if (!devices.Has(handle))
            devices[handle] := GestureTouchpad.Describe(handle)
        device := devices[handle]
        if (!device)
            return

        if (!GestureTriggers.IsEnabled()) {
            device.Pending := 0
            device.Stroke := false
            return
        }

        reportSize := NumGet(raw, headerSize, "UInt")
        reports := NumGet(raw, headerSize + 4, "UInt")
        if (!reportSize || reports * reportSize > bytes - headerSize - 8)
            return
        now := A_TickCount
        loop reports {
            report := raw.Ptr + headerSize + 8 + (A_Index - 1) * reportSize
            GestureTouchpad.ReadReport(device, report, reportSize, now)
        }
    }

    static Describe(handle) {
        size := 0
        DllCall("GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000005, "Ptr", 0, "UInt*", &size)
        if (!size)
            return false
        descriptor := Buffer(size)
        if (DllCall("GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000005, "Ptr", descriptor,
            "UInt*", &size, "Int") <= 0)
            return false
        caps := Buffer(64)
        if (DllCall("hid\HidP_GetCaps", "Ptr", descriptor, "Ptr", caps) != 0x110000
            || NumGet(caps, "UShort") != 5 || NumGet(caps, 2, "UShort") != 0x0D)
            return false
        nodeCount := NumGet(caps, 44, "UShort")
        if (!nodeCount)
            return false
        nodeSize := 16 + A_PtrSize
        nodes := Buffer(nodeCount * nodeSize)
        if (DllCall("hid\HidP_GetLinkCollectionNodes", "Ptr", nodes, "UInt*", &nodeCount,
            "Ptr", descriptor) != 0x110000)
            return false
        fingers := []
        loop nodeCount - 1 {
            link := A_Index
            offset := link * nodeSize
            if (NumGet(nodes, offset, "UShort") != 0x22 || NumGet(nodes, offset + 2, "UShort") != 0x0D
                || (NumGet(nodes, offset + 12, "UInt") & 0x100))
                continue
            xRange := GestureTouchpad.AxisRange(descriptor, link, 0x30)
            yRange := GestureTouchpad.AxisRange(descriptor, link, 0x31)
            if (xRange > 0 && yRange > 0)
                fingers.Push({Link: link, XRange: xRange, YRange: yRange})
        }
        return fingers.Length ? {Descriptor: descriptor, Fingers: fingers, Pending: 0, Frame: Map(),
            LastReport: 0, ScanTime: -1, Invalid: false, Stroke: false} : false
    }

    static AxisRange(descriptor, link, usage) {
        caps := Buffer(72)
        count := 1
        if (DllCall("hid\HidP_GetSpecificValueCaps", "Int", 0, "UShort", 1, "UShort", link,
            "UShort", usage, "Ptr", caps, "UShort*", &count, "Ptr", descriptor) != 0x110000)
            return 0
        return NumGet(caps, 44, "Int") - NumGet(caps, 40, "Int")
    }

    static Value(descriptor, report, size, page, link, usage) {
        value := 0
        status := DllCall("hid\HidP_GetUsageValue", "Int", 0, "UShort", page, "UShort", link,
            "UShort", usage, "UInt*", &value, "Ptr", descriptor, "Ptr", report, "UInt", size)
        return status == 0x110000 ? value : -1
    }

    static ReadReport(device, report, size, now) {
        descriptor := device.Descriptor
        count := GestureTouchpad.Value(descriptor, report, size, 0x0D, 0, 0x54)
        if (count < 0 || count > 16)
            return
        scanTime := GestureTouchpad.Value(descriptor, report, size, 0x0D, 0, 0x56)
        if (now - device.LastReport > 300) {
            device.Pending := 0
            device.Stroke := false
        }
        device.LastReport := now

        ; 混合模式首包声明整个帧的触点数，后续包的触点数为零。
        if (device.Pending && count == 0 && scanTime >= 0 && scanTime != device.ScanTime) {
            device.Pending := 0
            device.Stroke := false
            return
        }
        if (count > 0 || !device.Pending) {
            device.ScanTime := scanTime
            device.Pending := count
            device.Frame := Map()
            device.Invalid := false
        }
        static usages := Buffer(64)
        usageCount := usages.Size // 2
        if (DllCall("hid\HidP_GetUsages", "Int", 0, "UShort", 9, "UShort", 0, "Ptr", usages,
            "UInt*", &usageCount, "Ptr", descriptor, "Ptr", report, "UInt", size) == 0x110000 && usageCount)
            device.Invalid := true

        for finger in device.Fingers {
            if (!device.Pending)
                break
            link := finger.Link
            id := GestureTouchpad.Value(descriptor, report, size, 0x0D, link, 0x51)
            if (id < 0)
                continue
            device.Pending--
            usageCount := usages.Size // 2
            if (DllCall("hid\HidP_GetUsages", "Int", 0, "UShort", 0x0D, "UShort", link, "Ptr", usages,
                "UInt*", &usageCount, "Ptr", descriptor, "Ptr", report, "UInt", size) != 0x110000)
                continue
            tip := confident := false
            loop usageCount {
                usage := NumGet(usages, (A_Index - 1) * 2, "UShort")
                if (usage == 0x42)
                    tip := true
                else if (usage == 0x47)
                    confident := true
            }
            if (!tip)
                continue
            if (!confident)
                device.Invalid := true
            x := GestureTouchpad.Value(descriptor, report, size, 1, link, 0x30)
            y := GestureTouchpad.Value(descriptor, report, size, 1, link, 0x31)
            if (x >= 0 && y >= 0)
                device.Frame[id] := [x / finger.XRange, y / finger.YRange]
        }
        if (!device.Pending) {
            gesture := GestureTouchpad.Track(device, device.Frame, device.Invalid, now)
            if (gesture)
                GestureTriggers.OnTouch(gesture.Fingers, gesture.Action, gesture.Modifiers)
        }
    }

    static Track(device, contacts, invalid, now) {
        count := contacts.Count
        stroke := device.Stroke
        if (stroke)
            stroke.Modifiers &= GestureHeldModifiers()
        if (!count) {
            device.Stroke := false
            return stroke && !invalid ? GestureTouchpad.Recognize(stroke, now) : false
        }
        if (!stroke) {
            device.Stroke := stroke := {Started: now, First: contacts, Last: contacts, Peak: count,
                Cancelled: false, Travel: 0, Modifiers: GestureHeldModifiers()}
        }
        if (invalid || count > 4)
            stroke.Cancelled := true
        if (count > stroke.Peak) {
            stroke.Peak := count
            stroke.First := contacts
            stroke.Last := contacts
        }
        ; 松指时保留完整手势的最后一帧，避免剩余手指改变方向。
        if (count != stroke.Peak || stroke.Cancelled)
            return false
        for id, point in contacts {
            if (!stroke.First.Has(id)) {
                stroke.Cancelled := true
                return false
            }
            stroke.Travel := Max(stroke.Travel, GesturePath.Distance(point, stroke.First[id]))
        }
        stroke.Last := contacts
        return false
    }

    static Recognize(stroke, now) {
        duration := now - stroke.Started
        if (stroke.Cancelled || duration > 1500)
            return false
        if (duration <= 300 && stroke.Travel <= 0.035)
            return {Fingers: stroke.Peak, Action: 1, Modifiers: stroke.Modifiers}

        x := y := 0
        for id, point in stroke.Last {
            x += point[1] - stroke.First[id][1]
            y += point[2] - stroke.First[id][2]
        }
        horizontal := Abs(x) >= Abs(y)
        movement := horizontal ? x : y
        if (Abs(movement) / stroke.Peak < 0.12)
            return false
        axis := horizontal ? 1 : 2
        sign := movement < 0 ? -1 : 1
        for id, point in stroke.Last {
            if ((point[axis] - stroke.First[id][axis]) * sign < 0.04)
                return false
        }
        action := horizontal ? (sign < 0 ? 4 : 5) : (sign < 0 ? 2 : 3)
        return {Fingers: stroke.Peak, Action: action, Modifiers: stroke.Modifiers}
    }
}
