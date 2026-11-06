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

GetTimeVarArr() {
    ResultArr := []
    if (IsObject(MySoftData) && MySoftData.HasOwnProp("TimeVarMap")) {
        for Key in MySoftData.TimeVarMap {
            ResultArr.Push(Key)
        }
    }
    return ResultArr
}

;mode 0自定义 1-所有 2-循环次数 3-坐标 4-句柄ID 5-颜色 6-可运算变量 7-时间变量
GetGuiVarArr(Mode := 0) {
    if (Mode == 7) {
        return GetTimeVarArr()
    }
    ResultArr := []
    ResultMap := Map()
    SpecialKeyArr0 := []
    SpecialKeyArr1 := GetSpecialVarArr()     ;系统 + 时间类别
    SpecialKeyArr2 := [GetLang("循环次数"), GetLang("宏循环次数")]
    SpecialKeyArr3 := [GetLang("当前坐标X"), GetLang("当前坐标Y")]
    SpecialKeyArr4 := [GetLang("句柄ID")]
    SpecialKeyArr5 := [GetLang("当前鼠标颜色")]
    SpecialKeyArr6 := [GetLang("循环次数"), GetLang("宏循环次数"), GetLang("当前坐标X"), GetLang("当前坐标Y")]
    SpecialMap := Map(0, SpecialKeyArr0, 1, SpecialKeyArr1, 2, SpecialKeyArr2, 3, SpecialKeyArr3, 4, SpecialKeyArr4, 5,
        SpecialKeyArr5, 6, SpecialKeyArr6)
    SpecialKeyArr := SpecialMap[Mode]

    ; 添加全局变量（如果不存在）
    for Key in MySoftData.GlobalVariMap {
        if !ResultMap.Has(Key) {
            ResultMap[Key] := true
        }
    }

    ;为了让特殊变量出现在末尾，先删除
    for curKey in SpecialKeyArr {
        if ResultMap.Has(curKey) {
            ResultMap.Delete(curKey)
        }
    }

    ; 将映射的键收集到数组中
    for Key in ResultMap {
        ResultArr.Push(Key)
    }

    Length := ResultArr.Length
    loop Length {
        i := A_Index
        loop Length - i {
            j := A_Index + i
            if (!StrCompare(ResultArr[i], ResultArr[j])) {
                temp := ResultArr[i]
                ResultArr[i] := ResultArr[j]
                ResultArr[j] := temp
            }
        }
    }

    ResultArr.Push(SpecialKeyArr*)
    return ResultArr
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