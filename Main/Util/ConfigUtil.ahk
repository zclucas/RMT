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
;
; 延迟落盘（本层的默认行为）：
;   写配置 = 只改内存 + 标脏，落盘交给一个 250ms 的泵，按「最后一次写入后静默
;   CfgDebounceMs」或「首个脏文件等满 CfgMaxDelayMs」两个条件择先触发。
;   调用方（业务）只管改配置，不再为「一次操作写十几次磁盘」负责。
;   需要立刻落盘的场合（退出、需要让其它进程读到、用户点保存）调 CfgFlushAll()。
;   读配置永远读到含未落盘改动的最新内存值，语义比「改完才读」更一致。
; ============================================================
#Include "TomlUtil.ahk"

global Cfg_Cache := Map()   ; 文件路径 → {Stamp, Root}；Root: Map(段名 → Map(键 → 值))
global Cfg_BatchDepth := 0  ; 批处理嵌套深度；>0 时写入只改内存、落盘推迟到 CfgBatchEnd
global Cfg_BatchDirty := Map()  ; 批处理期间有未落盘改动的文件
global Cfg_Dirty := Map()   ; 有未落盘改动的文件（延迟落盘队列）
global Cfg_LastWriteAt := 0 ; 最近一次标脏的时刻（防抖用）
global Cfg_FirstDirtyAt := 0    ; 本轮首个脏文件的时刻（最长等待用）
global Cfg_PumpOn := false  ; 落盘泵是否在跑
global Cfg_PumpFn := 0      ; 落盘泵的函数引用（同一个对象才能「重置」而不是「新增」定时器）
global CfgDebounceMs := 400 ; 最后一次写入后静默这么久就落盘
global CfgMaxDelayMs := 3000    ; 持续写入时的最长等待，超时强制落盘

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
    global Cfg_Cache, Cfg_BatchDepth, Cfg_Dirty
    ; 批处理期间该文件的最新内容只在内存里（改动未落盘），指纹比对既无意义又纯属开销
    ;（一次 Cfg_Stamp = FileExist + FileGetTime + FileGetSize 三次文件操作；
    ;  Compat* 逐键写入时会调用几千次）
    if (Cfg_BatchDepth > 0 && Cfg_Cache.Has(file))
        return Cfg_Cache[file].Root
    ; 同理：延迟落盘窗口内磁盘是旧内容，内存 root 才是事实来源。
    ; 少了这一条，下次 CfgRead 会按旧指纹重新解析，把刚改的值原样读回旧值。
    if (Cfg_Dirty.Has(file) && Cfg_Cache.Has(file))
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

; ------------------------------------------------------------
; 延迟落盘
;
; 写入只改内存并标脏，落盘由 Cfg_FlushPump 择机完成：
;   · 最后一次写入后静默 CfgDebounceMs（默认 400ms）→ 落盘（合并一次操作里的多次写）
;   · 首个脏文件等满 CfgMaxDelayMs（默认 3s）→ 强制落盘（持续写入也不会无限拖）
; 需要立刻可见的场合（退出、跨进程交接、用户点保存）直接调 CfgFlushAll()。
; ------------------------------------------------------------

; 标记文件有未落盘改动并启动落盘泵
Cfg_MarkDirty(file) {
    global Cfg_Dirty, Cfg_LastWriteAt, Cfg_FirstDirtyAt, Cfg_PumpOn, Cfg_PumpFn
    Cfg_Dirty[file] := true
    now := A_TickCount
    Cfg_LastWriteAt := now
    if (!Cfg_FirstDirtyAt)
        Cfg_FirstDirtyAt := now
    if (Cfg_PumpOn)
        return
    ; 函数引用只取一次并存在全局：SetTimer 以对象识别定时器，每次新建对象等于叠加定时器
    if (!Cfg_PumpFn)
        Cfg_PumpFn := Cfg_FlushPump
    Cfg_PumpOn := true
    SetTimer(Cfg_PumpFn, 250)
}

Cfg_FlushPump() {
    global Cfg_Dirty, Cfg_LastWriteAt, Cfg_FirstDirtyAt, Cfg_PumpOn, Cfg_PumpFn
    if (!Cfg_Dirty.Count) {
        SetTimer(Cfg_PumpFn, 0)
        Cfg_PumpOn := false
        Cfg_FirstDirtyAt := 0
        return
    }
    now := A_TickCount
    idle := now - Cfg_LastWriteAt
    age := Cfg_FirstDirtyAt ? now - Cfg_FirstDirtyAt : 999999
    if (idle < CfgDebounceMs && age < CfgMaxDelayMs)
        return
    CfgFlushAll()
    if (!Cfg_Dirty.Count) {
        SetTimer(Cfg_PumpFn, 0)
        Cfg_PumpOn := false
        Cfg_FirstDirtyAt := 0
    }
}

; 立即把所有脏文件写盘；返回写成功的文件数。写失败的留在脏表里等下一轮。
CfgFlushAll() {
    global Cfg_Dirty, Cfg_Cache
    if (!Cfg_Dirty.Count)
        return 0
    pending := Cfg_Dirty
    Cfg_Dirty := Map()
    n := 0
    for file, _ in pending {
        if (!Cfg_Cache.Has(file))
            continue
        try {
            Cfg_WriteRoot(Cfg_Cache[file].Root, file)
            n += 1
        } catch {
            Cfg_Dirty[file] := true      ; 保留改动，下一轮重试
        }
    }
    return n
}

; 失效缓存；file 省略 → 清空全部
CfgInvalidate(file := "") {
    global Cfg_Cache, Cfg_BatchDirty, Cfg_Dirty
    ; AHK v2 的 Map.Delete 对不存在的键会抛错，必须 Has 守卫
    if (file == "") {
        CfgFlushAll()               ; 清缓存前把未落盘的改动写出去，否则等于丢弃
        Cfg_Cache.Clear()
        return
    }
    ; 批处理 / 延迟落盘期间该文件有未落盘的改动：内存 root 才是最新，不能丢
    if (Cfg_BatchDirty.Has(file) || Cfg_Dirty.Has(file))
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

; 结束批处理；最外层结束时把所有脏文件交给延迟落盘（由落盘泵合并写一次）
CfgBatchEnd() {
    global Cfg_BatchDepth, Cfg_BatchDirty, Cfg_Cache
    if (Cfg_BatchDepth > 0)
        Cfg_BatchDepth -= 1
    if (Cfg_BatchDepth > 0)
        return
    dirty := Cfg_BatchDirty
    Cfg_BatchDirty := Map()
    for file, _ in dirty {
        if (Cfg_Cache.Has(file))
            Cfg_MarkDirty(file)
    }
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
; 非批处理时也只改内存 + 标脏，落盘交给延迟泵（业务不再为「写一次磁盘」负责）
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
    Cfg_MarkDirty(file)
}

Cfg_Stringify(value) {
    if (IsObject(value))
        return ""
    return String(value)
}

; 删键；key 省略 → 删整段。键/段不存在时不落盘（与 IniDelete 一致）
CfgDelete(file, section, key := "") {
    global Cfg_BatchDepth, Cfg_Cache
    ; 磁盘上还没有但内存里刚写过（延迟落盘窗口内）的文件同样要能删
    if (file == "" || (!FileExist(file) && !Cfg_Cache.Has(file)))
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
    Cfg_MarkDirty(file)
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
    Cfg_MarkDirty(file)
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
