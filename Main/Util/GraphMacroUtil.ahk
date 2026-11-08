; 图形宏（MacroGraphStartNode / MacroGraphNode）遍历与多分支并行调度
; 主进程在 RMTUtil.ahk 中赋值为 WorkPool()；Worker 进程不使用本地 WorkPool
global MyWorkPool := ""
global workIndex := 0    ; 主进程占位；Worker 中由 HandleWorkOpenArg 赋实际 idx

GraphPoolLog(tag, detail := "") {
    ; 归口统一日志（C 项）：GraphPool 语义归入系统日志 info 级
    msg := detail != "" ? (tag " " detail) : tag
    RMTLogSys(RMT_LV_INFO, ProcessTag(), msg)
}

IsGraphNodeSerial(serialStr) {
    if (serialStr == "")
        return false
    SplitSerialTextAndNumbers(serialStr, &t, &n)
    return t == GetLangKey("图形节点") && n != ""
}

FilterGraphNodeSerials(serialArr) {
    out := []
    if (!IsObject(serialArr))
        return out
    for s in serialArr {
        if (s != "" && IsGraphNodeSerial(s))
            out.Push(s)
    }
    return out
}

; 首条后继在当前进程执行。仅在线程池可用且有多个后继时，才把其余分支交给主进程调度。
; fromStart=true 表示整张图的入口，调度器据此初始化分支计数。后续分叉沿用已有计数。
RunGraphSuccessors(tableItem, index, serialArr, fromStart := false) {
    branches := FilterGraphNodeSerials(serialArr)
    if (branches.Length == 0)
        return
    if (branches.Length == 1) {
        RunGraphNodeChain(tableItem, branches[1], index)
        return
    }
    if (!ShouldUseGraphWorkers()) {
        for b in branches
            RunGraphNodeChain(tableItem, b, index)
        return
    }
    ; 余下分支怎么派：主进程丢线程池、Worker 上报 Master，两份实现见 RunBranchDispatch
    RunBranchDispatch(tableItem, index, branches, fromStart)
    RunGraphNodeChain(tableItem, branches[1], index)
}

RunGraphNodeChain(tableItem, nodeSerial, index) {
    who := ProcessTag()
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
            if (item.VariableMap["循环-跳出"] || item.VariableMap["循环-跳过本轮"])
                return
        }
    }

    ; 节点指令及其返回的子指令跑完后，才继续逻辑后继。上面的跳转标志可提前结束这条链。
    nexts := (nodeData.HasOwnProp("NextNodeArr") && IsObject(nodeData.NextNodeArr)) ? nodeData.NextNodeArr : []
    RunGraphSuccessors(tableItem, index, nexts, false)
}

RunGraphFromStartNode(tableItem, startSerial, index) {
    startData := GetMacroCMDData(startSerial)
    if (!IsObject(startData))
        return
    nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
    RunGraphSuccessors(tableItem, index, nodeArr, true)
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

; 主窗口宏行「编辑」按钮图标：0 未编辑（闪电+刷新）/ 1 逻辑树 / 2 图形节点
GetMacroEditKind(macroStr) {
    if (IsEmptyMacroStr(macroStr))
        return 0
    if (IsMacroFirstCmdGraphStart(macroStr))
        return 2
    return 1
}

; 顶层图是否存在「多后继」分叉（NodeArr / NextNodeArr 长度>1，或存在 EmptyNode）。
; 搜索/如果的真假分支存在 TrueMacro/FalseMacro 中，不计入此处。
GraphHasParallelOrDisconnectedNodes(startSerial) {
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
; 该操作会写回嵌套配置。调用前应完成多链路丢失检查和用户确认。
ConvertGraphToLinearMacroInPlace(startSerial) {
    visited := Map()
    linear := FlattenFirstGraphChain(startSerial)
    ExpandNestedGraphStartsInMacro(linear, visited)
    return linear
}

; 仅压平第一链路，不处理嵌套分支
FlattenFirstGraphChain(startSerial) {
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
        linear := FlattenFirstGraphChain(macroStr)
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
                nested := FlattenFirstGraphChain(clean)
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
    static branchCmdMap := Map("循环", true, "搜索", true, "搜索Pro", true, "搜索All", true, "搜索Combo", true, "组合搜索", true, "搜索Multi", true, "如果", true, "如果Pro", true)
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
