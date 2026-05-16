#Requires AutoHotkey v2.0

global LastError := ""

ErrHandler(exception, mode) {
    LastError := exception

    result := _HandleError(exception)
    if (result == true || result == "suppress")
        return mode == "Return" ? -1 : 1

    return 0
}

_HandleError(exception) {
    what := ""
    msg := ""
    extra := ""
    stack := ""
    if (IsObject(exception)) {
        try extra := exception.Extra
        try what := exception.What
        try msg := exception.Message
        try stack := exception.Stack
    } else {
        msg := "" . exception
    }
    fullInfo := what . (what && msg ? " | " : "") . msg

    ; DLL加载失败 —— 静默
    if (RegExMatch(fullInfo, "Failed to load DLL.") || (msg && RegExMatch(msg, "Failed to load DLL."))){
        _ShowError("DLL加载失败,检查DLL是否存在并解锁：" extra, stack)
        return true
    }

    return false
}

_ShowError(msg, stack := "") {
    if (IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker) {
        if (IsSet(MsgSendHandler)) {
            fullMsg := msg
            if (stack != "")
                fullMsg .= "`n堆栈信息：`n" stack
            MsgSendHandler("Error", fullMsg)
            return
        }
    }
    
    if (stack != "")
        msgbox(msg "`n堆栈信息：`n" stack)
    else
        msgbox(msg)
}
