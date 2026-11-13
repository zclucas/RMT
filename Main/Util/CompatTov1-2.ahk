#Requires AutoHotkey v2.0

; 截至 1.2.2 的历史配置修正，仅主程序需要（入口：Gui\SettingMgrGui.ahk）
; 配置文件统一为 TOML：读写走 ConfigUtil 的 CfgRead/CfgWrite，文件路径由调用方给出
; 由 Main\GlobalUtil.ahk 引入，Worker(Thread\Work.ahk) 不加载本文件
; 旧资源字段转换由配置升级入口加载。

CompatMacro(MacroStr, &isFix) {
    CMDArr := SplitMacro(MacroStr)
    isFix := false
    modifyKeyMap := Map("移动Pro", 1, "搜索", 1, "搜索Pro", 1, "搜索Combo", 1, "组合搜索", 1, "搜索Multi", 1, "运行", 1, "运行Pro", 1, "如果", 1, "如果Pro", 1, "输出", 1, "变量", 1,
        "变量提取", 1, "宏操作", 1, "运算", 1, "后台鼠标", 1, "后台按键", 1, "循环", 1, "时间", 1, "倒计时", 1, "等待", 1, "等待确定", 1)
    loop CMDArr.Length {
        paramArr := SplitCommand(CMDArr[A_Index])
        cmdSymbol := GetCmdSymbol(paramArr[1])
        cleanName := GetCmdStr(paramArr[1])
        CMDArr[A_Index] := cleanName SubStr(CMDArr[A_Index], StrLen(paramArr[1]) + 1)
        paramArr[1] := cleanName

        ;1.0.9F3 间隔指令调整 统一使用两个参数  调整处理时机
        if (paramArr[1] == "间隔" && paramArr.Length == 3) {
            isFix := true
            paramArr[2] := paramArr[3]
            paramArr.RemoveAt(3)
            CMDArr[A_Index] := GetCmdByParams(paramArr)
        }

        ;1.1F1 按键指令动作类型改成中文（轴行无类型仅2段，须先判长度避免越界）
        if (paramArr[1] == "按键" && paramArr.Length >= 3 && IsInteger(paramArr[3])) {
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

; 段内键名迁移：Symbol<数字> → NewSymbol<数字>（Symbol 按正则片段传入，如 "Compare\+"）
CompatSerial(FilePath, Symbol, NewSymbol) {
    if (!FileExist(FilePath))
        return false

    renamed := Map()
    for key, _ in CfgSection(FilePath, SettingSection) {
        if (RegExMatch(key, "^" Symbol "(\d+)$", &m)) {
            newKey := NewSymbol . m[1]
            if (newKey != key)
                renamed[key] := newKey
        }
    }
    if (renamed.Count == 0)
        return false

    for oldKey, newKey in renamed {
        val := CfgRead(FilePath, SettingSection, oldKey, "")
        CfgWrite(val, FilePath, SettingSection, newKey)
        CfgDelete(FilePath, SettingSection, oldKey)
    }
    return true
}

; 旧文件名并入新文件：目标不存在则复制；两边都有则补目标缺失的键
CompatMergeTomlKeys(srcPath, destPath) {
    if (!FileExist(srcPath))
        return false
    if (!FileExist(destPath)) {
        FileCopy(srcPath, destPath)
        return true
    }
    hasFix := false
    for key, val in CfgSection(srcPath, SettingSection) {
        if (CfgRead(destPath, SettingSection, key, "") == "") {
            CfgWrite(val, destPath, SettingSection, key)
            hasFix := true
        }
    }
    return hasFix
}

CompatPath(FilePath, Data) {
    if (!IsObject(Data))
        return false
    SplitPath FilePath, , &settingDir

    changed := CompatPathTarget(settingDir, Data)
    if (ObjHasOwnProp(Data, "SearchTargetArr") && IsObject(Data.SearchTargetArr)) {
        for target in Data.SearchTargetArr {
            if (IsObject(target))
                changed := CompatPathTarget(settingDir, target) || changed
        }
    }
    return changed
}

CompatPathTarget(settingDir, Data) {
    if (!IsObject(Data) || !ObjHasOwnProp(Data, "SearchImagePath") || Data.SearchImagePath == "")
        return false
    ; 当前配置内仍有效的图片可以位于任意子目录。
    path := StrReplace(Data.SearchImagePath, "/", "\")
    if (!RegExMatch(path, "i)^(?:[a-z]:\\|\\\\)"))
        path := A_WorkingDir "\" path
    if (InStr(path, settingDir "\") == 1 && FileExist(path) && !DirExist(path))
        return false
    ; 优先识别配置的资源根，避免把同名配置或安装路径中的 Images 当成资源目录。
    ; 包内相对路径和导入临时目录仍可直接按 Images 定位。
    if (RegExMatch(Data.SearchImagePath, "i)(?:^|[\\/])Setting[\\/][^\\/]+[\\/]Images[\\/](.+)$", &m)
        || RegExMatch(Data.SearchImagePath, "i)(?:^|[\\/])Images[\\/](.+)$", &m)) {
        newPath := settingDir "\Images\" StrReplace(m[1], "/", "\")
        if (FileExist(newPath) && !DirExist(newPath)) {
            if (newPath = Data.SearchImagePath)
                return false
            Data.SearchImagePath := newPath
            return true
        }
    }
    ; 旧版“选择图片”只记录外部绝对路径。原图尚在时收进配置，导出才会携带。
    ; 变量名/表达式不按文件处理，缺失的原图也不伪造替代路径。
    if (RegExMatch(Data.SearchImagePath, "i)^(?:[a-z]:[\\/]|\\\\)")
        && FileExist(Data.SearchImagePath) && !DirExist(Data.SearchImagePath)) {
        newPath := StoreSearchImage(Data.SearchImagePath, settingDir)
        if (newPath != Data.SearchImagePath) {
            Data.SearchImagePath := newPath
            return true
        }
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

; 补齐/修复 TimingSerialArr：禁止用 "0" 占位（否则定时编辑会把键 0 写入 TimingFile.toml）
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
        "VoiceTriggerArr", "0",
        "VoiceKeywordsArr", "",
        "IcoPathArr", "",
        "SerialArr", "0"
    )
    for def in CreateDefaultTableDefs() {
        symbol := def[1]
        modeArrStr := CfgRead(filePath, SettingSection, symbol "ModeArr", "")
        if (modeArrStr == "")
            continue
        baseLen := StrSplit(modeArrStr, "π").Length
        for fieldName, defaultValue in arrFields {
            savedStr := CfgRead(filePath, SettingSection, symbol fieldName, "")
            if (savedStr == "") {
                newStr := ""
                loop baseLen {
                    newStr .= defaultValue
                    if (A_Index < baseLen)
                        newStr .= "π"
                }
                CfgWrite(newStr, filePath, SettingSection, symbol fieldName)
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
                    CfgWrite(newStr, filePath, SettingSection, symbol fieldName)
                    hasFix := true
                }
            }
        }
        ; TimingSerialArr：缺失、过短或含非法值（如旧逻辑填的 0）时按 TimingN 修复
        timingSaved := CfgRead(filePath, SettingSection, symbol "TimingSerialArr", "")
        timingChanged := false
        timingNew := CompatFixTimingSerialArr(timingSaved, baseLen, &timingChanged)
        if (timingChanged || timingSaved == "") {
            CfgWrite(timingNew, filePath, SettingSection, symbol "TimingSerialArr")
            hasFix := true
        }
    }
    for def in CreateDefaultTableDefs() {
        symbol := def[1]
        loop {
            MacroLabel := symbol "MacroArr" A_Index
            MacroStr := CfgRead(filePath, SettingSection, MacroLabel, "默认空文本")
            if (MacroStr == "默认空文本")
                break

            MacroStr := CompatMacro(MacroStr, &isFix)
            if (isFix) {
                hasFix := true
                CfgWrite(MacroStr, filePath, SettingSection, MacroLabel)
            }
        }

    }
    return hasFix
}

CompatTiming(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    for key, val in CfgSection(filePath, SettingSection) {
        ; 只保留 TimingN 键；丢弃误写入的异种序列码（如 0、移动Pro、搜索Pro）
        if (!RegExMatch(key, "^Timing\d+$")) {
            CfgDelete(filePath, SettingSection, key)
            hasFix := true
            continue
        }
        Data := TryParseCommandData(val)
        if (Data == "")
            continue

        curFix := false
        ; 以段键为准写回（新版 SaveTimingData 可能不落 SerialStr 字段）
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != key) {
            Data.SerialStr := key
            curFix := true
        }

        curFix := CompatNormalizeTimingData(Data) || curFix
        if (Data.HasOwnProp("StartTime")) {
            Data.DeleteProp("StartTime")
            curFix := true
        }
        if (Data.HasOwnProp("EndTime")) {
            Data.DeleteProp("EndTime")
            curFix := true
        }
        if (Data.HasOwnProp("NextStamp")) {
            Data.DeleteProp("NextStamp")
            curFix := true
        }

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatSearch(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Search", "搜索")
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
        if (Data == "")
            continue
        curFix := CompatPath(filePath, Data)

        if (Data.HasOwnProp("TrueMacro") && Data.TrueMacro != "") {
            Data.TrueMacro := CompatMacro(Data.TrueMacro, &isFix)
            curFix := curFix || isFix
        }

        if (Data.HasOwnProp("FalseMacro") && Data.FalseMacro != "") {
            Data.FalseMacro := CompatMacro(Data.FalseMacro, &isFix)
            curFix := curFix || isFix
        }

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatSearchPro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Search", "搜索Pro") || hasFix
    hasFix := CompatSerial(filePath, "Search\+", "搜索Pro") || hasFix
    for key, val in CfgSection(filePath, SettingSection) {
        ; 丢弃误写入的异种序列码（如移动Pro 被写进 SearchProFile）
        if (!RegExMatch(key, "^搜索Pro\d+$")) {
            CfgDelete(filePath, SettingSection, key)
            hasFix := true
            continue
        }
        Data := TryParseCommandData(val)
        if (Data == "")
            continue

        curFix := false
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != key) {
            Data.SerialStr := key
            curFix := true
        }

        curFix := CompatPath(filePath, Data) || curFix
        ; 1.3 已移除窗口规则，不再按导入机器分辨率切换 ConfigArr。
        if (!ObjHasOwnProp(Data, "WinInfo")) {
            Data.WinInfo := ""
            curFix := true
        }

        if (Data.HasOwnProp("TrueMacro") && Data.TrueMacro != "") {
            Data.TrueMacro := CompatMacro(Data.TrueMacro, &isFix)
            curFix := curFix || isFix
        }

        if (Data.HasOwnProp("FalseMacro") && Data.FalseMacro != "") {
            Data.FalseMacro := CompatMacro(Data.FalseMacro, &isFix)
            curFix := curFix || isFix
        }

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatMMPro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "MMPro", "移动Pro") || hasFix
    for key, val in CfgSection(filePath, SettingSection) {
        ; 丢弃误写入的异种序列码（如搜索Pro 被写进 MMProFile）
        if (!RegExMatch(key, "^(移动Pro|鼠标移动Pro)\d+$")) {
            CfgDelete(filePath, SettingSection, key)
            hasFix := true
            continue
        }
        Data := TryParseCommandData(val)
        if (Data == "")
            continue

        curFix := false
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != key) {
            Data.SerialStr := key
            curFix := true
        }
        ;1.0.8F7到新版本兼容, 新增鼠标类型
        ;如果有了，那就说明是新版本，不需要兼容处理
        if (!ObjHasOwnProp(Data, "ActionType")) {
            Data.ActionType := 1
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

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatOutput(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    FixTypeMap := Map("1", "发送内容", "2", "粘贴内容", "3", "临时提示",
        "4", "指令窗口", "5", "软件弹窗", "6", "系统语音", "7", "复制到剪切板")
    hasFix := CompatSerial(filePath, "Output", "输出")
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
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
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatRun(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Run", "运行")

    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
        if (Data == "")
            continue

        ; 字段补齐 / RunMode→Mode 等（含无 Mode 的 1.1.x 配置）
        curFix := CompatEnsureRunData(Data)

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }

    return hasFix
}

CompatTime(filePath) {
    hasFix := false
    if (!FileExist(filePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Time", "时间") || hasFix
    for key, val in CfgSection(filePath, SettingSection) {
        if (!RegExMatch(key, "^(时间|倒计时)\d+$"))
            continue
        Data := TryParseCommandData(val)
        if (Data == "")
            continue
        curFix := false
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != key) {
            Data.SerialStr := key
            curFix := true
        }
        curFix := CompatEnsureTimeData(Data) || curFix
        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatCountDown(filePath) {
    hasFix := false
    if (!FileExist(filePath))
        return hasFix
    hasFix := CompatSerial(filePath, "CountDown", "倒计时") || hasFix
    for key, val in CfgSection(filePath, SettingSection) {
        if (!RegExMatch(key, "^倒计时\d+$"))
            continue
        Data := TryParseCommandData(val)
        if (Data == "")
            continue
        curFix := false
        if (!Data.HasOwnProp("SerialStr") || Data.SerialStr != key) {
            Data.SerialStr := key
            curFix := true
        }
        curFix := CompatEnsureCountDownData(Data) || curFix
        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatLoop(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    hasFix := CompatSerial(filePath, "Loop", "循环")
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
        if (Data == "")
            continue

        curFix := false
        if (Data.LoopBody != "") {
            Data.LoopBody := CompatMacro(Data.LoopBody, &isFix)
            curFix := curFix || isFix
        }

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatSubMacro(FilePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    FixTypeMap := Map("1", "当前宏", "2", "按键宏", "3", "字串宏", "4", "轮盘宏", "5", "定时宏", "6", "宏")
    FixCallTypeMap := Map("1", "插入到当前宏", "2", "触发", "3", "暂停", "4", "取消暂停", "5", "终止")
    hasFix := CompatSerial(filePath, "SubMacro", "宏操作")
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
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
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
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
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
        if (Data == "")
            continue

        curFix := false
        if (!ObjHasOwnProp(Data, "WinInfo")) {
            Data.WinInfo := ""
            curFix := true
        }

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatCompare(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix := CompatSerial(filePath, "Compare", "如果")
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
        if (Data == "")
            continue
        curFix := false
        if (Data.HasOwnProp("TrueMacro") && Data.TrueMacro != "") {
            Data.TrueMacro := CompatMacro(Data.TrueMacro, &isFix)
            curFix := curFix || isFix
        }

        if (Data.HasOwnProp("FalseMacro") && Data.FalseMacro != "") {
            Data.FalseMacro := CompatMacro(Data.FalseMacro, &isFix)
            curFix := curFix || isFix
        }

        if (!ObjHasOwnProp(Data, "TrueControlType")) {
            Data.TrueControlType := "无"
            Data.FalseControlType := "无"
            curFix := true
        }

        hasFix := hasFix || curFix
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatComparePro(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix

    hasFix1 := CompatSerial(filePath, "Compare\+", "如果Pro")
    hasFix2 := CompatSerial(filePath, "ComparePro", "如果Pro")
    hasFix := hasFix1 || hasFix2
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
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
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
    return hasFix
}

CompatOperation(filePath) {
    hasFix := false
    if (!FileExist(FilePath))
        return hasFix
    hasFix1 := CompatSerial(filePath, "Operation", "运算")
    hasFix2 := CompatSerial(filePath, "Calc", "运算")
    hasFix := hasFix1 || hasFix2
    DeletePropArr := ["NameArr", "OperationArr", "SymbolGroups", "ValueGroups"]
    for key, val in CfgSection(filePath, SettingSection) {
        Data := TryParseCommandData(val)
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
        if (curFix)
            CfgWrite(JSON.stringify(Data, 0), filePath, SettingSection, key)
    }
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

; 无版本或低于 1.2.2 的配置，先执行历史修正。
CompatTo12_UpgradeDir(dir) {
    hasWork := false
    CfgBatchBegin()
    try {
        hasWork := CompatCMD(dir "\MacroFile.toml") || hasWork
        hasWork := CompatSearch(dir "\SearchFile.toml") || hasWork
        hasWork := CompatSearchPro(dir "\SearchProFile.toml") || hasWork
        hasWork := CompatMMPro(dir "\MMProFile.toml") || hasWork
        hasWork := CompatOutput(dir "\OutputFile.toml") || hasWork
        hasWork := CompatRun(dir "\RunFile.toml") || hasWork
        hasWork := CompatLoop(dir "\LoopFile.toml") || hasWork
        hasWork := CompatSubMacro(dir "\SubMacroFile.toml") || hasWork
        hasWork := CompatVariable(dir "\VariableFile.toml") || hasWork
        hasWork := CompatExVariable(dir "\ExVariableFile.toml") || hasWork
        hasWork := CompatCompare(dir "\CompareFile.toml") || hasWork
        hasWork := CompatComparePro(dir "\CompareProFile.toml") || hasWork
        hasWork := CompatOperation(dir "\OperationFile.toml") || hasWork
        hasWork := CompatBGMouse(dir "\BGMouseFile.toml") || hasWork
        hasWork := CompatBGKey(dir "\BGKeyFile.toml") || hasWork
        hasWork := CompatTiming(dir "\TimingFile.toml") || hasWork
        hasWork := CompatMergeTomlKeys(dir "\TimeFile.toml", dir "\TimeDataFile.toml") || hasWork
        hasWork := CompatTime(dir "\TimeDataFile.toml") || hasWork
        hasWork := CompatCountDown(dir "\CountDownFile.toml") || hasWork
    } finally {
        CfgBatchEnd()
    }
    return hasWork
}
