#Requires AutoHotkey v2.0

SetGlobalData(macroStr, visitMap) {
    if (macroStr == "")
        return
        
    ; 预构建指令类型映射表（使用static局部变量，避免重复的InStr调用和全局变量声明问题）
    static CmdTypeMap := ""
    if (CmdTypeMap == "") {
        CmdTypeMap := Map()
        typeList := ["按键", "后台按键", "按键检测", "变量提取", "变量", "文本处理", "运算",
            "搜索Pro", "搜索", "循环", "如果Pro", "如果", "数组", "输入", "文件读写", "运行"]
        
        for typeName in typeList
            CmdTypeMap.Set(typeName, true)
        
        CmdTypeMap.Set("__VarRelateTypes", Map("变量", true, "变量提取", true, "文本处理", true,
            "如果", true, "运算", true, "搜索", true, "搜索Pro", true,
            "循环", true, "如果Pro", true, "数组", true, "输入", true,
            "文件读写", true, "运行", true, "按键检测", true))
    }
    
    VariableMap := MySoftData.GlobalVariMap
    cmdArr := SplitMacro(macroStr)
    
    loop cmdArr.Length {
        paramArr := StrSplit(cmdArr[A_Index], "_")
        cmdName := GetCmdStr(paramArr[1])
        
        if (visitMap.Has(cmdName))
            continue
            
        SetCMDSerialData(cmdArr[A_Index])
        
        ; 优化：使用预提取的基础名称进行单次InStr匹配
        baseCmd := RegExReplace(cmdName, "\d+")
        
        IsPressKey := InStr(baseCmd, "按键") && !InStr(baseCmd, "按键检测")
        IsBGKey := InStr(baseCmd, "后台按键")
        IsKeyCheck := InStr(baseCmd, "按键检测")
        IsExVariable := InStr(baseCmd, "变量提取")
        IsVariable := InStr(baseCmd, "变量") && !IsExVariable
        IsTextOps := InStr(baseCmd, "文本处理")
        IsOpera := InStr(baseCmd, "运算")
        IsSearchPro := InStr(baseCmd, "搜索Pro")
        IsSearch := InStr(baseCmd, "搜索") && !IsSearchPro
        IsLoop := InStr(baseCmd, "循环")
        IsIfPro := InStr(baseCmd, "如果Pro")
        IsIf := InStr(baseCmd, "如果") && !IsIfPro
        IsArray := InStr(baseCmd, "数组")
        IsInput := InStr(baseCmd, "输入")
        IsFileIO := InStr(baseCmd, "文件读写")
        IsRun := InStr(baseCmd, "运行")
        IsVarRelate := CmdTypeMap["__VarRelateTypes"].Has(baseCmd)
        
        if (!MySoftData.HasJoyMacro && IsPressKey && !IsBGKey && paramArr.Length >= 3) {
            MySoftData.HasJoyMacro := InStr(paramArr[2], "Joy")
        }

        if (!IsVarRelate)
            continue
            
        visitMap[cmdName] := true
        Data := GetMacroCMDData(cmdName)

        if (IsVariable || IsExVariable) {
            loop Data.ToggleArr.Length {
                if (Data.ToggleArr[A_Index])
                    VariableMap[Data.VariableArr[A_Index]] := true
            }
        }
        else if (IsTextOps) {
            if (Data.SaveType == "变量")
                VariableMap[Data.SaveName] := true
            if (Data.SaveType == "数组")
                MySoftData.GlobalArrMap[Data.SaveName] := true
        }
        else if (IsIf) {
            if (Data.SaveToggle) {
                VariableMap[Data.SaveName] := true
            }
        }
        else if (IsKeyCheck) {
            VariableMap[Data.VarName] := true
        }
        else if (IsOpera) {
            loop Data.ToggleArr.Length {
                if (Data.ToggleArr[A_Index])
                    VariableMap[Data.UpdateNameArr[A_Index]] := true
            }
        }
        else if (IsSearch || IsSearchPro) {
            if (Data.ResultToggle) {
                VariableMap[Data.ResultSaveName] := true
            }

            if (Data.CoordToogle) {
                VariableMap[Data.CoordXName] := true
                VariableMap[Data.CoordYName] := true
            }
        }
        else if (IsArray) {
            SetArrayDataNewArr(Data)
            SetArrayDataNewVar(Data)
        }
        else if (IsInput) {
            if (Data.Type == "弹窗" || Data.Type == "状态")
                VariableMap[Data.SaveName] := true
        }
        else if (IsFileIO) {
            SetFileIOGlobalData(Data)
        }
        else if (IsRun) {
            if (ObjHasOwnProp(Data, "RunMode")) {
                if (Data.RunMode == 2) {
                    if (Data.SaveNameArr[1] != "")
                        VariableMap[Data.SaveNameArr[1]] := true
                }
                else if (Data.RunMode == 3) {
                    loop 3 {
                        if (Data.SaveNameArr[A_Index] != "")
                            VariableMap[Data.SaveNameArr[A_Index]] := true
                    }
                }
            }
        }

        if (IsIf || IsSearch || IsSearchPro) {
            SetGlobalData(Data.TrueMacro, visitMap)
            SetGlobalData(Data.FalseMacro, visitMap)
        }
        else if (IsLoop) {
            SetGlobalData(Data.LoopBody, visitMap)
        }
        else if (IsIfPro) {
            for index, value in Data.MacroArr {
                SetGlobalData(value, visitMap)
            }
            SetGlobalData(Data.DefaultMacro, visitMap)
        }
    }
}

;mode 0自定义 1-所有 2-循环次数 3-坐标 4-句柄ID 5-颜色 6-可运算变量
GetGuiVarArr(Mode := 0) {
    ResultArr := []
    ResultMap := Map()
    SpecialKeyArr0 := []
    SpecialKeyArr1 := GetSystemVarArr()     ;所有系统变量
    SpecialKeyArr2 := [GetLang("循环次数"), GetLang("宏循环次数")]
    SpecialKeyArr3 := [GetLang("当前鼠标坐标X"), GetLang("当前鼠标坐标Y")]
    SpecialKeyArr4 := [GetLang("句柄ID")]
    SpecialKeyArr5 := [GetLang("当前鼠标颜色")]
    SpecialKeyArr6 := [GetLang("循环次数"), GetLang("宏循环次数"), GetLang("当前鼠标坐标X"), GetLang("当前鼠标坐标Y")]
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
        MsgBox(Format(GetLang("结果变量名不规范：变量名不能为空")))
        return false
    }

    if (IsNumber(Name)) {
        MsgBox(Format(GetLang("结果变量名不规范：变量名不能是纯数字")))
        return false
    }

    if (InStr(Name, "_")) {
        MsgBox(Format(GetLang("结果变量名不规范：变量名不能包含下划线")))
        return false
    }
    return true
}

;变量名需要替换掉运算符
GetVarName(Name) {
    Name := GetLangKey(Name)
    Name := StrReplace(Name, "+", "＋")
    Name := StrReplace(Name, "-", "－")
    Name := StrReplace(Name, "*", "×")
    Name := StrReplace(Name, "/", "÷")
    return Name
}
