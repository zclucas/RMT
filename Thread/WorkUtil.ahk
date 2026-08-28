#Requires AutoHotkey v2.0

;初始化数据
{
    HandleWorkOpenArg() {
        global workIndex := A_Args[1]
        global parentHwnd := A_Args[2]
        global parentPID := A_Args[3]
        global txName := "RMT_TX_" workIndex
        global rxName := "RMT_RX_" workIndex
        global evtName := "RMT_EVT_" workIndex

        global shmTx := SharedMemory(txName, 1048576 + 192)
        global shmRx := SharedMemory(rxName, 1048576 + 192)
        global tx := RingBuffer(shmTx.ptr, 1048576)
        global rx := RingBuffer(shmRx.ptr, 1048576)

        global hEvt := 0
        if (evtName) {
            global hEvt := DllCall("OpenEventW", "uint", 0x00100002, "int", false, "ptr", StrPtr(evtName), "ptr")
        }
    }

    InitWorkFilePath() {
        global VBSPath := A_WorkingDir "\..\MinTool\PlayAudio.vbs"
        global StartTipAudio := A_WorkingDir "\..\Audio\Start.wav"
        global EndTipAudio := A_WorkingDir "\..\Audio\End.wav"
        global ViGEmDllPath := A_WorkingDir "\..\Plugins\ViGEm\ViGEmWrapper.dll"
        global AHIDllDir := A_WorkingDir "\..\Plugins\AhiDriver"
        global AHIPluginDir := A_WorkingDir "\..\Plugins\AhiDriver\installer"
        global ArrayFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\ArrayFile.ini"
        global TimingFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\TimingFile.ini"
        global MacroFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\MacroFile.ini"
        global SearchFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\SearchFile.ini"
        global SearchProFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\SearchProFile.ini"
        global ScreenShotFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\ScreenShotFile.ini"
        global CompareFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\CompareFile.ini"
        global CompareProFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\CompareProFile.ini"
        global MMProFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\MMProFile.ini"
        global BGKeyFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\BGKeyFile.ini"
        global RunFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\RunFile.ini"
        global OutputFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\OutputFile.ini"
        global VariableFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\VariableFile.ini"
        global ExVariableFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\ExVariableFile.ini"
        global TextOpsFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\TextOpsFile.ini"
        global SubMacroFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\SubMacroFile.ini"
        global LoopFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\LoopFile.ini"
        global OperationFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\OperationFile.ini"
        global BGMouseFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\BGMouseFile.ini"
        global InputFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\InputFile.ini"
        global FileIOFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\FileIOFile.ini"
        global WindowManageFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\WindowManageFile.ini"
        global KeyCheckFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\KeyCheckFile.ini"
        global CommentFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\CommentFile.ini"
        global GraphNodeFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\GraphNodeFile.ini"
        global GraphStartNodeFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\GraphStartNodeFile.ini"
        ; 阶段5：纯文本指令迁移到配置文件模式（间隔/按键/移动/RMT指令）
        global IntervalFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\IntervalFile.ini"
        global KeyDataFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\KeyDataFile.ini"
        global MoveDataFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\MoveDataFile.ini"
        global RMTCMDFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\RMTCMDFile.ini"
        global IniSection := "UserSettings"

    ;项目根目录（Worker进程A_WorkingDir指向Thread子目录，需回退到项目根）
    global ProjectRootDir := A_WorkingDir '\..\'
    loop files, ProjectRootDir {
        ProjectRootDir := A_LoopFileFullPath
        break
    }

    ;利用机制把路径中的\..转换掉
        loop files, StartTipAudio {
            StartTipAudio := A_LoopFileFullPath
            break
        }
        loop files, EndTipAudio {
            EndTipAudio := A_LoopFileFullPath
            break
        }
    }

    InitWork() {
        global MySoftData, MyHoldKeyNotify
        global graphBranchesWaiting := false
        global graphBranchesAckReceived := false
        global graphBranchesAckKey := ""
        global workerTaskBusy := false
        global workerPendingTasks := []
        MySoftData.isWorker := true
        ; 按键按住状态同步到主进程（供强杀后松开）
        MyHoldKeyNotify := (tIdx, iIdx, key, state, source) => MsgSendHandler("HoldKey", tIdx, iIdx, key, state, source)

        OnError(WorkOnError)
        SetTimer(CheckParentProcess, 10000)
    }

    WorkOnError(e, mode) {
        ; 统一日志（C 项）：Worker 运行时错误 → 仅 ER 通道上报主进程
        ; （主进程统一写系统日志 + 聚合，一次错误一条日志，避免双写）
        fullInfo := GetFullErrorInfo(e)
        try MsgSendHandler("Error", "error|" workIndex "|" fullInfo)
        ; 返回非零值阻止 AHK 默认错误对话框，避免 headless Worker 进程被对话框阻塞
        return 1
    }

    CheckParentProcess() {
        if !ProcessExist(parentPID) {
            GraphPoolLog("Worker父进程检测", Format("parentPID={1} 不存在, 即将退出", parentPID))
            ExitApp()
        }
    }

    WaitAndProcessTasks() {
        global hEvt, workerTaskBusy, tx
        if (!hEvt)
            return

        hArr := Buffer(A_PtrSize)
        NumPut("ptr", hEvt, hArr)

        while (true) {
            if (!workerTaskBusy && !tx.IsEmpty()) {
                CheckTxBuffer()
                continue
            }

            r := DllCall("MsgWaitForMultipleObjects", "uint", 1, "ptr", hArr.Ptr, "int", false, "uint", -1, "uint", 0x4FF, "uint")
            if (r == 0) {
                CheckTxBuffer()
            } else if (r == 1) {
                Sleep(-1)
            }
        }
    }

    WorkPluginInit() {
        ; 根据进程位数自动选择 x86 或 x64，失败时诊断具体原因（如缺少 VC++ 运行库）
        ocvReason := OpenCvEnsure()
        if (ocvReason != "")
            GraphPoolLog("Work插件初始化", Format("OpenCV 插件初始化失败：{}", ocvReason))

        IBPath := A_ScriptDir "\..\Plugins\IbInputSimulator.dll"
        DllCall('LoadLibrary', 'str', IBPath)

        SetTimer(CheckOcrIdle, 60000)
    }
}

;通信辅助函数
{
    MsgPostHandler(type, wParam, lParam) {
        PostMessage(type, wParam, lParam, , "ahk_id " parentHwnd)
    }

    WorkNotifyReady() {
        global workIndex
        MsgPostHandler(WM_LOAD_WORK, workIndex, A_ScriptHwnd)
    }

    MsgSendHandler(action, args*) {
        global rx, workIndex

        static actionMap := Map(
            "SetArray", "SA",
            "CloneArray", "CA",
            "DeleteArray", "DA",
            "ModifyArray", "MA",
            "InsertArray", "IA",
            "RemoveAtArray", "RA",
            "SetVari", "SV",
            "DelVari", "DV",
            "StopMacro", "ST",
            "HoldKey", "HK",
            "TR_MACRO", "TR",
            "GraphMacroBranches", "GB",
            "ItemState", "IS",
            "PauseState", "PS",
            "Report", "RP",
            "CmdTipForce", "FR",          ; 输出→指令窗口：强制显示，不经 CMDTip 门控
            "RMT指令", "RC",
            "MsgBox", "MB",
            "ToolTip", "TT",
            "MacroCount", "MC",
            "Error", "ER",          ; Worker 错误上报主进程（统一日志 C 项）
            "Joy", "JY"
        )

        opcode := actionMap[action]
        realArgs := []

        switch opcode {
            case "SV":
                commands := []
                nameArr := args[1]
                valueArr := args[2]
                loop nameArr.Length {
                    commands.Push(EncodeCommand("SV", nameArr[A_Index], valueArr[A_Index]))
                }
                payload := EncodeBatch(commands*)
                rx.Push(MsgType.EVENT, 0, payload)
                MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)
                return
            case "DV":
                commands := []
                nameArr := args[1]
                loop nameArr.Length {
                    commands.Push(EncodeCommand("DV", nameArr[A_Index]))
                }
                payload := EncodeBatch(commands*)
                rx.Push(MsgType.EVENT, 0, payload)
                MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)
                return
            case "SA":
                ; args[2] 已是 GetArrayStr，整串转发以保留二维结构
                realArgs.Push(args[1], args[2])
            case "CA":
                realArgs.Push(args[1], args[2])
            case "MA", "IA":
                path := args[2] "." args[3]
                realArgs.Push(args[1], path, args[5])
            case "RA":
                path := args[2] "." args[3]
                realArgs.Push(args[1], path)
            case "GB":
                tIdx := args[1]
                iIdx := args[2]
                branchCount := args[3]
                nodeSerialArr := args[4]
                realArgs.Push(tIdx, iIdx, branchCount)
                for ns in nodeSerialArr
                    realArgs.Push(ns)
            default:
                for a in args
                    realArgs.Push(a)
        }

        cmd := EncodeCommand(opcode, realArgs*)
        payload := EncodeBatch(cmd)
        rx.Push(MsgType.EVENT, 0, payload)
        MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)
    }

}

;接受主程序指令后回调
{
    OnExit(wParam, lParam, msg, hwnd) {
        ExitApp()
    }

    OnMasterToWorker(wParam, lParam, msg, hwnd) {
        CheckTxBuffer()
    }

    ScheduleWorkerTask(id, cmd) {
        SetTimer(OnExecTask.Bind(id, cmd), -1)
    }

    CheckTxBuffer() {
        global tx, workIndex, graphBranchesWaiting, workerTaskBusy, workerPendingTasks
        if (graphBranchesWaiting)
            return
        loop {
            while (tx.Pop(&type, &id, &cmd)) {
                switch type {
                    case MsgType.TASK:
                        if (workerTaskBusy) {
                            workerPendingTasks.Push({ id: id, cmd: cmd })
                            GraphPoolLog("Worker任务延后", Format("id={1} 原因=上一任务未完成 pending={2}", id, workerPendingTasks.Length))
                        } else {
                            ScheduleWorkerTask(id, cmd)
                        }
                    case MsgType.EVENT:
                        OnEventMessage(cmd)
                }
            }
            if (tx.IsEmpty())
                break
        }
    }

    OnExecTask(id, cmd) {
        global rx, workIndex, workerTaskBusy, workerPendingTasks
        ; 业务日志（C 项阶段3）：缓存当前任务标识供开始/结束埋点使用
        static _bizCurTab := 0, _bizCurItem := 0, _bizCurRemark := ""
        workerTaskBusy := true
        try {
            if (SubStr(cmd, 1, 2) != "R1") {
                GraphPoolLog("Worker任务解析失败", Format("id={1} err=Protocol header missing cmd={2}", id, SubStr(cmd, 1, 120)))
                return
            }
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

                if (opcode == "TR") {
                    tIdx := args[1]          ; TableID 字符串
                    iIdx := args[2]          ; ItemID 字符串
                    _bizCurTab := tIdx
                    _bizCurItem := iIdx
                    tableItem := GetTableByID(tIdx)
                    if (!tableItem) {
                        GraphPoolLog("Worker任务-表不存在", Format("tab={1} item={2}", tIdx, iIdx))
                        continue
                    }
                    itemIndex := GetItemIndexInTable(tableItem, iIdx)
                    item := tableItem.Items[itemIndex]
                    _bizCurRemark := item ? item.Remark : ""
                    RMTLogBusiness("宏:(" _bizCurRemark ")", Format("tab={1} item={2} 开始执行", tIdx, iIdx))
                    if (args.Length >= 3) {
                        nodeSerial := args[3]
                        GraphPoolLog("Worker开始执行", Format("tab={1} item={2} node={3}", tIdx, iIdx, nodeSerial))
                        WalkGraphNode(tableItem, nodeSerial, itemIndex)
                    } else {
                        TriggerMacro(tableItem, itemIndex)
                    }
                }
            }
        } catch as e {
            GraphPoolLog("Worker任务异常", Format("id={1} err={2} line={3} cmd={4}"
                , id, e.Message, e.Line, SubStr(cmd, 1, 120)))
        } finally {
            ; 业务日志（C 项阶段3）：宏结束（正常/异常统一记录）
            RMTLogBusiness("宏:(" _bizCurRemark ")", Format("tab{1} item{2} 结束", _bizCurTab, _bizCurItem))
            rx.Push(MsgType.FINISH, id)
            MsgPostHandler(WM_WORKER_TO_MASTER, workIndex, 0)
            if (workerPendingTasks.Length > 0) {
                t := workerPendingTasks.RemoveAt(1)
                ScheduleWorkerTask(t.id, t.cmd)
            } else {
                workerTaskBusy := false
            }
        }
    }

    OnEventMessage(cmd) {
        global _workerInputResult
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
                    case "IPR":
                        ; 主进程回传输入框结果：[ok, value]
                        ; 只写首次（主进程可能因 SureAction+HideAction 回传多条，CheckTxBuffer 一次消费，防止覆盖首次结果）
                        if (!IsObject(_workerInputResult))
                            _workerInputResult := [args[1], args.Length >= 2 ? args[2] : ""]
                    case "IBR":
                        ; 主进程回传按钮条结果：[button]（true/false/continue/cancel）
                        if (!IsObject(_workerInputResult))
                            _workerInputResult := [args[1]]
                    case "SV":
                        MySoftData.VariableMap[args[1]] := args[2]
                    case "DV":
                        if (MySoftData.VariableMap.Has(args[1]))
                            MySoftData.VariableMap.Delete(args[1])
                    case "CT":
                        MySoftData.CMDTip := (args[1] == "1")
                    case "PS":
                        tableItem := GetTableByID(args[1])
                        if (tableItem) {
                            itemIndex := GetItemIndexInTable(tableItem, args[2])
                            if (itemIndex >= 1)
                                tableItem.Items[itemIndex].Pause := args[3]
                        }
                    case "SA":
                        ; 新协议：name + GetArrayStr；旧协议：name + count + items...
                        if (args.Length == 2) {
                            MySoftData.ArrayMap[args[1]] := GetArray(args[2])
                        } else {
                            name := args[1]
                            count := Integer(args[2])
                            arr := []
                            loop count {
                                arr.Push(args[A_Index + 2])
                            }
                            MySoftData.ArrayMap[name] := arr
                        }
                    case "CA":
                        sourceName := args[1]
                        newArrName := args[2]
                        MySoftData.ArrayMap[newArrName] := MySoftData.ArrayMap[sourceName].Clone()
                    case "DA":
                        if (MySoftData.ArrayMap.Has(args[1]))
                            MySoftData.ArrayMap.Delete(args[1])
                    case "MA":
                        rootArr := MySoftData.ArrayMap[args[1]]
                        currArr := GetArrayRefByPath(rootArr, args[2], &lastIdx)
                        currArr[lastIdx] := args[3]
                    case "IA":
                        rootArr := MySoftData.ArrayMap[args[1]]
                        currArr := GetArrayRefByPath(rootArr, args[2], &lastIdx)
                        currArr.InsertAt(lastIdx, args[3])
                    case "RA":
                        rootArr := MySoftData.ArrayMap[args[1]]
                        currArr := GetArrayRefByPath(rootArr, args[2], &lastIdx)
                        currArr.RemoveAt(lastIdx)
                    case "ST":
                        tableItem := GetTableByID(args[1])
                        if (tableItem) {
                            itemIndex := GetItemIndexInTable(tableItem, args[2])
                            KillTableItemMacro(tableItem, itemIndex)
                        }
                        GraphPoolLog("Worker收到终止指令", Format("tab={1} item={2}", args[1], args[2]))
                    case "GA":
                        global graphBranchesAckKey, graphBranchesAckReceived
                        key := args[1] "_" args[2]
                        if (IsSet(graphBranchesAckKey) && graphBranchesAckKey == key)
                            graphBranchesAckReceived := true
                }
            } catch {
            }
        }
    }
}

;变量数据相关函数
{
    WorkSetGlobalArray(Name, Value) {
        MySoftData.ArrayMap[Name] := Value
        MsgSendHandler("SetArray", Name, GetArrayStr(Value))
    }

    WorkCloneGlobalArray(SourceArr, NewArrName) {
        MySoftData.ArrayMap[NewArrName] := SourceArr.Clone()
        sourceName := ""
        for name, arr in MySoftData.ArrayMap {
            if (arr == SourceArr && name != NewArrName) {
                sourceName := name
                break
            }
        }
        if (sourceName == "")
            sourceName := NewArrName
        MsgSendHandler("CloneArray", sourceName, NewArrName)
    }

    WorkDeleteGlobalArray(ArrName) {
        if (MySoftData.ArrayMap.Has(ArrName))
            MySoftData.ArrayMap.Delete(ArrName)
        MsgSendHandler("DeleteArray", ArrName)
    }

    WorkModifyGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
        SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
        SourceArr[Index] := Value
        ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
        MsgSendHandler("ModifyArray", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
    }

    WorkInsertGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
        SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
        SourceArr.InsertAt(Index, Value)
        ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
        MsgSendHandler("InsertArray", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
    }

    WorkRemoveAtGlobalArray(ArrName, MainIndex, Index) {
        SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
        SourceArr.RemoveAt(Index)
        MsgSendHandler("RemoveAtArray", ArrName, MainIndex, Index)
    }

    WorkSetGlobalVariable(NameArr, ValueArr, ignoreExist) {
        RealNameArr := NameArr.Clone()
        RealValueArr := ValueArr.Clone()

        if (ignoreExist) {
            RealNameArr := []
            RealValueArr := []
            loop NameArr.Length {
                if (!MySoftData.VariableMap.Has(NameArr[A_Index])) {
                    RealNameArr.Push(NameArr[A_Index])
                    RealValueArr.Push(ValueArr[A_Index])
                }
            }
        }
        if (RealNameArr.Length == 0)
            return

        loop RealNameArr.Length {
            MySoftData.VariableMap[RealNameArr[A_Index]] := ValueArr[A_Index]
        }
        MsgSendHandler("SetVari", RealNameArr, RealValueArr)
    }

    WorkDelGlobalVariable(NameArr) {
        RealNameArr := []
        loop NameArr.Length {
            if (MySoftData.VariableMap.Has(NameArr[A_Index])) {
                MySoftData.VariableMap.Delete(NameArr[A_Index])
                RealNameArr.Push(NameArr[A_Index])
            }
        }

        if (RealNameArr.Length == 0)
            return
        MsgSendHandler("DelVari", RealNameArr)
    }
}

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

    TriggerMacro(tableItem, itemIndex) {
        if (!IsObject(tableItem))
            tableItem := GetTableByID(String(tableItem))
        if (!tableItem)
            return
        if (IsObject(itemIndex)) {
            itemIndex := GetItemIndexInTable(tableItem, itemIndex.ID)
        } else if (!IsNumber(itemIndex)) {
            itemIndex := GetItemIndexInTable(tableItem, String(itemIndex))
        }
        if (itemIndex < 1)
            return
        item := tableItem.Items[itemIndex]
        macro := item ? item.Macro : ""
        OnTriggerMacroKeyAndInit(tableItem, macro, itemIndex)
    }

    WorkStopMacro(tableItem, itemIndex) {
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        MsgSendHandler("StopMacro", tID, iID)
    }

    WorkTriggerSubMacro(tableItem, itemIndex) {
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        MsgSendHandler("TR_MACRO", tID, iID)
    }

    WorkSubmitGraphBranches(tableItem, itemIndex, branchCount, nodeSerialArr) {
        global tx, workIndex, graphBranchesWaiting, graphBranchesAckKey, graphBranchesAckReceived, workerPendingTasks
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        nodes := ""
        for s in nodeSerialArr
            nodes .= (nodes != "" ? "," : "") s
        GraphPoolLog("Worker批量请求分支", Format("tab={1} item={2} 总数={3} 子分支=[{4}]"
            , tID, iID, branchCount, nodes))
        graphBranchesAckKey := tID "_" iID
        graphBranchesAckReceived := false
        graphBranchesWaiting := true
        try {
            MsgSendHandler("GraphMacroBranches", tID, iID, branchCount, nodeSerialArr)
            start := A_TickCount
            loop {
                while (tx.Pop(&type, &id, &payload)) {
                    if (type == MsgType.TASK) {
                        workerPendingTasks.Push({ id: id, cmd: payload })
                        GraphPoolLog("Worker等待分支时缓存任务", Format("id={1} pending={2}", id, workerPendingTasks.Length))
                        continue
                    }
                    if (type == MsgType.EVENT) {
                        try {
                            if (SubStr(payload, 1, 2) == "R1") {
                                commandsStr := SubStr(payload, 3)
                                for record in StrSplit(commandsStr, IPC_REC) {
                                    if (record == "")
                                        continue
                                    parts := StrSplit(record, IPC_SEP)
                                    if (parts.Length >= 3 && parts[1] == "GA" && parts[2] == tID && parts[3] == iID) {
                                        GraphPoolLog("Worker分支分配就绪", Format("tab={1} item={2}", tID, iID))
                                        return
                                    }
                                }
                            }
                        } catch {
                        }
                        OnEventMessage(payload)
                    }
                }
                if (graphBranchesAckReceived) {
                    GraphPoolLog("Worker分支分配就绪", Format("tab={1} item={2}", tID, iID))
                    return
                }
                if (A_TickCount - start >= 3000) {
                    GraphPoolLog("Worker等待分支分配超时", Format("tab={1} item={2}", tID, iID))
                    return
                }
                Sleep(10)
            }
        } finally {
            graphBranchesWaiting := false
            graphBranchesAckKey := ""
            graphBranchesAckReceived := false
        }
    }

    WorkSetTableItemState(tableItem, itemIndex, state) {
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        MsgSendHandler("ItemState", tID, iID, state)
    }

    WorkSetItemPauseState(tableItem, itemIndex, state) {
        tID := IsObject(tableItem) ? tableItem.ID : String(tableItem)
        iID := WorkResolveItemID(tableItem, itemIndex)
        if (IsObject(tableItem) && IsNumber(itemIndex)) {
            item := tableItem.Items[itemIndex]
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
    WorkCMDReport(cmdStr) {
        MsgSendHandler("Report", cmdStr)
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

    WorkMacroCount(content) {
        MsgSendHandler("MacroCount", content)
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

    GetArrayRefByPath(rootArr, path, &lastIdx) {
        parts := StrSplit(path, ".")
        curr := rootArr
        if (parts.Length == 2 && parts[1] == "0") {
            lastIdx := Integer(parts[2])
            return rootArr
        }
        loop parts.Length - 1 {
            idx := Integer(parts[A_Index])
            curr := curr[idx]
        }
        lastIdx := Integer(parts[parts.Length])
        return curr
    }
}
