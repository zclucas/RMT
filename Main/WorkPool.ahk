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
        this.createTick := 0          ; Worker 进程创建时间戳，用于检测启动超时
        this.tableIndex := 0          ; Worker 当前正在处理的宏所属的表索引（0=空闲）
        this.itemIndex := 0           ; Worker 当前正在处理的宏在表中的项索引（0=空闲）
        this.isGraphBranch := false   ; 是否为图形宏并行分支任务
        this.graphNodeSerial := ""    ; 图形分支起始节点（异常退出时重派）
        this.lastJoySeq := 0          ; 上次接收的摇桿序列号
    }
}

class WorkPool {
    __New() {
        this.workerExe := A_ScriptDir "\Thread\Work.exe"
        SplitPath(this.workerExe, &workerExeName)
        this.workerExeName := workerExeName
        this.maxSize := MainSoftData.MutiThreadNum
        this.isDynamic := (this.maxSize == -1)
        this.dynamicMaxLimit := 16
        this.corePoolSize := MainSoftData.DynamicCorePoolSize
        this.elasticTimeout := MainSoftData.ElasticTimeout * 1000

        this.freePool := Map()        ; idx -> WorkerData，空闲可用的 Worker
        this.usePool := Map()         ; idx -> WorkerData，正在执行任务的 Worker
        this.pending := Map()         ; idx -> WorkerData，正在启动尚未就绪的 Worker
        this.workerMap := Map()       ; idx -> WorkerData，所有存活 Worker（用于 rx 读取）

        this.taskQueue := TaskQueue()     ; 等待分发的任务队列，每项 {cmd, tableIndex, itemIndex}
        this.mainPID := DllCall("GetCurrentProcessId")
        this.idxCounter := 0          ; Worker 索引计数器（递增，用于分配唯一 idx）
        this.isDispatching := false    ; Dispatch 防重入标志
        this.dispatchPending := false
        this.targetWorkerCount := 0
        this.lostWorkerCheckRound := 0
        this.lostWorkerCheckFunc := ""
        this.rxPollFunc := ""

        OnMessage(WM_LOAD_WORK, ObjBindMethod(this, "OnWorkerReady"))
        OnMessage(WM_WORKER_TO_MASTER, ObjBindMethod(this, "OnWorkerToMaster"))

        if (this.isDynamic) {
            this.shrinkTimerFunc := ObjBindMethod(this, "FreeShrinkCheck")
            SetTimer(this.shrinkTimerFunc, 10000)
        }

        initWorkerNum := this.isDynamic ? this.corePoolSize : this.maxSize
        this.targetWorkerCount := initWorkerNum
        loop initWorkerNum
            this.CreateWorker(A_Index)
        this.idxCounter := initWorkerNum

        if (this.targetWorkerCount > 0) {
            this.lostWorkerCheckFunc := ObjBindMethod(this, "CheckLostWorkers")
            SetTimer(this.lostWorkerCheckFunc, -10000)
        }
        this.rxPollFunc := ObjBindMethod(this, "PollWorkerRx")
        SetTimer(this.rxPollFunc, 300)
    }

    __Delete() {
        this.Clear()
    }

    Clear() {
        if (this.rxPollFunc != "") {
            SetTimer(this.rxPollFunc, 0)
            this.rxPollFunc := ""
        }
        if (this.lostWorkerCheckFunc != "") {
            SetTimer(this.lostWorkerCheckFunc, 0)
            this.lostWorkerCheckFunc := ""
        }
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
        for idx, wd in this.pending {
            if (wd.hProc)
                CloseHandle(wd.hProc)
        }

        this.freePool := Map()
        this.usePool := Map()
        this.pending := Map()
        this.workerMap := Map()

        this.taskQueue := TaskQueue()
        this.idxCounter := 0
    }

    CreateWorker(reuseIdx := 0) {
        idx := reuseIdx > 0 ? reuseIdx : ++this.idxCounter
        wd := WorkerData(idx)

        txName := "RMT_TX_" idx
        rxName := "RMT_RX_" idx
        evtName := "Global\RMT_EVT_" idx

        wd.shmTx := SharedMemory(txName, 1048576 + 192)
        wd.tx := RingBuffer(wd.shmTx.ptr, 1048576)

        wd.shmRx := SharedMemory(rxName, 1048576 + 192)
        wd.rx := RingBuffer(wd.shmRx.ptr, 1048576)

        wd.hEvt := CreateEvent(evtName)
        wd.createTick := A_TickCount
        this.pending[idx] := wd

        Run(Format('"{}" --parentHwnd={} --idx={} --parentPID={} --txName="{}" --rxName="{}" --evtName="{}"'
            , this.workerExe
            , MainSoftData.MyGui.Hwnd
            , idx
            , this.mainPID
            , txName
            , rxName
            , evtName), , , &pid)

        wd.pid := pid
        wd.hProc := DllCall("OpenProcess", "uint", 0x0040 | 0x0001, "int", false, "uint", pid, "ptr")
        this.workerMap[idx] := wd
        GraphPoolLog("CreateWorker", Format("Worker#{1} 已启动 pending={2} maxSize={3}"
            , idx, this.pending.Count, this.maxSize))
    }

    GetActiveWorkerCount() {
        return this.freePool.Count + this.usePool.Count + this.pending.Count
    }

    GetPoolStatsStr() {
        return Format("闲置={1} 忙碌={2} 启动中={3} 队列={4}"
            , this.freePool.Count, this.usePool.Count, this.pending.Count, this.taskQueue.Size())
    }

    GetPendingWorkerIds() {
        ids := ""
        for idx in this.pending
            ids .= (ids != "" ? "," : "") idx
        return ids != "" ? ids : "无"
    }

    GetFreeWorkerIds() {
        ids := ""
        for idx in this.freePool
            ids .= (ids != "" ? "," : "") idx
        return ids != "" ? ids : "无"
    }

    Submit(cmd, tableIndex := 0, itemIndex := 0) {
        this.taskQueue.Push({ cmd: cmd, tableIndex: tableIndex, itemIndex: itemIndex, isGraphBranch: false })
        this.Dispatch()
        return 0
    }

    ; 向所有 Worker 广播事件（master 本地发起，无需排除）
    Broadcast(opcode, args*) {
        this.BroadcastEx(0, opcode, args*)
    }

    ; 向 Worker 广播事件，excludeIdx 为需要跳过的发起者 Worker idx（0=不跳过）。
    BroadcastEx(excludeIdx, opcode, args*) {
        cmd := EncodeCommand(opcode, args*)
        payload := EncodeBatch(cmd)
        this.BroadcastPayloadEx(excludeIdx, payload)
    }

    BroadcastPayloadEx(excludeIdx, payload) {
        if (!this.isDynamic && this.maxSize < 1)
            return

        for idx, wd in this.usePool {
            if (excludeIdx && idx == excludeIdx)
                continue
            this.PushTask(wd, MsgType.EVENT, 0, payload)
        }
        for idx, wd in this.freePool {
            if (excludeIdx && idx == excludeIdx)
                continue
            this.PushTask(wd, MsgType.EVENT, 0, payload)
        }
    }

    ; 图形宏全部分支 Worker 结束后，释放宏项占用状态
    FinishGraphMacroItem(tableIndex, itemIndex) {
        this.DrainItemTaskQueue(tableIndex, itemIndex)
        tableItem := MySoftData.TableInfo[tableIndex]
        itemState := 0
        if (tableItem.KilledArr.Length >= itemIndex && tableItem.KilledArr[itemIndex])
            itemState := 3
        if (tableItem.KilledArr.Length >= itemIndex)
            tableItem.KilledArr[itemIndex] := false
        if (tableItem.IsWorkIndexArr.Length >= itemIndex)
            tableItem.IsWorkIndexArr[itemIndex] := 0
        if (tableItem.GraphBranchCountArr.Length >= itemIndex)
            tableItem.GraphBranchCountArr[itemIndex] := 0
        SetTableItemState(tableIndex, itemIndex, itemState)
        GraphPoolLog("图形宏结束", Format("tab={1} item={2} state={3}", tableIndex, itemIndex, itemState))
    }

    DrainItemTaskQueue(tableIndex, itemIndex) {
        kept := []
        drained := 0
        while (this.taskQueue.Size() > 0) {
            task := this.taskQueue.Pop()
            if (task.tableIndex == tableIndex && task.itemIndex == itemIndex)
                drained++
            else
                kept.Push(task)
        }
        for t in kept
            this.taskQueue.Push(t)
        if (drained > 0)
            GraphPoolLog("清空任务队列", Format("tab={1} item={2} 丢弃={3}", tableIndex, itemIndex, drained))
    }

    ; 新一次宏触发前：清队列、停残留 Worker、重置状态
    PrepareItemRun(tableIndex, itemIndex) {
        this.DrainItemTaskQueue(tableIndex, itemIndex)
        ; 停止该宏项的残留 Worker
        payload := JSON.stringify(["StopMacro", tableIndex, itemIndex])
        for idx, wd in this.usePool {
            if (wd.tableIndex != tableIndex || wd.itemIndex != itemIndex)
                continue
            this.PushTask(wd, MsgType.EVENT, 0, payload)
            KillTableItemMacro(MySoftData.TableInfo[tableIndex], itemIndex)
        }
        tableItem := MySoftData.TableInfo[tableIndex]
        if (tableItem.GraphBranchCountArr.Length >= itemIndex)
            tableItem.GraphBranchCountArr[itemIndex] := 0
        if (tableItem.KilledArr.Length >= itemIndex)
            tableItem.KilledArr[itemIndex] := false
        if (tableItem.IsWorkIndexArr.Length >= itemIndex)
            tableItem.IsWorkIndexArr[itemIndex] := 0
    }

    ;分配任务
    Dispatch() {
        if (this.isDispatching) {
            this.dispatchPending := true
            return
        }
        this.isDispatching := true

        try {
            this.RemoveDeadFreeWorkers()
            while (this.taskQueue.Size() > 0 && this.freePool.Count > 0) {
                if (!this.AssignTask())
                    break
            }
            if (this.isDynamic && this.taskQueue.Size() > 0 && (this.usePool.Count + this.pending.Count) < this.dynamicMaxLimit)
                this.CreateWorker()
        } finally {
            this.isDispatching := false
            if (this.dispatchPending) {
                this.dispatchPending := false
                SetTimer(() => this.Dispatch(), -1)
            }
        }
        if (this.taskQueue.Size() > 0 && this.freePool.Count > 0)
            this.Dispatch()
    }

    ; 移除 freePool 中已失效的 Worker（进程退出或窗口不可达），并安排补建
    RemoveDeadFreeWorkers() {
        toClean := []
        for idx, wd in this.freePool {
            if (!this.IsWorkerDispatchable(wd))
                toClean.Push(wd)
        }
        for wd in toClean {
            GraphPoolLog("Worker不可用", Format("Worker#{1} pid={2} 进程已退出 移出并补建", wd.idx, wd.pid))
            this.CleanUpWorker(wd)
            this.ScheduleRecreateWorker(wd.idx, 0)
        }
    }

    ; 从 freePool 取一个 Worker，从 taskQueue 取一个任务，绑定后通知 Worker
    AssignTask() {
        ; 取第一个空闲 Worker（freePool 非空由 Dispatch 调用前保证）
        freeKeys := []
        for k in this.freePool {
            freeKeys.Push(k)
            break
        }
        idx := freeKeys[1]
        wd := this.freePool[idx]

        task := this.taskQueue.Pop()
        if (!wd.tx.Push(MsgType.TASK, wd.idx, task.cmd, 0)) {
            this.taskQueue.queue.InsertAt(1, task)
            GraphPoolLog("Dispatch失败", Format("Worker#{1} tx已满", wd.idx))
            return false
        }

        this.freePool.Delete(idx)
        this.usePool[idx] := wd
        wd.tableIndex := task.tableIndex
        wd.itemIndex := task.itemIndex
        wd.isGraphBranch := task.HasOwnProp("isGraphBranch") ? task.isGraphBranch : false
        wd.graphNodeSerial := ""
        if (wd.isGraphBranch) {
            try {
                paramArr := JSON.parse(task.cmd)
                wd.graphNodeSerial := paramArr[4]
            }
        }
        wd.idleTick := 0

        if (wd.hEvt)
            DllCall("SetEvent", "ptr", wd.hEvt)
        if (!this.PostMessage(WM_MASTER_TO_WORKER, wd)) {
            this.usePool.Delete(idx)
            this.freePool[idx] := wd
            wd.tableIndex := 0
            wd.itemIndex := 0
            wd.isGraphBranch := false
            wd.graphNodeSerial := ""
            this.taskQueue.queue.InsertAt(1, task)
            GraphPoolLog("Dispatch失败", Format("Worker#{1} PostMessage失败 node={2}", wd.idx, wd.graphNodeSerial))
            return false
        }
        GraphPoolLog("Dispatch分配", Format("Worker#{1} tab={2} item={3} graph={4} 闲置={5} 队列={6}"
            , wd.idx, task.tableIndex, task.itemIndex, task.isGraphBranch ? 1 : 0
            , this.freePool.Count, this.taskQueue.Size()))
        return true
    }

    ; 检查该宏项是否还有未完成的工作（usePool 中的忙碌 Worker 或 taskQueue 中排队的图形分支）
    HasItemWork(tableIndex, itemIndex) {
        for idx, w in this.usePool {
            if (w.tableIndex == tableIndex && w.itemIndex == itemIndex)
                return true
        }
        for task in this.taskQueue.queue {
            if (task.isGraphBranch && task.tableIndex == tableIndex && task.itemIndex == itemIndex)
                return true
        }
        return false
    }

    ; 延迟尝试结束图形宏项（用于 Worker 完成后还有排队任务的情况）
    TryFinishGraphItem(tIdx, iIdx) {
        tableItem := MySoftData.TableInfo[tIdx]
        if (tableItem.GraphBranchCountArr.Length >= iIdx && tableItem.GraphBranchCountArr[iIdx] > 0)
            return
        if (this.HasItemWork(tIdx, iIdx))
            return
        this.FinishGraphMacroItem(tIdx, iIdx)
    }

    ; 进程存活时按 pid 重新解析 Worker 窗口（缓存 hwnd 可能已失效）
    ResolveWorkerHwnd(wd) {
        if (!wd.pid || !ProcessExist(wd.pid))
            return 0
        if (wd.hwnd) {
            try {
                if (WinExist("ahk_id " wd.hwnd) && WinGetPID("ahk_id " wd.hwnd) == wd.pid)
                    return wd.hwnd
            }
        }
        try {
            hwnd := WinExist("ahk_pid " wd.pid " ahk_exe " this.workerExeName)
            if (!hwnd)
                hwnd := WinExist("ahk_pid " wd.pid)
            if (hwnd && WinGetPID("ahk_id " hwnd) == wd.pid) {
                if (wd.hwnd != hwnd)
                    GraphPoolLog("Workerhwnd恢复", Format("Worker#{1} 旧={2} 新={3} pid={4}"
                        , wd.idx, wd.hwnd, hwnd, wd.pid))
                wd.hwnd := hwnd
                return hwnd
            }
        }
        return 0
    }

    GetWorkerDispatchBlockReason(wd) {
        if (!wd.pid || !ProcessExist(wd.pid))
            return "进程已退出"
        if (!this.ResolveWorkerHwnd(wd))
            return "窗口不可达"
        return ""
    }

    IsWorkerDispatchable(wd) {
        return this.GetWorkerDispatchBlockReason(wd) == ""
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
        ; 图形宏并行分支：单项 Worker 结束时不改宏项全局占用/颜色，由 FinishGraphMacroItem 统一释放
        skipMacroRelease := wd.isGraphBranch && tableItem.GraphBranchCountArr.Length >= wd.itemIndex
            && tableItem.GraphBranchCountArr[wd.itemIndex] > 0

        if (!skipMacroRelease) {
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
        }

        wd.tableIndex := 0
        wd.itemIndex := 0
        wd.isGraphBranch := false
    }

    OnWorkerReady(wParam, lParam, msg, hwnd) {
        idx := wParam
        if (!this.pending.Has(idx))
            return
        wd := this.pending[idx]
        readyHwnd := lParam > 0 ? lParam : hwnd
        if (readyHwnd && wd.pid) {
            try {
                if (WinGetPID("ahk_id " readyHwnd) != wd.pid) {
                    GraphPoolLog("Worker就绪忽略", Format("Worker#{1} 迟到就绪 pid不匹配 expect={2}", idx, wd.pid))
                    return
                }
            } catch {
                return
            }
        }
        this.pending.Delete(idx)

        wd.hwnd := readyHwnd
        wd.isPending := false
        wd.idleTick := A_TickCount

        ; 动态创建的 Worker 需要同步主线程当前的变量和数组状态
        this.SyncStateToWorker(wd)

        this.freePool[idx] := wd
        GraphPoolLog("Worker就绪", Format("Worker#{1} 就绪后闲置={2} 队列={3} 仍启动中=[{4}]"
            , idx, this.freePool.Count, this.taskQueue.Size(), this.GetPendingWorkerIds()))
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
            this.PushTask(wd, MsgType.EVENT, 0, payload)
        }
    }

    RemoveWorkerFromPools(idx) {
        for pool in [this.freePool, this.usePool, this.pending] {
            if (pool.Has(idx))
                pool.Delete(idx)
        }
    }

    CleanUpWorker(wd, resetTask := true) {
        if (resetTask)
            this.ResetWorkerTaskState(wd, 3)
        this.RemoveWorkerFromPools(wd.idx)
        this.workerMap.Delete(wd.idx)
        try {
            if (wd.shmTx)
                wd.shmTx.Close()
            if (wd.shmRx)
                wd.shmRx.Close()
            if (wd.hEvt)
                CloseHandle(wd.hEvt)
        }
        wd.shmTx := 0
        wd.shmRx := 0
        wd.hEvt := 0
        if (wd.hProc) {
            CloseHandle(wd.hProc)
            wd.hProc := 0
        }
    }

    ScheduleRecreateWorker(reuseIdx, deadPid := 0) {
        SetTimer(() => this.TryRecreateWorker(reuseIdx, deadPid), -500)
    }

    TryRecreateWorker(reuseIdx, deadPid := 0) {
        if (deadPid && ProcessExist(deadPid)) {
            this.ScheduleRecreateWorker(reuseIdx, deadPid)
            return
        }
        if (this.freePool.Has(reuseIdx) || this.usePool.Has(reuseIdx) || this.pending.Has(reuseIdx))
            return
        this.CreateWorker(reuseIdx)
        this.Dispatch()
    }

    ; 仅进程已退出视为丢失（pending 慢启动不杀）；短暂抖动时二次确认
    IsWorkerProcessDead(wd) {
        if (!wd.pid)
            return true
        if (ProcessExist(wd.pid))
            return false
        Sleep(50)
        return !ProcessExist(wd.pid)
    }

    IsLostWorker(wd) {
        return this.IsWorkerProcessDead(wd)
    }

    ReclaimDeadUsePoolWorkers() {
        toAbort := []
        for idx, wd in this.usePool {
            if (this.IsWorkerProcessDead(wd))
                toAbort.Push(wd)
        }
        for wd in toAbort
            this.AbortDeadWorkerTask(wd)
    }

    AbortDeadWorkerTask(wd) {
        tIdx := wd.tableIndex
        iIdx := wd.itemIndex
        startNode := wd.graphNodeSerial
        GraphPoolLog("Worker进程退出", Format("Worker#{1} Master检测到进程已退出(非StopMacro) tab={2} item={3} graph={4} node={5} pid={6}"
            , wd.idx, tIdx, iIdx, wd.isGraphBranch ? 1 : 0, startNode, wd.pid))
        isGraphTask := false
        if (tIdx && iIdx) {
            tableItem := MySoftData.TableInfo[tIdx]
            branchCount := tableItem.GraphBranchCountArr.Length >= iIdx ? tableItem.GraphBranchCountArr[iIdx] : 0
            isGraphTask := (wd.isGraphBranch || branchCount > 0)
            if (isGraphTask) {
                remainCount := branchCount
                if (branchCount > 0) {
                    tableItem.GraphBranchCountArr[iIdx]--
                    remainCount := tableItem.GraphBranchCountArr[iIdx]
                }
                GraphPoolLog("图形分支Worker异常退出", Format("Worker#{1} tab={2} item={3} 剩余计数={4} 忙碌=[{5}] 队列={6}"
                    , wd.idx, tIdx, iIdx, remainCount, this.GetBusyWorkerIds(), this.taskQueue.Size()))
                if (tableItem.KilledArr.Length >= iIdx)
                    tableItem.KilledArr[iIdx] := true
                if (!this.HasItemWork(tIdx, iIdx))
                    this.DrainItemTaskQueue(tIdx, iIdx)
            }
        }
        reuseIdx := wd.idx
        skipReset := isGraphTask
        this.CleanUpWorker(wd, !skipReset)
        this.ScheduleRecreateWorker(reuseIdx, 0)
        if (isGraphTask && !this.HasItemWork(tIdx, iIdx)) {
            tableItem := MySoftData.TableInfo[tIdx]
            if (!(tableItem.GraphBranchCountArr.Length >= iIdx && tableItem.GraphBranchCountArr[iIdx] > 0))
                this.FinishGraphMacroItem(tIdx, iIdx)
        }
        this.Dispatch()
    }

    ; 启动 10s 后检测；数量已满则跳过
    CheckLostWorkers() {
        active := this.GetActiveWorkerCount()
        if (active >= this.targetWorkerCount && this.pending.Count == 0) {
            SetTimer(this.lostWorkerCheckFunc, 0)
            GraphPoolLog("检测丢失Worker", Format("Worker数量已满足 目标={1} 当前={2} 跳过检测", this.targetWorkerCount, active))
            return
        }
        this.lostWorkerCheckRound++
        removed := 0
        toDrop := []
        for idx, wd in this.pending {
            if (this.IsLostWorker(wd))
                toDrop.Push(wd)
        }
        for wd in toDrop {
            reuseIdx := wd.idx
            if (wd.hwnd)
                try this.PostMessage(WM_CLEAR_WORK, wd)
            GraphPoolLog("移除丢失Worker", Format("Worker#{1} pid={2} age={3}ms 进程已退出 将按原编号补建"
                , wd.idx, wd.pid, A_TickCount - wd.createTick))
            this.CleanUpWorker(wd)
            this.ScheduleRecreateWorker(reuseIdx, 0)
            removed++
        }
        active := this.GetActiveWorkerCount()
        GraphPoolLog("检测丢失Worker", Format("第{1}/5 目标={2} 当前={3} 移除补建={4} 闲置=[{5}] 启动中=[{6}]"
            , this.lostWorkerCheckRound, this.targetWorkerCount, active, removed
            , this.GetFreeWorkerIds(), this.GetPendingWorkerIds()))
        if (active >= this.targetWorkerCount || this.lostWorkerCheckRound >= 5) {
            SetTimer(this.lostWorkerCheckFunc, 0)
            this.Dispatch()
            return
        }
        SetTimer(this.lostWorkerCheckFunc, -2000)
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

    PollWorkerRx() {
        this.ReclaimDeadUsePoolWorkers()
        for idx, wd in this.workerMap {
            if (wd.rx && !wd.rx.IsEmpty())
                this.ProcessWorkerRx(wd)
        }
    }

    ; Worker→主线程消息处理：读取 RingBuffer 中的结果和事件
    OnWorkerToMaster(wParam := 0, lParam := 0, msg := 0, hwnd := 0) {
        idx := wParam
        if (!this.workerMap.Has(idx)) {
            GraphPoolLog("Worker消息无目标", Format("idx={1} 不在workerMap 闲置=[{2}] 忙碌=[{3}]"
                , idx, this.GetFreeWorkerIds(), this.GetBusyWorkerIds()))
            return
        }
        this.ProcessWorkerRx(this.workerMap[idx])
    }

    GetBusyWorkerIds() {
        ids := ""
        for idx in this.usePool
            ids .= (ids != "" ? "," : "") idx
        return ids != "" ? ids : "无"
    }

    ProcessWorkerRx(wd) {
        if (!wd || !wd.rx)
            return
        rb := wd.rx
        loop {
            while (rb.Pop(&type, &id, &result)) {
                switch type {
                    case MsgType.FINISH:
                        if (!this.usePool.Has(wd.idx))
                            continue
                        tIdx := wd.tableIndex
                        iIdx := wd.itemIndex
                        branchCount := 0
                        if (tIdx && iIdx && MySoftData.TableInfo[tIdx].GraphBranchCountArr.Length >= iIdx)
                            branchCount := MySoftData.TableInfo[tIdx].GraphBranchCountArr[iIdx]
                        isGraphTask := (wd.isGraphBranch || branchCount > 0) && tIdx && iIdx
                        if (isGraphTask) {
                            remainCount := branchCount
                            if (branchCount > 0) {
                                MySoftData.TableInfo[tIdx].GraphBranchCountArr[iIdx]--
                                remainCount := MySoftData.TableInfo[tIdx].GraphBranchCountArr[iIdx]
                            }
                            GraphPoolLog("Worker完成", Format("Worker#{1} tab={2} item={3} 图形分支 graph={4} 剩余计数={5} 队列={6} 忙碌=[{7}]"
                                , wd.idx, tIdx, iIdx, wd.isGraphBranch ? 1 : 0, remainCount, this.taskQueue.Size(), this.GetBusyWorkerIds()))
                            if (this.usePool.Has(wd.idx))
                                this.usePool.Delete(wd.idx)
                            this.freePool[wd.idx] := wd
                            wd.tableIndex := 0
                            wd.itemIndex := 0
                            wd.isGraphBranch := false
                            wd.graphNodeSerial := ""
                            wd.idleTick := A_TickCount
                            if (remainCount <= 0) {
                                if (!this.HasItemWork(tIdx, iIdx))
                                    this.FinishGraphMacroItem(tIdx, iIdx)
                                else
                                    SetTimer(() => this.TryFinishGraphItem(tIdx, iIdx), -200)
                            }
                            this.Dispatch()
                        } else {
                            this.ResetWorkerTaskState(wd, 0)
                            if (this.usePool.Has(wd.idx))
                                this.usePool.Delete(wd.idx)
                            this.freePool[wd.idx] := wd
                            wd.isGraphBranch := false
                            wd.idleTick := A_TickCount
                            this.Dispatch()
                        }
                    case MsgType.EVENT:
                        this.OnWorkerEvent(wd, result)
                }
            }
            if (rb.IsEmpty())
                break
        }
    }

    OnWorkerEvent(wd, payload) {
        if (SubStr(payload, 1, 2) != "R1")
            return

        commandsStr := SubStr(payload, 3)
        for record in StrSplit(commandsStr, Chr(2)) {
            if (record == "")
                continue

            parts := StrSplit(record, Chr(1))
            if (parts.Length == 0)
                continue

            opcode := parts[1]
            args := []
            loop parts.Length - 1 {
                args.Push(UnescapeIPC(parts[A_Index + 1]))
            }

            try {
                switch opcode {
                    case "SV":
                        SetGlobalVariable([args[1]], [args[2]], false, wd.idx)
                    case "DV":
                        DelGlobalVariable([args[1]], wd.idx)
                    case "RP":
                        CMDReport(args[1])
                    case "RC":
                        ExcuteRMTCMDAction(args[1])
                    case "IS":
                        SetTableItemState(args[1], args[2], args[3])
                    case "PS":
                        SetItemPauseState(args[1], args[2], args[3], wd.idx)
                    case "MB":
                        MsgBoxContent(args[1])
                    case "TT":
                        ToolTipContent(args[1])
                    case "MC":
                        MacroCount(args[1])
                    case "JY":
                        ViGJoySetState(args[1], args[2], args[3])
                    case "SA":
                        arr := []
                        count := Integer(args[2])
                        loop count {
                            arr.Push(args[A_Index + 2])
                        }
                        SetGlobalArray(args[1], arr, wd.idx)
                    case "CA":
                        CloneGlobalArray(args[1], args[2], wd.idx)
                    case "DA":
                        DeleteGlobalArray(args[1], wd.idx)
                    case "MA":
                        p := StrSplit(args[2], ".")
                        ModifyGlobalArray(args[1], p[1], p[2], false, args[3], wd.idx)
                    case "IA":
                        p := StrSplit(args[2], ".")
                        InsertGlobalArray(args[1], p[1], p[2], false, args[3], wd.idx)
                    case "RA":
                        p := StrSplit(args[2], ".")
                        RemoveAtGlobalArray(args[1], p[1], p[2], wd.idx)
                    case "ER":
                        MyErrorMsgBoxGui.ShowGui(args[1])
                    case "ST":
                        StopMacro(args[1], args[2])
                    case "GB":
                        tIdx := args[1]
                        iIdx := args[2]
                        branchCount := Integer(args[3])
                        nodeSerials := []
                        loop args.Length - 3 {
                            nodeSerials.Push(args[A_Index + 3])
                        }
                        HandleWorkerGraphBranches(wd, tIdx, iIdx, branchCount, nodeSerials)
                    case "TR":
                        TriggerMacroHandler(args[1], args[2])
                }
            } catch {
            }
        }
    }

    PushTask(wd, type, id, payload) {
        if (wd.tx.Push(type, id, payload)) {
            if (wd.hEvt)
                DllCall("SetEvent", "ptr", wd.hEvt)
            this.PostMessage(WM_MASTER_TO_WORKER, wd)
            return true
        }
        return false
    }

    PostMessage(type, wd, wParam := 0, lParam := 0) {
        if (!this.ResolveWorkerHwnd(wd)) {
            GraphPoolLog("PostMessage跳过", Format("Worker#{1} hwnd不可达 pid={2} msg=0x{3:X}", wd.idx, wd.pid, type))
            return false
        }
        try {
            PostMessage(type, wParam, lParam, , "ahk_id " wd.hwnd)
            return true
        } catch as e {
            GraphPoolLog("PostMessage失败", Format("Worker#{1} hwnd={2} msg=0x{3:X} err={4}"
                , wd.idx, wd.hwnd, type, e.Message))
            return false
        }
    }
}
