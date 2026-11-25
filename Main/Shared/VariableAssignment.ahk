; 新赋值：裸内容按原值保存，完整引用保留变量值类型，混合文本执行变量替换。
TryGetAssignmentValue(&value, tableItem, index, source) {
    if (RegExMatch(source, "^\{([^{}\r\n]+)\}$", &reference))
        return TryGetTabVarValue(&value, tableItem, index, GetBuiltinVarName(reference[1]), true, false)
    value := source
    if (InStr(source, "{") || InStr(source, "}"))
        GetSmartReplaceVarText(tableItem, index, &value)
    return true
}

; 旧类别仅作兼容读取；转换不能把旧字符里的花括号变成变量引用。
NormalizeVariableAssignmentRows(data) {
    if (!data.HasOwnProp("OperaTypeArr") || !data.HasOwnProp("CopyVariableArr"))
        return false
    changed := false
    for i, type in data.OperaTypeArr {
        if (!data.CopyVariableArr.Has(i))
            continue
        type := CmdEnumOpera(type)
        if (type != "数值" && type != "字符")
            continue
        source := data.CopyVariableArr[i]
        if (type == "字符") {
            source := StrReplace(StrReplace(source, "{", "/{"), "}", "/}")
        } else if (RegExMatch(source, "^[0-9A-Fa-f]{6}$")) {
            ; 旧读取逻辑优先按六位颜色值处理。
        } else if (IsNumber(source)) {
            source := Number(source)
        } else {
            source := "{" GetBuiltinVarName(source) "}"
        }
        data.CopyVariableArr[i] := source
        data.OperaTypeArr[i] := "赋值"
        changed := true
    }
    return changed
}
