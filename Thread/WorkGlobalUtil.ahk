#Requires AutoHotkey v2.0

#SingleInstance Off
#NoTrayIcon
DetectHiddenWindows true
Persistent

global MySoftData := SoftData()
global MainSoftData := MainConfig()     ; Worker 也需要实例化（AssetUtil/LangUtil 会引用）
global MyMouseInfo := MouseWinData()

; Worker 无 UI，该函数为空操作
SetToolTextDisplay(text) {
}
global IniFile := A_WorkingDir "\..\Setting\MainSettings.ini"
global ThemesIniPath := A_WorkingDir "\..\Setting\themes.ini"
global LangDir := A_WorkingDir "\..\Lang"

global MyChineseOcr := 0  ; 懒加载：首次使用时才初始化
global MyEnglishOcr := 0   ; 懒加载：首次使用时才初始化
global MyPToken := Gdip_Startup()
; Worker 无 UI：MyMainWin 仅主程序实例化（Main/MainWindowXaml.ahk:1084），
; 此处伪赋值占位，避免 Worker 编译期 #Warn UseUnsetGlobal 警告（MacroUtil 引用处有 IsObject 保护）
global MyMainWin := ""

; 主进程输入弹窗（输入框/按钮条）回传结果缓存：OnEventMessage 收到 IPR/IBR 写入，WorkerInputRequest 读取
global _workerInputResult := ""
; §17 热重载：主进程广播 CF 后待重载配置的标志（忙时置位，任务结束 finally 重载）
global workerConfigDirty := false
global MyStopMacro := WorkStopMacro
global MyTriggerSubMacro := WorkTriggerSubMacro
global MySubmitGraphBranches := WorkSubmitGraphBranches
global MySetGlobalVariable := WorkSetGlobalVariable
global MyDelGlobalVariable := WorkDelGlobalVariable
global MyCMDReportAciton := WorkCMDReport
global MyCMDTipForceAction := WorkCmdTipForceShow
global MyExcuteRMTCMDAction := WorkExcuteRMTCMDAction
global MySetTableItemState := WorkSetTableItemState
global MySetItemPauseState := WorkSetItemPauseState
global MyMsgBoxContent := WorkMsgBoxContent
global MyToolTipContent := WorkToolTipContent
global MyMacroCount := WorkMacroCount
global MyViGJoySetState := WorkViGJoySetState
;数组相关
global MySetGlobalArray := WorkSetGlobalArray
global MyCloneGlobalArray := WorkCloneGlobalArray
global MyDeleteGlobalArray := WorkDeleteGlobalArray
global MyModifyGlobalArray := WorkModifyGlobalArray
global MyInsertGlobalArray := WorkInsertGlobalArray
global MyRemoveAtGlobalArray := WorkRemoveAtGlobalArray