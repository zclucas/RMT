#Requires AutoHotkey v2.0

class AiMacroValidation {
    __New() {
        this.issues := []
        this.errors := 0
        this.warnings := 0
        this.checked := 0
        this.incomplete := false
        this.macroStack := Map()
        this.configStack := Map()
        this.graphNodes := Map()
        this.graphStack := Map()
    }

    static Run(args) {
        return JSON.stringify(AiMacroValidation.Check(args), 0)
    }

    static Check(args) {
        if (Integer(args.Get("tab", 0)) < 1)
            throw Error(GetLang("页签不存在"))
        table := AiAssist._ResolveTable(args["tab"])
        idx := Integer(args.Get("index", 0))
        if (idx < 1 || idx > table.Items.Length)
            throw Error(GetLang("宏序号不存在"))
        item := table.Items[idx]
        if (args.Has("item_id") && args["item_id"] !== item.ID)
            throw Error("目标宏已变化，请重新读取")
        check := AiMacroValidation()
        if (Trim(item.Macro) == "" && Trim(item.PreMacro) == "" && Trim(item.PostMacro) == "")
            check.Issue("warning", "empty_macro", "macro", "此宏没有指令")
        check.Macro(table, idx, "macro", 0)
        return Map("ok", JSON.true, "valid", check.errors = 0 ? JSON.true : JSON.false,
            "complete", check.incomplete ? JSON.false : JSON.true,
            "tab", table.Index, "index", idx, "item_id", item.ID, "checked_steps", check.checked,
            "error_count", check.errors, "warning_count", check.warnings, "issues", check.issues)
    }

    static FormatReport(result) {
        msg := Format(GetLang("已检查 {1} 步，{2} 个错误，{3} 个警告。"), result["checked_steps"],
            result["error_count"], result["warning_count"])
        if (result["complete"] == JSON.false || !result["complete"])
            msg .= "`n" GetLang("部分步骤尚未检查。")
        for issue in result["issues"]
            msg .= "`n`n[" GetLang(issue["severity"] = "error" ? "错误" : "警告") "] "
                . issue["location"] "`n" issue["message"]
        if (result["error_count"] + result["warning_count"] > result["issues"].Length)
            msg .= "`n`n" GetLang("仅显示前 60 条诊断。")
        return msg
    }

    Issue(severity, code, location, message) {
        if (severity == "error")
            this.errors++
        else
            this.warnings++
        if (this.issues.Length < 60)
            this.issues.Push(Map("severity", severity, "code", code, "location", location, "message", message))
    }

    Macro(table, idx, location, depth, includeHooks := true) {
        item := table.Items[idx]
        key := table.ID "|" item.ID
        if (this.macroStack.Has(key)) {
            this.Issue("error", "macro_cycle", location, "宏调用形成循环：" item.ID)
            return
        }
        this.macroStack[key] := true
        try {
            if (includeHooks)
                this.Text(table, idx, item.PreMacro, location "/pre", depth)
            this.Text(table, idx, item.Macro, location "/body", depth)
            if (includeHooks)
                this.Text(table, idx, item.PostMacro, location "/post", depth)
        } finally {
            this.macroStack.Delete(key)
        }
    }

    Text(table, idx, text, location, depth) {
        for i, command in SplitMacro(text) {
            if (this.checked >= 2000) {
                this.Limit(location)
                break
            }
            this.Command(table, idx, command, location "/" i, depth)
        }
    }

    Limit(location) {
        if (!this.incomplete)
            this.Issue("warning", "check_limit", location, "已达到静态检查上限，部分步骤尚未检查")
        this.incomplete := true
    }

    Command(table, idx, command, location, depth, graphNode := false) {
        if (depth > 40 || this.checked >= 2000) {
            this.Limit(location)
            return
        }
        this.checked++
        if (SubStr(CmdStripCurPos(command), 1, 2) == "🚫")
            return
        info := AiMacroEdit.ParseCommand(command)
        if (graphNode && (info.kind != "图形节点" || info.number == "")) {
            this.Issue("error", "graph_node_reference", location, "图形连线没有指向有效节点：" command)
            return
        }
        if (!(graphNode && info.kind == "图形节点") && !MacroCommandActions().Has(info.kind)) {
            this.Issue("error", "unknown_command", location, "无法识别指令：" info.serial)
            return
        }
        if (info.number == "" || !MySoftData.DataFileMap.Has(info.kind)) {
            this.Inline(info, location)
            return
        }
        try record := AiMacroEdit.ReadData(info)
        catch as e {
            this.Issue("error", "command_config", location, e.Message)
            return
        }
        key := record.file "|" info.kind info.number
        if (graphNode) {
            graphKey := table.ID "|" idx "|" key
            if (this.graphStack.Has(graphKey)) {
                this.Issue("error", "graph_cycle", location, "图形连线形成循环：" info.serial)
                return
            }
            if (this.graphNodes.Has(graphKey))
                return
            this.graphNodes[graphKey] := true
            this.graphStack[graphKey] := true
        } else if (this.configStack.Has(key)) {
            this.Issue("error", "branch_cycle", location, "指令分支形成循环：" info.serial)
            return
        }

        data := record.data
        try {
            AiMacroEdit.CheckParams(info.kind, data)
            if (info.kind == "间隔") {
                isRandom := CmdEnumZh(data.Get("Type", ""), CmdEnumIntervalNames()) == "随机"
                this.CheckInterval(data.Get("Time1", ""), isRandom ? data.Get("Time2", "") : unset)
            }
            if (AiMacroEdit.IsSearch(info.kind)) {
                targets := data.Get("SearchTargetArr", [])
                if (info.kind == "搜索All" || Type(targets) != "Array" || !targets.Length)
                    targets := [data]
                for i, target in targets {
                    AiMacroEdit.CheckRange(target)
                    this.CheckImage(target, location "/target/" i)
                }
            }
        } catch as e {
            this.Issue("error", "invalid_parameters", location, e.Message)
        }

        if (!graphNode)
            this.configStack[key] := true
        try {
            if (info.kind == "宏操作")
                this.CallMacro(table, idx, data, location, depth)
            for field in ["TrueMacro", "FalseMacro", "LoopBody", "DefaultMacro", "SubMacro", "CurCMD",
                "MacroArr", "TrueMacroArr", "FalseMacroArr", "StartMacroArr", "EndMacroArr"] {
                value := data.Get(field, "")
                if (Type(value) == "String" && value != "")
                    this.Text(table, idx, value, location "/" field, depth + 1)
                else if (Type(value) == "Array") {
                    for i, branch in value {
                        if (Type(branch) == "String")
                            this.Text(table, idx, branch, location "/" field "/" i, depth + 1)
                    }
                }
            }
            graphField := info.kind == "图形开始节点" ? "NodeArr" : info.kind == "图形节点" ? "NextNodeArr" : ""
            if (graphField != "") {
                nodes := data.Get(graphField, [])
                if (Type(nodes) != "Array")
                    this.Issue("error", "graph_nodes", location, "图形节点引用格式错误")
                else {
                    for i, node in nodes {
                        if (Type(node) == "String" && node != "")
                            this.Command(table, idx, node, location "/" graphField "/" i, depth + 1, true)
                        else
                            this.Issue("error", "graph_node_reference", location "/" graphField "/" i, "图形连线缺少目标节点")
                    }
                }
            }
        } finally {
            if (graphNode)
                this.graphStack.Delete(graphKey)
            else
                this.configStack.Delete(key)
        }
    }

    Inline(info, location) {
        static minimum := Map("间隔", 2, "按键", 3, "手柄", 3, "移动", 3, "鼠标移动", 3,
            "变量", 3, "RMT指令", 2, "流程跳转", 2, "注释", 1)
        if (!minimum.Has(info.kind)) {
            this.Issue("error", "missing_serial", location, "指令需要配置序列号：" info.kind)
            return
        }
        parts := SplitCommand(info.clean)
        if (parts.Length < minimum[info.kind])
            this.Issue("error", "inline_fields", location, "旧格式指令缺少参数：" info.kind)
        else if (info.kind == "间隔") {
            values := StrSplit(parts[2], "~")
            try {
                if (values.Length > 2)
                    throw Error("间隔随机范围格式错误")
                this.CheckInterval(values[1], values.Length = 2 ? values[2] : unset)
            } catch as e
                this.Issue("error", "invalid_parameters", location, e.Message)
        }
        else if (info.kind == "流程跳转") {
            try FlowJumpAction(info.clean)
            catch as e
                this.Issue("error", "inline_fields", location, e.Message)
        }
    }

    CheckInterval(first, second?) {
        if (Trim(String(first)) == "" || (IsNumber(first) && first < 0)
            || (IsSet(second) && (Trim(String(second)) == "" || (IsNumber(second) && second < 0)
                || (IsNumber(first) && IsNumber(second) && first > second))))
            throw Error("间隔时间不能为负数或空值，随机上限不能小于下限")
    }

    CheckImage(target, location) {
        type := CmdEnumSearch(target.Get("SearchType", ""))
        if (type != "屏幕图片" && type != "窗口图片")
            return
        path := Trim(String(target.Get("SearchImagePath", "")))
        if (path == "") {
            this.Issue("error", "empty_image", location, "图片搜索没有指定图片")
            return
        }
        ; 动态变量、网络路径与虚拟图片不在静态检查范围内。
        if (SubStr(path, 1, 2) == "\\" || InStr(path, "{") || InStr(path, "://")
            || !RegExMatch(path, "i)\.(png|bmp|jpe?g|gif|webp|ico)$"))
            return
        if !FileExist(path)
            this.Issue("warning", "missing_image", location, "当前找不到搜索图片：" path)
    }

    CallMacro(table, idx, data, location, depth) {
        macroType := data.Get("MacroType", "")
        callType := data.Get("CallType", "")
        target := macroType == "当前宏" ? table : GetTableBySymbol(CompatMacroTypeSymbol(macroType))
        targetIndex := IsObject(target)
            ? (macroType == "当前宏" ? idx : GetItemIndexInTable(target, data.Get("MacroSerial", "")))
            : 0
        if (!targetIndex) {
            this.Issue("error", "missing_macro", location, "宏操作找不到目标宏")
            return
        }
        if (callType == "插入到当前宏" || callType == "触发")
            this.Macro(target, targetIndex, location "/" target.Items[targetIndex].ID, depth + 1, callType == "触发")
    }
}
