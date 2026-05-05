#Requires AutoHotkey v2.0
#SingleInstance Force

global rawInputHwnd := 0
global mouseTrail := []
global msgCount := 0

hInstance := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
rawInputHwnd := DllCall("CreateWindowEx", "UInt", 0, "Str", "Message", "Ptr", 0, "UInt", 0
    , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr", -3, "Ptr", 0, "Ptr", hInstance, "Ptr", 0, "Ptr")

OnMessage(0x00FF, OnWMInput)

RID := Buffer(A_PtrSize == 8 ? 16 : 12, 0)
NumPut("UShort", 0x01, RID, 0)  
NumPut("UShort", 0x02, RID, 2)
NumPut("UInt", 0x00000100, RID, 4)
NumPut("UPtr", rawInputHwnd, RID, 8)

DllCall("RegisterRawInputDevices", "Ptr", RID.Ptr, "UInt", 1, "UInt", A_PtrSize == 8 ? 16 : 12)

mouseSpeed := 0
DllCall("SystemParametersInfo", "UInt", 0x0070, "UInt", 0, "IntP", &mouseSpeed, "UInt", 0)
dpiX := 96
try {
    hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    dpiX := DllCall("GetDeviceCaps", "Ptr", hDC, "Int", 88, "Int")
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
}
scaleFactor := (mouseSpeed / 10.0) * (dpiX / 96.0)

ToolTip("自动录制中... 移动鼠标`nF2: 显示结果 | ESC: 退出`n`nscale=" Round(scaleFactor,2))
SetTimer () => ToolTip(), -4000

Hotkey "F2", ShowResult
Hotkey "Escape", (*) => ExitApp()

OnWMInput(wParam, lParam, msg, hwnd) {
    global rawInputHwnd, mouseTrail, msgCount
    if (hwnd != rawInputHwnd)
        return

    headerSize := A_PtrSize == 8 ? 24 : 16
    rawInput := Buffer(64, 0)
    size := 64
    ret := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", rawInput.Ptr, "UIntP", &size, "UInt", headerSize)
    if (ret <= 0)
        return

    dwType := NumGet(rawInput, 0, "UInt")
    if (dwType != 0)
        return

    if (A_PtrSize == 8) {
        x := NumGet(rawInput, 36, "Int")
        y := NumGet(rawInput, 40, "Int")
    } else {
        x := NumGet(rawInput, 32, "Int")
        y := NumGet(rawInput, 36, "Int")
    }

    if (x != 0 || y != 0) {
        px := Round(x / scaleFactor)
        py := Round(y / scaleFactor)
        mouseTrail.Push(Map("px", px, "py", py, "t", A_TickCount))
        msgCount++
    }
}

ShowResult(*) {
    s := "=========================`n"
    s .= "RawInput 鼠标轨迹(像素)`n"
    s .= "=========================`n"
    s .= "鼠标速度: " mouseSpeed "/20  DPI: " dpiX "`n"
    s .= "换算系数: " Round(scaleFactor, 3) "`n"
    s .= "捕获点数: " mouseTrail.Length "`n`n"

    if (mouseTrail.Length == 0) {
        s .= "(未检测到鼠标移动)`n"
    } else {
        totalPx := 0
        totalPy := 0
        Loop Min(25, mouseTrail.Length) {
            p := mouseTrail[A_Index]
            totalPx += p["px"]
            totalPy += p["py"]
            s .= Format("{:3d}: dx={:+6d}px  dy={:+6d}px`n", A_Index, p["px"], p["py"])
        }
        if (mouseTrail.Length > 25)
            s .= "... 共 " mouseTrail.Length " 个点`n"
        dist := Sqrt(totalPx**2 + totalPy**2)
        s .= "`n------------------------`n"
        s .= "总位移: X=" totalPx "px  Y=" totalPy "px`n"
        s .= "直线距离: " Round(dist) "px`n"
        s .= "✅ RawInput 鼠标轨迹捕获成功！"
    }
    MsgBox(s, "RawInput 结果")
}
