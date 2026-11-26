#Requires AutoHotkey v2.0
#Include ..\Shared\RuntimeChoice.ahk

; 鼠标移动策略统一入口
; 按「按键类型」(ModeArr) + 「移动模式」(绝对/相对/游戏视角) 分发到 AHK / 罗技 / AHI / VIIPER
;
; keyMode 使用语义键：AHK Send / keybd_event / 罗技 / AHI / VIIPER。旧数字仅在入口兼容。
; moveMode 使用绝对移动 / 相对移动 / 游戏视角；游戏视角仅移动不点击。
;
; 速度约定（与编辑器一致）：uiSpeed 0~100，越大越快
; - AHK MouseMove / SetDefaultMouseSpeed：需转为 0 最快 ~ 100 最慢
; - 驱动与虚拟设备沿用各自的发送方式，步进速度按 AHK 的剩余距离衰减

; ========== 诊断日志 ==========
; 输出到 Log\MouseMoveDebug.log，用于排查位移偏差问题
global _mmLogInit := false
global _mmLogPath := ""

_MouseMoveLogInit() {
    global _mmLogInit, _mmLogPath
    if (_mmLogInit)
        return
    try {
        logDir := A_WorkingDir "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        _mmLogPath := logDir "\MouseMoveDebug.log"
        _mmLogInit := true
    }
}

MouseMoveLog(tag, msg) {
    global _mmLogInit, _mmLogPath
    if (!IsSet(RMTLogSysMinLevel) || !RMTLogLevelEnabled("debug", RMTLogSysMinLevel))
        return
    if (!_mmLogInit)
        _MouseMoveLogInit()
    if (_mmLogPath == "")
        return
    try {
        FileAppend(FormatTime(, "HH:mm:ss") "." SubStr(A_TickCount, -2) " [" tag "] " msg "`n"
            , _mmLogPath, "UTF-8")
    }
}

; 从宏项读取按键类型
GetMacroInputBackend(tableItem, index) {
    try
        return RuntimeChoice.Key("KeyMode", tableItem.Items[index].Mode)
    catch
        return "AHK Send"
}

NormalizeUiMouseSpeed(uiSpeed) {
    try
        return Max(0, Min(100, Integer(uiSpeed)))
    catch
        return 90
}

; AHK：0 最快，100 最慢
UiSpeedToAhkSpeed(uiSpeed) {
    uiSpeed := NormalizeUiMouseSpeed(uiSpeed)
    return (uiSpeed >= 100) ? 0 : (100 - uiSpeed)
}

; 初始化对应后端；失败返回 false（AHI/罗技不可用时上层应中止）
EnsureMouseBackend(keyMode, relative, usesButtons := false) {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    if (keyMode == "罗技")
        return !relative || InitMouseControl()
    if (keyMode == "VIIPER") {
        if (relative || usesButtons)
            ViiperInput.Stream("mouse")
        return true
    }
    if (keyMode == "AHI")
        return InitAHI()
    return true
}

; 按按键类型点击鼠标，默认左键。
MouseClickByKeyMode(keyMode, clickCount := 1, button := "LButton") {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    clickCount := Max(1, Integer(clickCount))
    if (keyMode == "VIIPER") {
        loop clickCount {
            try {
                ViiperInput.Key(button, true)
                Sleep(30)
            } finally ViiperInput.Key(button, false)
            Sleep(30)
        }
        return true
    }
    if (keyMode == "罗技") {
        if (!InitLogitechGHubNew())
            return false
        IbClick(button == "RButton" ? "Right" : "Left", , , clickCount)
        return true
    }
    if (keyMode == "AHI") {
        AhiClick(button == "RButton" ? "R" : "L", clickCount)
        return true
    }
    Click(Format("{} {}", button == "RButton" ? "Right" : "Left", clickCount))
    return true
}

; 绝对移动（屏幕坐标）；speed 为界面速度 0~100
MouseMoveAbsByKeyMode(keyMode, x, y, speed := 90, isHuman := false, item := "") {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    x := Round(x), y := Round(y)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (keyMode == "VIIPER") {
        if !MoveWindowsCursorAbs(x, y, uiSpeed, item)
            return false
        ; 单次核对落点，避免受限的光标位置触发错误点击。
        MouseGetPos(&endX, &endY)
        return endX == x && endY == y
    }
    SendMode("Event")
    CoordMode("Mouse", "Screen")

    if (isHuman && keyMode != "罗技" && keyMode != "AHI" && keyMode != "VIIPER") {
        hm := HumanMouse.GetInstance()
        hm.SetParams({ IsEnabled: true, Speed: uiSpeed })
        return hm.Move(x, y, , item)
    }

    MouseGetPos(&startX, &startY)
    if (keyMode == "罗技") {
        ok := MC_MoveAbsSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("ABS", Format("{} target=({},{}) start=({},{}) end=({},{}) dXY=({},{}) eXY=({},{}) speed={}"
            , keyMode, x, y, startX, startY, endX, endY
            , x - startX, y - startY, x - endX, y - endY, uiSpeed))
        return ok
    }
    if (keyMode == "AHI") {
        ok := AhiMoveAbsSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("ABS", Format("{} target=({},{}) start=({},{}) end=({},{}) dXY=({},{}) eXY=({},{}) speed={}"
            , keyMode, x, y, startX, startY, endX, endY
            , x - startX, y - startY, x - endX, y - endY, uiSpeed))
        return ok
    }
    return MoveAhkCursor(x, y, uiSpeed, false, item)
}

MoveWindowsCursorAbs(x, y, speed, item)
    => MoveDriverCursorAbs(x, y, speed, SendWindowsCursorPoint, item)

SendWindowsCursorPoint(x, y, *) => DllCall("SetCursorPos", "Int", x, "Int", y, "Int")

; AHK 每轴按剩余距离除以速度取步长，末段以最小步长到达目标。
; AHK 的最小步长是 32/65536 屏幕尺寸，驱动以整数像素/位移报告发送。
MouseMoveAxisStep(remaining, ahkSpeed, minStep, maxStep) {
    distance := Abs(remaining)
    step := ahkSpeed == 0 ? distance : Max(minStep, distance // ahkSpeed)
    return (remaining < 0 ? -1 : 1) * Min(distance, step, maxStep)
}

MoveDriverCursorAbs(x, y, speed, sendPoint, item) {
    CoordMode("Mouse", "Screen")
    left := SysGet(76), top := SysGet(77), width := SysGet(78), height := SysGet(79)
    x := Max(left, Min(left + width - 1, Round(x)))
    y := Max(top, Min(top + height - 1, Round(y)))
    MouseGetPos(&currentX, &currentY)
    ahkSpeed := UiSpeedToAhkSpeed(speed)
    minX := Max(1, Round(A_ScreenWidth / 2048))
    minY := Max(1, Round(A_ScreenHeight / 2048))
    while (currentX != x || currentY != y) {
        if (item && item.Killed)
            return false
        currentX += MouseMoveAxisStep(x - currentX, ahkSpeed, minX, width)
        currentY += MouseMoveAxisStep(y - currentY, ahkSpeed, minY, height)
        if !sendPoint(currentX, currentY, left, top, width, height)
            return false
        Sleep(A_MouseDelay)
    }
    MouseGetPos(&endX, &endY)
    return endX == x && endY == y && (!item || !item.Killed)
}

; 罗技和 AHI 的相对报告会受系统指针加速影响，每次读取实际光标再计算下一步。
MoveDriverCursorRel(dx, dy, speed, sendDelta, item) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&currentX, &currentY)
    left := SysGet(76), top := SysGet(77)
    targetX := Max(left, Min(left + SysGet(78) - 1, currentX + Integer(dx)))
    targetY := Max(top, Min(top + SysGet(79) - 1, currentY + Integer(dy)))
    ahkSpeed := UiSpeedToAhkSpeed(speed)
    minX := Max(1, Round(A_ScreenWidth / 2048))
    minY := Max(1, Round(A_ScreenHeight / 2048))
    ; 限制单个相对报告的幅度，降低指针加速导致的过冲。
    maxStep := ahkSpeed == 0 ? 127 : 50
    bestDistance := Abs(targetX - currentX) + Abs(targetY - currentY)
    stalled := 0
    loop 5000 {
        if (item && item.Killed)
            return false
        if (currentX == targetX && currentY == targetY)
            return true
        stepX := MouseMoveAxisStep(targetX - currentX, ahkSpeed, minX, maxStep)
        stepY := MouseMoveAxisStep(targetY - currentY, ahkSpeed, minY, maxStep)
        if !sendDelta(stepX, stepY)
            return false
        Sleep(A_MouseDelay)
        MouseGetPos(&currentX, &currentY)
        remaining := Abs(targetX - currentX) + Abs(targetY - currentY)
        if (remaining < bestDistance) {
            bestDistance := remaining
            stalled := 0
        } else if (++stalled >= 5) {
            ; 无进展时结束，避免在屏幕边缘或受限窗口里反复移动。
            return remaining <= 1 && (!item || !item.Killed)
        }
    }
    return currentX == targetX && currentY == targetY && (!item || !item.Killed)
}

; 相对移动；speed 为界面速度 0~100
MouseMoveRelByKeyMode(keyMode, x, y, speed := 90, isHuman := false, item := "") {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    x := Integer(x), y := Integer(y)
    if (keyMode == "VIIPER")
        return ViiperInput.Move(x, y, speed, item)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    SendMode("Event")
    CoordMode("Mouse", "Screen")

    if (isHuman && keyMode != "罗技" && keyMode != "AHI" && keyMode != "VIIPER") {
        MouseGetPos(&curX, &curY)
        hm := HumanMouse.GetInstance()
        hm.SetParams({ IsEnabled: true, Speed: uiSpeed })
        return hm.Move(curX + x, curY + y, , item)
    }

    MouseGetPos(&startX, &startY)
    if (keyMode == "罗技") {
        ok := MC_MoveRSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("REL", Format("{} delta=({},{}) start=({},{}) end=({},{}) expect=({},{}) err=({},{}) speed={}"
            , keyMode, x, y, startX, startY, endX, endY
            , startX + x, startY + y, (startX + x) - endX, (startY + y) - endY, uiSpeed))
        return ok
    }
    if (keyMode == "AHI") {
        ok := AhiMoveRSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("REL", Format("{} delta=({},{}) start=({},{}) end=({},{}) expect=({},{}) err=({},{}) speed={}"
            , keyMode, x, y, startX, startY, endX, endY
            , startX + x, startY + y, (startX + x) - endX, (startY + y) - endY, uiSpeed))
        return ok
    }
    return MoveAhkCursor(x, y, uiSpeed, true, item)
}

MoveAhkCursor(x, y, uiSpeed, relative, item) {
    if (item && item.Killed)
        return false
    ; 由 AHK 原生 MouseMove 控制速度与步进。返回后处理排队的停止消息。
    speed := UiSpeedToAhkSpeed(uiSpeed)
    MouseMove(x, y, speed, relative ? "R" : "")
    if (item && speed != 0)
        Sleep(-1)
    return !item || !item.Killed
}

; 游戏视角：相对位移，仅移动不点击；固定走 mouse_event，与按键类型无关
MoveMouseGameView(x, y) {
    x := Integer(x), y := Integer(y)
    ; MOUSEEVENTF_MOVE = 0x0001：相对移动（游戏通常通过 Raw Input 读取）
    DllCall("mouse_event", "UInt", 0x0001, "UInt", x, "UInt", y, "UInt", 0, "UPtr", 0)
    return true
}

; 相邻的累计位移相减，把舍入余量分配到各步。
DeltaMoveStep(delta, count, step) {
    return Round(delta * step / count) - Round(delta * (step - 1) / count)
}

; 统一策略：移动，可选随后点击
; speed: 界面速度 0~100（越大越快，100 瞬移）
; clickCount: 0=只移动；>0=移动后左键点击次数
; moveMode: 绝对移动 | 相对移动 | 游戏视角（忽略 clickCount/isHuman，走游戏视角语义）
MouseMoveByStrategy(keyMode, moveMode, x, y, speed := 90, clickCount := 0, isHuman := false, item := "") {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    moveMode := CmdEnumMoveMode(moveMode)
    clickCount := Integer(clickCount)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (item && item.Killed)
        return false

    ; 游戏视角与按键类型无关，直接走 mouse_event，无需初始化罗技/AHI 后端
    if (moveMode == "游戏视角")
        return MoveMouseGameView(x, y)

    if (!EnsureMouseBackend(keyMode, moveMode == "相对移动", clickCount > 0))
        return false

    ; AHK：带点击时用 Click 一步完成（含位移），避免相对位移执行两次
    if (clickCount > 0 && keyMode != "罗技" && keyMode != "AHI" && keyMode != "VIIPER" && (!item || uiSpeed == 100)) {
        SendMode("Event")
        CoordMode("Mouse", "Screen")
        SetDefaultMouseSpeed(UiSpeedToAhkSpeed(uiSpeed))
        if (moveMode == "相对移动")
            Click(Format("{} {} {} Relative", Integer(x), Integer(y), clickCount))
        else
            Click(Format("{} {} {}", Round(x), Round(y), clickCount))
        return true
    }

    ok := (moveMode == "相对移动")
        ? MouseMoveRelByKeyMode(keyMode, x, y, uiSpeed, isHuman && clickCount <= 0, item)
        : MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, isHuman && clickCount <= 0, item)
    if (!ok)
        return false

    if (clickCount > 0) {
        if (moveMode == "相对移动" && (keyMode == "罗技" || keyMode == "AHI" || keyMode == "VIIPER"))
            Sleep(30)
        if (item && item.Killed)
            return false
        return MouseClickByKeyMode(keyMode, clickCount)
    }
    return true
}

; 搜索等场景：屏幕绝对坐标移动，可选左击、右击；兼容旧动作名。
; speed: 界面速度 0~100
SearchMouseActionByStrategy(keyMode, actionType, x, y, speed := 90, clickCount := 1) {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    actionType := CmdEnumMouseAct(actionType)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (!EnsureMouseBackend(keyMode, false, actionType != "移动至目标" && actionType != "仅移动"))
        return false

    if (actionType == "移动至目标" || actionType == "仅移动")
        return MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, false)

    button := actionType == "移动至目标右键点击1次" ? "RButton" : "LButton"
    n := (actionType == "移动至目标点击2次") ? 2 : Max(1, Integer(clickCount))
    if (keyMode == "罗技" || keyMode == "AHI" || keyMode == "VIIPER") {
        if (!MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, false))
            return false
        return MouseClickByKeyMode(keyMode, n, button)
    }
    SendMode("Event")
    CoordMode("Mouse", "Screen")
    SetDefaultMouseSpeed(UiSpeedToAhkSpeed(uiSpeed))
    Click(Format("{} {} {} {}", button == "RButton" ? "Right" : "Left", Round(x), Round(y), n))
    return true
}

; 拖拽统一入口：绝对模式先定位起点，相对模式从当前位置按偏移拖动。
; 按下后始终在 finally 松开，避免移动异常导致左键保持按下。
MouseDragByStrategy(tableItem, index, keyMode, moveMode, x, y, endX, endY, speed := 90, isHuman := false) {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    moveMode := CmdEnumMoveMode(moveMode)
    item := GetItemByIndex(tableItem, index)
    if (item && item.Killed)
        return false
    if (!EnsureMouseBackend(keyMode, moveMode == "相对移动", true))
        return false
    if (moveMode == "绝对移动" && !MouseMoveAbsByKeyMode(keyMode, x, y, speed, false, item))
        return false
    if (keyMode == "罗技" && !InitLogitechGHubNew())
        return false
    try {
        MouseDragButtonByKeyMode(keyMode, true, tableItem, index)
        return (moveMode == "相对移动")
            ? MouseMoveRelByKeyMode(keyMode, x, y, speed, isHuman, item)
            : MouseMoveAbsByKeyMode(keyMode, endX, endY, speed, isHuman, item)
    }
    finally {
        if (!item || !item.Killed || item.HoldKey.Has("LButton"))
            MouseDragButtonByKeyMode(keyMode, false, tableItem, index)
    }
}

MouseDragButtonByKeyMode(keyMode, isDown, tableItem, index) {
    keyMode := RuntimeChoice.Key("KeyMode", keyMode)
    if (keyMode == "VIIPER")
        return SendViiperKey("LButton", isDown, tableItem, index)
    if (keyMode == "罗技")
        IbClick(isDown ? "Down" : "Up")
    else if (keyMode == "AHI") {
        if (isDown)
            AhiMouseDown("L")
        else
            AhiMouseUp("L")
    }
    else {
        SendMode("Event")
        Click(isDown ? "Down" : "Up")
    }
    bucket := GetHoldBucket(tableItem, index)
    if (isDown)
        TrackDown(bucket, "LButton", keyMode == "罗技" ? "Logic" : keyMode == "AHI" ? "AHI" : "Normal", tableItem, index)
    else
        TrackUp(bucket, "LButton", tableItem, index)
}
