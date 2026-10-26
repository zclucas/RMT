#Requires AutoHotkey v2.0

; 一键反馈：软件内直接向论坛提交 Bug / 建议（bug反馈 cat 42、功能建议 cat 44）
; 鉴权复用共享那套：设置页「登录论坛」授权写入 ini 的 ShareApiKey；管理员 Key 模式另走 ShareApiUser
; 正文就是 Discourse 的 Markdown 原文：图片用 ![名](路径) 直接写在正文里（Ctrl+V 粘贴 / 拖文件进输入框，
; 插在光标处），提交时逐张上传到 /uploads.json 再把正文里的本地路径替换成附件地址
class FeedbackGui {
    static instances := Map()
    static _opening := false
    static MaxImgs := 9          ; 站点 newuser_max_images=20，留点余量

    __New() {
        this.ui := 0
        this.closed := false
        this._btnStyle := ""
        this._kind := "bug"          ; bug | idea
        this._keepEnv := 1           ; 正文是否附带运行环境
        this._imgs := []             ; 正文里待上传的图：[{path, alt, raw, url, failed}]
        this._upIdx := 0             ; 正在上传第几张（1 起）
        this._pending := ""          ; upload | post
        this._pendingSince := 0
        this._pollFn := 0
        this._loginTick := ""
        this._relogin := false       ; 凭据被站点判失效后，才把按钮恢复成可点的「重新登录」
        this._resumeSubmit := false  ; 授权完成后自动继续提交
        this._openUrl := ""
        this._baseUrl := ""
        this._titleSent := ""
        this._bodySent := ""
        this._titleRetried := 0
        this._prefillBody := ""
        this._autoTpl := ""          ; 上一次自动写进描述框的骨架，用于判断用户是否动过
        this._done := false          ; 已提交成功：输入只读、不再弹放弃确认
    }

    static ShowGui(kind := "bug", prefillBody := "") {
        key := "global"
        if (FeedbackGui.instances.Has(key)) {
            oldInst := FeedbackGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && IsObject(oldInst.ui)
                    && hwnd && XAMLHost.IsHwndResponsive(hwnd, 300)) {
                try oldInst.ui.Update("Window", "Visibility", "Visible")
                try WinActivate("ahk_id " hwnd)
                if (kind != "")
                    oldInst._SetKind(kind)
                if (prefillBody != "") {
                    oldInst._prefillBody := prefillBody
                    try oldInst.ui.Update("BodyInput", "Text", prefillBody)
                }
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            FeedbackGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (FeedbackGui._opening)
            return
        FeedbackGui._opening := true
        try {
            inst := FeedbackGui()
            inst._kind := (kind = "idea") ? "idea" : "bug"
            inst._prefillBody := prefillBody
            inst._BuildAndShow()
            FeedbackGui.instances[key] := inst
        } finally {
            FeedbackGui._opening := false
        }
    }

    _BuildAndShow() {
        global MainSoftData
        this.closed := false
        title := GetLang("提交反馈")
        titleHeight := "30"
        ; 次要按钮：白底描边，悬停浅色
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        ; 主按钮：Action 实心，悬停/按下加深
        this._btnPrimaryStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        root := body.Add("Grid").Margin("16, 12, 16, 14")
        ; 正文框吃满剩余高度（固定窗口高度下 "*" 可靠），底部只留一行动作，不会浮出空白
        root.Rows("Auto", "Auto", "Auto", "Auto", "*", "Auto", "Auto")

        ; 类型：两个按钮当单选，选中态用 Action 配色
        kindRow := root.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").Margin("0,0,0,14")
        this._AddBtn(kindRow, "KindBug", GetLang("Bug 反馈"), 92).Margin("0,0,6,0")
        this._AddBtn(kindRow, "KindIdea", GetLang("功能建议"), 92)

        root.Add("TextBlock").Grid_Row(1).Text(GetLang("标题"))
            .Foreground("{DynamicResource TextSub}").FontSize(12).Margin("2,0,0,5")
        root.Add("TextBox").Name("TitleInput").Grid_Row(2).Height(28).Margin("0,0,0,12")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .VerticalContentAlignment("Center")
            .ToolTip(GetLang("一句话说清问题，至少 4 个字；不要和已有帖子重名"))

        root.Add("TextBlock").Grid_Row(3).Text(GetLang("描述"))
            .Foreground("{DynamicResource TextSub}").FontSize(12).Margin("2,0,0,5")
        root.Add("TextBox").Name("BodyInput").Grid_Row(4)
            .TextWrapping("Wrap").AcceptsReturn("True").VerticalScrollBarVisibility("Auto")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .ToolTip(GetLang("支持 Markdown（加粗、列表、引用、代码块）。图片：Ctrl+V 粘进正文，或把图片文件拖进来"))

        envRow := root.Add("Grid").Grid_Row(5).Margin("0,10,0,0")
        envRow.Cols("Auto", "*")
        envBtn := this._AddBtn(envRow, "EnvBtn", GetLang("附带环境信息"), 120).Grid_Column(0).Margin("0,0,10,0")
        envBtn.Height(24).FontSize(11)
        envRow.Add("TextBlock").Name("EnvText").Grid_Column(1).Text(this._EnvPreview())
            .Foreground("{DynamicResource TextSub}").FontSize(11).VerticalAlignment("Center")

        ; 底栏：左边状态、右边动作，一行收住
        bar := root.Add("Grid").Grid_Row(6).Margin("0,12,0,0")
        bar.Cols("*", "Auto")
        bar.Add("TextBlock").Name("StatusText").Grid_Column(0).Margin("2,0,12,0")
            .Text("").Foreground("{DynamicResource TextSub}").FontSize(12)
            .TextWrapping("Wrap").VerticalAlignment("Center").MaxHeight("42")
        btnRow := bar.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        this._AddBtn(btnRow, "LoginBtn", GetLang("登录论坛"), 84).Margin("0,0,14,0")
        this._AddBtn(btnRow, "OpenTopicBtn", GetLang("打开帖子"), 84).Margin("0,0,8,0").Visibility("Collapsed")
        this._AddBtn(btnRow, "CancelBtn", GetLang("取消"), 70).Margin("0,0,8,0")
        this._AddBtn(btnRow, "SubmitBtn", GetLang("提交反馈"), 92, true)

        refWin := XamlWin.ActiveOwner()
        posAttr := XamlWin.PosAttr(566, 470, refWin)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        ; 固定高度：引擎按 SizeToContent 算高会少一截，底部按钮会被裁掉
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="True"' posAttr ' Width="566" Height="470" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("KindBug", "Click", ObjBindMethod(this, "OnKindClick", "bug"))
        this.ui.OnEvent("KindIdea", "Click", ObjBindMethod(this, "OnKindClick", "idea"))
        this.ui.OnEvent("EnvBtn", "Click", ObjBindMethod(this, "OnEnvClick"))
        ; 图片：拖进输入框 / 正文框内 Ctrl+V，都是往正文里插 Markdown
        this.ui.OnEvent("BodyInput", "PreviewKeyDown:V", ObjBindMethod(this, "OnBodyPasteKey"))
        this.ui.OnEvent("BodyInput", "FileDrop", ObjBindMethod(this, "OnBodyFileDrop"))
        this.ui.OnEvent("BodyInput", "Drop", ObjBindMethod(this, "OnBodyFileDrop"))
        this.ui.OnEvent("SubmitBtn", "Click", ObjBindMethod(this, "OnSubmit"))
        this.ui.OnEvent("LoginBtn", "Click", ObjBindMethod(this, "OnLoginClick"))
        this.ui.OnEvent("OpenTopicBtn", "Click", ObjBindMethod(this, "OnOpenTopicClick"))
        this.ui.OnEvent("CancelBtn", "Click", ObjBindMethod(this, "OnCancelClick"))

        this._pollFn := ObjBindMethod(this, "_Poll")
        this._SyncKind()
        this._SyncEnv()
        this._SyncLoginBtn()

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
        else
            XamlWin.NudgeIfOff(this.ui, refWin)
    }

    _AddBtn(parent, name, content, width, primary := false) {
        btn := parent.Add("Button").Name(name).Content(content)
            .FontSize(12).Cursor("Hand").Width(width).Height(28)
            .BorderThickness("1")
        if (primary) {
            btn.Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
                .BorderBrush("{DynamicResource ActionStroke}").FontWeight("Bold")
            btn.InjectResources(this._btnPrimaryStyle)
        } else {
            btn.Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
                .BorderBrush("{DynamicResource EditStroke}")
            btn.InjectResources(this._btnStyle)
        }
        return btn
    }

    OnWindowLoad(state := unset, ctrl := unset, event := unset) {
        if (this._prefillBody != "")
            try this.ui.Update("BodyInput", "Text", this._prefillBody)
        ; 骨架与提示要等窗口起来后才有 Query 可用
        this._SyncContent()
        ; 拖放目标要等控件树起来再开，太早下发会被丢掉
        try this.ui.Update("BodyInput", "EnableDropTarget", "RMTFeedbackImage")
        try {
            XamlWin.OnLoadTheme(this.ui)
        }
        try this.ui.Update("Window", "Opacity", "1")
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        this._StopPoll()
        this._StopLoginTimer()
        FeedbackGui._opening := false
        if (FeedbackGui.instances.Has("global"))
            FeedbackGui.instances.Delete("global")
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnCancelClick(state := unset, ctrl := unset, event := unset) {
        if (this._done) {
            this.Close()
            return
        }
        if (this._pending != "") {
            this._SetStatus(GetLang("正在提交，等结果出来再关窗口"))
            return
        }
        ; 写了东西还没发，别一个误点就丢
        if (this._IsDirty()) {
            owner := 0
            try owner := this.ui.wpfHwnd
            if (!RmtDialog.Confirm(GetLang("内容还没提交，关掉就没了。确定关闭？"), GetLang("关闭反馈"), owner))
                return
        }
        this.Close()
    }

    _IsDirty() {
        title := "", body := ""
        try title := Trim(String(this.ui.Query("TitleInput>Text")))
        try body := Trim(String(this.ui.Query("BodyInput>Text")))
        if (title != "")
            return true
        return (body != "" && !FeedbackGui._LooksEmptyTemplate(body))
    }

    Close() {
        this.closed := true
        this._StopPoll()
        this._StopLoginTimer()
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    OnOpenTopicClick(state := unset, ctrl := unset, event := unset) {
        if (this._openUrl != "")
            try Run(this._openUrl)
    }

    ; ===== 类型 / 环境信息开关 =====

    OnKindClick(kind, state := unset, ctrl := unset, event := unset) {
        this._SetKind(kind)
    }

    _SetKind(kind) {
        this._kind := (kind = "idea") ? "idea" : "bug"
        this._SyncKind()
        this._SyncContent()
    }

    _SyncKind() {
        if (!IsObject(this.ui))
            return
        this._SyncToggle("KindBug", this._kind = "bug")
        this._SyncToggle("KindIdea", this._kind = "idea")
    }

    ; 描述框骨架跟着类型走（窗口标题固定，避免和类型按钮重复）
    _SyncContent() {
        if (!IsObject(this.ui) || this._done)
            return
        this._ApplyTemplate()
    }

    _KindTemplate() {
        if (this._kind = "idea")
            return "**使用场景**`n`n`n`n**期望能力**`n`n`n`n**为什么需要**（可选）`n`n"
        return "**复现步骤**`n1. `n2. `n`n**期望结果**`n`n`n`n**实际表现**`n`n"
    }

    ; 只填空描述框，或替换上一次自动写入的骨架；用户自己写过就不动
    _ApplyTemplate() {
        if (this._prefillBody != "" || this._done)
            return
        cur := ""
        try cur := String(this.ui.Query("BodyInput>Text"))
        tpl := this._KindTemplate()
        if (Trim(cur) != "" && FeedbackGui._NormTpl(cur) != FeedbackGui._NormTpl(this._autoTpl))
            return
        if (FeedbackGui._NormTpl(cur) == FeedbackGui._NormTpl(tpl))
            return
        this._autoTpl := tpl
        try this.ui.Update("BodyInput", "Text", tpl)
    }

    ; 去掉 Markdown 星号与空白后比较，避开 TextBox 回读时换行符差异
    static _NormTpl(s) {
        return RegExReplace(String(s), "[*\s]", "")
    }

    ; 只有骨架、一个字没补
    static _LooksEmptyTemplate(s) {
        t := RegExReplace(Trim(String(s)), "[*\s]", "")
        return (t == "复现步骤1.2.期望结果实际表现" || t == "使用场景期望能力为什么需要（可选）")
    }

    OnEnvClick(state := unset, ctrl := unset, event := unset) {
        this._keepEnv := this._keepEnv ? 0 : 1
        this._SyncEnv()
    }

    _SyncEnv() {
        if (!IsObject(this.ui) || this._done)
            return
        this._SyncToggle("EnvBtn", this._keepEnv)
        ; 用勾选表达开关，文案长度不变，按钮不会跳宽
        try this.ui.Update("EnvBtn", "Content", (this._keepEnv ? "✓ " : "") GetLang("附带环境信息"))
        try this.ui.Update("EnvText", "Text", this._keepEnv ? this._EnvPreview() : GetLang("不附带"))
    }

    ; 选中态配色沿用指令窗口那套 Action 色，不引入新变量
    _SyncToggle(name, on) {
        if (on) {
            try this.ui.Update(name, "Background", "{DynamicResource ActionBg}")
            try this.ui.Update(name, "BorderBrush", "{DynamicResource ActionStroke}")
            try this.ui.Update(name, "Foreground", "{DynamicResource ActionText}")
        } else {
            try this.ui.Update(name, "Background", "{DynamicResource EditBg}")
            try this.ui.Update(name, "BorderBrush", "{DynamicResource EditStroke}")
            try this.ui.Update(name, "Foreground", "{DynamicResource EditText}")
        }
    }

    ; 三态：未登录=可点「登录论坛」；已登录=灰掉「已登录」（不要重复弹授权）；凭据失效=可点「重新登录」
    _SyncLoginBtn() {
        if (!IsObject(this.ui) || this._done)
            return
        hasKey := (GetShareApiKey() != "")
        logged := (hasKey && !this._relogin)
        if (!hasKey)
            label := GetLang("登录论坛")
        else if (this._relogin)
            label := GetLang("重新登录")
        else
            label := GetLang("已登录")
        try this.ui.Update("LoginBtn", "Content", label)
        try this.ui.Update("LoginBtn", "IsEnabled", logged ? "False" : "True")
        try this.ui.Update("LoginBtn", "ToolTip", logged
            ? GetLang("已登录，可直接提交；要换账号请到 设置 → 共享 退出后重新登录")
            : (this._relogin
                ? GetLang("凭据失效了，点这里重新授权")
                : GetLang("在浏览器里登录论坛并点授权，以后提交就不用再填账号")))
    }

    ; ===== 正文里的图片（Markdown 直插，没有单独的附件栏） =====

    ; 正文框里 Ctrl+V：剪贴板是图就存盘并插一行 ![名](路径)；不是图就交给 TextBox 自己粘文本
    OnBodyPasteKey(state := unset, ctrl := unset, event := unset) {
        if (this._done)
            return
        mods := ""
        if (IsObject(state) && state.Has("KeyModifiers"))
            mods := String(state["KeyModifiers"])
        if (!InStr(mods, "Ctrl") || InStr(mods, "Shift") || InStr(mods, "Alt"))
            return
        if (!DllCall("IsClipboardFormatAvailable", "uint", 2) && !DllCall("IsClipboardFormatAvailable", "uint", 8))
            return
        path := this._SaveClipImage()
        if (path == "")
            return
        this._InsertMdImgs([path])
    }

    ; 把图片文件拖进正文框
    OnBodyFileDrop(state := unset, ctrl := unset, event := unset) {
        if (!IsObject(state))
            return
        raw := ""
        if (state.Has("FileDrop"))
            raw := String(state["FileDrop"])
        else if (state.Has("Drop"))
            raw := String(state["Drop"])
        if (raw == "")
            return
        paths := []
        for part in StrSplit(raw, "|") {
            p := Trim(part, " `t")
            if (p != "" && FileExist(p) && FeedbackGui._IsImg(p))
                paths.Push(p)
        }
        if (paths.Length = 0)
            return
        this._InsertMdImgs(paths)
    }

    ; 插在光标处，前后补换行，保证是独立一段
    _InsertMdImgs(paths) {
        if (!IsObject(this.ui) || this._done)
            return
        text := "", caret := 0
        try text := String(this.ui.Query("BodyInput>Text"))
        try caret := Integer(this.ui.Query("BodyInput>CaretIndex"))
        if (caret < 0 || caret > StrLen(text))
            caret := StrLen(text)
        block := ""
        for p in paths {
            name := ""
            SplitPath p, &name
            if (InStr(p, " "))
                block .= "![" name "](<" p ">)`n"
            else
                block .= "![" name "](" p ")`n"
        }
        pre := SubStr(text, 1, caret)
        post := SubStr(text, caret + 1)
        if (pre != "" && SubStr(pre, -1) != "`n")
            block := "`n" block
        if (post != "" && SubStr(post, 1, 1) != "`n")
            block .= "`n"
        try this.ui.Update("BodyInput", "InsertText", block)
        try this.ui.Update("BodyInput", "Focus", "True")
        ; 正文里已经能看到插入的 ![名](路径)，不再额外占用状态行
        this._SetStatus("")
    }

    static _IsImg(path) {
        return !!RegExMatch(path, "i)\.(png|jpe?g|bmp|gif|webp)$")
    }

    ; 正文里指向本地文件的 ![alt](路径)，提交前扫出来逐张上传
    _ScanBodyImgs(body) {
        imgs := []
        pos := 1
        while (pos := RegExMatch(body, "!\[([^\]\r\n]*)\]\(\s*(?:<([^>\r\n]+)>|([^)\r\n]+))\s*\)", &m, pos)) {
            alt := m[1]
            p := Trim((m[2] != "") ? m[2] : m[3], " `t")
            raw := m[0]
            pos += StrLen(raw)
            ; 已经是论坛地址/协议头的跳过，只处理指向本地文件的图
            if (RegExMatch(p, "i)^(https?:|//|data:|mailto:|upload:)"))
                continue
            if (!FeedbackGui._IsImg(p) || !FileExist(p))
                continue
            imgs.Push({ path: p, alt: alt, raw: raw, url: "", failed: false })
        }
        return imgs
    }

    ; 静默存剪贴板位图：SaveClipToBitmap 会弹 RMTErrorShow，这里自己用 GDI+ 存到临时目录
    _SaveClipImage() {
        dir := A_Temp "\RMTFeedback"
        if (!DirExist(dir))
            try DirCreate(dir)
        if (!DirExist(dir))
            return ""
        path := dir "\" FormatTime(A_Now, "yyyyMMdd-HHmmss") "-" A_MSec ".png"
        pBitmap := 0
        try pBitmap := Gdip_CreateBitmapFromClipboard()
        if (!pBitmap)
            return ""
        ok := 0
        try {
            Gdip_SaveBitmapToFile(pBitmap, path)
            ok := FileExist(path) ? 1 : 0
        }
        Gdip_DisposeImage(pBitmap)
        return ok ? path : ""
    }

    ; ===== 提交 =====

    OnSubmit(state := unset, ctrl := unset, event := unset) {
        if (!IsObject(this.ui))
            return
        if (this._pending != "") {
            this._SetStatus(GetLang("正在提交，请稍候"))
            return
        }
        title := Trim(String(this.ui.Query("TitleInput>Text")))
        body := Trim(String(this.ui.Query("BodyInput>Text")))
        if (StrLen(title) < 4) {
            this._SetStatus(GetLang("标题太短：一句话说清是什么问题（至少 4 个字）"), "err")
            return
        }
        if (StrLen(body) < 10) {
            this._SetStatus(GetLang("描述太短，请把复现步骤或使用场景写清楚一点"), "err")
            return
        }
        if (FeedbackGui._LooksEmptyTemplate(body)) {
            this._SetStatus(GetLang("描述里还只有骨架，把步骤或场景补上再提交"), "err")
            return
        }
        apiKey := GetShareApiKey()
        if (apiKey == "") {
            this._resumeSubmit := true
            this._BeginLogin()
            return
        }
        this._DoSubmit(title, body, apiKey)
    }

    _DoSubmit(title, body, apiKey) {
        global RMT_Discourse
        this._ResetResult()
        this._SetBusy(true)
        try disc := GetDiscourse()
        catch as e {
            this._SetBusy(false)
            this._SetStatus(e.Message, "err")
            return
        }
        apiUser := GetShareApiUser()
        try RMT_Discourse.SetAuth(apiUser, apiKey)
        this._baseUrl := GetShareServerUrl()
        this._titleSent := title
        this._bodySent := body
        this._titleRetried := 0
        ; 正文里的本地图片先扫出来，逐张上传，传完把路径换成论坛地址
        this._imgs := this._ScanBodyImgs(body)
        if (this._imgs.Length > FeedbackGui.MaxImgs) {
            n := this._imgs.Length
            this._imgs := []
            this._SetBusy(false)
            this._SetStatus(Format(GetLang("正文里有 {1} 张本地图，一次最多 {2} 张，先删掉几张再提交"), n, FeedbackGui.MaxImgs), "err")
            return
        }
        this._UploadNext()
    }

    ; 逐张上传：每张成功后在 _Poll 里写 url 并回来接着传下一张
    _UploadNext() {
        global RMT_Discourse
        idx := 0
        for i, it in this._imgs {
            if (it.url == "" && !it.failed) {
                idx := i
                break
            }
        }
        if (idx = 0) {
            this._BeginPost()
            return
        }
        this._upIdx := idx
        this._pending := "upload"
        this._pendingSince := 0
        this._SetStatus(Format(GetLang("正在上传第 {1}/{2} 张图..."), idx, this._imgs.Length))
        try RMT_Discourse.BeginUploadFile(this._baseUrl "/uploads.json", this._imgs[idx].path)
        catch as e {
            this._pending := ""
            this._ReplaceImgRef(idx, "")
            this._SetStatus(e.Message, "err")
            this._UploadNext()
            return
        }
        this._StartPoll()
    }

    ; 把正文里那张图的本地路径换成论坛地址；传不上就换一句说明，别在帖子里留坏链
    _ReplaceImgRef(idx, url) {
        if (idx < 1 || idx > this._imgs.Length)
            return
        it := this._imgs[idx]
        if (url != "") {
            it.url := url
            this._bodySent := StrReplace(this._bodySent, it.raw, "![" it.alt "](" url ")")
            return
        }
        it.failed := true
        name := (it.alt != "") ? it.alt : it.path
        this._bodySent := StrReplace(this._bodySent, it.raw, "（" GetLang("图片上传失败：") name "）")
    }

    _BeginPost() {
        global RMT_Discourse
        raw := this._BuildRaw()
        catId := GetFeedbackCategoryId(this._kind)
        this._pending := "post"
        this._pendingSince := 0
        this._SetStatus(GetLang("正在提交..."))
        try RMT_Discourse.BeginCreatePost(this._baseUrl "/posts.json", this._titleSent, raw, catId, "")
        catch as e {
            this._pending := ""
            this._SetBusy(false)
            this._SetStatus(e.Message, "err")
            return
        }
        this._StartPoll()
    }

    _BuildRaw() {
        global RMT_VERSION_DISPLAY
        ; 图片已经写在正文里（上传后路径已替换成论坛地址），这里只补环境信息
        raw := this._bodySent
        raw .= "`n`n"
        if (!this._keepEnv)
            return raw
        sys := this._SysText()
        scale := Round(A_ScreenDPI * 100 / 96)
        arch := (A_PtrSize = 8) ? "x64" : "x86"
        raw .= "---`n`n**运行环境**`n`n"
        raw .= "- 版本：RMTv" RMT_VERSION_DISPLAY "`n"
        raw .= "- 系统：" sys "`n"
        raw .= "- 屏幕：" A_ScreenWidth "×" A_ScreenHeight "，缩放 " scale "%`n"
        raw .= "- 架构：" arch
        return raw
    }

    _SysText() {
        prod := "", disp := "", build := ""
        key := "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        try prod := RegRead(key, "ProductName")
        try disp := RegRead(key, "DisplayVersion")
        try build := RegRead(key, "CurrentBuildNumber")
        if (prod == "")
            prod := A_OSVersion
        s := prod
        if (disp != "")
            s .= " " disp
        if (build != "")
            s .= " (" build ")"
        return s
    }

    _EnvPreview() {
        global RMT_VERSION_DISPLAY
        sys := this._SysText()
        if (RegExMatch(sys, "i)Windows\s+(\d+)", &m))
            sys := "Win" m[1]
        return "RMTv" RMT_VERSION_DISPLAY " · " sys " · " A_ScreenWidth "×" A_ScreenHeight
    }

    ; ===== 登录（与设置页同一套 UserApiKey 授权） =====

    OnLoginClick(state := unset, ctrl := unset, event := unset) {
        ; 已登录且凭据没被判失效：不重复走授权流程
        if (this._loginTick == "" && GetShareApiKey() != "" && !this._relogin) {
            this._SetStatus(GetLang("已登录论坛，无需重复授权"), "ok")
            return
        }
        this._BeginLogin()
    }

    _BeginLogin() {
        if (this._loginTick != "") {              ; 等待中再点 = 取消
            this._StopLoginTimer()
            try GetDiscourse().CancelUserAuth()
            this._SetStatus(GetLang("已取消登录"))
            return
        }
        try GetDiscourse().BeginUserAuth(GetShareServerUrl())
        catch as e {
            this._SetStatus(GetLang("无法开始授权：") e.Message, "err")
            return
        }
        this._SetStatus(GetLang("已打开浏览器，请登录论坛并点「授权」…（再点「登录论坛」可取消）"))
        this._loginTick := ObjBindMethod(this, "PollLogin")
        SetTimer(this._loginTick, 300)
    }

    _StopLoginTimer() {
        if (this._loginTick != "") {
            try SetTimer(this._loginTick, 0)
            this._loginTick := ""
        }
    }

    PollLogin() {
        st := 0
        try st := Integer(GetDiscourse().GetAuthState())
        catch {
            this._StopLoginTimer()
            this._SetStatus(GetLang("授权失败，请重试"), "err")
            return
        }
        if (st = 1)
            return
        this._StopLoginTimer()
        if (st != 2) {
            this._SetStatus(GetLang("已取消授权"))
            return
        }
        raw := "", err := ""
        try raw := GetDiscourse().TakeAuthResult()
        try err := GetDiscourse().GetAuthError()
        key := ""
        if (raw != "" && RegExMatch(raw, '"key"\s*:\s*"([^"]+)"', &m))
            key := m[1]
        if (key == "") {
            reason := (err != "") ? err : GetLang("授权页未返回凭据")
            this._SetStatus(GetLang("授权失败：") reason, "err")
            return
        }
        ; 用户密钥模式：用户名留空，C# 侧据此发 User-Api-Key
        SetShareAuth("", key)
        this._relogin := false
        this._SyncLoginBtn()
        this._SetStatus(GetLang("已登录论坛"), "ok")
        if (this._resumeSubmit) {
            this._resumeSubmit := false
            this.OnSubmit()
        }
    }

    ; ===== 轮询 =====

    _StartPoll() {
        if (IsObject(this._pollFn))
            SetTimer(this._pollFn, 150)
    }

    _StopPoll() {
        if (IsObject(this._pollFn))
            try SetTimer(this._pollFn, 0)
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
            this._SetBusy(false)
            return
        }
        if (this._pendingSince == 0)
            this._pendingSince := A_TickCount
        elapsedMs := A_TickCount - this._pendingSince
        if (elapsedMs > 120000) {
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            this._SetBusy(false)
            this._SetStatus(GetLang("等太久了，请求超时。检查网络后再试一次"), "err")
            return
        }
        elapsedSec := elapsedMs // 1000

        if (this._pending == "upload") {
            st := 0
            try st := Integer(RMT_Discourse.GetUploadState())
            if (st == 1) {
                if (Mod(elapsedSec, 2) == 0)
                    this._SetStatus(Format(GetLang("正在上传第 {1}/{2} 张图..."), this._upIdx, this._imgs.Length) " (" elapsedSec "s)")
                return
            }
            this._pending := ""
            this._pendingSince := 0
            this._StopPoll()
            idx := this._upIdx
            body := ""
            try body := RMT_Discourse.TakeUploadResult()
            if (body == "") {
                err := ""
                try err := RMT_Discourse.GetUploadError()
                ; 单张失败不阻断：把正文里那一行换成说明，接着传下一张
                this._ReplaceImgRef(idx, "")
                this._SetStatus(Format(GetLang("第 {1} 张图没传上，先跳过（正文照发）："), idx) FeedbackGui._ErrText(err))
                this._UploadNext()
                return
            }
            ; 图片地址必须用 upload://（short_url）或完整 url。
            ; short_path（/uploads/short-url/xxx.png）只有浏览器靠 302 能打开，
            ; Discourse 后台 cook 时按 upload 记录查不到，会把图替换成「此图片已损坏」。
            url := ""
            try {
                obj := JSON.parse(body)
                su := obj.Has("short_url") ? String(obj["short_url"]) : ""
                if (SubStr(su, 1, 9) == "upload://")
                    url := su
                else if (obj.Has("url") && obj["url"] != "")
                    url := obj["url"]
                else if (su != "")
                    url := su
                else if (obj.Has("short_path") && obj["short_path"] != "")
                    url := obj["short_path"]
            }
            this._ReplaceImgRef(idx, url)
            this._UploadNext()
            return
        }

        if (this._pending == "post") {
            st := 0
            try st := Integer(RMT_Discourse.GetPostState())
            if (st == 1) {
                if (Mod(elapsedSec, 2) == 0)
                    this._SetStatus(GetLang("正在提交...") " (" elapsedSec "s)")
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
                ; 站点禁止重名标题：撞了就自动加个时间后缀重发一次，别让用户自己改
                if (!this._titleRetried && InStr(err, "已被") && InStr(err, "使用")) {
                    this._titleRetried := 1
                    this._titleSent .= "（" FormatTime(A_Now, "yyyy-MM-dd HH:mm") "）"
                    this._BeginPost()
                    return
                }
                ; 凭据失效 / 无权发帖：恢复「重新登录」，授权成功后接着提交
                if (FeedbackGui._IsAuthError(err)) {
                    this._relogin := true
                    this._resumeSubmit := true
                    this._SyncLoginBtn()
                    this._SetBusy(false)
                    this._SetStatus(GetLang("登录已失效或没有发帖权限，请点「重新登录」授权：") FeedbackGui._ErrText(err), "err")
                    return
                }
                this._SetBusy(false)
                this._SetStatus(GetLang("提交失败：") FeedbackGui._ErrText(err), "err")
                return
            }
            topicId := "", topicSlug := ""
            try {
                obj := JSON.parse(body)
                topicId := obj.Has("topic_id") ? String(obj["topic_id"]) : ""
                topicSlug := obj.Has("topic_slug") ? String(obj["topic_slug"]) : ""
            }
            url := this._baseUrl
            if (topicSlug != "" && topicId != "")
                url .= "/t/" topicSlug "/" topicId
            else if (topicId != "")
                url .= "/t/" topicId
            if (topicId == "") {
                this._SetDone(GetLang("已提交，只是没取到帖子地址。可以到论坛「反馈」分类里看新帖。"), "")
                return
            }
            this._SetDone(GetLang("提交成功！新用户的首帖可能需要版主审核后才会公开显示。"), url)
        }
    }

    ; ===== 状态区 =====

    _SetStatus(text, kind := "") {
        if (!IsObject(this.ui))
            return
        prefix := (kind == "ok") ? "✓ " : (kind == "err") ? "✗ " : ""
        fg := (kind == "") ? "{DynamicResource TextSub}" : "{DynamicResource TextMain}"
        try this.ui.Update("StatusText", "Foreground", fg)
        try this.ui.Update("StatusText", "Text", prefix text)
        ; 状态区高度有限，长错误会被截断，悬停看全文
        try this.ui.Update("StatusText", "ToolTip", prefix text)
    }

    ; 提交中锁住按钮，避免重复点
    _SetBusy(on) {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("SubmitBtn", "Content", on ? GetLang("提交中…") : GetLang("提交反馈"))
        try this.ui.Update("SubmitBtn", "IsEnabled", on ? "False" : "True")
        if (on) {
            try this.ui.Update("LoginBtn", "IsEnabled", "False")
        } else {
            this._SyncLoginBtn()
        }
    }

    ; 成功后：收起提交/登录，输入只读，按钮变「关闭」
    _SetDone(text, url) {
        this._done := true
        this._openUrl := url
        this._SetBusy(false)
        ; 地址不写进状态行（点「打开帖子」就能看），一行文字省一截高度
        this._SetStatus(text, "ok")
        try this.ui.Update("SubmitBtn", "Visibility", "Collapsed")
        try this.ui.Update("LoginBtn", "Visibility", "Collapsed")
        try this.ui.Update("OpenTopicBtn", "Visibility", url = "" ? "Collapsed" : "Visible")
        try this.ui.Update("CancelBtn", "Content", GetLang("关闭"))
        try this.ui.Update("TitleInput", "IsReadOnly", "True")
        try this.ui.Update("BodyInput", "IsReadOnly", "True")
    }

    _ResetResult() {
        this._openUrl := ""
        try this.ui.Update("StatusText", "Text", "")
        try this.ui.Update("StatusText", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("OpenTopicBtn", "Visibility", "Collapsed")
    }

    ; 去掉 C# 侧的步骤标记（[D3]/[D4]…）再给用户看
    static _ErrText(raw) {
        s := String(raw)
        s := RegExReplace(s, "^\[D\d\]\s*", "")
        return Trim(s)
    }

    ; 判断是不是「凭据失效 / 无发帖权限」这类需要重新授权的情况
    static _IsAuthError(raw) {
        s := String(raw)
        if (s == "")
            return false
        if (InStr(s, "401") || InStr(s, "403"))
            return true
        for w in ["未登录", "没有权限", "无权", "需要登录", "invalid_access", "not permitted", "revoked"]
            if (InStr(s, w))
                return true
        return false
    }
}
