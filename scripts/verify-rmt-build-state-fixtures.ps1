[CmdletBinding()]
param(
    [string]$AhkExe = "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FixturePath = Join-Path $RepoRoot "scripts\fixtures\rmt-build-state-fixtures.ahk"

if (-not (Test-Path -LiteralPath $AhkExe)) {
    throw "AutoHotkey executable not found: $AhkExe"
}

if (-not (Test-Path -LiteralPath $FixturePath)) {
    throw "Missing RmtBuildState fixture script: scripts\fixtures\rmt-build-state-fixtures.ahk"
}

Push-Location $RepoRoot
try {
    & $AhkExe "/ErrorStdOut=UTF-8" $FixturePath
    $lastExitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
    $exitCode = if ($null -eq $lastExitCodeVar) { 0 } else { [int]$lastExitCodeVar.Value }
    if ($exitCode -ne 0) {
        throw "RmtBuildState fixture compatibility failed with exit code $exitCode"
    }
}
finally {
    Pop-Location
}
