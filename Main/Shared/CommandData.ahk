SplitMacro(macroStr) {
    cmdArr := StrSplit(macroStr, [",", "，", "`n", "⫶"])
    resultArr := []

    for value in cmdArr {
        curCmd := Trim(value, " `t`r")
        if (curCmd != "")
            resultArr.Push(curCmd)
    }
    return resultArr
}

SplitCommand(macro) {
    realKey := ""
    newMacro := macro

    ; 直接遍历全部20个特殊键做 InStr 包含检测。
    ; 原本的前4字符前缀优化是取 macro 开头的字符，但当特殊键不在指令开头时
    ; （例如 "按键_Launch_App2_点击_100"，前4字符为 "按键_L" 而非 "Laun"），
    ; 会导致所有长键名（Launch_App2 等）全部被漏检。
    ; SpecialKeyMap 只有 20 个键，直接遍历性能完全足够。
    for key in MySoftData.SpecialKeyMap {
        replaced := StrReplace(macro, key, "flagSymbol")
        if (replaced != macro) {
            realKey := key
            newMacro := replaced
            break
        }
    }

    result := StrSplit(realKey != "" ? newMacro : macro, "_")
    loop result.Length {
        if (InStr(result[A_Index], "flagSymbol")) {
            result[A_Index] := StrReplace(result[A_Index], "flagSymbol", realKey)
            break
        }
    }

    return result
}

GetCmdByParams(paramArr) {
    result := ""
    for index, value in paramArr {
        if (value != "") {
            result .= value "_"
        }
    }
    result := Trim(result, "_")
    return result
}

GetMacroStrByCmdArr(cmdArr) {
    ; 使用循环拼接（兼容所有数组类型，避免.Join()方法不存在的问题）
    result := ""
    for index, value in cmdArr {
        if (index > 1)
            result .= ","
        result .= value
    }
    return result
}

GetPressKeyArr(KeyArrStr) {
    if (InStr(KeyArrStr, "⎖")) {
        return StrSplit(KeyArrStr, "⎖")
    }
    return GetComboKeyArr(KeyArrStr)    ;兼容旧版本
}

; 高效的序列號拆分：將序列號拆為「指令名」與「尾部編號」
SplitSerialTextAndNumbers(serialStr, &textOnly, &numbersOnly) {
    len := StrLen(serialStr)
    i := 1
    while (i <= len) {
        c := Ord(SubStr(serialStr, i, 1))
        if (c >= 48 && c <= 57)   ; '0'..'9'
            break
        i++
    }
    textOnly    := SubStr(serialStr, 1, i - 1)
    numbersOnly := SubStr(serialStr, i)
}

; 配置值（JSON 字符串）→ Data 对象；非 JSON 返回 ""
TryParseCommandData(val) {
    if (Type(val) != "String")
        return ""
    SaveStr := Trim(val)
    if (SaveStr == "")
        return ""

    FirstChar := SubStr(SaveStr, 1, 1)
    LastChar := SubStr(SaveStr, -1, 1)
    if (FirstChar != "{" || LastChar != "}")
        return ""

    try
        return JSON.parse(SaveStr, , false)
    catch
        return ""
}

GetMacroCMDData(serialStr) {
    SplitSerialTextAndNumbers(serialStr, &textOnly, &numbersOnly)
    cmd := GetCommandKey(textOnly)
    normalizedSerialStr := cmd numbersOnly
    if (MySoftData.DataCacheMap.Has(normalizedSerialStr))
        return MySoftData.DataCacheMap[normalizedSerialStr]

    DataFile := MySoftData.DataFileMap[cmd]
    DataClass := MySoftData.DataClassMap[cmd]
    saveStr := ReadCommandConfig(DataFile, serialStr, cmd)
    Data := saveStr == "" ? DataClass() : JSON.parse(saveStr, , false)
    Data.SerialStr := normalizedSerialStr
    NormalizeCommandData(cmd, Data)
    if (saveStr != "")
        RegisterVariableIconTypes(cmd, Data)
    MySoftData.DataCacheMap[normalizedSerialStr] := Data
    return Data
}

; 旧配置可能把当前译名写到了配置键。无论界面语言如何，先找中文键，再找旧键。
ReadCommandConfig(path, serial, cmd) {
    SplitSerialTextAndNumbers(serial, &name, &number)
    canonical := cmd number
    value := CfgRead(path, SettingSection, canonical, "")
    if (value != "")
        return value
    if (serial != canonical) {
        value := CfgRead(path, SettingSection, serial, "")
        if (value != "")
            return value
    }
    for alias in CommandLanguageIndex().Aliases.Get(cmd, Map()) {
        if (alias == name)
            continue
        value := CfgRead(path, SettingSection, alias number, "")
        if (value != "")
            return value
    }
    ; 旧英文版把三个组合搜索指令显示成同一个 Search Combo。
    if (cmd == "搜索Combo") {
        for alias in ["组合搜索", "搜索Multi"] {
            value := CfgRead(path, SettingSection, alias number, "")
            if (value != "")
                return value
        }
    }
    return ""
}

NormalizeCommandData(cmd, Data) {
    CmdEnumNorm(cmd, Data)
    if (cmd == "变量")
        NormalizeVariableAssignmentRows(Data)
    for field in ["CurCMD", "LoopBody", "TrueMacro", "FalseMacro", "DefaultMacro", "SubMacro"] {
        if (Data.HasOwnProp(field) && Type(Data.%field%) == "String")
            Data.%field% := GetLangMacro(Data.%field%, 2)
    }
    for field in ["MacroArr", "TrueMacroArr", "FalseMacroArr", "StartMacroArr", "EndMacroArr", "NodeArr", "EmptyNode", "NextNodeArr"] {
        if (!Data.HasOwnProp(field) || !(Data.%field% is Array))
            continue
        for i, value in Data.%field% {
            if (Type(value) == "String")
                Data.%field%[i] := GetLangMacro(value, 2)
        }
    }
}

; 编号移动（移动1）读配置后还原为内联；已是 移动_X_Y_速度 则原样返回。
ExpandNumberedMoveCommand(cmd) {
    if (!RegExMatch(cmd, "^([ \t]*(?:🚫|▶|⭐)*)([^_|]+?)(?=[ \t]*(?:[_|]|$))", &m))
        return cmd
    key := m[2]
    SplitSerialTextAndNumbers(key, &text, &num)
    if (num == "" || GetCommandKey(text) != "移动")
        return cmd
    cmdKey := GetCommandKey(text)
    if (!MySoftData.DataFileMap.Has(cmdKey) || ReadCommandConfig(MySoftData.DataFileMap[cmdKey], key, cmdKey) == "")
        return cmd
    data := GetMacroCMDData(key)
    if (!IsObject(data))
        return cmd
    inline := FormatMoveInlineCmd(data.PosX, data.PosY, data.Speed, data.MoveMode)
    tail := SubStr(cmd, StrLen(m[0]) + 1)
    auto := data.PosX " " data.PosY
    if (RegExMatch(tail, "^_([^_|]+)(?=[_| \t]|$)", &rm) && rm[1] == auto)
        tail := SubStr(tail, StrLen(rm[0]) + 1)
    return m[1] inline tail
}

SaveMacroCMDData(Data) {
    SplitSerialTextAndNumbers(Data.SerialStr, &cmd, &number)
    cmdKey := GetCommandKey(cmd)
    ValidateCommandVariableNames(cmdKey, Data)
    DataFile := MySoftData.DataFileMap[cmdKey]
    Data.SerialStr := cmdKey number
    NormalizeCommandData(cmdKey, Data)
    saveStr := JSON.stringify(Data, 0)
    CfgWrite(saveStr, DataFile, SettingSection, Data.SerialStr)
    RegisterVariableIconTypes(cmdKey, Data)
    if (cmdKey == "变量")
        RegisterHandleVariableRows(Data)
    if (MySoftData.DataCacheMap.Has(Data.SerialStr))
        MySoftData.DataCacheMap.Delete(Data.SerialStr)
}

; 统一拦截普通编辑器、图形节点与其他直接保存入口，读取参数不按保存名称校验。
ValidateCommandVariableNames(cmd, data) {
    fields := ["SaveName", "SaveVar", "VarName", "ResultSaveName", "CoordXName", "CoordYName", "AllSaveName",
        "TimeoutStatusVar", "ResultVar", "ErrorVar", "ControlVar", "TypeVar", "ClassVar", "HwndVar",
        "XVar", "YVar", "WindowXVar", "WindowYVar", "WidthVar", "HeightVar", "CountVar", "NameVar",
        "PidVar", "PathVar", "ExistVar", "StatusVar", "StartTimeVar", "UptimeVar", "CpuVar", "GpuVar",
        "ResultArray", "WidthVarName", "HeightVarName", "ResponseVar", "ConfVar", "RatioVar", "DepthVar"]
    Loop 12
        fields.Push("ResultVar" A_Index)
    if (cmd == "时间") {
        mode := TimeNormSubMode(data)
        if (mode == "获取时间变量" || mode == "获取时间字符串")
            fields.Push("Param1")
        else if (mode == "时间计算")
            fields.Push("Param4")
    }
    for field in fields {
        if (data.HasOwnProp(field) && data.%field% != "") {
            error := CustomVariableNameError(data.%field%)
            if (error != "")
                throw ValueError(GetLang(error), , data.%field%)
        }
    }
    arrays := ["SaveNameArr", "UpdateNameArr"]
    if (cmd == "变量" || cmd == "变量提取")
        arrays.Push("VariableArr")
    for field in arrays {
        if (!data.HasOwnProp(field) || !(data.%field% is Array))
            continue
        for name in data.%field% {
            if (name == "")
                continue
            error := CustomVariableNameError(name)
            if (error != "")
                throw ValueError(GetLang(error), , name)
        }
    }
}

; 调试起点标记：▶（旧配置兼容 ⭐）；界面用向右键帽 Path，不直接画 ▶
CmdDebugMark() {
    return Chr(0x25B6)
}

CmdIsDebug(cmd) {
    return InStr(cmd, Chr(0x25B6)) || InStr(cmd, Chr(0x2B50))
}

CmdStripDebug(cmd) {
    cmd := StrReplace(cmd, Chr(0x25B6), "")
    return StrReplace(cmd, Chr(0x2B50), "")
}

; 仅剥离「行首」的调试当前位置标记 →（U+2192）。
; ⚠️ 关键：→ 同时是手柄 D-pad「右」的显示名（如 🎮→），绝不能全局 StrReplace，
; 否则会破坏 ParseCmdJoyDisplay 的手柄键名还原（DpadRight 失效）。
; 旧调试标记恒为单条指令文本的首字符前缀，故只剥行首即可，主/Worker 共享。
CmdStripCurPos(text) {
    if (text != "" && SubStr(text, 1, 1) == Chr(0x2192))
        return SubStr(text, 2)
    return text
}

; 向右键帽（删除末尾 E750 镜像，中间无 X）
CmdKeyRightPathData() {
    return "M 1.5,2 L 10.2,2 L 14.2,6 L 10.2,10 L 1.5,10 Z"
}

CmdKeyRightIconXaml(brush := "{DynamicResource Accent}", w := 13, h := 11, stroke := "1.8") {
    return '<Path Width="' w '" Height="' h '" Stretch="Uniform" Stroke="' brush '" StrokeThickness="' stroke '"'
        . ' Fill="Transparent" StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"'
        . ' Data="' CmdKeyRightPathData() '" VerticalAlignment="Center" HorizontalAlignment="Center" IsHitTestVisible="False"/>'
}

GetCmdStr(param) {
    param := StrReplace(param, "🚫", "")
    param := CmdStripDebug(param)
    return param
}

GetCmdSymbol(cmd) {
    ; 优化：使用InStr替代RegExMatch（单字符匹配更快）
    IsSkip := InStr(cmd, "🚫")
    IsDebug := CmdIsDebug(cmd)
    SkipStr := IsSkip ? "🚫" : ""
    DebugStr := IsDebug ? CmdDebugMark() : ""
    Symbol := Format("{}{}", SkipStr, DebugStr)
    return Symbol
}

GetCmdOnlyText(param) {
    param := GetCmdStr(param)
    ; 优化：使用单次遍历拆分（替代RegExReplace）
    dummyNumbers := ""
    SplitSerialTextAndNumbers(param, &textOnly, &dummyNumbers)
    return textOnly
}

SetDLConValue(Con, Arr, Text) {
    Con.Delete()
    Con.Add(Arr)
    if (Con.Type == "ComboBox") {
        Con.Text := Text
        return
    }

    if (Con.Type == "DDL") {
        Con.Text := Arr.Length >= 1 ? Arr[1] : ""
        loop Arr.Length {
            if (Arr[A_Index] == Text) {
                Con.Text := Text
                break
            }
        }
    }

}

GetNameAndValueByParamArr(&NameArr, &ValueArr, ParamArr) {
    NameArr := []
    ValueArr := []
    i := 2
    while (i <= paramArr.Length) {
        NameArr.Push(paramArr[i])
        ValueArr.Push(paramArr[i + 1])
        i += 2
    }
}

; 界面显示常见编码名，实际读写仍使用 AutoHotkey 的代码页名称。
GetEncodingDisplayName(Encoding) {
    if (Encoding == "CP0")
        return "ANSI"
    if (Encoding == "CP936")
        return "GB2312"
    if (Encoding == "CP54936")
        return "GB18030"
    if (Encoding == "CP950")
        return "BIG5"
    return Encoding
}

GetAhkEncodingName(Encoding) {
    if (Encoding == "ANSI")
        return "CP0"
    if (Encoding == "GB2312")
        return "CP936"
    if (Encoding == "GB18030")
        return "CP54936"
    if (Encoding == "BIG5")
        return "CP950"
    return Encoding
}


; 迁移生成的末尾宏操作随分支保存。分支体提前返回后，仍在原来的边界执行它。
SplitCompareBranchTail(macro) {
    static pattern := "is)^([\s\S]*[,，\r\n⫶])?[ \t]*((?:🚫|▶|⭐)*(?:宏操作|Ctrl)(\d+)(?=[_| \t]|$)[^,，\r\n⫶]*)[ \t]*$"
    if (RegExMatch(RTrim(macro, " `t`r`n,，⫶"), pattern, &m)) {
        data := GetMacroCMDData("宏操作" m[3])
        if (IsObject(data) && data.HasOwnProp("BranchTail") && data.BranchTail) {
            action := ""
            if (SubStr(m[2], 1, 2) != "🚫" && data.MacroType == "当前宏"
                && (data.CallType == "循环-跳过本轮" || data.CallType == "循环-跳出" || data.CallType == "分支-跳出"))
                action := data.CallType
            return {Body: RTrim(m[1], " `t`r`n,，⫶"), Tail: m[2], Action: action}
        }
    }
    return {Body: macro, Tail: "", Action: ""}
}

ReplaceCompareBranchBody(macro, body) {
    return AppendCompareBranchTail(body, SplitCompareBranchTail(macro).Tail)
}

AppendCompareBranchTail(body, tail) {
    if (tail == "")
        return body
    if (Trim(body, " `t`r`n") == "" || RegExMatch(body, "[,，\r\n⫶][ \t]*$"))
        return body tail
    return body "," tail
}
