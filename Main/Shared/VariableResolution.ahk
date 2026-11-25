GetReplaceVarText(tableItem, tableIndex, text, variTip := true) {
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
        hasValue := TryGetTabVarValue(&variValue, tableItem, tableIndex, value, variTip)
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
    if (SubStr(varName, 1, 1) == "❖")
        varName := GetBuiltinVarName(varName)
    varName := LegacyRuntimeVarNames().Get(varName, varName)

    if (allowLiteral && RegExMatch(varName, "^[0-9A-Fa-f]{6}$")) {
        Value := varName
        return true
    }

    if (allowLiteral && IsNumber(varName)) {
        Value := Number(varName)
        return true
    }

    switch varName {
        case "运行时坐标X", "运行时坐标Y":
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            Value := varName == "运行时坐标X" ? mouseX : mouseY
            return true
        case "运行时窗口坐标X", "运行时窗口坐标Y":
            pos := GetCurWinPos()
            Value := pos[varName == "运行时窗口坐标X" ? 1 : 2]
            return true
        case "日期文本":
            Value := FormatTime(A_Now, "yyyy-MM-dd")
            return true
        case "时分文本":
            Value := FormatTime(A_Now, "HH:mm")
            return true
        case "时分秒文本":
            Value := FormatTime(A_Now, "HH:mm:ss")
            return true
        case "运行时秒":
            Value := A_Sec
            return true
        case "运行时星期":
            Value := A_WDay == 1 ? 7 : A_WDay - 1
            return true
        case "运行时周":
            Value := Integer(SubStr(A_YWeek, 5))
            return true
        case "运行时时间戳":
            Value := UnixNow()
            return true
        case "运行时年":
            Value := A_YYYY
            return true
        case "运行时月":
            Value := A_MM
            return true
        case "运行时日":
            Value := A_DD
            return true
        case "运行时时":
            Value := A_Hour
            return true
        case "运行时分":
            Value := A_Min
            return true
        case "运行时剪切板":
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
        case "运行时鼠标颜色":
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            Value := StrReplace(Color, "0x", "")
            return true
        case "运行时句柄ID":
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

; 旧名称只用于配置迁移和运行兼容，不再出现在变量选项中。
LegacyRuntimeVarNames() {
    static names := Map("句柄ID", "运行时句柄ID",
        "当前坐标X", "运行时坐标X", "当前坐标Y", "运行时坐标Y",
        "当前鼠标颜色", "运行时鼠标颜色", "当前剪切板", "运行时剪切板",
        "当前时间戳", "运行时时间戳", "当前年", "运行时年", "当前月", "运行时月",
        "当前周", "运行时周", "当前星期", "运行时星期", "当前日", "运行时日",
        "当前时", "运行时时", "当前分", "运行时分", "当前秒", "运行时秒")
    return names
}

GetBuiltinVarGroups() {
    static groups := Map(
        "count", ["循环次数", "宏循环次数"],
        "x", ["运行时坐标X", "运行时窗口坐标X"],
        "y", ["运行时坐标Y", "运行时窗口坐标Y"],
        "handle", ["运行时句柄ID"],
        "color", ["运行时鼠标颜色"],
        "clipboard", ["运行时剪切板"],
        "timestamp", ["运行时时间戳"],
        "calendar", ["运行时年", "运行时月", "运行时周", "运行时星期", "运行时日"],
        "hour", ["运行时时"],
        "minute", ["运行时分"],
        "second", ["运行时秒"],
        "dateText", ["日期文本"],
        "clockText", ["时分文本", "时分秒文本"]
    )
    return groups
}

GetBuiltinVarNames(categories*) {
    names := []
    for category in categories {
        for name in GetBuiltinVarGroups()[category]
            names.Push("❖" GetLang(name))
    }
    return names
}

GetSystemVarArr() {
    return GetBuiltinVarNames("count", "handle", "color", "x", "y", "clipboard", "timestamp")
}

GetTimeCategoryVarArr() {
    return GetBuiltinVarNames("calendar", "hour", "minute", "second", "dateText", "clockText")
}

; 保留名、多语言替换和通用文本插入使用完整列表。
GetSpecialVarArr() {
    names := GetSystemVarArr()
    names.Push(GetTimeCategoryVarArr()*)
    return names
}

; 在可同时输入字面值和变量名的字段里，只转换内置变量名。
GetBuiltinVarName(value, toDisplay := false) {
    static names := []
    if (names.Length == 0) {
        for _, keys in GetBuiltinVarGroups()
            names.Push(keys*)
    }
    keys := names.Clone()
    for old in LegacyRuntimeVarNames()
        keys.Push(old)
    original := value
    marked := SubStr(value, 1, 1) == "❖"
    if (marked)
        value := SubStr(value, 2)
    key := GetConfigKey(value, keys)
    key := LegacyRuntimeVarNames().Get(key, key)
    for name in names {
        if (name == key)
            return toDisplay ? "❖" GetLang(key) : key
    }
    return marked ? original : key
}

; 仅在候选列表确实包含系统变量时转换回显，保存变量名和普通文本不受影响。
GetVariableComboText(items, value) {
    display := GetBuiltinVarName(value, true)
    reference := TranslateBuiltinVarReferences(value, true)
    for item in items {
        if (item == display)
            return display
        if (item == reference)
            return reference
    }
    return value
}

; 保存目标允许自定义名称，系统标记与数值字面量不能作为名称。
CustomVariableNameError(name) {
    name := Trim(name)
    if (name == "")
        return "结果变量名不规范：变量名不能为空"
    if (IsNumber(name))
        return "结果变量名不规范：变量名不能是纯数字"
    if (InStr(name, "❖"))
        return "结果变量名不规范：变量名不能包含系统变量字符❖"
    key := GetBuiltinVarName(name)
    for _, names in GetBuiltinVarGroups() {
        for builtin in names {
            if (key == builtin)
                return "结果变量名不规范：变量名不能与系统变量重名"
        }
    }
    return ""
}

TranslateBuiltinVarReferences(value, toDisplay := false) {
    pos := 1
    result := ""
    while (found := RegExMatch(value, "(?<!/)\{([^{}]+)\}", &match, pos)) {
        result .= SubStr(value, pos, found - pos) "{" GetBuiltinVarName(match[1], toDisplay) "}"
        pos := found + match.Len
    }
    return result SubStr(value, pos)
}

IsTimeCategoryName(name) {
    if (name == "")
        return false
    key := GetBuiltinVarName(name)
    for v in GetTimeCategoryVarArr() {
        if (name == v || key == v || key == GetLangKey(v))
            return true
    }
    return false
}

IsTimeVar(name) {
    return (name != "" && IsObject(MySoftData) && MySoftData.HasOwnProp("TimeVarMap") && (MySoftData.TimeVarMap.Has(name) || MySoftData.TimeVarMap.Has(GetLangKey(name))))
}


TryGetCompareOperand(&value, tableItem, index, operand, variTip := true) {
    if (RegExMatch(operand, "^\{([^{}\r\n]+)\}$", &reference))
        return TryGetTabVarValue(&value, tableItem, index, GetBuiltinVarName(reference[1]), variTip, false)
    value := IsNumber(operand) ? Number(operand) : operand
    return true
}

DoCompare(&currentComparison, tableItem, index, CompareType, Name, OtherValue) {
    CompareType := CmdEnumCompare(CompareType)
    if (CompareType == "变量存在") {
        currentComparison := RegExMatch(Name, "^\{([^{}\r\n]+)\}$", &reference)
            && TryGetTabVarValue(&Value, tableItem, index, GetBuiltinVarName(reference[1]), false, false)
        return true
    }
    ; 只有完整的 {变量} 引用才取值，裸文本不再随运行时变量表改变含义。
    if (!TryGetCompareOperand(&Value, tableItem, index, Name)
        || !TryGetCompareOperand(&OtherVal, tableItem, index, OtherValue))
        return false
    if (CompareType == "大于" || CompareType == "大于等于" || CompareType == "小于" || CompareType == "小于等于") {
        if (!IsNumber(Value) || !IsNumber(OtherVal)) {
            currentComparison := false
            return true
        }
        Value := Number(Value), OtherVal := Number(OtherVal)
    }

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
