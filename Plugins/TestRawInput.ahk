#Requires AutoHotkey v2.0
#SingleInstance Force

global rawInputHwnd := 0
global events := []
global startTime := 0

StrRepeat(str, count) {
    s := ""
    Loop count
        s .= str
    return s
}

hInstance := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
rawInputHwnd := DllCall("CreateWindowEx", "UInt", 0, "Str", "Message", "Ptr", 0, "UInt", 0
    , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr", -3, "Ptr", 0, "Ptr", hInstance, "Ptr", 0, "Ptr")

OnMessage(0x00FF, OnWMInput)

RID1 := Buffer(A_PtrSize == 8 ? 16 : 12, 0)
NumPut("UShort", 0x01, RID1, 0)
NumPut("UShort", 0x02, RID1, 2)
NumPut("UInt", 0x00000100, RID1, 4)
NumPut("UPtr", rawInputHwnd, RID1, 8)

RID2 := Buffer(A_PtrSize == 8 ? 16 : 12, 0)
NumPut("UShort", 0x01, RID2, 0)
NumPut("UShort", 0x06, RID2, 2)
NumPut("UInt", 0x00000100, RID2, 4)
NumPut("UPtr", rawInputHwnd, RID2, 8)

DllCall("RegisterRawInputDevices", "Ptr", RID1.Ptr, "UInt", 1, "UInt", A_PtrSize == 8 ? 16 : 12)
DllCall("RegisterRawInputDevices", "Ptr", RID2.Ptr, "UInt", 1, "UInt", A_PtrSize == 8 ? 16 : 12)

mouseSpeed := 0
DllCall("SystemParametersInfo", "UInt", 0x0070, "UInt", 0, "IntP", &mouseSpeed, "UInt", 0)
dpiX := 96
try {
    hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    dpiX := DllCall("GetDeviceCaps", "Ptr", hDC, "Int", 88, "Int")
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
}
scaleFactor := (mouseSpeed / 10.0) * (dpiX / 96.0)

outFile := A_ScriptDir "\ri_test.txt"
try {
    if FileExist(outFile)
        FileDelete(outFile)
} catch as e {
    outFile := A_ScriptDir "\ri_test_" A_Now ".txt"
}

ToolTip("录制中...`n移动+左键+右键+键盘`nF2: 保存 | ESC: 退出")
SetTimer () => ToolTip(), -4000

Hotkey "F2", SaveResult
Hotkey "Escape", (*) => ExitApp()

startTime := A_TickCount

OnWMInput(wParam, lParam, msg, hwnd) {
    global rawInputHwnd, events
    if (hwnd != rawInputHwnd)
        return

    headerSize := A_PtrSize == 8 ? 24 : 16
    rawInput := Buffer(64, 0)
    size := 64
    ret := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", rawInput.Ptr, "UIntP", &size, "UInt", headerSize)
    if (ret <= 0)
        return

    dwType := NumGet(rawInput, 0, "UInt")
    t := A_TickCount

    if (dwType == 0) {
        if (A_PtrSize == 8) {
            x := NumGet(rawInput, 36, "Int")
            y := NumGet(rawInput, 40, "Int")
            btnFlags := NumGet(rawInput, 28, "UShort")
            buttonData := NumGet(rawInput, 30, "Short")
        } else {
            x := NumGet(rawInput, 32, "Int")
            y := NumGet(rawInput, 36, "Int")
            btnFlags := NumGet(rawInput, 24, "UShort")
            buttonData := NumGet(rawInput, 26, "Short")
        }

        if (x != 0 || y != 0) {
            px := Round(x / scaleFactor)
            py := Round(y / scaleFactor)
            events.Push(Map("type", "move", "dx", px, "dy", py, "t", t))
        }

        static btnMap := Map(
            0x0001, "LBtn_Down", 0x0002, "LBtn_Up",
            0x0004, "RBtn_Down", 0x0008, "RBtn_Up",
            0x0010, "MBtn_Down", 0x0020, "MBtn_Up",
            0x0040, "X1Btn_Down", 0x0080, "X1Btn_Up",
            0x0100, "X2Btn_Down", 0x0200, "X2Btn_Up"
        )
        if (btnMap.Has(btnFlags))
            events.Push(Map("type", "btn", "name", btnMap[btnFlags], "t", t))

        if (btnFlags & 0x0400) {
            wheelName := buttonData > 0 ? "WheelUp" : "WheelDown"
            events.Push(Map("type", "btn", "name", wheelName, "wheelValue", buttonData, "t", t))
        }
        else if (btnFlags & 0x0800) {
            wheelName := buttonData > 0 ? "WheelRight" : "WheelLeft"
            events.Push(Map("type", "btn", "name", wheelName, "wheelValue", buttonData, "t", t))
        }
    }
    else if (dwType == 1) {
        vKey := 0
        flags := 0
        if (A_PtrSize == 8) {
            makeCode := NumGet(rawInput, 24, "UShort")
            flags := NumGet(rawInput, 26, "UShort")
            vKey := NumGet(rawInput, 30, "UShort")
        } else {
            makeCode := NumGet(rawInput, 16, "UShort")
            flags := NumGet(rawInput, 18, "UShort")
            vKey := NumGet(rawInput, 22, "UShort")
        }

        vkName := GetKeyName("vk" Format("{:02X}", vKey))
        if (!vkName)
            vkName := "vk" Format("{:02X}", vKey)
        state := (flags & 1) ? "Down" : "Up"
        events.Push(Map("type", "key", "name", vkName, "state", state, "t", t))
    }
}

SaveResult(*) {
    global events, startTime, outFile

    duration := A_TickCount - startTime

    totalDx := 0
    totalDy := 0
    moveCount := 0
    lDown := 0
    lUp := 0
    rDown := 0
    rUp := 0
    mDown := 0
    mUp := 0
    x1Down := 0
    x1Up := 0
    x2Down := 0
    x2Up := 0
    wheelUp := 0
    wheelDown := 0
    wheelLeft := 0
    wheelRight := 0
    kDown := 0
    kUp := 0

    for i, e in events {
        if (e["type"] = "move") {
            totalDx += e["dx"]
            totalDy += e["dy"]
            moveCount++
        }
        else if (e["type"] = "btn") {
            n := e["name"]
            if (n = "LBtn_Down")
                lDown++
            else if (n = "LBtn_Up")
                lUp++
            else if (n = "RBtn_Down")
                rDown++
            else if (n = "RBtn_Up")
                rUp++
            else if (n = "MBtn_Down")
                mDown++
            else if (n = "MBtn_Up")
                mUp++
            else if (n = "X1Btn_Down")
                x1Down++
            else if (n = "X1Btn_Up")
                x1Up++
            else if (n = "X2Btn_Down")
                x2Down++
            else if (n = "X2Btn_Up")
                x2Up++
            else if (n = "WheelUp")
                wheelUp++
            else if (n = "WheelDown")
                wheelDown++
            else if (n = "WheelLeft")
                wheelLeft++
            else if (n = "WheelRight")
                wheelRight++
        }
        else if (e["type"] = "key") {
            if (e["state"] = "Down")
                kDown++
            else
                kUp++
        }
    }

    dist := Sqrt(totalDx**2 + totalDy**2)
    angle := (totalDx == 0 && totalDy == 0) ? 0 : DllCall("msvcrt.dll\atan2", "Double", totalDy, "Double", totalDx, "Double") * 180 / 3.14159265
    if (angle < 0)
        angle += 360

    s := ""
    s .= "=========================================`n"
    s .= "   RawInput 录制结果`n"
    s .= "=========================================`n"
    s .= "时间: " A_Now "`n"
    s .= "时长: " (duration / 1000) " 秒  |  鼠标速度=" mouseSpeed "/20  DPI=" dpiX "`n"
    s .= "scale=" Round(scaleFactor, 3) "`n"
    s .= "----------------------------------------`n"
    s .= "移动: " moveCount " 次  |  dx=" totalDx " dy=" totalDy "px  距离≈" Round(dist) "px  方向=" Round(angle, 1) "°`n"
    s .= "左键: " lDown "/" lUp "  |  右键: " rDown "/" rUp "  |  中键: " mDown "/" mUp "`n"
    s .= "侧键1: " x1Down "/" x1Up "  |  侧键2: " x2Down "/" x2Up "`n"
    s .= "滚轮↑: " wheelUp "  ↓: " wheelDown "  ←: " wheelLeft "  →: " wheelRight "`n"
    s .= "键盘: " kDown "/" kUp "  |  总事件: " events.Length "`n"
    s .= "----------------------------------------`n"

    maxW1 := 6
    maxW2 := 5
    for i, e in events {
        desc := ""
        if (e["type"] = "move")
            desc := Format("{:+5d},{:+5d}px", e["dx"], e["dy"])
        else if (e["type"] = "btn") {
            if (e.Has("wheelValue"))
                desc := "[" . e["name"] . "(" . e["wheelValue"] . ")]"
            else
                desc := "[" . e["name"] . "]"
        }
        else if (e["type"] = "key")
            desc := Format("[{} {}]", e["name"], e["state"])
        w := StrLen(desc)
        if (w > maxW2)
            maxW2 := w
    }

    hdr1 := Format("{:" maxW1 "}", "#")
    hdr2 := Format("{:-" maxW2 "}", "事件")
    hdr3 := "时间(ms)"
    sep := StrRepeat("─", maxW1 + 1) . StrRepeat("─", maxW2 + 2) . "──────"

    s .= hdr1 "  " hdr2 "  " hdr3 "`n"
    s .= sep "`n"

    Loop events.Length {
        e := events[A_Index]
        relT := e["t"] - startTime
        if (e["type"] = "move")
            desc := Format("{:+5d},{:+5d}px", e["dx"], e["dy"])
        else if (e["type"] = "btn") {
            if (e.Has("wheelValue"))
                desc := "[" . e["name"] . "(" . e["wheelValue"] . ")]"
            else
                desc := "[" . e["name"] . "]"
        }
        else
            desc := Format("[{} {}]", e["name"], e["state"])
        s .= Format("{:" maxW1 "}d  {:-" maxW2 "}s  {:7d}`n", A_Index, desc, relT)
    }

    try {
        if FileExist(outFile)
            FileDelete(outFile)
    }
    FileAppend(s, outFile)
    ; Run(outFile)
    MsgBox(
        "✅ 已保存到:`n" outFile "`n`n"
        "时长: " (duration / 1000) "s`n"
        "移动: " moveCount " 点, 距离≈" Round(dist) "px`n"
        "左键: " lDown "/" lUp "  右键: " rDown "/" rUp "`n"
        "侧键1: " x1Down "/" x1Up "  侧键2: " x2Down "/" x2Up "`n"
        "滚轮↑: " wheelUp " ↓: " wheelDown " ←: " wheelLeft " →: " wheelRight "`n"
        "键盘: " kDown "/" kUp "`n"
        "总事件: " events.Length, "完成"
    )
}
