[CmdletBinding()]
param(
    [string]$DestinationRoot = ".tools\WebView2Runtime\Fixed",
    [string]$DownloadRoot = "",
    [ValidateSet("x64", "x86")]
    [string[]]$Architectures = @("x64", "x86"),
    [string]$Version = "latest",
    [switch]$KeepDownloads
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$WebView2Page = "https://developer.microsoft.com/en-us/microsoft-edge/webview2/"

function Resolve-PathForCreate {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Get-DefaultDownloadRoot {
    if ($env:RUNNER_TEMP) {
        return (Join-Path $env:RUNNER_TEMP "WebView2FixedRuntime")
    }
    return (Join-Path ([System.IO.Path]::GetTempPath()) "RMT-WebView2FixedRuntime")
}

function Get-WebView2FixedRuntimeBuilds {
    Write-Host "Reading WebView2 download page..."
    $html = (Invoke-WebRequest -Uri $WebView2Page -UseBasicParsing).Content
    $urlMatches = [regex]::Matches(
        $html,
        'https:[^"]+?Microsoft\.WebView2\.FixedVersionRuntime\.[^"]+?\.(x64|x86|arm64)\.cab'
    )

    $items = @()
    foreach ($match in $urlMatches) {
        $url = $match.Value -replace '\\u002F', '/'
        if ($url -match 'FixedVersionRuntime\.(?<version>[0-9.]+)\.(?<arch>x64|x86|arm64)\.cab') {
            $items += [pscustomobject]@{
                Version = [version]$matches["version"]
                VersionText = $matches["version"]
                Architecture = $matches["arch"]
                Url = $url
            }
        }
    }

    if ($items.Count -eq 0) {
        throw "Unable to find Fixed Version Runtime downloads on $WebView2Page"
    }
    return $items
}

function Select-WebView2FixedRuntimeBuilds {
    param(
        [object[]]$Builds,
        [string[]]$RequiredArchitectures,
        [string]$RequestedVersion
    )

    if ($RequestedVersion -ne "latest") {
        $selected = @($Builds | Where-Object { $_.VersionText -eq $RequestedVersion })
        foreach ($arch in $RequiredArchitectures) {
            if (-not ($selected | Where-Object { $_.Architecture -eq $arch })) {
                throw "WebView2 Fixed Runtime $RequestedVersion does not include $arch on the download page."
            }
        }
        return $selected
    }

    $groups = @($Builds | Group-Object VersionText |
        Sort-Object { [version]$_.Name } -Descending)
    foreach ($group in $groups) {
        $groupItems = @($group.Group)
        $hasAllArchitectures = $true
        foreach ($arch in $RequiredArchitectures) {
            if (-not ($groupItems | Where-Object { $_.Architecture -eq $arch })) {
                $hasAllArchitectures = $false
                break
            }
        }
        if ($hasAllArchitectures) {
            return $groupItems
        }
    }

    throw "Unable to find a WebView2 Fixed Runtime version with: $($RequiredArchitectures -join ', ')"
}

$destinationRootPath = Resolve-PathForCreate $DestinationRoot
$downloadRootPath = if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    Get-DefaultDownloadRoot
}
else {
    Resolve-PathForCreate $DownloadRoot
}

New-Item -ItemType Directory -Path $destinationRootPath, $downloadRootPath -Force | Out-Null

$builds = Get-WebView2FixedRuntimeBuilds
$selectedBuilds = Select-WebView2FixedRuntimeBuilds `
    -Builds $builds `
    -RequiredArchitectures $Architectures `
    -RequestedVersion $Version

$selectedVersion = ($selectedBuilds | Select-Object -First 1).VersionText
Write-Host "Selected WebView2 Fixed Runtime $selectedVersion"

foreach ($arch in $Architectures) {
    $build = $selectedBuilds | Where-Object { $_.Architecture -eq $arch } | Select-Object -First 1
    $cabPath = Join-Path $downloadRootPath (Split-Path $build.Url -Leaf)
    $archDestination = Join-Path $destinationRootPath $arch

    if (Test-Path -LiteralPath $archDestination) {
        Remove-Item -LiteralPath $archDestination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $archDestination -Force | Out-Null

    Write-Host "Downloading $arch runtime..."
    Invoke-WebRequest -Uri $build.Url -OutFile $cabPath -UseBasicParsing

    Write-Host "Expanding $arch runtime..."
    & expand.exe $cabPath "-F:*" $archDestination | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "expand.exe failed for $cabPath with exit code $LASTEXITCODE"
    }

    $runtimeExe = Get-ChildItem -LiteralPath $archDestination -Recurse -Filter "msedgewebview2.exe" |
        Select-Object -First 1
    if (-not $runtimeExe) {
        throw "Unable to find msedgewebview2.exe after expanding $arch runtime."
    }
    Write-Host "$arch runtime ready: $($runtimeExe.FullName)"
}

if (-not $KeepDownloads -and (Test-Path -LiteralPath $downloadRootPath)) {
    Remove-Item -LiteralPath $downloadRootPath -Recurse -Force
}
