#Requires AutoHotkey v2.0

; ============================================================================
; MacroGraphGui 职能拆分 —— 分支/循环体「内联展开」
;
; 在「如果/搜索/搜索Pro 真假分支」「如果Pro 情况分支」「循环体」标题栏提供折叠/展开：
;   · 折叠（默认）：容器仍是现在的样子（标题 + 指令小卡片预览）。
;   · 展开：把该容器子图里的指令以「真实可编辑节点」的形式内联渲染在画布上，
;           并从容器出点连线到子图首节点，可像普通节点一样内联编辑/双击编辑/拖动。
;
; 关键约束：内联子节点仅是「容器子图」的可视化编辑视图，不属于顶层图：
;   · 子节点放入 this.cmdNodes / this.pos（复用全部内联编辑机制），但不进 this.order；
;   · 顶层的连线捕获 / 归一 / 保存均通过 _IsInlineSub 跳过这些子节点与相关连线；
;   · 任意改动在 _SaveGraphAndNotifyParent 时就地回写到 TrueMacro / FalseMacro / MacroArr /
;     DefaultMacro / LoopBody（复用既有序列码，不产生泄漏）。
;
; 本视图为会话级：整窗重建（_Render）或重新打开编辑器时先回写再折叠，重建后默认折叠。
;
; 方法体 this 仍为 MacroGraphGui 实例，通过 _GraftMacroGraphMixin 嫁接到原型。
; ============================================================================

class MacroGraphInlineMixin {
    ; 该 id 是否为内联子节点
    _IsInlineSub(id) {
        return this.HasOwnProp("_ilOwner") && this._ilOwner.Has(id)
    }

    ; 是否可作为内联展开容器（真/假分支、如果Pro 情况、循环体）
    _IsInlineContainerId(brId) {
        return this._BranchInfo(brId) != "" || this._IsLoopBodyId(brId)
    }

    ; 数组是否已包含某值（序列码去重用）
    _ArrHasVal(arr, val) {
        for v in arr {
            if (v == val)
                return true
        }
        return false
    }

    ; 读取容器子图开始序列码（真假分支 / 如果Pro / 循环体）
    _InlineContainerStartSerial(brId) {
        bi := this._BranchInfo(brId)
        if (bi != "") {
            if (bi.proIdx >= 0)
                return this._IfProBranchMacro(bi.searchId, bi.proIdx)
            return this._BranchStartSerial(bi.searchId, bi.isTrue)
        }
        li := this._LoopBodyInfo(brId)
        if (li != "") {
            data := this._SearchData(li.loopId)
            if (!IsObject(data))
                return ""
            return data.HasOwnProp("LoopBody") ? data.LoopBody : ""
        }
        return ""
    }

    ; 把开始序列码写回容器对应字段
    _WriteInlineContainerStartSerial(brId, startSerial) {
        bi := this._BranchInfo(brId)
        if (bi != "") {
            if (bi.proIdx >= 0) {
                data := this._IfProData(bi.searchId)
                if (!IsObject(data))
                    return
                cc := this._IfProCaseCountFromData(data)
                if (bi.proIdx < cc)
                    data.MacroArr[bi.proIdx + 1] := startSerial
                else
                    data.DefaultMacro := startSerial
                SaveMacroCMDData(data)
                return
            }
            data := this._BranchParentData(bi.searchId)
            if (!IsObject(data))
                return
            if (bi.isTrue)
                data.TrueMacro := startSerial
            else
                data.FalseMacro := startSerial
            SaveMacroCMDData(data)
            return
        }
        li := this._LoopBodyInfo(brId)
        if (li != "") {
            data := this._SearchData(li.loopId)
            if (!IsObject(data))
                return
            data.LoopBody := startSerial
            SaveMacroCMDData(data)
        }
    }

    ; 折叠后刷新容器指令预览
    _RefreshInlineContainerBody(brId) {
        bi := this._BranchInfo(brId)
        if (bi != "") {
            if (bi.proIdx >= 0)
                this._RefreshProBranchBody(bi.searchId, bi.proIdx)
            else
                this._RefreshBranchBody(bi.searchId, bi.isTrue)
            return
        }
        li := this._LoopBodyInfo(brId)
        if (li != "")
            this._RefreshLoopBodyNode(li.loopId)
    }

    ; 真/假分支标题栏「内联展开/折叠」
    _OnBranchInlineToggle(searchId, isTrue, *) {
        if (this.ui == "" || this.graph == "")
            return
        this._ToggleInlineByBrId(this._BranchId(searchId, isTrue))
    }

    ; 如果Pro 情况分支标题栏「内联展开/折叠」
    _OnProBranchInlineToggle(parentId, idx, *) {
        if (this.ui == "" || this.graph == "")
            return
        this._ToggleInlineByBrId(this._ProBranchId(parentId, idx))
    }

    ; 循环体标题栏「内联展开/折叠」
    _OnLoopBodyInlineToggle(loopId, *) {
        if (this.ui == "" || this.graph == "")
            return
        this._ToggleInlineByBrId(this._LoopBodyId(loopId))
    }

    _ToggleInlineByBrId(brId) {
        if (brId == "" || !this._IsInlineContainerId(brId))
            return
        if (this._ilExpanded.Has(brId) && this._ilExpanded[brId])
            this._CollapseInlineByBrId(brId)
        else
            this._ExpandInlineByBrId(brId)
    }

    ; 兼容旧调用：真/假分支展开
    _ExpandInlineBranch(searchId, isTrue) {
        this._ExpandInlineByBrId(this._BranchId(searchId, isTrue))
    }

    ; 展开：解析容器子图 → 内联注入为真实节点 → 连线（容器→首节点、子节点之间）
    _ExpandInlineByBrId(brId) {
        if (brId == "" || !this._IsInlineContainerId(brId))
            return
        if (this._ilExpanded.Has(brId) && this._ilExpanded[brId])
            return
        startSerial := this._InlineContainerStartSerial(brId)
        ; 记住可复用的分支开始节点序列码（图结构才复用；线性/空则留空，序列化时再分配）
        SplitSerialTextAndNumbers(startSerial, &t, &n)
        this._ilStartSerial[brId] := (t == GetLangKey("图形开始节点") && n != "") ? startSerial : ""

        recs := this._InlineBranchRecords(startSerial)
        keyToSub := Map()
        subsArr := []
        for rec in recs {
            subId := "ILNode" (++this._ilSeq)
            node := MacroGraphNode()
            node.CurCMD := rec.cmd
            ; 图结构子节点复用其原序列码（就地更新，避免序列码泄漏）；线性/新增子节点留空
            node.SerialStr := (SubStr(rec.key, 1, 3) == "new") ? "" : rec.key
            ; 还原折叠/后继偏移，便于布局按「展开态」给后继留空（如 按键→如果B→间隔）
            if (node.SerialStr != "") {
                nd := GetMacroCMDData(node.SerialStr)
                if (IsObject(nd)) {
                    node.Folded := nd.HasOwnProp("Folded") ? nd.Folded : 0
                    for layoutProp in ["TrueBranchDX", "TrueBranchDY", "FalseBranchDX", "FalseBranchDY", "ExpandShift", "SuccDX", "SuccDY", "FoldSuccDX", "FoldSuccDY", "ProBranchOff", "LoopBodyDX", "LoopBodyDY"] {
                        if (nd.HasOwnProp(layoutProp))
                            node.%layoutProp% := nd.%layoutProp%
                    }
                }
            }
            this.cmdNodes[subId] := node
            this._ilOwner[subId] := brId
            this._ilSerial[subId] := node.SerialStr
            keyToSub[rec.key] := subId
            subsArr.Push(subId)
        }
        this._ilSubs[brId] := subsArr

        ; 布局：展开的如果/搜索后继按 ExpandMinGap 留空，不能只用固定 260 步进
        this._LayoutInlineSubs(brId, recs, keyToSub)

        ; 注入子节点（复用完整内联节点，自带字段编辑 + 双击编辑 + 拖动）
        for subId in subsArr
            this._InjectFullNode(subId, this.cmdNodes[subId])

        ; 子节点若本身带分支/循环体：注入其卡片并登记为内联子，折叠时一并清理
        for subId in subsArr {
            if (this._HasVisibleBranches(subId))
                this._InjectInlineSubBranches(brId, subId)
            if (this._IsExpandedLoop(subId))
                this._InjectInlineSubLoopBody(brId, subId)
        }

        ; 连线：容器→入口子节点、子节点之间。
        ; 内联子若本身是「如果/搜索」，后继仍由该子节点直连（与顶层：展开时主节点连后续一致）。
        for rec in recs {
            if (rec.entry && keyToSub.Has(rec.key))
                this._ActivateConnection(brId, keyToSub[rec.key])
            if (!keyToSub.Has(rec.key))
                continue
            fromSub := keyToSub[rec.key]
            for nk in rec.nexts {
                if (!keyToSub.Has(nk))
                    continue
                toSub := keyToSub[nk]
                this._ActivateConnection(fromSub, toSub)
            }
        }

        ; 连线就绪后再按展开间距微调（含 SuccDX 记忆；修复间隔仍贴在如果B收起位的问题）
        for subId in subsArr
            this._EnsureExpandGap(subId)

        this._ilExpanded[brId] := true
        this.ui.Update("ILExpand_" brId, "Content", "▾")
        this.ui.Update("ILExpand_" brId, "ToolTip", GetLang("收起"))
        this._ThickenConnections()
        this._RebindPathClicks()
    }

    ; 为内联子节点（本身是如果/搜索等带分支的节点）注入真/假/多分支卡片。
    ; 登记为内联子（_ilOwner），归属于外层 ownerBrId，随外层折叠一并清理。
    _InjectInlineSubBranches(ownerBrId, subId) {
        this._InjectBranches(subId)   ; 注入真/假（或如果Pro 多分支）卡片 + 分支↔子连线 + 事件
        brIds := []
        if (this._IsIfProNodeId(subId)) {
            count := this._IfProBranchCountFromId(subId)
            loop count
                brIds.Push(this._ProBranchId(subId, A_Index - 1))
        } else {
            brIds.Push(this._BranchId(subId, true))
            brIds.Push(this._BranchId(subId, false))
        }
        for b in brIds {
            this._ilOwner[b] := ownerBrId
            if (this._ilSubs.Has(ownerBrId))
                this._ilSubs[ownerBrId].Push(b)
        }
    }

    ; 为内联子循环节点注入外置循环体，并登记为内联子
    _InjectInlineSubLoopBody(ownerBrId, loopId) {
        this._InjectLoopBodyNode(loopId)
        bid := this._LoopBodyId(loopId)
        this._ilOwner[bid] := ownerBrId
        if (this._ilSubs.Has(ownerBrId))
            this._ilSubs[ownerBrId].Push(bid)
    }

    ; 兼容旧调用：真/假分支折叠
    _CollapseInlineBranch(searchId, isTrue) {
        this._CollapseInlineByBrId(this._BranchId(searchId, isTrue))
    }

    ; 按容器合成 ID 折叠（供递归折叠嵌套子容器：真假/如果Pro/循环体）
    _CollapseInlineBranchByBrId(brId2) {
        this._CollapseInlineByBrId(brId2)
    }

    ; 折叠：先回写容器子图，再移除内联子节点与相关连线，恢复容器卡片预览
    _CollapseInlineByBrId(brId) {
        if (brId == "" || !this._IsInlineContainerId(brId))
            return
        if (!(this._ilExpanded.Has(brId) && this._ilExpanded[brId]))
            return
        g := this.graph
        ; 先递归折叠嵌套的、仍处于展开态的子容器，否则更深层内联节点不在本容器 _ilSubs 里会残留
        subsPre := this._ilSubs.Has(brId) ? this._ilSubs[brId].Clone() : []
        for sid in subsPre {
            if (this._ilExpanded.Has(sid) && this._ilExpanded[sid])
                this._CollapseInlineByBrId(sid)
        }
        this._SerializeInlineBranch(brId)          ; 折叠前持久化，避免丢失编辑
        subs := this._ilSubs.Has(brId) ? this._ilSubs[brId].Clone() : []
        for sid in subs {
            keep := []
            for conn in g.connections {
                if (conn.From == sid || conn.To == sid)
                    g.SetConnVisible(conn.PathId, "Collapsed")
                else
                    keep.Push(conn)
            }
            g.connections := keep
            this.ui.Update("Node_" sid, "Visibility", "Collapsed")
            this.ui.Update("Port_In_" sid, "Visibility", "Collapsed")
            this.ui.Update("Port_Out_" sid, "Visibility", "Collapsed")
            ; 内联登记的外置循环体：一并隐藏回环路径，避免残留
            li := this._LoopBodyInfo(sid)
            if (li != "") {
                this.ui.Update("LoopEnterPath_" li.loopId, "Visibility", "Collapsed")
                this.ui.Update("LoopReturnPath_" li.loopId, "Visibility", "Collapsed")
                this.ui.Update("LoopEnterTri_" li.loopId, "Visibility", "Collapsed")
                this.ui.Update("LoopReturnTri_" li.loopId, "Visibility", "Collapsed")
                if (this._loopBodyInjected.Has(li.loopId))
                    this._loopBodyInjected.Delete(li.loopId)
            }
            nkeep := []
            for n in g.nodes {
                if (n.Id != sid)
                    nkeep.Push(n)
            }
            g.nodes := nkeep
            if (this.cmdNodes.Has(sid))
                this.cmdNodes.Delete(sid)
            if (this.pos.Has(sid))
                this.pos.Delete(sid)
            if (this._ilOwner.Has(sid))
                this._ilOwner.Delete(sid)
            if (this._ilSerial.Has(sid))
                this._ilSerial.Delete(sid)
            ; 内联子若曾注入过自身分支卡片，清掉注入记录，便于再次展开时重建
            if (this._branchInjected.Has(sid))
                this._branchInjected.Delete(sid)
            if (g.selectedNodes.Has(sid))
                g.selectedNodes.Delete(sid)
        }
        if (this._ilSubs.Has(brId))
            this._ilSubs.Delete(brId)
        this._ilExpanded[brId] := false
        this.ui.Update("ILExpand_" brId, "Content", "▸")
        this.ui.Update("ILExpand_" brId, "ToolTip", GetLang("展开"))
        this._RefreshInlineContainerBody(brId)
        this._CaptureTopLevelSuccessorLinks()
    }

    ; 整窗重建前：把所有展开的内联分支回写并从 cmdNodes/pos 摘除，避免污染重建后的顶层图。
    _DetachAllInlineForRebuild() {
        if (!this.HasOwnProp("_ilExpanded"))
            return
        for brId, on in this._ilExpanded {
            if (on)
                this._SerializeInlineBranch(brId)
        }
        subKeys := []
        for sid in this._ilOwner
            subKeys.Push(sid)
        for sid in subKeys {
            if (this.cmdNodes.Has(sid))
                this.cmdNodes.Delete(sid)
            if (this.pos.Has(sid))
                this.pos.Delete(sid)
        }
        this._ilExpanded := Map()
        this._ilSubs := Map()
        this._ilOwner := Map()
        this._ilSerial := Map()
        this._ilStartSerial := Map()
    }

    ; 回写所有展开中的内联分支（_SaveGraphAndNotifyParent 调用）
    _SerializeAllInlineBranches() {
        if (!this.HasOwnProp("_ilExpanded"))
            return
        for brId, on in this._ilExpanded {
            if (on)
                this._SerializeInlineBranch(brId)
        }
    }

    ; 把某容器的内联子图序列化并写回 TrueMacro/FalseMacro/MacroArr/DefaultMacro/LoopBody。
    ; 子节点/开始节点均复用既有序列码就地更新，无序列码泄漏。
    _SerializeInlineBranch(brId) {
        if (brId == "" || !this._IsInlineContainerId(brId))
            return
        subs := this._ilSubs.Has(brId) ? this._ilSubs[brId] : []

        ; 为每个仍存在的子节点确定（复用/新建）序列码
        serialOf := Map()
        for sid in subs {
            if (!this.cmdNodes.Has(sid))
                continue
            s := (this._ilSerial.Has(sid) && this._ilSerial[sid] != "") ? this._ilSerial[sid] : GetCMDSerialStr("图形节点")
            this._ilSerial[sid] := s
            serialOf[sid] := s
        }

        ; 从当前连线派生：入口(容器→子)、子→子后继、入度
        nextsOf := Map()
        entries := []
        hasIncoming := Map()
        for sid in serialOf
            hasIncoming[sid] := false
        for conn in this.graph.connections {
            if (conn.HasOwnProp("Active") && !conn.Active)
                continue
            f := conn.From, tt := conn.To
            ; 跳过「X → 分支/循环体卡片」的显示连线，它不是逻辑后继
            if (this._BranchInfo(tt) != "" || this._IsLoopBodyId(tt))
                continue
            ; 「内联如果/搜索/如果Pro 子」的分支卡片 → 后继：归一为「该子节点 → 后继」
            fi := this._BranchInfo(f)
            if (fi != "" && serialOf.Has(fi.searchId))
                f := fi.searchId
            if (f == brId && serialOf.Has(tt)) {
                if (!this._ArrHasVal(entries, serialOf[tt]))
                    entries.Push(serialOf[tt])
                hasIncoming[tt] := true
                continue
            }
            if (serialOf.Has(f) && serialOf.Has(tt)) {
                if (!nextsOf.Has(f))
                    nextsOf[f] := []
                if (!this._ArrHasVal(nextsOf[f], serialOf[tt]))
                    nextsOf[f].Push(serialOf[tt])
                hasIncoming[tt] := true
            }
        }

        ; 保存各子节点本体（坐标相对容器节点，便于再次展开时布局稳定）
        ; 保留 Folded/分支布局字段，避免嵌套如果等节点被裸 MacroGraphNode 覆盖后丢失折叠态
        brPos := this.pos.Has(brId) ? this.pos[brId] : { x: 0, y: 0 }
        for sid, s in serialOf {
            src := this.cmdNodes[sid]
            node := MacroGraphNode()
            node.SerialStr := s
            node.CurCMD := src.CurCMD
            p := this.pos.Has(sid) ? this.pos[sid] : { x: 0, y: 0 }
            node.X := p.x - brPos.x
            node.Y := p.y - brPos.y
            node.NextNodeArr := nextsOf.Has(sid) ? nextsOf[sid] : []
            node.Folded := src.HasOwnProp("Folded") ? src.Folded : 0
            for layoutProp in ["TrueBranchDX", "TrueBranchDY", "FalseBranchDX", "FalseBranchDY", "ExpandShift", "SuccDX", "SuccDY", "FoldSuccDX", "FoldSuccDY", "ProBranchOff", "LoopBodyDX", "LoopBodyDY"] {
                if (src.HasOwnProp(layoutProp))
                    node.%layoutProp% := src.%layoutProp%
            }
            src.SerialStr := s
            SaveMacroCMDData(node)
        }

        ; EmptyNode = 无入边且非入口的自由子节点
        entrySet := Map()
        for e in entries
            entrySet[e] := true
        emptyArr := []
        for sid, s in serialOf {
            if (!hasIncoming[sid] && !entrySet.Has(s))
                emptyArr.Push(s)
        }

        ; 开始节点（复用既有容器开始序列码，无则新建一次并记住）
        startSerial := (this._ilStartSerial.Has(brId) && this._ilStartSerial[brId] != "") ? this._ilStartSerial[brId] : GetCMDSerialStr("图形开始节点")
        this._ilStartSerial[brId] := startSerial
        sn := MacroGraphStartNode()
        sn.SerialStr := startSerial
        sn.NodeArr := entries
        sn.EmptyNode := emptyArr
        sn.X := 60
        sn.Y := 220
        SaveMacroCMDData(sn)

        this._WriteInlineContainerStartSerial(brId, startSerial)
    }

    ; 解析分支内容为记录数组 [{ key, cmd, nexts:[key...], entry, x, y }]。
    ; 图结构：key=各节点真实序列码；线性宏：key="new1"/"new2"… 顺序链接。
    _InlineBranchRecords(startSerial) {
        recs := []
        if (startSerial == "")
            return recs
        SplitSerialTextAndNumbers(startSerial, &t, &n)
        if (t != GetLangKey("图形开始节点") || n == "") {
            ; 线性宏 → 单链
            idx := 0
            prevRec := ""
            for cmd in SplitMacro(startSerial) {
                if (cmd == "")
                    continue
                idx += 1
                rec := { key: "new" idx, cmd: cmd, nexts: [], entry: (prevRec == ""), x: "", y: "" }
                recs.Push(rec)
                if (prevRec != "")
                    prevRec.nexts.Push(rec.key)
                prevRec := rec
            }
            return recs
        }
        startData := GetMacroCMDData(startSerial)
        if (!IsObject(startData))
            return recs
        nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
        emptyArr := (startData.HasOwnProp("EmptyNode") && IsObject(startData.EmptyNode)) ? startData.EmptyNode : []
        entrySet := Map()
        for s in nodeArr
            entrySet[s] := true
        seen := Map()
        queue := []
        for s in nodeArr
            queue.Push(s)
        for s in emptyArr
            queue.Push(s)
        while (queue.Length > 0) {
            s := queue.RemoveAt(1)
            if (s == "" || seen.Has(s))
                continue
            seen[s] := true
            nd := GetMacroCMDData(s)
            cmd := (IsObject(nd) && nd.HasOwnProp("CurCMD")) ? nd.CurCMD : ""
            nexts := (IsObject(nd) && nd.HasOwnProp("NextNodeArr") && IsObject(nd.NextNodeArr)) ? nd.NextNodeArr : []
            rec := { key: s, cmd: cmd, nexts: nexts.Clone(), entry: entrySet.Has(s)
                , x: (IsObject(nd) && nd.HasOwnProp("X")) ? nd.X : ""
                , y: (IsObject(nd) && nd.HasOwnProp("Y")) ? nd.Y : "" }
            recs.Push(rec)
            for ns in nexts
                queue.Push(ns)
        }
        return recs
    }

    ; 内联前驱到后继的目标横向间距：展开的如果/搜索用 ExpandMinGap，普通节点用 260
    _InlineSuccGap(predId) {
        plainStep := 260
        if (!this._HasVisibleBranches(predId) && !this._IsExpandedLoop(predId))
            return plainStep
        return this._ExpandTargetDX(predId)
    }

    ; 内联子节点布局：以分支节点为原点。
    ; X 按前驱累加间距（展开的如果B → 间隔 要用展开间距，不能 level*260）；
    ; Y 同层纵向堆叠；若存盘坐标比计算值更靠右/有 Y，则优先保留用户布局。
    _LayoutInlineSubs(brId, recs, keyToSub) {
        recByKey := Map()
        for rec in recs
            recByKey[rec.key] := rec
        level := Map()
        queue := []
        for rec in recs {
            if (rec.entry && keyToSub.Has(rec.key)) {
                level[keyToSub[rec.key]] := 0
                queue.Push(rec.key)
            }
        }
        while (queue.Length > 0) {
            k := queue.RemoveAt(1)
            if (!recByKey.Has(k) || !keyToSub.Has(k))
                continue
            lv := level[keyToSub[k]]
            for nk in recByKey[k].nexts {
                if (keyToSub.Has(nk) && !level.Has(keyToSub[nk])) {
                    level[keyToSub[nk]] := lv + 1
                    queue.Push(nk)
                }
            }
        }
        predsOf := Map()
        for rec in recs {
            if (!keyToSub.Has(rec.key))
                continue
            fromSub := keyToSub[rec.key]
            for nk in rec.nexts {
                if (!keyToSub.Has(nk))
                    continue
                toSub := keyToSub[nk]
                if (!predsOf.Has(toSub))
                    predsOf[toSub] := []
                predsOf[toSub].Push(fromSub)
            }
        }
        brPos := this.pos.Has(brId) ? this.pos[brId] : { x: 200, y: 200 }
        plainStep := 260
        ; 按层级排序，保证算 X 时前驱已有坐标
        byLevel := []
        for subId, lv in level
            byLevel.Push({ id: subId, lv: lv })
        n := byLevel.Length
        loop n - 1 {
            i := A_Index
            loop n - i {
                j := A_Index
                if (byLevel[j].lv > byLevel[j + 1].lv) {
                    tmp := byLevel[j]
                    byLevel[j] := byLevel[j + 1]
                    byLevel[j + 1] := tmp
                }
            }
        }
        xOf := Map()
        perLevel := Map()
        keyOfSub := Map()
        for k, sid in keyToSub
            keyOfSub[sid] := k
        for item in byLevel {
            subId := item.id
            lv := item.lv
            x := brPos.x + plainStep
            if (predsOf.Has(subId)) {
                x := ""
                for pred in predsOf[subId] {
                    predX := xOf.Has(pred) ? xOf[pred] : brPos.x
                    cand := predX + this._InlineSuccGap(pred)
                    if (x == "" || cand > x)
                        x := cand
                }
                if (x == "")
                    x := brPos.x + plainStep
            }
            idx := perLevel.Has(lv) ? perLevel[lv] : 0
            perLevel[lv] := idx + 1
            y := brPos.y + 150 * idx
            ; 存盘相对坐标：仅当不比展开间距更挤时采用（避免把收起态间距原样搬回来）
            if (keyOfSub.Has(subId) && recByKey.Has(keyOfSub[subId])) {
                rec := recByKey[keyOfSub[subId]]
                if (rec.x != "" && IsNumber(rec.x)) {
                    savedX := brPos.x + (rec.x + 0)
                    if (savedX >= x)
                        x := savedX
                }
                if (rec.y != "" && IsNumber(rec.y))
                    y := brPos.y + (rec.y + 0)
            }
            xOf[subId] := x
            this.pos[subId] := { x: x, y: y }
        }
    }
}

_GraftMacroGraphMixin(MacroGraphInlineMixin)
