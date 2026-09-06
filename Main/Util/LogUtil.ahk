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
    isWorker := IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker
    return isWorker ? (A_ScriptDir "\..\Log") : (A_WorkingDir "\Log")
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

; ---------------- 错误统一展示（宏内业务错误） ----------------
; 替代裸 MsgBox：Worker 环境经 ER 通道上报主进程（不阻塞宏、不本地写日志）；
; 主进程环境走错误中心 + 写系统日志（一次错误一条日志）。
; 返回 true 表示已处理（调用方无需再弹窗）。
RMTErrorShow(msg, level := RMT_LV_ERROR, source := "") {
    if (source == "")
        source := (IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker) ? ("Worker#" workIndex) : "Master"

    if (IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker) {
        ; Worker：仅 ER 上报主进程（主进程统一记录日志 + 聚合，避免双写）
        if (IsSet(MsgSendHandler))
            MsgSendHandler("Error", level "|" workIndex "|" msg)
        return true
    }

    ; 主进程：写系统日志（不模态弹窗）+ 按级别通知（warn 气泡 / error 错误中心，均可开关）
    RMTLogSys(level, source, msg)
    if (level == RMT_LV_WARN) {
        ; warn：托盘气泡（2s 自动消失）
        if (!(IsSet(MainSoftData) && ObjHasOwnProp(MainSoftData, "LogWarnBubble") && !MainSoftData.LogWarnBubble)) {
            try TrayTip(Format("[{1}] {2}", source, msg), GetLang("RMT 警告"), 1)
            try SetTimer(() => TrayTip(), -2000)
        }
    } else if (level == RMT_LV_ERROR) {
        ; error：错误中心聚合
        if (IsSet(MyErrorMsgBoxGui) && IsObject(MyErrorMsgBoxGui)
            && !(IsSet(MainSoftData) && ObjHasOwnProp(MainSoftData, "LogErrorBadge") && !MainSoftData.LogErrorBadge))
            MyErrorMsgBoxGui.ShowGui(Format("[{1}] {2}", source, msg))
    }
    return true
}
