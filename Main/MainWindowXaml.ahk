#Requires AutoHotkey v2.0
#Include MainWindow\ControlAdapters.ahk

; ============================================================================
; MainWin — 主窗口生命周期与事件入口。
; MainWindow 下的类内 #Include 按页签和功能组织方法，共用同一个 MainWin 实例。
; ============================================================================
class MainWin {
    __New() {
        this.ui := ""
        this.closed := false
        this._shareLoginTick := ""  ; 非空 = 正在等浏览器授权回调（SetTimer 的 bound method）
        this._shareVerifyTick := "" ; 非空 = 正在用 key 校验 /session/current.json
        this._linkCounter := 0
        this._linkQueue := []
        this._thankReady := false
        this._thankSponsorShown := false
        ; 每页已渲染的宏条目索引（供 RefreshItemColorUI 判断是否需更新色点）
        this.RenderedItems := Map()
        ; Epic5 虚拟列表：宏/模块显示区全走 _vl 渲染（模板已支持全部表类型：
        ; Normal/String/Menu/UI/Timing/SubMacro/Replace 的标志行 + IsEnabled 绑定），
        ; 结构操作（增删/折叠/上下移）只发 VL_INIT/VL_FOLD/VL_MOVE 增量命令，不再整表重建，
        ; 宏页走虚拟列表；非宏页（Tool/Setting/Help/Reward/Thank）走 Panel_ 不受影响
        this._vl := ""
        ; 注意：TableInfo 在 LoadCurMacroSetting 之后才填充（本类在 include 阶段实例化），
        ; _useVirtual 由 BuildAndShow 调用 _InitUseVirtual() 惰性构建
        this._useVirtual := Map()
        this._useVirtualBuilt := false
        this.aiAssistOpen := false
        this.sidePanelMode := 1
        this.aiPanelW := this._AiPanelDefaultW()
        this._aiDrag := false
        this._aiDragStartW := 0
        this._aiDragStartX := ""
        this._aiDragMaxW := 0
        this._aiAnim := false
        this._aiAnimTo := 0
        ; 一次性定时器：动画时长跑完后收尾。缓存成成员是为了让重复 SetTimer 命中同一对象（覆盖而非叠加）。
        this.aiFinishTick := ObjBindMethod(this, "_FinishAiPanelAnim")
        this._aiFitTab := 0
        this._aiPendingCaret := Map()
        this.aiFitTick := ObjBindMethod(this, "_FitAiInputCur")
        this.aiSeeded := false
        this._aiSeededTabs := Map()
        this._aiHist := Map()       ; 页签 → [{role, content}, ...]
        this._aiSessionId := Map()  ; 页签 → 当前会话 id
        this._aiBusy := Map()       ; 页签 → 正在请求
        this._aiCancel := Map()     ; 页签 → 用户点了暂停取消
        this._aiEmptyRetry := Map()
        this._aiToolRound := Map()
        this._aiThinkPhase := Map()
        this._aiThinkMode := Map()  ; 页签 → think | edit
        this._aiThinkDetail := Map()
        this._aiToolNotes := Map()
        this._aiChatTab := 0
        this.aiChatTick := ObjBindMethod(this, "_AiPollChat")
        this.aiStartTick := ObjBindMethod(this, "_AiStartChat")
        this._aiAttach := Map()      ; 页签 → [{id, kind, path, name}]
        this._aiAttachSeq := 0
        this._aiSttTab := 0          ; 正在录音的页签（同一时刻只有一路录音）
        this._aiVoiceRec := false    ; 录音中标志（占位符显隐要用）
        this._aiSttBase := ""        ; 开录时该页签框内原文
        this._aiSttLive := ""        ; 本轮识别文本
        ; AI 输入框的语音：开录 / 取字 / 收尾全在 VoiceInput 里，本处只把结果贴进框
        this._aiVoice := VoiceInput()
        this._aiVoice.OnText := ObjBindMethod(this, "_AiOnVoiceText")
        this._aiVoice.OnState := ObjBindMethod(this, "_AiOnVoiceState")
        this._aiVoice.OnNotify := ObjBindMethod(this, "_AiOnVoiceNotify")
        this._sideTreeSel := Map()
        this._dblOpenMacro := Map()  ; 页签 → 双击展开逻辑树的目标宏（再双击同一宏即折叠）
        this._sideTreeCmds := Map()
        this._sideTreeBound := Map()
        this._sideDebugTools := Map()
        this._sideTree := ""
        this._sideCtxBuilt := false
        this._rowSelIdx := Map()
        this._sideTopOn := false
        this._sideToolsExpanded := true
        this._suppressSideTreeRefresh := false
        this._aiLinkSeq := 0
        this._aiPendingLinks := []
        this._aiPendingFileActs := []
        this._aiPendingCopyAll := []
        this._aiPendingUserCards := []
        this._aiUserExpanded := Map()
        this._aiCopyAllText := Map()
        this._aiMsgFilePaths := []
        this._aiStickBottom := Map()
        this.aiScrollTick := ObjBindMethod(this, "_AiScrollPending")
        this._aiScrollTab := 0
        this._aiNormGuard := Map()
        this._pendingMacroNav := ""
        this._settingDirty := Map()
    }
#Include MainWindow\SidePanelMetrics.ahk

    ; 惰性构建虚拟表集合（须在 LoadCurMacroSetting 之后调用）
    _InitUseVirtual() {
        if (this._useVirtualBuilt)
            return
        this._useVirtual := Map()
        for t in MySoftData.TableInfo {
            if (CheckIsItemTable(t.Index))
                this._useVirtual[t.Index] := true
        }
        this._useVirtualBuilt := true
    }

    ; 按钮 hover/按下交互片段（hover=ControlBorder，按下=BtnPressBg 略深于 hover）
    _RmtBtnInteractionTriggers(bd := "Bd", line := "") {
        hoverLine := line != "" ? '<Setter TargetName="' line '" Property="Fill" Value="{DynamicResource Accent}"/>' : ""
        return '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="' bd '" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="' bd '" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . hoverLine
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True">'
            . '<Setter TargetName="' bd '" Property="Background" Value="{DynamicResource BtnPressBg}"/>'
            . '<Setter TargetName="' bd '" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . hoverLine
            . '</Trigger>'
    }

    BuildAndShow() {
        this._InitUseVirtual()
        if (IsSet(MainSoftData) && MainSoftData.HasProp("AiPanelWidth")) {
            savedW := Integer(MainSoftData.AiPanelWidth)
            if (savedW > 0)
                this.aiPanelW := this._ClampAiPanelW(savedW)
        }
        this.closed := false
        title := "RMTv" RMT_VERSION
        titleHeight := XAMLHost.GetTitleBarHeight()

        ; 根内容固定按 1400×787 设计渲染：引擎 Viewbox 会保留显式尺寸，
        ; 再按窗口实际尺寸（随屏幕等比缩放，见下方 wh 计算）等比例缩放——
        ; 任何分辨率下内容布局完全一致（高分屏只是整体放大）。
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Width(1400).Height(787)
        main.Rows(titleHeight, "*")
        main.Cols("130", "*")

        ; §11 主界面背景图（全局配置；铺满窗口最底层，内容面板未覆盖处可见）
        _bgImg := Trim(MainSoftData.BackImagePath)
        if (_bgImg != "" && FileExist(_bgImg)) {
            try {
                main.Add("Image").Name("WinBgImage").Grid_Row(0).Grid_RowSpan(2).Grid_Column(0).Grid_ColumnSpan(2)
                    .Source(_bgImg).Stretch("Fill").Opacity("0.9").IsHitTestVisible("False")
            } catch as e {
            }
        }

        ; ---- 标题栏（铬钮不放进 DragArea，与 RMT错误 弹窗一致，避免拖动区补丁把图标顶偏）----
        tb := main.Add("Grid").Grid_Row(0).Grid_ColumnSpan(2).Background("{DynamicResource TitleBarColor}")
        tb.Cols("*", "Auto")
        drag := tb.Add("Border").Grid_Column(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        dragInner := drag.Add("Grid")
        ; 标题左侧软件图标（rabit.png 带透明通道，作标题栏小图标；Grid 内需左对齐，否则会居中）
        dragInner.Add("Image").Name("TitleIcon").Width(20).Height(20).Margin("14,0,10,0").HorizontalAlignment("Left").VerticalAlignment("Center").Source(StrReplace(A_WorkingDir "\Images\Soft\rabit.png", "\", "/"))
        dragInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(XAMLHost.TitleFontSize()).FontWeight("Bold").VerticalAlignment("Center").Margin("44,0,0,0").Padding("0")
        btnGroup := tb.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Stretch")
        chromeFlat := '<Style TargetType="Button"><Setter Property="VerticalAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="border" Property="Background" Value="{DynamicResource BtnPressBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        minBtn := btnGroup.Add("Button").Name("BtnMinimize").Style("{StaticResource TitleBarCloseButton}").WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(titleHeight).MinHeight(titleHeight).Padding("0").VerticalAlignment("Stretch").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        minBtn.InjectResources(chromeFlat)
        minBtn.Add("TextBlock").Text(Chr(0xE921)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        maxBtn := btnGroup.Add("Button").Name("BtnMaximize").Style("{StaticResource TitleBarCloseButton}").WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(titleHeight).MinHeight(titleHeight).Padding("0").VerticalAlignment("Stretch").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        maxBtn.InjectResources(chromeFlat)
        maxBtn.Add("TextBlock").Text(Chr(0xE922)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        closeBtn := btnGroup.Add("Button").Name("BtnWinClose").Style("{StaticResource TitleBarCloseButton}").WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(titleHeight).MinHeight(titleHeight).Padding("0").VerticalAlignment("Stretch").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; ---- 左操作栏 ----
        left := main.Add("Grid").Grid_Row(1).Grid_Column(0).Margin("6,6,4,6")
        left.Rows("*", "Auto")
        leftTop := left.Add("StackPanel").Grid_Row(0)
        ; 当前配置名称：单行居中、非粗体；字号=主题字号；超长由 Viewbox 仅缩小不放大（改 FontSize 会被主题下限钳制）
        curNameBox := leftTop.Add("Viewbox").Margin("0,3,0,2").Stretch("Uniform").StretchDirection("DownOnly").HorizontalAlignment("Stretch")
        curNameBox.Add("TextBlock").Name("TxtCurSetting").Text(MySoftData.CurSettingName).TextAlignment("Center").HorizontalAlignment("Center").VerticalAlignment("Center").TextWrapping("NoWrap")
        sidebarButton := leftTop.Add("Button").Name("BtnConfig").Uid("gm:Main.Config").Height(33).MinHeight(33).Margin("0,3,0,2").Style("{StaticResource RmtSidebarBtn}")
        this._AddSidebarButtonContent(sidebarButton, "配置管理", 0xE8B7)
        leftTop.Add("Rectangle").Height(1).Margin("2,6,2,6").Fill("{DynamicResource ControlBorder}").Stretch("Fill")
        ; 全局操作标题 + 右侧展开按钮（控制休眠/暂停/终止所有宏的快捷键提示显隐，默认显示）
        globalOps := leftTop.Add("Grid").Margin("4,0,0,4")
        globalOps.Add("TextBlock").Text(GetLang("全局操作")).FontWeight("Bold").FontSize(11).Opacity("0.7").VerticalAlignment("Center").HorizontalAlignment("Left")
        globalOps.Add("Button").Name("BtnToggleHotkeyHint").Content(Chr(0xE70D)).Width(24).Height(24).MinHeight(24).Margin("0,0,2,0").HorizontalAlignment("Right").VerticalAlignment("Center").FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).Style("{StaticResource RmtIconBtn}")
        ; 休眠按钮：激活（休眠中）时切换为主题 Action 色背景 + 右上角白点
        suspendGrid := leftTop.Add("Grid").Margin("2,0,0,0")
        sidebarButton := suspendGrid.Add("Button").Name("BtnSuspend").Height(33).MinHeight(33).Style("{StaticResource RmtSidebarBtn}")
        this._AddSidebarButtonContent(sidebarButton, "休眠", 0xE708)
        susGridAct := suspendGrid.Add("Grid").Name("SuspendActiveGrid").Visibility("Collapsed")
        sidebarButton := susGridAct.Add("Button").Name("BtnSuspendActive").Height(33).MinHeight(33).Style("{StaticResource StateBtnActive}")
        this._AddSidebarButtonContent(sidebarButton, "休眠", 0xE708)
        susGridAct.Add("Ellipse").Name("SuspendDot").Width(8).Height(8).Fill("#FFFFFFFF").HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").IsHitTestVisible("False")
        leftTop.Add("TextBlock").Name("TxtSuspendKey").Text(FormatHotkeyDisplay(MainSoftData.SuspendHotkey)).Opacity("0.6").FontSize(11).Margin("0,0,6,0").HorizontalAlignment("Right").TextAlignment("Right")
        ; 暂停按钮：激活（暂停中）时切换为主题 Action 色背景 + 右上角白点
        pauseGrid := leftTop.Add("Grid").Margin("2,8,0,0")
        sidebarButton := pauseGrid.Add("Button").Name("BtnPause").Height(33).MinHeight(33).Style("{StaticResource RmtSidebarBtn}")
        this._AddSidebarButtonContent(sidebarButton, "暂停", 0xE769)
        pauGridAct := pauseGrid.Add("Grid").Name("PauseActiveGrid").Visibility("Collapsed")
        sidebarButton := pauGridAct.Add("Button").Name("BtnPauseActive").Height(33).MinHeight(33).Style("{StaticResource StateBtnActive}")
        this._AddSidebarButtonContent(sidebarButton, "暂停", 0xE769)
        pauGridAct.Add("Ellipse").Name("PauseDot").Width(8).Height(8).Fill("#FFFFFFFF").HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").IsHitTestVisible("False")
        leftTop.Add("TextBlock").Name("TxtPauseKey").Text(FormatHotkeyDisplay(MainSoftData.PauseHotkey)).Opacity("0.6").FontSize(11).Margin("0,0,6,0").HorizontalAlignment("Right").TextAlignment("Right")
        sidebarButton := leftTop.Add("Button").Name("BtnKill").Height(33).MinHeight(33).Margin("0,8,0,0").Style("{StaticResource RmtSidebarBtn}")
        this._AddSidebarButtonContent(sidebarButton, "终止所有宏", 0xE71A)
        leftTop.Add("TextBlock").Name("TxtKillKey").Text(FormatHotkeyDisplay(MainSoftData.KillMacroHotkey)).Opacity("0.6").FontSize(11).Margin("0,0,6,0").HorizontalAlignment("Right").TextAlignment("Right")
        sidebarButton := leftTop.Add("Button").Name("BtnReload").Height(33).MinHeight(33).Margin("0,8,0,0").Style("{StaticResource RmtSidebarBtn}")
        this._AddSidebarButtonContent(sidebarButton, "重启", 0xE777)
        if (!A_IsCompiled)
            leftTop.Add("Button").Name("BtnGMUI").Content("GM-UI").Height(33).MinHeight(33).Margin("0,8,0,0").Style("{StaticResource RmtSidebarBtn}")
        leftBottom := left.Add("StackPanel").Grid_Row(1).VerticalAlignment("Bottom")
        sidebarButton := leftBottom.Add("Button").Name("BtnHelp").Height(28).MinHeight(28).Margin("0,2,0,2")
        this._AddSidebarButtonContent(sidebarButton, "RMT文档", 0xE8A5)
        sidebarButton := leftBottom.Add("Button").Name("BtnSave").Uid("gm:Main.Save").Height(36).MinHeight(36).Margin("0,2,0,0").FontWeight("Bold")
        this._AddSidebarButtonContent(sidebarButton, "应用并保存", 0xE74E)

        ; ---- 右侧 TabControl ----
        right := main.Add("Grid").Grid_Row(1).Grid_Column(1).Margin("0,2,2,4")
        ; §10 显示页签：先按可见性过滤生成 _tabOrder（TableInfo 下标数组），页签位置 ↔ 表下标经 TabAdapter/OnTabChanged 映射
        this._tabOrder := []
        this._aiPanels := Map()    ; 已建出 AI 侧栏的页签（其余按需构建）
        ; 启动时选中可见的按键宏页签，缺失或隐藏时选中首个可见页签。
        initSel := 0
        for i, tableItem in MySoftData.TableInfo {
            if (IsTabVisible(tableItem))
                this._tabOrder.Push(i)
        }
        for pos, idx in this._tabOrder {
            if (MySoftData.TableInfo[idx].Symbol == "Normal") {
                initSel := pos - 1
                break
            }
        }
        if (this._tabOrder.Length)
            MainSoftData.TableIndex := this._tabOrder[initSel + 1]
        tab := right.Add("TabControl").Name("TabControl").Style("{StaticResource RmtMainTabCtrl}").Background("{DynamicResource BgColor}").SelectedIndex(String(initSel))
        loop this._tabOrder.Length {
            pos := A_Index
            idx := this._tabOrder[pos]
            tableItem := MySoftData.TableInfo[idx]
            ; 静态页标题不受旧配置中保存的历史名称影响。
            ; Reward 曾保存为「赞助」，此处固定显示新名称「支持我们」。
            switch tableItem.Symbol {
                case "Setting": tabTitle := GetLang("设置")
                case "Reward": tabTitle := GetLang("支持我们")
                default: tabTitle := GetLang(tableItem.Name)
            }
            tabItem := tab.Add("TabItem").Header(tabTitle)
            ; 首个/末个页签打 Tag，模板按 Tag 适配圆角（首个左圆角、末个右圆角），末个同时隐藏分割线
            if (pos == 1)
                tabItem.Tag("first")
            else if (pos == this._tabOrder.Length)
                tabItem.Tag("last")
            ; 页签内容区统一外层边框；上边距 -1 与页签条下边框重叠，避免双线且与页签条等粗
            bd := tabItem.Add("Border").BorderThickness("1.5").BorderBrush("{DynamicResource OutlineStroke}").CornerRadius("4").Margin("4,-1,2,2").Padding("2,2,0,2")
            bd.Apply({SnapsToDevicePixels: "True", UseLayoutRounding: "True", ClipToBounds: "False"})
            if (this._useVirtual.Has(idx)) {
                ; 宏/模块显示区：自适应剩余空间
                ; Epic5 虚拟列表：ListBox + DataTemplate + VirtualizingStackPanel(Recycling)，
                ; 行模板注入 Window.Resources，由 _vl.Init 一次 VL_INIT 填充
                vg := bd.Add("Grid").Name("TabGrid_" idx)
                vg.Cols("*", "Auto")
                ; UseLayoutRounding=False：整棵列表关闭布局取整，改由各卡片 SnapsToDevicePixels 画边。
                ; 取整会让行 Margin(2)/24px 控件在 125% DPI 下按累计偏移不同而 ±1px（展开/折叠/拖拽后
                ; 行距忽大忽小、侧边框断点、备注底边被吞）。关闭后位置为稳定小数，边框仍清晰。
                vg.Add("ListBox").Name("FoldList_" idx).Grid_Column(0).SelectionMode("Single").BorderThickness("0").Background("Transparent")
                    .Tag(tableItem.Symbol)
                    .Margin("0").UseLayoutRounding("False").SnapsToDevicePixels("True").Panel_ZIndex(1)
                    .VirtualizingPanel_IsVirtualizing("True").VirtualizingPanel_VirtualizationMode("Standard")
                    .VirtualizingPanel_CacheLength("2,2").VirtualizingPanel_CacheLengthUnit("Page")
                ; 吸顶折叠头 overlay（sticky header）：滚动时当前模块头钉在列表顶部
                vg.Add("ContentControl").Name("VLSticky_" idx).Grid_Column(0).VerticalAlignment("Top").HorizontalAlignment("Stretch").Visibility("Collapsed").Margin("0").UseLayoutRounding("False").SnapsToDevicePixels("True").Panel_ZIndex(1)
                ; AI 侧栏只在当前页签建：8 个宏页签各带一份是本窗口 XAML 的主要体积，
                ; 而同一时刻只显示一份。其余页签先不建，首次切过去再注入（见 _EnsureAiPanel）。
                if (idx == MainSoftData.TableIndex) {
                    this._BuildAiAssistPanel(vg, idx)
                    this._aiPanels[idx] := true
                }
                vg.Add("Border").Name("AiDragShield_" idx).Grid_Column(0).Grid_ColumnSpan(2)
                    .Background("Transparent").Cursor("SizeWE").Visibility("Collapsed").Panel_ZIndex(20)
                ; 扩展钮叠在滚动条和扩展内容之上（表现 + 点击同一层）
                vg.Add("Button").Name("BtnAiPanel_" idx).Grid_Column(0).Grid_ColumnSpan(2)
                    .HorizontalAlignment("Right").VerticalAlignment("Center")
                    .Panel_ZIndex(10)
                    .Style("{StaticResource RmtAiRailBtn}").Margin(this._AiRailMargin())
                    .Content(Chr(0xE76B)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
                    .ToolTip(GetLang("AI 助手"))
            } else {
                ; 工具页内容已按固定工作台尺寸排版；保留滚轮滚动能力但不显示无意义的细窄滚动条。
                ; 设置页做成固定「设置中心」工作台：外层必须 Disabled（Disabled 才会把视口高度交给内容，
                ; Hidden 仍按无限高度测量），由内容区自带的 ScrollViewer 负责滚动，左侧导航因此保持固定。
                ; 其它说明类页签仍保持 Auto，避免长帮助内容无法发现滚动位置。
                isToolTab := tableItem.ID == "Tool"
                isSettingTab := tableItem.ID == "Setting"
                sv := bd.Add("ScrollViewer").VerticalScrollBarVisibility(isSettingTab ? "Disabled" : (isToolTab ? "Hidden" : "Auto")).HorizontalScrollBarVisibility("Disabled")
                if (isSettingTab) {
                    bd.Padding("0,2,0,2")
                    sv.Add("Grid").Name("Panel_" idx).Margin("0,6,4,10")
                } else
                    sv.Add("StackPanel").Name("Panel_" idx).Margin("8,6,8,10")
            }
        }

        ; ---- 组装窗口 ----
        ; 主界面 TabControl 用 WrapPanel 做 items host：多行排列严格按添加顺序，点击任意行不会重组
        tabStyle := '<Style x:Key="RmtMainTabCtrl" TargetType="TabControl">'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TabControl"><Grid>'
            . '<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            ; 页签条整条声明为「可命中」，不当作窗口标题栏拖动区：窗口标题栏热区是窗口 DIP，
            ; 内容整体被 Viewbox 缩放后可能压到页签条上，那一段会变成拖窗、页签点不动。
            . '<Border Grid.Row="0" Margin="4,0,2,0" CornerRadius="4" BorderThickness="1.5" BorderBrush="{DynamicResource OutlineStroke}" Padding="0,0" SnapsToDevicePixels="True" WindowChrome.IsHitTestVisibleInChrome="True"><WrapPanel IsItemsHost="True"/></Border>'
            . '<Border Grid.Row="1" Background="Transparent"><ContentPresenter ContentSource="SelectedContent"/></Border>'
            . '</Grid></ControlTemplate></Setter.Value></Setter>'
            . '</Style>'
        ; 休眠/暂停激活态按钮样式：跟随主题 Action 色（各主题自动适配），悬停/按下用主题 ActionHover 色，
        ; 不走默认 Button 模板（默认模板悬停会把背景刷成半透明白，导致激活态「无底、白字」看不清）
        stateBtnStyle := '<Style x:Key="StateBtnActive" TargetType="Button">'
            . '<Setter Property="Foreground" Value="{DynamicResource ActionText}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ActionBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ActionStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1.5"/>'
            . '<Setter Property="Padding" Value="10,0"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Margin="0"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Border" Property="Background" Value="{DynamicResource ActionHoverBg}"/>'
            . '<Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True">'
            . '<Setter TargetName="Border" Property="Background" Value="{DynamicResource ActionPressBg}"/>'
            . '<Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter>'
            . '</Style>'
        ; 主窗口默认按钮：hover=ControlBorder，按下=BtnPressBg（略深于 hover）
        defaultBtnStyle := '<Style TargetType="Button">'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource OutlineStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1.5"/>'
            . '<Setter Property="Padding" Value="10,0"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Margin="0"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd") '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter>'
            . '</Style>'
        ; 侧栏按钮别名（与默认按钮交互一致，便于显式引用）
        sidebarBtnStyle := '<Style x:Key="RmtSidebarBtn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"/>'
        ; 图标按钮：透明底 + ControlBorder 悬停 / BtnPressBg 按下
        iconBtnStyle := '<Style x:Key="RmtIconBtn" TargetType="Button">'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter>'
            . '</Style>'
        foldRowStyles := this._BuildFoldRowStyles()
        ; 主窗口页签样式（隐式 Style，只作用于本窗口）：
        ; - 固定每个页签大小（宽 80），页签间用 1px 垂直线分割，仅上 20% ~ 下 20%（高度 60%）显示
        ; - 选中态：整块主题强调色低透明度背景（TabSelBg，各主题自动适配）+ 右上角 Accent 小圆点
        ; - 悬停：ControlBorder（TabItem 无 IsPressed，按下态无法用 Storyboard+DynamicResource，故仅做 hover）
        ; - 圆角：仅第一个页签左侧（4,0,0,4）、最后一个页签右侧（0,4,4,0）适配页签条圆角，其余页签直角
        tabItemStyle := '<Style TargetType="TabItem">'
            . '<Setter Property="Width" Value="80"/>'
            . '<Setter Property="Height" Value="28"/>'
            . '<Setter Property="MinHeight" Value="28"/>'
            . '<Setter Property="MaxHeight" Value="28"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TabItem">'
            . '<Grid Height="28" ClipToBounds="True">'
            . '<Border x:Name="Bd" Background="Transparent" BorderThickness="0" BorderBrush="Transparent" Padding="5,4,5,4" Cursor="Hand" CornerRadius="0">'
            . '<Grid>'
            . '<ContentPresenter ContentSource="Header" TextElement.Foreground="{DynamicResource TextMain}" TextElement.FontSize="14" TextElement.FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '<Ellipse x:Name="SelDot" Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-3,-1,-3" Visibility="Collapsed" IsHitTestVisible="False"/>'
            . '</Grid>'
            . '</Border>'
            . '<Rectangle x:Name="Divider" Width="2" Fill="{DynamicResource ControlBorder}" HorizontalAlignment="Right" VerticalAlignment="Stretch" Margin="0,3,0,3" IsHitTestVisible="False" SnapsToDevicePixels="True" RenderOptions.EdgeMode="Aliased"/>'
            . '</Grid>'
            . '<ControlTemplate.Triggers>'
            . '<MultiTrigger><MultiTrigger.Conditions>'
            . '<Condition Property="IsMouseOver" Value="True"/>'
            . '<Condition Property="IsSelected" Value="False"/>'
            . '</MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</MultiTrigger>'
            . '<Trigger Property="IsSelected" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/>'
            . '<Setter TargetName="SelDot" Property="Visibility" Value="Visible"/>'
            . '</Trigger>'
            . '<MultiTrigger><MultiTrigger.Conditions>'
            . '<Condition Property="IsMouseOver" Value="True"/>'
            . '<Condition Property="IsSelected" Value="True"/>'
            . '</MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</MultiTrigger>'
            . '<Trigger Property="Tag" Value="first">'
            . '<Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/>'
            . '</Trigger>'
            . '<Trigger Property="Tag" Value="last">'
            . '<Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/>'
            . '<Setter TargetName="Divider" Property="Visibility" Value="Collapsed"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter>'
            . '</Style>'
        ; 页签选中背景默认占位（主题应用时由 ApplyWinThemeToXaml 用 Accent 低透明度覆盖）
        tabSelBgRes := '<SolidColorBrush x:Key="TabSelBg" Color="#80FFFFFF"/>'
            . '<SolidColorBrush x:Key="BtnPressBg" Color="#E0CCCCCC"/>'
            . '<SolidColorBrush x:Key="ActionPressBg" Color="#FF106EBE"/>'
            . '<SolidColorBrush x:Key="ListAltBg" Color="#40000000"/>'
            . '<SolidColorBrush x:Key="ListRowAltBg" Color="#FF2A2A2A"/>'
            . '<SolidColorBrush x:Key="ListRowForbidBg" Color="#FFF0E6DC"/>'
            . '<SolidColorBrush x:Key="FoldHeaderBg" Color="#FF333333"/>'
            . '<SolidColorBrush x:Key="FoldAltBg" Color="#FF3A3A3A"/>'
            . '<SolidColorBrush x:Key="FoldDivider" Color="#66999999"/>'
            ; 主界面主要轮廓描边（按钮/页签/模块）：比 InputStroke 更深，随主题由 ApplyWinThemeToXaml 覆盖
            . '<SolidColorBrush x:Key="OutlineStroke" Color="#FF999999"/>'
            . '<sys:Double x:Key="AiChatFontSize">' XAMLHost.ChatBodyFontSize() '</sys:Double>'
            . '<sys:Double x:Key="AiChatFontSizeSmall">' XAMLHost.ChatSmallFontSize() '</sys:Double>'
        this._foldFieldW := 198
        this._foldFrontW := this._foldFieldW + 80
        ; 备注右缘对齐「菜单宏」右分割线(3×80)；前台左缘对齐「定时宏」左分割线(5×80)
        ; 间隙 160，扣掉备注右侧 Margin 8 → 前台左移 152；触发类型列 +5 → 157
        ; 宏行工具列收窄 10、TK 列 +5，Del 右缘左移 5 → 工具栏右移量 155
        ; 备注右缘到前台左缘：备注右侧 Margin 8 + 此前台左移 157
        ; 前台组右侧加了问号钮（24），整组左移 24 以免挤到操作按钮
        this._foldFrontShift := 133
        this._itemToolbarShift := 200
        ; 宏页签无触发键/触发类型：相对原「宏编辑器」列左移，并与模块前台保持固定间距
        this._subMacroEditShift := 210
        resStr := tabStyle . tabItemStyle . tabSelBgRes . stateBtnStyle . defaultBtnStyle . sidebarBtnStyle . iconBtnStyle . foldRowStyles . this._BuildVListTemplates()
        ; 按需注入 AI 侧栏时作为解析上下文的资源副本（见 _EnsureAiPanel）。
        ; 剔除画刷/字号标量：这些键在 Window.Resources 里已被主题与字体设置覆盖，
        ; 包装 Grid 若带着这里的静态默认值，会遮蔽主题值（注入面板配色退回未主题化的旧色）
        this._resInjectStr := RegExReplace(resStr, '<SolidColorBrush\b[^>]*/>', "")
        this._resInjectStr := RegExReplace(this._resInjectStr, '<sys:Double x:Key="[^"]+">[^<]*</sys:Double>', "")
        appStr := main.ToString()
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        tmp := StrReplace(tmp, "%resources%", resStr)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", appStr), "", "")
        ; 首次填充含数百条属性，同步提交需等引擎逐条设完（实测 344ms），
        ; 期间主线程阻塞、窗口无法绘制。改为批量异步投递，不等回执。
        this.ui.asyncUpdate := true
        ; 首帧即定死保存位置：模板 CenterScreen 会让 WPF 强制居中并覆盖后续 WinMove → 先默认位置闪一帧。
        ; 改 Manual + 注入 Left/Top/Width/Height（AHK 逻辑坐标 = WPF DIP，125% DPI 下物理 132,126 已实测吻合，无单位错位）。
        ; LastWinPos 无效或仅含旧坐标时使用新版居中默认尺寸。
        pos := GetLastWinPos()
        startLoc := 'WindowStartupLocation="CenterScreen"'
        ; 主界面默认尺寸按屏幕等比缩放：1920×1080 参考 1400×787。
        ; 更宽的屏幕（横向富余）按高度缩放、更高的屏幕（纵向富余）按宽度缩放，
        ; 即缩放系数 = min(屏幕宽/1920, 屏幕高/1080)；用 DIP 屏幕尺寸计算，物理像素随 DPI 正确。
        dpiScale := A_ScreenDPI / 96.0
        size := GetMainWindowDefaultSize()
        wh := 'Width="' Round(size[1] / dpiScale) '" Height="' Round(size[2] / dpiScale) '"'
        if (pos.Length) {
            ; AHK 进程 DPI aware，WinGetPos/LastWinPos 是物理像素；XAML 注入按 DIP 解释，须换算（实测 125% 屏偏右下 26px）
            ; ponytail: 用 A_ScreenDPI 单值；跨屏不同 DPI 时可能偏差，待真机多屏再按 per-monitor 换算
            scale := A_ScreenDPI / 96.0
            x := Round(pos[1] / scale), y := Round(pos[2] / scale), w := Round(pos[3] / scale), h := Round(pos[4] / scale)
            startLoc := 'WindowStartupLocation="Manual" Left="' x '" Top="' y '"'
            wh := 'Width="' w '" Height="' h '"'
        }
        ; 先填内容再显示：引擎等待初始化和首帧绘制完成，避免主题/列表刷入时抖动
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ' wh '')
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', startLoc)
        ; Viewbox 或窗口非客户区露出的边缘也使用主题底色，避免透明背景呈黑色。
        winEnd := InStr(this.ui.xaml, ">")
        head := StrReplace(SubStr(this.ui.xaml, 1, winEnd), 'Background="Transparent"', 'Background="{DynamicResource BgColor}"')
        this.ui.xaml := head SubStr(this.ui.xaml, winEnd + 1)

        ; ---- 壳级事件（初始 XAML 内，经 eventBindings 绑定） ----
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("Window", "PreviewMouseMove", ObjBindMethod(this, "OnAiSplitMove"))
        this.ui.OnEvent("Window", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnAiSplitEnd"))
        this.ui.OnEvent("BtnWinClose", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("BtnMinimize", "Click", ObjBindMethod(this, "OnMinimizeClick"))
        this.ui.OnEvent("BtnMaximize", "Click", ObjBindMethod(this, "OnMaximizeClick"))
        this.ui.OnEvent("TabControl", "SelectionChanged", ObjBindMethod(this, "OnTabChanged"))
        this.ui.OnEvent("BtnConfig", "Click", (*) => SettingMgrGui.ShowGui())
        this.ui.OnEvent("BtnSuspend", "Click", OnSuspendHotkey)
        this.ui.OnEvent("BtnSuspendActive", "Click", OnSuspendHotkey)
        this.ui.OnEvent("BtnPause", "Click", OnPauseHotKey)
        this.ui.OnEvent("BtnPauseActive", "Click", OnPauseHotKey)
        this.ui.OnEvent("BtnToggleHotkeyHint", "Click", ObjBindMethod(this, "OnToggleHotkeyHint"))
        for t in this._useVirtual {
            ; 这两个控件不属于侧栏，页签骨架里一直在：扩展开关与拖拽遮罩
            this.ui.OnEvent("BtnAiPanel_" t, "Click", ObjBindMethod(this, "OnToggleAiPanel"))
            this.ui.OnEvent("AiDragShield_" t, "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnAiSplitEnd"))
            ; 侧栏内的控件只有建出来的页签才有，绑定跟着建（见 _EnsureAiPanel）
            if (this._aiPanels.Has(t))
                this._BindAiPanel(t)
        }
        this.ui.OnEvent("BtnKill", "Click", OnKillAllMacro)
        this.ui.OnEvent("BtnReload", "Click", MenuReload)
        if (!A_IsCompiled)
            this.ui.OnEvent("BtnGMUI", "Click", (*) => this.ui.Update("Window", "GMUIOpen", ""))
        this.ui.OnEvent("BtnHelp", "Click", (*) => OnOpenRmtDoc())
        this.ui.OnEvent("BtnSave", "Click", OnSaveSetting)

        this._vl := VirtualListHost(this.ui)
        this.LoadLeftBarValues()
        this._startHidden := MainSoftData.HasProp("IsMinStart") && MainSoftData.IsMinStart
        this.ui._startHidden := this._startHidden
        ; ===== 先填充内容（Show 前入队，LoadedHwnd 时一次刷入），填充完再显示，避免空壳闪烁 =====
        try {
            this.PopulateAll()
        } catch as e {
            XamlUiDiag("PopulateAll 异常: " e.Message " @ " e.File ":" e.Line "`n" e.Stack, "MainWin")
        }
        ; 主题资源在 Show 之前入队（与弹窗同一套做法）：首帧就能拿到 BgColor/TextMain，
        ; 不必等 Loaded 之后再刷，避免窗口先露一帧无背景色。
        try ApplyXamlTheme(this.ui, MainSoftData.Theme)
        ; 建窗同样异步：XAML 114KB，同步 SendMessage 需等 daemon 出队处理（实测 244ms）。
        ; 改走共享内存 + PostMessage 后立即返回，句柄等待不变，主线程不再被占用。
        ; 失败时自动回退同步路径。
        this.ui.asyncCreate := true
        this.ui.Show()

        ; 句柄由引擎异步回传（Window.LoadedHwnd）。这里不再 Sleep 轮询等待：
        ; 主线程直接回落到启动链（PluginInit / 热键绑定与引擎建窗并行），
        ; 句柄到达后由 OnWindowLoad 接着做依赖句柄的收尾。
        ; 极快情况下句柄已经就绪，就地补一次，省掉一轮回调。
        if (this.ui.wpfHwnd)
            this._AfterHwndReady()
    }

    ; 句柄可用后的收尾。OnWindowLoad 回调与 BuildAndShow 尾段都会走到，内部去重。
    _AfterHwndReady() {
        if (this.HasOwnProp("_hwndReadyDone") && this._hwndReadyDone)
            return
        this._hwndReadyDone := true
        XamlUiDiag("MainWin hwnd=" this.ui.wpfHwnd, "MainWin")
        ; AI 输入框的 OLE 拖放目标需多个页签各两次同步 IPC（实测 350ms）。
        ; 此时首屏已可见，不必阻塞主线程，推迟到窗口出现后执行。
        try SetTimer(ObjBindMethod(this, "_EnableAiInputFileDrop"), -120)
    }

    ; AI 输入框：启用文件拖放（EnableDropTarget 含 DragOver，OnEvent Drop  alone 不够）
    _EnableAiInputFileDrop() {
        if (!IsObject(this.ui))
            return
        ; 每次 EnableDropTarget 都要在引擎侧建立 OLE 拖放目标，多个页签累计 350ms。
        ; 合并为一批异步投递，主线程不再等待；拖放目标延迟数十毫秒生效，无感知。
        batch := []
        for t in this._useVirtual {
            batch.Push({ ControlName: "AiInput_" t, PropertyName: "EnableDropTarget", Value: "RmtAiFile" })
            batch.Push({ ControlName: "AiInputHost_" t, PropertyName: "EnableDropTarget", Value: "RmtAiFile" })
        }
        if (!batch.Length)
            return
        if (this.ui.HasProp("asyncUpdate") && this.ui.asyncUpdate && this.ui.BatchUpdateAsync(batch))
            return
        for item in batch
            try this.ui.Update(item.ControlName, item.PropertyName, item.Value)
    }

    PopulateAll() {
        ; 页签内容按需构建：启动只建轻量页签，重页签等用户首次切过去再建。
        ; 赞助页要起 QrDecode.exe 解两张二维码图（实测 313ms），启动时根本不显示，这笔钱是白付的。
        this._tabBuilders := Map(
            GetTableIndexByID("Tool"), "BuildToolTab",
            GetTableIndexByID("Setting"), "BuildSettingTab",
            GetTableIndexByID("Help"), "BuildHelpTab",
            GetTableIndexByID("Reward"), "BuildRewardTab",
            GetTableIndexByID("Thank"), "BuildThankTab")
        this._builtTabs := Map()
        this._deferredTabs := Map(GetTableIndexByID("Reward"), true)

        ; 各页签独立构建：任一失败不得阻断后续 RenderTab（否则主界面宏列表空白）
        for idx, fn in this._tabBuilders {
            if (this._deferredTabs.Has(idx) && idx != MainSoftData.TableIndex)
                continue
            this._EnsureTabBuilt(idx)
        }
        ; 惰性渲染：只渲染当前 tab（旧路径全量渲染 7 tab 是启动 1.3s 的主因），切 tab 时由 OnTabChanged 补渲染
        this._renderedTabs := Map()
        cur := MainSoftData.TableIndex
        this._EnsureTabBuilt(cur)
        this._renderedTabs[cur] := true
        this.RenderTab(MySoftData.TableInfo[cur])
        ; 启动不默认选中第一条宏，等用户点选
        ; AI 预置对话改为首次打开侧栏/切到 AI 时惰性注入，避免启动与首展卡顿
    }

    ; 按需构建页签内容（幂等）。未登记构建函数的页签（普通宏表）直接跳过。
    _EnsureTabBuilt(idx) {
        if (!this.HasOwnProp("_builtTabs") || !IsObject(this._builtTabs))
            this._builtTabs := Map()
        if (this._builtTabs.Has(idx))
            return
        this._builtTabs[idx] := true
        if (!this.HasOwnProp("_tabBuilders") || !IsObject(this._tabBuilders) || !this._tabBuilders.Has(idx))
            return
        fn := this._tabBuilders[idx]
        try
            this.%fn%()
        catch as e
            XamlUiDiag(fn " 异常: " e.Message " @ " e.File ":" e.Line, "MainWin")
    }

    ; VL_INIT 重建虚拟行后补刷主题字号（否则新行仍用样式声明 11，比已缩放行偏小）
    RefreshVLFonts() {
        if (!IsObject(this.ui) || this.ui.IsFontScaleSkipped())
            return
        try {
            fs := XAMLHost.GetThemeFontSize()
            this.ui.Update("Window", "ApplyFonts", XAMLHost.BuildApplyFontsPayload(0, fs))
            XAMLHost.SyncChatFontResources(this.ui)
            ; 字号变了行高也跟着变，输入框的最大高度要按新行高重算
            this._aiRowH := Map()
            for t in this._useVirtual
                this._FitAiInput(t)
        } catch {
        }
    }

    OnWindowLoad(state, ctrl, event) {
        ; 引擎要等本回调（以及其它 LoadedHwnd 回调）全部返回后才发 InitialUpdateComplete 揭盖。
        ; 这里只挂一个延迟任务，图标/左栏数值/鼠标开关这类同步 IPC 统统挪到揭盖之后做，
        ; 否则它们的耗时会被原样加到"窗口可见"上（实测 400ms+）。
        try SetTimer(ObjBindMethod(this, "_AfterReveal"), -60)
    }

    ; 揭盖后的首批界面收尾（原 OnWindowLoad 内容）
    _AfterReveal() {
        try {
            ; 任务栏/Alt-Tab 图标：托盘已用 rabit.ico，窗口本身也要显式设置（脚本运行时默认是 AHK 图标）
            ; rabit.ico 已内置 16~128 多尺寸，这里取最大尺寸，Windows 会按任务栏尺寸/DPI 自动缩放到合适大小
            try {
                hIcon := LoadPicture("Images\Soft\rabit.ico", "Icon1 w128 h128", &ImageType := 1)
                if (hIcon)
                    this.ui.Update("Window", "Icon", "HICON:" hIcon)
            }
            ; 首帧已使用配置配色，避免 Loaded 再次应用基础主题造成闪烁。
            this.LoadLeftBarValues()
            ; 主窗绑着 Window/PreviewMouseMove，只为拖 AI 分割条时取 DragCoords。
            ; 默认关掉，按下分割条时再开（见 SetWindowMouseMove）：否则鼠标在窗口里划过
            ; 就是每秒六十来条全量状态回传。侧栏逻辑树的拖拽也复用这同一个开关。
            this.ui.SetWindowMouseMove(false)
            ; 句柄回传（LoadedHwnd）：补做依赖句柄的收尾（AI 输入框拖放目标等）
            this._AfterHwndReady()
        } catch as e {
            XamlUiDiag("MainWin OnWindowLoad err: " e.Message, "MainWin")
        }
        ; VirtualList 在 Loaded 时已按最终视口测量；此处再次 Reset 会重建行并跳动。
    }

    OnWindowClosing(state, ctrl, event) {
        this.HideSideDebugTools()
        this._AiVoiceClose()
        this._AiPersistAllTabs()
        this.closed := true
        OnGuiClose()
        this.ui := ""
    }

    OnCloseClick(state, ctrl, event) {
        ; 主窗口关闭 = 隐藏（应用继续托盘运行），不真正销毁窗口，托盘可恢复
        this._AiVoiceStop()
        this._AiPersistAllTabs()
        this.HideSideDebugTools()
        OnGuiClose()
        try WinHide(this.ui.wpfHwnd)
    }

    OnMinimizeClick(state, ctrl, event) {
        try this.ui.Update("Window", "WindowState", "Minimized")
    }

    OnMaximizeClick(state, ctrl, event) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        maxState := WinGetMinMax("ahk_id " hwnd)
        this.ui.Update("Window", "WindowState", maxState == 1 ? "Normal" : "Maximized")
    }

    ; §11 页签底部 + 按钮：新增模块到列表末尾
    OnTabAddFoldBtnClick(tableItem, state, ctrl, event) {
        OnItemAddFoldBtnClick(tableItem, tableItem.Folds.Length, "")
    }

    OnTabChanged(state, ctrl, event) {
        v := this.ui.Query("TabControl>SelectedIndex")
        if (v == "")
            return
        sel := Integer(v) + 1
        ; §10 页签位置 → TableInfo 下标（隐藏页签后位置与下标不再 1:1）
        idx := (this.HasOwnProp("_tabOrder") && IsObject(this._tabOrder) && sel >= 1 && sel <= this._tabOrder.Length)
            ? this._tabOrder[sel] : sel
        ; TabControl 初始选择与子控件 SelectionChanged 可能在 PopulateAll 尚未创建惰性渲染状态时冒泡。
        ; 此时不应切换页签；待 PopulateAll 完成并建立 _renderedTabs 后再响应后续事件。
        if (!this.HasOwnProp("_renderedTabs") || !IsObject(this._renderedTabs))
            return
        ; ComboBox.SelectionChanged 会冒泡到 TabControl；同页再入不重渲，避免切页/生成行时抖动
        if (idx == MainSoftData.TableIndex && this.HasOwnProp("_renderedTabs") && this._renderedTabs.Has(idx))
            return
        this.HideSideDebugTools()
        MainSoftData.TableIndex := idx
        ; 惰性构建：首次切到某个页签才生成它的内容（启动时只建当前页签）
        this._EnsureTabBuilt(idx)
        if (idx == GetTableIndexByID("Tool"))
            this.RefreshVoiceExtensionButton()
        this._EnsureAiPanel(idx)
        try MainSoftData.TabCtrl._value := idx
        OnTabValueChanged()
        ; 惰性渲染：该 tab 尚未构建过则首次切换时渲染（启动只渲染当前 tab）
        if (!this._renderedTabs.Has(idx)) {
            this._renderedTabs[idx] := true
            this.RenderTab(MySoftData.TableInfo[idx])
        }
        nav := this._pendingMacroNav
        this._pendingMacroNav := ""
        if (IsObject(nav) && nav.tab == idx && nav.idx >= 1) {
            this.SelectSideTreeItem(idx, nav.idx)
        } else {
            this.RefreshSideTree(idx)
        }
        if (this.aiAssistOpen) {
            if (IsObject(this._vl) && this._useVirtual.Has(idx))
                this._vl.SetCompact(idx, true)
            this._EnsureAiSeeded(idx)
        }
    }

    _AddSidebarButtonContent(button, label, glyph) {
        content := button.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
        content.Add("TextBlock").Text(Chr(glyph)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
            .FontSize(14).Margin("0,0,7,0").VerticalAlignment("Center")
        content.Add("TextBlock").Text(GetLang(label)).VerticalAlignment("Center")
    }

    LoadLeftBarValues() {
        this.ui.Update("TxtCurSetting", "Text", MySoftData.CurSettingName)
        ; 休眠/暂停按钮状态：普通态 ↔ 激活态（蓝色背景+红点）；BindUtil 通过 UIControls.*Toggle.Value 写入状态
        UIControls.SuspendToggle := StateBtnAdapter("BtnSuspend", "SuspendActiveGrid", this.ui)
        UIControls.PauseToggle := StateBtnAdapter("BtnPause", "PauseActiveGrid", this.ui)
        UIControls.SuspendToggle.Value := MainSoftData.IsSuspend
        UIControls.PauseToggle.Value := MainSoftData.IsPause
    }

    ; 全局操作右侧展开按钮：切换休眠/暂停/终止所有宏的快捷键提示显隐（默认显示）
    OnToggleHotkeyHint(state, ctrl, event) {
        if (!this.HasOwnProp("_showHotkeyHint"))
            this._showHotkeyHint := true
        this._showHotkeyHint := !this._showHotkeyHint
        vis := this._showHotkeyHint ? "Visible" : "Collapsed"
        this.ui.Update("TxtSuspendKey", "Visibility", vis)
        this.ui.Update("TxtPauseKey", "Visibility", vis)
        this.ui.Update("TxtKillKey", "Visibility", vis)
        this.ui.Update("BtnToggleHotkeyHint", "Content", this._showHotkeyHint ? Chr(0xE70D) : Chr(0xE76C))
    }
#Include MainWindow\SidePanelLayout.ahk
#Include MainWindow\SideMacroEditor.ahk
#Include MainWindow\AiConversationView.ahk
#Include MainWindow\AiMessageMarkup.ahk
#Include MainWindow\AiInput.ahk
#Include MainWindow\AiRequests.ahk
#Include MainWindow\AiSessions.ahk
#Include MainWindow\MacroListLayout.ahk
#Include MainWindow\MacroListRows.ahk
#Include MainWindow\MacroListTemplates.ahk
#Include MainWindow\ToolsPage.ahk
#Include MainWindow\SettingsPage.ahk
#Include MainWindow\SettingsActions.ahk
#Include MainWindow\HelpPage.ahk
#Include MainWindow\SupportPage.ahk
#Include MainWindow\ThanksPage.ahk
}

global MyMainWin := MainWin()
#Include MainWindow\CustomPanelActions.ahk
