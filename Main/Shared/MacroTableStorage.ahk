; ============================================================
; TOML 宏配置读写（MacroFile 指向 MacroFile.toml，操作封装在 Util\TomlUtil.ahk）
; ============================================================

; 从 TOML [[table]] 数组构建 TableItem 列表（每项为 Toml 对象，字段 id/symbol/name/order）
BuildTableItemListFromToml(tables) {
    result := []
    for tbl in tables {
        t := TableItem()
        t.Symbol := TomlUtil_Str(tbl, "symbol", "")
        t.ID := TomlUtil_Str(tbl, "id", t.Symbol)
        t.Name := TomlUtil_Str(tbl, "name", t.Symbol)
        t.Order := TomlUtil_Int(tbl, "order", 1)
        result.Push(t)
    }
    return result
}

; ============================================================
; 加载当前配置方案的所有表（动态表集合）
; 使用 TOML 的 [[table]] 顺序。没有集合时按默认表结构恢复。
; ============================================================
LoadCurMacroSetting() {
    global MySoftData, MacroFileSeedDefaults
    migrated := false

    ; 目录里已经有宏文件（含尚未转换的旧 ini）时，禁止再种入「快捷启动」那套默认列表。
    ; 1.3 写宏列表会按 14 个 [[table]] 重建整文件；读不懂的表以前会在这里回落成默认值，
    ; 复杂旧配置看起来就像整份宏列表被默认配置换掉。
    ; 旧扁平布局的展开由主进程在 InitFilePath 里做（依赖 IniImportUtil，Worker 不加载）。
    ; 这里只管「目录里已有配置」的判定，避免把复杂旧配置当全新表写默认宏。
    MacroFileSeedDefaults := !MacroFileHasExistingSource()

    ; ---- 表集合 [[table]] 数组 ----
    t := TomlUtil_Read()
    if (TomlUtil_Valid(t)) {
        tables := TomlUtil_Tables(t, "table")
        if (tables.Length > 0) {
            ; 独立函数建表：LoadCurMacroSetting 内 `for tableItem` 使 tableItem 为局部变量，
            ; 直接调 TableItem() 会被解析为局部变量调用（AHK v2 大小写不敏感）→ 抽离避免遮蔽
            MySoftData.TableInfo := BuildTableItemListFromToml(tables)
            RebuildTableLocator()
        } else {
            CreateTableItemArr(!MacroFileSeedDefaults && !HasThreeLevelData("Gesture"))
            migrated := true
        }
    } else {
        CreateTableItemArr(!MacroFileSeedDefaults)
        migrated := true
    }
    ; 旧配置按页签 ID 保留当前选中项，再补建缺失的内置宏表。
    if (MainSoftData.CurTableID == "" && IsInteger(MainSoftData.TableIndex)
        && MainSoftData.TableIndex >= 1 && MySoftData.TableInfo.Has(MainSoftData.TableIndex))
        MainSoftData.CurTableID := MySoftData.TableInfo[MainSoftData.TableIndex].ID
    if (EnsureBuiltInMacroTable("Network", "网络宏", "Replace")) {
        RMTLogSysInfo("网络触发", "旧配置迁移：已自动补建「网络宏」表（插在按键替换之后）")
        migrated := true
    }
    if (EnsureBuiltInMacroTable("Gesture", "手势宏", "String"))
        migrated := true
    for tableItem in MySoftData.TableInfo {
        if (ReadTableItemInfo(tableItem))
            migrated := true
        EnsureTableHasFold(tableItem)
    }
    RebuildTableLocator()
    ResolveCurTableIndex()
    ; 本函数只读：上面所有「补全」都只发生在内存里。要不要把表集合写回磁盘，
    ; 由调用方决定——主进程落盘，Worker 只读（它只管拿这份配置去执行宏）。
    return migrated
}

; 持久化的当前 tab 是 TableID（身份）：解析为显示顺序下标；无效则回落 1
ResolveCurTableIndex() {
    global MySoftData
    if (MainSoftData.CurTableID != "") {
        idx := GetTableIndexByID(MainSoftData.CurTableID)
        MainSoftData.TableIndex := idx > 0 ? idx : 1
    } else if (MainSoftData.TableIndex < 1 || MainSoftData.TableIndex > MySoftData.TableInfo.Length) {
        MainSoftData.TableIndex := 1
    }
}

; ============================================================
; 读取单个表的数据（tableItem 为表对象）
; 读三级段结构：[表ID]/[表ID.ModuleN]/[表ID.ModuleN.MacroM]，无三级数据则按全新表生成默认
; 返回 true 表示发生了初始化（需要落盘表集合），false 表示纯三级格式读取
; ============================================================
ReadTableItemInfo(tableItem) {
    global MySoftData
    symbol := tableItem.Symbol

    ; 非配置表（Tool/Setting/Help/Reward/Thank 等静态页）：不参与宏配置，
    ; 一律不读新/旧格式、不迁移，内存结构清空（Items/Folds 恒为空），磁盘由 SaveTableItemInfo 清空。
    if (IsStaticTable(tableItem)) {
        tableItem.Items := []
        tableItem.ItemMap := Map()
        tableItem.Folds := []
        tableItem.FoldMap := Map()
        return false
    }

    ; ---- 三级段检测：表段有 ModuleOrder 键，或存在 [tableID.*] 三级子段 ----
    if (HasThreeLevelData(tableItem.ID)) {
        ReadTableItemInfoNew(tableItem, tableItem.ID)
        return false
    }

    ; 扁平键还在，或文件在但解析失败：保留原文件。写成默认宏就会把用户列表盖掉。
    if (MacroFileMustKeep(symbol)) {
        tableItem.Items := []
        tableItem.ItemMap := Map()
        tableItem.Folds := []
        tableItem.FoldMap := Map()
        return false
    }

    ; 已有配置却读不出这张表：保持空白，不要写成默认宏。
    ; 全新安装（宏文件还不存在）才种入默认列表。
    global MacroFileSeedDefaults
    if (!IsSet(MacroFileSeedDefaults) || !MacroFileSeedDefaults) {
        tableItem.Items := []
        tableItem.ItemMap := Map()
        tableItem.Folds := []
        tableItem.FoldMap := Map()
        return false
    }

    ; ---- 全新表：初始化默认条目并落盘为三级格式 ----
    InitTableItemDefault(tableItem)
    SaveTableItemInfo(tableItem)
    return true
}

; toml 已有内容，或同目录还留着旧 ini，都算用户配置，不能当空白方案种默认宏。
MacroFileHasExistingSource() {
    global MacroFile
    if (MacroFileNonEmpty(MacroFile))
        return true
    ini := MacroFileIniSibling()
    return ini != "" && FileExist(ini)
}

MacroFileNonEmpty(path) {
    if (path == "" || !FileExist(path))
        return false
    try
        return FileGetSize(path) > 0
    catch
        return true
}

MacroFileIniSibling() {
    global MacroFile
    if (!IsSet(MacroFile) || SubStr(MacroFile, -5) != ".toml")
        return ""
    return SubStr(MacroFile, 1, -5) ".ini"
}

; 导入漏展开、或 Worker 没有导入器时：只要还能看到扁平键 / 文件解析失败，就不要落盘默认宏。
; 主进程会在 LoadCurMacroSetting 开头先尝试展开；这里是最后一道，避免 Save 把原文件盖成 8KB 默认列表。
MacroFileMustKeep(symbol) {
    global MacroFile
    if (!IsSet(MacroFile) || MacroFile == "" || !FileExist(MacroFile))
        return false
    try {
        if (FileGetSize(MacroFile) == 0)
            return false
    } catch {
        return true
    }
    t := TomlUtil_Read(MacroFile)
    if (!TomlUtil_Valid(t)) {
        try RMTLogSys(RMT_LV_ERROR, "配置导入", "MacroFile 无法解析，已停止写入默认宏：" MacroFile)
        return true
    }
    if (symbol == "")
        return false
    sec := "UserSettings"
    try {
        kv := CfgSection(MacroFile, sec)
    } catch {
        return true
    }
    if (kv.Has(symbol "ModeArr") || kv.Has(symbol "FoldInfo") || kv.Has(symbol "MacroArr1")) {
        try RMTLogSys(RMT_LV_ERROR, "配置导入", "MacroFile 仍是扁平布局，已停止用默认宏覆盖：" symbol)
        return true
    }
    return false
}

; 判断某表是否存在三级段结构数据（ModuleOrder 键或 [表ID.*] 子段）
HasThreeLevelData(tableID) {
    t := TomlUtil_Read()
    if (!TomlUtil_Valid(t))
        return false
    tableSeg := TomlUtil_Table(t, tableID)
    if (TomlUtil_Valid(tableSeg)) {
        if (TomlUtil_List(tableSeg, "ModuleOrder").Length > 0)
            return true
    }
    return EnumerateDottedSubSegments(tableID).Length > 0
}

; 全新表：按表类型生成默认条目
InitTableItemDefault(tableItem) {
    symbol := tableItem.Symbol
    defs := GetTableItemDefaultInfo(tableItem)
    ; 非宏表（Tool/Setting/Help/Reward/Thank）无默认条目配置（ModeArr 为空串 → 0 条）
    if (defs[3] == "") {
        EnsureTableHasFold(tableItem)
        tableItem.RebuildIndex()
        return
    }
    ; 先确保有默认模块（路径身份 Normal.Module{max+1}），宏路径依赖父模块路径
    EnsureTableHasFold(tableItem)
    defaultFold := tableItem.Folds.Length > 0 ? tableItem.Folds[1] : ""
    itemCount := StrSplit(defs[3], "π").Length      ; ModeArr 决定条目数
    loop itemCount {
        item := MacroItem()
        item.ID := NewMacroPath(tableItem, defaultFold.ID)     ; 路径身份 foldSeg.Macro{max+1}
        item.FoldID := defaultFold.ID
        tableItem.Items.Push(item)
    }
    ApplyLegacyArraysToItems(tableItem, defs, [])
    ; 首次启动（从未保存过配置）：给首个条目填默认宏模板，避免首次创建 Macro_* 落盘为空
    if (!MainSoftData.HasSaved && itemCount >= 1)
        tableItem.Items[1].Macro := GetDefaultMacroForTable(symbol)
    tableItem.RebuildIndex()
}

; 确保表有 ≥1 个折叠框：缺失时创建默认折叠框并把全部条目归入
; 非宏/非条目表（Tool/Setting/Help/Reward/Thank 等静态页）不参与折叠渲染，一律不加默认折叠框
EnsureTableHasFold(tableItem) {
    if (IsStaticTable(tableItem))
        return
    if (tableItem.Folds.Length > 0)
        return
    fold := MacroFold()
    fold.ID := NewModulePath(tableItem)   ; 路径身份 Normal.Module{max+1}
    fold.Remark := GetLang("RMT默认初始化配置")
    tableItem.Folds.Push(fold)
    for item in tableItem.Items
        item.FoldID := fold.ID
    tableItem.RebuildIndex()
}

; ============================================================
; 路径身份分配：模块 = tableID.Module{max+1}；宏 = foldSeg.Macro{max+1}。
; 已删除但仍被宏操作引用的路径也参与分配，防止新宏接管旧引用。
; ============================================================
NewModulePath(tableItem) {
    max := tableItem.PathCounters.Get(tableItem.ID, 0)
    for fold in tableItem.Folds {
        n := SegTailNum(fold.ID, "Module")
        if (n > max)
            max := n
    }
    ; 原模块删除后，移出的宏仍保留原 ID，不能复用其模块路径。
    for item in tableItem.Items {
        parent := SubStr(item.ID, 1, InStr(item.ID, ".", , , -1) - 1)
        n := SegTailNum(parent, "Module")
        if (n > max)
            max := n
    }
    for id in ReferencedMacroPaths(tableItem) {
        parent := SubStr(id, 1, InStr(id, ".", , , -1) - 1)
        n := SegTailNum(parent, "Module")
        if (n > max)
            max := n
    }
    id := tableItem.ID ".Module" (max + 1)
    tableItem.RememberPath(id)
    return id
}

NewMacroPath(tableItem, foldSeg) {
    max := tableItem.PathCounters.Get(foldSeg, 0)
    for item in tableItem.Items {
        if (SubStr(item.ID, 1, InStr(item.ID, ".", , , -1) - 1) != foldSeg)
            continue
        n := SegTailNum(item.ID, "Macro")
        if (n > max)
            max := n
    }
    for id in ReferencedMacroPaths(tableItem) {
        if (SubStr(id, 1, InStr(id, ".", , , -1) - 1) != foldSeg)
            continue
        n := SegTailNum(id, "Macro")
        if (n > max)
            max := n
    }
    id := foldSeg ".Macro" (max + 1)
    tableItem.RememberPath(id)
    return id
}

ReferencedMacroPaths(tableItem) {
    global SubMacroFile, SettingSection
    paths := []
    if (!IsSet(SubMacroFile))
        return paths
    prefix := tableItem.ID "."
    for _, raw in CfgSection(SubMacroFile, SettingSection) {
        data := CompatParseData(raw)
        if (IsObject(data) && data.HasOwnProp("MacroSerial") && Type(data.MacroSerial) == "String"
            && SubStr(data.MacroSerial, 1, StrLen(prefix)) == prefix)
            paths.Push(data.MacroSerial)
    }
    return paths
}

; 解析段名尾节的序号（Normal.Module3 → 3），前缀不匹配或非纯数字返回 0
SegTailNum(seg, prefix) {
    if (seg == "")
        return 0
    tail := GetSegTail(seg)
    if (SubStr(tail, 1, StrLen(prefix)) != prefix)
        return 0
    numStr := SubStr(tail, StrLen(prefix) + 1)
    return (RegExMatch(numStr, "^\d+$")) ? Integer(numStr) : 0
}

; ============================================================
; 新格式读取（三级段结构）：[TableID] / [TableID.ModuleN] / [TableID.ModuleN.MacroM]
;   [TableID]                表段：ModuleOrder=ModuleNπ...（模块显示顺序，重排不改段名）
;   [TableID.ModuleN]        模块段：MacroOrder=宏尾节或完整ID的数组 + 模块字段；段名即模块身份
;   [TableID.ModuleN.MacroM] 宏段：宏字段 + Macro 实义；段名即宏身份（表内唯一路径）
;   段名序号 = 稳定身份（移动不改 ID），归属和顺序由模块 MacroOrder 控制。
;   同模块可用 MacroN 尾节；跨模块存完整 ID，保留子宏及界面绑定引用。
; ============================================================
ReadTableItemInfoNew(tableItem, segID := "") {
    tableID := (segID == "") ? tableItem.ID : segID
    tableItem.Items := []
    tableItem.ItemMap := Map()
    tableItem.Folds := []
    tableItem.FoldMap := Map()

    ; ---- TOML 新链路（操作封装在 Util\TomlUtil.ahk，含点键自动补引号）----
    t := TomlUtil_Read()
    if (!TomlUtil_Valid(t))
        return
    tableSeg := TomlUtil_Table(t, tableID)
    rawCounters := TomlUtil_Str(tableSeg, "PathCounters", "")
    if (rawCounters != "") {
        try {
            counters := JSON.parse(rawCounters, true)
            if (counters is Map) {
                for parent, count in counters {
                    if (IsInteger(count) && count > tableItem.PathCounters.Get(parent, 0))
                        tableItem.PathCounters[parent] := Integer(count)
                }
            }
        }
    }
    foldSegmentOrder := TomlUtil_List(tableSeg, "ModuleOrder")
    foldSegs := EnumerateDottedSubSegments(tableID)   ; root 键前缀枚举（存在性确认）
    for foldRef in foldSegmentOrder {
        foldRef := Trim(foldRef, "`r`n ")
        if (foldRef == "")
            continue
        foldSeg := tableID "." foldRef
        if (!HasSegment(foldSeg, foldSegs))
            continue
        fseg := TomlUtil_Table(t, foldSeg)
        if (!TomlUtil_Valid(fseg))
            continue
        fold := MacroFold()
        fold.ID := foldSeg
        fold.Remark := TomlUtil_Str(fseg, "Remark")
        fold.FrontInfo := TomlUtil_Str(fseg, "FrontInfo")
        fold.ForbidState := !!TomlUtil_Bool(fseg, "ForbidState")
        fold.FoldState := !!TomlUtil_Bool(fseg, "FoldState")
        fold.ForbidHotkey := TomlUtil_Str(fseg, "ForbidHotkey")
        fold.TKType := Integer(TomlUtil_Str(fseg, "TKType", "4"))
        fold.TK := TomlUtil_Str(fseg, "TK")
        fold.GestureTK := TomlUtil_Str(fseg, "GestureTK")
        fold.PosMode := TomlUtil_Int(fseg, "PosMode", 0) == 1 ? 1 : 0
        fold.Anchor := TomlUtil_Int(fseg, "Anchor", 6)
        if (fold.Anchor < 0 || fold.Anchor > 8)
            fold.Anchor := 6
        fold.OffsetX := TomlUtil_Int(fseg, "OffsetX", -50)
        fold.OffsetY := TomlUtil_Int(fseg, "OffsetY", 50)
        fold.PosX := TomlUtil_Int(fseg, "PosX", 0)
        fold.PosY := TomlUtil_Int(fseg, "PosY", 0)
        fold.HoldTime := TomlUtil_Str(fseg, "HoldTime", "500")
        fold.UnorderedTrigger := !!TomlUtil_Bool(fseg, "UnorderedTrigger")
        tableItem.Folds.Push(fold)
        tableItem.FoldMap[foldSeg] := fold

        ; ---- 宏级：按 MacroOrder 加载，跨组条目保留完整路径身份 ----
        macroOrder := TomlUtil_List(fseg, "MacroOrder")
        for macroRef in macroOrder {
            macroSeg := ResolveMacroOrderPath(tableID, foldSeg, macroRef)
            if (macroSeg == "" || tableItem.ItemMap.Has(macroSeg))
                continue
            mseg := TomlUtil_Table(t, macroSeg)
            if (!TomlUtil_Valid(mseg))
                continue
            item := MacroItem()
            item.ID := macroSeg
            item.TK := TomlUtil_Str(mseg, "TK")
            item.HoldTime := TomlUtil_Str(mseg, "HoldTime", "500")
            item.UnorderedTrigger := !!TomlUtil_Bool(mseg, "UnorderedTrigger")
            item.Forbid := TomlUtil_Bool(mseg, "Forbid")
            item.LoopCount := TomlUtil_Str(mseg, "LoopCount", "1")
            item.Remark := TomlUtil_Str(mseg, "Remark")
            item.TriggerType := TomlUtil_Str(mseg, "TriggerType", "1")
            item.TimingSerial := TomlUtil_Str(mseg, "TimingSerial")
            ; 兼容旧版保存的整数 Mode；字符串读取器不会自动转换整数。
            item.Mode := TomlUtil_Str(mseg, "Mode", TomlUtil_Int(mseg, "Mode", 1))
            item.StartTipSound := TomlUtil_Str(mseg, "StartTipSound", "1")
            item.EndTipSound := TomlUtil_Str(mseg, "EndTipSound", "1")
            item.StopTipSound := TomlUtil_Str(mseg, "StopTipSound", "1")
            item.BindWindow := TomlUtil_Str(mseg, "BindWindow", "{模块窗口绑定}")
            if (item.BindWindow == "")
                item.BindWindow := "{模块窗口绑定}"
            item.IcoPath := TomlUtil_Str(mseg, "IcoPath")
            item.VoiceKeywords := TomlUtil_Str(mseg, "VoiceKeywords")
            item.Macro := TomlUtil_Str(mseg, "Macro")
            item.PreMacro := TomlUtil_Str(mseg, "PreMacro")     ;执行前钩子（缺省 ""）
            item.PostMacro := TomlUtil_Str(mseg, "PostMacro")   ;执行后钩子（缺省 ""）
            item.Breakpoints := TomlUtil_Str(mseg, "Breakpoints")   ;断点集合（缺省 ""）
            item.FoldID := foldSeg
            tableItem.Items.Push(item)
            tableItem.ItemMap[macroSeg] := item
        }
    }
}

; 判断 seg 是否在 segList（已枚举的子段名数组）中
HasSegment(seg, segList) {
    for s in segList {
        if (s == seg)
            return true
    }
    return false
}

; 归一化 Forbid 布尔（兼容旧格式字符串 "0"/"1" / 布尔 / 数字）
ParseBoolInt(x) {
    return (x == true || x == "1" || x == 1) ? 1 : 0
}

; ============================================================
; 枚举某个段名前缀下的全部直接子段（不含更深的孙段），按段名最后一节的数字自然排序。
; 例：prefix="Normal" → ["Normal.Module1","Normal.Module2"]
;     prefix="Normal.Module1" → ["Normal.Module1.Macro1", ...]
; 仅返回比 prefix 多一节（不含更深层级）的段。
; ============================================================
EnumerateDottedSubSegments(prefix) {
    segs := []
    orderMap := Map()   ; 段名 -> 末节数字
    ; ---- TOML 新链路：root 键迭代（TomlUtil_RootMap 已剥离引号，不再枚举磁盘） ----
    src := TomlUtil_RootMap()
    prefixDot := prefix "."
    for seg, _ in src {
        if (seg == "" || seg == prefix)
            continue
        if (SubStr(seg, 1, StrLen(prefixDot)) != prefixDot)
            continue
        tail := SubStr(seg, StrLen(prefixDot) + 1)
        if (InStr(tail, "."))
            continue   ; 更深层级孙段
        num := 0
        if (RegExMatch(tail, "(\d+)$", &m))
            num := Integer(m[1])
        segs.Push(seg)
        orderMap[seg] := num
    }
    ; 按末节数字自然升序
    BuildSortIndex(segs, orderMap)
    return segs
}

; 按 orderMap 提供的末节数字对 segs 做稳定升序（冒泡，量小）
BuildSortIndex(segs, orderMap) {
    n := segs.Length
    loop n - 1 {
        swapped := false
        inn := n - (A_Index - 1)
        j := 1
        while j < inn {
            if (orderMap[segs[j + 1]] < orderMap[segs[j]]) {
                tmp := segs[j]
                segs[j] := segs[j + 1]
                segs[j + 1] := tmp
                swapped := true
            }
            j++
        }
        if (!swapped)
            break
    }
}

; 把旧默认信息数组应用为条目（供全新表初始化）
ApplyLegacyArraysToItems(tableItem, defs, macroArr) {
    itemCount := StrSplit(defs[3], "π").Length
    loop itemCount {
        item := tableItem.Items[A_Index]
        item.TK := (StrSplit(defs[1], "π").Has(A_Index)) ? StrSplit(defs[1], "π")[A_Index] : ""
        item.HoldTime := (StrSplit(defs[2], "π").Has(A_Index)) ? StrSplit(defs[2], "π")[A_Index] : 500
        item.Mode := (StrSplit(defs[3], "π").Has(A_Index)) ? StrSplit(defs[3], "π")[A_Index] : 1
        item.Forbid := (StrSplit(defs[4], "π").Has(A_Index)) ? StrSplit(defs[4], "π")[A_Index] : 0
        item.Remark := (StrSplit(defs[5], "π").Has(A_Index)) ? StrSplit(defs[5], "π")[A_Index] : ""
        item.LoopCount := (StrSplit(defs[6], "π").Has(A_Index)) ? StrSplit(defs[6], "π")[A_Index] : "1"
        item.TriggerType := (StrSplit(defs[7], "π").Has(A_Index)) ? StrSplit(defs[7], "π")[A_Index] : 1
        item.TimingSerial := (StrSplit(defs[8], "π").Has(A_Index)) ? StrSplit(defs[8], "π")[A_Index] : ""
        item.StartTipSound := (StrSplit(defs[10], "π").Has(A_Index)) ? StrSplit(defs[10], "π")[A_Index] : 1
        item.EndTipSound := (StrSplit(defs[11], "π").Has(A_Index)) ? StrSplit(defs[11], "π")[A_Index] : 1
        item.IcoPath := (StrSplit(defs[12], "π").Has(A_Index)) ? StrSplit(defs[12], "π")[A_Index] : ""
        item.UnorderedTrigger := (StrSplit(defs[13], "π").Has(A_Index)) ? (StrSplit(defs[13], "π")[A_Index] == "1") : false
        item.VoiceKeywords := (StrSplit(defs[14], "π").Has(A_Index)) ? StrSplit(defs[14], "π")[A_Index] : ""
    }
}

; 返回新表的内置示例。按键替换表使用键名对，无示例的表返回空串。
GetDefaultMacroForTable(symbol) {
    if (symbol == "Normal") {
        return "按键_a_点击_100_10_200,间隔_3000"
    }
    else if (symbol == "String")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "Timing")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "SubMacro")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "Replace")
        return "Left,a"
    else if (symbol == "UI")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "Voice")
        return "按键_a_点击_100_10_200,间隔_3000"   ; 语音宏默认指令模板
    return ""
}

GetTableItemDefaultInfo(tableItem) {
    symbol := tableItem.Symbol
    savedTKArrStr := ""
    savedModeArrStr := ""
    savedForbidArrStr := ""
    savedRemarkArrStr := ""
    savedLoopCountStr := ""
    savedHoldTimeArrStr := ""
    savedTriggerTypeStr := ""
    savedSerialeArrStr := ""
    savedTimingSerialStr := ""
    savedStartTipSoundStr := ""
    savedEndTipSoundStr := ""
    savedIcoPathArrStr := ""
    savedUnorderedTriggerArrStr := ""
    savedVoiceKeywordsArrStr := ""

    if (symbol == "Normal") {
        savedTKArrStr := "k"
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("取消禁用配置才能生效")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "1"
        savedTimingSerialStr := "Timing1"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "0π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "String") {
        savedTKArrStr := ":?*:AA"
        savedHoldTimeArrStr := "0"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("按两次a触发")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "2"
        savedTimingSerialStr := "Timing2"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "Menu") {
        savedTKArrStr := "πππ"
        savedHoldTimeArrStr := "500π500π500π500"
        savedModeArrStr := "1π1π1π1"
        savedForbidArrStr := "0π0π0π0"
        savedRemarkArrStr := GetLang("快捷启动") "π" GetLang("音量调节") "π" GetLang("窗口管理") "π" GetLang("自定义")
        savedLoopCountStr := "1π1π1π1"
        savedTriggerTypeStr := "4π4π4π4"
        savedSerialeArrStr := "3π4π5π6"
        savedTimingSerialStr := "Timing3πTiming4πTiming5πTiming6"
        savedStartTipSoundStr := "1π1π1π1"
        savedEndTipSoundStr := "1π1π1π1"
        savedIcoPathArrStr := "0π0π0π0"
        savedUnorderedTriggerArrStr := "0π0π0π0"
    }
    else if (symbol == "UI") {
        savedTKArrStr := "ππ"
        savedHoldTimeArrStr := "500π500π500"
        savedModeArrStr := "1π1π1"
        savedForbidArrStr := "1π1π1"
        savedRemarkArrStr := GetLang("界面按钮") "π" GetLang("游戏辅助") "π" GetLang("快捷入口")
        savedLoopCountStr := "1π1π1"
        savedTriggerTypeStr := "1π1π1"
        savedSerialeArrStr := "14π15π16"
        savedTimingSerialStr := "Timing14πTiming15πTiming16"
        savedStartTipSoundStr := "1π1π1"
        savedEndTipSoundStr := "1π1π1"
        savedIcoPathArrStr := "0π0π0"
        savedUnorderedTriggerArrStr := "0π0π0"
    }
    else if (symbol == "Voice") {
        savedTKArrStr := "πππ"
        savedHoldTimeArrStr := "0π0π0"
        savedModeArrStr := "1π1π1"
        savedForbidArrStr := "1π1π1"
        savedRemarkArrStr := GetLang("语音宏示例1") "π" GetLang("语音宏示例2") "π" GetLang("语音宏示例3")
        savedLoopCountStr := "1π1π1"
        savedTriggerTypeStr := "1π1π1"
        savedSerialeArrStr := "17π18π19"
        savedTimingSerialStr := "Timing17πTiming18πTiming19"
        savedStartTipSoundStr := "1π1π1"
        savedEndTipSoundStr := "1π1π1"
        savedIcoPathArrStr := "0π0π0"
        savedUnorderedTriggerArrStr := "0π0π0"
        savedVoiceKeywordsArrStr := "你好π开始π停止"   ; 默认唤醒词
    }
    else if (symbol == "Timing") {
        savedTKArrStr := ""
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("通过定时或宏操作调用")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "9"
        savedTimingSerialStr := "Timing9"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "SubMacro") {
        savedTKArrStr := ""
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArr := GetLang("只能通过宏操作调用")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "10"
        savedTimingSerialStr := "Timing10"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "Replace") {
        savedTKArrStr := "k"
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("将k按键替换成其他按键")
        savedTriggerTypeStr := "1"
        savedLoopCountStr := "1"
        savedSerialeArrStr := "11"
        savedTimingSerialStr := "Timing11"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    return [savedTKArrStr, savedHoldTimeArrStr, savedModeArrStr, savedForbidArrStr, savedRemarkArrStr,
        savedLoopCountStr, savedTriggerTypeStr, savedSerialeArrStr, savedTimingSerialStr, savedStartTipSoundStr,
        savedEndTipSoundStr, savedIcoPathArrStr, savedUnorderedTriggerArrStr, savedVoiceKeywordsArrStr]
}

; ============================================================
; 保存单个表（三级段结构）：[TableID] / [TableID.ModuleN] / [TableID.ModuleN.MacroM]
;   [TableID]                表段：ModuleOrder=ModuleNπ...（冗余调试键，顺序以枚举子段为准）
;   [TableID.ModuleN]        模块段：ID=<真实全局 f_xxx> + 模块字段
;   [TableID.ModuleN.MacroM] 宏段：ID=<真实全局 ItemN> + 宏字段 + Macro 实义
;   段名序号 ModuleN/MacroN 为层级内易读序号，真实对象 ID 存段内 ID= 键恢复全局唯一引用。
; ============================================================
SaveTableItemInfo(tableItem) {
    return SaveTableItemInfoToml(tableItem)
}

; ============================================================
; TOML 保存（MacroFile.toml）：整文件读-改-写，原子覆盖
; 根表键即段名（扁平字面）：表段 [tableID]、模块段/宏段为含点路径身份（writer 自动引号）
; 只重建本表全部段（先剔除旧段再写入），其他表段与 [[table]] 数组原样保留
; ============================================================
SaveTableItemInfoToml(tableItem) {
    if (MacroFileMustKeep(""))
        return false
    root := TomlUtil_RootMap()
    SaveTableItemInfoTomlCore(root, tableItem)
    TomlUtil_Write(root)
    return true
}

; 把单表三级段组装进 root（不写文件）：供单表保存与批量保存共用
; 只重建本表全部段（先剔除旧段再写入），其他表段与 [[table]] 数组原样保留
SaveTableItemInfoTomlCore(root, tableItem) {
    tableID := tableItem.ID

    ; 非配置表（Tool/Setting/Help/Reward/Thank 等静态页）：清空本表全部段，保证磁盘零配置、零残留。
    if (IsStaticTable(tableItem)) {
        TomlUtil_DeleteSegs(root, tableID)
        return
    }

    ; 先剔除本表旧段（本次重建覆盖 + 孤儿自动清除），保留其他表段与 table 数组
    TomlUtil_DeleteSegs(root, tableID)

    ; 孤儿宏（FoldID 无匹配模块）先归入首模块，保证不丢失
    fallbackFold := tableItem.Folds.Length > 0 ? tableItem.Folds[1] : ""
    for item in tableItem.Items {
        if ((item.FoldID == "" || !FoldIDBelongs(item.FoldID, tableItem)) && fallbackFold != "")
            item.FoldID := fallbackFold.ID
    }

    ; ---- 表段 [tableID]：ModuleOrder = 模块尾节数组 ----
    moduleOrder := []
    for fold in tableItem.Folds {
        foldSeg := fold.ID
        if (foldSeg == "") {
            RMTLogSys(RMT_LV_ERROR, "SaveTableItemInfo", "模块缺少路径身份(ID)，无法确定段名，跳过")
            continue
        }
        moduleOrder.Push(GetSegTail(foldSeg))
    }
    tableSeg := Map()
    tableSeg["ModuleOrder"] := moduleOrder
    tableSeg["PathCounters"] := JSON.stringify(tableItem.PathCounters, 0)
    root[tableID] := tableSeg

    ; ---- 模块段 + 宏段（含点路径身份键，TomlWriter 自动加引号） ----
    for fold in tableItem.Folds {
        foldSeg := fold.ID
        if (foldSeg == "")
            continue
        fseg := Map()
        fseg["Remark"] := fold.Remark
        fseg["FrontInfo"] := fold.FrontInfo
        fseg["ForbidState"] := fold.ForbidState ? 1 : 0
        fseg["FoldState"] := fold.FoldState ? 1 : 0
        fseg["ForbidHotkey"] := fold.ForbidHotkey
        fseg["TKType"] := String(fold.TKType)
        fseg["TK"] := fold.TK
        if (fold.GestureTK != "")
            fseg["GestureTK"] := fold.GestureTK
        fseg["HoldTime"] := String(fold.HoldTime)
        fseg["UnorderedTrigger"] := fold.UnorderedTrigger ? 1 : 0
        if (tableItem.Symbol == "UI") {
            fseg["PosMode"] := fold.PosMode == 1 ? 1 : 0
            fseg["Anchor"] := fold.HasProp("Anchor") ? Integer(fold.Anchor) : 6
            fseg["OffsetX"] := fold.HasProp("OffsetX") ? Integer(fold.OffsetX) : -50
            fseg["OffsetY"] := fold.HasProp("OffsetY") ? Integer(fold.OffsetY) : 50
            fseg["PosX"] := fold.HasProp("PosX") ? Integer(fold.PosX) : 0
            fseg["PosY"] := fold.HasProp("PosY") ? Integer(fold.PosY) : 0
        }

        macroOrder := []
        for item in tableItem.Items {
            if (item.FoldID != foldSeg)
                continue   ; 宏归属按 FoldID，ID 保留最初分配的路径
            macroSeg := item.ID
            if (macroSeg == "") {
                RMTLogSys(RMT_LV_ERROR, "SaveTableItemInfo", Format("模块{1}内宏缺少路径身份(ID)，跳过", foldSeg))
                continue
            }
            ; 跨组不能只存尾节，否则重载会拼成目标组下不存在或同名的宏。
            macroOrder.Push(ResolveMacroOrderPath(tableID, foldSeg, GetSegTail(macroSeg)) == macroSeg
                ? GetSegTail(macroSeg) : macroSeg)
            mseg := Map()
            mseg["TK"] := item.TK
            mseg["HoldTime"] := String(item.HoldTime)
            mseg["Mode"] := String(item.Mode)
            mseg["Forbid"] := item.Forbid ? 1 : 0
            mseg["Remark"] := item.Remark
            mseg["LoopCount"] := String(item.LoopCount)
            mseg["TriggerType"] := String(item.TriggerType)
            mseg["TimingSerial"] := item.TimingSerial
            mseg["StartTipSound"] := String(item.StartTipSound)
            mseg["EndTipSound"] := String(item.EndTipSound)
            mseg["StopTipSound"] := String(item.StopTipSound)
            mseg["BindWindow"] := item.BindWindow
            mseg["IcoPath"] := item.IcoPath
            mseg["UnorderedTrigger"] := item.UnorderedTrigger ? 1 : 0
            mseg["VoiceKeywords"] := item.VoiceKeywords
            ; 宏内容：原样存储（多行换行由 TomlWriter 转义为 \n，读回自动还原，无需 ⫶ 编码）
            mseg["Macro"] := item.Macro
            ; 执行前/后钩子：与 Macro 同段的条目级宏串（缺省 ""，不启用）
            mseg["PreMacro"] := item.HasProp("PreMacro") ? item.PreMacro : ""
            mseg["PostMacro"] := item.HasProp("PostMacro") ? item.PostMacro : ""
            ; 断点集合：与 Macro 同段的条目级字段，值形如 ",sig1,sig2,"（缺省 ""）
            mseg["Breakpoints"] := item.Breakpoints
            root[macroSeg] := mseg
        }
        fseg["MacroOrder"] := macroOrder
        root[foldSeg] := fseg
    }
}

; ============================================================
; 批量保存全部表（TOML 模式）：一次解析 root + 一次原子写
; 含表集合 [[table]] 与各表三级段，替代 OnSaveSetting 的逐表读写（13 表 → 1 次解析 + 1 次写）
; ============================================================
SaveAllTableItemInfo(tableItems) {
    if (MacroFileMustKeep(""))
        return
    root := TomlUtil_RootMap()
    ; 表集合 [[table]]（id/symbol/name/order）
    tableArr := []
    for tableItem in tableItems {
        tableArr.Push(Map("id", tableItem.ID, "symbol", tableItem.Symbol, "name", tableItem.Name, "order", tableItem.Order))
    }
    root["table"] := tableArr
    ; 各表三级段（共享同一 root，避免逐表读-改-写）
    for tableItem in tableItems
        SaveTableItemInfoTomlCore(root, tableItem)
    TomlUtil_Write(root)
}

; 判断某 FoldID 是否属于本表现有模块集合
FoldIDBelongs(foldID, tableItem) {
    for fold in tableItem.Folds {
        if (fold.ID == foldID)
            return true
    }
    return false
}

; 取段名最后一节（Normal.Module1 → Module1）
GetSegTail(seg) {
    pos := InStr(seg, ".", , , -1)
    return (pos > 0) ? SubStr(seg, pos + 1) : seg
}

; 数组 π 拼接
JoinPi(arr) {
    out := ""
    for v in arr {
        if (out != "")
            out .= "π"
        out .= v
    }
    return out
}

; 保存整个表集合（动态表定义）：[[table]] 数组（id/symbol/name/order）
SaveTableCollection() {
    if (MacroFileMustKeep(""))
        return
    root := TomlUtil_RootMap()
    tableArr := []
    for tableItem in MySoftData.TableInfo {
        tableArr.Push(Map("id", tableItem.ID, "symbol", tableItem.Symbol, "name", tableItem.Name, "order", tableItem.Order))
    }
    root["table"] := tableArr
    TomlUtil_Write(root)
}

; ============================================================
; 旧格式 π 拼接序列化已废弃（新格式见 SaveTableItemInfo/ReadTableItemInfoNew）
; ============================================================

;Table信息相关
; 默认表定义（新体系：动态表集合的初始骨架）
; 每项 [Symbol, 显示名(语言键), 顺序]
MacroCategoryDefs() {
    static defs := [
        ["Normal", "按键宏", 1],
        ["String", "字串宏", 2],
        ["Gesture", "手势宏", 3],
        ["Menu", "菜单宏", 4],
        ["UI", "界面宏", 5],
        ["Voice", "语音宏", 6],
        ["Timing", "定时宏", 7],
        ["SubMacro", "宏", 8],
        ["Replace", "按键替换", 9],
        ["Network", "网络宏", 10]
    ]
    return defs
}

CreateDefaultTableDefs() {
    defs := MacroCategoryDefs().Clone()
    for entry in [["Tool", "工具"], ["Setting", "设置"], ["Help", "帮助"], ["Reward", "支持我们"], ["Thank", "特别感谢"]]
        defs.Push([entry[1], entry[2], defs.Length + 1])
    return defs
}

; 宏相关页签按 MainSoftData.TabVisibleMap 显隐（隐藏不影响触发）；
; 非配置表（Tool/Setting/Help/Reward/Thank）恒显示
IsTabVisible(tableItem) {
    symbol := tableItem.Symbol
    switch symbol {
        case "Tool", "Setting", "Help", "Reward", "Thank":
            return true
    }
    if (IsObject(MainSoftData.TabVisibleMap) && MainSoftData.TabVisibleMap.Has(symbol))
        return MainSoftData.TabVisibleMap[symbol]
    return true
}

; §20 指令改名兼容判断：旧名「移动/移动Pro」与新名「鼠标移动/鼠标移动Pro」都识别
; （旧配置宏内容/流程图节点类型零迁移兼容；增量移动为全新指令无旧名）
; 入参可为当前语言显示文本（如 "Mouse Move"）或中文键，内部统一 GetLangKey 后按键比较
IsMoveCmd(t) {
    k := GetLangKey(t)
    return k == "移动" || k == "鼠标移动"
}
IsMoveProCmd(t) {
    k := GetLangKey(t)
    return k == "移动Pro" || k == "鼠标移动Pro"
}
IsDeltaMoveCmd(t) => GetLangKey(t) == "增量移动"

CreateTableItemArr(legacyOrder := false) {
    global MySoftData
    Arr := []
    defs := CreateDefaultTableDefs()
    for def in defs {
        if (legacyOrder && def[1] == "Gesture")
            continue
        t := TableItem()
        t.ID := def[1]      ; 表身份固定 = 表类型 Symbol（Normal/String/...），不用动态 t_xxx → 重启不漂移，段名固定
        t.Symbol := def[1]
        t.Name := def[2]
        t.Order := Arr.Length + 1
        Arr.Push(t)
    }
    MySoftData.TableInfo := Arr
    RebuildTableLocator()
    return Arr
}

; 为旧配置补建新增的内置宏表，保留已有页签的相对顺序和身份。
EnsureBuiltInMacroTable(symbol, name, afterSymbol) {
    global MySoftData
    for tbl in MySoftData.TableInfo {
        if (tbl.Symbol == symbol)
            return false
    }
    insertIdx := 0
    loop MySoftData.TableInfo.Length {
        if (MySoftData.TableInfo[A_Index].Symbol == afterSymbol) {
            insertIdx := A_Index + 1
            break
        }
    }
    if (insertIdx == 0) {
        insertIdx := MySoftData.TableInfo.Length + 1
        for i, tbl in MySoftData.TableInfo {
            if (IsStaticTable(tbl)) {
                insertIdx := i
                break
            }
        }
    }
    t := TableItem()
    t.Symbol := symbol
    t.ID := symbol
    while (GetTableByID(t.ID))
        t.ID := symbol "_" (A_Index + 1)
    t.Name := name
    t.Order := insertIdx
    MySoftData.TableInfo.InsertAt(insertIdx, t)
    ; 整体归一化 Order 为 1..N。
    loop MySoftData.TableInfo.Length
        MySoftData.TableInfo[A_Index].Order := A_Index
    RebuildTableLocator()
    return true
}
