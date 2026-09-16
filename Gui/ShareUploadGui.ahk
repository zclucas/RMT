#Requires AutoHotkey v2.0

; 上传分享（极简版）：入口自带分享包/名称/级别，用户只可改名称+可选说明
; 论坛 API Key 在主窗口「设置」页配置（ini: ShareApiKey / ShareApiUser），窗口内不再出现授权区
; 发帖正文首楼嵌 ```json 元数据块（与迁移脚本同格式，level 用中文与标签一致）
class ShareUploadGui {
    static instances := Map()
    static _opening := false

    __New() {
        this.ui := 0
        this.closed := false
        this._btnStyle := ""
        this._rmtPath := ""
        this._name := ""
        this._level := ""
        this._pending := ""          ; whoami | find | checkver | upload | post | reply
        this._pendingSince := 0
        this._pollFn := 0
        this._pendingCtx := ""
        this._author := ""
        this._fileUrl := ""
        this._sha256 := ""
        this._updateTarget := 0      ; 非 0 = 追加版本层到已有帖（topicId）；由判重结果自动决定，不弹窗问
        this._sameTopicId := 0       ; 判重阶段命中的同名帖 id
        this._openUrl := ""          ; 成功后要打开的帖子地址（窗内「打开帖子」按钮用）
    }

    static ShowGui(rmtPath := "", name := "", level := "") {
        key := "global"
        if (ShareUploadGui.instances.Has(key)) {
            oldInst := ShareUploadGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && IsObject(oldInst.ui)
                    && hwnd && XAMLHost.IsHwndResponsive(hwnd, 300)) {
                try oldInst.ui.Update("Window", "Visibility", "Visible")
                try WinActivate("ahk_id " hwnd)
                if (rmtPath != "")
                    oldInst._SetRmtPath(rmtPath)
                if (name != "")
                    oldInst._name := name
                if (level != "")
                    oldInst._level := level
                try oldInst._Prefill()
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            ShareUploadGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (ShareUploadGui._opening)
            return
        ShareUploadGui._opening := true
        try {
            inst := ShareUploadGui()
            inst._rmtPath := rmtPath
            inst._name := name
            inst._level := (level != "") ? level : GetLang("配置")
            inst._BuildAndShow()
            ShareUploadGui.instances[key] := inst
        } finally {
            ShareUploadGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("上传分享")
        titleHeight := "30"
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        root := body.Add("Grid").Margin("14, 8, 14, 10")
        root.Rows("*", "Auto", "Auto")

        form := root.Add("StackPanel").Grid_Row(0).Margin("2,2,2,2")

        this._AddFieldRow(form, "分享包：", 0)
        pathRow := form.Add("Grid").Margin("0,0,0,10")
        pathRow.Cols("*", "Auto")
        pathRow.Add("TextBox").Name("PathInput").Height(26).Margin("0,0,8,0")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .VerticalContentAlignment("Center").Grid_Column(0).IsReadOnly("True")
        this._AddBtn(pathRow, "SelectFileBtn", GetLang("选择文件"), 80).Grid_Column(1)

        this._AddFieldRow(form, "名称：", 1)
        form.Add("TextBox").Name("NameInput").Height(26).Margin("0,0,0,10")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .VerticalContentAlignment("Center")

        this._AddFieldRow(form, "版本（可选）：", 3)
        form.Add("TextBox").Name("VerInput").Height(26).Margin("0,0,0,10")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .VerticalContentAlignment("Center")
            .ToolTip(GetLang("如 1.0 / 2026-09。填了会在共享详情里显示，便于区分版本"))

        this._AddFieldRow(form, "说明（可选）：", 2)
        form.Add("TextBox").Name("NoteInput").Height(60).Margin("0,0,0,2")
            .TextWrapping("Wrap").AcceptsReturn("True")
            .VerticalScrollBarVisibility("Auto")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 提示区：本窗是唯一的反馈出口 —— 校验失败、判重、上传/发帖结果全写这里，不弹任何子窗口
        root.Add("TextBlock").Name("StatusText").Grid_Row(1).Margin("2,8,2,0")
            .Text("").Foreground("{DynamicResource TextSub}").FontSize(12)
            .TextWrapping("Wrap").MaxHeight(80)

        btnRow := root.Add("StackPanel").Orientation("Horizontal").Grid_Row(2)
            .HorizontalAlignment("Center").Margin("0,10,0,2")
        this._AddBtn(btnRow, "PublishBtn", GetLang("发布到论坛"), 110).Margin("0,0,10,0")
        this._AddBtn(btnRow, "OpenTopicBtn", GetLang("打开帖子"), 90).Margin("0,0,10,0").Visibility("Collapsed")
        this._AddBtn(btnRow, "CancelBtn", GetLang("取消"), 90)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="True" Width="480" Height="505" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("SelectFileBtn", "Click", ObjBindMethod(this, "OnSelectFile"))
        this.ui.OnEvent("PublishBtn", "Click", ObjBindMethod(this, "OnPublish"))
        this.ui.OnEvent("OpenTopicBtn", "Click", ObjBindMethod(this, "OnOpenTopicClick"))
        this.ui.OnEvent("CancelBtn", "Click", ObjBindMethod(this, "OnCancelClick"))

        this._pollFn := ObjBindMethod(this, "_Poll")
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    _AddFieldRow(parent, label, _) {
        parent.Add("TextBlock").Text(GetLang(label))
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .Margin("0,0,0,4")
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
        this._Prefill()
        try {
            XamlWin.OnLoadTheme(this.ui)
        }
        try this.ui.Update("Window", "Opacity", "1")
    }

    _Prefill() {
        if (this._rmtPath != "")
            try this.ui.Update("PathInput", "Text", this._rmtPath)
        nameOut := this._name
        if (nameOut == "" && this._rmtPath != "") {
            SplitPath this._rmtPath, , , &extNoUse, &baseNoExt
            if (baseNoExt != "")
                nameOut := baseNoExt
        }
        if (nameOut != "")
            try this.ui.Update("NameInput", "Text", nameOut)
    }

    _SetRmtPath(path) {
        this._rmtPath := path
        try this.ui.Update("PathInput", "Text", path)
        if (this._name == "") {
            SplitPath path, , , &ext, &baseNoExt
            if (baseNoExt != "") {
                this._name := baseNoExt
                try this.ui.Update("NameInput", "Text", baseNoExt)
            }
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        this._StopPoll()
        ShareUploadGui._opening := false
        if (ShareUploadGui.instances.Has("global"))
            ShareUploadGui.instances.Delete("global")
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnCancelClick(state := unset, ctrl := unset, event := unset) {
        this.Close()
    }

    ; 窗内「打开帖子」：发布成功后才显示，地址就是本次发布/追加的帖子
    OnOpenTopicClick(state := unset, ctrl := unset, event := unset) {
        if (this._openUrl != "")
            try Run(this._openUrl)
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

    ; ===== 按钮事件 =====

    OnSelectFile(state := unset, ctrl := unset, event := unset) {
        picked := FileSelect(1, , GetLang("选择分享包"), GetLang("RMT分享包 (*.rmt)"))
        if (picked == "")
            return
        this._SetRmtPath(picked)
    }

    ; ===== 发布 =====

    OnPublish(state := unset, ctrl := unset, event := unset) {
        global RMT_Discourse
        if (this._pending != "") {
            this._SetStatus(GetLang("有任务进行中，请稍候"))
            return
        }
        this._ResetResult()
        try disc := GetDiscourse()
        catch as e {
            this._SetStatus(e.Message, "err")
            return
        }

        path := ""
        try path := Trim(String(this.ui.Query("PathInput>Text")))
        if (path == "" && this._rmtPath != "")
            path := this._rmtPath
        if (path == "" || !FileExist(path)) {
            this._SetStatus(GetLang("请先选择要分享的 .rmt 文件"), "err")
            return
        }
        SplitPath path, , , &ext
        if (StrLower(ext) != "rmt") {
            this._SetStatus(GetLang("只支持 .rmt 分享包"), "err")
            return
        }

        name := ""
        try name := Trim(String(this.ui.Query("NameInput>Text")))
        if (name == "")
            name := this._name
        if (name == "") {
            this._SetStatus(GetLang("请填写名称"), "err")
            return
        }
        note := ""
        try note := Trim(String(this.ui.Query("NoteInput>Text")))
        ver := ""
        try ver := Trim(String(this.ui.Query("VerInput>Text")))

        ; 鉴权：凭据来自设置页的「登录论坛」授权（或手动写进 ini 的管理员 Key）
        apiKey := GetShareApiKey()
        if (apiKey == "") {
            this._SetStatus(GetLang("请先在「设置」页点「登录论坛」完成授权"), "err")
            return
        }
        apiUser := GetShareApiUser()
        SetShareAuth(apiUser, apiKey)
        RMT_Discourse.SetAuth(apiUser, apiKey)

        baseUrl := GetShareServerUrl()
        this._rmtPath := path
        this._updateTarget := 0
        this._pendingCtx := {baseUrl: baseUrl, name: name, note: note, level: this._level,
            ver: ver, author: apiUser}

        ; 管理员模式用户名已知；用户密钥模式先取当前用户名（失败不阻断，author 留空）
        if (apiUser != "") {
            this._BeginFindSameName()
            return
        }
        this._pending := "whoami"
        this._pendingSince := 0
        this._SetStatus(GetLang("正在获取论坛用户名..."))
        try RMT_Discourse.BeginGetTextAuth(baseUrl "/session/current.json")
        catch as e {
            this._pending := ""
            this._SetStatus(e.Message, "err")
            return
        }
        this._StartPoll()
    }

    ; 发布前查同名帖：站点 duplicate_topic_titles=disallowed，重名不能新发。
    ; 命中后不问用户：命中别人的帖 → 提示改名；命中自己的帖 → 再核对版本，新的就追加为新版本层。
    _BeginFindSameName() {
        global RMT_Discourse
        ctx := this._pendingCtx
        if (ctx.name == "") {
            this._BeginUploadWithMeta()
            return
        }
        this._pending := "find"
        this._pendingSince := 0
        this._SetStatus(GetLang("正在检查同名分享..."))
        q := ctx.name " in:title category:shared"
        try RMT_Discourse.BeginGetTextAuth(ctx.baseUrl "/search.json?q=" this._UriEncode(q))
        catch {
            ; 查不了不阻断，按新建走
            this._BeginUploadWithMeta()
            return
        }
        this._StartPoll()
    }

    _BeginUploadWithMeta() {
        global RMT_Discourse
        this._SetStatus(GetLang("正在上传分享包..."))
        this._pending := "upload"
        this._pendingSince := 0
        try RMT_Discourse.BeginUploadFile(this._pendingCtx.baseUrl "/uploads.json", this._rmtPath)
        catch as e {
            this._pending := ""
            this._SetStatus(e.Message, "err")
            return
        }
        this._StartPoll()
    }

    _BuildMetaAndPost() {
        ctx := this._pendingCtx
        size := 0
        try size := FileGetSize(this._rmtPath)

        meta := Map()
        meta["rmt"] := 1
        meta["level"] := ctx.level
        meta["name"] := ctx.name
        meta["game"] := ""
        meta["author"] := ObjHasOwnProp(ctx, "author") ? ctx.author : ""
        meta["ver"] := ObjHasOwnProp(ctx, "ver") ? ctx.ver : ""
        meta["keytip"] := ""
        meta["file"] := this._fileUrl
        meta["size"] := size
        meta["sha256"] := this._sha256
        meta["deps"] := []
        meta["note"] := ctx.note

        metaJson := JSON.stringify(meta, 0)
        baseUrl := ctx.baseUrl

        ; 版本层：用 <details> 折叠，论坛网页上只占一行标题，不干扰讨论阅读；
        ; 楼层里的附件始终被引用，所以旧版本不会被站点的孤儿附件清理（48 小时）删掉
        if (IsObject(this._updateTarget)) {
            summary := (ctx.ver != "") ? (GetLang("版本 v") ctx.ver " · ") : GetLang("新版本 · ")
            summary .= FormatTime(A_Now, "yyyy-MM-dd")
            raw := "<details>`n<summary>" summary "</summary>`n`n"
            if (ctx.note != "")
                raw .= ctx.note "`n`n"
            raw .= "``````json`n" metaJson "`n``````" "`n`n</details>"

            this._pending := "reply"
            this._pendingSince := 0
            this._SetStatus(GetLang("正在发布新版本..."))
            try RMT_Discourse.BeginCreateReply(baseUrl "/posts.json", this._updateTarget.topicId, raw)
            catch as e {
                this._pending := ""
                this._SetStatus(e.Message, "err")
                return
            }
            this._StartPoll()
            return
        }

        ; 首楼：说明 + meta。新版本会追加到下方楼层，写明指引以免访客下到旧版
        raw := "> " GetLang("新版本会追加在本帖下方楼层，下载请以最新楼层为准。") "`n`n"
        if (ctx.note != "")
            raw .= ctx.note "`n`n"
        raw .= "``````json`n" metaJson "`n``````"

        title := ctx.name

        this._pending := "post"
        this._pendingSince := 0
        this._SetStatus(GetLang("正在发布帖子..."))
        try RMT_Discourse.BeginCreatePost(baseUrl "/posts.json", title, raw, GetShareCategoryId(), ctx.level)
        catch as e {
            this._pending := ""
            this._SetStatus(e.Message, "err")
            return
        }
        ; 上传成功那一步在 _Poll 里已 _StopPoll，这里必须重新挂上轮询，否则发帖结果永远没人取（界面停在这句）
        this._StartPoll()
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

        if (this._pendingSince == 0)
            this._pendingSince := A_TickCount
        elapsedMs := A_TickCount - this._pendingSince
        ; 看门狗：取用户名 30 秒，上传/发帖 3 分钟（大包慢网）
        limitMs := (this._pending == "whoami") ? 30000 : 180000
        if (elapsedMs > limitMs) {
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            this._SetStatus(GetLang("请求超时，请重试"), "err")
            return
        }
        elapsedSec := elapsedMs // 1000

        if (this._pending == "whoami") {
            st := 0
            try st := Integer(RMT_Discourse.GetTextAuthState())
            if (st == 1)
                return
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakeTextAuthResult()
            author := ""
            if (body != "") {
                try {
                    obj := JSON.parse(body)
                    if (obj.Has("current_user") && obj["current_user"].Has("username"))
                        author := obj["current_user"]["username"]
                }
            }
            this._pendingCtx.author := author
            this._BeginFindSameName()
        }
        else if (this._pending == "find") {
            st := 0
            try st := Integer(RMT_Discourse.GetTextAuthState())
            if (st == 1)
                return
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakeTextAuthResult()

            ctx := this._pendingCtx
            hitId := 0, hitUser := ""
            if (body != "") {
                try {
                    obj := JSON.parse(body)
                    if (obj.Has("topics") && IsObject(obj["topics"])) {
                        for t in obj["topics"] {
                            if (t.Has("title") && t["title"] == ctx.name) {
                                hitId := t.Has("id") ? t["id"] : 0
                                break
                            }
                        }
                    }
                    if (hitId != 0 && obj.Has("posts") && IsObject(obj["posts"])) {
                        for p in obj["posts"] {
                            if (p.Has("topic_id") && p["topic_id"] == hitId) {
                                hitUser := p.Has("username") ? p["username"] : ""
                                break
                            }
                        }
                    }
                }
            }
            ; 没有标题完全相等的 → 照常新建（模糊命中的同名子串不算）
            if (hitId == 0) {
                this._BeginUploadWithMeta()
                return
            }

            ; 同名帖不是自己发的 → 站点禁止同名，只能改名。绝不往别人的帖里塞版本层
            if (hitUser != "" && ctx.author != "" && hitUser != ctx.author) {
                this._SetStatus(Format(GetLang("名称已被 @{} 使用，请改名称后重试"), hitUser), "err")
                return
            }

            ; 同名且是自己发的 → 不弹窗，直接拉这帖的楼层核对版本号是否已经存在
            this._sameTopicId := hitId
            this._pending := "checkver"
            this._pendingSince := 0
            this._SetStatus(GetLang("正在核对已有版本..."))
            try RMT_Discourse.BeginGetTextAuth(ctx.baseUrl "/t/" hitId ".json")
            catch as e {
                this._pending := ""
                this._SetStatus(e.Message, "err")
                return
            }
            this._StartPoll()
        }
        else if (this._pending == "checkver") {
            st := 0
            try st := Integer(RMT_Discourse.GetTextAuthState())
            if (st == 1)
                return
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakeTextAuthResult()

            ctx := this._pendingCtx
            obj := ""
            try obj := JSON.parse(body)
            if (!IsObject(obj)) {
                errText := ""
                try errText := RMT_Discourse.GetTextAuthError()
                this._SetStatus(errText != "" ? (GetLang("读取已有分享失败: ") ShareUploadGui._ErrText(errText)) : GetLang("读取已有分享失败，请重试"), "err")
                return
            }

            ; 归属最终判定：以帖子真实数据为准。自动追加是「无提示」的，所以宁可拦错也不能塞进别人的帖
            owner := this._TopicOwner(obj)
            if (owner == "" || ctx.author == "" || StrLower(owner) != StrLower(ctx.author)) {
                label := (owner != "") ? ("@" owner) : GetLang("其他人")
                this._SetStatus(Format(GetLang("名称已被 {} 使用，请改名称后重试"), label), "err")
                return
            }

            ; 版本重复判定：空版本也算一个版本 —— 两个都没填版本号同样算重复
            cur := Trim(ctx.ver)
            for v in this._CollectVersions(obj) {
                if (StrLower(Trim(v)) == StrLower(cur)) {
                    label := (cur == "") ? GetLang("未填版本号") : ("v" cur)
                    this._SetStatus(Format(GetLang("《{}》已经有过一个「{}」的版本了。`n请改版本号（或改分享名称）后重试。"), ctx.name, label), "err")
                    return
                }
            }

            ; 版本是新的 → 作为新版本层追加到该帖（旧版内容、讨论、点赞全保留）
            this._updateTarget := {topicId: this._sameTopicId}
            this._BeginUploadWithMeta()
        }
        else if (this._pending == "upload") {
            st := 0
            try st := Integer(RMT_Discourse.GetUploadState())
            if (st == 1) {
                if (Mod(elapsedSec, 2) == 0)
                    this._SetStatus(GetLang("正在上传分享包...") " (" elapsedSec "s)")
                return
            }
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakeUploadResult()
            if (body == "") {
                err := ""
                try err := RMT_Discourse.GetUploadError()
                msg := (err != "") ? (GetLang("上传失败: ") ShareUploadGui._ErrText(err)) : GetLang("上传失败")
                this._SetStatus(msg, "err")
                return
            }
            ; 提取 short_path（优先）或 url
            fileUrl := ""
            try {
                obj := JSON.parse(body)
                if (obj.Has("short_path") && obj["short_path"] != "")
                    fileUrl := obj["short_path"]
                else if (obj.Has("url"))
                    fileUrl := obj["url"]
            }
            if (fileUrl == "") {
                this._SetStatus(GetLang("上传响应异常：未取到附件地址"), "err")
                return
            }
            this._fileUrl := fileUrl
            sha := ""
            try sha := RMT_Discourse.Sha256File(this._rmtPath)
            this._sha256 := sha
            this._BuildMetaAndPost()
        }
        else if (this._pending == "post") {
            st := 0
            try st := Integer(RMT_Discourse.GetPostState())
            if (st == 1) {
                if (Mod(elapsedSec, 2) == 0)
                    this._SetStatus(GetLang("正在发布帖子...") " (" elapsedSec "s)")
                return
            }
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakePostResult()
            if (body == "") {
                err := ""
                try err := RMT_Discourse.GetPostError()
                msg := (err != "") ? (GetLang("发帖失败: ") ShareUploadGui._ErrText(err)) : GetLang("发帖失败")
                this._SetStatus(msg, "err")
                return
            }
            topicId := "", topicSlug := ""
            try {
                obj := JSON.parse(body)
                topicId := obj.Has("topic_id") ? String(obj["topic_id"]) : ""
                topicSlug := obj.Has("topic_slug") ? String(obj["topic_slug"]) : ""
            }
            url := GetShareServerUrl()
            if (topicSlug != "" && topicId != "")
                url .= "/t/" topicSlug "/" topicId
            else if (topicId != "")
                url .= "/t/" topicId
            this._SetDone(GetLang("分享发布成功！"), url)
        }
        else if (this._pending == "reply") {
            st := 0
            try st := Integer(RMT_Discourse.GetPostState())
            if (st == 1) {
                if (Mod(elapsedSec, 2) == 0)
                    this._SetStatus(GetLang("正在发布新版本...") " (" elapsedSec "s)")
                return
            }
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            body := ""
            try body := RMT_Discourse.TakePostResult()
            if (body == "") {
                err := ""
                try err := RMT_Discourse.GetPostError()
                msg := (err != "") ? (GetLang("发布新版本失败: ") ShareUploadGui._ErrText(err)) : GetLang("发布新版本失败")
                this._SetStatus(msg, "err")
                return
            }
            topicId := IsObject(this._updateTarget) ? this._updateTarget.topicId : 0
            postNo := ""
            obj := ""
            try obj := JSON.parse(body)
            if (IsObject(obj) && obj.Has("post_number"))
                postNo := String(obj["post_number"])
            url := GetShareServerUrl() "/t/" topicId
            if (postNo != "")
                url .= "/" postNo
            this._SetDone(GetLang("新版本已追加到帖子下方楼层！"), url)
        }
    }

    ; URL 查询串编码（UTF-8 → %XX），同名搜索要带中文名称
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

    ; 去掉 C# 侧的步骤标记（[D3]/[D4]…）再给用户看；日志里仍保留完整标记
    static _ErrText(raw) {
        s := String(raw)
        s := RegExReplace(s, "^\[D\d\]\s*", "")
        return Trim(s)
    }

    ; 唯一的反馈出口：kind = "" 普通 / "ok" 成功 / "err" 失败（前缀符号区分，不引入新配色）
    _SetStatus(text, kind := "") {
        if (!IsObject(this.ui))
            return
        prefix := (kind == "ok") ? "✓ " : (kind == "err") ? "✗ " : ""
        fg := (kind == "") ? "{DynamicResource TextSub}" : "{DynamicResource TextMain}"
        try this.ui.Update("StatusText", "Foreground", fg)
        try this.ui.Update("StatusText", "Text", prefix text)
    }

    ; 发布完成：地址写进提示区，并放出「打开帖子」按钮
    _SetDone(text, url) {
        this._openUrl := url
        this._SetStatus(url = "" ? text : (text "`n" url), "ok")
        try this.ui.Update("OpenTopicBtn", "Visibility", "Visible")
    }

    ; 每次点发布先清掉上一次的结果（旧提示、旧地址、按钮显隐）
    _ResetResult() {
        this._openUrl := ""
        try this.ui.Update("StatusText", "Text", "")
        try this.ui.Update("StatusText", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("OpenTopicBtn", "Visibility", "Collapsed")
    }

    ; 同名帖的创建者（用于确认「是我的帖」，才允许自动追加版本层）
    _TopicOwner(obj) {
        try {
            if (obj.Has("details") && obj["details"].Has("created_by") && obj["details"]["created_by"].Has("username"))
                return String(obj["details"]["created_by"]["username"])
        }
        try {
            posts := obj["post_stream"]["posts"]
            if (IsObject(posts) && posts.Length >= 1 && posts[1].Has("username"))
                return String(posts[1]["username"])
        }
        return ""
    }

    ; 把同名帖的全部楼层扫一遍，收集各版本号（首楼=初版，其后每层=一个版本）
    ; 空串也是合法版本（用户不填版本号），所以空也要参与判重
    _CollectVersions(obj) {
        vers := []
        posts := (obj.Has("post_stream") && obj["post_stream"].Has("posts")) ? obj["post_stream"]["posts"] : []
        if (!IsObject(posts))
            return vers
        for p in posts {
            cooked := p.Has("cooked") ? p["cooked"] : ""
            if (cooked == "" || RegExMatch(cooked, "is)<pre[^>]*>\s*<code[^>]*>(.*?)</code></pre>", &m) = 0)
                continue
            meta := ""
            try meta := JSON.parse(ShareUploadGui._HtmlUnescape(m[1]))
            if (!IsObject(meta) || !meta.Has("file") || meta["file"] == "")
                continue
            vers.Push(meta.Has("ver") ? String(meta["ver"]) : "")
        }
        return vers
    }

    static _HtmlUnescape(s) {
        s := StrReplace(s, "&lt;", "<")
        s := StrReplace(s, "&gt;", ">")
        s := StrReplace(s, "&quot;", '"')
        s := StrReplace(s, "&#39;", "'")
        s := StrReplace(s, "&#x27;", "'")
        s := StrReplace(s, "&amp;", "&")
        return s
    }
}
