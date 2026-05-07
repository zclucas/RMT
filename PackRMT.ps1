# RMT 自动打包脚本
# 使用 Ahk2Exe.exe 编译 Work.ahk 为 Work1.exe

param(
    [ValidateSet("interactive", "none", "x64", "both")]
    [string]$ReleaseType = "interactive",
    [ValidateSet("both", "lite", "runtime")]
    [string]$Distribution = "both",
    [string]$OutputDir = "",
    [switch]$NoWait
)

$Host.UI.RawUI.WindowTitle = "RMT 打包工具"
$ErrorActionPreference = "Stop"

# ============================================================
# 配置路径
# ============================================================

# Ahk2Exe 编译器路径
$Ahk2ExePaths = @(
    "$PSScriptRoot\.tools\AutoHotkey\Compiler\Ahk2Exe.exe",
    "$PSScriptRoot\.tools\Ahk2Exe\Ahk2Exe.exe",
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
)

# 64位 Ahk2Exe base 路径
$Base64Paths = @(
    "$PSScriptRoot\.tools\AutoHotkey\v2\Unicode 64-bit.bin",
    "$PSScriptRoot\.tools\AutoHotkey\v2\AutoHotkey64.exe",
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
)

# 32位 Ahk2Exe base 路径
$Base32Paths = @(
    "$PSScriptRoot\.tools\AutoHotkey\v2\Unicode 32-bit.bin",
    "$PSScriptRoot\.tools\AutoHotkey\v2\AutoHotkey32.exe",
    "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
)

# 64位 AutoHotkey 运行器路径，用于 Ahk2Exe 的 /ahk 自动 include 扫描
$Ahk64Paths = @(
    "$PSScriptRoot\.tools\AutoHotkey\v2\AutoHotkey64.exe",
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
)

# 32位 AutoHotkey 运行器路径，用于 Ahk2Exe 的 /ahk 自动 include 扫描
$Ahk32Paths = @(
    "$PSScriptRoot\.tools\AutoHotkey\v2\AutoHotkey32.exe",
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

function Wait-KeyPress {
    param([string]$Message = "按任意键退出...", [int]$TimeoutSeconds = 0)
    if ($NoWait) { return }
    Write-Host "`n$Message" -ForegroundColor Yellow
    if ($TimeoutSeconds -gt 0) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if ([Console]::KeyAvailable) {
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); break
            }
            Start-Sleep -Milliseconds 100
        }
        $timer.Stop()
    }
    else {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
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
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
        if ([int]$key -ge 49 -and [int]$key -le 48 + $Options.Length) {
            return [int]$key - 48
        }
    }
}

# ============================================================
# 工具函数
# ============================================================

function Find-Exe {
    param([string]$Name, [string[]]$Paths)
    foreach ($path in $Paths) {
        if (Test-Path $path) { Write-Log "  ✓ 找到 $Name" "Green"; return $path }
    }
    Write-Log "  ✗ 未找到 $Name" "Red"
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

function Copy-RequiredFile {
    param([string]$Source, [string]$DestDir)

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "缺少发行资源: $Source"
    }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $DestDir -Force
    Write-Log "  已复制: $(Split-Path $Source -Leaf)" "Gray"
}

function Copy-RequiredDirectory {
    param([string]$Source, [string]$Destination)

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "缺少发行资源目录: $Source"
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force -Recurse
    Write-Log "  已复制: $(Split-Path $Source -Leaf)" "Gray"
}

function Get-Version {
    $uiUtil = Join-Path $PSScriptRoot "Main\UIUtil.ahk"
    if (-not (Test-Path $uiUtil)) {
        Write-Log "  ✗ 未找到 UIUtil.ahk，无法获取版本号" "Red"
        return $null
    }
    $content = Get-Content $uiUtil -Raw
    # 匹配 RMTv1.1.2 或 RMTv1.1 格式
    if ($content -match 'RMT_WEBVIEW_VERSION\s*:=\s*"RMTv(\d+(?:\.\d+)?(?:\.\d+)?)"') {
        $version = $matches[1]
        Write-Log "  版本号: v$version" "Gray"
        return $version
    }
    if ($content -match 'MyGui\.Title\s*:=\s*"RMTv(\d+(?:\.\d+)?(?:\.\d+)?)"') {
        $version = $matches[1]
        Write-Log "  版本号: v$version" "Gray"
        return $version
    }
    Write-Log "  ✗ 无法从 UIUtil.ahk 解析版本号" "Red"
    return $null
}

function Get-Ahk2ExeComSpecShim {
    $shimDir = Join-Path $PSScriptRoot ".tools\ComSpecShim"
    $shimPath = Join-Path $shimDir "cmd.exe"
    if (Test-Path $shimPath) {
        return $shimPath
    }

    try {
        New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
        $source = @'
using System;
public static class Program
{
    public static int Main(string[] args)
    {
        return 0;
    }
}
'@
        Add-Type -TypeDefinition $source -OutputAssembly $shimPath -OutputType ConsoleApplication -ErrorAction Stop
        return $shimPath
    }
    catch {
        Write-Log "  警告: 无法创建 Ahk2Exe ComSpec shim: $($_.Exception.Message)" "Yellow"
        return $null
    }
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
        [string]$AhkExe,
        [string]$OutputExe,
        [string]$IconPath,
        [string]$Name = "编译"
    )

    $arguments = @(
        "/in", "`"$AhkFile`"",
        "/icon", "`"$IconPath`"",
        "/base", "`"$BaseExe`"",
        "/ahk", "`"$AhkExe`"",
        "/cp", "65001",
        "/out", "`"$OutputExe`"",
        "/silent", "verbose"
    )

    Write-Log "  执行: Ahk2Exe /in ... /base ... /ahk ... /out ..." "Gray"
    $process = Start-Process -FilePath $Ahk2exe -ArgumentList $arguments -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Log "  ✗ 进程退出码: $($process.ExitCode)" "Red"
        return $false
    }

    Start-Sleep -Milliseconds 500

    if (-not (Test-Path $OutputExe)) {
        Write-Log "  ✗ 输出文件不存在" "Red"
        return $false
    }

    $size = [math]::Round((Get-Item $OutputExe).Length / 1MB, 2)
    Write-Log "  ✓ $Name 成功 (${size} MB)" "Green"
    return $true
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
    $null = Start-Process -FilePath "node" -ArgumentList "SingleHtml.js" -NoNewWindow -Wait -PassThru
    Pop-Location

    $OutputFile = Join-Path $PSScriptRoot "index.html"
    if (Test-Path $OutputFile) {
        $size = [math]::Round((Get-Item $OutputFile).Length / 1024, 1)
        $size = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
        Write-Log "✓ 帮助文档打包成功 (${size} MB)" "Green"
        return $true
    }
    Write-Log "帮助文档打包失败" "Red"
    return $false
}

function Copy-WebViewAssets {
    param([string]$ReleaseDir)

    $distDir = Join-Path $PSScriptRoot "WebViewApp\dist"
    $distIndex = Join-Path $distDir "index.html"
    if (-not (Test-Path $distIndex)) {
        Write-Log "  ✗ 未找到 WebViewApp\dist\index.html，请先运行 npm.cmd run build" "Red"
        return $false
    }

    $destWebViewApp = Join-Path $ReleaseDir "WebViewApp"
    if (Test-Path $destWebViewApp) {
        Remove-Item $destWebViewApp -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destWebViewApp -Force | Out-Null
    Copy-Item -Path $distDir -Destination (Join-Path $destWebViewApp "dist") -Force -Recurse
    Write-Log "  已复制 WebViewApp\dist" "Gray"

    $webViewTooLib = Join-Path $PSScriptRoot "Plugins\WebViewToo\Lib"
    $destWebViewToo = Join-Path $ReleaseDir "Plugins\WebViewToo"
    $destWebViewTooLib = Join-Path $destWebViewToo "Lib"
    if (Test-Path $destWebViewTooLib) {
        Remove-Item $destWebViewTooLib -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destWebViewToo -Force | Out-Null
    Copy-Item -Path $webViewTooLib -Destination $destWebViewTooLib -Force -Recurse
    Write-Log "  已复制 WebViewToo 运行库" "Gray"
    return $true
}

function Initialize-ReleaseDir {
    param(
        [string]$ReleaseDir,
        [ValidateSet("x64", "x32")]
        [string]$ReleaseArch
    )

    if (Test-Path -LiteralPath $ReleaseDir) {
        Remove-Item -LiteralPath $ReleaseDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

    Write-Log "初始化 $ReleaseArch 发行目录..." "Gray"
    foreach ($dirName in @("Audio", "Joy", "VBS", "Lang")) {
        Copy-RequiredDirectory `
            -Source (Join-Path $PSScriptRoot $dirName) `
            -Destination (Join-Path $ReleaseDir $dirName)
    }

    $helpSrc = Join-Path $PSScriptRoot "RMT帮助文档.html"
    if (Test-Path -LiteralPath $helpSrc) {
        Copy-RequiredFile -Source $helpSrc -DestDir $ReleaseDir
    }

    $pluginsDir = Join-Path $ReleaseDir "Plugins"
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
    Copy-RequiredFile -Source (Join-Path $PSScriptRoot "Plugins\IbInputSimulator.dll") -DestDir $pluginsDir

    $openCvDir = Join-Path $pluginsDir "OpenCV"
    Copy-RequiredFile -Source (Join-Path $PSScriptRoot "Plugins\OpenCV\opencv_world481.dll") -DestDir $openCvDir
    Copy-RequiredFile -Source (Join-Path $PSScriptRoot "Plugins\OpenCV\RMT_OpenCV.dll") -DestDir $openCvDir

    $rmtPluginDir = Join-Path $pluginsDir "RMT"
    Copy-RequiredFile -Source (Join-Path $PSScriptRoot "Plugins\RMT\RMT.dll") -DestDir $rmtPluginDir

    $screenCaptureDir = Join-Path $pluginsDir "ScreenCapture"
    Copy-RequiredFile -Source (Join-Path $PSScriptRoot "Plugins\ScreenCapture\ScreenCapture.exe") -DestDir $screenCaptureDir

    $vigemDir = Join-Path $pluginsDir "ViGEm"
    Copy-RequiredFile -Source (Join-Path $PSScriptRoot "Plugins\ViGEm\ViGEmWrapper.dll") -DestDir $vigemDir

    $rapidOcrDir = Join-Path $pluginsDir "RapidOcr"
    $rapidOcrArchDir = if ($ReleaseArch -eq "x64") { "64bit" } else { "32bit" }
    Copy-RequiredDirectory -Source (Join-Path $PSScriptRoot "Plugins\RapidOcr\$rapidOcrArchDir") -Destination (Join-Path $rapidOcrDir $rapidOcrArchDir)
    Copy-RequiredDirectory -Source (Join-Path $PSScriptRoot "Plugins\RapidOcr\ch_models") -Destination (Join-Path $rapidOcrDir "ch_models")
    Copy-RequiredDirectory -Source (Join-Path $PSScriptRoot "Plugins\RapidOcr\en_models") -Destination (Join-Path $rapidOcrDir "en_models")
}

function Get-ReleaseVariants {
    param([string]$DistributionType)
    if ($DistributionType -eq "both") {
        return @("lite", "runtime")
    }
    return @($DistributionType)
}

function Get-RuntimeArchName {
    param([string]$ReleaseArch)
    if ($ReleaseArch -eq "x64") {
        return "x64"
    }
    return "x86"
}

function Get-ReleaseOutputRoot {
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        return (Join-Path ([Environment]::GetFolderPath("Desktop")) "RMTRelease")
    }
    if ([System.IO.Path]::IsPathRooted($OutputDir)) {
        return $OutputDir
    }
    return (Join-Path $PSScriptRoot $OutputDir)
}

function Resolve-WebViewFixedRuntimeSource {
    param([string]$ArchName)

    $roots = @(
        (Join-Path $PSScriptRoot "Runtimes\WebView2\Fixed\$ArchName"),
        (Join-Path $PSScriptRoot ".tools\WebView2Runtime\Fixed\$ArchName"),
        (Join-Path $PSScriptRoot ".tools\WebView2Runtime\$ArchName")
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        if (Test-Path -LiteralPath (Join-Path $root "msedgewebview2.exe")) {
            return (Resolve-Path -LiteralPath $root).Path
        }

        $match = Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "msedgewebview2.exe") } |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

function Copy-WebViewFixedRuntime {
    param(
        [string]$ReleaseDir,
        [string]$ArchName
    )

    $source = Resolve-WebViewFixedRuntimeSource -ArchName $ArchName
    if (-not $source) {
        Write-Log "  ✗ 未找到 WebView2 Fixed Runtime ($ArchName)" "Red"
        Write-Log "    请放到 Runtimes\WebView2\Fixed\$ArchName 或 .tools\WebView2Runtime\Fixed\$ArchName" "Yellow"
        return $false
    }

    $dest = Join-Path $ReleaseDir "Runtimes\WebView2\Fixed\$ArchName"
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $source "*") -Destination $dest -Force -Recurse
    Write-Log "  已复制 WebView2 Fixed Runtime ($ArchName)" "Gray"
    return $true
}

function Copy-ReleaseVariant {
    param(
        [string]$SourceDir,
        [string]$VersionDir,
        [string]$Version,
        [string]$ReleaseArch,
        [string]$Variant
    )

    $dest = Join-Path $VersionDir "RMTv${Version}_${ReleaseArch}_${Variant}"
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Write-Log "复制 $SourceDir → $dest ..." "Gray"
    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $dest -Recurse -Force

    $runtimeRoot = Join-Path $dest "Runtimes\WebView2"
    if ($Variant -eq "runtime") {
        $runtimeArch = Get-RuntimeArchName -ReleaseArch $ReleaseArch
        if (-not (Copy-WebViewFixedRuntime -ReleaseDir $dest -ArchName $runtimeArch)) {
            return $null
        }
    }
    elseif (Test-Path -LiteralPath $runtimeRoot) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
    }

    return $dest
}

# ============================================================
# 发行版函数
# ============================================================

function New-Release {
    param([string]$Type) # "x64" or "x32" or "both"

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
        Initialize-ReleaseDir -ReleaseDir $releaseDir -ReleaseArch "x64"
        $releaseThread = Join-Path $releaseDir "Thread"

        # 创建目录
        New-Item -ItemType Directory -Path $releaseThread -Force | Out-Null

        # 复制 WebView2 前端和运行库
        if (-not (Copy-WebViewAssets $releaseDir)) {
            return $false
        }

        # 删除旧 Work*.exe
        Remove-OldFiles -Dir $releaseThread -Filter "Work*.exe"

        # 编译 Work1.exe
        if (-not (Compile -AhkFile $WorkAhk -BaseExe $Base64Exe -AhkExe $Ahk64Exe -OutputExe "$releaseThread\Work1.exe" -IconPath $IconPath -Name "Work1.exe")) {
            return $false
        }

        # 编译主程序 RMTv{version}.exe
        if (-not (Compile -AhkFile $RmtAhk -BaseExe $Base64Exe -AhkExe $Ahk64Exe -OutputExe "$releaseDir\RMTv$version.exe" -IconPath $IconPath -Name "RMTv$version.exe")) {
            return $false
        }
    }

    if ($Type -eq "x32" -or $Type -eq "both") {
        Write-Step 2 "生成 ReleaseX32"
        $releaseDir = Join-Path $PSScriptRoot "ReleaseX32"
        Initialize-ReleaseDir -ReleaseDir $releaseDir -ReleaseArch "x32"
        $releaseThread = Join-Path $releaseDir "Thread"

        # 创建目录
        New-Item -ItemType Directory -Path $releaseThread -Force | Out-Null

        # 复制 WebView2 前端和运行库
        if (-not (Copy-WebViewAssets $releaseDir)) {
            return $false
        }

        # 删除旧 Work*.exe
        Remove-OldFiles -Dir $releaseThread -Filter "Work*.exe"

        # 编译 Work1.exe (32位)
        if (-not (Compile -AhkFile $WorkAhk -BaseExe $Base32Exe -AhkExe $Ahk32Exe -OutputExe "$releaseThread\Work1.exe" -IconPath $IconPath -Name "Work1.exe")) {
            return $false
        }

        # 编译主程序 RMTv{version}.exe
        if (-not (Compile -AhkFile $RmtAhk -BaseExe $Base32Exe -AhkExe $Ahk32Exe -OutputExe "$releaseDir\RMTv$version.exe" -IconPath $IconPath -Name "RMTv$version.exe")) {
            return $false
        }
    }

    Write-Section "创建发行包"
    $rmtReleaseDir = Get-ReleaseOutputRoot

    if (-not (Test-Path -LiteralPath $rmtReleaseDir)) {
        New-Item -ItemType Directory -Path $rmtReleaseDir -Force | Out-Null
    }

    $versionDir = Join-Path $rmtReleaseDir "RMTv$version"
    if (Test-Path -LiteralPath $versionDir) {
        Write-Log "删除旧版本目录: $versionDir" "Yellow"
        Remove-Item -LiteralPath $versionDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
    Write-Log "创建 $versionDir" "Gray"

    $variants = Get-ReleaseVariants -DistributionType $Distribution
    $packageDirs = @()

    if ($Type -eq "x64" -or $Type -eq "both") {
        foreach ($variant in $variants) {
            $destX64 = Copy-ReleaseVariant -SourceDir (Join-Path $PSScriptRoot "ReleaseX64") -VersionDir $versionDir -Version $version -ReleaseArch "x64" -Variant $variant
            if (-not $destX64) {
                return $false
            }
            $packageDirs += $destX64
        }
    }

    if ($Type -eq "x32" -or $Type -eq "both") {
        foreach ($variant in $variants) {
            $destX32 = Copy-ReleaseVariant -SourceDir (Join-Path $PSScriptRoot "ReleaseX32") -VersionDir $versionDir -Version $version -ReleaseArch "x32" -Variant $variant
            if (-not $destX32) {
                return $false
            }
            $packageDirs += $destX32
        }
    }

    Write-Section "压缩发行包"
    $zipPaths = @()
    foreach ($packageDir in $packageDirs) {
        $zipName = "$(Split-Path $packageDir -Leaf).zip"
        $zipPath = Join-Path $rmtReleaseDir $zipName
        Compress-ReleaseZip -SourceDir $packageDir -ZipPath $zipPath
        $zipPaths += $zipPath
    }

    # 删除 ReleaseX64/ReleaseX32 下的 RMT*.exe
    Write-Section "清理临时文件"
    if ($Type -eq "x64" -or $Type -eq "both") {
        Write-Log "删除 ReleaseX64 下的 RMT*.exe..." "Gray"
        Get-ChildItem (Join-Path $PSScriptRoot "ReleaseX64") -Filter "RMT*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Log "  已删除: $($_.Name)" "Yellow"
        }
    }
    if ($Type -eq "x32" -or $Type -eq "both") {
        Write-Log "删除 ReleaseX32 下的 RMT*.exe..." "Gray"
        Get-ChildItem (Join-Path $PSScriptRoot "ReleaseX32") -Filter "RMT*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Log "  已删除: $($_.Name)" "Yellow"
        }
    }

    Write-Section "发行版创建完成"
    foreach ($packageDir in $packageDirs) {
        Write-Log "→ $packageDir" "White"
    }
    foreach ($zipPath in $zipPaths) {
        Write-Log "→ $zipPath" "White"
    }
    return $true
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
    Write-Log "  ✓ $zipName ($size MB)" "Green"
}

# ============================================================
# 主流程
# ============================================================

function Main {
    try {
        Write-Section "RMT 打包工具"
        Write-Log "PowerShell $($PSVersionTable.PSVersion)" "Gray"
        Write-Log "工作目录: $PSScriptRoot" "Gray"
        Write-Log "分发版本: $Distribution" "Gray"
        Write-Log "输出目录: $(Get-ReleaseOutputRoot)" "Gray"

        if (-not $PSScriptRoot) {
            Write-Log "错误: 无法确定脚本目录" "Red"
            Wait-KeyPress; exit 1
        }

        # 步骤 1: 检查文件
        Write-Step 1 "检查源文件"
        $WorkAhk = Join-Path $PSScriptRoot "Thread\Work.ahk"
        $WorkDir = Join-Path $PSScriptRoot "Thread"
        if (-not (Test-Path $WorkAhk)) {
            Write-Log "错误: 找不到 $WorkAhk" "Red"
            Wait-KeyPress; exit 1
        }
        Write-Log "✓ Work.ahk 存在" "Green"

        # 步骤 2: 查找编译工具
        Write-Step 2 "查找编译工具"
        $Ahk2exe = Find-Exe "Ahk2Exe" $Ahk2ExePaths
        if (-not $Ahk2exe) { Wait-KeyPress; exit 1 }

        $Base64Exe = Find-Exe "64Base (Unicode 64-bit.bin)" $Base64Paths
        if (-not $Base64Exe) { Wait-KeyPress; exit 1 }

        $Base32Exe = Find-Exe "32Base (Unicode 32-bit.bin)" $Base32Paths

        $Ahk64Exe = Find-Exe "64Runtime (AutoHotkey64.exe)" $Ahk64Paths
        if (-not $Ahk64Exe) { Wait-KeyPress; exit 1 }

        $Ahk32Exe = Find-Exe "32Runtime (AutoHotkey32.exe)" $Ahk32Paths

        # 步骤 3: 关闭正在运行的 RMT.ahk
        Write-Step 3 "关闭正在运行的 RMT.ahk"
        Stop-RunningRMT

        # 步骤 4: 清理旧文件
        Write-Step 4 "清理旧文件"
        Remove-OldFiles -Dir $WorkDir -Filter "Work1.exe"

        # 步骤 5: 编译 Work1.exe
        Write-Step 5 "编译 Work1.exe"
        $IconPath = Join-Path $PSScriptRoot "Images\Soft\rabit.ico"
        $result = Compile -AhkFile $WorkAhk -BaseExe $Base64Exe -AhkExe $Ahk64Exe -OutputExe "$WorkDir\Work1.exe" -IconPath $IconPath -Name "Work1.exe"
        if (-not $result) { Wait-KeyPress; exit 1 }

        # 步骤 6: 打包帮助文档
        Write-Step 6 "打包帮助文档"
        if (-not (Pack-HelpDoc)) {
            Write-Log "警告: 帮助文档打包失败" "Yellow"
        }
        Write-Log "运行环境work编译完成" "Green"

        # 步骤 7: 询问是否生成发行版
        Write-Step 7 "生成发行版"
        if ($ReleaseType -eq "interactive") {
            $choice = Ask-Choice "请选择发行版类型:" @("不生成", "测试版 (仅 X64)", "正式版 (X64 + X32)")
        }
        elseif ($ReleaseType -eq "none") {
            $choice = 1
        }
        elseif ($ReleaseType -eq "x64") {
            $choice = 2
        }
        else {
            $choice = 3
        }

        if ($choice -eq 2) {
            if (-not (New-Release -Type "x64")) {
                Write-Log "发行版创建失败" "Red"
            }
        }
        elseif ($choice -eq 3) {
            if ($Base32Exe -and $Ahk32Exe) {
                if (-not (New-Release -Type "both")) {
                    Write-Log "发行版创建失败" "Red"
                }
            }
            else {
                Write-Log "未找到 32 位 base 或运行器，生成 X64 测试版" "Yellow"
                if (-not (New-Release -Type "x64")) {
                    Write-Log "发行版创建失败" "Red"
                }
            }
        }
        else {
            Write-Log "跳过发行版生成" "Gray"
        }

        # 完成
        Write-Section "打包完成"
        Write-Host ""
        Wait-KeyPress -TimeoutSeconds 30

    }
    catch {
        Write-Log "错误: $($_.Exception.Message)" "Red"
        Write-Log "位置: $($_.InvocationInfo.ScriptLineNumber)" "Gray"
        Wait-KeyPress; exit 1
    }
}

Main
