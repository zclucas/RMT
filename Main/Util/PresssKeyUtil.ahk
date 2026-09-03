#Requires AutoHotkey v2.0
; ------------------------------------------------------------
; Helper
; ------------------------------------------------------------
GetHoldBucket(tableItem, index) {
    item := tableItem.Items[index]
    return item ? item.HoldKey : Map()
}

; Worker 启动时挂上同步回调；主进程保持为空，避免引用 Worker 专有函数
global MyHoldKeyNotify := ""

; Worker 按下/抬起时同步到主进程，强杀 Worker 后主进程仍能松开残留按键
NotifyHoldKeyChange(tableItem, index, key, state, source := "") {
    global MyHoldKeyNotify
    if (MyHoldKeyNotify = "" || !IsObject(tableItem) || index < 1)
        return
    try {
        item := tableItem.Items[index]
        if (!item)
            return
        MyHoldKeyNotify.Call(tableItem.ID, item.ID, key, state, source)
    } catch {
    }
}

TrackDown(bucket, key, source, tableItem := "", index := 0) {
    if !MySoftData.OnlyDownKeyMap.Has(key) {
        bucket[key] := source
        if (tableItem != "")
            NotifyHoldKeyChange(tableItem, index, key, 1, source)
    }
}

TrackUp(bucket, key, tableItem := "", index := 0) {
    if !MySoftData.OnlyDownKeyMap.Has(key) {
        if (bucket.Has(key))
            bucket.Delete(key)
        if (tableItem != "")
            NotifyHoldKeyChange(tableItem, index, key, 0, "")
    }
}

ClearDpadHoldState(bucket, tableItem := "", index := 0) {
    for dpadKey in ["Up", "Down", "Left", "Right"] {
        if (!bucket.Has(dpadKey))
            continue
        bucket.Delete(dpadKey)
        if (tableItem != "")
            NotifyHoldKeyChange(tableItem, index, dpadKey, 0, "")
    }
}

ResolveActionForKey(baseAction, key) {
    static LogicNoKeyMap := Map("Volume_Up", 0, "Volume_Down", 0, "Volume_Mute", 0)
    return (baseAction == SendLogicKey && LogicNoKeyMap.Has(key)) ? SendNormalKey : baseAction
}

SendKeysUp(keys, tableItem, index, Action) {
    Loop keys.Length {
        key := keys[keys.Length - A_Index + 1]
        SendSingleKey(key, 0, tableItem, index, Action)
    }
}
SendKeysDown(keys, tableItem, index, Action) {
    for key in keys
        SendSingleKey(key, 1, tableItem, index, Action)
}

; ------------------------------------------------------------
; Wrapper
; ------------------------------------------------------------
SendKeyWrapper(KeyArrStr, holdTime, tableItem, index, keyType, Action) {
    KeyArrStr := StrReplace(KeyArrStr, "逗号", ",")
    KeyArr := GetPressKeyArr(KeyArrStr)
    if (InStr(KeyArrStr, "Joy")) {
        arrText := ""
        if (IsObject(KeyArr)) {
            for k in KeyArr
                arrText .= (arrText = "" ? "" : ",") k
        }
        JoyDebugLog(Format("SendKeyWrapper in={} keyType={} hold={} arr=[{}] len={}"
            , KeyArrStr, keyType, holdTime, arrText, IsObject(KeyArr) ? KeyArr.Length : -1), "send")
    }
    if !IsObject(KeyArr) || (KeyArr.Length = 0) {
        if (InStr(KeyArrStr, "Joy"))
            JoyDebugLog(Format("SendKeyWrapper ABORT empty KeyArr for '{}'", KeyArrStr), "send")
        return
    }

    switch keyType {
        case 1:
            SendKeysDown(KeyArr, tableItem, index, Action)
        case 2:
            SendKeysUp(KeyArr, tableItem, index, Action)
        case 3:
            SendKeysDown(KeyArr, tableItem, index, Action)
            Sleep(holdTime)
            SendKeysUp(KeyArr, tableItem, index, Action)
    }
}

SendSingleKey(key, state, tableItem, index, Action) {
    static BrightKeyMap := Map("Bright_Up", 0, "Bright_Down", 0)
    if BrightKeyMap.Has(key) {
        if state
            SetBrightnessByKey(key)
        return
    }

    if !state && MySoftData.OnlyDownKeyMap.Has(key)
        return

    RealAction := ResolveActionForKey(Action, key)

    ; 手柄键经 ViGEm 输出，不是 AHK 物理键名（JoyB 等会导致 GetKeyState 抛错）
    isJoyKey := InStr(key, "Joy")
    if state && !isJoyKey && HandleRepeatedKeyDown(key, tableItem, index, RealAction)
        return

    if (isJoyKey)
        JoyDebugLog(Format("SendSingleKey call action key={} state={}", key, state), "send")

    RealAction(key, state, tableItem, index)
}

; ------------------------------------------------------------
; Repeated key-down policy
; ------------------------------------------------------------
HandleRepeatedKeyDown(key, tableItem, index, Action) {
    ; Joy* 不是合法 GetKeyState 键名，调用会抛错并中断宏
    if (InStr(key, "Joy"))
        return false

    try {
        if !GetKeyState(key)
            return false
    } catch {
        return false
    }

    switch MainSoftData.KeyDownDownType {
        case 1:  ; auto release first
            GraphPoolLog("RepeatedKeyDown", Format("tab={1} item={2} key={3} 已按下→先松开", tableItem.Index, index, key))
            Action(key, 0, tableItem, index)
        case 2:  ; ignore later press
            return true
        case 3:  ; allow duplicate press
    }
    return false
}

; ------------------------------------------------------------
; Senders
; ------------------------------------------------------------
SendNormalKey(Key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    GraphPoolLog("SendNormalKey", Format("tab={1} item={2} key={3} state={4}"
        , tableItem.Index, index, Key, state))
    Send("{Blind}{" Key " " (state ? "down" : "up") "}")
    if state
        TrackDown(bucket, Key, "Normal", tableItem, index)
    else
        TrackUp(bucket, Key, tableItem, index)
}

SendLogicKey(Key, state, tableItem, index) {
    if !InitLogitechGHubNew()
        return

    bucket := GetHoldBucket(tableItem, index)

    ; 滚轮走专用鼠标滚轮 API，避免 {WheelUp down} 经钩子时格式不稳定
    static WheelDeltaMap := Map("WheelUp", 120, "WheelDown", -120)
    if WheelDeltaMap.Has(Key) {
        if state
            DllCall("IbInputSimulator\IbSendMouseWheel", "Int", WheelDeltaMap[Key])
        if state
            TrackDown(bucket, Key, "Logic", tableItem, index)
        else
            TrackUp(bucket, Key, tableItem, index)
        return
    }

    IbSend("{Blind}{" Key " " (state ? "down" : "up") "}")
    if state
        TrackDown(bucket, Key, "Logic", tableItem, index)
    else
        TrackUp(bucket, Key, tableItem, index)
}

SendAHIKey(Key, state, tableItem, index) {
    if !InitAHI()
        return

    bucket := GetHoldBucket(tableItem, index)

    AhiSendKey(Key, state)
    if state
        TrackDown(bucket, Key, "AHI", tableItem, index)
    else
        TrackUp(bucket, Key, tableItem, index)
}

SendGameModeKey(Key, state, tableItem, index) {
    static MouseVK := Map(
        1, 0,     ; LButton
        2, 0,     ; RButton
        4, 0,     ; MButton
        5, 0,     ; XButton1
        6, 0,     ; XButton2
        158, 0,   ; WheelDown
        159, 0    ; WheelUp
    )

    static ExtendedVK := Map(
        0x21, 0,  ; PageUp
        0x22, 0,  ; PageDown
        0x23, 0,  ; End
        0x24, 0,  ; Home
        0x25, 0,  ; Left
        0x26, 0,  ; Up
        0x27, 0,  ; Right
        0x28, 0,  ; Down
        0x2D, 0,  ; Insert
        0x2E, 0   ; Delete
    )

    bucket := GetHoldBucket(tableItem, index)

    VK := GetKeyVK(Key)
    if MouseVK.Has(VK) {
        SendGameMouseKey(Key, state, tableItem, index)
        return
    }

    SC := GetKeySC(Key)
    flags := (state ? 0 : 2) | (ExtendedVK.Has(VK) ? 1 : 0)
    DllCall("keybd_event", "UChar", VK, "UChar", SC, "UInt", flags, "UPtr", 0)

    if state
        TrackDown(bucket, Key, "Game", tableItem, index)
    else
        TrackUp(bucket, Key, tableItem, index)
}

SendGameMouseKey(key, state, tableItem, index) {
    static MouseMap := Map(
        "LButton",   {Down: 0x0002, Up: 0x0004, Data: 0},
        "RButton",   {Down: 0x0008, Up: 0x0010, Data: 0},
        "MButton",   {Down: 0x0020, Up: 0x0040, Data: 0},
        "WheelUp",   {Down: 0x0800, Up: 0,      Data: 120},
        "WheelDown", {Down: 0x0800, Up: 0,      Data: -120},
        "XButton1",  {Down: 0x0080, Up: 0x0100, Data: 0x0001},
        "XButton2",  {Down: 0x0080, Up: 0x0100, Data: 0x0002}
    )

    bucket := GetHoldBucket(tableItem, index)
    info := MouseMap[key]

    if state {
        DllCall("mouse_event", "UInt", info.Down, "UInt", 0, "UInt", 0, "UInt", info.Data, "UInt", 0)
        TrackDown(bucket, key, "GameMouse", tableItem, index)
    } else {
        if info.Up
            DllCall("mouse_event", "UInt", info.Up, "UInt", 0, "UInt", 0, "UInt", info.Data, "UInt", 0)
        TrackUp(bucket, key, tableItem, index)
    }
}

SendJoyBtnKey(key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    JoyBtnName := SubStr(key, 4)

    ; 友好键名 → ViGEm 按钮名（Xbox / DS4 两套输出名）
    static xboxBtnMap := Map(
        "A", "A", "B", "B", "X", "X", "Y", "Y",
        "LB", "LB", "RB", "RB", "LS", "LS", "RS", "RS",
        "Back", "Back", "Start", "Start", "Home", "Guide", "Pad", "A",
        "O", "B", "Square", "X", "Triangle", "Y",
        "L1", "LB", "R1", "RB", "L3", "LS", "R3", "RS",
        "Share", "Back", "Options", "Start", "PS", "Guide", "TouchPad", "A"
    )
    static ds4BtnMap := Map(
        "A", "Cross", "B", "Circle", "X", "Square", "Y", "Triangle",
        "O", "Circle", "Square", "Square", "Triangle", "Triangle",
        "LB", "L1", "RB", "R1", "L1", "L1", "R1", "R1",
        "LS", "LS", "RS", "RS", "L3", "LS", "R3", "RS",
        "Back", "Share", "Start", "Options", "Share", "Share", "Options", "Options",
        "Home", "Ps", "PS", "Ps", "Pad", "TouchPad", "TouchPad", "TouchPad"
    )
    btnMap := (MainSoftData.JoyType == "DS4") ? ds4BtnMap : xboxBtnMap
    if (btnMap.Has(JoyBtnName))
        JoyBtnName := btnMap[JoyBtnName]

    ; 有效 ViGEm 按钮/扳机名白名单；未知键名（如其它手柄特有键 UUU）执行时忽略，避免程序异常
    static validJoyName := Map(
        "A", 0, "B", 0, "X", 0, "Y", 0, "LB", 0, "RB", 0, "LS", 0, "RS", 0,
        "Back", 0, "Start", 0, "Guide", 0,
        "Cross", 0, "Circle", 0, "Square", 0, "Triangle", 0,
        "L1", 0, "R1", 0, "L2", 0, "R2", 0, "L3", 0, "R3", 0,
        "Share", 0, "Options", 0, "Ps", 0, "TouchPad", 0,
        "LT", 0, "RT", 0, "ZMin", 0, "ZMax", 0
    )
    if (!validJoyName.Has(JoyBtnName)) {
        JoyDebugLog(Format("SendJoyBtnKey IGNORE unknown key={} btnName={}", key, JoyBtnName), "send")
        return
    }

    JoyDebugLog(Format("SendJoyBtnKey key={} state={} btnName={} MyViGJoySetState={}", key, state, JoyBtnName
        , Type(MyViGJoySetState)), "send")

    ; 扳机：JoyLT/RT、JoyL2/R2、轴名 ZMin/ZMax
    if (JoyBtnName = "LT" || JoyBtnName = "RT" || JoyBtnName = "L2" || JoyBtnName = "R2"
        || JoyBtnName = "ZMin" || JoyBtnName = "ZMax") {
        axisName := (JoyBtnName = "ZMin" || JoyBtnName = "LT" || JoyBtnName = "L2") ? "LT" : "RT"
        MyViGJoySetState("Axis", axisName, state ? 255 : 0)
    }
    else
        MyViGJoySetState("Btn", JoyBtnName, state)

    if state
        TrackDown(bucket, key, "Joy", tableItem, index)
    else
        TrackUp(bucket, key, tableItem, index)
}

SendJoyAxisKey(key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    Value := InStr(key, "Min") ? 0 : 100
    axisName := SubStr(key, 8, 2)
    outVal := state ? Value : 50
    JoyDebugLog(Format("SendJoyAxisKey key={} state={} axis={} value={}", key, state, axisName, outVal), "send")
    MyViGJoySetState("Axis", axisName, outVal)

    if state
        TrackDown(bucket, key, "JoyAxis", tableItem, index)
    else
        TrackUp(bucket, key, tableItem, index)
}

; 轴指令：解析规范轴键 JoyAxisLX/LY/RX/RY/LT/RT + 指令层轴值，换算并写入虚拟手柄。
;   JoyAxisLX/LY/RX/RY: 轴值为 -100..100（0=中心），换算到 ViGEm 摇杆 0..100（50=中心）
;   JoyAxisLT/RT:       轴值为 0..100，换算到 ViGEm 扳机 0..255
; key 形如 "JoyAxisLX"（不含 Min/Max，axisValue 为指令层真实模拟量）
SendJoyAxisValueKey(key, state, axisValue, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    axisName := SubStr(key, 8)             ; "JoyAxisLX" -> "LX"
    ; 白名单判定：未知轴名直接忽略，避免被当成摇杆写入非法值
    static StickAxes := Map("LX", 1, "LY", 1, "RX", 1, "RY", 1)
    static TriggerAxes := Map("LT", 1, "RT", 1)
    isStick := StickAxes.Has(axisName)
    isTrigger := TriggerAxes.Has(axisName)
    if (!isStick && !isTrigger) {
        JoyDebugLog(Format("SendJoyAxisValueKey IGNORE unknown axis key={}", key), "send")
        return
    }

    ; 松开（state=0）时回到中性：摇杆回中(指令0)、扳机归零(0)
    target := state ? axisValue : 0

    ; 换算：摇杆指令 -100..100 -> ViGEm 0..100(50=中心)；扳机指令 0..100 -> ViGEm 0..255
    outVal := 0
    if (isStick) {
        outVal := Round(ClampAxisValue(target, -100, 100) / 2 + 50)   ; -100->0, 0->50, +100->100
    } else {
        outVal := Round(ClampAxisValue(target, 0, 100) * 2.55)        ; 0->0, 100->255
    }
    JoyDebugLog(Format("SendJoyAxisValueKey key={} state={} value={} axis={} out={}", key, state, axisValue, axisName, outVal), "send")
    MyViGJoySetState("Axis", axisName, outVal)

    if (state)
        TrackDown(bucket, key, "JoyAxisValue", tableItem, index)
    else
        TrackUp(bucket, key, tableItem, index)
}

; 指令层轴值裁剪到 [min,max]，返回裁剪后整数
ClampAxisValue(v, min, max) {
    v := IsNumber(v) ? v : 0
    if (v < min)
        return min
    if (v > max)
        return max
    return v
}

SendJoyDpadKey(key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    RealKey := SubStr(key, 8)
    dpadVal := state ? RealKey : "None"
    JoyDebugLog(Format("SendJoyDpadKey key={} state={} dpad={}", key, state, dpadVal), "send")
    MyViGJoySetState("Dpad", dpadVal, 0)

    if state && (RealKey != "None")
        TrackDown(bucket, key, "JoyDpad", tableItem, index)
    else
        ClearDpadHoldState(bucket, tableItem, index)
}

; ------------------------------------------------------------
; Brightness
; ------------------------------------------------------------
SetBrightnessByKey(key, *) {
    if (key = "Bright_Down")
        ChangeBrightness(false)
    else if (key = "Bright_Up")
        ChangeBrightness(true)
}

ChangeBrightness(isAdd) {
    CurrentBrightness := GetBrightness()
    Value := Max(0, Min(100, CurrentBrightness + (isAdd ? 10 : -10)))
    wmi := ComObjGet("winmgmts:\\.\root\WMI")
    for item in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
        item.WmiSetBrightness(1, Value)
}