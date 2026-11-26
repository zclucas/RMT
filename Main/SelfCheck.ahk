#Requires AutoHotkey v2.0

RmtAssetsReleaseTag() {
    ; 与 CI 的资源标签一致，带完整版本号：预览版与正式版资源互不覆盖。
    arch := A_PtrSize == 8 ? "x64" : "x86"
    return "v" RMT_VERSION "_" arch
}

CheckStartupDirectory(rootDir) {
    settingDir := rootDir "\Setting"
    for dir in [rootDir, settingDir] {
        if (dir == settingDir && !FileExist(dir))
            continue
        if (CanCreateStartupFiles(dir))
            continue
        MsgBox("RMT 需要在软件目录中创建文件夹和配置文件，但以下目录无法正常读写："
            . "`n`n" dir "`n`n请将整个 RMT 软件文件夹移到有读写权限的位置，再重新运行。"
            , "RMT 目录权限", "Icon!")
        return false
    }
    return true
}

CanCreateStartupFiles(dir) {
    ; FILE_LIST_DIRECTORY，OPEN_EXISTING，FILE_FLAG_BACKUP_SEMANTICS（打开目录）。
    dirHandle := DllCall("CreateFileW", "Str", dir, "UInt", 1, "UInt", 7,
        "Ptr", 0, "UInt", 3, "UInt", 0x02000000, "Ptr", 0, "Ptr")
    if (dirHandle == -1)
        return false
    DllCall("CloseHandle", "Ptr", dirHandle)

    probe := dir "\.rmt-access-" DllCall("GetCurrentProcessId", "UInt") "-" Random(0, 0x7FFFFFFF)

    ; GENERIC_READ | GENERIC_WRITE，CREATE_NEW，FILE_FLAG_DELETE_ON_CLOSE。
    ; 只创建新文件，关闭句柄后自动清理。
    probeHandle := DllCall("CreateFileW", "Str", probe ".tmp", "UInt", 0xC0000000, "UInt", 0,
        "Ptr", 0, "UInt", 1, "UInt", 0x04000000, "Ptr", 0, "Ptr")
    if (probeHandle == -1)
        return false
    DllCall("CloseHandle", "Ptr", probeHandle)

    if (!DllCall("CreateDirectoryW", "Str", probe, "Ptr", 0))
        return false
    return !!DllCall("RemoveDirectoryW", "Str", probe)
}

; =============================================================================
; 启动前环境预检（原生界面，必须先于 XAML 引擎）
;
; 位置：RMT.ahk 里 XAMLHost.Prewarm() 之前。原因很直接——XAML 引擎本身是托管
; 程序集（ahk-xaml-wv2.dll 的导入表只有 mscoree!_CorExeMain），靠 .NET Framework 4
; 承载。.NET 缺失时引擎起不来，主窗和所有 RmtDialog / RmtProgress 都画不出来，
; 用户看到的就是「只有托盘、点了没反应」。所以这一段只能用 MsgBox 和原生进度窗。
;
; 顺序由依赖决定，不能调换：
;   KB4474419（SHA-2 签名）→ .NET Framework 4.8 →（引擎起来后）VC++ → DirectX
; Win7 没装 KB4474419 时，.NET 与 vc_redist 这两个微软签名的安装包会被判
; 「不是有效的 Win32 应用程序」，或者装到一半静默回滚。
;
; 资源都在 RMTAssets 的 Patch 标签，和 directx_Jun2010_redist、segmdl2.ttf 同处。
; 非 Win7 逐项下载；Win7 连不上网，改用 Patch 里的离线运行环境包 Runtime_x64/x86.zip——
; 包里是这组安装包 + InstallRuntime.bat，解压后双击脚本一次装齐（脚本自己判状态、判重启）。
; =============================================================================

; 返回 true 表示环境够启动；false 时调用方直接退出，不再往下走。
;
; 缺一项就装一项、装完要求重启再来一次，这是刻意的：
; KB4474419 和 KB4019990 都是 CBS 补丁，装完必须重启才真正生效，
; 在同一次开机里紧接着跑 .NET 4.8 安装器，签名校验和文件版本校验都还是旧的，
; 结果就是回滚，用户只会看到「自动安装根本没用」。
RuntimePrecheck() {
    RuntimeEnableTls12()

    netReady := NetFxReady()
    if (!netReady && RuntimeIsWin7()) {
        ; Win7 上装不了任何一项（全部依赖网络），先一次性讲清楚再退出，
        ; 免得用户点了「安装」才发现下载不了。
        if (RuntimeNeedsOfflineOnWin7()) {
            RuntimeOfflinePrompt()
            return false
        }

        ; .NET 4.8 与 vc_redist 都要求 Win7 SP1，RTM 版本装了也会失败
        if (!RuntimeHasSp1()) {
            msg := "本机是 Windows 7，但没有安装 Service Pack 1。`n`n"
                . "RMT 依赖的 .NET Framework 4.8 无法在 RTM 版本上安装。`n"
                . "请先把系统升级到 SP1，再重新运行 RMT。"
            MsgBox(msg, "RMT 运行环境", "Icon!")
            return false
        }

        ; 1) SHA-2 代码签名（KB4474419）：.NET 与 vc_redist 的安装包都是 SHA-2 签名
        ; 只在真要装 .NET 时才问：.NET 已就绪的 Win7 不该每次启动都被拦一次。
        if (!Sha2PatchInstalled()) {
            if (!Sha2PatchEnsureInstalled())
                return false
            MsgBox("KB4474419 已安装，必须重启计算机后才能继续。`n`n"
                . "重启后请重新运行 RMT，程序会接着检查并安装 .NET Framework 4.8。"
                , "RMT 运行环境", "Icon!")
            return false
        }

        ; 2) .NET 4.7 及以后的安装器在 Win7 上还要求 D3DCompiler_47（KB4019990）
        if (!D3DCompilerReady()) {
            if (!D3DCompilerEnsureInstalled())
                return false
            if (!D3DCompilerReady()) {
                MsgBox("KB4019990 已安装，但 d3dcompiler_47.dll 还没生效。`n`n"
                    . "请重启计算机后重新运行 RMT。", "RMT 运行环境", "Icon!")
                return false
            }
        }
    }

    ; XAML 引擎的宿主。缺了就退出：没有它连一个提示窗口都弹不出来。
    if (!netReady && !NetFxEnsureInstalled())
        return false
    return true
}

; ---- 系统版本 ----
RuntimeOsVersion() {
    try
        return RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentVersion")
    catch
        return ""
}

RuntimeIsWin7() {
    return RuntimeOsVersion() = "6.1"
}

; 系统位数（不是进程位数）。系统补丁要按 OS 位数选包：
; 32 位进程跑在 64 位系统上时，PROCESSOR_ARCHITEW6432 才有值。
RuntimeOs64Bit() {
    return (A_PtrSize == 8 || EnvGet("PROCESSOR_ARCHITEW6432") != "") ? true : false
}

RuntimeHasSp1() {
    try {
        csd := RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CSDVersion")
    } catch {
        return false
    }
    return InStr(csd, "Service Pack 1") ? true : false
}

; ---- 下载前放开 TLS 1.2 ----
; Msxml2.XMLHTTP 走 WinINET，Win7 默认只启用 TLS 1.0；GitCode 与 GitHub 都要求
; TLS 1.2。不放开的话 readyState 永远到不了 4，表现为超时而不是明确报错。
; INTERNET_OPTION_SECURE_PROTOCOLS = 84；TLS 1.0|1.1|1.2 = 0xA80。仅作用于本进程。
RuntimeEnableTls12() {
    proto := 0x0A80
    try {
        DllCall("wininet\InternetSetOptionW", "Ptr", 0, "UInt", 84, "UInt*", &proto, "UInt", 4, "Int")
    } catch {
        ; 设置失败不阻断：真下载不了时，提示里会说明可能是 TLS 问题
    }
}

; ---- KB4474419（SHA-2 代码签名支持）----
Sha2PatchInstalled() {
    ; 补丁落盘后会在 servicing\Packages 留下 Package_for_KB4474419 的 mum。
    ; 用文件判断而不是注册表：卸载补丁后文件会消失，也不依赖自定义标记。
    return FileExist(A_WinDir "\servicing\Packages\Package_for_KB4474419*") ? true : false
}

Sha2PatchAssetName() {
    return RuntimeOs64Bit()
        ? "windows6.1-kb4474419-v3-x64_b5614c6cea5cb4e198717789633dca16308ef79c.msu"
        : "windows6.1-kb4474419-v3-x86_0f687d50402790f340087c576886501b3223bec6.msu"
}

Sha2PatchEnsureInstalled() {
    msg := "检测到本机缺少 Windows 7 的 SHA-2 代码签名补丁（KB4474419）。`n`n"
        . "微软的 .NET Framework 4.8 和 VC++ 运行库安装包都用 SHA-2 签名，"
        . "缺少它时会报「不是有效的 Win32 应用程序」，或者装到一半静默回滚。`n`n"
        . "是否现在自动安装？（约 55 MB，需要管理员权限）"
    if (MsgBox(msg, "RMT 运行环境", "YesNo Icon?") != "Yes")
        return false
    return Sha2PatchInstall()
}

Sha2PatchInstall() {
    expectSize := RuntimeOs64Bit() ? 55853327 : 35919018
    file := RuntimePrepareAsset(Sha2PatchAssetName(), "正在下载 Windows 7 安全更新（KB4474419）…", expectSize)
    if (file = "")
        return false

    wusa := A_WinDir "\System32\wusa.exe"
    cmd := '*RunAs "' wusa '" "' file '" /quiet /norestart'
    exitCode := -1
    try {
        exitCode := RunWait(cmd, , "Hide")
    } catch {
    }
    ; 0 = 成功；3010 = 成功需重启；2359302 (0x00240006) = 该更新已经装过
    ; 不拿 mum 文件做二次确认：CBS 有时要等重启才把 Package_for_KB4474419 落盘，
    ; 那属于「装好了但要重启」，在这里报错反而误导；重启后预检会重新检测。
    if (exitCode = 0 || exitCode = 3010 || exitCode = 2359302)
        return true

    tip := "安装 KB4474419 未能完成（退出码 " exitCode "）。`n`n"
        . "常见原因：取消了管理员授权、系统是精简版、或已装更高版本的同类补丁。`n`n"
        . "可手动下载安装：`nhttps://www.catalog.update.microsoft.com/Search.aspx?q=KB4474419"
    MsgBox(tip, "RMT 运行环境", "Icon!")
    return false
}

; ---- KB4019990（d3dcompiler_47.dll）----
; .NET Framework 4.7 及以后的安装器会在 Win7 SP1 上检查 System32\d3dcompiler_47.dll，
; 缺了直接判「不支持的操作系统」或装到一半回滚（KB4019990 就是补这个组件）。
; 干净的 Win7 SP1 只有 d3dcompiler_43/46；47 要等 IE11 或月度汇总才带上。
D3DCompilerReady() {
    return FileExist(A_WinDir "\System32\d3dcompiler_47.dll") ? true : false
}

D3DCompilerAssetName() {
    return RuntimeOs64Bit()
        ? "windows6.1-kb4019990-x64.msu"
        : "windows6.1-kb4019990-x86.msu"
}

D3DCompilerEnsureInstalled() {
    msg := "本机缺少 D3DCompiler_47 组件（KB4019990）。`n`n"
        . ".NET Framework 4.7 及以后的安装器在 Windows 7 上会先检查它，"
        . "缺少时会把系统判为「不支持」并回滚安装。`n`n"
        . "是否现在自动安装？（约 1.5 MB，需要管理员权限）"
    if (MsgBox(msg, "RMT 运行环境", "YesNo Icon?") != "Yes")
        return false
    return D3DCompilerInstall()
}

D3DCompilerInstall() {
    expectSize := RuntimeOs64Bit() ? 2873529 : 1424481
    file := RuntimePrepareAsset(D3DCompilerAssetName(), "正在下载 Windows 7 组件更新（KB4019990）…", expectSize)
    if (file = "")
        return false

    wusa := A_WinDir "\System32\wusa.exe"
    exitCode := -1
    try {
        exitCode := RunWait('*RunAs "' wusa '" "' file '" /quiet /norestart', , "Hide")
    } catch {
    }
    ; 0 = 成功；3010 = 成功需重启；2359302 (0x00240006) = 该更新已经装过
    if (exitCode = 0 || exitCode = 3010 || exitCode = 2359302)
        return true

    tip := "安装 KB4019990 未能完成（退出码 " exitCode "）。`n`n"
        . "常见原因：取消了管理员授权、系统是精简版。`n`n"
        . "可手动下载安装：`nhttps://www.catalog.update.microsoft.com/Search.aspx?q=KB4019990"
    MsgBox(tip, "RMT 运行环境", "Icon!")
    return false
}

; ---- .NET Framework 4 ----
; XAML 引擎用 CorBindToRuntimeEx("v4.0.30319") 起 CLR，所以至少要 4.0。
; Release 是官方版本门槛：4.5 = 378389，4.6 = 393295，4.7.2 = 461808，4.8 = 528040。
; 这里按 4.8 判定：低于它就提示装 4.8——Win7 上 4.8 是最后一个版本，
; 一步装到位，不必逐级升。
NetFxRelease() {
    try rel := RegRead("HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full", "Release")
    catch
        return 0
    if (rel = "")
        return 0
    return Integer(rel)
}

NetFxReady() {
    return NetFxRelease() >= 528040
}

; Release 数值转可读版本，用于提示文案（对照微软官方版本表）
NetFxVersionName(rel) {
    if (rel >= 528040)
        return "4.8"
    if (rel >= 461808)
        return "4.7.2"
    if (rel >= 461308)
        return "4.7.1"
    if (rel >= 460798)
        return "4.7"
    if (rel >= 394802)
        return "4.6.2"
    if (rel >= 394254)
        return "4.6.1"
    if (rel >= 393295)
        return "4.6"
    if (rel >= 379893)
        return "4.5.2"
    if (rel >= 378758)
        return "4.5.1"
    if (rel >= 378389)
        return "4.5"
    return "4.0"
}

NetFxEnsureInstalled() {
    rel := NetFxRelease()
    verText := (rel > 0)
        ? ("当前是 " NetFxVersionName(rel) "（Release " rel "），低于 RMT 要求的 4.8")
        : "当前未安装"
    msg := "检测到本机的 .NET Framework 版本不足（" verText "）。`n`n"
        . "RMT 的主界面和全部提示窗口都由 .NET 承载，缺少它时程序只能待在托盘里，"
        . "点开也没有任何界面。`n`n"
        . "是否现在自动安装 .NET Framework 4.8？（约 121 MB，需要管理员权限）"
    if (MsgBox(msg, "RMT 运行环境", "YesNo Icon?") != "Yes")
        return false
    return NetFxInstall()
}

NetFxInstall() {
    file := RuntimePrepareAsset("NDP48-x86-x64-AllOS-ENU.exe", "正在下载 .NET Framework 4.8…", 121346568)
    if (file = "")
        return false

    cmd := '*RunAs "' file '" /q /norestart'
    exitCode := -1
    try {
        exitCode := RunWait(cmd, , "Hide")
    } catch {
    }
    ; 0 = 成功；3010 = 成功需重启；1641 = 已重启；5100 = 需要重启才能完成
    if (exitCode = 0 || exitCode = 3010 || exitCode = 1641 || exitCode = 5100) {
        if (NetFxReady())
            return true
        MsgBox("安装程序已完成，但系统需要重启后才生效。`n`n请重启计算机后重新运行 RMT。"
            , "RMT 运行环境", "Icon!")
        return false
    }

    tip := "安装 .NET Framework 4.8 未能完成（退出码 " exitCode "）。`n`n"
        . "常见原因：`n"
        . "  · 取消了管理员授权；`n"
        . "  · 缺少 KB4474419（SHA-2 签名）——刚装完请重启后重试；`n"
        . "  · 缺少 KB4490628（Win7 服务堆栈更新），表现是装到一半 0x80070643 回滚；`n"
        . "  · 缺少 KB4019990（d3dcompiler_47），表现是提示系统不受支持。`n`n"
        . "可手动下载离线包安装：`nhttps://dotnet.microsoft.com/download/dotnet-framework/net48"
    MsgBox(tip, "RMT 运行环境", "Icon!")
    return false
}

; ---- 资源获取 ----
; 离线副本：把安装包放进 <RMT目录>\Runtime\ 就直接用，完全跳过网络。
; 零环境的机器上网络是最不可控的一环，先给一条确定能走通的路。
; VC 与 DirectX 也走这里，所以三者的离线用法完全一致。
RuntimeOfflineAsset(name) {
    path := A_ScriptDir "\Runtime\" name
    return FileExist(path) ? path : ""
}

; 离线运行环境压缩包，放在 RMTAssets 的 Patch 里，按系统位数分两个：
; 包里是 KB4474419 + KB4019990 + .NET 4.8 + VC + segmdl2.ttf，以及一键安装脚本
; InstallRuntime.bat（脚本和安装包放在一起，解压即用，和 RMT 本体无关）。
RuntimeOfflineBundleName() {
    return "Runtime_" (RuntimeOs64Bit() ? "x64" : "x86") ".zip"
}

RuntimeOfflineBundleUrl() {
    ; 手工下载必须提供完整包，浏览器不会运行分片合并器。
    return RmtAssetsBaseUrl("Patch") RuntimeOfflineBundleName()
}

; Win7 在线版：三项系统组件里任意一项缺、且没有对应离线副本，就说明这个包不能用。
RuntimeNeedsOfflineOnWin7() {
    if (!Sha2PatchInstalled() && RuntimeOfflineAsset(Sha2PatchAssetName()) = "")
        return true
    if (!D3DCompilerReady() && RuntimeOfflineAsset(D3DCompilerAssetName()) = "")
        return true
    if (!NetFxReady() && RuntimeOfflineAsset("NDP48-x86-x64-AllOS-ENU.exe") = "")
        return true
    return false
}

; Win7 上缺组件时的统一出口：不联网，引导去拿离线运行环境压缩包。
; name 非空时额外说明还缺哪个文件。
RuntimeOfflinePrompt(name := "") {
    url := RuntimeOfflineBundleUrl()
    msg := "当前是 Windows 7，RMT 无法自动联网安装环境组件。`n`n"
        . "原因：Windows 7 默认未启用 TLS 1.2，根证书库也缺少 GitHub 与 CDN 使用的根证书，"
        . "系统自带的下载组件又不支持忽略证书错误。`n`n"
        . "请在任意一台能上网的电脑下载离线运行环境包（" RuntimeOfflineBundleName() "）：`n"
        . url "`n备用下载地址：`n" RmtDownloadDirectUrl(url) "`n`n"
        . "拷到本机解压，双击解压出来的 InstallRuntime.bat，它会按依赖顺序装齐全部组件，"
        . "中途需要重启就重启后把脚本再跑一次。装完再启动 RMT 即可。"
    if (name != "")
        msg .= "`n`n当前还缺文件：" name
    MsgBox(msg, "RMT 运行环境", "Icon!")
}

; 返回本地安装包路径；失败返回 ""。
; 先看 <RMT目录>\Runtime\ 的离线副本（用户可手工放置，绕过网络问题），
; 再复用软件目录 Cache\RMT-Setup 里上次下完的文件，最后才联网下载。
; expectSize 用来识别上次被中断的半成品：尺寸不够就删掉重下，否则会一直复用坏包。
RuntimePrepareAsset(name, hint, expectSize := 0) {
    offline := RuntimeOfflineAsset(name)
    if (offline != "")
        return offline

    ; Win7 不做网络尝试：干净系统没启用 TLS 1.2，根证书库也缺 GitHub/CDN 用的根证书，
    ; 而 WinINET 不支持忽略证书错误，硬试只会等满超时。直接引导用离线版。
    if (RuntimeIsWin7()) {
        RuntimeOfflinePrompt(name)
        return ""
    }

    dir := RmtCacheDir() "\RMT-Setup\" RmtAssetsReleaseTag()
    if (!DirExist(dir))
        try DirCreate(dir)
    path := dir "\" name
    if (FileExist(path)) {
        if (expectSize <= 0 || FileGetSize(path) >= expectSize)
            return path
        try FileDelete(path)
    }

    pg := NativeProgress("RMT 运行环境", hint)
    pg.Show()
    result := ""
    try {
        url := RmtAssetsBaseUrl("Patch") name
        result := DownloadResourceWithRetry(url, path, 3600, pg)
    } finally pg.Close()

    if (result = "ok")
        return path

    try FileDelete(path)
    msg := "下载失败：" hint "`n`n"
        . "可能是网络不通、代理不可用，或系统缺少 TLS 1.2 支持。`n`n"
        . "可以把安装包手动下载后放到：`n" A_ScriptDir "\Runtime\" name
    MsgBox(msg, "RMT 运行环境", "Icon!")
    return ""
}

; 原生进度窗：.NET / XAML 都还没就绪时唯一可用的进度提示。
; 下载进度接口与 RmtProgress 对齐。
class NativeProgress {
    percent := 0
    Cancelled := false
    gui := 0

    __New(title, text) {
        g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
        g.MarginX := 16, g.MarginY := 14
        g.SetFont("s9", "Microsoft YaHei")
        this.txt := g.Add("Text", "w400", text)
        this.bar := g.Add("Progress", "w400 h14 Range0-100", 0)
        this.sub := g.Add("Text", "w400 cGray", "已用时 0 秒")
        this.alternativeLabel := g.AddText("w400 Hidden", "备用下载地址")
        this.alternativeUrl := g.AddEdit("w400 r3 ReadOnly -VScroll Hidden")
        g.OnEvent("Close", (*) => this.Cancelled := true)
        g.Show("AutoSize Center")
        this.gui := g
        this.startTick := A_TickCount
        SetTimer(ObjBindMethod(this, "Tick"), 500)
    }

    ; 构造时已经显示；保留同名方法是为了和 RmtProgress 的调用习惯一致（调用方无需分支）
    Show() {
    }

    Report(msg, pct) {
        this.percent := pct
        try {
            this.txt.Value := msg
            this.bar.Value := Round(pct)
        }
    }

    SetDownloadAlternative(url, label := "备用下载地址") {
        if (this.alternativeUrl.Value == url)
            return
        this.alternativeLabel.Value := label
        this.alternativeUrl.Value := url
        this.alternativeLabel.Visible := url != ""
        this.alternativeUrl.Visible := url != ""
        this.gui.Show("AutoSize NA")
    }

    Tick() {
        if (!this.gui)
            return
        sec := Round((A_TickCount - this.startTick) / 1000)
        try {
            this.sub.Value := "已用时 " sec " 秒（下载速度取决于网络，请勿关闭窗口）"
        }
    }

    Close() {
        SetTimer(ObjBindMethod(this, "Tick"), 0)
        try this.gui.Destroy()
        this.gui := 0
    }
}

; RmtAssetsBaseUrl 定义在 AssetUtil.ahk：Worker 进程也 include 它，而 SelfCheck 不在 Worker 链里。
SelfCheckMissingFiles() {
    ; 运行库是其余插件的底座，先修它。齐全时零界面，不会多弹东西。
    VcRuntimeEnsureInstalled(true)
    ; 手柄组件只影响 Xbox 手柄的高级按键（扳机/Guide），排在运行库之后
    DirectXEnsureInstalled(true)

    arch := A_PtrSize == 8 ? "x64" : "x86"
    bitArch := A_PtrSize == 8 ? "64bit" : "32bit"
    tag := RmtAssetsReleaseTag()
    baseUrl := RmtAssetsBaseUrl(tag)
    ; 源码与开发编译版可使用带 WebView2 后缀的引擎，发行版资源包的条目名固定。
    xamlDir := !A_IsCompiled && XAML_ENGINE_BUILD_LOCATION != "lib/dep"
        ? "Cache\AhkWpf\" : "Plugins\AHK-XAML\lib\dep\"

    criticalFiles := [
        {path: "Plugins\Browser\RMT_Browser.dll", entry: "RMT_Browser.dll", bundle: "RMT.zip"},
        {path: "Plugins\RMT\RMT.dll", entry: "RMT.dll", bundle: "RMT.zip"},
        {path: "Plugins\RMT\RMT.ExcelHelper.exe", entry: "RMT.ExcelHelper.exe", bundle: "RMT.zip"},
        {path: "Plugins\IbInputSimulator.dll", entry: "IbInputSimulator.dll", bundle: "Input.zip"},
        {path: "Audio\Start.wav", entry: "Start.wav", bundle: "Audio.zip"},
        {path: "Audio\End.wav", entry: "End.wav", bundle: "Audio.zip"},
        {path: "Plugins\ViGEm\ViGEmWrapper.dll", entry: "ViGEmWrapper.dll", bundle: "ViGEm.zip"},
        {path: "Plugins\Joy\ViGEmBus.exe", entry: "ViGEmBus.exe", bundle: "ViGEm.zip"},
        {path: xamlDir XAMLHost.GetEngineDllName(), entry: "ahk-xaml.dll", bundle: "Xaml.zip"},
        {path: "Plugins\AHK-XAML\lib\dep\WpfAnimatedGif\WpfAnimatedGif.dll", entry: "WpfAnimatedGif.dll", bundle: "Xaml.zip"},
        {path: "Plugins\OpenCV\" arch "\RMT_OpenCV.dll", entry: "RMT_OpenCV.dll", bundle: "OpenCV.zip"},
        {path: "Plugins\OpenCV\" arch "\opencv_world481.dll", entry: "opencv_world481.dll", bundle: "OpenCV.zip"},
        {path: "Plugins\RapidOcr\" bitArch "\RapidOcrOnnx.dll", entry: "RapidOcrOnnx.dll", bundle: "RapidOcr.zip"},
        {path: "Plugins\TesseractOcr\" arch "\tesseract50.dll", entry: "tesseract50.dll", bundle: "TesseractOcr.zip"},
        {path: "Plugins\TesseractOcr\" arch "\leptonica-1.82.0.dll", entry: "leptonica-1.82.0.dll", bundle: "TesseractOcr.zip"},
        {path: "Plugins\TesseractOcr\tessdata\chi_sim.traineddata", entry: "chi_sim.traineddata", bundle: "TesseractOcr.zip"},
        {path: "Plugins\TesseractOcr\tessdata\eng.traineddata", entry: "eng.traineddata", bundle: "TesseractOcr.zip"},
        {path: "Plugins\ScreenCapture\ScreenCapture.exe", entry: "ScreenCapture.exe", bundle: "OpenCV.zip"},
        {path: "Plugins\AhiDriver\AutoHotInterception.dll", entry: "AutoHotInterception.dll", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\" arch "\interception.dll", entry: "interception_" arch ".dll", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\installer\install.ps1", entry: "install.ps1", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\installer\安装卸载.bat", entry: "InstallUninstall.bat", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\installer\install-interception.exe", entry: "install-interception.exe", bundle: "AhiDriver.zip"},
        {path: "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_det.onnx", entry: "ch_PP-OCRv6_det.onnx", bundle: "RapidOcr.zip"},
        {path: "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_rec.onnx", entry: "ch_PP-OCRv6_rec.onnx", bundle: "RapidOcr.zip"},
        {path: "Plugins\RapidOcr\ch_models\ppocrv6_tiny_dict.txt", entry: "ppocrv6_tiny_dict.txt", bundle: "RapidOcr.zip"},

        {path: "Thread\Work.exe", entry: "Work.exe", bundle: "RMT.zip"},
        {path: GetHelpDocRelativePath(), entry: "index.html", bundle: "RMT.zip"},
    ]
    for name, language in OfficialLanguages() {
        if (language.HasOwnProp("entry"))
            criticalFiles.Push({path: "Lang\" name ".txt", entry: language.entry, bundle: "Lang.zip"})
        criticalFiles.Push({path: "Lang\Flags\" language.flag ".png", entry: "Flags/" language.flag ".png", bundle: "Lang.zip"})
    }
    optionalFiles := [
        {path: "Plugins\Browser\LICENSE.txt", entry: "Browser-LICENSE.txt", bundle: "RMT.zip"},
        {path: "Plugins\MouseControl.dll", entry: "MouseControl.dll", bundle: "Input.zip"},
        {path: "Plugins\AhiDriver\installer\使用说明.txt", entry: "InstallReadme.txt", bundle: "AhiDriver.zip"},
        ; YOLO 是可选指令：缺了只影响这一个指令，不该按关键文件告警，
        ; 但要能被「文件校验」查出来并一键补齐。清单与 Yolo.Files 保持一致。
        {path: "Plugins\YOLO\" arch "\RMT_YOLO.dll", entry: "RMT_YOLO.dll", bundle: "Yolo.zip"},
        {path: "Plugins\YOLO\" arch "\onnxruntime.dll", entry: "onnxruntime.dll", bundle: "Yolo.zip"},
        {path: "Plugins\YOLO\" arch "\onnxruntime_providers_shared.dll", entry: "onnxruntime_providers_shared.dll", bundle: "Yolo.zip"},
    ]
    ; 源码运行时，RmtUpdate 可直接用 AutoHotkey 启动 Update.ahk。
    if (A_IsCompiled || RmtAssetMissing(A_ScriptDir "\Thread\Update.ahk"))
        optionalFiles.InsertAt(2, {path: "Thread\Update.exe", entry: "Update.exe", bundle: "RMT.zip"})
    ; 翻译同样是可选指令：DLL 缺失只影响这一个指令；模型 1.3 GB 不进包，走按需下载。
    ; 只提供 x64：2B 模型的常驻内存放不进 32 位地址空间，32 位包里没有这个插件。
    ; CPU 变体后端与 llama.cpp 的 MSVC 变体表对应（x64/sse42/sandybridge/haswell/
    ; skylakex/cannonlake/cascadelake/icelake/alderlake），升级 llama.cpp 若增删变体要同步这里。
    ; ggml-vulkan.dll 是官方 b12540 预编译件（体积 43 MB，着色器已内嵌），
    ; 有显卡的机器走 GPU 推理，没有 vulkan-1.dll 的机器加载失败自动落 CPU。
    if (arch == "x64") {
        optionalFiles.Push({path: "Plugins\Translate\x64\TranslateDll.dll", entry: "TranslateDll.dll", bundle: "Translate.zip"})
        optionalFiles.Push({path: "Plugins\Translate\x64\llama.dll", entry: "llama.dll", bundle: "Translate.zip"})
        optionalFiles.Push({path: "Plugins\Translate\x64\ggml.dll", entry: "ggml.dll", bundle: "Translate.zip"})
        optionalFiles.Push({path: "Plugins\Translate\x64\ggml-base.dll", entry: "ggml-base.dll", bundle: "Translate.zip"})
        optionalFiles.Push({path: "Plugins\Translate\x64\ggml-vulkan.dll", entry: "ggml-vulkan.dll", bundle: "Translate.zip"})
        for _, cpuVariant in ["x64", "sse42", "sandybridge", "haswell", "skylakex", "cannonlake", "cascadelake", "icelake", "alderlake"]
            optionalFiles.Push({path: "Plugins\Translate\x64\ggml-cpu-" cpuVariant ".dll", entry: "ggml-cpu-" cpuVariant ".dll", bundle: "Translate.zip"})
    }

    icoFileList := ["Wait.png", "BGKey.png", "IcoRunning.ico", "Joy.png", "DeltaMove.png", "KeyListen.png", "JoyListen.png", "SearchCombo.png", "Excel.png", "Time.png", "WaitConfirm.png", "RunPro.png",
        "Arr.png", "Condition.png", "Control.png", "FlowJump.png", "Extract.png", "False.png",
        "HttpRequest.png", "Browser.png", "AiDecision.png", "FileIO.png", "IcoPause.ico", "If.png", "IfPro.png",
        "Input.png", "Key.png", "Loop.png",
        "LoopBody.png", "LoopCount.png", "Mouse.png", "Move.png", "MovePro.png",
        "Operation.png", "Output.png", "Prompt.png", "Run.png", "Search.png",
        "SearchPro.png", "SearchAll.png", "MacroAction.png", "TextOps.png", "True.png",
        "Var.png", "WeiXin.png", "WindowManage.png", "WindowAdjustGear32.png", "ControlInfo.png", "ControlOperation.png", "ProcessManage.png",
        "ZhiFuBao.png", "AiFaDian.png", "Stripe2.png", "Stripe5.png", "rabit.ico", "rabit.png", "Comment.png", "ScreenShot.png"]

    for name in icoFileList
        criticalFiles.Push({path: "Images\Soft\" name, entry: name, bundle: "ico.zip"})

    allMissing := []
    missingCritical := 0
    missingOptional := 0
    downloads := Map()
    for groupIndex, files in [criticalFiles, optionalFiles] {
        isCritical := groupIndex == 1
        for file in files {
            file.fullPath := A_WorkingDir "\" file.path
            if (!RmtAssetMissing(file.fullPath))
                continue

            file.critical := isCritical
            allMissing.Push(file)
            if (isCritical)
                missingCritical++
            else
                missingOptional++

            url := baseUrl file.bundle
            if (!downloads.Has(url))
                downloads[url] := {name: file.bundle, files: []}
            downloads[url].files.Push(file)
        }
    }

    totalMissing := allMissing.Length
    if (totalMissing == 0) {
        RmtDialog.Info(GetLang("资源文件校验通过，未发现缺失文件"), GetLang("RMT 资源自检"), 64)
        return
    }

    fileListStr := ""
    showCount := Min(allMissing.Length, 5)
    loop showCount
        fileListStr .= "  · " allMissing[A_Index].path "`n"
    if (allMissing.Length > 5)
        fileListStr .= "  ... 等 " allMissing.Length " 个文件`n"

    detailStr := ""
    if (missingCritical > 0)
        detailStr .= "⚠ 关键文件 (" missingCritical ")`n"
    if (missingOptional > 0)
        detailStr .= "可选文件 (" missingOptional ")"
    tipMsg := "检测到 " totalMissing " 个资源文件缺失`n" detailStr "`n`n" fileListStr "`n版本：" tag "`n点击【取消】跳过下载，部分功能可能不可用。"

    result := RmtDialog.Choose(tipMsg, GetLang("RMT 资源自检"), [GetLang("下载"), GetLang("取消")])
    if (result != 1) {
        if (missingCritical > 0) {
            criticalNames := ""
            for file in allMissing {
                if (file.critical)
                    criticalNames .= file.path "`n"
            }
            RmtDialog.Info("以下关键文件缺失，软件可能无法正常运行：`n`n" criticalNames "`n`n请在QQ群 837661891 或者项目仓库寻求帮助", "RMT 警告", 16)
        }
        return
    }

    pg := RmtProgress(GetLang("RMT 资源下载"), GetLang("准备下载"), XamlWin.ActiveOwner(), GetLang("取消下载"))
    pg.Show()
    cancelled := false
    try {
        for url, download in downloads {
            pg.Report("正在下载：" download.name, 100 * (A_Index - 1) / downloads.Count)
            result := DownloadRmtAssetBundle(url, download.files, pg)
            if (result == "cancel") {
                cancelled := true
                break
            }
        }
    } finally pg.Close()

    failed := []
    stillCritical := false
    for file in allMissing {
        if (RmtAssetMissing(file.fullPath)) {
            failed.Push(file.path)
            stillCritical := stillCritical || file.critical
        }
    }

    successCount := totalMissing - failed.Length
    if (cancelled) {
        cancelMsg := "下载已取消。`n已成功补齐 " successCount "/" totalMissing " 个文件。`n可再次点击「文件校验」继续下载。"
        if (stillCritical)
            cancelMsg .= "`n`n仍有关键文件缺失，软件可能无法正常工作。"
        RmtDialog.Info(cancelMsg, "RMT 资源自检", 64)
    } else if (failed.Length) {
        failStr := ""
        for path in failed
            failStr .= path "`n"
        RmtDialog.Info("已补齐 " successCount "/" totalMissing " 个文件。`n`n以下文件修复失败：`n" failStr,
            "RMT 资源自检", stillCritical ? 16 : 48)
    } else {
        RmtDialog.Info("已补齐 " successCount " 个资源文件。", "RMT 资源自检", 64)
    }
}

; 等待下载结束并处理进度/取消；返回 ok、cancel 或 fail，并非异步任务句柄。
DownloadResourceWithRetry(url, savePath, timeoutSec, pg) {
    maxRetry := 3
    ; Win7 走网络基本必然失败（TLS 1.2 默认未启用 + 缺 GitHub/CDN 的根证书），
    ; 按原来的 3 轮长超时会把界面挂住十几分钟。这里压到 1 轮、最长 120 秒，
    ; 让用户尽快看到「下载失败」而不是以为程序死了。
    if (RuntimeIsWin7()) {
        maxRetry := 1
        if (timeoutSec > 120)
            timeoutSec := 120
    }
    alternative := RmtDownloadDirectUrl(url)
    if (alternative != "")
        maxRetry := Max(maxRetry, 2)
    Loop maxRetry {
        if (pg.Cancelled)
            return "cancel"

        if (A_Index > 1)
            pg.Report(Format("重试 ({}/{})...", A_Index - 1, maxRetry - 1), pg.percent)

        result := DownloadResourceOnce(A_Index > 1 && alternative != "" ? alternative : url, savePath, timeoutSec, pg)
        if (result == "ok")
            return "ok"
        if (result == "cancel")
            return "cancel"
        if (FileExist(savePath))
            FileDelete(savePath)

        if (A_Index < maxRetry)
            Sleep(1000)
    }
    return "fail"
}

DownloadResourceOnce(url, savePath, timeoutSec, pg) {
    systemDir := A_PtrSize == 4 && A_Is64bitOS ? "\Sysnative" : "\System32"
    curl := A_WinDir systemDir "\curl.exe"
    if (FileExist(curl) && (RmtIsAssetUrl(url) || HasMethod(pg, "SetDownloadAlternative")))
        return DownloadResourceWithCurl(curl, url, savePath, timeoutSec, pg)

    try {
        req := ComObject("Msxml2.XMLHTTP")
        req.open("GET", url, true)
        req.send()

        startTime := A_TickCount
        Loop {
            if (pg.Cancelled) {
                req.abort()
                return "cancel"
            }

            if (req.readyState == 4)
                break

            elapsed := (A_TickCount - startTime) / 1000
            if (elapsed > timeoutSec) {
                req.abort()
                return "timeout"
            }

            Sleep(200)
        }

        if (req.status == 200) {
            stream := ComObject("ADODB.Stream")
            stream.Type := 1
            stream.Open()
            stream.Write(req.responseBody)
            stream.SaveToFile(savePath, 2)
            stream.Close()
            return "ok"
        }
        return "fail"
    } catch as e {
        pg.Report("✗ 下载异常: " e.Message, pg.percent)
        return "fail"
    }
}

DownloadResourceWithCurl(curl, url, savePath, timeoutSec, pg) {
    headers := savePath ".headers"
    cmd := Format('"{}" -q -L --fail -s -S --suppress-connect-headers --max-time {} -D "{}" -o "{}" "{}"',
        curl, timeoutSec, headers, savePath, url)
    pid := 0
    total := 0
    started := A_TickCount
    label := GetLang("备用下载地址")
    sample := SampleDownload
    try {
        if (RmtIsAssetUrl(url))
            cmd := RmtAssetDownloadCommand(url, savePath, headers, timeoutSec)
        SetTimer(sample, 500)
        status := RunWait(cmd, , "Hide", &pid)
        if (pg.Cancelled)
            return "cancel"
        if (status == 0 && !RmtAssetMissing(savePath))
            return "ok"
        return status == 28 ? "timeout" : "fail"
    } catch as err {
        pg.Report("✗ 下载异常: " err.Message, pg.percent)
        return "fail"
    } finally {
        SetTimer(sample, 0)
        if (HasMethod(pg, "SetDownloadAlternative"))
            pg.SetDownloadAlternative("")
        try FileDelete(headers)
    }

    SampleDownload() {
        if (pg.Cancelled) {
            if (pid)
                try ProcessClose(pid)
            return
        }
        if (!total)
            total := RmtDownloadContentLength(headers)
        received := 0
        try received := FileGetSize(savePath)
        if (HasMethod(pg, "SetDownloadAlternative"))
            pg.SetDownloadAlternative(RmtDownloadAlternative(url, received, total, A_TickCount - started), label)
    }
}

RmtAssetMissing(path) {
    attrs := FileExist(path)
    if (!attrs || InStr(attrs, "D"))
        return true
    try return FileGetSize(path) == 0
    return true
}

; 每个包下载一次，只提取本次需要补齐的条目。
DownloadRmtAssetBundle(url, files, pg) {
    static sequence := 0
    stage := A_WorkingDir "\.rmt-assets-" DllCall("GetCurrentProcessId") "-" A_TickCount "-" (++sequence)
    try {
        DirCreate(stage)
        payload := stage "\download.zip"
        result := DownloadResourceWithRetry(url, payload, 120, pg)
        if (result != "ok")
            return result
        return RmtExtractAssetBundle(payload, files, pg, stage)
    } finally {
        try DirDelete(stage, true)
    }
}

RmtExtractAssetBundle(zipPath, files, pg, stage := "") {
    static sequence := 0
    ownStage := stage == ""
    if (ownStage)
        stage := A_WorkingDir "\.rmt-assets-" DllCall("GetCurrentProcessId") "-" A_TickCount "-" (++sequence)
    try {
        DirCreate(stage)
        entries := ""
        for file in files
            entries .= ' "' file.entry '"'
        pg.Report("正在解压：" SubStr(zipPath, InStr(zipPath, "\", , -1) + 1), pg.percent)
        systemDir := A_PtrSize == 4 && A_Is64bitOS ? "\Sysnative" : "\System32"
        tar := A_WinDir systemDir "\tar.exe"
        if (RunWait('"' tar '" -xf "' zipPath '" -C "' stage '" --' entries, , "Hide") != 0)
            return pg.Cancelled ? "cancel" : "fail"

        for file in files {
            if (RmtAssetMissing(stage "\" file.entry))
                return "fail"
        }

        for file in files {
            if (pg.Cancelled)
                return "cancel"
            if (!RmtAssetMissing(file.fullPath))
                continue
            SplitPath(file.fullPath, , &dir)
            DirCreate(dir)
            FileMove(stage "\" file.entry, file.fullPath, true)
        }
        return "ok"
    } catch as error {
        pg.Report("资源修复失败：" error.Message, pg.percent)
        return "fail"
    } finally {
        if (ownStage)
            try DirDelete(stage, true)
    }
}

; =============================================================================
; VC++ 运行库：自动检测 + 自动安装（仅主进程）
;
; 严格「先检测，缺了才装」，启动时不提前加载任何 DLL：
;   1. VcRuntimeIsReady() 只检测能否被系统解析，没有前置副作用
;   2. 缺了才询问用户，同意后下载官方 vc_redist.{arch}.exe 静默安装
;   3. 装完重新检测，确认真的可用
;
; 不做 app-local 兜底：官方安装包自己知道该装什么，比手工维护 DLL 清单可靠，
; 也就不存在「清单漏一项、干净机器起不来」的风险。
; 用户拒绝 UAC 时不做静默提权，直接返回 false，相关功能不可用。
; Worker 不走这里：它没有界面层，由调用方拿到错误码后自行提示。
; =============================================================================

; 返回 true 表示运行库已可用。ask=false 时不做任何交互（用于定时/静默场景）。
VcRuntimeEnsureInstalled(ask := true) {
    if (VcRuntimeIsReady())
        return true

    if (ask) {
        msg := "检测到本机未正确安装 Microsoft Visual C++ 2015-2022 运行库（" VcRuntimeArchDir() "）。`n`n"
        missingText := VcRuntimeMissingText()
        if (missingText != "")
            msg .= "缺少文件：" missingText "`n`n"
        msg .= "抓图、搜图、文字识别等功能将无法使用。`n`n"
        msg .= "是否自动下载并安装？安装过程需要管理员权限。"
        if (!RmtDialog.Confirm(msg, "RMT 运行库修复"))
            return false
    }

    ; 下载官方安装包并静默安装（需要管理员授权，用户拒绝会被 catch 掉）
    if (VcRuntimeInstallRedist()) {
        if (ask)
            RmtDialog.Info("VC++ 运行库安装完成，相关功能可直接使用。", "RMT 运行库修复")
        return true
    }

    if (ask) {
        arch := VcRuntimeArchDir()
        tip := "自动安装未能完成，可能是网络不通或取消了管理员授权。`n`n"
        tip .= "可手动下载安装：`nhttps://aka.ms/vs/17/release/vc_redist." arch ".exe"
        RmtDialog.Info(tip, "RMT 运行库修复")
    }
    return false
}

; 下载官方 vc_redist 并静默安装。需要管理员：用户拒绝 UAC 会被 catch 掉。
; 由版本清单锁定 Patch 内容，备用站也必须通过同一哈希校验。
VcRuntimeRedistUrls() {
    arch := VcRuntimeArchDir()
    return [RmtAssetsBaseUrl("Patch") "VC_redist." arch ".exe"]
}

VcRuntimeInstallRedist() {
    arch := VcRuntimeArchDir()
    stage := A_WorkingDir "\.rmt-vcredist-" DllCall("GetCurrentProcessId") "-" A_TickCount
    try {
        DirCreate(stage)
        exePath := stage "\vc_redist." arch ".exe"

        offline := RuntimeOfflineAsset("VC_redist." arch ".exe")
        if (offline != "") {
            FileCopy(offline, exePath, true)
        } else if (RuntimeIsWin7()) {
            RuntimeOfflinePrompt("VC_redist." arch ".exe")
            return false
        } else {
            result := ""
            for url in VcRuntimeRedistUrls() {
                pg := RmtProgress("RMT 运行库修复", "正在下载官方 VC++ 运行库…", XamlWin.ActiveOwner(), "取消下载")
                pg.Show()
                try {
                    result := DownloadResourceWithRetry(url, exePath, 600, pg)
                } finally pg.Close()
                if (result = "ok" || result = "cancel")
                    break
            }
            if (result != "ok")
                return false
        }

        pg := RmtProgress("RMT 运行库修复", "正在安装官方 VC++ 运行库…", XamlWin.ActiveOwner())
        pg.Show()
        exitCode := -1
        try {
            ; /quiet 无界面；/norestart 不自动重启。
            ; 3010 = 装好了但要重启才完全生效，1638 = 已有更新版本，都算成功。
            exitCode := RunWait('*RunAs "' exePath '" /install /quiet /norestart', , "Hide")
        } finally pg.Close()

        if (exitCode != 0 && exitCode != 3010 && exitCode != 1638)
            return false

        OpenCvResetEnsureCache()
        return VcRuntimeIsReady()
    } catch {
        ; 用户在 UAC 上点了「否」，或安装器起不来
        return false
    } finally {
        try DirDelete(stage, true)
    }
}

; 启动后静默检查：齐全就什么都不做；缺了才问一次。
; 由 RMT.ahk 在界面就绪后延迟调用，避免开机即弹 UAC。
VcRuntimeStartupCheck() {
    if (VcRuntimeIsReady())
        return
    VcRuntimeEnsureInstalled(true)
}

; =============================================================================
; DirectX XInput 组件：自动检测 + 静默安装（仅主进程）
;
; 与 VC++ 运行库同一套流程，同样「先检测，缺了才装」：
;   1. DirectXIsReady() 只看系统目录文件，不加载、无副作用
;   2. 缺了才询问，同意后下载官方 DirectX End-User Runtime（Jun2010），
;      先 /Q /T 自解包，再 DXSETUP.exe /silent 静默安装
;   3. 装完重新检测，以文件是否就位为准（不依赖安装器退出码）
;
; 资源来源：RMTAssets 的 Patch 标签，文件名保持官方原名
;   directx_Jun2010_redist.exe
; 放 Patch 而不是版本标签，是因为这份运行库跨版本通用，传一次全版本可用。
;
; 为什么用官方自解包而不是自己分发 xinput1_3.dll：
;   自解包能力内建，不需要系统有 tar / 解压工具（Win7 没有 tar.exe）；
;   装的是官方组件，顺带补齐 d3dx9 等 DX9 老组件，也不引入来源不明的二进制。
;
; 拒绝安装不影响程序运行：JoyXInputEx() 会自动退回兼容层或 DirectInput，
; 只是扳机键 LT/RT 会被合并、Guide 键读不到。
; =============================================================================

DirectXAssetName() {
    return "directx_Jun2010_redist.exe"
}

DirectXAssetUrl() {
    return RmtAssetsBaseUrl("Patch") DirectXAssetName()
}

; 用户选过「不再提示」就不再自动询问（仍可通过「文件校验」手动触发）
DirectXPromptSuppressed() {
    try return String(CfgRead(SettingFile, SettingSection, "SkipDirectXPrompt", "0")) = "1"
    return false
}

DirectXSuppressPrompt() {
    try {
        CfgWrite("1", SettingFile, SettingSection, "SkipDirectXPrompt")
        CfgFlushAll()
    }
}

; 返回 true 表示 XInput 已可用。ask=false 时不做任何交互（定时/静默场景）。
DirectXEnsureInstalled(ask := true) {
    if (DirectXIsReady())
        return true

    if (ask) {
        msg := "检测到本机缺少 DirectX 的 XInput 组件（" DirectXMissingText() "）。`n`n"
        msg .= "它用于读取 Xbox 手柄。缺失时手柄仍可用，但会退回兼容模式：`n"
        msg .= "扳机键 LT / RT 会合并成同一根轴，Guide 键读不到。`n`n"
        msg .= "可用官方 DirectX 运行库静默补齐（约 95 MB，需要管理员权限）。`n"
        msg .= "不使用手柄的可选「不再提示」。"
        pick := RmtDialog.Choose(msg, "RMT 手柄组件修复", ["立即安装", "稍后再说", "不再提示"])
        if (pick == 3) {
            DirectXSuppressPrompt()
            return false
        }
        if (pick != 1)
            return false
    }

    if (DirectXInstallFromRedist()) {
        if (ask)
            RmtDialog.Info("DirectX 组件已安装，手柄功能可完整使用。", "RMT 手柄组件修复")
        return true
    }

    if (ask) {
        tip := "自动安装未能完成，可能是网络不通或取消了管理员授权。`n`n"
        tip .= "可手动安装官方 DirectX End-User Runtime（Jun2010）后重试。"
        RmtDialog.Info(tip, "RMT 手柄组件修复")
    }
    return false
}

; 下载官方自解包 → /Q /T 解包 → DXSETUP /silent 静默安装。
; 成功与否以「文件是否就位」为准，安装器退出码不作判据：
; DXSETUP 在部分系统上装完会返回非 0（例如提示需重启），但组件其实已经就位。
DirectXInstallFromRedist() {
    stage := A_WorkingDir "\.rmt-directx-" DllCall("GetCurrentProcessId") "-" A_TickCount
    try {
        DirCreate(stage)
        redist := stage "\" DirectXAssetName()
        extractDir := stage "\dx"
        DirCreate(extractDir)

        offline := RuntimeOfflineAsset(DirectXAssetName())
        if (offline != "") {
            FileCopy(offline, redist, true)
        } else {
            ; 约 95 MB，超时给足；DownloadResourceWithRetry 自带 3 次重试
            pg := RmtProgress("RMT 手柄组件修复", "正在下载官方 DirectX 运行库…", XamlWin.ActiveOwner(), "取消下载")
            pg.Show()
            result := ""
            try {
                result := DownloadResourceWithRetry(DirectXAssetUrl(), redist, 1800, pg)
            } finally pg.Close()
            if (result != "ok")
                return false
        }

        ; /Q 无界面，/T 指定解包目录。自解包内建，不依赖系统的 tar / 解压组件。
        ; 注意 /T 的路径不能带引号——带引号直接报 "Command line option syntax
        ; error"（实测 2026-11-13），所以路径含空格时转 8.3 短路径再传。
        extractShort := extractDir
        shortBuf := Buffer(65536, 0)
        shortLen := DllCall("GetShortPathNameW", "Str", extractDir, "Ptr", shortBuf, "UInt", 32767)
        if (shortLen > 0)
            extractShort := StrGet(shortBuf, shortLen, "UTF-16")

        pg := RmtProgress("RMT 手柄组件修复", "正在解压 DirectX 运行库…", XamlWin.ActiveOwner())
        pg.Show()
        try {
            RunWait('"' redist '" /Q /T:' extractShort, , "Hide")
        } finally pg.Close()

        setup := extractDir "\DXSETUP.exe"
        if (!FileExist(setup))
            return false

        pg := RmtProgress("RMT 手柄组件修复", "正在安装 DirectX 组件…", XamlWin.ActiveOwner())
        pg.Show()
        try {
            ; 需要管理员：用户拒绝 UAC 会抛异常，由外层 catch 接住
            RunWait('*RunAs "' setup '" /silent', , "Hide")
        } finally pg.Close()

        return DirectXIsReady()
    } catch {
        ; 用户点了「否」或安装器起不来
        return false
    } finally {
        try DirDelete(stage, true)
    }
}

; 启动后静默检查：就绪就什么都不做；缺了才问一次。
; 由 RMT.ahk 在界面就绪后延迟调用，排在 VC 运行库自检之后。
DirectXStartupCheck() {
    if (DirectXIsReady())
        return
    ; 「不再提示」只挡启动时的自动询问，不影响「文件校验」里的主动修复
    if (DirectXPromptSuppressed())
        return
    ; Win7 上在线版拿不到 95 MB 的官方包（系统级 TLS/根证书问题），启动时不去试；
    ; 离线运行环境包也不带 DirectX（手感和按键都属于可选增强），
    ; 真缺 XInput 时从「文件校验」里手动修，或自己放 Runtime\directx_Jun2010_redist.exe。
    if (RuntimeIsWin7() && RuntimeOfflineAsset(DirectXAssetName()) = "")
        return
    DirectXEnsureInstalled(true)
}


; =============================================================================
; 图标字体：Segoe MDL2 Assets
;
; 主界面图标全部走 PUA 码位（U+E700 起），字形来自两个系统字体：
;   Segoe Fluent Icons —— Windows 11
;   Segoe MDL2 Assets  —— Windows 10
; Win7 两者都没有，WPF 回退到默认字体后每个图标都画成方块（tofu）。
;
; 处理方式和 VC 运行库 / DirectX 同构：检测 → 缺了从 RMTAssets 的 Patch 取字体 → 注册。
; 不往系统字体目录写文件、不需要管理员：AddFontResourceExW 把字体加进本次会话的
; 系统字体表（session 级，Worker 等其它进程同样可见），再广播 WM_FONTCHANGE 让
; DirectWrite 重建字体集合。不能用 FR_PRIVATE —— DirectWrite 不枚举进程私有字体。
;
; 必须在 XAMLHost.Prewarm 之前完成：WPF 引擎是独立进程，会缓存首次字体解析结果。
; 缺失时先用缓存/离线副本，再尝试 Patch 下载；失败明确提示离线修复方法。
; =============================================================================

IconFontFileName() {
    return "segmdl2.ttf"
}

IconFontAssetUrl() {
    return RmtAssetsBaseUrl("Patch") IconFontFileName()
}

; 实际选中字体并检查常用图标，避免仅按文件名误判、漏掉自定义安装及会话字体。
IconFontInstalled() {
    return IconFontFamilyReady("Segoe Fluent Icons") || IconFontFamilyReady("Segoe MDL2 Assets")
}

IconFontFamilyReady(family) {
    dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
    if (!dc)
        return false
    font := 0, old := 0
    try {
        font := DllCall("gdi32\CreateFontW", "Int", -16, "Int", 0, "Int", 0, "Int", 0
            , "Int", 400, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1
            , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "Str", family, "Ptr")
        if (!font)
            return false
        old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        face := Buffer(128, 0)
        if (!DllCall("gdi32\GetTextFaceW", "Ptr", dc, "Int", 64, "Ptr", face, "Int")
            || StrGet(face) != family)
            return false
        glyphs := Chr(0xE74E) Chr(0xE8BB) Chr(0xE713)
        indices := Buffer(StrLen(glyphs) * 2, 0)
        if (DllCall("gdi32\GetGlyphIndicesW", "Ptr", dc, "Str", glyphs, "Int", StrLen(glyphs)
            , "Ptr", indices, "UInt", 1, "UInt") == 0xFFFFFFFF)
            return false
        loop StrLen(glyphs) {
            if (NumGet(indices, (A_Index - 1) * 2, "UShort") == 0xFFFF)
                return false
        }
        return true
    } finally {
        if (old)
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old)
        if (font)
            DllCall("gdi32\DeleteObject", "Ptr", font)
        DllCall("gdi32\DeleteDC", "Ptr", dc)
    }
}

; 下载缓存：和插件资源同层，随软件目录一起清理
IconFontCacheFile() {
    ; 此时 InitFilePath 尚未运行，不能依赖 ProjectRootDir。
    return A_ScriptDir "\Plugins\Fonts\" IconFontFileName()
}

; 把字体加入本次会话的系统字体表。返回 true 表示注册成功。
IconFontRegister(path) {
    if (!FileExist(path))
        return false
    added := DllCall("gdi32\AddFontResourceExW", "Str", path, "UInt", 0, "Ptr", 0, "Int")
    if (added <= 0)
        return false
    ; WM_FONTCHANGE 广播：DirectWrite 收到后才重建字体集合，否则新字体对它不可见
    res := 0
    DllCall("SendMessageTimeoutW", "Ptr", 0xFFFF, "UInt", 0x001D, "Ptr", 0, "Ptr", 0
        , "UInt", 0x0002, "UInt", 1000, "Ptr*", &res)
    return IconFontFamilyReady("Segoe MDL2 Assets")
}

; 在独立 WPF 引擎创建前修复，本次启动直接生效，不需要重启。
IconFontStartupCheck() {
    if (IconFontInstalled())
        return true
    cache := IconFontCacheFile()
    try {
        if (IconFontRegister(cache))
            return true
        SplitPath(cache, , &cacheDir)
        DirCreate(cacheDir)
        src := RuntimeOfflineAsset(IconFontFileName())
        if (src != "") {
            FileCopy(src, cache, true)
            if (IconFontRegister(cache))
                return true
        }
        ; Win7 也尝试在线修复；原生进度窗不依赖 XAML，允许取消。
        ; 下载到临时文件，验证注册成功后才替换缓存，避免复用半成品。
        pg := NativeProgress("RMT 图标字体", "正在补齐图标字体…")
        pg.Show()
        try {
            result := DownloadResourceWithRetry(IconFontAssetUrl(), cache ".download", 20, pg)
        } finally pg.Close()
        if (result == "ok") {
            FileMove(cache ".download", cache, true)
            if (IconFontRegister(cache))
                return true
        }
    } catch {
        ; 目录不可写、坏字体或下载异常统一给出可操作的离线修复方式。
    } finally {
        try FileDelete(cache ".download")
    }
    MsgBox("未能补齐 Segoe MDL2 Assets 图标字体，按钮图标可能显示为方框。`n`n"
        . "请下载以下字体，放入软件目录 Runtime 文件夹后重新运行 RMT：`n"
        . IconFontAssetUrl() "`n备用下载地址：`n" RmtDownloadDirectUrl(IconFontAssetUrl())
        . "`n`n目标位置：`n" A_ScriptDir "\Runtime\" IconFontFileName()
        , "RMT 图标字体", "Icon!")
    return false
}

; 后台资源下载不创建进度窗口。
class RmtSilentDownloadProgress {
    percent := 0
    Cancelled := false

    SetDownloadAlternative(*) {
    }

    Report(msg, pct) {
    }
}
