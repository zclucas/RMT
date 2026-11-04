#Requires AutoHotkey v2.0

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

#Include "..\Main\AssetUtil.ahk"
#Include "..\Main\Util\LogUtil.ahk"
#Include "..\Main\Util\SharedMemory.ahk"
#Include "..\Main\Util\RingBuffer.ahk"
#Include WorkUtil.ahk
#Include WorkGlobalUtil.ahk

BootWorkerConfig()          ;读配置 + 建路径 + 解析命令行（唯一序列，见 WorkUtil）
InitWork()                  ;工作器特别初始化
WorkPluginInit()            ;插件初始化

; 注册消息
OnMessage(WM_CLEAR_WORK, OnExit)                        ;清除
OnMessage(WM_MASTER_TO_WORKER, OnMasterToWorker)        ;主进程分发任务/广播通知
WorkNotifyReady()   ;加载完成，同步通知主线程
WaitAndProcessTasks()
