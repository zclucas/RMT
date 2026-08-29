#Requires AutoHotkey v2.0

; ============================================================================
; MacroGraphGui 职能拆分 —— 运行时节点注入 / 连线管理
;
; 完整节点 / 摘要节点的运行时注入、画布坐标同步，以及连线捕获 / 启停 / 归一 /
; 重绑 / 加粗等连线管理。方法体保持原样，this 仍为 MacroGraphGui 实例，
; 通过 _GraftMacroGraphMixin 嫁接到 MacroGraphGui.Prototype。
; ============================================================================

class MacroGraphConnectionsMixin {
    ; 运行时注入一个完整可内联编辑的节点（不重建窗口）：
    ;   片段 XAML → AddXamlItem；登记 g.nodes；补绑引擎拖动/选中事件 + 本类事件；启用拖动。
    _InjectFullNode(id, node) {
        g := this.graph
        this._HookGraphIfProPaths()
        this._NodeFragments(id, node, &nodeXaml, &portInXaml, &portOutXaml)
        g.ui.Update(g.id, "AddXamlItem", nodeXaml)
        ; 端口已嵌入 nodeXaml 中，无需单独注入

        p := this.pos[id]
        x := p.x + g.offsetX
        y := p.y + g.offsetY
        dInj := this._Parse(node.CurCMD)
        nodeType := dInj.type
        nodeTitle := this._NodeTitleText(dInj)
        nodeW := (nodeType == GetLang("搜索Pro")) ? 380 : (this._IsFormalNodeType(nodeType) ? this._FormalNodeWidth(nodeType) : 200)
        g.nodes.Push({ Id: id, Title: nodeTitle, X: x, Y: y, W: nodeW, H: 60, Type: "Process" })

        ; 引擎拖动/选中处理（移动端口与连线、整体拖拽、高亮）
        g.ui.OnEvent("Node_" id, "DragMove", ObjBindMethod(g, "OnNodeMoved", id))
        g.ui.OnEvent("Node_" id, "SelectNode", ObjBindMethod(g, "OnSelectNode", id))
        g.ui.OnEvent("Node_" id, "CtrlSelectNode", ObjBindMethod(g, "OnCtrlSelectNode", id))
        ; 本类事件（双击编辑 + 内联字段），runtime=true 同步向引擎补绑事件与采集
        this._RegisterMyNodeEvents(id, node, true)
        ; 启用该节点拖动（稍后，待元素就绪）
        SetTimer(() => g.ui.Update("Node_" id, "EnableDrag", "grid=20"), -150)
    }

    ; 从引擎节点(g.nodes，含框选整体拖拽后更新的坐标)同步回 this.pos（逻辑坐标，去画布偏移）
    _SyncPositionsFromGraph() {
        if (this.graph == "")
            return
        ox := this.graph.offsetX, oy := this.graph.offsetY
        for n in this.graph.nodes {
            if (this.pos.Has(n.Id))
                this.pos[n.Id] := { x: n.X - ox, y: n.Y - oy }
        }
    }

    ; 运行时注入一个简要节点（标题 + 摘要 + 提示），双击可进完整编辑器
    _InjectSummaryNode(id, node) {
        g := this.graph
        p := this.pos[id]
        x := p.x + g.offsetX
        y := p.y + g.offsetY
        d := this._Parse(node.CurCMD)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        title := this._XmlEsc(this._NodeTitleText(d))
        detail := this._XmlEsc(this._Summary(d))
        tip := this._XmlEsc(GetLang("双击编辑"))

        nodeXaml := '<Border ' ns ' x:Name="Node_' id '" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3" Width="200" Padding="0" Margin="0" ClipToBounds="False" Canvas.Left="' x '" Canvas.Top="' y '"><Grid><Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Border x:Name="NodeShadow_' id '" Grid.Row="0" Grid.RowSpan="2" Background="{DynamicResource DropdownBg}" CornerRadius="6" IsHitTestVisible="False" Panel.ZIndex="-1"><Border.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="2" Opacity="0.4" Direction="270" Color="Black"/></Border.Effect></Border><Border x:Name="NodeSel_' id '" Grid.Row="0" Grid.RowSpan="2" Margin="-3" BorderThickness="3" BorderBrush="{DynamicResource GraphConnSel}" Background="Transparent" CornerRadius="8" Visibility="Collapsed" IsHitTestVisible="False" Panel.ZIndex="0"/><Border Grid.Row="0" Background="{DynamicResource TitleBarColor}" CornerRadius="3,3,0,0" Cursor="SizeAll"><TextBlock Text="' title '" Foreground="{DynamicResource TitleBarForeground}" FontWeight="Bold" FontSize="' this._MGFontSize(12) '" VerticalAlignment="Center" Margin="10,0"/></Border><StackPanel Grid.Row="1" Margin="10,0,0,8"><TextBlock Text="' detail '" Foreground="{DynamicResource TextMain}" FontSize="' this._MGFontSize(12) '" TextWrapping="Wrap"/><TextBlock Text="' tip '" Foreground="#888888" FontSize="' this._MGFontSize(10) '" Margin="0,4,0,0"/></StackPanel></Grid>'
        ; 端口放在内容行(Row1)顶部，向上伸出标题栏下方
        ; 入点：左边距-15（左移），上边距-5（上伸到标题栏下方），出点：右边距-15（右移）
        portIn := '<Ellipse ' ns ' x:Name="Port_In_' id '" Width="14" Height="14" Fill="#4CAF50" Stroke="#333" StrokeThickness="1" Grid.Row="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="-7,-7,0,0" Panel.ZIndex="10" IsHitTestVisible="True" Cursor="Hand"/>'
        portOut := '<Ellipse ' ns ' x:Name="Port_Out_' id '" Width="14" Height="14" Fill="#FF5722" Stroke="#333" StrokeThickness="1" Grid.Row="1" VerticalAlignment="Top" HorizontalAlignment="Right" Margin="0,-7,-7,0" Panel.ZIndex="10" IsHitTestVisible="True" Cursor="Hand"/>'
        nodeXaml := StrReplace(nodeXaml, "</Grid>", portIn portOut "</Grid>")
        g.ui.Update(g.id, "AddXamlItem", nodeXaml)

        g.nodes.Push({ Id: id, Title: this._NodeTitleText(d), X: x, Y: y, W: 200, H: 60, Type: "Process" })

        ; XNodeGraph 的拖动/选中处理（移动端口与连线、高亮）
        g.ui.OnEvent("Node_" id, "DragMove", ObjBindMethod(g, "OnNodeMoved", id))
        g.ui.OnEvent("Node_" id, "SelectNode", ObjBindMethod(g, "OnSelectNode", id))
        g.ui.OnEvent("Node_" id, "CtrlSelectNode", ObjBindMethod(g, "OnCtrlSelectNode", id))
        ; 本类的位置记录与双击编辑
        g.ui.OnEvent("Node_" id, "DragMove", this._OnNodeDrag.Bind(this, id))
        g.ui.OnEvent("Node_" id, "SelectNode", this._OnNodeClick.Bind(this, id))
        g.ui.OnEvent("Node_" id, "CtrlSelectNode", this._OnNodeClick.Bind(this, id))
        SetTimer(() => g.ui.Update("Node_" id, "EnableDrag", "grid=20"), -150)
    }

    _Summary(d) {
        if (d.type == GetLang("间隔")) {
            if (d.itype == GetLang("随机"))
                return d.time "~" d.time2 " ms"
            return d.time " ms"
        }
        if (d.type == GetLang("按键")) {
            s := d.key " " d.ktype
            if (d.ktype == GetLang("点击") && d.count != "1" && d.count != 1)
                s .= "  x" d.count
            return s
        }
        if (IsMoveCmd(d.type))
            return "(" d.posx ", " d.posy ")  " GetLang("移动速度：") d.speed
        if (IsDeltaMoveCmd(d.type))
            return GetLang("增量移动") "  (" d.posx ", " d.posy ")"
        if (d.type == GetLang("搜索") || d.type == GetLang("搜索Pro")) {
            typeNames := [GetLang("屏幕图片"), GetLang("屏幕颜色"), GetLang("屏幕文本"), GetLang("窗口图片"), GetLang("窗口颜色"), GetLang("窗口文本")]
            st := (d.HasOwnProp("searchType") && d.searchType >= 1 && d.searchType <= 6) ? d.searchType : 1
            typeStr := typeNames[st]
            cls := this._SearchTypeClass(st)
            if (cls.isColor)
                return typeStr "  #" d.searchColor
            if (cls.isText) {
                q := Chr(34)
                return typeStr "  " q d.searchText q
            }
            imgName := d.HasOwnProp("searchImagePath") ? RegExReplace(d.searchImagePath, ".*\\", "") : GetLang("未设置")
            return typeStr "  " imgName
        }
        if (d.type == GetLang("输入")) {
            typeStr := d.HasOwnProp("inputType") ? GetLang(d.inputType) : GetLang("弹窗")
            if (d.HasOwnProp("saveName") && d.saveName != "" && (d.inputType == "弹窗" || d.inputType == "状态"))
                return typeStr "  → " GetLang(d.saveName)
            return typeStr
        }
        if (d.type == GetLang("输出")) {
            typeStr := d.HasOwnProp("outputType") ? GetLang(d.outputType) : GetLang("发送内容")
            if (d.HasOwnProp("outputType") && d.outputType == "字符变量" && d.HasOwnProp("variableName") && d.variableName != "")
                return typeStr "  → " GetLang(d.variableName)
            txt := d.HasOwnProp("text") ? GetLangStr(d.text, 1) : ""
            if (StrLen(txt) > 24)
                txt := SubStr(txt, 1, 24) "..."
            return typeStr (txt != "" ? "  " txt : "")
        }
        if (this._IsFormalNodeType(d.type))
            return this._FormalSummary(d)
        return d.raw
    }

    _XmlEsc(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ; 把当前画布连线快照到 this.links（供重建时还原）
    _CaptureLinks() {
        if (this.graph == "")
            return
        newLinks := []
        seen := Map()
        for conn in this.graph.connections {
            ; 跳过已停用（折叠隐藏）的连线，它们在画面上不可见、逻辑上也不是当前后继
            if (conn.HasOwnProp("Active") && !conn.Active)
                continue
            from := conn.From
            to := conn.To
            ; 内联展开的分支子节点：仅是分支子图的编辑视图，不属于顶层图，相关连线一律丢弃
            if (this._IsInlineSub(from) || this._IsInlineSub(to))
                continue
            ; 循环回环连线（循环↔外置循环体）：纯显示用，不是逻辑后继，直接丢弃不入 links
            if (this._IsLoopBodyId(from) || this._IsLoopBodyId(to))
                continue
            ; 「分支 → X」翻译回「搜索 → X」（分支出点即搜索的后继出点）
            bi := this._BranchInfo(from)
            if (bi != "")
                from := bi.searchId
            ; 「如果Pro 分支 → X」翻译回「如果Pro → X」
            pi := this._ProBranchInfo(from)
            if (pi != "")
                from := pi.parentId
            ; 「X → 分支」翻译为「X → 分支所属搜索节点」（逻辑上汇入该搜索节点）
            bt := this._BranchInfo(to)
            if (bt != "")
                to := bt.searchId
            ; 「X → 如果Pro 分支」翻译为「X → 如果Pro 父节点」
            pt := this._ProBranchInfo(to)
            if (pt != "")
                to := pt.parentId
            ; 丢弃「搜索 → 分支节点」的强制连线（显示用，逻辑上不是真正后继）
            if (this._IsBranchId(conn.To) || this._IsProBranchId(conn.To) || from == to)
                continue
            k := from "|" to
            if (seen.Has(k))
                continue
            seen[k] := true
            newLinks.Push({ from: from, to: to })
        }
        this.links := newLinks
    }

    ; 用户新建连线后：清理旧「分支→后续」模型残留，再加粗并补绑点击
    _OnConnectionsChanged() {
        this._NormalizeBranchConnections()
        this._ThickenConnections()
        this._RebindPathClicks()
    }

    ; 连线纠正（新模型：展开时主节点仍连后续；分支仅入点、无出线）：
    ; 旧图/残留的「分支→X / 情况分支→X」译回「父→X」并停用分支出线。
    _NormalizeBranchConnections() {
        g := this.graph
        if (g == "")
            return
        toDeactivate := []
        toActivate := []
        for conn in g.connections {
            if (conn.HasOwnProp("Active") && !conn.Active)
                continue
            ; 内联子图连线保持原样
            if (this._IsInlineSub(conn.From) || this._IsInlineSub(conn.To))
                continue
            ; 残留：真假分支 → 后续 → 改为主节点 → 后续
            bi := this._BranchInfo(conn.From)
            if (bi != "" && bi.proIdx < 0 && !this._IsBranchId(conn.To) && !this._IsProBranchId(conn.To)) {
                toDeactivate.Push(conn)
                toActivate.Push({ from: bi.searchId, to: conn.To })
                continue
            }
            ; 残留：如果Pro 情况分支 → 后续 → 改为如果Pro → 后续
            pi := this._ProBranchInfo(conn.From)
            if (pi != "" && !this._IsProBranchId(conn.To) && !this._IsBranchId(conn.To)) {
                toDeactivate.Push(conn)
                toActivate.Push({ from: pi.parentId, to: conn.To })
            }
        }
        for conn in toDeactivate
            this._DeactivateConnection(conn)
        for a in toActivate
            this._ActivateConnection(a.from, a.to)
    }

    ; 激活（新建或重新显示）一条连线，并标记为有效后继
    _ActivateConnection(from, to) {
        g := this.graph
        if (g == "")
            return
        g.AddConnection(from, to)   ; 不存在则新建；已存在则重新置为可见并刷新路径
        pathId := g.id "_Path_" from "_" to
        for conn in g.connections {
            if (conn.PathId == pathId) {
                conn.Active := true
                break
            }
        }
        this.ui.Update(pathId, "StrokeThickness", "4")
        this.ui.OnEvent(pathId, "MouseLeftButtonDown", ObjBindMethod(g, "OnPathClicked", pathId))
    }

    ; 停用一条连线：仅隐藏路径并标记失效（不从画布移除，避免桥接器 NameScope 残留导致重建冲突）
    _DeactivateConnection(conn) {
        conn.Active := false
        if (this.graph != "")
            this.graph.SetConnVisible(conn.PathId, "Collapsed")
        else
            this.ui.Update(conn.PathId, "Visibility", "Collapsed")
    }

    ; 重新绑定所有连线的点击事件（连线集合变动后调用）
    _RebindPathClicks() {
        if (this.graph == "")
            return
        for conn in this.graph.connections
            this.ui.OnEvent(conn.PathId, "MouseLeftButtonDown", ObjBindMethod(this.graph, "OnPathClicked", conn.PathId))
    }

    ; 判断某连线是否牵涉到指定搜索节点的真/假分支（强制连线或分支出线）
    _ConnInvolvesSearchBranch(conn, searchId) {
        bf := this._BranchInfo(conn.From)
        bt := this._BranchInfo(conn.To)
        if (bf != "" && bf.searchId == searchId)
            return true
        if (bt != "" && bt.searchId == searchId)
            return true
        return false
    }

    ; -----------------------------------------------------------------
    ; 出点拖线 → 空白松手 → 指令菜单（与引擎 ConnDrag 状态机配套，入口集中于此）
    ; -----------------------------------------------------------------

    ; 引擎 ConnectionDropped：记录待连源与落点，延迟弹出指令菜单
    _OnConnectionDropped(state, *) {
        if (!state.Has("ConnectionDropped"))
            return
        parts := StrSplit(state["ConnectionDropped"], ",")
        if (parts.Length < 3)
            return
        this._ConnDropArm(RegExReplace(parts[1], "^Port_(Out|In)2?_", ""), Number(parts[2]), Number(parts[3]))
        ; 引擎已用 Dispatcher.Background 投递本事件；再短延时避开 ContextMenu 与 MouseUp 竞争
        SetTimer(() => this._ConnDropShowMenu(), -80)
    }

    ; 武装待连状态（OnAddCmd / 菜单关闭共用）
    _ConnDropArm(fromId, x, y) {
        this._pendingConnectionFrom := fromId
        if (this.graph != "") {
            this.graph.lastRightClickX := x
            this.graph.lastRightClickY := y
        }
    }

    ; 取消待连 + 收起引擎临时线（唯一清理入口）
    _ConnDropCancel() {
        this._pendingConnectionFrom := ""
        this._HideTempDropConnection()
    }

    ; 隐藏出点拖线留下的临时连线/箭头
    _HideTempDropConnection() {
        if (this.ui == "")
            return
        try this.ui.Update("Window", "HideTempConnection", "1")
    }

    ; 弹出拖线指令菜单（Closed 只绑一次）
    _ConnDropShowMenu() {
        if (this.ui == "")
            return
        ; 待连已被取消（例如期间点了节点）则不再弹
        if (!this.HasOwnProp("_pendingConnectionFrom") || this._pendingConnectionFrom == "")
            return
        if (!this.HasOwnProp("_dropMenuClosedBound") || !this._dropMenuClosedBound) {
            this.ui.OnEvent("MG_DropCM", "Closed", (*) => this._OnDropMenuClosed())
            this._dropMenuClosedBound := true
        }
        ; 若菜单已开：先抑制引擎 Closed 清线，关后再开
        try this.ui.Update("Window", "SuppressTempClear", "1")
        this._dropMenuSuppressClosed := true
        try this.ui.Update("MG_DropCM", "IsOpen", "False")
        this._dropMenuSuppressClosed := false
        this.ui.Update("MG_DropCM", "IsOpen", "True")
        try this.ui.Update("Window", "SuppressTempClear", "0")
    }

    ; 兼容旧名
    _OpenDropMenu() {
        this._ConnDropShowMenu()
    }

    ; 菜单关闭（点空白取消）：清待连；选指令后 OnAddCmd 也会清
    _OnDropMenuClosed(*) {
        if (this.HasOwnProp("_dropMenuSuppressClosed") && this._dropMenuSuppressClosed)
            return
        this._ConnDropCancel()
    }

    ; 把所有连线加粗，增大命中区域以便单击选中
    _ThickenConnections() {
        if (this.graph == "" || this.ui == "")
            return
        for conn in this.graph.connections
            this.ui.Update(conn.PathId, "StrokeThickness", "4")
    }
}

_GraftMacroGraphMixin(MacroGraphConnectionsMixin)
