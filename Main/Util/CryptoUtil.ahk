#Requires AutoHotkey v2.0
; ============================================================
; CryptoUtil — 分享包（.rmt）密码加解密
;
; 作用范围只有导出/导入这两步：
;   导出 → 打包完整体加密，得到一个打不开的 .rmt；
;   导入 → 认出加密头，问一次密码，解出来再走原来的解包流程。
;
; 磁盘上的 Setting\<方案>\*.toml 一律保持明文，程序运行、Worker 读配置、
; 旧版本配置都不受影响（加密的是「拿走的东西」，不是本机存储）。
;
; 实现：只用 Windows 自带的 CNG（bcrypt.dll），不依赖 .NET、不依赖任何
;       需要安装的运行库。Win8 及以上系统自带，RMT 的目标系统都在范围内。
;
; 包文件格式（纯二进制，42 字节头 + 密文 + 32 字节 MAC）：
;   0   4B  "RMTC"
;   4   1B  版本 = 2
;   5   1B  预留
;   6   4B  迭代次数（uint32 LE）
;   10 16B  salt
;   26 16B  iv
;   42 ...  密文（AES-256-CBC，PKCS7 填充）
;   末尾 32B  HMAC-SHA256(head | 密文)，密钥取 PBKDF2 输出的后半段
;
; 密钥：PBKDF2-HMAC-SHA256(密码, salt, 迭代) → 64 字节，
;       前 32 字节 AES 密钥，后 32 字节 HMAC 密钥（Encrypt-then-MAC）。
;
; 兼容：没有 "RMTC" 头的 .rmt 按旧明文包处理 → 老版本导出的包照常导入；
;       不设密码导出的包也是明文，新老版本都能读。
;
; 密码框走 XAML（与设置/提示窗同一套标题栏与主题），不用系统 Gui。
; ============================================================

global RMTC_Ver := 2
global RMTC_Iter := 150000
global RMTC_HeadSize := 42        ; 4 魔数 + 1 版本 + 1 预留 + 4 迭代 + 16 盐 + 16 IV
global RMTC_MacSize := 32
global RMTC_Prompting := false    ; 密码框是否已打开（防重入叠框）
global RMTC_ErrColor := "#E5484D"

; ============================================================
; CNG（bcrypt.dll）基础封装
; ============================================================
RMTC_OpenAlg(algId, hmacFlag := false) {
    h := 0
    st := DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &h, "wstr", algId
        , "ptr", 0, "uint", hmacFlag ? 0x8 : 0, "int")
    if (st != 0)
        throw Error("打开加密算法失败：" algId " (0x" Format("{:X}", st) ")")
    return h
}

RMTC_GetU32Prop(hAlg, name) {
    v := 0, n := 0
    st := DllCall("bcrypt\BCryptGetProperty", "ptr", hAlg, "wstr", name
        , "uint*", &v, "uint", 4, "uint*", &n, "uint", 0, "int")
    if (st != 0)
        throw Error("读取加密属性失败：" name)
    return v
}

RMTC_Random(n) {
    buf := Buffer(n)
    st := DllCall("bcrypt\BCryptGenRandom", "ptr", 0, "ptr", buf.Ptr, "uint", n
        , "uint", 0x2, "int")       ; 0x2 = BCRYPT_USE_SYSTEM_PREFERRED_RNG
    if (st != 0)
        throw Error("生成随机数失败")
    return buf
}

; 精确长度的 UTF-8 Buffer（不带结尾 0）
RMTC_Utf8Buffer(text) {
    len := StrPut(text, "utf-8") - 1
    tmp := Buffer(len + 1)
    StrPut(text, tmp, "utf-8")
    if (len == 0)
        return Buffer(1)
    out := Buffer(len)
    DllCall("RtlMoveMemory", "ptr", out.Ptr, "ptr", tmp.Ptr, "uint", len)
    return out
}

RMTC_Concat(a, b) {
    out := Buffer(a.Size + b.Size)
    DllCall("RtlMoveMemory", "ptr", out.Ptr, "ptr", a.Ptr, "uint", a.Size)
    if (b.Size)
        DllCall("RtlMoveMemory", "ptr", out.Ptr + a.Size, "ptr", b.Ptr, "uint", b.Size)
    return out
}

RMTC_BufEqual(a, b) {
    if (a.Size != b.Size)
        return false
    diff := 0
    loop a.Size
        diff |= NumGet(a, A_Index - 1, "uchar") ^ NumGet(b, A_Index - 1, "uchar")
    return diff == 0
}

; PBKDF2-HMAC-SHA256（Win8+ 自带；失败时直接报错，不静默降级）
RMTC_PBKDF2(pwd, saltBuf, iter, outLen) {
    out := Buffer(outLen)
    pwdBuf := RMTC_Utf8Buffer(pwd)
    hPrf := RMTC_OpenAlg("SHA256", true)
    try {
        st := DllCall("bcrypt\BCryptDeriveKeyPBKDF2", "ptr", hPrf
            , "ptr", pwdBuf.Ptr, "uint", pwdBuf.Size
            , "ptr", saltBuf.Ptr, "uint", saltBuf.Size
            , "int64", iter, "ptr", out.Ptr, "uint", outLen, "uint", 0, "int")
        if (st != 0)
            throw Error("密码派生失败 (0x" Format("{:X}", st) ")，系统可能过旧")
    } finally {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hPrf, "uint", 0)
    }
    return out
}

RMTC_HmacSha256(keyBuf, dataBuf) {
    hAlg := RMTC_OpenAlg("SHA256", true)
    hHash := 0
    try {
        objLen := RMTC_GetU32Prop(hAlg, "ObjectLength")
        objBuf := Buffer(objLen)
        st := DllCall("bcrypt\BCryptCreateHash", "ptr", hAlg, "ptr*", &hHash
            , "ptr", objBuf.Ptr, "uint", objLen
            , "ptr", keyBuf.Ptr, "uint", keyBuf.Size, "uint", 0, "int")
        if (st != 0)
            throw Error("HMAC 初始化失败 (0x" Format("{:X}", st) ")")
        try {
            st := DllCall("bcrypt\BCryptHashData", "ptr", hHash
                , "ptr", dataBuf.Ptr, "uint", dataBuf.Size, "uint", 0, "int")
            if (st != 0)
                throw Error("HMAC 计算失败 (0x" Format("{:X}", st) ")")
            out := Buffer(32)
            st := DllCall("bcrypt\BCryptFinishHash", "ptr", hHash
                , "ptr", out.Ptr, "uint", 32, "uint", 0, "int")
            if (st != 0)
                throw Error("HMAC 收尾失败 (0x" Format("{:X}", st) ")")
            return out
        } finally {
            DllCall("bcrypt\BCryptDestroyHash", "ptr", hHash)
        }
    } finally {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
    }
}

; AES-256-CBC 加解密。keyBuf 32 字节，ivBuf 16 字节。
; 填充自己处理：加密补 PKCS7，解密自己校验并去掉（不交给 CNG，便于判断密码错）
RMTC_AesCrypt(encrypt, keyBuf, ivBuf, inBuf) {
    hAlg := RMTC_OpenAlg("AES")
    hKey := 0
    try {
        ; BCRYPT_CHAINING_MODE 的值是宽字符串 "ChainingModeCBC"（含结尾 0）
        modeStr := "ChainingModeCBC"
        modeLen := (StrLen(modeStr) + 1) * 2
        modeBuf := Buffer(modeLen)
        StrPut(modeStr, modeBuf, "UTF-16")
        st := DllCall("bcrypt\BCryptSetProperty", "ptr", hAlg, "wstr", "ChainingMode"
            , "ptr", modeBuf.Ptr, "uint", modeLen, "uint", 0, "int")
        if (st != 0)
            throw Error("设置 CBC 模式失败 (0x" Format("{:X}", st) ")")

        st := DllCall("bcrypt\BCryptGenerateSymmetricKey", "ptr", hAlg, "ptr*", &hKey
            , "ptr", 0, "uint", 0, "ptr", keyBuf.Ptr, "uint", keyBuf.Size, "uint", 0, "int")
        if (st != 0)
            throw Error("初始化 AES 密钥失败 (0x" Format("{:X}", st) ")")

        iv := Buffer(16)
        DllCall("RtlMoveMemory", "ptr", iv.Ptr, "ptr", ivBuf.Ptr, "uint", 16)

        out := Buffer(inBuf.Size)
        n := 0
        if (encrypt)
            st := DllCall("bcrypt\BCryptEncrypt", "ptr", hKey, "ptr", inBuf.Ptr, "uint", inBuf.Size
                , "ptr", 0, "ptr", iv.Ptr, "uint", 16, "ptr", out.Ptr, "uint", out.Size
                , "uint*", &n, "uint", 0, "int")
        else
            st := DllCall("bcrypt\BCryptDecrypt", "ptr", hKey, "ptr", inBuf.Ptr, "uint", inBuf.Size
                , "ptr", 0, "ptr", iv.Ptr, "uint", 16, "ptr", out.Ptr, "uint", out.Size
                , "uint*", &n, "uint", 0, "int")
        if (st != 0 || n != out.Size)
            throw Error(encrypt ? "加密失败" : "解密失败")
        return out
    } finally {
        if (hKey)
            DllCall("bcrypt\BCryptDestroyKey", "ptr", hKey)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
    }
}

RMTC_AesEncrypt(keyBuf, ivBuf, plainBuf) {
    padLen := 16 - Mod(plainBuf.Size, 16)
    padded := Buffer(plainBuf.Size + padLen)
    if (plainBuf.Size)
        DllCall("RtlMoveMemory", "ptr", padded.Ptr, "ptr", plainBuf.Ptr, "uint", plainBuf.Size)
    DllCall("RtlFillMemory", "ptr", padded.Ptr + plainBuf.Size, "ptr", padLen, "uchar", padLen)
    return RMTC_AesCrypt(true, keyBuf, ivBuf, padded)
}

RMTC_AesDecrypt(keyBuf, ivBuf, ctBuf) {
    plain := RMTC_AesCrypt(false, keyBuf, ivBuf, ctBuf)
    if (plain.Size < 16 || Mod(plain.Size, 16) != 0)
        throw Error("密码错误或分享包已损坏")

    padLen := NumGet(plain, plain.Size - 1, "uchar")
    if (padLen < 1 || padLen > 16 || padLen > plain.Size)
        throw Error("密码错误或分享包已损坏")
    loop padLen {
        if (NumGet(plain, plain.Size - A_Index, "uchar") != padLen)
            throw Error("密码错误或分享包已损坏")
    }

    n := plain.Size - padLen
    if (n == 0)
        return Buffer(1)
    out := Buffer(n)
    DllCall("RtlMoveMemory", "ptr", out.Ptr, "ptr", plain.Ptr, "uint", n)
    return out
}

; ============================================================
; 加密头
; ============================================================
; 前 4 字节是不是 "RMTC"（加密的 .rmt；旧明文包是 "RMPK"）
RMTC_IsEncryptedFile(file) {
    if (!FileExist(file) || FileGetSize(file) < RMTC_HeadSize)
        return false
    try {
        f := FileOpen(file, "r")
        head := Buffer(4)
        f.RawRead(head, 4)
        f.Close()
        return (StrGet(head, 4, "cp0") == "RMTC")
    } catch {
        return false
    }
}

; 64 字节密钥材料 → {Enc:32B, Mac:32B}
RMTC_SplitKey(keyBuf) {
    enc := Buffer(32), mac := Buffer(32)
    DllCall("RtlMoveMemory", "ptr", enc.Ptr, "ptr", keyBuf.Ptr, "uint", 32)
    DllCall("RtlMoveMemory", "ptr", mac.Ptr, "ptr", keyBuf.Ptr + 32, "uint", 32)
    return { Enc: enc, Mac: mac }
}

; ============================================================
; 整包加解密（Buffer 进、Buffer 出）
; ============================================================
; 明文包 Buffer → 加密 Buffer
RMTC_SealBuffer(plain, pwd) {
    if (pwd == "")
        return plain

    salt := RMTC_Random(16)
    iv := RMTC_Random(16)
    k := RMTC_SplitKey(RMTC_PBKDF2(pwd, salt, RMTC_Iter, 64))
    ct := RMTC_AesEncrypt(k.Enc, iv, plain)

    head := Buffer(RMTC_HeadSize)
    StrPut("RMTC", head, 4, "cp0")
    NumPut("uchar", RMTC_Ver, head, 4)
    NumPut("uchar", 0, head, 5)
    NumPut("uint", RMTC_Iter, head, 6)
    DllCall("RtlMoveMemory", "ptr", head.Ptr + 10, "ptr", salt.Ptr, "uint", 16)
    DllCall("RtlMoveMemory", "ptr", head.Ptr + 26, "ptr", iv.Ptr, "uint", 16)

    body := RMTC_Concat(head, ct)
    return RMTC_Concat(body, RMTC_HmacSha256(k.Mac, body))
}

; 加密包 Buffer → 明文包 Buffer；密码错/损坏抛异常
RMTC_OpenBuffer(data, pwd) {
    if (data.Size < RMTC_HeadSize + 16 + RMTC_MacSize)
        throw Error("分享包太短，可能已损坏")
    if (StrGet(data, 4, "cp0") != "RMTC")
        throw Error("不是加密的分享包")
    ver := NumGet(data, 4, "uchar")
    if (ver != RMTC_Ver)
        throw Error("分享包版本不支持（" ver "）")
    iter := NumGet(data, 6, "uint")
    if (iter < 1000 || iter > 2000000)
        throw Error("分享包头部已损坏")

    salt := Buffer(16), iv := Buffer(16), head := Buffer(RMTC_HeadSize)
    DllCall("RtlMoveMemory", "ptr", head.Ptr, "ptr", data.Ptr, "uint", RMTC_HeadSize)
    DllCall("RtlMoveMemory", "ptr", salt.Ptr, "ptr", data.Ptr + 10, "uint", 16)
    DllCall("RtlMoveMemory", "ptr", iv.Ptr, "ptr", data.Ptr + 26, "uint", 16)

    ctLen := data.Size - RMTC_HeadSize - RMTC_MacSize
    if (ctLen <= 0 || Mod(ctLen, 16) != 0)
        throw Error("分享包已损坏")
    ct := Buffer(ctLen)
    DllCall("RtlMoveMemory", "ptr", ct.Ptr, "ptr", data.Ptr + RMTC_HeadSize, "uint", ctLen)
    mac := Buffer(RMTC_MacSize)
    DllCall("RtlMoveMemory", "ptr", mac.Ptr, "ptr", data.Ptr + RMTC_HeadSize + ctLen, "uint", RMTC_MacSize)

    k := RMTC_SplitKey(RMTC_PBKDF2(pwd, salt, iter, 64))

    ; 先验 MAC 再解密：伪造数据不会进 AES
    expect := RMTC_HmacSha256(k.Mac, RMTC_Concat(head, ct))
    if (!RMTC_BufEqual(expect, mac))
        throw Error("密码错误或分享包已损坏")

    return RMTC_AesDecrypt(k.Enc, iv, ct)
}

; ============================================================
; 密码输入（XAML，与设置/提示窗同一套标题栏与主题）
; ============================================================
; 导出：双框 + 「不加密」勾选。勾了才算不加密导出，关窗/取消一律中止
; owner：发起导出的那个窗口（配置管理 / 配置合并…），决定弹窗挂谁上面、关窗后回到谁
RMTC_AskExportPassword(owner := 0) {
    tip := "给这个分享包设置密码，别人导入时需要输入。`n不需要密码请勾选下面的「不加密」。"
    return RMTC_PwdGui("导出分享包", tip, false, true, owner)
}

; 导入加密包：单框，取消返回 Ok=false
RMTC_AskImportPassword(fileName, wrong := false, owner := 0) {
    tip := "「" fileName "」是加密的分享包，请输入作者设置的密码："
    return RMTC_PwdGui("导入加密分享包", tip, wrong, false, owner)
}

RMTC_PwdGui(title, tip, wrong, confirmMode, owner := 0) {
    global RMTC_Prompting
    if (RMTC_Prompting)
        return { Pwd: "", Ok: false }
    RMTC_Prompting := true
    try {
        return RMTC_PwdGuiShow(title, tip, wrong, confirmMode, owner)
    } finally {
        RMTC_Prompting := false
    }
}

; 本次弹窗的属主：跟随发起这次导出的窗口（配置管理 / 主窗口 / 配置合并…）
RMTC_PwdGuiShow(title, tip, wrong, confirmMode, owner := 0) {
    result := { Pwd: "", Ok: false, Done: false }

    if (!owner)
        owner := XamlWin.ActiveOwner()
    try XAMLHost.EnsureDaemonHealthy()

    fs := XAMLHost.FontSize()
    titleHeight := "30"
    winW := 400
    fontFamily := ""
    try {
        if (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
            fontFamily := MainSoftData.FontType
    }

    main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
    if (fontFamily != "")
        main.TextElement_FontFamily(fontFamily)
    main.TextElement_FontSize(fs)
    main.Rows(titleHeight, "Auto")

    XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClosePanel", "", Chr(0xE72E), "{DynamicResource Accent}")

    body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
    panel := body.Add("StackPanel").Margin("18,16,18,14")

    tipTb := panel.Add("TextBlock").Text(tip).Foreground("{DynamicResource TextMain}")
        .TextWrapping("Wrap").MaxWidth(winW - 40).Margin("0,0,0,12")
    if (fontFamily != "")
        tipTb.FontFamily(fontFamily)

    innerW := winW - 36
    pwdBox := panel.Add("PasswordBox").Name("PwdBox").Width(innerW).Height(30)
        .Padding("6,0,18,0").VerticalContentAlignment("Center").FontSize(fs)
        .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
        .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
    if (fontFamily != "")
        pwdBox.FontFamily(fontFamily)

    pwdBox2 := ""
    if (confirmMode) {
        panel.Add("TextBlock").Text("再输一次：").Foreground("{DynamicResource TextSub}")
            .Margin("0,10,0,4")
        pwdBox2 := panel.Add("PasswordBox").Name("PwdBox2").Width(innerW).Height(30)
            .Padding("6,0,18,0").VerticalContentAlignment("Center").FontSize(fs)
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (fontFamily != "")
            pwdBox2.FontFamily(fontFamily)
    }

    ; 导出专用：「不加密」是一个独立勾选，而不是一个「取消按钮」——
    ; 关窗 / Esc / 取消都必须是中止，不能顺手导出
    noPwdChk := ""
    if (confirmMode) {
        noPwdChk := panel.Add("CheckBox").Name("ChkNoPwd").Content("不加密（别人导入时不需要密码）")
            .Foreground("{DynamicResource TextSub}").FontSize(fs).Margin("0,10,0,0").Cursor("Hand")
        if (fontFamily != "")
            noPwdChk.FontFamily(fontFamily)
    }

    ; 提示行：默认留空占位，出错时填文字，避免窗口高度跳动
    panel.Add("TextBlock").Name("ErrText").Text(wrong ? "密码不对，请重试。" : "")
        .Foreground(RMTC_ErrColor).FontSize(fs).Margin("0,8,0,0").TextWrapping("Wrap")

    btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

    btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,16,0,2")
    okBtn := btnRow.Add("Button").Name("BtnOk").Content("确定")
        .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
        .FontWeight("Bold").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
        .FontSize(fs).Cursor("Hand").Width(88).Height(32).Margin("0,0,44,0").IsDefault("True")
    okBtn.InjectResources(btnStyle)
    cancelBtn := btnRow.Add("Button").Name("BtnCancel").Content("取消")
        .Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}")
        .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        .FontSize(fs).Cursor("Hand").Width(88).Height(32).IsCancel("True")
    cancelBtn.InjectResources(btnStyle)

    ; 落点写进 XAML：引擎揭盖时会按「高 600」给 SizeToContent 窗口估位置，这个窗只有 300 多高，
    ; 不写 Left/Top 就会明显偏上。尺寸仍由 SizeToContent 决定，estH 只用来算落点。
    lineH := Round(fs * 1.5)
    tipLines := 0
    loop parse tip, "`n"
        tipLines += Max(1, Ceil(StrLen(A_LoopField) * fs * 0.62 / (winW - 40)))
    estH := 30 + 30 + tipLines * lineH + 12 + 30 + 8 + lineH + 18 + 32
    if (confirmMode)
        estH += (10 + lineH + 30) + (10 + lineH + 6)
    posAttr := XamlWin.PosAttr(winW, estH, owner)

    tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
    ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
    safeTitle := RMTC_XmlEsc(title)
    ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" ShowInTaskbar="False"' posAttr ' Width="' winW '" SizeToContent="Height" Opacity="0"')
    ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
    if (fontFamily != "")
        ui.xaml := StrReplace(ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' fontFamily '"')
    ui.xaml := StrReplace(ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
    ui.xaml := StrReplace(ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

    finish(pwd, ok) {
        if (result.Done)
            return
        result.Pwd := pwd
        result.Ok := ok
        result.Done := true
        try ui.Update("Window", "Close", "")
    }

    onSubmit(*) {
        ; 密码按原样取用，不做 Trim（首尾空格也是密码的一部分）
        v := ui.Query("PwdBox")
        if (confirmMode) {
            ; 只有明确勾选「不加密」才按明文导出
            if (ui.Query("ChkNoPwd") == "True") {
                finish("", true)
                return
            }
            if (v == "") {
                ui.Update("ErrText", "Text", "请输入密码，或勾选「不加密」。")
                return
            }
            if (v != ui.Query("PwdBox2")) {
                ui.Update("ErrText", "Text", "两次输入的密码不一致。")
                return
            }
        } else if (v == "") {
            ui.Update("ErrText", "Text", "请输入密码。")
            return
        }
        finish(v, true)
    }

    ; 取消 / Esc / 右上角关闭 → 一律中止（Ok=false），打包调用方据此放弃导出
    onCancel(*) {
        finish("", false)
    }

    ui.OnEvent("BtnOk", "Click", onSubmit)
    ui.OnEvent("BtnCancel", "Click", onCancel)
    ui.OnEvent("BtnClosePanel", "Click", onCancel)
    ui.OnEvent("Window", "Closing", (*) => finish("", false))
    ui.OnEvent("Window", "LoadedHwnd", (*) => XamlWin.OnLoadTheme(ui))

    if (!XamlWin.Open(ui, "", owner))
        return { Pwd: "", Ok: false }
    ; 打开后把焦点放到第一个密码框
    try ui.Update("PwdBox", "Focus", "True")

    ; 落点已在 XAML 里给好，揭盖即到位；这里只做一次兜底校验（偏差 >40px 才纠正，正常不动）
    XamlWin.NudgeIfOff(ui, owner)

    ; 模态等待：期间禁用属主窗口，避免窗口还开着就能去点别的
    ownerDisabled := false
    while (!result.Done && WinExist("ahk_id " ui.wpfHwnd)) {
        if (ui.wpfHwnd && owner && !ownerDisabled) {
            try WinSetEnabled(0, "ahk_id " owner)
            ownerDisabled := true
        }
        Sleep(30)
    }
    if (ownerDisabled) {
        try WinSetEnabled(1, "ahk_id " owner)
        try WinActivate("ahk_id " owner)
    }
    result.Done := true
    return { Pwd: result.Pwd, Ok: result.Ok }
}

RMTC_XmlEsc(s) {
    s := StrReplace(String(s), "&", "&amp;")
    s := StrReplace(s, "<", "&lt;")
    s := StrReplace(s, ">", "&gt;")
    s := StrReplace(s, '"', "&quot;")
    return s
}
