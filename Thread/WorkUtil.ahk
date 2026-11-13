#Requires AutoHotkey v2.0

;初始化数据
{
    HandleWorkOpenArg() {
        if (A_Args.Length != 8 || A_Args[1] != "--macro-worker")
            ExitApp(1)
        global workIndex := Integer(A_Args[2])
        global parentHwnd := Integer(A_Args[3])
        global shmTx := SharedMemory(1048576 + 192, Integer(A_Args[4]))
        global shmRx := SharedMemory(1048576 + 192, Integer(A_Args[5]))
        global tx := RingBuffer(shmTx.ptr, 1048576)
        global rx := RingBuffer(shmRx.ptr, 1048576)

        ; 变量同步合并缓冲，见 QueueVariSync
        global VariSyncPending := Map()
        global VariSyncScheduled := false

        ; 指令流水攒批缓冲，见 WorkCMDReport
        global CmdReportBuf := ""
        global CmdReportScheduled := false

        ; 悬浮窗最新帧单槽，见 WorkHudOutput：不进事件队列，写入即覆盖
        global shmHud := SharedMemory(65536 + 64, Integer(A_Args[6]))
        global hudSlotPtr := shmHud.ptr
        global hudSlotSeq := NumGet(hudSlotPtr, 4, "UInt")
        global hudPostTick := 0
        global hudFailTick := 0

        ; 悬浮窗直连表：serial → {hwnd, tick, msg, last}，见 WorkHudDirectSlot
        global hudDirect := Map()

        global hEvt := Integer(A_Args[7])
        global workerParentHandle := Integer(A_Args[8])
    }

    InitWorkFilePath() {
        ; 路径表只有一份（AssetUtil.InitDataFilePaths）：Worker 只需要告诉它根目录在哪。
        ; 建目录 / 旧格式迁移 / 展开扁平宏都在主进程启动时做完，Worker 只读配置。
        InitDataFilePaths(A_WorkingDir "\..")
    }

    ; Worker 读配置的唯一序列：冷启动与热重载共用，避免两处顺序走散。
    ; 热重载时先清理文件缓存和已解析的指令对象，再走同一条配置加载路径。
    BootWorkerConfig(isReload := false) {
        if (isReload) {
            TomlUtil_Invalidate()
            CfgInvalidate()
            MySoftData.DataCacheMap.Clear()
        }
        LoadMainSetting()
        InitWorkFilePath()
        if (!isReload)
            HandleWorkOpenArg()
        LoadCurMacroSetting(false)  ; Worker 只加载配置
        InitData()
    }

    ; 日志里的进程标记（同名两套实现里的 Worker 版）。主进程版在 Main\UIUtil.ahk。
    ProcessTag() {
        return workIndex ? "Worker#" workIndex : "Worker"
    }

    ; ---------- 图形宏分支调度：Worker 版 ----------
    ; 主进程版在 Main\RMTUtil.ahk。Worker 没有本地的 WorkPool，分支一律交回主进程分配。
    ShouldUseGraphWorkers() {
        return true
    }

    RunBranchDispatch(tableItem, index, branches, fromStart) {
        item := tableItem.Items[index]
        ; 发生并行分支后由主进程统一收尾，包括从中间节点分叉的情况。
        item.GraphBranchCount := branches.Length
        GraphPoolLog("Worker图形分支", Format("tab={1} item={2} 分支数={3} 本Worker=[{4}] fromStart={5}"
            , tableItem.ID, index, branches.Length, branches[1], fromStart ? 1 : 0))
        subsidiary := []
        loop branches.Length - 1
            subsidiary.Push(branches[A_Index + 1])
        ; 传条目对象（WorkSubmitGraphBranches 取 .ID 作为 ItemID，身份=ID）
        MySubmitGraphBranches(tableItem, item, subsidiary)
    }

    ; 错误统一展示（同名两套实现里的 Worker 版）：只经 ER 通道上报主进程，
    ; 不写本地日志、不弹窗。主进程版在 Main\UIUtil.ahk。
    RMTErrorShow(msg, level := RMT_LV_ERROR, source := "") {
        if (IsSet(MsgSendHandler))
            MsgSendHandler("Error", level "|" workIndex "|" msg)
        return true
    }

    InitWork() {
        global MySoftData, MyHoldKeyNotify
        global graphBranchesAckReceived := false
        global graphBranchesAckKey := ""
        global workerTaskBusy := false
        global workerTask := 0
        ; 角色在 WorkGlobalUtil 建 MySoftData 时就置好了，此处不再改 （IsWorker 依赖它）
        ; 按键按住状态同步到主进程（供强杀后松开）
        MyHoldKeyNotify := (tIdx, iIdx, key, state, source) => MsgSendHandler("HoldKey", tIdx, iIdx, key, state, source)

        OnError(WorkOnError)
        SetTimer(PumpWorkerIpc, 25)
    }

    WorkOnError(e, mode) {
        ; 统一日志（C 项）：Worker 运行时错误 → 仅 ER 通道上报主进程
        ; （主进程统一写系统日志 + 聚合，一次错误一条日志，避免双写）
        fullInfo := GetFullErrorInfo(e)
        try MsgSendHandler("Error", "error|" workIndex "|" fullInfo)
        ; 返回非零值阻止 AHK 默认错误对话框，避免 headless Worker 进程被对话框阻塞
        return 1
    }

    PumpWorkerIpc() {
        if (DllCall("WaitForSingleObject", "ptr", workerParentHandle, "uint", 0, "uint") != 258)
            ExitApp()
        if (rx.Flush())
            MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)
        if (!tx.IsEmpty())
            CheckTxBuffer()
    }

    WaitAndProcessTasks() {
        handles := Buffer(A_PtrSize * 2)
        NumPut("ptr", workerParentHandle, "ptr", hEvt, handles)
        loop {
            PumpWorkerIpc()
            result := DllCall("MsgWaitForMultipleObjects", "uint", 2, "ptr", handles, "int", false
                , "uint", 50, "uint", 0x4FF, "uint")
            if (result == 0 || result == 0xFFFFFFFF)
                ExitApp()
            Sleep(-1)
        }
    }

    WorkPluginInit() {
        ; 根据进程位数自动选择 x86 或 x64，失败时诊断具体原因（如缺少 VC++ 运行库）
        ocvReason := OpenCvEnsure()
        if (ocvReason != "")
            GraphPoolLog("Work插件初始化", Format("OpenCV 插件初始化失败：{}", ocvReason))

        IBPath := ProjectRootDir "\Plugins\IbInputSimulator.dll"
        DllCall('LoadLibrary', 'str', IBPath)

        SetTimer(CheckOcrIdle, 60000)
    }
}

;通信辅助函数
{
    MsgPostHandler(type, wParam, lParam) {
        ; 返回 1 表示成功，0 表示失败。
        ; 投递队列满（每线程上限 1 万条）时 PostMessage 不返回 0，而是抛出 OSError
        ; （1816 = 配额不足）；异常若外传会沿 OnExecTask 中断宏执行。
        ; 消息丢失仅导致延迟一拍，主进程侧的槽与环形缓冲区仍保有最新值。
        try
            return PostMessage(type, wParam, lParam, , "ahk_id " parentHwnd)
        catch
            return 0
    }

    WorkNotifyReady() {
        SendWorkerPacket(MsgType.READY, 0, String(A_ScriptHwnd))
    }

    SendWorkerPacket(type, id, payload := "") {
        if (!rx.Send(type, id, payload))
            return false
        MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)
        return true
    }

    SendWorkerEvent(payload) {
        return SendWorkerPacket(MsgType.EVENT, workerTask ? workerTask.id : 0, payload)
    }

    MsgSendHandler(action, args*) {
        global rx, workIndex, VariSyncPending, CmdReportBuf

        ; 发送任何消息前先冲刷待同步变量。
        ; 变量同步有 16ms 合并窗口，宏写完变量后若立即发送其他消息（输入框、弹窗、
        ; 状态变化、悬浮窗等），主进程读取的镜像仍为旧值。先冲刷以保证
        ; 「变量先到、消息后到」的顺序。FlushVariSync 先清空缓冲再发送，不会递归。
        if (VariSyncPending.Count)
            FlushVariSync()

        ; 指令流水同理：待发送日志须先于其他消息（尤其 FINISH）发出，
        ; 否则宏结束时最后数百毫秒的指令会留在缓冲中。
        ; action 为 "Report" 时跳过，避免 FlushCmdReport 递归。
        if (action != "Report" && CmdReportBuf != "")
            FlushCmdReport()

        static actionMap := Map(
            "StopMacro", "ST",
            "HoldKey", "HK",
            "TR_MACRO", "TR",
            "GraphMacroBranches", "GB",
            "PauseState", "PS",
            "Report", "RP",
            "CmdTipForce", "FR",          ; 输出→指令窗口：强制显示，不经 CMDTip 门控
            "RMT指令", "RC",
            "CountDown", "CD",
            "Prompt", "NT",
            "MsgBox", "MB",
            "ToolTip", "TT",
            "OutputTip", "OT",
            "HudOutput", "HO",        ; 输出→悬浮显示：将渲染后的文本交给主进程建窗或更新
            "Error", "ER",          ; Worker 错误上报主进程（统一日志 C 项）
            "Joy", "JY"
        )

        opcode := actionMap[action]
        realArgs := []

        switch opcode {
            case "GB":
                tIdx := args[1]
                iIdx := args[2]
                nodeSerialArr := args[3]
                realArgs.Push(tIdx, iIdx)
                for ns in nodeSerialArr
                    realArgs.Push(ns)
            default:
                for a in args
                    realArgs.Push(a)
        }

        cmd := EncodeCommand(opcode, realArgs*)
        payload := EncodeBatch(cmd)
        return SendWorkerEvent(payload)
    }

}

;接受主程序指令后回调
{
    OnMasterToWorker(wParam, lParam, msg, hwnd) {
        CheckTxBuffer()
    }

    CheckTxBuffer() {
        global workerTaskBusy, workerTask
        previousCritical := A_IsCritical
        Critical("On")
        try {
            while (tx.Pop(&type, &id, &cmd, &flags)) {
                switch type {
                    case MsgType.TASK:
                        if (workerTaskBusy)
                            throw Error("Unexpected concurrent Worker task")
                        workerTaskBusy := true
                        workerTask := {id: id, paused: flags != 0, stopped: false, item: 0, table: 0, index: 0}
                        SetTimer(OnExecTask.Bind(workerTask, cmd), -1)
                    case MsgType.EVENT:
                        OnEventMessage(cmd)
                    default:
                        throw Error("Unexpected Worker packet")
                }
            }
        } catch {
            ; 主进程用进程句柄检测死亡并回收该任务。
            ExitApp(1)
        } finally Critical(previousCritical)
    }

    OnExecTask(task, cmd) {
        global workerTaskBusy, workerTask, workerConfigDirty
        result := "3"
        try {
            ; 主进程每次分派一个 TR 或 HM。
            if (SubStr(cmd, 1, 3) != "R1" IPC_REC)
                throw Error("Invalid Worker task protocol")
            parts := StrSplit(SubStr(cmd, 4), IPC_SEP)
            if (parts.Length < 3)
                throw Error("Missing Worker task target")
            opcode := parts[1]
            tableID := UnescapeIPC(parts[2])
            itemID := UnescapeIPC(parts[3])
            tableItem := GetTableByID(tableID)
            index := GetItemIndexInTable(tableItem, itemID)
            item := GetItemByIndex(tableItem, index)
            if (!item)
                throw Error("Worker task target unavailable")

            previousCritical := A_IsCritical
            Critical("On")
            try {
                task.item := item
                task.table := tableItem
                task.index := index
                item.Killed := task.stopped
                item.Pause := task.paused
                item.GraphBranchCount := 0
            } finally Critical(previousCritical)

            if (opcode == "TR") {
                RMTLogBusiness("宏:(" item.Remark ")", Format("tab={1} item={2} 开始执行", tableID, itemID))
                if (parts.Length == 4) {
                    item.HoldKey := Map()
                    WaitIfPaused(tableItem, index)
                    if (!item.Killed)
                        RunGraphNodeChain(tableItem, UnescapeIPC(parts[4]), index)
                } else if (!item.Killed) {
                    macro := parts.Length >= 5 ? UnescapeIPC(parts[5]) : item.Macro
                    RunMacroTrigger(tableItem, macro, index, true)
                }
                RMTLogBusiness("宏:(" item.Remark ")", Format("tab={1} item={2} 结束", tableID, itemID))
            } else if (opcode == "HM") {
                phase := parts.Length >= 4 ? UnescapeIPC(parts[4]) : "post"
                force := parts.Length >= 5 && UnescapeIPC(parts[5]) == "1"
                RunMacroHook(tableItem, item, phase, force)
            } else {
                throw Error("Unknown Worker task opcode")
            }
            result := (task.stopped || item.Killed) ? "3" : "0"
        } catch {
            GraphPoolLog("Worker任务失败", Format("id={1}", task.id))
        } finally {
            previousCritical := A_IsCritical
            Critical("On")
            try {
                if (workerConfigDirty) {
                    workerConfigDirty := false
                    ReloadWorkerConfig()
                }
                workerTask := 0
                workerTaskBusy := false
                SendWorkerPacket(MsgType.FINISH, task.id, result)
            } finally Critical(previousCritical)
        }
    }

    OnEventMessage(cmd) {
        global workerTaskBusy, workerConfigDirty
        if (SubStr(cmd, 1, 2) != "R1")
            return

        commandsStr := SubStr(cmd, 3)
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
                    case "CDR":
                        CountDownComplete(args[1])
                    case "IPR", "IBR":
                        WorkerInputReply(opcode, args*)
                    case "VR":
                        WorkerDataReply(args*)
                    case "SN":
                        snapshot := JSON.parse(args[1])
                        for pair in snapshot[1]
                            MySoftData.VariableMap[pair[1]] := pair[2]
                        for pair in snapshot[2]
                            MySoftData.ArrayMap[pair[1]] := pair[2]
                    case "SV", "SA":
                        target := opcode == "SV" ? MySoftData.VariableMap : MySoftData.ArrayMap
                        target[args[1]] := JSON.parse(args[2])[1]
                    case "DV", "DA":
                        target := opcode == "DV" ? MySoftData.VariableMap : MySoftData.ArrayMap
                        if (target.Has(args[1]))
                            target.Delete(args[1])
                    case "CT":
                        MySoftData.CMDTip := (args[1] == "1")
                    case "PS":
                        if (workerTask && workerTask.id == Integer(args[1])) {
                            workerTask.paused := args[2] == "1"
                            if (workerTask.item)
                                workerTask.item.Pause := workerTask.paused
                        }
                    case "ST":
                        if (workerTask && workerTask.id == Integer(args[1])) {
                            workerTask.stopped := true
                            if (workerTask.item)
                                KillTableItemMacro(workerTask.table, workerTask.index)
                        }
                    case "QT":
                        ExitApp()
                    case "CF":
                        ; §17 热重载：主进程保存选「否」后广播 → 重载宏配置（新增宏/宏内容即时生效）
                        ; 忙（正在执行宏）→ 置位，任务结束后再重载；空闲 → 立即重载
                        if (workerTaskBusy) {
                            workerConfigDirty := true
                            GraphPoolLog("Worker配置热重载延后", "当前任务执行中")
                        } else {
                            workerConfigDirty := false
                            ReloadWorkerConfig()
                        }
                    case "GA":
                        global graphBranchesAckKey, graphBranchesAckReceived
                        key := args[1] "_" args[2]
                        if (IsSet(graphBranchesAckKey) && graphBranchesAckKey == key)
                            graphBranchesAckReceived := true
                }
            } catch {
                ; 数据帧无法应用时退出，让主进程重建并重新同步完整快照。
                if (opcode == "SN" || opcode == "SV" || opcode == "SA" || opcode == "DV" || opcode == "DA")
                    ExitApp(1)
            }
        }
    }
}

; §17 热重载：重新加载宏配置（主进程保存选「否」后广播 CF 触发）
; 注意：LoadCurMacroSetting 会整表重建 TableInfo（新对象），运行中宏引用旧对象会破坏执行上下文，
; 因此只允许空闲时调用——CF 事件（空闲分支）与 OnExecTask finally（忙时延后）双保险。
ReloadWorkerConfig() {
    ; 重建宏表索引期间，不让任务定时器读取未加载完的条目。
    previousCritical := A_IsCritical
    Critical("On")
    try {
        ; 与冷启动走同一条序列（BootWorkerConfig），差别只有两处：
        ; 不重复解析命令行/共享内存，以及必须先失效 TomlUtil 缓存——Worker 侧缓存是
        ; 启动快照，主进程保存不会失效它，不失效就会读到旧内容。
        BootWorkerConfig(true)
        GraphPoolLog("Worker配置热重载", "完成")
    } catch as e {
        GraphPoolLog("Worker配置热重载失败", Format("err={1} line={2} what={3}`nstack={4}"
            , e.Message, e.Line, e.What, e.Stack))
    } finally Critical(previousCritical)
}

; Worker 的写入由主进程排序和提交。收到权威值后才继续下一条宏指令。
WorkCommitGlobalData(opcode, args*) {
    global workerDataRequest
    static sequence := 0
    request := {id: ++sequence, result: ""}
    workerDataRequest := request
    try {
        deadline := DllCall("GetTickCount64", "uint64") + 10000
        payload := EncodeBatch(EncodeCommand("GS", request.id, deadline, JSON.stringify([opcode, args])))
        if (!SendWorkerEvent(payload))
            throw Error("Worker data channel closed")
        while (request.result == "") {
            Sleep(10)
            if (workerTask && workerTask.stopped)
                return
            if (DllCall("GetTickCount64", "uint64") >= deadline)
                throw Error("Worker data commit timed out")
        }
        if (request.result != "1")
            throw Error("Worker data commit failed")
    } finally workerDataRequest := 0
}

WorkerDataReply(id, result) {
    if (IsSet(workerDataRequest) && workerDataRequest && workerDataRequest.id == Integer(id))
        workerDataRequest.result := result
}

WorkSetGlobalArray(name, value) => WorkCommitGlobalData("SA", name, value)
WorkCloneGlobalArray(source, name) => WorkSetGlobalArray(name, source)
WorkDeleteGlobalArray(name) => WorkCommitGlobalData("DA", name)
WorkModifyGlobalArray(name, row, index, isArrayValue, value) => WorkCommitGlobalData("MA", name, row, index, value)
WorkInsertGlobalArray(name, row, index, isArrayValue, value) => WorkCommitGlobalData("IA", name, row, index, value)
WorkRemoveAtGlobalArray(name, row, index) => WorkCommitGlobalData("RA", name, row, index)
WorkSetGlobalVariable(names, values, ignoreExist) => WorkCommitGlobalData("SV", names, values, ignoreExist)
WorkDelGlobalVariable(names) => WorkCommitGlobalData("DV", names)

; 宏指令相关函数
{
    ; 表身份 = TableItem 对象（主/Worker 内存同一结构）；Worker 协议回传用 ID。
    ; itemIndex 可能是：数字下标 / MacroItem 对象 / ItemID 字符串 → 统一解析为 ItemID
    WorkResolveItemID(tableItem, itemIndex) {
        if (IsObject(itemIndex))
            return itemIndex.ID
        if (IsObject(tableItem) && IsNumber(itemIndex) && itemIndex >= 1 && itemIndex <= tableItem.Items.Length)
            return tableItem.Items[itemIndex].ID
        return String(itemIndex)
    }

    WorkStopMacro(tableItem, itemIndex, playStopTip := false) {
        if (!IsObject(tableItem))
            tableItem := GetTableByID(String(tableItem))
        if (IsObject(tableItem) && !IsNumber(itemIndex))
            itemIndex := GetItemIndexInTable(tableItem, String(itemIndex))
        item := GetItemByIndex(tableItem, itemIndex)
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        if (playStopTip && IsObject(item) && item.StopTipSound == 2)
            PlayTipSound(3)
        if (workerTask && workerTask.item && workerTask.table.ID == tID && workerTask.item.ID == iID) {
            workerTask.stopped := true
            KillTableItemMacro(workerTask.table, workerTask.index)
        }
        MsgSendHandler("StopMacro", tID, iID)
    }

    WorkTriggerSubMacro(tableItem, itemIndex) {
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        MsgSendHandler("TR_MACRO", tID, iID)
    }

    WorkSubmitGraphBranches(tableItem, itemIndex, nodeSerialArr) {
        global graphBranchesAckKey, graphBranchesAckReceived
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        nodes := ""
        for s in nodeSerialArr
            nodes .= (nodes != "" ? "," : "") s
        GraphPoolLog("Worker批量请求分支", Format("tab={1} item={2} 子分支=[{3}]", tID, iID, nodes))
        graphBranchesAckKey := tID "_" iID
        graphBranchesAckReceived := false

        try {
            MsgSendHandler("GraphMacroBranches", tID, iID, nodeSerialArr)
            start := A_TickCount
            loop {
                if (graphBranchesAckReceived) {
                    GraphPoolLog("Worker分支分配就绪", Format("tab={1} item={2}", tID, iID))
                    return
                }
                if (workerTask && workerTask.stopped)
                    return
                if (A_TickCount - start >= 3000) {
                    throw Error("Worker graph dispatch timed out")
                }
                Sleep(10)
            }
        } finally {
            graphBranchesAckKey := ""
            graphBranchesAckReceived := false
        }
    }

    WorkSetItemPauseState(tableItem, itemIndex, state) {
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        if (IsObject(tableItem) && IsNumber(itemIndex)) {
            item := GetItemByIndex(tableItem, itemIndex)
            if (item)
                item.Pause := state
        } else {
            tableItemObj := GetTableByID(tID)
            if (tableItemObj) {
                itemIndexNum := GetItemIndexInTable(tableItemObj, iID)
                if (itemIndexNum >= 1)
                    tableItemObj.Items[itemIndexNum].Pause := state
            }
        }
        MsgSendHandler("PauseState", tID, iID, state)
    }
}

;子程序告诉主程动作
{
    ; 指令流水攒批：Worker 侧累积 100ms（或满 4KB）后发送一条 Report。
    ;
    ; 逐条发送时，主进程每收一条都要执行一次 ShowGui（窗口检查、字符串拼接、
    ; Update），开销与指令条数成正比，多宏并发时主线程饱和。
    ; 攒批后跨进程消息数仅与时间相关（约 10 条/秒），与指令条数无关。
    WorkCMDReport(cmdStr) {
        global CmdReportBuf, CmdReportScheduled
        CmdReportBuf .= (CmdReportBuf == "" ? "" : "`n") cmdStr
        ; 单批上限：RingBuffer 可容纳更大消息，但消息越大主进程解析越慢，4KB 已足够
        if (StrLen(CmdReportBuf) >= 4000) {
            FlushCmdReport()
            return
        }
        if (!CmdReportScheduled) {
            CmdReportScheduled := true
            SetTimer(FlushCmdReport, -100)
        }
    }

    FlushCmdReport() {
        global CmdReportBuf, CmdReportScheduled
        CmdReportScheduled := false
        if (CmdReportBuf == "")
            return
        buf := CmdReportBuf
        CmdReportBuf := ""
        ; 多行文本一次发送，主进程 AddCMD 按批处理
        MsgSendHandler("Report", buf)
    }

    ; 「输出→指令窗口」专用：不经 CMDTip 门控，始终转发给主进程显示（区别于 Report 溯源）
    WorkCmdTipForceShow(cmdStr) {
        MsgSendHandler("CmdTipForce", cmdStr)
    }

    WorkExcuteRMTCMDAction(cmdStr) {
        MsgSendHandler("RMT指令", cmdStr)
    }

    WorkMsgBoxContent(content) {
        MsgSendHandler("MsgBox", content)
    }

    WorkToolTipContent(content) {
        MsgSendHandler("ToolTip", content)
    }

    WorkOutputTipContent(content) {
        MsgSendHandler("OutputTip", content)
    }

    ; 悬浮显示：仅保留最新一帧，走单槽共享内存，不进事件队列。
    ;
    ; 逐帧发送 HO 消息存在两个问题：
    ;   1. 占满 Worker→主进程环形缓冲区，_Push 返回 false，消息丢失；
    ;   2. 占满主线程投递队列（上限 1 万条），其它 Worker 的通知无法入队。
    ;
    ; 现将内容覆盖写入固定槽，主进程按自身节奏读取；通知以 pending 标志保证
    ; 至多一条未处理，写入频率再高也不积压。
    WorkHudOutput(serialStr, content, tID, iID) {
        global hudSlotPtr, hudSlotSeq, hudPostTick, hudFailTick, workIndex, hudDirect

        ; 直连：主进程建窗后把引擎窗口句柄登记到槽尾表，此处每帧查表一次。
        ; 命中则直接向引擎投递文本，该帧不经过主进程。
        d := WorkHudDirectSlot(serialStr)
        if (IsObject(d) && WorkHudDirectWrite(d, content))
            return

        if (!hudSlotPtr)
            return

        ; 槽格式：serial \x01 tID \x01 iID \x01 content
        payload := serialStr Chr(1) tID Chr(1) iID Chr(1) content
        size := StrPut(payload, "UTF-8")
        if (size <= 1 || size > 65000)
            return
        buf := Buffer(size)
        StrPut(payload, buf, "UTF-8")

        ; 先写内容，再写长度与序号：主进程读到的必为完整帧
        DllCall("RtlMoveMemory", "Ptr", hudSlotPtr + 16, "Ptr", buf.Ptr, "Ptr", size)
        NumPut("UInt", size - 1, hudSlotPtr, 8)
        hudSlotSeq += 1
        NumPut("UInt", hudSlotSeq, hudSlotPtr, 4)

        ; 上一帧未被取走时不再通知：天然合并，最多保留一条未处理通知。
        ;
        ; 投递失败（队列满）时撤回 pending 以便下次重试，并退避 300ms，
        ; 避免紧循环中每帧重复失败。数据已写入槽，主进程读取时仍为最新值，
        ; 丢失的仅是唤醒动作。
        now := A_TickCount
        if (NumGet(hudSlotPtr, 0, "UInt") == 0) {
            if (now - hudFailTick >= 300) {
                NumPut("UInt", 1, hudSlotPtr, 0)
                if (MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)) {
                    hudPostTick := now
                } else {
                    NumPut("UInt", 0, hudSlotPtr, 0)
                    hudFailTick := now
                }
            }
        } else if (now - hudPostTick > 1000) {
            ; pending 超过 1 秒未被取走：主进程可能忙于长任务，补发一次通知
            if (MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)) {
                hudPostTick := now
            } else {
                NumPut("UInt", 0, hudSlotPtr, 0)
                hudFailTick := now
            }
        }
    }

    ; ---------------------------------------------------------------
    ; 悬浮窗直连
    ;
    ; 主进程建窗后把引擎窗口句柄登记到 RMT_HUD 槽尾的句柄表：
    ;   +65024 UInt32 项数；+65032 起每项 16 字节（serial / pad / hwnd）。
    ; 文本区只占 +16..+65015，两者互不重叠。
    ;
    ; Worker 每帧查一次表：命中则直接向引擎投递，该帧不经过主进程；
    ; 未命中（窗口未就绪或已关闭）走主进程路径。
    ;
    ; 不以消息传句柄：宏处于紧循环时不处理消息队列（仅在 Sleep/Wait 时泵消息），
    ; 这类通知收不到；槽内数据任意时刻读取都是最新值。
    ; ---------------------------------------------------------------
    WorkHudDirectSlot(serialStr) {
        global hudDirect, hudSlotPtr
        d := hudDirect.Has(serialStr) ? hudDirect[serialStr] : ""
        if (IsObject(d)) {
            if (d.hwnd)
                return d
            if (A_TickCount < d.retryAt)
                return ""          ; 表内暂无此项，退避期间不重复扫描
        }
        hwnd := hudSlotPtr ? WorkHudFindHwnd(serialStr) : 0
        if (!hwnd) {
            hudDirect[serialStr] := { hwnd: 0, retryAt: A_TickCount + 50, tick: 0, last: "" }
            return ""
        }
        hudDirect[serialStr] := { hwnd: hwnd, retryAt: 0, tick: 0, last: "" }
        return hudDirect[serialStr]
    }

    ; 在槽尾句柄表中查找 serial 对应的引擎窗口句柄，未登记返回 0
    WorkHudFindHwnd(serialStr) {
        global hudSlotPtr
        try key := Integer(serialStr)
        catch
            return 0
        count := NumGet(hudSlotPtr, 65024, "UInt")
        if (count > 35)
            return 0
        loop count {
            off := 65032 + (A_Index - 1) * 16
            if (NumGet(hudSlotPtr, off, "UInt") == key)
                return NumGet(hudSlotPtr, off + 8, "Ptr")
        }
        return 0
    }

    ; 直连投递一帧。返回 true 表示该帧已处理（含被限速或超时丢弃），
    ; false 表示该路径不可用，调用方改走主进程路径。
    WorkHudDirectWrite(d, content) {
        ; 限速约 100Hz：宏每秒可产生上千帧，中间帧无需显示
        now := A_TickCount
        if (d.retryAt && now < d.retryAt)
            return true
        if (d.tick && now - d.tick < 10)
            return true
        ; 内容未变化时跳过：静态内容无需周期性投递
        if (d.last == content)
            return true
        n := StrPut(content, "UTF-8") - 1
        if (n <= 0 || n > 60000)
            return true            ; 空内容或超长：丢弃，无需回退
        ; 窗口可能已被销毁，句柄失效即回退主进程路径并重新查表
        if (!DllCall("IsWindow", "Ptr", d.hwnd)) {
            d.hwnd := 0
            d.retryAt := now + 50
            return false
        }
        ; 引擎 0x004A 分支按「op|arg|value」解析且以换行分隔多条指令，须转义
        body := StrReplace(StrReplace(content, "`r", "&#x0D;"), "`n", "&#x0A;")
        payload := "HUD|Text|" body
        size := StrPut(payload, "UTF-8")
        ; 常驻发送缓冲：超时返回后接收方仍可能读取，不能指向已失效的临时内存
        static sndBuf := 0
        if (!IsObject(sndBuf) || sndBuf.Size < size)
            sndBuf := Buffer(Max(size, 65536))
        StrPut(payload, sndBuf, "UTF-8")
        cds := Buffer(A_PtrSize * 3, 0)
        NumPut("Ptr", size, cds, 0)
        NumPut("Ptr", sndBuf.Ptr, cds, A_PtrSize)
        d.tick := now
        ; SMTO_ABORTIFHUNG：引擎无响应时立即返回，避免 Worker 被挂住
        res := 0
        if (!DllCall("SendMessageTimeoutW", "Ptr", d.hwnd, "UInt", 0x004A, "Ptr", 0
            , "Ptr", cds, "UInt", 0x0002, "UInt", 200, "Ptr*", &res)) {
            d.retryAt := now + 200
            return true
        }
        d.last := content
        return true
    }

    WorkViGJoySetState(JoyType, Key, Value) {
        JoyDebugLog(Format("WorkViGJoySetState -> master JY type={} key={} value={}", JoyType, Key, Value), "worker")
        MsgSendHandler("Joy", JoyType, Key, Value)
    }
}

;通用函数
{
    GetFullErrorInfo(exception) {
        what := ""
        msg := ""
        extra := ""
        stack := ""
        fullMsg := ""

        if (IsObject(exception)) {
            try what := exception.What
            try msg := exception.Message
            try extra := exception.Extra
            try stack := exception.Stack
        } else {
            msg := "" . exception
        }

        if (what != "")
            fullMsg := what
        if (msg != "")
            fullMsg := fullMsg (fullMsg ? " | " : "") . msg
        if (extra != "")
            fullMsg := fullMsg "`nSpecifically: " extra
        if (stack != "")
            fullMsg := fullMsg "`n" stack

        return fullMsg
    }


}
