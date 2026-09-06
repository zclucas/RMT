#Requires AutoHotkey v2.0

; VL 协议分隔符：字段 \x1F(US)、行 \x1E(RS)（用户文本几乎不可能含的控制字符）
global US := Chr(0x1F), RS := Chr(0x1E)

; ============================================================================
; 主窗口宏列表虚拟化宿主（Epic5）
; 桥接命令见 XAML_AHK_Bridge.cs 的 VirtualListHost 类：
;   VL_INIT  (1 IPC 全量) / VL_ROW (单行) / VL_FOLD / VL_MOVE / VL_COMMIT_ALL
; 事件回传经 XAMLHost.OnEvent(listName, "VL_CLICK"/"VL_CHANGE"/"VL_COMMIT_ALL")。
; 字段分隔 \x1F(US)、行分隔 \x1E(RS)；ID 约定 行 R<t>_<i>、折叠头 F<t>_<f>。
; 模型 SSOT：VL_CHANGE/COMMIT_ALL 写回模型数组，视图是可丢弃投影。
; ============================================================================

class VirtualListHost {
    __New(ui) {
        this._ui := ui
        this._registered := Map()
        this._vlFonts := Map()
    }

    EnsureEvents(t) {
        if (this._registered.Has(t))
            return
        this._registered[t] := true
        listName := "FoldList_" t
        this._ui.OnEvent(listName, "VL_CLICK", ObjBindMethod(this, "_OnVLClick", t))
        this._ui.OnEvent(listName, "VL_CHANGE", ObjBindMethod(this, "_OnVLChange", t))
        this._ui.OnEvent(listName, "VL_COMMIT_ALL", ObjBindMethod(this, "_OnVLCommitAll", t))
        this._ui.OnEvent(listName, "VL_DROP", ObjBindMethod(this, "_OnVLDrop", t))
    }

    ; 离开 VL_CLICK 后再弹窗；fn 必须是 BoundFunc 且保存在 this，否则 AHK 可能丢掉定时器
    _DeferDialog(tag, fn) {
        try RmtDialog._Trace("VL defer " tag)
        this._dlgFn := fn
        SetTimer(this._dlgFn, -50)
    }

    Init(t, tableItem, refreshFonts := "") {
        this.EnsureEvents(t)
        this._ui.Update("FoldList_" t, "VL_INIT", this._BuildRecords(t, tableItem))
        ; 只在本窗第一次 VL 填充时刷字号。每个页签首切都 ApplyFonts 会整窗重测，切页偶发抖动
        doFonts := refreshFonts == "" ? !this._vlFonts.Has(0) : refreshFonts
        if (doFonts) {
            this._vlFonts[0] := true
            this._vlFonts[t] := true
            try MyMainWin.RefreshVLFonts()
        }
        try MyMainWin.RefreshSideTree(t)
    }

    Relayout(t) {
        this.EnsureEvents(t)
        this._ui.Update("FoldList_" t, "VL_RELAYOUT", "")
    }

    SetRowSel(t, i) {
        this.EnsureEvents(t)
        this._ui.Update("FoldList_" t, "VL_SEL", (i >= 1) ? ("R" t "_" i) : "")
    }

    ; 仅刷新模块禁用态，避免 VL_INIT 全量重建导致字号回落
    UpdateFoldForbid(t, f, forbidState) {
        this.EnsureEvents(t)
        this._ui.Update("FoldList_" t, "VL_FF", "F" t "_" f US (forbidState ? "1" : "0"))
    }

    ; 单行刷新：增量更新 VM（不可见行由 C# no-op），滚动/折叠态天然保留
    ; 续行须行首 `.`（操作符），变量 US 行首不触发 AHK 续行
    RefreshRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        item := tableItem.Items[i]
        val := "R" t "_" i
            . US . this._Esc(item.Remark)
            . US . this._Esc(this._TKStr(tableItem, i, t))
            . US . this._TKType(tableItem, i, t)
            . US . this._Esc(this._Loop(tableItem, i))
            . US . (item.Forbid ? "1" : "0")
            . US . this._Color(tableItem, i)
            . US . String(GetMacroEditKind(item.Macro))
        this._ui.Update("FoldList_" t, "VL_ROW", val)
    }

    UpdateColor(t, i) {
        this.RefreshRow(t, i)   ; 全行刷新（1 IPC），含颜色点；旧版仅刷色点，虚拟化下合并更省
    }

    SetCompact(t, compact) {
        this.EnsureEvents(t)
        this._ui.Update("FoldList_" t, "VL_COMPACT", compact ? "1" : "0")
    }

    FoldToggle(t, f, folded) {
        this._ui.Update("FoldList_" t, "VL_FOLD", "F" t "_" f US (folded ? "1" : "0"))
    }

    MoveRow(t, iA, iB) {
        this._ui.Update("FoldList_" t, "VL_MOVE", "R" t "_" iA US "R" t "_" iB)
    }

    ; 保存兜底：实体化行全字段提交（覆盖纯键盘后未失焦路径）
    CommitAll(t) {
        this._ui.Update("FoldList_" t, "VL_COMMIT_ALL", "")
    }

    ; ============ VL_INIT 数据构建 ============
    _BuildRecords(t, tableItem) {
        isMacro := CheckIsMacroTable(t)
        isNormal := CheckIsNormalTable(t)
        isSubMacro := CheckIsSubMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        ; 表类型标志行（per tab 恒定，C# 按此设行控件 IsEnabled）
        records := "T" t "_0"
            . US . (isSubMacro ? "0" : "1")
            . US . (isNormal ? "1" : "0")
            . US . (isMacro ? "1" : "0")
            . US . (isUI ? "0" : "1")
            . RS
        showTKRow := (isMenu || isUI) ? "1" : "0"
        for f, fold in tableItem.Folds {
            records .= "F" t "_" f
                . US . this._Esc(fold.Remark)
                . US . this._Esc(fold.FrontInfo)
                . US . (fold.ForbidState ? "1" : "0")
                . US . (fold.TKType - 1)
                . US . this._Esc(fold.TK)
                . US . (fold.FoldState ? "1" : "0")
                . US . showTKRow
                . RS
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                records .= "R" t "_" i
                    . US . this._Esc(item.Remark)
                    . US . this._Esc(this._TKStr(tableItem, i, t))
                    . US . this._TKType(tableItem, i, t)
                    . US . this._Esc(this._Loop(tableItem, i))
                    . US . (item.Forbid ? "1" : "0")
                    . US . this._Color(tableItem, i)
                    . US . (i ".")
                    . US . String(GetMacroEditKind(item.Macro))
                    . RS
            }
        }
        records .= "A" t "_0" . RS
        return records
    }

    _TKStr(tableItem, i, t) {
        item := tableItem.Items[i]
        isTiming := CheckIsTimingMacroTable(t)
        if (GetTableSymbol(t) == "Voice") {
            ; 语音宏：触发键列显示唤醒词
            tkStr := item.VoiceKeywords
            return tkStr == "" ? GetLang("编辑") : tkStr
        }
        tkStr := isTiming ? GetLang("定时") : FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
        if (tkStr == "" && CheckIsNormalTable(t))
            return ""
        return tkStr == "" ? GetLang("编辑") : tkStr
    }

    _TKType(tableItem, i, t) {
        item := tableItem.Items[i]
        isUI := GetTableSymbol(t) == "UI"
        return isUI ? "3" : (item.TriggerType - 1)
    }

    _Loop(tableItem, i) {
        return tableItem.Items[i].LoopCount == "-1" ? GetLang("无限") : tableItem.Items[i].LoopCount
    }

    _Color(tableItem, i) {
        cs := tableItem.Items[i].ColorState
        return cs == 1 ? "#2E7D32" : cs == 2 ? "#F9A825" : cs == 3 ? "#C62828" : "Transparent"
    }

    ; 分隔符 US/RS 是控制字符，用户文本几乎不可能含；仅剔除以防极端损坏配置错位
    _Esc(s) {
        return StrReplace(StrReplace(s, US, ""), RS, "")
    }

    ; ============ 事件分发 ============
    _OnVLClick(t, state, ctrl, event) {
        payload := state["VL_CLICK"]
        if (payload == "")
            return
        p := StrSplit(payload, US)
        if (p.Length < 2)
            return
        id := p[1], action := p[2]
        try RmtDialog._Trace("VL_CLICK id=" id " action=" action)
        tableItem := MySoftData.TableInfo[t]
        if (SubStr(id, 1, 1) == "A") {
            OnItemAddFoldBtnClick(tableItem, tableItem.Folds.Length, event)
            return
        }
        idx := Integer(SubStr(id, InStr(id, "_", , 2) + 1))
        if (SubStr(id, 1, 1) == "R") {
            if (IsObject(MyMainWin) && (action == "Select" || action == "Field"))
                MyMainWin.SelectSideTreeItem(t, idx, action == "Select")
            else if (IsObject(MyMainWin) && action != "Setting")
                MyMainWin.SelectSideTreeItem(t, idx, false)
            switch action {
                case "TKBtn": this._EditTK(tableItem, idx, event)
                case "TKBtnR": OnItemCustomEditTriggerStr(tableItem, idx, event)
                case "Setting":
                    if (IsObject(MyMainWin))
                        MyMainWin.SelectSideTreeItem(t, idx, false, true)
                    OnItemEditMacroSetting(tableItem, idx, event)
                case "Edit":
                    (CheckIsMacroTable(t) ? OnItemEditMacro : OnItemEditReplaceKey)(tableItem, idx, event)
                case "Forbid": OnItemForbidToggle(tableItem, idx, event)
                ; 复制/删除会弹 XAML 窗；必须离开 VL_CLICK/WM_COPYDATA 后再弹。
                ; BoundFunc 挂在 this 上，避免匿名闭包被回收导致定时器不触发（点了没反应、也没日志）。
                case "Copy": this._DeferDialog("Copy", OnItemCopyMacroBtnClick.Bind(tableItem, idx))
                case "Del": this._DeferDialog("Del", OnItemDelMacroBtnClick.Bind(tableItem, idx))
            }
        }
        else {
            switch action {
                case "FoldBtn": OnFoldBtnClick(tableItem, idx, event)
                case "FoldFrontBtn": OnFoldFrontInfoEdit(tableItem, idx, event)
                case "FoldTKEdit": OnFlodTKEditClick(tableItem, idx, event)
                case "FoldAddMacro": OnItemAddMacroBtnClick(tableItem, idx, event)
                case "FoldPasteMacro": OnItemPasteMacroBtnClick(tableItem, idx, event)
                case "FoldForbidBtn": OnFoldForbidToggleClick(tableItem, idx, event)
                case "FoldDel": this._DeferDialog("FoldDel", OnItemDelFoldBtnClick.Bind(tableItem, idx))
            }
        }
    }

    ; 触发键按钮分发表类型（复刻旧 _BindItemRow）
    _EditTK(tableItem, i, event) {
        t := tableItem.Index
        if (CheckIsStringMacroTable(t))
            OnItemEditTriggerStr(tableItem, i, event)
        else if (CheckIsTimingMacroTable(t))
            OnItemEditTiming(tableItem, i, event)
        else if (CheckIsMenuMacroTable(t))
            OnItemMenuMacroSettingClick(tableItem, i, event)
        else if (GetTableSymbol(t) == "UI")
            OnUIMacroSettingClick(tableItem, i, event)
        else if (GetTableSymbol(t) == "Voice")
            OnItemVoiceTriggerSetting(tableItem, i, event)   ; 语音宏：触发编辑弹窗填唤醒词
        else
            OnItemEditTriggerKey(tableItem, i, event)
    }

    _OnVLChange(t, state, ctrl, event) {
        payload := state["VL_CHANGE"]
        if (payload == "")
            return
        p := StrSplit(payload, US)
        if (p.Length < 3)
            return
        this._ApplyChange(MySoftData.TableInfo[t], p[1], p[2], p[3])
    }

    _OnVLCommitAll(t, state, ctrl, event) {
        tableItem := MySoftData.TableInfo[t]
        for k, v in state {
            if (k == "VL_COMMIT_ALL" || !(k ~= "^\d+$") || v == "")
                continue
            p := StrSplit(v, US)
            if (p.Length >= 3)
                this._ApplyChange(tableItem, p[1], p[2], p[3])
        }
    }

    ; §11 拖拽落点：srcId\x1FtgtId\x1F0前|1后
    ; 决策：宏可跨模块迁移；模块只能模块间迁移。模型变更后整表 VL_INIT 重建（低频，O(1) IPC）
    _OnVLDrop(t, state, ctrl, event) {
        payload := state["VL_DROP"]
        if (payload == "")
            return
        p := StrSplit(payload, US)
        if (p.Length < 3)
            return
        srcId := p[1], tgtId := p[2], before := p[3] == "0"
        tableItem := MySoftData.TableInfo[t]
        srcIsFold := SubStr(srcId, 1, 1) == "F"
        tgtIsFold := SubStr(tgtId, 1, 1) == "F"
        tgtIsAdd := SubStr(tgtId, 1, 1) == "A"
        srcIdx := Integer(SubStr(srcId, InStr(srcId, "_", , 2) + 1))
        tgtIdx := tgtIsAdd ? tableItem.Folds.Length : Integer(SubStr(tgtId, InStr(tgtId, "_", , 2) + 1))
        try {
            if (tgtIsAdd) {
                if (srcIsFold)
                    this.MoveFoldInTable(tableItem, srcIdx, tableItem.Folds.Length, false)
                else if (tableItem.Folds.Length >= 1)
                    this.MoveItemToFold(tableItem, srcIdx, tableItem.Folds[tableItem.Folds.Length].ID, "tail")
            } else if (srcIsFold && tgtIsFold) {
                ; 模块间迁移
                this.MoveFoldInTable(tableItem, srcIdx, tgtIdx, before)
            } else if (srcIsFold && !tgtIsFold) {
                ; 模块拖到宏行：移到目标宏所在模块前/后
                tgtFoldIdx := GetFoldIndexInTable(tableItem, tableItem.Items[tgtIdx].FoldID)
                if (tgtFoldIdx >= 1)
                    this.MoveFoldInTable(tableItem, srcIdx, tgtFoldIdx, before)
            } else if (!srcIsFold && tgtIsFold) {
                ; 宏移入目标模块（模块首/尾）
                this.MoveItemToFold(tableItem, srcIdx, tableItem.Folds[tgtIdx].ID, before ? "head" : "tail")
            } else {
                ; 宏行 → 宏行：同模块排序或跨模块迁移
                this.MoveItemTo(tableItem, srcIdx, tgtIdx, before)
            }
            tableItem.RebuildIndex()
            RebuildTableLocator()
            this.Init(t, tableItem, false)
            ; §17 热重载：拖拽移动宏/模块改变索引 → 重绑触发键（防热键闭包数字索引错位误触发）
            HotReloadPublish(t, 0)
        } catch as e {
        }
    }

    ; 模块移动（Folds 数组移动，宏 FoldID 引用不变；toFoldIdx 为移动前下标）
    MoveFoldInTable(tableItem, fromFoldIdx, toFoldIdx, before) {
        fold := tableItem.Folds[fromFoldIdx]
        tableItem.Folds.RemoveAt(fromFoldIdx)
        if (toFoldIdx > fromFoldIdx)
            toFoldIdx--
        if (toFoldIdx < 1)
            toFoldIdx := 1
        pos := before ? toFoldIdx : (toFoldIdx + 1)
        tableItem.Folds.InsertAt(pos, fold)
    }

    ; 宏移动：Items[fromIdx] 移到 Items[tgtIdx] 前/后（目标宏的模块；跨模块时改 FoldID）
    MoveItemTo(tableItem, fromIdx, tgtIdx, before) {
        if (fromIdx == tgtIdx)
            return
        dest := before ? tgtIdx : (tgtIdx + 1)
        adjDest := dest
        if (fromIdx < dest)
            adjDest--
        if (adjDest == fromIdx)
            before := !before
        item := tableItem.Items[fromIdx]
        tgtItem := tableItem.Items[tgtIdx]
        targetFoldID := tgtItem.FoldID
        tableItem.Items.RemoveAt(fromIdx)
        if (tgtIdx > fromIdx)
            tgtIdx--
        item.FoldID := targetFoldID
        pos := before ? tgtIdx : (tgtIdx + 1)
        if (pos < 1)
            pos := 1
        tableItem.Items.InsertAt(pos, item)
    }

    ; 宏移入指定模块（posMode: head=模块首 tail=模块尾）
    MoveItemToFold(tableItem, fromIdx, toFoldID, posMode) {
        item := tableItem.Items[fromIdx]
        tableItem.Items.RemoveAt(fromIdx)
        item.FoldID := toFoldID
        if (posMode == "tail") {
            ; 尾部：目标模块最后一个条目后；模块空则按 Folds 顺序定位
            pos := tableItem.Items.Length + 1
            foldIdx := GetFoldIndexInTable(tableItem, toFoldID)
            for i, it in tableItem.Items {
                itFoldIdx := GetFoldIndexInTable(tableItem, it.FoldID)
                if (it.FoldID == toFoldID)
                    pos := i + 1
                else if (itFoldIdx >= 1 && itFoldIdx > foldIdx)
                    break   ; 遇后续模块第一条目：停在其前（即目标模块尾）
            }
        } else {
            ; head：目标模块第一个条目前；模块空则插到该模块位置（Folds 顺序）
            pos := tableItem.Items.Length + 1
            foldIdx := GetFoldIndexInTable(tableItem, toFoldID)
            for i, it in tableItem.Items {
                itFoldIdx := GetFoldIndexInTable(tableItem, it.FoldID)
                if (it.FoldID == toFoldID) {
                    pos := i
                    break
                }
                if (itFoldIdx >= 1 && itFoldIdx > foldIdx) {
                    pos := i
                    break
                }
            }
        }
        tableItem.Items.InsertAt(pos, item)
    }

    ; 字段 → 模型映射（对象化，与旧 ReadTabValues 一致）
    _ApplyChange(tableItem, id, field, value) {
        idx := Integer(SubStr(id, InStr(id, "_", , 2) + 1))
        if (SubStr(id, 1, 1) == "R") {
            item := tableItem.Items[idx]
            if (!item)
                return
            switch field {
                case "Remark": item.Remark := value
                case "TKType": item.TriggerType := Integer(value) + 1
                case "Loop": item.LoopCount := (value == GetLang("无限")) ? "-1" : value
                case "Forbid": item.Forbid := (value == "1")
            }
        }
        else {
            fold := tableItem.Folds[idx]
            if (!fold)
                return
            switch field {
                case "FoldRemark": fold.Remark := value
                case "FoldTKType": fold.TKType := Integer(value) + 1
                case "FoldTK": fold.TK := value
            }
        }
        ; §18 宏表字段编辑即时持久化 + 热重载：任何字段变更（含 Remark/TKType/Loop 等）
        ; → 立即落盘 + 广播（触发键重绑/语音重建/定时重建/UI宏刷新 + Worker CF），
        ; 与折叠头 FoldTK 同生效链路，不必等保存选「否」；禁用/触发键/窗口条件即时生效
        HotReloadPublish(GetTableIndexByID(tableItem.ID), 0)
    }
}
