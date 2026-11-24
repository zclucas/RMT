# 统一发布到 GitHub / GitCode；共享资源替换前归档旧版本依赖。
param(
    [Parameter(Mandatory)][string]$InfoPath,
    [Parameter(Mandatory)][string]$OutDir,
    [Parameter(Mandatory)][string]$Repo
)
$ErrorActionPreference = 'Stop'
if ($Repo -cne 'zclucas/RMTAssets') { throw 'Unexpected resource repository.' }
if (!(Test-Path -LiteralPath $InfoPath)) { throw 'release-info.json is missing.' }
if ([IO.Path]::GetFullPath($InfoPath) -cne [IO.Path]::GetFullPath((Join-Path $OutDir 'release-info.json'))) {
    throw 'InfoPath must refer to the supplied artifact directory.'
}
& python (Join-Path $PSScriptRoot 'resource_layout.py') publish --directory $OutDir
if ($LASTEXITCODE -ne 0) { throw 'Resource publication failed; see resource-layout-result.json.' }
