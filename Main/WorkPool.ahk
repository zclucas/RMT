#Requires AutoHotkey v2.0
#Include Util\SharedMemory.ahk
#Include Util\RingBuffer.ahk
#Include Util\JsonUtil.ahk

; 匿名共享对象仅通过显式句柄清单交给本次创建的 Worker。
LaunchWorkerProcess(exe, arguments, handles*) {
    process := DllCall("GetCurrentProcess", "ptr")
    inherited := []
    listReady := false
    attrs := 0
    try {
        handles.Push(process)
        for handle in handles {
            copy := 0
            access := handle == process ? 0x00100000 : 0 ; 父进程句柄仅用于等待退出
            if (!DllCall("DuplicateHandle", "ptr", process, "ptr", handle, "ptr", process
                , "ptr*", &copy, "uint", access, "int", true, "uint", access ? 0 : 2))
                throw OSError()
            inherited.Push(copy)
        }
        handleList := Buffer(inherited.Length * A_PtrSize)
        for i, handle in inherited
            NumPut("ptr", handle, handleList, (i - 1) * A_PtrSize)
        size := 0
        DllCall("InitializeProcThreadAttributeList", "ptr", 0, "uint", 1, "uint", 0, "uptr*", &size)
        attrs := Buffer(size)
        if (!DllCall("InitializeProcThreadAttributeList", "ptr", attrs, "uint", 1, "uint", 0, "uptr*", &size))
            throw OSError()
        listReady := true
        if (!DllCall("UpdateProcThreadAttribute", "ptr", attrs, "uint", 0, "uptr", 0x20002
            , "ptr", handleList, "uptr", handleList.Size, "ptr", 0, "ptr", 0))
            throw OSError()

        startupSize := A_PtrSize == 8 ? 104 : 68
        startup := Buffer(startupSize + A_PtrSize, 0)
        NumPut("uint", startup.Size, startup)
        NumPut("ptr", attrs.Ptr, startup, startupSize)
        info := Buffer(A_PtrSize * 2 + 8, 0)
        cmd := '"' exe '" ' arguments
        for handle in inherited
            cmd .= " " handle
        cmdBuffer := Buffer((StrLen(cmd) + 1) * 2)
        StrPut(cmd, cmdBuffer, "UTF-16")
        SplitPath(exe, , &workerDir)
        if (!DllCall("CreateProcessW", "str", exe, "ptr", cmdBuffer, "ptr", 0, "ptr", 0
            , "int", true, "uint", 0x80000, "ptr", 0, "str", workerDir, "ptr", startup, "ptr", info))
            throw OSError()
        CloseHandle(NumGet(info, A_PtrSize, "ptr"))
        return {handle: NumGet(info, "ptr"), pid: NumGet(info, A_PtrSize * 2, "uint")}
    } finally {
        if (listReady)
            DllCall("DeleteProcThreadAttributeList", "ptr", attrs)
        for handle in inherited
            CloseHandle(handle)
    }
}

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
        this.hProc := 0               ; 创建 Worker 时返回的进程句柄

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
        this.tableID := ""            ; Worker 当前正在处理的宏所属的表 ID（空=空闲）
        this.itemID := ""             ; Worker 当前正在处理的宏的条目 ID（空=空闲）
        this.taskID := 0              ; 当前任务的分派令牌
        this.stopRequested := false
        this.isGraphBranch := false   ; 是否为图形宏并行分支任务
        this.graphNodeSerial := ""    ; 图形分支起始节点（异常退出时重派）
        this.rxBusy := false          ; ProcessWorkerRx 重入保护
        this.configDirty := false     ; §17 热重载：主进程保存后待补发配置刷新（CF）的标志
    }
}

class WorkPool {
    __New() {
        this.workerExe := A_ScriptDir "\Thread\Work.exe"
        this.maxSize := MainSoftData.MutiThreadNum
        this.isDynamic := (this.maxSize == -1)
        this.dynamicMaxLimit := 16
        this.corePoolSize := MainSoftData.DynamicCorePoolSize
        this.elasticTimeout := MainSoftData.ElasticTimeout * 1000
        this.stopTimeoutMs := 150      ; 协作终止等待超时(ms)，超时后强杀进程重建

        this.freePool := Map()        ; idx -> WorkerData，空闲可用的 Worker
        this.usePool := Map()         ; idx -> WorkerData，正在执行任务的 Worker
        this.pending := Map()         ; idx -> WorkerData，正在启动尚未就绪的 Worker
        this.workerMap := Map()       ; idx -> WorkerData，所有存活 Worker（用于 rx 读取）

        this.taskQueue := TaskQueue()     ; 等待分发的任务队列，每项 {cmd, tableIndex, itemIndex}
        this.idxCounter := 0          ; Worker 索引计数器（递增，用于分配唯一 idx）
        this.taskSequence := 0
        this.isDispatching := false    ; Dispatch 防重入标志
        this.dispatchPending := false
        this.rxPollFunc := ""
        this._inputGuis := Map()      ; 活动输入弹窗实例（key=req）
        this._nativeFileQueue := []
        this._nativeFileActive := false
        this._nativeFileCurrent := ""
        this._nativeFileNext := ""

        this.rxWakeFunc := ObjBindMethod(this, "OnWorkerToMaster")
        OnMessage(WM_WORKER_TO_MASTER, this.rxWakeFunc)

        ; §17 热重载订阅：整表保存（OnSaveSetting 选「否」→ Publish(0,0)，落盘后）→ 广播 Worker 重载配置，
        ; 使「新增宏 / 修改宏内容」保存选「否」后 Worker（Work.exe 启动快照）立即生效，不必重启
        global MyHotReloadBus
        if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
            MyHotReloadBus.Subscribe(ObjBindMethod(this, "OnHotReloadConfigChanged"))

        if (this.isDynamic) {
            this.shrinkTimerFunc := ObjBindMethod(this, "FreeShrinkCheck")
            SetTimer(this.shrinkTimerFunc, 10000)
        }

        initWorkerNum := this.isDynamic ? this.corePoolSize : this.maxSize
        loop initWorkerNum
            this.CreateWorker(A_Index)
        this.idxCounter := initWorkerNum

        this.rxPollFunc := ObjBindMethod(this, "PollWorkerRx")
        SetTimer(this.rxPollFunc, 50)

    }

    __Delete() {
        this.Clear()
    }

    Clear() {
        if (this.HasOwnProp("closing"))
            return
        this.closing := true
        if (this._nativeFileNext != "") {
            SetTimer(this._nativeFileNext, 0)
            this._nativeFileNext := ""
        }
        this._nativeFileQueue := []
        requests := []
        for req in this._inputGuis
            requests.Push(req)
        for req in requests
            this._CancelInput(req)
        OnMessage(WM_WORKER_TO_MASTER, this.rxWakeFunc, 0)

        if (this.rxPollFunc != "") {
            SetTimer(this.rxPollFunc, 0)
            this.rxPollFunc := ""
        }
        if (this.isDynamic && this.shrinkTimerFunc != "") {
            SetTimer(this.shrinkTimerFunc, 0)
            this.shrinkTimerFunc := ""
        }
        allWorkers := []
        for idx, wd in this.workerMap
            allWorkers.Push(wd)
        for wd in allWorkers
            this.CleanUpWorker(wd, false, true, true)

        this.freePool := Map()
        this.usePool := Map()
        this.pending := Map()
        this.workerMap := Map()

        this.taskQueue := TaskQueue()
        this.idxCounter := 0
    }

    CreateWorker(reuseIdx := 0) {
        if (this.HasOwnProp("closing"))
            return
        previousCritical := A_IsCritical
        Critical("On")
        idx := reuseIdx > 0 ? reuseIdx : ++this.idxCounter
        wd := WorkerData(idx)
        this.workerMap[idx] := wd
        this.pending[idx] := wd
        try {
            wd.shmTx := SharedMemory(1048576 + 192)
            wd.tx := RingBuffer(wd.shmTx.ptr, 1048576)
            wd.shmRx := SharedMemory(1048576 + 192)
            wd.rx := RingBuffer(wd.shmRx.ptr, 1048576)
            wd.hEvt := CreateEvent()
            if (!wd.hEvt)
                throw OSError()
            wd.createTick := A_TickCount
            child := LaunchWorkerProcess(this.workerExe, "--macro-worker " idx " " A_ScriptHwnd
                , wd.shmTx.hMap, wd.shmRx.hMap, wd.hEvt)
            wd.hProc := child.handle
            wd.pid := child.pid
        } catch {
            this.CleanUpWorker(wd, false, true)
            throw
        } finally Critical(previousCritical)
        GraphPoolLog("CreateWorker", Format("Worker#{1} 已启动 pid={2} pending={3} maxSize={4}"
            , idx, wd.pid, this.pending.Count, this.maxSize))
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

    Submit(cmd, tableID := "", itemID := "") {
        this.taskQueue.Push({ cmd: cmd, tableID: tableID, itemID: itemID, isGraphBranch: false, isHook: false })
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
        if (this.HasOwnProp("closing") || (!this.isDynamic && this.maxSize < 1))
            return

        previousCritical := A_IsCritical
        Critical("On")
        try {
            for idx, wd in this.workerMap {
                if (!wd.isPending && idx != excludeIdx)
                    this.PushTask(wd, MsgType.EVENT, 0, payload)
            }
        } finally Critical(previousCritical)
    }

    ; 图形宏全部分支 Worker 结束后，释放宏项占用状态
    FinishGraphMacroItem(tableID, itemID) {
        this.DrainItemTaskQueue(tableID, itemID)
        tableItem := GetTableByID(tableID)
        if (!tableItem)
            return
        itemIndex := GetItemIndexInTable(tableItem, itemID)
        item := GetItemByIndex(tableItem, itemIndex)
        if (!item)
            return
        itemState := 0
        if (item.Killed) {
            itemState := 3
            ReleaseTableItemHoldKeys(tableItem, itemIndex)
        }
        item.Killed := false
        item.IsWorkIndex := 0
        item.GraphBranchCount := 0
        SetTableItemState(tableItem, itemIndex, itemState)
        GraphPoolLog("图形宏结束", Format("tab={1} item={2} state={3}", tableID, itemID, itemState))
        ; 多分支场景：分支 Worker 只跑自己那条链，谁都不负责后置钩子，
        ; 由这里统一补派一次（钩子宏串仍交给 Worker 执行，主进程只投递）。
        this.DispatchPostHook(tableItem, item)
    }

    DrainItemTaskQueue(tableID, itemID) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            kept := []
            for task in this.taskQueue.queue {
                if (task.tableID != tableID || task.itemID != itemID)
                    kept.Push(task)
            }
            drained := this.taskQueue.Size() - kept.Length
            this.taskQueue.queue := kept
        } finally Critical(previousCritical)
        if (drained > 0)
            GraphPoolLog("清空任务队列", Format("tab={1} item={2} 丢弃={3}", tableID, itemID, drained))
    }

    ; 强制终止正在执行某宏项的 Worker 进程并安排重建。
    ; 搜图等 DllCall 期间协作式 Killed/ST 无法打断，只能杀进程。
    KillWorkersForItem(tableID, itemID) {
        toKill := []
        previousCritical := A_IsCritical
        Critical("On")
        try {
            for idx, wd in this.usePool {
                if (wd.tableID == tableID && wd.itemID == itemID) {
                    wd.stopRequested := true
                    toKill.Push({worker: wd, id: wd.taskID})
                }
            }
        } finally Critical(previousCritical)
        killed := 0
        for assignment in toKill {
            wd := assignment.worker
            GraphPoolLog("强制停止Worker", Format("Worker#{1} tab={2} item={3} pid={4}"
                , wd.idx, tableID, itemID, wd.pid))
            if (this.CleanUpWorker(wd, false, true, false, assignment.id)) {
                killed++
                this.ScheduleRecreateWorker(wd.idx)
            }
        }
        return killed
    }

    ; 用户停止宏：按 MainSoftData.MacroStopType 选择终止策略。
    ; 智能终止(1)：协作式终止（置 Killed + ST 通知 Worker），Worker 完成后回发 FINISH 确认；
    ;   超过 this.stopTimeoutMs 仍未确认（如 Worker 卡在搜图 DllCall）则强制杀进程重建。
    ; 强制终止(2)：不等待协作退出，直接杀进程重建，响应更快但频繁重建较耗资源。
    ForceStopItem(tableID, itemID) {
        this.DrainItemTaskQueue(tableID, itemID)
        tableItem := GetTableByID(tableID)
        if (!tableItem)
            return
        itemIndex := GetItemIndexInTable(tableItem, itemID)
        item := GetItemByIndex(tableItem, itemIndex)
        if (!item || item.HasOwnProp("Stopping"))
            return
        item.Stopping := true
        try this.StopItemRun(tableItem, itemIndex, item)
        finally item.DeleteProp("Stopping")
    }

    StopItemRun(tableItem, itemIndex, item) {
        tableID := tableItem.ID
        itemID := item.ID
        item.GraphBranchCount := 0

        ; 协作终止由 Worker 松键，主进程在 Worker 停止后释放剩余按键。
        item.Killed := true
        item.ToggleState := false

        if (MainSoftData.MacroStopType == 2) {
            ; 强制终止：直接杀进程重建，不等待 Worker 协作退出
            killed := this.KillWorkersForItem(tableID, itemID)
            GraphPoolLog("停止宏-强制终止", Format("tab={1} item={2} 强杀Worker={3} 忙碌=[{4}]"
                , tableID, itemID, killed, this.GetBusyWorkerIds()))
        } else {
            this.RequestItemStop(tableID, itemID)
            GraphPoolLog("停止宏-请求终止", Format("tab={1} item={2} 超时阈值={3}ms 忙碌=[{4}]"
                , tableID, itemID, this.stopTimeoutMs, this.GetBusyWorkerIds()))

            ; 2) 等待 Worker 回发 FINISH 确认终止（FINISH 处理后 Worker 离开 usePool）
            start := A_TickCount
            loop {
                try this.PollWorkerRx()
                if (!this.HasItemWork(tableID, itemID))
                    break
                if (A_TickCount - start >= this.stopTimeoutMs)
                    break
                Sleep(10)
            }
            elapsed := A_TickCount - start

            ; 3) 超时仍未确认 → 强制杀进程重建
            if (this.HasItemWork(tableID, itemID)) {
                killed := this.KillWorkersForItem(tableID, itemID)
                GraphPoolLog("停止宏-强杀", Format("tab={1} item={2} 协作超时={3}ms 强杀Worker={4} 忙碌=[{5}]"
                    , tableID, itemID, elapsed, killed, this.GetBusyWorkerIds()))
            } else {
                GraphPoolLog("停止宏-协作终止", Format("tab={1} item={2} 确认耗时={3}ms 未杀进程 忙碌=[{4}]"
                    , tableID, itemID, elapsed, this.GetBusyWorkerIds()))
            }
        }

        ReleaseTableItemHoldKeys(tableItem, itemIndex)
        item.IsWorkIndex := 0
        SetTableItemState(tableItem, itemIndex, 3)
        ; 强停时 Worker 侧走不到后置钩子（进程被杀，或分支没机会收尾），由主进程补派。
        ; 此时 Killed 已经是 true，钩子以 force 模式执行，否则清理会被自身的终止判断拦住。
        this.DispatchPostHook(tableItem, item)
    }

    ; 补派后置钩子：主进程只负责投递，钩子宏串仍然在 Worker 里执行。
    ; 任务身份用「主条目 ID + _hook」而不是主条目 ID —— 否则会被 HasItemWork 判成
    ; 「宏还在跑」，导致 FinishGraphMacroItem 永远收尾不了；也会被按主 ID 过滤的
    ; DrainItemTaskQueue 当成残留任务清掉。
    DispatchPostHook(tableItem, item) {
        if (!IsObject(item) || !item.HasProp("PostMacro"))
            return false
        if (Trim(item.PostMacro) == "")
            return false
        if (item.HasProp("PostHookFired") && item.PostHookFired)
            return false
        item.PostHookFired := true
        if (!WorkPoolEnabled())
            return false
        cmd := EncodeBatch(EncodeCommand("HM", tableItem.ID, item.ID, "post", "1"))
        this.taskQueue.Push({ cmd: cmd, tableID: tableItem.ID, itemID: item.ID "_hook", isGraphBranch: false, isHook: true })
        GraphPoolLog("后置钩子派发", Format("tab={1} item={2} 队列={3}"
            , tableItem.ID, item.ID, this.taskQueue.Size()))
        this.Dispatch()
        return true
    }

    ; 新一次宏触发前：清队列、强停残留 Worker、重置状态
    PrepareItemRun(tableID, itemID) {
        this.DrainItemTaskQueue(tableID, itemID)
        killed := this.KillWorkersForItem(tableID, itemID)
        tableItem := GetTableByID(tableID)
        if (!tableItem)
            return
        itemIndex := GetItemIndexInTable(tableItem, itemID)
        item := GetItemByIndex(tableItem, itemIndex)
        if (!item)
            return
        item.GraphBranchCount := 0
        item.Killed := false
        item.IsWorkIndex := 0
        if (killed)
            ReleaseTableItemHoldKeys(tableItem, itemIndex)
        item.HoldKey := Map()
        item.PostHookFired := false   ; 新一轮触发：后置钩子重新可派
    }

    ; 协作式通知 Worker 停止并松开按键（强杀前尽量先走这一步）
    RequestItemStop(tableID, itemID) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            for idx, wd in this.usePool {
                if (wd.tableID == tableID && wd.itemID == itemID) {
                    wd.stopRequested := true
                    this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("ST", wd.taskID)))
                }
            }
        } finally Critical(previousCritical)
    }

    SendItemPause(tableID, itemID, state) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            for idx, wd in this.usePool {
                if (wd.tableID == tableID && wd.itemID == itemID)
                    this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("PS", wd.taskID, state)))
            }
        } finally Critical(previousCritical)
    }

    ;分配任务
    Dispatch() {
        if (this.HasOwnProp("closing"))
            return
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
    }

    ; 移除已退出的空闲 Worker，并安排补建
    RemoveDeadFreeWorkers() {
        toClean := []
        for idx, wd in this.freePool {
            if (this.IsProcessDead(wd))
                toClean.Push(wd)
        }
        for wd in toClean {
            GraphPoolLog("Worker不可用", Format("Worker#{1} pid={2} 进程已退出 移出并补建", wd.idx, wd.pid))
            if (this.CleanUpWorker(wd))
                this.ScheduleRecreateWorker(wd.idx)
        }
    }

    ; 从 freePool 取一个 Worker，从 taskQueue 取一个任务，绑定后通知 Worker
    AssignTask() {
        previousCritical := A_IsCritical
        Critical("On")
        try return this._AssignTask()
        finally Critical(previousCritical)
    }

    _AssignTask() {
        if (!this.freePool.Count || !this.taskQueue.Size())
            return false
        for key, worker in this.freePool {
            idx := key
            wd := worker
            break
        }

        task := this.taskQueue.Pop()
        this.taskSequence := (this.taskSequence & 0xFFFFFFFF) + 1
        if (this.taskSequence > 0xFFFFFFFF)
            this.taskSequence := 1
        this.freePool.Delete(idx)
        this.usePool[idx] := wd
        wd.taskID := this.taskSequence
        wd.stopRequested := false
        wd.tableID := task.tableID
        wd.itemID := task.itemID
        wd.isGraphBranch := task.HasOwnProp("isGraphBranch") ? task.isGraphBranch : false
        wd.graphNodeSerial := ""
        if (wd.isGraphBranch) {
            ; R1 IPC 编码：TR|tableID|itemID|nodeSerial → 提取 nodeSerial
            try {
                if (SubStr(task.cmd, 1, 2) == "R1") {
                    rec := StrSplit(SubStr(task.cmd, 3), IPC_REC)[1]
                    parts := StrSplit(rec, IPC_SEP)
                    if (parts.Length >= 4)
                        wd.graphNodeSerial := UnescapeIPC(parts[4])
                }
            }
        }
        wd.idleTick := 0

        tableItem := GetTableByID(task.tableID)
        item := GetItemByIndex(tableItem, GetItemIndexInTable(tableItem, task.itemID))
        paused := item && item.Pause ? 1 : 0
        if (!this.PushTask(wd, MsgType.TASK, wd.taskID, task.cmd, paused)) {
            this.taskQueue.queue.InsertAt(1, task)
            if (this.CleanUpWorker(wd, false, true))
                this.ScheduleRecreateWorker(wd.idx)
            return false
        }
        GraphPoolLog("Dispatch分配", Format("Worker#{1} tab={2} item={3} graph={4} 闲置={5} 队列={6}"
            , wd.idx, task.tableID, task.itemID, task.isGraphBranch ? 1 : 0
            , this.freePool.Count, this.taskQueue.Size()))
        ; 钩子任务是收尾流程的附带执行，不计入宏执行次数。
        ; isHook 用 HasProp 判：任务对象是临时 Map，漏字段时直接访问会抛异常。
        if (!task.isGraphBranch && !(task.HasProp("isHook") && task.isHook))
            MySoftData.MacroTotalCount += 1
        return true
    }

    ; 检查该宏项是否还有未完成的工作（usePool 中的忙碌 Worker 或 taskQueue 中排队的图形分支）
    HasItemWork(tableID, itemID) {
        for idx, w in this.usePool {
            if (w.tableID == tableID && w.itemID == itemID)
                return true
        }
        for task in this.taskQueue.queue {
            if (task.tableID == tableID && task.itemID == itemID)
                return true
        }
        return false
    }

    ; 重置 Worker 的任务状态（任务完成或中止时调用）
    ; state: 0=正常完成, 3=异常中止
    ResetWorkerTaskState(wd, state) {
        if (wd.tableID == "" || wd.itemID == "") {
            wd.tableID := ""
            wd.itemID := ""
            return
        }

        tableItem := GetTableByID(wd.tableID)
        if (!tableItem) {
            wd.tableID := ""
            wd.itemID := ""
            wd.isGraphBranch := false
            return
        }
        itemIndex := GetItemIndexInTable(tableItem, wd.itemID)
        ; 用 GetItemByIndex 而非 Items[n]：钩子任务的身份是「主 ID + _hook」，
        ; 查不到会返回 0，直接下标会抛 Invalid index
        item := GetItemByIndex(tableItem, itemIndex)
        ; 图形宏并行分支：单项 Worker 结束时不改宏项全局占用/颜色，由 FinishGraphMacroItem 统一释放
        skipMacroRelease := wd.isGraphBranch && item && item.GraphBranchCount > 0

        if (!skipMacroRelease && item) {
            item.IsWorkIndex := 0
            if (state == 0) {
                itemState := item.Killed ? 3 : 0
            } else {
                itemState := 3
            }
            item.Killed := false
            SetTableItemState(tableItem, itemIndex, itemState)
        }

        wd.tableID := ""
        wd.itemID := ""
        wd.isGraphBranch := false
    }

    OnWorkerReady(wd, hwnd) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!wd.isPending || this.IsProcessDead(wd) || !this.IsInstanceAlive(wd))
                return
            pid := 0
            DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
            if (pid != wd.pid)
                return

            wd.hwnd := hwnd
            wd.idleTick := A_TickCount
            this.SyncStateToWorker(wd)
            if (wd.configDirty)
                this.SendConfigRefresh(wd)
            this.pending.Delete(wd.idx)
            wd.isPending := false
            this.freePool[wd.idx] := wd
        } finally Critical(previousCritical)
        this.Dispatch()
    }

    ; 快照与后续增量、任务使用同一条有序通道。
    SyncStateToWorker(wd) {
        variables := []
        for name, value in MySoftData.VariableMap
            variables.Push([name, value])
        arrays := []
        for name, value in MySoftData.ArrayMap
            arrays.Push([name, value])
        payload := EncodeBatch(EncodeCommand("CT", MySoftData.CMDTip)
            , EncodeCommand("SN", JSON.stringify([variables, arrays])))
        this.PushTask(wd, MsgType.EVENT, 0, payload)
    }

    ; ---- §17 热重载：配置变更 → Worker 重载（新增宏/宏内容保存选「否」即生效） ----

    ; §17/§18 总线回调：宏表整表变更（itemIndex==0 = 新增/删除宏/模块/内容/字段等 live 编辑已即时落盘）
    ; 与全量 Publish(0,0) → 广播 Worker 重载配置；行级变更（触发键/语音关键词等主进程消费）不重载 Worker
    OnHotReloadConfigChanged(tableIndex, itemIndex) {
        if (itemIndex != 0)
            return
        this.BroadcastConfigRefresh()
    }

    ; 广播配置刷新：空闲 Worker 立即发 CF；忙/启动中的置 configDirty，回空闲（FINISH/就绪）时补发
    BroadcastConfigRefresh() {
        if (this.workerMap.Count == 0)
            return
        GraphPoolLog("热重载", Format("Worker配置刷新 存活={1} 空闲={2} 忙={3} 启动中={4}"
            , this.workerMap.Count, this.freePool.Count, this.usePool.Count, this.pending.Count))
        for idx, wd in this.workerMap {
            wd.configDirty := true
        }
        for idx, wd in this.freePool {
            this.SendConfigRefresh(wd)
        }
    }

    ; 向指定 Worker 发送 CF（配置重载）事件并清标志
    SendConfigRefresh(wd) {
        if (!wd || !wd.tx)
            return
        if (this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("CF"))))
            wd.configDirty := false
    }

    ; 只摘除「同一个对象」：同编号的新实例（重建）不能被旧实例的清理顺带删掉。
    RemoveWorkerFromPools(wd) {
        for pool in [this.freePool, this.usePool, this.pending] {
            if (pool.Has(wd.idx) && pool[wd.idx] == wd)
                pool.Delete(wd.idx)
        }
    }

    ; FINISH 处理后把 Worker 放回空闲池。
    ; 处理过程中的状态更新（GetTableByID / SetTableItemState / 日志 / Dispatch）可能触发消息泵，
    ; 被新一轮热键或强制停止重入并清掉这个 wd。此时若照旧往池里放，空闲池就留下一个
    ; tx=0 的僵尸实例，下次分派时 wd.tx.Push 直接抛「Integer has no method named Push」。
    ReleaseWorkerToFreePool(wd) {
        this._CancelWorkerInputs(wd)
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!this.IsInstanceAlive(wd))
                return false
            this.usePool.Delete(wd.idx)
            wd.taskID := 0
            wd.tableID := ""
            wd.itemID := ""
            wd.isGraphBranch := false
            wd.graphNodeSerial := ""
            wd.idleTick := A_TickCount
            if (wd.configDirty)
                this.SendConfigRefresh(wd)
            this.freePool[wd.idx] := wd
            return true
        } finally Critical(previousCritical)
    }

    ; wd 是否仍是线程池里登记在册的活实例（未被强杀/缩容/重载清理，也未被同编号新实例替换）。
    ; 清理过的实例 tx/rx 已置 0，再拿去 wd.tx.Push 会抛「Integer has no method named Push」。
    IsInstanceAlive(wd) {
        return wd && wd.tx && this.workerMap.Has(wd.idx) && this.workerMap[wd.idx] == wd
    }

    ; 先停止进程，再读取最后已提交的按键状态并关闭通道。
    CleanUpWorker(wd, resetTask := true, terminateProcess := false, releaseKeys := false, expectedTaskID := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!wd || !this.workerMap.Has(wd.idx) || this.workerMap[wd.idx] != wd)
                return false
            if (expectedTaskID && wd.taskID != expectedTaskID)
                return false
            if (wd.hProc && !this.IsProcessDead(wd)) {
                if (!terminateProcess) {
                    this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("QT")))
                    DllCall("WaitForSingleObject", "ptr", wd.hProc, "uint", this.stopTimeoutMs)
                }
                if (!this.IsProcessDead(wd)) {
                    DllCall("TerminateProcess", "ptr", wd.hProc, "uint", 1)
                    if (DllCall("WaitForSingleObject", "ptr", wd.hProc, "uint", 200, "uint") != 0)
                        return false
                }
            }

            this.workerMap.Delete(wd.idx)
            this.RemoveWorkerFromPools(wd)
            if (wd.taskID)
                this.DrainWorkerHoldEvents(wd)
            if (wd.tx)
                wd.tx.Invalidate()
            if (wd.rx)
                wd.rx.Invalidate()
            wd.tx := 0
            wd.rx := 0
            if (wd.shmTx)
                wd.shmTx.Close()
            if (wd.shmRx)
                wd.shmRx.Close()
            if (wd.hEvt)
                CloseHandle(wd.hEvt)
            if (wd.hProc)
                CloseHandle(wd.hProc)
            wd.hEvt := 0
            wd.hProc := 0
        } finally Critical(previousCritical)
        if (releaseKeys && wd.taskID)
            this.ReleaseWorkerTaskKeys(wd)
        if (resetTask)
            this.ResetWorkerTaskState(wd, 3)
        this._CancelWorkerInputs(wd)
        if (wd.pid)
            try CloseXamlCountDownForWorker(wd.pid)
        return true
    }

    DrainWorkerHoldEvents(wd) {
        try {
            while (wd.rx && wd.rx.Pop(&type, &id, &payload)) {
                if (type != MsgType.EVENT || id != wd.taskID)
                    continue
                for record in StrSplit(SubStr(payload, 3), IPC_REC) {
                    parts := StrSplit(record, IPC_SEP)
                    if (parts.Length == 6 && parts[1] == "HK")
                        SyncWorkerHoldKey(UnescapeIPC(parts[2]), UnescapeIPC(parts[3]), UnescapeIPC(parts[4])
                            , UnescapeIPC(parts[5]), UnescapeIPC(parts[6]))
                }
            }
        }
    }

    ReleaseWorkerTaskKeys(wd) {
        tableItem := GetTableByID(wd.tableID)
        if (tableItem)
            ReleaseTableItemHoldKeys(tableItem, GetItemIndexInTable(tableItem, wd.itemID))
    }

    ScheduleRecreateWorker(index) {
        if (!this.HasOwnProp("closing"))
            SetTimer(() => this.TryRecreateWorker(index), -500)
    }

    TryRecreateWorker(index) {
        if (this.HasOwnProp("closing") || this.workerMap.Has(index))
            return
        this.CreateWorker(index)
        this.Dispatch()
    }

    IsProcessDead(wd) {
        return wd.hProc && DllCall("WaitForSingleObject", "ptr", wd.hProc, "uint", 0, "uint") == 0
    }

    AbortDeadWorkerTask(wd) {
        tableID := wd.tableID
        itemID := wd.itemID
        wasStopping := wd.stopRequested
        tableItem := GetTableByID(tableID)
        index := GetItemIndexInTable(tableItem, itemID)
        item := GetItemByIndex(tableItem, index)
        if (!this.CleanUpWorker(wd, false, true))
            return
        this.ScheduleRecreateWorker(wd.idx)
        if (item && !wasStopping) {
            ; 图形分支共享按键状态，先停下同一轮的其它分支，再统一松键。
            if (wd.isGraphBranch || item.GraphBranchCount > 0)
                this.ForceStopItem(tableID, itemID)
            else {
                this.ReleaseWorkerTaskKeys(wd)
                item.ToggleState := false
                this.ResetWorkerTaskState(wd, 3)
            }
        }
        this.Dispatch()
    }

    FreeShrinkCheck() {
        maxShrink := this.freePool.Count - this.corePoolSize
        if (maxShrink <= 0)
            return

        now := A_TickCount
        toShrink := []
        for idx, wd in this.freePool {
            if (toShrink.Length >= maxShrink)
                break
            if (wd.idleTick > 0 && (now - wd.idleTick) >= this.elasticTimeout)
                toShrink.Push(wd)
        }
        ; 先收集再清理：CleanUpWorker 会从 freePool 删除元素，直接在遍历中删会跳过/漏项
        for wd in toShrink {
            if (this.freePool.Has(wd.idx) && this.freePool[wd.idx] == wd)
                this.CleanUpWorker(wd)
        }
    }

    PollWorkerRx() {
        if (this.HasOwnProp("closing"))
            return
        workers := []
        for idx, wd in this.workerMap
            workers.Push(wd)
        for wd in workers {
            if (!this.IsInstanceAlive(wd) || wd.rxBusy)
                continue
            if (wd.tx.Flush())
                this.WakeWorker(wd)
            if (!wd.rx.IsEmpty())
                this.ProcessWorkerRx(wd)
            if (!this.IsInstanceAlive(wd))
                continue
            if (this.IsProcessDead(wd) || (wd.isPending && A_TickCount - wd.createTick > 30000))
                this.AbortDeadWorkerTask(wd)
        }
    }

    ; 窗口消息只负责唤醒，所有数据和就绪握手都从该 Worker 的 RX 读取。
    OnWorkerToMaster(wParam := 0, lParam := 0, msg := 0, hwnd := 0) {
        if (!this.HasOwnProp("closing") && this.workerMap.Has(wParam))
            this.ProcessWorkerRx(this.workerMap[wParam])
    }

    GetBusyWorkerIds() {
        ids := ""
        for idx in this.usePool
            ids .= (ids != "" ? "," : "") idx
        return ids != "" ? ids : "无"
    }

    ProcessWorkerRx(wd) {
        if (!this.IsInstanceAlive(wd) || wd.rxBusy)
            return
        wd.rxBusy := true
        failed := false
        try {
            while (this.IsInstanceAlive(wd) && wd.rx.Pop(&type, &id, &result)) {
                if (!this.IsInstanceAlive(wd))
                    break
                switch type {
                    case MsgType.READY:
                        this.OnWorkerReady(wd, Integer(result))
                    case MsgType.FINISH:
                        if (wd.taskID == id && this.usePool.Has(wd.idx))
                            this.HandleWorkerFinish(wd, result)
                    case MsgType.EVENT:
                        if (!wd.isPending && (id == 0 || id == wd.taskID))
                            this.OnWorkerEvent(wd, result)
                    default:
                        throw Error("Unexpected Worker packet")
                }
            }
        } catch as err {
            failed := true
            GraphPoolLog("Worker通信失败", Format("Worker#{1} line={2} op={3}", wd.idx, err.Line, err.What))
        } finally wd.rxBusy := false
        if (failed && this.IsInstanceAlive(wd)) {
            this.AbortDeadWorkerTask(wd)
        }
    }

    HandleWorkerFinish(wd, result) {
        tableID := wd.tableID
        itemID := wd.itemID
        tableItem := GetTableByID(tableID)
        index := GetItemIndexInTable(tableItem, itemID)
        item := GetItemByIndex(tableItem, index)
        isGraphTask := item && (wd.isGraphBranch || item.GraphBranchCount > 0)
        if (item && !isGraphTask && result == "0")
            item.PostHookFired := true
        if (!wd.stopRequested && item) {
            if (isGraphTask) {
                item.GraphBranchCount := Max(0, item.GraphBranchCount - 1)
                if (result != "0")
                    item.Killed := true
            } else {
                if (result != "0") {
                    this.ReleaseWorkerTaskKeys(wd)
                    item.ToggleState := false
                }
                this.ResetWorkerTaskState(wd, result == "0" ? 0 : 3)
            }
        }
        stopping := wd.stopRequested
        if (!this.ReleaseWorkerToFreePool(wd))
            return
        if (isGraphTask && !stopping) {
            if (result != "0" && this.HasItemWork(tableID, itemID))
                this.ForceStopItem(tableID, itemID)
            else if (!this.HasItemWork(tableID, itemID))
                this.FinishGraphMacroItem(tableID, itemID)
        }
        this.Dispatch()
    }

    OnWorkerEvent(wd, payload) {
        if (SubStr(payload, 1, 2) != "R1")
            return

        commandsStr := SubStr(payload, 3)
        for record in StrSplit(commandsStr, IPC_REC) {
            if (record == "")
                continue

            parts := StrSplit(record, IPC_SEP)
            if (parts.Length == 0)
                continue

            opcode := parts[1]
            args := []
            loop parts.Length - 1 {
                args.Push(UnescapeIPC(parts[A_Index + 1]))
            }

            try {
                switch opcode {
                    case "GS":
                        this.CommitWorkerData(wd, args[1], Integer(args[2]), args[3])
                    case "RP":
                        CMDReport(args[1])
                    case "FR":
                        ; 输出→指令窗口：强制显示，不经 CMDTip 门控
                        CmdTipForceShow(args[1])
                    case "RC":
                        ExcuteRMTCMDAction(args[1])
                    case "PS":
                        tableItem := GetTableByID(args[1])
                        if (tableItem)
                            SetItemPauseState(tableItem, GetItemIndexInTable(tableItem, args[2]), args[3])
                    case "NT":
                        QueuePromptDisplay(args[1])
                    case "CD":
                        ; 交给空闲任务建窗，避免在 Worker 消息回调中同步创建 XAML。
                        SetTimer(this._CountDownUiRequest.Bind(this, args.Clone(), wd, wd.pid), -10)
                    case "MB":
                        MsgBoxContent(args[1])
                    case "TT":
                        ToolTipContent(args[1])
                    case "OT":
                        OutputTipContent(args[1])
                    case "IP", "IB", "IF":
                        this._QueueWorkerInput(wd, Integer(args.RemoveAt(1)), opcode, args*)
                    case "IC":
                        this._CancelWorkerInput(wd, Integer(args[1]))
                    case "JY":
                        JoyDebugLog(Format("WorkPool recv JY args=[{}, {}, {}] from worker#{}"
                            , args.Length >= 1 ? args[1] : "", args.Length >= 2 ? args[2] : ""
                            , args.Length >= 3 ? args[3] : "", wd.idx), "pool")
                        ViGJoySetState(args[1], args[2], args[3])
                    case "ER":
                        ; Worker 错误上报（统一日志 C 项）：payload = "级别|workerIdx|完整信息"
                        ; 主进程聚合到错误中心 + 写系统日志；错误中心已有 ErrorList 累积显示
                        try {
                            erParts := StrSplit(args[1], "|", , 3)
                            erLevel := erParts.Length >= 1 ? erParts[1] : "error"
                            erSrc := erParts.Length >= 2 ? ("Worker#" erParts[2]) : ("Worker#" wd.idx)
                            erMsg := erParts.Length >= 3 ? erParts[3] : args[1]
                            ; 走 RMTErrorShow 统一按级别通知（warn 气泡 / error 错误中心，均可开关）
                            RMTErrorShow("宏执行异常: " erMsg, erLevel, erSrc)
                        } catch {
                            RMTLogSys(RMT_LV_ERROR, "Worker#" wd.idx, "ER解析失败: " args[1])
                            MyErrorMsgBoxGui.ShowGui(args[1])
                        }
                    case "ST":
                        tableItem := GetTableByID(args[1])
                        if (tableItem) {
                            stopIndex := GetItemIndexInTable(tableItem, args[2])
                            stopItem := GetItemByIndex(tableItem, stopIndex)
                            if (stopItem && !(wd.tableID == args[1] && wd.itemID == args[2]))
                                SetTimer(StopMacro.Bind(tableItem, stopIndex), -1)
                        }
                    case "HK":
                        ; Worker 同步按键按住状态：tableID, itemID, key, state, source
                        SyncWorkerHoldKey(args[1], args[2], args[3], args[4], args.Length >= 5 ? args[5] : "")
                    case "GB":
                        tIdx := args[1]
                        iIdx := args[2]
                        nodeSerials := []
                        loop args.Length - 2 {
                            nodeSerials.Push(args[A_Index + 2])
                        }
                        HandleWorkerGraphBranches(wd, tIdx, iIdx, nodeSerials)
                    case "TR":
                        ; Worker 请求主进程触发（TR_MACRO 分支指令）：args = tableID, itemID
                        TriggerMacroHandler(args[1], args[2])
                }
            } catch {
            }
        }
    }

    CommitWorkerData(wd, requestID, deadline, payload) {
        ok := false
        previousCritical := A_IsCritical
        try {
            request := JSON.parse(payload)
            Critical("On")
            if (this.IsInstanceAlive(wd) && wd.taskID && !wd.stopRequested
                && DllCall("GetTickCount64", "uint64") < deadline) {
                CommitGlobalData(request[1], request[2])
                ok := true
            }
        } catch {
            ok := false
        } finally Critical(previousCritical)
        this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("VR", requestID, ok)))
    }

    _RemoveInputGui(req) {
        if (IsObject(this._inputGuis) && this._inputGuis.Has(req))
            this._inputGuis.Delete(req)
    }

    ; 输入弹窗：每请求独立实例（并发互不阻塞）；Worker 请求结果跨进程回传，主进程宏请求写本地槽位
    _QueueWorkerInput(wd, requestID, opcode, args*) {
        if (!wd.taskID || wd.stopRequested)
            return
        req := {wd: wd, taskID: wd.taskID, id: requestID, local: false, done: false}
        this._inputGuis[req] := true
        SetTimer((*) => this._ShowInputDialogReq(req, opcode, args*), -10)
    }

    _CancelWorkerInput(wd, id) {
        for req in this._inputGuis {
            if (!req.local && req.wd == wd && req.id == id) {
                this._CancelInput(req)
                break
            }
        }
    }

    _CancelWorkerInputs(wd) {
        pending := []
        for req in this._inputGuis {
            if (!req.local && req.wd == wd)
                pending.Push(req)
        }
        for req in pending
            this._CancelInput(req)
    }

    _CancelInput(req) {
        req.done := true
        this._RemoveInputGui(req)
        try req.gui._CloseWindow()
        req.gui := ""
    }

    ; 主进程宏输入请求：SetTimer 异步弹窗（避免宏执行上下文同步 XAMLHost），结果写回 req.result
    RequestLocalInput(opcode, timeoutMs, item, args*) {
        req := { wd: { idx: 0 }, local: true, done: false, result: "", item: item }
        argArr := []
        for a in args
            argArr.Push(a)
        SetTimer((*) => this._ShowInputDialogReq(req, opcode, argArr*), -10)
        deadline := InputResponseDeadline(timeoutMs, 500, item)
        loop {
            Sleep(100)
            if (IsObject(item) && item.Killed) {
                this._CancelInput(req)
                return ""
            }
            if (req.done)
                break
            if (deadline && A_TickCount > deadline) {
                this._TimeoutInputDialog(req, opcode)
                break
            }
        }
        this._RemoveInputGui(req)
        return req.result
    }

    _ShowInputDialogReq(req, opcode, args*) {
        if (req.done)
            return
        this._inputGuis[req] := true   ; 追踪活动实例
        GraphPoolLog("输入请求处理", Format("wd=#{1} op={2}", req.wd.idx, opcode))
        pack := SplitInputReqArgs(args)
        real := pack.args
        try {
            if (opcode == "IF") {
                req.nativeFile := true
                this._nativeFileQueue.Push({req: req, timeoutMs: pack.timeoutMs,
                    title: real.Length ? SubStr(real[1], 7) : GetLang("选择文件")})
                this._ScheduleNativeFile()
                return
            }
            if (opcode == "IB") {
                ; 输入按钮条
                gui := InputBtnXamlGui()
                req.gui := gui
                gui.TrueAction := (*) => this._SendInputResult(req, "IBR", "true")
                gui.FalseAction := (*) => this._SendInputResult(req, "IBR", "false")
                gui.ContinueAction := (*) => this._SendInputResult(req, "IBR", "continue")
                gui.CancelAction := (*) => this._SendInputResult(req, "IBR", "cancel")
                gui.PauseAction := (*) => this._SendInputResult(req, "IBR", "pause")
                gui.TerminateAction := (*) => this._SendInputResult(req, "IBR", "terminate")
                gui.SelectAction := (val) => this._SendInputResult(req, "IBR", val)
                gui.HideAction := (*) => this._SendInputResult(req, "IBR", "cancel")
                gui.ShowGui(Integer(real.Length >= 1 ? real[1] : 1)
                    , real.Length >= 2 ? real[2] : ""
                    , real.Length >= 3 ? real[3] : ""
                    , real.Length >= 4 ? real[4] : "")
            } else {
                ; XAML 输入框
                gui := CustomInputGui()
                req.gui := gui
                gui.SureAction := (val) => this._SendInputResult(req, "IPR", "1", val)
                gui.HideAction := (*) => this._SendInputResult(req, "IPR", "0", "")
                gui.CloseAction := (*) => this._SendInputResult(req, "IPR", "0", "")
                gui.ShowGui(real.Length >= 1 ? real[1] : "", real.Length >= 2 ? real[2] : "")
            }
            if (pack.timeoutMs > 0)
                SetTimer((*) => this._TimeoutInputDialog(req, opcode), -pack.timeoutMs)
        } catch as e {
            GraphPoolLog("输入弹窗异常", Format("err={1} wd=#{2}", e.Message, req.wd.idx))
            if (opcode == "IB")
                this._SendInputResult(req, "IBR", "cancel")
            else
                this._SendInputResult(req, "IPR", "0", "")
        }
    }

    _ScheduleNativeFile() {
        if (!this._nativeFileActive && this._nativeFileQueue.Length && this._nativeFileNext = "") {
            this._nativeFileNext := ObjBindMethod(this, "_ShowNextNativeFile")
            SetTimer(this._nativeFileNext, -1)
        }
    }

    _ShowNextNativeFile() {
        this._nativeFileNext := ""
        if (this._nativeFileActive)
            return
        while (this._nativeFileQueue.Length) {
            request := this._nativeFileQueue.RemoveAt(1)
            req := request.req
            if (req.done)
                continue
            ; Windows 原生文件选择器在主线程使用模态循环，不在其中嵌套另一个。
            this._nativeFileActive := true
            timeoutCheck := (*) => this._TimeoutInputDialog(req, "IF")
            cancelCheck := () => req.item.Killed && this._CancelInput(req)
            try {
                dialog := InputFileDialog(this.workerExe)
                this._nativeFileCurrent := dialog
                req.gui := dialog
                if (request.timeoutMs > 0)
                    SetTimer(timeoutCheck, -request.timeoutMs)
                if (req.local && IsObject(req.item))
                    SetTimer(cancelCheck, 100)
                path := dialog.Show(request.title)
                if (req.HasOwnProp("fileTimedOut"))
                    this._SendInputResult(req, "IPR", "timeout")
                else
                    this._SendInputResult(req, "IPR", path != "" ? "1" : "0", path)
            } catch as e {
                GraphPoolLog("输入弹窗异常", Format("err={1} wd=#{2}", e.Message, req.wd.idx))
                this._SendInputResult(req, "IPR", req.HasOwnProp("fileTimedOut") ? "timeout" : "0", "")
            } finally {
                SetTimer(timeoutCheck, 0)
                SetTimer(cancelCheck, 0)
                this._nativeFileCurrent := ""
                this._nativeFileActive := false
                this._ScheduleNativeFile()
            }
            return
        }
    }

    _TimeoutInputDialog(req, opcode) {
        if (req.done)
            return
        gui := req.HasOwnProp("gui") ? req.gui : ""
        if (opcode == "IF" && gui is InputFileDialog) {
            ; 先退出原生模态循环，再回传结果，避免 Worker 紧接着重入文件选择。
            req.fileTimedOut := true
            gui._CloseWindow()
            return
        }
        this._SendInputResult(req, opcode == "IB" ? "IBR" : "IPR", "timeout")
        try gui._CloseWindow()
    }

    ; 回传输入结果（同一请求只回传一次）
    _SendInputResult(req, opcode, args*) {
        if (req.done)
            return
        req.done := true
        this._RemoveInputGui(req)
        try req.gui := ""
        catch {
            ; 注意：catch 必须带大括号，否则会吞掉下方回传 try 块
        }
        if (req.local) {
            req.result := args
        } else if (this.IsInstanceAlive(req.wd) && req.wd.taskID == req.taskID) {
            payload := EncodeBatch(EncodeCommand(opcode, req.id, args*))
            this.PushTask(req.wd, MsgType.EVENT, 0, payload)
        }
    }

    _CountDownUiRequest(args, wd, pid) {
        if (args[1] == "closeAt") {
            CloseXamlCountDownAt(args[2])
            return
        }
        if (args[1] == "stop") {
            CloseXamlCountDown(args[2])
            return
        }
        if (wd.pid != pid || !this.IsInstanceAlive(wd))
            return
        token := args[2]
        done := (*) => this._CountDownUiClosed(wd, pid, token)
        ownerPid := args.Length >= 6 && args[6] == "1" ? 0 : pid
        try StartXamlCountDown(token, Number(args[3]), Number(args[4]), Number(args[5]), done, ownerPid)
        catch as e {
            RMTLogSys(RMT_LV_ERROR, "CountDown", e.Message)
            done.Call()
        }
    }

    _CountDownUiClosed(wd, pid, token) {
        if (wd.pid == pid)
            this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("CDR", token)))
    }

    PushTask(wd, type, id, payload, flags := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!this.IsInstanceAlive(wd) || !wd.tx.Send(type, id, payload, flags))
                return false
            this.WakeWorker(wd)
            return true
        } finally Critical(previousCritical)
    }

    WakeWorker(wd) {
        if (wd.hEvt)
            SetEvent(wd.hEvt)
        if (wd.hwnd)
            DllCall("PostMessageW", "ptr", wd.hwnd, "uint", WM_MASTER_TO_WORKER, "uptr", 0, "ptr", 0)
    }
}
