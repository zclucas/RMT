
    ;添加指令
    OnAddCmd(CommandStr) {
        this._PushUndo()
        this.ResetDebugState()
        if (this.EditModeCon.Value == 1) {
            iconStr := this.GetCmdIconStr(CommandStr)
            displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
            root := this.MacroTreeViewCon.Add(displayStr, 0, iconStr)
            this.TreeAddBranch(root, CommandStr)
            this.LastItemID := root
        }
        else {
            MacroStr := this.GetMacroStr()
            MacroStr .= "`n" CommandStr
            cmdArr := SplitMacro(MacroStr)
            MacroStr := GetMacroStrByCmdArr(cmdArr)

            ; 保留滚动位置（#3）
            firstVisible := IsObject(this.ui) ? this.ui.Query("MacroText>FirstVisibleLine") : ""
            this.InitMacroText(MacroStr)
            if (firstVisible != "" && IsObject(this.ui))
                this.ui.Update("MacroText", "ScrollToLine", firstVisible)
            else
                this.MacroEditTextCon.ScrollToEnd()
        }
        this._NotifyMacroChanged()
    }

    ; ==================== 跳过指令切换（复用 🚫 标记，IDE 式注释） ====================

    ; Ctrl+/：切换选中项的 🚫。语义=全有或全无（全部已 🚫 → 全部取消；否则全部加 🚫）。
    ; 单条走同一函数（ids=[CurItemID]），与右键「跳过指令」同源。
    ; 关键：整批就地 Modify(id,,"text")（id 全程稳定），末尾一次性回写分支父；
    ;      禁止在此批量路径调用 OnModifyCmd(容器会 RefreshTree → 后代 id 失效，见 R5)。
    ToggleSkipSelected() {
        ids := this.GetMultiSelectedItems()
        if (ids.Length == 0 && this.CurItemID)
            ids.Push(this.CurItemID)
        if (ids.Length == 0)
            return
        single := (ids.Length == 1)
        targets := [], skipCfg := 0, skipDebug := 0, skipBranch := 0
        condPrefix := GetLang("条件")
        condPrefixLen := StrLen(condPrefix)
        for id in ids {
            raw := this.MacroTreeViewCon.GetText(id)
            clean := CmdStripCurPos(raw)              ; 仅剥行首 →，保留 ▶/⭐/🚫（与 case"Skip" 一致）
            if (SubStr(clean, 1, 1) == "⎖") {         ; 配置行不可跳过
                skipCfg += 1
                continue
            }
            if (CmdIsDebug(clean)) {                   ; ⭐/▶ 调试起点不可跳过
                skipDebug += 1
                continue
            }
            ; V5：分支容器节点（真/假/循环体/条件：…）不是指令，加 🚫 只会污染显示
            ; （数据侧有 SaveCommandData 的 fileMap 守卫兜底不落盘，但 UI 混乱且该次编辑静默丢失）
            if (clean == GetLang("真") || clean == GetLang("假") || clean == GetLang("循环体")
                || (condPrefix != "" && SubStr(clean, 1, condPrefixLen) == condPrefix)) {
                skipBranch += 1
                continue
            }
            targets.Push({ id: id, clean: clean })
        }
        ; 不可跳过项策略：单条沿用「调试起点」MsgBox 拒绝；批量跳过该行、末尾 Toast 汇总
        if (targets.Length == 0) {
            if (skipDebug > 0) {
                if (single)
                    RmtDialog.Info(GetLang("调试起点不能跳过"), "", "Owner" this.Gui.Hwnd)
                else
                    Toast.Show(GetLang("调试起点不能跳过"))
            }
            else if (skipBranch > 0)
                Toast.Show(GetLang("该节点不支持跳过"))
            else
                Toast.Show(GetLang("无可跳过的指令"))
            return
        }
        allSkipped := true
        for t in targets
            if (SubStr(t.clean, 1, 2) != "🚫") {
                allSkipped := false
                break
            }
        this.ResetDebugState()                         ; 编辑即结束调试（与 OnModifyCmd 一致）
        this._PushUndo()                               ; ★整批一次撤销（先于 BeginUndoBatch 捕获快照）
        this._BeginUndoBatch()
        for t in targets {
            newText := allSkipped ? SubStr(t.clean, 3) : "🚫" t.clean
            this.MacroTreeViewCon.Modify(t.id, , MySoftData.FormatCmdJoyDisplay(newText))   ; 就地改文本，id 不变
        }
        this._EndUndoBatch()
        this._CommitSkipEdits(targets)
        this._NotifyMacroChanged()
        if (skipDebug > 0) {
            if (single)
                RmtDialog.Info(GetLang("调试起点不能跳过"), "", "Owner" this.Gui.Hwnd)
            else
                Toast.Show(GetLang("调试起点不能跳过"))
        }
        else if (skipBranch > 0)
            Toast.Show(GetLang("该节点不支持跳过"))
        else if (skipCfg > 0)
            Toast.Show(GetLang("配置文件行已跳过"))
    }

    ; 批量跳过后的分支回写：把每个「被改节点的分支父」的新宏串写回其真实命令（镜像 OnModifyCmd 末尾）。
    ; 根级被改节点由 _NotifyMacroChanged 的 GetMacroStr 覆盖，此处跳过。
    _CommitSkipEdits(nodes) {
        parents := Map()
        for n in nodes {
            p := this.MacroTreeViewCon.GetParent(n.id)
            if (p == 0)
                continue                               ; 根级：由 _NotifyMacroChanged 的 GetMacroStr 覆盖
            parents[p] := true                         ; 分支父（真/假/循环体/条件）
        }
        for p in parents {
            grand := this.MacroTreeViewCon.GetParent(p)
            if (grand == 0)
                continue                               ; 防御
            realCmd := this.MacroTreeViewCon.GetText(grand)
            this.SaveCommandData(realCmd, this.GetTreeMacroStr(p), p)     ; 镜像 OnModifyCmd 末尾
        }
    }

    ;修改指令
    OnModifyCmd(CommandStr) {
        this._PushUndo()
        this.ResetDebugState()
        this.MacroTreeViewCon.Modify(this.CurItemID, , MySoftData.FormatCmdJoyDisplay(CommandStr))
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        if (ParentID == 0) {
            ; 仅分支指令（有子节点）修改结构时重建；叶子修改无需
            if (this.MacroTreeViewCon.GetChild(this.CurItemID) != 0)
                this.RefreshTree(this.CurItemID)
            this._NotifyMacroChanged()
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)

        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        if (this.MacroTreeViewCon.GetChild(this.CurItemID) != 0)
            this.RefreshTree(RealItemID)
        this._NotifyMacroChanged()
    }

    OnPreMoveCmd() {
        if (this._IsImmovableNode(this.MacroTreeViewCon.GetText(this.CurItemID))) {
            RmtDialog.Info(GetLang("该节点不能移动"))
            return
        }
        PreItemID := this.MacroTreeViewCon.GetPrev(this.CurItemID)
        if (PreItemID == 0) {
            RmtDialog.Info(GetLang("已经是第一个指令了，无法上移"))
            return
        }
        PreText := this.MacroTreeViewCon.GetText(PreItemID)
        if (PreText == "" || this._IsImmovableNode(PreText)) {
            RmtDialog.Info(GetLang("不可与特殊指令进行交换"))
            return
        }
        this.OnSwitchCmd(PreItemID, this.CurItemID)
    }

    OnNextMoveCmd() {
        if (this._IsImmovableNode(this.MacroTreeViewCon.GetText(this.CurItemID))) {
            RmtDialog.Info(GetLang("该节点不能移动"))
            return
        }
        NextItemID := this.MacroTreeViewCon.GetNext(this.CurItemID)
        if (NextItemID == 0) {
            RmtDialog.Info(GetLang("已经是最后的指令了，无法下移"))
            return
        }
        NextText := this.MacroTreeViewCon.GetText(NextItemID)
        if (NextText == "" || this._IsImmovableNode(NextText)) {
            RmtDialog.Info(GetLang("不可与特殊指令进行交换"))
            return
        }
        this.OnSwitchCmd(this.CurItemID, NextItemID)
    }

    OnSwitchCmd(ItemAID, ItemBID) {
        if (this._IsImmovableNode(this.MacroTreeViewCon.GetText(ItemAID)) || this._IsImmovableNode(this.MacroTreeViewCon.GetText(ItemBID))) {
            RmtDialog.Info(GetLang("不可与特殊指令进行交换"))
            return
        }
        this._PushUndo()
        this.ResetDebugState()
        LastItemID := this.MacroTreeViewCon.GetPrev(ItemAID)
        ParentID := this.MacroTreeViewCon.GetParent(ItemAID)
        NewACmdStr := this.MacroTreeViewCon.GetText(ItemBID)
        NewBCmdStr := this.MacroTreeViewCon.GetText(ItemAID)
        NewAIconStr := this.GetCmdIconStr(NewACmdStr)
        NewBIconStr := this.GetCmdIconStr(NewBCmdStr)

        this.MacroTreeViewCon.Delete(ItemAID)
        this.MacroTreeViewCon.Delete(ItemBID)
        SortArg := LastItemID == 0 ? "First" : LastItemID
        NewItemAID := this.MacroTreeViewCon.Add(NewACmdStr, ParentID, SortArg " " NewAIconStr)
        NewItemBID := this.MacroTreeViewCon.Add(NewBCmdStr, ParentID, NewItemAID " " NewBIconStr)
        this.TreeAddBranch(NewItemAID, NewACmdStr)
        this.TreeAddBranch(NewItemBID, NewBCmdStr)
        if (ParentID == 0) {
            this._NotifyMacroChanged()
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)

        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        this._NotifyMacroChanged()
    }

    ; Delete 熱鍵與右鍵「刪除」共用這個入口。
    ; 真／假／循環體／條件可以參與多選；刪除時不能直接刪掉容器，
    ; 而是依照單選的語義清空對應分支資料，再統一 RefreshTree。
    OnDeleteCmd() {
        this._PushUndo()
        this.ResetDebugState()

        selectedItems := this.GetMultiSelectedItems()
        if (selectedItems.Length == 0 && this.CurItemID)
            selectedItems.Push(this.CurItemID)
        if (selectedItems.Length == 0)
            return

        ; 單選：使用完整的分支刪除邏輯。
        if (selectedItems.Length == 1) {
            this.CurItemID := selectedItems[1]
            this._DeleteSingleCmd(this.CurItemID)
            this.ClearMultiSelection()
            this._NotifyMacroChanged()
            return
        }

        ; 多選項目必須位於同一層級。
        parentID := this.MacroTreeViewCon.GetParent(selectedItems[1])
        for itemID in selectedItems {
            if (this.MacroTreeViewCon.GetParent(itemID) != parentID) {
                ; 舊狀態若存在跨層多選，退回目前項目的單選刪除。
                this.SetSingleMultiSelection(this.CurItemID ? this.CurItemID : selectedItems[1])
                this.CurItemID := this.CurItemID ? this.CurItemID : selectedItems[1]
                this._DeleteSingleCmd(this.CurItemID)
                this.ClearMultiSelection()
                return
            }
        }

        ; 根層沒有「真／假／循環體／條件」容器，正常倒序刪除。
        if (parentID == 0) {
            loop selectedItems.Length {
                itemID := selectedItems[selectedItems.Length - A_Index + 1]
                try this.MacroTreeViewCon.Delete(itemID)
            }
            this.CurItemID := 0
            this.ClearMultiSelection()
            this._NotifyMacroChanged()
            ; T4：多选删除后剪掉被删命令的幽灵断点签名
            if (this._bpAllowed)
                this._NotifyBpChanged()
            return
        }

        ; parentID 有兩種情況：
        ; 1. parentID 是「真／假／循環體／條件」容器：selectedItems 是其中的普通指令。
        ; 2. parentID 是根層的分支命令：selectedItems 是「真／假／循環體／條件」容器本身。
        parentText := this.MacroTreeViewCon.GetText(parentID)
        parentIsContainer := this.IsContainerNode(parentText)

        if (parentIsContainer) {
            realItemID := this.MacroTreeViewCon.GetParent(parentID)
            if (!realItemID) {
                this.CurItemID := 0
                this.ClearMultiSelection()
                return
            }
            realCommandStr := this.MacroTreeViewCon.GetText(realItemID)
        } else {
            ; 分支命令本身就是 SaveCommandData 的 RealCommandStr，刷新它即可。
            realItemID := parentID
            realCommandStr := parentText
        }

        ; 同一 Parent 下若有「條件」容器，刪除前先保存原始 ItemNumber。
        ; IfPro 刪除分支時會移除陣列元素，因此必須從後往前處理。
        containerItems := []
        normalItems := []
        for itemID in selectedItems {
            try itemText := this.MacroTreeViewCon.GetText(itemID)
            catch
                continue

            if (this.IsContainerNode(itemText))
                containerItems.Push(itemID)
            else
                normalItems.Push(itemID)
        }

        ; 容器按 TreeView 順序由後往前處理，避免 IfPro 分支編號因前面刪除而位移。
        loop containerItems.Length {
            bestIndex := 1
            bestNumber := this.GetItemNumber(containerItems[1])
            idx := 2
            while (idx <= containerItems.Length) {
                number := this.GetItemNumber(containerItems[idx])
                if (number > bestNumber) {
                    bestIndex := idx
                    bestNumber := number
                }
                idx += 1
            }

            itemID := containerItems.RemoveAt(bestIndex)
            this.SaveCommandData(realCommandStr, "", itemID)
        }

        ; 一般子指令才直接 Delete；從後往前刪，避免 TreeView handle 互相影響。
        loop normalItems.Length {
            itemID := normalItems[normalItems.Length - A_Index + 1]
            try this.MacroTreeViewCon.Delete(itemID)
        }

        ; 如果 selectedItems 是容器本身，前面的 SaveCommandData 已逐個清空對應分支。
        ; 如果 selectedItems 是容器內普通指令，則需要把剩餘宏重新寫回該容器。
        if (parentIsContainer) {
            macroStr := this.GetTreeMacroStr(parentID)
            isCondi := SubStr(CmdStripCurPos(parentText), 1, StrLen(GetLang("条件"))) == GetLang("条件")
            macroStr := macroStr == "" && isCondi ? "空条件" : macroStr
            this.SaveCommandData(realCommandStr, macroStr, parentID)
        }

        this.RefreshTree(realItemID)
        this.CurItemID := 0
        this.ClearMultiSelection()
        this._NotifyMacroChanged()
        ; T4：删除容器分支后剪掉被删命令的幽灵断点签名
        if (this._bpAllowed)
            this._NotifyBpChanged()
    }

    ; 單一指令的刪除邏輯。容器節點不能直接 Delete，只能清空它所代表的分支。
    _DeleteSingleCmd(itemID) {
        if (!itemID)
            return

        itemText := this.MacroTreeViewCon.GetText(itemID)
        isContainer := this.IsContainerNode(itemText)
        ParentID := this.MacroTreeViewCon.GetParent(itemID)

        ; 理論上根層不會出現容器；即使狀態異常，也不要直接刪除容器。
        if (ParentID == 0) {
            if (!isContainer)
                this.MacroTreeViewCon.Delete(itemID)
            ; T4：根层早退分支同样剪枝，避免根层被删命令残留幽灵断点签名
            if (this._bpAllowed)
                this._NotifyBpChanged()
            return
        }

        NodeItemID := itemID
        RealItemID := ParentID
        macroStr := ""

        ; 普通指令：直接刪除，再將同層剩餘內容寫回父容器。
        if (!isContainer) {
            this.MacroTreeViewCon.Delete(itemID)
            NodeItemID := ParentID
            RealItemID := this.MacroTreeViewCon.GetParent(NodeItemID)
            macroStr := this.GetTreeMacroStr(NodeItemID)

            NodeItemText := this.MacroTreeViewCon.GetText(NodeItemID)
            isCondi := SubStr(CmdStripCurPos(NodeItemText), 1, StrLen(GetLang("条件"))) == GetLang("条件")
            macroStr := macroStr == "" && isCondi ? "空条件" : macroStr
        }

        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, NodeItemID)
        ; 普通指令删除已增量完成；仅清空容器分支时才需重建
        if (isContainer)
            this.RefreshTree(RealItemID)
        this._NotifyMacroChanged()
        ; T4：删除后重新采集「当前仍被标记」的签名写回宿主，剪掉已删命令的幽灵签名
        if (this._bpAllowed)
            this._NotifyBpChanged()
    }

    ;插入指令
    OnPreInsertCmd(CommandStr) {
        this._PushUndo()
        this.ResetDebugState()
        displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        PreItemID := this.MacroTreeViewCon.GetPrev(this.CurItemID)
        Seq := PreItemID == 0 ? "First" : PreItemID
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(displayStr, ParentID, Seq " " iconStr)
        this.TreeAddBranch(newItemID, CommandStr)
        if (ParentID == 0) {
            this._NotifyMacroChanged()
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        this._NotifyMacroChanged()
    }

    ; 插入一條指令；返回刷新後可繼續作為插入錨點的 TreeView ItemID。
    OnNextInsertCmd(CommandStr) {
        ; 防止多條指令誤傳進來，避免把「运行,输出,如果」當成一個 command key。
        cmds := SplitMacro(CommandStr)
        if (cmds.Length > 1) {
            this.PasteClipboardCommands(CommandStr)
            return 0
        }

        CommandStr := Trim(CommandStr, " `t`r`n")
        if (CommandStr == "")
            return 0

        this._PushUndo()
        this.ResetDebugState()

        anchorItemID := this.CurItemID
        ParentID := this.MacroTreeViewCon.GetParent(anchorItemID)

        displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(displayStr, ParentID, anchorItemID " " iconStr)
        if (anchorItemID == this.LastItemID)
            this.LastItemID := newItemID
        this.TreeAddBranch(newItemID, CommandStr)

        if (ParentID == 0) {
            this.CurItemID := newItemID
            this.MacroTreeViewCon.Modify(newItemID, "Select")
            this._NotifyMacroChanged()
            return newItemID
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, ParentID)

        ; 不再 RefreshTree：newItemID 保持有效，直接选中
        this.CurItemID := newItemID
        this.MacroTreeViewCon.Modify(newItemID, "Select")
        this._NotifyMacroChanged()
        return newItemID
    }

    ; 粘貼到真/假/循環體/條件容器節點內部：把指令追加到該分支末尾並回寫。
    ; 容器節點不能像普通指令一樣在同層級插入，否則 GetParent 取到根後 GetText(0) 報錯。
    PasteIntoContainer(containerID, cmds) {
        realItemID := this.MacroTreeViewCon.GetParent(containerID)
        if (!realItemID)
            return

        realCommandStr := this.MacroTreeViewCon.GetText(realItemID)
        macroStr := this.GetTreeMacroStr(containerID)

        for _, cmdStr in cmds {
            cmdStr := Trim(cmdStr, " `t`r`n")
            if (cmdStr == "")
                continue
            macroStr := (macroStr == "" ? "" : macroStr ",") cmdStr
        }

        this.SaveCommandData(realCommandStr, macroStr, containerID)
        this.RefreshTree(realItemID)
        this.CurItemID := 0
    }

    ; 整段粘贴记一次撤销。根层批量插入只修改宏串，分支还需要回写参数。
    PasteClipboardCommands(clipboardStr) {
        cmds := SplitMacro(clipboardStr)
        if (!cmds.Length)
            return

        tree := this.MacroTreeViewCon
        anchorID := this.CurItemID
        anchorText := CmdStripCurPos(tree.GetText(anchorID))
        if (SubStr(anchorText, 1, 1) == "⎖")
            return
        if (anchorText == "")
            anchorID := 0

        isContainer := this.IsContainerNode(anchorText)
        parentID := tree.GetParent(anchorID)
        isRoot := !isContainer && parentID == 0
        this._PushUndo(!isRoot)
        this._BeginUndoBatch()
        try {
            if (isRoot) {
                this.ResetDebugState()
                firstInserted := tree.InsertRootCommands(cmds, anchorID,
                    this.TreeAddBranch.Bind(this), this.GetCmdIconStr.Bind(this))
                this.LastItemID := tree.roots[tree.roots.Length].id
                this.CurItemID := firstInserted
                tree.Modify(firstInserted, "Select")
                return
            }
            if (isContainer) {
                this.PasteIntoContainer(anchorID, cmds)
                return
            }
            if (cmds.Length == 1) {
                this.OnNextInsertCmd(cmds[1])
                return
            }
            this._PasteAfterBranchCommand(cmds, parentID, anchorID)
        } finally {
            ; 在结束批次前统一登记，侧栏只回写一次宏串。
            this._NotifyMacroChanged()
            this._EndUndoBatch()
        }
    }

    _PasteAfterBranchCommand(cmds, parentID, anchorID) {
        ; 分支內：一次重建該分支宏，避免 RefreshTree 後舊 ItemID 失效。
        branchIndex := this.GetItemNumber(parentID)
        anchorIndex := this.GetItemNumber(anchorID)

        macroStr := this.GetTreeMacroStr(parentID)
        existingCmds := SplitMacro(macroStr)
        if (anchorIndex > existingCmds.Length)
            anchorIndex := existingCmds.Length

        mergedCmds := []
        for i, cmdStr in existingCmds {
            if (i == anchorIndex + 1) {
                for _, pasteCmd in cmds {
                    pasteCmd := Trim(pasteCmd, " `t`r`n")
                    if (pasteCmd != "")
                        mergedCmds.Push(pasteCmd)
                }
            }
            mergedCmds.Push(cmdStr)
        }

        ; 原本錨點在分支末尾時，插入內容要放到最後。
        if (anchorIndex >= existingCmds.Length) {
            for _, pasteCmd in cmds {
                pasteCmd := Trim(pasteCmd, " `t`r`n")
                if (pasteCmd != "")
                    mergedCmds.Push(pasteCmd)
            }
        }

        newMacroStr := ""
        for _, cmdStr in mergedCmds
            newMacroStr .= (newMacroStr == "" ? "" : ",") cmdStr

        realItemID := this.MacroTreeViewCon.GetParent(parentID)
        if (!realItemID)
            return
        realCommandStr := this.MacroTreeViewCon.GetText(realItemID)
        this.SaveCommandData(realCommandStr, newMacroStr, parentID)
        this.RefreshTree(realItemID)

        ; RefreshTree 後重新找回原本的分支節點。
        newParentID := this.GetNthChildItem(realItemID, branchIndex)
        if (!newParentID)
            return

        ; 找到插入區段最後一條，讓後續操作仍停在貼上的內容附近。
        targetIndex := anchorIndex + cmds.Length
        targetID := this.GetNthCommandChild(newParentID, targetIndex)
        if (targetID) {
            this.CurItemID := targetID
            this.MultiSelectAnchor := targetID
            this.MacroTreeViewCon.Modify(targetID, "Select")
        }
    }
