#Requires AutoHotkey v2.0

TextGetSource(Data, tableItem, index) {
    IsHas := TryGetTabVarValue(&SourceText, tableItem, index, Data.Name, false)
    SourceText := IsHas ? SourceText : Data.Name
    return SourceText
}

TextOpsSplit(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)
    IsHas := TryGetTabVarValue(&SplitArgs, tableItem, index, Data.ArgsName, false)
    SplitArgs := IsHas ? SplitArgs : Data.ArgsName

    if (Data.ArgsType == "内容分割")
        ResArr := StrSplit(SourceText, SplitArgs)
    else if (Data.ArgsType == "定长分割") {
        if (!IsInteger(SplitArgs) || SplitArgs == 0) {
            tip1 := GetLang("定长分割时参数必须是整数且大于0")
            tip2 := Format(GetLang("变量：{}   值：{}"), Data.ArgsName, SplitArgs)
            MsgBox(tip1 "`n" tip2)
            return
        }

        ResArr := TextSplitByLength(SourceText, SplitArgs)
    }
    else if (Data.ArgsType == "正则匹配") {
        try {
            ResArr := TextSplitByRegex(SourceText, SplitArgs)
        } catch as e {
            tip1 := GetLang("正则分割出错")
            tip2 := Format(GetLang("错误信息：{}"), e.Message)
            MsgBox(tip1 "`n" tip2)
            return
        }
    }
    MySetGlobalArray(Data.SaveName, ResArr)
}

TextOpsReplace(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)
    IsHas := TryGetTabVarValue(&SearchText, tableItem, index, Data.Search, false)
    SearchText := IsHas ? SearchText : Data.Search
    IsHas := TryGetTabVarValue(&ReplaceText, tableItem, index, Data.Replace, false)
    ReplaceText := IsHas ? ReplaceText : Data.Replace

    if (Data.MatchType == "正则匹配") {
        try {
            Res := RegExReplace(SourceText, SearchText, ReplaceText)
        } catch as e {
            tip1 := GetLang("正则替换出错")
            tip2 := Format(GetLang("错误信息：{}"), e.Message)
            MsgBox(tip1 "`n" tip2)
            return
        }
    } else {
        Res := StrReplace(SourceText, SearchText, ReplaceText)
    }
    MySetGlobalVariable([Data.SaveName], [Res], false)
}

TextOpsEx(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)

    if (Data.ArgsType == "数字提取") {
        ResArr := TextGetNumbers(SourceText)
    }
    else if (Data.ArgsType == "字母提取") {
        ResArr := TextGetWords(SourceText)
    }
    else if (Data.ArgsType == "中文提取") {
        ResArr := TextGetChineseBlocks(SourceText)
    }
    else if (Data.ArgsType == "正则匹配") {
        IsHas := TryGetTabVarValue(&Pattern, tableItem, index, Data.ArgsName, false)
        Pattern := IsHas ? Pattern : Data.ArgsName
        try {
            ResArr := TextGetByRegex(SourceText, Pattern)
        } catch as e {
            tip1 := GetLang("正则提取出错")
            tip2 := Format(GetLang("错误信息：{}"), e.Message)
            MsgBox(tip1 "`n" tip2)
            return
        }
    }
    MySetGlobalArray(Data.SaveName, ResArr)
}

TextOpsTrimSpace(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)

    if (Data.ArgsType == "去除前空白字符") {
        Res := LTrim(SourceText)
    }
    else if (Data.ArgsType == "去除后空白字符") {
        Res := RTrim(SourceText)
    }
    else if (Data.ArgsType == "去除前后空白字符") {
        Res := Trim(SourceText)
    }
    else if (Data.ArgsType == "去除所有空白字符") {
        Res := RegExReplace(SourceText, "\s+", "")
    }
    MySetGlobalVariable([Data.SaveName], [Res], false)
}

TextOpsUpOrLow(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)

    if (Data.ArgsType == "全部大写") {
        Res := StrUpper(SourceText)
    }
    else if (Data.ArgsType == "全部小写") {
        Res := StrLower(SourceText)
    }
    else if (Data.ArgsType == "首字母大写") {
        Res := StrTitle(SourceText)
    }
    MySetGlobalVariable([Data.SaveName], [Res], false)
}

TextOpsStatistics(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)

    if (Data.ArgsType == "字符数") {
        Res := StrLen(SourceText)
    }
    else if (Data.ArgsType == "单词数") {
        ResArr := TextGetWords(SourceText)
        Res := ResArr.Length
    }
    else if (Data.ArgsType == "行数") {
        Lines := StrSplit(SourceText, ["`r`n", "`r", "`n"])
        Res := Lines.Length
    }
    MySetGlobalVariable([Data.SaveName], [Res], false)
}

TextOpsConcat(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)
    IsHas := TryGetTabVarValue(&ConcatArgs, tableItem, index, Data.ArgsName, false)
    ConcatArgs := IsHas ? ConcatArgs : Data.ArgsName

    ResultStr := ConcatArgs
    loop 100 {
        startPos := InStr(ResultStr, "{")
        if (startPos == 0)
            break
        
        endPos := InStr(ResultStr, "}", false, startPos)
        if (endPos == 0)
            break
        
        VarName := SubStr(ResultStr, startPos + 1, endPos - startPos - 1)
        Value := "{" VarName "}"
        try {
            if (MySoftData.VariableMap.Has(VarName))
                Value := MySoftData.VariableMap[VarName]
        }
        catch {
            Value := VarName
        }
        
        Part1 := SubStr(ResultStr, 1, startPos - 1)
        Part2 := SubStr(ResultStr, endPos + 1)
        ResultStr := Part1 Value Part2
    }
    
    ResultStr := SourceText ResultStr
    MySetGlobalVariable([Data.SaveName], [ResultStr], false)
}

;辅助函数
TextSplitByLength(Text, Length) {
    ResArr := []
    CurPos := 1
    TextLen := StrLen(Text)
    while (CurPos + Length - 1 <= TextLen) {
        part := SubStr(text, CurPos, Length)
        ResArr.Push(part)
        CurPos += Length
    }
    if (CurPos <= TextLen) {
        part := SubStr(text, CurPos, TextLen - CurPos + 1)
        ResArr.Push(part)
    }
    return ResArr
}

TextGetNumbers(text) {
    result := []
    pos := 1
    while pos := RegExMatch(text, "-?\d+(?:\.\d+)?", &m, pos) {
        result.Push(m[0])
        pos += StrLen(m[0])
    }
    return result
}

TextGetWords(text) {
    result := []
    pos := 1
    while pos := RegExMatch(text, "[A-Za-z]+", &m, pos) {
        result.Push(m[0])
        pos += StrLen(m[0])
    }
    return result
}

TextGetChineseBlocks(text) {
    result := []
    pos := 1
    while pos := RegExMatch(text, "[\x{4E00}-\x{9FFF}]+", &m, pos) {
        result.Push(m[0])
        pos += StrLen(m[0])
    }
    return result
}

TextSplitByRegex(text, pattern) {
    result := []
    pos := 1
    lastEnd := 1
    while pos <= StrLen(text) && pos := RegExMatch(text, pattern, &m, pos) {
        matchPos := m.Pos[0]
        matchLen := StrLen(m[0])
        if (matchPos > lastEnd)
            result.Push(SubStr(text, lastEnd, matchPos - lastEnd))
        lastEnd := matchPos + matchLen
        pos := matchLen > 0 ? lastEnd : lastEnd + 1
    }
    if (lastEnd <= StrLen(text))
        result.Push(SubStr(text, lastEnd))
    return result
}

TextGetByRegex(text, pattern) {
    result := []
    pos := 1
    while pos := RegExMatch(text, pattern, &m, pos) {
        result.Push(m[0])
        matchLen := StrLen(m[0])
        pos += matchLen > 0 ? matchLen : 1
    }
    return result
}
