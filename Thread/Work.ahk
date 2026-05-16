#Requires AutoHotkey v2.0
#Include "..\Main\AssetUtil.ahk"
#Include "..\Gui\CustomInputGui.ahk"
#Include "..\Gui\InputBtnGui.ahk"
#Include "..\Plugins\RapidOcr\RapidOcr.ahk"
#Include "..\Plugins\IbInputSimulator.ahk"
#Include "..\Main\Util\SharedMemory.ahk"
#Include "..\Main\Util\RingBuffer.ahk"
#Include "..\Main\Util\JsonUtil.ahk"
#Include WorkUtil.ahk
#SingleInstance Force
DetectHiddenWindows true
Persistent
#NoTrayIcon

class MsgType {
    static TASK := 1
    static RESULT := 2
    static EVENT := 3
    static CONTROL := 4
}

global parentHwnd := A_Args[1]
global workIndex := A_Args[2]
global parentPID := A_Args[3]
global txName := A_Args[4]
global rxName := A_Args[5]
global evtName := A_Args[6]

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

global shmTx := SharedMemory(txName, 1048576 + 128)
global shmRx := SharedMemory(rxName, 1048576 + 128)
global tx := RingBuffer(shmTx.ptr, 1048576)
global rx := RingBuffer(shmRx.ptr, 1048576)
global hEvent := OpenEvent(evtName)

SetTimer(ProcessQueue, 1)
ProcessQueue() {
    global tx, rx, hEvent
    if (DllCall("WaitForSingleObject", "ptr", hEvent, "uint", 0) == 0) {
        while (tx.Pop(&type, &id, &cmd, &hTaskEvent)) {
            switch type {
                case MsgType.TASK:
                    result := ExecTask(cmd)
                    rx.Push(MsgType.RESULT, id, result)
                    if (hTaskEvent) {
                        SetEvent(hTaskEvent)
                        CloseHandle(hTaskEvent)
                    }
                case MsgType.CONTROL:
                    OnControlMessage(cmd)
                case MsgType.EVENT:
                    OnEventMessage(cmd)
            }
        }
        ResetEvent(hEvent)
    }
}

ExecTask(cmd) {
    try {
        paramArr := JSON.parse(cmd)
        if (paramArr[1] == "TR_MACRO") {
            TriggerMacro(paramArr[2], paramArr[3])
            return 1
        }
    } catch as e {
        if (IsSet(MsgSendHandler))
            MsgSendHandler("Error", GetFullErrorInfo(e))
    }
    
    if (IsSet(MyExcuteRMTCMDAction)) {
        try return MyExcuteRMTCMDAction(cmd)
        catch as e {
            if (IsSet(MsgSendHandler))
                MsgSendHandler("Error", GetFullErrorInfo(e))
        }
    }
    return 1
}

GetFullErrorInfo(exception) {
    what := ""
    msg := ""
    extra := ""
    stack := ""
    fullMsg := ""
    
    if (IsObject(exception)) {
        try what := exception.What
        try msg := exception.Message
        try extra := exception.Extra
        try stack := exception.Stack
    } else {
        msg := "" . exception
    }
    
    if (what != "")
        fullMsg := what
    if (msg != "")
        fullMsg := fullMsg (fullMsg ? " | " : "") . msg
    if (extra != "")
        fullMsg := fullMsg "`nSpecifically: " extra
    if (stack != "")
        fullMsg := fullMsg "`n" stack
    
    return fullMsg
}

OnControlMessage(cmd) {
    ; Handle any JSON control messages
}

; 注册消息
OnMessage(WM_STOP_MACRO, OnWorkStopMacro)
OnMessage(WM_CLEAR_WORK, OnExit)

myTitle := "RMTWork" workIndex
mygui := Gui("+ToolWindow")          ; 创建 GUI，无标题栏
mygui.Title := myTitle               ; 设置窗口标题（这才是 WinGetTitle 能读到的）
mygui.Show("Hide")                   ; 隐藏窗口
global myHwnd := mygui.Hwnd
MsgPostHandler(WM_LOAD_WORK, workIndex, A_ScriptHwnd)