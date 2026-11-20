#Requires AutoHotkey v2.0

class CompatCompareFlowMigration {
    __New(dir) {
        this.path := dir "\SubMacroFile.toml"
        this.root := Cfg_Load(this.path).Clone()
        section := IniImport_Section()
        this.values := this.root[section] := Cfg_Seg(this.root, section).Clone()
        this.next := 1
        this.dirty := false
        for serial in this.values {
            if (RegExMatch(serial, "i)^(?:宏操作|Ctrl)(\d+)$", &m))
                this.next := Max(this.next, Integer(m[1]) + 1)
        }
    }

    AddOperation(action) {
        ; 独立配置避免编辑某条跳转时改到其他位置。
        serial := "宏操作" this.next++
        data := SubMacroData()
        data.SerialStr := serial
        data.MacroType := "当前宏"
        data.CallType := action
        data.MacroSerial := ""
        data.BranchTail := true
        this.values[serial] := JSON.stringify(data, 0)
        this.dirty := true
        return serial
    }

    Save() {
        ; 先写入指令配置，再改写宏引用，保证中断后可重新升级。
        if (this.dirty) {
            Cfg_WriteRoot(this.root, this.path)
            this.dirty := false
        }
    }
}


Compat13_UpgradeCompareBranches(dir) {
    migration := CompatCompareFlowMigration(dir)
    journal := migration.root.Get("CompareFlowMigration", Map()).Clone()
    changed := false
    for stem in ["CompareFile", "CompareProFile"] {
        path := dir "\" stem ".toml"
        if (!FileExist(path))
            continue
        root := Cfg_Load(path, true).Clone()
        section := IniImport_Section()
        values := root[section] := Cfg_Seg(root, section).Clone()
        dirty := false
        for key, raw in values.Clone() {
            data := TryParseCommandData(raw)
            if (!IsObject(data))
                continue
            source := stem ":" key ":"
            if (stem == "CompareFile") {
                updated := Compat13_AppendBranchFlow(data, "TrueMacro", "TrueControlType", migration, journal, source "True")
                updated := Compat13_AppendBranchFlow(data, "FalseMacro", "FalseControlType", migration, journal, source "False") || updated
            } else {
                updated := Compat13_AppendBranchFlow(data, "DefaultMacro", "DefaultControlType", migration, journal, source "Default")
                if (data.HasOwnProp("ControlTypeArr") && data.ControlTypeArr is Array) {
                    if (!data.HasOwnProp("MacroArr") || !(data.MacroArr is Array))
                        data.MacroArr := []
                    count := data.HasOwnProp("VariNameArr") && data.VariNameArr is Array
                        ? Min(data.ControlTypeArr.Length, data.VariNameArr.Length) : data.ControlTypeArr.Length
                    loop count {
                        i := A_Index
                        if (!data.ControlTypeArr.Has(i))
                            continue
                        action := CompatFlowAction(data.ControlTypeArr[i])
                        if (action == "")
                            continue
                        while (data.MacroArr.Length < i)
                            data.MacroArr.Push("")
                        data.MacroArr[i] := Compat13_AppendOperation(
                            data.MacroArr.Has(i) ? data.MacroArr[i] : "", action, migration, journal, source i)
                        data.ControlTypeArr[i] := "无"
                        updated := true
                    }
                }
            }
            if (updated) {
                values[key] := JSON.stringify(data, 0)
                dirty := true
            }
        }
        if (dirty) {
            migration.root["CompareFlowMigration"] := journal
            migration.Save()
            Cfg_WriteRoot(root, path)
            changed := true
        }
    }
    if (migration.root.Has("CompareFlowMigration")) {
        migration.root.Delete("CompareFlowMigration")
        Cfg_WriteRoot(migration.root, migration.path)
    }
    return changed
}

Compat13_AppendBranchFlow(data, macroField, controlField, migration, journal, source) {
    if (!data.HasOwnProp(controlField))
        return false
    action := CompatFlowAction(data.%controlField%)
    if (action == "")
        return false
    macro := data.HasOwnProp(macroField) ? data.%macroField% : ""
    data.%macroField% := Compat13_AppendOperation(macro, action, migration, journal, source)
    data.%controlField% := "无"
    return true
}

Compat13_AppendOperation(macro, action, migration, journal, source) {
    serial := journal.Get(source, "")
    existing := TryParseCommandData(migration.values.Get(serial, ""))
    if (!IsObject(existing) || !existing.HasOwnProp("BranchTail") || !existing.BranchTail || existing.CallType != action) {
        serial := migration.AddOperation(action)
        journal[source] := serial
    }
    return AppendCompareBranchTail(macro, serial "_" CompatFlowRemark(action))
}

CompatFlowRemark(action) {
    switch action {
        case "循环-跳过本轮": return "循环-跳出本轮"
        case "分支-跳出": return "分支跳出"
        default: return action
    }
}

CompatFlowAction(value) {
    if (IsObject(value))
        return ""
    switch Trim(String(value)), false {
        case "2", "循环-跳过本轮", "循环-跳出本轮", "迴圈-跳過本輪", "迴圈-跳出本輪", "Loop-Continue":
            return "循环-跳过本轮"
        case "3", "循环-跳出", "迴圈-跳出", "Loop-Exit":
            return "循环-跳出"
        case "4", "分支-跳出", "分支跳出", "Branch-Exit":
            return "分支-跳出"
    }
    return ""
}
