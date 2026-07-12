#Requires AutoHotkey v2.0

;初始化数据
{
    HandleWorkOpenArg() {
        argMap := MapArgs(A_Args)
        global parentHwnd := argMap.Has("--parentHwnd") ? argMap["--parentHwnd"] : ""
        global workIndex := argMap.Has("--idx") ? argMap["--idx"] : 0
        global parentPID := argMap.Has("--parentPID") ? argMap["--parentPID"] : 0
        global txName := argMap.Has("--txName") ? argMap["--txName"] : ""
        global rxName := argMap.Has("--rxName") ? argMap["--rxName"] : ""
        global evtName := argMap.Has("--evtName") ? argMap["--evtName"] : ""

        global shmTx := SharedMemory(txName, 1048576 + 192)
        global shmRx := SharedMemory(rxName, 1048576 + 192)
        global tx := RingBuffer(shmTx.ptr, 1048576)
        global rx := RingBuffer(shmRx.ptr, 1048576)

        global hEvt := 0
        if (evtName) {
            global hEvt := DllCall("OpenEventW", "uint", 0x00100002, "int", false, "ptr", StrPtr(evtName), "ptr")
        }
    }

    MapArgs(args) {
        result := Map()
        for arg in args {
            p := StrSplit(arg, "=", , 2)
            if (p.Length == 2) {
                result[p[1]] := p[2]
            }
        }
        return result
    }

    InitWorkFilePath() {
        global VBSPath := A_WorkingDir "\..\MinTool\PlayAudio.vbs"
        global StartTipAudio := A_WorkingDir "\..\Audio\Start.wav"
        global EndTipAudio := A_WorkingDir "\..\Audio\End.wav"
        global ViGEmDllPath := A_WorkingDir "\..\Plugins\ViGEm\ViGEmWrapper.dll"
        global AHIDllDir := A_WorkingDir "\..\Plugins\AhiDriver"
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
        global MySoftData
        global graphBranchesWaiting := false
        global graphBranchesAckReceived := false
        global graphBranchesAckKey := ""
        global workerTaskBusy := false
        global workerPendingTasks := []
        MySoftData.isWorker := true

        OnError(WorkOnError)
        SetTimer(CheckParentProcess, 10000)
        SetTimer(CheckTxBuffer, 1000)  ; 兜底轮询：1000ms 检查一次环形缓冲区，防止 PostMessage 丢失
    }

    WorkOnError(e, mode) {
        GraphPoolLog("Worker运行时错误", Format("err={1} line={2} file={3} mode={4}"
            , e.Message, e.Line, e.File, mode))
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
        ; 根据进程位数自动选择 x86 或 x64
        archDir := (A_PtrSize = 4) ? "x86" : "x64"
        dllDir := A_ScriptDir "\..\Plugins\OpenCV\" archDir
        OpenCvPath := dllDir "\RMT_OpenCV.dll"
        IBPath := A_ScriptDir "\..\Plugins\IbInputSimulator.dll"

        ; 使用 SetDllDirectory 将 dllDir 添加到 DLL 搜索路径中
        DllCall("SetDllDirectory", "Str", dllDir)
        DllCall('LoadLibrary', 'str', OpenCvPath, "Ptr")
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
            "TR_MACRO", "TR",
            "GraphMacroBranches", "GB",
            "ItemState", "IS",
            "PauseState", "PS",
            "Report", "RP",
            "RMT指令", "RC",
            "MsgBox", "MB",
            "ToolTip", "TT",
            "MacroCount", "MC",
            "Joy", "JY"
        )

        opcode := actionMap.Has(action) ? actionMap[action] : action
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
                name := args[1]
                arr := GetArray(args[2])
                realArgs.Push(name, arr.Length)
                for item in arr
                    realArgs.Push(item)
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
        workerTaskBusy := true
        try {
            if (SubStr(cmd, 1, 2) != "R1") {
                GraphPoolLog("Worker任务解析失败", Format("id={1} err=Protocol header missing cmd={2}", id, SubStr(cmd, 1, 120)))
                return
            }
            commandsStr := SubStr(cmd, 3)
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

                if (opcode == "TR") {
                    tIdx := args[1]
                    iIdx := args[2]
                    if (args.Length >= 3) {
                        nodeSerial := args[3]
                        GraphPoolLog("Worker开始执行", Format("tab={1} item={2} node={3}", tIdx, iIdx, nodeSerial))
                        tableItem := MySoftData.TableInfo[tIdx]
                        WalkGraphNode(tableItem, nodeSerial, iIdx)
                    } else {
                        TriggerMacro(tIdx, iIdx)
                    }
                }
            }
        } catch as e {
            GraphPoolLog("Worker任务异常", Format("id={1} err={2} line={3} cmd={4}"
                , id, e.Message, e.Line, SubStr(cmd, 1, 120)))
        } finally {
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
        if (SubStr(cmd, 1, 2) != "R1")
            return

        commandsStr := SubStr(cmd, 3)
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
                        MySoftData.VariableMap[args[1]] := args[2]
                    case "DV":
                        if (MySoftData.VariableMap.Has(args[1]))
                            MySoftData.VariableMap.Delete(args[1])
                    case "CT":
                        MySoftData.CMDTip := args[1]
                    case "PS":
                        tableItem := MySoftData.TableInfo[args[1]]
                        tableItem.PauseArr[args[2]] := args[3]
                    case "SA":
                        name := args[1]
                        count := Integer(args[2])
                        arr := []
                        loop count {
                            arr.Push(args[A_Index + 2])
                        }
                        MySoftData.ArrayMap[name] := arr
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
                        tableItem := MySoftData.TableInfo[args[1]]
                        KillTableItemMacro(tableItem, args[2])
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

;宏指令相关函数
{
    TriggerMacro(tableIndex, itemIndex) {
        tableItem := MySoftData.TableInfo[tableIndex]
        macro := tableItem.MacroArr[itemIndex]
        OnTriggerMacroKeyAndInit(tableItem, macro, itemIndex)
    }

    WorkStopMacro(tableIndex, itemIndex) {
        MsgSendHandler("StopMacro", tableIndex, itemIndex)
    }

    WorkTriggerSubMacro(tableIndex, itemIndex) {
        MsgSendHandler("TR_MACRO", tableIndex, itemIndex)
    }

    WorkSubmitGraphBranches(tableIndex, itemIndex, branchCount, nodeSerialArr) {
        global tx, workIndex, graphBranchesWaiting, graphBranchesAckKey, graphBranchesAckReceived, workerPendingTasks
        nodes := ""
        for s in nodeSerialArr
            nodes .= (nodes != "" ? "," : "") s
        GraphPoolLog("Worker批量请求分支", Format("tab={1} item={2} 总数={3} 子分支=[{4}]"
            , tableIndex, itemIndex, branchCount, nodes))
        graphBranchesAckKey := tableIndex "_" itemIndex
        graphBranchesAckReceived := false
        graphBranchesWaiting := true
        try {
            MsgSendHandler("GraphMacroBranches", tableIndex, itemIndex, branchCount, nodeSerialArr)
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
                                for record in StrSplit(commandsStr, Chr(2)) {
                                    if (record == "")
                                        continue
                                    parts := StrSplit(record, Chr(1))
                                    if (parts.Length >= 3 && parts[1] == "GA" && parts[2] == tableIndex && parts[3] == itemIndex) {
                                        GraphPoolLog("Worker分支分配就绪", Format("tab={1} item={2}", tableIndex, itemIndex))
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
                    GraphPoolLog("Worker分支分配就绪", Format("tab={1} item={2}", tableIndex, itemIndex))
                    return
                }
                if (A_TickCount - start >= 3000) {
                    GraphPoolLog("Worker等待分支分配超时", Format("tab={1} item={2}", tableIndex, itemIndex))
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

    WorkSetTableItemState(tableIndex, itemIndex, state) {
        MsgSendHandler("ItemState", tableIndex, itemIndex, state)
    }

    WorkSetItemPauseState(tableIndex, itemIndex, state) {
        tableItem := MySoftData.TableInfo[tableIndex]
        tableItem.PauseArr[itemIndex] := state
        MsgSendHandler("PauseState", tableIndex, itemIndex, state)
    }
}

;子程序告诉主程动作
{
    WorkCMDReport(cmdStr) {
        MsgSendHandler("Report", cmdStr)
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
