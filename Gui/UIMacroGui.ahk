#Requires AutoHotkey v2.0

class UIMacroGui {
    static STATE_DEFAULT := 0    ; 默认/空闲（隐藏色块）
    static STATE_RUNNING := 1    ; 运行中（绿色）
    static STATE_PAUSED := 2     ; 暂停中（黄色）
    static STATE_STOPPED := 3    ; 停止/终止（红色，5秒后自动恢复）

    ; 状态色点颜色
    static StateColors := Map(
        UIMacroGui.STATE_RUNNING, "#FF4CAF50",
        UIMacroGui.STATE_PAUSED,  "#FFFFC107",
        UIMacroGui.STATE_STOPPED, "#FFF44336"
    )

    __new() {
        this.PanelMap := Map()       ; foldIndex -> panelInfo
        this.PanelTimers := Map()     ; foldIndex -> FuncObj（SetTimer回调引用）
        this.IsCreating := false
        this.MonitorTimer := ""
        this.RunningMap := Map()
        this.RecoverTimers := Map()
        this._lastActiveHwnd := 0       ; 上次检测的前台窗口 hwnd
        this.StartMonitor()
    }

    StartMonitor() {
        if (this.MonitorTimer != "")
            return
        this.MonitorTimer := Timer(this.CheckAllPanels.Bind(this), 200)
        this.MonitorTimer.On()
    }

    StopMonitor() {
        if (this.MonitorTimer != "") {
            this.MonitorTimer.Off()
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

    ; 创建面板入口（对齐 CreateFloatingPanel L182-265）
    CreatePanel(foldIndex) {
        tableItem := MySoftData.TableInfo[4]
        if (!tableItem || !tableItem.FoldInfo)
            return

        foldInfo := tableItem.FoldInfo
        if (foldIndex > foldInfo.RemarkArr.Length)
            return

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        indexSpanStr := foldInfo.IndexSpanArr[foldIndex]
        indexSpan := StrSplit(indexSpanStr, "-")
        if (!IsInteger(indexSpan[1]) || !IsInteger(indexSpan[2]))
            return

        startIndex := Integer(indexSpan[1])
        endIndex := Integer(indexSpan[2])

        btnItems := []
        Loop (endIndex - startIndex + 1) {
            macroIndex := startIndex + A_Index - 1
            if (macroIndex > tableItem.RemarkArr.Length)
                continue
            if (Integer(tableItem.ForbidArr[macroIndex]) = 1)
                continue

            remarkValue := tableItem.RemarkArr[macroIndex]
            iconValue := tableItem.IcoPathArr[macroIndex]
            btnText := remarkValue == "" ? GetLang("操作") A_Index : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

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
        frontInfo := foldInfo.FrontInfoArr[foldIndex]
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
        panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode)
        if (!panelInfo)
            return

        this.PanelMap.Set(foldIndex, panelInfo)

        ; 等待窗口就绪+初始化（对齐 WaitForHwnd + OnPanelReady）
        this.WaitForPanelReady(foldIndex)
    }

    ; 为指定 hwnd 创建自动面板（界面激活时默认显示），键为 foldIndex|hwnd
    CreateAutoPanel(foldIndex, panelKey, targetHwnd) {
        if (this.PanelMap.Has(panelKey))
            return

        tableItem := MySoftData.TableInfo[4]
        if (!tableItem || !tableItem.FoldInfo)
            return

        foldInfo := tableItem.FoldInfo
        if (foldIndex > foldInfo.RemarkArr.Length)
            return

        indexSpanStr := foldInfo.IndexSpanArr[foldIndex]
        indexSpan := StrSplit(indexSpanStr, "-")
        if (!IsInteger(indexSpan[1]) || !IsInteger(indexSpan[2]))
            return

        startIndex := Integer(indexSpan[1])
        endIndex := Integer(indexSpan[2])

        btnItems := []
        Loop (endIndex - startIndex + 1) {
            macroIndex := startIndex + A_Index - 1
            if (macroIndex > tableItem.RemarkArr.Length)
                continue
            if (Integer(tableItem.ForbidArr[macroIndex]) = 1)
                continue

            remarkValue := tableItem.RemarkArr[macroIndex]
            iconValue := tableItem.IcoPathArr[macroIndex]
            btnText := remarkValue == "" ? GetLang("操作") A_Index : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

            btnItems.Push({
                name: "Btn_" macroIndex,
                text: btnText,
                icon: displayIcon,
                macroIndex: macroIndex
            })
        }

        if (btnItems.Length == 0)
            return

        ; 自动面板始终有目标窗口（isScreenMode = false）
        panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, false, true)
        if (!panelInfo)
            return

        panelInfo.autoShow := true  ; 标记为自动面板
        this.PanelMap.Set(panelKey, panelInfo)
        this.WaitForPanelReady(panelKey)

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

        ; 配置变化检测：按钮尺寸/列数/颜色变化 → 销毁重建
        if (panelInfo._cfg_BtnHeight != MySoftData.UIPanelBtnHeight
            || panelInfo._cfg_BtnWidth != MySoftData.UIPanelBtnWidth
            || panelInfo._cfg_Cols != MySoftData.UIPanelCols
            || panelInfo._cfg_BtnColor != MySoftData.UIPanelBtnColor
            || panelInfo._cfg_BgColor != MySoftData.UIPanelBgColor
            || panelInfo._cfg_FontColor != MySoftData.UIPanelFontColor) {
            parts := StrSplit(panelKey, "|")
            foldIndex := Integer(parts[1])
            targetHwnd := Integer(parts[2])
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
        btnItemH := MySoftData.UIPanelBtnHeight
        btnItemW := MySoftData.UIPanelBtnWidth
        btnGap := 2
        bodyMarginV := 6
        cols := MySoftData.UIPanelCols
        wpfBorderPad := 22
        ; 面板宽度 = 列数 * 按钮宽度 + 按钮左右边距(各2px) + 主体左右边距(各4px)
        pw := cols * (btnItemW + 4) + 8

        btnColor := MySoftData.UIPanelBtnColor
        bgColor := MySoftData.UIPanelBgColor
        fontColor := MySoftData.UIPanelFontColor

        tableItem := MySoftData.TableInfo[4]
        foldRemark := tableItem.FoldInfo.RemarkArr[foldIndex]

        rows := Ceil(btnItems.Length / cols)
        contentH := rows * btnItemH + (rows - 1) * btnGap + bodyMarginV
        ph := titleBarH + contentH + wpfBorderPad

        CoordMode("Mouse", "Screen")
        MouseGetPos(&initX, &initY)

        ; 根据配置计算初始位置
        if (MySoftData.UIPanelDefaultPos != 8) {
            this.CalcDefaultPosition(MySoftData.UIPanelDefaultPos, &initX, &initY, pw, ph)
            offsetX := initX   ; 相对于目标窗口的偏移量（预设位置值）
            offsetY := initY
            if (!isScreenMode && targetHwnd) {
                try {
                    rect := this.GetWindowRectCoords(targetHwnd)
                    initX += rect["left"]   ; 转为屏幕绝对坐标用于 XAML Left/Top
                    initY += rect["top"]
                }
            }
        } else {
            offsetX := initX
            offsetY := initY
            if (!isScreenMode && targetHwnd) {
                try {
                    rect := this.GetWindowRectCoords(targetHwnd)
                    offsetX := initX - rect["left"]
                    offsetY := initY - rect["top"]
                }
            }
        }

        ; 构建XAML（与 floating_panel L213-233 完全一致的结构）
        main := XAML_Generator("Grid")
        main.Background(bgColor)
        main.Rows(titleBarH, "*")

        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("#88000000")
        titleBar.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground("#FFFFFF").FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")

        body := main.Add("Grid").Grid_Row(1).Name("BodyPanel").Margin("4,2,4,4")

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
            marginStr := "2,0,2," marginBottom

            btn := body.Add("Button").Name(item.name).Height(btnItemH)
                .Grid_Row(row).Grid_Column(col)
                .Margin(marginStr)
            btn.Background(btnColor).Foreground(fontColor).FontSize(10)
            btn.HorizontalAlignment("Stretch")
            btn.Padding("2,0,2,0")

            sp := btn.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")

            sp.Add("Border").Name(item.name "_State")
                .Width(6).Height(6).CornerRadius(3)
                .VerticalAlignment("Center").Margin("0,0,2,0")
                .Background("Transparent")

            if (item.icon != "") {
                fullIconPath := this.GetFullIconPath(item.icon)
                if (fullIconPath != "" && FileExist(fullIconPath)) {
                    sp.Add("Image").Name(item.name "_Img")
                        .Source(fullIconPath).Width(14).Height(14).VerticalAlignment("Center").Margin("0,0,3,0")
                }
            }

            sp.Add("TextBlock").Text(item.text).VerticalAlignment("Center").Foreground(fontColor).FontSize(10)
                .TextTrimming("CharacterEllipsis").MaxWidth("50")
        }

        ; XAML字符串处理（对齐 floating_panel L235-244）
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" ShowInTaskbar="False" Width="' pw '" Height="' ph '"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
        ui.xaml := StrReplace(ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
        ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="' bgColor '"')

        ui.xaml := StrReplace(ui.xaml, '%resources%', '<SolidColorBrush x:Key="TextMain" Color="White"/><CornerRadius x:Key="WindowRadius">8</CornerRadius><CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>')
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
            frontInfo: tableItem.FoldInfo.FrontInfoArr[foldIndex],
            visible: true,
            btnItems: btnItems,
            offsetX: offsetX,
            offsetY: offsetY,
            lastSetX: "",
            lastSetY: "",
            panelReady: false,
            ; 配置快照：用于检测面板显示时配置是否变化
            _cfg_BtnHeight: btnItemH,
            _cfg_BtnWidth: btnItemW,
            _cfg_Cols: cols,
            _cfg_BtnColor: btnColor,
            _cfg_BgColor: bgColor,
            _cfg_FontColor: fontColor
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

        ; L373-L375: 设置窗口扩展样式 + 移除系统菜单（隐藏标题栏右键菜单）
        hwnd := panelInfo.wpfHwnd
        if (hwnd) {
            exStyle := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
            DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int"
                , exStyle | 0x80)
            ; 移除系统菜单（标题栏右键菜单），保留SC_MOVE以支持拖拽
            hSysMenu := DllCall("user32\GetSystemMenu", "Ptr", hwnd, "Int", 0, "Ptr")
            if (hSysMenu) {
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF060, "UInt", 0)  ; SC_CLOSE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF020, "UInt", 0)  ; SC_MINIMIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF000, "UInt", 0)  ; SC_SIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF030, "UInt", 0)  ; SC_MAXIMIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF120, "UInt", 0)  ; SC_RESTORE
            }
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

        ; L398-L409: 屏幕模式分支
        if (panelInfo.isScreenMode) {
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

        ; ====== 位置变化检测（替代三阶段拖拽检测） ======
        ; 原理：记录我们上次 SetWindowPos 设到的位置(lastSetX/Y)。
        ;   - 如果实际位置 == lastSetX/Y → 没有外部干扰 → 正常跟随
        ;   - 如果实际位置 != lastSetX/Y → 有外部力量移动了面板(用户拖拽等)
        ;     → 立即更新 offset 来适配新位置 → 之后用新 offset 跟随
        ; 这完全不依赖 LButton / hwndUnderMouse / isDragging，绕开了检测失效的问题。
        if (!panelInfo.isScreenMode && panelInfo.lastSetX != "" && panelInfo.lastSetY != "") {
            diagRect := this.GetWindowRectCoords(hwnd)
            targetDiagRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
            devX := Abs(diagRect["left"] - panelInfo.lastSetX)
            devY := Abs(diagRect["top"] - panelInfo.lastSetY)
            if (devX > 3 || devY > 3) {
                panelInfo.offsetX := diagRect["left"] - targetDiagRect["left"]
                panelInfo.offsetY := diagRect["top"] - targetDiagRect["top"]
            }
        }

        ; 阶段3 — 正常跟随移动（对齐 floating_panel MovePanel L171-179）
        rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
        newX := rect["left"] + panelInfo.offsetX
        newY := rect["top"] + panelInfo.offsetY
        ownerHwnd := panelInfo.isScreenMode ? 0 : panelInfo.targetHwnd
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
        ; ====== 前置守卫：窗口跟随模式必须先通过前台激活检查 ======
        tableItem := MySoftData.TableInfo[4]
        targetHwnd := 0
        if (tableItem && tableItem.FoldInfo) {
            frontInfo := tableItem.FoldInfo.FrontInfoArr[foldIndex]
            if (frontInfo != "") {
                targetHwnd := this.ResolveTargetHwnd(frontInfo)
                if (targetHwnd) {
                    ; 目标窗口存在 → 必须在前台才允许操作面板
                    activeHwnd := WinGetID("A")
                    if (activeHwnd != targetHwnd)
                        return
                } else {
                    ; 目标窗口不存在 → 不允许操作
                    return
                }
            }
        }

        ; 面板键：有目标窗口则用 foldIndex|hwnd（与自动面板共享同一个实例）
        panelKey := targetHwnd ? (foldIndex "|" targetHwnd) : foldIndex

        if (!this.PanelMap.Has(panelKey)) {
            if (targetHwnd) {
                this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
                ; 手动快捷键触发需要激活面板
                if (this.PanelMap.Has(panelKey)) {
                    try WinActivate("ahk_id " this.PanelMap[panelKey].wpfHwnd)
                }
            } else
                this.CreatePanel(foldIndex)
            return
        }

        panelInfo := this.PanelMap[panelKey]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return

        ; 配置变化检测：按钮尺寸/列数/颜色变化时销毁重建
        if (panelInfo.visible == false  ; 只在从隐藏→显示时检查
            && (panelInfo._cfg_BtnHeight != MySoftData.UIPanelBtnHeight
                || panelInfo._cfg_BtnWidth != MySoftData.UIPanelBtnWidth
                || panelInfo._cfg_Cols != MySoftData.UIPanelCols
                || panelInfo._cfg_BtnColor != MySoftData.UIPanelBtnColor
                || panelInfo._cfg_BgColor != MySoftData.UIPanelBgColor
                || panelInfo._cfg_FontColor != MySoftData.UIPanelFontColor)) {
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
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 1)          ; SW_SHOW
            this.ApplyPanelPosition(panelInfo)
            ; 更新偏移量（窗口跟随模式）
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                try {
                    rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                    rect2 := this.GetWindowRectCoords(hwnd)
                    panelInfo.offsetX := rect2["left"] - rect["left"]
                    panelInfo.offsetY := rect2["top"] - rect["top"]
                }
            }
        } else {
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 0)
        }
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
            ; 面板窗口已失效（被关闭）
            if (!panelInfo.ui || !panelInfo.wpfHwnd || !WinExist("ahk_id " panelInfo.wpfHwnd)) {
                deadFolds.Push(panelKey)
                continue
            }
            if (!panelInfo.isScreenMode)
                continue
            if (!panelInfo.visible)
                continue

            hwnd := panelInfo.wpfHwnd

            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        }
        ; 清理已关闭的面板残留条目（DestroyPanel 会关闭窗口 + 停止定时器）
        for panelKey in deadFolds {
            this.DestroyPanel(panelKey)
        }

        ; ====== 界面激活时默认显示 ======
        try {
            if (MySoftData.UIPanelShowOnActive) {
                activeHwnd := WinGetID("A")
                if (activeHwnd && activeHwnd != this._lastActiveHwnd) {
                    this._lastActiveHwnd := activeHwnd

                    tableItem := MySoftData.TableInfo[4]
                    if (tableItem && tableItem.FoldInfo) {
                        foldInfo := tableItem.FoldInfo
                        for foldIndex, _ in foldInfo.IndexSpanArr {
                            if (foldInfo.ForbidStateArr[foldIndex])
                                continue

                            frontInfo := foldInfo.FrontInfoArr[foldIndex]
                            ; 直接用前台 hwnd 匹配 FrontInfo（支持多实例）
                            if (frontInfo == "" || !this.IsHwndMatchFrontInfo(activeHwnd, frontInfo))
                                continue

                            ; 面板键: foldIndex|hwnd → 每个窗口实例一个独立面板
                            panelKey := foldIndex "|" activeHwnd

                            ; 面板与目标窗口 hwnd 绑定：存在则显示，不存在则创建
                            if (!this.PanelMap.Has(panelKey))
                                this.CreateAutoPanel(foldIndex, panelKey, activeHwnd)
                            else
                                this.ShowAutoPanel(panelKey)
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
            tableItem := MySoftData.TableInfo[4]
            if (Integer(tableItem.ForbidArr[macroIndex]) = 1)
                return

            if (!tableItem.MacroArr[macroIndex] || tableItem.MacroArr[macroIndex] == "")
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

        tableItem := MySoftData.TableInfo[4]
        macroStr := tableItem.MacroArr[macroIndex]

        this.CancelRecoverTimer(macroIndex)

        actionObj := this
        action := (*) => (
            OnTriggerMacroKeyAndInit(tableItem, macroStr, macroIndex),
            SetTimer(() => actionObj.OnMacroComplete(macroIndex), -10)
        )

        this.RunningMap[macroIndex] := {IsRunning: true, TimerAction: action}
        SetTimer(action, -1)
        MySetTableItemState(4, macroIndex, UIMacroGui.STATE_RUNNING)
        this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_RUNNING)
    }

    StopMacro(macroIndex) {
        tableItem := MySoftData.TableInfo[4]

        this.CancelRecoverTimer(macroIndex)

        tableItem.KilledArr[macroIndex] := true
        tableItem.PauseArr[macroIndex] := false

        if (this.RunningMap.Has(macroIndex))
            this.RunningMap.Delete(macroIndex)

        MySetTableItemState(4, macroIndex, UIMacroGui.STATE_STOPPED)
        this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_STOPPED)
    }

    OnMacroComplete(macroIndex) {
        if (this.IsMacroRunning(macroIndex)) {
            this.RunningMap.Delete(macroIndex)
            this.CancelRecoverTimer(macroIndex)
            MySetTableItemState(4, macroIndex, UIMacroGui.STATE_DEFAULT)
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
                        } else if (UIMacroGui.StateColors.Has(state)) {
                            color := UIMacroGui.StateColors[state]
                            panelInfo.ui.Update(stateName, "Visibility", "Visible")
                            panelInfo.ui.Update(stateName, "Background", color)
                        }
                    }
                    ; ui.Update() 后恢复位置（对齐 MovePanel L171-179）
                    if (!panelInfo.isScreenMode && panelInfo.panelReady && panelInfo.visible
                        && panelInfo.wpfHwnd && panelInfo.targetHwnd
                        && DllCall("user32\IsWindow", "Ptr", panelInfo.wpfHwnd)
                        && DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
                        targetRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                        restoreX := targetRect["left"] + panelInfo.offsetX
                        restoreY := targetRect["top"] + panelInfo.offsetY
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
        if (!this.PanelMap.Has(foldIndex))
            this.CreatePanel(foldIndex)

        panelInfo := this.PanelMap.Has(foldIndex) ? this.PanelMap[foldIndex] : ""
        if (!panelInfo || !panelInfo.wpfHwnd)
            return

        try {
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

    ; 根据配置的位置编号计算面板初始坐标
    ; pos: 1=左上,2=中上,3=右上,4=中左,5=中心,6=中右,7=左下,8=鼠标位置
    CalcDefaultPosition(pos, &x, &y, pw, ph) {
        sw := A_ScreenWidth
        sh := A_ScreenHeight
        switch pos {
            case 1: x := 20, y := 20                          ; 左上
            case 2: x := (sw - pw) // 2, y := 20             ; 中上
            case 3: x := sw - pw - 20, y := 20               ; 右上
            case 4: x := 20, y := (sh - ph) // 2            ; 中左
            case 5: x := (sw - pw) // 2, y := (sh - ph) // 2 ; 中心
            case 6: x := sw - pw - 20, y := (sh - ph) // 2  ; 中右
            case 7: x := 20, y := sh - ph - 20               ; 左下
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

        if (MySoftData.UIPanelDefaultPos != 8) {
            this.CalcDefaultPosition(MySoftData.UIPanelDefaultPos, &initX, &initY, pw, ph)
            ; 窗口跟随模式：预设位置改为相对于目标窗口
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                try {
                    wRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                    initX += wRect["left"]
                    initY += wRect["top"]
                }
            }
        } else {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&initX, &initY)
            ; 鼠标位置本身已是屏幕绝对坐标，SetWindowPos 直接使用
        }

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
