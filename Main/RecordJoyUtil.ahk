#Requires AutoHotkey v2.0
RecordControllerNum := 10
RecordJoyFloat := 10
RecordAxisMaxValue := 100
RecordJoyIndexArr := []

; ============================================================
; GameInput 手柄读取层（替代旧 XInput / DirectInput）
; ------------------------------------------------------------
; 在 RMT 主进程内用 CLR 加载 Plugins/GameInput/GameInputWrapper.cs，
; 经 PollXboxString() 轮询 GameInput 状态并换算成 XInput 兼容布局
; （wButtons=标准 XInput 位 / 扳机 0..255 / 摇杆 -32768..32767）。
; 录制由 RecordJoyTimer（定时轮询）驱动：按钮/DPad 走 wButtons 位判定，
; 摇杆/扳机按真实偏转采样成无类型设值轴指令（见 RecordRealAxisSpec）。
; CLR_CompileCS 已由 AssetUtil.ahk 在主进程启动期 include，无需重复。
; ============================================================
global __GI_wrapper := 0        ; GameInputWrapper COM 实例（幂等加载）

; 首次使用时编译并初始化 C# GameInput wrapper（一次加载，多轮录制复用）
GI_EnsureWrapper() {
    global __GI_wrapper
    if (__GI_wrapper)
        return __GI_wrapper
    try {
        csPath := A_ScriptDir "\Plugins\GameInput\GameInputWrapper.cs"
        csCode := FileRead(csPath, "UTF-8")
        asm := CLR_CompileCS(csCode)
        w := asm.CreateInstance("GameInputTest.GameInputWrapper")
        if (!w || !w.Init())
            throw Error("GameInputWrapper.Init() 失败（需 Win10 1809+ 且已装 GameInput）")
        __GI_wrapper := w
    } catch as e {
        __GI_wrapper := 0
        JoyDebugLog("RecordJoy: GameInput 加载失败: " e.Message)
        throw e
    }
    return __GI_wrapper
}

; 是否存在真实手柄（GameInput 视角）。旧版用 GetKeyState("JoyName") 探测 DI，
; 现改为查询 wrapper 已跟踪的设备数。
GI_HasDevice() {
    global __GI_wrapper
    try {
        if (!__GI_wrapper)
            return false
        return __GI_wrapper.DeviceCount > 0
    }
    return false
}

; 反回环已下移到 GI_CollectStates 读取源头：直接过滤 PID=0x028E(ViGEm 伪装 Xbox360) 的设备行，
; 使其永不进入读取数组 → 触发/录制读不到自己 ViGEm 输出，无回环（见下方 GI_CollectStates）。
; 曾尝试的 wrapper 层 ExcludeDeviceId / AutoExcludeNewFromHere 排除已废弃：前者依赖 ViGEm 被 GameInput
; 登记(待命不输出则登记不上→时序不可控)，后者只排"武装后新出现"设备而 ViGEm 常驻早于基准→结构性失效。

; 采样：把 wrapper 输出的每台设备状态（XInput 兼容布局）读成数组。
; 返回 RecordXInputStates 兼容数组：元素 {wButtons, bLeftTrigger, bRightTrigger,
; sThumbLX, sThumbLY, sThumbRX, sThumbRY}，供 RecordJoyTimer 判定。
GI_CollectStates() {
    global __GI_wrapper
    states := []
    try {
        if (!__GI_wrapper)
            return states
        txt := __GI_wrapper.PollXboxString()
        if (txt == "")
            return states
        for line in StrSplit(txt, "`n") {
            line := Trim(line, " `t")
            if (line == "")
                continue
            p := StrSplit(line, ";")
            if (p.Length < 8)
                continue
            ; 反回环：直接忽略本进程 ViGEm 虚拟手柄(PID=0x028E, 伪装Xbox360)的设备行，
            ; 使其永不进入读取数组 → JoyMacro 触发/录制侧都读不到自己 ViGEm 的输出 → 无回环。
            ; 物理手柄(VID=045E 但 PID≠028E, 如 0B13)不受影响，正常读入。
            ; 局限：若未来插一台真 Xbox360(PID=028E)会被一并忽略——需父设备(ViGEm Bus)区分，
            ; 当前 ReadingData 无 parent 字段，暂用 PID 过滤，踩到真 Xbox360 时再升级。
            if (p.Length >= 10 && p[10] ~= "^\d+$" && Integer(p[10]) = 0x028E)
                continue
            states.Push({
                wButtons:       Integer(p[2]),
                bLeftTrigger:   Integer(p[3]),
                bRightTrigger:  Integer(p[4]),
                sThumbLX:       Integer(p[5]),
                sThumbLY:       Integer(p[6]),
                sThumbRX:       Integer(p[7]),
                sThumbRY:       Integer(p[8]),
                ; vid/pid 透传（原 wrapper 每行末尾字段），供调用方按设备身份过滤
                vid:            (p.Length >= 10 && p[9] ~= "^\d+$") ? Integer(p[9]) : 0,
                pid:            (p.Length >= 10 && p[10] ~= "^\d+$") ? Integer(p[10]) : 0
            })
        }
    }
    return states
}

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

; ============================================================
; 真轴录制（模拟量采样）配置
; ------------------------------------------------------------
; 录制层把摇杆/扳机按「真实偏转」落成无类型设值轴指令（非二进制方向键），
; 键名与编辑器/回放一致：JoyAxisLX/LY/RX/RY 摇杆(-100..100)，JoyAxisLT/RT 扳机(0..100)。
; 每轮采样按值变化死区落一条「按键_<轴>:<值>」（前后自动补 间隔_）。
; symbol 指 RecordXInputStates 里的读取键（Xbox 统一布局）。
; ============================================================
RecordRealAxisSpec := [
    ["JoyAxisLX", "JoyX"],
    ["JoyAxisLY", "JoyY"],
    ["JoyAxisRX", "JoyU"],
    ["JoyAxisRY", "JoyR"],
    ["JoyAxisLT", "JoyZMin"],
    ["JoyAxisRT", "JoyZMax"]
]

; 由 XInput 兼容状态算某真轴当前 % 值（摇杆 -100..100，扳机 0..100）
RecordRealAxisValue(symbol, State) {
    if (symbol == "JoyZMin")
        return Round(State.bLeftTrigger * 100 / 255)
    if (symbol == "JoyZMax")
        return Round(State.bRightTrigger * 100 / 255)
    raw := 0
    if (symbol == "JoyX")
        raw := State.sThumbLX
    else if (symbol == "JoyY")
        raw := State.sThumbLY
    else if (symbol == "JoyU")
        raw := State.sThumbRX
    else if (symbol == "JoyR")
        raw := State.sThumbRY
    v := Round(raw * 100 / 32768)
    if (v < -100)
        v := -100
    if (v > 100)
        v := 100
    return v
}

; 落一条轴设值采样（无类型）。值变化死区、回中兜底交给调用方判断。
RecordJoyAxisSet(axisKey, value) {
    global MainSoftData
    curTime := A_TickCount
    span := curTime - MainSoftData.RecordLastTime
    MainSoftData.RecordLastTime := curTime
    MainSoftData.RecordMacroStr .= Format("{}_{},", GetLang("间隔"), span)
    MainSoftData.RecordMacroStr .= Format("{}_{}:{},", GetLang("按键"), axisKey, value)
}

; 上次已落宏的各轴值（初值从每轮采样建立；录制结束时非零需兜底回中）
RecordAxisLastVal := Map()

; 录制首轮各轴基线（避免把开始时的既有偏转落成指令）
RecordAxisBase := Map()

RecordJoyTimer() {
    global RecordXInputStates, MainSoftData, MySoftData, RecordJoyIndexArr, RecordJoyAxises, XboxJoyAndPOVMap

    if (!UIControls.ToolCheckRecord.Value)
        return

    static lastTick := 0
    debounceMs := MainSoftData.RecordJoyInterval
    if (debounceMs < 20)
        debounceMs := 20
    if (A_TickCount - lastTick < debounceMs)
        return
    lastTick := A_TickCount

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

    ; 对每个友好名，检查控制器（GameInput 统一 Xbox 布局）
    for friendlyKey in allFriendlyKeys {
        isPressed := false
        for idx in RecordJoyIndexArr {
            ; 在 Xbox 映射表中查通用键名对应的原始键
            for rawKey, btnKey in MySoftData.PhysToXboxJoyMap {
                if (btnKey != friendlyKey)
                    continue

                if (RecordJoyAxises.Has(rawKey)) {
                    ; 摇杆方向/扳机不再按二进制方向键录制（真轴走下方 RecordRealAxisSpec 采样）。
                    ; 仅需跳过：轴方向不会进入 RecordHoldKeyMap，也无需 OnRecordAddMacroStr。
                    continue
                }
                else {
                    ; 按钮 & DPad 一律按 wButtons 位判定（GameInput 换算已含 DPad 位）。
                    ; rawKey 需在 XboxJoyAndPOVMap 中（按钮用 XInput 位，JoyPOV_* 用 DPad 位）。
                    if (XboxJoyAndPOVMap.Has(rawKey))
                        isPressed := XboxBtnOnXInput(rawKey, RecordXInputStates)
                }

                if (isPressed)
                    break
            }
            if (isPressed)
                break
        }

        if (isPressed) {
            OnRecordAddMacroStr(friendlyKey, true)
        }
        else if (MainSoftData.RecordHoldKeyMap.Has(friendlyKey))
            OnRecordAddMacroStr(friendlyKey, false)
    }

    ; 真轴采样：把摇杆/扳机当前偏转（%）按值变化死区落成「设值」轴指令。
    ; 首个有效状态只建基线（不落初始偏移）；此后 |Δ|≥StepVal 才采样，抑制中心抖动。
    RecordAxisSampleTimer()

    SetTimer(RecordJoyTimer, -MainSoftData.RecordJoyInterval)
}

; 真轴模拟量采样（被 RecordJoyTimer 调用）。多台手柄只取第 1 台状态。
RecordAxisSampleTimer() {
    global RecordAxisLastVal, RecordAxisBase, MainSoftData
    if (RecordXInputStates.Length == 0)
        return
    s := RecordXInputStates[1]
    stepVal := 3                 ; 值变化死区（±，抑制噪声；也决定采样粒度）
    for _, spec in RecordRealAxisSpec {
        axisKey := spec[1]
        symbol := spec[2]
        v := RecordRealAxisValue(symbol, s)
        ; 首轮：记基线，不落（录制开始时摇杆/扳机已有偏转只作基线）
        if (!RecordAxisBase.Has(axisKey)) {
            RecordAxisBase[axisKey] := v
            RecordAxisLastVal[axisKey] := v
            continue
        }
        last := RecordAxisLastVal.Has(axisKey) ? RecordAxisLastVal[axisKey] : RecordAxisBase[axisKey]
        ; 值变化足够大才落；回中(到0)或从0离开无论步进多少都落，保证能回到中心
        changed := Abs(v - last) >= stepVal
        if (!changed && !(last != 0 && v == 0))
            continue
        RecordAxisLastVal[axisKey] := v
        RecordJoyAxisSet(axisKey, v)
    }
}

; 录制结束兜底：仍有非零偏转的轴落一条 :0 回中，保证录制宏在末尾把手柄轴归零。
; 与按钮 AutoLoosen 一致，仅在 RecordAutoLoosen 开启时调用（由 OnFinishRecordMacro 触发）。
RecordJoyAxisRecentre() {
    global RecordAxisLastVal
    if (!IsObject(RecordAxisLastVal) || RecordAxisLastVal.Count == 0)
        return
    for axisKey, v in RecordAxisLastVal {
        if (v == 0)
            continue
        RecordAxisLastVal[axisKey] := 0
        RecordJoyAxisSet(axisKey, 0)
    }
}

RecordJoy() {
    global RecordJoyIndexArr, MainSoftData
    ; 首次启动前确保 GameInput wrapper 就绪（无手柄/加载失败会在此暴露，不静默空录）
    try {
        GI_EnsureWrapper()
    } catch as e {
        JoyDebugLog("RecordJoy: GameInput 不可用，跳过手柄录制: " e.Message)
        return
    }
    RecordRefreshJoyIndexArr()
    MainSoftData.RecordHoldKeyMap := Map()
    MainSoftData.RecordInitialHoldMap := Map()
    ; 真轴采样基线复位：录制开始时摇杆/扳机的既有偏转只作基线，不落成指令
    global RecordAxisLastVal, RecordAxisBase
    RecordAxisLastVal := Map()
    RecordAxisBase := Map()
    SetTimer(RecordJoyTimer, -50)
}

RecordRefreshJoyIndexArr() {
    global RecordJoyIndexArr
    ; 不再用 GetKeyState("JoyName") 枚举 DI 手柄；有 GameInput 设备即视为 1 台
    RecordJoyIndexArr := []
    if (GI_HasDevice())
        RecordJoyIndexArr.Push(1)
}

RecordCollectXInputStates() {
    ; 用 GameInput wrapper 采样（替代旧 XInputGetState 轮询）
    return GI_CollectStates()
}

XboxBtnOnXInput(rawKey, xiStates) {
    global XboxJoyAndPOVMap
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
    global RecordJoyAxises, XboxJosAxisMap, RecordAxisMaxValue, RecordJoyFloat
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
    ; 替代旧 XInputGetState：从 GameInput 采样取对应槽位的状态对象（布局 XInput 兼容）
    states := GI_CollectStates()
    if (UserIndex < states.Length)
        return states[UserIndex + 1]
    if (states.Length > 0)
        return states[1]
    return 0
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