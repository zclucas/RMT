#Requires AutoHotkey v2.0
; ------------------------------------------------------------
; Helper
; ------------------------------------------------------------
GetHoldBucket(tableItem, index) {
    return tableItem.HoldKeyArr[index]
}

TrackDown(bucket, key, source) {
    if !MySoftData.OnlyDownKeyMap.Has(key)
        bucket[key] := source
}

TrackUp(bucket, key) {
    if !MySoftData.OnlyDownKeyMap.Has(key)
        bucket.Delete(key)
}

ClearDpadHoldState(bucket) {
    for dpadKey in ["Up", "Down", "Left", "Right"]
        bucket.Delete(dpadKey)
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

    Send("{Blind}{" Key " " (state ? "down" : "up") "}")
    if state
        TrackDown(bucket, Key, "Normal")
    else
        TrackUp(bucket, Key)
}

SendLogicKey(Key, state, tableItem, index) {
    if !InitLogitechGHubNew()
        return

    bucket := GetHoldBucket(tableItem, index)

    IbSend("{Blind}{" Key " " (state ? "down" : "up") "}")
    if state
        TrackDown(bucket, Key, "Logic")
    else
        TrackUp(bucket, Key)
}

SendAHIKey(Key, state, tableItem, index) {
    if !InitAHI()
        return

    bucket := GetHoldBucket(tableItem, index)

    AhiSendKey(Key, state)
    if state
        TrackDown(bucket, Key, "AHI")
    else
        TrackUp(bucket, Key)
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
        TrackDown(bucket, Key, "Game")
    else
        TrackUp(bucket, Key)
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
        TrackDown(bucket, key, "GameMouse")
    } else {
        if info.Up
            DllCall("mouse_event", "UInt", info.Up, "UInt", 0, "UInt", 0, "UInt", info.Data, "UInt", 0)
        TrackUp(bucket, key)
    }
}

SendJoyBtnKey(key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    JoyBtnName := SubStr(key, 4)

    ; PS5 模式：将 Xbox 风格的按钮名转为 DS4 风格
    if (MainSoftData.JoyType == "PS5") {
        static ps5BtnMap := Map(
            "A", "Square",
            "B", "Cross",
            "X", "Circle",
            "Y", "Triangle",
            "LB", "L1",
            "RB", "R1",
            "Back", "Share",
            "Start", "Options",
            "Home", "Ps",
            "Pad", "TouchPad"
        )
        if (ps5BtnMap.Has(JoyBtnName))
            JoyBtnName := ps5BtnMap[JoyBtnName]
    }

    JoyDebugLog(Format("SendJoyBtnKey key={} state={} btnName={} MyViGJoySetState={}", key, state, JoyBtnName
        , Type(MyViGJoySetState)), "send")

    ; 兼容 LT/RT 的两种键名：
    ;   - 友好名（JoyLT/JoyRT）→ btnName = LT/RT
    ;   - 映射后的轴名（JoyZMin/JoyZMax）→ btnName = ZMin/ZMax
    if (JoyBtnName = "LT" || JoyBtnName = "RT"
        || JoyBtnName = "ZMin" || JoyBtnName = "ZMax") {
        axisName := (JoyBtnName = "ZMin" || JoyBtnName = "LT") ? "LT" : "RT"
        MyViGJoySetState("Axis", axisName, state ? 255 : 0)
    }
    else
        MyViGJoySetState("Btn", JoyBtnName, state)

    if state
        TrackDown(bucket, key, "Joy")
    else
        TrackUp(bucket, key)
}

SendJoyAxisKey(key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    Value := InStr(key, "Min") ? 0 : 100
    axisName := SubStr(key, 8, 2)
    outVal := state ? Value : 50
    JoyDebugLog(Format("SendJoyAxisKey key={} state={} axis={} value={}", key, state, axisName, outVal), "send")
    MyViGJoySetState("Axis", axisName, outVal)

    if state
        TrackDown(bucket, key, "JoyAxis")
    else
        TrackUp(bucket, key)
}

SendJoyDpadKey(key, state, tableItem, index) {
    bucket := GetHoldBucket(tableItem, index)

    RealKey := SubStr(key, 8)
    dpadVal := state ? RealKey : "None"
    JoyDebugLog(Format("SendJoyDpadKey key={} state={} dpad={}", key, state, dpadVal), "send")
    MyViGJoySetState("Dpad", dpadVal, 0)

    if state && (RealKey != "None")
        TrackDown(bucket, key, "JoyDpad")
    else
        ClearDpadHoldState(bucket)
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