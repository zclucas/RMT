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
    ; 阶段5：纯文本指令（间隔/按键/移动/RMT指令）已迁移到配置文件模式，
    ; 与其它指令一样登记序列码（旧配置无序列号则跳过，避免 Integer("") 报错）
    textOnly := RegExReplace(paramArr[1], "\d+")
    numbersOnly := RegExReplace(paramArr[1], "\D+")
    if (numbersOnly == "")          ; 旧纯文本格式（如 间隔_500）无序列号，跳过
        return
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
            CfgDelete(DataFile, SettingSection, SerialStr)
    }
    Data.NumMap.Set(Data.CurNum, true)
    Data.Refresh()
    return SerialStr
}
