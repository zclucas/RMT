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
    WinX := 0
    WinY := 0
    DllCall("SetProcessDPIAware")
    if (hwnd == 0) {
        hwnd := DllCall("User32\WindowFromPoint", "int64", (ScreenY << 32) | (ScreenX & 0xFFFFFFFF), "ptr")
    }
    try {

        ; 获取该窗口的主窗口（避免偏移）
        GA_ROOT := 2
        rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", GA_ROOT, "ptr")

        ; 创建结构体 POINT
        pt := Buffer(8, 0)
        NumPut("int", ScreenX, pt, 0)  ; X
        NumPut("int", ScreenY, pt, 4)  ; Y

        ; 屏幕坐标转客户区
        DllCall("User32\ScreenToClient", "ptr", rootHwnd, "ptr", pt)

        WinX := NumGet(pt, 0, "int")
        WinY := NumGet(pt, 4, "int")
    }
    return [WinX, WinY]
}

GetCurWinPos() {
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY
    return GetWinPos(mouseX, mouseY)
}
