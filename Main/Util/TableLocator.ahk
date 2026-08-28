#Requires AutoHotkey v2.0
; ============================================================
; TableLocator — RMT 新定位体系核心（ID 化 + Map 索引）
; 取代基于数组下标的定位：表/条目/折叠框全部持有稳定唯一 ID，
; 跨表引用一律存 TableID + ItemID 字符串对，增删/移动不破坏引用。
; 索引挂载点：MySoftData.TableInfo（顺序数组）+ MySoftData.TableMap（TableID→TableItem）
;             + MySoftData.GlobalItemMap（ItemID→{TableID, Item}，全表唯一索引）
; ============================================================

; ===== ID 生成器 =====
; 表 ID：t_ + HHmmss + 随机 2 位（表集合独立，不进 SerialMap）
GetTableSerialStr() {
    return "t_" FormatTime(, "HHmmss") Random(10, 99)
}

; 折叠框 ID：f_ + HHmmss + 随机 2 位
GetFoldSerialStr() {
    return "f_" FormatTime(, "HHmmss") Random(10, 99)
}

; 条目 ID：复用 GetCMDSerialStr("Item")（已全局唯一登记，含时间戳+随机数）

; ===== 全局索引构建 =====
; 遍历 MySoftData.TableInfo 重建 TableMap / GlobalItemMap / 每表 ItemMap/FoldMap
; 在配置加载完成、增删表、增删条目后调用
RebuildTableLocator() {
    global MySoftData
    MySoftData.TableMap := Map()
    MySoftData.GlobalItemMap := Map()
    for tableItem in MySoftData.TableInfo {
        if (tableItem.ID == "")
            tableItem.ID := tableItem.Symbol == "" ? GetTableSerialStr() : tableItem.Symbol
        MySoftData.TableMap[tableItem.ID] := tableItem
        tableItem.RebuildIndex()
        for item in tableItem.Items {
            if (item.ID != "")
                MySoftData.GlobalItemMap[item.ID] := { TableID: tableItem.ID, Item: item }
        }
    }
}

; ===== 表查询 API =====
; 按 TableID 取表对象（无则 ""）
GetTableByID(tableID) {
    global MySoftData
    if (tableID == "")
        return ""
    return MySoftData.TableMap.Has(tableID) ? MySoftData.TableMap[tableID] : ""
}

; 按 TableID 返回表在 TableInfo 中的显示顺序下标（1 基；找不到返回 0）
GetTableIndexByID(tableID) {
    global MySoftData
    if (tableID == "")
        return 0
    for i, t in MySoftData.TableInfo {
        if (t.ID == tableID)
            return i
    }
    return 0
}

; 按表 Symbol 取第一个匹配表（无则 ""）——表可多实例同 Symbol，取第一个
GetTableBySymbol(symbol) {
    global MySoftData
    for tableItem in MySoftData.TableInfo {
        if (tableItem.Symbol == symbol)
            return tableItem
    }
    return ""
}

; 按表 Symbol 取全部匹配表数组
GetTablesBySymbol(symbol) {
    global MySoftData
    result := []
    for tableItem in MySoftData.TableInfo {
        if (tableItem.Symbol == symbol)
            result.Push(tableItem)
    }
    return result
}

; ===== 条目查询 API =====
; 按 TableID + ItemID 取条目对象（无则 ""）
GetItemByID(tableID, itemID) {
    t := GetTableByID(tableID)
    if (!t || itemID == "")
        return ""
    return t.GetItem(itemID)
}

; 按全局唯一 ItemID 取条目（跨表，依赖 GlobalItemMap；无则 ""）
GetItemGlobal(itemID) {
    global MySoftData
    if (itemID == "")
        return ""
    if (!MySoftData.GlobalItemMap.Has(itemID))
        return ""
    return MySoftData.GlobalItemMap[itemID].Item
}

; 按全局唯一 ItemID 取条目所在表（跨表；无则 ""）
GetItemTableGlobal(itemID) {
    global MySoftData
    if (itemID == "")
        return ""
    if (!MySoftData.GlobalItemMap.Has(itemID))
        return ""
    return GetTableByID(MySoftData.GlobalItemMap[itemID].TableID)
}

; ===== 折叠框查询 API =====
; 按 TableID + FoldID 取折叠框对象（无则 ""）
GetFoldByID(tableID, foldID) {
    t := GetTableByID(tableID)
    if (!t || foldID == "")
        return ""
    return t.GetFold(foldID)
}

; ===== 顺序/数组辅助 =====
; 条目对象 → 在表内顺序下标（1 基；找不到返回 0）
GetItemIndexInTable(tableItem, itemID) {
    if (!tableItem || itemID == "")
        return 0
    for i, item in tableItem.Items {
        if (item.ID == itemID)
            return i
    }
    return 0
}

; 折叠框对象 → 在表内顺序下标（1 基；找不到返回 0）
GetFoldIndexInTable(tableItem, foldID) {
    if (!tableItem || foldID == "")
        return 0
    for i, fold in tableItem.Folds {
        if (fold.ID == foldID)
            return i
    }
    return 0
}

; 折叠框内所有条目（按表内顺序；返回数组，空则 []）
GetFoldItems(tableItem, fold) {
    result := []
    if (!tableItem || !fold)
        return result
    for item in tableItem.Items {
        if (item.FoldID == fold.ID)
            result.Push(item)
    }
    return result
}

; ===== 表集合操作 =====
; 新增表（默认插到末尾），返回新 TableItem
; 表 ID 固定 = 表类型 Symbol（分发版表集合固定，Symbol 即身份；同名 Symbol 追加序号避免冲突）
AddTable(symbol, name := "") {
    global MySoftData
    t := TableItem()
    t.Symbol := symbol
    t.ID := symbol
    n := 1
    while (GetTableByID(t.ID) != "") {
        n += 1
        t.ID := symbol "_" n
    }
    t.Name := (name == "") ? symbol : name
    t.Order := MySoftData.TableInfo.Length + 1
    MySoftData.TableInfo.Push(t)
    RebuildTableLocator()
    return t
}

; 删除表（按 TableID），同时清理全局索引
RemoveTable(tableID) {
    global MySoftData
    for i, tableItem in MySoftData.TableInfo {
        if (tableItem.ID == tableID) {
            MySoftData.TableInfo.RemoveAt(i)
            RebuildTableLocator()
            return true
        }
    }
    return false
}

; 表改名（按 TableID）
RenameTable(tableID, newName) {
    t := GetTableByID(tableID)
    if (!t)
        return false
    t.Name := newName
    return true
}

; ===== 条目操作（表内） =====
; 表内新增条目（插到末尾），返回新 MacroItem
; 路径身份：item.FoldID 需先设为父模块路径（tableID.ModuleN），否则用 fallbackFoldSeg；item.ID = foldSeg.Macro{max+1}
AddTableItem(tableItem, item := "", fallbackFoldSeg := "") {
    if (!item)
        item := MacroItem()
    if (item.ID == "") {
        parentSeg := (item.FoldID != "") ? item.FoldID : fallbackFoldSeg
        if (parentSeg != "")
            item.ID := NewMacroPath(tableItem, parentSeg)
        else
            item.ID := GetCMDSerialStr("Item")   ; 兜底（无模块归属时退回序列号，正常流程应有模块）
    }
    tableItem.Items.Push(item)
    tableItem.RebuildIndex()
    RebuildTableLocator()
    return item
}

; 表内按 ItemID 删除条目
RemoveTableItem(tableItem, itemID) {
    for i, item in tableItem.Items {
        if (item.ID == itemID) {
            tableItem.Items.RemoveAt(i)
            tableItem.RebuildIndex()
            RebuildTableLocator()
            return true
        }
    }
    return false
}

; 表内移动条目：fromItemID 移到 toItemID 之后（toItemID 为空则移到末尾）
MoveTableItem(tableItem, fromItemID, toItemID := "") {
    fromIdx := GetItemIndexInTable(tableItem, fromItemID)
    if (!fromIdx)
        return false
    item := tableItem.Items[fromIdx]
    tableItem.Items.RemoveAt(fromIdx)
    if (toItemID == "") {
        tableItem.Items.Push(item)
    } else {
        toIdx := GetItemIndexInTable(tableItem, toItemID)
        if (!toIdx) {
            tableItem.Items.Push(item)
        } else {
            tableItem.Items.InsertAt(toIdx + 1, item)
        }
    }
    tableItem.RebuildIndex()
    RebuildTableLocator()
    return true
}

; ===== 折叠框操作（表内） =====
; 表内新增折叠框，返回 MacroFold
; 路径身份：fold.ID = tableID.Module{max+1}
AddTableFold(tableItem, fold := "") {
    if (!fold)
        fold := MacroFold()
    if (fold.ID == "")
        fold.ID := NewModulePath(tableItem)
    tableItem.Folds.Push(fold)
    tableItem.RebuildIndex()
    return fold
}

; 表内按 FoldID 删除折叠框（同时清空归属条目的 FoldID）
RemoveTableFold(tableItem, foldID) {
    for i, fold in tableItem.Folds {
        if (fold.ID == foldID) {
            tableItem.Folds.RemoveAt(i)
            for item in tableItem.Items {
                if (item.FoldID == foldID)
                    item.FoldID := ""
            }
            tableItem.RebuildIndex()
            return true
        }
    }
    return false
}

; ===== 旧格式兼容辅助（迁移期） =====
; 旧格式：条目归属由 FoldInfo.IndexSpanArr（"起始-结束" 下标范围）表达。
; 迁移：把每个折叠框的 IndexSpan 转成 FoldID，条目按范围内下标分配 FoldID。
; 入参 oldFoldInfo（ItemFoldInfo，JSON.parse 结果），返回 [foldsArr, itemFoldIDArr]
MigrateIndexSpanToFoldID(oldFoldInfo, itemCount) {
    itemFoldIDArr := Array(itemCount + 1)
    loop itemCount
        itemFoldIDArr[A_Index] := ""
    foldsArr := []
    if (!IsObject(oldFoldInfo) || !oldFoldInfo.HasOwnProp("IndexSpanArr"))
        return [foldsArr, itemFoldIDArr]

    for f, spanStr in oldFoldInfo.IndexSpanArr {
        fold := MacroFold()
        fold.ID := GetFoldSerialStr()
        fold.Remark := oldFoldInfo.HasOwnProp("RemarkArr") && oldFoldInfo.RemarkArr.Has(f) ? oldFoldInfo.RemarkArr[f] : ""
        fold.FrontInfo := oldFoldInfo.HasOwnProp("FrontInfoArr") && oldFoldInfo.FrontInfoArr.Has(f) ? oldFoldInfo.FrontInfoArr[f] : ""
        fold.ForbidState := oldFoldInfo.HasOwnProp("ForbidStateArr") && oldFoldInfo.ForbidStateArr.Has(f) ? !!oldFoldInfo.ForbidStateArr[f] : false
        fold.FoldState := oldFoldInfo.HasOwnProp("FoldStateArr") && oldFoldInfo.FoldStateArr.Has(f) ? !!oldFoldInfo.FoldStateArr[f] : false
        fold.TKType := oldFoldInfo.HasOwnProp("TKTypeArr") && oldFoldInfo.TKTypeArr.Has(f) ? oldFoldInfo.TKTypeArr[f] : 4
        fold.TK := oldFoldInfo.HasOwnProp("TKArr") && oldFoldInfo.TKArr.Has(f) ? oldFoldInfo.TKArr[f] : ""
        fold.HoldTime := oldFoldInfo.HasOwnProp("HoldTimeArr") && oldFoldInfo.HoldTimeArr.Has(f) ? oldFoldInfo.HoldTimeArr[f] : 500
        fold.UnorderedTrigger := oldFoldInfo.HasOwnProp("UnorderedTriggerArr") && oldFoldInfo.UnorderedTriggerArr.Has(f) ? !!oldFoldInfo.UnorderedTriggerArr[f] : false

        span := StrSplit(spanStr, "-")
        if (IsInteger(span[1]) && IsInteger(span[2])) {
            start := Integer(span[1])
            end := Integer(span[2])
            if (end > itemCount)
                end := itemCount
            loop end - start + 1 {
                idx := start + A_Index - 1
                if (idx >= 1 && idx <= itemCount)
                    itemFoldIDArr[idx] := fold.ID
            }
        }
        foldsArr.Push(fold)
    }
    return [foldsArr, itemFoldIDArr]
}
