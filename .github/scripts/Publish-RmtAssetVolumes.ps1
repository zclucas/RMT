# Add byte volumes to existing GitHub assets without replacing the original.
param(
    [Parameter(Mandatory)][ValidatePattern('^(Common|v[0-9.]+(?:F\d+)?_x(?:64|86))$')][string]$Tag,
    [string]$AssetName = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../Scripts/Split-RmtAsset.ps1')
$repo = 'zclucas/RMTAssets'
$release = gh release view $Tag --repo $repo --json tagName,isDraft,assets | ConvertFrom-Json
if ($LASTEXITCODE -or $release.isDraft -or $release.tagName -cne $Tag) { throw 'Missing published release.' }
if ($AssetName -and !($release.assets | Where-Object { $_.name -ceq $AssetName })) { throw 'Requested source attachment not found.' }
$dir = New-Item -ItemType Directory -Path (Join-Path $env:RUNNER_TEMP ([guid]::NewGuid()))
function Remove-StaleVolumes([string]$OriginalName, [string[]]$PublishedNames) {
    $obsolete = @(Get-RmtObsoleteAssetVolumes -OriginalNames @($OriginalName) -PublishedNames $PublishedNames -ExistingNames $release.assets.name)
    foreach ($name in @($obsolete | Sort-Object { if ($_.EndsWith('.parts.json')) { 0 } else { 1 } })) {
        gh release delete-asset $Tag $name --repo $repo --yes
        if ($LASTEXITCODE) { throw "Cannot retire obsolete volume $Tag/$name" }
    }
}
# 历史 Common 等附件也补发分片到 GitHub，再按普通小附件同步。
foreach ($asset in @($release.assets | Where-Object { $_.name -cnotmatch '\.(?:parts\.json|part\d{4})$' -and (!$AssetName -or $_.name -ceq $AssetName) })) {
    if ($asset.size -le 95000000) {
        Remove-StaleVolumes $asset.name @($asset.name)
        continue
    }
    $manifestName = $asset.name + '.parts.json'
    if ($asset.digest -match '^sha256:([0-9a-f]{64})$' -and $release.assets.name -ccontains $manifestName) {
        $sourceHash = $Matches[1]
        gh release download $Tag --repo $repo --pattern $manifestName --dir $dir --clobber
        if ($LASTEXITCODE) { throw 'Cannot read existing volume manifest.' }
        $manifest = Get-Content -LiteralPath (Join-Path $dir $manifestName) -Raw | ConvertFrom-Json
        [IO.File]::Delete((Join-Path $dir $manifestName))
        $complete = $manifest.version -eq 1 -and $manifest.size -eq $asset.size -and $manifest.sha256 -ceq $sourceHash -and $manifest.parts.Count -gt 0
        foreach ($part in $manifest.parts) {
            $remote = @($release.assets | Where-Object { $_.name -ceq $part.name })
            if ($remote.Count -ne 1 -or $remote[0].size -ne $part.size -or $remote[0].digest -cne ('sha256:' + $part.sha256)) { $complete = $false }
        }
        if ($complete) {
            Remove-StaleVolumes $asset.name (@($manifest.parts.name) + @($manifestName))
            continue
        }
    }
    $path = Join-Path $dir $asset.name
    gh release download $Tag --repo $repo --pattern $asset.name --dir $dir
    if ($LASTEXITCODE -or (Get-Item -LiteralPath $path).Length -ne $asset.size) { throw 'GitHub download failed.' }
    if ($asset.digest -match '^sha256:([0-9a-f]{64})$' -and
        (Get-FileHash -LiteralPath $path).Hash -ine $Matches[1]) { throw 'GitHub checksum mismatch.' }
    $volumes = @(Split-RmtAsset -Path $path -OutDir $dir)
    gh release upload $Tag @volumes --repo $repo --clobber
    if ($LASTEXITCODE) { throw "Cannot publish volumes for $Tag/$($asset.name). RMT_ASSETS_TOKEN needs Contents write access." }
    Remove-StaleVolumes $asset.name @($volumes | ForEach-Object { Split-Path $_ -Leaf })
    [IO.File]::Delete($path)
    foreach ($volume in $volumes) { [IO.File]::Delete($volume) }
}
$dir.Delete()
