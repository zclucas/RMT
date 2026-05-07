[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SingleHtmlScript = Join-Path $RepoRoot "Web\JS\SingleHtml.js"
if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    throw "Node.js is required to verify generated help documentation."
}

if (-not (Test-Path -LiteralPath $SingleHtmlScript)) {
    throw "Missing help document packer: Web\JS\SingleHtml.js"
}

$outputPath = Join-Path $RepoRoot "index.html"
if (-not (Test-Path -LiteralPath $outputPath)) {
    throw "Missing generated help document: index.html"
}

Push-Location $RepoRoot
try {
    & node $SingleHtmlScript --check
    $lastExitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
    $exitCode = if ($null -eq $lastExitCodeVar) { 0 } else { [int]$lastExitCodeVar.Value }
    if ($exitCode -ne 0) {
        throw "Help documentation generation check failed with exit code $exitCode"
    }
}
finally {
    Pop-Location
}
