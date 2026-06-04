#Requires AutoHotkey v2.0

class UIMacroGui {
    static STATE_DEFAULT := 0    ; 默认/空闲（隐藏色块）
    static STATE_RUNNING := 1    ; 运行中（绿色 GreenColor.png）
    static STATE_PAUSED := 2     ; 暂停中（黄色 YellowColor.png）
    static STATE_STOPPED := 3    ; 停止/终止（红色 RedColor.png，5秒后自动恢复）

    ; 状态色点图片路径
    static IMG_DIR := A_ScriptDir "\..\Images\Soft"
    static StateImages := Map(
        UIMacroGui.STATE_RUNNING, A_ScriptDir "\..\Images\Soft\GreenColor.png",
        UIMacroGui.STATE_PAUSED,  A_ScriptDir "\..\Images\Soft\YellowColor.png",
        UIMacroGui.STATE_STOPPED, A_ScriptDir "\..\Images\Soft\RedColor.png"
    )

    __new() {
        this.PanelMap := Map()       ; foldIndex -> panelInfo
        this.PanelTimers := Map()     ; foldIndex -> FuncObj（SetTimer回调引用）
        this.IsCreating := false
        this.MonitorTimer := ""
        this.RunningMap := Map()
        this.RecoverTimers := Map()
        this.StartMonitor()
    }

    StartMonitor() {
        if (this.MonitorTimer != "")
            return
        this.MonitorTimer := Timer(this.CheckAllPanels.Bind(this), 50)
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
            if (tableItem.ForbidArr[macroIndex])
                continue
            if (!tableItem.MacroArr[macroIndex] || tableItem.MacroArr[macroIndex] == "")
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

    ; 构建XAML面板（对齐 CreateFloatingPanel L182-264）
    BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode) {
        pw := 130
        titleBarH := 26
        toggleBtnH := 28
        btnItemH := 34
        btnGap := 2
        bodyMarginV := 6
        wpfBorderPad := 22

        tableItem := MySoftData.TableInfo[4]
        foldRemark := tableItem.FoldInfo.RemarkArr[foldIndex]

        contentH := btnItems.Length * btnItemH + (btnItems.Length - 1) * btnGap + bodyMarginV
        ph := titleBarH + toggleBtnH + contentH + wpfBorderPad

        CoordMode("Mouse", "Screen")
        MouseGetPos(&initX, &initY)

        ; 计算初始偏移（对齐 floating_panel g_offsetX/Y 初始化为鼠标位置）
        offsetX := initX
        offsetY := initY
        if (!isScreenMode && targetHwnd) {
            try {
                rect := this.GetWindowRectCoords(targetHwnd)
                offsetX := initX - rect["left"]
                offsetY := initY - rect["top"]
            }
        }

        collapsedHeight := titleBarH + toggleBtnH + wpfBorderPad + 4
        expandedHeight := ph

        ; 构建XAML（与 floating_panel L213-233 完全一致的结构）
        main := XAML_Generator("Grid")
        main.Background("{x:Null}")
        main.Rows(titleBarH, "Auto", "*")

        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("#88000000")
        titleBar.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground("#FFFFFF").FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")

        toggleBtn := main.Add("Button").Grid_Row(1).Name("BtnToggle").Content("▼ 收起").Height(toggleBtnH)
            .HorizontalAlignment("Center").Margin("0,0,0,0").FontSize(9).Foreground("#999")
        toggleBtn.Background("#00000000").BorderBrush("#00000000")

        body := main.Add("StackPanel").Grid_Row(2).Name("BodyPanel").Margin("4,2,4,4")

        for i, item in btnItems {
            isLast := (i == btnItems.Length)
            marginStr := isLast ? "" : ",0," btnGap

            btn := body.Add("Button").Name(item.name).Height(btnItemH)
                .Margin("0,0" marginStr)
            btn.Background("#333333").Foreground("#DDD").FontSize(11)
            btn.HorizontalAlignment("Stretch")

            sp := btn.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")

            sp.Add("Image").Name(item.name "_State")
                .Width(10).Height(10).VerticalAlignment("Center").Margin("0,0,4,0")

            if (item.icon != "") {
                fullIconPath := this.GetFullIconPath(item.icon)
                if (fullIconPath != "" && FileExist(fullIconPath)) {
                    sp.Add("Image").Name(item.name "_Img")
                        .Source(fullIconPath).Width(18).Height(18).VerticalAlignment("Center").Margin("0,0,6,0")
                }
            }

            sp.Add("TextBlock").Text(item.text).VerticalAlignment("Center").Foreground("#DDD").FontSize(11)
        }

        ; XAML字符串处理（对齐 floating_panel L235-244）
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" Width="' pw '" Height="' ph '"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
        ui.xaml := StrReplace(ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
        ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="{x:Null}"')

        ui.xaml := StrReplace(ui.xaml, '%resources%', '<SolidColorBrush x:Key="TextMain" Color="White"/><CornerRadius x:Key="WindowRadius">8</CornerRadius><CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>')
        ui.xaml := StrReplace(ui.xaml, '%components%', '')

        ; 绑定事件（对齐 floating_panel L246-249）
        for i, item in btnItems {
            mi := item.macroIndex
            ui.OnEvent(item.name, "Click", (*) => this.OnButtonClick(mi))
        }
        ui.OnEvent("BtnToggle", "Click", (*) => this.OnToggleClick(foldIndex))

        ; 显示窗口（对齐 floating_panel L254）
        ui.Show()

        ; 等待wpfHwnd就绪（对齐 floating_panel L256-262）
        loop 20 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
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
            isCollapsed: false,
            expandedHeight: expandedHeight,
            collapsedHeight: collapsedHeight,
            btnItems: btnItems,
            offsetX: offsetX,
            offsetY: offsetY,
            lastSetX: "",
            lastSetY: "",
            panelReady: false
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

        ; L368-L371: 获取窗口尺寸
        hwnd := panelInfo.wpfHwnd
        if (hwnd) {
            rect := this.GetWindowRectCoords(hwnd)
            panelInfo.expandedHeight := rect["bottom"] - rect["top"]
        }

        ; L373-L375: 设置窗口扩展样式
        if (hwnd) {
            exStyle := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
            DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int"
                , (exStyle | 0x80 | 0x08000000) & ~0x40000)
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

        if (!this.PanelMap.Has(foldIndex)) {
            this.CreatePanel(foldIndex)
            return
        }

        panelInfo := this.PanelMap[foldIndex]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return

        ; L498: 切换可见性
        panelInfo.visible := !panelInfo.visible
        hwnd := panelInfo.wpfHwnd
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
            return

        if (panelInfo.visible) {
            ; L503-L509: 显示（严格对齐 floating_panel TogglePanelVisibility L503-L509：hwndAfter=0）
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0                                  ; 对齐 L506: hwndAfter=0
                , "Int", mx, "Int", my                                   ; 对齐 L507
                , "Int", 0, "Int", 0                                     ; 对齐 L507
                , "UInt", 0x0001 | 0x0004 | 0x0010)                     ; 对齐 L508
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 1)          ; 对齐 L509: SW_SHOW
            ; 更新偏移量（窗口跟随模式）
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                try {
                    rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                    panelInfo.offsetX := mx - rect["left"]
                    panelInfo.offsetY := my - rect["top"]
                }
            }
        } else {
            ; L510-L512: 隐藏 — SW_HIDE
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
        for foldIndex, panelInfo in this.PanelMap {
            if (!panelInfo.ui || !panelInfo.wpfHwnd)
                continue
            if (!panelInfo.isScreenMode)
                continue
            if (!panelInfo.visible)
                continue

            hwnd := panelInfo.wpfHwnd

            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
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

    ; 收起/展开（严格对齐 floating_panel OnToggleClick L458-488）
    OnToggleClick(foldIndex) {
        if (!this.PanelMap.Has(foldIndex))
            return

        panelInfo := this.PanelMap[foldIndex]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return
        if (!panelInfo.panelReady)
            return

        ; L467: 切换状态
        panelInfo.isCollapsed := !panelInfo.isCollapsed
        hwnd := panelInfo.wpfHwnd

        curRect := this.GetWindowRectCoords(hwnd)
        curW := curRect["right"] - curRect["left"]

        ; L471-L478: 收起（严格对齐 floating_panel L471-L478：x=0,y=0 + SWP_NOMOVE）
        if (panelInfo.isCollapsed) {
            try panelInfo.ui.Update("BodyPanel", "Visibility", "Collapsed")
            try panelInfo.ui.Update("BtnToggle", "Content", "▲ 展开")
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0                                   ; 对齐 L476-L477
                , "Int", curW, "Int", panelInfo.collapsedHeight         ; 对齐 L477
                , "UInt", 0x0002 | 0x0004 | 0x0010 | 0x4000)          ; 对齐 L478
        } else {
            ; L479-L487: 展开（严格对齐 floating_panel L479-L487）
            try panelInfo.ui.Update("BodyPanel", "Visibility", "Visible")
            try panelInfo.ui.Update("BtnToggle", "Content", "▼ 收起")
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0
                , "Int", curW, "Int", panelInfo.expandedHeight
                , "UInt", 0x0002 | 0x0004 | 0x0010 | 0x4000)
        }
    }

    ; ========== 宏执行逻辑 ==========

    OnButtonClick(macroIndex) {
        try {
            tableItem := MySoftData.TableInfo[4]
            if (tableItem.ForbidArr[macroIndex])
                return

            if (!tableItem.MacroArr[macroIndex] || tableItem.MacroArr[macroIndex] == "")
                return

            if (this.IsMacroRunning(macroIndex)) {
                this.StopMacro(macroIndex)
            } else {
                this.StartMacro(macroIndex)
            }

            ; 点击后面板抢走了焦点 → 立即将焦点还给目标窗口
            this.RestoreTargetFocus(macroIndex)
        }
        catch as e {
        }
    }

    ; 恢复目标窗口的前台状态（点击面板按钮后调用）
    RestoreTargetFocus(macroIndex) {
        for foldIndex, panelInfo in this.PanelMap {
            if (!panelInfo.btnItems || !panelInfo.targetHwnd)
                continue
            for item in panelInfo.btnItems {
                if (item.macroIndex == macroIndex) {
                    if (panelInfo.targetHwnd && DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd))
                        WinActivate("ahk_id " panelInfo.targetHwnd)
                    return
                }
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
                        } else if (UIMacroGui.StateImages.Has(state)) {
                            imgPath := UIMacroGui.StateImages[state]
                            panelInfo.ui.Update(stateName, "Visibility", "Visible")
                            panelInfo.ui.Update(stateName, "Source", imgPath)
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
                    return
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

    GetWindowRectCoords(hwnd) {
        rect := Buffer(16, 0)
        DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        left := NumGet(rect, 0, "Int")
        top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int")
        bottom := NumGet(rect, 12, "Int")
        return Map("left", left, "top", top, "right", right, "bottom", bottom)
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
