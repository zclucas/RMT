#Requires AutoHotkey v2.0
global RMT_VERSION := "1.3"
#Include Main\SelfCheck.ahk
#Include Main\AssetUtil.ahk
#Include Main\GlobalUtil.ahk
#Include Main\MainGlobalUtil.ahk

; §3 单实例：已有实例且携带命令行参数 → 转发命令队列后退出；否则（无参数/提权切换）接管
if (!EnsureSingleInstance())
    ExitApp()

InitFilePath()              ;初始化文件路径
LoadCurMacroSetting()       ;加载当前配置宏，宏指令
HandleOpenArg()             ;处理打开软件的参数
EditListen()                ;滚轮按键监听，防止滚轮修改下拉框数值
InitData()                  ;初始化软件数据，加载所有的宏指令
InitUI()                    ;初始化主界面UI
SetEditData()               ;缓存编辑器数据，设置下拉框变量，检测是否有手柄按键

;放后面初始化，因为这初始化时间比较长
PluginInit()
MyTimingScheduler.Start()
InitVoiceEngine().Start()    ;启动语音触发监听（引擎 DLL 缺失时安全降级，不影响其余功能）
BindKey()           ;绑定快捷键

; §3 命令行收尾：启动命令队列监听 + 执行首次启动携带的命令（如 rmt -run 1-2 在无实例时直接启动执行）
StartCmdQueueListener()
RmtRunStartupCommands()