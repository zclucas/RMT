InitTableItemState() {
    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        InitSingleTableState(tableItem)
    }

    tableItem := MySoftData.SpecialTableItem
    if (tableItem.Items.Length == 0) {
        item := MacroItem()
        item.ID := GetCMDSerialStr("Item")
        tableItem.Items.Push(item)
        tableItem.RebuildIndex()
    }
    InitSingleTableState(tableItem)
}

; 运行时状态随条目对象初始化（每条目一个状态，增删条目不破坏其它条目）
InitSingleTableState(tableItem) {
    ; 内置控制键统一默认值（缺失才补，兼容已有运行态映射）
    static CtlKeys := Map(
        "宏循环次数", 0,
        "循环-跳过本轮", false,
        "循环-跳出", false,
        "分支-跳出", false
    )
    for item in tableItem.Items {
        if (!item.HoldKey)
            item.HoldKey := Map()
        ; 注意：空 Map() 也是真值，不能只用 !item.VariableMap 判断缺失键
        if (!ObjHasOwnProp(item, "VariableMap"))   ;属性未创建
            item.VariableMap := Map()
        for key, def in CtlKeys {
            if (!item.VariableMap.Has(key))
                item.VariableMap[key] := def
        }
    }
}

KillSingleTableMacro(tableItem) {
    for index, item in tableItem.Items {
        KillTableItemMacro(tableItem, index)
    }
}

; 松开宏项仍按住的按键（不修改 Killed）
ReleaseTableItemHoldKeys(tableItem, index) {
    item := GetItemByIndex(tableItem, index)
    if (!item || !item.HoldKey || item.HoldKey.Count == 0)
        return
    HoldKeyMap := item.HoldKey.Clone()
    GraphPoolLog("ReleaseHoldKeys", Format("tab={1} item={2} count={3} keys=[{4}]"
        , tableItem.ID, item.ID, HoldKeyMap.Count, HoldKeyMap.Count ? "..." : ""))
    for key, value in HoldKeyMap {
        if (value == "Game") {
            SendGameModeKey(key, 0, tableItem, index)
        }
        else if (value == "Normal") {
            SendNormalKey(key, 0, tableItem, index)
        }
        else if (value == "BGKey") {
            target := StrSplit(key, ":", , 3)
            SendBGKeyState(target[2], target[3], 0, tableItem, index)
        }
        else if (SubStr(value, 1, 8) == "BGMouse:") {
            target := StrSplit(key, ":", , 3)
            try SendBGMouseButton(target[2], Integer(target[3]), false, Integer(SubStr(value, 9)), tableItem, index)
        }
        else if (value == "Logic") {
            SendLogicKey(key, 0, tableItem, index)
        }
        else if (SubStr(value, 1, 7) == "VIIPER:") {
            ReleaseViiperKey(key, value, tableItem, index)
        }
        else if (value == "AHI") {
            SendAHIKey(key, 0, tableItem, index)
        }
        else if (value == "Joy") {
            SendJoyBtnKey(key, 0, tableItem, index)
        }
        else if (value == "JoyAxis") {
            SendJoyAxisKey(key, 0, tableItem, index)
        }
        else if (value == "JoyAxisValue") {
            ; 连续轴指令（JoyAxisLX/LY/RX/RY/LT/RT + 轴值）被中断/停止：回中/归零到 0
            SendJoyAxisValueKey(key, 0, 0, tableItem, index)
        }
        else if (value == "JoyDpad") {
            SendJoyDpadKey(key, 0, tableItem, index)
        }
        else if (value == "GameMouse") {
            SendGameMouseKey(key, 0, tableItem, index)
        }
    }
    item.HoldKey := Map()
}

; Worker 同步过来的按键按住状态（供主进程强杀后松开）
; Worker 同步按键按住状态（供主进程强杀后松开）：tableID/itemID 字符串
SyncWorkerHoldKey(tableID, itemID, key, state, source := "") {
    tableItem := GetTableByID(String(tableID))
    if (!tableItem)
        return
    itemIndex := GetItemIndexInTable(tableItem, String(itemID))
    item := GetItemByIndex(tableItem, itemIndex)
    if (!item || !item.HoldKey)
        return
    bucket := item.HoldKey
    if (Integer(state)) {
        if (source != "")
            bucket[key] := source
    } else if (bucket.Has(key)) {
        bucket.Delete(key)
    }
}

KillTableItemMacro(tableItem, index) {
    item := GetItemByIndex(tableItem, index)
    if (!item)
        return
    GraphPoolLog("KillTableItemMacro", Format("tab={1} item={2} trig={3}", tableItem.ID, item.ID
        , item.TriggerType))
    item.Killed := true
    ReleaseTableItemHoldKeys(tableItem, index)

    ; 如果是开关型按键宏，重置其开关状态
    if (item.TriggerType == 4) {
        item.ToggleState := false
    }
}

GetTabHeight() {
    maxY := 0
    loop MySoftData.TableInfo.Length {
        posY := MySoftData.TableInfo[A_Index].UnderPosY
        if (posY > maxY)
            maxY := posY
    }

    height := maxY - MainSoftData.TabPosY
    return height
    ; return Max(height, 500)
}

UpdateUnderPosY(tableIndex, value) {
    table := MySoftData.TableInfo[tableIndex]
    table.UnderPosY += value
}

GetTableSymbol(index) {
    global MySoftData
    t := MySoftData.TableInfo[index]
    return t ? t.Symbol : ""
}

; 按表 Symbol 返回第一个匹配表的显示顺序下标（1 基；找不到返回 0）
GetTimingTableIndex() {
    global MySoftData
    for i, t in MySoftData.TableInfo {
        if (t.Symbol == "Timing")
            return i
    }
    return ""
}

; 按 Symbol 或表名返回显示顺序下标（1 基；找不到返回 0）
GetTableIndex(SymbolOrName) {
    global MySoftData
    for i, t in MySoftData.TableInfo {
        if (SymbolOrName == t.Name || SymbolOrName == t.Symbol)
            return i
    }
    return 0
}

; 判断某个 Symbol 是否为参与宏的条目类型（与 CheckIsItemTable(index) 同集合，但直接按 Symbol 判定，
; 不依赖 tableItem.Index 走 GetTableIndexByID 的定位，避免在表集合尚未完全构建／表索引错位时误判）。
IsItemSymbol(symbol) {
    if (symbol == "Normal")
        return true
    if (symbol == "String")
        return true
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "Replace")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    if (symbol == "Network")
        return true
    return false
}

; 是否静态/非配置表（Tool/Setting/Help/Reward/Thank 等 非 CheckIsItemSymbol）：不参与宏配置。
; 用于 ReadTableItemInfo / SaveTableItemInfo / EnsureTableHasFold 在读写入口统一短路。
IsStaticTable(tableItem) {
    if (!IsObject(tableItem) || !tableItem.HasProp("Symbol"))
        return true
    return !IsItemSymbol(tableItem.Symbol)
}

CheckIsNormalTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Normal")
        return true
    return false
}

CheckIsItemTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Normal")
        return true
    if (symbol == "String")
        return true
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "Replace")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    if (symbol == "Network")
        return true
    return false
}

CheckIsMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Normal")
        return true
    if (symbol == "String")
        return true
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    if (symbol == "Network")
        return true
    return false
}

CheckIsStringMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "String")
        return true
    return false
}

CheckIsTimingMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Timing")
        return true
    return false
}

CheckIsMenuMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Menu")
        return true
    return false
}

InitArray(tableItem, arrName) {
    if (!tableItem.HasProp(arrName)) {
        tableItem.%arrName% := []
    }
}

CheckIsNoTriggerKey(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    return false
}

CheckIsSubMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "SubMacro")
        return true
    return false
}
