#Requires AutoHotkey v2.0

; ============================================================================
; MacroGraphGui 职能拆分 —— 右键菜单 / 添加指令节点
;
; 画布右键菜单构建与样式、菜单项状态刷新、右键命中判定，
; 以及新增指令节点 / 拖线落空新建节点。方法体保持原样，this 仍为 MacroGraphGui 实例，
; 通过 _GraftMacroGraphMixin 嫁接到 MacroGraphGui.Prototype。
; ============================================================================

class MacroGraphMenuMixin {
    ; ----------------------------------------------------------------- 右键添加节点

    _BuildContextMenu() {
        canvas := this.graph.canvas
        ; MG_CM 挂在 0 尺寸隐藏宿主上，Placement=MousePoint（按光标点定位，能可靠弹出）。
        ; FlowDirection=LeftToRight：确保菜单/子菜单向「右」展开——若继承到 RightToLeft，
        ; MousePoint 会让菜单向光标左侧弹、子菜单也往左（正是"出现在鼠标左下、二级菜单在左"的表现）。
        cmHost := canvas.Add("Border").Name("MG_CMHost").Width("0").Height("0").Visibility("Collapsed")
        cmEl := cmHost.Add("Border.ContextMenu")
        cm := cmEl.Add("ContextMenu").Name("MG_CM").MinWidth("180").MaxHeight("600").Placement("MousePoint").FlowDirection("LeftToRight").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness(1).Foreground("{DynamicResource TextMain}")

        ; 注入局部资源：
        ;   ① 自定义 ContextMenu 模板（无阴影边框，与位置正确的 MG_DropCM 一致）——
        ;      主题默认 ContextMenu 模板含阴影 Chrome 边距，会让菜单在光标附近偏移错位；
        ;      改用此无边距模板后按光标点规整落在右下方；顺带一级菜单也能滚轮滚动。
        ;   ② MenuItem 子菜单模板（▸ 箭头 + 右向弹出 + 滚轮滚动的二级菜单）。
        cm.InjectResources(this._ContextMenuScrollStyle())
        cm.InjectResources(this._MenuItemSubmenuStyle())

        ; 1. 编辑（仅选中单个节点时可交互）
        cm.Add("MenuItem").Name("MG_Edit").Header(GetLang("编辑"))

        ; 2. 新增指令（有子菜单）
        miAdd := cm.Add("MenuItem").Name("MG_AddRoot").Header(GetLang("新增指令"))
        for i, name in this.CmdList {
            mi := miAdd.Add("MenuItem").Name("MG_Add_" i).Header(name)
            iconUri := this._IconUri(i)
            if (iconUri != "")
                mi.Add("MenuItem.Icon").Add("Image").SetProp("Source", iconUri).Width("16").Height("16")
        }

        ; 3. 复制（快捷键提示）
        cm.Add("MenuItem").Name("MG_Copy").Header(GetLang("复制")).InputGestureText("Ctrl+C")

        ; 4. 粘贴（快捷键提示）
        cm.Add("MenuItem").Name("MG_Paste").Header(GetLang("粘贴")).InputGestureText("Ctrl+V")

        ; 5. 删除（快捷键提示）
        cm.Add("MenuItem").Name("MG_Delete").Header(GetLang("删除")).InputGestureText("Delete")

        ; ---- 出点连线到空白处用的指令弹出菜单（挂在隐藏 Border 上，与右键菜单独立） ----
        dropHost := canvas.Add("Border").Name("MG_DropHost").Width("0").Height("0").Visibility("Collapsed")
        dm := dropHost.Add("Border.ContextMenu").Add("ContextMenu").Name("MG_DropCM").MinWidth("180").MaxHeight("400").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness(1).Foreground("{DynamicResource TextMain}")
        dm.InjectResources(this._ContextMenuScrollStyle())
        for i, name in this.CmdList {
            mi := dm.Add("MenuItem").Name("MG_Drop_" i).Header(name)
            iconUri := this._IconUri(i)
            if (iconUri != "")
                mi.Add("MenuItem.Icon").Add("Image").SetProp("Source", iconUri).Width("16").Height("16")
        }
    }

    ; 支持子菜单的 MenuItem 模板（含 ▸ 箭头列 + 右向弹出 Popup）。
    ; 作为 ContextMenu 局部资源注入，覆盖全局主题中可能缺失子菜单支持的旧模板。
    ; 悬停蓝色高亮 + 仅父级菜单项悬停时展开子菜单（叶子项不展空 Popup，避免右侧水平条出现）。
    _MenuItemSubmenuStyle() {
        return ''
            . '<Style TargetType="MenuItem">'
            .   '<Setter Property="Background" Value="Transparent"/>'
            .   '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            .   '<Setter Property="Padding" Value="10,8"/>'
            .   '<Setter Property="Template"><Setter.Value>'
            .     '<ControlTemplate TargetType="MenuItem">'
            .       '<Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="3">'
            .         '<Grid>'
            .           '<Grid.ColumnDefinitions>'
            .             '<ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>'
            .           '</Grid.ColumnDefinitions>'
            .           '<ContentPresenter ContentSource="Icon" Margin="0,0,8,0" VerticalAlignment="Center"/>'
            .           '<ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>'
            .           '<TextBlock Grid.Column="2" Text="{TemplateBinding InputGestureText}" Foreground="{DynamicResource TextSub}" Margin="15,0,0,0" VerticalAlignment="Center"/>'
            .           '<Path Grid.Column="3" x:Name="ArrowPath" Data="M0,0 L4,4 L0,8 Z" Fill="{DynamicResource TextMain}" Margin="8,0,2,0" VerticalAlignment="Center" Visibility="Collapsed"/>'
            .           '<Popup x:Name="PART_Popup" AllowsTransparency="True" Placement="Right" HorizontalOffset="-3" PlacementTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Focusable="False">'
            .             '<Border FlowDirection="LeftToRight" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3" Padding="4,4,0,4" MinWidth="180">'
            .               '<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False" MaxHeight="400" Margin="0" Padding="0"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" Margin="0,0,4,0"/></ScrollViewer>'
            .             '</Border>'
            .           '</Popup>'
            .         '</Grid>'
            .       '</Border>'
            .       '<ControlTemplate.Triggers>'
            .         '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger>'
            .         '<Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger>'
            .         '<Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource TextSub}"/></Trigger>'
            .         '<Trigger Property="HasItems" Value="True"><Setter TargetName="ArrowPath" Property="Visibility" Value="Visible"/></Trigger>'
            .         '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="HasItems" Value="True"/></MultiTrigger.Conditions><Setter Property="IsSubmenuOpen" Value="True"/></MultiTrigger>'
            .       '</ControlTemplate.Triggers>'
            .     '</ControlTemplate>'
            .   '</Setter.Value></Setter>'
            . '</Style>'
    }

    ; 支持滚轮滑动的 ContextMenu 模板（ItemsPresenter 包裹在 ScrollViewer 中，修复无法通过滚轮滚动内容的问题）
    _ContextMenuScrollStyle() {
        return ''
            . '<Style TargetType="ContextMenu">'
            .   '<Setter Property="Template"><Setter.Value>'
            .     '<ControlTemplate TargetType="ContextMenu">'
            .       '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="4">'
            .         '<ScrollViewer VerticalScrollBarVisibility="Auto" CanContentScroll="False">'
            .           '<ItemsPresenter/>'
            .         '</ScrollViewer>'
            .       '</Border>'
            .     '</ControlTemplate>'
            .   '</Setter.Value></Setter>'
            . '</Style>'
    }

    ; 画布右键：解析坐标/连线命中后弹出菜单
    ; （C#：右键按下准备拖动画布，松开且未移动才发 ContextMenuOpened；命中连线时附带 PathId）
    _OnGraphContextMenu(state, *) {
        if (this.ui == "" || this.graph == "")
            return
        g := this.graph
        hitPath := ""
        if (IsObject(state) && state.Has("ContextMenuOpened")) {
            parts := StrSplit(state["ContextMenuOpened"], ",")
            if (parts.Length >= 2) {
                g.lastRightClickX := Number(parts[1])
                g.lastRightClickY := Number(parts[2])
            }
            if (parts.Length >= 3 && parts[3] != "")
                hitPath := parts[3]
        }
        ; 右键连线：选中该连线，菜单仅「删除」可交互
        if (hitPath != "") {
            g.OnPathClicked(hitPath, Map(), "", "")
            this._OpenConnectionContextMenu()
            return
        }
        this._OpenContextMenu()
    }

    ; 连线右键菜单：仅删除可点
    _OpenConnectionContextMenu() {
        if (this.ui == "")
            return
        this.ui.Update("MG_Edit", "IsEnabled", "False")
        this.ui.Update("MG_Copy", "IsEnabled", "False")
        this.ui.Update("MG_Paste", "IsEnabled", "False")
        this.ui.Update("MG_Delete", "IsEnabled", "True")
        this.ui.Update("MG_AddRoot", "IsEnabled", "False")
        this.ui.Update("MG_AddRoot", "IsSubmenuOpen", "False")
        this.ui.Update("MG_CM", "IsOpen", "True")
    }

    ; 右键（未拖动画布）时触发：先刷新菜单项状态，再在鼠标位置弹出右键菜单。
    _OpenContextMenu() {
        if (this.ui == "" || this.graph == "")
            return
        ; 开始节点禁止右键菜单
        if (this._NodeIdAtRightClick() == this.startId)
            return
        this._UpdateMenuState()
        ; 用最稳的 IsOpen 打开（Placement=MousePoint，落在光标处，确保能弹出）。
        this.ui.Update("MG_CM", "IsOpen", "True")
    }

    ; 右键菜单打开前：根据当前选中状态更新菜单项的可用性
    _UpdateMenuState() {
        if (this.ui == "" || this.graph == "")
            return
        g := this.graph
        isBlank := this._IsRightClickOnBlank()
        ; 右键空白处时自动取消选中（含"选中节点后再右键空白处"场景）
        if (isBlank) {
            g.selectedNodes.Clear()
            for n in g.nodes
                g.SetNodeSelected(n.Id, false)
            for conn in g.connections {
                if (conn.Selected) {
                    conn.Selected := false
                    g.SetConnSelected(conn.PathId, false)
                }
            }
        } else {
            ; 右键命中节点：若该节点尚未在选区中，则将其设为唯一选中（标准编辑器行为），
            ; 这样"编辑/复制/删除"可直接作用于右键的节点（无需先左键选中）
            hitId := this._NodeIdAtRightClick()
            if (hitId != "" && !g.selectedNodes.Has(hitId)) {
                g.selectedNodes.Clear()
                for n in g.nodes
                    g.SetNodeSelected(n.Id, false)
                for conn in g.connections {
                    if (conn.Selected) {
                        conn.Selected := false
                        g.SetConnSelected(conn.PathId, false)
                    }
                }
                g.selectedNodes[hitId] := true
                g.SetNodeSelected(hitId, true)
            }
        }
        hasSelection := g.selectedNodes.Count > 0
        hasSingleSelection := g.selectedNodes.Count == 1
        hasConnection := false
        for conn in g.connections {
            if (conn.Selected) {
                hasConnection := true
                break
            }
        }
        hasClipboard := this.HasOwnProp("_clipboard") && this._clipboard && this._clipboard.nodes && this._clipboard.nodes.Length > 0

        ; 编辑：仅选中单个节点时可交互
        this.ui.Update("MG_Edit", "IsEnabled", hasSingleSelection ? "True" : "False")
        ; 复制：选中节点或连线时可交互
        this.ui.Update("MG_Copy", "IsEnabled", (hasSelection || hasConnection) ? "True" : "False")
        ; 粘贴：有剪贴板且未选中节点/连线时可交互
        this.ui.Update("MG_Paste", "IsEnabled", hasClipboard ? "True" : "False")
        ; 删除：选中节点或连线时可交互
        this.ui.Update("MG_Delete", "IsEnabled", (hasSelection || hasConnection) ? "True" : "False")

        ; 新增指令：仅在右键空白处时可用；右键命中节点时禁用
        this.ui.Update("MG_AddRoot", "IsEnabled", isBlank ? "True" : "False")

        ; 右键空白处或连线拖放时：自动展开"新增指令"子菜单；右键命中节点时收起
        forceOpen := this.HasOwnProp("_forceOpenSubmenu") && this._forceOpenSubmenu
        this._forceOpenSubmenu := false  ; 重置标记
        this.ui.Update("MG_AddRoot", "IsSubmenuOpen", (forceOpen || isBlank) ? "True" : "False")
    }

    ; 依据最近一次右键坐标判断是否点在空白处（未命中任何节点矩形）
    _IsRightClickOnBlank() {
        g := this.graph
        if (g == "" || !g.HasProp("lastRightClickX"))
            return true
        rx := g.lastRightClickX, ry := g.lastRightClickY
        for n in g.nodes {
            if (rx >= n.X && rx <= n.X + n.W && ry >= n.Y && ry <= n.Y + n.H)
                return false
        }
        return true
    }

    ; 返回最近一次右键坐标命中的节点 Id（命中多个时取最后一个，即最上层）；未命中返回 ""
    _NodeIdAtRightClick() {
        g := this.graph
        if (g == "" || !g.HasProp("lastRightClickX"))
            return ""
        rx := g.lastRightClickX, ry := g.lastRightClickY
        hitId := ""
        for n in g.nodes {
            if (rx >= n.X && rx <= n.X + n.W && ry >= n.Y && ry <= n.Y + n.H)
                hitId := n.Id
        }
        return hitId
    }

    OnAddCmd(cmdName, *) {
        if (this.ui == "" || !this.ui.wpfHwnd || this.graph == "")
            return
        ; 在右键位置运行时注入完整内联节点（不重建窗口，避免闪烁）；不自动连线
        this._CaptureTopLevelSuccessorLinks()
        this._SyncPositionsFromGraph()
        id := this._NewId()
        node := this._CreateDefaultCommandNode(cmdName)
        this.cmdNodes[id] := node
        ox := this.graph.HasProp("lastRightClickX") ? this.graph.lastRightClickX - this.graph.offsetX : 200
        oy := this.graph.HasProp("lastRightClickY") ? this.graph.lastRightClickY - this.graph.offsetY : 200
        this.pos[id] := { x: ox, y: oy }

        ; 取出本次（若有）的待连线源端口
        pendingFrom := (this.HasOwnProp("_pendingConnectionFrom") && this._pendingConnectionFrom != "") ? this._pendingConnectionFrom : ""
        this._pendingConnectionFrom := ""   ; 先摘掉，避免菜单 Closed 再清一次时误伤
        fromIsBranch := this._IsBranchId(pendingFrom)
        logicalFrom := this._LogicalNodeId(pendingFrom)

        ; 若从「内联展开的容器」引出新增：新节点归入同一子图（不进 this.order），
        ; 随该容器折叠/保存一并处理，避免污染顶层图或折叠残留。
        ; pendingFrom 可能是内联子，也可能是已展开的分支/循环体容器本身。
        ownerBr := ""
        if (pendingFrom != "") {
            if (this._ilOwner.Has(pendingFrom))
                ownerBr := this._ilOwner[pendingFrom]
            else if (this.HasOwnProp("_ilExpanded") && this._ilExpanded.Has(pendingFrom) && this._ilExpanded[pendingFrom])
                ownerBr := pendingFrom
        }
        if (ownerBr != "") {
            this._ilOwner[id] := ownerBr
            this._ilSerial[id] := ""
            if (this._ilSubs.Has(ownerBr))
                this._ilSubs[ownerBr].Push(id)
        } else {
            this.order.Push(id)
        }

        ; ---- 统一走运行时注入（不重建窗口，避免闪烁；亦修复添加搜索后无法继续添加节点的问题）----
        this._InjectFullNode(id, node)
        ; 搜索/如果节点：强制绑定真/假分支节点（新建默认展开）；内联子则其分支卡片也登记为内联
        if (this._HasVisibleBranches(id)) {
            if (ownerBr != "")
                this._InjectInlineSubBranches(ownerBr, id)
            else
                this._InjectBranches(id)
        }
        ; 循环节点：注入外置循环体节点 + 回环路径（新建默认展开）；内联子则登记为内联
        if (this._IsExpandedLoop(id)) {
            if (ownerBr != "")
                this._InjectInlineSubLoopBody(ownerBr, id)
            else
                this._InjectLoopBodyNode(id)
        }
        ; 由出点拖拽触发的添加：自动连线（展开态主节点仍直连后续；分支无出点）
        if (pendingFrom != "" && pendingFrom != id) {
            srcOk := fromIsBranch ? this._branchInjected.Has(logicalFrom) : this._NodeExists(pendingFrom)
            if (srcOk) {
                this._ActivateConnection(pendingFrom, id)
                this._RedirectBranchSuccessorLinks()
                ; 内联子图里从展开的如果/搜索引出新节点时，按展开间距推开后继
                if (ownerBr != "" && logicalFrom != "" && logicalFrom != id)
                    this._EnsureExpandGap(logicalFrom)
            }
            ; 正式连线已指向新节点后再收起临时连线，避免中间闪断
            this._HideTempDropConnection()
        }
        this._ThickenConnections()
        this._RebindPathClicks()
        this._SaveGraphAndNotifyParent()
    }
}

_GraftMacroGraphMixin(MacroGraphMenuMixin)
