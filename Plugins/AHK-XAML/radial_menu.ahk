#Requires AutoHotkey v2.0
#Include "lib/XAML_Host.ahk"
#Include "lib/XAML_Generator.ahk"

class XamlRadialMenu {
    ; ====== 调用方式 ======
    ; result := XamlRadialMenu.Show(options)
    ; result.Selected       : 选中的扇区名称，取消时为 "__CANCEL__"
    ; result.SelectedIndex  : 选中的索引 (1-based)，取消时为 -1
    ; result.SelectedName   : 同 Selected
    ;
    ; ====== options 参数 ======
    ; Items          : Array  扇区配置数组，每项: { Name, Image, Callback }
    ;   - Name      : String 扇区显示文字
    ;   - Image     : String 图片路径，空字符串则只显示居中文字
    ;   - Callback  : Func   选中回调函数 Callback(idx, name)
    ;
    ; Radius         : Number 外圆半径，默认 172
    ; InnerRadius    : Number 内圆半径（中心空白区），默认 Radius*0.4
    ; IconSize       : Number 图标/热区大小(px)，默认 50
    ; FontSize       : Number 文字大小(pt)，默认 11
    ; X / Y          : Number 显示位置，默认鼠标位置
    ; Owner          : Number 所有者窗口句柄，默认 0
    ;
    ; NormalFill     : String 普通状态扇区背景色 (#AARRGGBB)，默认 "#FFFCFCFC"
    ; NormalStroke   : String 普通状态边框色，默认 "#FFC6DFFC"
    ; NormalText     : String 普通状态文字色，默认 "#CC333333"
    ; NormalThickness: Number 普通状态边框粗细，默认 1
    ;
    ; HoverFill      : String 悬停状态背景色，默认 "#FFFDE8E8"
    ; HoverStroke    : String 悬停状态边框色，默认 "#FFE81123"
    ; HoverText      : String 悬停状态文字色，默认 "#FFE81123"
    ; HoverThickness : Number 悬停状态边框粗细，默认 2
    ;
    ; SelectedFill   : String 选中状态背景色，默认 "#FF0078D7"
    ; SelectedStroke : String 选中状态边框色，默认 "#FFFFFFFF"
    ; SelectedText   : String 选中状态文字色，默认 "#FFFFFFFF"
    ; SelectedThickness: Number 选中状态边框粗细，默认 2
    ;
    ; IconPosRatio   : Number 有图片时图标位置比例(0~1)，0=内圈 1=外圈，默认 0.72
    ; LabelPosRatio  : Number 有图片时文字位置比例(0~1)，默认 0.35
    ; CenterPosRatio : Number 无图片时文字居中位置比例(0~1)，默认 0.58

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
            p := this.Index
            ui := menu.ui
            ui.Update("Wedge_" p, "Fill", menu.normalFill)
            ui.Update("Wedge_" p, "Stroke", menu.normalStroke)
            ui.Update("Wedge_" p, "StrokeThickness", String(menu.normalThickness))
            ui.Update("IconBg_" p, "Fill", "#00FFFFFF")
            ui.Update("Label_" p, "Foreground", menu.normalText)
        }

        RenderHover(menu) {
            p := this.Index
            ui := menu.ui
            ui.Update("Wedge_" p, "Fill", menu.hoverFill)
            ui.Update("Wedge_" p, "Stroke", menu.hoverStroke)
            ui.Update("Wedge_" p, "StrokeThickness", String(menu.hoverThickness))
            ui.Update("IconBg_" p, "Fill", "#00FFFFFF")
            ui.Update("Label_" p, "Foreground", menu.hoverText)
        }

        RenderSelected(menu) {
            p := this.Index
            ui := menu.ui
            ui.Update("Wedge_" p, "Fill", menu.selectedFill)
            ui.Update("Wedge_" p, "Stroke", menu.selectedStroke)
            ui.Update("Wedge_" p, "StrokeThickness", String(menu.selectedThickness))
            ui.Update("IconBg_" p, "Fill", "#00FFFFFF")
            ui.Update("Label_" p, "Foreground", menu.selectedText)
        }

        OnHover(menu) {
            this.State := 1
            this.RenderHover(menu)
            if (this.Name != "")
                ToolTip(this.Name)
        }

        OnLeave(menu) {
            if (!this.State)
                return
            this.State := 0
            this.RenderNormal(menu)
            ToolTip()
        }
    }

    ui := 0
    sectors := []
    hoveredIdx := 0
    closed := false
    winSize := 0
    resultObj := 0

    static Show(options) {
        menu := XamlRadialMenu()
        menu.Run(options)
        return menu.resultObj
    }

    static _H(menu, idx) {
        v := idx
        return { Select: (*) => menu.DoSelect(v), Hover: (*) => menu.DoHover(v), Leave: (*) => menu.DoLeave(v) }
    }

    Run(options) {
        items := options.HasProp("Items") ? options.Items : []
        radius := options.HasProp("Radius") ? options.Radius : 172
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
        x := options.HasProp("X") ? options.X : ""
        y := options.HasProp("Y") ? options.Y : ""
        owner := options.HasProp("Owner") ? options.Owner : 0
        triggerKey := options.HasProp("TriggerKey") ? options.TriggerKey : ""

        dpiX := 0
        DllCall("shcore\GetDpiForMonitor", "Ptr", DllCall("user32\MonitorFromPoint", "Int64", (x != "" ? x : A_ScreenWidth / 2) & 0xFFFFFFFF | ((y != "" ? y : A_ScreenHeight / 2) << 32), "UInt", 2, "Ptr"), "Int", 0, "UInt*", &dpiX, "UInt*", 0)
        dpiScale := dpiX > 0 ? dpiX / 96.0 : 1.0

        itemCount := items.Length
        if (itemCount < 1)
            itemCount := 8
        if (itemCount > 16)
            itemCount := 16

        radius := Round(radius * dpiScale)
        innerR := Round(innerR * dpiScale)
        iconSize := Round(iconSize * dpiScale)
        fontSize := Round(fontSize * dpiScale)

        pad := Round(4 * dpiScale)
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
        winLeft := Round(finalX) - cx
        winTop := Round(finalY) - cy

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
            this.sectors.Push(XamlRadialMenu.WheelSector(idx, name, imgPath, cb, startAngle, endAngle, midAngle))
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

        centerBtn := canvas.Add("Ellipse").Name("CenterBtn")
        centerBtn.Width(innerR * 2).Height(innerR * 2)
        centerBtn.Canvas_Left(cx - innerR).Canvas_Top(cy - innerR)
        centerBtn.Fill("#00000000").Stroke("#00000000").StrokeThickness(0).IsHitTestVisible("False")

        centerIcon := canvas.Add("TextBlock").Name("CenterIcon")
        centerIcon.Text("")
        centerIcon.IsHitTestVisible("False")

        this.ui := XAMLHost(win.ToString(), "", owner)
        this.resultObj := { Selected: "", SelectedIndex: -1, SelectedName: "" }

        this.ui.OnEvent("Window", "LoadedHwnd", (*) => this._OnLoaded())

        Loop itemCount {
            idx := A_Index
            h := XamlRadialMenu._H(this, idx)
            this.ui.OnEvent("Wedge_" idx, "PreviewMouseLeftButtonDown", h.Select)
            this.ui.OnEvent("IconBg_" idx, "PreviewMouseLeftButtonDown", h.Select)
            this.ui.OnEvent("Wedge_" idx, "MouseMove", h.Hover)
            this.ui.OnEvent("IconBg_" idx, "MouseMove", h.Hover)
            this.ui.OnEvent("Wedge_" idx, "MouseLeave", h.Leave)
            this.ui.OnEvent("IconBg_" idx, "MouseLeave", h.Leave)
        }

        this.ui.OnEvent("CenterBtn", "PreviewMouseLeftButtonDown", (*) => this.DoCancel())
        this.ui.OnEvent("CenterBtn", "MouseMove", (*) => this.DoCenterEnter())
        this.ui.OnEvent("CenterBtn", "MouseLeave", (*) => this.DoCenterLeave())
        this.ui.OnEvent("RootCanvas", "MouseMove", (*) => this.DoCanvasMove())

        this.ui.Show()

        startTime := A_TickCount
        while (!this.ui.wpfHwnd && A_TickCount - startTime < 5000)
            Sleep(20)

        for sec in this.sectors {
            if (sec.ImagePath != "" && FileExist(sec.ImagePath))
                this.ui.Update("Icon_" sec.Index, "Source", sec.ImagePath)
        }

        while (this.resultObj.Selected == "" && !this.closed && ProcessExist(this.ui.pid))
            Sleep(50)
    }

    _OnLoaded() {
    }

    DoSelect(idx, *) {
        this.closed := true
        sec := this.sectors[idx]
        sec.RenderSelected(this)
        Sleep(150)
        this.resultObj.Selected := sec.Name
        this.resultObj.SelectedIndex := idx
        this.resultObj.SelectedName := sec.Name
        ToolTip()
        this.ui.Update("Window", "Close", "")
        if (IsObject(sec.Callback))
            try sec.Callback.Call(idx, sec.Name)
    }

    DoHover(idx, *) {
        prevIdx := this.hoveredIdx
        if (prevIdx > 0 && prevIdx != idx)
            this.sectors[prevIdx].OnLeave(this)
        this.hoveredIdx := idx
        this.sectors[idx].OnHover(this)
    }

    DoLeave(idx, *) {
        if (this.hoveredIdx == idx) {
            this.hoveredIdx := 0
            this.sectors[idx].OnLeave(this)
        }
    }

    DoCanvasMove(*) {
        idx := this.hoveredIdx
        if (idx > 0) {
            this.hoveredIdx := 0
            this.sectors[idx].OnLeave(this)
        }
    }

    DoCenterEnter(*) {
        idx := this.hoveredIdx
        if (idx > 0) {
            this.sectors[idx].OnLeave(this.ui)
            this.hoveredIdx := 0
        }
        this.ui.Update("CenterBtn", "Fill", "#FFDDDDDD")
        this.ui.Update("CenterBtn", "Stroke", "#FFAAAAAA")
        this.ui.Update("CenterIcon", "Foreground", "#666666")
    }

    DoCenterLeave(*) {
        this.ui.Update("CenterBtn", "Fill", "#FFEEEEEE")
        this.ui.Update("CenterBtn", "Stroke", "#FFCCCCCC")
        this.ui.Update("CenterIcon", "Foreground", "#999999")
    }

    DoCancel(*) {
        this.closed := true
        this.resultObj.Selected := "__CANCEL__"
        this.resultObj.SelectedIndex := -1
        this.resultObj.SelectedName := ""
        ToolTip()
        this.ui.Update("Window", "Close", "")
    }
}

OnTestSectorSelected(idx, name) {
    MsgBox("扇区 " idx " 被选中: " name, "Callback", "64 T2")
}

global g_radialMenu := 0

#HotIf WinActive("ahk_exe AutoHotkey64.exe") or !WinExist("ahk_class #32770")
F2:: {
    global g_radialMenu
    if (IsObject(g_radialMenu) && !g_radialMenu.closed) {
        g_radialMenu.DoCancel()
        return
    }
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)

    g_radialMenu := XamlRadialMenu()
    g_radialMenu.Run({
        Items: [
            { Name: "移动",   Image: "C:\\Users\\yun\\Desktop\\test.gif", Callback: OnTestSectorSelected },
            { Name: "点击",   Image: "C:\\Users\\yun\\Desktop\\test.gif", Callback: OnTestSectorSelected },
            { Name: "滚动",   Image: "" },
            { Name: "延迟",   Image: "" },
            { Name: "循环",   Image: "" },
            { Name: "搜索",   Image: "" },
            { Name: "输入",   Image: "" },
            { Name: "声音",   Image: "" }
        ],
        X: mx,
        Y: my,
        Radius: 150,
        InnerRadius: 60,
        NormalFill: "#ffe5ff00",
        SelectedFill: "#FFFF6B00",
        HoverStroke: "#FFFF6B00"
    })

    result := g_radialMenu.resultObj
    if (result.Selected == "__CANCEL__")
        MsgBox("已取消", "XamlRadialMenu", "64 T1")
}
#HotIf

Persistent()
