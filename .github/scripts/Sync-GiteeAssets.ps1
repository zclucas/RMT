# Mirror one published RMTAssets release. A retry fills missing files and verifies existing ones.
param([Parameter(Mandatory)][ValidatePattern('^(Common|v[0-9.]+(?:F\d+)?_x(?:64|86))$')][string]$Tag)
$ErrorActionPreference = 'Stop'
$repo = 'zclucas/RMTAssets'
$api = 'https://gitee.com/api/v5/repos/fateman/RMTAssets'
if (!$env:GITEE_RELEASE_TOKEN) { throw 'Missing GITEE_RELEASE_TOKEN.' }
$release = gh release view $Tag --repo $repo --json name,body,tagName,isDraft,isPrerelease,assets | ConvertFrom-Json
if ($LASTEXITCODE -or $release.isDraft -or $release.tagName -cne $Tag) { throw "Missing published release $Tag." }

$target = Invoke-RestMethod "$api/releases/tags/$Tag" -SkipHttpErrorCheck -StatusCodeVariable status -TimeoutSec 60
if ($status -eq 404 -or ($status -eq 200 -and !$target)) {
    $target = Invoke-RestMethod "$api/releases" -Method Post -TimeoutSec 60 -Body @{
        access_token = $env:GITEE_RELEASE_TOKEN
        tag_name = $Tag
        target_commitish = 'main'
        name = $release.name
        body = $release.body
        prerelease = $release.isPrerelease.ToString().ToLowerInvariant()
    }
}
if (!$target.id -or $target.tag_name -cne $Tag) { throw "Cannot read Gitee release $Tag (HTTP $status)." }

$dir = New-Item -ItemType Directory -Path (Join-Path $env:RUNNER_TEMP ([guid]::NewGuid()))
$failed = @()
foreach ($asset in ($release.assets | Sort-Object size)) {
    $name = $asset.name
    if ($name -notmatch '^[\w.-]+$' -or $name -in '.', '..') { throw "Invalid attachment name: $name" }
    $path = Join-Path $dir $name
    try {
        $hash = $asset.digest -replace '^sha256:', ''
        $exists = $target.assets.name -ccontains $name
        if (!$exists -or $hash -notmatch '^[0-9a-f]{64}$') {
            gh release download $Tag --repo $repo --pattern $name --dir $dir
            if ($LASTEXITCODE -or (Get-Item -LiteralPath $path).Length -ne $asset.size) { throw 'GitHub download failed.' }
            $actual = (Get-FileHash -LiteralPath $path).Hash
            if ($hash -and $hash -ne $actual) { throw 'GitHub checksum mismatch.' }
            $hash = $actual
        }
        if (!$exists) {
            $reply = curl --silent --show-error --fail --connect-timeout 20 --max-time 900 --header 'Expect:' `
                --variable '%GITEE_RELEASE_TOKEN' --expand-form 'access_token={{GITEE_RELEASE_TOKEN}}' `
                --form "file=@$path" "$api/releases/$($target.id)/attach_files"
            if ($LASTEXITCODE) { throw "Gitee upload failed (curl $LASTEXITCODE)." }
            $uploaded = $reply | ConvertFrom-Json
            if ($uploaded.name -cne $name -or $uploaded.size -ne $asset.size) { throw 'Unexpected Gitee attachment.' }
        }
        curl --silent --show-error --fail --location --retry 2 --connect-timeout 20 --max-time 900 `
            --output $path "https://gitee.com/fateman/RMTAssets/releases/download/$Tag/$name"
        if ($LASTEXITCODE -or (Get-FileHash -LiteralPath $path).Hash -ne $hash) { throw 'Gitee download checksum failed.' }
        Write-Host "Verified $Tag/$name"
    } catch {
        Write-Warning "$Tag/$name - $($_.Exception.Message)"
        $failed += $name
    } finally { [IO.File]::Delete($path) }
}
$dir.Delete()
if ($failed.Count) { throw "Failed $Tag attachments: $($failed -join ', ')" }
