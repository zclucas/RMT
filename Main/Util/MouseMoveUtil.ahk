#Requires AutoHotkey v2.0

; 鼠标移动策略统一入口
; 按「按键类型」(ModeArr) + 「移动模式」(绝对/相对/游戏视角) 分发到 AHK / 罗技 / AHI
;
; keyMode : 1 默认(AHK) | 2 游戏(AHK键) | 3 罗技 | 4 AHI
; moveMode: 0 绝对 | 1 相对 | 2 游戏视角（相对位移，仅移动不点击，与按键类型无关）
;
; 速度约定（与编辑器一致）：uiSpeed 0~100，越大越快
; - AHK MouseMove / SetDefaultMouseSpeed：需转为 0 最快 ~ 100 最慢
; - 罗技 / AHI 平滑：按步长+延时插值，90+ 步长指数增长

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
    if (!_mmLogInit)
        _MouseMoveLogInit()
    if (_mmLogPath == "")
        return
    try {
        modeStr := "?" ; fallback
        FileAppend(FormatTime(, "HH:mm:ss") "." SubStr(A_TickCount, -2) " [" tag "] " msg "`n"
            , _mmLogPath, "UTF-8")
    }
}

; keyMode → 可读名称
_MM_KM_NAME := Map(1, "AHK", 2, "AHK-Game", 3, "Logitech", 4, "AHI")
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

; 罗技/AHI：越大越快；0 表示最慢（用 1，避免旧接口把 <=0 当成瞬移）
UiSpeedToDriverSpeed(uiSpeed) {
    uiSpeed := NormalizeUiMouseSpeed(uiSpeed)
    if (uiSpeed >= 100)
        return 100
    if (uiSpeed <= 0)
        return 1
    return uiSpeed
}

; 初始化对应后端；失败返回 false（AHI/罗技不可用时上层应中止）
EnsureMouseBackend(keyMode) {
    keyMode := Integer(keyMode)
    if (keyMode == 3) {
        if (!InitMouseControl())
            return false
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
MouseMoveAbsByKeyMode(keyMode, x, y, speed := 90, isHuman := false) {
    keyMode := Integer(keyMode)
    x := Round(x), y := Round(y)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    SendMode("Event")
    CoordMode("Mouse", "Screen")

    if (isHuman && keyMode != 3 && keyMode != 4) {
        hm := HumanMouse.GetInstance()
        hm.SetParams({ IsEnabled: true, Speed: uiSpeed })
        hm.Move(x, y)
        return true
    }

    MouseGetPos(&startX, &startY)
    if (keyMode == 3) {
        MC_MoveAbsSmooth(x, y, UiSpeedToDriverSpeed(uiSpeed))
        MouseGetPos(&endX, &endY)
        MouseMoveLog("ABS", Format("{} target=({},{}) start=({},{}) end=({},{}) dXY=({},{}) eXY=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
            , x - startX, y - startY, x - endX, y - endY, uiSpeed))
        return true
    }
    if (keyMode == 4) {
        AhiMoveAbsSmooth(x, y, UiSpeedToDriverSpeed(uiSpeed))
        MouseGetPos(&endX, &endY)
        MouseMoveLog("ABS", Format("{} target=({},{}) start=({},{}) end=({},{}) dXY=({},{}) eXY=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
            , x - startX, y - startY, x - endX, y - endY, uiSpeed))
        return true
    }
    MouseMove(x, y, UiSpeedToAhkSpeed(uiSpeed))
    return true
}

; 相对移动；speed 为界面速度 0~100
MouseMoveRelByKeyMode(keyMode, x, y, speed := 90, isHuman := false) {
    keyMode := Integer(keyMode)
    x := Integer(x), y := Integer(y)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    SendMode("Event")
    CoordMode("Mouse", "Screen")

    if (isHuman && keyMode != 3 && keyMode != 4) {
        MouseGetPos(&curX, &curY)
        hm := HumanMouse.GetInstance()
        hm.SetParams({ IsEnabled: true, Speed: uiSpeed })
        hm.Move(curX + x, curY + y)
        return true
    }

    MouseGetPos(&startX, &startY)
    if (keyMode == 3) {
        MC_MoveRSmooth(x, y, UiSpeedToDriverSpeed(uiSpeed))
        MouseGetPos(&endX, &endY)
        MouseMoveLog("REL", Format("{} delta=({},{}) start=({},{}) end=({},{}) expect=({},{}) err=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
            , startX + x, startY + y, (startX + x) - endX, (startY + y) - endY, uiSpeed))
        return true
    }
    if (keyMode == 4) {
        AhiMoveRSmooth(x, y, UiSpeedToDriverSpeed(uiSpeed))
        MouseGetPos(&endX, &endY)
        MouseMoveLog("REL", Format("{} delta=({},{}) start=({},{}) end=({},{}) expect=({},{}) err=({},{}) speed={}"
            , _MM_KeyModeName(keyMode), x, y, startX, startY, endX, endY
            , startX + x, startY + y, (startX + x) - endX, (startY + y) - endY, uiSpeed))
        return true
    }
    MouseMove(x, y, UiSpeedToAhkSpeed(uiSpeed), "R")
    return true
}

; 游戏视角：相对位移，仅移动不点击；固定走 mouse_event，与按键类型无关
MouseMoveGameViewByKeyMode(keyMode, x, y, speed := 90) {
    x := Integer(x), y := Integer(y)
    ; MOUSEEVENTF_MOVE = 0x0001：相对移动（游戏通常通过 Raw Input 读取）
    DllCall("mouse_event", "UInt", 0x0001, "UInt", x, "UInt", y, "UInt", 0, "UPtr", 0)
    return true
}

; 统一策略：移动，可选随后点击
; speed: 界面速度 0~100（越大越快，100 瞬移）
; clickCount: 0=只移动；>0=移动后左键点击次数
; moveMode: 0 绝对 | 1 相对 | 2 游戏视角（忽略 clickCount/isHuman，走游戏视角语义）
MouseMoveByStrategy(keyMode, moveMode, x, y, speed := 90, clickCount := 0, isHuman := false) {
    keyMode := Integer(keyMode)
    moveMode := Integer(moveMode)
    clickCount := Integer(clickCount)
    uiSpeed := NormalizeUiMouseSpeed(speed)

    ; 游戏视角与按键类型无关，直接走 mouse_event，无需初始化罗技/AHI 后端
    if (moveMode == 2)
        return MouseMoveGameViewByKeyMode(keyMode, x, y, uiSpeed)

    if (!EnsureMouseBackend(keyMode))
        return false

    ; AHK：带点击时用 Click 一步完成（含位移），避免相对位移执行两次
    if (clickCount > 0 && keyMode != 3 && keyMode != 4) {
        SendMode("Event")
        CoordMode("Mouse", "Screen")
        SetDefaultMouseSpeed(UiSpeedToAhkSpeed(uiSpeed))
        if (moveMode == 1)
            Click(Format("{} {} {} Relative", Integer(x), Integer(y), clickCount))
        else
            Click(Format("{} {} {}", Round(x), Round(y), clickCount))
        return true
    }

    ok := (moveMode == 1)
        ? MouseMoveRelByKeyMode(keyMode, x, y, uiSpeed, isHuman && clickCount <= 0)
        : MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, isHuman && clickCount <= 0)
    if (!ok)
        return false

    if (clickCount > 0) {
        if (moveMode == 1)
            Sleep(30)
        return MouseClickByKeyMode(keyMode, clickCount)
    }
    return true
}

; 搜索等场景：屏幕绝对坐标移动，可选点击/双击
; actionType: 2=只移动 | 3=移动后点击 | 4=移动后双击
; speed: 界面速度 0~100
SearchMouseActionByStrategy(keyMode, actionType, x, y, speed := 90, clickCount := 1) {
    keyMode := Integer(keyMode)
    actionType := Integer(actionType)
    uiSpeed := NormalizeUiMouseSpeed(speed)
    if (!EnsureMouseBackend(keyMode))
        return false

    if (actionType == 2)
        return MouseMoveAbsByKeyMode(keyMode, x, y, uiSpeed, false)

    n := (actionType == 4) ? 2 : Max(1, Integer(clickCount))
    if (keyMode == 3 || keyMode == 4) {
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
