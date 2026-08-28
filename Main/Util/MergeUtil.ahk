#Requires AutoHotkey v2.0

class MergeTreeNode {
    __New() {
        this.Type := ""
        this.TabName := ""
        this.TabIndex := 0
        this.DisplayName := ""
        this.IsChecked := true
        this.Serial := ""
        this.TriggerKey := ""
        this.Remark := ""
        this.MacroStr := ""
        this.ResourceSerials := []
        this.ModuleName := ""
        this.ItemIndex := 0
        this.StartIndex := 0
        this.EndIndex := 0
        this.Children := []
        this.Level := 0
        this.ListViewRow := 0
        this.IsTabNode := false
    }
}

class MergeResult {
    __New() {
        this.SourceName := ""
        this.GroupName := ""
        this.ModuleCount := 0
        this.ImportTime := ""
        this.MergedItems := Map()
        this.RenamedResources := []
        this.RenamedVariables := []
        this.CopiedImages := []
    }
}

class MergeUtil {
    static TempMergeDir := ""

    ; 可合并页签：按 Symbol 读写源 MacroFile.ini，Index 映射到「当前程序」页签。
    ; 旧版（1.2 前）源配置无 UITKArr 等键 → 界面宏解析为空并跳过；
    ; 1.2+ 源配置有 UI 数据 → 正常导入到界面宏页签。无需单独版本分支。
    static GetMergeTabConfig() {
        tabs := []
        for symbol in ["Normal", "String", "Menu", "UI", "Voice", "Timing", "SubMacro", "Replace"] {
            idx := GetTableIndex(symbol)
            if (idx <= 0)
                continue
            tabs.Push({ Index: idx, Symbol: symbol, Name: MySoftData.TableInfo[idx].Name })
        }
        return tabs
    }

    static ParseSourceConfig(settingDir) {
        root := MergeTreeNode()
        root.Type := "Root"
        root.DisplayName := GetLang("全部宏")
        root.Level := 0

        tabConfig := MergeUtil.GetMergeTabConfig()
        for _, tabInfo in tabConfig {
            tabNode := MergeTreeNode()
            tabNode.Type := "Tab"
            tabNode.TabIndex := tabInfo.Index
            tabNode.TabName := tabInfo.Name
            tabNode.DisplayName := tabInfo.Name " (0" GetLang("项") ")"
            tabNode.Level := 1

            moduleNodes := MergeUtil.ParseMacroItemsByModule(settingDir, tabInfo.Symbol, tabInfo.Index)
            itemCount := 0
            for moduleNode in moduleNodes {
                moduleNode.Level := 2
                moduleNode.TabName := tabInfo.Name
                moduleNode.TabIndex := tabInfo.Index
                for item in moduleNode.Children {
                    item.Level := 3
                    item.TabName := tabInfo.Name
                    item.TabIndex := tabInfo.Index
                    item.ModuleName := moduleNode.ModuleName
                    if (item.TriggerKey != "" || item.Remark != "")
                        itemCount++
                }
                tabNode.Children.Push(moduleNode)
            }
            tabNode.DisplayName := "📁" tabInfo.Name " (" moduleNodes.Length GetLang("个模块") ")"
            if (moduleNodes.Length > 0)
                root.Children.Push(tabNode)
        }

        return root
    }

    static ParseMacroItemsByModule(settingDir, symbol, tabIndex) {
        macroFile := settingDir "\MacroFile.ini"
        if (!FileExist(macroFile))
            return []

        tkArrStr := IniRead(macroFile, "UserSettings", symbol "TKArr", "")
        remarkArrStr := IniRead(macroFile, "UserSettings", symbol "RemarkArr", "")
        modeArrStr := IniRead(macroFile, "UserSettings", symbol "ModeArr", "")

        modeArr := StrSplit(modeArrStr, "π")
        tkArr := StrSplit(tkArrStr, "π")
        remarkArr := StrSplit(remarkArrStr, "π")

        allItems := []
        loop modeArr.Length {
            node := MergeTreeNode()
            node.Type := "Item"
            node.TabIndex := tabIndex
            node.ItemIndex := A_Index
            node.TriggerKey := (A_Index <= tkArr.Length) ? tkArr[A_Index] : ""
            node.Remark := (A_Index <= remarkArr.Length) ? remarkArr[A_Index] : ""
            node.DisplayName := A_Index ". " node.Remark

            macroStr := IniRead(macroFile, "UserSettings", symbol "MacroArr" A_Index, "")
            macroStr := StrReplace(macroStr, "⫶", "`n")
            node.MacroStr := macroStr

            node.ResourceSerials := MergeUtil.ExtractResourceSerials(macroStr)

            allItems.Push(node)
        }

        foldInfo := MergeUtil.ParseFoldInfo(settingDir, symbol)

        if (!foldInfo || !ObjHasOwnProp(foldInfo, "IndexSpanArr") || !IsObject(foldInfo.IndexSpanArr) || foldInfo.IndexSpanArr
        .Length == 0) {
            defaultModule := MergeTreeNode()
            defaultModule.Type := "Module"
            defaultModule.ModuleName := GetLang("默认模块")
            defaultModule.DisplayName := "📦" GetLang("默认模块") " (" allItems.Length GetLang("项") ")"
            defaultModule.Children := allItems
            return [defaultModule]
        }

        moduleNodes := []
        indexSpanArr := foldInfo.IndexSpanArr
        foldRemarkArr := (ObjHasOwnProp(foldInfo, "RemarkArr") && IsObject(foldInfo.RemarkArr)) ? foldInfo.RemarkArr : ""

        indexSpanLen := IsObject(indexSpanArr) ? indexSpanArr.Length : 0
        foldRemarkArrLen := IsObject(foldRemarkArr) ? foldRemarkArr.Length : 0
        spanCount := (foldRemarkArrLen > 0) ? Min(indexSpanLen, foldRemarkArrLen) : indexSpanLen

        if (spanCount <= 0) {
            defaultModule := MergeTreeNode()
            defaultModule.Type := "Module"
            defaultModule.ModuleName := GetLang("默认模块")
            defaultModule.DisplayName := "📦" GetLang("默认模块") " (" allItems.Length GetLang("项") ")"
            defaultModule.Children := allItems
            return [defaultModule]
        }
        loop spanCount {
            foldIndex := A_Index
            spanRaw := (indexSpanArr.Has(foldIndex)) ? indexSpanArr[foldIndex] : ""
            if (!IsObject(spanRaw))
                spanStr := String(spanRaw)
            else
                spanStr := ""
            if (spanStr == "")
                continue

            moduleName := (IsObject(foldRemarkArr) && foldRemarkArr.Has(foldIndex)) ? String(foldRemarkArr[foldIndex]) : GetLang(
                "模块") foldIndex

            spanParts := StrSplit(spanStr, "-")
            startPart := Trim(spanParts[1])
            if (startPart == "" || !IsNumber(startPart))
                continue
            startIndex := Integer(startPart)
            endPart := (spanParts.Length > 1) ? Trim(spanParts[2]) : ""
            endIndex := (endPart != "" && IsNumber(endPart)) ? Integer(endPart) : startIndex

            moduleNode := MergeTreeNode()
            moduleNode.Type := "Module"
            moduleNode.ModuleName := moduleName
            moduleNode.StartIndex := startIndex
            moduleNode.EndIndex := endIndex
            moduleNode.DisplayName := "📦" moduleName " (" (endIndex - startIndex + 1) GetLang("项") ")"

            loop (endIndex - startIndex + 1) {
                idx := startIndex + A_Index - 1
                if (idx > allItems.Length)
                    break
                moduleNode.Children.Push(allItems[idx])
            }

            if (moduleNode.Children.Length > 0)
                moduleNodes.Push(moduleNode)
        }

        usedIndices := Map()
        for moduleNode in moduleNodes {
            loop (moduleNode.EndIndex - moduleNode.StartIndex + 1) {
                idx := moduleNode.StartIndex + A_Index - 1
                usedIndices.Set(idx, true)
            }
        }

        unassignedItems := []
        for idx, item in allItems {
            if (!usedIndices.Has(idx))
                unassignedItems.Push(item)
        }

        if (unassignedItems.Length > 0) {
            unassignedModule := MergeTreeNode()
            unassignedModule.Type := "Module"
            unassignedModule.ModuleName := GetLang("未分类")
            unassignedModule.DisplayName := "📦" GetLang("未分类") " (" unassignedItems.Length GetLang("项") ")"
            unassignedModule.Children := unassignedItems
            moduleNodes.Push(unassignedModule)
        }

        return moduleNodes
    }

    static ParseFoldInfo(settingDir, symbol) {
        macroFile := settingDir "\MacroFile.ini"
        if (!FileExist(macroFile))
            return ""

        foldInfoStr := IniRead(macroFile, IniSection, symbol "FoldInfo", "")
        if (foldInfoStr == "")
            return ""

        try {
            parsedObj := JSON.parse(foldInfoStr, , false)
            if (!IsObject(parsedObj))
                return ""

            if (!ObjHasOwnProp(parsedObj, "IndexSpanArr") || !ObjHasOwnProp(parsedObj, "RemarkArr"))
                return ""

            indexSpanArr := parsedObj.IndexSpanArr
            remarkArr := parsedObj.RemarkArr

            if (!IsObject(indexSpanArr))
                return ""
            if (indexSpanArr.Length == 0)
                return ""

            return parsedObj
        } catch as e {
            return ""
        }
    }

    static ExtractResourceSerials(macroStr) {
        serials := []
        if (macroStr == "")
            return serials

        cmdArr := SplitMacro(macroStr)
        if (!IsObject(cmdArr) || cmdArr.Length == 0)
            return serials

        for cmdStr in cmdArr {
            if (!IsObject(cmdStr))
                cmdStr := String(cmdStr)
            cleanCmd := GetCmdStr(String(cmdStr))
            if (cleanCmd == "")
                continue

            serialStr := MergeUtil.ExtractSerialFromCmdDirect(cleanCmd)
            if (serialStr != "" && !serials.Has(serialStr))
                serials.Push(serialStr)
        }

        return serials
    }

    static ExtractSerialFromCmdDirect(cmdStr) {
        if (cmdStr == "")
            return ""

        for cmdType, _ in MySoftData.DataFileMap {
            if (SubStr(cmdStr, 1, StrLen(cmdType)) != cmdType)
                continue

            afterType := SubStr(cmdStr, StrLen(cmdType) + 1)
            if (afterType == "")
                continue

            if (SubStr(afterType, 1, 1) == "_") {
                remaining := SubStr(afterType, 2)
                if (remaining == "")
                    continue

                nextUnderscore := InStr(remaining, "_")
                if (nextUnderscore > 0) {
                    potentialSerial := SubStr(remaining, 1, nextUnderscore - 1)
                    if (potentialSerial != "") {
                        for subType, _ in MySoftData.DataFileMap {
                            if (SubStr(potentialSerial, 1, StrLen(subType)) == subType) {
                                subAfter := SubStr(potentialSerial, StrLen(subType) + 1)
                                if (subAfter != "" && IsNumber(subAfter))
                                    return potentialSerial
                            }
                        }
                        if (IsNumber(potentialSerial))
                            return cmdType . potentialSerial
                    }
                }
                else {
                    if (IsNumber(remaining))
                        return cmdType . remaining
                }
            }
            else {
                underscorePos := InStr(afterType, "_")
                if (underscorePos > 0) {
                    pureSerial := SubStr(afterType, 1, underscorePos - 1)
                    if (pureSerial != "" && IsNumber(pureSerial))
                        return cmdType . pureSerial
                }
                else {
                    if (IsNumber(afterType))
                        return cmdType . afterType
                }
            }
        }

        for cmdType, _ in MySoftData.DataFileMap {
            typeLen := StrLen(cmdType)
            if (SubStr(cmdStr, 1, typeLen) == cmdType) {
                rest := SubStr(cmdStr, typeLen + 1)
                if (rest != "") {
                    match := RegExMatch(rest, "i)^_?([A-Za-z\x{4e00}-\x{9fff}]+\d+)")
                    if (match)
                        return match[1]
                    match := RegExMatch(rest, "^_?(\d+)")
                    if (match && match[1] != "")
                        return cmdType . match[1]
                }
            }
        }

        return ""
    }

    static HasAnyCheckedItem(node) {
        for child in node.Children {
            if (child.Type == "Item" && child.IsChecked)
                return true
            if (child.Type != "Item" && MergeUtil.HasAnyCheckedItem(child))
                return true
        }
        return false
    }

    static SetChildrenChecked(node, isChecked) {
        if (node.Type == "Item") {
            node.IsChecked := isChecked
        }
        for child in node.Children {
            MergeUtil.SetChildrenChecked(child, isChecked)
        }
    }

    static CollectAllResourceSerials(checkedItems) {
        allSerials := Map()
        for item in checkedItems {
            for serial in item.ResourceSerials {
                if (serial != "" && !allSerials.Has(serial))
                    allSerials.Set(serial, item.DisplayName)
            }
        }
        return allSerials
    }

    static CheckConflicts(checkedItems) {
        conflicts := []

        sourceSerials := MergeUtil.CollectAllResourceSerials(checkedItems)

        for serial, displayName in sourceSerials {
            cmdType := MergeUtil.InferSerialType(serial)
            if (cmdType == "")
                continue

            DataFile := MySoftData.DataFileMap[cmdType]
            if (DataFile == "")
                continue

            existingData := IniRead(DataFile, IniSection, serial, "")
            if (existingData != "") {
                conflicts.Push({
                    Serial: serial,
                    Type: cmdType,
                    SourceItemDisplayName: displayName,
                    ConflictType: "resource_exists"
                })
            }
        }

        return conflicts
    }

    ; 预览指令序列号重命名映射（old → new）；无冲突时返回空 Map
    static PreviewSerialReplaceMap(checkedItems, sourceSettingDir := "") {
        replaceMap := Map()
        if (sourceSettingDir == "")
            sourceSettingDir := MergeUtil.TempMergeDir != "" ? MergeUtil.TempMergeDir : ""
        if (sourceSettingDir == "")
            return replaceMap

        allSourceSerials := MergeUtil.CollectAllResourceSerials(checkedItems)
        if (GetObjectCount(allSourceSerials) == 0)
            return replaceMap

        collectedConfigs := MergeUtil.CollectSourceConfigs(sourceSettingDir, allSourceSerials)
        if (GetObjectCount(collectedConfigs) == 0)
            return replaceMap

        replaceInfo := MergeUtil.BuildSerialReplaceMap(collectedConfigs)
        if (!IsObject(replaceInfo) || !IsObject(replaceInfo.ReplaceMap))
            return replaceMap
        return replaceInfo.ReplaceMap
    }

    static InferSerialType(serialStr) {
        ; 与 MacroClipboardUtil.InferSerialTypeByPrefix 一致：最长前缀匹配
        if (serialStr == "")
            return ""
        bestType := ""
        bestLen := 0
        for cmdType, _ in MySoftData.DataFileMap {
            typeLen := StrLen(cmdType)
            if (typeLen <= bestLen || typeLen >= StrLen(serialStr))
                continue
            if (SubStr(serialStr, 1, typeLen) != cmdType)
                continue
            afterType := SubStr(serialStr, typeLen + 1)
            numPart := RegExReplace(afterType, "\D.*$", "")
            if (numPart != "" && IsNumber(numPart)) {
                bestType := cmdType
                bestLen := typeLen
            }
        }
        return bestType
    }

    static GetModuleCountFromItems(checkedItems) {
        moduleSet := Map()
        for item in checkedItems {
            moduleName := item.ModuleName != "" ? item.ModuleName : GetLang("默认模块")
            if (!moduleSet.Has(moduleName))
                moduleSet.Set(moduleName, true)
        }
        return GetObjectCount(moduleSet)
    }

    static GroupItemsByModule(checkedItems) {
        moduleGroups := Map()
        for item in checkedItems {
            moduleName := item.ModuleName != "" ? item.ModuleName : GetLang("默认模块")
            if (!moduleGroups.Has(moduleName))
                moduleGroups.Set(moduleName, [])
            moduleGroups[moduleName].Push(item)
        }
        return moduleGroups
    }

    ; 源配置依赖序列码收集：与 MacroClipboardUtil.FindDependentSerials 字段集一致，
    ; 但改用字符串解析提取（ExtractSerialFromCmdDirect）。合并源配置时依赖序列码尚未写入
    ; 当前目标配置，用 ExtractSerialFromCmd 会因「目标文件里查不到」而漏掉，或带出备注后缀
    ; （如 搜索Pro66_检索怪物 → 整串），导致后续 FindSerialTypeFromSource 读不到配置。
    static FindDependentSerialsFromSource(dataObj) {
        depSerials := []
        if (!IsObject(dataObj))
            return depSerials

        fieldsToCheck := ["MacroArr", "TrueMacroArr", "FalseMacroArr",
                           "StartMacroArr", "EndMacroArr",
                           "DefaultMacro", "SubMacro", "LoopBody",
                           "TrueMacro", "FalseMacro",
                           "NodeArr", "EmptyNode", "NextNodeArr", "CurCMD"]

        PushDep(serial) {
            if (serial != "")
                depSerials.Push(serial)
        }

        for fieldName in fieldsToCheck {
            try {
                if (!ObjAccess(dataObj, [fieldName]))
                    continue
                fieldValue := ObjAccess(dataObj, [fieldName])
                if (fieldValue == "")
                    continue

                if (IsObject(fieldValue)) {
                    for item in fieldValue {
                        if (item != "")
                            PushDep(MergeUtil.ExtractSerialFromCmdDirect(GetCmdStr(String(item))))
                    }
                } else if (fieldName == "CurCMD") {
                    PushDep(MergeUtil.ExtractSerialFromCmdDirect(GetCmdStr(String(fieldValue))))
                } else {
                    cmdList := SplitMacro(fieldValue)
                    for cmdStr in cmdList
                        PushDep(MergeUtil.ExtractSerialFromCmdDirect(GetCmdStr(String(cmdStr))))
                }
            } catch as e {
                continue
            }
        }

        return depSerials
    }

    static CollectSourceConfigs(sourceSettingDir, sourceSerials) {
        collectedConfigs := Map()

        sourceDataFileMap := MergeUtil.BuildSourceDataFileMap(sourceSettingDir)

        ; 队列式递归收集依赖链：
        ;   图形开始节点 → NodeArr(图形节点) → CurCMD(搜索Pro) → TrueMacro(嵌套图形开始节点) → …
        ; 必须把整条链全部收集并重映射序列码，否则合并后分支内指令（搜索Pro 真/假分支下的内容）全部丢失。
        queue := []
        for serial, _ in sourceSerials {
            if (serial != "" && !collectedConfigs.Has(serial))
                queue.Push(serial)
        }

        qi := 1
        while (qi <= queue.Length) {
            serial := queue[qi++]
            if (serial == "" || collectedConfigs.Has(serial))
                continue

            cmdType := MergeUtil.FindSerialTypeFromSource(serial, sourceDataFileMap)
            if (cmdType == "")
                continue

            Data := MergeUtil.ReadSourceConfigData(sourceSettingDir, serial, cmdType, sourceDataFileMap)
            if (!IsObject(Data))
                continue

            configJson := JSON.stringify(Data, 0)
            collectedConfigs.Set(serial, Map("类型", cmdType, "配置", configJson))

            depSerials := MergeUtil.FindDependentSerialsFromSource(Data)
            for depSerial in depSerials {
                if (depSerial != "" && !collectedConfigs.Has(depSerial))
                    queue.Push(depSerial)
            }
        }

        return collectedConfigs
    }

    static BuildSourceDataFileMap(sourceSettingDir) {
        fileMap := Map()
        for cmdType, targetDataFile in MySoftData.DataFileMap {
            fileName := RegExReplace(targetDataFile, ".*\\", "")
            sourceFilePath := sourceSettingDir "\" fileName
            if (FileExist(sourceFilePath)) {
                fileMap.Set(cmdType, sourceFilePath)
            }
            else {
                fileMap.Set(cmdType, targetDataFile)
            }
        }
        return fileMap
    }

    static ReadSourceConfigData(sourceSettingDir, serial, cmdType, sourceDataFileMap) {
        DataFile := sourceDataFileMap.Has(cmdType) ? sourceDataFileMap[cmdType] : MySoftData.DataFileMap[cmdType]
        if (DataFile == "")
            return ""

        saveStr := IniRead(DataFile, IniSection, serial, "")
        if (saveStr == "") {
            textOnly := RegExReplace(serial, "\d+")
            numbersOnly := RegExReplace(serial, "\D+")
            normalizedKey := GetLangKey(textOnly) . numbersOnly
            saveStr := IniRead(DataFile, IniSection, normalizedKey, "")
        }

        if (saveStr == "")
            return ""

        try {
            return JSON.parse(saveStr, , false)
        } catch as e {
            return ""
        }
    }

    static FindSerialTypeFromSource(serialStr, sourceDataFileMap) {
        ; 优先按前缀推断，避免源配置文件里误写入异种序列码时读错类型
        inferredType := MergeUtil.InferSerialType(serialStr)
        if (inferredType != "" && sourceDataFileMap.Has(inferredType)) {
            try {
                if (IniRead(sourceDataFileMap[inferredType], IniSection, serialStr, "") != "")
                    return inferredType
            } catch as e {
            }
        }

        for cmdType, DataFile in sourceDataFileMap {
            try {
                existingData := IniRead(DataFile, IniSection, serialStr, "")
                if (existingData != "")
                    return cmdType
            } catch as e {
            }
        }

        if (inferredType != "" && sourceDataFileMap.Has(inferredType))
            return inferredType

        return ""
    }

    static BuildSerialReplaceMap(collectedConfigs) {
        usedSerials := Map()
        serialReplaceMap := Map()
        parsedConfigs := []

        for serialStr, configInfo in collectedConfigs {
            try {
                if (serialStr == "" || !IsObject(configInfo))
                    continue

                configJsonStr := ObjAccess(configInfo, ["配置"])

                if (configJsonStr == "")
                    continue

                Data := JSON.parse(configJsonStr, , false)
                if (!IsObject(Data))
                    continue

                oldSerialStr := Data.SerialStr
                if (oldSerialStr == "") {
                    continue
                }

                parsedConfigs.Push(Map("oldSerial", oldSerialStr, "Data", Data))

                newSerialStr := GenerateUniqueSerialBatch(oldSerialStr, usedSerials)
                if (newSerialStr == "") {
                    continue
                }
                usedSerials.Set(newSerialStr, true)

                Data.SerialStr := newSerialStr

                if (newSerialStr != oldSerialStr) {
                    serialReplaceMap.Set(oldSerialStr, newSerialStr)
                }
            } catch as e {
            }
        }

        maxPasses := 10
        loop maxPasses {
            changedThisPass := false

            for i, configInfo in parsedConfigs {
                Data := configInfo["Data"]

                try {
                    UpdateConfigInternalRefs(Data, serialReplaceMap)
                } catch as e {
                }
            }

            if (!changedThisPass)
                break
        }

        return { ReplaceMap: serialReplaceMap, ParsedConfigs: parsedConfigs }
    }

    static ProcessAndSaveRenamedConfigs(replaceInfo, sourceSettingDir, result) {
        serialReplaceMap := replaceInfo.ReplaceMap
        parsedConfigs := replaceInfo.ParsedConfigs

        for i, configInfo in parsedConfigs {
            Data := configInfo["Data"]
            oldSerialStr := configInfo["oldSerial"]
            newSerialStr := Data.SerialStr

            if (newSerialStr != oldSerialStr && serialReplaceMap.Has(oldSerialStr)) {
                imageRenameCount := MergeUtil.RenameImagesForSerial(Data, oldSerialStr, newSerialStr, sourceSettingDir,
                    result)
            }

            try {
                SaveMacroCMDData(Data)
                result.RenamedResources.Push({ OldSerial: oldSerialStr, NewSerial: newSerialStr })
            } catch as e {
            }
        }

        return serialReplaceMap
    }

    static RenameImagesForSerial(Data, oldSerial, newSerial, sourceSettingDir, result) {
        renamedCount := 0

        if (oldSerial == "" || newSerial == "")
            return renamedCount

        if (!ObjHasOwnProp(Data, "SearchImagePath") || Data.SearchImagePath == "")
            return renamedCount

        sourceImagePath := Data.SearchImagePath
        if (!FileExist(sourceImagePath))
            return renamedCount

        SplitPath sourceImagePath, &imageFileName, &sourceImageDir, &imageExt, &imageNameNoExt

        targetImagesDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images"
        if (!DirExist(targetImagesDir))
            DirCreate(targetImagesDir)

        oldTextPart := RegExReplace(oldSerial, "\d+")
        newTextPart := RegExReplace(newSerial, "\d+")
        oldNumPart := RegExReplace(oldSerial, "\D+")
        newNumPart := RegExReplace(newSerial, "\D+")

        newImageName := RegExReplace(imageNameNoExt, oldTextPart . oldNumPart "$", newTextPart . newNumPart)
        if (newImageName == imageNameNoExt) {
            newImageName := newSerial "_" imageNameNoExt
        }

        targetImagePath := targetImagesDir "\" newImageName "." imageExt

        try {
            FileCopy(sourceImagePath, targetImagePath, true)
            if (FileExist(targetImagePath)) {
                Data.SearchImagePath := targetImagePath
                renamedCount++
                result.CopiedImages.Push({ SourcePath: sourceImagePath, TargetPath: targetImagePath })
            }
        } catch as e {
        }

        return renamedCount
    }

    static ApplySerialReplaceToMacros(checkedItems, serialReplaceMap) {
        updatedItems := []

        for item in checkedItems {
            newMacroStr := item.MacroStr

            for oldSerial, newSerial in serialReplaceMap {
                newMacroStr := ReplaceSerialInCmdList(newMacroStr, oldSerial, newSerial)
            }

            if (newMacroStr != item.MacroStr) {
                item.MacroStr := newMacroStr
            }

            updatedItems.Push(item)
        }

        return updatedItems
    }

    ; -----------------------------------------------------------------
    ; 变量冲突检测 / 仅导入侧重命名
    ; -----------------------------------------------------------------

    static IsSystemVarName(name) {
        if (name == "")
            return true
        for v in GetSystemVarArr() {
            if (name == v || name == GetLangKey(v))
                return true
        }
        builtins := ["宏循环次数", "循环次数", "循环-跳过本轮", "循环-跳出", "分支-跳出"]
        for b in builtins {
            if (name == b || name == GetLang(b) || name == GetLangKey(b))
                return true
        }
        return false
    }

    static AddVarNameCandidate(varMap, name) {
        try
            name := Trim(String(name))
        catch
            return
        if (name == "" || IsNumber(name))
            return
        if (InStr(name, "\") || InStr(name, "/") || InStr(name, "{") || InStr(name, "}"))
            return
        if (MergeUtil.IsSystemVarName(name))
            return
        varMap[name] := true
    }

    static CollectBraceVars(text, varMap) {
        if (text == "" || !IsObject(varMap))
            return
        pos := 1
        while (RegExMatch(text, "\{([^\{\}]+)\}", &m, pos)) {
            MergeUtil.AddVarNameCandidate(varMap, m[1])
            pos := m.Pos + m.Len
            if (pos <= 0)
                break
        }
    }

    static CollectVarsFromIntervalCmd(cmdStr, varMap) {
        if (cmdStr == "")
            return
        paramArr := StrSplit(cmdStr, "_")
        if (paramArr.Length < 2)
            return
        cmdKey := GetLangKey(GetCmdStr(paramArr[1]))
        if (cmdKey != "间隔")
            return
        rest := paramArr[2]
        loop (paramArr.Length - 2)
            rest .= "_" paramArr[A_Index + 2]
        if (InStr(rest, "~")) {
            parts := StrSplit(rest, "~")
            MergeUtil.AddVarNameCandidate(varMap, parts[1])
            if (parts.Length >= 2)
                MergeUtil.AddVarNameCandidate(varMap, parts[2])
        }
        else
            MergeUtil.AddVarNameCandidate(varMap, rest)
    }

    static CollectIntervalVarsInMacroStr(macroStr, varMap) {
        if (macroStr == "")
            return
        for cmdStr in SplitMacro(macroStr)
            MergeUtil.CollectVarsFromIntervalCmd(cmdStr, varMap)
    }

    static CollectVarsFromDataObj(Data, varMap) {
        if (!IsObject(Data) || !IsObject(varMap))
            return

        for f in ["ResultSaveName", "CoordXName", "CoordYName", "SaveName", "VariableName", "VarName", "Name", "ArgsName"] {
            if (ObjHasOwnProp(Data, f))
                MergeUtil.AddVarNameCandidate(varMap, Data.%f%)
        }

        for f in ["VariableArr", "CopyVariableArr", "MinVariableArr", "MaxVariableArr", "NameArr", "UpdateNameArr", "SaveNameArr"] {
            if (!ObjHasOwnProp(Data, f) || !IsObject(Data.%f%))
                continue
            for v in Data.%f% {
                if (IsObject(v)) {
                    for vv in v
                        MergeUtil.AddVarNameCandidate(varMap, vv)
                }
                else
                    MergeUtil.AddVarNameCandidate(varMap, v)
            }
        }

        if (ObjHasOwnProp(Data, "VariNameArr") && IsObject(Data.VariNameArr)) {
            for row in Data.VariNameArr {
                if (IsObject(row)) {
                    for vv in row
                        MergeUtil.AddVarNameCandidate(varMap, vv)
                }
                else
                    MergeUtil.AddVarNameCandidate(varMap, row)
            }
        }

        for f in ["PosVarX", "PosVarY", "StartPosX", "StartPosY", "EndPosX", "EndPosY",
            "RowVar", "ColVar", "RowEndVar", "ColEndVar", "TextRowVar", "InsertCount", "LoopCount",
            "MainIndex", "ArgsIndex", "PosX", "PosY", "Width", "Height", "Transparency"] {
            if (ObjHasOwnProp(Data, f))
                MergeUtil.AddVarNameCandidate(varMap, Data.%f%)
        }

        for f in ["Text", "Target", "StdIn", "FilePath", "Content", "ExtractStr", "SearchText",
            "SearchImagePath", "WinInfo", "SearchValue", "NewTitle", "Search", "Replace"] {
            if (ObjHasOwnProp(Data, f))
                MergeUtil.CollectBraceVars(Data.%f%, varMap)
        }
        if (ObjHasOwnProp(Data, "ExpressionArr") && IsObject(Data.ExpressionArr)) {
            for expr in Data.ExpressionArr
                MergeUtil.CollectBraceVars(expr, varMap)
        }

        for f in ["LoopBody", "TrueMacro", "FalseMacro", "DefaultMacro", "SubMacro"] {
            if (ObjHasOwnProp(Data, f) && Data.%f% != "")
                MergeUtil.CollectIntervalVarsInMacroStr(Data.%f%, varMap)
        }
        for f in ["MacroArr", "TrueMacroArr", "FalseMacroArr", "StartMacroArr", "EndMacroArr"] {
            if (!ObjHasOwnProp(Data, f) || !IsObject(Data.%f%))
                continue
            for m in Data.%f%
                MergeUtil.CollectIntervalVarsInMacroStr(m, varMap)
        }
    }

    ; 从勾选宏 + 已解析的导入配置中收集变量名
    static CollectImportVariableNames(checkedItems, sourceSettingDir, replaceInfo := "") {
        varMap := Map()
        sourceDataFileMap := MergeUtil.BuildSourceDataFileMap(sourceSettingDir)
        visitSerials := Map()

        for item in checkedItems {
            MergeUtil.CollectIntervalVarsInMacroStr(item.MacroStr, varMap)
            MergeUtil.CollectVarsWalkingMacro(item.MacroStr, sourceSettingDir, sourceDataFileMap, visitSerials, varMap)
        }

        if (IsObject(replaceInfo) && IsObject(replaceInfo.ParsedConfigs)) {
            for _, configInfo in replaceInfo.ParsedConfigs
                MergeUtil.CollectVarsFromDataObj(configInfo["Data"], varMap)
        }
        return varMap
    }

    static CollectVarsWalkingMacro(macroStr, sourceSettingDir, sourceDataFileMap, visitSerials, varMap) {
        if (macroStr == "")
            return
        for cmdStr in SplitMacro(macroStr) {
            MergeUtil.CollectVarsFromIntervalCmd(cmdStr, varMap)
            cleanCmd := GetCmdStr(String(cmdStr))
            serial := MergeUtil.ExtractSerialFromCmdDirect(cleanCmd)
            if (serial == "" || visitSerials.Has(serial))
                continue
            visitSerials[serial] := true
            cmdType := MergeUtil.FindSerialTypeFromSource(serial, sourceDataFileMap)
            if (cmdType == "")
                continue
            Data := MergeUtil.ReadSourceConfigData(sourceSettingDir, serial, cmdType, sourceDataFileMap)
            if (!IsObject(Data))
                continue
            MergeUtil.CollectVarsFromDataObj(Data, varMap)
            for f in ["LoopBody", "TrueMacro", "FalseMacro", "DefaultMacro", "SubMacro"] {
                if (ObjHasOwnProp(Data, f) && Data.%f% != "")
                    MergeUtil.CollectVarsWalkingMacro(Data.%f%, sourceSettingDir, sourceDataFileMap, visitSerials, varMap)
            }
            for f in ["MacroArr", "TrueMacroArr", "FalseMacroArr", "StartMacroArr", "EndMacroArr"] {
                if (!ObjHasOwnProp(Data, f) || !IsObject(Data.%f%))
                    continue
                for m in Data.%f%
                    MergeUtil.CollectVarsWalkingMacro(m, sourceSettingDir, sourceDataFileMap, visitSerials, varMap)
            }
        }
    }

    ; 检测与当前配置冲突的变量，生成导入侧重命名映射（不影响当前配置）
    ; Var1→Var2→Var3…；State→State1→State2…
    static BuildVarReplaceMap(sourceVarMap) {
        replaceMap := Map()
        if (!IsObject(sourceVarMap) || GetObjectCount(sourceVarMap) == 0)
            return replaceMap

        usedMap := Map()
        for k, _ in MySoftData.GlobalVariMap
            usedMap[k] := true
        for k, _ in sourceVarMap
            usedMap[k] := true

        for varName, _ in sourceVarMap {
            if (MergeUtil.IsSystemVarName(varName))
                continue
            if (!MySoftData.GlobalVariMap.Has(varName))
                continue
            newName := MergeUtil.GenerateUniqueVarName(varName, usedMap)
            if (newName == "" || newName == varName)
                continue
            replaceMap[varName] := newName
            usedMap[newName] := true
        }
        return replaceMap
    }

    static GenerateUniqueVarName(baseName, usedMap) {
        if (RegExMatch(baseName, "^(.*?)(\d+)$", &m)) {
            prefix := m[1]
            num := Integer(m[2]) + 1
        }
        else {
            prefix := baseName
            num := 1
        }
        loop 10000 {
            candidate := prefix num
            if (!usedMap.Has(candidate) && !MergeUtil.IsSystemVarName(candidate))
                return candidate
            num++
        }
        return prefix A_Now
    }

    ; 预览导入侧变量重命名映射（old → new）；无冲突时返回空 Map
    static PreviewVarReplaceMap(checkedItems, sourceSettingDir := "") {
        if (sourceSettingDir == "")
            sourceSettingDir := MergeUtil.TempMergeDir != "" ? MergeUtil.TempMergeDir : ""
        if (sourceSettingDir == "")
            return Map()
        sourceVarMap := MergeUtil.CollectImportVariableNames(checkedItems, sourceSettingDir, "")
        return MergeUtil.BuildVarReplaceMap(sourceVarMap)
    }

    static ApplyVarRenameToMacros(checkedItems, varReplaceMap) {
        if (!IsObject(varReplaceMap) || GetObjectCount(varReplaceMap) == 0)
            return checkedItems
        for item in checkedItems
            item.MacroStr := MergeUtil.ApplyVarRenameToMacroStr(item.MacroStr, varReplaceMap)
        return checkedItems
    }

    static ApplyVarRenameToMacroStr(macroStr, varReplaceMap) {
        if (macroStr == "" || !IsObject(varReplaceMap) || GetObjectCount(varReplaceMap) == 0)
            return macroStr
        cmdArr := SplitMacro(macroStr)
        result := ""
        for index, cmdStr in cmdArr {
            if (index > 1)
                result .= ","
            result .= MergeUtil.ApplyVarRenameToIntervalCmd(cmdStr, varReplaceMap)
        }
        return result
    }

    static ApplyVarRenameToIntervalCmd(cmdStr, varReplaceMap) {
        paramArr := StrSplit(cmdStr, "_")
        if (paramArr.Length < 2)
            return cmdStr
        cmdKey := GetLangKey(GetCmdStr(paramArr[1]))
        if (cmdKey != "间隔")
            return cmdStr
        rest := paramArr[2]
        loop (paramArr.Length - 2)
            rest .= "_" paramArr[A_Index + 2]
        if (InStr(rest, "~")) {
            parts := StrSplit(rest, "~")
            left := MergeUtil.ReplaceVarExact(parts[1], varReplaceMap)
            right := parts.Length >= 2 ? MergeUtil.ReplaceVarExact(parts[2], varReplaceMap) : ""
            rest := left "~" right
        }
        else
            rest := MergeUtil.ReplaceVarExact(rest, varReplaceMap)
        return paramArr[1] "_" rest
    }

    static ReplaceVarExact(val, varReplaceMap) {
        if (val == "" || !IsObject(varReplaceMap))
            return val
        val := String(val)
        return varReplaceMap.Has(val) ? varReplaceMap[val] : val
    }

    static ReplaceVarInText(text, varReplaceMap) {
        if (text == "" || !IsObject(varReplaceMap) || GetObjectCount(varReplaceMap) == 0)
            return text
        text := String(text)
        for oldName, newName in varReplaceMap
            text := StrReplace(text, "{" oldName "}", "{" newName "}")
        return text
    }

    static ApplyVarRenameToData(Data, varReplaceMap) {
        if (!IsObject(Data) || !IsObject(varReplaceMap) || GetObjectCount(varReplaceMap) == 0)
            return

        for f in ["ResultSaveName", "CoordXName", "CoordYName", "SaveName", "VariableName", "VarName", "Name", "ArgsName"] {
            if (ObjHasOwnProp(Data, f))
                Data.%f% := MergeUtil.ReplaceVarExact(Data.%f%, varReplaceMap)
        }

        for f in ["VariableArr", "CopyVariableArr", "MinVariableArr", "MaxVariableArr", "NameArr", "UpdateNameArr", "SaveNameArr"] {
            if (!ObjHasOwnProp(Data, f) || !IsObject(Data.%f%))
                continue
            arr := Data.%f%
            for i, v in arr {
                if (IsObject(v)) {
                    for j, vv in v
                        v[j] := MergeUtil.ReplaceVarExact(vv, varReplaceMap)
                }
                else
                    arr[i] := MergeUtil.ReplaceVarExact(v, varReplaceMap)
            }
        }

        if (ObjHasOwnProp(Data, "VariNameArr") && IsObject(Data.VariNameArr)) {
            for i, row in Data.VariNameArr {
                if (IsObject(row)) {
                    for j, vv in row
                        row[j] := MergeUtil.ReplaceVarExact(vv, varReplaceMap)
                }
                else
                    Data.VariNameArr[i] := MergeUtil.ReplaceVarExact(row, varReplaceMap)
            }
        }

        for f in ["PosVarX", "PosVarY", "StartPosX", "StartPosY", "EndPosX", "EndPosY",
            "RowVar", "ColVar", "RowEndVar", "ColEndVar", "TextRowVar", "InsertCount", "LoopCount",
            "MainIndex", "ArgsIndex", "PosX", "PosY", "Width", "Height", "Transparency"] {
            if (ObjHasOwnProp(Data, f))
                Data.%f% := MergeUtil.ReplaceVarExact(Data.%f%, varReplaceMap)
        }

        for f in ["Text", "Target", "StdIn", "FilePath", "Content", "ExtractStr", "SearchText",
            "SearchImagePath", "WinInfo", "SearchValue", "NewTitle", "Search", "Replace"] {
            if (ObjHasOwnProp(Data, f))
                Data.%f% := MergeUtil.ReplaceVarInText(Data.%f%, varReplaceMap)
        }
        if (ObjHasOwnProp(Data, "ExpressionArr") && IsObject(Data.ExpressionArr)) {
            for i, expr in Data.ExpressionArr
                Data.ExpressionArr[i] := MergeUtil.ReplaceVarInText(expr, varReplaceMap)
        }

        for f in ["LoopBody", "TrueMacro", "FalseMacro", "DefaultMacro", "SubMacro"] {
            if (ObjHasOwnProp(Data, f) && Data.%f% != "")
                Data.%f% := MergeUtil.ApplyVarRenameToMacroStr(Data.%f%, varReplaceMap)
        }
        for f in ["MacroArr", "TrueMacroArr", "FalseMacroArr", "StartMacroArr", "EndMacroArr"] {
            if (!ObjHasOwnProp(Data, f) || !IsObject(Data.%f%))
                continue
            for i, m in Data.%f%
                Data.%f%[i] := MergeUtil.ApplyVarRenameToMacroStr(m, varReplaceMap)
        }
    }

    static ExecuteMerge(checkedItems, sourceName) {
        result := MergeResult()
        result.SourceName := sourceName
        result.GroupName := ""
        result.ImportTime := FormatTime(, "yyyy-MM-dd HH:mm:ss")

        sourceDir := MergeUtil.TempMergeDir != "" ? MergeUtil.TempMergeDir : A_WorkingDir "\Setting\" sourceName

        allSourceSerials := MergeUtil.CollectAllResourceSerials(checkedItems)
        replaceInfo := ""
        serialReplaceMap := Map()

        if (GetObjectCount(allSourceSerials) > 0) {
            collectedConfigs := MergeUtil.CollectSourceConfigs(sourceDir, allSourceSerials)

            if (GetObjectCount(collectedConfigs) > 0) {
                replaceInfo := MergeUtil.BuildSerialReplaceMap(collectedConfigs)
                serialReplaceMap := replaceInfo.ReplaceMap
            }
        }

        ; 变量冲突：仅重命名导入侧，不影响当前配置已有变量
        sourceVarMap := MergeUtil.CollectImportVariableNames(checkedItems, sourceDir, replaceInfo)
        varReplaceMap := MergeUtil.BuildVarReplaceMap(sourceVarMap)
        if (GetObjectCount(varReplaceMap) > 0) {
            if (IsObject(replaceInfo) && IsObject(replaceInfo.ParsedConfigs)) {
                for _, configInfo in replaceInfo.ParsedConfigs
                    MergeUtil.ApplyVarRenameToData(configInfo["Data"], varReplaceMap)
            }
            checkedItems := MergeUtil.ApplyVarRenameToMacros(checkedItems, varReplaceMap)
            for oldName, newName in varReplaceMap
                result.RenamedVariables.Push({ OldName: oldName, NewName: newName })
        }

        if (IsObject(replaceInfo) && IsObject(replaceInfo.ParsedConfigs)) {
            serialReplaceMap := MergeUtil.ProcessAndSaveRenamedConfigs(replaceInfo, sourceDir, result)
            checkedItems := MergeUtil.ApplySerialReplaceToMacros(checkedItems, serialReplaceMap)
        }

        ; 导入侧新变量名登记到当前下拉列表（不覆盖旧名）
        for _, pair in result.RenamedVariables
            MySoftData.GlobalVariMap[pair.NewName] := true
        for varName, _ in sourceVarMap {
            if (!varReplaceMap.Has(varName))
                MySoftData.GlobalVariMap[varName] := true
        }

        MergeUtil.CopyNonConflictingImages(sourceDir, result)

        tabGrouped := Map()
        for _, tabInfo in MergeUtil.GetMergeTabConfig() {
            tabGrouped.Set(tabInfo.Index, [])
        }

        for item in checkedItems {
            if (tabGrouped.Has(item.TabIndex))
                tabGrouped[item.TabIndex].Push(item)
        }

        totalModuleCount := 0

        for tabIndex, items in tabGrouped {
            if (items.Length == 0)
                continue

            tableItem := MySoftData.TableInfo[tabIndex]

            moduleGroups := MergeUtil.GroupItemsByModule(items)

            for moduleName, moduleItems in moduleGroups {
                fold := MacroFold()
                fold.ID := GetFoldSerialStr()
                fold.Remark := moduleName " (" sourceName ")"
                tableItem.Folds.Push(fold)
                serialList := []

                for i, item in moduleItems {
                    newSerial := GetCMDSerialStr("Item")
                    if (newSerial == "")
                        newSerial := "Item" A_Now i
                    newTimingSerial := GetCMDSerialStr("Timing")
                    if (newTimingSerial == "")
                        newTimingSerial := newSerial

                    newItem := MacroItem()
                    newItem.ID := newSerial
                    newItem.TimingSerial := newTimingSerial
                    newItem.TK := item.TriggerKey
                    newItem.Mode := 1
                    newItem.Forbid := 0
                    newItem.Remark := item.Remark
                    newItem.LoopCount := 1
                    newItem.TriggerType := 1
                    newItem.HoldTime := 500
                    newItem.UnorderedTrigger := false
                    newItem.StartTipSound := 1
                    newItem.EndTipSound := 1
                    newItem.VoiceKeywords := ""
                    newItem.Macro := item.MacroStr
                    newItem.IcoPath := ""
                    newItem.FoldID := fold.ID
                    tableItem.Items.Push(newItem)
                    serialList.Push(newSerial)
                }

                if (IsObject(tableItem.FoldOffsetArr))
                    tableItem.FoldOffsetArr.Push(0)

                totalModuleCount++
            }
            tableItem.RebuildIndex()
            RebuildTableLocator()

            result.MergedItems.Set(tabIndex, [])
        }

        result.ModuleCount := totalModuleCount

        ; 仅保存可导入的宏页签，避免工具/设置等非宏页签越界
        for _, tabInfo in MergeUtil.GetMergeTabConfig() {
            if (tabGrouped.Has(tabInfo.Index) && tabGrouped[tabInfo.Index].Length > 0)
                SaveTableItemInfo(MySoftData.TableInfo[tabInfo.Index])
        }

        return result
    }

    static CopyNonConflictingImages(sourceSettingDir, result) {
        sourceImagesDir := sourceSettingDir "\Images"
        targetImagesDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images"

        if (!DirExist(sourceImagesDir))
            return

        if (!DirExist(targetImagesDir))
            DirCreate(targetImagesDir)

        loop files, sourceImagesDir "\*.*", "FR" {
            targetPath := targetImagesDir "\" A_LoopFileName
            if (!FileExist(targetPath)) {
                try {
                    FileCopy(A_LoopFilePath, targetPath, true)
                    result.CopiedImages.Push({ SourcePath: A_LoopFilePath, TargetPath: targetPath })
                }
            }
        }

        subDirs := ["ScreenShot", "SearchPro"]
        for subDir in subDirs {
            srcSub := sourceImagesDir "\" subDir
            tgtSub := targetImagesDir "\" subDir
            if (DirExist(srcSub)) {
                if (!DirExist(tgtSub))
                    DirCreate(tgtSub)

                loop files, srcSub "\*.*", "FR" {
                    tgtPath := tgtSub "\" A_LoopFileName
                    if (!FileExist(tgtPath)) {
                        try {
                            FileCopy(A_LoopFilePath, tgtPath, true)
                            result.CopiedImages.Push({ SourcePath: A_LoopFilePath, TargetPath: tgtPath })
                        }
                    }
                }
            }
        }
    }

    static PrepareTempFromRmt(rmtFilePath) {
        tempDir := A_Temp "\RMT_Merge_" A_Now
        if (DirExist(tempDir))
            DirDelete(tempDir, true)
        DirCreate(tempDir)

        FolderPackager.UnpackFile(rmtFilePath, tempDir)
        MySettingMgrGui.OnRepairSetting(tempDir)

        MergeUtil.TempMergeDir := tempDir
        return tempDir
    }

    static CleanupTemp() {
        if (MergeUtil.TempMergeDir != "" && DirExist(MergeUtil.TempMergeDir)) {
            try {
                DirDelete(MergeUtil.TempMergeDir, true)
            }
        }
        MergeUtil.TempMergeDir := ""
    }

    static GenerateDefaultGroupName(sourceName) {
        timeStr := FormatTime(, "MM-dd_HH-mm")
        return GetLang("导入") "_" sourceName "_" timeStr
    }
}
