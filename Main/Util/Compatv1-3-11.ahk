#Requires AutoHotkey v2.0

Compat13_UpgradeVariableAssignments(dir) {
    path := dir "\VariableFile.toml"
    changed := false
    for serial, raw in CfgSection(path, IniImport_Section()) {
        data := TryParseCommandData(raw)
        if (IsObject(data) && NormalizeVariableAssignmentRows(data)) {
            CfgWrite(JSON.stringify(data, 0), path, IniImport_Section(), serial)
            changed := true
        }
    }
    return changed
}
