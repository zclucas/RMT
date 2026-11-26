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

        baseCmd := GetCommandKey(RTrim(cmdName, "0123456789"))
        
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
                if (baseCmd == "变量")
                    RegisterHandleVariableRows(Data)
                loop Data.ToggleArr.Length {
                    if (Data.ToggleArr[A_Index])
                        VariableMap[Data.VariableArr[A_Index]] := true
                }
            case "文本处理":
                if (Data.HasOwnProp("LegacyTextProcess")) {
                    legacy := Data.LegacyTextProcess
                    for row, enabled in legacy.ToggleArr {
                        if (enabled && legacy.VariableArr.Has(row))
                            VariableMap[legacy.VariableArr[row]] := true
                    }
                    continue
                }
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
            case "窗口控件", "控件信息", "控件操作", "AI判断":
                RegisterCommandResultVars(Data)
                if (baseCmd == "AI判断" || WindowControl.UsesTimeout(CmdEnumZh(Data.ActionType, WindowControl.Actions)))
                    TimeoutPolicy.RegisterStatus(Data)
            case "YOLO检测":
                RegisterYoloVars(Data)
            case "翻译":
                RegisterTranslateVars(Data)
            case "进程管理":
                ProcessManage.RegisterOutputs(Data)
            case "窗口信息", "窗口操作", "窗口管理":
                WindowEnsureResults(Data)
                WindowRegisterResults(Data)
            case "浏览器":
                if (BrowserActions.UsesTimeout(CmdEnumZh(Data.ActionType, BrowserActions.Names)))
                    TimeoutPolicy.RegisterStatus(Data)
                if (Data.HasOwnProp("SaveVar") && Data.SaveVar != ""
                    && !BrowserActions.IsCloseAction(CmdEnumZh(Data.ActionType, BrowserActions.Names)))
                    for suffix in ["", "_Success", "_Error", "_ElapsedMs"]
                        VariableMap[Data.SaveVar suffix] := true
            case "网络请求":
                HttpRequestRegisterResults(Data)
            case "等待":
                if (Data.HasOwnProp("TimeoutStatusVar"))
                    TimeoutPolicy.RegisterStatus(Data)
                else if (Data.HasOwnProp("ResultSaveName") && Data.ResultSaveName != "")
                    VariableMap[Data.ResultSaveName] := true
            case "文件读写", "Excel":
                SetFileIOGlobalData(Data)
            case "运行", "运行Pro":
                mode := CmdEnumZh(Data.Mode, CmdEnumRunModeNames())
                count := mode == "等待+输入输出" ? 3 : mode == "等待+返回值" ? 1 : 0
                loop count {
                    if (Data.SaveNameArr.Has(A_Index) && Data.SaveNameArr[A_Index] != "")
                        VariableMap[Data.SaveNameArr[A_Index]] := true
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

; 只有明确读取句柄的变量行才加入窗口绑定候选，不按变量名猜测类型。
RegisterHandleVariableRows(data) {
    for i, enabled in data.ToggleArr {
        type := CmdEnumOpera(data.OperaTypeArr[i])
        source := data.CopyVariableArr[i]
        isHandle := type == "赋值"
            ? RegExMatch(source, "^\{([^{}\r\n]+)\}$", &reference) && GetBuiltinVarName(reference[1]) == "运行时句柄ID"
            : (type == "系统" || type == "数值") && GetBuiltinVarName(source) == "运行时句柄ID"
        if (enabled && data.VariableArr[i] != ""
            && isHandle)
            MySoftData.HandleVarMap[data.VariableArr[i]] := true
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
    for old in LegacyRuntimeVarNames() {
        reserved[old] := true
        reserved[GetLang(old)] := true
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
            if (CustomVariableNameError(name) == "" && !reserved.Has(name) && !seen.Has(name)) {
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
            return GetGuiVarReferences("number")
        case "字符包含", "包含", "正则匹配":
            return GetGuiVarReferences("text")
        default:
            return GetGuiVarReferences("all")
    }
}

CheckVarNameIfValid(Name) {
    Name := Trim(Name)
    if ((error := CustomVariableNameError(Name)) != "") {
        RmtDialog.Info(GetLang(error))
        return false
    }

    if (InStr(Name, "_")) {
        RmtDialog.Info(Format(GetLang("结果变量名不规范：变量名不能包含下划线")))
        return false
    }
    return true
}

GetVarName(Name) {
    ; 保存目标不能因系统变量显示名转换而绕过名称校验。
    return InStr(Name, "❖") ? Name : GetLangKey(Name)
}
