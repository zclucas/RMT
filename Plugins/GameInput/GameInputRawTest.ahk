#Requires AutoHotkey v2.0
#SingleInstance Force

; Load GameInput.dll
hModule := DllCall("LoadLibrary", "Str", "GameInput.dll", "Ptr")
if (!hModule) {
    MsgBox("GameInput.dll not found!")
    ExitApp(1)
}
pCreate := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "GameInputCreate", "Ptr")
if (!pCreate) {
    MsgBox("GameInputCreate not found!")
    ExitApp(1)
}

pGI := 0
hr := DllCall(pCreate, "Ptr*", &pGI, "Int")
if (hr < 0 || !pGI) {
    MsgBox("GameInputCreate failed: 0x" Format("{:08X}", hr))
    ExitApp(1)
}

vt := NumGet(pGI, 0, "Ptr")
out := "GameInputCreate OK`r`n"
out .= "pGI=0x" Format("{:X}", pGI) "  vt=0x" Format("{:X}", vt) "`r`n`r`n"

; ---- vt[3] = GetCurrentTimestamp (confirmed) ----
fp3 := NumGet(vt + 3 * A_PtrSize, 0, "Ptr")
ts1 := DllCall(fp3, "Ptr", pGI, "Int64")
ts2 := DllCall(fp3, "Ptr", pGI, "Int64")
out .= "vt[3] GetCurrentTimestamp:`r`n"
out .= "  1st=0x" Format("{:016X}", ts1) "`r`n"
out .= "  2nd=0x" Format("{:016X}", ts2)
out .= (ts1 != ts2 ? " MONOTONIC ✓" : " (static)") "`r`n`r`n"

; ---- vt[4] = GetCurrentReading? ----
fp4 := NumGet(vt + 4 * A_PtrSize, 0, "Ptr")
buf := Buffer(A_PtrSize, 0)

Test(mask, label) {
    global fp4, pGI, buf
    NumPut("Ptr", 0, buf)
    hr := DllCall(fp4, "Ptr", pGI, "UInt", mask, "Ptr", 0, "Ptr", buf.Ptr, "Int")
    rd := NumGet(buf, 0, "Ptr")
    s := "  " label " → HR=0x" Format("{:08X}", hr & 0xFFFFFFFF)
    s .= " rd=" (rd ? "0x" Format("{:X}", rd) : "null")
    return s
}

out .= "vt[4] (assumed GetCurrentReading):`r`n"
out .= Test(0xFFFFFFFF, "ALL ") "`r`n"
out .= Test(0x0000000E, "CTRL") "`r`n"
out .= Test(0x3400000E, "GAMP") "`r`n"
out .= Test(0x00000000, "NONE") "`r`n"

; ---- Wait 3s, ask user to press a gamepad button ----
out .= "`r`nWaiting 3 seconds — PRESS ANY GAMEPAD BUTTON NOW!`r`n"
Sleep(3000)
out .= Test(0xFFFFFFFF, "BTN?") "`r`n"
out .= Test(0x00000000, "BTN?") "`r`n"

; ---- Test reading pointer (if any) ----
rd := NumGet(buf, 0, "Ptr")
if (rd) {
    rvt := NumGet(rd, 0, "Ptr")
    out .= "`r`nReading* = 0x" Format("{:X}", rd)
    out .= "  vt=0x" Format("{:X}", rvt) "`r`n"

    ; GetDevice (vtable 6 on IGameInputReading)
    fpGetDev := NumGet(rvt + 6 * A_PtrSize, 0, "Ptr")
    cDev := 0
    hr := DllCall(fpGetDev, "Ptr", rd, "Ptr*", &cDev, "Int")
    out .= "GetDevice → HR=0x" Format("{:08X}", hr) " dev=0x" Format("{:X}", cDev) "`r`n"

    ; GetGamepadState (vtable 22)
    fpGS := NumGet(rvt + 22 * A_PtrSize, 0, "Ptr")
    gs := Buffer(32, 0)
    hr := DllCall(fpGS, "Ptr", rd, "Ptr", gs.Ptr, "Int")
    out .= "GetGamepadState → HR=0x" Format("{:08X}", hr) "`r`n"
    if (hr >= 0) {
        out .= Format("  LX={:+.3f} LY={:+.3f}", NumGet(gs, 0, "Float"), NumGet(gs, 4, "Float"))
        out .= Format("  RX={:+.3f} RY={:+.3f}", NumGet(gs, 8, "Float"), NumGet(gs, 12, "Float"))
        out .= Format("  LT={:.3f} RT={:.3f}", NumGet(gs, 16, "Float"), NumGet(gs, 20, "Float"))
        out .= Format("  Btn=0x{:X}`r`n", NumGet(gs, 24, "UInt64"))
    }
} else {
    out .= "`r`nStill null reading.`r`n"
}

; Show
GuiObj := Gui(, "GameInput Raw Test v2")
GuiObj.SetFont("s9", "Consolas")
GuiObj.Add("Edit", "x10 y10 w760 h400 ReadOnly", out)
GuiObj.Show("w780 h430")
GuiObj.OnEvent("Close", (*) => (DllCall("FreeLibrary", "Ptr", hModule), ExitApp(0)))
Persistent()
