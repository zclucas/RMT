#Requires AutoHotkey v2.0

class MenuWheelGui {
    static Hotkeys := ["1", "2", "3", "4", "5", "6", "7", "8"]

    __new() {
        this.MenuIndex := 1
        this.TableID := ""
        this.Gui := ""
        this.isOpen := false
        this.sectors := []
        this.hoveredIdx := 0
        this.closed := false
        this.showTooltip := true
        this.selectMode := 1
        this.swipe := ""
        this.swipeTriggered := false
        this._hkIds := []
        global MyHotReloadBus
        if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
            MyHotReloadBus.Subscribe(ObjBindMethod(this, "OnHotReloadConfigChanged"))
    }

    OnHotReloadConfigChanged(tableIndex, itemIndex) {
        tableItem := GetTableByID(this.TableID)
        if (this.isOpen && (tableIndex == 0 || (tableItem && tableItem.Index == tableIndex)))
            this.Close()
    }

    ShowGui(MenuIndex, tableItem) {
        this.PreviousActiveWindow := WinExist("A")
        this.ShowRadialMenu(MenuIndex, tableItem)
    }

    ShowRadialMenu(MenuIndex, tableItem) {
        this.MenuIndex := MenuIndex
        this.showTooltip := !!MainSoftData.MenuWheelShowTooltip
        this.selectMode := MainSoftData.HasProp("MenuWheelSelectMode") ? MainSoftData.MenuWheelSelectMode : 2

        this.Close()
        if (!tableItem.Folds.Has(MenuIndex))
            return
        fold := tableItem.Folds[MenuIndex]
        if (!fold || fold.ForbidState)
            return
        foldItems := GetFoldItems(tableItem, fold)
        visibleIndices := []
        for index, item in foldItems {
            if (!ParseBoolInt(item.Forbid))
                visibleIndices.Push(index)
        }
        if (visibleIndices.Length == 0)
            return
        this.TableID := tableItem.ID

        itemCount := visibleIndices.Length

        ; 先进入打开状态，避免等待 hwnd 期间软键盘/热键无法工作
        this.closed := false
        this.swipeTriggered := false
        this.isOpen := true

        ; 根据实际宏数量注册对应数量的数字键
        activeHotkeys := []
        Loop Min(itemCount, MenuWheelGui.Hotkeys.Length) {
            activeHotkeys.Push(MenuWheelGui.Hotkeys[A_Index])
        }
        if (activeHotkeys.Length > 0) {
            this._hkIds := WinHotkey.Register(activeHotkeys, ObjBindMethod(this, "_OnHotkey"))
        } else {
            this._hkIds := []
        }

        ; 从统一主题配置读取轮盘颜色（选中态复用悬停色）
        modNormalFill := AppThemeUtil.GetWheelColor("NormalFill", "#FFFCFCFC")
        modNormalStroke := AppThemeUtil.GetWheelColor("NormalStroke", "#FFC6DFFC")
        modHoverFill := AppThemeUtil.GetWheelColor("HoverFill", "#FFE8F1FB")
        modHoverStroke := AppThemeUtil.GetWheelColor("HoverStroke", "#FF0078D7")
        modNormalText := AppThemeUtil.GetWheelColor("NormalText", "#CC333333")
        modHoverText := AppThemeUtil.GetWheelColor("HoverText", "#FF0078D7")
        modSwipeLine := AppThemeUtil.GetWheelColor("SwipeLineColor", "#FF3A88F5")

        items := []
        loop itemCount {
            originalIndex := visibleIndices[A_Index]
            item := foldItems[originalIndex]
            remark := item.Remark
            btnName := remark != "" ? remark : "菜单" A_Index

            icoPath := item.IcoPath

            h := this.OnRadialMenuSelect.Bind(this, tableItem.ID, fold.ID, item.ID)

            items.Push({
                Name: btnName,
                Image: icoPath,
                Callback: h
            })
        }

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        if (MainSoftData.FixedMenuWheel) {
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

        wheelScale := Max(Min(MainSoftData.MenuWheelScale, 200), 30) / 100.0
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
            SelectedFill: modHoverFill,
            SelectedStroke: modHoverStroke,
            SelectedText: modHoverText,
            SelectedThickness: 2,
            SwipeLineColor: modSwipeLine,
            IconPosRatio: 0.72,
            LabelPosRatio: 0.35,
            CenterPosRatio: 0.58
        })
        MainSoftData.CurMenuWheelIndex := this.MenuIndex
    }

    ToggleFunc(state) {
        if (this.selectMode == 2 && IsObject(this.swipe))
            this.swipe.Toggle(state)
    }

    OnSoftKey(key, isDown) {
        if (!isDown)
            return

        idx := Integer(key)
        if (idx < 1 || idx > MenuWheelGui.Hotkeys.Length)
            return

        ; 輪盤顯示中：走輪盤選取
        if (this.isOpen && IsObject(this.ui)) {
            this.DoSelect(idx, "")
            return
        }

        ; 輪盤未顯示：直接輸出數字
        try SendText(key)
    }

    Close() {
        if (!this.isOpen)
            return
        this.closed := true
        this._Cleanup()
    }

    ; 主题调色板预览/保存时即时刷新已打开轮盘；样式触发器使用动态资源，
    ; 因而常态、悬停、选中、文字与划线会一起换色，无需关闭重开。
    ApplyThemeColors() {
        this.normalFill := AppThemeUtil.GetWheelColor("NormalFill", "#FFFCFCFC")
        this.normalStroke := AppThemeUtil.GetWheelColor("NormalStroke", "#FFC6DFFC")
        this.hoverFill := AppThemeUtil.GetWheelColor("HoverFill", "#FFE8F1FB")
        this.hoverStroke := AppThemeUtil.GetWheelColor("HoverStroke", "#FF0078D7")
        this.normalText := AppThemeUtil.GetWheelColor("NormalText", "#CC333333")
        this.hoverText := AppThemeUtil.GetWheelColor("HoverText", "#FF0078D7")
        this.selectedFill := this.hoverFill
        this.selectedStroke := this.hoverStroke
        this.selectedText := this.hoverText
        this.swipeLineColor := AppThemeUtil.GetWheelColor("SwipeLineColor", "#FF3A88F5")
        if (this.closed || !this.isOpen || !IsObject(this.ui))
            return
        updates := [
            {ControlName: "Resource", PropertyName: "WheelNormalFill", Value: this.normalFill},
            {ControlName: "Resource", PropertyName: "WheelNormalStroke", Value: this.normalStroke},
            {ControlName: "Resource", PropertyName: "WheelHoverFill", Value: this.hoverFill},
            {ControlName: "Resource", PropertyName: "WheelHoverStroke", Value: this.hoverStroke},
            {ControlName: "Resource", PropertyName: "WheelNormalText", Value: this.normalText},
            {ControlName: "Resource", PropertyName: "WheelHoverText", Value: this.hoverText}
        ]
        if (this.selectMode == 2)
            updates.Push({ControlName: "SwipeLine", PropertyName: "Stroke", Value: this.swipeLineColor})
        try this.ui.BatchUpdate(updates)
    }

    _BuildAndShow(items, x, y, options) {
        radius := options.HasProp("Radius") ? options.Radius : 150
        innerR := options.HasProp("InnerRadius") ? options.InnerRadius : Round(radius * 0.4)
        iconSize := options.HasProp("IconSize") ? options.IconSize : 50
        fontSize := options.HasProp("FontSize") ? options.FontSize : 11
        normalFill := options.HasProp("NormalFill") ? options.NormalFill : "#FFFCFCFC"
        normalStroke := options.HasProp("NormalStroke") ? options.NormalStroke : "#FFC6DFFC"
        hoverFill := options.HasProp("HoverFill") ? options.HoverFill : "#FFE8F1FB"
        hoverStroke := options.HasProp("HoverStroke") ? options.HoverStroke : "#FF0078D7"
        selectedFill := options.HasProp("SelectedFill") ? options.SelectedFill : "#FF0078D7"
        selectedStroke := options.HasProp("SelectedStroke") ? options.SelectedStroke : "#FFFFFFFF"
        normalText := options.HasProp("NormalText") ? options.NormalText : "#CC333333"
        hoverText := options.HasProp("HoverText") ? options.HoverText : "#FF0078D7"
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
            . '<SolidColorBrush x:Key="WheelNormalFill" Color="' normalFill '"/>'
            . '<SolidColorBrush x:Key="WheelNormalStroke" Color="' normalStroke '"/>'
            . '<SolidColorBrush x:Key="WheelHoverFill" Color="' hoverFill '"/>'
            . '<SolidColorBrush x:Key="WheelHoverStroke" Color="' hoverStroke '"/>'
            . '<SolidColorBrush x:Key="WheelNormalText" Color="' normalText '"/>'
            . '<SolidColorBrush x:Key="WheelHoverText" Color="' hoverText '"/>'
            . '<Style TargetType="{x:Type FrameworkElement}" x:Key="GlobalToolTipStyle">'
            . '  <Setter Property="ToolTipService.InitialShowDelay" Value="200"/>'
            . '</Style>'
            . '<Style x:Key="WheelWedgeStyle" TargetType="Path">'
            . '  <Setter Property="Fill" Value="{DynamicResource WheelNormalFill}"/>'
            . '  <Setter Property="Stroke" Value="{DynamicResource WheelNormalStroke}"/>'
            . '  <Setter Property="StrokeThickness" Value="' String(normalThickness) '"/>'
            . '  <Style.Triggers>'
            . '    <Trigger Property="IsMouseOver" Value="True">'
            . '      <Setter Property="Fill" Value="{DynamicResource WheelHoverFill}"/>'
            . '      <Setter Property="Stroke" Value="{DynamicResource WheelHoverStroke}"/>'
            . '      <Setter Property="StrokeThickness" Value="' String(hoverThickness) '"/>'
            . '    </Trigger>'
            . '  </Style.Triggers>'
            . '</Style>'
            . '<Style x:Key="CenterCircleStyle" TargetType="Ellipse">'
            . '  <Setter Property="Fill" Value="{DynamicResource WheelNormalFill}"/>'
            . '  <Setter Property="Stroke" Value="{DynamicResource WheelNormalStroke}"/>'
            . '  <Setter Property="StrokeThickness" Value="' String(normalThickness) '"/>'
            . '  <Style.Triggers>'
            . '    <Trigger Property="IsMouseOver" Value="True">'
            . '      <Setter Property="Fill" Value="{DynamicResource WheelHoverFill}"/>'
            . '      <Setter Property="Stroke" Value="{DynamicResource WheelHoverStroke}"/>'
            . '      <Setter Property="StrokeThickness" Value="' String(hoverThickness) '"/>'
            . '    </Trigger>'
            . '  </Style.Triggers>'
            . '</Style>'
            . '<Style x:Key="CloseIconStyle" TargetType="TextBlock">'
            . '  <Setter Property="Foreground" Value="{DynamicResource WheelNormalText}"/>'
            . '  <Style.Triggers>'
            . '    <DataTrigger Binding="{Binding IsMouseOver, ElementName=CenterCircle}" Value="True">'
            . '      <Setter Property="Foreground" Value="{DynamicResource WheelHoverText}"/>'
            . '    </DataTrigger>'
            . '  </Style.Triggers>'
            . '</Style>'
        ; 扇区文字悬停色：用 Style+DataTrigger，避免本地 Foreground 盖住触发器
        Loop itemCount {
            idx := A_Index
            wheelStyle .= '<Style x:Key="WheelLabelStyle_' idx '" TargetType="TextBlock">'
                . '  <Setter Property="Foreground" Value="{DynamicResource WheelNormalText}"/>'
                . '  <Style.Triggers>'
                . '    <DataTrigger Binding="{Binding IsMouseOver, ElementName=Wedge_' idx '}" Value="True">'
                . '      <Setter Property="Foreground" Value="{DynamicResource WheelHoverText}"/>'
                . '    </DataTrigger>'
                . '  </Style.Triggers>'
                . '</Style>'
        }
        win.InjectResources(wheelStyle)

        canvas := win.Add("Canvas").Name("RootCanvas")
        canvas.Width(winW).Height(winH).Background("#00000000")

        Loop itemCount {
            idx := A_Index
            sec := this.sectors[idx]

            if (itemCount == 1) {
                ; 繪製無縫的完整圓環
                pathData := "M " cx "," (cy - radius)
                    . " A " radius "," radius " 0 1 1 " cx "," (cy + radius)
                    . " A " radius "," radius " 0 1 1 " cx "," (cy - radius)
                    . " M " cx "," (cy - innerR)
                    . " A " innerR "," innerR " 0 1 0 " cx "," (cy + innerR)
                    . " A " innerR "," innerR " 0 1 0 " cx "," (cy - innerR)
                    . " Z"
            } else {
                ; 繪製普通扇區
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
            }

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

        iconUpdates := []
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
                iconUpdates.Push({ControlName: "Icon_" idx, PropertyName: "Source", Value: sec.ImagePath})

                lbl := canvas.Add("TextBlock").Name("Label_" idx)
                lbl.Text(sec.Name)
                lbl.FontSize(fontSize).FontWeight("SemiBold")
                lbl.Style("{StaticResource WheelLabelStyle_" idx "}")
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
                lbl.FontSize(fontSize).FontWeight("SemiBold")
                lbl.Style("{StaticResource WheelLabelStyle_" idx "}")
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

        ui := this.ui
        ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "_OnLoaded", ui))
        if (iconUpdates.Length)
            ui.BatchUpdate(iconUpdates)
        XamlWin.QueueTheme(ui)
        ui.asyncCreate := true
        ui.Show()
        SetTimer(() => (this.ui == ui && !ui.wpfHwnd ? this.Close() : 0), -5000)
    }

    _OnLoaded(ui, *) {
        if (this.ui != ui || this.closed || !this.isOpen)
            return
        ; 在窗口显示前设置 WS_EX_NOACTIVATE，保留原窗口的键盘焦点。
        try WinSetExStyle("+0x08000000", "ahk_id " ui.wpfHwnd)
        this._aliveHwnd := ui.wpfHwnd
        this.Gui := { Hwnd: ui.wpfHwnd }

        if (this.selectMode == 2) {
            this.swipe := MenuWheelGui.SwipeSelector(this)
            this.swipe.Init()
        } else {
            this.swipe := ""
        }

        tableItem := GetTableByID(this.TableID)
        fold := tableItem && tableItem.Folds.Has(this.MenuIndex) ? tableItem.Folds[this.MenuIndex] : ""
        if (!fold)
            return
        idx := 0
        updates := []
        for item in GetFoldItems(tableItem, fold) {
            if (ParseBoolInt(item.Forbid))
                continue
            if (++idx > this.sectors.Length)
                break
            isWorkRunning := item.IsWorkIndex != 0
            state := isWorkRunning ? 1 : item.ColorState
            if (state > 0 && MacroStateColors.Has(state)) {
                updates.Push(
                    {ControlName: "StateDot_" idx, PropertyName: "Fill", Value: MacroStateColors[state]},
                    {ControlName: "StateDot_" idx, PropertyName: "Visibility", Value: "Visible"}
                )
            }
        }
        if (updates.Length)
            ui.BatchUpdate(updates)
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
        MainSoftData.CurMenuWheelIndex := -1
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

    OnRadialMenuSelect(tableID, foldID, itemID, *) {
        resolved := ResolveMacroItem(tableID, itemID)
        fold := GetFoldByID(tableID, foldID)
        if (!resolved || !fold || resolved.Item.FoldID != foldID)
            return
        tableItem := resolved.Table
        item := resolved.Item
        ; §17 统一禁用门控：轮盘条目被禁用（条目 Forbid / 所属模块禁用）→ 选择不触发，
        ; 覆盖轮盘已打开期间条目被禁用（保存选「否」热重载或模块开关热键）的场景
        if (ParseBoolInt(item.Forbid) || fold.ForbidState)
            return
        macroIndex := resolved.Index
        triggerType := item.TriggerType

        ; 开关模式：与按键宏保持一致，统一走 OnToggleTriggerMacro
        if (triggerType == 4) {
            if (item.IsWorkIndex || (WorkPoolEnabled() && MyWorkPool.HasItemWork(tableID, itemID))) {
                ; Worker 运行中 → 停止
                MyStopMacro(tableItem, macroIndex)
                return
            }
            ; 未运行或主进程内运行 → 走统一的开关逻辑
            OnToggleTriggerMacro(tableItem, macroIndex)
            return
        }

        ; 非开关模式：直接启动
        TriggerMacroHandler(tableItem, macroIndex)
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
    }

    class SwipeSelector {
        menu := ""
        drawFn := ""
        lastPoint := ""

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
            this.lastPoint := ""
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

            try WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
            catch
                return
            relX := (mx - wx) / m.dpiScale
            relY := (my - wy) / m.dpiScale
            point := relX "," relY
            if (point == this.lastPoint)
                return
            this.lastPoint := point
            ui.BatchUpdate([
                {ControlName: "SwipeLine", PropertyName: "X2", Value: String(relX)},
                {ControlName: "SwipeLine", PropertyName: "Y2", Value: String(relY)}
            ])
        }
    }
}
