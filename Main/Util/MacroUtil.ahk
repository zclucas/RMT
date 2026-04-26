;按键宏命令
OnTriggerMacroKeyAndInit(tableItem, macro, index) {
    MyMacroCount("Add")
    tableItem.KilledArr[index] := false
    tableItem.PauseArr[index] := false
    tableItem.ActionCount[index] := 0
    tableItem.VariableMapArr[index]["宏循环次数"] := 1
    tableItem.VariableMapArr[index]["循环次数"] := 0
    isContinue := tableItem.TKArr.Has(index) && MySoftData.ContinueKeyMap.Has(tableItem.TKArr[index]) && tableItem.LoopCountArr[
        index] == 1
    isLoop := tableItem.LoopCountArr[index] == -1
    loop {
        isFirst := tableItem.ActionCount[index] == 0
        isLast := tableItem.ActionCount[index] == tableItem.LoopCountArr[index] - 1
        isOver := tableItem.ActionCount[index] >= tableItem.LoopCountArr[index]
        WaitIfPaused(tableItem, index)

        if (tableItem.KilledArr[index])
            break

        if (!isLoop && !isContinue && isOver)
            break

        if (!isFirst && isContinue && isOver) {
            key := MySoftData.ContinueKeyMap[tableItem.TKArr[index]]
            Sleep(MySoftData.ContinueIntervale)

            if (!GetKeyState(key, "P")) {
                break
            }
        }

        HandTipSound(tableItem, index, 1, isFirst, isLast)
        OnTriggerMacroOnce(tableItem, macro, index)
        HandTipSound(tableItem, index, 2, isFirst, isLast)

        if (tableItem.VariableMapArr[index]["循环-跳过本轮"]) {
            tableItem.VariableMapArr[index]["循环-跳过本轮"] := false
        }

        if (tableItem.VariableMapArr[index]["循环-跳出"]) {
            tableItem.VariableMapArr[index]["循环-跳出"] := false
            break
        }

        tableItem.ActionCount[index]++
        tableItem.VariableMapArr[index]["宏循环次数"] += 1
    }
    OnFinishMacro(tableItem, macro, index)
}

OnFinishMacro(tableItem, macro, index) {
    if (tableItem.TriggerTypeArr[index] == 4) { ;开关状态下
        tableItem.ToggleStateArr[index] := false
    }

    ReleaseAllCaches()

    itemState := tableItem.KilledArr[index] ? 3 : 0
    MySetTableItemState(tableItem.index, index, itemState)
}

OnTriggerMacroOnce(tableItem, macro, index) {
    global MySoftData
    static Actions := Map(
        "间隔", OnInterval,
        "按键", OnPressKey,
        "搜索", OnSearchWrapper,
        "搜索Pro", OnSearchWrapper,
        "移动", OnMouseMove,
        "移动Pro", OnMMPro,
        "运行", OnRunFile,
        "如果", OnCompare,
        "如果Pro", OnComparePro,
        "输出", OnOutput,
        "变量", OnVariable,
        "变量提取", OnExVariableWrapper,
        "宏操作", OnSubMacro,
        "运算", OnOperation,
        "后台鼠标", OnBGMouse,
        "后台按键", OnBGKey,
        "RMT指令", OnRMTCMD,
        "循环", OnLoop,
        "文本处理", OnTextOps,
        "数组", OnArray,
        "输入", OnInput,
        "文件读写", OnFileIO
    )

    cmdArr := SplitMacro(macro)

    for value in cmdArr {
        if (tableItem.KilledArr[index])
            break

        WaitIfPaused(tableItem, index)
        if (SubStr(cmdArr[A_Index], 1, 2) == "🚫")
            continue

        cmdStr := GetCmdStr(cmdArr[A_Index])
        paramArr := StrSplit(cmdStr, "_")
        if (MySoftData.CMDTip) {
            MyCMDReportAciton(cmdStr)
        }

        ; 移除末尾数字以匹配Map键 (例如 "搜索1" -> "搜索"), 但保留Pro等后缀
        cmdKey := RTrim(paramArr[1], "0123456789")
        result := Actions[cmdKey](tableItem, cmdStr, index)
        if (result != "") {
            cmdArr.InsertAt(A_Index + 1, result*)
        }

        if (tableItem.VariableMapArr[index]["分支-跳出"]) {
            tableItem.VariableMapArr[index]["分支-跳出"] := false
            break
        }

        if (tableItem.VariableMapArr[index]["循环-跳过本轮"]) {
            break
        }

        if (tableItem.VariableMapArr[index]["循环-跳出"]) {
            break
        }
    }
}

OnSearchWrapper(tableItem, cmdStr, index) {
    isLoopFound := SearchOnTrigger(tableItem, cmdStr, index)
    if (isLoopFound != "" && isLoopFound == false) {
        return [cmdStr]
    }
}

OnExVariableWrapper(tableItem, cmdStr, index) {
    isLoopFound := OnExVariable(tableItem, cmdStr, index)
    if (isLoopFound != "" && isLoopFound == false) {
        return [cmdStr]
    }
}

OnRunFile(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    isMp3 := RegExMatch(Data.RunPath, ".mp3$")
    if (isMp3 && Data.BackPlay) {
        playAudioCmd := Format('wscript.exe "{}" "{}"', VBSPath, Data.RunPath)
        Run(playAudioCmd)
        return
    }
    processedPath := GetReplaceVarText(tableItem, index, Data.RunPath)
    Run(processedPath)
}

OnCompare(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    result := Data.LogicalType == 1 ? true : false
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index])
            continue

        CompareType := Data.CompareTypeArr[A_Index]
        hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Data.NameArr[A_Index], Data.VariableArr[
            A_Index])
        if (!hasComparison)
            return

        if (Data.LogicalType == 1) {
            result := result && currentComparison
            if (!result)
                break
        } else {
            result := result || currentComparison
            if (result)
                break
        }
    }

    if (Data.SaveToggle) {
        SaveValue := result ? Data.TrueValue : Data.FalseValue
        MySetGlobalVariable([Data.SaveName], [SaveValue], false)
    }

    macro := result ? Data.TrueMacro : Data.FalseMacro
    if (macro != "")
        OnTriggerMacroOnce(tableItem, macro, index)

    ControlType := result ? Data.TrueControlType : Data.FalseControlType
    HandleControlType(tableItem, index, ControlType)
}

OnComparePro(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    loop Data.VariNameArr.Length {
        NameArr := Data.VariNameArr[A_Index]
        CompareTypeArr := Data.CompareTypeArr[A_Index]
        VariableArr := Data.VariableArr[A_Index]
        LogicType := Data.LogicTypeArr[A_Index]
        Macro := Data.MacroArr[A_Index]
        ControlType := Data.ControlTypeArr[A_Index]
        result := LogicType == 1 ? true : false

        for i, Name in NameArr {
            CompareType := CompareTypeArr[i]
            hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Name, VariableArr[i])
            if (!hasComparison)
                return

            if (LogicType == 1) {
                result := result && currentComparison
                if (!result)
                    break
            } else {
                result := result || currentComparison
                if (result)
                    break
            }
        }

        if (result) {
            if (Macro != "")
                OnTriggerMacroOnce(tableItem, Macro, index)
            HandleControlType(tableItem, index, ControlType)
            return
        }
    }
    OnTriggerMacroOnce(tableItem, Data.DefaultMacro, index)
    HandleControlType(tableItem, index, Data.DefaultControlType)
}

OnMMPro(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    LastSumTime := 0
    Data.Count := Data.IsGameView ? data.Count : 1
    loop Data.Count {
        WaitIfPaused(tableItem, index)

        if (tableItem.KilledArr[index])
            return

        FloatInterval := GetFloatTime(Data.Interval, MySoftData.PreIntervalFloat)
        OnMMProOnce(tableItem, index, Data)
        if (A_Index != Data.Count)
            Sleep(FloatInterval)
    }
}

OnMMProOnce(tableItem, index, Data) {
    SendMode("Event")
    CoordMode("Mouse", "Screen")
    Speed := 100 - Data.Speed

    hasPosVarX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosVarX)
    hasPosVarY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosVarY)
    if (!hasPosVarX || !hasPosVarY) {
        return
    }

    PosX := GetFloatValue(PosX, MySoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MySoftData.CoordYFloat)
    ClickCount := Data.ActionType == 2 ? 1 : 2
    if (Data.IsGameView) {
        MOUSEEVENTF_MOVE := 0x0001
        DllCall("mouse_event", "UInt", MOUSEEVENTF_MOVE, "UInt", PosX, "UInt", PosY, "UInt", 0, "UInt", 0)
    }
    else if (Data.ActionType == 1) {
        if (Data.IsRelative) {
            MouseMove(PosX, PosY, Speed, "R")
        }
        else
            MouseMove(PosX, PosY, Speed)
    }
    else if (Data.ActionType == 2 || Data.ActionType == 3) {
        SetDefaultMouseSpeed(Speed)
        if (Data.IsRelative) {
            Click(Format("{} {} {} Relative"), PosX, PosY, ClickCount)
        }
        else {
            Click(Format("{} {} {}"), PosX, PosY, ClickCount)
        }
    }
}

OnOutput(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    Content := GetReplaceVarText(tableItem, index, Data.Text)

    if (Data.OutputType == "发送内容") {     ;send
        SendText(Content)
    }
    else if (Data.OutputType == "粘贴内容") {    ;粘贴文本
        SetClipboard(Content)
        ClipWait
        Send "{Blind}^v"
    }
    else if (Data.OutputType == "临时提示") {    ;提示
        MyToolTipContent(Content)
    }
    else if (Data.OutputType == "指令窗口") {    ;指令窗口
        MyCMDReportAciton(Content)
    }
    else if (Data.OutputType == "软件弹窗") {    ;弹窗
        MyMsgBoxContent(Content)
    }
    else if (Data.OutputType == "系统语音") {    ;语音
        spovice := ComObject("sapi.spvoice")
        spovice.Speak(Content)
    }
    else if (Data.OutputType == "复制到剪切板") {    ;剪切板
        SetClipboard(Content)
    }
}

OnLoop(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    if (Data.LoopCount == -1) {
        loop {
            tableItem.VariableMapArr[index]["循环次数"] := A_Index
            if (!GetLoopState(tableItem, cmd, index, Data))
                break

            if (tableItem.KilledArr[index])
                break

            WaitIfPaused(tableItem, index)
            OnTriggerMacroOnce(tableItem, Data.LoopBody, index)

            if (tableItem.VariableMapArr[index]["循环-跳过本轮"]) {
                tableItem.VariableMapArr[index]["循环-跳过本轮"] := false
            }

            if (tableItem.VariableMapArr[index]["循环-跳出"]) {
                tableItem.VariableMapArr[index]["循环-跳出"] := false
                break
            }
        }
    }
    else {
        hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.LoopCount)
        if (!hasValue)
            return

        loop Value {
            tableItem.VariableMapArr[index]["循环次数"] := A_Index
            if (!GetLoopState(tableItem, cmd, index, Data))
                break

            if (tableItem.KilledArr[index])
                break

            WaitIfPaused(tableItem, index)
            OnTriggerMacroOnce(tableItem, Data.LoopBody, index)

            if (tableItem.VariableMapArr[index]["循环-跳过本轮"]) {
                tableItem.VariableMapArr[index]["循环-跳过本轮"] := false
            }

            if (tableItem.VariableMapArr[index]["循环-跳出"]) {
                tableItem.VariableMapArr[index]["循环-跳出"] := false
                break
            }
        }
    }
}

GetLoopState(tableItem, cmd, index, Data) {
    if (Data.CondiType == 1)
        return true

    result := Data.LogicType == 1 ? true : false
    loop 4 {
        if (!Data.ToggleArr[A_Index])
            continue
        CompareType := Data.CompareTypeArr[A_Index]
        hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Data.NameArr[A_Index], Data.VariableArr[
            A_Index])
        if (!hasComparison) {
            result := false
            break
        }

        if (Data.LogicType == 1) {
            result := result && currentComparison
            if (!result)
                break
        } else {
            result := result || currentComparison
            if (result)
                break
        }
    }

    if (Data.CondiType == 2)
        return result

    if (Data.CondiType == 3)
        return !result
}

OnSubMacro(tableItem, cmd, index) {
    global MySoftData
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    macroIndex := Data.MacroType == "当前宏" ? index : Data.Index
    macroTableIndex := Data.MacroType == "当前宏" ? tableItem.Index : GetTableIndex(Data.MacroType)
    macroItem := Data.MacroType == "当前宏" ? tableItem : MySoftData.TableInfo[macroTableIndex]

    IsAbnormal := macroItem.SerialArr.Length < macroIndex || macroItem.SerialArr[macroIndex] != Data.MacroSerial
    if (Data.MacroType != "当前宏" && IsAbnormal) {
        loop macroItem.ModeArr.Length {
            if (Data.MacroSerial == macroItem.SerialArr[A_Index]) {
                macroIndex := A_Index
                break
            }
        }
    }

    if (Data.CallType == "插入到当前宏") {   ;插入
        macro := macroItem.MacroArr[macroIndex]
        resultMacro := ""
        isHas := TryGetTabVarValue(&Count, tableItem, index, Data.InsertCount, true)
        if (isHas) {
            loop Count {
                resultMacro .= macro ","
            }
        }
        resultMacro := Trim(resultMacro, ",")
        return SplitMacro(resultMacro)
    }
    else if (Data.CallType == "触发") {  ;触发
        MyTriggerSubMacro(macroTableIndex, macroIndex)
    }
    else if (Data.CallType == "暂停") {  ;暂停
        MySetItemPauseState(macroTableIndex, macroIndex, 1)
    }
    else if (Data.CallType == "取消暂停") {  ;取消暂停
        MySetItemPauseState(macroTableIndex, macroIndex, 0)
    }
    else if (Data.CallType == "终止") {  ;终止
        MySubMacroStopAction(macroTableIndex, macroIndex)
    }
}

OnVariable(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    LocalVariableMap := tableItem.VariableMapArr[index]
    DeleteNameArr := []
    VariableNameArr := []
    ValueArr := []
    loop 4 {
        if (!Data.ToggleArr[A_Index])
            continue
        VariableName := Data.VariableArr[A_Index]
        if (Data.OperaTypeArr[A_Index] == 5) {  ;删除
            DeleteNameArr.Push(VariableName)
            continue
        }

        Value := 0
        if (Data.OperaTypeArr[A_Index] == 1) {   ;数值
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }
        if (Data.OperaTypeArr[A_Index] == 2) {  ;随机
            hasMin := TryGetTabVarValue(&minValue, tableItem, index, Data.MinVariableArr[A_Index])
            hasMax := TryGetTabVarValue(&maxValue, tableItem, index, Data.MaxVariableArr[A_Index])
            if (!hasMin || !hasMax)
                return
            Value := Random(minValue, maxValue)
        }
        if (Data.OperaTypeArr[A_Index] == 3) {  ;字符
            Value := Data.CopyVariableArr[A_Index]
        }

        if (Data.OperaTypeArr[A_Index] == 4) {   ;系统
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }

        VariableNameArr.Push(VariableName)
        ValueArr.Push(Value)
    }

    if (DeleteNameArr.Length != 0)
        MyDelGlobalVariable(DeleteNameArr)

    if (VariableNameArr.Length != 0)
        MySetGlobalVariable(VariableNameArr, ValueArr, Data.IsIgnoreExist)
}

OnExVariable(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    count := Data.SearchCount
    interval := Data.SearchInterval

    ;变量初始化默认值0
    NameArr := []
    ValueArr := []
    loop Data.ToggleArr.Length {
        if (Data.ToggleArr[A_Index]) {
            NameArr.Push(Data.VariableArr[A_Index])
            ValueArr.Push(0)
        }
    }
    MySetGlobalVariable(NameArr, ValueArr, true)

    if (Data.SearchCount == -1) {
        return OnExVariableOnce(tableItem, index, Data)
    }
    else {
        loop Data.SearchCount {
            WaitIfPaused(tableItem, index)

            if (tableItem.KilledArr[index])
                return

            isFound := OnExVariableOnce(tableItem, index, Data)
            if (isFound)
                return

            if (Data.SearchCount > A_Index) {
                FloatInterval := GetFloatTime(Data.SearchInterval, MySoftData.PreIntervalFloat)
                Sleep(FloatInterval)
            }
        }
    }
}

OnExVariableOnce(tableItem, index, Data) {
    if (Data.ExtractType == 1) {
        HasX1 := TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
        HasY1 := TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
        HasX2 := TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
        HasY2 := TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
        if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
            return
        TextObjs := GetScreenTextObjArr(X1, Y1, X2, Y2, Data.OCRType)
        TextObjs := TextObjs == "" ? [] : TextObjs
    }
    else if (Data.ExtractType == 2) {
        TextObjs := []
        if (!IsClipboardText())
            return
        obj := Object()
        obj.Text := A_Clipboard
        TextObjs.Push(obj)
    }
    else if (Data.ExtractType == 3) {
        HasX1 := TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
        HasY1 := TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
        HasX2 := TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
        HasY2 := TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
        if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
            return
        TextObjs := []
        hwndList := GetHwndList(Data.WinInfo)
        loop hwndList.Length {
            CurWinTextObjs := GetWinTextObjArr(hwndList[A_Index], X1, Y1, X2, Y2, Data.OCRType)
            if (CurWinTextObjs != "")
                TextObjs.Push(CurWinTextObjs*)
        }
    }

    isOk := false
    allText := ""
    for index, value in TextObjs {
        allText .= value.text
        allText .= "`n"
    }
    allText := RTrim(allText, "`n")
    ExtractStr := GetReplaceVarText(tableItem, index, Data.ExtractStr)
    for _, value in TextObjs {
        VariableValueArr := ExtractVariable(value.Text, ExtractStr)
        VariableValueArr := ExtractStr == "" && allText != "" ? [allText] : VariableValueArr
        if (VariableValueArr == "")
            continue

        if (GetExVariableActiveLength(Data.ToggleArr) > VariableValueArr.Length)
            continue

        RealNameArr := []
        RealValueArr := []
        loop VariableValueArr.Length {
            if (Data.ToggleArr[A_Index]) {
                RealNameArr.Push(Data.VariableArr[A_Index])
                RealValueArr.Push(VariableValueArr[A_Index])
            }
        }
        MySetGlobalVariable(RealNameArr, RealValueArr, Data.IsIgnoreExist)
        isOk := true
        break
    }

    return isOk
}

OnOperation(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    NewNameArr := []
    NewValueArr := []
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index] || Data.ExpressionArr[A_Index] == "")
            continue

        isOk := GetExpressionResult(Data.ExpressionArr[A_Index], tableItem, index, &Res)
        if (!isOk)
            continue

        MySoftData.VariableMap[Data.UpdateNameArr[A_Index]] := res
        NewNameArr.Push(Data.UpdateNameArr[A_Index])
        NewValueArr.Push(res)
    }
    if (NewNameArr.Length > 0)
        MySetGlobalVariable(NewNameArr, NewValueArr, false)
}

OnBGMouse(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    WM_DOWN_ARR := [0x201, 0x207, 0x204]    ;左键，中键，右键
    WM_UP_ARR := [0x202, 0x208, 0x205]    ;左键，中键，右键
    WM_DCLICK_ARR := [0x203, 0x209, 0x206]    ;左键，中键，右键
    hasPosVarX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosVarX)
    hasPosVarY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosVarY)
    if (!hasPosVarX || !hasPosVarY) {
        return
    }
    PosX := GetFloatValue(PosX, MySoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MySoftData.CoordYFloat)
    hwndList := GetHwndList(Data.TargetTitle)
    loop hwndList.Length {
        hwnd := hwndList[A_Index]
        ; 点击位置（窗口客户区坐标）
        lParam := (PosY << 16) | (PosX & 0xFFFF)

        if (Data.MouseType == 4) {  ;滚轮
            if (Data.ScrollV != 0) {
                value := 120 * Data.ScrollV
                PostMessage(0x020A, (value << 16), lParam, , "ahk_id " hwnd)
            }
            else if (Data.ScrollH != 0) {
                value := 120 * Data.ScrollH
                PostMessage(0x020E, (value << 16), lParam, , "ahk_id " hwnd)
            }
            return
        }

        if (Data.OperateType == 1) {    ;点击
            PostMessage WM_DOWN_ARR[Data.MouseType], 1, lParam, , "ahk_id " hwnd
            Sleep Data.ClickTime
            PostMessage WM_UP_ARR[Data.MouseType], 0, lParam, , "ahk_id " hwnd
        }
        else if (Data.OperateType == 2) {   ;双击
            PostMessage WM_DCLICK_ARR[Data.MouseType], 1, lParam, , "ahk_id " hwnd
            Sleep Data.ClickTime
            PostMessage WM_UP_ARR[Data.MouseType], 0, lParam, , "ahk_id " hwnd
        }
        else if (Data.OperateType == 3) {   ;按下
            PostMessage WM_DOWN_ARR[Data.MouseType], 1, lParam, , "ahk_id " hwnd
        }
        else if (Data.OperateType == 4) {   ;松开
            PostMessage WM_UP_ARR[Data.MouseType], 0, lParam, , "ahk_id " hwnd
        }
    }
}

OnBGKey(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    loop Data.ClickCount {
        WaitIfPaused(tableItem, index)

        if (tableItem.KilledArr[index])
            break

        FloatHold := GetFloatTime(Data.ClickTime, MySoftData.HoldFloat)
        FloatInterval := GetFloatTime(Data.ClickInterval, MySoftData.PreIntervalFloat)
        SendBGKey(Data, tableItem, index)
        if (Data.Type == 3 && A_Index != Data.ClickCount)
            Sleep(FloatInterval)
    }
}

SendBGKey(Data, tableItem, index) {
    hwndList := GetHwndList(Data.FrontStr)

    if (Data.Type == 1 || Data.Type == 3) {
        for hwnd in hwndList {
            for key in Data.KeyArr {
                SendBGKeyState(hwnd, key, 1, tableItem, index)
            }
        }

    }

    if (Data.Type == 3) {
        Sleep(Data.ClickTime)
    }

    if (Data.Type == 2 || Data.Type == 3) {
        for hwnd in hwndList {
            for key in Data.KeyArr {
                SendBGKeyState(hwnd, key, 0, tableItem, index)
            }
        }
    }
}

SendBGKeyState(hwnd, Key, state, tableItem, index) {
    if (Key == "逗号")
        Key := ","
    VKCode := GetKeyVK(Key)
    VSCode := GetKeySC(Key)
    lParamDown := (VSCode << 16) | 1
    lParamUp := (VSCode << 16) | 0xC0000001

    if (MySoftData.OnlyDownKeyMap.Has(Key)) {
        if (state == 0)
            return
        try {
            PostMessage 0x100, VKCode, lParamDown, , "ahk_id " hwnd
        }

        return
    }

    if (state == 1) {
        try {
            PostMessage 0x100, VKCode, lParamDown, , "ahk_id " hwnd
        }
    }
    else {
        try {
            PostMessage 0x101, VKCode, lParamUp, , "ahk_id " hwnd
        }
    }

    if (state == 1) {
        tableItem.HoldKeyArr[index][Key] := "Normal"
    }
    else {
        if (tableItem.HoldKeyArr[index].Has(Key)) {
            tableItem.HoldKeyArr[index].Delete(Key)
        }
    }
}

OnMouseMove(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    PosX := Integer(paramArr[2])
    PosY := Integer(paramArr[3])
    Speed := paramArr.Length >= 4 ? 100 - Integer(paramArr[4]) : 0
    IsRelative := paramArr.Length >= 5 ? Integer(paramArr[5]) : 0

    PosX := GetFloatValue(PosX, MySoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MySoftData.CoordYFloat)
    SendMode("Event")
    CoordMode("Mouse", "Screen")
    if (IsRelative) {
        MouseMove(PosX, PosY, Speed, "R")
    }
    else {
        MouseMove(PosX, PosY, Speed)
    }
}

OnRMTCMD(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    cmdStr := paramArr[2]
    if (cmdStr == "启用键鼠") {
        BlockInput false
    }
    else if (cmdStr == "禁用键鼠") {
        BlockInput true
    }
    else {
        MyExcuteRMTCMDAction(cmd)
    }
}

OnInterval(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    isVar := !IsNumber(paramArr[2])
    interval := isVar ? 0 : Integer(paramArr[2])
    if (isVar) {
        hasInterval := TryGetTabVarValue(&interval, tableItem, index, paramArr[2])
        if (!hasInterval)
            return
    }

    FloatInterval := GetFloatTime(interval, MySoftData.IntervalFloat)
    curTime := 0
    clip := Min(100, FloatInterval)
    while (curTime < FloatInterval) {
        WaitIfPaused(tableItem, index)

        if (tableItem.KilledArr[index])
            break
        Sleep(clip)
        curTime += clip
        clip := Min(500, FloatInterval - curTime)
    }
}

OnPressKey(tableItem, cmd, index) {
    paramArr := SplitCommand(cmd)
    isJoyKey := InStr(paramArr[2], "Joy")
    isJoyAxis := InStr(paramArr[2], "JoyAxis")
    isJoyDpad := InStr(paramArr[2], "JoyDpad")
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey)
    keyTypeMap := Map("按下", 1, "松开", 2, "点击", 3)
    action := actionMap[Integer(tableItem.ModeArr[index])]
    action := isJoyKey ? SendJoyBtnKey : action
    action := isJoyAxis ? SendJoyAxisKey : action
    action := isJoyDpad ? SendJoyDpadKey : action

    keyType := keyTypeMap[paramArr[3]]
    holdTime := paramArr.Length >= 4 ? Integer(paramArr[4]) : 100
    count := paramArr.Length >= 5 ? Integer(paramArr[5]) : 1
    IntervalTime := paramArr.Length >= 6 ? Integer(paramArr[6]) : 0

    loop count {
        WaitIfPaused(tableItem, index)

        if (tableItem.KilledArr[index])
            break

        FloatHold := GetFloatTime(holdTime, MySoftData.HoldFloat)
        FloatInterval := GetFloatTime(IntervalTime, MySoftData.PreIntervalFloat)
        SendKeyWrapper(paramArr[2], FloatHold, tableItem, index, keyType, action)
        if (keyType == 3 && A_Index != count && FloatInterval > 0)
            Sleep(FloatInterval)
    }
}

;按键替换
OnReplaceDownKey(tableItem, info, index, *) {
    infos := StrSplit(info, ",")
    mode := Integer(tableItem.ModeArr[index])
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey)
    action := actionMap[mode]
    loop infos.Length {
        assistKey := infos[A_Index]
        assistKey := StrReplace(assistKey, "逗号", ",")
        action(assistKey, 1, tableItem, index)
    }
}

OnReplaceUpKey(tableItem, info, index, *) {
    infos := StrSplit(info, ",")
    mode := Integer(tableItem.ModeArr[index])
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey)
    action := actionMap[mode]
    loop infos.Length {
        assistKey := infos[A_Index]
        assistKey := StrReplace(assistKey, "逗号", ",")
        action(assistKey, 0, tableItem, index)
    }
}

;按钮回调
MenuReload(*) {
    IniWrite(MySoftData.TabCtrl.Value, IniFile, IniSection, "TableIndex")
    IniWrite(true, IniFile, IniSection, "IsReload")
    Reload()
}

OnToolTextFilterSelectImage(*) {
    global ToolCheckInfo
    path := FileSelect(, , GetLang("选择图片"))
    if (path == "")
        return
    ocr := ToolCheckInfo.OCRTypeCtrl.Value == 1 ? MyChineseOcr : MyEnglishOcr
    result := ocr.ocr_from_file(path)
    ToolCheckInfo.ToolTextCtrl.Value := result
    SetClipboard(result)
}

OnClearToolText(*) {
    ToolCheckInfo.ToolTextCtrl.Value := ""
}

OnBootStartChanged(*) {
    global MySoftData ; 访问全局变量
    MySoftData.IsBootStart := MySoftData.BootStartCtrl.Value
    regPath := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
    softPath := A_ScriptFullPath
    params := " -min"
    if (MySoftData.IsBootStart) {
        RegWrite(softPath params, "REG_SZ", regPath, "RMT")
    }
    else {
        RegDelete(regPath, "RMT")
    }
    IniWrite(MySoftData.BootStartCtrl.Value, IniFile, IniSection, "IsBootStart")
}

OnMenuWheelPosChanged(*) {
    global MySoftData ; 访问全局变量
    MySoftData.FixedMenuWheel := !MySoftData.FixedMenuWheel
    IniWrite(MySoftData.FixedMenuWheel, IniFile, IniSection, "FixedMenuWheel")
}

OnTextOps(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    switch Data.Type {
        case "文本分割":
            TextOpsSplit(Data, tableItem, index)
        case "文本提取":
            TextOpsEx(Data, tableItem, index)
        case "文本替换":
            TextOpsReplace(Data, tableItem, index)
        case "去除空格":
            TextOpsTrimSpace(Data, tableItem, index)
        case "大小写转换":
            TextOpsUpOrLow(Data, tableItem, index)
        case "文本统计":
            TextOpsStatistics(Data, tableItem, index)
    }
}

OnArray(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    ;用中文方便拓展，数值类型不好拓展
    switch Data.Type {
        case "创建":
            if (Data.IsIgnoreExist && MySoftData.ArrayMap.Has(Data.Name))
                return
            MySetGlobalArray(Data.Name, Data.InitArr)
        case "克隆":
            if (Data.IsIgnoreExist && MySoftData.ArrayMap.Has(Data.SaveName))
                return

            SourceArr := GetCmdArray(Data, tableItem, index, true)
            if (SourceArr == "")
                return

            MyCloneGlobalArray(SourceArr, Data.SaveName)
        case "删除":
            if (MySoftData.ArrayMap.Has(Data.Name))
                MyDeleteGlobalArray(Data.Name)
        case "包含":
            ArrayCheckIfContain(Data, tableItem, index)
        case "取值":
            ArrayGetIndexValue(Data, tableItem, index)
        case "赋值":
            ArrayModifyIndexValue(Data, tableItem, index)
        case "插入":
            ArrayInsertIndexValue(Data, tableItem, index)
        case "追加":
            ArrayPushValue(Data, tableItem, index)
        case "移除":
            ArrayRemoveAtIndex(Data, tableItem, index)
        case "移除最后":
            ArrayPopValue(Data, tableItem, index)
        case "反转":
            ArrayReverse(Data, tableItem, index)
        case "长度":
            ArrayGetLength(Data, tableItem, index)
    }
}

OnInput(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    switch Data.Type {
        case "弹窗":
            InputPopUp(Data, tableItem, index)
        case "状态":
            InputStateValue(Data, tableItem, index)
        case "继续":
            InputContinue(Data, tableItem, index)
        case "继续&取消":
            InputContinueAndCencel(Data, tableItem, index)
    }
}

OnFileIO(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    FilePath := GetReplaceVarText(tableItem, index, Data.FilePath)
    if (!FileExist(FilePath)) {
        MsgBox(GetLang("{}文件不存在"), FilePath)
        return
    }

    switch Data.OperType {
        case "读取Excel":
            ReadExcel(Data, tableItem, index)
        case "写入Excel":
            WriteExcel(Data, tableItem, index)
        case "读取文本文件":
            ReadTextFile(Data, tableItem, index)
        case "写入文本文件":
            WriteTextFile(Data, tableItem, index)
    }
}
