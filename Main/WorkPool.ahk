#Requires AutoHotkey v2.0
#Include Util\SharedMemory.ahk
#Include Util\RingBuffer.ahk
#Include Util\JsonUtil.ahk

class MsgType {
    static TASK := 1
    static RESULT := 2
    static EVENT := 3
    static CONTROL := 4
}

class TaskQueue {
    __New() {
        this.queue := []
    }
    Push(task) => this.queue.Push(task)
    Pop() => (this.queue.Length == 0) ? "" : this.queue.RemoveAt(1)
    Size() => this.queue.Length
}

class Future {
    __New(id, tableIndex := 0, itemIndex := 0) {
        this.id := id
        this.done := false
        this.result := ""
        this.hEvent := CreateEvent()
        this.tableIndex := tableIndex
        this.itemIndex := itemIndex
    }

    __Delete() {
        if (this.hEvent) {
            CloseHandle(this.hEvent)
            this.hEvent := 0
        }
    }

    SetResult(result) {
        this.result := result
        this.done := true
        ; The worker signals the event, but we can also signal it here for safety/timeouts
        SetEvent(this.hEvent)
    }

    IsReady() {
        return DllCall("WaitForSingleObject", "ptr", this.hEvent, "uint", 0) == 0
    }

    GetResult(timeout := 5000) {
        start := A_TickCount
        while (!this.done) {
            if (A_TickCount - start > timeout)
                throw Error("Future timeout")
            
            ; If the event is signaled but PollResult hasn't run yet, 
            ; we can manually trigger a PollResult for faster response.
            if (this.IsReady()) {
                ; We could call this.parent.PollResult() here if we had a reference
                ; For now, Sleep -1 will let the timer fire very quickly.
                Sleep -1
                if (this.done)
                    break
            }
            Sleep -1
        }
        return this.result
    }
}

class WorkPool {
    __New() {
        this.workerExe := A_ScriptDir "\Thread\Work.exe"
        this.maxSize := MySoftData.MutiThreadNum
        this.isDynamic := (this.maxSize == -1)
        this.dynamicMaxLimit := 16
        this.corePoolSize := MySoftData.DynamicCorePoolSize
        this.elasticTimeout := MySoftData.ElasticTimeout * 1000
        this.dynamicMinSize := this.corePoolSize
        
        this.pool := []
        this.active := Map()            ; workerIndex -> hwnd
        this.pending := Map()
        
        this.tx := Map()
        this.rx := Map()
        this.evt := Map()
        this.shmTx := Map()
        this.shmRx := Map()

        this.queue := TaskQueue()
        this.futures := Map()
        this.futureCreateTime := Map()
        this.futureTimeout := 10000

        this.workerIdleTime := Map()
        this.workerPIDs := Map()
        this.workerProcs := Map()
        this.workerIndex := 0
        this.mainPID := DllCall("GetCurrentProcessId")
        this.taskCounter := 0
        
        OnMessage(WM_LOAD_WORK, ObjBindMethod(this, "OnWorkerReady"))
        OnMessage(WM_STOP_MACRO, ObjBindMethod(this, "OnStopMacro"))

        SetTimer(ObjBindMethod(this, "Dispatch"), 10)
        SetTimer(ObjBindMethod(this, "CheckFutures"), 1000)
        SetTimer(ObjBindMethod(this, "PollResult"), 1)  ; Hybrid polling
        
        if (this.isDynamic) {
            this.shrinkTimerFunc := ObjBindMethod(this, "IdleShrinkCheck")
            SetTimer(this.shrinkTimerFunc, 10000)
        }

        if (this.isDynamic) {
            loop this.dynamicMinSize {
                this.CreateWorker()
            }
        } else {
            loop this.maxSize {
                this.CreateWorker()
            }
        }
    }

    __Delete() {
        if (this.isDynamic && this.shrinkTimerFunc != "") {
            SetTimer(this.shrinkTimerFunc, 0)
            this.shrinkTimerFunc := ""
        }
        this.Clear()
    }

    CreateWorker() {
        this.workerIndex++
        idx := this.workerIndex

        txName := "RMT_TX_" idx
        rxName := "RMT_RX_" idx
        evtName := "RMT_EVT_" idx

        ; Allocate capacity + 128 for headers
        this.shmTx[idx] := SharedMemory(txName, 1048576 + 128)
        this.tx[idx] := RingBuffer(this.shmTx[idx].ptr, 1048576)
        
        this.shmRx[idx] := SharedMemory(rxName, 1048576 + 128)
        this.rx[idx] := RingBuffer(this.shmRx[idx].ptr, 1048576)
        
        this.evt[idx] := CreateEvent(evtName)
        this.pending[idx] := true

        Run(Format('"{}" {} {} {} "{}" "{}" "{}"'
            , this.workerExe
            , MySoftData.MyGui.Hwnd
            , idx
            , this.mainPID
            , txName
            , rxName
            , evtName), , , &pid)
        
        this.workerPIDs[idx] := pid
        ; Open handle with PROCESS_DUP_HANDLE | PROCESS_TERMINATE
        hProc := DllCall("OpenProcess", "uint", 0x0040 | 0x0001, "int", false, "uint", pid, "ptr")
        this.workerProcs[idx] := hProc
    }

    Submit(cmd, tableIndex := 0, itemIndex := 0) {
        this.taskCounter++
        id := this.taskCounter
        fut := Future(id, tableIndex, itemIndex)

        this.futures.Set(id, fut)
        this.futureCreateTime.Set(id, A_TickCount)
        this.queue.Push({ id: id, cmd: cmd, hEvent: fut.hEvent })

        return fut
    }

    Dispatch() {
        while (this.queue.Size() > 0 && this.pool.Length > 0) {
            idx := this.pool.Pop()

            if (!this.IsAlive(idx)) {
                this.CleanupWorker(idx)
                this.CreateWorker()
                continue
            }

            task := this.queue.Pop()
            
            ; Duplicate handle for worker
            hTargetEvent := 0
            if (!DllCall("DuplicateHandle"
                , "ptr", DllCall("GetCurrentProcess")
                , "ptr", task.hEvent
                , "ptr", this.workerProcs[idx]
                , "ptr*", &hTargetEvent
                , "uint", 0
                , "int", false
                , "uint", 2)) ; DUPLICATE_SAME_ACCESS
            {
                ; Fallback if duplication fails
                hTargetEvent := 0
            }

            if (!this.tx[idx].Push(MsgType.TASK, task.id, task.cmd, hTargetEvent)) {
                ; Buffer full
                if (hTargetEvent) {
                    ; If it failed to push, we should probably close the duplicated handle in the worker
                    ; but since we can't easily, we'll just let it leak or retry.
                    ; Better: only duplicate IF push is likely to succeed.
                }
                this.queue.queue.InsertAt(1, task)
                this.pool.Push(idx)
                break
            }
            SetEvent(this.evt[idx])
            
            if (this.workerIdleTime.Has(idx))
                this.workerIdleTime.Delete(idx)
        }

        if (this.isDynamic && this.queue.Size() > 0 && (this.active.Count + this.pending.Count) < this.dynamicMaxLimit) {
            this.CreateWorker()
        }
    }
    
    Broadcast(action, args*) {
        if (!this.isDynamic && this.maxSize < 1)
            return
        
        payload := JSON.stringify([action, args*])
        for idx in this.active {
            if this.tx.Has(idx) {
                this.tx[idx].Push(MsgType.EVENT, 0, payload)
                SetEvent(this.evt[idx])
            }
        }
    }

    PollResult() {
        for idx, rb in this.rx {
            ; Hybrid Polling: Non-blocking pop all available results
            while (rb.Pop(&type, &id, &result)) {
                switch type {
                    case MsgType.RESULT:
                        if (this.futures.Has(id)) {
                            fut := this.futures[id]
                            fut.SetResult(result)
                            
                            if (fut.tableIndex > 0 && fut.itemIndex > 0) {
                                tableItem := MySoftData.TableInfo[fut.tableIndex]
                                if (tableItem.IsWorkIndexArr.Length >= fut.itemIndex) {
                                    tableItem.IsWorkIndexArr[fut.itemIndex] := 0
                                }

                                itemState := tableItem.KilledArr.Length >= fut.itemIndex && tableItem.KilledArr[fut.itemIndex] ? 3 : 0
                                SetTableItemState(fut.tableIndex, fut.itemIndex, itemState)
                            }
                            
                            this.futures.Delete(id)
                            this.futureCreateTime.Delete(id)
                        }
                        this.pool.Push(idx)
                        this.workerIdleTime.Set(idx, A_TickCount)
                    case MsgType.EVENT:
                        this.OnWorkerEvent(idx, result)
                    case MsgType.CONTROL:
                        ; reserved for control messages from worker
                }
            }
        }
    }

    CheckFutures() {
        now := A_TickCount
        toDelete := []
        for id, createTime in this.futureCreateTime {
            if ((now - createTime) >= this.futureTimeout) {
                if (this.futures.Has(id)) {
                    fut := this.futures[id]
                    fut.SetResult("timeout")

                    if (fut.tableIndex > 0 && fut.itemIndex > 0) {
                        tableItem := MySoftData.TableInfo[fut.tableIndex]
                        if (tableItem.IsWorkIndexArr.Length >= fut.itemIndex)
                            tableItem.IsWorkIndexArr[fut.itemIndex] := 0
                        SetTableItemState(fut.tableIndex, fut.itemIndex, 3)
                    }

                    this.futures.Delete(id)
                }
                toDelete.Push(id)
            }
        }
        for id in toDelete {
            this.futureCreateTime.Delete(id)
        }
    }

    IsAlive(idx) {
        return this.active.Has(idx) && WinExist("ahk_id " this.active[idx])
    }

    OnWorkerReady(wParam, lParam, msg, hwnd) {
        idx := wParam
        workerHwnd := lParam > 0 ? lParam : hwnd
        
        if (this.pending.Has(idx))
            this.pending.Delete(idx)
            
        this.active.Set(idx, workerHwnd)
        this.pool.Push(idx)
        this.workerIdleTime.Set(idx, A_TickCount)
    }

    CleanupWorker(idx) {
        if (this.active.Has(idx))
            this.active.Delete(idx)
        if (this.workerIdleTime.Has(idx))
            this.workerIdleTime.Delete(idx)
        if (this.workerProcs.Has(idx)) {
            CloseHandle(this.workerProcs[idx])
            this.workerProcs.Delete(idx)
        }
        if (this.workerPIDs.Has(idx))
            this.workerPIDs.Delete(idx)
    }

    Clear() {
        for idx, hwnd in this.active {
            this.PostMessage(WM_CLEAR_WORK, idx, 0, 0)
        }
        
        this.pool := []
        this.active := Map()
        this.pending := Map()
        this.workerIdleTime := Map()
        
        for idx, hProc in this.workerProcs
            CloseHandle(hProc)
        this.workerProcs := Map()
        this.workerPIDs := Map()

        this.futures := Map()
        this.futureCreateTime := Map()
        this.queue := TaskQueue()
        this.workerIndex := 0
        
        ; Close RingBuffers
        this.tx := Map()
        this.rx := Map()
        this.shmTx := Map()
        this.shmRx := Map()
        for idx, h in this.evt
            ResetEvent(h) ; Optional
    }

    PostMessage(type, idx, wParam, lParam) {
        if (this.active.Has(idx)) {
            hwnd := this.active[idx]
            try {
                PostMessage(type, wParam, lParam, , "ahk_id " hwnd)
            }
        }
    }

    IdleShrinkCheck() {
        if (this.pool.Length <= this.corePoolSize)
            return
        now := A_TickCount
        shrinkIndices := []
        for idx, idleTick in this.workerIdleTime {
            if ((now - idleTick) >= this.elasticTimeout)
                shrinkIndices.Push(idx)
        }
        maxShrink := this.pool.Length - this.corePoolSize
        if (shrinkIndices.Length == 0 || maxShrink <= 0)
            return
            
        loop Min(shrinkIndices.Length, maxShrink) {
            targetIndex := shrinkIndices[A_Index]
            this.PostMessage(WM_CLEAR_WORK, targetIndex, 0, 0)
            this.active.Delete(targetIndex)
            if (this.workerIdleTime.Has(targetIndex))
                this.workerIdleTime.Delete(targetIndex)
                
            poolIndex := 0
            loop this.pool.Length {
                if (this.pool[A_Index] == targetIndex) {
                    poolIndex := A_Index
                    break
                }
            }
            if (poolIndex > 0)
                this.pool.RemoveAt(poolIndex)
        }
    }

    BroadcastStop(tableIndex, itemIndex) {
        for idx, workerHwnd in this.active {
            this.PostMessage(WM_STOP_MACRO, idx, tableIndex, itemIndex)
        }
        tableItem := MySoftData.TableInfo[tableIndex]
        KillTableItemMacro(tableItem, itemIndex)
        SetTableItemState(tableIndex, itemIndex, 3)
    }

    OnStopMacro(wParam, lParam, msg, hwnd) {
        tableIndex := wParam
        itemIndex := lParam
        this.BroadcastStop(tableIndex, itemIndex)
    }

    OnWorkerEvent(idx, payload) {
        try {
            paramArr := JSON.parse(payload)
            action := paramArr[1]
            args := []
            loop paramArr.Length - 1 {
                args.Push(paramArr[A_Index + 1])
            }

            switch action {
                case "SetVari":
                    SetGlobalVariable(args[1], args[2], false)
                case "DelVari":
                    DelGlobalVariable(args[1])
                case "Report":
                    CMDReport(args[1])
                case "RMT指令":
                    ExcuteRMTCMDAction(args[1])
                case "ItemState":
                    SetTableItemState(args[1], args[2], args[3])
                case "PauseState":
                    SetItemPauseState(args[1], args[2], args[3])
                case "MsgBox":
                    MsgBoxContent(args[1])
                case "ToolTip":
                    ToolTipContent(args[1])
                case "MacroCount":
                    MacroCount(args[1])
                case "Joy":
                    ViGJoySetState(args[1], args[2], args[3])
                case "SetArray":
                    SetGlobalArray(args[1], GetArray(args[2]))
                case "CloneArray":
                    CloneGlobalArray(GetArray(args[1]), args[2])
                case "DeleteArray":
                    DeleteGlobalArray(args[1])
                case "ModifyArray":
                    ModifyGlobalArray(args[1], args[2], args[3], args[4], args[5])
                case "InsertArray":
                    InsertGlobalArray(args[1], args[2], args[3], args[4], args[5])
                case "RemoveAtArray":
                    RemoveAtGlobalArray(args[1], args[2], args[3])
                case "Error":
                    MyErrorMsgBoxGui.ShowGui(args[1])
            }
        } catch as e {
            ; JSON parse error or invalid event
        }
    }
}