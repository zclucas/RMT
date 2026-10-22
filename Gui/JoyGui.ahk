#Requires AutoHotkey v2.0

; =====================================================================
; 手柄指令编辑器 —— 可视化手柄，点击按键/摇杆/扳机生成
; 指令格式：
;   手柄_A_点击_100[_次数[_间隔]]
;   手柄_A+B_按下
;   手柄_上_按下
;   手柄_LX:80[_LY:20]
;   手柄_LT:50
; =====================================================================

class JoyGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._loading := false
        this._closing := false
        this.TriggerAction := (*) => this.TriggerMacro()

        this.SelectColor := "{DynamicResource ActionBg}"
        this.CheckedArr := []          ; 数字按键短名：A、上、LB…
        this.AxisMap := Map()          ; 轴短名 → 数值  LX/LY/RX/RY/LT/RT
        this.Mode := "digital"         ; digital | analog
        this.CommandStr := ""
        this._btnDefBg := Map()        ; 控件名 → 默认背景
        this._btnDefBd := Map()        ; 控件名 → 默认边框
        this._btnKeyMap := Map()       ; 控件名 → 短名或 AxisLS 等
        this._padBtnLayout := Map()
        this._axisGroup := ""          ; AxisLS / AxisRS / AxisLT / AxisRT
        this._stickLayout := Map()
        this._stickDrag := ""
        this._stickDragMoved := false
        this._trigClick := ""
        this._pendingPadClick := ""
        this._ignoreClick := false
        this._dragOffX := 0
        this._dragOffY := 0
        this._dragStartX := 0
        this._dragStartY := 0
        this._stickTick := ObjBindMethod(this, "OnStickDragTick")
        this._joyListenPrev := Map()
        this._selBorder := "{DynamicResource ActionStroke}"
        this._syncing := false
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _UiAlive() {
        return !(this.HasProp("_closed") && this._closed) && IsObject(this.ui)
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._loading := true
        this._closing := false
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(cmd)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this))) {
            this._closed := true
            this._loading := false
            return
        }
        this.ToggleFunc(true)
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        this._analogVis := "Hidden"
        this._btnDefBg := Map()
        this._btnDefBd := Map()
        this._btnKeyMap := Map()
        this._padBtnLayout := Map()
        this._stickLayout := Map()
        this._stickDrag := ""
        this._trigClick := ""
        this._pendingPadClick := ""
        try SetTimer(this._stickTick, 0)
        title := this.ParentTile GetLang("手柄编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("14")
        body.Rows("*", "Auto", "48")

        padCard := body.Add("Border").Grid_Row(0).CornerRadius("10").Padding("12")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        vb := padCard.Add("Viewbox").Stretch("Uniform").Margin("0,-20,0,20")
        padHost := vb.Add("Grid").Width("640").Height("340")
        this._pad := padHost.Add("Canvas").Name("JoyPadCanvas").Width("640").Height("340").Background("Transparent")
        this._BuildPad()

        paramCard := body.Add("Border").Grid_Row(1).CornerRadius("8").Padding("12").Margin("0,14,0,0")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        param := paramCard.Add("StackPanel")

        digitalRow := param.Add("StackPanel").Name("DigitalRow").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").MinHeight("26")
        typeBox := digitalRow.Add("StackPanel").Name("TypeBox").Orientation("Horizontal").VerticalAlignment("Center").ToolTip(this._TypeHelpText())
        typeBox.Add("TextBlock").Text(GetLang("类型:")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        kt := typeBox.Add("ComboBox").Name("KeyTypeCon").Width(80).Height(26).MinHeight(26).Margin("4,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11").Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        for t in GetLangArr(["按下", "松开", "点击"])
            kt.Add("ComboBoxItem").Content(t)
        digitalRow.Add("TextBlock").Name("HoldTimeTipCon").Text(GetLang("点击时长:")).VerticalAlignment("Center").Margin("14,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddNumBox(digitalRow, "HoldTimeCon", "60", "100")
        digitalRow.Add("TextBlock").Name("KeyCountTipCon").Text(GetLang("点击次数：")).VerticalAlignment("Center").Margin("14,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddNumBox(digitalRow, "KeyCountCon", "60", "1")
        digitalRow.Add("TextBlock").Name("PerIntervalTipCon").Text(GetLang("每次间隔：")).VerticalAlignment("Center").Margin("14,0,0,0").Foreground("{DynamicResource TextMain}").FontSize("12").Visibility("Collapsed")
        this._AddNumBox(digitalRow, "PerIntervalCon", "60", "200", "Collapsed")

        analogRow := param.Add("StackPanel").Name("AnalogRow").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0,8,0,0").MinHeight("26").Height("26").Visibility("Hidden")
        analogRow.Add("TextBlock").Name("AxisTip1").Text("LX").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12").Width("28")
        analogRow.Add("Slider").Name("AxisSlider1").Width("180").Height("26").Minimum("-100").Maximum("100").Value("100").IsMoveToPointEnabled("True").VerticalAlignment("Center")
        analogRow.Add("TextBox").Name("AxisVal1").Width("48").Height(26).MinHeight(26).Margin("6,0,16,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        analogRow.Add("TextBlock").Name("AxisTip2").Text("LY").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12").Width("28")
        analogRow.Add("Slider").Name("AxisSlider2").Width("180").Height("26").Minimum("-100").Maximum("100").Value("0").IsMoveToPointEnabled("True").VerticalAlignment("Center")
        analogRow.Add("TextBox").Name("AxisVal2").Width("48").Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        param.Add("StackPanel").Name("CommandStrCon").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,8,0,0")
            .VerticalAlignment("Center").MinHeight("22").Height("22")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        clearBtn := btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(88).Height(32).MinHeight(32).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
            .Margin("0,0,150,0")
        clearBtn.InjectResources(FrontInfoGui._OkBtnHoverStyle())
        AddCmdOkBtn(btnRow, "BtnOk")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="720" Height="590" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this._RegisterPadEvents()
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/28-手柄", ObjBindMethod(this, "TriggerMacro"), "!l")
        this.ui.OnEvent("JoyPadCanvas", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnPadMouseDown"))
        this.ui.OnEvent("JoyPadCanvas", "PreviewMouseMove", ObjBindMethod(this, "OnPadMouseMove"))
        this.ui.OnEvent("JoyPadCanvas", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnPadMouseUp"))
        this.ui.OnEvent("KeyTypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("HoldTimeCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("KeyCountCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("PerIntervalCon", "TextChanged", ObjBindMethod(this, "OnChangeEditValue"))
        this.ui.OnEvent("AxisSlider1", "ValueChanged", ObjBindMethod(this, "OnAxisSlider", 1))
        this.ui.OnEvent("AxisSlider2", "ValueChanged", ObjBindMethod(this, "OnAxisSlider", 2))
        this.ui.OnEvent("AxisVal1", "TextChanged", ObjBindMethod(this, "OnAxisText", 1))
        this.ui.OnEvent("AxisVal2", "TextChanged", ObjBindMethod(this, "OnAxisText", 2))
        this.ui.OnEvent("AxisVal1", "LostFocus", ObjBindMethod(this, "OnAxisTextCommit", 1))
        this.ui.OnEvent("AxisVal2", "LostFocus", ObjBindMethod(this, "OnAxisTextCommit", 2))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearAll())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
    }

    _AddNumBox(parent, name, width, text := "", vis := "") {
        tb := parent.Add("TextBox").Name(name).Width(width).Height(26).MinHeight(26).Margin("6,0,0,0")
            .VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11").Padding("4,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (text != "")
            tb.Text(text)
        if (vis != "")
            tb.Visibility(vis)
    }

    _FluentFont() {
        return "Segoe Fluent Icons, Segoe MDL2 Assets"
    }

    _Mdl2Font() {
        return "Segoe MDL2 Assets, Segoe Fluent Icons"
    }

    _CommandFont() {
        global MainSoftData
        base := (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "Microsoft YaHei UI"
        return base ", Segoe Fluent Icons, Segoe MDL2 Assets"
    }

    _PadBtnStyle(radius) {
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="' radius '" SnapsToDevicePixels="True" UseLayoutRounding="False"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.88"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _IconBtnStyle() {
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid ClipToBounds="False" SnapsToDevicePixels="True" UseLayoutRounding="False"><Ellipse x:Name="bd" Margin="1.5" Fill="{TemplateBinding Background}" Stroke="{TemplateBinding BorderBrush}" StrokeThickness="1.5" SnapsToDevicePixels="True"/><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.88"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    _PlacePadBtn(id, label, x, y, w, h, bg, fg := "{DynamicResource TextMain}", radius := 6, bd := "{DynamicResource ControlBorder}", fontSize := 11, fontFamily := "", tip := "", glyphMargin := "", rotate := 0) {
        name := "Pad_" id
        btn := this._pad.Add("Button").Name(name).Width(String(w)).Height(String(h))
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .SetProp("Panel.ZIndex", "10")
            .FontSize(fontSize).FontWeight("SemiBold").Cursor("Hand").Padding("0")
            .Background(bg).Foreground(fg).BorderBrush(bd).BorderThickness("1.5")
            .SetProp("SnapsToDevicePixels", "True").SetProp("UseLayoutRounding", "False")
        if (glyphMargin != "" || rotate != 0) {
            tb := btn.Add("TextBlock").Text(label).FontSize(fontSize).FontWeight("SemiBold")
                .HorizontalAlignment("Center").VerticalAlignment("Center")
                .Margin(glyphMargin == "" ? "0" : glyphMargin).Padding("0").IsHitTestVisible("False")
                .SetProp("LineStackingStrategy", "BlockLineHeight").LineHeight(String(fontSize))
            if (fontFamily != "")
                tb.FontFamily(fontFamily)
            if (rotate != 0) {
                tb.SetProp("RenderTransformOrigin", "0.5,0.5")
                tb.Add("TextBlock.LayoutTransform").Add("RotateTransform").Angle(String(rotate))
            }
        } else {
            btn.Content(label)
            if (fontFamily != "")
                btn.FontFamily(fontFamily)
        }
        if (tip != "")
            btn.ToolTip(tip)
        btn.InjectResources(this._PadBtnStyle(radius))
        this._btnKeyMap.Set(name, id)
        this._btnDefBg.Set(name, bg)
        this._btnDefBd.Set(name, bd)
        this._padBtnLayout[id] := { x: x, y: y, w: w, h: h }
    }

    _PlaceIconBtn(id, glyph, tip, x, y, size, fontSize := 15, ring := true) {
        name := "Pad_" id
        bg := ring ? "{DynamicResource ControlBg}" : "#00FFFFFF"
        bd := ring ? "{DynamicResource ControlBorder}" : "#00FFFFFF"
        btn := this._pad.Add("Button").Name(name).Width(String(size)).Height(String(size))
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .SetProp("Panel.ZIndex", "10")
            .Cursor("Hand").Padding("0")
            .Background(bg).Foreground("{DynamicResource TextMain}").BorderBrush(bd).BorderThickness("1.5")
            .ToolTip(tip)
            .SetProp("SnapsToDevicePixels", "True").SetProp("UseLayoutRounding", "False")
        btn.Add("TextBlock").Text(glyph).FontFamily(this._FluentFont()).FontSize(fontSize).FontWeight("SemiBold")
            .Foreground("{DynamicResource TextMain}").HorizontalAlignment("Center").VerticalAlignment("Center")
            .Margin("0.5,-1,0,1").IsHitTestVisible("False")
        btn.InjectResources(this._IconBtnStyle())
        this._btnKeyMap.Set(name, id)
        this._btnDefBg.Set(name, bg)
        this._btnDefBd.Set(name, bd)
        this._padBtnLayout[id] := { x: x, y: y, w: size, h: size }
    }

    _PlacePs5Triangle(x, y, size, bg, fg, bd) {
        name := "Pad_Y"
        btn := this._pad.Add("Button").Name(name).Width(String(size)).Height(String(size))
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .SetProp("Panel.ZIndex", "10")
            .Cursor("Hand").Padding("0")
            .Background(bg).Foreground(fg).BorderBrush(bd).BorderThickness("1.5")
            .SetProp("SnapsToDevicePixels", "True").SetProp("UseLayoutRounding", "False")
        side := 14
        h := 12
        btn.Add("Path").Name("Pad_YGlyph").Data("M " (side / 2) ",0.6 L " (side - 0.5) "," (h - 0.4) " L 0.5," (h - 0.4) " Z")
            .Fill("#00FFFFFF").Stroke(fg).StrokeThickness("1").SetProp("StrokeLineJoin", "Miter")
            .Stretch("Uniform").Width(String(side)).Height(String(h))
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .Margin("0,-1,0,1").IsHitTestVisible("False")
            .SetProp("SnapsToDevicePixels", "True")
        btn.InjectResources(this._PadBtnStyle(size / 2))
        this._btnKeyMap.Set(name, "Y")
        this._btnDefBg.Set(name, bg)
        this._btnDefBd.Set(name, bd)
        this._padBtnLayout["Y"] := { x: x, y: y, w: size, h: size }
    }

    _PlacePs5Cross(x, y, size, bg, fg, bd) {
        name := "Pad_A"
        btn := this._pad.Add("Button").Name(name).Width(String(size)).Height(String(size))
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .SetProp("Panel.ZIndex", "10")
            .Cursor("Hand").Padding("0")
            .Background(bg).Foreground(fg).BorderBrush(bd).BorderThickness("1.5")
            .SetProp("SnapsToDevicePixels", "True").SetProp("UseLayoutRounding", "False")
        g := 10
        host := btn.Add("Grid").HorizontalAlignment("Stretch").VerticalAlignment("Stretch")
            .IsHitTestVisible("False")
        host.Add("Path").Name("Pad_AGlyph").Data("M 1,1 L " (g - 1) "," (g - 1))
            .Fill("#00FFFFFF").Stroke(fg).StrokeThickness("1.2")
            .SetProp("StrokeStartLineCap", "Round").SetProp("StrokeEndLineCap", "Round")
            .Stretch("Fill").Width(String(g)).Height(String(g))
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .SetProp("SnapsToDevicePixels", "True")
        host.Add("Path").Name("Pad_AGlyph2").Data("M " (g - 1) ",1 L 1," (g - 1))
            .Fill("#00FFFFFF").Stroke(fg).StrokeThickness("1.2")
            .SetProp("StrokeStartLineCap", "Round").SetProp("StrokeEndLineCap", "Round")
            .Stretch("Fill").Width(String(g)).Height(String(g))
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .SetProp("SnapsToDevicePixels", "True")
        btn.InjectResources(this._PadBtnStyle(size / 2))
        this._btnKeyMap.Set(name, "A")
        this._btnDefBg.Set(name, bg)
        this._btnDefBd.Set(name, bd)
        this._padBtnLayout["A"] := { x: x, y: y, w: size, h: size }
    }

    _PlaceRectIconBtn(id, glyph, tip, x, y, w := 38, h := 22, fontSize := 12, fontFamily := "") {
        if (fontFamily == "")
            fontFamily := this._FluentFont()
        this._PlacePadBtn(id, glyph, x, y, w, h, "{DynamicResource ControlBg}", "{DynamicResource TextMain}", 4, "{DynamicResource ControlBorder}", fontSize, fontFamily, tip)
    }

    _PlaceStick(id, x, y, size, knob) {
        pad := 4
        hostSize := size + pad * 2
        wellR := Integer((size - knob) / 2)
        maxR := wellR + 5
        host := this._pad.Add("Grid").Width(String(hostSize)).Height(String(hostSize)).Cursor("SizeAll")
            .SetProp("Canvas.Left", String(x - pad)).SetProp("Canvas.Top", String(y - pad))
            .SetProp("Panel.ZIndex", "8").ClipToBounds("False")
            .SetProp("SnapsToDevicePixels", "True").SetProp("UseLayoutRounding", "False")
        host.Add("Ellipse").Width(String(size)).Height(String(size))
            .Fill("{DynamicResource DropdownBg}").Stroke("{DynamicResource ControlBorder}").StrokeThickness("2")
            .HorizontalAlignment("Center").VerticalAlignment("Center").IsHitTestVisible("False")
            .SetProp("SnapsToDevicePixels", "True")
        host.Add("Ellipse").Name("Pad_" id "Bg").Width(String(size - 6)).Height(String(size - 6))
            .Fill("{DynamicResource InputBg}").Stroke("{DynamicResource ControlBorder}").StrokeThickness("1.5")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .SetProp("SnapsToDevicePixels", "True")
        knobBox := host.Add("Grid").Name("Pad_" id "Knob").Width(String(knob)).Height(String(knob))
            .HorizontalAlignment("Left").VerticalAlignment("Top").Margin((pad + wellR) "," (pad + wellR) ",0,0")
        knobBox.Add("Ellipse").Name("Pad_" id "KnobFill").Width(String(knob)).Height(String(knob))
            .Fill("{DynamicResource ControlBg}").Stroke("{DynamicResource ControlBorder}").StrokeThickness("1.5")
            .SetProp("SnapsToDevicePixels", "True")
        tag := (id == "AxisLS") ? "L" : "R"
        knobBox.Add("TextBlock").Name("Pad_" id "Tag").Text(tag).FontSize("12").FontWeight("Bold")
            .Foreground("{DynamicResource TextMain}")
            .HorizontalAlignment("Center").VerticalAlignment("Center").IsHitTestVisible("False")
        this._stickLayout[id] := { kind: "stick", x: x, y: y, size: size, knob: knob, maxR: maxR, wellR: wellR, pad: pad }
        this._btnKeyMap.Set("Pad_" id, id)
        this._btnDefBg.Set("Pad_" id "Bg", "{DynamicResource InputBg}")
        this._btnDefBg.Set("Pad_" id "KnobFill", "{DynamicResource ControlBg}")
    }

    _PlaceTrigger(id, label, x, y, w, h) {
        r := Integer(w / 2)
        innerW := w - 3
        innerH := h - 3
        innerR := Max(r - 2, 1)
        host := this._pad.Add("Grid").Width(String(w)).Height(String(h)).Cursor("Hand")
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .ToolTip(GetLang("单击为满行程，轴值在下方修改"))
        pill := host.Add("Border").Name("Pad_" id "Bg").Width(String(w)).Height(String(h))
            .CornerRadius(String(r)).Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1.5")
        inner := pill.Add("Grid")
        clip := inner.Add("Border").Name("Pad_" id "FillClip").HorizontalAlignment("Stretch").VerticalAlignment("Bottom")
            .Height("0").Visibility("Collapsed").ClipToBounds("True").BorderThickness("0").Background("#00FFFFFF")
        clip.Add("Border").Width(String(innerW)).Height(String(innerH)).VerticalAlignment("Bottom").HorizontalAlignment("Center")
            .CornerRadius(String(innerR)).Background("{DynamicResource Accent}").IsHitTestVisible("False")
        inner.Add("TextBlock").Name("Pad_" id "Label").Text(label).FontSize("10").FontWeight("SemiBold")
            .Foreground("{DynamicResource TextMain}").HorizontalAlignment("Center").VerticalAlignment("Center")
            .IsHitTestVisible("False")
        this._stickLayout[id] := { kind: "trig", x: x, y: y, w: w, h: h, innerH: innerH, label: label }
        this._btnKeyMap.Set("Pad_" id, id)
        this._btnDefBg.Set("Pad_" id "Bg", "{DynamicResource ControlBg}")
    }

    _PlaceDpad(cx, cy) {
        ff := this._FluentFont()
        size := 68, th := 24, well := 82
        bg := "{DynamicResource DropdownBg}"
        fg := "{DynamicResource TextMain}"
        bd := "{DynamicResource ControlBorder}"
        this._pad.Add("Ellipse").Width(String(well)).Height(String(well))
            .Fill("{DynamicResource ControlBg}").Stroke(bd).StrokeThickness("1.5")
            .SetProp("Canvas.Left", String(cx - well / 2)).SetProp("Canvas.Top", String(cy - well / 2))
            .IsHitTestVisible("False")
        this._pad.Add("Border").Width(String(th)).Height(String(size)).CornerRadius(String(Integer(th / 2)))
            .Background(bg).BorderBrush(bd).BorderThickness("1.5")
            .SetProp("Canvas.Left", String(cx - th / 2)).SetProp("Canvas.Top", String(cy - size / 2)).IsHitTestVisible("False")
        this._pad.Add("Border").Width(String(size)).Height(String(th)).CornerRadius(String(Integer(th / 2)))
            .Background(bg).BorderBrush(bd).BorderThickness("1.5")
            .SetProp("Canvas.Left", String(cx - size / 2)).SetProp("Canvas.Top", String(cy - th / 2)).IsHitTestVisible("False")
        arm := 22
        this._PlacePadBtn("DpadUp", Chr(0xE70E), cx - 11, cy - size / 2 + 2, 22, arm, bg, fg, 8, "#00FFFFFF", 11, ff, GetLang("上"))
        this._PlacePadBtn("DpadDown", Chr(0xE70D), cx - 11, cy + size / 2 - arm - 2, 22, arm, bg, fg, 8, "#00FFFFFF", 11, ff, GetLang("下"))
        this._PlacePadBtn("DpadLeft", Chr(0xE76B), cx - size / 2 + 2, cy - 11, arm, 22, bg, fg, 8, "#00FFFFFF", 11, ff, GetLang("左"))
        this._PlacePadBtn("DpadRight", Chr(0xE76C), cx + size / 2 - arm - 2, cy - 11, arm, 22, bg, fg, 8, "#00FFFFFF", 11, ff, GetLang("右"))
        this._PlacePadBtn("DpadNone", "", cx - 9, cy - 9, 18, 18, "{DynamicResource ControlBg}", fg, 9, bd, 10, "", GetLang("无方向"))
        this._btnKeyMap["Pad_DpadUp"] := "上"
        this._btnKeyMap["Pad_DpadDown"] := "下"
        this._btnKeyMap["Pad_DpadLeft"] := "左"
        this._btnKeyMap["Pad_DpadRight"] := "右"
        this._btnKeyMap["Pad_DpadNone"] := "无方向"
    }

    _PlaceAbxy(cx, cy) {
        global MySoftData, MainSoftData
        well := 92, btn := 28, d := 24
        wellC := "{DynamicResource ControlBg}"
        fg := "{DynamicResource TextMain}"
        bd := "{DynamicResource ControlBorder}"
        this._pad.Add("Ellipse").Width(String(well)).Height(String(well)).Fill(wellC).Stroke(bd).StrokeThickness("1.5")
            .SetProp("Canvas.Left", String(cx - well / 2)).SetProp("Canvas.Top", String(cy - well / 2))
            .IsHitTestVisible("False")
        half := btn / 2
        isPs5 := (IsSet(MainSoftData) && MainSoftData.TriggerJoyType == "PS5")
        if (isPs5) {
            ff := this._FluentFont()
            this._PlacePs5Triangle(cx - half, cy - d - half, btn, wellC, fg, bd)
            this._PlacePadBtn("X", Chr(0xE739), cx - d - half, cy - half, btn, btn, wellC, fg, half, bd, 14, ff)
            this._PlacePadBtn("B", Chr(0xECCA), cx + d - half, cy - half, btn, btn, wellC, fg, half, bd, 14, ff, "", "0,1,0,0")
            this._PlacePs5Cross(cx - half, cy + d - half, btn, wellC, fg, bd)
        } else {
            this._PlacePadBtn("Y", MySoftData.GetJoyDisplayName("JoyY"), cx - half, cy - d - half, btn, btn, wellC, fg, half, bd, 12)
            this._PlacePadBtn("X", MySoftData.GetJoyDisplayName("JoyX"), cx - d - half, cy - half, btn, btn, wellC, fg, half, bd, 12)
            this._PlacePadBtn("B", MySoftData.GetJoyDisplayName("JoyB"), cx + d - half, cy - half, btn, btn, wellC, fg, half, bd, 12)
            this._PlacePadBtn("A", MySoftData.GetJoyDisplayName("JoyA"), cx - half, cy + d - half, btn, btn, wellC, fg, half, bd, 12)
        }
    }

    _BuildPad() {
        global MySoftData, MainSoftData
        shell := "{DynamicResource DropdownBg}"
        well := "{DynamicResource ControlBg}"
        bd := "{DynamicResource ControlBorder}"
        fg := "{DynamicResource TextMain}"

        bodyData := "M 186,92 L 454,92 C 510,92 540,200 548,270 C 556,340 528,417 442,292 L 198,292 C 112,417 84,340 92,270 C 100,200 130,92 186,92 Z"
        this._pad.Add("Path").Data(bodyData).Fill(shell).Stroke(bd).StrokeThickness("1.6")
            .SetProp("StrokeLineJoin", "Round").SetProp("Panel.ZIndex", "0").IsHitTestVisible("False")
        this._pad.Add("Path").Data("M 528,188 L 448,276").Stroke(bd).StrokeThickness("1.4")
            .Fill("#00FFFFFF").SetProp("StrokeStartLineCap", "Round").SetProp("StrokeEndLineCap", "Round")
            .SetProp("Panel.ZIndex", "1").IsHitTestVisible("False")
        this._pad.Add("Path").Data("M 112,188 L 192,276").Stroke(bd).StrokeThickness("1.4")
            .Fill("#00FFFFFF").SetProp("StrokeStartLineCap", "Round").SetProp("StrokeEndLineCap", "Round")
            .SetProp("Panel.ZIndex", "1").IsHitTestVisible("False")

        this._PlaceLtRt(190, 14, 32, 42)
        this._PlacePadBtn("LB", MySoftData.GetJoyDisplayName("JoyLB"), 178, 58, 56, 13, well, fg, 7, bd, 10)
        this._PlacePadBtn("RB", MySoftData.GetJoyDisplayName("JoyRB"), 406, 58, 56, 13, well, fg, 7, bd, 10)

        topY := 142
        lowY := 238
        stick := 76
        isPs5 := (IsSet(MainSoftData) && MainSoftData.TriggerJoyType == "PS5")
        if (isPs5) {
            this._PlaceDpad(198, topY)
            this._PlaceAbxy(442, topY)
        } else {
            this._PlaceStick("AxisLS", 198 - stick / 2, topY - stick / 2, stick, 42)
            this._PlaceAbxy(442, topY)
        }

        this._PlaceIconBtn("Home", Chr(0xE80F), MySoftData.GetJoyDisplayName("JoyHome"), 306, 126, 28, 13, true)
        this._PlaceRectIconBtn("Back", Chr(0x2B8C), MySoftData.GetJoyDisplayName("JoyBack"), 255, 170, 38, 22, 12, "Segoe UI Symbol, Segoe UI")
        this._PlaceRectIconBtn("Pad", Chr(0xE74A), MySoftData.GetJoyDisplayName("JoyPad"), 301, 170)
        this._PlaceRectIconBtn("Start", Chr(0xE700), MySoftData.GetJoyDisplayName("JoyStart"), 347, 170)

        if (isPs5) {
            this._PlaceStick("AxisLS", 238 - stick / 2, lowY - stick / 2, stick, 42)
            this._PlaceStick("AxisRS", 402 - stick / 2, lowY - stick / 2, stick, 42)
        } else {
            this._PlaceDpad(238, lowY)
            this._PlaceStick("AxisRS", 402 - stick / 2, lowY - stick / 2, stick, 42)
        }
    }

    _LtRtAsButton() {
        if (!IsSet(MainSoftData) || !IsObject(MainSoftData) || !MainSoftData.HasProp("JoyLtRtAsButton"))
            return true
        return !!MainSoftData.JoyLtRtAsButton
    }

    _PlaceLtRt(x, y, w, h) {
        global MySoftData
        if (this._LtRtAsButton()) {
            well := "{DynamicResource ControlBg}"
            fg := "{DynamicResource TextMain}"
            bd := "{DynamicResource ControlBorder}"
            this._PlacePadBtn("LT", MySoftData.GetJoyDisplayName("JoyLT"), x, y, w, h, well, fg, Integer(w / 2), bd, 10)
            this._PlacePadBtn("RT", MySoftData.GetJoyDisplayName("JoyRT"), 418, y, w, h, well, fg, Integer(w / 2), bd, 10)
            return
        }
        this._PlaceTrigger("AxisLT", MySoftData.GetJoyDisplayName("JoyLT"), x, y, w, h)
        this._PlaceTrigger("AxisRT", MySoftData.GetJoyDisplayName("JoyRT"), 418, y, w, h)
    }

    _RegisterPadEvents() {
        for name, id in this._btnKeyMap {
            if (this._IsAnalogId(id))
                continue
            clickId := id
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnPadClick").Bind(clickId))
        }
    }

    _HitPadButton(px, py) {
        if (px < 0 || !IsObject(this._padBtnLayout))
            return ""
        for id, r in this._padBtnLayout {
            if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h)
                return id
        }
        return ""
    }

    _EventXY(state) {
        raw := ""
        if (IsObject(state)) {
            if (state.Has("JoyPadCanvas"))
                raw := state["JoyPadCanvas"]
            else if (state.Has("PreviewMouseLeftButtonDown"))
                raw := state["PreviewMouseLeftButtonDown"]
            else if (state.Has("PreviewMouseMove"))
                raw := state["PreviewMouseMove"]
            else if (state.Has("PreviewMouseLeftButtonUp"))
                raw := state["PreviewMouseLeftButtonUp"]
        }
        if (!InStr(raw, ","))
            return { x: -1, y: -1 }
        parts := StrSplit(raw, ",")
        return { x: Integer(parts[1]), y: Integer(parts[2]) }
    }

    _HitAnalog(px, py) {
        if (px < 0)
            return ""
        for id, layout in this._stickLayout {
            if (layout.kind == "stick") {
                cx := layout.x + layout.size / 2
                cy := layout.y + layout.size / 2
                dx := px - cx, dy := py - cy
                hitR := layout.size / 2 + 5
                if (dx * dx + dy * dy <= hitR * hitR)
                    return id
            }
        }
        return ""
    }

    _HitTrigger(px, py) {
        if (px < 0)
            return ""
        for id, layout in this._stickLayout {
            if (layout.kind == "trig") {
                if (px >= layout.x && px <= layout.x + layout.w && py >= layout.y && py <= layout.y + layout.h)
                    return id
            }
        }
        return ""
    }

    _LayoutClickId(layoutId) {
        name := "Pad_" layoutId
        if (this._btnKeyMap.Has(name))
            return this._btnKeyMap[name]
        return layoutId
    }

    OnPadMouseDown(state, *) {
        xy := this._EventXY(state)
        padId := this._HitPadButton(xy.x, xy.y)
        if (padId != "") {
            this._pendingPadClick := ""
            this._ignoreClick := false
            this.OnPadClick(this._LayoutClickId(padId))
            this._ignoreClick := true
            SetTimer(() => this._ignoreClick := false, -180)
            return
        }
        this._pendingPadClick := ""
        id := this._HitAnalog(xy.x, xy.y)
        if (id == "") {
            this._trigClick := this._HitTrigger(xy.x, xy.y)
            return
        }
        this._trigClick := ""
        this._stickDrag := id
        this._stickDragMoved := false
        CoordMode("Mouse", "Client")
        MouseGetPos(&mx, &my)
        this._dragOffX := mx - xy.x
        this._dragOffY := my - xy.y
        this._dragStartX := xy.x
        this._dragStartY := xy.y
        try SetTimer(this._stickTick, 0)
        try SetTimer(this._stickTick, 16)
    }

    OnPadMouseMove(state, *) {
        if (this._stickDrag == "")
            return
        this._stickDragMoved := true
        this.OnStickDragTick()
    }

    OnStickDragTick(*) {
        if (this._stickDrag == "" || !IsObject(this.ui))
            return
        if (!GetKeyState("LButton", "P")) {
            this.OnPadMouseUp()
            return
        }
        CoordMode("Mouse", "Client")
        MouseGetPos(&mx, &my)
        cx := mx - this._dragOffX
        cy := my - this._dragOffY
        if (!this._stickDragMoved) {
            dx := cx - this._dragStartX
            dy := cy - this._dragStartY
            if (dx * dx + dy * dy < 25)
                return
            this._stickDragMoved := true
        }
        this._ApplyAnalogFromPoint(this._stickDrag, cx, cy)
    }

    OnPadMouseUp(*) {
        if (this._trigClick != "") {
            id := this._trigClick
            this._trigClick := ""
            this.OnPadClick(id)
            return
        }
        if (this._stickDrag == "")
            return
        id := this._stickDrag
        moved := this._stickDragMoved
        this._stickDrag := ""
        try SetTimer(this._stickTick, 0)
        if (!moved) {
            if (id == "AxisLS")
                this.OnPadClick(this._AnalogSelected("AxisLS") ? "AxisLS" : "LS")
            else if (id == "AxisRS")
                this.OnPadClick(this._AnalogSelected("AxisRS") ? "AxisRS" : "RS")
            return
        }
        this._ignoreClick := true
        SetTimer(() => this._ignoreClick := false, -80)
        this._RefreshPadHighlight()
        this.Refresh()
    }

    _ApplyAnalogFromPoint(id, px, py) {
        if (!this._stickLayout.Has(id))
            return
        layout := this._stickLayout[id]
        if (layout.kind == "stick") {
            this._axisGroup := id
            cx := layout.x + layout.size / 2
            cy := layout.y + layout.size / 2
            maxR := layout.HasProp("maxR") ? layout.maxR : (layout.size / 2 - layout.knob / 2)
            if (maxR < 1)
                maxR := 1
            nx := (px - cx) / maxR
            ny := (py - cy) / maxR
            pair := this._ClampStickVector(Round(nx * 100), Round(-ny * 100))
            a1 := (id == "AxisLS") ? "LX" : "RX"
            a2 := (id == "AxisLS") ? "LY" : "RY"
            this.AxisMap[a1] := pair.x
            this.AxisMap[a2] := pair.y
        }
        this._SyncAnalogRowVis()
        this._SyncAxisControls()
        this._UpdateAnalogVisuals()
        this._RefreshPadHighlight()
        this.UpdateCommandStr()
    }

    _SyncAnalogRowVis() {
        if (!this._UiAlive())
            return
        hasAxis := this.AxisMap.Count > 0
        dual := this._axisGroup == "AxisLS" || this._axisGroup == "AxisRS"
        want := hasAxis ? "Visible" : "Hidden"
        if (!(this.HasProp("_analogVis") && this._analogVis == want)) {
            this.ui.Update("AnalogRow", "Visibility", want)
            this._analogVis := want
        }
        vis2 := dual ? "Visible" : "Hidden"
        this.ui.Update("AxisTip2", "Visibility", vis2)
        this.ui.Update("AxisSlider2", "Visibility", vis2)
        this.ui.Update("AxisVal2", "Visibility", vis2)
    }

    _CenterStickKnob(id, nx, ny) {
        if (!IsObject(this.ui) || !this._stickLayout.Has(id))
            return
        layout := this._stickLayout[id]
        maxR := layout.HasProp("maxR") ? layout.maxR : ((layout.size - layout.knob) / 2)
        pad := layout.HasProp("pad") ? layout.pad : 0
        wellR := layout.HasProp("wellR") ? layout.wellR : Integer((layout.size - layout.knob) / 2)
        kx := pad + wellR + nx * maxR
        ky := pad + wellR + ny * maxR
        this.ui.Update("Pad_" id "Knob", "Margin", Round(kx) "," Round(ky) ",0,0")
    }

    _UpdateAnalogVisuals() {
        if (!IsObject(this.ui))
            return
        logUi := this.HasProp("_joyLogUi") && this._joyLogUi
        if (logUi)
            this._JoyLog("_UpdateAnalogVisuals begin")
        for id, layout in this._stickLayout {
            if (layout.kind == "stick") {
                a1 := (id == "AxisLS") ? "LX" : "RX"
                a2 := (id == "AxisLS") ? "LY" : "RY"
                vx := 0, vy := 0
                if (this.AxisMap.Has(a1) || this.AxisMap.Has(a2)) {
                    vx := this.AxisMap.Get(a1, 0) / 100.0
                    vy := -this.AxisMap.Get(a2, 0) / 100.0
                }
                this._CenterStickKnob(id, vx, vy)
            } else {
                name := (id == "AxisLT") ? "LT" : "RT"
                v := this.AxisMap.Has(name) ? this.AxisMap.Get(name, 0) : 0
                innerH := layout.HasProp("innerH") ? layout.innerH : (layout.h - 3)
                fillH := (v <= 0) ? 0 : Integer(Round(innerH * v / 100.0))
                if (fillH > innerH)
                    fillH := innerH
                clipName := "Pad_" id "FillClip"
                if (fillH <= 0) {
                    this.ui.Update(clipName, "Height", "0")
                    this.ui.Update(clipName, "Visibility", "Collapsed")
                } else {
                    this.ui.Update(clipName, "Visibility", "Visible")
                    this.ui.Update(clipName, "Height", String(fillH))
                }
                this.ui.Update("Pad_" id "Label", "Text", layout.label)
            }
        }
        if (logUi)
            this._JoyLog("_UpdateAnalogVisuals end")
    }

    _IsAnalogId(id) {
        if (id == "AxisLS" || id == "AxisRS")
            return true
        if ((id == "AxisLT" || id == "AxisRT") && !this._LtRtAsButton())
            return true
        return false
    }

    _AnalogSelected(id) {
        if (id == "AxisLS")
            return this.AxisMap.Has("LX") || this.AxisMap.Has("LY")
        if (id == "AxisRS")
            return this.AxisMap.Has("RX") || this.AxisMap.Has("RY")
        if (id == "AxisLT")
            return this.AxisMap.Has("LT")
        if (id == "AxisRT")
            return this.AxisMap.Has("RT")
        return false
    }

    _ClearAnalogGroup(id) {
        if (id == "AxisLS") {
            if (this.AxisMap.Has("LX"))
                this.AxisMap.Delete("LX")
            if (this.AxisMap.Has("LY"))
                this.AxisMap.Delete("LY")
        } else if (id == "AxisRS") {
            if (this.AxisMap.Has("RX"))
                this.AxisMap.Delete("RX")
            if (this.AxisMap.Has("RY"))
                this.AxisMap.Delete("RY")
        } else if (id == "AxisLT" && this.AxisMap.Has("LT"))
            this.AxisMap.Delete("LT")
        else if (id == "AxisRT" && this.AxisMap.Has("RT"))
            this.AxisMap.Delete("RT")
        if (this._axisGroup == id)
            this._axisGroup := ""
        if (this.AxisMap.Has("LX") || this.AxisMap.Has("LY"))
            this._axisGroup := "AxisLS"
        else if (this.AxisMap.Has("RX") || this.AxisMap.Has("RY"))
            this._axisGroup := "AxisRS"
        else if (this.AxisMap.Has("LT"))
            this._axisGroup := "AxisLT"
        else if (this.AxisMap.Has("RT"))
            this._axisGroup := "AxisRT"
        if (!IsObject(this._joyStickOff))
            this._joyStickOff := Map()
        this._joyStickOff[id] := true
    }

    _DpadSet() {
        return Map("上", true, "下", true, "左", true, "右", true, "无方向", true)
    }

    OnPadClick(id, *) {
        this._JoyLog("OnPadClick " id " ignore=" this._ignoreClick " live=" (this.HasProp("_joyLiveClick") && this._joyLiveClick))
        if (!this._UiAlive())
            return
        if (this._ignoreClick && !(this.HasProp("_joyLiveClick") && this._joyLiveClick))
            return
        if (!(this.HasProp("_joyLiveClick") && this._joyLiveClick)) {
            this._ignoreClick := true
            SetTimer(() => this._ignoreClick := false, -200)
        }
        if (this._IsAnalogId(id)) {
            if (this._AnalogSelected(id)) {
                this._JoyLog("OnPadClick analog off " id)
                this._ClearAnalogGroup(id)
                this._SyncAnalogRowVis()
                this._UpdateAnalogVisuals()
                this._RefreshPadHighlight()
                this.Refresh()
                this._JoyLog("OnPadClick analog off done " id)
                return
            }
            if (IsObject(this._joyStickOff) && this._joyStickOff.Has(id))
                this._joyStickOff.Delete(id)
            this._axisGroup := id
            if (id == "AxisLS") {
                this.AxisMap["LX"] := 100
                this.AxisMap["LY"] := 0
            } else if (id == "AxisRS") {
                this.AxisMap["RX"] := 100
                this.AxisMap["RY"] := 0
            } else if (id == "AxisLT")
                this.AxisMap["LT"] := 100
            else if (id == "AxisRT")
                this.AxisMap["RT"] := 100
            this._JoyLog("OnPadClick analog " id)
            this._SyncAxisControls()
            this._RefreshPadHighlight()
            this.Refresh()
            this._JoyLog("OnPadClick analog done " id)
            return
        }

        found := 0
        for i, v in this.CheckedArr {
            if (v == id) {
                found := i
                break
            }
        }
        dpad := this._DpadSet()
        if (found) {
            this.CheckedArr.RemoveAt(found)
            if (!IsObject(this._joyUserOff))
                this._joyUserOff := Map()
            this._joyUserOff[id] := true
        } else {
            if (IsObject(this._joyUserOff) && this._joyUserOff.Has(id))
                this._joyUserOff.Delete(id)
            if (dpad.Has(id)) {
                i := this.CheckedArr.Length
                while (i >= 1) {
                    if (dpad.Has(this.CheckedArr[i]))
                        this.CheckedArr.RemoveAt(i)
                    i--
                }
            }
            this.CheckedArr.Push(id)
        }
        this._JoyLog("OnPadClick digital " id " found=" found)
        this._RefreshPadHighlight()
        this.Refresh()
        this._JoyLog("OnPadClick digital done " id)
    }

    _RefreshPadHighlight() {
        if (!this._UiAlive())
            return
        logUi := this.HasProp("_joyLogUi") && this._joyLogUi
        if (logUi)
            this._JoyLog("_RefreshPadHighlight begin")
        selected := Map()
        for v in this.CheckedArr
            selected[v] := true
        if (this.AxisMap.Has("LX") || this.AxisMap.Has("LY"))
            selected["AxisLS"] := true
        if (this.AxisMap.Has("RX") || this.AxisMap.Has("RY"))
            selected["AxisRS"] := true
        if (this.AxisMap.Has("LT"))
            selected["AxisLT"] := true
        if (this.AxisMap.Has("RT"))
            selected["AxisRT"] := true
        for name, id in this._btnKeyMap {
            on := selected.Has(id)
            if (id == "AxisLS")
                on := on || selected.Has("LS")
            else if (id == "AxisRS")
                on := on || selected.Has("RS")
            else if (id == "AxisLT")
                on := on || selected.Has("LT")
            else if (id == "AxisRT")
                on := on || selected.Has("RT")
            try {
                if (id == "AxisLS" || id == "AxisRS") {
                    knobName := "Pad_" id "KnobFill"
                    tagName := "Pad_" id "Tag"
                    this.ui.Update(knobName, "Fill", on ? this.SelectColor : "{DynamicResource ControlBg}")
                    this.ui.Update(knobName, "Stroke", on ? this._selBorder : "{DynamicResource ControlBorder}")
                    this.ui.Update(tagName, "Foreground", on ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
                } else if (id == "AxisLT" || id == "AxisRT") {
                    bgName := "Pad_" id "Bg"
                    this.ui.Update(bgName, "BorderBrush", on ? this._selBorder : "{DynamicResource ControlBorder}")
                } else {
                    defBg := this._btnDefBg.Get(name, "{DynamicResource ControlBg}")
                    defBd := this._btnDefBd.Get(name, "{DynamicResource ControlBorder}")
                    this.ui.Update(name, "Background", on ? this.SelectColor : defBg)
                    this.ui.Update(name, "Foreground", on ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
                    this.ui.Update(name, "BorderBrush", on ? this._selBorder : defBd)
                    this.ui.Update(name, "BorderThickness", "1.5")
                    if (id == "Y")
                        this.ui.Update("Pad_YGlyph", "Stroke", on ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
                    if (id == "A") {
                        this.ui.Update("Pad_AGlyph", "Stroke", on ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
                        this.ui.Update("Pad_AGlyph2", "Stroke", on ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
                    }
                }
            } catch as e {
                this._JoyLog("HL FAIL " name " id=" id " " e.Message " L" e.Line)
            }
        }
        if (logUi)
            this._JoyLog("_RefreshPadHighlight end")
    }

    _SyncAxisControls() {
        if (!this._UiAlive() || this.AxisMap.Count == 0 || this._axisGroup == "")
            return
        this._JoyLog("_SyncAxisControls " this._axisGroup)
        this._syncing := true
        if (this._axisGroup == "AxisLS" || this._axisGroup == "AxisRS") {
            a1 := (this._axisGroup == "AxisLS") ? "LX" : "RX"
            a2 := (this._axisGroup == "AxisLS") ? "LY" : "RY"
            this.ui.Update("AxisTip1", "Text", a1)
            this.ui.Update("AxisTip2", "Text", a2)
            this.ui.Update("AxisSlider1", "Minimum", "-100")
            this.ui.Update("AxisSlider1", "Maximum", "100")
            this.ui.Update("AxisSlider2", "Minimum", "-100")
            this.ui.Update("AxisSlider2", "Maximum", "100")
            v1 := this.AxisMap.Get(a1, 100)
            v2 := this.AxisMap.Get(a2, 0)
            this.ui.Update("AxisSlider1", "Value", String(v1))
            this.ui.Update("AxisSlider2", "Value", String(v2))
            this.ui.Update("AxisVal1", "Text", String(v1))
            this.ui.Update("AxisVal2", "Text", String(v2))
        } else {
            a1 := (this._axisGroup == "AxisLT") ? "LT" : "RT"
            this.ui.Update("AxisTip1", "Text", a1)
            this.ui.Update("AxisSlider1", "Minimum", "0")
            this.ui.Update("AxisSlider1", "Maximum", "100")
            v1 := this.AxisMap.Get(a1, 100)
            this.ui.Update("AxisSlider1", "Value", String(v1))
            this.ui.Update("AxisVal1", "Text", String(v1))
        }
        this._syncing := false
        this._UpdateAnalogVisuals()
        this._JoyLog("_SyncAxisControls done")
    }

    _AxisNames() {
        if (this._axisGroup == "AxisLS")
            return ["LX", "LY"]
        if (this._axisGroup == "AxisRS")
            return ["RX", "RY"]
        if (this._axisGroup == "AxisLT")
            return ["LT"]
        if (this._axisGroup == "AxisRT")
            return ["RT"]
        return []
    }

    _ClampAxis(name, v) {
        if (!IsNumber(v))
            v := (name == "LT" || name == "RT" || name == "LX" || name == "RX") ? 100 : 0
        v := Integer(v)
        if (name == "LT" || name == "RT") {
            if (v < 0)
                return 0
            if (v > 100)
                return 100
            return v
        }
        if (v < -100)
            return -100
        if (v > 100)
            return 100
        return v
    }

    _StickVecLimit() {
        return 125
    }

    _ClampStickVector(x, y) {
        x := this._ClampAxis("LX", x)
        y := this._ClampAxis("LY", y)
        lim := this._StickVecLimit()
        len := Sqrt(x * x + y * y)
        if (len > lim && len > 0) {
            x := Round(x * lim / len)
            y := Round(y * lim / len)
            x := this._ClampAxis("LX", x)
            y := this._ClampAxis("LY", y)
        }
        return { x: x, y: y }
    }

    _StickFitOther(kept) {
        kept := Integer(kept)
        lim := this._StickVecLimit()
        rem := lim * lim - kept * kept
        if (rem <= 0)
            return 0
        return Integer(Sqrt(rem))
    }

    _NormalizeStickPair(keepName := "") {
        names := this._AxisNames()
        if (names.Length != 2)
            return
        xName := names[1], yName := names[2]
        x := this._ClampAxis(xName, this.AxisMap.Get(xName, 0))
        y := this._ClampAxis(yName, this.AxisMap.Get(yName, 0))
        if (keepName == yName) {
            maxX := this._StickFitOther(y)
            if (Abs(x) > maxX)
                x := (x < 0) ? -maxX : maxX
        } else {
            maxY := this._StickFitOther(x)
            if (Abs(y) > maxY)
                y := (y < 0) ? -maxY : maxY
        }
        this.AxisMap[xName] := x
        this.AxisMap[yName] := y
    }

    _ApplyAxisInput(which, raw) {
        names := this._AxisNames()
        if (which < 1 || which > names.Length)
            return
        name := names[which]
        this.AxisMap[name] := this._ClampAxis(name, raw)
        if (names.Length == 2)
            this._NormalizeStickPair(name)
        this._SyncAxisControls()
        this.Refresh()
    }

    OnAxisSlider(which, *) {
        if (this._syncing || this._axisGroup == "")
            return
        raw := this.ui.Query("AxisSlider" which)
        this._ApplyAxisInput(which, IsNumber(raw) ? Round(Float(raw)) : 0)
    }

    OnAxisText(which, *) {
        if (this._syncing || this._axisGroup == "")
            return
        raw := this.ui.Query("AxisVal" which)
        if (!IsNumber(raw))
            return
        this._ApplyAxisInput(which, raw)
    }

    OnAxisTextCommit(which, *) {
        if (this._syncing || this._axisGroup == "")
            return
        raw := this.ui.Query("AxisVal" which)
        if (!IsNumber(raw)) {
            this._SyncAxisControls()
            return
        }
        this._ApplyAxisInput(which, raw)
    }

    ClearAll() {
        this.Mode := "digital"
        this.CheckedArr := []
        this.AxisMap := Map()
        this._axisGroup := ""
        this._RefreshPadHighlight()
        this.Refresh()
    }

    Init(cmd) {
        cmd := RMTParseErrHandle(cmd).cmd
        cmd := JoyLegacyKeyToJoyCmd(cmd)
        this.Mode := "digital"
        this.CheckedArr := []
        this.AxisMap := Map()
        this._axisGroup := ""
        this.ui.Update("HoldTimeCon", "Text", "100")
        this.ui.Update("KeyCountCon", "Text", "1")
        this.ui.Update("PerIntervalCon", "Text", "200")
        this._SetKeyType(GetLang("点击"))

        paramArr := cmd != "" ? SplitCommand(cmd) : []
        if (paramArr.Length < 2) {
            this.CheckedArr := ["A"]
            this._RefreshPadHighlight()
            this.Refresh()
            return
        }

        typeWords := Map(GetLang("按下"), true, GetLang("松开"), true, GetLang("点击"), true)
        i := 2
        while (i <= paramArr.Length) {
            p := paramArr[i]
            if (RegExMatch(p, "^(LX|LY|RX|RY|LT|RT):(-?[0-9]+)$", &m)) {
                this.AxisMap[m[1]] := Integer(m[2])
            } else if (typeWords.Has(p)) {
                this._SetKeyType(p)
                if (i + 1 <= paramArr.Length)
                    this.ui.Update("HoldTimeCon", "Text", paramArr[i + 1])
                if (i + 2 <= paramArr.Length)
                    this.ui.Update("KeyCountCon", "Text", paramArr[i + 2])
                if (i + 3 <= paramArr.Length)
                    this.ui.Update("PerIntervalCon", "Text", paramArr[i + 3])
                break
            } else {
                for short in StrSplit(StrReplace(p, "+", "⎖"), "⎖") {
                    short := Trim(short)
                    if (short != "")
                        this.CheckedArr.Push(JoyInternalToShort(short))
                }
            }
            i++
        }

        this._ApplyLtRtMode()
        if (this.AxisMap.Count > 0) {
            if (this.AxisMap.Has("LX") || this.AxisMap.Has("LY"))
                this._axisGroup := "AxisLS"
            else if (this.AxisMap.Has("RX") || this.AxisMap.Has("RY"))
                this._axisGroup := "AxisRS"
            else if (this.AxisMap.Has("LT"))
                this._axisGroup := "AxisLT"
            else if (this.AxisMap.Has("RT"))
                this._axisGroup := "AxisRT"
            this._NormalizeStickPair("")
            this._SyncAxisControls()
        }
        this._RefreshPadHighlight()
        this.Refresh()
    }

    _ApplyLtRtMode() {
        if (this._LtRtAsButton()) {
            for name in ["LT", "RT"] {
                if (!this.AxisMap.Has(name))
                    continue
                if (Integer(this.AxisMap[name]) > 0) {
                    found := false
                    for v in this.CheckedArr {
                        if (v == name) {
                            found := true
                            break
                        }
                    }
                    if (!found)
                        this.CheckedArr.Push(name)
                }
                this.AxisMap.Delete(name)
            }
            if (this._axisGroup == "AxisLT" || this._axisGroup == "AxisRT")
                this._axisGroup := ""
            return
        }
        kept := []
        for v in this.CheckedArr {
            if (v == "LT" || v == "RT") {
                if (!this.AxisMap.Has(v))
                    this.AxisMap[v] := 100
            } else {
                kept.Push(v)
            }
        }
        this.CheckedArr := kept
        if (this._axisGroup == "" && this.AxisMap.Has("LT"))
            this._axisGroup := "AxisLT"
        else if (this._axisGroup == "" && this.AxisMap.Has("RT"))
            this._axisGroup := "AxisRT"
    }

    _KeyTypeIndex() {
        v := IsObject(this.ui) ? this.ui.Query("KeyTypeCon>SelectedIndex") : ""
        if (!IsNumber(v) || Integer(v) < 0)
            return 3
        return Integer(v) + 1
    }

    _KeyTypeText() {
        return IsObject(this.ui) ? this.ui.Query("KeyTypeCon") : GetLang("点击")
    }

    _SetKeyType(text) {
        items := GetLangArr(["按下", "松开", "点击"])
        idx := 3
        for i, it in items
            if (it == text)
                idx := i
        this.ui.Update("KeyTypeCon", "SelectedIndex", String(idx - 1))
    }

    _TypeHelpText() {
        str1 := GetLang("按下，松开是不消耗时间的，可以理解为瞬发")
        str2 := GetLang("按下后建议搭配一个松开，如果不松开再次按下，后续按下指令可能无效（卡键）")
        str3 := GetLang("点击时间小于200表现为点击， 大于250表现为长按")
        return Format("{}`n{}`n{}", str1, str2, str3)
    }

    OnChangeEditValue(*) {
        if ((this.HasProp("_loading") && this._loading) || !this._UiAlive())
            return
        this.Refresh()
    }

    UpdateCommandStr() {
        CommandStr := GetLang("手柄")
        order := ["LX", "LY", "RX", "RY", "LT", "RT"]
        for name in order {
            if (this.AxisMap.Has(name))
                CommandStr .= "_" name ":" this.AxisMap[name]
        }
        if (this.CheckedArr.Length > 0) {
            keys := ""
            for v in this.CheckedArr
                keys .= (keys == "" ? "" : "+") v
            CommandStr .= "_" keys
            CommandStr .= "_" this._KeyTypeText()
            if (this._KeyTypeIndex() == 3) {
                CommandStr .= "_" this.ui.Query("HoldTimeCon")
                if (this.ui.Query("KeyCountCon") != 1) {
                    CommandStr .= "_" this.ui.Query("KeyCountCon")
                    if (this.ui.Query("PerIntervalCon") != 0)
                        CommandStr .= "_" this.ui.Query("PerIntervalCon")
                }
            }
        }
        this.CommandStr := CommandStr
    }

    Refresh() {
        if (!this._UiAlive())
            return
        this._JoyLog("Refresh begin")
        this.UpdateCommandStr()
        isClick := this._KeyTypeIndex() == 3
        isCount := isClick
        isInter := isCount && this.ui.Query("KeyCountCon") != 1

        this.ui.Update("HoldTimeTipCon", "Visibility", isClick ? "Visible" : "Collapsed")
        this.ui.Update("HoldTimeCon", "Visibility", isClick ? "Visible" : "Collapsed")
        this.ui.Update("KeyCountTipCon", "Visibility", isCount ? "Visible" : "Collapsed")
        this.ui.Update("KeyCountCon", "Visibility", isCount ? "Visible" : "Collapsed")
        this.ui.Update("PerIntervalTipCon", "Visibility", isInter ? "Visible" : "Collapsed")
        this.ui.Update("PerIntervalCon", "Visibility", isInter ? "Visible" : "Collapsed")
        this._JoyLog("Refresh vis+cmd")
        this._SyncAnalogRowVis()
        this._ShowCommandStr()
        this._UpdateAnalogVisuals()
        this._JoyLog("Refresh end")
    }

    _ShowCommandStr() {
        global MySoftData
        if (!this._UiAlive())
            return
        if (this.HasProp("_loading") && this._loading)
            return
        try {
            disp := IsObject(MySoftData) ? MySoftData.FormatCmdJoyDisplay(this.CommandStr) : this.CommandStr
            full := (this.CommandStr == "")
                ? GetLang("当前指令：无")
                : Format("{}{}", GetLang("当前指令："), disp)
            xaml := this._CommandStrXaml(full)
            this._JoyLog("_ShowCommandStr len=" StrLen(xaml) " text=" full)
            this.ui.Update("CommandStrCon", "ClearItems", "")
            this._JoyLog("_ShowCommandStr AddXamlItem")
            this.ui.Update("CommandStrCon", "AddXamlItem", xaml)
            this._JoyLog("_ShowCommandStr done")
        } catch as e {
            this._JoyLog("_ShowCommandStr FAIL " e.Message " L" e.Line)
        }
    }

    _CommandGlyphKind(ch) {
        c := Ord(ch)
        if (c == 0x25B3 || c == 0x25B2 || c == 0xF13A || c == 0xF139 || c == 0xEA82 || c == 0xE768)
            return "tri"
        if (c == 0xE711 || c == 0xE8BB || c == 0xD7 || c == 0x2715)
            return "cross"
        if (c >= 0xE000 && c <= 0xF8FF)
            return "fluent"
        return ""
    }

    _CommandTextXaml(s) {
        return '<TextBlock Text="' this._EscapeXml(s) '" FontSize="12" VerticalAlignment="Center"'
            . ' Foreground="{DynamicResource TextMain}" FontFamily="' this._EscapeXml(this._CommandFont()) '"/>'
    }

    _CommandGlyphXaml(kind, ch) {
        fg := "{DynamicResource TextMain}"
        fam := (kind == "tri") ? "Segoe UI Symbol, Segoe UI" : this._FluentFont()
        return '<TextBlock Text="&#x' Format("{:X}", Ord(ch)) ';" FontSize="12" VerticalAlignment="Center" Margin="0,1,0,0"'
            . ' Foreground="' fg '" FontFamily="' this._EscapeXml(fam) '"/>'
    }

    _CommandStrXaml(text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        inner := "", buf := ""
        Loop Parse text {
            kind := this._CommandGlyphKind(A_LoopField)
            if (kind == "") {
                buf .= A_LoopField
                continue
            }
            if (buf != "") {
                inner .= this._CommandTextXaml(buf)
                buf := ""
            }
            inner .= this._CommandGlyphXaml(kind, A_LoopField)
        }
        if (buf != "")
            inner .= this._CommandTextXaml(buf)
        return '<StackPanel ' ns ' Orientation="Horizontal" VerticalAlignment="Center">' inner '</StackPanel>'
    }

    CheckIfValid() {
        if (this.AxisMap.Count == 0 && this.CheckedArr.Length == 0) {
            MsgBox(GetLang("请选择手柄按键或摇杆！"))
            return false
        }
        if (this.CheckedArr.Length > 0) {
            if (!IsInteger(this.ui.Query("KeyCountCon")) || Integer(this.ui.Query("KeyCountCon")) <= 0) {
                MsgBox(GetLang("按键次数必须为大于零的整数！"))
                return false
            }
            if (this._KeyTypeIndex() == 3) {
                if (IsFloat(this.ui.Query("HoldTimeCon")) || this.ui.Query("HoldTimeCon") < 0) {
                    MsgBox(GetLang("按键时间请输入大于0的整数"))
                    return false
                }
            }
        }
        return true
    }

    OnSureBtnClick(*) {
        this.UpdateCommandStr()
        if (!this.CheckIfValid())
            return
        if (!IsViGEmInstalled()) {
            ShowViGEmInstallTip()
            return
        }
        action := this.SureBtnAction
        action(this.CommandStr)
        this.OnGuiClose()
    }

    TriggerMacro(*) {
        if (!this.CheckIfValid())
            return
        this.UpdateCommandStr()
        OnTriggerSepcialItemMacro(this.CommandStr)
    }

    ToggleFunc(state) {
        if (state) {
            try Hotkey("!l", this.TriggerAction, "On")
        } else {
            try Hotkey("!l", this.TriggerAction, "Off")
        }
    }

    _OnLiveAnalogPicked() {
    }

    _JoyLog(msg) {
        try JoyPickerLog(msg)
    }

    _OnLiveButton(short) {
        this._JoyLog("_OnLiveButton " short)
        if (!IsObject(this.ui) || (this.HasProp("_closed") && this._closed))
            return
        if (this.HasProp("_joyUserOff") && IsObject(this._joyUserOff) && this._joyUserOff.Has(short)) {
            this._JoyLog("_OnLiveButton skip userOff " short)
            return
        }
        this._joyLiveClick := true
        try this.OnPadClick(short)
        catch as e
            this._JoyLog("_OnLiveButton OnPadClick FAIL " short " " e.Message " L" e.Line)
        this._joyLiveClick := false
        this._JoyLog("_OnLiveButton done " short)
    }

    _ApplyLiveStick(id, a1, a2, x, y) {
        if (!IsObject(this.ui) || (this.HasProp("_closed") && this._closed))
            return
        if (this.HasProp("_stickDrag") && this._stickDrag != "")
            return
        pair := this._ClampStickVector(x, y)
        x := pair.x
        y := pair.y
        if (Sqrt(x * x + y * y) < 20) {
            this._joyListenPrev[id] := false
            if (IsObject(this._joyStickOff) && this._joyStickOff.Has(id))
                this._joyStickOff.Delete(id)
            return
        }
        if (this.HasProp("_joyStickOff") && IsObject(this._joyStickOff) && this._joyStickOff.Has(id))
            return
        oldX := this.AxisMap.Get(a1, 0)
        oldY := this.AxisMap.Get(a2, 0)
        first := !this._joyListenPrev.Get(id, false)
        this.AxisMap[a1] := x
        this.AxisMap[a2] := y
        this._axisGroup := id
        this._NormalizeStickPair("")
        nx := this.AxisMap[a1]
        ny := this.AxisMap[a2]
        if (!first && nx == oldX && ny == oldY)
            return
        this._JoyLog("_ApplyLiveStick " id " " nx "," ny " first=" first)
        this._OnLiveAnalogPicked()
        try this._SyncAxisControls()
        if (first) {
            try this.UpdateCommandStr()
            try this._ShowCommandStr()
            try this._RefreshPadHighlight()
            try this.Refresh()
        }
        this._joyListenPrev[id] := true
        this._JoyLog("_ApplyLiveStick done " id)
    }

    _ApplyLiveTriggersExclusive(lt, rt) {
        if (this._LtRtAsButton())
            return
        lt := this._ClampAxis("LT", lt)
        rt := this._ClampAxis("RT", rt)
        lOn := lt >= 8
        rOn := rt >= 8
        if (!lOn && !rOn) {
            if (IsObject(this._joyStickOff)) {
                if (this._joyStickOff.Has("AxisLT"))
                    this._joyStickOff.Delete("AxisLT")
                if (this._joyStickOff.Has("AxisRT"))
                    this._joyStickOff.Delete("AxisRT")
            }
            return
        }
        if (lOn && (!rOn || lt >= rt))
            this._SetLiveTriggerOnly("LT", "AxisLT", lt)
        else
            this._SetLiveTriggerOnly("RT", "AxisRT", rt)
    }

    _SetLiveTriggerOnly(name, id, v) {
        if (!IsObject(this.ui) || (this.HasProp("_closed") && this._closed))
            return
        if (this.HasProp("_joyStickOff") && IsObject(this._joyStickOff) && this._joyStickOff.Has(id))
            return
        other := (name == "LT") ? "RT" : "LT"
        if (this.AxisMap.Has(other))
            this.AxisMap.Delete(other)
        first := !this._joyListenPrev.Get(id, false)
        if (!first && this.AxisMap.Has(name) && Abs(this.AxisMap[name] - v) < 2)
            return
        this.AxisMap[name] := v
        this._axisGroup := id
        this._OnLiveAnalogPicked()
        try this._SyncAxisControls()
        if (first) {
            try this.UpdateCommandStr()
            try this._ShowCommandStr()
            try this._RefreshPadHighlight()
            try this.Refresh()
        }
        this._joyListenPrev[id] := true
        this._joyListenPrev[(id == "AxisLT") ? "AxisRT" : "AxisLT"] := false
    }

    OnWindowLoad(*) {
        if (!this._UiAlive())
            return
        try XamlWin.OnLoadTheme(this.ui)
        try JoyPickerHook.Attach(this)
        this._loading := false
        try this._ShowCommandStr()
    }

    _StopJoyHook() {
        this._closed := true
        this._loading := false
        try JoyPickerHook.Detach(this)
        this._stickDrag := ""
        try SetTimer(this._stickTick, 0)
        try this.ToggleFunc(false)
    }

    OnWindowClosing(*) {
        if (this.HasProp("_closing") && this._closing) {
            this.ui := ""
            return
        }
        this._closing := true
        this._StopJoyHook()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
    }

    OnCancelClick(*) {
        this._CloseWindow()
    }

    _CloseWindow() {
        if (this.HasProp("_closing") && this._closing)
            return
        this._closing := true
        this._StopJoyHook()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        ui := this.ui
        this.ui := ""
        if (IsObject(ui)) {
            try ui.Update("Window", "Close", "")
        }
    }

    OnGuiClose() {
        this._CloseWindow()
    }
}

; JoyShortToInternal / JoyInternalToShort 已移到 Main\Util\JoyNameUtil.ahk（Worker 进程也要用）

IsJoyLegacyKeyCmd(cmd) {
    if (cmd == "")
        return false
    paramArr := SplitCommand(cmd)
    if (paramArr.Length < 1)
        return false
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (GetCmdOnlyText(textOnly) != GetLang("按键"))
        return false
    keyName := ""
    if (numbersOnly != "") {
        try keyName := GetMacroCMDData(paramArr[1]).KeyName
    } else if (paramArr.Length >= 2) {
        keyName := paramArr[2]
    }
    return InStr(keyName, "Joy") || InStr(keyName, "Axis") || InStr(keyName, "Dpad")
}

JoyLegacyKeyToJoyCmd(cmd) {
    if (cmd == "")
        return cmd
    paramArr := SplitCommand(cmd)
    if (paramArr.Length < 1)
        return cmd
    SplitSerialTextAndNumbers(paramArr[1], &textOnly, &numbersOnly)
    if (GetCmdOnlyText(textOnly) == GetLang("手柄"))
        return cmd
    if (GetCmdOnlyText(textOnly) != GetLang("按键"))
        return cmd
    if (!IsJoyLegacyKeyCmd(cmd))
        return cmd

    keyName := ""
    ktype := GetLang("点击")
    hold := 100
    count := 1
    interval := 0
    axisCmd := ""
    if (numbersOnly != "") {
        Data := GetMacroCMDData(paramArr[1])
        keyName := Data.KeyName
        if (IsObject(Data) && Data.IsAxis && InStr(Data.KeyName, "JoyAxis")) {
            axisCmd := JoyInternalToShort(Data.KeyName) ":" (Data.HasOwnProp("AxisValue") ? Data.AxisValue : 0)
        } else {
            ktype := GetLangArr(["按下", "松开", "点击"])[Data.KeyType]
            hold := Data.HoldTime
            count := Data.Count
            interval := Data.IntervalTime
        }
    } else {
        keyName := paramArr[2]
        if (RegExMatch(keyName, "^(JoyAxisL[XY]|JoyAxisR[XY]|JoyAxisLT|JoyAxisRT):(-?[0-9]+)$", &am))
            axisCmd := SubStr(am[1], 8) ":" am[2]
        else {
            if (paramArr.Length >= 3)
                ktype := paramArr[3]
            if (paramArr.Length >= 4)
                hold := paramArr[4]
            if (paramArr.Length >= 5)
                count := paramArr[5]
            if (paramArr.Length >= 6)
                interval := paramArr[6]
        }
    }
    if (axisCmd != "")
        return GetLang("手柄") "_" axisCmd

    shorts := ""
    for part in StrSplit(keyName, "⎖") {
        s := JoyInternalToShort(part)
        shorts .= (shorts == "" ? "" : "+") s
    }
    out := GetLang("手柄") "_" shorts "_" ktype
    if (ktype == GetLang("点击")) {
        out .= "_" hold
        if (count != 1 && count != "1") {
            out .= "_" count
            if (interval != 0 && interval != "0")
                out .= "_" interval
        }
    }
    return out
}

; JoyCmdToPressKeyParts 已移到 Main\Util\JoyNameUtil.ahk（Worker 进程的 MacroUtil 也要调用）
