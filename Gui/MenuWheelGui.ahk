#Requires AutoHotkey v2.0

class MenuWheelGui {
    static Hotkeys := ["1", "2", "3", "4", "5", "6", "7", "8"]

    __new() {
        this.MenuIndex := 1
        this.Gui := ""
        this.isOpen := false
        this.sectors := []
        this.hoveredIdx := 0
        this.closed := false
        this.showTooltip := true
        this.selectMode := 1
        this.swipe := ""
        this.swipeTriggered := false
    }

    ShowGui(MenuIndex) {
        PreviousActiveWindow := WinExist("A")
        this.ShowRadialMenu(MenuIndex)
        try {
            WinActivate(PreviousActiveWindow)
        }
    }

    ShowRadialMenu(MenuIndex) {
        this.MenuIndex := MenuIndex
        this.showTooltip := !!MySoftData.MenuWheelShowTooltip
        this.selectMode := MySoftData.HasProp("MenuWheelSelectMode") ? MySoftData.MenuWheelSelectMode : 2
        if (this.isOpen) {          ; 已有轮盘？先自清
            this.closed := true
            this._Cleanup()         ; 关闭旧窗 + sectors:=[] + 重置状态
        }
        
        tableItem := MySoftData.TableInfo[3]

        ; 从 WheelThemes.ini 读取当前主题的颜色值
        themeKey := MySoftData.HasProp("MenuWheelTheme") ? MySoftData.MenuWheelTheme : "Default"
        themesIniPath := A_WorkingDir "\Setting\WheelThemes.ini"
        themeSection := "Theme_" themeKey
        modNormalFill := IniRead(themesIniPath, themeSection, "NormalFill", "#FFFCFCFC")
        modNormalStroke := IniRead(themesIniPath, themeSection, "NormalStroke", "#FFC6DFFC")
        modHoverFill := IniRead(themesIniPath, themeSection, "HoverFill", "#FFFDE8E8")
        modHoverStroke := IniRead(themesIniPath, themeSection, "HoverStroke", "#FFE81123")
        modSelectedFill := IniRead(themesIniPath, themeSection, "SelectedFill", "#FF0078D7")
        modSelectedStroke := IniRead(themesIniPath, themeSection, "SelectedStroke", "#FFFFFFFF")
        modNormalText := IniRead(themesIniPath, themeSection, "NormalText", "#CC333333")
        modHoverText := IniRead(themesIniPath, themeSection, "HoverText", "#FFE81123")
        modSelectedText := IniRead(themesIniPath, themeSection, "SelectedText", "#FFFFFFFF")
        modSwipeLine := IniRead(themesIniPath, themeSection, "SwipeLineColor", "#3A88F5")

        items := []
        loop 8 {
            macroIndex := (MenuIndex - 1) * 8 + A_Index
            remark := tableItem.RemarkArr[macroIndex]
            btnName := remark != "" ? remark : "菜单" A_Index

            icoPath := tableItem.IcoPathArr[macroIndex]

            arcNr := A_Index
            h := MenuWheelGui._MakeCallback(this, arcNr, MenuIndex)

            items.Push({
                Name: btnName,
                Image: icoPath,
                Callback: h
            })
        }

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        if (MySoftData.FixedMenuWheel) {
            pt := Buffer(8, 0)
            NumPut("Int", mx, pt, 0)
            NumPut("Int", my, pt, 4)
            hwndMon := DllCall("user32\MonitorFromPoint", "Ptr", pt, "UInt", 2, "Ptr")
            monInfo := Buffer(40, 0)
            NumPut("UInt", 40, monInfo, 0)
            DllCall("user32\GetMonitorInfo", "Ptr", hwndMon, "Ptr", monInfo)
            monLeft := NumGet(monInfo, 4, "Int")
            monTop := NumGet(monInfo, 8, "Int")
            monRight := NumGet(monInfo, 12, "Int")
            monBottom := NumGet(monInfo, 16, "Int")
            mx := Round((monLeft + monRight) * 0.5)
            my := Round((monTop + monBottom) * 0.70)
        }

        wheelScale := Max(Min(MySoftData.MenuWheelScale, 200), 30) / 100.0
        this._BuildAndShow(items, mx, my, {
            Radius: Round(150 * wheelScale),
            InnerRadius: Round(60 * wheelScale),
            IconSize: Round(50 * wheelScale),
            FontSize: Max(Round(11 * wheelScale), 8),
            NormalFill: modNormalFill,
            NormalStroke: modNormalStroke,
            NormalText: modNormalText,
            NormalThickness: 1,
            HoverFill: modHoverFill,
            HoverStroke: modHoverStroke,
            HoverText: modHoverText,
            HoverThickness: 2,
            SelectedFill: modSelectedFill,
            SelectedStroke: modSelectedStroke,
            SelectedText: modSelectedText,
            SelectedThickness: 2,
            SwipeLineColor: modSwipeLine,
            IconPosRatio: 0.72,
            LabelPosRatio: 0.35,
            CenterPosRatio: 0.58
        })
        MySoftData.CurMenuWheelIndex := this.MenuIndex
    }

    static _MakeCallback(guiObj, arcNr, menuIdx) {
        return (idx, name) => guiObj.OnRadialMenuSelect(arcNr, menuIdx)
    }

    ToggleFunc(state) {
        if (this.selectMode == 2 && IsObject(this.swipe))
            this.swipe.Toggle(state)
    }

    OnSoftKey(key, isDown) {
        if (!isDown || !this.isOpen)
            return
        idx := Integer(key)
        if (idx >= 1 && idx <= MenuWheelGui.Hotkeys.Length && IsObject(this.ui))
            this.DoSelect(idx, "")
    }

    Close() {
        if (!this.isOpen)
            return
        this.closed := true
        this._Cleanup()
    }

    _BuildAndShow(items, x, y, options) {
        radius := options.HasProp("Radius") ? options.Radius : 150
        innerR := options.HasProp("InnerRadius") ? options.InnerRadius : Round(radius * 0.4)
        iconSize := options.HasProp("IconSize") ? options.IconSize : 50
        fontSize := options.HasProp("FontSize") ? options.FontSize : 11
        normalFill := options.HasProp("NormalFill") ? options.NormalFill : "#FFFCFCFC"
        normalStroke := options.HasProp("NormalStroke") ? options.NormalStroke : "#FFC6DFFC"
        hoverFill := options.HasProp("HoverFill") ? options.HoverFill : "#FFFDE8E8"
        hoverStroke := options.HasProp("HoverStroke") ? options.HoverStroke : "#FFE81123"
        selectedFill := options.HasProp("SelectedFill") ? options.SelectedFill : "#FF0078D7"
        selectedStroke := options.HasProp("SelectedStroke") ? options.SelectedStroke : "#FFFFFFFF"
        normalText := options.HasProp("NormalText") ? options.NormalText : "#CC333333"
        hoverText := options.HasProp("HoverText") ? options.HoverText : "#FFE81123"
        selectedText := options.HasProp("SelectedText") ? options.SelectedText : "#FFFFFFFF"
        normalThickness := options.HasProp("NormalThickness") ? options.NormalThickness : 1
        hoverThickness := options.HasProp("HoverThickness") ? options.HoverThickness : 2
        selectedThickness := options.HasProp("SelectedThickness") ? options.SelectedThickness : 2
        iconPosRatio := options.HasProp("IconPosRatio") ? options.IconPosRatio : 0.72
        labelPosRatio := options.HasProp("LabelPosRatio") ? options.LabelPosRatio : 0.35
        centerPosRatio := options.HasProp("CenterPosRatio") ? options.CenterPosRatio : 0.58
        swipeLineColor := options.HasProp("SwipeLineColor") ? options.SwipeLineColor : "#3A88F5"

        this.normalFill := normalFill
        this.normalStroke := normalStroke
        this.hoverFill := hoverFill
        this.hoverStroke := hoverStroke
        this.selectedFill := selectedFill
        this.selectedStroke := selectedStroke
        this.normalText := normalText
        this.hoverText := hoverText
        this.selectedText := selectedText
        this.normalThickness := normalThickness
        this.hoverThickness := hoverThickness
        this.selectedThickness := selectedThickness
        this.iconPosRatio := iconPosRatio
        this.labelPosRatio := labelPosRatio
        this.centerPosRatio := centerPosRatio
        this.swipeLineColor := swipeLineColor

        finalX := x
        finalY := y
        ptDpi := Buffer(8, 0)
        NumPut("Int", finalX, ptDpi, 0)
        NumPut("Int", finalY, ptDpi, 4)
        hwndMon := DllCall("user32\MonitorFromPoint", "Ptr", ptDpi, "UInt", 2, "Ptr")
        dpiX := 0, dpiY := 0
        DllCall("shcore\GetDpiForMonitor", "Ptr", hwndMon, "Int", 0, "UInt*", &dpiX, "UInt*", &dpiY)
        this.dpiScale := (dpiX > 0) ? (dpiX / 96.0) : (A_ScreenDPI / 96.0)

        itemCount := items.Length
        if (itemCount < 1)
            itemCount := 8
        if (itemCount > 16)
            itemCount := 16

        radius := Round(radius * this.dpiScale)
        innerR := Round(innerR * this.dpiScale)
        iconSize := Round(iconSize * this.dpiScale)
        fontSize := Round(fontSize * this.dpiScale)

        pad := Round(4 * this.dpiScale)
        cx := radius + pad
        cy := radius + pad
        winW := (radius + pad) * 2
        winH := (radius + pad) * 2

        winLeft := finalX / this.dpiScale - cx
        winTop := finalY / this.dpiScale - cy

        angleStep := 360.0 / itemCount

        Loop itemCount {
            idx := A_Index
            startAngle := (idx - 1) * angleStep - 90 - angleStep / 2
            endAngle := idx * angleStep - 90 - angleStep / 2
            midAngle := (startAngle + endAngle) / 2
            itemDef := items.Has(idx) ? items[idx] : {}
            name := itemDef.HasProp("Name") ? itemDef.Name : ("Sector" idx)
            imgPath := itemDef.HasProp("Image") ? itemDef.Image : ""
            cb := itemDef.HasProp("Callback") ? itemDef.Callback : 0
            this.sectors.Push(MenuWheelGui.WheelSector(idx, name, imgPath, cb, startAngle, endAngle, midAngle))
        }

        win := XAML_Generator("Window")
        win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
        win.Width(winW).Height(winH)
        win.Left(winLeft).Top(winTop)
        win.WindowStyle("None").AllowsTransparency("True").Background("{x:Null}")
        win.ShowInTaskbar("False").Topmost("True").ResizeMode("NoResize")
        win.WindowStartupLocation("Manual")
        ; 注入原生 WPF 悬停样式 + 圆角配置 + Tooltip 配置
        wheelStyle := '<CornerRadius x:Key="PanelRadius">0,0,0,0</CornerRadius>'
            . '<Style TargetType="{x:Type FrameworkElement}" x:Key="GlobalToolTipStyle">'
            . '  <Setter Property="ToolTipService.InitialShowDelay" Value="200"/>'
            . '</Style>'
            . '<Style x:Key="WheelWedgeStyle" TargetType="Path">'
            . '  <Setter Property="Fill" Value="' normalFill '"/>'
            . '  <Setter Property="Stroke" Value="' normalStroke '"/>'
            . '  <Setter Property="StrokeThickness" Value="' String(normalThickness) '"/>'
            . '  <Style.Triggers>'
            . '    <Trigger Property="IsMouseOver" Value="True">'
            . '      <Setter Property="Fill" Value="' hoverFill '"/>'
            . '      <Setter Property="Stroke" Value="' hoverStroke '"/>'
            . '      <Setter Property="StrokeThickness" Value="' String(hoverThickness) '"/>'
            . '    </Trigger>'
            . '  </Style.Triggers>'
            . '</Style>'
            . '<Style x:Key="CenterCircleStyle" TargetType="Ellipse">'
            . '  <Setter Property="Fill" Value="' normalFill '"/>'
            . '  <Setter Property="Stroke" Value="' normalStroke '"/>'
            . '  <Setter Property="StrokeThickness" Value="' String(normalThickness) '"/>'
            . '  <Style.Triggers>'
            . '    <Trigger Property="IsMouseOver" Value="True">'
            . '      <Setter Property="Fill" Value="' hoverFill '"/>'
            . '      <Setter Property="Stroke" Value="' hoverStroke '"/>'
            . '      <Setter Property="StrokeThickness" Value="' String(hoverThickness) '"/>'
            . '    </Trigger>'
            . '  </Style.Triggers>'
            . '</Style>'
            . '<Style x:Key="CloseIconStyle" TargetType="TextBlock">'
            . '  <Setter Property="Foreground" Value="' this.normalText '"/>'
            . '  <Style.Triggers>'
            . '    <DataTrigger Binding="{Binding IsMouseOver, ElementName=CenterCircle}" Value="True">'
            . '      <Setter Property="Foreground" Value="' this.hoverText '"/>'
            . '    </DataTrigger>'
            . '  </Style.Triggers>'
            . '</Style>'
        win.InjectResources(wheelStyle)

        canvas := win.Add("Canvas").Name("RootCanvas")
        canvas.Width(winW).Height(winH).Background("#00000000")

        Loop itemCount {
            idx := A_Index
            sec := this.sectors[idx]
            startRad := sec.StartAngle * 0.0174532925199433
            endRad := sec.EndAngle * 0.0174532925199433
            largeArc := angleStep > 180 ? "1" : "0"

            ix1 := Round(cx + innerR * Cos(startRad))
            iy1 := Round(cy + innerR * Sin(startRad))
            ox1 := Round(cx + radius * Cos(startRad))
            oy1 := Round(cy + radius * Sin(startRad))
            ox2 := Round(cx + radius * Cos(endRad))
            oy2 := Round(cy + radius * Sin(endRad))
            ix2 := Round(cx + innerR * Cos(endRad))
            iy2 := Round(cy + innerR * Sin(endRad))

            pathData := "M " ix1 "," iy1
                . " L " ox1 "," oy1
                . " A " radius "," radius " 0 " largeArc " 1 " ox2 "," oy2
                . " L " ix2 "," iy2
                . " A " innerR "," innerR " 0 " largeArc " 0 " ix1 "," iy1 " Z"

            wedge := canvas.Add("Path").Name("Wedge_" idx)
            wedge.Data(pathData).Style("{StaticResource WheelWedgeStyle}").Cursor("Hand")
            if (this.showTooltip)
                wedge.ToolTip(sec.Name)
        }

        centerCircle := canvas.Add("Ellipse").Name("CenterCircle")
        centerCircle.Width(innerR * 2).Height(innerR * 2)
        centerCircle.Canvas_Left(cx - innerR).Canvas_Top(cy - innerR)
        centerCircle.Style("{StaticResource CenterCircleStyle}").Cursor("Hand")
        if (this.showTooltip)
            centerCircle.ToolTip(GetLang("关闭"))

        closeIcon := canvas.Add("TextBlock").Name("CloseIcon")
        closeIcon.Text("✕").FontSize(Round(fontSize * 1.4)).FontWeight("SemiBold")
        closeIcon.Style("{StaticResource CloseIconStyle}").TextAlignment("Center").IsHitTestVisible("False")
        closeIcon.Canvas_Left(cx - fontSize * 0.6).Canvas_Top(cy - Round(fontSize * 0.7))

        Loop itemCount {
            idx := A_Index
            sec := this.sectors[idx]
            midRad := sec.MidAngle * 0.0174532925199433

            if (sec.ImagePath != "" && FileExist(sec.ImagePath)) {
                iconPosR := innerR + (radius - innerR) * this.iconPosRatio
                labelPosR := innerR + (radius - innerR) * this.labelPosRatio

                ipx := Round(cx + iconPosR * Cos(midRad))
                ipy := Round(cy + iconPosR * Sin(midRad))
                lpx := Round(cx + labelPosR * Cos(midRad))
                lpy := Round(cy + labelPosR * Sin(midRad))

                iconBg := canvas.Add("Ellipse").Name("IconBg_" idx)
                iconBg.Width(iconSize).Height(iconSize)
                iconBg.Canvas_Left(ipx - iconSize / 2).Canvas_Top(ipy - iconSize / 2)
                iconBg.Fill("#00FFFFFF").Stroke("#00FFFFFF").StrokeThickness(0).IsHitTestVisible("False")

                iconEl := canvas.Add("Image").Name("Icon_" idx)
                iconEl.Width(iconSize - 8).Height(iconSize - 8)
                iconEl.Canvas_Left(ipx - iconSize / 2 + 4).Canvas_Top(ipy - iconSize / 2 + 4)
                iconEl.Stretch("Uniform")
                iconEl.IsHitTestVisible("False")

                lbl := canvas.Add("TextBlock").Name("Label_" idx)
                lbl.Text(sec.Name)
                lbl.FontFamily("Segoe UI Variable Display, Segoe UI, sans-serif")
                lbl.FontSize(fontSize).Foreground(this.normalText).FontWeight("SemiBold")
                lbl.TextAlignment("Center").TextTrimming("CharacterEllipsis")
                lbl.Width(Round(78 * this.dpiScale)).Canvas_Left(lpx - Round(39 * this.dpiScale)).Canvas_Top(lpy - 8).IsHitTestVisible("False")

                ; 运行状态色点（默认隐藏，放在文本下方居中）
                dotSize := Round(8 * this.dpiScale)
                stateDot := canvas.Add("Ellipse").Name("StateDot_" idx)
                stateDot.Width(dotSize).Height(dotSize)
                stateDot.Canvas_Left(lpx - Round(dotSize / 2)).Canvas_Top(lpy + fontSize + 2)
                stateDot.Visibility("Collapsed").IsHitTestVisible("False")
            } else {
                centerR := innerR + (radius - innerR) * this.centerPosRatio
                cpx := Round(cx + centerR * Cos(midRad))
                cpy := Round(cy + centerR * Sin(midRad))

                iconBg := canvas.Add("Ellipse").Name("IconBg_" idx)
                iconBg.Width(iconSize).Height(iconSize)
                iconBg.Canvas_Left(cpx - iconSize / 2).Canvas_Top(cpy - iconSize / 2)
                iconBg.Fill("#00FFFFFF").Stroke("#00FFFFFF").StrokeThickness(0).IsHitTestVisible("False")

                lbl := canvas.Add("TextBlock").Name("Label_" idx)
                lbl.Text(sec.Name)
                lbl.FontFamily("Segoe UI Variable Display, Segoe UI, sans-serif")
                lbl.FontSize(fontSize).Foreground(this.normalText).FontWeight("SemiBold")
                lbl.TextAlignment("Center").TextTrimming("CharacterEllipsis")
                lbl.Width(Round(78 * this.dpiScale)).Canvas_Left(cpx - Round(39 * this.dpiScale)).Canvas_Top(cpy - 8).IsHitTestVisible("False")

                ; 运行状态色点（默认隐藏，放在文本下方居中）
                dotSize := Round(8 * this.dpiScale)
                stateDot := canvas.Add("Ellipse").Name("StateDot_" idx)
                stateDot.Width(dotSize).Height(dotSize)
                stateDot.Canvas_Left(cpx - Round(dotSize / 2)).Canvas_Top(cpy + fontSize + 2)
                stateDot.Visibility("Collapsed").IsHitTestVisible("False")
            }
        }

        ; 划线模式：在主轮盘 Canvas 上添加划线（不创建独立窗口，避免遮挡事件）
        if (this.selectMode == 2) {
            swipeLine := canvas.Add("Line").Name("SwipeLine")
            swipeLine.X1(cx).Y1(cy).X2(cx).Y2(cy)
            swipeLine.Stroke(this.swipeLineColor).StrokeThickness(3).StrokeDashArray("4,2")
            swipeLine.IsHitTestVisible("False")
        }

        this.ui := XAMLHost(win.ToString(), "", 0)
        this.closed := false
        this.swipeTriggered := false
        this.isOpen := true

        Loop itemCount {
            idx := A_Index
            h := MenuWheelGui._H(this, idx)
            this.ui.OnEvent("Wedge_" idx, "PreviewMouseLeftButtonDown", h.Select)
            this.ui.OnEvent("IconBg_" idx, "PreviewMouseLeftButtonDown", h.Select)
            ; 划线模式需要悬停触发选中，绑定 MouseMove/MouseLeave
            if (this.selectMode == 2) {
                this.ui.OnEvent("Wedge_" idx, "MouseMove", h.Hover)
                this.ui.OnEvent("IconBg_" idx, "MouseMove", h.Hover)
                this.ui.OnEvent("Wedge_" idx, "MouseLeave", h.Leave)
                this.ui.OnEvent("IconBg_" idx, "MouseLeave", h.Leave)
            }
        }

        this.ui.OnEvent("CenterCircle", "PreviewMouseLeftButtonDown", (*) => this.DoCancel())

        this.ui.Show()

        startTime := A_TickCount
        while (!this.ui.wpfHwnd && A_TickCount - startTime < 5000)
            Sleep(20)

        for sec in this.sectors {
            if (sec.ImagePath != "" && FileExist(sec.ImagePath))
                this.ui.Update("Icon_" sec.Index, "Source", sec.ImagePath)
        }

        if (this.selectMode == 2) {
            this.swipe := MenuWheelGui.SwipeSelector(this)
            this.swipe.Init()
        } else {
            this.swipe := ""
        }

        ; 显示宏运行状态颜色
        tableItem := MySoftData.TableInfo[3]
        Loop itemCount {
            idx := A_Index
            macroIndex := (this.MenuIndex - 1) * 8 + idx
            isWorkRunning := tableItem.IsWorkIndexArr.Length >= macroIndex && tableItem.IsWorkIndexArr[macroIndex] != 0
            state := isWorkRunning ? 1 : (tableItem.ColorStateArr.Length >= macroIndex ? tableItem.ColorStateArr[macroIndex] : 0)
            if (state > 0 && MacroStateColors.Has(state))
                this.sectors[idx].RenderState(this, MacroStateColors[state])
        }

        this._aliveHwnd := this.ui.wpfHwnd
        this.Gui := { Hwnd: this.ui.wpfHwnd }
        ; 注册数字键热键（窗口打开期间全局有效，关闭时注销）
        this._hkIds := WinHotkey.Register(MenuWheelGui.Hotkeys, ObjBindMethod(this, "_OnHotkey"))
    }

    _OnHotkey(key) {
        idx := 0
        for i, k in MenuWheelGui.Hotkeys {
            if (k == key) {
                idx := i
                break
            }
        }
        if (idx > 0 && idx <= this.sectors.Length)
            this.DoSelect(idx)
    }

    static _H(menu, idx) {
        v := idx
        return { Select: (*) => menu.DoSelect(v), Hover: (*) => menu.DoHover(v), Leave: (*) => menu.DoLeave(v) }
    }

    DoSelect(idx, *) {
        if (!this.isOpen || this.closed)
            return
        this.closed := true
        this.swipeTriggered := true
        if (IsObject(this.swipe))
            this.swipe.Stop()
        sec := this.sectors[idx]
        sec.RenderSelected(this)
        if (IsObject(sec.Callback)) {
            this._pendingCallback := sec.Callback
            this._pendingCallbackIdx := idx
            this._pendingCallbackName := sec.Name
            SetTimer(ObjBindMethod(this, "_ExecutePendingCallback"), -10)
        }
        this._Cleanup()
    }

    _ExecutePendingCallback() {
        cb := this._pendingCallback
        idx := this._pendingCallbackIdx
        name := this._pendingCallbackName
        this._pendingCallback := ""
        try cb.Call(idx, name)
    }

    DoHover(idx, *) {
        if (!this.isOpen || this.closed)
            return
        this.hoveredIdx := idx
        if (this.selectMode == 2 && IsObject(this.swipe) && !this.swipeTriggered)
            this.DoSelect(idx, "")
    }

    DoLeave(idx, *) {
        if (!this.isOpen || this.closed)
            return
        if (this.hoveredIdx == idx)
            this.hoveredIdx := 0
    }

    _Cleanup() {
        this.ToggleFunc(false)
        if (this._hkIds.Length > 0) {
            WinHotkey.UnregisterAll(this._hkIds)
            this._hkIds := []
        }
        this.isOpen := false
        if (IsObject(this.swipe))
            this.swipe.Stop()
        MySoftData.CurMenuWheelIndex := -1
        ToolTip()
        if (this.HasProp("ui") && IsObject(this.ui)) {
            try {
                this.ui.Update("Window", "Close", "")
                this.ui.Dispose()
            }
        }
        this.ui := ""
        this.Gui := ""
        this.sectors := []
    }

    DoCancel() {
        if (!this.isOpen || this.closed)
            return
        this.closed := true
        this._Cleanup()
    }

    OnRadialMenuSelect(ArcNr, MenuIndex) {
        tableItem := MySoftData.TableInfo[3]
        macroIndex := (MenuIndex - 1) * 8 + ArcNr
        triggerType := tableItem.TriggerTypeArr[macroIndex]

        ; 开关模式：与按键宏保持一致，统一走 OnToggleTriggerMacro
        if (triggerType == 4) {
            WorkerIndex := tableItem.IsWorkIndexArr[macroIndex]
            if (WorkerIndex != 0) {
                ; Worker 运行中 → 停止
                MyStopMacro(tableItem.Index, macroIndex)
                return
            }
            ; 未运行或主进程内运行 → 走统一的开关逻辑（管理 ToggleStateArr）
            OnToggleTriggerMacro(tableItem.Index, macroIndex)
            return
        }

        ; 非开关模式：直接启动
        SetTableItemState(tableItem.index, macroIndex, 1)
        OnTriggerMacroKeyAndInit(tableItem, tableItem.MacroArr[macroIndex], macroIndex)
    }

    ; ====== 内部轮盘实现 ======
    class WheelSector {
        Index := 0
        Name := ""
        ImagePath := ""
        Callback := 0
        StartAngle := 0
        EndAngle := 0
        MidAngle := 0

        __New(idx, name, imagePath, callback, startAng, endAng, midAng) {
            this.Index := idx
            this.Name := name
            this.ImagePath := imagePath
            this.Callback := callback
            this.StartAngle := startAng
            this.EndAngle := endAng
            this.MidAngle := midAng
        }

        ; 选中时清除 Style（移除 IsMouseOver Trigger），再设选中色，避免被覆盖
        RenderSelected(menu) {
            p := this.Index
            ui := menu.ui
            if (!IsObject(ui))
                return
            ui.BatchUpdate([
                { ControlName: "Wedge_" p, PropertyName: "Style", Value: "{x:Null}" },
                { ControlName: "Wedge_" p, PropertyName: "Fill", Value: menu.selectedFill },
                { ControlName: "Wedge_" p, PropertyName: "Stroke", Value: menu.selectedStroke },
                { ControlName: "Wedge_" p, PropertyName: "StrokeThickness", Value: String(menu.selectedThickness) },
                { ControlName: "Label_" p, PropertyName: "Foreground", Value: menu.selectedText }
            ])
        }

        ; 按宏运行状态渲染色点（使用全局 MacroStateColors）
        RenderState(menu, stateColor) {
            p := this.Index
            ui := menu.ui
            if (!IsObject(ui))
                return
            ui.BatchUpdate([
                { ControlName: "StateDot_" p, PropertyName: "Fill", Value: stateColor },
                { ControlName: "StateDot_" p, PropertyName: "Visibility", Value: "Visible" }
            ])
        }
    }

    class SwipeSelector {
        menu := ""
        drawFn := ""

        __New(menu) {
            this.menu := menu
        }

        Init() {
            this.drawFn := ObjBindMethod(this, "_OnTick")
            SetTimer(this.drawFn, 16)
        }

        Toggle(state) {
            if (state) {
                if (!this.drawFn)
                    this.drawFn := ObjBindMethod(this, "_OnTick")
                SetTimer(this.drawFn, 16)
            } else {
                this.Stop()
            }
        }

        Stop() {
            if (this.drawFn) {
                SetTimer(this.drawFn, 0)
                this.drawFn := ""
            }
        }

        _OnTick() {
            m := this.menu
            if (!m.isOpen || m.closed || !IsObject(m.ui))
                return
            ui := m.ui
            hwnd := ui.wpfHwnd
            if (!hwnd)
                return

            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)

            WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
            relX := (mx - wx) / m.dpiScale
            relY := (my - wy) / m.dpiScale

            ui.Update("SwipeLine", "X2", String(relX))
            ui.Update("SwipeLine", "Y2", String(relY))
        }
    }
}
