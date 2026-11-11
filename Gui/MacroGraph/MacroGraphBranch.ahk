#Requires AutoHotkey v2.0

; ============================================================================
; MacroGraphGui 职能拆分 —— 分支 / 折叠展开 / 布局
;
; 搜索类节点的真/假分支节点显隐、折叠展开、嵌套分支编辑器，以及展开/收起时
; 后继子树的横向平移与位置还原逻辑。方法体保持原样，this 仍为 MacroGraphGui 实例，
; 通过 _GraftMacroGraphMixin 嫁接到 MacroGraphGui.Prototype。
; ============================================================================

class MacroGraphBranchMixin {
    ; 切换搜索/如果节点折叠态：折叠隐藏真/假分支节点（直连后续），展开则显示分支节点。
    ; 如果节点额外：收起时显示条件摘要 + 内嵌真/假分支；展开时恢复完整条件卡。
    ; 运行时显隐 + 连线启停，避免整窗重建闪烁。
    _OnToggleFold(id, *) {
        if (!this.cmdNodes.Has(id))
            return
        node := this.cmdNodes[id]
        willFold := this._NodeFolded(id) ? 0 : 1
        node.Folded := willFold
        SaveMacroCMDData(node)
        if (willFold)
            this._FoldSearchRuntime(id)
        else
            this._UnfoldSearchRuntime(id)
        if (this._IsIfNodeId(id) && this.ui != "") {
            if (willFold) {
                this._RefreshIfSummary(id)
                this._RefreshIfInlineBranches(id)
            }
            this.ui.Update("IfFullBox_" id, "Visibility", willFold ? "Collapsed" : "Visible")
            this.ui.Update("IfSumBox_" id, "Visibility", willFold ? "Visible" : "Collapsed")
            this.ui.Update("IfInlineBranch_" id, "Visibility", willFold ? "Visible" : "Collapsed")
            if (!willFold)
                this._RefreshFormalIfVisibility(id)
        }
        ; 标题按钮图标：折叠→▶（点击展开），展开→▼（点击收起）
        this.ui.Update("SFold_" id, "Content", willFold ? "▶" : "▼")
        this.ui.Update("SFold_" id, "ToolTip", willFold ? GetLang("展开") : GetLang("收起"))
        this._CaptureTopLevelSuccessorLinks()
    }

    ; 切换变量节点折叠态：折叠=只显示各启用变量「变量名 = 值」摘要；展开=完整卡片。
    ; 摘要与完整两套容器同时存在，仅切换显隐（不整窗重建），避免闪烁；节点高度随容器自动收放。
    _OnToggleVarFold(id, *) {
        if (this.ui == "" || !this.cmdNodes.Has(id))
            return
        node := this.cmdNodes[id]
        willFold := this._NodeFolded(id) ? 0 : 1
        node.Folded := willFold
        try SaveMacroCMDData(node)
        if (willFold)
            this._RefreshVariableSummary(id)   ; 收起前用当前值刷新摘要
        this.ui.Update("VarSumBox_" id, "Visibility", willFold ? "Visible" : "Collapsed")
        this.ui.Update("VarFullBox_" id, "Visibility", willFold ? "Collapsed" : "Visible")
        this.ui.Update("SFold_" id, "Content", willFold ? "▶" : "▼")
        this.ui.Update("SFold_" id, "ToolTip", willFold ? GetLang("展开") : GetLang("收起"))
    }

    ; 切换运算节点折叠态：折叠=只显示各启用槽「目标 = 表达式」摘要；展开=完整卡片。
    _OnToggleOpFold(id, *) {
        if (this.ui == "" || !this.cmdNodes.Has(id))
            return
        node := this.cmdNodes[id]
        willFold := this._NodeFolded(id) ? 0 : 1
        node.Folded := willFold
        try SaveMacroCMDData(node)
        if (willFold)
            this._RefreshOperationSummary(id)
        this.ui.Update("OpSumBox_" id, "Visibility", willFold ? "Visible" : "Collapsed")
        this.ui.Update("OpFullBox_" id, "Visibility", willFold ? "Collapsed" : "Visible")
        this.ui.Update("SFold_" id, "Content", willFold ? "▶" : "▼")
        this.ui.Update("SFold_" id, "ToolTip", willFold ? GetLang("展开") : GetLang("收起"))
    }

    ; 切换循环节点折叠态：
    ;   展开(Folded=0)：次数/条件/逻辑/条件卡 + 外置循环体节点（回环连线）；
    ;   收起(Folded=1)：次数/条件下拉保留，条件简化为圆点摘要 + 内置循环体列表，隐藏外置体与回环连线。
    ; 运行时显隐 + 连线启停，避免整窗重建闪烁。
    _OnToggleLoopFold(id, *) {
        if (this.ui == "" || !this.cmdNodes.Has(id))
            return
        node := this.cmdNodes[id]
        willFold := this._NodeFolded(id) ? 0 : 1
        node.Folded := willFold
        try SaveMacroCMDData(node)
        if (willFold) {
            this._FoldLoopRuntime(id)          ; 隐藏外置循环体 + 停用回环连线
            this._RefreshLoopSummary(id)
            this._RefreshLoopChips(id)
        } else {
            this._UnfoldLoopRuntime(id)        ; 显示/注入外置循环体 + 启用回环连线
        }
        this.ui.Update("LoopInlineBody_" id, "Visibility", willFold ? "Visible" : "Collapsed")
        d := this._FormalDFromId(id)
        showCondi := CmdEnumZh(d.HasOwnProp("condiType") ? d.condiType : 1, CmdEnumCondiNames()) != "无"
        this.ui.Update("LoopCondiSumBox_" id, "Visibility", (willFold && showCondi) ? "Visible" : "Collapsed")
        this._RefreshFormalLoopVisibility(id)  ; 同步逻辑/条件卡显隐（收起时隐藏）
        this.ui.Update("SFold_" id, "Content", willFold ? "▶" : "▼")
        this.ui.Update("SFold_" id, "ToolTip", willFold ? GetLang("展开") : GetLang("收起"))
        this._CaptureTopLevelSuccessorLinks()
    }

    ; 折叠循环：隐藏外置循环体节点 + 两条回环路径 + 循环节点右侧两个交互点；后继子树左移靠近循环节点
    _FoldLoopRuntime(loopId) {
        if (this.ui == "")
            return
        bid := this._LoopBodyId(loopId)
        ; 先折叠循环体上的内联展开并回写，再隐藏循环体卡片
        this._CollapseInlineByBrId(bid)
        this.ui.Update("Node_" bid, "Visibility", "Collapsed")
        this.ui.Update("LoopEnterPath_" loopId, "Visibility", "Collapsed")
        this.ui.Update("LoopReturnPath_" loopId, "Visibility", "Collapsed")
        this.ui.Update("LoopCyO_" loopId, "Visibility", "Collapsed")
        this.ui.Update("LoopCyI_" loopId, "Visibility", "Collapsed")
        ; 回环路径两端的三角箭头也随收起隐藏（否则收起后仍残留在循环节点右侧）
        this.ui.Update("LoopEnterTri_" loopId, "Visibility", "Collapsed")
        this.ui.Update("LoopReturnTri_" loopId, "Visibility", "Collapsed")
        this._CaptureTopLevelSuccessorLinks()
        this._SpreadForCollapse(loopId)        ; 收起：后继子树左移，与循环节点保持目标间距
    }

    ; 展开循环：显示（或首次注入）外置循环体节点 + 两条回环路径 + 循环节点右侧两个交互点；后继子树右移恢复
    _UnfoldLoopRuntime(loopId) {
        if (this.ui == "")
            return
        bid := this._LoopBodyId(loopId)
        if (!this._loopBodyInjected.Has(loopId)) {
            this._InjectLoopBodyNode(loopId)
        } else {
            this.ui.Update("Node_" bid, "Visibility", "Visible")
            this.ui.Update("LoopEnterPath_" loopId, "Visibility", "Visible")
            this.ui.Update("LoopReturnPath_" loopId, "Visibility", "Visible")
            this._UpdateLoopCyclePaths(loopId)
        }
        this.ui.Update("LoopCyO_" loopId, "Visibility", "Visible")
        this.ui.Update("LoopCyI_" loopId, "Visibility", "Visible")
        ; 回环路径两端的三角箭头随展开恢复显示
        this.ui.Update("LoopEnterTri_" loopId, "Visibility", "Visible")
        this.ui.Update("LoopReturnTri_" loopId, "Visibility", "Visible")
        this._CaptureTopLevelSuccessorLinks()
        this._SpreadForExpand(loopId)          ; 展开：后继子树右移腾出外置循环体空间
    }

    ; 刷新循环收起态条件摘要（逻辑关系 + 条件圆点行）
    _RefreshLoopSummary(id) {
        if (this.ui == "")
            return
        info := this._LoopSummaryInfo(id)
        this.ui.Update("LoopSumLogic_" id, "Text", GetLang("逻辑关系") "：" info.logicName)
        this.ui.Update("LoopSumLogic_" id, "Visibility", info.showLogic ? "Visible" : "Collapsed")
        data := this._SearchData(id)
        loop 4 {
            slot := A_Index
            ci := this._LoopCondiSummaryRow(data, slot)
            this.ui.Update("LoopSumCondiRow_" slot "_" id, "Visibility", ci.on ? "Visible" : "Collapsed")
            this.ui.Update("LoopSumCondiTxt_" slot "_" id, "Text", ci.text)
        }
    }

    ; 外置循环体节点单击：计时判定双击 → 打开嵌套节点编辑器编辑循环体子图
    _OnLoopBodyClick(loopId, *) {
        now := A_TickCount
        lkey := "LB_" loopId
        if (this._lastClickId == lkey && now - this._lastClickTime < 400) {
            this._lastClickId := ""
            this._lastClickTime := 0
            this._OpenLoopBodyEditor(loopId)
        } else {
            this._lastClickId := lkey
            this._lastClickTime := now
        }
    }

    ; 打开嵌套「节点编辑器」编辑循环体子图；循环体内容以「图形开始节点序列码」存于 LoopBody
    _OpenLoopBodyEditor(loopId) {
        data := this._SearchData(loopId)
        if (data == "")
            return
        if (this.BranchGraphGui == "")
            this.BranchGraphGui := MacroGraphGui()
        cur := ObjHasOwnProp(data, "LoopBody") ? data.LoopBody : ""
        this.BranchGraphGui.OwnerHwnd := (this.ui != "" && this.ui.wpfHwnd) ? this.ui.wpfHwnd : ""
        this.BranchGraphGui.ShowToTreeBtn := false
        this.BranchGraphGui.OnSwitchToTreeAction := ""
        this.BranchGraphGui.SureBtnAction := (startSerial) => this._OnLoopBodyEditorSure(loopId, startSerial)
        this.BranchGraphGui.OnClosedAction := (*) => this._RefreshLoopBodyNode(loopId)
        this.BranchGraphGui.ShowGui(cur, this.WindowBindingContext)
    }

    ; 嵌套循环体编辑器回写：保存循环体子图的开始节点序列码到 LoopData
    _OnLoopBodyEditorSure(loopId, startSerial) {
        data := this._SearchData(loopId)
        if (data == "")
            return
        data.LoopBody := startSerial
        SaveMacroCMDData(data)
    }

    ; 就地刷新变量节点摘要（收起态显示），从当前 INI/解析数据取值，无需重建
    _RefreshVariableSummary(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        anyOn := false
        loop 4 {
            slot := A_Index
            info := this._VarSummaryRowInfo(d, slot)
            if (info.on)
                anyOn := true
            this.ui.Update("VarSumRow_" slot "_" id, "Visibility", info.on ? "Visible" : "Collapsed")
            this.ui.Update("VarSumTxt_" slot "_" id, "Text", info.text)
        }
        this.ui.Update("VarSumEmpty_" id, "Visibility", anyOn ? "Collapsed" : "Visible")
    }

    ; 折叠：隐藏分支节点与「主→分支」连线，主节点直连后续（后继边展开时已存在）
    _FoldSearchRuntime(searchId) {
        g := this.graph
        if (g == "")
            return
        ; 先折叠真/假分支上的内联展开内容并回写，再隐藏分支卡片，避免内联子节点残留画布
        this._CollapseInlineBranch(searchId, true)
        this._CollapseInlineBranch(searchId, false)
        this._CaptureTopLevelSuccessorLinks()                 ; 先取得当前逻辑后继
        succ := this._SuccessorsOf(searchId)
        for conn in g.connections {
            if (this._ConnInvolvesSearchBranch(conn, searchId))
                this._DeactivateConnection(conn)
        }
        for isTrue in [true, false]
            this.ui.Update("Node_" this._BranchId(searchId, isTrue), "Visibility", "Collapsed")
        this._ApplyPairBranchPortVisibility(searchId)
        for x in succ
            this._ActivateConnection(searchId, x)
        this._CaptureTopLevelSuccessorLinks()
        ; 收起：后继子树左移，与搜索节点保持至少 120px 间距
        this._SpreadForCollapse(searchId)
        this._RebindPathClicks()
    }

    ; 展开：显示分支节点并由主节点侧边出点连入；主节点仍直连后续（分支无出点）
    _UnfoldSearchRuntime(searchId) {
        g := this.graph
        if (g == "")
            return
        this._CaptureTopLevelSuccessorLinks()
        succ := this._SuccessorsOf(searchId)
        ; 分支节点：首次展开则注入，否则显隐 + 主→分支连线
        if (!this._branchInjected.Has(searchId)) {
            this._InjectBranchPair(searchId)
        } else {
            for isTrue in [true, false]
                this.ui.Update("Node_" this._BranchId(searchId, isTrue), "Visibility", "Visible")
            this._ActivateConnection(searchId, this._BranchId(searchId, true))
            this._ActivateConnection(searchId, this._BranchId(searchId, false))
        }
        ; 主节点 → 各后续（展开态与收起态一致）
        for x in succ
            this._ActivateConnection(searchId, x)
        this._ApplyPairBranchPortVisibility(searchId)
        this._SchedulePairBranchPathUpdate(searchId)
        ; 展开：若后继离搜索过近，把整条后继子树右移腾出分支显示空间
        this._SpreadForExpand(searchId)
        this._RebindPathClicks()
    }

    ; ---- 搜索/如果：侧边真假出点路径（对齐 BrPort，Tag 供拖动保持起点）----
    _IsPairBranchLink(fromId, toId) {
        if ((!this._IsSearchNodeId(fromId) && !this._IsIfNodeId(fromId)) || !this._IsBranchId(toId))
            return false
        bi := this._BranchInfo(toId)
        return bi != "" && bi.proIdx < 0 && bi.searchId == fromId && (this._IsExpandedSearch(fromId) || this._IsExpandedIf(fromId))
    }

    _PairBranchPathGeom(parentId, toId, px := "", py := "") {
        g := this.graph
        if (g == "")
            return ""
        pn := g.GetNode(parentId)
        bn := g.GetNode(toId)
        if (!pn || !bn)
            return ""
        bi := this._BranchInfo(toId)
        if (bi == "" || bi.proIdx >= 0)
            return ""
        px := (px != "") ? px : pn.X
        py := (py != "") ? py : pn.Y
        nw := this._BranchParentWidth(parentId)
        mt := this._PairBranchPortMarginTop(bi.isTrue)
        sy := py + 30 + mt + 7
        sx := px + nw
        return this._IfProBranchGeom(sx, sy, bn.X, bn.Y + 31)
    }

    _ApplyPairBranchConnectionPath(fromId, toId, pathId, initial := false, pathEl := "") {
        g := this.graph
        geom := this._PairBranchPathGeom(fromId, toId)
        if (geom == "")
            return
        if (initial && pathEl != "") {
            g._SetConnPathData(pathId, geom, true, pathEl)
            sy := this._IfProParsePathStartY(geom)
            pn := g.GetNode(fromId)
            if (sy != "" && pn)
                pathEl.SetProp("Tag", "ifproStartY:" Round(sy - pn.Y))
        } else if (this.ui != "") {
            g._SetConnPathData(pathId, geom)
            sy := this._IfProParsePathStartY(geom)
            if (sy != "")
                this._SetIfProPathDragTag(pathId, fromId, sy)
        }
    }

    _SchedulePairBranchPathUpdate(parentId, px := "", py := "") {
        if (this.ui == "" || this.graph == "")
            return
        this._UpdatePairBranchPaths(parentId, px, py)
    }

    _UpdatePairBranchPaths(parentId, px := "", py := "") {
        g := this.graph
        if (g == "" || this.ui == "" || !(this._IsExpandedSearch(parentId) || this._IsExpandedIf(parentId)))
            return
        for isTrue in [true, false] {
            brId := this._BranchId(parentId, isTrue)
            pathId := g.id "_Path_" parentId "_" brId
            geom := this._PairBranchPathGeom(parentId, brId, px, py)
            if (geom != "") {
                g._SetConnPathData(pathId, geom)
                sy := this._IfProParsePathStartY(geom)
                if (sy != "")
                    this._SetIfProPathDragTag(pathId, parentId, sy)
                g._PlaceConnArrow(brId, pathId)
            }
        }
    }

    ; 取某节点当前的逻辑后继（基于 this.links）
    _SuccessorsOf(id) {
        out := []
        for link in this.links {
            if (link.from == id && this._NodeExists(link.to))
                out.Push(link.to)
        }
        return out
    }

    ; 分支节点单击：用计时判定双击 → 打开嵌套节点编辑器编辑该分支子图
    _OnBranchClick(searchId, isTrue, *) {
        now := A_TickCount
        bkey := "BR_" searchId (isTrue ? "T" : "F")
        if (this._lastClickId == bkey && now - this._lastClickTime < 400) {
            this._lastClickId := ""
            this._lastClickTime := 0
            this._OpenBranchEditor(searchId, isTrue)
        } else {
            this._lastClickId := bkey
            this._lastClickTime := now
        }
    }

    ; 分支节点「展开/收起」按钮：在前 6 条与全部指令之间切换。
    ; 运行时仅切换裁剪容器限高与按钮文字，避免整窗重建闪烁。
    _OnBranchToggleExpand(searchId, isTrue, *) {
        brId := this._BranchId(searchId, isTrue)
        nv := !(this._branchExpanded.Has(brId) && this._branchExpanded[brId])
        this._branchExpanded[brId] := nv
        cmds := this._BranchGraphCmds(this._BranchStartSerial(searchId, isTrue))
        this._RebuildBranchChips(brId, cmds, nv)
        this.ui.Update("SBExpand_" brId, "Content", nv ? GetLang("收起") : (GetLang("展开") " (" cmds.Length ")"))
    }

    ; 打开嵌套「节点编辑器」编辑分支子图；分支内容以「图形开始节点序列码」存于 TrueMacro/FalseMacro
    _OpenBranchEditor(searchId, isTrue) {
        data := this._BranchParentData(searchId)
        if (data == "")
            return
        if (this.BranchGraphGui == "")
            this.BranchGraphGui := MacroGraphGui()
        cur := isTrue ? (ObjHasOwnProp(data, "TrueMacro") ? data.TrueMacro : "") : (ObjHasOwnProp(data, "FalseMacro") ? data.FalseMacro : "")
        this.BranchGraphGui.OwnerHwnd := (this.ui != "" && this.ui.wpfHwnd) ? this.ui.wpfHwnd : ""
        this.BranchGraphGui.ShowToTreeBtn := false
        this.BranchGraphGui.OnSwitchToTreeAction := ""
        this.BranchGraphGui.SureBtnAction := (startSerial) => this._OnBranchEditorSure(searchId, isTrue, startSerial)
        ; 嵌套编辑器关闭后：就地刷新该分支节点的指令清单（不重建父窗口，避免闪烁/重复窗口）
        this.BranchGraphGui.OnClosedAction := (*) => this._RefreshBranchBody(searchId, isTrue)
        this.BranchGraphGui.ShowGui(cur, this.WindowBindingContext)
    }

    ; 嵌套分支编辑器回写：保存分支子图的开始节点序列码到 SearchData（不在此处重建父图，避免实时联动抖动）
    _OnBranchEditorSure(searchId, isTrue, startSerial) {
        data := this._BranchParentData(searchId)
        if (data == "")
            return
        if (isTrue)
            data.TrueMacro := startSerial
        else
            data.FalseMacro := startSerial
        SaveMacroCMDData(data)
    }

    ; 展开循环节点的外置循环体随父节点平移（保持相对位置）
    _ShiftLoopBodyNode(loopId, dx, dy := 0) {
        if ((dx == 0 && dy == 0) || !this._IsExpandedLoop(loopId))
            return
        g := this.graph
        if (g == "")
            return
        bid := this._LoopBodyId(loopId)
        if (this.pos.Has(bid) && g.GetNode(bid))
            this._ShiftNode(bid, dx, dy)
        for conn in g.connections {
            if (conn.From == loopId || conn.To == loopId || this._IsLoopBodyId(conn.From) || this._IsLoopBodyId(conn.To))
                g.UpdatePath(conn.From, conn.To, conn.PathId)
        }
    }

    ; 展开搜索节点的分支节点随父节点平移（保持用户摆放的相对位置，不重置为默认偏移）
    _ShiftBranchNodes(searchId, dx, dy := 0) {
        if (dx == 0 && dy == 0)
            return
        if (this._IsIfProNodeId(searchId)) {
            this._ShiftProBranchNodes(searchId, dx, dy)
            return
        }
        if (!this._HasVisibleBranches(searchId))
            return
        g := this.graph
        if (g == "")
            return
        for isTrue in [true, false] {
            brId := this._BranchId(searchId, isTrue)
            if (this.pos.Has(brId) && g.GetNode(brId))
                this._ShiftNode(brId, dx, dy)
        }
        for conn in g.connections {
            if (conn.From == searchId || this._IsBranchId(conn.From) || this._IsBranchId(conn.To))
                g.UpdatePath(conn.From, conn.To, conn.PathId)
        }
        this._SchedulePairBranchPathUpdate(searchId)
    }

    ; 展开时后继与父节点的最小横向间距：
    ;   · 如果Pro：越过分支区（默认 dx 已含父宽间隙且对齐 grid + 分支宽 200 + 余量）
    ;   · 搜索/如果：越过分支区（默认 dx 网格对齐 + 分支宽 200 + 余量）
    ;   · 循环：越过外置循环体（父宽 + 60 间距 + 循环体宽 200 + 余量）
    _ExpandMinGap(searchId) {
        if (this._IsLoopNodeId(searchId))
            return this._LoopNodeWidth(searchId) + 60 + 200 + 80
        if (this._IsIfProNodeId(searchId))
            return this._IfProBranchDefaultDX() + 200 + 80
        return this._PairBranchDefaultDX(searchId) + 200 + 80
    }

    ; 收起时 A 右缘到后继节点左缘的目标间距（px）
    _CollapseMargin() {
        return 120
    }

    ; 收起时后继节点左缘相对 A 左缘的目标 X 间距（= 节点宽 + 右缘余量）
    _CollapseGap(searchId) {
        return this._BranchParentWidth(searchId) + this._CollapseMargin()
    }

    ; 搜索节点逻辑X
    _NodeX(id) {
        return this.pos.Has(id) ? this.pos[id].x : 0
    }

    ; 搜索节点逻辑Y
    _NodeY(id) {
        return this.pos.Has(id) ? this.pos[id].y : 0
    }

    ; 逻辑边迭代：画布已有连线时用 graph.connections（含内联子图）；否则用 this.links（渲染前静态铺开）
    _LogicEdges() {
        edges := []
        if (this.graph != "" && this.graph.connections.Length > 0) {
            for conn in this.graph.connections {
                if (conn.HasOwnProp("Active") && !conn.Active)
                    continue
                edges.Push({ from: conn.From, to: conn.To })
            }
        } else {
            for link in this.links
                edges.Push({ from: link.from, to: link.to })
        }
        return edges
    }

    ; 直接后继中离搜索节点最近的主节点逻辑 X（跳过分支合成节点，避免误用 B 的分支位置）
    _NearestSuccessorX(searchId) {
        nearest := ""
        for link in this._LogicEdges() {
            if (link.from != searchId || !this.pos.Has(link.to) || this._IsBranchId(link.to) || this._IsProBranchId(link.to))
                continue
            sx := this.pos[link.to].x
            if (nearest == "" || sx < nearest)
                nearest := sx
        }
        return nearest
    }

    ; 直接后继中离搜索节点最近的主节点 id（跳过分支合成节点）；无后继返回 ""
    _NearestSuccessorId(searchId) {
        nearestId := "", nearestX := ""
        for link in this._LogicEdges() {
            if (link.from != searchId || !this.pos.Has(link.to) || this._IsBranchId(link.to) || this._IsProBranchId(link.to))
                continue
            sx := this.pos[link.to].x
            if (nearestX == "" || sx < nearestX) {
                nearestX := sx
                nearestId := link.to
            }
        }
        return nearestId
    }

    ; 收集某节点的全部后代（沿逻辑边传递闭包），跳过分支合成节点
    _DescendantsOf(startId) {
        out := Map()
        queue := []
        edges := this._LogicEdges()
        for link in edges {
            if (link.from == startId && !this._IsBranchId(link.to) && !this._IsProBranchId(link.to))
                queue.Push(link.to)
        }
        while (queue.Length) {
            cur := queue.RemoveAt(1)
            if (out.Has(cur) || cur == startId || this._IsBranchId(cur) || this._IsProBranchId(cur))
                continue
            out[cur] := true
            for link in edges {
                if (link.from == cur && !this._IsBranchId(link.to) && !this._IsProBranchId(link.to))
                    queue.Push(link.to)
            }
        }
        return out
    }

    ; 仅保证展开间距（不记忆 FoldSucc）：后继过近则右移整条后继子树
    _EnsureExpandGap(searchId) {
        if (!this._HasVisibleBranches(searchId) && !this._IsExpandedLoop(searchId))
            return
        succId := this._NearestSuccessorId(searchId)
        if (succId == "" || !this.pos.Has(succId))
            return
        curDX := this.pos[succId].x - this._NodeX(searchId)
        target := this._ExpandTargetDX(searchId)
        if (curDX >= target)
            return
        this._ShiftDescendants(searchId, target - curDX, 0)
    }

    ; 平移单个节点（更新逻辑坐标、引擎坐标与界面位置）
    _ShiftNode(id, dx, dy := 0) {
        if (dx == 0 && dy == 0)
            return
        g := this.graph
        if (this.pos.Has(id))
            this.pos[id] := { x: this.pos[id].x + dx, y: this.pos[id].y + dy }
        n := g.GetNode(id)
        if (n) {
            n.X := n.X + dx
            n.Y := n.Y + dy
            g.ui.Update("Node_" id, "SetPosition", String(n.X) "," String(n.Y))
        }
    }

    ; 兼容旧调用：仅横向平移
    _ShiftNodeX(id, dx) {
        this._ShiftNode(id, dx, 0)
    }

    ; 把搜索节点的整条后继子树平移；展开搜索的主节点平移时，其分支/循环体同步平移
    _ShiftDescendants(searchId, dx, dy := 0) {
        if (dx == 0 && dy == 0)
            return
        g := this.graph
        if (g == "")
            return
        desc := this._DescendantsOf(searchId)
        for id in desc {
            if (this._IsBranchId(id) || this._IsProBranchId(id) || this._IsLoopBodyId(id))
                continue
            this._ShiftNode(id, dx, dy)
            if (this._HasVisibleBranches(id))
                this._ShiftBranchNodes(id, dx, dy)
            if (this._IsExpandedLoop(id))
                this._ShiftLoopBodyNode(id, dx, dy)
        }
        for conn in g.connections
            g.UpdatePath(conn.From, conn.To, conn.PathId)
    }

    ; 兼容旧调用：仅横向平移后继子树
    _ShiftDescendantsX(searchId, dx) {
        this._ShiftDescendants(searchId, dx, 0)
    }

    ; 渲染前（引擎未就绪，只改 this.pos 逻辑坐标）静态平移后继子树。
    ; 用于首次进入时为展开搜索节点预留分支空间，避免分支与后继重叠。
    _StaticShiftDescendantsX(searchId, dx) {
        if (dx == 0)
            return
        desc := this._DescendantsOf(searchId)
        for id in desc {
            if (this._IsBranchId(id) || this._IsProBranchId(id) || !this.pos.Has(id))
                continue
            this.pos[id] := { x: this.pos[id].x + dx, y: this.pos[id].y }
        }
    }

    ; 渲染前：为所有展开的搜索节点预留分支空间。后继离搜索过近（< 展开目标间距）时把后继子树右移到
    ; 目标间距（位置式，幂等；仅在过近时右移，不改动比目标更宽的用户布局），
    ; 修复「首次进入编辑器时搜索后面的分支错乱/重叠」。目标间距见 _ExpandTargetDX（优先用保存的后继相对位置）。
    _StaticSpreadExpandedSearches() {
        for id in this.order {
            if (!this._HasVisibleBranches(id) && !this._IsExpandedLoop(id))
                continue
            nearest := this._NearestSuccessorX(id)
            if (nearest == "")
                continue
            curDX := nearest - this._NodeX(id)
            target := this._ExpandTargetDX(id)
            if (curDX >= target)
                continue
            this._StaticShiftDescendantsX(id, target - curDX)
        }
    }

    ; 展开：先记忆当前收起态后继位置，再把后继子树对齐到展开记忆(SuccDX/DY)：
    ;   · 有记忆的后继偏移(SuccDX≥最小间距)：精确对齐（含 Y）；
    ;   · 无记忆：仅在后继过近时右移到最小间距，已较远的后继不往回拉。
    _SpreadForExpand(searchId) {
        succId := this._NearestSuccessorId(searchId)
        if (succId == "" || !this.pos.Has(succId))
            return
        this._RememberFoldSuccOffset(searchId)
        curDX := this.pos[succId].x - this._NodeX(searchId)
        curDY := this.pos[succId].y - this._NodeY(searchId)
        minGap := this._ExpandMinGap(searchId)
        savedX := this._SavedSuccOffsetX(searchId)
        savedY := this._SavedLayoutOffset(searchId, "SuccDY")
        if (savedX != "" && savedX >= minGap) {
            dx := savedX - curDX
        } else {
            if (curDX >= minGap && savedY == "")
                return
            dx := (curDX >= minGap) ? 0 : (minGap - curDX)
        }
        dy := (savedY != "") ? (savedY - curDY) : 0
        if (dx != 0 || dy != 0)
            this._ShiftDescendants(searchId, dx, dy)
    }

    ; 取节点上保存的布局数值字段；未保存/非法返回 ""
    _SavedLayoutOffset(searchId, prop) {
        if (!this.cmdNodes.Has(searchId))
            return ""
        node := this.cmdNodes[searchId]
        if (!node.HasOwnProp(prop))
            return ""
        v := node.%prop%
        if (v == "" || !IsNumber(v))
            return ""
        return v + 0
    }

    ; 取节点上保存的「最近后继相对 X 偏移」(SuccDX)；未保存/非法返回 ""
    _SavedSuccOffsetX(searchId) {
        return this._SavedLayoutOffset(searchId, "SuccDX")
    }

    ; 取收起态记忆的后继相对 X 偏移 (FoldSuccDX)
    _SavedFoldSuccOffsetX(searchId) {
        return this._SavedLayoutOffset(searchId, "FoldSuccDX")
    }

    ; 展开时「最近后继」相对搜索节点的目标 X 偏移：
    ; 优先用保存/记忆的后继相对位置(SuccDX)，并夹紧到不小于 _ExpandMinGap（保证分支不与后继重叠）；
    ; 无有效保存值时直接用 _ExpandMinGap。
    _ExpandTargetDX(searchId) {
        minGap := this._ExpandMinGap(searchId)
        saved := this._SavedSuccOffsetX(searchId)
        if (saved != "" && saved > minGap)
            return saved
        return minGap
    }

    ; 收起前把当前(展开态)最近后继的相对偏移记忆到 SuccDX/SuccDY，供下次展开精确还原。
    ; 仅当当前偏移确属展开态(>= 最小间距)时记录，避免把收起态的小间距误存为展开偏移。
    _RememberSuccOffset(searchId) {
        if (!this.cmdNodes.Has(searchId))
            return
        succId := this._NearestSuccessorId(searchId)
        if (succId == "" || !this.pos.Has(succId))
            return
        curDX := this.pos[succId].x - this._NodeX(searchId)
        if (curDX < this._ExpandMinGap(searchId))
            return
        node := this.cmdNodes[searchId]
        node.SuccDX := curDX
        node.SuccDY := this.pos[succId].y - this._NodeY(searchId)
        SaveMacroCMDData(node)
    }

    ; 展开前把当前(收起态)最近后继的相对偏移记忆到 FoldSuccDX/DY，供下次收起精确还原。
    _RememberFoldSuccOffset(searchId) {
        if (!this.cmdNodes.Has(searchId))
            return
        succId := this._NearestSuccessorId(searchId)
        if (succId == "" || !this.pos.Has(succId))
            return
        node := this.cmdNodes[searchId]
        node.FoldSuccDX := this.pos[succId].x - this._NodeX(searchId)
        node.FoldSuccDY := this.pos[succId].y - this._NodeY(searchId)
        SaveMacroCMDData(node)
    }

    ; 收起：先记忆当前(展开态)后继偏移，再把后继子树对齐到收起记忆(FoldSuccDX/DY)；
    ; 无收起记忆时回退到默认 _CollapseGap（仅 X）。
    _SpreadForCollapse(searchId) {
        succId := this._NearestSuccessorId(searchId)
        if (succId == "" || !this.pos.Has(succId))
            return
        this._RememberSuccOffset(searchId)
        curDX := this.pos[succId].x - this._NodeX(searchId)
        curDY := this.pos[succId].y - this._NodeY(searchId)
        savedX := this._SavedFoldSuccOffsetX(searchId)
        savedY := this._SavedLayoutOffset(searchId, "FoldSuccDY")
        targetDX := (savedX != "") ? savedX : this._CollapseGap(searchId)
        ; 收起间距不应大于展开最小间距（否则分支区仍被撑开）
        maxFold := this._ExpandMinGap(searchId) - 40
        if (maxFold > 0 && targetDX > maxFold)
            targetDX := maxFold
        if (targetDX < 80)
            targetDX := this._CollapseGap(searchId)
        dx := targetDX - curDX
        dy := (savedY != "") ? (savedY - curDY) : 0
        if (dx != 0 || dy != 0)
            this._ShiftDescendants(searchId, dx, dy)
    }
}

_GraftMacroGraphMixin(MacroGraphBranchMixin)
