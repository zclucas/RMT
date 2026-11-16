#Requires AutoHotkey v2.0

SetGlobalData(macroStr, visitMap) {
    if (macroStr == "")
        return
        
    VariableMap := MySoftData.GlobalVariMap
    cmdArr := SplitMacro(macroStr)
    
    loop cmdArr.Length {
        paramArr := StrSplit(cmdArr[A_Index], "_")
        cmdName := GetCmdStr(paramArr[1])
        
        if (visitMap.Has(cmdName))
            continue
            
        visitMap[cmdName] := true
        SetCMDSerialData(cmdArr[A_Index])

        baseCmd := RTrim(cmdName, "0123456789")
        
        if (baseCmd == "按键" || baseCmd == "手柄") {
            if (!MySoftData.HasJoyMacro) {
                if (baseCmd == "手柄") {
                    MySoftData.HasJoyMacro := true
                } else {
                    SplitSerialTextAndNumbers(cmdName, &tOnly, &nOnly)
                    keyName := ""
                    if (nOnly != "") {
                        try keyName := GetMacroCMDData(cmdName).KeyName
                    } else if (paramArr.Length >= 3) {
                        keyName := paramArr[2]
                    }
                    MySoftData.HasJoyMacro := InStr(keyName, "Joy")
                }
            }
            continue
        }
            
        ; 過濾掉系統未登錄的指令類型（如 RMT指令 等），避免 DataFileMap 查詢崩潰
        if (!MySoftData.DataFileMap.Has(baseCmd))
            continue

        Data := GetMacroCMDData(cmdName)

        ; 每個指令的變量提取 + 子宏遞歸 合併在同一個 switch 裡
        switch baseCmd {
            case "变量", "变量提取":
                loop Data.ToggleArr.Length {
                    if (Data.ToggleArr[A_Index])
                        VariableMap[Data.VariableArr[A_Index]] := true
                }
            case "文本处理":
                if (Data.SaveType == "变量")
                    VariableMap[Data.SaveName] := true
                if (Data.SaveType == "数组")
                    MySoftData.GlobalArrMap[Data.SaveName] := true
            case "按键检测", "手柄检测":
                VariableMap[Data.VarName] := true
            case "运算":
                loop Data.ToggleArr.Length {
                    if (Data.ToggleArr[A_Index])
                        VariableMap[Data.UpdateNameArr[A_Index]] := true
                }
            case "数组":
                SetArrayDataNewArr(Data)
                SetArrayDataNewVar(Data)
            case "输入":
                if (Data.Type == "弹窗" || Data.Type == "状态" || Data.Type == "选择" || Data.Type == "多选")
                    VariableMap[Data.SaveName] := true
            case "网络请求":
                HttpRequestRegisterResults(Data)
            case "等待":
                if (Data.HasOwnProp("ResultSaveName") && Data.ResultSaveName != "")
                    VariableMap[Data.ResultSaveName] := true
            case "文件读写", "Excel":
                SetFileIOGlobalData(Data)
            case "运行", "运行Pro":
                if (Data.Mode = 2) {
                    if (Data.SaveNameArr[1] != "")
                        VariableMap[Data.SaveNameArr[1]] := true
                }
                else if (Data.Mode = 4) {
                    loop 3 {
                        if (Data.SaveNameArr[A_Index] != "")
                            VariableMap[Data.SaveNameArr[A_Index]] := true
                    }
                }
            case "循环":
                SetGlobalData(Data.LoopBody, visitMap)
            case "如果":
                if (Data.SaveToggle)
                    VariableMap[Data.SaveName] := true
                SetGlobalData(Data.TrueMacro, visitMap)
                SetGlobalData(Data.FalseMacro, visitMap)
            case "如果Pro":
                for index, value in Data.MacroArr {
                    SetGlobalData(value, visitMap)
                }
                SetGlobalData(Data.DefaultMacro, visitMap)
            case "搜索", "搜索Pro", "搜索All", "搜索Combo", "组合搜索", "搜索Multi":
                if (baseCmd == "搜索All")
                    MySoftData.GlobalArrMap[Data.AllSaveName] := true
                if (Data.ResultToggle)
                    VariableMap[Data.ResultSaveName] := true
                if (Data.CoordToogle) {
                    VariableMap[Data.CoordXName] := true
                    VariableMap[Data.CoordYName] := true
                }
                SetGlobalData(Data.TrueMacro, visitMap)
                SetGlobalData(Data.FalseMacro, visitMap)
            case "时间":
                subMode := TimeNormSubMode(Data)
                if (subMode == "获取时间变量" || subMode == "获取时间字符串") {
                    if (Data.Param1 != "") {
                        VariableMap[Data.Param1] := true
                        if (subMode == "获取时间变量")
                            MySoftData.TimeVarMap[Data.Param1] := true
                    }
                } else if (subMode == "时间计算") {
                    if (Data.Param4 != "")
                        VariableMap[Data.Param4] := true
                }
        }
    }
}

; 无类别时只列自定义变量，供保存结果等字段使用。
GetGuiVarArr(categories*) {
    reserved := Map()
    for _, keys in GetBuiltinVarGroups() {
        for key in keys {
            reserved[key] := true
            reserved[GetLang(key)] := true
        }
    }

    items := []
    seen := Map()
    sources := [MySoftData.GlobalVariMap]
    for category in categories {
        if (category == "timeVars") {
            if (MySoftData.HasOwnProp("TimeVarMap"))
                sources.Push(MySoftData.TimeVarMap)
            break
        }
    }
    for source in sources {
        for name in source {
            if (name != "" && !reserved.Has(name) && !seen.Has(name)) {
                seen[name] := true
                items.Push(name)
            }
        }
    }

    for category in categories {
        switch category {
            case "all": names := GetSpecialVarArr()
            case "text": names := GetBuiltinVarNames("clipboard", "dateText", "clockText")
            case "number": names := GetBuiltinVarNames("count", "x", "y", "calendar", "hour", "minute", "second", "timestamp")
            case "timeVars": continue
            default: names := GetBuiltinVarNames(category)
        }
        for name in names {
            if (!seen.Has(name)) {
                seen[name] := true
                items.Push(name)
            }
        }
    }
    return items
}

GetGuiVarReferences(categories*) {
    items := []
    for name in GetGuiVarArr(categories*)
        items.Push("{" name "}")
    return items
}

GetCompareGuiVarArr(operator) {
    if (IsNumber(operator))
        operator := CmdEnumCompare(operator)
    switch GetLangKey(operator) {
        case "大于", "大于等于", "小于", "小于等于":
            return GetGuiVarArr("number")
        case "字符包含", "包含", "正则匹配":
            return GetGuiVarArr("text")
        default:
            return GetGuiVarArr("all")
    }
}

CheckVarNameIfValid(Name) {
    if (Name == "") {
        RmtDialog.Info(Format(GetLang("结果变量名不规范：变量名不能为空")))
        return false
    }

    if (IsNumber(Name)) {
        RmtDialog.Info(Format(GetLang("结果变量名不规范：变量名不能是纯数字")))
        return false
    }

    if (InStr(Name, "_")) {
        RmtDialog.Info(Format(GetLang("结果变量名不规范：变量名不能包含下划线")))
        return false
    }
    return true
}

GetVarName(Name) {
    return GetLangKey(Name)
}
