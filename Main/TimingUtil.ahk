#Requires AutoHotkey v2.0

class TimingScheduler {

    __New(tableIndex) {
        this.tableIndex := tableIndex
        this.heap := MinHeap()
        this.timerFunc := ObjBindMethod(this, "OnTimer")
        this.endCheckTimerFunc := ObjBindMethod(this, "OnEndCheck")
        this.running := false
    }

    Start() {
        if (this.running)
            return

        if (this.tableIndex = "")
            return
        tableItem := MySoftData.TableInfo[this.tableIndex]
        HandleOnSoftStart(tableItem)

        this.running := true

        this.Rebuild()
    }

    Stop() {
        this.running := false
        this.StopTimers()
        this.heap.Clear()
    }

    Suspend() {
        if (!this.running)
            return
        this.running := false
        this.StopTimers()
    }

    Resume() {
        if (this.running)
            return
        this.running := true
        this.ScheduleNext()
        this.ScheduleEndCheck()
    }

    StopTimers() {
        SetTimer(this.timerFunc, 0)
        SetTimer(this.endCheckTimerFunc, 0)
    }

    Rebuild() {
        this.StopTimers()
        this.heap.Clear()

        tableItem := MySoftData.TableInfo[this.tableIndex]
        now := UnixNow()

        for index, _ in tableItem.ModeArr {
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            Data := GetMacroCMDData(tableItem.TimingSerialArr[index])

            nextTime := CalculateNextStamp(Data, now)
            if (nextTime)
                this.heap.Push({ time: nextTime, index: index })
        }

        this.ScheduleNext()
        this.ScheduleEndCheck()
    }

    ScheduleNext() {
        if (!this.running || this.heap.IsEmpty())
            return

        next := this.heap.Peek()
        delay := (next.time - UnixNow()) * 1000
        this.SetOneShotTimer(this.timerFunc, delay)
    }

    ScheduleEndCheck() {
        if (!this.running) {
            SetTimer(this.endCheckTimerFunc, 0)
            return
        }

        tableItem := MySoftData.TableInfo[this.tableIndex]
        now := UnixNow()
        nextEnd := 0

        for index, _ in tableItem.ModeArr {
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            if (index <= tableItem.ColorStateArr.Length && tableItem.ColorStateArr[index] == 3)
                continue

            Data := GetMacroCMDData(tableItem.TimingSerialArr[index])
            if (!Data.HasOwnProp("EndStamp") || !Data.EndStamp)
                continue

            if (!nextEnd || Data.EndStamp < nextEnd)
                nextEnd := Data.EndStamp
        }

        if (!nextEnd) {
            SetTimer(this.endCheckTimerFunc, 0)
            return
        }

        delay := (nextEnd - now) * 1000
        this.SetOneShotTimer(this.endCheckTimerFunc, delay)
    }

    SetOneShotTimer(timerFunc, delayMs) {
        if (delayMs < 1)
            delayMs := 1
        else if (delayMs > 2147483647)
            delayMs := 2147483647 ; SetTimer 可用的最大毫秒數上限

        SetTimer(timerFunc, -delayMs)
    }

    OnTimer() {
        if (!this.running)
            return

        tableItem := MySoftData.TableInfo[this.tableIndex]
        now := UnixNow()

        while (!this.heap.IsEmpty()) {
            next := this.heap.Peek()
            if (next.time > now)
                break

            item := this.heap.Pop()
            index := item.index

            Data := GetMacroCMDData(tableItem.TimingSerialArr[index])

            if (Data.HasOwnProp("EndStamp") && now >= Data.EndStamp)
                continue

            shouldTrigger := true

            if ((frontInfo := GetItemFrontInfo(tableItem, index)) != "") {
                if (!MyMouseInfo.CheckIfMatch(frontInfo, true))
                    shouldTrigger := false
            }

            if (shouldTrigger)
                TriggerMacroHandler(this.tableIndex, index)

            nextTime := CalculateNextStamp(Data, item.time)
            if (nextTime)
                this.heap.Push({ time: nextTime, index: index })
        }

        this.ScheduleNext()
    }

    OnEndCheck() {
        if (!this.running)
            return

        tableItem := MySoftData.TableInfo[this.tableIndex]
        now := UnixNow()

        for index, _ in tableItem.ModeArr {
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            if (index <= tableItem.ColorStateArr.Length && tableItem.ColorStateArr[index] == 3)
                continue

            Data := GetMacroCMDData(tableItem.TimingSerialArr[index])

            if (!Data.HasOwnProp("EndStamp") || now < Data.EndStamp)
                continue

            if (index <= tableItem.IsWorkIndexArr.Length && tableItem.IsWorkIndexArr[index] != 0)
                MyStopMacro(this.tableIndex, index)
        }

        ; 只在真正需要時重新搜尋下一個 EndStamp，避免每秒掃描
        this.ScheduleEndCheck()
    }
}

class MinHeap {

    __New() {
        this.heap := []
    }

    Push(item) {
        this.heap.Push(item)
        this._Up(this.heap.Length)
    }

    Pop() {
        if (this.heap.Length = 0)
            return ""

        if (this.heap.Length = 1)
            return this.heap.Pop()

        top := this.heap[1]
        this.heap[1] := this.heap.Pop()
        this._Down(1)
        return top
    }

    Peek() {
        return this.heap.Length ? this.heap[1] : ""
    }

    IsEmpty() {
        return this.heap.Length = 0
    }

    Clear() {
        this.heap := []
    }

    _Up(i) {
        while (i > 1) {
            p := i // 2
            if (this.heap[i].time < this.heap[p].time)
                this._Swap(i, p), i := p
            else
                break
        }
    }

    _Down(i) {
        len := this.heap.Length
        while (i * 2 <= len) {
            c := i * 2
            if (c + 1 <= len && this.heap[c + 1].time < this.heap[c].time)
                c++

            if (this.heap[c].time < this.heap[i].time)
                this._Swap(i, c), i := c
            else
                break
        }
    }

    _Swap(a, b) {
        tmp := this.heap[a]
        this.heap[a] := this.heap[b]
        this.heap[b] := tmp
    }
}

CalculateNextStamp(Data, baseStamp) {
    start := Data.StartStamp

    if (baseStamp < start) ; 還沒開始
        return CheckEnd(Data, start)

    switch Data.Type {
        case 1: ; 單次
            return 0
        case 3: ; 週期
            return NextRepeatTime(Data, start, baseStamp)
    }

    return 0
}

NextRepeatTime(Data, start, baseStamp) {
    if (Data.CustomUnit == 6) {
        next := NextMonthTime(start, baseStamp, Data.CustomInterval)
    } else {
        interval := GetTimingInterval(Data)
        next := start + ((baseStamp - start) // interval + 1) * interval
    }

    return CheckEnd(Data, next)
}

NextMonthTime(start, baseStamp, interval) {
    startStr := StampToTimeStr(start)
    baseStr := StampToTimeStr(baseStamp)

    monthsDiff := DateDiff(baseStr, startStr, "Months")
    nextStr := DateAdd(startStr, ((monthsDiff // interval) + 1) * interval, "Months")
    return TimeStrToStamp(nextStr)
}

CheckEnd(Data, nextTime) {
    return (Data.HasOwnProp("EndStamp") && nextTime >= Data.EndStamp) ? 0 : nextTime
}

UnixNow() {
    return DateDiff(A_Now, "19700101000000", "Seconds")
}

TimeStrToStamp(timeStr) {
    return DateDiff(timeStr, "19700101000000", "Seconds")
}

StampToTimeStr(stamp) {
    return DateAdd("19700101000000", stamp, "Seconds")
}

GetTimingInterval(Data) {
    static IntervalMap := [1, 60, 3600, 86400, 604800] ; 秒 分 時 天 週
    return Data.CustomInterval * IntervalMap[Data.CustomUnit]
}

TimingCheckItemIfValid(tableItem, index) {
    return (index <= tableItem.MacroArr.Length)
        && (tableItem.MacroArr[index] != "")
        && (index > tableItem.ForbidArr.Length || !tableItem.ForbidArr[index])
        && !GetItemFoldForbidState(tableItem, index)
}

HandleOnSoftStart(tableItem) {
    if (MainSoftData.IsReload)
        return

    for index, _ in tableItem.ModeArr {
        if (!TimingCheckItemIfValid(tableItem, index))
            continue

        Data := GetMacroCMDData(tableItem.TimingSerialArr[index])
        if (Data.Type == 2)
            TriggerMacroHandler(tableItem.Index, index)
    }
}