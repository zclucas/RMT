#Requires AutoHotkey v2.0

; 鼠标移动策略统一入口
; 按「按键类型」(ModeArr) + 「移动模式」(绝对/相对/游戏视角) 分发到 AHK / 罗技 / AHI / VIIPER
;
; keyMode : 1 默认(AHK) | 2 游戏(AHK键) | 3 罗技 | 4 AHI | 5 VIIPER
; moveMode: 0 绝对 | 1 相对 | 2 游戏视角（相对位移，仅移动不点击，与按键类型无关）
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

; keyMode → 可读名称
_MM_KM_NAME := Map(1, "AHK", 2, "AHK-Game", 3, "Logitech", 4, "AHI", 5, "VIIPER")
_MM_ModeName(mode) => (mode == 0 ? "Abs" : (mode == 1 ? "Rel" : "GameView"))

_MM_KeyModeName(km) {
    return _MM_KM_NAME.Has(Integer(km)) ? _MM_KM_NAME[Integer(km)] : "KM" km
}

; 从宏项读取按键类型
GetMacroKeyMode(tableItem, index) {
    try
        return Integer(tableItem.Items[index].Mode)
    catch
        return 1
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
    keyMode := Integer(keyMode)
    if (keyMode == 3)
        return !relative || InitMouseControl()
    if (keyMode == 5) {
        if (relative || usesButtons)
            ViiperInput.Stream("mouse")
        return true
    }
    if (keyMode == 4)
        return InitAHI()
    return true
}

; 按按键类型点击左键
MouseClickByKeyMode(keyMode, clickCount := 1) {
    keyMode := Integer(keyMode)
    clickCount := Max(1, Integer(clickCount))
    if (keyMode == 5) {
        loop clickCount {
            try {
                ViiperInput.Key("LButton", true)
                Sleep(30)
            } finally ViiperInput.Key("LButton", false)
            Sleep(30)
        }
        return true
    }
    if (keyMode == 3) {
        if (!InitLogitechGHubNew())
            return false
        IbClick("Left", , , clickCount)
        return true
    }
    if (keyMode == 4) {
        AhiClick("L", clickCount)
        return true
    }
    Click(, , , clickCount)
    return true
}

; 绝对移动（屏幕坐标）；speed 为界面速度 0~100
MouseMoveAbsByKeyMode(keyMode, x, y, speed := 90, isHuman := false, item := "") {
    keyMode := Integer(keyMode)
    x := Round(x), y := Round(y)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (keyMode == 5) {
        if !MoveWindowsCursorAbs(x, y, uiSpeed, item)
            return false
        ; 单次核对落点，避免受限的光标位置触发错误点击。
        MouseGetPos(&endX, &endY)
        return endX == x && endY == y
    }
    SendMode("Event")
    CoordMode("Mouse", "Screen")

    if (isHuman && keyMode != 3 && keyMode != 4 && keyMode != 5) {
        hm := HumanMouse.GetInstance()
        hm.SetParams({ IsEnabled: true, Speed: uiSpeed })
        return hm.Move(x, y, , item)
    }

    MouseGetPos(&startX, &startY)
    if (keyMode == 3) {
        ok := MC_MoveAbsSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("ABS", Format("{} target=({},{}) start=({},{}) end=({},{}) dXY=({},{}) eXY=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
            , x - startX, y - startY, x - endX, y - endY, uiSpeed))
        return ok
    }
    if (keyMode == 4) {
        ok := AhiMoveAbsSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("ABS", Format("{} target=({},{}) start=({},{}) end=({},{}) dXY=({},{}) eXY=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
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
    keyMode := Integer(keyMode)
    x := Integer(x), y := Integer(y)
    if (keyMode == 5)
        return ViiperInput.Move(x, y, speed, item)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    SendMode("Event")
    CoordMode("Mouse", "Screen")

    if (isHuman && keyMode != 3 && keyMode != 4 && keyMode != 5) {
        MouseGetPos(&curX, &curY)
        hm := HumanMouse.GetInstance()
        hm.SetParams({ IsEnabled: true, Speed: uiSpeed })
        return hm.Move(curX + x, curY + y, , item)
    }

    MouseGetPos(&startX, &startY)
    if (keyMode == 3) {
        ok := MC_MoveRSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("REL", Format("{} delta=({},{}) start=({},{}) end=({},{}) expect=({},{}) err=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
            , startX + x, startY + y, (startX + x) - endX, (startY + y) - endY, uiSpeed))
        return ok
    }
    if (keyMode == 4) {
        ok := AhiMoveRSmooth(x, y, uiSpeed, item)
        MouseGetPos(&endX, &endY)
        MouseMoveLog("REL", Format("{} delta=({},{}) start=({},{}) end=({},{}) expect=({},{}) err=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
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
MouseMoveGameViewByKeyMode(keyMode, x, y, speed := 90) {
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
    keyMode := Integer(keyMode)
    moveMode := CmdEnumMoveMode(moveMode)
    clickCount := Integer(clickCount)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (item && item.Killed)
        return false

    ; 游戏视角与按键类型无关，直接走 mouse_event，无需初始化罗技/AHI 后端
    if (moveMode == "游戏视角")
        return MouseMoveGameViewByKeyMode(keyMode, x, y, uiSpeed)

    if (!EnsureMouseBackend(keyMode, moveMode == "相对移动", clickCount > 0))
        return false

    ; AHK：带点击时用 Click 一步完成（含位移），避免相对位移执行两次
    if (clickCount > 0 && keyMode != 3 && keyMode != 4 && keyMode != 5 && (!item || uiSpeed == 100)) {
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
        if (moveMode == "相对移动" && keyMode >= 3)
            Sleep(30)
        if (item && item.Killed)
            return false
        return MouseClickByKeyMode(keyMode, clickCount)
    }
    return true
}

; 搜索等场景：屏幕绝对坐标移动，可选点击/双击
; actionType: 移动至目标 | 移动至目标点击1次 | 移动至目标点击2次
; speed: 界面速度 0~100
SearchMouseActionByStrategy(keyMode, actionType, x, y, speed := 90, clickCount := 1) {
    keyMode := Integer(keyMode)
    actionType := CmdEnumMouseAct(actionType)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (!EnsureMouseBackend(keyMode, false, actionType != "移动至目标"))
        return false

    if (actionType == "移动至目标")
        return MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, false)

    n := (actionType == "移动至目标点击2次") ? 2 : Max(1, Integer(clickCount))
    if (keyMode == 3 || keyMode == 4 || keyMode == 5) {
        if (!MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, false))
            return false
        return MouseClickByKeyMode(keyMode, n)
    }
    SendMode("Event")
    CoordMode("Mouse", "Screen")
    SetDefaultMouseSpeed(UiSpeedToAhkSpeed(uiSpeed))
    Click(Format("{} {} {}", Round(x), Round(y), n))
    return true
}

; 拖拽统一入口：绝对模式先定位起点，相对模式从当前位置按偏移拖动。
; 按下后始终在 finally 松开，避免移动异常导致左键保持按下。
MouseDragByStrategy(tableItem, index, keyMode, moveMode, x, y, endX, endY, speed := 90, isHuman := false) {
    keyMode := Integer(keyMode)
    moveMode := CmdEnumMoveMode(moveMode)
    item := GetItemByIndex(tableItem, index)
    if (item && item.Killed)
        return false
    if (!EnsureMouseBackend(keyMode, moveMode == "相对移动", true))
        return false
    if (moveMode == "绝对移动" && !MouseMoveAbsByKeyMode(keyMode, x, y, speed, false, item))
        return false
    if (keyMode == 3 && !InitLogitechGHubNew())
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
    if (keyMode == 5)
        return SendViiperKey("LButton", isDown, tableItem, index)
    if (keyMode == 3)
        IbClick(isDown ? "Down" : "Up")
    else if (keyMode == 4) {
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
        TrackDown(bucket, "LButton", keyMode == 3 ? "Logic" : keyMode == 4 ? "AHI" : "Normal", tableItem, index)
    else
        TrackUp(bucket, "LButton", tableItem, index)
}
