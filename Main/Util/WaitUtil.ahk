#Requires AutoHotkey v2.0

; =================================================================
; §16 等待指令执行端 —— 「检测间隔 + 轮询」骨架 + 19 种检测
;
; 每种等待 = WaitCheckOnce 的一个分支。变化类在开始时记基准，
; 基准放 WaitStateMap（表ID|条目ID），不写回共享的 Data。
; 中断与其它指令一致：WaitIfPaused / item.Killed / InterruptibleSleep。
; =================================================================

global WaitStateMap := Map()
global WaitKeyCapOn := false
global WaitKeyCapCB := ""
global WaitKeyCapIH := ""
global WaitKeyWatchCount := 0
global WaitKeyWatchIH := ""
global WaitKeyPulse := ""

; ---------- 轮询骨架 ----------

OnWait(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    if (!IsObject(Data))
        return
    key := WaitStateKey(tableItem, index)
    watchKey := false
    try {
        t := WaitTypeNum(Data)
        watchKey := (t == "等待按键按下" || t == "等待按键松开")
        if (watchKey)
            WaitInstallKeyWatch()
        WaitInitBaseline(tableItem, index, Data)
        Loop {
            WaitIfPaused(tableItem, index)
            item := tableItem.Items[index]
            if (!item || item.Killed)
                return
            if (WaitCheckOnce(tableItem, index, Data))
                return
            iv := Data.HasProp("Interval") ? Data.Interval : 500
            if (!IsNumber(iv) || Number(iv) <= 0)
                iv := 500
            FloatInterval := 500
            try FloatInterval := GetFloatTime(iv, MainSoftData.PreIntervalFloat)
            if (!IsNumber(FloatInterval) || FloatInterval < 15)
                FloatInterval := 15
            InterruptibleSleep(tableItem, index, FloatInterval)
        }
    } finally {
        if (watchKey)
            WaitRemoveKeyWatch()
        if (WaitStateMap.Has(key))
            WaitStateMap.Delete(key)
    }
}

WaitStateKey(tableItem, index) {
    return tableItem.ID "|" tableItem.Items[index].ID
}

WaitTypeNum(Data) {
    t := Data.HasProp("WaitType") ? Data.WaitType : "等待变量值"
    return CmdEnumWait(t)
}

; ---------- 一次性基准（变化类） ----------

WaitInitBaseline(tableItem, index, Data) {
    key := WaitStateKey(tableItem, index)
    switch WaitTypeNum(Data) {
        case "等待屏幕变化":
            WaitStateMap[key] := WaitScreenFingerprint(tableItem, index, Data)
        case "等待鼠标移动":
            WaitStateMap[key] := WaitMousePos()
        case "等待鼠标停止移动":
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            WaitStateMap[key] := {x: mx, y: my, tick: A_TickCount}
        case "等待剪切板变化":
            WaitStateMap[key] := WaitClipboardSeq()
        case "等待窗口屏幕变化":
            WaitStateMap[key] := WaitWinClientFingerprint(WaitResolveWindow(tableItem, index, Data.Param1))
        case "等待窗口大小变化":
            WaitStateMap[key] := WaitWinSize(WaitResolveWindow(tableItem, index, Data.Param1))
        case "等待按键松开":
            ; 已按下则等松开；未按下则先等一次按下再松开
            name := WaitNormKeyName(WaitResolveText(tableItem, index, Data.Param1))
            WaitStateMap[key] := {armed: name != "" && IsPhysicalKeyPressed(name)}
        case "等待文件变化":
            WaitStateMap[key] := WaitFileStamp(WaitResolveText(tableItem, index, Data.Param1))
        case "等待日期":
            WaitStateMap[key] := WaitCalcTargetTime(tableItem, index, Data)
    }
}

; ---------- 单次检测（19 种） ----------

WaitCheckOnce(tableItem, index, Data) {
    key := WaitStateKey(tableItem, index)
    switch WaitTypeNum(Data) {
        case "等待变量值":
            if (!TryGetTabVarValue(&v, tableItem, index, GetVarName(Data.Param1), false)
                && !TryGetTabVarValue(&v, tableItem, index, Data.Param1, false))
                return false
            return Trim(String(v)) == WaitExpectedText(tableItem, index, Data.Param2)
        case "等待按键按下":
            return WaitIsKeyDown(WaitResolveText(tableItem, index, Data.Param1))
        case "等待按键松开":
            return WaitKeyReleased(key, WaitResolveText(tableItem, index, Data.Param1))
        case "等待屏幕变化":
            return WaitChanged(key, WaitScreenFingerprint(tableItem, index, Data))
        case "等待鼠标移动":
            return WaitPlainChanged(key, WaitMousePos())
        case "等待鼠标停止移动":
            return WaitMouseStopped(key, Data)
        case "等待剪切板变化":
            return WaitPlainChanged(key, WaitClipboardSeq())
        case "等待进程存在":
            return WaitProcessAlive(WaitResolveText(tableItem, index, Data.Param1))
        case "等待进程关闭":
            name := WaitResolveText(tableItem, index, Data.Param1)
            return name != "" && !WaitProcessAlive(name)
        case "等待窗口存在":
            return WaitHwndList(tableItem, index, Data.Param1).Length > 0
        case "等待窗口激活":
            hwndList := WaitHwndList(tableItem, index, Data.Param1)
            if (hwndList.Length == 0)
                return false
            try
                return WinActive("ahk_id " hwndList[1])
            return false
        case "等待窗口屏幕变化":
            return WaitChanged(key, WaitWinClientFingerprint(WaitResolveWindow(tableItem, index, Data.Param1)))
        case "等待窗口大小变化":
            return WaitChanged(key, WaitWinSize(WaitResolveWindow(tableItem, index, Data.Param1)))
        case "等待窗口关闭":
            spec := WaitResolveWindow(tableItem, index, Data.Param1)
            if (spec == "")
                return false
            return GetHwndList(spec).Length == 0
        case "等待窗口最小化":
            hwndList := WaitHwndList(tableItem, index, Data.Param1)
            if (hwndList.Length == 0)
                return false
            try
                return WinGetMinMax("ahk_id " hwndList[1]) == -1
            return false
        case "等待文件存在":
            return WaitFileExists(WaitResolveText(tableItem, index, Data.Param1))
        case "等待文件删除":
            path := WaitResolveText(tableItem, index, Data.Param1)
            return path != "" && !WaitFileExists(path)
        case "等待文件变化":
            return WaitChanged(key, WaitFileStamp(WaitResolveText(tableItem, index, Data.Param1)))
        case "等待日期":
            target := WaitStateMap.Has(key) ? WaitStateMap[key] : ""
            if (target == "") {
                target := WaitCalcTargetTime(tableItem, index, Data)
                if (target != "")
                    WaitStateMap[key] := target
            }
            return target != "" && A_Now >= target
    }
    return false
}

; 空基准先记下，避免「目标刚出现」被当成一次变化
WaitChanged(key, cur) {
    base := WaitStateMap.Has(key) ? WaitStateMap[key] : ""
    if (cur == "" || base == "") {
        if (cur != "")
            WaitStateMap[key] := cur
        return false
    }
    return cur != base
}

WaitPlainChanged(key, cur) {
    if (!WaitStateMap.Has(key)) {
        WaitStateMap[key] := cur
        return false
    }
    return cur != WaitStateMap[key]
}

; ---------- 参数解析 ----------

WaitResolveText(tableItem, index, raw) {
    raw := String(raw)
    if (raw == "")
        return ""
    if (InStr(raw, "{"))
        return GetReplaceVarText(tableItem, index, raw)
    if (IsNumber(raw))
        return raw
    if (TryGetTabVarValue(&v, tableItem, index, raw, false))
        return String(v)
    keyed := GetLangKey(raw)
    if (keyed != raw && TryGetTabVarValue(&v, tableItem, index, keyed, false))
        return String(v)
    return raw
}

WaitExpectedText(tableItem, index, raw) {
    raw := String(raw)
    if (InStr(raw, "{"))
        return Trim(GetReplaceVarText(tableItem, index, raw))
    if (raw != "" && !IsNumber(raw)) {
        if (TryGetTabVarValue(&v, tableItem, index, raw, false))
            return Trim(String(v))
        keyed := GetLangKey(raw)
        if (keyed != raw && TryGetTabVarValue(&v, tableItem, index, keyed, false))
            return Trim(String(v))
    }
    return Trim(raw)
}

WaitResolveNum(tableItem, index, raw, fallback := 0) {
    text := WaitResolveText(tableItem, index, raw)
    return IsNumber(text) ? Integer(text) : fallback
}

WaitResolveWindow(tableItem, index, winInfo) {
    winInfo := ResolveBindWindow(tableItem, index, winInfo)
    if (winInfo == "" || !InStr(winInfo, "{"))
        return winInfo
    return GetReplaceVarText(tableItem, index, winInfo)
}

WaitHwndList(tableItem, index, winInfo) {
    return GetHwndList(WaitResolveWindow(tableItem, index, winInfo))
}

; ---------- 按键 ----------

WaitNormKeyName(key) {
    key := Trim(String(key))
    if (key == "")
        return ""
    static alias := Map(
        "左键", "LButton", "鼠标左键", "LButton",
        "右键", "RButton", "鼠标右键", "RButton",
        "中键", "MButton", "鼠标中键", "MButton",
        "侧键1", "XButton1", "侧键2", "XButton2",
        "滚轮上", "WheelUp", "滚轮下", "WheelDown",
        "滚轮左", "WheelLeft", "滚轮右", "WheelRight")
    if (alias.Has(key))
        key := alias[key]
    keyed := GetLangKey(key)
    if (keyed != key && alias.Has(keyed))
        key := alias[keyed]
    else if (keyed != key)
        key := keyed
    return NormalizeKeyPickerName(key)
}

; 松开：开始时已按下则等它松开；否则先看到按下，再等到松开
WaitKeyReleased(stateKey, key) {
    key := WaitNormKeyName(key)
    if (key == "")
        return false
    st := (WaitStateMap.Has(stateKey) && IsObject(WaitStateMap[stateKey])) ? WaitStateMap[stateKey] : {armed: false}
    down := WaitIsKeyDown(key)
    if (!st.armed) {
        if (down)
            st.armed := true
        WaitStateMap[stateKey] := st
        return false
    }
    WaitStateMap[stateKey] := st
    return !down
}

WaitIsKeyDown(key) {
    key := WaitNormKeyName(key)
    if (key == "")
        return false
    if (WaitKeyPulse != "") {
        hit := WaitKeyPulse == key
        WaitKeyPulse := ""
        if (hit)
            return true
    }
    return IsPhysicalKeyPressed(key)
}

WaitInstallKeyWatch() {
    global WaitKeyWatchCount, WaitKeyWatchIH, WaitKeyPulse
    WaitKeyWatchCount++
    if (WaitKeyWatchCount > 1)
        return
    WaitKeyPulse := ""
    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := WaitKeyWatchDown
    try ih.Start()
    WaitKeyWatchIH := ih
    for hk in WaitWheelKeys()
        try Hotkey("~*" hk, WaitKeyWatchWheel, "On")
}

WaitRemoveKeyWatch() {
    global WaitKeyWatchCount, WaitKeyWatchIH, WaitKeyPulse
    if (WaitKeyWatchCount <= 0)
        return
    WaitKeyWatchCount--
    if (WaitKeyWatchCount > 0)
        return
    if (IsObject(WaitKeyWatchIH)) {
        try WaitKeyWatchIH.Stop()
        WaitKeyWatchIH := ""
    }
    for hk in WaitWheelKeys()
        try Hotkey("~*" hk, WaitKeyWatchWheel, "Off")
    WaitKeyPulse := ""
}

WaitKeyWatchDown(ih, vk, sc) {
    global WaitKeyPulse
    try WaitKeyPulse := WaitNormKeyName(GetKeyName(Format("vk{:x}sc{:x}", vk, sc)))
}

WaitKeyWatchWheel(thisHotkey) {
    global WaitKeyPulse
    WaitKeyPulse := WaitNormKeyName(RegExReplace(thisHotkey, "^[~\*]+"))
}

WaitWheelKeys() {
    return ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
}

; 编辑器录入一颗按键。Esc 或超时取消。
WaitBeginKeyCapture(callback) {
    global WaitKeyCapOn, WaitKeyCapCB, WaitKeyCapIH
    WaitEndKeyCapture()
    while (GetKeyState("LButton", "P") || GetKeyState("RButton", "P") || GetKeyState("MButton", "P"))
        Sleep(15)
    WaitKeyCapCB := callback
    WaitKeyCapOn := true
    ih := InputHook("V T15")
    ih.KeyOpt("{All}", "E")
    ih.OnEnd := WaitKeyCapOnEnd
    WaitKeyCapIH := ih
    try ih.Start()
    for hk in WaitCaptureMouseKeys()
        try Hotkey("~*" hk, WaitKeyCapOnMouse, "On")
    try MyToolTipContent(GetLang("请按下要等待的按键（Esc 取消）"))
}

WaitKeyCapOnEnd(ih, *) {
    global WaitKeyCapOn
    if (!WaitKeyCapOn)
        return
    key := ih.EndKey
    if (key == "" || key == "Escape") {
        WaitEndKeyCapture()
        return
    }
    WaitFinishKeyCapture(key)
}

WaitKeyCapOnMouse(thisHotkey) {
    global WaitKeyCapOn
    if (!WaitKeyCapOn)
        return
    WaitFinishKeyCapture(RegExReplace(thisHotkey, "^[~\*]+"))
}

WaitFinishKeyCapture(key) {
    global WaitKeyCapOn, WaitKeyCapCB
    if (!WaitKeyCapOn)
        return
    cb := WaitKeyCapCB
    WaitEndKeyCapture()
    key := WaitNormKeyName(key)
    if (cb != "" && key != "")
        cb(key)
}

WaitEndKeyCapture() {
    global WaitKeyCapOn, WaitKeyCapCB, WaitKeyCapIH
    WaitKeyCapOn := false
    WaitKeyCapCB := ""
    if (IsObject(WaitKeyCapIH)) {
        try WaitKeyCapIH.Stop()
        WaitKeyCapIH := ""
    }
    for hk in WaitCaptureMouseKeys()
        try Hotkey("~*" hk, WaitKeyCapOnMouse, "Off")
    try {
        MySoftData.ToolTipEndTime := 0
        ToolTip()
    }
}

WaitCaptureMouseKeys() {
    return ["LButton", "RButton", "MButton", "XButton1", "XButton2"
        , "WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
}

; ---------- 屏幕 / 鼠标 / 剪切板 ----------

WaitMousePos() {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    return mx "|" my
}

WaitMouseStopped(key, Data) {
    if (!WaitStateMap.Has(key) || !IsObject(WaitStateMap[key]))
        return false
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    st := WaitStateMap[key]
    if (st.x != mx || st.y != my) {
        st.x := mx
        st.y := my
        st.tick := A_TickCount
        return false
    }
    need := Data.HasProp("Interval") ? Data.Interval : 500
    if (!IsNumber(need) || Number(need) < 50)
        need := 50
    return (A_TickCount - st.tick) >= Integer(need)
}

WaitClipboardSeq() {
    try
        return DllCall("GetClipboardSequenceNumber", "uint")
    return 0
}

; 固定 16×16 采样，避免整屏逐点取色把轮询拖死
WaitRectFingerprint(x1, y1, x2, y2) {
    if (!IsNumber(x1) || !IsNumber(y1) || !IsNumber(x2) || !IsNumber(y2))
        return ""
    x1 := Integer(x1), y1 := Integer(y1), x2 := Integer(x2), y2 := Integer(y2)
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
    w := x2 - x1
    h := y2 - y1
    if (w < 4 || h < 4)
        return ""
    CoordMode("Pixel", "Screen")
    stepX := Max(1, w // 16)
    stepY := Max(1, h // 16)
    hash := 2166136261
    got := 0
    yy := y1
    while (yy <= y2) {
        xx := x1
        while (xx <= x2) {
            col := WaitPixelAt(xx, yy)
            if (col != "") {
                try {
                    hash ^= Integer(col)
                    hash := (hash * 16777619) & 0xFFFFFFFF
                    got++
                }
            }
            xx += stepX
        }
        yy += stepY
    }
    return got > 0 ? Format("{:08X}", hash) : ""
}

WaitPixelAt(x, y) {
    col := ""
    try col := PixelGetColor(x, y)
    if (col == "")
        try col := PixelGetColor(x, y, "Alt")
    return col
}

WaitScreenFingerprint(tableItem, index, Data) {
    x1 := WaitResolveNum(tableItem, index, Data.StartPosX, 0)
    y1 := WaitResolveNum(tableItem, index, Data.StartPosY, 0)
    x2 := WaitResolveNum(tableItem, index, Data.EndPosX, 0)
    y2 := WaitResolveNum(tableItem, index, Data.EndPosY, 0)
    return WaitRectFingerprint(x1, y1, x2, y2)
}

; WinGetClientPos 给出的已是屏幕坐标
WaitWinClientFingerprint(winInfo) {
    hwndList := GetHwndList(winInfo)
    if (hwndList.Length == 0)
        return ""
    try {
        WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwndList[1])
        if (w <= 2 || h <= 2)
            return ""
        return WaitRectFingerprint(x, y, x + w - 1, y + h - 1)
    }
    return ""
}

WaitWinSize(winInfo) {
    hwndList := GetHwndList(winInfo)
    if (hwndList.Length == 0)
        return ""
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwndList[1])
        return w "|" h
    }
    return ""
}

; ---------- 进程 / 文件 ----------

WaitProcessAlive(name) {
    name := Trim(name, " `t`"")
    if (name == "")
        return false
    if (InStr(name, "\") || InStr(name, "/"))
        try SplitPath(name, &name)
    if (name == "")
        return false
    if (ProcessExist(name))
        return true
    if (!InStr(name, ".") && ProcessExist(name ".exe"))
        return true
    return false
}

WaitFileExists(path) {
    path := Trim(path, " `t`"")
    if (path == "")
        return false
    try
        return FileExist(path) != ""
    return false
}

WaitFileStamp(path) {
    path := Trim(path, " `t`"")
    if (path == "" || !WaitFileExists(path))
        return ""
    try
        return FileGetTime(path, "M") "|" FileGetSize(path)
    return ""
}

; ---------- 日期 ----------

WaitNormDateUnit(unit) {
    u := GetLangKey(Trim(String(unit)))
    switch u {
        case "分钟", "Minute", "Minutes":
            return "分钟"
        case "小时", "Hour", "Hours":
            return "小时"
        case "天", "Day", "Days":
            return "天"
        case "具体时间", "Specific Time":
            return "具体时间"
        case "时间变量", "Time Variable":
            return "时间变量"
        default:
            return u == "" ? "分钟" : u
    }
}

WaitCalcTargetTime(tableItem, index, Data) {
    unit := WaitNormDateUnit(Data.Param2)
    raw := WaitResolveText(tableItem, index, Data.Param1)
    switch unit {
        case "分钟", "小时", "天":
            raw := Trim(String(raw))
            if (!IsNumber(raw))
                return ""
            span := unit == "分钟" ? "Minutes" : (unit == "小时" ? "Hours" : "Days")
            return DateAdd(A_Now, Integer(raw), span)
        case "具体时间":
            return WaitParseDateTime(raw)
        case "时间变量":
            v := ""
            name := Trim(String(Data.Param1))
            found := false
            if (InStr(name, "{")) {
                v := GetReplaceVarText(tableItem, index, name)
                found := v != ""
            } else if (TryGetTabVarValue(&v, tableItem, index, name, false)
                || TryGetTabVarValue(&v, tableItem, index, GetVarName(name), false))
                found := true
            if (!found)
                return ""
            if (IsNumber(v)) {
                n := Integer(v)
                if (n > 9999999999)
                    n := n // 1000
                return DateAdd("19700101000000", n, "Seconds")
            }
            return WaitParseDateTime(String(v))
    }
    return ""
}

; 解析为 YYYYMMDDHH24MISS。仅时刻（8:00）且已过，则取下一天。
WaitParseDateTime(s) {
    s := Trim(s)
    if (s == "")
        return ""
    if (RegExMatch(s, "^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$", &tm)) {
        target := Format("{}{:02}{:02}{:02}", A_YYYY A_MM A_DD, tm[1], tm[2], (tm.Count >= 3 && tm[3] != "") ? tm[3] : 0)
        if (target <= A_Now)
            target := DateAdd(target, 1, "Days")
        return target
    }
    digits := RegExReplace(s, "\D")
    if (StrLen(digits) >= 14)
        return SubStr(digits, 1, 14)
    if (StrLen(digits) == 8)
        return digits "000000"
    if (RegExMatch(s, "(\d{4})[-/年. ](\d{1,2})[-/月. ](\d{1,2})", &m)) {
        y := m[1]
        mo := Format("{:02}", m[2])
        d := Format("{:02}", m[3])
        h := "00", mi := "00", se := "00"
        if (RegExMatch(s, "(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?", &mt)) {
            h := Format("{:02}", mt[1])
            mi := Format("{:02}", mt[2])
            se := (mt.Count >= 3 && mt[3] != "") ? Format("{:02}", mt[3]) : "00"
        }
        return y mo d h mi se
    }
    return ""
}

WaitHintText(waitType) {
    switch CmdEnumWait(waitType) {
        case "等待鼠标移动":
            return "鼠标相对开始等待时的位置发生移动后继续"
        case "等待鼠标停止移动":
            return "鼠标保持不动达到一个检测间隔后继续"
        case "等待剪切板变化":
            return "剪切板内容发生变化后继续"
    }
    return ""
}
