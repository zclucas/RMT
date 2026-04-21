#Requires AutoHotkey v2.0
SendKeyWrapper(KeyArrStr, holdTime, tableItem, index, keyType, Action) {
    static BrightKeyMap := Map("Bright_Up", 0, "Bright_Down", 0)
    static LogicNoKeyMap := Map("Volume_Up", 0, "Volume_Down", 0, "Volume_Mute", 0)
    static OnlyDownKeyMap := Map("WheelDown", 0, "WheelUp", 0)
    KeyArrStr := StrReplace(KeyArrStr, "逗号", ",")
    KeyArr := GetPressKeyArr(KeyArrStr)

    if (Action == SendLogicKey && LogicNoKeyMap.Has(key))   ;罗技没有的按键替换为普通按键
        Action := SendNormalKey

    if (keyType == 1 || keyType == 3) {     ;按下-点击
        for key in KeyArr {
            if (BrightKeyMap.Has(key)) {
                SetBrightnessByKey(key)
                continue
            }

            if (HandleKeyDownDown(key, tableItem, index, Action))   ;按下时按下特殊处理
                continue

            Action(key, 1, tableItem, index)  ; 按下
        }
    }

    if (keyType == 3) {     ;点击
        Sleep(holdTime)
    }

    if (keyType == 2 || keyType == 3) {     ;松开-点击
        for key in KeyArr {
            if (BrightKeyMap.Has(key) || OnlyDownKeyMap.Has(key))
                continue

            Action(key, 0, tableItem, index)  ; 松开
        }
    }
}

SendNormalKey(Key, state, tableItem, index) {
    Symbol := state == 1 ? "down" : "up"
    keySymbol := "{Blind}{" key " " Symbol "}"
    Send(keySymbol)

    if (MySoftData.OnlyDownKeyMap.Has(Key))
        return
    if (state == 1) {
        tableItem.HoldKeyArr[index][Key] := "Normal"
    }
    else {
        if (tableItem.HoldKeyArr[index].Has(Key)) {
            tableItem.HoldKeyArr[index].Delete(Key)
        }
    }
}

SendGameModeKey(Key, state, tableItem, index) {
    VK := GetKeyVK(Key)
    SC := GetKeySC(Key)

    if (VK == 1 || VK == 2 || VK == 4 || VK == 158 || VK == 159 || VK == 5 || VK == 6) {   ; 鼠标左键、右键、中键、下滑，上滑
        SendGameMouseKey(key, state, tableItem, index)
        return
    }

    ; 检测是否为扩展键
    isExtendedKey := false
    extendedArr := [0x25, 0x26, 0x27, 0x28, 0X2D, 0X2E, 0X23, 0X24, 0X21, 0X22]    ; 左、上、右、下箭头
    for index, value in extendedArr {
        if (VK == value) {
            isExtendedKey := true
            break
        }
    }

    if (state == 1) {
        DllCall("keybd_event", "UChar", VK, "UChar", SC, "UInt", isExtendedKey ? 0x1 : 0, "UPtr", 0)
        if (MySoftData.OnlyDownKeyMap.Has(Key))
            return
        tableItem.HoldKeyArr[index][key] := "Game"
    }
    else {
        DllCall("keybd_event", "UChar", VK, "UChar", SC, "UInt", (isExtendedKey ? 0x3 : 0x2), "UPtr", 0)
        if (tableItem.HoldKeyArr[index].Has(key)) {
            tableItem.HoldKeyArr[index].Delete(key)
        }
    }
}

SendGameMouseKey(key, state, tableItem, index) {
    scrollStep := 0
    mouseData := 0  ; 用于存储滚轮或侧键的数据（120/-120 或 0x0001/0x0002）

    if (StrCompare(Key, "LButton", false) == 0) {
        mouseDown := 0x0002  ; MOUSEEVENTF_LEFTDOWN
        mouseUp := 0x0004    ; MOUSEEVENTF_LEFTUP
    }
    else if (StrCompare(Key, "RButton", false) == 0) {
        mouseDown := 0x0008  ; MOUSEEVENTF_RIGHTDOWN
        mouseUp := 0x0010    ; MOUSEEVENTF_RIGHTUP
    }
    else if (StrCompare(Key, "MButton", false) == 0) {
        mouseDown := 0x0020  ; MOUSEEVENTF_MIDDLEDOWN
        mouseUp := 0x0040    ; MOUSEEVENTF_MIDDLEUP
    }
    else if (StrCompare(Key, "WheelUp", false) == 0) {
        mouseDown := 0x0800  ; MOUSEEVENTF_WHEEL
        mouseUp := 0x0000    ; 滚轮没有 "UP" 事件
        mouseData := 120     ; +120 表示向上滚动
    }
    else if (StrCompare(Key, "WheelDown", false) == 0) {
        mouseDown := 0x0800  ; MOUSEEVENTF_WHEEL
        mouseUp := 0x0000    ; 滚轮没有 "UP" 事件
        mouseData := -120    ; -120 表示向下滚动
    }
    else if (StrCompare(Key, "XButton1", false) == 0) {
        mouseDown := 0x0080  ; MOUSEEVENTF_XDOWN
        mouseUp := 0x0100    ; MOUSEEVENTF_XUP
        mouseData := 0x0001  ; 表示 XButton1
    }
    else if (StrCompare(Key, "XButton2", false) == 0) {
        mouseDown := 0x0080  ; MOUSEEVENTF_XDOWN
        mouseUp := 0x0100    ; MOUSEEVENTF_XUP
        mouseData := 0x0002  ; 表示 XButton2
    }

    if (state == 1) {
        DllCall("mouse_event", "UInt", mouseDown, "UInt", 0, "UInt", 0, "UInt", mouseData, "UInt", 0)
        tableItem.HoldKeyArr[index][key] := "GameMouse"
    }
    else {
        if (mouseUp != 0) {  ; 只有非滚轮事件才发送 UP
            DllCall("mouse_event", "UInt", mouseUp, "UInt", 0, "UInt", 0, "UInt", mouseData, "UInt", 0)
        }
        if (tableItem.HoldKeyArr[index].Has(key)) {
            tableItem.HoldKeyArr[index].Delete(key)
        }
    }
}

SendLogicKey(Key, state, tableItem, index) {
    if (!InitLogitechGHubNew())
        return

    Symbol := state == 1 ? "down" : "up"
    keySymbol := "{Blind}{" key " " Symbol "}"
    IbSend(keySymbol)

    if (MySoftData.OnlyDownKeyMap.Has(Key))
        return
    if (state == 1) {
        tableItem.HoldKeyArr[index][Key] := "Logic"
    }
    else {
        if (tableItem.HoldKeyArr[index].Has(Key)) {
            tableItem.HoldKeyArr[index].Delete(Key)
        }
    }
}

SendJoyBtnKey(key, state, tableItem, index) {
    JoyBtnName := SubStr(key, 4)
    if (JoyBtnName == "LT" || JoyBtnName == "RT") {
        Value := state == 1 ? 100 : 0
        MyViGJoySetState("Axis", JoyBtnName, Value)
    }
    else {
        MyViGJoySetState("Btn", JoyBtnName, state)
    }

    if (state == 1) {
        tableItem.HoldKeyArr[index][key] := "Joy"
    }
    else {
        if (tableItem.HoldKeyArr[index].Has(key)) {
            tableItem.HoldKeyArr[index].Delete(key)
        }
    }
}

SendJoyAxisKey(key, state, tableItem, index) {
    Value := InStr(key, "Min") ? 0 : 100
    Value := state == 1 ? Value : 50
    JoyAxisName := SubStr(key, 8, 2)
    MyViGJoySetState("Axis", JoyAxisName, Value)

    if (state == 1) {
        tableItem.HoldKeyArr[index][key] := "JoyAxis"
    }
    else {
        if (tableItem.HoldKeyArr[index].Has(key)) {
            tableItem.HoldKeyArr[index].Delete(key)
        }

    }
}

SendJoyDpadKey(key, state, tableItem, index) {
    RealKey := SubStr(key, 8)
    Value := state ? RealKey : "None"
    MyViGJoySetState("Dpad", Value, 0)

    if (state == 1 && Value != "None") {
        tableItem.HoldKeyArr[index][key] := "JoyDpad"
    }
    else {
        DpadArr := ["Up", "Down", "Left", "Right"]
        loop DpadArr.Length {
            curKey := DpadArr[A_Index]
            if (tableItem.HoldKeyArr[index].Has(curKey)) {
                tableItem.HoldKeyArr[index].Delete(curKey)
            }
        }
    }
}

SetBrightnessByKey(key, *) {
    if (key == "Bright_Down")
        ChangeBrightness(false)
    if (key == "Bright_Up")
        ChangeBrightness(true)
}

ChangeBrightness(isAdd) {
    CurrentBrightness := GetBrightness()
    Value := isAdd ? CurrentBrightness + 10 : CurrentBrightness - 10
    Value := Max(0, Min(100, Value)) ; 限制在 0-100
    wmi := ComObjGet("winmgmts:\\.\root\WMI")
    for item in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods") {
        item.WmiSetBrightness(1, Value)
    }
}

;处理宏按键：按下时按下
HandleKeyDownDown(key, tableItem, index, Action) {
    isSkip := false
    try {   ;按下前已经按下的话先松开
        state := GetKeyState(key)
        if (state == 1) {
            if (MySoftData.KeyDownDownType == 1)    ; 1自动松开
                Action(key, 0, tableItem, index)
            else if (MySoftData.KeyDownDownType == 2)   ;2忽略后续按下
                isSkip := true
            else if (MySoftData.KeyDownDownType == 3) { ;3允许该行为，不做任何干预
            }
        }
    }
    return isSkip
}
