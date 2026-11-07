;按键宏命令
OnTriggerMacroKeyAndInit(tableItem, macro, index) {
    item := GetItemByIndex(tableItem, index)
    if (!item)
        return
    item.Killed := false
    item.Pause := false
    item.ActionCount := 0
    item.HoldKey := Map()
    item.VariableMap["宏循环次数"] := 1
    item.VariableMap["循环次数"] := 0
    ; 执行前钩子：一次触发只跑一次（不是每轮循环）。只在发起者执行——
    ; 图形宏的分支 Worker 走 WalkGraphNode，不经本函数，天然不会重复。
    RunMacroHook(tableItem, item, "pre")
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
    ; 执行后钩子：只在本进程独占该条目时执行。多分支场景下本 Worker 只是分支之一，
    ; 收尾由主进程 FinishGraphMacroItem 统一补派后置钩子任务，此处跳过以免跑多份。
    if (!skipFinish)
        RunMacroHook(tableItem, item, "post")
    if (!skipFinish)
        OnFinishMacro(tableItem, macro, index)
}

OnFinishMacro(tableItem, macro, index) {
    item := GetItemByIndex(tableItem, index)
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

; ============================================================
; 执行前 / 执行后钩子
;
; 钩子宏串跑在独立的 scratch 表上，不复用主条目的 VariableMap ——
; 否则 分支-跳出 / 循环-跳出 / 宏循环次数 会被钩子改写后串进主宏执行流。
; scratch 表的 ID 不在真实表集合里，Worker 上报 ItemState 时主进程 GetTableByID
; 落空即安全返回，不会污染 UI 状态。
; ============================================================

; 取一个空闲的钩子 scratch 表。用池化的原因：钩子里的「宏操作」可能触发另一个
; 带钩子的宏，重入时必须有独立实例，否则两者会共写同一份 VariableMap。
GetHookTableItem() {
    static pool := []
    for t in pool {
        if (!t.HookBusy) {
            t.HookBusy := true
            return t
        }
    }
    t := TableItem()
    t.ID := "__RmtHook" (pool.Length + 1)
    t.HookBusy := true
    hookItem := MacroItem()
    hookItem.ID := "__HookItem"
    t.Items.Push(hookItem)
    t.RebuildIndex()
    InitSingleTableState(t)
    pool.Push(t)
    return t
}

; phase: "pre" = 执行前钩子，其余按 "post" = 执行后钩子
; force: true = 即使主条目已被终止也继续跑完（主进程补派的清理钩子用这个模式，
;        强停时 item.Killed 已经是 true，不强制的话清理会一行都不执行）
RunMacroHook(tableItem, item, phase, force := false) {
    if (!IsObject(item))
        return false
    field := (phase == "pre") ? "PreMacro" : "PostMacro"
    if (!item.HasProp(field))
        return false
    macroStr := item.%field%
    if (Trim(macroStr) == "")
        return false

    hookTable := GetHookTableItem()
    hookItem := hookTable.Items[1]
    who := ProcessTag()
    try {
        hookItem.Killed := false
        hookItem.Pause := false
        hookItem.ActionCount := 0
        hookItem.HoldKey := Map()
        hookItem.VariableMap["宏循环次数"] := 1
        hookItem.VariableMap["循环次数"] := 0
        hookItem.VariableMap["循环-跳过本轮"] := false
        hookItem.VariableMap["循环-跳出"] := false
        hookItem.VariableMap["分支-跳出"] := false

        GraphPoolLog("钩子开始", Format("执行者={1} tab={2} item={3} phase={4}"
            , who, tableItem.ID, item.ID, phase))

        cmdArr := SplitMacro(macroStr)
        for value in cmdArr {
            ; 钩子没有独立停止信号，跟随主条目：主条目被终止时立刻收手
            if (!force && item.Killed) {
                hookItem.Killed := true
                break
            }
            result := ExecuteMacroCmdOnce(hookTable, cmdArr[A_Index], 1)
            if (result != "")
                cmdArr.InsertAt(A_Index + 1, result*)
            if (hookItem.VariableMap["分支-跳出"] || hookItem.VariableMap["循环-跳出"])
                break
        }

        GraphPoolLog("钩子结束", Format("执行者={1} tab={2} item={3} phase={4} killed={5}"
            , who, tableItem.ID, item.ID, phase, item.Killed ? 1 : 0))
    } catch as e {
        ; 钩子异常不能带崩主宏：只记录并上报
        GraphPoolLog("钩子异常", Format("tab={1} item={2} phase={3} err={4} line={5}"
            , tableItem.ID, item.ID, phase, e.Message, e.Line))
        try RMTErrorShow("钩子执行异常(" phase "): " e.Message, RMT_LV_ERROR, who)
    } finally {
        hookTable.HookBusy := false
    }
    return true
}

; ============================================================
; 调试步入 / 断点 共享纯函数（零 XAML 依赖；主进程与 Worker 通用）
; 轮 1 仅启用 TryInterceptBranch（步入拦截）+ BpSig/BpStrHas（断点身份/包含判定）；
; 不含任何阻塞式断点闸门（真实运行断点暂停属轮 2）。
; ============================================================

; 调试分支拦截：命中返回 true（仅记录命中分支、不执行分支体），由调试器接管步入。
; 未激活（正常触发 / Worker / F5）→ 直接 false，对既有执行语义逐字节等价。
; 注意：本函数只碰普通对象与全局变量，绝不引用任何 XAML 类名（Worker 编译安全）。
TryInterceptBranch(kind, branchField, controlType, hitIndex := -1) {
    global MySoftData
    if (!IsSet(MySoftData) || !IsObject(MySoftData) || !MySoftData.HasProp("DebugHook"))
        return false
    hook := MySoftData.DebugHook
    if (!IsObject(hook) || !hook.active)
        return false
    hook.recorded := true
    hook.kind := kind
    hook.branchField := branchField
    hook.controlType := controlType
    hook.hitIndex := hitIndex
    return true
}

; 断点签名：命令的稳定标识（跨语言模式）。优先序列号（GetLangKey 归一为中文键），
; 无序列号的旧格式指令退回去标记后的整串。共享纯函数，主/Worker 通用。
; 已知局限：无序列号的旧格式指令（如「间隔_500」）重复时签名退化为整串 →
; 同名重复指令共享断点、落在首条（编辑器创建的现代宏不受影响）。
; 回退分支已剥离逗号：断点串以 ",sig1,sig2," 存放并用 ",sig," 包夹 InStr 匹配，
; 若旧格式文本含逗号会产生假阳命中；写/读两侧同走本函数，归一即一致。
BpSig(cmdText) {
    txt := CmdStripCurPos(GetCmdStr(cmdText))
    paramArr := StrSplit(txt, "_")
    if (paramArr.Length == 0)
        return ""
    textOnly := ""
    numbersOnly := ""
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (numbersOnly == "")
        return StrReplace(txt, ",", "")             ; 旧格式：纯文本整串（剥离逗号防 ,sig, 假阳）
    return GetLangKey(textOnly) . numbersOnly        ; 现代格式：序列号（跨语言稳定）
}

; 断点集合包含判定：断点串规范化为 ",sig1,sig2,"，用 ",sig," 包夹 InStr 做无歧义匹配。
BpStrHas(bpStr, sig) {
    if (bpStr == "" || sig == "")
        return false
    return InStr(bpStr, "," sig ",") ? true : false
}

; 执行单条宏指令（线性宏循环与图形节点 Walk 共用）
ExecuteMacroCmdOnce(tableItem, cmdStr, index, graphNode := "") {
    global MySoftData
    static Actions := Map(
        "间隔", OnInterval,
        "按键", OnPressKey,
        "手柄", OnPressJoy,
        "搜索", SearchOnTrigger,
        "搜索Pro", SearchOnTrigger,
        "搜索All", SearchOnTrigger,
        "搜索Combo", SearchOnTrigger,
        "组合搜索", SearchOnTrigger,
        "搜索Multi", SearchOnTrigger,
        "移动", OnMouseMove,
        "移动Pro", OnMMPro,
        ; §20 改名双键：新名「鼠标移动/鼠标移动Pro/增量移动」；旧名键保留兼容旧配置宏
        "鼠标移动", OnMouseMove,
        "鼠标移动Pro", OnMMPro,
        "增量移动", OnDeltaMove,
        "运行", OnRunFile,
        "运行Pro", OnRunFile,
        "如果", OnCompare,
        "如果Pro", OnComparePro,
        "输出", OnOutput,
        "变量", OnVariable,
        "变量提取", OnExVariable,
        "宏操作", OnSubMacro,
        "运算", OnOperation,
        "后台鼠标", OnBGMouse,
        "后台按键", OnBGKey,
        "RMT指令", OnRMTCMD,
        "循环", OnLoop,
        "流程跳转", OnFlowJump,
        "文本处理", OnTextOps,
        "数组", OnArray,
        "输入", OnInput,
        "等待确定", OnWaitConfirm,
        "网络请求", OnHttpRequest,
        "文件读写", OnFileIO,
        "Excel", OnFileIO,
        "窗口信息", OnWindowManage, "调整窗口", OnWindowManage, "窗口管理", OnWindowManage,
        "按键检测", OnKeyCheck,
        "手柄检测", OnJoyCheck,
        "等待", OnWait,
        "时间", OnTimeData,
        "倒计时", OnCountDown,
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

    if (MainSoftData.CheckForeground && (frontInfo := GetItemFrontInfo(tableItem, index)) != "" && !CheckFrontWindowActive(frontInfo)) {
        KillTableItemMacro(tableItem, index)
        return
    }

    ; 兼容剥离历史 |EH: 后缀；出错一律停止
    cmdStr := RMTParseErrHandle(cmdStr).cmd

    ; 避免重复调用 GetCmdStr，并用 InStr 提取首段 Key 替代全量 StrSplit
    ; 解 G2：清洗串只剥离 🚫/▶/⭐（参数段完整保留），交给处理器一律用 cleanCmdStr，
    ; 避免调试起点 ▶ 进入处理器导致序列号解析失败而误杀宏
    cleanCmdStr := GetCmdStr(cmdStr)
    firstUnderscore := InStr(cleanCmdStr, "_")
    firstPart := firstUnderscore ? SubStr(cleanCmdStr, 1, firstUnderscore - 1) : cleanCmdStr
    cmdKey := RTrim(firstPart, "0123456789")
    mappedKey := GetLangKey(cmdKey)
    if (Actions.Has(mappedKey))
        cmdKey := mappedKey

    if (MySoftData.CMDTip)
        MyCMDReportAciton(cleanCmdStr)

    ok := true
    try {
        result := Actions[cmdKey](tableItem, cleanCmdStr, index)
    } catch as err {
        ok := false
        errMsg := IsObject(err) && err.HasProp("Message") ? err.Message : String(err)
        RMTErrorShow(Format("[{1}] {2}", cmdKey, errMsg), RMT_LV_ERROR, "宏")
        KillTableItemMacro(tableItem, index)
        result := ""
    }
    ; 业务日志（C 项阶段3）：每指令执行流水（默认关，设置开启后生效；Worker 执行侧写入）
    ; 执行后记录，成功/失败并入同一条，不额外增加日志条目（复用 cleanCmdStr）
    RMTLogBusiness("宏:(" item.Remark ")", Format("tab{1} item{2} {3}指令: {4}"
        , tableItem.ID, item.ID, ok ? "" : "失败 ", cleanCmdStr))
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

    if (IsMouseWindowBinding(frontInfoStr)) {
        MouseGetPos , , &hwnd
        return hwnd != 0 && WinActive("ahk_id " hwnd)
    }

    ; 句柄ID格式：❖hwnd1|hwnd2|...
    if (InStr(frontInfoStr, "❖")) {
        hwndList := StrSplit(StrReplace(frontInfoStr, "❖"), "|")
        for hwnd in hwndList {
            if (WinActive("ahk_id " hwnd))
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

    return !!WinActive(winTitle)
}

OnRunFile(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    target := Data.Target
    GetSmartReplaceVarText(tableItem, index, &target)
    runOpt := Map("后台", "Hide", "默认", "", "最小化", "Min", "最大化", "Max")
    optName := CmdEnumRunOption(Data.Option)
    optFlag := runOpt.Has(optName) ? runOpt[optName] : ""
    switch CmdEnumZh(Data.Mode, CmdEnumRunModeNames()) {
        case "不等待":
            Run(target, , optFlag)

        case "等待+返回值":
            exitCode := RunWait(target, , optFlag)
            MySetGlobalVariable([Data.SaveNameArr[1]], [exitCode], false)

        case "不等待+输入":
            stdinText := Data.StdIn
            GetSmartReplaceVarText(tableItem, index, &stdinText)
            _RunCommandNoWait(target, &Data, stdinText)

        case "等待+输入输出":
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

; 无序列号、无配置文件：动作直接保存在命令字符串里。
FlowJumpActions() {
    return ["循环-跳过本轮", "循环-跳出", "分支-跳出"]
}

FlowJumpAction(cmd) {
    parts := StrSplit(cmd, "_")
    if (parts.Length != 2 || GetLangKey(parts[1]) != "流程跳转")
        throw Error("Invalid flow jump command: " cmd)
    action := GetLangKey(parts[2])
    for valid in FlowJumpActions() {
        if (action == valid)
            return action
    }
    throw Error("Invalid flow jump action: " parts[2])
}

OnFlowJump(tableItem, cmd, index) {
    HandleControlType(tableItem, index, FlowJumpAction(cmd))
}

OnCompare(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    result := CmdEnumLogic(Data.LogicalType) == "且" ? true : false
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index])
            continue

        CompareType := Data.CompareTypeArr[A_Index]
        hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Data.NameArr[A_Index], Data.VariableArr[
            A_Index])
        if (!hasComparison)
            return

        if (CmdEnumLogic(Data.LogicalType) == "且") {
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

    ; 调试步入拦截：命中则仅判定、不执行分支体，控制类型延后到调试帧结算
    if (TryInterceptBranch("If", result ? "TrueMacro" : "FalseMacro", result ? Data.TrueControlType : Data.FalseControlType))
        return

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
        result := CmdEnumLogic(LogicType) == "且" ? true : false

        for i, Name in NameArr {
            CompareType := CompareTypeArr[i]
            hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Name, VariableArr[i])
            if (!hasComparison)
                return

            if (CmdEnumLogic(LogicType) == "且") {
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
            ; 调试步入拦截：命中分支，仅判定不执行体
            if (TryInterceptBranch("IfPro", "MacroArr", ControlType, A_Index))
                return
            if (Macro != "")
                OnTriggerMacroOnce(tableItem, Macro, index)
            HandleControlType(tableItem, index, ControlType)
            return
        }
    }
    ; 调试步入拦截：默认分支（以上都不是），仅判定不执行体
    if (TryInterceptBranch("IfPro", "DefaultMacro", Data.DefaultControlType, -1))
        return
    OnTriggerMacroOnce(tableItem, Data.DefaultMacro, index)
    HandleControlType(tableItem, index, Data.DefaultControlType)
}

OnMMPro(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    LastSumTime := 0
    MoveMode := CmdEnumMoveMode(ObjHasOwnProp(Data, "MouseMoveMode") ? Data.MouseMoveMode : "绝对移动")
    ; §20 新版已去除「移动次数」，恒 1 次；旧配置数据保留 Count/Interval 字段则沿用
    Count := ObjHasOwnProp(Data, "Count") ? Data.Count : 1
    Data.Count := MoveMode == "游戏视角" ? Count : 1
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
    MoveMode := CmdEnumMoveMode(ObjHasOwnProp(Data, "MouseMoveMode") ? Data.MouseMoveMode : "绝对移动")
    keyMode := GetMacroKeyMode(tableItem, index)
    IsHumanMouse := ObjHasOwnProp(Data, "IsHumanMouse") ? Data.IsHumanMouse : 0

    hasPosVarX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosVarX)
    hasPosVarY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosVarY)
    if (!hasPosVarX || !hasPosVarY)
        return

    PosX := GetFloatValue(PosX, MainSoftData.CoordXFloat)
    PosY := GetFloatValue(PosY, MainSoftData.CoordYFloat)

    ; 旧配置「游戏视角」已拆为「增量移动」指令，读入后仍按 mouse_event 相对位移执行
    if (MoveMode == "游戏视角")
        return MouseMoveGameViewByKeyMode(keyMode, PosX, PosY, Speed)

    action := CmdEnumMMAction(Data.ActionType)
    isDrag := action == "A到B拖拽" || action == "拖拽"
    isABDrag := action == "A到B拖拽"
    EndX := 0, EndY := 0
    if (isABDrag && MoveMode == "绝对移动") {
        if (!TryGetTabVarValue(&EndX, tableItem, index, Data.HasOwnProp("EndPosVarX") ? Data.EndPosVarX : 200)
            || !TryGetTabVarValue(&EndY, tableItem, index, Data.HasOwnProp("EndPosVarY") ? Data.EndPosVarY : 200))
            return
        EndX := GetFloatValue(EndX, MainSoftData.CoordXFloat)
        EndY := GetFloatValue(EndY, MainSoftData.CoordYFloat)
    }

    ; 坐标基准为窗口且绝对移动时，坐标按窗口左上角偏移（窗口信息支持 {绑定窗口}）
    RefMode := CmdEnumRef(ObjHasOwnProp(Data, "RefMode") ? Data.RefMode : "屏幕")
    if (RefMode == "窗口" && MoveMode == "绝对移动") {
        WinInfo := ObjHasOwnProp(Data, "WinInfo") ? Data.WinInfo : ""
        hwndList := GetHwndList(ResolveBindWindow(tableItem, index, WinInfo))
        if (!IsObject(hwndList) || hwndList.Length == 0)
            return
        WinGetPos(&winX, &winY, , , "ahk_id " hwndList[1])
        PosX := winX + PosX
        PosY := winY + PosY
        if (isDrag) {
            EndX += winX
            EndY += winY
        }
    }

    if (isDrag) {
        if (action == "拖拽" && MoveMode == "绝对移动") {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&startX, &startY)
            return MouseDragByStrategy(keyMode, MoveMode, startX, startY, PosX, PosY, Speed, IsHumanMouse)
        }
        return MouseDragByStrategy(keyMode, MoveMode, PosX, PosY, EndX, EndY, Speed, IsHumanMouse)
    }

    clickCount := (action == "移动") ? 0 : (action == "移动后单击" ? 1 : 2)
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
        count := ObjHasOwnProp(Data, "Count") ? Data.Count : 1
        interval := ObjHasOwnProp(Data, "Interval") ? Data.Interval : 0
    } else {
        deltaX := paramArr.Length >= 2 ? paramArr[2] : 0
        deltaY := paramArr.Length >= 3 ? paramArr[3] : 0
        count := paramArr.Length >= 4 ? paramArr[4] : 1
        interval := paramArr.Length >= 5 ? paramArr[5] : 0
    }

    hasCount := TryGetTabVarValue(&cnt, tableItem, index, count)
    if (!hasCount)
        return
    if (!IsNumber(cnt) || Integer(cnt) <= 0)
        cnt := 1
    else
        cnt := Integer(cnt)

    keyMode := GetMacroKeyMode(tableItem, index)
    loop cnt {
        WaitIfPaused(tableItem, index)
        item := tableItem.Items[index]
        if (item && item.Killed)
            return

        hasX := TryGetTabVarValue(&dX, tableItem, index, deltaX)
        hasY := TryGetTabVarValue(&dY, tableItem, index, deltaY)
        if (!hasX || !hasY)
            return
        dX := GetFloatValue(dX, MainSoftData.CoordXFloat)
        dY := GetFloatValue(dY, MainSoftData.CoordYFloat)
        ; DeltaX/DeltaY 是本次总偏移，按次数拆成等量步骤执行。
        MouseMoveGameViewByKeyMode(keyMode, dX / cnt, dY / cnt, 100)

        if (A_Index != cnt) {
            hasInterval := TryGetTabVarValue(&iv, tableItem, index, interval)
            if (!hasInterval)
                return
            Sleep(GetFloatTime(iv, MainSoftData.PreIntervalFloat))
        }
    }
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
        MyOutputTipContent(Content)
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
            ; 调试步入拦截：无限循环体，仅判定不执行体
            if (TryInterceptBranch("Loop", "LoopBody", "", A_Index))
                return
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
            ; 调试步入拦截：计数循环体，仅判定不执行体
            if (TryInterceptBranch("Loop", "LoopBody", "", A_Index))
                return
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
    if (CmdEnumZh(Data.CondiType, CmdEnumCondiNames()) == "无")
        return true

    result := CmdEnumLogic(Data.LogicType) == "且" ? true : false
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index])
            continue
        CompareType := Data.CompareTypeArr[A_Index]
        hasComparison := DoCompare(&currentComparison, tableItem, index, CompareType, Data.NameArr[A_Index], Data.VariableArr[
            A_Index])
        ; 取值失败不是比较结果为假；退出条件不能将失败取反成继续循环。
        if (!hasComparison)
            return false

        if (CmdEnumLogic(Data.LogicType) == "且") {
            result := result && currentComparison
            if (!result)
                break
        } else {
            result := result || currentComparison
            if (result)
                break
        }
    }

    if (CmdEnumZh(Data.CondiType, CmdEnumCondiNames()) == "继续条件")
        return result

    if (CmdEnumZh(Data.CondiType, CmdEnumCondiNames()) == "退出条件")
        return !result
}

OnSubMacro(tableItem, cmd, index) {
    global MySoftData
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    macroIndex := Data.MacroType == "当前宏" ? index : Data.Index
    ; 目标表直接取对象（当前宏 → 本表；其它 → 按 Symbol 定位），身份 = 对象/ID，非位置
    macroItem := Data.MacroType == "当前宏" ? tableItem : GetTableBySymbol(CompatMacroTypeSymbol(Data.MacroType))
    if (!macroItem) {
        GraphPoolLog("宏操作-目标表不存在", Format("type={1} index={2}", Data.MacroType, Data.Index))
        return
    }
    macroTableID := macroItem.ID
    targetItemID := macroItem.Items.Has(macroIndex) ? macroItem.Items[macroIndex].ID : ""

    IsAbnormal := !macroItem.Items.Has(macroIndex) || macroItem.Items[macroIndex].ID != Data.MacroSerial
    if (Data.MacroType != "当前宏" && IsAbnormal) {
        targetItemID := ""
        for i, item in macroItem.Items {
            if (Data.MacroSerial == item.ID) {
                macroIndex := i
                targetItemID := item.ID
                break
            }
        }
    }

    if (!targetItemID)
        return

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
        MyStopMacro(macroTableID, targetItemID, true)
    }
}

OnVariable(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (numbersOnly == "" && paramArr.Length >= 3) {
        varName := paramArr[2]
        p1 := InStr(cmd, "_")
        p2 := (p1 > 0) ? InStr(cmd, "_", false, p1 + 1) : 0
        src := (p2 > 0) ? SubStr(cmd, p2 + 1) : ""
        Value := ""
        if (varName != "" && TryGetTabVarValue(&Value, tableItem, index, src, false))
            MySetGlobalVariable([varName], [Value], false)
        return
    }
    Data := GetMacroCMDData(paramArr[1])
    LocalVariableMap := tableItem.Items[index].VariableMap
    DeleteNameArr := []
    VariableNameArr := []
    ValueArr := []
    loop Data.ToggleArr.Length {
        if (!Data.ToggleArr[A_Index])
            continue
        VariableName := Data.VariableArr[A_Index]
        opera := CmdEnumOpera(Data.OperaTypeArr[A_Index])
        if (opera == "删除") {
            DeleteNameArr.Push(VariableName)
            continue
        }

        Value := 0
        if (opera == "数值") {
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }
        if (opera == "随机数值") {
            hasMin := TryGetTabVarValue(&minValue, tableItem, index, Data.MinVariableArr[A_Index])
            hasMax := TryGetTabVarValue(&maxValue, tableItem, index, Data.MaxVariableArr[A_Index])
            if (!hasMin || !hasMax)
                return
            Value := Random(minValue, maxValue)
        }
        if (opera == "字符") {
            Value := Data.CopyVariableArr[A_Index]
        }

        if (opera == "系统") {
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }

        if (opera == "时间" && IsTimeCategoryName(Data.CopyVariableArr[A_Index])) {
            hasValue := TryGetTabVarValue(&Value, tableItem, index, Data.CopyVariableArr[A_Index])
            if (!hasValue)
                return
        }
        else if (opera == "时间") {   ;旧「时间」：取当前时间字符串（兼容已保存宏）
            srcVal := Data.CopyVariableArr[A_Index]
            if (srcVal != "") {
                hasSrc := TryGetTabVarValue(&srcTime, tableItem, index, srcVal, false)
                stamp := hasSrc ? TimeToAhkStamp(srcTime) : ""
            } else {
                stamp := ""
            }
            if (stamp == "")
                stamp := A_Now
            Value := FormatTime(stamp, "yyyy-MM-dd HH:mm:ss")
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
    cmdName := StrSplit(cmd, "_")[1]
    Data := GetMacroCMDData(cmdName)

    ; 变量初始化默认值0
    NameArr := []
    ValueArr := []
    for i, toggle in Data.ToggleArr {
        if (toggle) {
            NameArr.Push(Data.VariableArr[i])
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
            return [cmd]
        }
        return true
    } else {
        loop Data.SearchCount {
            WaitIfPaused(tableItem, index)

            item := tableItem.Items[index]
            if (item.Killed)
                return

            if (OnExVariableOnce(tableItem, index, Data))
                return

            if (A_Index < Data.SearchCount) {
                FloatInterval := GetFloatTime(Data.SearchInterval, MainSoftData.PreIntervalFloat)
                InterruptibleSleep(tableItem, index, FloatInterval)
            }
        }
    }
}

OnExVariableOnce(tableItem, index, Data) {
    TextObjs := []
    switch CmdEnumZh(Data.ExtractType, CmdEnumExtractNames()) {
        case "屏幕":
            if (!TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
             || !TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
             || !TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
             || !TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY))
                return false
            TextObjs := GetScreenTextObjArr(X1, Y1, X2, Y2, Data.OCRType)
            if (TextObjs == "")
                TextObjs := []

        case "剪切板":
            if (!IsClipboardText())
                return false
            TextObjs := [{ Text: A_Clipboard }]

        case "窗口":
            if (!TryGetTabVarValue(&X1, tableItem, 1, Data.StartPosX)
             || !TryGetTabVarValue(&Y1, tableItem, 1, Data.StartPosY)
             || !TryGetTabVarValue(&X2, tableItem, 1, Data.EndPosX)
             || !TryGetTabVarValue(&Y2, tableItem, 1, Data.EndPosY))
                return false
            hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.WinInfo))   ; §22 绑定窗口替换
            for hwnd in hwndList {
                if ((CurWinTextObjs := GetWinTextObjArr(hwnd, X1, Y1, X2, Y2, Data.OCRType)) != "")
                    TextObjs.Push(CurWinTextObjs*)
            }
    }

    allText := ""
    for _, value in TextObjs {
        allText .= value.Text "`n"
    }
    allText := RTrim(allText, "`n")

    ExtractStr := GetReplaceVarText(tableItem, index, Data.ExtractStr)
    activeLen := GetExVariableActiveLength(Data.ToggleArr)

    for _, value in TextObjs {
        VariableValueArr := ExtractVariable(value.Text, ExtractStr)
        if (ExtractStr == "" && allText != "")
            VariableValueArr := [allText]
        if (VariableValueArr == "" || activeLen > VariableValueArr.Length)
            continue

        RealNameArr := []
        RealValueArr := []
        for i, toggle in Data.ToggleArr {
            if (toggle) {
                RealNameArr.Push(Data.VariableArr[i])
                RealValueArr.Push(VariableValueArr[i])
            }
        }
        MySetGlobalVariable(RealNameArr, RealValueArr, Data.IsIgnoreExist)
        return true
    }

    return false
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

        mouseBtn := CmdEnumZh(Data.MouseType, CmdEnumMouseBtnNames())
        if (mouseBtn == "滚轮") {
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

        btnIdx := Map("左键", 1, "中键", 2, "右键", 3).Get(mouseBtn, 1)
        oper := CmdEnumZh(Data.OperateType, CmdEnumBgOperNames())
        if (oper == "点击") {
            PostMessage WM_DOWN_ARR[btnIdx], 1, lParam, , "ahk_id " hwnd
            Sleep Data.ClickTime
            PostMessage WM_UP_ARR[btnIdx], 0, lParam, , "ahk_id " hwnd
        }
        else if (oper == "双击") {
            PostMessage WM_DCLICK_ARR[btnIdx], 1, lParam, , "ahk_id " hwnd
            Sleep Data.ClickTime
            PostMessage WM_UP_ARR[btnIdx], 0, lParam, , "ahk_id " hwnd
        }
        else if (oper == "按下") {
            PostMessage WM_DOWN_ARR[btnIdx], 1, lParam, , "ahk_id " hwnd
        }
        else if (oper == "松开") {
            PostMessage WM_UP_ARR[btnIdx], 0, lParam, , "ahk_id " hwnd
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
        if (CmdEnumKeyAct(Data.Type) == "点击" && A_Index != Data.ClickCount)
            Sleep(FloatInterval)
    }
}

SendBGKey(Data, tableItem, index) {
    hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.FrontStr))   ; §22 绑定窗口替换

    keyAct := CmdEnumKeyAct(Data.Type)
    if (keyAct == "按下" || keyAct == "点击") {
        for hwnd in hwndList {
            for key in Data.KeyArr {
                SendBGKeyState(hwnd, key, 1, tableItem, index)
            }
        }

    }

    if (keyAct == "点击") {
        Sleep(Data.ClickTime)
    }

    if (keyAct == "松开" || keyAct == "点击") {
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
        MoveMode := CmdEnumMoveMode(Data.MoveMode)
    } else {
        PosX := 0, PosY := 0
        if (paramArr.Length < 3 || !TryGetTabVarValue(&PosX, tableItem, index, paramArr[2], false))
            PosX := (paramArr.Length >= 2 && IsNumber(paramArr[2])) ? Integer(paramArr[2]) : 0
        if (paramArr.Length < 3 || !TryGetTabVarValue(&PosY, tableItem, index, paramArr[3], false))
            PosY := (paramArr.Length >= 3 && IsNumber(paramArr[3])) ? Integer(paramArr[3]) : 0
        Speed := paramArr.Length >= 4 ? Integer(paramArr[4]) : 90
        MoveMode := CmdEnumMoveMode(paramArr.Length >= 5 ? paramArr[5] : 0)
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
        isRandom := CmdEnumZh(Data.Type, CmdEnumIntervalNames()) == "随机"
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

OnPressJoy(tableItem, cmd, index) {
    global MySoftData
    MySoftData.HasJoyMacro := true
    info := JoyCmdToPressKeyParts(cmd)
    if (info.axes.Length > 0) {
        for ax in info.axes
            OnPressKey(tableItem, GetLang("按键") "_" ax, index)
        if (info.buttons.Length == 0)
            return
    }
    if (info.buttons.Length == 0)
        return
    keyName := ""
    for b in info.buttons
        keyName .= (keyName == "" ? "" : "⎖") b
    press := GetLang("按键") "_" keyName "_" info.ktype
    for r in info.rest
        press .= "_" r
    return OnPressKey(tableItem, press, index)
}

OnPressKey(tableItem, cmd, index) {
    global MySoftData
    paramArr := SplitCommand(cmd)
    ; 阶段5：新格式 按键<serial> 走配置文件；旧格式 按键_a_点击_100 兼容
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    isConfigCmd := (numbersOnly != "" && MySoftData.DataFileMap.Has(textOnly))
    if (isConfigCmd) {
        Data := GetMacroCMDData(paramArr[1])
        keyName := Data.KeyName
        keyTypeVal := CmdEnumKeyAct(Data.KeyType)
        holdTime := Data.HoldTime
        count := Data.Count
        intervalTime := Data.IntervalTime
    } else {
        Data := ""
        keyName := paramArr[2]
        ; 纯文本带值轴指令（录制产物 按键_JoyAxisLX:75，无"按下/松开/点击"类型段）：
        ; 无需解析 keyType/保持等，后续统一轴分支会直接设值并 return。
        isTextAxisCmd := (paramArr.Length == 2 && RegExMatch(paramArr[2]
            , "^(JoyAxisL[XY]|JoyAxisR[XY]|JoyAxisL[TR]|JoyAxisR[TR]):(-?[0-9]+)$"))
        keyTypeVal := isTextAxisCmd ? "按下" : CmdEnumKeyAct(paramArr[3])
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
    item := GetItemByIndex(tableItem, index)
    if (!item)
        return

    ; 轴模拟量指令：把该虚拟手柄轴设为目标值并保持。
    ; 轴是连续行为（非按键），无"按下/松开/点击"。直至下一条同轴指令覆盖
    ; （含 AxisValue=0 回中）或宏链被中断/停止时兜底回中。
    ; 两种来源：
    ;   1) 编辑器/录制 config：按键<serial> → Data.IsAxis=1，值在 Data.AxisValue
    ;   2) 录制纯文本（可读、剪贴板粘贴）：按键_JoyAxisLX:75 → 值内联在键名
    axisKey := ""
    axisValue := ""
    if (isConfigCmd && IsObject(Data) && Data.IsAxis && InStr(Data.KeyName, "JoyAxis")) {
        axisKey := Data.KeyName
        axisValue := Data.HasOwnProp("AxisValue") ? Data.AxisValue : 0
    } else if (!isConfigCmd && RegExMatch(keyName
        , "^(JoyAxisL[XY]|JoyAxisR[XY]|JoyAxisL[TR]|JoyAxisR[TR]):(-?[0-9]+)$", &am)) {
        axisKey := am[1]
        axisValue := Integer(am[2])
    }
    if (axisKey != "") {
        JoyDebugLog(Format("OnPressKey AXIS cmd={} key={} value={} mode={} pool={} killed={}"
            , cmd, axisKey, axisValue, item.Mode, WorkPoolEnabled(), item.Killed), "press")
        ; 连续语义：恒定 state=1（设到 axisValue 并 TrackDown 保持）。axisValue=0 即回中/归零。
        SendJoyAxisValueKey(axisKey, 1, axisValue, tableItem, index)
        return
    }

    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey, 4, SendAHIKey, 5, SendViiperKey)
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
        if (CmdEnumKeyAct(keyType) == "点击" && A_Index != count && FloatInterval > 0)
            Sleep(FloatInterval)
    }
}

; 滚轮/亮度键只有按下事件；共享给热键绑定与替换释放逻辑（本文件也由 Worker 加载）。
IsPulseTriggerKey(keyStr) {
    k := StrLower(keyStr)
    return InStr(k, "wheel") || InStr(k, "bright_")
}

;按键替换。热键绑定的是表 ID + 条目 ID，按下时再解析当前行。
; 行被删除或换序后，旧下标会指向空数组（Invalid index: 1），不能再用行号取 Mode。
ReplaceKeysUseJoy(replaceKey) {
    for key in StrSplit(replaceKey, ",") {
        if (InStr(MySoftData.GetJoyFriendlyKey(Trim(key)), "Joy") == 1)
            return true
    }
    return false
}

OnReplaceDownKey(tableID, itemID, *) {
    ReplaceKeySend(tableID, itemID, 1)
    resolved := ResolveMacroItem(tableID, itemID)
    if (!resolved || resolved.Item.HoldKey.Count == 0)
        return
    item := resolved.Item
    ; 手柄由 JoyMacro 提供松开边沿；键鼠补充物理键态检测，覆盖组合键和切换窗口后丢失的 up。
    if (InStr(item.TK, "Joy"))
        return
    if (!item.HasOwnProp("ReplaceReleaseTimer") || item.ReplaceReleaseTimer == "")
        item.ReplaceReleaseTimer := WatchReplaceKeyRelease.Bind(tableID, itemID, item.TK)
    ; 滚轮只有按下事件，替换为一次短按，不能让虚拟手柄一直按住。
    SetTimer(item.ReplaceReleaseTimer, IsPulseTriggerKey(item.TK) ? -50 : 30)
}

OnReplaceUpKey(tableID, itemID, *) {
    ReplaceKeySend(tableID, itemID, 0)
}

WatchReplaceKeyRelease(tableID, itemID, triggerKey) {
    resolved := ResolveMacroItem(tableID, itemID)
    if (!resolved) {
        SetTimer(, 0)
        return
    }
    released := true
    if (!IsPulseTriggerKey(triggerKey))
        try released := !AreKeysPressed(triggerKey)
    if (released || MainSoftData.IsSuspend || resolved.Item.HoldKey.Count == 0)
        OnReplaceUpKey(tableID, itemID)
}

; 重绑/停用/退出时释放替换项；替换不经过宏运行状态机，ColorState 不会标记为运行中。
ReleaseReplaceKeys() {
    for tableItem in MySoftData.TableInfo {
        if (tableItem.Symbol != "Replace")
            continue
        for item in tableItem.Items
            OnReplaceUpKey(tableItem.ID, item.ID)
    }
}

ReplaceKeySend(tableID, itemID, state) {
    resolved := ResolveMacroItem(tableID, itemID)
    if (!resolved)
        return
    tableItem := resolved.Table
    item := resolved.Item
    index := resolved.Index
    if (!state) {
        if (item.HasOwnProp("ReplaceReleaseTimer") && item.ReplaceReleaseTimer != "") {
            SetTimer(item.ReplaceReleaseTimer, 0)
            item.ReplaceReleaseTimer := ""
        }
        ; 按实际发送过的键及通道松开，编辑替换内容或切换模式后也能释放原来的输出。
        ReleaseTableItemHoldKeys(tableItem, index)
        return
    }
    if (MainSoftData.IsSuspend)
        return
    infos := StrSplit(item.Macro, ",")
    mode := 1
    try mode := Integer(item.Mode)
    catch
        mode := 1
    actionMap := Map(1, SendNormalKey, 2, SendGameModeKey, 3, SendLogicKey, 4, SendAHIKey, 5, SendViiperKey)
    if (!actionMap.Has(mode))
        mode := 1
    baseAction := actionMap[mode]
    loop infos.Length {
        assistKey := Trim(infos[A_Index])
        assistKey := StrReplace(assistKey, "逗号", ",")
        if (assistKey = "")
            continue
        assistKey := MySoftData.GetJoyFriendlyKey(assistKey)
        ; 每个替换键独立分发，允许键鼠与手柄混选；手柄输出不受键鼠模拟模式影响。
        action := baseAction
        if (InStr(assistKey, "JoyAxis") == 1)
            action := SendJoyAxisKey
        else if (InStr(assistKey, "JoyDpad") == 1)
            action := SendJoyDpadKey
        else if (InStr(assistKey, "Joy") == 1)
            action := SendJoyBtnKey
        action(assistKey, state, tableItem, index)
    }
}

;按钮回调
MenuReload(*) {
    ; 持久化当前 tab 用 TableID（身份）；未切换过则回落 TabCtrl.Value
    savedTab := MainSoftData.CurTableID != "" ? MainSoftData.CurTableID : MainSoftData.TabCtrl.Value
    CfgWrite(savedTab, SettingFile, SettingSection, "TableIndex")
    CfgWrite(true, SettingFile, SettingSection, "IsReload")
    SafeReload()
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
            MySetGlobalArray(Data.Name, CloneArray(Data.InitArr))
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
        case "选择":
            InputChoice(Data, tableItem, index, false)
        case "选择文件":
            InputPickFile(Data, tableItem, index)
        case "多选":
            InputChoice(Data, tableItem, index, true)
        case "继续":
            InputContinue(Data, tableItem, index)
        case "继续&取消":
            InputContinueAndCencel(Data, tableItem, index)
    }
}

OnFileIO(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    OperType := FileIONormType(Data.OperType)

    ; 文件路径支持 {变量}：解析放在执行层（ReadExcel/WriteExcel/ReadTextFile/WriteTextFile 内 GetReplaceVarText）。
    ; 只有读取类才校验“解析后文件是否存在”，缺失时提示重新选择；
    ; 写入类不校验存在性——目标文件（如带日期的新文件名）可能尚未创建。
    if (FileIOIsReadType(OperType)) {
        isExcel := FileIOIsExcelType(OperType)
        filter := isExcel ? "Excel Files (*.xlsx; *.xls)" : ""
        if (!ValidateCmdPath(&Data, "FilePath", GetLang("选择文件"), filter, tableItem, index))
            return
    }

    switch OperType {
        case "读取Excel":
            ReadExcel(Data, tableItem, index)
        case "写入Excel":
            WriteExcel(Data, tableItem, index)
        case "读取文件":
            ReadTextFile(Data, tableItem, index)
        case "写入文件":
            WriteTextFile(Data, tableItem, index)
    }
}

; 将标题、类名、进程名条件解析为可见窗口的精确句柄。
; 显式句柄/窗口组保留原意；多个可见匹配项仍按窗口层叠顺序选第一个。
MaximizeManagedWindow(winTitle) {
    SetManagedWindowState(winTitle, 1)
}

SetManagedWindowState(winTitle, state) {
    ; 先固定目标，兼容显式窗口组，避免最大化改变层叠顺序后重新匹配到其它窗口。
    hwnds := WinGetList(winTitle)
    for hwnd in hwnds {
        try {
            target := "ahk_id " hwnd
            restoreFromMinimized := state == 0 && WinGetMinMax(target) == -1
            switch state {
                case 1: WinMaximize(target)
                case -1: WinMinimize(target)
                case 0: WinRestore(target)
            }
            ; 部分自绘窗口不响应 ShowWindow，改用对应的系统命令。
            ; 无需先 WinActivate，也不向其它匹配窗口重试。
            currentState := WinGetMinMax(target)
            if (currentState != state && !(restoreFromMinimized && currentState == 1)) {
                command := state == 1 ? 0xF030 : state == -1 ? 0xF020 : 0xF120
                PostMessage(0x0112, command, 0, , target) ; WM_SYSCOMMAND
                ; 等待异步命令生效，避免后续移动、点击抢在状态切换之前执行。
                deadline := A_TickCount + 250
                while (WinExist(target) && WinGetMinMax(target) != state
                    && !(restoreFromMinimized && WinGetMinMax(target) == 1) && A_TickCount < deadline)
                    Sleep(10)
            }
        }
    }
}


; 按层叠顺序收集可见匹配项，显式句柄或窗口组尊重用户指定。
WindowMatchedHandles(query, matchMode := "所有") {
    result := []
    if (query == "")
        return result
    explicit := InStr(query, "ahk_id ") || InStr(query, "ahk_group ")
    for hwnd in WinGetList(query) {
        if (!explicit) {
            if (!DllCall("IsWindowVisible", "ptr", hwnd))
                continue
            try cls := WinGetClass("ahk_id " hwnd)
            catch
                continue
            if (cls == "Progman" || cls == "WorkerW")
                continue
        }
        result.Push(hwnd)
    }
    if (result.Length && matchMode != "所有")
        return [result[matchMode == "最后" ? -1 : 1]]
    return result
}

WindowReadInfo(data, query) {
    WindowEnsureResults(data)
    fields := WindowInfoFields(data.ActionType)
    if (!fields.Length)
        return false
    values := []
    for label in fields
        values.Push("")
    isList := data.ActionType == "匹配窗口列表"
    matchMode := data.HasProp("MatchMode") ? data.MatchMode : (isList ? "所有" : "首个")
    hwnds := WindowMatchedHandles(query, matchMode)
    if (isList) {
        name := GetVarName(data.ResultVar1)
        if (name != "")
            MySetGlobalArray(name, hwnds)
        return true
    }
    hwnd := hwnds.Length ? hwnds[1] : 0
    if (data.ActionType == "窗口状态")
        values := [0, 0, 0, 0, 0, "", 0]
    if (hwnd) {
        target := "ahk_id " hwnd
        try {
            switch data.ActionType {
                case "窗口位置", "位置与宽高":
                    WinGetPos(&x, &y, &w, &h, target)
                    values := data.ActionType == "窗口位置" ? [x, y] : [x, y, w, h]
                case "标题类名句柄":
                    values := [WinGetTitle(target), WinGetClass(target), hwnd]
                case "进程信息":
                    values[1] := WinGetProcessName(target)
                    values[2] := WinGetPID(target)
                    values[3] := WinGetProcessPath(target)
                case "窗口状态":
                    mm := WinGetMinMax(target)
                    alpha := WinGetTransparent(target)
                    exStyle := WinGetExStyle(target)
                    values := [1, WinActive(target) ? 1 : 0, mm == -1 ? 1 : 0, mm == 1 ? 1 : 0, (exStyle & 0x8) ? 1 : 0,
                        alpha == "" ? 100 : Round(alpha * 100 / 255), (exStyle & 0x20) ? 1 : 0]
                case "透明度与鼠标穿透状态":
                    alpha := WinGetTransparent(target)
                    values := [alpha == "" ? 100 : Round(alpha * 100 / 255), (WinGetExStyle(target) & 0x20) ? 1 : 0]
            }
        }
    }
    names := [], results := []
    for i, value in values {
        prop := "ResultVar" i
        name := GetVarName(data.%prop%)
        if (name != "") {
            names.Push(name)
            results.Push(value)
        }
    }
    if (names.Length)
        MySetGlobalVariable(names, results, false)
    return true
}

CenterManagedWindow(hwnd) {
    target := "ahk_id " hwnd
    WinGetPos(, , &w, &h, target)
    monitor := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    info := Buffer(40, 0)
    NumPut("uint", 40, info)
    if (!DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", info))
        return
    left := NumGet(info, 20, "int"), top := NumGet(info, 24, "int")
    right := NumGet(info, 28, "int"), bottom := NumGet(info, 32, "int")
    WinMove(left + Floor((right - left - w) / 2), top + Floor((bottom - top - h) / 2), , , target)
}

OnWindowManage(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])

    searchValue := GetReplaceVarText(tableItem, index, ResolveBindWindow(tableItem, index, Data.SearchValue))
    winTitle := GetParamsWinInfoStr(searchValue)
    if (WindowReadInfo(Data, winTitle))
        return
    matchMode := Data.HasProp("MatchMode") ? Data.MatchMode
        : WindowDefaultMatchMode(Data.ActionType, InStr(winTitle, "ahk_id ") || InStr(winTitle, "ahk_group "))
    ; 先固定匹配窗口，层叠顺序在后续操作中可能变化。
    hwnds := WindowMatchedHandles(winTitle, matchMode)
    if (!hwnds.Length)
        return

    ; 查询返回第一个匹配窗口的完整宽高，与工具监视的尺寸一致。
    if (Data.ActionType == "获取窗口宽高") {
        try {
            WinGetPos(, , &width, &height, "ahk_id " hwnds[1])
            widthVar := GetVarName(Data.WidthVarName)
            heightVar := GetVarName(Data.HeightVarName)
            if (widthVar != "" && heightVar != "")
                MySetGlobalVariable([widthVar, heightVar], [width, height], false)
        }
        return
    }

    if (Data.ActionType == "激活窗口") {
        ; 逐个激活时从后向前，最后让原本最靠前的匹配窗口获得焦点。
        Loop hwnds.Length {
            try WinActivate("ahk_id " hwnds[-A_Index])
        }
        return
    }
    if (Data.ActionType == "关闭窗口" && Data.HasProp("CloseProcess") && Data.CloseProcess) {
        ; 先固定并去重进程，避免结束一个进程后同进程其它窗口句柄失效。
        pids := Map()
        for hwnd in hwnds {
            try pids[WinGetPID("ahk_id " hwnd)] := true
        }
        for pid in pids {
            try ProcessClose(pid)
        }
        return
    }
    for hwnd in hwnds {
        try {
            winTitle := "ahk_id " hwnd
            switch Data.ActionType {
                case "最大化窗口":
                    MaximizeManagedWindow(winTitle)
                case "最小化窗口":
                    SetManagedWindowState(winTitle, -1)
                case "还原窗口":
                    SetManagedWindowState(winTitle, 0)
                case "关闭窗口":
                    WinClose(winTitle)
                case "窗口居中":
                    CenterManagedWindow(hwnd)
                case "位置和宽高":
                    if (TryGetTabVarValue(&x, tableItem, index, Data.PosX)
                        && TryGetTabVarValue(&y, tableItem, index, Data.PosY)
                        && TryGetTabVarValue(&w, tableItem, index, Data.Width)
                        && TryGetTabVarValue(&h, tableItem, index, Data.Height))
                        WinMove(Integer(x), Integer(y), Integer(w), Integer(h), winTitle)
                case "移动窗口", "相对移动":
                    hasPosX := TryGetTabVarValue(&PosX, tableItem, index, Data.PosX)
                    hasPosY := TryGetTabVarValue(&PosY, tableItem, index, Data.PosY)
                    if (hasPosX && hasPosY) {
                        if (Data.ActionType == "相对移动") {
                            WinGetPos(&oldX, &oldY, , , winTitle)
                            PosX += oldX
                            PosY += oldY
                        }
                        WinMove(Integer(PosX), Integer(PosY), , , winTitle)
                    }
                case "调整宽高", "调整大小":
                    hasWidth := TryGetTabVarValue(&Width, tableItem, index, Data.Width)
                    hasHeight := TryGetTabVarValue(&Height, tableItem, index, Data.Height)
                    if (hasWidth && hasHeight) {
                        WinMove(, , Integer(Width), Integer(Height), winTitle)
                    }
                case "切换置顶":
                    WinSetAlwaysOnTop(-1, winTitle)
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
                case "切换鼠标穿透":
                    if (WinGetExStyle(winTitle) & 0x20)
                        WinSetExStyle("-0x20", winTitle)
                    else {
                        if (!(WinGetExStyle(winTitle) & 0x80000))
                            WinSetTransparent(255, winTitle)
                        WinSetExStyle("+0x20", winTitle)
                    }
                case "开启鼠标穿透":
                    ; 普通窗口需启用分层样式，才能向其它进程的窗口透传鼠标。
                    ; 已有的透明度/分层绘制效果保持原样。
                    if (!(WinGetExStyle(winTitle) & 0x80000))
                        WinSetTransparent(255, winTitle)
                    WinSetExStyle("+0x20", winTitle)
                case "关闭鼠标穿透":
                    WinSetExStyle("-0x20", winTitle)
            }
        }
    }
}

OnKeyCheck(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    ApplyKeyCheckResult(Data)
}

OnJoyCheck(tableItem, cmd, index) {
    paramArr := StrSplit(cmd, "_")
    Data := GetMacroCMDData(paramArr[1])
    ApplyKeyCheckResult(Data, true)
}

ApplyKeyCheckResult(Data, isJoy := false) {
    keyArr := Data.KeyArr
    if (keyArr.Length == 0)
        return

    varName := Data.VarName
    analogKeys := []
    digitalKeys := []
    for key in keyArr {
        if (RegExMatch(key, "^(?:JoyAxis)?(L[XY]|R[XY]|LT|RT):(-?[0-9]+)$"))
            analogKeys.Push(key)
        else
            digitalKeys.Push(key)
    }
    checkType := isJoy ? CmdEnumJoyCheck(Data.CheckType, analogKeys.Length > 0) : CmdEnumZh(Data.CheckType, CmdEnumKeyCheckNames())
    stateType := CmdEnumZh(Data.StateType, CmdEnumStateNames())

    if (analogKeys.Length > 0) {
        ok := true
        for key in analogKeys {
            if (!IsCheckKeyPressed(key, "", checkType, isJoy)) {
                ok := false
                break
            }
        }
        MySetGlobalVariable([varName], [ok ? 1 : 0], false)
        return
    }

    stateMode := stateType == "物理状态" ? "P" : ""
    isAllPressed := true
    isAnyPressed := false
    for key in digitalKeys {
        isPressed := IsCheckKeyPressed(key, stateMode, "大于等于", isJoy)
        if (isPressed) {
            isAnyPressed := true
            if (checkType == "有一个按下")
                break
        } else {
            isAllPressed := false
            if (checkType == "同时按下")
                break
        }
    }
    result := (checkType == "同时按下") ? (isAllPressed ? 1 : 0) : (isAnyPressed ? 1 : 0)
    MySetGlobalVariable([varName], [result], false)
}

IsCheckKeyPressed(key, stateMode, axisCmp := 2, isJoy := false) {
    global MySoftData
    if (RegExMatch(key, "^(?:JoyAxis)?(L[XY]|R[XY]|LT|RT):(-?[0-9]+)$", &am))
        return IsJoyAxisCompare(am[1], Integer(am[2]), axisCmp)

    static shortMap := Map(
        "A", "JoyA", "B", "JoyB", "X", "JoyX", "Y", "JoyY",
        "LB", "JoyLB", "RB", "JoyRB", "LT", "JoyLT", "RT", "JoyRT",
        "LS", "JoyLS", "RS", "JoyRS", "Back", "JoyBack", "Start", "JoyStart",
        "Home", "JoyHome", "Pad", "JoyPad",
        "上", "JoyDpadUp", "下", "JoyDpadDown", "左", "JoyDpadLeft", "右", "JoyDpadRight",
        "无方向", "JoyDpadNone", "无", "JoyDpadNone")
    inn := isJoy && shortMap.Has(key) ? shortMap[key] : key

    if (inn == "JoyDpadNone")
        return IsJoyPovCentered()

    joyMap := IsObject(MySoftData) ? MySoftData.GetJoyToAhkMap() : Map()
    ahkKey := joyMap.Has(inn) ? joyMap[inn] : inn
    if (RegExMatch(ahkKey, "^JoyPOV_(\d+)$", &pm))
        return IsJoyPovAt(Integer(pm[1]))

    if (InStr(inn, "Joy") || InStr(inn, "Axis") || InStr(inn, "Dpad")) {
        if (stateMode == "P")
            return IsPhysicalKeyPressed(ahkKey)
        try
            return !!GetKeyState(ahkKey)
        catch
            return IsPhysicalKeyPressed(ahkKey)
    }

    try
        return stateMode == "" ? !!GetKeyState(key) : !!GetKeyState(key, stateMode)
    catch
        return false
}

IsJoyPovAt(target) {
    loop 4 {
        try {
            pov := GetKeyState(A_Index "JoyPOV")
            if (IsNumber(pov) && Integer(pov) == target)
                return true
        }
    }
    return false
}

IsJoyPovCentered() {
    found := false
    loop 4 {
        try {
            pov := GetKeyState(A_Index "JoyPOV")
            found := true
            if (pov == "" || pov == -1)
                return true
        }
    }
    return !found
}

IsJoyAxisCompare(name, stored, cmpType) {
    static axisMap := Map("LX", "JoyX", "LY", "JoyY", "RX", "JoyU", "RY", "JoyR", "LT", "JoyZ", "RT", "JoyZ")
    ahkAxis := axisMap.Has(name) ? axisMap[name] : ""
    if (ahkAxis == "")
        return false
    isTrig := (name == "LT" || name == "RT")
    loop 4 {
        try {
            raw := GetKeyState(A_Index ahkAxis)
            if (!IsNumber(raw))
                continue
            cur := isTrig ? Integer(raw) : Integer((Float(raw) - 50) * 2)
            switch CmdEnumJoyCheck(cmpType, true) {
                case "大于设定值":
                    if (cur > stored)
                        return true
                case "大于等于":
                    if (cur >= stored)
                        return true
                case "等于设定值":
                    if (cur == stored)
                        return true
                case "小于等于":
                    if (cur <= stored)
                        return true
                case "小于设定值":
                    if (cur < stored)
                        return true
                default:
                    if (cur >= stored)
                        return true
            }
        }
    }
    return false
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

    if (CmdEnumNameType(Data.NameType) == "固定名称" && Data.FixedName != "") {
        fileName := Data.FixedName ".png"
    } else {
        fileName := Data.SerialStr "-" A_Now ".png"
    }

    filePath := baseDir "\" fileName
    ShotDebugLog(Format("截图将保存到：{}", filePath))

    ocvReason := OpenCvEnsure()
    if (ocvReason != "") {
        ; 失败原因已由 OpenCvEnsure 写进日志；启动时的界面提示在主进程 InitNativePlugins 里做
        ShotDebugLog(Format("抓图失败：OpenCV 不可用（{}）", ocvReason))
        return
    }

    if (CmdEnumZh(Data.ScreenShotType, CmdEnumShotNames()) == "窗口抓图") {
        winInfo := GetReplaceVarText(tableItem, index, ResolveBindWindow(tableItem, index, Data.WinInfo))
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
