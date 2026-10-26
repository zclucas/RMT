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
        this._textFocusName := ""   ; 当前聚焦的文本框名（侧栏编辑热键据此判断是否透传 Ctrl+C/V/Z/Y、Delete）
        this._shareLoginTick := ""  ; 非空 = 正在等浏览器授权回调（SetTimer 的 bound method）
        this._shareVerifyTick := "" ; 非空 = 正在用 key 校验 /session/current.json
        this._linkCounter := 0
        this._linkQueue := []
        this._thankReady := false
        this._thankSponsorShown := false
        this._sponsorLogos := []
        this._sponsorLayoutKey := ""
        this._sponsorLaying := false
        this._sponsorLayoutWait := ""
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
        this._settingDirty := Map()
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
        leftTop.Add("Button").Name("BtnConfig").Uid("gm:Main.Config").Content(GetLang("配置管理")).Height(33).MinHeight(33).Margin("0,3,0,2").Style("{StaticResource RmtSidebarBtn}")
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
        if (!A_IsCompiled)
            leftTop.Add("Button").Name("BtnGMUI").Content("GM-UI").Height(33).MinHeight(33).Margin("0,8,0,0").Style("{StaticResource RmtSidebarBtn}")
        leftBottom := left.Add("StackPanel").Grid_Row(1).VerticalAlignment("Bottom")
        leftBottom.Add("Button").Name("BtnHelp").Content(GetLang("RMT文档")).Height(28).MinHeight(28).Margin("0,2,0,2")
        leftBottom.Add("Button").Name("BtnSave").Uid("gm:Main.Save").Content(GetLang("应用并保存")).Height(36).MinHeight(36).Margin("0,2,0,0").FontWeight("Bold")

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
                ; 工具页内容已按固定工作台尺寸排版；保留滚轮滚动能力但不显示无意义的细窄滚动条。
                ; 设置页做成固定「设置中心」工作台：外层必须 Disabled（Disabled 才会把视口高度交给内容，
                ; Hidden 仍按无限高度测量），由内容区自带的 ScrollViewer 负责滚动，左侧导航因此保持固定。
                ; 其它说明类页签仍保持 Auto，避免长帮助内容无法发现滚动位置。
                isToolTab := tableItem.ID == "Tool"
                isSettingTab := tableItem.ID == "Setting"
                sv := bd.Add("ScrollViewer").VerticalScrollBarVisibility(isSettingTab ? "Disabled" : (isToolTab ? "Hidden" : "Auto")).HorizontalScrollBarVisibility("Disabled")
                if (isSettingTab)
                    sv.Add("Grid").Name("Panel_" idx).Margin("8,6,8,10")
                else
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
        ; 前台组右侧加了问号钮（24），整组左移 24 以免挤到操作按钮
        this._foldFrontShift := 133
        this._itemToolbarShift := 200
        ; 宏页签无触发键/触发类型：相对原「宏编辑器」列左移，并与模块前台保持固定间距
        this._subMacroEditShift := 210
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
            ; 焦点跟踪：侧栏逻辑树的窗口级 $^c/$^v/$^z/$^y/Delete 会吞键，AI 框同样收不到按键（含 Ctrl+V 贴图）
            this.ui.OnEvent("AiInput_" t, "GotFocus", ObjBindMethod(this, "OnTextInputFocus", "AiInput_" t))
            this.ui.OnEvent("AiInput_" t, "LostFocus", ObjBindMethod(this, "OnTextInputBlur", "AiInput_" t))
            try this.ui.Update("AiInput_" t, "BindEvent", "GotFocus")
            try this.ui.Update("AiInput_" t, "BindEvent", "LostFocus")
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
        if (!A_IsCompiled)
            this.ui.OnEvent("BtnGMUI", "Click", (*) => this.ui.Update("Window", "GMUIOpen", ""))
        this.ui.OnEvent("BtnHelp", "Click", (*) => OnOpenRmtDoc())
        this.ui.OnEvent("BtnSave", "Click", OnSaveSetting)

        this._vl := VirtualListHost(this.ui)
        this.LoadLeftBarValues()
        this._startHidden := MainSoftData.HasProp("IsMinStart") && MainSoftData.IsMinStart
        this.ui._skipAutoReveal := this._startHidden
        ; ===== 先填充内容（Show 前入队，LoadedHwnd 时一次刷入），填充完再显示，避免空壳闪烁 =====
        try {
            this.PopulateAll()
        } catch as e {
            XamlUiDiag("PopulateAll 异常: " e.Message " @ " e.File ":" e.Line "`n" e.Stack, "MainWin")
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
        ; 各页签独立构建：任一失败不得阻断后续 RenderTab（否则主界面宏列表空白）
        for fn in ["BuildToolTab", "BuildSettingTab", "BuildHelpTab", "BuildRewardTab", "BuildThankTab"] {
            try
                this.%fn%()
            catch as e
                XamlUiDiag(fn " 异常: " e.Message " @ " e.File ":" e.Line, "MainWin")
        }
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
        ; TabControl 初始选择与子控件 SelectionChanged 可能在 PopulateAll 尚未创建惰性渲染状态时冒泡。
        ; 此时不应切换页签；待 PopulateAll 完成并建立 _renderedTabs 后再响应后续事件。
        if (!this.HasOwnProp("_renderedTabs") || !IsObject(this._renderedTabs))
            return
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
        this._ShowAiDragShield(false)
        try this.ui.Update("Window", "Cursor", "Arrow")
        if (IsSet(MainSoftData))
            MainSoftData.AiPanelWidth := this.aiPanelW
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
            ; 只用当前可见列表计算可用宽度。查询第一个虚拟页签会命中隐藏控件，
            ; 其 ActualWidth 为 0，任何点击/拖拽都会把面板错误夹到最小宽度。
            t := (IsSet(MainSoftData) ? MainSoftData.TableIndex : 0)
            if (!t || !this._useVirtual.Has(t)) {
                for idx in this._useVirtual {
                    candidateW := Integer(this.ui.Query("FoldList_" idx ">ActualWidth"))
                    if (candidateW > 0) {
                        t := idx
                        break
                    }
                }
            }
            if (t) {
                listW := Integer(this.ui.Query("FoldList_" t ">ActualWidth"))
                if (listW > 0) {
                    avail := listW + this.aiPanelW - this._AiListMinW()
                    if (avail < maxW)
                        maxW := avail
                }
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
        treeCtx.Add("MenuItem").Name("SideMenuBpCmd").Header(GetLang("断点"))
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
        bpStr := ""
        if (item && CheckIsMacroTable(t) && Trim(item.Macro) != "") {
            macroStr := GetLangMacro(item.Macro, 1)
            bpStr := item.HasProp("Breakpoints") ? item.Breakpoints : ""
        }
        this._sideTree.Load(t, macroStr, bpStr)
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

    ; 断点写回：更新条目字段 + 热重载广播（断点为独立字段，不动 Macro 文本，也不重建树）
    ; 树标记已由 MacroEditGui.SetBreakPoint 就地更新；此处仅落字段并广播到 Worker
    _WriteSideTreeBreakpoints(t, bpStr) {
        item := this._ResolveSideTreeItem(t)
        if (!item)
            return
        item.Breakpoints := bpStr
        HotReloadPublish(t, 0)
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
        ed.MenuHandler(ed._ContinueLabel())
    }

    OnSideToolStep(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.MenuHandler(ed._StepIntoLabel())
    }

    ; ⚠️ 当前无调用方（侧栏「运行到下一断点」工具钮已随 F7 退休删除，
    ;    语义并入「继续」F5）；保留以备回退——勿当活代码引用。
    OnSideToolRunToBp(t, *) {
        if (!IsObject(this._sideTree))
            return
        this._sideTree.Activate(t)
        ed := this._sideTree.ActiveEditor()
        if (!IsObject(ed))
            ed := this._sideTree.Ensure(t)
        if (!IsObject(ed))
            return
        ed.ContinueRun()
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
        this._AddSideToolBtn(toolBar, idx, "Record", Chr(0xE7C8), GetLang("指令录制"), true)
        this._AddSideToolBtn(toolBar, idx, "Expand", Chr(0xE73F), GetLang("缩放"), false)
        this._AddSideToolBtn(toolBar, idx, "Undo", Chr(0xE7A7), GetLang("撤销"), false)
        this._AddSideToolBtn(toolBar, idx, "Redo", Chr(0xE7A6), GetLang("恢复"), false)
        this._AddSideToolBtn(toolBar, idx, "Back", Chr(0xE750), GetLang("删除末尾"), false)
        this._AddSideToolSep(toolBar)
        this._AddSideToolBtn(toolBar, idx, "Run", Chr(0xE768), GetLang("播放/继续"), false)
        this._AddSideToolBtn(toolBar, idx, "Step", "", GetLang("步入"), false)
        this._AddSideToolSep(toolBar)
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
            SttGui.RequestModelDownload()
            return
        }
        inputBefore := ""
        try inputBefore := Trim(this.ui.Query("AiInput_" t))
        initializing := !engine.streamLoaded
        if (initializing && inputBefore == "") {
            try this.ui.Update("AiInputPh_" t, "Text", GetLang("模型正在加载…"))
            try this.ui.Update("AiInputPh_" t, "Visibility", "Visible")
            Sleep(50)
        }
        if (!engine.StreamBegin()) {
            this._AiSyncPlaceholder(t)
            Toast.Error(GetLang("开始录音失败：") engine._ErrText(engine.StreamGetLastError()))
            return
        }
        this._aiRec[t] := true
        this._aiSttTab := t
        this._aiSttBase := ""
        try this._aiSttBase := this.ui.Query("AiInput_" t)
        this._aiSttLive := ""
        try this.ui.Update("AiInput_" t, "Foreground", "{DynamicResource TextSub}")
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
        if (Trim(live) != "" && live != this._aiSttLive)
            this._AiSetVoiceText(t, live)
    }

    _AiSetVoiceText(t, text) {
        this._aiSttLive := text
        base := this._aiSttBase
        separator := (base != "" && !RegExMatch(base, "\s$")) ? " " : ""
        this.ui.Update("AiInput_" t, "Text", base separator text)
        try this.ui.Update("AiInputPh_" t, "Text", GetLang("询问关于宏的任何问题…"))
        try this.ui.Update("AiInputPh_" t, "Visibility", "Collapsed")
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
        this._AiSyncPlaceholder(t)
    }

    _AiStopRec(t) {
        if (!IsObject(this._aiRec))
            this._aiRec := Map()
        this._aiRec[t] := false
        SetTimer(this.aiSttTick, 0)
        try this.ui.Update("AiInput_" t, "Foreground", "{DynamicResource InputText}")
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
        if (result != "" && result != this._aiSttLive)
            this._AiSetVoiceText(t, result)
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
        hasLive := rec && this._aiSttLive != ""
        vis := (Trim(text) == "" && !hasAtt && !hasLive) ? "Visible" : "Collapsed"
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
            tkStr := FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(fold.TK))
            xaml .= '<Grid Margin="0,4,0,0">'
                . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
                . '<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">'
                . '<Button Name="FoldTKEdit_' t '_' f '" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang("触发键") '">' this._BuildTKBtnInnerXaml(tkStr, false) '</Button>'
                . '<ComboBox Name="FoldTKType_' t '_' f '" Style="{StaticResource RmtItemCombo}" Width="82" Margin="0" SelectedIndex="' (fold.TKType - 1) '" IsEnabled="' (isUI ? "False" : "True") '" ToolTip="' GetLang("触发类型") '">'
                . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
                . '</ComboBox></StackPanel></Grid>'
        }
        xaml .= '</StackPanel></Border>'
        return xaml
    }

    _BuildFoldLayoutColDefs() {
        gap := this._FoldGroupGap()
        if (this._IsAiPanelOpen()) {
            wideGap := 8 + this._foldFrontShift
            gapCol := '<ColumnDefinition Width="100*" MinWidth="' this._AiPanelGapMin() '" MaxWidth="' wideGap '"/>'
            lastCol := '<ColumnDefinition Width="*"/>'
        } else {
            gapCol := '<ColumnDefinition Width="' gap '"/>'
            lastCol := '<ColumnDefinition Width="*"/>'
        }
        remarkGroupW := 24 + 6 + this._foldFieldW
        frontGroupW := 12 + 4 + this._foldFrontW + 4 + 24 + 4 + 24
        toolbarW := 3 * (24 + 4) + 24
        return '<ColumnDefinition Width="' remarkGroupW '"/>' gapCol
            . '<ColumnDefinition Width="' frontGroupW '"/>' gapCol
            . '<ColumnDefinition Width="' toolbarW '"/>' lastCol
    }

    ; 模块头主行：备注 | 间距 | 前台 | 同距 | 操作按钮 | 剩余
    _BuildFoldHeaderRowXaml(t, f, fold, vlMode) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        folded := vlMode ? false : fold.FoldState
        remark := vlMode ? "" : fold.Remark
        frontInfo := vlMode ? "" : fold.FrontInfo
        forbidState := vlMode ? false : fold.ForbidState
        return '<Grid ' ns ' VerticalAlignment="Center">'
            . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">' this._BuildFoldCollapseBtnXaml(t, f, folded, vlMode) this._BuildFoldRemarkFieldXaml(t, f, remark, vlMode) '</StackPanel>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center"' this._FoldFrontVisAttr(t, vlMode) '>' this._BuildFoldFrontCenterXaml(t, f, frontInfo, vlMode) '</StackPanel>'
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
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Grid>'
            . '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1"' this._BorderSnap() '>'
            . '<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>'
            . '</Border><Rectangle Height="1" VerticalAlignment="Bottom" Margin="3,0,3,1" Fill="{TemplateBinding BorderBrush}" IsHitTestVisible="False"/>'
            . '</Grid></ControlTemplate></Setter.Value></Setter>'
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
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid>'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border><Rectangle x:Name="BottomLine" Height="1" VerticalAlignment="Bottom" Margin="3,0,3,0" Fill="{TemplateBinding BorderBrush}" IsHitTestVisible="False"/>'
            . '</Grid>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd", "BottomLine") '</ControlTemplate.Triggers>'
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
            . '<Setter Property="BorderThickness" Value="1"/>'
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
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="SnapsToDevicePixels" Value="True"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid>'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1" Padding="{TemplateBinding Padding}"' this._BorderSnap() '>'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>'
            . '</Border><Rectangle x:Name="BottomLine" Height="1" VerticalAlignment="Bottom" Margin="3,0,3,1" Fill="{TemplateBinding BorderBrush}" IsHitTestVisible="False"/>'
            . '</Grid>'
            . '<ControlTemplate.Triggers>' this._RmtBtnInteractionTriggers("Bd", "BottomLine") '</ControlTemplate.Triggers>'
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
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="MinHeight" Value="24"/><Setter Property="Height" Value="24"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Padding" Value="4,0,20,0"/>'
            . '<Setter Property="SnapsToDevicePixels" Value="True"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">'
            . '<Grid' this._BorderSnap() '>'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Margin="0,0,0,1"' this._BorderSnap() '/>'
            . '<ToggleButton Background="Transparent" BorderThickness="0" Focusable="False" ClickMode="Press" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">'
            . '<ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent">'
            . '<Path Fill="{DynamicResource TextMain}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0" Data="M 0 0 L 4 4 L 8 0 Z"/>'
            . '</Border></ControlTemplate></ToggleButton.Template></ToggleButton>'
            . '<ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"/>'
            . '<TextBox x:Name="PART_EditableTextBox" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="{TemplateBinding Padding}" Focusable="True" Background="Transparent" Foreground="{TemplateBinding Foreground}" BorderThickness="0" Visibility="Hidden" IsReadOnly="{TemplateBinding IsReadOnly}"/>'
            . '<Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">'
            . '<Border x:Name="DropDownBorder" Background="{DynamicResource DropdownBg}" BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="3" Margin="0,4,0,0" Width="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="350">'
            . '<ScrollViewer Margin="0" SnapsToDevicePixels="True" Tag="ContainScroll"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>'
            . '</Border></Popup><Rectangle Height="1" VerticalAlignment="Bottom" Margin="3,0,3,1" Fill="{TemplateBinding BorderBrush}" IsHitTestVisible="False"/></Grid>'
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
    ; 行内控件的 Border 向上收 1 DIP，并在模板顶层补绘底边，避免语音宏行的描边被裁掉。
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

    _BuildTKBtnInnerXaml(tkStr, vlMode, bindingName := "TKStr") {
        kb := '&#xE92E;'
        if (vlMode) {
            ; 可见性由数据侧直接给 TKTextVis / TKGlyphVis（VListRow / VListFold 均有），
            ; 内联 DataTrigger 在注入模板中不生效，不能靠它切换
            binding := "{Binding " bindingName "}"
            return '<Grid>'
                . '<Viewbox Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Stretch" VerticalAlignment="Center" Visibility="{Binding TKTextVis}">'
                . '<TextBlock Text="' binding '" TextWrapping="NoWrap" TextAlignment="Center" FontSize="14"/>'
                . '</Viewbox>'
                . '<TextBlock Text="' kb '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="{Binding TKGlyphVis}"/>'
                . '</Grid>'
        }
        if (tkStr == "")
            return '<TextBlock Text="' kb '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
        return '<Viewbox Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Stretch" VerticalAlignment="Center">'
            . '<TextBlock Text="' this._XmlEsc(tkStr) '" TextWrapping="NoWrap" TextAlignment="Center" FontSize="14"/>'
            . '</Viewbox>'
    }

    ; 定时宏「宏配置」：未编辑=时钟 E121；已保存=秒表 E916
    _BuildTimingConfigBtnInnerXaml(vlMode, t := 0, i := 0, configured := false) {
        clock := '&#xE121;'
        timer := '&#xE916;'
        font := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"'
        if (vlMode) {
            return '<Grid ClipToBounds="False" IsHitTestVisible="False">'
                . '<TextBlock Text="' clock '" Visibility="{Binding ClockVis}"' font '/>'
                . '<TextBlock Text="' timer '" Visibility="{Binding TimerVis}"' font '/>'
                . '</Grid>'
        }
        emptyVis := configured ? "Collapsed" : "Visible"
        setVis := configured ? "Visible" : "Collapsed"
        return '<Grid ClipToBounds="False" IsHitTestVisible="False">'
            . '<TextBlock Name="TimingCfgEmpty_' t '_' i '" Text="' clock '" Visibility="' emptyVis '"' font '/>'
            . '<TextBlock Name="TimingCfgSet_' t '_' i '" Text="' timer '" Visibility="' setVis '"' font '/>'
            . '</Grid>'
    }

    ; 菜单宏/界面宏的“触发键”位置实际用于图片配置：未配置显示通用图片图标，
    ; 已配置则直接显示对应图片的缩略图。
    _BuildImageConfigBtnInnerXaml(vlMode, t := 0, i := 0, imagePath := "") {
        photo := '&#xE91B;'
        font := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource TextMain}"'
        if (vlMode) {
            return '<Grid Width="24" Height="20" IsHitTestVisible="False">'
                . '<TextBlock Text="' photo '" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="{Binding PhotoVis}"' font '/>'
                . '<Image Source="{Binding ConfigImagePath}" Width="20" Height="20" Stretch="UniformToFill" Visibility="{Binding TKThumbVis}"/>'
                . '</Grid>'
        }
        configured := imagePath != ""
        iconVis := configured ? "Collapsed" : "Visible"
        imageVis := configured ? "Visible" : "Collapsed"
        src := this._XmlEsc(StrReplace(imagePath, "\", "/"))
        return '<Grid Width="24" Height="20" IsHitTestVisible="False">'
            . '<TextBlock Name="ImageCfgGlyph_' t '_' i '" Text="' photo '" Visibility="' iconVis '" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"' font '/>'
            . '<Image Name="ImageCfgThumb_' t '_' i '" Source="' src '" Visibility="' imageVis '" Width="20" Height="20" Stretch="UniformToFill"/>'
            . '</Grid>'
    }

    _BuildVirtualItemConfigBtnInnerXaml() {
        return '<Grid>'
            . '<Grid Visibility="{Binding KeyInputVis}">' this._BuildTKBtnInnerXaml("", true) '</Grid>'
            . '<Grid Visibility="{Binding ImageConfigVis}">' this._BuildImageConfigBtnInnerXaml(true) '</Grid>'
            . '<Grid Visibility="{Binding TimingConfigVis}">' this._BuildTimingConfigBtnInnerXaml(true) '</Grid>'
            . '</Grid>'
    }

    _GetItemConfigImagePath(t, item) {
        path := item.IcoPath
        if (path == "" || path == "0")
            return ""
        if (FileExist(path))
            return path
        dirName := GetTableSymbol(t) == "UI" ? "UIIcon" : "MenuIcon"
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\" dirName "\" path
        return FileExist(fullPath) ? fullPath : ""
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

    ; 宏页签不展示模块前台；虚拟列表用绑定，实体行按表类型折叠
    _FoldFrontVisAttr(t, vlMode) {
        if (vlMode)
            return ' Visibility="{Binding ShowFrontVisibility}"'
        if (t > 0 && CheckIsSubMacroTable(t))
            return ' Visibility="Collapsed"'
        return ""
    }

    _BuildFoldFrontCenterXaml(t, f, frontInfo, vlMode) {
        fw := this._foldFrontW
        box := this._FoldFieldBoxAttrs(' IsReadOnly="True" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled"')
        iconFont := ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
        frontIcon := '<TextBlock Text="&#xE7F4;" Width="12" TextAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"' iconFont ' Margin="0,0,4,0" ToolTip="' GetLang("前台") '"/>'
        if (vlMode) {
            return frontIcon
                . '<TextBox Tag="FoldFront" Text="{Binding FoldFront}" Width="' fw '"' box '/>'
                . '<Button Tag="FoldFrontBtn" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE70F;" ToolTip="' GetLang("编辑") '"' iconFont ' Margin="4,0,0,0"/>'
                . '<Button Tag="FoldFrontHelp" Style="{StaticResource RmtFoldToolBtn}" Content="?" ToolTip="' GetLang("前台说明") '" FontSize="11" Margin="4,0,0,0"/>'
        }
        return frontIcon
            . '<TextBox Name="FoldFront_' t '_' f '" Text="' this._XmlEsc(frontInfo) '" Width="' fw '"' box '/>'
            . '<Button Name="FoldFrontBtn_' t '_' f '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE70F;" ToolTip="' GetLang("编辑") '"' iconFont ' Margin="4,0,0,0"/>'
            . '<Button Name="FoldFrontHelp_' t '_' f '" Style="{StaticResource RmtFoldToolBtn}" Content="?" ToolTip="' GetLang("前台说明") '" FontSize="11" Margin="4,0,0,0"/>'
    }

    _BuildItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        item := tableItem.Items[i]
        isMacro := CheckIsMacroTable(t)
        isNormal := CheckIsNormalTable(t)
        isTriggerStr := CheckIsStringMacroTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isSubMacro := CheckIsSubMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isVoice := GetTableSymbol(t) == "Voice"
        isNetwork := GetTableSymbol(t) == "Network"
        canEditTKType := isNormal || isTriggerStr

        if (isVoice) {
            ; 语音宏：触发键列显示唤醒词
            tkStr := item.VoiceKeywords
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        } else if (isNetwork) {
            ; §23 网络宏：触发键列显示「复制链接」，点击/右键=直接复制单次 URL
            tkStr := item.ID == "" ? GetLang("编辑") : GetLang("复制链接")
        } else if (isTiming) {
            tkStr := ""
        } else {
            tkStr := FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
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
            . '<DockPanel Grid.Column="4" LastChildFill="True" HorizontalAlignment="Stretch" Visibility="' (isSubMacro ? "Collapsed" : "Visible") '" Margin="' ((isMenu || isUI) ? "45,0,-45,0" : "0") '">'
            . '<Button Name="TKBtn_' t '_' i '" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang((isMenu || isUI) ? "编辑" : (isTiming ? "定时" : "触发键")) '" IsEnabled="' (isSubMacro ? "False" : "True") '">' ((isMenu || isUI) ? this._BuildImageConfigBtnInnerXaml(false, t, i, this._GetItemConfigImagePath(t, item)) : (isTiming ? this._BuildTimingConfigBtnInnerXaml(false, t, i, HasTimingConfig(item)) : this._BuildTKBtnInnerXaml(tkStr, false))) '</Button>'
            . '</DockPanel>'
            . (isNetwork ? '<Button Grid.Column="5" Name="NetHelp_' t '_' i '" Style="{StaticResource RmtItemFieldBtn}" Width="24" HorizontalAlignment="Left" Margin="0,0,4,0" Content="&#xE946;" ToolTip="' GetLang("网络触发说明") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>' : '')
            . '<ComboBox Grid.Column="5" Name="TKType_' t '_' i '" Style="{StaticResource RmtItemCombo}" Margin="0" SelectedIndex="' tkTypeIdx '" IsEnabled="' (canEditTKType ? "True" : "False") '" Visibility="' ((isSubMacro || isNetwork || isMenu || isUI || isVoice || isTiming) ? "Collapsed" : "Visible") '" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . this._BuildItemEditGroupWrap(false, t
                , this._BuildItemEditBtnXaml(t, i, item, false)
                . '<ComboBox Grid.Column="1" Name="Loop_' t '_' i '" Style="{StaticResource RmtItemCombo}" Margin="0,0,4,0" IsEditable="True" IsEnabled="' (isMacro ? "True" : "False") '" ToolTip="' GetLang("循环次数") '">'
                . '<ComboBoxItem Content="' GetLang("无限") '"/>'
                . '</ComboBox>'
                . '<Button Grid.Column="2" Name="Setting_' t '_' i '" Style="{StaticResource RmtItemPrimaryBtn}" Margin="0" Content="&#xE713;" ToolTip="' GetLang("设置") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"/>')
            . '<StackPanel Grid.Column="11" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Name="Copy_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE8C8;" ToolTip="' GetLang("复制") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . '<Button Name="Share_' t '_' i '" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE898;" ToolTip="' GetLang("分享到论坛") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0,0,4,0"/>'
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
        col := ' Grid.Column="0"'
        if (vlMode)
            return '<Button' col ' Tag="Edit" Style="{StaticResource RmtItemEditBtn}" ToolTip="' tip '">' this._BuildItemEditBtnInnerXaml(true) '</Button>'
        kind := GetMacroEditKind(item.Macro)
        return '<Button' col ' Name="Edit_' t '_' i '" Style="{StaticResource RmtItemEditBtn}" ToolTip="' tip '">' this._BuildItemEditBtnInnerXaml(false, t, i, kind) '</Button>'
    }

    ; 宏编辑器 / 循环次数 / 设置：原列宽不变。宏页签挂到模块「前台」同列，右侧压缩时一起动。
    _BuildItemEditGroupWrap(vlMode, t, inner) {
        body := this._BuildItemEditGroupBody(inner)
        if (!vlMode) {
            if (t > 0 && CheckIsSubMacroTable(t))
                return this._BuildItemEditOverlayHost(body, "")
            return this._BuildItemEditNormalHost(body, "")
        }
        return this._BuildItemEditNormalHost(body, this._EditGroupHostVis(true))
            . this._BuildItemEditOverlayHost(body, this._EditGroupHostVis(false))
    }

    _BuildItemEditGroupBody(inner) {
        L := this._ItemLayoutWide()
        return '<Grid HorizontalAlignment="Left" VerticalAlignment="Stretch">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="' L["edit"] '"/>'
            . '<ColumnDefinition Width="' L["loop"] '"/>'
            . '<ColumnDefinition Width="' L["setting"] '"/>'
            . '</Grid.ColumnDefinitions>'
            . inner
            . '</Grid>'
    }

    _BuildItemEditNormalHost(body, visStyle) {
        return '<Grid Grid.Column="7" Grid.ColumnSpan="3" HorizontalAlignment="Left" VerticalAlignment="Stretch">'
            . visStyle
            . body
            . '</Grid>'
    }

    _BuildItemEditOverlayHost(body, visStyle) {
        return '<Grid Grid.Column="0" Grid.ColumnSpan="13" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="' this._SubMacroOverlayMargin() '" ClipToBounds="False">'
            . visStyle
            . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
            . '<Grid Grid.Column="2" HorizontalAlignment="Left" VerticalAlignment="Stretch" Margin="' this._SubMacroFrontOffset() ',0,0,0">'
            . body
            . '</Grid></Grid>'
    }

    ; 宏页签：Visible 当无触发键（TKBtnEnabled=False）；其它页签相反
    _EditGroupHostVis(showWhenHasTK) {
        defVis := showWhenHasTK ? "Visible" : "Collapsed"
        altVis := showWhenHasTK ? "Collapsed" : "Visible"
        return '<Grid.Style><Style TargetType="Grid"><Setter Property="Visibility" Value="' defVis '"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding TKBtnEnabled}" Value="False">'
            . '<Setter Property="Visibility" Value="' altVis '"/>'
            . '</DataTrigger></Style.Triggers></Style></Grid.Style>'
    }

    ; 宏行内容区相对模块头内边距的差：把覆盖层原点对齐到模块头
    _SubMacroOverlayMargin() {
        itemPad := 4, foldPad := 8
        return (foldPad - itemPad - this._ItemDragColW()) ",0,0,0"
    }

    ; 宽布局下「宏编辑器」相对模块前台左缘的间距；压缩时沿用此值，相对位置不变
    _SubMacroFrontOffset() {
        L := this._ItemLayoutWide()
        itemLeft := 4 + this._ItemDragColW()
        editLeft := itemLeft + L["color"] + L["seq"] + L["remark"] + L["spacerTK"] + L["tk"] + L["type"] + L["spacerEdit"]
        remarkGroupW := 24 + 6 + this._foldFieldW
        frontLeft := 8 + remarkGroupW + 8 + this._foldFrontShift
        return editLeft - this._subMacroEditShift - frontLeft
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
        isNetwork := GetTableSymbol(t) == "Network"

        editTK := isTriggerStr ? OnItemEditTriggerStr : OnItemEditTriggerKey
        editTK := isTiming ? OnItemEditTiming : editTK
        editTK := isMenu ? OnItemMenuMacroSettingClick : editTK
        editMacro := isMacro ? OnItemEditMacro : OnItemEditReplaceKey
        if (isUI)
            editTK := OnUIMacroSettingClick
        else if (isNetwork)
            editTK := (*) => OnItemNetworkCopyUrl(tableItem, i)   ; §23 网络宏：触发键列点击 → 直接复制单次 URL
        else if (GetTableSymbol(t) == "Voice")
            ; 与虚拟列表路径一致：离开 XAML 点击回调后再创建语音编辑窗口。
            editTK := ObjBindMethod(this, "_DeferVoiceTrigger")

        loopStr := tableItem.Items[i].LoopCount == "-1" ? GetLang("无限") : tableItem.Items[i].LoopCount
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)

        this._Bind("SeqBtn_" t "_" i, "Click", ObjBindMethod(this, "SelectSideTreeItem", t, i))
        this._Bind("TKBtn_" t "_" i, "Click", editTK.Bind(tableItem, i))
        ; §23 网络宏：右键同为直接复制单次 URL；其余表保持自定义触发串
        this._Bind("TKBtn_" t "_" i, "MouseRightButtonUp", isNetwork ? ((*) => OnItemNetworkCopyUrl(tableItem, i)) : OnItemCustomEditTriggerStr.Bind(tableItem, i))
        ; §23 网络宏：触发键左侧「?」按钮 → 网络触发说明弹窗（仅网络表行存在该按钮）
        if (isNetwork)
            this._Bind("NetHelp_" t "_" i, "Click", OnItemNetworkHelp.Bind(tableItem, i))
        this._Bind("Setting_" t "_" i, "Click", OnItemEditMacroSetting.Bind(tableItem, i))
        this._Bind("Edit_" t "_" i, "Click", editMacro.Bind(tableItem, i))
        this._Bind("Forbid_" t "_" i, "Click", OnItemForbidToggle.Bind(tableItem, i))
        this._Bind("Copy_" t "_" i, "Click", OnItemCopyMacroBtnClick.Bind(tableItem, i))
        this._Bind("Del_" t "_" i, "Click", OnItemDelMacroBtnClick.Bind(tableItem, i))
    }

    ; 旧的实体行路径也复用虚拟列表宿主的安全调度，避免在 XAML 点击回调中重入开窗。
    _DeferVoiceTrigger(tableItem, index, *) {
        if (IsObject(this._vl)) {
            this._vl._DeferDialog("VoiceTrigger", OnItemVoiceTriggerSetting.Bind(tableItem, index))
            return
        }
        ; 仅作为初始化早期兜底；正常主窗口生命周期总会先建立 _vl。
        this._voiceDlgFn := OnItemVoiceTriggerSetting.Bind(tableItem, index)
        SetTimer(this._voiceDlgFn, -50)
    }

    _BindFoldRows(t) {
        tableItem := MySoftData.TableInfo[t]
        for f, fold in tableItem.Folds {
            this._Bind("FoldFrontBtn_" t "_" f, "Click", OnFoldFrontInfoEdit.Bind(tableItem, f))
            this._Bind("FoldFrontHelp_" t "_" f, "Click", OnFoldFrontHelp.Bind(tableItem, f))
            this._Bind("FoldBtn_" t "_" f, "Click", OnFoldBtnClick.Bind(tableItem, f))
            this._Bind("FoldTKEdit_" t "_" f, "Click", OnFlodTKEditClick.Bind(tableItem, f))
            this._Bind("FoldAddMacro_" t "_" f, "Click", OnItemAddMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldPasteMacro_" t "_" f, "Click", OnItemPasteMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldShare_" t "_" f, "Click", OnFoldShareBtnClick.Bind(tableItem, f))
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
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        isVoice := GetTableSymbol(t) == "Voice"
        if (isVoice) {
            ; 语音宏：触发键列显示唤醒词（无按键）
            tkStr := item.VoiceKeywords
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        } else if (isTiming) {
            tkStr := ""
        } else {
            tkStr := FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(item.TK))
            tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        }
        loopStr := item.LoopCount == "-1" ? GetLang("无限") : item.LoopCount
        tkTypeIdx := item.TriggerType - 1
        if (isUI)
            tkTypeIdx := 3
        this.ui.Update("Remark_" t "_" i, "Text", item.Remark)
        if (CheckIsNormalTable(t) && tkStr == GetLang("编辑"))
            tkStr := ""
        if (isMenu || isUI) {
            imagePath := this._GetItemConfigImagePath(t, item)
            configured := imagePath != ""
            this.ui.Update("ImageCfgGlyph_" t "_" i, "Visibility", configured ? "Collapsed" : "Visible")
            this.ui.Update("ImageCfgThumb_" t "_" i, "Source", StrReplace(imagePath, "\", "/"))
            this.ui.Update("ImageCfgThumb_" t "_" i, "Visibility", configured ? "Visible" : "Collapsed")
        } else if (isTiming) {
            configured := HasTimingConfig(item)
            this.ui.Update("TimingCfgEmpty_" t "_" i, "Visibility", configured ? "Collapsed" : "Visible")
            this.ui.Update("TimingCfgSet_" t "_" i, "Visibility", configured ? "Visible" : "Collapsed")
        } else if (tkStr == "") {
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
            . '<DockPanel Grid.Column="4" LastChildFill="True" HorizontalAlignment="Stretch">'
            . '<DockPanel.Style><Style TargetType="DockPanel"><Setter Property="Margin" Value="0"/><Setter Property="Visibility" Value="Visible"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding ImageConfigVis}" Value="Visible"><Setter Property="Margin" Value="45,0,-45,0"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding TKBtnEnabled}" Value="False"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
            . '</Style.Triggers></Style></DockPanel.Style>'
            . '<Button Tag="TKBtn" IsEnabled="{Binding TKBtnEnabled}" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang("编辑") '">' this._BuildVirtualItemConfigBtnInnerXaml() '</Button>'
            . '</DockPanel>'
            . '<Button Grid.Column="5" Tag="NetHelp" Visibility="{Binding NetHelpVis}" Style="{StaticResource RmtItemFieldBtn}" Width="24" HorizontalAlignment="Left" Margin="0,0,4,0" Content="&#xE946;" ToolTip="' GetLang("网络触发说明") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . '<ComboBox Grid.Column="5" Tag="TKType" SelectedIndex="{Binding TKType}" IsEnabled="{Binding TKTypeEnabled}" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBox.Style><Style TargetType="ComboBox" BasedOn="{StaticResource RmtItemCombo}"><Setter Property="Margin" Value="0"/><Setter Property="Visibility" Value="Visible"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding NetTypeVis}" Value="Collapsed"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
            . '<DataTrigger Binding="{Binding TKBtnEnabled}" Value="False"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger>'
            . '</Style.Triggers></Style></ComboBox.Style>'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . this._BuildItemEditGroupWrap(true, 0
                , this._BuildItemEditBtnXaml(0, 0, "", true)
                . '<ComboBox Grid.Column="1" Tag="Loop" Text="{Binding LoopText}" IsEditable="True" IsEnabled="{Binding LoopEnabled}" Style="{StaticResource RmtItemCombo}" Margin="0,0,4,0" ToolTip="' GetLang("循环次数") '">'
                . '<ComboBoxItem Content="' GetLang("无限") '"/>'
                . '</ComboBox>'
                . '<Button Grid.Column="2" Tag="Setting" Style="{StaticResource RmtItemPrimaryBtn}" Margin="0" Content="&#xE713;" ToolTip="' GetLang("设置") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"/>')
            . '<StackPanel Grid.Column="11" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Tag="Copy" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE8C8;" ToolTip="' GetLang("复制") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"/>'
            . '<Button Tag="Share" Style="{StaticResource RmtFoldToolBtn}" Content="&#xE898;" ToolTip="' GetLang("分享到论坛") '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Margin="0,0,4,0"/>'
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
            . '<Grid Margin="0,4,0,0" Visibility="{Binding ShowTKRowVisibility}">'
            . '<Grid.ColumnDefinitions>' this._BuildFoldLayoutColDefs() '</Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">'
            . '<Button Tag="FoldTKEdit" Style="{StaticResource RmtItemFieldBtn}" Width="120" Margin="0,0,4,0" ToolTip="' GetLang("触发键") '">' this._BuildTKBtnInnerXaml("", true, "FoldTKStr") '</Button>'
            . '<ComboBox Tag="FoldTKType" SelectedIndex="{Binding FoldTKType}" IsEnabled="{Binding FoldTKTypeEnabled}" Style="{StaticResource RmtItemCombo}" Width="82" Margin="0" ToolTip="' GetLang("触发类型") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox></StackPanel></Grid>'
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

    ; 模块行工具按钮：新增宏 / 粘贴宏 / 分享到论坛 / 禁用 / 删除
    _BuildFoldToolbarXaml(t, f, forbidState, vlMode := false) {
        return this._BuildFoldIconBtn("FoldAddMacro", "FoldAddMacro", t, f, "+", GetLang("新增宏"), vlMode, false)
            . this._BuildFoldIconBtn("FoldPasteMacro", "FoldPasteMacro", t, f, "&#xE77F;", GetLang("粘贴宏"), vlMode)
            . this._BuildFoldIconBtn("FoldShare", "FoldShare", t, f, "&#xE898;", GetLang("分享到论坛"), vlMode)
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
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Tool 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Tool")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)

        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        iconFont := 'Segoe Fluent Icons, Segoe MDL2 Assets'
        field(label, glyph, name, value) {
            return '<Grid Margin="0,0,16,10"><Grid.ColumnDefinitions><ColumnDefinition Width="116"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="' glyph '" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" Margin="0,0,6,0"/><TextBlock Text="' this._XmlEsc(label) '" VerticalAlignment="Center"/></StackPanel>'
                . '<TextBox Grid.Column="1" Name="' name '" Text="' this._XmlEsc(value) '" Height="26" MinHeight="26" Padding="6,0" VerticalContentAlignment="Center" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/></Grid>'
        }
        card(title, glyph, body, margin := "0", headerRight := "") {
            glyphXaml := glyph == "" ? "" : '<TextBlock Text="' glyph '" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" FontSize="13" Margin="0,0,7,0"/>'
            return '<Border Margin="' margin '" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1.25" CornerRadius="7" Padding="0">'
                . '<Grid><Grid.RowDefinitions><RowDefinition Height="38"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
                . '<Border Background="{DynamicResource TitleBarColor}" CornerRadius="7,7,0,0" Padding="12,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Orientation="Horizontal" VerticalAlignment="Center">' glyphXaml '<TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" VerticalAlignment="Center"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">' headerRight '</StackPanel></Grid></Border>'
                . '<Grid Grid.Row="1" Margin="14,12,14,14">' body '</Grid></Grid></Border>'
        }
        openBtn(name, glyph, text, primary := false) {
            bg := primary ? '{DynamicResource ActionBg}' : '{DynamicResource ControlBg}'
            fg := primary ? '{DynamicResource ActionText}' : '{DynamicResource TextMain}'
            br := primary ? '{DynamicResource ActionStroke}' : '{DynamicResource ControlBorder}'
            return '<Button Name="' name '" Height="28" MinHeight="28" Padding="10,0" Background="' bg '" Foreground="' fg '" BorderBrush="' br '" BorderThickness="1" Cursor="Hand">'
                . '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/></Grid.ColumnDefinitions><TextBlock Text="' glyph '" FontFamily="' iconFont '" VerticalAlignment="Center" Margin="0,0,6,0"/><TextBlock Grid.Column="1" Text="' this._XmlEsc(text) '" VerticalAlignment="Center"/><TextBlock Grid.Column="2" Text="↗" FontSize="8" VerticalAlignment="Top" HorizontalAlignment="Right"/></Grid></Button>'
        }
        actionRow(title, detail, hotkey, buttonXaml) {
            return '<Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" CornerRadius="5" Padding="10,7" Margin="0,0,0,8"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
                . '<StackPanel><StackPanel Orientation="Horizontal"><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold"/><TextBlock Text="' this._XmlEsc(hotkey) '" Opacity="0.65" Margin="7,0,0,0"/></StackPanel><TextBlock Text="' this._XmlEsc(detail) '" FontSize="11" Opacity="0.7" Margin="0,3,0,0"/></StackPanel>'
                . '<StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">' buttonXaml '</StackPanel></Grid></Border>'
        }
        iconBtn(name, glyph, tip, action := false) {
            bg := action ? '{DynamicResource ActionBg}' : '{DynamicResource ControlBg}'
            fg := action ? '{DynamicResource ActionText}' : '{DynamicResource TextMain}'
            br := action ? '{DynamicResource ActionStroke}' : '{DynamicResource ControlBorder}'
            return '<Button Name="' name '" Content="' glyph '" ToolTip="' this._XmlEsc(tip) '" FontFamily="' iconFont '" FontSize="12" Width="30" Height="28" MinHeight="28" Padding="0" Margin="0,0,6,0" Background="' bg '" Foreground="' fg '" BorderBrush="' br '" BorderThickness="1" Cursor="Hand"/>'
        }

        monitorBody := '<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">' openBtn("BtnOpenVarListen", "&#xE7B3;", GetLang("变量监视器"), true) '</StackPanel>'
            . '<StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,12,0,12" VerticalAlignment="Center"><TextBlock Text="&#xE962;" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" Margin="0,0,7,0"/><TextBlock Text="' GetLang("鼠标信息") '" FontWeight="Bold" VerticalAlignment="Center"/><TextBlock Name="TxtToolCheckKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolCheckHotkey) '" Opacity="0.65" Margin="9,0,8,0" VerticalAlignment="Center"/><CheckBox Name="ChkToolCheck" Content="' GetLang("开关") '" Style="{StaticResource ToolSwitch}"/> </StackPanel>'
            . '<Grid Grid.Row="2"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel>'
            . field("屏幕坐标", "&#xE81D;", "TxtMousePos", MainSoftData.PosStr)
            . field("窗口标题", "&#xE8A5;", "TxtProcessTile", MainSoftData.ProcessTile)
            . field("窗口类", "&#xE8D7;", "TxtProcessClass", MainSoftData.ProcessClass)
            . field("句柄 Id", "&#xE71B;", "TxtProcessId", MainSoftData.ProcessId) '</StackPanel><StackPanel Grid.Column="1">'
            . field("窗口坐标", "&#xE7F4;", "TxtWinPos", MainSoftData.WinPosStr)
            . field("进程名", "&#xE9D9;", "TxtProcessName", MainSoftData.ProcessName)
            . field("进程 PID", "&#xE950;", "TxtProcessPid", MainSoftData.ProcessPid)
            . field("位置颜色", "&#xE790;", "TxtColor", MainSoftData.Color) '</StackPanel></Grid></Grid>'

        auxiliaryBody := '<StackPanel><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="&#xE840;" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" Margin="0,0,7,0"/><TextBlock Text="' GetLang("窗口置顶") '" FontWeight="Bold" VerticalAlignment="Center"/><CheckBox Name="ChkAlwaysOnTop" Content="' GetLang("保持 RMT 主窗口在最前") '" Style="{StaticResource ToolSwitch}" Margin="12,0,0,0"/></StackPanel><StackPanel Orientation="Horizontal" Margin="0,12,0,0">' openBtn("BtnFileCheck", "&#xE8B7;", GetLang("文件校验"), true) '<Button Name="BtnFileCheckHelp" Content="?" ToolTip="' GetLang("文件校验说明") '" Width="28" Height="28" MinHeight="28" Padding="0" Margin="8,0,0,0"/></StackPanel></StackPanel>'
        recordBody := '<StackPanel>'
            . actionRow(GetLang("指令录制"), GetLang("记录鼠标与键盘操作"), FormatHotkeyDisplay(MainSoftData.ToolRecordMacroHotKey), '<CheckBox Name="ChkToolCheckRecord" Content="&#xE7C8;" ToolTip="' GetLang("开始或停止录制") '" Style="{StaticResource ToolRecordSwitch}"/>')
            . actionRow(GetLang("图片提取文本"), GetLang("从截图或本地图片识别文本"), FormatHotkeyDisplay(MainSoftData.ToolTextFilterHotKey), iconBtn("BtnTextShot", "&#xE7A8;", GetLang("截图提取文本")) iconBtn("BtnTextImage", "&#xE8B7;", GetLang("从图片提取文本")))
            . actionRow(GetLang("语音提取文本"), GetLang("打开语音识别窗口并写入输出区"), "", openBtn("BtnStt", "&#xE720;", GetLang("打开"), true)) '</StackPanel>'
        outputBody := '<TextBox Name="TxtToolText" Text="" Height="200" AcceptsReturn="True" VerticalContentAlignment="Top" TextWrapping="Wrap" Padding="8,6" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
        clearToolTextBtn := '<Button Name="BtnClearToolText" Content="&#xE74D;" ToolTip="' GetLang("清空内容") '" FontFamily="' iconFont '" Width="28" Height="26" MinHeight="26" Padding="0"/>'

    toolXaml := '<Grid ' ns ' Margin="2,2,3,10"><Grid.Resources>'
            . '<Style x:Key="ToolSwitch" TargetType="CheckBox"><Setter Property="Margin" Value="0"/><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><StackPanel Orientation="Horizontal"><Border x:Name="Track" Width="34" Height="18" CornerRadius="9" Background="{DynamicResource ControlBorder}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><Ellipse x:Name="Thumb" Width="12" Height="12" Fill="{DynamicResource ControlBg}" HorizontalAlignment="Left" Margin="2"/></Border><ContentPresenter Margin="7,0,0,0" VerticalAlignment="Center"/></StackPanel><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="{DynamicResource ActionBg}"/><Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style x:Key="ToolRecordSwitch" TargetType="CheckBox"><Setter Property="Width" Value="30"/><Setter Property="Height" Value="28"/><Setter Property="Padding" Value="0"/><Setter Property="FontFamily" Value="' iconFont '"/><Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="Background" Value="{DynamicResource ControlBg}"/><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="HorizontalContentAlignment" Value="Center"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionBg}"/><Setter Property="Foreground" Value="{DynamicResource ActionText}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
            . '</Grid.Resources><Grid.ColumnDefinitions><ColumnDefinition Width="35*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="65*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="14"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<StackPanel Grid.Column="0">' card(GetLang("辅助操作"), "&#xE713;", auxiliaryBody) card(GetLang("录制与提取"), "&#xE7C8;", recordBody, "0,14,0,0") '</StackPanel>'
            . '<Border Grid.Column="2">' card(GetLang("监视"), "&#xE7B3;", monitorBody) '</Border><Border Grid.Row="2" Grid.ColumnSpan="3">' card(GetLang("录制指令或提取文本内容"), "", outputBody, "0", clearToolTextBtn) '</Border></Grid>'
        Add(toolXaml)

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

    ; ============ 全局页：系统 / 宏 / 显示页签 / 界面 / AI 助手 ============
    BuildSettingTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Setting 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Setting")
        ; 设置页导航需要与 Tab 内容外框相接：仅取消本页宿主默认的 8px 左边距。
        this.ui.Update(p, "Margin", "0,6,4,10")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'

        ; ============ 设置中心（参考 Web\SettingsLayoutReference.html）============
        ; 左侧 8 页导航 + 右侧卡片页，全部设置内联；控件沿用既有 Name 与 MainSoftData 字段；
        ; 落盘仍由主界面「应用并保存」统一处理（OnSaveSetting 的 CheckAndAddDirty 已覆盖这些键）。
        iconFont := 'Segoe Fluent Icons, Segoe MDL2 Assets'
        navStyle := '<Style x:Key="SetNavItem" TargetType="RadioButton">'
            . '<Setter Property="Height" Value="36"/><Setter Property="Margin" Value="0"/><Setter Property="Padding" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalAlignment" Value="Stretch"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">'
            . '<Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="0" CornerRadius="0" Padding="0" Margin="0,0,-8,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="3"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Rectangle x:Name="Bar" Grid.Column="0" Width="3" RadiusX="1.5" RadiusY="1.5" Fill="{DynamicResource Accent}" Visibility="Collapsed" Margin="0,5,0,5"/>'
            . '<ContentPresenter Grid.Column="1" Margin="8,0,0,0" VerticalAlignment="Center"/></Grid></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListAltBg}"/></Trigger>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="Bar" Property="Visibility" Value="Visible"/><Setter Property="FontWeight" Value="Bold"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        switchStyle := '<Style x:Key="SetSwitch" TargetType="CheckBox"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="50"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border x:Name="Track" Width="42" Height="24" CornerRadius="12" Background="{DynamicResource ControlBorder}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><Grid><TextBlock x:Name="OffGlyph" Text="×" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource TextSub}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,7,1"/><Ellipse x:Name="Thumb" Width="18" Height="18" Fill="{DynamicResource ControlBg}" HorizontalAlignment="Left" Margin="2"/></Grid></Border><ContentPresenter Grid.Column="1" VerticalAlignment="Center"/></Grid><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="{DynamicResource ActionBg}"/><Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="OffGlyph" Property="Visibility" Value="Collapsed"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        fieldStyles := '<Style TargetType="TextBox"><Setter Property="Height" Value="33"/><Setter Property="MinHeight" Value="33"/><Setter Property="Padding" Value="10,0"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Foreground" Value="{DynamicResource InputText}"/><Setter Property="Background" Value="{DynamicResource InputBg}"/><Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/></Border></ControlTemplate></Setter.Value></Setter></Style>'
            . '<Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="MinHeight" Value="30"/></Style>'
            . '<Style x:Key="SetTabButton" TargetType="CheckBox"><Setter Property="Width" Value="85"/><Setter Property="Height" Value="32"/><Setter Property="Margin" Value="0,4,8,4"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Border x:Name="Bd" CornerRadius="6" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1"><Grid><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/><Ellipse x:Name="Dot" Visibility="Collapsed" Width="7" Height="7" Fill="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,5,6,0"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="Dot" Property="Visibility" Value="Visible"/><Setter Property="FontWeight" Value="Bold"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        ; ---------- 行/卡片构建 ----------
        this._setHelpMap := Map()
        this._setHelpSeq := 0
        helpFnByLabel := Map()
        helpFnByLabel[GetLang("多线程数")] := OnClickMutiThreadHelpBtn
        helpFnByLabel[GetLang("模态子窗口")] := OnClickModalSubGuiHelpBtn
        helpFnByLabel[GetLang("仅前台运行宏")] := OnClickCheckForegroundHelpBtn
        helpFnByLabel[GetLang("管理员启动")] := OnClickAdminStartHelpBtn
        helpFnByLabel[GetLang("重复按下行为")] := OnClickKeyDownDownHelpBtn
        helpFnByLabel[GetLang("宏终止方式")] := OnClickMacroStopHelpBtn
        helpFnByLabel[GetLang("自动松开修饰键")] := OnClickAutoLoosenModifierHelpBtn
        helpFnByLabel[GetLang("连续触发")] := OnClickContinuousTriggerHelpBtn
        helpFnByLabel[GetLang("宏手柄类型")] := OnClickMacroJoyTypeHelpBtn
        helpFnByLabel[GetLang("手柄映射")] := OnClickTriggerJoyTypeHelpBtn
        dot(tip, title := "") {
            if (tip == "")
                return ""
            this._setHelpSeq += 1
            name := "BtnSetHelp_" this._setHelpSeq
            this._setHelpMap[name] := {title: title != "" ? title : GetLang("说明"), text: tip, fn: helpFnByLabel.Has(title) ? helpFnByLabel[title] : ""}
            return '<Button Name="' name '" Content="?" Width="24" Height="24" MinHeight="24" Padding="4,2" Margin="6,0,0,0" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Cursor="Hand"/>'
        }
        afterHint(ctrl, hint) {
            if (InStr(ctrl, "<Slider"))
                return '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
                    . ctrl
                    . '<TextBlock Grid.Column="1" Text="' this._XmlEsc(hint) '" MaxWidth="200" Margin="10,0,0,0" FontSize="12" Foreground="{DynamicResource TextSub}" TextWrapping="Wrap" VerticalAlignment="Center"/></Grid>'
            return '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . ctrl
                . '<TextBlock Grid.Column="1" Text="' this._XmlEsc(hint) '" Margin="10,0,0,0" FontSize="12" Foreground="{DynamicResource TextSub}" TextWrapping="Wrap" VerticalAlignment="Center"/></Grid>'
        }
        row(label, ctrl, tip := "", w := "104", lblName := "") {
            helpBtn := ""
            if (tip != "") {
                if (helpFnByLabel.Has(label) || InStr(tip, "`n"))
                    helpBtn := StrReplace(dot(tip, label), "<Button ", '<Button DockPanel.Dock="Right" ')
                else
                    ctrl := afterHint(ctrl, tip)
            }
            return '<Border MinHeight="48" Padding="0,5" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="0,0,0,0.5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="' w '"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . '<DockPanel VerticalAlignment="Center" LastChildFill="True">' helpBtn '<TextBlock' (lblName == "" ? "" : ' Name="' lblName '"') ' Text="' this._XmlEsc(label) '" TextWrapping="Wrap" FontWeight="SemiBold" Foreground="{DynamicResource TextMain}" FontSize="13"/></DockPanel>'
                . '<Grid Grid.Column="2" VerticalAlignment="Center">' ctrl '</Grid></Grid></Border>'
        }
        tog(label, name, val, desc := "", tip := "", w := "104", lblName := "") {
            help := tip != "" ? tip : desc
            return row(label, '<CheckBox Name="' name '" IsChecked="' (val ? "True" : "False") '" Style="{StaticResource SetSwitch}"/>', help, w, lblName)
        }
        togI(label, name, val) {
            return '<CheckBox Name="' name '" Content="' this._XmlEsc(label) '" IsChecked="' (val ? "True" : "False") '" Style="{StaticResource SetTabButton}" ToolTip="' GetLang("隐藏的页签不影响宏触发，保存后重启生效。") '"/>'
        }
        cmb(label, name, items, sel, zero := false, tip := "", w := "104") {
            selIdx := ""
            itemsXaml := ""
            for k, it in items {
                isSel := IsInteger(sel) ? (k == Integer(sel) + (zero ? 1 : 0)) : (it == sel)
                if (isSel)
                    selIdx := k - 1
                itemsXaml .= '<ComboBoxItem Content="' this._XmlEsc(it) '"/>'
            }
            selAttr := (selIdx == "") ? "" : ' SelectedIndex="' selIdx '"'
            return row(label, '<ComboBox Name="' name '" Height="33" MinHeight="33" Padding="10,0" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"' selAttr '>' itemsXaml '</ComboBox>', tip, w)
        }
        num(label, name, val, tip := "", w := "104", boxW := "96") {
            return row(label, '<TextBox Name="' name '" Text="' this._XmlEsc(String(val)) '" Height="33" MinHeight="33" Padding="10,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>', tip, w)
        }
        ; 随机浮动：标签与问号右移，输入框延展至右边缘。
        numCompact(label, name, val, tip) {
            return row(label, '<TextBox Name="' name '" Text="' this._XmlEsc(String(val)) '" Height="33" MinHeight="33" Padding="10,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>', tip, "188")
        }
        txt(label, name, val, tip := "", w := "104", boxW := "240") {
            return row(label, '<TextBox Name="' name '" Text="' this._XmlEsc(String(val)) '" Height="33" MinHeight="33" Padding="10,0" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>', tip, w)
        }
        sld(label, name, valName, val, mn, mx, tk, tip := "", w := "104") {
            return row(label, '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="9"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Slider Name="' name '" Height="28" Minimum="' mn '" Maximum="' mx '" Value="' val '" TickFrequency="' tk '" IsSnapToTickEnabled="True" VerticalAlignment="Center" Cursor="Hand"/>'
                . '<TextBox Grid.Column="2" Name="' valName '" Text="' val '" TextAlignment="Center"/></Grid>', tip, w)
        }
        btnRow(label, ctrl, tip := "", w := "104") {
            return row(label, ctrl, tip, w)
        }
        card(title, glyph, body, margin := "0", headerRight := "", modId := "") {
            ; 每张卡的最后一行不画下分隔线；前面的行保留，用于所有类别的统一布局。
            body := RegExReplace(body, 's)(.*)<Border([^>]*?)BorderThickness="0,0,0,0\.5"', '$1<Border$2BorderThickness="0"')
            g := glyph == "" ? "" : '<TextBlock Text="' glyph '" FontFamily="' iconFont '" Foreground="{DynamicResource Accent}" FontSize="12" Margin="0,0,6,0" VerticalAlignment="Center"/>'
            if (modId != "")
                headerRight := '<Button Name="BtnSetReset_' modId '" Content="&#xE72C;" FontFamily="' iconFont '" FontSize="12" Width="22" Height="22" MinHeight="22" Padding="0" Margin="0,0,2,0" VerticalAlignment="Center" Cursor="Hand" ToolTip="' this._XmlEsc(GetLang("重置")) '" Visibility="Collapsed" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource TextSub}"/>' headerRight
            return '<Border Margin="' margin '" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="10" Padding="0">'
                . '<Grid><Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
                . '<Border Background="{DynamicResource TitleBarColor}" CornerRadius="10,10,0,0" Padding="10,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Orientation="Horizontal" VerticalAlignment="Center">' g '<TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">' headerRight '</StackPanel></Grid></Border>'
                . '<StackPanel Grid.Row="1" Margin="15,6,15,11">' body '</StackPanel></Grid></Border>'
        }
        twoCol(l, r) {
            ; 左右两列各自垂直堆叠，互不卡行高，避免中间断层。整行模块（如主题颜色）放在 twoCol 外面。
            return '<Grid VerticalAlignment="Top"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" VerticalAlignment="Top">' l '</StackPanel><StackPanel Grid.Column="2" VerticalAlignment="Top">' r '</StackPanel></Grid>'
        }
        navItem(id, glyph, text, checked := false) {
            return '<RadioButton Name="SetNav_' id '" GroupName="SetNav" Style="{StaticResource SetNavItem}"' (checked ? ' IsChecked="True"' : '') '><StackPanel Orientation="Horizontal" Margin="12,0,0,0"><TextBlock Text="' glyph '" FontFamily="' iconFont '" FontSize="14" Foreground="{DynamicResource Accent}" Margin="0,0,9,0" VerticalAlignment="Center"/><TextBlock Name="SetNavText_' id '" Text="' this._XmlEsc(text) '" VerticalAlignment="Center" FontSize="13"/></StackPanel></RadioButton>'
        }
        pending(body) {
            return '<Expander Header="' GetLang("待确认的原有功能") '" IsExpanded="False" Margin="0,20,0,0" Foreground="{DynamicResource TextSub}"><StackPanel Margin="12">' body '</StackPanel></Expander>'
        }
        page(id, body, visible := false) {
            return '<StackPanel Name="SetPage_' id '"' (visible ? '' : ' Visibility="Collapsed"') '>'
                . '<StackPanel Margin="14,20,14,28">' body '</StackPanel></StackPanel>'
        }

        ; ---------- 公共片段 ----------
        tabsBody := '<WrapPanel>'
            . togI(GetLang("按键宏"), "TabVisible_Normal", this._TabVisibleVal("Normal")) . togI(GetLang("字串宏"), "TabVisible_String", this._TabVisibleVal("String")) . togI(GetLang("菜单宏"), "TabVisible_Menu", this._TabVisibleVal("Menu")) . togI(GetLang("界面宏"), "TabVisible_UI", this._TabVisibleVal("UI")) . togI(GetLang("语音宏"), "TabVisible_Voice", this._TabVisibleVal("Voice")) . togI(GetLang("定时宏"), "TabVisible_Timing", this._TabVisibleVal("Timing")) . togI(GetLang("宏"), "TabVisible_SubMacro", this._TabVisibleVal("SubMacro")) . togI(GetLang("按键替换"), "TabVisible_Replace", this._TabVisibleVal("Replace")) . togI(GetLang("网络宏"), "TabVisible_Network", this._TabVisibleVal("Network")) . '</WrapPanel>'
        appearanceBody := cmb(GetLang("软件字体"), "CmbFont", MainSoftData.FontList, MainSoftData.FontType, false, GetLang("软件界面使用的字体，修改后保存设置生效。"))
            . sld(GetLang("字体大小"), "ThemeFontSizeCon", "ThemeFontSizeVal", MainSoftData.FontSize, 0, 40, 1, GetLang("字号 0~40；保存后统一刷新界面。"))

        ; ---------- 页：系统（按参考稿逐行排列） ----------
        ltRtIsPs5 := (MainSoftData.TriggerJoyType == "PS5")
        ltRtLabel := GetLang(ltRtIsPs5 ? "L2、R2按键化" : "LT、RT按键化")
        ltRtDesc := Format(GetLang("开启后 {} 当普通按键；关闭则当扳机轴，可设 0~100。"), ltRtIsPs5 ? "L2/R2" : "LT/RT")
        behaviorPage := page("behavior"
            , twoCol(
                card(GetLang("软件"), "&#xE74C;", tog(GetLang("开机自启"), "ChkBootStart", MainSoftData.IsBootStart)
                    . tog(GetLang("管理员启动"), "ChkAdminStart", MainSoftData.IsAdminStart, GetLang("后台功能与部分按键类型需要管理员权限"))
                    . row(GetLang("权限说明"), '<TextBlock Text="' GetLang("不要通过程序兼容性强制管理员运行；请使用本选项，才能与开机自启一起生效。") '" TextWrapping="Wrap" Foreground="{DynamicResource TextSub}" FontSize="13"/>')
                    . tog(GetLang("在线功能"), "ChkDataReport", MainSoftData.IsDataReport, GetLang("获取版本更新、AI 智能助手"))
                    . cmb(GetLang("语言"), "CmbLang", MainSoftData.LangArr, MainSoftData.Lang)
                    . cmb(GetLang("首选编辑器"), "CmbPreferredEditor", GetLangArr(["逻辑树", "图形节点"]), MainSoftData.PreferredMacroEditor)
                    . tog(GetLang("模态子窗口"), "ChkModalSubGui", MainSoftData.IsModalSubGui, GetLang("打开指令编辑等子窗口时禁用主窗口")), "0", "", "soft")
                . card(GetLang("显示页签"), "&#xE8A5;", tabsBody, "0,18,0,0", "", "tabs")
                , card(GetLang("通用"), "&#xE713;", cmb(GetLang("截图工具"), "CmbScreenShot", GetLangArr(["微软截图", "RMT截图", "SC截图"]), MainSoftData.ScreenShotType)
                    . cmb(GetLang("图片识别模型"), "CmbSearchImage", GetLangArr(["OpenCV", "RMT搜图"]), MainSoftData.SearchImageType)
                    . num(GetLang("多线程数"), "EditMutiThreadNum", MainSoftData.MutiThreadNum, GetLang("-1：动态多线程；0：单线程；n：固定线程数（推荐 3~5）"))
                    . num(GetLang("网络宏端口"), "EditNetPort", MainSoftData.NetworkPort, GetLang("网络宏端口 1-65535，默认 16888；仅监听本机回环地址。"))
                    . cmb(GetLang("指令备注生成"), "CmbRemarkAuto", GetLangArr(["不生成", "自动生成", "覆盖生成"]), MainSoftData.RemarkAutoType), "0", "", "general")
                . card(GetLang("手柄"), "&#xE7FC;", cmb(GetLang("手柄映射"), "CmbTriggerJoyType", ["Xbox", "PS5"], MainSoftData.TriggerJoyType)
                    . cmb(GetLang("宏手柄类型"), "CmbJoyType", ["Xbox", "PS5"], MainSoftData.JoyType)
                    . '<Border MinHeight="48" Padding="0,5" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="0,0,0,0.5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="128"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                    . '<TextBlock Name="LblJoyLtRtAsButton" Text="' this._XmlEsc(ltRtLabel) '" TextWrapping="Wrap" FontWeight="SemiBold" Foreground="{DynamicResource TextMain}" FontSize="13" VerticalAlignment="Center"/>'
                    . '<Grid Grid.Column="2" VerticalAlignment="Center"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                    . '<CheckBox Name="ChkJoyLtRtAsButton" IsChecked="' (MainSoftData.JoyLtRtAsButton ? "True" : "False") '" Style="{StaticResource SetSwitch}" VerticalAlignment="Center"/>'
                    . '<TextBlock Grid.Column="1" Name="LblJoyLtRtAsButton_Desc" Text="' this._XmlEsc(ltRtDesc) '" Margin="10,0,0,0" FontSize="12" Foreground="{DynamicResource TextSub}" TextWrapping="Wrap" VerticalAlignment="Center"/>'
                    . '</Grid></Grid></Border>', "0,18,0,0", "", "joy"))
            , true)

        ; ---------- 页：宏 ----------
        macroPage := page("macro", twoCol(
                card(GetLang("通用"), "&#xE8D4;", tog(GetLang("仅前台运行宏"), "ChkForeground", MainSoftData.CheckForeground, GetLang("窗口不匹配则终止运行的宏"))
                    . tog(GetLang("自动松开修饰键"), "ChkAutoLoosen", MainSoftData.AutoLoosenModifier, GetLang("组合键触发前先松开修饰键"))
                    . tog(GetLang("连续触发"), "ChkContinuous", MainSoftData.ContinuousTrigger, GetLang("按住触发键期间允许连续触发"))
                    . cmb(GetLang("宏终止方式"), "CmbMacroStop", GetLangArr(["智能终止", "强制终止"]), MainSoftData.MacroStopType)
                    . cmb(GetLang("重复按下行为"), "CmbKeyDownDown", GetLangArr(["自动松开", "忽略重复按下", "允许重复按下"]), MainSoftData.KeyDownDownType)
                    . tog(GetLang("无变量提醒"), "ChkNoVariable", MainSoftData.NoVariableTip, GetLang("变量为空时提示")), "0", "", "trig")
                , card(GetLang("随机浮动"), "&#xE823;", numCompact(GetLang("点击时间浮动（%）"), "EditHoldFloat", MainSoftData.HoldFloat, GetLang("点击指令时，按下或等待时长可随机上下浮动的百分比。"))
                    . numCompact(GetLang("每次间隔浮动（%）"), "EditPreIntervalFloat", MainSoftData.PreIntervalFloat, GetLang("两次宏执行之间的间隔可随机上下浮动的百分比。"))
                    . numCompact(GetLang("间隔指令浮动（%）"), "EditIntervalFloat", MainSoftData.IntervalFloat, GetLang("间隔指令本身的时长可随机上下浮动的百分比。"))
                    . numCompact(GetLang("坐标 X 浮动 (px)"), "EditCoordXFloat", MainSoftData.CoordXFloat, GetLang("鼠标坐标 X 轴可随机上下偏移的像素值。"))
                    . numCompact(GetLang("坐标 Y 浮动 (px)"), "EditCoordYFloat", MainSoftData.CoordYFloat, GetLang("鼠标坐标 Y 轴可随机上下偏移的像素值。")), "0", "", "float")))

        ; ---------- 页：指令录制 ----------
        recordPage := page("record", twoCol(
            card(GetLang("通用"), "&#xE7C8;", tog(GetLang("录制显示边框"), "ShowBorderCon", MainSoftData.RecordShowBorder, GetLang("录制时显示范围边框"))
                . tog(GetLang("长按多次录制"), "HoldMutiCon", MainSoftData.RecordHoldMuti, GetLang("按住时连续录制"))
                . tog(GetLang("结束自动添加按键松开"), "AutoLoosenCon", MainSoftData.RecordAutoLoosen, GetLang("录制结束后补充松开指令")), "0", "", "recCommon")
            . card(GetLang("键盘"), "&#xE765;", tog(GetLang("键盘录制"), "KeyboardTogCon", MainSoftData.RecordKeyboard, GetLang("记录键盘操作")), "0,18,0,0", "", "recKey")
            , card(GetLang("鼠标"), "&#xE962;", tog(GetLang("鼠标录制"), "MouseTogCon", MainSoftData.RecordMouse, GetLang("记录鼠标操作"))
                . cmb(GetLang("鼠标轨迹"), "MouseTrailModeCon", GetLangArr(["不录制", "关键点位", "关键点相对位移", "全量"]), MainSoftData.RecordMouseTrail, true)
                . num(GetLang("速度 (0~100)"), "MouseTrailSpeedCon", MainSoftData.RecordMouseTrailSpeed), "0", "", "recMouse")
            . card(GetLang("手柄"), "&#xE7FC;", tog(GetLang("手柄录制"), "JoyTogCon", MainSoftData.RecordJoy, GetLang("记录手柄操作"))
                . num(GetLang("检测间隔 (ms)"), "JoyIntervalCon", MainSoftData.RecordJoyInterval), "0,18,0,0", "", "recJoy")))

        ; ---------- 页：快捷键 ----------
        hotkeyGroups := [
            {title: "全局与工具", glyph: "&#xE765;", defs: [
                {f: "SuspendHotkey", l: "软件休眠", t: true},
                {f: "PauseHotkey", l: "暂停宏", t: false},
                {f: "KillMacroHotkey", l: "终止宏", t: false},
                {f: "ToolRecordMacroHotKey", l: "指令录制", t: false},
                {f: "ToolTextFilterHotKey", l: "文本提取", t: false}]},
            {title: "截图与调试", glyph: "&#xE8D4;", defs: [
                {f: "ScreenShotHotKey", l: "屏幕截图", t: false},
                {f: "FreePasteHotKey", l: "自由贴", t: false},
                {f: "ToolCheckHotkey", l: "鼠标信息", t: false},
                {f: "DebugRunHotkey", l: "继续", t: true},
                {f: "DebugStepHotkey", l: "步入", t: true}]}
        ]
        hotkeyCards := []
        for hi, hg in hotkeyGroups {
            hb := ""
            for hd in hg.defs {
                hv := MainSoftData.HasProp(hd.f) ? String(MainSoftData.%hd.f%) : ""
                hdisp := hv == "" ? GetLang("无") : FormatHotkeyDisplay(hv)
                hb .= row(GetLang(hd.l), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions><TextBox Name="Val_' hd.f '" Text="' this._XmlEsc(hdisp) '" IsReadOnly="True"/><Button Grid.Column="1" Name="BtnEdit_' hd.f '" Content="&#xE70F;" FontFamily="' iconFont '" ToolTip="' GetLang("录入快捷键") '" Margin="8,0,0,0" Padding="0"/></Grid>')
            }
            hotkeyCards.Push(card(GetLang(hg.title), hg.glyph, hb, "0", "", "hk" hi))
        }
        hotkeyPage := page("hotkey", twoCol(hotkeyCards[1], hotkeyCards[2]))

        ; ---------- 页：日志 ----------
        logPage := page("diagnostic", twoCol(
            card(GetLang("指令显示"), "&#xE8A5;", tog(GetLang("启用指令显示"), "ChkCMDTip", MySoftData.CMDTip, GetLang("在屏幕上显示宏运行状态"))
                . num(GetLang("显示位置 X"), "CmdTipPosXCon", MainSoftData.CMDPosX)
                . num(GetLang("显示位置 Y"), "CmdTipPosYCon", MainSoftData.CMDPosY)
                . sld(GetLang("显示宽度"), "CmdTipWidthCon", "CmdTipWidthVal", MainSoftData.CMDWidth, 80, 800, 5)
                . sld(GetLang("显示高度"), "CmdTipHeightCon", "CmdTipHeightVal", MainSoftData.CMDHeight, 40, 600, 5)
                . sld(GetLang("字体大小"), "CmdTipFontCon", "CmdTipFontVal", MainSoftData.CMDFontSize, 8, 36, 1)
                . sld(GetLang("背景透明度"), "CmdTipAlphaCon", "CmdTipAlphaVal", MainSoftData.CMDTransparency, 0, 100, 1)
                . tog(GetLang("输出到文件"), "CmdTipLogFileCon", MainSoftData.CMDLogToFile, GetLang("把指令显示内容写入日志文件"))
                . row(GetLang("日志文件路径"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="85"/></Grid.ColumnDefinitions><TextBox Name="CmdTipLogPathCon" Text="' this._XmlEsc(MainSoftData.CMDLogFilePath) '"/><Button Name="BtnCmdTipBrowse" Grid.Column="1" Content="' GetLang("浏览") ' ↗" Width="76" HorizontalAlignment="Right" Padding="6,0"/></Grid>')
                . cmb(GetLang("自动清理时间"), "CmdTipAutoClearCon", GetLangArr(["从不", "每天", "每周"]), MainSoftData.CMDLogAutoClear, true), "0", "", "cmdTip")
            , card(GetLang("日志与错误"), "&#xE81C;", cmb(GetLang("日志级别"), "CmbLogLevel", ["debug", "info", "warn", "error"], MainSoftData.SysLogMinLevel)
                . tog(GetLang("warn 气泡"), "ChkLogWarnBubble", MainSoftData.LogWarnBubble, GetLang("警告时显示托盘气泡"))
                . tog(GetLang("错误中心"), "ChkLogErrorBadge", MainSoftData.LogErrorBadge, GetLang("error 在错误中心聚合"))
                . tog(GetLang("业务日志"), "ChkBusinessLog", MainSoftData.BusinessLog, GetLang("记录宏运行流水"))
                . btnRow(GetLang("日志中心"), '<Button Name="BtnLogCenter" Content="' GetLang("打开日志中心") ' ↗" HorizontalAlignment="Left" Padding="10,0"/>'), "0", "", "logErr")))

        ; ---------- 页：界面 ----------
        triggerPage := page("trigger"
            , twoCol(
                card(GetLang("菜单宏-轮盘"), "&#xE700;", tog(GetLang("固定位置"), "WheelFixedPosCon", MainSoftData.FixedMenuWheel, GetLang("固定在屏幕中下方"))
                    . tog(GetLang("显示扇区名称提示"), "WheelShowTooltipCon", MainSoftData.MenuWheelShowTooltip, GetLang("悬停显示扇区名称"))
                    . cmb(GetLang("选择模式"), "WheelSelectModeCon", GetLangArr(["点击选择", "划线选择"]), MainSoftData.MenuWheelSelectMode)
                    . sld(GetLang("轮盘大小"), "WheelScaleCon", "WheelScaleVal", MainSoftData.MenuWheelScale, 50, 200, 10), "0", "", "wheel")
                    . card(GetLang("时间-倒计时"), "&#xE916;", cmb(GetLang("样式"), "CountDownStyleCon", GetLangArr(["时分秒", "智能", "秒"]), MainSoftData.CountDownStyle)
                        . tog(GetLang("补零"), "CountDownPadCon", MainSoftData.CountDownPadZero, GetLang("如 1:30:9 显示为 01:30:09；仅秒不补"))
                        . sld(GetLang("透明度"), "CountDownAlphaCon", "CountDownAlphaVal", MainSoftData.CountDownAlpha, 0, 100, 1)
                        . sld(GetLang("字体大小"), "CountDownFontCon", "CountDownFontVal", MainSoftData.CountDownFontSize, 8, 72, 1), "0,18,0,0", "", "countdown")
                , card(GetLang("界面宏-浮窗"), "&#xE737;", sld(GetLang("按钮宽度"), "UIPanelBtnWidthCon", "UIPanelBtnWidthVal", MainSoftData.UIPanelBtnWidth, 40, 250, 5)
                    . sld(GetLang("按钮高度"), "UIPanelBtnHeightCon", "UIPanelBtnHeightVal", MainSoftData.UIPanelBtnHeight, 20, 60, 2)
                    . sld(GetLang("字体大小"), "UIPanelFontSizeCon", "UIPanelFontSizeVal", MainSoftData.UIPanelFontSize, 8, 24, 1)
                    . sld(GetLang("每行个数"), "UIPanelColsCon", "UIPanelColsVal", MainSoftData.UIPanelCols, 1, 6, 1), "0", "", "uipanel")
            )
        )

        ; ---------- 页：主题 ----------
        tcMap := (MainSoftData.HasProp("ThemeColors") && IsObject(MainSoftData.ThemeColors)) ? MainSoftData.ThemeColors : AppThemeUtil.NewColorMapFromPreset(AppThemeUtil.GetDefaultPreset())
        themeNames := []
        for tp in AppThemeUtil.Presets
            themeNames.Push(GetLang(tp.Name))
        themeNames.Push(GetLang("自定义"))
        themeIdx := AppThemeUtil.Presets.Length
        for ti, tp in AppThemeUtil.Presets {
            if (tp.Key == MainSoftData.AppTheme) {
                themeIdx := ti - 1
                break
            }
        }
        paletteBody := '<UniformGrid Columns="3">'
        for slot, cd in AppThemeUtil.ColorDefs {
            col := tcMap.Has(cd.Key) ? tcMap[cd.Key] : "#FF000000"
            paletteBody .= '<Grid Margin="0,4,16,4"><Grid.ColumnDefinitions><ColumnDefinition Width="56"/><ColumnDefinition Width="*"/><ColumnDefinition Width="35"/></Grid.ColumnDefinitions><TextBlock Text="' this._XmlEsc(GetLang("颜色") " " slot) '" VerticalAlignment="Center" FontSize="13"/><TextBox Grid.Column="1" Name="PaletteText_' slot '" Text="' this._XmlEsc(col) '" IsReadOnly="True" Padding="7,0"/><Border Grid.Column="2" Name="PalettePreview_' slot '" Width="28" Height="28" CornerRadius="6" HorizontalAlignment="Right" Background="' this._XmlEsc(col) '" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" Cursor="Arrow"/></Grid>'
        }
        paletteBody .= '</UniformGrid>'
        themePage := page("appearance"
            , twoCol(
                card(GetLang("主题方案"), "&#xE790;", cmb(GetLang("选择主题"), "ThemePresetCon", themeNames, themeIdx, true)
                    . '<TextBlock Text="' this._XmlEsc(GetLang("选「自定义」后色块可点击取色；颜色与字体随「应用并保存」落盘。")) '" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,8,0,0" TextWrapping="Wrap"/>', "0", "", "theme")
                , card(GetLang("字体"), "&#xE8D2;", appearanceBody, "0", "", "font")
            )
            . card(GetLang("主题颜色"), "&#xE790;", paletteBody, "0,18,0,0", "", "palette")
        )

        ; ---------- 页：AI 助手 ----------
        aiProviderNames := []
        for ap in AiAssist.Providers
            aiProviderNames.Push(GetLang(ap["name"]))
        aiAccessNames := []
        for al in AiAssist.AccessLabels
            aiAccessNames.Push(GetLang(al))
        aiApprovalNames := []
        for al in AiAssist.ApprovalLabels
            aiApprovalNames.Push(GetLang(al))
        aiModelXaml := ""
        for mi in AiAssist.ModelListArr()
            aiModelXaml .= '<ComboBoxItem Content="' this._XmlEsc(String(mi)) '"/>'
        aiPage := page("ai"
            , twoCol(
                card(GetLang("大模型"), "&#xE99A;", cmb(GetLang("模型商"), "AiProviderCon", aiProviderNames, AiAssist.ProviderIndex(MainSoftData.AiProvider) - 1, true)
                    . row(GetLang("API URL"), '<TextBox Name="AiBaseUrlCon" Text="' this._XmlEsc(MainSoftData.AiApiBaseUrl) '" Height="33" MinHeight="33" Padding="6,0,18,0" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>', GetLang("OpenAI 兼容接口，例如 https://api.openai.com/v1"))
                    . row(GetLang("API Key"), '<PasswordBox Name="AiApiKeyCon" Password="' this._XmlEsc(MainSoftData.AiApiKey) '" Height="33" MinHeight="33" Padding="6,0,18,0" VerticalContentAlignment="Center" FontSize="12" Background="{DynamicResource InputBg}" Foreground="{DynamicResource InputText}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>')
                    . row(GetLang("模型列表"), '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox Name="AiModelCon" IsEditable="True" Text="' this._XmlEsc(MainSoftData.AiModel) '" Height="33" MinHeight="33" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1">' aiModelXaml '</ComboBox><Button Grid.Column="1" Name="BtnAiRefreshModels" Content="&#xE72C;" FontFamily="' iconFont '" FontSize="14" Width="33" Height="33" MinWidth="33" MinHeight="33" Padding="0" Margin="8,0,0,0" ToolTip="' this._XmlEsc(GetLang("刷新")) '"/></Grid>'), "0", "", "aiModel")
                , card(GetLang("权限"), "&#xE72E;", cmb(GetLang("写入权限"), "AiAccessCon", aiAccessNames, MainSoftData.AiAccessMode - 1, true, GetLang("只读：只能读取；工作区：写入仅限软件目录；完全访问：无读写限制。"))
                    . cmb(GetLang("指令审批"), "AiApprovalCon", aiApprovalNames, MainSoftData.AiApprovalMode - 1, true)
                    . row(GetLang("权限说明"), '<TextBlock Text="' GetLang("只读：只能读取；工作区：写入仅限软件目录；完全访问：无读写限制。") '" TextWrapping="Wrap" Foreground="{DynamicResource TextSub}"/>'), "0", "", "aiPerm")
            )
        )

        ; ---------- 组装：左侧导航 + 右侧页面 ----------
        navDefs := [["behavior", "&#xE713;", "系统"], ["macro", "&#xE768;", "宏"], ["record", "&#xE7C8;", "指令录制"], ["trigger", "&#xE8D4;", "界面"], ["hotkey", "&#xE765;", "快捷键"], ["appearance", "&#xE790;", "主题"], ["ai", "&#xE99A;", "AI 助手"], ["diagnostic", "&#xE81C;", "日志"]]
        navSep := '<Border Height="1" Background="{DynamicResource OutlineStroke}" Margin="0,0,-9,0" HorizontalAlignment="Stretch"/>'
        navAll := navSep
        for ni, nd in navDefs {
            if (ni > 1)
                navAll .= navSep
            navAll .= navItem(nd[1], nd[2], GetLang(nd[3]), ni == 1)
        }
        navAll .= navSep
        pagesAll := behaviorPage . macroPage . recordPage . triggerPage . hotkeyPage . themePage . aiPage . logPage
        Add('<Grid ' ns '><Grid.Resources>' navStyle . switchStyle . fieldStyles '</Grid.Resources>'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="146"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            ; 先画纵向边框，再画导航与横向分隔线，使交点由横线覆盖，不留抗锯齿缝隙。
            . '<Border Grid.Column="1" Width="1" HorizontalAlignment="Center" Background="{DynamicResource OutlineStroke}"/>'
            . '<StackPanel Grid.Column="0" Margin="0,2,0,2">' navAll . '</StackPanel>'
            . '<ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><Grid>' pagesAll . '</Grid></ScrollViewer>'
            . '</Grid>')

        ; ---- 事件 ----
        this._Bind("EditHoldFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "HoldFloat"))
        this._Bind("EditPreIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "PreIntervalFloat"))
        this._Bind("EditIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "IntervalFloat"))
        this._Bind("EditCoordXFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordXFloat"))
        this._Bind("EditCoordYFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordYFloat"))
        this._Bind("EditMutiThreadNum", "LostFocus", ObjBindMethod(this, "OnIntEdit", "MutiThreadNum"))
        this._Bind("CmbFont", "SelectionChanged", ObjBindMethod(this, "OnComboText", "FontType"))
        this._Bind("ChkBootStart", "Click", OnBootStartChanged)
        this._Bind("ChkAdminStart", "Click", OnAdminStartChanged)
        this._Bind("ChkForeground", "Click", ObjBindMethod(this, "OnCheckEdit", "CheckForeground"))
        this._Bind("ChkAutoLoosen", "Click", ObjBindMethod(this, "OnCheckEdit", "AutoLoosenModifier"))
        this._Bind("ChkContinuous", "Click", ObjBindMethod(this, "OnCheckEdit", "ContinuousTrigger"))
        this._Bind("ChkNoVariable", "Click", ObjBindMethod(this, "OnCheckEdit", "NoVariableTip"))
        this._Bind("ChkBusinessLog", "Click", ObjBindMethod(this, "OnBusinessLogToggle"))
        this._Bind("ChkModalSubGui", "Click", ObjBindMethod(this, "OnCheckEdit", "IsModalSubGui"))
        this._Bind("ChkDataReport", "Click", ObjBindMethod(this, "OnCheckEdit", "IsDataReport"))
        this._Bind("CmbLang", "SelectionChanged", ObjBindMethod(this, "OnComboText", "Lang"))
        this._Bind("CmbPreferredEditor", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "PreferredMacroEditor"))
        this._Bind("CmbScreenShot", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "ScreenShotType"))
        this._Bind("CmbSearchImage", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "SearchImageType"))
        this._Bind("CmbTriggerJoyType", "SelectionChanged", ObjBindMethod(this, "OnTriggerJoyTypeChanged"))
        this._Bind("CmbJoyType", "SelectionChanged", ObjBindMethod(this, "OnComboText", "JoyType"))
        this._Bind("ChkJoyLtRtAsButton", "Click", ObjBindMethod(this, "OnCheckEdit", "JoyLtRtAsButton"))
        this._Bind("CmbKeyDownDown", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "KeyDownDownType"))
        this._Bind("CmbRemarkAuto", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "RemarkAutoType"))
        this._Bind("CmbMacroStop", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "MacroStopType"))
        ; §10 显示页签勾选
        for sym in ["Normal", "String", "Menu", "UI", "Voice", "Timing", "SubMacro", "Replace", "Network"]
            this._Bind("TabVisible_" sym, "Click", ObjBindMethod(this, "OnTabVisibleCheck", sym))
        ; ---- 设置中心：左侧导航 ----
        for pid in ["behavior", "macro", "record", "trigger", "hotkey", "appearance", "ai", "diagnostic"]
            this._Bind("SetNav_" pid, "Click", ObjBindMethod(this, "OnSettingNavClick", pid))

        ; ---- 设置中心：仅「日志中心」仍为独立查看窗口（非设置项）----
        this._Bind("BtnLogCenter", "Click", (*) => LogCenterGui.ShowGui())

        ; ---- 设置中心：指令录制 ----
        this._Bind("ShowBorderCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordShowBorder"))
        this._Bind("HoldMutiCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordHoldMuti"))
        this._Bind("AutoLoosenCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordAutoLoosen"))
        this._Bind("KeyboardTogCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordKeyboard"))
        this._Bind("MouseTogCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordMouse"))
        this._Bind("MouseTrailModeCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex0", "RecordMouseTrail"))
        this._Bind("MouseTrailSpeedCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "RecordMouseTrailSpeed"))
        this._Bind("JoyTogCon", "Click", ObjBindMethod(this, "OnCheckEdit", "RecordJoy"))
        this._Bind("JoyIntervalCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "RecordJoyInterval"))

        ; ---- 设置中心：快捷键（录入经既有 MyEditHotkeyGui 链路）----
        for hg in hotkeyGroups
            for hd in hg.defs
                this._Bind("BtnEdit_" hd.f, "Click", ObjBindMethod(this, "OnSettingEditHotkey", hd.f, hd.t))
        if (this.HasProp("_setHelpMap")) {
            for helpName, _ in this._setHelpMap
                this._Bind(helpName, "Click", ObjBindMethod(this, "OnSettingHelpClick", helpName))
        }

        ; ---- 设置中心：日志 ----
        this._Bind("CmbLogLevel", "SelectionChanged", ObjBindMethod(this, "OnComboText", "SysLogMinLevel"))
        this._Bind("ChkLogWarnBubble", "Click", ObjBindMethod(this, "OnCheckEdit", "LogWarnBubble"))
        this._Bind("ChkLogErrorBadge", "Click", ObjBindMethod(this, "OnCheckEdit", "LogErrorBadge"))

        ; ---- 设置中心：指令显示 ----
        this._Bind("ChkCMDTip", "Click", OnClickCMDTipToggle)
        this._Bind("CmdTipPosXCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CMDPosX"))
        this._Bind("CmdTipPosYCon", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CMDPosY"))
        this._Bind("CmdTipWidthCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDWidth", "CmdTipWidthVal", 80, 800))
        this._Bind("CmdTipWidthVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDWidth", "CmdTipWidthCon", 80, 800))
        this._Bind("CmdTipHeightCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDHeight", "CmdTipHeightVal", 40, 600))
        this._Bind("CmdTipHeightVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDHeight", "CmdTipHeightCon", 40, 600))
        this._Bind("CmdTipFontCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDFontSize", "CmdTipFontVal", 8, 36))
        this._Bind("CmdTipFontVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDFontSize", "CmdTipFontCon", 8, 36))
        this._Bind("CmdTipAlphaCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CMDTransparency", "CmdTipAlphaVal", 0, 100))
        this._Bind("CmdTipAlphaVal", "LostFocus", ObjBindMethod(this, "OnSettingNumText", "CMDTransparency", "CmdTipAlphaCon", 0, 100))
        this._Bind("CmdTipLogFileCon", "Click", ObjBindMethod(this, "OnCheckEdit", "CMDLogToFile"))
        this._Bind("BtnCmdTipBrowse", "Click", ObjBindMethod(this, "OnSettingLogBrowse"))
        this._Bind("CmdTipLogPathCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "CMDLogFilePath"))
        this._Bind("CmdTipAutoClearCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex0", "CMDLogAutoClear"))

        ; ---- 设置中心：界面 ----
        this._Bind("WheelFixedPosCon", "Click", ObjBindMethod(this, "OnCheckEdit", "FixedMenuWheel"))
        this._Bind("WheelShowTooltipCon", "Click", ObjBindMethod(this, "OnCheckEdit", "MenuWheelShowTooltip"))
        this._Bind("WheelSelectModeCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "MenuWheelSelectMode"))
        this._Bind("WheelScaleCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "MenuWheelScale", "WheelScaleVal", 50, 200))
        this._Bind("UIPanelBtnWidthCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelBtnWidth", "UIPanelBtnWidthVal", 40, 250))
        this._Bind("UIPanelBtnHeightCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelBtnHeight", "UIPanelBtnHeightVal", 20, 60))
        this._Bind("UIPanelFontSizeCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelFontSize", "UIPanelFontSizeVal", 8, 24))
        this._Bind("UIPanelColsCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "UIPanelCols", "UIPanelColsVal", 1, 6))
        this._Bind("CountDownFontCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CountDownFontSize", "CountDownFontVal", 8, 72))
        this._Bind("CountDownAlphaCon", "ValueChanged", ObjBindMethod(this, "OnSettingSlider", "CountDownAlpha", "CountDownAlphaVal", 0, 100))
        this._Bind("CountDownStyleCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "CountDownStyle"))
        this._Bind("CountDownPadCon", "Click", ObjBindMethod(this, "OnCheckEdit", "CountDownPadZero"))

        for spec in [["MenuWheelScale", "WheelScaleCon", "WheelScaleVal", 50, 200],
            ["UIPanelBtnWidth", "UIPanelBtnWidthCon", "UIPanelBtnWidthVal", 40, 250],
            ["UIPanelBtnHeight", "UIPanelBtnHeightCon", "UIPanelBtnHeightVal", 20, 60],
            ["UIPanelFontSize", "UIPanelFontSizeCon", "UIPanelFontSizeVal", 8, 24],
            ["UIPanelCols", "UIPanelColsCon", "UIPanelColsVal", 1, 6],
            ["CountDownFontSize", "CountDownFontCon", "CountDownFontVal", 8, 72],
            ["CountDownAlpha", "CountDownAlphaCon", "CountDownAlphaVal", 0, 100]]
            this._Bind(spec[3], "LostFocus", ObjBindMethod(this, "OnSettingNumText", spec[1], spec[2], spec[4], spec[5]))

        ; ---- 设置中心：主题字体大小 / AI 助手 ----
        this._Bind("ThemeFontSizeCon", "ValueChanged", ObjBindMethod(this, "OnSettingFontSize"))
        this._Bind("ThemeFontSizeVal", "LostFocus", ObjBindMethod(this, "OnSettingFontSizeText"))
        this._Bind("AiProviderCon", "SelectionChanged", ObjBindMethod(this, "OnAiProviderChanged"))
        this._Bind("AiBaseUrlCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "AiApiBaseUrl"))
        this._Bind("AiApiKeyCon", "LostFocus", ObjBindMethod(this, "OnTextEdit", "AiApiKey"))
        this._Bind("AiModelCon", "LostFocus", ObjBindMethod(this, "OnAiModelChanged"))
        this._Bind("AiAccessCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "AiAccessMode"))
        this._Bind("AiApprovalCon", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "AiApprovalMode"))
        this._Bind("BtnAiRefreshModels", "Click", ObjBindMethod(this, "OnAiRefreshModels"))

        ; ---- 设置中心：主题（预设 + 颜色 1~14）----
        this._Bind("ThemePresetCon", "SelectionChanged", ObjBindMethod(this, "OnSettingThemeChanged"))
        loop AppThemeUtil.ColorDefs.Length
            this._Bind("PalettePreview_" A_Index, "MouseLeftButtonDown", ObjBindMethod(this, "OnSettingPickColor", A_Index))
        this._RenderSettingPalette()

        UIControls.CMDTip := CtrlAdapter("ChkCMDTip", this.ui, "IsChecked")
        this.ui.Update("ChkCMDTip", "IsChecked", MySoftData.CMDTip ? "True" : "False")
        this._InitSettingModuleSpecs()
        this._BindSettingModuleResets()
        this._RefreshAllSettingModules()
    }

    ; ============ 设置中心：交互与辅助 ============

    ; 页面切换（RadioButton 视觉态由本方法显式设置，避免依赖 GroupName 作用域）
    OnSettingNavClick(pageId, state, ctrl, event) {
        for pid in ["behavior", "macro", "record", "trigger", "hotkey", "appearance", "ai", "diagnostic"] {
            try this.ui.Update("SetNav_" pid, "IsChecked", pid == pageId ? "True" : "False")
            try this.ui.Update("SetPage_" pid, "Visibility", pid == pageId ? "Visible" : "Collapsed")
        }
    }

    MarkSettingDirty(ctrl := "") {
        pageId := ""
        if (RegExMatch(ctrl, "i)^(Edit(Hold|PreInterval|Interval|Coord)|CmbKeyDown|CmbMacroStop|ChkNoVariable|ChkForeground|ChkContinuous|ChkAutoLoosen)"))
            pageId := "macro"
        else if (RegExMatch(ctrl, "i)^(Wheel|UIPanel|CountDown)") )
            pageId := "trigger"
        else if (RegExMatch(ctrl, "i)^(ShowBorder|HoldMuti|AutoLoosenCon|KeyboardTog|MouseTog|MouseTrail|JoyTog|JoyInterval)") )
            pageId := "record"
        else if (RegExMatch(ctrl, "i)^(CmbLog|ChkLog|ChkBusiness|ChkCMD|CmdTip|Val_)") )
            pageId := (InStr(ctrl, "Val_") = 1) ? "hotkey" : "diagnostic"
        else if (RegExMatch(ctrl, "i)^Ai") || ctrl == "ThemePresetCon")
            pageId := ctrl == "ThemePresetCon" ? "appearance" : "ai"
        else if (RegExMatch(ctrl, "i)^(CmbFont|ThemeFont|Palette)") )
            pageId := "appearance"
        else if (RegExMatch(ctrl, "i)^(ChkBoot|ChkAdmin|ChkData|ChkModal|CmbLang|CmbPreferred|CmbScreen|CmbSearchImage|CmbRemark|CmbTriggerJoy|CmbJoy|ChkJoy|EditMuti|TabVisible)") )
            pageId := "behavior"
        else if (ctrl == "EditNetPort")
            pageId := "behavior"
        if (pageId != "") {
            this._settingDirty[pageId] := true
            labels := Map("behavior", "系统", "macro", "宏", "record", "指令录制", "trigger", "界面", "hotkey", "快捷键", "appearance", "主题", "ai", "AI 助手", "diagnostic", "日志")
            try this.ui.Update("SetNavText_" pageId, "Text", GetLang(labels[pageId]) " *")
        }
        this._RefreshAllSettingModules()
    }

    ClearSettingDirty() {
        labels := Map("behavior", "系统", "macro", "宏", "record", "指令录制", "trigger", "界面", "hotkey", "快捷键", "appearance", "主题", "ai", "AI 助手", "diagnostic", "日志")
        this._settingDirty := Map()
        for pageId, label in labels
            try this.ui.Update("SetNavText_" pageId, "Text", GetLang(label))
    }

    _InitSettingModuleSpecs() {
        tabFields := []
        for sym in ["Normal", "String", "Menu", "UI", "Voice", "Timing", "SubMacro", "Replace", "Network"]
            tabFields.Push({key: sym, def: true, ctrl: "TabVisible_" sym, kind: "tab"})
        this._setMods := [
            {id: "soft", fields: [{key: "IsBootStart", def: false, ctrl: "ChkBootStart", kind: "chk", hook: "boot"}, {key: "IsAdminStart", def: false, ctrl: "ChkAdminStart", kind: "chk", hook: "admin"}, {key: "IsDataReport", def: true, ctrl: "ChkDataReport", kind: "chk"}, {key: "Lang", def: "中文", ctrl: "CmbLang", kind: "cmbText"}, {key: "PreferredMacroEditor", def: 1, ctrl: "CmbPreferredEditor", kind: "cmb"}, {key: "IsModalSubGui", def: true, ctrl: "ChkModalSubGui", kind: "chk"}]},
            {id: "general", fields: [{key: "ScreenShotType", def: 3, ctrl: "CmbScreenShot", kind: "cmb"}, {key: "SearchImageType", def: 1, ctrl: "CmbSearchImage", kind: "cmb"}, {key: "MutiThreadNum", def: -1, ctrl: "EditMutiThreadNum", kind: "num"}, {key: "NetworkPort", def: 16888, ctrl: "EditNetPort", kind: "num"}, {key: "RemarkAutoType", def: 2, ctrl: "CmbRemarkAuto", kind: "cmb"}]},
            {id: "trig", fields: [{key: "CheckForeground", def: false, ctrl: "ChkForeground", kind: "chk"}, {key: "AutoLoosenModifier", def: true, ctrl: "ChkAutoLoosen", kind: "chk"}, {key: "ContinuousTrigger", def: true, ctrl: "ChkContinuous", kind: "chk"}, {key: "MacroStopType", def: 1, ctrl: "CmbMacroStop", kind: "cmb"}, {key: "KeyDownDownType", def: 1, ctrl: "CmbKeyDownDown", kind: "cmb"}, {key: "NoVariableTip", def: false, ctrl: "ChkNoVariable", kind: "chk"}]},
            {id: "tabs", fields: tabFields},
            {id: "joy", fields: [{key: "TriggerJoyType", def: "Xbox", ctrl: "CmbTriggerJoyType", kind: "cmbText"}, {key: "JoyType", def: "Xbox", ctrl: "CmbJoyType", kind: "cmbText"}, {key: "JoyLtRtAsButton", def: true, ctrl: "ChkJoyLtRtAsButton", kind: "chk"}]},
            {id: "float", fields: [{key: "HoldFloat", def: 0, ctrl: "EditHoldFloat", kind: "num"}, {key: "PreIntervalFloat", def: 0, ctrl: "EditPreIntervalFloat", kind: "num"}, {key: "IntervalFloat", def: 0, ctrl: "EditIntervalFloat", kind: "num"}, {key: "CoordXFloat", def: 0, ctrl: "EditCoordXFloat", kind: "num"}, {key: "CoordYFloat", def: 0, ctrl: "EditCoordYFloat", kind: "num"}]},
            {id: "recCommon", fields: [{key: "RecordShowBorder", def: true, ctrl: "ShowBorderCon", kind: "chk"}, {key: "RecordHoldMuti", def: true, ctrl: "HoldMutiCon", kind: "chk"}, {key: "RecordAutoLoosen", def: true, ctrl: "AutoLoosenCon", kind: "chk"}]},
            {id: "recKey", fields: [{key: "RecordKeyboard", def: true, ctrl: "KeyboardTogCon", kind: "chk"}]},
            {id: "recMouse", fields: [{key: "RecordMouse", def: true, ctrl: "MouseTogCon", kind: "chk"}, {key: "RecordMouseTrail", def: 1, ctrl: "MouseTrailModeCon", kind: "cmb0"}, {key: "RecordMouseTrailSpeed", def: 95, ctrl: "MouseTrailSpeedCon", kind: "num"}]},
            {id: "recJoy", fields: [{key: "RecordJoy", def: false, ctrl: "JoyTogCon", kind: "chk"}, {key: "RecordJoyInterval", def: 100, ctrl: "JoyIntervalCon", kind: "num"}]},
            {id: "hk1", fields: [{key: "SuspendHotkey", def: "!p", ctrl: "Val_SuspendHotkey", kind: "hk"}, {key: "PauseHotkey", def: "!i", ctrl: "Val_PauseHotkey", kind: "hk"}, {key: "KillMacroHotkey", def: "!k", ctrl: "Val_KillMacroHotkey", kind: "hk"}, {key: "ToolRecordMacroHotKey", def: "!r", ctrl: "Val_ToolRecordMacroHotKey", kind: "hk"}, {key: "ToolTextFilterHotKey", def: "", ctrl: "Val_ToolTextFilterHotKey", kind: "hk"}]},
            {id: "hk2", fields: [{key: "ScreenShotHotKey", def: "", ctrl: "Val_ScreenShotHotKey", kind: "hk"}, {key: "FreePasteHotKey", def: "", ctrl: "Val_FreePasteHotKey", kind: "hk"}, {key: "ToolCheckHotkey", def: "!o", ctrl: "Val_ToolCheckHotkey", kind: "hk"}, {key: "DebugRunHotkey", def: "f5", ctrl: "Val_DebugRunHotkey", kind: "hk"}, {key: "DebugStepHotkey", def: "f11", ctrl: "Val_DebugStepHotkey", kind: "hk"}]},
            {id: "cmdTip", fields: [{key: "CMDTip", def: false, ctrl: "ChkCMDTip", kind: "chkMy", hook: "cmdtip"}, {key: "CMDWidth", defFn: "cmdW", ctrl: "CmdTipWidthCon", kind: "sld", val: "CmdTipWidthVal"}, {key: "CMDHeight", def: 300, ctrl: "CmdTipHeightCon", kind: "sld", val: "CmdTipHeightVal"}, {key: "CMDPosX", defFn: "cmdX", ctrl: "CmdTipPosXCon", kind: "num"}, {key: "CMDPosY", def: 0, ctrl: "CmdTipPosYCon", kind: "num"}, {key: "CMDFontSize", def: 12, ctrl: "CmdTipFontCon", kind: "sld", val: "CmdTipFontVal"}, {key: "CMDTransparency", def: 50, ctrl: "CmdTipAlphaCon", kind: "sld", val: "CmdTipAlphaVal"}, {key: "CMDLogToFile", def: false, ctrl: "CmdTipLogFileCon", kind: "chk"}, {key: "CMDLogFilePath", def: "", ctrl: "CmdTipLogPathCon", kind: "txt"}, {key: "CMDLogAutoClear", def: 0, ctrl: "CmdTipAutoClearCon", kind: "cmb0"}]},
            {id: "logErr", fields: [{key: "SysLogMinLevel", def: "info", ctrl: "CmbLogLevel", kind: "cmbText"}, {key: "LogWarnBubble", def: true, ctrl: "ChkLogWarnBubble", kind: "chk"}, {key: "LogErrorBadge", def: true, ctrl: "ChkLogErrorBadge", kind: "chk"}, {key: "BusinessLog", def: false, ctrl: "ChkBusinessLog", kind: "chk", hook: "blog"}]},
            {id: "wheel", fields: [{key: "FixedMenuWheel", def: false, ctrl: "WheelFixedPosCon", kind: "chk"}, {key: "MenuWheelShowTooltip", def: false, ctrl: "WheelShowTooltipCon", kind: "chk"}, {key: "MenuWheelSelectMode", def: 2, ctrl: "WheelSelectModeCon", kind: "cmb"}, {key: "MenuWheelScale", def: 100, ctrl: "WheelScaleCon", kind: "sld", val: "WheelScaleVal"}]},
            {id: "countdown", fields: [{key: "CountDownStyle", def: 2, ctrl: "CountDownStyleCon", kind: "cmb"}, {key: "CountDownPadZero", def: true, ctrl: "CountDownPadCon", kind: "chk"}, {key: "CountDownAlpha", def: 70, ctrl: "CountDownAlphaCon", kind: "sld", val: "CountDownAlphaVal"}, {key: "CountDownFontSize", def: 15, ctrl: "CountDownFontCon", kind: "sld", val: "CountDownFontVal"}]},
            {id: "uipanel", fields: [{key: "UIPanelBtnWidth", def: 80, ctrl: "UIPanelBtnWidthCon", kind: "sld", val: "UIPanelBtnWidthVal"}, {key: "UIPanelBtnHeight", def: 34, ctrl: "UIPanelBtnHeightCon", kind: "sld", val: "UIPanelBtnHeightVal"}, {key: "UIPanelFontSize", def: 12, ctrl: "UIPanelFontSizeCon", kind: "sld", val: "UIPanelFontSizeVal"}, {key: "UIPanelCols", def: 3, ctrl: "UIPanelColsCon", kind: "sld", val: "UIPanelColsVal"}]},
            {id: "theme", fields: [{key: "AppTheme", def: "Default", ctrl: "ThemePresetCon", kind: "theme"}]},
            {id: "font", fields: [{key: "FontType", def: "微软雅黑", ctrl: "CmbFont", kind: "cmbText"}, {key: "FontSize", def: 15, ctrl: "ThemeFontSizeCon", kind: "sld", val: "ThemeFontSizeVal"}]},
            {id: "palette", fields: [{key: "AppTheme", def: "Default", ctrl: "ThemePresetCon", kind: "theme"}]},
            {id: "aiModel", fields: [{key: "AiProvider", def: "openai", ctrl: "AiProviderCon", kind: "aiProv"}, {key: "AiApiBaseUrl", def: "https://api.openai.com/v1", ctrl: "AiBaseUrlCon", kind: "txt"}, {key: "AiApiKey", def: "", ctrl: "AiApiKeyCon", kind: "pwd"}, {key: "AiModel", def: "", ctrl: "AiModelCon", kind: "txt"}]},
            {id: "aiPerm", fields: [{key: "AiAccessMode", def: 2, ctrl: "AiAccessCon", kind: "cmb"}, {key: "AiApprovalMode", def: 2, ctrl: "AiApprovalCon", kind: "cmb"}]}
        ]
    }

    _BindSettingModuleResets() {
        if (!IsObject(this._setMods))
            return
        for mod in this._setMods
            this._Bind("BtnSetReset_" mod.id, "Click", ObjBindMethod(this, "OnSettingModuleReset", mod.id))
    }

    _SettingFieldDef(f) {
        if (f.HasOwnProp("defFn") && f.defFn == "cmdW")
            return GetDefaultCMDTipWidth()
        if (f.HasOwnProp("defFn") && f.defFn == "cmdX")
            return A_ScreenWidth - GetDefaultCMDTipWidth()
        return f.def
    }

    _SettingFieldCur(f) {
        if (f.kind == "tab")
            return this._TabVisibleVal(f.key)
        if (f.kind == "chkMy")
            return !!MySoftData.CMDTip
        if (f.kind == "pwd")
            return Trim(String(MainSoftData.HasProp(f.key) ? MainSoftData.%f.key% : ""))
        if (f.kind == "hk")
            return Trim(String(MainSoftData.HasProp(f.key) ? MainSoftData.%f.key% : ""))
        return MainSoftData.HasProp(f.key) ? MainSoftData.%f.key% : this._SettingFieldDef(f)
    }

    _SettingFieldDirty(f) {
        cur := this._SettingFieldCur(f)
        def := this._SettingFieldDef(f)
        if (f.kind == "chk" || f.kind == "chkMy" || f.kind == "tab")
            return !!cur != !!def
        if (IsNumber(cur) && IsNumber(def))
            return Integer(cur) != Integer(def)
        return String(cur) != String(def)
    }

    _RefreshAllSettingModules() {
        if (this.HasProp("_setModLock") && this._setModLock)
            return
        if (!IsObject(this._setMods) || !IsObject(this.ui))
            return
        for mod in this._setMods {
            dirty := false
            for f in mod.fields {
                if (this._SettingFieldDirty(f)) {
                    dirty := true
                    break
                }
            }
            try this.ui.Update("BtnSetReset_" mod.id, "Visibility", dirty ? "Visible" : "Collapsed")
        }
    }

    OnSettingModuleReset(modId, state := "", ctrl := "", event := "") {
        if (!IsObject(this._setMods))
            return
        spec := ""
        for mod in this._setMods {
            if (mod.id == modId) {
                spec := mod
                break
            }
        }
        if (!IsObject(spec))
            return
        this._setModLock := true
        try {
            for f in spec.fields
                this._ApplySettingFieldDefault(f)
        } finally {
            this._setModLock := false
        }
        hint := (spec.fields.Length > 0) ? spec.fields[1].ctrl : ""
        this.MarkSettingDirty(hint)
        this._RefreshAllSettingModules()
    }

    _ApplySettingFieldDefault(f) {
        def := this._SettingFieldDef(f)
        switch f.kind {
            case "chk":
                MainSoftData.%f.key% := !!def
                try this.ui.Update(f.ctrl, "IsChecked", def ? "True" : "False")
                if (f.HasOwnProp("hook") && f.hook == "boot")
                    OnBootStartChanged("")
                else if (f.HasOwnProp("hook") && f.hook == "admin")
                    OnAdminStartChanged("")
                else if (f.HasOwnProp("hook") && f.hook == "blog")
                    this.OnBusinessLogToggle("", f.ctrl, "")
            case "chkMy":
                try this.ui.Update(f.ctrl, "IsChecked", def ? "True" : "False")
                MySoftData.CMDTip := !!def
                SetCMDTipValue(!!def)
            case "tab":
                MainSoftData.TabVisibleMap[f.key] := !!def
                try this.ui.Update(f.ctrl, "IsChecked", def ? "True" : "False")
            case "cmb":
                MainSoftData.%f.key% := Integer(def)
                try this.ui.Update(f.ctrl, "SelectedIndex", Integer(def) - 1)
            case "cmb0":
                MainSoftData.%f.key% := Integer(def)
                try this.ui.Update(f.ctrl, "SelectedIndex", Integer(def))
            case "cmbText":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", String(def))
            case "sld":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Value", String(def))
                if (f.HasOwnProp("val"))
                    try this.ui.Update(f.val, "Text", String(def))
            case "num":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", String(def))
            case "txt":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", String(def))
            case "pwd":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Password", String(def))
            case "hk":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", (def == "" ? GetLang("无") : FormatHotkeyDisplay(def)))
            case "theme":
                tidx := 0
                for ti, tp in AppThemeUtil.Presets {
                    if (tp.Key == "Default") {
                        tidx := ti - 1
                        break
                    }
                }
                try this.ui.Update("ThemePresetCon", "SelectedIndex", tidx)
                this.OnSettingThemeChanged("", "ThemePresetCon", "")
            case "aiProv":
                MainSoftData.AiProvider := "openai"
                try this.ui.Update("AiProviderCon", "SelectedIndex", AiAssist.ProviderIndex("openai") - 1)
                this.OnAiProviderChanged("", "AiProviderCon", "")
        }
        if (f.kind == "cmbText" && f.key == "TriggerJoyType")
            this._RefreshJoyLtRtAsButtonText()
    }

    OnSettingLogBrowse(*) {
        selected := FileSelect("S", MainSoftData.CMDLogFilePath, GetLang("日志文件路径"), "Log (*.log; *.txt)")
        if (selected == "")
            return
        MainSoftData.CMDLogFilePath := selected
        this.ui.Update("CmdTipLogPathCon", "Text", selected)
        this.MarkSettingDirty("CmdTipLogPathCon")
    }

    ; 0 基索引下拉（配置值即索引，如 RecordMouseTrail / CMDLogAutoClear）
    OnComboIndex0(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := Integer(this.ui.Query(ctrl ">SelectedIndex"))
        this.MarkSettingDirty(ctrl)
    }

    ; 滑块 → 写字段 + 同步数值框
    OnSettingSlider(fieldName, valName, mn, mx, state, ctrl, event) {
        v := this.ui.Query(ctrl)
        if (!IsNumber(v))
            return
        v := Max(mn, Min(mx, Integer(Round(Number(v)))))
        MainSoftData.%fieldName% := v
        this.MarkSettingDirty(ctrl)
        try this.ui.Update(valName, "Text", String(v))
    }

    ; 数值框 → 写字段 + 同步滑块
    OnSettingNumText(fieldName, name, mn, mx, state, ctrl, event) {
        t := Trim(this.ui.Query(ctrl))
        if (t == "" || !IsNumber(t))
            return
        v := Max(mn, Min(mx, Integer(Round(Number(t)))))
        MainSoftData.%fieldName% := v
        this.MarkSettingDirty(ctrl)
        try this.ui.Update(name, "Value", String(v))
    }

    ; 界面浮窗出现位置：下拉序号 ↔ 锚点 id（id 8 不存在，顺序见 UIMacroPanelSettingGui.PosOptions）
    _UIPanelPosIds() {
        return [1, 2, 3, 4, 5, 6, 7, 9, 10]
    }
    _UIPanelPosIndex(id) {
        for i, pid in this._UIPanelPosIds() {
            if (pid == id)
                return i - 1
        }
        return 0
    }
    OnUIPanelPosChanged(state, ctrl, event) {
        idx := this.ui.Query("UIPanelDefaultPosCon>SelectedIndex")
        if (!IsNumber(idx))
            return
        ids := this._UIPanelPosIds()
        idx := Integer(idx) + 1
        if (idx < 1 || idx > ids.Length)
            return
        MainSoftData.UIPanelDefaultPos := ids[idx]
    }

    ; 主题：字体大小（滑块/数值框），原位预览并与「应用并保存」一致地写回 FontSize
    OnSettingFontSize(state, ctrl, event) {
        v := this.ui.Query("ThemeFontSizeCon")
        if (!IsNumber(v))
            return
        this._ApplySettingFontSize(Integer(Round(Number(v))))
    }
    OnSettingFontSizeText(state, ctrl, event) {
        t := Trim(this.ui.Query("ThemeFontSizeVal"))
        if (t == "" || !IsNumber(t)) {
            try this.ui.Update("ThemeFontSizeVal", "Text", String(MainSoftData.FontSize))
            return
        }
        this._ApplySettingFontSize(Integer(Round(Number(t))))
    }
    _ApplySettingFontSize(fs) {
        fs := Max(0, Min(40, fs))
        MainSoftData.FontSize := fs
        this.MarkSettingDirty("ThemeFontSizeCon")
        try this.ui.Update("ThemeFontSizeCon", "Value", String(fs))
        try this.ui.Update("ThemeFontSizeVal", "Text", String(fs))
        try {
            ApplyUserFontSize(fs, false)
            this.ui.Update("Window", "ApplyFonts", XAMLHost.BuildApplyFontsPayload(0, fs))
        }
    }

    ; 快捷键录入：复用 HotkeySettingGui 的录入链（MyEditHotkeyGui + 触发键/字串编辑器）
    OnSettingEditHotkey(fieldName, onlyTrigger, state, ctrl, event) {
        cur := MainSoftData.HasProp(fieldName) ? String(MainSoftData.%fieldName%) : ""
        showCon := HotkeyValueHolder(cur)
        keyCon := HotkeyValueHolder(cur)
        AfterSure(*) {
            newVal := keyCon.Value
            MainSoftData.%fieldName% := newVal
            try this.ui.Update("Val_" fieldName, "Text", (newVal == "" ? GetLang("无") : FormatHotkeyDisplay(newVal)))
            this.MarkSettingDirty("Val_" fieldName)
            this._ignoreConfirmUntil := A_TickCount + 500
            try WinActivate("ahk_id " this.ui.wpfHwnd)
        }
        MyEditHotkeyGui.AfterSureAction := AfterSure
        OnOpenEditHotkeyGui(showCon, keyCon, onlyTrigger)
    }

    ; AI：模型商 → 写 id，并同步 API URL 可编辑性（仅 azure / 自定义可编辑）
    OnAiProviderChanged(state, ctrl, event) {
        idx := this.ui.Query("AiProviderCon>SelectedIndex")
        if (!IsNumber(idx))
            return
        prov := AiAssist.ProviderByIndex(Integer(idx) + 1)
        MainSoftData.AiProvider := prov["id"]
        this.MarkSettingDirty(ctrl)
        editable := (prov["id"] = "custom" || Trim(prov["url"]) == "")
        try this.ui.Update("AiBaseUrlCon", "IsReadOnly", editable ? "False" : "True")
        try this.ui.Update("AiBaseUrlCon", "IsEnabled", editable ? "True" : "False")
        try this.ui.Update("AiBaseUrlCon", "Text", Trim(prov["url"]))
    }

    ; AI：模型列表（可编辑下拉）→ AiModel + 合并 AiModelList
    OnAiModelChanged(state, ctrl, event) {
        m := Trim(this.ui.Query("AiModelCon"))
        if (m == "")
            return
        MainSoftData.AiModel := m
        this.MarkSettingDirty(ctrl)
        list := m
        for id in AiAssist.ModelListArr() {
            id := Trim(id)
            if (id != "" && id != m)
                list .= "," id
        }
        MainSoftData.AiModelList := list
    }

    ; AI：拉取模型列表（仅写内存，落盘由「应用并保存」统一处理）
    OnAiRefreshModels(state, ctrl, event) {
        baseUrl := Trim(this.ui.Query("AiBaseUrlCon"))
        apiKey := Trim(this.ui.Query("AiApiKeyCon"))
        if (apiKey == "" || baseUrl == "") {
            Toast.Warning(GetLang("请先填写 API Key 与 API URL"))
            return
        }
        try this.ui.Update("BtnAiRefreshModels", "IsEnabled", "False")
        try {
            ids := AiAssist.FetchModels(baseUrl, apiKey)
            if (ids.Length < 1)
                throw Error(GetLang("未解析到可用模型，请检查 API URL 是否指向 OpenAI 兼容接口"))
            MainSoftData.AiModelList := ""
            for id in ids
                MainSoftData.AiModelList .= (MainSoftData.AiModelList == "" ? "" : ",") id
            try this.ui.Update("AiModelCon", "ClearItems", "")
            for id in ids
                try this.ui.Update("AiModelCon", "AddItem", id)
            keep := MainSoftData.AiModel
            if (keep == "")
                keep := ids[1]
            try this.ui.Update("AiModelCon", "Text", keep)
            Toast.Success(GetLang("已刷新模型列表"))
        } catch as e {
            Toast.Error(e.Message)
        } finally {
            try this.ui.Update("BtnAiRefreshModels", "IsEnabled", "True")
        }
    }

    ; ============ 设置中心：主题（预设 + 颜色 1~14）============

    ; 预设下拉：末位为「自定义」（只切换 key，保留当前颜色）
    OnSettingThemeChanged(state, ctrl, event) {
        idx := this.ui.Query("ThemePresetCon>SelectedIndex")
        if (!IsNumber(idx))
            return
        idx := Integer(idx)
        this.MarkSettingDirty(ctrl)
        if (idx < 0 || idx >= AppThemeUtil.Presets.Length) {
            MainSoftData.AppTheme := "Custom"
        } else {
            preset := AppThemeUtil.Presets[idx + 1]
            MainSoftData.AppTheme := preset.Key
            colors := AppThemeUtil.NewColorMapFromPreset(preset)
            MainSoftData.ThemeColors := colors
            AppThemeUtil.ApplyToRuntime(colors)
            try AppThemeUtil.ApplyWinThemeToXaml(this.ui, colors)
        }
        this._RenderSettingPalette()
    }

    ; 把颜色 1~14 刷到色值框 / 色块；仅「自定义」时色块可点
    _RenderSettingPalette() {
        if (!(MainSoftData.HasProp("ThemeColors") && IsObject(MainSoftData.ThemeColors)))
            return
        editable := (MainSoftData.AppTheme == "Custom")
        for i, entry in AppThemeUtil.BuildPalette(MainSoftData.ThemeColors) {
            try this.ui.Update("PaletteText_" i, "Text", entry.Color)
            try this.ui.Update("PalettePreview_" i, "Background", entry.Color)
            try this.ui.Update("PalettePreview_" i, "Cursor", editable ? "Hand" : "Arrow")
            try this.ui.Update("PalettePreview_" i, "IsHitTestVisible", editable ? "True" : "False")
        }
    }

    ; 取色：仅自定义主题；取色后写回 ThemeColors 并即时预览
    OnSettingPickColor(slot, state, ctrl, event) {
        if (MainSoftData.AppTheme != "Custom")
            return
        if (!(MainSoftData.HasProp("ThemeColors") && IsObject(MainSoftData.ThemeColors)))
            return
        key := "Theme_Color" Format("{:02}", slot)
        cur := MainSoftData.ThemeColors.Has(key) ? MainSoftData.ThemeColors[key] : "#FF000000"
        result := XColorPicker.Show({Title: GetLang("颜色") slot, DefaultColor: cur, Owner: this.ui.wpfHwnd, Modal: true})
        if (result.Status != "OK")
            return
        MainSoftData.ThemeColors[key] := AppThemeUtil.NormalizeArgb(result.Color)
        AppThemeUtil.ApplyToRuntime(MainSoftData.ThemeColors)
        try AppThemeUtil.ApplyWinThemeToXaml(this.ui, MainSoftData.ThemeColors)
        this._RenderSettingPalette()
    }

    ; ============ 设置中心：右键菜单有序列表 ============

    _CtxItemLabel(key) {
        static m := Map("Edit", "编辑", "Skip", "跳过指令", "Debug", "调试起点", "Insert", "插入指令", "Copy", "复制", "SharedCopy", "共享复制", "Paste", "粘贴", "Delete", "删除", "Add", "添加指令", "BranchCopy", "复制", "BranchSharedCopy", "共享复制")
        if (key == "Separator")
            return "───────"
        return m.Has(key) ? GetLang(m[key]) : key
    }

    _InitCtxLists() {
        this._ctxGenAll := ["Edit", "Skip", "Debug", "Insert", "Copy", "SharedCopy", "Paste", "Delete", "Separator"]
        this._ctxBranchAll := ["Add", "BranchCopy", "BranchSharedCopy", "Paste", "Delete", "Separator"]
        defGen := ["Edit", "Skip", "Debug", "Separator", "Insert", "Separator", "Copy", "SharedCopy", "Paste", "Separator", "Delete"]
        defBranch := ["Add", "Separator", "BranchCopy", "BranchSharedCopy", "Paste", "Separator", "Delete"]
        gRaw := MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : ""
        bRaw := MainSoftData.HasProp("BranchContextMenu") ? MainSoftData.BranchContextMenu : ""
        this._ctxGenActive := this._ParseCtxList(gRaw, defGen)
        this._ctxBranchActive := this._ParseCtxList(bRaw, defBranch)
        this._RebuildCtxAvail()
    }

    _ParseCtxList(raw, def) {
        out := []
        if (Trim(String(raw)) == "") {
            for k in def
                out.Push(k)
            return out
        }
        for k in StrSplit(String(raw), ",") {
            k := Trim(k)
            if (k != "")
                out.Push(k)
        }
        return out
    }

    _InArr(arr, v) {
        for x in arr {
            if (x == v)
                return true
        }
        return false
    }

    ; 可用项目 = 全集里未出现在显示项目的项；分隔线始终可用（可重复添加、不被消耗）
    _RebuildCtxAvail() {
        this._ctxGenAvail := []
        for k in this._ctxGenAll {
            if (k == "Separator" || !this._InArr(this._ctxGenActive, k))
                this._ctxGenAvail.Push(k)
        }
        this._ctxBranchAvail := []
        for k in this._ctxBranchAll {
            if (k == "Separator" || !this._InArr(this._ctxBranchActive, k))
                this._ctxBranchAvail.Push(k)
        }
    }

    _RenderOneCtxList(listId, arr) {
        try this.ui.Update(listId, "ClearItems", "")
        for k in arr
            try this.ui.Update(listId, "AddItem", this._CtxItemLabel(k))
    }

    _RenderCtxLists(reselId := "", reselIdx := -1, sync := true) {
        this._RebuildCtxAvail()
        this._RenderOneCtxList("GenActiveList", this._ctxGenActive)
        this._RenderOneCtxList("GenAvailList", this._ctxGenAvail)
        this._RenderOneCtxList("BranchActiveList", this._ctxBranchActive)
        this._RenderOneCtxList("BranchAvailList", this._ctxBranchAvail)
        if (sync)
            this._SyncCtxConfig()
        if (reselId != "" && reselIdx >= 0)
            try this.ui.Update(reselId, "SelectedIndex", String(reselIdx))
    }

    ; 显示项目 → 配置键（CSV）；SharedCopy 由两份列表派生
    _SyncCtxConfig() {
        MainSoftData.GeneralContextMenu := this._JoinCtxList(this._ctxGenActive)
        MainSoftData.BranchContextMenu := this._JoinCtxList(this._ctxBranchActive)
        MainSoftData.SharedCopy := (this._InArr(this._ctxGenActive, "SharedCopy") || this._InArr(this._ctxBranchActive, "BranchSharedCopy"))
    }

    _JoinCtxList(arr) {
        s := ""
        for i, k in arr
            s .= (i > 1 ? "," : "") k
        return s
    }

    _CtxSelIdx(listId) {
        raw := this.ui.Query(listId ">SelectedIndex")
        return IsNumber(raw) ? Integer(raw) : -1
    }

    OnCtxMove(dir, which, state, ctrl, event) {
        listId := (which == "gen") ? "GenActiveList" : "BranchActiveList"
        active := (which == "gen") ? this._ctxGenActive : this._ctxBranchActive
        sel := this._CtxSelIdx(listId)
        if (sel < 0 || sel >= active.Length)
            return
        ai := sel + 1
        if (dir == "up") {
            if (ai <= 1)
                return
            tmp := active[ai]
            active[ai] := active[ai - 1]
            active[ai - 1] := tmp
            this._RenderCtxLists(listId, ai - 2)
        } else {
            if (ai >= active.Length)
                return
            tmp := active[ai]
            active[ai] := active[ai + 1]
            active[ai + 1] := tmp
            this._RenderCtxLists(listId, ai)
        }
    }

    OnCtxAdd(which, state, ctrl, event) {
        isGen := (which == "gen")
        avail := isGen ? this._ctxGenAvail : this._ctxBranchAvail
        active := isGen ? this._ctxGenActive : this._ctxBranchActive
        availId := isGen ? "GenAvailList" : "BranchAvailList"
        activeId := isGen ? "GenActiveList" : "BranchActiveList"
        sel := this._CtxSelIdx(availId)
        if (sel < 0 || sel >= avail.Length)
            return
        item := avail[sel + 1]
        actSel := this._CtxSelIdx(activeId)
        insertAt := (actSel >= 0 && actSel < active.Length) ? actSel + 2 : active.Length + 1
        active.InsertAt(insertAt, item)
        if (item != "Separator")
            avail.RemoveAt(sel + 1)
        this._RenderCtxLists(activeId, insertAt - 1)
    }

    OnCtxRemove(which, state, ctrl, event) {
        isGen := (which == "gen")
        active := isGen ? this._ctxGenActive : this._ctxBranchActive
        activeId := isGen ? "GenActiveList" : "BranchActiveList"
        sel := this._CtxSelIdx(activeId)
        if (sel < 0 || sel >= active.Length)
            return
        active.RemoveAt(sel + 1)
        newSel := (sel > 0) ? sel - 1 : (active.Length > 0 ? 0 : -1)
        this._RenderCtxLists(activeId, newSel)
    }

    OnIntEdit(fieldName, state, ctrl, event) {
        v := Trim(this.ui.Query(ctrl))
        if (v != "" && IsInteger(v)) {
            MainSoftData.%fieldName% := Integer(v)
            this.MarkSettingDirty(ctrl)
        }
    }

    OnTextEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
        this.MarkSettingDirty(ctrl)
    }

    ; 共享上传：退出登录 —— 清空本机凭据（论坛侧那条密钥不撤销，用户可自行去 个人设置 → 应用 撤销）
    OnShareLogoutClick(state, ctrl, event) {
        if (this._shareLoginTick != "") {              ; 正在等授权：一并取消
            SetTimer(this._shareLoginTick, 0)
            this._shareLoginTick := ""
            try GetDiscourse().CancelUserAuth()
        }
        SetShareAuth("", "")
        this._SetShareLoginState(this._ShareLoginStateText())
    }

    ; ---- 共享上传：浏览器授权登录（Discourse /user-api-key/new） ----
    ; 点按钮 → C# 起本地固定端口监听 + 打开浏览器授权页 → 轮询 GetAuthState()，
    ; 2 = 已用 RSA 私钥解出 key → 写 ini → 再用 key 打 /session/current.json 校验并显示用户名。
    ; 前置条件：站点后台 allowed_user_api_auth_redirects 必须逐字包含
    ;   http://127.0.0.1:38471/authcb（另 :38472 / :38473 是端口被占时的顺延位），
    ;   该设置不支持通配符，端口必须与 C# 的 AuthCallbackPorts 一致。
    OnShareLoginClick(state, ctrl, event) {
        if (this._shareLoginTick != "") {              ; 等待中再点 = 取消
            SetTimer(this._shareLoginTick, 0)
            this._shareLoginTick := ""
            try GetDiscourse().CancelUserAuth()
            this._SetShareLoginState(this._ShareLoginStateText())
            return
        }
        try GetDiscourse().BeginUserAuth(GetShareServerUrl())
        catch as e {
            this._SetShareLoginState(GetLang("无法开始授权：") . e.Message)
            return
        }
        this._SetShareLoginState(GetLang("已打开浏览器，请登录论坛并点「授权」…（再点本按钮可取消）"))
        this._shareLoginTick := ObjBindMethod(this, "PollShareLogin")
        SetTimer(this._shareLoginTick, 300)
    }

    PollShareLogin() {
        st := 0
        try st := Integer(GetDiscourse().GetAuthState())
        catch as e {
            SetTimer(this._shareLoginTick, 0)
            this._shareLoginTick := ""
            this._SetShareLoginState(GetLang("授权失败：") . e.Message)
            return
        }
        if (st = 1)                                   ; 1 = 仍在等回调（C# 侧 5 分钟超时）
            return
        SetTimer(this._shareLoginTick, 0)
        this._shareLoginTick := ""
        if (st != 2) {
            this._SetShareLoginState(this._ShareLoginStateText())
            return
        }
        raw := "", err := ""
        try raw := GetDiscourse().TakeAuthResult()
        try err := GetDiscourse().GetAuthError()
        key := ""
        if (raw != "" && RegExMatch(raw, '"key"\s*:\s*"([^"]+)"', &m))
            key := m[1]
        if (key == "") {
            if (err == "")
                err := GetLang("授权页未返回凭据")
            this._SetShareLoginState(GetLang("授权失败：") . err)
            return
        }
        ; 用户密钥模式：用户名必须留空（C# 的 ApplyAuth 据此发 User-Api-Key 而非 Api-Key）
        SetShareAuth("", key)
        this._SetShareLoginState(GetLang("已授权，正在校验…"))
        this.StartShareVerify(key)
    }

    ; 用刚拿到的 key 打一次 /session/current.json：既确认凭据可用，也顺带取回用户名显示
    StartShareVerify(key) {
        if (this._shareVerifyTick != "")
            return
        try GetDiscourse().SetAuth("", key)
        try GetDiscourse().BeginGetTextAuth(GetShareServerUrl() . "/session/current.json")
        this._shareVerifyTick := ObjBindMethod(this, "PollShareVerify")
        SetTimer(this._shareVerifyTick, 400)
    }

    PollShareVerify() {
        st := 0
        try st := Integer(GetDiscourse().GetTextAuthState())
        catch {
            SetTimer(this._shareVerifyTick, 0)
            this._shareVerifyTick := ""
            this._SetShareLoginState(GetLang("已保存凭据（未能校验）"))
            return
        }
        if (st = 1)
            return
        SetTimer(this._shareVerifyTick, 0)
        this._shareVerifyTick := ""
        body := ""
        if (st = 2)
            try body := GetDiscourse().TakeTextAuthResult()
        if (body != "" && RegExMatch(body, '"username"\s*:\s*"([^"]+)"', &m))
            this._SetShareLoginState(GetLang("已登录：") . m[1])
        else
            this._SetShareLoginState(GetLang("凭据已保存，但校验未通过（可能已在论坛被撤销）"))
    }

    ; 状态行初始文案：只读 ini，不联网（启动时不发请求；校验只在点「登录论坛」后做）
    _ShareLoginStateText() {
        if (GetShareApiKey() == "")
            return GetLang("未登录")
        u := GetShareApiUser()
        return (u != "") ? GetLang("已登录（管理员 Key）：") . u : GetLang("已登录")
    }

    _SetShareLoginState(text) {
        try this.ui.Update("TxtShareLoginState", "Text", text)
    }

    ; 文本框焦点跟踪：主窗口聚焦文本框时，侧栏逻辑树的 $^c/$^v/$^z/$^y/Delete 需透传（见 MacroEditGui._PassEditKeyToTextInput）
    OnTextInputFocus(nm, state, ctrl, event) {
        this._textFocusName := nm
    }

    OnTextInputBlur(nm, state, ctrl, event) {
        if (this._textFocusName == nm)
            this._textFocusName := ""
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

    OnSettingHelpClick(name, state := "", ctrl := "", event := "") {
        if (!this.HasProp("_setHelpMap") || !this._setHelpMap.Has(name))
            return
        item := this._setHelpMap[name]
        if (item.HasProp("fn") && item.fn != "") {
            item.fn()
            return
        }
        RmtDialog.Info(item.text, item.title)
    }

    OnCheckEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl) == "True"
        this.MarkSettingDirty(ctrl)
    }

    ; §10 显示页签勾选：写入 TabVisibleMap（保存后重启生效）
    OnTabVisibleCheck(symbol, state, ctrl, event) {
        if (!MainSoftData.TabVisibleMap.Has(symbol))
            return
        MainSoftData.TabVisibleMap[symbol] := this.ui.Query(ctrl) == "True"
        this.MarkSettingDirty(ctrl)
    }

    _TabVisibleVal(symbol) {
        return (MainSoftData.TabVisibleMap.Has(symbol)) ? MainSoftData.TabVisibleMap[symbol] : true
    }

    ; 业务日志开关：写 MainSoftData + 同步 LogUtil global + 持久化
    OnBusinessLogToggle(state, ctrl, event) {
        global RMTLogBusinessEnabled
        MainSoftData.BusinessLog := this.ui.Query(ctrl) == "True"
        this.MarkSettingDirty(ctrl)
        RMTLogBusinessEnabled := MainSoftData.BusinessLog
        CfgWrite(MainSoftData.BusinessLog, SettingFile, SettingSection, "BusinessLog")
    }

    OnComboText(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
        this.MarkSettingDirty(ctrl)
    }

    OnTriggerJoyTypeChanged(state, ctrl, event) {
        this.OnComboText("TriggerJoyType", state, ctrl, event)
        this._RefreshJoyLtRtAsButtonText()
    }

    _JoyLtRtAsButtonLabel() {
        isPs5 := (MainSoftData.TriggerJoyType == "PS5")
        return GetLang(isPs5 ? "L2、R2按键化" : "LT、RT按键化")
    }

    _JoyLtRtAsButtonDesc() {
        isPs5 := (MainSoftData.TriggerJoyType == "PS5")
        return Format(GetLang("开启后 {} 当普通按键；关闭则当扳机轴，可设 0~100。"), isPs5 ? "L2/R2" : "LT/RT")
    }

    _RefreshJoyLtRtAsButtonText() {
        if (!IsObject(this.ui))
            return
        this.ui.Update("LblJoyLtRtAsButton", "Text", this._JoyLtRtAsButtonLabel())
        this.ui.Update("LblJoyLtRtAsButton_Desc", "Text", this._JoyLtRtAsButtonDesc())
    }

    OnComboIndex(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := Integer(this.ui.Query(ctrl ">SelectedIndex")) + 1
        this.MarkSettingDirty(ctrl)
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
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Help 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Help")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ; 结构与 HelpTabLayoutReference.html 一致：先说明合法使用，再给出文档、社区与反馈入口。
        disclaimerRules := '<Grid Margin="10,8"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Border Grid.Row="0" Grid.Column="0" Margin="0,0,8,5" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("1", "本软件按“原样”提供。因使用、修改、传播或分发本软件所产生的风险与后果，由使用者自行承担；开发者不作任何明示或默示担保。") '</Border>'
            . '<Border Grid.Row="0" Grid.Column="1" Margin="8,0,0,5" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("2", "本软件仅限用于合法且已获授权的场景。严禁用于游戏作弊、未经授权的系统访问、数据篡改，或其他违反法律法规及第三方规则的行为。") '</Border>'
            . '<Border Grid.Row="1" Grid.Column="0" Margin="0,5,8,0" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("3", "使用前，请自行确认使用方式符合所在地法律法规、平台条款及相关约定。因违规使用而引发的损失、纠纷或责任，与开发者无关。") '</Border>'
            . '<Border Grid.Row="1" Grid.Column="1" Margin="8,5,0,0" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("4", "下载、安装或使用本软件，即表示你已充分理解并接受上述风险承诺：不将其用于任何非法目的，并同意不就他人滥用行为向开发者追责。") '</Border>'
            . '</Grid>'
        disclaimer := '<StackPanel><TextBlock Text="' this._XmlEsc(GetLang("本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力")) '" FontSize="10" Foreground="{DynamicResource TextSub}" Margin="0,0,0,8"/>'
            . disclaimerRules
            . '<TextBlock Text="' this._XmlEsc(GetLang("若不同意上述条款，请立即停止使用本软件。")) '" Foreground="{DynamicResource Accent}" FontWeight="Bold" FontSize="12" Margin="0,9,0,0"/></StackPanel>'
        Add(this._HelpCard(GetLang("免责声明与合法使用提醒"), "&#xE7BA;", disclaimer, "", "0,2,0,14", true))

        docs := '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Padding="0,0,12,0">' this._HelpResource("&#xE8A5;", GetLang("软件说明文档"), GetLang("快速上手、指令手册、常见问题、常见报错与更新日志。"), "https://docs.ruomengtu.com/", GetLang("打开文档")) '</Border>'
            . '<Border Grid.Column="1" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1,0,0,0" Padding="12,0">' this._HelpResource("&#xE714;", GetLang("更新视频合集"), GetLang("查看版本更新视频与直播交流问答。"), "https://www.bilibili.com/video/BV1yR8x6xEBW", GetLang("观看视频")) '</Border>'
            . '<Border Grid.Column="2" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1,0,0,0" Padding="12,0,0,0">' this._HelpResource("&#xE8B7;", GetLang("配置共享仓库"), GetLang("案例学习、获取他人分享的宏配置，并支持下载导入。"), "https://zclucas.github.io/RMT-Setting/", GetLang("查看仓库")) '</Border></Grid>'
        Add(this._HelpCard(GetLang("文档与学习"), "&#xE8A5;", docs, GetLang("从入门到进阶"), "0,0,0,14"))

        community := '<Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._HelpCommunityTile(0, 0, "&#xE902;", GetLang("RMT 交流论坛"), GetLang("经验交流、问题讨论与社区动态"), "https://forum.ruomengtu.com/", "0,0,5,5")
            . this._HelpCommunityTile(0, 1, "&#xE8BD;", GetLang("RMT QQ 交流群"), GetLang("加入群组以参与反馈文档编辑"), "https://qm.qq.com/q/DgpDumEPzq", "5,0,0,5")
            . this._HelpCommunityTile(1, 0, "&#xE943;", GetLang("GitHub 开源地址"), GetLang("查看发行版与软件最新版本"), "https://github.com/zclucas/RMT", "0,5,5,0")
            . this._HelpCommunityTile(1, 1, "&#xE8B7;", GetLang("Gitee 开源地址"), GetLang("镜像项目源代码与版本信息"), "https://gitee.com/fateman/RMT", "5,5,0,0")
            . '</Grid>'

        feedback := '<StackPanel><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._HelpFeedbackItem(0, "&#xE7BA;", GetLang("Bug 文档"), GetLang("提交可复现步骤、预期结果、实际表现，以及必要的截图或日志。"), "https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj", GetLang("打开 Bug 文档"), "0,0,5,0")
            . this._HelpFeedbackItem(1, "&#xE8F2;", GetLang("需求文档"), GetLang("描述使用场景、期望能力与优先级，帮助我们评估和规划。"), "https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo", GetLang("打开需求文档"), "5,0,0,0")
            . '</Grid>'
            . '<Border Margin="0,10,0,0">' this._HelpFeedbackItem(0, "&#xE8BD;", GetLang("在软件内直接提交"), GetLang("不用跳浏览器：填标题和描述即可发到论坛，自动带上 RMT 版本、系统、屏幕缩放，还可以直接附截图。"), "rmt:feedback", GetLang("立即反馈"), "0") '</Border>'
            . '<Border Margin="0,10,0,0" Padding="9,7" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" Margin="0,0,7,0"/><TextBlock Text="' this._XmlEsc(GetLang("Bug 文档和需求文档需要加入交流群后才可编辑；未加入时仍可打开查看现有内容。")) '" TextWrapping="Wrap" Foreground="{DynamicResource TextSub}" FontSize="11"/></StackPanel></Border></StackPanel>'

        lower := '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Grid.Column="0" Margin="0,0,7,0">'
            . this._HelpCard(GetLang("社区"), "&#xE8BD;", community, GetLang("交流、群组与开源"), "0")
            . '</Border><Border Grid.Column="1" Margin="7,0,0,0">'
            . this._HelpCard(GetLang("问题反馈"), "&#xE7BA;", feedback, GetLang("共同完善 RMT"), "0")
            . '</Border></Grid>'
        Add(lower)

        this._FlushLinks()
    }

    _HelpCard(title, glyph, body, hint := "", margin := "0", warning := false, headH := 42) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        accent := warning ? '{DynamicResource Accent}' : '{DynamicResource OutlineStroke}'
        titleSize := headH <= 30 ? "12" : "13"
        glyphSize := headH <= 30 ? "13" : "14"
        hintXaml := hint == "" ? "" : '<TextBlock Grid.Column="1" Text="' this._XmlEsc(hint) '" Foreground="{DynamicResource TextSub}" FontSize="11" FontWeight="Normal" VerticalAlignment="Center" HorizontalAlignment="Right"/>'
        return '<Border ' ns ' Margin="' margin '" Background="{DynamicResource ControlBg}" BorderBrush="' accent '" BorderThickness="1.25" CornerRadius="8" Padding="0">'
            . '<Grid><Grid.RowDefinitions><RowDefinition Height="' headH '"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<Border Grid.Row="0" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="0,0,0,1" CornerRadius="7,7,0,0" Padding="13,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' glyphSize '" Foreground="{DynamicResource Accent}" Margin="0,0,8,0" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="' titleSize '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel>' hintXaml '</Grid></Border>'
            . '<Border Grid.Row="1" Padding="13,11">' body '</Border></Grid></Border>'
    }

    _HelpDisclaimerItem(number, text) {
        return '<Grid Margin="0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="19" Height="19" CornerRadius="9.5" Background="{DynamicResource Accent}" VerticalAlignment="Top"><TextBlock Text="' number '" Foreground="{DynamicResource ActionText}" FontWeight="Bold" FontSize="10" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Grid.Column="1" Text="' this._XmlEsc(GetLang(text)) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextMain}"/></Grid>'
    }

    _HelpResource(glyph, title, description, url, buttonText) {
        return '<StackPanel><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Orientation="Horizontal"><Border Width="27" Height="27" CornerRadius="6" Background="{DynamicResource EditHoverBg}" Margin="0,0,7,0"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Grid.Row="1" Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,8,0,9"/></Grid>'
            . this._HelpLinkButton(url, buttonText) '</StackPanel>'
    }

    _HelpCommunityTile(row, col, glyph, title, description, url, margin) {
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Margin="' margin '" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6">'
            . this._HelpTileButton(url, glyph, title, description) '</Border>'
    }

    _HelpFeedbackItem(col, glyph, title, description, url, buttonText, margin) {
        return '<Border Grid.Column="' col '" Margin="' margin '" Padding="10" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><StackPanel><StackPanel Orientation="Horizontal"><Border Width="26" Height="26" CornerRadius="6" Background="{DynamicResource EditHoverBg}" Margin="0,0,7,0"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,0,8"/>' this._HelpLinkButton(url, buttonText) '</StackPanel></Border>'
    }

    _HelpTileButton(url, glyph, title, description) {
        this._linkCounter := this._linkCounter + 1
        name := "HelpLink_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        return '<Button Name="' name '" Cursor="Hand" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch"><Grid Margin="10"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="26" Height="26" CornerRadius="6" Background="{DynamicResource EditHoverBg}"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Grid.Column="1" Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/><TextBlock Grid.Row="1" Grid.ColumnSpan="2" Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource TextSub}" Margin="0,7,0,0"/></Grid></Button>'
    }

    _HelpLinkButton(url, text, accent := false) {
        this._linkCounter := this._linkCounter + 1
        name := "HelpLink_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        bg := accent ? "{DynamicResource EditHoverBg}" : "{DynamicResource InputBg}"
        fg := accent ? "{DynamicResource Accent}" : "{DynamicResource TextMain}"
        weight := accent ? "Bold" : "Normal"
        return '<Button Name="' name '" Cursor="Hand" HorizontalAlignment="Left" MinHeight="25" Padding="8,0" VerticalContentAlignment="Center" Background="' bg '" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><Grid VerticalAlignment="Center"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="' this._XmlEsc(text) '" FontSize="10" FontWeight="' weight '" Foreground="' fg '" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="9" Foreground="{DynamicResource Accent}" Margin="5,0,0,0" VerticalAlignment="Center"/></Grid></Button>'
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
        if (url = "")
            return
        ; 软件内反馈：不走浏览器，直接开反馈窗口
        if (url = "rmt:feedback") {
            FeedbackGui.ShowGui()
            return
        }
        ; 本地 html 帮助文档 → 优先用 Chromium app 模式小窗打开
        if (RegExMatch(url, "i)\.html?$") && FileExist(url) && OpenHelpInAppWindow())
            return
        Run(url)
    }

    ; ============ 赞助页 ============
    BuildRewardTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Reward 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Reward")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        countStr := FormatIntegerWithCommas(MySoftData.MacroTotalCount)
        weiXinImg := StrReplace(A_WorkingDir "\Images\Soft\WeiXin.png", "\", "/")
        zhiFuBaoImg := StrReplace(A_WorkingDir "\Images\Soft\ZhiFuBao.png", "\", "/")
        ; 赞助二维码通过 FileInstall 编译进主程序，运行时不读取 Images\Soft 下的同名文件。
        aiFaDianImg := this._GetBuiltInSupportQr("aifadian")
        stripe2Img := this._GetBuiltInSupportQr("stripe2")
        stripe5Img := this._GetBuiltInSupportQr("stripe5")
        stripe2Url := this._ReadQrUrl(stripe2Img)
        stripe5Url := this._ReadQrUrl(stripe5Img)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        hero := '<Border ' ns ' Margin="0,2,0,14" Padding="18,15" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1.25" CornerRadius="8"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="' this._XmlEsc(GetLang("感谢每一位支持 RMT 的守护者")) '" FontSize="16" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(GetLang("RMT 始终免费、开源。若它为你节省了时间，欢迎用一杯咖啡的心意支持开发与维护。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,14,0"/><TextBlock Text="' this._XmlEsc(GetLang("若暂时不方便，分享给朋友同样是珍贵的支持。开发不易，感谢你的每一份温暖！")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,5,14,0"/><Border HorizontalAlignment="Left" Margin="0,8,0,0" Padding="8,3" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><TextBlock Text="' this._XmlEsc(GetLang("功能无限制，赞助自愿")) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/></Border></StackPanel><StackPanel Grid.Column="1" VerticalAlignment="Center"><Border Padding="12,8" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Border Width="28" Height="28" CornerRadius="14" Background="{DynamicResource EditHoverBg}" Margin="0,0,8,0"><TextBlock Text="&#xE823;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel><TextBlock Text="' this._XmlEsc(GetLang("已累计执行")) '" FontSize="10" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' countStr '" TextWrapping="NoWrap" FontSize="20" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,0"/></StackPanel></StackPanel></Border></StackPanel></Grid></Border>'
        Add(hero)

        singleSupport := '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._SupportQrCard(0, 0, 1, weiXinImg, GetLang("微信赞助"), GetLang("扫码完成一次性赞助。快捷直接，适合随时表达一份心意。"), "0,0,5,0")
            . this._SupportQrCard(0, 1, 1, zhiFuBaoImg, GetLang("支付宝赞助"), GetLang("扫码完成一次性赞助。与微信同为推荐的直接支持方式。"), "5,0,0,0")
            . '</Grid>'
        guardianButtons := '<StackPanel Orientation="Horizontal">' this._HelpLinkButton("https://forum.ruomengtu.com/", GetLang("打开 RMT 论坛")) '<Border Width="7"/> ' this._HelpLinkButton("https://qm.qq.com/q/DgpDumEPzq", GetLang("加入 QQ 交流群")) '</StackPanel>'
        benefits := '<StackPanel>'
            . this._SupportAfterCard(0, 0, 1, "&#xE902;", GetLang("领取守护者称号"), GetLang("完成赞助后，可通过 RMT 论坛或 RMT QQ 交流群私信联系，领取论坛和 QQ 交流群的“守护者”称号。"), guardianButtons, "0,0,0,10")
            . this._SupportAfterCard(1, 0, 1, "&#xE8A5;", GetLang("若梦星河"), GetLang("赞助后的留言会展示在若梦星河，感谢每一位让 RMT 走得更远的朋友。"), this._HelpLinkButton("https://docs.ruomengtu.com/supporters/", GetLang("打开若梦星河")), "0", GetLang("提示：名单会在版本更新时统一更新。"))
            . '</StackPanel>'
        stripeSupport := '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._SupportQrCard(0, 0, 1, stripe2Img, GetLang("2 美元 / 月"), GetLang("扫码或打开链接，用一份持续的心意陪伴 RMT。"), "0,0,5,0", "", stripe2Url, GetLang("打开订阅页"), true)
            . this._SupportQrCard(0, 1, 1, stripe5Img, GetLang("5 美元 / 月"), GetLang("扫码或打开链接，以更深的心意，陪伴 RMT 走过更多精彩旅程。"), "5,0,0,0", "", stripe5Url, GetLang("打开订阅页"), true)
            . '</Grid>'
        aiFaDian := this._SupportAiFaDianSideCard(aiFaDianImg)
        enterprise := this._SupportEnterpriseCard()
        supportLayout := '<Grid ' ns ' Margin="0,0,0,14"><Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Margin="0,0,7,0">'
            . this._HelpCard(GetLang("个人赞助"), "&#xE8C7;", singleSupport, GetLang("微信与支付宝"), "0,0,0,14", false, 30)
            . this._HelpCard(GetLang("Stripe订阅"), "&#xE8C8;", stripeSupport, GetLang("国际卡按月"), "0,0,0,14", false, 30)
            . this._HelpCard(GetLang("爱发电 · 月度守护"), "&#xE8C8;", aiFaDian, GetLang("国内按月"), "0", false, 30)
            . '</StackPanel><StackPanel Grid.Column="1" Margin="7,0,0,0">'
            . this._HelpCard(GetLang("企业赞助"), "&#xE731;", enterprise, "", "0,0,0,14", false, 30)
            . this._HelpCard(GetLang("感谢与留念"), "&#xE9CE;", benefits, GetLang("让每份心意被看见"), "0", false, 30)
            . '</StackPanel></Grid>'
        Add(supportLayout)
        this._Bind("RewardSponsorMailCopy", "Click", ObjBindMethod(this, "OnCopySponsorMail"))
        this._FlushLinks()
    }

    _SupportEnterpriseCard() {
        mail := "ruomengtu@gmail.com"
        return '<StackPanel><TextBlock Text="' this._XmlEsc(GetLang("欢迎企业、工作室及团队支持 RMT 开源项目的长期发展。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}"/><TextBlock Text="' this._XmlEsc(GetLang("非诚勿扰")) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,6,0,0"/><WrapPanel Margin="0,10,0,0"><TextBlock Text="' this._XmlEsc(GetLang("联系邮箱：")) '" FontSize="11" Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(mail) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMain}" VerticalAlignment="Center" Margin="0,0,8,0"/><Button Name="RewardSponsorMailCopy" Cursor="Hand" Width="25" Height="25" Padding="0" VerticalAlignment="Center" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" ToolTip="' this._XmlEsc(GetLang("复制")) '"><TextBlock Text="&#xE8C8;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Button></WrapPanel></StackPanel>'
    }

    OnCopySponsorMail(*) {
        A_Clipboard := "ruomengtu@gmail.com"
        try Toast.Success(GetLang("已复制"))
    }

    _SupportQrCard(row, col, span, image, title, description, margin, badge := "", url := "", btnText := "", accentBtn := false) {
        badgeXaml := ""
        if (url == "") {
            if (badge == "")
                badge := GetLang("推荐 · 单次赞助")
            badgeXaml := '<Border HorizontalAlignment="Left" Padding="8,4" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="4"><TextBlock Text="' this._XmlEsc(badge) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}"/></Border>'
        }
        btnXaml := url == "" ? "" : '<Border Margin="0,10,0,0">' this._HelpLinkButton(url, btnText, accentBtn) '</Border>'
        descMargin := url == "" ? "0,10,0,12" : "0,10,0,0"
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Grid.ColumnSpan="' span '" Margin="' margin '" MinHeight="166" Padding="16" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="138"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="132" Height="132" Padding="5" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Image Source="' image '" Stretch="Uniform"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="14" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="' descMargin '"/>' badgeXaml btnXaml '</StackPanel></Grid></Border>'
    }

    _SupportAiFaDianSideCard(image) {
        return '<Border MinHeight="166" Padding="16" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="138"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="132" Height="132" Padding="5" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Image Source="' image '" Stretch="Uniform"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center">' this._SupportFactBox(GetLang("按月支持"), GetLang("长期守护与支持"), "0,0,0,8") this._SupportFactBox(GetLang("手续费"), GetLang("每笔6%手续费"), "0") '</StackPanel></Grid></Border>'
    }

    _SupportFactBox(title, description, margin) {
        return '<Border Margin="' margin '" Padding="9,7" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><StackPanel><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="11" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource TextSub}" Margin="0,3,0,0"/></StackPanel></Border>'
    }

    _GetBuiltInSupportQr(kind) {
        static paths := Map()
        if (paths.Has(kind))
            return paths[kind]
        switch kind {
            case "stripe2":
                tempPath := A_Temp "\RMT_Stripe2.png"
                try FileInstall("Images\Soft\Stripe2.png", tempPath, 1)
                src := A_WorkingDir "\Images\Soft\Stripe2.png"
            case "stripe5":
                tempPath := A_Temp "\RMT_Stripe5.png"
                try FileInstall("Images\Soft\Stripe5.png", tempPath, 1)
                src := A_WorkingDir "\Images\Soft\Stripe5.png"
            default:
                tempPath := A_Temp "\RMT_AiFaDian.png"
                try FileInstall("Images\Soft\AiFaDian.png", tempPath, 1)
                src := A_WorkingDir "\Images\Soft\AiFaDian.png"
        }
        if (FileExist(tempPath)) {
            paths[kind] := StrReplace(tempPath, "\", "/")
            return paths[kind]
        }
        ; 脚本模式 / 临时文件占用时回退到工作目录源图，避免赞助页拖垮 PopulateAll
        if (FileExist(src))
            return StrReplace(src, "\", "/")
        return ""
    }

    _GetQrDecodeExe() {
        static exePath := ""
        if (exePath != "" && FileExist(exePath))
            return exePath
        dir := A_Temp "\RMT_SupportQr"
        DirCreate(dir)
        destExe := dir "\QrDecode.exe"
        destDll := dir "\zxing.dll"
        try FileInstall("Plugins\SupportQr\QrDecode.exe", destExe, 1)
        try FileInstall("Plugins\SupportQr\zxing.dll", destDll, 1)
        if (!FileExist(destExe)) {
            srcExe := A_WorkingDir "\Plugins\SupportQr\QrDecode.exe"
            srcDll := A_WorkingDir "\Plugins\SupportQr\zxing.dll"
            if (FileExist(srcExe)) {
                FileCopy(srcExe, destExe, 1)
                if (FileExist(srcDll))
                    FileCopy(srcDll, destDll, 1)
            }
        }
        if (FileExist(destExe))
            exePath := destExe
        return exePath
    }

    _ReadQrUrl(imagePath) {
        static cache := Map()
        if (imagePath == "")
            return ""
        if (cache.Has(imagePath))
            return cache[imagePath]
        exe := this._GetQrDecodeExe()
        if (exe == "")
            return ""
        winPath := StrReplace(imagePath, "/", "\")
        if (!FileExist(winPath))
            return ""
        dir := A_Temp "\RMT_SupportQr"
        outFile := dir "\out.txt"
        try FileDelete(outFile)
        cmd := Format('"{1}" /c ""{2}" "{3}" > "{4}""', A_ComSpec, exe, winPath, outFile)
        try RunWait(cmd, dir, "Hide")
        if (!FileExist(outFile))
            return ""
        url := Trim(FileRead(outFile, "UTF-8"), " `t`r`n")
        if (!RegExMatch(url, "i)^https?://"))
            return ""
        cache[imagePath] := url
        return url
    }

    _SupportAfterCard(row, col, span, glyph, title, description, footer, margin, note := "") {
        noteXaml := note == "" ? "" : '<TextBlock Text="' this._XmlEsc(note) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource Accent}" Margin="0,7,0,0"/>'
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Grid.ColumnSpan="' span '" Margin="' margin '" Padding="11" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><StackPanel><StackPanel Orientation="Horizontal"><Border Width="26" Height="26" CornerRadius="6" Background="{DynamicResource EditHoverBg}" Margin="0,0,7,0"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,0,0"/>' noteXaml '<Border Margin="0,10,0,0">' footer '</Border></StackPanel></Border>'
    }

    ; ============ 特别感谢页 ============
    BuildThankTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Thank 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Thank")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        wall := '<Border ' ns ' Margin="0,2,0,14" Padding="16,14" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource Accent}" BorderThickness="1.25" CornerRadius="8"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE734;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="15" Margin="0,0,8,0"/><TextBlock Text="' this._XmlEsc(GetLang("若梦星河")) '" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Text="' this._XmlEsc(GetLang("这里会逐步收录支持者留言、开发者贡献与开源项目，也会记录让 RMT 持续成长的每一份善意与协作。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,16,0"/><TextBlock Text="' this._XmlEsc(GetLang("提示：收录数据会在版本更新时统一更新。")) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,5,0,0"/></StackPanel><Border Grid.Column="1" VerticalAlignment="Center" Margin="10,0,0,0">' this._ThankLinkButton("https://docs.ruomengtu.com/supporters/", GetLang("打开若梦星河"), "&#xE734;") '</Border></Grid></Border>'
        Add(wall)
        Add('<ContentControl ' ns ' Name="ThankSponsorHost" HorizontalAlignment="Stretch" HorizontalContentAlignment="Stretch" Visibility="Collapsed"/>')

        dev := '<Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._ThankContributor(0, 0, "yun", "yun", this._GetBuiltInThankAvatar("yun"), "https://github.com/yunkuangao", "0,0,5,5")
            . this._ThankContributor(0, 1, "boxstudy", "B", this._GetBuiltInThankAvatar("boxstudy"), "https://github.com/boxstudy", "5,0,5,5")
            . this._ThankContributor(0, 2, "sovaedv776", "S", this._GetBuiltInThankAvatar("sovaedv776"), "https://github.com/sovaedv776", "5,0,0,5")
            . this._ThankContributor(1, 0, "张正波", "张", "", "https://gitee.com/bogezzb", "0,5,5,0")
            . this._ThankContributor(1, 1, "GushuLily", "G", this._GetBuiltInThankAvatar("gushulily"), "https://github.com/GushuLily", "5,5,5,0")
            . this._ThankContributor(1, 2, "T8numen", "T", this._GetBuiltInThankAvatar("t8numen"), "https://github.com/T8numen", "5,5,0,0")
            . '</Grid>'

        oss := '<Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._ThankProject(0, 0, "&#xE8BD;", "Discourse", "为 RMT 社区论坛提供支持。", "https://github.com/discourse/discourse", "0,0,5,5")
            . this._ThankProject(0, 1, "&#xE720;", "sherpa-onnx", "为 RMT 语音关键词识别提供支持。", "https://github.com/k2-fsa/sherpa-onnx", "5,0,0,5")
            . this._ThankProject(1, 0, "&#xE91B;", "OpenCV", "视觉识别与图像处理能力。", "https://github.com/opencv/opencv", "0,5,5,5")
            . this._ThankProject(1, 1, "&#xE8B7;", "ahk2_lib", "AutoHotkey v2 基础工具库。", "https://github.com/thqby/ahk2_lib", "5,5,0,5")
            . this._ThankProject(2, 0, "&#xE8A9;", "RapidOCR", "本地文字识别能力。", "https://github.com/RapidAI/RapidOCR", "0,5,5,0")
            . this._ThankProject(2, 1, "&#xE7FC;", "ViGEm Bus", "虚拟手柄支持。", "https://github.com/nefarius/ViGEmBus", "5,5,0,0")
            . '</Grid>'

        cocreate := '<StackPanel>'
            . this._ThankInfoBlock("&#xE8D7;", GetLang("感谢若梦兔守护者的支持与陪伴。每一份信任都让 RMT 能够持续维护、不断成长。"), "0,0,0,7")
            . this._ThankInfoBlock("&#xE946;", GetLang("有效的 Bug 反馈与需求建议、社区答疑和配置分享，都是 RMT 的共创力量。参与的伙伴会收录在若梦星河。"), "0")
            . '</StackPanel>'
        community := '<StackPanel><TextBlock Text="' this._XmlEsc(GetLang("感谢在社区中积极交流、提出建议、协助答疑的每一位群友。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,0,0,9"/><WrapPanel>'
            . this._ThankNickname("AYu") this._ThankNickname("万年置伞") this._ThankNickname("别说*不下啦") this._ThankNickname("仰望") this._ThankNickname("话听") this._ThankNickname("yun") this._ThankNickname("小足")
            . '</WrapPanel></StackPanel>'

        layout := '<Grid ' ns ' Margin="0,0,0,14"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="1.55*"/><ColumnDefinition Width="0.85*"/></Grid.ColumnDefinitions><Border Grid.Row="0" Grid.Column="0" Margin="0,0,7,7">'
            . this._HelpCard(GetLang("开发贡献者"), "&#xE77B;", dev, GetLang("感谢同行"), "0", false, 30)
            . '</Border><Border Grid.Row="1" Grid.Column="0" Margin="0,7,7,0">'
            . this._HelpCard(GetLang("开源项目支持"), "&#xE8B7;", oss, GetLang("致谢以下开源项目"), "0", false, 30)
            . '</Border><Border Grid.Row="0" Grid.Column="1" Margin="7,0,0,7">'
            . this._HelpCard(GetLang("守护与共创"), "&#xE8D4;", cocreate, "", "0", false, 30)
            . '</Border><Border Grid.Row="1" Grid.Column="1" Margin="7,7,0,0" VerticalAlignment="Top">'
            . this._HelpCard(GetLang("社区活跃伙伴"), "&#xE902;", community, GetLang("QQ 昵称"), "0", false, 30)
            . '</Border></Grid>'
        Add(layout)
        this._thankReady := true
        this._FlushLinks()
        this.ApplyThankSponsors()
    }

    ; 有赞助时显示在开发贡献者上方。回包晚于页面构建时，由 ApplyRMTServerRsp 再调用。
    ApplyThankSponsors() {
        global RMT_Sponsors
        if (!this._thankReady || this._thankSponsorShown)
            return
        if (!IsSet(RMT_Sponsors) || !(RMT_Sponsors is Array) || RMT_Sponsors.Length < 1)
            return
        queued := this._linkQueue.Length
        shown := []
        for sp in RMT_Sponsors {
            localPath := EnsureSponsorLogo(sp.Has("logo") ? sp["logo"] : "")
            if (localPath == "")
                continue
            shown.Push(Map(
                "name", sp.Has("name") ? sp["name"] : "",
                "logo", StrReplace(localPath, "\", "/"),
                "url", sp.Has("url") ? sp["url"] : ""
            ))
        }
        if (shown.Length < 1)
            return
        this._sponsorLogos := shown
        this._sponsorLayoutKey := ""
        ; 「感谢支持」与「QQ 昵称」同走提示文字：字号 11、常规字重
        body := '<StackPanel Name="ThankSponsorLogos" HorizontalAlignment="Stretch"/>'
        card := this._HelpCard(GetLang("企业赞助"), "&#xE731;", body, GetLang("感谢支持"), "0,0,0,14", false, 30)
        try {
            this.ui.Update("ThankSponsorHost", "AddXamlItem", card)
            this.ui.Update("ThankSponsorHost", "Visibility", "Visible")
        } catch {
            while (this._linkQueue.Length > queued)
                this._linkQueue.Pop()
            return
        }
        this._thankSponsorShown := true
        this._Bind("ThankSponsorLogos", "SizeChanged", ObjBindMethod(this, "LayoutThankSponsors"))
        this.LayoutThankSponsors()
    }

    ; 按当前宽度均分行列：多出来的名额放在上面几行（n+1），其余为 n
    LayoutThankSponsors(*) {
        if (this._sponsorLaying || this._sponsorLogos.Length < 1)
            return
        w := ""
        try w := this.ui.Query("ThankSponsorLogos>ActualWidth")
        if (w == "" || !IsNumber(w))
            return
        w := Integer(Floor(Number(w)))
        if (w < 80) {
            if (!this._sponsorLayoutWait) {
                this._sponsorLayoutWait := ObjBindMethod(this, "LayoutThankSponsors")
                SetTimer(this._sponsorLayoutWait, -120)
            }
            return
        }
        slot := 124
        cap := Integer(Floor(w / slot))
        if (cap < 1)
            cap := 1
        n := this._sponsorLogos.Length
        if (cap > n)
            cap := n
        rows := Integer(Ceil(n / cap))
        key := cap "|" rows "|" n
        if (key == this._sponsorLayoutKey)
            return
        this._sponsorLaying := true
        this._sponsorLayoutKey := key
        try {
            base := n // rows
            extra := Mod(n, rows)
            ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
            this.ui.Update("ThankSponsorLogos", "ClearItems", "")
            idx := 1
            loop rows {
                take := base + (A_Index <= extra ? 1 : 0)
                rowXaml := '<StackPanel ' ns ' Orientation="Horizontal" HorizontalAlignment="Center">'
                loop take {
                    rowXaml .= this._ThankSponsorLogo(this._sponsorLogos[idx])
                    idx++
                }
                rowXaml .= '</StackPanel>'
                this.ui.Update("ThankSponsorLogos", "AddXamlItem", rowXaml)
            }
            this._FlushLinks()
        } finally {
            this._sponsorLaying := false
        }
    }

    ; 无边框 100×100 logo，悬停时在指针上方弹出企业名称，点击打开链接
    _ThankSponsorLogo(sp) {
        name := sp["name"] != "" ? sp["name"] : GetLang("企业赞助")
        logo := sp["logo"]
        url := sp["url"]
        tip := '<Button.ToolTip><ToolTip Placement="Mouse" HorizontalOffset="12" VerticalOffset="-32" Padding="8,3" FontSize="11" Background="{DynamicResource ControlBg}" Foreground="{DynamicResource TextMain}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><TextBlock Text="' this._XmlEsc(name) '" FontSize="11"/></ToolTip></Button.ToolTip>'
        img := '<Image Width="100" Height="100" Source="' this._XmlEsc(logo) '" Stretch="Uniform"/>'
        tpl := '<Button.Template><ControlTemplate TargetType="Button"><ContentPresenter/></ControlTemplate></Button.Template>'
        cursor := "Arrow"
        btnName := ""
        if (url != "") {
            this._linkCounter := this._linkCounter + 1
            btnName := "ThankSponsor_" this._linkCounter
            this._linkQueue.Push({ name: btnName, url: url, event: "Click" })
            cursor := "Hand"
        }
        nameAttr := btnName == "" ? "" : ' Name="' btnName '"'
        return '<Button' nameAttr ' Cursor="' cursor '" Background="Transparent" BorderThickness="0" Padding="0" Margin="12,8" FocusVisualStyle="{x:Null}">' tpl tip img '</Button>'
    }

    _ThankLinkButton(url, text, glyph := "&#xE8A7;") {
        this._linkCounter := this._linkCounter + 1
        name := "ThankLink_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        return '<Button Name="' name '" Cursor="Hand" MinHeight="35" Padding="15,7" VerticalContentAlignment="Center" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1">' this._ThankSoftHoverTemplate() '<StackPanel Orientation="Horizontal"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" Margin="0,0,6,0" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(text) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/><TextBlock Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="9" Foreground="{DynamicResource Accent}" Margin="6,0,0,0" VerticalAlignment="Center"/></StackPanel></Button>'
    }

    ; 特别感谢页的可点击卡片沿用设置左侧分类的柔和悬停底色，避免默认按钮高亮过重。
    _ThankSoftHoverTemplate() {
        return '<Button.Template><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListAltBg}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Button.Template>'
    }

    _ThankContributor(row, col, title, initial, image, url, margin) {
        this._linkCounter := this._linkCounter + 1
        name := "ThankContributor_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        avatar := image == "" ? '<Border Width="30" Height="30" CornerRadius="15" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><TextBlock Text="' this._XmlEsc(initial) '" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>' : '<Ellipse Width="30" Height="30" Stroke="{DynamicResource OutlineStroke}" StrokeThickness="1"><Ellipse.Fill><ImageBrush ImageSource="' image '" Stretch="UniformToFill"/></Ellipse.Fill></Ellipse>'
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Margin="' margin '" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><Button Name="' name '" Cursor="Hand" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch">' this._ThankSoftHoverTemplate() '<Grid Margin="9,7"><Grid.ColumnDefinitions><ColumnDefinition Width="37"/><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/></Grid.ColumnDefinitions>' avatar '<StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="' this._XmlEsc(title) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(GetLang("项目贡献者")) '" FontSize="9" Foreground="{DynamicResource TextSub}" Margin="0,2,0,0"/></StackPanel><TextBlock Grid.Column="2" Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid></Button></Border>'
    }

    _ThankProject(row, col, glyph, title, description, url, margin) {
        this._linkCounter := this._linkCounter + 1
        name := "ThankProject_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Margin="' margin '" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><Button Name="' name '" Cursor="Hand" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch">' this._ThankSoftHoverTemplate() '<Grid Margin="10,8"><Grid.ColumnDefinitions><ColumnDefinition Width="36"/><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/></Grid.ColumnDefinitions><Border Width="28" Height="28" CornerRadius="6" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="' this._XmlEsc(title) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(GetLang(description)) '" TextWrapping="Wrap" FontSize="9" Foreground="{DynamicResource TextSub}" Margin="0,2,0,0"/></StackPanel><TextBlock Grid.Column="2" Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid></Button></Border>'
    }

    _ThankInfoBlock(glyph, text, margin := "0") {
        return '<Border Margin="' margin '" Padding="10" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" VerticalAlignment="Top"/><TextBlock Grid.Column="1" Text="' this._XmlEsc(text) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource TextMain}"/></Grid></Border>'
    }

    _ThankNickname(text) {
        return '<Border Margin="0,0,7,7" Padding="8,4" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><TextBlock Text="' this._XmlEsc(text) '" FontSize="10" Foreground="{DynamicResource TextMain}"/></Border>'
    }

    _GetBuiltInThankAvatar(id) {
        static paths := Map()
        if (paths.Has(id))
            return paths[id]
        switch id {
            case "yun":
                tempPath := A_Temp "\RMT_Thank_yun.jpg"
                FileInstall("Web\assets\thank-avatars\yun.jpg", tempPath, 1)
            case "boxstudy":
                tempPath := A_Temp "\RMT_Thank_boxstudy.jpg"
                FileInstall("Web\assets\thank-avatars\boxstudy.jpg", tempPath, 1)
            case "sovaedv776":
                tempPath := A_Temp "\RMT_Thank_sovaedv776.png"
                FileInstall("Web\assets\thank-avatars\sovaedv776.png", tempPath, 1)
            case "gushulily":
                tempPath := A_Temp "\RMT_Thank_gushulily.jpg"
                FileInstall("Web\assets\thank-avatars\gushulily.jpg", tempPath, 1)
            case "t8numen":
                tempPath := A_Temp "\RMT_Thank_t8numen.jpg"
                FileInstall("Web\assets\thank-avatars\t8numen.jpg", tempPath, 1)
            default:
                return ""
        }
        paths[id] := StrReplace(tempPath, "\", "/")
        return paths[id]
    }

    _FlushLinks() {
        for item in this._linkQueue
            this._Bind(item.name, item.HasOwnProp("event") ? item.event : "MouseLeftButtonUp", ObjBindMethod(this, "OnLinkClick", item.url))
        this._linkQueue := []
    }
}

global MyMainWin := MainWin()
