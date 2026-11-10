
    ; ============ 帮助页 ============
    BuildHelpTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Help 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Help")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ; 先说明合法使用，再给出文档、社区与反馈入口。
        disclaimerRules := '<Grid Margin="10,8"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Border Grid.Row="0" Grid.Column="0" Margin="0,0,8,5" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("1", "本软件按“原样”提供。因使用、修改、传播或分发本软件所产生的风险与后果，由使用者自行承担；开发者不作任何明示或默示担保。") '</Border>'
            . '<Border Grid.Row="0" Grid.Column="1" Margin="8,0,0,5" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("2", "本软件仅限用于合法且已获授权的场景。严禁用于游戏作弊、未经授权的系统访问、数据篡改，或其他违反法律法规及第三方规则的行为。") '</Border>'
            . '<Border Grid.Row="1" Grid.Column="0" Margin="0,5,8,0" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("3", "使用前，请自行确认使用方式符合所在地法律法规、平台条款及相关约定。因违规使用而引发的损失、纠纷或责任，与开发者无关。") '</Border>'
            . '<Border Grid.Row="1" Grid.Column="1" Margin="8,5,0,0" Padding="8,6" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5">' this._HelpDisclaimerItem("4", "下载、安装或使用本软件，即表示你已充分理解并接受上述风险承诺：不将其用于任何非法目的，并同意不就他人滥用行为向开发者追责。") '</Border>'
            . '</Grid>'
        disclaimer := '<StackPanel><TextBlock Text="' this._XmlEsc(GetLang("本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力")) '" FontSize="10" Foreground="{DynamicResource TextSub}" Margin="0,0,0,8"/>'
            . disclaimerRules
            . '<TextBlock Text="' this._XmlEsc(GetLang("若不同意上述条款，请立即停止使用本软件。")) '" Foreground="{DynamicResource Accent}" FontWeight="Bold" FontSize="12" Margin="0,9,0,0"/></StackPanel>'
        Add(this._HelpCard(GetLang("免责声明与合法使用提醒"), "&#xE7BA;", disclaimer, "", "0,2,0,14", true))

        docs := '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Padding="0,0,12,0">' this._HelpResource("&#xE8A5;", GetLang("软件说明文档"), GetLang("快速上手、指令手册、命令行、常见问题、常见报错与更新日志。"), "https://docs.ruomengtu.com/", GetLang("打开文档")) '</Border>'
            . '<Border Grid.Column="1" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1,0,0,0" Padding="12,0">' this._HelpResource("&#xE714;", GetLang("更新视频合集"), GetLang("查看版本更新视频与直播交流问答。"), "https://www.bilibili.com/video/BV1yR8x6xEBW", GetLang("观看视频")) '</Border>'
            . '<Border Grid.Column="2" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1,0,0,0" Padding="12,0,0,0">' this._HelpResource("&#xE8B7;", GetLang("配置共享仓库"), GetLang("案例学习、获取他人分享的宏配置，并支持下载导入。"), "https://zclucas.github.io/RMT-Setting/", GetLang("查看仓库")) '</Border></Grid>'
        Add(this._HelpCard(GetLang("文档与学习"), "&#xE8A5;", docs, GetLang("从入门到进阶"), "0,0,0,14"))

        community := '<Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._HelpCommunityTile(0, 0, "&#xE902;", GetLang("RMT 交流论坛"), GetLang("经验交流、问题讨论与社区动态"), "https://forum.ruomengtu.com/", "0,0,5,5")
            . this._HelpCommunityTile(0, 1, "&#xE8BD;", GetLang("RMT QQ 交流群"), GetLang("加入群组以参与反馈文档编辑"), "https://qm.qq.com/q/DgpDumEPzq", "5,0,0,5")
            . this._HelpCommunityTile(1, 0, "&#xE943;", GetLang("GitHub 开源地址"), GetLang("查看发行版与软件最新版本"), "https://github.com/zclucas/RMT", "0,5,5,0")
            . this._HelpCommunityTile(1, 1, "&#xE8B7;", GetLang("Gitee 开源地址"), GetLang("镜像项目源代码与版本信息"), "https://gitee.com/fateman/RMT", "5,5,0,0")
            . '</Grid>'

        feedback := '<StackPanel><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._HelpFeedbackItem(0, "&#xE7BA;", GetLang("Bug 文档"), GetLang("提交可复现步骤、预期结果、实际表现，以及必要的截图或日志。"), "https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj", GetLang("打开 Bug 文档"), "0,0,5,0")
            . this._HelpFeedbackItem(1, "&#xE8F2;", GetLang("需求文档"), GetLang("描述使用场景、期望能力与优先级，帮助我们评估和规划。"), "https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo", GetLang("打开需求文档"), "5,0,0,0")
            . '</Grid>'
            . '<Border Margin="0,10,0,0">' this._HelpFeedbackItem(0, "&#xE8BD;", GetLang("在软件内直接提交"), GetLang("可直接向论坛提交反馈，支持多个附件，并自动附带版本号、系统和分辨率。"), "rmt:feedback", GetLang("立即反馈"), "0") '</Border>'
            . '<Border Margin="0,10,0,0" Padding="9,7" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" Margin="0,0,7,0"/><TextBlock Text="' this._XmlEsc(GetLang("Bug 文档和需求文档需要加入交流群后才可编辑；未加入时仍可打开查看现有内容。")) '" TextWrapping="Wrap" Foreground="{DynamicResource TextSub}" FontSize="11"/></StackPanel></Border></StackPanel>'

        lower := '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Grid.Column="0" Margin="0,0,7,0">'
            . this._HelpCard(GetLang("社区"), "&#xE8BD;", community, GetLang("交流、群组与开源"), "0")
            . '</Border><Border Grid.Column="1" Margin="7,0,0,0">'
            . this._HelpCard(GetLang("问题反馈"), "&#xE7BA;", feedback, GetLang("共同完善 RMT"), "0")
            . '</Border></Grid>'
        Add(lower)

        this._FlushLinks()
    }

    _HelpCard(title, glyph, body, hint := "", margin := "0", warning := false, headH := 42) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        accent := warning ? '{DynamicResource Accent}' : '{DynamicResource OutlineStroke}'
        titleSize := headH <= 30 ? "12" : "13"
        glyphSize := headH <= 30 ? "13" : "14"
        hintXaml := hint == "" ? "" : '<TextBlock Grid.Column="1" Text="' this._XmlEsc(hint) '" Foreground="{DynamicResource TextSub}" FontSize="11" FontWeight="Normal" VerticalAlignment="Center" HorizontalAlignment="Right"/>'
        return '<Border ' ns ' Margin="' margin '" Background="{DynamicResource ControlBg}" BorderBrush="' accent '" BorderThickness="1.25" CornerRadius="8" Padding="0">'
            . '<Grid><Grid.RowDefinitions><RowDefinition Height="' headH '"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<Border Grid.Row="0" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="0,0,0,1" CornerRadius="7,7,0,0" Padding="13,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="' glyphSize '" Foreground="{DynamicResource Accent}" Margin="0,0,8,0" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="' titleSize '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel>' hintXaml '</Grid></Border>'
            . '<Border Grid.Row="1" Padding="13,11">' body '</Border></Grid></Border>'
    }

    _HelpDisclaimerItem(number, text) {
        return '<Grid Margin="0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="19" Height="19" CornerRadius="9.5" Background="{DynamicResource Accent}" VerticalAlignment="Top"><TextBlock Text="' number '" Foreground="{DynamicResource ActionText}" FontWeight="Bold" FontSize="10" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Grid.Column="1" Text="' this._XmlEsc(GetLang(text)) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextMain}"/></Grid>'
    }

    _HelpResource(glyph, title, description, url, buttonText) {
        return '<StackPanel><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Orientation="Horizontal"><Border Width="27" Height="27" CornerRadius="6" Background="{DynamicResource EditHoverBg}" Margin="0,0,7,0"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Grid.Row="1" Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,8,0,9"/></Grid>'
            . this._HelpLinkButton(url, buttonText) '</StackPanel>'
    }

    _HelpCommunityTile(row, col, glyph, title, description, url, margin) {
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Margin="' margin '" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6">'
            . this._HelpTileButton(url, glyph, title, description) '</Border>'
    }

    _HelpFeedbackItem(col, glyph, title, description, url, buttonText, margin) {
        return '<Border Grid.Column="' col '" Margin="' margin '" Padding="10" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="6"><StackPanel><StackPanel Orientation="Horizontal"><Border Width="26" Height="26" CornerRadius="6" Background="{DynamicResource EditHoverBg}" Margin="0,0,7,0"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,0,8"/>' this._HelpLinkButton(url, buttonText) '</StackPanel></Border>'
    }

    _HelpTileButton(url, glyph, title, description) {
        this._linkCounter := this._linkCounter + 1
        name := "HelpLink_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        return '<Button Name="' name '" Cursor="Hand" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch"><Grid Margin="10"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="26" Height="26" CornerRadius="6" Background="{DynamicResource EditHoverBg}"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Grid.Column="1" Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/><TextBlock Grid.Row="1" Grid.ColumnSpan="2" Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource TextSub}" Margin="0,7,0,0"/></Grid></Button>'
    }

    _HelpLinkButton(url, text, accent := false) {
        this._linkCounter := this._linkCounter + 1
        name := "HelpLink_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url, event: "Click" })
        bg := accent ? "{DynamicResource EditHoverBg}" : "{DynamicResource InputBg}"
        fg := accent ? "{DynamicResource Accent}" : "{DynamicResource TextMain}"
        weight := accent ? "Bold" : "Normal"
        return '<Button Name="' name '" Cursor="Hand" HorizontalAlignment="Left" MinHeight="25" Padding="8,0" VerticalContentAlignment="Center" Background="' bg '" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1"><Grid VerticalAlignment="Center"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="' this._XmlEsc(text) '" FontSize="10" FontWeight="' weight '" Foreground="' fg '" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="&#xE8A7;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="9" Foreground="{DynamicResource Accent}" Margin="5,0,0,0" VerticalAlignment="Center"/></Grid></Button>'
    }

    _Para(text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        return '<TextBlock ' ns ' Text="' this._XmlEsc(GetLang(text)) '" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,3"/>'
    }

    _LinkRow(label, url, text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        this._linkCounter := this._linkCounter + 1
        name := "Link_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url })
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,3,0,3">'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="130" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBlock Name="' name '" Text="' this._XmlEsc(text) '" TextDecorations="Underline" Foreground="#2D6CDF" Cursor="Hand" FontSize="12" TextWrapping="Wrap"/>'
            . '</StackPanel>'
    }

    OnLinkClick(url, state, ctrl, event) {
        if (url = "")
            return
        ; 软件内反馈：不走浏览器，直接开反馈窗口
        if (url = "rmt:feedback") {
            FeedbackGui.ShowGui()
            return
        }
        ; 本地 html 帮助文档 → 优先用 Chromium app 模式小窗打开
        if (RegExMatch(url, "i)\.html?$") && FileExist(url) && OpenHelpInAppWindow())
            return
        Run(url)
    }
