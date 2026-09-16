#Requires AutoHotkey v2.0

; 共享详情窗：展示单条分享的统计（点赞/回复/浏览）、最新版包信息（版本/适用游戏/按键提示/依赖/哈希）、
; 正文、版本历史与讨论（两者分列），并提供「下载导入」「去论坛讨论」入口。
; 版本历史：每发布一次新版本就往帖内追加一层（正文带 ```json 元数据块），本窗口据此把楼层分成
; 「版本层」与「讨论层」；「下载导入」取的是最新版本层的附件。
; 数据由 ShareCenterGui 在拿到 /t/{id}.json 后整理传入（ShowGui），本窗口不发网络请求。
class ShareDetailGui {
    static instances := Map()
    static _opening := false

    __New() {
        this.ui := 0
        this.closed := false
        this._btnStyle := ""
        this._owner := 0        ; ShareCenterGui 实例（下载入口回它）
        this._topic := 0        ; 列表里的 topic Map（含 id/title）
        this._info := 0         ; 帖子级信息（views/likes/replies/posts/solved/date/tags/baseUrl）
        this._meta := 0         ; 首楼 ```json 元数据（Map 或 ""）
        this._posts := []       ; 全部楼层 [{username,num,html,date}]
    }

    static ShowGui(owner, topic, info, meta, posts) {
        key := "global"
        if (ShareDetailGui.instances.Has(key)) {
            old := ShareDetailGui.instances[key]
            hwnd := (IsObject(old.ui) && old.ui.HasProp("wpfHwnd")) ? old.ui.wpfHwnd : 0
            ; 活着 → 换数据重渲染，不重建窗口
            if (!old.closed && IsObject(old.ui) && hwnd && XAMLHost.IsHwndResponsive(hwnd, 300)) {
                old._owner := owner
                old._topic := topic
                old._info := info
                old._meta := meta
                old._posts := posts
                try {
                    old._Render()
                    old._SetStatus("")
                }
                try old.ui.Update("Window", "Visibility", "Visible")
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!old.closed && IsObject(old.ui))
                    old.Close()
            }
            ShareDetailGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (ShareDetailGui._opening)
            return
        ShareDetailGui._opening := true
        try {
            inst := ShareDetailGui()
            inst._owner := owner
            inst._topic := topic
            inst._info := info
            inst._meta := meta
            inst._posts := posts
            inst._BuildAndShow()
            ShareDetailGui.instances[key] := inst
        } finally {
            ShareDetailGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("共享详情")
        titleHeight := "30"
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        root := body.Add("Grid").Margin("14, 8, 14, 10")
        root.Rows("*", "Auto", "Auto")

        scroll := root.Add("ScrollViewer").Grid_Row(0)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        scroll.Add("StackPanel").Name("DetailPanel").Margin("2, 2, 8, 6")

        root.Add("TextBlock").Name("StatusText").Grid_Row(1).Margin("2,6,2,0")
            .Text("").Foreground("{DynamicResource TextSub}").FontSize(12)
            .TextTrimming("CharacterEllipsis")

        btnRow := root.Add("StackPanel").Orientation("Horizontal").Grid_Row(2)
            .HorizontalAlignment("Center").Margin("0,8,0,2")
        this._AddBtn(btnRow, "DownloadBtn", GetLang("下载导入"), 100).Margin("0,0,10,0")
        this._AddBtn(btnRow, "ForumBtn", GetLang("去论坛讨论"), 110).Margin("0,0,10,0")
        this._AddBtn(btnRow, "CloseBtn", GetLang("关闭"), 80)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="True" Width="640" Height="600" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("CloseBtn", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("DownloadBtn", "Click", ObjBindMethod(this, "OnDownloadClick"))
        this.ui.OnEvent("ForumBtn", "Click", ObjBindMethod(this, "OnForumClick"))

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    _AddBtn(parent, name, content, width) {
        btn := parent.Add("Button").Name(name).Content(content)
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(12).Cursor("Hand").Width(width).Height(28)
        btn.InjectResources(this._btnStyle)
        return btn
    }

    OnWindowLoad(state := unset, ctrl := unset, event := unset) {
        this._Render()
        try {
            XamlWin.OnLoadTheme(this.ui)
        }
        try this.ui.Update("Window", "Opacity", "1")
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        ShareDetailGui._opening := false
        if (ShareDetailGui.instances.Has("global"))
            ShareDetailGui.instances.Delete("global")
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnCloseClick(state := unset, ctrl := unset, event := unset) {
        this.Close()
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    ; ===== 按钮 =====

    OnDownloadClick(state := unset, ctrl := unset, event := unset) {
        if (!IsObject(this._owner) || !IsObject(this._topic)) {
            this._SetStatus(GetLang("共享中心已关闭，请在列表中下载"))
            return
        }
        if (!this._owner.DownloadTopic(this._topic)) {
            this._SetStatus(GetLang("共享中心正忙，请稍候再试"))
            return
        }
        this._SetStatus(GetLang("已开始下载，进度见共享中心状态栏"))
    }

    OnForumClick(state := unset, ctrl := unset, event := unset) {
        info := this._info
        baseUrl := GetShareServerUrl()
        try {
            if (IsObject(info) && info.Has("baseUrl") && info["baseUrl"] != "")
                baseUrl := info["baseUrl"]
        }
        id := (IsObject(info) && info.Has("id")) ? info["id"] : 0
        slug := (IsObject(info) && info.Has("slug")) ? info["slug"] : ""
        if (id == 0) {
            this._SetStatus(GetLang("缺少帖子地址"))
            return
        }
        url := (slug != "") ? (baseUrl "/t/" slug "/" id) : (baseUrl "/t/" id)
        try {
            Run(url)
            this._SetStatus(GetLang("已在浏览器打开"))
        } catch as e {
            this._SetStatus(e.Message)
        }
    }

    ; ===== 渲染 =====

    _Render() {
        if (!IsObject(this.ui) || !IsObject(this._info))
            return
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        info := this._info

        x := '<StackPanel ' ns '>'
        x .= '<TextBlock Text="' this._X(info["title"]) '" Foreground="{DynamicResource TextMain}"'
            . ' FontSize="16" FontWeight="SemiBold" TextWrapping="Wrap"/>'

        top := []
        for t in info["tags"]
            top.Push("#" t)
        author := this._MetaStr("author")
        if (author != "")
            top.Push(author)
        if (info["date"] != "")
            top.Push(info["date"])
        if (top.Length > 0) {
            line := ""
            for i, v in top
                line .= (i > 1 ? " · " : "") v
            x .= '<TextBlock Text="' this._X(line) '" Foreground="{DynamicResource TextSub}" FontSize="12"'
                . ' Margin="0,4,0,0" TextWrapping="Wrap"/>'
        }

        stat := []
        stat.Push("👍 " (IsNumber(info["likes"]) ? info["likes"] : 0))
        stat.Push("💬 " this._TalkCount())   ; 只数讨论层，不含版本层
        stat.Push("👁 " (IsNumber(info["views"]) ? info["views"] : 0))
        if (info["solved"])
            stat.Push(GetLang("✔ 已解决"))
        line := ""
        for i, v in stat
            line .= (i > 1 ? " · " : "") v
        x .= '<TextBlock Text="' this._X(line) '" Foreground="{DynamicResource TextMain}" FontSize="12" Margin="0,6,0,0"/>'

        ; 本机已装状态：装过就报本机版本；与线上不一致则提示可更新
        if (info.Has("installed") && info["installed"]) {
            if (info.Has("hasUpdate") && info["hasUpdate"]) {
                localTxt := (info["localVer"] != "") ? ("v" info["localVer"]) : GetLang("旧版")
                onlineTxt := (info["onlineVer"] != "") ? ("v" info["onlineVer"]) : GetLang("新版")
                tip := Format(GetLang("⬆ 本机已装 {}，线上最新 {}，可点「更新」并入当前配置（会替换上一版并入的模块）"), localTxt, onlineTxt)
                x .= '<TextBlock Text="' this._X(tip) '" Foreground="{DynamicResource Accent}"'
                    . ' FontSize="12" FontWeight="SemiBold" Margin="0,6,0,0" TextWrapping="Wrap"/>'
            } else {
                localTxt := (info["localVer"] != "") ? ("v" info["localVer"]) : GetLang("未标版本")
                x .= '<TextBlock Text="' this._X(Format(GetLang("✔ 本机已装 {}，已是最新"), localTxt)) '"'
                    . ' Foreground="{DynamicResource TextSub}"'
                    . ' FontSize="12" Margin="0,6,0,0" TextWrapping="Wrap"/>'
            }
        }

        ; 交代一句落点：下载不等于新开一份配置，而是并进当前配置
        x .= '<TextBlock Text="' this._X(Format(GetLang("导入方式：并入当前配置《{}》，不新建配置、不需重启"), MySoftData.CurSettingName)) '"'
            . ' Foreground="{DynamicResource TextSub}" FontSize="11" Margin="0,6,0,0" TextWrapping="Wrap"/>'

        x .= this._SectionXaml(GetLang("包信息（最新版）"), this._MetaRows())
        x .= this._SectionXaml(GetLang("正文"), this._BodyXaml())
        ; 版本层与讨论层分开显示：版本层 = 正文里带 ```json 元数据块的楼层
        x .= this._SectionXaml(Format(GetLang("版本历史（{} 个）"), this._VersionCount()), this._VersionXaml())
        x .= this._SectionXaml(Format(GetLang("讨论（{} 条）"), this._TalkCount()), this._DiscussXaml())

        x .= '</StackPanel>'
        this.ui.Update("DetailPanel", "ClearItems", "")
        this.ui.Update("DetailPanel", "AddXamlItem", x)

        ; 按钮文案跟着「有没有新版本」走（窗口是复用的，不重置会留下上一次的文案）
        try this.ui.Update("DownloadBtn", "Content",
            (info.Has("hasUpdate") && info["hasUpdate"]) ? GetLang("更新") : GetLang("下载导入"))
    }

    _SectionXaml(title, contentXaml) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        return '<Border ' ns ' Margin="0,10,0,0" Padding="10,8" CornerRadius="6"'
            . ' Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . '<StackPanel>'
            . '<TextBlock Text="' this._X(title) '" Foreground="{DynamicResource TextMain}"'
            . ' FontSize="13" FontWeight="SemiBold" Margin="0,0,0,6"/>'
            . contentXaml
            . '</StackPanel></Border>'
    }

    _MetaRows() {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        if (!IsObject(this._meta))
            return '<TextBlock ' ns ' Text="' this._X(GetLang("该帖没有共享信息块（可能是手工发布的帖子）")) '"'
                . ' Foreground="{DynamicResource TextSub}" FontSize="12" TextWrapping="Wrap"/>'

        m := this._meta
        deps := ""
        try {
            if (m.Has("deps") && IsObject(m["deps"])) {
                for i, d in m["deps"]
                    deps .= (i > 1 ? "、" : "") String(d)
            }
        }

        rows := []
        rows.Push([GetLang("名称"), this._MetaStr("name")])
        rows.Push([GetLang("级别"), this._MetaStr("level")])
        rows.Push([GetLang("版本"), this._MetaStr("ver")])
        rows.Push([GetLang("适用游戏"), this._MetaStr("game")])
        rows.Push([GetLang("按键提示"), this._MetaStr("keytip")])
        rows.Push([GetLang("文件大小"), this._FmtSize(m.Has("size") ? m["size"] : 0)])
        if (deps != "")
            rows.Push([GetLang("依赖"), deps])
        rows.Push(["SHA256", this._MetaStr("sha256")])

        out := ""
        for r in rows {
            filled := (r[2] != "")
            v := filled ? r[2] : GetLang("未填写")
            col := filled ? "TextMain" : "TextSub"
            out .= '<TextBlock ' ns ' Text="' this._X(r[1] "：" v) '" Foreground="{DynamicResource ' col '}"'
                . ' FontSize="12" Margin="0,1,0,1" TextWrapping="Wrap"/>'
        }
        return out
    }

    _BodyXaml() {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        empty := '<TextBlock ' ns ' Text="' this._X(GetLang("（无正文）")) '" Foreground="{DynamicResource TextSub}" FontSize="12"/>'
        if (this._posts.Length == 0)
            return empty
        html := this._posts[1]["html"]
        ; 首楼的 ```json 元数据块已单列在「包信息」，正文里剥掉
        html := RegExReplace(html, "is)<pre[^>]*>\s*<code[^>]*>.*?</code></pre>", "")
        txt := this._HtmlToText(html)
        if (txt == "")
            return empty
        return '<TextBlock ' ns ' Text="' this._X(txt) '" Foreground="{DynamicResource TextMain}"'
            . ' FontSize="12" TextWrapping="Wrap" LineHeight="18"/>'
    }

    ; ===== 版本层 / 讨论层 =====

    ; 版本层判据：正文里带 ```json 元数据块（首楼是初版，也算一层版本）
    _IsVersionPost(p) {
        return (InStr(p["html"], "lang-json") > 0)
    }

    _VersionCount() {
        n := 0
        for p in this._posts {
            if (this._IsVersionPost(p))
                n++
        }
        return n
    }

    _TalkCount() {
        n := 0
        for i, p in this._posts {
            if (i > 1 && !this._IsVersionPost(p))
                n++
        }
        return n
    }

    _VersionXaml() {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        vers := []
        for p in this._posts {
            if (this._IsVersionPost(p))
                vers.Push(p)
        }
        if (vers.Length == 0)
            return '<TextBlock ' ns ' Text="' this._X(GetLang("没有版本记录")) '" Foreground="{DynamicResource TextSub}" FontSize="12"/>'

        out := ""
        last := vers.Length
        for i, p in vers {
            m := this._PostMeta(p)
            ver := "", size := ""
            if (IsObject(m)) {
                if (m.Has("ver"))
                    ver := Trim(String(m["ver"]))
                if (m.Has("size"))
                    size := this._FmtSize(m["size"])
            }
            line := "#" p["num"]
            if (ver != "")
                line .= " · v" ver
            line .= " · " p["date"]
            if (size != "")
                line .= " · " size
            if (i == last)
                line .= "  " GetLang("（最新）")
            col := (i == last) ? "TextMain" : "TextSub"
            out .= '<TextBlock ' ns ' Text="' this._X(line) '" Foreground="{DynamicResource ' col '}"'
                . ' FontSize="12" Margin="0,1,0,1" TextWrapping="Wrap"/>'
        }
        return out
    }

    _DiscussXaml() {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        out := ""
        n := 0
        for i, p in this._posts {
            if (i == 1 || this._IsVersionPost(p))
                continue
            n++
            head := "#" p["num"] " " p["username"] " · " p["date"]
            body := this._HtmlToText(p["html"])
            if (body == "")
                body := GetLang("（空）")
            out .= '<StackPanel ' ns ' Margin="0,0,0,8">'
                . '<TextBlock Text="' this._X(head) '" Foreground="{DynamicResource TextSub}" FontSize="11"/>'
                . '<TextBlock Text="' this._X(body) '" Foreground="{DynamicResource TextMain}"'
                . ' FontSize="12" TextWrapping="Wrap" LineHeight="17" Margin="0,2,0,0"/>'
                . '</StackPanel>'
        }
        if (n == 0)
            out := '<TextBlock ' ns ' Text="' this._X(GetLang("还没有人回复")) '" Foreground="{DynamicResource TextSub}" FontSize="12"/>'
        return out
    }

    ; 从某层 cooked 里取 ```json 元数据（拿版本号/大小用；取不到返回 0）
    _PostMeta(p) {
        if (RegExMatch(p["html"], "is)<pre[^>]*>\s*<code[^>]*>(.*?)</code></pre>", &m) = 0)
            return 0
        try {
            return JSON.parse(this._HtmlUnescape(m[1]))
        } catch {
            return 0
        }
    }

    _HtmlUnescape(s) {
        s := StrReplace(s, "&lt;", "<")
        s := StrReplace(s, "&gt;", ">")
        s := StrReplace(s, "&quot;", '"')
        s := StrReplace(s, "&#39;", "'")
        s := StrReplace(s, "&#x27;", "'")
        s := StrReplace(s, "&amp;", "&")
        return s
    }

    ; ===== 工具 =====

    _MetaStr(key) {
        if (!IsObject(this._meta) || !this._meta.Has(key))
            return ""
        v := this._meta[key]
        if (IsObject(v))
            return ""
        s := Trim(String(v))
        return s
    }

    _FmtSize(n) {
        if (!IsNumber(n) || n <= 0)
            return ""
        if (n >= 1048576)
            return Format("{:.1f} MB", n / 1048576)
        if (n >= 1024)
            return Format("{:.1f} KB", n / 1024)
        return n " B"
    }

    ; Discourse cooked HTML → 纯文本（保留段落换行）
    _HtmlToText(html) {
        s := String(html)
        s := RegExReplace(s, "is)<br\s*/?>", "`n")
        s := RegExReplace(s, "is)</(p|div|li|h[1-6])>", "`n")
        s := RegExReplace(s, "is)<[^>]*>", "")
        s := StrReplace(s, "&nbsp;", " ")
        s := StrReplace(s, "&lt;", "<")
        s := StrReplace(s, "&gt;", ">")
        s := StrReplace(s, "&quot;", '"')
        s := StrReplace(s, "&#39;", "'")
        s := StrReplace(s, "&#x27;", "'")
        s := StrReplace(s, "&amp;", "&")
        s := RegExReplace(s, "[ \t]+", " ")
        s := RegExReplace(s, "(\r?\n)\s*(\r?\n)+", "`n")
        s := RegExReplace(s, "[ \t]*\r?\n[ \t]*", "`n")
        return Trim(s)
    }

    _SetStatus(text) {
        if IsObject(this.ui)
            try this.ui.Update("StatusText", "Text", text)
    }

    _X(s) {
        s := String(s)
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }
}
