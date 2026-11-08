; 手柄按键输出诊断日志（排查：宏内 Joy 按键不生效）
; 归口统一日志（C 项）：debug 级（默认不写，设置页开启 Debug 后生效）
JoyDebugLog(msg, tag := "joy") {
    who := ProcessTag()
    RMTLogSys(RMT_LV_DEBUG, who, "[" tag "] " msg)
}

; 手柄/手柄检测自动勾选：立即落盘 Log\JoyPicker.log（闪退时看最后一行）
JoyPickerLog(msg) {
    try {
        logDir := A_WorkingDir "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " +" A_TickCount " " msg "`n", logDir "\JoyPicker.log", "UTF-8")
    }
}

JoyPickerLogReset() {
    try {
        logDir := A_WorkingDir "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        path := logDir "\JoyPicker.log"
        if FileExist(path) {
            sz := 0
            try sz := FileGetSize(path)
            if (IsNumber(sz) && Integer(sz) > 1048576)
                try FileDelete(path)
        }
        JoyPickerLog("==== session start pid=" DllCall("GetCurrentProcessId") " ====")
    }
}

; 抓图指令诊断日志（排查：抓图后 Images\TempShot 下没有生成 Shot.png）
; 输出：主进程 A_WorkingDir\Log\ShotDebug.log；Worker 写到 A_ScriptDir\..\Log\ShotDebug.log
ShotDebugLog(msg, tag := "shot") {
    try {
        logDir := CMDLogAppDir() "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        who := ProcessTag()
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " +" A_TickCount " [" who "/" tag "] " msg "`n"
            , logDir "\ShotDebug.log", "UTF-8")
    }
}

; 搜索指令诊断日志（排查：搜索无结果、真/假分支都不执行）
; 输出：主进程 A_WorkingDir\Log\SearchDebug.log；Worker 写到 A_ScriptDir\..\Log\SearchDebug.log
SearchDebugLog(msg, tag := "search") {
    try {
        logDir := CMDLogAppDir() "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        who := ProcessTag()
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " +" A_TickCount " [" who "/" tag "] " msg "`n"
            , logDir "\SearchDebug.log", "UTF-8")
    }
}
