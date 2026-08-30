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

    ; DLL加载失败 —— 静默（提示后抑制默认对话框）
    if (RegExMatch(fullInfo, "Failed to load DLL.") || (msg && RegExMatch(msg, "Failed to load DLL."))){
        _ShowError("DLL加载失败,检查DLL是否存在并解锁：" extra, stack)
        return true
    }

    ; 其余错误：统一归口日志 + 错误中心聚合，不再弹 AHK 默认错误框（避免打断操作）
    _ShowError(fullInfo, stack)
    return true
}

_ShowError(msg, stack := "") {
    fullMsg := msg
    if (stack != "")
        fullMsg .= "`n堆栈信息：`n" stack

    if (IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker) {
        if (IsSet(MsgSendHandler)) {
            ; Worker：仅 ER 上报主进程（主进程统一记录日志 + 聚合，避免双写）
            MsgSendHandler("Error", "error|" workIndex "|" fullMsg)
            return
        }
    }

    ; 主进程：归口系统日志 + 错误中心聚合（不模态弹窗打断）
    RMTLogSys(RMT_LV_ERROR, "Master", fullMsg)
    if (IsSet(MyErrorMsgBoxGui) && IsObject(MyErrorMsgBoxGui))
        MyErrorMsgBoxGui.ShowGui(Format("[Master] {}", fullMsg))
    else
        msgbox(fullMsg)
}
