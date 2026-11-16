/*  XInput by Lexikos
 */

#Requires AutoHotkey v2.0-beta.6

/*
    Function: XInput_Init
    
    Initializes XInput.ahk with the given XInput DLL.
    
    Parameters:
        dll     -   The path or name of the XInput DLL to load.
*/
XInput_Init(dll:="")
{
    global
    if _XInput_hm ?? 0
        return
    
    ;======== CONSTANTS DEFINED IN XINPUT.H ========
    
    ; Device types available in XINPUT_CAPABILITIES
    XINPUT_DEVTYPE_GAMEPAD          := 0x01

    ; Device subtypes available in XINPUT_CAPABILITIES
    XINPUT_DEVSUBTYPE_GAMEPAD       := 0x01

    ; Flags for XINPUT_CAPABILITIES
    XINPUT_CAPS_VOICE_SUPPORTED     := 0x0004

    ; Constants for gamepad buttons
    XINPUT_GAMEPAD_DPAD_UP          := 0x0001
    XINPUT_GAMEPAD_DPAD_DOWN        := 0x0002
    XINPUT_GAMEPAD_DPAD_LEFT        := 0x0004
    XINPUT_GAMEPAD_DPAD_RIGHT       := 0x0008
    XINPUT_GAMEPAD_START            := 0x0010
    XINPUT_GAMEPAD_BACK             := 0x0020
    XINPUT_GAMEPAD_LEFT_THUMB       := 0x0040
    XINPUT_GAMEPAD_RIGHT_THUMB      := 0x0080
    XINPUT_GAMEPAD_LEFT_SHOULDER    := 0x0100
    XINPUT_GAMEPAD_RIGHT_SHOULDER   := 0x0200
    XINPUT_GAMEPAD_GUIDE            := 0x0400
    XINPUT_GAMEPAD_A                := 0x1000
    XINPUT_GAMEPAD_B                := 0x2000
    XINPUT_GAMEPAD_X                := 0x4000
    XINPUT_GAMEPAD_Y                := 0x8000

    ; Gamepad thresholds
    XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE  := 7849
    XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE := 8689
    XINPUT_GAMEPAD_TRIGGER_THRESHOLD    := 30

    ; Flags to pass to XInputGetCapabilities
    XINPUT_FLAG_GAMEPAD             := 0x00000001
    
    ;=============== END CONSTANTS =================
    
    ; 候选顺序与 JoyXInputEx() 保持一致。不能只认 XInput1_3：Windows 7 常见
    ; 只有 xinput9_1_0（Vista 时代的兼容层），缺 1_3 时整块直接失败。
    ; 每个候选都要「加载 + 解析导出」全通过才算可用，否则换下一个——
    ; 只判断文件存在，遇到「有文件但缺函数」的版本会直接判死。
    local cands, nm, hm, gs, ss, gc

    _XInput_hm := 0
    _XInput_GetState := _XInput_SetState := _XInput_GetCapabilities := 0

    if (dll = "")
        cands := ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll", "xinput1_2.dll", "xinput1_1.dll"]
    else
        cands := [dll]

    for nm in cands {
        hm := DllCall("LoadLibrary", "str", nm, "ptr")
        if (!hm)
            continue
        ; 旧实现优先用 ordinal 100（带 Guide 位的扩展 GetState），不支持再按名字取
        gs := DllCall("GetProcAddress", "ptr", hm, "ptr", 100, "ptr")
        if (!gs)
            gs := DllCall("GetProcAddress", "ptr", hm, "astr", "XInputGetState", "ptr")
        ss := DllCall("GetProcAddress", "ptr", hm, "astr", "XInputSetState", "ptr")
        gc := DllCall("GetProcAddress", "ptr", hm, "astr", "XInputGetCapabilities", "ptr")
        if (gs && ss && gc) {
            _XInput_hm := hm
            _XInput_GetState := gs
            _XInput_SetState := ss
            _XInput_GetCapabilities := gc
            break
        }
        DllCall("FreeLibrary", "ptr", hm)
    }

    if !_XInput_hm
        throw Error("Failed to initialize XInput: 系统没有可用的 XInput DLL（已试 xinput1_4 / 1_3 / 9_1_0 / 1_2 / 1_1）")
}

; XInput 只是可选能力，系统里没有任何可用的 XInput DLL 时不该让主程序起不来。
; 生产代码读手柄走 JoyXInputEx()（自带多候选 + 优雅降级），本库只给
; Plugins\ViGEm\test.ahk 用，所以自动初始化失败只留标志（_XInput_hm=0），不抛错。
try XInput_Init()
catch
    _XInput_hm := 0

/*
    Function: XInput_GetState
    
    Retrieves the current state of the specified controller.

    Parameters:
        UserIndex   -   [in] Index of the user's controller. Can be a value from 0 to 3.
    
    Returns:
        An object with with properties equivalent to merging XINPUT_STATE and XINPUT_GAMEPAD.
        https://docs.microsoft.com/en-us/windows/win32/api/xinput/ns-xinput-xinput_state
    
    Error handling:
        Returns false if the controller is disconnected.
        Throws an OSError for other errors.
*/
XInput_GetState(UserIndex)
{
    global _XInput_GetState
    
    xiState := Buffer(16)

    if err := DllCall(_XInput_GetState ,"uint",UserIndex ,"ptr",xiState) {
        if err = 1167 ; ERROR_DEVICE_NOT_CONNECTED
            return 0
        throw OSError(err, -1)
    }
    
    return {
        dwPacketNumber: NumGet(xiState,  0, "UInt"),
        wButtons:       NumGet(xiState,  4, "UShort"),
        bLeftTrigger:   NumGet(xiState,  6, "UChar"),
        bRightTrigger:  NumGet(xiState,  7, "UChar"),
        sThumbLX:       NumGet(xiState,  8, "Short"),
        sThumbLY:       NumGet(xiState, 10, "Short"),
        sThumbRX:       NumGet(xiState, 12, "Short"),
        sThumbRY:       NumGet(xiState, 14, "Short"),
    }
}

/*
    Function: XInput_SetState
    
    Sends data to a connected controller. This function is used to activate the vibration
    function of a controller.
    
    Parameters:
        UserIndex       -   [in] Index of the user's controller. Can be a value from 0 to 3.
        LeftMotorSpeed  -   [in] Speed of the left motor, between 0 and 65535.
        RightMotorSpeed -   [in] Speed of the right motor, between 0 and 65535.
    
    Error handling:
        Throws an OSError on failure, such as if the controller is not connected.
    
    Remarks:
        The left motor is the low-frequency rumble motor. The right motor is the
        high-frequency rumble motor. The two motors are not the same, and they create
        different vibration effects.
*/
XInput_SetState(UserIndex, LeftMotorSpeed, RightMotorSpeed)
{
    global _XInput_SetState
    if err := DllCall(_XInput_SetState ,"uint",UserIndex ,"uint*",LeftMotorSpeed|RightMotorSpeed<<16)
        throw OSError(err, -1)
}

/*
    Function: XInput_GetCapabilities
    
    Retrieves the capabilities and features of a connected controller.
    
    Parameters:
        UserIndex   -   [in] Index of the user's controller. Can be a value in the range 03.
        Flags       -   [in] Input flags that identify the controller type.
                                0   - All controllers.
                                1   - XINPUT_FLAG_GAMEPAD: Xbox 360 Controllers only.
    
    Returns:
        An object with properties equivalent to XINPUT_CAPABILITIES.
        https://docs.microsoft.com/en-au/windows/win32/api/xinput/ns-xinput-xinput_capabilities
    
    Error handling:
        Returns false if the controller is disconnected.
        Throws an OSError for other errors.
*/
XInput_GetCapabilities(UserIndex, Flags)
{
    global _XInput_GetCapabilities
    
    xiCaps := Buffer(20)
    
    if err := DllCall(_XInput_GetCapabilities ,"uint",UserIndex ,"uint",Flags ,"ptr",xiCaps) {
        if err = 1167 ; ERROR_DEVICE_NOT_CONNECTED
            return 0
        throw OSError(err, -1)
    }
    
    return {
        Type:                   NumGet(xiCaps,  0, "UChar"),
        SubType:                NumGet(xiCaps,  1, "UChar"),
        Flags:                  NumGet(xiCaps,  2, "UShort"),
        Gamepad: {
            wButtons:           NumGet(xiCaps,  4, "UShort"),
            bLeftTrigger:       NumGet(xiCaps,  6, "UChar"),
            bRightTrigger:      NumGet(xiCaps,  7, "UChar"),
            sThumbLX:           NumGet(xiCaps,  8, "Short"),
            sThumbLY:           NumGet(xiCaps, 10, "Short"),
            sThumbRX:           NumGet(xiCaps, 12, "Short"),
            sThumbRY:           NumGet(xiCaps, 14, "Short")
        },
        Vibration: {
            wLeftMotorSpeed:    NumGet(xiCaps, 16, "UShort"),
            wRightMotorSpeed:   NumGet(xiCaps, 18, "UShort")
        }
    }
}

/*
    Function: XInput_Term
    Unloads the previously loaded XInput DLL.
*/
XInput_Term() {
    global
    if _XInput_hm
        DllCall("FreeLibrary","uint",_XInput_hm), _XInput_hm :=_XInput_GetState :=_XInput_SetState :=_XInput_GetCapabilities :=0
}

; TODO: XInputEnable, 'GetBatteryInformation and 'GetKeystroke.