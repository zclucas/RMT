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
        this.CopiedImages := []
    }
}

class MergeUtil {
    static TempMergeDir := ""

    static GetMergeTabConfig() {
        return [{ Index: 1, Symbol: "Normal", Name: "按键宏" }, { Index: 2, Symbol: "String", Name: "字串宏" }, { Index: 3,
            Symbol: "Menu", Name: "菜单宏" }, { Index: 4, Symbol: "Timing", Name: "定时宏" }, { Index: 5, Symbol: "SubMacro",
                Name: "宏" }, { Index: 6, Symbol: "Replace", Name: "按键替换" }
        ]
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
                for item in moduleNode.Children {
                    item.Level := 3
                    item.TabName := tabInfo.Name
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
            node.TriggerKey := tkArr.Has(A_Index) ? tkArr[A_Index] : ""
            node.Remark := remarkArr.Has(A_Index) ? remarkArr[A_Index] : ""

            displayKey := node.TriggerKey != "" ? node.TriggerKey : GetLang("无触发键")
            displayRemark := node.Remark != "" ? node.Remark : ""
            node.DisplayName := A_Index ". " displayRemark

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
        remarkArr := (ObjHasOwnProp(foldInfo, "RemarkArr") && IsObject(foldInfo.RemarkArr)) ? foldInfo.RemarkArr : ""

        indexSpanLen := IsObject(indexSpanArr) ? indexSpanArr.Length : 0
        remarkArrLen := IsObject(remarkArr) ? remarkArr.Length : 0
        spanCount := (remarkArrLen > 0) ? Min(indexSpanLen, remarkArrLen) : indexSpanLen

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

            moduleName := (IsObject(remarkArr) && remarkArr.Has(foldIndex)) ? String(remarkArr[foldIndex]) : GetLang(
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

    static InferSerialType(serialStr) {
        if (serialStr == "")
            return ""

        for cmdType, _ in MySoftData.DataFileMap {
            typeLen := StrLen(cmdType)
            if (typeLen >= StrLen(serialStr))
                continue

            if (SubStr(serialStr, 1, typeLen) == cmdType) {
                afterType := SubStr(serialStr, typeLen + 1)
                numPart := RegExReplace(afterType, "\D.*$", "")
                if (numPart != "" && IsNumber(numPart))
                    return cmdType
            }
        }
        return ""
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

    static CollectSourceConfigs(sourceSettingDir, sourceSerials) {
        collectedConfigs := Map()

        sourceDataFileMap := MergeUtil.BuildSourceDataFileMap(sourceSettingDir)

        for serial, _ in sourceSerials {
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

            depSerials := FindDependentSerials(Data)
            for depSerial in depSerials {
                if (!collectedConfigs.Has(depSerial)) {
                    depCmdType := MergeUtil.FindSerialTypeFromSource(depSerial, sourceDataFileMap)
                    if (depCmdType != "") {
                        depData := MergeUtil.ReadSourceConfigData(sourceSettingDir, depSerial, depCmdType,
                            sourceDataFileMap)
                        if (IsObject(depData)) {
                            depJson := JSON.stringify(depData, 0)
                            collectedConfigs.Set(depSerial, Map("类型", depCmdType, "配置", depJson))
                        }
                    }
                }
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
        for cmdType, DataFile in sourceDataFileMap {
            try {
                existingData := IniRead(DataFile, IniSection, serialStr, "")
                if (existingData != "")
                    return cmdType
            } catch as e {
            }
        }

        inferredType := MergeUtil.InferSerialType(serialStr)
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

    static ExecuteMerge(checkedItems, sourceName) {
        result := MergeResult()
        result.SourceName := sourceName
        result.GroupName := ""
        result.ImportTime := FormatTime(, "yyyy-MM-dd HH:mm:ss")

        sourceDir := MergeUtil.TempMergeDir != "" ? MergeUtil.TempMergeDir : A_WorkingDir "\Setting\" sourceName

        allSourceSerials := MergeUtil.CollectAllResourceSerials(checkedItems)

        if (GetObjectCount(allSourceSerials) > 0) {
            collectedConfigs := MergeUtil.CollectSourceConfigs(sourceDir, allSourceSerials)

            if (GetObjectCount(collectedConfigs) > 0) {
                replaceInfo := MergeUtil.BuildSerialReplaceMap(collectedConfigs)

                serialReplaceMap := MergeUtil.ProcessAndSaveRenamedConfigs(replaceInfo, sourceDir, result)

                checkedItems := MergeUtil.ApplySerialReplaceToMacros(checkedItems, serialReplaceMap)
            }
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
                startIndex := tableItem.ModeArr.Length + 1
                serialList := []

                for i, item in moduleItems {
                    curIndex := startIndex + i - 1

                    tableItem.TKArr.Push(item.TriggerKey)
                    tableItem.ModeArr.Push(1)
                    tableItem.ForbidArr.Push(0)
                    tableItem.RemarkArr.Push(item.Remark)
                    tableItem.LoopCountArr.Push(1)
                    tableItem.TriggerTypeArr.Push(1)
                    tableItem.HoldTimeArr.Push(500)
                    tableItem.UnorderedTriggerArr.Push(false)
                    tableItem.StartTipSoundArr.Push(1)
                    tableItem.EndTipSoundArr.Push(1)
                    tableItem.MacroArr.Push(item.MacroStr)

                    newSerial := GetCMDSerialStr("Item")
                    if (newSerial == "") {
                        continue
                    }
                    tableItem.SerialArr.Push(newSerial)

                    newTimingSerial := GetCMDSerialStr("Timing")
                    if (newTimingSerial == "") {
                        newTimingSerial := newSerial
                    }
                    tableItem.TimingSerialArr.Push(newTimingSerial)
                    serialList.Push(newSerial)

                    tableItem.KilledArr.Push(false)
                    tableItem.ActionCount.Push(0)
                    tableItem.HoldKeyArr.Push(Map())
                    tableItem.ToggleStateArr.Push(false)
                    tableItem.ToggleActionArr.Push("")
                    tableItem.IsWorkIndexArr.Push(false)
                    tableItem.PauseArr.Push(false)
                    tableItem.ColorStateArr.Push(0)

                    VariableMap := Map()
                    VariableMap["宏循环次数"] := 0
                    VariableMap["循环-跳过本轮"] := false
                    VariableMap["循环-跳出"] := false
                    VariableMap["分支-跳出"] := false
                    tableItem.VariableMapArr.Push(VariableMap)
                }

                foldInfo := tableItem.FoldInfo
                endIndex := tableItem.ModeArr.Length

                spanStr := startIndex "-" endIndex
                foldInfo.RemarkArr.Push(moduleName " (" sourceName ")")
                foldInfo.FrontInfoArr.Push("")
                foldInfo.IndexSpanArr.Push(spanStr)
                foldInfo.FoldStateArr.Push(false)
                foldInfo.ForbidStateArr.Push(0)

                foldInfo.TKTypeArr.Push(1)
                foldInfo.TKArr.Push("")
                foldInfo.HoldTimeArr.Push(500)
                foldInfo.UnorderedTriggerArr.Push(false)

                totalModuleCount++
            }

            result.MergedItems.Set(tabIndex, [])
        }

        result.ModuleCount := totalModuleCount

        loop MySoftData.TabNameArr.Length {
            tableItem := MySoftData.TableInfo[A_Index]
            SaveTableItemInfo(A_Index)
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
