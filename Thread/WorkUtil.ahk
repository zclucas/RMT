#Requires AutoHotkey v2.0

;初始化数据
{
    InitWorkFilePath() {
        global VBSPath := A_WorkingDir "\..\MinTool\PlayAudio.vbs"
        global StartTipAudio := A_WorkingDir "\..\Audio\Start.wav"
        global EndTipAudio := A_WorkingDir "\..\Audio\End.wav"
        global ViGEmDllPath := A_WorkingDir "\..\Plugins\ViGEm\ViGEmWrapper.dll"
        global ArrayFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\ArrayFile.ini"
        global TimingFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\TimingFile.ini"
        global MacroFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\MacroFile.ini"
        global SearchFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\SearchFile.ini"
        global SearchProFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\SearchProFile.ini"
        global CompareFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\CompareFile.ini"
        global CompareProFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\CompareProFile.ini"
        global MMProFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\MMProFile.ini"
        global BGKeyFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\BGKeyFile.ini"
        global RunFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\RunFile.ini"
        global OutputFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\OutputFile.ini"
        global VariableFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\VariableFile.ini"
        global ExVariableFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\ExVariableFile.ini"
        global TextOpsFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\TextOpsFile.ini"
        global SubMacroFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\SubMacroFile.ini"
        global LoopFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\LoopFile.ini"
        global OperationFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\OperationFile.ini"
        global BGMouseFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\BGMouseFile.ini"
        global InputFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\InputFile.ini"
        global FileIOFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\FileIOFile.ini"
        global WindowManageFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\WindowManageFile.ini"
        global KeyCheckFile := A_WorkingDir "\..\Setting\" MySoftData.CurSettingName "\KeyCheckFile.ini"
        global IniSection := "UserSettings"

        ;利用机制把路径中的\..转换掉
        loop files, StartTipAudio {
            StartTipAudio := A_LoopFileFullPath
            break
        }
        loop files, EndTipAudio {
            EndTipAudio := A_LoopFileFullPath
            break
        }
    }

    InitWork() {
        global MySoftData
        MySoftData.isWorker := true
    }

    WorkOpenCVLoadDll() {
        ; 根据进程位数自动选择 x86 或 x64
        archDir := (A_PtrSize = 4) ? "x86" : "x64"
        dllDir := A_ScriptDir "\..\Plugins\OpenCV\" archDir
        OpenCvPath := dllDir "\RMT_OpenCV.dll"
        IBPath := A_ScriptDir "\..\Plugins\IbInputSimulator.dll"

        ; 使用 SetDllDirectory 将 dllDir 添加到 DLL 搜索路径中
        DllCall("SetDllDirectory", "Str", dllDir)

        DllCall('LoadLibrary', 'str', OpenCvPath, "Ptr")
        DllCall('LoadLibrary', 'str', IBPath)
    }
}

;通信辅助函数
{
    MsgPostHandler(type, wParam, lParam) {
        PostMessage(type, wParam, lParam, , "ahk_id " parentHwnd)
    }

    MsgSendHandler(action, args*) {
        global rx
        payload := JSON.stringify([action, args*])
        rx.Push(MsgType.EVENT, 0, payload)
    }
}

;接受主程序指令后回调
{
    OnWorkStopMacro(wParam, lParam, msg, hwnd) {
        tableIndex := wParam
        itemIndex := lParam
        tableItem := MySoftData.TableInfo[tableIndex]
        KillTableItemMacro(tableItem, itemIndex)
    }

    OnExit(wParam, lParam, msg, hwnd) {
        ExitApp()
    }

    CheckParentProcess() {
        if !ProcessExist(parentPID) {
            ExitApp()
        }
    }

    SetTimer(CheckParentProcess, 2000)

    OnEventMessage(cmd) {
        try {
            paramArr := JSON.parse(cmd)
            action := paramArr[1]
            args := []
            loop paramArr.Length - 1 {
                args.Push(paramArr[A_Index + 1])
            }
            switch action {
                case "SetVari":
                    NameArr := args[1]
                    ValueArr := args[2]
                    loop NameArr.Length {
                        MySoftData.VariableMap[NameArr[A_Index]] := ValueArr[A_Index]
                    }
                case "DelVari":
                    NameArr := args[1]
                    loop NameArr.Length {
                        if (MySoftData.VariableMap.Has(NameArr[A_Index]))
                            MySoftData.VariableMap.Delete(NameArr[A_Index])
                    }
                case "CMDTip":
                    MySoftData.CMDTip := args[1]
                case "PauseState":
                    tableItem := MySoftData.TableInfo[args[1]]
                    tableItem.PauseArr[args[2]] := args[3]
                case "SetArray":
                    Name := args[1]
                    Value := GetArray(args[2])
                    MySoftData.ArrayMap[Name] := Value
                case "CloneArray":
                    SourceArr := GetArray(args[1])
                    NewArrName := args[2]
                    MySoftData.ArrayMap[NewArrName] := SourceArr
                case "DeleteArray":
                    if (MySoftData.ArrayMap.Has(args[1]))
                        MySoftData.ArrayMap.Delete(args[1])
                case "ModifyArray":
                    ArrName := args[1]
                    MainIndex := args[2]
                    Index := args[3]
                    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
                    Value := args[4] ? GetArray(args[5]) : args[5]
                    SourceArr[Index] := Value
                case "InsertArray":
                    ArrName := args[1]
                    MainIndex := args[2]
                    Index := args[3]
                    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
                    Value := args[4] ? GetArray(args[5]) : args[5]
                    SourceArr.InsertAt(Index, Value)
                case "RemoveAtArray":
                    ArrName := args[1]
                    MainIndex := args[2]
                    Index := args[3]
                    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
                    SourceArr.RemoveAt(Index)
            }
        } catch {
        }
    }
}

;变量数据相关函数
{
    WorkSetGlobalArray(Name, Value) {
        MySoftData.ArrayMap[Name] := Value
        MsgSendHandler("SetArray", Name, GetArrayStr(Value))
    }

    WorkCloneGlobalArray(SourceArr, NewArrName) {
        MySoftData.ArrayMap[NewArrName] := SourceArr.Clone()
        MsgSendHandler("CloneArray", GetArrayStr(SourceArr), NewArrName)
    }

    WorkDeleteGlobalArray(ArrName) {
        MsgSendHandler("DeleteArray", ArrName)
    }

    WorkModifyGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
        ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
        MsgSendHandler("ModifyArray", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
    }

    WorkInsertGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
        ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
        MsgSendHandler("InsertArray", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
    }

    WorkRemoveAtGlobalArray(ArrName, MainIndex, Index) {
        MsgSendHandler("RemoveAtArray", ArrName, MainIndex, Index)
    }

    WorkSetGlobalVariable(NameArr, ValueArr, ignoreExist) {
        RealNameArr := NameArr.Clone()
        RealValueArr := ValueArr.Clone()
        
        if (ignoreExist) {
            RealNameArr := []
            RealValueArr := []
            loop NameArr.Length {
                if (!MySoftData.VariableMap.Has(NameArr[A_Index])) {
                    RealNameArr.Push(NameArr[A_Index])
                    RealValueArr.Push(ValueArr[A_Index])
                }
            }
        }
        if (RealNameArr.Length == 0)
            return

        loop RealNameArr.Length {
            MySoftData.VariableMap[RealNameArr[A_Index]] := ValueArr[A_Index]
        }
        MsgSendHandler("SetVari", RealNameArr, RealValueArr)
    }

    WorkDelGlobalVariable(NameArr) {
        RealNameArr := []
        loop NameArr.Length {
            if (MySoftData.VariableMap.Has(NameArr[A_Index])) {
                MySoftData.VariableMap.Delete(NameArr[A_Index])
                RealNameArr.Push(NameArr[A_Index])
            }
        }

        if (RealNameArr.Length == 0)
            return
        MsgSendHandler("DelVari", RealNameArr)
    }
}

;宏指令相关函数
{
    TriggerMacro(tableIndex, itemIndex) {
        tableItem := MySoftData.TableInfo[tableIndex]
        macro := tableItem.MacroArr[itemIndex]
        OnTriggerMacroKeyAndInit(tableItem, macro, itemIndex)
    }

    WorkSubMacroStopAction(tableIndex, itemIndex) {
        MsgPostHandler(WM_STOP_MACRO, tableIndex, itemIndex)
    }

    WorkTriggerSubMacro(tableIndex, itemIndex) {
        MsgPostHandler(WM_TR_MACRO, tableIndex, itemIndex)
    }

    WorkSetTableItemState(tableIndex, itemIndex, state) {
        MsgSendHandler("ItemState", tableIndex, itemIndex, state)
    }

    WorkSetItemPauseState(tableIndex, itemIndex, state) {
        MsgSendHandler("PauseState", tableIndex, itemIndex, state)
    }
}

;子程序告诉主程动作
{
    WorkCMDReport(cmdStr) {
        MsgSendHandler("Report", cmdStr)
    }

    WorkExcuteRMTCMDAction(cmdStr) {
        MsgSendHandler("RMT指令", cmdStr)
    }

    WorkMsgBoxContent(content) {
        MsgSendHandler("MsgBox", content)
    }

    WorkToolTipContent(content) {
        MsgSendHandler("ToolTip", content)
    }

    WorkMacroCount(content) {
        MsgSendHandler("MacroCount", content)
    }

    WorkViGJoySetState(JoyType, Key, Value) {
        MsgSendHandler("Joy", JoyType, Key, Value)
    }
}
