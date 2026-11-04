# RMT 编译脚本（开发用，只编译，不打包）
# 编译主程序 RMTv<版本>.exe 与 Thread\Work.exe，输出到项目根目录，编译完即可直接运行。
# 完整的发行包打包见 PackRMT.ps1。
#
# 没有位置参数时：x64，编译主程序 + Worker，不清理。
# 带参数时按参数执行，参数之间没有顺序要求：
#
#   .\Build.ps1              主程序 + Worker（x64）
#   .\Build.ps1 x86          主程序 + Worker（32 位）
#   .\Build.ps1 rmt          只编译主程序
#   .\Build.ps1 work         只编译 Worker
#   .\Build.ps1 clean        只清理 Log + Setting，不编译
#   .\Build.ps1 clean log    只清理 Log
#   .\Build.ps1 clean work   先清理再编译 Worker
#   .\Build.ps1 x64 clean    先清理再编译（与上一个等价）
#
# 版本号自动读 RMT.ahk 的 RMT_VERSION；图标固定用 Images\Soft\rabit.ico；
# 输出固定到项目根目录（Worker 在其下的 Thread）。
# 编译/清理前如果文件被本项目目录内正在运行的实例占用，会自动结束该实例。

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    Write-Host "  [WARN] $Text" -ForegroundColor Yellow
}

function Write-Err([string]$Text) {
    Write-Host "  [ERROR] $Text" -ForegroundColor Red
}

function Show-Usage {
    Write-Host "  可用参数：x64  x86  rmt  work  clean [log|setting|all]" -ForegroundColor Gray
    Write-Host "  例：.\Build.ps1    .\Build.ps1 work    .\Build.ps1 clean log    .\Build.ps1 x86 clean" -ForegroundColor Gray
}

# ---------- 解析参数 ----------
$tokens = @()
foreach ($t in $args) {
    foreach ($piece in ("$t".Trim().ToLowerInvariant() -split "\s+")) {
        if ($piece -ne "") { $tokens += $piece }
    }
}

$unknown = @($tokens | Where-Object { $_ -notin @("x64", "x86", "rmt", "work", "clean", "log", "setting", "all") })
if ($unknown.Count -gt 0) {
    Write-Err "不认识的参数：$($unknown -join ' ')"
    Show-Usage
    exit 1
}

$Arch = if ($tokens -contains "x86") { "x86" } else { "x64" }

$hasClean = ($tokens -contains "clean") -or ($tokens -contains "log") -or
            ($tokens -contains "setting") -or ($tokens -contains "all")
$CleanScope = "all"
if ($tokens -contains "setting") { $CleanScope = "setting" }
elseif ($tokens -contains "log") { $CleanScope = "log" }

$selectedBuild = ($tokens -contains "rmt") -or ($tokens -contains "work") -or
                 ($tokens -contains "x64") -or ($tokens -contains "x86")
$WantRmt = $false
$WantWork = $false
if ($tokens.Count -eq 0) {
    $WantRmt = $true
    $WantWork = $true
} elseif ($selectedBuild) {
    $WantRmt = $tokens -contains "rmt"
    $WantWork = $tokens -contains "work"
    if (-not $WantRmt -and -not $WantWork) {   # 只给了架构：两个都编
        $WantRmt = $true
        $WantWork = $true
    }
}

# ---------- 编译器 ----------
$Ahk2Exe = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$BaseX64 = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$BaseX86 = "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
$BaseExe = if ($Arch -eq "x86") { $BaseX86 } else { $BaseX64 }

if ($WantRmt -or $WantWork) {
    foreach ($p in @($Ahk2Exe, $BaseExe)) {
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Err "找不到编译器：$p"
            Write-Host "  请安装 AutoHotkey v2（含编译器），或修改本脚本顶部的默认路径。" -ForegroundColor Yellow
            exit 1
        }
    }
}

# ---------- 版本号 ----------
$Version = ""
$rmtAhk = Join-Path $Root "RMT.ahk"
if (($WantRmt -or $WantWork) -and (Test-Path -LiteralPath $rmtAhk)) {
    $content = Get-Content -LiteralPath $rmtAhk -Raw
    if ($content -match 'global RMT_VERSION\s*:=\s*"([^"]+)"') { $Version = $matches[1] }
}
if (($WantRmt -or $WantWork) -and -not $Version) {
    Write-Err "无法从 RMT.ahk 读取 RMT_VERSION"
    exit 1
}

$OutDir = $Root
$IconPath = Join-Path $Root "Images\Soft\rabit.ico"
if (-not (Test-Path -LiteralPath $IconPath)) {
    Write-Warn "未找到图标 $IconPath，改为不写图标"
    $IconPath = ""
}

# ---------- 结束本项目目录内的实例 ----------
function Stop-ProjectProcess {
    param([string[]]$Names)
    $killed = 0
    foreach ($n in $Names) {
        Get-Process -Name $n -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                try { $_.Kill(); $killed++; Write-Host "  已结束: $($_.Path)" -ForegroundColor Gray } catch { }
            }
    }
    if ($killed -gt 0) { Start-Sleep -Milliseconds 400 }
    return $killed
}

# ---------- 清理 ----------
if ($hasClean) {
    Write-Step "清理目录（$CleanScope）"
    $cleanDirs = @()
    if ($CleanScope -eq "log" -or $CleanScope -eq "all") { $cleanDirs += (Join-Path $Root "Log") }
    if ($CleanScope -eq "setting" -or $CleanScope -eq "all") { $cleanDirs += (Join-Path $Root "Setting") }

    foreach ($dir in $cleanDirs) {
        if (-not (Test-Path -LiteralPath $dir)) {
            Write-Host "  跳过（不存在）：$dir" -ForegroundColor Gray
            continue
        }
        $errMsg = ""
        try {
            Remove-Item -LiteralPath $dir -Recurse -Force
        } catch {
            $errMsg = $_.Exception.Message
        }
        if ($errMsg -ne "") {
            # 多半是正在运行的实例占着 Log\System.log，结束后占用进程再试一次
            Write-Warn "删除被占用，结束本项目目录内的实例后重试"
            $null = Stop-ProjectProcess -Names @("RMTv*", "Work")
            Start-Sleep -Milliseconds 200
            try {
                Remove-Item -LiteralPath $dir -Recurse -Force
                $errMsg = ""
            } catch {
                Write-Err "删除失败：$dir（$($_.Exception.Message)）"
                Write-Host "  可能还有其它进程占用，或需要管理员权限。" -ForegroundColor Yellow
                exit 1
            }
        }
        Write-Ok "已删除 $dir"
    }
    if ($CleanScope -eq "all") {
        Write-Host "  提示：clean 会连 Setting（配置方案/宏/变量）一起删；只删日志用 clean log" -ForegroundColor DarkGray
    }
}

# ---------- 编译 ----------
function Stop-OwnerIfLocked([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = [IO.Path]::GetFullPath($Path)
    try {
        $fs = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $fs.Close()
        return   # 没被占用
    } catch { }
    $name = [IO.Path]::GetFileNameWithoutExtension($full)
    $n = Stop-ProjectProcess -Names @($name)
    if ($n -eq 0) { Write-Warn "$full 被占用，但没有找到本项目目录内的进程" }
}

function Compile([string]$AhkFile, [string]$OutputExe, [string]$Name) {
    if (-not (Test-Path -LiteralPath $AhkFile)) {
        Write-Err "找不到脚本：$AhkFile"
        return $false
    }
    Stop-OwnerIfLocked $OutputExe
    if (Test-Path -LiteralPath $OutputExe) {
        Remove-Item -LiteralPath $OutputExe -Force -ErrorAction SilentlyContinue
    }

    $exeArgs = @("/in", "`"$AhkFile`"", "/base", "`"$BaseExe`"", "/out", "`"$OutputExe`"", "/silent")
    if ($IconPath) {
        $exeArgs = @("/in", "`"$AhkFile`"", "/icon", "`"$IconPath`"", "/base", "`"$BaseExe`"", "/out", "`"$OutputExe`"", "/silent")
    }

    $logOut = Join-Path $env:TEMP "rmt-build-$Name.out.log"
    $logErr = Join-Path $env:TEMP "rmt-build-$Name.err.log"
    Remove-Item -LiteralPath $logOut, $logErr -Force -ErrorAction SilentlyContinue
    # 用 cmd 重定向而不是 Start-Process：本机环境变量里若同时存在 HTTPS_PROXY / https_proxy
    # 这类只差大小写的键，Start-Process 会因字典冲突直接抛异常。
    $cmdLine = "`"$Ahk2Exe`" $($exeArgs -join ' ') > `"$logOut`" 2> `"$logErr`""
    & $env:ComSpec /c $cmdLine | Out-Null
    $code = $LASTEXITCODE

    if ($code -ne 0 -or -not (Test-Path -LiteralPath $OutputExe)) {
        Write-Err "$Name 编译失败（退出码 $code）"
        foreach ($log in @($logErr, $logOut)) {
            if ((Test-Path -LiteralPath $log) -and (Get-Item $log).Length -gt 0) {
                Get-Content -LiteralPath $log | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
            }
        }
        return $false
    }

    $size = [math]::Round((Get-Item -LiteralPath $OutputExe).Length / 1MB, 2)
    Write-Ok "$Name -> $OutputExe ($size MB)"
    return $true
}

$failed = $false
$stamp = Get-Date -Format "HH:mm:ss"

if ($WantRmt) {
    Write-Step "编译主程序 RMTv$Version.exe ($Arch)"
    if (-not (Compile -AhkFile $rmtAhk -OutputExe (Join-Path $OutDir "RMTv$Version.exe") -Name "主程序")) {
        $failed = $true
    }
}

if ($WantWork) {
    Write-Step "编译 Worker Work.exe ($Arch)"
    $threadDir = Join-Path $OutDir "Thread"
    if (-not (Test-Path -LiteralPath $threadDir)) {
        New-Item -ItemType Directory -Path $threadDir -Force | Out-Null
    }
    if (-not (Compile -AhkFile (Join-Path $Root "Thread\Work.ahk") -OutputExe (Join-Path $threadDir "Work.exe") -Name "Worker")) {
        $failed = $true
    }
}

# ---------- 结果 ----------
Write-Host ""
if ($failed) {
    Write-Host "[$stamp] 编译未全部成功" -ForegroundColor Red
} elseif (-not ($WantRmt -or $WantWork)) {
    Write-Host "[$stamp] 清理完成（未编译）" -ForegroundColor Green
} else {
    Write-Host "[$stamp] 编译完成：$OutDir" -ForegroundColor Green
}

exit $(if ($failed) { 1 } else { 0 })
