;按键宏命令
OnTriggerMacroKeyAndInit(tableItem, macro, index) {
    MyMacroCount("Add")
    item := tableItem.Items[index]
    if (!item)
        return
    item.Killed := false
    item.Pause := false
    item.ActionCount := 0
    item.HoldKey := Map()
    item.VariableMap["宏循环次数"] := 1
    item.VariableMap["循环次数"] := 0
    isContinue := MySoftData.ContinueKeyMap.Has(item.TK) && item.LoopCount == 1
    isLoop := item.LoopCount == -1
    loop {
        isFirst := item.ActionCount == 0
        isLast := item.ActionCount == item.LoopCount - 1
        isOver := item.ActionCount >= item.LoopCount
        WaitIfPaused(tableItem, index)

        if (item.Killed)
            break

        if (!isLoop && !isContinue && isOver)
            break

        if (!isFirst && isContinue && isOver) {
            key := MySoftData.ContinueKeyMap[item.TK]
            Sleep(MySoftData.ContinueIntervale)

            if (!GetKeyState(key, "P")) {
                break
            }
        }

        HandTipSound(tableItem, index, 1, isFirst, isLast)
        OnTriggerMacroOnce(tableItem, macro, index)
        HandTipSound(tableItem, index, 2, isFirst, isLast)

        if (item.VariableMap["循环-跳过本轮"]) {
            item.VariableMap["循环-跳过本轮"] := false
        }

        if (item.VariableMap["循环-跳出"]) {
            item.VariableMap["循环-跳出"] := false
            break
        }

        item.ActionCount++
        item.VariableMap["宏循环次数"] += 1
    }
    ; 图形宏多分支时跳过 OnFinishMacro，由 Master 的 FinishGraphMacroItem 统一释放
    skipFinish := item.GraphBranchCount > 0
    if (!skipFinish)
        OnFinishMacro(tableItem, macro, index)
}

OnFinishMacro(tableItem, macro, index) {
    item := tableItem.Items[index]
    if (!item)
        return
    ; 开关模式下被kill终止时，补充播放循环结束提示音（类型3）
    if (item.Killed && item.EndTipSound == 3)
        PlayTipSound(2)

    if (item.TriggerType == 4) { ;开关状态下
        item.ToggleState := false
    }

    ; 结束时兜底松开仍按住的键：仅终止或开关触发类型需要松开；
    ; 按下/松开/双击/长按正常结束时保持按键按住，不在此松开
    needRelease := item.Killed || item.TriggerType == 4
    GraphPoolLog("OnFinishMacro", Format("tab={1} item={2} killed={3} trig={4} hold={5} needRelease={6}"
        , tableItem.ID, item.ID, item.Killed, item.TriggerType
        , item.HoldKey.Count, needRelease))
    if (needRelease)
        ReleaseTableItemHoldKeys(tableItem, index)
    ReleaseAllCaches()

    itemState := item.Killed ? 3 : 0
    MySetTableItemState(tableItem, index, itemState)
}

OnTriggerMacroOnce(tableItem, macro, index) {
    cmdArr := SplitMacro(macro)
    item := tableItem.Items[index]

    for value in cmdArr {
        if (item.Killed)
            break
        result := ExecuteMacroCmdOnce(tableItem, cmdArr[A_Index], index)
        if (result != "") {
            cmdArr.InsertAt(A_Index + 1, result*)
        }
        if (item.VariableMap["分支-跳出"]) {
            item.VariableMap["分支-跳出"] := false
            break
        }
        if (item.VariableMap["循环-跳过本轮"])
            break
        if (item.VariableMap["循环-跳出"])
            break
    }
}

; 执行单条宏指令（线性宏循环与图形节点 Walk 共用）
ExecuteMacroCmdOnce(tableItem, cmdStr, index, graphNode := "") {
    global MySoftData
    static Actions := Map(
        "间隔", OnInterval,
        "按键", OnPressKey,
        "搜索", OnSearchWrapper,
        "搜索Pro", OnSearchWrapper,
        "移动", OnMouseMove,
        "移动Pro", OnMMPro,
        ; §20 改名双键：新名「鼠标移动/鼠标移动Pro/增量移动」；旧名键保留兼容旧配置宏
        "鼠标移动", OnMouseMove,
        "鼠标移动Pro", OnMMPro,
        "增量移动", OnDeltaMove,
        "运行", OnRunFile,
        "如果", OnCompare,
        "如果Pro", OnComparePro,
        "输出", OnOutput,
        "变量", OnVariable,
        "变量提取", OnExVariableWrapper,
        "宏操作", OnSubMacro,
        "运算", OnOperation,
        "后台鼠标", OnBGMouse,
        "后台按键", OnBGKey,
        "RMT指令", OnRMTCMD,
        "循环", OnLoop,
        "文本处理", OnTextOps,
        "数组", OnArray,
        "输入", OnInput,
        "文件读写", OnFileIO,
        "窗口管理", OnWindowManage,
        "按键检测", OnKeyCheck,
        "等待", OnWait,
        "注释", (*) => "",
        "抓图", OnScreenShot,
        "图形开始节点", OnGraphStartNode
    )

    item := tableItem.Items[index]
    if (!item)
        return
    if (item.Killed)
        return
    WaitIfPaused(tableItem, index)
    if (item.Killed)
        return
    if (SubStr(cmdStr, 1, 2) == "🚫")
        return

    frontInfo := GetItemFrontInfo(tableItem, index)
    if (MainSoftData.CheckForeground && frontInfo != "" && !CheckFrontWindowActive(frontInfo)) {
        KillTableItemMacro(tableItem, index)
        return
    }

    ; 阶段5：剥离指令自带错误处理段（影刀模式 |EH:...），出错按配置 stop/ignore/retry
    eh := RMTParseErrHandle(cmdStr)
    cmdStr := eh.cmd

    paramArr := StrSplit(GetCmdStr(cmdStr), "_")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(cmdStr)

    ; 业务日志（C 项阶段3）：每指令执行流水（默认关，设置开启后生效；Worker 执行侧写入）
    RMTLogBusiness("宏:(" item.Remark ")", Format("tab{1} item{2} 指令: {3}", tableItem.ID, item.ID, GetCmdStr(cmdStr)))

    cmdKey := RTrim(paramArr[1], "0123456789")
    try {
        result := Actions[cmdKey](tableItem, cmdStr, index)
    } catch as err {
        ; 错误处理配置：优先指令 Data 配置（间隔<serial> 等配置文件模式），|EH: 后缀兼容保留
        ehCfg := eh.cfg
        if (!IsObject(ehCfg))
            ehCfg := RMTGetDataErrHandle(cmdStr)
        handled := RMTHandleError(err, cmdKey, ehCfg, () => Actions[cmdKey](tableItem, cmdStr, index))
        if (handled[1]) {
            result := handled[2]
        } else {
            KillTableItemMacro(tableItem, index)
            result := ""
        }
    }
    return result
}

; 从指令配置文件 Data 读取错误处理配置（新格式：间隔<serial> → IntervalData.ErrMode 等）
; 无配置或默认 stop 时返回 ""（调用方走默认 stop）
RMTGetDataErrHandle(cmdStr) {
    try {
        paramArr := StrSplit(cmdStr, "_")
        SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
        if (numbersOnly == "" || !MySoftData.DataFileMap.Has(textOnly))
            return ""
        Data := GetMacroCMDData(paramArr[1])
        if (!Data.HasOwnProp("ErrMode") || Data.ErrMode == "stop")
            return ""
        return { mode: Data.ErrMode
            , retryCount: Data.HasOwnProp("ErrRetryCount") ? Data.ErrRetryCount : 3
            , retryInterval: Data.HasOwnProp("ErrRetryInterval") ? Data.ErrRetryInterval : 500 }
    } catch {
        return ""
    }
}

OnGraphStartNode(tableItem, cmdStr, index) {
    OnTriggerGraphMacro(tableItem, cmdStr, index)
}

; 检查前台窗口是否还存在并处于激活状态
CheckFrontWindowActive(frontInfoStr) {
    if (frontInfoStr == "")
        return true

    ; 句柄ID格式：❖hwnd1|hwnd2|...
    if (InStr(frontInfoStr, "❖")) {
        hwndList := StrSplit(StrReplace(frontInfoStr, "❖"), "|")
        for hwnd in hwndList {
            if (WinExist("ahk_id " hwnd) && WinActive("ahk_id " hwnd))
                return true
        }
        return false
    }

    ; 窗口信息格式：标题⎖类名⎖进程名
    infoArr := StrSplit(frontInfoStr, "⎖")
    if (infoArr.Length != 3)
        return true

    title := infoArr[1]
    className := infoArr[2]
    process := infoArr[3]

    ; 构建WinTitle字符串进行检测
    winTitle := ""
    if (title != "")
        winTitle .= title
    if (className != "")
        winTitle .= " ahk_class " className
    if (process != "")
        winTitle .= " ahk_exe " process

    if (winTitle == "")
        return true

    return !!(WinExist(winTitle) && WinActive(winTitle))
}

OnSearchWrapper(tableItem, cmdStr, index) {
    isLoopFound := SearchOnTrigger(tableItem, cmdStr, index)
    item := tableItem.Items[index]
    if (item && item.Killed)
        return
    if (isLoopFound != "" && isLoopFound == false) {
        return [cmdStr]
    }
}

OnExVariableWrapper(tableItem, cmdStr, index) {
    isLoopFound := OnExVariable(tableItem, cmdStr, index)
    if (isLoopFound != "" && isLoopFound == false) {
        return [cmdStr]
    }
}

OnRunFile(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    target := Data.Target
    GetSmartReplaceVarText(tableItem, index, &target)
    options := ["Hide", "", "Min", "Max"]

    switch Data.Mode {
        case 1:
            Run(target, , options[1 + Data.Option])

        case 2:
            exitCode := RunWait(target, , options[1 + Data.Option])
            MySetGlobalVariable([Data.SaveNameArr[1]], [exitCode], false)

        case 3:
            stdinText := Data.StdIn
            GetSmartReplaceVarText(tableItem, index, &stdinText)
            _RunCommandNoWait(target, &Data, stdinText)

        case 4:
            stdout := ""
            stderr := ""
            stdinText := Data.StdIn
            GetSmartReplaceVarText(tableItem, index, &stdinText)
            exitCode := _RunCommand(target, &Data, stdinText, &stdout, &stderr)
            MySetGlobalVariable(Data.SaveNameArr, [exitCode, stdout, stderr], false)
    }
}

_RunCommandNoWait(commandLine, &Data, stdinText) {
    static STARTF_USESHOWWINDOW := 0x00000001
    static STARTF_USESTDHANDLES := 0x00000100
    static CREATE_NO_WINDOW := 0x08000000
    static HANDLE_FLAG_INHERIT := 0x00000001

    commandLine := Trim(commandLine)
    if (commandLine = "")
        throw Error("_RunCommandNoWait: commandLine is empty")
    commandLine := _ResolveAssociatedCommand(commandLine)

    stdinRd := 0
    stdinWr := 0
    hProcess := 0
    hThread := 0

    saSize := (A_PtrSize = 8) ? 24 : 12
    sa := Buffer(saSize, 0)
    NumPut("UInt", saSize, sa, 0)
    NumPut("Int", 1, sa, (A_PtrSize = 8) ? 16 : 8)

    siSize := (A_PtrSize = 8) ? 104 : 68
    si := Buffer(siSize, 0)
    NumPut("UInt", siSize, si, 0)

    piSize := (A_PtrSize = 8) ? 24 : 16
    pi := Buffer(piSize, 0)

    try {
        if !DllCall("Kernel32\CreatePipe", "Ptr*", &stdinRd, "Ptr*", &stdinWr, "Ptr", sa.Ptr, "UInt", 0, "Int")
            throw Error("CreatePipe(stdin) failed. LastError=" A_LastError)

        ; 父程序保留寫入端
        DllCall("Kernel32\SetHandleInformation", "Ptr", stdinWr, "UInt", HANDLE_FLAG_INHERIT, "UInt", 0)

        ; 和 RunCommand 一樣
        siFlags := STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW
        NumPut("UInt", siFlags, si, (A_PtrSize = 8) ? 60 : 44)

        NumPut("UShort", Data.Option, si, (A_PtrSize = 8) ? 64 : 48)

        ; stdin 給子程序
        NumPut("Ptr", stdinRd, si, (A_PtrSize = 8) ? 80 : 56)

        ; 不指定 stdout/stderr
        ; 讓 Windows 繼承父程序設定

        creationFlags := Data.Option ? 0 : CREATE_NO_WINDOW

        if !DllCall("Kernel32\CreateProcessW"
            , "Ptr", 0
            , "Str", commandLine
            , "Ptr", 0
            , "Ptr", 0
            , "Int", 1
            , "UInt", creationFlags
            , "Ptr", 0
            , "Str", A_WorkingDir
            , "Ptr", si.Ptr
            , "Ptr", pi.Ptr
            , "Int")
            throw Error("CreateProcessW failed. LastError=" A_LastError)

        hProcess := NumGet(pi, 0, "Ptr")
        hThread := NumGet(pi, A_PtrSize, "Ptr")

        DllCall("Kernel32\CloseHandle", "Ptr", hThread)
        hThread := 0

        ; 子程序已複製 stdin handle
        DllCall("Kernel32\CloseHandle", "Ptr", stdinRd)
        stdinRd := 0


        if (stdinText != "")
            _WriteTextToPipe(stdinWr, stdinText, Data.Encoding.In)

        ; EOF
        DllCall("Kernel32\CloseHandle", "Ptr", stdinWr)
        stdinWr := 0

    } finally {
        if (stdinRd)
            DllCall("Kernel32\CloseHandle", "Ptr", stdinRd)
        if (stdinWr)
            DllCall("Kernel32\CloseHandle", "Ptr", stdinWr)
        if (hThread)
            DllCall("Kernel32\CloseHandle", "Ptr", hThread)
        if (hProcess)
            DllCall("Kernel32\CloseHandle", "Ptr", hProcess)
    }
}

_RunCommand(commandLine, &Data, stdinText, &stdout, &stderr) {
    static STARTF_USESHOWWINDOW := 0x00000001
    static STARTF_USESTDHANDLES := 0x00000100
    static CREATE_NO_WINDOW := 0x08000000
    static HANDLE_FLAG_INHERIT := 0x00000001
    static WAIT_TIMEOUT := 0x00000102
    commandLine := Trim(commandLine)
    if (commandLine = "")
        throw Error("_RunCommand: commandLine is empty")
    commandLine := _ResolveAssociatedCommand(commandLine)
    stdoutRd := 0, stdoutWr := 0
    stderrRd := 0, stderrWr := 0
    stdinRd := 0, stdinWr := 0
    hProcess := 0, hThread := 0
    exitCode := 0
    outText := ""
    errText := ""
    saSize := (A_PtrSize = 8) ? 24 : 12
    sa := Buffer(saSize, 0)
    NumPut("UInt", saSize, sa, 0)
    NumPut("Int", 1, sa, (A_PtrSize = 8) ? 16 : 8)
    siSize := (A_PtrSize = 8) ? 104 : 68
    si := Buffer(siSize, 0)
    NumPut("UInt", siSize, si, 0)
    piSize := (A_PtrSize = 8) ? 24 : 16
    pi := Buffer(piSize, 0)
    try {
        if !DllCall("Kernel32\CreatePipe", "Ptr*", &stdinRd, "Ptr*", &stdinWr, "Ptr", sa.Ptr, "UInt", 0, "Int")
            throw Error("CreatePipe(stdin) failed. LastError=" A_LastError)
        if !DllCall("Kernel32\CreatePipe", "Ptr*", &stdoutRd, "Ptr*", &stdoutWr, "Ptr", sa.Ptr, "UInt", 0, "Int")
            throw Error("CreatePipe(stdout) failed. LastError=" A_LastError)
        if !DllCall("Kernel32\CreatePipe", "Ptr*", &stderrRd, "Ptr*", &stderrWr, "Ptr", sa.Ptr, "UInt", 0, "Int")
            throw Error("CreatePipe(stderr) failed. LastError=" A_LastError)
        DllCall("Kernel32\SetHandleInformation", "Ptr", stdoutRd, "UInt", HANDLE_FLAG_INHERIT, "UInt", 0)
        DllCall("Kernel32\SetHandleInformation", "Ptr", stderrRd, "UInt", HANDLE_FLAG_INHERIT, "UInt", 0)
        DllCall("Kernel32\SetHandleInformation", "Ptr", stdinWr, "UInt", HANDLE_FLAG_INHERIT, "UInt", 0)
        siFlags := STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW
        NumPut("UInt", siFlags, si, (A_PtrSize = 8) ? 60 : 44)
        NumPut("UShort", Data.Option, si, (A_PtrSize = 8) ? 64 : 48)
        NumPut("Ptr", stdinRd, si, (A_PtrSize = 8) ? 80 : 56)
        NumPut("Ptr", stdoutWr, si, (A_PtrSize = 8) ? 88 : 60)
        NumPut("Ptr", stderrWr, si, (A_PtrSize = 8) ? 96 : 64)
        creationFlags := Data.Option ? 0 : CREATE_NO_WINDOW
        if !DllCall("Kernel32\CreateProcessW", "Ptr", 0, "Str", commandLine, "Ptr", 0, "Ptr", 0, "Int", 1, "UInt", creationFlags, "Ptr", 0, "Str", A_WorkingDir, "Ptr", si.Ptr, "Ptr", pi.Ptr, "Int")
            throw Error("CreateProcessW failed. LastError=" A_LastError)
        hProcess := NumGet(pi, 0, "Ptr")
        hThread := NumGet(pi, A_PtrSize, "Ptr")
        DllCall("Kernel32\CloseHandle", "Ptr", hThread)
        hThread := 0
        DllCall("Kernel32\CloseHandle", "Ptr", stdinRd)
        stdinRd := 0
        DllCall("Kernel32\CloseHandle", "Ptr", stdoutWr)
        stdoutWr := 0
        DllCall("Kernel32\CloseHandle", "Ptr", stderrWr)
        stderrWr := 0
        if (stdinText != "")
            _WriteTextToPipe(stdinWr, stdinText, Data.Encoding.In)
        DllCall("Kernel32\CloseHandle", "Ptr", stdinWr)
        stdinWr := 0
        loop {
            outText .= _DrainPipe(stdoutRd, Data.Encoding.Out)
            errText .= _DrainPipe(stderrRd, Data.Encoding.Err)
            wait := DllCall("Kernel32\WaitForSingleObject", "Ptr", hProcess, "UInt", 50, "UInt")
            if (wait != WAIT_TIMEOUT) {
                outText .= _DrainPipe(stdoutRd, Data.Encoding.Out)
                errText .= _DrainPipe(stderrRd, Data.Encoding.Err)
                break
            }
        }
        if !DllCall("Kernel32\GetExitCodeProcess", "Ptr", hProcess, "UInt*", &exitCode := 0, "Int")
            throw Error("GetExitCodeProcess failed. LastError=" A_LastError)
        stdout := outText
        stderr := errText

    } catch as e {
        throw e

    } finally {
        if (stdinRd)
            DllCall("Kernel32\CloseHandle", "Ptr", stdinRd)
        if (stdinWr)
            DllCall("Kernel32\CloseHandle", "Ptr", stdinWr)
        if (stdoutRd)
            DllCall("Kernel32\CloseHandle", "Ptr", stdoutRd)
        if (stdoutWr)
            DllCall("Kernel32\CloseHandle", "Ptr", stdoutWr)
        if (stderrRd)
            DllCall("Kernel32\CloseHandle", "Ptr", stderrRd)
        if (stderrWr)
            DllCall("Kernel32\CloseHandle", "Ptr", stderrWr)
        if (hThread)
            DllCall("Kernel32\CloseHandle", "Ptr", hThread)
        if (hProcess)
            DllCall("Kernel32\CloseHandle", "Ptr", hProcess)
    }
    return exitCode
}

_WriteTextToPipe(hPipe, text, encoding) {
    if (!hPipe || text = "")
        return
    byteCount := StrPut(text, encoding) - 1
    if (byteCount <= 0)
        return
    buf := Buffer(byteCount + 8, 0)
    StrPut(text, buf, encoding)
    totalWritten := 0
    while (totalWritten < byteCount) {
        written := 0
        ok := DllCall("Kernel32\WriteFile", "Ptr", hPipe, "Ptr", buf.Ptr + totalWritten, "UInt", byteCount - totalWritten, "UInt*", &written, "Ptr", 0, "Int")
        if (!ok || written <= 0)
            break
        totalWritten += written
    }
}

_DrainPipe(hPipe, encoding) {
    if (!hPipe)
        return ""
    out := ""
    buf := Buffer(4096, 0)
    loop {
        avail := 0
        if !DllCall("Kernel32\PeekNamedPipe", "Ptr", hPipe, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &avail, "Ptr", 0, "Int")
            break
        if (avail <= 0)
            break
        toRead := (avail > buf.Size) ? buf.Size : avail
        bytesRead := 0
        if !DllCall("Kernel32\ReadFile", "Ptr", hPipe, "Ptr", buf.Ptr, "UInt", toRead, "UInt*", &bytesRead, "Ptr", 0, "Int")
            break
        if (bytesRead <= 0)
            break
        out .= StrGet(buf.Ptr, bytesRead, encoding)
    }
    return out
}

_ResolveAssociatedCommand(commandLine) {
    s := LTrim(commandLine)
    if (s = "")
        return commandLine
    if !RegExMatch(s, '^(?:"([^"]+)"|(\S+))(.*)$', &m)
        return commandLine
    file := m[1] ? m[1] : m[2]
    tail := Trim(m[3])
    if !FileExist(file)
        return commandLine
    SplitPath(file, , , &ext)
    if (ext = "")
        return commandLine
    assocCmd := _AssocQueryCommand("." ext)
    return assocCmd ? _BuildAssociatedCommand(assocCmd, file, tail) : commandLine
}

_AssocQueryCommand(ext) {
    static ASSOCF_NONE := 0x00000000
    static ASSOCSTR_COMMAND := 0x00000001
    cch := 0
    hr := DllCall("Shlwapi\AssocQueryStringW", "UInt", ASSOCF_NONE, "UInt", ASSOCSTR_COMMAND, "Str", ext, "Str", "open", "Ptr", 0, "UInt*", &cch, "Int")
    if (hr != 0 && hr != 1)
        return ""
    buf := Buffer(cch * 2, 0)
    hr := DllCall("Shlwapi\AssocQueryStringW", "UInt", ASSOCF_NONE, "UInt", ASSOCSTR_COMMAND, "Str", ext, "Str", "open", "Ptr", buf.Ptr, "UInt*", &cch, "Int")
    if (hr != 0)
        return ""
    return StrGet(buf, "UTF-16")
}

_BuildAssociatedCommand(template, filePath, tailArgs := "") {
    cmd := _ExpandEnvironmentStrings(template)
    quotedFile := '"' StrReplace(filePath, '"', '""') '"'
    cmd := StrReplace(cmd, '"%1"', quotedFile)
    cmd := StrReplace(cmd, '"%L"', quotedFile)
    cmd := StrReplace(cmd, '"%l"', quotedFile)
    cmd := StrReplace(cmd, "%1", quotedFile)
    cmd := StrReplace(cmd, "%L", quotedFile)
    cmd := StrReplace(cmd, "%l", quotedFile)
    if (InStr(cmd, "%*"))
        cmd := StrReplace(cmd, "%*", tailArgs)
    else if (Trim(tailArgs) != "")
        cmd := Trim(cmd) " " tailArgs
    else
        cmd := Trim(cmd)
    return cmd
}

_ExpandEnvironmentStrings(text) {
    cch := DllCall("Kernel32\ExpandEnvironmentStringsW", "Str", text, "Ptr", 0, "UInt", 0, "UInt")
    if (cch <= 0)
        return text
    buf := Buffer(cch * 2, 0)
    if !DllCall("Kernel32\ExpandEnvironmentStringsW", "Str", text, "Ptr", buf.Ptr, "UInt", cch, "UInt")
        return text
    return StrGet(buf, "UTF-16")
}

OnCompare(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    result := Data.LogicalType == 1 ? true : false
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index])
            continue

        CompareType := Data.CompareTypeArr[A_Index]
        hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Data.NameArr[A_Index], Data.VariableArr[
            A_Index])
        if (!hasComparison)
            return

        if (Data.LogicalType == 1) {
            result := result && currentComparison
            if (!result)
                break
        } else {
            result := result || currentComparison
            if (result)
                break
        }
    }

    if (Data.SaveToggle) {
        SaveValue := result ? Data.TrueValue : Data.FalseValue
        MySetGlobalVariable([Data.SaveName], [SaveValue], false)
    }

    macro := result ? Data.TrueMacro : Data.FalseMacro
    if (macro != "")
        OnTriggerMacroOnce(tableItem, macro, index)

    ControlType := result ? Data.TrueControlType : Data.FalseControlType
    HandleControlType(tableItem, index, ControlType)
}

OnComparePro(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    loop Data.VariNameArr.Length {
        NameArr := Data.VariNameArr[A_Index]
        CompareTypeArr := Data.CompareTypeArr[A_Index]
        VariableArr := Data.VariableArr[A_Index]
        LogicType := Data.LogicTypeArr[A_Index]
        Macro := Data.MacroArr[A_Index]
        ControlType := Data.ControlTypeArr[A_Index]
        result := LogicType == 1 ? true : false

        for i, Name in NameArr {
            CompareType := CompareTypeArr[i]
            hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Name, VariableArr[i])
            if (!hasComparison)
                return

            if (LogicType == 1) {
                result := result && currentComparison
                if (!result)
                    break
            } else {
                result := result || currentComparison
                if (result)
                    break
            }
        }

        if (result) {
            if (Macro != "")
                OnTriggerMacroOnce(tableItem, Macro, index)
            HandleControlType(tableItem, index, ControlType)
            return
        }
    }
    OnTriggerMacroOnce(tableItem, Data.DefaultMacro, index)
    HandleControlType(tableItem, index, Data.DefaultControlType)
}

OnMMPro(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    LastSumTime := 0
    MoveMode := ObjHasOwnProp(Data, "MouseMoveMode") ? Data.MouseMoveMode : 0
    ; §20 新版已去除「移动次数」，恒 1 次；旧配置数据保留 Count/Interval 字段则沿用
    Count := ObjHasOwnProp(Data, "Count") ? Data.Count : 1
    Data.Count := MoveMode == 2 ? Count : 1
    loop Data.Count {
        WaitIfPaused(tableItem, index)

        item := tableItem.Items[index]
        if (item && item.Killed)
            return

        FloatInterval := GetFloatTime(ObjHasOwnProp(Data, "Interval") ? Data.Interval : 0, MainSoftData.PreIntervalFloat)
        OnMMProOnce(tableItem, index, Data)
        if (A_Index != Data.Count)
            Sleep(FloatInterval)
    }
}

OnMMProOnce(tableItem, index, Data) {
    ; Speed 为界面速度 0~100（越大越快），由 MouseMoveUtil 按按键类型换算
    Speed := Data.Speed
    MoveMode := ObjHasOwnProp(Data, "MouseMoveMode") ? Data.MouseMoveMode : 0
    keyMode := GetMacroKeyMode(tableItem, index)
    IsHumanMouse := ObjHasOwnProp(Data, "IsHumanMouse") ? Data.IsHumanMouse : 0

    hasPosVarX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosVarX)
    hasPosVarY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosVarY)
    if (!hasPosVarX || !hasPosVarY)
        return

    PosX := GetFloatValue(PosX, MainSoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MainSoftData.CoordYFloat)

    ; §20 旧配置兼容：MouseMoveMode==2（游戏视角）已拆为「增量移动」指令，旧数据仍按 mouse_event 相对位移执行
    if (MoveMode == 2)
        return MouseMoveGameViewByKeyMode(keyMode, PosX, PosY, Speed)

    ; §20 坐标基准：RefMode==1（窗口）且绝对移动时，坐标按窗口左上角偏移（窗口信息支持 {绑定窗口}）
    RefMode := ObjHasOwnProp(Data, "RefMode") ? Integer(Data.RefMode) : 0
    if (RefMode == 1 && MoveMode == 0) {
        WinInfo := ObjHasOwnProp(Data, "WinInfo") ? Data.WinInfo : ""
        hwndList := GetHwndList(ResolveBindWindow(tableItem, index, WinInfo))
        if (!IsObject(hwndList) || hwndList.Length == 0)
            return
        WinGetPos(&winX, &winY, , , "ahk_id " hwndList[1])
        PosX := winX + PosX
        PosY := winY + PosY
    }

    ; ActionType: 1 移动 | 2 单击 | 3 双击
    clickCount := (Data.ActionType == 1) ? 0 : (Data.ActionType == 2 ? 1 : 2)
    MouseMoveByStrategy(keyMode, MoveMode, PosX, PosY, Speed, clickCount, IsHumanMouse)
}

; §20 增量移动指令（原移动Pro-游戏视角拆出）：X/Y 相对位移，固定走 mouse_event，与按键类型无关
OnDeltaMove(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (numbersOnly != "" && MySoftData.DataFileMap.Has(GetLangKey(textOnly))) {
        Data := GetMacroCMDData(paramArr[1])
        deltaX := Data.DeltaX
        deltaY := Data.DeltaY
    } else {
        deltaX := paramArr.Length >= 2 ? paramArr[2] : 0
        deltaY := paramArr.Length >= 3 ? paramArr[3] : 0
    }

    hasX := TryGetTabVarValue(&dX, tableItem, index, deltaX)
    hasY := TryGetTabVarValue(&dY, tableItem, index, deltaY)
    if (!hasX || !hasY)
        return
    dX := GetFloatValue(dX, MainSoftData.CoordXFloat)
    dY := GetFloatValue(dY, MainSoftData.CoordYFloat)
    MouseMoveGameViewByKeyMode(GetMacroKeyMode(tableItem, index), dX, dY, 100)
}

OnOutput(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    Content := GetReplaceVarText(tableItem, index, Data.Text)

    if (Data.OutputType == "发送内容") {     ;send
        ; SendText(Content)
        savedMode := A_SendMode
        SendMode("Input")
        SetKeyDelay(10, 10)
        SendText(Content)
        SendMode(savedMode)
    }
    else if (Data.OutputType == "粘贴内容") {    ;粘贴文本
        SetClipboard(Content)
        ClipWait
        Send "{Blind}^v"
    }
    else if (Data.OutputType == "临时提示") {    ;提示
        MyToolTipContent(Content)
    }
    else if (Data.OutputType == "指令窗口") {    ;指令窗口
        MyCMDTipForceAction(Content)
    }
    else if (Data.OutputType == "软件弹窗") {    ;弹窗
        MyMsgBoxContent(Content)
    }
    else if (Data.OutputType == "系统语音") {    ;语音
        spovice := ComObject("sapi.spvoice")
        spovice.Speak(Content)
    }
    else if (Data.OutputType == "复制到剪切板") {    ;剪切板
        SetClipboard(Content)
    }
    else if (Data.OutputType == "字符变量") {    ;字符变量 - 将内容保存到指定变量
        VarName := GetReplaceVarText(tableItem, index, Data.VariableName)
        if (VarName == "")
            return
        Content := GetReplaceVarText(tableItem, index, Data.Text)
        MySetGlobalVariable([VarName], [Content], false)
    }
}

OnLoop(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    if (Data.LoopCount == -1) {
        loop {
            item := tableItem.Items[index]
            item.VariableMap["循环次数"] := A_Index
            if (!GetLoopState(tableItem, cmd, index, Data))
                break

            if (item.Killed)
                break

            WaitIfPaused(tableItem, index)
            OnTriggerMacroOnce(tableItem, Data.LoopBody, index)

            if (item.VariableMap["循环-跳过本轮"]) {
                item.VariableMap["循环-跳过本轮"] := false
            }

            if (item.VariableMap["循环-跳出"]) {
                item.VariableMap["循环-跳出"] := false
                break
            }
        }
    }
    else {
        hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.LoopCount)
        if (!hasValue)
            return

        loop Value {
            item := tableItem.Items[index]
            item.VariableMap["循环次数"] := A_Index
            if (!GetLoopState(tableItem, cmd, index, Data))
                break

            if (item.Killed)
                break

            WaitIfPaused(tableItem, index)
            OnTriggerMacroOnce(tableItem, Data.LoopBody, index)

            if (item.VariableMap["循环-跳过本轮"]) {
                item.VariableMap["循环-跳过本轮"] := false
            }

            if (item.VariableMap["循环-跳出"]) {
                item.VariableMap["循环-跳出"] := false
                break
            }
        }
    }
}

GetLoopState(tableItem, cmd, index, Data) {
    if (Data.CondiType == 1)
        return true

    result := Data.LogicType == 1 ? true : false
    loop 4 {
        if (!Data.ToggleArr[A_Index])
            continue
        CompareType := Data.CompareTypeArr[A_Index]
        hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Data.NameArr[A_Index], Data.VariableArr[
            A_Index])
        if (!hasComparison) {
            result := false
            break
        }

        if (Data.LogicType == 1) {
            result := result && currentComparison
            if (!result)
                break
        } else {
            result := result || currentComparison
            if (result)
                break
        }
    }

    if (Data.CondiType == 2)
        return result

    if (Data.CondiType == 3)
        return !result
}

OnSubMacro(tableItem, cmd, index) {
    global MySoftData
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    macroIndex := Data.MacroType == "当前宏" ? index : Data.Index
    ; 目标表直接取对象（当前宏 → 本表；其它 → 按 Symbol 定位），身份 = 对象/ID，非位置
    macroItem := Data.MacroType == "当前宏" ? tableItem : GetTableBySymbol(Data.MacroType)
    if (!macroItem) {
        GraphPoolLog("宏操作-目标表不存在", Format("type={1} index={2}", Data.MacroType, Data.Index))
        return
    }
    macroTableID := macroItem.ID
    targetItemID := macroItem.Items.Has(macroIndex) ? macroItem.Items[macroIndex].ID : ""

    IsAbnormal := !macroItem.Items.Has(macroIndex) || macroItem.Items[macroIndex].ID != Data.MacroSerial
    if (Data.MacroType != "当前宏" && IsAbnormal) {
        for i, item in macroItem.Items {
            if (Data.MacroSerial == item.ID) {
                macroIndex := i
                targetItemID := item.ID
                break
            }
        }
    }

    if (Data.CallType == "插入到当前宏") {   ;插入
        if (!targetItemID)
            return
        macro := macroItem.GetItem(targetItemID).Macro
        resultMacro := ""
        isHas := TryGetTabVarValue(&Count, tableItem, index, Data.InsertCount, true)
        if (isHas) {
            loop Count {
                resultMacro .= macro ","
            }
        }
        resultMacro := Trim(resultMacro, ",")
        return SplitMacro(resultMacro)
    }
    else if (Data.CallType == "触发") {  ;触发
        MyTriggerSubMacro(macroTableID, targetItemID)
    }
    else if (Data.CallType == "暂停") {  ;暂停
        MySetItemPauseState(macroTableID, targetItemID, 1)
    }
    else if (Data.CallType == "取消暂停") {  ;取消暂停
        MySetItemPauseState(macroTableID, targetItemID, 0)
    }
    else if (Data.CallType == "终止") {  ;终止
        MyStopMacro(macroTableID, targetItemID)
    }
}

OnVariable(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    LocalVariableMap := tableItem.Items[index].VariableMap
    DeleteNameArr := []
    VariableNameArr := []
    ValueArr := []
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index])
            continue
        VariableName := Data.VariableArr[A_Index]
        if (Data.OperaTypeArr[A_Index] == 5) {  ;删除
            DeleteNameArr.Push(VariableName)
            continue
        }

        Value := 0
        if (Data.OperaTypeArr[A_Index] == 1) {   ;数值
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }
        if (Data.OperaTypeArr[A_Index] == 2) {  ;随机
            hasMin := TryGetTabVarValue(&minValue, tableItem, index, Data.MinVariableArr[A_Index])
            hasMax := TryGetTabVarValue(&maxValue, tableItem, index, Data.MaxVariableArr[A_Index])
            if (!hasMin || !hasMax)
                return
            Value := Random(minValue, maxValue)
        }
        if (Data.OperaTypeArr[A_Index] == 3) {  ;字符
            Value := Data.CopyVariableArr[A_Index]
        }

        if (Data.OperaTypeArr[A_Index] == 4) {   ;系统
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }

        VariableNameArr.Push(VariableName)
        ValueArr.Push(Value)
    }

    if (DeleteNameArr.Length != 0)
        MyDelGlobalVariable(DeleteNameArr)

    if (VariableNameArr.Length != 0)
        MySetGlobalVariable(VariableNameArr, ValueArr, Data.IsIgnoreExist)
}

OnExVariable(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    count := Data.SearchCount
    interval := Data.SearchInterval

    ;变量初始化默认值0
    NameArr := []
    ValueArr := []
    loop Data.ToggleArr.Length {
        if (Data.ToggleArr[A_Index]) {
            NameArr.Push(Data.VariableArr[A_Index])
            ValueArr.Push(0)
        }
    }
    MySetGlobalVariable(NameArr, ValueArr, true)

    if (Data.SearchCount == -1) {
        WaitIfPaused(tableItem, index)
        item := tableItem.Items[index]
        if (item.Killed)
            return
        isFound := OnExVariableOnce(tableItem, index, Data)
        if (item.Killed)
            return
        if (!isFound) {
            FloatInterval := GetFloatTime(Data.SearchInterval, MainSoftData.PreIntervalFloat)
            InterruptibleSleep(tableItem, index, FloatInterval)
        }
        return isFound
    }
    else {
        loop Data.SearchCount {
            WaitIfPaused(tableItem, index)

            item := tableItem.Items[index]
            if (item.Killed)
                return

            isFound := OnExVariableOnce(tableItem, index, Data)
            if (isFound)
                return

            if (Data.SearchCount > A_Index) {
                FloatInterval := GetFloatTime(Data.SearchInterval, MainSoftData.PreIntervalFloat)
                InterruptibleSleep(tableItem, index, FloatInterval)
            }
        }
    }
}

OnExVariableOnce(tableItem, index, Data) {
    if (Data.ExtractType == 1) {
        HasX1 := TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
        HasY1 := TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
        HasX2 := TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
        HasY2 := TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
        if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
            return
        TextObjs := GetScreenTextObjArr(X1, Y1, X2, Y2, Data.OCRType)
        TextObjs := TextObjs == "" ? [] : TextObjs
    }
    else if (Data.ExtractType == 2) {
        TextObjs := []
        if (!IsClipboardText())
            return
        obj := Object()
        obj.Text := A_Clipboard
        TextObjs.Push(obj)
    }
    else if (Data.ExtractType == 3) {
        HasX1 := TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
        HasY1 := TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
        HasX2 := TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
        HasY2 := TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY)
        if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
            return
        TextObjs := []
        hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.WinInfo))   ; §22 绑定窗口替换
        loop hwndList.Length {
            CurWinTextObjs := GetWinTextObjArr(hwndList[A_Index], X1, Y1, X2, Y2, Data.OCRType)
            if (CurWinTextObjs != "")
                TextObjs.Push(CurWinTextObjs*)
        }
    }

    isOk := false
    allText := ""
    for index, value in TextObjs {
        allText .= value.text
        allText .= "`n"
    }
    allText := RTrim(allText, "`n")
    ExtractStr := GetReplaceVarText(tableItem, index, Data.ExtractStr)
    for _, value in TextObjs {
        VariableValueArr := ExtractVariable(value.Text, ExtractStr)
        VariableValueArr := ExtractStr == "" && allText != "" ? [allText] : VariableValueArr
        if (VariableValueArr == "")
            continue

        if (GetExVariableActiveLength(Data.ToggleArr) > VariableValueArr.Length)
            continue

        RealNameArr := []
        RealValueArr := []
        loop VariableValueArr.Length {
            if (Data.ToggleArr[A_Index]) {
                RealNameArr.Push(Data.VariableArr[A_Index])
                RealValueArr.Push(VariableValueArr[A_Index])
            }
        }
        MySetGlobalVariable(RealNameArr, RealValueArr, Data.IsIgnoreExist)
        isOk := true
        break
    }

    return isOk
}

OnOperation(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    NewNameArr := []
    NewValueArr := []
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index] || Data.ExpressionArr[A_Index] == "")
            continue

        isOk := GetExpressionResult(Data.ExpressionArr[A_Index], tableItem, index, &Res)
        if (!isOk)
            continue

        MySoftData.VariableMap[Data.UpdateNameArr[A_Index]] := res
        NewNameArr.Push(Data.UpdateNameArr[A_Index])
        NewValueArr.Push(res)
    }
    if (NewNameArr.Length > 0)
        MySetGlobalVariable(NewNameArr, NewValueArr, false)
}

OnBGMouse(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    WM_DOWN_ARR := [0x201, 0x207, 0x204]    ;左键，中键，右键
    WM_UP_ARR := [0x202, 0x208, 0x205]    ;左键，中键，右键
    WM_DCLICK_ARR := [0x203, 0x209, 0x206]    ;左键，中键，右键
    hasPosVarX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosVarX)
    hasPosVarY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosVarY)
    if (!hasPosVarX || !hasPosVarY) {
        return
    }
    PosX := GetFloatValue(PosX, MainSoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MainSoftData.CoordYFloat)
    hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.TargetTitle))   ; §22 绑定窗口替换
    loop hwndList.Length {
        hwnd := hwndList[A_Index]
        ; 点击位置（窗口客户区坐标）
        lParam := (PosY << 16) | (PosX & 0xFFFF)

        if (Data.MouseType == 4) {  ;滚轮
            if (Data.ScrollV != 0) {
                value := 120 * Data.ScrollV
                PostMessage(0x020A, (value << 16), lParam, , "ahk_id " hwnd)
            }
            else if (Data.ScrollH != 0) {
                value := 120 * Data.ScrollH
                PostMessage(0x020E, (value << 16), lParam, , "ahk_id " hwnd)
            }
            return
        }

        if (Data.OperateType == 1) {    ;点击
            PostMessage WM_DOWN_ARR[Data.MouseType], 1, lParam, , "ahk_id " hwnd
            Sleep Data.ClickTime
            PostMessage WM_UP_ARR[Data.MouseType], 0, lParam, , "ahk_id " hwnd
        }
        else if (Data.OperateType == 2) {   ;双击
            PostMessage WM_DCLICK_ARR[Data.MouseType], 1, lParam, , "ahk_id " hwnd
            Sleep Data.ClickTime
            PostMessage WM_UP_ARR[Data.MouseType], 0, lParam, , "ahk_id " hwnd
        }
        else if (Data.OperateType == 3) {   ;按下
            PostMessage WM_DOWN_ARR[Data.MouseType], 1, lParam, , "ahk_id " hwnd
        }
        else if (Data.OperateType == 4) {   ;松开
            PostMessage WM_UP_ARR[Data.MouseType], 0, lParam, , "ahk_id " hwnd
        }
    }
}

OnBGKey(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    loop Data.ClickCount {
        WaitIfPaused(tableItem, index)

        item := tableItem.Items[index]
        if (item && item.Killed)
            break

        FloatHold := GetFloatTime(Data.ClickTime, MainSoftData.HoldFloat)
        FloatInterval := GetFloatTime(Data.ClickInterval, MainSoftData.PreIntervalFloat)
        SendBGKey(Data, tableItem, index)
        if (Data.Type == 3 && A_Index != Data.ClickCount)
            Sleep(FloatInterval)
    }
}

SendBGKey(Data, tableItem, index) {
    hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.FrontStr))   ; §22 绑定窗口替换

    if (Data.Type == 1 || Data.Type == 3) {
        for hwnd in hwndList {
            for key in Data.KeyArr {
                SendBGKeyState(hwnd, key, 1, tableItem, index)
            }
        }

    }

    if (Data.Type == 3) {
        Sleep(Data.ClickTime)
    }

    if (Data.Type == 2 || Data.Type == 3) {
        for hwnd in hwndList {
            loop Data.KeyArr.Length {
                key := Data.KeyArr[Data.KeyArr.Length - A_Index + 1]
                SendBGKeyState(hwnd, key, 0, tableItem, index)
            }
        }
    }
}

SendBGKeyState(hwnd, Key, state, tableItem, index) {
    if (Key == "逗号")
        Key := ","
    VKCode := GetKeyVK(Key)
    VSCode := GetKeySC(Key)
    lParamDown := (VSCode << 16) | 1
    lParamUp := (VSCode << 16) | 0xC0000001

    if (MySoftData.OnlyDownKeyMap.Has(Key)) {
        if (state == 0)
            return
        try {
            PostMessage 0x100, VKCode, lParamDown, , "ahk_id " hwnd
        }

        return
    }

    if (state == 1) {
        try {
            PostMessage 0x100, VKCode, lParamDown, , "ahk_id " hwnd
        }
    }
    else {
        try {
            PostMessage 0x101, VKCode, lParamUp, , "ahk_id " hwnd
        }
    }

    if (state == 1) {
        tableItem.Items[index].HoldKey[Key] := "Normal"
    }
    else {
        tableItem.Items[index].HoldKey.Delete(Key)
    }
}

OnMouseMove(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    ; 阶段5：新格式 移动<serial> 走配置文件；旧格式 移动_X_Y_Speed_MoveMode 兼容
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    textOnly := GetLangKey(textOnly)   ; 英文模式序列码前缀反译（旧名「移动」/新名「鼠标移动」都命中 DataFileMap）
    if (numbersOnly != "" && MySoftData.DataFileMap.Has(textOnly)) {
        Data := GetMacroCMDData(paramArr[1])
        PosX := Integer(Data.PosX)
        PosY := Integer(Data.PosY)
        Speed := Integer(Data.Speed)
        MoveMode := Integer(Data.MoveMode)
    } else {
        PosX := Integer(paramArr[2])
        PosY := Integer(paramArr[3])
        Speed := paramArr.Length >= 4 ? Integer(paramArr[4]) : 90
        MoveMode := paramArr.Length >= 5 ? Integer(paramArr[5]) : 0
    }

    PosX := GetFloatValue(PosX, MainSoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MainSoftData.CoordYFloat)
    keyMode := GetMacroKeyMode(tableItem, index)
    MouseMoveByStrategy(keyMode, MoveMode, PosX, PosY, Speed, 0, false)
}

; RMT 输入控制：键鼠/鼠标/键盘 启用与禁用（cmd 可为中文键或当前语言文本）
ApplyRmtInputControl(cmdStr) {
    key := GetLangKey(cmdStr)
    switch key {
        case "启用键鼠":
            BlockInput false
            try BlockInput "MouseMoveOff"
            RmtBlockKeyboard(false)
            return true
        case "禁用键鼠":
            BlockInput true
            return true
        case "启用鼠标":
            BlockInput "MouseMoveOff"
            return true
        case "禁用鼠标":
            BlockInput "MouseMove"
            return true
        case "启用键盘":
            RmtBlockKeyboard(false)
            return true
        case "禁用键盘":
            RmtBlockKeyboard(true)
            return true
        case "启用鼠标加速":
            SetMouseAccelState(true)
            return true
        case "禁用鼠标加速":
            SetMouseAccelState(false)
            return true
    }
    return false
}

; 鼠标加速（精准指针）控制；每次读取当前参数，只改 acceleration 字段，保留 threshold 不变
SetMouseAccelState(enable) {
    params := Buffer(12)
    ; 读取当前鼠标参数 [threshold1, threshold2, acceleration]
    DllCall("SystemParametersInfo", "UInt", 0x0003, "UInt", 0, "Ptr", params, "UInt", 0)  ; SPI_GETMOUSE
    ; 只改 params[2] (acceleration)，保留 threshold1/2 不变
    NumPut("Int", enable ? 1 : 0, params, 8)
    ; 写回，SPIF_SENDCHANGE 广播变更，不写注册表
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", params, "UInt", 0x02)
}

; 仅屏蔽键盘（InputHook）；与 BlockInput 鼠标模式相互独立
RmtBlockKeyboard(enableBlock) {
    static hook := unset
    if (!IsSet(hook)) {
        hook := InputHook("L0 I")
        hook.KeyOpt("{All}", "S")
    }
    if (enableBlock) {
        if (!hook.InProgress)
            hook.Start()
    } else if (hook.InProgress) {
        hook.Stop()
    }
}

OnRMTCMD(tableItem, cmd, index) {
    ; 新格式: RMT指令<serial> 走配置文件；旧格式 RMT指令_类别_指令 兼容
    paramArr := StrSplit(cmd, "_")
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (numbersOnly != "" && MySoftData.DataFileMap.Has(textOnly)) {
        Data := GetMacroCMDData(paramArr[1])
        cmdStr := Data.CmdStr
        category := Data.HasOwnProp("Category") ? Data.Category : GetLang("全部")
        if (cmdStr == GetLang("显示菜单"))
            cmdStr .= "_" (Data.HasOwnProp("MenuIndex") ? Data.MenuIndex : 1)
        ; §2 禁用模块/取消禁用模块：附加目标表符号 + 模块路径身份（⫶ 分隔，执行端按段取参）
        if ((cmdStr == GetLang("禁用模块") || cmdStr == GetLang("取消禁用模块"))
            && Data.HasOwnProp("TableSymbol") && Data.TableSymbol != "")
            cmdStr .= "⫶" Data.TableSymbol "⫶" Data.FoldID
        cmd := "RMT指令⫶" category "⫶" cmdStr
    } else {
        cmdStr := paramArr[3]
        if (cmdStr == GetLang("显示菜单") && paramArr.Length >= 5)
            cmdStr .= "_" paramArr[4]
        cmd := StrReplace(cmd, "_", "⫶")
    }
    if (ApplyRmtInputControl(cmdStr))
        return
    MyExcuteRMTCMDAction(cmd)
}

OnInterval(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    ; 阶段5：新格式 间隔<serial> 走配置文件；旧格式 间隔_500 兼容解析
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (numbersOnly != "" && MySoftData.DataFileMap.Has(textOnly)) {
        Data := GetMacroCMDData(paramArr[1])
        time1 := Data.Time1
        time2 := Data.Time2
        isRandom := Data.Type == 2
    } else {
        time1 := paramArr[2]
        time2 := paramArr.Length >= 3 ? paramArr[3] : ""
        TimeArr := StrSplit(paramArr[2], "~")
        isRandom := TimeArr.Length > 1
        if (isRandom) {
            time1 := TimeArr[1]
            time2 := TimeArr[2]
        }
    }

    if (!isRandom) {
        hasInterval := TryGetTabVarValue(&interval, tableItem, index, time1)
        if (!hasInterval)
            return
    }
    else {
        hasInterval1 := TryGetTabVarValue(&interval1, tableItem, index, time1)
        hasInterval2 := TryGetTabVarValue(&interval2, tableItem, index, time2)
        if (!hasInterval1 || !hasInterval2)
            return

        interval := Random(interval1, interval2)
    }

    FloatInterval := GetFloatTime(interval, MainSoftData.IntervalFloat)
    InterruptibleSleep(tableItem, index, FloatInterval)
}

OnPressKey(tableItem, cmd, index) {
    global MySoftData
    paramArr := SplitCommand(cmd)
    ; 阶段5：新格式 按键<serial> 走配置文件；旧格式 按键_a_点击_100 兼容
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (numbersOnly != "" && MySoftData.DataFileMap.Has(textOnly)) {
        Data := GetMacroCMDData(paramArr[1])
        keyName := Data.KeyName
        keyTypeVal := Data.KeyType          ; 1按下 2松开 3点击
        holdTime := Data.HoldTime
        count := Data.Count
        intervalTime := Data.IntervalTime
    } else {
        keyName := paramArr[2]
        keyTypeMap := Map("按下", 1, "松开", 2, "点击", 3)
        keyTypeVal := keyTypeMap[paramArr[3]]
        holdTime := paramArr.Length >= 4 ? Integer(paramArr[4]) : 100
        count := paramArr.Length >= 5 ? Integer(paramArr[5]) : 1
        intervalTime := paramArr.Length >= 6 ? Integer(paramArr[6]) : 0
    }

    ; 录制产生的通用键名（AxisLXMin/DpadUp/AxisLT/JoyN 等）→ 友好键名（JoyAxisLXMin/JoyDpadUp/JoyLT/JoyA），
    ; 否则摇杆/方向键/扳机不含 "JoyAxis"/"JoyDpad" 前缀，会落到普通按键发送而无效
    keyName := MySoftData.GetJoyFriendlyKey(keyName)
    isJoyKey := InStr(keyName, "Joy")
    isJoyAxis := InStr(keyName, "JoyAxis")
    isJoyDpad := InStr(keyName, "JoyDpad")
    item := tableItem.Items[index]
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey, 4, SendAHIKey)
    action := actionMap[Integer(item.Mode)]
    action := isJoyKey ? SendJoyBtnKey : action
    action := isJoyAxis ? SendJoyAxisKey : action
    action := isJoyDpad ? SendJoyDpadKey : action

    if (isJoyKey || isJoyAxis || isJoyDpad) {
        actionName := isJoyDpad ? "SendJoyDpadKey" : (isJoyAxis ? "SendJoyAxisKey" : "SendJoyBtnKey")
        JoyDebugLog(Format("OnPressKey cmd={} key={} type={} mode={} action={} pool={} killed={} HasJoyMacro={}"
            , cmd, keyName, keyTypeVal, item.Mode, actionName
            , WorkPoolEnabled(), item.Killed, MySoftData.HasJoyMacro), "press")
    }

    keyType := keyTypeVal
    loop count {
        WaitIfPaused(tableItem, index)

        if (item.Killed)
            break

        FloatHold := GetFloatTime(holdTime, MainSoftData.HoldFloat)
        FloatInterval := GetFloatTime(intervalTime, MainSoftData.PreIntervalFloat)
        SendKeyWrapper(keyName, FloatHold, tableItem, index, keyType, action)
        if (keyType == 3 && A_Index != count && FloatInterval > 0)
            Sleep(FloatInterval)
    }
}

;按键替换
OnReplaceDownKey(tableItem, info, index, *) {
    infos := StrSplit(info, ",")
    mode := Integer(tableItem.Items[index].Mode)
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey, 4, SendAHIKey)
    action := actionMap[mode]
    loop infos.Length {
        assistKey := infos[A_Index]
        assistKey := StrReplace(assistKey, "逗号", ",")
        action(assistKey, 1, tableItem, index)
    }
}

OnReplaceUpKey(tableItem, info, index, *) {
    infos := StrSplit(info, ",")
    mode := Integer(tableItem.Items[index].Mode)
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey, 4, SendAHIKey)
    action := actionMap[mode]
    loop infos.Length {
        assistKey := infos[A_Index]
        assistKey := StrReplace(assistKey, "逗号", ",")
        action(assistKey, 0, tableItem, index)
    }
}

;按钮回调
MenuReload(*) {
    ; 持久化当前 tab 用 TableID（身份）；未切换过则回落 TabCtrl.Value
    savedTab := MainSoftData.CurTableID != "" ? MainSoftData.CurTableID : MainSoftData.TabCtrl.Value
    IniWrite(savedTab, IniFile, IniSection, "TableIndex")
    IniWrite(true, IniFile, IniSection, "IsReload")
    SafeReload()
}

OnToolTextFilterSelectImage(*) {
    global MainSoftData
    path := FileSelect(, , GetLang("选择图片"))
    if (path == "")
        return
    ocr := GetChineseOcr() ; v6 统一多语言模型，不再区分语言
    result := ocr.ocr_from_file(path)
    SetToolTextDisplay(result)
    SetClipboard(result)
}

OnClearToolText(*) {
    SetToolTextDisplay("")
}

GetBootStartRegPaths() {
    ; 同时清理 64/32 位注册表视图，避免取消自启后残留
    return [
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKEY_CURRENT_USER\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    ]
}

GetBootStartValueNames() {
    ; RMT 为当前值名，ButtonAssist 为历史值名
    return ["RMT", "ButtonAssist"]
}

IsBootStart() {
    for regPath in GetBootStartRegPaths() {
        for name in GetBootStartValueNames() {
            try {
                value := RegRead(regPath, name)
                if (value != "")
                    return true
            }
        }
    }
    return false
}

ClearBootStartRegistry() {
    for regPath in GetBootStartRegPaths() {
        for name in GetBootStartValueNames() {
            try RegDelete(regPath, name)
        }
    }
}

; 按 enable 写入/清理开机自启注册表；返回是否与预期一致
ApplyBootStartRegistry(enable) {
    ClearBootStartRegistry()
    if (!enable)
        return !IsBootStart()

    regPath := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
    cmd := '"' A_ScriptFullPath '" -min'
    if (MainSoftData.IsAdminStart)
        cmd .= " -admin"
    try {
        RegWrite(cmd, "REG_SZ", regPath, "RMT")
    } catch {
        return false
    }
    return IsBootStart()
}

; 启动时让注册表与 ini 中的 IsBootStart 对齐（清理取消后仍残留的自启项）
SyncBootStartRegistry() {
    ApplyBootStartRegistry(!!MainSoftData.IsBootStart)
}

OnBootStartChanged(ctrl, *) {
    global MyMainWin
    ; Worker 无 UI：MyMainWin 为 "" 占位（见 WorkGlobalUtil），仅主程序实例化后走真实逻辑
    if (!IsObject(MyMainWin))
        return
    MainSoftData.IsBootStart := MyMainWin.ui.Query("ChkBootStart") == "True"
    ok := ApplyBootStartRegistry(MainSoftData.IsBootStart)
    IniWrite(MainSoftData.IsBootStart ? 1 : 0, IniFile, IniSection, "IsBootStart")
    if (!ok) {
        ; 注册表未能与选项对齐时回滚勾选，避免界面已关、实际仍自启
        MainSoftData.IsBootStart := !MainSoftData.IsBootStart
        try MyMainWin.ui.Update("ChkBootStart", "IsChecked", MainSoftData.IsBootStart ? "True" : "False")
        IniWrite(MainSoftData.IsBootStart ? 1 : 0, IniFile, IniSection, "IsBootStart")
        MsgBox(GetLang("开机自启设置失败，请检查是否被安全软件拦截，或勿通过兼容性强制管理员运行。"), GetLang("提示"), 48)
    }
}

OnAdminStartChanged(ctrl, *) {
    global MyMainWin
    ; Worker 无 UI：MyMainWin 为 "" 占位（见 WorkGlobalUtil），仅主程序实例化后走真实逻辑
    if (!IsObject(MyMainWin))
        return
    MainSoftData.IsAdminStart := MyMainWin.ui.Query("ChkAdminStart") == "True"
    IniWrite(MainSoftData.IsAdminStart ? 1 : 0, IniFile, IniSection, "IsAdminStart")
    if (MainSoftData.IsBootStart)
        ApplyBootStartRegistry(true)
}

OnTextOps(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    switch Data.Type {
        case "文本分割":
            TextOpsSplit(Data, tableItem, index)
        case "文本提取":
            TextOpsEx(Data, tableItem, index)
        case "文本替换":
            TextOpsReplace(Data, tableItem, index)
        case "去除空格":
            TextOpsTrimSpace(Data, tableItem, index)
        case "大小写转换":
            TextOpsUpOrLow(Data, tableItem, index)
        case "文本统计":
            TextOpsStatistics(Data, tableItem, index)
        case "文本拼接":
            TextOpsConcat(Data, tableItem, index)
    }
}

OnArray(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    ;用中文方便拓展，数值类型不好拓展
    switch Data.Type {
        case "创建":
            if (Data.IsIgnoreExist && MySoftData.ArrayMap.Has(Data.Name))
                return
            MySetGlobalArray(Data.Name, Data.InitArr)
        case "克隆":
            SourceArr := GetCmdArray(Data, tableItem, index, true)
            if (SourceArr == "")
                return

            MyCloneGlobalArray(SourceArr, Data.SaveName)
        case "删除":
            if (MySoftData.ArrayMap.Has(Data.Name))
                MyDeleteGlobalArray(Data.Name)
        case "包含":
            ArrayCheckIfContain(Data, tableItem, index)
        case "取值":
            ArrayGetIndexValue(Data, tableItem, index)
        case "赋值":
            ArrayModifyIndexValue(Data, tableItem, index)
        case "插入":
            ArrayInsertIndexValue(Data, tableItem, index)
        case "追加":
            ArrayPushValue(Data, tableItem, index)
        case "移除":
            ArrayRemoveAtIndex(Data, tableItem, index)
        case "移除最后":
            ArrayPopValue(Data, tableItem, index)
        case "反转":
            ArrayReverse(Data, tableItem, index)
        case "长度":
            ArrayGetLength(Data, tableItem, index)
    }
}

OnInput(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    switch Data.Type {
        case "弹窗":
            InputPopUp(Data, tableItem, index)
        case "状态":
            InputStateValue(Data, tableItem, index)
        case "继续":
            InputContinue(Data, tableItem, index)
        case "继续&取消":
            InputContinueAndCencel(Data, tableItem, index)
    }
}

OnFileIO(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    FilePath := GetReplaceVarText(tableItem, index, Data.FilePath)
    isExcel := Data.OperType == "读取Excel" || Data.OperType == "写入Excel"
    filter := isExcel ? "Excel Files (*.xlsx)" : "Text Files (*.txt)"
    if (!ValidateCmdPath(&Data, "FilePath", GetLang("选择文件"), filter, tableItem, index))
        return
    FilePath := Data.FilePath

    switch Data.OperType {
        case "读取Excel":
            ReadExcel(Data, tableItem, index)
        case "写入Excel":
            WriteExcel(Data, tableItem, index)
        case "读取文本文件":
            ReadTextFile(Data, tableItem, index)
        case "写入文本文件":
            WriteTextFile(Data, tableItem, index)
    }
}

; 将模糊的窗口标题条件解析为可见窗口的精确句柄
; 仅当 winTitle 为纯进程名匹配（ahk_exe）时才做筛选，
; 精确句柄(ahk_id/ahk_group)或带标题/类名的匹配直接原样返回
ResolveVisibleWinHandle(winTitle) {
    ; 已是精确句柄或句柄组，用户明确指定了目标，不做干预
    if (InStr(winTitle, "ahk_id ") || InStr(winTitle, "ahk_group "))
        return winTitle

    ; 纯标题匹配（不包含ahk_exe和ahk_class），不需要额外筛选
    if (!InStr(winTitle, "ahk_exe") && !InStr(winTitle, "ahk_class"))
        return winTitle

    ; 包含进程名或类名匹配，需要筛选出可见窗口避免命中隐藏窗口导致黑屏
    try {
        detectedHwnds := WinGetList(winTitle)
        for hwnd in detectedHwnds {
            if (!DllCall("IsWindowVisible", "ptr", hwnd))
                continue
            cls := WinGetClass("ahk_id " hwnd)
            if (cls == "Progman" || cls == "WorkerW")
                continue
            return "ahk_id " hwnd
        }
    }
    return ""
}

OnWindowManage(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    searchValue := GetReplaceVarText(tableItem, index, Data.SearchValue)
    winTitle := GetParamsWinInfoStr(searchValue)
    if (winTitle == "")
        return

    ; 将模糊匹配解析为可见窗口的精确句柄，避免命中隐藏窗口导致黑屏等异常
    winTitle := ResolveVisibleWinHandle(winTitle)
    if (winTitle == "")
        return

    try {
        switch Data.ActionType {
            case "激活窗口":
                WinActivate(winTitle)
            case "最大化窗口":
                WinMaximize(winTitle)
            case "最小化窗口":
                WinMinimize(winTitle)
            case "还原窗口":
                WinRestore(winTitle)
            case "关闭窗口":
                WinClose(winTitle)
            case "移动窗口":
                hasPosX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosX)
                hasPosY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosY)
                if (hasPosX && hasPosY) {
                    WinMove(Integer(PosX), Integer(PosY), , , winTitle)
                }
            case "调整大小":
                hasWidth := TryGetTabVarValue(&Width, tableItem, index, Data.Width)
                hasHeight := TryGetTabVarValue(&Height, tableItem, index, Data.Height)
                if (hasWidth && hasHeight) {
                    WinMove(, , Integer(Width), Integer(Height), winTitle)
                }
            case "置顶窗口":
                WinSetAlwaysOnTop(1, winTitle)
            case "取消置顶":
                WinSetAlwaysOnTop(0, winTitle)
            case "修改标题":
                newTitle := GetReplaceVarText(tableItem, index, Data.NewTitle)
                WinSetTitle(newTitle, winTitle)
            case "修改透明度":
                hasTransparency := TryGetTabVarValue(&Transparency, tableItem, index, Data.Transparency)
                if (hasTransparency) {
                    alphaValue := Round(255 * Integer(Transparency) / 100)
                    WinSetTransparent(alphaValue, winTitle)
                }
            case "开启鼠标穿透":
                WinSetExStyle("+0x20", winTitle)
            case "关闭鼠标穿透":
                WinSetExStyle("-0x20", winTitle)
        }
    }
}

OnKeyCheck(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    keyArr := Data.KeyArr
    if (keyArr.Length == 0)
        return

    checkType := Data.CheckType
    stateType := Data.StateType
    varName := Data.VarName
    trueValue := 1
    falseValue := 0

    stateMode := stateType == 1 ? "P" : ""
    isAllPressed := true
    isAnyPressed := false

    for index, key in keyArr {
        isPressed := GetKeyState(key, stateMode)
        if (isPressed) {
            isAnyPressed := true
            if (checkType == 2)
                break
        } else {
            isAllPressed := false
            if (checkType == 1)
                break
        }
    }

    result := ""
    if (checkType == 1) {
        result := isAllPressed ? trueValue : falseValue
    } else {
        result := isAnyPressed ? trueValue : falseValue
    }

    MySetGlobalVariable([varName], [result], false)
}

OnScreenShot(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    startX := GetReplaceVarText(tableItem, index, Data.StartPosX)
    startY := GetReplaceVarText(tableItem, index, Data.StartPosY)
    endX := GetReplaceVarText(tableItem, index, Data.EndPosX)
    endY := GetReplaceVarText(tableItem, index, Data.EndPosY)

    ShotDebugLog(Format("抓图 cmd={} type={} 原始坐标 startX={} startY={} endX={} endY={}"
        , cmd, Data.ScreenShotType, Data.StartPosX, Data.StartPosY, Data.EndPosX, Data.EndPosY))

    if (!IsNumber(startX) || !IsNumber(startY) || !IsNumber(endX) || !IsNumber(endY)) {
        ShotDebugLog(Format("坐标不是有效数字，已终止：startX={} startY={} endX={} endY={}"
            , startX, startY, endX, endY))
        return
    }

    startX := Number(startX)
    startY := Number(startY)
    endX := Number(endX)
    endY := Number(endY)

    shotWidth := endX - startX
    shotHeight := endY - startY
    if (shotWidth <= 0 || shotHeight <= 0) {
        ShotDebugLog(Format("抓图宽高非法，已终止：w={} h={}", shotWidth, shotHeight))
        return
    }

    baseDir := ProjectRootDir "\Setting\" MySoftData.CurSettingName "\Images\TempShot"
    if (!DirExist(baseDir) && !DirCreate(baseDir)) {
        ; 安装目录（如 Program Files）无写权限时，回退到用户临时目录
        baseDir := A_Temp "\RMT_TempShot\" MySoftData.CurSettingName
        ShotDebugLog(Format("主 TempShot 目录不可用，回退到：{}", baseDir))
        if (!DirExist(baseDir) && !DirCreate(baseDir)) {
            ShotDebugLog(Format("回退 TempShot 目录创建失败：{}", baseDir))
            return
        }
    }

    if (Data.NameType == 1 && Data.FixedName != "") {
        fileName := Data.FixedName ".png"
    } else {
        fileName := Data.SerialStr "-" A_Now ".png"
    }

    filePath := baseDir "\" fileName
    ShotDebugLog(Format("截图将保存到：{}", filePath))

    ocvReason := OpenCvEnsure()
    if (ocvReason != "") {
        ShotDebugLog(Format("抓图失败：OpenCV 不可用（{}）", ocvReason))
        ShowOpenCvInstallPrompt(ocvReason)
        return
    }

    if (Data.ScreenShotType == 2) {
        winInfo := GetReplaceVarText(tableItem, index, Data.WinInfo)
        winInfo := ResolveBindWindow(tableItem, index, winInfo)   ; §22 绑定窗口替换
        if (winInfo == "") {
            ShotDebugLog("窗口抓图：窗口信息为空，已终止")
            return
        }

        hwndList := GetHwndList(winInfo)
        if (!hwndList || hwndList.Length == 0) {
            ShotDebugLog(Format("窗口抓图：未找到目标窗口，winInfo={}", winInfo))
            return
        }

        hwnd := hwndList[1]

        try {
            matPtr := DllCall("RMT_OpenCV.dll\CaptureWinMat", "Int", hwnd, "Int", startX,
                "Int", startY, "Int", shotWidth, "Int", shotHeight, "Cdecl Ptr")
            if (!matPtr) {
                ShotDebugLog(Format("窗口抓图：CaptureWinMat 返回空，hwnd={}", hwnd))
                return
            }

            saveRet := DllCall("RMT_OpenCV.dll\SaveMatToFile", "ptr", matPtr, "AStr", filePath, "cdecl Int")
            DllCall("RMT_OpenCV.dll\ReleaseMat", "ptr", matPtr, "cdecl")
            if (!saveRet) {
                ShotDebugLog(Format("窗口抓图：SaveMatToFile 保存失败，filePath={}", filePath))
                return
            }
        } catch as e {
            ShotDebugLog(Format("窗口抓图：DllCall 异常 Message={} Extra={} What={}", e.Message, e.Extra, e.What))
            return
        }
    } else {
        try {
            matPtr := DllCall("RMT_OpenCV.dll\CaptureScreenMat", "Int", startX,
                "Int", startY, "Int", shotWidth, "Int", shotHeight, "Cdecl Ptr")
            if (!matPtr) {
                ShotDebugLog("屏幕抓图：CaptureScreenMat 返回空")
                return
            }

            saveRet := DllCall("RMT_OpenCV.dll\SaveMatToFile", "ptr", matPtr, "AStr", filePath, "cdecl Int")
            DllCall("RMT_OpenCV.dll\ReleaseMat", "ptr", matPtr, "cdecl")
            if (!saveRet) {
                ShotDebugLog(Format("屏幕抓图：SaveMatToFile 保存失败，filePath={}", filePath))
                return
            }
        } catch as e {
            ShotDebugLog(Format("屏幕抓图：DllCall 异常 Message={} Extra={} What={}", e.Message, e.Extra, e.What))
            return
        }
    }

    ShotDebugLog(Format("抓图成功：{}", filePath))

    if (Data.ResultToggle) {
        MySetGlobalVariable([Data.ResultSaveName], [filePath], false)
    }
}
