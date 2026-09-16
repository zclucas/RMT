; 全局 UI 控件容器（存放需要外部程序化更新的 GUI 控件对象）
; 这些控件不在 MainSoftData/SoftData 中存储，仅在 UI 层访问
global UIControls := {
    SuspendToggle: "",
    PauseToggle: "",
    CMDTip: "",
    RecordToggle: "",
    ToolCheck: "",
    ToolCheckRecord: "",
    AlwaysOnTop: "",
    ToolText: "",
    OCRType: ""
}

; 设置工具页文本显示内容（Master 有 GUI，Worker 无操作）
SetToolTextDisplay(text) {
    if (UIControls.ToolText)
        UIControls.ToolText.Value := text
}

; 编译包显示架构后缀；.ahk 调试运行不带 x64/x86
global RMT_VERSION_DISPLAY := A_IsCompiled
    ? (RMT_VERSION "_" (A_PtrSize = 8 ? "x64" : "x86"))
    : RMT_VERSION

;窗口&UI刷新
InitUI() {
    global MySoftData
    ; 首次启动：先同意免责声明，再显示主界面
    if (!MainSoftData.AgreeAgreement) {
        if (!AgreementGui.ShowAndWait())
            ExitApp()
        MainSoftData.AgreeAgreement := true
        IniWrite(true, IniFile, IniSection, "AgreeAgreement")
    }

    MyMainWin.BuildAndShow()

    MainSoftData.MyGui := GuiAdapter(MyMainWin.ui)
    MainSoftData.MyGui.Title := "RMTv" RMT_VERSION_DISPLAY
    MainSoftData.TabCtrl := TabAdapter(MyMainWin.ui, MyMainWin)
    MainSoftData.TabCtrl._value := MainSoftData.TableIndex
    MainSoftData.BtnSave := CtrlAdapter("BtnSave", MyMainWin.ui, "Text")

    MyTriggerKeyGui.SureFocusCon := MainSoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MainSoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MainSoftData.BtnSave
    MyUIMacroSettingGui.SureFocusCon := MainSoftData.BtnSave

    CustomTrayMenu()
    OnOpen()
}

OnOpen() {
    global MySoftData
    if (MainSoftData.IsMinStart) {
        MainSoftData.IsMinStart := false
        MainSoftData.MyGui.Hide()
        return
    }

    IniWrite(false, IniFile, IniSection, "IsReload")
    if (MainSoftData.LastShowMonth != A_Mon) {
        MainSoftData.TabCtrl.Value := 9
        MainSoftData.LastShowMonth := A_Mon
        IniWrite(MainSoftData.LastShowMonth, IniFile, IniSection, "LastShowMonth")
    }
    ; 首次打开不 WinMove/WinShow：主窗口 Opacity=0，内容填完再揭盖；再 Move 会抖一下
    RefreshListenVarGui()
}

; 主窗口关闭时清理所有鼠标热键订阅
OnGuiClose(*) {
    WinHotkey.UnsubscribeAllMouse()
    MyCMDTipGui._wheelCb := ""
    MyFreePasteGui._wheelCb := ""
    MyTargetGui._lbuttonCb := ""
}

; 读取保存的主窗口位置尺寸；旧格式 xπy 两段回退默认 1070×590，损坏/越界返回空数组
; BuildAndShow 可见前置位 + RefreshGui 都复用，避免两处解析漂移
GetLastWinPos() {
    LastWinPosStr := IniRead(IniFile, IniSection, "LastWinPos", "")
    WinPosArr := StrSplit(LastWinPosStr, "π")
    if (WinPosArr.Length >= 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        if (WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth && WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight) {
            ; 新格式 xπyπSπ缩放系数：尺寸 = 1400×787 基准 × 当前屏幕 fs × 系数（物理像素）
            ; 跨分辨率（4K→1080p 等）时窗口比例不变，不会因保存的绝对尺寸而巨大化
            if (WinPosArr.Length >= 4 && WinPosArr[3] == "S" && IsNumber(WinPosArr[4])) {
                dpi := DllCall("GetDpiForSystem", "UInt") / 96.0
                dipSW := A_ScreenWidth / dpi
                dipSH := A_ScreenHeight / dpi
                fs := Min(dipSW / 1920, dipSH / 1080)
                scale := Float(WinPosArr[4])
                w := Min(Round(1400 * fs * scale * dpi), VirtualWidth)
                h := Min(Round(787 * fs * scale * dpi), VirtualHeight)
                return [WinPosArr[1], WinPosArr[2], w, h]
            }
            ; 旧格式 xπy 两段 → 默认 1070×590；旧 4 段含绝对 w/h（≥400×300 才采信，上界钳虚拟屏防存档超大值）
            w := (WinPosArr.Length >= 4 && IsNumber(WinPosArr[3]) && WinPosArr[3] >= 400) ? Min(WinPosArr[3], VirtualWidth) : 1070
            h := (WinPosArr.Length >= 4 && IsNumber(WinPosArr[4]) && WinPosArr[4] >= 300) ? Min(WinPosArr[4], VirtualHeight) : 590
            return [WinPosArr[1], WinPosArr[2], w, h]
        }
    }
    return []
}

RefreshGui() {
    IniWrite(false, IniFile, IniSection, "IsReload")

    pos := GetLastWinPos()
    if (pos.Length) {
        MainSoftData.MyGui.Show(Format("x{} y{} w{} h{}", pos[1], pos[2], pos[3], pos[4]))
        RefreshListenVarGui()
        return
    }

    if (MainSoftData.LastShowMonth != A_Mon) {
        MainSoftData.TabCtrl.Value := 9
        MainSoftData.LastShowMonth := A_Mon
        IniWrite(MainSoftData.LastShowMonth, IniFile, IniSection, "LastShowMonth")
    }

    MainSoftData.MyGui.Show(Format("w{} h{}", 1070, 590))
    RefreshListenVarGui()
}

RefreshListenVarGui(isForce := false) {
    IsOenListVar := IniRead(IniFile, IniSection, "IsOpenListenVar", false)
    if (!isForce && !IsOenListVar)
        return

    LastPosStr := IniRead(IniFile, IniSection, "ListenVarPos", "")
    WinPosArr := StrSplit(LastPosStr, "π")
    if (WinPosArr.Length == 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        isXValid := WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth
        isYValid := WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight
        if (isXValid && isYValid) {
            MyVarListenGui.ShowGui(WinPosArr[1], WinPosArr[2])
            return
        }
    }

    MyVarListenGui.ShowGui()
}

RefreshToolUI() {
    global MainSoftData
    ; XAML 版：Tool*Ctrl 由异步 BuildToolTab 赋值（_PopulateAsync），窗口显示瞬间鼠标移动
    ; 可能先触发本函数（BindUtil 鼠标钩子），控件未赋值时直接跳过，避免对不存在属性赋值抛错
    if (!MainSoftData.HasProp("ToolMousePosCtrl") || !IsObject(MainSoftData.ToolMousePosCtrl))
        return
    MainSoftData.ToolMousePosCtrl.Value := MainSoftData.PosStr
    MainSoftData.ToolProcessNameCtrl.Value := MainSoftData.ProcessName
    MainSoftData.ToolProcessTileCtrl.Value := MainSoftData.ProcessTile
    MainSoftData.ToolProcessPidCtrl.Value := MainSoftData.ProcessPid
    MainSoftData.ToolProcessClassCtrl.Value := MainSoftData.ProcessClass
    MainSoftData.ToolProcessIdCtrl.Value := MainSoftData.ProcessId
    MainSoftData.ToolColorCtrl.Value := MainSoftData.Color
    MainSoftData.ToolMouseWinPosCtrl.Value := MainSoftData.WinPosStr
}

; 编辑快捷键：确认选择后再同步到 MainSoftData（以及显示控件）
OnEditHotkeyAndSync(showCon, keyCon, OnlyTriggerKey, fieldName, *) {
    SyncAfterSure(val) {
        MainSoftData.%fieldName% := val
        try showCon.Value := val
        try keyCon.Value := val
    }
    MyEditHotkeyGui.AfterSureAction := SyncAfterSure
    OnOpenEditHotkeyGui(showCon, keyCon, OnlyTriggerKey)
}

; 设置页数值编辑：输入过程中允许空/非法字符，仅在合法整数时写回
OnSettingIntEditChange(fieldName, ctrl, *) {
    v := Trim(ctrl.Value)
    if (v != "" && IsInteger(v))
        MainSoftData.%fieldName% := Integer(v)
}

; 系统托盘优化
CustomTrayMenu() {
    loop 30 {
        if (WinExist("ahk_class Shell_TrayWnd")) {
            break
        }
        Sleep(1000)
    }
    tipStr := MainSoftData.MyGui.Title
    if (IsProcessElevated())
        tipStr .= "`n" GetLang("管理员权限")

    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("日志中心"), (*) => LogCenterGui.ShowGui())
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("显示窗口"), (*) => RefreshGui())
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("休眠"), (*) => OnSuspendHotkey())
    A_TrayMenu.Insert(GetLang("休眠"), GetLang("开始录制"), (*) => OnTrayStartRecord())
    A_TrayMenu.Insert(GetLang("休眠"), GetLang("结束录制"), (*) => OnTrayEndRecord())
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Delete("&Suspend Hotkeys")
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Default := GetLang("显示窗口")
    A_IconTip := tipStr  ; 鼠标悬停时显示此内容
    A_IconHidden := 0   ;0(可见) 和 1(隐藏)
    TraySetIcon("Images\Soft\rabit.ico", , true)
}

OnTrayStartRecord(*) {
    if (RI_isActive || (IsSet(CD_canceled) && !CD_canceled && (IsSet(RecordCountdownGui) && RecordCountdownGui != "")))
        return
    UIControls.ToolCheckRecord.Value := true
    OnToolRecordMacro(false)
}

OnTrayEndRecord(*) {
    if (!RI_isActive && !(IsSet(CD_canceled) && !CD_canceled && (IsSet(RecordCountdownGui) && RecordCountdownGui != "")))
        return
    UIControls.ToolCheckRecord.Value := false
    OnForceEndRecord()
}

; 帮助文档首页：统一走程序目录下的 Web\index.html（源码态与发布版同名）
GetHelpDocPath() {
    return A_WorkingDir "\Web\index.html"
}

; 打开帮助文档；文件不存在时给出提示而不是抛 Run 错误
; pageHash 形如 "#/docs/commands/key"，留空则打开首页
; 三层降级：内嵌 WebView2 窗（Win10/11，自绘标题栏）→ Chromium --app 小窗 → 系统默认浏览器
OnOpenHelpDoc(pageHash := "") {
    p := GetHelpDocPath()
    if (!FileExist(p)) {
        MsgBox(GetLang("未找到帮助文档，请检查程序目录下的 Web 文件夹是否完整。"), GetLang("提示"))
        return
    }
    if (HasWebView2Runtime() && HelpDocWin.Open(pageHash))
        return
    if (OpenHelpInAppWindow(pageHash))
        return
    Run(p)   ; 没有可用的 Chromium 浏览器 → 交系统默认浏览器
}

; 探测系统是否装有 WebView2 运行时（Win10 1803+ 一般自带；Win7 没有）
; 检查 EdgeUpdate Clients 注册表里的 pv 值，三个视图都查
HasWebView2Runtime() {
    static keys := ["HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
                  , "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
                  , "HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"]
    for k in keys {
        try {
            v := Trim(RegRead(k, "pv"))
            if (v != "")
                return true
        }
    }
    return false
}

; 用 Chromium 浏览器的 --app 模式打开帮助文档（无地址栏的独立小窗）
; pageHash 形如 "#/docs/commands/key"，留空则打开首页
; winW / winH：窗口宽高。winW 默认 560（窄栏，触发站点移动端布局）；winH 传 0 表示与主窗口等高
; 返回 true = 已用 app 模式打开；false = 没找到浏览器或启动失败
OpenHelpInAppWindow(pageHash := "", winW := 560, winH := 0) {
    docPath := GetHelpDocPath()
    if (!FileExist(docPath))
        return false
    exe := FindChromiumBrowser()
    if (exe = "")
        return false

    ; 独立 user-data-dir：不与用户已开的浏览器共进程，
    ; 既不会被「恢复上次会话」/插件干扰，用户关浏览器时也不会连带关掉帮助窗
    profileDir := A_Temp "\RMT_HelpBrowser"
    if (!DirExist(profileDir))
        DirCreate(profileDir)

    ; 位置与尺寸：贴当前前台窗口（点「帮助」时就是 RMT 主窗口）右侧并等高，
    ; 右边放不下就贴左侧；完全取不到主窗口就贴主屏右侧
    mx := 0
    my := 0
    mw := 0
    mh := 0
    try WinGetPos(&mx, &my, &mw, &mh, "A")
    w := winW
    if (winW > A_ScreenWidth)
        w := A_ScreenWidth - 40
    if (mw < 200 || mh < 200) {
        x := A_ScreenWidth - w - 12
        y := 60
        h := (winH > 0) ? winH : Round(A_ScreenHeight * 0.85)
    } else {
        x := mx + mw
        y := my
        h := (winH > 0) ? winH : mh
        if (x + w > A_ScreenWidth)
            x := (mx - w >= 0) ? mx - w : A_ScreenWidth - w
    }

    cmd := '"' exe '"'
        . ' --app="' FileToFileUri(docPath) pageHash '"'
        . ' --user-data-dir="' profileDir '"'
        . ' --no-first-run --no-default-browser-check'
        . ' --window-size=' w ',' h
        . ' --window-position=' x ',' y
    try
        Run(cmd)
    catch
        return false
    return true
}

; 本地路径 → file:/// URL（--app 只接受 URL，不接受裸路径）
FileToFileUri(path) {
    p := StrReplace(path, "\", "/")
    if (!RegExMatch(p, "^[A-Za-z]:"))
        return ""
    return "file:///" UriEncode(p)
}

; UTF-8 百分号编码，保留 URL 路径中安全的字符（含 / 和 :）
; 用途：用户名/安装目录含中文或空格时，file:// URL 仍然可用
UriEncode(s) {
    buf := Buffer(StrPut(s, "UTF-8"))
    StrPut(s, buf, "UTF-8")
    out := "", i := 0
    while (i < buf.Size - 1) {
        b := NumGet(buf, i, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2F || b = 0x3A || b = 0x2D || b = 0x5F || b = 0x2E || b = 0x7E)
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
        i++
    }
    return out
}

; 探测可用的 Chromium 浏览器 exe 路径，找不到返回 ""
FindChromiumBrowser() {
    ; 1) 注册表 App Paths（Chrome / Edge；32 位进程需另查 WOW6432Node）
    for name in ["chrome.exe", "msedge.exe"] {
        for key in ["HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\"
                  , "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\"
                  , "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\"] {
            try {
                p := Trim(RegRead(key name), '" ')
                if (p != "" && FileExist(p))
                    return p
            }
        }
    }
    ; 2) 常见安装路径兜底
    pf  := EnvGet("ProgramFiles")
    pfx := EnvGet("ProgramFiles(x86)")
    lad := EnvGet("LocalAppData")
    for p in [lad "\Google\Chrome\Application\chrome.exe"
            , pf  "\Google\Chrome\Application\chrome.exe"
            , pfx "\Google\Chrome\Application\chrome.exe"
            , pfx "\Microsoft\Edge\Application\msedge.exe"
            , pf  "\Microsoft\Edge\Application\msedge.exe"
            , lad "\Microsoft\Edge\Application\msedge.exe"]
        if (FileExist(p))
            return p
    return ""
}
