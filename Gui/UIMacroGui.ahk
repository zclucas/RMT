#Requires AutoHotkey v2.0

class UIMacroGui {
    static STATE_DEFAULT := 0    ; 默认/空闲（隐藏色块）
    static STATE_RUNNING := 1    ; 运行中（绿色）
    static STATE_PAUSED := 2     ; 暂停中（黄色）
    static STATE_STOPPED := 3    ; 停止/终止（红色，5秒后自动恢复）

    __new() {
        this.PanelMap := Map()       ; foldIndex -> panelInfo
        this.PanelTimers := Map()     ; foldIndex -> FuncObj（SetTimer回调引用）
        this.IsCreating := false
        this.MonitorTimer := ""
        this.RunningMap := Map()
        this.RecoverTimers := Map()
        this._lastActiveHwnd := 0       ; 上次检测的前台窗口 hwnd
        ; 用户主动关闭（右键关闭/Alt+F4/热键隐藏）后禁止「激活时默认显示」重建，直到热键再开
        this.UserClosedKeys := Map()
        this.StartMonitor()
    }

    MarkUserClosed(panelKey) {
        this.UserClosedKeys[panelKey] := true
    }

    ClearUserClosed(panelKey) {
        if (this.UserClosedKeys.Has(panelKey))
            this.UserClosedKeys.Delete(panelKey)
    }

    IsUserClosed(panelKey) {
        return this.UserClosedKeys.Has(panelKey) && this.UserClosedKeys[panelKey]
    }

    StartMonitor() {
        if (this.MonitorTimer != "")
            return
        this.MonitorTimer := this.CheckAllPanels.Bind(this)
        SetTimer this.MonitorTimer, 200
    }

    StopMonitor() {
        if (this.MonitorTimer != "") {
            SetTimer this.MonitorTimer, 0
            this.MonitorTimer := ""
        }
        for foldIndex in this.PanelTimers.Clone() {
            this.StopFollowTimer(foldIndex)
        }
        this.HideAllPanels()
        for macroIndex in this.RunningMap {
            this.StopMacro(macroIndex)
        }
        for macroIndex in this.RecoverTimers {
            this.CancelRecoverTimer(macroIndex)
        }
    }

    ; ========== 面板管理（严格对齐 floating_panel.ahk） ==========

    ; 获取界面宏表 + 折叠框 + 折叠框内条目（统一入口，避免各处重复 TableInfo[4]/IndexSpan）
    _GetFoldContext(foldIndex) {
        tableItem := GetTableBySymbol("UI")
        if (!tableItem)
            return ""
        fold := tableItem.Folds[foldIndex]
        if (!fold)
            return ""
        return { tableItem: tableItem, fold: fold, items: GetFoldItems(tableItem, fold) }
    }

    ; 创建面板入口（对齐 CreateFloatingPanel L182-265）
    CreatePanel(foldIndex) {
        ctx := this._GetFoldContext(foldIndex)
        if (!ctx || ctx.items.Length == 0)
            return
        tableItem := ctx.tableItem
        fold := ctx.fold

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        btnItems := []
        for i, item in ctx.items {
            if (item.Forbid)
                continue

            remarkValue := item.Remark
            iconValue := item.IcoPath
            btnText := remarkValue == "" ? GetLang("操作") i : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

            macroIndex := GetItemIndexInTable(tableItem, item.ID)
            btnItems.Push({
                name: "Btn_" macroIndex,
                text: btnText,
                icon: displayIcon,
                macroIndex: macroIndex
            })
        }

        if (btnItems.Length == 0)
            return

        ; 解析目标窗口（对齐 floating_panel 的 targetB_Hwnd）
        frontInfo := fold.FrontInfo
        targetHwnd := 0
        isScreenMode := true

        if (frontInfo != "") {
            targetHwnd := this.ResolveTargetHwnd(frontInfo)
            if (targetHwnd)
                isScreenMode := false
        }

        if (!isScreenMode && targetHwnd) {
            if (!DllCall("user32\IsWindow", "Ptr", targetHwnd))
                return
            ; 前台激活检查：目标窗口必须在前台才允许创建面板
            activeHwnd := WinGetID("A")
            if (activeHwnd != targetHwnd)
                return
        }

        ; 构建面板（对齐 CreateFloatingPanel）
        ; 创建期间置位 IsCreating：BuildXAMLPanel/WaitForPanelReady 内的 Sleep 会泵消息，
        ; 导致 CheckAllPanels 重入；此时 PanelMap 尚未写入，自动显示会再建一个重复面板。
        this.IsCreating := true
        try {
            panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode)
            if (!panelInfo)
                return

            this.PanelMap.Set(foldIndex, panelInfo)

            ; 等待窗口就绪+初始化（对齐 WaitForHwnd + OnPanelReady）
            this.WaitForPanelReady(foldIndex)
        } finally {
            this.IsCreating := false
        }
    }

    ; 为指定 hwnd 创建自动面板（界面激活时默认显示），键为 foldIndex|hwnd；targetHwnd=0 时创建屏幕模式面板
    CreateAutoPanel(foldIndex, panelKey, targetHwnd) {
        if (this.PanelMap.Has(panelKey))
            return
        ; 用户曾主动关闭：不要因点击主界面/切换前台而自动重建
        if (this.IsUserClosed(panelKey))
            return

        ctx := this._GetFoldContext(foldIndex)
        if (!ctx || ctx.items.Length == 0)
            return
        tableItem := ctx.tableItem
        fold := ctx.fold

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        btnItems := []
        for i, item in ctx.items {
            if (item.Forbid)
                continue

            remarkValue := item.Remark
            iconValue := item.IcoPath
            btnText := remarkValue == "" ? GetLang("操作") i : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

            macroIndex := GetItemIndexInTable(tableItem, item.ID)
            btnItems.Push({
                name: "Btn_" macroIndex,
                text: btnText,
                icon: displayIcon,
                macroIndex: macroIndex
            })
        }

        if (btnItems.Length == 0)
            return

        ; 自动面板：有目标窗口则窗口跟随模式，否则屏幕模式
        isScreenMode := (targetHwnd == 0)
        ; 创建期间置位 IsCreating，防止 Sleep 泵消息时 CheckAllPanels 重入造成重复面板
        this.IsCreating := true
        try {
            panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode, true)
            if (!panelInfo)
                return

            panelInfo.autoShow := true  ; 标记为自动面板
            this.PanelMap.Set(panelKey, panelInfo)
            this.WaitForPanelReady(panelKey)
        } finally {
            this.IsCreating := false
        }

        ; 确保面板在目标窗口之上（不抢焦点）
        if (IsObject(panelInfo) && panelInfo.wpfHwnd) {
            DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0  ; HWND_TOP
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0001 | 0x0002 | 0x0010)  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
        }
    }

    ; 显示自动面板（不抢焦点，不激活）
    ShowAutoPanel(panelKey) {
        panelInfo := this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
        if (!panelInfo || !panelInfo.wpfHwnd)
            return

        ; 如果已被使用者手動關閉，則不進行自動顯示
        if (this.IsUserClosed(panelKey) || (panelInfo.HasProp("userClosed") && panelInfo.userClosed))
            return

        ; 配置变化检测：按钮尺寸/列数/颜色变化 → 销毁重建
        if (panelInfo._cfg_BtnHeight != MainSoftData.UIPanelBtnHeight
            || panelInfo._cfg_BtnWidth != MainSoftData.UIPanelBtnWidth
            || panelInfo._cfg_Cols != MainSoftData.UIPanelCols
            || panelInfo._cfg_FontSize != MainSoftData.UIPanelFontSize
            || panelInfo._cfg_BtnColor != MainSoftData.UIPanelBtnColor
            || panelInfo._cfg_BtnText != MainSoftData.UIPanelBtnText
            || panelInfo._cfg_BgColor != MainSoftData.UIPanelBgColor
            || panelInfo._cfg_TitleBg != MainSoftData.UIPanelTitleBg
            || panelInfo._cfg_TitleText != MainSoftData.UIPanelTitleText) {
            parts := StrSplit(panelKey, "|")
            foldIndex := Integer(parts[1])
            targetHwnd := (parts.Length >= 2) ? Integer(parts[2]) : 0
            this.DestroyPanel(panelKey)
            this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
            return
        }

        try {
            DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 8)  ; SW_SHOWNA
            ; 不调用 ApplyPanelPosition——保持用户拖拽后的位置，跟随定时器会处理定位
            ; 提升到目标窗口之上（不抢焦点）
            DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0  ; HWND_TOP
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0001 | 0x0002 | 0x0010)  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
            panelInfo.visible := true
        }
    }

    ; 构建XAML面板（对齐 CreateFloatingPanel L182-264）
    BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode, skipActivate := false) {
        titleBarH := 26
        btnItemH := MainSoftData.UIPanelBtnHeight
        btnItemW := MainSoftData.UIPanelBtnWidth
        btnGap := 2
        bodyMarginV := 6
        cols := MainSoftData.UIPanelCols
        wpfBorderPad := 2
        ; 面板宽度 = 列数 * 按钮宽度 + 按钮左右边距(各2px) + 主体左右边距(各4px)
        pw := cols * (btnItemW + 4) + 8

        btnColor := MainSoftData.UIPanelBtnColor
        btnTextColor := MainSoftData.UIPanelBtnText
        bgColor := MainSoftData.UIPanelBgColor
        titleBg := MainSoftData.UIPanelTitleBg
        titleText := MainSoftData.UIPanelTitleText
        fontSize := Integer(MainSoftData.UIPanelFontSize)

        tableItem := GetTableBySymbol("UI")
        fold := tableItem ? tableItem.Folds[foldIndex] : ""
        foldRemark := fold ? fold.Remark : ""

        rows := Ceil(btnItems.Length / cols)
        contentH := rows * btnItemH + (rows - 1) * btnGap + bodyMarginV
        ph := titleBarH + contentH + wpfBorderPad

        ; 根据配置的「出现位置」计算初始坐标（锚点）。
        ; 锚定容器：屏幕模式 → 整个屏幕；窗口跟随模式 → 目标窗口（窗口化时的窗口矩形）。
        ; 注：XAML 的 Window.Left/Top 使用 DIP（设备无关像素），A_ScreenWidth/GetWindowRect 返回物理像素，
        ;     屏幕模式按 A_ScreenDPI 换算为 DIP；窗口跟随模式保持物理坐标与 SetWindowPos 跟随逻辑一致。
        initX := 0, initY := 0
        baseLeft := 0, baseTop := 0
        if (isScreenMode) {
            swDIP := A_ScreenWidth * 96 // A_ScreenDPI
            shDIP := A_ScreenHeight * 96 // A_ScreenDPI
            this.CalcDefaultPosition(MainSoftData.UIPanelDefaultPos, &initX, &initY, pw, ph, swDIP, shDIP)
        } else {
            contW := 0, contH := 0
            if (targetHwnd) {
                try {
                    rect := this.GetWindowRectCoords(targetHwnd)
                    contW := rect["right"] - rect["left"]
                    contH := rect["bottom"] - rect["top"]
                    baseLeft := rect["left"]
                    baseTop := rect["top"]
                }
            }
            if (contW <= 0)
                contW := A_ScreenWidth
            if (contH <= 0)
                contH := A_ScreenHeight
            this.CalcDefaultPosition(MainSoftData.UIPanelDefaultPos, &initX, &initY, pw, ph, contW, contH)
            initX += baseLeft
            initY += baseTop
        }
        ; 配置的位置偏移（相对锚点基准）。窗口跟随模式下此偏移作为「固定偏移量」保存，
        ; 锚点基准由 FollowSinglePanel 按目标窗口当前尺寸实时计算，从而窗口缩放时也能正确重新锚定。
        cfgOffX := Integer(MainSoftData.UIPanelOffsetX)
        cfgOffY := Integer(MainSoftData.UIPanelOffsetY)
        initX += cfgOffX
        initY += cfgOffY
        offsetX := cfgOffX
        offsetY := cfgOffY

        ; 构建XAML（与 floating_panel L213-233 完全一致的结构）
        main := XAML_Generator("Grid")
        main.Background(bgColor)
        main.Rows(titleBarH, "*")

        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background(titleBg)
        titleBar.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground(titleText).FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")

        body := main.Add("Grid").Grid_Row(1).Name("BodyPanel").Margin("2,1,2,2")
        textMaxW := Max(btnItemW - 8, 24)

        ; 按钮样式挂在控件本地，避免无 x:Key 的 Style 进 Window.Resources 后被同步到
        ; Application.Current，关闭浮窗后污染其它 XAML 窗口
        panelBtnStyle := '<Style TargetType="Button"><Setter Property="BorderThickness" Value="1"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Arrow"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="1,0"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#FF0A84FF"/><Setter TargetName="Bd" Property="BorderThickness" Value="1"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#FF0A84FF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        ; 列定义：根据按钮宽度显式设置
        colDefs := body.Add("Grid.ColumnDefinitions")
        loop cols
            colDefs.Add("ColumnDefinition").Width(btnItemW)

        ; 行定义：每行固定高度
        rowDefs := body.Add("Grid.RowDefinitions")
        loop rows
            rowDefs.Add("RowDefinition").Height(btnItemH)

        for i, item in btnItems {
            row := Floor((i - 1) / cols)
            col := Mod(i - 1, cols)
            isLastRow := (row = rows - 1)
            marginBottom := isLastRow ? "0" : btnGap
            marginStr := "1,0,1," marginBottom

            btn := body.Add("Button").Name(item.name).Height(btnItemH)
                .Grid_Row(row).Grid_Column(col)
                .Margin(marginStr)
            btn.Background(btnColor).Foreground(btnTextColor).FontSize(fontSize)
            btn.HorizontalAlignment("Stretch")
            btn.Padding("0")
            btn.InjectResources(panelBtnStyle)

            sp := btn.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
                .VerticalAlignment("Center")

            ; 运行状态色点（默认隐藏）
            sp.Add("Ellipse").Name(item.name "_State")
                .Width(8).Height(8).VerticalAlignment("Center").Margin("0,0,2,0")
                .Visibility("Collapsed").IsHitTestVisible("False")

            if (item.icon != "") {
                fullIconPath := this.GetFullIconPath(item.icon)
                if (fullIconPath != "" && FileExist(fullIconPath)) {
                    sp.Add("Image").Name(item.name "_Img")
                        .Source(fullIconPath).Width(14).Height(14).VerticalAlignment("Center").Margin("0,0,2,0")
                }
            }

            sp.Add("TextBlock").Text(item.text).VerticalAlignment("Center").Foreground(btnTextColor).FontSize(fontSize)
                .TextTrimming("CharacterEllipsis").MaxWidth(String(textMaxW))
        }

        ; XAML字符串处理（对齐 floating_panel L235-244）
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" ShowInTaskbar="False" Width="' pw '" Height="' ph '"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
        ui.xaml := StrReplace(ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
        ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="' bgColor '"')

        ui.xaml := StrReplace(ui.xaml, '%resources%', '<CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>')
        ui.xaml := StrReplace(ui.xaml, '%components%', '')

        ; 绑定事件（对齐 floating_panel L246-249）
        for i, item in btnItems {
            ui.OnEvent(item.name, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnBtnClick", item.macroIndex, foldIndex))
        }

        ; 显示窗口（对齐 floating_panel L254）
        ui.Show()

        ; 等待wpfHwnd就绪（对齐 floating_panel L256-262）
        loop 20 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
                if !skipActivate
                    WinActivate("ahk_id " ui.wpfHwnd)
                break
            }
            Sleep(50)
        }

        ; 返回面板信息（对齐 floating_panel 全局变量初始化 L207-L211, L251-L252）
        return {
            ui: ui,
            wpfHwnd: ui.wpfHwnd ? ui.wpfHwnd : 0,
            foldIndex: foldIndex,
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            frontInfo: fold ? fold.FrontInfo : "",
            visible: true,
            btnItems: btnItems,
            anchorPos: MainSoftData.UIPanelDefaultPos,
            offsetX: offsetX,
            offsetY: offsetY,
            lastSetX: "",
            lastSetY: "",
            panelReady: false,
            ; 配置快照：用于检测面板显示时配置是否变化
            _cfg_BtnHeight: btnItemH,
            _cfg_BtnWidth: btnItemW,
            _cfg_Cols: cols,
            _cfg_FontSize: fontSize,
            _cfg_BtnColor: btnColor,
            _cfg_BtnText: btnTextColor,
            _cfg_BgColor: bgColor,
            _cfg_TitleBg: titleBg,
            _cfg_TitleText: titleText
        }
    }

    ; 等待窗口就绪并执行初始化（= floating_panel WaitForHwnd L352-361 + OnPanelReady L363-389）
    WaitForPanelReady(foldIndex) {
        panelInfo := this.PanelMap.Has(foldIndex) ? this.PanelMap[foldIndex] : ""
        if (!panelInfo)
            return

        ; 对齐 WaitForHwnd L352-361：循环等待wpfHwnd
        loop 50 {
            if (panelInfo.ui && panelInfo.ui.HasProp("wpfHwnd") && panelInfo.ui.wpfHwnd) {
                ; 对齐 L355: g_panelReady := true
                panelInfo.panelReady := true
                ; 对齐 L356: OnPanelReady()
                this.OnPanelReady(foldIndex)
                return
            }
            Sleep(50)
        }
    }

    ; 面板就绪后的初始化（严格对齐 floating_panel OnPanelReady L363-389）
    OnPanelReady(foldIndex) {
        panelInfo := this.PanelMap.Has(foldIndex) ? this.PanelMap[foldIndex] : ""
        if (!panelInfo)
            return

        ; L364-L366: 设置 NativeOwner
        if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
            try panelInfo.ui.Update("Window", "NativeOwner", String(panelInfo.targetHwnd))
        }

        ; L373-L375: 设置窗口扩展样式 + 精简系统菜单（保留关闭，供标题栏右键）
        hwnd := panelInfo.wpfHwnd
        if (hwnd) {
            exStyle := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
            DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int"
                , exStyle | 0x80)
            ; 精简系统菜单项，保留 SC_CLOSE / SC_MOVE；置顶时菜单层级由引擎 SysMenu 事件配合处理
            hSysMenu := DllCall("user32\GetSystemMenu", "Ptr", hwnd, "Int", 0, "Ptr")
            if (hSysMenu) {
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF020, "UInt", 0)  ; SC_MINIMIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF000, "UInt", 0)  ; SC_SIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF030, "UInt", 0)  ; SC_MAXIMIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF120, "UInt", 0)  ; SC_RESTORE
            }
            ; 系统菜单打开期间暂停 AHK 侧反复 WinSetAlwaysOnTop，避免把菜单重新压到下面
            try panelInfo.ui.OnEvent("Window", "SysMenu", ObjBindMethod(this, "OnPanelSysMenu", foldIndex))
        }

        ; L377-L384: 模式分支初始化
        if (panelInfo.isScreenMode) {
            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        } else {
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0002 | 0x0001 | 0x0004 | 0x0010 | 0x0020)
        }

        ; L387: 立即执行一次跟随
        this.FollowSinglePanel(foldIndex)

        ; L388: 启动定时器
        this.StartFollowTimer(foldIndex)
    }

    ; 跟随逻辑（严格逐行对齐 floating_panel FollowTarget L391-440 + MovePanel L171-179）
    FollowSinglePanel(foldIndex) {
        if (!this.PanelMap.Has(foldIndex))
            return

        panelInfo := this.PanelMap[foldIndex]

        ; L392: if (!g_panelReady) return
        if (!panelInfo.panelReady)
            return

        ; L394-L396: 获取hwnd并验证
        hwnd := panelInfo.wpfHwnd
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
            return

        ; L398-L409: 屏幕模式分支（系统菜单打开时勿反复置顶，否则菜单会被压到浮窗下方）
        if (panelInfo.isScreenMode) {
            if (!(panelInfo.HasProp("_suspendTopmost") && panelInfo._suspendTopmost))
                try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
            return
        }

        ; L411-L416: 目标窗口检查
        if (!panelInfo.targetHwnd)
            return
        if (!DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
            this.DestroyPanel(foldIndex)
            return
        }

        ; ====== 目标窗口矩形 + 面板尺寸 ======
        rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
        winW := rect["right"] - rect["left"]
        winH := rect["bottom"] - rect["top"]
        panelRect := this.GetWindowRectCoords(hwnd)
        pw := panelRect["right"] - panelRect["left"]
        ph := panelRect["bottom"] - panelRect["top"]
        if (winW <= 0)
            winW := A_ScreenWidth
        if (winH <= 0)
            winH := A_ScreenHeight
        if (pw <= 0)
            pw := 250
        if (ph <= 0)
            ph := 200

        ; ====== 锚点基准（相对目标窗口左上角） ======
        ; 依据窗口当前尺寸实时计算，窗口缩放时中心/右上/右下等锚点会随新尺寸重新定位
        anchorX := 0, anchorY := 0
        anchorPos := panelInfo.HasProp("anchorPos") ? panelInfo.anchorPos : 1
        this.CalcDefaultPosition(anchorPos, &anchorX, &anchorY, pw, ph, winW, winH)

        ; ====== 位置变化检测（替代三阶段拖拽检测） ======
        ; 原理：记录我们上次 SetWindowPos 设到的位置(lastSetX/Y)。
        ;   - 如果实际位置 == lastSetX/Y → 没有外部干扰 → 正常跟随
        ;   - 如果实际位置 != lastSetX/Y → 有外部力量移动了面板(用户拖拽等)
        ;     → 把「实际位置相对锚点基准」的差值写回 offset → 之后用新 offset 跟随
        if (panelInfo.lastSetX != "" && panelInfo.lastSetY != "") {
            devX := Abs(panelRect["left"] - panelInfo.lastSetX)
            devY := Abs(panelRect["top"] - panelInfo.lastSetY)
            if (devX > 3 || devY > 3) {
                panelInfo.offsetX := panelRect["left"] - rect["left"] - anchorX
                panelInfo.offsetY := panelRect["top"] - rect["top"] - anchorY
            }
        }

        ; 阶段3 — 正常跟随移动（窗口移动/缩放都会使锚点基准变化而正确跟随）
        newX := rect["left"] + anchorX + panelInfo.offsetX
        newY := rect["top"] + anchorY + panelInfo.offsetY
        ownerHwnd := panelInfo.targetHwnd
        DllCall("user32\SetWindowPos"
            , "Ptr", hwnd
            , "Ptr", ownerHwnd
            , "Int", newX, "Int", newY
            , "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010 | 0x4000)
        ; 记录本次设置的目标位置，供下次回调对比
        panelInfo.lastSetX := newX
        panelInfo.lastSetY := newY
    }

    ; 切换可见性（严格对齐 floating_panel TogglePanelVisibility L490-513）
    TogglePanel(foldIndex) {
        ; 创建进行中：忽略本次触发，避免在 PanelMap 写入前重入创建出重复面板
        if (this.IsCreating)
            return

        tableItem := GetTableBySymbol("UI")
        ; 每次触发实时读取，避免编辑前台后仍用旧判断
        frontInfo := ""
        if (tableItem) {
            fold := tableItem.Folds[foldIndex]
            if (fold)
                frontInfo := fold.FrontInfo
        }

        targetHwnd := 0
        panelKey := foldIndex

        ; ====== 前置守卫：有前台信息时，以鼠标所在窗口为准（不用焦点窗口） ======
        ; 与按键宏 TriggerKeyData / TimingUtil 一致，走 MyMouseInfo.CheckIfMatch
        if (frontInfo != "") {
            if (MyMouseInfo.CheckIfMatch(frontInfo, true)) {
                ; 鼠标在对应前台窗口上 → 允许开关该实例
                targetHwnd := Integer(MyMouseInfo.WinId)
                panelKey := foldIndex "|" targetHwnd
            } else {
                ; 鼠标在本模块浮窗上：仅当该浮窗绑定的目标仍匹配当前前台信息时允许
                ; （方便在按钮上按触发键隐藏；目标已不符则视为非对应前台，无效）
                mouseHwnd := MyMouseInfo.HasError ? 0 : Integer(MyMouseInfo.WinId)
                matched := false
                if (mouseHwnd) {
                    for key, panelInfo in this.PanelMap {
                        if (panelInfo.foldIndex != foldIndex || panelInfo.wpfHwnd != mouseHwnd)
                            continue
                        if (panelInfo.targetHwnd && this.IsHwndMatchFrontInfo(panelInfo.targetHwnd, frontInfo)) {
                            targetHwnd := panelInfo.targetHwnd
                            panelKey := key
                            matched := true
                        }
                        break
                    }
                }
                if (!matched)
                    return
            }
        }

        if (!this.PanelMap.Has(panelKey)) {
            this.ClearUserClosed(panelKey)  ; 热键主动打开：清除「用户关闭」标记
            if (targetHwnd)
                this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
            else
                this.CreatePanel(foldIndex)
            return
        }

        panelInfo := this.PanelMap[panelKey]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return

        ; 配置变化检测：按钮尺寸/列数/颜色变化时销毁重建
        if (panelInfo.visible == false  ; 只在从隐藏→显示时检查
            && (panelInfo._cfg_BtnHeight != MainSoftData.UIPanelBtnHeight
                || panelInfo._cfg_BtnWidth != MainSoftData.UIPanelBtnWidth
                || panelInfo._cfg_Cols != MainSoftData.UIPanelCols
                || panelInfo._cfg_FontSize != MainSoftData.UIPanelFontSize
                || panelInfo._cfg_BtnColor != MainSoftData.UIPanelBtnColor
                || panelInfo._cfg_BtnText != MainSoftData.UIPanelBtnText
                || panelInfo._cfg_BgColor != MainSoftData.UIPanelBgColor
                || panelInfo._cfg_TitleBg != MainSoftData.UIPanelTitleBg
                || panelInfo._cfg_TitleText != MainSoftData.UIPanelTitleText)) {
            this.ClearUserClosed(panelKey)
            this.DestroyPanel(panelKey)
            if (targetHwnd)
                this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
            else
                this.CreatePanel(foldIndex)
            return
        }

        ; 切换可见性
        panelInfo.visible := !panelInfo.visible
        hwnd := panelInfo.wpfHwnd
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
            return

        if (panelInfo.visible) {
            panelInfo.userClosed := false
            this.ClearUserClosed(panelKey)
            ; SW_SHOWNA：显示但不抢焦点，保持鼠标下仍是目标窗，下次触发判断更稳定
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 8)
            this.ApplyPanelPosition(panelInfo)
            ; 重新显示后重置固定偏移为配置偏移（清除用户拖拽增量）；锚点基准由跟随逻辑按窗口尺寸实时计算
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                panelInfo.offsetX := Integer(MainSoftData.UIPanelOffsetX)
                panelInfo.offsetY := Integer(MainSoftData.UIPanelOffsetY)
            }
        } else {
            panelInfo.userClosed := true
            this.MarkUserClosed(panelKey)
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 0)
        }
    }

    ; 引擎通知：标题栏系统菜单打开/关闭（暂停/恢复 AlwaysOnTop 重刷）
    ; 回调参数：(stateMap, "Window", "SysMenu")，Open/Close 在 stateMap["SysMenu"]
    OnPanelSysMenu(panelKey, state := unset, ctrl := unset, event := unset) {
        if (!this.PanelMap.Has(panelKey))
            return
        panelInfo := this.PanelMap[panelKey]
        isOpen := false
        if (IsSet(state) && IsObject(state) && state.Has("SysMenu"))
            isOpen := (state["SysMenu"] = "Open")
        panelInfo._suspendTopmost := isOpen
        if (!isOpen && panelInfo.isScreenMode && panelInfo.visible && panelInfo.wpfHwnd)
            try WinSetAlwaysOnTop(1, "ahk_id " panelInfo.wpfHwnd)
    }

    ; 销毁指定模块的全部面板（前台信息变更时清理旧目标实例）
    DestroyFoldPanels(foldIndex) {
        keys := []
        for key, panelInfo in this.PanelMap {
            if (panelInfo.foldIndex == foldIndex)
                keys.Push(key)
        }
        for key in keys
            this.DestroyPanel(key)
    }

    ; 销毁面板（严格对齐 floating_panel ClosePanel L515-523）
    DestroyPanel(foldIndex) {
        if (!this.PanelMap.Has(foldIndex))
            return

        ; L517: 停止定时器（对齐 SetTimer(FollowTarget, 0)）
        this.StopFollowTimer(foldIndex)

        panelInfo := this.PanelMap[foldIndex]
        ; L518-L520: 关闭窗口
        if (panelInfo.ui) {
            try panelInfo.ui.Update("Window", "Close", "")
        }
        ; L521-L522: 清理
        if (this.PanelMap.Has(foldIndex))
            this.PanelMap.Delete(foldIndex)
    }

    ; 屏幕模式面板的定期检查（对齐 FollowTarget 中 L398-L409 的screenMode分支）
    CheckAllPanels() {
        deadFolds := []
        for panelKey, panelInfo in this.PanelMap {
            ; 非屏幕模式面板：目标窗口已关闭则自动销毁
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd
                && !DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
                deadFolds.Push(panelKey)
                continue
            }
            ; 面板窗口已失效（被关闭）：视为用户主动关闭，禁止随后点主界面自动重建
            if (!panelInfo.ui || !panelInfo.wpfHwnd || !WinExist("ahk_id " panelInfo.wpfHwnd)) {
                this.MarkUserClosed(panelKey)
                deadFolds.Push(panelKey)
                continue
            }

            ; 處理目標視窗隱藏/退到後台時，浮窗隱藏；重新顯現時浮窗也重新顯現
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                ; 檢查目標視窗是否最小化 (WinGetMinMax 傳回 -1 代表最小化) 或不可見
                try {
                    isMin := WinGetMinMax("ahk_id " panelInfo.targetHwnd) == -1
                    targetVisible := !isMin && DllCall("user32\IsWindowVisible", "Ptr", panelInfo.targetHwnd)
                } catch {
                    targetVisible := false
                }
                
                if (!targetVisible && panelInfo.visible) {
                    panelInfo.visible := false
                    panelInfo.targetWasHidden := true
                    DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 0) ; SW_HIDE
                } else if (targetVisible && !panelInfo.visible && (panelInfo.HasProp("targetWasHidden") && panelInfo.targetWasHidden)) {
                    panelInfo.visible := true
                    panelInfo.targetWasHidden := false
                    DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 8) ; SW_SHOWNA
                    this.ApplyPanelPosition(panelInfo)
                }
            }

            if (!panelInfo.isScreenMode)
                continue
            if (!panelInfo.visible)
                continue

            hwnd := panelInfo.wpfHwnd
            if (!(panelInfo.HasProp("_suspendTopmost") && panelInfo._suspendTopmost))
                WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        }
        ; 清理已关闭的面板残留条目（DestroyPanel 会关闭窗口 + 停止定时器）
        for panelKey in deadFolds {
            this.DestroyPanel(panelKey)
        }

        ; 用户主动关闭浮窗（右键关闭 / Alt+F4）会引起焦点切换，若不处理，下面的"激活时默认显示"
        ; 会把这次焦点变化当成窗口切换而立即重建面板。这里把 _lastActiveHwnd 同步为关闭后的
        ; 当前前台窗口，使其不立即重建，等到下次真正切换窗口时再显示 —— 与快捷键隐藏的行为一致。
        if (deadFolds.Length > 0) {
            try this._lastActiveHwnd := WinGetID("A")
        }

        ; ====== 界面激活时默认显示（同时支持有前台和无前台模块） ======
        try {
            ; 正在创建面板时跳过：避免创建过程中（BuildXAMLPanel 的 Sleep 泵消息）重入建出重复面板
            if (!this.IsCreating && MainSoftData.UIPanelShowOnActive) {
                activeHwnd := WinGetID("A")
                if (activeHwnd != this._lastActiveHwnd) {
                    this._lastActiveHwnd := activeHwnd

                    tableItem := GetTableBySymbol("UI")
                    if (tableItem) {
                        for foldIndex, fold in tableItem.Folds {
                            if (fold.ForbidState)
                                continue

                            frontInfo := fold.FrontInfo
                            if (frontInfo == "") {
                                ; 无前台模块（屏幕模式）：仅当 RMT 主界面被激活时才创建/显示，
                                ; 避免点击任务栏或切到其它任意窗口也把已关闭的浮窗重新弹出。
                                mainHwnd := (IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.HasProp("Hwnd")) ? MainSoftData.MyGui.Hwnd : 0
                                if (!mainHwnd || activeHwnd != mainHwnd)
                                    continue
                                panelKey := foldIndex
                                if (this.IsUserClosed(panelKey))
                                    continue
                                if (!this.PanelMap.Has(panelKey))
                                    this.CreateAutoPanel(foldIndex, panelKey, 0)
                                else
                                    this.ShowAutoPanel(panelKey)
                            } else if (activeHwnd && this.IsHwndMatchFrontInfo(activeHwnd, frontInfo)) {
                                ; 有前台模块：面板键为 foldIndex|hwnd（每个窗口实例独立面板）
                                panelKey := foldIndex "|" activeHwnd
                                if (this.IsUserClosed(panelKey))
                                    continue
                                if (!this.PanelMap.Has(panelKey))
                                    this.CreateAutoPanel(foldIndex, panelKey, activeHwnd)
                                else
                                    this.ShowAutoPanel(panelKey)
                            }
                        }
                    }
                }
            }
        } catch {
        }
    }

    ; 启动跟随定时器（对齐 floating_panel L388: SetTimer(FollowTarget, 50)）
    StartFollowTimer(foldIndex) {
        if (this.PanelTimers.Has(foldIndex)) {
            oldCb := this.PanelTimers[foldIndex]
            if (oldCb)
                SetTimer(oldCb, 0)
        }
        cb := this.FollowSinglePanel.Bind(this, foldIndex)
        this.PanelTimers[foldIndex] := cb
        SetTimer(cb, 50)
    }

    ; 停止跟随定时器（对齐 floating_panel L517: SetTimer(FollowTarget, 0)）
    StopFollowTimer(foldIndex) {
        if (!this.PanelTimers.Has(foldIndex))
            return
        cb := this.PanelTimers[foldIndex]
        if (cb)
            SetTimer(cb, 0)
        this.PanelTimers.Delete(foldIndex)
    }

    ; ========== 宏执行逻辑 ==========

    ; ObjBindMethod 转发器（ObjBindMethod 固定参数值，避免闭包捕获循环变量的引用问题）
    _OnBtnClick(macroIndex, foldIndex, *) {
        this.OnButtonClick(macroIndex, foldIndex)
    }

    OnButtonClick(macroIndex, foldIndex, *) {
        try {
            tableItem := GetTableBySymbol("UI")
            item := tableItem ? tableItem.Items[macroIndex] : ""
            if (!item || item.Forbid)
                return

            if (!item.Macro)
                return

            if (this.IsMacroRunning(macroIndex)) {
                this.StopMacro(macroIndex)
            } else {
                this.StartMacro(macroIndex)
            }

            ; 点击后面板抢走了焦点 → 立即将焦点还给目标窗口
            this.RestoreTargetFocus(macroIndex, foldIndex)
        }
        catch as e {
        }
    }

    ; 恢复目标窗口的前台状态（点击面板按钮后调用）
    RestoreTargetFocus(macroIndex, foldIndex) {
        ; 先找 foldIndex 匹配且 wpfHwnd 是当前前台的面板（点击的 panel）
        activeHwnd := WinGetID("A")
        for panelKey, panelInfo in this.PanelMap {
            if (panelInfo.foldIndex != foldIndex || !panelInfo.targetHwnd)
                continue
            ; 当前前台窗口正好是这个 panel 的 wpfHwnd → 被点击的 panel
            if (panelInfo.wpfHwnd == activeHwnd) {
                if (DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd))
                    WinActivate("ahk_id " panelInfo.targetHwnd)
                return
            }
        }
        ; 回退：激活任意匹配的面板的目标窗口
        for panelKey, panelInfo in this.PanelMap {
            if (panelInfo.foldIndex == foldIndex && panelInfo.targetHwnd) {
                if (DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd))
                    WinActivate("ahk_id " panelInfo.targetHwnd)
                return
            }
        }
    }

    IsMacroRunning(macroIndex) {
        return (this.RunningMap.Has(macroIndex)
            && this.RunningMap[macroIndex].IsRunning)
    }

    StartMacro(macroIndex) {
        if (this.IsMacroRunning(macroIndex))
            return

        tableItem := GetTableBySymbol("UI")
        item := tableItem ? tableItem.Items[macroIndex] : ""
        if (!item)
            return
        macroStr := item.Macro

        this.CancelRecoverTimer(macroIndex)

        actionObj := this
        action := (*) => (
            OnTriggerMacroKeyAndInit(tableItem, macroStr, macroIndex),
            SetTimer(() => actionObj.OnMacroComplete(macroIndex), -10)
        )

        this.RunningMap[macroIndex] := {IsRunning: true, TimerAction: action}
        SetTimer(action, -1)
        MySetTableItemState(tableItem, macroIndex, UIMacroGui.STATE_RUNNING)
        this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_RUNNING)
    }

    StopMacro(macroIndex) {
        tableItem := GetTableBySymbol("UI")

        this.CancelRecoverTimer(macroIndex)

        if (tableItem && tableItem.Items.Has(macroIndex)) {
            item := tableItem.Items[macroIndex]
            item.Killed := true
            item.Pause := false
        }

        if (this.RunningMap.Has(macroIndex))
            this.RunningMap.Delete(macroIndex)

        MySetTableItemState(tableItem, macroIndex, UIMacroGui.STATE_STOPPED)
        this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_STOPPED)
    }

    OnMacroComplete(macroIndex) {
        if (this.IsMacroRunning(macroIndex)) {
            this.RunningMap.Delete(macroIndex)
            this.CancelRecoverTimer(macroIndex)
            tableItem := GetTableBySymbol("UI")
            if (tableItem)
                MySetTableItemState(tableItem, macroIndex, UIMacroGui.STATE_DEFAULT)
            this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_DEFAULT)
        }
    }

    ; 更新按钮状态色点
    UpdateButtonStatus(macroIndex, state) {
        for foldIndex, panelInfo in this.PanelMap {
            if (!panelInfo.ui || !panelInfo.btnItems)
                continue
            for item in panelInfo.btnItems {
                if (item.macroIndex == macroIndex) {
                    stateName := item.name "_State"
                    try {
                        if (state == UIMacroGui.STATE_DEFAULT) {
                            panelInfo.ui.Update(stateName, "Visibility", "Collapsed")
                        } else if (MacroStateColors.Has(state)) {
                            color := MacroStateColors[state]
                            panelInfo.ui.Update(stateName, "Visibility", "Visible")
                            panelInfo.ui.Update(stateName, "Fill", color)
                        }
                    }
                    ; ui.Update() 后恢复位置（对齐 MovePanel L171-179）
                    if (!panelInfo.isScreenMode && panelInfo.panelReady && panelInfo.visible
                        && panelInfo.wpfHwnd && panelInfo.targetHwnd
                        && DllCall("user32\IsWindow", "Ptr", panelInfo.wpfHwnd)
                        && DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
                        targetRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                        winW := targetRect["right"] - targetRect["left"]
                        winH := targetRect["bottom"] - targetRect["top"]
                        pr := this.GetWindowRectCoords(panelInfo.wpfHwnd)
                        pw := pr["right"] - pr["left"]
                        ph := pr["bottom"] - pr["top"]
                        anchorX := 0, anchorY := 0
                        anchorPos := panelInfo.HasProp("anchorPos") ? panelInfo.anchorPos : 1
                        this.CalcDefaultPosition(anchorPos, &anchorX, &anchorY, pw, ph, winW, winH)
                        restoreX := targetRect["left"] + anchorX + panelInfo.offsetX
                        restoreY := targetRect["top"] + anchorY + panelInfo.offsetY
                        DllCall("user32\SetWindowPos"
                            , "Ptr", panelInfo.wpfHwnd, "Ptr", panelInfo.targetHwnd
                            , "Int", restoreX, "Int", restoreY
                            , "Int", 0, "Int", 0
                            , "UInt", 0x0001 | 0x0004 | 0x0010 | 0x4000)
                    }
                    break
                }
            }
        }
    }

    UpdateButtonsState(macroIndex, state) {
        this.UpdateButtonStatus(macroIndex, state)
    }

    CancelRecoverTimer(macroIndex) {
        if (this.RecoverTimers.Has(macroIndex)) {
            oldTimer := this.RecoverTimers[macroIndex]
            if (oldTimer)
                SetTimer(oldTimer, 0)
            this.RecoverTimers.Delete(macroIndex)
        }
    }

    HideAllPanels() {
        for foldIndex in this.PanelTimers.Clone() {
            this.StopFollowTimer(foldIndex)
        }
        for foldIndex, panelInfo in this.PanelMap.Clone() {
            try {
                if (panelInfo.ui)
                    panelInfo.ui.Update("Window", "Close", "")
            }
        }
        this.PanelMap.Clear()
    }

    RefreshPanels() {
        this.HideAllPanels()
    }

    ShowPanel(foldIndex) {
        this.ClearUserClosed(foldIndex)
        if (!this.PanelMap.Has(foldIndex))
            this.CreatePanel(foldIndex)

        panelInfo := this.PanelMap.Has(foldIndex) ? this.PanelMap[foldIndex] : ""
        if (!panelInfo || !panelInfo.wpfHwnd)
            return

        try {
            panelInfo.userClosed := false
            DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 9)
            if (panelInfo.isScreenMode) {
                WinSetAlwaysOnTop(1, "ahk_id " panelInfo.wpfHwnd)
            }

            ; Show 之后重新应用默认位置（WPF Show 会恢复上次位置）
            this.ApplyPanelPosition(panelInfo)

            WinActivate("ahk_id " panelInfo.wpfHwnd)
            panelInfo.visible := true
        }
    }

    GetFullIconPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon\" path
        if (FileExist(fullPath))
            return fullPath

        return ""
    }

    ; 根据配置的位置编号计算面板相对容器（屏幕或目标窗口）的锚点坐标
    ; pos: 1=左上,2=中上,3=右上,4=中左,5=中心,6=中右,7=左下,9=中下,10=右下
    ; sw/sh 为锚定容器尺寸（屏幕模式=屏幕，窗口跟随模式=目标窗口矩形），缺省取主屏
    CalcDefaultPosition(pos, &x, &y, pw, ph, sw := 0, sh := 0) {
        if (sw <= 0)
            sw := A_ScreenWidth
        if (sh <= 0)
            sh := A_ScreenHeight
        switch pos {
            case 1: x := 20, y := 20                          ; 左上
            case 2: x := (sw - pw) // 2, y := 20             ; 中上
            case 3: x := sw - pw - 20, y := 20               ; 右上
            case 4: x := 20, y := (sh - ph) // 2            ; 中左
            case 5: x := (sw - pw) // 2, y := (sh - ph) // 2 ; 中心
            case 6: x := sw - pw - 20, y := (sh - ph) // 2  ; 中右
            case 7: x := 20, y := sh - ph - 20               ; 左下
            case 9: x := (sw - pw) // 2, y := sh - ph - 20  ; 中下
            case 10: x := sw - pw - 20, y := sh - ph - 20   ; 右下
        }
    }

    ; 根据配置的默认位置，在显示面板前应用位置
    ApplyPanelPosition(panelInfo) {
        ; 获取面板尺寸
        try {
            rect := this.GetWindowRectCoords(panelInfo.wpfHwnd)
            pw := rect["right"] - rect["left"]
            ph := rect["bottom"] - rect["top"]
        } catch {
            pw := 250, ph := 200
        }

        initX := 0, initY := 0
        baseLeft := 0, baseTop := 0
        contW := 0, contH := 0

        ; 窗口跟随模式：以目标窗口为锚定容器；否则以屏幕为容器
        if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
            try {
                wRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                contW := wRect["right"] - wRect["left"]
                contH := wRect["bottom"] - wRect["top"]
                baseLeft := wRect["left"]
                baseTop := wRect["top"]
            }
        }
        if (contW <= 0)
            contW := A_ScreenWidth
        if (contH <= 0)
            contH := A_ScreenHeight

        this.CalcDefaultPosition(MainSoftData.UIPanelDefaultPos, &initX, &initY, pw, ph, contW, contH)
        initX += baseLeft
        initY += baseTop

        initX += Integer(MainSoftData.UIPanelOffsetX)
        initY += Integer(MainSoftData.UIPanelOffsetY)

        DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0
            , "Int", initX, "Int", initY, "Int", 0, "Int", 0, "UInt", 0x0001)
    }

    GetWindowRectCoords(hwnd) {
        rect := Buffer(16, 0)
        DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        left := NumGet(rect, 0, "Int")
        top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int")
        bottom := NumGet(rect, 12, "Int")
        return Map("left", left, "top", top, "right", right, "bottom", bottom)
    }

    ; 直接用 hwnd 匹配 FrontInfo 条件（用于自动显示检测）
    IsHwndMatchFrontInfo(hwnd, frontInfo) {
        if (frontInfo == "" || !hwnd)
            return false

        ; ❖ 句柄列表模式：检查 hwnd 是否在列表中
        if (InStr(frontInfo, "❖")) {
            idStr := StrReplace(frontInfo, "❖")
            for _, id in StrSplit(idStr, "|") {
                if (id != "" && Integer(id) == hwnd)
                    return true
            }
            return false
        }

        ; title⎖class⎖process 模式
        infoArr := StrSplit(frontInfo, "⎖")
        if (infoArr.Length != 3)
            return false

        try {
            if (infoArr[1] != "" && !InStr(WinGetTitle("ahk_id " hwnd), infoArr[1]))
                return false
            if (infoArr[2] != "" && WinGetClass("ahk_id " hwnd) != infoArr[2])
                return false
            if (infoArr[3] != "" && WinGetProcessName("ahk_id " hwnd) != infoArr[3])
                return false
            return true
        }
        return false
    }

    ResolveTargetHwnd(frontInfo) {
        if (frontInfo == "")
            return 0

        if (InStr(frontInfo, "❖")) {
            idStr := StrReplace(frontInfo, "❖")
            hwndList := StrSplit(idStr, "|")
            for index, hwnd in hwndList {
                if (hwnd == "")
                    continue
                try {
                    hwndVal := Integer(hwnd)
                    if (DllCall("user32\IsWindow", "Ptr", hwndVal))
                        return hwndVal
                }
            }
            return 0
        }

        infoArr := StrSplit(frontInfo, "⎖")
        if (infoArr.Length != 3)
            return 0

        title := infoArr[1]
        className := infoArr[2]
        process := infoArr[3]

        winTitle := ""
        if (title != "")
            winTitle .= title
        if (className != "")
            winTitle .= " ahk_class " className
        if (process != "")
            winTitle .= " ahk_exe " process

        if (winTitle == "")
            return 0

        try {
            hwnd := WinExist(winTitle)
            return hwnd ? hwnd : 0
        }
        return 0
    }

    __Delete() {
        this.StopMonitor()
    }
}
