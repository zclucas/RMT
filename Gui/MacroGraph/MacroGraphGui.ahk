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
;   - 表格行"编辑"：空宏按首选编辑器；首条为图形开始节点时进入本编辑器。
;   - 右上角「逻辑树」：保存后切换到逻辑树编辑器（多链路需确认强行切换）。
;   - 关闭窗口时持久化图结构并回写 MacroArr（内存）；真正落盘需主界面「应用并保存」。
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
    ; 已打开的节点编辑器实例（主题变更时同步刷新）
    static openInstances := Map()

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

        ; 若梦兔全部指令（§20 改名：移动→鼠标移动、移动Pro→鼠标移动Pro、新增 增量移动）
        this.CmdList := GetLangArr(["间隔", "按键", "搜索", "搜索Pro", "鼠标移动", "鼠标移动Pro", "增量移动", "输入", "输出", "循环", "宏操作",
            "变量", "变量提取", "如果", "如果Pro", "运算", "运行", "文件读写", "文本处理", "数组", "RMT指令", "后台鼠标",
            "后台按键", "窗口管理", "按键检测", "等待", "注释", "抓图"])

        ; 各指令对应图标（顺序与 CmdList 一一对应，复用 MacroEditGui 的图标资源）
        this.CmdIconArr := ["Images\Soft\Interval.png", "Images\Soft\Key.png",
            "Images\Soft\Search.png", "Images\Soft\SearchPro.png",
            "Images\Soft\Move.png", "Images\Soft\MovePro.png", "Images\Soft\Move.png",
            "Images\Soft\Input.png", "Images\Soft\Output.png",
            "Images\Soft\Loop.png", "Images\Soft\Sub.png",
            "Images\Soft\Var.png", "Images\Soft\Extract.png",
            "Images\Soft\If.png", "Images\Soft\IfPro.png",
            "Images\Soft\Operation.png", "Images\Soft\Run.png",
            "Images\Soft\FileIO.png", "Images\Soft\TextOps.png",
            "Images\Soft\Arr.png", "Images\Soft\rabit.png",
            "Images\Soft\Mouse.png", "Images\Soft\Key.png",
            "Images\Soft\WindowManage.png", "Images\Soft\KeyCheck.png",
            "Images\Soft\Control.png",
            "Images\Soft\Comment.png", "Images\Soft\ScreenShot.png"]

        ; 复用现有子编辑器（双击节点时打开）
        this.IntervalGui := IntervalGui()
        this.KeyGui := KeyGui()
        this.MouseGui := MouseMoveGui()
        this.SearchGui := SearchGui()
        this.SearchProGui := SearchProGui()
        this.MMProGui := MMProGui()
        this.DeltaMoveGui := DeltaMoveGui()
        this.InputGui := InputGui()
        this.OutputGui := OutputGui()
        this.SubMacroGui := SubMacroGui()
        this.VariableGui := VariableGui()
        this.ExVariableGui := ExVariableGui()
        this.OperationGui := OperationGui()
        this.RunGui := RunGui()
        this.FileIOGui := FileIOGui()
        this.TextOpsGui := TextOpsGui()
        this.ArrayGui := ArrayGui()
        this.RMTCMDGui := RMTCMDGui()
        this.BGMouseGui := BGMouseGui()
        this.BGKeyGui := BGKeyGui()
        this.WindowManageGui := WindowManageGui()
        this.KeyCheckGui := KeyCheckGui()
        this.WaitGui := WaitGui()
        this.ScreenShotGui := ScreenShotGui()
        this.CommentGui := CommentGui()
        this.LoopGui := LoopGui()
        this.CompareGui := CompareGui()
        this.CompareProGui := CompareProGui()
        this.BranchGraphGui := ""     ; 搜索/如果/如果Pro 分支的「嵌套节点编辑器」（懒加载）
        this._branchExpanded := Map() ; 分支节点是否展开显示全部指令（key=分支合成ID）
        this._loopChipsExpanded := Map() ; 循环体指令卡片是否展开（key=内联用循环ID/外置用循环体合成ID）
        this._branchInjected := Map() ; 本窗口生命周期内已注入过分支节点的搜索ID（折叠/展开时只显隐不重建）
        ; 如果分支「内联展开」状态（会话级）：见 MacroGraphInline.ahk
        this._ilExpanded := Map()     ; brId -> true 是否内联展开
        this._ilSubs := Map()         ; brId -> [内联子节点id...]
        this._ilOwner := Map()        ; 内联子节点id -> 所属 brId
        this._ilSerial := Map()       ; 内联子节点id -> 其分支子图序列码（就地复用，无则空）
        this._ilStartSerial := Map()  ; brId -> 分支开始节点序列码（复用，无则空）
        this._ilSeq := 0              ; 内联子节点id 自增序号
        this._loopBodyInjected := Map() ; 本窗口生命周期内已注入过外置循环体节点的循环ID（折叠/展开时只显隐不重建）
        this._ifProUiCaseCount := Map() ; 如果Pro 节点当前 UI 已渲染的情况数（用于编辑器增删后判断是否需要重建）
        this._ifProPortMargin := Map()  ; 如果Pro 各情况出点 Margin.Top（与连线路径对齐）
        this._nodeShellGrid := ""       ; _NewNodeShell 最近构建的 Grid（IfPro 出点挂载用）
        this.OnClosedAction := ""     ; 窗口关闭后回调（嵌套分支编辑器用于通知父图刷新）
        this.ShowToTreeBtn := true    ; 右上角「逻辑树」按钮；分支子图编辑器置 false
        this.OnSwitchToTreeAction := "" ; 自定义「切换逻辑树」；空则走顶层 MyMacroGui 流程
        this._shotNodeId := ""        ; 正在执行截图取色的搜索节点ID（截图剪贴板回调用）
        this._searchClipAction := ObjBindMethod(this, "_SearchCheckClipboard") ; 截图剪贴板轮询回调（稳定引用，便于 SetTimer 开关）
        this._suppressCloseApply := false ; 切换到逻辑树时跳过关闭时的 _Apply，避免覆盖已写回的线性宏
        this._closeHandled := false       ; 防止 Window.Closed 重复触发导致分支列表被刷新叠加
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
        this._closeHandled := false
        this._CloseUI()
        this.startSerial := ""
        this.cmdNodes := Map()
        this.order := []
        this.pos := Map()
        this.links := []
        this.seq := 0
        ; 实例会被分支/循环体嵌套编辑器复用：清掉上一会话内联态，避免 _Render 误串行化脏数据
        this._ilExpanded := Map()
        this._ilSubs := Map()
        this._ilOwner := Map()
        this._ilSerial := Map()
        this._ilStartSerial := Map()
        this._ilSeq := 0

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
        ; macroStr 若本身是「图形开始节点」序列码（_LoadGraph 因内容为空才返回 false），
        ; 说明这是一张空图，绝不能当线性宏 SplitMacro——否则会把序列码本身当成一条指令，
        ; 生成一个无法识别的「临时节点」（如双击编辑空的真/假分支时出现的多余节点）。
        SplitSerialTextAndNumbers(macroStr, &mgT, &mgN)
        isEmptyGraphSerial := (mgT == GetLangKey("图形开始节点") && mgN != "")
        if (!isEmptyGraphSerial) {
            for cmd in SplitMacro(macroStr) {
                id := this._NewId()
                this.cmdNodes[id] := this._MakeNode(cmd)
                this.order.Push(id)
                this.pos[id] := { x: x, y: baseY }
                this.links.Push({ from: prevId, to: id })
                prevId := id
                x += step
            }
        }
        this._Render()
    }

    ; 根据数据模型构建并显示窗口（始终最大化；节点用保存的坐标，连线用 links）
    _Render() {
        ; 整窗重建前：把内联展开的分支回写并摘除其子节点，避免污染重建后的顶层图（重建后默认折叠）
        this._DetachAllInlineForRebuild()
        ; 双缓冲：先创建并显示新窗口，待其就绪后再关闭旧窗口，避免新增节点时窗口闪缩
        oldUi := this.ui
        this.graph := ""
        this.injected := Map()        ; 重建后所有节点均为完整内联节点
        this._branchInjected := Map() ; 新窗口：分支节点注入记录清零（NameScope 全新）
        this._loopBodyInjected := Map() ; 新窗口：外置循环体节点注入记录清零（NameScope 全新）
        this._loopChipsExpanded := Map() ; 新窗口：循环体指令卡片展开态清零
        this._ifProUiCaseCount := Map() ; 新窗口：如果Pro 情况数 UI 缓存清零
        this._ifProPortMargin := Map()  ; 新窗口：如果Pro 出点位置缓存清零
        this._nodeShellGrid := ""

        win := XAML_Generator("Window")
        win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
        ; 画布/窗口背景固定深色（不随浅色主题变白）
        win.Title(GetLang("节点编辑器")).Width(1100).Height(700).WindowStartupLocation("CenterScreen").WindowState("Maximized").Background("#FF1E1E1E")
        iconPath := StrReplace(A_WorkingDir "\Images\Soft\rabit.ico", "\", "/")
        if (FileExist(iconPath))
            win.Icon(iconPath)

        root := win.Add("Grid")
        this.graph := root.NodeGraph("RMTGraph")
        ; 画布底固定深色（与节点 DropdownBg 分离，避免浅色主题把整片画布刷白）
        this.graph.bdr.Name("MG_GraphChrome").Background("#FF1E1E1E").BorderBrush("{DynamicResource ControlBorder}")
        this._HookGraphIfProPaths()

        ; 右上角：逻辑树（分支子图可不显示）；内容链接存储，关闭时自动保存，无需保存按钮
        if (this.ShowToTreeBtn) {
            toTreeBtn := root.Add("Button").Name("MG_BtnToTree").Content(GetLang("逻辑树")).HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,12,16,0").Width("90").Height("32").Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize("14").Cursor("Hand")
            this._ApplyActionBtnStyle(toTreeBtn)
        }

        ; 渲染前：为展开的搜索节点预留分支空间（仅在后继过近时右移逻辑坐标），避免首次进入分支与后继重叠
        this._StaticSpreadExpandedSearches()

        ; 节点（使用各自保存的坐标）
        this._BuildBaseNode(this.startId, GetLang("开始"), "Input")
        for id in this.order
            this._BuildCmdNode(id, this.cmdNodes[id])

        ; 搜索/如果节点（展开态）：构建强制绑定的真/假分支节点。
        ; 后继位置由保存的坐标直接决定（收/展为位置式对齐，无需累加位移记录）。
        for id in this.order {
            if (this._HasVisibleBranches(id)) {
                this._BuildBranches(id)
                this._branchInjected[id] := true
            }
        }

        ; 循环节点（展开态）：构建外置循环体节点 + 两条回环连线（循环→体、体→循环）
        for id in this.order {
            if (this._IsExpandedLoop(id)) {
                this._BuildLoopBodyNode(id)
                this._loopBodyInjected[id] := true
            }
        }

        ; 连线（来自 links，跨重建保留）。展开/收起均由主节点直连后续；
        ; 展开时另有「主→分支」强制边（由 _BuildBranches 添加），分支无出点。
        for link in this.links {
            if (!this._NodeExists(link.from) || !this._NodeExists(link.to))
                continue
            this.graph.AddConnection(link.from, link.to)
        }

        ; 右键菜单挂在画布内 MG_CM（RMTGraph 已禁用外层 Border 演示菜单，避免滑出边界露底误弹）
        this._BuildContextMenu()

        ; ---- 宿主 ----
        ownerHwnd := this.OwnerHwnd != "" ? this.OwnerHwnd : 0
        this.ui := XAMLHost(win.ToString(), "", ownerHwnd)
        this.ui.skipFontScale := true
        this.graph.Bind(this.ui)
        this._HookGraphIfProPaths()
        for id in this.order {
            if (this._IsExpandedIfPro(id)) {
                this._RefreshIfProPortPositions(id)
                this._UpdateIfProBranchPaths(id)
            } else if (this._IsExpandedSearch(id) || this._IsExpandedIf(id)) {
                this._ApplyPairBranchPortVisibility(id)
                this._UpdatePairBranchPaths(id)
            }
        }
        this._RegisterNodeEvents()
        ; 为所有连线补绑点击事件（XNodeGraph 仅给运行时新增连线绑定，构建期连线需手动补）
        for conn in this.graph.connections
            this.ui.OnEvent(conn.PathId, "MouseLeftButtonDown", ObjBindMethod(this.graph, "OnPathClicked", conn.PathId))
        ; 用户新建连线后，对新连线加粗并补绑点击（便于单击选中）
        this.ui.OnEvent(this.graph.id, "ConnectPorts", (*) => this._OnConnectionsChanged())
        ; 出点拖拽连线到空白处松开：记录源端口和位置，弹出指令菜单
        this.ui.OnEvent(this.graph.id, "ConnectionDropped", this._OnConnectionDropped.Bind(this))
        ; Start 跟踪拖动位置
        this.ui.OnEvent("Node_" this.startId, "DragMove", this._OnNodeDrag.Bind(this, this.startId))
        for i, name in this.CmdList
            this.ui.OnEvent("MG_Add_" i, "Click", this.OnAddCmd.Bind(this, name))
        ; 出点连线到空白处：直接弹出指令菜单项事件（共用 OnAddCmd，内部已有 _pendingConnectionFrom 检测）
        for i, name in this.CmdList
            this.ui.OnEvent("MG_Drop_" i, "Click", this.OnAddCmd.Bind(this, name))
        this.ui.OnEvent("MG_Copy", "Click", (*) => this._CopySelected())
        this.ui.OnEvent("MG_Paste", "Click", (*) => this._PasteNodes(true))
        this.ui.OnEvent("MG_Delete", "Click", (*) => this._DeleteSelected())
        this.ui.OnEvent("MG_Edit", "Click", (*) => this._EditSelected())
        ; 右键（未拖动画布）时：更新菜单项状态后手动弹出右键菜单（含连线命中）
        this.ui.OnEvent(this.graph.id, "ContextMenuOpened", this._OnGraphContextMenu.Bind(this))
        ; Ctrl+V：引擎用 Mouse.GetPosition(canvas)（与拖线同源）发 PasteAt，不走右键锚点
        this.ui.OnEvent(this.graph.id, "PasteAt", this._OnPasteAt.Bind(this))
        if (this.ShowToTreeBtn)
            this.ui.OnEvent("MG_BtnToTree", "Click", (*) => this._OnSwitchToTree())
        this.ui.OnEvent("Window", "PreviewKeyDown", this._OnKeyDown.Bind(this))
        sid := this._sessionId
        this.ui.OnEvent("Window", "Closed", (*) => this.OnWindowClosed(sid))

        ; 为所有内联编辑 TextBox 绑定回车事件（输入完成后刷新节点数据）
        this._BindTextBoxEnterEvents()

        this.ui.Show()
        MacroGraphGui.openInstances[this._sessionId] := this
        this._ApplyTheme()
        this._oldUi := oldUi
        SetTimer(this._readyTimer, 50)
    }

    ; 套用 AppTheme：节点/网格/按钮跟主题；仅窗口与画布底固定深色
    _ApplyTheme() {
        if (!IsObject(this.ui))
            return
        themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
        try ApplyXamlTheme(this.ui, themeName)
        darkBg := "#FF1E1E1E"
        try this.ui.Update("Window", "Background", darkBg)
        try this.ui.Update("Resource", "BgColor", darkBg)
        try this.ui.Update("MG_GraphChrome", "Background", darkBg)
        ; 网格/连线走主题「图形节点」组(GraphLine/GraphConn)；节点体走 DropdownBg、TitleBar*、Input* 等
    }

    static RefreshOpenThemes() {
        for , inst in MacroGraphGui.openInstances {
            try {
                if (IsObject(inst) && IsObject(inst.ui))
                    inst._ApplyTheme()
            }
        }
    }

    _NodeExists(id) {
        return id == this.startId || this.cmdNodes.Has(id)
    }

    _EnableWhenReady() {
        if (this.ui == "" || !this.ui.wpfHwnd)
            return
        SetTimer(this._readyTimer, 0)
        this._ApplyTheme()
        this.graph.EnableDrag(this.ui, true)
        this._ThickenConnections()    ; 加粗连线，增大命中区域便于单击选中
        for id in this.order {
            if (this._IsExpandedIfPro(id))
                this._UpdateIfProBranchPaths(id)
        }
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

    ; 切换到逻辑树：单链路直接切换；多链路（不含搜索/如果真假分支）需确认强行切换
    ; GraphStartToLinearMacro 会递归把循环/搜索/如果等分支内的嵌套图形开始节点一并转为线性宏
    _OnSwitchToTree() {
        this._SaveGraph()
        if (HasGraphMultiBranch(this.startSerial)) {
            tip := GetLang("多链路指令无法切换到逻辑树编辑器") "`n"
                . GetLang("强行切换非第一链路的配置将丢失")
            choice := CustomMsgBox(tip, GetLang("提示"), GetLang("取消") "|" GetLang("强行切换"))
            if (choice != 2)
                return
        }

        linear := GraphStartToLinearMacro(this.startSerial)
        ; 关闭时跳过 _Apply，避免把已写回的线性宏再次覆盖成图形开始节点
        this._suppressCloseApply := true
        treeAction := this.OnSwitchToTreeAction
        this.OnSwitchToTreeAction := ""
        sureAction := this.SureBtnAction
        this.SureBtnAction := ""
        this._CloseUI()

        ; 嵌套场景（如逻辑树里双击循环体内图形开始节点）：由调用方回写并刷新，不打开顶层编辑器
        if (treeAction != "") {
            treeAction(linear)
            return
        }

        if (sureAction != "")
            sureAction(linear)
        MyMacroGui.SureFocusCon := MainSoftData.BtnSave
        MyMacroGui.SureBtnAction := sureAction
        MyMacroGui.SaveBtnAction := OnSaveSetting
        MyMacroGui.ShowGui(linear, true)
    }

    OnWindowClosed(sid := -1, *) {
        if (MacroGraphGui.openInstances.Has(sid))
            MacroGraphGui.openInstances.Delete(sid)
        ; 仅处理当前会话窗口的关闭；旧窗口迟到的异步关闭事件直接忽略，避免覆盖写空
        if (sid != this._sessionId)
            return
        ; WPF Closed 可能连发：二次进入会让 OnClosedAction 再刷一次分支芯片，列表叠成双份
        if (this._closeHandled)
            return
        this._closeHandled := true
        SetTimer(this._readyTimer, 0)
        skipApply := this._suppressCloseApply
        this._suppressCloseApply := false
        closedCb := this.OnClosedAction
        sureAction := this.SureBtnAction
        ; 先摘掉回调再落盘/回写，避免 Closed 连发时二次进入（_closeHandled）或二次刷新叠列表
        this.OnClosedAction := ""
        this.SureBtnAction := ""
        if (!skipApply) {
            this._SerializeAllInlineBranches()
            if (this.graph != "")
                this._SaveGraph()
            ; 关闭时务必把 startSerial 写回父级（TrueMacro/LoopBody 等），不能依赖后续再触发 _Apply
            if (sureAction != "" && this.startSerial != "")
                sureAction(this.startSerial)
        }
        this.ui := ""
        this.graph := ""
        this._ilExpanded := Map()
        this._ilSubs := Map()
        this._ilOwner := Map()
        this._ilSerial := Map()
        this._ilStartSerial := Map()
        if (closedCb != "")
            closedCb()
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





    _DefaultObj(cmdName) {
        if (cmdName == GetLang("间隔")) {
            ; 阶段5：配置化（间隔<serial>_备注，参数存 IntervalFile.ini）
            serial := GetCMDSerialStr("间隔")
            data := IntervalData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(CorrectRemark(serial, data.Time1))
        }
        if (cmdName == GetLang("按键")) {
            ; 阶段5：配置化
            serial := GetCMDSerialStr("按键")
            data := KeyDataConfig()
            data.SerialStr := serial
            data.KeyName := "a"
            data.KeyType := 3
            data.HoldTime := 100
            SaveMacroCMDData(data)
            return this._MakeNode(CorrectRemark(serial, "a_" GetLang("点击")))
        }
        if (IsMoveCmd(cmdName)) {
            ; 阶段5：配置化
            serial := GetCMDSerialStr(GetLangKey(cmdName))
            data := MoveDataConfig()
            data.SerialStr := serial
            data.Speed := 90
            SaveMacroCMDData(data)
            return this._MakeNode(CorrectRemark(serial, "0 0"))
        }
        if (IsMoveProCmd(cmdName)) {
            ; 移动Pro 走 INI 持久化（参数存 MMProFile.ini，CurCMD 仅为序列码引用，与执行引擎一致）
            serial := GetCMDSerialStr(GetLangKey(cmdName))
            data := MMProData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(serial)
        }
        if (IsDeltaMoveCmd(cmdName)) {
            ; §20 增量移动：配置化（参数存 DeltaMoveFile.ini）
            serial := GetCMDSerialStr(GetLangKey(cmdName))
            data := DeltaMoveData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(CorrectRemark(serial, "0 0"))
        }
        if (cmdName == GetLang("搜索") || cmdName == GetLang("搜索Pro")) {
            ; 搜索/搜索Pro 走 INI 持久化（参数存 SearchFile.ini，CurCMD 仅为序列码引用，与执行引擎一致）
            serial := GetCMDSerialStr(cmdName == GetLang("搜索Pro") ? "搜索Pro" : "搜索")
            data := SearchData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(serial)
        }
        if (cmdName == GetLang("输入")) {
            serial := GetCMDSerialStr("输入")
            data := InputData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(serial)
        }
        if (cmdName == GetLang("输出")) {
            serial := GetCMDSerialStr("输出")
            data := OutputData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(serial)
        }
        if (cmdName == GetLang("RMT指令")) {
            ; 阶段5：配置化（RMT指令<serial>_截图，参数存 RMTCMDFile.ini）
            serial := GetCMDSerialStr("RMT指令")
            data := RMTCMDData()
            data.SerialStr := serial
            SaveMacroCMDData(data)
            return this._MakeNode(CorrectRemark(serial, data.CmdStr))
        }
        for key in this._FormalIniCmdKeys() {
            if (cmdName == GetLang(key)) {
                serial := GetCMDSerialStr(key)
                cls := this._FormalIniDataClass(key)
                if (cls == "")
                    break
                data := cls()
                data.SerialStr := serial
                SaveMacroCMDData(data)
                cmd := (key == "注释") ? this._CommentCmdFromData(data) : serial
                return this._MakeNode(cmd)
            }
        }
        ; 其它指令：临时节点占位（仍只存 CurCMD，类型由解析判定）
        return this._MakeNode(cmdName)
    }

    _OnField(id, field, state, ctrl, event) {
        if (!this.cmdNodes.Has(id))
            return
        ; KeyDown 只处理回车（Enter/Return）；其它按键忽略
        if (IsObject(event) && event.HasProp("Key")) {
            k := event.Key
            if (k != "Return" && k != "Enter")
                return
        }
        nameMap := Map("time", "Time_", "time2", "Time2_", "hold", "Hold_", "count", "Count_", "inter", "Inter_", "posx", "PosX_", "posy", "PosY_", "speed", "Speed_")
        key := nameMap[field] id
        ; 优先 state；缺字段时用 Query 读当前控件（回车/失焦时 state 偶发不含该键）
        val := ""
        hasVal := false
        if (IsObject(state) && state.Has(key)) {
            val := state[key]
            hasVal := true
        }
        else if (this.ui != "") {
            q := this.ui.Query(key)
            if (q != "") {
                val := q
                hasVal := true
            }
        }
        ; 无有效值时不要回写/刷新，否则会把输入框强制刷回模型旧值（如次数 2→1）
        if (!hasVal)
            return
        ; 时间为可编辑下拉，忽略下拉初始化阶段的空值，避免覆盖已有时间
        if ((field == "time" || field == "time2") && val == "")
            return
        ; 数值字段：忽略空串（输入中）；最小为 1
        if (field == "hold" || field == "count" || field == "inter" || field == "speed") {
            if (val == "")
                return
            if (IsNumber(val) && val + 0 < 1)
                val := "1"
        }
        d := this._Parse(this.cmdNodes[id].CurCMD)
        d.%field% := val
        this.cmdNodes[id].CurCMD := this._BuildCmd(d)
        if (field == "count")
            this._RefreshKeyVisibility(id)
        ; 防抖：200ms 内只执行一次 _CaptureLinks + _Apply
        if (this.HasOwnProp("_fieldDebounceTimer"))
            SetTimer(this._fieldDebounceTimer, 0)
        this._fieldDebounceTimer := this._DoFieldApply.Bind(this)
        SetTimer(this._fieldDebounceTimer, -200)
    }

    _DoFieldApply() {
        this._CaptureLinks()
        this._Apply()
    }

    ; 为所有内联编辑 TextBox 绑定回车写回（失焦由 _RegisterMyNodeEvents 的 LostFocus 处理）
    ; 不绑 TextChanged：输入过程不必每次写回；标签拖拽改值在打开编辑器/点保存时 Flush
    ; 注：须绑 "KeyDown"（引擎按 KeyEventArgs 追加 :Return）；绑 "KeyDown:Return" 无法挂上 WPF 事件
    _BindTextBoxEnterEvents() {
        fields := ["hold", "count", "inter", "posx", "posy", "speed"]
        nameMap := Map("hold", "Hold_", "count", "Count_", "inter", "Inter_", "posx", "PosX_", "posy", "PosY_", "speed", "Speed_")
        for id in this.cmdNodes {
            for field in fields {
                boxName := nameMap[field] id
                this.ui.OnEvent(boxName, "KeyDown", ObjBindMethod(this, "_OnField", id, field))
            }
        }
    }

    ; 重算按键节点 点击时长/次数/间隔 行的显隐；同时同步控件值，避免切换后显示旧值
    _RefreshKeyVisibility(id) {
        d := this._Parse(this.cmdNodes[id].CurCMD)
        if (d.type != GetLang("按键") || this.ui == "")
            return
        ; 显隐以当前下拉 SelectedIndex 为准，避免 CurCMD 尚未跟上时行仍残留显示
        ktype := this._KeyTypeFromState("TypeCmb_" id, Map(), d.ktype)
        isClick := ktype == GetLang("点击")
        showInter := isClick && IsNumber(d.count) && (d.count + 0) > 1
        ; 同步控件值，确保切换类型后控件内容与数据模型一致
        this.ui.Update("Hold_" id, "Text", d.hold)
        this.ui.Update("Count_" id, "Text", d.count)
        this.ui.Update("Inter_" id, "Text", d.inter)
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
        ; 打开完整编辑器前：把节点内联控件（含标签拖拽改过的值）写回数据模型
        this._FlushInlineFieldsFromUI(id)
        d := this._Parse(this.cmdNodes[id].CurCMD)
        editor := ""
        if (d.type == GetLang("间隔"))
            editor := this.IntervalGui
        else if (d.type == GetLang("按键"))
            editor := this.KeyGui
        else if (IsMoveCmd(d.type))
            editor := this.MouseGui
        else if (IsDeltaMoveCmd(d.type))
            editor := this.DeltaMoveGui
        else if (IsMoveProCmd(d.type))
            editor := this.MMProGui
        else if (d.type == GetLang("搜索Pro"))
            editor := this.SearchProGui
        else if (d.type == GetLang("搜索"))
            editor := this.SearchGui
        else if (d.type == GetLang("输入"))
            editor := this.InputGui
        else if (d.type == GetLang("输出"))
            editor := this.OutputGui
        else {
            editors := this._FormalEditorMap()
            if (editors.Has(d.type))
                editor := editors[d.type]
        }
        if (editor == "")
            return

        editor.OwnerHwnd := (this.ui != "" && this.ui.wpfHwnd) ? this.ui.wpfHwnd : ""
        editor.SureBtnAction := (cmd) => this.OnEditorSure(id, cmd)
        ; RMT 指令参数存于 CurCMD 本身，打开编辑器时用规范化后的 CMD，与节点内联显示一致
        if (d.type == GetLang("RMT指令"))
            editor.ShowGui(this._BuildCmd(d))
        else
            editor.ShowGui(this.cmdNodes[id].CurCMD)
    }

    ; 完整编辑器确定后：回写数据并刷新节点显示
    OnEditorSure(id, cmd) {
        if (!this.cmdNodes.Has(id))
            return
        this.cmdNodes[id].CurCMD := cmd
        dEdit := this._Parse(cmd)
        ; 搜索/搜索Pro：就地刷新内联字段与分支节点内容，避免整窗重建（闪烁/窗口被销毁）
        if (dEdit.type == GetLang("搜索") || dEdit.type == GetLang("搜索Pro")) {
            this._RefreshSearchNode(id, dEdit)
            this._Apply()
            return
        }
        if (dEdit.type == GetLang("输入")) {
            this._RefreshInputNode(id, dEdit)
            this._Apply()
            return
        }
        if (dEdit.type == GetLang("输出")) {
            this._RefreshOutputNode(id, dEdit)
            this._Apply()
            return
        }
        if (this._IsFormalNodeType(dEdit.type)) {
            ; 形式化节点：优先就地刷新内联控件值（避免整窗 _Render 闪烁）；
            ; 未覆盖的类型回退到整体重建（从 INI 读取，保证字段/显隐完全同步）。
            if (this._RefreshFormalInline(id, dEdit)) {
                this._Apply()
                return
            }
            this._CaptureLinks()
            this._Render()
            return
        }
        ; 注入的简要节点无法就地刷新 → 重建为完整内联节点
        if (this.injected.Has(id)) {
            this._CaptureLinks()
            this._Render()
            return
        }
        if (this.ui != "") {
            d := this._Parse(cmd)
            this.ui.Update("Title_" id, "Text", this._NodeTitleText(d))
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
            else if (IsMoveCmd(d.type)) {
                this.ui.Update("PosX_" id, "Text", d.posx)
                this.ui.Update("PosY_" id, "Text", d.posy)
                this.ui.Update("Speed_" id, "Text", d.speed)
                this.ui.Update("ModeCmb_" id, "SelectedIndex", this._MoveModeIndex(d.mode))
                this._RefreshMoveVisibility(id)
            }
            else if (IsDeltaMoveCmd(d.type)) {
                this.ui.Update("DPosX_" id, "Text", d.posx)
                this.ui.Update("DPosY_" id, "Text", d.posy)
            }
            else if (IsMoveProCmd(d.type)) {
                data := this._MMProData(id)
                if (data != "") {
                    this.ui.Update("MPPosX_" id, "Text", GetLang(data.PosVarX))
                    this.ui.Update("MPPosY_" id, "Text", GetLang(data.PosVarY))
                    this.ui.Update("MPSpeed_" id, "Text", data.Speed)
                    this.ui.Update("MPActionCmb_" id, "SelectedIndex", this._MMProActionIndex(data.ActionType))
                    this.ui.Update("MPModeCmb_" id, "SelectedIndex", this._MoveModeIndex(data.MouseMoveMode))
                    this.ui.Update("MPHuman_" id, "IsChecked", (ObjHasOwnProp(data, "IsHumanMouse") && (data.IsHumanMouse == 1 || data.IsHumanMouse == "1")) ? "True" : "False")
                    this.ui.Update("MPCount_" id, "Text", ObjHasOwnProp(data, "Count") ? data.Count : 1)
                    this.ui.Update("MPInterval_" id, "Text", ObjHasOwnProp(data, "Interval") ? data.Interval : 1000)
                    this._RefreshMMProVisibility(id)
                }
            }
        }
        this._Apply()
    }

    ; 搜索/搜索Pro 完整编辑器确定后：就地刷新内联字段、显隐与真/假分支节点内容（不重建窗口）
    _RefreshSearchNode(id, d) {
        if (this.ui == "")
            return
        isPro := (d.type == GetLang("搜索Pro"))
        maxType := isPro ? 6 : 3
        st := (d.HasOwnProp("searchType") && d.searchType >= 1 && d.searchType <= maxType) ? d.searchType : 1
        this.ui.Update("Title_" id, "Text", this._NodeTitleText(d))
        this.ui.Update("STypeCmb_" id, "SelectedIndex", st - 1)
        this.ui.Update("SColor_" id, "Text", d.HasOwnProp("searchColor") ? d.searchColor : "FFFFFF")
        this.ui.Update("SText_" id, "Text", d.HasOwnProp("searchText") ? d.searchText : "")
        imgPath := d.HasOwnProp("searchImagePath") ? d.searchImagePath : ""
        ; 搜索Pro：完整路径（过长左侧 ...）；普通搜索仍只显示文件名
        if (isPro)
            this._SetSearchImgDisplay(id, imgPath)
        else
            this.ui.Update("SImg_" id, "Text", imgPath != "" ? RegExReplace(imgPath, ".*\\", "") : GetLang("未设置"))
        this.ui.Update("SStartX_" id, "Text", d.HasOwnProp("startPosX") ? d.startPosX : 0)
        this.ui.Update("SStartY_" id, "Text", d.HasOwnProp("startPosY") ? d.startPosY : 0)
        this.ui.Update("SEndX_" id, "Text", d.HasOwnProp("endPosX") ? d.endPosX : A_ScreenWidth)
        this.ui.Update("SEndY_" id, "Text", d.HasOwnProp("endPosY") ? d.endPosY : A_ScreenHeight)
        maxAct := isPro ? 3 : 4
        ma := (d.HasOwnProp("mouseAction") && d.mouseAction >= 1 && d.mouseAction <= maxAct) ? d.mouseAction : 2
        this.ui.Update("SActCmb_" id, "SelectedIndex", ma - 1)
        ; 搜索Pro 专属字段同步
        if (isPro) {
            this.ui.Update("SWin_" id, "Text", d.HasOwnProp("winInfo") ? d.winInfo : "")
            cnt := d.HasOwnProp("searchCount") ? d.searchCount : 1
            this.ui.Update("SCount_" id, "Text", (cnt == -1 || cnt == "-1") ? GetLang("无限") : "" cnt)
            this.ui.Update("SInterval_" id, "Text", d.HasOwnProp("searchInterval") ? d.searchInterval : 1000)
            this.ui.Update("SSpeed_" id, "Text", d.HasOwnProp("speed") ? d.speed : 90)
            this.ui.Update("SClick_" id, "Text", d.HasOwnProp("clickCount") ? d.clickCount : 1)
            this.ui.Update("SResTog_" id, "IsChecked", (d.HasOwnProp("resultToggle") && (d.resultToggle == 1 || d.resultToggle == "1")) ? "True" : "False")
            this.ui.Update("SResName_" id, "Text", d.HasOwnProp("resultSaveName") ? d.resultSaveName : "")
            this.ui.Update("SResTrue_" id, "Text", d.HasOwnProp("trueValue") ? d.trueValue : 1)
            this.ui.Update("SResFalse_" id, "Text", d.HasOwnProp("falseValue") ? d.falseValue : 0)
            this.ui.Update("SCoordTog_" id, "IsChecked", (d.HasOwnProp("coordToggle") && (d.coordToggle == 1 || d.coordToggle == "1")) ? "True" : "False")
            this.ui.Update("SCoordX_" id, "Text", d.HasOwnProp("coordXName") ? d.coordXName : "")
            this.ui.Update("SCoordY_" id, "Text", d.HasOwnProp("coordYName") ? d.coordYName : "")
        }
        this._RefreshSearchVisibility(id)
        ; TrueMacro/FalseMacro 可能在搜索编辑器中被修改，刷新分支节点内容
        this._RefreshBranchBody(id, true)
        this._RefreshBranchBody(id, false)
    }

    ; ----------------------------------------------------------------- 生成/回写

    ; 回写：图形宏以「开始节点(MacroGraphStartNode) 的 SerialStr」作为入口引用写回 MacroArr
    ; _flushSilent：打开编辑器前 Flush Formal 时跳过，避免批量回写主宏
    _Apply() {
        if (this.HasOwnProp("_flushSilent") && this._flushSilent)
            return
        this._SerializeAllInlineBranches()   ; 内联展开的分支：把当前编辑就地回写 TrueMacro/FalseMacro
        ; 先落盘图结构再通知父级：否则父级刷新会读到空/旧分支
        if (this.graph != "")
            this._SaveGraph()
        else
            this._CaptureLinks()
        if (this.SureBtnAction == "")
            return
        action := this.SureBtnAction
        action(this.startSerial)
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

; ============================================================================
; 职能拆分：MacroGraphGui 体量过大，按职责把方法分拆到 MacroGraph\ 子文件中。
; 每个子文件用一个 *Mixin 类「装」对应方法（方法体保持原样、this 仍为 MacroGraphGui 实例），
; 再通过 _GraftMacroGraphMixin 把这些方法嫁接到 MacroGraphGui.Prototype 上。
; mixin 类本身从不实例化，仅作方法容器。
; ============================================================================

; 把 mixin 类原型上的方法（跳过 __Class/__Init/__New 等元属性）逐个嫁接到 MacroGraphGui.Prototype。
_GraftMacroGraphMixin(mixinClass) {
    proto := MacroGraphGui.Prototype
    src := mixinClass.Prototype
    for name in src.OwnProps() {
        if (SubStr(name, 1, 2) == "__")
            continue
        proto.DefineProp(name, src.GetOwnPropDesc(name))
    }
}

#Include MacroGraphData.ahk
#Include MacroGraphHandlers.ahk
#Include MacroGraphBranch.ahk
#Include MacroGraphNodeUI.ahk
#Include MacroGraphFormal.ahk
#Include MacroGraphFormalHandlers.ahk
#Include MacroGraphIfPro.ahk
#Include MacroGraphEvents.ahk
#Include MacroGraphEdit.ahk
#Include MacroGraphMenu.ahk
#Include MacroGraphConnections.ahk
#Include MacroGraphInline.ahk
