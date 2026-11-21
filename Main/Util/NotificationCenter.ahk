#Requires AutoHotkey v2.0

class RmtNotifications {
    static entries := []
    static unread := 0
    static instance := ""
    static limit := 200

    static Add(message, level := "info") {
        message := Trim(String(message))
        if (message == "")
            return
        this.entries.Push({message: message, level: level, time: FormatTime(, "HH:mm:ss"), read: false})
        this.unread++
        if (this.entries.Length > this.limit) {
            removed := this.entries.RemoveAt(1)
            if (!removed.read)
                this.unread--
        }
    }

    static MarkRead() {
        for entry in this.entries
            entry.read := true
        this.unread := 0
    }

    static Clear() {
        this.entries := []
        this.unread := 0
    }

    static Open() {
        if (IsObject(this.instance) && IsObject(this.instance.ui)) {
            WinActivate("ahk_id " this.instance.ui.wpfHwnd)
            return
        }
        this.instance := RmtNotificationWindow()
        this.instance.Show()
    }
}

class RmtNotificationWindow {
    __New() {
        this.ui := ""
        this.signature := ""
        this.timer := ObjBindMethod(this, "Refresh")
    }

    Show() {
        title := GetLang("通知")
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows("30", "*", "48")
        XAMLHost.AddTitleBar(main, title, "30")
        main.Add("ListBox").Name("NotificationItems").Grid_Row(1).Margin("12,10,12,0")
            .Background("{DynamicResource ControlBg}").BorderThickness("0")
        buttons := main.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Right").Margin("0,0,12,0")
        buttons.Add("Button").Name("BtnClearNotifications").Content(GetLang("清除通知")).Padding("10,4").Margin("0,0,8,0")
        buttons.Add("Button").Name("BtnCloseNotifications").Content(GetLang("关闭")).Padding("10,4")
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()))
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' EscapeXamlXml(title) '" Width="560" Height="460"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnClosing"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClose"))
        this.ui.OnEvent("BtnCloseNotifications", "Click", ObjBindMethod(this, "OnClose"))
        this.ui.OnEvent("BtnClearNotifications", "Click", ObjBindMethod(this, "OnClear"))
        if (!XamlWin.Open(this.ui)) {
            this.ui := ""
            RmtNotifications.instance := ""
            return
        }
        this.Refresh()
        SetTimer(this.timer, 500)
    }

    Refresh(*) {
        if (!IsObject(this.ui))
            return
        entries := RmtNotifications.entries
        signature := entries.Length "|" RmtNotifications.unread
        if (signature == this.signature)
            return
        updates := [{ControlName: "NotificationItems", PropertyName: "ClearItems", Value: ""}]
        loop entries.Length {
            entry := entries[entries.Length - A_Index + 1]
            text := StrReplace(EscapeXamlXml(entry.time "  [" entry.level "]  " entry.message), "`n", "&#10;")
            updates.Push({ControlName: "NotificationItems", PropertyName: "AddXamlItem",
                Value: '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
                    . '<TextBlock Text="' text '" TextWrapping="Wrap" Foreground="{DynamicResource TextMain}"/>'
                    . '</ListBoxItem>'})
        }
        this.ui.BatchUpdate(updates)
        RmtNotifications.MarkRead()
        this.signature := entries.Length "|0"
    }

    OnClear(*) {
        RmtNotifications.Clear()
        this.signature := ""
        this.Refresh()
    }

    OnClose(*) {
        if (IsObject(this.ui))
            this.ui.Update("Window", "Close", "")
    }

    OnClosing(*) {
        SetTimer(this.timer, 0)
        this.ui := ""
        RmtNotifications.instance := ""
    }
}
