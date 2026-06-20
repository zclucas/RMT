#Requires AutoHotkey v2.0

;初始化数据
{
    HandleWorkOpenArg() {
        global parentHwnd := A_Args[1]
        global workIndex := A_Args[2]
        global parentPID := A_Args[3]
        global txName := A_Args[4]
        global rxName := A_Args[5]

        global shmTx := SharedMemory(txName, 1048576 + 192)
        global shmRx := SharedMemory(rxName, 1048576 + 192)
        global tx := RingBuffer(shmTx.ptr, 1048576)
        global rx := RingBuffer(shmRx.ptr, 1048576)
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
        payload := JSON.stringify([action, args*])
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
            try {
                paramArr := JSON.parse(cmd)
            } catch as e {
                GraphPoolLog("Worker任务解析失败", Format("id={1} err={2} cmd={3}", id, e.Message, SubStr(cmd, 1, 120)))
                return
            }
            if (paramArr[1] == "TR_GRAPH") {
                GraphPoolLog("Worker开始执行", Format("tab={1} item={2} node={3}", paramArr[2], paramArr[3], paramArr[4]))
                tableItem := MySoftData.TableInfo[paramArr[2]]
                WalkGraphNode(tableItem, paramArr[4], paramArr[3])
            } else {
                tableItem := MySoftData.TableInfo[paramArr[2]]
                itemIndex := paramArr[3]
                macro := tableItem.MacroArr[itemIndex]
                if (IsGraphStartSerial(macro) && ShouldUseGraphWorkers()) {
                    tableItem.KilledArr[itemIndex] := false
                    tableItem.PauseArr[itemIndex] := false
                    OnTriggerGraphMacro(tableItem, macro, itemIndex)
                } else {
                    TriggerMacro(paramArr[2], paramArr[3])
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
        try {
            paramArr := JSON.parse(cmd)
            actionStr := paramArr[1]
            args := []
            loop paramArr.Length - 1 {
                args.Push(paramArr[A_Index + 1])
            }
            switch actionStr {
                case "SyncVarData":
                    ; 全量同步：清空后用主线程状态覆盖
                    VarArr := args[1]
                    ArrArr := args[2]
                    MySoftData.VariableMap.Clear()
                    for entry in VarArr
                        MySoftData.VariableMap[entry[1]] := entry[2]
                    MySoftData.ArrayMap.Clear()
                    for entry in ArrArr
                        MySoftData.ArrayMap[entry[1]] := GetArray(entry[2])
                case "SetVari":
                    NameArr := args[1]
                    ValueArr := args[2]
                    loop NameArr.Length {
                        MySoftData.VariableMap[NameArr[A_Index]] := ValueArr[A_Index]
                    }
                case "DelVari":
                    NameArr := args[1]
                    loop NameArr.Length {
                        if (MySoftData.VariableMap.Has(NameArr[A_Index]))
                            MySoftData.VariableMap.Delete(NameArr[A_Index])
                    }
                case "CMDTip":
                    MySoftData.CMDTip := args[1]
                case "PauseState":
                    tableItem := MySoftData.TableInfo[args[1]]
                    tableItem.PauseArr[args[2]] := args[3]
                case "SetArray":
                    Name := args[1]
                    Value := GetArray(args[2])
                    MySoftData.ArrayMap[Name] := Value
                case "CloneArray":
                    SourceArr := GetArray(args[1])
                    NewArrName := args[2]
                    MySoftData.ArrayMap[NewArrName] := SourceArr
                case "DeleteArray":
                    if (MySoftData.ArrayMap.Has(args[1]))
                        MySoftData.ArrayMap.Delete(args[1])
                case "ModifyArray":
                    ArrName := args[1]
                    MainIndex := args[2]
                    Index := args[3]
                    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex
                        ]
                    Value := args[4] ? GetArray(args[5]) : args[5]
                    SourceArr[Index] := Value
                case "InsertArray":
                    ArrName := args[1]
                    MainIndex := args[2]
                    Index := args[3]
                    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex
                        ]
                    Value := args[4] ? GetArray(args[5]) : args[5]
                    SourceArr.InsertAt(Index, Value)
                case "RemoveAtArray":
                    ArrName := args[1]
                    MainIndex := args[2]
                    Index := args[3]
                    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex
                        ]
                    SourceArr.RemoveAt(Index)
                case "StopMacro":
                    tableItem := MySoftData.TableInfo[args[1]]
                    KillTableItemMacro(tableItem, args[2])
                case "GraphBranchesAck":
                    global graphBranchesAckKey, graphBranchesAckReceived
                    key := args[1] "_" args[2]
                    if (IsSet(graphBranchesAckKey) && graphBranchesAckKey == key)
                        graphBranchesAckReceived := true
            }
        } catch {
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
        MsgSendHandler("CloneArray", GetArrayStr(SourceArr), NewArrName)
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

    WorkRequestGraphBranch(tableIndex, itemIndex, nodeSerial, skipInc := false) {
        MsgSendHandler("TR_GRAPH", tableIndex, itemIndex, nodeSerial, skipInc)
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
                            paramArr := JSON.parse(payload)
                            if (paramArr[1] == "GraphBranchesAck" && paramArr[2] == tableIndex && paramArr[3] == itemIndex) {
                                GraphPoolLog("Worker分支分配就绪", Format("tab={1} item={2}", tableIndex, itemIndex))
                                return
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

}
