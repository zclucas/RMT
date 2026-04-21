#Requires AutoHotkey v2.0

global MyTimingScheduler := ""

TimingCheck() {
    if ((tableIndex := GetTimingTableIndex()) == "")
        return

    tableItem := MySoftData.TableInfo[tableIndex]
    NormalizeTimingData(tableItem)
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
        this.running := false
    }

    Start() {
        this.running := true
        this.Rebuild()
    }

    Stop() {
        this.running := false
        SetTimer(this.timerFunc, 0)
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
            if (Data == "")
                continue

            if (Data.EndStamp && now >= Data.EndStamp)
                continue

            Data.NextStamp := CalculateNextStamp(Data, now)

            if (Data.NextStamp)
                this.heap.Push({ time: Data.NextStamp, index: index })
        }

        this.ScheduleNext()
    }

    ScheduleNext() {
        if (!this.running || this.heap.IsEmpty())
            return

        next := this.heap.Peek()
        now := UnixNow()

        delay := (next.time - now) * 1000
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
            if (Data == "")
                continue

            shouldTrigger := true

            if ((frontInfo := GetItemFrontInfo(tableItem, index)) != "") {
                if (!MyMouseInfo.CheckIfMatch(frontInfo, true))
                    shouldTrigger := false
            }

            Data.NextStamp := CalculateNextStamp(Data, Data.NextStamp)

            if (Data.EndStamp && Data.NextStamp >= Data.EndStamp)
                Data.NextStamp := 0

            if (shouldTrigger)
                TriggerMacroHandler(this.tableIndex, index)

            if (Data.NextStamp)
                this.heap.Push({ time: Data.NextStamp, index: index })
        }

        this.ScheduleNext()
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

NormalizeTimingData(tableItem) {
    for index, _ in tableItem.ModeArr {

        Data := GetMacroCMDData(tableItem.TimingSerialArr[index])
        if (Data == "" || Data.HasOwnProp("StartStamp"))
            continue

        Data.StartStamp := TimeStrToStamp(Data.StartTime)
        Data.EndStamp := Data.EndTime != "" ? TimeStrToStamp(Data.EndTime) : 0
        Data.NextStamp := 0
    }
}

CalculateNextStamp(Data, baseStamp) {
    start := Data.StartStamp
    spanSeconds := baseStamp - start

    switch Data.Type {
        case 1:
            return spanSeconds < 0 ? start : 0

        case 2, 3, 4, 7:
            interval := GetTimingInterval(Data)

            if (spanSeconds < 0)
                return start

            count := Floor(spanSeconds / interval)
            return start + (count + 1) * interval

        case 5:
            if (spanSeconds < 0)
                return start

            t := DateAdd("19700101000000", baseStamp, "Seconds")
            baseStr := FormatTime(t, "yyyyMMddHHmmss")

            timeSuffix := SubStr(Data.StartTime, 7)
            targetStr := SubStr(baseStr, 1, 6) timeSuffix
            target := TimeStrToStamp(targetStr)

            if (baseStamp < target)
                return target

            year := SubStr(baseStr, 1, 4)
            month := Number(SubStr(baseStr, 5, 2))

            ++month
            if (month > 12)
                month := 1, ++year

            nextStr := Format("{:04}{:02}", year, month) timeSuffix
            return TimeStrToStamp(nextStr)

        default:
            return 0
    }
}

UnixNow() {
    return DateDiff(A_Now, "19700101000000", "Seconds")
}

TimeStrToStamp(timeStr) {
    return DateDiff(timeStr, "19700101000000", "Seconds")
}

GetTimingInterval(Data) {
    IntervalMap := Map(2, 3600, 3, 86400, 4, 604800)
    if (IntervalMap.Has(Data.Type))
        return IntervalMap[Data.Type]

    MultiplierMap := [1, 60, 3600, 86400, 604800]
    return Data.CustomInterval * MultiplierMap[Data.CustomUnit]
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
        if (Data != "" && Data.Type == 6)
            TriggerMacroHandler(tableItem.Index, index)
    }
}