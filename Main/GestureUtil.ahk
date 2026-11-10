; 手势配置放在 MacroItem.TK，沿用已有的保存、复制和合并路径。
GestureMouseKeys() {
    static keys := Map("LButton", "左键", "MButton", "中键", "RButton", "右键",
        "XButton1", "侧键1", "XButton2", "侧键2", "WheelLeft", "左滚轮", "WheelRight", "右滚轮")
    return keys
}

GestureTouchNames() {
    static names := ["三指轻点", "三指上滑", "三指下滑", "三指左滑", "三指右滑",
        "四指轻点", "四指上滑", "四指下滑", "四指左滑", "四指右滑"]
    return names
}

GestureIsWheel(key) => key == "WheelLeft" || key == "WheelRight"

GestureDefaultChord(slot) => ((0x6F + slot) << 16) | 7

GestureHotkeyText(chord) {
    return ((chord & 2) ? "^" : "") ((chord & 1) ? "!" : "") ((chord & 4) ? "+" : "")
        . GetKeyName(Format("vk{:02X}", chord >> 16))
}

GestureParseHotkey(value) {
    if (!RegExMatch(value, "^([!^+]+)([^!^+]+)$", &match))
        return 0
    vk := GetKeyVK(match[2])
    modifiers := (InStr(match[1], "!") ? 1 : 0) | (InStr(match[1], "^") ? 2 : 0) | (InStr(match[1], "+") ? 4 : 0)
    return vk ? (vk << 16) | modifiers : 0
}

GestureRead(value) {
    parts := StrSplit(value, "|")
    if ((parts.Length == 2 || parts.Length == 4) && parts[1] == "Touch"
        && RegExMatch(parts[2], "^(?:[1-9]|10)$")) {
        slot := Integer(parts[2])
        if (parts.Length == 2)
            return {Source: "Touch", Slot: slot, Chord: GestureDefaultChord(slot)}
        if (RegExMatch(parts[3], "^[1-7]$") && RegExMatch(parts[4], "^[1-9][0-9]{0,2}$")
            && Integer(parts[4]) <= 254)
            return {Source: "Touch", Slot: slot, Chord: (Integer(parts[4]) << 16) | Integer(parts[3])}
        return false
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
    gesture := GestureRead(value)
    if (!gesture)
        return GetLang("编辑手势")
    if (gesture.Source == "Touch")
        return GetLang(GestureTouchNames()[gesture.Slot])
    return GetLang(GestureMouseKeys()[gesture.Key]) " · " GetLang(GesturePath.Labels()[gesture.Shape])
}

class GesturePath {
    static Labels() {
        static labels := Map("Right", "→", "DownRight", "↘", "Down", "↓", "DownLeft", "↙",
            "Left", "←", "UpLeft", "↖", "Up", "↑", "UpRight", "↗",
            "L", "L", "V", "V", "Caret", "∧", "Z", "Z", "S", "S", "N", "N", "W", "W", "M", "M",
            "Circle", "圆", "Triangle", "三角形", "Square", "方形", "Diamond", "菱形",
            "Tilt", "直接触发", "Custom", "自定义")
        return labels
    }

    static Shapes() {
        static shapes := 0
        if (shapes)
            return shapes
        vertices := Map("Right", [[0,0],[1,0]], "DownRight", [[0,0],[1,1]],
            "Down", [[0,0],[0,1]], "DownLeft", [[1,0],[0,1]],
            "Left", [[1,0],[0,0]], "UpLeft", [[1,1],[0,0]],
            "Up", [[0,1],[0,0]], "UpRight", [[0,1],[1,0]],
            "L", [[0,0],[0,1],[0.75,1]], "V", [[0,0],[0.5,1],[1,0]],
            "Caret", [[0,1],[0.5,0],[1,1]], "Z", [[0,0],[1,0],[0,1],[1,1]],
            "N", [[0,1],[0,0],[1,1],[1,0]],
            "W", [[0,0],[0.25,1],[0.5,0.25],[0.75,1],[1,0]],
            "M", [[0,1],[0.25,0],[0.5,0.75],[0.75,0],[1,1]],
            "S", [[1,0],[0.4,0],[0,0.2],[0.15,0.4],[0.85,0.6],[1,0.8],[0.6,1],[0,1]],
            "Triangle", [[0.5,0],[1,1],[0,1],[0.5,0]],
            "Square", [[0,0],[1,0],[1,1],[0,1],[0,0]],
            "Diamond", [[0.5,0],[1,0.5],[0.5,1],[0,0.5],[0.5,0]])
        circle := []
        loop 33 {
            angle := (A_Index - 1) * 6.28318530718 / 32
            circle.Push([Cos(angle), Sin(angle)])
        }
        vertices["Circle"] := circle
        shapes := Map()
        for name, points in vertices {
            forward := this.Normalize(points)
            if (this.IsClosed(forward)) {
                reverse := []
                loop points.Length
                    reverse.Push(points[points.Length - A_Index + 1])
                shapes[name] := [forward, this.Normalize(reverse)]
            } else {
                shapes[name] := [forward]
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

    static Score(points, template, closed) {
        best := 1.0
        count := closed ? 31 : 32
        loop (closed ? count : 1) {
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
    static TouchIDs := Map()
    static SetupChord := 0
    static LastTilt := Map()
    static Events := []
    static Stroke := false
    static Hook := 0
    static MouseCallback := 0
    static Editing := false

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
        for chord, id in this.TouchIDs
            DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", id)
        this.TouchIDs := Map()
        this.Touch := Map()
        this.LastTilt := Map()
        this.Mouse := Map()
    }

    static Bind() {
        static listening := false
        for tableItem in MySoftData.TableInfo {
            if (tableItem.Symbol != "Gesture")
                continue
            for index, item in tableItem.Items {
                if (item.Macro == "" || ParseBoolInt(item.Forbid) || GetItemFoldForbidState(tableItem, index))
                    continue
                gesture := GestureRead(item.TK)
                if (!gesture)
                    continue
                gesture.TableID := tableItem.ID
                gesture.ItemID := item.ID
                gesture.Config := item.TK
                mapForSource := gesture.Source == "Touch" ? this.Touch : this.Mouse
                key := gesture.Source == "Touch" ? gesture.Chord : gesture.Key
                if (!mapForSource.Has(key))
                    mapForSource[key] := []
                mapForSource[key].Push(gesture)
            }
        }
        if (this.Touch.Count && !listening) {
            OnMessage(0x0312, ObjBindMethod(GestureTriggers, "OnHotkey"))
            listening := true
        }
        for chord, gestures in this.Touch {
            if (chord == this.SetupChord)
                continue
            id := 0x5600 + A_Index
            if (id < 0x6000 && this.RegisterTouch(id, chord))
                this.TouchIDs[chord] := id
            else
                RMTLogSys(RMT_LV_WARN, "Gesture", "Could not register touchpad shortcut: " GestureHotkeyText(chord))
        }
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

    static RegisterTouch(id, chord) {
        if (this.ConflictsWithAppHotkey(chord))
            return false
        return DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd, "Int", id,
            "UInt", 0x4000 | (chord & 0xFFFF), "UInt", chord >> 16)
    }

    static ConflictsWithAppHotkey(chord) {
        global BoundMacroHotkeyList
        if (!IsSet(BoundMacroHotkeyList) || !IsObject(BoundMacroHotkeyList))
            return false
        for hotkey in BoundMacroHotkeyList {
            if (!RegExMatch(hotkey, "i)^([~*$]*)([!^+]*)([^ !^+&<>#]+)(?: up)?$", &parts))
                continue
            if (GetKeyVK(parts[3]) != chord >> 16)
                continue
            if (parts[2] == "") {
                if (InStr(parts[1], "*"))
                    return true
                continue
            }
            existing := GestureParseHotkey(parts[2] parts[3])
            if (existing == chord || (InStr(parts[1], "*") && (existing & chord) == existing))
                return true
        }
        return false
    }

    static ShortcutAvailable(chord) {
        if (this.TouchIDs.Has(chord))
            return true
        probeID := 0x5600
        if (!this.RegisterTouch(probeID, chord))
            return false
        DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", probeID)
        return true
    }

    static SetSetupChord(chord := 0) {
        if (chord == this.SetupChord)
            return
        previous := this.SetupChord
        this.SetupChord := chord
        if (this.TouchIDs.Has(chord)) {
            DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", this.TouchIDs[chord])
            this.TouchIDs.Delete(chord)
        }
        for candidate in this.Touch {
            if (candidate != previous)
                continue
            id := 0x5600 + A_Index
            if (id < 0x6000 && this.RegisterTouch(id, previous))
                this.TouchIDs[previous] := id
            else
                RMTLogSys(RMT_LV_WARN, "Gesture", "Could not restore touchpad shortcut: " GestureHotkeyText(previous))
            break
        }
    }

    static OnHotkey(wParam, lParam, msg, hwnd) {
        if (!GestureTriggers.IsEnabled() || GestureTriggers.TouchIDs.Get(lParam, 0) != wParam
            || hwnd != A_ScriptHwnd || !GestureTriggers.Touch.Has(lParam))
            return
        for gesture in GestureTriggers.Touch[lParam] {
            if (GestureTriggers.CanRun(gesture)) {
                GestureTriggers.Dispatch(gesture)
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
            if (key != "" && GestureTriggers.Mouse.Has(key))
                GestureTriggers.Events.Push({Key: key, Down: down, Point: [NumGet(data, 0, "Int"), NumGet(data, 4, "Int")]})
        }
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "UPtr", msg, "Ptr", data, "Ptr")
    }

    static IsEnabled() => !MainSoftData.IsPause && !A_IsSuspended
        && (!this.Editing || !WinActive("ahk_id " this.Editing.Window.Hwnd))

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
                this.Stroke := {Key: event.Key, Candidates: candidates, Points: [event.Point], Started: now, Moved: now, Wheel: wheel}
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
        score := closed ? 0.16 : 0.18
        for gesture in stroke.Candidates {
            if (!this.CanRun(gesture))
                continue
            for template in gesture.Path {
                if (closed != GesturePath.IsClosed(template))
                    continue
                candidateScore := GesturePath.Score(points, template, closed)
                if (candidateScore < score) {
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
