; 时间浮动按原值的百分比计算，坐标浮动使用绝对偏移。
; 配置中的 + 或 - 限定浮动方向。两者都没有时允许向两边浮动。
RandomizeDurationByPercent(durationMs, jitterPercent) {
    allowIncrease := InStr(jitterPercent, "+")
    allowDecrease := InStr(jitterPercent, "-")
    if (!allowIncrease && !allowDecrease) {
        allowIncrease := true
        allowDecrease := true
    }

    durationMs := Integer(durationMs)
    jitterPercent := Integer(jitterPercent)
    jitterMs := Abs(durationMs * (jitterPercent * 0.01))
    maximumMs := allowIncrease ? durationMs + jitterMs : durationMs
    minimumMs := allowDecrease ? durationMs - jitterMs : durationMs
    randomizedMs := Max(0, Random(minimumMs, maximumMs))
    return randomizedMs
}

RandomizeValueByOffset(baseValue, offset) {
    allowIncrease := InStr(offset, "+")
    allowDecrease := InStr(offset, "-")
    if (!allowIncrease && !allowDecrease) {
        allowIncrease := true
        allowDecrease := true
    }

    baseValue := Integer(baseValue)
    offsetMagnitude := Abs(offset)
    maximumValue := allowIncrease ? baseValue + offsetMagnitude : baseValue
    minimumValue := allowDecrease ? baseValue - offsetMagnitude : baseValue
    return Random(minimumValue, maximumValue)
}

; 将屏幕点转换为目标顶层窗口的客户区坐标；未命中窗口时返回 [0, 0]。
ScreenPointToWindowClient(ScreenX, ScreenY, hwnd := 0) {
    DllCall("SetProcessDPIAware")
    if (hwnd == 0) {
        hwnd := DllCall("User32\WindowFromPoint", "int64", (ScreenY << 32) | (ScreenX & 0xFFFFFFFF), "ptr")
    }
    ; 鼠标可能指向子控件，坐标以主窗口客户区左上角为原点。
    rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    if (!rootHwnd)
        return [0, 0]
    try WinGetClientPos(&clientX, &clientY, , , rootHwnd)
    catch
        return [0, 0]
    return [ScreenX - clientX, ScreenY - clientY]
}

GetMouseWindowClientPosition() {
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY
    return ScreenPointToWindowClient(mouseX, mouseY)
}
