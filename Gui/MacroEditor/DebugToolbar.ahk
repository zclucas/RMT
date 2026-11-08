
class MacroDebugToolbar {
    static Actions := [
        {name: "Continue", glyph: 0xE768, label: "_ContinueLabel"},
        {name: "StepOver", glyph: 0xE76C, label: "_StepOverLabel"},
        {name: "StepInto", glyph: 0xE70D, label: "_StepIntoLabel"},
        {name: "StepOut", glyph: 0xE70E, label: "_StepOutLabel"},
        {name: "RunToCursor", path: "M 1,4 L 7,8 L 1,12 Z M 9,2 L 15,9 L 12,9 L 10.5,12 Z", label: "_RunToCursorLabel"},
        {name: "Kill", glyph: 0xE71A, label: ""}
    ]

    static ActiveTrigger() {
        return '<Trigger Property="Tag" Value="DebugToolbarOpen">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ActionBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionStroke}"/>'
            . '</Trigger>'
    }

    static Build(editor) {
        win := XAML_Generator("Window")
            .SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
            .SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
            .Title(GetLang("调试")).WindowStyle("None").ResizeMode("NoResize").SizeToContent("WidthAndHeight")
            .ShowInTaskbar("False").ShowActivated("False").AllowsTransparency("True")
            .WindowStartupLocation("Manual").Background("Transparent").Opacity(0)
        frame := win.Add("Border").CornerRadius(5).Padding("4")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource OutlineStroke}").BorderThickness(1.5)
        row := frame.Add("StackPanel").Orientation("Horizontal")
        row.Add("Border").Name("DragArea").Width(22).Cursor("SizeAll").Background("Transparent").ToolTip(GetLang("拖拽"))
            .Add("TextBlock").Text("⠿").FontFamily("Segoe UI Symbol").FontSize(16).IsHitTestVisible("False")
            .Foreground("{DynamicResource TextSub}").HorizontalAlignment("Center").VerticalAlignment("Center")
        row.InjectResources('<Style TargetType="Button"><Setter Property="Template"><Setter.Value>'
            . '<ControlTemplate TargetType="Button"><Border x:Name="Surface" Background="Transparent" CornerRadius="3"'
            . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1.25">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Background" Value="{DynamicResource BtnPressBg}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')
        for action in this.Actions {
            button := row.Add("Button").Name("MacroDebug" action.name).ToolTip(this.Label(editor, action.label))
                .Width(28).Height(28).Margin("3,0,0,0").Cursor("Hand").Focusable("False")
                .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14).FontWeight("Bold")
                .Foreground("{DynamicResource TextMain}")
            if (action.HasOwnProp("path")) {
                button.Add("Path").Data(action.path).Width(16).Height(14).Stretch("Uniform")
                    .Stroke("{DynamicResource TextMain}").StrokeThickness(1.5).StrokeLineJoin("Round")
            } else
                button.Content(Chr(action.glyph))
        }
        return win.ToString()
    }

    static Label(editor, method) => method == "" ? GetLang("终止") : editor.%method%()

    static Run(editor, method, *) {
        editor.MenuHandler(this.Label(editor, method))
    }

    __New(ui, launcher, dot, anchor, editor, dispatch, bindLive := false) {
        this.ui := ui
        this.launcher := launcher
        this.dot := dot
        this.anchor := anchor
        this.editor := editor
        this.dispatch := dispatch
        this.popup := ""
        this.position := ""
        this.open := false
        ui.OnEvent(launcher, "Click", ObjBindMethod(this, "Toggle"))
        if (bindLive)
            ui.BindEventBatched(launcher, "Click")
    }

    Toggle(*) {
        if (this.open) {
            this.Hide()
            return
        }
        this._SetOpen(true)
        SetTimer(ObjBindMethod(this, "_Show"), -1)
    }

    Hide(*) {
        if (!this.open)
            return
        popup := this.popup
        this.popup := ""
        this._SetOpen(false)
        if (IsObject(popup)) {
            this._RememberPosition(popup)
            popup.Update("Window", "Close", "")
        }
    }

    _Show() {
        if (!this.open || IsObject(this.popup))
            return
        owner := this.ui.wpfHwnd
        if (!owner || !DllCall("user32\IsWindowVisible", "Ptr", owner, "Int")) {
            this.Hide()
            return
        }
        ; 在 Show 前查询，避免在引擎的 LoadedHwnd 回调内同步查询。
        anchor := []
        try anchor := StrSplit(this.ui.Query(this.anchor ">ScreenOrigin"), ",")
        if (!this.open || IsObject(this.popup))
            return
        try {
            popup := XAMLHost(MacroDebugToolbar.Build(this.editor), "", owner)
            this.popup := popup
            popup.skipFontScale := true
            popup.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "_OnLoaded", popup, anchor))
            popup.OnEvent("Window", "Closing", ObjBindMethod(this, "_OnClosing", popup))
            for action in MacroDebugToolbar.Actions
                popup.OnEvent("MacroDebug" action.name, "Click", ObjBindMethod(this, "_OnAction", popup, action.label))
            XamlWin.QueueTheme(popup)
            popup.Show()
        } catch {
            this.Hide()
        }
    }

    _OnLoaded(popup, anchor, *) {
        if (this.popup != popup)
            return
        hwnd := popup.wpfHwnd
        try WinSetExStyle("+0x08000000", hwnd) ; 点击调试浮窗时保留编辑器焦点与快捷键
        try {
            if (IsObject(this.position)) {
                x := this.position.x, y := this.position.y
                grip := Buffer(16)
                NumPut("Int", x + 8, "Int", y + 8, "Int", x + 24, "Int", y + 24, grip)
                if (!DllCall("user32\MonitorFromRect", "Ptr", grip, "UInt", 0, "Ptr"))
                    this.position := ""
            }
            if (!IsObject(this.position)) {
                if (anchor.Length == 2 && IsInteger(anchor[1]) && IsInteger(anchor[2])) {
                    x := Integer(anchor[1]) + 8, y := Integer(anchor[2]) + 8
                } else {
                    WinGetPos(&ownerX, &ownerY,,, this.ui.wpfHwnd)
                    x := ownerX + 8, y := ownerY + 64
                }
            }
            WinMove(x, y,,, hwnd)
        }
        popup.Update("Window", "Opacity", "1")
    }

    _OnAction(popup, method, *) {
        if (this.popup != popup)
            return
        try this.dispatch.Call(method)
        finally {
            if (method == "" && this.popup == popup)
                this.Hide()
        }
    }

    _RememberPosition(popup) {
        if (popup.wpfHwnd) {
            try {
                WinGetPos(&x, &y,,, popup.wpfHwnd)
                this.position := {x: x, y: y}
            }
        }
    }

    _OnClosing(popup, *) {
        if (this.popup != popup)
            return
        this._RememberPosition(popup)
        this.popup := ""
        this._SetOpen(false)
    }

    _SetOpen(open) {
        this.open := open
        vis := open ? "Visible" : "Collapsed"
        try this.ui.BatchUpdate([
            {ControlName: this.launcher, PropertyName: "Tag", Value: open ? "DebugToolbarOpen" : ""},
            {ControlName: this.launcher, PropertyName: "Foreground", Value: open ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}"},
            {ControlName: this.dot, PropertyName: "Visibility", Value: vis}
        ])
    }
}
