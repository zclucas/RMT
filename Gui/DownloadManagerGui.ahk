#Requires AutoHotkey v2.0

class DownloadManagerGui {
    static instance := ""

    static Open() {
        if (IsObject(DownloadManagerGui.instance) && IsObject(DownloadManagerGui.instance.ui)) {
            try WinActivate("ahk_id " DownloadManagerGui.instance.Hwnd())
            return
        }
        inst := DownloadManagerGui()
        DownloadManagerGui.instance := inst
        inst.Show()
    }

    __New() {
        this.ui := ""
        this.rowIds := []
        this.rowKeys := Map()
        this.rowBindings := Map()
        this.signature := "__initial__"
        this.timer := ObjBindMethod(this, "Refresh")
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    Show() {
        global MainSoftData
        title := GetLang("下载管理")
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
            .TextElement_FontSize(XAMLHost.FontSize())
        main.Rows("30", "*")
        XAMLHost.AddTitleBar(main, title, "30")

        body := main.Add("Grid").Grid_Row(1).Margin("14,10")
        body.Rows("Auto", "*", "Auto")
        body.Add("TextBlock").Grid_Row(0).Name("TxtDownloadSummary")
            .Foreground("{DynamicResource TextSub}").Margin("0,0,0,8")
        scroll := body.Add("ScrollViewer").Grid_Row(1).VerticalScrollBarVisibility("Auto")
        scroll.Add("StackPanel").Name("DownloadItems")
        buttons := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal")
            .HorizontalAlignment("Right").Margin("0,10,0,0")
        buttons.Add("Button").Name("BtnOpenDownloadFolder").Content(GetLang("打开下载目录"))
            .Padding("10,4")

        ownerHwnd := (IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.HasProp("Hwnd")) ? MainSoftData.MyGui.Hwnd : 0
        xaml := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        this.ui := XAMLHost(StrReplace(xaml, "%app%", main.ToString()), "", ownerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' EscapeXamlXml(title) '" Width="760" Height="520"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnClosing"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClose"))
        this.ui.OnEvent("BtnOpenDownloadFolder", "Click", ObjBindMethod(this, "OnOpenFolder"))

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this))) {
            this.ui := ""
            DownloadManagerGui.instance := ""
            return
        }
        this.Refresh()
        SetTimer(this.timer, 500)
    }

    Refresh(*) {
        if (!IsObject(this.ui))
            return
        jobs := RmtDownloadManager.Snapshot()
        signature := ""
        for job in jobs {
            percent := job.expectedBytes > 0
                ? Min(100, Floor(100 * job.receivedBytes / job.expectedBytes)) : -1
            receivedMb := Floor(job.receivedBytes / 1048576)
            signature .= job.id "|" job.status "|" percent "|" receivedMb "|" job.error "`n"
        }
        if (signature == this.signature)
            return
        this.signature := signature
        activeCount := 0
        for job in jobs
            if (job.status == "queued" || job.status == "downloading")
                activeCount += 1
        this.ui.Update("TxtDownloadSummary", "Text",
            Format(GetLang("共 {} 个下载任务，{} 个进行中"), jobs.Length, activeCount))

        updates := [{ControlName: "DownloadItems", PropertyName: "ClearItems", Value: ""}]
        for index, job in jobs {
            if (!this.rowKeys.Has(job.id)) {
                this.rowIds.Push(job.id)
                this.rowKeys[job.id] := this.rowIds.Length
            }
            rowKey := this.rowKeys[job.id]
            updates.Push({ControlName: "DownloadItems", PropertyName: "AddXamlItem",
                Value: this._JobRowXaml(rowKey, job)})
        }
        this.ui.BatchUpdate(updates)
        for index, job in jobs {
            rowKey := this.rowKeys[job.id]
            removeAction := job.status == "queued" || job.status == "downloading" ? "Cancel" : "Delete"
            for action in ["Open", "Retry", removeAction] {
                name := "Btn" action "Download_" rowKey
                bindingKey := name
                if (!this.rowBindings.Has(bindingKey)) {
                    this.rowBindings[bindingKey] := true
                    this.ui.OnEvent(name, "Click", this._JobActionHandler(rowKey, action))
                }
                this.ui.BindEventBatched(name, "Click")
            }
        }
    }

    _JobRowXaml(index, job) {
        name := EscapeXamlXml(job.name)
        status := this._StatusText(job)
        error := job.error == "" ? "" : "`n" job.error
        received := job.receivedBytes > 0 ? Format("{:.1f} MB", job.receivedBytes / 1048576) : "0 MB"
        total := job.expectedBytes > 0 ? Format(" / {:.1f} MB", job.expectedBytes / 1048576) : ""
        percent := job.expectedBytes > 0
            ? Format("  {:.0f}% ", Min(100, 100 * job.receivedBytes / job.expectedBytes)) : "  "
        progress := job.status == "downloading" ? percent received total : ""
        canCancel := job.status == "queued" || job.status == "downloading"
        canRetry := job.status == "completed" || job.status == "failed" || job.status == "cancelled"
        removeAction := canCancel ? "Cancel" : "Delete"
        removeLabel := canCancel ? GetLang("取消") : GetLang("删除")
        return '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
            . ' CornerRadius="6" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" Margin="0,0,0,8" Padding="10,8">'
            . '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>'
            . '<ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0"><TextBlock Text="' name '" Foreground="{DynamicResource InputText}"'
            . ' FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>'
            . '<TextBlock Text="' EscapeXamlXml(status . progress . error) '" Foreground="{DynamicResource TextSub}"'
            . ' TextWrapping="Wrap" Margin="0,3,8,0"/></StackPanel>'
            . '<Button Grid.Column="1" Name="BtnOpenDownload_' index '" Content="' EscapeXamlXml(GetLang("打开目录")) '"'
            . ' Padding="8,3" Margin="4,0"/>'
            . '<Button Grid.Column="2" Name="BtnRetryDownload_' index '" Content="' EscapeXamlXml(GetLang("重试")) '"'
            . ' IsEnabled="' (canRetry ? "True" : "False") '" Padding="8,3" Margin="4,0"/>'
            . '<Button Grid.Column="3" Name="Btn' removeAction 'Download_' index '" Content="' EscapeXamlXml(removeLabel) '"'
            . ' Padding="8,3" Margin="4,0"/>'
            . '</Grid></Border>'
    }

    _StatusText(job) {
        switch job.status {
            case "queued": return GetLang("排队中")
            case "downloading": return GetLang("下载中")
            case "completed": return GetLang("已完成")
            case "failed": return GetLang("失败")
            case "cancelled": return GetLang("已取消")
            default: return job.status
        }
    }

    _JobActionHandler(index, action) {
        return (state, ctrl, event) => this.OnJobAction(index, action)
    }

    OnJobAction(index, action) {
        if (index > this.rowIds.Length)
            return
        id := this.rowIds[index]
        if (action == "Open") {
            if (RmtDownloadManager.jobs.Has(id)) {
                SplitPath(RmtDownloadManager.jobs[id].targetPath, , &dir)
                if (dir != "")
                    Run('"' dir '"')
            }
        } else {
            try {
                if (action == "Cancel")
                    RmtDownloadManager.Cancel(id)
                else if (action == "Delete")
                    RmtDownloadManager.Delete(id)
                else if (action == "Retry")
                    RmtDownloadManager.Retry(id)
            } catch as error {
                RmtDialog.Info(error.Message, GetLang("下载管理"), this.Hwnd())
            }
        }
        this.signature := ""
        this.Refresh()
    }

    OnOpenFolder(state, ctrl, event) {
        DirCreate(RmtCacheDir() "\Downloads")
        Run('"' RmtCacheDir() '\Downloads"')
    }

    OnClose(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }

    OnClosing(state, ctrl, event) {
        SetTimer(this.timer, 0)
        this.ui := ""
        DownloadManagerGui.instance := ""
    }
}
