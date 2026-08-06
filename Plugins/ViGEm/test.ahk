#Requires AutoHotkey v2.0

; ============================================================
;  手柄路径诊断 & 映射验证脚本
;  检测 DirectInput / XInput 路径 + 验证映射表
; ============================================================

#Include XInput.ahk
XInput_Init()

outputFile := A_ScriptDir "\diagnostic_result.txt"
result := ""

Log(msg) {
    global result
    result .= msg "`n"
}

; ========== 手柄类型检测（与 DataClass.Ahk 同逻辑） ==========
; 逻辑：XInput 能检测到 → Xbox，XInput 检测不到但有 DI 设备 → PS5
DetectControllerType() {
    diName := ""
    diIndex := 0
    loop 10 {
        name := GetKeyState(A_Index "JoyName")
        if (name != "") {
            diName := name
            diIndex := A_Index
            break
        }
    }
    if (diName == "")
        return Map("type", "", "name", "", "diIndex", 0)

    ; XInput 检测：成功 → Xbox 兼容手柄
    loop 4 {
        try {
            xiState := Buffer(16)
            err := DllCall("XInput1_4\XInputGetState", "uint", A_Index - 1, "ptr", xiState)
            if (!err)
                return Map("type", "Xbox", "name", diName, "diIndex", diIndex)
        }
    }

    ; XInput 检测失败但有 DI 手柄 → PS5（目前只考虑这两种手柄）
    return Map("type", "PS5", "name", diName, "diIndex", diIndex)
}

ctrlInfo := DetectControllerType()

; ========== 映射表定义 ==========
xboxMap := Map(
    "JoyA","Joy1", "JoyB","Joy2", "JoyX","Joy3", "JoyY","Joy4",
    "JoyLB","Joy5", "JoyRB","Joy6", "JoyLT","JoyZMin", "JoyRT","JoyZMax",
    "JoyLS","Joy9", "JoyRS","Joy10", "JoyBack","Joy7", "JoyStart","Joy8",
    "JoyDpadUp","JoyPOV_0", "JoyDpadRight","JoyPOV_9000",
    "JoyDpadDown","JoyPOV_18000", "JoyDpadLeft","JoyPOV_27000"
)

ps5Map := Map(
    "JoyA","Joy1",   ; □ Square
    "JoyB","Joy2",   ; × Cross
    "JoyX","Joy3",   ; ○ Circle
    "JoyY","Joy4",   ; △ Triangle
    "JoyLB","Joy5",  ; L1
    "JoyRB","Joy6",  ; R1
    "JoyLT","Joy7",  ; L2 (数字按钮)
    "JoyRT","Joy8",  ; R2 (数字按钮)
    "JoyLS","Joy11",  ; 左摇杆按下 (L3)
    "JoyRS","Joy12", ; 右摇杆按下 (R3)
    "JoyBack","Joy9", "JoyStart","Joy10", ; PS5 无 Back/Start，对应 Create/Options
    "JoyPad","Joy14",    ; 触摸板按压
    "JoyHome","Joy13",   ; PS 键 (Home)
    "JoyDpadUp","JoyPOV_0", "JoyDpadRight","JoyPOV_9000",
    "JoyDpadDown","JoyPOV_18000", "JoyDpadLeft","JoyPOV_27000"
)

activeMap := (ctrlInfo["type"] == "PS5") ? ps5Map : xboxMap

; ========== 1. 手柄类型检测 ==========
Log("========== 1. 手柄类型检测 ==========")
Log("  类型: " ctrlInfo["type"])
Log("  DI 名称: " ctrlInfo["name"])
Log("  DI 索引: " ctrlInfo["diIndex"])
Log("  使用映射: " (ctrlInfo["type"] == "PS5" ? "PS5" : ctrlInfo["type"] == "Xbox" ? "Xbox" : "无"))

Log("")

; ========== 2. DirectInput 路径检测 ==========
Log("========== 2. DirectInput 路径 ==========")
foundDI := []
loop 10 {
    idx := A_Index
    name := GetKeyState(idx "JoyName")
    if (name != "") {
        foundDI.Push(idx)
        info := GetKeyState(idx "JoyInfo")
        Log("  [" idx "] " name "  能力: " info)

        for axis in ["JoyX", "JoyY", "JoyZ", "JoyR", "JoyU", "JoyV"] {
            val := GetKeyState(idx axis)
            if (val != "")
                Log("      " axis " = " val)
        }
        if InStr(info, "P") {
            pov := GetKeyState(idx "JoyPOV")
            Log("      JoyPOV = " pov)
        }
    }
}
if (foundDI.Length == 0)
    Log("  无 DI 手柄")

Log("")

; ========== 3. XInput 路径检测 ==========
Log("========== 3. XInput 路径 ==========")
foundXI := []
loop 4 {
    idx := A_Index - 1
    try {
        State := XInput_GetState(idx)
        if (State != 0) {
            foundXI.Push(idx)
            Log("  [XInput-" idx "] 已连接  LT:" State.bLeftTrigger " RT:" State.bRightTrigger
                . " Btns:" Format("{:04X}", State.wButtons))
        }
    } catch {
    }
}
if (foundXI.Length == 0)
    Log("  无 XInput 手柄")

Log("")

; ========== 4. 当前激活的映射表 ==========
Log("========== 4. 当前激活的映射表 (" ctrlInfo["type"] ") ==========")
guiNames := ctrlInfo["type"] == "PS5"
    ? ["JoyA(□)", "JoyB(×)", "JoyX(○)", "JoyY(△)",
       "JoyLB(L1)", "JoyRB(R1)", "JoyLT(L2)", "JoyRT(R2)",
       "JoyLS(L3)", "JoyRS(R3)", "JoyBack(Crt)", "JoyStart(Opt)",
       "JoyPad(触板)", "JoyHome(PS)",
       "JoyDpadUp", "JoyDpadRight", "JoyDpadDown", "JoyDpadLeft"]
    : ["JoyA(A)", "JoyB(B)", "JoyX(X)", "JoyY(Y)",
       "JoyLB(LB)", "JoyRB(RB)", "JoyLT(LT)", "JoyRT(RT)",
       "JoyLS(LS)", "JoyRS(RS)", "JoyBack(Back)", "JoyStart(Start)",
       "JoyDpadUp", "JoyDpadRight", "JoyDpadDown", "JoyDpadLeft"]
for i, guiName in guiNames {
    key := StrSplit(guiName, "(")[1]
    ahkKey := activeMap.Has(key) ? activeMap[key] : "(未映射)"
    Log("  " RPad(guiName, 22) " → " ahkKey)
}

Log("")
Log("========== 5. 结论 ==========")
if (ctrlInfo["type"] == "PS5")
    Log("  PS5 手柄（非 XInput）！使用 PS5 映射表。")
else if (ctrlInfo["type"] == "Xbox")
    Log("  Xbox 兼容手柄！使用 Xbox 映射表。")
else
    Log("  未检测到手柄！")

FileAppend(result, outputFile, "UTF-8")
MsgBox(result, "手柄诊断结果")

; ========== 实时监控 GUI ==========
MonitorGui := Gui("+Resize +MinSize470x580", "手柄实时监控")

; 映射表用 Checkbox，每个按键一行
; 布局：4个Checkbox一行，每行显示4个按键
MonitorGui.SetFont("s9", "微软雅黑")
MonitorGui.AddText("x10 y10 w450 h20", "类型: " ctrlInfo["type"] " | 设备: " ctrlInfo["name"] " | 映射: " (ctrlInfo["type"] == "PS5" ? "PS5 (□×○△)" : ctrlInfo["type"] == "Xbox" ? "Xbox" : "无"))
MonitorGui.AddText("x10 y32 w450 h18 cGray", "勾选 = 当前按下的按键")

; 12个按钮的 Checkbox — 根据手柄类型分开显示
isPS5 := ctrlInfo["type"] == "PS5"
btnList := isPS5
    ? [["JoyA","□"], ["JoyB","×"], ["JoyX","○"], ["JoyY","△"],
       ["JoyLB","L1"], ["JoyRB","R1"], ["JoyLT","L2"], ["JoyRT","R2"],
       ["JoyLS","L3"], ["JoyRS","R3"], ["JoyBack","Crt"], ["JoyStart","Opt"],
       ["JoyPad","触板"], ["JoyHome","PS"]]
    : [["JoyA","A"], ["JoyB","B"], ["JoyX","X"], ["JoyY","Y"],
       ["JoyLB","LB"], ["JoyRB","RB"], ["JoyLT","LT"], ["JoyRT","RT"],
       ["JoyLS","LS"], ["JoyRS","RS"], ["JoyBack","Back"], ["JoyStart","Start"]]
joyCheckboxMap := Map()
posX := 15, posY := 55
for i, e in btnList {
    key := e[1], label := e[2]
    ahk := activeMap.Has(key) ? activeMap[key] : "?"
    cb := MonitorGui.AddCheckbox("x" posX " y" posY " w85 h22 Disabled", label " → " ahk)
    joyCheckboxMap.Set(key, cb)
    posX += 90
    if (Mod(i, 4) == 0) {
        posX := 15
        posY += 28
    }
}

MonitorGui.AddText("x15 y" (posY + 38) " w450 h20", "--- 轴状态 ---")
axisStatic := MonitorGui.AddText("x15 y" (posY + 60) " w450 h60", "")
diBtnStatic := MonitorGui.AddText("x15 y" (posY + 123) " w450 h80", "")
xiStatic := MonitorGui.AddText("x15 y" (posY + 208) " w450 h60 cGray", "")
MonitorGui.AddText("x15 y" (posY + 273) " w450 h18 cGray", "F5 刷新 | End 退出")

MonitorGui.Show("w470 h" (posY + 360))

; 上次保存的按钮状态，用于减少刷新
lastBtnState := Map()
for e in btnList
    lastBtnState.Set(e[1], 0)

SetTimer LiveMonitor, 200
LiveMonitor() {
    global MonitorGui, joyCheckboxMap, axisStatic, diBtnStatic, xiStatic, activeMap, lastBtnState, foundXI

    ; ---- 更新按钮 Checkbox 状态（只改变化的值） ----
    diIndex := ctrlInfo["diIndex"]
    if (diIndex > 0) {
        for key, cb in joyCheckboxMap {
            ahkKey := activeMap.Has(key) ? activeMap[key] : ""
            if (ahkKey == "") {
                cb.Value := 0
                continue
            }
            ; 处理 JoyZMin/JoyZMax 等轴类映射
            pressed := 0
            if (InStr(ahkKey, "ZMin") || InStr(ahkKey, "ZMax")) {
                ; XInput 手柄的 LT/RT 通过 XInput 读取，DI 轴不可靠
                isLT := InStr(ahkKey, "ZMin")
                for xiIdx in foundXI {
                    try xiState := XInput_GetState(xiIdx)
                    if (xiState != 0) {
                        pressed := isLT ? xiState.bLeftTrigger > 30 : xiState.bRightTrigger > 30
                        if pressed
                            break
                    }
                }
            } else if (InStr(ahkKey, "POV"))
                pressed := 0  ; 方向键通过轴按钮整体显示
            else
                pressed := GetKeyState(diIndex ahkKey, "P") ? 1 : 0

            if (pressed != lastBtnState[key]) {
                cb.Value := pressed
                lastBtnState[key] := pressed
            }
        }
    }

    ; ---- 更新轴状态 ----
    if (diIndex > 0) {
        jx := GetKeyState(diIndex "JoyX"), jy := GetKeyState(diIndex "JoyY")
        jz := GetKeyState(diIndex "JoyZ"), jr := GetKeyState(diIndex "JoyR")
        ju := GetKeyState(diIndex "JoyU"), jv := GetKeyState(diIndex "JoyV")
        axisTxt := "X=" Format("{:5.1f}", jx) " Y=" Format("{:5.1f}", jy) " Z=" Format("{:5.1f}", jz)
            . " R=" Format("{:5.1f}", jr) " U=" Format("{:5.1f}", ju) " V=" Format("{:5.1f}", jv)

        info := GetKeyState(diIndex "JoyInfo")
        if InStr(info, "P") {
            pov := GetKeyState(diIndex "JoyPOV")
            axisTxt .= "  POV=" pov
        }
        axisStatic.Value := axisTxt

        ; ---- 按钮编号状态 ----
        btnTxt := "Btn: "
        loop 16 {
            pressed := GetKeyState(diIndex "Joy" A_Index)
            btnTxt .= (pressed ? "[" : " ") Format("{:2d}", A_Index) (pressed ? "]" : " ")
            if (Mod(A_Index, 8) == 0)
                btnTxt .= "`n      "
        }
        diBtnStatic.Value := btnTxt
    } else {
        axisStatic.Value := "(无 DI 数据)"
        diBtnStatic.Value := ""
    }

    ; ---- XI 状态 ----
    xiTxt := ""
    loop 4 {
        try {
            s := XInput_GetState(A_Index - 1)
            if (s != 0)
                xiTxt .= "LT=" s.bLeftTrigger " RT=" s.bRightTrigger " Btns=" Format("{:04X}", s.wButtons)
        }
    }
    xiStatic.Value := (xiTxt != "" ? xiTxt : "(无 XInput)")
}

RPad(s, len) {
    while (StrLen(s) < len)
        s .= " "
    return s
}

F5::Reload()
Esc::ExitApp()
