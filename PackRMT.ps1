# RMT 自动打包脚本
# 使用 Ahk2Exe.exe 编译 Work.ahk 为 Work.exe
# 此脚本需要编码格式为UTF-8 BOM 或者 UTF-16才能正常运行
# 若运行直接闪退，请在powershell执行：Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
param([switch]$NoPause)

try { $Host.UI.RawUI.WindowTitle = "RMT 打包工具" } catch { }
$ErrorActionPreference = "Stop"

# ============================================================
# 配置路径
# ============================================================

# Ahk2Exe 编译器路径
$Ahk2ExePaths = @(
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
)

# 64位 Base 编译器路径
$Base64Paths = @(
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
)

# 32位 Base 编译器路径
$Base32Paths = @(
    "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
)

# ============================================================
# 通用函数
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

function Write-Step {
    param([int]$Num, [string]$Message, [string]$Color = "Cyan")
    Write-Host "`n[$Num] $Message" -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

# 读取单个按键；宿主不支持 ReadKey 时返回 $null，由调用方回退到 Read-Host
function Read-SingleKey {
    try {
        if ([Console]::IsInputRedirected) { return $null }
        return $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    }
    catch { return $null }
}

function Wait-KeyPress {
    param([string]$Message = "按任意键退出...")
    Write-Host "`n$Message" -ForegroundColor Yellow
    if ($null -ne (Read-SingleKey)) { return }
    try { $null = Read-Host } catch { }
}

function Ask-Choice {
    param([string]$Title, [string[]]$Options, [int]$Default = 0)
    Write-Host "`n$Title" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Length; $i++) {
        $flag = if ($i -eq $Default) { "[*]" } else { "[ ]" }
        Write-Host "  $flag $($i+1). $($Options[$i])" -ForegroundColor White
    }
    Write-Host ""
    while ($true) {
        $key = Read-SingleKey
        if ($null -eq $key) {
            $input = Read-Host "请输入序号 (1-$($Options.Length))"
            if ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $Options.Length) {
                return [int]$input
            }
            continue
        }
        if ([int]$key -ge 49 -and [int]$key -le 48 + $Options.Length) {
            return [int]$key - 48
        }
    }
}

function Show-ErrorDetail {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "  打包中断：发生错误" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "消息: $($ErrorRecord.Exception.Message)" -ForegroundColor Red
    Write-Host "类型: $($ErrorRecord.Exception.GetType().FullName)" -ForegroundColor Gray
    Write-Host "分类: $($ErrorRecord.CategoryInfo.Category)" -ForegroundColor Gray

    if ($ErrorRecord.InvocationInfo) {
        Write-Host "位置: 第 $($ErrorRecord.InvocationInfo.ScriptLineNumber) 行" -ForegroundColor Gray
        if ($ErrorRecord.InvocationInfo.Line) {
            Write-Host "代码: $($ErrorRecord.InvocationInfo.Line.Trim())" -ForegroundColor Gray
        }
    }

    $inner = $ErrorRecord.Exception.InnerException
    while ($inner) {
        Write-Host "内部异常: $($inner.Message)" -ForegroundColor DarkYellow
        $inner = $inner.InnerException
    }

    if ($ErrorRecord.ScriptStackTrace) {
        Write-Host "`n调用堆栈:" -ForegroundColor Gray
        Write-Host $ErrorRecord.ScriptStackTrace -ForegroundColor DarkGray
    }
}

# 资源管理器右键运行时不会附带 -ExecutionPolicy，用的是持久化策略
function Get-PersistedPolicy {
    try {
        $list = Get-ExecutionPolicy -List
        foreach ($scope in @("MachinePolicy", "UserPolicy", "CurrentUser", "LocalMachine")) {
            $policy = ($list | Where-Object { $_.Scope -eq $scope }).ExecutionPolicy
            if ($policy -and $policy -ne "Undefined") { return $policy }
        }
        return "Restricted"
    }
    catch { return $null }
}

# ============================================================
# 工具函数
# ============================================================

function Find-Exe {
    param([string]$Name, [string[]]$Paths)
    foreach ($path in $Paths) {
        if (Test-Path $path) { Write-Log "  [OK] 找到 $Name" "Green"; return $path }
    }
    Write-Log "  [ERROR] 未找到 $Name" "Red"
    return $null
}

function Remove-OldFiles {
    param([string]$Dir, [string]$Filter)
    if (-not (Test-Path $Dir)) { Write-Log "  目录不存在: $Dir" "Gray"; return }
    $files = Get-ChildItem $Dir -Filter $Filter -ErrorAction SilentlyContinue
    if (-not $files) { Write-Log "  无旧文件" "Gray"; return }
    Write-Log "  找到 $($files.Count) 个旧文件" "Gray"
    $files | ForEach-Object {
        try { Remove-Item $_.FullName -Force -ErrorAction Stop; Write-Log "    已删除: $($_.Name)" "Yellow" }
        catch { Write-Log "    删除失败: $($_.Name)" "Red" }
    }
}

function Copy-IfExist {
    param([string]$Source, [string]$DestDir)
    if (Test-Path $Source) {
        $dest = Join-Path $DestDir (Split-Path $Source -Leaf)
        Copy-Item $Source -Destination $dest -Force -ErrorAction SilentlyContinue
        if ($?) { Write-Log "  已复制: $(Split-Path $Source -Leaf)" "Gray" }
    }
}

function Get-Version {
    $rmtAhk = Join-Path $PSScriptRoot "RMT.ahk"
    if (-not (Test-Path $rmtAhk)) {
        Write-Log "  [ERROR] 未找到 RMT.ahk，无法获取版本号" "Red"
        return $null
    }
    $content = Get-Content $rmtAhk -Raw
    # 匹配 global RMT_VERSION := "1.2F7" 格式
    if ($content -match 'global RMT_VERSION\s*:=\s*"([^"]+)"') {
        $version = $matches[1]
        Write-Log "  版本号: v$version" "Gray"
        return $version
    }
    Write-Log "  [ERROR] 无法从 RMT.ahk 解析版本号" "Red"
    return $null
}

# ============================================================
# 进程检查函数
# ============================================================

function Stop-RunningRMT {
    Write-Log "检查 RMT.ahk 是否正在运行..." "Gray"
    $rmtProcess = Get-CimInstance Win32_Process -Filter "Name LIKE '%AutoHotkey%'" | Where-Object { $_.CommandLine -like "*RMT.ahk*" }
    if ($rmtProcess) {
        Write-Log "RMT.ahk 正在运行，正在关闭..." "Yellow"
        $rmtProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Start-Sleep -Seconds 1
        Write-Log "RMT.ahk 已关闭" "Green"
    } else {
        Write-Log "RMT.ahk 未运行" "Green"
    }
}

# ============================================================
# 编译函数
# ============================================================

function Compile {
    param(
        [string]$AhkFile,
        [string]$BaseExe,
        [string]$OutputExe,
        [string]$IconPath,
        [string]$Name = "编译"
    )

    # /silent：禁用所有消息框（编译失败不再弹窗），错误写入 stderr、成功信息写入 stdout。
    # 日志重定向到文件后统一打印/清理。详见官方文档 Scripts.htm#ahk2exe。
    $logDir = Join-Path $PSScriptRoot "Log"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $stdoutLog = Join-Path $logDir "Ahk2Exe_${Name}_${stamp}.out.log"
    $stderrLog = Join-Path $logDir "Ahk2Exe_${Name}_${stamp}.err.log"

    $arguments = @(
        "/in", "`"$AhkFile`"",
        "/icon", "`"$IconPath`"",
        "/base", "`"$BaseExe`"",
        "/out", "`"$OutputExe`"",
        "/silent"
    )

    Write-Log "  执行: Ahk2Exe /in ... /icon ... /base ... /out ... /silent" "Gray"
    $process = Start-Process -FilePath $script:Ahk2exe `
        -ArgumentList $arguments `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog

    # 退出码：0 表示成功，非 0 表示错误类型（见 Ahk2Exe 的 ErrorCodes.md）
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        Write-Log "  [ERROR] $Name 编译失败，退出码: $($process.ExitCode)" "Red"
        Show-CompileOutput -StderrLog $stderrLog -StdoutLog $stdoutLog
        return $false
    }

    Start-Sleep -Milliseconds 500

    # 个别环境下重定向后取不到退出码，此时以输出文件是否生成为准
    if (-not (Test-Path $OutputExe)) {
        Write-Log "  [ERROR] $Name 编译失败（未生成输出文件）" "Red"
        Show-CompileOutput -StderrLog $stderrLog -StdoutLog $stdoutLog
        return $false
    }

    # 编译成功，清理临时日志
    Remove-Item $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue

    $size = [math]::Round((Get-Item $OutputExe).Length / 1MB, 2)
    Write-Log "  [OK] $Name 成功 (${size} MB)" "Green"
    return $true
}

# 打印 Ahk2Exe 编译输出（优先 stderr，为空时用 stdout 兜底）
function Show-CompileOutput {
    param(
        [string]$StderrLog,
        [string]$StdoutLog
    )

    $lines = @()
    if (Test-Path $StderrLog) { $lines += Get-Content $StderrLog }
    if (-not $lines -and (Test-Path $StdoutLog)) { $lines += Get-Content $StdoutLog }
    if (-not $lines) { return }

    Write-Host "  -------- Ahk2Exe 输出 --------" -ForegroundColor Yellow
    $lines | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host "  ------------------------------" -ForegroundColor Yellow
    Write-Log "  编译日志已保留: $StderrLog" "Gray"
}

function Pack-HelpDoc {
    $WebDir = Join-Path $PSScriptRoot "Web/JS"

    if (-not (Test-Path (Join-Path $WebDir "SingleHtml.js"))) {
        Write-Log "未找到 SingleHtml.js，跳过" "Yellow"
        return $true
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Log "未找到 Node.js，跳过" "Yellow"
        return $true
    }

    Write-Log "Node.js $(node -v) 打包中..." "Gray"
    Push-Location $WebDir
    try {
        $proc = Start-Process -FilePath "node" -ArgumentList "SingleHtml.js" -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Log "  [ERROR] SingleHtml.js 退出码: $($proc.ExitCode)" "Red"
        }
    }
    finally { Pop-Location }

    $indexHtml = Join-Path $PSScriptRoot "index.html"
    if (-not (Test-Path $indexHtml)) {
        Write-Log "帮助文档打包失败：未生成 index.html" "Red"
        return $false
    }

    $size = [math]::Round((Get-Item $indexHtml).Length / 1MB, 2)
    Write-Log "[OK] 帮助文档打包成功 (${size} MB)：index.html" "Green"
    return $true
}

# ============================================================
# 发行版函数
# ============================================================

function New-Release {
    param([string]$Type) # "x64" or "x86" or "both"

    Write-Section "创建发行版"
    Write-Log "模式: $Type" "Cyan"

    # 获取版本号
    $version = Get-Version
    if (-not $version) {
        Write-Log "无法获取版本号，取消发行版创建" "Red"
        return $false
    }

    $RmtAhk = Join-Path $PSScriptRoot "RMT.ahk"
    $IconPath = Join-Path $PSScriptRoot "Images\Soft\rabit.ico"

    if ($Type -eq "x64" -or $Type -eq "both") {
        Write-Step 1 "生成 ReleaseX64"
        $releaseDir = Join-Path $PSScriptRoot "ReleaseX64"
        $releaseThread = Join-Path $releaseDir "Thread"

        # 创建目录
        New-Item -ItemType Directory -Path $releaseThread -Force | Out-Null

        # 复制 Lang 目录
        Write-Log "复制 Lang 目录..." "Gray"
        if (Test-Path "$releaseDir\Lang") {
            Remove-Item "$releaseDir\Lang" -Recurse -Force
        }
        Copy-Item -Path "$PSScriptRoot\Lang" -Destination "$releaseDir\Lang" -Force -Recurse -ErrorAction SilentlyContinue

        # 复制 Images 目录
        Write-Log "复制 Images 目录..." "Gray"
        if (Test-Path "$releaseDir\Images") {
            Remove-Item "$releaseDir\Images" -Recurse -Force
        }
        Copy-Item -Path "$PSScriptRoot\Images" -Destination "$releaseDir\Images" -Force -Recurse -ErrorAction SilentlyContinue

        # 复制帮助文档
        Copy-HelpDocs -ReleaseDir $releaseDir

        # 删除旧 Work.exe
        Remove-OldFiles -Dir $releaseThread -Filter "Work.exe"

        # 编译 Work.exe
        if (-not (Compile -AhkFile $script:WorkAhk -BaseExe $script:Base64Exe -OutputExe "$releaseThread\Work.exe" -IconPath $IconPath -Name "Work.exe")) {
            return $false
        }

        # 编译主程序 RMTv{version}.exe
        if (-not (Compile -AhkFile $RmtAhk -BaseExe $script:Base64Exe -OutputExe "$releaseDir\RMTv$version.exe" -IconPath $IconPath -Name "RMTv$version.exe")) {
            return $false
        }

        # 复制 OpenCV DLL (x64)
        Write-Log "复制 OpenCV DLL (x64)..." "Gray"
        Copy-OpenCV -ReleaseDir $releaseDir -Arch "x64"

        # 复制文字识别插件 RapidOcr (x64)
        Write-Log "复制 RapidOcr 插件 (x64)..." "Gray"
        Copy-RapidOcr -ReleaseDir $releaseDir -Arch "x64"

        # 复制 AHK-XAML DLL
        Write-Log "复制 AHK-XAML DLL..." "Gray"
        Copy-XamlDlls -ReleaseDir $releaseDir

        # 复制 AhiDriver（DLL + Interception 安装包）
        Write-Log "复制 AhiDriver (x64)..." "Gray"
        Copy-AhiDriver -ReleaseDir $releaseDir -Arch "x64"

        # 复制罗技输入相关 DLL（按键 + 鼠标移动）
        Write-Log "复制输入插件 DLL..." "Gray"
        Copy-InputDlls -ReleaseDir $releaseDir

        # 复制语音触发插件 Voice (x64)
        Write-Log "复制 Voice 插件 (x64)..." "Gray"
        Copy-Voice -ReleaseDir $releaseDir -Arch "x64"
    }

    if ($Type -eq "x86" -or $Type -eq "both") {
        Write-Step 2 "生成 ReleaseX86"
        $releaseDir = Join-Path $PSScriptRoot "ReleaseX86"
        $releaseThread = Join-Path $releaseDir "Thread"

        # 创建目录
        New-Item -ItemType Directory -Path $releaseThread -Force | Out-Null

        # 复制 Lang 目录
        Write-Log "复制 Lang 目录..." "Gray"
        if (Test-Path "$releaseDir\Lang") {
            Remove-Item "$releaseDir\Lang" -Recurse -Force
        }
        Copy-Item -Path "$PSScriptRoot\Lang" -Destination "$releaseDir\Lang" -Force -Recurse -ErrorAction SilentlyContinue

        # 复制 Images 目录
        Write-Log "复制 Images 目录..." "Gray"
        if (Test-Path "$releaseDir\Images") {
            Remove-Item "$releaseDir\Images" -Recurse -Force
        }
        Copy-Item -Path "$PSScriptRoot\Images" -Destination "$releaseDir\Images" -Force -Recurse -ErrorAction SilentlyContinue

        # 复制帮助文档
        Copy-HelpDocs -ReleaseDir $releaseDir

        # 删除旧 Work.exe
        Remove-OldFiles -Dir $releaseThread -Filter "Work.exe"

        # 编译 Work.exe (32位)
        if (-not (Compile -AhkFile $script:WorkAhk -BaseExe $script:Base32Exe -OutputExe "$releaseThread\Work.exe" -IconPath $IconPath -Name "Work.exe")) {
            return $false
        }

        # 编译主程序 RMTv{version}.exe
        if (-not (Compile -AhkFile $RmtAhk -BaseExe $script:Base32Exe -OutputExe "$releaseDir\RMTv$version.exe" -IconPath $IconPath -Name "RMTv$version.exe")) {
            return $false
        }

        # 复制 OpenCV DLL (x86)
        Write-Log "复制 OpenCV DLL (x86)..." "Gray"
        Copy-OpenCV -ReleaseDir $releaseDir -Arch "x86"

        # 复制文字识别插件 RapidOcr (x86)
        Write-Log "复制 RapidOcr 插件 (x86)..." "Gray"
        Copy-RapidOcr -ReleaseDir $releaseDir -Arch "x86"

        # 复制 AHK-XAML DLL
        Write-Log "复制 AHK-XAML DLL..." "Gray"
        Copy-XamlDlls -ReleaseDir $releaseDir

        # 复制 AhiDriver（DLL + Interception 安装包）
        Write-Log "复制 AhiDriver (x86)..." "Gray"
        Copy-AhiDriver -ReleaseDir $releaseDir -Arch "x86"

        # 复制罗技输入相关 DLL（按键 + 鼠标移动）
        Write-Log "复制输入插件 DLL..." "Gray"
        Copy-InputDlls -ReleaseDir $releaseDir

        # 复制语音触发插件 Voice (x86)
        Write-Log "复制 Voice 插件 (x86)..." "Gray"
        Copy-Voice -ReleaseDir $releaseDir -Arch "x86"
    }

    Write-Section "创建发行包到桌面"
    $desktop = [Environment]::GetFolderPath("Desktop")
    $rmtReleaseDir = Join-Path $desktop "RMTRelease"

    # 删除旧的 RMTRelease 目录
    if (Test-Path $rmtReleaseDir) {
        Write-Log "删除旧 RMTRelease 目录..." "Yellow"
        Remove-Item $rmtReleaseDir -Recurse -Force
    }

    $versionDir = Join-Path $rmtReleaseDir "RMTv$version"
    New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
    Write-Log "创建 $versionDir" "Gray"

    if ($Type -eq "x64" -or $Type -eq "both") {
        $destX64 = Join-Path $versionDir "RMTv${version}_x64"
        New-Item -ItemType Directory -Path $destX64 -Force | Out-Null
        Write-Log "复制 ReleaseX64 to $destX64 ..." "Gray"
        Copy-Item -Path "$PSScriptRoot\ReleaseX64\*" -Destination $destX64 -Recurse -Force
    }

    if ($Type -eq "x86" -or $Type -eq "both") {
        $destX86 = Join-Path $versionDir "RMTv${version}_x86"
        New-Item -ItemType Directory -Path $destX86 -Force | Out-Null
        Write-Log "复制 ReleaseX86 to $destX86 ..." "Gray"
        Copy-Item -Path "$PSScriptRoot\ReleaseX86\*" -Destination $destX86 -Recurse -Force
    }

    # 生成资源清单目录（对应 Main\SelfCheck.ahk 的文件校验清单）
    Write-Section "生成资源清单 (RMTAssets)"
    if ($Type -eq "x64" -or $Type -eq "both") {
        New-RMTAssets -Arch "x64" -ReleaseDir $rmtReleaseDir
    }
    if ($Type -eq "x86" -or $Type -eq "both") {
        New-RMTAssets -Arch "x86" -ReleaseDir $rmtReleaseDir
    }

    Write-Section "压缩发行包"
    if ($Type -eq "x64" -or $Type -eq "both") {
        Compress-ReleaseZip -SourceDir (Join-Path $versionDir "RMTv${version}_x64") -ZipPath (Join-Path $rmtReleaseDir "RMTv${version}_x64.zip")
    }
    if ($Type -eq "x86" -or $Type -eq "both") {
        Compress-ReleaseZip -SourceDir (Join-Path $versionDir "RMTv${version}_x86") -ZipPath (Join-Path $rmtReleaseDir "RMTv${version}_x86.zip")
    }

    # 删除 ReleaseX64/ReleaseX86 下的 RMT*.exe
    Write-Section "清理临时文件"
    if ($Type -eq "x64" -or $Type -eq "both") {
        Write-Log "删除 ReleaseX64 下的 RMT*.exe..." "Gray"
        Get-ChildItem (Join-Path $PSScriptRoot "ReleaseX64") -Filter "RMT*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Log "  已删除: $($_.Name)" "Yellow"
        }
    }
    if ($Type -eq "x86" -or $Type -eq "both") {
        Write-Log "删除 ReleaseX86 下的 RMT*.exe..." "Gray"
        Get-ChildItem (Join-Path $PSScriptRoot "ReleaseX86") -Filter "RMT*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Log "  已删除: $($_.Name)" "Yellow"
        }
    }

    Write-Section "发行版创建完成"
    Write-Log "to $versionDir\RMTv${version}_x64" "White"
    if ($Type -eq "both") {
        Write-Log "to $versionDir\RMTv${version}_x86" "White"
    }
    Write-Log "to $rmtReleaseDir\RMTv${version}_x64.zip" "White"
    if ($Type -eq "both") {
        Write-Log "to $rmtReleaseDir\RMTv${version}_x86.zip" "White"
    }
    Write-Log "to $rmtReleaseDir\RMTAssets_x64" "White"
    if ($Type -eq "both") {
        Write-Log "to $rmtReleaseDir\RMTAssets_x86" "White"
    }
    return $true
}

function Copy-HelpDocs {
    param([string]$ReleaseDir)

    $src = Join-Path $PSScriptRoot "index.html"
    if (Test-Path $src) {
        Copy-Item $src -Destination (Join-Path $ReleaseDir "index.html") -Force
        Write-Log "  已复制: index.html" "Gray"
    } else {
        Write-Log "  [WARN] 未找到帮助文档: index.html" "Yellow"
    }
}

function Copy-OpenCV {
    param([string]$ReleaseDir, [string]$Arch)

    $srcDir = Join-Path $PSScriptRoot "Plugins\OpenCV\$Arch"
    $dstDir = Join-Path $ReleaseDir "Plugins\OpenCV\$Arch"

    if (-not (Test-Path $srcDir)) {
        Write-Log "  [ERROR] OpenCV 源目录不存在: $srcDir" "Yellow"
        return
    }

    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null

    Get-ChildItem $srcDir -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $dstDir -Force
        Write-Log "  已复制: OpenCV/$Arch/$($_.Name)" "Gray"
    }
}

function Copy-XamlDlls {
    param([string]$ReleaseDir)

    $srcDepDir = Join-Path $PSScriptRoot "Plugins\AHK-XAML\lib\dep"
    $dstDepDir = Join-Path $ReleaseDir "Plugins\AHK-XAML\lib\dep"
    $dlls = @("ahk-xaml.dll")

    New-Item -ItemType Directory -Path $dstDepDir -Force | Out-Null

    foreach ($dll in $dlls) {
        $src = Join-Path $srcDepDir $dll
        if (Test-Path $src) {
            Copy-Item $src -Destination $dstDepDir -Force
            Write-Log "  已复制: AHK-XAML/lib/dep/$dll" "Gray"
        } else {
            Write-Log "  [WARN] 未找到: AHK-XAML/lib/dep/$dll" "Yellow"
        }
    }

    # WpfAnimatedGif.dll 在 dep/WpfAnimatedGif 子目录
    $gifSrc = Join-Path $srcDepDir "WpfAnimatedGif\WpfAnimatedGif.dll"
    $gifDstDir = Join-Path $dstDepDir "WpfAnimatedGif"
    if (Test-Path $gifSrc) {
        New-Item -ItemType Directory -Path $gifDstDir -Force | Out-Null
        Copy-Item $gifSrc -Destination $gifDstDir -Force
        Write-Log "  已复制: AHK-XAML/lib/dep/WpfAnimatedGif/WpfAnimatedGif.dll" "Gray"
    } else {
        Write-Log "  [WARN] 未找到: AHK-XAML/lib/dep/WpfAnimatedGif/WpfAnimatedGif.dll" "Yellow"
    }
}

function Copy-AhiDriver {
    param([string]$ReleaseDir, [string]$Arch) # Arch: "x64" / "x86"

    $srcDir = Join-Path $PSScriptRoot "Plugins\AhiDriver"
    $dstDir = Join-Path $ReleaseDir "Plugins\AhiDriver"

    # 清理旧版 Plugins\AHI 目录（安装包已并入 AhiDriver\installer）
    $legacyAhiDir = Join-Path $ReleaseDir "Plugins\AHI"
    if (Test-Path $legacyAhiDir) {
        Remove-Item $legacyAhiDir -Recurse -Force
        Write-Log "  已清理旧目录: Plugins/AHI" "Yellow"
    }

    if (-not (Test-Path $srcDir)) {
        Write-Log "  [WARN] AhiDriver 源目录不存在: $srcDir" "Yellow"
        return
    }

    if (Test-Path $dstDir) {
        Remove-Item $dstDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null

    # 运行时只需对应架构的 DLL；ahk 源文件已编译进主程序/Worker
    $files = @(
        "AutoHotInterception.dll",
        "$Arch\interception.dll"
    )
    foreach ($rel in $files) {
        $src = Join-Path $srcDir $rel
        $dst = Join-Path $dstDir $rel
        if (Test-Path $src) {
            $parent = Split-Path $dst -Parent
            if (-not (Test-Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item $src -Destination $dst -Force
            Write-Log "  已复制: AhiDriver/$rel" "Gray"
        } else {
            Write-Log "  [WARN] 未找到: AhiDriver/$rel" "Yellow"
        }
    }

    # Interception 安装包（installer 子目录：install.ps1 / 安装卸载.bat / install-interception.exe）
    $installerSrc = Join-Path $srcDir "installer"
    $installerDst = Join-Path $dstDir "installer"
    if (Test-Path $installerSrc) {
        if (Test-Path $installerDst) {
            Remove-Item $installerDst -Recurse -Force
        }
        Copy-Item -Path $installerSrc -Destination $installerDst -Recurse -Force
        # 不把本机安装日志打进发行包
        $logFile = Join-Path $installerDst "install-log.txt"
        if (Test-Path $logFile) {
            Remove-Item $logFile -Force -ErrorAction SilentlyContinue
        }
        Write-Log "  已复制: AhiDriver/installer" "Gray"
    } else {
        Write-Log "  [WARN] 未找到: AhiDriver/installer" "Yellow"
    }
}

# 罗技按键(Ib) + 罗技鼠标移动(MouseControl)
function Copy-InputDlls {
    param([string]$ReleaseDir)

    $dstDir = Join-Path $ReleaseDir "Plugins"
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null

    $files = @(
        "IbInputSimulator.dll",
        "MouseControl.dll"
    )
    foreach ($name in $files) {
        $src = Join-Path $PSScriptRoot "Plugins\$name"
        $dst = Join-Path $dstDir $name
        if (Test-Path $src) {
            Copy-Item $src -Destination $dst -Force
            Write-Log "  已复制: Plugins/$name" "Gray"
        } else {
            Write-Log "  [WARN] 未找到: Plugins/$name" "Yellow"
        }
    }
}

# 语音触发插件（Voice）：按架构复制运行时 DLL + 共享 KWS 模型
function Copy-Voice {
    param([string]$ReleaseDir, [string]$Arch) # Arch: "x64" / "x86"

    $srcDir = Join-Path $PSScriptRoot "Plugins\Voice\$Arch"
    $dstDir = Join-Path $ReleaseDir "Plugins\Voice\$Arch"

    if (-not (Test-Path $srcDir)) {
        Write-Log "  [WARN] Voice 源目录不存在: $srcDir" "Yellow"
        return
    }

    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null

    # 架构相关的运行时 DLL（VoiceDll + sherpa c-api + onnxruntime）
    Get-ChildItem $srcDir -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $dstDir -Force
        Write-Log "  已复制: Voice/$Arch/$($_.Name)" "Gray"
    }

    # 共享 KWS 模型（跨架构，缺才复制）
    $modelSrc = Join-Path $PSScriptRoot "Plugins\Voice\models\kws"
    $modelDst = Join-Path $ReleaseDir "Plugins\Voice\models\kws"
    if (Test-Path $modelSrc) {
        New-Item -ItemType Directory -Path $modelDst -Force | Out-Null
        Get-ChildItem $modelSrc -File | ForEach-Object {
            $dst = Join-Path $modelDst $_.Name
            if (-not (Test-Path $dst)) {
                Copy-Item $_.FullName -Destination $dst -Force
                Write-Log "  已复制: Voice/models/kws/$($_.Name)" "Gray"
            }
        }
    } else {
        Write-Log "  [WARN] Voice 模型目录不存在: $modelSrc" "Yellow"
    }
}

# 文字识别插件（RapidOcr）：按架构复制 DLL + PP-OCRv6 ch_models（v6 统一多语言模型，无 en_models）
function Copy-RapidOcr {
    param([string]$ReleaseDir, [string]$Arch) # Arch: "x64" / "x86"

    $bitArch = if ($Arch -eq "x64") { "64bit" } else { "32bit" }
    $srcDll = Join-Path $PSScriptRoot "Plugins\RapidOcr\$bitArch\RapidOcrOnnx.dll"
    $dstDll = Join-Path $ReleaseDir "Plugins\RapidOcr\$bitArch\RapidOcrOnnx.dll"

    if (Test-Path $srcDll) {
        New-Item -ItemType Directory -Path (Split-Path $dstDll -Parent) -Force | Out-Null
        Copy-Item $srcDll -Destination $dstDll -Force
        Write-Log "  已复制: RapidOcr/$bitArch/RapidOcrOnnx.dll" "Gray"
    } else {
        Write-Log "  [WARN] 未找到: RapidOcr/$bitArch/RapidOcrOnnx.dll" "Yellow"
    }

    # PP-OCRv6 ch_models（det/rec/dict，跨架构共用，缺才复制）
    $modelSrc = Join-Path $PSScriptRoot "Plugins\RapidOcr\ch_models"
    $modelDst = Join-Path $ReleaseDir "Plugins\RapidOcr\ch_models"
    if (Test-Path $modelSrc) {
        New-Item -ItemType Directory -Path $modelDst -Force | Out-Null
        Get-ChildItem $modelSrc -File | ForEach-Object {
            $dst = Join-Path $modelDst $_.Name
            if (-not (Test-Path $dst)) {
                Copy-Item $_.FullName -Destination $dst -Force
                Write-Log "  已复制: RapidOcr/ch_models/$($_.Name)" "Gray"
            }
        }
    } else {
        Write-Log "  [WARN] RapidOcr 模型目录不存在: $modelSrc" "Yellow"
    }
}

function Compress-ReleaseZip {
    param([string]$SourceDir, [string]$ZipPath)

    $zipName = Split-Path $ZipPath -Leaf
    Write-Log "  压缩 $zipName ..." "Gray"
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }
    Compress-Archive -Path "$SourceDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal
    $size = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
    Write-Log "  [OK] $zipName ($size MB)" "Green"
}

# 生成 RMTAssets_{arch} 资源清单目录
# 目录内为扁平化的资源文件，与 Main\SelfCheck.ahk 中 criticalMap / optionalMap / icoFileList
# 一一对应，用于上传到 RMTAssets 仓库对应 tag（v{version}_{arch}）的 Release 资产
function New-RMTAssets {
    param([string]$Arch, [string]$ReleaseDir)

    $bitArch = if ($Arch -eq "x64") { "64bit" } else { "32bit" }
    $assetsDir = Join-Path $ReleaseDir "RMTAssets_$Arch"
    New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
    Write-Log "生成 $assetsDir ..." "Gray"

    # 关键文件 + 可选文件（本地路径 -> 资源名，与 SelfCheck.ahk 保持一致）
    $assetList = @(
        @{ Dest = "RMT.dll";                         Src = "Plugins\RMT\RMT.dll" },
        @{ Dest = "IbInputSimulator.dll";            Src = "Plugins\IbInputSimulator.dll" },
        @{ Dest = "Start.wav";                       Src = "Audio\Start.wav" },
        @{ Dest = "End.wav";                         Src = "Audio\End.wav" },
        @{ Dest = "ViGEmWrapper.dll";                Src = "Plugins\ViGEm\ViGEmWrapper.dll" },
        @{ Dest = "ViGEmBus.exe";                    Src = "Joy\ViGEmBus.exe" },
        @{ Dest = "Xbox.png";                        Src = "Joy\Xbox按键映射.png" },
        @{ Dest = "ahk-xaml.dll";                    Src = "Plugins\AHK-XAML\lib\dep\ahk-xaml.dll" },
        @{ Dest = "WpfAnimatedGif.dll";              Src = "Plugins\AHK-XAML\lib\dep\WpfAnimatedGif\WpfAnimatedGif.dll" },
        @{ Dest = "RMT_OpenCV.dll";                  Src = "Plugins\OpenCV\$Arch\RMT_OpenCV.dll" },
        @{ Dest = "opencv_world481.dll";             Src = "Plugins\OpenCV\$Arch\opencv_world481.dll" },
        @{ Dest = "VoiceDll.dll";                    Src = "Plugins\Voice\$Arch\VoiceDll.dll" },
        @{ Dest = "sherpa-onnx-c-api.dll";           Src = "Plugins\Voice\$Arch\sherpa-onnx-c-api.dll" },
        @{ Dest = "onnxruntime.dll";                 Src = "Plugins\Voice\$Arch\onnxruntime.dll" },
        @{ Dest = "onnxruntime_providers_shared.dll"; Src = "Plugins\Voice\$Arch\onnxruntime_providers_shared.dll" },
        @{ Dest = "kws_decoder.onnx";                Src = "Plugins\Voice\models\kws\decoder-epoch-13-avg-2-chunk-16-left-64.onnx" },
        @{ Dest = "kws_encoder.int8.onnx";           Src = "Plugins\Voice\models\kws\encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx" },
        @{ Dest = "kws_joiner.int8.onnx";            Src = "Plugins\Voice\models\kws\joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx" },
        @{ Dest = "kws_tokens.txt";                  Src = "Plugins\Voice\models\kws\tokens.txt" },
        @{ Dest = "RapidOcrOnnx.dll";                Src = "Plugins\RapidOcr\$bitArch\RapidOcrOnnx.dll" },
        @{ Dest = "ScreenCapture.exe";               Src = "Plugins\ScreenCapture\ScreenCapture.exe" },
        @{ Dest = "AutoHotInterception.dll";         Src = "Plugins\AhiDriver\AutoHotInterception.dll" },
        @{ Dest = "interception_$Arch.dll";          Src = "Plugins\AhiDriver\$Arch\interception.dll" },
        @{ Dest = "install.ps1";                     Src = "Plugins\AhiDriver\installer\install.ps1" },
        @{ Dest = "InstallUninstall.bat";            Src = "Plugins\AhiDriver\installer\安装卸载.bat" },
        @{ Dest = "install-interception.exe";        Src = "Plugins\AhiDriver\installer\install-interception.exe" },
        @{ Dest = "InstallReadme.txt";                 Src = "Plugins\AhiDriver\installer\使用说明.txt" },
        @{ Dest = "ch_PP-OCRv6_det.onnx";            Src = "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_det.onnx" },
        @{ Dest = "ch_PP-OCRv6_rec.onnx";            Src = "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_rec.onnx" },
        @{ Dest = "ppocrv6_tiny_dict.txt";           Src = "Plugins\RapidOcr\ch_models\ppocrv6_tiny_dict.txt" },
        @{ Dest = "chinese.txt";                     Src = "Lang\中文.txt" },
        @{ Dest = "English.txt";                     Src = "Lang\English.txt" },
        @{ Dest = "Work.exe";                        Src = "Release$Arch\Thread\Work.exe" },
        @{ Dest = "index.html";                      Src = "index.html" },
        @{ Dest = "MouseControl.dll";                Src = "Plugins\MouseControl.dll" },
        @{ Dest = "PlayAudio.vbs";                   Src = "MinTool\PlayAudio.vbs" },
        @{ Dest = "CountDown.exe";                   Src = "MinTool\CountDown.exe" }
    )

    $missing = 0
    foreach ($asset in $assetList) {
        $src = Join-Path $PSScriptRoot $asset.Src
        if (-not (Test-Path $src)) {
            Write-Log "  [WARN] 未找到: $($asset.Src)" "Yellow"
            $missing++
            continue
        }
        Copy-Item $src -Destination (Join-Path $assetsDir $asset.Dest) -Force
        Write-Log "  已复制: $($asset.Dest)" "Gray"
    }

    # 生成 ico.zip（Images\Soft 下 SelfCheck.ahk 的 icoFileList）
    $icoList = @(
        "Arr.png", "Condition.png", "Control.png", "Extract.png", "False.png",
        "FileIO.png", "GreenColor.png", "IcoPause.ico", "If.png", "IfPro.png",
        "Input.png", "Interval.png", "Key.png", "KeyCheck.png", "Loop.png",
        "LoopBody.png", "LoopCount.png", "Mouse.png", "Move.png", "MovePro.png",
        "Operation.png", "Output.png", "RedColor.png", "Run.png", "Search.png",
        "SearchPro.png", "Sub.png", "Target.png", "TextOps.png", "True.png",
        "Var.png", "WeiXin.png", "WindowManage.png", "YellowColor.png",
        "ZhiFuBao.png", "rabit.ico", "rabit.png", "Comment.png", "ScreenShot.png"
    )

    $softDir = Join-Path $PSScriptRoot "Images\Soft"
    $icoTempDir = Join-Path $assetsDir "_ico_temp"
    New-Item -ItemType Directory -Path $icoTempDir -Force | Out-Null
    $icoMissing = 0
    foreach ($ico in $icoList) {
        $src = Join-Path $softDir $ico
        if (Test-Path $src) {
            Copy-Item $src -Destination (Join-Path $icoTempDir $ico) -Force
        } else {
            Write-Log "  [WARN] 未找到图标: $ico" "Yellow"
            $icoMissing++
        }
    }
    $icoZip = Join-Path $assetsDir "ico.zip"
    if (Test-Path $icoZip) { Remove-Item $icoZip -Force }
    Compress-Archive -Path "$icoTempDir\*" -DestinationPath $icoZip -CompressionLevel Optimal
    Remove-Item $icoTempDir -Recurse -Force
    Write-Log "  已生成: ico.zip ($($icoList.Count - $icoMissing) 个文件)" "Gray"

    if ($missing -gt 0 -or $icoMissing -gt 0) {
        Write-Log "  [WARN] RMTAssets_$Arch 存在缺失文件" "Yellow"
    } else {
        Write-Log "  [OK] RMTAssets_$Arch 生成完成" "Green"
    }
}

# ============================================================
# 主流程
# ============================================================

function Main {
    Write-Section "RMT 打包工具"
    Write-Log "PowerShell $($PSVersionTable.PSVersion)" "Gray"
    Write-Log "工作目录: $PSScriptRoot" "Gray"

    if (-not $PSScriptRoot) {
        throw "无法确定脚本目录（PSScriptRoot 为空），请直接运行 PackRMT.cmd"
    }

    $persisted = Get-PersistedPolicy
    if ($persisted -eq "Restricted" -or $persisted -eq "AllSigned") {
        Write-Log "提示: 系统执行策略为 $persisted，右键 [使用 PowerShell 运行] 本 ps1 会被拒绝并闪退" "Yellow"
        Write-Log "      请始终用 PackRMT.cmd 启动，或执行: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" "Yellow"
    }

    # 步骤 1: 检查文件
    Write-Step 1 "检查源文件"
    $script:WorkAhk = Join-Path $PSScriptRoot "Thread\Work.ahk"
    $WorkDir = Join-Path $PSScriptRoot "Thread"
    if (-not (Test-Path $script:WorkAhk)) {
        throw "找不到源文件: $($script:WorkAhk)"
    }
    Write-Log "[OK] Work.ahk 存在" "Green"

    # 步骤 2: 查找编译工具
    Write-Step 2 "查找编译工具"
    $script:Ahk2exe = Find-Exe "Ahk2Exe" $Ahk2ExePaths
    if (-not $script:Ahk2exe) {
        throw "未找到 Ahk2Exe.exe，请确认已安装 AutoHotkey 编译器: $($Ahk2ExePaths -join ' | ')"
    }

    $script:Base64Exe = Find-Exe "64Base (AutoHotkey64.exe)" $Base64Paths
    if (-not $script:Base64Exe) {
        throw "未找到 AutoHotkey64.exe: $($Base64Paths -join ' | ')"
    }

    $script:Base32Exe = Find-Exe "32Base (AutoHotkey32.exe)" $Base32Paths

    # 步骤 3: 关闭正在运行的 RMT.ahk
    Write-Step 3 "关闭正在运行的 RMT.ahk"
    Stop-RunningRMT

    # 步骤 4: 清理旧文件
    Write-Step 4 "清理旧文件"
    Remove-OldFiles -Dir $WorkDir -Filter "Work.exe"

    # 步骤 5: 编译 Work.exe
    Write-Step 5 "编译 Work.exe"
    $IconPath = Join-Path $PSScriptRoot "Images\Soft\rabit.ico"
    if (-not (Compile -AhkFile $script:WorkAhk -BaseExe $script:Base64Exe -OutputExe "$WorkDir\Work.exe" -IconPath $IconPath -Name "Work.exe")) {
        throw "编译 Work.exe 失败，详见上方 Ahk2Exe 输出"
    }

    # 步骤 6: 打包帮助文档
    Write-Step 6 "打包帮助文档"
    if (-not (Pack-HelpDoc)) {
        Write-Log "警告: 帮助文档打包失败" "Yellow"
    }
    Write-Log "运行环境work编译完成" "Green"

    # 步骤 7: 询问是否生成发行版
    Write-Step 7 "生成发行版"
    $choice = Ask-Choice "请选择发行版类型:" @("不生成", "测试版 (仅 X64)", "正式版 (X64 + X86)")

    if ($choice -eq 2) {
        if (-not (New-Release -Type "x64")) {
            Write-Log "发行版创建失败" "Red"
        }
    }
    elseif ($choice -eq 3) {
        if ($script:Base32Exe) {
            if (-not (New-Release -Type "both")) {
                Write-Log "发行版创建失败" "Red"
            }
        }
        else {
            Write-Log "未找到 32 位编译器，生成 X64 测试版" "Yellow"
            if (-not (New-Release -Type "x64")) {
                Write-Log "发行版创建失败" "Red"
            }
        }
    }
    else {
        Write-Log "跳过发行版生成" "Gray"
    }

    Write-Section "打包完成"
}

# ============================================================
# 入口：任何异常都打印完整信息，且必须等待手动按键才退出
# ============================================================

$script:ExitCode = 0
$script:Transcript = $null

try {
    if ($PSScriptRoot) {
        $logDir = Join-Path $PSScriptRoot "Log"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $script:Transcript = Join-Path $logDir "PackRMT_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Start-Transcript -Path $script:Transcript -Force | Out-Null
    }
}
catch { $script:Transcript = $null }

try {
    Main
}
catch {
    Show-ErrorDetail $_
    $script:ExitCode = 1
}
finally {
    if ($script:Transcript) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host "`n日志: $($script:Transcript)" -ForegroundColor DarkGray
    }
    if (-not $NoPause) {
        if ($script:ExitCode -eq 0) {
            Wait-KeyPress "==== 全部完成，按任意键关闭窗口 ===="
        }
        else {
            Wait-KeyPress "==== 执行失败（退出码 $($script:ExitCode)），请查看上方错误信息，按任意键关闭窗口 ===="
        }
    }
}

exit $script:ExitCode
