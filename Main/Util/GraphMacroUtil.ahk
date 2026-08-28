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
    ; 归口统一日志（C 项）：GraphPool 语义归入系统日志 info 级
    who := MySoftData.isWorker ? ("Worker#" workIndex) : "Master"
    msg := detail != "" ? (tag " " detail) : tag
    RMTLogSys(RMT_LV_INFO, who, msg)
}

FlushLogBufferAsync() {
    ; 已归口 RMTLog（LogUtil 自带缓冲+异步刷新），此函数保留为空壳兼容旧调用
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
    return WorkPoolEnabled()
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
            , tableItem.ID, index, branches.Length, branches[1], fromStart ? 1 : 0))
        subsidiary := []
        loop branches.Length - 1
            subsidiary.Push(branches[A_Index + 1])
        global MySubmitGraphBranches
        ; 传条目对象（WorkSubmitGraphBranches 取 .ID 作为 ItemID，身份=ID）
        MySubmitGraphBranches(tableItem, tableItem.Items[index], fromStart ? branches.Length : 0, subsidiary)
        WalkGraphNode(tableItem, branches[1], index)
        return
    }
    ; Master：直接通过 WorkPool 分配其余分支（任务队列存 TableID/ItemID，cmd 用 R1 IPC 编码）
    global MyWorkPool
    tableID := tableItem.ID
    itemID := tableItem.Items[index].ID
    loop branches.Length - 1 {
        cmd := EncodeBatch(EncodeCommand("TR", tableID, itemID, branches[A_Index + 1]))
        tableItem.Items[index].GraphBranchCount++
        GraphPoolLog("分支分配", Format("tab={1} item={2} node={3} 来源=Master/DispatchGraphBranches", tableID, itemID, branches[A_Index + 1]))
        MyWorkPool.taskQueue.Push({ cmd: cmd, tableID: tableID, itemID: itemID, isGraphBranch: true })
        MyWorkPool.Dispatch()
    }
    WalkGraphNode(tableItem, branches[1], index)
}

WalkGraphNode(tableItem, nodeSerial, index) {
    who := MySoftData.isWorker ? Format("W{1}", workIndex) : "Master"
    item := tableItem.Items[index]
    GraphPoolLog("进入节点", Format("执行者={1} tab={2} item={3} node={4}", who, tableItem.ID, index, nodeSerial))
    if (item && item.Killed) {
        GraphPoolLog("跳过节点", Format("执行者={1} tab={2} item={3} node={4} 原因=已终止", who, tableItem.ID, index, nodeSerial))
        return
    }
    if (!IsGraphNodeSerial(nodeSerial)) {
        GraphPoolLog("跳过节点", Format("执行者={1} tab={2} item={3} node={4} 原因=非图形节点", who, tableItem.ID, index, nodeSerial))
        return
    }
    nodeData := GetMacroCMDData(nodeSerial)
    if (!IsObject(nodeData)) {
        GraphPoolLog("跳过节点", Format("执行者={1} tab={2} item={3} node={4} 原因=无节点数据", who, tableItem.ID, index, nodeSerial))
        return
    }

    curCmd := nodeData.HasOwnProp("CurCMD") ? nodeData.CurCMD : ""
    if (curCmd != "") {
        ; 使用本地队列处理命令返回的子命令，避免递归栈溢出
        queue := [curCmd]
        while (queue.Length > 0) {
            cmd := queue.RemoveAt(1)
            GraphPoolLog("节点指令", Format("执行者={1} tab={2} item={3} node={4} cmd={5}", who, tableItem.ID, index, nodeSerial, GetCmdStr(cmd)))
            result := ExecuteMacroCmdOnce(tableItem, cmd, index, nodeSerial)
            if (result != "") {
                pos := 1
                for r in result {
                    queue.InsertAt(pos, r)
                    pos++
                }
            }
            if (item && item.Killed)
                return
            if (item.VariableMap["分支-跳出"]) {
                item.VariableMap["分支-跳出"] := false
                return
            }
            if (item.VariableMap["循环-跳出"])
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
    if (branches.Length > 1 && MySoftData.isWorker) {
        item := tableItem.Items[index]
        if (item)
            item.GraphBranchCount := branches.Length
    }
    DispatchGraphBranches(tableItem, index, nodeArr, true)
}

; 主进程占位；Worker 中由 WrokGlobalUtil 覆盖为 WorkSubmitGraphBranches
SubmitGraphBranchesHandler(tableIndex, itemIndex, branchCount, nodeSerialArr, *) {
}

; ---------- 编辑器切换辅助（逻辑树 ↔ 节点图）----------

; 是否为「图形开始节点」序列码
IsGraphStartSerial(serialStr) {
    if (serialStr == "")
        return false
    SplitSerialTextAndNumbers(serialStr, &t, &n)
    return t == GetLangKey("图形开始节点") && n != ""
}

; 宏内容为空（新建未配置）
IsEmptyMacroStr(macroStr) {
    return Trim(macroStr) == ""
}

; 宏首条指令是否为图形开始节点（用于决定打开哪种编辑器）
IsMacroFirstCmdGraphStart(macroStr) {
    macroStr := Trim(macroStr)
    if (macroStr == "")
        return false
    if (IsGraphStartSerial(macroStr))
        return true
    cmdArr := SplitMacro(macroStr)
    if (cmdArr.Length < 1)
        return false
    return IsGraphStartSerial(cmdArr[1])
}

; 顶层图是否存在「多后继」分叉（NodeArr / NextNodeArr 长度>1，或存在 EmptyNode）。
; 搜索/如果的真假分支存在 TrueMacro/FalseMacro 中，不计入此处。
HasGraphMultiBranch(startSerial) {
    if (!IsGraphStartSerial(startSerial))
        return false
    startData := GetMacroCMDData(startSerial)
    if (!IsObject(startData))
        return false
    nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
    if (nodeArr.Length > 1)
        return true
    emptyArr := (startData.HasOwnProp("EmptyNode") && IsObject(startData.EmptyNode)) ? startData.EmptyNode : []
    if (emptyArr.Length > 0)
        return true

    ; 广度遍历：任一节点 NextNodeArr 多后继即视为多链路
    queue := []
    visited := Map()
    for s in nodeArr {
        if (s != "" && !visited.Has(s)) {
            visited[s] := true
            queue.Push(s)
        }
    }
    qi := 1
    while (qi <= queue.Length) {
        cur := queue[qi++]
        nd := GetMacroCMDData(cur)
        if (!IsObject(nd))
            continue
        nexts := (nd.HasOwnProp("NextNodeArr") && IsObject(nd.NextNodeArr)) ? nd.NextNodeArr : []
        if (nexts.Length > 1)
            return true
        for ns in nexts {
            if (ns != "" && !visited.Has(ns)) {
                visited[ns] := true
                queue.Push(ns)
            }
        }
    }
    return false
}

; 将图形开始节点压成线性宏串：只沿第一链路（NodeArr[1] → 各 NextNodeArr[1]）
; 并递归把循环/搜索/搜索Pro/如果/如果Pro 分支内嵌套的图形开始节点转为线性宏写回 Data
; 多链路时非第一链路内容会丢失
GraphStartToLinearMacro(startSerial) {
    visited := Map()
    linear := GraphStartFlattenFirstChain(startSerial)
    ExpandNestedGraphStartsInMacro(linear, visited)
    return linear
}

; 仅压平第一链路，不处理嵌套分支
GraphStartFlattenFirstChain(startSerial) {
    result := []
    if (!IsGraphStartSerial(startSerial)) {
        for cmd in SplitMacro(startSerial) {
            if (cmd != "")
                result.Push(cmd)
        }
        return GetMacroStrByCmdArr(result)
    }
    startData := GetMacroCMDData(startSerial)
    if (!IsObject(startData))
        return ""
    nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
    cur := nodeArr.Length >= 1 ? nodeArr[1] : ""
    visited := Map()
    while (cur != "" && !visited.Has(cur)) {
        visited[cur] := true
        nd := GetMacroCMDData(cur)
        if (!IsObject(nd))
            break
        cmd := nd.HasOwnProp("CurCMD") ? nd.CurCMD : ""
        if (cmd != "")
            result.Push(cmd)
        nexts := (nd.HasOwnProp("NextNodeArr") && IsObject(nd.NextNodeArr)) ? nd.NextNodeArr : []
        cur := nexts.Length >= 1 ? nexts[1] : ""
    }
    return GetMacroStrByCmdArr(result)
}

; 分支内容（图形开始序列码或线性宏）转为线性宏，并递归处理更深嵌套
; visited[图形开始序列码] 缓存已转换的线性宏，避免重复压平；二次命中返回缓存而非空串
ConvertBranchMacroToLinear(macroStr, visited) {
    macroStr := Trim(macroStr)
    if (macroStr == "")
        return ""

    ; 整个分支就是一个图形开始节点
    if (IsGraphStartSerial(macroStr)) {
        if (visited.Has(macroStr))
            return visited[macroStr]
        visited[macroStr] := ""   ; 占位，防环
        linear := GraphStartFlattenFirstChain(macroStr)
        ExpandNestedGraphStartsInMacro(linear, visited)
        visited[macroStr] := linear
        return linear
    }

    ; 已是线性宏：展开其中夹杂的图形开始节点，并处理各指令的嵌套分支
    cmdArr := SplitMacro(macroStr)
    newArr := []
    changed := false
    for cmd in cmdArr {
        clean := GetCmdStr(cmd)
        if (IsGraphStartSerial(clean)) {
            if (visited.Has(clean)) {
                cached := visited[clean]
                if (cached != "") {
                    for subCmd in SplitMacro(cached) {
                        if (subCmd != "")
                            newArr.Push(subCmd)
                    }
                }
            } else {
                visited[clean] := ""
                nested := GraphStartFlattenFirstChain(clean)
                ExpandNestedGraphStartsInMacro(nested, visited)
                visited[clean] := nested
                for subCmd in SplitMacro(nested) {
                    if (subCmd != "")
                        newArr.Push(subCmd)
                }
            }
            changed := true
        } else {
            newArr.Push(cmd)
            ExpandNestedGraphStartsInCmd(cmd, visited)
        }
    }
    return changed ? GetMacroStrByCmdArr(newArr) : macroStr
}

; 遍历宏串中指令，转换其 Data 分支字段里的嵌套图形开始节点
ExpandNestedGraphStartsInMacro(macroStr, visited) {
    if (Trim(macroStr) == "")
        return
    for cmd in SplitMacro(macroStr)
        ExpandNestedGraphStartsInCmd(cmd, visited)
}

; 若指令含分支字段（循环/搜索/如果…），把其中图形开始节点压成线性宏并写回
ExpandNestedGraphStartsInCmd(cmdStr, visited) {
    serial := StrSplit(GetCmdStr(cmdStr), "_")[1]
    if (serial == "")
        return
    visitKey := "cmd:" serial
    if (visited.Has(visitKey))
        return

    cmdKey := GetLangKey(GetCmdOnlyText(serial))
    static branchCmdMap := Map("循环", true, "搜索", true, "搜索Pro", true, "如果", true, "如果Pro", true)
    if (!branchCmdMap.Has(cmdKey))
        return

    visited[visitKey] := true
    Data := GetMacroCMDData(serial)
    if (!IsObject(Data))
        return

    changed := false
    for f in ["LoopBody", "TrueMacro", "FalseMacro", "DefaultMacro", "SubMacro"] {
        if (!ObjHasOwnProp(Data, f) || Data.%f% == "")
            continue
        oldVal := Data.%f%
        newVal := ConvertBranchMacroToLinear(oldVal, visited)
        if (newVal != oldVal) {
            Data.%f% := GetLangMacro(newVal, 2)
            changed := true
        }
    }
    if (ObjHasOwnProp(Data, "MacroArr") && IsObject(Data.MacroArr)) {
        loop Data.MacroArr.Length {
            m := Data.MacroArr[A_Index]
            if (m == "")
                continue
            newVal := ConvertBranchMacroToLinear(m, visited)
            if (newVal != m) {
                Data.MacroArr[A_Index] := GetLangMacro(newVal, 2)
                changed := true
            }
        }
    }
    if (changed)
        SaveMacroCMDData(Data)
}
