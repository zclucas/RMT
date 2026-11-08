
    ; 取得 parent 的第 N 個直接子節點（1-based）。
    GetNthChildItem(parentID, wantedIndex) {
        if (!parentID || wantedIndex < 1)
            return 0

        childID := this.MacroTreeViewCon.GetChild(parentID)
        index := 1
        while (childID) {
            if (index == wantedIndex)
                return childID
            index += 1
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
        return 0
    }

    ; 取得 branch 下第 N 條真正宏指令，忽略 ⎖ 控制項。
    GetNthCommandChild(parentID, wantedIndex) {
        if (!parentID || wantedIndex < 1)
            return 0

        childID := this.MacroTreeViewCon.GetChild(parentID)
        index := 1
        while (childID) {
            text := this.MacroTreeViewCon.GetText(childID)
            if (text != "" && SubStr(text, 1, 1) != "⎖") {
                if (index == wantedIndex)
                    return childID
                index += 1
            }
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
        return 0
    }

    OnSubNodeAddCmd(CommandStr) {
        this._PushUndo()
        displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(displayStr, this.CurItemID, iconStr)
        this.TreeAddBranch(newItemID, CommandStr)
        macroStr := this.GetTreeMacroStr(this.CurItemID)

        RealItemID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, this.CurItemID)
        this._NotifyMacroChanged()
    }

    OnSubNodeEdit(nodeItemID, macroStr) {
        this._PushUndo()
        RealItemID := this.MacroTreeViewCon.GetParent(nodeItemID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        macroStr := macroStr == "" ? " " : macroStr
        this.SaveCommandData(RealCommandStr, macroStr, nodeItemID)
        this.RefreshTree(RealItemID)
        this._NotifyMacroChanged()
    }

    ; F3：分支体子编辑器「确定」入口 —— 先回写分支体宏文本（同 OnSubNodeEdit），
    ; 再把该子编辑器本次新增的断点并入父树（父树已 RefreshTree，新节点就位，标记可命中）。
    _OnSubEditorSure(nodeItemID, macroStr, srcEd) {
        this.OnSubNodeEdit(nodeItemID, macroStr)
        if (IsObject(srcEd))
            this._IngestChildBreakpoints(srcEd.GetTreeBreakpoints())
    }

    ; F3：把「子编辑器（分支体）」新增的断点并入本编辑器树并落盘/上报。
    ; 采用「并集」语义：只新增命中签名的标记，绝不覆盖其他分支已有签名（呼应扁平签名模型）。
    _IngestChildBreakpoints(bpStr) {
        if (bpStr == "")
            return
        this._ApplyBreakpoints(bpStr)
        this._bpStr := this.GetTreeBreakpoints()
        if (IsObject(this.OnBpChanged))
            try this.OnBpChanged.Call(this._bpStr)
    }

    ExpandAll() {
        this.MacroTreeViewCon.Opt("-Redraw")
        rootItemID := this.MacroTreeViewCon.GetNext(0)
        while (rootItemID) {
            this.MacroTreeViewCon.Modify(rootItemID, "Expand")
            this.TreeExpandRecursive(rootItemID)
            rootItemID := this.MacroTreeViewCon.GetNext(rootItemID)
        }
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    TreeExpandRecursive(ItemID) {
        childID := this.MacroTreeViewCon.GetChild(ItemID)
        while (childID) {
            this.MacroTreeViewCon.Modify(childID, "Expand")
            this.TreeExpandRecursive(childID)
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
    }

    CollapseAll() {
        this.MacroTreeViewCon.Opt("-Redraw")
        itemID := this.MacroTreeViewCon.GetNext(0)
        while (itemID) {
            this.TreeCollapse(itemID)
            itemID := this.MacroTreeViewCon.GetNext(itemID)
        }
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    TreeCollapse(ItemID) {
        childID := this.MacroTreeViewCon.GetChild(ItemID)
        while (childID) {
            this.TreeCollapse(childID)
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
        if (this.MacroTreeViewCon.GetChild(ItemID))
            this.MacroTreeViewCon.Modify(ItemID, "Collapse")
    }

    GetTreeMacroStr(ItemID) {
        macroStr := ""
        rootItemID := this.MacroTreeViewCon.GetChild(ItemID)
        while (rootItemID) {
            cmdStr := this.MacroTreeViewCon.GetText(rootItemID)
            if (cmdStr != "" && SubStr(cmdStr, 1, 1) != "⎖") {
                ; 剥离当前位置标记 →（纯瞬态，不进入宏串）；保留 ▶ 供 F5 起点切片使用（解 G1）
                cmdStr := CmdStripCurPos(cmdStr)
                macroStr .= MySoftData.ParseCmdJoyDisplay(cmdStr) ","
            }

            rootItemID := this.MacroTreeViewCon.GetNext(rootItemID)
        }
        macroStr := Trim(macroStr, ",")
        return macroStr
    }

    ; ==================== 多選複製 ====================

    SetSingleMultiSelection(itemID) {
        this.ClearMultiSelection()
        if (!itemID)
            return
        this.SetMultiSelected(itemID, true)
        this.MultiSelectAnchor := itemID
    }

    SetMultiSelected(itemID, isSelected) {
        if (!itemID)
            return

        if (isSelected) {
            try this.MacroTreeViewCon.Modify(itemID, "Check")
            catch
                return
            this.MultiSelectItems[itemID] := true
        } else {
            try this.MacroTreeViewCon.Modify(itemID, "-Check")
            this.MultiSelectItems.Delete(itemID)
        }
    }

    ClearMultiSelection() {
        if (!IsObject(this.MultiSelectItems))
            this.MultiSelectItems := Map()
        if (this.MultiSelectItems.Count == 0) {
            this.MultiSelectAnchor := 0
            return
        }

        ; 逐项更新 ✓ 标记（不触发全量渲染）
        for itemID in this.MultiSelectItems {
            try this.MacroTreeViewCon.Modify(itemID, "-Check")
        }
        this.MultiSelectItems.Clear()
        this.MultiSelectAnchor := 0
    }

    ToggleMultiSelection(itemID) {
        if (!itemID)
            return

        ; 多選必須維持在同一層級。
        ; 不同 Parent 的 Ctrl+Click 直接改成單選，避免刪除時 RefreshTree 讓其他 ItemID 失效。
        if (!this.MultiSelectItems.Has(itemID)
            && this.MultiSelectAnchor
            && this.MacroTreeViewCon.GetParent(this.MultiSelectAnchor) != this.MacroTreeViewCon.GetParent(itemID)) {
            this.SetSingleMultiSelection(itemID)
            return
        }

        if (this.MultiSelectItems.Has(itemID))
            this.SetMultiSelected(itemID, false)
        else
            this.SetMultiSelected(itemID, true)
        this.MultiSelectAnchor := itemID
    }

    SelectMultiRange(anchorID, itemID) {
        if (!anchorID || !itemID) {
            this.SetSingleMultiSelection(itemID)
            return
        }

        if (this.MacroTreeViewCon.GetParent(anchorID) != this.MacroTreeViewCon.GetParent(itemID)) {
            this.SetSingleMultiSelection(itemID)
            return
        }

        this.ClearMultiSelection()
        cur := anchorID
        reached := false
        while (cur) {
            this.SetMultiSelected(cur, true)
            if (cur == itemID) {
                reached := true
                break
            }
            cur := this.MacroTreeViewCon.GetNext(cur)
        }

        if (!reached) {
            this.ClearMultiSelection()
            cur := anchorID
            while (cur) {
                this.SetMultiSelected(cur, true)
                if (cur == itemID)
                    break
                cur := this.MacroTreeViewCon.GetPrev(cur)
            }
        }
        this.MultiSelectAnchor := anchorID
    }

    GetMultiSelectedItems() {
        result := []
        this._CollectCheckedItems(0, &result)
        return result
    }

    _CollectCheckedItems(parentID, &result) {
        itemID := parentID == 0 ? this.MacroTreeViewCon.GetNext(0) : this.MacroTreeViewCon.GetChild(parentID)
        while (itemID) {
            if (this.MultiSelectItems.Has(itemID))
                result.Push(itemID)
            this._CollectCheckedItems(itemID, &result)
            itemID := this.MacroTreeViewCon.GetNext(itemID)
        }
    }

    GetCmdIconStr(cmdStr) {
        paramArr := StrSplit(cmdStr, "_")
        paramArr[1] := GetCmdStr(paramArr[1])

        textOnly := RegExReplace(paramArr[1], "\d+")
        if (this.CmdIconFileMap.Has(textOnly)) {
            rel := this.CmdIconFileMap[textOnly]
            full := A_WorkingDir "\" rel
            if (FileExist(full))
                return StrReplace(full, "\", "/")
        }
        return ""
    }
