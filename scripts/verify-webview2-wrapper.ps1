[CmdletBinding()]
param(
    [string]$EntryScript = "RMT.ahk"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$EntryPath = Resolve-Path (Join-Path $RepoRoot $EntryScript)
$OldWebViewRoot = Resolve-Path (Join-Path $RepoRoot "Plugins\WebView2")
$WebViewTooRoot = Resolve-Path (Join-Path $RepoRoot "Plugins\WebViewToo\Lib")
$ExpectedWebView2 = Resolve-Path (Join-Path $WebViewTooRoot "WebView2.ahk")
$ExpectedWebViewToo = Resolve-Path (Join-Path $WebViewTooRoot "WebViewToo.ahk")

function Normalize-PathText {
    param([string]$PathText)
    return ([System.IO.Path]::GetFullPath($PathText)).TrimEnd('\')
}

function Test-IsUnderPath {
    param(
        [string]$Path,
        [string]$Root
    )

    $normalizedPath = Normalize-PathText $Path
    $normalizedRoot = Normalize-PathText $Root
    return $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-IncludeTargets {
    param([string]$SourcePath)

    $sourceDir = Split-Path -Parent $SourcePath
    $content = Get-Content -LiteralPath $SourcePath -Raw
    $matches = [regex]::Matches($content, '(?im)^\s*#Include(?:Again)?\s+(?<target>.+?)\s*$')
    $targets = @()

    foreach ($match in $matches) {
        $rawTarget = $match.Groups["target"].Value.Trim()
        if ($rawTarget.StartsWith("*i ", [System.StringComparison]::OrdinalIgnoreCase)) {
            $rawTarget = $rawTarget.Substring(3).Trim()
        }
        $rawTarget = $rawTarget.Trim('"', "'")

        if ([string]::IsNullOrWhiteSpace($rawTarget) -or $rawTarget.StartsWith("<") -or $rawTarget.Contains("%")) {
            continue
        }

        $candidate = if ([System.IO.Path]::IsPathRooted($rawTarget)) {
            $rawTarget
        }
        else {
            Join-Path $sourceDir $rawTarget
        }

        if (Test-Path -LiteralPath $candidate) {
            $targets += (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $targets
}

function Get-IncludeGraph {
    param([string]$RootScript)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push((Resolve-Path -LiteralPath $RootScript).Path)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if (-not $seen.Add($current)) {
            continue
        }

        foreach ($target in Get-IncludeTargets $current) {
            $stack.Push($target)
        }
    }

    return @($seen)
}

function Get-TrackedAhkFiles {
    Push-Location $RepoRoot
    try {
        $files = & git ls-files "*.ahk"
        if ($LASTEXITCODE -eq 0 -and $files) {
            return @($files | ForEach-Object { Join-Path $RepoRoot $_ })
        }
    }
    finally {
        Pop-Location
    }

    return @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter "*.ahk" -File |
        Where-Object { $_.FullName -notmatch '\\ReleaseX(32|64)\\' } |
        ForEach-Object { $_.FullName })
}

$includeGraph = Get-IncludeGraph $EntryPath
$oldRuntimeIncludes = @($includeGraph | Where-Object { Test-IsUnderPath $_ $OldWebViewRoot })
$webViewTooIncludes = @($includeGraph | Where-Object { Test-IsUnderPath $_ $WebViewTooRoot })

if ($oldRuntimeIncludes.Count -gt 0) {
    throw "RMT runtime include graph loads the legacy Plugins\WebView2 wrapper:`n$($oldRuntimeIncludes -join "`n")"
}

if (-not ($includeGraph -contains $ExpectedWebViewToo.Path)) {
    throw "RMT runtime include graph does not include Plugins\WebViewToo\Lib\WebViewToo.ahk"
}

if (-not ($includeGraph -contains $ExpectedWebView2.Path)) {
    throw "RMT runtime include graph does not include Plugins\WebViewToo\Lib\WebView2.ahk"
}

$badSourceIncludes = @()
foreach ($file in Get-TrackedAhkFiles) {
    $fullPath = (Resolve-Path -LiteralPath $file).Path
    if (Test-IsUnderPath $fullPath $OldWebViewRoot) {
        continue
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    if ($content -match '(?im)^\s*#Include(?:Again)?\s+.*Plugins[\\/]+WebView2[\\/]+') {
        $badSourceIncludes += $fullPath
    }
}

if ($badSourceIncludes.Count -gt 0) {
    throw "Source files outside Plugins\WebView2 include the legacy WebView2 wrapper:`n$($badSourceIncludes -join "`n")"
}

Write-Host "WebView2 wrapper check passed."
Write-Host ("Runtime WebViewToo files: {0}" -f $webViewTooIncludes.Count)
