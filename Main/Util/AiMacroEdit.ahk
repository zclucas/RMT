#Requires AutoHotkey v2.0

class AiMacroEdit {
    static pending := ""
    static lastEdit := ""
    static sequence := 0

    static Tools() {
        return [
            AiAssist._ToolDef("preview_macro_step_edit", "预览指定步骤的参数修改。changes 使用 read_macro_step 里的字段名，只传要改的字段。", '[{"name":"tab","type":"integer","desc":"页签序号","req":true},{"name":"index","type":"integer","desc":"宏序号"},{"name":"item_id","type":"string","desc":"宏 ID","req":true},{"name":"command_index","type":"integer","desc":"步骤序号","req":true},{"name":"phase","type":"string","desc":"body、pre 或 post"},{"name":"expected_command","type":"string","desc":"步骤原文","req":true},{"name":"target_index","type":"integer","desc":"搜索目标序号，多目标时修改目标参数必填"},{"name":"row_index","type":"integer","desc":"变量行或等待条件行，从 1 开始"},{"name":"changes","type":"object","desc":"搜索：Similar、SearchText、SearchColor、SearchImagePath、StartPosX/Y、EndPosX/Y、SearchCount、SearchInterval。变量：VariableArr、CopyVariableArr、MinVariableArr、MaxVariableArr、OperaTypeArr，值写单行标量。等待：TimeoutMs、Interval、ResultSaveName、Param1、Param2、DurationMs、RandomMaxMs、ConditionValue。","req":true}]'),
            AiAssist._ToolDef("apply_macro_step_edit", "显示预览差异，用户确认后应用该预览。", '[{"name":"preview_id","type":"integer","desc":"preview_macro_step_edit 返回的编号","req":true}]'),
            AiAssist._ToolDef("undo_macro_step_edit", "确认后撤销当前配置中本次启动以来最近一次结构化参数修改。", "[]")
        ]
    }

    ; 与执行器相同，使用第一个下划线前的序列号。保留指令原文供精确替换。
    static ParseCommand(command) {
        clean := GetCmdStr(RMTParseErrHandle(CmdStripCurPos(command)).cmd)
        serial := StrSplit(clean, "_", , 2)[1]
        kind := GetLangKey(RTrim(serial, "0123456789"))
        number := SubStr(serial, StrLen(RTrim(serial, "0123456789")) + 1)
        return {clean: clean, serial: serial, kind: kind, number: number}
    }

    static ReadData(info) {
        file := MySoftData.DataFileMap.Get(info.kind, "")
        if (file == "" || info.number == "")
            throw Error("指令缺少配置序列号：" info.serial)
        canonical := info.kind info.number
        raw := CfgRead(file, SettingSection, canonical, "")
        if (raw == "" && canonical != info.serial)
            raw := CfgRead(file, SettingSection, info.serial, "")
        if (raw == "")
            throw Error("缺少指令配置：" info.serial)
        if (SubStr(LTrim(raw), 1, 1) != "{")
            throw Error("指令配置不是 JSON 对象：" info.serial)
        return {file: file, raw: raw, data: JSON.parse(raw, true)}
    }

    static IsSearch(kind) {
        return InStr("|搜索|搜索Pro|搜索All|搜索Combo|组合搜索|搜索Multi|", "|" kind "|", true) > 0
    }

    static RequireWrite() {
        if (!AiAssist.CanWrite())
            throw Error(GetLang("当前为只读，无法修改"))
    }

    static Preview(args) {
        AiMacroEdit.RequireWrite()
        AiMacroEdit.pending := ""
        if (Integer(args.Get("tab", 0)) < 1)
            throw Error(GetLang("页签不存在"))
        step := AiAssist._ResolveMacroStep(args)
        if (step.item.ID == "" || args.Get("item_id", "") !== step.item.ID
            || args.Get("expected_command", "") !== step.command)
            throw Error("宏或步骤已变化，请重新读取该步骤")
        info := AiMacroEdit.ParseCommand(step.command)
        AiMacroEdit.CheckPanelBinding(step, info)
        record := AiMacroEdit.ReadData(info)
        changes := args.Get("changes", "")
        if (Type(changes) != "Map" || changes.Count < 1 || changes.Count > 12)
            throw Error("changes 必须是包含 1 至 12 个字段的对象")
        diff := AiMacroEdit.Patch(info.kind, record.data, changes, args)
        if (!diff.Length)
            return JSON.stringify(Map("ok", JSON.true, "changed", JSON.false), 0)

        AiMacroEdit.sequence += 1
        field := step.field
        AiMacroEdit.pending := {id: AiMacroEdit.sequence, config: MySoftData.CurSettingName,
            step: step, originalText: step.item.%field%, info: info,
            file: record.file, raw: record.raw, data: record.data, diff: diff}
        return JSON.stringify(Map("ok", JSON.true, "changed", JSON.true, "preview_id", AiMacroEdit.sequence,
            "tab", step.table.Index, "index", step.index, "phase", step.phase,
            "command_index", step.number, "command_type", info.kind, "changes", diff), 0)
    }

    static Patch(kind, data, changes, args) {
        diff := []
        target := data
        prefix := ""
        if (AiMacroEdit.IsSearch(kind)) {
            targets := data.Get("SearchTargetArr", [])
            if (kind != "搜索All" && Type(targets) == "Array" && targets.Length) {
                targetIndex := Integer(args.Get("target_index", targets.Length = 1 ? 1 : 0))
                if (targetIndex > 0 && targetIndex <= targets.Length) {
                    target := targets[targetIndex]
                    prefix := "目标 " targetIndex " / "
                } else
                    target := ""
            } else if (Integer(args.Get("target_index", 1)) != 1)
                throw Error("此指令只有一个搜索目标")
        }
        row := Integer(args.Get("row_index", 1))
        for field, value in changes {
            if (IsObject(value) || StrLen(String(value)) > 512)
                throw Error("参数必须是最多 512 字符的标量：" field)
            if (AiMacroEdit.IsSearch(kind)) {
                if (field = "SearchCount") {
                    value := AiMacroEdit.Int(value, -1, 2147483647, field)
                    if (value = 0)
                        throw Error("SearchCount 必须大于零或为 -1（无限）")
                    AiMacroEdit.Set(data, field, value, diff)
                } else if (field = "SearchInterval")
                    AiMacroEdit.Set(data, field, AiMacroEdit.Int(value, 0, 2147483647, field), diff)
                else {
                    if (Type(target) != "Map")
                        throw Error("请用 target_index 指定已有的搜索目标")
                    switch field {
                        case "Similar": value := AiMacroEdit.Int(value, 0, 100, field)
                        case "SearchColor":
                            value := String(value)
                            if (!RegExMatch(value, "i)^(?:0x|#)?[0-9a-f]{6}$"))
                                throw Error("SearchColor 需要六位 RGB 十六进制值")
                            value := StrUpper(RegExReplace(value, "i)^(?:0x|#)", ""))
                        case "SearchText", "SearchImagePath":
                            value := Trim(String(value))
                            if (value == "")
                                throw Error(field " 不能为空")
                        case "StartPosX", "StartPosY", "EndPosX", "EndPosY":
                            value := AiMacroEdit.NumberOrVariable(value, field)
                        default: throw Error("搜索指令不支持修改字段：" field)
                    }
                    AiMacroEdit.Set(target, field, value, diff, prefix)
                }
            } else if (kind == "变量") {
                if (!InStr("|VariableArr|CopyVariableArr|MinVariableArr|MaxVariableArr|OperaTypeArr|", "|" field "|", true))
                    throw Error("变量指令不支持修改字段：" field)
                values := data.Get(field, [])
                if (Type(values) != "Array" || row < 1 || row > values.Length)
                    throw Error("变量行不存在：" row)
                switch field {
                    case "VariableArr": value := AiMacroEdit.VarName(value, field)
                    case "OperaTypeArr":
                        value := GetLangKey(String(value))
                        if (!InStr("|数值|随机数值|字符|系统|时间|删除|", "|" value "|", true))
                            throw Error("未知的变量操作：" value)
                    case "MinVariableArr", "MaxVariableArr": value := AiMacroEdit.NumberOrVariable(value, field)
                    default: value := String(value)
                }
                AiMacroEdit.Set(values, row, value, diff, field " / 行 ")
            } else if (kind == "等待")
                AiMacroEdit.PatchWait(data, field, value, row, diff)
            else
                throw Error("当前支持搜索、变量、等待指令的参数编辑")
        }
        AiMacroEdit.CheckParams(kind, data, target, row)
        return diff
    }

    static PatchWait(data, field, value, row, diff) {
        waitType := CmdEnumWait(data.Get("WaitType", "等待变量值"))
        switch field {
            case "TimeoutMs", "Interval":
                AiMacroEdit.Set(data, field, AiMacroEdit.Int(value, field = "Interval" ? 1 : 0, 4294967295, field), diff)
            case "ResultSaveName":
                AiMacroEdit.Set(data, field, value == "" ? "" : AiMacroEdit.VarName(value, field), diff)
            case "DurationMs", "RandomMaxMs":
                time := data.Get("TimeConfig", "")
                unit := Type(time) == "Map" ? TimeNormWaitType(time.Get("Param2", "")) : ""
                if (waitType != "等待时间" || (unit != "毫秒" && unit != "毫秒-随机")
                    || (field == "RandomMaxMs" && unit != "毫秒-随机"))
                    throw Error("此等待模式不支持修改 " field)
                key := field == "DurationMs" ? "Param1" : field
                AiMacroEdit.Set(time, key, AiMacroEdit.NumberOrVariable(value, field, true), diff, "TimeConfig.")
            case "ConditionValue":
                conditions := data.Get("Conditions", [])
                if (waitType != "等待变量值" || Type(conditions) != "Array" || row < 1 || row > conditions.Length)
                    throw Error("等待条件行不存在：" row)
                AiMacroEdit.Set(conditions[row], "Value", String(value), diff, "条件 " row " / ")
            case "Param1", "Param2":
                conditions := data.Get("Conditions", [])
                if (waitType == "等待时间" || waitType == "等待时间区间" || waitType == "等待确定"
                    || (waitType == "等待变量值" && Type(conditions) == "Array" && conditions.Length))
                    throw Error("请修改该等待模式的专用参数")
                AiMacroEdit.Set(data, field, String(value), diff)
            default: throw Error("等待指令不支持修改字段：" field)
        }
    }

    static Set(container, key, value, diff, prefix := "") {
        old := Type(container) == "Map" ? container.Get(key, JSON.null) : container[key]
        if (JSON.stringify([old], 0) == JSON.stringify([value], 0))
            return
        diff.Push(Map("field", prefix key, "before", old, "after", value))
        container[key] := value
    }

    static Int(value, min, max, field) {
        if (!RegExMatch(String(value), "^-?\d+$") || !IsNumber(value) || value < min || value > max)
            throw Error(field " 必须是 " min " 至 " max " 的整数")
        return Integer(value)
    }

    static VarName(value, field) {
        value := Trim(String(value))
        if (value == "" || IsNumber(value) || RegExMatch(value, "[_\r\n]"))
            throw Error(field " 需要有效的变量名")
        return value
    }

    static NumberOrVariable(value, field, milliseconds := false) {
        if (IsNumber(value))
            return milliseconds ? AiMacroEdit.Int(value, 0, 4294967295, field) : value
        return AiMacroEdit.VarName(value, field)
    }

    static CheckParams(kind, data, target := "", row := 0) {
        if (AiMacroEdit.IsSearch(kind)) {
            if (data.Has("SearchCount") && IsNumber(data["SearchCount"]) && data["SearchCount"] <= 0 && data["SearchCount"] != -1)
                throw Error("搜索次数必须大于零或为无限")
            if (Type(target) == "Map")
                AiMacroEdit.CheckRange(target)
        } else if (kind == "变量") {
            toggles := data.Get("ToggleArr", [])
            fields := ["VariableArr", "OperaTypeArr", "CopyVariableArr", "MinVariableArr", "MaxVariableArr"]
            if (Type(toggles) != "Array" || !toggles.Length)
                throw Error("变量指令缺少变量行")
            for field in fields {
                values := data.Get(field, "")
                if (Type(values) != "Array" || values.Length != toggles.Length)
                    throw Error("变量配置行数不一致：" field)
            }
            for i, op in data["OperaTypeArr"] {
                if (row && row != i)
                    continue
                if (CmdEnumOpera(op) != "随机数值")
                    continue
                min := data["MinVariableArr"][i]
                max := data["MaxVariableArr"][i]
                if (IsNumber(min) && IsNumber(max) && Number(min) > Number(max))
                    throw Error("变量随机范围的最小值大于最大值，行 " i)
            }
        } else if (kind == "等待") {
            if (data.Has("TimeoutMs"))
                AiMacroEdit.Int(data["TimeoutMs"], 0, 4294967295, "TimeoutMs")
            time := data.Get("TimeConfig", "")
            if (CmdEnumWait(data.Get("WaitType", "等待变量值")) == "等待时间" && Type(time) == "Map") {
                unit := TimeNormWaitType(time.Get("Param2", ""))
                if (unit == "毫秒" || unit == "毫秒-随机") {
                    min := AiMacroEdit.NumberOrVariable(time.Get("Param1", ""), "DurationMs", true)
                    if (unit == "毫秒-随机") {
                        max := AiMacroEdit.NumberOrVariable(time.Get("RandomMaxMs", ""), "RandomMaxMs", true)
                        if (IsNumber(min) && IsNumber(max) && Number(min) >= Number(max))
                            throw Error("随机等待上限必须大于下限")
                    }
                }
            }
        }
    }

    static CheckRange(data) {
        for axis in ["X", "Y"] {
            start := data.Get("StartPos" axis, "")
            end := data.Get("EndPos" axis, "")
            if (IsNumber(start) && IsNumber(end) && Number(start) >= Number(end))
                throw Error("搜索范围终点必须大于起点：" axis)
        }
    }

    static CheckPanelBinding(step, info) {
        ; 自定义面板也能绑定按键宏、定时宏等其他页签的正文。
        if (step.phase != "body")
            return
        for key in UIMacroStepBinding.OccupiedMap() {
            if (InStr(key, step.item.ID "|") != 1)
                continue
            if (InStr(key, "|data|" info.kind "|" info.kind info.number "|")
                || InStr(key, "|data|" info.kind "|" info.serial "|")
                || InStr(key, "|h" step.number ":" info.serial ":")
                || InStr(key, "|h" step.number ":" info.kind info.number ":"))
                throw Error("此步骤已有界面面板绑定，请在指令编辑器中修改")
        }
    }

    static Current(edit, expected) {
        AiMacroEdit.RequireWrite()
        if (MySoftData.CurSettingName !== edit.config)
            throw Error("当前配置已切换")
        step := edit.step
        table := AiAssist._ResolveTable(step.table.Index)
        idx := GetItemIndexInTable(table, step.item.ID)
        if (table != step.table || idx < 1 || table.Items[idx] != step.item)
            throw Error("目标宏已变化")
        field := step.field
        if (UIMacroStepBinding.GetStep(step.item.%field%, step.number) !== expected)
            throw Error("目标步骤已变化，请重新读取")
        return idx
    }

    static DiffText(edit, undo := false) {
        phase := Map("body", "正文", "pre", "前置钩子", "post", "后置钩子")[edit.step.phase]
        text := Format("第 {1} 页第 {2} 条宏 · {3}第 {4} 步", edit.step.table.Index,
            GetItemIndexInTable(edit.step.table, edit.step.item.ID), phase, edit.step.number)
        for change in edit.diff {
            before := SubStr(JSON.stringify([change[undo ? "after" : "before"]], 0), 2, -1)
            after := SubStr(JSON.stringify([change[undo ? "before" : "after"]], 0), 2, -1)
            text .= "`n`n" change["field"] "`n" before " → " after
        }
        return text
    }

    static Apply(args) {
        edit := AiMacroEdit.pending
        if (!IsObject(edit) || Integer(args.Get("preview_id", 0)) != edit.id)
            throw Error("预览已失效，请重新预览")
        step := edit.step
        AiMacroEdit.Current(edit, step.command)
        if (!RmtDialog.Confirm(AiMacroEdit.DiffText(edit), "确认 AI 参数修改"))
            throw Error("用户取消参数修改")
        wasCritical := A_IsCritical
        Critical("On")
        try idx := AiMacroEdit.Commit(edit)
        finally Critical(wasCritical)
        AiAssist._RefreshMacroUi(step.table, idx)
        return JSON.stringify(Map("ok", JSON.true, "command", edit.newCommand, "serial", edit.serial), 0)
    }

    static Commit(edit) {
        global SerialMap
        if (AiMacroEdit.pending != edit)
            throw Error("预览已变化，请重新预览")
        step := edit.step
        info := edit.info
        idx := AiMacroEdit.Current(edit, step.command)
        field := step.field
        if (step.item.%field% !== edit.originalText)
            throw Error("宏指令顺序或内容已变化，请重新预览")
        AiMacroEdit.CheckPanelBinding(step, info)
        if (AiMacroEdit.ReadData(info).raw !== edit.raw)
            throw Error("原指令配置已变化，请重新预览")

        ; 按运行时序列分配规则保留编号，但不覆盖未使用的既有配置。
        if (!SerialMap.Has(info.kind))
            SerialMap[info.kind] := SerialData(info.kind)
        seq := SerialMap[info.kind]
        num := seq.CurNum
        while (seq.NumMap.Has(num) || CfgRead(edit.file, SettingSection, info.kind num, "") != "")
            num++
        serial := info.kind num
        seq.CurNum := num + 1
        seq.Refresh()

        pos := InStr(step.command, info.serial, true)
        if (!pos)
            throw Error("无法定位步骤序列号")
        cmd := SubStr(step.command, 1, pos - 1) serial SubStr(step.command, pos + StrLen(info.serial))
        fields := Map(field, UIMacroStepBinding.SetStepText(step.item.%field%, step.number, cmd))
        oldSig := BpSig(step.command)
        edit.copiedBreakpoint := BpStrHas(step.item.Breakpoints, oldSig)
        if (edit.copiedBreakpoint)
            fields["Breakpoints"] := "," Trim(step.item.Breakpoints, ",") "," serial ","

        edit.data["SerialStr"] := serial
        saved := JSON.stringify(edit.data, 0)
        AiMacroEdit.pending := ""
        try CfgWrite(saved, edit.file, SettingSection, serial)
        catch as e {
            CfgInvalidate(edit.file)
            throw e
        }
        try AiAssist._SaveMacroFields(step.table, step.item, fields)
        catch as e {
            try CfgDelete(edit.file, SettingSection, serial)
            catch
                CfgInvalidate(edit.file)
            throw e
        }
        edit.newCommand := cmd
        edit.serial := serial
        edit.saved := saved
        AiMacroEdit.lastEdit := edit
        return idx
    }

    static Undo() {
        edit := AiMacroEdit.lastEdit
        if (!IsObject(edit))
            throw Error("没有可撤销的参数修改")
        AiMacroEdit.Current(edit, edit.newCommand)
        if (!RmtDialog.Confirm(AiMacroEdit.DiffText(edit, true), "撤销 AI 参数修改"))
            throw Error("用户取消撤销")
        wasCritical := A_IsCritical
        Critical("On")
        try idx := AiMacroEdit.Restore(edit)
        finally Critical(wasCritical)
        AiAssist._RefreshMacroUi(edit.step.table, idx)
        return '{"ok":true,"undone":true}'
    }

    static Restore(edit) {
        if (AiMacroEdit.lastEdit != edit)
            throw Error("最近一次参数修改已变化")
        idx := AiMacroEdit.Current(edit, edit.newCommand)
        if (AiMacroEdit.ReadData(edit.info).raw !== edit.raw
            || CfgRead(edit.file, SettingSection, edit.serial, "") !== edit.saved)
            throw Error("指令配置已有其他改动，无法直接撤销")
        step := edit.step
        AiMacroEdit.CheckPanelBinding(step, AiMacroEdit.ParseCommand(edit.newCommand))
        field := step.field
        fields := Map(field, UIMacroStepBinding.SetStepText(step.item.%field%, step.number, step.command))
        if (edit.copiedBreakpoint) {
            bp := StrReplace(step.item.Breakpoints, "," edit.serial ",", ",")
            fields["Breakpoints"] := bp == "," ? "" : bp
        }
        AiAssist._SaveMacroFields(step.table, step.item, fields)
        AiMacroEdit.lastEdit := ""
        ; 新配置可能已被复制到别的步骤，撤销只恢复本步骤引用。
        return idx
    }
}

#Include AiMacroValidation.ahk
