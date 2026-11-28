#Requires AutoHotkey v2.0

class AiDirectDebug {
    static history := []
    static watches := []
    static previous := Map()

    static IsCommand(name) => name == "变量监视" || name == "执行记录" || name == "调试状态" || name == "调试操作" || name == "RMT指令"

    static AddCatalog(catalog) {
        catalog["RMT指令"] := {source: "RMT指令", help: "直接调用软件现有辅助控制。action=开启指令显示/关闭指令显示/开启变量监视/关闭变量监视/关闭菜单/打开界面窗口/关闭界面窗口。涉及宏触发、退出重载或锁定输入的控制不能用于直接操作任务。操作后检查实际界面。", fields: "action", required: "action"}
        catalog["变量监视"] := {source: "变量监视", help: "读取实际全局变量和数组。names可选名称数组，传入时更新本次AI监视名单；空数组监视全部。返回值、变化和是否截断。open=true同时打开软件原变量监视窗口。不会修改变量。", fields: "names,open", required: ""}
        catalog["执行记录"] := {source: "直接执行反馈", help: "读取最近直接指令的结果和变量快照，最多30条；limit=1~30默认10。失败后的部分结果也可通过变量监视读取。", fields: "limit", required: ""}
        catalog["调试状态"] := {source: "断点调试器", help: "读取已打开的现有指令、节点ID、断点、当前位置、局部变量和调用栈；返回editor_token。target=side（默认侧栏）/editor（独立指令编辑器）。仅查看，不创建宏。", fields: "target", required: ""}
        catalog["调试操作"] := {source: "断点调试器", help: "仅调试用户已打开的现有指令。必须先调试状态；target与状态一致，editor_token须匹配，编辑器切换或内容改变会拒绝。action=breakpoint_on/breakpoint_off/step_into/step_over/continue/step_out/run_to_node/stop；断点及run_to_node需原样传node_id。继续/步出/运行到节点最多100步/30秒。检查当前位置、target_reached及变量后决定后续，不得为桌面任务生成宏。", fields: "target,editor_token,action,node_id", required: "editor_token,action"}
    }

    static Value(value, depth := 0) {
        if (value == JSON.true || value == JSON.false || value == JSON.null)
            return value
        if (depth >= 4)
            return "[嵌套内容已截断]"
        if (Type(value) == "Array") {
            result := []
            loop Min(value.Length, 100)
                result.Push(this.Value(value[A_Index], depth + 1))
            if (value.Length > 100)
                result.Push("[后续项已截断，共" value.Length "项]")
            return result
        }
        if (Type(value) == "Map") {
            result := Map()
            for key, child in value {
                result[key] := this.Value(child, depth + 1)
                if (result.Count >= 100)
                    break
            }
            return result
        }
        if (IsObject(value))
            return "[" Type(value) "]"
        return Type(value) == "String" && StrLen(value) > 12000 ? SubStr(value, 1, 12000) "[已截断]" : value
    }

    static Variables(p) {
        names := p.Get("names", [])
        if (Type(names) != "Array")
            throw Error("names 必须是变量名数组。")
        result := Map("variables", Map(), "arrays", Map(), "truncated", JSON.false, "warnings", [])
        for pair in [["variables", MySoftData.VariableMap], ["arrays", MySoftData.ArrayMap]] {
            entries := Map()
            try {
                for key, value in pair[2]
                    entries[key] := value
            } catch as e {
                result["truncated"] := JSON.true
                result["warnings"].Push("共享变量枚举不可用：" e.Message "；仅返回指定名称，请诊断环境并修复共享变量插件。")
                for key in names {
                    if (pair[2].Has(key))
                        entries[key] := pair[2][key]
                }
            }
            for key, value in entries {
                include := !names.Length
                for name in names {
                    if (key == name)
                        include := true
                }
                if (!include)
                    continue
                if (result[pair[1]].Count >= 200) {
                    result["truncated"] := JSON.true
                    break
                }
                result[pair[1]][key] := this.Value(value)
            }
        }
        return result
    }

    static Record(name, p, result) {
        if (this.IsCommand(name) && name != "RMT指令")
            return
        ; 不保留API密钥、请求头、输入正文或参数副本。
        this.history.Push(Map("sequence", AiDirectControl.sequence, "command", name, "result", this.Value(result)))
        if (this.history.Length > 30)
            this.history.RemoveAt(1)
    }

    static Execute(name, p, item) {
        switch name {
            case "RMT指令":
                action := p["action"]
                valid := false
                for choice in ["开启指令显示","关闭指令显示","开启变量监视","关闭变量监视","关闭菜单","打开界面窗口","关闭界面窗口"] {
                    if (action == choice)
                        valid := true
                }
                if (!valid)
                    throw Error("action 必须为list_instructions列出的软件辅助操作。")
                MyExcuteRMTCMDAction("RMT指令⫶调试⫶" action)
                return Map("executed",JSON.true,"verified",JSON.false,"action",action,"guidance","请检查辅助窗口的实际状态。")
            case "变量监视":
                if (p.Has("names")) {
                    if (Type(p["names"]) != "Array" || p["names"].Length > 100)
                        throw Error("names 必须是最多100个名称的数组。")
                    for value in p["names"] {
                        if (Type(value) != "String")
                            throw Error("names 必须只包含字符串。")
                    }
                    this.watches := p["names"].Clone()
                }
                current := this.Variables(Map("names", this.watches))
                changes := Map()
                for group in ["variables", "arrays"] {
                    for key, value in current[group] {
                        id := group ":" key
                        serialized := JSON.stringify([value], 0)
                        if (!this.previous.Has(id) || this.previous[id] != serialized)
                            changes[id] := value
                    }
                }
                next := Map()
                for group in ["variables", "arrays"] {
                    for key, value in current[group]
                        next[group ":" key] := JSON.stringify([value], 0)
                }
                for id in this.previous {
                    if (!next.Has(id))
                        changes[id] := Map("deleted_or_unwatched", JSON.true)
                }
                this.previous := next
                current["changes"] := changes
                current["watch_names"] := this.watches
                if (p.Get("open", false))
                    MyVarListenGui.ShowGui()
                return current
            case "执行记录":
                limit := AiDirectControl.Int(p, "limit", 10, 1, 30)
                records := []
                loop Min(limit, this.history.Length)
                    records.InsertAt(1, this.history[this.history.Length - A_Index + 1])
                return Map("records", records)
            case "调试状态", "调试操作":
                ed := ""
                target := p.Get("target", "side")
                if (target == "side") {
                    try ed := MyMainWin._sideTree.ActiveEditor()
                } else if (target == "editor") {
                    try {
                        if (!MyMacroGui._closed && IsObject(MyMacroGui.Gui))
                            ed := MyMacroGui
                    }
                } else
                    throw Error("target 必须是side或editor。")
                if (!IsObject(ed)) {
                    if (name == "调试操作")
                        throw Error("没有活动的现有指令编辑器；请先打开待调试的条目。")
                    return Map("available", JSON.false, "guidance", "请先在侧栏打开需要调试的现有条目；直接桌面操作仍使用execute_instruction。")
                }
                state := this.State(ed)
                if (name == "调试状态")
                    return state
                if (p["editor_token"] != state["editor_token"])
                    throw Error("编辑器或指令内容已改变，请重新读取调试状态。")
                action := p["action"]
                node := ""
                if (action == "breakpoint_on" || action == "breakpoint_off" || action == "run_to_node") {
                    node := p.Get("node_id", "")
                    if ((Type(node) != "String" && Type(node) != "Integer") || StrLen(String(node)) > 128 || node == "")
                        throw Error("node_id 必须来自调试状态返回的节点。")
                    found := false
                    for row in state["nodes"] {
                        if (row["node_id"] == node)
                            found := true
                    }
                    if (!found)
                        throw Error("节点不属于当前编辑器，请重新读取调试状态。")
                }
                if (action == "breakpoint_on" || action == "breakpoint_off") {
                    ed.MacroTreeViewCon.SetBreakPoint(node, action == "breakpoint_on")
                    ed._NotifyBpChanged()
                } else if (action == "stop") {
                    scratch := MySoftData.SpecialTableItem
                    if (scratch.Items.Length) {
                        scratch.Items[1].Killed := true
                        ReleaseTableItemHoldKeys(scratch, 1)
                    }
                    ed.ResetDebugState()
                } else {
                    if (action != "step_into" && action != "step_over" && action != "continue" && action != "step_out" && action != "run_to_node")
                        throw Error("未知调试action。")
                    depth := ed.DebugStack.Length
                    deadline := A_TickCount + 30000
                    steps := 0
                    scratch := MySoftData.SpecialTableItem
                    if (!scratch.Items.Length) {
                        debugItem := MacroItem()
                        debugItem.ID := "ai-debug-scratch"
                        scratch.Items.Push(debugItem)
                        scratch.RebuildIndex()
                    }
                    if (scratch.Items[1].ColorState != 0)
                        throw Error("调试器仍在运行，请等待停止后重新查询。")
                    scope := {token: "AI-debug-context", data: "", messages: [], cancelItem: scratch.Items[1]}
                    DirectCommandScope(scope)
                    expired := false
                    watchdog := () => (expired := true, item.Killed := true, scope.cancelItem.Killed := true)
                    SetTimer(watchdog, -30000)
                    try {
                      loop {
                        AiDirectControl.Check(item)
                        if (action == "run_to_node") {
                            if (!ed.DebugItemID) {
                                startNode := ed.FindDebugStartItem()
                                ed._Goto(startNode ? startNode : ed.MacroTreeViewCon.GetNext(0))
                            }
                            if (ed.DebugItemID == node)
                                break
                        }
                        if (MySoftData.SpecialTableItem.Items[1].ColorState != 0)
                            throw Error("调试器仍在运行，请等待停止后重新查询。")
                        if (action == "step_over")
                            ed.StepOver()
                        else
                            ed.StepInto()
                        if (scope.messages.Length)
                            throw Error(scope.messages[1]["message"])
                        if (expired)
                            throw Error("调试执行超时，已停止当前步骤。")
                        AiDirectControl.Check(item)
                        if (scratch.Items[1].Killed)
                            throw Error("当前调试指令失败或已终止；请检查变量及原指令参数。")
                        steps += 1
                        if (action == "step_into" || action == "step_over" || !ed.DebugItemID)
                            break
                        if (ed.MacroTreeViewCon.IsBreakPoint(ed.DebugItemID))
                            break
                        if (action == "run_to_node" && ed.DebugItemID == node)
                            break
                        if (action == "step_out" && ed.DebugStack.Length < depth)
                            break
                        if (steps >= 100 || A_TickCount >= deadline)
                            break
                      }
                    } catch as e {
                        scratch.Items[1].Killed := true
                        try ReleaseTableItemHoldKeys(scratch, 1)
                        ed.ResetDebugState()
                        throw e
                    } finally {
                        SetTimer(watchdog, 0)
                        DirectCommandScope("")
                    }
                    state := this.State(ed)
                    state["steps"] := steps
                    if (action == "run_to_node")
                        state["target_reached"] := ed.DebugItemID == node ? JSON.true : JSON.false
                    state["budget_reached"] := steps >= 100 || A_TickCount >= deadline ? JSON.true : JSON.false
                    state["variables"] := this.Variables(Map("names", this.watches))
                    return state
                }
                return this.State(ed)
        }
    }

    static State(ed) {
        nodes := []
        this.Nodes(ed, 0, nodes, 0)
        binding := ed.HasOwnProp("WindowBindingContext") ? ed.WindowBindingContext : ""
        text := JSON.stringify([nodes, binding], 0)
        bytes := Buffer(StrPut(text, "UTF-8"))
        length := StrPut(text, bytes, "UTF-8") - 1
        revision := DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", bytes, "UInt", length, "UInt")
        current := ed.DebugItemID
        frames := []
        for frame in ed.DebugStack {
            fields := Map()
            for key, value in frame.OwnProps()
                fields[key] := this.Value(value)
            frames.Push(fields)
        }
        locals := Map()
        if (MySoftData.SpecialTableItem.Items.Length)
            locals := this.Value(MySoftData.SpecialTableItem.Items[1].VariableMap)
        return Map("available", JSON.true, "editor_token", ObjPtr(ed) ":" revision, "current_node", current,
            "current_command", current ? ed._RawText(current) : "", "stack_depth", ed.DebugStack.Length,
            "stack", frames, "local_variables", locals,
            "breakpoints", ed.GetTreeBreakpoints(), "nodes", nodes, "truncated", nodes.Length >= 200 ? JSON.true : JSON.false)
    }

    static Nodes(ed, parent, nodes, depth) {
        if (depth >= 30 || nodes.Length >= 200)
            return
        child := ed.MacroTreeViewCon.GetChild(parent)
        while (child && nodes.Length < 200) {
            nodes.Push(Map("node_id", child, "parent_id", parent, "command", ed._RawText(child),
                "breakpoint", ed.MacroTreeViewCon.IsBreakPoint(child) ? JSON.true : JSON.false))
            this.Nodes(ed, child, nodes, depth + 1)
            child := ed.MacroTreeViewCon.GetNext(child)
        }
    }
}
