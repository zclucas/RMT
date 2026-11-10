#Requires AutoHotkey v2.0

; 每项操作持有自己的窗口，可报告百分比，也可只显示当前阶段。
class RmtProgress {
    static Run(title, message, action, owner := "") {
        progress := RmtProgress(title, message, owner)
        ownerWindow := owner ? "ahk_id " owner : ""
        restoreOwner := owner && DllCall("user32\IsWindowEnabled", "Ptr", owner, "Int")
        try {
            if (restoreOwner)
                try WinSetEnabled(false, ownerWindow)
            progress.Show()
            return action.Call(progress)
        } finally {
            progress.Close()
            if (restoreOwner)
                try WinSetEnabled(true, ownerWindow)
        }
    }

    __New(title, message, owner := "", cancelText := "") {
        this.title := title
        this.message := message
        this.owner := owner
        this.cancelText := cancelText
        this.Cancelled := false
        this.finished := false
        this.opening := false
        this.percent := ""
        this.ui := ""
        this.lastUpdate := 0
    }

    Show() {
        if (this.finished || this.opening)
            return
        if (IsObject(this.ui) && this.ui.wpfHwnd) {
            try WinActivate("ahk_id " this.ui.wpfHwnd)
            return
        }
        this.opening := true
        try {
            body := XAML_Generator("StackPanel").Margin("20,16,20,18")
            body.Add("TextBlock").Name("ProgressText").Text(this._DisplayText())
                .Foreground("{DynamicResource TextMain}").TextWrapping("Wrap")
            body.Add("ProgressBar").Name("OperationProgress").Height(9).Margin("0,12,0,0")
                .Foreground("{DynamicResource ProgressBar}").Maximum(100)
                .IsIndeterminate(this.percent == "" ? "True" : "False")
                .Value(this.percent == "" ? 0 : this.percent)
            height := 120
            if (this.cancelText != "") {
                body.Add("Button").Name("CancelOperation").Content(this.cancelText).Height(30)
                    .HorizontalAlignment("Right").MinWidth(90).Margin("0,14,0,0")
                height := 164
            }
            ui := XamlWin.Create(this.title, body, 440, height)
            ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
            ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"',
                'WindowStartupLocation="Manual"' XamlWin.PosAttr(440, height, this.owner))
            if (this.cancelText == "")
                ui.Update("BtnClosePanel", "Visibility", "Collapsed")
            else {
                ui.OnEvent("CancelOperation", "Click", ObjBindMethod(this, "_Cancel"))
                ui.OnEvent("Window", "Closing", ObjBindMethod(this, "_Cancel"))
            }
            this.ui := ui
            if (!XamlWin.Open(ui, "", this.owner))
                this.Close()
        } catch {
            this.Close()
        } finally this.opening := false
    }

    Report(message, percent := "") {
        if (percent != "")
            percent := Max(0, Min(100, percent))
        phaseChanged := (this.percent == "") != (percent == "")
        this.message := message
        this.percent := percent
        if (!IsObject(this.ui) || !this.ui.wpfHwnd)
            return
        if (!phaseChanged && percent != "" && percent < 100 && A_TickCount - this.lastUpdate < 80)
            return
        this.lastUpdate := A_TickCount
        try this.ui.BatchUpdate([
            {ControlName: "ProgressText", PropertyName: "Text", Value: this._DisplayText()},
            {ControlName: "OperationProgress", PropertyName: "IsIndeterminate", Value: percent == "" ? "True" : "False"},
            {ControlName: "OperationProgress", PropertyName: "Value", Value: String(percent == "" ? 0 : percent)}
        ])
    }

    _DisplayText() => this.message (this.percent == "" ? "" : "  (" Floor(this.percent) "%)")

    _Cancel(*) {
        if (!this.finished)
            this.Cancelled := true
    }

    Close() {
        this.finished := true
        ui := this.ui
        this.ui := ""
        if (IsObject(ui))
            try ui.Update("Window", "Close", "")
    }
}
