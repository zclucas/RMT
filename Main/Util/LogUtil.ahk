#Requires AutoHotkey v2.0

; =====================================================================
; RMT 统一日志（C 项：统一日志系统 + 错误分级）
; 两个日志文件：System.log（系统运行/错误）+ Business.log（宏运行流水）
; 行格式统一（两文件相同）：
;   [来源] [pid] [时间戳] [级别] 消息
;   来源：Master / Worker#N / Engine / DLL / Plugin / 宏
;   pid：进程标识（同一进程所有日志同 pid，可关联成一组运行）
;   级别：[debug]/[info]/[warn]/[error]
; 特性：
;   - 内存缓冲 + SetTimer 异步刷新（不阻塞按键/消息处理，同 GraphPoolLog 模式）
;   - 每文件超 2MB 自动轮转改名 .old 重建
;   - Worker 写 A_ScriptDir\..\Log\；主进程写 A_WorkingDir\Log\
;   - 业务日志受总开关控制（默认关，防量爆炸）
;   - 系统 debug 级默认不写（设置页可调最低级别）
; 使用：
;   RMTLogSys("info", "Master", "配置加载完成")
;   RMTLogSysError("Worker#2", "宏执行异常: ...")
;   RMTLogBusiness("宏", "tab1 item3 指令: 按键_a")
; =====================================================================

; ---------------- 级别常量 ----------------
global RMT_LV_DEBUG := "debug"
global RMT_LV_INFO  := "info"
global RMT_LV_WARN  := "warn"
global RMT_LV_ERROR := "error"

; ---------------- 内部状态 ----------------
global _rmtLogSysBuffer := ""
global _rmtLogBizBuffer := ""
global _rmtLogSysPath := ""
global _rmtLogBizPath := ""
global _rmtLogInitialized := false

; 业务日志总开关（默认关；由设置页"日志与错误"分组控制，见设计文档阶段5）
global RMTLogBusinessEnabled := false

; 系统日志最低级别（默认 info：debug 级不写；设置页可调）
global RMTLogSysMinLevel := RMT_LV_INFO

; 日志刷新周期（毫秒）：内存缓冲攒够此间隔落盘一次。
; 原 5000 → 1000：日志中心打开时轮询 1s 兜底，缩短日志可见延迟（最坏 ~2s）
global RMTLogFlushInterval := 1000

; 写入即通知：日志中心注册回调，日志写入后异步触发（主进程 System/Business 即时可见）
global _rmtLogNotifyCb := 0
RMTLogSetNotify(cb) {
    global _rmtLogNotifyCb
    _rmtLogNotifyCb := cb
}
RMTLogClearNotify() {
    global _rmtLogNotifyCb
    _rmtLogNotifyCb := 0
}
_rmtLogNotify() {
    global _rmtLogNotifyCb
    if (_rmtLogNotifyCb)
        SetTimer(_rmtLogNotifyCb, -1)   ; 异步触发，不阻塞写入路径
}

RMTLogDir() {
    return CMDLogAppDir() "\Log"
}

; ---------------- 指令显示日志路径 ----------------
; 配置里存的是目录（空 = 软件所在目录\Log），不是某一次浏览得到的绝对路径。
; 软件文件夹挪走之后，空值和下一次仍落在旧安装目录里的 Log 会自动改到当前软件目录。

; 软件根目录由入口文件给出（主进程 GlobalUtil / Worker Thread\WorkGlobalUtil），
; 这里只读，不再按角色拼 A_ScriptDir\..。
CMDLogAppDir() {
    if (IsSet(AppRootDir) && AppRootDir != "")
        return AppRootDir
    return RTrim(A_WorkingDir != "" ? A_WorkingDir : A_ScriptDir, "\")
}

CMDLogNorm(p) {
    p := Trim(StrReplace(String(p), "/", "\"))
    while (InStr(p, "\\"))
        p := StrReplace(p, "\\", "\")
    return RTrim(p, "\")
}

CMDLogIsAbs(p) {
    return RegExMatch(p, "^[A-Za-z]:\\") || SubStr(p, 1, 2) == "\\"
}

CMDLogIsUnder(path, root) {
    p := StrLower(CMDLogNorm(path))
    r := StrLower(CMDLogNorm(root))
    if (p == "" || r == "")
        return false
    return p == r || InStr(p, r "\") == 1
}

CMDLogDirPrefix() {
    return GetLang("软件所在目录")
}

; 用户在输入框里看到的文字 → 配置里保存的值（空 = 默认 Log 目录）
CMDLogStoreFromUserText(text) {
    t := CMDLogNorm(text)
    prefix := CMDLogDirPrefix()
    if (t == "" || t == prefix || t == prefix "\Log" || t == "软件所在目录" || t == "软件所在目录\Log" || t == ".\Log" || StrLower(t) == "log")
        return ""
    lowT := StrLower(t)
    lowP := StrLower(prefix)
    if (lowP != "" && InStr(lowT, lowP "\") == 1)
        t := SubStr(t, StrLen(prefix) + 2)
    else if (InStr(lowT, "软件所在目录\") == 1)
        t := SubStr(t, StrLen("软件所在目录") + 2)
    return CMDLogCalibrateStored(t)
}

CMDLogPathDisplay(stored) {
    s := CMDLogCalibrateStored(stored)
    if (s == "")
        return CMDLogDirPrefix() "\Log"
    if (CMDLogIsAbs(s))
        return s
    return CMDLogDirPrefix() "\" s
}

; 实际写入的日志文件。目录配置补上 CMDLog.txt；用户另选的 .log/.txt 文件保持原样。
CMDLogResolveFile(stored) {
    s := CMDLogCalibrateStored(stored)
    if (s == "")
        return CMDLogAppDir() "\Log\CMDLog.txt"
    full := CMDLogIsAbs(s) ? s : (CMDLogAppDir() "\" s)
    SplitPath(full, , , &ext)
    ext := StrLower(ext)
    if (ext == "log" || ext == "txt")
        return full
    return full "\CMDLog.txt"
}

CMDLogResolveDir(stored) {
    file := CMDLogResolveFile(stored)
    SplitPath(file, &name, &dir, &ext)
    ext := StrLower(ext)
    if (ext == "log" || ext == "txt")
        return dir
    return file
}

CMDLogCalibrateStored(stored) {
    s := CMDLogNorm(stored)
    if (s == "" || s == "." || s == ".\Log" || StrLower(s) == "log")
        return ""
    ; 旧版把目录存成「目录\CMDLog.txt」
    if (StrLen(s) > 11 && SubStr(StrLower(s), -10) == "cmdlog.txt" && SubStr(s, -11, 1) == "\")
        s := RTrim(SubStr(s, 1, StrLen(s) - 11), "\")
    if (s == "" || StrLower(s) == "log")
        return ""

    app := CMDLogAppDir()
    full := CMDLogIsAbs(s) ? s : (app "\" s)
    full := CMDLogNorm(full)
    if (CMDLogIsUnder(full, app)) {
        rel := SubStr(full, StrLen(CMDLogNorm(app)) + 2)
        if (rel == "" || StrLower(rel) == "log")
            return ""
        return rel
    }

    moved := CMDLogMovedInstallRel(full)
    if (moved != "")
        return (StrLower(moved) == "log") ? "" : moved
    return CMDLogIsAbs(s) ? full : s
}

; 旧安装目录下的 Log（文件夹已挪走，或旁边还留着一份旧的 RMT）→ 相对当前软件目录的尾巴
CMDLogMovedInstallRel(abs) {
    low := StrLower(CMDLogNorm(abs))
    app := StrLower(CMDLogAppDir())
    pos := 1
    while (pos := InStr(low, "\log", , pos)) {
        root := SubStr(abs, 1, pos - 1)
        rest := SubStr(abs, pos + 1)
        restLow := StrLower(rest)
        pos += 4
        if (restLow != "log" && InStr(restLow, "log\") != 1)
            continue
        rootNorm := StrLower(CMDLogNorm(root))
        if (rootNorm == "" || rootNorm == app || CMDLogIsUnder(root, CMDLogAppDir()) || CMDLogIsUnder(CMDLogAppDir(), root))
            continue
        if (DirExist(root) && !DirExist(root "\Setting") && !FileExist(root "\RMT.exe") && !FileExist(root "\RMT.ahk"))
            continue
        return rest
    }
    return ""
}

; 按日志文件的修改时间清理。每天 = 不是今天写的就删；每周 = 不是本周写的就删。
; 旧实现只清空屏幕上的指令，而且把「上次清理」记成今天、只放在内存里，重启后永远不会再清。
CMDLogTryAutoClear(filePath, mode) {
    if (!IsNumber(mode))
        return false
    mode := Integer(mode)
    if (mode != 1 && mode != 2)
        return false
    if (filePath == "" || !FileExist(filePath))
        return false
    try fileTime := FileGetTime(filePath)
    catch
        return false
    due := false
    if (mode == 1)
        due := SubStr(fileTime, 1, 8) != SubStr(A_Now, 1, 8)
    else
        due := CMDLogWeekKey(fileTime) != CMDLogWeekKey(A_Now)
    if (!due)
        return false
    try FileDelete(filePath)
    catch {
        try {
            f := FileOpen(filePath, "w", "UTF-8")
            if IsObject(f)
                f.Close()
        }
    }
    return !FileExist(filePath) || (FileExist(filePath) && FileGetSize(filePath) == 0)
}

; 以周一为界的周序号。用完整时间戳，避免只拿 yyyyMMdd 去 FormatTime 时对不上周。
CMDLogWeekKey(ts) {
    ts := String(ts)
    if (StrLen(ts) < 8)
        return ts
    day := SubStr(ts, 1, 8) "000000"
    try
        return "W" Floor(DateDiff(day, "19700105000000", "Days") / 7)
    catch
        return SubStr(ts, 1, 8)
}

; 进程 PID（缓存，AHK v2 无 A_PID 内置；用于日志线程标识——同一进程所有日志同 pid）
global _rmtLogPid := 0
RMTLogPid() {
    global _rmtLogPid
    if (!_rmtLogPid)
        _rmtLogPid := DllCall("GetCurrentProcessId")
    return _rmtLogPid
}

; ---------------- 主入口：系统日志 ----------------
RMTLogSys(level, source, msg) {
    global _rmtLogSysBuffer, _rmtLogSysPath, _rmtLogInitialized
    global RMTLogSysMinLevel

    ; debug 级且当前最低级别非 debug 时跳过
    if (level == RMT_LV_DEBUG && RMTLogSysMinLevel != RMT_LV_DEBUG)
        return

    if (!_rmtLogInitialized) {
        _rmtLogSysPath := RMTLogDir() "\System.log"
        _rmtLogInitialized := true
        SetTimer(FlushRMTLogAsync, RMTLogFlushInterval)  ; 周期异步刷新
    }

    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    _rmtLogSysBuffer .= "[" source "] [" RMTLogPid() "] [" ts "] [" level "] " msg "`n"

    if (StrLen(_rmtLogSysBuffer) >= 1024 * 50)
        SetTimer(FlushRMTLogAsync, -1)
    _rmtLogNotify()   ; 写入即通知（日志中心即时刷新）
}

; ---------------- 主入口：业务日志 ----------------
RMTLogBusiness(source, msg) {
    global _rmtLogBizBuffer, _rmtLogBizPath, _rmtLogInitialized
    global RMTLogBusinessEnabled

    if (!RMTLogBusinessEnabled)
        return

    if (!_rmtLogInitialized) {
        _rmtLogBizPath := RMTLogDir() "\Business.log"
        _rmtLogInitialized := true
        SetTimer(FlushRMTLogAsync, RMTLogFlushInterval)
    }

    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    _rmtLogBizBuffer .= "[" source "] [" RMTLogPid() "] [" ts "] [info] " msg "`n"

    if (StrLen(_rmtLogBizBuffer) >= 1024 * 50)
        SetTimer(FlushRMTLogAsync, -1)
    _rmtLogNotify()   ; 写入即通知（日志中心即时刷新）
}

FlushRMTLogAsync() {
    global _rmtLogSysBuffer, _rmtLogBizBuffer, _rmtLogSysPath, _rmtLogBizPath, _rmtLogInitialized

    if (!_rmtLogInitialized)
        return

    if (_rmtLogSysBuffer != "") {
        buffer := _rmtLogSysBuffer
        _rmtLogSysBuffer := ""
        _AppendLogRotate(_rmtLogSysPath, buffer)
    }
    if (_rmtLogBizBuffer != "") {
        buffer := _rmtLogBizBuffer
        _rmtLogBizBuffer := ""
        _AppendLogRotate(_rmtLogBizPath, buffer)
    }
}

; 追加写入 + 轮转（超 2MB 改名 .old 重建）
_AppendLogRotate(path, buffer) {
    if (path == "")
        return
    try {
        SplitPath(path, , &logDir)
        if !DirExist(logDir)
            DirCreate(logDir)
        if (FileExist(path) && FileGetSize(path) >= 2 * 1024 * 1024) {
            FileMove(path, path ".old", 1)
        }
        FileAppend(buffer, path, "UTF-8")
    }
}

; ---------------- 便捷封装：系统日志 ----------------
RMTLogSysDebug(source, msg) {
    RMTLogSys(RMT_LV_DEBUG, source, msg)
}
RMTLogSysInfo(source, msg) {
    RMTLogSys(RMT_LV_INFO, source, msg)
}
RMTLogSysWarn(source, msg) {
    RMTLogSys(RMT_LV_WARN, source, msg)
}
RMTLogSysError(source, msg) {
    RMTLogSys(RMT_LV_ERROR, source, msg)
}

; ---------------- 指令错误处理（阶段5 接入） ----------------
; 指令错误处理配置：{mode: "stop"/"ignore"/"retry", retryCount, retryInterval}
; 默认：停止运行（用户需显式配置"忽略"或"重试"才会继续）
; 存储：指令字符串尾部追加 `|EH:<mode>[;<count>;<interval>]`（影刀模式，每条指令独立配置）
;   例：间隔_500|EH:stop           （默认，也可省略）
;       间隔_500|EH:ignore
;       间隔_500|EH:retry;3;500    （重试3次，间隔500ms；耗尽仍失败→停止）
; 说明：EH 段不参与指令参数解析（_ 分隔），各编辑器/执行处先经 RMTParseErrHandle 剥离
RMTGetErrorHandle(cmdType) {
    ; 无 EH 段的指令兜底：停止运行（保持旧行为）
    return { mode: "stop", retryCount: 3, retryInterval: 500 }
}

; 解析指令字符串中的 EH 段
; 返回 { cmd: 剥离后的纯指令, cfg: {mode,...} | "" }
RMTParseErrHandle(cmdStr) {
    if (!(pos := InStr(cmdStr, "|EH:")))
        return { cmd: cmdStr, cfg: "" }

    cleanCmd := SubStr(cmdStr, 1, pos - 1)
    ehStr := SubStr(cmdStr, pos + 4)
    parts := StrSplit(ehStr, ";")
    mode := parts[1]

    if (mode == "retry") {
        cfg := { mode: "retry"
            , retryCount: parts.Length >= 2 ? Integer(parts[2]) : 3
            , retryInterval: parts.Length >= 3 ? Integer(parts[3]) : 500 }
    } else {
        cfg := { mode: mode }
    }

    return { cmd: cleanCmd, cfg: cfg }
}

; 构建 EH 段后缀（cfg 为 "" 或 mode=stop 时不追加）
RMTBuildErrHandleSuffix(cfg) {
    if (!IsObject(cfg) || cfg.mode == "stop")
        return ""
    if (cfg.mode == "ignore")
        return "|EH:ignore"
    return "|EH:retry;" cfg.retryCount ";" cfg.retryInterval
}

; 指令错误统一处理（ExecuteMacroCmdOnce catch 接入）
; err: 异常对象；cmdType: 指令类型（如 "间隔"）；ehCfg: 指令自带配置（无则用 RMTGetErrorHandle）
; execFunc: 重试时的重新执行闭包（仅 retry 用）
; 返回 [continue, result]：continue=false 表示应终止当前宏（调用方负责 KillTableItemMacro）
RMTHandleError(err, cmdType, ehCfg := "", execFunc := 0) {
    cfg := IsObject(ehCfg) ? ehCfg : RMTGetErrorHandle(cmdType)
    errMsg := IsObject(err) && err.HasProp("Message") ? err.Message : String(err)
    switch cfg.mode {
        case "ignore":
            RMTErrorShow(Format("[{1}] {2}", cmdType, errMsg), RMT_LV_WARN, "宏")
            return [true, ""]
        case "retry":
            loop cfg.retryCount {
                Sleep(cfg.retryInterval)
                try {
                    r := execFunc()
                    return [true, r]
                } catch as re {
                    errMsg := IsObject(re) && re.HasProp("Message") ? re.Message : String(re)
                }
            }
            RMTErrorShow(Format("[{1}] 重试{2}次仍失败: {3}", cmdType, cfg.retryCount, errMsg), RMT_LV_ERROR, "宏")
            return [false, ""]
        default: ; stop
            RMTErrorShow(Format("[{1}] {2}", cmdType, errMsg), RMT_LV_ERROR, "宏")
            return [false, ""]
    }
}