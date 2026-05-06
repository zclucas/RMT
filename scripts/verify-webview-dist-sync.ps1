[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DistRelativePath = "WebViewApp/dist"

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    throw "Git is required to verify WebViewApp/dist sync."
}

Push-Location $RepoRoot
try {
    & git rev-parse --is-inside-work-tree | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify WebViewApp/dist sync outside a Git worktree."
    }

    $changedFiles = @(& git diff --name-only -- $DistRelativePath)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read WebViewApp/dist working tree changes."
    }

    $untrackedFiles = @(& git ls-files --others --exclude-standard -- $DistRelativePath)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read WebViewApp/dist untracked files."
    }

    $dirtyFiles = @($changedFiles + $untrackedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dirtyFiles.Count -gt 0) {
        $fileList = ($dirtyFiles | Sort-Object -Unique | ForEach-Object { "  $_" }) -join "`n"
        throw "WebViewApp/dist is not synced with the current source build. Run npm.cmd run build in WebViewApp, then stage or commit the generated assets:`n$fileList"
    }
}
finally {
    Pop-Location
}

Write-Host "WebViewApp/dist is synced with the tracked generated assets."
