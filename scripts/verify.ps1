[CmdletBinding()]
param(
    [string]$AhkExe = "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe",
    [switch]$SkipAhkValidate,
    [switch]$SkipBridgeContract,
    [switch]$SkipWebViewWrapperCheck,
    [switch]$SkipWebBuild,
    [switch]$SkipWhitespaceCheck
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$WebViewApp = Join-Path $RepoRoot "WebViewApp"

function Write-Step {
    param([string]$Name)
    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
}

function Invoke-Native {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory = $RepoRoot
    )

    Write-Step $Name
    Push-Location $WorkingDirectory
    try {
        & $FilePath @ArgumentList
        $lastExitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
        $exitCode = if ($null -eq $lastExitCodeVar) { 0 } else { [int]$lastExitCodeVar.Value }
        if ($exitCode -ne 0) {
            throw "$Name failed with exit code $exitCode"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$Check
    )

    Write-Step $Name
    & $Check
}

Invoke-Check "Version consistency" {
    $uiUtilPath = Join-Path $RepoRoot "Main\UIUtil.ahk"
    $fallbackStatePath = Join-Path $RepoRoot "WebViewApp\src\fallbackState.ts"
    $packagePath = Join-Path $RepoRoot "WebViewApp\package.json"

    $uiUtil = Get-Content -LiteralPath $uiUtilPath -Raw
    if ($uiUtil -notmatch 'RMT_WEBVIEW_VERSION\s*:=\s*"RMTv(?<version>\d+\.\d+\.\d+)"') {
        throw "Unable to read RMT_WEBVIEW_VERSION from Main\UIUtil.ahk"
    }
    $ahkVersion = $matches["version"]

    $packageVersion = (Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json).version
    if ($ahkVersion -ne $packageVersion) {
        throw "Version mismatch: Main\UIUtil.ahk has $ahkVersion, WebViewApp\package.json has $packageVersion"
    }

    $bridge = Get-Content -LiteralPath $fallbackStatePath -Raw
    $expectedBridgeVersion = 'version:\s*"RMTv' + [regex]::Escape($ahkVersion) + '"'
    if ($bridge -notmatch $expectedBridgeVersion) {
        throw "Version mismatch: WebViewApp\src\fallbackState.ts fallback is not RMTv$ahkVersion"
    }

    Write-Host "RMTv$ahkVersion"
}

if (-not $SkipBridgeContract) {
    Invoke-Native "WebView bridge contract" "node" @("scripts\verify-webview-contract.mjs")
}

if (-not $SkipWebViewWrapperCheck) {
    Invoke-Native "WebView2 wrapper check" "powershell" @("-ExecutionPolicy", "Bypass", "-File", "scripts\verify-webview2-wrapper.ps1")
}

if (-not $SkipAhkValidate) {
    if (-not (Test-Path -LiteralPath $AhkExe)) {
        throw "AutoHotkey executable not found: $AhkExe"
    }
    Invoke-Native "AHK validate" $AhkExe @("/ErrorStdOut=UTF-8", "/Validate", ".\RMT.ahk")
}

if (-not $SkipWebBuild) {
    Invoke-Native "React/TypeScript build" "npm.cmd" @("run", "build") $WebViewApp

    Invoke-Check "WebView dist assets" {
        $distPath = Join-Path $WebViewApp "dist"
        $assetsPath = Join-Path $distPath "assets"
        if (-not (Test-Path -LiteralPath (Join-Path $distPath "index.html"))) {
            throw "Missing WebViewApp\dist\index.html"
        }
        if (-not (Get-ChildItem -LiteralPath $assetsPath -Filter "*.js" -File -ErrorAction SilentlyContinue)) {
            throw "Missing WebViewApp\dist\assets JavaScript bundle"
        }
        if (-not (Get-ChildItem -LiteralPath $assetsPath -Filter "*.css" -File -ErrorAction SilentlyContinue)) {
            throw "Missing WebViewApp\dist\assets CSS bundle"
        }
        Write-Host "dist/index.html and assets are present"
    }
}

if (-not $SkipWhitespaceCheck) {
    Invoke-Native "Git whitespace check" "git" @("diff", "--check")
}

Write-Host ""
Write-Host "Verification passed." -ForegroundColor Green
