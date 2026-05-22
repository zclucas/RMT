#Requires AutoHotkey v2.0
#Include "XAML_Host.ahk"
#Include "XAML_Generator.ahk"
; ==============================================================================
; SIMPLE COMPONENTS (Prototype Extensions)
; ==============================================================================

XAMLElement.Prototype.DefineProp("TelemetryRow", { Call: _TelemetryRow })
_TelemetryRow(this, id, location, latencyMs, status, statusColor) {
    rowGrid := this.Add("ListBoxItem").Add("Grid")
    rowGrid.Cols("120", "170", "80", "*")
    rowGrid.Add("TextBlock").Grid_Column(0).Text(id).Foreground("{DynamicResource TextMain}").Margin("10,0,0,0").VerticalAlignment("Center")
    rowGrid.Add("TextBlock").Grid_Column(1).Text(location).Foreground("{DynamicResource TextSub}").VerticalAlignment("Center")
    rowGrid.Add("TextBlock").Grid_Column(2).Text(latencyMs).Foreground(statusColor).VerticalAlignment("Center")

    border := rowGrid.Add("Border").Grid_Column(3).Background("#20" StrReplace(statusColor, "#", "")).HorizontalAlignment("Left").Padding("8,3").CornerRadius(4)
    border.Add("TextBlock").Text(status).Foreground(statusColor).FontSize(10).FontWeight("Bold")
    return this
}

XAMLElement.Prototype.DefineProp("Toggle", { Call: _Toggle })
_Toggle(this, name, label, isChecked := false, tooltip := "") {
    grid := this.Add("Grid").Margin("0,0,0,15")
    grid.Add("TextBlock").Text(label).Foreground("{DynamicResource TextMain}").VerticalAlignment("Center")
    chk := grid.Add("CheckBox").Name(name).Style("{StaticResource ToggleSwitch}").HorizontalAlignment("Right")
    if (isChecked)
        chk.IsChecked()
    if (tooltip != "")
        chk.ToolTip(tooltip)
    return this
}

XAMLElement.Prototype.DefineProp("SegmentGroup", { Call: _SegmentGroup })
_SegmentGroup(this, groupName, options, selectedIndex := 1) {
    border := this.Add("Border").Use("CardPanel").HorizontalAlignment("Left").Margin("0,0,0,25")
    sp := border.Add("StackPanel").Orientation("Horizontal")
    for index, opt in options {
        rb := sp.Add("RadioButton").Style("{StaticResource SegmentedBtn}").Content(opt).GroupName(groupName)
        if (index == selectedIndex)
            rb.IsChecked()
        if (index < options.Length)
            rb.BorderThickness("0,0,1,0")
        else
            rb.BorderThickness("0")
    }
    return this
}

XAMLElement.Prototype.DefineProp("MetricCard", { Call: _MetricCard })
_MetricCard(this, title, mainValue, subValue, subColor := "#32D74B", progressValue := -1) {
    card := this.Add("Border").Use("CardPanel").Padding("15")
    sp := card.Add("StackPanel")
    sp.Add("TextBlock").Text(title).Foreground("{DynamicResource TextSub}").FontSize(10).FontWeight("Bold")
    sp.Add("TextBlock").Text(mainValue).Foreground("{DynamicResource TextMain}").FontSize(24).FontWeight("Light").Margin("0,10,0,0")

    if (progressValue != -1) {
        sp.Add("ProgressBar").Value(progressValue).Maximum(100).Height(4).Margin("0,10,0,0").Foreground("{DynamicResource Accent}").Background("{DynamicResource ControlBorder}").BorderThickness(0)
    } else {
        sp.Add("TextBlock").Text(subValue).Foreground(subColor).FontSize(11).Margin("0,5,0,0")
    }
    return card
}


; ==============================================================================
; COMPLEX COMPONENTS (Stateful Classes)
; ==============================================================================

class XColorPicker {
    static Show(options) {
        title := options.HasProp("Title") ? options.Title : "Select Color"
        defaultColor := options.HasProp("DefaultColor") ? options.DefaultColor : "#FF0A84FF"
        owner := options.HasProp("Owner") ? options.Owner : 0
        modal := options.HasProp("Modal") ? options.Modal : false
        themeName := options.HasProp("Theme") ? options.Theme : "Dark Mica (Win 11)"
        iniPath := options.HasProp("IniPath") ? options.IniPath : (FileExist("themes.ini") ? "themes.ini" : "../themes.ini")

        bgRes := "DropdownBg"
        if FileExist(iniPath) {
            try {
                themeData := IniRead(iniPath, themeName)
                Loop Parse, themeData, "`n", "`r" {
                    parts := StrSplit(A_LoopField, "=", " `t", 2)
                    if (parts.Length == 2 && parts[1] == "Window_DWM") {
                        if (SubStr(parts[2], 1, 1) == "2" || SubStr(parts[2], 1, 1) == "3")
                            bgRes := "BgColor"
                        break
                    }
                }
            }
        }

        main := XAML_Generator("Grid").Background("{DynamicResource " bgRes "}")
        main.Rows("40", "10", "180", "15", "Auto", "15", "Auto", "15", "Auto")

        ; Titlebar
        tb := main.Add("Grid").Grid_Row(0).Background("Transparent").Name("DragArea").Margin("15,10,15,0")
        tb.Cols("Auto", "*", "Auto")

        iconChar := options.HasProp("Icon") ? options.Icon : ""
        iconColor := options.HasProp("IconColor") ? options.IconColor : "{DynamicResource Accent}"

        if (iconChar != "") {
            tb.Add("TextBlock").Text(iconChar).Foreground(iconColor).FontSize(16).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").VerticalAlignment("Center").Margin("0,0,10,0").Grid_Column(0)
            tb.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").FontSize(14).FontWeight("Bold").VerticalAlignment("Center").Grid_Column(1)
        } else {
            tb.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").FontSize(14).FontWeight("Bold").VerticalAlignment("Center").Grid_Column(0).Grid_ColumnSpan(2)
        }

        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        closeBtn := tb.Add("Button").Name("BtnClose").WindowChrome_IsHitTestVisibleInChrome("True").Width(30).Height(30).HorizontalAlignment("Right").Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness(0).Grid_Column(2)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; 2D Color Canvas
        canvasGrid := main.Add("Grid").Name("CanvasGrid").Grid_Row(2).Margin("15,0,15,0").ClipToBounds("True")
        canvasGrid.Add("Border").Name("CanvasBg").Background("#FFFF0000").CornerRadius("6")

        wGr := canvasGrid.Add("Border").CornerRadius("6").Add("Border.Background").Add("LinearGradientBrush").StartPoint("0,0").EndPoint("1,0")
        wGr.Add("GradientStop").Color("#FFFFFFFF").Offset("0")
        wGr.Add("GradientStop").Color("#00FFFFFF").Offset("1")

        bGr := canvasGrid.Add("Border").CornerRadius("6").Add("Border.Background").Add("LinearGradientBrush").StartPoint("0,1").EndPoint("0,0")
        bGr.Add("GradientStop").Color("#FF000000").Offset("0")
        bGr.Add("GradientStop").Color("#00000000").Offset("1")

        canvasArea := canvasGrid.Add("Grid").Name("CanvasArea").Background("Transparent").Cursor("Cross")
        canvasArea.Add("Ellipse").Name("CanvasThumb").HorizontalAlignment("Left").VerticalAlignment("Top").Width("14").Height("14").Stroke("White").StrokeThickness("2").Fill("Transparent").Margin("-7,-7,0,0").IsHitTestVisible("False")

        ; Sliders Row
        sliderGrid := main.Add("Grid").Grid_Row(4).Margin("15,0,15,0")
        sliderGrid.Cols("Auto", "*", "Auto")

        sliderGrid.Add("Border").Width("36").Height("36").CornerRadius("18").Background("#15FFFFFF").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Grid_Column(0).Margin("0,0,15,0").Add("TextBlock").Text(Chr(0xE891)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("16").Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").HorizontalAlignment("Center")

        sliders := sliderGrid.Add("StackPanel").Grid_Column(1).VerticalAlignment("Center").Margin("0,0,15,0")

        hueBg := sliders.Add("Border").Height("10").CornerRadius("5").Margin("0,0,0,12").Add("Border.Background").Add("LinearGradientBrush").StartPoint("0,0").EndPoint("1,0")
        hueBg.Add("GradientStop").Color("#FFFF0000").Offset("0")
        hueBg.Add("GradientStop").Color("#FFFFFF00").Offset("0.16")
        hueBg.Add("GradientStop").Color("#FF00FF00").Offset("0.33")
        hueBg.Add("GradientStop").Color("#FF00FFFF").Offset("0.5")
        hueBg.Add("GradientStop").Color("#FF0000FF").Offset("0.66")
        hueBg.Add("GradientStop").Color("#FFFF00FF").Offset("0.83")
        hueBg.Add("GradientStop").Color("#FFFF0000").Offset("1")
        sliders.Add("Slider").Name("HueSlider").Minimum("0").Maximum("360").Value("0").Margin("0,-18,0,0")

        alphaBg := sliders.Add("Border").Height("10").CornerRadius("5").Background("Transparent").ClipToBounds("True")

        ; Dynamic Fill overlay masked by a transparent-to-white gradient
        alphaFill := alphaBg.Add("Rectangle").Name("AlphaFillRect").Fill("White")
        mask := alphaFill.Add("Rectangle.OpacityMask").Add("LinearGradientBrush").StartPoint("0,0").EndPoint("1,0")
        mask.Add("GradientStop").Color("Transparent").Offset("0")
        mask.Add("GradientStop").Color("White").Offset("1")
        sliders.Add("Slider").Name("AlphaSlider").Minimum("0").Maximum("255").Value("255").Margin("0,-14,0,0")

        sliderGrid.Add("Border").Name("ColorPreview").Grid_Column(2).Width("36").Height("36").CornerRadius("18").Background(defaultColor).BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; Inputs Row
        inGrid := main.Add("Grid").Grid_Row(6).Margin("15,0,15,0")
        inGrid.Cols("Auto", "15", "Auto")
        inGrid.Rows("Auto", "5", "Auto", "5", "Auto")

        inGrid.Add("TextBlock").Text("HEX").Foreground("{DynamicResource TextSub}").FontSize("10").Grid_Row(0).Grid_Column(0)

        spLbl := inGrid.Add("StackPanel").Grid_Row(0).Grid_Column(2).Orientation("Horizontal")
        spLbl.Add("TextBlock").Text("RGB").Foreground("{DynamicResource TextSub}").FontSize("10").Margin("0,0,4,0")
        spLbl.Add("TextBlock").Text(Chr(0xE70D)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Foreground("{DynamicResource TextSub}").FontSize("8").VerticalAlignment("Center")

        inGrid.Add("TextBox").Name("HexInput").Text(defaultColor).Width("85").Height("28").Padding("8,4").Grid_Row(2).Grid_Column(0)

        rgbSp := inGrid.Add("StackPanel").Grid_Row(2).Grid_Column(2).Orientation("Horizontal")
        rgbSp.Add("TextBlock").Text("R:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,4,0")
        rgbSp.Add("TextBox").Name("RInput").Text("255").Width("35").Height("28").Padding("2,4").Margin("0,0,8,0").HorizontalContentAlignment("Center")
        rgbSp.Add("TextBlock").Text("G:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,4,0")
        rgbSp.Add("TextBox").Name("GInput").Text("0").Width("35").Height("28").Padding("2,4").Margin("0,0,8,0").HorizontalContentAlignment("Center")
        rgbSp.Add("TextBlock").Text("B:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,4,0")
        rgbSp.Add("TextBox").Name("BInput").Text("0").Width("35").Height("28").Padding("2,4").Margin("0,0,8,0").HorizontalContentAlignment("Center")
        rgbSp.Add("TextBlock").Text("A:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,4,0")
        rgbSp.Add("TextBox").Name("AInput").Text("255").Width("35").Height("28").Padding("2,4").HorizontalContentAlignment("Center")

        inGrid.Add("TextBlock").Text("Some information about this color").Foreground("{DynamicResource TextSub}").FontSize("11").Grid_Row(4).Grid_ColumnSpan(3).Margin("0,10,0,0")

        btnSp := main.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right").Grid_Row(8).Margin("0,0,15,15")
        main.InjectResources('<Style x:Key="DialogBtn" TargetType="Button"><Setter Property="Background" Value="#10FFFFFF"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="15,6"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#20FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style><Style x:Key="DialogPrimaryBtn" TargetType="Button"><Setter Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="15,6"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        btnSp.Add("Button").Name("BtnCancel").Content("Cancel").Style("{StaticResource DialogBtn}").Width("100").Height("32").Cursor("Hand").Margin("0,0,10,0")
        btnSp.Add("Button").Name("BtnConfirm").Content("Confirm").Style("{StaticResource DialogPrimaryBtn}").Width("100").Height("32").Cursor("Hand")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Width="360" SizeToContent="Height" ResizeMode="NoResize" Topmost="True"')

        resultObj := { Color: "", Status: "Cancel", Instance: ui, IsDragging: false, Hue: 0.0, Sat: 1.0, Val: 1.0, Alpha: 255, R: 0, G: 0, B: 0, LastMoveTime: 0 }

        if (modal && owner)
            WinSetEnabled(0, "ahk_id " owner)

        ui.OnEvent("Window", "LoadedHwnd", (state, ctrl, event) => XColorPicker.OnLoad(ui, owner, themeName, iniPath, defaultColor, resultObj))
        ui.OnEvent("Window", "Closing", (state, ctrl, event) => XColorPicker.OnClose(resultObj, owner, modal))

        ui.OnEvent("CanvasArea", "PreviewMouseLeftButtonDown", ObjBindMethod(XColorPicker, "OnCanvasDown", ui, resultObj))
        ui.OnEvent("CanvasArea", "PreviewMouseLeftButtonUp", ObjBindMethod(XColorPicker, "OnCanvasUp", ui, resultObj))
        ui.OnEvent("CanvasArea", "PreviewMouseMove", ObjBindMethod(XColorPicker, "OnCanvasMove", ui, resultObj))

        ui.OnEvent("HueSlider", "ValueChanged", ObjBindMethod(XColorPicker, "OnHueSlider", ui, resultObj))
        ui.OnEvent("AlphaSlider", "ValueChanged", ObjBindMethod(XColorPicker, "OnAlphaSlider", ui, resultObj))

        ui.OnEvent("RInput", "TextChanged", ObjBindMethod(XColorPicker, "UpdateFromRGB", ui, resultObj))
        ui.OnEvent("GInput", "TextChanged", ObjBindMethod(XColorPicker, "UpdateFromRGB", ui, resultObj))
        ui.OnEvent("BInput", "TextChanged", ObjBindMethod(XColorPicker, "UpdateFromRGB", ui, resultObj))
        ui.OnEvent("AInput", "TextChanged", ObjBindMethod(XColorPicker, "UpdateFromRGB", ui, resultObj))
        ui.OnEvent("HexInput", "TextChanged", ObjBindMethod(XColorPicker, "UpdateFromHex", ui, resultObj))

        ui.OnEvent("BtnClose", "Click", (state, ctrl, event) => ui.Update("Window", "Close", ""))
        ui.OnEvent("BtnCancel", "Click", (state, ctrl, event) => ui.Update("Window", "Close", ""))
        ui.OnEvent("BtnConfirm", "Click", (state, ctrl, event) => XColorPicker.ConfirmSelection(ui, resultObj, state))

        ui.Track("HueSlider")
        ui.Track("AlphaSlider")
        ui.Track("RInput")
        ui.Track("GInput")
        ui.Track("BInput")
        ui.Track("AInput")
        ui.Track("HexInput")

        ui.Show()

        while (resultObj.Status == "Cancel" && ProcessExist(ui.pid)) {
            Sleep(50)
        }

        if (modal && owner)
            WinSetEnabled(1, "ahk_id " owner)

        return resultObj
    }

    static OnLoad(ui, owner, themeName, iniPath, defaultColor, resultObj, state := "", ctrl := "", event := "") {
        if owner
            ui.Update("Window", "NativeOwner", owner)
        if FileExist(iniPath) {
            try {
                themeData := IniRead(iniPath, themeName)
                Loop Parse, themeData, "`n", "`r" {
                    parts := StrSplit(A_LoopField, "=", " `t", 2)
                    if (parts.Length == 2) {
                        key := parts[1]
                        val := parts[2]
                        if (key == "Window_DWM")
                            ui.Update("Window", "DWM", val)
                        else if (InStr(key, "Resource_") == 1)
                            ui.Update("Resource", SubStr(key, 10), val)
                    }
                }
            }
        }
        XColorPicker.ParseHex(defaultColor, ui, resultObj)
    }

    static OnClose(resultObj, owner, modal, state := "", ctrl := "", event := "") {
        if owner && modal
            WinSetEnabled(1, "ahk_id " owner)
    }

    static ConfirmSelection(ui, resultObj, state) {
        if state.Has("HexInput")
            resultObj.Color := state["HexInput"]
        resultObj.Status := "OK"
        ui.Update("Window", "Close", "")
    }

    static OnCanvasDown(ui, resultObj, state, ctrl, event) {
        resultObj.IsDragging := true
        XColorPicker.ProcessCanvasMouse(ui, resultObj)
    }

    static OnCanvasUp(ui, resultObj, state, ctrl, event) {
        resultObj.IsDragging := false
    }

    static OnCanvasMove(ui, resultObj, state, ctrl, event) {
        if (resultObj.IsDragging && A_TickCount - resultObj.LastMoveTime >= 16) {
            resultObj.LastMoveTime := A_TickCount
            XColorPicker.ProcessCanvasMouse(ui, resultObj)
        }
    }

    static ProcessCanvasMouse(ui, resultObj) {
        CoordMode("Mouse", "Client")
        MouseGetPos(&mX, &mY, &mWin)

        ; If the user dragged far away, we still process relative to the start window
        ; Canvas is at X=15, Y=50. Width=330, Height=180
        x := mX - 15
        y := mY - 50

        if (x < 0)
            x := 0
        if (x > 330)
            x := 330
        if (y < 0)
            y := 0
        if (y > 180)
            y := 180

        resultObj.Sat := x / 330.0
        resultObj.Val := 1.0 - (y / 180.0)

        ui.Update("CanvasThumb", "Margin", String(x - 7) "," String(y - 7) ",0,0")

        XColorPicker.UpdateFromHSV(ui, resultObj)
    }

    static OnHueSlider(ui, resultObj, state, ctrl, event) {
        if state.Has("HueSlider") {
            newHue := Float(state["HueSlider"])
            if (Abs(newHue - resultObj.Hue) < 0.1)
                return
            resultObj.Hue := newHue

            ; Update canvas background hue
            hHex := XColorPicker.HSVtoHEX(resultObj.Hue, 1.0, 1.0)
            ui.Update("CanvasBg", "Background", hHex)

            XColorPicker.UpdateFromHSV(ui, resultObj)
        }
    }

    static OnAlphaSlider(ui, resultObj, state, ctrl, event) {
        if state.Has("AlphaSlider") {
            a := Integer(state["AlphaSlider"])
            if (a == resultObj.Alpha)
                return
            resultObj.Alpha := a
            ui.Update("AInput", "Text", String(a))
            XColorPicker.UpdateFromHSV(ui, resultObj)
        }
    }

    static UpdateFromHex(ui, resultObj, state, ctrl, event) {
        if !state.Has("HexInput")
            return
        hex := state["HexInput"]
        if (StrLen(hex) == 7 || StrLen(hex) == 9)
            XColorPicker.ParseHex(hex, ui, resultObj)
    }

    static UpdateFromRGB(ui, resultObj, state, ctrl, event) {
        try {
            r := state["RInput"] != "" ? Integer(state["RInput"]) : 0
            g := state["GInput"] != "" ? Integer(state["GInput"]) : 0
            b := state["BInput"] != "" ? Integer(state["BInput"]) : 0
            a := state["AInput"] != "" ? Integer(state["AInput"]) : 255

            r := Min(Max(r, 0), 255)
            g := Min(Max(g, 0), 255)
            b := Min(Max(b, 0), 255)
            a := Min(Max(a, 0), 255)

            if (r == resultObj.R && g == resultObj.G && b == resultObj.B && a == resultObj.Alpha)
                return

            resultObj.R := r
            resultObj.G := g
            resultObj.B := b
            resultObj.Alpha := a

            ui.Update("AlphaSlider", "Value", String(a))
            XColorPicker.RgbToHsv(r, g, b, &h, &s, &v)
            resultObj.Hue := h
            resultObj.Sat := s
            resultObj.Val := v

            ui.Update("HueSlider", "Value", String(h))
            ui.Update("CanvasBg", "Background", XColorPicker.HSVtoHEX(h, 1.0, 1.0))

            x := s * 330.0
            y := (1.0 - v) * 180.0
            ui.Update("CanvasThumb", "Margin", String(x - 7) "," String(y - 7) ",0,0")

            hex := Format("#{:02X}{:02X}{:02X}{:02X}", a, r, g, b)
            ui.Update("HexInput", "Text", hex)
            ui.Update("ColorPreview", "Background", hex)
        }
    }

    static ParseHex(hex, ui, resultObj) {
        if RegExMatch(hex, "^#?([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})$", &m) {
            resultObj.Alpha := Integer("0x" m[1]), r := Integer("0x" m[2]), g := Integer("0x" m[3]), b := Integer("0x" m[4])
        } else if RegExMatch(hex, "^#?([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})$", &m) {
            resultObj.Alpha := 255, r := Integer("0x" m[1]), g := Integer("0x" m[2]), b := Integer("0x" m[3])
        } else {
            return
        }

        ui.Update("RInput", "Text", String(r))
        ui.Update("GInput", "Text", String(g))
        ui.Update("BInput", "Text", String(b))
        ui.Update("AInput", "Text", String(resultObj.Alpha))
        ; The UpdateFromRGB hook will naturally fire, but we'll force it here to be safe
        XColorPicker.UpdateFromRGB(ui, resultObj, Map("RInput", String(r), "GInput", String(g), "BInput", String(b), "AInput", String(resultObj.Alpha)), "", "")
    }

    static UpdateFromHSV(ui, resultObj) {
        h := resultObj.Hue
        s := resultObj.Sat
        v := resultObj.Val

        c := v * s
        x := c * (1.0 - Abs(Mod(h / 60.0, 2) - 1.0))
        m := v - c

        r := 0.0, g := 0.0, b := 0.0
        if (0 <= h && h < 60) {
            r := c, g := x, b := 0
        } else if (60 <= h && h < 120) {
            r := x, g := c, b := 0
        } else if (120 <= h && h < 180) {
            r := 0, g := c, b := x
        } else if (180 <= h && h < 240) {
            r := 0, g := x, b := c
        } else if (240 <= h && h < 300) {
            r := x, g := 0, b := c
        } else if (300 <= h <= 360) {
            r := c, g := 0, b := x
        }

        rInt := Round((r + m) * 255)
        gInt := Round((g + m) * 255)
        bInt := Round((b + m) * 255)

        alpha := resultObj.Alpha

        if (rInt == resultObj.R && gInt == resultObj.G && bInt == resultObj.B)
            return

        resultObj.R := rInt
        resultObj.G := gInt
        resultObj.B := bInt

        ui.Update("RInput", "Text", String(rInt))
        ui.Update("GInput", "Text", String(gInt))
        ui.Update("BInput", "Text", String(bInt))

        ; Update Alpha slider preview to match current RGB color
        baseHex := Format("#FF{:02X}{:02X}{:02X}", rInt, gInt, bInt)
        ui.Update("AlphaFillRect", "Fill", baseHex)

        hex := Format("#{:02X}{:02X}{:02X}{:02X}", alpha, rInt, gInt, bInt)
        ui.Update("ColorPreview", "Background", hex)
        ui.Update("HexInput", "Text", hex)
    }

    static HSVtoHEX(h, s, v) {
        c := v * s
        x := c * (1.0 - Abs(Mod(h / 60.0, 2) - 1.0))
        m := v - c
        r := 0.0, g := 0.0, b := 0.0
        if (0 <= h && h < 60) {
            r := c, g := x, b := 0
        } else if (60 <= h && h < 120) {
            r := x, g := c, b := 0
        } else if (120 <= h && h < 180) {
            r := 0, g := c, b := x
        } else if (180 <= h && h < 240) {
            r := 0, g := x, b := c
        } else if (240 <= h && h < 300) {
            r := x, g := 0, b := c
        } else {
            r := c, g := 0, b := x
        }
        return Format("#FF{:02X}{:02X}{:02X}", Round((r + m) * 255), Round((g + m) * 255), Round((b + m) * 255))
    }

    static RgbToHsv(r, g, b, &h, &s, &v) {
        r := r / 255.0, g := g / 255.0, b := b / 255.0
        cmax := Max(r, g, b)
        cmin := Min(r, g, b)
        delta := cmax - cmin

        if (delta == 0)
            h := 0
        else if (cmax == r)
            h := 60 * Mod((g - b) / delta, 6)
        else if (cmax == g)
            h := 60 * (((b - r) / delta) + 2)
        else
            h := 60 * (((r - g) / delta) + 4)

        if (h < 0)
            h += 360

        s := cmax == 0 ? 0 : delta / cmax
        v := cmax
    }
}

class XTokenizer {
    __New(ui, parentXAML, options := {}) {
        this.ui := ui
        this.tags := options.HasProp("InitialTags") ? options.InitialTags : []
        this.logOutput := options.HasProp("LogTarget") ? options.LogTarget : ""

        id := XTokenizer.Count() + 1
        this.wpName := "TokenWrapPanel_" id
        this.inputName := "TxtTokenInput_" id
        this.comboName := "ComboTokenSplit_" id
        this.chkConfirmName := "ChkConfirmDelete_" id
        this.baseId := id
        this.currentText := ""
        this.lastClickTime := 0
        this.lastClickIdx := 0

        tokHeaderSp := parentXAML.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,8")
        tokHeaderSp.Add("TextBlock").Text("TOKENIZING SEARCH (TAGS)").VerticalAlignment("Center").Margin("0,0,15,0").Foreground("{DynamicResource TextSub}").FontSize(11).FontWeight("Bold")
        tokCombo := tokHeaderSp.Add("ComboBox").Name(this.comboName).Width(180).Height(35).SelectedIndex(0)
        tokCombo.Add("ComboBoxItem").Content("Comma (,)")
        tokCombo.Add("ComboBoxItem").Content("Space ( )")
        tokHeaderSp.Add("CheckBox").Name(this.chkConfirmName).Content("Confirm Deletion").VerticalAlignment("Center").Margin("15,0,0,0").IsChecked("True")

        tokBorder := parentXAML.Add("Border").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6").Padding("6,6,0,0").Margin("0,0,0,20")
        tokWp := tokBorder.Add("WrapPanel").Name(this.wpName).Orientation("Horizontal").Background("Transparent").Cursor("IBeam")

        ; Pre-allocate max 15 tags
        Loop 15 {
            tagName := "TagBorder_" this.baseId "_" A_Index
            tagTxtName := "TagText_" this.baseId "_" A_Index
            tagBtnName := "BtnDeleteTag_" this.baseId "_" A_Index

            tag := tokWp.Add("Border").Name(tagName).Style("{StaticResource TagToken}").Visibility("Collapsed")
            tagSp := tag.Add("StackPanel").Orientation("Horizontal")
            tagSp.Add("TextBlock").Name(tagTxtName).Text("").Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").FontSize(12)
            tagSp.Add("Button").Name(tagBtnName).Style("{StaticResource TagTokenCloseBtn}")
        }

        tokWp.Add("TextBox").Name(this.inputName).Background("Transparent").BorderThickness("0").Foreground("{DynamicResource TextMain}").CaretBrush("{DynamicResource TextMain}").AcceptsReturn("True").TextWrapping("Wrap").VerticalAlignment("Center").MinWidth("100").Tag("Add filter...").Margin("0,0,0,6")
    }

    Bind() {
        this.ui.host.Track(this.comboName)
        this.ui.host.Track(this.chkConfirmName)
        this.ui.host.Track(this.inputName)

        this.ui.host.OnEvent(this.inputName, "TextChanged", ObjBindMethod(this, "OnTextChanged"))
        this.ui.host.OnEvent(this.wpName, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "FocusInput"))

        Loop 15 {
            this.ui.host.OnEvent("BtnDeleteTag_" this.baseId "_" A_Index, "Click", ObjBindMethod(this, "OnDeleteClick"))
            this.ui.host.OnEvent("TagBorder_" this.baseId "_" A_Index, "MouseLeftButtonDown", ObjBindMethod(this, "OnTagDoubleClick"))
        }

        this.RenderTags()

        ; Note: Enter validation is handled by keyboard hook in XAML_GUI for simplicity
        ; due to lack of direct KeyDown events in XAMLHost right now.
    }

    RenderTags() {
        Loop 15 {
            tagName := "TagBorder_" this.baseId "_" A_Index
            tagTxtName := "TagText_" this.baseId "_" A_Index
            if (A_Index <= this.tags.Length) {
                this.ui.host.Update(tagTxtName, "Text", this.tags[A_Index])
                this.ui.host.Update(tagName, "Visibility", "Visible")
            } else {
                this.ui.host.Update(tagName, "Visibility", "Collapsed")
                this.ui.host.Update(tagTxtName, "Text", "")
            }
        }
    }

    OnTextChanged(state, ctrl, event) {
        if (!state.Has(this.inputName) || !state.Has(this.comboName))
            return

        this.currentText := state[this.inputName]
        text := state[this.inputName]
        splitMode := state[this.comboName]
        splitChar := (splitMode == "Space ( )") ? " " : ","

        if (InStr(text, splitChar) || InStr(text, "`n") || InStr(text, "`r")) {
            text := StrReplace(text, "`r", "")
            text := StrReplace(text, "`n", "")
            parts := StrSplit(text, splitChar)

            for part in parts {
                trimmed := Trim(part)
                if (trimmed != "" && this.tags.Length < 15) {
                    this.tags.Push(trimmed)
                    if (this.logOutput != "")
                        this.ui.host.Update(this.logOutput, "AddItem", "Captured Tag: " trimmed)
                }
            }
            this.ui.host.Update(this.inputName, "Text", "")
            this.RenderTags()
        }
    }

    OnDeleteClick(state, ctrl, event) {
        parts := StrSplit(ctrl, "_")
        idx := Integer(parts[parts.Length])
        if (state.Has(this.chkConfirmName) && state[this.chkConfirmName] == "True") {
            theme := state.Has("ComboTheme") ? state["ComboTheme"] : "Dark Mica (Win 11)"
            res := XDialog.Show({
                Title: "Delete Tag?",
                Message: "Are you sure you want to remove this tag?",
                Icon: Chr(0xE74D),
                IconColor: "#FF453A",
                Buttons: ["Delete", "Cancel"],
                Width: 350,
                Modal: true,
                Owner: this.ui.host.wpfHwnd,
                Theme: theme
            })
            if (res.Button == "Delete") {
                this.tags.RemoveAt(idx)
                this.RenderTags()
            }
        } else {
            this.tags.RemoveAt(idx)
            this.RenderTags()
        }
    }

    OnTagDoubleClick(state, ctrl, event) {
        parts := StrSplit(ctrl, "_")
        idx := Integer(parts[parts.Length])

        now := A_TickCount
        if (this.lastClickIdx == idx && (now - this.lastClickTime) < 400) {
            ; Double click detected
            if (!state.Has(this.inputName) || state[this.inputName] == "") {
                tagText := this.tags[idx]
                this.tags.RemoveAt(idx)
                this.ui.host.Update(this.inputName, "Text", tagText)
                this.ui.host.Update(this.inputName, "Focus", "True")
                this.RenderTags()
            }
            this.lastClickTime := 0 ; Reset
        } else {
            this.lastClickIdx := idx
            this.lastClickTime := now
        }
    }

    FocusInput(state, ctrl, event) {
        this.ui.host.Update(this.inputName, "Focus", "True")
    }

    ValidateCurrentInput() {
        token := Trim(this.currentText)
        if (token != "" && this.tags.Length < 15) {
            this.tags.Push(token)
            this.ui.host.Update(this.inputName, "Text", "")
            this.currentText := ""
            if (this.logOutput != "")
                this.ui.host.Update(this.logOutput, "AddItem", "Captured Tag: " token)
            this.RenderTags()
        }
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

class XNumericUpDown {
    __New(ui, parentXAML, isDecimal := false, options := {}) {
        this.ui := ui
        this.isDecimal := isDecimal
        this.val := options.HasProp("Default") ? options.Default : (isDecimal ? 3.14 : 42)
        this.id := "NumInput_" XNumericUpDown.Count()

        parentXAML.Add("TextBox").Name(this.id).Style("{StaticResource NumericUpDown}").Text(String(this.val)).HorizontalContentAlignment("Center")
    }

    Bind() {
        this.ui.host.Track(this.id)
        this.ui.host.OnEvent(this.id, "TextChanged", ObjBindMethod(this, "OnTextChanged"))
        ; Up/Down arrows are usually hooked via global hotkeys in the app, but XNumericUpDown exposes Increment/Decrement
    }

    OnTextChanged(state, ctrl, event) {
        valStr := state[this.id]
        if (!this.isDecimal) {
            clean := RegExReplace(valStr, "[^\d\-]")
            if (clean != valStr) {
                this.ui.host.Update(this.id, "Text", clean)
                this.val := (clean != "" && clean != "-") ? Integer(clean) : 0
            } else {
                this.val := (valStr != "" && valStr != "-") ? Integer(valStr) : 0
            }
        } else {
            clean := RegExReplace(valStr, "[^\d\.\-]")
            StrReplace(clean, ".", ".", , &dotCount)
            if (dotCount > 1) {
                clean := SubStr(clean, 1, InStr(clean, ".", , , 2) - 1)
            }
            if (clean != valStr) {
                this.ui.host.Update(this.id, "Text", clean)
            }
            if (clean != "" && clean != "-" && clean != "." && !RegExMatch(clean, "\.$")) {
                this.val := Float(clean)
            }
        }
    }

    Increment(shiftPressed := false) {
        step := shiftPressed ? (this.isDecimal ? 1.0 : 10) : (this.isDecimal ? 0.1 : 1)
        if (this.val + step <= 100) {
            this.val += step
            this.ui.host.Update(this.id, "Text", this.isDecimal ? String(Round(this.val, 2)) : String(this.val))
        }
    }

    Decrement(shiftPressed := false) {
        step := shiftPressed ? (this.isDecimal ? 1.0 : 10) : (this.isDecimal ? 0.1 : 1)
        if (this.val - step >= 0) {
            this.val -= step
            this.ui.host.Update(this.id, "Text", this.isDecimal ? String(Round(this.val, 2)) : String(this.val))
        }
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

; ==============================================================================
; XRibbon Component System
; ==============================================================================

class XRibbon {
    __New(parentXAML) {
        this.container := parentXAML.Name("RibbonMainContainer")
        this.tabCtrl := parentXAML.Add("TabControl").Name("RibbonTabs").Style("{StaticResource RibbonTabControl}")
        
        ; Crucial fix: If the Ribbon is positioned up in the title bar (Grid_Row 0), 
        ; we must explicitly tell WindowChrome that it can be clicked!
        this.tabCtrl.WindowChrome_IsHitTestVisibleInChrome("True")
        
        this.tabs := []
        this.isPinned := true
        this.container.ClipToBounds("False")
    }

    AddTab(title) {
        tabItem := this.tabCtrl.Add("TabItem").Header(title).Style("{StaticResource RibbonTabItem}")
        wrapPanel := tabItem.Add("WrapPanel").Margin("0").Orientation("Horizontal")
        tab := XRibbonTab(wrapPanel)
        this.tabs.Push(tab)
        return tab
    }

    BindEvents(ui) {
        this.ui := ui
        ui.OnEvent("RibbonTabs", "MouseDoubleClick", this.OnDoubleClick.Bind(this))
        ui.OnEvent("RibbonTabs", "PreviewMouseLeftButtonDown", this.OnTabClick.Bind(this))
    }

    OnDoubleClick(state, ctrl, event) {
        if (this.isPinned) {
            this.Collapse()
        } else {
            this.Pin()
        }
        this.UpdateHost()
    }

    OnTabClick(state, ctrl, event) {
        if (!this.isPinned) {
            this.ExpandOverlay()
            this.UpdateHost()
        }
    }

    Pin() {
        this.isPinned := true
        this.container.Height("NaN")
        this.container.Margin("0")
        this.container.ClipToBounds("False")
        this.container.SetProp("Panel.ZIndex", "1")
    }

    Collapse() {
        this.isPinned := false
        this.container.Height(50)
        this.container.Margin("0")
        this.container.ClipToBounds("True")
        this.container.SetProp("Panel.ZIndex", "1")
    }

    ExpandOverlay() {
        this.container.Height("NaN")
        this.container.Margin("0,0,0,-92")
        this.container.ClipToBounds("False")
        this.container.SetProp("Panel.ZIndex", "100")
    }

    UpdateHost() {
        this.ui.Update("RibbonMainContainer", "Height", this.container._Props.Has("Height") ? this.container._Props["Height"] : "NaN")
        this.ui.Update("RibbonMainContainer", "Margin", this.container._Props.Has("Margin") ? this.container._Props["Margin"] : "0")
        this.ui.Update("RibbonMainContainer", "ClipToBounds", this.container._Props.Has("ClipToBounds") ? this.container._Props["ClipToBounds"] : "False")
        this.ui.Update("RibbonMainContainer", "Panel.ZIndex", this.container._Props.Has("Panel.ZIndex") ? this.container._Props["Panel.ZIndex"] : "0")
    }
}

class XRibbonTab {
    __New(wrapPanel) {
        this.panel := wrapPanel
    }

    AddGroup(title) {
        border := this.panel.Add("Border").Style("{StaticResource RibbonGroupBorder}")
        grid := border.Add("Grid")
        grid.Rows("*", "Auto")

        contentPanel := grid.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").Margin("0,0,0,2")

        titleTxt := grid.Add("TextBlock").Grid_Row(1).Text(title).Style("{StaticResource RibbonGroupTitle}")

        return XRibbonGroup(contentPanel)
    }
}

class XRibbonGroup {
    __New(stackPanel) {
        this.panel := stackPanel
    }

    AddLargeBtn(name, text, iconHex) {
        return this.panel.Add("Button").Name(name).Tag(Chr(iconHex)).Content(text).Style("{StaticResource RibbonButtonLarge}")
    }

    AddSmallBtn(name, text, iconHex) {
        return this.panel.Add("Button").Name(name).Tag(Chr(iconHex)).Content(text).Style("{StaticResource RibbonButtonSmall}").Margin("0,0,0,2")
    }

    AddSeparator() {
        return this.panel.Add("Rectangle").Width(1).Fill("{DynamicResource ControlBorder}").Margin("4,2,4,2")
    }

    AddVerticalStack() {
        stack := this.panel.Add("StackPanel").Orientation("Vertical").VerticalAlignment("Center").Margin("2,0")
        return XRibbonGroup(stack)
    }
}

; ==============================================================================
; ADVANCED COMPONENTS SUITE
; ==============================================================================

XAMLElement.Prototype.DefineProp("FileDropZone", { Call: _FileDropZone })
_FileDropZone(this, name, promptTxt, allowedExts) {
    bdr := this.Add("Border").Name(name).BorderThickness("2").CornerRadius("8").Padding("20").Cursor("Hand").AllowDrop("True").Background("Transparent")
    bdr.BorderBrush("{DynamicResource ControlBorder}")

    sp := bdr.Add("StackPanel").VerticalAlignment("Center").HorizontalAlignment("Center").IsHitTestVisible("False")
    sp.Add("TextBlock").Name(name "_Icon").Text(Chr(0xE8B5)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(32).Foreground("{DynamicResource Accent}").HorizontalAlignment("Center").Margin("0,0,0,10")
    sp.Add("TextBlock").Name(name "_Text").Text(promptTxt).Foreground("{DynamicResource TextMain}").FontSize(14).FontWeight("SemiBold").HorizontalAlignment("Center")

    extsStr := ""
    for ext in allowedExts
        extsStr .= ext " "
    sp.Add("TextBlock").Text("Allowed: " extsStr).Foreground("{DynamicResource TextSub}").FontSize(11).HorizontalAlignment("Center").Margin("0,5,0,0")

    return bdr
}

XAMLElement.Prototype.DefineProp("SliderRange", { Call: _SliderRange })
_SliderRange(this, title, minVal, maxVal, defaultStart, defaultEnd) {
    grid := this.Add("Grid").Margin("0,0,0,15")
    grid.Rows("Auto", "Auto", "Auto")
    grid.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").Margin("0,0,0,10").FontWeight("Bold").Grid_Row(0)

    sliderGrid := grid.Add("Grid").Grid_Row(1).Margin("10,0")

    minName := StrReplace(title, " ", "") "_SliderMin"
    maxName := StrReplace(title, " ", "") "_SliderMax"

    ; Bottom Slider (Max Value + Selection Track)
    ; Minimum is clamped to minVal (static), clamping against min-thumb is done via events
    sMax := sliderGrid.Add("Slider").Minimum(minVal).Maximum(maxVal).Value(defaultEnd).Name(maxName)
    sMax.IsSelectionRangeEnabled("True").SelectionStart("{Binding Value, ElementName=" minName "}").SelectionEnd("{Binding Value, ElementName=" maxName "}")
    sMax.InjectResources('<Style TargetType="Slider"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Slider"><Grid VerticalAlignment="Center"><Border Background="{DynamicResource ControlBorder}" Height="4" CornerRadius="2" Margin="8,0" /><Canvas Margin="8,0" Height="4" VerticalAlignment="Center"><Rectangle x:Name="PART_SelectionRange" Fill="{DynamicResource Accent}" Height="4" /></Canvas><Track x:Name="PART_Track"><Track.DecreaseRepeatButton><RepeatButton Background="Transparent" BorderThickness="0" IsHitTestVisible="False"/></Track.DecreaseRepeatButton><Track.IncreaseRepeatButton><RepeatButton Background="Transparent" BorderThickness="0" IsHitTestVisible="False"/></Track.IncreaseRepeatButton><Track.Thumb><Thumb Width="16" Height="16"><Thumb.Template><ControlTemplate TargetType="Thumb"><Ellipse Fill="{DynamicResource Accent}" /></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></Grid></ControlTemplate></Setter.Value></Setter></Style>')

    sMin := sliderGrid.Add("Slider").Minimum(minVal).Maximum(maxVal).Value(defaultStart).Name(minName)
    sMin.InjectResources('<Style TargetType="Slider"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Slider"><Grid VerticalAlignment="Center"><Track x:Name="PART_Track"><Track.DecreaseRepeatButton><RepeatButton Background="Transparent" BorderThickness="0" IsHitTestVisible="False"/></Track.DecreaseRepeatButton><Track.IncreaseRepeatButton><RepeatButton Background="Transparent" BorderThickness="0" IsHitTestVisible="False"/></Track.IncreaseRepeatButton><Track.Thumb><Thumb Width="16" Height="16"><Thumb.Template><ControlTemplate TargetType="Thumb"><Ellipse Fill="{DynamicResource Accent}" /></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></Grid></ControlTemplate></Setter.Value></Setter></Style>')

    tbGrid := grid.Add("Grid").Grid_Row(2).Margin("0,10,0,0")
    tbGrid.Cols("*", "Auto", "*")

    bdrMin := tbGrid.Add("Border").Use("CardPanel").Padding("10,5").Grid_Column(0)
    bdrMin.Add("TextBlock").Text("{Binding Value, ElementName=" minName ", StringFormat={}{0:0}}").Background("Transparent").Foreground("{DynamicResource TextSub}").HorizontalAlignment("Center")

    tbGrid.Add("TextBlock").Text("-").Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("10,0").Grid_Column(1).HorizontalAlignment("Center")

    bdrMax := tbGrid.Add("Border").Use("CardPanel").Padding("10,5").Grid_Column(2)
    bdrMax.Add("TextBlock").Text("{Binding Value, ElementName=" maxName ", StringFormat={}{0:0}}").Background("Transparent").Foreground("{DynamicResource TextSub}").HorizontalAlignment("Center")
}

; ==============================================================================
; DateRangePickerEx — Advanced Date Range Selector
; ==============================================================================
class DateRangePickerEx {
    __New(id, defaultStart, defaultEnd) {
        this.id := id
        this.startStr := StrReplace(defaultStart, "-")
        this.endStr := StrReplace(defaultEnd, "-")
        this.viewYear := SubStr(this.startStr, 1, 4)
        this.viewMonth := SubStr(this.startStr, 5, 2)
        this.startMode := true ; true = waiting for start date, false = waiting for end date
    }

    Build(parent) {
        btn := parent.Add("ToggleButton").Name(this.id "_Btn").Background("Transparent").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Cursor("Hand").Padding("15,5").Height(35)
        btn.InjectResources('<Style TargetType="ToggleButton"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource ControlBgHover}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')
        sp := btn.Add("StackPanel").Orientation("Horizontal")
        sp.Add("TextBlock").Text(Chr(0xE787)).FontFamily("Segoe Fluent Icons").Margin("0,0,10,0").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        sp.Add("TextBlock").Name(this.id "_Display").Text(FormatTime(this.startStr, "yyyy-MM-dd") "  -  " FormatTime(this.endStr, "yyyy-MM-dd")).VerticalAlignment("Center").FontWeight("SemiBold").Foreground("{DynamicResource TextMain}")

        pop := btn.AddRichPopover()

        mainGrid := pop.Add("Grid").Margin("0,0,0,5")
        mainGrid.Cols("Auto", "20", "Auto")

        ; Build Two Calendars
        loop 2 {
            calIdx := A_Index
            cBase := mainGrid.Add("StackPanel").Grid_Column(calIdx == 1 ? 0 : 2).Width(250)

            ; Header
            hdr := cBase.Add("Grid").Margin("0,0,0,15")
            hdr.Cols("Auto", "*", "Auto")

            if (calIdx == 1)
                hdr.Add("Button").Name(this.id "_Prev").Content(Chr(0xE76B)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Use("IconBtn").Width(30).Height(30).Grid_Column(0).Cursor("Hand")

            hdr.Add("TextBlock").Name(this.id "_MonthYear_" calIdx).Text("Month Year").HorizontalAlignment("Center").VerticalAlignment("Center").FontWeight("Bold").FontSize(14).Grid_Column(1)

            if (calIdx == 2)
                hdr.Add("Button").Name(this.id "_Next").Content(Chr(0xE76C)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Use("IconBtn").Width(30).Height(30).Grid_Column(2).Cursor("Hand")

            ; Days of week
            dow := cBase.Add("UniformGrid").Columns(7).Margin("0,0,0,10")
            for d in ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                dow.Add("TextBlock").Text(d).HorizontalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize(11).FontWeight("Bold")

            ; Days Grid
            grid := cBase.Add("UniformGrid").Columns(7)
            loop 42 {
                dayId := (calIdx - 1) * 42 + A_Index

                ; Cell Wrapper
                cell := grid.Add("Grid").Height(32)

                ; Layer 1: Background range highlight (stretches to edges, no corner radius)
                rangeBg := cell.Add("Border").Name(this.id "_RangeBg_" dayId).BorderThickness("0")
                rangeBg.InjectResources('<Style TargetType="Border"><Setter Property="Background" Value="Transparent"/><Style.Triggers><Trigger Property="Tag" Value="Range"><Setter Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Opacity" Value="0.2"/></Trigger></Style.Triggers></Style>')

                ; Layer 2: Circular hover/selection button
                btnDay := cell.Add("Button").Name(this.id "_Day_" dayId).Width(32).Height(32).BorderThickness("0").Cursor("Hand")
                btnDay.InjectResources('<Style TargetType="Button"><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="Background" Value="Transparent"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="16" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBgHover}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter><Style.Triggers><Trigger Property="Tag" Value="Selected"><Setter Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="Tag" Value="Today"><Setter Property="BorderThickness" Value="1"/><Setter Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="{DynamicResource Accent}"/></Trigger></Style.Triggers></Style>')
            }
        }
    }

    Bind(uiHost) {
        this.ui := uiHost
        uiHost.OnEvent(this.id "_Btn", "Click", ObjBindMethod(this, "OnOpen"))
        uiHost.OnEvent(this.id "_Prev", "Click", ObjBindMethod(this, "OnPrev"))
        uiHost.OnEvent(this.id "_Next", "Click", ObjBindMethod(this, "OnNext"))

        loop 84 {
            this._BindDayBtn(uiHost, A_Index)
        }
    }

    _BindDayBtn(uiHost, idx) {
        uiHost.OnEvent(this.id "_Day_" idx, "Click", (state, ctrl, ev) => this.OnDayClick(state, idx))
    }

    OnOpen(state, ctrl, ev) {
        this.Render()
    }

    OnPrev(state, ctrl, ev) {
        this.viewMonth -= 1
        if (this.viewMonth < 1) {
            this.viewMonth := 12
            this.viewYear -= 1
        }
        this.Render()
    }

    OnNext(state, ctrl, ev) {
        this.viewMonth += 1
        if (this.viewMonth > 12) {
            this.viewMonth := 1
            this.viewYear += 1
        }
        this.Render()
    }

    OnDayClick(state, idx) {
        if (!this.dayMap.Has(idx))
            return

        clickedDate := this.dayMap[idx]

        if (this.startMode) {
            this.startStr := clickedDate
            this.endStr := clickedDate
            this.startMode := false
        } else {
            if (clickedDate < this.startStr) {
                this.endStr := this.startStr
                this.startStr := clickedDate
            } else {
                this.endStr := clickedDate
            }
            this.startMode := true
        }

        this.ui.Update(this.id "_Display", "Text", FormatTime(this.startStr, "yyyy-MM-dd") "  -  " FormatTime(this.endStr, "yyyy-MM-dd"))
        this.Render()
    }

    Render() {
        this.dayMap := Map()
        monthNames := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

        loop 2 {
            calIdx := A_Index

            ; Calculate year/month for this calendar
            calMonth := this.viewMonth + (calIdx - 1)
            calYear := this.viewYear
            if (calMonth > 12) {
                calMonth -= 12
                calYear += 1
            }

            y := Format("{:04}", calYear)
            m := Format("{:02}", calMonth)

            this.ui.Update(this.id "_MonthYear_" calIdx, "Text", monthNames[Integer(m)] " " y)

            firstDay := y m "01"
            wDay := FormatTime(firstDay, "WDay")
            startOffset := wDay - 2
            if (startOffset < 0)
                startOffset := 6

            daysInMonth := this.GetDaysInMonth(y, m)

            loop 42 {
                dayId := (calIdx - 1) * 42 + A_Index
                dayNum := A_Index - startOffset

                if (dayNum > 0 && dayNum <= daysInMonth) {
                    currentDate := y m Format("{:02}", dayNum)
                    this.dayMap[dayId] := currentDate

                    this.ui.Update(this.id "_Day_" dayId, "Content", dayNum)
                    this.ui.Update(this.id "_Day_" dayId, "IsEnabled", "True")

                    isStart := (currentDate == this.startStr)
                    isEnd := (currentDate == this.endStr)
                    inRange := (currentDate >= this.startStr && currentDate <= this.endStr)
                    isSingleDayRange := (this.startStr == this.endStr)

                    ; 1. Configure the Circular Button (Foreground)
                    if (isStart || isEnd) {
                        this.ui.Update(this.id "_Day_" dayId, "Tag", "Selected")
                    } else if (currentDate == FormatTime(A_Now, "yyyyMMdd")) {
                        this.ui.Update(this.id "_Day_" dayId, "Tag", "Today")
                    } else {
                        this.ui.Update(this.id "_Day_" dayId, "Tag", "")
                    }

                    ; 2. Configure the Range Band (Background)
                    if (inRange && !isSingleDayRange) {
                        this.ui.Update(this.id "_RangeBg_" dayId, "Tag", "Range")
                        ; Half-fill logic for endpoints to avoid bleeding outside the circle
                        if (isStart)
                            this.ui.Update(this.id "_RangeBg_" dayId, "Margin", "16,0,0,0")
                        else if (isEnd)
                            this.ui.Update(this.id "_RangeBg_" dayId, "Margin", "0,0,16,0")
                        else
                            this.ui.Update(this.id "_RangeBg_" dayId, "Margin", "0,0,0,0")
                    } else {
                        this.ui.Update(this.id "_RangeBg_" dayId, "Tag", "")
                        this.ui.Update(this.id "_RangeBg_" dayId, "Margin", "0")
                    }

                } else {
                    this.ui.Update(this.id "_Day_" dayId, "Content", "")
                    this.ui.Update(this.id "_Day_" dayId, "IsEnabled", "False")
                    this.ui.Update(this.id "_Day_" dayId, "Tag", "")
                    this.ui.Update(this.id "_RangeBg_" dayId, "Tag", "")
                }
            }
        }
    }

    GetDaysInMonth(y, m) {
        m := Integer(m)
        y := Integer(y)
        if (m == 4 || m == 6 || m == 9 || m == 11)
            return 30
        if (m == 2)
            return (Mod(y, 4) == 0 && (Mod(y, 100) != 0 || Mod(y, 400) == 0)) ? 29 : 28
        return 31
    }
}


XAMLElement.Prototype.DefineProp("BreadcrumbBar", { Call: _BreadcrumbBar })
_BreadcrumbBar(this, paths) {
    sp := this.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,15")

    for i, p in paths {
        btn := sp.Add("Button").Content(p).Background("Transparent").BorderThickness(0).Foreground(i == paths.Length ? "{DynamicResource TextMain}" : "{DynamicResource Accent}").FontWeight(i == paths.Length ? "Bold" : "Normal").Cursor("Hand")
        btn.InjectResources('<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.8"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        if (i < paths.Length) {
            chevron := sp.Add("ToggleButton").Content(Chr(0xE76C)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).Foreground("{DynamicResource TextSub}").Background("Transparent").BorderThickness(0).Margin("4,0").Cursor("Hand")
            chevron.InjectResources('<Style TargetType="ToggleButton"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton"><Border Background="{TemplateBinding Background}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.8"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

            pop := chevron.AddRichPopover()
            pop.Add("TextBlock").Text("Sibling Folders").FontWeight("Bold").Margin("0,0,0,5").Foreground("{DynamicResource TextSub}")
            pop.Add("Button").Content(p " Resources").Background("Transparent").BorderThickness(0).HorizontalAlignment("Left")
            pop.Add("Button").Content(p " Configs").Background("Transparent").BorderThickness(0).HorizontalAlignment("Left")
            pop.Add("Button").Content(p " Utils").Background("Transparent").BorderThickness(0).HorizontalAlignment("Left")
        }
    }
    return sp
}

XAMLElement.Prototype.DefineProp("Stepper", { Call: _Stepper })
_Stepper(this, steps, currentIndex) {
    grid := this.Add("Grid").Margin("0,0,0,20")
    grid.Rows("Auto", "Auto")

    colArr := []
    for _ in steps {
        colArr.Push("*")
    }
    grid.Cols(colArr*)

    for i, _ in steps {
        if (i < steps.Length) {
            isCompleted := i < currentIndex
            lineColor := isCompleted ? "{DynamicResource Accent}" : "{DynamicResource ControlBorder}"

            rightGrid := grid.Add("Grid").Grid_Column(i - 1).Grid_Row(0)
            rightGrid.Cols("*", "*")
            rightGrid.Add("Rectangle").Height(2).Fill(lineColor).Grid_Column(1).VerticalAlignment("Center")

            leftGrid := grid.Add("Grid").Grid_Column(i).Grid_Row(0)
            leftGrid.Cols("*", "*")
            leftGrid.Add("Rectangle").Height(2).Fill(lineColor).Grid_Column(0).VerticalAlignment("Center")
        }
    }

    for i, stepText in steps {
        isCompleted := i < currentIndex
        isCurrent := i == currentIndex

        circleBg := isCompleted || isCurrent ? "{DynamicResource Accent}" : "{DynamicResource ControlBg}"
        circleFg := isCompleted || isCurrent ? "White" : "{DynamicResource TextSub}"
        circleBorder := isCurrent ? "{DynamicResource Accent}" : "{DynamicResource ControlBorder}"

        circle := grid.Add("Border").Width(24).Height(24).CornerRadius(12).Background(circleBg).BorderBrush(circleBorder).BorderThickness(isCurrent ? 2 : 1).HorizontalAlignment("Center").Grid_Row(0).Grid_Column(i - 1)

        if (isCompleted) {
            circle.Add("TextBlock").Text(Chr(0xE73E)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).Foreground("White").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,1,0,0")
        } else {
            circle.Add("TextBlock").Text(i).Foreground(circleFg).FontSize(11).FontWeight("Bold").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,2,0,0")
        }

        textFg := isCurrent ? "{DynamicResource TextMain}" : "{DynamicResource TextSub}"
        grid.Add("TextBlock").Text(stepText).Foreground(textFg).FontSize(11).FontWeight(isCurrent ? "Bold" : "Normal").HorizontalAlignment("Center").Margin("0,5,0,0").Grid_Row(1).Grid_Column(i - 1)
    }

    return grid
}

XAMLElement.Prototype.DefineProp("SplitPanel", { Call: _SplitPanel })
_SplitPanel(this, orientation, ratio) {
    rParts := StrSplit(ratio, ":")
    w1 := (rParts.Length >= 1) ? rParts[1] "*" : "1*"
    w2 := (rParts.Length >= 2) ? rParts[2] "*" : "1*"

    grid := this.Add("Grid")

    if (orientation == "Horizontal") {
        grid.Cols(w1, "Auto", w2)
        grid.Add("GridSplitter").Grid_Column(1).Width(5).HorizontalAlignment("Center").Background("Transparent").Cursor("SizeWE")
    } else {
        grid.Rows(w1, "Auto", w2)
        grid.Add("GridSplitter").Grid_Row(1).Height(5).VerticalAlignment("Center").Background("Transparent").Cursor("SizeNS")
    }

    grid.LeftPanel := grid.Add("Border").Grid_Column(0).Grid_Row(0)
    grid.RightPanel := grid.Add("Border").Grid_Column(orientation == "Horizontal" ? 2 : 0).Grid_Row(orientation == "Horizontal" ? 0 : 2)

    grid.DefineProp("SetLeft", { Call: (this, child) => this.LeftPanel.Add(child) })
    grid.DefineProp("SetRight", { Call: (this, child) => this.RightPanel.Add(child) })

    return grid
}

XAMLElement.Prototype.DefineProp("DataTableView", { Call: _DataTableView })
_DataTableView(this, id, dataArray) {
    bdr := this.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(6).Background("{DynamicResource ControlBg}").ClipToBounds("True")
    grid := bdr.Add("Grid")
    grid.Rows("30", "*")

    grid.IsSharedSizeScope("True")

    if (dataArray.Length == 0)
        return bdr

    columns := []
    for key, val in dataArray[1].OwnProps() {
        columns.Push(key)
    }

    headerGrid := grid.Add("Grid").Grid_Row(0).Background("{DynamicResource ControlBgHover}")
    hColDefs := headerGrid.Add("Grid.ColumnDefinitions")
    for i, col in columns {
        hColDefs.Add("ColumnDefinition").Width(i == columns.Length ? "*" : "Auto").SharedSizeGroup("TableCol_" i)
        if (i < columns.Length)
            hColDefs.Add("ColumnDefinition").Width("1") ; Space for splitter
    }

    for i, col in columns {
        colIdx := (i - 1) * 2
        headerGrid.Add("Button").Name(id "_Header_" StrReplace(col, " ", "")).Content(col).Grid_Column(colIdx).Background("Transparent").Foreground("{DynamicResource TextSub}").BorderThickness("0").FontSize(11).FontWeight("Bold").HorizontalContentAlignment("Left").Padding("10,0").Cursor("Hand")

        if (i < columns.Length) {
            headerGrid.Add("GridSplitter").Grid_Column(colIdx + 1).Width(1).HorizontalAlignment("Center").VerticalAlignment("Stretch").Background("{DynamicResource ControlBorder}")
        }
    }

    lb := grid.Add("ListBox").Name(id "_List").Grid_Row(1).Background("Transparent").BorderThickness("0").ScrollViewer_HorizontalScrollBarVisibility("Disabled").HorizontalContentAlignment("Stretch")

    for rIndex, rowObj in dataArray {
        _BuildDataTableRow(lb, columns, rIndex, rowObj)
    }

    return bdr
}

_BuildDataTableRow(parent, columns, rIndex, rowObj) {
    rowGrid := parent.Add("Grid").Background(Mod(rIndex, 2) == 0 ? "{DynamicResource ControlBg}" : "Transparent")
    rColDefs := rowGrid.Add("Grid.ColumnDefinitions")

    for i, col in columns {
        rColDefs.Add("ColumnDefinition").Width(i == columns.Length ? "*" : "Auto").SharedSizeGroup("TableCol_" i)
        if (i < columns.Length)
            rColDefs.Add("ColumnDefinition").Width("1")
    }

    for i, col in columns {
        val := rowObj.HasProp(col) ? rowObj.%col% : ""
        colIdx := (i - 1) * 2
        rowGrid.Add("TextBlock").Text(val).Grid_Column(colIdx).Foreground("{DynamicResource TextMain}").FontSize(12).VerticalAlignment("Center").Margin("10,8").TextTrimming("CharacterEllipsis").ToolTip(val)
    }
    return rowGrid
}


XAMLElement.Prototype.DefineProp("AddRichPopover", { Call: _AddRichPopover })
_AddRichPopover(this) {
    static popoverCounter := 0
    popoverCounter++
    elementName := ""
    if (this._Props.Has("Name") && this._Props["Name"] != "") {
        elementName := this._Props["Name"]
    } else {
        elementName := "PopoverAnchor_" A_TickCount "_" popoverCounter
        this.Name(elementName)
    }

    popup := this.Parent().Add("Popup").PlacementTarget("{Binding Source={x:Reference " elementName "}}").Placement("Bottom").StaysOpen("False").AllowsTransparency("True").IsOpen("{Binding Source={x:Reference " elementName "}, Path=IsChecked, Mode=TwoWay}")
    bdr := popup.Add("Border").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(6).Padding("10").Margin("4")

    bdr.Add("Border.Effect").Add("DropShadowEffect").BlurRadius(12).ShadowDepth(3).Opacity(0.25).Color("Black")

    sp := bdr.Add("StackPanel")
    return sp
}

XAMLElement.Prototype.DefineProp("StatCard", { Call: _StatCard })
_StatCard(this, title, metric, trendText, trendUp) {
    card := this.Add("Border").Use("CardPanel").Padding("20")
    sp := card.Add("StackPanel")

    sp.Add("TextBlock").Text(title).Foreground("{DynamicResource TextSub}").FontSize(12).FontWeight("Bold").Margin("0,0,0,10")
    sp.Add("TextBlock").Text(metric).Foreground("{DynamicResource TextMain}").FontSize(32).FontWeight("Light").Margin("0,0,0,5")

    trendSp := sp.Add("StackPanel").Orientation("Horizontal")
    trendColor := trendUp ? "#32D74B" : "#FF453A"
    trendIcon := trendUp ? Chr(0xE74A) : Chr(0xE74B)

    trendSp.Add("TextBlock").Text(trendIcon).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).Foreground(trendColor).VerticalAlignment("Center").Margin("0,0,5,0")
    trendSp.Add("TextBlock").Text(trendText).Foreground(trendColor).FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center")

    return card
}

XAMLElement.Prototype.DefineProp("Timeline", { Call: _Timeline })
_Timeline(this, events) {
    sp := this.Add("StackPanel")

    for i, evt in events {
        grid := sp.Add("Grid")
        grid.Cols("30", "*")
        grid.Rows("Auto", "*")

        grid.Add("Ellipse").Width(10).Height(10).Fill("{DynamicResource Accent}").Grid_Column(0).Grid_Row(0).HorizontalAlignment("Center").Margin("0,5,0,0")
        if (i < events.Length) {
            grid.Add("Rectangle").Width(2).Fill("{DynamicResource ControlBorder}").Grid_Column(0).Grid_Row(1).HorizontalAlignment("Center").Margin("0,5,0,0").MinHeight(20)
        }

        contentSp := grid.Add("StackPanel").Grid_Column(1).Grid_Row(0).Grid_RowSpan(2).Margin("10,0,0,20")
        contentSp.Add("TextBlock").Text(evt.time).Foreground("{DynamicResource TextSub}").FontSize(10).FontWeight("Bold").Margin("0,0,0,2")
        contentSp.Add("TextBlock").Text(evt.desc).Foreground("{DynamicResource TextMain}").FontSize(13).TextWrapping("Wrap")
    }

    return sp
}

XAMLElement.Prototype.DefineProp("SkeletonLoader", { Call: _SkeletonLoader })
_SkeletonLoader(this, w, h, isCircle := false) {
    bdr := this.Add("Border").Width(w).Height(h).CornerRadius(isCircle ? h / 2 : 4).Background("{DynamicResource ControlBorder}")

    trigger := bdr.Add("Border.Triggers").Add("EventTrigger").RoutedEvent("FrameworkElement.Loaded")
    sb := trigger.Add("BeginStoryboard").Add("Storyboard")
    sb.Add("DoubleAnimation").Storyboard_TargetProperty("Opacity").From(0.4).To(1.0).Duration("0:0:1").AutoReverse("True").RepeatBehavior("Forever")

    return bdr
}

XAMLElement.Prototype.DefineProp("HotKeyBox", { Call: _HotKeyBox })
_HotKeyBox(this, id, defaultVal := "", placeholder := "Press a key combination...") {
    bdr := this.Add("Border").Use("CardPanel").Padding("10,5").BorderThickness(1).BorderBrush("{DynamicResource ControlBorder}")
    grid := bdr.Add("Grid")
    grid.Cols("*", "Auto")

    tb := grid.Add("TextBox").Name(id).Grid_Column(0).Text(defaultVal).Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").Tag(placeholder).IsReadOnly("True").Cursor("Hand")

    grid.Add("TextBlock").Grid_Column(1).Text(Chr(0xE765)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("10,0,0,0")

    return tb
}

class XSegmentedNetworkInput {
    __New(id, type := "IP", defaultVals := []) {
        this.id := id
        this.type := type
        this.defaultVals := defaultVals
        this.count := (type == "IP") ? 4 : 6
        this.sep := (type == "IP") ? "." : ":"
        this.ui := ""
    }

    Build(parent) {
        sp := parent.Add("StackPanel").Orientation("Horizontal")
        bdr := sp.Add("Border").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(4).Padding("4")
        inner := bdr.Add("StackPanel").Orientation("Horizontal")

        loop this.count {
            idx := A_Index
            val := (this.defaultVals.Length >= idx) ? String(this.defaultVals[idx]) : ""
            inner.Add("TextBox").Name(this.id "_Octet_" idx).Text(val).Width(35).Height(24).Padding("0,2").HorizontalContentAlignment("Center").Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}")
            if (idx < this.count)
                inner.Add("TextBlock").Text(this.sep).Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("2,0")
        }
        return sp
    }

    Bind(ui) {
        this.ui := ui
        loop this.count {
            ui.Track(this.id "_Octet_" A_Index)
            ui.OnEvent(this.id "_Octet_" A_Index, "TextChanged", ObjBindMethod(this, "OnTextChanged", A_Index))
        }
    }

    OnTextChanged(idx, state, ctrl, ev) {
        val := state[ctrl]
        orig := val

        if (this.type == "IP")
            val := RegExReplace(val, "[^\d\.\ ]", "")
        else
            val := RegExReplace(val, "[^\da-fA-F\:\ ]", "")

        shouldJump := false

        if (SubStr(val, -1) == this.sep || SubStr(val, -1) == " ") {
            val := StrReplace(val, this.sep, "")
            val := StrReplace(val, " ", "")
            shouldJump := true
        }

        if (val != orig)
            this.ui.Update(ctrl, "Text", val)

        if (shouldJump) {
            if (idx < this.count)
                this.ui.Update(this.id "_Octet_" (idx + 1), "Focus", "True")
        } else {
            if (this.type == "IP" && StrLen(val) >= 3 && idx < this.count) {
                this.ui.Update(this.id "_Octet_" (idx + 1), "Focus", "True")
            } else if (this.type == "MAC" && StrLen(val) >= 2 && idx < this.count) {
                this.ui.Update(this.id "_Octet_" (idx + 1), "Focus", "True")
            }
        }
    }
}

XAMLElement.Prototype.DefineProp("RadialGauge", { Call: _RadialGauge })
XAMLElement.Prototype.DefineProp("Gauge", { Call: _RadialGauge })
_RadialGauge(this, id, title, value, maxVal, units := "%") {
    card := this.Add("Border").Use("CardPanel").Padding("15")
    sp := card.Add("StackPanel")
    sp.Add("TextBlock").Text(title).Foreground("{DynamicResource TextSub}").FontSize(11).FontWeight("Bold").HorizontalAlignment("Center").Margin("0,0,0,10")

    gaugeGrid := sp.Add("Grid").Width(100).Height(50)

    bgArc := gaugeGrid.Add("Path").Data("M 4,50 A 46,46 0 0,1 96,50").Stroke("{DynamicResource ControlBorder}").StrokeThickness(8).HorizontalAlignment("Center")

    ; We draw the fill arc from Left (4) to Right (96)
    ; StrokeDashOffset shifts the dash pattern, revealing the solid part from the start (Left)
    fillArc := gaugeGrid.Add("Path").Name(id "_Arc").Data("M 4,50 A 46,46 0 0,1 96,50").Stroke("{DynamicResource Accent}").StrokeThickness(8).HorizontalAlignment("Center")

    ; Total length is 144.51 pixels. At thickness 8, dash length is 18.06 units.
    fillArc.StrokeDashArray("18.06 18.06")

    pct := value / maxVal
    offset := 18.06 * (1 - pct)
    fillArc.StrokeDashOffset(offset)

    valSp := gaugeGrid.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Bottom").Margin("0,0,0,-10")
    valSp.Add("TextBlock").Name(id "_Text").Text(value).Foreground("{DynamicResource TextMain}").FontSize(20).FontWeight("Bold").VerticalAlignment("Bottom")
    valSp.Add("TextBlock").Text(units).Foreground("{DynamicResource TextSub}").FontSize(12).VerticalAlignment("Bottom").Margin("2,0,0,3")

    return card
}


XAMLElement.Prototype.DefineProp("SkeletonBlock", { Call: _SkeletonBlock })
_SkeletonBlock(this, w, h, radius := 4) {
    bdr := this.Add("Border").Height(h).CornerRadius(radius).Background("{DynamicResource ControlBorder}")

    if (w == "100%") {
        bdr.HorizontalAlignment("Stretch")
    } else if (w != "") {
        bdr.Width(w)
    }

    trigger := bdr.Add("Border.Triggers").Add("EventTrigger").RoutedEvent("FrameworkElement.Loaded")
    sb := trigger.Add("BeginStoryboard").Add("Storyboard")
    sb.Add("DoubleAnimation").Storyboard_TargetProperty("Opacity").From(0.3).To(0.8).Duration("0:0:1.5").AutoReverse("True").RepeatBehavior("Forever")

    return bdr
}

XAMLElement.Prototype.DefineProp("Avatar", { Call: _Avatar })
_Avatar(this, imagePath, initials, statusColor := "") {
    grid := this.Add("Grid").Width(40).Height(40).HorizontalAlignment("Left")

    circleBg := grid.Add("Ellipse").Fill("{DynamicResource ControlBgHover}").Width(40).Height(40)

    grid.Add("TextBlock").Text(initials).Foreground("{DynamicResource TextSub}").FontWeight("Bold").FontSize(14).HorizontalAlignment("Center").VerticalAlignment("Center")

    if (imagePath != "") {
        grid.Add("Border").CornerRadius(20).ClipToBounds("True").Add("Image").Source(imagePath).Stretch("UniformToFill")
    }

    if (statusColor != "") {
        statusBdr := grid.Add("Border").Width(12).Height(12).CornerRadius(6).Background(statusColor).BorderBrush("{DynamicResource ControlBg}").BorderThickness(2).HorizontalAlignment("Right").VerticalAlignment("Bottom")
    }

    return grid
}

XAMLElement.Prototype.DefineProp("AddBadge", { Call: _AddBadge })
_AddBadge(this, text, bgColor := "#FF453A") {
    target := this

    if (this._Props.Has("Content")) {
        originalContent := this._Props["Content"]
        this._Props.Delete("Content")

        target := this.Add("Grid")
        target.Add("TextBlock").Text(originalContent).HorizontalAlignment("Center").VerticalAlignment("Center")
    }

    bdr := target.Add("Border").Background(bgColor).CornerRadius(10).Padding("6,2").HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,-12,-12,0")
    bdr.Add("TextBlock").Text(text).Foreground("White").FontSize(10).FontWeight("Bold").HorizontalAlignment("Center").VerticalAlignment("Center")
    return bdr
}

XAMLElement.Prototype.DefineProp("AddContextMenu", { Call: _AddContextMenu })
_AddContextMenu(this, items) {
    cm := this.Add("FrameworkElement.ContextMenu").Add("ContextMenu").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).Foreground("{DynamicResource TextMain}")
    for item in items {
        if (item == "-") {
            cm.Add("Separator").Background("{DynamicResource ControlBorder}").Margin("0,4")
        } else {
            cm.Add("MenuItem").Header(item)
        }
    }
    return cm
}

XAMLElement.Prototype.DefineProp("Snackbar", { Call: _Snackbar })
_Snackbar(this, message, actionText := "") {
    bdr := this.Add("Border").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(6).Padding("15,10").HorizontalAlignment("Center").VerticalAlignment("Bottom").Margin("0,0,0,20")
    bdr.Add("Border.Effect").Add("DropShadowEffect").BlurRadius(15).ShadowDepth(4).Opacity(0.4)

    sp := bdr.Add("StackPanel").Orientation("Horizontal")
    sp.Add("TextBlock").Text(message).Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").FontSize(13)

    if (actionText != "") {
        sp.Add("Button").Content(actionText).Foreground("{DynamicResource Accent}").Background("Transparent").BorderThickness(0).Margin("15,0,0,0").FontWeight("Bold").VerticalAlignment("Center").Cursor("Hand")
    }
    return bdr
}

; ==============================================================================
; DataGridEx — comprehensive data grid with search, filter, sort, pagination
; ==============================================================================
class DataGridEx {
    __New(id, dataArray, opts := {}) {
        this.id := id
        this.data := dataArray
        this.columns := []
        this.columnWidths := Map()
        this.sortCol := opts.HasProp("SortCol") ? opts.SortCol : ""
        this.sortAsc := true
        this.page := 1
        this.pageSize := opts.HasProp("PageSize") ? opts.PageSize : 50
        this.searchQuery := ""
        this.showSearch := opts.HasProp("ShowSearch") ? opts.ShowSearch : true
        this.showFilters := opts.HasProp("ShowFilters") ? opts.ShowFilters : false
        this.showPagination := opts.HasProp("ShowPagination") ? opts.ShowPagination : true
        this.showReset := opts.HasProp("ShowReset") ? opts.ShowReset : true
        this.showRowCount := opts.HasProp("ShowRowCount") ? opts.ShowRowCount : true
        this.filterColumn := opts.HasProp("FilterColumn") ? opts.FilterColumn : ""
        this.filterValues := opts.HasProp("FilterValues") ? opts.FilterValues : []
        this.filterStates := Map()
        this.showDensity := opts.HasProp("ShowDensity") ? opts.ShowDensity : true
        this.density := "comfy"

        this.hiddenColumns := Map()
        if (opts.HasProp("HiddenColumns")) {
            for _, cName in opts.HiddenColumns
                this.hiddenColumns[cName] := true
        }

        this.ui := ""

        ; Auto-detect columns from first row
        if (dataArray.Length > 0) {
            for key, val in dataArray[1].OwnProps()
                this.columns.Push(key)
            if (this.sortCol == "")
                this.sortCol := this.columns[1]
        }

        ; Column widths: set defaults
        if (opts.HasProp("ColumnWidths")) {
            for col, w in opts.ColumnWidths.OwnProps()
                this.columnWidths[col] := w
        }

        ; Init filter states
        for fv in this.filterValues
            this.filterStates[fv] := true
    }

    ; Set column width (e.g. "150" for fixed, "2*" for star, "30%" for percentage)
    SetColumnWidth(colName, width) {
        this.columnWidths[colName] := width
        return this
    }

    ; Get WPF width string for a column
    _GetColWidth(colName, colIndex) {
        if (this.hiddenColumns.Has(colName) && this.hiddenColumns[colName])
            return "0"

        if (this.columnWidths.Has(colName)) {
            w := this.columnWidths[colName]
            ; Percentage: convert "30%" to "3*" (approx star ratio)
            if (InStr(w, "%")) {
                pct := StrReplace(w, "%", "")
                return pct / 10 "*"
            }
            return w
        }
        ; Default: last column fills remaining space
        return (colIndex == this.columns.Length) ? "*" : "Auto"
    }

    ; Build the XAML UI into a parent element
    Build(parent) {
        grid := parent.Add("Grid").Name(this.id "_MainGrid").Margin("0,0,0,0")
        rows := "Auto,*"
        if (this.showPagination)
            rows .= ",Auto"
        grid.Rows(StrSplit(rows, ",")*)

        ; --- Toolbar ---
        toolbar := grid.Add("Grid").Grid_Row(0).Margin("0,0,0,10")
        toolCols := ""
        colIdx := 0
        if (this.showSearch) {
            toolCols .= "*,"
        }
        if (this.showReset)
            toolCols .= "Auto,"
        if (this.showFilters)
            toolCols .= "Auto,"
        toolCols .= "Auto," ; Columns toggle
        if (this.showDensity)
            toolCols .= "Auto," ; Density toggle
        if (this.showRowCount)
            toolCols .= "Auto,"
        toolCols := RTrim(toolCols, ",")
        toolbar.Cols(StrSplit(toolCols, ",")*)

        tci := 0
        if (this.showSearch) {
            searchBdr := toolbar.Add("Border").Use("CardPanel").Padding("6,4").Grid_Column(tci).Margin("0,0,10,0").VerticalAlignment("Top")
            sg := searchBdr.Add("Grid")
            sg.Cols("Auto", "*")
            sg.Add("TextBlock").Text(Chr(0xE721)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14).Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("4,0,8,0").Grid_Column(0)
            sg.Add("TextBox").Name(this.id "_Search").Background("Transparent").BorderThickness("0").Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").Grid_Column(1).FontSize(13)
            tci++
        }
        if (this.showReset) {
            toolbar.Add("Button").Name(this.id "_BtnReset").Content("Reset").Grid_Column(tci).Width(70).Height(30).VerticalAlignment("Top").Margin("0,0,10,0").Use("IconBtn").Cursor("Hand")
            tci++
        }
        if (this.showFilters && this.filterValues.Length > 0) {
            filterBtn := toolbar.Add("ToggleButton").Content("Filters").Grid_Column(tci).Width(80).Height(30).VerticalAlignment("Top").Margin("0,0,10,0").Use("IconBtn").Cursor("Hand")
            pop := filterBtn.AddRichPopover()
            pop.Add("TextBlock").Text("Filter by " this.filterColumn).FontWeight("Bold").Foreground("{DynamicResource TextMain}").Margin("0,0,0,8")
            for fv in this.filterValues {
                pop.Add("CheckBox").Content(fv).Name(this.id "_Filter_" StrReplace(fv, " ", "")).IsChecked("True").Margin("0,0,0,5")
            }
            tci++
        }

        ; Columns toggle
        colBtn := toolbar.Add("ToggleButton").Content("Columns").Grid_Column(tci).Width(80).Height(30).VerticalAlignment("Top").Margin("0,0,10,0").Use("IconBtn").Cursor("Hand")
        colPop := colBtn.AddRichPopover()
        colPop.Add("TextBlock").Text("Visible Columns").FontWeight("Bold").Foreground("{DynamicResource TextMain}").Margin("0,0,0,8")
        for col in this.columns {
            isChecked := this.hiddenColumns.Has(col) && this.hiddenColumns[col] ? "False" : "True"
            colPop.Add("CheckBox").Content(col).Name(this.id "_ToggleCol_" StrReplace(col, " ", "")).IsChecked(isChecked).Margin("0,0,0,5")
        }
        tci++

        if (this.showDensity) {
            toolbar.Add("Button").Name(this.id "_BtnDensity").Content(this.density == "comfy" ? "Comfy" : "Compact").Grid_Column(tci).Width(80).Height(30).VerticalAlignment("Top").Margin("0,0,10,0").Use("IconBtn").Cursor("Hand")
            tci++
        }

        if (this.showRowCount) {
            initEnd := Min(this.pageSize, this.data.Length)
            initText := this.data.Length == 0 ? "0 rows" : this.data.Length " rows, showing (" initEnd ")"
            toolbar.Add("TextBlock").Name(this.id "_RowCount").Text(initText).Grid_Column(tci).VerticalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize(12).FontWeight("Normal")
        }
        ; --- Table ---
        tableBdr := grid.Add("Border").Grid_Row(1).Margin("0,0,15,0").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(6).Background("{DynamicResource ControlBg}").ClipToBounds("True")

        tableGrid := tableBdr.Add("Grid")
        tableGrid.Rows("30", "*")
        tableGrid.IsSharedSizeScope("True")

        ; Table Header
        headerGrid := tableGrid.Add("Grid").Name(this.id "_HeaderGrid").Grid_Row(0).Background("{DynamicResource ControlBgHover}")
        hColDefs := headerGrid.Add("Grid.ColumnDefinitions")
        for i, col in this.columns {
            w := this._GetColWidth(col, i)
            hColDefs.Add("ColumnDefinition").Name(this.id "_HeaderCol_" i).Width(w)
            if (i < this.columns.Length)
                hColDefs.Add("ColumnDefinition").Name(this.id "_HeaderSplit_" i).Width(w == "0" ? "0" : "Auto")
        }

        ; Dummy Grid to proxy explicit Widths into SharedSizeGroups (fixes GridSplitter bug)
        dummyGrid := tableGrid.Add("Grid").Height(0).IsHitTestVisible("False").Grid_Row(0)
        dColDefs := dummyGrid.Add("Grid.ColumnDefinitions")
        for i, col in this.columns {
            dColDefs.Add("ColumnDefinition").Width("{Binding ElementName=" this.id "_HeaderCol_" i ", Path=Width}").SharedSizeGroup("TableCol_" i)
            if (i < this.columns.Length)
                dColDefs.Add("ColumnDefinition").Width("{Binding ElementName=" this.id "_HeaderSplit_" i ", Path=Width}").SharedSizeGroup("TableSplit_" i)
        }

        for i, col in this.columns {
            colIdx := (i - 1) * 2
            headerGrid.Add("Button").Name(this.id "_Table_Header_" StrReplace(col, " ", "")).Content(col).Grid_Column(colIdx).Background("Transparent").Foreground("{DynamicResource TextSub}").BorderThickness("0").FontSize(11).FontWeight("Bold").HorizontalContentAlignment("Left").Padding("10,0").Cursor("Hand")
            if (i < this.columns.Length) {
                headerGrid.Add("Border").Grid_Column(colIdx + 1).Width(1).HorizontalAlignment("Center").Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
                headerGrid.Add("GridSplitter").Name(this.id "_Table_Splitter_" i).Grid_Column(colIdx + 1).Width(7).HorizontalAlignment("Center").VerticalAlignment("Stretch").Background("Transparent").Cursor("SizeWE").ResizeBehavior("PreviousAndNext")
            }
        }

        ; Table ListBox
        lb := tableGrid.Add("ListBox").Name(this.id "_Table_List").Grid_Row(1).Background("Transparent").BorderThickness("0").ScrollViewer_HorizontalScrollBarVisibility("Auto").VirtualizingPanel_IsVirtualizing("False").HorizontalContentAlignment("Stretch")
        lb.InjectResources('<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/></Style>')

        ; --- Pagination ---
        if (this.showPagination) {
            pagSp := grid.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Grid_Row(2).Margin("0,15,15,0")
            pagSp.Add("Button").Name(this.id "_BtnPrev").Content(Chr(0xE76B)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Width(30).Height(30).Use("IconBtn").Margin("0,0,10,0").Cursor("Hand")
            pagSp.Add("TextBlock").Name(this.id "_PageStatus").Text("Page 1").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize(13)
            pagSp.Add("Button").Name(this.id "_BtnNext").Content(Chr(0xE76C)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Width(30).Height(30).Use("IconBtn").Margin("10,0,0,0").Cursor("Hand")
        }

        return grid
    }

    ; Register events with the XAMLHost instance
    Bind(uiHost) {
        this.ui := uiHost

        ; Header sort buttons & splitters
        for i, col in this.columns {
            uiHost.OnEvent(this.id "_Table_Header_" StrReplace(col, " ", ""), "Click", ((c) => (state, ctrl, ev) => this.Sort(state, c))(col))
            if (i < this.columns.Length) {
                uiHost.Track(this.id "_Table_Splitter_" i)
                uiHost.OnEvent(this.id "_Table_Splitter_" i, "MouseDoubleClick", (state, ctrl, ev) => this.OnSplitterDoubleClick(state, ctrl))
            }
        }

        ; Search
        if (this.showSearch) {
            uiHost.Track(this.id "_Search")
            uiHost.OnEvent(this.id "_Search", "TextChanged", (state, ctrl, ev) => this.OnSearch(state))
        }

        ; Reset
        if (this.showReset)
            uiHost.OnEvent(this.id "_BtnReset", "Click", (state, ctrl, ev) => this.Reset(state))

        ; Filters
        if (this.showFilters) {
            for fv in this.filterValues {
                fvName := fv
                trackName := this.id "_Filter_" StrReplace(fv, " ", "")
                uiHost.Track(trackName)
                uiHost.OnEvent(trackName, "Click", (state, ctrl, ev) => this.OnFilter(state))
            }
        }

        ; Column Toggles
        for col in this.columns {
            trackName := this.id "_ToggleCol_" StrReplace(col, " ", "")
            uiHost.Track(trackName)
            uiHost.OnEvent(trackName, "Click", (state, ctrl, ev) => this.OnColumnToggle(state))
        }

        ; Density Toggle
        if (this.showDensity) {
            uiHost.OnEvent(this.id "_BtnDensity", "Click", (state, ctrl, ev) => this.ToggleDensity(state))
        }

        ; Pagination
        if (this.showPagination) {
            uiHost.OnEvent(this.id "_BtnPrev", "Click", (state, ctrl, ev) => this.ChangePage(state, -1))
            uiHost.OnEvent(this.id "_BtnNext", "Click", (state, ctrl, ev) => this.ChangePage(state, 1))
        }

        ; Initial Render on Load
        uiHost.Track(this.id "_MainGrid")
        uiHost.OnEvent(this.id "_MainGrid", "Loaded", (state, ctrl, ev) => this.Render(state))
    }

    Sort(state, col) {
        if (this.sortCol == col)
            this.sortAsc := !this.sortAsc
        else {
            this.sortCol := col
            this.sortAsc := true
        }
        this.page := 1
        this.Render(state)
    }

    ToggleDensity(state) {
        this.density := (this.density == "comfy") ? "compact" : "comfy"
        this.ui.Update(this.id "_BtnDensity", "Content", this.density == "comfy" ? "Comfy" : "Compact")
        this.Render(state)
    }

    ChangePage(state, delta) {
        this.page += delta
        if (this.page < 1)
            this.page := 1
        this.Render(state)
    }

    OnSearch(state) {
        searchKey := this.id "_Search"
        this.searchQuery := state.Has(searchKey) ? state[searchKey] : ""
        this.page := 1
        this.Render(state)
    }

    OnFilter(state) {
        ; Read filter checkbox states
        for fv in this.filterValues {
            key := this.id "_Filter_" StrReplace(fv, " ", "")
            this.filterStates[fv] := !state.Has(key) || (state[key] ~= "i)true|1")
        }
        this.page := 1
        this.Render(state)
    }

    OnColumnToggle(state) {
        for i, col in this.columns {
            key := this.id "_ToggleCol_" StrReplace(col, " ", "")
            isVisible := state.Has(key) ? (state[key] ~= "i)true|1") : true

            wasHidden := this.hiddenColumns.Has(col) ? this.hiddenColumns[col] : false
            isHidden := !isVisible

            if (wasHidden == isHidden)
                continue

            this.hiddenColumns[col] := isHidden

            if (isHidden) {
                this.ui.Update(this.id "_HeaderCol_" i, "Width", "0")
                if (i < this.columns.Length)
                    this.ui.Update(this.id "_HeaderSplit_" i, "Width", "0")
            } else {
                w := this._GetColWidth(col, i)
                this.ui.Update(this.id "_HeaderCol_" i, "Width", w)
                if (i < this.columns.Length)
                    this.ui.Update(this.id "_HeaderSplit_" i, "Width", "Auto")
            }
        }
        this.Render(state)
    }

    OnSplitterDoubleClick(state, ctrlName) {
        colIndex := RegExReplace(ctrlName, ".*_(\d+)$", "$1")
        colName := this.columns[colIndex]

        ; Find the longest text string in the column to approximate pixel width
        maxLen := StrLen(colName)
        for row in this.data {
            if (row.HasProp(colName)) {
                val := String(row.%colName%)
                if (StrLen(val) > maxLen)
                    maxLen := StrLen(val)
            }
        }

        ; Approximate pixel width: ~7.5px per char (Segoe UI 12) + 30px padding
        newWidth := Round(maxLen * 7.5 + 30)

        this.ui.Update(this.id "_HeaderCol_" colIndex, "Width", String(newWidth))
        if (colIndex < this.columns.Length)
            this.ui.Update(this.id "_HeaderSplit_" colIndex, "Width", "Auto")

        this.columnWidths[colName] := String(newWidth)
    }

    Reset(state) {
        this.page := 1
        this.sortCol := this.columns.Length > 0 ? this.columns[1] : ""
        this.sortAsc := true
        this.searchQuery := ""
        for fv in this.filterValues
            this.filterStates[fv] := true
        if (this.showSearch)
            this.ui.Update(this.id "_Search", "Text", "")
        this.Render(state)
    }

    Render(state) {
        ; --- 1. Sort ---
        if (this.sortCol != "" && this.data.Length > 1) {
            sc := this.sortCol
            sa := this.sortAsc
            loop this.data.Length {
                i := A_Index
                loop this.data.Length - i {
                    j := A_Index
                    v1 := this.data[j].%sc%
                    v2 := this.data[j + 1].%sc%

                    isNum := IsNumber(v1) && IsNumber(v2)
                    if (isNum)
                        swap := sa ? (v1 > v2) : (v1 < v2)
                    else
                        swap := sa ? (StrCompare(v1, v2) > 0) : (StrCompare(v1, v2) < 0)

                    if (swap) {
                        tmp := this.data[j]
                        this.data[j] := this.data[j + 1]
                        this.data[j + 1] := tmp
                    }
                }
            }
        }

        ; --- 2. Filter ---
        filtered := []
        for rowObj in this.data {
            ; Column filter
            if (this.filterColumn != "" && rowObj.HasProp(this.filterColumn)) {
                fVal := rowObj.%this.filterColumn%
                if (this.filterStates.Has(fVal) && !this.filterStates[fVal])
                    continue
            }
            ; Search filter
            if (this.searchQuery != "") {
                found := false
                for col in this.columns {
                    if (rowObj.HasProp(col) && InStr(rowObj.%col%, this.searchQuery))
                        found := true
                }
                if (!found)
                    continue
            }
            filtered.Push(rowObj)
        }

        ; --- 3. Pagination ---
        total := filtered.Length
        totalPages := (total > 0) ? Ceil(total / this.pageSize) : 1
        if (this.page > totalPages)
            this.page := totalPages
        if (this.page < 1)
            this.page := 1

        startIdx := (this.page - 1) * this.pageSize + 1
        endIdx := Min(startIdx + this.pageSize - 1, total)

        if (this.showPagination)
            this.ui.Update(this.id "_PageStatus", "Text", "Page " this.page " of " totalPages)

        if (this.showRowCount) {
            if (total == 0)
                this.ui.Update(this.id "_RowCount", "Text", "0 rows")
            else
                this.ui.Update(this.id "_RowCount", "Text", total " rows, showing (" (endIdx - startIdx + 1) ")")
        }

        ; --- 4. Clear & guard ---
        this.ui.Update(this.id "_Table_List", "ClearItems", "")
        if (total == 0)
            return

        startIdx := (this.page - 1) * this.pageSize + 1
        endIdx := Min(startIdx + this.pageSize - 1, total)
        count := endIdx - startIdx + 1
        if (count <= 0)
            return

        ; --- 5. Inject rows ---
        loop count {
            idx := startIdx + A_Index - 1
            rowObj := filtered[idx]

            rowGrid := XAML_Generator()
            rowGrid.Background(Mod(A_Index, 2) == 0 ? "{DynamicResource ControlBg}" : "Transparent")
            rowGrid.MinWidth("{Binding ElementName=" this.id "_HeaderGrid, Path=ActualWidth}")
            rColDefs := rowGrid.Add("Grid.ColumnDefinitions")

            for i, col in this.columns {
                w := this._GetColWidth(col, i)
                ; Use Width="0" so the row content does not stretch the SharedSizeGroup
                rColDefs.Add("ColumnDefinition").Width("0").SharedSizeGroup("TableCol_" i)

                if (i < this.columns.Length)
                    rColDefs.Add("ColumnDefinition").Width(w == "0" ? "0" : "Auto").SharedSizeGroup("TableSplit_" i)
            }

            isCompact := (this.density == "compact")
            fSize := isCompact ? 11 : 12
            marginText := isCompact ? "10,4" : "10,12"

            for i, col in this.columns {
                val := rowObj.HasProp(col) ? rowObj.%col% : ""
                colIdx := (i - 1) * 2
                rowGrid.Add("TextBlock").Text(val).Grid_Column(colIdx).Foreground("{DynamicResource TextMain}").FontSize(fSize).VerticalAlignment("Center").Margin(marginText).TextTrimming("CharacterEllipsis").ToolTip(val)
            }

            rowStr := rowGrid.Compile()
            rowStr := RegExReplace(rowStr, "<!--.*?-->", "")
            rowStr := StrReplace(rowStr, "<Grid ", '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" ')
            this.ui.Update(this.id "_Table_List", "AddXamlItem", rowStr)
        }
    }
}

; ==============================================================================
; Rating — configurable star/icon rating selector
; ==============================================================================
XAMLElement.Prototype.DefineProp("Rating", { Call: _Rating })
_Rating(this, id, opts := {}) {
    maxVal := opts.HasProp("Max") ? opts.Max : 5
    defaultVal := opts.HasProp("Default") ? opts.Default : 0
    icon := opts.HasProp("Icon") ? opts.Icon : Chr(0xE735)  ; Segoe Fluent star
    iconEmpty := opts.HasProp("IconEmpty") ? opts.IconEmpty : Chr(0xE734)  ; Segoe Fluent empty star
    iconSize := opts.HasProp("Size") ? opts.Size : 22
    allowHalf := opts.HasProp("AllowHalf") ? opts.AllowHalf : false
    iconFont := opts.HasProp("IconFont") ? opts.IconFont : "Segoe Fluent Icons, Segoe MDL2 Assets"
    color := opts.HasProp("Color") ? opts.Color : "#FFD700"
    emptyColor := opts.HasProp("EmptyColor") ? opts.EmptyColor : "{DynamicResource TextSub}"

    grid := this.Add("Grid").Margin("0,0,0,5")
    grid.Cols("Auto", "Auto")

    sp := grid.Add("StackPanel").Orientation("Horizontal").Grid_Column(0)

    if (allowHalf) {
        ; Half-star mode: each position has two halved buttons
        steps := maxVal * 2
        loop maxVal {
            idx := A_Index
            ; Container for one star position
            starGrid := sp.Add("Grid").Width(iconSize).Height(iconSize).Margin("1,0")

            ; Left half button (covers left 50%)
            leftVal := idx - 0.5
            leftBtn := starGrid.Add("Button").Name(id "_Half_" (idx * 2 - 1)).Width(iconSize / 2).HorizontalAlignment("Left").Background("Transparent").BorderThickness("0").Cursor("Hand").Padding("0").Tag(leftVal)
            leftBtn.Add("TextBlock").Text(leftVal <= defaultVal ? icon : iconEmpty).FontFamily(iconFont).FontSize(iconSize).Foreground(leftVal <= defaultVal ? color : emptyColor).Margin("-" iconSize / 4 ",0,0,0")

            ; Right half button (covers right 50%)
            rightVal := idx
            rightBtn := starGrid.Add("Button").Name(id "_Half_" (idx * 2)).Width(iconSize / 2).HorizontalAlignment("Right").Background("Transparent").BorderThickness("0").Cursor("Hand").Padding("0").Tag(rightVal)
            rightBtn.Add("TextBlock").Text(rightVal <= defaultVal ? icon : iconEmpty).FontFamily(iconFont).FontSize(iconSize).Foreground(rightVal <= defaultVal ? color : emptyColor).Margin("0,0,-" iconSize / 4 ",0")
        }
    } else {
        ; Whole-star mode: simple toggle buttons
        loop maxVal {
            idx := A_Index
            isFilled := idx <= defaultVal
            btn := sp.Add("Button").Name(id "_Star_" idx).Background("Transparent").BorderThickness("0").Cursor("Hand").Padding("2,0").Margin("1,0").Tag(idx)
            btn.Add("TextBlock").Text(isFilled ? icon : iconEmpty).FontFamily(iconFont).FontSize(iconSize).Foreground(isFilled ? color : emptyColor).Name(id "_StarIcon_" idx)
        }
    }

    ; Value display
    grid.Add("TextBlock").Name(id "_Value").Text(defaultVal "/" maxVal).Foreground("{DynamicResource TextSub}").FontSize(12).VerticalAlignment("Center").Margin("10,0,0,0").Grid_Column(1)

    ; Store metadata on the grid
    grid.DefineProp("RatingId", { Get: (*) => id })
    grid.DefineProp("RatingMax", { Get: (*) => maxVal })
    grid.DefineProp("RatingIcon", { Get: (*) => icon })
    grid.DefineProp("RatingIconEmpty", { Get: (*) => iconEmpty })
    grid.DefineProp("AllowHalf", { Get: (*) => allowHalf })
    grid.DefineProp("RatingColor", { Get: (*) => color })
    grid.DefineProp("RatingEmptyColor", { Get: (*) => emptyColor })

    return grid
}

; Helper to bind rating events to a UI host
RatingBind(uiHost, id, maxVal, allowHalf, icon, iconEmpty, color, emptyColor) {
    if (allowHalf) {
        loop maxVal * 2 {
            _BindRatingHalf(uiHost, id, maxVal, A_Index, icon, iconEmpty, color, emptyColor)
        }
    } else {
        loop maxVal {
            _BindRatingStar(uiHost, id, maxVal, A_Index, icon, iconEmpty, color, emptyColor)
        }
    }
}

; Factory: creates a new scope so `idx` is captured by value
_BindRatingStar(uiHost, id, maxVal, idx, icon, iconEmpty, color, emptyColor) {
    uiHost.OnEvent(id "_Star_" idx, "Click", (state, ctrl, ev) => _RatingSet(uiHost, id, maxVal, idx, icon, iconEmpty, color, emptyColor))
}
_BindRatingHalf(uiHost, id, maxVal, idx, icon, iconEmpty, color, emptyColor) {
    uiHost.OnEvent(id "_Half_" idx, "Click", (state, ctrl, ev) => _RatingSetHalf(uiHost, id, maxVal, idx, icon, iconEmpty, color, emptyColor))
}

_RatingSet(uiHost, id, maxVal, clickedIdx, icon, iconEmpty, color, emptyColor) {
    ; Read current rating from the displayed text
    currentText := ""
    try {
        ; We'll use a simple state approach — check what's displayed
        ; If clicking same star as current rating, toggle half-step
    }

    ; Get current rating by counting filled stars (check icon text)
    ; Since we can't easily read WPF state from AHK, store in a global
    static ratings := Map()
    if (!ratings.Has(id))
        ratings[id] := 0

    currentRating := ratings[id]

    if (clickedIdx == currentRating) {
        ; Same star clicked — toggle to half-step above (x.5)
        newRating := currentRating + 0.5
        if (newRating > maxVal)
            newRating := clickedIdx  ; Cap at max, stay at current
    } else if (clickedIdx == Ceil(currentRating) && currentRating != Floor(currentRating)) {
        ; Clicking the star that's currently half-filled — go to full
        newRating := clickedIdx
    } else {
        newRating := clickedIdx
    }

    ratings[id] := newRating
    filledFull := Floor(newRating)
    hasHalf := (newRating != filledFull)

    loop maxVal {
        if (A_Index <= filledFull) {
            uiHost.Update(id "_StarIcon_" A_Index, "Text", icon)
            uiHost.Update(id "_StarIcon_" A_Index, "Foreground", color)
        } else if (A_Index == filledFull + 1 && hasHalf) {
            ; Half-filled star — use filled icon with reduced opacity
            uiHost.Update(id "_StarIcon_" A_Index, "Text", icon)
            uiHost.Update(id "_StarIcon_" A_Index, "Foreground", color)
            uiHost.Update(id "_StarIcon_" A_Index, "Opacity", "0.4")
        } else {
            uiHost.Update(id "_StarIcon_" A_Index, "Text", iconEmpty)
            uiHost.Update(id "_StarIcon_" A_Index, "Foreground", emptyColor)
            uiHost.Update(id "_StarIcon_" A_Index, "Opacity", "1")
        }
    }
    ; Also reset opacity on fully filled stars (in case they were previously half)
    loop filledFull {
        uiHost.Update(id "_StarIcon_" A_Index, "Opacity", "1")
    }

    ; Display value — show decimal only if half
    displayVal := hasHalf ? (newRating) : (Integer(newRating))
    uiHost.Update(id "_Value", "Text", displayVal "/" maxVal)
}

_RatingSetHalf(uiHost, id, maxVal, clickedHalf, icon, iconEmpty, color, emptyColor) {
    ; clickedHalf is 1-based: 1=0.5, 2=1.0, 3=1.5, etc.
    rating := clickedHalf / 2
    uiHost.Update(id "_Value", "Text", rating "/" maxVal)
}

; ==============================================================================
; EmojiPicker — popover grid of clickable emoji
; ==============================================================================
XAMLElement.Prototype.DefineProp("EmojiPicker", { Call: _EmojiPicker })
_EmojiPicker(this, id, opts := {}) {
    btnText := opts.HasProp("ButtonText") ? opts.ButtonText : Chr(0x1F600)
    targetName := opts.HasProp("Target") ? opts.Target : ""

    ; Emoji categories
    smileys := ["😀", "😁", "😂", "🤣", "😃", "😄", "😅", "😆", "😉", "😊", "😋", "😎", "😍", "🥰", "😘", "😗", "😙", "🤗", "🤩", "🤔", "🤨", "😐", "😑", "😶", "🙄", "😏", "😣", "😥", "😮", "🤐", "😯", "😪", "😫", "🥱", "😴", "😌"]
    gestures := ["👍", "👎", "👏", "🙌", "🤝", "👋", "✌️", "🤞", "🤟", "🤘", "👌", "🤌", "👈", "👉", "👆", "👇", "☝️", "✋"]
    hearts := ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟"]
    objects := ["🔥", "⭐", "🌟", "✨", "💫", "🎉", "🎊", "🏆", "🥇", "🎯", "💡", "📌", "📎", "🔑", "🔒", "💬", "💭", "🗨️"]

    allEmoji := []
    for e in smileys
        allEmoji.Push(e)
    for e in gestures
        allEmoji.Push(e)
    for e in hearts
        allEmoji.Push(e)
    for e in objects
        allEmoji.Push(e)

    ; Toggle button to open the picker
    btn := this.Add("ToggleButton").Name(id "_Btn").Width(45).Height(35).Use("IconBtn").Cursor("Hand").Padding("6")
    btn.Add("Image").Name(id "_BtnImg").Source(_GetTwemojiUrl(btnText)).Width(24).Height(24).Stretch("Uniform")

    pop := btn.AddRichPopover()

    ; Category header
    tabSp := pop.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,8")
    tabSp.Add("TextBlock").Text("Smileys & Gestures & Hearts & Objects").Foreground("{DynamicResource TextSub}").FontSize(10).FontWeight("Bold")

    ; Emoji grid — use Segoe UI Emoji font for color rendering
    wrap := pop.Add("ScrollViewer").Name(id "_EmojiScroll").Height(200).VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").Tag("ContainScroll")
    emojiGrid := wrap.Add("WrapPanel").Width(280)

    for i, emoji in allEmoji {
        url := _GetTwemojiUrl(emoji)

        btn := emojiGrid.Add("Button").Name(id "_E_" i).Width(35).Height(35).Background("Transparent").BorderThickness("0").Cursor("Hand").Padding("6").Margin("1").ToolTip(emoji)
        btn.Add("Image").Source(url).Stretch("Uniform")
    }

    ; Selected display
    selBdr := pop.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,1,0,0").Margin("0,8,0,0").Padding("0,8,0,0")
    selSp := selBdr.Add("StackPanel").Orientation("Horizontal")
    selSp.Add("TextBlock").Text("Selected: ").Foreground("{DynamicResource TextSub}").FontSize(12).VerticalAlignment("Center").Margin("0,0,5,0")
    selSp.Add("Image").Name(id "_SelectedImg").Width(20).Height(20).VerticalAlignment("Center").Visibility("Collapsed")
    selSp.Add("TextBlock").Name(id "_Selected").Text("None").Foreground("{DynamicResource TextMain}").FontSize(16).FontFamily("Segoe UI Emoji").VerticalAlignment("Center").Margin("5,0,0,0")

    ; Store metadata
    btn.DefineProp("EmojiId", { Get: (*) => id })
    btn.DefineProp("EmojiCount", { Get: (*) => allEmoji.Length })
    btn.DefineProp("EmojiList", { Get: (*) => allEmoji })

    return btn
}

; Helper to bind emoji picker events
EmojiPickerBind(uiHost, id, emojiList, targetName := "") {
    for i, emoji in emojiList {
        _BindEmojiBtn(uiHost, id, i, emoji, targetName)
    }
}

; Factory: creates a new scope so `emoji` and `i` are captured by value
_BindEmojiBtn(uiHost, id, i, emoji, targetName) {
    uiHost.OnEvent(id "_E_" i, "Click", (state, ctrl, ev) => _EmojiSelect(uiHost, id, emoji, targetName))
}

_EmojiSelect(uiHost, id, emoji, targetName) {
    uiHost.Update(id "_Selected", "Text", emoji)

    url := _GetTwemojiUrl(emoji)

    uiHost.Update(id "_SelectedImg", "Source", url)
    uiHost.Update(id "_SelectedImg", "Visibility", "Visible")

    ; Update main toggle button image
    uiHost.Update(id "_BtnImg", "Source", url)

    if (targetName != "")
        uiHost.Update(targetName, "Text", emoji)
}

_GetTwemojiUrl(emoji) {
    hex := ""
    pos := 1
    len := StrLen(emoji)
    while (pos <= len) {
        c := Ord(SubStr(emoji, pos, 2))
        if (c == 0xFE0F) {
            pos++
            continue
        }
        if (c > 0xFFFF)
            pos += 2
        else
            pos += 1
        hex .= Format("{:x}", c) "-"
    }
    return "https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/72x72/" RTrim(hex, "-") ".png"
}