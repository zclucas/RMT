#Requires AutoHotkey v2.0
global RMT_VERSION := "1.2F19"
#Include Main\SelfCheck.ahk
; SelfCheckMissingFiles()   ;开发日常注释，打正式包启用，方便动态修改一些文件
#Include Main\AssetUtil.ahk
#Include Main\GlobalUtil.ahk
#Include Main\MainGlobalUtil.ahk

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
BindKey()           ;绑定快捷键