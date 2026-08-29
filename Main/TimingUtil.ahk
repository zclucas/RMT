#Requires AutoHotkey v2.0

class TimingScheduler {

    __New(tableID) {
        this.tableID := tableID
        this.heap := MinHeap()
        this.timerFunc := ObjBindMethod(this, "OnTimer")
        this.endCheckTimerFunc := ObjBindMethod(this, "OnEndCheck")
        this.running := false
        ; §17 热重载订阅：定时表配置变更（宏/模块禁用、定时参数、宏内容）→ 空闲时重建调度堆，
        ; 使禁用/启用/改定时保存选「否」后立即生效（不再只靠重启时 Rebuild）
        global MyHotReloadBus
        if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
            MyHotReloadBus.Subscribe(ObjBindMethod(this, "OnConfigChanged"), (t) => this._IsTimingTable(t))
    }

    ; 订阅过滤器：仅关心定时表（t 为 TableInfo 索引；Publish(0,0) 整表变更由总线直通 handler）
    _IsTimingTable(t) {
        global MySoftData
        if (!IsObject(MySoftData) || !MySoftData.HasProp("TableInfo"))
            return false
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return false
        return MySoftData.TableInfo[t].Symbol == "Timing"
    }

    ; §17 热重载回调：重建调度堆（禁用条目移除、启用条目加入、定时参数按新配置重排）
    OnConfigChanged(tableIndex, itemIndex) {
        this.Rebuild()
    }

    ; 表 ID 可能为 ""（include 阶段 TableInfo 未填充）；启动时解析一次
    _ResolveTableID() {
        if (this.tableID == "") {
            t := GetTableBySymbol("Timing")
            this.tableID := t ? t.ID : ""
        }
        return this.tableID
    }

    _GetTable() {
        if (this._ResolveTableID() == "")
            return ""
        return GetTableByID(this.tableID)
    }

    Start() {
        if (this.running)
            return

        tableItem := this._GetTable()
        if (!tableItem)
            return
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

        tableItem := this._GetTable()
        if (!tableItem)
            return
        now := UnixNow()

        for index, item in tableItem.Items {
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            Data := GetMacroCMDData(item.TimingSerial)

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

        tableItem := this._GetTable()
        if (!tableItem)
            return
        now := UnixNow()
        nextEnd := 0

        for index, item in tableItem.Items {
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            if (item.ColorState == 3)
                continue

            Data := GetMacroCMDData(item.TimingSerial)
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

        tableItem := this._GetTable()
        if (!tableItem)
            return
        now := UnixNow()

        while (!this.heap.IsEmpty()) {
            next := this.heap.Peek()
            if (next.time > now)
                break

            item := this.heap.Pop()
            index := item.index
            itemObj := tableItem.Items[index]
            if (!itemObj)
                continue

            ; §17 触发前实时复查：热重载/编辑后残留的排程条目（条目或所属模块被禁用、宏内容被清空）
            ; 不再触发也不再续排，自然从堆中排空（配合总线订阅 Rebuild 双保险）
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            Data := GetMacroCMDData(itemObj.TimingSerial)

            if (Data.HasOwnProp("EndStamp") && now >= Data.EndStamp)
                continue

            shouldTrigger := true

            if ((frontInfo := GetItemFrontInfo(tableItem, index)) != "") {
                if (!MyMouseInfo.CheckIfMatch(frontInfo, true))
                    shouldTrigger := false
            }

            if (shouldTrigger)
                TriggerMacroHandler(tableItem, index)

            nextTime := CalculateNextStamp(Data, item.time)
            if (nextTime)
                this.heap.Push({ time: nextTime, index: index })
        }

        this.ScheduleNext()
    }

    OnEndCheck() {
        if (!this.running)
            return

        tableItem := this._GetTable()
        if (!tableItem)
            return
        now := UnixNow()

        for index, item in tableItem.Items {
            if (!TimingCheckItemIfValid(tableItem, index))
                continue

            if (item.ColorState == 3)
                continue

            Data := GetMacroCMDData(item.TimingSerial)

            if (!Data.HasOwnProp("EndStamp") || now < Data.EndStamp)
                continue

            if (item.IsWorkIndex != 0)
                MyStopMacro(tableItem, index)
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
    item := tableItem.Items[index]
    return item
        && (item.Macro != "")
        && !item.Forbid
        && !GetItemFoldForbidState(tableItem, index)
}

HandleOnSoftStart(tableItem) {
    if (MainSoftData.IsReload)
        return

    for index, item in tableItem.Items {
        if (!TimingCheckItemIfValid(tableItem, index))
            continue

        Data := GetMacroCMDData(item.TimingSerial)
        if (Data.Type == 2)
            TriggerMacroHandler(tableItem, index)
    }
}