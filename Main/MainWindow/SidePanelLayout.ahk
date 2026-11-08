
    ; AI 侧栏的事件绑定。侧栏按需构建（只有当前页签先建），绑定必须跟着建的动作走，
    ; 否则晚建出来的页签侧栏是死的（按钮不响应、输入框收不到键）。
    ; 统一走 _BindLive：Show 之后注入的控件不在建窗事件表里，引擎侧钩子要靠 BindEvent 现挂。
    _BindAiPanel(t) {
        this._BindLive("AiSplit_" t, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnAiSplitStart"))
        this._BindLive("BtnSideModeTree_" t, "Click", ObjBindMethod(this, "OnSidePanelMode", 1))
        this._BindLive("BtnSideModeAi_" t, "Click", ObjBindMethod(this, "OnSidePanelMode", 2))
        this._BindLive("BtnSideToolsToggle_" t, "Click", ObjBindMethod(this, "OnSideToolsToggle"))
        this._BindLive("AiInput_" t, "TextChanged", ObjBindMethod(this, "OnAiInputChanged", t))
        this._BindLive("AiInput_" t, "PreviewKeyDown:Return", ObjBindMethod(this, "OnAiInputEnter", t))
        this._BindLive("AiInput_" t, "PreviewKeyDown:V", ObjBindMethod(this, "OnAiInputPasteKey", t))
        ; 焦点跟踪：侧栏逻辑树的窗口级 $^c/$^v/$^z/$^y/Delete 会吞键，AI 框同样收不到按键（含 Ctrl+V 贴图）
        this._BindLive("AiInput_" t, "GotFocus", ObjBindMethod(this, "OnTextInputFocus", "AiInput_" t))
        this._BindLive("AiInput_" t, "LostFocus", ObjBindMethod(this, "OnTextInputBlur", "AiInput_" t))
        this._BindLive("AiInput_" t, "FileDrop", ObjBindMethod(this, "OnAiInputFileDrop", t))
        this._BindLive("AiInput_" t, "Drop", ObjBindMethod(this, "OnAiInputFileDrop", t))
        this._BindLive("AiInputHost_" t, "FileDrop", ObjBindMethod(this, "OnAiInputFileDrop", t))
        this._BindLive("AiInputHost_" t, "Drop", ObjBindMethod(this, "OnAiInputFileDrop", t))
        this._BindLive("AiSend_" t, "Click", ObjBindMethod(this, "OnAiSendClick", t))
        this._BindLive("AiMic_" t, "Click", ObjBindMethod(this, "OnAiMicClick", t))
        this._BindLive("SideAiToolHistory_" t, "Click", ObjBindMethod(this, "OnSideAiToolHistory", t))
        this._BindLive("SideAiToolValidate_" t, "Click", ObjBindMethod(this, "OnSideAiToolValidate", t))
        this._BindLive("SideAiToolSettings_" t, "Click", ObjBindMethod(this, "OnSideAiToolSettings", t))
        this._BindLive("SideAiToolTop_" t, "Click", ObjBindMethod(this, "OnSideToolTop", t))
        this._BindSideTree(t)
    }

    ; OnEvent 只登记 AHK 侧回调（仅随建窗载荷送达引擎）；Show 之后动态注入的控件
    ; 必须让引擎按名字现找控件挂钩子（走 _QueueBind 的批量下发）。
    ; 引擎按「事件键 + 控件引用」去重，建窗时已挂过的重复发无害。
    _BindLive(name, evt, cb) {
        this.ui.OnEvent(name, evt, cb)
        this.ui.BindEventBatched(name, evt)
    }

    ; 按需建出某个页签的 AI 侧栏（幂等）：生成一份侧栏 XAML 注入占位 Grid，
    ; 再按当前全局状态（是否展开、宽度、逻辑树/AI 模式）把这个新实例对齐。
    _EnsureAiPanel(idx) {
        if (!this.HasOwnProp("_aiPanels") || !IsObject(this._aiPanels))
            this._aiPanels := Map()
        if (this._aiPanels.Has(idx))
            return
        this._aiPanels[idx] := true
        g := XAML_Generator("Grid")
        try {
            this._BuildAiAssistPanel(g, idx)
            ; AddXamlItem 走 XamlReader.Parse 独立解析：拿不到 Window 根上的 xmlns
            ; （直接报「无法创建未知类型 Grid」），也解析不了 {StaticResource ...}
            ; （样式只在 Window.Resources 里，SyncWindowResourcesToApp 有意跳过 Style）。
            ; 所以套一层同构包装 Grid：自带全部命名空间 + 完整资源块，AiWrap 原样落在内层第 1 列。
            for child in g.Children()
                this.ui.Update("TabGrid_" idx, "AddXamlItem"
                    , '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
                    . ' xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
                    . ' xmlns:sys="clr-namespace:System;assembly=mscorlib"'
                    . ' xmlns:primitives="clr-namespace:System.Windows.Controls.Primitives;assembly=PresentationFramework"'
                    . ' Grid.Column="1">'
                    . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
                    . '<Grid.Resources>' this._resInjectStr '</Grid.Resources>'
                    . child.ToString()
                    . '</Grid>')
        } catch as e {
            XamlUiDiag("_EnsureAiPanel 异常: " e.Message " @" e.Line, "MainWin")
            return
        }
        this._BindAiPanel(idx)
        ; 启动时是遍历所有页签发 EnableDropTarget 的，晚建的这一份要单独补
        try this.ui.Update("AiInput_" idx, "EnableDropTarget", "RmtAiFile")
        try this.ui.Update("AiInputHost_" idx, "EnableDropTarget", "RmtAiFile")
        if (this.aiAssistOpen) {
            try this.ui.Update("AiWrap_" idx, "MinWidth", "0")
            try this.ui.Update("AiWrap_" idx, "Width", String(this.aiPanelW))
            try this.ui.Update("AiInner_" idx, "MinWidth", "0")
            try this.ui.Update("AiInner_" idx, "Width", String(this.aiPanelW))
            try this.ui.Update("AiWrap_" idx, "Visibility", "Visible")
            try this.ui.Update("BtnAiPanel_" idx, "Content", Chr(0xE76C))
        }
        this._ApplySidePanelMode()
        this._ApplySideToolsVisibility()
    }

    OnToggleAiPanel(state, ctrl, event) {
        this.aiAssistOpen := !this.aiAssistOpen
        this._ApplyAiPanelUi()
    }

    _ApplyAiPanelGlyph() {
        glyph := this.aiAssistOpen ? Chr(0xE76C) : Chr(0xE76B)
        m := this._AiRailMargin()
        u := []
        for t in this._useVirtual {
            u.Push({ControlName: "BtnAiPanel_" t, PropertyName: "Content", Value: glyph})
            u.Push({ControlName: "BtnAiPanel_" t, PropertyName: "Margin", Value: m})
        }
        if (u.Length)
            try this.ui.BatchUpdate(u)
    }

    _AiRailMargin() {
        ; -2：钮的右边框压在内容框 1.5px 右边框内侧（贴边）。
        ; 主窗口模板 ResizeBorderThickness=4：贴边后仅最外 0.5px 落在非客户区拖拽带里，
        ; hover/点击全程有效（早先 6px 带会吞掉按钮右缘 2.5px，贴边侧鼠标未出钮就丢高亮）
        return "0,0,-2,0"
    }

    _ListScrollMargin(open) {
        return "0"
    }

    _ApplyListScrollMargin(open) {
        m := this._ListScrollMargin(open)
        u := []
        for t in this._useVirtual
            u.Push({ControlName: "FoldList_" t, PropertyName: "Margin", Value: m})
        if (u.Length)
            try this.ui.BatchUpdate(u)
    }

    _ApplyAiPanelUi() {
        this._ApplyAiPanelGlyph()
        opening := this.aiAssistOpen
        ; 先开启动画，重活延后，避免首次展开卡顿
        ; 动画没跑完就再次切换时不传起点（空串），让引擎从当前渲染宽度续接，避免跳回去重跑
        from := this._aiAnim ? "" : (opening ? 0 : this.aiPanelW)
        to := opening ? this.aiPanelW : 0
        this._StartAiPanelAnim(from, to)
        if (opening) {
            this._ApplyListScrollMargin(true)
            t0 := MainSoftData.TableIndex
            if (IsObject(this._vl) && this._useVirtual.Has(t0))
                this._vl.SetCompact(t0, true)
            this._EnsureAiSeeded(t0)
            if (this.sidePanelMode == 1)
                SetTimer(ObjBindMethod(this, "RefreshSideTree", t0), -1)
        } else {
            this.HideSideDebugTools()
            this._ApplyListScrollMargin(false)
            t0 := MainSoftData.TableIndex
            if (IsObject(this._vl) && this._useVirtual.Has(t0))
                this._vl.SetCompact(t0, false)
        }
    }

    ; 展开/收起侧栏：整段动画交给引擎的 DoubleAnimation，AHK 只发一批命令。
    ; 旧实现用 16ms 定时器每帧给每个页签发 Width，10 个页签就是每秒 ~600 条同步 SendMessage，
    ; 每条都阻塞 AHK 主线程等 WPF 处理完——这是展开/拖拽 AI 面板卡顿的主因。
    _StartAiPanelAnim(from, to) {
        ms := this._AiPanelAnimMs()
        hasFrom := (from != "")
        this._aiAnim := true
        this._aiAnimTo := to
        innerW := to > 0 ? to : this.aiPanelW

        u := []
        for t in this._useVirtual {
            u.Push({ControlName: "AiWrap_" t, PropertyName: "MinWidth", Value: "0"})
            ; 从静止态起步时先落定起点；动画中途续接则不动，让引擎从当前渲染宽度接上
            if (hasFrom)
                u.Push({ControlName: "AiWrap_" t, PropertyName: "AnimWidth", Value: from ",0"})
            u.Push({ControlName: "AiWrap_" t, PropertyName: "Visibility", Value: "Visible"})
            u.Push({ControlName: "AiInner_" t, PropertyName: "MinWidth", Value: "0"})
            u.Push({ControlName: "AiInner_" t, PropertyName: "Width", Value: String(innerW)})
            u.Push({ControlName: "AiInner_" t, PropertyName: "HorizontalAlignment", Value: "Right"})
        }
        ; 动画行紧跟在准备行之后、同一批下发：所有页签在同一帧开始跑，视觉才同步
        for t in this._useVirtual
            u.Push({ControlName: "AiWrap_" t, PropertyName: "AnimWidth", Value: to "," ms})
        if (u.Length)
            try this.ui.BatchUpdate(u)

        SetTimer(this.aiFinishTick, -(ms + 40))
    }

    ; 动画结束后的定稿（复位 MinWidth、收起后隐藏）。整段落一次，不再逐帧。
    _FinishAiPanelAnim() {
        if (!this._aiAnim)
            return
        ; 期间被反向切换过（定时器已被新的覆盖，这里再挡一次）：本次定稿已过期
        if ((this._aiAnimTo > 0) != this.aiAssistOpen)
            return
        this._aiAnim := false
        to := this._aiAnimTo
        u := []
        if (to <= 0) {
            for t in this._useVirtual {
                u.Push({ControlName: "AiWrap_" t, PropertyName: "Visibility", Value: "Collapsed"})
                u.Push({ControlName: "AiWrap_" t, PropertyName: "Width", Value: String(this.aiPanelW)})
                u.Push({ControlName: "AiWrap_" t, PropertyName: "MinWidth", Value: String(this._AiPanelMinW())})
            }
        } else {
            for t in this._useVirtual {
                u.Push({ControlName: "AiWrap_" t, PropertyName: "Width", Value: String(this.aiPanelW)})
                u.Push({ControlName: "AiWrap_" t, PropertyName: "MinWidth", Value: String(this._AiPanelMinW())})
                u.Push({ControlName: "AiInner_" t, PropertyName: "Width", Value: String(this.aiPanelW)})
                u.Push({ControlName: "AiInner_" t, PropertyName: "MinWidth", Value: String(this._AiPanelMinW())})
            }
        }
        if (u.Length)
            try this.ui.BatchUpdate(u)
    }

    OnAiSplitStart(state, ctrl, event) {
        if (!this.aiAssistOpen)
            return
        this._aiDrag := true
        this._aiDragStartW := this.aiPanelW
        ; 拖拽期间才要窗口级鼠标坐标，先打开回传（松开时在 OnAiSplitEnd 关掉）
        this.ui.SetWindowMouseMove(true)
        ; 容器总宽在拖拽过程中不变，宽度上限按下时问引擎一次，之后整段拖拽都用这个值
        this._aiDragMaxW := 0
        try this._aiDragMaxW := Integer(this.ui.Query("Window>MaxPanelWidth:" this._AiListMinW()))
        ; 桥接层统一按 Window 坐标上报，按下时就记录起点，短距离拖拽也能生效。
        this._aiDragStartX := this._AiDragX(state)
        this._ShowAiDragShield(true)
        try this.ui.Update("Window", "Cursor", "SizeWE")
    }

    OnAiSplitMove(state, ctrl, event) {
        if (!this._aiDrag)
            return
        x := this._AiDragX(state)
        if (x == "")
            return
        if (this._aiDragStartX == "") {
            this._aiDragStartX := x
            return
        }
        this._SetAiPanelWidth(this._aiDragStartW + (this._aiDragStartX - x))
    }

    OnAiSplitEnd(state := "", ctrl := "", event := "") {
        if (!this._aiDrag)
            return
        this._aiDrag := false
        this._aiDragStartX := ""
        this._aiDragMaxW := 0
        this.ui.SetWindowMouseMove(false)
        ; 分栏按下时引擎会 CaptureMouse（拖出 6px 热区仍要跟手）；万一 Up 没派发到，
        ; 捕获会一直挂在 UI 线程上，同一引擎里的其它窗口就全点不动了。这里主动释放。
        try this.ui.Update("Window", "ReleaseCapture", "")
        this._ShowAiDragShield(false)
        try this.ui.Update("Window", "Cursor", "Arrow")
        if (IsSet(MainSoftData))
            MainSoftData.AiPanelWidth := this.aiPanelW
    }

    _ShowAiDragShield(on) {
        vis := on ? "Visible" : "Collapsed"
        u := []
        for t in this._useVirtual
            u.Push({ControlName: "AiDragShield_" t, PropertyName: "Visibility", Value: vis})
        if (u.Length)
            try this.ui.BatchUpdate(u)
    }

    _AiDragX(state) {
        coord := ""
        if (IsObject(state) && state.Has("DragCoords"))
            coord := state["DragCoords"]
        if (coord == "")
            return ""
        parts := StrSplit(coord, ",")
        if (parts.Length < 1)
            return ""
        try
            return Integer(parts[1])
        return ""
    }

    ; 面板宽度上限由引擎给出：它知道列表和面板的实际宽度，也知道哪个页签当前可见。
    ; 主程序只做数值夹取，不再回读 FoldList 的 ActualWidth。
    _ClampAiPanelW(w) {
        w := Integer(w)
        minW := this._AiPanelMinW()
        maxW := this._AiPanelMaxW()
        if (this._aiDrag && this._aiDragMaxW > 0) {
            ; 拖拽全程容器总宽不变，按下时问引擎一次就够，别每帧往返
            if (this._aiDragMaxW < maxW)
                maxW := this._aiDragMaxW
        } else {
            try {
                avail := Integer(this.ui.Query("Window>MaxPanelWidth:" this._AiListMinW()))
                if (avail > 0 && avail < maxW)
                    maxW := avail
            }
        }
        if (maxW < minW)
            maxW := minW
        if (w < minW)
            w := minW
        if (w > maxW)
            w := maxW
        return w
    }
    _SetAiPanelWidth(w) {
        w := this._ClampAiPanelW(w)
        if (w == this.aiPanelW)
            return
        this.aiPanelW := w
        ; 拖拽时外框与内框一起改：合并成一条批量命令，整帧只有一次跨进程往返。
        ; 内框原来用 160ms 定时器缓动跟随，每帧又是 N 条同步消息；拖拽本身是连续的，
        ; 直接跟上反而更跟手，也省掉了那组定时器。
        u := []
        for t in this._useVirtual {
            u.Push({ControlName: "AiWrap_" t, PropertyName: "AnimWidth", Value: w ",0"})
            u.Push({ControlName: "AiInner_" t, PropertyName: "Width", Value: String(w)})
        }
        if (u.Length)
            try this.ui.BatchUpdate(u)
    }

    OnSidePanelMode(mode, state, ctrl, event) {
        this.sidePanelMode := Integer(mode)
        this._ApplySidePanelMode()
        t := MainSoftData.TableIndex
        if (this.sidePanelMode == 1)
            this.RefreshSideTree(t)
        else if (this.aiAssistOpen) {
            this._EnsureAiSeeded(t)
            this._EnableAiInputFileDrop()
        }
    }

    _AddSideToolSep(toolBar) {
        toolBar.Add("Rectangle").Width(1).Height(16).Fill("{DynamicResource ControlBorder}")
            .VerticalAlignment("Center").Margin("6,0,10,0").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")
    }

    _AddSideToolBtn(toolBar, idx, key, glyph, tip, isToggle, prefix := "SideTool") {
        host := toolBar.Add("Grid").Margin("0,0,4,0").ClipToBounds("False")
        btn := host.Add("Button").Name(prefix key "_" idx)
            .Style("{StaticResource RmtFoldToolBtn}")
            .Width(26).Height(26).MinHeight(26)
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .ToolTip(tip)
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}")
            .Foreground("{DynamicResource TextMain}")
        if (key == "Step") {
            ; 向下箭头 + 下方小圆点（单步）
            sp := btn.Add("StackPanel").Orientation("Vertical").HorizontalAlignment("Center").VerticalAlignment("Center")
            sp.Add("TextBlock").Text(Chr(0xE74B)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
                .FontSize(9).HorizontalAlignment("Center").Foreground("{DynamicResource TextMain}")
            sp.Add("Ellipse").Width(3).Height(3).Fill("{DynamicResource TextMain}")
                .HorizontalAlignment("Center").Margin("0,1,0,0")
        } else if (key == "CmdTip") {
            ; 左侧竖条 + 三条等长横线（指令日志）
            g := btn.Add("Grid").Width(14).Height(12).HorizontalAlignment("Center").VerticalAlignment("Center")
            g.Add("Rectangle").Width(1.6).Height(12).Fill("{DynamicResource TextMain}").HorizontalAlignment("Left").RadiusX(0.6).RadiusY(0.6)
            lines := g.Add("StackPanel").Orientation("Vertical").HorizontalAlignment("Right").VerticalAlignment("Center").Margin("3,0,0,0")
            loop 3
                lines.Add("Rectangle").Width(9).Height(1.6).Fill("{DynamicResource TextMain}").RadiusX(0.6).RadiusY(0.6).Margin(A_Index < 3 ? "0,0,0,2" : "0")
        } else
            btn.Content(glyph)
        if (isToggle) {
            dotHost := host.Add("Grid").Name(prefix key "Dot_" idx).Visibility("Collapsed")
            dotHost.Add("Ellipse").Width(6).Height(6).Fill("{DynamicResource Accent}")
                .HorizontalAlignment("Right").VerticalAlignment("Top")
                .Margin("0,2,2,0").IsHitTestVisible("False")
        }
    }

    SyncSideToolToggle(t, key, on, prefix := "SideTool") {
        if (!IsObject(this.ui))
            return
        btn := prefix key "_" t
        dot := prefix key "Dot_" t
        if (on) {
            try this.ui.Update(btn, "Background", "{DynamicResource ActionBg}")
            try this.ui.Update(btn, "BorderBrush", "{DynamicResource ActionStroke}")
            try this.ui.Update(btn, "Foreground", "{DynamicResource ActionText}")
            try this.ui.Update(dot, "Visibility", "Visible")
        } else {
            try this.ui.Update(btn, "Background", "{DynamicResource ControlBg}")
            try this.ui.Update(btn, "BorderBrush", "{DynamicResource ControlBorder}")
            try this.ui.Update(btn, "Foreground", "{DynamicResource TextMain}")
            try this.ui.Update(dot, "Visibility", "Collapsed")
        }
    }

    OnSideToolsToggle(*) {
        this._sideToolsExpanded := !this._sideToolsExpanded
        this._ApplySideToolsVisibility()
    }

    _ApplySideToolsVisibility() {
        expanded := !!this._sideToolsExpanded
        isTree := this.sidePanelMode == 1
        glyph := expanded ? Chr(0xE70E) : Chr(0xE70D)
        tip := expanded ? GetLang("收起操作") : GetLang("展开操作")
        for t in this._useVirtual {
            treeVis := (expanded && isTree) ? "Visible" : "Collapsed"
            aiVis := (expanded && !isTree) ? "Visible" : "Collapsed"
            try this.ui.Update("SideToolBar_" t, "Visibility", treeVis)
            try this.ui.Update("SideToolSplit_" t, "Visibility", treeVis)
            try this.ui.Update("SideAiToolBar_" t, "Visibility", aiVis)
            try this.ui.Update("SideAiToolSplit_" t, "Visibility", aiVis)
            try this.ui.Update("BtnSideToolsToggle_" t, "Content", glyph)
            try this.ui.Update("BtnSideToolsToggle_" t, "ToolTip", tip)
            if ((!expanded || !isTree) && this._sideDebugTools.Has(t))
                this._sideDebugTools[t].Hide()
            if (expanded) {
                if (isTree)
                    this.SyncSideToolToggle(t, "Top", this._sideTopOn)
                else
                    this.SyncSideToolToggle(t, "Top", this._sideTopOn, "SideAiTool")
            }
        }
    }

    OnSideAiToolHistory(t, *) {
        AiHistoryGui.ShowGui(t)
    }

    OnSideAiToolValidate(t, *) {
        item := this._ResolveSideTreeItem(t)
        if (!IsObject(item)) {
            Toast.Info(GetLang("请先选择要校验的宏"))
            return
        }
        title := GetLang("运行前校验")
        try {
            table := AiAssist._ResolveTable(t)
            idx := GetItemIndexInTable(table, item.ID)
            result := AiMacroValidation.Check(Map("tab", t, "index", idx, "item_id", item.ID))
            RmtDialog.Info(AiMacroValidation.FormatReport(result), title, this.ui.wpfHwnd)
        } catch as e {
            RmtDialog.Info(e.Message, title, this.ui.wpfHwnd)
        }
    }

    OnSideAiToolSettings(t, *) {
        AiSettingGui.ShowGui()
    }
