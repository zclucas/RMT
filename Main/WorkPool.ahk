#Requires AutoHotkey v2.0
#Include Util\SharedMemory.ahk
#Include Util\RingBuffer.ahk
#Include Util\JsonUtil.ahk

class TaskQueue {
    __New() {
        this.queue := []
    }
    Push(task) => this.queue.Push(task)
    Pop() => (this.queue.Length == 0) ? "" : this.queue.RemoveAt(1)
    Size() => this.queue.Length
}

; Worker 数据封装：每个 Worker 进程的所有相关数据集中管理
class WorkerData {
    __New(idx) {
        this.idx := idx               ; Worker 唯一索引编号（递增分配）

        ; === 进程信息 ===
        this.pid := 0                 ; Worker 进程 PID
        this.hProc := 0               ; Worker 进程句柄（OpenProcess），用于 DuplicateHandle 和终止进程

        ; === 窗口/通信 ===
        this.hwnd := 0                ; Worker 主窗口句柄，用于 PostMessage 发送指令
        this.isPending := true        ; Worker 是否正在启动中（true=启动中，false=已就绪）

        ; === 共享内存通道 ===
        this.shmTx := 0               ; 主进程→Worker 的共享内存对象（SharedMemory）
        this.shmRx := 0               ; Worker→主进程 的共享内存对象（SharedMemory）
        this.tx := 0                  ; 主进程→Worker 的环形缓冲区（RingBuffer），用于发送任务和广播
        this.rx := 0                  ; Worker→主进程 的环形缓冲区（RingBuffer），用于接收结果和事件
        this.hEvt := 0                ; 边沿触发通知用的 Event 句柄

        ; === 状态追踪 ===
        this.idleTick := 0            ; Worker 进入空闲状态的时间戳（A_TickCount），用于弹性缩容判断
        this.tableIndex := 0          ; Worker 当前正在处理的宏所属的表索引（0=空闲）
        this.itemIndex := 0           ; Worker 当前正在处理的宏在表中的项索引（0=空闲）
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

        this.freePool := Map()        ; idx -> WorkerData，空闲可用的 Worker
        this.usePool := Map()         ; idx -> WorkerData，正在执行任务的 Worker
        this.pending := Map()         ; idx -> WorkerData，正在启动尚未就绪的 Worker

        this.taskQueue := TaskQueue()     ; 等待分发的任务队列，每项 {cmd, tableIndex, itemIndex}
        this.mainPID := DllCall("GetCurrentProcessId")
        this.idxCounter := 0          ; Worker 索引计数器（递增，用于分配唯一 idx）
        this.isDispatching := false    ; Dispatch 防重入标志
        this.broadcastExcludeIdx := 0  ; Broadcast 时需要跳过的 Worker idx（发起者自己）

        OnMessage(WM_LOAD_WORK, ObjBindMethod(this, "OnWorkerReady"))
        OnMessage(WM_WORKER_TO_MASTER, ObjBindMethod(this, "OnWorkerToMaster"))

        if (this.isDynamic) {
            this.shrinkTimerFunc := ObjBindMethod(this, "FreeShrinkCheck")
            SetTimer(this.shrinkTimerFunc, 10000)
        }

        initWorkerNum := this.isDynamic ? this.corePoolSize : this.maxSize
        loop initWorkerNum {
            this.CreateWorker()
        }
    }

    __Delete() {
        this.Clear()
    }

    Clear() {
        if (this.isDynamic && this.shrinkTimerFunc != "") {
            SetTimer(this.shrinkTimerFunc, 0)
            this.shrinkTimerFunc := ""
        }

        for idx, wd in this.freePool
            this.PostMessage(WM_CLEAR_WORK, wd)
        for idx, wd in this.usePool
            this.PostMessage(WM_CLEAR_WORK, wd)
        for idx, wd in this.pending
            this.PostMessage(WM_CLEAR_WORK, wd)

        for idx, wd in this.freePool {
            if (wd.hProc)
                CloseHandle(wd.hProc)
        }
        for idx, wd in this.usePool {
            if (wd.hProc)
                CloseHandle(wd.hProc)
        }

        this.freePool := Map()
        this.usePool := Map()
        this.pending := Map()

        this.taskQueue := TaskQueue()
        this.idxCounter := 0
    }

    CreateWorker() {
        this.idxCounter++
        idx := this.idxCounter
        wd := WorkerData(idx)

        txName := "RMT_TX_" idx
        rxName := "RMT_RX_" idx
        evtName := "RMT_EVT_" idx

        wd.shmTx := SharedMemory(txName, 1048576 + 192)
        wd.tx := RingBuffer(wd.shmTx.ptr, 1048576)

        wd.shmRx := SharedMemory(rxName, 1048576 + 192)
        wd.rx := RingBuffer(wd.shmRx.ptr, 1048576)

        wd.hEvt := CreateEvent(evtName)
        this.pending[idx] := wd

        Run(Format('"{}" {} {} {} "{}" "{}" "{}"'
            , this.workerExe
            , MySoftData.MyGui.Hwnd
            , idx
            , this.mainPID
            , txName
            , rxName
            , evtName), , , &pid)

        wd.pid := pid
        wd.hProc := DllCall("OpenProcess", "uint", 0x0040 | 0x0001, "int", false, "uint", pid, "ptr")
    }

    Submit(cmd, tableIndex := 0, itemIndex := 0) {
        this.taskQueue.Push({ cmd: cmd, tableIndex: tableIndex, itemIndex: itemIndex })
        this.Dispatch()
        return 0
    }

    Broadcast(actionStr, args*) {
        if (!this.isDynamic && this.maxSize < 1)
            return

        payload := JSON.stringify([actionStr, args*])
        for idx, wd in this.usePool {
            if (this.broadcastExcludeIdx && idx == this.broadcastExcludeIdx)
                continue
            wd.tx.Push(MsgType.EVENT, 0, payload)
            this.PostMessage(WM_MASTER_TO_WORKER, wd)
        }
        for idx, wd in this.freePool {
            if (this.broadcastExcludeIdx && idx == this.broadcastExcludeIdx)
                continue
            wd.tx.Push(MsgType.EVENT, 0, payload)
            this.PostMessage(WM_MASTER_TO_WORKER, wd)
        }
        this.broadcastExcludeIdx := 0  ; 重置，避免影响其他非 Worker 事件触发的 Broadcast
    }

    ;分配任务
    Dispatch() {
        if (this.isDispatching)
            return
        this.isDispatching := true

        try {
            while (this.taskQueue.Size() > 0 && this.freePool.Count > 0) {
                freeArr := []
                for idx in this.freePool
                    freeArr.Push(idx)
                idx := freeArr[1]
                wd := this.freePool[idx]

                task := this.taskQueue.Pop()
                wd.tx.Push(MsgType.TASK, wd.idx, task.cmd, 0)

                ; Worker 从空闲转入忙碌，任务元数据直接记录在 WorkerData 上
                this.freePool.Delete(idx)
                this.usePool[idx] := wd
                wd.tableIndex := task.tableIndex
                wd.itemIndex := task.itemIndex

                this.PostMessage(WM_MASTER_TO_WORKER, wd)
                wd.idleTick := 0
            }

            if (this.isDynamic && this.taskQueue.Size() > 0 && (this.usePool.Count + this.pending.Count) < this.dynamicMaxLimit
            ) {
                this.CreateWorker()
            }
        } finally {
            this.isDispatching := false
        }
    }

    ; 重置 Worker 的任务状态（任务完成或中止时调用）
    ; state: 0=正常完成, 3=异常中止
    ResetWorkerTaskState(wd, state) {
        if (wd.tableIndex == 0 || wd.itemIndex == 0) {
            wd.tableIndex := 0
            wd.itemIndex := 0
            return
        }

        tableItem := MySoftData.TableInfo[wd.tableIndex]
        if (tableItem.IsWorkIndexArr.Length >= wd.itemIndex)
            tableItem.IsWorkIndexArr[wd.itemIndex] := 0

        if (state == 0) {
            itemState := tableItem.KilledArr.Length >= wd.itemIndex && tableItem.KilledArr[wd.itemIndex] ? 3 : 0
        } else {
            itemState := 3
        }
        if (tableItem.KilledArr.Length >= wd.itemIndex)
            tableItem.KilledArr[wd.itemIndex] := false
        SetTableItemState(wd.tableIndex, wd.itemIndex, itemState)

        wd.tableIndex := 0
        wd.itemIndex := 0
    }

    OnWorkerReady(wParam, lParam, msg, hwnd) {
        idx := wParam
        if (!this.pending.Has(idx))
            return
        wd := this.pending[idx]
        this.pending.Delete(idx)

        wd.hwnd := lParam > 0 ? lParam : hwnd
        wd.isPending := false
        wd.idleTick := A_TickCount

        ; 动态创建的 Worker 需要同步主线程当前的变量和数组状态
        this.SyncStateToWorker(wd)

        this.freePool[idx] := wd
        this.Dispatch()
    }

    ; 将主线程的全部变量和数组状态同步到指定 Worker（用于动态创建的 Worker 初始化）
    SyncStateToWorker(wd) {
        ; 序列化 VariableMap → [[name, value], ...]
        VarArr := []
        for name, value in MySoftData.VariableMap
            VarArr.Push([name, value])

        ; 序列化 ArrayMap → [[name, arrayStr], ...]
        ArrArr := []
        for name, arr in MySoftData.ArrayMap
            ArrArr.Push([name, GetArrayStr(arr)])

        if (VarArr.Length > 0 || ArrArr.Length > 0) {
            payload := JSON.stringify(["SyncVarData", VarArr, ArrArr])
            wd.tx.Push(MsgType.EVENT, 0, payload)
            this.PostMessage(WM_MASTER_TO_WORKER, wd)
        }
    }

    CleanUpWorker(wd) {
        this.ResetWorkerTaskState(wd, 3)

        this.freePool.Delete(wd.idx)
        this.usePool.Delete(wd.idx)

        if (wd.hProc) {
            CloseHandle(wd.hProc)
            wd.hProc := 0
        }
    }

    FreeShrinkCheck() {
        maxShrink := this.freePool.Count - this.corePoolSize
        if (maxShrink <= 0)
            return

        now := A_TickCount
        shrunk := 0
        for idx, wd in this.freePool {
            if (shrunk >= maxShrink)
                break
            if (wd.idleTick > 0 && (now - wd.idleTick) >= this.elasticTimeout) {
                this.PostMessage(WM_CLEAR_WORK, wd)
                this.CleanUpWorker(wd)
                shrunk++
            }
        }
    }

    ; Worker→主线程消息处理：读取 RingBuffer 中的结果和事件，直接解析处理
    OnWorkerToMaster(wParam := 0, lParam := 0, msg := 0, hwnd := 0) {
        idx := wParam
        wd := this.usePool.Has(idx) ? this.usePool[idx] : (this.freePool.Has(idx) ? this.freePool[idx] : 0)
        if (!wd)
            return

        rb := wd.rx
        loop {
            while (rb.Pop(&type, &id, &result)) {
                switch type {
                    case MsgType.FINISH:
                        this.ResetWorkerTaskState(wd, 0)
                        this.usePool.Delete(wd.idx)
                        this.freePool[wd.idx] := wd
                        wd.idleTick := A_TickCount
                        this.Dispatch()
                    case MsgType.EVENT:
                        this.OnWorkerEvent(wd, result)
                }
            }
            if (rb.IsEmpty())
                break
        }
    }

    OnWorkerEvent(wd, payload) {
        ; 标记发起者，Broadcast 时将跳过该 Worker（发起者已在本地处理过）
        this.broadcastExcludeIdx := wd.idx
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
                case "StopMacro":
                    StopMacro(args[1], args[2])
                case "TR_MACRO":
                    TriggerMacroHandler(args[1], args[2])
            }
        } catch as e {
        }
        this.broadcastExcludeIdx := 0  ; 安全重置，防止 handler 未调用 Broadcast 时残留
    }

    BroadcastStop(tableIndex, itemIndex) {
        payload := JSON.stringify(["StopMacro", tableIndex, itemIndex])
        for idx, wd in this.usePool
            wd.tx.Push(MsgType.EVENT, 0, payload)
        for idx, wd in this.freePool
            wd.tx.Push(MsgType.EVENT, 0, payload)
        for idx, wd in this.usePool
            this.PostMessage(WM_MASTER_TO_WORKER, wd)
        for idx, wd in this.freePool
            this.PostMessage(WM_MASTER_TO_WORKER, wd)
        tableItem := MySoftData.TableInfo[tableIndex]
        KillTableItemMacro(tableItem, itemIndex)
        SetTableItemState(tableIndex, itemIndex, 3)
    }

    PostMessage(type, wd, wParam := 0, lParam := 0) {
        if (wd.hwnd) {
            try {
                PostMessage(type, wParam, lParam, , "ahk_id " wd.hwnd)
            }
        }
    }
}
