[CmdletBinding()]
param(
    [string[]]$ReleaseDir = @(),
    [string]$ReleaseRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
function Get-RmtVersion {
    $uiUtilPath = Join-Path $RepoRoot "Main\UIUtil.ahk"
    $content = Get-Content -LiteralPath $uiUtilPath -Raw
    if ($content -notmatch 'RMT_WEBVIEW_VERSION\s*:=\s*"RMTv(?<version>\d+(?:\.\d+){1,2})"') {
        throw "Unable to read RMT_WEBVIEW_VERSION from Main\UIUtil.ahk"
    }

    return $matches["version"]
}

function Resolve-ReleaseDirs {
    param(
        [string[]]$ExplicitDirs,
        [string]$Root,
        [string]$Version
    )

    if ($ExplicitDirs.Count -gt 0) {
        return @($ExplicitDirs | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
    }

    $releaseRootPath = $Root
    if ([string]::IsNullOrWhiteSpace($releaseRootPath)) {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $releaseRootPath = Join-Path (Join-Path $desktop "RMTRelease") "RMTv$Version"
    }

    if (-not (Test-Path -LiteralPath $releaseRootPath)) {
        throw "Missing release root: $releaseRootPath"
    }

    $dirs = @(Get-ChildItem -LiteralPath $releaseRootPath -Directory |
        Where-Object { $_.Name -match '^RMTv.+_x(64|32)(?:_(?:lite|runtime))?$' } |
        ForEach-Object { $_.FullName })

    if ($dirs.Count -eq 0) {
        throw "No packaged release directories found under $releaseRootPath"
    }

    return $dirs
}

function Assert-PathExists {
    param(
        [string]$BaseDir,
        [string]$RelativePath,
        [string]$Description,
        [System.Collections.Generic.List[string]]$Problems
    )

    $fullPath = Join-Path $BaseDir $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        [void]$Problems.Add("Missing ${Description}: $RelativePath")
    }
}

function Assert-GlobExists {
    param(
        [string]$BaseDir,
        [string]$RelativePath,
        [string]$Filter,
        [string]$Description,
        [System.Collections.Generic.List[string]]$Problems
    )

    $fullPath = Join-Path $BaseDir $RelativePath
    $matches = @(Get-ChildItem -LiteralPath $fullPath -Filter $Filter -File -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0) {
        [void]$Problems.Add("Missing ${Description}: $RelativePath\$Filter")
    }
}

function Test-ReleaseDir {
    param(
        [string]$Path,
        [string]$Version
    )

    $releasePath = (Resolve-Path -LiteralPath $Path).Path
    $problems = [System.Collections.Generic.List[string]]::new()
    $expectedExe = "RMTv$Version.exe"

    Assert-PathExists $releasePath $expectedExe "main executable" $problems
    Assert-PathExists $releasePath "Thread\Work1.exe" "worker executable" $problems
    Assert-PathExists $releasePath "Lang" "language directory" $problems
    Assert-PathExists $releasePath "Plugins\WebViewToo\Lib\WebViewToo.ahk" "WebViewToo wrapper" $problems
    Assert-PathExists $releasePath "Plugins\WebViewToo\Lib\WebView2.ahk" "WebView2 wrapper" $problems
    Assert-PathExists $releasePath "WebViewApp\dist\index.html" "WebView dist index" $problems
    Assert-PathExists $releasePath "index.html" "help document" $problems
    Assert-GlobExists $releasePath "WebViewApp\dist\assets" "*.js" "WebView JavaScript bundle" $problems
    Assert-GlobExists $releasePath "WebViewApp\dist\assets" "*.css" "WebView CSS bundle" $problems

    if ((Split-Path -Leaf $releasePath) -match '_x64(?:_|$)') {
        Assert-PathExists $releasePath "Plugins\WebViewToo\Lib\64bit\WebView2Loader.dll" "64-bit WebView2 loader" $problems
    }
    elseif ((Split-Path -Leaf $releasePath) -match '_x32(?:_|$)') {
        Assert-PathExists $releasePath "Plugins\WebViewToo\Lib\32bit\WebView2Loader.dll" "32-bit WebView2 loader" $problems
    }
    else {
        $hasAnyLoader = (Test-Path -LiteralPath (Join-Path $releasePath "Plugins\WebViewToo\Lib\64bit\WebView2Loader.dll")) -or
            (Test-Path -LiteralPath (Join-Path $releasePath "Plugins\WebViewToo\Lib\32bit\WebView2Loader.dll"))
        if (-not $hasAnyLoader) {
            [void]$problems.Add("Missing WebView2 loader DLL under Plugins\WebViewToo\Lib")
        }
    }

    $nodeModulesPath = Join-Path $releasePath "WebViewApp\node_modules"
    if (Test-Path -LiteralPath $nodeModulesPath) {
        [void]$problems.Add("Unexpected node_modules directory: WebViewApp\node_modules")
    }

    if ($problems.Count -gt 0) {
        $message = ($problems | ForEach-Object { "  $_" }) -join "`n"
        throw "Release layout check failed for $releasePath`n$message"
    }

    Write-Host "Release layout check passed: $releasePath"
}

$version = Get-RmtVersion
$releaseDirs = Resolve-ReleaseDirs $ReleaseDir $ReleaseRoot $version

foreach ($dir in $releaseDirs) {
    Test-ReleaseDir $dir $version
}
