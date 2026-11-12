; 时间浮动按原值的百分比计算，坐标浮动使用绝对偏移。
; 配置中的 + 或 - 限定浮动方向。两者都没有时允许向两边浮动。
RandomizeDurationByPercent(oriTime, floatValue) {
    hasAdd := InStr(floatValue, "+")
    hasReduce := InStr(floatValue, "-")
    if (!hasAdd && !hasReduce) {
        hasAdd := true
        hasReduce := true
    }

    oriTime := Integer(oriTime)
    floatValue := Integer(floatValue)
    value := Abs(oriTime * (floatValue * 0.01))
    maxValue := hasAdd ? oriTime + value : oriTime
    minValue := hasReduce ? oriTime - value : oriTime
    result := Max(0, Random(minValue, maxValue))
    return result
}

RandomizeValueByOffset(oriValue, floatValue) {
    hasAdd := InStr(floatValue, "+")
    hasReduce := InStr(floatValue, "-")
    if (!hasAdd && !hasReduce) {
        hasAdd := true
        hasReduce := true
    }

    oriValue := Integer(oriValue)
    value := Abs(floatValue)
    maxValue := hasAdd ? oriValue + value : oriValue
    minValue := hasReduce ? oriValue - value : oriValue
    return Random(minValue, maxValue)
}

; 本地时钟跨午夜会归零。计算耗时应使用 A_TickCount。
GetMillisecondsSinceMidnight() {
    return A_Hour * 3600 * 1000 + A_Min * 60 * 1000 + A_Sec * 1000 + A_mSec
}

StrToHex(str) {
    hex := ""
    loop parse str {
        hex .= Format("{:02X}", Ord(A_LoopField))
    }
    return hex
}

GetWinPos(ScreenX, ScreenY, hwnd := 0) {
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

GetCurWinPos() {
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY
    return GetWinPos(mouseX, mouseY)
}
