#Requires AutoHotkey v2.0
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
