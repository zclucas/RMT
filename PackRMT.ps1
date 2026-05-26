# RMT 自动打包脚本
# 使用 Ahk2Exe.exe 编译 Work.ahk 为 Work.exe
# 此脚本需要编码格式为UTF-8 BOM 或者 UTF-16才能正常运行
$Host.UI.RawUI.WindowTitle = "RMT 打包工具"
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

function Wait-KeyPress {
    param([string]$Message = "按任意键退出...", [int]$TimeoutSeconds = 0)
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
    $uiUtil = Join-Path $PSScriptRoot "Main\UIUtil.ahk"
    if (-not (Test-Path $uiUtil)) {
        Write-Log "  [ERROR] 未找到 UIUtil.ahk，无法获取版本号" "Red"
        return $null
    }
    $content = Get-Content $uiUtil -Raw
    # 匹配 RMTv1.2F1、RMTv2.1.2、RMTv2.0 等格式
    if ($content -match 'MyGui\.Title\s*:=\s*"RMTv(\d+(?:\.\d+)*(?:[a-zA-Z]+\d*)?)"') {
        $version = $matches[1]
        Write-Log "  版本号: v$version" "Gray"
        return $version
    }
    Write-Log "  [ERROR] 无法从 UIUtil.ahk 解析版本号" "Red"
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

    $arguments = @(
        "/in", "`"$AhkFile`"",
        "/icon", "`"$IconPath`"",
        "/base", "`"$BaseExe`"",
        "/out", "`"$OutputExe`""
    )

    Write-Log "  执行: Ahk2Exe /in ... /base ... /out ..." "Gray"
    $process = Start-Process -FilePath $Ahk2exe -ArgumentList $arguments -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Log "  [ERROR] 进程退出码: $($process.ExitCode)" "Red"
        return $false
    }

    Start-Sleep -Milliseconds 500

    if (-not (Test-Path $OutputExe)) {
        Write-Log "  [ERROR] 输出文件不存在" "Red"
        return $false
    }

    $size = [math]::Round((Get-Item $OutputExe).Length / 1MB, 2)
    Write-Log "  [OK] $Name 成功 (${size} MB)" "Green"
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
        $size = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
        Write-Log "[OK] 帮助文档打包成功 (${size} MB)" "Green"
        return $true
    }
    Write-Log "帮助文档打包失败" "Red"
    return $false
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

        # 复制帮助文档（index.html）
        $helpSrc = Join-Path $PSScriptRoot "index.html"
        if (Test-Path $helpSrc) {
            Copy-Item $helpSrc -Destination (Join-Path $releaseDir "index.html") -Force
            Write-Log "  已复制: index.html" "Gray"
        }

        # 删除旧 Work.exe
        Remove-OldFiles -Dir $releaseThread -Filter "Work.exe"

        # 编译 Work.exe
        if (-not (Compile -AhkFile $WorkAhk -BaseExe $Base64Exe -OutputExe "$releaseThread\Work.exe" -IconPath $IconPath -Name "Work.exe")) {
            return $false
        }

        # 编译主程序 RMTv{version}.exe
        if (-not (Compile -AhkFile $RmtAhk -BaseExe $Base64Exe -OutputExe "$releaseDir\RMTv$version.exe" -IconPath $IconPath -Name "RMTv$version.exe")) {
            return $false
        }

        # 复制 OpenCV DLL (x64)
        Write-Log "复制 OpenCV DLL (x64)..." "Gray"
        Copy-OpenCV -ReleaseDir $releaseDir -Arch "x64"

        # 复制 AHK-XAML DLL
        Write-Log "复制 AHK-XAML DLL..." "Gray"
        Copy-XamlDlls -ReleaseDir $releaseDir
    }

    if ($Type -eq "x32" -or $Type -eq "both") {
        Write-Step 2 "生成 ReleaseX32"
        $releaseDir = Join-Path $PSScriptRoot "ReleaseX32"
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

        # 复制帮助文档（index.html）
        $helpSrc = Join-Path $PSScriptRoot "index.html"
        if (Test-Path $helpSrc) {
            Copy-Item $helpSrc -Destination (Join-Path $releaseDir "index.html") -Force
            Write-Log "  已复制: index.html" "Gray"
        }

        # 删除旧 Work.exe
        Remove-OldFiles -Dir $releaseThread -Filter "Work.exe"

        # 编译 Work.exe (32位)
        if (-not (Compile -AhkFile $WorkAhk -BaseExe $Base32Exe -OutputExe "$releaseThread\Work.exe" -IconPath $IconPath -Name "Work.exe")) {
            return $false
        }

        # 编译主程序 RMTv{version}.exe
        if (-not (Compile -AhkFile $RmtAhk -BaseExe $Base32Exe -OutputExe "$releaseDir\RMTv$version.exe" -IconPath $IconPath -Name "RMTv$version.exe")) {
            return $false
        }

        # 复制 OpenCV DLL (x86)
        Write-Log "复制 OpenCV DLL (x86)..." "Gray"
        Copy-OpenCV -ReleaseDir $releaseDir -Arch "x86"

        # 复制 AHK-XAML DLL
        Write-Log "复制 AHK-XAML DLL..." "Gray"
        Copy-XamlDlls -ReleaseDir $releaseDir
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

    if ($Type -eq "x32" -or $Type -eq "both") {
        $destX32 = Join-Path $versionDir "RMTv${version}_x32"
        New-Item -ItemType Directory -Path $destX32 -Force | Out-Null
        Write-Log "复制 ReleaseX32 to $destX32 ..." "Gray"
        Copy-Item -Path "$PSScriptRoot\ReleaseX32\*" -Destination $destX32 -Recurse -Force
    }

    Write-Section "压缩发行包"
    if ($Type -eq "x64" -or $Type -eq "both") {
        Compress-ReleaseZip -SourceDir (Join-Path $versionDir "RMTv${version}_x64") -ZipPath (Join-Path $rmtReleaseDir "RMTv${version}_x64.zip")
    }
    if ($Type -eq "x32" -or $Type -eq "both") {
        Compress-ReleaseZip -SourceDir (Join-Path $versionDir "RMTv${version}_x32") -ZipPath (Join-Path $rmtReleaseDir "RMTv${version}_x32.zip")
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
    Write-Log "to $versionDir\RMTv${version}_x64" "White"
    if ($Type -eq "both") {
        Write-Log "to $versionDir\RMTv${version}_x32" "White"
    }
    Write-Log "to $rmtReleaseDir\RMTv${version}_x64.zip" "White"
    if ($Type -eq "both") {
        Write-Log "to $rmtReleaseDir\RMTv${version}_x32.zip" "White"
    }
    return $true
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

    $srcDir = Join-Path $PSScriptRoot "Plugins\AHK-XAML\lib"
    $dstDir = Join-Path $ReleaseDir "Plugins\AHK-XAML\lib"
    $dlls = @("ahk-xaml.dll", "WpfAnimatedGif.dll")

    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null

    foreach ($dll in $dlls) {
        $src = Join-Path $srcDir $dll
        if (Test-Path $src) {
            Copy-Item $src -Destination $dstDir -Force
            Write-Log "  已复制: AHK-XAML/lib/$dll" "Gray"
        } else {
            Write-Log "  [WARN] 未找到: AHK-XAML/lib/$dll" "Yellow"
        }
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

# ============================================================
# 主流程
# ============================================================

function Main {
    try {
        Write-Section "RMT 打包工具"
        Write-Log "PowerShell $($PSVersionTable.PSVersion)" "Gray"
        Write-Log "工作目录: $PSScriptRoot" "Gray"

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
        Write-Log "[OK] Work.ahk 存在" "Green"

        # 步骤 2: 查找编译工具
        Write-Step 2 "查找编译工具"
        $Ahk2exe = Find-Exe "Ahk2Exe" $Ahk2ExePaths
        if (-not $Ahk2exe) { Wait-KeyPress; exit 1 }

        $Base64Exe = Find-Exe "64Base (AutoHotkey64.exe)" $Base64Paths
        if (-not $Base64Exe) { Wait-KeyPress; exit 1 }

        $Base32Exe = Find-Exe "32Base (AutoHotkey32.exe)" $Base32Paths

        # 步骤 3: 关闭正在运行的 RMT.ahk
        Write-Step 3 "关闭正在运行的 RMT.ahk"
        Stop-RunningRMT

        # 步骤 4: 清理旧文件
        Write-Step 4 "清理旧文件"
        Remove-OldFiles -Dir $WorkDir -Filter "Work.exe"

        # 步骤 5: 编译 Work.exe
        Write-Step 5 "编译 Work.exe"
        $IconPath = Join-Path $PSScriptRoot "Images\Soft\rabit.ico"
        $result = Compile -AhkFile $WorkAhk -BaseExe $Base64Exe -OutputExe "$WorkDir\Work.exe" -IconPath $IconPath -Name "Work.exe"
        if (-not $result) { Wait-KeyPress; exit 1 }

        # 步骤 6: 打包帮助文档
        Write-Step 6 "打包帮助文档"
        if (-not (Pack-HelpDoc)) {
            Write-Log "警告: 帮助文档打包失败" "Yellow"
        }
        Write-Log "运行环境work编译完成" "Green"

        # 步骤 7: 询问是否生成发行版
        Write-Step 7 "生成发行版"
        $choice = Ask-Choice "请选择发行版类型:" @("不生成", "测试版 (仅 X64)", "正式版 (X64 + X32)")

        if ($choice -eq 2) {
            if (-not (New-Release -Type "x64")) {
                Write-Log "发行版创建失败" "Red"
            }
        }
        elseif ($choice -eq 3) {
            if ($Base32Exe) {
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
