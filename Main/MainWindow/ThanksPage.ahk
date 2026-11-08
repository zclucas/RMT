
    ; ============ 特别感谢页 ============
    BuildThankTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Thank 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Thank")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        wall := '<Border ' ns ' Margin="0,2,0,14" Padding="16,14" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource Accent}" BorderThickness="1.25" CornerRadius="8"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE734;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="15" Margin="0,0,8,0"/><TextBlock Text="' this._XmlEsc(GetLang("若梦星河")) '" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Text="' this._XmlEsc(GetLang("这里会逐步收录支持者留言、开发者贡献与开源项目，也会记录让 RMT 持续成长的每一份善意与协作。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,16,0"/><TextBlock Text="' this._XmlEsc(GetLang("提示：收录数据会在版本更新时统一更新。")) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,5,0,0"/></StackPanel><Border Grid.Column="1" VerticalAlignment="Center" Margin="10,0,0,0">' this._ThankLinkButton("https://docs.ruomengtu.com/supporters/", GetLang("打开若梦星河"), "&#xE734;") '</Border></Grid></Border>'
        Add(wall)
        Add('<ContentControl ' ns ' Name="ThankSponsorHost" HorizontalAlignment="Stretch" HorizontalContentAlignment="Stretch" Visibility="Collapsed"/>')

        dev := '<Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._ThankContributor(0, 0, "yun", "yun", this._GetBuiltInThankAvatar("yun"), "https://github.com/yunkuangao", "0,0,5,5")
            . this._ThankContributor(0, 1, "boxstudy", "B", this._GetBuiltInThankAvatar("boxstudy"), "https://github.com/boxstudy", "5,0,5,5")
            . this._ThankContributor(0, 2, "sovaedv776", "S", this._GetBuiltInThankAvatar("sovaedv776"), "https://github.com/sovaedv776", "5,0,0,5")
            . this._ThankContributor(1, 0, "张正波", "张", "", "https://gitee.com/bogezzb", "0,5,5,0")
            . this._ThankContributor(1, 1, "GushuLily", "G", this._GetBuiltInThankAvatar("gushulily"), "https://github.com/GushuLily", "5,5,5,0")
            . this._ThankContributor(1, 2, "T8numen", "T", this._GetBuiltInThankAvatar("t8numen"), "https://github.com/T8numen", "5,5,0,0")
            . '</Grid>'

        oss := '<Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._ThankProject(0, 0, "&#xE8BD;", "Discourse", "为 RMT 社区论坛提供支持。", "https://github.com/discourse/discourse", "0,0,5,5")
            . this._ThankProject(0, 1, "&#xE720;", "sherpa-onnx", "为 RMT 语音关键词识别提供支持。", "https://github.com/k2-fsa/sherpa-onnx", "5,0,0,5")
            . this._ThankProject(1, 0, "&#xE91B;", "OpenCV", "视觉识别与图像处理能力。", "https://github.com/opencv/opencv", "0,5,5,5")
            . this._ThankProject(1, 1, "&#xE8B7;", "ahk2_lib", "AutoHotkey v2 基础工具库。", "https://github.com/thqby/ahk2_lib", "5,5,0,5")
            . this._ThankProject(2, 0, "&#xE8A9;", "RapidOCR", "本地文字识别能力。", "https://github.com/RapidAI/RapidOCR", "0,5,5,0")
            . this._ThankProject(2, 1, "&#xE7FC;", "ViGEm Bus", "虚拟手柄支持。", "https://github.com/nefarius/ViGEmBus", "5,5,0,0")
            . '</Grid>'

        cocreate := '<StackPanel>'
            . this._ThankInfoBlock("&#xE8D7;", GetLang("感谢若梦兔守护者的支持与陪伴。每一份信任都让 RMT 能够持续维护、不断成长。"), "0,0,0,7")
            . this._ThankInfoBlock("&#xE946;", GetLang("有效的 Bug 反馈与需求建议、社区答疑和配置分享，都是 RMT 的共创力量。参与的伙伴会收录在若梦星河。"), "0")
            . '</StackPanel>'
        community := '<StackPanel><TextBlock Text="' this._XmlEsc(GetLang("感谢在社区中积极交流、提出建议、协助答疑的每一位群友。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,0,0,9"/><WrapPanel>'
            . this._ThankNickname("AYu") this._ThankNickname("万年置伞") this._ThankNickname("别说*不下啦") this._ThankNickname("仰望") this._ThankNickname("话听") this._ThankNickname("yun") this._ThankNickname("小足")
            . '</WrapPanel></StackPanel>'

        layout := '<Grid ' ns ' Margin="0,0,0,14"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="1.55*"/><ColumnDefinition Width="0.85*"/></Grid.ColumnDefinitions><Border Grid.Row="0" Grid.Column="0" Margin="0,0,7,7">'
            . this._HelpCard(GetLang("开发贡献者"), "&#xE77B;", dev, GetLang("感谢同行"), "0", false, 30)
            . '</Border><Border Grid.Row="1" Grid.Column="0" Margin="0,7,7,0">'
            . this._HelpCard(GetLang("开源项目支持"), "&#xE8B7;", oss, GetLang("致谢以下开源项目"), "0", false, 30)
            . '</Border><Border Grid.Row="0" Grid.Column="1" Margin="7,0,0,7">'
            . this._HelpCard(GetLang("守护与共创"), "&#xE8D4;", cocreate, "", "0", false, 30)
            . '</Border><Border Grid.Row="1" Grid.Column="1" Margin="7,7,0,0" VerticalAlignment="Top">'
            . this._HelpCard(GetLang("社区活跃伙伴"), "&#xE902;", community, GetLang("QQ 昵称"), "0", false, 30)
            . '</Border></Grid>'
        Add(layout)
        this._thankReady := true
        this._FlushLinks()
        this.ApplyThankSponsors()
    }

    ; 有赞助时显示在开发贡献者上方。回包晚于页面构建时，由 ApplyRMTServerRsp 再调用。
    ApplyThankSponsors() {
        global RMT_Sponsors
        if (!this._thankReady || this._thankSponsorShown)
            return
        if (!IsSet(RMT_Sponsors) || !(RMT_Sponsors is Array) || RMT_Sponsors.Length < 1)
            return
        queued := this._linkQueue.Length
        shown := []
        for sp in RMT_Sponsors {
            localPath := EnsureSponsorLogo(sp.Has("logo") ? sp["logo"] : "")
            if (localPath == "")
                continue
            shown.Push(Map(
                "name", sp.Has("name") ? sp["name"] : "",
                "logo", StrReplace(localPath, "\", "/"),
                "url", sp.Has("url") ? sp["url"] : ""
            ))
        }
        if (shown.Length < 1)
            return
        ; 「感谢支持」与「QQ 昵称」同走提示文字：字号 11、常规字重
        body := '<StackPanel Name="ThankSponsorLogos" HorizontalAlignment="Stretch"/>'
        card := this._HelpCard(GetLang("企业赞助"), "&#xE731;", body, GetLang("感谢支持"), "0,0,0,14", false, 30)
        try {
            this.ui.Update("ThankSponsorHost", "AddXamlItem", card)
            this.ui.Update("ThankSponsorHost", "Visibility", "Visible")
        } catch {
            while (this._linkQueue.Length > queued)
                this._linkQueue.Pop()
            return
        }
        this._thankSponsorShown := true
        ; logo 一次性交给引擎，分行与居中由引擎的 FlowLayout 完成：宽度变化时引擎自己重排，
        ; 这里不监听 SizeChanged，也不回读 ActualWidth。
        for sp in shown {
            try this.ui.Update("ThankSponsorLogos", "AddXamlItem", this._ThankSponsorLogo(sp))
        }
        try this.ui.Update("ThankSponsorLogos", "FlowLayout", "124")
        this._FlushLinks()
    }

    ; 无边框 100×100 logo，悬停时在指针上方弹出企业名称，点击打开链接
    _ThankSponsorLogo(sp) {
        name := sp["name"] != "" ? sp["name"] : GetLang("企业赞助")
        logo := sp["logo"]
        url := sp["url"]
        tip := '<Button.ToolTip><ToolTip Placement="Mouse" HorizontalOffset="12" VerticalOffset="-32" Padding="8,3" FontSize="11" Background="{DynamicResource ControlBg}" Foreground="{DynamicResource TextMain}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><TextBlock Text="' this._XmlEsc(name) '" FontSize="11"/></ToolTip></Button.ToolTip>'
        img := '<Image Width="100" Height="100" Source="' this._XmlEsc(logo) '" Stretch="Uniform"/>'
        tpl := '<Button.Template><ControlTemplate TargetType="Button"><ContentPresenter/></ControlTemplate></Button.Template>'
        cursor := "Arrow"
        btnName := ""
        if (url != "") {
            this._linkCounter := this._linkCounter + 1
            btnName := "ThankSponsor_" this._linkCounter
            this._linkQueue.Push({ name: btnName, url: url, event: "Click" })
            cursor := "Hand"
        }
        nameAttr := btnName == "" ? "" : ' Name="' btnName '"'
        return '<Button' nameAttr ' Cursor="' cursor '" Background="Transparent" BorderThickness="0" Padding="0" Margin="12,8" FocusVisualStyle="{x:Null}">' tpl tip img '</Button>'
    }

    _ThankLinkButton(url, text, glyph := "&#xE8A7;") {
        this._linkCounter := this._linkCounter + 1
        name := "ThankLink_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        return '<Button Name="' name '" Cursor="Hand" MinHeight="35" Padding="15,7" VerticalContentAlignment="Center" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1">' this._ThankSoftHoverTemplate() '<StackPanel Orientation="Horizontal"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" Margin="0,0,6,0" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(text) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/><TextBlock Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="9" Foreground="{DynamicResource Accent}" Margin="6,0,0,0" VerticalAlignment="Center"/></StackPanel></Button>'
    }

    ; 特别感谢页的可点击卡片沿用设置左侧分类的柔和悬停底色，避免默认按钮高亮过重。
    _ThankSoftHoverTemplate() {
        return '<Button.Template><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListAltBg}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Button.Template>'
    }

    _ThankContributor(row, col, title, initial, image, url, margin) {
        this._linkCounter := this._linkCounter + 1
        name := "ThankContributor_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        avatar := image == "" ? '<Border Width="30" Height="30" CornerRadius="15" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><TextBlock Text="' this._XmlEsc(initial) '" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>' : '<Ellipse Width="30" Height="30" Stroke="{DynamicResource OutlineStroke}" StrokeThickness="1"><Ellipse.Fill><ImageBrush ImageSource="' image '" Stretch="UniformToFill"/></Ellipse.Fill></Ellipse>'
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Margin="' margin '" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><Button Name="' name '" Cursor="Hand" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch">' this._ThankSoftHoverTemplate() '<Grid Margin="9,7"><Grid.ColumnDefinitions><ColumnDefinition Width="37"/><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/></Grid.ColumnDefinitions>' avatar '<StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="' this._XmlEsc(title) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(GetLang("项目贡献者")) '" FontSize="9" Foreground="{DynamicResource TextSub}" Margin="0,2,0,0"/></StackPanel><TextBlock Grid.Column="2" Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid></Button></Border>'
    }

    _ThankProject(row, col, glyph, title, description, url, margin) {
        this._linkCounter := this._linkCounter + 1
        name := "ThankProject_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Margin="' margin '" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><Button Name="' name '" Cursor="Hand" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch">' this._ThankSoftHoverTemplate() '<Grid Margin="10,8"><Grid.ColumnDefinitions><ColumnDefinition Width="36"/><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/></Grid.ColumnDefinitions><Border Width="28" Height="28" CornerRadius="6" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="' this._XmlEsc(title) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(GetLang(description)) '" TextWrapping="Wrap" FontSize="9" Foreground="{DynamicResource TextSub}" Margin="0,2,0,0"/></StackPanel><TextBlock Grid.Column="2" Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid></Button></Border>'
    }

    _ThankInfoBlock(glyph, text, margin := "0") {
        return '<Border Margin="' margin '" Padding="10" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource Accent}" VerticalAlignment="Top"/><TextBlock Grid.Column="1" Text="' this._XmlEsc(text) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource TextMain}"/></Grid></Border>'
    }

    _ThankNickname(text) {
        return '<Border Margin="0,0,7,7" Padding="8,4" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><TextBlock Text="' this._XmlEsc(text) '" FontSize="10" Foreground="{DynamicResource TextMain}"/></Border>'
    }

    _GetBuiltInThankAvatar(id) {
        static paths := Map()
        ; 静态表：id -> [源文件名, 临时文件名]
        static files := Map(
            "yun",        ["yun.jpg",        "RMT_Thank_yun.jpg"],
            "boxstudy",   ["boxstudy.jpg",   "RMT_Thank_boxstudy.jpg"],
            "sovaedv776", ["sovaedv776.png", "RMT_Thank_sovaedv776.png"],
            "gushulily",  ["gushulily.jpg",  "RMT_Thank_gushulily.jpg"],
            "t8numen",    ["t8numen.jpg",    "RMT_Thank_t8numen.jpg"])
        if (paths.Has(id))
            return paths[id]
        if (!files.Has(id))
            return ""
        f := files[id]
        rel := "Web\assets\thank-avatars\" f[1]
        tempPath := A_Temp "\" f[2]
        ; 只在临时文件不存在时才 FileInstall：同名临时图仍被上一轮实例的 WPF 持有时，
        ; 覆盖写会抛 Failed，而这个异常会中断整个 BuildThankTab（感谢页整页空白）。
        if (!FileExist(tempPath))
            try FileInstall(rel, tempPath, 1)
        out := FileExist(tempPath) ? tempPath : A_WorkingDir "\" rel
        if (!FileExist(out))
            return ""
        paths[id] := StrReplace(out, "\", "/")
        return paths[id]
    }

    _FlushLinks() {
        for item in this._linkQueue
            this._Bind(item.name, item.HasOwnProp("event") ? item.event : "MouseLeftButtonUp", ObjBindMethod(this, "OnLinkClick", item.url))
        this._linkQueue := []
    }
