#Requires AutoHotkey v2.0

; 旧条件裸名称按被升级配置的定义确定含义，不读取当前运行方案的变量表。
Compat13_UpgradeConditionOperands(dir) {
    vars := Map()
    for _, names in GetBuiltinVarGroups() {
        for name in names {
            vars[name] := true
            vars["❖" name] := true
        }
    }
    for old, name in LegacyRuntimeVarNames()
        vars[old] := true
    loop files, dir "\*.toml" {
        SplitPath(A_LoopFileFullPath, , , , &stem)
        for _, raw in CfgSection(A_LoopFileFullPath, IniImport_Section()) {
            data := TryParseCommandData(raw)
            if (IsObject(data))
                Compat13_CollectConditionVariables(data, stem, vars)
        }
    }
    changed := false
    for stem in ["CompareFile", "CompareProFile", "LoopFile"] {
        path := dir "\" stem ".toml"
        if (!FileExist(path))
            continue
        for serial, raw in CfgSection(path, IniImport_Section()) {
            data := TryParseCommandData(raw)
            if (!IsObject(data) || data.HasOwnProp("ConditionOperandsVersion"))
                continue
            for field in ["NameArr", "VariNameArr", "VariableArr"] {
                if (data.HasOwnProp(field) && data.%field% is Array)
                    Compat13_ConditionReferenceArray(data.%field%, vars)
            }
            ; 每条完成后写标记，写盘中断重试也不改写已经确定的字面文本。
            data.ConditionOperandsVersion := 1
            CfgWrite(JSON.stringify(data, 0), path, IniImport_Section(), serial)
            changed := true
        }
    }
    return changed
}

Compat13_ConditionReferenceArray(values, vars) {
    for i, value in values {
        if (value is Array)
            Compat13_ConditionReferenceArray(value, vars)
        else
            values[i] := Compat13_ConditionReference(value, vars)
    }
}

Compat13_ConditionReference(value, vars) {
    ; 数值保持数值，已有引用不能重复包裹。
    if (IsNumber(value))
        return value
    if (RegExMatch(value, "^\{[^{}\r\n]+\}$"))
        return TranslateBuiltinVarReferences(value)
    name := GetBuiltinVarName(value)
    return vars.Has(value) || vars.Has(name) ? "{" name "}" : value
}

Compat13_CollectConditionVariables(data, stem, vars) {
    if (!Compat13_Schemas().Has(stem))
        return
    if (stem == "VariableFile" || stem == "ExVariableFile" || stem == "OperationFile") {
        field := stem == "OperationFile" ? "UpdateNameArr" : "VariableArr"
        if (data.HasOwnProp(field) && data.%field% is Array) {
            for i, name in data.%field% {
                if (!data.HasOwnProp("ToggleArr") || (data.ToggleArr.Has(i) && data.ToggleArr[i]))
                    Compat13_AddConditionVariable(vars, name)
            }
        }
    }
    if (data.HasOwnProp("LegacyTextProcess"))
        Compat13_CollectConditionVariables(data.LegacyTextProcess, "VariableFile", vars)
    for field in ["SaveName", "SaveVar", "VarName", "ResultSaveName", "CoordXName", "CoordYName",
        "TimeoutStatusVar", "ResultVar", "ErrorVar", "ControlVar", "ValueVar", "StateVar", "ClassVar", "HwndVar",
        "XVar", "YVar", "WindowXVar", "WindowYVar", "WidthVar", "HeightVar", "CountVar", "NameVar",
        "PidVar", "PathVar", "ExistVar", "StatusVar", "StartTimeVar", "UptimeVar", "CpuVar", "GpuVar",
        "ResponseVar", "ConfVar", "RatioVar", "DepthVar"] {
        if (!data.HasOwnProp(field))
            continue
        if ((field == "SaveName" && data.HasOwnProp("SaveToggle") && !data.SaveToggle)
            || (field == "ResultSaveName" && data.HasOwnProp("ResultToggle") && !data.ResultToggle)
            || ((field == "CoordXName" || field == "CoordYName") && data.HasOwnProp("CoordToogle") && !data.CoordToogle))
            continue
        if (field == "SaveName") {
            if (stem == "ArrayFile") {
                kind := data.HasOwnProp("Type") ? data.Type : ""
                scalar := kind == "包含" || kind == "长度"
                    || ((kind == "取值" || kind == "移除" || kind == "移除最后")
                        && data.HasOwnProp("SaveType") && data.SaveType == "变量")
                if (!scalar)
                    continue
            } else if (data.HasOwnProp("SaveType") && data.SaveType == "数组")
                continue
            if (stem == "FileIOFile" && (!data.HasOwnProp("OperType") || !FileIOIsReadType(FileIONormType(data.OperType))
                || (data.HasOwnProp("OperMode") && (data.OperMode == "指定区域-行" || data.OperMode == "指定区域-列"))))
                continue
        }
        Compat13_AddConditionVariable(vars, data.%field%)
    }
    loop 12 {
        field := "ResultVar" A_Index
        if (data.HasOwnProp(field))
            Compat13_AddConditionVariable(vars, data.%field%)
    }
    if (data.HasOwnProp("SaveNameArr") && data.SaveNameArr is Array) {
        mode := data.HasOwnProp("Mode") ? CmdEnumZh(data.Mode, CmdEnumRunModeNames()) : ""
        count := mode == "等待+输入输出" ? 3 : mode == "等待+返回值" ? 1 : 0
        loop Min(count, data.SaveNameArr.Length)
            Compat13_AddConditionVariable(vars, data.SaveNameArr[A_Index])
    }

}

Compat13_AddConditionVariable(vars, name) {
    if (!IsObject(name) && name != "" && !IsNumber(name))
        vars[name] := true
}
