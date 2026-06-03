#Requires AutoHotkey v2.0

SerialMap := Map()
GetSerialStr(CmdStr) {
    currentDateTime := FormatTime(, "HHmmss")
    randomNum := Random(0, 9)
    return CmdStr CurrentDateTime randomNum
}

SetCMDSerialData(CMD) {
    paramArr := StrSplit(CMD, "_")
    paramArr[1] := GetCmdStr(paramArr[1])
    IsMouseMove := StrCompare(paramArr[1], "移动", false) == 0
    IsPressKey := StrCompare(paramArr[1], "按键", false) == 0
    IsInterval := StrCompare(paramArr[1], "间隔", false) == 0
    IsRMT := StrCompare(paramArr[1], "RMT指令", false) == 0
    if (IsMouseMove || IsPressKey || IsInterval || IsRMT)
        return

    textOnly := RegExReplace(paramArr[1], "\d+")
    numbersOnly := RegExReplace(paramArr[1], "\D+")
    if (!SerialMap.Has(textOnly)) {
        SerialMap.Set(textOnly, SerialData(textOnly))
    }
    Data := SerialMap[textOnly]
    try {
        Data.NumMap.Set(Integer(numbersOnly), true)
    }
    catch as e {
        tipStr := Format("{}{} {}`n{}", GetLang("初始化失败: "), CMD, GetLang("错误"), e.Message)
        MsgBox(tipStr, GetLang("错误"), 0x10)
    }

    Data.Refresh()
}

SetSerialByArr(Arr) {
    for index, value in Arr {
        textOnly := RegExReplace(value, "\d+")
        textOnly := textOnly == "" ? "Default" : textOnly
        numbersOnly := RegExReplace(value, "\D+")
        if (numbersOnly == "")          ; 无数字的序列值（如 Start/End）无序号可登记，跳过避免 Integer("") 报错
            continue
        if (!SerialMap.Has(textOnly)) {
            SerialMap.Set(textOnly, SerialData(textOnly))
        }
        Data := SerialMap[textOnly]
        Data.NumMap.Set(Integer(numbersOnly), true)
        Data.Refresh()
    }
}

GetCMDSerialStr(Cmd) {
    Cmd := GetLangKey(Cmd)
    if (!SerialMap.Has(Cmd)) {
        SerialMap.Set(Cmd, SerialData(Cmd))
    }
    Data := SerialMap[Cmd]
    SerialStr := Format("{}{}", Cmd, Data.CurNum)
    if (MySoftData.DataFileMap.Has(Cmd)) {
        DataFile := MySoftData.DataFileMap[Cmd]
        if (FileExist(DataFile))
            IniDelete(DataFile, IniSection, SerialStr)
    }
    Data.NumMap.Set(Data.CurNum, true)
    Data.Refresh()
    return SerialStr
}
