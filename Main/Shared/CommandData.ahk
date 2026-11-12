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

; 高效的序列号拆分函数：一次遍历同时提取文本和数字部分（避免2次RegExReplace）
SplitSerialTextAndNumbers(serialStr, &textOnly, &numbersOnly) {
    textOnly := ""
    numbersOnly := ""
    loop parse serialStr {
        ch := A_LoopField
        if (IsInteger(ch))
            numbersOnly .= ch
        else
            textOnly .= ch
    }
}

GetMacroCMDData(serialStr) {
    if (MySoftData.DataCacheMap.Has(serialStr)) {
        return MySoftData.DataCacheMap[serialStr]
    }

    ; 优化：使用单次遍历拆分（替代2次RegExReplace）
    SplitSerialTextAndNumbers(serialStr, &textOnly, &numbersOnly)
    cmd := GetLangKey(textOnly)

    ; 同一步骤可能带显示语言中的指令名。优先读取规范化键，再回退到旧配置中的原键。
    normalizedSerialStr := Format("{}{}", cmd, numbersOnly)

    if (normalizedSerialStr != serialStr && MySoftData.DataCacheMap.Has(normalizedSerialStr)) {
        return MySoftData.DataCacheMap[normalizedSerialStr]
    }

    DataFile := MySoftData.DataFileMap[cmd]
    DataClass := MySoftData.DataClassMap[cmd]
    saveStr := CfgRead(DataFile, SettingSection, normalizedSerialStr, "")
    if (saveStr == "" && normalizedSerialStr != serialStr)
        saveStr := CfgRead(DataFile, SettingSection, serialStr, "")
    if (saveStr == "")
        saveStr := CompatLegacyCmdSaveStr(cmd, DataFile, numbersOnly, normalizedSerialStr, serialStr)
    if (saveStr == "") {
        Data := DataClass()
        Data.SerialStr := SerialStr
    }
    else {
        Data := JSON.parse(saveStr, , false)
        if (cmd == "时间")
            CompatEnsureTimeData(Data)
        else if (cmd == "倒计时")
            CompatEnsureCountDownData(Data)
        else if (cmd == "运行" || cmd == "运行Pro")
            CompatEnsureRunData(Data)
        else if (cmd == "文件读写" || cmd == "Excel")
            CompatEnsureFileIOData(Data)
        else if (cmd == "输出")
            CompatEnsureOutputData(Data)
    }
    CmdEnumNorm(cmd, Data)

    MySoftData.DataCacheMap.Set(normalizedSerialStr, Data)

    ; 两个缓存键引用同一个对象，写入时要一起失效。
    if (normalizedSerialStr != serialStr) {
        MySoftData.DataCacheMap.Set(serialStr, Data)
    }

    return Data
}

SaveMacroCMDData(Data) {
    ; 优化：使用单次遍历拆分（替代RegExReplace）
    dummyNumbers := ""
    SplitSerialTextAndNumbers(Data.SerialStr, &cmd, &dummyNumbers)
    cmdKey := GetLangKey(cmd)
    if (!MySoftData.DataFileMap.Has(cmdKey))
        cmdKey := cmd
    DataFile := MySoftData.DataFileMap[cmdKey]

    saveStr := JSON.stringify(Data, 0)
    CfgWrite(saveStr, DataFile, SettingSection, Data.SerialStr)
    ; 清掉原串与规范化键，避免中英文序列码双缓存导致读到旧对象（勾选未回显）
    if (MySoftData.DataCacheMap.Has(Data.SerialStr))
        MySoftData.DataCacheMap.Delete(Data.SerialStr)
    normalizedSerialStr := Format("{}{}", cmdKey, dummyNumbers)
    if (normalizedSerialStr != Data.SerialStr && MySoftData.DataCacheMap.Has(normalizedSerialStr))
        MySoftData.DataCacheMap.Delete(normalizedSerialStr)
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
