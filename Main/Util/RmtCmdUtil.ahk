#Requires AutoHotkey v2.0

; =================================================================
; RMT 命令行指令（§3）—— 文件命令队列 IPC
;
; 用法（配合系统 PATH 中的 rmt 命令，或直接调用 RMT 主程序）：
;   rmt -help                指令帮助
;   rmt -min                 后台运行（已有）
;   rmt -run m-n             启动第 m 页签第 n 个宏
;   rmt -kill m-n            终止指定宏
;   rmt -killall             终止所有宏
;   rmt -pause m-n           暂停指定宏
;   rmt -resume m-n          继续指定宏
;   rmt -pauseall            暂停所有宏
;   rmt -resumeall           继续所有宏
;   rmt -set key value       设置全局变量（不存在则新增）
;   rmt -get key             获取全局变量（字符串）
;   rmt -setarr key [1,2,3]  设置数组变量
;   rmt -getarr key          获取数组（字符串形式 [1,2,3]）
;   rmt -status m-n          查询宏状态（0 闲置 / 1 运行 / 2 暂停）
;
; 关键设计（文档 §3 评估）：
;   1. 单实例：脚本顶层 EnsureSingleInstance() 用命名互斥判定唯一实例；
;      二次启动携带参数时，把参数写入 A_Temp\RMT_CmdQueue\req_*.cmd 队列文件，
;      由运行中实例的空闲轮询（StartCmdQueueListener → RmtCmdPoll）读取执行，
;      避免 #SingleInstance 替换语义导致运行中的宏被终止。
;   2. 返回值：-get / -getarr / -status 由运行实例写 res_<reqId>.txt 结果文件，
;      调用进程轮询读取后输出到 stdout（GUI 无控制台时静默，可改读结果文件）。
;   3. 无参数重复启动（含提权切换 -elevated）：终止旧实例后接管，
;      对齐原 #SingleInstance Force 行为（提权切换时由 pid 文件定位旧实例）。
; =================================================================

global RMT_CmdMutex := 0
global RMT_CmdQueueDir := ""
global RMT_PidFile := ""

RmtCmdInitPaths() {
    global RMT_CmdQueueDir, RMT_PidFile
    RMT_CmdQueueDir := A_Temp "\RMT_CmdQueue"
    RMT_PidFile := A_Temp "\RMT_SingleInstance.pid"
}

; 创建/持有命名互斥；已有实例占用时返回 0（已存在则释放句柄）
RmtCreateMutex() {
    h := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 1, "Str", "Local\RMT_SingleInstance", "Ptr")
    if (!h)
        return 0
    err := DllCall("Kernel32\GetLastError", "UInt")
    if (err == 183) {    ; ERROR_ALREADY_EXISTS
        DllCall("Kernel32\CloseHandle", "Ptr", h)
        return 0
    }
    return h
}

; 单实例判定（RMT.ahk 顶层调用）：
;   唯一实例 → 持有互斥并返回 true（调用方随后启动监听）
;   已有实例 + 携带命令行参数（非 -elevated）→ 转发队列 + 取回结果 + 退出
;   已有实例 + 无参数 / -elevated → 终止旧实例后接管（对齐原 #SingleInstance Force，支持提权切换）
EnsureSingleInstance() {
    global RMT_CmdMutex
    RmtCmdInitPaths()
    if (!DirExist(RMT_CmdQueueDir))
        DirCreate(RMT_CmdQueueDir)

    mutex := RmtCreateMutex()
    if (mutex) {
        RMT_CmdMutex := mutex
        RmtWritePid()
        return true
    }

    ; 已有实例运行
    hasArgs := A_Args.Length > 0
    isElevatedArg := false
    if (hasArgs) {
        for a in A_Args {
            if (a == "-elevated") {
                isElevatedArg := true
                break
            }
        }
    }
    if (hasArgs && !isElevatedArg) {
        ; 命令行调用 → 转发给运行实例，需要返回值时轮询结果文件
        reqId := RmtCmdForward(A_Args)
        if (RmtCmdNeedsResult(A_Args)) {
            res := RmtCmdWaitResult(reqId, 6000)
            try FileAppend(res, "*")   ; stdout（GUI 无控制台时静默；调用方可读结果文件）
        }
        ExitApp(0)
    }

    ; 无参数 / 提权切换：终止旧实例后接管
    RmtKillOldInstance()
    mutex := RmtCreateMutex()
    if (mutex) {
        RMT_CmdMutex := mutex
        RmtWritePid()
        return true
    }
    return false
}

RmtWritePid() {
    global RMT_PidFile
    try FileAppend(ProcessExist(), RMT_PidFile, "UTF-8")
}

RmtReadPid() {
    global RMT_PidFile
    if (!FileExist(RMT_PidFile))
        return 0
    try {
        return Integer(Trim(FileRead(RMT_PidFile, "UTF-8")))
    }
    return 0
}

; 终止旧实例（读 pid 文件定位），随后重试获取互斥
RmtKillOldInstance() {
    oldPid := RmtReadPid()
    if (oldPid > 0 && oldPid != ProcessExist()) {
        try ProcessClose(oldPid)
        loop 200 {
            if (RmtCreateMutex())
                return
            Sleep(50)
        }
    }
}

; ---------- 命令队列（文件 IPC） ----------

; 转发参数到运行实例：写 req_<reqId>.cmd，返回 reqId
RmtCmdForward(args) {
    global RMT_CmdQueueDir
    reqId := Format("{}_q{}", A_Now, Random(1000, 99999))
    content := ""
    for a in args
        content .= a "⫶"
    content := RTrim(content, "⫶")
    FileAppend(content, RMT_CmdQueueDir "\req_" reqId ".cmd", "UTF-8")
    return reqId
}

; 该命令是否需要返回值（调用方等待结果文件）
RmtCmdNeedsResult(args) {
    if (args.Length < 1)
        return false
    return args[1] == "-get" || args[1] == "-getarr" || args[1] == "-status"
}

; 轮询等待结果文件（超时返回 ""）
RmtCmdWaitResult(reqId, timeoutMs) {
    global RMT_CmdQueueDir
    resFile := RMT_CmdQueueDir "\res_" reqId ".txt"
    end := A_TickCount + timeoutMs
    while (A_TickCount < end) {
        if (FileExist(resFile)) {
            try {
                res := FileRead(resFile, "UTF-8")
                FileDelete(resFile)
                return res
            }
        }
        Sleep(100)
    }
    return ""
}

; 启动监听：运行实例空闲轮询命令队列（RMT.ahk 启动完成后调用）
StartCmdQueueListener() {
    global RMT_CmdQueueDir
    RmtCmdInitPaths()
    if (!DirExist(RMT_CmdQueueDir))
        DirCreate(RMT_CmdQueueDir)
    SetTimer(RmtCmdPoll, 500)
}

RmtCmdPoll(*) {
    global RMT_CmdQueueDir
    if (!DirExist(RMT_CmdQueueDir))
        return
    loop files, RMT_CmdQueueDir "\req_*.cmd" {
        filePath := A_LoopFilePath
        SplitPath(filePath, , , , &nameNoExt)
        reqId := StrReplace(nameNoExt, "req_", "")
        try {
            content := FileRead(filePath, "UTF-8")
            args := StrSplit(content, "⫶")
            result := RmtCmdDispatch(args)
            if (result != "")
                FileAppend(result, RMT_CmdQueueDir "\res_" reqId ".txt", "UTF-8")
        } catch {
        }
        try FileDelete(filePath)
    }
}

; 执行首次启动携带的命令参数（无旧实例时，RMT.ahk 启动完成后调用）
RmtRunStartupCommands() {
    global MySoftData
    if (!IsObject(MySoftData) || !MySoftData.HasProp("StartupCmdArr") || MySoftData.StartupCmdArr.Length == 0)
        return
    args := MySoftData.StartupCmdArr
    MySoftData.StartupCmdArr := []
    result := RmtCmdDispatch(args)
    if (result != "") {
        try FileAppend(result, "*")
    }
}

; ---------- 命令解析执行（运行实例环境） ----------

; m-n 解析：-run 1-2 → m=1, n=2
RmtParseMN(str, &m, &n) {
    m := 0, n := 0
    parts := StrSplit(str, "-")
    if (parts.Length == 2 && IsNumber(parts[1]) && IsNumber(parts[2])) {
        m := Integer(parts[1])
        n := Integer(parts[2])
    }
}

; 按 m-n 取表与条目；非法返回 ""
RmtTableItemByMN(m, n, &tableItem) {
    global MySoftData
    tableItem := ""
    if (m < 1 || m > MySoftData.TableInfo.Length)
        return false
    tableItem := MySoftData.TableInfo[m]
    if (n < 1 || n > tableItem.Items.Length)
        return false
    return true
}

RmtCmdDispatch(args) {
    global MySoftData, MainSoftData
    if (args.Length < 1)
        return ""
    cmd := args[1]
    switch cmd {
        case "-help":
            MsgBox(RmtCmdHelpText(), GetLang("RMT 命令行帮助"))
            return ""
        case "-min":
            MainSoftData.IsMinStart := true
            return ""
        case "-run":
            if (args.Length >= 3) {
                RmtParseMN(args[2], &m, &n)
                if (RmtTableItemByMN(m, n, &tableItem))
                    TriggerMacroHandler(tableItem, n)
            }
            return ""
        case "-kill":
            if (args.Length >= 3) {
                RmtParseMN(args[2], &m, &n)
                if (RmtTableItemByMN(m, n, &tableItem))
                    MyStopMacro(tableItem, n)
            }
            return ""
        case "-killall":
            OnKillAllMacro()
            return ""
        case "-pause":
            if (args.Length >= 3) {
                RmtParseMN(args[2], &m, &n)
                if (RmtTableItemByMN(m, n, &tableItem))
                    SetItemPauseState(tableItem, n, 1)
            }
            return ""
        case "-resume":
            if (args.Length >= 3) {
                RmtParseMN(args[2], &m, &n)
                if (RmtTableItemByMN(m, n, &tableItem))
                    SetItemPauseState(tableItem, n, 0)
            }
            return ""
        case "-pauseall":
            SetPauseState(true)
            return ""
        case "-resumeall":
            SetPauseState(false)
            return ""
        case "-set":
            if (args.Length >= 3)
                SetGlobalVariable([args[2]], [args[3]], false)
            return ""
        case "-get":
            if (args.Length >= 2)
                return MySoftData.VariableMap.Has(args[2]) ? String(MySoftData.VariableMap[args[2]]) : ""
            return ""
        case "-setarr":
            if (args.Length >= 3)
                SetGlobalArray(args[2], GetArray(args[3]))
            return ""
        case "-getarr":
            if (args.Length >= 2 && MySoftData.ArrayMap.Has(args[2]))
                return GetArrayStr(MySoftData.ArrayMap[args[2]])
            return ""
        case "-status":
            if (args.Length >= 3) {
                RmtParseMN(args[2], &m, &n)
                if (RmtTableItemByMN(m, n, &tableItem)) {
                    item := tableItem.Items[n]
                    if (item.Pause)
                        return "2"
                    if (item.ColorState == 1)
                        return "1"
                    return "0"
                }
            }
            return ""
    }
    return ""
}

RmtCmdHelpText() {
    return "RMT 命令行指令`n"
        . "`n"
        . "-help          显示本帮助`n"
        . "-min           后台运行，不显示主界面`n"
        . "-run m-n       启动第 m 页签第 n 个宏`n"
        . "-kill m-n      终止第 m 页签第 n 个宏`n"
        . "-killall       终止所有宏`n"
        . "-pause m-n     暂停第 m 页签第 n 个宏`n"
        . "-resume m-n    继续第 m 页签第 n 个宏`n"
        . "-pauseall      暂停所有宏`n"
        . "-resumeall     继续所有宏`n"
        . "-set key value 设置全局变量（不存在则新增）`n"
        . "-get key       获取全局变量（字符串）`n"
        . "-setarr key [1,2,3]  设置数组变量`n"
        . "-getarr key    获取数组（字符串形式）`n"
        . "-status m-n    查询宏状态（0 闲置 / 1 运行 / 2 暂停）"
}
