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
        this.PanelMap := Map()       ; foldIndex -> panelInfo {ui, wpfHwnd, visible, ...}
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
        this.HideAllPanels()
        for macroIndex in this.RunningMap {
            this.StopMacro(macroIndex)
        }
        for macroIndex in this.RecoverTimers {
            this.CancelRecoverTimer(macroIndex)
        }
    }

    ; ========== 面板管理 ==========

    ; 为指定模块创建悬浮面板
    CreatePanel(foldIndex) {
        tableItem := MySoftData.TableInfo[4]
        if (!tableItem || !tableItem.FoldInfo)
            return

        foldInfo := tableItem.FoldInfo
        if (foldIndex > foldInfo.RemarkArr.Length)
            return

        ; 如果已有面板，先销毁
        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        indexSpanStr := foldInfo.IndexSpanArr[foldIndex]
        indexSpan := StrSplit(indexSpanStr, "-")
        if (!IsInteger(indexSpan[1]) || !IsInteger(indexSpan[2]))
            return

        startIndex := Integer(indexSpan[1])
        endIndex := Integer(indexSpan[2])

        ; 收集该模块下所有宏项
        btnItems := []
        Loop (endIndex - startIndex + 1) {
            macroIndex := startIndex + A_Index - 1
            if (macroIndex > tableItem.RemarkArr.Length)
                continue
            if (tableItem.ForbidArr.Has(macroIndex) && tableItem.ForbidArr[macroIndex])
                continue
            if (!tableItem.MacroArr.Has(macroIndex) || tableItem.MacroArr[macroIndex] == "")
                continue

            remarkValue := tableItem.RemarkArr.Has(macroIndex) ? tableItem.RemarkArr[macroIndex] : ""
            iconValue := tableItem.UIIconArr.Has(macroIndex) ? tableItem.UIIconArr[macroIndex] : ""
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

        ; 获取目标窗口信息（使用第一个有窗口信息的宏）
        targetHwnd := 0
        isScreenMode := false
        for idx, item in btnItems {
            mi := item.macroIndex
            if (tableItem.UIWindowArr.Has(mi) && tableItem.UIWindowArr[mi] != "") {
                frontValue := tableItem.UIWindowArr[mi]
                paramStr := GetParamsWinInfoStr(frontValue)
                if (paramStr != "") {
                    hwndList := WinGetList(paramStr)
                    if (hwndList.Length > 0 && hwndList[1])
                        targetHwnd := hwndList[1]
                }
                break
            }
        }

        ; 如果没有找到目标窗口，使用屏幕模式
        if (!targetHwnd)
            isScreenMode := true

        ; 窗口跟随模式：检查目标窗口是否有效且激活
        if (!isScreenMode && targetHwnd) {
            if (!DllCall("user32\IsWindow", "Ptr", targetHwnd))
                return
            activeHwnd := WinGetID("A")
            if (activeHwnd != targetHwnd)
                return
        }

        ; 构建XAML面板
        panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode)
        if (!panelInfo)
            return

        this.PanelMap.Set(foldIndex, panelInfo)

        ; 等待窗口就绪后设置属性
        this.WaitForPanelReady(foldIndex, targetHwnd, isScreenMode)
    }

    BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode) {
        pw := 130
        titleBarH := 26
        toggleBtnH := 28
        btnItemH := 34
        btnGap := 2
        bodyMarginV := 6
        wpfBorderPad := 22

        ; 模块备注作为标题
        tableItem := MySoftData.TableInfo[4]
        foldRemark := tableItem.FoldInfo.RemarkArr.Has(foldIndex) ? tableItem.FoldInfo.RemarkArr[foldIndex] : GetLang("面板") foldIndex

        contentH := btnItems.Length * btnItemH + (btnItems.Length - 1) * btnGap + bodyMarginV
        ph := titleBarH + toggleBtnH + contentH + wpfBorderPad

        ; 计算初始位置：鼠标当前位置（使用屏幕坐标）
        CoordMode("Mouse", "Screen")
        MouseGetPos(&initX, &initY)

        ; 计算相对于目标窗口的偏移量（用于窗口跟随模式）
        offsetX := initX
        offsetY := initY
        if (!isScreenMode && targetHwnd) {
            try {
                rect := this.GetWindowRectCoords(targetHwnd)
                offsetX := initX - rect["left"]
                offsetY := initY - rect["top"]
            }
        }

        g_isCollapsed := false
        g_collapsedHeight := titleBarH + toggleBtnH + wpfBorderPad + 4
        g_expandedHeight := ph

        main := XAML_Generator("Grid")
        main.Background("{x:Null}")
        main.Rows(titleBarH, "Auto", "*")

        ; 标题栏
        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("#88000000")
        titleBar.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground("#FFFFFF").FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")

        ; 收起/展开按钮
        toggleBtn := main.Add("Button").Grid_Row(1).Name("BtnToggle").Content("▼ 收起").Height(toggleBtnH)
            .HorizontalAlignment("Center").Margin("0,0,0,0").FontSize(9).Foreground("#999")
        toggleBtn.Background("#00000000").BorderBrush("#00000000")

        ; 按钮区域
        body := main.Add("StackPanel").Grid_Row(2).Name("BodyPanel").Margin("4,2,4,4")

        for i, item in btnItems {
            isLast := (i == btnItems.Length)
            marginStr := isLast ? "" : ",0," btnGap

            btn := body.Add("Button").Name(item.name).Height(btnItemH)
                .Margin("0,0" marginStr)
            btn.Background("#333333").Foreground("#DDD").FontSize(11)
            btn.HorizontalAlignment("Stretch")

            ; 按钮内容布局：[状态色点] [图标] [文字]
            sp := btn.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")

            ; 左侧状态色点（运行状态指示）
            sp.Add("Image").Name(item.name "_State")
                .Width(10).Height(10).VerticalAlignment("Center").Margin("0,0,4,0")

            ; 用户设置的图标
            if (item.icon != "") {
                fullIconPath := this.GetFullIconPath(item.icon)
                if (fullIconPath != "" && FileExist(fullIconPath)) {
                    sp.Add("Image").Name(item.name "_Img")
                        .Source(fullIconPath).Width(18).Height(18).VerticalAlignment("Center").Margin("0,0,6,0")
                }
            }

            sp.Add("TextBlock").Text(item.text).VerticalAlignment("Center").Foreground("#DDD").FontSize(11)
        }

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" Width="' pw '" Height="' ph '"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
        ui.xaml := StrReplace(ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
        ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="{x:Null}"')

        ui.xaml := StrReplace(ui.xaml, '%resources%', '<SolidColorBrush x:Key="TextMain" Color="White"/><CornerRadius x:Key="WindowRadius">8</CornerRadius><CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>')
        ui.xaml := StrReplace(ui.xaml, '%components%', '')

        ; 绑定按钮事件
        for i, item in btnItems {
            mi := item.macroIndex
            ui.OnEvent(item.name, "Click", (*) => this.OnButtonClick(mi))
        }

        ui.OnEvent("BtnToggle", "Click", (*) => this.OnToggleClick(foldIndex))

        ui.Show()

        ; 等待wpfHwnd就绪
        loop 20 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
                WinActivate("ahk_id " ui.wpfHwnd)
                break
            }
            Sleep(50)
        }

        return {
            ui: ui,
            wpfHwnd: ui.wpfHwnd ? ui.wpfHwnd : 0,
            foldIndex: foldIndex,
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            visible: true,
            isCollapsed: false,
            expandedHeight: g_expandedHeight,
            collapsedHeight: g_collapsedHeight,
            btnItems: btnItems,
            offsetX: offsetX,
            offsetY: offsetY,
            isDragging: false
        }
    }

    WaitForPanelReady(foldIndex, targetHwnd, isScreenMode) {
        panelInfo := this.PanelMap.Has(foldIndex) ? this.PanelMap[foldIndex] : ""
        if (!panelInfo)
            return

        loop 30 {
            if (panelInfo.ui && panelInfo.ui.HasProp("wpfHwnd") && panelInfo.ui.wpfHwnd) {
                hwnd := panelInfo.ui.wpfHwnd
                panelInfo.wpfHwnd := hwnd

                ; 设置窗口样式
                exStyle := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
                DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int"
                    , (exStyle | 0x80 | 0x08000000) & ~0x40000)

                if (isScreenMode) {
                    WinSetAlwaysOnTop(1, "ahk_id " hwnd)
                } else {
                    ; 窗口跟随模式：设置owner关系
                    if (targetHwnd) {
                        try panelInfo.ui.Update("Window", "NativeOwner", String(targetHwnd))
                    }
                    DllCall("user32\SetWindowPos"
                        , "Ptr", hwnd, "Ptr", 0
                        , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                        , "UInt", 0x0002 | 0x0001 | 0x0004 | 0x0010 | 0x0020)
                }

                break
            }
            Sleep(50)
        }
    }

    ; 切换面板可见性（由触发键调用）
    TogglePanel(foldIndex) {
        if (!this.PanelMap.Has(foldIndex)) {
            this.CreatePanel(foldIndex)
            return
        }

        panelInfo := this.PanelMap[foldIndex]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return

        ; 窗口跟随模式：检查目标窗口是否有效且激活
        if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
            if (!DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd))
                return
            activeHwnd := WinGetID("A")
            if (activeHwnd != panelInfo.targetHwnd)
                return
        }

        try {
            if (panelInfo.visible) {
                DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 0)  ; SW_HIDE
                panelInfo.visible := false
            } else {
                ; 显示面板：用 SetWindowPos 一步完成定位+显示（SWP_SHOWWINDOW）
                CoordMode("Mouse", "Screen")
                MouseGetPos(&mx, &my)
                DllCall("user32\SetWindowPos"
                    , "Ptr", panelInfo.wpfHwnd, "Ptr", 0
                    , "Int", mx, "Int", my
                    , "Int", 0, "Int", 0
                    , "UInt", 0x0001 | 0x0004 | 0x0040)  ; SWP_NOSIZE | SWP_NOZORDER | SWP_SHOWWINDOW
                ; 更新相对于目标窗口的偏移量（窗口跟随模式）
                if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                    try {
                        rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                        panelInfo.offsetX := mx - rect["left"]
                        panelInfo.offsetY := my - rect["top"]
                    }
                }
                if (panelInfo.isScreenMode) {
                    WinSetAlwaysOnTop(1, "ahk_id " panelInfo.wpfHwnd)
                }
                WinActivate("ahk_id " panelInfo.wpfHwnd)
                panelInfo.visible := true
            }
        }
    }

    ; 显示指定模块的面板
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

    ; 销毁指定模块的面板
    DestroyPanel(foldIndex) {
        if (!this.PanelMap.Has(foldIndex))
            return

        panelInfo := this.PanelMap[foldIndex]
        if (panelInfo.ui) {
            try {
                panelInfo.ui.Update("Window", "Close", "")
            }
        }
        this.PanelMap.Delete(foldIndex)
    }

    CheckAllPanels() {
        for foldIndex, panelInfo in this.PanelMap {
            if (!panelInfo.ui || !panelInfo.wpfHwnd)
                continue
            if (!panelInfo.visible)
                continue

            hwnd := panelInfo.wpfHwnd

            if (panelInfo.isScreenMode) {
                ; 屏幕模式：检测拖拽 + 保持置顶
                if (GetKeyState("LButton", "P")) {
                    MouseGetPos(&mx, &my, &hwndUnderMouse)
                    if (hwndUnderMouse == hwnd) {
                        panelInfo.isDragging := true
                    }
                } else if (panelInfo.isDragging) {
                    panelInfo.isDragging := false
                }
                WinSetAlwaysOnTop(1, "ahk_id " hwnd)
            } else {
                ; 窗口跟随模式
                if (!panelInfo.targetHwnd)
                    continue
                if (!DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd))
                    continue

                ; 拖拽检测：用户拖拽面板时跳过跟随移动
                if (GetKeyState("LButton", "P")) {
                    MouseGetPos(&mx, &my, &hwndUnderMouse)
                    if (hwndUnderMouse == hwnd) {
                        panelInfo.isDragging := true
                        this.DoFollowTarget(panelInfo, false)  ; 不移动，仅更新z-order
                        continue
                    }
                }

                ; 拖拽结束后，重新计算相对偏移
                if (panelInfo.isDragging) {
                    panelRect := this.GetWindowRectCoords(hwnd)
                    targetRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                    panelInfo.offsetX := panelRect["left"] - targetRect["left"]
                    panelInfo.offsetY := panelRect["top"] - targetRect["top"]
                    panelInfo.isDragging := false
                }

                this.DoFollowTarget(panelInfo, true)
            }
        }
    }

    DoFollowTarget(panelInfo, doMove := true) {
        if (!panelInfo.wpfHwnd || !panelInfo.targetHwnd)
            return

        rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
        newX := rect["left"] + panelInfo.offsetX
        newY := rect["top"] + panelInfo.offsetY

        ; 使用 MovePanel 模式：hWndInsertAfter 设为目标窗口（保持 z-order 关系）
        DllCall("user32\SetWindowPos"
            , "Ptr", panelInfo.wpfHwnd
            , "Ptr", panelInfo.targetHwnd   ; owner/insertAfter = 目标窗口
            , "Int", newX, "Int", newY
            , "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010 | 0x4000)
    }

    FollowTarget(panelInfo) {
        ; 兼容旧调用，委托给 DoFollowTarget
        this.DoFollowTarget(panelInfo, true)
    }

    HideAllPanels() {
        for foldIndex, panelInfo in this.PanelMap {
            try {
                if (panelInfo.ui)
                    panelInfo.ui.Update("Window", "Close", "")
            }
        }
        this.PanelMap.Clear()
    }

    OnToggleClick(foldIndex) {
        if (!this.PanelMap.Has(foldIndex))
            return

        panelInfo := this.PanelMap[foldIndex]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return

        panelInfo.isCollapsed := !panelInfo.isCollapsed
        hwnd := panelInfo.wpfHwnd

        curRect := this.GetWindowRectCoords(hwnd)
        curW := curRect["right"] - curRect["left"]

        if (panelInfo.isCollapsed) {
            try panelInfo.ui.Update("BodyPanel", "Visibility", "Collapsed")
            try panelInfo.ui.Update("BtnToggle", "Content", "▲ 展开")
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0
                , "Int", curW, "Int", panelInfo.collapsedHeight
                , "UInt", 0x0002 | 0x0004 | 0x0010 | 0x4000)
        } else {
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
            if (tableItem.ForbidArr.Has(macroIndex) && tableItem.ForbidArr[macroIndex])
                return

            if (!tableItem.MacroArr.Has(macroIndex) || tableItem.MacroArr[macroIndex] == "")
                return

            if (this.IsMacroRunning(macroIndex)) {
                this.StopMacro(macroIndex)
            } else {
                this.StartMacro(macroIndex)
            }
        }
        catch as e {
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

    ; 更新指定宏按钮的状态色点
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

    RefreshPanels() {
        this.HideAllPanels()
    }

    GetFullIconPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon" path
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

    __Delete() {
        this.StopMonitor()
    }
}
