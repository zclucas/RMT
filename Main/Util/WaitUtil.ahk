#Requires AutoHotkey v2.0

; =================================================================
; §16 等待指令执行端 —— 「检测间隔 + 轮询」骨架 + 19 种检测
;
; 设计（文档 §16 评估）：统一轮询基类骨架（OnWait），
; 每种等待 = WaitCheckOnce 的一个分支；变化类（屏幕/鼠标/剪切板/
; 窗口/文件）在 WaitInitBaseline 记录一次性基准，轮询对比基准。
; 基准存 WaitStateMap（key = 表ID|条目ID），避免污染共享的 Data 配置对象。
; 中断语义与其它指令一致：WaitIfPaused / item.Killed / InterruptibleSleep。
; =================================================================

global WaitStateMap := Map()

; ---------- 轮询骨架 ----------

OnWait(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    WaitInitBaseline(tableItem, index, Data)
    Loop {
        WaitIfPaused(tableItem, index)
        item := tableItem.Items[index]
        if (item.Killed)
            return
        if (WaitCheckOnce(tableItem, index, Data))
            return
        FloatInterval := GetFloatTime(Data.Interval, MainSoftData.PreIntervalFloat)
        InterruptibleSleep(tableItem, index, FloatInterval)
    }
}

WaitStateKey(tableItem, index) {
    return tableItem.ID "|" tableItem.Items[index].ID
}

; ---------- 一次性基准（变化类） ----------

WaitInitBaseline(tableItem, index, Data) {
    key := WaitStateKey(tableItem, index)
    switch Data.WaitType {
        case 4:    ; 屏幕变化
            WaitStateMap[key] := WaitScreenFingerprint(Data)
        case 5:    ; 鼠标移动
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            WaitStateMap[key] := mx "|" my
        case 6:    ; 鼠标停止
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            WaitStateMap[key] := {x: mx, y: my, still: 0}
        case 7:    ; 剪切板变化
            WaitStateMap[key] := WaitClipboardText()
        case 12:   ; 窗口屏幕变化
            WaitStateMap[key] := WaitWinClientFingerprint(ResolveBindWindow(tableItem, index, Data.Param1))
        case 13:   ; 窗口大小变化
            WaitStateMap[key] := WaitWinSize(ResolveBindWindow(tableItem, index, Data.Param1))
        case 18:   ; 文件变化
            WaitStateMap[key] := WaitFileStamp(Data.Param1)
        case 19:   ; 日期
            WaitStateMap[key] := WaitCalcTargetTime(tableItem, index, Data)
    }
}

; ---------- 单次检测（19 种） ----------

WaitCheckOnce(tableItem, index, Data) {
    key := WaitStateKey(tableItem, index)
    switch Data.WaitType {
        case 1:    ; 等待变量值（变量 == 期望值；期望值支持 {变量} 替换）
            expected := GetReplaceVarText(tableItem, index, Data.Param2)
            return TryGetTabVarValue(&v, tableItem, index, Data.Param1) && String(v) == String(expected)
        case 2:    ; 等待按键按下
            return WaitIsKeyDown(Data.Param1)
        case 3:    ; 等待按键松开
            return !WaitIsKeyDown(Data.Param1)
        case 4:    ; 等待屏幕变化
            return WaitScreenFingerprint(Data) != WaitStateMap[key]
        case 5:    ; 等待鼠标移动
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            return mx "|" my != WaitStateMap[key]
        case 6:    ; 等待鼠标停止（连续 3 次轮询位置不变）
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            st := WaitStateMap[key]
            if (!IsObject(st))
                return false
            if (st.x == mx && st.y == my) {
                st.still++
                return st.still >= 3
            }
            st.x := mx
            st.y := my
            st.still := 0
            return false
        case 7:    ; 等待剪切板变化
            return WaitClipboardText() != WaitStateMap[key]
        case 8:    ; 等待进程存在
            return ProcessExist(GetReplaceVarText(tableItem, index, Data.Param1)) != ""
        case 9:    ; 等待进程关闭
            return ProcessExist(GetReplaceVarText(tableItem, index, Data.Param1)) == ""
        case 10:   ; 等待窗口存在
            return WaitHwndList(tableItem, index, Data.Param1).Length > 0
        case 11:   ; 等待窗口激活
            hwndList := WaitHwndList(tableItem, index, Data.Param1)
            return hwndList.Length > 0 && WinActive("ahk_id " hwndList[1])
        case 12:   ; 等待窗口屏幕变化
            return WaitWinClientFingerprint(ResolveBindWindow(tableItem, index, Data.Param1)) != WaitStateMap[key]
        case 13:   ; 等待窗口大小变化
            return WaitWinSize(ResolveBindWindow(tableItem, index, Data.Param1)) != WaitStateMap[key]
        case 14:   ; 等待窗口关闭
            return WaitHwndList(tableItem, index, Data.Param1).Length == 0
        case 15:   ; 等待窗口最小化
            hwndList := WaitHwndList(tableItem, index, Data.Param1)
            return hwndList.Length > 0 && WinGetMinMax("ahk_id " hwndList[1]) == -1
        case 16:   ; 等待文件存在
            return FileExist(GetReplaceVarText(tableItem, index, Data.Param1)) != ""
        case 17:   ; 等待文件删除
            return FileExist(GetReplaceVarText(tableItem, index, Data.Param1)) == ""
        case 18:   ; 等待文件变化
            return WaitFileStamp(GetReplaceVarText(tableItem, index, Data.Param1)) != WaitStateMap[key]
        case 19:   ; 等待日期
            target := WaitStateMap[key]
            return target != "" && A_Now >= target
    }
    return false
}

; ---------- 检测辅助 ----------

WaitHwndList(tableItem, index, winInfo) {
    winInfo := GetReplaceVarText(tableItem, index, winInfo)
    return GetHwndList(ResolveBindWindow(tableItem, index, winInfo))
}

WaitIsKeyDown(key) {
    if (key == "")
        return false
    try
        return GetKeyState(key, "P")
    return false
}

WaitClipboardText() {
    return IsClipboardText() ? A_Clipboard : ""
}

; 屏幕区域网格采样指纹（20px 步长，容错单点取色异常）
WaitScreenFingerprint(Data) {
    CoordMode("Pixel", "Screen")
    x1 := Integer(Data.StartPosX), y1 := Integer(Data.StartPosY)
    x2 := Integer(Data.EndPosX), y2 := Integer(Data.EndPosY)
    if (x2 < x1) {
        t := x1
        x1 := x2
        x2 := t
    }
    if (y2 < y1) {
        t := y1
        y1 := y2
        y2 := t
    }
    if (x2 - x1 < 4 || y2 - y1 < 4)
        return ""
    fp := ""
    interval := 20
    yy := y1
    while (yy <= y2) {
        xx := x1
        while (xx <= x2) {
            try fp .= PixelGetColor(xx, yy)
            xx += interval
        }
        yy += interval
    }
    return fp
}

; 窗口客户区屏幕指纹（用于「窗口屏幕变化」）
WaitWinClientFingerprint(winInfo) {
    hwndList := GetHwndList(winInfo)
    if (hwndList.Length == 0)
        return ""
    hwnd := hwndList[1]
    WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    if (cw <= 2 || ch <= 2)
        return ""
    DllCall("SetProcessDPIAware")
    rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    pt := Buffer(8, 0)
    NumPut("int", cx, pt, 0)
    NumPut("int", cy, pt, 4)
    DllCall("User32\ClientToScreen", "ptr", rootHwnd, "ptr", pt)
    sx := NumGet(pt, 0, "int")
    sy := NumGet(pt, 4, "int")
    CoordMode("Pixel", "Screen")
    fp := ""
    interval := 20
    yy := sy
    while (yy <= sy + ch - 1) {
        xx := sx
        while (xx <= sx + cw - 1) {
            try fp .= PixelGetColor(xx, yy)
            xx += interval
        }
        yy += interval
    }
    return fp
}

; 窗口宽高（用于「窗口大小变化」）
WaitWinSize(winInfo) {
    hwndList := GetHwndList(winInfo)
    if (hwndList.Length == 0)
        return ""
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwndList[1])
    return w "|" h
}

; 文件修改时间+大小（用于「文件变化」）
WaitFileStamp(path) {
    if (path == "" || !FileExist(path))
        return ""
    try
        return FileGetTime(path, "M") "|" FileGetSize(path)
    return ""
}

; ---------- 日期（等待日期） ----------

; 目标时间：分钟/小时/天（相对）+ 具体时间 / 时间变量（绝对）
WaitCalcTargetTime(tableItem, index, Data) {
    unit := GetLangKey(Data.Param2)
    switch unit {
        case "分钟":
            return DateAdd(A_Now, IsNumber(Data.Param1) ? Integer(Data.Param1) : 0, "Minutes")
        case "小时":
            return DateAdd(A_Now, IsNumber(Data.Param1) ? Integer(Data.Param1) : 0, "Hours")
        case "天":
            return DateAdd(A_Now, IsNumber(Data.Param1) ? Integer(Data.Param1) : 0, "Days")
        case "具体时间":
            return WaitParseDateTime(Data.Param1)
        case "时间变量":
            if (TryGetTabVarValue(&v, tableItem, index, Data.Param1)) {
                if (IsNumber(v))
                    return DateAdd("19700101000000", Integer(v), "Seconds")   ; Unix 秒（配合 §4 时间戳变量）
                return WaitParseDateTime(String(v))
            }
    }
    return ""
}

; 解析日期时间字符串为 YYYYMMDDHH24MISS：
;   支持 "20260101120000" / "20260101" / "2026-01-01 12:00:00" / "2026/1/1 8:00"
WaitParseDateTime(s) {
    s := Trim(s)
    if (s == "")
        return ""
    digits := RegExReplace(s, "\D")
    if (digits.Length >= 14)
        return SubStr(digits, 1, 14)
    if (digits.Length == 8)
        return digits "000000"
    y := "", mo := "", d := "", h := "00", mi := "00", se := "00"
    if (RegExMatch(s, "(\d{4})[-/年. ](\d{1,2})[-/月. ](\d{1,2})", &m)) {
        y := m[1]
        mo := Format("{:02}", m[2])
        d := Format("{:02}", m[3])
        if (RegExMatch(s, "(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?", &mt)) {
            h := Format("{:02}", mt[1])
            mi := Format("{:02}", mt[2])
            se := (mt.Count >= 3 && mt[3] != "") ? Format("{:02}", mt[3]) : "00"
        }
        return y mo d h mi se
    }
    return ""
}
