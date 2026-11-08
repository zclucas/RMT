#Requires AutoHotkey v2.0
#Warn All, Off

; Worker 不加载任何界面：所有对话框请求都转给主进程渲染，本进程只发请求、等回执。
; 走项目已有的「输入 / 等待确认」通道（InputRequest → 主进程独立弹窗 → IBR 回传）。
; 宏卡在等人确认是预期行为，这里的超时只用于防止主进程消失时永久挂住。
class RmtDialog {
    ; 10 分钟：用户离开一会儿再回来处理也来得及
    static TimeoutMs := 600000

    static Info(msg, title := "", owner := 0) {
        ; 通知型：单向投递，不等回执
        try WorkMsgBoxContent(String(msg))
    }

    static Confirm(msg, title := "", owner := 0) {
        r := InputRequest("IB", "1", String(msg), "", "", "to=" RmtDialog.TimeoutMs)
        return IsObject(r) && r.Length >= 1 && r[1] == "true"
    }

    ; buttons：数组或 "|" 分隔字符串；返回按钮序号（关闭 / 超时返回 0）
    static Choose(msg, title := "", buttons := [], owner := 0) {
        opts := IsObject(buttons) ? buttons : StrSplit(String(buttons), "|")
        if (!opts.Length)
            return 0
        joined := ""
        for i, o in opts
            joined .= (i > 1 ? "," : "") String(o)
        r := InputRequest("IB", "5", String(msg), joined, String(opts[1]), "to=" RmtDialog.TimeoutMs)
        if (!IsObject(r) || !r.Length)
            return 0
        v := String(r[1])
        if (SubStr(v, 1, 4) == "sel:")
            v := SubStr(v, 5)
        for i, o in opts {
            if (String(o) == v)
                return i
        }
        return 0
    }
}

#Include "..\Main\Util\Gdip_All.ahk"
#Include "..\Main\Util\JsonUtil.ahk"
#Include "..\Gui\ImageProcessGui.ahk"

if (A_Args.Length >= 3 && A_Args[1] == "--sample-align-worker") {
    prefix := A_Args[2]
    requestPath := prefix ".request.json"
    resultPath := prefix ".result.json"
    resultTempPath := resultPath ".tmp"
    readyPath := prefix ".ready"
    stopPath := prefix ".stop"
    token := 0
    try {
        token := Gdip_Startup()
        if (!token)
            throw Error("GDI+ startup failed")
        editor := ImageProcessGui()
        editor.SampleMode := true
        editor._sampleWorkerRoot := A_ScriptDir "\.."
        editor._sampleEdgeCacheLimit := Max(0, Integer(A_Args[3]))
        FileAppend("ready", readyPath, "UTF-8")
        loop {
            if (FileExist(stopPath))
                break
            if (!FileExist(requestPath)) {
                Sleep(5)
                continue
            }

            request := JSON.parse(FileRead(requestPath), false, true)
            FileDelete(requestPath)
            response := {match: 0, diagnostic: {}, error: ""
                , edgeCacheHits: 0, edgeCacheBuilds: 0}
            try {
                ref := {Path: request["refPath"], W: request["refW"], H: request["refH"]}
                sample := {Path: request["samplePath"], W: request["sampleW"], H: request["sampleH"]}
                hitsBefore := editor._sampleEdgeCacheHits
                buildsBefore := editor._sampleEdgeCacheBuilds
                mode := request.Has("mode") ? request["mode"] : "align"
                if (mode == "verify")
                    response.match := editor._SampleVerifyPairAtOffset(ref, sample
                        , request["expectedX"], request["expectedY"], response.diagnostic)
                else if (mode == "effect")
                    response.match := editor._SampleAlignEffectCandidate(
                        ref, sample, response.diagnostic)
                else
                    response.match := editor._AlignPairTo(ref, sample, response.diagnostic)
                response.edgeCacheHits := editor._sampleEdgeCacheHits - hitsBefore
                response.edgeCacheBuilds := editor._sampleEdgeCacheBuilds - buildsBefore
            } catch as e {
                response.error := e.Message
            }
            try FileDelete(resultTempPath)
            FileAppend(JSON.stringify(response), resultTempPath, "UTF-8")
            FileMove(resultTempPath, resultPath, true)
        }
    } catch as e {
        response := {match: 0, diagnostic: {}, error: e.Message
            , edgeCacheHits: 0, edgeCacheBuilds: 0}
        try FileAppend(JSON.stringify(response), resultTempPath, "UTF-8")
        try FileMove(resultTempPath, resultPath, true)
    } finally {
        if (token)
            Gdip_Shutdown(token)
    }
    ExitApp()
}

#Include "..\Main\AssetUtil.ahk"
#Include "..\Main\Util\LogUtil.ahk"
#Include "..\Main\Util\SharedMemory.ahk"
#Include "..\Main\Util\RingBuffer.ahk"
#Include InputFilePicker.ahk
#Include WorkUtil.ahk
#Include WorkGlobalUtil.ahk

if (A_Args.Length = 4 && A_Args[1] = "--input-file") {
    if RegExMatch(A_Args[2], "^Local\\RMT_Picker_\d+_\d+_\d+$")
        RunInputFilePicker(A_Args[2], Integer(A_Args[3]), Integer(A_Args[4]))
    ExitApp()
}

BootWorkerConfig()          ;读配置 + 建路径 + 解析命令行（唯一序列，见 WorkUtil）
InitWork()                  ;工作器特别初始化
WorkPluginInit()            ;插件初始化

; 注册消息
OnMessage(WM_CLEAR_WORK, OnWorkerExitMessage)           ;清除
OnMessage(WM_MASTER_TO_WORKER, OnMasterToWorker)        ;主进程分发任务/广播通知
WorkNotifyReady()   ;加载完成，同步通知主线程
WaitAndProcessTasks()
