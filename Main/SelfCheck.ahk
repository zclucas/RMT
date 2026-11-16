#Requires AutoHotkey v2.0

RmtAssetsReleaseTag() {
    ; 与 CI 的资源标签一致，带完整版本号：预览版与正式版资源互不覆盖。
    arch := A_PtrSize == 8 ? "x64" : "x86"
    return "v" RMT_VERSION "_" arch
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
; 资源都在 RMTAssets 的 Common 标签，和 directx_Jun2010_redist、segmdl2.ttf 同处。
; 非 Win7 逐项下载；Win7 连不上网，改用 Common 里的离线运行环境包 Runtime_x64/x86.zip——
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
; Msxml2.XMLHTTP 走 WinINET，Win7 默认只启用 TLS 1.0；GitHub 与 gh-proxy 都要求
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
; 这里按 4.6 判定：低于它就提示装 4.8——Win7 上 4.8 是最后一个版本，
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
    return NetFxRelease() >= 393295
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
        ? ("当前是 " NetFxVersionName(rel) "（Release " rel "），低于 RMT 要求的 4.6")
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

; 离线运行环境压缩包，放在 RMTAssets 的 Common 里，按系统位数分两个：
; 包里是 KB4474419 + KB4019990 + .NET 4.8 + VC + segmdl2.ttf，以及一键安装脚本
; InstallRuntime.bat（脚本和安装包放在一起，解压即用，和 RMT 本体无关）。
RuntimeOfflineBundleName() {
    return "Runtime_" (RuntimeOs64Bit() ? "x64" : "x86") ".zip"
}

RuntimeOfflineBundleUrl() {
    return RmtAssetsBaseUrl("Common") RuntimeOfflineBundleName()
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
    msg := "当前是 Windows 7，RMT 无法自动联网安装环境组件。`n`n"
        . "原因：Windows 7 默认未启用 TLS 1.2，根证书库也缺少 GitHub 与 CDN 使用的根证书，"
        . "系统自带的下载组件又不支持忽略证书错误。`n`n"
        . "请在任意一台能上网的电脑下载离线运行环境包（" RuntimeOfflineBundleName() "）：`n"
        . RuntimeOfflineBundleUrl() "`n`n"
        . "拷到本机解压，双击解压出来的 InstallRuntime.bat，它会按依赖顺序装齐全部组件，"
        . "中途需要重启就重启后把脚本再跑一次。装完再启动 RMT 即可。"
    if (name != "")
        msg .= "`n`n当前还缺文件：" name
    MsgBox(msg, "RMT 运行环境", "Icon!")
}

; 返回本地安装包路径；失败返回 ""。
; 先看 <RMT目录>\Runtime\ 的离线副本（用户可手工放置，绕过网络问题），
; 再复用 %TEMP%\RMT-Setup 里上次下完的文件，最后才联网下载。
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

    dir := A_Temp "\RMT-Setup"
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
        result := DownloadAsync(RmtAssetsBaseUrl("Common") name, path, 3600, pg)
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
; DownloadAsync 只用到 percent / Cancelled / Report 三个成员，接口与 RmtProgress 对齐。
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

    criticalFiles := [
        {path: "Plugins\RMT\RMT.dll", entry: "RMT.dll", bundle: "RMT.zip"},
        {path: "Plugins\RMT\RMT.ExcelHelper.exe", entry: "RMT.ExcelHelper.exe", bundle: "RMT.zip"},
        {path: "Plugins\IbInputSimulator.dll", entry: "IbInputSimulator.dll", bundle: "Input.zip"},
        {path: "Audio\Start.wav", entry: "Start.wav", bundle: "Audio.zip"},
        {path: "Audio\End.wav", entry: "End.wav", bundle: "Audio.zip"},
        {path: "Plugins\ViGEm\ViGEmWrapper.dll", entry: "ViGEmWrapper.dll", bundle: "ViGEm.zip"},
        {path: "Joy\ViGEmBus.exe", entry: "ViGEmBus.exe", bundle: "ViGEm.zip"},
        {path: "Joy\Xbox按键映射.png", entry: "Xbox.png", bundle: "ViGEm.zip"},
        {path: "Plugins\AHK-XAML\lib\dep\ahk-xaml.dll", entry: "ahk-xaml.dll", bundle: "Xaml.zip"},
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
        {path: "index.html", entry: "index.html", bundle: "RMT.zip"},
    ]
    for name, language in OfficialLanguages() {
        if (language.HasOwnProp("entry"))
            criticalFiles.Push({path: "Lang\" name ".txt", entry: language.entry, bundle: "Lang.zip"})
        criticalFiles.Push({path: "Lang\Flags\" language.flag ".png", entry: "Flags/" language.flag ".png", bundle: "Lang.zip"})
    }
    optionalFiles := [
        {path: "Plugins\MouseControl.dll", entry: "MouseControl.dll", bundle: "Input.zip"},
        {path: "MinTool\PlayAudio.vbs", entry: "PlayAudio.vbs", bundle: "Audio.zip"},
        {path: "Plugins\AhiDriver\installer\使用说明.txt", entry: "InstallReadme.txt", bundle: "AhiDriver.zip"},
    ]

    icoFileList := ["Wait.png", "BGKey.png", "IcoRunning.ico", "Joy.png", "DeltaMove.png", "KeyListen.png", "JoyListen.png", "SearchCombo.png", "Excel.png", "Time.png", "WaitConfirm.png", "RunPro.png",
        "Arr.png", "Condition.png", "Control.png", "FlowJump.png", "Extract.png", "False.png",
        "HttpRequest.png", "FileIO.png", "IcoPause.ico", "If.png", "IfPro.png",
        "Input.png", "Key.png", "Loop.png",
        "LoopBody.png", "LoopCount.png", "Mouse.png", "Move.png", "MovePro.png",
        "Operation.png", "Output.png", "Prompt.png", "Run.png", "Search.png",
        "SearchPro.png", "SearchAll.png", "MacroAction.png", "TextOps.png", "True.png",
        "Var.png", "WeiXin.png", "WindowManage.png", "WindowAdjustGear32.png",
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
    tipMsg := "检测到 " totalMissing " 个资源文件缺失`n" detailStr "`n`n" fileListStr "`n版本：" tag "`n点击【是】从 GitHub 自动下载`n点击【否】跳过（部分功能可能不可用）"

    result := RmtDialog.Confirm(tipMsg, "RMT 资源自检")
    if (!result) {
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

DownloadAsync(url, savePath, timeoutSec, pg) {
    maxRetry := 3
    ; Win7 走网络基本必然失败（TLS 1.2 默认未启用 + 缺 GitHub/CDN 的根证书），
    ; 按原来的 3 轮长超时会把界面挂住十几分钟。这里压到 1 轮、最长 120 秒，
    ; 让用户尽快看到「下载失败」而不是以为程序死了。
    if (RuntimeIsWin7()) {
        maxRetry := 1
        if (timeoutSec > 120)
            timeoutSec := 120
    }
    Loop maxRetry {
        if (pg.Cancelled)
            return "cancel"

        if (A_Index > 1)
            pg.Report(Format("重试 ({}/{})...", A_Index - 1, maxRetry - 1), pg.percent)

        result := DownloadOnce(url, savePath, timeoutSec, pg)
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

DownloadOnce(url, savePath, timeoutSec, pg) {
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
        result := DownloadAsync(url, payload, 120, pg)
        if (result != "ok")
            return result

        entries := ""
        for file in files
            entries .= ' "' file.entry '"'
        pg.Report("正在解压：" SubStr(url, InStr(url, "/", , -1) + 1), pg.percent)
        systemDir := A_PtrSize == 4 && A_Is64bitOS ? "\Sysnative" : "\System32"
        tar := A_WinDir systemDir "\tar.exe"
        if (RunWait('"' tar '" -xf "' payload '" -C "' stage '" --' entries, , "Hide") != 0)
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
; 优先从 RMTAssets 的 Common 取（国内直连 aka.ms 常常超时），失败再回落官方短链。
VcRuntimeRedistUrls() {
    arch := VcRuntimeArchDir()
    return [RmtAssetsBaseUrl("Common") "VC_redist." arch ".exe"
        , "https://aka.ms/vs/17/release/vc_redist." arch ".exe"]
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
                    result := DownloadAsync(url, exePath, 600, pg)
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
; 资源来源：RMTAssets 的 Common 标签，文件名保持官方原名
;   directx_Jun2010_redist.exe
; 放 Common 而不是版本标签，是因为这份运行库跨版本通用，传一次全版本可用。
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
    return RmtAssetsBaseUrl("Common") DirectXAssetName()
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
            ; 约 95 MB，超时给足；DownloadAsync 自带 3 次重试
            pg := RmtProgress("RMT 手柄组件修复", "正在下载官方 DirectX 运行库…", XamlWin.ActiveOwner(), "取消下载")
            pg.Show()
            result := ""
            try {
                result := DownloadAsync(DirectXAssetUrl(), redist, 1800, pg)
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
; 处理方式和 VC 运行库 / DirectX 同构：检测 → 缺了从 RMTAssets 的 Common 取字体 → 注册。
; 不往系统字体目录写文件、不需要管理员：AddFontResourceExW 把字体加进本次会话的
; 系统字体表（session 级，Worker 等其它进程同样可见），再广播 WM_FONTCHANGE 让
; DirectWrite 重建字体集合。不能用 FR_PRIVATE —— DirectWrite 不枚举进程私有字体。
;
; 图标属非必要资源：缺了只是显示成方块，不阻断启动，也不弹框询问。
; =============================================================================

IconFontFileName() {
    return "segmdl2.ttf"
}

IconFontAssetUrl() {
    return RmtAssetsBaseUrl("Common") IconFontFileName()
}

; 系统已装（Win10/11 自带，或用户手工装过）。以字体目录里的文件为准，
; 和 XAML_Host 的 _HasMdl2() 同一判据。
IconFontInstalled() {
    return FileExist(A_WinDir "\Fonts\" IconFontFileName()) ? true : false
}

; 下载缓存：和插件资源同层，随软件目录一起清理
IconFontCacheFile() {
    global ProjectRootDir
    return ProjectRootDir "\Plugins\Fonts\" IconFontFileName()
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
    return true
}

; 建主窗之前调用：只有本地已有缓存时才注册，一次 DllCall，不联网。
; 首次运行没有缓存，交给 IconFontStartupCheck 在界面就绪后补齐。
IconFontRegisterCached() {
    if (IconFontInstalled())
        return true
    cache := IconFontCacheFile()
    if (!FileExist(cache))
        return false
    return IconFontRegister(cache)
}

; 界面就绪后异步检查：系统没有、缓存也没有 → 后台下载并注册，装完提示一次。
; 主窗此时已经建好，WPF 不会回头重新解析 FontFamily，所以提示「重启后生效」。
IconFontStartupCheck() {
    if (IconFontInstalled())
        return
    cache := IconFontCacheFile()
    if (!FileExist(cache)) {
        SplitPath(cache, , &cacheDir)
        if (cacheDir != "")
            try DirCreate(cacheDir)
        ; Win7 连不上网：离线运行环境包里顺带带了这份字体（Runtime\segmdl2.ttf），有就用
        if (RuntimeIsWin7()) {
            src := RuntimeOfflineAsset(IconFontFileName())
            if (src = "")
                return
            try FileCopy(src, cache, true)
        } else {
            ; 约 283 KB，超时给 20 秒；DownloadAsync 自带 3 次重试
            if (DownloadAsync(IconFontAssetUrl(), cache, 20, IconFontSilentProgress()) != "ok")
                return
        }
    }
    if (IconFontRegister(cache))
        try Toast.Info("图标字体已安装，重启 RMT 后主界面图标生效", 5000)
}

; DownloadAsync 只用 Cancelled / percent / Report 三样，这里给个静默占位。
class IconFontSilentProgress {
    percent := 0
    Cancelled := false

    Report(msg, pct) {
    }
}
