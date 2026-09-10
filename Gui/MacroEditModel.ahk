#Requires AutoHotkey v2.0

; =====================================================================
; MacroEditGui 的 XAML 迁移基础：节点模型 + 原生 TreeView 兼容适配器
;
; 思路：MacroEditGui 约 1800 行逻辑直接调用原生 AHK TreeView API
; （Add/Delete/Modify/GetText/GetParent/GetChild/GetNext/GetPrev），
; 用 MacroTreeAdapter 把这些调用翻译到内存节点树（MacroEditNode），
; 视图用 WPF TreeView 全量重建 + SelectByTag 恢复选中，从而让现有
; 逻辑层基本原样保留。
;
; ponytail: 全量重建（宏体量千条内无感），后续若超大宏卡顿再改增量。
; =====================================================================

class MacroEditNode {
    __New(id, text, icon, parent := "") {
        this.id := id
        this.text := text          ; 显示文本（含 ⭐/🚫/→/⎖ 前缀）
        this.icon := icon          ; 图标文件绝对路径（/ 分隔）
        this.parent := parent
        this.children := []
        this.checked := false      ; 多选标记
        this.expanded := true      ; 展开状态
        this.splitView := "both"   ; 真假分栏：both / true / false
        this.debugCur := false     ; 调试当前位置（→）标记：纯瞬态内存字段，绝不写入 node.text
        this.debugBp := false      ; 断点标记：纯瞬态内存字段，绝不写入 node.text（独立 Brk_ 图标通道）
    }
}

class MacroTreeAdapter {
    __New(ui, treeName) {
        this.ui := ui
        this.treeName := treeName
        this.nodes := Map()        ; id → MacroEditNode
        this.roots := []           ; 根节点数组
        this._seq := 0
        this._redrawSuspended := false
        this._visible := false
        this._iconMap := Map()     ; "IconN" → 文件路径（兼容旧调用）
        this._events := Map()      ; 事件名 → 回调（右键/双击，P5 接线）
        this._renderCause := ""    ; 临时诊断
        this._suppressRender := false  ; 拖拽期间禁止全量重建
        this._splitRenderPending := false
    }

    Hwnd {
        get => (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    Visible {
        get => this._visible
        set {
            this._visible := value
            if (IsObject(this.ui))
                this.ui.Update(this.treeName, "Visibility", value ? "Visible" : "Collapsed")
        }
    }

    SetImageList(id) {
        ; 图标嵌入节点 Header，图片列表无用
    }

    SetIconMap(iconMap) {
        this._iconMap := iconMap
    }

    Opt(options) {
        if (InStr(options, "-Redraw"))
            this._redrawSuspended := true
        else if (InStr(options, "+Redraw")) {
            this._redrawSuspended := false
            this._renderCause := "Opt+Redraw"
            this.Render()
        }
    }

    Focus() {
        if (IsObject(this.ui))
            this.ui.Update(this.treeName, "Focus", "True")
    }

    OnEvent(event, callback) {
        this._events[event] := callback
    }

    ; ---------------- 遍历（id 为节点 id 字符串；0 表示根） ----------------

    GetParent(id) {
        if (id == 0)
            return 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        return (node && node.parent) ? node.parent.id : 0
    }

    GetChild(id) {
        if (id == 0)
            return this.roots.Length ? this.roots[1].id : 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        return (node && node.children.Length) ? node.children[1].id : 0
    }

    GetNext(id) {
        if (id == 0)
            return this.roots.Length ? this.roots[1].id : 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        if (!node)
            return 0
        siblings := node.parent ? node.parent.children : this.roots
        i := this._IndexOf(siblings, node.id)
        return (i > 0 && i < siblings.Length) ? siblings[i + 1].id : 0
    }

    GetPrev(id) {
        if (id == 0)
            return 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        if (!node)
            return 0
        siblings := node.parent ? node.parent.children : this.roots
        i := this._IndexOf(siblings, node.id)
        return i > 1 ? siblings[i - 1].id : 0
    }

    GetText(id) {
        if (id == 0)
            return ""
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        return node ? node.text : ""
    }

    GetCount() {
        count := 0
        for node in this.roots
            count += this._CountChildren(node)
        return count
    }

    IsExpanded(id) {
        if (id == 0 || !this.nodes.Has(id))
            return false
        return this.nodes[id].expanded
    }

    ; ---------------- 修改 ----------------

    Modify(id, options := "", newText := "") {
        if (id == 0 || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        needsRender := false
        if (newText != "" && node.text != newText) {
            node.text := newText
            ; 增量更新文本块，不整树重建
            if (IsObject(this.ui)) {
                this.ui.Update("Txt_" id, "Text", CmdStripDebug(newText))
                try this.ui.Update("Dbg_" id, "Visibility", CmdIsDebug(newText) ? "Visible" : "Collapsed")
            }
            this._UpdateCheckMark(id)
        }
        ; 勾选只更新 ✓ 标记，不触发全量重渲染（避免点击闪烁/覆盖折叠）
        if (InStr(options, "Check") && !node.checked) {
            node.checked := true
            this._UpdateCheckMark(id)
        } else if (InStr(options, "-Check") && node.checked) {
            node.checked := false
            this._UpdateCheckMark(id)
        }
        if (InStr(options, "Expand") && !node.expanded) {
            node.expanded := true
            needsRender := true
        } else if (InStr(options, "Collapse") && node.expanded) {
            node.expanded := false
            needsRender := true
        }
        if (InStr(options, "Select"))
            this._Select(id)
        if (needsRender && !this._redrawSuspended) {
            this._renderCause := "Modify:" options
            this.Render()
        }
    }

    ; 调试当前位置（→）标记：只改节点字段并增量刷新 Cur_ 图标，绝不修改 node.text。
    ; 这样 → 不会经 GetTreeMacroStr / 快照 / 侧栏写回链路进入真实宏串（解 G1）。
    SetCurrentPos(id, on) {
        if (id == 0 || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        node.debugCur := on ? true : false
        if (IsObject(this.ui))
            try this.ui.Update("Cur_" id, "Visibility", node.debugCur ? "Visible" : "Collapsed")
    }

    ; 断点标记：只改节点字段并增量刷新 Brk_ 图标，绝不修改 node.text。
    ; 与 SetCurrentPos / Dbg_ 一样走独立图标通道，零文本污染（解 G1 同类约束）。
    SetBreakPoint(id, on) {
        if (id == 0 || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        node.debugBp := on ? true : false
        if (IsObject(this.ui))
            try this.ui.Update("Brk_" id, "Visibility", node.debugBp ? "Visible" : "Collapsed")
    }

    ; 读取节点断点标记（字段，非文本）；不存在返回 false
    IsBreakPoint(id) {
        if (id == 0 || !this.nodes.Has(id))
            return false
        node := this.nodes[id]
        return (node.HasProp("debugBp") && node.debugBp) ? true : false
    }

    ; 更新单个节点的多选高亮（无勾选框，改卡片底色）
    _UpdateCheckMark(id) {
        if (!IsObject(this.ui) || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        this.ui.Update("CardBd_" id, "Background", this._CardBgXml(node, this._FlatIndexOf(id)))
        try this.ui.Update("CardInner_" id, "Opacity", this._NodeIsSkip(node) ? "0.42" : "1")
    }

    Unselect() {
        if (IsObject(this.ui))
            try this.ui.Update(this.treeName, "SelectedIndex", "-1")
    }

    _NodeIsSkip(node) {
        return IsObject(node) && InStr(node.text, "🚫")
    }

    _CardBgXml(node, flatIdx := 0) {
        if (node.checked)
            return "{DynamicResource TabSelBg}"
        if (this._NodeIsSkip(node))
            return "{DynamicResource ListRowForbidBg}"
        return ((flatIdx >= 0 && Mod(flatIdx, 2) == 0) ? "{DynamicResource DropdownBg}" : "{DynamicResource ListRowAltBg}")
    }

    _Select(id) {
        if (IsObject(this.ui))
            this.ui.Update(this.treeName, "SelectByTag", id)
    }

    ; ---------------- 添加 ----------------

    Add(text, parentID := 0, options := "") {
        opts := StrSplit(Trim(options), A_Space)
        insertBefore := false
        insertAfterId := ""
        icon := ""
        for token in opts {
            if (token == "First")
                insertBefore := true
            else if (token != "" && this.nodes.Has(token))
                insertAfterId := token
            else if (token != "")
                icon := this._ResolveIcon(token)
        }
        this._seq += 1
        id := "n" this._seq
        node := MacroEditNode(id, text, icon)
        this.nodes[id] := node
        ; 父节点由叶变父（0→1 子）需补展开箭头，整树重建一次；其余增量插入
        parentWasLeaf := (parentID != 0 && this.nodes.Has(parentID) && this.nodes[parentID].children.Length == 0)
        if (parentID != 0 && this.nodes.Has(parentID)) {
            node.parent := this.nodes[parentID]
            this._InsertInto(node.parent.children, node, insertBefore, insertAfterId)
        } else {
            this._InsertInto(this.roots, node, insertBefore, insertAfterId)
        }
        if (!this._redrawSuspended) {
            if (this._AffectsSplit(node)) {
                this._ScheduleSplitRender()
                return id
            }
            if (parentWasLeaf)
                this._UpdateArrow(parentID)
            if (this._IsVisible(node)) {
                idx := this._FlatIndexOf(id)
                if (idx >= 0)
                    this.ui.Update(this.treeName, "InsertXamlItem", idx "|" this._BuildCardXml(node, this._Depth(node), idx))
                else
                    this.Render()
            }
        }
        return id
    }

    _InsertInto(arr, node, insertBefore, insertAfterId) {
        if (insertBefore) {
            arr.InsertAt(1, node)
            return
        }
        if (insertAfterId != "") {
            for i, n in arr
                if (n.id == insertAfterId) {
                    arr.InsertAt(i + 1, node)
                    return
                }
        }
        arr.Push(node)
    }

    _ResolveIcon(token) {
        return this._iconMap.Has(token) ? this._iconMap[token] : token
    }

    ; ---------------- 删除 ----------------

    Delete(id := "") {
        ; 原生 Delete() 无参 = 清空整棵
        if (id == "") {
            this.nodes := Map()
            this.roots := []
            if (!this._redrawSuspended) {
                this._renderCause := "Delete-all"
                this.Render()
            }
            return
        }
        if (!this.nodes.Has(id))
            return
        node := this.nodes[id]
        ; 先收集可见卡片 id（改模型前），删单个节点时增量移除，避免整树重建
        visibleIds := []
        if (this._IsVisible(node))
            this._CollectVisibleIds(node, &visibleIds)
        ; 父节点由父变叶（1→0 子）需去箭头，整树重建一次
        parentBecomesLeaf := (node.parent && node.parent.children.Length == 1)
        if (node.parent) {
            arr := node.parent.children
            for i, n in arr
                if (n.id == id) {
                    arr.RemoveAt(i)
                    break
                }
        } else {
            for i, n in this.roots
                if (n.id == id) {
                    this.roots.RemoveAt(i)
                    break
                }
        }
        this._RemoveRecursive(node)
        if (!this._redrawSuspended) {
            if (this._AffectsSplit(node)) {
                this._ScheduleSplitRender()
                return
            }
            if (parentBecomesLeaf && node.parent)
                this._UpdateArrow(node.parent.id)
            for vid in visibleIds
                this.ui.Update(this.treeName, "RemoveItem", vid)
        }
    }

    _RemoveRecursive(node) {
        for child in node.children
            this._RemoveRecursive(child)
        this.nodes.Delete(node.id)
    }

    ; ---------------- 渲染 ----------------

    Render() {
        if (!IsObject(this.ui) || this._redrawSuspended || this._suppressRender)
            return
        this._renderCause := ""
        this.ui.Update(this.treeName, "ClearItems", "")
        ; 展平为可见节点（仅展开分支），深度=缩进
        cards := []
        for root in this.roots
            this._AppendVisibleCards(root, 0, &cards)
        ; 批量推送卡片：逐条 Update 是 N 次同步 IPC 往返（千条级宏打开/刷新卡顿元凶），
        ; 合并为少量 BatchUpdate 分块（WM_COPYDATA 单消息体量限制，按字节分块），一次往返处理多条。
        this._BatchPushCards(cards)
    }

    ; 分块批量推送 AddXamlItem：单块控制在 ~36KB 以内（含 UTF-8 中文 3 字节/字），
    ; 单次 WM_COPYDATA 安全上限 64KB，留足余量避免大宏超限丢消息。
    _BatchPushCards(cards) {
        if (cards.Length == 0)
            return
        chunk := []
        chunkBytes := 0
        maxBytes := 36000
        for xml in cards {
            if (xml == "")
                continue
            chunk.Push({ControlName: this.treeName, PropertyName: "AddXamlItem", Value: xml})
            chunkBytes += StrPut(xml, "UTF-8") - 1
            if (chunkBytes >= maxBytes) {
                if (chunk.Length > 0)
                    this.ui.BatchUpdate(chunk)
                chunk := []
                chunkBytes := 0
            }
        }
        if (chunk.Length > 0)
            this.ui.BatchUpdate(chunk)
    }

    ; 节点落在搜索/如果的真假分栏里时，增删需整段重画
    _AffectsSplit(node) {
        p := IsObject(node) ? node : ""
        while (IsObject(p)) {
            t := this._CleanNodeText(p)
            if (t == GetLang("真") || t == GetLang("假"))
                return true
            if (IsObject(this._FindTrueFalsePair(p)))
                return true
            p := p.parent
        }
        return false
    }

    ToggleSplitView(searchId, which) {
        if (!IsObject(this.nodes) || !this.nodes.Has(searchId))
            return
        node := this.nodes[searchId]
        cur := (node.HasProp("splitView") && node.splitView != "") ? node.splitView : "both"
        if (which == "T")
            node.splitView := (cur == "true") ? "both" : "true"
        else if (which == "F")
            node.splitView := (cur == "false") ? "both" : "false"
        else
            return
        this._renderCause := "SplitView"
        this.Render()
    }

    _ScheduleSplitRender() {
        if (this._splitRenderPending)
            return
        this._splitRenderPending := true
        SetTimer(ObjBindMethod(this, "_FlushSplitRender"), -1)
    }

    _FlushSplitRender() {
        this._splitRenderPending := false
        if (!this._redrawSuspended && !this._suppressRender)
            this.Render()
    }

    _FindTrueFalsePair(node) {
        trueN := "", falseN := ""
        if (!IsObject(node))
            return ""
        for child in node.children {
            t := this._CleanNodeText(child)
            if (t == GetLang("真"))
                trueN := child
            else if (t == GetLang("假"))
                falseN := child
        }
        if (IsObject(trueN) && IsObject(falseN))
            return {true: trueN, false: falseN}
        return ""
    }

    ; 真/假栏内是否还有更深层的搜索/如果（它们自己也带真假对）
    _SubtreeHasTrueFalsePair(node) {
        if (!IsObject(node))
            return false
        for child in node.children {
            if (IsObject(this._FindTrueFalsePair(child)))
                return true
            if (this._SubtreeHasTrueFalsePair(child))
                return true
        }
        return false
    }

    ; 仅最内层搜索/如果用左右分栏；上级一律树形，避免套娃分栏过窄
    _ShouldUseSplit(node) {
        pair := this._FindTrueFalsePair(node)
        if (!IsObject(pair))
            return false
        return !this._SubtreeHasTrueFalsePair(pair.true) && !this._SubtreeHasTrueFalsePair(pair.false)
    }

    ; ⚠️ 当前无调用方：旧「嵌套分栏左缘拉回一级」策略专用，2026-09-10 弃用后保留以备回退
    _FirstLevelNode(node) {
        p := node
        while (IsObject(p) && IsObject(p.parent))
            p := p.parent
        return p
    }

    ; ⚠️ 当前无调用方（同上）
    _FindAncestorPairOwner(node) {
        p := IsObject(node) ? node.parent : ""
        while (IsObject(p)) {
            if (IsObject(this._FindTrueFalsePair(p)))
                return p
            p := p.parent
        }
        return ""
    }

    ; 递归收集可见节点卡片（塌陷分支不进入）
    _AppendVisibleCards(node, depth, &cards) {
        cards.Push(this._BuildCardXml(node, depth, cards.Length))
        if (!node.expanded)
            return
        pair := this._FindTrueFalsePair(node)
        if (IsObject(pair) && this._ShouldUseSplit(node)) {
            cards.Push(this._BuildSplitPairXml(pair, cards.Length))
            for child in node.children {
                if (child != pair.true && child != pair.false)
                    this._AppendVisibleCards(child, depth + 1, &cards)
            }
            return
        }
        for child in node.children
            this._AppendVisibleCards(child, depth + 1, &cards)
    }

    _SplitViewMode(pair) {
        parent := (IsObject(pair) && IsObject(pair.true)) ? pair.true.parent : ""
        if (IsObject(parent) && parent.HasProp("splitView") && parent.splitView != "")
            return parent.splitView
        return "both"
    }

    _SplitRailW() {
        return 16
    }

    ; 顶层分栏：左缘对齐一级搜索/如果的图标左边，右缘贴齐内容区
    _BuildSplitPairXml(pair, flatIdx := 0) {
        inset := this._SplitPairLeftInset(pair)
        view := this._SplitViewMode(pair)
        tag := pair.true.id "+" pair.false.id "+" inset "+" view
        return '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
            . ' Tag="' tag '" Background="Transparent" BorderThickness="0" Padding="0" Margin="0" HorizontalContentAlignment="Stretch">'
            . '<Grid HorizontalAlignment="Stretch" Margin="' inset ',0,0,0">'
            . this._BuildSplitPairBodyXml(pair, view, flatIdx)
            . '</Grid></ListBoxItem>'
    }

    _BuildSplitPairBodyXml(pair, view, flatIdx := 0) {
        leftXml := this._BuildBranchColumnItems(pair.true, flatIdx)
        rightXml := this._BuildBranchColumnItems(pair.false, flatIdx)
        rowH := 26
        railW := this._SplitRailW()
        stroke := "{DynamicResource ControlBorder}"
        searchId := ""
        if (IsObject(pair.true) && IsObject(pair.true.parent))
            searchId := pair.true.parent.id
        rail := this._SplitRailXml(searchId, view)
        leftCol := this._SplitColumnXml(pair.true, leftXml, true, rowH, searchId, view)
        rightCol := this._SplitColumnXml(pair.false, rightXml, false, rowH, searchId, view)
        cols := ""
        body := ""
        if (view == "true") {
            cols := '<ColumnDefinition Width="*"/><ColumnDefinition Width="' railW '"/>'
            body := '<Grid Grid.Column="0">' leftCol '</Grid>'
                . '<Grid Grid.Column="1">' rail '</Grid>'
        } else if (view == "false") {
            cols := '<ColumnDefinition Width="' railW '"/><ColumnDefinition Width="*"/>'
            body := '<Grid Grid.Column="0">' rail '</Grid>'
                . '<Grid Grid.Column="1">' rightCol '</Grid>'
        } else {
            cols := '<ColumnDefinition Width="*"/><ColumnDefinition Width="' railW '"/><ColumnDefinition Width="*"/>'
            body := '<Grid Grid.Column="0">' leftCol '</Grid>'
                . '<Grid Grid.Column="1">' rail '</Grid>'
                . '<Grid Grid.Column="2">' rightCol '</Grid>'
        }
        return '<Border BorderBrush="' stroke '" BorderThickness="1" Background="Transparent" HorizontalAlignment="Stretch" SnapsToDevicePixels="True">'
            . '<Grid MinHeight="' rowH '" HorizontalAlignment="Stretch">'
            . '<Grid.ColumnDefinitions>' cols '</Grid.ColumnDefinitions>'
            . body
            . '</Grid></Border>'
    }

    _SplitColumnXml(branchNode, itemsXml, isTrue, rowH, searchId := "", view := "both") {
        bid := IsObject(branchNode) ? branchNode.id : ""
        return '<Grid Name="SplitCol_' bid '" Tag="' bid '" MinHeight="' rowH '" HorizontalAlignment="Stretch">'
            . '<StackPanel VerticalAlignment="Top" HorizontalAlignment="Stretch">' itemsXml '</StackPanel>'
            . this._SplitBranchBadgeXml(branchNode, isTrue, searchId, view)
            . '</Grid>'
    }

    _SplitRailXml(searchId, view) {
        stroke := "{DynamicResource ControlBorder}"
        return '<Grid HorizontalAlignment="Stretch" VerticalAlignment="Stretch" IsHitTestVisible="False">'
            . '<Rectangle Width="1" HorizontalAlignment="Center" VerticalAlignment="Stretch" Fill="' stroke '" SnapsToDevicePixels="True"/>'
            . '</Grid>'
    }

    _SplitRailBtnXml(name, src, opacity, tip) {
        src := StrReplace(src, "\", "/")
        return '<Button Name="' name '" Width="16" Height="16" Margin="0,2,3,0" Padding="0" Cursor="Hand"'
            . ' HorizontalAlignment="Right" VerticalAlignment="Top"'
            . ' Focusable="False" Background="Transparent" BorderThickness="0" ToolTip="' this._EscapeXml(tip) '">'
            . '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="Transparent" CornerRadius="2" Width="16" Height="16">'
            . '<Image Source="' this._EscapeXml(src) '" Width="12" Height="12" Opacity="' opacity '"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBgHover}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Button.Template></Button>'
    }

    _BuildBranchColumnItems(branchNode, flatIdx := 0) {
        xml := ""
        if (!IsObject(branchNode) || !branchNode.expanded)
            return this._BuildSplitEmptyXml(IsObject(branchNode) ? branchNode.id : "")
        for child in branchNode.children
            xml .= this._AppendSplitChildXml(child, branchNode, flatIdx)
        return (xml == "") ? this._BuildSplitEmptyXml(branchNode.id) : xml
    }

    _AppendSplitChildXml(node, depthBase, flatIdx := 0) {
        d := this._Depth(node) - this._Depth(depthBase) - 1
        if (d < 0)
            d := 0
        xml := this._BuildCardInnerXml(node, d, flatIdx, true)
        if (!node.expanded)
            return xml
        for child in node.children
            xml .= this._AppendSplitChildXml(child, depthBase, flatIdx)
        return xml
    }

    ; 分栏左缘一律对齐【所属父容器】的图标左边：
    ;   - 顶层：父容器即一级搜索/如果 → 左缘对齐一级图标左边（原行为不变）
    ;   - 嵌套：父容器即该嵌套容器自身 → 左缘随父级缩进，不再被拉回最左侧
    ; （2026-09-10 用户反馈：多重嵌套下分栏框贴最左侧，与父级缩进脱节）
    ; 上限保护（T5）：_WidthBeforeIcon 随嵌套深度每层 +20px 线性增长，深度 ≳15 时
    ; inset 会吃掉整块面板宽度、把真/假两栏压成 0 宽。故取 Min(计算值, _SplitInsetCap())：
    ; 浅嵌套（≤ 约 8 层，计算值 ≤ 约 180）远低于上限 → Min 不生效，顶层与浅嵌套行为零变化。
    _SplitPairLeftInset(pair) {
        owner := (IsObject(pair) && IsObject(pair.true)) ? pair.true.parent : ""
        prefix := IsObject(owner) ? this._WidthBeforeIcon(owner) : 20
        return Min(2 + prefix, this._SplitInsetCap())
    }

    ; 分栏 inset 上限（像素）：inset + rail(_SplitRailW()=16) 之后须为真/假两栏各留最小可读
    ; 宽度（行高 26、图标约 20px）。180 对常见面板宽度可保证两栏 > 0 宽，且高于所有浅嵌套值。
    _SplitInsetCap() {
        return 180
    }

    _SplitBranchBadgeXml(branchNode, isTrue, searchId := "", view := "both") {
        src := ""
        if (IsObject(branchNode) && branchNode.HasProp("icon") && branchNode.icon != "")
            src := branchNode.icon
        if (src == "")
            src := "Images/Soft/" (isTrue ? "True.png" : "False.png")
        src := StrReplace(src, "\", "/")
        which := isTrue ? "true" : "false"
        name := (isTrue ? "SplitViewT_" : "SplitViewF_") searchId
        op := (view == which) ? "1" : "0.72"
        tip := (view == which) ? GetLang("显示全部") : (isTrue ? GetLang("只显示真") : GetLang("只显示假"))
        return this._SplitRailBtnXml(name, src, op, tip)
    }

    _BuildSplitEmptyXml(fallbackId) {
        return '<Border Tag="' fallbackId '" Background="Transparent" MinHeight="26" HorizontalAlignment="Stretch"/>'
    }

    _IsLastChild(node) {
        if (!IsObject(node) || !IsObject(node.parent))
            return true
        kids := node.parent.children
        return kids.Length > 0 && kids[kids.Length] == node
    }

    ; 清理节点显示前缀（调试/跳过等标记），便于识别真/假容器
    _CleanNodeText(node) {
        t := node.text
        ; 仅剥行首 →（调试位置标记）；→ 亦是手柄 D-pad「右」显示名，不可全局剥离
        t := CmdStripCurPos(t)
        while (t != "") {
            ch := SubStr(t, 1, 1)
            if (ch == Chr(0x25B6) || ch == Chr(0x2B50) || ch == "🚫" || ch == "→" || ch == "⎖" || ch == " ")
                t := SubStr(t, 2)
            else
                break
        }
        return t
    }

    ; 真 / 假 / 循环体 / 条件*：分支容器（自身不接上级连线）
    _IsBranchContainer(node) {
        if (!IsObject(node))
            return false
        t := this._CleanNodeText(node)
        if (t == GetLang("真") || t == GetLang("假") || t == GetLang("循环体"))
            return true
        cond := GetLang("条件")
        return (cond != "" && SubStr(t, 1, StrLen(cond)) == cond)
    }

    _FindBranchAncestor(node) {
        p := node.parent
        while (IsObject(p)) {
            if (this._IsBranchContainer(p))
                return p
            p := p.parent
        }
        return ""
    }

    ; 该行「指令图标」左侧已占用宽度（用于对齐下级展开符/连线）
    _WidthBeforeIcon(node) {
        if (!IsObject(node))
            return 0
        d := this._Depth(node)
        if (d == 0)
            return 20
        if (this._IsBranchContainer(node))
            return this._WidthBeforeIcon(node.parent) + 20
        branchAnc := this._FindBranchAncestor(node)
        if (IsObject(branchAnc)) {
            levels := this._Depth(node) - this._Depth(branchAnc)
            if (levels < 1)
                levels := 1
            return this._WidthBeforeIcon(branchAnc) + 20 * levels
        }
        return 20 * (d + 1)
    }

    _PadSlotXml(w := 20) {
        return '<Border Width="' w '" Height="20" Background="Transparent"/>'
    }

    ; 展开/收缩按钮（加大加粗）；overlay=true 时叠在引导列中心
    _BuildArrowBtnXml(node, glyph, overlay := false) {
        w := 20
        align := overlay ? ' HorizontalAlignment="Center"' : ""
        return '<Button Name="Arrow_' node.id '" Width="' w '" Height="' w '" Margin="0" Padding="0"'
            . ' Cursor="Hand" Focusable="False" VerticalAlignment="Center"' align
            . ' Background="Transparent" BorderThickness="0" Panel.ZIndex="1"'
            . ' HorizontalContentAlignment="Center" VerticalContentAlignment="Center">'
            . '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="3" Width="' w '" Height="' w '">'
            . '<TextBlock Name="Arrow_' node.id '_Txt" Text="' glyph '"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" FontWeight="Bold"'
            . ' Foreground="{DynamicResource TextMain}" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBgHover}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Button.Template></Button>'
    }

    ; 图标列引导：竖线在图标中心(8)；有子时展开符叠在该列
    _BuildIconColGuideXml(node, hasMore, hasChild, glyph := "") {
        colW := 20
        lineX := 8
        line := "{DynamicResource ControlBorder}"
        if (hasChild) {
            arrowXml := this._BuildArrowBtnXml(node, glyph, true)
        } else {
            arrowXml := '<Border Name="Arrow_' node.id '" Width="0" Height="0">'
                . '<TextBlock Name="Arrow_' node.id '_Txt" Text=""/></Border>'
        }
        if (hasMore) {
            return '<Grid Width="' colW '" VerticalAlignment="Stretch">'
                . '<Rectangle Width="1" Margin="' lineX ',0,0,0" HorizontalAlignment="Left" VerticalAlignment="Stretch" Fill="' line '" SnapsToDevicePixels="True"/>'
                . '<Rectangle Height="1" VerticalAlignment="Center" Margin="' lineX ',0,0,0" HorizontalAlignment="Stretch" Fill="' line '" SnapsToDevicePixels="True"/>'
                . arrowXml
                . '</Grid>'
        }
        arrowSpan := hasChild ? StrReplace(arrowXml, 'Name="Arrow_', 'Grid.RowSpan="2" Name="Arrow_', 1) : arrowXml
        return '<Grid Width="' colW '" VerticalAlignment="Stretch">'
            . '<Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<Rectangle Grid.Row="0" Width="1" Margin="' lineX ',0,0,0" HorizontalAlignment="Left" VerticalAlignment="Stretch" Fill="' line '" SnapsToDevicePixels="True"/>'
            . '<Rectangle Grid.Row="0" Grid.RowSpan="2" Height="1" VerticalAlignment="Center" Margin="' lineX ',0,0,0" HorizontalAlignment="Stretch" Fill="' line '" SnapsToDevicePixels="True"/>'
            . arrowSpan
            . '</Grid>'
    }

    _BuildCardPrefixXml(node, depth, colMode := false) {
        hasChild := node.children.Length > 0
        isBranch := this._IsBranchContainer(node)
        glyph := hasChild ? (node.expanded ? Chr(0xE70D) : Chr(0xE76C)) : ""
        prefix := ""
        if (colMode) {
            ; 分栏内：不画真/假列头，列内指令从 depth=0 起画连线
            if (depth == 0)
                return hasChild ? this._BuildArrowBtnXml(node, glyph, false) : this._PadSlotXml(20)
            line := "{DynamicResource ControlBorder}"
            loop (depth - 1) {
                prefix .= '<Grid Width="16" VerticalAlignment="Stretch">'
                    . '<Rectangle Width="1" Margin="8,0,0,0" HorizontalAlignment="Left" VerticalAlignment="Stretch" Fill="' line '" SnapsToDevicePixels="True"/>'
                    . '</Grid>'
            }
            prefix .= this._BuildIconColGuideXml(node, !this._IsLastChild(node), hasChild, glyph)
            return prefix
        }
        if (depth == 0) {
            prefix := hasChild ? this._BuildArrowBtnXml(node, glyph, false) : this._PadSlotXml(20)
        } else if (isBranch) {
            pad := this._WidthBeforeIcon(node.parent)
            if (pad > 0)
                prefix .= this._PadSlotXml(pad)
            prefix .= hasChild ? this._BuildArrowBtnXml(node, glyph, false) : this._PadSlotXml(20)
        } else {
            branchAnc := this._FindBranchAncestor(node)
            if (IsObject(branchAnc)) {
                pad := this._WidthBeforeIcon(branchAnc)
                if (pad > 0)
                    prefix .= this._PadSlotXml(pad)
                gap := this._Depth(node) - this._Depth(branchAnc) - 1
                line := "{DynamicResource ControlBorder}"
                loop gap {
                    prefix .= '<Grid Width="20" VerticalAlignment="Stretch">'
                        . '<Rectangle Width="1" Margin="8,0,0,0" HorizontalAlignment="Left" VerticalAlignment="Stretch" Fill="' line '" SnapsToDevicePixels="True"/>'
                        . '</Grid>'
                }
                prefix .= this._BuildIconColGuideXml(node, !this._IsLastChild(node), hasChild, glyph)
            } else {
                pad := this._WidthBeforeIcon(node.parent)
                if (pad > 0)
                    prefix .= this._PadSlotXml(pad)
                if (hasChild)
                    prefix .= this._BuildArrowBtnXml(node, glyph, false)
                else
                    prefix .= '<Border Name="Arrow_' node.id '" Width="0" Height="0"><TextBlock Name="Arrow_' node.id '_Txt" Text=""/></Border>'
            }
        }
        return prefix
    }

    _BuildCardInnerXml(node, depth, flatIdx := 0, colMode := false) {
        prefix := this._BuildCardPrefixXml(node, depth, colMode)
        cardBg := this._CardBgXml(node, flatIdx)
        skipOp := this._NodeIsSkip(node) ? "0.42" : "1"
        dbgVis := CmdIsDebug(node.text) ? "Visible" : "Collapsed"
        curVis := (node.HasProp("debugCur") && node.debugCur) ? "Visible" : "Collapsed"
        brkVis := (node.HasProp("debugBp") && node.debugBp) ? "Visible" : "Collapsed"
        dispText := this._EscapeXml(CmdStripDebug(node.text))
        xml := '<Border Name="CardBd_' node.id '" Tag="' node.id '" CornerRadius="0" BorderThickness="0" Background="' cardBg '" Margin="0" Padding="2,0,6,0" HorizontalAlignment="Stretch">'
            . '<StackPanel Name="CardInner_' node.id '" Orientation="Horizontal" VerticalAlignment="Stretch" MinHeight="24" Opacity="' skipOp '">'
            . prefix
        if (node.icon != "")
            xml .= '<Image Source="' this._EscapeXml(node.icon) '" Width="16" Height="16" Margin="0,0,4,0" VerticalAlignment="Center"/>'
        else
            xml .= '<Border Width="16" Height="16" Margin="0,0,4,0"/>'
        xml .= '<Grid Name="Dbg_' node.id '" Width="14" Height="12" Margin="0,0,4,0" Visibility="' dbgVis '" VerticalAlignment="Center">'
            . CmdKeyRightIconXaml("{DynamicResource Accent}", 13, 11, "1.8")
            . '</Grid>'
        ; 当前位置标记（→）：实心三角，视觉上区别于调试起点的空心键帽；
        ; 可见性读节点字段 debugCur，保证 Render() 全量重建后仍与字段一致（解 G1）
        xml .= '<Grid Name="Cur_' node.id '" Width="10" Height="12" Margin="0,0,4,0" Visibility="' curVis '" VerticalAlignment="Center">'
            . '<Path Width="9" Height="11" Stretch="Uniform" Fill="{DynamicResource Accent}"'
            . ' Data="M 0,0 L 9,5.5 L 0,11 Z" VerticalAlignment="Center" HorizontalAlignment="Center" IsHitTestVisible="False"/>'
            . '</Grid>'
        ; 断点标记（Brk_ 独立通道）：实心小红圆，与 Dbg_（空心键帽）/ Cur_（实心三角）三通道互不干扰；
        ; 可见性读节点字段 debugBp，保证 Render() 全量重建后仍与字段一致（零文本污染）
        xml .= '<Grid Name="Brk_' node.id '" Width="10" Height="12" Margin="0,0,4,0" Visibility="' brkVis '" VerticalAlignment="Center">'
            . '<Ellipse Width="9" Height="9" Fill="#E53935" VerticalAlignment="Center" HorizontalAlignment="Center" IsHitTestVisible="False"/>'
            . '</Grid>'
        xml .= '<TextBlock Name="Txt_' node.id '" Text="' dispText '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'
        xml .= '</StackPanel></Border>'
        return xml
    }

    _BuildCardXml(node, depth, flatIdx := 0) {
        return '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
            . ' Tag="' node.id '" Background="Transparent" BorderThickness="0" Padding="0" Margin="0" HorizontalContentAlignment="Stretch">'
            . this._BuildCardInnerXml(node, depth, flatIdx, false)
            . '</ListBoxItem>'
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _IndexOf(arr, id) {
        for i, n in arr
            if (n.id == id)
                return i
        return 0
    }

    _CountChildren(node) {
        c := 1
        for child in node.children
            c += this._CountChildren(child)
        return c
    }

    ; ---------------- 增量渲染辅助 ----------------

    ; 节点是否可见（所有祖先均展开；根节点恒可见）
    _IsVisible(node) {
        p := node.parent
        while (p) {
            if (!p.expanded)
                return false
            p := p.parent
        }
        return true
    }

    ; 节点深度（根=0），决定卡片左缩进
    _Depth(node) {
        d := 0
        p := node.parent
        while (p) {
            d += 1
            p := p.parent
        }
        return d
    }

    ; 节点在扁平可见列表中的索引（与 Render 展平顺序一致），不可见/不存在返回 -1
    _FlatIndexOf(id) {
        idx := 0
        found := -1
        for node in this.roots
            this._WalkFlatIndex(node, &idx, id, &found)
        return found
    }

    _WalkFlatIndex(node, &idx, targetId, &found) {
        if (found >= 0)
            return
        if (node.id == targetId) {
            found := idx
            return
        }
        idx += 1
        if (node.expanded)
            for child in node.children
                this._WalkFlatIndex(child, &idx, targetId, &found)
    }

    ; 收集节点及其可见后代的 id（展平顺序，用于增量移除）
    _CollectVisibleIds(node, &arr) {
        arr.Push(node.id)
        if (node.expanded)
            for child in node.children
                this._CollectVisibleIds(child, &arr)
    }

    ; 更新节点展开箭头文字（叶↔父转换时增量改，不重建）
    _UpdateArrow(id) {
        if (!IsObject(this.ui) || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        hasChild := node.children.Length > 0
        glyph := hasChild ? (node.expanded ? Chr(0xE70D) : Chr(0xE76C)) : ""
        this.ui.Update("Arrow_" id "_Txt", "Text", glyph)
    }
}

; ---------------- 其它控件兼容适配器 ----------------

class MacroTextBox {
    __New(ui, name) {
        this.ui := ui
        this.name := name
        this._visible := false
    }

    Hwnd {
        get => (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    Visible {
        get => this._visible
        set {
            this._visible := value
            if (IsObject(this.ui))
                this.ui.Update(this.name, "Visibility", value ? "Visible" : "Collapsed")
        }
    }

    Value {
        get => IsObject(this.ui) ? this.ui.Query(this.name) : ""
        set {
            if (IsObject(this.ui))
                this.ui.Update(this.name, "Text", value)
        }
    }

    ScrollToEnd() {
        if (IsObject(this.ui))
            this.ui.Update(this.name, "ScrollToEnd", "")
    }
}

class MacroCombo {
    __New(ui, name) {
        this.ui := ui
        this.name := name
        this._value := 1
    }

    Value {
        get => this._value
        set {
            this._value := value
            if (IsObject(this.ui))
                this.ui.Update(this.name, "SelectedIndex", String(value - 1))
        }
    }
}

class MacroCheckBox {
    __New(ui, name) {
        this.ui := ui
        this.name := name
    }

    Value {
        get => (IsObject(this.ui) && this.ui.Query(this.name) == "True")
        set {
            if (IsObject(this.ui))
                this.ui.Update(this.name, "IsChecked", value ? "True" : "False")
        }
    }
}

class MacroButton {
    __New(ui, name) {
        this.ui := ui
        this.name := name
        this._visible := true
    }

    Visible {
        get => this._visible
        set {
            this._visible := value
            if (IsObject(this.ui))
                this.ui.Update(this.name, "Visibility", value ? "Visible" : "Collapsed")
        }
    }
}

; 菜单适配：MenuHandler 仍调用 ToolMenu.Check/Uncheck/ToggleCheck，
; 映射到 WPF MenuItem.IsChecked。IsChecked 状态在 AHK 侧维护，避免回调内 Query。
class MacroMenuAdapter {
    __New(ui) {
        this.ui := ui
        this._checked := Map()
        this._nameMap := Map(
            GetLang("变量监视"), "MenuVarListen",
            GetLang("指令显示"), "MenuCmdTip",
            GetLang("窗口置顶"), "MenuTopMost"
        )
    }

    _Name(name) => this._nameMap.Has(name) ? this._nameMap[name] : ""

    Check(name) {
        this._checked[name] := true
        if (IsObject(this.ui) && this._Name(name) != "")
            this.ui.Update(this._Name(name), "IsChecked", "True")
    }

    Uncheck(name) {
        this._checked[name] := false
        if (IsObject(this.ui) && this._Name(name) != "")
            this.ui.Update(this._Name(name), "IsChecked", "False")
    }

    ToggleCheck(name) {
        cur := this._checked.Has(name) ? this._checked[name] : false
        cur ? this.Uncheck(name) : this.Check(name)
    }
}

; 值桥接：把 XAML 控件包装成带 .Value 读写的对象，供原生 GUI（如 FrontInfoGui）读写
class XamlValueBridge {
    __New(ui, ctrlName) {
        this.ui := ui
        this.ctrlName := ctrlName
    }

    Value {
        get => IsObject(this.ui) ? this.ui.Query(this.ctrlName) : ""
        set {
            if (IsObject(this.ui))
                this.ui.Update(this.ctrlName, "Text", value)
        }
    }
}

; 兼容外部对 .Gui.Hwnd / .Gui.Title / .Gui.Hide 的调用
class MacroEditGuiFacade {
    __New(owner) {
        this._owner := owner
    }

    Hwnd {
        get => (IsObject(this._owner.ui) && this._owner.ui.HasProp("wpfHwnd")) ? this._owner.ui.wpfHwnd : 0
    }

    Title {
        get => this._owner._title
    }

    Hide() {
        this._owner._HideWindow()
    }
}
