#Requires AutoHotkey v2.0

;初始化数据
{
    InitWorkFilePath() {
        global VBSPath := A_WorkingDir "\..\VBS\PlayAudio.vbs"
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
        OpenCvPath := A_ScriptDir "\..\Plugins\OpenCV\RMT_OpenCV.dll"
        IBPath := A_ScriptDir "\..\Plugins\IbInputSimulator.dll"

        ; 构建包含 DLL 文件的目录路径
        dllDir := A_ScriptDir "\..\Plugins\OpenCV"
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

    MsgSendHandler(str, Timestamp := "") {
        if (Timestamp == "") {
            currentDateTime := FormatTime(, "HHmmss")
            randomNum := Random(0, 9) Random(0, 9) Random(0, 9)
            Timestamp := CurrentDateTime randomNum
            data := ReceiveCheckData()
            data.Timestamp := Timestamp
            data.Str := str
            ReceiveInfoMap.Set(Timestamp, data)
        }
        if (!ReceiveInfoMap.Has(Timestamp))
            return
        data := ReceiveInfoMap[Timestamp]
        data.EnableCheckAction()

        CopyDataStruct := Buffer(3 * A_PtrSize)  ; 分配结构的内存区域.
        ; 首先设置结构的 cbData 成员为字符串的大小, 包括它的零终止符:
        SizeInBytes := (StrLen(str) + 1) * 2
        NumPut("Ptr", SizeInBytes  ; 操作系统要求这个需要完成.
            , "Ptr", StrPtr(str)  ; 设置 lpData 为到字符串自身的指针.
            , CopyDataStruct, A_PtrSize)
        SendMessage(WM_COPYDATA, Timestamp, CopyDataStruct, , "ahk_id " parentHwnd)
    }

}

;接受主程序指令后回调
{
    OnWorkTriggerMacro(wParam, lParam, msg, hwnd) {
        TriggerMacro(wParam, lParam)
        MsgPostHandler(WM_RELEASE_WORK, wParam, lParam)
    }

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

    OnWorkGetCmdStr(wParam, lParam, msg, hwnd) {
        StringAddress := NumGet(lParam, 2 * A_PtrSize, "Ptr")  ; 检索 CopyDataStruct 的 lpData 成员.
        Cmd := StrGet(StringAddress)  ; 从结构中复制字符串.
        paramArr := StrSplit(cmd, "_")
        switch paramArr[1] {
            case "SetVari":
                GetNameAndValueByParamArr(&NameArr, &ValueArr, paramArr)
                loop NameArr.Length {
                    MySoftData.VariableMap[NameArr[A_Index]] := ValueArr[A_Index]
                }
            case "DelVari":
                NameArr := paramArr.Clone()
                NameArr.RemoveAt(1)
                loop NameArr.Length {
                    if (MySoftData.VariableMap.Has(NameArr[A_Index]))
                        MySoftData.VariableMap.Delete(NameArr[A_Index])
                }
            case "CMDTip":
                MySoftData.CMDTip := paramArr[2]
            case "PauseState":
                tableItem := MySoftData.TableInfo[paramArr[2]]
                tableItem.PauseArr[paramArr[3]] := paramArr[4]
            case "SetArray":
                Name := paramArr[2]
                Value := GetArray(paramArr[3])
                MySoftData.ArrayMap[Name] := Value
            case "CloneArray":
                SourceArr := GetArray(paramArr[2])
                NewArrName := paramArr[3]
                MySoftData.ArrayMap[NewArrName] := SourceArr
            case "DeleteArray":
                if (MySoftData.ArrayMap.Has(paramArr[2]))
                    MySoftData.ArrayMap.Delete(paramArr[2])
            case "ModifyArray":
                ArrName := paramArr[2]
                MainIndex := paramArr[3]
                Index := paramArr[4]
                SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
                Value := paramArr[5] ? GetArray(paramArr[6]) : paramArr[6]
                SourceArr[Index] := Value
            case "InsertArray":
                ArrName := paramArr[2]
                MainIndex := paramArr[3]
                Index := paramArr[4]
                SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
                Value := paramArr[5] ? GetArray(paramArr[6]) : paramArr[6]
                SourceArr.InsertAt(Index, Value)
            case "RemoveAtArray":
                ArrName := paramArr[2]
                MainIndex := paramArr[3]
                Index := paramArr[4]
                SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
                SourceArr.RemoveAt(Index)
        }
    }

    OnMainReceiveInfo(wParam, lParam, msg, hwnd) {
        Timestamp := String(wParam)

        if (ReceiveInfoMap.Has(Timestamp)) {
            ReceiveInfoMap[Timestamp].Destroy()
        }
    }
}

;变量数据相关函数
{
    WorkSetGlobalArray(Name, Value) {
        MySoftData.ArrayMap[Name] := Value
        CmdStr := Format("SetArray_{}_{}", Name, GetArrayStr(Value))
        MsgSendHandler(CmdStr)
    }

    WorkCloneGlobalArray(SourceArr, NewArrName) {
        MySoftData.ArrayMap[NewArrName] := SourceArr.Clone()
        CMDStr := Format("CloneArray_{}_{}", GetArrayStr(SourceArr), NewArrName)
        MsgSendHandler(CmdStr)
    }

    WorkDeleteGlobalArray(ArrName) {
        CMDStr := Format("DeleteArray_{}", ArrName)
        MsgSendHandler(CmdStr)
    }

    WorkModifyGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
        ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
        CMDStr := Format("ModifyArray_{}_{}_{}_{}_{}", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
        MsgSendHandler(CmdStr)
    }

    WorkInsertGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
        ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
        CMDStr := Format("InsertArray_{}_{}_{}_{}_{}", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
        MsgSendHandler(CmdStr)
    }

    WorkRemoveAtGlobalArray(ArrName, MainIndex, Index) {
        CMDStr := Format("RemoveAtArray_{}_{}_{}", ArrName, MainIndex, Index)
        MsgSendHandler(CmdStr)
    }

    WorkSetGlobalVariable(NameArr, ValueArr, ignoreExist) {
        RealNameArr := NameArr.Clone()
        RealValueArr := ValueArr.Clone()
        NameValueCMDStr := "SetVari"
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
            if (Type(RealValueArr[A_Index]) == "String") {
                RealValueArr[A_Index] := Trim(RealValueArr[A_Index], "`n")
                RealValueArr[A_Index] := Trim(RealValueArr[A_Index])
            }
            NameValueCMDStr .= Format("_{}_{}", RealNameArr[A_Index], RealValueArr[A_Index])
            MySoftData.VariableMap[RealNameArr[A_Index]] := ValueArr[A_Index]
        }
        MsgSendHandler(NameValueCMDStr)
    }

    WorkDelGlobalVariable(NameArr) {
        RealNameArr := []
        NameValueCMDStr := "DelVari"
        loop NameArr.Length {
            if (MySoftData.VariableMap.Has(NameArr[A_Index])) {
                NameValueCMDStr .= Format("_{}", NameArr[A_Index])
                MySoftData.VariableMap.Delete(NameArr[A_Index])
                RealNameArr.Push(NameArr[A_Index])
            }
        }

        if (RealNameArr.Length == 0)
            return
        MsgSendHandler(NameValueCMDStr)
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
        str := Format("ItemState_{}_{}_{}", tableIndex, itemIndex, state)
        MsgSendHandler(str)
    }

    WorkSetItemPauseState(tableIndex, itemIndex, state) {
        str := Format("PauseState_{}_{}_{}", tableIndex, itemIndex, state)
        MsgSendHandler(str)
    }
}

;子程序告诉主程动作
{
    WorkCMDReport(cmdStr) {
        str := Format("Report_{}", cmdStr)
        MsgSendHandler(str)
    }

    WorkExcuteRMTCMDAction(cmdStr) {
        MsgSendHandler(cmdStr)
    }

    WorkMsgBoxContent(content) {
        str := Format("MsgBox_{}", content)
        MsgSendHandler(str)
    }

    WorkToolTipContent(content) {
        str := Format("ToolTip_{}", content)
        MsgSendHandler(str)
    }

    WorkMacroCount(content) {
        str := Format("MacroCount_{}", content)
        MsgSendHandler(str)
    }

    WorkViGJoySetState(JoyType, Key, Value) {
        str := Format("Joy_{}_{}_{}", JoyType, Key, Value)
        MsgSendHandler(str)
    }
}

;通信校验
{
    CheckIfReceiveInfo(Timestamp) {
        ;不存在表示已经接收了，就不用处理
        if (!ReceiveInfoMap.Has(Timestamp))
            return

        MsgSendHandler(ReceiveInfoMap[Timestamp].Str, Timestamp)
    }

    class ReceiveCheckData {
        __New() {
            this.Timestamp := ""
            this.Str := ""
            this.Count := 0
            this.CheckAction := ""
        }

        EnableCheckAction() {
            this.Count++
            if (this.Count <= 3) {
                action := CheckIfReceiveInfo.Bind(this.Timestamp)
                this.CheckAction := action
                SetTimer(action, -30)
            }
        }

        Destroy() {
            if (ReceiveInfoMap.Has(this.Timestamp)) {
                if (this.CheckAction != "") {
                    action := this.CheckAction
                    SetTimer(action, 0)
                }

                ReceiveInfoMap.Delete(this.Timestamp)
            }
        }
    }
}
