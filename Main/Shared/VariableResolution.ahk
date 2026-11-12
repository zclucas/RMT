GetReplaceVarText(tableItem, tableIndex, text) {
    matches := []      ; 存储变量名（不含花括号）
    arrayMatches := [] ; 存储数组名（不含花括号和ε）
    pos := 1

    ; 匹配 {xxx} 或 {εxxx}
    while (pos := RegExMatch(text, "\{([^{}]*?)\}", &match, pos)) {
        content := match[1]
        if (RegExMatch(content, "^ε(.+)$", &arrMatch)) {     ; 以ε开头 -> 数组
            arrayMatches.Push(arrMatch[1])
        } else {        ; 普通变量
            matches.Push(content)
        }
        pos += match.Len
    }

    ResText := text
    ; 替换普通变量
    for index, value in matches {
        hasValue := TryGetTabVarValue(&variValue, tableItem, tableIndex, value, true)
        if (hasValue)
            ResText := StrReplace(ResText, "{" value "}", variValue)
    }

    ; 替换数组变量（去掉花括号和ε）
    for index, arrName in arrayMatches {
        if (MySoftData.ArrayMap.Has(arrName)) {
            arrValue := GetArrayStr(MySoftData.ArrayMap[arrName])
            ResText := StrReplace(ResText, "{ε" arrName "}", arrValue)
        }
    }

    return ResText
}

; ──────────────────────────────────────────────────────────────────────
; 解析變量並執行實際替換（作用於「存儲格式」文字）
;
;   1. {var} -> var值
;   2. /{    -> {
;   3. /}    -> }
; ──────────────────────────────────────────────────────────────────────
GetSmartReplaceVarText(tableItem, index, &text) {
    static ESC_L := Chr(0xE001)
    static ESC_R := Chr(0xE002)

    ; 先保護字面量花括號
    text := StrReplace(text, "/{", ESC_L)
    text := StrReplace(text, "/}", ESC_R)

    result := ""
    pos := 1
    len := StrLen(text)

    while (pos <= len) {
        openPos := InStr(text, "{", false, pos)

        if (!openPos) {
            result .= SubStr(text, pos)
            break
        }

        ; 加入 { 前面的文字
        if (openPos > pos)
            result .= SubStr(text, pos, openPos - pos)

        ; 找對應的 }
        closePos := InStr(text, "}", false, openPos + 1)

        if (!closePos) {
            ; 沒有完整的 {xxx}，原樣保留後面內容
            result .= SubStr(text, openPos)
            break
        }

        varName := SubStr(text, openPos + 1, closePos - openPos - 1)
        varValue := ""

        ; 直接使用 TryGetTabVarValue
        if (TryGetTabVarValue(&varValue, tableItem, index, varName, true)) {
            result .= varValue
        } else {
            ; 非變量，原樣保留
            result .= SubStr(text, openPos, closePos - openPos + 1)
        }

        pos := closePos + 1
    }

    ; 還原一般花括號
    result := StrReplace(result, ESC_L, "{")
    result := StrReplace(result, ESC_R, "}")

    text := result
}

TryGetVarValue(&Value, varName, variTip := true, tableVarMap := Map(), allowLiteral := true) {

    if (allowLiteral && RegExMatch(varName, "^[0-9A-Fa-f]{6}$")) {
        Value := varName
        return true
    }

    if (allowLiteral && IsNumber(varName)) {
        Value := Number(varName)
        return true
    }

    switch varName {
        case "当前鼠标坐标X", "当前鼠标坐标Y", "当前坐标X", "当前坐标Y":
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            Value := (varName == "当前鼠标坐标X" || varName == "当前坐标X") ? mouseX : mouseY
            return true
        case "当前日期":
            Value := FormatTime(A_Now, "yyyy-MM-dd")
            return true
        case "当前时间":
            Value := FormatTime(A_Now, "HH:mm")
            return true
        case "当前时间(秒)":
            Value := FormatTime(A_Now, "HH:mm:ss")
            return true
        case "当前秒":
            Value := A_Sec
            return true
        case "当前星期几", "当前星期":
            Value := A_WDay == 1 ? 7 : A_WDay - 1
            return true
        case "当前周":
            Value := Integer(SubStr(A_YWeek, 5))
            return true
        ; §21 数值型时间变量（旧「当前时间/当前秒」字符串型不再列出，此处保留兼容）
        case "当前时间戳":
            Value := UnixNow()
            return true
        case "当前年":
            Value := A_YYYY
            return true
        case "当前月":
            Value := A_MM
            return true
        case "当前日":
            Value := A_DD
            return true
        case "当前时":
            Value := A_Hour
            return true
        case "当前分":
            Value := A_Min
            return true
        case "当前剪切板":
            ; 仅剪切板是文本时取值；图片/文件等非文本，或没有文本内容时为「空」
            Value := "空"
            if (DllCall("IsClipboardFormatAvailable", "UInt", 13) || DllCall("IsClipboardFormatAvailable", "UInt", 1)) {
                try {
                    clipText := A_Clipboard
                    if (Type(clipText) == "String" && clipText != "")
                        Value := clipText
                }
            }
            return true
        case "当前鼠标颜色":
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            Value := StrReplace(Color, "0x", "")
            return true
        case "句柄ID":
            winId := 0
            try {
                CoordMode("Mouse", "Screen")
                MouseGetPos &mouseX, &mouseY, &winId
            }
            Value := winId
            return true
    }

    if (tableVarMap.Has(varName)) {
        Value := tableVarMap[varName]
        return true
    }

    GlobalVariableMap := MySoftData.VariableMap
    if (GlobalVariableMap.Has(varName)) {
        Value := GlobalVariableMap[varName]
        return true
    }

    if (variTip)
        ShowNoVariableTip(varName)
    return false
}

TryGetTabVarValue(&Value, tableItem, index, varName, variTip := true, allowLiteral := true) {
    item := tableItem.Items[index]
    if (!item)
        return false
    return TryGetVarValue(&Value, varName, variTip, item.VariableMap, allowLiteral)
}

ShowNoVariableTip(VarName) {
    if (MainSoftData.NoVariableTip) {
        str1 := GetLang("当前环境不存在变量") VarName
        str2 := Format(GetLang("tip1:请确保有创建变量-{}的相关指令"), VarName)
        str3 := Format(GetLang("tip2:请确保上述指令运行过"))
        RMTErrorShow(Format("{}`n{}`n{}", str1, str2, str3), RMT_LV_WARN, "宏")
    }
}

GetBrightness() {
    wmi := ComObjGet("winmgmts:\\.\root\WMI")
    itmes := wmi.ExecQuery("SELECT * FROM WmiMonitorBrightness")
    for item in itmes {
        return item.CurrentBrightness
    }
    return 20
}

GetSystemVarArr() {
    return [GetLang("循环次数"), GetLang("宏循环次数"), GetLang("句柄ID"), GetLang("当前鼠标颜色"),
    GetLang("当前坐标X"), GetLang("当前坐标Y"), GetLang("当前剪切板"), GetLang("当前时间戳")]
}

GetTimeCategoryVarArr() {
    return [GetLang("当前年"), GetLang("当前月"), GetLang("当前周"), GetLang("当前星期"), GetLang("当前日"),
    GetLang("当前时"), GetLang("当前分"), GetLang("当前秒")]
}

; 系统 + 时间（去重），用于保留名、多语言替换、变量下拉「所有」
GetSpecialVarArr() {
    seen := Map()
    arr := []
    extra := [GetLang("当前鼠标坐标X"), GetLang("当前鼠标坐标Y")]
    for src in [GetSystemVarArr(), GetTimeCategoryVarArr(), extra] {
        for v in src {
            if (v != "" && !seen.Has(v)) {
                seen[v] := true
                arr.Push(v)
            }
        }
    }
    return arr
}

IsTimeCategoryName(name) {
    if (name == "")
        return false
    key := GetLangKey(name)
    for v in GetTimeCategoryVarArr() {
        if (name == v || key == v || key == GetLangKey(v))
            return true
    }
    return false
}

IsTimeVar(name) {
    return (name != "" && IsObject(MySoftData) && MySoftData.HasOwnProp("TimeVarMap") && (MySoftData.TimeVarMap.Has(name) || MySoftData.TimeVarMap.Has(GetLangKey(name))))
}


DoCompare(&currentComparison, tableItem, index, CompareType, Name, OtherValue) {
    CompareType := CmdEnumCompare(CompareType)
    if (CompareType == "变量存在") {
        hasValue := TryGetTabVarValue(&Value, tableItem, index, Name, false)
        currentComparison := hasValue
        return true
    }

    hasValue := TryGetTabVarValue(&Value, tableItem, index, Name)
    if (!hasValue)
        return false

    if (CompareType == "等于" || CompareType == "字符包含" || CompareType == "正则匹配" || CompareType == "不等于") {
        hasOtherValue := TryGetTabVarValue(&OtherVal, tableItem, index, OtherValue, false)
        OtherVal := hasOtherValue ? OtherVal : OtherValue
        hasOtherValue := true
    }
    else {
        hasOtherValue := TryGetTabVarValue(&OtherVal, tableItem, index, OtherValue)
    }

    if (!hasOtherValue)
        return false

    switch CompareType {
        case "大于": currentComparison := Value > OtherVal
        case "大于等于": currentComparison := Value >= OtherVal
        case "等于": currentComparison := Value == OtherVal
        case "小于等于": currentComparison := Value <= OtherVal
        case "小于": currentComparison := Value < OtherVal
        case "字符包含": currentComparison := FindRegexMatchPosition(Value, OtherVal)
        case "正则匹配": currentComparison := RegExMatch(Value, OtherVal)
        case "不等于": currentComparison := Value != OtherVal
        default: currentComparison := false
    }
    return true
}

HandleControlType(tableItem, index, ControlType) {
    item := tableItem.Items[index]
    if (!item)
        return
    switch (ControlType) {
        case "循环-跳过本轮":
            item.VariableMap["循环-跳过本轮"] := true
        case "循环-跳出":
            item.VariableMap["循环-跳出"] := true
        case "分支-跳出":
            item.VariableMap["分支-跳出"] := true
    }
}
