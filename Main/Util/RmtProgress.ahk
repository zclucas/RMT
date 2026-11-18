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

    __New(title, message, owner := "", cancelText := "", standalone := false) {
        this.title := title
        this.message := message
        this.owner := owner
        this.cancelText := cancelText
        this.standalone := standalone
        this.Cancelled := false
        this.finished := false
        this.opening := false
        this.showTimer := ""
        this.percent := ""
        this.downloadAlternative := ""
        this.downloadAlternativeLabel := ""
        this.ui := ""
        this.lastUpdate := 0
    }

    Show() {
        if (this.standalone) {
            if (!this.finished && !IsObject(this.ui))
                this._ShowStandalone()
            return
        }
        if (this.finished || this.opening || IsObject(this.showTimer))
            return
        if (IsObject(this.ui)) {
            if (this.ui.wpfHwnd)
                try WinActivate("ahk_id " this.ui.wpfHwnd)
            return
        }
        ; 短操作直接完成，避免进度窗闪现，也避免和主窗争用引擎。
        if (this.cancelText == "") {
            this.showTimer := ObjBindMethod(this, "_Show")
            SetTimer(this.showTimer, -200)
        } else
            this._Show()
    }

    _Show() {
        this.showTimer := ""
        if (this.finished)
            return
        this.opening := true
        try {
            this.displayedText := this._DisplayText()
            this.displayedPercent := this.percent
            body := XAML_Generator("StackPanel").Margin("20,16,20,18")
            body.Add("TextBlock").Name("ProgressText").Text(this.displayedText)
                .Foreground("{DynamicResource TextMain}").TextWrapping("Wrap")
            body.Add("ProgressBar").Name("OperationProgress").Height(9).Margin("0,12,0,0")
                .Foreground("{DynamicResource ProgressBar}").Maximum(100)
                .IsIndeterminate(this.displayedPercent == "" ? "True" : "False")
                .Value(this.displayedPercent == "" ? 0 : this.displayedPercent)
            alternative := body.Add("StackPanel").Name("DownloadAlternative").Margin("0,10,0,0")
                .Visibility(this.downloadAlternative == "" ? "Collapsed" : "Visible")
            alternative.Add("TextBlock").Name("DownloadAlternativeLabel").Text(this.downloadAlternativeLabel)
                .Foreground("{DynamicResource TextMain}")
            alternative.Add("TextBox").Name("DownloadAlternativeUrl").Text(this.downloadAlternative)
                .IsReadOnly("True").TextWrapping("Wrap").Margin("0,4,0,0")
            height := 120
            if (this.cancelText != "") {
                body.Add("Button").Name("CancelOperation").Content(this.cancelText).Height(30)
                    .HorizontalAlignment("Right").MinWidth(90).Margin("0,14,0,0")
                height := 164
            }
            ui := XamlWin.Create(this.title, body, 440, "Auto")
            ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
            ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"',
                'WindowStartupLocation="Manual"' XamlWin.PosAttr(440, height, this.owner))
            if (this.cancelText == "")
                ui.Update("BtnClosePanel", "Visibility", "Collapsed")
            else {
                ui.OnEvent("CancelOperation", "Click", ObjBindMethod(this, "_Cancel"))
                ui.OnEvent("Window", "Closing", ObjBindMethod(this, "_Cancel"))
            }
            if (!this.finished) {
                this.ui := ui
                ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "_OnLoaded", ui))
                XamlWin.OpenNoWait(ui, "", this.owner)
            }
        } catch {
            this.Close()
        } finally this.opening := false
    }

    Report(message, percent := "") {
        this.message := message
        this.percent := percent == "" ? "" : Max(0, Min(100, percent))
        this._Refresh()
    }

    SetDownloadAlternative(url, label := "备用下载地址", force := false) {
        if (!force && url == this.downloadAlternative)
            return
        this.downloadAlternative := url
        this.downloadAlternativeLabel := label
        if (!IsObject(this.ui))
            return
        if (this.standalone) {
            this.ui["DownloadAlternativeLabel"].Value := label
            this.ui["DownloadAlternativeUrl"].Value := url
            this.ui["DownloadAlternativeLabel"].Visible := url != ""
            this.ui["DownloadAlternativeUrl"].Visible := url != ""
            this.ui.Show("AutoSize NA")
        } else if (this.ui.wpfHwnd) {
            try this.ui.BatchUpdate([
                {ControlName: "DownloadAlternativeLabel", PropertyName: "Text", Value: label},
                {ControlName: "DownloadAlternativeUrl", PropertyName: "Text", Value: url},
                {ControlName: "DownloadAlternative", PropertyName: "Visibility", Value: url == "" ? "Collapsed" : "Visible"}
            ])
        }
    }

    _OnLoaded(ui, *) {
        ; 异步建窗可能尚未读取共享内存，等句柄回传后再关窗。
        if (this.finished) {
            if (ui.wpfHwnd)
                try ui.Update("Window", "Close", "")
            return
        }
        this._Refresh(true)
        this.SetDownloadAlternative(this.downloadAlternative, this.downloadAlternativeLabel, true)
    }

    _Refresh(force := false) {
        if (this.standalone) {
            if (IsObject(this.ui)) {
                this.ui["ProgressText"].Text := this._DisplayText()
                bar := this.ui["OperationProgress"]
                if (this.displayedPercent == "") != (this.percent == "") {
                    bar.Opt(this.percent == "" ? "+0x8" : "-0x8")
                    SendMessage(0x40A, this.percent == "", 40, bar)
                }
                if (this.percent != "")
                    bar.Value := Floor(this.percent)
                this.displayedPercent := this.percent
            }
            return
        }
        if (!IsObject(this.ui) || !this.ui.wpfHwnd)
            return
        message := this._DisplayText()
        percent := this.percent
        if (message == this.displayedText && percent == this.displayedPercent)
            return
        phaseChanged := (this.displayedPercent == "") != (percent == "")
        if (!force && !phaseChanged && percent != "" && percent < 100 && A_TickCount - this.lastUpdate < 80)
            return
        this.lastUpdate := A_TickCount
        this.displayedText := message
        this.displayedPercent := percent
        try this.ui.BatchUpdate([
            {ControlName: "ProgressText", PropertyName: "Text", Value: message},
            {ControlName: "OperationProgress", PropertyName: "IsIndeterminate", Value: percent == "" ? "True" : "False"},
            {ControlName: "OperationProgress", PropertyName: "Value", Value: String(percent == "" ? 0 : percent)}
        ])
    }

    _DisplayText() => this.message (this.percent == "" ? "" : "  (" Floor(this.percent) "%)")

    _Cancel(*) {
        if (!this.finished)
            this.Cancelled := true
    }

    ; 独立程序使用同一进度接口，避免加载待替换的 XAML 运行时。
    _ShowStandalone() {
        ui := Gui("-MinimizeBox -MaximizeBox", this.title)
        ui.MarginX := 20
        ui.MarginY := 16
        ui.SetFont("s10", "Segoe UI")
        ui.AddText("w420 r2 vProgressText", this._DisplayText())
        ui.AddProgress("w420 h9 vOperationProgress +0x8")
        ui.AddText("w420 Hidden vDownloadAlternativeLabel")
        ui.AddEdit("w420 r3 ReadOnly -VScroll Hidden vDownloadAlternativeUrl")
        ui.OnEvent("Close", (*) => 1)
        this.ui := ui
        this.displayedPercent := ""
        SendMessage(0x40A, 1, 40, ui["OperationProgress"])
        this._Refresh()
        ui.Show("AutoSize Center")
        if (this.downloadAlternative != "")
            this.SetDownloadAlternative(this.downloadAlternative, this.downloadAlternativeLabel, true)
    }

    Close() {
        this.finished := true
        showTimer := this.showTimer
        this.showTimer := ""
        if (IsObject(showTimer))
            SetTimer(showTimer, 0)
        ui := this.ui
        this.ui := ""
        if (IsObject(ui)) {
            if (this.standalone)
                ui.Destroy()
            else if (ui.wpfHwnd)
                try ui.Update("Window", "Close", "")
        }
    }
}
