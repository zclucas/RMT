#Requires AutoHotkey v2.0

UnixNow() {
    localTime := Buffer(16)
    DllCall("GetLocalTime", "Ptr", localTime)
    stamp := Format("{:04}{:02}{:02}{:02}{:02}{:02}", NumGet(localTime, 0, "UShort"),
        NumGet(localTime, 2, "UShort"), NumGet(localTime, 6, "UShort"), NumGet(localTime, 8, "UShort"),
        NumGet(localTime, 10, "UShort"), NumGet(localTime, 12, "UShort"))
    return TimeStrToStamp(stamp) + NumGet(localTime, 14, "UShort")
}

TimeStrToStamp(timeStr) {
    return DateDiff(timeStr, "19700101000000", "Seconds") * 1000
}

StampToTimeStr(stamp) {
    return DateAdd("19700101000000", stamp // 1000, "Seconds")
}

TimeEpochMilliseconds(value) {
    value := Trim(value)
    if (!RegExMatch(value, "^[0-9]{1,13}\z") || StrLen(value) == 8)
        return ""
    return StrLen(value) <= 10 ? Integer(value) * 1000 : Integer(value)
}

; =====================================================================
; 时间指令执行端
;   SubMode 中文：等待 / 区间判断 / 倒计时
;   使用当前语义键，不读取预览版数字模式。
; =====================================================================

OnTimeData(tableItem, cmd, index) {
    Data := GetMacroCMDData(StrSplit(cmd, "_")[1])
    switch TimeNormSubMode(Data) {
        case "等待": TimeExecWaitUntil(tableItem, index, Data)
        case "区间判断": TimeExecWindowCheck(tableItem, index, Data)
    }
}

TimeCmdKey(serialStr) => GetLangKey(RegExReplace(String(serialStr), "\d+"))

TimeNormSubMode(Data) => TimeNormSubModeVal(Data.SubMode)

TimeNormSubModeVal(raw) => CurrentCommandChoice(raw, ["等待", "区间判断"])

TimeGraphNormSubMode(d) {
    if (GetLangKey(d.type) == "倒计时")
        return "倒计时"
    return CurrentCommandChoice(d.HasOwnProp("timeSub") ? d.timeSub : "等待", ["等待", "区间判断", "倒计时"])
}

; ---------- 模式1：指定时刻等待 / 相对等待 ----------

TimeExecWaitUntil(tableItem, index, Data) {
    targetMs := TimeWaitTargetMilliseconds(tableItem, index, Data)
    targetTime := targetMs == "" ? TimeCalcTargetDateTime(tableItem, index, Data) : ""
    if (targetMs == "" && targetTime == "")
        return

    checkInterval := Integer(Data.CheckInterval > 0 ? Data.CheckInterval : 500)
    timeoutMs := Integer(Data.Timeout > 0 ? Data.Timeout : 0)
    startTick := A_TickCount

    Loop {
        WaitIfPaused(tableItem, index)
        item := tableItem.Items[index]
        if (item.Killed)
            return

        ; 到达目标时间
        remaining := targetMs == "" ? "" : targetMs - UnixNow()
        if (targetMs == "" ? A_Now >= targetTime : remaining <= 0)
            return

        ; 超时检查
        if (timeoutMs > 0 && (A_TickCount - startTick >= timeoutMs))
            return

        floatInterval := RandomizeDurationByPercent(checkInterval, MainSoftData.PreIntervalFloat)
        if (targetMs != "")
            floatInterval := Min(floatInterval, remaining)
        if (timeoutMs > 0)
            floatInterval := Min(floatInterval, Max(1, timeoutMs - (A_TickCount - startTick)))
        InterruptibleSleep(tableItem, index, floatInterval)
    }
}

TimeDurationSeconds(tableItem, index, Data) {
    parts := StrSplit(Trim(String(Data.Param1)), ":")
    if (parts.Length == 3) {
        h := TimeResolveValue(tableItem, index, parts[1])
        m := TimeResolveValue(tableItem, index, parts[2])
        s := TimeResolveValue(tableItem, index, parts[3])
        return TimeParseDurationSecs(h ":" m ":" s, "时长")
    }
    return TimeParseDurationSecs(TimeResolveValue(tableItem, index, Data.Param1), "时长")
}

TimeWaitTargetMilliseconds(tableItem, index, Data) {
    switch TimeNormWaitType(Data.Param2) {
        case "时间戳": return TimeEpochMilliseconds(TimeResolveValue(tableItem, index, Data.Param1))
        case "时长": return UnixNow() + TimeDurationSeconds(tableItem, index, Data) * 1000
    }
    return ""
}

TimeNormWaitType(unit) => CurrentCommandChoice(unit == "" ? "时刻" : unit,
    ["时刻", "时长", "时间戳", "毫秒", "毫秒-随机"])

TimeNormWindowType(unit) => CurrentCommandChoice(unit == "" ? "时刻" : unit, ["时刻", "时间戳"])

TimeNormMismatch(action) => CurrentCommandChoice(action == "" ? "跳过" : action, ["跳过", "等待", "终止"])

TimeParseDurationSecs(val, unit) {
    raw := Trim(String(val))
    u := GetLangKey(Trim(String(unit)))
    if (RegExMatch(raw, "^(-?\d+):(-?\d+):(-?\d+)$", &mt))
        return Integer(mt[1]) * 3600 + Integer(mt[2]) * 60 + Integer(mt[3])
    return IsNumber(raw) ? Integer(raw) : 0
}

; 编辑器既可填写变量名，也可使用 {变量}；字面数值保持原值。
TimeResolveValue(tableItem, index, raw) {
    raw := Trim(String(raw))
    value := GetReplaceVarText(tableItem, index, raw)
    if (value == raw && raw != "" && !IsNumber(raw)
        && TryGetTabVarValue(&resolved, tableItem, index, GetVarName(raw), false))
        return String(resolved)
    return value
}

TimeCalcTargetDateTime(tableItem, index, Data) {
    param1Val := TimeResolveValue(tableItem, index, Data.Param1)
    waitType := TimeNormWaitType(Data.Param2)

    switch waitType {
        case "时长":
            raw := Trim(String(Data.Param1))
            arr := StrSplit(raw, ":")
            if (arr.Length == 3) {
                h := TimeResolveValue(tableItem, index, arr[1])
                m := TimeResolveValue(tableItem, index, arr[2])
                s := TimeResolveValue(tableItem, index, arr[3])
                param1Val := h ":" m ":" s
            }
            secs := TimeParseDurationSecs(param1Val, Data.Param2)
            return DateAdd(A_Now, secs, "Seconds")
        case "时刻":
            return TimeParseDateTime(TimeResolveClock(tableItem, index, Data.Param1))
        case "时间戳":
            valStr := String(param1Val)
            if (valStr == "") {
                rawVarName := GetVarName(Data.Param1)
                v := ""
                if (TryGetTabVarValue(&v, tableItem, index, rawVarName))
                    valStr := String(v)
            }
            if (valStr != "") {
                if (IsNumber(valStr)) {
                    if (StrLen(valStr) <= 10)
                        return DateAdd("19700101000000", Integer(valStr), "Seconds")
                    else if (StrLen(valStr) == 13)
                        return DateAdd("19700101000000", Integer(SubStr(valStr, 1, 10)), "Seconds")
                }
                return TimeParseDateTime(valStr)
            }
            return ""
        default:
            return TimeParseDateTime(param1Val)
    }
}

TimeParseDateTime(s) {
    s := Trim(s)
    if (s == "")
        return ""

    ; 1. 纯数字处理 (14位YYYYMMDDHHMISS / 8位YYYYMMDD / 10位Unix秒 / 13位Unix毫秒)
    if (RegExMatch(s, "^\d+$")) {
        len := StrLen(s)
        if (len == 14)
            return s
        if (len == 8)
            return s "000000"
        ms := TimeEpochMilliseconds(s)
        if (ms != "")
            return StampToTimeStr(ms)
    }

    ; 2. 纯时刻格式：14:30:00, 14:30
    if (RegExMatch(s, "^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?", &mt)) {
        h := Format("{:02}", mt[1])
        mi := Format("{:02}", mt[2])
        se := (mt.Count >= 3 && mt[3] != "") ? Format("{:02}", mt[3]) : "00"
        todayTime := SubStr(A_Now, 1, 8) h mi se
        ; 如果当天目标时间已过，自动顺延至明天同一时间
        if (A_Now > todayTime)
            return DateAdd(todayTime, 1, "Days")
        return todayTime
    }

    ; 3. 年月日 + 时分秒：2026-09-19 14:30:00 / 2026/09/19 14:30
    if (RegExMatch(s, "(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})", &m)) {
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

    ; 4. ISO 8601 标准格式 (2026-09-19T14:30:00Z / 2026-09-19T14:30:00+08:00)
    if (RegExMatch(s, "(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})", &m)) {
        return m[1] m[2] m[3] m[4] m[5] m[6]
    }

    return ""
}

TimeToAhkStamp(s) {
    s := Trim(s)
    if (s == "")
        return ""
    return TimeParseDateTime(s)
}

; ---------- 模式2：时间区间判断 ----------

TimeResolveClock(tableItem, index, raw) {
    raw := Trim(String(TimeResolveValue(tableItem, index, raw)))
    arr := StrSplit(raw, ":")
    if (arr.Length == 3) {
        h := TimeResolveValue(tableItem, index, arr[1])
        m := TimeResolveValue(tableItem, index, arr[2])
        s := TimeResolveValue(tableItem, index, arr[3])
        return Trim(h) ":" Trim(m) ":" Trim(s)
    }
    return GetReplaceVarText(tableItem, index, raw)
}

TimeParseClockOfDay(s) {
    s := Trim(s)
    if (RegExMatch(s, "^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?", &mt)) {
        h := Format("{:02}", Integer(mt[1]))
        mi := Format("{:02}", Integer(mt[2]))
        se := (mt.Count >= 3 && mt[3] != "") ? Format("{:02}", Integer(mt[3])) : "00"
        return SubStr(A_Now, 1, 8) h mi se
    }
    stamp := TimeParseDateTime(s)
    if (stamp == "")
        return ""
    return SubStr(A_Now, 1, 8) SubStr(stamp, 9)
}

TimeNowInClockWindow(startStamp, endStamp) {
    nt := SubStr(A_Now, 9)
    st := SubStr(startStamp, 9)
    et := SubStr(endStamp, 9)
    if (st <= et)
        return nt >= st && nt <= et
    return nt >= st || nt <= et
}

TimeResolveStamp(tableItem, index, raw) {
    raw := Trim(String(TimeResolveValue(tableItem, index, raw)))
    arr := StrSplit(raw, ":")
    if (arr.Length >= 6) {
        y := GetReplaceVarText(tableItem, index, arr[1])
        mo := GetReplaceVarText(tableItem, index, arr[2])
        d := GetReplaceVarText(tableItem, index, arr[3])
        h := GetReplaceVarText(tableItem, index, arr[4])
        mi := GetReplaceVarText(tableItem, index, arr[5])
        s := GetReplaceVarText(tableItem, index, arr[6])
        y := (IsNumber(y) && Integer(y) > 0) ? Integer(y) : Integer(A_Year)
        mo := (IsNumber(mo) && Integer(mo) > 0) ? Integer(mo) : Integer(A_Mon)
        d := (IsNumber(d) && Integer(d) > 0) ? Integer(d) : Integer(A_DD)
        h := IsNumber(h) ? Integer(h) : 0
        mi := IsNumber(mi) ? Integer(mi) : 0
        s := IsNumber(s) ? Integer(s) : 0
        return Format("{:04}{:02}{:02}{:02}{:02}{:02}", y, mo, d, h, mi, s)
    }
    clock := TimeResolveClock(tableItem, index, raw)
    if (arr.Length == 3)
        return TimeParseClockOfDay(clock)
    return TimeParseDateTime(clock)
}

TimeWindowInRange(tableItem, index, Data, outside := false) {
    kind := TimeNormWindowType(Data.Param5)
    if (kind == "时间戳") {
        start := TimeRangeEndpointMilliseconds(tableItem, index, Data.Param1)
        end := TimeRangeEndpointMilliseconds(tableItem, index, Data.Param2)
        if (start == "" || end == "" || start > end)
            return false
        now := UnixNow()
        inRange := now >= start && now <= end
        return outside ? !inRange : inRange
    }
    startStamp := TimeResolveStamp(tableItem, index, Data.Param1)
    endStamp := TimeResolveStamp(tableItem, index, Data.Param2)
    if (startStamp == "" || endStamp == "")
        return false
    if (StrSplit(Trim(String(Data.Param1)), ":").Length >= 6) {
        if (startStamp > endStamp)
            return false
        now := A_Now
        inRange := now >= startStamp && now <= endStamp
    } else
        inRange := TimeNowInClockWindow(startStamp, endStamp)
    return outside ? !inRange : inRange
}

TimeRangeEndpointMilliseconds(tableItem, index, value) {
    ms := TimeEpochMilliseconds(TimeResolveValue(tableItem, index, value))
    if (ms != "")
        return ms
    stamp := TimeResolveStamp(tableItem, index, value)
    return stamp == "" ? "" : TimeStrToStamp(stamp)
}

TimeExecWindowCheck(tableItem, index, Data) {
    mismatchAction := TimeNormMismatch(Data.Param4 != "" ? Data.Param4 : "跳过")
    if (TimeWindowInRange(tableItem, index, Data))
        return

    switch mismatchAction {
        case "跳过":
            return
        case "终止":
            KillTableItemMacro(tableItem, index)
        case "等待":
            Loop {
                WaitIfPaused(tableItem, index)
                item := tableItem.Items[index]
                if (item.Killed)
                    return
                if (TimeWindowInRange(tableItem, index, Data))
                    return
                InterruptibleSleep(tableItem, index, 1000)
            }
    }
}
