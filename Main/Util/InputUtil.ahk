#Requires AutoHotkey v2.0

; =====================================================================
; 输入指令统一通信（输入框/按钮条）：
; Worker 跨进程请求主进程弹窗（IP/IB → WorkPool 弹窗 → IPR/IBR 回传）；
; 主进程宏经 WorkPool.RequestLocalInput 由主线程异步弹窗（结果写本地槽位）。
; 返回 args 数组（IPR: [ok, value]；IBR: [button]）；失败/超时返回 ""
; =====================================================================
InputRequest(opcode, args*) {
    global MyWorkPool
    if (IsSet(workIndex) && workIndex > 0)
        return WorkerInputRequest(opcode, args*)
    ; 主进程宏：交由主线程 WorkPool 弹窗
    if (MyWorkPool != "" && IsObject(MyWorkPool))
        return MyWorkPool.RequestLocalInput(opcode == "IB", args*)
    return ""
}

WorkerInputRequest(opcode, args*) {
    global rx, workIndex, parentHwnd, _workerInputResult
    if (!IsSet(rx) || !IsSet(parentHwnd))
        return ""
    cmd := EncodeCommand(opcode, args*)
    payload := EncodeBatch(cmd)
    rx.Push(MsgType.EVENT, 0, payload)
    PostMessage(WM_WORKER_TO_MASTER, workIndex, 0, , "ahk_id " parentHwnd)
    _workerInputResult := ""
    ; 阻塞等待主进程回传，超时兜底
    deadline := A_TickCount + 300000
    loop {
        Sleep(100)
        if (IsObject(_workerInputResult))
            break
        if (A_TickCount > deadline)
            return ""
    }
    r := _workerInputResult
    _workerInputResult := ""
    return r
}

InputPopUp(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    Label := GetLang("变量名：") Data.SaveName
    Content := ""
    if (MySoftData.VariableMap.Has(Data.SaveName))
        Content := MySoftData.VariableMap[Data.SaveName]

    result := InputRequest("IP", Label, Content)
    if (IsObject(result) && result.Length >= 2 && result[1] == "1") {
        MySetGlobalVariable([Data.SaveName], [result[2]], false)
    }

    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputStateValue(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    result := InputRequest("IB", "1")
    if (IsObject(result) && result[1] == "true")
        MySetGlobalVariable([Data.SaveName], [1], false)
    else if (IsObject(result) && result[1] == "false")
        MySetGlobalVariable([Data.SaveName], [0], false)

    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputContinue(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    InputRequest("IB", "2")

    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputContinueAndCencel(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    result := InputRequest("IB", "3")
    if (IsObject(result) && result[1] == "cancel") {
        if (Data.CancelType == "终止当前宏")
            MyStopMacro(tableItem, index)
        if (Data.CancelType == "终止所有宏")
            MyExcuteRMTCMDAction("RMT指令_宏控制_终止所有宏")
    }

    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}
