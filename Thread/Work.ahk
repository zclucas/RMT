#Requires AutoHotkey v2.0
#Include "..\Main\AssetUtil.ahk"
#Include "..\Gui\CustomInputGui.ahk"
#Include "..\Gui\InputBtnGui.ahk"
#Include "..\Plugins\RapidOcr\RapidOcr.ahk"
#Include "..\Plugins\IbInputSimulator.ahk"
#Include "..\Main\Util\SharedMemory.ahk"
#Include "..\Main\Util\RingBuffer.ahk"
#Include "..\Main\Util\JsonUtil.ahk"
#Include "..\Main\Util\ErrorHandler.ahk"
#Include WorkUtil.ahk
#SingleInstance Force
DetectHiddenWindows true
Persistent
#NoTrayIcon

OnError(ErrHandler)

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

OnMessage(WM_WORK_NOTIFY, OnWorkNotify)

OnWorkNotify(wParam, lParam, msg, hwnd) {
    ProcessQueue()
}

ProcessQueue() {
    global tx, rx, hEvent, workIndex
    
    tx.SetNotifyFlag(0)
    
    maxBatch := 10
    processed := 0
    
    while (processed < maxBatch && tx.Pop(&type, &id, &cmd, &hTaskEvent)) {
        processed++
        switch type {
            case MsgType.TASK:
                result := ExecTask(cmd)
                rx.Push(MsgType.RESULT, id, result)
                
                ; Notify parent
                if (rx.ExchangeNotifyFlag(1) == 0)
                    MsgPostHandler(WM_RESULT_NOTIFY, workIndex, 0)

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

    ; Level-triggered re-check
    if (!tx.IsEmpty()) {
        if (tx.ExchangeNotifyFlag(1) == 0)
            PostMessage(WM_WORK_NOTIFY, 0, 0, , "ahk_id " A_ScriptHwnd)
    }
}

ExecTask(cmd) {
    try {
        paramArr := JSON.parse(cmd)
        if (paramArr[1] == "TR_MACRO") {
            TriggerMacro(paramArr[2], paramArr[3])
            return 1
        }
    } catch {
        ; fallback to old string execution if any
    }
    
    if (IsSet(MyExcuteRMTCMDAction)) {
        try return MyExcuteRMTCMDAction(cmd)
    }
    return 1
}

OnControlMessage(cmd) {
    ; Handle any JSON control messages
}

; 注册消息
OnMessage(WM_STOP_MACRO, OnWorkStopMacro)
OnMessage(WM_CLEAR_WORK, OnExit)

MsgPostHandler(WM_LOAD_WORK, workIndex, A_ScriptHwnd)