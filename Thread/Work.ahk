#Requires AutoHotkey v2.0
#Include "..\Main\AssetUtil.ahk"
#Include "..\Gui\CustomInputGui.ahk"
#Include "..\Gui\InputBtnGui.ahk"
#Include "..\Plugins\RapidOcr\RapidOcr.ahk"
#Include "..\Plugins\IbInputSimulator.ahk"
#Include WorkUtil.ahk

RmtPostState(*) {
    ; Worker processes do not own the WebView; shared macro utilities can call this safely.
}

#SingleInstance Force
DetectHiddenWindows true
Persistent
#NoTrayIcon

global parentHwnd := A_Args[1]
global workIndex := A_Args[2]
global parentPID := A_Args[3]
global ReceiveInfoMap := Map()
global MySoftData := SoftData()
global ToolCheckInfo := ToolCheck()
global MyMouseInfo := MouseWinData()
global IniFile := A_WorkingDir "\..\Setting\MainSettings.ini"
global LangDir := A_WorkingDir "\..\Lang"
LoadMainSetting()   ;加载配置
InitWorkFilePath()  ;初始化文件路径
LoadCurMacroSetting()   ;加载当前配置宏
InitData()
InitWork()

global MyChineseOcr := 0  ; 懒加载：首次使用时才初始化
global MyEnglishOcr := 0   ; 懒加载：首次使用时才初始化
global MyPToken := Gdip_Startup()
global MyInputGui := CustomInputGui()
global MyInputBtnGui := InputBtnGui()
global MySubMacroStopAction := WorkSubMacroStopAction
global MyTriggerSubMacro := WorkTriggerSubMacro
global MySetGlobalVariable := WorkSetGlobalVariable
global MyDelGlobalVariable := WorkDelGlobalVariable
global MyCMDReportAciton := WorkCMDReport
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
WorkOpenCVLoadDll()
SetTimer(CheckOcrIdle, 60000)

; 注册消息
OnMessage(WM_TR_MACRO, OnWorkTriggerMacro)
OnMessage(WM_STOP_MACRO, OnWorkStopMacro)
OnMessage(WM_CLEAR_WORK, OnExit)
OnMessage(WM_COPYDATA, OnWorkGetCmdStr)
OnMessage(WM_RECEIVE_INFO, OnMainReceiveInfo)

myTitle := "RMTWork" workIndex
mygui := Gui("+ToolWindow")          ; 创建 GUI，无标题栏
mygui.Title := myTitle               ; 设置窗口标题（这才是 WinGetTitle 能读到的）
mygui.Show("Hide")                   ; 隐藏窗口
global myHwnd := mygui.Hwnd
MsgPostHandler(WM_LOAD_WORK, workIndex, 0)
