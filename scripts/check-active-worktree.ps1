[CmdletBinding()]
param(
    [string]$ExpectedDirectoryName = "RMT-zclucas-Dev_UI"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoName = Split-Path -Leaf $RepoRoot
$repoParent = Split-Path -Parent $RepoRoot
$rmtScript = Join-Path $RepoRoot "RMT.ahk"
$distPath = Join-Path $RepoRoot "WebViewApp\dist"
$distIndex = Join-Path $distPath "index.html"
$assetsPath = Join-Path $distPath "assets"

function Write-Status {
    param(
        [string]$Label,
        [string]$Value
    )

    Write-Host ("{0,-18} {1}" -f ($Label + ":"), $Value)
}

function Get-GitBranch {
    Push-Location $RepoRoot
    try {
        $branch = & git branch --show-current 2>$null
        $exitCode = if ($null -eq (Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue)) { 0 } else { $LASTEXITCODE }
        if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
            return "(unknown)"
        }
        return $branch.Trim()
    }
    finally {
        Pop-Location
    }
}

$assetFiles = @()
if (Test-Path -LiteralPath $assetsPath) {
    $assetFiles = @(Get-ChildItem -LiteralPath $assetsPath -File -ErrorAction SilentlyContinue)
}

Write-Host "RMT active worktree check" -ForegroundColor Cyan
Write-Host ""
Write-Status "Repo root" $RepoRoot
Write-Status "Repo folder" $repoName
Write-Status "Git branch" (Get-GitBranch)
Write-Status "RMT entry" $rmtScript
Write-Status "WebView index" $distIndex
Write-Status "WebView assets" ("{0} file(s)" -f $assetFiles.Count)

if (-not (Test-Path -LiteralPath $rmtScript)) {
    throw "Missing RMT.ahk in the current repository root."
}

if (-not (Test-Path -LiteralPath $distIndex)) {
    throw "Missing WebViewApp\dist\index.html. Run npm.cmd run build in WebViewApp."
}

if ($assetFiles.Count -eq 0) {
    throw "Missing WebViewApp\dist\assets files. Run npm.cmd run build in WebViewApp."
}

if ($repoName -ne $ExpectedDirectoryName) {
    Write-Warning "Current folder is '$repoName', expected '$ExpectedDirectoryName' for this maintenance thread."
}

$siblingRmtDirs = @(
    Get-ChildItem -LiteralPath $repoParent -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $RepoRoot -and $_.Name -like "RMT*" } |
        Sort-Object Name
)

if ($siblingRmtDirs.Count -gt 0) {
    Write-Host ""
    Write-Warning "Sibling RMT folders exist. Starting RMT.ahk from those folders may show older UI or stale dist files."
    foreach ($dir in $siblingRmtDirs) {
        Write-Host ("  - {0}" -f $dir.FullName)
    }
}

Write-Host ""
Write-Host "Use this entry for manual checks:" -ForegroundColor Green
Write-Host ("  {0}" -f $rmtScript)
