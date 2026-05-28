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
        this.showTooltip := !!MySoftData.MenuWheelShowTooltip
        this.selectMode := MySoftData.HasProp("MenuWheelSelectMode") ? MySoftData.MenuWheelSelectMode : 1
        this.swipe := ""
        this.swipeTriggered := false
        this.pendingSelectTimer := ""
        this.pendingIdx := 0
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
        tableItem := MySoftData.TableInfo[3]

        iniPath := A_WorkingDir "\Setting\MainSettings.ini"
        modNormalFill := IniRead(iniPath, "MenuWheel", "NormalFill", "#FFFCFCFC")
        modNormalStroke := IniRead(iniPath, "MenuWheel", "NormalStroke", "#FFC6DFFC")
        modHoverFill := IniRead(iniPath, "MenuWheel", "HoverFill", "#FFFDE8E8")
        modHoverStroke := IniRead(iniPath, "MenuWheel", "HoverStroke", "#FFE81123")
        modSelectedFill := IniRead(iniPath, "MenuWheel", "SelectedFill", "#FF0078D7")
        modSelectedStroke := IniRead(iniPath, "MenuWheel", "SelectedStroke", "#FFFFFFFF")

        items := []
        loop 8 {
            macroIndex := (MenuIndex - 1) * 8 + A_Index
            remark := tableItem.RemarkArr[macroIndex]
            btnName := remark != "" ? remark : "菜单" A_Index

            gifPath := ""
            if (tableItem.HasProp("GifPathArr") && tableItem.GifPathArr.Length >= macroIndex) {
                gifPath := tableItem.GifPathArr[macroIndex]
                if (gifPath != "") {
                    fullPath := this.GetFullGifPath(gifPath)
                    if (fullPath != "" && FileExist(fullPath))
                        gifPath := fullPath
                    else
                        gifPath := ""
                }
            }

            arcNr := A_Index
            h := MenuWheelGui._MakeCallback(this, arcNr, MenuIndex)

            items.Push({
                Name: btnName,
                Image: gifPath,
                Callback: h
            })
        }

        if (MySoftData.FixedMenuWheel) {
            mx := Round(A_ScreenWidth * 0.5)
            my := Round(A_ScreenHeight * 0.70)
        } else {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
        }

        this._BuildAndShow(items, mx, my, {
            Radius: 150,
            InnerRadius: 60,
            IconSize: 50,
            FontSize: 11,
            NormalFill: modNormalFill,
            NormalStroke: modNormalStroke,
            NormalText: "#CC333333",
            NormalThickness: 1,
            HoverFill: modHoverFill,
            HoverStroke: modHoverStroke,
            HoverText: "#FFE81123",
            HoverThickness: 2,
            SelectedFill: modSelectedFill,
            SelectedStroke: modSelectedStroke,
            SelectedText: "#FFFFFFFF",
            SelectedThickness: 2,
            IconPosRatio: 0.72,
            LabelPosRatio: 0.35,
            CenterPosRatio: 0.58
        })
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
        this.ToggleFunc(false)
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

        dpiScale := A_ScreenDPI / 96.0
        this.dpiScale := dpiScale

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
        this.winSize := winW

        finalX := x
        finalY := y
        if (finalX == "" or finalY == "") {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            finalX := mx
            finalY := my
        }
        winLeft := finalX / this.dpiScale - cx
        winTop := finalY / this.dpiScale - cy

        angleStep := 360.0 / itemCount

        Loop itemCount {
            idx := A_Index
            startAngle := (idx - 1) * angleStep - 90
            endAngle := idx * angleStep - 90
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
            wedge.Data(pathData).Fill(normalFill).Stroke(normalStroke).StrokeThickness(normalThickness).Cursor("Hand")
        }

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
                iconBg.Fill("#00FFFFFF").Stroke("#00FFFFFF").StrokeThickness(0).Cursor("Hand")

                iconEl := canvas.Add("Image").Name("Icon_" idx)
                iconEl.Width(iconSize - 8).Height(iconSize - 8)
                iconEl.Canvas_Left(ipx - iconSize / 2 + 4).Canvas_Top(ipy - iconSize / 2 + 4)
                iconEl.Stretch("Uniform")
                iconEl.IsHitTestVisible("False")

                lbl := canvas.Add("TextBlock").Name("Label_" idx)
                lbl.Text(sec.Name)
                lbl.FontFamily("Segoe UI Variable Display, Segoe UI, sans-serif")
                lbl.FontSize(fontSize).Foreground(this.normalText).FontWeight("SemiBold")
                lbl.TextAlignment("Center")
                lbl.Canvas_Left(lpx - 28).Canvas_Top(lpy - 8).Width(56).IsHitTestVisible("False")
            } else {
                centerR := innerR + (radius - innerR) * this.centerPosRatio
                cpx := Round(cx + centerR * Cos(midRad))
                cpy := Round(cy + centerR * Sin(midRad))

                iconBg := canvas.Add("Ellipse").Name("IconBg_" idx)
                iconBg.Width(iconSize).Height(iconSize)
                iconBg.Canvas_Left(cpx - iconSize / 2).Canvas_Top(cpy - iconSize / 2)
                iconBg.Fill("#00FFFFFF").Stroke("#00FFFFFF").StrokeThickness(0).Cursor("Hand")

                lbl := canvas.Add("TextBlock").Name("Label_" idx)
                lbl.Text(sec.Name)
                lbl.FontFamily("Segoe UI Variable Display, Segoe UI, sans-serif")
                lbl.FontSize(fontSize).Foreground(this.normalText).FontWeight("SemiBold")
                lbl.TextAlignment("Center")
                lbl.Canvas_Left(cpx - 28).Canvas_Top(cpy - 8).Width(56).IsHitTestVisible("False")
            }
        }

        swipeLine := canvas.Add("Line").Name("SwipeLine")
        swipeLine.X1(cx).Y1(cy).X2(cx).Y2(cy)
        swipeLine.Stroke("#3A88F5").StrokeThickness(3).StrokeDashArray("4,2").IsHitTestVisible("False")

        this.ui := XAMLHost(win.ToString(), "", 0)
        this.closed := false
        this.swipeTriggered := false
        this.isOpen := true
        try FileAppend("[WHEEL-OPEN] menu=" this.MenuIndex "`n", A_Temp "\AhkWpf\mem_trace.log")

        Loop itemCount {
            idx := A_Index
            h := MenuWheelGui._H(this, idx)
            this.ui.OnEvent("Wedge_" idx, "PreviewMouseLeftButtonDown", h.Select)
            this.ui.OnEvent("IconBg_" idx, "PreviewMouseLeftButtonDown", h.Select)
            this.ui.OnEvent("Wedge_" idx, "MouseMove", h.Hover)
            this.ui.OnEvent("IconBg_" idx, "MouseMove", h.Hover)
            this.ui.OnEvent("Wedge_" idx, "MouseLeave", h.Leave)
            this.ui.OnEvent("IconBg_" idx, "MouseLeave", h.Leave)
        }

        this.ui.OnEvent("RootCanvas", "MouseMove", (*) => this.DoCanvasMove())

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
            if (this.HasProp("ui") && IsObject(this.ui))
                this.ui.Update("SwipeLine", "Visibility", "Collapsed")
        }
        this._aliveHwnd := this.ui.wpfHwnd
        this.Gui := { Hwnd: this.ui.wpfHwnd }
        WindowHotkeyManager.Register(this, MenuWheelGui.Hotkeys, this.OnSoftKey.Bind(this), this._IsAlive.Bind(this))
    }

    _IsAlive() {
        return WinExist("ahk_id " this._aliveHwnd)
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
        Sleep(150)
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
        prevIdx := this.hoveredIdx
        if (prevIdx > 0 && prevIdx != idx)
            this.sectors[prevIdx].OnLeave(this)
        this.hoveredIdx := idx
        this.sectors[idx].OnHover(this)
        if (this.showTooltip)
            ToolTip(this.sectors[idx].Name)
        if (this.selectMode == 2 && IsObject(this.swipe) && !this.swipeTriggered) {
            this._StartPendingSelect(idx)
        }
    }

    DoLeave(idx, *) {
        if (!this.isOpen || this.closed)
            return
        if (this.hoveredIdx == idx) {
            this.hoveredIdx := 0
            this._CancelPendingSelect()
            this.sectors[idx].OnLeave(this)
            ToolTip()
        }
    }

    DoCanvasMove(*) {
        if (!this.isOpen || this.closed)
            return
        if (this.hoveredIdx > 0) {
            prevIdx := this.hoveredIdx
            this._CancelPendingSelect()
            this.sectors[prevIdx].OnLeave(this)
            this.hoveredIdx := 0
        }
        ToolTip()
    }

    _StartPendingSelect(idx) {
        this._CancelPendingSelect()
        this.pendingIdx := idx
        this.pendingSelectTimer := ObjBindMethod(this, "_OnPendingSelectTick")
        SetTimer(this.pendingSelectTimer, 50)
    }

    _CancelPendingSelect() {
        if (this.pendingSelectTimer) {
            SetTimer(this.pendingSelectTimer, 0)
            this.pendingSelectTimer := ""
        }
        this.pendingIdx := 0
    }

    _OnPendingSelectTick() {
        this.pendingSelectTimer := ""
        if (!this.isOpen || this.closed)
            return
        idx := this.pendingIdx
        if (idx > 0 && this.hoveredIdx == idx)
            this.DoSelect(idx, "")
        this.pendingIdx := 0
    }

    _Cleanup() {
        try FileAppend("[WHEEL-CLEANUP] menu=" this.MenuIndex "`n", A_Temp "\AhkWpf\mem_trace.log")
        WindowHotkeyManager.Unregister(this)
        this.isOpen := false
        this._CancelPendingSelect()
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
        SetTableItemState(tableItem.index, macroIndex, 1)
        OnTriggerMacroKeyAndInit(tableItem, tableItem.MacroArr[macroIndex], macroIndex)
    }

    GetFullGifPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\Gif\" path
        if (FileExist(fullPath))
            return fullPath

        return ""
    }

    ; ====== 内部轮盘实现 ======
    class WheelSector {
        Index := 0
        Name := ""
        ImagePath := ""
        Callback := 0
        State := 0
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
            this.State := 0
        }

        RenderNormal(menu) {
            this.State := 0
            p := this.Index
            ui := menu.ui
            if (!IsObject(ui))
                return
            fill := menu.normalFill
            stroke := menu.normalStroke
            ui.Update("Wedge_" p, "Fill", fill)
            ui.Update("Wedge_" p, "Stroke", stroke)
            ui.Update("Wedge_" p, "StrokeThickness", String(menu.normalThickness))
            ui.Update("IconBg_" p, "Fill", "#00FFFFFF")
            ui.Update("Label_" p, "Foreground", menu.normalText)
        }

        OnHover(menu) {
            if (this.State == 2)
                return
            this.State := 1
            p := this.Index
            ui := menu.ui
            if (!IsObject(ui))
                return
            fill := menu.hoverFill
            stroke := menu.hoverStroke
            ui.Update("Wedge_" p, "Fill", fill)
            ui.Update("Wedge_" p, "Stroke", stroke)
            ui.Update("Wedge_" p, "StrokeThickness", String(menu.hoverThickness))
            ui.Update("IconBg_" p, "Fill", "#00FFFFFF")
            ui.Update("Label_" p, "Foreground", menu.hoverText)
        }

        OnLeave(menu) {
            if (this.State == 0)
                return
            this.State := 0
            this.RenderNormal(menu)
        }

        RenderSelected(menu) {
            this.State := 2
            p := this.Index
            ui := menu.ui
            if (!IsObject(ui))
                return
            fill := menu.selectedFill
            stroke := menu.selectedStroke
            ui.Update("Wedge_" p, "Fill", fill)
            ui.Update("Wedge_" p, "Stroke", stroke)
            ui.Update("Wedge_" p, "StrokeThickness", String(menu.selectedThickness))
            ui.Update("IconBg_" p, "Fill", "#00FFFFFF")
            ui.Update("Label_" p, "Foreground", menu.selectedText)
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
            SetTimer(this.drawFn, 15)
            if (IsObject(this.menu.ui))
                this.menu.ui.Update("SwipeLine", "Visibility", "Visible")
        }

        Toggle(state) {
            if (state) {
                if (!this.drawFn)
                    this.drawFn := ObjBindMethod(this, "_OnTick")
                SetTimer(this.drawFn, 15)
                if (IsObject(this.menu.ui))
                    this.menu.ui.Update("SwipeLine", "Visibility", "Visible")
            } else {
                this.Stop()
            }
        }

        Stop() {
            if (this.drawFn) {
                SetTimer(this.drawFn, 0)
                this.drawFn := ""
            }
            if (IsObject(this.menu.ui)) {
                try {
                    this.menu.ui.Update("SwipeLine", "Visibility", "Collapsed")
                }
            }
        }

        _OnTick() {
            if (!this.menu.isOpen || this.menu.closed || !IsObject(this.menu.ui))
                return
            hwnd := this.menu.ui.wpfHwnd
            if (!hwnd)
                return

            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)

            pt := Buffer(8, 0)
            NumPut("Int", mx, pt, 0)
            NumPut("Int", my, pt, 4)
            DllCall("user32\ScreenToClient", "Ptr", hwnd, "Ptr", pt)
            relX := NumGet(pt, 0, "Int") / this.menu.dpiScale
            relY := NumGet(pt, 4, "Int") / this.menu.dpiScale

            this.menu.ui.Update("SwipeLine", "X2", relX)
            this.menu.ui.Update("SwipeLine", "Y2", relY)
        }
    }
}
