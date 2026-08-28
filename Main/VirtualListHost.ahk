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
    }

    EnsureEvents(t) {
        if (this._registered.Has(t))
            return
        this._registered[t] := true
        listName := "FoldList_" t
        this._ui.OnEvent(listName, "VL_CLICK", ObjBindMethod(this, "_OnVLClick", t))
        this._ui.OnEvent(listName, "VL_CHANGE", ObjBindMethod(this, "_OnVLChange", t))
        this._ui.OnEvent(listName, "VL_COMMIT_ALL", ObjBindMethod(this, "_OnVLCommitAll", t))
    }

    Init(t, tableItem) {
        this.EnsureEvents(t)
        this._ui.Update("FoldList_" t, "VL_INIT", this._BuildRecords(t, tableItem))
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
        this._ui.Update("FoldList_" t, "VL_ROW", val)
    }

    UpdateColor(t, i) {
        this.RefreshRow(t, i)   ; 全行刷新（1 IPC），含颜色点；旧版仅刷色点，虚拟化下合并更省
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
                    . RS
            }
        }
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
        tableItem := MySoftData.TableInfo[t]
        idx := Integer(SubStr(id, InStr(id, "_", , 2) + 1))
        if (SubStr(id, 1, 1) == "R") {
            switch action {
                case "TKBtn": this._EditTK(tableItem, idx, event)
                case "TKBtnR": OnItemCustomEditTriggerStr(tableItem, idx, event)
                case "Setting": OnItemEditMacroSetting(tableItem, idx, event)
                case "Edit":
                    (CheckIsMacroTable(t) ? OnItemEditMacro : OnItemEditReplaceKey)(tableItem, idx, event)
                case "Pre": OnItemMoveUp(tableItem, idx, event)
                case "Next": OnItemMoveDown(tableItem, idx, event)
                case "Copy": OnItemCopyMacroBtnClick(tableItem, idx, event)
                case "Del": OnItemDelMacroBtnClick(tableItem, idx, event)
            }
        }
        else {
            switch action {
                case "FoldBtn": OnFoldBtnClick(tableItem, idx, event)
                case "FoldFrontBtn": OnFoldFrontInfoEdit(tableItem, idx, event)
                case "FoldAdd": OnItemAddMacroBtnClick(tableItem, idx, event)
                case "FoldPaste": OnItemPasteMacroBtnClick(tableItem, idx, event)
                case "FoldAddMod": OnItemAddFoldBtnClick(tableItem, idx, event)
                case "FoldDelMod": OnItemDelFoldBtnClick(tableItem, idx, event)
                case "FoldTKEdit": OnFlodTKEditClick(tableItem, idx, event)
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
                case "FoldFront": fold.FrontInfo := value
                case "FoldTKType": fold.TKType := Integer(value) + 1
                case "FoldForbid": fold.ForbidState := (value == "1")
                case "FoldTK": fold.TK := value
            }
        }
    }
}
