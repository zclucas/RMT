<#
.SYNOPSIS
    单独下载 RMT「语音转文字」所需的本地流式识别模型。

.DESCRIPTION
    GitHub 单文件上限 100MB，而 x-asr 的 encoder.int8.onnx 约 149MB，
    无法随仓库分发，因此模型改为按需下载（本脚本 / RMT 窗口内按钮两条途径）。

    模型落地到 Plugins\Voice\models\stt_stream\，RMT 会自动检测该目录；
    缺失时 STT 窗口会显示「下载识别模型」按钮。

.PARAMETER Chunk
    流式 chunk 档位：160ms（最低延迟）/ 480ms（默认，均衡）/ 960ms / 1920ms（最准）。
    越大越准，首字延迟越高。切换档位会重新下载对应模型并覆盖。

.PARAMETER Force
    目标已存在时也强制重新下载。

.PARAMETER NoProxy
    不走 gh-proxy 加速，直连 GitHub（国内网络通常很慢）。

.EXAMPLE
    .\GetSttModel.ps1
    .\GetSttModel.ps1 -Chunk 960ms
#>
param(
    [ValidateSet('160ms', '480ms', '960ms', '1920ms')]
    [string]$Chunk   = '480ms',
    [switch]$Force,
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'

$VoiceDir   = $PSScriptRoot
$DepDir     = Join-Path $VoiceDir 'third_party'
$DlDir      = Join-Path $DepDir 'downloads'
$TargetDir  = Join-Path $VoiceDir 'models\stt_stream'

$PkgName = "sherpa-onnx-x-asr-$Chunk-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-05"
$BaseUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models'
$Url     = "$BaseUrl/$PkgName.tar.bz2"
$Proxy   = if ($NoProxy) { '' } else { 'https://gh-proxy.org/' }

# 包内实际文件名（decoder 不带 .int8 后缀，别写成 decoder.int8.onnx）
$Files = @('encoder.int8.onnx', 'decoder.onnx', 'joiner.int8.onnx', 'tokens.txt', 'bpe.model')

Write-Host '========================================' -ForegroundColor Cyan
Write-Host "  RMT STT 模型下载（chunk = $Chunk）" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

New-Item -ItemType Directory -Force -Path $DlDir, $TargetDir | Out-Null

# --- 已存在则跳过 ---
if (-not $Force) {
    $allExist = $true
    foreach ($f in $Files) {
        if (-not (Test-Path (Join-Path $TargetDir $f))) { $allExist = $false; break }
    }
    if ($allExist) {
        $bytes = (Get-ChildItem $TargetDir | Measure-Object -Property Length -Sum).Sum
        Write-Host "[OK] 模型已就位：$TargetDir（$([math]::Round($bytes/1MB,1)) MB，跳过下载）" -ForegroundColor Green
        Write-Host '     需要换档位或重新拉取请用 -Chunk <档位> 或 -Force' -ForegroundColor DarkGray
        exit 0
    }
}

# --- 下载 ---
$Tar = Join-Path $DlDir "$PkgName.tar.bz2"
if ((Test-Path $Tar) -and ((Get-Item $Tar).Length -lt 1MB)) { Remove-Item $Tar -Force }

if (Test-Path $Tar) {
    Write-Host "[OK] 压缩包已缓存: $Tar ($([math]::Round((Get-Item $Tar).Length/1MB,1)) MB)" -ForegroundColor Green
} else {
    $dlUrl = if ($Proxy -ne '') { $Proxy + $Url } else { $Url }
    Write-Host '[下载] x-asr 流式模型（约 128MB）...' -ForegroundColor Yellow
    Write-Host "       $dlUrl" -ForegroundColor DarkGray

    $ok = $false
    try {
        & curl.exe -k --ssl-no-revoke -L --fail --silent --show-error -o $Tar $dlUrl 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $Tar) -and (Get-Item $Tar).Length -gt 1MB) { $ok = $true }
    } catch {}

    if (-not $ok) {
        Write-Host '       curl 失败，改用 Invoke-WebRequest ...' -ForegroundColor DarkGray
        try {
            Invoke-WebRequest -Uri $dlUrl -OutFile $Tar -SkipCertificateCheck -UseBasicParsing -TimeoutSec 600
            if ((Get-Item $Tar).Length -gt 1MB) { $ok = $true }
        } catch {
            Write-Host "[错误] 下载失败：$($_.Exception.Message)" -ForegroundColor Red
            Write-Host '       可尝试 -NoProxy 直连，或挂代理后重试。' -ForegroundColor DarkGray
            exit 1
        }
    }
    Write-Host "[OK] 下载完成 ($([math]::Round((Get-Item $Tar).Length/1MB,1)) MB)" -ForegroundColor Green
}

# --- 解压 ---
$SrcDir = Join-Path $DepDir $PkgName
if (-not (Test-Path $SrcDir)) {
    Write-Host "[解压] $PkgName.tar.bz2 ..." -ForegroundColor Yellow
    & tar.exe -xjf $Tar -C $DepDir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[错误] 解压失败（需要 Windows 10 1803+ 自带的 tar）' -ForegroundColor Red
        exit 1
    }
}
if (-not (Test-Path $SrcDir)) {
    Write-Host "[错误] 解压后未找到模型目录: $SrcDir" -ForegroundColor Red
    exit 1
}

# --- 部署 ---
# 单个文件失败不中断：目标被占用（如 RMT 正在运行）时其余文件仍要落位，
# 最后统一汇总，避免「复制一半就崩」又看不出是哪个文件出的问题。
$failed = @()
foreach ($f in $Files) {
    $src = Join-Path $SrcDir $f
    $dst = Join-Path $TargetDir $f
    if (-not (Test-Path $src)) {
        $failed += "$f（包内缺失）"
        continue
    }
    # 重试 3 次：文件刚被删除时句柄可能尚未释放，或被安全软件瞬时占用
    $copied = $false
    $lastMsg = ''
    for ($i = 1; $i -le 3; $i++) {
        try {
            Copy-Item $src $dst -Force -ErrorAction Stop
            if (Test-Path $dst) { $copied = $true; break }
        } catch {
            $lastMsg = (($_.Exception.Message -split "`n")[0]).Trim()
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $copied) {
        $failed += "$f（$lastMsg）"
        Write-Host "[警告] 部署失败: $f —— $lastMsg" -ForegroundColor Yellow
    }
}

# --- 校验 ---
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host '[错误] 以下文件未部署成功:' -ForegroundColor Red
    foreach ($x in $failed) { Write-Host "       - $x" -ForegroundColor Red }
    Write-Host '       若提示文件被占用，请先关闭 RMT 再重试。' -ForegroundColor DarkGray
    exit 1
}

$bytes = (Get-ChildItem $TargetDir | Measure-Object -Property Length -Sum).Sum
Write-Host ''
Write-Host "[OK] 模型已就位: $TargetDir（$([math]::Round($bytes/1MB,1)) MB）" -ForegroundColor Green
Write-Host '     重启 RMT 后，工具页 → 打开语音转文字 即可使用。' -ForegroundColor DarkGray
Write-Host '     提示：模型目录建议加入 .gitignore（超 GitHub 100MB 单文件限制）。' -ForegroundColor DarkGray
exit 0
