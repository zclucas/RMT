#Requires AutoHotkey v2.0

; ============================================================================
; 主窗口 XAML 迁移
; 用 XAMLHost + XAML_Generator 替代原生 Gui() 应用壳。
; 适配器让消费文件对原生控件的 .Value/.Text/.Hwnd/.Focus()/.GetPos()/.Opt()
; 等引用继续工作：
;   GuiAdapter  -> MainSoftData.MyGui
;   TabAdapter  -> MainSoftData.TabCtrl
;   CtrlAdapter -> UIControls.* / MainSoftData.Tool*Ctrl / MainSoftData.BtnSave
; ============================================================================

class CtrlAdapter {
    __New(name, ui, prop := "Text") {
        this._name := name
        this._ui := ui
        this._prop := prop        ; "Text" | "IsChecked" | "SelectedIndex"
    }
    Value {
        get {
            v := this._ui.Query(this._name)
            if (this._prop == "IsChecked")
                return (v == "True")
            return v
        }
        set {
            if (this._prop == "IsChecked")
                this._ui.Update(this._name, "IsChecked", value ? "True" : "False")
            else if (this._prop == "SelectedIndex")
                this._ui.Update(this._name, "SelectedIndex", String(value - 1))
            else
                this._ui.Update(this._name, this._prop, String(value))
        }
    }
    Text {
        get => this._ui.Query(this._name)
        set => this._ui.Update(this._name, "Text", String(value))
    }
    Focus() {
        this._ui.Update(this._name, "Focus", "True")
    }
    Enabled {
        set => this._ui.Update(this._name, "IsEnabled", value ? "True" : "False")
    }
}

class TabAdapter {
    __New(ui, owner := "") {
        this.ui := ui
        this._owner := owner
        this._value := 1
    }
    ; §10 可见页签映射表（TableInfo 下标数组，主窗口构建时按 TabVisibleMap 过滤生成）
    _TabOrder() {
        o := (IsObject(this._owner) && this._owner.HasOwnProp("_tabOrder") && IsObject(this._owner._tabOrder)) ? this._owner._tabOrder : ""
        return (o && o.Length > 0) ? o : ""
    }
    Value {
        get {
            o := this._TabOrder()
            if (!o)
                return this._value
            v := this.ui.Query("TabControl>SelectedIndex")
            if (v == "")
                return this._value
            sel := Integer(v) + 1
            if (sel >= 1 && sel <= o.Length)
                return o[sel]
            return this._value
        }
        set {
            this._value := value
            o := this._TabOrder()
            if (!o) {
                this.ui.Update("TabControl", "SelectedIndex", String(value - 1))
                return
            }
            for i, t in o {
                if (t == value) {
                    this.ui.Update("TabControl", "SelectedIndex", String(i - 1))
                    return
                }
            }
            ; 目标表被隐藏：切到第一个可见页签
            this.ui.Update("TabControl", "SelectedIndex", "0")
        }
    }
    UseTab(i := "") {
        if (i != "")
            this.Value := i
    }
    Move(*) {
    }
    OnEvent(evt, cb) {
        if (evt == "Change")
            this.ui.OnEvent("TabControl", "SelectionChanged", cb)
    }
}

class GuiAdapter {
    __New(ui) {
        this.ui := ui
        this._title := ""
    }
    Hwnd {
        get => this.ui.wpfHwnd
    }
    Title {
        get => this._title
        set {
            this._title := value
            this.ui.Update("Window", "Title", value)
        }
    }
    Show(opts := "") {
        hwnd := this.ui.wpfHwnd
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
            return
        if (opts != "") {
            if (RegExMatch(opts, "i)x(\d+)", &mx) && RegExMatch(opts, "i)y(\d+)", &my)) {
                w := RegExMatch(opts, "i)w(\d+)", &mw) ? Integer(mw[1]) : 1070
                h := RegExMatch(opts, "i)h(\d+)", &mh) ? Integer(mh[1]) : 590
                WinMove(Integer(mx[1]), Integer(my[1]), w, h, hwnd)
            }
        }
        WinShow(hwnd)
        ; 与原生 Gui.Show 语义一致：显示即激活（托盘「显示窗口」/最小化启动恢复都走这里）
        try WinActivate(hwnd)
    }
    Hide() {
        WinHide(this.ui.wpfHwnd)
    }
    Opt(opt) {
        if (InStr(opt, "AlwaysOnTop"))
            this.ui.Update("Window", "Topmost", SubStr(opt, 1, 1) == "+" ? "True" : "False")
    }
    GetPos(&x, &y, &w, &h) {
        WinGetPos(&x, &y, &w, &h, this.ui.wpfHwnd)
    }
    Flash() {
        DllCall("FlashWindow", "Ptr", this.ui.wpfHwnd, "Int", 1)
    }
    Submit() {
        return ""   ; 值已由事件/回读同步到 MainSoftData，此处 no-op
    }
}

; 休眠/暂停 状态按钮适配器：激活时显示「蓝色背景+右上角红点」按钮，否则显示普通按钮
; BindUtil 通过 UIControls.SuspendToggle/PauseToggle.Value 写入状态，与本类对接
class StateBtnAdapter {
    __New(normalName, activeName, ui) {
        this._normal := normalName
        this._active := activeName
        this._ui := ui
    }
    Value {
        get => ""
        set {
            this._ui.Update(this._normal, "Visibility", value ? "Collapsed" : "Visible")
            this._ui.Update(this._active, "Visibility", value ? "Visible" : "Collapsed")
        }
    }
}

; ============================================================================
; MainWin — 主窗口壳 + 静态页 + 宏列表渲染
; ============================================================================
class MainWin {
    __New() {
        this.ui := ""
        this.closed := false
        this._linkCounter := 0
        this._linkQueue := []
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
        this.aiSplitWatch := ObjBindMethod(this, "_PollAiSplit")
        this._aiAnim := false
        this._aiAnimFrom := 0
        this._aiAnimTo := 0
        this._aiAnimT0 := 0
        this._aiAnimW := 0
        this.aiAnimTick := ObjBindMethod(this, "_TickAiPanelAnim")
        this._aiFitTab := 0
        this._aiPendingCaret := Map()
        this.aiFitTick := ObjBindMethod(this, "_FitAiInputCur")
        this.aiInnerCur := this.aiPanelW
        this.aiInnerFrom := 0
        this.aiInnerTo := 0
        this.aiInnerT0 := 0
        this.aiInnerOn := false
        this.aiInnerTick := ObjBindMethod(this, "_TickAiInnerW")
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
        this._aiRec := Map()         ; 页签 → 录音中
        this._aiSttTab := 0
        this.aiSttTick := ObjBindMethod(this, "_AiPollStt")
        this._sideTreeSel := Map()
        this._sideTreeCmds := Map()
        this._sideTreeBound := Map()
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
        this._aiInputWide := Map()
        this._aiInputBoxW := Map()
        this._pendingMacroNav := ""
    }

    ; ---- 扩展面板尺寸（可手动改）----
    ; 默认宽度：首次展开 / 未拖过时的宽度
    _AiPanelDefaultW() {
        return 380
    }
    ; 最小宽度：再小选项和指令行会挤变形
    _AiPanelMinW() {
        return 260
    }
    ; 最大宽度：再大会过度挤压左侧宏列表
    _AiPanelMaxW() {
        return 490
    }
    ; 左边框拖拽热区宽度
    _AiPanelSplitW() {
        return 6
    }
    ; 扩展钮默认宽度（窄）；hover 展开到 _AiRailHoverW
    _AiRailW() {
        return 8
    }
    ; 扩展钮 hover 宽度
    _AiRailHoverW() {
        return 18
    }
    ; 逻辑树 / AI助手 选项宽度（与顶部页签一致）
    _AiTabW() {
        return 80
    }
    ; 左侧宏行/模块头组间距下限（面板拉最宽、左侧最窄时）
    _AiPanelGapMin() {
        return 4
    }
    ; 拖拽时左侧列表至少保留的宽度
    _AiListMinW() {
        return 420
    }
    ; 展开/收起动画时长（毫秒）
    _AiPanelAnimMs() {
        return 220
    }
    ; 对话输入框外框高度：与 AI 设置 CtrlH 一致
    _AiInputLineH() {
        return AiSettingGui.CtrlH
    }
    _AiInputRadius() {
        return 3
    }
    ; 对话区字号走 DynamicResource，避开 ScaleFontSize/ApplyFonts 的主题下限（声明 12 会被抬成 15）
    _AiChatBodyFontSize() {
        return "{DynamicResource AiChatFontSize}"
    }
    _AiChatSmallFontSize() {
        return "{DynamicResource AiChatFontSizeSmall}"
    }
    _AiChatFontFamily() {
        return (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
            ? MainSoftData.FontType : "微软雅黑"
    }
    ; 多行时每增一行的行距（在单行高度上叠加）
    _AiInputExtraLineH() {
        return 16
    }
    ; 拖拽调宽时对话框宽度跟随的过渡时长
    _AiInnerAnimMs() {
        return 160
    }
    ; 对话输入框最多显示行数，超出出滚动条
    _AiInputMaxLines() {
        return 10
    }
    _AiUserPreviewLines() {
        return 3.5
    }
    _AiUserPreviewLineH() {
        return Max(18, Integer(XAMLHost.ChatBodyFontSize()) + 6)
    }
    _AiUserPreviewH() {
        pad := Integer(AiSettingGui.ContentPadL)
        return Round(this._AiUserPreviewLineH() * this._AiUserPreviewLines() + pad * 2)
    }
    _AiUserNeedsClip(text) {
        raw := this._AiNormalizeNewlines(text, false)
        lines := StrSplit(raw, "`n")
        if (lines.Length > 3)
            return true
        for line in lines {
            if (StrLen(line) > 28)
                return true
        }
        return false
    }

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
    _RmtBtnInteractionTriggers(bd := "Bd") {
        return '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="' bd '" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="' bd '" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True">'
            . '<Setter TargetName="' bd '" Property="Background" Value="{DynamicResource BtnPressBg}"/>'
            . '<Setter TargetName="' bd '" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
    }

    BuildAndShow() {
        this._InitUseVirtual()
        if (IsSet(MainSoftData) && MainSoftData.HasProp("AiPanelWidth")) {
            savedW := Integer(MainSoftData.AiPanelWidth)
            if (savedW > 0)
                this.aiPanelW := this._ClampAiPanelW(savedW)
            this.aiInnerCur := this.aiPanelW
        }
        ; 动态表集合：配置持久化的 TableIndex 可能越界（表已删/表数变化），钳制到有效范围
        if (MainSoftData.TableIndex < 1 || MainSoftData.TableIndex > MySoftData.TableInfo.Length)
            MainSoftData.TableIndex := 1
        this.closed := false
        title := "RMTv" RMT_VERSION
        titleHeight := "30"

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
        leftTop.Add("Button").Name("BtnConfig").Content(GetLang("配置管理")).Height(33).MinHeight(33).Margin("0,3,0,2").Style("{StaticResource RmtSidebarBtn}")
        leftTop.Add("Rectangle").Height(1).Margin("2,6,2,6").Fill("{DynamicResource ControlBorder}").Stretch("Fill")
        ; 全局操作标题 + 右侧展开按钮（控制休眠/暂停/终止所有宏的快捷键提示显隐，默认显示）
        globalOps := leftTop.Add("Grid").Margin("4,0,0,4")
        globalOps.Add("TextBlock").Text(GetLang("全局操作")).FontWeight("Bold").FontSize(11).Opacity("0.7").VerticalAlignment("Center").HorizontalAlignment("Left")
        globalOps.Add("Button").Name("BtnToggleHotkeyHint").Content(Chr(0xE70D)).Width(24).Height(24).MinHeight(24).Margin("0,0,2,0").HorizontalAlignment("Right").VerticalAlignment("Center").FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).Style("{StaticResource RmtIconBtn}")
        ; 休眠按钮：激活（休眠中）时切换为主题 Action 色背景 + 右上角白点
        suspendGrid := leftTop.Add("Grid").Margin("2,0,0,0")
        suspendGrid.Add("Button").Name("BtnSuspend").Content(GetLang("休眠")).Height(33).MinHeight(33).Style("{StaticResource RmtSidebarBtn}")
        susGridAct := suspendGrid.Add("Grid").Name("SuspendActiveGrid").Visibility("Collapsed")
        susGridAct.Add("Button").Name("BtnSuspendActive").Content(GetLang("休眠")).Height(33).MinHeight(33).Style("{StaticResource StateBtnActive}")
        susGridAct.Add("Ellipse").Name("SuspendDot").Width(8).Height(8).Fill("#FFFFFFFF").HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").IsHitTestVisible("False")
        leftTop.Add("TextBlock").Name("TxtSuspendKey").Text(FormatHotkeyDisplay(MainSoftData.SuspendHotkey)).Opacity("0.6").FontSize(11).Margin("0,0,6,0").HorizontalAlignment("Right").TextAlignment("Right")
        ; 暂停按钮：激活（暂停中）时切换为主题 Action 色背景 + 右上角白点
        pauseGrid := leftTop.Add("Grid").Margin("2,8,0,0")
        pauseGrid.Add("Button").Name("BtnPause").Content(GetLang("暂停")).Height(33).MinHeight(33).Style("{StaticResource RmtSidebarBtn}")
        pauGridAct := pauseGrid.Add("Grid").Name("PauseActiveGrid").Visibility("Collapsed")
        pauGridAct.Add("Button").Name("BtnPauseActive").Content(GetLang("暂停")).Height(33).MinHeight(33).Style("{StaticResource StateBtnActive}")
        pauGridAct.Add("Ellipse").Name("PauseDot").Width(8).Height(8).Fill("#FFFFFFFF").HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").IsHitTestVisible("False")
        leftTop.Add("TextBlock").Name("TxtPauseKey").Text(FormatHotkeyDisplay(MainSoftData.PauseHotkey)).Opacity("0.6").FontSize(11).Margin("0,0,6,0").HorizontalAlignment("Right").TextAlignment("Right")
        leftTop.Add("Button").Name("BtnKill").Content(GetLang("终止所有宏")).Height(33).MinHeight(33).Margin("0,8,0,0").Style("{StaticResource RmtSidebarBtn}")
        leftTop.Add("TextBlock").Name("TxtKillKey").Text(FormatHotkeyDisplay(MainSoftData.KillMacroHotkey)).Opacity("0.6").FontSize(11).Margin("0,0,6,0").HorizontalAlignment("Right").TextAlignment("Right")
        leftTop.Add("Button").Name("BtnReload").Content(GetLang("重启")).Height(33).MinHeight(33).Margin("0,8,0,0").Style("{StaticResource RmtSidebarBtn}")
        leftBottom := left.Add("StackPanel").Grid_Row(1).VerticalAlignment("Bottom")
        leftBottom.Add("Button").Name("BtnHelp").Content(GetLang("RMT文档")).Height(28).MinHeight(28).Margin("0,2,0,2")
        leftBottom.Add("Button").Name("BtnSave").Content(GetLang("应用并保存")).Height(36).MinHeight(36).Margin("0,2,0,0").FontWeight("Bold")

        ; ---- 右侧 TabControl ----
        right := main.Add("Grid").Grid_Row(1).Grid_Column(1).Margin("0,2,2,4")
        ; §10 显示页签：先按可见性过滤生成 _tabOrder（TableInfo 下标数组），页签位置 ↔ 表下标经 TabAdapter/OnTabChanged 映射
        this._tabOrder := []
        loop MySoftData.TableInfo.Length {
            if (IsTabVisible(MySoftData.TableInfo[A_Index]))
                this._tabOrder.Push(A_Index)
        }
        initSel := 0
        for i, t in this._tabOrder {
            if (t == MainSoftData.TableIndex) {
                initSel := i - 1
                break
            }
        }
        if (initSel == 0 && this._tabOrder.Length >= 1) {
            ; 当前表被隐藏 → 落到第一个可见页签，并同步身份（避免保存时持久化隐藏表 ID）
            MainSoftData.TableIndex := this._tabOrder[1]
            MainSoftData.CurTableID := MySoftData.TableInfo[this._tabOrder[1]].ID
        }
        tab := right.Add("TabControl").Name("TabControl").Style("{StaticResource RmtMainTabCtrl}").Background("{DynamicResource BgColor}").SelectedIndex(String(initSel))
        loop this._tabOrder.Length {
            pos := A_Index
            idx := this._tabOrder[pos]
            tableItem := MySoftData.TableInfo[idx]
            tabItem := tab.Add("TabItem").Header(GetLang(tableItem.Name))
            ; 首个/末个页签打 Tag，模板按 Tag 适配圆角（首个左圆角、末个右圆角），末个同时隐藏分割线
            if (pos == 1)
                tabItem.Tag("first")
            else if (pos == this._tabOrder.Length)
                tabItem.Tag("last")
            ; 页签内容区统一外层边框；上边距 -1 与页签条下边框重叠，避免双线且与页签条等粗
            bd := tabItem.Add("Border").BorderThickness("1.5").BorderBrush("{DynamicResource OutlineStroke}").CornerRadius("4").Margin("4,-1,2,2").Padding("2,2,0,2")
            bd.Apply({SnapsToDevicePixels: "True", UseLayoutRounding: "False", ClipToBounds: "False"})
            if (this._useVirtual.Has(idx)) {
                ; 宏/模块显示区：自适应剩余空间
                ; Epic5 虚拟列表：ListBox + DataTemplate + VirtualizingStackPanel(Recycling)，
                ; 行模板注入 Window.Resources，由 _vl.Init 一次 VL_INIT 填充
                vg := bd.Add("Grid")
                vg.Cols("*", "Auto")
                ; UseLayoutRounding=False：整棵列表关闭布局取整，改由各卡片 SnapsToDevicePixels 画边。
                ; 取整会让行 Margin(2)/24px 控件在 125% DPI 下按累计偏移不同而 ±1px（展开/折叠/拖拽后
                ; 行距忽大忽小、侧边框断点、备注底边被吞）。关闭后位置为稳定小数，边框仍清晰。
                vg.Add("ListBox").Name("FoldList_" idx).Grid_Column(0).SelectionMode("Single").BorderThickness("0").Background("Transparent")
                    .Margin("0").UseLayoutRounding("False").SnapsToDevicePixels("True").Panel_ZIndex(1)
                    .VirtualizingPanel_IsVirtualizing("True").VirtualizingPanel_VirtualizationMode("Standard")
                    .VirtualizingPanel_CacheLength("2,2").VirtualizingPanel_CacheLengthUnit("Page")
                ; 吸顶折叠头 overlay（sticky header）：滚动时当前模块头钉在列表顶部
                vg.Add("ContentControl").Name("VLSticky_" idx).Grid_Column(0).VerticalAlignment("Top").HorizontalAlignment("Stretch").Visibility("Collapsed").Margin("0").UseLayoutRounding("False").SnapsToDevicePixels("True").Panel_ZIndex(1)
                this._BuildAiAssistPanel(vg, idx)
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
                ; 工具/设置/帮助/赞助/感谢：ScrollViewer 包在统一内容边框内
                sv := bd.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
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
            . '<Border Grid.Row="0" Margin="4,0,2,0" CornerRadius="4" BorderThickness="1.5" BorderBrush="{DynamicResource OutlineStroke}" Padding="0,0" SnapsToDevicePixels="True"><WrapPanel IsItemsHost="True"/></Border>'
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
        this._foldFrontShift := 157
        this._itemToolbarShift := 200
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        tmp := StrReplace(tmp, "%resources%", tabStyle . tabItemStyle . tabSelBgRes . stateBtnStyle . defaultBtnStyle . sidebarBtnStyle . iconBtnStyle . foldRowStyles . this._BuildVListTemplates())
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        ; 首帧即定死保存位置：模板 CenterScreen 会让 WPF 强制居中并覆盖后续 WinMove → 先默认位置闪一帧。
        ; 改 Manual + 注入 Left/Top/Width/Height（AHK 逻辑坐标 = WPF DIP，125% DPI 下物理 132,126 已实测吻合，无单位错位）。
        ; LastWinPos 无效时保持 CenterScreen 1070×590 居中默认。
        pos := GetLastWinPos()
        startLoc := 'WindowStartupLocation="CenterScreen"'
        ; 主界面默认尺寸按屏幕等比缩放：1920×1080 参考 1400×787。
        ; 更宽的屏幕（横向富余）按高度缩放、更高的屏幕（纵向富余）按宽度缩放，
        ; 即缩放系数 = min(屏幕宽/1920, 屏幕高/1080)；用 DIP 屏幕尺寸计算，物理像素随 DPI 正确。
        dpiScale := DllCall("GetDpiForSystem", "UInt") / 96.0
        dipSW := A_ScreenWidth / dpiScale
        dipSH := A_ScreenHeight / dpiScale
        fs := Min(dipSW / 1920, dipSH / 1080)
        wh := 'Width="' Round(1400 * fs) '" Height="' Round(787 * fs) '"'
        if (pos.Length) {
            ; AHK 进程 DPI aware，WinGetPos/LastWinPos 是物理像素；XAML 注入按 DIP 解释，须换算（实测 125% 屏偏右下 26px）
            ; ponytail: 用 GetDpiForSystem 单值；跨屏不同 DPI 时可能偏差，待真机多屏再按 per-monitor 换算
            scale := DllCall("GetDpiForSystem", "UInt") / 96.0
            x := Round(pos[1] / scale), y := Round(pos[2] / scale), w := Round(pos[3] / scale), h := Round(pos[4] / scale)
            startLoc := 'WindowStartupLocation="Manual" Left="' x '" Top="' y '"'
            wh := 'Width="' w '" Height="' h '"'
        }
        ; 先填内容再显示：Opacity=0 走引擎离屏揭盖，避免空壳→主题/列表刷入时抖动
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ' wh ' Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', startLoc)

        ; ---- 壳级事件（初始 XAML 内，经 eventBindings 绑定） ----
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("Window", "Revealed", ObjBindMethod(this, "OnWindowRevealed"))
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
            this.ui.OnEvent("BtnAiPanel_" t, "Click", ObjBindMethod(this, "OnToggleAiPanel"))
            this.ui.OnEvent("AiSplit_" t, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnAiSplitStart"))
            this.ui.OnEvent("AiDragShield_" t, "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnAiSplitEnd"))
            this.ui.OnEvent("BtnSideModeTree_" t, "Click", ObjBindMethod(this, "OnSidePanelMode", 1))
            this.ui.OnEvent("BtnSideModeAi_" t, "Click", ObjBindMethod(this, "OnSidePanelMode", 2))
            this.ui.OnEvent("BtnSideToolsToggle_" t, "Click", ObjBindMethod(this, "OnSideToolsToggle"))
            this.ui.OnEvent("AiInput_" t, "TextChanged", ObjBindMethod(this, "OnAiInputChanged", t))
            this.ui.OnEvent("AiInput_" t, "PreviewKeyDown:Return", ObjBindMethod(this, "OnAiInputEnter", t))
            this.ui.OnEvent("AiInput_" t, "PreviewKeyDown:V", ObjBindMethod(this, "OnAiInputPasteKey", t))
            this.ui.OnEvent("AiInput_" t, "FileDrop", ObjBindMethod(this, "OnAiInputFileDrop", t))
            this.ui.OnEvent("AiInput_" t, "Drop", ObjBindMethod(this, "OnAiInputFileDrop", t))
            this.ui.OnEvent("AiInputHost_" t, "FileDrop", ObjBindMethod(this, "OnAiInputFileDrop", t))
            this.ui.OnEvent("AiInputHost_" t, "Drop", ObjBindMethod(this, "OnAiInputFileDrop", t))
            this.ui.OnEvent("AiSend_" t, "Click", ObjBindMethod(this, "OnAiSendClick", t))
            this.ui.OnEvent("AiMic_" t, "Click", ObjBindMethod(this, "OnAiMicClick", t))
            this.ui.OnEvent("SideAiToolHistory_" t, "Click", ObjBindMethod(this, "OnSideAiToolHistory", t))
            this.ui.OnEvent("SideAiToolSettings_" t, "Click", ObjBindMethod(this, "OnSideAiToolSettings", t))
            this.ui.OnEvent("SideAiToolTop_" t, "Click", ObjBindMethod(this, "OnSideToolTop", t))
            this._BindSideTree(t)
        }
        this.ui.OnEvent("BtnKill", "Click", OnKillAllMacro)
        this.ui.OnEvent("BtnReload", "Click", MenuReload)
        this.ui.OnEvent("BtnHelp", "Click", (*) => Run(A_WorkingDir "\index.html"))
        this.ui.OnEvent("BtnSave", "Click", OnSaveSetting)

        this._vl := VirtualListHost(this.ui)
        this.LoadLeftBarValues()
        this._startHidden := MainSoftData.HasProp("IsMinStart") && MainSoftData.IsMinStart
        this.ui._skipAutoReveal := this._startHidden
        ; ===== 先填充内容（Show 前入队，LoadedHwnd 时一次刷入），填充完再显示，避免空壳闪烁 =====
        try {
            this.PopulateAll()
        } catch {
        }
        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.wpfHwnd) {
                gotHwnd := true
                XamlUiDiag("MainWin hwnd=" this.ui.wpfHwnd, "MainWin")
                this._EnableAiInputFileDrop()
                break
            }
            Sleep(50)
        }
    }

    ; AI 输入框：启用文件拖放（EnableDropTarget 含 DragOver，OnEvent Drop  alone 不够）
    _EnableAiInputFileDrop() {
        if (!IsObject(this.ui))
            return
        for t in this._useVirtual {
            try this.ui.Update("AiInput_" t, "EnableDropTarget", "RmtAiFile")
            try this.ui.Update("AiInputHost_" t, "EnableDropTarget", "RmtAiFile")
        }
    }

    PopulateAll() {
        this.BuildToolTab()
        this.BuildSettingTab()
        this.BuildHelpTab()
        this.BuildRewardTab()
        this.BuildThankTab()
        ; 惰性渲染：只渲染当前 tab（旧路径全量渲染 7 tab 是启动 1.3s 的主因），切 tab 时由 OnTabChanged 补渲染
        this._renderedTabs := Map()
        cur := MainSoftData.TableIndex
        this._renderedTabs[cur] := true
        this.RenderTab(MySoftData.TableInfo[cur])
        ; 启动不默认选中第一条宏，等用户点选
        ; AI 预置对话改为首次打开侧栏/切到 AI 时惰性注入，避免启动与首展卡顿
    }

    ; VL_INIT 重建虚拟行后补刷主题字号（否则新行仍用样式声明 11，比已缩放行偏小）
    RefreshVLFonts() {
        if (!IsObject(this.ui) || this.ui.IsFontScaleSkipped())
            return
        try {
            fs := XAMLHost.GetThemeFontSize()
            this.ui.Update("Window", "ApplyFonts", XAMLHost.BuildApplyFontsPayload(0, fs))
            XAMLHost.SyncChatFontResources(this.ui)
        } catch {
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            ; 任务栏/Alt-Tab 图标：托盘已用 rabit.ico，窗口本身也要显式设置（脚本运行时默认是 AHK 图标）
            ; rabit.ico 已内置 16~128 多尺寸，这里取最大尺寸，Windows 会按任务栏尺寸/DPI 自动缩放到合适大小
            try {
                hIcon := LoadPicture("Images\Soft\rabit.ico", "Icon1 w128 h128", &ImageType := 1)
                if (hIcon)
                    this.ui.Update("Window", "Icon", "HICON:" hIcon)
            }
            ApplyXamlTheme(this.ui, MainSoftData.Theme)
            this.LoadLeftBarValues()
        } catch as e {
            XamlUiDiag("MainWin OnWindowLoad err: " e.Message, "MainWin")
        }
        ; 最小化启动：保持隐藏，不揭盖
        if (this.HasOwnProp("_startHidden") && this._startHidden)
            return
        try this.ui.Update("Window", "Opacity", "1")
        ; 主题/揭盖后再走折叠同款 Reset，避免首帧在视口未定时量出的底边/行距
        SetTimer(ObjBindMethod(this, "_RelayoutCurrentVL"), -1)
    }

    _RelayoutCurrentVL() {
        try {
            if (!IsObject(this._vl) || !IsObject(this._useVirtual))
                return
            cur := MainSoftData.TableIndex
            if (this._useVirtual.Has(cur))
                this._vl.Relayout(cur)
        }
    }

    OnWindowRevealed(state, ctrl, event) {
        try WinActivate("ahk_id " this.ui.wpfHwnd)
        this._RelayoutCurrentVL()
    }

    OnWindowClosing(state, ctrl, event) {
        this._AiPersistAllTabs()
        this.closed := true
        OnGuiClose()
        this.ui := ""
    }

    OnCloseClick(state, ctrl, event) {
        ; 主窗口关闭 = 隐藏（应用继续托盘运行），不真正销毁窗口，托盘可恢复
        this._AiPersistAllTabs()
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
        ; ComboBox.SelectionChanged 会冒泡到 TabControl；同页再入不重渲，避免切页/生成行时抖动
        if (idx == MainSoftData.TableIndex && this.HasOwnProp("_renderedTabs") && this._renderedTabs.Has(idx))
            return
        MainSoftData.TableIndex := idx
        if (idx >= 1 && idx <= MySoftData.TableInfo.Length)
            MainSoftData.CurTableID := MySoftData.TableInfo[idx].ID
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

    OnToggleAiPanel(state, ctrl, event) {
        this.aiAssistOpen := !this.aiAssistOpen
        this._ApplyAiPanelUi()
    }

    _ApplyAiPanelGlyph() {
        glyph := this.aiAssistOpen ? Chr(0xE76C) : Chr(0xE76B)
        for t in this._useVirtual {
            try this.ui.Update("BtnAiPanel_" t, "Content", glyph)
            try this.ui.Update("BtnAiPanel_" t, "Margin", this._AiRailMargin())
        }
    }

    _AiRailMargin() {
        ; 往右叠 2px，让钮的右边框压在内容框 1.5px 右边框上（一条线，不留缝）
        return "0,0,-2,0"
    }

    _ListScrollMargin(open) {
        return "0"
    }

    _ApplyListScrollMargin(open) {
        m := this._ListScrollMargin(open)
        for t in this._useVirtual
            try this.ui.Update("FoldList_" t, "Margin", m)
    }

    _ApplyAiPanelUi() {
        this._ApplyAiPanelGlyph()
        opening := this.aiAssistOpen
        ; 先开启动画，重活延后，避免首次展开卡顿
        from := this._aiAnim ? this._aiAnimW : (opening ? 0 : this.aiPanelW)
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
            this._ApplyListScrollMargin(false)
            t0 := MainSoftData.TableIndex
            if (IsObject(this._vl) && this._useVirtual.Has(t0))
                this._vl.SetCompact(t0, false)
        }
    }

    _StartAiPanelAnim(from, to) {
        this._StopAiInnerW()
        innerW := to > 0 ? to : this.aiPanelW
        this.aiInnerCur := innerW
        this._aiAnim := true
        this._aiAnimFrom := from
        this._aiAnimTo := to
        this._aiAnimT0 := A_TickCount
        this._aiAnimW := from
        for t in this._useVirtual {
            try this.ui.Update("AiWrap_" t, "MinWidth", "0")
            try this.ui.Update("AiWrap_" t, "Width", String(from))
            try this.ui.Update("AiWrap_" t, "Visibility", "Visible")
            try this.ui.Update("AiInner_" t, "MinWidth", "0")
            try this.ui.Update("AiInner_" t, "Width", String(innerW))
            try this.ui.Update("AiInner_" t, "HorizontalAlignment", "Right")
        }
        SetTimer(this.aiAnimTick, 16)
    }

    _TickAiPanelAnim() {
        if (!this._aiAnim)
            return
        ms := this._AiPanelAnimMs()
        if (ms < 1)
            ms := 1
        p := (A_TickCount - this._aiAnimT0) / ms
        if (p >= 1)
            p := 1
        ease := 1 - (1 - p) ** 3
        w := this._aiAnimFrom + (this._aiAnimTo - this._aiAnimFrom) * ease
        this._aiAnimW := w
        for t in this._useVirtual {
            try this.ui.Update("AiWrap_" t, "Width", String(Round(w)))
        }
        if (p < 1)
            return
        SetTimer(this.aiAnimTick, 0)
        this._aiAnim := false
        if (this._aiAnimTo <= 0) {
            for t in this._useVirtual {
                try this.ui.Update("AiWrap_" t, "Visibility", "Collapsed")
                try this.ui.Update("AiWrap_" t, "Width", String(this.aiPanelW))
                try this.ui.Update("AiWrap_" t, "MinWidth", String(this._AiPanelMinW()))
            }
            return
        }
        for t in this._useVirtual {
            try this.ui.Update("AiWrap_" t, "Width", String(this.aiPanelW))
            try this.ui.Update("AiWrap_" t, "MinWidth", String(this._AiPanelMinW()))
            try this.ui.Update("AiInner_" t, "Width", String(this.aiPanelW))
            try this.ui.Update("AiInner_" t, "MinWidth", String(this._AiPanelMinW()))
        }
    }

    OnAiSplitStart(state, ctrl, event) {
        if (!this.aiAssistOpen)
            return
        this._aiDrag := true
        this._aiDragStartW := this.aiPanelW
        this._aiDragStartX := ""
        this._ShowAiDragShield(true)
        try this.ui.Update("Window", "Cursor", "SizeWE")
        SetTimer(this.aiSplitWatch, 50)
    }

    OnAiSplitMove(state, ctrl, event) {
        if (!this._aiDrag)
            return
        if (!GetKeyState("LButton", "P")) {
            this.OnAiSplitEnd(state, ctrl, event)
            return
        }
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
        SetTimer(this.aiSplitWatch, 0)
        this._ShowAiDragShield(false)
        try this.ui.Update("Window", "Cursor", "Arrow")
        if (IsSet(MainSoftData))
            MainSoftData.AiPanelWidth := this.aiPanelW
    }

    _PollAiSplit() {
        if (!this._aiDrag)
            return
        if (!GetKeyState("LButton", "P"))
            this.OnAiSplitEnd()
    }

    _ShowAiDragShield(on) {
        vis := on ? "Visible" : "Collapsed"
        for t in this._useVirtual
            try this.ui.Update("AiDragShield_" t, "Visibility", vis)
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

    _ClampAiPanelW(w) {
        w := Integer(w)
        minW := this._AiPanelMinW()
        maxW := this._AiPanelMaxW()
        try {
            t := 0
            for idx in this._useVirtual {
                t := idx
                break
            }
            if (t) {
                listW := Integer(this.ui.Query("FoldList_" t ">ActualWidth"))
                avail := listW + this.aiPanelW - this._AiListMinW()
                if (avail < maxW)
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
        for t in this._useVirtual {
            try this.ui.Update("AiWrap_" t, "Width", String(w))
        }
        this._StartAiInnerW(this.aiInnerCur, w)
    }

    _StopAiInnerW() {
        if (this.aiInnerOn)
            SetTimer(this.aiInnerTick, 0)
        this.aiInnerOn := false
    }

    _StartAiInnerW(from, to) {
        from := Integer(from)
        to := Integer(to)
        if (from == to) {
            this._StopAiInnerW()
            this.aiInnerCur := to
            this._ApplyAiInnerW(to)
            return
        }
        this.aiInnerOn := true
        this.aiInnerFrom := from
        this.aiInnerTo := to
        this.aiInnerT0 := A_TickCount
        this.aiInnerCur := from
        this._ApplyAiInnerW(from)
        SetTimer(this.aiInnerTick, 16)
    }

    _TickAiInnerW() {
        if (!this.aiInnerOn)
            return
        ms := this._AiInnerAnimMs()
        if (ms < 1)
            ms := 1
        p := (A_TickCount - this.aiInnerT0) / ms
        if (p >= 1)
            p := 1
        ease := 1 - (1 - p) ** 3
        w := this.aiInnerFrom + (this.aiInnerTo - this.aiInnerFrom) * ease
        this.aiInnerCur := w
        this._ApplyAiInnerW(Round(w))
        if (p < 1)
            return
        this._StopAiInnerW()
        this.aiInnerCur := this.aiInnerTo
        this._ApplyAiInnerW(this.aiInnerTo)
    }

    _ApplyAiInnerW(w) {
        for t in this._useVirtual {
            try this.ui.Update("AiInner_" t, "Width", String(w))
            try this.ui.Update("AiInner_" t, "HorizontalAlignment", "Right")
        }
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

    OnSideAiToolSettings(t, *) {
        AiSettingGui.ShowGui()
    }

    _BuildSideTreeContextMenus(host) {
        scrollStyle := IsObject(MyMacroGui) ? MyMacroGui._ContextMenuScrollStyle() : ""
        subStyle := IsObject(MyMacroGui) ? MyMacroGui._MenuItemSubmenuStyle() : ""
        treeCtxHost := host.Add("Border").Name("SideTreeCtxHost").Width("0").Height("0").Visibility("Collapsed")
        treeCtx := treeCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("SideTreeCtxMenu")
            .MinWidth("180").Placement("MousePoint")
        if (scrollStyle != "")
            treeCtx.InjectResources(scrollStyle)
        if (subStyle != "")
            treeCtx.InjectResources(subStyle)
        if (IsObject(MyMacroGui))
            MyMacroGui._ApplyCtxMenuTheme(treeCtx)
        else
            treeCtx.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        treeCtx.FontSize(String(XAMLHost.PopupFontSizeDeclared()))
            .FontFamily((MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑")
        ; 编辑 | 复制、粘贴 | 上插、下插 | 跳过、调试起点 | 删除
        treeCtx.Add("MenuItem").Name("SideMenuEditCmd").Header(GetLang("编辑"))
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("SideMenuCopyCmd").Header(GetLang("复制"))
        treeCtx.Add("MenuItem").Name("SideMenuPasteCmd").Header(GetLang("粘贴"))
        treeCtx.Add("Separator")
        miPre := treeCtx.Add("MenuItem").Name("SideMenuInsertPreCmd").Header(GetLang("上插指令"))
        this._AddSideCmdMenuItems(miPre, "SideMenuInsertPre_")
        miNext := treeCtx.Add("MenuItem").Name("SideMenuInsertNextCmd").Header(GetLang("下插指令"))
        this._AddSideCmdMenuItems(miNext, "SideMenuInsertNext_")
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("SideMenuSkipCmd").Header(GetLang("跳过指令"))
        treeCtx.Add("MenuItem").Name("SideMenuDebugCmd").Header(GetLang("调试起点"))
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("SideMenuDeleteCmd").Header(GetLang("删除"))

        branchCtxHost := host.Add("Border").Name("SideBranchCtxHost").Width("0").Height("0").Visibility("Collapsed")
        branchCtx := branchCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("SideBranchCtxMenu")
            .MinWidth("180").Placement("MousePoint")
        if (scrollStyle != "")
            branchCtx.InjectResources(scrollStyle)
        if (subStyle != "")
            branchCtx.InjectResources(subStyle)
        if (IsObject(MyMacroGui))
            MyMacroGui._ApplyCtxMenuTheme(branchCtx)
        else
            branchCtx.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        branchCtx.FontSize(String(XAMLHost.PopupFontSizeDeclared()))
            .FontFamily((MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑")
        miAdd := branchCtx.Add("MenuItem").Name("SideMenuBranchAddCmd").Header(GetLang("添加指令"))
        this._AddSideCmdMenuItems(miAdd, "SideMenuBranchAdd_")
        branchCtx.Add("Separator")
        branchCtx.Add("MenuItem").Name("SideMenuBranchDelete").Header(GetLang("删除"))

        blankCtxHost := host.Add("Border").Name("SideTreeBlankCtxHost").Width("0").Height("0").Visibility("Collapsed")
        blankCtx := blankCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("SideTreeBlankCtxMenu")
            .MinWidth("180").Placement("MousePoint")
        if (scrollStyle != "")
            blankCtx.InjectResources(scrollStyle)
        if (subStyle != "")
            blankCtx.InjectResources(subStyle)
        if (IsObject(MyMacroGui))
            MyMacroGui._ApplyCtxMenuTheme(blankCtx)
        else
            blankCtx.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        blankCtx.FontSize(String(XAMLHost.PopupFontSizeDeclared()))
            .FontFamily((MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑")
        miBlank := blankCtx.Add("MenuItem").Name("SideMenuBlankInsertCmd").Header(GetLang("插入指令"))
        this._AddSideCmdMenuItems(miBlank, "SideMenuBlankInsert_")
        blankCtx.Add("MenuItem").Name("SideMenuBlankPasteCmd").Header(GetLang("粘贴"))
    }

    _AddSideCmdMenuItems(parentMi, namePrefix) {
        cmdArr := IsObject(MyMacroGui) ? MyMacroGui.CMDStrArr : []
        iconMap := IsObject(MyMacroGui) ? MyMacroGui.CmdIconFileMap : Map()
        for index, value in cmdArr {
            mi := parentMi.Add("MenuItem").Name(namePrefix index).Header(value)
            iconRel := iconMap.Has(value) ? iconMap[value] : ""
            if (iconRel != "") {
                full := StrReplace(A_WorkingDir "\" iconRel, "\", "/")
                if (FileExist(StrReplace(full, "/", "\")))
                    mi.Add("MenuItem.Icon").Add("Image").SetProp("Source", full).Width("16").Height("16")
            }
        }
    }

    _ApplySidePanelMode() {
        isTree := this.sidePanelMode == 1
        treeVis := isTree ? "Visible" : "Collapsed"
        aiVis := isTree ? "Collapsed" : "Visible"
        for t in this._useVirtual {
            try this.ui.Update("SideTreePane_" t, "Visibility", treeVis)
            try this.ui.Update("SideAiPane_" t, "Visibility", aiVis)
            try this.ui.Update("SideAiFoot_" t, "Visibility", aiVis)
            this._SyncSideModeBtn(t, isTree)
        }
        this._ApplySideToolsVisibility()
    }

    _BindSideTree(t) {
        if (this._sideTreeBound.Has(t))
            return
        this._sideTreeBound[t] := true
        if (!IsObject(this._sideTree))
            this._sideTree := SideLogicTree(this)
        this.ui.OnEvent("SideToolExpand_" t, "Click", ObjBindMethod(this, "OnSideToolExpand", t))
        this.ui.OnEvent("SideToolUndo_" t, "Click", ObjBindMethod(this, "OnSideToolUndo", t))
        this.ui.OnEvent("SideToolRedo_" t, "Click", ObjBindMethod(this, "OnSideToolRedo", t))
        this.ui.OnEvent("SideToolBack_" t, "Click", ObjBindMethod(this, "OnSideToolBack", t))
        this.ui.OnEvent("SideToolRecord_" t, "Click", ObjBindMethod(this, "OnSideToolRecord", t))
        this.ui.OnEvent("SideToolRun_" t, "Click", ObjBindMethod(this, "OnSideToolRun", t))
        this.ui.OnEvent("SideToolStep_" t, "Click", ObjBindMethod(this, "OnSideToolStep", t))
        this.ui.OnEvent("SideToolVar_" t, "Click", ObjBindMethod(this, "OnSideToolVar", t))
        this.ui.OnEvent("SideToolCmdTip_" t, "Click", ObjBindMethod(this, "OnSideToolCmdTip", t))
        this.ui.OnEvent("SideToolTop_" t, "Click", ObjBindMethod(this, "OnSideToolTop", t))
    }

    RefreshSideTree(t) {
        if (!IsObject(this.ui) || !this._useVirtual.Has(t))
            return
        if (!IsObject(this._sideTree))
            this._sideTree := SideLogicTree(this)
        emptyName := "SideTreeEmpty_" t
        item := this._ResolveSideTreeItem(t)
        selIdx := item ? GetItemIndexInTable(MySoftData.TableInfo[t], item.ID) : 0
        this._ApplyRowSel(t, selIdx)
        macroStr := ""
        if (item && CheckIsMacroTable(t) && Trim(item.Macro) != "")
            macroStr := GetLangMacro(item.Macro, 1)
        this._sideTree.Load(t, macroStr)
        this._sideTree.SyncToolToggles(t)
        hasCmd := Trim(macroStr) != ""
        try this.ui.Update(emptyName, "Visibility", hasCmd ? "Collapsed" : "Visible")
    }

    _WriteSideTreeMacroStr(t, macroStr) {
        item := this._ResolveSideTreeItem(t)
        if (!item)
            return
        item.Macro := GetLangMacro(macroStr, 2)
        HotReloadPublish(t, 0)
        idx := GetItemIndexInTable(MySoftData.TableInfo[t], item.ID)
        if (idx >= 1) {
            ; 避免 RefreshItemRow → RefreshSideTree 递归重建当前树
            this._suppressSideTreeRefresh := true
            try {
                if (this._useVirtual.Has(t) && IsObject(this._vl))
                    this._vl.RefreshRow(t, idx)
                else
                    this.RefreshItemRow(t, idx)
            } finally {
                this._suppressSideTreeRefresh := false
            }
        }
        emptyName := "SideTreeEmpty_" t
        try this.ui.Update(emptyName, "Visibility", Trim(macroStr) == "" ? "Visible" : "Collapsed")
    }

    OnSideToolExpand(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        expandAll := !this._sideTree._allExpanded
        if (expandAll)
            ed.ExpandAll()
        else
            ed.CollapseAll()
        this._sideTree._allExpanded := expandAll
        this._SyncSideExpandBtn(t)
    }

    ; 下次点是展开 → E740（箭头分开）；下次点是收缩 → E73F（现图标）
    _SyncSideExpandBtn(t) {
        if (!IsObject(this.ui))
            return
        allExp := IsObject(this._sideTree) ? !!this._sideTree._allExpanded : true
        glyph := allExp ? Chr(0xE73F) : Chr(0xE740)
        try this.ui.Update("SideToolExpand_" t, "Content", glyph)
    }

    OnSideToolUndo(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.Undo()
    }

    OnSideToolRedo(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.Redo()
    }

    OnSideToolBack(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.Backspace()
        ed._NotifyMacroChanged()
    }

    OnSideToolRecord(t, *) {
        OnHotToolRecordMacro(true)
        if (IsObject(this._sideTree))
            this._sideTree.SyncToolToggles(t)
    }

    OnSideToolRun(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.MenuHandler(ed._DebugRunLabel())
    }

    OnSideToolStep(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.MenuHandler(ed._DebugStepLabel())
    }

    OnSideToolVar(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (IsObject(ed)) {
            this._sideTree.Activate(t)
            ed.MenuHandler(GetLang("变量监视"))
        } else {
            if (MyVarListenGui.Gui != "" && MyVarListenGui.Gui.Hwnd) {
                style := WinGetStyle(MyVarListenGui.Gui.Hwnd)
                if (style & 0x10000000) {
                    MyVarListenGui.Gui.Hide()
                } else
                    MyVarListenGui.ShowGui()
            } else
                MyVarListenGui.ShowGui()
        }
        if (IsObject(this._sideTree))
            this._sideTree.SyncToolToggles(t)
    }

    OnSideToolCmdTip(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (IsObject(ed)) {
            this._sideTree.Activate(t)
            ed.MenuHandler(GetLang("指令显示"))
        }
        if (IsObject(this._sideTree))
            this._sideTree.SyncToolToggles(t)
    }

    OnSideToolTop(t, *) {
        this._sideTopOn := !this._sideTopOn
        if (IsObject(this._sideTree))
            this._sideTree._topOn := this._sideTopOn
        try this.ui.Update("Window", "Topmost", this._sideTopOn ? "True" : "False")
        for tab in this._useVirtual {
            this.SyncSideToolToggle(tab, "Top", this._sideTopOn)
            this.SyncSideToolToggle(tab, "Top", this._sideTopOn, "SideAiTool")
        }
    }

    _FirstSideTreeItem(tableItem) {
        if (!IsObject(tableItem))
            return ""
        if (tableItem.Folds.Length >= 1) {
            fold := tableItem.Folds[1]
            for item in tableItem.Items {
                if (item.FoldID == fold.ID)
                    return item
            }
        }
        return tableItem.Items.Length >= 1 ? tableItem.Items[1] : ""
    }

    _SelectFirstSideTreeItem(t) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        item := this._FirstSideTreeItem(MySoftData.TableInfo[t])
        if (!item)
            return
        this._sideTreeSel[t] := item.ID
        this._ApplyRowSel(t, GetItemIndexInTable(MySoftData.TableInfo[t], item.ID))
    }

    _ResolveSideTreeItem(t) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return ""
        tableItem := MySoftData.TableInfo[t]
        id := this._sideTreeSel.Has(t) ? this._sideTreeSel[t] : ""
        if (id == "")
            return ""
        return tableItem.GetItem(id)
    }

    SelectSideTreeItem(t, index, openPanel := true, deferTree := false, *) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        tableItem := MySoftData.TableInfo[t]
        if (index < 1 || index > tableItem.Items.Length)
            return
        item := tableItem.Items[index]
        if (!item)
            return
        ; 事件回调会把 state 传到 openPanel；只有显式 false 才不展开
        doOpen := (openPanel != false && openPanel != 0)
        opened := false
        if (doOpen && !this._IsAiPanelOpen()) {
            this.aiAssistOpen := true
            this.sidePanelMode := 1
            this._ApplyAiPanelUi()
            this._ApplySidePanelMode()
            opened := true
        }
        same := this._sideTreeSel.Has(t) && this._sideTreeSel[t] == item.ID
        this._sideTreeSel[t] := item.ID
        this._ApplyRowSel(t, index)
        if (this._IsAiPanelOpen() && this.sidePanelMode == 1 && (!same || opened)) {
            if (deferTree == true)
                SetTimer(ObjBindMethod(this, "RefreshSideTree", t), -1)
            else
                this.RefreshSideTree(t)
        }
    }

    _ApplyRowSel(t, index) {
        if (t < 1)
            return
        if (this._useVirtual.Has(t) && IsObject(this._vl)) {
            this._vl.SetRowSel(t, index)
            return
        }
        if (this._rowSelIdx.Has(t)) {
            old := this._rowSelIdx[t]
            if (old != index && old >= 1)
                this._SetItemRowSelChrome(t, old, false)
        }
        if (index >= 1) {
            this._SetItemRowSelChrome(t, index, true)
            this._rowSelIdx[t] := index
        } else {
            this._rowSelIdx[t] := 0
        }
    }

    _SetItemRowSelChrome(t, i, on) {
        if (!this._IsRendered(t, i))
            return
        tableItem := MySoftData.TableInfo[t]
        item := (i >= 1 && i <= tableItem.Items.Length) ? tableItem.Items[i] : ""
        if (on) {
            this.ui.Update("ItemCard_" t "_" i, "Background", "{DynamicResource TabSelBg}")
            this.ui.Update("RowSelDot_" t "_" i, "Visibility", "Visible")
            this.ui.Update("RowSelMark_" t "_" i, "Visibility", "Visible")
        } else {
            bg := (item && (item.Forbid || GetItemFoldForbidState(tableItem, i))) ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource ControlBg}"
            this.ui.Update("ItemCard_" t "_" i, "Background", bg)
            this.ui.Update("RowSelDot_" t "_" i, "Visibility", "Collapsed")
            this.ui.Update("RowSelMark_" t "_" i, "Visibility", "Collapsed")
        }
    }

    _SyncSideModeBtn(t, isTree) {
        this._PaintSideModeBtn("BtnSideModeTree_" t, isTree, "first")
        this._PaintSideModeBtn("BtnSideModeAi_" t, !isTree, "last")
    }

    _PaintSideModeBtn(name, on, which) {
        tag := (which == "last") ? (on ? "sel-last" : "last") : (on ? "sel-first" : "first")
        try this.ui.Update(name, "Tag", tag)
    }

    _BuildAiAssistPanel(vg, idx) {
        wrap := vg.Add("Grid").Name("AiWrap_" idx).Grid_Column(1)
            .Width(this.aiPanelW).MinWidth(this._AiPanelMinW()).MaxWidth(this._AiPanelMaxW())
            .Visibility("Collapsed").Margin("0").Panel_ZIndex(1).ClipToBounds("True")
        panel := wrap.Add("Border").Name("AiInner_" idx).Margin("0").Padding("0")
            .Width(this.aiPanelW).HorizontalAlignment("Right")
            .Background("{DynamicResource ControlBg}")
        wrap.Add("Border").Name("AiSplit_" idx)
            .HorizontalAlignment("Left").Width(this._AiPanelSplitW())
            .Background("Transparent").Cursor("SizeWE")
            .BorderThickness("1.5,0,0,0").BorderBrush("{DynamicResource OutlineStroke}")
            .ToolTip(GetLang("拖拽调整宽度"))
        g := panel.Add("Grid")
        g.Rows("Auto", "*", "Auto")
        head := g.Add("Grid").Grid_Row(0)
        head.Rows("28", "1.5", "Auto", "1.5")
        tabW := this._AiTabW()
        opt := head.Add("Grid").Grid_Row(0).Height(28).MinHeight(28)
        opt.Cols(tabW, "Auto", tabW, "*", "Auto")
        opt.Add("Button").Name("BtnSideModeTree_" idx).Grid_Column(0).Content(GetLang("逻辑树"))
            .Style("{StaticResource RmtSideModeTab}").Width(tabW).Tag("sel-first")
        opt.Add("Rectangle").Grid_Column(1).Width(2).Fill("{DynamicResource ControlBorder}")
            .VerticalAlignment("Stretch").Margin("0,3,0,3").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")
        opt.Add("Button").Name("BtnSideModeAi_" idx).Grid_Column(2).Content(GetLang("AI助手"))
            .Style("{StaticResource RmtSideModeTab}").Width(tabW).Tag("last")
        opt.Add("Button").Name("BtnSideToolsToggle_" idx).Grid_Column(4)
            .Style("{StaticResource RmtFoldToolBtn}").Width(26).Height(26).MinHeight(26)
            .Margin("0,0,6,0").VerticalAlignment("Center").HorizontalAlignment("Right")
            .Content(Chr(0xE70E)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .ToolTip(GetLang("收起操作"))
            .Background("Transparent").BorderBrush("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TextMain}")
        head.Add("Rectangle").Grid_Row(1).Height(1.5).Fill("{DynamicResource OutlineStroke}")
            .HorizontalAlignment("Stretch").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")

        toolBar := head.Add("StackPanel").Name("SideToolBar_" idx).Grid_Row(2)
            .Orientation("Horizontal").Height(30).Margin("4,4,4,4").VerticalAlignment("Center")
        this._AddSideToolBtn(toolBar, idx, "Expand", Chr(0xE73F), GetLang("展开/收缩"), false)
        this._AddSideToolBtn(toolBar, idx, "Undo", Chr(0xE7A7), GetLang("撤销"), false)
        this._AddSideToolBtn(toolBar, idx, "Redo", Chr(0xE7A6), GetLang("恢复"), false)
        this._AddSideToolBtn(toolBar, idx, "Back", Chr(0xE750), GetLang("删除末尾"), false)
        this._AddSideToolBtn(toolBar, idx, "Record", Chr(0xE7C8), GetLang("指令录制"), true)
        this._AddSideToolBtn(toolBar, idx, "Run", Chr(0xE768), GetLang("运行"), false)
        this._AddSideToolBtn(toolBar, idx, "Step", "", GetLang("单步运行"), false)
        this._AddSideToolBtn(toolBar, idx, "Var", Chr(0xE7B3), GetLang("变量监视"), true)
        this._AddSideToolBtn(toolBar, idx, "CmdTip", Chr(0xE8E3), GetLang("指令显示"), true)
        this._AddSideToolBtn(toolBar, idx, "Top", Chr(0xE840), GetLang("窗口置顶"), true)

        aiToolBar := head.Add("StackPanel").Name("SideAiToolBar_" idx).Grid_Row(2)
            .Orientation("Horizontal").Height(30).Margin("4,4,4,4").VerticalAlignment("Center")
            .Visibility("Collapsed")
        this._AddSideToolBtn(aiToolBar, idx, "History", Chr(0xE81C), GetLang("对话记录"), false, "SideAiTool")
        this._AddSideToolBtn(aiToolBar, idx, "Settings", Chr(0xE713), GetLang("设置"), false, "SideAiTool")
        this._AddSideToolBtn(aiToolBar, idx, "Top", Chr(0xE840), GetLang("窗口置顶"), true, "SideAiTool")

        head.Add("Rectangle").Name("SideToolSplit_" idx).Grid_Row(3).Height(1.5)
            .Fill("{DynamicResource OutlineStroke}")
            .HorizontalAlignment("Stretch").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")
        head.Add("Rectangle").Name("SideAiToolSplit_" idx).Grid_Row(3).Height(1.5)
            .Fill("{DynamicResource OutlineStroke}")
            .HorizontalAlignment("Stretch").IsHitTestVisible("False")
            .SnapsToDevicePixels("True").Visibility("Collapsed")

        body := g.Add("Grid").Grid_Row(1)
        treeHost := body.Add("Grid").Name("SideTreePane_" idx).Visibility("Visible")
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="Transparent" SnapsToDevicePixels="True"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>'
        treeLb := treeHost.Add("ListBox").Name("SideTreeList_" idx)
            .BorderThickness("0").Background("Transparent").Padding("0")
            .HorizontalContentAlignment("Stretch")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
            .VirtualizingPanel_IsVirtualizing("False")
            .InjectResources(lbStyle)
        treeHost.Add("Border").Name("SideDragInsertLine_" idx).Height(2)
            .HorizontalAlignment("Stretch").VerticalAlignment("Top")
            .Background("{DynamicResource Accent}").BorderThickness(0)
            .SetProp("Panel.ZIndex", "10").Visibility("Collapsed").IsHitTestVisible("False")
        ghostPop := treeHost.Add("Popup").Name("SideDragGhost_" idx).Placement("Absolute")
            .AllowsTransparency("True").IsHitTestVisible("False").IsOpen("False")
        ghostBd := ghostPop.Add("Border").CornerRadius("3").BorderThickness("1").Padding("10,5")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource Accent}").Opacity("0.94")
        ghostBd.Add("TextBlock").Name("SideDragGhostTxt_" idx).MaxWidth("280").TextTrimming("CharacterEllipsis")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        treeHost.Add("TextBlock").Name("SideTreeEmpty_" idx).Text(GetLang("暂无指令"))
            .Foreground("{DynamicResource TextSub}").FontSize(12)
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .IsHitTestVisible("False")

        if (!this._sideCtxBuilt) {
            this._sideCtxBuilt := true
            this._BuildSideTreeContextMenus(head)
        }

        aiSv := body.Add("ScrollViewer").Name("SideAiPane_" idx).Visibility("Collapsed")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        msgs := aiSv.Add("StackPanel").Name("SideAiMsgs_" idx).Margin("12,12,12,8")
        lineH := this._AiInputLineH()
        textH := lineH - 2
        maxH := lineH + (this._AiInputMaxLines() - 1) * this._AiInputExtraLineH()
        sendW := this._AiInputSendW()
        padL := AiSettingGui.ContentPadL
        r := this._AiInputRadius()
        foot := g.Add("Border").Name("SideAiFoot_" idx).Grid_Row(2).Padding("10,4,10,8").BorderThickness("0")
            .Visibility("Collapsed")
        footCol := foot.Add("StackPanel")
        ; 「正在思考」放在输入区上方（不进消息列表），避免第二次请求复用旧节点导致位置错乱
        footCol.Add("TextBlock").Name("AiThinkTxt_" idx).Text(GetLang("正在思考") "…")
            .FontSize(this._AiChatBodyFontSize()).FontStyle("Italic").Foreground("{DynamicResource TextSub}")
            .Margin("2,0,0,6").Visibility("Collapsed").IsHitTestVisible("False")
            .TextWrapping("Wrap")
        chrome := footCol.Add("Border").Name("AiInputHost_" idx).Height(lineH).MinHeight(lineH).MaxHeight(maxH + this._AiAttachBarH())
            .Padding(padL ",0," padL ",0")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1").CornerRadius(String(r)).AllowDrop("True")
        chrome.Apply({SnapsToDevicePixels: "True", UseLayoutRounding: "False"})
        box := chrome.Add("Grid")
        box.Rows("Auto", "*")
        att := box.Add("StackPanel").Name("AiAttachBar_" idx).Grid_Row(0).Orientation("Horizontal")
            .Margin("0,6,4,4").Visibility("Collapsed").ClipToBounds("False")
        inner := box.Add("Grid").Grid_Row(1)
        tb := inner.Add("TextBox").Name("AiInput_" idx).Style("{StaticResource RmtAiChatBox}")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch")
            .Height(textH).MinHeight(textH).MaxHeight(maxH)
            .AcceptsReturn("True").TextWrapping("Wrap").AllowDrop("False")
            .VerticalScrollBarVisibility("Hidden").HorizontalScrollBarVisibility("Disabled")
            .VerticalContentAlignment("Center").Padding("0").Margin("0")
            .FontSize(this._AiChatBodyFontSize())
            .Foreground("{DynamicResource InputText}")
            .Background("Transparent").BorderThickness("0")
        this._AttachTextEditContextMenu(tb, true)
        ph := inner.Add("TextBlock").Name("AiInputPh_" idx).Text(GetLang("询问关于宏的任何问题…")).IsHitTestVisible("False")
            .VerticalAlignment("Center").HorizontalAlignment("Left").Margin("0")
            .Foreground("{DynamicResource TextSub}").Opacity("0.55")
            .FontSize(this._AiChatBodyFontSize())
        btns := inner.Add("StackPanel").Name("AiInputBtns_" idx).Orientation("Horizontal")
            .HorizontalAlignment("Right").VerticalAlignment("Center")
            .SetProp("Panel.ZIndex", "2")
        btns.Add("Button").Name("AiMic_" idx).Width(sendW).Height(sendW).MinHeight(sendW)
            .Style("{StaticResource RmtAiIconBtn}").Margin("0,0,2,0")
            .Content(Chr(0xE720)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
            .ToolTip(GetLang("语音输入"))
        btns.Add("Button").Name("AiSend_" idx).Width(sendW).Height(sendW).MinHeight(sendW)
            .Style("{StaticResource RmtAiIconBtn}").Margin("0")
            .Content(Chr(0xE724)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
            .ToolTip(GetLang("发送"))
    }

    ; 文本框 / 只读富文本：用 XAML ContextMenu 替换系统旧菜单
    ; AI 菜单在 Viewbox 外：只用主题字号（与输入框观感一致），不再乘 Viewbox（窗口化时会过大）
    _AttachTextEditContextMenu(el, editable) {
        if (!IsObject(el))
            return
        fs := XAMLHost.FontSize()
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑"
        cm := el.Add("FrameworkElement.ContextMenu").Add("ContextMenu")
            .MinWidth("140").Placement("MousePoint")
            .FontSize(String(fs)).FontFamily(ff)
        scrollStyle := IsObject(MyMacroGui) ? MyMacroGui._ContextMenuScrollStyle() : ""
        if (scrollStyle != "")
            cm.InjectResources(scrollStyle)
        if (IsObject(MyMacroGui)) {
            cm.InjectResources(MyMacroGui._MenuItemSubmenuStyle())
            MyMacroGui._ApplyCtxMenuTheme(cm)
        } else
            cm.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        cm.FontSize(String(fs)).FontFamily(ff)
        if (editable) {
            cm.Add("MenuItem").Header(GetLang("剪切")).SetMarkup("Command", "Cut")
            cm.Add("MenuItem").Header(GetLang("复制")).SetMarkup("Command", "Copy")
            cm.Add("MenuItem").Header(GetLang("粘贴")).SetMarkup("Command", "Paste")
            cm.Add("Separator")
            cm.Add("MenuItem").Header(GetLang("全选")).SetMarkup("Command", "SelectAll")
        } else {
            cm.Add("MenuItem").Header(GetLang("复制")).SetMarkup("Command", "Copy")
            cm.Add("Separator")
            cm.Add("MenuItem").Header(GetLang("全选")).SetMarkup("Command", "SelectAll")
        }
    }

    _AiMsgContextMenuXaml(isUser := false, text := "") {
        fs := XAMLHost.FontSize()
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? this._XmlEsc(MainSoftData.FontType) : "微软雅黑"
        extra := '<MenuItem Header="' this._XmlEsc(GetLang("全选")) '" Command="SelectAll"/>'
        if (isUser) {
            this._aiLinkSeq += 1
            name := "AiCopyAll_" this._aiLinkSeq
            if (!IsObject(this._aiPendingCopyAll))
                this._aiPendingCopyAll := []
            if (!IsObject(this._aiCopyAllText))
                this._aiCopyAllText := Map()
            this._aiPendingCopyAll.Push(name)
            this._aiCopyAllText[name] := this._AiPlainAttachLabel(text)
            extra := '<MenuItem Name="' name '" Header="' this._XmlEsc(GetLang("全部复制")) '"/>'
        }
        return '<RichTextBox.ContextMenu>'
            . '<ContextMenu MinWidth="140" Placement="MousePoint"'
            . ' FontSize="' fs '" FontFamily="' ff '"'
            . ' Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" Foreground="{DynamicResource TextMain}">'
            . '<MenuItem Header="' this._XmlEsc(GetLang("复制")) '" Command="Copy"/>'
            . '<Separator/>'
            . extra
            . '</ContextMenu></RichTextBox.ContextMenu>'
    }

    OnAiCopyAll(name, *) {
        txt := ""
        if (IsObject(this._aiCopyAllText) && this._aiCopyAllText.Has(name))
            txt := this._aiCopyAllText[name]
        if (txt == "")
            return
        A_Clipboard := txt
        Toast.Success(GetLang("已复制"))
    }

    _AiInputSendW() {
        return 24
    }
    _AiInputIconReserve() {
        return this._AiInputSendW() * 2 + 4
    }

    _AiInputPad(lines) {
        pad := AiSettingGui.ContentPadL
        return lines <= 1 ? pad ",0," pad ",0" : pad ",2," pad ",2"
    }

    _AiInputPhMargin(lines) {
        return "0"
    }

    _AiAttachBarH() {
        return 52
    }

    _SeedAiMsgs() {
        if (this.aiSeeded)
            return
        this.aiSeeded := true
        t := MainSoftData.TableIndex
        if (t < 1 || !this._useVirtual.Has(t)) {
            for tab in this._useVirtual {
                t := tab
                break
            }
        }
        if (t < 1)
            return
        this._EnsureAiSeeded(t)
    }

    _EnsureAiSeeded(t := 0) {
        if (!IsObject(this._aiSeededTabs))
            this._aiSeededTabs := Map()
        if (t < 1)
            t := MainSoftData.TableIndex
        if (t < 1 || !this._useVirtual.Has(t) || this._aiSeededTabs.Has(t))
            return
        this._aiSeededTabs[t] := true
        this.aiSeeded := true
        fence := Chr(96) Chr(96) Chr(96)
        tick := Chr(96)
        ; Cursor 风格：单条助手欢迎，不做 A/B 对聊演示
        welcome := "我是 **RMT 助手**，可以帮你解读、修改和生成宏配置。`n`n"
            . "试试：`n"
            . "- 描述你想做的操作，我给出可落地的改法`n"
            . "- 粘贴或拖入文件路径，一起分析配置`n"
            . "- 用链接跳转宏项，例如 [当前页第 1 个宏](rmt:" t ":1)`n`n"
            . "支持 Markdown（标题、列表、**加粗**、" tick "代码" tick "、表格等）。"
        this._AiAppendMsg(t, false, welcome)
    }

    _AiAppendMsg(t, isUser, text) {
        stick := true
        try stick := this._AiIsStickBottom(t)
        this._aiPendingLinks := []
        this._aiPendingFileActs := []
        this._aiPendingCopyAll := []
        this._aiPendingUserCards := []
        xaml := this._AiMsgXaml(isUser, text)
        try this.ui.Update("SideAiMsgs_" t, "AddXamlItem", xaml)
        for name in this._aiPendingLinks
            this._Bind(name, "Click", ObjBindMethod(this, "OnAiNavClick", name))
        for act in this._aiPendingFileActs
            this._Bind(act.name, "Click", ObjBindMethod(this, "OnAiFileMenu", act))
        for name in this._aiPendingCopyAll
            this._Bind(name, "Click", ObjBindMethod(this, "OnAiCopyAll", name))
        for name in this._aiPendingUserCards
            this._Bind(name, "MouseLeftButtonUp", ObjBindMethod(this, "OnAiUserMsgClick", name))
        if (stick)
            this._AiScrollToEndSoon(t)
    }

    ; Cursor 风格回合：用户有边框卡片；助手正文铺开。不再标「你 / 助手」。
    _AiMsgXaml(isUser, text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        fg := "{DynamicResource TextMain}"
        this._aiMsgFilePaths := this._AiExtractFilePaths(text)
        body := this._AiMdBodyXaml(text, fg, isUser)
        fs := this._AiChatBodyFontSize()
        ff := this._XmlEsc(this._AiChatFontFamily())
        rtbHit := ""
        rtbName := ""
        if (isUser) {
            this._aiLinkSeq += 1
            card := "AiUserMsg_" this._aiLinkSeq
            rtbName := ' Name="' card '_Body"'
            if (this._AiUserNeedsClip(text)) {
                rtbHit := ' IsHitTestVisible="False"'
                this._aiPendingUserCards.Push(card)
            }
        }
        rtb := '<RichTextBox' rtbName ' IsReadOnly="True" IsDocumentEnabled="True" BorderThickness="0"'
            . ' Background="Transparent" Padding="0" Margin="0"'
            . ' VerticalScrollBarVisibility="Disabled" HorizontalScrollBarVisibility="Disabled"'
            . ' IsUndoEnabled="False" CaretBrush="Transparent" Cursor="IBeam" Tag="PassScroll"'
            . rtbHit
            . ' FontSize="' fs '" FontFamily="' ff '" Foreground="' fg '">'
            . this._AiMsgContextMenuXaml(isUser, text)
            . '<FlowDocument PagePadding="0" TextAlignment="Left" FontSize="' fs '" FontFamily="' ff '">'
            . body
            . '</FlowDocument></RichTextBox>'
        if (isUser) {
            pad := AiSettingGui.ContentPadL
            r := this._AiInputRadius()
            clip := this._AiUserNeedsClip(text)
            extra := clip
                ? ' MaxHeight="' this._AiUserPreviewH() '" ClipToBounds="True" Cursor="Hand" ToolTip="' this._XmlEsc(GetLang("点击展开")) '"'
                : ""
            return '<Border ' ns ' Name="' card '" Margin="0,2,0,9" Padding="' pad ',' pad '" HorizontalAlignment="Stretch"'
                . ' Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}"'
                . ' BorderThickness="1" CornerRadius="' r '"' extra '>'
                . rtb
                . '</Border>'
        }
        return '<Border ' ns ' Margin="0,0,0,13" Padding="2,0,0,0" Background="Transparent" HorizontalAlignment="Stretch">'
            . rtb
            . '</Border>'
    }

    OnAiUserMsgClick(name, *) {
        if (!IsObject(this._aiUserExpanded))
            this._aiUserExpanded := Map()
        if (this._aiUserExpanded.Has(name) && this._aiUserExpanded[name])
            return
        this._aiUserExpanded[name] := true
        try this.ui.Update(name, "MaxHeight", "10000")
        try this.ui.Update(name, "Cursor", "Arrow")
        try this.ui.Update(name, "ToolTip", "")
        try this.ui.Update(name "_Body", "IsHitTestVisible", "True")
    }

    _AiMdBodyXaml(text, fg, preserveLines := false) {
        if (preserveLines)
            return this._AiPreserveLinesXaml(text, fg)
        out := ""
        for blk in this._AiParseMd(text)
            out .= this._AiMdBlockXaml(blk, fg)
        if (out == "")
            out := this._AiMdParagraph(text, fg, this._AiChatBodyFontSize(), "0,0,0,0")
        return out
    }

    ; 用户输入按原文换行展示，不按 Markdown 把相邻行拼成一段
    _AiPreserveLinesXaml(text, fg) {
        raw := this._AiNormalizeNewlines(text, false)
        fs := this._AiChatBodyFontSize()
        lh := this._AiUserPreviewLineH()
        out := ""
        for line in StrSplit(raw, "`n")
            out .= '<Paragraph Margin="0,0,0,0" LineHeight="' lh '" LineStackingStrategy="BlockLineHeight"'
                . ' FontSize="' fs '" Foreground="' fg '">' this._AiInlineXaml(line, fg) '</Paragraph>'
        if (out == "")
            out .= '<Paragraph Margin="0,0,0,0" LineHeight="' lh '" LineStackingStrategy="BlockLineHeight"'
                . ' FontSize="' fs '" Foreground="' fg '">' this._AiMdRun("", ' Foreground="' fg '"') '</Paragraph>'
        return out
    }

    _AiParseMd(text) {
        blocks := []
        raw := this._AiNormalizeNewlines(text, false)
        lines := StrSplit(raw, "`n")
        fence := Chr(96) Chr(96) Chr(96)
        i := 1
        n := lines.Length
        while (i <= n) {
            line := lines[i]
            if (Trim(line) == "") {
                i++
                continue
            }
            tline := Trim(line)
            if (SubStr(tline, 1, 3) == fence) {
                lang := Trim(SubStr(tline, 4))
                body := ""
                i++
                while (i <= n && SubStr(Trim(lines[i]), 1, 3) != fence) {
                    body .= (body == "" ? "" : "`n") lines[i]
                    i++
                }
                blocks.Push(Map("type", "code", "lang", lang, "text", body))
                i++
                continue
            }
            if (this._AiLooksTable(line) && i < n && this._AiLooksTableSep(lines[i + 1])) {
                rows := []
                while (i <= n && this._AiLooksTable(lines[i])) {
                    if (!this._AiLooksTableSep(lines[i]))
                        rows.Push(this._AiTableCells(lines[i]))
                    i++
                }
                blocks.Push(Map("type", "table", "rows", rows))
                continue
            }
            if (RegExMatch(line, "^(#{1,3})\s+(.+)$", &mh)) {
                blocks.Push(Map("type", "h", "level", StrLen(mh[1]), "text", mh[2]))
                i++
                continue
            }
            if (RegExMatch(tline, "^([-*_])\1{2,}$")) {
                blocks.Push(Map("type", "hr"))
                i++
                continue
            }
            if (RegExMatch(line, "^>\s?(.*)$", &mq)) {
                q := mq[1]
                i++
                while (i <= n && RegExMatch(lines[i], "^>\s?(.*)$", &mq2)) {
                    q .= "`n" mq2[1]
                    i++
                }
                blocks.Push(Map("type", "quote", "text", q))
                continue
            }
            if (RegExMatch(line, "^[-*+]\s+(.+)$", &mu)) {
                items := [mu[1]]
                i++
                while (i <= n && RegExMatch(lines[i], "^[-*+]\s+(.+)$", &mu2)) {
                    items.Push(mu2[1])
                    i++
                }
                blocks.Push(Map("type", "ul", "items", items))
                continue
            }
            if (RegExMatch(line, "^\d+[.)]\s+(.+)$", &mo)) {
                items := [mo[1]]
                i++
                while (i <= n && RegExMatch(lines[i], "^\d+[.)]\s+(.+)$", &mo2)) {
                    items.Push(mo2[1])
                    i++
                }
                blocks.Push(Map("type", "ol", "items", items))
                continue
            }
            para := line
            i++
            while (i <= n && !this._AiMdBreak(lines[i]) && !this._AiMdKeepLine(para, lines[i])) {
                para .= " " Trim(lines[i])
                i++
            }
            blocks.Push(Map("type", "p", "text", para))
        }
        return blocks
    }

    ; 上一行已是完整句，或下一行是路径/目标，不要拼成一段（避免「评分」被从中间折开）
    _AiMdKeepLine(prev, nextLine) {
        next := Trim(nextLine)
        if (next == "")
            return true
        if (RegExMatch(Trim(prev), "[。！？.!?」』]$"))
            return true
        if (RegExMatch(next, "^(目标：|写入失败|请到|路径：)"))
            return true
        if (RegExMatch(next, "^[A-Za-z]:[\\/]") || InStr(next, "\Desktop\") || InStr(next, "/Desktop/"))
            return true
        return false
    }

    _AiMdBreak(line) {
        if (Trim(line) == "")
            return true
        tline := Trim(line)
        fence := Chr(96) Chr(96) Chr(96)
        if (SubStr(tline, 1, 3) == fence)
            return true
        if (RegExMatch(line, "^(#{1,3})\s+"))
            return true
        if (RegExMatch(line, "^[-*+]\s+"))
            return true
        if (RegExMatch(line, "^\d+[.)]\s+"))
            return true
        if (RegExMatch(line, "^>\s?"))
            return true
        if (this._AiLooksTable(line))
            return true
        if (RegExMatch(tline, "^([-*_])\1{2,}$"))
            return true
        return false
    }

    _AiLooksTable(line) {
        return SubStr(Trim(line), 1, 1) == "|"
    }

    _AiLooksTableSep(line) {
        return RegExMatch(Trim(line), "^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$")
    }

    _AiTableCells(line) {
        s := Trim(line)
        if (SubStr(s, 1, 1) == "|")
            s := SubStr(s, 2)
        if (s != "" && SubStr(s, -1) == "|")
            s := SubStr(s, 1, StrLen(s) - 1)
        cells := []
        for part in StrSplit(s, "|")
            cells.Push(Trim(part))
        return cells
    }

    _AiMdBlockXaml(blk, fg) {
        tp := blk["type"]
        if (tp == "h") {
            fs := blk["level"] == 1 ? 16 : (blk["level"] == 2 ? 14 : 13)
            return this._AiMdParagraph(blk["text"], fg, fs, "0,2,0,6", true)
        }
        if (tp == "p")
            return this._AiMdParagraph(blk["text"], fg, this._AiChatBodyFontSize(), "0,0,0,6")
        if (tp == "hr")
            return '<BlockUIContainer><Rectangle Height="1" Fill="{DynamicResource ControlBorder}" Margin="0,8" HorizontalAlignment="Stretch"/></BlockUIContainer>'
        if (tp == "quote")
            return '<BlockUIContainer><Border BorderThickness="2,0,0,0" BorderBrush="{DynamicResource Accent}" Padding="8,2,0,2" Margin="0,2,0,8">'
                . '<TextBlock TextWrapping="Wrap" FontSize="' this._AiChatBodyFontSize() '" Foreground="' fg '" Opacity="0.9">' this._AiInlineXaml(blk["text"], fg) '</TextBlock>'
                . '</Border></BlockUIContainer>'
        if (tp == "code") {
            head := blk["lang"] != "" ? '<TextBlock Text="' this._XmlEsc(blk["lang"]) '" FontSize="' this._AiChatSmallFontSize() '" Margin="0,0,0,4" Foreground="{DynamicResource TextSub}"/>' : ""
            return '<BlockUIContainer><Border Background="{DynamicResource ListAltBg}" CornerRadius="4" Padding="8,6" Margin="0,2,0,8">'
                . '<StackPanel>' head
                . '<TextBlock Text="' this._XmlEsc(blk["text"]) '" FontFamily="Consolas, Cascadia Mono, Courier New" FontSize="' this._AiChatSmallFontSize() '"'
                . ' TextWrapping="Wrap" Foreground="{DynamicResource TextMain}" xml:space="preserve"/>'
                . '</StackPanel></Border></BlockUIContainer>'
        }
        if (tp == "ul" || tp == "ol") {
            out := ""
            idx := 1
            for it in blk["items"] {
                mark := tp == "ol" ? (idx ". ") : "• "
                out .= '<Paragraph Margin="0,1,0,1" FontSize="' this._AiChatBodyFontSize() '" Foreground="' fg '">'
                    . '<Run Text="' this._XmlEsc(mark) '"/>' this._AiInlineXaml(it, fg)
                    . '</Paragraph>'
                idx++
            }
            return out
        }
        if (tp == "table")
            return '<BlockUIContainer>' this._AiMdTableXaml(blk["rows"], fg) '</BlockUIContainer>'
        return this._AiMdParagraph(blk.Has("text") ? blk["text"] : "", fg, this._AiChatBodyFontSize(), "0,0,0,0")
    }

    _AiMdTableXaml(rows, fg) {
        if (rows.Length < 1)
            return ""
        cols := 1
        for row in rows {
            if (row.Length > cols)
                cols := row.Length
        }
        colDef := ""
        loop cols
            colDef .= '<ColumnDefinition Width="Auto"/>'
        rowDef := ""
        loop rows.Length
            rowDef .= '<RowDefinition Height="Auto"/>'
        cells := ""
        r := 0
        for row in rows {
            c := 0
            bg := r == 0 ? "{DynamicResource ControlBg}" : "Transparent"
            wt := r == 0 ? ' FontWeight="SemiBold"' : ""
            while (c < cols) {
                val := c < row.Length ? row[c + 1] : ""
                cells .= '<Border Grid.Row="' r '" Grid.Column="' c '" Background="' bg '"'
                    . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="0,0,1,1" Padding="6,4">'
                    . '<TextBlock TextWrapping="Wrap" FontSize="' this._AiChatSmallFontSize() '"' wt '>' this._AiInlineXaml(val, fg) '</TextBlock>'
                    . '</Border>'
                c++
            }
            r++
        }
        return '<Border BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1,1,0,0" CornerRadius="3" Margin="0,4,0,8">'
            . '<ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">'
            . '<Grid>'
            . '<Grid.ColumnDefinitions>' colDef '</Grid.ColumnDefinitions>'
            . '<Grid.RowDefinitions>' rowDef '</Grid.RowDefinitions>'
            . cells
            . '</Grid></ScrollViewer></Border>'
    }

    _AiMdParagraph(text, fg, fs, margin, bold := false) {
        wt := bold ? ' FontWeight="SemiBold"' : ""
        return '<Paragraph Margin="' margin '" FontSize="' fs '" Foreground="' fg '"' wt '>'
            . this._AiInlineXaml(text, fg) '</Paragraph>'
    }

    _AiInlineXaml(s, fg) {
        if (s == "")
            return this._AiMdRun("", ' Foreground="' fg '"')
        out := ""
        i := 1
        len := StrLen(s)
        tick := Chr(96)
        while (i <= len) {
            ch := SubStr(s, i, 1)
            two := SubStr(s, i, 2)
            if (two == "**") {
                close := InStr(s, "**", false, i + 2)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 2, close - i - 2), ' FontWeight="SemiBold" Foreground="' fg '"')
                    i := close + 2
                    continue
                }
            }
            if (two == "~~") {
                close := InStr(s, "~~", false, i + 2)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 2, close - i - 2), ' TextDecorations="Strikethrough" Foreground="' fg '"')
                    i := close + 2
                    continue
                }
            }
            if (ch == tick) {
                close := InStr(s, tick, false, i + 1)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 1, close - i - 1), ' FontFamily="Consolas, Cascadia Mono, Courier New" Background="{DynamicResource ListAltBg}" Foreground="' fg '"')
                    i := close + 1
                    continue
                }
            }
            if (ch == "*" || ch == "_") {
                close := this._AiMdEmphClose(s, i, ch)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 1, close - i - 1), ' FontStyle="Italic" Foreground="' fg '"')
                    i := close + 1
                    continue
                }
            }
            if (ch == "[") {
                rest := SubStr(s, i)
                if (RegExMatch(rest, "^\[([^\]]+)\]\((rmtfile:[^)]+)\)", &ml)) {
                    out .= this._AiFileLinkXaml(ml[1], this._AiDecodeFileUrl(ml[2]))
                    i += StrLen(ml[0])
                    continue
                }
                if (RegExMatch(rest, "^\[([^\]]+)\]\(([^)]+)\)", &ml)) {
                    nav := this._AiParseNavUrl(ml[2])
                    if (IsObject(nav))
                        out .= this._AiNavLinkXaml(ml[1], nav.tab, nav.idx)
                    else
                        out .= this._AiMdRun(ml[1], ' TextDecorations="Underline" Foreground="{DynamicResource Accent}"')
                    i += StrLen(ml[0])
                    continue
                }
            }
            j := i + 1
            while (j <= len) {
                c := SubStr(s, j, 1)
                t2 := SubStr(s, j, 2)
                if (t2 == "**" || t2 == "~~" || c == tick || c == "*" || c == "_" || c == "[")
                    break
                j++
            }
            out .= this._AiMdRun(SubStr(s, i, j - i), ' Foreground="' fg '"')
            i := j
        }
        return out
    }

    ; 路径、宏指令（按键_a_点击）里的 _ / * 不当成斜体
    _AiMdEmphClose(s, i, ch) {
        if (ch == "_" && this._AiMdPathish(s))
            return 0
        prev := (i > 1) ? SubStr(s, i - 1, 1) : " "
        nxt := SubStr(s, i + 1, 1)
        if (nxt == "" || nxt == ch)
            return 0
        if (this._AiMdWordChar(prev) || this._AiMdPathChar(prev))
            return 0
        close := InStr(s, ch, false, i + 1)
        while (close) {
            inner := SubStr(s, i + 1, close - i - 1)
            after := (close < StrLen(s)) ? SubStr(s, close + 1, 1) : " "
            if (inner != "" && !this._AiMdPathChar(after) && !(ch == "_" && this._AiMdWordChar(after))
                && !InStr(inner, "\") && !InStr(inner, "/") && !InStr(inner, ":"))
                return close
            close := InStr(s, ch, false, close + 1)
        }
        return 0
    }

    _AiMdPathish(s) {
        return InStr(s, ":\") || InStr(s, ":/") || InStr(s, "\Desktop") || InStr(s, "/Desktop")
    }

    _AiMdWordChar(c) {
        return (c != "" && RegExMatch(c, "^[A-Za-z0-9]$"))
    }

    _AiMdPathChar(c) {
        return (c = "\" || c = "/" || c = ":" || c = "." || c = "-")
    }

    _AiMdRun(text, extra) {
        return '<Run' extra ' BaselineAlignment="Baseline" Text="' this._XmlEsc(text) '"/>'
    }

    _AiParseNavUrl(url) {
        url := Trim(url)
        if (RegExMatch(url, "i)^rmt://t/(\d+)/i/(\d+)/?$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        if (RegExMatch(url, "i)^rmt:(\d+):(\d+)$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        if (RegExMatch(url, "i)^#t(\d+)i(\d+)$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        if (RegExMatch(url, "i)^macro://(\d+)/(\d+)/?$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        return ""
    }

    _AiEncodeFileUrl(path) {
        p := StrReplace(String(path), "\", "/")
        p := StrReplace(p, "%", "%25")
        p := StrReplace(p, ")", "%29")
        p := StrReplace(p, "(", "%28")
        p := StrReplace(p, " ", "%20")
        return "rmtfile:///" p
    }

    _AiDecodeFileUrl(url) {
        p := String(url)
        p := RegExReplace(p, "^rmtfile:/+", "")
        p := StrReplace(p, "%20", " ")
        p := StrReplace(p, "%28", "(")
        p := StrReplace(p, "%29", ")")
        p := StrReplace(p, "%25", "%")
        p := StrReplace(p, "/", "\")
        return p
    }

    _AiExtractFilePaths(text) {
        paths := []
        pos := 1
        while (RegExMatch(text, "\[([^\]]+)\]\((rmtfile:[^)]+)\)", &m, pos)) {
            paths.Push(this._AiDecodeFileUrl(m[2]))
            pos += StrLen(m[0])
            if (pos < 1)
                break
        }
        return paths
    }

    _AiFileLinkXaml(label, path) {
        this._aiLinkSeq += 1
        id := this._aiLinkSeq
        btn := "AiFile_" id
        mOpen := "AiFileOpen_" id
        mDir := "AiFileDir_" id
        mAll := "AiFileAll_" id
        allPaths := IsObject(this._aiMsgFilePaths) ? this._aiMsgFilePaths.Clone() : [path]
        this._aiPendingFileActs.Push({name: btn, act: "open", path: path, paths: allPaths})
        this._aiPendingFileActs.Push({name: mOpen, act: "open", path: path, paths: allPaths})
        this._aiPendingFileActs.Push({name: mDir, act: "folder", path: path, paths: allPaths})
        this._aiPendingFileActs.Push({name: mAll, act: "folders", path: path, paths: allPaths})
        return '<InlineUIContainer BaselineAlignment="Center">'
            . '<Button Name="' btn '" Cursor="Hand" Background="Transparent" BorderThickness="0"'
            . ' Padding="0" Margin="0,0,2,0" VerticalAlignment="Center"'
            . ' ToolTip="' this._XmlEsc(path) '">'
            . '<Button.ContextMenu><ContextMenu MinWidth="160" Placement="MousePoint"'
            . ' Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" Foreground="{DynamicResource TextMain}">'
            . '<MenuItem Name="' mOpen '" Header="' this._XmlEsc(GetLang("打开")) '"/>'
            . '<MenuItem Name="' mDir '" Header="' this._XmlEsc(GetLang("打开所在文件夹")) '"/>'
            . '<MenuItem Name="' mAll '" Header="' this._XmlEsc(GetLang("打开所有文件夹")) '"/>'
            . '</ContextMenu></Button.ContextMenu>'
            . '<TextBlock Text="' this._XmlEsc(label) '" TextDecorations="Underline"'
            . ' Foreground="{DynamicResource Accent}" FontSize="' this._AiChatBodyFontSize() '" Cursor="Hand"/>'
            . '</Button></InlineUIContainer>'
    }

    OnAiFileMenu(act, *) {
        if (!IsObject(act) || !act.HasProp("act"))
            return
        if (act.act = "open") {
            if (act.path != "" && FileExist(act.path))
                try Run('"' act.path '"')
            return
        }
        paths := (act.HasProp("paths") && Type(act.paths) = "Array") ? act.paths : [act.path]
        if (act.act = "folder")
            paths := [act.path]
        seen := Map()
        for p in paths {
            dir := ""
            SplitPath(p, , &dir)
            if (dir == "" || seen.Has(dir))
                continue
            seen[dir] := true
            if (DirExist(dir))
                try Run('explorer.exe "' dir '"')
        }
    }

    _AiNavLinkXaml(label, tab, idx) {
        this._aiLinkSeq += 1
        name := "AiNav_" this._aiLinkSeq
        this._aiPendingLinks.Push(name)
        tip := GetLang("跳转到宏配置") " T" tab " #" idx
        return '<InlineUIContainer BaselineAlignment="Center">'
            . '<Button Name="' name '" Tag="' tab "|" idx '" Cursor="Hand"'
            . ' Background="Transparent" BorderThickness="0" Padding="0" Margin="0,0,0,0"'
            . ' VerticalAlignment="Center" ToolTip="' this._XmlEsc(tip) '">'
            . '<TextBlock Text="' this._XmlEsc(label) '" TextDecorations="Underline"'
            . ' Foreground="{DynamicResource Accent}" FontSize="' this._AiChatBodyFontSize() '" Cursor="Hand"/>'
            . '</Button></InlineUIContainer>'
    }

    OnAiNavClick(name, *) {
        tag := ""
        try tag := this.ui.Query(name ">Tag")
        if (tag == "" || !InStr(tag, "|"))
            return
        parts := StrSplit(tag, "|")
        if (parts.Length < 2)
            return
        this.NavigateToMacro(Integer(parts[1]), Integer(parts[2]))
    }

    ; 跳转到指定页签下的第 index 个宏，并切到逻辑树以便查看
    NavigateToMacro(tab, index) {
        if (tab < 1 || tab > MySoftData.TableInfo.Length)
            return
        tableItem := MySoftData.TableInfo[tab]
        if (index < 1 || index > tableItem.Items.Length)
            return
        if (!this.aiAssistOpen) {
            this.aiAssistOpen := true
            this._ApplyAiPanelUi()
        }
        this.sidePanelMode := 1
        this._ApplySidePanelMode()
        sameTab := (tab == MainSoftData.TableIndex)
        this._pendingMacroNav := {tab: tab, idx: index}
        if (sameTab) {
            this._pendingMacroNav := ""
            this.SelectSideTreeItem(tab, index)
            return
        }
        if (IsObject(MainSoftData.TabCtrl))
            MainSoftData.TabCtrl.Value := tab
        else {
            o := this._tabOrder
            for i, t in o {
                if (t == tab) {
                    try this.ui.Update("TabControl", "SelectedIndex", String(i - 1))
                    break
                }
            }
        }
    }

    _AiNormalizeNewlines(text, forTextBox := true) {
        text := StrReplace(text, "`r`n", "`n")
        text := StrReplace(text, "`r", "`n")
        text := StrReplace(text, Chr(0x85), "`n")
        text := StrReplace(text, Chr(0x2028), "`n")
        text := StrReplace(text, Chr(0x2029), "`n")
        if (forTextBox)
            return StrReplace(text, "`n", "`r`n")
        return text
    }

    _AiIsStickBottom(t) {
        sh := ""
        try sh := this.ui.Query("SideAiPane_" t ">ScrollableHeight")
        if (sh == "" || !IsNumber(sh) || Float(sh) <= 2)
            return true
        vo := 0, vh := 0, eh := 0
        try vo := Float(this.ui.Query("SideAiPane_" t ">VerticalOffset"))
        try vh := Float(this.ui.Query("SideAiPane_" t ">ViewportHeight"))
        try eh := Float(this.ui.Query("SideAiPane_" t ">ExtentHeight"))
        if (eh <= 0)
            return true
        return (vo + vh >= eh - 12)
    }

    _AiScrollToEndSoon(t) {
        this._aiScrollTab := t
        SetTimer(this.aiScrollTick, -40)
    }

    _AiScrollPending() {
        t := this._aiScrollTab
        if (t < 1)
            return
        try this.ui.Update("SideAiPane_" t, "ScrollToEnd", "")
    }

    OnAiInputChanged(t, state, ctrl, event) {
        this._AiNormalizeInputBox(t)
        this._AiSyncPlaceholder(t)
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
    }

    _AiNormalizeInputBox(t) {
        if (this._aiNormGuard.Has(t) && this._aiNormGuard[t])
            return
        text := ""
        try text := this.ui.Query("AiInput_" t)
        if (text == "")
            return
        norm := this._AiNormalizeNewlines(text, true)
        if (norm == text)
            return
        caret := StrLen(text)
        try {
            v := this.ui.Query("AiInput_" t ">CaretIndex")
            if (v != "")
                caret := Integer(v)
        }
        if (caret < 0)
            caret := 0
        if (caret > StrLen(text))
            caret := StrLen(text)
        newCaret := StrLen(this._AiNormalizeNewlines(SubStr(text, 1, caret), true))
        this._aiNormGuard[t] := true
        try {
            this.ui.Update("AiInput_" t, "Text", norm)
            this.ui.Update("AiInput_" t, "CaretIndex", String(newCaret))
        } finally {
            this._aiNormGuard[t] := false
        }
    }

    OnAiInputEnter(t, state, ctrl, event) {
        mods := ""
        if (IsObject(state) && state.Has("KeyModifiers"))
            mods := state["KeyModifiers"]
        if (InStr(mods, "Shift") || InStr(mods, "Alt")) {
            this._AiInsertNewline(t)
            return
        }
        this._AiSendFrom(t)
    }

    OnAiSendClick(t, state, ctrl, event) {
        if (this._AiIsBusy(t)) {
            this._AiCancelFromUser(t)
            return
        }
        this._AiSendFrom(t)
    }

    OnAiInputPasteKey(t, state, ctrl, event) {
        mods := ""
        if (IsObject(state) && state.Has("KeyModifiers"))
            mods := state["KeyModifiers"]
        if (!InStr(mods, "Ctrl"))
            return
        if (DllCall("IsClipboardFormatAvailable", "UInt", 8) || DllCall("IsClipboardFormatAvailable", "UInt", 2)) {
            if (this._AiPasteClipboardImage(t))
                return
        }
    }

    OnAiMicClick(t, *) {
        if (!IsObject(this._aiRec))
            this._aiRec := Map()
        if (this._aiRec.Has(t) && this._aiRec[t]) {
            this._AiStopRec(t)
            return
        }
        engine := InitSttEngine()
        if (!IsObject(engine) || !engine.IsDllReady()) {
            Toast.Warning(GetLang("语音引擎未就绪"))
            return
        }
        if (!engine.IsStreamReady()) {
            Toast.Warning(GetLang("识别模型未就绪，请先下载模型"))
            return
        }
        if (!engine.StreamBegin()) {
            Toast.Error(GetLang("开始录音失败：") engine._ErrText(engine.StreamGetLastError()))
            return
        }
        this._aiRec[t] := true
        this._aiSttTab := t
        try this.ui.Update("AiMic_" t, "Foreground", "{DynamicResource Accent}")
        try this.ui.Update("AiMic_" t, "ToolTip", GetLang("停止录音"))
        try this.ui.Update("AiInputPh_" t, "Text", GetLang("正在聆听…"))
        this._AiSyncPlaceholder(t)
        SetTimer(this.aiSttTick, 150)
    }

    _AiPollStt() {
        t := this._aiSttTab
        if (t < 1 || !IsObject(this._aiRec) || !this._aiRec.Has(t) || !this._aiRec[t]) {
            SetTimer(this.aiSttTick, 0)
            return
        }
        engine := InitSttEngine()
        live := ""
        try live := engine.StreamPoll()
        if (Trim(live) != "")
            try this.ui.Update("AiInputPh_" t, "Text", live)
    }

    _AiStopRec(t) {
        if (!IsObject(this._aiRec))
            this._aiRec := Map()
        this._aiRec[t] := false
        SetTimer(this.aiSttTick, 0)
        try this.ui.Update("AiMic_" t, "Foreground", "{DynamicResource TextMain}")
        try this.ui.Update("AiMic_" t, "ToolTip", GetLang("语音输入"))
        try this.ui.Update("AiInputPh_" t, "Text", GetLang("询问关于宏的任何问题…"))
        engine := InitSttEngine()
        if (!IsObject(engine))
            return
        if (!engine.StreamEnd(0)) {
            this._AiSyncPlaceholder(t)
            return
        }
        loop 40 {
            st := engine.StreamGetState()
            if (st == 3 || st == 4)
                break
            Sleep(50)
        }
        result := Trim(engine.StreamGetResult())
        if (result != "")
            this._AiAppendInputText(t, result)
        this._AiSyncPlaceholder(t)
    }

    ; 拖入文件：顶部芯片（仅文件名，下划线，整块删除）
    OnAiInputFileDrop(t, state, ctrl, event) {
        files := this._AiParseDropFiles(state)
        if (files.Length < 1)
            return
        for path in files {
            path := Trim(path)
            if (path == "" || !FileExist(path))
                continue
            this._AiAddAttach(t, this._AiIsImageFile(path) ? "image" : "file", path)
        }
    }

    _AiParseDropFiles(state) {
        files := []
        raw := ""
        if (IsObject(state)) {
            if (state.Has("DropFiles") && Type(state["DropFiles"]) = "Array")
                return state["DropFiles"]
            if (state.Has("FileDrop"))
                raw := String(state["FileDrop"])
            else if (state.Has("Drop"))
                raw := String(state["Drop"])
        }
        if (raw == "")
            return files
        for part in StrSplit(raw, "|") {
            p := Trim(part)
            if (p != "")
                files.Push(p)
        }
        return files
    }

    _AiAttachList(t) {
        if (!IsObject(this._aiAttach))
            this._aiAttach := Map()
        if (!this._aiAttach.Has(t))
            this._aiAttach[t] := []
        return this._aiAttach[t]
    }

    _AiIsImageFile(path) {
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        return (ext = "png" || ext = "jpg" || ext = "jpeg" || ext = "gif" || ext = "bmp" || ext = "webp")
    }

    _AiAddAttach(t, kind, path) {
        list := this._AiAttachList(t)
        for a in list {
            if (a["path"] = path)
                return
        }
        this._aiAttachSeq := Integer(this._aiAttachSeq) + 1
        SplitPath(path, &name)
        if (name == "")
            name := path
        list.Push(Map("id", this._aiAttachSeq, "kind", kind, "path", path, "name", name))
        this._AiRefreshAttachBar(t)
    }

    _AiRemoveAttach(t, id) {
        list := this._AiAttachList(t)
        out := []
        for a in list {
            if (Integer(a["id"]) != Integer(id))
                out.Push(a)
        }
        this._aiAttach[t] := out
        this._AiRefreshAttachBar(t)
    }

    _AiClearAttach(t) {
        if (!IsObject(this._aiAttach))
            this._aiAttach := Map()
        this._aiAttach[t] := []
        this._AiRefreshAttachBar(t)
    }

    _AiRefreshAttachBar(t) {
        list := this._AiAttachList(t)
        try this.ui.Update("AiAttachBar_" t, "ClearItems", "")
        if (list.Length < 1) {
            try this.ui.Update("AiAttachBar_" t, "Visibility", "Collapsed")
            this._AiSyncPlaceholder(t)
            this._FitAiInput(t)
            return
        }
        try this.ui.Update("AiAttachBar_" t, "Visibility", "Visible")
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        for a in list {
            id := a["id"]
            if (a["kind"] = "image")
                xaml := this._AiImageChipXaml(t, id, a["path"], ns)
            else
                xaml := this._AiFileChipXaml(t, id, a["name"], ns)
            try this.ui.Update("AiAttachBar_" t, "AddXamlItem", xaml)
            this._AiBindAttachEvents(t, id)
        }
        this._AiSyncPlaceholder(t)
        this._FitAiInput(t)
    }

    _AiBindAttachEvents(t, id) {
        ; 动态 AddXamlItem 后必须 BindEvent，否则引擎未挂 WPF 事件，点击无反应
        try this._Bind("AiAttOpen_" t "_" id, "MouseLeftButtonUp", ObjBindMethod(this, "OnAiAttachOpen", t, id))
        try this._Bind("AiAttDel_" t "_" id, "Click", ObjBindMethod(this, "OnAiAttachDel", t, id))
    }

    _AiFileChipXaml(t, id, name, ns) {
        return this._AiChipWrapXaml(t, id, ns
            , '<TextBlock Name="AiAttOpen_' t '_' id '" Text="' this._XmlEsc(name) '" TextDecorations="Underline"'
            . ' Cursor="Hand" VerticalAlignment="Center" Margin="4,2,4,2" Foreground="{DynamicResource Accent}" FontSize="' this._AiChatBodyFontSize() '"/>')
    }

    _AiImageChipXaml(t, id, path, ns) {
        src := this._AiFileUri(path)
        return this._AiChipWrapXaml(t, id, ns
            , '<Image Name="AiAttOpen_' t '_' id '" Source="' this._XmlEsc(src) '" Width="32" Height="32"'
            . ' Margin="2" Stretch="UniformToFill" Cursor="Hand"/>')
    }

    _AiChipWrapXaml(t, id, ns, inner) {
        del := "AiAttDel_" t "_" id
        return '<Grid ' ns ' Margin="0,0,8,2" Background="Transparent">'
            . '<Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" CornerRadius="3" Padding="4,4,16,4">' inner '</Border>'
            . '<Button Name="' del '" Width="14" Height="14" Padding="0"'
            . ' HorizontalAlignment="Right" VerticalAlignment="Top"'
            . ' Background="{DynamicResource ControlBorder}" BorderThickness="0" Cursor="Hand"'
            . ' ToolTip="' this._XmlEsc(GetLang("删除")) '" Focusable="False" Panel.ZIndex="2">'
            . '<Button.Style><Style TargetType="Button">'
            . '<Setter Property="Opacity" Value="0"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding IsMouseOver, RelativeSource={RelativeSource AncestorType=Grid}}" Value="True">'
            . '<Setter Property="Opacity" Value="1"/>'
            . '</DataTrigger></Style.Triggers></Style></Button.Style>'
            . '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="7" Width="14" Height="14">'
            . '<TextBlock Text="' Chr(0xE711) '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"'
            . ' FontSize="8" Foreground="{DynamicResource TitleBarForeground}"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border></ControlTemplate></Button.Template></Button></Grid>'
    }

    _AiFileUri(path) {
        p := StrReplace(path, "\", "/")
        p := StrReplace(p, " ", "%20")
        if (RegExMatch(p, "^[A-Za-z]:"))
            p := "/" p
        return "file://" p
    }

    OnAiAttachOpen(t, id, *) {
        for a in this._AiAttachList(t) {
            if (Integer(a["id"]) = Integer(id)) {
                try Run('"' a["path"] '"')
                return
            }
        }
    }

    OnAiAttachDel(t, id, *) {
        this._AiRemoveAttach(t, id)
    }

    _AiSyncPlaceholder(t) {
        text := ""
        try text := this.ui.Query("AiInput_" t)
        rec := IsObject(this._aiRec) && this._aiRec.Has(t) && this._aiRec[t]
        hasAtt := this._AiAttachList(t).Length > 0
        vis := (!rec && Trim(text) == "" && !hasAtt) ? "Visible" : "Collapsed"
        try this.ui.Update("AiInputPh_" t, "Visibility", vis)
    }

    _AiPasteClipboardImage(t) {
        dir := A_Temp "\RMT\AiPaste"
        if (!DirExist(dir))
            DirCreate(dir)
        path := dir "\" FormatTime(A_Now, "yyyyMMddHHmmss") "_" Random(100, 999) ".png"
        pBm := 0
        try pBm := Gdip_CreateBitmapFromClipboard()
        if (!pBm)
            return false
        ok := false
        try {
            Gdip_SaveBitmapToFile(pBm, path)
            ok := FileExist(path)
        }
        try Gdip_DisposeImage(pBm)
        if (!ok)
            return false
        this._AiAddAttach(t, "image", path)
        return true
    }

    _AiAppendInputText(t, extra) {
        extra := Trim(extra)
        if (extra == "")
            return
        text := ""
        try text := this.ui.Query("AiInput_" t)
        text := this._AiNormalizeNewlines(text, true)
        if (text != "" && !RegExMatch(text, "[`r`n\s]$"))
            text .= " "
        text .= extra
        try this.ui.Update("AiInput_" t, "Text", text)
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
        this._AiSyncPlaceholder(t)
    }

    _AiConsumeAttachText(t) {
        list := this._AiAttachList(t)
        if (list.Length < 1)
            return ""
        out := ""
        for a in list {
            name := a["name"]
            path := a["path"]
            out .= (out == "" ? "" : " ") "[" name "](" this._AiEncodeFileUrl(path) ")"
        }
        this._AiClearAttach(t)
        return (out == "") ? "" : "`n" out
    }

    _AiInsertNewline(t) {
        try this.ui.Update("AiInput_" t, "InsertText", "`r`n")
        caret := ""
        try caret := this.ui.Query("AiInput_" t ">CaretIndex")
        if (caret != "" && IsNumber(caret))
            this._aiPendingCaret[t] := Integer(caret)
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
    }

    _FitAiInputCur() {
        this._FitAiInput(this._aiFitTab)
    }

    _AiInputContentWidth(t) {
        w := 0
        try {
            v := this.ui.Query("AiInputHost_" t ">ActualWidth")
            if (v != "" && IsNumber(v))
                w := Float(v) - AiSettingGui.ContentPadL * 2
        }
        if (w < 40) {
            try {
                v := this.ui.Query("AiInput_" t ">ActualWidth")
                if (v != "" && IsNumber(v))
                    w := Float(v)
            }
        }
        if (w >= 40) {
            if (!IsObject(this._aiInputBoxW))
                this._aiInputBoxW := Map()
            this._aiInputBoxW[t] := w
            return w
        }
        if (IsObject(this._aiInputBoxW) && this._aiInputBoxW.Has(t) && this._aiInputBoxW[t] >= 40)
            return this._aiInputBoxW[t]
        pw := this.aiPanelW
        if (!IsNumber(pw) || pw < 80)
            pw := this._AiPanelDefaultW()
        return Max(80, pw - 20 - AiSettingGui.ContentPadL * 2)
    }

    _AiInputTextPx(s) {
        fs := Float(XAMLHost.ChatBodyFontSize())
        if (fs < 10)
            fs := 12
        px := 0.0
        i := 1
        len := StrLen(s)
        while (i <= len) {
            o := Ord(SubStr(s, i, 1))
            if (o >= 0x2E80)
                px += fs
            else if (o == 9)
                px += fs * 2
            else
                px += fs * 0.55
            i += 1
        }
        return px
    }

    _AiInputLayout(t, text, &vis, &lastRatio) {
        vis := 1
        lastRatio := 0.0
        raw := this._AiNormalizeNewlines(text, false)
        if (raw == "")
            return
        boxW := this._AiInputContentWidth(t)
        if (boxW < 1)
            boxW := 1
        vis := 0
        lastPx := 0.0
        for line in StrSplit(raw, "`n") {
            px := this._AiInputTextPx(line)
            if (px <= 0) {
                vis += 1
                lastPx := 0.0
                continue
            }
            n := Integer((px - 0.01) / boxW) + 1
            if (n < 1)
                n := 1
            vis += n
            lastPx := px - (n - 1) * boxW
        }
        if (vis < 1)
            vis := 1
        lastRatio := lastPx / boxW
    }

    _AiInputKeepWide(t, lastRatio) {
        if (!IsObject(this._aiInputWide))
            this._aiInputWide := Map()
        this._aiInputWide[t] := (lastRatio >= 0.8)
        return this._aiInputWide[t]
    }

    _FitAiInput(t) {
        if (t < 1)
            return
        lineH := this._AiInputLineH()
        extraH := this._AiInputExtraLineH()
        maxLines := this._AiInputMaxLines()
        text := ""
        try text := this.ui.Query("AiInput_" t)
        vis := 1
        lastRatio := 0.0
        this._AiInputLayout(t, text, &vis, &lastRatio)
        lines := vis
        if (this._AiInputKeepWide(t, lastRatio))
            lines += 1
        if (lines < 1)
            lines := 1
        if (lines > maxLines)
            lines := maxLines
        multi := lines > 1
        chromeH := multi ? (lineH + (lines - 1) * extraH + 2) : lineH
        textH := chromeH - 2
        if (textH < lineH - 2)
            textH := lineH - 2
        pad := this._AiInputPad(lines)
        vca := multi ? "Top" : "Center"
        sb := lines >= maxLines ? "Auto" : (multi ? "Disabled" : "Hidden")
        try this.ui.Update("AiInput_" t, "Height", String(textH))
        try this.ui.Update("AiInput_" t, "MinHeight", String(multi ? extraH : (lineH - 2)))
        try this.ui.Update("AiInput_" t, "Margin", "0")
        try this.ui.Update("AiInput_" t, "Padding", "0")
        try this.ui.Update("AiInput_" t, "VerticalContentAlignment", vca)
        try this.ui.Update("AiInput_" t, "VerticalScrollBarVisibility", sb)
        try this.ui.Update("AiInputHost_" t, "Height", String(chromeH + this._AiAttachHostExtra(t)))
        try this.ui.Update("AiInputHost_" t, "Padding", pad)
        try this.ui.Update("AiInputPh_" t, "VerticalAlignment", vca)
        try this.ui.Update("AiInputPh_" t, "Margin", "0")
        try this.ui.Update("AiInputBtns_" t, "VerticalAlignment", multi ? "Bottom" : "Center")
        try this.ui.Update("AiInputBtns_" t, "Margin", multi ? "0,0,0,1" : "0")
        if (IsObject(this._aiPendingCaret) && this._aiPendingCaret.Has(t)) {
            try this.ui.Update("AiInput_" t, "CaretIndex", String(this._aiPendingCaret[t]))
            this._aiPendingCaret.Delete(t)
        }
        this._AiSyncPlaceholder(t)
    }

    _AiAttachHostExtra(t) {
        if (this._AiAttachList(t).Length < 1)
            return 0
        return this._AiAttachBarH()
    }

    _AiSendFrom(t) {
        text := ""
        try text := this.ui.Query("AiInput_" t)
        text := Trim(this._AiNormalizeNewlines(text, false), "`n")
        if (text == "" && this._AiAttachList(t).Length < 1)
            return
        if (this._AiIsBusy(t)) {
            Toast.Info(GetLang("正在等待上一条回复…"))
            return
        }
        AiAssist.EnsureDefaults()
        if (!AiAssist.IsConfigured()) {
            Toast.Warning(GetLang("请先在设置中填写 API Key、API URL 与模型"))
            AiSettingGui.ShowGui()
            return
        }
        this._aiBusy[t] := true
        if (!IsObject(this._aiCancel))
            this._aiCancel := Map()
        this._aiCancel[t] := false
        if (!IsObject(this._aiEmptyRetry))
            this._aiEmptyRetry := Map()
        this._aiEmptyRetry[t] := false
        this._aiChatTab := t
        if (!IsObject(this._aiToolRound))
            this._aiToolRound := Map()
        this._aiToolRound[t] := 0
        this._AiClearToolNotes(t)
        this._AiSetSendMode(t, true)
        this._AiShowThinking(t, false, GetLang("正在分析你的问题"))
        try this.ui.Update("AiInput_" t, "Text", "")
        try {
            if (IsObject(this._aiInputWide))
                this._aiInputWide[t] := false
            attTxt := this._AiConsumeAttachText(t)
            if (attTxt != "")
                text := Trim(text attTxt)
            this._FitAiInput(t)
            try this._AiAppendMsg(t, true, text)
            catch
                this._AiAppendMsg(t, true, this._AiPlainAttachLabel(text))
            try this._AiHistPush(t, "user", text)
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
            return
        }
        SetTimer(this.aiStartTick, -30)
    }

    _AiStartChat(*) {
        t := this._aiChatTab
        if (t < 1)
            return
        try {
            msgs := this._AiBuildApiMessages(t)
            AiAssist.BeginChat(msgs)
            SetTimer(this.aiChatTick, 200)
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
        }
    }

    _AiPlainAttachLabel(text) {
        t := Trim(RegExReplace(String(text), "\[([^\]]+)\]\(rmtfile:[^)]+\)", "$1"))
        return (t != "") ? t : GetLang("附件")
    }

    _AiErrText(e) {
        errMsg := IsObject(e) && e.HasProp("Message") ? e.Message : String(e)
        if (IsObject(e) && e.HasProp("File") && e.File != "")
            errMsg .= "`n" e.File (e.HasProp("Line") ? ":" e.Line : "")
        return errMsg
    }

    _AiPollChat() {
        t := this._aiChatTab
        if (t < 1) {
            SetTimer(this.aiChatTick, 0)
            return
        }
        if (this._AiCancelRequested(t)) {
            this._AiFinishChat(t, "", "", true)
            return
        }
        st := 0
        try st := AiAssist.ChatState()
        catch {
            this._AiFinishChat(t, "", GetLang("无法读取请求状态"))
            return
        }
        if (st == 1) {
            this._AiPulseThinking(t)
            return
        }
        if (st == 0) {
            ; idle：可能尚未 latch，或结果已被另一轮 Take 取走；勿当成「中断」清掉 busy
            return
        }
        reply := ""
        errMsg := ""
        try reply := AiAssist.TakeChat()
        catch as e
            errMsg := this._AiErrText(e)
        if (errMsg == "" && this._AiContinueTools(t, reply))
            return
        this._AiFinishChat(t, reply, errMsg)
    }

    _AiContinueTools(t, reply) {
        payload := AiAssist.ParseToolPayload(reply)
        if (!IsObject(payload))
            return false
        calls := (payload.Has("calls") && Type(payload["calls"]) = "Array") ? payload["calls"] : []
        if (calls.Length < 1)
            return false
        if (!IsObject(this._aiToolRound))
            this._aiToolRound := Map()
        rnd := this._aiToolRound.Has(t) ? Integer(this._aiToolRound[t]) : 0
        if (this._AiCancelRequested(t))
            return false
        if (rnd >= 8) {
            this._aiToolRound[t] := 0
            return false
        }
        this._aiToolRound[t] := rnd + 1
        this._AiShowThinking(t, true, GetLang("正在调用工具"))
        content := payload.Has("content") ? String(payload["content"]) : ""
        tcParts := ""
        for call in calls {
            if (Type(call) != "Map")
                continue
            cid := call.Has("id") ? String(call["id"]) : ("call_" A_Index)
            name := call.Has("name") ? String(call["name"]) : ""
            args := call.Has("arguments") ? String(call["arguments"]) : "{}"
            if (tcParts != "")
                tcParts .= ","
            tcParts .= '{"id":"' AiAssist._JsonEsc(cid) '","type":"function","function":{"name":"' AiAssist._JsonEsc(name) '","arguments":"' AiAssist._JsonEsc(args) '"}}'
        }
        asst := Map("role", "assistant", "content", content, "tool_calls", "[" tcParts "]")
        reason := AiAssist.ReasoningOf(payload)
        if (reason != "")
            asst["reasoning_content"] := reason
        this._AiHistPushMap(t, asst)
        for call in calls {
            if (Type(call) != "Map")
                continue
            cid := call.Has("id") ? String(call["id"]) : ("call_" A_Index)
            name := call.Has("name") ? String(call["name"]) : ""
            args := call.Has("arguments") ? String(call["arguments"]) : "{}"
            this._AiShowThinking(t, true, this._AiToolDoingText(name, args))
            result := AiAssist.ExecTool(name, args)
            this._AiNoteToolResult(t, name, args, result)
            this._AiHistPushMap(t, Map("role", "tool", "content", result, "tool_call_id", cid))
        }
        this._AiShowThinking(t, false, GetLang("正在根据工具结果继续思考"))
        try {
            msgs := this._AiBuildApiMessages(t)
            AiAssist.BeginChat(msgs)
            SetTimer(this.aiChatTick, 200)
            return true
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
            return true
        }
    }

    _AiFinishChat(t, reply, errMsg, cancelled := false) {
        SetTimer(this.aiChatTick, 0)
        if (!IsObject(this._aiBusy))
            this._aiBusy := Map()
        if (cancelled || this._AiCancelRequested(t)) {
            this._aiBusy[t] := false
            if (!IsObject(this._aiCancel))
                this._aiCancel := Map()
            this._aiCancel[t] := false
            if (IsObject(this._aiToolRound) && this._aiToolRound.Has(t))
                this._aiToolRound[t] := 0
            this._AiSetSendMode(t, false)
            this._AiHideThinking(t)
            msg := GetLang("（已取消）")
            this._AiAppendMsg(t, false, msg)
            try this._AiHistPush(t, "assistant", msg)
            this._AiClearToolNotes(t)
            return
        }
        if (errMsg != "") {
            this._aiBusy[t] := false
            if (IsObject(this._aiToolRound) && this._aiToolRound.Has(t))
                this._aiToolRound[t] := 0
            this._AiSetSendMode(t, false)
            this._AiHideThinking(t)
            fail := GetLang("请求失败") "：`n" errMsg
            this._AiAppendMsg(t, false, fail)
            try this._AiHistPush(t, "assistant", fail)
            this._AiClearToolNotes(t)
            return
        }
        payload := AiAssist.ParseToolPayload(reply)
        reason := ""
        if (IsObject(payload) && payload.Has("content"))
            reply := String(payload["content"])
        if (IsObject(payload))
            reason := AiAssist.ReasoningOf(payload)
        reply := Trim(reply)
        if (reply == "")
            reply := Trim(this._AiComposeToolReply(t))
        if (reply == "" && !this._AiEmptyRetried(t)) {
            this._AiRetryEmptyReply(t)
            return
        }
        this._aiBusy[t] := false
        if (IsObject(this._aiToolRound) && this._aiToolRound.Has(t))
            this._aiToolRound[t] := 0
        this._AiSetSendMode(t, false)
        this._AiHideThinking(t)
        if (reply == "")
            reply := GetLang("这次没有生成说明。请再试一次，或把目标宏说得更具体（例如 1:2、触发键、要做的动作）。")
        else if (this._AiHasPermissionFail(t) && !InStr(reply, "写入权限") && !InStr(reply, "完全访问")) {
            extra := this._AiComposeToolFailReply(t)
            if (extra != "")
                reply .= "`n`n" extra
        }
        asst := Map("role", "assistant", "content", reply)
        if (reason != "")
            asst["reasoning_content"] := reason
        try this._AiHistPushMap(t, asst)
        this._AiAppendMsg(t, false, reply)
        this._AiClearToolNotes(t)
        if (IsObject(this._aiEmptyRetry))
            this._aiEmptyRetry[t] := false
    }

    _AiIsBusy(t) {
        return IsObject(this._aiBusy) && this._aiBusy.Has(t) && this._aiBusy[t]
    }

    _AiCancelRequested(t) {
        return IsObject(this._aiCancel) && this._aiCancel.Has(t) && this._aiCancel[t]
    }

    _AiCancelFromUser(t) {
        if (!IsObject(this._aiCancel))
            this._aiCancel := Map()
        this._aiCancel[t] := true
        this._aiChatTab := t
        AiAssist.CancelChat()
        this._AiFinishChat(t, "", "", true)
    }

    _AiSetSendMode(t, busy) {
        glyph := busy ? Chr(0xE769) : Chr(0xE724)
        tip := busy ? GetLang("取消") : GetLang("发送")
        try this.ui.Update("AiSend_" t, "Content", glyph)
        try this.ui.Update("AiSend_" t, "ToolTip", tip)
        try this.ui.Update("AiSend_" t, "IsEnabled", "True")
    }

    _AiEmptyRetried(t) {
        return IsObject(this._aiEmptyRetry) && this._aiEmptyRetry.Has(t) && this._aiEmptyRetry[t]
    }

    _AiRetryEmptyReply(t) {
        if (!IsObject(this._aiEmptyRetry))
            this._aiEmptyRetry := Map()
        this._aiEmptyRetry[t] := true
        this._aiBusy[t] := true
        this._aiChatTab := t
        this._AiSetSendMode(t, true)
        this._AiShowThinking(t, false, GetLang("正在整理回复"))
        this._AiHistPush(t, "user", "请用中文说明刚才的结果或无法完成的原因，不要空回复。")
        try {
            msgs := this._AiBuildApiMessages(t)
            AiAssist.BeginChat(msgs)
            SetTimer(this.aiChatTick, 200)
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
        }
    }

    _AiThinkLabel(t) {
        if (IsObject(this._aiThinkDetail) && this._aiThinkDetail.Has(t) && Trim(this._aiThinkDetail[t]) != "")
            return this._aiThinkDetail[t]
        if (IsObject(this._aiThinkMode) && this._aiThinkMode.Has(t) && this._aiThinkMode[t] = "edit")
            return GetLang("正在编辑")
        return GetLang("正在思考")
    }

    _AiShowThinking(t, editing := false, detail := "") {
        if (!IsObject(this._aiThinkPhase))
            this._aiThinkPhase := Map()
        if (!IsObject(this._aiThinkMode))
            this._aiThinkMode := Map()
        if (!IsObject(this._aiThinkDetail))
            this._aiThinkDetail := Map()
        this._aiThinkPhase[t] := 0
        this._aiThinkMode[t] := editing ? "edit" : "think"
        if (detail != "")
            this._aiThinkDetail[t] := detail
        else if (!this._aiThinkDetail.Has(t) || this._aiThinkDetail[t] == "")
            this._aiThinkDetail[t] := editing ? GetLang("正在编辑") : GetLang("正在思考")
        try this.ui.Update("AiThinkTxt_" t, "Text", this._AiThinkLabel(t) "…")
        try this.ui.Update("AiThinkTxt_" t, "Visibility", "Visible")
    }

    _AiPulseThinking(t) {
        if (!IsObject(this._aiThinkPhase))
            this._aiThinkPhase := Map()
        phase := this._aiThinkPhase.Has(t) ? Integer(this._aiThinkPhase[t]) : 0
        phase := Mod(phase + 1, 4)
        this._aiThinkPhase[t] := phase
        dots := ""
        loop phase
            dots .= "."
        if (dots == "")
            dots := "…"
        try this.ui.Update("AiThinkTxt_" t, "Text", this._AiThinkLabel(t) dots)
    }

    _AiHideThinking(t) {
        if (IsObject(this._aiThinkMode) && this._aiThinkMode.Has(t))
            this._aiThinkMode[t] := "think"
        if (IsObject(this._aiThinkDetail) && this._aiThinkDetail.Has(t))
            this._aiThinkDetail[t] := ""
        try this.ui.Update("AiThinkTxt_" t, "Visibility", "Collapsed")
    }

    _AiToolArgPath(argsJson) {
        try {
            obj := JSON.parse(argsJson)
            if (Type(obj) = "Map") {
                if (obj.Has("path") && Trim(String(obj["path"])) != "")
                    return String(obj["path"])
                if (obj.Has("command") && Trim(String(obj["command"])) != "")
                    return String(obj["command"])
            }
        } catch {
        }
        return ""
    }

    _AiToolDoingText(name, argsJson) {
        path := this._AiToolArgPath(argsJson)
        SplitPath(path, &fn)
        switch name {
            case "write_file":
                return GetLang("正在写入文件") (fn != "" ? "：" fn : "")
            case "read_file":
                return GetLang("正在读取文件") (fn != "" ? "：" fn : "")
            case "list_dir":
                return GetLang("正在列出目录") (path != "" ? "：" path : "")
            case "run_command":
                return GetLang("正在执行命令")
            case "run_script":
                return GetLang("正在运行脚本") (fn != "" ? "：" fn : "")
            case "update_macro":
                return GetLang("正在修改宏")
            case "add_macro":
                return GetLang("正在新增宏")
            case "list_macros":
                return GetLang("正在查看宏列表")
            case "read_macro":
                return GetLang("正在读取宏")
            default:
                return GetLang("正在调用") " " name
        }
    }

    _AiNoteToolResult(t, name, argsJson, result) {
        if (!IsObject(this._aiToolNotes))
            this._aiToolNotes := Map()
        if (!this._aiToolNotes.Has(t))
            this._aiToolNotes[t] := []
        ok := true
        err := ""
        try {
            obj := JSON.parse(result)
            if (Type(obj) = "Map") {
                if (obj.Has("ok") && !obj["ok"])
                    ok := false
                if (obj.Has("error"))
                    err := String(obj["error"])
            }
        } catch {
        }
        path := this._AiToolArgPath(argsJson)
        this._aiToolNotes[t].Push(Map("name", name, "ok", ok, "error", err, "path", path))
        if (!ok && err != "")
            this._AiShowThinking(t, true, GetLang("工具失败") "：" this._AiShortErr(err))
    }

    _AiShortErr(err) {
        e := Trim(RegExReplace(String(err), "[\r\n]+", " "))
        if (StrLen(e) > 48)
            return SubStr(e, 1, 48) "…"
        return e
    }

    _AiHasPermissionFail(t) {
        if (!IsObject(this._aiToolNotes) || !this._aiToolNotes.Has(t))
            return false
        for n in this._aiToolNotes[t] {
            if (Type(n) != "Map" || !n.Has("error"))
                continue
            e := String(n["error"])
            if (InStr(e, "工作区") || InStr(e, "写入权限") || InStr(e, "完全访问") || InStr(e, "permission"))
                return true
        }
        return false
    }

    _AiComposeToolReply(t) {
        fail := this._AiComposeToolFailReply(t)
        if (fail != "")
            return fail
        if (!IsObject(this._aiToolNotes) || !this._aiToolNotes.Has(t))
            return ""
        okN := 0
        failN := 0
        done := ""
        for n in this._aiToolNotes[t] {
            if (Type(n) != "Map")
                continue
            nm := n.Has("name") ? String(n["name"]) : ""
            if (n.Has("ok") && n["ok"]) {
                okN += 1
                if (nm = "update_macro")
                    done := GetLang("已按你的要求改好对应宏")
                else if (nm = "add_macro" && done == "")
                    done := GetLang("已新增宏")
            } else
                failN += 1
        }
        if (okN < 1 && failN < 1)
            return ""
        if (okN > 0 && failN < 1)
            return (done != "" ? done : GetLang("操作已完成")) "。" GetLang("如需调整请继续说明。")
        if (okN > 0)
            return GetLang("部分操作已完成，另有步骤失败。请换种说法再试，或检查目标宏是否存在。")
        return GetLang("操作未成功。请检查目标宏是否存在，或把页签和序号说得更具体。")
    }

    _AiComposeToolFailReply(t) {
        if (!this._AiHasPermissionFail(t))
            return ""
        lines := []
        lines.Push(GetLang("写入失败：当前写入权限为「工作区」，不能写到桌面等软件目录以外的位置。"))
        lines.Push(GetLang("请到「AI 设置 → 写入权限」改为「完全访问」后再试。"))
        seen := Map()
        for n in this._aiToolNotes[t] {
            if (Type(n) != "Map" || (n.Has("ok") && n["ok"]))
                continue
            p := n.Has("path") ? Trim(n["path"]) : ""
            if (p != "" && !seen.Has(p)) {
                seen[p] := true
                lines.Push("")
                fence := Chr(96) Chr(96) Chr(96)
                lines.Push(GetLang("目标："))
                lines.Push(fence)
                lines.Push(p)
                lines.Push(fence)
            }
        }
        out := ""
        for line in lines
            out .= (out == "" ? "" : "`n") line
        return out
    }

    _AiClearToolNotes(t) {
        if (IsObject(this._aiToolNotes) && this._aiToolNotes.Has(t))
            this._aiToolNotes[t] := []
    }

    _AiHistPush(t, role, content) {
        this._AiHistPushMap(t, Map("role", role, "content", content))
    }

    _AiHistPushMap(t, m) {
        if (!IsObject(this._aiHist))
            this._aiHist := Map()
        if (!this._aiHist.Has(t))
            this._aiHist[t] := []
        this._aiHist[t].Push(m)
        this._AiPersistSession(t)
    }

    AiGetSessionId(t) {
        if (!IsObject(this._aiSessionId) || !this._aiSessionId.Has(t))
            return ""
        return String(this._aiSessionId[t])
    }

    ; saveCurrent=true 时先落盘当前会话再清空
    AiNewChat(t, saveCurrent := true, showToast := true) {
        t := Integer(t)
        if (t < 1)
            return
        if (saveCurrent)
            this._AiPersistSession(t)
        this._AiClearChatUi(t)
        if (!IsObject(this._aiHist))
            this._aiHist := Map()
        this._aiHist[t] := []
        if (!IsObject(this._aiSessionId))
            this._aiSessionId := Map()
        this._aiSessionId[t] := ""
        if (!IsObject(this._aiSeededTabs))
            this._aiSeededTabs := Map()
        this._aiSeededTabs[t] := true  ; 阻止再次注入演示对话
        if (showToast)
            Toast.Success(GetLang("已新建对话"))
    }

    AiLoadSession(t, id) {
        t := Integer(t)
        id := Trim(String(id))
        if (t < 1 || id == "")
            return
        sess := AiChatStore.Get(id)
        if (!IsObject(sess)) {
            Toast.Warning(GetLang("找不到该对话记录"))
            return
        }
        ; 切换前保存当前（不同会话时）
        curId := this.AiGetSessionId(t)
        if (curId != "" && curId != id)
            this._AiPersistSession(t)
        else if (curId == "" && IsObject(this._aiHist) && this._aiHist.Has(t) && this._aiHist[t].Length > 0)
            this._AiPersistSession(t)

        msgs := []
        if (sess.Has("messages") && Type(sess["messages"]) = "Array") {
            for m in sess["messages"] {
                if (Type(m) != "Map")
                    continue
                role := m.Has("role") ? String(m["role"]) : "user"
                content := m.Has("content") ? String(m["content"]) : ""
                if (role = "tool" || role = "system" || Trim(content) == "")
                    continue
                rec := Map("role", role, "content", content)
                if (m.Has("tool_calls"))
                    rec["tool_calls"] := String(m["tool_calls"])
                if (m.Has("reasoning_content") && m["reasoning_content"] != "")
                    rec["reasoning_content"] := String(m["reasoning_content"])
                msgs.Push(rec)
            }
        }
        this._AiClearChatUi(t)
        if (!IsObject(this._aiHist))
            this._aiHist := Map()
        this._aiHist[t] := msgs.Clone()
        if (!IsObject(this._aiSessionId))
            this._aiSessionId := Map()
        this._aiSessionId[t] := id
        if (!IsObject(this._aiSeededTabs))
            this._aiSeededTabs := Map()
        this._aiSeededTabs[t] := true
        for m in msgs
            this._AiAppendMsg(t, m["role"] = "user", m["content"])
        Toast.Success(GetLang("已打开对话"))
    }

    _AiPersistAllTabs() {
        if (!IsObject(this._aiHist))
            return
        for t, _ in this._aiHist
            this._AiPersistSession(t)
    }

    _AiPersistSession(t) {
        if (!IsObject(this._aiHist) || !this._aiHist.Has(t))
            return
        msgs := this._aiHist[t]
        if (Type(msgs) != "Array" || msgs.Length < 1)
            return
        if (!IsObject(this._aiSessionId))
            this._aiSessionId := Map()
        curId := this._aiSessionId.Has(t) ? String(this._aiSessionId[t]) : ""
        newId := ""
        try newId := AiChatStore.Upsert(curId, msgs)
        if (newId != "")
            this._aiSessionId[t] := newId
        try {
            if (AiHistoryGui.instances.Has("main")) {
                inst := AiHistoryGui.instances["main"]
                if (IsObject(inst) && !inst.closed)
                    inst._RefreshList()
            }
        }
    }

    _AiClearChatUi(t) {
        try this.ui.Update("SideAiMsgs_" t, "ClearItems", "")
        this._AiHideThinking(t)
    }

    _AiBuildApiMessages(t) {
        msgs := []
        msgs.Push(Map("role", "system", "content", AiAssist.BuildSystemPrompt()))
        if (IsObject(this._aiHist) && this._aiHist.Has(t)) {
            arr := this._aiHist[t]
            start := 1
            maxKeep := 24
            if (arr.Length > maxKeep)
                start := arr.Length - maxKeep + 1
            i := start
            while (i <= arr.Length) {
                m := arr[i]
                if (Type(m) = "Map")
                    msgs.Push(this._AiApiMessage(m))
                i++
            }
        }
        return msgs
    }

    _AiApiMessage(m) {
        role := m.Has("role") ? String(m["role"]) : "user"
        content := m.Has("content") ? String(m["content"]) : ""
        if (role = "user")
            content := this._AiExpandAttachForApi(content)
        out := Map("role", role, "content", content)
        if (m.Has("tool_calls"))
            out["tool_calls"] := m["tool_calls"]
        if (m.Has("tool_call_id"))
            out["tool_call_id"] := m["tool_call_id"]
        if (m.Has("reasoning_content") && m["reasoning_content"] != "")
            out["reasoning_content"] := m["reasoning_content"]
        else if (m.Has("reasoning") && m["reasoning"] != "")
            out["reasoning_content"] := m["reasoning"]
        if (m.Has("raw"))
            out["raw"] := m["raw"]
        return out
    }

    _AiExpandAttachForApi(text) {
        paths := this._AiExtractFilePaths(text)
        if (paths.Length < 1)
            return text
        display := Trim(RegExReplace(text, "\[([^\]]+)\]\(rmtfile:[^)]+\)", "$1"))
        extra := ""
        for path in paths {
            extra .= this._AiReadAttachBody(path)
        }
        return Trim(display) extra
    }

    _AiReadAttachBody(path) {
        if (path == "" || !FileExist(path))
            return "`n`n[文件不存在] " path
        SplitPath(path, &name, , &ext)
        ext := StrLower(ext)
        if (RegExMatch(ext, "i)^(png|jpe?g|gif|bmp|webp|ico)$"))
            return "`n`n[图片] " name " 路径: " path
        maxChars := 24000
        raw := ""
        try {
            f := FileOpen(path, "r", "UTF-8")
            raw := f.Read(maxChars + 1)
            f.Close()
        } catch {
            try {
                f := FileOpen(path, "r")
                raw := f.Read(maxChars + 1)
                f.Close()
            } catch {
                return "`n`n[无法读取] " name " 路径: " path
            }
        }
        if (StrLen(raw) > maxChars)
            raw := SubStr(raw, 1, maxChars) "`n…(已截断)"
        fence := Chr(96) Chr(96) Chr(96)
        return "`n`n### 附件 " name "`n路径: " path "`n" fence ext "`n" raw "`n" fence
    }

    ; ============ 宏列表渲染 ============
    ReadTabValues(tableItem) {
        t := tableItem.Index
        if (this._useVirtual.Has(t))
            return  ; Epic5：VL_CHANGE 已逐字段写回模型，此处 no-op
        ; 收集所有需读取的控件名，单次批量 Query（一次 daemon 往返），替代逐项轮询
        names := []
        for f, fold in tableItem.Folds {
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                if (!this._IsRendered(t, i))
                    continue
                names.Push("Remark_" t "_" i)
                names.Push("TKType_" t "_" i ">SelectedIndex")
                names.Push("Loop_" t "_" i)
            }
            names.Push("FoldRemark_" t "_" f)
            names.Push("FoldFront_" t "_" f)
            names.Push("FoldTKType_" t "_" f ">SelectedIndex")
            names.Push("FoldTK_" t "_" f)
        }
        if (names.Length == 0)
            return
        state := this.ui.Query(names*)

        for f, fold in tableItem.Folds {
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                if (!this._IsRendered(t, i))
                    continue
                if (state.Has("Remark_" t "_" i))
                    try item.Remark := state["Remark_" t "_" i]
                if (state.Has("TKType_" t "_" i ">SelectedIndex"))
                    try item.TriggerType := Integer(state["TKType_" t "_" i ">SelectedIndex"]) + 1
                if (state.Has("Loop_" t "_" i))
                    try item.LoopCount := (state["Loop_" t "_" i] == GetLang("无限")) ? "-1" : state["Loop_" t "_" i]
            }
            if (state.Has("FoldRemark_" t "_" f))
                try fold.Remark := state["FoldRemark_" t "_" f]
            if (state.Has("FoldFront_" t "_" f))
                try fold.FrontInfo := state["FoldFront_" t "_" f]
            if (state.Has("FoldTKType_" t "_" f ">SelectedIndex"))
                try fold.TKType := Integer(state["FoldTKType_" t "_" f ">SelectedIndex"]) + 1
            if (state.Has("FoldTK_" t "_" f))
                try fold.TK := state["FoldTK_" t "_" f]
        }
    }

    _IsRendered(t, i) {
        return this.RenderedItems.Has(t) && this.RenderedItems[t].Has(i)
    }

    RenderTab(tableItem) {
        t := tableItem.Index
        ; 非宏表（Tool/Setting/Help/Reward/Thank）用专用 Panel_ 构建，不走 FoldList 渲染
        if (!this._useVirtual.Has(t) && !CheckIsItemTable(t))
            return
        if (this._useVirtual.Has(t)) {
            ; Epic5：1 次 VL_INIT 填充虚拟列表（模型已由 VL_CHANGE 保持，视图全量重建成本 O(1) IPC）
            this._vl.Init(t, tableItem)
            if (this._IsAiPanelOpen())
                this._vl.SetCompact(t, true)
            return
        }
        this.RenderedItems[t] := Map()
        listName := "FoldList_" t
        this.ui.Update(listName, "ClearItems", "")
        ; B: 每模块 1 次 AddXamlItem 批量渲染（整组一个根 StackPanel），不再逐行 N 次桥接往返。
        ;    注意不能增量逐批加子项：StackPanel 每加一个子项就全量重测量（增量 = O(n²)），整组一次加 = O(n)。
        ; A: 折叠行也全渲染进 FoldItems_<t>_<f> 子容器，折叠切换只切容器 Visibility 不重建（千条级折叠/展开瞬间，滚动位置保留）
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        for f, fold in tableItem.Folds {
            vis := fold.FoldState ? ' Visibility="Collapsed"' : ""
            xaml := '<StackPanel ' ns '>'
                . this._BuildFoldTitleRow(t, f, f == 1)
                . '<StackPanel Name="FoldItems_' t '_' f '"' vis '>'
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                xaml .= this._BuildItemRow(t, i)
                this.RenderedItems[t][i] := true
            }
            xaml .= '</StackPanel></StackPanel>'
            this.ui.Update(listName, "AddXamlItem", xaml)
        }
        ; 绑定须在 AddXamlItem 之后（控件已存在）
        ; 折叠态行隐藏且事件不可达：跳过 BindEvent（千条级折叠组省 ~9×N 次桥接往返），
        ; 展开折叠时由 OnFoldBtnClick 补绑（_Bind 清旧再挂，幂等）
        for f, fold in tableItem.Folds {
            if (fold.FoldState)
                continue
            for i, item in tableItem.Items {
                if (item.FoldID != fold.ID)
                    continue
                this._BindItemRow(t, i)
            }
        }
        this._BindFoldRows(t)
    }

    _BuildFoldTitleRow(t, f, isFirst := false) {
        fold := MySoftData.TableInfo[t].Folds[f]
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        foldBg := fold.ForbidState ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource FoldHeaderBg}"
        xaml := '<Border ' ns ' Name="FoldCard_' t '_' f '" CornerRadius="0" BorderThickness="0" BorderBrush="{DynamicResource OutlineStroke}" Background="' foldBg '" Margin="0" Padding="8,6,8,6"' this._BorderSnap() '>'
            . '<StackPanel Name="FoldCardInner_' t '_' f '" Opacity="' (fold.ForbidState ? this._ForbidContentOpacity() : "1") '" VerticalAlignment="Center" TextElement.FontSize="' XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11)) '">'
            . this._BuildFoldDividerXaml(false, isFirst)
            . this._BuildFoldHeaderRowXaml(t, f, fold, false)
        if (isMenu || isUI) {
            xaml .= '<StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,4,0,0">'
                . '<TextBlock Text="' (isUI ? GetLang("面板触发键：") : GetLang("菜单触发键：")) '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'
                . '<ComboBox Name="FoldTKType_' t '_' f '" Width="70" Height="24" MinHeight="24" Margin="2,0,10,0" SelectedIndex="' (fold.TKType - 1) '" IsEnabled="' (isUI ? "False" : "True") '">'
                . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
                . '</ComboBox>'
                . '<TextBox Name="FoldTK_' t '_' f '" Text="' this._XmlEsc(fold.TK) '" Width="100" Height="24" VerticalContentAlignment="Center" TextAlignment="Center"/>'
                . '<Button Name="FoldTKEdit_' t '_' f '" Content="' GetLang("编辑") '" Height="24" MinHeight="24" Padding="8,0" Margin="6,0,0,0"/>'
                . '</StackPanel>'
        }
        xaml .= '</StackPanel></Border>'
        return xaml
    }

    ; 模块头主行：备注 | 间距 | 前台 | 同距 | 操作按钮 | 剩余
    _BuildFoldHeaderRowXaml(t, f, fold, vlMode) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        folded := vlMode ? false : fold.FoldState
        remark := vlMode ? "" : fold.Remark
        frontInfo := vlMode ? "" : fold.FrontInfo
        forbidState := vlMode ? false : fold.ForbidState
        gap := this._FoldGroupGap()
        if (this._IsAiPanelOpen()) {
            wideGap := 8 + this._foldFrontShift
            gapCol := '<ColumnDefinition Width="100*" MinWidth="' this._AiPanelGapMin() '" MaxWidth="' wideGap '"/>'
            lastCol := '<ColumnDefinition Width="*"/>'
        } else {
            gapCol := '<ColumnDefinition Width="' gap '"/>'
            lastCol := '<ColumnDefinition Width="*"/>'
        }
        return '<Grid ' ns ' VerticalAlignment="Center">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="Auto"/>' gapCol
            . '<ColumnDefinition Width="Auto"/>' gapCol
            . '<ColumnDefinition Width="Auto"/>' lastCol
            . '</Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">' this._BuildFoldCollapseBtnXaml(t, f, folded, vlMode) this._BuildFoldRemarkFieldXaml(t, f, remark, vlMode) '</StackPanel>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">' this._BuildFoldFrontCenterXaml(t, f, frontInfo, vlMode) '</StackPanel>'
            . '<StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center">' this._BuildFoldToolbarXaml(t, f, forbidState, vlMode) '</StackPanel>'
            . '</Grid>'
    }

    _BuildFoldCollapseBtnXaml(t, f, folded, vlMode) {
        iconStyle := ' Style="{StaticResource RmtIconBtn}"'
        if (vlMode) {
            return '<Button Tag="FoldBtn" Width="24" Height="24" MinHeight="24" Margin="0,0,6,0" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12">'
                . '<Button.Style><Style TargetType="Button" BasedOn="{StaticResource RmtIconBtn}">'
                . '<Setter Property="Content" Value="&#xE70D;"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Folded}" Value="True"><Setter Property="Content" Value="&#xE76C;"/></DataTrigger></Style.Triggers>'
                . '</Style></Button.Style></Button>'
        }
        foldGlyph := folded ? "&#xE76C;" : "&#xE70D;"
        return '<Button Name="FoldBtn_' t '_' f '" Width="24" Height="24" MinHeight="24" Margin="0,0,6,0"' iconStyle '>'
            . '<TextBlock Name="FoldGlyph_' t '_' f '" Text="' foldGlyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Button>'
    }

    ; 模块头专用样式：输入框左内边距与占位符对齐；工具按钮悬停跟主题色
    _BuildFoldRowStyles() {
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        fieldBox := '<Style x:Key="RmtFoldFieldBox" TargetType="TextBox">'
            . '<Setter Property="FontSize" Value="' foldFs '"/>'
            . '<Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Height" Value="24"/>'
            . '<Setter Property="Padding" Value="1,0,1,0"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="TextAlignment" Value="Left"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1.25"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">'
            . '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"' this._BorderSnap() '>'
            . '<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>'
            . '</Border></ControlTemplate></Setter.Value></Setter>'
            . '<Style.Triggers>'
            . '<Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="1"/><Setter Property="FontSize" Value="' foldFs '"/></Trigger>'
            . '<Trigger Property="IsReadOnly" Value="True"><Setter Property="FontSize" Value="' foldFs '"/></Trigger>'
            . '</Style.Triggers></Style>'
        chatBox := '<Style x:Key="RmtAiChatBox" TargetType="TextBox">'
            . '<Setter Property="FontSize" Value="' this._AiChatBodyFontSize() '"/>'
            . '<Setter Property="MinHeight" Value="' (this._AiInputLineH() - 2) '"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="TextWrapping" Value="Wrap"/>'
            . '<Setter Property="AcceptsReturn" Value="True"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="TextAlignment" Value="Left"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="VerticalScrollBarVisibility" Value="Hidden"/>'
            . '<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">'
            . '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="' this._AiInputRadius() '"' this._BorderSnap() '>'
            . '<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>'
            . '</Border></ControlTemplate></Setter.Value></Setter></Style>'
        aiIconBtn := '<Style x:Key="RmtAiIconBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="22"/><Setter Property="Height" Value="22"/><Setter Property="MinHeight" Value="22"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextSub}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="3" Width="22" Height="22">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBgHover}"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        aiMsgBox := '<Style x:Key="RmtAiMsgBox" TargetType="RichTextBox">'
            . '<Setter Property="FontSize" Value="' this._AiChatBodyFontSize() '"/>'
            . '<Setter Property="IsReadOnly" Value="True"/>'
            . '<Setter Property="IsDocumentEnabled" Value="True"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="VerticalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="IsUndoEnabled" Value="False"/>'
            . '<Setter Property="CaretBrush" Value="Transparent"/>'
            . '<Setter Property="Cursor" Value="IBeam"/>'
            . '<Setter Property="Tag" Value="PassScroll"/>'
            . '</Style>'
        toolBtn := '<Style x:Key="RmtFoldToolBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="24"/><Setter Property="Height" Value="24"/><Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0,0,4,0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter Property="BorderThickness" Value="1.25"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd") '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        primaryBtn := StrReplace(toolBtn, 'x:Key="RmtFoldToolBtn"', 'x:Key="RmtItemPrimaryBtn"')
        primaryBtn := StrReplace(primaryBtn, 'Width" Value="24"', 'Width" Value="48"')
        editBtn := StrReplace(toolBtn, 'x:Key="RmtFoldToolBtn"', 'x:Key="RmtItemEditBtn"')
        editBtn := StrReplace(editBtn, 'Width" Value="24"', 'Width" Value="64"')
        forbidBtn := '<Style x:Key="RmtFoldForbidBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="24"/><Setter Property="Height" Value="24"/><Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0,0,4,0"/>'
            . '<Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>'
            . '<Setter Property="FontSize" Value="12"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter Property="BorderThickness" Value="1.25"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="False"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsMouseOver}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</MultiDataTrigger>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="False"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsPressed}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</MultiDataTrigger>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True">'
            . '<Setter Property="Foreground" Value="{DynamicResource ActionText}"/>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionStroke}"/>'
            . '</DataTrigger>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="True"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsMouseOver}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</MultiDataTrigger>'
            . '<MultiDataTrigger><MultiDataTrigger.Conditions>'
            . '<Condition Binding="{Binding FoldForbid}" Value="True"/>'
            . '<Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsPressed}" Value="True"/>'
            . '</MultiDataTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionPressBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</MultiDataTrigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        itemForbid := StrReplace(forbidBtn, 'x:Key="RmtFoldForbidBtn"', 'x:Key="RmtItemForbidBtn"')
        itemForbid := StrReplace(itemForbid, 'Binding="{Binding FoldForbid}"', 'Binding="{Binding Forbid}"')
        itemFieldBtn := '<Style x:Key="RmtItemFieldBtn" TargetType="Button">'
            . '<Setter Property="Height" Value="24"/><Setter Property="MinHeight" Value="24"/>'
            . '<Setter Property="Padding" Value="4,0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1.25"/>'
            . '<Setter Property="SnapsToDevicePixels" Value="True"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd") '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        itemCombo := '<Style x:Key="RmtItemCombo" TargetType="ComboBox">'
            . '<Style.Resources><Style TargetType="TextBox">'
            . '<Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="MinHeight" Value="0"/><Setter Property="MinWidth" Value="0"/>'
            . '<Setter Property="VerticalAlignment" Value="Center"/><Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">'
            . '<ScrollViewer x:Name="PART_ContentHost" Background="Transparent" VerticalAlignment="Center" Margin="0"/>'
            . '</ControlTemplate></Setter.Value></Setter></Style></Style.Resources>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1.25"/>'
            . '<Setter Property="MinHeight" Value="24"/><Setter Property="Height" Value="24"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Padding" Value="4,0,20,0"/>'
            . '<Setter Property="SnapsToDevicePixels" Value="True"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">'
            . '<Grid' this._BorderSnap() '>'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"' this._BorderSnap() '/>'
            . '<ToggleButton Background="Transparent" BorderThickness="0" Focusable="False" ClickMode="Press" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">'
            . '<ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent">'
            . '<Path Fill="{DynamicResource TextMain}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0" Data="M 0 0 L 4 4 L 8 0 Z"/>'
            . '</Border></ControlTemplate></ToggleButton.Template></ToggleButton>'
            . '<ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"/>'
            . '<TextBox x:Name="PART_EditableTextBox" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="{TemplateBinding Padding}" Focusable="True" Background="Transparent" Foreground="{TemplateBinding Foreground}" BorderThickness="0" Visibility="Hidden" IsReadOnly="{TemplateBinding IsReadOnly}"/>'
            . '<Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">'
            . '<Border x:Name="DropDownBorder" Background="{DynamicResource DropdownBg}" BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="3" Margin="0,4,0,0" Width="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="350">'
            . '<ScrollViewer Margin="0" SnapsToDevicePixels="True" Tag="ContainScroll"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>'
            . '</Border></Popup></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsEditable" Value="True"><Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/><Setter TargetName="ContentSite" Property="Visibility" Value="Hidden"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        railW := this._AiRailW()
        railHoverW := this._AiRailHoverW()
        tabW := this._AiTabW()
        aiRail := '<Style x:Key="RmtAiRailBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="' railW '"/><Setter Property="MinWidth" Value="' railW '"/>'
            . '<Setter Property="MaxWidth" Value="' railHoverW '"/>'
            . '<Setter Property="Height" Value="200"/>'
            . '<Setter Property="MinHeight" Value="200"/><Setter Property="MaxHeight" Value="200"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Grid>'
            . '<Path x:Name="Bd" Data="M 18,0 L 18,200 L 0,176 L 0,24 Z" Stretch="Fill"'
            . ' Fill="{DynamicResource ControlBg}" Stroke="{DynamicResource OutlineStroke}" StrokeThickness="1.5"'
            . ' StrokeLineJoin="Round" SnapsToDevicePixels="True"/>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="-3,0,0,0"/>'
            . '</Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter Property="Width" Value="' railHoverW '"/>'
            . '<Setter TargetName="Bd" Property="Fill" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Fill" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        sideModeTab := '<Style x:Key="RmtSideModeTab" TargetType="Button">'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="5,4"/>'
            . '<Setter Property="Width" Value="' tabW '"/>'
            . '<Setter Property="MinWidth" Value="' tabW '"/>'
            . '<Setter Property="MaxWidth" Value="' tabW '"/>'
            . '<Setter Property="Height" Value="28"/>'
            . '<Setter Property="MinHeight" Value="28"/>'
            . '<Setter Property="MaxHeight" Value="28"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Center"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Grid Height="28" ClipToBounds="True">'
            . '<Border x:Name="Bd" Background="Transparent" BorderThickness="0" Padding="{TemplateBinding Padding}" Cursor="Hand" CornerRadius="0">'
            . '<Grid>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource TextMain}" TextElement.FontSize="14" TextElement.FontWeight="SemiBold"/>'
            . '<Ellipse x:Name="SelDot" Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-3,-1,-3" Visibility="Collapsed" IsHitTestVisible="False"/>'
            . '</Grid></Border></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="Tag" Value="first"><Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/></Trigger>'
            . '<Trigger Property="Tag" Value="last"><Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/></Trigger>'
            . '<Trigger Property="Tag" Value="sel-first"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/><Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/><Setter TargetName="SelDot" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="Tag" Value="sel-last"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/><Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/><Setter TargetName="SelDot" Property="Visibility" Value="Visible"/></Trigger>'
            . '<MultiTrigger><MultiTrigger.Conditions>'
            . '<Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="sel-first"/>'
            . '</MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/>'
            . '<Setter TargetName="Bd" Property="CornerRadius" Value="4,0,0,4"/>'
            . '</MultiTrigger>'
            . '<MultiTrigger><MultiTrigger.Conditions>'
            . '<Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="sel-last"/>'
            . '</MultiTrigger.Conditions>'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/>'
            . '<Setter TargetName="Bd" Property="CornerRadius" Value="0,4,4,0"/>'
            . '</MultiTrigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        sideTreeItem := '<Style x:Key="RmtSideTreeItem" TargetType="ListBoxItem">'
            . '<Setter Property="Height" Value="28"/><Setter Property="MinHeight" Value="28"/>'
            . '<Setter Property="Padding" Value="8,0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="HorizontalContentAlignment" Value="Stretch"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" Height="28">'
            . '<TextBlock Text="{Binding}" VerticalAlignment="Center" FontSize="12" TextTrimming="CharacterEllipsis" Foreground="{TemplateBinding Foreground}"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="ItemsControl.AlternationIndex" Value="1"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListRowAltBg}"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource TabSelBg}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        return fieldBox . chatBox . aiIconBtn . aiMsgBox . toolBtn . primaryBtn . editBtn . forbidBtn . itemForbid . itemFieldBtn . itemCombo . aiRail . sideModeTab . sideTreeItem
    }

    ; 模块头输入框：RmtFoldFieldBox 覆盖全局 TextBox Padding=12，保证与占位符左对齐
    _FoldFieldBoxAttrs(extra := "") {
        return ' Style="{StaticResource RmtFoldFieldBox}"' extra
    }

    _BuildDragHandleXaml() {
        dot := '<Ellipse Width="3" Height="3" Fill="{DynamicResource TextSub}" Opacity="0.7" Margin="1"/>'
        return '<Button Tag="DragHandle" Style="{StaticResource RmtIconBtn}" Width="22" Height="24" MinHeight="24" ToolTip="' GetLang("拖拽调整顺序") '" VerticalAlignment="Center" HorizontalAlignment="Center" Cursor="Arrow">'
            . '<UniformGrid Rows="3" Columns="2" Width="10" Height="14" IsHitTestVisible="False">'
            . dot dot dot dot dot dot
            . '</UniformGrid></Button>'
    }

    _ItemDragColW() {
        return 38
    }

    ; 控件高度用 24：100%/125%/150%/200% DPI 下都是整数物理像素。
    ; 26×125%=32.5，窗口 UseLayoutRounding 取整后底边 1px 会被裁掉。
    _CtrlH() {
        return 24
    }

    ; 描边禁止 UseLayoutRounding（与窗口取整叠加会吞底边）。不用 Aliased：125% DPI 下会把 1DIP 收成 1 物理像素，边框发丝细。
    _BorderSnap() {
        return ' SnapsToDevicePixels="True" UseLayoutRounding="False"'
    }

    _IsAiPanelOpen() {
        return this.HasOwnProp("aiAssistOpen") && this.aiAssistOpen
    }

    _FoldGroupGap() {
        return this._IsAiPanelOpen() ? this._AiPanelGapMin() : (8 + this._foldFrontShift)
    }

    ; 宏行列宽：备注右缘对齐模块备注；触发键对齐「语音宏」左分割线；组间距统一用备注→触发键间距
    _ItemLayoutWide() {
        tabW := 80
        toTab := 2
        inner0 := 4 + this._ItemDragColW()
        colorW := 20
        seqW := 22
        remarkW := (8 + 24 + 6 + this._foldFieldW) - inner0 - colorW - seqW
        tkW := 125
        typeW := 82
        editCol := 68
        loopCol := 86
        settingCol := 48
        tkLeft := tabW * 4 - toTab - inner0
        spacerTK := tkLeft - (colorW + seqW + remarkW)
        if (spacerTK < 0)
            spacerTK := 0
        spacerTK += 35
        return Map("color", colorW, "seq", seqW, "remark", remarkW
            , "spacerTK", spacerTK, "tk", tkW, "type", typeW
            , "spacerEdit", spacerTK, "edit", editCol, "loop", loopCol, "setting", settingCol
            , "spacerCopy", spacerTK)
    }

    _ItemLayout() {
        L := this._ItemLayoutWide()
        if (this._IsAiPanelOpen()) {
            g := this._AiPanelGapMin()
            L["spacerTK"] := g
            L["spacerEdit"] := g
            L["spacerCopy"] := g
        }
        return L
    }

    _ItemInnerColDefs() {
        L := this._ItemLayoutWide()
        if (this._IsAiPanelOpen()) {
            minG := this._AiPanelGapMin()
            maxG := L["spacerTK"]
            sp := '<ColumnDefinition Width="100*" MinWidth="' minG '" MaxWidth="' maxG '"/>'
            return '<ColumnDefinition Width="' L["color"] '"/><ColumnDefinition Width="' L["seq"] '"/><ColumnDefinition Width="' L["remark"] '"/>'
                . sp . '<ColumnDefinition Width="' L["tk"] '"/><ColumnDefinition Width="' L["type"] '"/>'
                . sp . '<ColumnDefinition Width="' L["edit"] '"/><ColumnDefinition Width="' L["loop"] '"/><ColumnDefinition Width="' L["setting"] '"/>'
                . sp . '<ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>'
        }
        return '<ColumnDefinition Width="' L["color"] '"/><ColumnDefinition Width="' L["seq"] '"/><ColumnDefinition Width="' L["remark"] '"/>'
            . '<ColumnDefinition Width="' L["spacerTK"] '"/><ColumnDefinition Width="' L["tk"] '"/><ColumnDefinition Width="' L["type"] '"/>'
            . '<ColumnDefinition Width="' L["spacerEdit"] '"/><ColumnDefinition Width="' L["edit"] '"/><ColumnDefinition Width="' L["loop"] '"/><ColumnDefinition Width="' L["setting"] '"/>'
            . '<ColumnDefinition Width="' L["spacerCopy"] '"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>'
    }

    _BuildItemCardOpen(ns := "", t := 0, i := 0, forbid := false, rowSel := false) {
        nsAttr := ns != "" ? " " ns : ""
        nameAttr := t > 0 ? ' Name="ItemCard_' t '_' i '"' : ""
        defBg := rowSel ? "{DynamicResource TabSelBg}" : ((t > 0 && forbid) ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource ControlBg}")
        ; 宏行贴在页签内容框里，不再自绘左右/底边；高度 30（内边距 3+3，内容 24）。
        return '<Border' nsAttr nameAttr ' BorderBrush="{DynamicResource OutlineStroke}" ClipToBounds="False"' this._BorderSnap() '>'
            . '<Border.Style><Style TargetType="Border">'
            . '<Setter Property="CornerRadius" Value="0"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Padding" Value="4,3,6,3"/>'
            . '<Setter Property="Background" Value="' defBg '"/>'
            . '<Setter Property="Height" Value="30"/>'
            . '<Setter Property="MinHeight" Value="30"/>'
            . '<Setter Property="MaxHeight" Value="30"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding IsAltRow}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowAltBg}"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding Forbid}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowForbidBg}"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowForbidBg}"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding RowSel}" Value="True"><Setter Property="Background" Value="{DynamicResource TabSelBg}"/></DataTrigger>'
            . '</Style.Triggers></Style></Border.Style>'
            . '<Grid Height="24" VerticalAlignment="Center"' this._ItemForbidOpacityAttrs(t == 0, t, i, forbid) '>'
            . this._ItemForbidOpacityStyle(t == 0)
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="' this._ItemDragColW() '"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Grid Grid.Column="0" VerticalAlignment="Stretch" HorizontalAlignment="Stretch" ClipToBounds="False">'
            . this._BuildRowSelDotXaml(t == 0, t, i, rowSel)
            . this._BuildRowSelIconXaml(t == 0, t, i, rowSel)
            . '<Grid VerticalAlignment="Center" HorizontalAlignment="Left" Margin="12,0,2,0">' this._BuildDragHandleXaml() '</Grid>'
            . '</Grid>'
            . '<Grid Grid.Column="1" Height="24">'
    }

    _ItemCardClose() {
        return '</Grid></Grid></Border>'
    }

    ; 禁用时内容整体变淡（边框/文字一起暗淡），不靠深色底
    _ItemForbidOpacityAttrs(vlMode, t := 0, i := 0, forbid := false) {
        if (vlMode)
            return ""
        return ' Name="ItemCardInner_' t '_' i '" Opacity="' (forbid ? this._ForbidContentOpacity() : "1") '"'
    }

    _ForbidContentOpacity() {
        return "0.42"
    }

    _ItemForbidOpacityStyle(vlMode) {
        if (!vlMode)
            return ""
        op := this._ForbidContentOpacity()
        return '<Grid.Style><Style TargetType="Grid"><Setter Property="Opacity" Value="1"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding Forbid}" Value="True"><Setter Property="Opacity" Value="' op '"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Opacity" Value="' op '"/></DataTrigger>'
            . '</Style.Triggers></Style></Grid.Style>'
    }

    _BuildRowSelDotXaml(vlMode, t := 0, i := 0, rowSel := false) {
        if (vlMode) {
            return '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-3,-3,0,0" IsHitTestVisible="False">'
                . '<Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding RowSel}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Ellipse.Style></Ellipse>'
        }
        vis := rowSel ? "Visible" : "Collapsed"
        return '<Grid Name="RowSelDot_' t '_' i '" Visibility="' vis '" HorizontalAlignment="Left" VerticalAlignment="Top" IsHitTestVisible="False">'
            . '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" Margin="-3,-3,0,0"/>'
            . '</Grid>'
    }

    _BuildRowSelIconXaml(vlMode, t := 0, i := 0, rowSel := false) {
        body := CmdKeyRightIconXaml("{DynamicResource Accent}", 15, 12, "2.1")
        if (vlMode) {
            return '<Grid HorizontalAlignment="Left" VerticalAlignment="Center">'
                . '<Grid.Style><Style TargetType="Grid"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding RowSel}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Grid.Style>' body '</Grid>'
        }
        vis := rowSel ? "Visible" : "Collapsed"
        return '<Grid Name="RowSelMark_' t '_' i '" Visibility="' vis '" HorizontalAlignment="Left" VerticalAlignment="Center">' body '</Grid>'
    }

    _BuildSeqNoXaml(vlMode, t := 0, i := 0, rowSel := false) {
        seqText := vlMode ? "{Binding SeqNo}" : (i ".")
        nameBtn := vlMode ? ' Tag="Seq"' : ' Name="SeqBtn_' t '_' i '" Tag="Seq"'
        btn := '<Button' nameBtn ' Cursor="Hand" Focusable="False" HorizontalAlignment="Left" VerticalAlignment="Center" Background="Transparent" BorderThickness="0" Padding="0">'
            . '<Button.Template><ControlTemplate TargetType="Button"><Border Background="Transparent" Padding="2,0,4,0"><ContentPresenter VerticalAlignment="Center"/></Border></ControlTemplate></Button.Template>'
            . '<TextBlock Text="' seqText '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '</Button>'
        return '<Grid Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="-15,0,0,0">'
            . btn
            . '</Grid>'
    }

    _BuildFoldDividerXaml(vlMode, isFirst := false) {
        ; 左右缩进的浅色细线，避开输入框上下边，避免三条线叠在一起。
        rect := '<Rectangle Height="1" Margin="10,2,10,8" Fill="{DynamicResource FoldDivider}" SnapsToDevicePixels="True"'
        if (vlMode) {
            return rect . '>'
                . '<Rectangle.Style><Style TargetType="Rectangle">'
                . '<Setter Property="Visibility" Value="Visible"/>'
                . '<Style.Triggers>'
                . '<DataTrigger Binding="{Binding IsFirstFold}" Value="True"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
                . '</Style.Triggers></Style></Rectangle.Style></Rectangle>'
        }
        if (isFirst)
            return ""
        return rect . '/>'
    }

    _BuildFoldCardBorderOpen() {
        return '<Border BorderBrush="{DynamicResource OutlineStroke}" ClipToBounds="False"' this._BorderSnap() '>'
            . '<Border.Style><Style TargetType="Border">'
            . '<Setter Property="Background" Value="{DynamicResource FoldHeaderBg}"/>'
            . '<Setter Property="CornerRadius" Value="0"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Padding" Value="8,6,8,6"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Background" Value="{DynamicResource ListRowForbidBg}"/></DataTrigger>'
            . '</Style.Triggers></Style></Border.Style>'
    }

    _BuildTKBtnInnerXaml(tkStr, vlMode) {
        kb := '&#xE92E;'
        if (vlMode) {
            return '<Grid>'
                . '<Viewbox Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Stretch" VerticalAlignment="Center">'
                . '<Viewbox.Style><Style TargetType="Viewbox"><Setter Property="Visibility" Value="Visible"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding TKStr}" Value=""><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers>'
                . '</Style></Viewbox.Style>'
                . '<TextBlock Text="{Binding TKStr}" TextWrapping="NoWrap" TextAlignment="Center" FontSize="14"/>'
                . '</Viewbox>'
                . '<TextBlock Text="' kb '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center">'
                . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding TKStr}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></TextBlock.Style></TextBlock>'
                . '</Grid>'
        }
        if (tkStr == "")
            return '<TextBlock Text="' kb '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
        return '<Viewbox Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Stretch" VerticalAlignment="Center">'
            . '<TextBlock Text="' this._XmlEsc(tkStr) '" TextWrapping="NoWrap" TextAlignment="Center" FontSize="14"/>'
            . '</Viewbox>'
    }

    _BuildFoldRemarkFieldXaml(t, f, remark, vlMode) {
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        ph := this._XmlEsc(GetLang("请输入备注信息"))
        fw := this._foldFieldW
        box := this._FoldFieldBoxAttrs()
        if (vlMode) {
            ; 占位符绑 TextBox.Text（模板内局部名），按键即隐；不绑 FoldRemark（LostFocus 才回写）
            return '<Grid Width="' fw '" Height="24" MinHeight="24">'
                . '<TextBox Name="FoldRemarkBox" Tag="FoldRemark" Text="{Binding FoldRemark}"' box '/>'
                . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
                . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=FoldRemarkBox}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></TextBlock.Style></TextBlock></Grid>'
        }
        return '<Grid Width="' fw '" Height="24" MinHeight="24">'
            . '<TextBox Name="FoldRemark_' t '_' f '" Text="' this._XmlEsc(remark) '"' box '/>'
            . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
            . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=FoldRemark_' t '_' f '}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
            . '</Style></TextBlock.Style></TextBlock></Grid>'
    }

    _BuildItemRemarkFieldXaml(t, i, remark, vlMode) {
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        ph := this._XmlEsc(GetLang("请输入备注信息"))
        box := this._FoldFieldBoxAttrs(' ToolTip="' GetLang("备注") '"')
        if (vlMode) {
            ; 占位符绑 TextBox.Text（模板内局部名），按键即隐；不绑 Remark（LostFocus 才回写）
            return '<Grid Grid.Column="2" Height="24" MinHeight="24" Margin="-5,0,0,0">'
                . '<TextBox Name="RemarkBox" Tag="Remark" Text="{Binding Remark}"' box '/>'
                . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
                . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=RemarkBox}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></TextBlock.Style></TextBlock></Grid>'
        }
        return '<Grid Grid.Column="2" Height="24" MinHeight="24" Margin="-5,0,0,0">'
            . '<TextBox Name="Remark_' t '_' i '" Text="' this._XmlEsc(remark) '"' box '/>'
            . '<TextBlock Text="' ph '" IsHitTestVisible="False" VerticalAlignment="Center" Margin="1,0,1,0" HorizontalAlignment="Left" Foreground="{DynamicResource TextSub}" Opacity="0.55" FontSize="' foldFs '">'
            . '<TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=Remark_' t '_' i '}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
            . '</Style></TextBlock.Style></TextBlock></Grid>'
    }

    _BuildFoldFrontCenterXaml(t, f, frontInfo, vlMode) {
        fw := this._foldFrontW
        box := this._FoldFieldBoxAttrs(' IsReadOnly="True" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled"')
        iconFont := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
        frontIcon := '<TextBlock Text="&#xE7F4;" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"' iconFont ' Margin="0,0,4,0" ToolTip="' GetLang("前台") '"/>'
        if (vlMode) {
            return frontIcon
                . '<TextBox Tag="FoldFront" Text="{Binding FoldFront}" Width="' fw '"' box '/>'
                . '<Button Tag="FoldFrontBtn" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE70F;" ToolTip="' GetLang("编辑") '"' iconFont ' Margin="4,0,0,0"/>'
        }
        return frontIcon
            . '<TextBox Name="FoldFront_' t '_' f '" Text="' this._XmlEsc(frontInfo) '" Width="' fw '"' box '/>'
            . '<Button Name="FoldFrontBtn_' t '_' f '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE70F;" ToolTip="' GetLang("编辑") '"' iconFont ' Margin="4,0,0,0"/>'
    }

    _BuildItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        item := tableItem.Items[i]
        isMacro := CheckIsMacroTable(t)
        isNormal := CheckIsNormalTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isSubMacro := CheckIsSubMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isVoice := GetTableSymbol(t) == "Voice"

        if (isVoice) {
            ; 语音宏：触发键列显示唤醒词
            tkStr := item.VoiceKeywords
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        } else {
            tkStr := isTiming ? GetLang("定时") : FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        }
        loopStr := item.LoopCount == "-1" ? GetLang("无限") : item.LoopCount
        colorState := item.ColorState
        colorHex := colorState == 1 ? "#2E7D32" : colorState == 2 ? "#F9A825" : colorState == 3 ? "#C62828" : "Transparent"
        tkTypeIdx := item.TriggerType - 1
        if (isUI)
            tkTypeIdx := 3

        if (isNormal && tkStr == GetLang("编辑"))
            tkStr := ""
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        rowSel := this._sideTreeSel.Has(t) && this._sideTreeSel[t] == item.ID
        xaml := this._BuildItemCardOpen(ns, t, i, item.Forbid || GetItemFoldForbidState(tableItem, i), rowSel)
            . '<Grid.ColumnDefinitions>' this._ItemInnerColDefs() '</Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Name="Color_' t '_' i '" Width="12" Height="12" CornerRadius="6" Background="' colorHex '" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . this._BuildSeqNoXaml(false, t, i, rowSel)
            . this._BuildItemRemarkFieldXaml(t, i, item.Remark, false)
            . '<Button Grid.Column="4" Name="TKBtn_' t '_' i '" Style="{StaticResource RmtItemFieldBtn}" Margin="0,0,4,0" ToolTip="' GetLang("触发键") '" IsEnabled="' (isSubMacro ? "False" : "True") '">' this._BuildTKBtnInnerXaml(tkStr, false) '</Button>'
            . '<ComboBox Grid.Column="5" Name="TKType_' t '_' i '" Style="{StaticResource RmtItemCombo}" Margin="0" SelectedIndex="' tkTypeIdx '" IsEnabled="' (isNormal ? "True" : "False") '" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . this._BuildItemEditBtnXaml(t, i, item, false)
            . '<ComboBox Grid.Column="8" Name="Loop_' t '_' i '" Style="{StaticResource RmtItemCombo}" Margin="0,0,4,0" IsEditable="True" IsEnabled="' (isMacro ? "True" : "False") '" ToolTip="' GetLang("循环次数") '">'
            . '<ComboBoxItem Content="' GetLang("无限") '"/>'
            . '</ComboBox>'
            . '<Button Grid.Column="9" Name="Setting_' t '_' i '" Style="{StaticResource RmtItemPrimaryBtn}" Margin="0" Content="&#xE713;" ToolTip="' GetLang("设置") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"/>'
            . '<StackPanel Grid.Column="11" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Name="Copy_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE8C8;" ToolTip="' GetLang("复制") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . this._BuildItemForbidBtnXaml(t, i, item.Forbid, false)
            . '<Button Name="Del_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE74D;" ToolTip="' GetLang("删除") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0"/>'
            . '</StackPanel>'
            . this._ItemCardClose()
        return xaml
    }

    _BuildItemEditBtnInnerXaml(vlMode, t := 0, i := 0, kind := 0) {
        iconAttr := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"'
        x := '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
            . '<TextBlock Text="&#xE945;"' iconAttr '/>'
            . '<TextBlock Text="&#xE72C;" Margin="1,0,0,0"' iconAttr '/>'
        if (vlMode) {
            x .= '<TextBlock' iconAttr '>'
                . '<TextBlock.Style><Style TargetType="TextBlock">'
                . '<Setter Property="Visibility" Value="Collapsed"/>'
                . '<Setter Property="Margin" Value="2,0,0,0"/>'
                . '<Style.Triggers>'
                . '<DataTrigger Binding="{Binding EditKind}" Value="1">'
                . '<Setter Property="Visibility" Value="Visible"/>'
                . '<Setter Property="Text" Value="&#xE71D;"/>'
                . '<Setter Property="Margin" Value="2,0,0,0"/>'
                . '</DataTrigger>'
                . '<DataTrigger Binding="{Binding EditKind}" Value="2">'
                . '<Setter Property="Visibility" Value="Visible"/>'
                . '<Setter Property="Text" Value="&#xE8F1;"/>'
                . '<Setter Property="Margin" Value="3,0,0,0"/>'
                . '</DataTrigger>'
                . '</Style.Triggers></Style></TextBlock.Style></TextBlock>'
        } else {
            vis := kind = 0 ? "Collapsed" : "Visible"
            glyph := kind = 2 ? "&#xE8F1;" : "&#xE71D;"
            gap := kind = 2 ? "3,0,0,0" : "2,0,0,0"
            x .= '<TextBlock Name="EditGlyph3_' t '_' i '" Text="' glyph '" Visibility="' vis '" Margin="' gap '"' iconAttr '/>'
        }
        return x . '</StackPanel>'
    }

    _BuildItemEditBtnXaml(t, i, item, vlMode) {
        tip := GetLang("编辑")
        col := ' Grid.Column="7"'
        if (vlMode)
            return '<Button' col ' Tag="Edit" Style="{StaticResource RmtItemEditBtn}" ToolTip="' tip '">' this._BuildItemEditBtnInnerXaml(true) '</Button>'
        kind := GetMacroEditKind(item.Macro)
        return '<Button' col ' Name="Edit_' t '_' i '" Style="{StaticResource RmtItemEditBtn}" ToolTip="' tip '">' this._BuildItemEditBtnInnerXaml(false, t, i, kind) '</Button>'
    }

    _BuildItemForbidBtnXaml(t, i, forbidState, vlMode) {
        if (vlMode) {
            return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
                . '<Button Tag="Forbid" Content="&#xE25B;" ToolTip="' GetLang("禁用") '" Style="{StaticResource RmtItemForbidBtn}"/>'
                . '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,6,0" IsHitTestVisible="False">'
                . '<Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding Forbid}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Ellipse.Style></Ellipse></Grid>'
        }
        actBg := forbidState ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}"
        actBr := forbidState ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}"
        actFg := forbidState ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}"
        dotVis := forbidState ? "Visible" : "Collapsed"
        return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
            . '<Button Name="Forbid_' t '_' i '" Tag="Forbid" Content="&#xE25B;" ToolTip="' GetLang("禁用") '" Style="{StaticResource RmtFoldToolBtn}"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
            . ' Background="' actBg '" BorderBrush="' actBr '" Foreground="' actFg '"/>'
            . '<Grid Name="ForbidDot_' t '_' i '" Visibility="' dotVis '"><Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,2,0" IsHitTestVisible="False"/></Grid>'
            . '</Grid>'
    }

    _BindItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        isMacro := CheckIsMacroTable(t)
        isTriggerStr := CheckIsStringMacroTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"

        editTK := isTriggerStr ? OnItemEditTriggerStr : OnItemEditTriggerKey
        editTK := isTiming ? OnItemEditTiming : editTK
        editTK := isMenu ? OnItemMenuMacroSettingClick : editTK
        editMacro := isMacro ? OnItemEditMacro : OnItemEditReplaceKey
        if (isUI)
            editTK := OnUIMacroSettingClick
        else if (GetTableSymbol(t) == "Voice")
            editTK := OnItemVoiceTriggerSetting   ; 语音宏：触发键列点击 → 语音触发编辑弹窗（填唤醒词）

        loopStr := tableItem.Items[i].LoopCount == "-1" ? GetLang("无限") : tableItem.Items[i].LoopCount
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)

        this._Bind("SeqBtn_" t "_" i, "Click", ObjBindMethod(this, "SelectSideTreeItem", t, i))
        this._Bind("TKBtn_" t "_" i, "Click", editTK.Bind(tableItem, i))
        this._Bind("TKBtn_" t "_" i, "MouseRightButtonUp", OnItemCustomEditTriggerStr.Bind(tableItem, i))
        this._Bind("Setting_" t "_" i, "Click", OnItemEditMacroSetting.Bind(tableItem, i))
        this._Bind("Edit_" t "_" i, "Click", editMacro.Bind(tableItem, i))
        this._Bind("Forbid_" t "_" i, "Click", OnItemForbidToggle.Bind(tableItem, i))
        this._Bind("Copy_" t "_" i, "Click", OnItemCopyMacroBtnClick.Bind(tableItem, i))
        this._Bind("Del_" t "_" i, "Click", OnItemDelMacroBtnClick.Bind(tableItem, i))
    }

    _BindFoldRows(t) {
        tableItem := MySoftData.TableInfo[t]
        for f, fold in tableItem.Folds {
            this._Bind("FoldFrontBtn_" t "_" f, "Click", OnFoldFrontInfoEdit.Bind(tableItem, f))
            this._Bind("FoldBtn_" t "_" f, "Click", OnFoldBtnClick.Bind(tableItem, f))
            this._Bind("FoldTKEdit_" t "_" f, "Click", OnFlodTKEditClick.Bind(tableItem, f))
            this._Bind("FoldAddMacro_" t "_" f, "Click", OnItemAddMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldPasteMacro_" t "_" f, "Click", OnItemPasteMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldForbidBtn_" t "_" f, "Click", OnFoldForbidToggleClick.Bind(tableItem, f))
            this._Bind("FoldDel_" t "_" f, "Click", OnItemDelFoldBtnClick.Bind(tableItem, f))
        }
    }

    ; 本地登记回调 + 让引擎挂上真实 WPF 事件（动态注入控件必须在 AddXamlItem 之后调用）
    ; 重建前先清同名旧回调，避免重复触发（同 ConfigMergeGui.PopulateListView 做法）
    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.Update(name, "BindEvent", evt)
    }

    ; 表身份 = tableItem 对象；t 仅作控件命名显示顺序槽位（内部解析）
    UpdateItemColor(tableItem, i) {
        if (!IsObject(tableItem))
            tableItem := GetTableByID(String(tableItem))
        if (!tableItem)
            return
        t := tableItem.Index
        if (this._useVirtual.Has(t)) {
            this._vl.UpdateColor(t, i)
            return
        }
        if (!this._IsRendered(t, i))
            return
        item := tableItem.Items[i]
        state := item ? item.ColorState : 0
        colorHex := state == 1 ? "#2E7D32" : state == 2 ? "#F9A825" : state == 3 ? "#C62828" : "Transparent"
        this.ui.Update("Color_" t "_" i, "Background", colorHex)
    }

    ; 增量刷新单行显示值：结构操作（上/下移）后只刷被交换两行，不整列表重建（滚动位置自然保留）。
    ; 槽位不变、事件绑 (tableItem, index) 闭包不重建，故仅更新各控件值即可。
    RefreshItemRow(t, i) {
        if (this._useVirtual.Has(t)) {
            this._vl.RefreshRow(t, i)
            this._RefreshSideTreeIfItem(t, i)
            return
        }
        if (!this._IsRendered(t, i))
            return
        tableItem := MySoftData.TableInfo[t]
        item := tableItem.Items[i]
        if (!item)
            return
        isTiming := CheckIsTimingMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isVoice := GetTableSymbol(t) == "Voice"
        if (isVoice) {
            ; 语音宏：触发键列显示唤醒词（无按键）
            tkStr := item.VoiceKeywords
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        } else {
            tkStr := isTiming ? GetLang("定时") : FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        }
        loopStr := item.LoopCount == "-1" ? GetLang("无限") : item.LoopCount
        tkTypeIdx := item.TriggerType - 1
        if (isUI)
            tkTypeIdx := 3
        this.ui.Update("Remark_" t "_" i, "Text", item.Remark)
        if (CheckIsNormalTable(t) && tkStr == GetLang("编辑"))
            tkStr := ""
        if (tkStr == "") {
            this.ui.Update("TKBtn_" t "_" i, "Content", Chr(0xE92E))
            this.ui.Update("TKBtn_" t "_" i, "FontFamily", "Segoe Fluent Icons, Segoe MDL2 Assets")
        } else {
            this.ui.Update("TKBtn_" t "_" i, "Content", tkStr)
        }
        this.ui.Update("TKType_" t "_" i, "SelectedIndex", String(tkTypeIdx))
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)
        this.SyncItemForbidBtnUI(t, i, item.Forbid)
        rowSel := this._sideTreeSel.Has(t) && this._sideTreeSel[t] == item.ID
        cardBg := rowSel ? "{DynamicResource TabSelBg}" : ((item.Forbid || GetItemFoldForbidState(tableItem, i)) ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource ControlBg}")
        this.ui.Update("ItemCard_" t "_" i, "Background", cardBg)
        try this.ui.Update("ItemCardInner_" t "_" i, "Opacity", (item.Forbid || GetItemFoldForbidState(tableItem, i)) ? this._ForbidContentOpacity() : "1")
        this.ui.Update("RowSelDot_" t "_" i, "Visibility", rowSel ? "Visible" : "Collapsed")
        this.ui.Update("RowSelMark_" t "_" i, "Visibility", rowSel ? "Visible" : "Collapsed")
        this.UpdateItemColor(t, i)
        this._RefreshItemEditGlyph(t, i, item.Macro)
        this._RefreshSideTreeIfItem(t, i)
    }

    _RefreshSideTreeIfItem(t, i) {
        if (this._suppressSideTreeRefresh)
            return
        if (!this._sideTreeSel.Has(t))
            return
        tableItem := MySoftData.TableInfo[t]
        if (i < 1 || i > tableItem.Items.Length)
            return
        item := tableItem.Items[i]
        if (item && item.ID == this._sideTreeSel[t])
            this.RefreshSideTree(t)
    }

    _RefreshItemEditGlyph(t, i, macroStr) {
        kind := GetMacroEditKind(macroStr)
        if (kind = 0) {
            this.ui.Update("EditGlyph3_" t "_" i, "Visibility", "Collapsed")
            return
        }
        this.ui.Update("EditGlyph3_" t "_" i, "Visibility", "Visible")
        this.ui.Update("EditGlyph3_" t "_" i, "Text", kind = 2 ? Chr(0xE8F1) : Chr(0xE71D))
        this.ui.Update("EditGlyph3_" t "_" i, "Margin", kind = 2 ? "3,0,0,0" : "2,0,0,0")
    }

    _XmlEsc(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        s := StrReplace(s, "`r`n", "&#10;")
        s := StrReplace(s, "`n", "&#10;")
        s := StrReplace(s, "`r", "&#10;")
        return s
    }

    ; ============ Epic5 虚拟列表模板（注入 Window.Resources，VLTemplateSelector 按行类型取用） ============
    ; 复刻 _BuildItemRow / _BuildFoldTitleRow 列结构，字面值换 {Binding}，控件加 Tag 供容器级事件路由。
    ; 折叠头 TK 行文案固定「菜单触发键：」（模板共享，UI 表同文案，阶段C 如需区分再拆模板）。
    _BuildVListTemplates() {
        keep := this._IsAiPanelOpen()
        this.aiAssistOpen := false
        normal := this._BuildVListTemplateSet("")
        this.aiAssistOpen := true
        compact := this._BuildVListTemplateSet("C")
        this.aiAssistOpen := keep
        return normal . compact
    }

    _BuildVListTemplateSet(suf) {
        row := '<DataTemplate x:Key="RmtMacroRow' suf '">'
            . this._BuildItemCardOpen()
            . '<Grid.ColumnDefinitions>' this._ItemInnerColDefs() '</Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Width="12" Height="12" CornerRadius="6" Background="{Binding ColorHex}" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . this._BuildSeqNoXaml(true)
            . this._BuildItemRemarkFieldXaml(0, 0, "", true)
            . '<Button Grid.Column="4" Tag="TKBtn" IsEnabled="{Binding TKBtnEnabled}" Style="{StaticResource RmtItemFieldBtn}" Margin="0,0,4,0" ToolTip="' GetLang("触发键") '">' this._BuildTKBtnInnerXaml("", true) '</Button>'
            . '<ComboBox Grid.Column="5" Tag="TKType" SelectedIndex="{Binding TKType}" IsEnabled="{Binding TKTypeEnabled}" Style="{StaticResource RmtItemCombo}" Margin="0" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . this._BuildItemEditBtnXaml(0, 0, "", true)
            . '<ComboBox Grid.Column="8" Tag="Loop" Text="{Binding LoopText}" IsEditable="True" IsEnabled="{Binding LoopEnabled}" Style="{StaticResource RmtItemCombo}" Margin="0,0,4,0" ToolTip="' GetLang("循环次数") '">'
            . '<ComboBoxItem Content="' GetLang("无限") '"/>'
            . '</ComboBox>'
            . '<Button Grid.Column="9" Tag="Setting" Style="{StaticResource RmtItemPrimaryBtn}" Margin="0" Content="&#xE713;" ToolTip="' GetLang("设置") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"/>'
            . '<StackPanel Grid.Column="11" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Tag="Copy" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE8C8;" ToolTip="' GetLang("复制") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . this._BuildItemForbidBtnXaml(0, 0, false, true)
            . '<Button Tag="Del" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE74D;" ToolTip="' GetLang("删除") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0"/>'
            . '</StackPanel>'
            . this._ItemCardClose() '</DataTemplate>'
        foldFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSize(11))
        fold := '<DataTemplate x:Key="RmtFoldHeader' suf '">'
            . this._BuildFoldCardBorderOpen()
            . '<StackPanel VerticalAlignment="Center" TextElement.FontSize="' foldFs '">'
            . '<StackPanel.Style><Style TargetType="StackPanel"><Setter Property="Opacity" Value="1"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Opacity" Value="' this._ForbidContentOpacity() '"/></DataTrigger></Style.Triggers></Style></StackPanel.Style>'
            . this._BuildFoldDividerXaml(true)
            . this._BuildFoldHeaderRowXaml(0, 0, "", true)
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,4,0,0" Visibility="{Binding ShowTKRowVisibility}">'
            . '<TextBlock Text="' GetLang("菜单触发键：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'
            . '<ComboBox Tag="FoldTKType" SelectedIndex="{Binding FoldTKType}" IsEnabled="{Binding FoldTKTypeEnabled}" Width="70" Height="24" MinHeight="24" Margin="2,0,10,0">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . '<TextBox Tag="FoldTK" Text="{Binding FoldTK}" Width="100" Height="24" VerticalContentAlignment="Center" TextAlignment="Center"/>'
            . '<Button Tag="FoldTKEdit" Content="' GetLang("编辑") '" Height="24" MinHeight="24" Padding="8,0" Margin="6,0,0,0"/>'
            . '</StackPanel>'
            . '</StackPanel></Border></DataTemplate>'
        addFold := '<DataTemplate x:Key="RmtAddFold">'
            . '<Grid Height="72" HorizontalAlignment="Stretch">'
            . '<Button Tag="AddFold" Width="56" Height="56" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="-10,0,10,0" Cursor="Hand" ToolTip="' GetLang("新增模块") '">'
            . '<Button.Template><ControlTemplate TargetType="Button"><Grid>'
            . '<Ellipse x:Name="Bd" Stroke="{DynamicResource ControlBorder}" StrokeThickness="2" Fill="{DynamicResource ControlBg}"/>'
            . '<Grid Width="24" Height="24" IsHitTestVisible="False">'
            . '<Rectangle Width="24" Height="4" Fill="{DynamicResource TextMain}" RadiusX="1.5" RadiusY="1.5"/>'
            . '<Rectangle Width="4" Height="24" Fill="{DynamicResource TextMain}" RadiusX="1.5" RadiusY="1.5"/>'
            . '</Grid></Grid>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Fill" Value="{DynamicResource ControlBorder}"/><Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Fill" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="Bd" Property="Stroke" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Button.Template></Button></Grid></DataTemplate>'
        return row . fold . (suf == "" ? addFold : "")
    }

    _BuildFoldIconBtn(tag, name, t, f, content, tip, vlMode, isIcon := true, last := false) {
        margin := last ? "" : ' Margin="0,0,4,0"'
        font := isIcon ? ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"' : ' FontSize="14"'
        attrs := ' Style="{StaticResource RmtFoldToolBtn}" Content="' content '" ToolTip="' tip '"' . font
        if (last)
            attrs .= ' Margin="0"'
        if (vlMode)
            return '<Button Tag="' tag '" ' attrs '/>'
        return '<Button Name="' name '_' t '_' f '" Tag="' tag '" ' attrs '/>'
    }

    ; 模块行工具按钮：新增宏 / 粘贴宏 / 禁用 / 删除
    _BuildFoldToolbarXaml(t, f, forbidState, vlMode := false) {
        return this._BuildFoldIconBtn("FoldAddMacro", "FoldAddMacro", t, f, "+", GetLang("新增宏"), vlMode, false)
            . this._BuildFoldIconBtn("FoldPasteMacro", "FoldPasteMacro", t, f, "&#xE77F;", GetLang("粘贴宏"), vlMode)
            . this._BuildFoldForbidBtnXaml(t, f, forbidState, vlMode)
            . this._BuildFoldIconBtn("FoldDel", "FoldDel", t, f, "&#xE74D;", GetLang("删除"), vlMode, true, true)
    }

    ; 禁用：RmtFoldForbidBtn 悬停走主题 ActionHover；非 VL 由 SyncFoldForbidBtnUI 同步激活态
    _BuildFoldForbidBtnXaml(t, f, forbidState, vlMode) {
        icon := "&#xE25B;"
        tip := GetLang("禁用")
        dot := '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,2,0" IsHitTestVisible="False"/>'
        if (vlMode) {
            return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
                . '<Button Tag="FoldForbidBtn" Content="' icon '" ToolTip="' tip '" Style="{StaticResource RmtFoldForbidBtn}"/>'
                . '<Ellipse Width="6" Height="6" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,6,0" IsHitTestVisible="False">'
                . '<Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed"/>'
                . '<Style.Triggers><DataTrigger Binding="{Binding FoldForbid}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>'
                . '</Style></Ellipse.Style></Ellipse></Grid>'
        }
        actBg := forbidState ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}"
        actBr := forbidState ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}"
        actFg := forbidState ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}"
        dotVis := forbidState ? "Visible" : "Collapsed"
        return '<Grid VerticalAlignment="Center" ClipToBounds="False">'
            . '<Button Name="FoldForbidBtn_' t '_' f '" Tag="FoldForbidBtn" Content="' icon '" ToolTip="' tip '" Style="{StaticResource RmtFoldToolBtn}"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
            . ' Background="' actBg '" BorderBrush="' actBr '" Foreground="' actFg '"/>'
            . '<Grid Name="FoldForbidDot_' t '_' f '" Visibility="' dotVis '">' dot '</Grid>'
            . '</Grid>'
    }

    SyncItemForbidBtnUI(t, i, forbidState) {
        if (!IsObject(this.ui))
            return
        if (forbidState) {
            this.ui.Update("Forbid_" t "_" i, "Background", "{DynamicResource ActionBg}")
            this.ui.Update("Forbid_" t "_" i, "BorderBrush", "{DynamicResource ActionStroke}")
            this.ui.Update("Forbid_" t "_" i, "Foreground", "{DynamicResource ActionText}")
            this.ui.Update("ForbidDot_" t "_" i, "Visibility", "Visible")
        } else {
            this.ui.Update("Forbid_" t "_" i, "Background", "{DynamicResource ControlBg}")
            this.ui.Update("Forbid_" t "_" i, "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update("Forbid_" t "_" i, "Foreground", "{DynamicResource TextMain}")
            this.ui.Update("ForbidDot_" t "_" i, "Visibility", "Collapsed")
        }
    }

    SyncFoldForbidBtnUI(t, f, forbidState) {
        if (!IsObject(this.ui))
            return
        if (forbidState) {
            this.ui.Update("FoldForbidBtn_" t "_" f, "Background", "{DynamicResource ActionBg}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "BorderBrush", "{DynamicResource ActionStroke}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "Foreground", "{DynamicResource ActionText}")
            this.ui.Update("FoldForbidDot_" t "_" f, "Visibility", "Visible")
        } else {
            this.ui.Update("FoldForbidBtn_" t "_" f, "Background", "{DynamicResource ControlBg}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update("FoldForbidBtn_" t "_" f, "Foreground", "{DynamicResource TextMain}")
            this.ui.Update("FoldForbidDot_" t "_" f, "Visibility", "Collapsed")
        }
        this.ui.Update("FoldCard_" t "_" f, "Background", forbidState ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource FoldHeaderBg}")
        try this.ui.Update("FoldCardInner_" t "_" f, "Opacity", forbidState ? this._ForbidContentOpacity() : "1")
        tableItem := MySoftData.TableInfo[t]
        fold := tableItem.Folds[f]
        if (!fold)
            return
        for i, item in tableItem.Items {
            if (item.FoldID == fold.ID)
                this.RefreshItemRow(t, i)
        }
    }

    ; 行/折叠头共用 CheckBox（自定义勾选模板，Tag 兼作绑定路径）
    _VlCheckBox(tag, col) {
        colAttr := col == "" ? "" : ' Grid.Column="' col '"'
        return '<CheckBox' colAttr ' Tag="' tag '" Content="' GetLang("禁用") '" IsChecked="{Binding ' tag '}" HorizontalAlignment="Left" Margin="2,0,0,0" VerticalAlignment="Center">'
            . '<CheckBox.Template><ControlTemplate TargetType="CheckBox">'
            . '<BulletDecorator Background="Transparent" Cursor="Hand">'
            . '<BulletDecorator.Bullet><Border x:Name="Border" Width="18" Height="18" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3"><Path x:Name="CheckMark" Visibility="Collapsed" Data="M 4 9 L 7 12 L 13 5" Stroke="{DynamicResource Accent}" StrokeThickness="2" StrokeEndLineCap="Round" StrokeStartLineCap="Round" StrokeLineJoin="Round"/></Border></BulletDecorator.Bullet>'
            . '<ContentPresenter Margin="4,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" RecognizesAccessKey="True"/>'
            . '</BulletDecorator>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></CheckBox.Template></CheckBox>'
    }

    ; ============ 工具页 ============
    BuildToolTab() {
        ; Panel_ 编号 = TableInfo 位置（工具表第 9 位；1-8 为宏表走虚拟列表，无 Panel_）
        p := "Panel_9"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)

        Add(this._LabelRow("变量监视器：", '<StackPanel Orientation="Horizontal"><Button Name="BtnOpenVarListen" Content="' GetLang("打开监视器") '" Height="24" MinHeight="24" Padding="10,0" Margin="0,0,8,0"/><Button Name="BtnFileCheck" Content="' GetLang("文件校验") '" Height="24" MinHeight="24" Padding="10,0" Margin="0,0,8,0"/><Button Name="BtnFileCheckHelp" Content="?" Height="24" MinHeight="24" Width="30" Padding="0" Cursor="Hand" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/></StackPanel>'))
        Add(this._LabelRow("鼠标信息：", '<StackPanel Orientation="Horizontal"><TextBlock Name="TxtToolCheckKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolCheckHotkey) '" VerticalAlignment="Center" Opacity="0.6" Margin="0,0,8,0"/><CheckBox Name="ChkToolCheck" Content="' GetLang("开关") '" VerticalAlignment="Center" Margin="0,0,16,0"/><CheckBox Name="ChkAlwaysOnTop" Content="' GetLang("窗口置顶") '" VerticalAlignment="Center"/></StackPanel>'))
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add(this._TwoColRow(ns, "屏幕坐标：", "TxtMousePos", MainSoftData.PosStr, "窗口坐标：", "TxtWinPos", MainSoftData.WinPosStr))
        Add(this._TwoColRow(ns, "进程窗口标题：", "TxtProcessTile", MainSoftData.ProcessTile, "进程名：", "TxtProcessName", MainSoftData.ProcessName))
        Add(this._TwoColRow(ns, "进程窗口类：", "TxtProcessClass", MainSoftData.ProcessClass, "进程PID:", "TxtProcessPid", MainSoftData.ProcessPid))
        Add(this._TwoColRow(ns, "句柄Id:", "TxtProcessId", MainSoftData.ProcessId, "位置颜色：", "TxtColor", MainSoftData.Color))
        Add(this._LabelRow("指令录制：", '<StackPanel Orientation="Horizontal"><TextBlock Name="TxtRecordKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolRecordMacroHotKey) '" VerticalAlignment="Center" Opacity="0.6" Margin="0,0,8,0"/><CheckBox Name="ChkToolCheckRecord" Content="' GetLang("开关") '" VerticalAlignment="Center"/></StackPanel>'))
        Add(this._LabelRow("图片文本提取：", '<StackPanel Orientation="Horizontal"><TextBlock Name="TxtTextFilterKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolTextFilterHotKey) '" VerticalAlignment="Center" Opacity="0.6" Margin="0,0,8,0"/><Button Name="BtnTextShot" Content="' GetLang("截图提取文本") '" Height="24" MinHeight="24" Padding="10,0" Margin="0,0,8,0"/><Button Name="BtnTextImage" Content="' GetLang("从图片提取文本") '" Height="24" MinHeight="24" Padding="10,0"/></StackPanel>'))
        Add(this._LabelRow("语音转文字：", '<StackPanel Orientation="Horizontal"><Button Name="BtnStt" Content="' GetLang("打开语音转文字") '" Height="24" MinHeight="24" Padding="10,0"/></StackPanel>'))
        Add('<StackPanel ' ns ' Orientation="Horizontal" Margin="0,6,0,0"><TextBlock Text="' GetLang("录制的指令或提取的文本内容：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/><Button Name="BtnClearToolText" Content="' GetLang("清空内容") '" Height="24" MinHeight="24" Padding="10,0" Margin="12,0,0,0"/></StackPanel>')
        Add('<TextBox ' ns ' Name="TxtToolText" Text="" Height="140" AcceptsReturn="True" VerticalContentAlignment="Top" TextWrapping="Wrap" Padding="6,4" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>')

        this._Bind("BtnOpenVarListen", "Click", (*) => MyVarListenGui.ShowGui())
        this._Bind("BtnFileCheck", "Click", (*) => SelfCheckMissingFiles())
        this._Bind("BtnFileCheckHelp", "Click", OnClickFileCheckHelpBtn)
        this._Bind("ChkToolCheck", "Click", OnToolCheckHotkey)
        this._Bind("ChkAlwaysOnTop", "Click", OnToolAlwaysOnTop)
        this._Bind("ChkToolCheckRecord", "Click", OnHotToolRecordMacro.Bind(false))
        this._Bind("BtnTextShot", "Click", OnToolTextFilterScreenShot)
        this._Bind("BtnTextImage", "Click", OnToolTextFilterSelectImage)
        this._Bind("BtnStt", "Click", (*) => SttGui.ShowGui())
        this._Bind("BtnClearToolText", "Click", OnClearToolText)

        UIControls.ToolCheck := CtrlAdapter("ChkToolCheck", this.ui, "IsChecked")
        UIControls.AlwaysOnTop := CtrlAdapter("ChkAlwaysOnTop", this.ui, "IsChecked")
        UIControls.ToolCheckRecord := CtrlAdapter("ChkToolCheckRecord", this.ui, "IsChecked")
        UIControls.ToolText := CtrlAdapter("TxtToolText", this.ui, "Text")
        MainSoftData.ToolMousePosCtrl := CtrlAdapter("TxtMousePos", this.ui, "Text")
        MainSoftData.ToolMouseWinPosCtrl := CtrlAdapter("TxtWinPos", this.ui, "Text")
        MainSoftData.ToolProcessTileCtrl := CtrlAdapter("TxtProcessTile", this.ui, "Text")
        MainSoftData.ToolProcessNameCtrl := CtrlAdapter("TxtProcessName", this.ui, "Text")
        MainSoftData.ToolProcessClassCtrl := CtrlAdapter("TxtProcessClass", this.ui, "Text")
        MainSoftData.ToolProcessPidCtrl := CtrlAdapter("TxtProcessPid", this.ui, "Text")
        MainSoftData.ToolProcessIdCtrl := CtrlAdapter("TxtProcessId", this.ui, "Text")
        MainSoftData.ToolColorCtrl := CtrlAdapter("TxtColor", this.ui, "Text")

        this.ui.Update("ChkToolCheck", "IsChecked", MainSoftData.IsToolCheck ? "True" : "False")
        this.ui.Update("ChkToolCheckRecord", "IsChecked", MainSoftData.IsToolRecord ? "True" : "False")
        this.ui.Update("ChkAlwaysOnTop", "IsChecked", "False")
    }

    _LabelRow(label, controlXaml) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        if (label == "")
            return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4">' controlXaml '</StackPanel>'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4">'
            . '<TextBlock Text="' this._XmlEsc(label) '" Margin="0,0,6,0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . controlXaml
            . '</StackPanel>'
    }

    ; 两列行：label1+TextBox1 | label2+TextBox2，复刻旧布局「一行两列」
    _TwoColRow(ns, label1, name1, val1, label2, name2, val2) {
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,0,4">'
            . '<TextBlock Text="' this._XmlEsc(label1) '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name1 '" Text="' this._XmlEsc(val1) '" Width="220" Height="24" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<TextBlock Text="' this._XmlEsc(label2) '" Width="120" Margin="16,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name2 '" Text="' this._XmlEsc(val2) '" Width="220" Height="24" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
    }

    ; ============ 设置页（§12 按「作用范围」重组：通用设置 / 宏设置 / 功能选项） ============
    BuildSettingTab() {
        p := "Panel_10"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'

        ; ---- 通用设置：开机自启/管理员启动/多线程数/语言/首选编辑器/软件字体/截图方式/手柄类型/模态子窗口 ----
        Add('<TextBlock ' ns ' Text="' GetLang("通用设置") '" FontWeight="Bold" Margin="0,6,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._CheckRow("开机自启", "ChkBootStart", MainSoftData.IsBootStart)
            . this._CheckRow("管理员启动", "ChkAdminStart", MainSoftData.IsAdminStart
                , GetLang("开启后：软件会以管理员身份启动。部分功能（如后台键鼠、部分游戏按键模拟等）需要管理员权限才能生效。")
                . "`n" GetLang("若同时开启开机自启，自启时也会以管理员身份启动。")
                . "`n" GetLang("重要：请不要自行通过「右键若梦兔 → 属性 → 兼容性 → 以管理员身份运行此程序」绑定管理员权限，这样会导致「开机自启」选项失效。如需管理员权限，请使用本选项。"))
            . this._CheckRow("模态子窗口", "ChkModalSubGui", MainSoftData.IsModalSubGui
                , GetLang("开启后：打开指令编辑等子窗口时，会禁用主窗口，必须先关闭子窗口才能继续操作主窗口。")
                . "`n" GetLang("关闭后：子窗口与主窗口可同时操作，方便对照主界面内容进行编辑。")
                . "`n" GetLang("提示：默认开启，一般建议保持开启，避免误操作主窗口导致编辑内容丢失。"))
            . this._IntRow("多线程数(-1~10)：", "EditMutiThreadNum", MainSoftData.MutiThreadNum
                , GetLang("设置若梦兔最大线程数量") "`n" GetLang("-1：动态多线程，线程闲置时回收（30秒），不足时创建新的线程")
                . "`n" GetLang("0：单线程") "`n" GetLang("n：固定线程为指定n（推荐3~5）")
                . "`n" GetLang("提示：动态多线程采用固定线程3+动态多线程池最大16"))
            . this._ComboRow("语言/Lang：", "CmbLang", MainSoftData.LangArr, MainSoftData.Lang)
            . this._ComboRow(GetLang("首选编辑器："), "CmbPreferredEditor", GetLangArr(["逻辑树", "图形节点"]), MainSoftData.PreferredMacroEditor)
            . this._ComboRow(GetLang("截图方式："), "CmbScreenShot", GetLangArr(["微软截图", "RMT截图", "SC截图"]), MainSoftData.ScreenShotType)
            . this._ComboRow(GetLang("手柄映射："), "CmbTriggerJoyType", ["Xbox", "PS5"], MainSoftData.TriggerJoyType
                , GetLang("手柄映射说明"))
            . this._ComboRow(GetLang("宏手柄类型："), "CmbJoyType", ["Xbox", "PS5"], MainSoftData.JoyType
                , GetLang("宏手柄类型说明"))
            . this._ComboRow(GetLang("软件字体："), "CmbFont", MainSoftData.FontList, MainSoftData.FontType
                , GetLang("软件界面使用的字体，修改后保存设置生效。"))
            . '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"><TextBlock Text="' GetLang("软件背景颜色：") '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/><TextBox Name="EditSoftBGColor" Text="' MainSoftData.SoftBGColor '" Width="100" Height="24" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/></StackPanel>'
            . '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"><TextBlock Text="' GetLang("背景图：") '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/><TextBox Name="EditBackImage" Text="' this._XmlEsc(MainSoftData.BackImagePath) '" Width="220" Height="24" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/><Button Name="BtnBackImageBrowse" Content="' GetLang("浏览") '" Height="24" MinHeight="24" Padding="8,0" Margin="4,0,0,0"/><Button Name="BtnBackImageClear" Content="' GetLang("清空") '" Height="24" MinHeight="24" Padding="8,0" Margin="4,0,0,0"/></StackPanel>'
            . '</WrapPanel>')

        ; ---- 宏设置：时间/间隔/坐标浮动 + 无变量提醒（多线程数已在通用设置，去重） ----
        Add('<TextBlock ' ns ' Text="' GetLang("宏设置") '" FontWeight="Bold" Margin="0,10,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._IntRow("点击时间浮动(%)：", "EditHoldFloat", MainSoftData.HoldFloat)
            . this._IntRow("每次间隔浮动(%)：", "EditPreIntervalFloat", MainSoftData.PreIntervalFloat)
            . this._IntRow("间隔指令浮动(%)：", "EditIntervalFloat", MainSoftData.IntervalFloat)
            . this._IntRow("坐标X浮动(px)：", "EditCoordXFloat", MainSoftData.CoordXFloat)
            . this._IntRow("坐标Y浮动(px)：", "EditCoordYFloat", MainSoftData.CoordYFloat)
            . this._CheckRow("无变量提醒", "ChkNoVariable", MainSoftData.NoVariableTip)
            . '</WrapPanel>')

        ; ---- 功能选项：其余开关 + 功能按钮 ----
        Add('<TextBlock ' ns ' Text="' GetLang("功能选项") '" FontWeight="Bold" Margin="0,10,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._CheckRow("仅前台运行宏", "ChkForeground", MainSoftData.CheckForeground
                , GetLang("开启后：宏运行时会检查该项配置的前台窗口；若当前前台窗口不匹配，则终止该宏。")
                . "`n" GetLang("关闭后：不校验前台窗口，宏按原逻辑继续执行。")
                . "`n" GetLang("提示：需在对应宏项中配置「前台」信息后才会生效；未配置前台信息的宏不受此选项影响。"))
            . this._CheckRow("自动松开修饰键", "ChkAutoLoosen", MainSoftData.AutoLoosenModifier
                , GetLang("开启后：当触发键为「修饰键 + 普通键」（如 Ctrl + A）时，触发宏前会先松开修饰键，再执行宏逻辑。")
                . "`n" GetLang("这样可避免修饰键仍被按住，导致宏里发送的按键变成组合键（例如本意发 A，实际变成 Ctrl+A）。")
                . "`n" GetLang("关闭后：不自动松开修饰键，保持物理按键原样。")
                . "`n" GetLang("提示：触发键以 ~ 开头（穿透）时，不会自动松开修饰键。"))
            . this._CheckRow("连续触发", "ChkContinuous", MainSoftData.ContinuousTrigger
                , GetLang("开启后：按下、开关、长按类型在按住触发键期间可以连续触发。")
                . "`n" GetLang("关闭后：按下、开关、长按类型必须先松开触发键，才能再次触发。")
                . "`n" GetLang("提示：松开、松止、双击类型不受此选项影响。"))
            . this._CheckRow("业务日志", "ChkBusinessLog", MainSoftData.BusinessLog
                , GetLang("开启后：记录宏运行流水到 Log\\Business.log（宏触发/每指令/宏结束）。")
                . "`n" GetLang("关闭后：不记录业务流水（默认）。")
                . "`n" GetLang("提示：业务日志可能产生大量内容，建议排查问题时开启。"))
            . this._CheckRow("分割线", "ChkSplitLine", MainSoftData.ShowSplitLine)
            . this._ComboRow(GetLang("按下时按下："), "CmbKeyDownDown", GetLangArr(["自动松开", "忽略重复按下", "允许重复按下"]), MainSoftData.KeyDownDownType
                , GetLang("当宏按键已经处于按下状态，再次触发按下指令时特别处理")
                . "`n" GetLang("自动松开：再次按下前，先松开该按键（确保指令正常执行）")
                . "`n" GetLang("忽略重复按下：保持按键之前的状态，忽略后续的按下指令")
                . "`n" GetLang("允许重复按下：再次按下宏按键（罗技按键可能卡死）")
                . "`n" GetLang("Tip1：按下时再次按下，真实键盘无法触发这个行为，这个行为通常是无效的")
                . "`n" GetLang("Tip2：按下时再次按下，按键检测网站可能无法检测，但记事本中可以有效输出"))
            . this._ComboRow(GetLang("指令备注") "：", "CmbRemarkAuto", GetLangArr(["不生成", "自动生成", "覆盖生成"]), MainSoftData.RemarkAutoType)
            . this._ComboRow(GetLang("宏终止方式："), "CmbMacroStop", GetLangArr(["智能终止", "强制终止"]), MainSoftData.MacroStopType
                , GetLang("智能终止：优先以协作方式让宏自行退出，设 150ms 期限，逾期未退出则强制结束。")
                . "`n" GetLang("强制终止：直接结束线程并创建新线程，不等待宏自行退出。")
                . "`n" GetLang("提示：强制终止响应更快，但频繁结束、创建线程会消耗较多资源，建议保持智能终止。"))
            . '</WrapPanel>')

        ; ---- §10 显示页签选项：勾选控制页签显隐（隐藏仅显示效果，不影响触发；保存后重启生效） ----
        Add('<TextBlock ' ns ' Text="' GetLang("显示页签") '" FontWeight="Bold" Margin="0,10,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._CheckRow(GetLang("按键宏"), "TabVisible_Normal", this._TabVisibleVal("Normal"))
            . this._CheckRow(GetLang("字串宏"), "TabVisible_String", this._TabVisibleVal("String"))
            . this._CheckRow(GetLang("菜单宏"), "TabVisible_Menu", this._TabVisibleVal("Menu"))
            . this._CheckRow(GetLang("界面宏"), "TabVisible_UI", this._TabVisibleVal("UI"))
            . this._CheckRow(GetLang("语音宏"), "TabVisible_Voice", this._TabVisibleVal("Voice"))
            . this._CheckRow(GetLang("定时宏"), "TabVisible_Timing", this._TabVisibleVal("Timing"))
            . this._CheckRow(GetLang("宏"), "TabVisible_SubMacro", this._TabVisibleVal("SubMacro"))
            . this._CheckRow(GetLang("按键替换"), "TabVisible_Replace", this._TabVisibleVal("Replace"))
            . '</WrapPanel>')
        Add('<TextBlock ' ns ' Text="' GetLang("隐藏的页签仅不显示，不影响该页签下宏的正常触发（保存后重启生效）。") '" Foreground="{DynamicResource TextSub}" FontSize="11" Margin="0,2,0,4"/>')

        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . '<Button Name="BtnTheme" Content="' GetLang("主题") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnHotkey" Content="' GetLang("快捷键") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnToolRecord" Content="' GetLang("指令录制") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnLogCenter" Content="' GetLang("日志中心") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnLogSetting" Content="' GetLang("日志与错误") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnRightClickMenu" Content="' GetLang("右键菜单设置") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnMenuWheel" Content="' GetLang("轮盘") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnUIPanel" Content="' GetLang("界面浮窗") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<CheckBox Name="ChkCMDTip" Content="' GetLang("指令显示") '" VerticalAlignment="Center" Margin="4,4,6,4"/>'
            . '<Button Name="BtnCMDTipSetting" Content="' GetLang("设置") '" Height="28" MinHeight="28" Padding="10,0" Margin="0,4,0,4"/>'
            . '</WrapPanel>')

        ; ---- 事件 ----
        this._Bind("EditHoldFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "HoldFloat"))
        this._Bind("EditPreIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "PreIntervalFloat"))
        this._Bind("EditIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "IntervalFloat"))
        this._Bind("EditCoordXFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordXFloat"))
        this._Bind("EditCoordYFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordYFloat"))
        this._Bind("EditMutiThreadNum", "LostFocus", ObjBindMethod(this, "OnIntEdit", "MutiThreadNum"))
        this._Bind("EditSoftBGColor", "LostFocus", ObjBindMethod(this, "OnTextEdit", "SoftBGColor"))
        ; §11 背景图：浏览/清空（写入 MainSoftData.BackImagePath，保存后重启生效）
        this._Bind("BtnBackImageBrowse", "Click", ObjBindMethod(this, "OnBackImageBrowse"))
        this._Bind("BtnBackImageClear", "Click", ObjBindMethod(this, "OnBackImageClear"))
        this._Bind("CmbFont", "SelectionChanged", ObjBindMethod(this, "OnComboText", "FontType"))
        this._Bind("ChkBootStart", "Click", OnBootStartChanged)
        this._Bind("ChkAdminStart", "Click", OnAdminStartChanged)
        this._Bind("ChkForeground", "Click", ObjBindMethod(this, "OnCheckEdit", "CheckForeground"))
        this._Bind("ChkAutoLoosen", "Click", ObjBindMethod(this, "OnCheckEdit", "AutoLoosenModifier"))
        this._Bind("ChkContinuous", "Click", ObjBindMethod(this, "OnCheckEdit", "ContinuousTrigger"))
        this._Bind("ChkNoVariable", "Click", ObjBindMethod(this, "OnCheckEdit", "NoVariableTip"))
        this._Bind("ChkBusinessLog", "Click", ObjBindMethod(this, "OnBusinessLogToggle"))
        this._Bind("ChkModalSubGui", "Click", ObjBindMethod(this, "OnCheckEdit", "IsModalSubGui"))
        this._Bind("ChkSplitLine", "Click", ObjBindMethod(this, "OnCheckEdit", "ShowSplitLine"))
        this._Bind("CmbLang", "SelectionChanged", ObjBindMethod(this, "OnComboText", "Lang"))
        this._Bind("CmbPreferredEditor", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "PreferredMacroEditor"))
        this._Bind("CmbScreenShot", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "ScreenShotType"))
        this._Bind("CmbTriggerJoyType", "SelectionChanged", ObjBindMethod(this, "OnComboText", "TriggerJoyType"))
        this._Bind("CmbJoyType", "SelectionChanged", ObjBindMethod(this, "OnComboText", "JoyType"))
        this._Bind("CmbKeyDownDown", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "KeyDownDownType"))
        this._Bind("CmbRemarkAuto", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "RemarkAutoType"))
        this._Bind("CmbMacroStop", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "MacroStopType"))
        ; §10 显示页签勾选
        for sym in ["Normal", "String", "Menu", "UI", "Voice", "Timing", "SubMacro", "Replace"]
            this._Bind("TabVisible_" sym, "Click", ObjBindMethod(this, "OnTabVisibleCheck", sym))
        this._Bind("BtnTheme", "Click", OnClickThemeSettingBtn)
        this._Bind("BtnHotkey", "Click", OnClickHotkeySettingBtn)
        this._Bind("BtnToolRecord", "Click", OnClickToolRecordSettingBtn)
        this._Bind("BtnLogCenter", "Click", (*) => LogCenterGui.ShowGui())
        this._Bind("BtnLogSetting", "Click", (*) => LogSettingGui.ShowGui())
        this._Bind("BtnRightClickMenu", "Click", (*) => RightClickMenuSettingGui().ShowGui())
        this._Bind("BtnMenuWheel", "Click", OnClickMenuWheelSettingBtn)
        this._Bind("BtnUIPanel", "Click", OnClickUIMacroPanelSettingBtn)
        this._Bind("ChkCMDTip", "Click", OnClickCMDTipToggle)
        this._Bind("BtnCMDTipSetting", "Click", (*) => CMDTipSettingGui.ShowGui())

        UIControls.CMDTip := CtrlAdapter("ChkCMDTip", this.ui, "IsChecked")
        this.ui.Update("ChkCMDTip", "IsChecked", MySoftData.CMDTip ? "True" : "False")
    }

    OnIntEdit(fieldName, state, ctrl, event) {
        v := Trim(this.ui.Query(ctrl))
        if (v != "" && IsInteger(v))
            MainSoftData.%fieldName% := Integer(v)
    }

    OnTextEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
    }

    ; §11 背景图：浏览选择图片文件（写入配置，保存后重启生效）
    OnBackImageBrowse(state, ctrl, event) {
        path := FileSelect(1, , GetLang("选择背景图片"), "图片 (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp)|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp")
        if (path == "")
            return
        MainSoftData.BackImagePath := path
        this.ui.Update("EditBackImage", "Text", path)
    }

    OnBackImageClear(state, ctrl, event) {
        MainSoftData.BackImagePath := ""
        this.ui.Update("EditBackImage", "Text", "")
    }

    OnCheckEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl) == "True"
    }

    ; §10 显示页签勾选：写入 TabVisibleMap（保存后重启生效）
    OnTabVisibleCheck(symbol, state, ctrl, event) {
        if (!MainSoftData.TabVisibleMap.Has(symbol))
            return
        MainSoftData.TabVisibleMap[symbol] := this.ui.Query(ctrl) == "True"
    }

    _TabVisibleVal(symbol) {
        return (MainSoftData.TabVisibleMap.Has(symbol)) ? MainSoftData.TabVisibleMap[symbol] : true
    }

    ; 业务日志开关：写 MainSoftData + 同步 LogUtil global + 持久化
    OnBusinessLogToggle(state, ctrl, event) {
        global RMTLogBusinessEnabled
        MainSoftData.BusinessLog := this.ui.Query(ctrl) == "True"
        RMTLogBusinessEnabled := MainSoftData.BusinessLog
        IniWrite(MainSoftData.BusinessLog, IniFile, IniSection, "BusinessLog")
    }

    OnComboText(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
    }

    OnComboIndex(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := Integer(this.ui.Query(ctrl ">SelectedIndex")) + 1
    }

    _IntRow(label, name, val, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name '" Text="' val '" Width="100" Height="24" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
    }

    _CheckRow(label, name, val, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<CheckBox Name="' name '" Content="' this._XmlEsc(label) '" IsChecked="' (val ? "True" : "False") '" VerticalAlignment="Center"/>'
            . '</StackPanel>'
    }

    _ComboRow(label, name, items, sel, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        selIdx := ""
        itemsXaml := ""
        for k, it in items {
            ; INI 读出的数值可能是字符串（如 "1"），需按整数匹配
            isSel := IsInteger(sel) ? (k == Integer(sel)) : (it == sel)
            if (isSel)
                selIdx := k - 1
            itemsXaml .= '<ComboBoxItem Content="' this._XmlEsc(it) '"/>'
        }
        selAttr := (selIdx == "") ? "" : ' SelectedIndex="' selIdx '"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="80" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<ComboBox Name="' name '" Width="130" Height="24" MinHeight="24" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"' selAttr '>' itemsXaml '</ComboBox>'
            . '</StackPanel>'
    }

    ; ============ 帮助页 ============
    BuildHelpTab() {
        p := "Panel_11"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add('<TextBlock ' ns ' Text="' GetLang("免责声明") '" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,8,0,4"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力") '" FontSize="10" HorizontalAlignment="Center" Opacity="0.7" Margin="0,0,0,8"/>')
        Add(this._Para('1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。'))
        Add(this._Para("2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。"))
        Add(this._Para("3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。"))
        Add(this._Para("4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"))
        Add('<TextBlock ' ns ' Text="' GetLang("若不同意上述条款，请立即停止使用本软件。") '" Foreground="Red" HorizontalAlignment="Center" Margin="0,10,0,0"/>')

        Add(this._LinkRow(GetLang("更新视频合集："), "https://www.bilibili.com/video/BV1yR8x6xEBW", GetLang("版本更新视频，直播交流问答")))
        Add(this._LinkRow(GetLang("操作说明文档："), A_WorkingDir "\index.html", GetLang("快速上手，指令手册、常见问题、常见报错、更新日志等")))
        Add(this._LinkRow(GetLang("配置共享仓库："), "https://zclucas.github.io/RMT-Setting/", GetLang("案例学习、获取他人分享的宏配置（支持下载导入）")))
        Add(this._LinkRow(GetLang("国内开源网址："), "https://gitee.com/fateman/RMT", "https://gitee.com/fateman/RMT"))
        Add(this._LinkRow(GetLang("国外开源网址："), "https://github.com/zclucas/RMT", "https://github.com/zclucas/RMT"))
        Add(this._LabelRow(GetLang("软件检查更新："), '<TextBlock Text="' GetLang("浏览开源网址，查看右侧发行版处即可知道软件最新版本") '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'))
        Add(this._LinkRow(GetLang("软件交流渠道："), "https://qm.qq.com/q/DgpDumEPzq", "QQ群（837661891）、QQ频道、GitHub 论坛、Discord"))
        Add(this._LabelRow(GetLang("软件反馈表格："), '<TextBlock Text="' GetLang("bug文档") '、' GetLang("需求文档") '、' GetLang("使用备注") '（仅交流群成员有编辑权限）" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'))
        Add(this._LabelRow(GetLang("软件开源协议："), '<TextBlock Text="AGPL-3.0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'))
        this._FlushLinks()
    }

    _Para(text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        return '<TextBlock ' ns ' Text="' this._XmlEsc(GetLang(text)) '" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,3"/>'
    }

    _LinkRow(label, url, text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        this._linkCounter := this._linkCounter + 1
        name := "Link_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url })
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,3,0,3">'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="130" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBlock Name="' name '" Text="' this._XmlEsc(text) '" TextDecorations="Underline" Foreground="#2D6CDF" Cursor="Hand" FontSize="12" TextWrapping="Wrap"/>'
            . '</StackPanel>'
    }

    OnLinkClick(url, state, ctrl, event) {
        Run(url)
    }

    ; ============ 赞助页 ============
    BuildRewardTab() {
        p := "Panel_12"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        countStr := FormatIntegerWithCommas(MySoftData.MacroTotalCount)
        str := Format(GetLang("若梦兔（RMT）—— 这款完全免费的开源软件，始终陪在你身边。")) "`n"
            . Format(GetLang("至今已为您执行 {:} 次宏指令。"), countStr) "`n"
            . GetLang("诚邀本月赞助成为若梦兔的 “守护者”，一起让若梦兔走得更远。")
        weiXinImg := StrReplace(A_WorkingDir "\Images\Soft\WeiXin.png", "\", "/")
        zhiFuBaoImg := StrReplace(A_WorkingDir "\Images\Soft\ZhiFuBao.png", "\", "/")
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add('<TextBlock ' ns ' Text="' this._XmlEsc(str) '" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,4"/>')
        Add('<StackPanel ' ns ' Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">'
            . '<StackPanel Margin="0,0,40,0"><Image Source="' weiXinImg '" Width="180" Height="180"/><TextBlock Text="' GetLang("微信赞助") '" HorizontalAlignment="Center" Margin="0,6,0,0"/></StackPanel>'
            . '<StackPanel><Image Source="' zhiFuBaoImg '" Width="180" Height="180"/><TextBlock Text="' GetLang("支付宝赞助") '" HorizontalAlignment="Center" Margin="0,6,0,0"/></StackPanel>'
            . '</StackPanel>')
        Add('<TextBlock ' ns ' Text="' this._XmlEsc(GetLang("当然，如果你暂时不方便，分享给朋友也是很棒的支持~")) '`n' this._XmlEsc(GetLang("开发不易，感谢你的每一份温暖！")) '" FontSize="12" TextWrapping="Wrap" Margin="0,16,0,0"/>')
    }

    ; ============ 特别感谢页 ============
    BuildThankTab() {
        p := "Panel_13"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add('<TextBlock ' ns ' Text="' GetLang("感谢以下开发者为项目付出的智慧与汗水（排名不分先后）：") '" FontWeight="Bold" TextWrapping="Wrap" Margin="0,8,0,4"/>')
        Add(this._ThankLinks(["https://github.com/GushuLily", "https://gitee.com/bogezzb", "https://github.com/yunkuangao", "https://github.com/boxstudy", "https://github.com/sovaedv776", "https://github.com/T8numen"], ["GushuLily", "张正波", "yun", "boxstudy", "sovaedv776", "T8numen"]))
        Add('<TextBlock ' ns ' Text="' GetLang("软件的开发离不开众多优秀开源项目的支持，特别感谢：") '" FontWeight="Bold" TextWrapping="Wrap" Margin="0,14,0,4"/>')
        Add(this._ThankLinks(["https://github.com/opencv/opencv", "https://github.com/thqby/ahk2_lib", "https://github.com/RapidAI/RapidOCR", "https://github.com/evilC/AHK-CvJoyInterface", "https://github.com/Chaoses-Ib/IbInputSimulator", "https://github.com/evilC/AHK-ViGEm-Bus", "https://github.com/CesarHlp1/AHK-ViGEm-Bus-v2.ahk", "https://github.com/xland/ScreenCapture", "https://github.com/owhs/ahk-xaml"], ["OpenCV", "ahk2_lib", "RapidOCR", "AHK-CvJoyInterface", "IbInputSimulator", "AHK-ViGEm-Bus", "AHK-ViGEm-Bus-v2", "ScreenCapture", "ahk-xaml"]))
        Add('<TextBlock ' ns ' Text="' GetLang("感谢以下群友在社区中的活跃参与和宝贵建议：（QQ昵称）") '" FontWeight="Bold" TextWrapping="Wrap" Margin="0,14,0,4"/>')
        Add('<TextBlock ' ns ' Text="AYu    万年置伞    别说*不下啦    仰望    话听    yun" FontSize="12" Margin="0,4,0,4"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("感谢所有赞助支持若梦兔的守护者，以及参与完善 Bug 和需求文档的朋友。") '" FontSize="12" TextWrapping="Wrap" Margin="0,14,0,0"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("感谢每一位陪伴我们走过这段旅程的粉丝和群友们！是你们的支持与信任，让这个软件从一个小小的想法，一步步成长为今天的样子。每一次的鼓励、每一条的建议，都是我们前进的动力。") '`n' GetLang("感谢你们不离不弃，与我们共同见证每一次的迭代与成长。") '" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("再次感谢所有关心、支持、帮助过这个项目的每一个人！") '`n' GetLang("因为有你，这个项目才变得更有意义。") '" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>')
        Add('<TextBlock ' ns ' Text="—— 若梦兔' GetLang("敬上") '" FontSize="12" HorizontalAlignment="Right" Margin="0,8,0,0"/>')
        this._FlushLinks()
    }

    _ThankLinks(urls, names) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        row := '<WrapPanel ' ns ' Margin="0,3,0,3">'
        for k, url in urls {
            this._linkCounter := this._linkCounter + 1
            name := "ThankLink_" this._linkCounter
            this._linkQueue.Push({ name: name, url: url })
            row .= '<TextBlock Name="' name '" Text="' this._XmlEsc(names[k]) '" TextDecorations="Underline" Foreground="#2D6CDF" Cursor="Hand" FontSize="12" Margin="0,0,18,0"/>'
        }
        row .= '</WrapPanel>'
        return row
    }

    _FlushLinks() {
        for item in this._linkQueue
            this._Bind(item.name, "MouseLeftButtonUp", ObjBindMethod(this, "OnLinkClick", item.url))
        this._linkQueue := []
    }
}

global MyMainWin := MainWin()
