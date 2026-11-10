#Requires AutoHotkey v2.0

#SingleInstance Off
#NoTrayIcon
DetectHiddenWindows true
Persistent

global MySoftData := SoftData()
global MainSoftData := MainConfig()     ; Worker 也需要实例化（AssetUtil/LangUtil 会引用）
global MyMouseInfo := MouseWinData()

global SettingFile := A_WorkingDir "\..\Setting\MainSettings.toml"
global ThemesPath := A_WorkingDir "\..\Setting\themes.toml"
global LangDir := A_WorkingDir "\..\Lang"
; 软件根目录：Worker 的 A_WorkingDir 是 Thread\ 子目录，这里减一层并规整掉 \..。
; 之后所有路径都以它为准，公共函数里不再需要判断「是不是 Worker」。
global AppRootDir := ResolvePathNoDotDot(A_WorkingDir "\..")

global MyChineseOcr := 0  ; 懒加载：首次使用时才初始化
global MyEnglishOcr := 0   ; 懒加载：首次使用时才初始化
global MyPToken := Gdip_Startup()

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
global MyCountDownStart := (token, total, x, y, detached) => MsgSendHandler("CountDown", "start", token, total, x, y, detached)
global MyCountDownStop := (token) => MsgSendHandler("CountDown", "stop", token)
global MyCountDownCloseByPosition := (key) => MsgSendHandler("CountDown", "closeAt", key)
global MyShowPrompt := (payload) => MsgSendHandler("Prompt", payload)
global MyMsgBoxContent := WorkMsgBoxContent
global MyToolTipContent := WorkToolTipContent
global MyOutputTipContent := WorkOutputTipContent
global MyViGJoySetState := WorkViGJoySetState
;数组相关
global MySetGlobalArray := WorkSetGlobalArray
global MyCloneGlobalArray := WorkCloneGlobalArray
global MyDeleteGlobalArray := WorkDeleteGlobalArray
global MyModifyGlobalArray := WorkModifyGlobalArray
global MyInsertGlobalArray := WorkInsertGlobalArray
global MyRemoveAtGlobalArray := WorkRemoveAtGlobalArray
