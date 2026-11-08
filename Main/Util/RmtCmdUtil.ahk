#Requires AutoHotkey v2.0

; =================================================================
; RMT 命令行（供其他软件调用）
;
;   rmt -help                显示全部指令
;   rmt -min                 后台运行，不打开主界面
;   rmt -run m-n             启动第 m 页签第 n 个宏
;   rmt -kill m-n            终止第 m 页签第 n 个宏
;   rmt -killall             终止所有宏
;   rmt -pause m-n           暂停第 m 页签第 n 个宏
;   rmt -resume m-n          继续第 m 页签第 n 个宏
;   rmt -pauseall            暂停所有宏
;   rmt -resumeall           继续所有宏
;   rmt -set key value       设置全局变量（没有则新增），值一律按字符串
;   rmt -get key             获取全局变量（字符串）
;   rmt -setarr key [1,2,3]  设置数组变量
;   rmt -getarr key          获取数组，返回字符串 [1,2,3]
;   rmt -status m-n          宏状态：0 闲置，1 正在运行，2 暂停中
;
; 环境变量 rmt = 程序完整路径（未编译时为 rmt.cmd）。
; 同时把 rmt.cmd 所在目录加入用户 PATH，因此新开的终端可直接输入 rmt。
; 已以管理员运行时，再写入系统环境变量 rmt，并把命令目录加入系统 PATH。
;
; 单实例：命名互斥。已有实例时，把参数写入命令队列，由常驻实例执行，
; 避免再次启动把正在跑的宏杀掉。需要结果的调用在进程退出前把文本写到标准输出。
; =================================================================

global RMT_CmdMutex := 0
global RMT_CmdQueueDir := ""
global RMT_PidFile := ""
global RMT_CmdReadyFile := ""
global RMT_CmdOwnConsole := false

RmtCmdInitPaths() {
    global RMT_CmdQueueDir, RMT_PidFile, RMT_CmdReadyFile
    RMT_CmdQueueDir := A_Temp "\RMT_CmdQueue"
    RMT_PidFile := A_Temp "\RMT_SingleInstance.pid"
    RMT_CmdReadyFile := A_Temp "\RMT_SingleInstance.ready"
}

; 创建并持有命名互斥。已被占用时返回 0。
RmtCreateMutex() {
    h := DllCall("kernel32\CreateMutexW", "Ptr", 0, "Int", 1, "WStr", "Local\RMT_SingleInstance", "Ptr")
    err := A_LastError
    if (!h)
        return 0
    if (err == 183) {    ; ERROR_ALREADY_EXISTS
        DllCall("kernel32\CloseHandle", "Ptr", h)
        return 0
    }
    return h
}

RmtReleaseMutex(h) {
    global RMT_CmdMutex
    if (h) {
        DllCall("kernel32\ReleaseMutex", "Ptr", h)
        DllCall("kernel32\CloseHandle", "Ptr", h)
    }
    if (RMT_CmdMutex = h)
        RMT_CmdMutex := 0
}

; 唯一实例返回 true。命令行调用在本函数内转发并退出，不会返回。
EnsureSingleInstance() {
    global RMT_CmdMutex
    RmtCmdInitPaths()
    if (!DirExist(RMT_CmdQueueDir))
        DirCreate(RMT_CmdQueueDir)

    if (RmtCmdIsHelp(A_Args))
        RmtCmdEmit(RmtCmdHelpText(), 0)

    mutex := RmtCreateMutex()
    if (mutex) {
        if (RmtCmdHasAction(A_Args)) {
            ; 这次启动只做客户端：放开互斥，拉起常驻实例，转发指令后退出
            RmtReleaseMutex(mutex)
            if (!RmtCmdSpawnServer(A_Args) || !RmtCmdWaitReady(120000)) {
                RmtCmdEmit("若梦兔启动失败或超时", 2)
                return false
            }
            RmtCmdClientFinish(RmtCmdClientArgs(A_Args))
            return false
        }
        RMT_CmdMutex := mutex
        RmtWritePid()
        return true
    }

    ; 已有实例。无参数或提权切换才接管；其余参数转发给正在运行的实例。
    if (RmtCmdIsTakeover(A_Args)) {
        h := RmtCmdTakeover()
        if (h) {
            RMT_CmdMutex := h
            RmtWritePid()
            return true
        }
        return false
    }
    RmtCmdClientFinish(RmtCmdClientArgs(A_Args))
}

RmtWritePid() {
    global RMT_PidFile
    try FileDelete(RMT_PidFile)
    FileAppend(ProcessExist(), RMT_PidFile)
}

RmtReadPid() {
    global RMT_PidFile
    if (!FileExist(RMT_PidFile))
        return 0
    try
        return Integer(Trim(FileRead(RMT_PidFile)))
    return 0
}

; 结束旧实例并拿到互斥句柄。句柄必须交还给调用方，不能在这里丢掉。
RmtCmdTakeover() {
    oldPid := RmtReadPid()
    if (RmtCmdProcessIsThisApp(oldPid)) {
        try ProcessClose(oldPid)
    }
    loop 200 {
        h := RmtCreateMutex()
        if (h)
            return h
        Sleep(50)
    }
    return 0
}

RmtCmdProcessIsThisApp(pid) {
    if (!pid || pid == ProcessExist() || !ProcessExist(pid))
        return false
    cmd := ""
    try {
        wmi := ComObjGet("winmgmts:")
        query := wmi.ExecQuery("Select CommandLine from Win32_Process where ProcessId=" pid)
        for proc in query
            cmd := proc.CommandLine
    }
    if (cmd != "" && InStr(cmd, A_ScriptFullPath))
        return true
    try {
        path := ProcessGetPath(pid)
        if (StrLower(path) = StrLower(A_ScriptFullPath))
            return true
    }
    return false
}

; ---------- 参数分类 ----------

RmtCmdSame(a, b) {
    return StrLower(a) = StrLower(b)
}

RmtCmdIsLaunchFlag(arg) {
    return RmtCmdSame(arg, "-min") || RmtCmdSame(arg, "-admin") || RmtCmdSame(arg, "-elevated")
}

RmtCmdIsHelp(args) {
    if !(args is Array) || args.Length < 1
        return false
    a := StrLower(args[1])
    return a = "-help" || a = "--help" || a = "/?"
}

; 除启动开关外，还有需要执行的指令
RmtCmdHasAction(args) {
    if !(args is Array)
        return false
    for a in args {
        if (SubStr(a, 1, 1) = "-" && !RmtCmdIsLaunchFlag(a))
            return true
    }
    return false
}

; 无参数，或仅有提权标记：关掉旧实例后由本进程接管
RmtCmdIsTakeover(args) {
    if !(args is Array) || args.Length = 0
        return true
    for a in args {
        if (!RmtCmdSame(a, "-elevated"))
            return false
    }
    return true
}

; 转发给常驻实例的参数。-min / -admin / -elevated 由启动过程消化。
RmtCmdClientArgs(args) {
    action := []
    hasMin := false
    for a in args {
        if (RmtCmdSame(a, "-min"))
            hasMin := true
        else if (!RmtCmdIsLaunchFlag(a))
            action.Push(a)
    }
    if (action.Length)
        return action
    if (hasMin)
        return ["-min"]
    return []
}

RmtCmdTail(args, index) {
    text := ""
    if (args.Length < index)
        return ""
    loop args.Length - index + 1 {
        if (A_Index > 1)
            text .= " "
        text .= args[index + A_Index - 1]
    }
    return text
}

RmtCmdQuote(text) {
    return '"' StrReplace(text, '"', '""') '"'
}

; ---------- 客户端：拉起常驻实例、转发、取回结果 ----------

RmtCmdHostCommand() {
    if (A_IsCompiled)
        return RmtCmdQuote(A_ScriptFullPath)
    return RmtCmdQuote(A_AhkPath) " " RmtCmdQuote(A_ScriptFullPath)
}

RmtCmdSpawnServer(args) {
    global RMT_CmdReadyFile
    try FileDelete(RMT_CmdReadyFile)
    launch := ""
    for a in args {
        if (RmtCmdSame(a, "-min") || RmtCmdSame(a, "-admin"))
            launch .= " " RmtCmdQuote(a)
    }
    ; start 脱离当前控制台，调用方退出后常驻实例继续运行
    cmd := RmtCmdQuote(A_ComSpec) " /c start `"`" " RmtCmdHostCommand() launch
    try {
        Run(cmd)
        return true
    } catch {
        return false
    }
}

RmtCmdWaitReady(timeoutMs) {
    global RMT_CmdReadyFile
    end := A_TickCount + timeoutMs
    while (A_TickCount < end) {
        if (FileExist(RMT_CmdReadyFile)) {
            pid := 0
            try pid := Integer(Trim(FileRead(RMT_CmdReadyFile)))
            if (pid > 0 && ProcessExist(pid))
                return true
        }
        Sleep(100)
    }
    return false
}

RmtCmdClientFinish(args) {
    if !(args is Array) || args.Length = 0
        RmtCmdEmit("", 0)
    reqId := RmtCmdForward(args)
    packed := RmtCmdWaitResult(reqId, 15000)
    if (packed == "")
        RmtCmdEmit("指令执行超时", 2)
    code := 0
    text := ""
    RmtCmdUnpack(packed, &code, &text)
    RmtCmdEmit(text, code)
}

RmtCmdForward(args) {
    global RMT_CmdQueueDir
    if (!DirExist(RMT_CmdQueueDir))
        DirCreate(RMT_CmdQueueDir)
    reqId := Format("{}_{}_{}", A_Now, ProcessExist(), Random(1000, 99999))
    content := ""
    for a in args
        content .= a Chr(31)
    content := RegExReplace(content, Chr(31) "$")
    FileAppend(content, RMT_CmdQueueDir "\req_" reqId ".cmd", "UTF-8-RAW")
    return reqId
}

RmtCmdWaitResult(reqId, timeoutMs) {
    global RMT_CmdQueueDir
    resFile := RMT_CmdQueueDir "\res_" reqId ".txt"
    end := A_TickCount + timeoutMs
    while (A_TickCount < end) {
        if (FileExist(resFile)) {
            try {
                res := FileRead(resFile, "UTF-8")
                try FileDelete(resFile)
                return res
            }
        }
        Sleep(50)
    }
    return ""
}

RmtCmdPack(result) {
    return result.code "`n" result.text
}

RmtCmdUnpack(packed, &code, &text) {
    code := 0
    text := ""
    pos := InStr(packed, "`n")
    if (!pos) {
        text := packed
        return
    }
    head := SubStr(packed, 1, pos - 1)
    text := SubStr(packed, pos + 1)
    if (IsNumber(head))
        code := Integer(head)
    else
        text := packed
}

; ---------- 常驻实例 ----------

StartCmdQueueListener() {
    global RMT_CmdQueueDir, RMT_CmdReadyFile
    RmtCmdInitPaths()
    if (!DirExist(RMT_CmdQueueDir))
        DirCreate(RMT_CmdQueueDir)
    SetTimer(RmtCmdPoll, 200)
    OnExit(RmtCmdOnExit)
    try FileDelete(RMT_CmdReadyFile)
    FileAppend(ProcessExist(), RMT_CmdReadyFile)
}

RmtCmdOnExit(*) {
    global RMT_PidFile, RMT_CmdReadyFile
    me := ProcessExist()
    if (RmtReadPid() = me)
        try FileDelete(RMT_PidFile)
    readyPid := 0
    try readyPid := Integer(Trim(FileRead(RMT_CmdReadyFile)))
    if (readyPid = me)
        try FileDelete(RMT_CmdReadyFile)
}

RmtCmdPoll(*) {
    global RMT_CmdQueueDir
    if (!DirExist(RMT_CmdQueueDir))
        return
    loop files, RMT_CmdQueueDir "\req_*.cmd" {
        filePath := A_LoopFilePath
        SplitPath(filePath, , , , &nameNoExt)
        reqId := StrReplace(nameNoExt, "req_", "")
        result := RmtCmdFail("指令执行失败")
        try {
            content := FileRead(filePath, "UTF-8")
            args := StrSplit(content, Chr(31))
            result := RmtCmdDispatch(args)
        } catch as e {
            result := RmtCmdFail(e.Message)
        }
        RmtCmdPublishResult(reqId, result)
        try FileDelete(filePath)
    }
}

RmtCmdPublishResult(reqId, result) {
    global RMT_CmdQueueDir
    dest := RMT_CmdQueueDir "\res_" reqId ".txt"
    tmp := dest ".tmp"
    try FileDelete(tmp)
    FileAppend(RmtCmdPack(result), tmp, "UTF-8-RAW")
    try FileMove(tmp, dest, 1)
}

; 本进程自己就是常驻实例时（例如只带 -min 启动），启动完成后执行残留参数
RmtRunStartupCommands() {
    global MySoftData
    if (!IsObject(MySoftData) || !MySoftData.HasProp("StartupCmdArr") || MySoftData.StartupCmdArr.Length == 0)
        return
    args := MySoftData.StartupCmdArr
    MySoftData.StartupCmdArr := []
    try result := RmtCmdDispatch(args)
    catch as e
        result := RmtCmdFail(e.Message)
    if (result.text != "")
        RmtCmdWriteOut(result.text)
}

; ---------- 指令执行 ----------

RmtCmdOk(text := "") {
    return { code: 0, text: String(text) }
}

RmtCmdFail(text) {
    return { code: 1, text: String(text) }
}

RmtParseMN(str, &m, &n) {
    m := 0, n := 0
    parts := StrSplit(str, "-")
    if (parts.Length == 2 && RegExMatch(parts[1], "^\d+$") && RegExMatch(parts[2], "^\d+$")) {
        m := Integer(parts[1])
        n := Integer(parts[2])
    }
}

RmtTableItemByMN(m, n, &tableItem) {
    global MySoftData
    tableItem := ""
    if (!IsObject(MySoftData) || m < 1 || m > MySoftData.TableInfo.Length)
        return false
    tableItem := MySoftData.TableInfo[m]
    if (n < 1 || n > tableItem.Items.Length)
        return false
    return true
}

RmtCmdItemStatus(item) {
    paused := false
    try paused := (item.Pause = 1 || item.Pause = true)
    state := 0
    try state := Integer(item.ColorState)
    if (paused || state = 2)
        return "2"
    if (state = 1)
        return "1"
    return "0"
}

RmtCmdSafeStr(value) {
    if (IsObject(value))
        return ""
    return String(value)
}

RmtCmdHideMain() {
    try {
        if (IsSet(MainSoftData) && IsObject(MainSoftData) && IsObject(MainSoftData.MyGui))
            MainSoftData.MyGui.Hide()
    }
}

RmtCmdDispatch(args) {
    global MySoftData, MainSoftData
    if !(args is Array) || args.Length < 1
        return RmtCmdFail("缺少指令，使用 rmt -help 查看")
    cmd := StrLower(Trim(args[1]))
    switch cmd {
        case "-help", "--help", "/?":
            return RmtCmdOk(RmtCmdHelpText())
        case "-min":
            MainSoftData.IsMinStart := true
            RmtCmdHideMain()
            return RmtCmdOk()
        case "-run", "-kill", "-pause", "-resume", "-status":
            return RmtCmdMacroOp(cmd, args)
        case "-killall":
            OnKillAllMacro()
            return RmtCmdOk()
        case "-pauseall":
            SetPauseState(true)
            return RmtCmdOk()
        case "-resumeall":
            SetPauseState(false)
            return RmtCmdOk()
        case "-set":
            return RmtCmdSetVar(args)
        case "-get":
            return RmtCmdGetVar(args)
        case "-setarr":
            return RmtCmdSetArr(args)
        case "-getarr":
            return RmtCmdGetArr(args)
        default:
            return RmtCmdFail("未知指令: " args[1] "，使用 rmt -help 查看")
    }
}

RmtCmdMacroOp(cmd, args) {
    if (args.Length < 2)
        return RmtCmdFail("用法: rmt " cmd " m-n")
    RmtParseMN(args[2], &m, &n)
    if (m < 1 || n < 1)
        return RmtCmdFail("位置格式应为 m-n，例如 1-2")
    if (!RmtTableItemByMN(m, n, &tableItem))
        return RmtCmdFail("页签或宏不存在: " args[2])
    item := tableItem.Items[n]
    switch cmd {
        case "-status":
            return RmtCmdOk(RmtCmdItemStatus(item))
        case "-run":
            if (ParseBoolInt(item.Forbid) || GetItemFoldForbidState(tableItem, n))
                return RmtCmdFail("该宏已禁用")
            TriggerMacroHandler(tableItem, n)
        case "-kill":
            MyStopMacro(tableItem, n)
        case "-pause":
            SetItemPauseState(tableItem, n, 1)
        case "-resume":
            SetItemPauseState(tableItem, n, 0)
    }
    return RmtCmdOk()
}

RmtCmdSetVar(args) {
    if (args.Length < 3)
        return RmtCmdFail("用法: rmt -set key value")
    key := Trim(args[2])
    if (key == "")
        return RmtCmdFail("变量名不能为空")
    SetGlobalVariable([key], [RmtCmdTail(args, 3)], false)
    return RmtCmdOk()
}

RmtCmdGetVar(args) {
    global MySoftData
    if (args.Length < 2 || Trim(args[2]) == "")
        return RmtCmdFail("用法: rmt -get key")
    key := Trim(args[2])
    if (!IsObject(MySoftData) || !MySoftData.VariableMap.Has(key))
        return RmtCmdFail("变量不存在: " key)
    return RmtCmdOk(RmtCmdSafeStr(MySoftData.VariableMap[key]))
}

RmtCmdSetArr(args) {
    if (args.Length < 3)
        return RmtCmdFail("用法: rmt -setarr key [1,2,3]")
    key := Trim(args[2])
    if (key == "")
        return RmtCmdFail("数组名不能为空")
    try arr := RmtCmdParseArray(RmtCmdTail(args, 3))
    catch
        return RmtCmdFail("数组格式错误，应为 [1,2,3]")
    SetGlobalArray(key, arr)
    return RmtCmdOk()
}

RmtCmdGetArr(args) {
    global MySoftData
    if (args.Length < 2 || Trim(args[2]) == "")
        return RmtCmdFail("用法: rmt -getarr key")
    key := Trim(args[2])
    if (!IsObject(MySoftData) || !MySoftData.ArrayMap.Has(key))
        return RmtCmdFail("数组不存在: " key)
    return RmtCmdOk(RmtCmdFormatArray(MySoftData.ArrayMap[key]))
}

; 外层方括号只表示「这是数组」。内部格式沿用软件自己的数组文本。
RmtCmdParseArray(text) {
    text := Trim(text)
    if (StrLen(text) >= 2) {
        open := SubStr(text, 1, 1)
        close := SubStr(text, -1)
        wrapped := (open = "[" && close = "]") || (open = "【" && close = "】")
        if (wrapped && GetArrayEndPos(text, 0) == StrLen(text))
            text := SubStr(text, 2, StrLen(text) - 2)
    }
    arr := GetArray(text)
    RmtCmdTrimArray(arr)
    return arr
}

RmtCmdTrimArray(arr) {
    if !(arr is Array)
        return
    loop arr.Length {
        value := arr[A_Index]
        if (value is Array)
            RmtCmdTrimArray(value)
        else
            arr[A_Index] := Trim(String(value))
    }
}

RmtCmdFormatArray(arr) {
    if !(arr is Array)
        return "[]"
    return "[" GetArrayStr(arr) "]"
}

RmtCmdHelpText() {
    return "若梦兔命令行`n"
        . "环境变量 rmt 为程序路径。重新打开终端后，可在任意目录使用 rmt。`n"
        . "`n"
        . "rmt -help                  显示所有指令及作用`n"
        . "rmt -min                   后台运行，不打开主界面`n"
        . "rmt -run m-n               启动第 m 页签的第 n 个宏`n"
        . "rmt -kill m-n              终止第 m 页签的第 n 个宏`n"
        . "rmt -killall               终止所有宏`n"
        . "rmt -pause m-n             暂停第 m 页签的第 n 个宏`n"
        . "rmt -resume m-n            继续第 m 页签的第 n 个宏`n"
        . "rmt -pauseall              暂停所有宏`n"
        . "rmt -resumeall             继续所有宏`n"
        . "rmt -set key value         设置全局变量，没有则新增`n"
        . "rmt -get key               获取全局变量，结果为字符串`n"
        . "rmt -setarr key [1,2,3,4]  设置数组变量`n"
        . "rmt -getarr key            获取数组，例如 [1,2,3,4]`n"
        . "rmt -status m-n            查询宏状态：0 闲置，1 正在运行，2 暂停中`n"
        . "`n"
        . "m、n 从 1 开始。成功时退出码为 0，结果写在标准输出。"
}

; ---------- 标准输出 ----------

RmtCmdEmit(text, code := 0) {
    RmtCmdWriteOut(text)
    RmtCmdWaitOwnConsole()
    ExitApp(code)
}

RmtCmdWriteOut(text) {
    global RMT_CmdOwnConsole
    if (text == "")
        return
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`n", "`r`n")
    if (SubStr(text, -1) != "`n")
        text .= "`r`n"
    if (RmtCmdWriteStd(text))
        return
    if (DllCall("kernel32\AttachConsole", "UInt", 0xFFFFFFFF) && RmtCmdWriteConsole(text))
        return
    if (DllCall("kernel32\AllocConsole")) {
        RMT_CmdOwnConsole := true
        RmtCmdWriteConsole(text)
    }
}

RmtCmdWriteStd(text) {
    h := DllCall("kernel32\GetStdHandle", "Int", -11, "Ptr")
    if (!h || h = -1)
        return false
    kind := DllCall("kernel32\GetFileType", "Ptr", h, "UInt") & 0xFFFF
    if (kind = 2)
        return RmtCmdWriteConsoleHandle(h, text)
    if (kind = 1 || kind = 3)
        return RmtCmdWriteFileUtf8(h, text)
    return false
}

RmtCmdWriteConsole(text) {
    h := DllCall("kernel32\CreateFileW", "WStr", "CONOUT$", "UInt", 0x40000000, "UInt", 3, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
    if (!h || h = -1)
        return false
    ok := RmtCmdWriteConsoleHandle(h, text)
    DllCall("kernel32\CloseHandle", "Ptr", h)
    return ok
}

RmtCmdWriteConsoleHandle(h, text) {
    written := 0
    return DllCall("kernel32\WriteConsoleW", "Ptr", h, "WStr", text, "UInt", StrLen(text), "UInt*", &written, "Ptr", 0)
}

RmtCmdWriteFileUtf8(h, text) {
    n := StrPut(text, "UTF-8")
    if (n <= 1)
        return true
    buf := Buffer(n, 0)
    StrPut(text, buf, "UTF-8")
    written := 0
    return DllCall("kernel32\WriteFile", "Ptr", h, "Ptr", buf, "UInt", n - 1, "UInt*", &written, "Ptr", 0)
}

RmtCmdWaitOwnConsole() {
    global RMT_CmdOwnConsole
    if (!RMT_CmdOwnConsole)
        return
    RmtCmdWriteConsole("按任意键关闭...`r`n")
    hIn := DllCall("kernel32\CreateFileW", "WStr", "CONIN$", "UInt", 0x80000000, "UInt", 3, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
    if (!hIn || hIn = -1)
        return
    buf := Buffer(8, 0)
    read := 0
    DllCall("kernel32\ReadConsoleW", "Ptr", hIn, "Ptr", buf, "UInt", 1, "UInt*", &read, "Ptr", 0)
    DllCall("kernel32\CloseHandle", "Ptr", hIn)
}

; ---------- 环境变量 rmt 与 rmt 命令 ----------

RmtRegisterCliCommand() {
    try {
        userDir := A_AppData "\RMT"
        userCmd := RmtCmdInstallLauncher(userDir)
        target := A_IsCompiled ? A_ScriptFullPath : userCmd
        changed := false
        if (RmtSetEnvString("HKCU\Environment", "rmt", target))
            changed := true
        if (RmtAppendEnvPath("HKCU\Environment", userDir))
            changed := true
        if (A_IsCompiled && RmtProcessIsElevated()) {
            sysKey := "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
            sysDir := EnvGet("ProgramData") "\RMT"
            if (sysDir != "\RMT")
                RmtCmdInstallLauncher(sysDir)
            if (RmtSetEnvString(sysKey, "rmt", target))
                changed := true
            if (sysDir != "\RMT" && RmtAppendEnvPath(sysKey, sysDir))
                changed := true
        }
        if (changed)
            RmtBroadcastEnvChange()
    } catch {
    }
}

RmtProcessIsElevated() {
    hToken := 0
    if !DllCall("advapi32\OpenProcessToken", "Ptr", DllCall("kernel32\GetCurrentProcess", "Ptr"), "UInt", 0x0008, "Ptr*", &hToken)
        return false
    elev := 0
    retLen := 0
    ok := DllCall("advapi32\GetTokenInformation", "Ptr", hToken, "Int", 20, "UInt*", &elev, "UInt", 4, "UInt*", &retLen)
    DllCall("kernel32\CloseHandle", "Ptr", hToken)
    return ok && (elev != 0)
}

RmtCmdInstallLauncher(dir) {
    if (!DirExist(dir))
        DirCreate(dir)
    path := dir "\rmt.cmd"
    text := RmtCmdLauncherText()
    old := ""
    if (FileExist(path)) {
        try old := FileRead(path, "UTF-8")
    }
    if (old != text) {
        try FileDelete(path)
        FileAppend(text, path, "UTF-8")
    }
    return path
}

RmtCmdLauncherText() {
    cp := "for /f `"tokens=2 delims=:`" %%P in ('chcp') do set `"RMT_CP=%%P`"`r`n"
        . "set `"RMT_CP=%RMT_CP: =%`"`r`n"
        . "chcp 65001 >nul`r`n"
    tail := "set `"RMT_EC=%ERRORLEVEL%`"`r`n"
        . "if exist `"%RMT_OUT%`" type `"%RMT_OUT%`"`r`n"
        . "del /q `"%RMT_OUT%`" 2>nul`r`n"
        . "if defined RMT_CP chcp %RMT_CP% >nul`r`n"
        . "exit /b %RMT_EC%`r`n"
    if (A_IsCompiled) {
        exe := A_ScriptFullPath
        return "@echo off`r`nsetlocal EnableExtensions`r`n"
            . cp
            . "set `"RMT_EXE=" . exe . "`"`r`n"
            . "if /I `"%~1`"==`"-min`" if `"%~2`"==`"`" (`r`n"
            . "    start `"`" `"%RMT_EXE%`" -min`r`n"
            . "    if defined RMT_CP chcp %RMT_CP% >nul`r`n"
            . "    exit /b 0`r`n"
            . ")`r`n"
            . "set `"RMT_OUT=%TEMP%\RMT_cli_%RANDOM%%RANDOM%.txt`"`r`n"
            . "`"%RMT_EXE%`" %* > `"%RMT_OUT%`"`r`n"
            . tail
    }
    return "@echo off`r`nsetlocal EnableExtensions`r`n"
        . cp
        . "set `"RMT_HOST=" . A_AhkPath . "`"`r`n"
        . "set `"RMT_SCRIPT=" . A_ScriptFullPath . "`"`r`n"
        . "if /I `"%~1`"==`"-min`" if `"%~2`"==`"`" (`r`n"
        . "    start `"`" `"%RMT_HOST%`" `"%RMT_SCRIPT%`" -min`r`n"
        . "    if defined RMT_CP chcp %RMT_CP% >nul`r`n"
        . "    exit /b 0`r`n"
        . ")`r`n"
        . "set `"RMT_OUT=%TEMP%\RMT_cli_%RANDOM%%RANDOM%.txt`"`r`n"
        . "`"%RMT_HOST%`" `"%RMT_SCRIPT%`" %* > `"%RMT_OUT%`"`r`n"
        . tail
}

RmtCmdPathAdd(pathValue, dir) {
    dir := RTrim(dir, "\/")
    if (dir == "")
        return pathValue
    parts := StrSplit(pathValue, ";")
    for part in parts {
        raw := RTrim(Trim(part), "\/")
        if (raw == "")
            continue
        expanded := RTrim(RmtExpandEnv(raw), "\/")
        if (StrLower(raw) = StrLower(dir) || StrLower(expanded) = StrLower(dir))
            return pathValue
    }
    pathValue := RTrim(pathValue, "; ")
    if (pathValue == "")
        return dir
    return pathValue ";" dir
}

RmtExpandEnv(text) {
    need := DllCall("kernel32\ExpandEnvironmentStringsW", "WStr", text, "Ptr", 0, "UInt", 0)
    if (need <= 1)
        return text
    buf := Buffer(need * 2, 0)
    DllCall("kernel32\ExpandEnvironmentStringsW", "WStr", text, "Ptr", buf, "UInt", need)
    return StrGet(buf, "UTF-16")
}

RmtAppendEnvPath(key, dir) {
    dir := RTrim(dir, "\/")
    if (dir == "")
        return false
    value := ""
    type := 1
    if (!RmtRegReadValue(key, "Path", &value, &type)) {
        value := ""
        type := 2
    }
    if (type != 1 && type != 2)
        type := 1
    next := RmtCmdPathAdd(value, dir)
    if (next = value)
        return false
    return RmtRegWriteString(key, "Path", next, type)
}

RmtSetEnvString(key, name, value) {
    old := ""
    type := 1
    if (RmtRegReadValue(key, name, &old, &type) && old = value)
        return false
    return RmtRegWriteString(key, name, value, 1)
}

RmtRegOpenKey(path, &hKey, access) {
    hKey := 0
    hive := 0x80000001
    sub := path
    if (SubStr(path, 1, 5) = "HKLM\") {
        hive := 0x80000002
        sub := SubStr(path, 6)
    } else if (SubStr(path, 1, 5) = "HKCU\") {
        hive := 0x80000001
        sub := SubStr(path, 6)
    }
    err := DllCall("advapi32\RegOpenKeyExW", "Ptr", hive, "WStr", sub, "UInt", 0, "UInt", access, "Ptr*", &hKey)
    return err = 0 && hKey
}

RmtRegReadValue(path, name, &value, &type) {
    value := ""
    type := 0
    if (!RmtRegOpenKey(path, &hKey, 0x20019))
        return false
    size := 0
    typ := 0
    DllCall("advapi32\RegQueryValueExW", "Ptr", hKey, "WStr", name, "Ptr", 0, "UInt*", &typ, "Ptr", 0, "UInt*", &size)
    if (size <= 0) {
        DllCall("advapi32\RegCloseKey", "Ptr", hKey)
        return false
    }
    buf := Buffer(size + 4, 0)
    err := DllCall("advapi32\RegQueryValueExW", "Ptr", hKey, "WStr", name, "Ptr", 0, "UInt*", &typ, "Ptr", buf, "UInt*", &size)
    DllCall("advapi32\RegCloseKey", "Ptr", hKey)
    if (err != 0)
        return false
    type := typ
    if (typ = 1 || typ = 2)
        value := StrGet(buf, "UTF-16")
    return true
}

RmtRegWriteString(path, name, value, type) {
    if (!RmtRegOpenKey(path, &hKey, 0x0002))
        return false
    cb := (StrLen(value) + 1) * 2
    err := DllCall("advapi32\RegSetValueExW", "Ptr", hKey, "WStr", name, "UInt", 0, "UInt", type, "WStr", value, "UInt", cb)
    DllCall("advapi32\RegCloseKey", "Ptr", hKey)
    return err = 0
}

RmtRegDeleteValue(path, name) {
    if (!RmtRegOpenKey(path, &hKey, 0x0002))
        return false
    err := DllCall("advapi32\RegDeleteValueW", "Ptr", hKey, "WStr", name)
    DllCall("advapi32\RegCloseKey", "Ptr", hKey)
    return err = 0
}

RmtBroadcastEnvChange() {
    r := 0
    DllCall("user32\SendMessageTimeoutW", "Ptr", 0xFFFF, "UInt", 0x001A, "Ptr", 0, "Ptr", StrPtr("Environment"), "UInt", 0x0002, "UInt", 5000, "Ptr*", &r)
}
