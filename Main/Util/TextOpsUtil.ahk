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
        if (!IsInteger(SplitArgs) || SplitArgs <= 0) {
            tip1 := GetLang("定长分割时参数必须是整数且大于0")
            tip2 := Format(GetLang("变量：{}   值：{}"), Data.ArgsName, SplitArgs)
            RMTErrorShow(tip1 "`n" tip2, RMT_LV_WARN, "宏")
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
            RMTErrorShow(tip1 "`n" tip2, RMT_LV_WARN, "宏")
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
            RMTErrorShow(tip1 "`n" tip2, RMT_LV_WARN, "宏")
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
            RMTErrorShow(tip1 "`n" tip2, RMT_LV_WARN, "宏")
            return
        }
    }
    MySetGlobalArray(Data.SaveName, ResArr)
}

TextOpsTypeNames() {
    return ["文本拼接", "文本分割", "文本提取", "文本替换", "时间戳处理", "去除空格", "大小写转换", "文本统计"]
}

TextOpsTimestampModes() {
    return ["自定义格式", "提取时间量", "提取所有时间量", "日期时间", "日期", "时刻"]
}

TextOpsTimestampPresetFormat(mode) {
    switch mode {
        case "日期时间": return "yyyy-MM-dd HH:mm:ss"
        case "日期": return "yyyy-MM-dd"
        case "时刻": return "HH:mm:ss"
    }
    return ""
}

TextOpsTimestampComponents() {
    return [
        ["年", "YYYY", "年份", 1, 4, "-"],
        ["月", "MM", "月份", 5, 2, "-"],
        ["日", "DD", "日号", 7, 2, " "],
        ["时", "HH", "小时", 9, 2, ":"],
        ["分", "mm", "分钟", 11, 2, ":"],
        ["秒", "ss", "秒钟", 13, 2, ""],
        ["毫秒", "fff", "毫秒", 0, 3, ""]
    ]
}

TextOpsTimestampComponentIndex(componentName) {
    for i, component in TextOpsTimestampComponents() {
        if (component[1] == componentName)
            return i - 1
    }
    return 0
}

TextOpsTimestampComponentLabels() {
    labels := []
    for component in TextOpsTimestampComponents() {
        label := GetLang(component[3])
        labels.Push(label == component[3] ? component[1] : label)
    }
    return labels
}

TextOpsTimestampFormatParts(data) {
    components := TextOpsTimestampComponents()
    parts := []
    seen := Map()
    if (data.HasOwnProp("TimestampFormatParts") && data.TimestampFormatParts is Array) {
        for part in data.TimestampFormatParts {
            if (!IsObject(part) || !part.HasOwnProp("Index") || !part.HasOwnProp("Enabled") || !part.HasOwnProp("Suffix"))
                continue
            if (!IsInteger(part.Index) || part.Index < 1 || part.Index > components.Length || seen.Has(part.Index))
                continue
            parts.Push({Index: part.Index, Enabled: part.Enabled, Suffix: components[part.Index][1] == "毫秒" ? "" : part.Suffix})
            seen[part.Index] := true
        }
    }
    for i, component in components {
        if (!seen.Has(i))
            parts.Push({Index: i, Enabled: component[1] != "毫秒", Suffix: component[6]})
    }
    return parts
}

TextOpsResultType(type, mode) {
    return (type == "文本分割" || type == "文本提取" || (type == "时间戳处理" && mode == "提取所有时间量"))
        ? "数组" : "变量"
}

TextOpsTimestamp(data, tableItem, index) {
    source := Trim(data.Name)
    if (RegExMatch(source, "^\{([^{}]+)\}$", &reference) && GetLangKey(reference[1]) == "当前时间戳")
        source := "当前时间戳"
    epochMs := TimeEpochMilliseconds(TimeResolveValue(tableItem, index, source))
    if (epochMs == "") {
        RMTErrorShow(GetLang("无效的时间戳"), RMT_LV_WARN, "宏")
        return
    }
    stamp := StampToTimeStr(epochMs)
    components := TextOpsTimestampComponents()
    fields := []
    for component in components
        fields.Push(component[4] ? SubStr(stamp, component[4], component[5]) : Format("{:03}", Mod(epochMs, 1000)))

    switch data.ArgsType {
        case "提取时间量":
            result := Integer(fields[TextOpsTimestampComponentIndex(data.ArgsName) + 1])
        case "提取所有时间量":
            values := []
            for field in fields
                values.Push(Integer(field))
            MySetGlobalArray(data.SaveName, values)
            return
        case "自定义格式":
            result := ""
            for part in TextOpsTimestampFormatParts(data) {
                if (part.Enabled)
                    result .= fields[part.Index] part.Suffix
            }
        default:
            preset := TextOpsTimestampPresetFormat(data.ArgsType)
            result := FormatTime(stamp, preset != "" ? preset : TextOpsTimestampPresetFormat("日期时间"))
    }
    MySetGlobalVariable([data.SaveName], [result], false)
}

TextOpsTrimSpace(Data, tableItem, index) {
    SourceText := TextGetSource(Data, tableItem, index)

    if (Data.ArgsType == "去除前空白字符") {
        Res := RegExReplace(SourceText, "^\s+", "")
    }
    else if (Data.ArgsType == "去除后空白字符") {
        Res := RegExReplace(SourceText, "\s+$", "")
    }
    else if (Data.ArgsType == "去除前后空白字符") {
        Res := RegExReplace(SourceText, "^\s+|\s+$", "")
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
    IsHas := TryGetTabVarValue(&ConcatArgs, tableItem, index, Data.ArgsName, false)
    ConcatArgs := IsHas ? ConcatArgs : Data.ArgsName

    ResultStr := ConcatArgs
    GetSmartReplaceVarText(tableItem, index, &ResultStr)
    
    if (Data.Name != "") {
        SourceText := TextGetSource(Data, tableItem, index)
        ResultStr := SourceText ResultStr
    }
    MySetGlobalVariable([Data.SaveName], [ResultStr], false)
}

;辅助函数
TextSplitByLength(Text, Length) {
    if (!IsInteger(Length) || Length <= 0)
        throw ValueError("定长分割时参数必须是整数且大于0")
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
    while pos <= StrLen(text) + 1 && pos := RegExMatch(text, pattern, &m, pos) {
        result.Push(m[0])
        matchLen := StrLen(m[0])
        pos += matchLen > 0 ? matchLen : 1
    }
    return result
}
