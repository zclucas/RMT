; MouseControl.dll 鼠标驱动封装模块
; DLL 来源: https://github.com/Tjner0/MouseControl
; 使用前需安装旧版 GHub/LGS 驱动

#Requires AutoHotkey v2.0

; 主进程 A_ScriptDir 指向项目根目录，Worker(Work.exe) 位于 Thread 子目录，
; 因此需回退一级定位 Plugins\MouseControl.dll，否则多线程下罗技鼠标移动无效
global MCDllPath := FileExist(A_ScriptDir "\Plugins\MouseControl.dll")
    ? A_ScriptDir "\Plugins\MouseControl.dll"
    : A_ScriptDir "\..\Plugins\MouseControl.dll"
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
    return true
}

; 绝对移动到目标屏幕坐标。
MC_MoveAbs(targetX, targetY) => MC_MoveAbsSmooth(targetX, targetY, 100)

; MouseControl.dll 的 move_Abs 使用 SendInput，按主屏尺寸做整数换算。
; 直接使用 Windows 屏幕像素坐标，避免副屏坐标偏差。
MC_MoveAbsSmooth(targetX, targetY, speed := 0, item := "")
    => MoveWindowsCursorAbs(targetX, targetY, speed, item)

MC_MoveRSmooth(relX, relY, speed := 0, item := "")
    => MoveDriverCursorRel(relX, relY, speed, MC_MoveR, item)

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
