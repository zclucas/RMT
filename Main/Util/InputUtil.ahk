#Requires AutoHotkey v2.0

; =====================================================================
; 输入 / 等待确定 统一通信（输入框/按钮条）：
; Worker 跨进程请求主进程弹窗（IP/IB/IF → WorkPool 弹窗 → IPR/IBR 回传）；
; 主进程宏经 WorkPool.RequestLocalInput 由主线程异步弹窗（结果写本地槽位）。
; 返回 args 数组（IPR: [ok, value]；IBR: [button]）；失败/超时返回 ""
; IB 结果：true/false/continue/cancel/pause/terminate/timeout，或 sel:选项
; =====================================================================
InputRequest(opcode, args*) {
    return DispatchInputRequest(opcode, "", args*)
}

RequestMacroInput(Data, tableItem, index, opcode, args*) {
    args.Push(InputTimeoutArg(Data))
    return DispatchInputRequest(opcode, GetItemByIndex(tableItem, index), args*)
}

DispatchInputRequest(opcode, item, args*) {
    global MyWorkPool
    pack := SplitInputReqArgs(args)
    sendArgs := pack.args.Clone()
    if (pack.timeoutMs > 0)
        sendArgs.Push("to=" pack.timeoutMs)
    if (IsSet(workIndex) && workIndex > 0)
        return WorkerInputRequest(opcode, pack.timeoutMs, item, sendArgs*)
    ; 主进程宏：交由主线程 WorkPool 弹窗
    if (MyWorkPool != "" && IsObject(MyWorkPool))
        return MyWorkPool.RequestLocalInput(opcode, pack.timeoutMs, item, sendArgs*)
    return ""
}

InputResponseDeadline(timeoutMs, graceMs, item) {
    if (timeoutMs > 0)
        return A_TickCount + timeoutMs + graceMs
    return IsObject(item) ? 0 : A_TickCount + 300000
}

WorkerInputRequest(opcode, timeoutMs, item, args*) {
    global rx, workIndex, parentHwnd, _workerInputResult
    if (!IsSet(rx) || !IsSet(parentHwnd))
        return ""
    cmd := EncodeCommand(opcode, args*)
    payload := EncodeBatch(cmd)
    _workerInputResult := ""
    rx.Push(MsgType.EVENT, 0, payload)
    ; 队列满时 PostMessage 抛 OSError(1816)，不能让它传播到宏执行流程
    try PostMessage(WM_WORKER_TO_MASTER, workIndex, 0, , "ahk_id " parentHwnd)
    deadline := InputResponseDeadline(timeoutMs, 2000, item)
    loop {
        Sleep(100)
        if (IsObject(item) && item.Killed)
            return ""
        if (IsObject(_workerInputResult))
            break
        if (deadline && A_TickCount > deadline)
            return ["timeout"]
    }
    r := _workerInputResult
    _workerInputResult := ""
    return r
}

SplitInputReqArgs(args) {
    timeoutMs := 0
    realArgs := []
    for a in args {
        if (Type(a) == "String" && SubStr(a, 1, 3) == "to=") {
            try timeoutMs := Integer(SubStr(a, 4))
            catch
                timeoutMs := 0
        }
        else
            realArgs.Push(a)
    }
    return { timeoutMs: timeoutMs, args: realArgs }
}

EnsureInputData(Data) {
    if (!IsObject(Data))
        return
    if (!ObjHasOwnProp(Data, "Prompt"))
        Data.Prompt := "提示文本"
    if (!ObjHasOwnProp(Data, "Options"))
        Data.Options := "选项一，选项二，选项三"
    if (!ObjHasOwnProp(Data, "DefaultValue"))
        Data.DefaultValue := ""
    if (!ObjHasOwnProp(Data, "TimeoutMs"))
        Data.TimeoutMs := 0
    if (!ObjHasOwnProp(Data, "TimeoutAction"))
        Data.TimeoutAction := "无"
}

InputTypeKeys(current := "") {
    keys := ["弹窗", "状态", "选择", "选择文件", "多选"]
    if (current == "继续" || current == "继续&取消")
        keys.Push(current)
    return keys
}

InputHasResult(type) {
    return type == "弹窗" || type == "状态" || type == "选择" || type == "选择文件" || type == "多选"
}

InputField(Data, prop, def := "") {
    return (IsObject(Data) && ObjHasOwnProp(Data, prop)) ? Data.%prop% : def
}

InputTimeoutArg(Data) {
    ms := Integer(InputField(Data, "TimeoutMs", 0))
    return ms > 0 ? "to=" ms : ""
}

InputDefaultPrompt() {
    return GetLang("提示文本")
}

InputDefaultOptions() {
    return GetLang("选项一") "，" GetLang("选项二") "，" GetLang("选项三")
}

InputOptionArr(str) {
    arr := []
    if (str == "")
        return arr
    text := StrReplace(str, "`r`n", ",")
    text := StrReplace(text, "`r", ",")
    text := StrReplace(text, "`n", ",")
    text := StrReplace(text, "，", ",")
    parts := StrSplit(text, ",")
    for p in parts {
        p := Trim(p)
        if (p != "")
            arr.Push(p)
    }
    return arr
}

InputResolveText(tableItem, index, text) {
    if (text == "")
        return ""
    try
        return GetReplaceVarText(tableItem, index, text)
    catch
        return text
}

InputBeginPause(Data) {
    if (InputField(Data, "PauseType", "暂停当前宏") == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")
}

InputEndPause(Data, skipResume := false) {
    if (skipResume)
        return
    if (InputField(Data, "PauseType", "暂停当前宏") == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputBtnResult(result) {
    if (!IsObject(result) || result.Length < 1)
        return ""
    return result[1]
}

InputSelValue(result) {
    btn := InputBtnResult(result)
    if (SubStr(btn, 1, 4) == "sel:")
        return SubStr(btn, 5)
    return ""
}

InputApplyStop(tableItem, index, stopType) {
    if (stopType == "终止所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_终止所有宏")
    else
        MyStopMacro(tableItem, index)
}

InputPopUp(Data, tableItem, index) {
    EnsureInputData(Data)
    InputBeginPause(Data)

    prompt := InputResolveText(tableItem, index, Data.Prompt)
    Label := prompt != "" ? prompt : GetLang("变量名：") Data.SaveName
    Content := InputResolveText(tableItem, index, Data.DefaultValue)
    if (Content == "" && MySoftData.VariableMap.Has(Data.SaveName))
        Content := MySoftData.VariableMap[Data.SaveName]

    result := RequestMacroInput(Data, tableItem, index, "IP", Label, Content)
    if (IsObject(result) && result.Length >= 2 && result[1] == "1") {
        MySetGlobalVariable([Data.SaveName], [result[2]], false)
    }
    else if (InputBtnResult(result) == "timeout") {
        if (HandleInputTimeout(Data, tableItem, index, Data.DefaultValue)) {
            InputEndPause(Data)
            return
        }
    }

    InputEndPause(Data)
}

InputPickFile(Data, tableItem, index) {
    EnsureInputData(Data)
    InputBeginPause(Data)
    try {
        title := InputResolveText(tableItem, index, Data.Prompt)
        if (title == "" || title == "提示文本" || title == InputDefaultPrompt())
            title := GetLang("选择文件")
        result := RequestMacroInput(Data, tableItem, index, "IF", "title=" title)
        switch InputBtnResult(result) {
            case "1":
                if (result.Length >= 2 && result[2] != "")
                    MySetGlobalVariable([Data.SaveName], [result[2]], false)
            case "timeout":
                HandleInputTimeout(Data, tableItem, index, Data.DefaultValue)
        }
    } finally InputEndPause(Data)
}

InputStateValue(Data, tableItem, index) {
    EnsureInputData(Data)
    InputBeginPause(Data)

    prompt := InputResolveText(tableItem, index, Data.Prompt)
    result := RequestMacroInput(Data, tableItem, index, "IB", "1", prompt, "", "")
    btn := InputBtnResult(result)
    if (btn == "true")
        MySetGlobalVariable([Data.SaveName], [1], false)
    else if (btn == "false")
        MySetGlobalVariable([Data.SaveName], [0], false)
    else if (btn == "timeout") {
        def := InputResolveText(tableItem, index, Data.DefaultValue)
        if (HandleInputTimeout(Data, tableItem, index, def != "" ? def : "0")) {
            InputEndPause(Data)
            return
        }
    }

    InputEndPause(Data)
}

InputChoice(Data, tableItem, index, multi := false) {
    EnsureInputData(Data)
    InputBeginPause(Data)

    prompt := InputResolveText(tableItem, index, Data.Prompt)
    options := InputResolveText(tableItem, index, Data.Options)
    if (InputOptionArr(options).Length == 0)
        options := InputDefaultOptions()
    def := InputResolveText(tableItem, index, Data.DefaultValue)
    result := RequestMacroInput(Data, tableItem, index, "IB", multi ? "6" : "5", prompt, options, def)
    btn := InputBtnResult(result)
    if (btn == "timeout") {
        if (HandleInputTimeout(Data, tableItem, index, def)) {
            InputEndPause(Data)
            return
        }
    }
    else if (SubStr(btn, 1, 4) == "sel:") {
        MySetGlobalVariable([Data.SaveName], [InputSelValue(result)], false)
    }

    InputEndPause(Data)
}

HandleInputTimeout(Data, tableItem, index, fallback := "") {
    action := GetLangKey(InputField(Data, "TimeoutAction", "无"))
    switch action {
        case "用默认值":
            val := InputResolveText(tableItem, index, fallback)
            if (val == "")
                val := InputResolveText(tableItem, index, Data.DefaultValue)
            MySetGlobalVariable([Data.SaveName], [val], false)
            return false
        case "保持原值":
            return false
        case "终止当前宏":
            InputApplyStop(tableItem, index, "终止当前宏")
            return true
        case "终止所有宏":
            InputApplyStop(tableItem, index, "终止所有宏")
            return true
    }
    return false
}

InputContinue(Data, tableItem, index) {
    InputBeginPause(Data)
    RequestMacroInput(Data, tableItem, index, "IB", "2", InputResolveText(tableItem, index, InputField(Data, "Prompt", "")), "", "")
    InputEndPause(Data)
}

InputContinueAndCencel(Data, tableItem, index) {
    InputBeginPause(Data)
    result := RequestMacroInput(Data, tableItem, index, "IB", "3", InputResolveText(tableItem, index, InputField(Data, "Prompt", "")), "", "")
    if (InputBtnResult(result) == "cancel")
        InputApplyStop(tableItem, index, Data.CancelType)
    InputEndPause(Data, InputBtnResult(result) == "cancel" && Data.CancelType == "终止所有宏")
}

OnWaitConfirm(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    if (!IsObject(Data))
        return
    RunWaitConfirmation(tableItem, index, Data)
}

RunWaitConfirmation(tableItem, index, Data, waitData := "") {
    item := GetItemByIndex(tableItem, index)
    pausedAll := GetLangKey(InputField(Data, "PauseType", "暂停当前宏")) == "暂停所有宏"
    if (pausedAll)
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    prompt := InputResolveText(tableItem, index, InputField(Data, "Prompt", ""))
    ibType := GetLangKey(InputField(Data, "Type", "继续")) == "继续&终止&暂停" ? "4" : "2"
    result := RequestMacroInput(IsObject(waitData) ? waitData : Data, tableItem, index, "IB", ibType, prompt, "", "")
    action := InputBtnResult(result)
    if (IsObject(item) && (item.Killed || GetItemByIndex(tableItem, index) != item))
        action := ""
    if (IsObject(waitData) && IsObject(item)
        && (action == "timeout" || action == "continue" || action == "terminate" || action == "pause"))
        WaitWriteStatus(waitData, action == "timeout")
    if (action == "timeout")
        action := WaitConfirmTimeoutAction(InputField(Data, "TimeoutAction", "无"))

    if (action == "terminate") {
        terminateType := InputField(Data, "TerminateType", "终止当前宏")
        InputApplyStop(tableItem, index, terminateType)
        if (terminateType != "终止所有宏" && pausedAll)
            MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
        return
    }
    if (action == "pause") {
        if (InputField(Data, "PauseBtnType", "暂停当前宏") == "暂停所有宏") {
            if (!pausedAll)
                MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")
        }
        else {
            if (pausedAll)
                MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
            MySetItemPauseState(tableItem, index, 1)
        }
        return
    }

    if (pausedAll)
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

WaitConfirmTimeoutAction(action) {
    key := GetLangKey(action)
    switch key {
        case "自动终止":
            return "terminate"
        case "自动暂停":
            return "pause"
        default:
            return "continue"
    }
}
