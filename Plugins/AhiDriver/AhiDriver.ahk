; AHI Driver Wrapper
; Description: 封装 AutoHotInterception 为通用输入驱动（类似 IbInputSimulator）
; Version: 1.4 (支持键盘+鼠标智能识别)
; 基于 evilC/AutoHotInterception 库

#Requires AutoHotkey v2.0
#Include AutoHotInterception.ahk

global AHI_Driver := ""
global AHI_KeyboardId := 1   ; 默认使用第一个键盘设备
global AHI_MouseId := 11     ; 默认使用第一个鼠标设备

; 诊断日志（写入 Log\MouseMoveDebug.log，与 MouseMoveUtil 共用）
_AHI_Log(tag, msg) {
    try {
        logPath := (A_WorkingDir "\Log\MouseMoveDebug.log")
        FileAppend(FormatTime(, "HH:mm:ss") "." SubStr(A_TickCount, -2) " [" tag "] " msg "`n"
            , logPath, "UTF-8")
    }
}

; 鼠标键映射表（名称 → AHI 按钮编号）
; 基于 Interception API: interception.h
; BUTTON_1=左键(0), BUTTON_2=右键(1), BUTTON_3=中键(2), BUTTON_4=X1(3), BUTTON_5=X2(4)
; 参考: https://github.com/oblitum/Interception/blob/master/library/interception.h
global AHI_MouseBtnMap := Map(
    "LButton", 0,    ; 左键 → BUTTON_1 (INTERCEPTION_MOUSE_LEFT_BUTTON_DOWN = 0x001)
    "RButton", 1,    ; 右键 → BUTTON_2 (INTERCEPTION_MOUSE_RIGHT_BUTTON_DOWN = 0x004)
    "MButton", 2,    ; 中键 → BUTTON_3 (INTERCEPTION_MOUSE_MIDDLE_BUTTON_DOWN = 0x010)
    "XButton1", 3,   ; 侧键1 → BUTTON_4 (INTERCEPTION_MOUSE_BUTTON_4_DOWN = 0x040)
    "XButton2", 4    ; 侧键2 → BUTTON_5 (INTERCEPTION_MOUSE_BUTTON_5_DOWN = 0x100)
)

; 滚轮映射表（名称 → [AHI 按钮编号, state]）
; AHI 的滚轮不是"移动"，而是通过按钮事件发送：
;   button 5 = 垂直滚轮，6 = 横向滚轮
;   state 1 = 上/右，-1 = 下/左
; 参考: https://github.com/evilC/AutoHotInterception
global AHI_WheelMap := Map(
    "WheelUp",    [5, 1],
    "WheelDown",  [5, -1],
    "WheelRight", [6, 1],
    "WheelLeft",  [6, -1]
)

; AHI 安装目录（含 install.ps1 / 安装卸载.bat）
GetAHIPluginDir() {
    if (IsSet(AHIPluginDir) && DirExist(AHIPluginDir))
        return AHIPluginDir
    cand := A_WorkingDir "\Plugins\AhiDriver\installer"
    if DirExist(cand)
        return cand
    cand := A_WorkingDir "\..\Plugins\AhiDriver\installer"
    if DirExist(cand)
        return cand
    return A_WorkingDir "\Plugins\AhiDriver\installer"
}

; 读取文件 ProductName（用于判断 keyboard.sys / mouse.sys 是否为 Interception）
GetFileProductName(path) {
    if !FileExist(path)
        return ""
    size := DllCall("version\GetFileVersionInfoSizeW", "wstr", path, "uint*", 0)
    if !size
        return ""
    buf := Buffer(size)
    if !DllCall("version\GetFileVersionInfoW", "wstr", path, "uint", 0, "uint", size, "ptr", buf)
        return ""
    if !DllCall("version\VerQueryValueW", "ptr", buf, "wstr", "\VarFileInfo\Translation", "ptr*", &pTrans := 0, "uint*", &len := 0) || !pTrans
        return ""
    lang := Format("{:04X}{:04X}", NumGet(pTrans, 0, "UShort"), NumGet(pTrans, 2, "UShort"))
    if !DllCall("version\VerQueryValueW", "ptr", buf, "wstr", "\StringFileInfo\" lang "\ProductName", "ptr*", &pName := 0, "uint*", &nLen := 0) || !pName
        return ""
    return StrGet(pName, "UTF-16")
}

; 是否已安装完整 Interception 驱动（文件 + UpperFilters 钩子）
IsInterceptionInstalled() {
    kbdSys := A_WinDir "\System32\drivers\keyboard.sys"
    mouSys := A_WinDir "\System32\drivers\mouse.sys"
    if (GetFileProductName(kbdSys) != "Interception" || GetFileProductName(mouSys) != "Interception")
        return false

    kbdClass := "{4D36E96B-E325-11CE-BFC1-08002BE10318}"
    mouClass := "{4D36E96F-E325-11CE-BFC1-08002BE10318}"
    try {
        kbdFilters := RegRead("HKLM\SYSTEM\CurrentControlSet\Control\Class\" kbdClass, "UpperFilters")
        mouFilters := RegRead("HKLM\SYSTEM\CurrentControlSet\Control\Class\" mouClass, "UpperFilters")
    } catch {
        return false
    }
    ; REG_MULTI_SZ 读出为换行分隔
    hasKbd := false, hasMou := false
    for part in StrSplit(kbdFilters, "`n", "`r") {
        if (Trim(part) = "keyboard") {
            hasKbd := true
            break
        }
    }
    for part in StrSplit(mouFilters, "`n", "`r") {
        if (Trim(part) = "mouse") {
            hasMou := true
            break
        }
    }
    return hasKbd && hasMou
}

; 未安装 Interception 时提示；返回 true 表示用户点了「自动安装」
ShowInterceptionInstallTip() {
    chosen := ""
    tipText := GetLang("使用AHI需要安装interception") "`n`n"
        . GetLang("（Plugins/AhiDriver/installer/安装卸载bat 可以手动操作）")

    g := Gui("+AlwaysOnTop -MinimizeBox", GetLang("提示"))
    try
        g.SetFont("S10 W550 Q2", MainSoftData.FontType)
    catch
        g.SetFont("S10")
    g.Add("Text", "x20 y18 w340 h60", tipText)
    btnInstall := g.Add("Button", "x20 y90 w150 h30 Default", GetLang("自动安装"))
    btnCancel := g.Add("Button", "x190 y90 w150 h30", GetLang("取消"))
    btnInstall.OnEvent("Click", (*) => (chosen := "install", g.Destroy()))
    btnCancel.OnEvent("Click", (*) => (chosen := "cancel", g.Destroy()))
    g.OnEvent("Close", (*) => (chosen := "cancel", g.Destroy()))
    g.Show("w380 h140 Center")
    hwnd := g.Hwnd
    WinWaitClose("ahk_id " hwnd)

    if (chosen != "install")
        return false

    ahiDir := GetAHIPluginDir()
    installPs1 := ahiDir "\install.ps1"
    if !FileExist(installPs1) {
        MsgBox(GetLang("未找到 Interception 安装脚本") "`n" installPs1, GetLang("提示"), 48)
        return false
    }

    ps := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(ps)
        ps := "powershell.exe"
    cmd := Format('"{1}" -NoProfile -ExecutionPolicy Bypass -File "{2}" -Action install -NoPause', ps, installPs1)
    exitCode := RunWait(cmd, ahiDir)
    if (exitCode = 0) {
        MsgBox(GetLang("Interception 安装完成，可直接使用 AHI 按键类型"), GetLang("提示"), 64)
    } else {
        MsgBox(GetLang("Interception 安装失败，可手动运行 Plugins/AhiDriver/installer/安装卸载.bat"), GetLang("提示"), 48)
    }
    return true
}

; 延迟初始化函数（首次使用时调用）
InitAHI() {
    static hasTipNoInterception := false

    if (IsObject(AHI_Driver)) {
        return true
    }

    if (!IsInterceptionInstalled()) {
        if (!hasTipNoInterception) {
            hasTipNoInterception := true
            ShowInterceptionInstallTip()
        }
        return false
    }

    try {
        global AHI_Driver := AutoHotInterception()
        AHI_Driver.SetState(false)
        return true
    } catch as err {
        MsgBox(
            "❌ AHI 驱动加载失败！`n`n"
            "错误信息: " err.Message "`n`n"
            "请检查：`n"
            "1. 是否已安装 Interception 驱动并已重启？`n"
            "2. Plugins\AhiDriver 下 interception.dll / AutoHotInterception.dll 是否存在？`n"
            "3. 是否以管理员权限运行？`n`n"
            "也可手动运行 Plugins\AhiDriver\installer\安装卸载.bat",
            "AHI 错误", 16
        )
        return false
    }
}

AhiDestroy() {
    global AHI_Driver
    if (IsObject(AHI_Driver)) {
        try {
            AHI_Driver.SetState(false)
        }
    }
}

AhiSetState(state) {
    if (!InitAHI())
        return
    
    global AHI_Driver
    AHI_Driver.SetState(state)
}

; 发送单个按键（自动识别键盘/鼠标）
AhiSendKey(key, state := 1) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_KeyboardId, AHI_MouseId, AHI_MouseBtnMap, AHI_WheelMap

    ; 检查是否为鼠标按键
    if (AHI_MouseBtnMap.Has(key)) {
        btnNum := AHI_MouseBtnMap[key]

        if (state == 1) {
            AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
        } else {
            AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
        }
        return true
    }

    ; 滚轮：一次性事件，只在 state==1 时发送（旧的 SendMouseMoveRelative 会把光标当 Y 轴移动，且方向相反）
    if (AHI_WheelMap.Has(key)) {
        if (state == 1) {
            wheel := AHI_WheelMap[key]
            AHI_Driver.SendMouseButtonEvent(AHI_MouseId, wheel[1], wheel[2])
            _AHI_Log("AHI_Wheel", Format("key={} btn={} state={}", key, wheel[1], wheel[2]))
        }
        return true
    }

    ; 键盘按键
    ; 注意：AHI 只认 <=256 的扫描码，以及 256+ 白名单内的扩展键（方向键/Insert/Delete/Win/RCtrl/RAlt/RShift/
    ; NumLock/NumpadEnter/NumpadDiv/PrtScr/AppsKey）。多媒体键（Volume_*/Media_*/Browser_*/Launch_*）的
    ; AHK 扫描码都 >256 且不在白名单内，AHI 会直接抛异常，必须拦下来，否则整个宏会被打断
    scanCode := GetKeySC(key)
    if (scanCode != 0) {
        try
            AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, state)
        catch as err {
            _AHI_Log("AHI_KeyErr", Format("key={} sc=0x{:X} state={} err={}", key, scanCode, state, err.Message))
            return false
        }
        return true
    }
    
    return false
}

; 发送按键字符串（支持组合键，自动识别键盘/鼠标）
; 注意：此函数用于独立发送完整按键序列（按下+释放），与 SendAHIKey 不同
AhiSend(keys) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_KeyboardId, AHI_MouseId, AHI_MouseBtnMap, AHI_WheelMap
    keys := Trim(keys)
    if (keys == "")
        return false

    ; 预处理：提取大括号内的内容（如 {LButton}, {Ctrl}）
    pos := 1
    while (pos <= StrLen(keys)) {
        char := SubStr(keys, pos, 1)

        if (char == "{") {
            ; 查找匹配的 }
            endPos := InStr(keys, "}", , pos + 1)
            if (endPos == 0)
                endPos := StrLen(keys) + 1

            ; 提取括号内的键名
            keyName := SubStr(keys, pos + 1, endPos - pos - 1)

            ; 处理特殊键
            if (AHI_MouseBtnMap.Has(keyName)) {
                btnNum := AHI_MouseBtnMap[keyName]
                AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
                AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
            } else if (AHI_WheelMap.Has(keyName)) {
                wheel := AHI_WheelMap[keyName]
                AHI_Driver.SendMouseButtonEvent(AHI_MouseId, wheel[1], wheel[2])
            } else {
                ; 键盘按键
                scanCode := GetKeySC(keyName)
                if (scanCode != 0) {
                    AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 1)
                    AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 0)
                }
            }

            pos := endPos + 1
        } else if (char != " ") {
            ; 单个字符键盘按键
            scanCode := GetKeySC(char)
            if (scanCode != 0) {
                AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 1)
                AHI_Driver.SendKeyEvent(AHI_KeyboardId, scanCode, 0)
            }

            pos++
        } else {
            ; 空格，跳过
            pos++
        }
    }

    return true
}

; 发送修饰键 + 普通键组合（辅助函数，一般不直接用于宏系统）
AhiSendCombo(key, modifiers*) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_KeyboardId

    for mod in modifiers {
        modScanCode := GetKeySC(mod)
        if (modScanCode != 0)
            AHI_Driver.SendKeyEvent(AHI_KeyboardId, modScanCode, 1)
    }

    keyScanCode := GetKeySC(key)
    if (keyScanCode != 0) {
        AHI_Driver.SendKeyEvent(AHI_KeyboardId, keyScanCode, 1)
        AHI_Driver.SendKeyEvent(AHI_KeyboardId, keyScanCode, 0)
    }

    Loop (modifiers.Length) {
        mod := modifiers[modifiers.Length - A_Index + 1]
        modScanCode := GetKeySC(mod)
        if (modScanCode != 0)
            AHI_Driver.SendKeyEvent(AHI_KeyboardId, modScanCode, 0)
    }

    return true
}

; 规范化鼠标键名（支持 L/R/M 缩写与 LButton 等完整名）
AhiNormalizeMouseBtn(whichButton := "L") {
    btnName := whichButton
    if (btnName == "L")
        return "LButton"
    if (btnName == "R")
        return "RButton"
    if (btnName == "M")
        return "MButton"
    return btnName
}

; 鼠标点击（Interception）；clickCount 为点击次数
AhiClick(whichButton := "L", clickCount := 1) {
    if (!InitAHI()) {
        ; AHK v2 的 Click 最多 3 个参数（X, Y, Options），次数要拼进 Options 字符串
        static fallbackBtn := Map("LButton", "Left", "RButton", "Right", "MButton", "Middle"
            , "XButton1", "X1", "XButton2", "X2")
        btnName := AhiNormalizeMouseBtn(whichButton)
        btnOpt := fallbackBtn.Has(btnName) ? fallbackBtn[btnName] : "Left"
        cnt := Max(1, Integer(clickCount))
        Loop cnt {
            Click(btnOpt)
            if (A_Index < cnt)
                Sleep(50)
        }
        return false
    }

    global AHI_Driver, AHI_MouseId, AHI_MouseBtnMap
    btnName := AhiNormalizeMouseBtn(whichButton)
    btnNum := AHI_MouseBtnMap.Has(btnName) ? AHI_MouseBtnMap[btnName] : 0
    clickCount := Max(1, Integer(clickCount))

    loop clickCount {
        AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
        AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
        if (A_Index < clickCount)
            Sleep(50)
    }
    return true
}

; 鼠标按下/释放（用于拖拽等）
AhiMouseDown(whichButton := "L") {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_MouseId, AHI_MouseBtnMap
    btnName := AhiNormalizeMouseBtn(whichButton)
    btnNum := AHI_MouseBtnMap.Has(btnName) ? AHI_MouseBtnMap[btnName] : 0
    AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 1)
    return true
}

AhiMouseUp(whichButton := "L") {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_MouseId, AHI_MouseBtnMap
    btnName := AhiNormalizeMouseBtn(whichButton)
    btnNum := AHI_MouseBtnMap.Has(btnName) ? AHI_MouseBtnMap[btnName] : 0
    AHI_Driver.SendMouseButtonEvent(AHI_MouseId, btnNum, 0)
    return true
}

; ========== 鼠标移动（Interception，正式接口） ==========

; 屏幕坐标 → Interception 绝对坐标（0~65535，映射整个虚拟桌面）
; 公式：屏幕像素 0~(vw-1) 线性映射到 0~65535
; 缓存 SysGet 避免循环中重复查询，同时消除并发下的屏幕尺寸漂移
AhiScreenToAbs(x, y, &absX, &absY) {
    static vx := "", vy := "", vw := "", vh := ""
    if (vx == "") {
        vx := SysGet(76)   ; SM_XVIRTUALSCREEN
        vy := SysGet(77)   ; SM_YVIRTUALSCREEN
        vw := Max(1, SysGet(78))  ; SM_CXVIRTUALSCREEN
        vh := Max(1, SysGet(79))  ; SM_CYVIRTUALSCREEN
    }
    ; 使用 (vw - 1) / (vh - 1) 作为分母，保证最右/最下像素映射到 65535
    absX := Max(0, Min(65535, Round((Integer(x) - vx) * 65535.0 / Max(1, vw - 1))))
    absY := Max(0, Min(65535, Round((Integer(y) - vy) * 65535.0 / Max(1, vh - 1))))
}

; 平滑步进参数
; 步长上限 50：避免单次 driver 调用值过大被 Windows 鼠标加速曲线放大
; speed: 1~100 越大越快
; 90+ 高速段：步长指数增长，90=46, 91=46*1.3, 92=46*1.3^2, ..., 100=46*1.3^10
AhiSmoothStepParams(speed, &maxStep, &stepDelay) {
    speed := Max(1, Min(100, Integer(speed)))
    if (speed >= 90) {
        maxStep := Round(46 * (1.3 ** (speed - 90)))
        stepDelay := 1
        return
    }
    factor := speed / 100.0
    maxStep := Max(2, Min(50, Round(2 + 50 * (factor ** 1.2))))
    stepDelay := Max(1, Round(22 * ((1 - factor) ** 1.2) + 1))
}

; 相对移动
AhiMoveR(x, y) {
    if (!InitAHI())
        return false
    global AHI_Driver, AHI_MouseId
    AHI_Driver.SendMouseMoveRelative(AHI_MouseId, Integer(x), Integer(y))
    return true
}

; 绝对移动到屏幕坐标（真绝对报告，避免相对+加速导致乱飘）
AhiMoveAbs(targetX, targetY) {
    if (!InitAHI())
        return false

    global AHI_Driver, AHI_MouseId
    ; 钳制到虚拟桌面范围内，避免驱动收到越界坐标后行为异常
    static vx := "", vy := "", vw := "", vh := ""
    if (vx == "") {
        vx := SysGet(76), vy := SysGet(77)
        vw := SysGet(78), vh := SysGet(79)
    }
    targetX := Max(vx, Min(vx + vw - 1, Integer(targetX)))
    targetY := Max(vy, Min(vy + vh - 1, Integer(targetY)))
    AhiScreenToAbs(targetX, targetY, &absX, &absY)
    AHI_Driver.SendMouseMoveAbsolute(AHI_MouseId, absX, absY)
    return true
}

; 带速度的绝对移动
; 内部拆分为小步长相对移动，不调用 SendMouseMoveAbsolute 以避免 AHI 驱动坐标映射异常导致闪烁
; speed: 1~100 越大越快（拆分为小步相对移动）
AhiMoveAbsSmooth(targetX, targetY, speed := 0) {
    if (!InitAHI())
        return false

    CoordMode("Mouse", "Screen")

    ; 钳制目标到虚拟桌面范围
    static vx := "", vy := "", vw := "", vh := ""
    if (vx == "") {
        vx := SysGet(76), vy := SysGet(77)
        vw := SysGet(78), vh := SysGet(79)
    }
    targetX := Max(vx, Min(vx + vw - 1, Integer(targetX)))
    targetY := Max(vy, Min(vy + vh - 1, Integer(targetY)))

    MouseGetPos(&curX, &curY)
    dx := targetX - curX
    dy := targetY - curY

    if (Abs(dx) <= 1 && Abs(dy) <= 1)
        return true

    ; 全部走相对步进，避免 AHI 绝对移动在坐标映射不一致时闪烁
    return AhiMoveRSmooth(dx, dy, speed)
}

; 相对移动（平滑，闭环校正 + 自适应步长）
;   - 步长随剩余距离等比衰减：≤5px→1，否则≤1/3，上限 maxStep
;   - speed: 1~100 越大越快
AhiMoveRSmooth(relX, relY, speed := 0) {
    if (!InitAHI())
        return false

    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY)
    expectX := startX + Integer(relX)
    expectY := startY + Integer(relY)

    if (speed <= 0)
        speed := 1
    useSpeed := Min(100, Max(1, Integer(speed)))

    AhiSmoothStepParams(useSpeed, &maxStep, &stepDelay)

    stepCount := 0
    stuckCount := 0
    oscillationCount := 0
    prevDxSign := 0, prevDySign := 0
    lastCurX := -9999, lastCurY := -9999
    Loop 5000 {
        MouseGetPos(&curX, &curY)
        dx := expectX - curX
        dy := expectY - curY
        len := Sqrt(dx * dx + dy * dy)

        if (len <= 1)
            break

        ; 检测震荡死循环（方向反复反转说明在目标附近来回振荡）
        curDxSign := (dx > 0 ? 1 : (dx < 0 ? -1 : 0))
        curDySign := (dy > 0 ? 1 : (dy < 0 ? -1 : 0))
        if (prevDxSign != 0 && curDxSign != 0 && curDxSign != prevDxSign)
            oscillationCount++
        else if (prevDySign != 0 && curDySign != 0 && curDySign != prevDySign)
            oscillationCount++
        else if (curDxSign != 0 || curDySign != 0)
            oscillationCount := Max(0, oscillationCount - 1)
        prevDxSign := curDxSign, prevDySign := curDySign
        if (oscillationCount >= 5) {
            ; 陷入震荡，最后再发一次精确微调然后退出
            if (Abs(dx) <= 2 && Abs(dy) <= 2) {
                AhiMoveR(dx, dy)
                Sleep(stepDelay)
            }
            break
        }

        ; 检测卡死（光标不再移动但目标未达成，如触屏边缘）
        if (curX = lastCurX && curY = lastCurY) {
            stuckCount++
            if (stuckCount >= 3)
                break
        } else {
            stuckCount := 0
        }
        lastCurX := curX, lastCurY := curY

        stepCount++
        ; 自适应步长：剩余距离 ≤5px 时降为 1，否则每步最多覆盖 1/3
        adaptiveMaxStep := Max(1, Min(maxStep, len <= 5 ? 1 : Round(len / 3)))

        if (len <= adaptiveMaxStep) {
            AhiMoveR(dx, dy)
            Sleep(stepDelay)
            continue
        }
        sx := Round(dx * adaptiveMaxStep / len)
        sy := Round(dy * adaptiveMaxStep / len)
        if (sx = 0 && dx != 0)
            sx := dx > 0 ? 1 : -1
        if (sy = 0 && dy != 0)
            sy := dy > 0 ? 1 : -1
        AhiMoveR(sx, sy)
        Sleep(stepDelay)
    }

    ; 诊断日志
    MouseGetPos(&endX, &endY)
    _AHI_Log("AHI_RSmooth", Format("req=({},{}) start=({},{}) expect=({},{}) end=({},{}) err=({},{}) steps={} maxStep={} speed={}"
        , Integer(relX), Integer(relY), startX, startY, expectX, expectY, endX, endY
        , expectX - endX, expectY - endY, stepCount, maxStep, useSpeed))
    return true
}

