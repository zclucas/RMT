; AHI Driver Wrapper
; Description: 封装 AutoHotInterception 为通用输入驱动（类似 IbInputSimulator）
; Version: 1.4 (支持键盘+鼠标智能识别)
; 基于 evilC/AutoHotInterception 库

#Requires AutoHotkey v2.0
#Include AutoHotInterception.ahk

global AHI_Driver := ""
global AHI_KeyboardId := 1   ; 默认使用第一个键盘设备
global AHI_MouseId := 11     ; 默认使用第一个鼠标设备

; 鼠标键映射表（名称 → AHI 按钮编号）
; 基于 Interception API: interception.h
; BUTTON_1=左键(0), BUTTON_2=右键(1), BUTTON_3=中键(2), BUTTON_4=X1(3), BUTTON_5=X2(4)
; 参考: https://github.com/oblitum/Interception/blob/master/library/interception.h
global AHI_MouseBtnMap := Map(
    "LButton", 0,    ; 左键 → BUTTON_1 (INTERCEPTION_MOUSE_LEFT_BUTTON_DOWN = 0x001)
    "RButton", 1,    ; 右键 → BUTTON_2 (INTERCEPTION_MOUSE_RIGHT_BUTTON_DOWN = 0x004)
    "MButton", 2,    ; 中键 → BUTTON_3 (INTERCEPTION_MOUSE_MIDDLE_BUTTON_DOWN = 0x010)
    "XButton1", 3,   ; 侧键1 → BUTTON_4 (INTERCEPTION_MOUSE_BUTTON_4_DOWN = 0x040)
    "XButton2", 4    ; 侧键2 → BUTTON_5 (INTERCEPTION_MOUSE_BUTTON_5_DOWN = 0x100)
)

; 延迟初始化函数（首次使用时调用）
InitAHI() {
    if (IsObject(AHI_Driver)) {
        return true
    }

    try {
        global AHI_Driver := AutoHotInterception()
        AHI_Driver.SetState(false)
        return true
    } catch as err {
        MsgBox(
            "❌ AHI 驱动加载失败！`n`n"
            "错误信息: " err.Message "`n`n"
            "请检查：`n"
            "1. 是否已安装 Interception 驱动？`n"
            "2. Plugins\AhiDriver\x64\interception.dll 是否存在？`n"
            "3. 是否以管理员权限运行？`n`n"
            "驱动下载地址:`n"
            "https://github.com/oblitum/Interception/releases",
            "AHI 错误", 16
        )
        return false
    }
}

AhiDestroy() {
    global AHI_Driver
    if (IsObject(AHI_Driver)) {
        try {
            AHI_Driver.SetState(false)
        }
    }
}

AhiSetState(state) {
    if (!InitAHI())
        return
    
    global AHI_Driver
    AHI_Driver.SetState(state)
}

; 发送单个按键（自动识别键盘/鼠标）
AhiSendKey(key, state := 1) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_KeyboardId, AHI_MouseId, AHI_MouseBtnMap

    ; 检查是否为鼠标按键
    if (AHI_MouseBtnMap.Has(key)) {
        btnNum := AHI_MouseBtnMap[key]

        if (state == 1) {
            AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
        } else {
            AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
        }
        return true
    }

    ; 滚轮特殊处理
    if (key == "WheelUp") {
        if (state == 1)
            AHI_Driver.SendMouseMoveRelative(AHI_MouseId, 0, 120)
        return true
    }
    if (key == "WheelDown") {
        if (state == 1)
            AHI_Driver.SendMouseMoveRelative(AHI_MouseId, 0, -120)
        return true
    }

    ; 键盘按键
    scanCode := GetKeySC(key)
    if (scanCode != 0) {
        AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, state)
        return true
    }
    
    return false
}

; 发送按键字符串（支持组合键，自动识别键盘/鼠标）
; 注意：此函数用于独立发送完整按键序列（按下+释放），与 SendAHIKey 不同
AhiSend(keys) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_KeyboardId, AHI_MouseId, AHI_MouseBtnMap
    keys := Trim(keys)
    if (keys == "")
        return false

    ; 预处理：提取大括号内的内容（如 {LButton}, {Ctrl}）
    pos := 1
    while (pos <= StrLen(keys)) {
        char := SubStr(keys, pos, 1)

        if (char == "{") {
            ; 查找匹配的 }
            endPos := InStr(keys, "}", , pos + 1)
            if (endPos == 0)
                endPos := StrLen(keys) + 1

            ; 提取括号内的键名
            keyName := SubStr(keys, pos + 1, endPos - pos - 1)

            ; 处理特殊键
            if (AHI_MouseBtnMap.Has(keyName)) {
                btnNum := AHI_MouseBtnMap[keyName]
                AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
                AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
            } else if (keyName == "WheelUp") {
                AHI_Driver.SendMouseMoveRelative(AHI_MouseId, 0, 120)
            } else if (keyName == "WheelDown") {
                AHI_Driver.SendMouseMoveRelative(AHI_MouseId, 0, -120)
            } else {
                ; 键盘按键
                scanCode := GetKeySC(keyName)
                if (scanCode != 0) {
                    AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 1)
                    AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 0)
                }
            }

            pos := endPos + 1
        } else if (char != " ") {
            ; 单个字符键盘按键
            scanCode := GetKeySC(char)
            if (scanCode != 0) {
                AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 1)
                AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 0)
            }

            pos++
        } else {
            ; 空格，跳过
            pos++
        }
    }

    return true
}

; 发送修饰键 + 普通键组合（辅助函数，一般不直接用于宏系统）
AhiSendCombo(key, modifiers*) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_KeyboardId

    for mod in modifiers {
        modScanCode := GetKeySC(mod)
        if (modScanCode != 0)
            AHI_Driver.SendKeyEvent(AHI_KeyboardId, modScanCode, 1)
    }

    keyScanCode := GetKeySC(key)
    if (keyScanCode != 0) {
        AHI_Driver.SendKeyEvent(AHI_KeyboardId, keyScanCode, 1)
        AHI_Driver.SendKeyEvent(AHI_KeyboardId, keyScanCode, 0)
    }

    Loop (modifiers.Length) {
        mod := modifiers[modifiers.Length - A_Index + 1]
        modScanCode := GetKeySC(mod)
        if (modScanCode != 0)
            AHI_Driver.SendKeyEvent(AHI_KeyboardId, modScanCode, 0)
    }

    return true
}

; 鼠标点击（辅助函数，一般不直接用于宏系统）
AhiClick(whichButton := "L", args*) {
    if (!InitAHI()) {
        Click(whichButton, args*)
        return
    }

    global AHI_Driver, AHI_MouseId, AHI_MouseBtnMap

    ; 支持完整按钮名或缩写
    btnName := whichButton
    if (btnName == "L")
        btnName := "LButton"
    else if (btnName == "R")
        btnName := "RButton"
    else if (btnName == "M")
        btnName := "MButton"

    btnNum := AHI_MouseBtnMap.Has(btnName) ? AHI_MouseBtnMap[btnName] : 0

    AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
    AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
}

; 鼠标按下/释放（用于拖拽等）
AhiMouseDown(whichButton := "L") {
    if (!InitAHI())
        return

    global AHI_Driver, AHI_MouseId, AHI_MouseBtnMap
    
    btnName := (whichButton == "L") ? "LButton" : ((whichButton == "R") ? "RButton" : "MButton")
    btnNum := AHI_MouseBtnMap.Has(btnName) ? AHI_MouseBtnMap[btnName] : 0

    AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
}

AhiMouseUp(whichButton := "L") {
    if (!InitAHI())
        return

    global AHI_Driver, AHI_MouseId, AHI_MouseBtnMap
    
    btnName := (whichButton == "L") ? "LButton" : ((whichButton == "R") ? "RButton" : "MButton")
    btnNum := AHI_MouseBtnMap.Has(btnName) ? AHI_MouseBtnMap[btnName] : 0

    AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
}

; 鼠标移动（相对）
AhiMouseMove(x, y, speed := 0) {
    if (!InitAHI()) {
        MouseMove(x, y, speed)
        return
    }

    global AHI_Driver, AHI_MouseId
    if (speed > 0) {
        steps := Max(1, speed)
        dx := x / steps
        dy := y / steps
        Loop steps {
            AHI_Driver.SendMouseMoveRelative(AHI_MouseId, Round(dx), Round(dy))
            Sleep(10)
        }
    } else {
        AHI_Driver.SendMouseMoveRelative(AHI_MouseId, x, y)
    }
}

; 鼠标移动到绝对位置
AhiMouseMoveTo(x, y) {
    if (!InitAHI()) {
        MouseMove(x, y)
        return
    }

    global AHI_Driver, AHI_MouseId
    AHI_Driver.MoveCursor(x, y, "Screen", AHI_MouseId)
}
