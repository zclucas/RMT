#Requires AutoHotkey v2.0

class ColorPanelGui {
    __New() {
        this.Gui := ""
        this.ui := ""
        this.SureAction := ""
        this.ColorValue := 0
        this.CoordX := 0
        this.CoordY := 0
        this.TargetHwnd := 0
        this.RowColorNum := 11
        this.ColColorNum := 15
        this.active := false
        this._colors := Map()
    }

    static Window(title, width) {
        win := XAML_Generator("Window")
        win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
        return win.Title(title).Width(width).SizeToContent("Height").WindowStyle("None")
            .AllowsTransparency("True").Background("Transparent").Topmost("True")
            .ShowInTaskbar("False").ShowActivated("False").ResizeMode("NoResize")
            .WindowStartupLocation("Manual").Opacity(0)
    }

    ShowGui(targetHwnd := 0) {
        if (this.active)
            return
        this.active := true
        this.TargetHwnd := targetHwnd
        this._colors := Map()
        this.AddGui()
    }

    AddGui() {
        win := ColorPanelGui.Window(GetLang("定位取色器"), 280)
        win.FontFamily(MainSoftData.FontType).FontSize(13).Foreground("{DynamicResource TextMain}")
        card := win.Add("Border").Name("DragArea").Background("{DynamicResource BgColor}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(12).Padding("16,8,16,12")
        body := card.Add("StackPanel")
        head := body.Add("Grid").Height(28).Margin("0,0,0,8")
        head.Cols("*", "28")
        head.Add("TextBlock").Text(GetLang("定位取色器")).FontSize(16).FontWeight("SemiBold").VerticalAlignment("Center")
        ; 整块卡片就是 DragArea（窗口无系统标题栏，靠它拖动），引擎的 WM_NCHITTEST 会把落在这块
        ; 区域里的点击判成标题栏，按钮就再也收不到 Click。标上 IsHitTestVisibleInChrome 让引擎
        ; 放行——和标题栏上的最小化/关闭钮同一个约定。
        closeBtn := head.Add("Button").Name("Cancel").Grid_Column(1).Width(28).Height(28).Cursor("Hand").Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness(0).WindowChrome_IsHitTestVisibleInChrome("True").ToolTip("Esc · " GetLang("取消"))
        closeBtn.Add("Path").Data("M 0,0 L 12,12 M 12,0 L 0,12").Width(12).Height(12)
            .Stroke("{DynamicResource TextMain}").StrokeThickness(1.5).Stretch("Uniform").IsHitTestVisible("False")
        closeBtn.InjectResources(this._ButtonStyle(false, "ControlBorder"))
        frame := body.Add("Border").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).HorizontalAlignment("Center")
        grid := frame.Add("Canvas").Width(240).Height(176).ClipToBounds("True")
        loop 11 {
            row := A_Index
            loop 15 {
                col := A_Index
                grid.Add("Rectangle").Name("Pixel_" col "_" row).Width(16).Height(16)
                    .Canvas_Left((col - 1) * 16).Canvas_Top((row - 1) * 16).Fill("{DynamicResource InputBg}")
            }
        }
        grid.Add("Rectangle").Width(20).Height(20).Canvas_Left(110).Canvas_Top(78).Stroke("Black").StrokeThickness(4).IsHitTestVisible("False")
        grid.Add("Rectangle").Width(20).Height(20).Canvas_Left(110).Canvas_Top(78).Stroke("White").StrokeThickness(2).IsHitTestVisible("False")
        ; 色块跨两行；HEX / RGB 与 X / Y 按列对齐。
        info := body.Add("Grid").Margin("0,12,0,12")
        info.Cols("48", "78", "*").Rows("20", "20")
        info.Add("Border").Name("Swatch").Grid_RowSpan(2).Width(40).Height(40).CornerRadius(4)
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness(1).HorizontalAlignment("Left")
        info.Add("TextBlock").Name("Hex").Grid_Column(1).Text("—").FontFamily("Consolas").FontSize(15)
            .FontWeight("SemiBold").VerticalAlignment("Center")
        info.Add("TextBlock").Name("RGB").Grid_Column(2).Text("RGB —").Foreground("{DynamicResource TextSub}")
            .FontFamily("Consolas").FontSize(11).VerticalAlignment("Center")
        info.Add("TextBlock").Name("CoordX").Grid_Row(1).Grid_Column(1).Text("X —")
            .FontFamily("Consolas").FontSize(13).VerticalAlignment("Center")
        info.Add("TextBlock").Name("CoordY").Grid_Row(1).Grid_Column(2).Text("Y —")
            .FontFamily("Consolas").FontSize(13).VerticalAlignment("Center")
        hints := body.Add("Border").TextElement_Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}").CornerRadius(6).Padding(10).Add("StackPanel")
        hints.Add("TextBlock").Text("↑ ↓ ← →   微调 1 像素").Margin("0,0,0,6")
        hints.Add("TextBlock").Text("Enter  确定       Esc  取消").Foreground("{DynamicResource InputText}")
        actions := body.Add("Grid").Margin("0,12,0,0")
        actions.Cols("72", "8", "*")
        reset := actions.Add("Button").Name("Reset").Content("复位").Height(34).Cursor("Hand")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness(1).WindowChrome_IsHitTestVisibleInChrome("True").ToolTip("将准星移回本屏幕中央")
        reset.InjectResources(this._ButtonStyle(false))
        confirm := actions.Add("Button").Name("Confirm").Grid_Column(2).Content("确定选取  ↵").Height(34).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness(1).WindowChrome_IsHitTestVisibleInChrome("True")
        confirm.InjectResources(this._ButtonStyle(true))
        this.ui := XAMLHost(win.ToString(), "", MyTargetGui.Hwnd())
        this.ui.skipFontScale := true
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "_Loaded"))
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnClose"))
        this.ui.OnEvent("Cancel", "Click", ObjBindMethod(this, "OnClose"))
        this.ui.OnEvent("Reset", "Click", (*) => MyTargetGui.ResetPosition())
        this.ui.OnEvent("Confirm", "Click", ObjBindMethod(this, "GuiDoubleClick"))
        ; 在窗口显示前入队应用主题，避免先出现固定深色再跳色。
        XamlWin.QueueTheme(this.ui)
        this.ui.Show()
        this.Gui := GuiAdapter(this.ui)
    }

    ; 独立模板覆盖默认按钮 hover，避免主题背景被全局模板清空。
    _ButtonStyle(primary, hoverResource := "") {
        hover := hoverResource != "" ? hoverResource : (primary ? "ActionHoverBg" : "EditHoverBg")
        stroke := primary ? "ActionHoverStroke" : "EditHoverStroke"
        pressed := primary ? "ActionPressBg" : "BtnPressBg"
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Surface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="{DynamicResource ' hover '}"/><Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource ' stroke '}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Background" Value="{DynamicResource ' pressed '}"/></Trigger>'
            . '<Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }
    _Loaded(*) {
        if (!this.active)
            return
        this.AvoidPoint(MyTargetGui.startX, MyTargetGui.startY)
        this.ui.Update("Window", "Opacity", "1")
    }

    AvoidPoint(x, y) {
        hwnd := this.ui.wpfHwnd
        WinGetPos(&oldX, &oldY, &w, &h, hwnd)
        monitor := MonitorGetPrimary()
        loop MonitorGetCount() {
            MonitorGet(A_Index, &l, &t, &r, &b)
            if (x >= l && x < r && y >= t && y < b) {
                monitor := A_Index
                break
            }
        }
        MonitorGetWorkArea(monitor, &l, &t, &r, &b)
        px := r - w - 16, py := t + 16
        if (x >= px - 45 && y <= py + h + 45)
            px := l + 16
        if (oldX != px || oldY != py)
            WinMove(px, py, , , hwnd)
    }

    RefreshCoord() {
        MyTargetGui.GetPoint(&x, &y)
        this.CoordX := x, this.CoordY := y
    }

    GetSelectedPoint() {
        if (!this.TargetHwnd)
            return [this.CoordX, this.CoordY]
        if (!WinExist("ahk_id " this.TargetHwnd))
            return []
        return GetWinPos(this.CoordX, this.CoordY, this.TargetHwnd)
    }

    RefreshMapImage() {
        colors := GetPixelColorMap(this.CoordX, this.CoordY, this.RowColorNum, this.ColColorNum)
        updates := []
        for key, value in colors {
            if (!this._colors.Has(key) || this._colors[key] != value)
                updates.Push({ControlName: "Pixel_" StrReplace(key, "-", "_"), PropertyName: "Fill", Value: Format("#{:06X}", Integer(value))})
        }
        this._colors := colors
        this.ColorValue := Integer(colors["8-6"])
        hex := Format("#{:06X}", this.ColorValue)
        updates.Push({ControlName: "Hex", PropertyName: "Text", Value: hex})
        updates.Push({ControlName: "Swatch", PropertyName: "Background", Value: hex})
        updates.Push({ControlName: "RGB", PropertyName: "Text", Value: Format("RGB {},{},{}", (this.ColorValue >> 16) & 255, (this.ColorValue >> 8) & 255, this.ColorValue & 255)})
        point := this.GetSelectedPoint()
        updates.Push({ControlName: "CoordX", PropertyName: "Text", Value: "X " (point.Length ? point[1] : "—")})
        updates.Push({ControlName: "CoordY", PropertyName: "Text", Value: "Y " (point.Length ? point[2] : "—")})
        this.ui.BatchUpdate(updates)
        return point
    }

    GuiDoubleClick(*) {
        if (!this.active || !MyTargetGui.Hwnd())
            return
        ; 确认时同步重采样，避免取到上一帧的颜色/坐标。
        this.RefreshCoord()
        point := this.RefreshMapImage()
        action := this.SureAction
        color := Format("{:06X}", this.ColorValue)
        this.OnClose()
        if (IsObject(action) && point.Length)
            action(point[1], point[2], color)
    }

    OnClose(*) {
        if (!this.active && !MyTargetGui.active)
            return
        this.active := false
        ui := this.ui
        this.ui := ""
        this.Gui := ""
        MyTargetGui.HideGui()
        if IsObject(ui)
            try ui.Update("Window", "Close", "")
    }

    static PickColor(defaultColor := "") {
        result := ""
        MyTargetGui.SureAction := (x, y, color) => result := "#" color
        MyTargetGui.ShowGui()
        Sleep(30)
        loop 600 {
            if (!MyTargetGui.active)
                return result
            Sleep(100)
        }
        MyColorPanel.OnClose()
        return result
    }
}
