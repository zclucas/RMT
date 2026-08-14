#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; GameInput 手柄测试工具
; Live display of all connected gamepad inputs via GameInput API
; ============================================================

#Include "../CLR.ahk"

; GameInputGamepadButtons bitmask (from InputWeave.GameInput):
; Menu=1 View=2 A=4 B=8 X=16 Y=32
; DPadUp=64 DPadDown=128 DPadLeft=256 DPadRight=512
; LB=1024 RB=2048 L3=4096 R3=8192
global BtnNames := Map(
    0,  "Menu",    1,  "View",    2,  "A",       3,  "B",
    4,  "X",       5,  "Y",       6,  "D-Up",    7,  "D-Down",
    8,  "D-Left",  9,  "D-Right", 10, "LB",      11, "RB",
    12, "L3",      13, "R3"
)

global MAX_SLOTS := 4
global wrapper := 0
global guiObj := 0
global deviceSlots := Map()   ; deviceId -> slotIndex
global slotDevices := Map()   ; slotIndex -> deviceId
global lastDiag := ""

; ============================================================
; GUI
; ============================================================

BuildGui() {
    global guiObj
    guiObj := Gui("+Resize +MinSize640x360", "GameInput Test - Controller Monitor")
    guiObj.SetFont("s9", "Consolas")
    guiObj.OnEvent("Close", OnGuiClose)

    guiObj.Add("Text", "x10 y8 w620 h24 vStatusText",
        "GameInput loaded. Press a gamepad button to begin.")
    guiObj.Add("Text", "x10 y32 w620 h20 c888888 vHintText",
        "(GameInput is event-driven — readings only appear on input changes)")

    yBase := 58
    slotH := 142

    Loop MAX_SLOTS {
        slot := A_Index
        sy := yBase + (slot - 1) * (slotH + 6)

        grp := guiObj.Add("GroupBox", "x10 y" sy " w620 h" slotH " vSlotGrp" slot, "Slot " slot)
        grp.Visible := false

        yOff := sy + 22
        guiObj.SetFont("s8", "Consolas")
        guiObj.Add("Text", "x20 y" yOff " w190 vSlot" slot "LStick", "L:  0.00,  0.00")
        guiObj.Add("Text", "x220 y" yOff " w190 vSlot" slot "RStick", "R:  0.00,  0.00")
        guiObj.Add("Text", "x430 y" yOff " w190 vSlot" slot "Trig",   "L2:0.00 R2:0.00")

        yOff += 20
        guiObj.Add("Text", "x20 y" yOff " w300 vSlot" slot "DPad", "DPad: -")
        yOff += 20
        guiObj.Add("Text", "x20 y" yOff " w600 vSlot" slot "Btns", "Buttons: -")

        yOff += 20
        guiObj.SetFont("s7", "Consolas")
        guiObj.Add("Text", "x20 y" yOff " w600 c888888 vSlot" slot "DevID", "")
        guiObj.SetFont("s8", "Consolas")
    }

    bY := yBase + MAX_SLOTS * (slotH + 6) + 6
    guiObj.SetFont("s9", "Consolas")
    guiObj.Add("Text", "x10 y" bY " w620 h20 vPollStatus", "Controllers: 0")
    bY += 22
    guiObj.SetFont("s8", "Consolas")
    guiObj.Add("Edit", "x10 y" bY " w620 h80 ReadOnly vDiagBox",
        "按LT/RT/推摇杆，观察下方偏移")

    guiObj.Show("w640 h" (bY + 100))
}

OnGuiClose(*) {
    global wrapper
    try
        if (wrapper)
            wrapper.Dispose()
    ExitApp(0)
}

; ============================================================
; Poll & Update
; ============================================================

PollAndUpdate() {
    global wrapper, guiObj, deviceSlots, slotDevices

    result := ""
    try
        result := wrapper.PollString()
    catch
        return

    if (result = "") {
        UpdateCount()
        return
    }

    lines := StrSplit(result, "`n", " `t")
    for line in lines {
        if (line = "")
            continue
        parts := StrSplit(line, ";")
        if (parts.Length < 8)
            continue

        ; C# field order: devId;lx;ly;rx;ry;lt;rt;buttons
        devId := parts[1]
        lx    := Float(parts[2])
        ly    := Float(parts[3])
        rx    := Float(parts[4])
        ry    := Float(parts[5])
        lt    := Float(parts[6])
        rt    := Float(parts[7])
        btns  := Integer(parts[8])

        ; Allocate new slot if needed
        if !deviceSlots.Has(devId) {
            slot := AllocSlot(devId)
            if (slot = 0)
                continue
        }

        slot := deviceSlots[devId]
        UpdateSlot(slot, devId, lx, ly, rx, ry, lt, rt, btns)
    }
    UpdateCount()
}

UpdateSlot(slot, devId, lx, ly, rx, ry, lt, rt, btns) {
    guiObj["SlotGrp" slot].Visible := true
    guiObj["SlotGrp" slot].Text := "Controller " slot

    guiObj["Slot" slot "LStick"].Value := Format("L: {:+05.2f}, {:+05.2f}", lx, ly)
    guiObj["Slot" slot "RStick"].Value := Format("R: {:+05.2f}, {:+05.2f}", rx, ry)
    guiObj["Slot" slot "Trig"].Value   := Format("L2:{:.2f}  R2:{:.2f}", lt, rt)

    ; DPad (bits 6-9)
    dpad := ""
    if (btns >> 6) & 1
        dpad .= "U"
    if (btns >> 7) & 1
        dpad .= "D"
    if (btns >> 8) & 1
        dpad .= "L"
    if (btns >> 9) & 1
        dpad .= "R"
    if (dpad = "")
        dpad := "-"
    guiObj["Slot" slot "DPad"].Value := "DPad: " dpad

    ; Buttons (bits 0-5, 10-13)
    pressed := []
    Loop 16 {
        bit := A_Index - 1
        if (bit >= 6 && bit <= 9)
            continue
        if (btns >> bit) & 1 {
            name := BtnNames.Has(bit) ? BtnNames[bit] : "B" bit
            pressed.Push(name)
        }
    }
    guiObj["Slot" slot "Btns"].Value := "Buttons: " (pressed.Length > 0 ? Join(pressed, " ") : "-")

    guiObj["Slot" slot "DevID"].Value := devId
}

AllocSlot(devId) {
    global deviceSlots, slotDevices, MAX_SLOTS
    Loop MAX_SLOTS {
        if !slotDevices.Has(A_Index) {
            slotDevices[A_Index] := devId
            deviceSlots[devId] := A_Index
            return A_Index
        }
    }
    return 0
}

ShowDiag() {
    global wrapper, guiObj, lastDiag
    try {
        d := wrapper.GetDiag()
        if (d != lastDiag) {
            lastDiag := d
            guiObj["DiagBox"].Value := d
        }
    }
}

UpdateCount() {
    global guiObj, deviceSlots
    count := 0
    for _ in deviceSlots
        count++
    guiObj["PollStatus"].Value := "Controllers: " count
}

Join(arr, sep) {
    s := ""
    for i, v in arr {
        if (i > 1)
            s .= sep
        s .= v
    }
    return s
}

; ============================================================
; Entry
; ============================================================

loadGui := Gui(, "GameInput Test")
loadGui.SetFont("s10", "Microsoft YaHei")
loadGui.Add("Text", "x20 y30 w500", "Compiling & initializing GameInput...")
loadGui.Show("w320 h100")

try {
    csPath := A_ScriptDir "\GameInputWrapper.cs"
    csCode := FileRead(csPath, "UTF-8")

    ; Try compilation — CLR_CompileCS throws with details on failure
    asm := CLR_CompileCS(csCode)
    if (!asm)
        throw Error("C# compilation returned null (no details)")

    wrapper := asm.CreateInstance("GameInputTest.GameInputWrapper")
    if (!wrapper)
        throw Error("Failed to create GameInputWrapper instance")

    if (!wrapper.Init())
        throw Error("GameInput SDK unavailable.`nRequires Windows 10 1809+ with GameInput.dll.")

    loadGui.Destroy()

    ; Verify CLR interop works
    pingResult := wrapper.Ping()
    if (!pingResult || !InStr(pingResult, "pong")) {
        MsgBox("CLR interop failed: Ping() returned '" pingResult "'", "Error", 0x10)
        ExitApp(1)
    }

    BuildGui()
    guiObj["StatusText"].Value := "CLR OK | " wrapper.GetDebugInfo()
    ; Also add a diag display
    guiObj["HintText"].Value := "(Press gamepad buttons — diag updates every 2s)"
    SetTimer PollAndUpdate, 50
    SetTimer ShowDiag, 500

} catch as e {
    try loadGui.Destroy()
    fullMsg := "GameInput Error:`n`n" e.Message
    try
        if (e.Extra)
            fullMsg .= "`n`n" e.Extra
    errGui := Gui("+Resize", "GameInput Error")
    errGui.SetFont("s9", "Consolas")
    errGui.Add("Edit", "x10 y10 w700 h350 ReadOnly", fullMsg)
    errGui.Show("w720 h380")
    errGui.OnEvent("Close", (*) => ExitApp(1))
    Persistent()
}
