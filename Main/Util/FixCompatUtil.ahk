#Requires AutoHotkey v2.0

; 旧版本配置文件的迁移改写，仅主程序需要（入口：Gui\SettingMgrGui.ahk）
; 由 Main\GlobalUtil.ahk 引入，Worker(Thread\Work.ahk) 不加载本文件
; 内存数据结构的补齐逻辑在 CompatDataUtil.ahk，那部分主程序与Worker共用

CompatGetData(LineStr, FilePath) {
    FoundPos := InStr(LineStr, "=")
    if (FoundPos == 0)
        return ""

    SerialStr := SubStr(LineStr, 1, FoundPos - 1)
    CurLineStr := SubStr(LineStr, FoundPos + 1)
    CheckStr := IniRead(FilePath, IniSection, SerialStr, "")    ;部分A_LoopReadLine会因为编码问题错位，校验一下
    if (CurLineStr == "" && CheckStr == "")
        return ""

    CurData := Object()
    CheckData := Object()
    try {
        CurData := JSON.parse(CurLineStr, , false)
    }

    try {
        CheckData := JSON.parse(CheckStr, , false)
    }

    SaveStr := CurLineStr
    Data := CurData
    CurDataPropCount := ObjOwnPropCount(CurData)
    CheckDataPropCount := ObjOwnPropCount(CheckData)
    if (CurDataPropCount < CheckDataPropCount) {
        SaveStr := CheckStr
        Data := CheckData
    }
    else if (CurDataPropCount == CheckDataPropCount && StrLen(CurLineStr) > StrLen(CheckStr)) {
        SaveStr := CheckStr
        Data := CheckData
    }

    FirstChar := SubStr(SaveStr, 1, 1)
    LastChar := SubStr(SaveStr, -1, 1)
    if (FirstChar != "{" || LastChar != "}")
        return ""

    return Data
}

CompatMacro(MacroStr, &isFix) {
    CMDArr := SplitMacro(MacroStr)
    isFix := false
    modifyKeyMap := Map("移动Pro", 1, "搜索", 1, "搜索Pro", 1, "运行", 1, "如果", 1, "如果Pro", 1, "输出", 1, "变量", 1,
        "变量提取", 1, "宏操作", 1, "运算", 1, "后台鼠标", 1, "后台按键", 1, "循环", 1)
    loop CMDArr.Length {
        paramArr := SplitCommand(CMDArr[A_Index])
        cmdSymbol := GetCmdSymbol(paramArr[1])
        paramArr[1] := GetCmdStr(paramArr[1])

        ;1.0.9F3 间隔指令调整 统一使用两个参数  调整处理时机
        if (paramArr[1] == "间隔" && paramArr.Length == 3) {
            isFix := true
            paramArr[2] := paramArr[3]
            paramArr.RemoveAt(3)
            CMDArr[A_Index] := GetCmdByParams(paramArr)
        }

        ;1.1F1 按键指令动作类型改成中文
        if (paramArr[1] == "按键" && IsInteger(paramArr[3])) {
            keyTypeMap := Map(1, "按下", 2, "松开", 3, "点击")
            if (keyTypeMap.Has(Integer(paramArr[3]))) {
                isFix := true
                paramArr[3] := keyTypeMap[Integer(paramArr[3])]
                CMDArr[A_Index] := GetCmdByParams(paramArr)
            }
        }

        ;1.1 简化配置命令    形如搜索_Search1234_备注 => 搜索1234_备注
        if (modifyKeyMap.Has(paramArr[1])) {
            isFix := true
            textOnly := RegExReplace(paramArr[2], "\d+")
            numbersOnly := RegExReplace(paramArr[2], "\D+")
            paramArr[1] := paramArr[1] numbersOnly
            paramArr[2] := paramArr.Length == 3 ? paramArr[3] : ""
            paramArr.Pop()
            CMDArr[A_Index] := GetCmdByParams(paramArr)
        }

        ;RMT指令旧格式归一化: RMT指令_指令 → RMT指令_类别_指令, RMT指令_显示菜单_序号 → RMT指令_宏控制_显示菜单_序号
        if (paramArr[1] == "RMT指令") {
            static RMTCmdCategoryMap := Map(
                "截图", "图文", "截图提取文本", "图文", "自由贴", "图文",
                "启用鼠标", "输入控制", "启用键盘", "输入控制", "启用键鼠", "输入控制",
                "禁用鼠标", "输入控制", "禁用键盘", "输入控制", "禁用键鼠", "输入控制",
                "启用鼠标加速", "输入控制", "禁用鼠标加速", "输入控制",
                "显示菜单", "宏控制", "关闭菜单", "宏控制",
                "暂停所有宏", "宏控制", "恢复所有宏", "宏控制", "终止所有宏", "宏控制", "全局暂停", "宏控制",
                "开启变量监视", "调试", "关闭变量监视", "调试",
                "开启指令显示", "调试", "关闭指令显示", "调试",
                "关闭指令显示窗口", "调试", "切换指令显示开关", "调试",
                "关闭软件", "软件自身", "休眠", "软件自身", "重载", "软件自身"
            )
            static RMTCmdRenameMap := Map(
                "全局暂停", "暂停所有宏",
                "关闭指令显示窗口", "关闭指令显示",
                "切换指令显示开关", "开启指令显示"
            )
            IsOldRMTFormat := false
            if (paramArr.Length == 2 && RMTCmdCategoryMap.Has(paramArr[2]))
                IsOldRMTFormat := true
            else if (paramArr.Length == 3 && paramArr[2] == "显示菜单")
                IsOldRMTFormat := true

            if (IsOldRMTFormat) {
                isFix := true
                oldCmdStr := paramArr[2]
                if (RMTCmdRenameMap.Has(oldCmdStr))
                    oldCmdStr := RMTCmdRenameMap[oldCmdStr]
                paramArr[2] := RMTCmdCategoryMap[oldCmdStr]
                paramArr.InsertAt(3, oldCmdStr)
                CMDArr[A_Index] := GetCmdByParams(paramArr)
            }
        }
        CMDArr[A_Index] := cmdSymbol CMDArr[A_Index]
    }
    MacroStr := GetMacroStrByCmdArr(CMDArr)
    return MacroStr
}

CompatSerial(FilePath, Symbol, NewSymbol) {
    fileContent := FileRead(filePath, "UTF-16")
    newContent := RegExReplace(fileContent, Symbol "(\d+)", NewSymbol "$1")
    if (newContent != fileContent) {
        FileDelete(filePath)
        FileAppend(newContent, filePath, "UTF-16")
        return true
    }
    return false
}

CompatPath(FilePath, Data) {
    SplitPath FilePath, &name, &dir, &ext, &name_no_ext, &drive
    SplitPath dir, &name, &dir, &ext, &SettingName, &drive
    if (!ObjHasOwnProp(Data, "SearchImagePath") || Data.SearchImagePath == "")
        return false

    StartPos := InStr(Data.SearchImagePath, "Setting", 1)
    SubPath := SubStr(Data.SearchImagePath, StartPos)
    NewPath1 := A_WorkingDir "\" SubPath    ;调整盘符

    FileNameArr := StrSplit(NewPath1, "\")
    NewPath2 := ""
    for index, value in FileNameArr {
        if (value == "Setting" && index + 2 <= FileNameArr.Length && FileNameArr[index + 2] == "Images") {
            FileNameArr[index + 1] := SettingName
        }
        NewPath2 .= value "\"
    }

    NewPath := RTrim(NewPath2, "\")     ;修改成对应配置下
    if (FileExist(NewPath)) {
        Data.SearchImagePath := NewPath
        return true
    }
    return false
}

; 生成不与 usedMap 冲突的 Timing 序列码（不走 GetCMDSerialStr，避免误删 TimingFile 键）
CompatNextTimingSerial(usedMap) {
    n := 1
    loop {
        cand := "Timing" n
        if (!usedMap.Has(cand)) {
            usedMap.Set(cand, true)
            return cand
        }
        n += 1
    }
}

; 补齐/修复 TimingSerialArr：禁止用 "0" 占位（否则定时编辑会把键 0 写入 TimingFile.ini）
CompatFixTimingSerialArr(savedStr, baseLen, &changed) {
    changed := false
    usedMap := Map()
    valueArr := savedStr == "" ? [] : StrSplit(savedStr, "π")
    ; 先登记已合法的 Timing 序列，避免补齐时撞号
    for v in valueArr {
        if (RegExMatch(v, "^Timing\d+$"))
            usedMap.Set(v, true)
    }
    loop baseLen {
        i := A_Index
        cur := (i <= valueArr.Length) ? valueArr[i] : ""
        if (!RegExMatch(cur, "^Timing\d+$")) {
            cur := CompatNextTimingSerial(usedMap)
            if (i <= valueArr.Length)
                valueArr[i] := cur
            else
                valueArr.Push(cur)
            changed := true
        }
    }
    newStr := ""
    loop valueArr.Length {
        newStr .= valueArr[A_Index]
        if (A_Index < valueArr.Length)
            newStr .= "π"
    }
    return newStr
}

CompatCMD(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    ; 兼容旧版缺失的结构数组字段（如UnorderedTriggerArr等），以ModeArr长度为基准补齐
    ; 注意：TimingSerialArr 不能默认填 "0"，否则定时配置会乱入 TimingFile
    arrFields := Map(
        "UnorderedTriggerArr", "0",
        "TriggerTypeArr", "1",
        "HoldTimeArr", "500",
        "LoopCountArr", "1",
        "StartTipSoundArr", "1",
        "EndTipSoundArr", "1",
        "IcoPathArr", "",
        "SerialArr", "0"
    )
    loop MainSoftData.TabSymbolArr.Length {
        symbol := GetTableSymbol(A_Index)
        modeArrStr := IniRead(filePath, IniSection, symbol "ModeArr", "")
        if (modeArrStr == "")
            continue
        baseLen := StrSplit(modeArrStr, "π").Length
        for fieldName, defaultValue in arrFields {
            savedStr := IniRead(filePath, IniSection, symbol fieldName, "")
            if (savedStr == "") {
                newStr := ""
                loop baseLen {
                    newStr .= defaultValue
                    if (A_Index < baseLen)
                        newStr .= "π"
                }
                IniWrite(newStr, filePath, IniSection, symbol fieldName)
                hasFix := true
            } else {
                valueArr := StrSplit(savedStr, "π")
                if (valueArr.Length < baseLen) {
                    loop baseLen - valueArr.Length
                        valueArr.Push(defaultValue)
                    newStr := ""
                    loop valueArr.Length {
                        newStr .= valueArr[A_Index]
                        if (A_Index < valueArr.Length)
                            newStr .= "π"
                    }
                    IniWrite(newStr, filePath, IniSection, symbol fieldName)
                    hasFix := true
                }
            }
        }
        ; TimingSerialArr：缺失、过短或含非法值（如旧逻辑填的 0）时按 TimingN 修复
        timingSaved := IniRead(filePath, IniSection, symbol "TimingSerialArr", "")
        timingChanged := false
        timingNew := CompatFixTimingSerialArr(timingSaved, baseLen, &timingChanged)
        if (timingChanged || timingSaved == "") {
            IniWrite(timingNew, filePath, IniSection, symbol "TimingSerialArr")
            hasFix := true
        }
    }
    loop MainSoftData.TabSymbolArr.Length {
        symbol := GetTableSymbol(A_Index)
        loop {
            MacroLabel := symbol "MacroArr" A_Index
            MacroStr := IniRead(filePath, IniSection, MacroLabel, "默认空文本")
            if (MacroStr == "默认空文本")
                break

            MacroStr := CompatMacro(MacroStr, &isFix)
            if (isFix) {
                hasFix := true
                IniWrite(MacroStr, filePath, IniSection, MacroLabel)
            }
        }

    }
    return hasFix
}

CompatTiming(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        FoundPos := InStr(A_LoopReadLine, "=")
        if (FoundPos == 0)
            continue
        lineKey := SubStr(A_LoopReadLine, 1, FoundPos - 1)
        ; 只保留 TimingN 键；丢弃误写入的异种序列码（如 0、移动Pro、搜索Pro）
        if (!RegExMatch(lineKey, "^Timing\d+$")) {
            hasFix := true
            continue
        }
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false
        ; 以 ini 行键为准写回（新版 SaveTimingData 可能不落 SerialStr 字段）
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != lineKey) {
            Data.SerialStr := lineKey
            curFix := true
        }

        if (Data.HasOwnProp("StartTime")) {
            Data.StartStamp := TimeStrToStamp(Data.StartTime)
            Data.DeleteProp("StartTime")
            curFix := true
        }
        if (Data.HasOwnProp("EndTime")) {
            Data.EndStamp := (Data.EndTime != "" ? TimeStrToStamp(Data.EndTime) : 0)
            Data.DeleteProp("EndTime")
            curFix := true
        }
        if (Data.HasOwnProp("NextStamp")) {
            Data.DeleteProp("NextStamp")
            curFix := true
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", lineKey, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatSearch(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Search", "搜索")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue
        curFix := CompatPath(filePath, Data)

        if (Data.TrueMacro != "") {
            Data.TrueMacro := CompatMacro(Data.TrueMacro, &isFix)
            curFix := curFix || isFix
        }

        if (Data.FalseMacro != "") {
            Data.FalseMacro := CompatMacro(Data.FalseMacro, &isFix)
            curFix := curFix || isFix
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatSearchPro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Search", "搜索Pro") || hasFix
    hasFix := CompatSerial(filePath, "Search\+", "搜索Pro") || hasFix
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        FoundPos := InStr(A_LoopReadLine, "=")
        if (FoundPos == 0)
            continue
        lineKey := SubStr(A_LoopReadLine, 1, FoundPos - 1)
        ; 丢弃误写入的异种序列码（如移动Pro 被写进 SearchProFile）
        if (!RegExMatch(lineKey, "^搜索Pro\d+$")) {
            hasFix := true
            continue
        }
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != lineKey) {
            Data.SerialStr := lineKey
            hasFix := true
        }

        curFix := CompatPath(filePath, Data)
        ;如果有了，那就说明是新版本，不需要兼容处理
        if (!ObjHasOwnProp(Data, "ConfigName")) {
            Data.ConfigName := "默认"
            Data.ConfigArr := []
            curFix := true
        }

        ;自动选择对应的窗口规则配置如果有的话
        if (Data.ConfigArr.Length != 0) {
            curFix := CompatSearchProConfig(Data) || curFix
        }

        if (!ObjHasOwnProp(Data, "WinInfo")) {
            Data.WinInfo := ""
            curFix := true
        }

        if (Data.TrueMacro != "") {
            Data.TrueMacro := CompatMacro(Data.TrueMacro, &isFix)
            curFix := curFix || isFix
        }

        if (Data.FalseMacro != "") {
            Data.FalseMacro := CompatMacro(Data.FalseMacro, &isFix)
            curFix := curFix || isFix
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", lineKey, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatMMPro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "MMPro", "移动Pro") || hasFix
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        FoundPos := InStr(A_LoopReadLine, "=")
        if (FoundPos == 0)
            continue
        lineKey := SubStr(A_LoopReadLine, 1, FoundPos - 1)
        if (!RegExMatch(lineKey, "^移动Pro\d+$")) {
            hasFix := true
            continue
        }
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != lineKey) {
            Data.SerialStr := lineKey
            hasFix := true
        }

        curFix := false
        ;1.0.8F7到新版本兼容, 新增鼠标类型
        ;如果有了，那就说明是新版本，不需要兼容处理
        if (!ObjHasOwnProp(Data, "ActionType")) {
            Data.ActionType := 1
            curFix := true
        }

        ;1.0.9F4 新增窗口分辨率映射不同的配置
        ;如果有了，那就说明是新版本，不需要兼容处理
        if (!ObjHasOwnProp(Data, "ConfigName")) {
            Data.ConfigName := "默认"
            Data.ConfigArr := []
            curFix := true
        }

        ;旧版使用IsRelative/IsGameView字段，新版统一为MouseMoveMode
        if (!ObjHasOwnProp(Data, "MouseMoveMode")) {
            MouseMoveMode := 0
            if (ObjHasOwnProp(Data, "IsGameView") && Data.IsGameView == 1)
                MouseMoveMode := 2
            else if (ObjHasOwnProp(Data, "IsRelative") && Data.IsRelative == 1)
                MouseMoveMode := 1
            Data.MouseMoveMode := MouseMoveMode
            curFix := true
        }

        ;自动选择对应的窗口规则配置如果有的话
        if (!Data.ConfigArr.Length == 0) {
            curFix := CompatMMProConfig(Data) || curFix
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", lineKey, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatOutput(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    FixTypeMap := Map("1", "发送内容", "2", "粘贴内容", "3", "临时提示",
        "4", "指令窗口", "5", "软件弹窗", "6", "系统语音", "7", "复制到剪切板")
    hasFix := CompatSerial(filePath, "Output", "输出")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue
        curFix := false
        if (IsInteger(Data.OutputType) && FixTypeMap.Has(String(Data.OutputType))) {
            curFix := true
            Data.OutputType := FixTypeMap[String(Data.OutputType)]
        }
        if (!Data.HasOwnProp("VariableName")) {
            curFix := true
            Data.VariableName := ""
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatRun(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Run", "运行")

    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        ; 字段补齐 / RunMode→Mode 等（含无 Mode 的 1.1.x 配置）
        curFix := CompatEnsureRunData(Data)

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")

    return hasFix
}

CompatLoop(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    hasFix := CompatSerial(filePath, "Loop", "循环")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false
        if (Data.LoopBody != "") {
            Data.LoopBody := CompatMacro(Data.LoopBody, &isFix)
            curFix := curFix || isFix
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatSubMacro(FilePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    FixTypeMap := Map("1", "当前宏", "2", "按键宏", "3", "字串宏", "4", "菜单宏", "5", "定时宏", "6", "宏")
    FixCallTypeMap := Map("1", "插入到当前宏", "2", "触发", "3", "暂停", "4", "取消暂停", "5", "终止")
    hasFix := CompatSerial(filePath, "SubMacro", "宏操作")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, FilePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false
        ;宏插入可以指定次数
        if (!ObjHasOwnProp(Data, "InsertCount")) {
            curFix := true
            Data.InsertCount := 1
        }

        if (IsInteger(Data.MacroType) && FixTypeMap.Has(String(Data.MacroType))) {
            curFix := true
            Data.MacroType := FixTypeMap[String(Data.MacroType)]
        }

        if (IsInteger(Data.CallType) && FixCallTypeMap.Has(String(Data.CallType))) {
            curFix := true
            Data.CallType := FixCallTypeMap[String(Data.CallType)]
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatVariable(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Variable", "变量")
    return hasFix
}

CompatExVariable(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "ExVariable", "变量提取")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false
        if (!ObjHasOwnProp(Data, "WinInfo")) {
            Data.WinInfo := ""
            curFix := true
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatCompare(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Compare", "如果")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue
        curFix := false
        if (Data.TrueMacro != "") {
            Data.TrueMacro := CompatMacro(Data.TrueMacro, &isFix)
            curFix := curFix || isFix
        }

        if (Data.FalseMacro != "") {
            Data.FalseMacro := CompatMacro(Data.FalseMacro, &isFix)
            curFix := curFix || isFix
        }

        if (!ObjHasOwnProp(Data, "TrueControlType")) {
            Data.TrueControlType := "无"
            Data.FalseControlType := "无"
            curFix := true
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatComparePro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    hasFix1 := CompatSerial(filePath, "Compare\+", "如果Pro")
    hasFix2 := CompatSerial(filePath, "ComparePro", "如果Pro")
    hasFix := hasFix1 || hasFix2
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false
        loop Data.MacroArr.Length {
            if (Data.MacroArr[A_Index] != "") {
                Data.MacroArr[A_Index] := CompatMacro(Data.MacroArr[A_Index], &isFix)
                curFix := curFix || isFix
            }
        }

        if (Data.DefaultMacro != "") {
            Data.DefaultMacro := CompatMacro(Data.DefaultMacro, &isFix)
            curFix := curFix || isFix
        }

        if (!ObjHasOwnProp(Data, "ControlTypeArr")) {
            ControlTypeArr := []
            loop Data.MacroArr.Length {
                ControlTypeArr.Push("无")
            }
            Data.ControlTypeArr := ControlTypeArr
            Data.DefaultControlType := "无"
            curFix := true
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatOperation(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix1 := CompatSerial(filePath, "Operation", "运算")
    hasFix2 := CompatSerial(filePath, "Calc", "运算")
    hasFix := hasFix1 || hasFix2
    newContent := "[UserSettings]"
    DeletePropArr := ["NameArr", "OperationArr", "SymbolGroups", "ValueGroups"]
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false

        ; 确保ExpressionArr字段存在
        if (!ObjHasOwnProp(Data, "ExpressionArr")) {
            Data.ExpressionArr := ["", "", "", ""]
            curFix := true
        }

        ; 迁移旧数据：将OperationArr复制到ExpressionArr
        if (ObjHasOwnProp(Data, "OperationArr")) {
            loop Data.ExpressionArr.Length {
                if (Data.OperationArr[A_Index] != "") {
                    oldExpr := Data.OperationArr[A_Index]
                    newExpr := CompatConvertExpr(oldExpr)
                    Data.ExpressionArr[A_Index] := newExpr
                    if (newExpr != oldExpr) {
                        curFix := true
                    }
                }
            }
        }

        loop DeletePropArr.Length {
            PropName := DeletePropArr[A_Index]
            if (ObjHasOwnProp(Data, PropName)) {
                Data.DeleteProp(PropName)
                curFix := true
            }
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatBGMouse(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "BGMouse", "后台鼠标")
    return hasFix
}

CompatBGKey(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "BGKey", "后台按键")
    return hasFix
}

; 将旧格式变量名转换为新格式{变量名}
CompatConvertExpr(expression) {
    if (expression = "" || Type(expression) != "String")
        return expression

    ; 这个正则表达式查找任何潜在的变量名（以字母/中文/_开头，后跟字母/数字/中文/_）
    ; 它也会找到已经用{}包裹的变量
    NeedleRegEx := "(\{([a-zA-Z一-龥_][a-zA-Z0-9一-龥_]*)\})|([a-zA-Z一-龥_][a-zA-Z0-9一-龥_]*)"

    newExpression := ""
    lastPos := 1

    while (pos := RegExMatch(expression, NeedleRegEx, &match, lastPos)) {
        ; 附加最后一个匹配和当前匹配之间的文本
        newExpression .= SubStr(expression, lastPos, pos - lastPos)

        ; match[0] 是完整的匹配
        ; 如果 match[1] 存在，它是一个 {var} 匹配，所以它已经是新格式
        ; 如果 match[3] 存在，它是一个 var 匹配，所以需要转换

        if (match[1] != "") {
            ; 已经是新格式，如 {var}，所以直接附加
            newExpression .= match[0]
        } else if (match[3] != "") {
            ; 旧格式，如 var，所以用 {} 包裹它
            newExpression .= "{" . match[0] . "}"
        }

        lastPos := pos + StrLen(match[0])
    }

    ; 附加最后一个匹配后的剩余字符串
    newExpression .= SubStr(expression, lastPos)

    return newExpression
}

CompatSearchProConfig(Data) {
    isFix := false
    CurConfigRuleStr := StrSplit(Data.ConfigName, "_")[1]
    CurScreenRuleStr := Format("{}*{}", A_ScreenWidth, A_ScreenHeight)
    ;默认就是这个配置就不用更换了
    if (CurConfigRuleStr == CurScreenRuleStr)
        return isFix

    ConfigData := ""
    loop Data.ConfigArr.Length {
        ConfigRuleStr := StrSplit(Data.ConfigArr[A_Index].ConfigName, "_")[1]
        if (ConfigRuleStr == CurScreenRuleStr) {
            ConfigData := Data.ConfigArr.RemoveAt(A_Index)
            break
        }
    }

    ;匹配上了，交换内容
    if (ConfigData != "") {
        LastConfig := Object()
        LastConfig.ConfigName := Data.ConfigName
        LastConfig.SearchType := Data.SearchType
        LastConfig.SearchColor := Data.SearchColor
        LastConfig.SearchText := Data.SearchText
        LastConfig.SearchImagePath := Data.SearchImagePath
        LastConfig.Similar := Data.Similar
        LastConfig.OCRType := Data.OCRType
        LastConfig.SearchImageType := Data.SearchImageType
        LastConfig.StartPosX := Data.StartPosX
        LastConfig.StartPosY := Data.StartPosY
        LastConfig.EndPosX := Data.EndPosX
        LastConfig.EndPosY := Data.EndPosY
        LastConfig.SearchCount := Data.SearchCount
        LastConfig.SearchInterval := Data.SearchInterval
        LastConfig.MouseActionType := Data.MouseActionType
        LastConfig.Speed := Data.Speed
        LastConfig.ClickCount := Data.ClickCount
        Data.ConfigArr.Push(LastConfig)

        Data.ConfigName := ConfigData.ConfigName
        Data.SearchType := ConfigData.SearchType
        Data.SearchColor := ConfigData.SearchColor
        Data.SearchText := ConfigData.SearchText
        Data.SearchImagePath := ConfigData.SearchImagePath
        Data.Similar := ConfigData.Similar
        Data.OCRType := ConfigData.OCRType
        Data.SearchImageType := ConfigData.SearchImageType
        Data.StartPosX := ConfigData.StartPosX
        Data.StartPosY := ConfigData.StartPosY
        Data.EndPosX := ConfigData.EndPosX
        Data.EndPosY := ConfigData.EndPosY
        Data.SearchCount := ConfigData.SearchCount
        Data.SearchInterval := ConfigData.SearchInterval
        Data.MouseActionType := ConfigData.MouseActionType
        Data.Speed := ConfigData.Speed
        Data.ClickCount := ConfigData.ClickCount

        isFix := true
    }
    return isFix
}

CompatMMProConfig(Data) {
    isFix := false
    CurConfigRuleStr := StrSplit(Data.ConfigName, "_")[1]
    CurScreenRuleStr := Format("{}*{}", A_ScreenWidth, A_ScreenHeight)
    ;默认就是这个配置就不用更换了
    if (CurConfigRuleStr == CurScreenRuleStr)
        return isFix

    ConfigData := ""
    loop Data.ConfigArr.Length {
        ConfigRuleStr := StrSplit(Data.ConfigArr[A_Index].ConfigName, "_")[1]
        if (ConfigRuleStr == CurScreenRuleStr) {
            ConfigData := Data.ConfigArr.RemoveAt(A_Index)
            break
        }
    }
    ;匹配上了，交换内容
    if (ConfigData != "") {
        LastConfig := Object()
        LastConfig.ConfigName := Data.ConfigName
        LastConfig.PosVarX := Data.PosVarX
        LastConfig.PosVarY := Data.PosVarY
        LastConfig.ActionType := Data.ActionType
        if (ObjHasOwnProp(Data, "MouseMoveMode"))
            LastConfig.MouseMoveMode := Data.MouseMoveMode
        else {
            MouseMoveMode := 0
            if (ObjHasOwnProp(Data, "IsGameView") && Data.IsGameView == 1)
                MouseMoveMode := 2
            else if (ObjHasOwnProp(Data, "IsRelative") && Data.IsRelative == 1)
                MouseMoveMode := 1
            LastConfig.MouseMoveMode := MouseMoveMode
        }
        LastConfig.Speed := Data.Speed
        LastConfig.Count := Data.Count
        LastConfig.Interval := Data.Interval
        Data.ConfigArr.Push(LastConfig)

        Data.ConfigName := ConfigData.ConfigName
        Data.PosVarX := ConfigData.PosVarX
        Data.PosVarY := ConfigData.PosVarY
        Data.ActionType := ConfigData.ActionType
        if (ObjHasOwnProp(ConfigData, "MouseMoveMode"))
            Data.MouseMoveMode := ConfigData.MouseMoveMode
        else {
            MouseMoveMode := 0
            if (ObjHasOwnProp(ConfigData, "IsGameView") && ConfigData.IsGameView == 1)
                MouseMoveMode := 2
            else if (ObjHasOwnProp(ConfigData, "IsRelative") && ConfigData.IsRelative == 1)
                MouseMoveMode := 1
            Data.MouseMoveMode := MouseMoveMode
        }
        Data.Speed := ConfigData.Speed
        Data.Count := ConfigData.Count
        Data.Interval := ConfigData.Interval

        isFix := true
    }
    return isFix
}