#Requires AutoHotkey v2.0
#Include Util\SharedMemory.ahk
#Include Util\RingBuffer.ahk
#Include Util\JsonUtil.ahk

; 枚举系统中所有进程，返回 [{pid, name, parentPid}, ...]。
; 用于残留 Worker 检测：找出父进程为当前主进程、但已不在线程池追踪中的 Work.exe。
; 采用 Toolhelp32 快照（TH32CS_SNAPPROCESS），不依赖窗口可见性，headless Worker 也能枚举到。
EnumProcesses() {
    procs := []
    ; TH32CS_SNAPPROCESS = 0x00000002
    hSnap := DllCall("CreateToolhelp32Snapshot", "uint", 0x00000002, "uint", 0, "ptr")
    if (!hSnap)
        return procs

    ; PROCESSENTRY32W 字段布局：
    ;   dwSize(4) cntUsage(4) th32ProcessID(4) th32DefaultHeapID(A_PtrSize)
    ;   th32ModuleID(4) cntThreads(4) th32ParentProcessID(4) pcPriClassBase(4) dwFlags(4) szExeFile[260]
    structSize := 32 + A_PtrSize + 520
    pidOffset := 8
    parentOffset := 20 + A_PtrSize
    nameOffset := 32 + A_PtrSize

    entry := Buffer(structSize, 0)
    NumPut("uint", structSize, entry, 0)   ; dwSize

    if (!DllCall("Process32FirstW", "ptr", hSnap, "ptr", entry)) {
        DllCall("CloseHandle", "ptr", hSnap)
        return procs
    }

    loop {
        pid := NumGet(entry, pidOffset, "uint")
        parentPid := NumGet(entry, parentOffset, "uint")
        name := StrGet(entry.Ptr + nameOffset, "utf-16")
        if (pid)
            procs.Push({ pid: pid, name: name, parentPid: parentPid })
        if (!DllCall("Process32NextW", "ptr", hSnap, "ptr", entry))
            break
    }

    DllCall("CloseHandle", "ptr", hSnap)
    return procs
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
        this.tableID := ""            ; Worker 当前正在处理的宏所属的表 ID（空=空闲）
        this.itemID := ""             ; Worker 当前正在处理的宏的条目 ID（空=空闲）
        this.isGraphBranch := false   ; 是否为图形宏并行分支任务
        this.graphNodeSerial := ""    ; 图形分支起始节点（异常退出时重派）
        this.rxBusy := false          ; ProcessWorkerRx 重入保护
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
        this.stopTimeoutMs := 150      ; 协作终止等待超时(ms)，超时后强杀进程重建

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
        this.residualCheckFunc := ""
        this._inputGuis := Map()      ; 活动输入弹窗实例（key=req）

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

        ; 残留 Worker 清理：每 10 分钟枚举一次 Work.exe，强杀不在线程池追踪中的残留进程
        this.residualCheckFunc := ObjBindMethod(this, "CheckResidualWorkers")
        SetTimer(this.residualCheckFunc, 600000)
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
        if (this.residualCheckFunc != "") {
            SetTimer(this.residualCheckFunc, 0)
            this.residualCheckFunc := ""
        }

        ; 先收集所有存活 Worker，避免遍历时改动 freePool/usePool/pending
        allWorkers := []
        for idx, wd in this.freePool
            allWorkers.Push(wd)
        for idx, wd in this.usePool
            allWorkers.Push(wd)
        for idx, wd in this.pending
            allWorkers.Push(wd)

        ; 优雅通知退出后，强制终止并显式释放共享内存/事件句柄：
        ; 确保 Reload 前 RMT_TX_/RMT_RX_/RMT_EVT_ 等命名对象被彻底释放，
        ; 避免新旧实例（Worker 进程）竞争同一命名共享内存/事件导致报错。
        for wd in allWorkers {
            this.PostMessage(WM_CLEAR_WORK, wd)
            this.CleanUpWorker(wd, false, true)
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
        evtName := "RMT_EVT_" idx

        wd.shmTx := SharedMemory(txName, 1048576 + 192)
        wd.tx := RingBuffer(wd.shmTx.ptr, 1048576)

        wd.shmRx := SharedMemory(rxName, 1048576 + 192)
        wd.rx := RingBuffer(wd.shmRx.ptr, 1048576)

        wd.hEvt := CreateEvent(evtName)
        wd.createTick := A_TickCount
        this.pending[idx] := wd

        Run(Format('"{}" {} {} {}'
            ; parentHwnd 必须用主进程窗口（A_ScriptHwnd）：XAML 迁移后 MyGui.Hwnd 是 daemon 进程窗口，
            ; Worker PostMessage 到它收不到主进程 OnMessage，导致 Worker→主进程消息（MsgSendHandler/输入请求）全部失效
            , this.workerExe
            , idx
            , A_ScriptHwnd
            , this.mainPID), , , &pid)

        wd.pid := pid
        ; PROCESS_TERMINATE | PROCESS_DUP_HANDLE | SYNCHRONIZE，供强制停止时 TerminateProcess
        wd.hProc := DllCall("OpenProcess", "uint", 0x0001 | 0x0040 | 0x00100000, "int", false, "uint", pid, "ptr")
        this.workerMap[idx] := wd
        GraphPoolLog("CreateWorker", Format("Worker#{1} 已启动 pid={2} pending={3} maxSize={4}"
            , idx, pid, this.pending.Count, this.maxSize))
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
        this.taskQueue.Push({ cmd: cmd, tableID: tableID, itemID: itemID, isGraphBranch: false })
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
    FinishGraphMacroItem(tableID, itemID) {
        this.DrainItemTaskQueue(tableID, itemID)
        tableItem := GetTableByID(tableID)
        if (!tableItem)
            return
        itemIndex := GetItemIndexInTable(tableItem, itemID)
        item := tableItem.Items[itemIndex]
        if (!item)
            return
        itemState := 0
        if (item.Killed)
            itemState := 3
        item.Killed := false
        item.IsWorkIndex := 0
        item.GraphBranchCount := 0
        SetTableItemState(tableItem, itemIndex, itemState)
        GraphPoolLog("图形宏结束", Format("tab={1} item={2} state={3}", tableID, itemID, itemState))
    }

    DrainItemTaskQueue(tableID, itemID) {
        kept := []
        drained := 0
        while (this.taskQueue.Size() > 0) {
            task := this.taskQueue.Pop()
            if (task.tableID == tableID && task.itemID == itemID)
                drained++
            else
                kept.Push(task)
        }
        for t in kept
            this.taskQueue.Push(t)
        if (drained > 0)
            GraphPoolLog("清空任务队列", Format("tab={1} item={2} 丢弃={3}", tableID, itemID, drained))
    }

    ; 强制终止正在执行某宏项的 Worker 进程并安排重建。
    ; 搜图等 DllCall 期间协作式 Killed/ST 无法打断，只能杀进程。
    KillWorkersForItem(tableID, itemID) {
        toKill := []
        for idx, wd in this.usePool {
            if (wd.tableID == tableID && wd.itemID == itemID)
                toKill.Push(wd)
        }
        for wd in toKill {
            reuseIdx := wd.idx
            deadPid := wd.pid
            GraphPoolLog("强制停止Worker", Format("Worker#{1} tab={2} item={3} pid={4}"
                , reuseIdx, tableID, itemID, deadPid))
            ; 先切断环缓冲引用并移出 workerMap，再杀进程/Unmap，避免 Poll 读已释放内存
            this.CleanUpWorker(wd, true, true)
            this.ScheduleRecreateWorker(reuseIdx, deadPid)
        }
        return toKill.Length
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
        item := tableItem.Items[itemIndex]
        if (!item)
            return
        item.GraphBranchCount := 0

        ; 1) 标记终止：主进程 Killed（供 FINISH 时判定终态 3）+ ST 通知 Worker 侧置 Killed 并松开按键
        KillTableItemMacro(tableItem, itemIndex)

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

        item.IsWorkIndex := 0
        SetTableItemState(tableItem, itemIndex, 3)
    }

    ; 新一次宏触发前：清队列、强停残留 Worker、重置状态
    PrepareItemRun(tableID, itemID) {
        this.DrainItemTaskQueue(tableID, itemID)
        this.KillWorkersForItem(tableID, itemID)
        tableItem := GetTableByID(tableID)
        if (!tableItem)
            return
        itemIndex := GetItemIndexInTable(tableItem, itemID)
        item := tableItem.Items[itemIndex]
        if (!item)
            return
        item.GraphBranchCount := 0
        item.Killed := false
        item.IsWorkIndex := 0
        item.HoldKey := Map()
    }

    ; 协作式通知 Worker 停止并松开按键（强杀前尽量先走这一步）
    RequestItemStop(tableID, itemID) {
        payload := EncodeBatch(EncodeCommand("ST", tableID, itemID))
        for idx, wd in this.usePool {
            if (wd.tableID == tableID && wd.itemID == itemID)
                this.PushTask(wd, MsgType.EVENT, 0, payload)
        }
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

        if (wd.hEvt)
            DllCall("SetEvent", "ptr", wd.hEvt)
        if (!this.PostMessage(WM_MASTER_TO_WORKER, wd)) {
            this.usePool.Delete(idx)
            this.freePool[idx] := wd
            wd.tableID := ""
            wd.itemID := ""
            wd.isGraphBranch := false
            wd.graphNodeSerial := ""
            this.taskQueue.queue.InsertAt(1, task)
            GraphPoolLog("Dispatch失败", Format("Worker#{1} PostMessage失败 node={2}", wd.idx, wd.graphNodeSerial))
            return false
        }
        GraphPoolLog("Dispatch分配", Format("Worker#{1} tab={2} item={3} graph={4} 闲置={5} 队列={6}"
            , wd.idx, task.tableID, task.itemID, task.isGraphBranch ? 1 : 0
            , this.freePool.Count, this.taskQueue.Size()))
        return true
    }

    ; 检查该宏项是否还有未完成的工作（usePool 中的忙碌 Worker 或 taskQueue 中排队的图形分支）
    HasItemWork(tableID, itemID) {
        for idx, w in this.usePool {
            if (w.tableID == tableID && w.itemID == itemID)
                return true
        }
        for task in this.taskQueue.queue {
            if (task.isGraphBranch && task.tableID == tableID && task.itemID == itemID)
                return true
        }
        return false
    }

    ; 延迟尝试结束图形宏项（用于 Worker 完成后还有排队任务的情况）
    TryFinishGraphItem(tID, iID) {
        tableItem := GetTableByID(tID)
        if (!tableItem)
            return
        itemIndex := GetItemIndexInTable(tableItem, iID)
        item := tableItem.Items[itemIndex]
        if (item && item.GraphBranchCount > 0)
            return
        if (this.HasItemWork(tID, iID))
            return
        this.FinishGraphMacroItem(tID, iID)
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
        item := tableItem.Items[itemIndex]
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
        ; 同步指令显示状态：Worker 默认 false，需在就绪时拉取主进程当前值
        this.PushTask(wd, MsgType.EVENT, 0, EncodeBatch(EncodeCommand("CT", MySoftData.CMDTip)))

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

    ; resetTask: 是否重置宏项占用状态
    ; terminateProcess: 强制停止时先杀进程再关映射
    CleanUpWorker(wd, resetTask := true, terminateProcess := false) {
        if (!wd)
            return
        if (resetTask)
            this.ResetWorkerTaskState(wd, 3)
        this.RemoveWorkerFromPools(wd.idx)
        this.workerMap.Delete(wd.idx)

        ; 必须先切断 tx/rx，正在执行的 ProcessWorkerRx 会因此立刻退出，不再 Pop
        shmTx := wd.shmTx
        shmRx := wd.shmRx
        tx := wd.tx
        rx := wd.rx
        hEvt := wd.hEvt
        hProc := wd.hProc
        wd.tx := 0
        wd.rx := 0
        wd.shmTx := 0
        wd.shmRx := 0
        wd.hEvt := 0
        wd.hProc := 0

        ; 使残留的 RingBuffer 引用（如 ProcessWorkerRx 内暂停时捕获的 rb）失效，
        ; 防止 Unmap 后再次 NumGet 读取已释放内存
        if (tx)
            tx.Invalidate()
        if (rx)
            rx.Invalidate()

        if (terminateProcess) {
            if (hProc)
                DllCall("TerminateProcess", "ptr", hProc, "uint", 1)
            if (wd.pid && ProcessExist(wd.pid)) {
                try ProcessClose(wd.pid)
            }
        }

        try {
            if (shmTx)
                shmTx.Close()
            if (shmRx)
                shmRx.Close()
            if (hEvt)
                CloseHandle(hEvt)
            if (hProc)
                CloseHandle(hProc)
        }

        ; 残留诊断：解除追踪后短暂等待，若进程仍存活则记录（残留 Work.exe 的关键线索）。
        ; 强杀(terminateProcess=true)为异步；缩容/重载(terminateProcess=false)依赖 WM_CLEAR_WORK 让 Worker
        ; 自行退出，二者都留出短暂时间后仍未退出，才视为疑似残留。后续由 CheckResidualWorkers 兜底强杀。
        if (wd.pid) {
            waited := 0
            while (waited < 200 && ProcessExist(wd.pid)) {
                Sleep(10)
                waited += 10
            }
            if (ProcessExist(wd.pid))
                GraphPoolLog("Worker清理后仍存活", Format("Worker#{1} pid={2} 方式={3} 进程未退出"
                    , wd.idx, wd.pid, terminateProcess ? "强杀" : "仅解除追踪"))
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
        tID := wd.tableID
        iID := wd.itemID
        startNode := wd.graphNodeSerial
        GraphPoolLog("Worker进程退出", Format("Worker#{1} Master检测到进程已退出(非StopMacro) tab={2} item={3} graph={4} node={5} pid={6}"
            , wd.idx, tID, iID, wd.isGraphBranch ? 1 : 0, startNode, wd.pid))
        isGraphTask := false
        if (tID && iID) {
            tableItem := GetTableByID(tID)
            if (tableItem) {
                itemIndex := GetItemIndexInTable(tableItem, iID)
                item := tableItem.Items[itemIndex]
                branchCount := item ? item.GraphBranchCount : 0
                isGraphTask := (wd.isGraphBranch || branchCount > 0)
                if (isGraphTask && item) {
                    remainCount := branchCount
                    if (branchCount > 0) {
                        item.GraphBranchCount--
                        remainCount := item.GraphBranchCount
                    }
                    GraphPoolLog("图形分支Worker异常退出", Format("Worker#{1} tab={2} item={3} 剩余计数={4} 忙碌=[{5}] 队列={6}"
                        , wd.idx, tID, iID, remainCount, this.GetBusyWorkerIds(), this.taskQueue.Size()))
                    item.Killed := true
                    if (!this.HasItemWork(tID, iID))
                        this.DrainItemTaskQueue(tID, iID)
                }
            }
        }
        reuseIdx := wd.idx
        skipReset := isGraphTask
        this.CleanUpWorker(wd, !skipReset)
        this.ScheduleRecreateWorker(reuseIdx, 0)
        if (isGraphTask && !this.HasItemWork(tID, iID)) {
            tableItem := GetTableByID(tID)
            if (tableItem) {
                itemIndex := GetItemIndexInTable(tableItem, iID)
                item := tableItem.Items[itemIndex]
                if (!(item && item.GraphBranchCount > 0))
                    this.FinishGraphMacroItem(tID, iID)
            }
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

    ; 残留 Worker 清理：每 10 分钟枚举一次 Work.exe 进程。
    ; 若存在父进程为当前主进程、但已不在线程池（free/use/pending，均登记在 workerMap）追踪中的
    ; 进程，说明其为历史强杀/缩容/重载过程中未真正退出的残留，直接强杀回收资源。
    CheckResidualWorkers() {
        tracked := Map()
        for idx, wd in this.workerMap {
            if (wd.pid)
                tracked[wd.pid] := true
        }

        residual := []
        for p in EnumProcesses() {
            if (StrLower(p.name) != StrLower(this.workerExeName))
                continue
            ; 只清理归属当前主进程的 Worker，避免误杀其他 RMT 实例；父进程未知(0)按本实例处理
            if (p.parentPid && p.parentPid != this.mainPID)
                continue
            if (tracked.Has(p.pid))
                continue
            residual.Push(p)
        }

        if (residual.Length == 0)
            return

        for p in residual {
            GraphPoolLog("清理残留Worker", Format("pid={1} parent={2} 不在线程池追踪中 强杀", p.pid, p.parentPid))
            this.ForceKillProcess(p.pid)
        }
        GraphPoolLog("残留Worker检查", Format("追踪={1} 发现残留={2} 已强杀", tracked.Count, residual.Length))
    }

    ; 按 PID 强杀进程（残留 Worker 清理用），TerminateProcess + ProcessClose 双保险
    ForceKillProcess(pid) {
        hProc := DllCall("OpenProcess", "uint", 0x0001, "int", false, "uint", pid, "ptr")
        if (hProc) {
            DllCall("TerminateProcess", "ptr", hProc, "uint", 1)
            DllCall("CloseHandle", "ptr", hProc)
        }
        if (ProcessExist(pid)) {
            try ProcessClose(pid)
        }
    }

    PollWorkerRx() {
        this.ReclaimDeadUsePoolWorkers()
        for idx, wd in this.workerMap {
            if (!wd.rx || wd.rxBusy)
                continue
            if (!wd.rx.IsEmpty())
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

    ; 环缓冲是否仍归属该 Worker 且可安全访问（强制停止会先切断 rx）
    IsWorkerRxAlive(wd, rb := 0) {
        if (!wd || !wd.rx || !this.workerMap.Has(wd.idx))
            return false
        if (rb != 0 && wd.rx != rb)
            return false
        return true
    }

    ProcessWorkerRx(wd) {
        if (!this.IsWorkerRxAlive(wd) || wd.rxBusy)
            return
        wd.rxBusy := true
        try {
            loop {
                rb := wd.rx
                if (!this.IsWorkerRxAlive(wd, rb))
                    return
                while (this.IsWorkerRxAlive(wd, rb)) {
                    if (!rb.Pop(&type, &id, &result))
                        break
                    if (!this.IsWorkerRxAlive(wd, rb))
                        return
                    switch type {
                        case MsgType.FINISH:
                            if (!this.usePool.Has(wd.idx))
                                continue
                            tID := wd.tableID
                            iID := wd.itemID
                            branchCount := 0
                            if (tID && iID) {
                                tableItem := GetTableByID(tID)
                                if (tableItem) {
                                    itemIndex := GetItemIndexInTable(tableItem, iID)
                                    item := tableItem.Items[itemIndex]
                                    if (item)
                                        branchCount := item.GraphBranchCount
                                }
                            }
                            isGraphTask := (wd.isGraphBranch || branchCount > 0) && tID && iID
                            if (isGraphTask) {
                                tableItem := GetTableByID(tID)
                                item := tableItem ? tableItem.Items[GetItemIndexInTable(tableItem, iID)] : ""
                                remainCount := branchCount
                                if (item && branchCount > 0) {
                                    item.GraphBranchCount--
                                    remainCount := item.GraphBranchCount
                                }
                                GraphPoolLog("Worker完成", Format("Worker#{1} tab={2} item={3} 图形分支 graph={4} 剩余计数={5} 队列={6} 忙碌=[{7}]"
                                    , wd.idx, tID, iID, wd.isGraphBranch ? 1 : 0, remainCount, this.taskQueue.Size(), this.GetBusyWorkerIds()))
                                if (this.usePool.Has(wd.idx))
                                    this.usePool.Delete(wd.idx)
                                this.freePool[wd.idx] := wd
                                wd.tableID := ""
                                wd.itemID := ""
                                wd.isGraphBranch := false
                                wd.graphNodeSerial := ""
                                wd.idleTick := A_TickCount
                                if (remainCount <= 0) {
                                    if (!this.HasItemWork(tID, iID))
                                        this.FinishGraphMacroItem(tID, iID)
                                    else
                                        SetTimer(() => this.TryFinishGraphItem(tID, iID), -200)
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
                            ; OnWorkerEvent 内可能 Sleep（如指令提示），期间强制停止会切断 rx
                            if (!this.IsWorkerRxAlive(wd, rb))
                                return
                    }
                }
                if (!this.IsWorkerRxAlive(wd, rb) || rb.IsEmpty())
                    break
            }
        } finally {
            wd.rxBusy := false
        }
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
                    case "SV":
                        SetGlobalVariable([args[1]], [args[2]], false, wd.idx)
                    case "DV":
                        DelGlobalVariable([args[1]], wd.idx)
                    case "RP":
                        CMDReport(args[1])
                    case "RC":
                        ExcuteRMTCMDAction(args[1])
                    case "IS":
                        tableItem := GetTableByID(args[1])
                        if (tableItem)
                            SetTableItemState(tableItem, GetItemIndexInTable(tableItem, args[2]), args[3])
                    case "PS":
                        tableItem := GetTableByID(args[1])
                        if (tableItem)
                            SetItemPauseState(tableItem, GetItemIndexInTable(tableItem, args[2]), args[3], wd.idx)
                    case "MB":
                        MsgBoxContent(args[1])
                    case "TT":
                        ToolTipContent(args[1])
                    case "IP":
                        ; Worker 请求输入框：创建独立实例弹窗（不同宏/Worker 并发，互不阻塞；共享主进程 daemon）
                        ; 异步创建：避免在消息轮询/OnMessage 上下文同步 XAMLHost（主进程单线程会与 daemon 回传互堵）
                        SetTimer((*) => this._ShowInputDialog(wd, false, args.Length >= 1 ? args[1] : "", args.Length >= 2 ? args[2] : ""), -10)
                    case "IB":
                        ; Worker 请求输入按钮条：创建独立实例，结果回传对应 Worker
                        SetTimer((*) => this._ShowInputDialog(wd, true, args.Length >= 1 ? args[1] : "1"), -10)
                    case "MC":
                        MacroCount(args[1])
                    case "JY":
                        JoyDebugLog(Format("WorkPool recv JY args=[{}, {}, {}] from worker#{}"
                            , args.Length >= 1 ? args[1] : "", args.Length >= 2 ? args[2] : ""
                            , args.Length >= 3 ? args[3] : "", wd.idx), "pool")
                        ViGJoySetState(args[1], args[2], args[3])
                    case "SA":
                        ; 新协议：name + GetArrayStr；旧协议：name + count + items...
                        if (args.Length == 2) {
                            SetGlobalArray(args[1], GetArray(args[2]), wd.idx)
                        } else {
                            arr := []
                            count := Integer(args[2])
                            loop count {
                                arr.Push(args[A_Index + 2])
                            }
                            SetGlobalArray(args[1], arr, wd.idx)
                        }
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
                        if (tableItem)
                            StopMacro(tableItem, GetItemIndexInTable(tableItem, args[2]))
                    case "HK":
                        ; Worker 同步按键按住状态：tableID, itemID, key, state, source
                        SyncWorkerHoldKey(args[1], args[2], args[3], args[4], args.Length >= 5 ? args[5] : "")
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
                        ; Worker 请求主进程触发（TR_MACRO 分支指令）：args = tableID, itemID
                        TriggerMacroHandler(args[1], args[2])
                }
            } catch {
            }
        }
    }

    ; 输入弹窗：每请求独立实例（并发互不阻塞）；Worker 请求结果跨进程回传，主进程宏请求写本地槽位
    _ShowInputDialog(wd, isBtn, args*) {
        this._ShowInputDialogReq({ wd: wd, local: false, done: false }, isBtn, args*)
    }

    ; 主进程宏输入请求：SetTimer 异步弹窗（避免宏执行上下文同步 XAMLHost），结果写回 req.result
    RequestLocalInput(isBtn, args*) {
        req := { wd: { idx: 0 }, local: true, done: false, result: "" }
        SetTimer((*) => this._ShowInputDialogReq(req, isBtn, args*), -10)
        deadline := A_TickCount + 300000
        loop {
            Sleep(100)
            if (req.done)
                break
            if (A_TickCount > deadline) {
                ; 超时：关闭弹窗，返回 ""
                try req.gui._CloseWindow()
                catch
                break
            }
        }
        this._inputGuis.Delete(req)
        return req.result
    }

    _ShowInputDialogReq(req, isBtn, args*) {
        this._inputGuis[req] := true   ; 追踪活动实例
        GraphPoolLog("输入请求处理", Format("wd=#{1} type={2}", req.wd.idx, isBtn ? "btn" : "input"))
        try {
            if (isBtn) {
                ; 输入按钮条
                gui := InputBtnXamlGui()
                req.gui := gui
                gui.TrueAction := (*) => this._SendInputResult(req, "IBR", "true")
                gui.FalseAction := (*) => this._SendInputResult(req, "IBR", "false")
                gui.ContinueAction := (*) => this._SendInputResult(req, "IBR", "continue")
                gui.CancelAction := (*) => this._SendInputResult(req, "IBR", "cancel")
                gui.HideAction := (*) => this._SendInputResult(req, "IBR", "cancel")
                gui.ShowGui(Integer(args[1]))
            } else {
                ; XAML 输入框
                gui := CustomInputGui()
                req.gui := gui
                gui.SureAction := (val) => this._SendInputResult(req, "IPR", "1", val)
                gui.HideAction := (*) => this._SendInputResult(req, "IPR", "0", "")
                gui.CloseAction := (*) => this._SendInputResult(req, "IPR", "0", "")
                gui.ShowGui(args[1], args.Length >= 2 ? args[2] : "")
            }
        } catch as e {
            GraphPoolLog("输入弹窗异常", Format("err={1} wd=#{2}", e.Message, req.wd.idx))
            this._SendInputResult(req, "IPR", "0", "")
        }
    }

    ; 回传输入结果（同一请求只回传一次）
    _SendInputResult(req, opcode, args*) {
        if (req.done)
            return
        req.done := true
        this._inputGuis.Delete(req)
        try req.gui := ""
        catch {
            ; 注意：catch 必须带大括号，否则会吞掉下方回传 try 块
        }
        if (req.local) {
            ; 主进程宏请求：结果直接写入本地槽位
            req.result := args
            argStr := ""
            for a in args
                argStr .= (argStr != "" ? "," : "") a
            GraphPoolLog("输入回传", Format("wd=#{1} op={2} args=[{3}] local=1", req.wd.idx, opcode, argStr))
            return
        }
        try {
            payload := EncodeBatch(EncodeCommand(opcode, args*))
            ok := this.PushTask(req.wd, MsgType.EVENT, 0, payload)
            argStr := ""
            for a in args
                argStr .= (argStr != "" ? "," : "") a
            GraphPoolLog("输入回传", Format("wd=#{1} op={2} args=[{3}] push={4}", req.wd.idx, opcode, argStr, ok))
        } catch as e {
            GraphPoolLog("输入回传失败", Format("err={1} wd=#{2}", e.Message, req.wd.idx))
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
