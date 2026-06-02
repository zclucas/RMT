#Requires AutoHotkey v2.0

global RI_hwnd := 0
global RI_isActive := false
global RI_accumX := 0
global RI_accumY := 0
global RI_scaleFactor := 1.0
global RI_headerSize := A_PtrSize == 8 ? 24 : 16
global RI_eventQueue := []
global RI_startX := 0
global RI_startY := 0
global RI_lastEmitX := 0
global RI_lastEmitY := 0
global RI_lastSnapX := -999999
global RI_lastSnapY := -999999
global RecordCountdownGui := ""
global CD_pToken := 0
global CD_hbm := 0
global CD_hdc := 0
global CD_obm := 0
global CD_G := 0
global CD_pBrushBg := 0
global CD_pPenTrack := 0
global CD_pPenFill := 0
global CD_pBrushTxt := 0
global CD_hFont := 0
global CD_hFormat := 0
global CD_hFamily := 0
global CD_canceled := false
global CD_startTime := 0
global CD_duration := 0
global CD_hwnd := 0
global CD_cx := 0
global CD_cy := 0
global CD_x := 0
global CD_y := 0
global CD_boxSize := 0
global CD_ringRadius := 0
global CD_bgRadius := 0
global CD_fontSize := 0
global CD_cb := []

global RecordBorder := ""
global RecordBorder_frame := 0

class RecordHighlightOutline {
    gui := []
    dotGui := []

    __New(x1, y1, x2, y2, b := 3, color := "red", Transparent := 255) {
        this.gui.Length := 8
        this.dotGui.Length := 4
        Loop 8 {
            this.gui[A_Index] := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x00080000")
            this.gui[A_Index].BackColor := color
            DllCall("SetLayeredWindowAttributes", "Ptr", this.gui[A_Index].hwnd, "Uint", 0, "Uchar", Transparent, "int", 2)
        }

        cornerLen := Min(Min(x2 - x1, y2 - y1) // 10, 80)

        Loop 4 {
            this.dotGui[A_Index] := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x00080000")
            this.dotGui[A_Index].BackColor := "ff3333"
            DllCall("SetLayeredWindowAttributes", "Ptr", this.dotGui[A_Index].hwnd, "Uint", 0, "Uchar", 255, "int", 2)
        }

        this.cornerLen := cornerLen
        this.b := b
        this.x1 := x1
        this.y1 := y1
        this.x2 := x2
        this.y2 := y2
    }

    Show(x1?, y1?, x2?, y2?, b?) {
        x1 := IsSet(x1) ? x1 : this.x1
        y1 := IsSet(y1) ? y1 : this.y1
        x2 := IsSet(x2) ? x2 : this.x2
        y2 := IsSet(y2) ? y2 : this.y2
        b := IsSet(b) ? b : this.b
        cl := this.cornerLen
        m := 5

        this.gui[1].Show("NA x" (m) " y" (m) " w" cl " h" b)
        this.gui[2].Show("NA x" (m) " y" (m) " w" b " h" cl)
        this.gui[3].Show("NA x" (x2 - m - cl) " y" (m) " w" cl " h" b)
        this.gui[4].Show("NA x" (x2 - m - b) " y" (m) " w" b " h" cl)
        this.gui[5].Show("NA x" (x2 - m - cl) " y" (y2 - m - b) " w" cl " h" b)
        this.gui[6].Show("NA x" (x2 - m - b) " y" (y2 - m - cl) " w" b " h" cl)
        this.gui[7].Show("NA x" (m) " y" (y2 - m - b) " w" cl " h" b)
        this.gui[8].Show("NA x" (m) " y" (y2 - m - cl) " w" b " h" cl)

        dotR := 6
        this.dotGui[1].Show("NA x" (m - dotR) " y" (m - dotR) " w" (dotR * 2) " h" (dotR * 2))
        this.dotGui[2].Show("NA x" (x2 - m - dotR) " y" (m - dotR) " w" (dotR * 2) " h" (dotR * 2))
        this.dotGui[3].Show("NA x" (x2 - m - dotR) " y" (y2 - m - dotR) " w" (dotR * 2) " h" (dotR * 2))
        this.dotGui[4].Show("NA x" (m - dotR) " y" (y2 - m - dotR) " w" (dotR * 2) " h" (dotR * 2))
    }

    Hide() {
        Loop 8 {
            try {
                this.gui[A_Index].Hide()
            }
        }
        Loop 4 {
            try {
                this.dotGui[A_Index].Hide()
            }
        }
    }

    Destroy() {
        Loop 8 {
            try {
                this.gui[A_Index].Destroy()
            }
        }
        Loop 4 {
            try {
                this.dotGui[A_Index].Destroy()
            }
        }
    }

    SetAlpha(alpha) {
        Loop 8 {
            try {
                DllCall("SetLayeredWindowAttributes", "Ptr", this.gui[A_Index].hwnd, "Uint", 0, "Uchar", alpha, "int", 2)
            }
        }
        pulse := (alpha / 255) > 0.6 ? 255 : Round(alpha * 0.9)
        Loop 4 {
            try {
                DllCall("SetLayeredWindowAttributes", "Ptr", this.dotGui[A_Index].hwnd, "Uint", 0, "Uchar", pulse, "int", 2)
            }
        }
    }
}

RI_Init() {
    global RI_hwnd, RI_scaleFactor
    if (RI_hwnd)
        return true

    hInstance := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
    RI_hwnd := DllCall("CreateWindowEx", "UInt", 0, "Str", "Message", "Ptr", 0, "UInt", 0
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr", -3, "Ptr", 0, "Ptr", hInstance, "Ptr", 0, "Ptr")

    OnMessage(0x00FF, OnWMInput_Raw)

    RID := Buffer(A_PtrSize == 8 ? 16 : 12, 0)
    NumPut("UShort", 0x01, RID, 0)
    NumPut("UShort", 0x02, RID, 2)
    NumPut("UInt", 0x00000100, RID, 4)
    NumPut("UPtr", RI_hwnd, RID, 8)

    if (!DllCall("RegisterRawInputDevices", "Ptr", RID.Ptr, "UInt", 1, "UInt", A_PtrSize == 8 ? 16 : 12))
        return false

    RID2 := Buffer(A_PtrSize == 8 ? 16 : 12, 0)
    NumPut("UShort", 0x01, RID2, 0)
    NumPut("UShort", 0x06, RID2, 2)
    NumPut("UInt", 0x00000100, RID2, 4)
    NumPut("UPtr", RI_hwnd, RID2, 8)

    DllCall("RegisterRawInputDevices", "Ptr", RID2.Ptr, "UInt", 1, "UInt", A_PtrSize == 8 ? 16 : 12)

    mouseSpeed := 0
    DllCall("SystemParametersInfo", "UInt", 0x0070, "UInt", 0, "IntP", &mouseSpeed, "UInt", 0)
    dpiX := 96
    try {
        hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        dpiX := DllCall("GetDeviceCaps", "Ptr", hDC, "Int", 88, "Int")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
    }
    RI_scaleFactor := (mouseSpeed / 10.0) * (dpiX / 96.0)

    return true
}

RI_StartRecord(startX?, startY?) {
    global RI_isActive, RI_accumX, RI_accumY, RI_eventQueue, RI_startX, RI_startY, RI_lastEmitX, RI_lastEmitY, RI_lastSnapX, RI_lastSnapY
    RI_Init()
    RI_isActive := true
    RI_accumX := 0
    RI_accumY := 0
    RI_eventQueue := []
    RI_startX := IsSet(startX) ? startX : 0
    RI_startY := IsSet(startY) ? startY : 0
    RI_lastEmitX := RI_startX
    RI_lastEmitY := RI_startY
    RI_lastSnapX := -999999
    RI_lastSnapY := -999999
}

RI_GetAbsPos() {
    global RI_startX, RI_startY, RI_accumX, RI_accumY, RI_scaleFactor
    absX := RI_startX + Round(RI_accumX / RI_scaleFactor)
    absY := RI_startY + Round(RI_accumY / RI_scaleFactor)
    return [absX, absY]
}

ShowRecordCountdown(callback) {
    global RecordCountdownGui, CD_pToken, CD_hbm, CD_hdc, CD_obm, CD_G
    global CD_pBrushBg, CD_pPenTrack, CD_pPenFill, CD_pBrushTxt
    global CD_hFont, CD_hFormat, CD_hFamily
    global CD_canceled, CD_startTime, CD_duration, CD_hwnd
    global CD_cx, CD_cy, CD_x, CD_y, CD_boxSize
    global CD_ringRadius, CD_bgRadius, CD_fontSize, CD_cb

    if (IsSet(RecordCountdownGui) && RecordCountdownGui != "" && !(IsSet(CD_canceled) && CD_canceled))
        return

    MonitorGet(, &monLeft, &monTop, &monRight, &monBottom)
    monW := monRight - monLeft
    monH := monBottom - monTop
    boxSize := Min(monW, monH) // 3
    cx := boxSize / 2
    cy := boxSize / 2
    x := (monW - boxSize) / 2 + monLeft
    y := (monH - boxSize) / 2 + monTop

    cdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 +LastFound")
    cdGui.Show("NA x" x " y" y " w" boxSize " h" boxSize)
    hwnd := WinExist()

    CD_pToken := Gdip_Startup()
    CD_hbm := CreateDIBSection(boxSize, boxSize)
    CD_hdc := CreateCompatibleDC()
    CD_obm := SelectObject(CD_hdc, CD_hbm)
    CD_G := Gdip_GraphicsFromHDC(CD_hdc)
    Gdip_SetSmoothingMode(CD_G, 4)

    ringRadius := Round(boxSize * 0.38)
    ringWidth := Round(boxSize * 0.065)
    bgRadius := boxSize * 0.42
    fontSize := Max(Round(boxSize * 0.22), 36)

    CD_pBrushBg := Gdip_BrushCreateSolid(0xCC000000)
    CD_pPenTrack := Gdip_CreatePen(0x28FFFFFF, ringWidth)
    CD_pPenFill := Gdip_CreatePen(0xFFFFFFFF, ringWidth)
    CD_pBrushTxt := Gdip_BrushCreateSolid(0xFFFFFFFF)
    CD_hFamily := Gdip_FontFamilyCreate("Segoe UI")
    CD_hFont := Gdip_FontCreate(CD_hFamily, fontSize, 1)
    CD_hFormat := Gdip_StringFormatCreate(0x4000)
    Gdip_SetStringFormatAlign(CD_hFormat, 1)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "UPtr", CD_hFormat, "Int", 1)
    Gdip_SetTextRenderingHint(CD_G, 4)

    CD_canceled := false
    CD_startTime := A_TickCount
    CD_duration := 3000
    CD_hwnd := hwnd
    CD_cx := cx
    CD_cy := cy
    CD_x := x
    CD_y := y
    CD_boxSize := boxSize
    CD_ringRadius := ringRadius
    CD_bgRadius := bgRadius
    CD_fontSize := fontSize
    CD_cb := []
    CD_cb.Push(callback)
    RecordCountdownGui := cdGui

    SetTimer(DrawCDFrame, 33)
}

DrawCDFrame() {
    global CD_canceled, CD_startTime, CD_duration, CD_cb
    global CD_hwnd, CD_hdc, CD_cx, CD_cy, CD_x, CD_y, CD_boxSize
    global CD_ringRadius, CD_bgRadius, CD_fontSize
    global CD_G, CD_pBrushBg, CD_pPenTrack, CD_pPenFill, CD_pBrushTxt
    global CD_hFont, CD_hFormat, RecordCountdownGui

    if (CD_canceled) {
        SetTimer(DrawCDFrame, 0)
        CDDestroy()
        return
    }

    elapsed := A_TickCount - CD_startTime
    if (elapsed >= CD_duration) {
        SetTimer(DrawCDFrame, 0)
        CDDestroy()
        cb := CD_cb.Pop()
        cb.Call()
        return
    }

    progress := elapsed / CD_duration
    displayNum := 3 - Floor(elapsed / 1000)
    if (displayNum < 1)
        displayNum := 1
    sweepAngle := 360 * progress

    cx := CD_cx
    cy := CD_cy
    ringRadius := CD_ringRadius
    ringD := ringRadius * 2
    bgRadius := CD_bgRadius
    ringX := cx - ringRadius
    ringY := cy - ringRadius
    bgX := cx - bgRadius
    bgY := cy - bgRadius
    bgD := bgRadius * 2

    Gdip_GraphicsClear(CD_G, 0x00000000)
    Gdip_FillEllipse(CD_G, CD_pBrushBg, bgX, bgY, bgD, bgD)
    Gdip_DrawArc(CD_G, CD_pPenTrack, ringX, ringY, ringD, ringD, -90, 360)
    if (sweepAngle > 0.5)
        Gdip_DrawArc(CD_G, CD_pPenFill, ringX, ringY, ringD, ringD, -90, sweepAngle)

    txtR := CD_fontSize * 1.8
    mRC := Buffer(16)
    CreateRectF(&mRC, cx - txtR, cy - txtR, txtR * 2, txtR * 2)
    Gdip_DrawString(CD_G, String(displayNum), CD_hFont, CD_hFormat, CD_pBrushTxt, &mRC)

    UpdateLayeredWindow(CD_hwnd, CD_hdc, Round(CD_x), Round(CD_y), CD_boxSize, CD_boxSize)
}

CDDestroy() {
    global CD_hdc, CD_obm, CD_hbm, CD_G
    global CD_pBrushBg, CD_pPenTrack, CD_pPenFill, CD_pBrushTxt
    global CD_hFont, CD_hFormat, CD_hFamily, CD_pToken
    global RecordCountdownGui

    if (IsSet(CD_hdc) && CD_hdc) {
        try SelectObject(CD_hdc, CD_obm)
        try DeleteObject(CD_hbm)
        try DeleteDC(CD_hdc)
    }
    if (IsSet(CD_G) && CD_G)
        try Gdip_DeleteGraphics(CD_G)
    if (IsSet(CD_pBrushBg) && CD_pBrushBg)
        try Gdip_DeleteBrush(CD_pBrushBg)
    if (IsSet(CD_pPenTrack) && CD_pPenTrack)
        try Gdip_DeletePen(CD_pPenTrack)
    if (IsSet(CD_pPenFill) && CD_pPenFill)
        try Gdip_DeletePen(CD_pPenFill)
    if (IsSet(CD_pBrushTxt) && CD_pBrushTxt)
        try Gdip_DeleteBrush(CD_pBrushTxt)
    if (IsSet(CD_hFont) && CD_hFont)
        try Gdip_DeleteFont(CD_hFont)
    if (IsSet(CD_hFormat) && CD_hFormat)
        try Gdip_DeleteStringFormat(CD_hFormat)
    if (IsSet(CD_hFamily) && CD_hFamily)
        try Gdip_DeleteFontFamily(CD_hFamily)
    if (IsSet(CD_pToken) && CD_pToken)
        try Gdip_Shutdown(CD_pToken)
    if (IsSet(RecordCountdownGui) && RecordCountdownGui != "") {
        try RecordCountdownGui.Destroy()
        RecordCountdownGui := ""
    }
}

HideRecordCountdown() {
    global CD_canceled, RecordCountdownGui
    if (!IsSet(RecordCountdownGui) || RecordCountdownGui == "")
        return
    CD_canceled := true
}

DoStartRecord(isHotkey) {
    OnStartRecordInner(isHotkey)
}

OnStartRecordInner(*) {
    global ToolCheckInfo, MySoftData

    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY
    ToolCheckInfo.RecordMacroStr := ""
    ToolCheckInfo.RecordLastTime := A_TickCount

    MySoftData.IsTogStartRecord := true
    RI_StartRecord(mouseX, mouseY)
    if (ToolCheckInfo.RecordJoy)
        RecordJoy()
    ShowRecordBorder()
}

OnWMInput_Raw(wParam, lParam, msg, hwnd) {
    global RI_isActive, RI_accumX, RI_accumY, RI_hwnd, RI_headerSize, RI_lastEmitX, RI_lastEmitY, RI_lastSnapX, RI_lastSnapY
    if (!RI_isActive || hwnd != RI_hwnd)
        return

    rawInput := Buffer(64, 0)
    size := 64
    ret := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", rawInput.Ptr, "UIntP", &size, "UInt", RI_headerSize)
    if (ret <= 0)
        return

    dwType := NumGet(rawInput, 0, "UInt")

    if (dwType == 0) {
        if (A_PtrSize == 8) {
            x := NumGet(rawInput, 36, "Int")
            y := NumGet(rawInput, 40, "Int")
            btnFlags := NumGet(rawInput, 28, "UShort")
            buttonData := NumGet(rawInput, 30, "Short")
        } else {
            x := NumGet(rawInput, 32, "Int")
            y := NumGet(rawInput, 36, "Int")
            btnFlags := NumGet(rawInput, 24, "UShort")
            buttonData := NumGet(rawInput, 26, "Short")
        }

        if (x != 0 || y != 0) {
            RI_accumX += x
            RI_accumY += y
            if (ToolCheckInfo.RecordMouse && ToolCheckInfo.RecordMouseTrail == 3) {
                RI_eventQueue.Push(Map("type", "move", "ax", x, "ay", y, "t", A_TickCount))
            }
        }

        static btnMap := Map(
            0x0001, ["LButton", GetLang("按下")],
            0x0002, ["LButton", GetLang("松开")],
            0x0004, ["RButton", GetLang("按下")],
            0x0008, ["RButton", GetLang("松开")],
            0x0010, ["MButton", GetLang("按下")],
            0x0020, ["MButton", GetLang("松开")],
            0x0040, ["XButton1", GetLang("按下")],
            0x0080, ["XButton1", GetLang("松开")],
            0x0100, ["XButton2", GetLang("按下")],
            0x0200, ["XButton2", GetLang("松开")]
        )
        if (btnFlags != 0 && ToolCheckInfo.RecordMouse) {
            CoordMode("Mouse", "Screen")
            MouseGetPos &snapX, &snapY
            if (snapX != RI_lastSnapX || snapY != RI_lastSnapY) {
                RI_lastSnapX := snapX
                RI_lastSnapY := snapY
                RI_eventQueue.Push(Map("type", "snap", "ax", snapX, "ay", snapY, "t", A_TickCount))
            }
            if (btnMap.Has(btnFlags)) {
                btnInfo := btnMap[btnFlags]
                RI_eventQueue.Push(Map("type", "mouse", "name", btnInfo[1], "state", btnInfo[2], "t", A_TickCount))
            }
            else if (btnFlags & 0x0400) {
                wheelName := buttonData > 0 ? "WheelUp" : "WheelDown"
                RI_eventQueue.Push(Map("type", "mouse", "name", wheelName, "state", GetLang("按下"), "wheelValue", buttonData, "t", A_TickCount))
            }
            else if (btnFlags & 0x0800) {
                wheelName := buttonData > 0 ? "WheelRight" : "WheelLeft"
                RI_eventQueue.Push(Map("type", "mouse", "name", wheelName, "state", GetLang("按下"), "wheelValue", buttonData, "t", A_TickCount))
            }
            else {
                RI_eventQueue.Push(Map("type", "mouse", "name", "Btn" Format("{:04X}", btnFlags), "state", GetLang("按下"), "t", A_TickCount))
            }
        }
    }
    else if (dwType == 1 && ToolCheckInfo.RecordKeyboard) {
        CoordMode("Mouse", "Screen")
        MouseGetPos &snapX, &snapY
        if (snapX != RI_lastSnapX || snapY != RI_lastSnapY) {
            RI_lastSnapX := snapX
            RI_lastSnapY := snapY
            RI_eventQueue.Push(Map("type", "snap", "ax", snapX, "ay", snapY, "t", A_TickCount))
        }
        vKey := 0
        flags := 0
        if (A_PtrSize == 8) {
            makeCode := NumGet(rawInput, 24, "UShort")
            flags := NumGet(rawInput, 26, "UShort")
            vKey := NumGet(rawInput, 30, "UShort")
        } else {
            makeCode := NumGet(rawInput, 16, "UShort")
            flags := NumGet(rawInput, 18, "UShort")
            vKey := NumGet(rawInput, 22, "UShort")
        }

        vkName := GetKeyName("vk" Format("{:02X}", vKey))
        if (!vkName)
            vkName := "vk" Format("{:02X}", vKey)

        state := (flags & 1) ? GetLang("松开") : GetLang("按下")
        RI_eventQueue.Push(Map("type", "key", "name", vkName, "state", state, "t", A_TickCount))
    }
}

RecordConsumeRI() {
    global RI_eventQueue

    if (RI_eventQueue.Length > 1) {
        loop RI_eventQueue.Length - 1 {
            i := A_Index
            j := i + 1
            while (j > 1 && RI_eventQueue[j]["t"] < RI_eventQueue[j - 1]["t"]) {
                temp := RI_eventQueue[j]
                RI_eventQueue[j] := RI_eventQueue[j - 1]
                RI_eventQueue[j - 1] := temp
                j--
            }
        }
    }

    while (RI_eventQueue.Length > 0) {
        item := RI_eventQueue.RemoveAt(1)
        if (item["type"] == "move" || item["type"] == "snap") {
            span := item["t"] - ToolCheckInfo.RecordLastTime
            ToolCheckInfo.RecordLastTime := item["t"]
            suffix := (item["type"] == "move") ? "_2" : ""
            ToolCheckInfo.RecordMacroStr .= GetLang("间隔") "_" span ","
            ToolCheckInfo.RecordMacroStr .= GetLang("移动") "_" item["ax"] "_" item["ay"] suffix ","
        }
        else {
            isDown := item["state"] == GetLang("按下")
            OnRecordAddMacroStr(item["name"], isDown, item["t"])
        }
    }
}

OnRecordAddMacroStr(keyName, isDown, eventTime?) {
    if (keyName == "WheelUp" || keyName == "WheelDown" || keyName == "WheelLeft" || keyName == "WheelRight") {
        if (ToolCheckInfo.RecordMouse && isDown) {
            curTime := IsSet(eventTime) ? eventTime : A_TickCount
        span := curTime - ToolCheckInfo.RecordLastTime
        ToolCheckInfo.RecordLastTime := curTime
        ToolCheckInfo.RecordMacroStr .= GetLang("间隔") "_" span ","
        ToolCheckInfo.RecordMacroStr .= GetLang("按键") "_" keyName "_" GetLang("按下") ","
        }
        return
    }
    else if (isDown) {
        if (!ToolCheckInfo.RecordHoldMuti && ToolCheckInfo.RecordHoldKeyMap.Has(keyName))
            return
        ToolCheckInfo.RecordHoldKeyMap[keyName] := true
    }
    else if (ToolCheckInfo.RecordHoldKeyMap.Has(keyName)) {
        ToolCheckInfo.RecordHoldKeyMap.Delete(keyName)
    }

    curTime := IsSet(eventTime) ? eventTime : A_TickCount
    span := curTime - ToolCheckInfo.RecordLastTime
    keySymbol := isDown ? GetLang("按下") : GetLang("松开")
    ToolCheckInfo.RecordLastTime := curTime
    IsJoy := InStr(keyName, "Joy")
    IsMouse := keyName == "LButton" || keyName == "RButton" || keyName == "MButton" || keyName == "XButton1" || keyName == "XButton2"
    IsKeyboard := !IsMouse && !IsJoy

    if (IsJoy || (IsKeyboard && ToolCheckInfo.RecordKeyboard)) {
        keyName := keyName == "," ? GetLang("逗号") : keyName
        ToolCheckInfo.RecordMacroStr .= Format("{}_{},", GetLang("间隔"), span)
        ToolCheckInfo.RecordMacroStr .= Format("{}_{}_{},", GetLang("按键"), keyName, keySymbol)
    }

    if (IsMouse && ToolCheckInfo.RecordMouse) {
        ToolCheckInfo.RecordMacroStr .= GetLang("间隔") "_" span ","
        ToolCheckInfo.RecordMacroStr .= GetLang("按键") "_" keyName "_" keySymbol ","
    }
}

OnFinishRecordMacro() {
    global RI_isActive
    RI_isActive := false
    if (ToolCheckInfo.RecordAutoLoosen) {
        for Key, Value in ToolCheckInfo.RecordHoldKeyMap {
            keyName := Key == "," ? GetLang("逗号") : Key
            ToolCheckInfo.RecordMacroStr .= GetLang("按键") "_" keyName "_" GetLang("松开") ","
        }
    }
    macroStr := Trim(ToolCheckInfo.RecordMacroStr, ",")
    macroStr := SimpleRecordMacroStr(macroStr)
    macroStr := DiscardRecordTriggerKey(macroStr, true)
    macroStr := DiscardRecordTriggerKey(macroStr, false)
    macroStr := FilterMoveCmd(macroStr)

    if (MySoftData.MacroEditGui != "") {
        MySoftData.MacroEditGui.InitTreeView(macroStr)
        MySoftData.MacroEditGui.InitMacroText(MacroStr)
    }
    macroLineStr := StrReplace(macroStr, ",", "`n")
    ToolCheckInfo.ToolTextCtrl.Value := macroLineStr
    SetClipboard(macroLineStr)
    MsgBox(GetLang("录制指令已复制到剪切板！`n`n请在【按键宏】页签下粘贴宏，`n配置触发键后，即可通过按键回放指令。"), GetLang("录制完成提示"))
}

FilterMoveCmd(macroStr) {
    if (macroStr == "")
        return ""

    trailMode := ToolCheckInfo.RecordMouseTrail
    moveKey := GetLang("移动")
    spanKey := GetLang("间隔")
    CmdArr := SplitMacro(macroStr)

    filteredArr := []
    loop CmdArr.Length {
        cmd := CmdArr[A_Index]
        paramArr := SplitCommand(cmd)
        isZeroSpan := (paramArr[1] == spanKey && paramArr[2] == "0")

        if (trailMode == 0) {
            if (isZeroSpan || paramArr[1] == moveKey)
                continue
            filteredArr.Push(cmd)
        }
        else if (trailMode == 3) {
            isSnapMove := (paramArr[1] == moveKey && !(paramArr.Length >= 4 && paramArr[paramArr.Length] == "2"))
            if (!isZeroSpan && !isSnapMove)
                filteredArr.Push(cmd)
        }
        else {
            if (!isZeroSpan)
                filteredArr.Push(cmd)
        }
    }

    if (trailMode == 0)
        return CleanOrphanSpan(filteredArr)

    if (trailMode == 1)
        return FillMoveSpeed(filteredArr, ToolCheckInfo.RecordMouseTrailSpeed)

    if (trailMode == 3)
        return CompressFullMoves(filteredArr)

    if (trailMode == 2)
        return CleanOrphanSpan(ConvertToRelative(filteredArr, ToolCheckInfo.RecordMouseTrailSpeed))

    return macroStr
}

CompressFullMoves(CmdArr) {
    moveKey := GetLang("移动")
    resultArr := []
    accX := 0
    accY := 0
    hasAcc := false

    loop CmdArr.Length {
        cmd := CmdArr[A_Index]
        paramArr := SplitCommand(cmd)
        if (paramArr[1] == moveKey && paramArr.Length >= 4 && paramArr[paramArr.Length] == "2") {
            accX += Integer(paramArr[2])
            accY += Integer(paramArr[3])
            hasAcc := true
        }
        else {
            if (hasAcc) {
                resultArr.Push(moveKey "_" accX "_" accY "_100_2")
                accX := 0
                accY := 0
                hasAcc := false
            }
            resultArr.Push(cmd)
        }
    }

    if (hasAcc)
        resultArr.Push(moveKey "_" accX "_" accY "_100_2")

    return CleanOrphanSpan(resultArr)
}

FillMoveSpeed(CmdArr, spd) {
    moveKey := GetLang("移动")
    resultArr := []
    loop CmdArr.Length {
        cmd := CmdArr[A_Index]
        paramArr := SplitCommand(cmd)
        if (paramArr[1] == moveKey) {
            if (paramArr.Length >= 4 && paramArr[paramArr.Length] == "2") {
                resultArr.Push(moveKey "_" paramArr[2] "_" paramArr[3] "_" spd "_2")
            }
            else if (paramArr.Length >= 3) {
                resultArr.Push(moveKey "_" paramArr[2] "_" paramArr[3] "_" spd)
            }
            else {
                resultArr.Push(cmd)
            }
        }
        else {
            resultArr.Push(cmd)
        }
    }
    return GetMacroStrByCmdArr(resultArr)
}

ConvertToRelative(CmdArr, spd?) {
    moveKey := GetLang("移动")
    lastX := 0
    lastY := 0
    isFirst := true
    resultArr := []
    loop CmdArr.Length {
        cmd := CmdArr[A_Index]
        paramArr := SplitCommand(cmd)
        if (paramArr[1] == moveKey) {
            if (isFirst) {
                isFirst := false
                lastX := Integer(paramArr[2])
                lastY := Integer(paramArr[3])
                continue
            }
            ax := Integer(paramArr[2])
            ay := Integer(paramArr[3])
            dx := ax - lastX
            dy := ay - lastY
            useSpd := IsSet(spd) ? spd : 95
            resultArr.Push(moveKey "_" dx "_" dy "_" useSpd "_1")
            lastX := ax
            lastY := ay
        }
        else {
            resultArr.Push(cmd)
        }
    }
    return resultArr
}

CleanOrphanSpan(CmdArr) {
    spanKey := GetLang("间隔")
    cleanArr := []
    pendingSpan := 0
    loop CmdArr.Length {
        cmd := CmdArr[A_Index]
        paramArr := SplitCommand(cmd)
        if (paramArr[1] == spanKey) {
            pendingSpan += Integer(paramArr[2])
        }
        else {
            if (pendingSpan > 0) {
                cleanArr.Push(spanKey "_" pendingSpan)
                pendingSpan := 0
            }
            cleanArr.Push(cmd)
        }
    }
    if (pendingSpan > 0)
        cleanArr.Push(spanKey "_" pendingSpan)

    return GetMacroStrByCmdArr(cleanArr)
}

OnHotToolRecordMacro(isHotkey, *) {
    action := OnToolRecordMacro.Bind(isHotkey)
    SetTimer(action, -1)
}

OnToolRecordMacro(isHotkey, *) {
    global ToolCheckInfo, MySoftData

    if (isHotkey) {
        LastState := ToolCheckInfo.ToolCheckRecordMacroCtrl.Value
        ToolCheckInfo.ToolCheckRecordMacroCtrl.Value := !LastState
    }
    state := ToolCheckInfo.ToolCheckRecordMacroCtrl.Value

    if (MySoftData.MacroEditGui != "") {
        MySoftData.RecordToggleCon.Value := state
    }

    if (state) {
        ShowRecordCountdown(DoStartRecord.Bind(isHotkey))
    }
    else {
        MySoftData.IsTogEndRecord := isHotkey == ""
        global RI_isActive, RI_eventQueue, CD_canceled
        wasCountingDown := IsSet(CD_canceled) && !CD_canceled && (IsSet(RecordCountdownGui) && RecordCountdownGui != "")
        RI_isActive := false
        RecordConsumeRI()
        RI_eventQueue := []
        ToolCheckInfo.ToolCheckRecordMacroCtrl.Value := false
        HideRecordCountdown()
        HideRecordBorder()
        if (!wasCountingDown) {
            OnFinishRecordMacro()
        } else {
            ToolCheckInfo.RecordMacroStr := ""
            ToolCheckInfo.RecordHoldKeyMap := Map()
            if (MySoftData.MacroEditGui != "") {
                MySoftData.MacroEditGui.InitTreeView("")
                MySoftData.MacroEditGui.InitMacroText("")
            }
            ToolCheckInfo.ToolTextCtrl.Value := ""
        }
    }
}

OnForceEndRecord() {
    global RI_isActive, RI_eventQueue, CD_canceled
    wasCountingDown := IsSet(CD_canceled) && !CD_canceled && (IsSet(RecordCountdownGui) && RecordCountdownGui != "")
    isRecording := RI_isActive

    if (wasCountingDown) {
        HideRecordCountdown()
        ToolCheckInfo.RecordMacroStr := ""
        ToolCheckInfo.RecordHoldKeyMap := Map()
        if (MySoftData.MacroEditGui != "") {
            MySoftData.MacroEditGui.InitTreeView("")
            MySoftData.MacroEditGui.InitMacroText("")
        }
        ToolCheckInfo.ToolTextCtrl.Value := ""
        if (MySoftData.MacroEditGui != "")
            MySoftData.RecordToggleCon.Value := false
        return
    }

    if (!isRecording)
        return

    RI_isActive := false
    RecordConsumeRI()
    RI_eventQueue := []
    HideRecordCountdown()
    HideRecordBorder()
    OnFinishRecordMacro()
}

ShowRecordBorder() {
    global RecordBorder, RecordBorder_frame

    if (!ToolCheckInfo.RecordShowBorder)
        return
    if (IsSet(RecordBorder) && RecordBorder != "")
        return

    MonitorGetWorkArea(, &waLeft, &waTop, &waRight, &waBottom)
    RecordBorder := RecordHighlightOutline(waLeft, waTop, waRight, waBottom, 3, "ff3333", 200)
    RecordBorder.Show(waLeft, waTop, waRight, waBottom)

    RecordBorder_frame := 0
    SetTimer(DrawRecordBorderFrame, 30)
}

DrawRecordBorderFrame() {
    global RecordBorder, RecordBorder_frame

    if (!IsSet(RecordBorder) || RecordBorder == "") {
        SetTimer(DrawRecordBorderFrame, 0)
        return
    }

    f := Mod(RecordBorder_frame, 150)
    RecordBorder_frame++
    pulse := (Sin(f * 0.12) + 1) / 2
    alpha := Round(160 + 95 * pulse)
    RecordBorder.SetAlpha(alpha)
}

HideRecordBorder() {
    global RecordBorder

    SetTimer(DrawRecordBorderFrame, 0)
    if (IsSet(RecordBorder) && RecordBorder != "") {
        try RecordBorder.Destroy()
    }
    RecordBorder := ""
    RecordBorder_frame := 0
}
