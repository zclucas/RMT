
    ; ============ 赞助页 ============
    BuildRewardTab() {
        ; §23 Panel_ 编号 = TableInfo 位置：表集合新增「网络宏」后 Reward 起顺延 +1，改按 Symbol 动态取位
        p := "Panel_" GetTableIndexByID("Reward")
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        countStr := FormatIntegerWithCommas(MySoftData.MacroTotalCount)
        weiXinImg := StrReplace(A_WorkingDir "\Images\Soft\WeiXin.png", "\", "/")
        zhiFuBaoImg := StrReplace(A_WorkingDir "\Images\Soft\ZhiFuBao.png", "\", "/")
        ; 赞助二维码随主程序发布。FileInstall 行必须单独成行，Ahk2Exe 才会打进 exe。
        aiFaDianImg := this._GetBuiltInSupportQr("aifadian")
        stripe2Img := this._GetBuiltInSupportQr("stripe2")
        stripe5Img := this._GetBuiltInSupportQr("stripe5")
        stripe2Url := this._ReadQrUrl(stripe2Img)
        stripe5Url := this._ReadQrUrl(stripe5Img)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        hero := '<Border ' ns ' Margin="0,2,0,14" Padding="18,15" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1.25" CornerRadius="8"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="' this._XmlEsc(GetLang("感谢每一位支持 RMT 的守护者")) '" FontSize="16" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(GetLang("RMT 始终免费、开源。若它为你节省了时间，欢迎用一杯咖啡的心意支持开发与维护。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,14,0"/><TextBlock Text="' this._XmlEsc(GetLang("若暂时不方便，分享给朋友同样是珍贵的支持。开发不易，感谢你的每一份温暖！")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,5,14,0"/><Border HorizontalAlignment="Left" Margin="0,8,0,0" Padding="8,3" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><TextBlock Text="' this._XmlEsc(GetLang("功能无限制，赞助自愿")) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMain}"/></Border></StackPanel><StackPanel Grid.Column="1" VerticalAlignment="Center"><Border Padding="12,8" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Border Width="28" Height="28" CornerRadius="14" Background="{DynamicResource EditHoverBg}" Margin="0,0,8,0"><TextBlock Text="&#xE823;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel><TextBlock Text="' this._XmlEsc(GetLang("已累计执行")) '" FontSize="10" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' countStr '" TextWrapping="NoWrap" FontSize="20" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,0"/></StackPanel></StackPanel></Border></StackPanel></Grid></Border>'
        Add(hero)

        singleSupport := '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._SupportQrCard(0, 0, 1, weiXinImg, GetLang("微信赞助"), GetLang("扫码完成一次性赞助。快捷直接，适合随时表达一份心意。"), "0,0,5,0")
            . this._SupportQrCard(0, 1, 1, zhiFuBaoImg, GetLang("支付宝赞助"), GetLang("扫码完成一次性赞助。与微信同为推荐的直接支持方式。"), "5,0,0,0")
            . '</Grid>'
        guardianButtons := '<StackPanel Orientation="Horizontal">' this._HelpLinkButton("https://forum.ruomengtu.com/", GetLang("打开 RMT 论坛")) '<Border Width="7"/> ' this._HelpLinkButton("https://qm.qq.com/q/DgpDumEPzq", GetLang("加入 QQ 交流群")) '</StackPanel>'
        benefits := '<StackPanel>'
            . this._SupportAfterCard(0, 0, 1, "&#xE902;", GetLang("领取守护者称号"), GetLang("完成赞助后，可通过 RMT 论坛或 RMT QQ 交流群私信联系，领取论坛和 QQ 交流群的“守护者”称号。"), guardianButtons, "0,0,0,10")
            . this._SupportAfterCard(1, 0, 1, "&#xE8A5;", GetLang("若梦星河"), GetLang("赞助后的留言会展示在若梦星河，感谢每一位让 RMT 走得更远的朋友。"), this._HelpLinkButton("https://docs.ruomengtu.com/supporters/", GetLang("打开若梦星河")), "0", GetLang("提示：名单会在版本更新时统一更新。"))
            . '</StackPanel>'
        stripeSupport := '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . this._SupportQrCard(0, 0, 1, stripe2Img, GetLang("2 美元 / 月"), GetLang("扫码或打开链接，用一份持续的心意陪伴 RMT。"), "0,0,5,0", "", stripe2Url, GetLang("打开订阅页"), true)
            . this._SupportQrCard(0, 1, 1, stripe5Img, GetLang("5 美元 / 月"), GetLang("扫码或打开链接，以更深的心意，陪伴 RMT 走过更多精彩旅程。"), "5,0,0,0", "", stripe5Url, GetLang("打开订阅页"), true)
            . '</Grid>'
        aiFaDian := this._SupportAiFaDianSideCard(aiFaDianImg)
        enterprise := this._SupportEnterpriseCard()
        supportLayout := '<Grid ' ns ' Margin="0,0,0,14"><Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            . '<StackPanel Grid.Column="0" Margin="0,0,7,0">'
            . this._HelpCard(GetLang("个人赞助"), "&#xE8C7;", singleSupport, GetLang("微信与支付宝"), "0,0,0,14", false, 30)
            . this._HelpCard(GetLang("Stripe订阅"), "&#xE8C8;", stripeSupport, GetLang("国际卡按月"), "0,0,0,14", false, 30)
            . this._HelpCard(GetLang("爱发电 · 月度守护"), "&#xE8C8;", aiFaDian, GetLang("国内按月"), "0", false, 30)
            . '</StackPanel><StackPanel Grid.Column="1" Margin="7,0,0,0">'
            . this._HelpCard(GetLang("企业赞助"), "&#xE731;", enterprise, "", "0,0,0,14", false, 30)
            . this._HelpCard(GetLang("感谢与留念"), "&#xE9CE;", benefits, GetLang("让每份心意被看见"), "0", false, 30)
            . '</StackPanel></Grid>'
        Add(supportLayout)
        this._Bind("RewardSponsorMailCopy", "Click", ObjBindMethod(this, "OnCopySponsorMail"))
        this._FlushLinks()
    }

    _SupportEnterpriseCard() {
        mail := "ruomengtu@gmail.com"
        return '<StackPanel><TextBlock Text="' this._XmlEsc(GetLang("欢迎企业、工作室及团队支持 RMT 开源项目的长期发展。")) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}"/><TextBlock Text="' this._XmlEsc(GetLang("非诚勿扰")) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,6,0,0"/><WrapPanel Margin="0,10,0,0"><TextBlock Text="' this._XmlEsc(GetLang("联系邮箱：")) '" FontSize="11" Foreground="{DynamicResource TextMain}" VerticalAlignment="Center"/><TextBlock Text="' this._XmlEsc(mail) '" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMain}" VerticalAlignment="Center" Margin="0,0,8,0"/><Button Name="RewardSponsorMailCopy" Cursor="Hand" Width="25" Height="25" Padding="0" VerticalAlignment="Center" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" ToolTip="' this._XmlEsc(GetLang("复制")) '"><TextBlock Text="&#xE8C8;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Button></WrapPanel></StackPanel>'
    }

    OnCopySponsorMail(*) {
        A_Clipboard := "ruomengtu@gmail.com"
        try Toast.Success(GetLang("已复制"))
    }

    _SupportQrCard(row, col, span, image, title, description, margin, badge := "", url := "", btnText := "", accentBtn := false) {
        badgeXaml := ""
        if (url == "") {
            if (badge == "")
                badge := GetLang("推荐 · 单次赞助")
            badgeXaml := '<Border HorizontalAlignment="Left" Padding="8,4" Background="{DynamicResource EditHoverBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="4"><TextBlock Text="' this._XmlEsc(badge) '" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}"/></Border>'
        }
        btnXaml := url == "" ? "" : '<Border Margin="0,10,0,0">' this._HelpLinkButton(url, btnText, accentBtn) '</Border>'
        descMargin := url == "" ? "0,10,0,12" : "0,10,0,0"
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Grid.ColumnSpan="' span '" Margin="' margin '" MinHeight="166" Padding="16" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="138"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="132" Height="132" Padding="5" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Image Source="' image '" Stretch="Uniform"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="14" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="' descMargin '"/>' badgeXaml btnXaml '</StackPanel></Grid></Border>'
    }

    _SupportAiFaDianSideCard(image) {
        return '<Border MinHeight="166" Padding="16" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="138"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="132" Height="132" Padding="5" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><Image Source="' image '" Stretch="Uniform"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center">' this._SupportFactBox(GetLang("按月支持"), GetLang("长期守护与支持"), "0,0,0,8") this._SupportFactBox(GetLang("手续费"), GetLang("每笔6%手续费"), "0") '</StackPanel></Grid></Border>'
    }

    _SupportFactBox(title, description, margin) {
        return '<Border Margin="' margin '" Padding="9,7" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="5"><StackPanel><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="11" Foreground="{DynamicResource TextMain}"/><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource TextSub}" Margin="0,3,0,0"/></StackPanel></Border>'
    }

    _GetBuiltInSupportQr(kind) {
        static paths := Map()
        if (paths.Has(kind))
            return paths[kind]
        switch kind {
            case "stripe2":
                rel := "Images\Soft\Stripe2.png"
                tempPath := A_Temp "\RMT_Stripe2.png"
                try {
                    FileInstall("Images\Soft\Stripe2.png", tempPath, 1)
                }
            case "stripe5":
                rel := "Images\Soft\Stripe5.png"
                tempPath := A_Temp "\RMT_Stripe5.png"
                try {
                    FileInstall("Images\Soft\Stripe5.png", tempPath, 1)
                }
            default:
                rel := "Images\Soft\AiFaDian.png"
                tempPath := A_Temp "\RMT_AiFaDian.png"
                try {
                    FileInstall("Images\Soft\AiFaDian.png", tempPath, 1)
                }
        }
        got := this._MaterializeBundled(tempPath, rel)
        if (got == "")
            return ""
        paths[kind] := StrReplace(got, "\", "/")
        return paths[kind]
    }

    _GetQrDecodeExe() {
        static exePath := ""
        if (exePath != "" && this._IsPeImage(exePath))
            return exePath
        dir := A_Temp "\RMT_SupportQr"
        DirCreate(dir)
        destExe := dir "\QrDecode.exe"
        destDll := dir "\zxing.dll"
        ; 行首必须是 FileInstall。写成 try FileInstall 时 Ahk2Exe 不收录，
        ; 编译版会先把目标截成 0 字节，cmd 再启动它就会弹出“此应用无法在你的电脑上运行”。
        try {
            FileInstall("Plugins\SupportQr\QrDecode.exe", destExe, 1)
        }
        try {
            FileInstall("Plugins\SupportQr\zxing.dll", destDll, 1)
        }
        exe := this._MaterializeBundled(destExe, "Plugins\SupportQr\QrDecode.exe")
        if (exe == destExe)
            this._MaterializeBundled(destDll, "Plugins\SupportQr\zxing.dll")
        if (this._IsPeImage(exe))
            exePath := exe
        return exePath
    }

    ; FileInstall 找不到资源时会留下 0 字节文件，FileExist 仍为真，不能据此认为提取成功。
    _FileHasData(path) {
        if (path == "" || !FileExist(path))
            return false
        try
            return FileGetSize(path) > 0
        return false
    }

    _IsPeImage(path) {
        if (!this._FileHasData(path))
            return false
        try {
            f := FileOpen(path, "r")
            if (!IsObject(f))
                return false
            sig := f.Read(2)
            f.Close()
            return sig == "MZ"
        }
        return false
    }

    _MaterializeBundled(dest, rel) {
        if (this._FileHasData(dest))
            return dest
        src := A_WorkingDir "\" rel
        if (!this._FileHasData(src))
            src := A_ScriptDir "\" rel
        if (!this._FileHasData(src))
            return ""
        try {
            SplitPath(dest, , &parent)
            if (parent != "")
                DirCreate(parent)
            if (FileExist(dest))
                FileDelete(dest)
            FileCopy(src, dest, 1)
        }
        if (this._FileHasData(dest))
            return dest
        return src
    }

    _ReadQrUrl(imagePath) {
        static cache := Map()
        if (imagePath == "")
            return ""
        if (cache.Has(imagePath))
            return cache[imagePath]
        exe := this._GetQrDecodeExe()
        if (!this._IsPeImage(exe))
            return ""
        winPath := StrReplace(imagePath, "/", "\")
        if (!this._FileHasData(winPath))
            return ""
        dir := A_Temp "\RMT_SupportQr"
        outFile := dir "\out.txt"
        try FileDelete(outFile)
        cmd := Format('"{1}" /c ""{2}" "{3}" > "{4}""', A_ComSpec, exe, winPath, outFile)
        try RunWait(cmd, dir, "Hide")
        if (!FileExist(outFile))
            return ""
        url := Trim(FileRead(outFile, "UTF-8"), " `t`r`n")
        if (!RegExMatch(url, "i)^https?://"))
            return ""
        cache[imagePath] := url
        return url
    }

    _SupportAfterCard(row, col, span, glyph, title, description, footer, margin, note := "") {
        noteXaml := note == "" ? "" : '<TextBlock Text="' this._XmlEsc(note) '" TextWrapping="Wrap" FontSize="10" Foreground="{DynamicResource Accent}" Margin="0,7,0,0"/>'
        return '<Border Grid.Row="' row '" Grid.Column="' col '" Grid.ColumnSpan="' span '" Margin="' margin '" Padding="11" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource OutlineStroke}" BorderThickness="1" CornerRadius="7"><StackPanel><StackPanel Orientation="Horizontal"><Border Width="26" Height="26" CornerRadius="6" Background="{DynamicResource EditHoverBg}" Margin="0,0,7,0"><TextBlock Text="' glyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Text="' this._XmlEsc(title) '" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/></StackPanel><TextBlock Text="' this._XmlEsc(description) '" TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource TextSub}" Margin="0,7,0,0"/>' noteXaml '<Border Margin="0,10,0,0">' footer '</Border></StackPanel></Border>'
    }
