; MouseControl.dll 鼠标驱动封装模块
; DLL 来源: https://github.com/Tjner0/MouseControl
; 使用前需安装旧版 GHub/LGS 驱动

#Requires AutoHotkey v2.0

global MCDllPath := A_ScriptDir "\Plugins\MouseControl.dll"
global MCHandle := 0
global MCIsInit := false

; 初始化 MouseControl.dll
MC_Init() {
    global MCHandle, MCIsInit, MCDllPath
    if (MCIsInit)
        return true

    MCHandle := DllCall("LoadLibrary", "Str", MCDllPath, "Ptr")
    if (!MCHandle) {
        OutputDebug("MouseControl.dll 加载失败，错误码: " A_LastError)
        return false
    }

    MCIsInit := true
    return true
}

; 释放
MC_Destroy() {
    global MCHandle, MCIsInit
    if (MCHandle) {
        DllCall("FreeLibrary", "Ptr", MCHandle)
        MCHandle := 0
    }
    MCIsInit := false
}

; ========== 相对移动 ==========

; 相对移动（瞬时）
MC_MoveR(x, y) {
    global MCDllPath
    DllCall(MCDllPath "\move_R", "Int", Integer(x), "Int", Integer(y))
}

; 绝对移动到目标坐标（使用 MouseGetPos + move_R，精度完美）
MC_MoveAbs(targetX, targetY) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&curX, &curY)
    MC_MoveR(targetX - curX, targetY - curY)
}

; 带速度的绝对移动（分步插值）
; targetX/Y: 目标屏幕坐标
; speed: 0=瞬移, 1~99=速度（值越大越快，与AHK MouseMove的Speed含义一致）
MC_MoveAbsSmooth(targetX, targetY, speed := 0) {
    if (speed <= 0 || speed >= 100) {
        MC_MoveAbs(targetX, targetY)
        return
    }

    CoordMode("Mouse", "Screen")
    MouseGetPos(&curX, &curY)

    dx := targetX - curX
    dy := targetY - curY
    dist := Sqrt(dx * dx + dy * dy)

    if (dist < 2)  ; 已经很接近
        return

    ; 根据速度计算步数和延迟（模拟AHK MouseMove的速度感）
    ; speed越大→步数少→延迟短→速度快
    stepCount := Max(1, Round(dist * (100 - speed) / 1500))
    stepDelay := Max(1, Round((100 - speed) / 10))

    stepX := dx / stepCount
    stepY := dy / stepCount

    Loop Round(stepCount) {
        MC_MoveR(Round(stepX), Round(stepY))
        Sleep(stepDelay)
    }

    ; 最后一步修正残余误差
    MouseGetPos(&finalX, &finalY)
    if (finalX != targetX || finalY != targetY)
        MC_MoveR(targetX - finalX, targetY - finalY)
}

; 带速度的相对移动
MC_MoveRSmooth(relX, relY, speed := 0) {
    if (speed <= 0 || speed >= 100) {
        MC_MoveR(relX, relY)
        return
    }

    dist := Sqrt(relX * relX + relY * relY)
    if (dist < 2)
        return

    stepCount := Max(1, Round(dist * (100 - speed) / 1500))
    stepDelay := Max(1, Round((100 - speed) / 10))

    stepX := relX / stepCount
    stepY := relY / stepCount

    remainingX := relX
    remainingY := relY

    Loop Round(stepCount) - 1 {
        MC_MoveR(Round(stepX), Round(stepY))
        remainingX -= Round(stepX)
        remainingY -= Round(stepY)
        Sleep(stepDelay)
    }
    ; 最后一步用剩余量确保精确到达
    MC_MoveR(Round(remainingX), Round(remainingY))
}

; ========== 点击 ==========

MC_ClickLeftDown() {
    global MCDllPath
    DllCall(MCDllPath "\click_Left_down")
}

MC_ClickLeftUp() {
    global MCDllPath
    DllCall(MCDllPath "\click_Left_up")
}

MC_ClickRightDown() {
    global MCDllPath
    DllCall(MCDllPath "\click_Right_down")
}

MC_ClickRightUp() {
    global MCDllPath
    DllCall(MCDllPath "\click_Right_up")
}

; 左键点击（按下+松开）
MC_ClickLeft() {
    MC_ClickLeftDown()
    Sleep(50)
    MC_ClickLeftUp()
}

; 右键点击
MC_ClickRight() {
    MC_ClickRightDown()
    Sleep(50)
    MC_ClickRightUp()
}

; 带坐标的点击（先移过去再点）
MC_MoveAndClick(x, y, clickCount := 1, whichButton := "L") {
    MC_MoveAbs(x, y)
    Sleep(30)
    Loop clickCount {
        if (whichButton == "L") {
            MC_ClickLeft()
        } else {
            MC_ClickRight()
        }
        if (A_Index < clickCount)
            Sleep(50)
    }
}
