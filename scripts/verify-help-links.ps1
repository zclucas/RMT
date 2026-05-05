[CmdletBinding()]
param(
    [string]$DocsPath = "Web"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DocsRoot = Resolve-Path (Join-Path $RepoRoot $DocsPath)
$Problems = [System.Collections.Generic.List[string]]::new()

function Get-LineNumber {
    param(
        [string]$Content,
        [int]$Index
    )

    if ($Index -le 0) {
        return 1
    }

    return ([regex]::Matches($Content.Substring(0, $Index), "`r`n|`n|`r")).Count + 1
}

function Test-IsExternalTarget {
    param([string]$Target)

    return $Target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or
        $Target.StartsWith("#")
}

function Get-TargetPathPart {
    param([string]$Target)

    $cleanTarget = $Target.Trim()
    if ($cleanTarget.StartsWith("<") -and $cleanTarget.EndsWith(">")) {
        $cleanTarget = $cleanTarget.Substring(1, $cleanTarget.Length - 2)
    }

    if ($cleanTarget -match '^(?<path>\S+)\s+["''][^"'']+["'']$') {
        $cleanTarget = $matches["path"]
    }

    $pathPart = ($cleanTarget -split '#', 2)[0]
    $pathPart = ($pathPart -split '\?', 2)[0]
    if ([string]::IsNullOrWhiteSpace($pathPart)) {
        return ""
    }

    return [System.Uri]::UnescapeDataString($pathPart)
}

function Resolve-LocalTargetPath {
    param(
        [string]$SourcePath,
        [string]$Target
    )

    $pathPart = Get-TargetPathPart $Target
    if ([string]::IsNullOrWhiteSpace($pathPart)) {
        return $null
    }

    $normalized = $pathPart.Replace("/", "\")
    if ($normalized.StartsWith("\RMT\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $RepoRoot $normalized.Substring(5)
    }

    if ($normalized.StartsWith("\")) {
        return Join-Path $RepoRoot $normalized.TrimStart("\")
    }

    if ([System.IO.Path]::IsPathRooted($normalized)) {
        return $normalized
    }

    return Join-Path (Split-Path -Parent $SourcePath) $normalized
}

function Test-Target {
    param(
        [string]$SourcePath,
        [string]$Content,
        [System.Text.RegularExpressions.Match]$Match
    )

    $target = $Match.Groups["target"].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($target) -or (Test-IsExternalTarget $target)) {
        return
    }

    $resolvedPath = Resolve-LocalTargetPath $SourcePath $target
    if ($null -eq $resolvedPath) {
        return
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        $relativeSource = [System.IO.Path]::GetRelativePath($RepoRoot, $SourcePath)
        $line = Get-LineNumber $Content $Match.Index
        [void]$Problems.Add("${relativeSource}:$line missing local target: $target")
    }
}

$markdownFiles = @(Get-ChildItem -LiteralPath $DocsRoot -Filter "*.md" -File)
if ($markdownFiles.Count -eq 0) {
    throw "No Markdown files found under $DocsPath."
}

foreach ($file in $markdownFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $markdownMatches = [regex]::Matches($content, '(?m)!?\[[^\]\r\n]*\]\((?<target>[^)\r\n]+)\)')
    $htmlMatches = [regex]::Matches($content, '(?i)\b(?:src|href)\s*=\s*["''](?<target>[^"'']+)["'']')

    foreach ($match in $markdownMatches) {
        Test-Target $file.FullName $content $match
    }

    foreach ($match in $htmlMatches) {
        Test-Target $file.FullName $content $match
    }
}

if ($Problems.Count -gt 0) {
    $message = ($Problems | ForEach-Object { "  $_" }) -join "`n"
    throw "Help Markdown local link check failed:`n$message"
}

Write-Host "Help Markdown local links and images are valid."
