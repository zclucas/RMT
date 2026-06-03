#Requires AutoHotkey v2.0
#SingleInstance Force

global scriptDir := A_ScriptDir
SetWorkingDir(scriptDir "\..\..")

#include lib\XAML_GUI.ahk
#include lib\XAML_Generator.ahk
#include lib\XAML_Host.ahk

XAMLHost.Prewarm()

global targetB_Hwnd := 0
global targetB_Title := ""
global floatingPanel := ""
global isSelectingWindow := false
global selectorUiRef := ""
global g_panelReady := false
global g_isDragging := false
global g_offsetX := 50
global g_offsetY := 50
global g_screenMode := false
global g_panelVisible := true

ShowWindowSelector() {
    selector := XAML_GUI("选择目标窗口", { 
        TitleBarHeight: 36, 
        Width: 360, 
        Height: 300,
        AppIcon: false 
    })
    
    content := selector.main.Add("StackPanel").Grid_Row(1).Margin("30,16,30,16")
    
    content.Add("TextBlock").Text("悬浮面板模式")
        .Foreground("#FFFFFF").FontSize(16).FontWeight("Bold").Margin("0,0,0,6")
    
    modeRow := content.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,14")
    global chkScreenMode := modeRow.Add("CheckBox").Name("ChkScreenMode").Content("🖥️ 屏幕悬浮（不跟随窗口）")
        .Foreground("#CCCCCC").FontSize(12)
    
    content.Add("TextBlock").Name("TxtFollowHint").Text("📌 跟随模式：按住 Ctrl+左键 点击目标窗口`n面板将跟随目标窗口移动（可拖拽调整位置）")
        .Foreground("#AAAAAA").FontSize(11).TextWrapping("Wrap").Margin("0,0,0,14")
    
    global txtBoundInfo := content.Add("TextBlock").Name("TxtBoundInfo").Text("⏳ 未选择")
        .Foreground("#FFFFFF").FontSize(12).FontWeight("SemiBold")
    
    btnRow := content.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,8,0,0")
    
    btnSelect := btnRow.Add("Button").Name("BtnSelectWindow").Content("🖱️ 选择窗口").Width(120).Height(34)
    btnSelect.Background("#FF0078D7").Foreground("#FFF")
    
    btnCreate := btnRow.Add("Button").Name("BtnCreatePanel").Content("✨ 创建面板").Width(120).Height(34).Margin("10,0,0,0")
    btnCreate.Background("#FF333333").Foreground("#FFF")
    
    ui := selector.Compile()
    global selectorUi := ui
    
    ui.OnEvent("BtnSelectWindow", "Click", OnBtnSelectClick)
    ui.OnEvent("BtnCreatePanel", "Click", OnBtnCreateClick)
    ui.OnEvent("ChkScreenMode", "Click", OnModeCheckChange)
    
    selector.Show()
}

OnBtnSelectClick(*) {
    StartWindowSelection(selectorUi)
}

OnModeCheckChange(*) {
    global g_screenMode := !g_screenMode
    try {
        if (g_screenMode) {
            selectorUi.Update("TxtBoundInfo", "Text", "🖥️ 屏幕悬浮模式")
            selectorUi.Update("TxtFollowHint", "Text", "🖥️ 屏幕悬浮模式：面板固定在屏幕上，可自由拖拽调整位置")
            selectorUi.Update("BtnSelectWindow", "IsEnabled", "False")
        } else {
            selectorUi.Update("TxtBoundInfo", "Text", "⏳ 未选择")
            selectorUi.Update("TxtFollowHint", "Text", "📌 跟随模式：按住 Ctrl+左键 点击目标窗口`n面板将跟随目标窗口移动（可拖拽调整位置）")
            selectorUi.Update("BtnSelectWindow", "IsEnabled", "True")
        }
    }
}

OnBtnCreateClick(*) {
    if (g_screenMode) {
        try selectorUi.appWindow.Destroy()
        Sleep(200)
        CreateScreenFloatingPanel()
    } else {
        if (!targetB_Hwnd) {
            try selectorUi.Update("TxtBoundInfo", "Text", "❌ 请先选择窗口！")
            return
        }
        
        try selectorUi.appWindow.Destroy()
        Sleep(200)
        CreateFloatingPanel()
    }
}

StartWindowSelection(uiInstance) {
    global isSelectingWindow, selectorUiRef
    if (isSelectingWindow)
        return
    
    isSelectingWindow := true
    selectorUiRef := uiInstance
    ToolTip("按住 Ctrl + 左键点击目标窗口`n(按 Esc 取消)", A_ScreenWidth//2, A_ScreenHeight//3)
    Hotkey("^LButton", OnSelectHotkey, "On")
}

OnSelectHotkey(*) {
    global isSelectingWindow, selectorUiRef, targetB_Hwnd, targetB_Title
    
    if (!isSelectingWindow || !selectorUiRef)
        return
    
    Hotkey("^LButton", "Off")
    ToolTip()
    
    MouseGetPos(&mx, &my, &hwndUnderMouse)
    
    if (!hwndUnderMouse) {
        isSelectingWindow := false
        try selectorUiRef.Update("TxtBoundInfo", "Text", "❌ 未检测到窗口")
        return
    }
    
    if (hwndUnderMouse == selectorUiRef.wpfHwnd) {
        isSelectingWindow := false
        try selectorUiRef.Update("TxtBoundInfo", "Text", "❌ 不能选自身！")
        return
    }
    
    winTitle := WinGetTitle("ahk_id " hwndUnderMouse)
    if (winTitle == "" || winTitle == "Program Manager") {
        isSelectingWindow := false
        try selectorUiRef.Update("TxtBoundInfo", "Text", "❌ 无效窗口")
        return
    }
    
    targetB_Hwnd := hwndUnderMouse
    targetB_Title := winTitle
    isSelectingWindow := false
    
    displayTitle := StrLen(winTitle) > 35 ? SubStr(winTitle, 1, 35) "..." : winTitle
    try selectorUiRef.Update("TxtBoundInfo", "Text", "✅ " displayTitle)
}

CancelSelection() {
    global isSelectingWindow
    if (!isSelectingWindow)
        return
    Hotkey("^LButton", "Off")
    ToolTip()
    isSelectingWindow := false
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


MovePanel(hwnd, x, y) {
    ownerHwnd := g_screenMode ? 0 : targetB_Hwnd
    DllCall("user32\SetWindowPos"
        , "Ptr", hwnd
        , "Ptr", ownerHwnd
        , "Int", x, "Int", y
        , "Int", 0, "Int", 0
        , "UInt", 0x0001 | 0x0004 | 0x0010 | 0x4000)
}


CreateFloatingPanel() {
    pw := 120
    
    titleBarH := 26
    toggleBtnH := 28
    btnItemH := 28
    btnGap := 2
    bodyMarginV := 6
    wpfBorderPad := 22
    
    btnItems := [
        {name: "Btn1", text: "操作 1", handler: "OnBtn1Click"},
        {name: "Btn2", text: "操作 2", handler: "OnBtn2Click"},
        {name: "Btn3", text: "操作 3", handler: "OnBtn3Click"},
        {name: "Btn4", text: "操作 4", handler: "OnBtn4Click"},
    ]
    
    contentH := btnItems.Length * btnItemH + (btnItems.Length - 1) * btnGap + bodyMarginV
    ph := titleBarH + toggleBtnH + contentH + wpfBorderPad
    
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    initX := mx
    initY := my
    
global g_isCollapsed := false
global g_expandedHeight
global g_collapsedHeight
g_expandedHeight := ph
g_collapsedHeight := titleBarH + toggleBtnH + wpfBorderPad + 4
    
    main := XAML_Generator("Grid")
    main.Background("{x:Null}")
    main.Rows(titleBarH, "Auto", "*")
    
    titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("#88000000")
    titleBar.Add("TextBlock").Name("Row1").Text("状态").Foreground("#FFFFFF").FontSize(11)
        .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")
    
    toggleBtn := main.Add("Button").Grid_Row(1).Name("BtnToggle").Content("▼ 收起").Height(toggleBtnH)
        .HorizontalAlignment("Center").Margin("0,0,0,0").FontSize(9).Foreground("#999")
    toggleBtn.Background("#00000000").BorderBrush("#00000000")
    
    body := main.Add("StackPanel").Grid_Row(2).Name("BodyPanel").Margin("4,2,4,4")
    
    for i, item in btnItems {
        isLast := (i == btnItems.Length)
        marginStr := isLast ? "" : ",0," btnGap
        btn := body.Add("Button").Name(item.name).Content(item.text).Height(btnItemH)
            .Margin("0,0" marginStr)
        btn.Background("#333333").Foreground("#DDD").FontSize(10)
    }
    
    tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
    ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
    
    ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" Width="' pw '" Height="' ph '"')
    ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
    ui.xaml := StrReplace(ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
    ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="{x:Null}"')
    
    ui.xaml := StrReplace(ui.xaml, '%resources%', '<SolidColorBrush x:Key="TextMain" Color="White"/><CornerRadius x:Key="WindowRadius">8</CornerRadius><CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>')
    ui.xaml := StrReplace(ui.xaml, '%components%', '')
    
    for item in btnItems
        ui.OnEvent(item.name, "Click", %item.handler%)
    
    ui.OnEvent("BtnToggle", "Click", OnToggleClick)
    
    global g_panelReady := false
    global floatingPanel := ui
    
    ui.Show()
    
    loop 10 {
        if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
            WinActivate("ahk_id " ui.wpfHwnd)
            break
        }
        Sleep(50)
    }
    
    WaitForHwnd()
}

CreateScreenFloatingPanel() {
    pw := 120
    
    titleBarH := 26
    toggleBtnH := 28
    btnItemH := 28
    btnGap := 2
    bodyMarginV := 6
    wpfBorderPad := 22
    
    btnItems := [
        {name: "Btn1", text: "操作 1", handler: "OnBtn1Click"},
        {name: "Btn2", text: "操作 2", handler: "OnBtn2Click"},
        {name: "Btn3", text: "操作 3", handler: "OnBtn3Click"},
        {name: "Btn4", text: "操作 4", handler: "OnBtn4Click"},
    ]
    
    contentH := btnItems.Length * btnItemH + (btnItems.Length - 1) * btnGap + bodyMarginV
    ph := titleBarH + toggleBtnH + contentH + wpfBorderPad
    
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    initX := mx
    initY := my
    
global g_isCollapsed := false
global g_expandedHeight
global g_collapsedHeight
g_expandedHeight := ph
g_collapsedHeight := titleBarH + toggleBtnH + wpfBorderPad + 4
    
    main := XAML_Generator("Grid")
    main.Background("{x:Null}")
    main.Rows(titleBarH, "Auto", "*")
    
    titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("#88000000")
    titleBar.Add("TextBlock").Name("Row1").Text("🖥️ 悬浮").Foreground("#FFFFFF").FontSize(11)
        .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")
    
    toggleBtn := main.Add("Button").Grid_Row(1).Name("BtnToggle").Content("▼ 收起").Height(toggleBtnH)
        .HorizontalAlignment("Center").Margin("0,0,0,0").FontSize(9).Foreground("#999")
    toggleBtn.Background("#00000000").BorderBrush("#00000000")
    
    body := main.Add("StackPanel").Grid_Row(2).Name("BodyPanel").Margin("4,2,4,4")
    
    for i, item in btnItems {
        isLast := (i == btnItems.Length)
        marginStr := isLast ? "" : ",0," btnGap
        btn := body.Add("Button").Name(item.name).Content(item.text).Height(btnItemH)
            .Margin("0,0" marginStr)
        btn.Background("#333333").Foreground("#DDD").FontSize(10)
    }
    
    tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
    ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
    
    ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" Width="' pw '" Height="' ph '"')
    ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
    ui.xaml := StrReplace(ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
    ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="{x:Null}"')
    
    ui.xaml := StrReplace(ui.xaml, '%resources%', '<SolidColorBrush x:Key="TextMain" Color="White"/><CornerRadius x:Key="WindowRadius">8</CornerRadius><CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>')
    ui.xaml := StrReplace(ui.xaml, '%components%', '')
    
    for item in btnItems
        ui.OnEvent(item.name, "Click", %item.handler%)
    
    ui.OnEvent("BtnToggle", "Click", OnToggleClick)
    
    global g_panelReady := false
    global floatingPanel := ui
    
    ui.Show()
    
    loop 10 {
        if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
            WinActivate("ahk_id " ui.wpfHwnd)
            break
        }
        Sleep(50)
    }
    
    WaitForHwnd()
}

WaitForHwnd() {
    loop 50 {
        if (floatingPanel.HasProp("wpfHwnd") && floatingPanel.wpfHwnd) {
            global g_panelReady := true
            OnPanelReady()
            return
        }
        Sleep(50)
    }
}

OnPanelReady() {
    if (targetB_Hwnd) {
        try floatingPanel.Update("Window", "NativeOwner", String(targetB_Hwnd))
    }
    
    hwnd := floatingPanel.wpfHwnd
    if (hwnd) {
        rect := GetWindowRectCoords(hwnd)
        global g_expandedHeight := rect["bottom"] - rect["top"]
        
        exStyle := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
        DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int"
            , (exStyle | 0x80 | 0x08000000) & ~0x40000)
        
        if (g_screenMode) {
            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        } else {
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0002 | 0x0001 | 0x0004 | 0x0010 | 0x0020)
        }
    }
    
    FollowTarget()
    SetTimer(FollowTarget, 50)
}

FollowTarget() {
    if (!g_panelReady)
        return
    hwnd := floatingPanel.wpfHwnd
    if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
        return

    if (g_screenMode) {
        if (GetKeyState("LButton", "P")) {
            MouseGetPos(&mx, &my, &hwndUnderMouse)
            if (hwndUnderMouse == hwnd) {
                global g_isDragging := true
            }
        } else if (g_isDragging) {
            global g_isDragging := false
        }
        try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        return
    }
    
    if (!targetB_Hwnd)
        return
    if (!DllCall("user32\IsWindow", "Ptr", targetB_Hwnd))
        return
    
    if (GetKeyState("LButton", "P")) {
        MouseGetPos(&mx, &my, &hwndUnderMouse)
        if (hwndUnderMouse == hwnd) {
            global g_isDragging := true
            return
        }
    }
    
    if (g_isDragging) {
        panelRect := GetWindowRectCoords(hwnd)
        targetRect := GetWindowRectCoords(targetB_Hwnd)
        global g_offsetX := panelRect["left"] - targetRect["left"]
        global g_offsetY := panelRect["top"] - targetRect["top"]
        global g_isDragging := false
        return
    }
    
    rect := GetWindowRectCoords(targetB_Hwnd)
    newX := rect["left"] + g_offsetX
    newY := rect["top"] + g_offsetY
    
    MovePanel(hwnd, newX, newY)
}

OnBtn1Click(*) {
    MsgBox("操作 1 被点击", "RMT Panel", "64 T1")
}

OnBtn2Click(*) {
    MsgBox("操作 2 被点击", "RMT Panel", "64 T1")
}

OnBtn3Click(*) {
    MsgBox("操作 3 被点击", "RMT Panel", "64 T1")
}

OnBtn4Click(*) {
    MsgBox("操作 4 被点击", "RMT Panel", "64 T1")
}

OnToggleClick(*) {
    global g_isCollapsed, g_expandedHeight, g_collapsedHeight
    if (!floatingPanel || !g_panelReady)
        return
    
    hwnd := floatingPanel.wpfHwnd
    if (!hwnd)
        return
    
    g_isCollapsed := !g_isCollapsed
    curRect := GetWindowRectCoords(hwnd)
    curW := curRect["right"] - curRect["left"]
    
    if (g_isCollapsed) {
        try floatingPanel.Update("BodyPanel", "Visibility", "Collapsed")
        try floatingPanel.Update("BtnToggle", "Content", "▲ 展开")
        DllCall("user32\SetWindowPos"
            , "Ptr", hwnd, "Ptr", 0
            , "Int", 0, "Int", 0
            , "Int", curW, "Int", g_collapsedHeight
            , "UInt", 0x0002 | 0x0004 | 0x0010 | 0x4000)
    } else {
        try floatingPanel.Update("BodyPanel", "Visibility", "Visible")
        try floatingPanel.Update("BtnToggle", "Content", "▼ 收起")
        DllCall("user32\SetWindowPos"
            , "Ptr", hwnd, "Ptr", 0
            , "Int", 0, "Int", 0
            , "Int", curW, "Int", g_expandedHeight
            , "UInt", 0x0002 | 0x0004 | 0x0010 | 0x4000)
    }
}

TogglePanelVisibility() {
    global g_panelVisible, floatingPanel, g_panelReady

    if (!floatingPanel || !g_panelReady) {
        CreateScreenFloatingPanel()
        return
    }

    g_panelVisible := !g_panelVisible
    hwnd := floatingPanel.wpfHwnd
    if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
        return

    if (g_panelVisible) {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", mx, "Int", my, "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010)
        DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 1)  ; SW_SHOW
    } else {
        DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 0)  ; SW_HIDE
    }
}

ClosePanel() {
    SetTimer(FollowTarget, 0)
    if (floatingPanel) {
        try floatingPanel.Update("Window", "Close", "")
        floatingPanel := ""
    }
    ExitApp()
}

ShowWindowSelector()

Persistent()

F2::TogglePanelVisibility()

Escape::
{
    CancelSelection()
}
