IsClipboardText() {
    ; 检查是否存在文本格式
    if DllCall("IsClipboardFormatAvailable", "UInt", 1)  ; CF_TEXT = 1
        return true
    if DllCall("IsClipboardFormatAvailable", "UInt", 13) ; CF_UNICODETEXT = 13
        return true
    return false
}

;没必要删除
ClearUselessSetting(deleteMacro) {
    if (deleteMacro == "")
        return
    RegExMatch(deleteMacro, "(Compare\d+)", &match)
    match := match != "" ? match : []
    for id, value in match {
        if (value == "")
            continue
        CfgDelete(CompareFile, SettingSection, value)
    }

    RegExMatch(deleteMacro, "(Coord\d+)", &match)
    match := match != "" ? match : []
    for id, value in match {
        if (value == "")
            continue
        CfgDelete(MMPROFile, SettingSection, value)
    }
}

; 避免写入提示报错
SetClipboard(Content) {
    loop 5 {  ; 最多重试5次
        try {
            A_Clipboard := Content
            return true
        } catch as err {
            Sleep(100)  ; 等待50毫秒
            continue
        }
    }
    return false  ; 5次都失败
}

ValidateCmdPath(&Data, pathFieldName, selectTitle, filter, tableItem := "", index := 1, showSelect := true) {
    if (!ObjHasOwnProp(Data, pathFieldName))
        return true

    rawPath := Data.%pathFieldName%
    hasVariable := InStr(rawPath, "{") && InStr(rawPath, "}")

    if (!hasVariable) {
        if (rawPath == "" || FileExist(rawPath))
            return true

        if (!showSelect)
            return false

        tipStr := Format(GetLang("路径 '{}' 不存在，请重新选择"), rawPath)
        result := CustomMsgBox(tipStr, GetLang("路径缺失"), GetLang("选择文件|跳过本条指令"))

        if (result == 2)
            return false

        newPath := FileSelect(1, , GetLang(selectTitle), filter)
        if (newPath == "")
            return false

        Data.%pathFieldName% := newPath
        SaveMacroCMDData(Data)
        return true
    }

    actualPath := GetReplaceVarText(tableItem, index, rawPath)

    if (actualPath != "" && FileExist(actualPath))
        return true

    if (!showSelect)
        return false

    tipStr := Format("{}`n`n{}: {}`n{}: {}",
        GetLang("变量路径解析后文件不存在"),
        GetLang("原始配置"), rawPath,
        GetLang("解析为"), actualPath == "" ? GetLang("(空值)") : actualPath)

    result := CustomMsgBox(tipStr, GetLang("变量路径错误"), GetLang("覆盖变量|跳过本条指令"))

    if (result == 2)
        return false

    newPath := FileSelect(1, , GetLang(selectTitle), filter)
    if (newPath == "")
        return false

    Data.%pathFieldName% := newPath
    SaveMacroCMDData(Data)
    return true
}

; 初始化完成后使用配置根路径。Worker 启动早期可从 Thread 的上级目录定位资源。
GetProjectRoot() {
    global ProjectRootDir
    if IsSet(ProjectRootDir) && ProjectRootDir != ""
        return ProjectRootDir
    root := A_ScriptDir
    if !DirExist(root '\Plugins') {
        root .= '\..'
        loop files, root {
            root := A_LoopFileFullPath
            break
        }
    }
    return root
}

