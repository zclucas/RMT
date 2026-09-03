#Requires AutoHotkey v2.0

class JoyMacro {

    class MacroInfo {
        __New(action, actionUp, processName) {
            this.actionFunc := action
            this.actionUpFunc := actionUp
            this.processName := processName
        }

        Action() {
            global MyMouseInfo
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
        this.joyFloat := 5
        this.axisMaxValue := 100

        this.timerAction := this.CheckMacro.Bind(this)

        ; 轴分类/区间表（CheckMacro 分发用 joyAxises/joyPOVMap；区间统一走 Xbox 布局 xboxJosAxisMap）
        this.joyAxises := Map("JoyXMin", 0, "JoyXMax", 100, "JoyYMin", 0, "JoyYMax", 100, "JoyZMin", 0, "JoyZMax", 100,
            "JoyRMin", 0, "JoyRMax", 100, "JoyUMin", 0, "JoyUMax", 100, "JoyVMin", 0, "JoyVMax", 100)
        this.joyPOVMap := Map("JoyPOV_0", 0, "JoyPOV_9000", 9000, "JoyPOV_18000", 18000, "JoyPOV_27000", 27000)

        ; 边缘触发状态追踪（0=上次松开，1=上次按下）——统一路径唯一状态表（GameInput/XInput）
        this.prevXboxState := Map()

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
        ; 统一到 GameInput 的 XInput 兼容布局：强制用 Xbox 映射，不再按 JoyType 切换
        ; 到 PS5 布局（JoyXboxToAhkMap 与 JoyPS5ToAhkMap 左侧物理键名相同，
        ; 仅右侧内部目标不同；GameInput 把 DS4 也归一为 XInput，故 Xbox 映射对所有类型都对）。
        joyToAhkMap := MySoftData.JoyXboxToAhkMap

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

    Enable() {
        if (this.MacroMap.Count == 0 && this.ComboMacroMap.Count == 0)
            return
        ; 手柄类型由用户通过 GUI 下拉框设置，此处不再自动覆盖。
        ; 不再用 GetKeyState("NJoyName") 枚举 DI 设备——设备有无交给每 tick 的
        ; XInputState()(GameInput) 自然判定，无设备时读不到任何按下即不触发。
        try GI_EnsureWrapper()
        catch as e
            JoyDebugLog("JoyMacro.Enable: GameInput 不可用: " e.Message)
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
        ; 统一单路径：按钮从 GameInput 读（wButtons 位），不再走 DirectInput。
        ; 仅在能映射到 XInput 位时触发（JoyN / DPad 键都已含在 xboxJoyBtnMap）。
        if (this.xboxJoyBtnMap.Has(joyBtnSymbol))
            this.CheckXboxBtnOrPOVMacro(joyBtnSymbol)
    }

    CheckComboMacro(comboKey) {
        ; 统一单路径：组合键走 GameInput（XInput 布局），不再并行跑 DI 分支。
        ; key1/key2 已由 AddMacro 经 Xbox 映射转成内部键，直接走 XInput 组合判定。
        keyParts := StrSplit(comboKey, " & ")
        if (keyParts.Length != 2)
            return

        key1 := keyParts[1]
        key2 := keyParts[2]

        ; GameInput 不读回 ViGEm 虚拟输出（回环探针已证），无需按虚拟槽位跳过
        loop 4 {
            idx := A_Index - 1
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
        ; 统一单路径：DPad 从 GameInput 读（wButtons 位），不再走 DirectInput POV。
        if (this.xboxJoyBtnMap.Has(joyPOVSymbol))
            this.CheckXboxBtnOrPOVMacro(joyPOVSymbol)
    }

    CheckAxisMacro(joyAxisSymbol) {
        ; 统一单路径：轴从 GameInput 读（真实摇杆/扳机值），不再走 DirectInput。
        if (this.xboxJosAxisMap.Has(joyAxisSymbol))
            this.CheckXboxAxisMacro(joyAxisSymbol)
    }

    CheckXboxBtnOrPOVMacro(joySymbol) {
        isXboxHasBtn := this.xboxJoyBtnMap.Has(joySymbol)
        if (!isXboxHasBtn)
            return

        ; 反回环已下移到读取源头(GI_CollectStates 过滤 PID=0x028E 的 ViGEm 设备)：
        ; ViGEm 永不进入本读取数组，JoyMacro 读到的只有物理手柄 → 此处直接按边沿触发即可。
        ; (曾用的因果位掩码 IsViGEmOutputtingBit/__ViGEmOutButtons 已删除——它在 ViGEm 输出
        ;  同键位时会误伤物理手柄的同键按下。)
        loop 4 {
            idx := A_Index - 1
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

        ; GameInput 不读回 ViGEm 虚拟输出，无需按虚拟槽位跳过
        loop 4 {
            idx := A_Index - 1
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
        ; GameInput 读取失败(未就绪/异常)按无轴值处理，避免异常冒泡打断轴触发循环
        try State := this.XInputState(userIndex)
        catch
            return 0
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
            ; XInput/GameInput 只有双摇杆(X/Y) + 右摇杆(R/U) + 双扳机(Z)，无第 6 轴 JoyV。
            ; 旧实现返回 sThumbRY 会与 JoyR 撞（误读右摇杆 Y），统一路径下 JoyV 无合法数据源，
            ; 强制 return 0 使其永不触发（Xbox 映射也不含 JoyV 键，仅防御）。
            return 0
        }

        return 0
    }

    ; 手柄状态读取：只走 GameInput（同进程复用 RecordJoyUtil 的 wrapper，
    ; 每次读最新 reading 快照，天然事件驱动）。不再退回旧 XInput1_4。
    ; UserIndex 在 GameInput 下无槽位概念，单手柄取 device[0]，多手柄按设备序映射。
    ; 读取失败(GameInput 未就绪/加载异常)时异常上抛，由调用点按"读不到即不触发"处理。
    XInputState(UserIndex) {
        GI_EnsureWrapper()   ; 幂等懒加载 GameInput wrapper；触发首次读取即自初始化
        states := GI_CollectStates()
        if (states.Length == 0)
            return 0
        ; 越界槽位(UerIndex>=设备数)直接返回 0，不再回退读 device[0]——
        ; 否则多手柄/槽位循环时第 2+ 台会重复读到第 1 台，造成重复计数/误触发
        if (UserIndex >= states.Length)
            return 0
        st := states[UserIndex + 1]
        return {
            dwPacketNumber: 0,
            wButtons:       st.wButtons,
            bLeftTrigger:   st.bLeftTrigger,
            bRightTrigger:  st.bRightTrigger,
            sThumbLX:       st.sThumbLX,
            sThumbLY:       st.sThumbLY,
            sThumbRX:       st.sThumbRX,
            sThumbRY:       st.sThumbRY
        }
    }

}
