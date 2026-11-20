<#
.SYNOPSIS
    单独下载 RMT「本地翻译」所需的 GGUF 模型。

.DESCRIPTION
    Index-Translate-2B 的 Q4_K_M GGUF 约 1.3 GB，不进仓库也不进发行包。
    模型落地到 Plugins\Translate\models\，翻译指令执行时自动检测；
    缺失时指令会给出明确错误，先跑本脚本补齐。

    下载源顺序：ModelScope（国内快）→ HuggingFace（直连）。

.PARAMETER Model
    模型文件名。默认 Index-Translate-2B.Q4_K_M.gguf。
    9B 档位（Index-Translate-9B.Q4_K_M.gguf，约 5.9 GB）需要更高配置，按需指定。

.PARAMETER Force
    目标已存在时也强制重新下载。

.EXAMPLE
    .\GetTranslateModel.ps1
    .\GetTranslateModel.ps1 -Model Index-Translate-9B.Q4_K_M.gguf
#>
param(
    [string]$Model = 'Index-Translate-2B.Q4_K_M.gguf',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$TransDir  = $PSScriptRoot
$TargetDir = Join-Path $TransDir 'models'
$DlDir     = Join-Path $TransDir 'third_party\downloads'

# 2B / 9B 是两个独立仓库；-Model 按 9B 命中 9B 仓库，其余落 2B
$Repo    = if ($Model -match '-9B') { 'IndexTeam/Index-Translate-9B-GGUF' } else { 'IndexTeam/Index-Translate-2B-GGUF' }
$Urls    = @(
    "https://modelscope.cn/models/$Repo/resolve/master/$Model",
    "https://huggingface.co/$Repo/resolve/main/$Model"
)
# 小于下限视为半包：2B Q4_K_M 实际 1312164352 字节；9B 约 5.9 GB
$MinBytes = if ($Model -match '-9B') { 5000MB } else { 1200MB }

Write-Host '========================================' -ForegroundColor Cyan
Write-Host "  RMT 本地翻译模型下载：$Model" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

New-Item -ItemType Directory -Force -Path $TargetDir, $DlDir | Out-Null

$target = Join-Path $TargetDir $Model
if ((Test-Path $target) -and -not $Force) {
    $size = (Get-Item $target).Length
    if ($size -ge $MinBytes) {
        Write-Host "[OK] 模型已存在: $target ($([math]::Round($size/1GB,2)) GB)" -ForegroundColor Green
        Read-Host '按回车退出'
        exit 0
    }
    Write-Host "[警告] 已有文件不完整（$([math]::Round($size/1MB,1)) MB），重新下载" -ForegroundColor Yellow
}

$part = "$target.$([guid]::NewGuid()).part"
$ok = $false
foreach ($url in $Urls) {
    Write-Host "[下载] $url" -ForegroundColor Yellow
    try {
        & curl.exe -fL --ssl-no-revoke --retry 3 --retry-delay 2 --max-time 7200 -C - -o $part $url
        if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
        if ((Get-Item $part).Length -lt $MinBytes) { throw '下载文件不完整' }
        Move-Item $part $target -Force
        $ok = $true
        break
    } catch {
        Write-Warning "$url — $($_.Exception.Message)"
        if (Test-Path $part) { Remove-Item $part -Force }
    }
}

if (-not $ok) {
    Write-Host '[错误] 全部下载源失败。可手动从 https://huggingface.co/IndexTeam/Index-Translate-2B-GGUF 下载后放到 models\ 目录。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

Write-Host ''
Write-Host "[OK] 完成: $target ($([math]::Round((Get-Item $target).Length/1GB,2)) GB)" -ForegroundColor Green
Write-Host '重启 RMT 后翻译指令即可使用本地引擎。' -ForegroundColor White
Read-Host '按回车退出'
