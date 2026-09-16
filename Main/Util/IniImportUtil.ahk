#Requires AutoHotkey v2.0
; ============================================================
; IniImportUtil — 导入旧版 INI 配置时的格式转换（INI → TOML）
;
; 调用时机：导入 / 迁移 / 复制 / 校对配置（Gui\SettingMgrGui.ahk 的 OnRepairSetting），
; 只在主进程执行；由 Main\GlobalUtil.ahk 引入，Worker(Thread\Work.ahk) 不加载本文件。
;
; 旧 INI 结构：UTF-16(含 BOM)、单层 [段]、key=value（值多为紧凑 JSON，只按首个 = 切分）。
; 转换规则：段名 → TOML 表名；键名 / 值原样落盘（TomlWriter 自动加引号与转义）。
;   MacroFile.ini 保持「扁平数组」键名原样落盘
;   （symbol TKArr / ModeArr / MacroArrN / FoldInfo 等），随后由
;   本文件 IniImport_ExpandFlatMacroFile 展开成三级段 TOML。
;
; 冲突策略：旧 INI 一律胜出（它是本次导入的数据源）。同名 .toml 直接覆盖，不留备份。
; 收尾：写入后回读校验通过才删除原 INI。
; ============================================================

; 不参与转换的 INI（第三方库自带，不属于 RMT 配置体系）
global IniImportSkipNames := Map(
    "docking_layout.ini", 1,   ; AHK-XAML 面板停靠布局
    "config.ini", 1            ; MinTool 倒计时等独立小工具
)

; 配置段名（AssetUtil 启动时建同名全局；此处兜底，避免调用时序问题）
IniImport_Section() {
    global SettingSection
    if (IsSet(SettingSection) && SettingSection != "")
        return SettingSection
    return "UserSettings"
}

; ============================================================
; 目录级：把 dir 下全部 *.ini 转成同名 .toml
; 返回 Map("Converted" n, "Skipped" n, "Failed" Map(文件名 → 错误))
; ============================================================
IniImport_ConvertDir(dir) {
    result := Map("Converted", 0, "Skipped", 0, "Failed", Map())
    if (dir == "" || !DirExist(dir))
        return result

    loop files, dir "\*.ini" {
        iniPath := A_LoopFileFullPath
        name := A_LoopFileName
        if (IniImportSkipNames.Has(name)) {
            result["Skipped"] += 1
            continue
        }
        tomlPath := SubStr(iniPath, 1, StrLen(iniPath) - 4) ".toml"
        tFile := A_TickCount

        ; 旧版 INI 是本次导入的数据源，一律胜出：同名 .toml 直接覆盖
        ;（多为被导入目录里「应用启动时生成的默认骨架」，值全是默认宏）
        try {
            sectionMap := IniImport_ParseIni(iniPath)
            if (IniImport_CountKeys(sectionMap) == 0) {
                ; 连段头都没解析出来 → 编码/行格式异常，保留原文件待查
                if (sectionMap.Count == 0)
                    throw Error("未解析到任何配置项（编码或行格式异常），已跳过并保留原文件")
                ; 只有段头、没有任何键 → 本来就是空配置（如 SearchFile.ini）。
                ; 没有信息量，既不值得生成空 toml，也不该用它覆盖已有 toml，归档原 ini 即可。
                result["Skipped"] += 1
                try FileDelete(iniPath)
                catch as e
                    RMTLogSys(RMT_LV_ERROR, "配置导入", Format("删除空配置 {1} 失败: {2}", name, e.Message))
                continue
            }
            IniImport_WriteToml(tomlPath, sectionMap)
            IniImport_Verify(tomlPath, sectionMap)
            result["Converted"] += 1
            ms := A_TickCount - tFile
            ; 单文件耗时观测：>600ms 才记，用于定位拖慢转换的大文件
            if (ms > 600)
                RMTLogSysInfo("配置导入", Format("  {1} 转换耗时 {2}ms（{3} 字节）", name, ms, A_LoopFileSize))
            ; 校验通过后删掉原 INI（数据已在 toml；留着会被下次导入重复处理）
            try FileDelete(iniPath)
            catch as e
                RMTLogSys(RMT_LV_ERROR, "配置导入", Format("删除原 INI 失败 {1}: {2}", name, e.Message))
        } catch as e {
            result["Failed"][name] := e.Message
        }
    }
    return result
}

; ============================================================
; 单文件：旧 INI 文本 → Map(段名 → Map(键 → 值))
; ============================================================
IniImport_ParseIni(path) {
    text := IniImport_ReadText(path)
    out := Map()
    section := ""
    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)
        if (line == "" || SubStr(line, 1, 1) == ";")
            continue
        if (SubStr(line, 1, 1) == "[") {
            pos := InStr(line, "]")
            section := (pos > 1) ? Trim(SubStr(line, 2, pos - 2)) : ""
            if (section != "" && !out.Has(section))
                out[section] := Map()
            continue
        }
        eq := InStr(line, "=")
        if (eq <= 1)
            continue
        key := Trim(SubStr(line, 1, eq - 1))
        if (key == "")
            continue
        val := Trim(SubStr(line, eq + 1))
        if (section == "")
            section := IniImport_Section()
        if (!out.Has(section))
            out[section] := Map()
        out[section][key] := val
    }
    return out
}

; 读旧 INI 文本：旧版 RMT 配置是 UTF-16LE(+BOM)，也存在 UTF-8 变体。
; 快路径：先按 UTF-16 解一次，若「就是一份完整 ini」直接用 —— 大配置（几百 KB）省掉
; 第二次读取 + 两遍逐行评分（两遍 StrSplit 是导入期的可观测开销）。
; 快路径不成立（无 BOM 的 UTF-8 被当 UTF-16 解会出现 NUL / 替换字符）才双解码取高分。
IniImport_ReadText(path) {
    t16 := ""
    try t16 := FileRead(path, "UTF-16")
    if (IniImport_IsIniText(t16))
        return t16
    t8 := ""
    try t8 := FileRead(path, "UTF-8")
    return (IniImport_TextScore(t16) > IniImport_TextScore(t8)) ? t16 : t8
}

; 快速判定「这段文本就是一份可用的 ini」：无 NUL / 替换字符，且有段头和键值行
IniImport_IsIniText(text) {
    if (text == "" || InStr(text, Chr(0)) || InStr(text, Chr(0xFFFD)))
        return false
    return InStr(text, "=") && RegExMatch(text, "m)^\s*\[")
}

; 文本可信度：段头 [x] +2、键值行 a=b +1、含 NUL / 替换字符 −2
IniImport_TextScore(text) {
    if (text == "")
        return -1
    score := 0
    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)
        if (line == "")
            continue
        if (InStr(line, Chr(0)) || InStr(line, Chr(0xFFFD)))
            score -= 2
        else if (SubStr(line, 1, 1) == "[")
            score += 2
        else if (InStr(line, "="))
            score += 1
    }
    return score
}

; 段内键值总数（判断解析结果是否为「空」）
IniImport_CountKeys(sectionMap) {
    n := 0
    for _, kv in sectionMap
        n += kv.Count
    return n
}

; ============================================================
; 落盘：整文件覆盖写（不读旧文件）
; 旧 INI 是本次导入的数据源，一律胜出 —— 不必合并，也省掉一次全文件解析
;（目标 toml 通常只是「应用启动时生成的默认骨架」；缺的字段由后续 Compat* 补齐）
; ============================================================
IniImport_WriteToml(tomlPath, sectionMap) {
    root := Map()
    for section, kv in sectionMap {
        seg := Map()
        for key, val in kv
            seg[key] := val
        root[section] := seg
    }
    Cfg_WriteRoot(root, tomlPath)
}

; 回读校验：确认写出的文件内容完整、可被后续读取，不完整则抛错（不删原 INI，下次可重试）
;
; 大文件（>200KB，如 535KB 的 SearchProFile）走轻量路径：完整校验是「读回 → TOML 全解析
; → tomap → Flatten → 逐键比对」，一次约 1 秒；而写入走的是批量转义（正确性由构造保证），
; 随后的 Compat* 还会真正解析一次。故大文件只确认「文件非空 + 每个键名都写进去了」。
; 小文件仍做完整解析比对，覆盖转义正确性。
IniImport_Verify(tomlPath, sectionMap) {
    if (!FileExist(tomlPath))
        throw Error(Format("回读校验失败：写出的文件不存在（{1}）", tomlPath))
    size := FileGetSize(tomlPath)
    if (size == 0)
        throw Error(Format("回读校验失败：写出的文件为空（{1}）", tomlPath))
    if (size > 200000) {
        text := ""
        try text := FileRead(tomlPath, "UTF-8")
        catch as e
            throw Error(Format("回读校验失败：无法读取写出的文件（{1}）", tomlPath))
        if (text == "")
            throw Error(Format("回读校验失败：写出的文件无可读内容（{1}）", tomlPath))
        for section, kv in sectionMap {
            for key, val in kv {
                if (!InStr(text, IniImport_QuoteKey(key)))
                    throw Error(Format("回读校验失败：{1} [{2}] {3}", tomlPath, section, key))
            }
        }
        return
    }
    IniImport_VerifyDeep(tomlPath, sectionMap)
}

; 完整校验：真读磁盘 → 重新解析 → 逐键比同值
; 注意：必须绕过 Cfg_Load —— Cfg_WriteRoot 会把内存 root 挂回缓存，
; 走 Cfg_Load 就成「自己和自己比」，校验形同虚设
IniImport_VerifyDeep(tomlPath, sectionMap) {
    t := ""
    try {
        t := Toml().read(FileRead(tomlPath, "UTF-8"))
    } catch as e {
        ; 带上底层异常详情：解析失败只说「无法解析」无法定位，异常对象里的
        ; Message/What/Extra/Line 才能指认是哪个位置、哪一类值（如含 \b 的路径）出的问题
        throw Error(Format("回读校验失败：写出的文件无法解析（{1}）[{2}] What={3} Extra={4} Line={5}",
            tomlPath, e.Message, "" e.What, "" e.Extra, "" e.Line))
    }
    if (!TomlUtil_Valid(t))
        throw Error(Format("回读校验失败：写出的文件为空或解析无结果（{1}）", tomlPath))
    root := Map()
    Cfg_Flatten(t.tomap(), root, "")
    for section, kv in sectionMap {
        if (!root.Has(section))
            throw Error(Format("回读校验失败：缺少表 [{1}]（{2}）", section, tomlPath))
        seg := root[section]
        for key, val in kv {
            if (!seg.Has(key) || seg[key] != val)
                throw Error(Format("回读校验失败：{1} [{2}] {3}", tomlPath, section, key))
        }
    }
}

; 与 TOML 库 MapValueWriter.quoteKey 同规则：含裸字符集之外的字符（中文/点/空格等）时加双引号
IniImport_QuoteKey(key) {
    return RegExMatch(key, "^.*[^A-Za-z\d_-].*$") ? '"' key '"' : key
}

; 段内取值（kv 为 CfgSection 读出的一次性快照）
IniImport_Kv(kv, key, def := "") {
    return kv.Has(key) ? kv[key] : def
}

; ============================================================
; 扁平布局辅助：清掉 MacroFile.toml 里已展开的扁平键
;   （symbol TKArr/ModeArr/MacroArrN/FoldInfo，含 Compat 回填写入的同形键）
;   只删形如 <字母>Arr[数字] / <字母>FoldInfo 的键，其余键原样保留
; ============================================================
IniImport_StripFlatKeys(root) {
    sec := IniImport_Section()
    if (!root.Has(sec))
        return
    seg := root[sec]
    if (!IsObject(seg))
        return
    for key in seg.Clone() {
        if (RegExMatch(key, "^[A-Za-z][A-Za-z0-9_]*Arr\d*$") || RegExMatch(key, "^[A-Za-z][A-Za-z0-9_]*FoldInfo$"))
            seg.Delete(key)
    }
    if (seg.Count == 0)
        root.Delete(sec)
}

; ============================================================
; 供 IniImport_ReadTableItemFlat 使用的 π 数组取值辅助
; ============================================================
IniImport_SplitPi(str) {
    return (str == "") ? [] : StrSplit(str, "π")
}

IniImport_ArrAt(arr, idx, def) {
    return (arr.Has(idx) && arr[idx] != "") ? arr[idx] : def
}

; 从 JSON.parse(text, , false) 得到的「普通 Object」里按属性名取数组的第 idx 项。
; 语法必须区分开（与 MergeUtil.ParseFoldInfo 的用法一致，那是本项目里已验证可用的写法）：
;   · 普通 Object（JSON 对象）→ 属性语法 obj.prop / HasOwnProp；Object 没有 __Item，不能用 obj[prop]
;   · Array（JSON 数组）      → 下标语法 arr[idx] / arr.Has(idx)
; 曾把 Object 递归转成 Map 再取值，结果「Object 属性语法」与「Map 下标语法」用反 →
; FoldInfo 读取整体失败，模块被静默折叠成 Module1（见 2026-09-17 记忆「模块丢失」一节）。
IniImport_ArrGet(obj, prop, idx, def) {
    if (!IsObject(obj) || !ObjHasOwnProp(obj, prop))
        return def
    v := obj.%prop%
    return (IsObject(v) && v.Has(idx)) ? v[idx] : def
}

; ============================================================
; 扁平数组格式读取（旧版 INI 配置导入 / 旧分享包）：
;   symbol TKArr / ModeArr / HoldTimeArr / ForbidArr / RemarkArr / LoopCountArr /
;   TriggerTypeArr / StartTipSoundArr / EndTipSoundArr / IcoPathArr /
;   UnorderedTriggerArr / VoiceKeywordsArr / TimingSerialArr / FoldInfo /
;   MacroArr N（N = 条目序号，值内 ⫶ 代表换行）
;   键名与旧 INI 完全一致，故导入期只需把 INI 机械转成 toml（本文件 IniImport_ConvertDir）即可读取。
;   模块归属由 FoldInfo.IndexSpanArr（"起始-结束" 下标区间）换算；
;   模块/条目的身份按新体系重新分配为路径（表ID.ModuleN.MacroM），旧 SerialArr 不再作为身份。
; 返回 true 表示读到了扁平数据（调用方需落盘三级段并清掉扁平键）
; ============================================================
IniImport_ReadTableItemFlat(tableItem, filePath := "") {
    global MacroFile
    symbol := tableItem.Symbol
    if (filePath == "")
        filePath := MacroFile
    sec := IniImport_Section()
    ; 整段一次读出（Cfg_Load 只解析一次），后续取值全走内存
    kv := CfgSection(filePath, sec)

    modeArrStr := IniImport_Kv(kv, symbol "ModeArr")
    foldInfoStr := IniImport_Kv(kv, symbol "FoldInfo")
    if (modeArrStr == "" && foldInfoStr == "")
        return false

    modeArr := IniImport_SplitPi(modeArrStr)
    itemCount := modeArr.Length

    ; ---- 模块：FoldInfo → MacroFold（身份 = 路径 表ID.ModuleN）----
    ; JSON.parse(text, , false) → 普通 Object + Array；取值语法见 IniImport_ArrGet 顶部注释。
    oldFoldInfo := ""
    if (foldInfoStr != "") {
        try {
            parsed := JSON.parse(foldInfoStr, , false)
            if (IsObject(parsed) && ObjHasOwnProp(parsed, "IndexSpanArr") && IsObject(parsed.IndexSpanArr))
                oldFoldInfo := parsed
            else
                RMTLogSysInfo("配置导入", Format("  {1} FoldInfo 内容异常（无 IndexSpanArr），按单模块处理", symbol))
        } catch as e {
            ; 不静默：FoldInfo 解析失败会静默丢掉全部模块分档，必须留痕
            RMTLogSysInfo("配置导入", Format("  {1} FoldInfo 解析失败：{2}", symbol, e.Message))
            oldFoldInfo := ""
        }
    }
    folds := []
    itemFoldIdx := Map()        ; 条目下标 → 模块序号(1..n)
    if (IsObject(oldFoldInfo)) {
        spanArr := oldFoldInfo.IndexSpanArr
        loop spanArr.Length {
            f := A_Index
            fold := MacroFold()
            fold.ID := tableItem.ID "." "Module" f
            fold.Remark := IniImport_ArrGet(oldFoldInfo, "RemarkArr", f, "")
            fold.FrontInfo := IniImport_ArrGet(oldFoldInfo, "FrontInfoArr", f, "")
            fold.ForbidState := !!IniImport_ArrGet(oldFoldInfo, "ForbidStateArr", f, false)
            fold.FoldState := !!IniImport_ArrGet(oldFoldInfo, "FoldStateArr", f, false)
            fold.TKType := IniImport_ArrGet(oldFoldInfo, "TKTypeArr", f, 4)
            fold.TK := IniImport_ArrGet(oldFoldInfo, "TKArr", f, "")
            fold.HoldTime := IniImport_ArrGet(oldFoldInfo, "HoldTimeArr", f, 500)
            fold.UnorderedTrigger := !!IniImport_ArrGet(oldFoldInfo, "UnorderedTriggerArr", f, false)
            folds.Push(fold)

            spanStr := String(spanArr.Has(f) ? spanArr[f] : "")
            span := StrSplit(spanStr, "-")
            if (span.Length >= 2 && IsInteger(span[1]) && IsInteger(span[2])) {
                startIdx := Integer(span[1])
                endIdx := Integer(span[2])
                loop endIdx - startIdx + 1 {
                    idx := startIdx + A_Index - 1
                    if (idx >= 1 && idx <= itemCount)
                        itemFoldIdx[idx] := f
                }
            }
        }
    }
    ; 无有效模块（FoldInfo 缺失/损坏）→ 建一个默认模块承载全部条目，身份仍为路径
    if (folds.Length == 0) {
        fold := MacroFold()
        fold.ID := tableItem.ID "." "Module1"
        fold.Remark := GetLang("RMT默认初始化配置")
        folds.Push(fold)
    }
    RMTLogSysInfo("配置导入", Format("  展开 {1}：模块 {2} 个 / 条目 {3} 个", symbol, folds.Length, itemCount))
    tableItem.Folds := folds
    tableItem.FoldMap := Map()
    for fold in folds
        tableItem.FoldMap[fold.ID] := fold

    ; ---- 条目：按 π 数组逐项还原，身份按模块分段编号 ----
    tkArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "TKArr"))
    holdTimeArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "HoldTimeArr"))
    forbidArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "ForbidArr"))
    remarkArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "RemarkArr"))
    loopCountArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "LoopCountArr"))
    triggerTypeArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "TriggerTypeArr"))
    timingSerialArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "TimingSerialArr"))
    startTipSoundArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "StartTipSoundArr"))
    endTipSoundArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "EndTipSoundArr"))
    icoPathArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "IcoPathArr"))
    unorderedTriggerArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "UnorderedTriggerArr"))
    voiceKeywordsArr := IniImport_SplitPi(IniImport_Kv(kv, symbol "VoiceKeywordsArr"))

    tableItem.Items := []
    tableItem.ItemMap := Map()
    seqMap := Map()             ; 模块序号 → 已分配的宏序号
    loop itemCount {
        fi := itemFoldIdx.Has(A_Index) ? itemFoldIdx[A_Index] : 1
        if (fi < 1 || fi > folds.Length)
            fi := 1
        seq := (seqMap.Has(fi) ? seqMap[fi] : 0) + 1
        seqMap[fi] := seq

        item := MacroItem()
        item.ID := folds[fi].ID "." "Macro" seq
        item.FoldID := folds[fi].ID
        item.TK := IniImport_ArrAt(tkArr, A_Index, "")
        item.HoldTime := IniImport_ArrAt(holdTimeArr, A_Index, 500)
        item.Mode := IniImport_ArrAt(modeArr, A_Index, 1)
        item.Forbid := IniImport_ArrAt(forbidArr, A_Index, 0)
        item.Remark := IniImport_ArrAt(remarkArr, A_Index, "")
        item.LoopCount := IniImport_ArrAt(loopCountArr, A_Index, "1")
        item.TriggerType := IniImport_ArrAt(triggerTypeArr, A_Index, 1)
        item.TimingSerial := IniImport_ArrAt(timingSerialArr, A_Index, "")
        item.StartTipSound := IniImport_ArrAt(startTipSoundArr, A_Index, 1)
        item.EndTipSound := IniImport_ArrAt(endTipSoundArr, A_Index, 1)
        item.IcoPath := IniImport_ArrAt(icoPathArr, A_Index, "")
        ut := IniImport_ArrAt(unorderedTriggerArr, A_Index, "0")
        item.UnorderedTrigger := (ut == "1" || ut == "true")
        item.VoiceKeywords := IniImport_ArrAt(voiceKeywordsArr, A_Index, "")
        tableItem.Items.Push(item)
        tableItem.ItemMap[item.ID] := item
    }
    ; 宏内容单独键：symbol MacroArr N（⫶ 还原为换行）
    loop itemCount
        tableItem.Items[A_Index].Macro := StrReplace(IniImport_Kv(kv, symbol "MacroArr" A_Index), "⫶", "`n")

    CompatEnsureArrLength(tableItem)
    tableItem.RebuildIndex()
    return true
}

; ============================================================
; 导入期迁移：MacroFile.toml 若是扁平数组布局（旧版 INI 转换产物 / 旧分享包），
; 就地展开成三级段 TOML 并清掉已展开的扁平键，使 reload 后按三级段加载。
; 只在导入链路调用（主进程 SettingMgrGui.OnRepairSetting），须在 Compat* 补齐数组字段之后。
; 返回 true 表示发生了展开。
; ============================================================
IniImport_ExpandFlatMacroFile(settingDir) {
    tAll := A_TickCount
    if (settingDir == "")
        return false
    macroPath := settingDir "\MacroFile.toml"
    if (!FileExist(macroPath))
        return false
    ; TomlUtil 的缓存无指纹，Compat* 刚改过这个文件 → 强制重读，避免拿到批处理前的旧内容
    TomlUtil_Invalidate(macroPath)
    sec := IniImport_Section()
    kv := CfgSection(macroPath, sec)   ; 一次解析，后续判键走内存

    ; 扁平标记：任一默认表存在 <symbol>FoldInfo / <symbol>TKArr 键
    flatMark := false
    for def in CreateDefaultTableDefs() {
        if (IniImport_Kv(kv, def[1] "FoldInfo") != "" || IniImport_Kv(kv, def[1] "TKArr") != "") {
            flatMark := true
            break
        }
    }
    if (!flatMark)
        return false

    ; 旧配置无 [[table]] 表集合定义 → 用默认表骨架（Tab 顺序即默认顺序）
    tblArr := []
    for def in CreateDefaultTableDefs() {
        tb := TableItem()
        tb.ID := def[1]
        tb.Symbol := def[1]
        tb.Name := def[2]
        tb.Order := def[3]
        tblArr.Push(tb)
    }
    flatArr := []
    for tb in tblArr {
        if (IsStaticTable(tb))
            continue                        ; 工具/设置/帮助/赞助/感谢：无宏配置，不读不写
        tTb := A_TickCount
        if (!IniImport_ReadTableItemFlat(tb, macroPath))
            continue
        msTb := A_TickCount - tTb
        if (msTb > 500)                     ; 慢表单独记：旧配置条目多时便于定位
            RMTLogSysInfo("配置导入", Format("  展开 {1} 耗时 {2}ms（{3} 条宏）", tb.ID, msTb, tb.Items.Length))
        EnsureTableHasFold(tb)
        flatArr.Push(tb)
    }
    if (flatArr.Length == 0)
        return false

    tWrite := A_TickCount
    ; TomlUtil_Read 按路径缓存且无指纹 —— 必须先失效，否则可能拿到导入前的旧解析结果（会把刚写的扁平数据盖掉）
    TomlUtil_Invalidate(macroPath)
    root := TomlUtil_RootMap(macroPath)
    tableArr := []
    for tb in tblArr
        tableArr.Push(Map("id", tb.ID, "symbol", tb.Symbol, "name", tb.Name, "order", tb.Order))
    root["table"] := tableArr
    ; 只写读到扁平数据的表：其余表（如旧版没有的语音宏/网络宏）不落段，load 时按全新表初始化
    for tb in flatArr
        SaveTableItemInfoTomlCore(root, tb)
    IniImport_StripFlatKeys(root)
    TomlUtil_Write(root, macroPath)
    RMTLogSysInfo("配置导入", Format("MacroFile 扁平数组布局已展开为三级段：{1}（落盘 {2}ms，总计 {3}ms）",
        macroPath, A_TickCount - tWrite, A_TickCount - tAll))
    return true
}
