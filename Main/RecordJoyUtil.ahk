#Requires AutoHotkey v2.0
RecordControllerNum := 10
RecordJoyFloat := 10
RecordAxisMaxValue := 100
RecordJoyIndexArr := []

RecordJoyAxises := Map("JoyXMin", 0, "JoyXMax", 100, "JoyYMin", 0, "JoyYMax", 100, "JoyZMin", 0, "JoyZMax", 100,
    "JoyRMin", 0, "JoyRMax", 100, "JoyUMin", 0, "JoyUMax", 100, "JoyVMin", 0, "JoyVMax", 100)
RecordJoyPOVMap := Map("JoyPOV_0", 0, "JoyPOV_9000", 9000, "JoyPOV_18000", 18000, "JoyPOV_27000", 27000)

XboxJoyAndPOVMap := Map("Joy1", 12, "Joy2", 13, "Joy3", 14, "Joy4", 15, "Joy5", 8, "Joy6", 9, "Joy7", 5,
    "Joy8", 4, "Joy9", 6, "Joy10", 7,
    "JoyPOV_0", 0, "JoyPOV_9000", 3, "JoyPOV_18000", 1, "JoyPOV_27000", 2)

XboxJosAxisMap := Map("JoyXMin", -32768, "JoyXMax", 32767, "JoyYMin", -32768, "JoyYMax", 32767, "JoyZMin",
    255, "JoyZMax", 255, "JoyRMin", -32768, "JoyRMax", 32767, "JoyUMin", -32768, "JoyUMax", 32767, "JoyVMin", -
    32768, "JoyVMax", 32767)

RecordXInputStates := []

DetectControllerJoyType(idx) {
    ; XInput slot idx-1 → Xbox, 否则 PS5
    ; Windows 上 XInput 用户 N 对应 DirectInput 索引 N+1
    try {
        xiState := Buffer(16)
        err := DllCall("XInput1_4\XInputGetState", "uint", idx - 1, "ptr", xiState)
        if (!err)
            return "Xbox"
    }
    return "PS5"
}

CheckBtnOnIndex(rawKey, idx) {
    return GetKeyState(idx rawKey)
}

CheckPOVOnIndex(rawKey, idx) {
    cont_info := GetKeyState(idx "JoyInfo")
    if !InStr(cont_info, "P")
        return false
    state := GetKeyState(idx "JoyPOV")
    value := RecordJoyPOVMap.Get(rawKey)
    return (state == value)
}

RecordJoyTimer() {
    global RecordXInputStates, MainSoftData, MySoftData

    if (!UIControls.ToolCheckRecord.Value)
        return

    static lastTick := 0
    debounceMs := MainSoftData.RecordJoyInterval
    if (debounceMs < 20)
        debounceMs := 20
    if (A_TickCount - lastTick < debounceMs)
        return
    lastTick := A_TickCount

    static axisBase := Map()

    RecordRefreshJoyIndexArr()
    RecordXInputStates := RecordCollectXInputStates()

    ; 收集所有通用键名（JoyN、Axis*、Dpad*）
    allFriendlyKeys := Map()
    for _, physMap in [MySoftData.PhysToXboxJoyMap, MySoftData.PhysToPS5JoyMap] {
        for rawKey, btnKey in physMap {
            if (allFriendlyKeys.Has(btnKey))
                continue
            allFriendlyKeys[btnKey] := true
        }
    }

    ; 对每个友好名，检查所有控制器
    for friendlyKey in allFriendlyKeys {
        isPressed := false
        for idx in RecordJoyIndexArr {
            ctrlType := DetectControllerJoyType(idx)
            physMap := (ctrlType == "PS5") ? MySoftData.PhysToPS5JoyMap : MySoftData.PhysToXboxJoyMap

            ; 在映射表中查通用键名对应的原始键
            for rawKey, btnKey in physMap {
                if (btnKey != friendlyKey)
                    continue

                if (RecordJoyAxises.Has(rawKey) && ctrlType == "Xbox") {
                    for s in RecordXInputStates {
                        if (rawKey == "JoyZMin" && s.bLeftTrigger > 30) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyZMax" && s.bRightTrigger > 30) {
                            isPressed := true
                            break
                        }
                        lx := s.sThumbLX
                        ly := s.sThumbLY
                        rx := s.sThumbRX
                        ry := s.sThumbRY
                        if (rawKey == "JoyXMin" && lx < -16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyXMax" && lx > 16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyYMin" && ly < -16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyYMax" && ly > 16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyUMin" && rx < -16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyUMax" && rx > 16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyRMin" && ry < -16384) {
                            isPressed := true
                            break
                        }
                        if (rawKey == "JoyRMax" && ry > 16384) {
                            isPressed := true
                            break
                        }
                    }
                } else if (RecordJoyAxises.Has(rawKey) && ctrlType != "Xbox") {
                    ; PS5 轴检测（按物理轴映射）：JoyX/Y=左摇杆, JoyZ/R=右摇杆, JoyU=R2, JoyV=L2
                    joyAxisName := SubStr(rawKey, 1, 4)
                    state := GetKeyState(idx joyAxisName)
                    if (IsNumber(state)) {
                        ; 自动检测值域（0-65535 或 0-100）
                        maxRange := (state > 100) ? 65535 : 100
                        minThresh := maxRange * 0.15
                        maxThresh := maxRange * 0.85

                        if (joyAxisName == "JoyX" || joyAxisName == "JoyY"
                            || joyAxisName == "JoyZ" || joyAxisName == "JoyR") {
                            ; 摇杆轴
                            if InStr(rawKey, "Min") && state < minThresh
                                isPressed := true
                            else if InStr(rawKey, "Max") && state > maxThresh
                                isPressed := true
                        } else if (joyAxisName == "JoyU" || joyAxisName == "JoyV") {
                            ; 扳机轴
                            if InStr(rawKey, "Max") && state > maxThresh
                                isPressed := true
                        }
                    }
                } else if (RecordJoyPOVMap.Has(rawKey)) {
                    if (CheckPOVOnIndex(rawKey, idx))
                        isPressed := true
                } else {
                    ; 跳过轴键（非 Xbox 的轴不检测按钮路径）
                    if (RecordJoyAxises.Has(rawKey))
                        continue
                    ; PS5 跳过 Joy7/Joy8（L2/R2 按钮噪声，LT/RT 已经通过 U/V 轴检测）
                    if (ctrlType != "Xbox" && (rawKey == "Joy7" || rawKey == "Joy8"))
                        continue
                    if (CheckBtnOnIndex(rawKey, idx))
                        isPressed := true
                    if (!isPressed) {
                        btnToPhysMap := MySoftData.GetJoyToPhysMap()
                        r := btnToPhysMap.Has(friendlyKey) ? btnToPhysMap[friendlyKey] : ""
                        if (r && XboxJoyAndPOVMap.Has(r))
                            isPressed := XboxBtnOnXInput(r, RecordXInputStates)
                    }
                }

                if (isPressed)
                    break
            }
            if (isPressed)
                break
        }

        if (isPressed)
            OnRecordAddMacroStr(friendlyKey, true)
        else if (MainSoftData.RecordHoldKeyMap.Has(friendlyKey))
            OnRecordAddMacroStr(friendlyKey, false)
    }
    SetTimer(RecordJoyTimer, -MainSoftData.RecordJoyInterval)
}

RecordJoy() {
    global RecordJoyIndexArr, MainSoftData
    RecordRefreshJoyIndexArr()
    MainSoftData.RecordHoldKeyMap := Map()
    MainSoftData.RecordInitialHoldMap := Map()
    SetTimer(RecordJoyTimer, -50)
}

RecordRefreshJoyIndexArr() {
    global RecordJoyIndexArr
    virtualXiIdx := RecordGetVirtualXInputIdx()
    RecordJoyIndexArr := []
    loop RecordControllerNum {
        if !GetKeyState(A_Index "JoyName")
            continue
        ; 跳过 ViGEm 虚拟手柄（输出设备，不参与输入检测）
        if (virtualXiIdx >= 0) {
            try {
                vs := Buffer(16)
                ve := DllCall("XInput1_4\XInputGetState", "uint", A_Index - 1, "ptr", vs)
                if (!ve && A_Index - 1 == virtualXiIdx)
                    continue
            }
        }
        RecordJoyIndexArr.Push(A_Index)
    }
}

RecordGetVirtualXInputIdx() {
    global ViGJoy
    try {
        if (IsSet(ViGJoy))
            return ViGJoy.ViGJoyXInputIdx
    }
    return -1
}

RecordCollectXInputStates() {
    states := []
    virtualIdx := RecordGetVirtualXInputIdx()
    loop 4 {
        idx := A_Index - 1
        if (idx == virtualIdx)
            continue
        try state := RecordXInputState(idx)
        catch
            continue
        if (state != 0)
            states.Push(state)
    }
    return states
}

XboxBtnOnXInput(rawKey, xiStates) {
    if (!XboxJoyAndPOVMap.Has(rawKey))
        return false
    bitSymbol := XboxJoyAndPOVMap.Get(rawKey)
    for state in xiStates {
        if ((state.wButtons >> bitSymbol) & 1)
            return true
    }
    return false
}

GetAxisTriggerSection(axisKey, isXbox) {
    value := RecordJoyAxises.Get(axisKey)
    floatValue := RecordAxisMaxValue * (RecordJoyFloat / 100)
    if (isXbox) {
        value := XboxJosAxisMap.Get(axisKey)
        floatValue := Abs(value) * (RecordJoyFloat / 100)
    }
    if (value <= 0) {
        return [value, value + floatValue]
    }
    else {
        return [value - floatValue, value]
    }
}

GetXboxAxisValueFromState(joyAxisSymbol, State) {
    joyAxisName := SubStr(joyAxisSymbol, 1, 4)
    if (State == 0)
        return 0

    if (joyAxisSymbol == "JoyZMin") {
        return State.bLeftTrigger
    }
    else if (joyAxisSymbol == "JoyZMax") {
        return State.bRightTrigger
    }

    if (joyAxisName == "JoyX") {
        return State.sThumbLX
    }
    else if (joyAxisName == "JoyY") {
        return State.sThumbLY
    }
    else if (joyAxisName == "JoyR") {
        return State.sThumbRY
    }
    else if (joyAxisName == "JoyU") {
        return State.sThumbRX
    }
    else if (joyAxisName == "JoyV") {
        return State.sThumbRY
    }

    return 0
}

RecordXInputState(UserIndex) {
    xiState := Buffer(16)
    if err := DllCall("XInput1_4\XInputGetState", "uint", UserIndex, "ptr", xiState) {
        if err = 1167
            return 0
        throw OSError(err, -1)
    }
    return {
        dwPacketNumber: NumGet(xiState, 0, "UInt"),
        wButtons: NumGet(xiState, 4, "UShort"),
        bLeftTrigger: NumGet(xiState, 6, "UChar"),
        bRightTrigger: NumGet(xiState, 7, "UChar"),
        sThumbLX: NumGet(xiState, 8, "Short"),
        sThumbLY: NumGet(xiState, 10, "Short"),
        sThumbRX: NumGet(xiState, 12, "Short"),
        sThumbRY: NumGet(xiState, 14, "Short"),
    }
}

XInputState(UserIndex) {
    return RecordXInputState(UserIndex)
}

GetXboxAxisValue(joyAxisSymbol) {
    global RecordXInputStates
    if (RecordXInputStates.Length > 0)
        return GetXboxAxisValueFromState(joyAxisSymbol, RecordXInputStates[1])
    return 0
}