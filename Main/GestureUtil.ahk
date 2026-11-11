; 手势配置放在 MacroItem.TK，沿用已有的保存、复制和合并路径。
GestureMouseKeys() {
    static keys := Map("LButton", "左键", "MButton", "中键", "RButton", "右键",
        "XButton1", "侧键1", "XButton2", "侧键2", "WheelLeft", "左滚轮", "WheelRight", "右滚轮")
    return keys
}

GestureFingerNames() => ["一指", "二指", "三指", "四指"]

GestureTouchActions() => ["轻点", "上滑", "下滑", "左滑", "右滑"]

GestureModifierKeys() {
    static keys := [
        ["LShift", 0xA0], ["LCtrl", 0xA2], ["Win", 0x5B, 0x5C], ["LAlt", 0xA4],
        ["RAlt", 0xA5], ["RCtrl", 0xA3], ["RShift", 0xA1]
    ]
    return keys
}

GestureModifierLabel(mask) {
    if (mask == 128)
        return "Ctrl+Alt"
    label := ""
    for index, key in GestureModifierKeys() {
        if (mask & (1 << (index - 1)))
            label .= (label == "" ? "" : "+") key[1]
    }
    return label
}

GestureHeldModifiers() {
    mask := 0
    for index, key in GestureModifierKeys() {
        if (DllCall("GetAsyncKeyState", "Int", key[2], "Short") < 0
            || (key.Length == 3 && DllCall("GetAsyncKeyState", "Int", key[3], "Short") < 0))
            mask |= 1 << (index - 1)
    }
    ; 旧的 Ctrl+Alt 绑定允许任一侧 Ctrl 和 Alt。
    if ((mask & 0x22) && (mask & 0x18))
        mask |= 128
    return mask
}

GestureIsWheel(key) => key == "WheelLeft" || key == "WheelRight"

GestureBinding(value, source) {
    for binding in StrSplit(value, "||") {
        if (source == "Mouse" ? InStr(binding, "Mouse|") == 1
            : (InStr(binding, "Touch|") == 1 || InStr(binding, "Touchpad|") == 1))
            return binding
    }
    return ""
}

GestureWithBinding(value, source, binding) {
    mouse := source == "Mouse" ? binding : GestureBinding(value, "Mouse")
    touch := source == "Touch" ? binding : GestureBinding(value, "Touch")
    return mouse (mouse != "" && touch != "" ? "||" : "") touch
}

GestureRead(value) {
    parts := StrSplit(value, "|")
    if (RegExMatch(value, "^Touchpad\|[1-4]\|[1-5]\|(?:[01]|m[1-9][0-9]{0,2})$")) {
        modifiers := parts[4] == "1" ? 128 : (parts[4] == "0" ? 0 : Integer(SubStr(parts[4], 2)))
        if (modifiers > 127 && parts[4] != "1")
            return false
        return {Source: "Touch", Fingers: Integer(parts[2]), Action: Integer(parts[3]), Modifiers: modifiers}
    }
    ; 旧触控板配置保留动作和双指修饰条件，改用触控板输入识别。
    if (parts.Length >= 2 && parts[1] == "Touch") {
        if (parts.Length == 3 && RegExMatch(parts[2], "^1[1-5]$") && RegExMatch(parts[3], "^[01]$"))
            return {Source: "Touch", Fingers: 2, Action: Integer(parts[2]) - 10, Modifiers: parts[3] == "1" ? 128 : 0}
        if (!RegExMatch(parts[2], "^([1-9]|10)$"))
            return false
        if (parts.Length != 2 && !(parts.Length == 4 && RegExMatch(parts[3], "^[1-7]$")
            && RegExMatch(parts[4], "^[1-9][0-9]{0,2}$") && Integer(parts[4]) <= 254))
            return false
        slot := Integer(parts[2])
        return {Source: "Touch", Fingers: slot <= 5 ? 3 : 4, Action: Mod(slot - 1, 5) + 1, Modifiers: 0}
    }
    if (parts.Length != 3 || parts[1] != "Mouse" || !GestureMouseKeys().Has(parts[2]))
        return false
    key := parts[2]
    shape := parts[3]
    if (shape == "Tilt")
        return GestureIsWheel(key) ? {Source: "Mouse", Key: key, Shape: shape, Path: []} : false
    shapes := GesturePath.Shapes()
    if (shapes.Has(shape))
        return {Source: "Mouse", Key: key, Shape: shape, Path: shapes[shape]}
    if (!RegExMatch(shape, "^Custom:(?:-?[0-9]{1,3}:-?[0-9]{1,3};){31}-?[0-9]{1,3}:-?[0-9]{1,3}$"))
        return false
    points := []
    for point in StrSplit(SubStr(shape, 8), ";") {
        xy := StrSplit(point, ":")
        points.Push([Integer(xy[1]) / 100, Integer(xy[2]) / 100])
    }
    return {Source: "Mouse", Key: key, Shape: "Custom", Path: [points]}
}

GestureDisplay(value) {
    mouse := GestureRead(GestureBinding(value, "Mouse"))
    touch := GestureRead(GestureBinding(value, "Touch"))
    mouseLabel := mouse ? GetLang(GestureMouseKeys()[mouse.Key]) " · " GetLang(GesturePath.Labels()[mouse.Shape]) : ""
    touchLabel := touch ? (touch.Modifiers ? GestureModifierLabel(touch.Modifiers) " · " : "")
        . GetLang(GestureFingerNames()[touch.Fingers]) " " GetLang(GestureTouchActions()[touch.Action]) : ""
    if (!mouse && !touch)
        return GetLang("编辑手势")
    return mouseLabel (mouseLabel != "" && touchLabel != "" ? " / " : "") touchLabel
}

class GesturePath {
    static Presets() {
        static presets := 0
        if (presets)
            return presets
        presets := [
            ["Up", "↑", [[0,1],[0,0]]], ["Down", "↓", [[0,0],[0,1]]],
            ["Left", "←", [[1,0],[0,0]]], ["Right", "→", [[0,0],[1,0]]],
            ["UpRight", "↗", [[0,1],[1,0]]], ["DownRight", "↘", [[0,0],[1,1]]],
            ["DownLeft", "↙", [[1,0],[0,1]]], ["UpLeft", "↖", [[1,1],[0,0]]]
        ]
        elbow := [[0,0],[0,1],[0.75,1]]
        for flipped in [false, true] {
            loop 4 {
                turns := A_Index - 1
                angle := turns * 90
                id := flipped ? "LFlip" angle : (angle ? "L" angle : "L")
                label := (flipped ? ["┌ →", "┐ ↓", "┘ ←", "└ ↑"] : ["└ →", "┌ ↓", "┐ ←", "┘ ↑"])[turns + 1]
                presets.Push([id, label, this.Transform(elbow, turns, flipped)])
            }
        }
        circle := []
        loop 33 {
            angle := (A_Index - 1) * 6.28318530718 / 32
            circle.Push([Cos(angle), Sin(angle)])
        }
        presets.Push(
            ["ReturnLeftRight", "← →", [[1,0],[0,0],[1,0]]],
            ["ReturnRightLeft", "→ ←", [[0,0],[1,0],[0,0]]],
            ["ReturnUpDown", "↑ ↓", [[0,1],[0,0],[0,1]]],
            ["ReturnDownUp", "↓ ↑", [[0,0],[0,1],[0,0]]],
            ["Caret", "∧", [[0,1],[0.5,0],[1,1]]],
            ["V", "∨", [[0,0],[0.5,1],[1,0]]],
            ["CaretLeft", "〈", [[1,0],[0,0.5],[1,1]]],
            ["CaretRight", "〉", [[0,0],[1,0.5],[0,1]]],
            ["Z", "Z", [[0,0],[1,0],[0,1],[1,1]]],
            ["S", "S", [[1,0],[0.4,0],[0,0.2],[0.15,0.4],[0.85,0.6],[1,0.8],[0.6,1],[0,1]]],
            ["N", "N", [[0,1],[0,0],[1,1],[1,0]]],
            ["W", "W", [[0,0],[0.25,1],[0.5,0.25],[0.75,1],[1,0]]],
            ["M", "M", [[0,1],[0.25,0],[0.5,0.75],[0.75,0],[1,1]]],
            ["Triangle", "三角形", [[0.5,0],[1,1],[0,1],[0.5,0]]],
            ["Square", "方形", [[0,0],[1,0],[1,1],[0,1],[0,0]]],
            ["Diamond", "菱形", [[0.5,0],[1,0.5],[0.5,1],[0,0.5],[0.5,0]]],
            ["Circle", "圆", circle]
        )
        return presets
    }

    static Transform(points, turns, flipped) {
        result := []
        for point in points {
            x := point[1]
            y := flipped ? -point[2] : point[2]
            loop turns {
                nextX := -y
                y := x
                x := nextX
            }
            result.Push([x, y])
        }
        return result
    }

    static Labels() {
        static labels := 0
        if (!labels) {
            labels := Map("Tilt", "直接触发", "Custom", "自定义")
            for preset in this.Presets()
                labels[preset[1]] := preset[2]
        }
        return labels
    }

    static Shapes() {
        static shapes := 0
        if (shapes)
            return shapes
        shapes := Map()
        for preset in this.Presets() {
            points := preset[3]
            forward := this.Normalize(points)
            shapes[preset[1]] := [forward]
            if (this.IsLoop(forward)) {
                reverse := []
                loop points.Length
                    reverse.Push(points[points.Length - A_Index + 1])
                shapes[preset[1]].Push(this.Normalize(reverse))
            }
        }
        return shapes
    }

    static Distance(a, b) => Sqrt((a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)

    ; 以等弧长采样，并保留轨迹方向及长宽比。
    static Normalize(points, minSize := 0) {
        if (points.Length < 2)
            return []
        lengths := [0]
        minX := maxX := points[1][1]
        minY := maxY := points[1][2]
        loop points.Length - 1 {
            i := A_Index + 1
            point := points[i]
            minX := Min(minX, point[1])
            maxX := Max(maxX, point[1])
            minY := Min(minY, point[2])
            maxY := Max(maxY, point[2])
            lengths.Push(lengths[-1] + this.Distance(points[i - 1], point))
        }
        scale := Max(maxX - minX, maxY - minY)
        if (scale <= 0 || scale < minSize)
            return []
        middleX := (minX + maxX) / 2
        middleY := (minY + maxY) / 2
        segment := 2
        result := []
        loop 32 {
            target := lengths[-1] * (A_Index - 1) / 31
            while (segment < points.Length && lengths[segment] <= target)
                segment++
            span := lengths[segment] - lengths[segment - 1]
            fraction := span > 0 ? (target - lengths[segment - 1]) / span : 0
            a := points[segment - 1]
            b := points[segment]
            result.Push([(a[1] + fraction * (b[1] - a[1]) - middleX) / scale,
                (a[2] + fraction * (b[2] - a[2]) - middleY) / scale])
        }
        return result
    }

    static IsClosed(points) => this.Distance(points[1], points[-1]) < 0.23

    ; 折返会回到起点，但没有围成环。比较时保留先后方向。
    static IsLoop(points) {
        if (!this.IsClosed(points))
            return false
        twiceArea := 0
        previous := points[-1]
        for point in points {
            twiceArea += previous[1] * point[2] - point[1] * previous[2]
            previous := point
        }
        return Abs(twiceArea) >= 0.16
    }

    static Score(points, template, cyclic) {
        best := 1.0
        count := cyclic ? 31 : 32
        loop (cyclic ? count : 1) {
            shift := A_Index - 1
            total := 0
            loop count {
                a := points[A_Index]
                b := template[Mod(A_Index + shift - 1, count) + 1]
                total += (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2
            }
            best := Min(best, Sqrt(total / count))
        }
        return best
    }

    static Encode(points) {
        value := "Custom:"
        for i, point in points
            value .= (i == 1 ? "" : ";") Round(point[1] * 100) ":" Round(point[2] * 100)
        return value
    }

    static Cursor() {
        static point := Buffer(8)
        DllCall("GetCursorPos", "Ptr", point)
        return [NumGet(point, 0, "Int"), NumGet(point, 4, "Int")]
    }
}

class GestureTriggers {
    static Mouse := Map()
    static Touch := Map()
    static LastTilt := Map()
    static Events := []
    static Stroke := false
    static Hook := 0
    static MouseCallback := 0
    static Editing := false
    static ShuttingDown := false

    static PollCallback() {
        static callback := ObjBindMethod(GestureTriggers, "Poll")
        return callback
    }

    static Reset() {
        if (this.Hook) {
            DllCall("UnhookWindowsHookEx", "Ptr", this.Hook)
            this.Hook := 0
        }
        if (this.MouseCallback) {
            CallbackFree(this.MouseCallback)
            this.MouseCallback := 0
        }
        SetTimer(this.PollCallback(), 0)
        this.Events := []
        this.Stroke := false
        GestureTouchpad.Stop()
        this.Touch := Map()
        this.LastTilt := Map()
        this.Mouse := Map()
    }

    static Shutdown() {
        this.ShuttingDown := true
        this.Reset()
        if (this.Editing)
            this.Editing.CloseForExit()
    }

    static Bind() {
        if (this.ShuttingDown)
            return
        for tableItem in MySoftData.TableInfo {
            if (tableItem.Symbol != "Gesture")
                continue
            for index, item in tableItem.Items {
                if (item.Macro == "" || ParseBoolInt(item.Forbid) || GetItemFoldForbidState(tableItem, index))
                    continue
                for binding in StrSplit(item.TK, "||") {
                    gesture := GestureRead(binding)
                    if (!gesture)
                        continue
                    gesture.TableID := tableItem.ID
                    gesture.ItemID := item.ID
                    gesture.Config := item.TK
                    mapForSource := gesture.Source == "Touch" ? this.Touch : this.Mouse
                    key := gesture.Source == "Touch" ? (gesture.Fingers - 1) * 5 + gesture.Action : gesture.Key
                    if (!mapForSource.Has(key))
                        mapForSource[key] := []
                    mapForSource[key].Push(gesture)
                }
            }
        }
        if (this.Touch.Count && !GestureTouchpad.Start())
            RMTLogSys(RMT_LV_WARN, "Gesture", "Could not register precision touchpad raw input.")
        if (this.Mouse.Count) {
            this.MouseCallback := CallbackCreate(ObjBindMethod(GestureTriggers, "OnMouse"), "Fast", 3)
            module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
            this.Hook := DllCall("SetWindowsHookEx", "Int", 14, "Ptr", this.MouseCallback, "Ptr", module, "UInt", 0, "Ptr")
            if (!this.Hook) {
                CallbackFree(this.MouseCallback)
                this.MouseCallback := 0
                RMTLogSys(RMT_LV_WARN, "Gesture", "Could not install the mouse gesture hook.")
                return
            }
            SetTimer(this.PollCallback(), 15)
        }
    }

    static OnTouch(fingers, action, heldModifiers) {
        for gesture in this.Touch.Get((fingers - 1) * 5 + action, []) {
            if (((heldModifiers & gesture.Modifiers) == gesture.Modifiers) && this.CanRun(gesture)) {
                this.Dispatch(gesture)
                break
            }
        }
    }

    static OnMouse(code, msg, data) {
        code := code << 32 >> 32  ; Win32 的 nCode 是有符号 int。
        static buttons := Map(0x201, "LButton", 0x202, "LButton", 0x204, "RButton", 0x205, "RButton",
            0x207, "MButton", 0x208, "MButton")
        if (code >= 0 && !(NumGet(data, 12, "UInt") & 1)) {
            key := buttons.Get(msg, "")
            down := msg == 0x201 || msg == 0x204 || msg == 0x207 || msg == 0x20B || msg == 0x20E
            if (msg == 0x20B || msg == 0x20C)
                key := NumGet(data, 10, "UShort") == 1 ? "XButton1" : "XButton2"
            else if (msg == 0x20E)
                key := NumGet(data, 10, "Short") < 0 ? "WheelLeft" : "WheelRight"
            if (GestureTriggers.Mouse.Has(key))
                GestureTriggers.Events.Push({Key: key, Down: down,
                    Point: [NumGet(data, 0, "Int"), NumGet(data, 4, "Int")]})
        }
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "UPtr", msg, "Ptr", data, "Ptr")
    }

    static IsEnabled() => !this.ShuttingDown && !MainSoftData.IsPause && !A_IsSuspended
        && (!this.Editing || !this.Editing.Hwnd() || !WinActive("ahk_id " this.Editing.Hwnd()))

    static Poll() {
        this := GestureTriggers
        events := this.Events
        this.Events := []
        if (!this.IsEnabled()) {
            this.Stroke := false
            return
        }
        now := A_TickCount
        for event in events {
            if (!event.Down) {
                if (this.Stroke && this.Stroke.Key == event.Key) {
                    this.Stroke.Points.Push(event.Point)
                    this.FinishStroke()
                }
                continue
            }
            if (this.Stroke)
                continue
            wheel := GestureIsWheel(event.Key)
            candidates := []
            direct := false
            hasPath := false
            for gesture in this.Mouse.Get(event.Key, []) {
                if (!this.CanRun(gesture))
                    continue
                candidates.Push(gesture)
                if (gesture.Shape != "Tilt")
                    hasPath := true
                else if (!direct)
                    direct := gesture
            }
            if (direct && !hasPath) {
                if (now - this.LastTilt.Get(event.Key, -500) >= 400) {
                    this.LastTilt[event.Key] := now
                    this.Dispatch(direct)
                }
            } else if (candidates.Length)
                this.Stroke := {Key: event.Key, Candidates: candidates, Points: [event.Point], Started: now,
                    Moved: now, Wheel: wheel}
        }
        if (!this.Stroke)
            return
        stroke := this.Stroke
        point := GesturePath.Cursor()
        if (GesturePath.Distance(point, stroke.Points[-1]) >= 2) {
            stroke.Points.Push(point)
            stroke.Moved := now
        }
        if (stroke.Wheel && (now - stroke.Started >= 3000
            || (now - stroke.Started >= 550 && now - stroke.Moved >= 260)))
            this.FinishStroke()
        else if (now - stroke.Started >= 10000)
            this.Stroke := false
    }

    static FinishStroke() {
        stroke := this.Stroke
        this.Stroke := false
        points := GesturePath.Normalize(stroke.Points, 25)
        if (!points.Length) {
            for gesture in stroke.Candidates {
                if (gesture.Shape == "Tilt" && this.CanRun(gesture)) {
                    this.Dispatch(gesture)
                    return
                }
            }
            return
        }
        closed := GesturePath.IsClosed(points)
        best := false
        score := 1.0
        for gesture in stroke.Candidates {
            if (!this.CanRun(gesture))
                continue
            for template in gesture.Path {
                if (closed != GesturePath.IsClosed(template))
                    continue
                cyclic := closed && (gesture.Shape == "Custom" || GesturePath.IsLoop(template))
                candidateScore := GesturePath.Score(points, template, cyclic)
                if (candidateScore < score && candidateScore < (cyclic ? 0.16 : 0.18)) {
                    best := gesture
                    score := candidateScore
                }
            }
        }
        if (best)
            this.Dispatch(best)
    }

    static CanRun(gesture) {
        if (!this.IsEnabled())
            return false
        resolved := ResolveMacroItem(gesture.TableID, gesture.ItemID)
        if (!resolved || resolved.Item.TK != gesture.Config || resolved.Item.Macro == "" || ParseBoolInt(resolved.Item.Forbid))
            return false
        fold := GetItemFoldData(resolved.Table, resolved.Index)
        return !fold.forbidState && CheckFrontWindowActive(fold.frontInfo)
    }

    static Dispatch(gesture) {
        SetTimer(ObjBindMethod(this, "Run", gesture), -1)
    }

    static Run(gesture) {
        if (this.CanRun(gesture))
            TriggerMacroHandler(gesture.TableID, gesture.ItemID)
    }
}
