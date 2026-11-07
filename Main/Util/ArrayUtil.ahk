#Requires AutoHotkey v2.0

; 数组配置与运行数据、克隆结果之间不能共享内层数组。
CloneArray(DataArray) {
    Result := DataArray.Clone()
    loop DataArray.Length {
        if (DataArray.Has(A_Index) && DataArray[A_Index] is Array)
            Result[A_Index] := CloneArray(DataArray[A_Index])
    }
    return Result
}

GetArrayStr(DataArray) {
    ResText := ""
    for Index, Value in DataArray {
        if (Index > 1)
            ResText .= ","
        if (Value is Array)
            ResText .= "[" GetArrayStr(Value) "]"
        else if (Value == "" && DataArray.Length == 1)
            ; 区分空数组与仅有一个空字符串的数组；字面量 \e 的反斜杠会先转义。
            ResText .= "\e"
        else {
            curText := StrReplace(Value, "\", "\\")
            for Char in [",", "，", "[", "]", "【", "】"]
                curText := StrReplace(curText, Char, "\" Char)
            ResText .= curText
        }
    }
    return ResText
}

GetArray(Text) {
    ResArr := []
    if (Text == "")
        return ResArr
    Pos := 1
    Length := StrLen(Text)
    while (Pos <= Length) {
        Char := SubStr(Text, Pos, 1)
        if (Char == "[" || Char == "【") {
            EndPos := GetArrayEndPos(Text, Pos - 1)
            if (!EndPos)
                throw ValueError("数组括号未闭合或不匹配",, Text)
            ResArr.Push(GetArray(SubStr(Text, Pos + 1, EndPos - Pos - 1)))
            Pos := EndPos + 1
            if (Pos <= Length && !InStr(",，", SubStr(Text, Pos, 1)))
                throw ValueError("子数组后缺少分隔符",, Text)
        } else {
            EndPos := GetNextSplitPos(Text, Pos - 1)
            if (!EndPos)
                EndPos := Length + 1
            ResArr.Push(GetEscapeValue(SubStr(Text, Pos, EndPos - Pos)))
            Pos := EndPos
        }
        ; 每次处理一个完整元素；末尾分隔符保留一个空元素。
        if (Pos == Length)
            ResArr.Push("")
        Pos++
    }
    return ResArr
}

IsArrayEscapeChar(Char) {
    return Char != "" && InStr("\,，[]【】e", Char, true) != 0
}

GetNextSplitPos(Text, StartPos) {
    Pos := StartPos + 1
    while (Pos <= StrLen(Text)) {
        Char := SubStr(Text, Pos, 1)
        if (Char == "\" && IsArrayEscapeChar(SubStr(Text, Pos + 1, 1)))
            Pos += 2
        else if (Char == "," || Char == "，")
            return Pos
        else
            Pos++
    }
    return 0
}

GetArrayEndPos(Text, StartPos) {
    Closers := []
    Pos := StartPos + 1
    while (Pos <= StrLen(Text)) {
        Char := SubStr(Text, Pos, 1)
        if (Char == "\" && IsArrayEscapeChar(SubStr(Text, Pos + 1, 1))) {
            Pos += 2
            continue
        }
        if (Char == "[" || Char == "【")
            Closers.Push(Char == "[" ? "]" : "】")
        else if (Char == "]" || Char == "】") {
            if (!Closers.Length || Closers.Pop() != Char)
                return 0
            if (!Closers.Length)
                return Pos
        }
        Pos++
    }
    return 0
}

; 一次扫描完成反转义，不用占位符，避免真实文本 ⎖ 或二次替换损坏数据。
GetEscapeValue(Value) {
    if (Value == "\e")
        return ""
    Result := ""
    Pos := 1
    while (Pos <= StrLen(Value)) {
        Char := SubStr(Value, Pos, 1)
        NextChar := SubStr(Value, Pos + 1, 1)
        if (Char == "\" && NextChar != "e" && IsArrayEscapeChar(NextChar)) {
            Result .= NextChar
            Pos += 2
        } else {
            Result .= Char
            Pos++
        }
    }
    return Result
}

GetGuiArrNameArr() {
    ResultArr := []
    for Key in MySoftData.GlobalArrMap {
        ResultArr.Push(Key)
    }
    return ResultArr
}

TryGetArrValue(&ResArr, ArrName, variTip := true) {
    if (!MySoftData.ArrayMap.Has(ArrName)) {
        if (variTip && MainSoftData.NoVariableTip)
            RMTErrorShow(GetLang("当前环境不存在数组") ArrName, RMT_LV_WARN, "宏")
        return false
    }

    ResArr := MySoftData.ArrayMap[ArrName]
    return true
}

GetCmdArray(Data, tableItem, index, variTip := true) {
    if (!MySoftData.ArrayMap.Has(Data.Name)) {
        if (variTip && MainSoftData.NoVariableTip)
            RMTErrorShow(GetLang("当前环境不存在数组") Data.Name, RMT_LV_WARN, "宏")
        return ""
    }

    ResArr := MySoftData.ArrayMap[Data.Name]
    if (Data.MainIndex != 0) {
        isHas := TryGetTabVarValue(&Value, tableItem, index, Data.MainIndex, variTip)
        if (!isHas)
            return ""

        if (IsInteger(Value) && Value == 0)
            return ResArr
        if (!ArrayIndexInRange(Value, ResArr.Length)) {
            if (variTip && MainSoftData.NoVariableTip) {
                str1 := Format(GetLang("数组：{}  长度：{}"), Data.Name, ResArr.Length)
                str2 := Format("无法获取第{}的值", Value)
                RmtDialog.Info(str1 "`n" str2)
            }
            return ""
        }
        ResArr := ResArr[Value]
    }

    if (Data.MainIndex != 0 && !IsObject(ResArr)) {
        if (variTip && MainSoftData.NoVariableTip) {
            str1 := Format(GetLang("数组：{}  第{}个值不是数组"), Data.Name, Value)
            RmtDialog.Info(str1)
        }
        return ""
    }
    return ResArr
}

ArrayIndexInRange(index, length, allowEnd := false) {
    return IsInteger(index) && index != 0 && index >= -length && index <= length + (allowEnd ? 1 : 0)
}

SetArrayDataNewArr(Data) {
    NewArrName := ""
    if (Data.Type == "创建")
        NewArrName := Data.Name
    else if (Data.Type == "克隆") {
        NewArrName := Data.SaveName
    }
    else if (Data.Type == "取值" || Data.Type == "移除" || Data.Type == "移除最后") {
        if (Data.SaveType == "数组")
            NewArrName := Data.SaveName
    }

    if (NewArrName != "")
        MySoftData.GlobalArrMap[NewArrName] := true
}

SetArrayDataNewVar(Data) {
    NewVarName := ""
    if (Data.Type == "包含" || Data.Type == "长度")
        NewVarName := Data.SaveName
    else if (Data.Type == "取值" || Data.Type == "移除" || Data.Type == "移除最后") {
        if (Data.SaveType == "变量")
            NewVarName := Data.SaveName
    }

    if (NewVarName != "")
        MySoftData.GlobalVariMap[NewVarName] := true
}

ArrayCheckIfContain(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    if (Data.ArgsType == "变量或值") {
        isHas := TryGetTabVarValue(&Value, tableItem, index, Data.ArgsName, true)
        if (!isHas)
            return

        Res := 0
        loop SourceArr.Length {
            if (SourceArr[A_Index] == Value) {
                Res := 1
                break
            }
        }
    }
    else if (Data.ArgsType == "数组") {
        if (!MySoftData.ArrayMap.Has(Data.ArgsName)) {
            if (MainSoftData.NoVariableTip)
                RMTErrorShow(GetLang("当前环境不存在数组") Data.Name, RMT_LV_WARN, "宏")
            return
        }

        Res := 0
        ArgsStr := GetArrayStr(MySoftData.ArrayMap[Data.ArgsName])
        loop SourceArr.Length {
            if (IsObject(SourceArr[A_Index])) {
                if (GetArrayStr(SourceArr[A_Index]) == ArgsStr) {
                    Res := 1
                    break
                }
            }
        }
    }
    MySetGlobalVariable([Data.SaveName], [Res], false)
}

ArrayGetIndexValue(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    TryGetTabVarValue(&MainIndex, tableItem, index, Data.MainIndex, false)
    isHas := TryGetTabVarValue(&GetIndex, tableItem, index, Data.ArgsIndex, true)
    if (!isHas)
        return

    if (!ArrayIndexInRange(GetIndex, SourceArr.Length)) {
        if (MainSoftData.NoVariableTip) {
            tip1 := Format(GetLang("数组：{} 长度：{}"), Data.Name, SourceArr.Length)
            tip2 := Format(GetLang("数组：{}  子数组{}  长度：{}"), Data.Name, MainIndex, SourceArr.Length)
            str1 := MainIndex == 0 ? tip1 : tip2
            str2 := Format("无法获取第{}的值", GetIndex)
            RmtDialog.Info(str1 "`n" str2)
        }
        return ""
    }
    Value := SourceArr[GetIndex]

    if (Data.SaveType == "变量")
        MySetGlobalVariable([Data.SaveName], [Value], false)
    else if (Data.SaveType == "数组")
        MySetGlobalArray(Data.SaveName, Value)
}

ArrayModifyIndexValue(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    TryGetTabVarValue(&MainIndex, tableItem, index, Data.MainIndex, false)
    isHas := TryGetTabVarValue(&SetIndex, tableItem, index, Data.ArgsIndex, true)
    if (!isHas)
        return

    if (!ArrayIndexInRange(SetIndex, SourceArr.Length)) {
        if (MainSoftData.NoVariableTip) {
            tip1 := Format(GetLang("数组：{} 长度：{}"), Data.Name, SourceArr.Length)
            tip2 := Format(GetLang("数组：{}  子数组{}  长度：{}"), Data.Name, MainIndex, SourceArr.Length)
            str1 := MainIndex == 0 ? tip1 : tip2
            str2 := Format("无法修改第{}的值", SetIndex)
            RmtDialog.Info(str1 "`n" str2)
        }
        return ""
    }

    if (Data.ArgsType == "变量或值") {
        isHas := TryGetTabVarValue(&Value, tableItem, index, Data.ArgsName, true)
        if (!isHas)
            return
        MyModifyGlobalArray(Data.Name, MainIndex, SetIndex, 0, Value)
    }
    else if (Data.ArgsType == "数组") {
        if (!MySoftData.ArrayMap.Has(Data.ArgsName)) {
            if (MainSoftData.NoVariableTip)
                RMTErrorShow(GetLang("当前环境不存在数组") Data.Name, RMT_LV_WARN, "宏")
            return
        }
        Value := MySoftData.ArrayMap[Data.ArgsName]
        MyModifyGlobalArray(Data.Name, MainIndex, SetIndex, 1, Value)
    }
}

ArrayInsertIndexValue(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    TryGetTabVarValue(&MainIndex, tableItem, index, Data.MainIndex, false)
    isHas := TryGetTabVarValue(&InsertIndex, tableItem, index, Data.ArgsIndex, true)
    if (!isHas)
        return

    if (!ArrayIndexInRange(InsertIndex, SourceArr.Length, true)) {
        if (MainSoftData.NoVariableTip) {
            TryGetTabVarValue(&SubIndex, tableItem, index, Data.MainIndex, false)
            tip1 := Format(GetLang("数组：{} 长度：{}"), Data.Name, SourceArr.Length)
            tip2 := Format(GetLang("数组：{}  子数组{}  长度：{}"), Data.Name, SubIndex, SourceArr.Length)
            str1 := SubIndex == 0 ? tip1 : tip2
            str2 := Format("无法在第{}位置插入数据", InsertIndex)
            RmtDialog.Info(str1 "`n" str2)
        }
        return ""
    }

    if (Data.ArgsType == "变量或值") {
        isHas := TryGetTabVarValue(&Value, tableItem, index, Data.ArgsName, true)
        if (!isHas)
            return
        MyInsertGlobalArray(Data.Name, MainIndex, InsertIndex, 0, Value)
    }
    else if (Data.ArgsType == "数组") {
        if (!MySoftData.ArrayMap.Has(Data.ArgsName)) {
            if (MainSoftData.NoVariableTip)
                RMTErrorShow(GetLang("当前环境不存在数组") Data.Name, RMT_LV_WARN, "宏")
            return
        }
        Value := MySoftData.ArrayMap[Data.ArgsName]
        MyInsertGlobalArray(Data.Name, MainIndex, InsertIndex, 1, Value)
    }
}

ArrayPushValue(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    PushIndex := SourceArr.Length + 1
    TryGetTabVarValue(&MainIndex, tableItem, index, Data.MainIndex, false)
    if (Data.ArgsType == "变量或值") {
        isHas := TryGetTabVarValue(&Value, tableItem, index, Data.ArgsName, true)
        if (!isHas)
            return
        MyInsertGlobalArray(Data.Name, MainIndex, PushIndex, 0, Value)
    }
    else if (Data.ArgsType == "数组") {
        if (!MySoftData.ArrayMap.Has(Data.ArgsName)) {
            if (MainSoftData.NoVariableTip)
                RMTErrorShow(GetLang("当前环境不存在数组") Data.Name, RMT_LV_WARN, "宏")
            return
        }
        Value := MySoftData.ArrayMap[Data.ArgsName]
        MyInsertGlobalArray(Data.Name, MainIndex, PushIndex, 1, Value)
    }
}

ArrayRemoveAtIndex(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    isHas := TryGetTabVarValue(&RemoveIndex, tableItem, index, Data.ArgsIndex, true)
    if (!isHas)
        return

    TryGetTabVarValue(&MainIndex, tableItem, index, Data.MainIndex, false)
    if (!ArrayIndexInRange(RemoveIndex, SourceArr.Length)) {
        if (MainSoftData.NoVariableTip) {
            tip1 := Format(GetLang("数组：{} 长度：{}"), Data.Name, SourceArr.Length)
            tip2 := Format(GetLang("数组：{}  子数组{}  长度：{}"), Data.Name, MainIndex, SourceArr.Length)
            str1 := MainIndex == 0 ? tip1 : tip2
            str2 := Format("无法移除第{}位置的数据", RemoveIndex)
            RmtDialog.Info(str1 "`n" str2)
        }
        return
    }
    Value := SourceArr[RemoveIndex]
    MyRemoveAtGlobalArray(Data.Name, MainIndex, RemoveIndex)

    if (Data.SaveType == "变量")
        MySetGlobalVariable([Data.SaveName], [Value], false)
    else if (Data.SaveType == "数组")
        MySetGlobalArray(Data.SaveName, Value)
}

ArrayPopValue(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return
    if (SourceArr.Length == 0) {
        if (MainSoftData.NoVariableTip) {
            tip1 := Format(GetLang("数组：{} 长度：{}"), Data.Name, SourceArr.Length)
            tip2 := Format(GetLang("数组：{}  子数组{}  长度：{}"), Data.Name, MainIndex, SourceArr.Length)
            str1 := MainIndex == 0 ? tip1 : tip2
            str2 := Format("无法移除末尾的数据")
            RmtDialog.Info(str1 "`n" str2)
        }
        return
    }

    TryGetTabVarValue(&MainIndex, tableItem, index, Data.MainIndex, false)
    Value := SourceArr[SourceArr.Length]
    MyRemoveAtGlobalArray(Data.Name, MainIndex, SourceArr.Length)

    if (Data.SaveType == "变量")
        MySetGlobalVariable([Data.SaveName], [Value], false)
    else if (Data.SaveType == "数组")
        MySetGlobalArray(Data.SaveName, Value)
}

ArrayReverse(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    ResArr := []
    loop SourceArr.Length {
        Value := SourceArr[SourceArr.Length - A_Index + 1]
        ResArr.Push(Value)
    }

    MySetGlobalArray(Data.SaveName, ResArr)
}

ArrayGetLength(Data, tableItem, index) {
    SourceArr := GetCmdArray(Data, tableItem, index, true)
    if (SourceArr == "")
        return

    Value := SourceArr.Length
    MySetGlobalVariable([Data.SaveName], [Value], false)
}

ArrayTrimRightNull(Arr) {
    if (!IsObject(Arr))
        return
    loop {
        if (Arr.Length == 0 || Arr[Arr.Length] != "")
            return

        Arr.Pop()
    }
}
