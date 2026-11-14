#Requires AutoHotkey v2.0

global LastError := ""
global _ErrShowing := false

; 始终返回 1：阻止 AHK 默认错误框（Help/Edit/Reload/ExitApp），只走 RMT 错误窗
ErrHandler(exception, mode) {
    global LastError
    LastError := exception
    try _HandleError(exception)
    return 1
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

    ; 其余错误：统一归口日志 + RMT 错误窗，不再弹 AHK 默认错误框
    _ShowError(fullInfo, stack)
    return true
}

_ShowError(msg, stack := "") {
    global _ErrShowing
    fullMsg := msg
    if (stack != "")
        fullMsg .= "`n堆栈信息：`n" stack

    ; Worker 不注册本处理器：它自己的 OnError(WorkOnError) 会把错误走 IPC 上报（见 WorkUtil）。
    ; 所以这里只处理主进程的错误，不需要再按角色分支。
    if (_ErrShowing)
        return
    _ErrShowing := true
    try {
        ; 主进程：归口系统日志 + 错误中心聚合（不模态弹窗打断）
        RMTLogSys(RMT_LV_ERROR, "Master", fullMsg)
        ; 必须立刻落盘：启动期出错时自动执行线程就此结束、进程随即退出，
        ; 日志只留在缓冲区里，用户看到的就是「托盘一闪就没了」且零痕迹。
        try FlushRMTLogAsync()
        if (IsSet(MyErrorMsgBoxGui) && IsObject(MyErrorMsgBoxGui))
            MyErrorMsgBoxGui.ShowGui(Format("[Master] {}", fullMsg))
    } catch {
    } finally {
        _ErrShowing := false
    }
}
