#Requires AutoHotkey v2.0

; Worker 不加载界面。AssetUtil 里会直接写 RmtDialog，类必须先存在，
; 否则编译时会被当成未赋值的局部变量。提示转给主进程显示。
class RmtDialog {
    static Info(msg, title := "", owner := 0) {
        try WorkMsgBoxContent(String(msg))
    }

    static Confirm(msg, title := "", owner := 0) {
        try WorkMsgBoxContent(String(msg))
        return false
    }

    static Choose(msg, title := "", buttons := [], owner := 0) {
        try WorkMsgBoxContent(String(msg))
        return 0
    }
}

#Include "..\Main\AssetUtil.ahk"
#Include "..\Main\Util\LogUtil.ahk"
#Include "..\Main\Util\SharedMemory.ahk"
#Include "..\Main\Util\RingBuffer.ahk"
#Include WorkUtil.ahk
#Include WorkGlobalUtil.ahk

LoadMainSetting()           ;加载配置
InitWorkFilePath()          ;初始化文件路径
HandleWorkOpenArg()         ;处理打开参数
LoadCurMacroSetting()       ;加载当前配置宏
InitData()                  ;初始化软件数据，加载所有的宏指令
InitWork()                  ;工作器特别初始化
WorkPluginInit()            ;插件初始化

; 注册消息
OnMessage(WM_CLEAR_WORK, OnExit)                        ;清除
OnMessage(WM_MASTER_TO_WORKER, OnMasterToWorker)        ;主进程分发任务/广播通知
WorkNotifyReady()   ;加载完成，同步通知主线程
WaitAndProcessTasks()
