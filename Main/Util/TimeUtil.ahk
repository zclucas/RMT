#Requires AutoHotkey v2.0

; =====================================================================
; 时间指令执行端 —— 5 种子模式
;   1. 指定时刻等待
;   2. 时间区间判断
;   3. 获取时间变量  (Param1=目标变量名, Param2=来源时间变量/可选)
;   4. 获取时间字符串 (Param1=目标变量名, Param2=来源时间变量/可选, Param3=格式模板)
;   5. 时间计算      (Param1=时间变量1, Param2=时间变量2/偏移, Param3=操作, Param4=目标变量, Param5=单位)
; =====================================================================

OnTimeData(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    if (!IsObject(Data))
        return

    subMode := Integer(Data.SubMode)
    switch subMode {
        case 1: ; 指定时刻等待
            TimeExecWaitUntil(tableItem, index, Data)
        case 2: ; 时间区间判断
            TimeExecWindowCheck(tableItem, index, Data)
        case 3: ; 获取时间变量
            TimeExecGetTimeVar(tableItem, index, Data)
        case 4: ; 获取时间字符串
            TimeExecGetTimeStr(tableItem, index, Data)
        case 5: ; 时间计算
            TimeExecTimeMath(tableItem, index, Data)
    }
}

; ---------- 模式1：指定时刻等待 / 相对等待 ----------

TimeExecWaitUntil(tableItem, index, Data) {
    targetTime := TimeCalcTargetDateTime(tableItem, index, Data)
    if (targetTime == "")
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
        if (A_Now >= targetTime)
            return

        ; 超时检查
        if (timeoutMs > 0 && (A_TickCount - startTick >= timeoutMs))
            return

        floatInterval := GetFloatTime(checkInterval, MainSoftData.PreIntervalFloat)
        InterruptibleSleep(tableItem, index, floatInterval)
    }
}

TimeCalcTargetDateTime(tableItem, index, Data) {
    param1Val := GetReplaceVarText(tableItem, index, Data.Param1)
    unit := Data.Param2

    switch unit {
        case "秒", "Seconds":
            secs := IsNumber(param1Val) ? Integer(param1Val) : 0
            return DateAdd(A_Now, secs, "Seconds")
        case "分钟", "Minutes":
            mins := IsNumber(param1Val) ? Integer(param1Val) : 0
            return DateAdd(A_Now, mins, "Minutes")
        case "小时", "Hours":
            hrs := IsNumber(param1Val) ? Integer(param1Val) : 0
            return DateAdd(A_Now, hrs, "Hours")
        case "天", "Days":
            days := IsNumber(param1Val) ? Integer(param1Val) : 0
            return DateAdd(A_Now, days, "Days")
        case "具体时间", "SpecificTime":
            return TimeParseDateTime(param1Val)
        case "时间变量", "TimeVariable":
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
        if (len <= 10)
            return DateAdd("19700101000000", Integer(s), "Seconds")
        if (len == 13)
            return DateAdd("19700101000000", Integer(SubStr(s, 1, 10)), "Seconds")
    }

    ; 2. 纯时刻格式：14:30:00, 14:30, 14点30分, 14点30分00秒
    if (RegExMatch(s, "^(\d{1,2})[:点时](\d{1,2})(?:[:分](\d{1,2}))?", &mt)) {
        h := Format("{:02}", mt[1])
        mi := Format("{:02}", mt[2])
        se := (mt.Count >= 3 && mt[3] != "") ? Format("{:02}", mt[3]) : "00"
        todayTime := SubStr(A_Now, 1, 8) h mi se
        ; 如果当天目标时间已过，自动顺延至明天同一时间
        if (A_Now > todayTime)
            return DateAdd(todayTime, 1, "Days")
        return todayTime
    }

    ; 3. 年月日 + 时分秒：2026-09-19 14:30:00 / 2026/09/19 14:30 / 2026年09月19日 14点30分
    if (RegExMatch(s, "(\d{4})[-/年. ](\d{1,2})[-/月. ](\d{1,2})", &m)) {
        y := m[1]
        mo := Format("{:02}", m[2])
        d := Format("{:02}", m[3])
        h := "00", mi := "00", se := "00"
        if (RegExMatch(s, "(\d{1,2})[:点时](\d{1,2})(?:[:分](\d{1,2}))?", &mt)) {
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
TimeFormatResult(stamp, formatType) {
    if (stamp == "")
        return ""
    switch formatType {
        case "UnixTimestamp":
            return DateDiff(stamp, "19700101000000", "Seconds")
        case "E":
            w := FormatTime(stamp, "WDay")
            return w == 1 ? 7 : w - 1
        case "EEEE":
            return FormatTime(stamp, "dddd")
        case "EEE":
            return FormatTime(stamp, "ddd")
        case "", "原始格式", "Raw":
            return FormatTime(stamp, "yyyy-MM-dd HH:mm:ss")
        default:
            try {
                return FormatTime(stamp, formatType)
            } catch {
                return FormatTime(stamp, "yyyy-MM-dd HH:mm:ss")
            }
    }
}

TimeToAhkStamp(s) {
    s := Trim(s)
    if (s == "")
        return ""
    return TimeParseDateTime(s)
}

; ---------- 模式2：时间区间判断 ----------

TimeExecWindowCheck(tableItem, index, Data) {
    startTime := Data.Param1
    endTime := Data.Param2
    allowDays := Data.Param3 != "" ? Data.Param3 : "1,2,3,4,5,6,7"
    mismatchAction := Data.Param4 != "" ? Data.Param4 : "跳过"

    startStamp := TimeParseDateTime(startTime)
    endStamp := TimeParseDateTime(endTime)
    if (startStamp == "" || endStamp == "")
        return

    nowDayOfWeek := A_WDay == 1 ? 7 : (A_WDay - 1)  ; AHK: 1=Sun → convert to 1=Mon
    dayOk := InStr("," allowDays ",", "," nowDayOfWeek ",")

    nowInWindow := (A_Now >= startStamp && A_Now <= endStamp)
    inWindow := dayOk && nowInWindow

    if (inWindow)
        return

    switch mismatchAction {
        case "跳过", "Skip":
            return
        case "停止", "Stop":
            KillTableItemMacro(tableItem, index)
        case "等待", "Wait":
            Loop {
                WaitIfPaused(tableItem, index)
                item := tableItem.Items[index]
                if (item.Killed)
                    return
                nowDayOfWeek2 := A_WDay == 1 ? 7 : (A_WDay - 1)
                dayOk2 := InStr("," allowDays ",", "," nowDayOfWeek2 ",")
                if (dayOk2 && A_Now >= startStamp && A_Now <= endStamp)
                    return
                InterruptibleSleep(tableItem, index, 1000)
            }
    }
}

; ---------- 模式3：获取时间变量 ----------
; Param1 = 目标变量名
; Param2 = 来源时间（可为变量名、时间字符串、空=当前时间）

TimeExecGetTimeVar(tableItem, index, Data) {
    varName := GetVarName(Trim(Data.Param1))
    if (varName == "")
        return

    srcParam := Trim(Data.Param2)
    if (srcParam != "") {
        srcVal := GetReplaceVarText(tableItem, index, srcParam)
        stamp := TimeToAhkStamp(srcVal)
    } else {
        stamp := ""
    }
    if (stamp == "")
        stamp := A_Now

    ; 时间变量存储为标准格式字符串 "yyyy-MM-dd HH:mm:ss"
    outVal := FormatTime(stamp, "yyyy-MM-dd HH:mm:ss")
    MySetGlobalVariable([varName], [outVal], false)
}

; ---------- 模式4：获取时间字符串 ----------
; Param1 = 目标变量名
; Param2 = 来源时间（可为变量名、时间字符串、空=当前时间）
; Param3 = 格式化模板

TimeExecGetTimeStr(tableItem, index, Data) {
    varName := GetVarName(Trim(Data.Param1))
    if (varName == "")
        return

    srcParam := Trim(Data.Param2)
    if (srcParam != "") {
        srcVal := GetReplaceVarText(tableItem, index, srcParam)
        stamp := TimeToAhkStamp(srcVal)
    } else {
        stamp := ""
    }
    if (stamp == "")
        stamp := A_Now

    formatTemplate := Data.Param3 != "" ? Data.Param3 : "yyyy-MM-dd HH:mm:ss"
    outStr := TimeFormatResult(stamp, formatTemplate)
    MySetGlobalVariable([varName], [outStr], false)
}

; ---------- 模式5：时间计算 ----------
; Param1 = 时间变量1（或时间字符串）
; Param2 = 时间变量2 / 数值偏移
; Param3 = 操作 (差值 / 增加 / 减少)
; Param4 = 保存变量名
; Param5 = 单位/格式 (秒 / 毫秒 / 分钟 / 小时 / 天 / HH:mm:ss)

TimeExecTimeMath(tableItem, index, Data) {
    src1 := GetReplaceVarText(tableItem, index, Data.Param1)
    src2 := GetReplaceVarText(tableItem, index, Data.Param2)
    opType := Data.Param3 != "" ? Data.Param3 : "差值" ; 差值 / 增加 / 减少
    targetVar := GetVarName(Trim(Data.Param4))
    unit := Data.Param5 != "" ? Data.Param5 : "秒" ; 秒 / 毫秒 / 分钟 / 小时 / 天 / HH:mm:ss 等

    if (targetVar == "")
        return

    result := ""

    if (opType == "差值" || opType == "Diff") {
        ; 计算两个时间之差 (src1 - src2)
        t1 := TimeToAhkStamp(src1)
        t2 := TimeToAhkStamp(src2)
        if (t1 != "" && t2 != "") {
            diffSec := DateDiff(t1, t2, "Seconds")
            switch unit {
                case "毫秒", "Milliseconds":
                    result := diffSec * 1000
                case "分钟", "Minutes":
                    result := Round(diffSec / 60, 2)
                case "小时", "Hours":
                    result := Round(diffSec / 3600, 2)
                case "天", "Days":
                    result := Round(diffSec / 86400, 2)
                case "HH:mm:ss", "时分秒":
                    absSec := Abs(diffSec)
                    h := Format("{:02}", Floor(absSec / 3600))
                    mi := Format("{:02}", Floor(Mod(absSec, 3600) / 60))
                    se := Format("{:02}", Mod(absSec, 60))
                    result := (diffSec < 0 ? "-" : "") h ":" mi ":" se
                default: ; 秒
                    result := diffSec
            }
        }
    } else if (opType == "增加" || opType == "Add" || opType == "减少" || opType == "Sub") {
        ; 时间增加或减少偏移
        baseTime := TimeToAhkStamp(src1)
        if (baseTime == "")
            baseTime := A_Now

        offsetVal := IsNumber(src2) ? Integer(src2) : 0
        if (opType == "减少" || opType == "Sub")
            offsetVal := -offsetVal

        ahkUnit := "Seconds"
        switch unit {
            case "分钟", "Minutes":
                ahkUnit := "Minutes"
            case "小时", "Hours":
                ahkUnit := "Hours"
            case "天", "Days":
                ahkUnit := "Days"
            default:
                ahkUnit := "Seconds"
        }

        resStamp := DateAdd(baseTime, offsetVal, ahkUnit)
        result := FormatTime(resStamp, "yyyy-MM-dd HH:mm:ss")
    }

    if (result != "") {
        MySetGlobalVariable([targetVar], [result], false)
    }
}

