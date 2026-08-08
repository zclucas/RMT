#Requires AutoHotkey v2.0

class JoyMacro {

    class MacroInfo {
        __New(action, actionUp, processName) {
            this.actionFunc := action
            this.actionUpFunc := actionUp
            this.processName := processName
        }

        Action() {
            if (this.processName != "") {
                if (!MyMouseInfo.CheckIfMatch(this.processName, true))
                    return
            }

            action := this.actionFunc
            action()
        }

        ActionUp() {
            if (this.actionUpFunc == "")
                return
            ; 松开时不检查窗口条件（确保松止能停下）
            action := this.actionUpFunc
            action()
        }
    }

    __New() {
        this.MacroMap := Map()
        this.ComboMacroMap := Map()
        this.interval := 50
        this.controllerNum := 10
        this.joyBtnNum := 32
        this.joyFloat := 5
        this.axisMaxValue := 100
        this.JoyIndexArr := []

        this.timerAction := this.CheckMacro.Bind(this)

        this.joyAxises := Map("JoyXMin", 0, "JoyXMax", 100, "JoyYMin", 0, "JoyYMax", 100, "JoyZMin", 0, "JoyZMax", 100,
            "JoyRMin", 0, "JoyRMax", 100, "JoyUMin", 0, "JoyUMax", 100, "JoyVMin", 0, "JoyVMax", 100)
        this.joyPOVMap := Map("JoyPOV_0", 0, "JoyPOV_9000", 9000, "JoyPOV_18000", 18000, "JoyPOV_27000", 27000)

        ; 边缘触发状态追踪（0=上次松开，1=上次按下）
        this.prevBtnState := Map()      ; DI 普通按钮
        this.prevPOVState := Map()      ; DI POV 方向
        this.prevAxisState := Map()     ; DI 轴
        this.prevXboxState := Map()     ; XInput 按钮（按位记录）

        this.xboxJoyBtnMap := Map("Joy1", 12, "Joy2", 13, "Joy3", 14, "Joy4", 15, "Joy5", 8, "Joy6", 9, "Joy7", 5,
            "Joy8", 4, "Joy9", 6, "Joy10", 7,
            "JoyPOV_0", 0, "JoyPOV_18000", 1, "JoyPOV_27000", 2, "JoyPOV_9000", 3)
        this.xboxJosAxisMap := Map("JoyXMin", -32768, "JoyXMax", 32767, "JoyYMin", -32768, "JoyYMax", 32767, "JoyZMin",
            255, "JoyZMax", 255, "JoyRMin", -32768, "JoyRMax", 32767, "JoyUMin", -32768, "JoyUMax", 32767, "JoyVMin", -
            32768, "JoyVMax", 32767)

    }

    __Delete() {
        SetTimer this.timerAction, 0
    }

    AddMacro(key, action, processName, actionUp := "") {
        joyToAhkMap := MySoftData.GetJoyToAhkMap()

        if (InStr(key, " & ")) {
            keyParts := StrSplit(key, " & ")
            if (keyParts.Length == 2) {
                ahkKey1 := joyToAhkMap[keyParts[1]]
                ahkKey2 := joyToAhkMap[keyParts[2]]

                if (ahkKey1 == "" || ahkKey2 == "") {
                    return
                }

                comboKey := ahkKey1 " & " ahkKey2
                macro := JoyMacro.MacroInfo(action, actionUp, processName)
                this.ComboMacroMap.Set(comboKey, macro)
                this.Enable()
                return
            }
        }

        macro := JoyMacro.MacroInfo(action, actionUp, processName)
        ahkKey := joyToAhkMap[key]
        this.MacroMap.Set(ahkKey, macro)
        this.Enable()
    }

    ; 自动检测连接的手柄类型
    static DetectJoyType() {
        global MainSoftData
        diFound := false
        loop 10 {
            if GetKeyState(A_Index "JoyName") {
                diFound := true
                break
            }
        }
        if (!diFound)
            return
        loop 4 {
            try {
                xiState := Buffer(16)
                err := DllCall("XInput1_4\XInputGetState", "uint", A_Index - 1, "ptr", xiState)
                if (!err) {
                    if (MainSoftData.JoyType != "Xbox") {
                        MainSoftData.JoyType := "Xbox"
                        JoyDebugLog("JoyMacro: auto-detect JoyType=Xbox")
                    }
                    return
                }
            }
        }
        if (MainSoftData.JoyType != "PS5") {
            MainSoftData.JoyType := "PS5"
            JoyDebugLog("JoyMacro: auto-detect JoyType=PS5")
        }
    }

    Enable() {
        if (this.MacroMap.Count == 0 && this.ComboMacroMap.Count == 0)
            return
        ; 手柄类型由用户通过 GUI 下拉框设置，此处不再自动覆盖
        this.JoyIndexArr := []
        loop this.controllerNum {
            if GetKeyState(A_Index "JoyName") {
                this.JoyIndexArr.Push(A_Index)
            }
        }
        SetTimer this.timerAction, 0
        SetTimer this.timerAction, this.interval
    }

    CheckMacro() {
        if (this.ComboMacroMap.Count > 0) {
            for key, macro in this.ComboMacroMap {
                this.CheckComboMacro(key)
            }
        }

        for key, macro in this.MacroMap {
            isJoyAxis := this.joyAxises.Has(key)
            isJoyPOV := this.joyPOVMap.Has(key)
            isJoyBtn := !isJoyAxis && !isJoyPOV

            if (isJoyBtn) {
                this.CheckBtnMacro(key)
            }
            else if (isJoyPOV) {
                this.CheckPOVMacro(key)
            }
            else {
                this.CheckAxisMacro(key)
            }
        }
    }

    CheckBtnMacro(joyBtnSymbol) {
        if (this.JoyIndexArr.Length == 0)
            return
        diIndex := this.JoyIndexArr[1]
        pressed := GetKeyState(diIndex "" joyBtnSymbol, "P")
        prev := this.prevBtnState.Has(joyBtnSymbol) ? this.prevBtnState[joyBtnSymbol] : 0

        if (pressed && !prev) {
            this.prevBtnState[joyBtnSymbol] := 1
            this.MacroMap.Get(joyBtnSymbol).Action()
        }
        if (!pressed && prev) {
            this.prevBtnState[joyBtnSymbol] := 0
            this.MacroMap.Get(joyBtnSymbol).ActionUp()
        }

        this.CheckXboxBtnOrPOVMacro(joyBtnSymbol)
    }

    CheckComboMacro(comboKey) {
        keyParts := StrSplit(comboKey, " & ")
        if (keyParts.Length != 2)
            return

        key1 := keyParts[1]
        key2 := keyParts[2]

        isAxis1 := this.joyAxises.Has(key1)
        isPOV1 := this.joyPOVMap.Has(key1)
        isAxis2 := this.joyAxises.Has(key2)
        isPOV2 := this.joyPOVMap.Has(key2)

        isBtn1 := !isAxis1 && !isPOV1
        isBtn2 := !isAxis2 && !isPOV2

        loop this.JoyIndexArr.Length {
            index := this.JoyIndexArr[A_Index]
            pressed1 := false
            pressed2 := false

            if (isBtn1) {
                pressed1 := GetKeyState(index "" key1, "P")
            }
            else if (isPOV1) {
                cont_info := GetKeyState(index "JoyInfo")
                if InStr(cont_info, "P") {
                    state := GetKeyState(index "JoyPOV", "P")
                    value := this.joyPOVMap.Get(key1)
                    pressed1 := (state == value)
                }
            }
            else if (isAxis1) {
                cont_info := GetKeyState(index "JoyInfo")
                if (cont_info != "ZRUPD") {
                    joyAxisName := SubStr(key1, 1, 4)
                    state := GetKeyState(index joyAxisName, "P")
                    valueSection := this.GetAxisTriggerSection(key1, false)
                    pressed1 := (IsNumber(state) && state >= valueSection[1] && state <= valueSection[2])
                }
            }

            if (isBtn2) {
                pressed2 := GetKeyState(index "" key2, "P")
            }
            else if (isPOV2) {
                cont_info := GetKeyState(index "JoyInfo")
                if InStr(cont_info, "P") {
                    state := GetKeyState(index "JoyPOV", "P")
                    value := this.joyPOVMap.Get(key2)
                    pressed2 := (state == value)
                }
            }
            else if (isAxis2) {
                cont_info := GetKeyState(index "JoyInfo")
                if (cont_info != "ZRUPD") {
                    joyAxisName := SubStr(key2, 1, 4)
                    state := GetKeyState(index joyAxisName, "P")
                    valueSection := this.GetAxisTriggerSection(key2, false)
                    pressed2 := (IsNumber(state) && state >= valueSection[1] && state <= valueSection[2])
                }
            }

            if (pressed1 && pressed2) {
                prevKey := comboKey "|DI|" index
                prev := this.prevXboxState.Has(prevKey) ? this.prevXboxState[prevKey] : 0
                bothNow := 1

                if (bothNow && !prev) {
                    this.prevXboxState[prevKey] := 1
                    this.ComboMacroMap.Get(comboKey).Action()
                    return
                }
                if (!bothNow && prev)
                    this.prevXboxState[prevKey] := 0
            }
        }

        this.CheckXboxComboMacro(comboKey)
    }

    CheckXboxComboMacro(comboKey) {
        keyParts := StrSplit(comboKey, " & ")
        if (keyParts.Length != 2)
            return

        key1 := keyParts[1]
        key2 := keyParts[2]

        global ViGJoy
        try virtualIdx := ViGJoy.ViGJoyXInputIdx
        catch
            virtualIdx := -1
        loop 4 {
            idx := A_Index - 1
            if (idx == virtualIdx)
                continue
            try State := this.XInputState(idx)
            catch
                continue
            if (State == 0)
                continue

            pressed1 := false
            pressed2 := false

            if (this.xboxJoyBtnMap.Has(key1)) {
                bitSymbol1 := this.xboxJoyBtnMap.Get(key1)
                pressed1 := (State.wButtons >> bitSymbol1) & 1
            }
            else if (this.xboxJosAxisMap.Has(key1)) {
                value1 := this.GetXboxAxisValue(key1, idx)
                valueSection1 := this.GetAxisTriggerSection(key1, true)
                pressed1 := (value1 != 0 && value1 >= valueSection1[1] && value1 <= valueSection1[2])
            }

            if (this.xboxJoyBtnMap.Has(key2)) {
                bitSymbol2 := this.xboxJoyBtnMap.Get(key2)
                pressed2 := (State.wButtons >> bitSymbol2) & 1
            }
            else if (this.xboxJosAxisMap.Has(key2)) {
                value2 := this.GetXboxAxisValue(key2, idx)
                valueSection2 := this.GetAxisTriggerSection(key2, true)
                pressed2 := (value2 != 0 && value2 >= valueSection2[1] && value2 <= valueSection2[2])
            }

            if (pressed1 && pressed2) {
                prevKey := comboKey "|Xbox|" idx
                prev := this.prevXboxState.Has(prevKey) ? this.prevXboxState[prevKey] : 0
                bothNow := 1

                if (bothNow && !prev) {
                    this.prevXboxState[prevKey] := 1
                    this.ComboMacroMap.Get(comboKey).Action()
                    return
                }
                if (!bothNow && prev)
                this.prevXboxState[prevKey] := 0
            }
        }
    }

    CheckPOVMacro(joyPOVSymbol) {
        loop this.JoyIndexArr.Length {
            index := this.JoyIndexArr[A_Index]
            cont_info := GetKeyState(index "JoyInfo")
            if InStr(cont_info, "P") {
                state := GetKeyState(index "JoyPOV", "P")
                value := this.joyPOVMap.Get(joyPOVSymbol)
                pressed := (state == value)
                prev := this.prevPOVState.Has(joyPOVSymbol) ? this.prevPOVState[joyPOVSymbol] : 0

                if (pressed && !prev) {
                    this.prevPOVState[joyPOVSymbol] := 1
                    this.MacroMap.Get(joyPOVSymbol).Action()
                    return
                }
                if (!pressed && prev) {
                    this.prevPOVState[joyPOVSymbol] := 0
                    this.MacroMap.Get(joyPOVSymbol).ActionUp()
                }
            }
        }

        this.CheckXboxBtnOrPOVMacro(joyPOVSymbol)
    }

    CheckAxisMacro(joyAxisSymbol) {
        loop this.JoyIndexArr.Length {
            index := this.JoyIndexArr[A_Index]
            cont_name := GetKeyState(index "JoyName")
            cont_info := GetKeyState(index "JoyInfo")
            if (cont_info == "ZRUPD")
                continue
            joyAxisName := SubStr(joyAxisSymbol, 1, 4)
            state := GetKeyState(index joyAxisName, "P")
            valueSection := this.GetAxisTriggerSection(joyAxisSymbol, false)
            pressed := (IsNumber(state) && state >= valueSection[1] && state <= valueSection[2])
            prev := this.prevAxisState.Has(joyAxisSymbol) ? this.prevAxisState[joyAxisSymbol] : 0

            if (pressed && !prev) {
                this.prevAxisState[joyAxisSymbol] := 1
                this.MacroMap.Get(joyAxisSymbol).Action()
                return
            }
            if (!pressed && prev) {
                this.prevAxisState[joyAxisSymbol] := 0
                this.MacroMap.Get(joyAxisSymbol).ActionUp()
            }
        }

        if (SubStr(joyAxisSymbol, 1, 4) == "JoyV")
            return false

        this.CheckXboxAxisMacro(joyAxisSymbol)
    }

    CheckXboxBtnOrPOVMacro(joySymbol) {
        isXboxHasBtn := this.xboxJoyBtnMap.Has(joySymbol)
        if (!isXboxHasBtn)
            return

        global ViGJoy
        try virtualIdx := ViGJoy.ViGJoyXInputIdx
        catch
            virtualIdx := -1
        loop 4 {
            idx := A_Index - 1
            if (idx == virtualIdx)
                continue
            try state := this.XInputState(idx)
            catch
                continue
            if (state != 0) {
                bitSymbol := this.xboxJoyBtnMap.Get(joySymbol)
                pressed := (state.wButtons >> bitSymbol) & 1
                prevKey := joySymbol "|Xbox|" idx
                prev := this.prevXboxState.Has(prevKey) ? this.prevXboxState[prevKey] : 0

                if (pressed && !prev) {
                    this.prevXboxState[prevKey] := 1
                    this.MacroMap.Get(joySymbol).Action()
                    return
                }
                if (!pressed && prev) {
                    this.prevXboxState[prevKey] := 0
                    this.MacroMap.Get(joySymbol).ActionUp()
                }
            }
        }
    }

    CheckXboxAxisMacro(joyAxisSymbol) {
        valueSection := this.GetAxisTriggerSection(joyAxisSymbol, true)

        global ViGJoy
        try virtualIdx := ViGJoy.ViGJoyXInputIdx
        catch
            virtualIdx := -1
        loop 4 {
            idx := A_Index - 1
            if (idx == virtualIdx)
                continue
            value := this.GetXboxAxisValue(joyAxisSymbol, idx)
            if (value == 0)
                continue

            pressed := (value >= valueSection[1] && value <= valueSection[2])
            prevKey := joyAxisSymbol "|Xbox|" idx
            prev := this.prevXboxState.Has(prevKey) ? this.prevXboxState[prevKey] : 0

            if (pressed && !prev) {
                this.prevXboxState[prevKey] := 1
                this.MacroMap.Get(joyAxisSymbol).Action()
                return
            }
            if (!pressed && prev) {
                this.prevXboxState[prevKey] := 0
                this.MacroMap.Get(joyAxisSymbol).ActionUp()
            }
        }
    }

    ;数据获取函数
    GetAxisTriggerSection(axisKey, isXbox) {
        value := this.joyAxises.Get(axisKey)
        floatValue := this.axisMaxValue * (this.joyFloat / 100)
        if (isXbox) {
            value := this.xboxJosAxisMap.Get(axisKey)
            floatValue := Abs(value) * (this.joyFloat / 100)
        }
        if (value <= 0) {
            return [value, value + floatValue]
        }
        else {
            return [value - floatValue, value]
        }
    }

    GetXboxAxisValue(joyAxisSymbol, userIndex := 0) {
        joyAxisName := SubStr(joyAxisSymbol, 1, 4)
        State := this.XInputState(userIndex)
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
            return State.sThumbRY   ;可能是sThumbRX
        }

        return 0
    }

    ;XInput API
    XInputState(UserIndex) {
        xiState := Buffer(16)
        if err := DllCall("XInput1_4\XInputGetState", "uint", UserIndex, "ptr", xiState) {
            if err = 1167 ; ERROR_DEVICE_NOT_CONNECTED
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

}
