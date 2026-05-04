#Requires AutoHotkey v2.0

; ============================================================================
; MacroClipboardUtil.ahk - 宏复制/粘贴功能工具库
; 
; 功能：
;   1. 复制宏指令集（含完整外部配置）到剪贴板（JSON格式）
;   2. 从剪贴板粘贴宏指令集（自动处理序列码冲突和嵌套引用）
;   3. 支持递归依赖收集（最多10层深度）
;   4. 支持跨设备迁移（自动重命名冲突配置）
;
; 依赖：
;   - JsonUtil.ahk (JSON.parse / JSON.stringify)
;   - 全局变量: MySoftData, IniSection
; ============================================================================


; ============================================================================
; 基础设施层 - 对象类型兼容性处理
; ============================================================================

; 通用对象属性访问器（兼容 Object 和 Map）
; 用法:
;   读取: ObjAccess(obj, ["key1", "key2"])     → 返回值或 ""
;   写入: ObjAccess(obj, ["key"], value)         → 返回 true/false
;   数组: ObjAccess(obj, ["arrKey"], val, index)  → 设置数组元素
ObjAccess(obj, keys, value?, index?) {
    for key in keys {
        try {
            if (Type(obj) == "Map") {
                if (IsSet(value)) {
                    if (IsSet(index)) {
                        arr := obj[key]
                        if (IsObject(arr)) {
                            arr[index] := value
                            return true
                        }
                    } else {
                        obj[key] := value
                        return true
                    }
                } else {
                    if (obj.Has(key))
                        return obj[key]
                }
            } else {
                if (IsSet(value)) {
                    if (IsSet(index)) {
                        arr := obj.%key%
                        if (IsObject(arr)) {
                            arr[index] := value
                            return true
                        }
                    } else {
                        obj.%key% := value
                        return true
                    }
                } else {
                    if (obj.HasOwnProp(key))
                        return obj.%key%
                }
            }
        } catch {
        }
    }
    return IsSet(value) ? false : ""
}

; 获取对象的属性数量（兼容 Object 和 Map）
GetObjectCount(obj) {
    if (!IsObject(obj))
        return 0
    try {
        return (Type(obj) == "Map") ? obj.Count : ObjCountOwnProps(obj)
    } catch {
        return 0
    }
}

ObjCountOwnProps(obj) {
    count := 0
    for prop in obj.OwnProps()
        count++
    return count
}

; 创建对象枚举器（兼容 Object 和 Map 的 for 循环）
EnumerateObject(obj) {
    keysArr := []
    if (Type(obj) == "Map") {
        for key, value in obj
            keysArr.Push(Map("key", key, "value", value))
    } else {
        try {
            for propName in obj.OwnProps()
                keysArr.Push(Map("key", propName, "value", obj.%propName%))
        } catch {
        }
    }
    return { Keys: keysArr, Index: 0 }
}


; ============================================================================
; 序列码解析层 - 从指令字符串中提取/验证序列码
; ============================================================================

; 查找序列码所属的指令类型（用于纯序列码格式，如"输出1"）
FindSerialType(serialStr) {
    ; 遍历所有已知的配置文件类型
    for cmdType, DataFile in MySoftData.DataFileMap {
        try {
            existingData := IniRead(DataFile, IniSection, serialStr, "")
            if (existingData != "")
                return cmdType
        } catch as e {
        }
    }
    return ""
}

; 从指令字符串中提取序列码（支持多种格式）
; 格式规范: [类型][数字]_备注  例: 搜索Pro1353532_0 /
; 其中 [类型][数字] 组成完整的唯一序列码，_ 后面全是备注
ExtractSerialFromCmd(cmdStr) {
    if (cmdStr == "")
        return ""

    cleanCmd := GetCmdStr(cmdStr)

    ; 策略1: 尝试匹配已知的类型前缀（格式: [类型][数字]_备注）
    for cmdType, DataFile in MySoftData.DataFileMap {
        if (SubStr(cleanCmd, 1, StrLen(cmdType)) == cmdType) {
            afterType := SubStr(cleanCmd, StrLen(cmdType) + 1)

            if (afterType == "")
                continue

            ; 从备注部分分离出纯序列码：找到第一个 _ 截断
            underscorePos := InStr(afterType, "_")
            if (underscorePos > 0) {
                pureSerial := SubStr(afterType, 1, underscorePos - 1)
                fullSerial := cmdType . pureSerial
                if (IniRead(DataFile, IniSection, fullSerial, "") != "")
                    return fullSerial
            }

            ; 如果没有 _ ，整个 afterType 就是序列码
            fullSerial := cmdType . afterType
            if (IniRead(DataFile, IniSection, fullSerial, "") != "")
                return fullSerial
        }
    }

    ; 策略2: 整体作为序列码在配置文件中查找
    if (FindSerialType(cleanCmd) != "")
        return cleanCmd

    ; 策略3: 尝试去掉尾部备注（兼容旧格式）
    trimmedSerial := RegExReplace(cleanCmd, "_(?=[^a-zA-Z0-9]).*$", "")
    if (trimmedSerial != "" && trimmedSerial != cleanCmd && FindSerialType(trimmedSerial) != "")
        return trimmedSerial

    return ""
}

; 在已知类型的配置文件中查找或验证序列码
FindOrValidateSerial(serialPart, cmdType) {
    if (serialPart == "")
        return ""

    DataFile := MySoftData.DataFileMap[cmdType]
    if (DataFile == "")
        return ""

    try {
        if (IniRead(DataFile, IniSection, serialPart, "") != "")
            return serialPart

        loop StrLen(serialPart) {
            testPart := SubStr(serialPart, 1, StrLen(serialPart) - A_Index)
            if (testPart == "")
                break
            if (IniRead(DataFile, IniSection, cmdType . testPart, "") != "")
                return cmdType . testPart
        }
    } catch {
    }

    return ""
}


; ============================================================================
; 配置收集层 - 递归收集指令的所有依赖配置
; ============================================================================

; 收集单个指令字符串对应的配置（返回是否成功收集）
CollectConfigForCmd(cmdStr, cmdConfigMap) {
    cleanCmd := GetCmdStr(cmdStr)

    if (cleanCmd == "")
        return false

    serialStr := ExtractSerialFromCmd(cleanCmd)

    if (serialStr == "")
        return false

    cmdType := FindSerialType(serialStr)
    if (cmdType == "") {
        paramArr := StrSplit(cleanCmd, "_")
        if (paramArr.Length >= 2 && MySoftData.DataFileMap.Has(paramArr[1])) {
            cmdType := paramArr[1]
        } else {
            return false
        }
    }

    if (cmdConfigMap.Has(serialStr))
        return true

    try {
        Data := GetMacroCMDData(serialStr)
        if (IsObject(Data)) {
            configJson := JSON.stringify(Data, 0)
            cmdConfigMap.Set(serialStr, Map("类型", cmdType, "配置", configJson))
            return true
        }
    } catch as e {
    }

    return false
}

; 从配置对象中查找所有依赖的序列码引用
FindDependentSerials(dataObj) {
    depSerials := []

    if (!IsObject(dataObj))
        return depSerials

    fieldsToCheck := ["MacroArr", "TrueMacroArr", "FalseMacroArr",
                       "StartMacroArr", "EndMacroArr",
                       "DefaultMacro", "SubMacro",
                       "TrueMacro", "FalseMacro"]

    for fieldName in fieldsToCheck {
        try {
            if (ObjAccess(dataObj, [fieldName])) {
                fieldValue := ObjAccess(dataObj, [fieldName])

                if (fieldValue != "") {
                    if (IsObject(fieldValue)) {
                        for item in fieldValue {
                            if (item != "") {
                                extractedSerial := ExtractSerialFromCmd(item)
                                if (extractedSerial != "")
                                    depSerials.Push(extractedSerial)
                            }
                        }
                    } else {
                        cmdList := SplitMacro(fieldValue)
                        for cmdStr in cmdList {
                            extractedSerial := ExtractSerialFromCmd(cmdStr)
                            if (extractedSerial != "")
                                depSerials.Push(extractedSerial)
                        }
                    }
                }
            }
        } catch as e {
            continue
        }
    }

    return depSerials
}


; ============================================================================
; 序列码生成层 - 批量生成无冲突的唯一序列码
; ============================================================================

; 批量生成唯一的序列码（避免与现有配置及同批次内其他配置冲突）
GenerateUniqueSerialBatch(baseSerial, usedSerials) {
    textOnly := RegExReplace(baseSerial, "\d+$")
    numbersOnly := RegExReplace(baseSerial, "\D")

    if (numbersOnly == "") {
        baseSerial := textOnly "1"
        textOnly := textOnly
        numbersOnly := "1"
    }

    maxAttempt := 100
    loop maxAttempt {
        candidate := textOnly numbersOnly

        if (usedSerials.Has(candidate)) {
            numbersOnly := Integer(numbersOnly) + 1
            continue
        }

        try {
            cmd := RegExReplace(candidate, "\d+")
            DataFile := MySoftData.DataFileMap[cmd]
            if (DataFile != "") {
                existingData := IniRead(DataFile, IniSection, candidate, "")
                if (existingData != "") {
                    numbersOnly := Integer(numbersOnly) + 1
                    continue
                }
            }
        } catch as e {
        }

        return candidate
    }

    return textOnly A_Now
}


; ============================================================================
; 引用更新层 - 替换配置中的旧序列码引用
; ============================================================================

; 递归更新配置对象内部的所有序列码引用
UpdateConfigInternalRefs(dataObj, replaceMap) {
    if (!IsObject(dataObj) || !IsObject(replaceMap) || replaceMap.Count == 0)
        return

    fieldsToUpdate := ["MacroArr", "TrueMacroArr", "FalseMacroArr",
                       "StartMacroArr", "EndMacroArr",
                       "DefaultMacro", "SubMacro",
                       "TrueMacro", "FalseMacro"]

    for fieldName in fieldsToUpdate {
        try {
            if (!ObjAccess(dataObj, [fieldName]))
                continue

            fieldValue := ObjAccess(dataObj, [fieldName])
            if (fieldValue == "")
                continue

            if (IsObject(fieldValue)) {
                for index, item in fieldValue {
                    if (item != "") {
                        for oldSerial, newSerial in replaceMap {
                            if (item == oldSerial)
                                ObjAccess(dataObj, [fieldName], newSerial, index)
                        }
                    }
                }
            } else {
                for oldSerial, newSerial in replaceMap {
                    newValue := ReplaceSerialInCmdList(fieldValue, oldSerial, newSerial)
                    if (newValue != fieldValue) {
                        fieldValue := newValue
                        ObjAccess(dataObj, [fieldName], newValue)
                    }
                }
            }
        } catch as e {
            continue
        }
    }
}

; 精确替换指令列表中的序列码引用（支持带后缀的序列码）
ReplaceSerialInCmdList(cmdList, oldSerial, newSerial) {
    result := ""
    pos := 1
    oldLen := StrLen(oldSerial)

    while (pos <= StrLen(cmdList)) {
        foundPos := InStr(cmdList, oldSerial, , pos)
        if (!foundPos) {
            result .= SubStr(cmdList, pos)
            break
        }

        result .= SubStr(cmdList, pos, foundPos - pos)

        nextCharPos := foundPos + oldLen
        if (nextCharPos > StrLen(cmdList)) {
            result .= newSerial
            break
        }

        nextChar := SubStr(cmdList, nextCharPos, 1)
        code := Ord(nextChar)
        isExtender := (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 19968 && code <= 40959)

        if (!isExtender) {
            result .= newSerial
        } else {
            result .= oldSerial
        }

        pos := nextCharPos
    }

    return result
}


; ============================================================================
; 主功能层 - 复制/粘贴入口函数
; ============================================================================

; 复制宏指令集（完整复制所有指令及外部配置，用于跨设备迁移）
OnItemCopyMacroBtnClick(tableItem, CopyIndex, *) {
    macroText := tableItem.MacroArr[CopyIndex]
    if (macroText == "") {
        MsgBox(GetLang("当前宏没有指令内容，无法复制"), GetLang("提示"))
        return
    }

    exportData := Map()
    exportData["版本"] := "RMTv1.2"
    exportData["导出时间"] := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    exportData["指令列表"] := macroText
    
    cmdConfigMap := Map()
    cmdArr := SplitMacro(macroText)

    ; 第1轮：收集直接引用的配置
    for cmdStr in cmdArr {
        CollectConfigForCmd(cmdStr, cmdConfigMap)
    }

    ; 第2-N轮：递归收集嵌套/依赖的配置（最多10层深度）
    maxDepth := 10
    loop maxDepth {
        newConfigsAdded := false

        for serialStr, configInfo in cmdConfigMap {
            try {
                innerJson := ""
                if (IsObject(configInfo)) {
                    innerJson := ObjAccess(configInfo, ["配置", "Config", "config"])
                }

                if (innerJson != "") {
                    innerData := JSON.parse(innerJson, , false)

                    if (IsObject(innerData)) {
                        depSerials := FindDependentSerials(innerData)

                        for depSerial in depSerials {
                            if (!cmdConfigMap.Has(depSerial)) {
                                if (CollectConfigForCmd(depSerial, cmdConfigMap))
                                    newConfigsAdded := true
                            }
                        }
                    }
                }
            } catch as e {
                continue
            }
        }

        if (!newConfigsAdded)
            break
    }

    exportData["指令配置"] := cmdConfigMap
    
    try {
        jsonString := JSON.stringify(exportData, , "  ")
    } catch as e {
        jsonString := Format(
            "[RMT指令集]`n"
            "版本: RMTv1.2`n"
            "导出时间: {}`n"
            "指令列表: {}",
            FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            macroText
        )
    }

    A_Clipboard := jsonString
    if (A_Clipboard == jsonString) {
        MsgBox(GetLang("已复制宏"))
    } else {
        MsgBox(GetLang("复制到剪贴板失败，请重试"), GetLang("错误"))
    }
}

; 粘贴宏指令集（从剪贴板读取完整指令集及配置）
OnItemPasteMacroBtnClick(tableItem, btn, *) {
    clipboardText := A_Clipboard
    if (clipboardText == "") {
        MsgBox(GetLang("剪贴板为空"), GetLang("提示"))
        return
    }

    importData := ""
    isRMTFormat := false

    try {
        trimmedText := Trim(clipboardText)

        if (SubStr(trimmedText, 1, 1) == "{") {
            importData := JSON.parse(trimmedText, , false)

            if (!IsObject(importData)) {
                isRMTFormat := false
            } else {
                hasVersion := ObjAccess(importData, ["版本", "Version", "version"]) != ""
                hasCmdList := ObjAccess(importData, ["指令列表", "CommandList", "commandList", "MacroList"]) != ""

                if (hasVersion && hasCmdList) {
                    isRMTFormat := true
                }
            }
        }
    } catch as e {
        isRMTFormat := false
    }

    result := MsgBox(GetLang("是否粘贴宏？"), GetLang("确认粘贴"), 1)
    if (result == "Cancel")
        return

    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[btn].itemConInfo.FoldIndex
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    titleHeight := isMenu ? 85 : 55
    AddIndex := GetFoldAddItemIndex(foldInfo, foldIndex)
    if (foldInfo.FoldStateArr[foldIndex])
        OnFoldBtnClick(tableItem, btn)

    isFirst := foldInfo.IndexSpanArr[foldIndex] == "无-无"
    UpdateFoldIndexInfo(foldInfo, AddIndex, foldIndex, true)
    RecycleTabItem(tableItem)

    if (isRMTFormat && importData != "") {
        newCmdList := ObjAccess(importData, ["指令列表", "CommandList", "commandList", "MacroList"])
        configMap := ObjAccess(importData, ["指令配置", "ConfigMap", "configMap"])

        parsedConfigs := []
        serialReplaceMap := Map()

        if (IsObject(configMap) && GetObjectCount(configMap) > 0) {

            enumObj := EnumerateObject(configMap)
            while (enumObj.Index < enumObj.Keys.Length) {
                try {
                    enumObj.Index++
                    serialStr := enumObj.Keys[enumObj.Index]["key"]
                    configInfo := enumObj.Keys[enumObj.Index]["value"]

                    configJsonStr := ""
                    if (IsObject(configInfo)) {
                        configJsonStr := ObjAccess(configInfo, ["配置", "Config", "config", "Data", "data"])
                    }

                    if (configJsonStr != "") {
                        Data := JSON.parse(configJsonStr, , false)
                    } else {
                        if (IsObject(configInfo)) {
                            Data := configInfo
                        } else {
                            Data := JSON.parse(configInfo, , false)
                        }
                    }

                    oldSerialStr := Data.SerialStr
                    parsedConfigs.Push(Map("oldSerial", oldSerialStr, "Data", Data))
                } catch as e {
                }
            }

            usedSerials := Map()

            for i, configInfo in parsedConfigs {
                oldSerialStr := configInfo["oldSerial"]
                Data := configInfo["Data"]

                newSerialStr := GenerateUniqueSerialBatch(oldSerialStr, usedSerials)
                usedSerials.Set(newSerialStr, true)

                Data.SerialStr := newSerialStr
                configInfo["newSerial"] := newSerialStr

                if (newSerialStr != oldSerialStr) {
                    if (!IsObject(serialReplaceMap))
                        serialReplaceMap := Map()
                    serialReplaceMap.Set(oldSerialStr, newSerialStr)
                }
            }

            maxPasses := 10

            loop maxPasses {
                changedThisPass := false

                for i, configInfo in parsedConfigs {
                    Data := configInfo["Data"]

                    try {
                        UpdateConfigInternalRefs(Data, serialReplaceMap)
                        SaveMacroCMDData(Data)
                    } catch as e {
                    }
                }

                if (!changedThisPass)
                    break
            }

            for i, configInfo in parsedConfigs {
                oldSerialStr := configInfo["oldSerial"]
                newSerialStr := configInfo["newSerial"]

                if (newSerialStr != oldSerialStr) {
                    newCmdList := ReplaceSerialInCmdList(newCmdList, oldSerialStr, newSerialStr)
                }
            }
        }

        if (newCmdList == "" || !IsObject(newCmdList) && StrLen(Trim(newCmdList)) == 0) {
            newCmdList := clipboardText
        }

        tableItem.ColorStateArr.InsertAt(AddIndex, 0)
        tableItem.TKArr.InsertAt(AddIndex, "")
        tableItem.TriggerTypeArr.InsertAt(AddIndex, 1)
        tableItem.MacroArr.InsertAt(AddIndex, newCmdList)
        tableItem.ModeArr.InsertAt(AddIndex, 1)
        tableItem.ForbidArr.InsertAt(AddIndex, 0)
        tableItem.RemarkArr.InsertAt(AddIndex, Format("{} {}", GetLang("从剪贴板导入"), FormatTime(, "HH:mm")))
        tableItem.LoopCountArr.InsertAt(AddIndex, "1")
        tableItem.HoldTimeArr.InsertAt(AddIndex, 500)
        tableItem.StartTipSoundArr.InsertAt(AddIndex, 1)
        tableItem.EndTipSoundArr.InsertAt(AddIndex, 1)
    } else {
        tableItem.ColorStateArr.InsertAt(AddIndex, 0)
        tableItem.TKArr.InsertAt(AddIndex, "")
        tableItem.TriggerTypeArr.InsertAt(AddIndex, 1)
        tableItem.MacroArr.InsertAt(AddIndex, clipboardText)
        tableItem.ModeArr.InsertAt(AddIndex, 1)
        tableItem.ForbidArr.InsertAt(AddIndex, 0)
        tableItem.RemarkArr.InsertAt(AddIndex, Format("{} {}", GetLang("从剪贴板导入"), FormatTime(, "HH:mm")))
        tableItem.LoopCountArr.InsertAt(AddIndex, "1")
        tableItem.HoldTimeArr.InsertAt(AddIndex, 500)
        tableItem.StartTipSoundArr.InsertAt(AddIndex, 1)
        tableItem.EndTipSoundArr.InsertAt(AddIndex, 1)
    }

    PosY := 1000000
    for index, value in tableItem.AllConArr {
        if (foldIndex == value.FoldIndex && PosY > value.OriPosY)
            PosY := value.OriPosY
    }

    PosY += titleHeight
    if (isFirst) {
        MySoftData.TabCtrl.UseTab(tableItem.Index)
        LoadItemFoldTip(tableItem, foldIndex, PosY)
        MySoftData.TabCtrl.UseTab()
    }

    afterHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
    tableItem.AllGroup[foldIndex].Move(, , , afterHei)

    addHei := isFirst ? 75 : 40
    tableItem.FoldOffsetArr[foldIndex] += addHei
    MySlider.RefreshTab()

    MsgBox(GetLang("已粘贴宏"))
}
