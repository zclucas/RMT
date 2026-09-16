#Requires AutoHotkey v2.0
; ============================================================
; ConfigUtil — 配置存储层（TOML）
;
; 取代 AHK 内置 IniRead / IniWrite / IniDelete：所有配置文件统一为 UTF-8 TOML，
; 原 INI 的「段」→ TOML 表，「键」→ 表内键。
;   覆盖：Setting\MainSettings.toml、Setting\themes.toml、
;         以及各方案目录 Setting\<方案>\*.toml
;
; 接口与 INI 三件套参数顺序保持一致，便于整体替换：
;   IniRead(f, s, k, d)  → CfgRead(f, s, k, d)
;   IniWrite(v, f, s, k) → CfgWrite(v, f, s, k)
;   IniDelete(f, s, k)   → CfgDelete(f, s, k)
;   IniRead(f, s)        → CfgSection(f, s)       ; 整段读出 : Map(键 → 值)
;   IniRead(f)           → CfgSections(f)         ; 段名数组
;
; 取值语义与 IniRead 对齐：键存在 → 返回字符串；键不存在 → 返回调用方传入的默认值。
; 写值统一 String() 后落盘（TOML 基础字符串），与旧 INI 的字符串往返完全一致，
; 因此所有下游对取值的类型判断（IsNumber / Integer() / 字符串比较）无需改动。
;
; 键名/段名含非裸字符（中文、点号、空格等）时由 TomlWriter 自动加引号；
; 本层在读取侧统一去引号，调用方一律传无引号名。
;
; 缓存：按路径缓存整文件解析结果，用「修改时间 + 文件大小」判活；
; 文件被本进程或其它进程改写后指纹变化 → 自动重解析。
; 本进程写入后直接把内存 root 挂回缓存（不清缓存，避免下次读重解析）；
; 配置热重载入口可调 CfgInvalidate 主动失效。
;
; 批处理（CfgBatchBegin / CfgBatchEnd）：把逐键写入合并成一次解析 + 一次落盘，
; 供旧配置迁移这类「按段遍历、逐键改写」的场景使用，避免整文件重复读写。
; ============================================================
#Include "TomlUtil.ahk"

global Cfg_Cache := Map()   ; 文件路径 → {Stamp, Root}；Root: Map(段名 → Map(键 → 值))
global Cfg_BatchDepth := 0  ; 批处理嵌套深度；>0 时写入只改内存、落盘推迟到 CfgBatchEnd
global Cfg_BatchDirty := Map()  ; 批处理期间有未落盘改动的文件

; ============================================================
; 文件级
; ============================================================

; 文件指纹（修改时间 + 大小）；不存在返回 "0"
Cfg_Stamp(file) {
    if (file == "" || !FileExist(file))
        return "0"
    try
        return FileGetTime(file, "M") "|" FileGetSize(file)
    catch
        return "0"
}

; 解析整文件为 Map(段名 → Map(键 → 值))，带指纹缓存；文件不存在/解析失败 → 空 Map
Cfg_Load(file) {
    global Cfg_Cache, Cfg_BatchDepth
    ; 批处理期间该文件的最新内容只在内存里（改动未落盘），指纹比对既无意义又纯属开销
    ;（一次 Cfg_Stamp = FileExist + FileGetTime + FileGetSize 三次文件操作；
    ;  Compat* 逐键写入时会调用几千次）
    if (Cfg_BatchDepth > 0 && Cfg_Cache.Has(file))
        return Cfg_Cache[file].Root
    stamp := Cfg_Stamp(file)
    if (Cfg_Cache.Has(file)) {
        st := Cfg_Cache[file]
        if (st.Stamp == stamp)
            return st.Root
    }
    root := Map()
    if (stamp != "0") {
        try {
            t := Toml().read(FileRead(file, "UTF-8"))
            if (TomlUtil_Valid(t))
                Cfg_Flatten(t.tomap(), root, "")
        } catch as e {
            try RMTLogSys(RMT_LV_ERROR, "ConfigUtil", Format("解析配置 {1} 失败: {2}", file, e.Message))
        }
    }
    Cfg_Cache[file] := {Stamp: stamp, Root: root}
    return root
}

; 把 TOML 表展平进 root：标量 → root[段][键]，子表 → 递归成 "段.子表"
; 解析层会保留引号字符（"搜索1"），此处统一剥掉，与 CfgWrite 的写入侧对称
Cfg_Flatten(tbl, root, section) {
    seg := Cfg_Seg(root, section)
    for k, v in tbl {
        name := TomlUtil_StripKey(k)
        if (IsObject(v) && v is Map)
            Cfg_Flatten(v, root, (section == "") ? name : section "." name)
        else
            seg[name] := Cfg_Scalar(v)
    }
}

; 取（不存在则建）某段
Cfg_Seg(root, section) {
    if (!root.Has(section))
        root[section] := Map()
    return root[section]
}

; TOML 标量 → 字符串（与 IniRead 的返回一致；布尔 true/false 按 AHK 整数 1/0 字符串化）
Cfg_Scalar(v) {
    if (v is Java.Null)
        return ""
    if (IsObject(v)) {
        if (v is ArrayList) {
            out := []
            for item in v
                out.Push(Cfg_Scalar(item))
            return out
        }
        return ""
    }
    return String(v)
}

; 原子写整文件：先写 .tmp 再替换，防主进程/Worker 读到半截文件
; 写成功后把内存 root 直接挂回缓存（指纹取新值）——若此处改回「失效缓存」，
; 下一个 CfgRead/CfgWrite 会重新整文件解析，逐键写入的旧配置迁移会退化成 O(n²)
Cfg_WriteRoot(root, file) {
    global Cfg_Cache
    ok := false
    try {
        content := TomlWriter().write(root)
        SplitPath file, , &dir
        if (dir != "" && !DirExist(dir))
            DirCreate(dir)
        f := FileOpen(file ".tmp", "w", "UTF-8-RAW")
        f.Write(content)
        f.Close()
        FileMove(file ".tmp", file, 1)
        ok := true
    } catch as e {
        try RMTLogSys(RMT_LV_ERROR, "ConfigUtil", Format("写配置 {1} 失败: {2}", file, e.Message))
        throw e
    } finally {
        ; 写失败时不更新缓存：指纹不变，下次 Cfg_Load 会按磁盘重解析，语义与旧行为一致
        if (ok)
            Cfg_Cache[file] := {Stamp: Cfg_Stamp(file), Root: root}
    }
}

; 失效缓存；file 省略 → 清空全部
CfgInvalidate(file := "") {
    global Cfg_Cache, Cfg_BatchDirty
    ; AHK v2 的 Map.Delete 对不存在的键会抛错，必须 Has 守卫
    if (file == "") {
        Cfg_Cache.Clear()
        return
    }
    ; 批处理期间该文件有未落盘的改动：内存 root 才是最新，不能丢
    if (Cfg_BatchDirty.Has(file))
        return
    if (Cfg_Cache.Has(file))
        Cfg_Cache.Delete(file)
}

; ============================================================
; 批处理：把「逐键 CfgWrite / CfgDelete」合并成「一次解析 + 一次落盘」
;
; 用途：旧配置迁移（FixCompatUtil 的 Compat*）要按段遍历、逐键改写，
; 每个键都整文件重写一遍会退化到 O(n²)（实测一份 64KB 配置要 119 秒）。
; 用法：
;   CfgBatchBegin()
;   try {
;       ... 大量 CfgWrite / CfgDelete ...
;   } finally {
;       CfgBatchEnd()      ; 出错也一定会落盘，不会丢已改内容
;   }
; 期间 CfgRead / CfgSection 读到的是含未落盘改动的最新内存值（比旧行为更一致）。
; ============================================================

; 开始批处理（可嵌套）
CfgBatchBegin() {
    global Cfg_BatchDepth
    Cfg_BatchDepth += 1
}

; 结束批处理；最外层结束时把所有脏文件各写一次
CfgBatchEnd() {
    global Cfg_BatchDepth, Cfg_BatchDirty
    if (Cfg_BatchDepth > 0)
        Cfg_BatchDepth -= 1
    if (Cfg_BatchDepth > 0)
        return
    dirty := Cfg_BatchDirty
    Cfg_BatchDirty := Map()
    for file, _ in dirty
        Cfg_WriteRoot(Cfg_Load(file), file)
}

; 批处理期间：标记脏文件并跳过落盘
CfgBatchTouch(file) {
    global Cfg_BatchDirty
    Cfg_BatchDirty[file] := true
}

; ============================================================
; 取值 / 写入 / 删除
; ============================================================

; 读取标量：键存在 → 字符串；键不存在 → def
CfgRead(file, section, key, def := "") {
    if (file == "")
        return def
    root := Cfg_Load(file)
    if (!root.Has(section))
        return def
    seg := root[section]
    return seg.Has(key) ? seg[key] : def
}

; 写入标量（值统一字符串化落盘）
CfgWrite(value, file, section, key) {
    global Cfg_BatchDepth
    if (file == "")
        return
    root := Cfg_Load(file)
    Cfg_Seg(root, section)[key] := Cfg_Stringify(value)
    if (Cfg_BatchDepth > 0) {
        CfgBatchTouch(file)
        return
    }
    Cfg_WriteRoot(root, file)
}

Cfg_Stringify(value) {
    if (IsObject(value))
        return ""
    return String(value)
}

; 删键；key 省略 → 删整段。键/段不存在时不落盘（与 IniDelete 一致）
CfgDelete(file, section, key := "") {
    global Cfg_BatchDepth
    if (file == "" || !FileExist(file))
        return
    root := Cfg_Load(file)
    if (!root.Has(section))
        return
    if (key == "") {
        root.Delete(section)
    } else {
        seg := root[section]
        if (!seg.Has(key))
            return
        seg.Delete(key)
    }
    if (Cfg_BatchDepth > 0) {
        CfgBatchTouch(file)
        return
    }
    Cfg_WriteRoot(root, file)
}

; 段名数组（等价 CfgRead(file)：返回全部段名）
CfgSections(file) {
    out := []
    if (file == "")
        return out
    for name, _ in Cfg_Load(file)
        out.Push(name)
    return out
}

; 段内全部键值 → Map 副本（等价 CfgRead(file, section) 的整段读出）
CfgSection(file, section) {
    if (file == "")
        return Map()
    root := Cfg_Load(file)
    return root.Has(section) ? root[section].Clone() : Map()
}

; 段是否有内容
CfgHasSection(file, section) {
    root := Cfg_Load(file)
    return root.Has(section) && root[section].Count > 0
}

; 删除某段及其全部带点子段（供表清空/孤儿清理）
CfgDeleteSegs(file, section) {
    global Cfg_BatchDepth
    root := Cfg_Load(file)
    prefixDot := section "."
    changed := false
    for name in root.Clone() {
        if (name == section || SubStr(name, 1, StrLen(prefixDot)) == prefixDot) {
            root.Delete(name)
            changed := true
        }
    }
    if (!changed)
        return
    if (Cfg_BatchDepth > 0) {
        CfgBatchTouch(file)
        return
    }
    Cfg_WriteRoot(root, file)
}

; 枚举某段下的全部直接子段（按段名最后一节的自然数字升序）
; 例：section="Normal" → ["Normal.Module1","Normal.Module2"]
CfgSubSections(file, section) {
    root := Cfg_Load(file)
    prefixDot := section "."
    segs := []
    orderMap := Map()
    for name, _ in root {
        if (name == section || SubStr(name, 1, StrLen(prefixDot)) != prefixDot)
            continue
        tail := SubStr(name, StrLen(prefixDot) + 1)
        if (InStr(tail, "."))
            continue   ; 更深层级孙段
        num := 0
        if (RegExMatch(tail, "(\d+)$", &m))
            num := Integer(m[1])
        segs.Push(name)
        orderMap[name] := num
    }
    BuildSortIndex(segs, orderMap)
    return segs
}
