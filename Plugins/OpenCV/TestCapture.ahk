;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; 测试截图性能脚本
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


#Requires AutoHotkey v2.0
#SingleInstance Force

dllPath := A_ScriptDir "\RMT_OpenCV.dll"
if !FileExist(dllPath) {
    MsgBox "找不到 DLL: " dllPath
    ExitApp
}

saveDir := A_ScriptDir "\"
DirCreate(saveDir)

; ====== 全局状态 ======
global gInitMemBase := 0
global gWinInitialized := false
global gWinCount := 0, gWinTotalMs := 0, gWinMinMs := 0, gWinMaxMs := 0
global gScreenCount := 0, gScreenTotalMs := 0, gScreenMinMs := 0, gScreenMaxMs := 0
gInitMemBase := GetProcessMemory()

; 预热 BitBlt
prePtr := DllCall(dllPath "\CaptureScreenMat", "Int", 0, "Int", 0, "Int", 1920, "Int", 1080, "Ptr")
if (prePtr)
    DllCall(dllPath "\ReleaseMat", "Ptr", prePtr)

; ====== GUI (两列对比) ======
MyGui := Gui("+AlwaysOnTop", "截图测试工具 - 对比模式")
MyGui.SetFont("s10")

; 顶部公共控件
MyGui.Add("Text",, "窗口句柄:")
edtHwnd := MyGui.Add("Edit", "vEdtHwnd w200 ReadOnly")
MyGui.Add("Text", "xm", "区域 (x,y,w,h):")
edtRegion := MyGui.Add("Edit", "vEdtRegion w200", "0,0,1920,1080")

btnBind := MyGui.Add("Button", "w100", "绑定窗口 (F1)")
btnRunAll := MyGui.Add("Button", "wp Default", "同时测试(F5)")
btnReset := MyGui.Add("Button", "wp", "重置统计")
btnOpen := MyGui.Add("Button", "wp", "打开文件夹")

; 分隔线
MyGui.Add("Text", "xm h2 w440 BackgroundGray")

; 两列标签
MyGui.SetFont("Bold")
MyGui.Add("Text", "xm y+8 w210 Center", "--- DWM 窗口截图 ---")
MyGui.Add("Text", "x+m w210 Center", "--- BitBlt 屏幕截图 ---")
MyGui.SetFont() ; 恢复默认字体

; ====== 两列对比 (Section 对齐) ======
; --- 第1行: 初始化信息 ---
MyGui.SetFont("s9")
lblWinInit := MyGui.Add("Text", "xm w200 r5 vLblWinInit",
    Format("基线: {:.1f}MB`nDWM: 未初始化", gInitMemBase))
lblScreenInit := MyGui.Add("Text", "x+m wp r5 vLblScreenInit",
    Format("基线: {:.1f}MB`nBitBlt: 已初始化 (+{:.1f}MB)",
        gInitMemBase, GetProcessMemory() - gInitMemBase))

; --- 第2行: 截图结果 (含统计) ---
lblWinResult := MyGui.Add("Text", "xm y+4 w200 r7 Border vLblWin", "等待 F5 测试...")
lblScreenResult := MyGui.Add("Text", "x+m wp r7 Border vLblScreen", "等待 F5 测试...")
MyGui.SetFont()

btnBind.OnEvent("Click", OnBind)
btnRunAll.OnEvent("Click", OnRunAll)
btnReset.OnEvent("Click", OnReset)
btnOpen.OnEvent("Click", (*) => Run('explorer.exe "' saveDir '"'))
MyGui.OnEvent("Close", (*) => ExitApp)
MyGui.Show()

; ====== 快捷键 ======
F1:: OnBind()
F5:: OnRunAll()

; ====== 绑定窗口 & 预热 DWM ======
OnBind(*) {
    global gWinInitialized
    MouseGetPos ,, &hwnd
    title := WinGetTitle("ahk_id " hwnd)
    edtHwnd.Value := hwnd

    if (!gWinInitialized) {
        prePtr := DllCall(dllPath "\CaptureWinMat", "Int", hwnd, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
        if (prePtr)
            DllCall(dllPath "\ReleaseMat", "Ptr", prePtr)
        gWinInitialized := true
        initMem := GetProcessMemory() - gInitMemBase
        lblWinInit.Value := Format("基线: {:.1f}MB`n已绑定: {}`nDWM 初始化 (+{:.1f}MB)",
            gInitMemBase, title, initMem)
    } else {
        lblWinInit.Value := Format("基线: {:.1f}MB`n已绑定: {}",
            gInitMemBase, title)
    }
}

; ====== 同时执行两种截图 ======
OnRunAll(*) {
    global gWinCount, gWinTotalMs, gWinMinMs, gWinMaxMs
    global gScreenCount, gScreenTotalMs, gScreenMinMs, gScreenMaxMs

    hwnd := Integer(edtHwnd.Value)
    if (!hwnd) {
        lblWinResult.Value := "请先绑定窗口"
        return
    }

    r := ParseRegion()

    ; ---- 左列: DWM ----
    memW1 := GetProcessMemory()
    t1w := A_TickCount
    winMat := DllCall(dllPath "\CaptureWinMat", "Int", hwnd,
        "Int", r.x, "Int", r.y, "Int", r.w, "Int", r.h, "Ptr")
    t2w := A_TickCount
    if (winMat) {
        ts := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
        winFile := saveDir "dwm_" ts ".png"
        retW := DllCall(dllPath "\SaveMatToFile", "Ptr", winMat, "AStr", winFile, "Int")
        DllCall(dllPath "\ReleaseMat", "Ptr", winMat)
    }
    memW2 := GetProcessMemory()
    msW := t2w - t1w

    ; 累计统计
    gWinCount++
    gWinTotalMs += msW
    gWinMinMs := (gWinMinMs == 0 || msW < gWinMinMs) ? msW : gWinMinMs
    gWinMaxMs := (msW > gWinMaxMs) ? msW : gWinMaxMs

    ; ---- 右列: BitBlt ----
    memS1 := GetProcessMemory()
    t1s := A_TickCount
    screenMat := DllCall(dllPath "\CaptureScreenMat",
        "Int", r.x, "Int", r.y, "Int", r.w, "Int", r.h, "Ptr")
    t2s := A_TickCount
    if (screenMat) {
        ts := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
        screenFile := saveDir "bitblt_" ts ".png"
        retS := DllCall(dllPath "\SaveMatToFile", "Ptr", screenMat, "AStr", screenFile, "Int")
        DllCall(dllPath "\ReleaseMat", "Ptr", screenMat)
    }
    memS2 := GetProcessMemory()
    msS := t2s - t1s

    ; 累计统计
    gScreenCount++
    gScreenTotalMs += msS
    gScreenMinMs := (gScreenMinMs == 0 || msS < gScreenMinMs) ? msS : gScreenMinMs
    gScreenMaxMs := (msS > gScreenMaxMs) ? msS : gScreenMaxMs

    ; ---- 更新显示 -----
    avgW := Round(gWinTotalMs / gWinCount, 1)
    avgS := Round(gScreenTotalMs / gScreenCount, 1)

    lblWinResult.Value := Format(
        "#{} 本次: {}ms | 内存: +{:.1f}MB`n--- 统计 ---`n次数: {}  平均: {}ms`n最小: {}ms  最大: {}ms",
        gWinCount, msW, memW2-memW1, gWinCount, avgW, gWinMinMs, gWinMaxMs)

    lblScreenResult.Value := Format(
        "#{} 本次: {}ms | 内存: +{:.1f}MB`n--- 统计 ---`n次数: {}  平均: {}ms`n最小: {}ms  最大: {}ms",
        gScreenCount, msS, memS2-memS1, gScreenCount, avgS, gScreenMinMs, gScreenMaxMs)
}

; ====== 重置统计 ======
OnReset(*) {
    global gWinCount, gWinTotalMs, gWinMinMs, gWinMaxMs
    global gScreenCount, gScreenTotalMs, gScreenMinMs, gScreenMaxMs

    gWinCount := 0, gWinTotalMs := 0, gWinMinMs := 0, gWinMaxMs := 0
    gScreenCount := 0, gScreenTotalMs := 0, gScreenMinMs := 0, gScreenMaxMs := 0

    lblWinResult.Value := "等待 F5 测试..."
    lblScreenResult.Value := "等待 F5 测试..."
}

; ====== 解析区域参数 ======
ParseRegion() {
    parts := StrSplit(edtRegion.Value, ",")
    return {
        x: Integer(parts.Has(1) ? parts[1] : 0),
        y: Integer(parts.Has(2) ? parts[2] : 0),
        w: Integer(parts.Has(3) ? parts[3] : 0),
        h: Integer(parts.Has(4) ? parts[4] : 0)
    }
}

; ====== 获取当前进程工作集内存 (MB) ======
GetProcessMemory() {
    static wmiSvc := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
    pid := ProcessExist()
    for proc in wmiSvc.ExecQuery('SELECT * FROM Win32_Process WHERE ProcessId=' . pid)
        return proc.WorkingSetSize / 1024 / 1024
    return 0
}
