[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SingleHtmlScript = Join-Path $RepoRoot "Web\JS\SingleHtml.js"
$HelpDocName = "RMT" + [char]0x5e2e + [char]0x52a9 + [char]0x6587 + [char]0x6863 + ".html"

if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    throw "Node.js is required to verify generated help documentation."
}

if (-not (Test-Path -LiteralPath $SingleHtmlScript)) {
    throw "Missing help document packer: Web\JS\SingleHtml.js"
}

foreach ($relativePath in @($HelpDocName, "index.html")) {
    $outputPath = Join-Path $RepoRoot $relativePath
    if (-not (Test-Path -LiteralPath $outputPath)) {
        throw "Missing generated help document: $relativePath"
    }
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
