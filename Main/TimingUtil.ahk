#Requires AutoHotkey v2.0

global MyTimingScheduler := ""

TimingCheck() {
    if ((tableIndex := GetTimingTableIndex()) == "")
        return

    tableItem := MySoftData.TableInfo[tableIndex]
    HandleOnSoftStart(tableItem)

    global MyTimingScheduler
    if (IsObject(MyTimingScheduler))
        MyTimingScheduler.Stop()

    MyTimingScheduler := TimingScheduler(tableIndex)
    MyTimingScheduler.Start()
}

class TimingScheduler {

    __New(tableIndex) {
        this.tableIndex := tableIndex
        this.heap := MinHeap()
        this.timerFunc := ObjBindMethod(this, "OnTimer")
        this.endCheckTimerFunc := ObjBindMethod(this, "OnEndCheck")
        this.running := false
    }

    Start() {
        this.running := true
        this.Rebuild()
        SetTimer(this.endCheckTimerFunc, 1000)
    }

    Stop() {
        this.running := false
        SetTimer(this.timerFunc, 0)
        SetTimer(this.endCheckTimerFunc, 0)
        this.heap.Clear()
    }

    Rebuild() {
        if (!this.running)
            return

        SetTimer(this.timerFunc, 0)
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
    }

    ScheduleNext() {
        if (!this.running || this.heap.IsEmpty())
            return

        next := this.heap.Peek()

        delay := (next.time - UnixNow()) * 1000
        if (delay < 1)
            delay := 1

        SetTimer(this.timerFunc, -delay)
    }

    OnTimer() {
        if (!this.running)
            return

        tableItem := MySoftData.TableInfo[this.tableIndex]
        now := UnixNow()

        while (!this.heap.IsEmpty() && this.heap.Peek().time <= now) {

            item := this.heap.Pop()
            index := item.index

            Data := GetMacroCMDData(tableItem.TimingSerialArr[index])

            if (Data.EndTime != "" && now >= TimeStrToStamp(Data.EndTime))
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

            if (Data.EndTime == "" || now < TimeStrToStamp(Data.EndTime))
                continue

            if (index <= tableItem.IsWorkIndexArr.Length && tableItem.IsWorkIndexArr[index] != 0)
                MyWorkPool.BroadcastStop(this.tableIndex, index)
        }
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
    start := TimeStrToStamp(Data.StartTime)

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
    ; if (!nextTime) ; 一定會 > 0 所以沒意義
    ;     return 0

    if (Data.EndTime != "" && nextTime >= TimeStrToStamp(Data.EndTime))
        return 0

    return nextTime
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
    IntervalMap := [1, 60, 3600, 86400, 604800] ; 秒 分 時 天 週
    return Data.CustomInterval * IntervalMap[Data.CustomUnit]
}

TimingCheckItemIfValid(tableItem, index) {
    return !GetItemFoldForbidState(tableItem, index)
        && !tableItem.ForbidArr[index]
        && tableItem.MacroArr.Length >= index
        && tableItem.MacroArr[index] != ""
}

HandleOnSoftStart(tableItem) {
    if (MySoftData.IsReload)
        return

    for index, _ in tableItem.ModeArr {
        if (!TimingCheckItemIfValid(tableItem, index))
            continue

        Data := GetMacroCMDData(tableItem.TimingSerialArr[index])
        if (Data.Type == 2)
            TriggerMacroHandler(tableItem.Index, index)
    }
}