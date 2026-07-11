; 图形宏（MacroGraphStartNode / MacroGraphNode）遍历与多分支并行调度
; 主进程在 RMTUtil.ahk 中赋值为 WorkPool()；Worker 进程不使用本地 WorkPool
global MyWorkPool := ""
global workIndex := 0    ; 主进程占位；Worker 中由 HandleWorkOpenArg 赋实际 idx

GraphPoolLogPath() {
    return MySoftData.isWorker ? A_ScriptDir "\..\Log\GraphPool.log" : A_ScriptDir "\Log\GraphPool.log"
}

; 图形宏线程池调试日志（Master 行附带 Worker 池统计：闲置/忙碌/启动中/队列）
; 使用内存缓冲 + SetTimer 异步刷新，避免磁盘IO阻塞按键处理
global _graphPoolLogBuffer := ""
global _graphPoolLogPath := ""
global _graphPoolLogInitialized := false

GraphPoolLog(tag, detail := "") {
    global MyWorkPool, workIndex, _graphPoolLogBuffer, _graphPoolLogPath, _graphPoolLogInitialized
    static flushSize := 1024 * 50   ; 50KB缓冲
    
    if (!_graphPoolLogInitialized) {
        _graphPoolLogPath := GraphPoolLogPath()
        _graphPoolLogInitialized := true
        SetTimer(FlushLogBufferAsync, 5000)  ; 每5秒异步刷新一次
    }
    
    if (MySoftData.isWorker)
        head := Format("[{}] [W{}] {}", A_Now, workIndex, tag)
    else {
        stats := (MyWorkPool != "" && IsObject(MyWorkPool)) ? MyWorkPool.GetPoolStatsStr() : "pool=未初始化"
        head := Format("[{}] [Master] {} ({})", A_Now, tag, stats)
    }
    line := detail != "" ? head " " detail "`n" : head "`n"
    
    _graphPoolLogBuffer .= line
    
    if (StrLen(_graphPoolLogBuffer) >= flushSize) {
        SetTimer(FlushLogBufferAsync, -1)  ; 立即异步刷新（不阻塞当前线程）
    }
}

FlushLogBufferAsync() {
    global _graphPoolLogBuffer, _graphPoolLogPath, _graphPoolLogInitialized
    
    if (!_graphPoolLogInitialized || _graphPoolLogBuffer == "")
        return
    
    buffer := _graphPoolLogBuffer
    _graphPoolLogBuffer := ""
    
    try {
        logDir := MySoftData.isWorker ? A_ScriptDir "\..\Log" : A_ScriptDir "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        FileAppend(buffer, _graphPoolLogPath, "UTF-8")
    }
}

IsGraphNodeSerial(serialStr) {
    if (serialStr == "")
        return false
    SplitSerialTextAndNumbers(serialStr, &t, &n)
    return t == GetLangKey("图形节点") && n != ""
}

ShouldUseGraphWorkers() {
    global MyWorkPool
    if (MySoftData.isWorker)
        return true
    return MyWorkPool != "" && (MyWorkPool.isDynamic || MyWorkPool.maxSize >= 1)
}

ShouldSkipGraphNextDispatch(cmdStr) {
    if (cmdStr == "")
        return false
    paramArr := StrSplit(GetCmdStr(cmdStr), "_")
    cmdKey := RTrim(paramArr[1], "0123456789")
    skipTypes := [GetLang("如果"), GetLang("如果Pro"), GetLang("搜索"), GetLang("搜索Pro"), GetLang("循环")]
    for t in skipTypes {
        if (cmdKey == t)
            return true
    }
    return false
}

CollectGraphBranchSerials(serialArr) {
    out := []
    if (!IsObject(serialArr))
        return out
    for s in serialArr {
        if (s != "" && IsGraphNodeSerial(s))
            out.Push(s)
    }
    return out
}

; 多后继分支调度：单分支本进程执行，多分支通知 Master 分配其余分支后本进程执行第一个
; fromStart=true：从图形开始节点发起，设置 GraphBranchCount 并标记发起 Worker
DispatchGraphBranches(tableItem, index, serialArr, fromStart := false) {
    branches := CollectGraphBranchSerials(serialArr)
    if (branches.Length == 0)
        return
    if (branches.Length == 1) {
        WalkGraphNode(tableItem, branches[1], index)
        return
    }
    if (!ShouldUseGraphWorkers()) {
        for b in branches
            WalkGraphNode(tableItem, b, index)
        return
    }
    if (MySoftData.isWorker) {
        GraphPoolLog("Worker图形分支", Format("tab={1} item={2} 分支数={3} 本Worker=[{4}] fromStart={5}"
            , tableItem.Index, index, branches.Length, branches[1], fromStart ? 1 : 0))
        subsidiary := []
        loop branches.Length - 1
            subsidiary.Push(branches[A_Index + 1])
        global MySubmitGraphBranches
        MySubmitGraphBranches(tableItem.Index, index, fromStart ? branches.Length : 0, subsidiary)
        WalkGraphNode(tableItem, branches[1], index)
        return
    }
    ; Master：直接通过 WorkPool 分配其余分支
    global MyWorkPool
    loop branches.Length - 1 {
        cmd := JSON.stringify(["TR_MACRO", tableItem.Index, index, branches[A_Index + 1]])
        tableItem.GraphBranchCountArr[index]++
        GraphPoolLog("分支分配", Format("tab={1} item={2} node={3} 来源=Master/DispatchGraphBranches", tableItem.Index, index, branches[A_Index + 1]))
        MyWorkPool.taskQueue.Push({ cmd: cmd, tableIndex: tableItem.Index, itemIndex: index, isGraphBranch: true })
        MyWorkPool.Dispatch()
    }
    WalkGraphNode(tableItem, branches[1], index)
}

WalkGraphNode(tableItem, nodeSerial, index) {
    who := MySoftData.isWorker ? Format("W{1}", workIndex) : "Master"
    GraphPoolLog("进入节点", Format("执行者={1} tab={2} item={3} node={4}", who, tableItem.Index, index, nodeSerial))
    if (tableItem.KilledArr[index]) {
        GraphPoolLog("跳过节点", Format("执行者={1} tab={2} item={3} node={4} 原因=已终止", who, tableItem.Index, index, nodeSerial))
        return
    }
    if (!IsGraphNodeSerial(nodeSerial)) {
        GraphPoolLog("跳过节点", Format("执行者={1} tab={2} item={3} node={4} 原因=非图形节点", who, tableItem.Index, index, nodeSerial))
        return
    }
    nodeData := GetMacroCMDData(nodeSerial)
    if (!IsObject(nodeData)) {
        GraphPoolLog("跳过节点", Format("执行者={1} tab={2} item={3} node={4} 原因=无节点数据", who, tableItem.Index, index, nodeSerial))
        return
    }

    curCmd := nodeData.HasOwnProp("CurCMD") ? nodeData.CurCMD : ""
    if (curCmd != "") {
        ; 使用本地队列处理命令返回的子命令，避免递归栈溢出
        queue := [curCmd]
        while (queue.Length > 0) {
            cmd := queue.RemoveAt(1)
            GraphPoolLog("节点指令", Format("执行者={1} tab={2} item={3} node={4} cmd={5}", who, tableItem.Index, index, nodeSerial, GetCmdStr(cmd)))
            result := ExecuteMacroCmdOnce(tableItem, cmd, index, nodeSerial)
            if (result != "") {
                pos := 1
                for r in result {
                    queue.InsertAt(pos, r)
                    pos++
                }
            }
            if (tableItem.KilledArr[index])
                return
            if (tableItem.VariableMapArr[index]["分支-跳出"]) {
                tableItem.VariableMapArr[index]["分支-跳出"] := false
                return
            }
            if (tableItem.VariableMapArr[index]["循环-跳出"])
                return
        }
    }

    if (ShouldSkipGraphNextDispatch(curCmd))
        return
    nexts := (nodeData.HasOwnProp("NextNodeArr") && IsObject(nodeData.NextNodeArr)) ? nodeData.NextNodeArr : []
    DispatchGraphBranches(tableItem, index, nexts, false)
}

OnTriggerGraphMacro(tableItem, startSerial, index) {
    startData := GetMacroCMDData(startSerial)
    if (!IsObject(startData))
        return
    nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
    branches := CollectGraphBranchSerials(nodeArr)
    ; Worker 多分支启动时设置本地计数，用于跳过 OnFinishMacro（由 Master 统一释放）
    if (branches.Length > 1 && MySoftData.isWorker && tableItem.GraphBranchCountArr.Length >= index)
        tableItem.GraphBranchCountArr[index] := branches.Length
    DispatchGraphBranches(tableItem, index, nodeArr, true)
}

; 主进程占位；Worker 中由 WrokGlobalUtil 覆盖为 WorkSubmitGraphBranches
SubmitGraphBranchesHandler(tableIndex, itemIndex, branchCount, nodeSerialArr, *) {
}
