#Requires AutoHotkey v2.0
; #NoTrayIcon
global RMT_VERSION := "1.3F3"
#Include Main\SelfCheck.ahk
#Include Main\AssetUtil.ahk
#Include Main\GlobalUtil.ahk
#Include Main\MainGlobalUtil.ahk
#SingleInstance Off ; 命令行客户端先走应用互斥，不能由界面库的 Force 规则替换常驻进程。

; §3 单实例：已有实例且携带命令行参数 → 转发命令队列后退出；否则（无参数/提权切换）接管
if (!EnsureSingleInstance())
    ExitApp()

; 把程序路径写入环境变量 rmt，并安装 rmt 命令（仅常驻实例执行，命令行转发进程会先退出）
RmtRegisterCliCommand()
XAMLHost.Prewarm()
InitFilePath()              ;初始化文件路径
LoadCurMacroSetting()       ;加载当前宏配置
HandleOpenArg()             ;处理打开软件的参数
RegisterNativeComboWheelGuard()
InitData()                  ;初始化软件数据，加载所有的宏指令
InitUI()                    ;初始化主界面UI
SetEditData()               ;缓存编辑器数据，设置下拉框变量，检测是否有手柄按键

;放后面初始化，因为这初始化时间比较长
;注意：PluginInit 里会创建 WorkPool，随即拉起 Worker 进程。Worker 只读配置，所以必须排在 LoadCurMacroSetting之后
PluginInit()
MyTimingScheduler.Start()
MyNetworkServer.Start()     ;§23 网络触发：启动 HTTP 监听（默认 127.0.0.1:16888，bind 失败仅告警不阻塞）
InitVoiceEngine().Start()    ;启动语音触发监听（引擎 DLL 缺失时安全降级，不影响其余功能）
BindKey()           ;绑定快捷键

; §3 命令行收尾：启动命令队列监听 + 执行首次启动携带的命令（如 rmt -run 1-2 在无实例时直接启动执行）
StartCmdQueueListener()
; 启动命令会读主窗适配器（界面状态），排到 UI 收尾之后；两者共用同一个就绪回调
WaitMainWinReady(RunStartupCommandsAfterUI)

RunStartupCommandsAfterUI() {
    RmtRunStartupCommands()
    ; 语音模型预热：磁盘上有流式模型就在后台线程加载（1~3 秒），
    ; 这样输入弹窗「按住 Alt 说话」不必等首次加载。放启动链末尾再延迟 2 秒，
    ; 避开开窗/拉起 Worker 的高峰；加载在 DLL 线程里做，主线程不阻塞。
    SetTimer(SttWarmupStreamAsync, -2000)
}
