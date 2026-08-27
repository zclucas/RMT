<#
.SYNOPSIS
    RMT VoiceDll 一键编译部署脚本 (MSVC) — 完全自包含版
.DESCRIPTION
    Plugins\Voice 自包含构建布局：
      src\           源码（VoiceDll.cpp + g2p_data.h）
      x64\           运行时产物（VoiceDll.dll + 依赖 DLL，64 位）
      x86\           运行时产物（VoiceDll.dll + 依赖 DLL，32 位）
      models\kws\    KWS 模型（跨架构共享）
      third_party\   依赖下载缓存（git 忽略）
      tools\         测试工具（VoiceTest.exe / zh_4.wav）
    sherpa-onnx 依赖库与 KWS 模型由本脚本自动下载到 third_party\ 下，
    除 MSVC 构建工具外，不依赖任何外部路径。
    支持 x64 / x86 双架构，按架构部署到 x64\ 或 x86\。
.EXAMPLE
    .\buildDll.ps1            ; 默认 x64：一键下载依赖 + 编译 + 部署
    .\buildDll.ps1 -Arch x86  ; 编译 x86 版到 x86\
    .\buildDll.ps1 -NoPause   ; 编译后不等待按键（CI 用）
.PARAMETER Arch
    目标架构: x86 或 x64，默认 x64
.PARAMETER NoPause
    结束后不等待按键
#>

param(
    [ValidateSet("x86", "x64")]
    [string]$Arch = "x64",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
# 本目录 = Plugins\Voice
$VoiceDir = $PSScriptRoot

# ==================== 版本常量（升级时只改这里） ====================
$SherpaVer   = "v1.13.6"
$SherpaPkg   = "sherpa-onnx-v1.13.6-win-$Arch-shared-MD-Release"
$ModelName   = "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
# 只取 chunk-16 组模型，避免 glob 歧义
$ModelChunk  = "chunk-16-left-64"
$SherpaUrl   = "https://github.com/k2-fsa/sherpa-onnx/releases/download/$SherpaVer/$SherpaPkg.tar.bz2"
$ModelUrl    = "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$ModelName.tar.bz2"

# ==================== 目录 ====================
# 依赖下载解压区（git 忽略）
$DepDir     = Join-Path $VoiceDir "third_party"
# tar.bz2 缓存
$DlDir      = Join-Path $DepDir "downloads"
$SherpaDir  = Join-Path $DepDir $SherpaPkg
# 按架构分编译输出目录，避免 x86/x64 中间产物互踩
$BuildDir   = Join-Path $DepDir ("out_" + $Arch)
# 运行时目录（按架构：x64\ 与 x86\ 并列在插件根）
$RunDir     = Join-Path $VoiceDir $Arch
# 运行时模型目录（跨架构共享）
$RunModelDir = Join-Path $VoiceDir "models\kws"
New-Item -ItemType Directory -Force -Path $DlDir, $SherpaDir, $BuildDir, $RunDir, $RunModelDir | Out-Null

# 源码在 src\ 子目录
$Src      = Join-Path $VoiceDir "src\VoiceDll.cpp"
$G2pH     = Join-Path $VoiceDir "src\g2p_data.h"
# 部署目标：$Arch\VoiceDll.dll
$OutDll   = Join-Path $RunDir "VoiceDll.dll"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RMT VoiceDll 一键编译部署 (自包含 $Arch)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ==================== 检查源码 ====================
if (-not (Test-Path $Src)) { Write-Host "[错误] 未找到源码: $Src" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
if (-not (Test-Path $G2pH)) { Write-Host "[错误] 未找到 G2P 表: $G2pH" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
Write-Host "[OK] 源码: $Src" -ForegroundColor Green
Write-Host "[OK] G2P表: $G2pH" -ForegroundColor Green

# ==================== 下载依赖（有缓存则跳过） ====================
# GitHub 下载代理前缀（加速国内下载；留空则直连 GitHub）
$ProxyPrefix = "https://gh-proxy.org/"

function Invoke-Download($Url, $Dest, $Label) {
    if (Test-Path $Dest) {
        $sz = (Get-Item $Dest).Length
        if ($sz -gt 1MB) { Write-Host "[OK] $Label 已缓存: $Dest ($([math]::Round($sz/1MB,1)) MB)" -ForegroundColor Green; return }
        Remove-Item $Dest -Force
    }
    # 走代理：gh-proxy 用法是 前缀 + 完整原 URL
    $dlUrl = if ($ProxyPrefix -ne "") { $ProxyPrefix + $Url } else { $Url }
    Write-Host "[下载] $Label ..." -ForegroundColor Yellow
    Write-Host "       $dlUrl" -ForegroundColor DarkGray
    # 优先 curl（-k --ssl-no-revoke 绕过代理吊销检查）；失败回退 Invoke-WebRequest
    $ok = $false
    try {
        & curl.exe -k --ssl-no-revoke -L --fail --silent --show-error -o $Dest $dlUrl 2>$null
        if ($LASTEXITCODE -eq 0 -and (Get-Item $Dest).Length -gt 1MB) { $ok = $true }
    } catch {}
    if (-not $ok) {
        Write-Host "       curl 失败，改用 Invoke-WebRequest ..." -ForegroundColor DarkGray
        try {
            Invoke-WebRequest -Uri $dlUrl -OutFile $Dest -SkipCertificateCheck -UseBasicParsing -TimeoutSec 300
            if ((Get-Item $Dest).Length -gt 1MB) { $ok = $true }
        } catch {
            Write-Host "[错误] 下载失败: $($_.Exception.Message)" -ForegroundColor Red
            if (-not $NoPause) { Read-Host "按回车退出" }
            exit 1
        }
    }
    Write-Host "[OK] $Label 下载完成 ($([math]::Round((Get-Item $Dest).Length/1MB,1)) MB)" -ForegroundColor Green
}

function Expand-TarBz2($Tar, $Target) {
    $mark = Join-Path $Target (".ok_" + [IO.Path]::GetFileNameWithoutExtension($Tar))
    if (Test-Path $mark) { return }
    Write-Host "[解压] $([IO.Path]::GetFileName($Tar)) ..." -ForegroundColor Yellow
    & tar.exe -xjf $Tar -C $Target 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 解压失败（需要 Windows 10 1803+ 自带 tar）" -ForegroundColor Red
        if (-not $NoPause) { Read-Host "按回车退出" }
        exit 1
    }
    Set-Content -Path $mark -Value "done"
}

# --- sherpa-onnx 库包 ---
$sherpaTar = Join-Path $DlDir "$SherpaPkg.tar.bz2"
Invoke-Download $SherpaUrl $sherpaTar "sherpa-onnx 库包"
Expand-TarBz2 $sherpaTar $DepDir
$Inc    = Join-Path $SherpaDir "include"
$LibDir = Join-Path $SherpaDir "lib"
$CapiLib = Join-Path $LibDir "sherpa-onnx-c-api.lib"
if (-not (Test-Path $CapiLib)) { Write-Host "[错误] 解压后未找到 sherpa-onnx-c-api.lib: $CapiLib" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
Write-Host "[OK] sherpa 依赖: $SherpaDir" -ForegroundColor Green

# --- KWS 模型包 ---
$modelTar = Join-Path $DlDir "$ModelName.tar.bz2"
Invoke-Download $ModelUrl $modelTar "KWS 中文模型"
Expand-TarBz2 $modelTar $DepDir
$modelSrcDir = Join-Path $DepDir $ModelName
if (-not (Test-Path $modelSrcDir)) { Write-Host "[错误] 解压后未找到模型目录: $modelSrcDir" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
Write-Host "[OK] 模型源: $modelSrcDir" -ForegroundColor Green

# ==================== 查找 MSVC 编译器（按架构选 vcvars32/64） ====================
$vcvarsName = if ($Arch -eq "x86") { "vcvars32.bat" } else { "vcvars64.bat" }
$vcvarsPaths = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio",
    "${env:ProgramFiles}\Microsoft Visual Studio"
)
$vsVersions = @(18, 17, 16, 15, "2019", "2017")
$vsEditions = @("BuildTools", "Community", "Professional")
$VcVarsBat = $null
foreach ($vsBase in $vcvarsPaths) {
    foreach ($ver in $vsVersions) {
        foreach ($edition in $vsEditions) {
            $candidate = Join-Path $vsBase "$ver\$edition\VC\Auxiliary\Build\$vcvarsName"
            if (Test-Path $candidate) { $VcVarsBat = $candidate; break }
        }
        if ($VcVarsBat) { break }
    }
    if ($VcVarsBat) { break }
}
if (-not $VcVarsBat) {
    Write-Host "[错误] 未找到 MSVC $Arch 编译器（$vcvarsName）！" -ForegroundColor Red
    Write-Host "请安装 Build Tools 并勾选「使用 C++ 的桌面开发」($Arch 支持)" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
Write-Host "[OK] MSVC 编译器已就绪 ($Arch)" -ForegroundColor Green

# ==================== 检查运行时 DLL 是否被占用 ====================
if (Test-Path $OutDll) {
    try {
        $fs = [System.IO.File]::Open($OutDll, 'Open', 'Read', 'None')
        $fs.Close()
        Write-Host "[OK] 目标 VoiceDll.dll 未被占用" -ForegroundColor Green
    } catch {
        Write-Host "[警告] 目标 VoiceDll.dll 正被占用（RMT 可能正在运行）！" -ForegroundColor Yellow
        Write-Host "  请先关闭 RMT 再重新运行本脚本" -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host "按回车退出" }
        exit 1
    }
}

# ==================== 编译 + 链接 ====================
$clBat = Join-Path $BuildDir "_build_cl.bat"
$cl = @"
chcp 65001 >nul
call "$VcVarsBat" >nul 2>&1
if errorlevel 1 exit /b 100
cl /nologo /O2 /MD /EHsc /W3 /utf-8 /DWIN32_LEAN_AND_MEAN /DNDEBUG /DUNICODE /D_UNICODE ^
   /I"$Inc" ^
   "$Src" ^
   "$CapiLib" ^
   ole32.lib avrt.lib uuid.lib ^
   /link /DLL /MACHINE:$($Arch.ToUpper()) /OUT:"$BuildDir\VoiceDll.dll"
if errorlevel 1 exit /b 101
exit /b 0
"@
Set-Content -Path $clBat -Value $cl -Encoding ASCII

Write-Host ""
Write-Host "[1/3] 正在编译 VoiceDll.cpp ($Arch) ..." -ForegroundColor Green
& cmd.exe /c "`"$clBat`""
$compileExit = $LASTEXITCODE
Remove-Item $clBat -ErrorAction SilentlyContinue
if ($compileExit -ne 0 -or -not (Test-Path "$BuildDir\VoiceDll.dll")) {
    Write-Host "[错误] 编译失败！exit=$compileExit" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
Write-Host "[OK] 编译成功: $BuildDir\VoiceDll.dll" -ForegroundColor Green

# ==================== 部署运行时资产 ====================
Write-Host ""
Write-Host "[2/3] 组装运行时依赖 ..." -ForegroundColor Green
# 依赖 DLL（sherpa c-api + onnxruntime）→ $Arch\（与 VoiceDll.dll 同目录）
foreach ($depDll in @("sherpa-onnx-c-api.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll")) {
    $srcDll = Join-Path $LibDir $depDll
    if (-not (Test-Path $srcDll)) { Write-Host "[警告] 依赖缺失: $srcDll（跳过）" -ForegroundColor Yellow; continue }
    Copy-Item $srcDll (Join-Path $RunDir $depDll) -Force
}
Write-Host "[OK] 依赖 DLL 已组装到 $Arch" -ForegroundColor Green

# 模型（chunk-16 组 4 个文件）→ models\kws（跨架构共享，缺才复制）
$modelFiles = @(
    "decoder-epoch-13-avg-2-$ModelChunk.onnx",
    "encoder-epoch-13-avg-2-$ModelChunk.int8.onnx",
    "joiner-epoch-13-avg-2-$ModelChunk.int8.onnx",
    "tokens.txt"
)
foreach ($mf in $modelFiles) {
    $srcMf = Join-Path $modelSrcDir $mf
    $dstMf = Join-Path $RunModelDir $mf
    if (-not (Test-Path $srcMf)) { Write-Host "[警告] 模型文件缺失: $srcMf（跳过）" -ForegroundColor Yellow; continue }
    if (-not (Test-Path $dstMf)) { Copy-Item $srcMf $dstMf -Force }
}
Write-Host "[OK] 模型已就位: models\kws" -ForegroundColor Green

Write-Host ""
Write-Host "[3/3] 部署 VoiceDll.dll ..." -ForegroundColor Green
Copy-Item -Path "$BuildDir\VoiceDll.dll" -Destination $OutDll -Force
$dllSize = [math]::Round((Get-Item $OutDll).Length / 1KB, 1)
Write-Host "[OK] 部署完成: $OutDll ($dllSize KB)" -ForegroundColor Green

# 清理中间产物（仅保留 DLL）
Remove-Item "$BuildDir\VoiceDll.obj", "$BuildDir\VoiceDll.lib", "$BuildDir\VoiceDll.exp" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VoiceDll 编译部署成功！（$Arch 自包含）" -ForegroundColor Green
Write-Host "  产物: $Arch\VoiceDll.dll" -ForegroundColor White
Write-Host "  依赖与模型缓存: $DepDir（git 已忽略）" -ForegroundColor White
if ($Arch -eq "x86") {
    Write-Host "  注意: x86 版需用 AutoHotkey32.exe 运行 RMT 才能加载" -ForegroundColor Yellow
} else {
    Write-Host "  重启 RMT 后生效" -ForegroundColor White
}
Write-Host "========================================" -ForegroundColor Cyan

if (-not $NoPause) { Read-Host "按回车退出" }
