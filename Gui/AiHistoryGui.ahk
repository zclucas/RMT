#Requires AutoHotkey v2.0

; =====================================================================
; AI 对话记录：新建 / 打开 / 删除已持久化会话
; 入口：侧栏 AI 工具栏「对话记录」
; =====================================================================

class AiHistoryGui {
    static instances := Map()
    static _opening := false

    __New(tabIdx := 0) {
        this.ui := ""
        this.closed := true
        this.tabIdx := Integer(tabIdx)
        this._revealed := false
        this._applying := false
        this._rowIds := []
        this._skipRow := false
    }

    static ShowGui(tabIdx := 0) {
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin))
                MyMainWin._AiPersistAllTabs()
        }
        key := "main"
        if (AiHistoryGui.instances.Has(key)) {
            oldInst := AiHistoryGui.instances[key]
            try {
                if (!oldInst.closed && IsObject(oldInst.ui)) {
                    oldInst.tabIdx := Integer(tabIdx)
                    oldInst._RefreshList()
                    try WinActivate("ahk_id " oldInst.ui.wpfHwnd)
                    return
                }
            }
            AiHistoryGui.instances.Delete(key)
        }
        try XAMLHost.EnsureDaemonHealthy()
        if (AiHistoryGui._opening)
            return
        AiHistoryGui._opening := true
        try {
            inst := AiHistoryGui(tabIdx)
            inst._BuildAndShow()
            AiHistoryGui.instances[key] := inst
        } finally {
            AiHistoryGui._opening := false
        }
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("对话记录")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("12,10,12,12")
        body.Rows("Auto", "*", "Auto")

        top := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").Margin("0,0,0,8")
        top.Add("Button").Name("BtnNewChat").Content(GetLang("新建对话")).Height(28).MinHeight(28).Padding("12,0").Margin("0,0,8,0")
        top.Add("TextBlock").Name("TxtHistHint").Text("").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextSub}").FontSize("11")

        sv := body.Add("ScrollViewer").Grid_Row(1).VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
            .Background("Transparent")
        sv.Add("StackPanel").Name("HistList").Margin("0")

        body.Add("TextBlock").Grid_Row(2).Name("TxtHistEmpty").Text(GetLang("暂无对话记录")).Margin("0,8,0,0")
            .Foreground("{DynamicResource TextSub}").HorizontalAlignment("Center").Visibility("Collapsed")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        owner := 0
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.HasProp("wpfHwnd"))
                owner := MyMainWin.ui.wpfHwnd
        }
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="380" Height="460" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("BtnNewChat", "Click", ObjBindMethod(this, "OnNewChatClick"))

        this._applying := true
        this._revealed := false
        XamlWin.OnLoadTheme(this.ui)
        this._QueueListRefresh()

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
        SetTimer(ObjBindMethod(this, "_ReleaseApplyingGuard"), -200)
    }

    _QueueListRefresh() {
        ; Show 前入队 Clear + 行；LoadedHwnd 一次刷入
        this._RefreshList(true)
    }

    _RefreshList(preShow := false) {
        if (!IsObject(this.ui))
            return
        sessions := AiChatStore.List()
        this._rowIds := []
        try this.ui.Update("HistList", "ClearItems", "")
        curId := ""
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin))
                curId := MyMainWin.AiGetSessionId(this.tabIdx)
        }
        count := 0
        for s in sessions {
            if (Type(s) != "Map" || !s.Has("id"))
                continue
            id := String(s["id"])
            title := s.Has("title") ? String(s["title"]) : GetLang("未命名对话")
            updated := s.Has("updated") ? AiChatStore.FormatUpdated(s["updated"]) : ""
            msgN := 0
            if (s.Has("messages") && Type(s["messages"]) = "Array")
                msgN := s["messages"].Length
            this._rowIds.Push(id)
            count++
            isCur := (curId != "" && curId = id)
            xaml := this._RowXaml(id, title, updated, msgN, isCur)
            try this.ui.Update("HistList", "AddXamlItem", xaml)
        }
        emptyVis := count < 1 ? "Visible" : "Collapsed"
        try this.ui.Update("TxtHistEmpty", "Visibility", emptyVis)
        hint := count < 1 ? "" : Format(GetLang("共 {1} 条"), count)
        try this.ui.Update("TxtHistHint", "Text", hint)
        if (!preShow)
            this._BindRowEvents()
        else
            SetTimer(ObjBindMethod(this, "_BindRowEvents"), -50)
    }

    _RowXaml(id, title, updated, msgN, isCur) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        safeId := RegExReplace(id, "[^A-Za-z0-9_]", "_")
        accent := isCur ? "{DynamicResource Accent}" : "{DynamicResource ControlBorder}"
        bg := isCur ? "{DynamicResource FoldHeaderBg}" : "{DynamicResource InputBg}"
        sub := updated
        if (msgN > 0)
            sub .= (sub == "" ? "" : " · ") Format(GetLang("{1} 条消息"), msgN)
        return '<Border ' ns ' Name="HistRow_' safeId '" Margin="0,0,0,6" Padding="10,8,8,8" CornerRadius="4"'
            . ' Background="' bg '" BorderThickness="1" BorderBrush="' accent '" Cursor="Hand" ClipToBounds="False">'
            . '<Grid ClipToBounds="False">'
            . '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Margin="0,0,6,0">'
            . '<TextBlock Text="' this._EscapeXml(title) '" TextTrimming="CharacterEllipsis"'
            . ' Foreground="{DynamicResource TextMain}" FontSize="12" FontWeight="' (isCur ? "SemiBold" : "Normal") '"/>'
            . '<TextBlock Text="' this._EscapeXml(sub) '" Margin="0,3,0,0"'
            . ' Foreground="{DynamicResource TextSub}" FontSize="11"/>'
            . '</StackPanel>'
            . '<Button Name="HistDel_' safeId '" Grid.Column="1" Width="24" Height="24" MinWidth="24" MinHeight="24"'
            . ' Padding="0" Margin="0" HorizontalAlignment="Center" VerticalAlignment="Center"'
            . ' Cursor="Hand" ToolTip="' this._EscapeXml(GetLang("删除")) '"'
            . ' FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}"'
            . ' BorderThickness="1.25" Foreground="{DynamicResource TextMain}" ClipToBounds="False"'
            . ' Content="' Chr(0xE74D) '">'
            . '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}"'
            . ' BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"'
            . ' CornerRadius="3" Width="24" Height="24" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
            . '<Trigger Property="IsPressed" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnPressBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Button.Template>'
            . '</Button></Grid></Border>'
    }

    _BindHist(name, evt, cb) {
        if (!IsObject(this.ui))
            return
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        try this.ui.Update(name, "BindEvent", evt)
    }

    _BindRowEvents(*) {
        if (!IsObject(this.ui) || this.closed)
            return
        for id in this._rowIds {
            safeId := RegExReplace(id, "[^A-Za-z0-9_]", "_")
            try this._BindHist("HistRow_" safeId, "MouseLeftButtonUp", ObjBindMethod(this, "OnRowClick", id))
            try this._BindHist("HistDel_" safeId, "Click", ObjBindMethod(this, "OnDelClick", id))
        }
    }

    OnRowClick(id, state, ctrl, event) {
        if (this._skipRow)
            return
        if (!IsSet(MyMainWin) || !IsObject(MyMainWin))
            return
        MyMainWin.AiLoadSession(this.tabIdx, id)
        this.OnCloseClick("", "", "")
    }

    OnDelClick(id, state, ctrl, event) {
        this._skipRow := true
        SetTimer(() => (this._skipRow := false), -200)
        if (!RmtDialog.Confirm(GetLang("确定删除这条对话记录？"), GetLang("对话记录")))
            return
        AiChatStore.Delete(id)
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && MyMainWin.AiGetSessionId(this.tabIdx) = id)
                MyMainWin.AiNewChat(this.tabIdx, false, false)
        }
        this._RefreshList()
        Toast.Success(GetLang("已删除"))
    }

    OnNewChatClick(state, ctrl, event) {
        if (!IsSet(MyMainWin) || !IsObject(MyMainWin))
            return
        MyMainWin.AiNewChat(this.tabIdx, true)
        this.OnCloseClick("", "", "")
    }

    _TryReveal() {
        if (this._revealed || this.closed || !IsObject(this.ui))
            return
        if (!this.ui.HasProp("wpfHwnd") || !this.ui.wpfHwnd)
            return
        this._revealed := true
        try this.ui.Update("Window", "Opacity", "1")
    }

    _ReleaseApplyingGuard(*) {
        this._applying := false
    }

    OnWindowLoad(state, ctrl, event) {
        if (!this._applying) {
        XamlWin.OnLoadTheme(this.ui)
        }
        this._RefreshList()
        this._TryReveal()
    }

    OnWindowClosing(state, ctrl, event) {
        this._revealed := true
        this.ui := ""
        this.closed := true
        if (AiHistoryGui.instances.Has("main"))
            AiHistoryGui.instances.Delete("main")
    }

    OnCloseClick(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }
}
