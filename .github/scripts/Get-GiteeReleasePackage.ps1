# Download a public RMT release attachment and verify it before exposing it to callers.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^v\d+\.\d+(?:\.\d+)*(?:F\d+)?$')][string]$Tag,
    [Parameter(Mandatory)][ValidateSet('x64', 'x86')][string]$Arch,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$Sha256,
    [Parameter(Mandatory)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
$name = "RMT${Tag}_$Arch.zip"
$dest = [IO.Directory]::CreateDirectory($OutDir).FullName
$temp = Join-Path $dest ([guid]::NewGuid().ToString() + '.part')
$url = "https://gitee.com/fateman/RMT/releases/download/$Tag/$name"
try {
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' `
        --retry 2 --connect-timeout 20 --max-time 1200 --output $temp $url
    if ($LASTEXITCODE -ne 0) { throw "Gitee download failed for $name (curl exit $LASTEXITCODE)." }
    if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Gitee SHA-256 mismatch for $name."
    }
    [IO.File]::Move($temp, (Join-Path $dest $name), $true)
    Write-Host "Verified Gitee download: $name ($Sha256)"
} finally {
    [IO.File]::Delete($temp)
}
