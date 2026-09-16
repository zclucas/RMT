#Requires AutoHotkey v2.0

class ShareCenterGui {
    static instances := Map()
    static _opening := false
    static _index := []            ; 全量索引：所有共享 topic（Map(id/title/tags/author/likes/replies/posts/solved/date/blurb)）
    static _indexStamp := ""       ; 索引建立时刻（yyyyMMddHHmmss，本地时间）
    static INDEX_TTL := 7200       ; 索引有效期（秒，2 小时）
    static CACHE_FILE := A_WorkingDir "\Cache\ShareIndex.json"  ; 索引落盘缓存
    static INSTALLED_FILE := A_WorkingDir "\Cache\ShareInstalled.json"  ; 已装记录：topic_id → 导入时的版本快照
    static _installed := Map()     ; 已装记录（惰性加载）
    static _installedLoaded := false
    static PAGE_SIZE := 50         ; 本地分页大小

    __New() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._btnStyle := ""
        this._applyingUI := false
        this._page := 1
        this._hasNext := false
        this._topics := []              ; 当前页 topic（索引过滤后的切片）
        this._view := []                ; 过滤+排序后的完整视图
        this._levels := []
        this._sorts := []
        this._pending := ""             ; "" | index | detail | download
        this._pendingSince := 0         ; 请求发起时刻（看门狗用）
        this._indexPage := 0            ; 索引抓取进度：当前页
        this._detailTopic := ""         ; 详情/下载的目标 topic
        this._detailMode := ""          ; detail 请求的去向：info=详情窗 / download=下载导入
        this._detailMeta := 0           ; 本次拿到的「最新版」meta（导入成功后据此写已装记录）
        this._detailPosts := 0          ; 本次拿到的楼层数（已装记录的基线）
        this._downloadPath := ""
        this._pollFn := 0
    }

    ShowGui() {
        ShareCenterGui.ShowGui()
    }

    static ShowGui() {
        key := "global"
        if (ShareCenterGui.instances.Has(key)) {
            oldInst := ShareCenterGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            ; 窗口活着（含隐藏态）→ 显示并激活，不重建（避免闪烁）
            if (!oldInst.closed && IsObject(oldInst.ui)
                    && hwnd && XAMLHost.IsHwndResponsive(hwnd, 300)) {
                try oldInst.ui.Update("Window", "Visibility", "Visible")
                try WinActivate("ahk_id " hwnd)
                ; 索引未加载过才加载（优先本地文件缓存，过期也不自动拉）
                if (ShareCenterGui._index.Length == 0)
                    oldInst.LoadPage(1)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            ShareCenterGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (ShareCenterGui._opening)
            return
        ShareCenterGui._opening := true
        try {
            inst := ShareCenterGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            ShareCenterGui.instances[key] := inst
        } finally {
            ShareCenterGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("共享中心")
        titleHeight := "30"
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        this._levels := [GetLang("全部"), GetLang("宏"), GetLang("模块"), GetLang("配置")]
        this._sorts := [GetLang("最新"), GetLang("最多点赞"), GetLang("最多回复")]

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        root := body.Add("Grid").Margin("14, 8, 14, 10")
        root.Rows("Auto", "*", "Auto", "Auto")

        ; 筛选行：级别下拉 + 排序下拉 + 搜索框 + 搜索按钮
        filterRow := root.Add("Grid").Grid_Row(0).Margin("0,2,0,8")
        filterRow.Cols("Auto", "Auto", "Auto", "Auto", "*", "Auto", "Auto", "Auto")
        filterRow.Add("TextBlock").Text(GetLang("级别："))
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Grid_Column(0)
        filterRow.Add("ComboBox").Name("LevelDDL").Width(80).Height(26).MinHeight(26)
            .Grid_Column(1).HorizontalAlignment("Left").Margin("4,0,10,0")
        filterRow.Add("ComboBox").Name("SortDDL").Width(80).Height(26).MinHeight(26)
            .Grid_Column(2).HorizontalAlignment("Left").Margin("0,0,10,0")
        filterRow.Add("TextBox").Name("SearchInput").Height(26)
            .Grid_Column(4).Margin("4,0,10,0").VerticalContentAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        this._AddBtn(filterRow, "SearchBtn", GetLang("搜索"), 64)
            .Grid_Column(5).VerticalAlignment("Center")
        this._AddBtn(filterRow, "UpdateBtn", GetLang("刷新"), 48)
            .Grid_Column(6).VerticalAlignment("Center")
        this._AddBtn(filterRow, "UploadBtn", GetLang("上传"), 48)
            .Grid_Column(7).VerticalAlignment("Center")

        ; 列表区（卡片）
        scroll := root.Add("ScrollViewer").Grid_Row(1)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        scroll.Add("StackPanel").Name("ShareListPanel").Margin("4, 4, 4, 4")

        ; 状态行
        root.Add("TextBlock").Name("StatusText").Grid_Row(2).Margin("2,6,2,0")
            .Text("").Foreground("{DynamicResource TextSub}").FontSize(12)
            .TextTrimming("CharacterEllipsis")

        ; 底部分页
        btnRow := root.Add("StackPanel").Orientation("Horizontal").Grid_Row(3)
            .HorizontalAlignment("Center").Margin("0,8,0,2")
        this._AddBtn(btnRow, "PrevBtn", GetLang("上一页"), 70).Margin("0,0,10,0")
        btnRow.Add("TextBlock").Name("PageText").Text("1")
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Margin("0,0,10,0")
        this._AddBtn(btnRow, "NextBtn", GetLang("下一页"), 70)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="True" Width="620" Height="560" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        groupBoxStyle := '<Style TargetType="GroupBox"><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/></Style>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>' groupBoxStyle)

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("SearchBtn", "Click", ObjBindMethod(this, "OnSearchClick"))
        this.ui.OnEvent("UpdateBtn", "Click", ObjBindMethod(this, "OnUpdateClick"))
        this.ui.OnEvent("UploadBtn", "Click", ObjBindMethod(this, "OnUploadClick"))
        this.ui.OnEvent("PrevBtn", "Click", ObjBindMethod(this, "OnPrevClick"))
        this.ui.OnEvent("NextBtn", "Click", ObjBindMethod(this, "OnNextClick"))
        this.ui.Track("LevelDDL")
        this.ui.Track("SortDDL")
        this.ui.OnEvent("LevelDDL", "SelectionChanged", ObjBindMethod(this, "OnFilterChange"))
        this.ui.OnEvent("SortDDL", "SelectionChanged", ObjBindMethod(this, "OnFilterChange"))

        this.RefreshDDLs()
        this._pollFn := ObjBindMethod(this, "_Poll")
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

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        this._StopPoll()
        ShareCenterGui._opening := false
        if (this._instanceKey != "" && ShareCenterGui.instances.Has(this._instanceKey))
            ShareCenterGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            XamlWin.OnLoadTheme(this.ui)
            this.LoadPage(1)
        } finally {
            this.ui.Update("Window", "Opacity", "1")
        }
    }

    OnCancelClick(state := unset, ctrl := unset, event := unset) {
        ; 关闭=隐藏窗口（保留实例与列表），重开秒显不闪烁
        if IsObject(this.ui)
            try this.ui.Update("Window", "Visibility", "Hidden")
    }

    Close() {
        this.closed := true
        this._StopPoll()
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    OnClose() {
        this.Close()
    }

    RefreshDDLs() {
        if (!IsObject(this.ui))
            return
        this._applyingUI := true
        try {
            ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
            this.ui.Update("LevelDDL", "ClearItems", "")
            for name in this._levels {
                this.ui.Update("LevelDDL", "AddXamlItem",
                    '<ComboBoxItem ' ns ' Content="' this._XmlEsc(name) '"/>')
            }
            this.ui.Update("LevelDDL", "SelectedIndex", "0")

            this.ui.Update("SortDDL", "ClearItems", "")
            for name in this._sorts {
                this.ui.Update("SortDDL", "AddXamlItem",
                    '<ComboBoxItem ' ns ' Content="' this._XmlEsc(name) '"/>')
            }
            this.ui.Update("SortDDL", "SelectedIndex", "0")
        } finally {
            this._applyingUI := false
        }
    }

    ; ===== 数据加载（全量本地索引） =====

    GetSelectedLevel() {
        idx := this.ui.Query("LevelDDL>SelectedIndex")
        if (IsNumber(idx) && Integer(idx) >= 0 && Integer(idx) + 1 <= this._levels.Length)
            return this._levels[Integer(idx) + 1]
        return this._levels[1]
    }

    GetSelectedSort() {
        idx := this.ui.Query("SortDDL>SelectedIndex")
        if (IsNumber(idx) && Integer(idx) == 1)
            return "likes"
        if (IsNumber(idx) && Integer(idx) == 2)
            return "replies"
        return "latest"
    }

    OnFilterChange(state := unset, ctrl := unset, event := unset) {
        if (this._applyingUI)
            return
        ; 本地过滤，不请求网络
        this._ApplyFilterAndRender(1)
    }

    ; 搜索按钮 = 本地搜索当前索引；索引过期会自动重建
    OnSearchClick(state := unset, ctrl := unset, event := unset) {
        this.LoadPage(1)
    }

    ; 刷新按钮 = 手动重建索引（拉取最新数据并更新本地缓存）
    OnUpdateClick(state := unset, ctrl := unset, event := unset) {
        ShareCenterGui._index := []
        ShareCenterGui._indexStamp := ""
        this.LoadPage(1, true)
    }

    ; 上传按钮 = 打开上传分享窗口（配置级：手动选 .rmt 包）
    OnUploadClick(state := unset, ctrl := unset, event := unset) {
        ShareUploadGui.ShowGui("", "", GetLang("配置"))
    }

    OnPrevClick(state := unset, ctrl := unset, event := unset) {
        if (this._page > 1)
            this._ApplyFilterAndRender(this._page - 1)
    }

    OnNextClick(state := unset, ctrl := unset, event := unset) {
        if (this._hasNext)
            this._ApplyFilterAndRender(this._page + 1)
    }

    LoadPage(page, force := false) {
        global RMT_Discourse
        if (!IsObject(this.ui))
            return
        this._page := page

        if (force)
            return this._BeginIndexFetch()

        ; 内存索引新鲜 → 纯本地渲染
        if (this._IndexFresh()) {
            this._ApplyFilterAndRender(page)
            return
        }

        ; 内存没有 → 读文件缓存（过期也先用，不自动拉）
        if (ShareCenterGui._index.Length == 0)
            this._LoadIndexFromFile()

        if (ShareCenterGui._index.Length > 0) {
            this._ApplyFilterAndRender(page)
            if (!this._IndexFresh())
                this._SetStatus(GetLang("缓存已过期，点「刷新」获取最新数据"))
            return
        }

        ; 完全没有缓存（首次使用）→ 才发网络请求
        this._BeginIndexFetch()
    }

    _BeginIndexFetch() {
        global RMT_Discourse
        if (!IsObject(this.ui))
            return
        if (this._pending != "")
            return
        try disc := GetDiscourse()
        catch as e {
            this._SetStatus(e.Message)
            return
        }
        ShareCenterGui._index := []
        this._indexPage := 1
        this._pending := "index"
        this._pendingSince := A_TickCount
        this._SetStatus(GetLang("正在获取索引..."))
        url := this._BuildIndexUrl(this._indexPage)
        try RMT_Discourse.BeginGetText(url)
        catch as e {
            this._pending := ""
            this._SetStatus(e.Message)
            return
        }
        this._StartPoll()
    }

    _IndexFresh() {
        return ShareCenterGui._index.Length > 0
            && ShareCenterGui._indexStamp != ""
            && DateDiff(A_Now, ShareCenterGui._indexStamp, "Seconds") <= ShareCenterGui.INDEX_TTL
    }

    _LoadIndexFromFile() {
        path := ShareCenterGui.CACHE_FILE
        if (!FileExist(path))
            return false
        try {
            obj := JSON.parse(FileRead(path, "UTF-8"))
            if (!IsObject(obj) || !obj.Has("topics") || !IsObject(obj["topics"]))
                return false
            topics := []
            for t in obj["topics"] {
                topic := Map()
                topic["id"] := t.Has("id") ? t["id"] : 0
                topic["title"] := t.Has("title") ? t["title"] : ""
                tags := []
                if (t.Has("tags") && IsObject(t["tags"]))
                    for tag in t["tags"]
                        tags.Push(tag)
                topic["tags"] := tags
                topic["likes"] := t.Has("likes") ? t["likes"] : 0
                topic["replies"] := t.Has("replies") ? t["replies"] : 0
                topic["posts"] := t.Has("posts") ? t["posts"] : 0
                topic["solved"] := (t.Has("solved") && t["solved"] = true)
                topic["date"] := t.Has("date") ? t["date"] : ""
                topic["author"] := t.Has("author") ? t["author"] : ""
                topic["blurb"] := t.Has("blurb") ? t["blurb"] : ""
                topics.Push(topic)
            }
            ShareCenterGui._index := topics
            ShareCenterGui._indexStamp := obj.Has("time") ? String(obj["time"]) : ""
            return true
        } catch {
            return false
        }
    }

    _SaveIndexToFile() {
        path := ShareCenterGui.CACHE_FILE
        try {
            SplitPath path, , &dir
            if (!DirExist(dir))
                DirCreate(dir)
            parts := ""
            for topic in ShareCenterGui._index {
                tagsJson := ""
                for i, tag in topic["tags"]
                    tagsJson .= (i > 1 ? "," : "") '"' ShareCenterGui._JsonEsc(tag) '"'
                parts .= (A_Index > 1 ? "," : "") '{"id":' topic["id"] ','
                    . '"title":"' ShareCenterGui._JsonEsc(topic["title"]) '","tags":[' tagsJson '],'
                    . '"likes":' topic["likes"] ',"replies":' this._Num(topic, "replies")
                    . ',"posts":' this._Num(topic, "posts")
                    . ',"solved":' (topic.Has("solved") && topic["solved"] ? "true" : "false") ','
                    . '"date":"' ShareCenterGui._JsonEsc(topic["date"]) '",'
                    . '"author":"' ShareCenterGui._JsonEsc(topic["author"]) '","blurb":"' ShareCenterGui._JsonEsc(topic["blurb"]) '"}'
            }
            json := '{"time":"' ShareCenterGui._indexStamp '","topics":[' parts ']}'
            f := FileOpen(path, "w", "UTF-8")
            f.Write(json)
            f.Close()
        } catch {
            ; 缓存写失败不影响功能
        }
    }

    ; JSON 字符串转义（静态：索引缓存与已装记录两处落盘都用它）
    static _JsonEsc(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`t", "\t")
        return s
    }

    ; 取数值字段（缺键/非数字 → 0）。旧版缓存文件没有新字段，靠这里兜底
    _Num(map, key) {
        if (!map.Has(key))
            return 0
        v := map[key]
        return IsNumber(v) ? Integer(v) : 0
    }

    _BuildIndexUrl(page) {
        baseUrl := GetShareServerUrl()
        q := "category:shared order:latest"
        return baseUrl "/search.json?page=" page "&q=" this._UriEncode(q)
    }

    ; 过滤 + 排序 + 本地分页 → 渲染
    _ApplyFilterAndRender(page) {
        if (ShareCenterGui._index.Length == 0) {
            this.LoadPage(page)
            return
        }
        this._page := page

        query := ""
        try query := Trim(String(this.ui.Query("SearchInput>Text")))
        level := this.GetSelectedLevel()
        order := this.GetSelectedSort()

        view := []
        for topic in ShareCenterGui._index {
            ; 无标签 = 非共享帖（分类描述帖等），跳过
            if (topic["tags"].Length == 0)
                continue
            if (level != this._levels[1]) {
                matched := false
                for tag in topic["tags"] {
                    if (tag == level) {
                        matched := true
                        break
                    }
                }
                if (!matched)
                    continue
            }
            if (query != "") {
                hay := topic["title"] " " topic["blurb"] " " topic["author"]
                if (!InStr(hay, query))
                    continue
            }
            ; 已装 / 有新版本（粗筛：线上楼层数比导入时多）
            this._MarkInstalled(topic)
            view.Push(topic)
        }

        if (order == "likes")
            view := this._SortByNum(view, "likes")
        else if (order == "replies")
            view := this._SortByNum(view, "replies")

        this._view := view
        start := (page - 1) * ShareCenterGui.PAGE_SIZE + 1
        end := page * ShareCenterGui.PAGE_SIZE
        this._topics := []
        i := 0
        for topic in view {
            i++
            if (i >= start && i <= end)
                this._topics.Push(topic)
        }
        this._hasNext := view.Length > end

        this._RenderRows()
        this.ui.Update("PageText", "Text", this._page "")
        this._SetStatus(Format(GetLang("共{}条"), view.Length))
    }

    ; 按数值字段降序（简单插入排序；量级几十~几千，够用且稳定）
    _SortByNum(view, field) {
        arr := view.Clone()
        n := arr.Length
        loop n - 1 {
            j := A_Index
            while (j > 0 && this._Num(arr[j], field) < this._Num(arr[j + 1], field)) {
                tmp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := tmp
                j--
            }
        }
        return arr
    }

    ; 解析 search.json 一页：返回 topic Map 数组（按 posts 顺序，已按 topic_id 去重）
    _ParseIndexPage(body) {
        obj := JSON.parse(body)
        if (!IsObject(obj))
            throw Error(GetLang("列表数据解析失败"))

        topicsMap := Map()
        if (obj.Has("topics") && IsObject(obj["topics"])) {
            for t in obj["topics"] {
                try {
                    if (t.Has("id"))
                        topicsMap[t["id"]] := t
                }
            }
        }

        result := []
        seen := Map()
        if (obj.Has("posts") && IsObject(obj["posts"])) {
            for p in obj["posts"] {
                try {
                    tid := p["topic_id"]
                    if (seen.Has(tid) || !topicsMap.Has(tid))
                        continue
                    seen[tid] := true
                    t := topicsMap[tid]
                    ; 跳过无标签的帖子（如分类描述帖，不是共享内容）
                    if (!t.Has("tags") || !IsObject(t["tags"]) || t["tags"].Length == 0)
                        continue
                    topic := Map()
                    topic["id"] := tid
                    topic["title"] := t.Has("title") ? t["title"] : ""
                    tags := []
                    try {
                        if (t.Has("tags") && IsObject(t["tags"])) {
                            for tag in t["tags"] {
                                ; Discourse 某些版本 tags 是 [{id,name,slug}] 对象数组，取 name
                                if (IsObject(tag)) {
                                    try tags.Push(tag["name"])
                                } else
                                    tags.Push(tag)
                            }
                        }
                    }
                    topic["tags"] := tags
                    topic["likes"] := p.Has("like_count") ? p["like_count"] : 0
                    ; 统计三件套：点赞(post 级)、回复数、帖子数；已解决来自 discourse-solved
                    topic["replies"] := t.Has("reply_count") ? t["reply_count"] : 0
                    topic["posts"] := t.Has("posts_count") ? t["posts_count"] : 0
                    topic["solved"] := t.Has("has_accepted_answer") ? t["has_accepted_answer"] : false
                    topic["date"] := t.Has("created_at") ? SubStr(t["created_at"], 1, 10) : ""
                    topic["blurb"] := p.Has("blurb") ? p["blurb"] : ""
                    ; 摘要压成单行文本，避免换行进 XAML 属性
                    topic["blurb"] := Trim(StrReplace(StrReplace(topic["blurb"], "`r", " "), "`n", " "))
                    ; 作者从正文提取（发帖人可能是代发/管理员，不是真实作者），取不到就留空
                    author := ""
                    try {
                        if (RegExMatch(topic["blurb"], "作者\s*[：:]\s*(.*?)(?:[｜|]|适用|$)", &am) > 0)
                            author := Trim(am[1])
                    }
                    topic["author"] := author
                    result.Push(topic)
                }
            }
        }
        return result
    }

    _RenderRows() {
        ; 清理旧动态事件
        toDel := []
        for key, _ in this.ui.events {
            if (InStr(key, "ShareDl_") == 1 || InStr(key, "ShareInfo_") == 1)
                toDel.Push(key)
        }
        for key in toDel
            this.ui.events.Delete(key)

        this.ui.Update("ShareListPanel", "ClearItems", "")
        if (this._topics.Length == 0) {
            ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
            this.ui.Update("ShareListPanel", "AddXamlItem",
                '<TextBlock ' ns ' Text="' this._XmlEsc(GetLang("暂无共享内容")) '"'
                . ' Foreground="{DynamicResource TextSub}" FontSize="13"'
                . ' HorizontalAlignment="Center" Margin="0,16,0,16"/>')
            return
        }

        ; 整页卡片拼成单个 XAML，一次注入（逐条注入会卡）
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        allXaml := '<StackPanel ' ns '>'
        for i, topic in this._topics
            allXaml .= this._BuildCardXaml(i, topic)
        allXaml .= '</StackPanel>'
        this.ui.Update("ShareListPanel", "AddXamlItem", allXaml)
        for i, topic in this._topics {
            btnName := "ShareDl_" i
            infoName := "ShareInfo_" i
            this.ui.OnEvent(btnName, "Click", ObjBindMethod(this, "OnRowDownload", i))
            this.ui.Update(btnName, "BindEvent", "Click")
            this.ui.OnEvent(infoName, "Click", ObjBindMethod(this, "OnRowDetail", i))
            this.ui.Update(infoName, "BindEvent", "Click")
        }
    }

    _BuildCardXaml(i, topic) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        btnName := "ShareDl_" i
        infoName := "ShareInfo_" i

        metaParts := []
        for tag in topic["tags"]
            metaParts.Push("#" tag)
        if (topic["author"] != "")
            metaParts.Push(topic["author"])
        if (topic["likes"] > 0)
            metaParts.Push("👍" topic["likes"])
        if (this._Num(topic, "replies") > 0)
            metaParts.Push("💬" this._Num(topic, "replies"))
        if (topic.Has("solved") && topic["solved"])
            metaParts.Push(GetLang("✔已解决"))
        ; 已装过的包标一下本机版本（没填版本号就只标「已装」）；有新版本则不在这里标（另有强调行）
        if (topic.Has("installed") && topic["installed"]
                && !(topic.Has("hasUpdate") && topic["hasUpdate"]))
            metaParts.Push((topic["localVer"] != "") ? (GetLang("已装 v") topic["localVer"]) : GetLang("已装"))
        if (topic["date"] != "")
            metaParts.Push(topic["date"])
        meta := ""
        for j, part in metaParts
            meta .= (j > 1 ? " · " : "") part

        ; 图标取标题首字符
        iconChar := topic["title"] != "" ? SubStr(topic["title"], 1, 1) : "R"

        xaml := '<Border ' ns ' Margin="0,0,0,8" CornerRadius="8" Padding="0"'
            . ' Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1">'
            . '<Grid Margin="10,8,10,8">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="Auto"/>'
            . '<ColumnDefinition Width="*"/>'
            . '<ColumnDefinition Width="Auto"/>'
            . '</Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Width="40" Height="40" CornerRadius="20"'
            . ' Background="{DynamicResource TitleBarColor}" VerticalAlignment="Center">'
            . '<TextBlock Text="' this._XmlEsc(iconChar) '" FontSize="17"'
            . ' Foreground="{DynamicResource TitleBarForeground}"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<StackPanel Grid.Column="1" Margin="10,0,8,0" VerticalAlignment="Center">'
            . '<TextBlock Text="' this._XmlEsc(topic["title"]) '"'
            . ' Foreground="{DynamicResource TextMain}" FontSize="13" FontWeight="SemiBold"'
            . ' TextTrimming="CharacterEllipsis"/>'
            . '<TextBlock Text="' this._XmlEsc(topic["blurb"]) '"'
            . ' Foreground="{DynamicResource TextSub}" FontSize="11" Margin="0,2,0,0"'
            . ' TextWrapping="Wrap" MaxHeight="30" LineHeight="15"'
            . ' TextTrimming="CharacterEllipsis"/>'
            . '<TextBlock Text="' this._XmlEsc(meta) '"'
            . ' Foreground="{DynamicResource TextSub}" FontSize="11" Margin="0,3,0,0"'
            . ' TextTrimming="CharacterEllipsis"/>'
            . ((topic.Has("hasUpdate") && topic["hasUpdate"])
                ? ('<TextBlock Text="' this._XmlEsc(GetLang("⬆ 有新版本，点「详情」看版本")) '"'
                    . ' Foreground="{DynamicResource Accent}" FontSize="11" FontWeight="SemiBold"'
                    . ' Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>')
                : "")
            . '</StackPanel>'
            . '<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Name="' infoName '" Content="' GetLang("详情") '"'
            . ' Width="52" Height="24" Cursor="Hand" FontSize="12"'
            . ' Background="{DynamicResource EditBg}" Foreground="{DynamicResource EditText}"'
            . ' BorderBrush="{DynamicResource EditStroke}" BorderThickness="1"/>'
            . '<Button Name="' btnName '" Content="' GetLang("下载") '"'
            . ' Width="52" Height="24" Margin="8,0,0,0" Cursor="Hand" FontSize="12"'
            . ' Background="{DynamicResource EditBg}" Foreground="{DynamicResource EditText}"'
            . ' BorderBrush="{DynamicResource EditStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
            . '</Grid>'
            . '</Border>'
        return xaml
    }

    ; ===== 已装记录 / 更新检测 =====
    ; 导入成功时记下「这帖我装的是哪一版」（ver + sha256）和当时的楼层数；
    ; 之后刷新索引即可标出「有新版本」，点开详情再做精确比对。全程只写本地文件，不碰论坛。

    static InstalledGet(topicId) {
        ShareCenterGui._InstalledLoad()
        key := String(topicId)
        return ShareCenterGui._installed.Has(key) ? ShareCenterGui._installed[key] : 0
    }

    ; meta = 线上那一层的 ```json 元数据；posts = 导入当时的楼层数（粗筛基线）
    static InstalledPut(topicId, meta, posts, settingName) {
        if (topicId == "")
            return
        ShareCenterGui._InstalledLoad()
        rec := Map()
        rec["name"] := ""
        rec["ver"] := ""
        rec["sha256"] := ""
        if (IsObject(meta)) {
            try {
                rec["name"] := meta.Has("name") ? Trim(String(meta["name"])) : ""
                rec["ver"] := meta.Has("ver") ? Trim(String(meta["ver"])) : ""
                rec["sha256"] := meta.Has("sha256") ? Trim(String(meta["sha256"])) : ""
            }
        }
        rec["posts"] := IsNumber(posts) ? Integer(posts) : 0
        rec["setting"] := settingName
        rec["time"] := A_Now
        ShareCenterGui._installed[String(topicId)] := rec
        ShareCenterGui._InstalledSave()
    }

    ; 详情窗确认「已是最新」后把楼层基线刷成线上值 —— 否则别人回帖也会一直被算成「有新版本」
    static InstalledRefreshBaseline(topicId, posts) {
        ShareCenterGui._InstalledLoad()
        key := String(topicId)
        if (!ShareCenterGui._installed.Has(key))
            return
        ShareCenterGui._installed[key]["posts"] := IsNumber(posts) ? Integer(posts) : 0
        ShareCenterGui._InstalledSave()
    }

    static _InstalledLoad() {
        if (ShareCenterGui._installedLoaded)
            return
        ShareCenterGui._installedLoaded := true
        path := ShareCenterGui.INSTALLED_FILE
        if (!FileExist(path))
            return
        try {
            obj := JSON.parse(FileRead(path, "UTF-8"))
            if (!IsObject(obj) || !obj.Has("items") || !IsObject(obj["items"]))
                return
            for tid, r in obj["items"] {
                m := Map()
                m["name"] := r.Has("name") ? String(r["name"]) : ""
                m["ver"] := r.Has("ver") ? String(r["ver"]) : ""
                m["sha256"] := r.Has("sha256") ? String(r["sha256"]) : ""
                m["posts"] := (r.Has("posts") && IsNumber(r["posts"])) ? Integer(r["posts"]) : 0
                m["setting"] := r.Has("setting") ? String(r["setting"]) : ""
                m["time"] := r.Has("time") ? String(r["time"]) : ""
                ShareCenterGui._installed[String(tid)] := m
            }
        } catch {
            ; 记录文件损坏：当成没装过，不影响其它功能
        }
    }

    static _InstalledSave() {
        path := ShareCenterGui.INSTALLED_FILE
        try {
            SplitPath path, , &dir
            if (!DirExist(dir))
                DirCreate(dir)
            parts := ""
            for tid, r in ShareCenterGui._installed {
                parts .= (parts != "" ? "," : "")
                    . '"' ShareCenterGui._JsonEsc(tid) '":{"name":"' ShareCenterGui._JsonEsc(r["name"]) '"'
                    . ',"ver":"' ShareCenterGui._JsonEsc(r["ver"]) '"'
                    . ',"sha256":"' ShareCenterGui._JsonEsc(r["sha256"]) '"'
                    . ',"posts":' r["posts"]
                    . ',"setting":"' ShareCenterGui._JsonEsc(r["setting"]) '"'
                    . ',"time":"' ShareCenterGui._JsonEsc(r["time"]) '"}'
            }
            f := FileOpen(path, "w", "UTF-8")
            f.Write('{"v":1,"items":{' parts '}}')
            f.Close()
        } catch {
            ; 写失败不影响功能
        }
    }

    ; 给列表里的 topic 补两个只用于展示的字段：localVer（本机装的版本）/ hasUpdate（线上楼层数涨了）
    ; 粗筛：讨论回复也会让楼层数涨 —— 点开详情会做 sha256 精确比对并顺手刷新基线
    _MarkInstalled(topic) {
        topic["installed"] := false
        topic["localVer"] := ""
        topic["hasUpdate"] := false
        rec := ShareCenterGui.InstalledGet(topic["id"])
        if (!IsObject(rec))
            return
        topic["installed"] := true
        topic["localVer"] := rec["ver"]
        topic["hasUpdate"] := (this._Num(topic, "posts") > this._Num(rec, "posts"))
    }

    ; 详情级精确比对：sha256 不同 = 有新包；任一方没 sha256 就退化成比版本号
    _FillUpdateState(info, meta, obj) {
        info["installed"] := false
        info["localVer"] := ""
        info["localSha"] := ""
        info["onlineVer"] := ""
        info["hasUpdate"] := false

        onlineSha := ""
        if (IsObject(meta)) {
            try {
                onlineSha := meta.Has("sha256") ? Trim(String(meta["sha256"])) : ""
                info["onlineVer"] := meta.Has("ver") ? Trim(String(meta["ver"])) : ""
            }
        }

        rec := ShareCenterGui.InstalledGet(info["id"])
        if (!IsObject(rec))
            return
        info["installed"] := true
        info["localVer"] := rec["ver"]
        info["localSha"] := rec["sha256"]

        if (rec["sha256"] != "" && onlineSha != "")
            info["hasUpdate"] := (rec["sha256"] != onlineSha)
        else
            info["hasUpdate"] := (rec["ver"] != info["onlineVer"])

        if (!info["hasUpdate"]) {
            posts := obj.Has("posts_count") ? obj["posts_count"] : 0
            if (posts > this._Num(rec, "posts"))
                ShareCenterGui.InstalledRefreshBaseline(info["id"], posts)
        }
    }

    ; 导入成功后写已装记录（ver/sha256 取线上那一层的 meta，posts 记当时楼层数作基线）
    _RecordInstalled(settingName) {
        topic := this._detailTopic
        if (!IsObject(topic))
            return
        tid := topic.Has("id") ? topic["id"] : 0
        if (tid == 0)
            return
        ShareCenterGui.InstalledPut(tid, this._detailMeta, this._detailPosts, settingName)
    }

    ; ===== 下载导入 =====

    OnRowDownload(index, state := unset, ctrl := unset, event := unset) {
        if (index < 1 || index > this._topics.Length)
            return
        this._BeginTopicFetchByTopic(this._topics[index], "download")
    }

    ; 详情：与下载共用同一个 /t/{id}.json 请求，只是拿到后打开详情窗
    OnRowDetail(index, state := unset, ctrl := unset, event := unset) {
        if (index < 1 || index > this._topics.Length)
            return
        this._BeginTopicFetchByTopic(this._topics[index], "info")
    }

    ; 详情窗里的「下载导入」回调（topic 可能不在当前页，所以按对象走）
    DownloadTopic(topic) {
        if (this.closed || !IsObject(this.ui))
            return false
        if (this._pending != "") {
            this._SetStatus(GetLang("有任务进行中，请稍候"))
            return false
        }
        this._BeginTopicFetchByTopic(topic, "download")
        return true
    }

    _BeginTopicFetchByTopic(topic, mode) {
        global RMT_Discourse
        if (!IsObject(topic))
            return
        if (this._pending != "") {
            this._SetStatus(GetLang("有任务进行中，请稍候"))
            return
        }
        try disc := GetDiscourse()
        catch as e {
            this._SetStatus(e.Message)
            return
        }

        baseUrl := GetShareServerUrl()
        url := baseUrl "/t/" topic["id"] ".json"
        this._detailTopic := topic
        this._detailMode := mode
        this._detailMeta := 0
        this._detailPosts := 0
        this._pending := "detail"
        this._SetStatus(Format("{} #{}", GetLang("正在获取详情"), topic["id"]))
        try RMT_Discourse.BeginGetText(url)
        catch as e {
            this._pending := ""
            this._SetStatus(e.Message)
            return
        }
        this._StartPoll()
    }

    ; 详情窗数据整理：把 /t/{id}.json 拆成「帖子统计 + 最新版 meta + 全部楼层」，交给 ShareDetailGui
    _ShowDetail(obj) {
        posts := []
        try {
            for p in obj["post_stream"]["posts"] {
                item := Map()
                item["username"] := p.Has("username") ? p["username"] : ""
                item["num"] := p.Has("post_number") ? p["post_number"] : 0
                item["html"] := p.Has("cooked") ? p["cooked"] : ""
                item["date"] := p.Has("created_at") ? SubStr(p["created_at"], 1, 10) : ""
                posts.Push(item)
            }
        }

        meta := ""
        try meta := this._LatestMeta(obj)

        info := Map()
        info["id"] := obj.Has("id") ? obj["id"] : 0
        info["title"] := obj.Has("title") ? obj["title"] : ""
        info["slug"] := obj.Has("slug") ? obj["slug"] : ""
        info["views"] := obj.Has("views") ? obj["views"] : 0
        info["likes"] := obj.Has("like_count") ? obj["like_count"] : 0
        info["replies"] := obj.Has("reply_count") ? obj["reply_count"] : 0
        info["posts"] := obj.Has("posts_count") ? obj["posts_count"] : 0
        info["solved"] := obj.Has("has_accepted_answer") ? obj["has_accepted_answer"] : false
        info["date"] := obj.Has("created_at") ? SubStr(obj["created_at"], 1, 10) : ""
        tags := []
        try {
            for tg in obj["tags"]
                tags.Push(IsObject(tg) ? tg["name"] : tg)
        }
        info["tags"] := tags
        info["baseUrl"] := GetShareServerUrl()

        ; 更新检测：与本地已装记录比对（sha256 精确比对），结果交给详情窗显示
        this._FillUpdateState(info, meta, obj)

        topic := IsObject(this._detailTopic) ? this._detailTopic : Map()
        ShareDetailGui.ShowGui(this, topic, info, meta, posts)
    }

    ; 取「最新版本」的 meta：每个版本占一层楼（正文里带 ```json 块），最后一层就是最新版。
    ; 首楼只是初版 —— 只读首楼的话，更新过的分享会下到旧包。
    _LatestMeta(obj) {
        posts := (obj.Has("post_stream") && obj["post_stream"].Has("posts")) ? obj["post_stream"]["posts"] : []
        i := IsObject(posts) ? posts.Length : 0
        while (i >= 1) {
            cooked := posts[i].Has("cooked") ? posts[i]["cooked"] : ""
            try {
                return this._ExtractShareMeta(cooked)
            } catch {
            }
            i--
        }
        throw Error(GetLang("帖子缺少共享信息块"))
    }

    ; 从某一层的 cooked 提取 ```json 元数据块
    _ExtractShareMeta(cooked) {
        if (RegExMatch(cooked, "is)<pre[^>]*>\s*<code[^>]*>(.*?)</code></pre>", &m) = 0)
            throw Error(GetLang("帖子缺少共享信息块"))
        raw := this._HtmlUnescape(m[1])
        meta := JSON.parse(raw)
        if (!IsObject(meta) || !meta.Has("file") || meta["file"] == "")
            throw Error(GetLang("共享信息块缺少 file 字段"))
        return meta
    }

    _BeginDownload(meta) {
        global RMT_Discourse
        baseUrl := GetShareServerUrl()
        fileUrl := meta["file"]
        if (SubStr(fileUrl, 1, 4) != "http") {
            if (SubStr(fileUrl, 1, 1) != "/")
                fileUrl := "/" fileUrl
            fileUrl := baseUrl fileUrl
        }
        ; 从 URL 取文件名（去掉短url前缀与查询串）
        fileName := fileUrl
        if (InStr(fileName, "?"))
            fileName := SubStr(fileName, 1, InStr(fileName, "?") - 1)
        fileName := StrReplace(fileName, "/", "\")
        SplitPath fileName, &baseName
        if (baseName == "")
            baseName := "shared.rmt"
        this._downloadPath := A_Temp "\RMT_Share\" baseName

        topic := this._detailTopic
        titleTxt := IsObject(topic) ? topic["title"] : ""
        this._SetStatus(Format("{} {}", GetLang("正在下载"), titleTxt))
        this._pending := "download"
        try RMT_Discourse.BeginDownload(fileUrl, this._downloadPath)
        catch as e {
            this._pending := ""
            this._SetStatus(e.Message)
            return
        }
        this._StartPoll()
    }

    ; 下载完成后「并入当前配置」——走与「合并导入」同一条路（MergeUtil）：
    ; 解包到临时目录 → 解析出宏/模块 → 追加进当前配置的页签与模块 → 落盘。
    ; 关键：不改 CurSettingName、不写 IsReload、不 SafeReload ——
    ; 因为动的只是「当前配置里的表」，落盘后由热重载把 Worker / 触发键 / 定时 / 界面宏一并刷新。
    _ImportDownloaded() {
        savePath := this._downloadPath
        if (!FileExist(savePath)) {
            this._SetStatus(GetLang("下载文件不存在"))
            return
        }

        shareName := ""
        if (IsObject(this._detailMeta) && this._detailMeta.Has("name"))
            shareName := Trim(String(this._detailMeta["name"]))
        if (shareName == "")
            SplitPath savePath, , , , &shareName

        ; 合并是追加式的：同一版重复下会多出一份模块，先拦掉
        if (this._AlreadyLatest()) {
            this._SetStatus(Format(GetLang("已是最新版本，无需重复导入：{}"), shareName))
            return
        }

        items := []
        try {
            MergeUtil.PrepareTempFromRmt(savePath)
            root := MergeUtil.ParseSourceConfig(MergeUtil.TempMergeDir)
            this._CollectMergeItems(root, items)
        } catch as e {
            MergeUtil.CleanupTemp()
            this._SetStatus(GetLang("解包失败: ") e.Message)
            return
        }

        if (items.Length == 0) {
            MergeUtil.CleanupTemp()
            this._SetStatus(GetLang("包里没有可导入的宏"))
            return
        }

        ; 更新场景：先记下上一版并入的模块 —— 等合并成功后再撤，失败时旧版仍在
        oldFolds := this._FindImportedFolds(shareName)

        try {
            result := MergeUtil.ExecuteMerge(items, shareName)
            removed := this._RemoveFoldsByID(oldFolds)
            ; §18 与「合并导入」同款收尾：显式落盘全部表 + 表集合，再走热重载
            SaveAllTableItemInfo(MySoftData.TableInfo)
            OnSaveSetting()
            MergeUtil.CleanupTemp()
            ; 主界面当前页签重渲染，新并入的模块立刻可见（其余页签切换时自然重建）
            try MyMainWin.RenderTab(MySoftData.TableInfo[MainSoftData.TableIndex])
            ; 记下「本机装的是这一版（这个 sha256）」——下次刷新索引即可标出新版本
            this._RecordInstalled(MySoftData.CurSettingName)
            this._ApplyFilterAndRender(this._page)
            ; 更新场景多提一句「已替换上一版」；首次导入不提
            msg := GetLang("已并入当前配置《{}》：{} 个模块 / {} 个宏")
            if (removed > 0)
                msg := GetLang("已并入当前配置《{}》：{} 个模块 / {} 个宏（已替换上一版 {} 个模块）")
            this._SetStatus(Format(msg, MySoftData.CurSettingName, result.ModuleCount, items.Length, removed))
        } catch as e {
            MergeUtil.CleanupTemp()
            this._SetStatus(GetLang("导入失败: ") e.Message)
        }
    }

    ; 合并树里收集全部宏节点（MergeTreeNode 默认 IsChecked=true，即整包导入）
    _CollectMergeItems(node, arr) {
        if (!IsObject(node))
            return
        if (node.Type == "Item" && node.IsChecked)
            arr.Push(node)
        if (node.HasProp("Children")) {
            for child in node.Children
                this._CollectMergeItems(child, arr)
        }
    }

    ; 找出「上次并入」产生的模块：MergeUtil 给并入模块固定命名「原模块名 (来源名)」
    _FindImportedFolds(shareName) {
        out := []
        if (shareName == "")
            return out
        suffix := " (" shareName ")"
        n := StrLen(suffix)
        for i, tableItem in MySoftData.TableInfo {
            for fold in tableItem.Folds {
                if (StrLen(fold.Remark) > n && SubStr(fold.Remark, -n) == suffix)
                    out.Push({ Tab: i, ID: fold.ID })
            }
        }
        return out
    }

    ; 撤掉指定模块（连同其下全部宏）—— 更新时用，避免新旧两份同名模块并存
    _RemoveFoldsByID(list) {
        if (!IsObject(list) || list.Length == 0)
            return 0
        removed := 0
        for i, tableItem in MySoftData.TableInfo {
            ids := Map()
            for rec in list {
                if (rec.Tab == i)
                    ids[rec.ID] := true
            }
            if (ids.Count == 0)
                continue
            keepFolds := []
            for fold in tableItem.Folds {
                if (!ids.Has(fold.ID))
                    keepFolds.Push(fold)
            }
            if (keepFolds.Length == 0)      ; 别把整张表清空
                continue
            keepItems := []
            for item in tableItem.Items {
                if (!ids.Has(item.FoldID))
                    keepItems.Push(item)
            }
            tableItem.Folds := keepFolds
            tableItem.Items := keepItems
            tableItem.RebuildIndex()
            removed += ids.Count
        }
        if (removed > 0)
            RebuildTableLocator()
        return removed
    }

    ; 本机这一版是否就是线上最新版（比 sha256，缺则退比版本号）
    _AlreadyLatest() {
        rec := ShareCenterGui.InstalledGet(IsObject(this._detailTopic) ? this._detailTopic["id"] : 0)
        if (!IsObject(rec) || !IsObject(this._detailMeta))
            return false
        onlineSha := ""
        onlineVer := ""
        if (this._detailMeta.Has("sha256"))
            onlineSha := Trim(String(this._detailMeta["sha256"]))
        if (this._detailMeta.Has("ver"))
            onlineVer := Trim(String(this._detailMeta["ver"]))

        localSha := rec["sha256"]
        if (localSha != "" && onlineSha != "")
            return (localSha == onlineSha)
        if (rec["ver"] != "" || onlineVer != "")
            return (rec["ver"] == onlineVer)
        return false
    }

    ; ===== 轮询 =====

    _StartPoll() {
        if (IsObject(this._pollFn))
            SetTimer(this._pollFn, 150)
    }

    _StopPoll() {
        if (IsObject(this._pollFn))
            SetTimer(this._pollFn, 0)
    }

    _Poll(*) {
        global RMT_Discourse
        if (this.closed || !IsObject(this.ui) || this._pending == "") {
            this._StopPoll()
            return
        }
        if (!IsObject(RMT_Discourse)) {
            this._pending := ""
            this._StopPoll()
            return
        }

        ; 看门狗：单次请求 45 秒无结果视为挂起，强制复位
        if (this._pendingSince == 0)
            this._pendingSince := A_TickCount
        elapsedMs := A_TickCount - this._pendingSince
        if (elapsedMs > 45000) {
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            this._SetStatus(GetLang("请求超时，请重试"))
            return
        }

        ; 等待中：状态栏实时显示已等待秒数
        elapsedSec := elapsedMs // 1000
        waitingText := GetLang("正在获取索引...") " (" elapsedSec "s)"

        if (this._pending == "index") {
            st := 0
            try st := Integer(RMT_Discourse.GetTextState())
            if (st == 1) {
                if (Mod(elapsedSec, 2) = 0 || elapsedMs - (elapsedSec * 1000) < 300)
                    this._SetStatus(waitingText)
                return
            }
            body := ""
            try body := RMT_Discourse.TakeTextResult()
            if (body == "") {
                err := ""
                try err := RMT_Discourse.GetTextError()
                this._pending := ""
                this._pendingSince := 0
                this._StopPoll()
                this._SetStatus((err != "") ? (GetLang("获取索引失败: ") err) : GetLang("获取索引失败"))
                return
            }

            ; 解析并追加本页
            pageTopics := []
            try pageTopics := this._ParseIndexPage(body)
            catch as e {
                this._pending := ""
                this._pendingSince := 0
                this._StopPoll()
                this._SetStatus(GetLang("列表渲染失败: ") e.Message)
                return
            }
            for topic in pageTopics
                ShareCenterGui._index.Push(topic)

            ; 满页说明可能还有下一页，继续串行抓取
            if (pageTopics.Length >= ShareCenterGui.PAGE_SIZE) {
                this._indexPage++
                this._pendingSince := A_TickCount   ; 重置看门狗（按页计时）
                try RMT_Discourse.BeginGetText(this._BuildIndexUrl(this._indexPage))
                catch as e {
                    this._pending := ""
                    this._pendingSince := 0
                    this._StopPoll()
                    this._SetStatus(GetLang("获取索引失败: ") e.Message)
                    return
                }
                return
            }

            ; 索引抓完
            ShareCenterGui._indexStamp := A_Now
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            this._SaveIndexToFile()
            this._ApplyFilterAndRender(this._page)
        }
        else if (this._pending == "detail") {
            st := 0
            try st := Integer(RMT_Discourse.GetTextState())
            if (st == 1)
                return
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakeTextResult()
            if (body == "") {
                err := ""
                try err := RMT_Discourse.GetTextError()
                this._SetStatus((err != "") ? (GetLang("获取详情失败: ") err) : GetLang("获取详情失败"))
                return
            }
            try {
                obj := JSON.parse(body)
                if (this._detailMode == "info") {
                    this._ShowDetail(obj)
                } else {
                    posts := obj["post_stream"]["posts"]
                    cooked := posts[posts.Length]["cooked"]   ; 仅用于失败日志
                    meta := this._LatestMeta(obj)
                    ; 留着给导入成功后写已装记录用
                    this._detailMeta := meta
                    this._detailPosts := obj.Has("posts_count") ? obj["posts_count"] : 0
                    this._BeginDownload(meta)
                }
            } catch as e {
                ; 留痕：哪个 topic、为什么解析失败（索引过期/非共享帖/服务端异常）
                try {
                    tid := IsObject(this._detailTopic) ? this._detailTopic["id"] : 0
                    info := "详情解析失败 topic=" tid " err=" e.Message " bodyLen=" StrLen(body)
                    if IsSet(cooked) && IsObject(cooked) = false {
                        info .= " cookedLen=" StrLen(cooked)
                            . " hasPre=" (InStr(cooked, "<pre") ? 1 : 0)
                            . " hasClose=" (InStr(cooked, "</code></pre>") ? 1 : 0)
                            . " tail=" SubStr(cooked, -60)
                    } else
                        info .= " cooked=未取得或非字符串"
                    RMTLogSys(RMT_LV_INFO, "ShareCenter", info)
                    ; 落盘完整 body，便于与服务端直抓数据对比
                    try FileDelete(A_Temp "\rmt_body_dump.json")
                    FileAppend(body, A_Temp "\rmt_body_dump.json", "UTF-8")
                }
                this._SetStatus(GetLang("解析共享信息失败: ") e.Message GetLang("（若帖子已删除或非共享帖，点「刷新」更新索引）"))
            }
        }
        else if (this._pending == "download") {
            st := 0
            try st := Integer(RMT_Discourse.GetDownloadState())
            if (st == 1)
                return
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            result := ""
            try result := RMT_Discourse.TakeDownloadResult()
            if (result == "OK") {
                this._SetStatus(GetLang("下载完成，开始导入"))
                this._ImportDownloaded()
            } else {
                this._SetStatus(result != "" ? result : GetLang("下载失败"))
            }
        }
    }

    ; ===== 工具 =====

    _SetStatus(text) {
        if IsObject(this.ui)
            try this.ui.Update("StatusText", "Text", text)
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

    _UriEncode(str) {
        buf := Buffer(StrPut(str, "UTF-8") - 1)
        StrPut(str, buf, "UTF-8")
        out := ""
        loop buf.Size {
            b := NumGet(buf, A_Index - 1, "UChar")
            if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E
                out .= Chr(b)
            else
                out .= Format("%{:02X}", b)
        }
        return out
    }

    _XmlEsc(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }
}
