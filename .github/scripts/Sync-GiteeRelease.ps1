# Requires PowerShell 7 and GitHub CLI. CI supplies GH_TOKEN and GITEE_RELEASE_TOKEN.
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+\.\d+(?:\.\d+)*(?:F\d+)?$')]
    [string]$Tag
)

$ErrorActionPreference = 'Stop'
if (-not $env:GITEE_RELEASE_TOKEN) { throw 'Set the GITEE_RELEASE_TOKEN secret before publishing.' }

$source = 'zclucas/RMT'
$target = 'fateman/RMT'
$api = "https://gitee.com/api/v5/repos/$target"
$release = gh release view $Tag --repo $source --json tagName,name,body,isDraft,isPrerelease,assets
if ($LASTEXITCODE -ne 0) { throw "Cannot read GitHub release $Tag." }
$release = $release | ConvertFrom-Json
if ($release.isDraft -or $release.tagName -cne $Tag) {
    throw "Expected a published GitHub release for $Tag."
}
$sha = gh api "repos/$source/commits/$Tag" --jq '.sha'
if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') {
    throw "Cannot resolve GitHub tag $Tag."
}
if ($env:RELEASE_RUN_SHA -and $env:RELEASE_RUN_SHA -cne $sha) {
    throw "GitHub tag $Tag has moved since the build."
}

# The code mirror can lag behind the release workflow. Resolve annotated tags to commits.
$ref = "refs/tags/$Tag"
for ($attempt = 1; $attempt -le 21; $attempt++) {
    $refs = git ls-remote "https://gitee.com/$target.git" $ref "$ref^{}"
    if ($LASTEXITCODE -ne 0) { throw "Cannot query tags on $target." }
    $match = $refs | Where-Object { ($_ -split "`t", 2)[1] -ceq "$ref^{}" }
    if (-not $match) { $match = $refs | Where-Object { ($_ -split "`t", 2)[1] -ceq $ref } }
    if ($match) {
        $mirrorSha = ($match -split "`t", 2)[0]
        if ($mirrorSha -ceq $sha) { break }
        throw "Gitee tag $Tag points to $mirrorSha; expected $sha."
    }
    if ($attempt -eq 21) {
        throw "Tag $Tag is not on $target yet. Refresh the code mirror, then re-run this workflow."
    }
    Write-Host "Waiting for Gitee to mirror $Tag ($attempt/20)."
    Start-Sleep -Seconds 15
}

$names = @("RMT$($Tag)_x64.zip", "RMT$($Tag)_x86.zip")
foreach ($name in $names) {
    $asset = $release.assets | Where-Object name -CEQ $name
    if (-not $asset -or $asset.size -le 0 -or $asset.size -gt 100MB) {
        throw "GitHub asset $name is missing, empty or above the Gitee size limit."
    }
}

$dir = Join-Path ([IO.Path]::GetTempPath()) ("rmt-gitee-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    gh release download $Tag --repo $source --dir $dir --pattern $names[0] --pattern $names[1]
    if ($LASTEXITCODE -ne 0) { throw "Cannot download the GitHub release assets for $Tag." }
    foreach ($name in $names) {
        $asset = $release.assets | Where-Object name -CEQ $name
        if ((Get-Item -LiteralPath (Join-Path $dir $name)).Length -ne $asset.size) {
            throw "Downloaded size does not match GitHub for $name."
        }
    }

    $gitee = Invoke-RestMethod -Uri "$api/releases/tags/$Tag" -TimeoutSec 30 -SkipHttpErrorCheck -StatusCodeVariable status
    if ($status -eq 404 -or ($status -eq 200 -and $null -eq $gitee)) {
        $gitee = Invoke-RestMethod -Uri "$api/releases" -Method Post -TimeoutSec 30 -Body @{
            access_token     = $env:GITEE_RELEASE_TOKEN
            tag_name         = $Tag
            target_commitish = $sha
            name             = $release.name
            body             = $release.body
            prerelease       = $release.isPrerelease.ToString().ToLowerInvariant()
        }
    }
    if (-not $gitee.id -or $gitee.tag_name -cne $Tag -or $gitee.prerelease -ne $release.isPrerelease) {
        throw "Gitee release $Tag could not be read or has a different prerelease setting."
    }

    $attachmentApi = "$api/releases/$($gitee.id)/attach_files"
    $attachments = Invoke-RestMethod -Uri "${attachmentApi}?per_page=100" -TimeoutSec 30
    foreach ($name in $names) {
        $asset = $release.assets | Where-Object name -CEQ $name
        $attached = $attachments | Where-Object name -CEQ $name
        if ($attached) {
            if ($attached.size -ne $asset.size) {
                throw "Gitee already has a different file named $name; check the existing attachment."
            }
            Write-Host "Already uploaded: $name"
            continue
        }
        $uploaded = Invoke-RestMethod -Uri $attachmentApi -Method Post -TimeoutSec 180 -Form @{
            access_token = $env:GITEE_RELEASE_TOKEN
            file         = Get-Item -LiteralPath (Join-Path $dir $name)
        }
        if ($uploaded.name -cne $name -or $uploaded.size -ne $asset.size) {
            throw "Gitee did not confirm upload of $name."
        }
        Write-Host "Uploaded: $name"
    }
    Write-Host "Gitee release: https://gitee.com/$target/releases/tag/$Tag"
} finally {
    Remove-Item -LiteralPath (Join-Path $dir $names[0]), (Join-Path $dir $names[1]) -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dir -ErrorAction SilentlyContinue
}
