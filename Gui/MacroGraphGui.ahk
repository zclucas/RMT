#Requires AutoHotkey v2.0

; ============================================================================
; MacroGraphGui —— 蓝图式（节点化）宏指令编辑器
;
; 说明：节点数据对象 MacroGraphNode 已在 Main\DataClass.Ahk 中定义
;       （字段 SerialStr / CurCMD / NextNodeArr）。本编辑器中每个节点仅持有
;       完整指令字符串 CurCMD，其余信息（类型/时间/按键/点击时长…）全部通过
;       解析 CurCMD 实时获得（见 _Parse）。
;
; 交互：
;   - 表格行"编辑"按钮右键进入（左键仍为旧的顺序编辑器）。
;   - 右上角"保存"按钮：保存并关闭界面。
;   - 画布空白处右键：弹出若梦兔全部指令菜单，点击生成对应节点。
;       · 间隔 / 按键：生成可内联编辑的完整节点。
;       · 其它指令：先生成临时节点（占位，后续完善）。
;   - 节点参数可直接在节点面板上内联编辑：
;       · 间隔节点：直接编辑时间(ms)
;       · 按键节点：下拉选择按键类型；类型为"点击"时显示点击时长/点击次数；
;                   点击次数>1 时再显示每次间隔。
;   - 双击间隔/按键节点：打开对应完整编辑器（IntervalGui / KeyGui）。
;   - 关闭窗口或任何内联修改时，按连线顺序重建宏并实时回写。
;
; 架构：维护数据模型 cmdNodes(数据) + order(存在列表) + pos(各节点位置) + links(连线)。
;       新增节点时重建窗口(_Render)，但保留各节点位置与连线、窗口始终最大化，
;       从而避免窗口大小被重置；新节点放在右键位置且不自动连线。
; ============================================================================

class MacroGraphGui {
    __New() {
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.ui := ""
        this.graph := ""
        this.cmdNodes := Map()        ; nodeId -> MacroGraphNode 实例（仅持有 CurCMD）
        this.order := []              ; 指令节点 id 列表（存在性，不决定连线）
        this.pos := Map()             ; nodeId(含Start) -> { x, y } 逻辑坐标(不含画布偏移)
        this.links := []              ; 连线 [{ from, to }]，跨重建保留
        this.seq := 0
        this.startId := "Start"
        this._readyTimer := this._EnableWhenReady.Bind(this)
        this._lastClickId := ""
        this._lastClickTime := 0
        this._oldUi := ""             ; 双缓冲：重建时暂存旧窗口，待新窗口就绪后再关闭
        this.injected := Map()        ; 运行时注入(简要)的节点 id；这类节点编辑后需重建为完整内联节点
        this.startSerial := ""        ; 本图开始节点(MacroGraphStartNode)的 SerialStr；保存后回写 MacroArr 即此值
        this._sessionId := 0          ; 每次打开自增；用于忽略旧窗口迟到的异步关闭事件，避免覆盖写空

        ; 若梦兔全部指令
        this.CmdList := GetLangArr(["间隔", "按键", "搜索", "搜索Pro", "移动", "移动Pro", "输入", "输出", "循环", "宏操作",
            "变量", "变量提取", "如果", "如果Pro", "运算", "运行", "文件读写", "文本处理", "数组", "RMT指令", "后台鼠标",
            "后台按键", "窗口管理", "按键检测"])

        ; 各指令对应图标（顺序与 CmdList 一一对应，复用 MacroEditGui 的图标资源）
        this.CmdIconArr := ["Images\Soft\Interval.png", "Images\Soft\Key.png",
            "Images\Soft\Search.png", "Images\Soft\SearchPro.png",
            "Images\Soft\Move.png", "Images\Soft\MovePro.png",
            "Images\Soft\Input.png", "Images\Soft\Output.png",
            "Images\Soft\Loop.png", "Images\Soft\Sub.png",
            "Images\Soft\Var.png", "Images\Soft\Extract.png",
            "Images\Soft\If.png", "Images\Soft\IfPro.png",
            "Images\Soft\Operation.png", "Images\Soft\Run.png",
            "Images\Soft\FileIO.png", "Images\Soft\TextOps.png",
            "Images\Soft\Arr.png", "Images\Soft\rabit.png",
            "Images\Soft\Mouse.png", "Images\Soft\Key.png",
            "Images\Soft\WindowManage.png", "Images\Soft\KeyCheck.png"]

        ; 复用现有子编辑器（双击节点时打开）
        this.IntervalGui := IntervalGui()
        this.KeyGui := KeyGui()
        this.MouseGui := MouseMoveGui()
    }

    ; 指令图标的绝对路径（正斜杠，供 WPF Image.Source 使用）；不存在则返回空
    _IconUri(idx) {
        if (idx < 1 || idx > this.CmdIconArr.Length)
            return ""
        full := A_WorkingDir "\" this.CmdIconArr[idx]
        if (!FileExist(full))
            return ""
        return StrReplace(full, "\", "/")
    }

    ; ----------------------------------------------------------------- 入口

    ShowGui(macroStr, key := "") {
        this._sessionId += 1
        this._CloseUI()
        this.startSerial := ""
        this.cmdNodes := Map()
        this.order := []
        this.pos := Map()
        this.links := []
        this.seq := 0

        ; 优先从已保存的图结构复原：macroStr 此时即开始节点(MacroGraphStartNode)的 SerialStr。
        ; 复原成功直接显示；否则按线性宏铺开（首次打开或旧的线性宏）。
        if (this._LoadGraph(macroStr)) {
            this._Render()
            return
        }

        ; 线性铺开（首次/旧数据）：开始节点 + 各指令节点依次串联，无结束节点
        this.startSerial := GetCMDSerialStr("图形开始节点")
        baseY := 220, step := 240, x := 60
        this.pos[this.startId] := { x: x, y: baseY }
        prevId := this.startId
        x += step
        for cmd in SplitMacro(macroStr) {
            id := this._NewId()
            this.cmdNodes[id] := this._MakeNode(cmd)
            this.order.Push(id)
            this.pos[id] := { x: x, y: baseY }
            this.links.Push({ from: prevId, to: id })
            prevId := id
            x += step
        }
        this._Render()
    }

    ; 根据数据模型构建并显示窗口（始终最大化；节点用保存的坐标，连线用 links）
    _Render() {
        ; 双缓冲：先创建并显示新窗口，待其就绪后再关闭旧窗口，避免新增节点时窗口闪缩
        oldUi := this.ui
        this.graph := ""
        this.injected := Map()        ; 重建后所有节点均为完整内联节点

        win := XAML_Generator("Window")
        win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
        win.Title(GetLang("节点编辑器")).Width(1100).Height(700).WindowStartupLocation("CenterScreen").WindowState("Maximized").Background("#1E1E1E")
        iconPath := StrReplace(A_WorkingDir "\Images\Soft\rabit.ico", "\", "/")
        if (FileExist(iconPath))
            win.Icon(iconPath)

        root := win.Add("Grid")
        this.graph := root.NodeGraph("RMTGraph")

        ; 右上角保存按钮（覆盖在画布之上）
        root.Add("Button").Name("MG_BtnSave").Content(GetLang("保存")).HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,12,16,0").Width("90").Height("32").Background("#2E6E3E").Foreground("White").BorderThickness("0").FontSize("13").Cursor("Hand")

        ; 节点（使用各自保存的坐标）
        this._BuildBaseNode(this.startId, GetLang("开始"), "Input")
        for id in this.order
            this._BuildCmdNode(id, this.cmdNodes[id])

        ; 连线（来自 links，跨重建保留）
        for link in this.links {
            if (this._NodeExists(link.from) && this._NodeExists(link.to))
                this.graph.AddConnection(link.from, link.to)
        }

        ; 右键菜单（_BuildContextMenu 内部会把 ContextMenu 属性元素移到画布子元素最前，
        ; 保证属性元素先于内容，避免 WPF 报 Canvas Children 重复设置）
        this._BuildContextMenu()

        ; ---- 宿主 ----
        ownerHwnd := this.OwnerHwnd != "" ? this.OwnerHwnd : 0
        this.ui := XAMLHost(win.ToString(), "", ownerHwnd)
        this.graph.Bind(this.ui)
        this._RegisterNodeEvents()
        ; 为所有连线补绑点击事件（XNodeGraph 仅给运行时新增连线绑定，构建期连线需手动补）
        for conn in this.graph.connections
            this.ui.OnEvent(conn.PathId, "MouseLeftButtonDown", ObjBindMethod(this.graph, "OnPathClicked", conn.PathId))
        ; 用户新建连线后，对新连线加粗并补绑点击（便于单击选中）
        this.ui.OnEvent(this.graph.id, "ConnectPorts", (*) => this._OnConnectionsChanged())
        ; Start 跟踪拖动位置
        this.ui.OnEvent("Node_" this.startId, "DragMove", this._OnNodeDrag.Bind(this, this.startId))
        for i, name in this.CmdList
            this.ui.OnEvent("MG_Add_" i, "Click", this.OnAddCmd.Bind(this, name))
        this.ui.OnEvent("MG_BtnSave", "Click", (*) => this._OnSave())
        this.ui.OnEvent("Window", "KeyDown", this._OnKeyDown.Bind(this))
        sid := this._sessionId
        this.ui.OnEvent("Window", "Closed", (*) => this.OnWindowClosed(sid))

        this.ui.Show()
        this._oldUi := oldUi
        SetTimer(this._readyTimer, 50)
    }

    _NodeExists(id) {
        return id == this.startId || this.cmdNodes.Has(id)
    }

    _EnableWhenReady() {
        if (this.ui == "" || !this.ui.wpfHwnd)
            return
        SetTimer(this._readyTimer, 0)
        this.graph.EnableDrag(this.ui, true)
        this._ThickenConnections()    ; 加粗连线，增大命中区域便于单击选中
        ; 启用画布"框选"模式：左键在空白处拖拽即可框选多个节点（C# 引擎已实现，默认 Pan 不生效）
        this.ui.Update(this.graph.id, "SetCanvasMode", "Select")
        ; 将窗口激活置前（避免显示在主界面下方）
        try {
            WinShow("ahk_id " this.ui.wpfHwnd)
            WinActivate("ahk_id " this.ui.wpfHwnd)
        }
        ; 新窗口就绪后再关闭旧窗口（双缓冲，消除闪缩）
        if (this._oldUi != "") {
            try this._oldUi.Update("Window", "Close", "")
            try this._oldUi.Dispose()
            this._oldUi := ""
        }
    }

    ; 保存并关闭：先持久化图结构，再回写线性宏（从第一个节点开始）
    _OnSave() {
        this._SaveGraph()
        this._Apply()
        if (this.ui != "")
            this.ui.Update("Window", "Close", "")
    }

    OnWindowClosed(sid := -1, *) {
        ; 仅处理当前会话窗口的关闭；旧窗口迟到的异步关闭事件直接忽略，避免覆盖写空
        if (sid != this._sessionId)
            return
        SetTimer(this._readyTimer, 0)
        this._SaveGraph()
        this._Apply()
        this.ui := ""
        this.graph := ""
    }

    _CloseUI() {
        SetTimer(this._readyTimer, 0)
        if (this._oldUi != "") {
            try this._oldUi.Dispose()
            this._oldUi := ""
        }
        if (this.ui != "") {
            try this.ui.Update("Window", "Close", "")
            try this.ui.Dispose()
            this.ui := ""
        }
        this.graph := ""
    }

    ; ----------------------------------------------------------------- 节点事件注册

    _RegisterNodeEvents() {
        for id, node in this.cmdNodes
            this._RegisterMyNodeEvents(id, node, false)
    }

    ; 注册单个节点的"本类"事件（双击编辑 + 内联字段）。runtime=true 时同时向引擎补绑/补采集
    ; （运行时注入的控件不在启动期的事件/采集清单里，需用 BindEvent/Track 命令动态补上）。
    _RegisterMyNodeEvents(id, node, runtime := false) {
        ; 双击节点打开完整编辑器（节点是 Border，无原生双击，用 SelectNode 计时判定）
        ; SelectNode/CtrlSelectNode/DragMove 由引擎 EnableDrag 主动下发，仅需本地 OnEvent 接收
        this.ui.OnEvent("Node_" id, "SelectNode", this._OnNodeClick.Bind(this, id))
        this.ui.OnEvent("Node_" id, "CtrlSelectNode", this._OnNodeClick.Bind(this, id))
        this.ui.OnEvent("Node_" id, "DragMove", this._OnNodeDrag.Bind(this, id))

        d := this._Parse(node.CurCMD)
        if (d.type == GetLang("间隔")) {
            this._TrackCtrl("ITypeCmb_" id, runtime)
            this._TrackCtrl("Time_" id, runtime)
            this._TrackCtrl("Time2_" id, runtime)
            this._BindCtrl("ITypeCmb_" id, "SelectionChanged", this._OnIntervalType.Bind(this, id), runtime)
            this._BindCtrl("Time_" id, "LostFocus", this._OnField.Bind(this, id, "time"), runtime)
            this._BindCtrl("Time2_" id, "LostFocus", this._OnField.Bind(this, id, "time2"), runtime)
        }
        else if (d.type == GetLang("按键")) {
            this._TrackCtrl("TypeCmb_" id, runtime)
            this._TrackCtrl("Hold_" id, runtime)
            this._TrackCtrl("Count_" id, runtime)
            this._TrackCtrl("Inter_" id, runtime)
            this._BindCtrl("TypeCmb_" id, "SelectionChanged", this._OnKeyType.Bind(this, id), runtime)
            this._BindCtrl("Hold_" id, "LostFocus", this._OnField.Bind(this, id, "hold"), runtime)
            this._BindCtrl("Count_" id, "LostFocus", this._OnField.Bind(this, id, "count"), runtime)
            this._BindCtrl("Inter_" id, "LostFocus", this._OnField.Bind(this, id, "inter"), runtime)
        }
        else if (d.type == GetLang("移动")) {
            this._TrackCtrl("PosX_" id, runtime)
            this._TrackCtrl("PosY_" id, runtime)
            this._TrackCtrl("Speed_" id, runtime)
            this._TrackCtrl("ModeCmb_" id, runtime)
            this._BindCtrl("PosX_" id, "LostFocus", this._OnField.Bind(this, id, "posx"), runtime)
            this._BindCtrl("PosY_" id, "LostFocus", this._OnField.Bind(this, id, "posy"), runtime)
            this._BindCtrl("Speed_" id, "LostFocus", this._OnField.Bind(this, id, "speed"), runtime)
            this._BindCtrl("ModeCmb_" id, "SelectionChanged", this._OnMoveMode.Bind(this, id), runtime)
        }
    }

    ; 采集控件值：本地登记（启动期清单用）；运行时再用 Track 命令通知引擎纳入状态采集
    _TrackCtrl(name, runtime) {
        this.ui.Track(name)
        if (runtime)
            this.ui.Update(name, "Track", "")
    }

    ; 绑定控件事件：本地登记回调；运行时再用 BindEvent 命令让引擎为该控件挂上真实 WPF 事件
    _BindCtrl(name, evt, cb, runtime) {
        this.ui.OnEvent(name, evt, cb)
        if (runtime)
            this.ui.Update(name, "BindEvent", evt)
    }

    ; 拖动节点时记录其逻辑坐标（DragCoords 为画布坐标，需减去画布偏移）
    _OnNodeDrag(id, state, *) {
        if (!state.Has("DragCoords") || !this.pos.Has(id) || this.graph == "")
            return
        parts := StrSplit(state["DragCoords"], ",")
        if (parts.Length >= 2) {
            this.pos[id].x := Number(parts[1]) - this.graph.offsetX
            this.pos[id].y := Number(parts[2]) - this.graph.offsetY
        }
    }

    ; 窗口按键：选中节点/连线后按 Delete 删除（事件名形如 KeyDown:Delete，第三参为 {Key}）
    _OnKeyDown(state, ctrl, info) {
        key := (IsObject(info) && info.HasProp("Key")) ? info.Key : ""
        if (key == "Delete" || key == "Back")
            this._DeleteSelected()
    }

    ; 删除当前选中的节点与连线（就地隐藏，不重建窗口）
    _DeleteSelected() {
        if (this.graph == "")
            return
        this.graph.DeleteSelectedConnections()
        this._DeleteSelectedNodes()
        this._CaptureLinks()
        this._Apply()
    }

    _DeleteSelectedNodes() {
        g := this.graph
        ids := []
        for id in g.selectedNodes
            ids.Push(id)
        for id in ids {
            if (id == this.startId || !this.cmdNodes.Has(id))
                continue
            g.ui.Update("Node_" id, "Visibility", "Collapsed")
            g.ui.Update("Port_In_" id, "Visibility", "Collapsed")
            g.ui.Update("Port_Out_" id, "Visibility", "Collapsed")
            ; 删除并隐藏相关连线
            keep := []
            for conn in g.connections {
                if (conn.From == id || conn.To == id)
                    g.ui.Update(conn.PathId, "Visibility", "Collapsed")
                else
                    keep.Push(conn)
            }
            g.connections := keep
            ; 从节点表移除
            nkeep := []
            for n in g.nodes {
                if (n.Id != id)
                    nkeep.Push(n)
            }
            g.nodes := nkeep
            this.cmdNodes.Delete(id)
            this._RemoveFromOrder(id)
            if (this.pos.Has(id))
                this.pos.Delete(id)
            if (this.injected.Has(id))
                this.injected.Delete(id)
            if (g.selectedNodes.Has(id))
                g.selectedNodes.Delete(id)
        }
    }

    _RemoveFromOrder(id) {
        no := []
        for x in this.order {
            if (x != id)
                no.Push(x)
        }
        this.order := no
    }

    ; ----------------------------------------------------------------- 右键添加节点

    _BuildContextMenu() {
        ; MaxHeight 触发主题 ContextMenu 模板内置的 ScrollViewer 滚动；MinWidth 加宽弹窗
        canvas := this.graph.canvas
        cmEl := canvas.Add("FrameworkElement.ContextMenu")
        cm := cmEl.Add("ContextMenu").MinWidth("220").MaxHeight("420").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).Foreground("{DynamicResource TextMain}")
        for i, name in this.CmdList {
            mi := cm.Add("MenuItem").Name("MG_Add_" i).Header(name)
            iconUri := this._IconUri(i)
            if (iconUri != "")
                mi.Add("MenuItem.Icon").Add("Image").SetProp("Source", iconUri).Width("16").Height("16")
        }
        ; 将 ContextMenu 属性元素移到画布子元素最前，保证"属性元素在内容子元素之前"。
        ; 否则该属性元素会夹在 Canvas 的隐式 Children（Rectangle 背景、各节点…）中间，
        ; 切断 Children 集合，导致 WPF 报 XamlDuplicateMemberException：已对 Canvas 设置 Children 属性。
        ; 注意：不能假设 cmEl 一定是最后一个子元素——按对象身份定位其真实位置后再移到最前。
        ch := canvas._Children
        idx := 0
        for i, c in ch {
            if (c == cmEl) {
                idx := i
                break
            }
        }
        if (idx > 1) {
            ch.RemoveAt(idx)
            ch.InsertAt(1, cmEl)
        }
    }

    OnAddCmd(cmdName, *) {
        if (this.ui == "" || !this.ui.wpfHwnd || this.graph == "")
            return
        ; 在右键位置运行时注入完整内联节点（不重建窗口，避免闪烁）；不自动连线
        this._CaptureLinks()
        this._SyncPositionsFromGraph()
        id := this._NewId()
        node := this._DefaultObj(cmdName)
        this.cmdNodes[id] := node
        this.order.Push(id)
        ox := this.graph.HasProp("lastRightClickX") ? this.graph.lastRightClickX - this.graph.offsetX : 200
        oy := this.graph.HasProp("lastRightClickY") ? this.graph.lastRightClickY - this.graph.offsetY : 200
        this.pos[id] := { x: ox, y: oy }
        this._InjectFullNode(id, node)
        this._Apply()
    }

    ; 运行时注入一个完整可内联编辑的节点（不重建窗口）：
    ;   片段 XAML → AddXamlItem；登记 g.nodes；补绑引擎拖动/选中事件 + 本类事件；启用拖动。
    _InjectFullNode(id, node) {
        g := this.graph
        this._NodeFragments(id, node, &nodeXaml, &portInXaml, &portOutXaml)
        g.ui.Update(g.id, "AddXamlItem", nodeXaml)
        g.ui.Update(g.id, "AddXamlItem", portInXaml)
        g.ui.Update(g.id, "AddXamlItem", portOutXaml)

        p := this.pos[id]
        x := p.x + g.offsetX
        y := p.y + g.offsetY
        g.nodes.Push({ Id: id, Title: this._Parse(node.CurCMD).type, X: x, Y: y, W: 160, H: 60, Type: "Process" })

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
        title := this._XmlEsc(d.type)
        detail := this._XmlEsc(this._Summary(d))
        tip := this._XmlEsc(GetLang("双击编辑"))

        nodeXaml := '<Border ' ns ' x:Name="Node_' id '" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="6" Width="160" Canvas.Left="' x '" Canvas.Top="' y '"><Border.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="2" Opacity="0.4" Direction="270" Color="Black"/></Border.Effect><Grid><Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border Grid.Row="0" Background="#3E3E50" CornerRadius="5,5,0,0" Cursor="SizeAll"><TextBlock Text="' title '" Foreground="White" FontWeight="Bold" FontSize="11" VerticalAlignment="Center" Margin="10,0"/></Border><StackPanel Grid.Row="1" Margin="10,6,10,8"><TextBlock Text="' detail '" Foreground="#DDDDDD" FontSize="11" TextWrapping="Wrap"/><TextBlock Text="' tip '" Foreground="#888888" FontSize="9" Margin="0,4,0,0"/></StackPanel></Grid></Border>'
        g.ui.Update(g.id, "AddXamlItem", nodeXaml)

        portIn := '<Ellipse ' ns ' x:Name="Port_In_' id '" Width="10" Height="10" Fill="#4CAF50" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x - 5) '" Canvas.Top="' (y + 30) '" IsHitTestVisible="True" Cursor="Hand"/>'
        g.ui.Update(g.id, "AddXamlItem", portIn)
        portOut := '<Ellipse ' ns ' x:Name="Port_Out_' id '" Width="10" Height="10" Fill="#FF5722" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x + 155) '" Canvas.Top="' (y + 30) '" IsHitTestVisible="True" Cursor="Hand"/>'
        g.ui.Update(g.id, "AddXamlItem", portOut)

        g.nodes.Push({ Id: id, Title: d.type, X: x, Y: y, W: 160, H: 60, Type: "Process" })

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
        if (d.type == GetLang("移动"))
            return "(" d.posx ", " d.posy ")  " GetLang("移动速度：") d.speed
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
        for conn in this.graph.connections
            newLinks.Push({ from: conn.From, to: conn.To })
        this.links := newLinks
    }

    ; 用户新建连线后：加粗连线并补绑点击事件
    _OnConnectionsChanged() {
        this._ThickenConnections()
        for conn in this.graph.connections
            this.ui.OnEvent(conn.PathId, "MouseLeftButtonDown", ObjBindMethod(this.graph, "OnPathClicked", conn.PathId))
    }

    ; 把所有连线加粗，增大命中区域以便单击选中（默认 2.5px 太细难以点中）
    _ThickenConnections() {
        if (this.graph == "" || this.ui == "")
            return
        for conn in this.graph.connections
            this.ui.Update(conn.PathId, "StrokeThickness", "6")
    }

    _DefaultObj(cmdName) {
        if (cmdName == GetLang("间隔"))
            return this._MakeNode(GetLang("间隔") "_500")
        if (cmdName == GetLang("按键"))
            return this._MakeNode(GetLang("按键") "_a_" GetLang("点击") "_100")
        if (cmdName == GetLang("移动"))
            return this._MakeNode(GetLang("移动") "_0_0_90")
        ; 其它指令：临时节点占位（仍只存 CurCMD，类型由解析判定）
        return this._MakeNode(cmdName)
    }

    ; ----------------------------------------------------------------- 内联编辑回调

    _OnKeyType(id, state, ctrl, event) {
        if (!this.cmdNodes.Has(id))
            return
        key := "TypeCmb_" id
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (state.Has(key) && state[key] != "")
            d.ktype := state[key]
        this.cmdNodes[id].CurCMD := this._BuildCmd(d)
        this._RefreshKeyVisibility(id)
        this._Apply()
    }

    ; 间隔类型下拉变更：固定/随机；切换时保留当前已填的时间值，并切换第二时间行显隐
    _OnIntervalType(id, state, ctrl, event) {
        if (!this.cmdNodes.Has(id))
            return
        key := "ITypeCmb_" id
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (state.Has("Time_" id) && state["Time_" id] != "")
            d.time := state["Time_" id]
        if (state.Has("Time2_" id) && state["Time2_" id] != "")
            d.time2 := state["Time2_" id]
        if (state.Has(key) && state[key] != "")
            d.itype := this._IntervalTypeFromText(state[key])
        this.cmdNodes[id].CurCMD := this._BuildCmd(d)
        this._RefreshIntervalVisibility(id)
        this._Apply()
    }

    ; 随机模式显示第二时间行，固定模式隐藏
    _RefreshIntervalVisibility(id) {
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (d.type != GetLang("间隔") || this.ui == "")
            return
        isRandom := d.itype == GetLang("随机")
        this.ui.Update("Time2Row_" id, "Visibility", isRandom ? "Visible" : "Collapsed")
    }

    ; 间隔类型 -> 下拉项索引
    _IntervalTypeIndex(itype) {
        return (itype == GetLang("随机")) ? 1 : 0
    }

    ; 下拉项文本 -> 间隔类型（与显示项使用同一 GetLang，确保中英文一致匹配）
    _IntervalTypeFromText(text) {
        return (text == GetLang("随机")) ? GetLang("随机") : GetLang("固定")
    }

    ; 移动方式下拉变更：映射为模式编号(0/1/2)；游戏视角(2)强制速度100
    _OnMoveMode(id, state, ctrl, event) {
        if (!this.cmdNodes.Has(id))
            return
        key := "ModeCmb_" id
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (state.Has(key) && state[key] != "")
            d.mode := this._MoveModeFromText(state[key])
        if (d.mode == "2")
            d.speed := "100"
        this.cmdNodes[id].CurCMD := this._BuildCmd(d)
        this._RefreshMoveVisibility(id)
        this._Apply()
    }

    ; 游戏视角模式下速度固定100且禁用编辑；其余模式恢复可编辑
    _RefreshMoveVisibility(id) {
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (d.type != GetLang("移动") || this.ui == "")
            return
        isGameView := (d.mode == "2" || d.mode == 2)
        if (isGameView) {
            this.ui.Update("Speed_" id, "Text", "100")
            this.ui.Update("Speed_" id, "IsEnabled", "False")
        }
        else {
            this.ui.Update("Speed_" id, "IsEnabled", "True")
        }
    }

    ; 模式编号 -> 下拉项索引
    _MoveModeIndex(mode) {
        if (mode == "1" || mode == 1)
            return 1
        if (mode == "2" || mode == 2)
            return 2
        return 0
    }

    ; 下拉项文本 -> 模式编号（与显示项使用同一 GetLang，确保中英文一致匹配）
    _MoveModeFromText(text) {
        if (text == GetLang("相对移动"))
            return "1"
        if (text == GetLang("游戏视角"))
            return "2"
        return "0"
    }

    _OnField(id, field, state, ctrl, event) {
        if (!this.cmdNodes.Has(id))
            return
        nameMap := Map("time", "Time_", "time2", "Time2_", "hold", "Hold_", "count", "Count_", "inter", "Inter_", "posx", "PosX_", "posy", "PosY_", "speed", "Speed_")
        key := nameMap[field] id
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (state.Has(key))
            d.%field% := state[key]
        this.cmdNodes[id].CurCMD := this._BuildCmd(d)
        if (field == "count")
            this._RefreshKeyVisibility(id)
        this._Apply()
    }

    ; 重算按键节点 点击时长/次数/间隔 行的显隐
    _RefreshKeyVisibility(id) {
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (d.type != GetLang("按键") || this.ui == "")
            return
        isClick := d.ktype == GetLang("点击")
        showInter := isClick && IsNumber(d.count) && (d.count + 0) > 1
        this.ui.Update("HoldRow_" id, "Visibility", isClick ? "Visible" : "Collapsed")
        this.ui.Update("CountRow_" id, "Visibility", isClick ? "Visible" : "Collapsed")
        this.ui.Update("InterRow_" id, "Visibility", showInter ? "Visible" : "Collapsed")
    }

    ; ----------------------------------------------------------------- 双击打开编辑器

    _OnNodeClick(id, *) {
        now := A_TickCount
        if (this._lastClickId == id && now - this._lastClickTime < 400) {
            this._lastClickId := ""
            this._lastClickTime := 0
            this.OpenNodeEditor(id)
        }
        else {
            this._lastClickId := id
            this._lastClickTime := now
        }
    }

    OpenNodeEditor(id) {
        if (!this.cmdNodes.Has(id))
            return
        d := this._Parse(this.cmdNodes[id].CurCMD)
        editor := ""
        if (d.type == GetLang("间隔"))
            editor := this.IntervalGui
        else if (d.type == GetLang("按键"))
            editor := this.KeyGui
        else if (d.type == GetLang("移动"))
            editor := this.MouseGui
        if (editor == "")
            return

        editor.OwnerHwnd := (this.ui != "" && this.ui.wpfHwnd) ? this.ui.wpfHwnd : ""
        editor.SureBtnAction := (cmd) => this.OnEditorSure(id, cmd)
        editor.ShowGui(this.cmdNodes[id].CurCMD)
    }

    ; 完整编辑器确定后：回写数据并刷新节点显示
    OnEditorSure(id, cmd) {
        if (!this.cmdNodes.Has(id))
            return
        this.cmdNodes[id].CurCMD := cmd
        ; 注入的简要节点无法就地刷新内部文字 → 重建为完整内联节点
        if (this.injected.Has(id)) {
            this._CaptureLinks()
            this._Render()
            return
        }
        if (this.ui != "") {
            d := this._Parse(cmd)
            this.ui.Update("Title_" id, "Text", d.type)
            if (d.type == GetLang("间隔")) {
                this.ui.Update("ITypeCmb_" id, "SelectedIndex", this._IntervalTypeIndex(d.itype))
                this.ui.Update("Time_" id, "Text", d.time)
                this.ui.Update("Time2_" id, "Text", d.time2)
                this._RefreshIntervalVisibility(id)
            }
            else if (d.type == GetLang("按键")) {
                this.ui.Update("KeyName_" id, "Text", d.key)
                this.ui.Update("TypeCmb_" id, "Text", d.ktype)
                this.ui.Update("Hold_" id, "Text", d.hold)
                this.ui.Update("Count_" id, "Text", d.count)
                this.ui.Update("Inter_" id, "Text", d.inter)
                this._RefreshKeyVisibility(id)
            }
            else if (d.type == GetLang("移动")) {
                this.ui.Update("PosX_" id, "Text", d.posx)
                this.ui.Update("PosY_" id, "Text", d.posy)
                this.ui.Update("Speed_" id, "Text", d.speed)
                this.ui.Update("ModeCmb_" id, "SelectedIndex", this._MoveModeIndex(d.mode))
                this._RefreshMoveVisibility(id)
            }
        }
        this._Apply()
    }

    ; ----------------------------------------------------------------- 生成/回写

    ; 回写：图形宏以「开始节点(MacroGraphStartNode) 的 SerialStr」作为入口引用写回 MacroArr
    _Apply() {
        if (this.SureBtnAction == "")
            return
        this._CaptureLinks()
        action := this.SureBtnAction
        action(this.startSerial)
    }

    ; ----------------------------------------------------------------- 图结构持久化

    ; 保存图结构（全部走项目标准 SaveMacroCMDData，无额外索引）：
    ;   - 每个 MacroGraphNode（CurCMD、后继 NextNodeArr 的 SerialStr、坐标）存入 GraphNodeFile.ini；
    ;   - 开始节点 MacroGraphStartNode（NodeArr=开始连向的节点、EmptyNode=无前置的自由节点、坐标）存入 GraphStartNodeFile.ini。
    ;   - MacroArr 仅记录开始节点的 SerialStr，复原时由它即可取得全部信息。
    _SaveGraph() {
        if (this.graph == "")
            return
        if (this.startSerial == "")
            this.startSerial := GetCMDSerialStr("图形开始节点")
        this._CaptureLinks()
        this._SyncPositionsFromGraph()

        ; 后继表(engineId->[engineId])、入度统计、开始节点的后继
        nextMap := Map()
        inDeg := Map()
        for id in this.order
            inDeg[id] := 0
        startNexts := []
        for link in this.links {
            if (link.from == this.startId) {
                if (this.cmdNodes.Has(link.to))
                    startNexts.Push(link.to)
                continue
            }
            if (!this.cmdNodes.Has(link.from))
                continue
            if (!nextMap.Has(link.from))
                nextMap[link.from] := []
            nextMap[link.from].Push(link.to)
            if (this.cmdNodes.Has(link.to))
                inDeg[link.to] := inDeg[link.to] + 1
        }

        ; NodeArr = 开始节点连向的节点 SerialStr
        nodeArr := []
        startedSet := Map()
        for toE in startNexts {
            nodeArr.Push(this.cmdNodes[toE].SerialStr)
            startedSet[toE] := true
        }

        ; 逐指令节点保存本体
        for id in this.order {
            node := this.cmdNodes[id]
            nexts := []
            if (nextMap.Has(id)) {
                for toE in nextMap[id] {
                    if (this.cmdNodes.Has(toE))
                        nexts.Push(this.cmdNodes[toE].SerialStr)
                }
            }
            node.NextNodeArr := nexts
            p := this.pos.Has(id) ? this.pos[id] : { x: 0, y: 0 }
            node.X := p.x
            node.Y := p.y
            SaveMacroCMDData(node)          ; 存入 GraphNodeFile.ini（key=node.SerialStr）
        }

        ; EmptyNode = 既不被开始节点连接、也无任何前置指令节点的自由节点
        emptyNode := []
        for id in this.order {
            if (startedSet.Has(id) || inDeg[id] > 0)
                continue
            emptyNode.Push(this.cmdNodes[id].SerialStr)
        }

        ; 保存开始节点 MacroGraphStartNode
        sp := this.pos.Has(this.startId) ? this.pos[this.startId] : { x: 60, y: 220 }
        startNode := MacroGraphStartNode()
        startNode.SerialStr := this.startSerial
        startNode.NodeArr := nodeArr
        startNode.EmptyNode := emptyNode
        startNode.X := sp.x
        startNode.Y := sp.y
        SaveMacroCMDData(startNode)         ; 存入 GraphStartNodeFile.ini（key=startSerial）
    }

    ; 从开始节点 SerialStr 复原整张图；成功返回 true（cmdNodes/pos/links/order 均已重建）。
    ; 读 MacroGraphStartNode 拿到 NodeArr/EmptyNode 作为种子，沿各节点 NextNodeArr 广度遍历取回全部节点。
    _LoadGraph(startSerial) {
        if (startSerial == "")
            return false
        SplitSerialTextAndNumbers(startSerial, &t, &n)
        if (t != GetLangKey("图形开始节点") || n == "")    ; 非「图形开始节点」序列码 → 按线性宏处理
            return false
        startData := GetMacroCMDData(startSerial)
        if (!IsObject(startData))
            return false
        nodeArr := (startData.HasOwnProp("NodeArr") && IsObject(startData.NodeArr)) ? startData.NodeArr : []
        emptyArr := (startData.HasOwnProp("EmptyNode") && IsObject(startData.EmptyNode)) ? startData.EmptyNode : []
        if (nodeArr.Length == 0 && emptyArr.Length == 0)
            return false      ; 无内容（未保存过/空图）→ 走线性铺开

        this.startSerial := startSerial

        ; 广度遍历收集所有节点（种子 = NodeArr ∪ EmptyNode；沿 NextNodeArr 展开）
        serialToEngine := Map()
        nextSerialsMap := Map()
        loadedSerials := []
        queue := []
        for s in nodeArr
            queue.Push(s)
        for s in emptyArr
            queue.Push(s)
        while (queue.Length > 0) {
            serial := queue.RemoveAt(1)
            if (serial == "" || serialToEngine.Has(serial))
                continue
            nodeData := GetMacroCMDData(serial)
            eid := this._NewId()
            node := MacroGraphNode()
            node.SerialStr := serial
            node.CurCMD := (IsObject(nodeData) && nodeData.HasOwnProp("CurCMD")) ? nodeData.CurCMD : ""
            this.cmdNodes[eid] := node
            this.order.Push(eid)
            x := (IsObject(nodeData) && nodeData.HasOwnProp("X")) ? nodeData.X : 0
            y := (IsObject(nodeData) && nodeData.HasOwnProp("Y")) ? nodeData.Y : 0
            this.pos[eid] := { x: x, y: y }
            serialToEngine[serial] := eid
            nexts := (IsObject(nodeData) && nodeData.HasOwnProp("NextNodeArr") && IsObject(nodeData.NextNodeArr)) ? nodeData.NextNodeArr : []
            nextSerialsMap[serial] := nexts
            for ns in nexts
                queue.Push(ns)
            loadedSerials.Push(serial)
        }

        ; 重建指令节点之间的连线（NextNodeArr 里是后继的 SerialStr）
        for serial, eid in serialToEngine {
            for nextSerial in nextSerialsMap[serial] {
                if (serialToEngine.Has(nextSerial))
                    this.links.Push({ from: eid, to: serialToEngine[nextSerial] })
            }
        }
        ; 开始节点坐标 + Start->NodeArr 连线
        this.pos[this.startId] := { x: (startData.HasOwnProp("X") ? startData.X : 60), y: (startData.HasOwnProp("Y") ? startData.Y : 220) }
        for s in nodeArr {
            if (serialToEngine.Has(s))
                this.links.Push({ from: this.startId, to: serialToEngine[s] })
        }
        ; 登记已用序号（含开始节点），避免后续 GetCMDSerialStr 生成重复
        loadedSerials.Push(startSerial)
        SetSerialByArr(loadedSerials)
        return true
    }

    ; ----------------------------------------------------------------- 指令解析/重建

    ; 创建节点：MacroGraphNode（来自 DataClass），持有 CurCMD，SerialStr 由 GetCMDSerialStr("图形节点") 生成
    _MakeNode(cmd) {
        node := MacroGraphNode()
        node.CurCMD := cmd
        node.SerialStr := GetCMDSerialStr("图形节点")
        return node
    }

    ; 解析 CurCMD，返回包含各字段的明细对象（节点信息全部由此而来，不单独存储）
    _Parse(cmd) {
        paramArr := SplitCommand(cmd)
        name := paramArr.Length >= 1 ? paramArr[1] : cmd
        d := { type: name, raw: cmd, temp: false, time: "", time2: "", itype: "", key: "", ktype: "", hold: "", count: "", inter: "", posx: "", posy: "", speed: "", mode: "" }

        if (name == GetLang("间隔")) {
            raw := paramArr.Length >= 2 ? paramArr[2] : "500"
            timeArr := StrSplit(raw, "~")
            if (timeArr.Length >= 2) {
                d.itype := GetLang("随机")
                d.time := timeArr[1]
                d.time2 := timeArr[2]
            }
            else {
                d.itype := GetLang("固定")
                d.time := raw
                d.time2 := "1000"
            }
        }
        else if (name == GetLang("按键")) {
            d.key := paramArr.Length >= 2 ? paramArr[2] : ""
            d.ktype := paramArr.Length >= 3 ? paramArr[3] : GetLang("点击")
            d.hold := paramArr.Length >= 4 ? paramArr[4] : "100"
            d.count := paramArr.Length >= 5 ? paramArr[5] : "1"
            d.inter := paramArr.Length >= 6 ? paramArr[6] : "200"
        }
        else if (name == GetLang("移动")) {
            d.posx := paramArr.Length >= 2 ? paramArr[2] : "0"
            d.posy := paramArr.Length >= 3 ? paramArr[3] : "0"
            d.speed := paramArr.Length >= 4 ? paramArr[4] : "90"
            d.mode := paramArr.Length >= 5 ? paramArr[5] : "0"
        }
        else {
            d.temp := true
        }
        return d
    }

    _BuildCmd(d) {
        if (d.type == GetLang("间隔")) {
            if (d.itype == GetLang("随机"))
                return GetLang("间隔") "_" d.time "~" d.time2
            return GetLang("间隔") "_" d.time
        }


        if (d.type == GetLang("按键")) {
            isClick := d.ktype == GetLang("点击")
            hasHold := isClick
            hasCount := hasHold && (d.count != "1" && d.count != 1)
            hasInter := hasCount && (d.inter != "0" && d.inter != 0)
            cmd := GetLang("按键") "_" d.key "_" d.ktype
            if (hasHold)
                cmd .= "_" d.hold
            if (hasCount)
                cmd .= "_" d.count
            if (hasInter)
                cmd .= "_" d.inter
            return cmd
        }

        if (d.type == GetLang("移动")) {
            cmd := GetLang("移动") "_" d.posx "_" d.posy "_" d.speed
            ; 模式：0=移动(省略) 1=相对移动 2=游戏视角，与 MouseMoveGui 保持一致
            if (d.mode != "0" && d.mode != 0 && d.mode != "")
                cmd .= "_" d.mode
            return cmd
        }
        return d.raw
    }

    ; ----------------------------------------------------------------- 节点构建

    ; 开始/结束等无内联控件的节点
    _BuildBaseNode(id, title, nodeType) {
        node := this._NewNodeShell(id, title, nodeType, &body)
        return node
    }

    ; 指令节点（含内联编辑控件）
    _BuildCmdNode(id, node) {
        d := this._Parse(node.CurCMD)
        this._NewNodeShell(id, d.type, "Process", &body)
        this._FillNodeBody(id, d, body)
    }

    ; 填充节点 body（内联编辑控件）。静态构建与运行时注入复用同一套生成逻辑。
    _FillNodeBody(id, d, body) {
        if (d.type == GetLang("间隔")) {
            isRandom := d.itype == GetLang("随机")
            ; 间隔类型下拉（固定/随机）—— 标签与下拉同行
            this._AddComboRow(body, "ITypeRow_" id, GetLang("类型："), "ITypeCmb_" id
                , [GetLang("固定"), GetLang("随机")], this._IntervalTypeIndex(d.itype), true)
            ; 固定值 / 随机最小值
            this._AddFieldRow(body, "Time1Row_" id, GetLang("时间："), "Time_" id, d.time, true)
            ; 随机最大值（仅随机模式显示）
            this._AddFieldRow(body, "Time2Row_" id, GetLang("时间："), "Time2_" id, d.time2, isRandom)
        }
        else if (d.type == GetLang("按键")) {
            body.Add("TextBlock").Name("KeyName_" id).Text(d.key).Foreground("#FFD27F").FontWeight("Bold").FontSize("12").TextWrapping("Wrap")

            ; 按键类型下拉 —— 标签与下拉同行
            this._AddComboRow(body, "TypeRow_" id, GetLang("按键类型"), "TypeCmb_" id
                , [GetLang("按下"), GetLang("松开"), GetLang("点击")], this._TypeIndex(d.ktype), true)

            isClick := d.ktype == GetLang("点击")
            showInter := isClick && IsNumber(d.count) && (d.count + 0) > 1

            this._AddFieldRow(body, "HoldRow_" id, GetLang("点击时长:"), "Hold_" id, d.hold, isClick)
            this._AddFieldRow(body, "CountRow_" id, GetLang("点击次数："), "Count_" id, d.count, isClick)
            this._AddFieldRow(body, "InterRow_" id, GetLang("每次间隔："), "Inter_" id, d.inter, showInter)
        }
        else if (d.type == GetLang("移动")) {
            isGameView := (d.mode == "2" || d.mode == 2)
            ; 坐标X / 坐标Y / 移动速度 —— 标签与数值同行
            this._AddFieldRow(body, "PosXRow_" id, GetLang("坐标位置X:"), "PosX_" id, d.posx, true)
            this._AddFieldRow(body, "PosYRow_" id, GetLang("坐标位置Y:"), "PosY_" id, d.posy, true)
            this._AddFieldRow(body, "SpeedRow_" id, GetLang("移动速度："), "Speed_" id, isGameView ? "100" : d.speed, true, !isGameView)
            ; 移动方式下拉 —— 标签与下拉同行
            this._AddComboRow(body, "ModeRow_" id, GetLang("移动方式"), "ModeCmb_" id
                , [GetLang("移动"), GetLang("相对移动"), GetLang("游戏视角")], this._MoveModeIndex(d.mode), true)
        }
        else {
            ; 临时节点占位
            body.Add("TextBlock").Text(GetLang("临时节点")).Foreground("#FF9E9E").FontSize("11")
            body.Add("TextBlock").Text(d.raw).Foreground("#DDDDDD").FontSize("10").TextWrapping("Wrap")
        }
    }

    ; 构建可运行时注入的节点片段（Border + 两个端口）的 XAML 字符串。
    ; 复用 _FillNodeBody，确保注入节点与静态渲染节点结构/初始状态完全一致。
    _NodeFragments(id, node, &nodeXaml, &portInXaml, &portOutXaml) {
        g := this.graph
        d := this._Parse(node.CurCMD)
        p := this.pos.Has(id) ? this.pos[id] : { x: 200, y: 200 }
        x := p.x + g.offsetX
        y := p.y + g.offsetY
        pres := "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xns := "http://schemas.microsoft.com/winfx/2006/xaml"

        border := XAMLElement("Border")
        border.SetProp("xmlns", pres).SetProp("xmlns:x", xns)
        border.Name("Node_" id).Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6").Width("160").SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
        border.Add("Border.Effect").Add("DropShadowEffect").BlurRadius("8").ShadowDepth("2").Opacity("0.4").Direction("270").SetProp("Color", "Black")
        grid := border.Add("Grid")
        grid.Rows("30", "*")
        this._BuildHeader(grid, id, d.type, "#3E3E50")
        body := grid.Add("StackPanel").Grid_Row(1).Margin("10,6,10,8")
        this._FillNodeBody(id, d, body)
        ; 引擎接收命令后按换行符切分（ProcessMessage 的 text.Split('\n')），
        ; 而 ToString() 生成的是带缩进/注释换行的多行 XAML。若直接注入会在第一个换行处被截断，
        ; 导致 AddXamlItem 解析失败、节点及其内联控件根本不会创建（表现为新增节点显示异常）。
        ; 故注入前必须压成单行。
        nodeXaml := this._FlattenXaml(border.ToString())

        portIn := XAMLElement("Ellipse")
        portIn.SetProp("xmlns", pres).SetProp("xmlns:x", xns)
        portIn.Width("10").Height("10").Fill("#4CAF50").Stroke("#333").StrokeThickness("1").SetProp("Canvas.Left", String(x - 5)).SetProp("Canvas.Top", String(y + 30)).Name("Port_In_" id).IsHitTestVisible("True").Cursor("Hand")
        portInXaml := this._FlattenXaml(portIn.ToString())

        portOut := XAMLElement("Ellipse")
        portOut.SetProp("xmlns", pres).SetProp("xmlns:x", xns)
        portOut.Width("10").Height("10").Fill("#FF5722").Stroke("#333").StrokeThickness("1").SetProp("Canvas.Left", String(x + 155)).SetProp("Canvas.Top", String(y + 30)).Name("Port_Out_" id).IsHitTestVisible("True").Cursor("Hand")
        portOutXaml := this._FlattenXaml(portOut.ToString())
    }

    ; 把 XAMLElement.ToString() 的多行输出压成单行，供运行时 AddXamlItem 注入使用。
    ; 引擎按 `n 切分命令，多行 XAML 会被截断；属性值里的换行已被 ToString 转义为 &#10;，
    ; 故此处移除的全部是结构性换行/缩进，安全。
    _FlattenXaml(s) {
        s := StrReplace(s, "`r", "")
        s := StrReplace(s, "`n", "")
        return s
    }

    ; 创建节点外壳（Border + 头部标题 + 端口），body 通过引用返回供填充
    _NewNodeShell(id, title, nodeType, &body) {
        g := this.graph
        p := this.pos.Has(id) ? this.pos[id] : { x: 200, y: 200 }
        x := p.x + g.offsetX
        y := p.y + g.offsetY
        headerColor := nodeType == "Input" ? "#2E5A2E" : (nodeType == "Output" ? "#5A2E2E" : "#3E3E50")

        node := g.canvas.Add("Border").Name("Node_" id).Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6").Width("160").SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
        node.Add("Border.Effect").Add("DropShadowEffect").BlurRadius("8").ShadowDepth("2").Opacity("0.4").Direction("270").SetProp("Color", "Black")

        grid := node.Add("Grid")
        grid.Rows("30", "*")

        this._BuildHeader(grid, id, title, headerColor)

        body := grid.Add("StackPanel").Grid_Row(1).Margin("10,6,10,8")

        if (nodeType != "Input")
            g.canvas.Add("Ellipse").Width("10").Height("10").Fill("#4CAF50").Stroke("#333").StrokeThickness("1").SetProp("Canvas.Left", String(x - 5)).SetProp("Canvas.Top", String(y + 30)).Name("Port_In_" id).IsHitTestVisible("True").Cursor("Hand")
        if (nodeType != "Output")
            g.canvas.Add("Ellipse").Width("10").Height("10").Fill("#FF5722").Stroke("#333").StrokeThickness("1").SetProp("Canvas.Left", String(x + 155)).SetProp("Canvas.Top", String(y + 30)).Name("Port_Out_" id).IsHitTestVisible("True").Cursor("Hand")

        nodeObj := { Id: id, Title: title, X: x, Y: y, UI: node, W: 160, H: 60, Type: nodeType }
        g.nodes.Push(nodeObj)
        return node
    }

    ; 节点标题栏（图标 + 标题）。静态构建与运行时注入复用同一逻辑
    _BuildHeader(grid, id, title, headerColor) {
        header := grid.Add("Border").Grid_Row(0).Cursor("SizeAll").Background(headerColor).CornerRadius("5,5,0,0")
        hp := header.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center").Margin("8,0")
        iconUri := this._IconForType(title)
        if (iconUri != "")
            hp.Add("Image").SetProp("Source", iconUri).Width("14").Height("14").Margin("0,0,5,0").VerticalAlignment("Center")
        hp.Add("TextBlock").Name("Title_" id).Text(title).Foreground("White").FontWeight("Bold").FontSize("11").VerticalAlignment("Center")
        return header
    }

    ; 由指令类型名查找对应图标 URI（匹配 CmdList 顺序）；开始节点等无对应项返回空
    _IconForType(typeName) {
        for i, n in this.CmdList {
            if (n == typeName)
                return this._IconUri(i)
        }
        return ""
    }

    ; 一行 "标签 + 文本框"，visible 控制初始显隐，enabled 控制文本框是否可编辑
    _AddFieldRow(body, rowName, labelText, boxName, boxValue, visible, enabled := true) {
        row := body.Add("StackPanel").Name(rowName).Orientation("Horizontal").Margin("0,3,0,0")
        if (!visible)
            row.Visibility("Collapsed")
        row.Add("TextBlock").Text(labelText).Foreground("#DDDDDD").FontSize("11").Width("62").VerticalAlignment("Center")
        box := this._MakeTextBox(row, boxName, boxValue, "66")
        if (!enabled)
            box.IsEnabled("False")
        return row
    }

    ; 一行 "标签 + 下拉框"，visible 控制初始显隐
    _AddComboRow(body, rowName, labelText, comboName, items, selIndex, visible) {
        row := body.Add("StackPanel").Name(rowName).Orientation("Horizontal").Margin("0,3,0,0")
        if (!visible)
            row.Visibility("Collapsed")
        row.Add("TextBlock").Text(labelText).Foreground("#DDDDDD").FontSize("11").Width("62").VerticalAlignment("Center")
        cmb := row.Add("ComboBox").Name(comboName).Width("66").Height("22").MinHeight("0").FontSize("11").SelectedIndex(selIndex)
        for it in items
            cmb.Add("ComboBoxItem").Content(it)
        return row
    }

    ; 统一的小高度文本框（MinHeight=0 覆盖主题默认的 36，否则高度不生效）
    _MakeTextBox(parent, name, value, width) {
        return parent.Add("TextBox").Name(name).Text(value).Width(width).Height("20").MinHeight("0").FontSize("11").Padding("4,0").VerticalContentAlignment("Center")
    }

    ; ----------------------------------------------------------------- 辅助

    _TypeIndex(ktype) {
        if (ktype == GetLang("按下"))
            return 0
        if (ktype == GetLang("松开"))
            return 1
        return 2   ; 点击
    }

    _NewId() {
        this.seq += 1
        return "Cmd" this.seq
    }
}
