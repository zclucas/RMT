#Requires AutoHotkey v2.0
; ============================================================
; TomlUtil — toml4ahk 封装层（TOML 宏配置读写统一入口）
; 依赖：Main\Util\Toml\Toml.ahk + TomlBase.ahk（toml4ahk 裁剪版）
; 设计要点：
;   - 含点段名（路径身份）写回时 TomlWriter 自动加引号（["Normal.Module1"]）；
;     解析后 root 键保留引号字符（"Normal.Module1"）。本层自动处理引号差异，
;     调用方一律传无引号键（如 "Normal.Module1"），TomlUtil_Table 内部补引号。
;   - 读文件带缓存（按路径），写后自动失效，避免重复全文件解析。
;   - 所有取字段接口对空/无效段返回默认值，调用方无需判空。
; ============================================================
#Include "Toml\Toml.ahk"

global TomlUtil_Cache := Map()

; ---------- 文件级 ----------

; 默认目标文件（全局 MacroFile；调用方可传 filePath 覆盖）
TomlUtil_Path() {
    global MacroFile
    return MacroFile
}

; 解析整个文件（带缓存）；文件不存在或解析失败返回 ""
TomlUtil_Read(filePath := "") {
    global TomlUtil_Cache
    if (filePath == "")
        filePath := TomlUtil_Path()
    if (TomlUtil_Cache.Has(filePath))
        return TomlUtil_Cache[filePath]
    obj := ""
    if (FileExist(filePath)) {
        try {
            obj := Toml().read(FileRead(filePath, "UTF-8"))
        } catch as e {
            RMTLogSys(RMT_LV_ERROR, "TomlUtil", Format("解析 {1} 失败: {2}", filePath, e.Message))
            obj := ""
        }
    }
    TomlUtil_Cache[filePath] := obj
    return obj
}

; 失效缓存（写文件后必须调用）
; 注意：AHK v2 的 Map.Delete 对不存在的键抛 "Item has no value"（不是返回 0）。
; 必须 Has 守卫：Worker 启动后 TomlUtil_Write 的 finally 已失效缓存，CF 重载再次 Invalidate 时键已不存在。
TomlUtil_Invalidate(filePath := "") {
    global TomlUtil_Cache
    if (filePath == "")
        filePath := TomlUtil_Path()
    if (TomlUtil_Cache.Has(filePath))
        TomlUtil_Cache.Delete(filePath)
}

; 现有 root（键剥离引号，值保留解析后的 HashMap/ArrayList），供整文件写回；文件不存在返回空 Map
TomlUtil_RootMap(filePath := "") {
    t := TomlUtil_Read(filePath)
    root := Map()
    if (!TomlUtil_Valid(t))
        return root
    for k, v in t.tomap()
        root[TomlUtil_StripKey(k)] := v
    return root
}

; 原子写整个 TOML 文件：先写 .tmp 再覆盖，防主进程/Worker 读到半截文件
TomlUtil_Write(root, filePath := "") {
    if (filePath == "")
        filePath := TomlUtil_Path()
    try {
        content := TomlWriter().write(root)
        try {
            f := FileOpen(filePath ".tmp", "w", "UTF-8-RAW")
            f.Write(content)
            f.Close()
        }
        FileMove(filePath ".tmp", filePath, 1)
    } catch as e {
        RMTLogSys(RMT_LV_ERROR, "TomlUtil", Format("写 {1} 失败: {2}", filePath, e.Message))
        throw e
    } finally {
        TomlUtil_Invalidate(filePath)
    }
}

; 删除 root 中某表全部段（表段 + [tableID.*] 子段），供静态表清空与保存重建
TomlUtil_DeleteSegs(root, tableID) {
    prefixDot := tableID "."
    for key in root.Clone() {
        if (key == tableID || SubStr(key, 1, StrLen(prefixDot)) == prefixDot)
            root.Delete(key)
    }
}

; ---------- 键辅助 ----------

; 含点键补引号（toml4ahk 解析后 root 键保留引号字符，取段必须带引号）
TomlUtil_Key(key) {
    return (InStr(key, ".")) ? '"' key '"' : key
}

; 剥离含点键的前后引号（"Normal.Module1" → Normal.Module1）
TomlUtil_StripKey(key) {
    if (StrLen(key) >= 2 && SubStr(key, 1, 1) == '"' && SubStr(key, -1) == '"')
        return SubStr(key, 2, -1)
    return key
}

; ---------- 取值 ----------

; 段是否有效（非空、非 Java.Null）
TomlUtil_Valid(t) {
    return IsObject(t) && !(t is Java.Null)
}

; 取子表（含点键自动补引号）；不存在返回 ""
TomlUtil_Table(t, key) {
    if (!TomlUtil_Valid(t))
        return ""
    seg := t.getTable(TomlUtil_Key(key))
    return (seg is Java.Null) ? "" : seg
}

; 取字符串字段（默认值）
TomlUtil_Str(t, key, def := "") {
    if (!TomlUtil_Valid(t))
        return def
    return t.getString(key, def)
}

; 取整数字段（默认值）
TomlUtil_Int(t, key, def := 0) {
    if (!TomlUtil_Valid(t))
        return def
    v := t.getLong(key, def)
    return (v is integer) ? v : def
}

; 取布尔字段 → 1/0（落盘为 TOML 整数 0/1，兼容字符串 "0"/"1"/"true"/"false"）
TomlUtil_Bool(t, key, def := 0) {
    if (!TomlUtil_Valid(t))
        return TomlUtil_NormBool(def)
    return TomlUtil_NormBool(t.getLong(key, TomlUtil_NormBool(def)))
}

TomlUtil_NormBool(x) {
    return (x == true || x == 1 || x == "1" || x == "true") ? 1 : 0
}

; 取数组字段 → 原生数组（默认 []）
TomlUtil_List(t, key) {
    if (!TomlUtil_Valid(t))
        return []
    l := t.getList(key)
    return (l is ArrayList) ? l.toahk() : []
}

; 取表数组（[[table]]）→ Toml 对象数组（每项可直接用 TomlUtil_Str/Int 取字段）
TomlUtil_Tables(t, key) {
    result := []
    if (!TomlUtil_Valid(t))
        return result
    tables := t.getTables(key)
    if (tables is ArrayList) {
        for tt in tables
            result.Push(tt)
    }
    return result
}

; Toml 段 → 原生 Map（键为原始字符串，值保留解析后的 Java 包装）
TomlUtil_ToMap(t) {
    m := Map()
    if (!TomlUtil_Valid(t))
        return m
    for k, v in t.tomap()
        m[k] := v
    return m
}
