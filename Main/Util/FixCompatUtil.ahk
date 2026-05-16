#Requires AutoHotkey v2.0

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

;1.0.8F4到新版本兼容, 模块中新增菜单模块相关数据
Compat1_0_8F4FlodInfo(FoldInfo) {
    if (FoldInfo == "" || ObjHasOwnProp(FoldInfo, "FrontInfoArr"))
        return

    FoldInfo.FrontInfoArr := []
    FoldInfo.TKTypeArr := []
    FoldInfo.TKArr := []
    FoldInfo.HoldTimeArr := []
    loop FoldInfo.RemarkArr.Length {
        FoldInfo.FrontInfoArr.Push("")
        FoldInfo.TKTypeArr.Push(1)
        FoldInfo.TKArr.Push("")
        FoldInfo.HoldTimeArr.Push(500)
    }
}

;1.0.9F1到新版本兼容 增加配置音选项
Compat1_0_9F1TipSound(tableItem) {
    if (tableItem.ModeArr.Length == tableItem.StartTipSoundArr.Length &&
        tableItem.ModeArr.Length == tableItem.EndTipSoundArr.Length)
        return

    for index, value in tableItem.ModeArr {
        if (tableItem.StartTipSoundArr.Length < index) {
            tableItem.StartTipSoundArr.Push(1)
        }

        if (tableItem.EndTipSoundArr.Length < index) {
            tableItem.EndTipSoundArr.Push(1)
        }
    }
}

CompatCMD(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    loop MySoftData.TabSymbolArr.Length {
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
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

        curFix := false
        ; Upgrade 12-char timestamps to 14-char
        if (StrLen(Data.StartTime) == 12) {
            Data.StartTime .= "00"
            curFix := true
        }
        if (Data.EndTime != "" && StrLen(Data.EndTime) == 12) {
            Data.EndTime .= "00"
            curFix := true
        }

        ; Ensure CustomUnit exists
        if (!ObjHasOwnProp(Data, "CustomUnit")) {
            Data.CustomUnit := 2 ; Default to Minutes
            curFix := true
        }

        ; Migrate old types to new scheme (1: Once, 2: Startup, 3: Custom)
        if (Data.Type >= 2 && Data.Type <= 5) {
            oldType := Data.Type
            Data.Type := 3 ; Custom
            Data.CustomInterval := 1
            if (oldType == 2) ; Hourly
                Data.CustomUnit := 3
            else if (oldType == 3) ; Daily
                Data.CustomUnit := 4
            else if (oldType == 4) ; Weekly
                Data.CustomUnit := 5
            else if (oldType == 5) ; Monthly
                Data.CustomUnit := 6
            curFix := true
        } else if (Data.Type == 6) { ; Old Startup
            Data.Type := 2
            curFix := true
        } else if (Data.Type == 7) { ; Old Custom
            Data.Type := 3
            curFix := true
        }

        ; Force re-calculation of relative stamps
        if (curFix || Data.HasOwnProp("StartStamp")) {
            if (Data.HasOwnProp("StartStamp")) {
                Data.DeleteProp("StartStamp")
                curFix := true
            }
            if (Data.HasOwnProp("EndStamp")) {
                Data.DeleteProp("EndStamp")
                curFix := true
            }
            if (Data.HasOwnProp("NextStamp")) {
                Data.DeleteProp("NextStamp")
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
    hasFix := CompatSerial(filePath, "Search", "搜索Pro")
    hasFix := CompatSerial(filePath, "Search\+", "搜索Pro")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

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
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
    }
    FileDelete(filePath)
    FileAppend(newContent, filePath, "UTF-16")
    return hasFix
}

CompatMMPro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "MMPro", "移动Pro")
    newContent := "[UserSettings]"
    FileEncoding("UTF-16")
    loop read, filePath {
        Data := CompatGetData(A_LoopReadLine, filePath)
        if (Data == "")
            continue

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

        ;自动选择对应的窗口规则配置如果有的话
        if (!Data.ConfigArr.Length == 0) {
            curFix := CompatMMProConfig(Data) || curFix
        }

        hasFix := hasFix || curFix
        saveStr := JSON.stringify(Data, 0)
        newContent .= Format("`n{}={}", Data.SerialStr, saveStr)
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

        curFix := false
        if (!ObjHasOwnProp(Data, "RunMode")) {
            Data.RunMode := 1
            Data.SaveNameArr := ["Var1", "Var2", "Var3"]
            curFix := true
        } else if (ObjHasOwnProp(Data, "SaveName")) {
            Data.SaveNameArr := [Data.SaveName, "Var2", "Var3"]
            Data.DeleteProp("SaveName")
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
