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
Write-Host "Reading GitHub release $Tag."
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

$names = @("RMT$($Tag)_x64.zip", "RMT$($Tag)_x86.zip")
foreach ($name in $names) {
    $asset = $release.assets | Where-Object name -CEQ $name
    if (-not $asset -or $asset.size -le 0 -or $asset.size -gt 100MB) {
        throw "GitHub asset $name is missing, empty or above the Gitee size limit."
    }
}

# Resolve annotated tags to their commit. Push only the release tag when the mirror lacks it.
$ref = "refs/tags/$Tag"
$giteeRemote = "https://gitee.com/$target.git"
$gitHttp = @('-c', 'http.lowSpeedLimit=1', '-c', 'http.lowSpeedTime=45')
Write-Host "Checking Gitee tag $Tag."
$refs = git @gitHttp ls-remote $giteeRemote $ref "$ref^{}"
if ($LASTEXITCODE -ne 0) { throw "Cannot query tags on $target." }
$match = $refs | Where-Object { ($_ -split "`t", 2)[1] -ceq "$ref^{}" }
if (-not $match) { $match = $refs | Where-Object { ($_ -split "`t", 2)[1] -ceq $ref } }
if ($match) {
    $mirrorSha = ($match -split "`t", 2)[0]
    if ($mirrorSha -cne $sha) { throw "Gitee tag $Tag points to $mirrorSha; expected $sha." }
} else {
    Write-Host "Creating Gitee tag $Tag at $sha."
    $createdTag = Invoke-RestMethod -Uri "$api/tags" -Method Post -TimeoutSec 30 -SkipHttpErrorCheck -StatusCodeVariable tagStatus -Body @{
        access_token = $env:GITEE_RELEASE_TOKEN
        refs         = $sha
        tag_name     = $Tag
    }
    if ($tagStatus -eq 201) {
        if ($createdTag.name -cne $Tag -or $createdTag.commit.sha -cne $sha) {
            throw "Gitee did not confirm tag $Tag at $sha."
        }
    } elseif ($tagStatus -in 400, 404, 422) {
        # Gitee may lack the commit history, so a shallow fetch is insufficient for the push.
        Write-Host "Gitee tag API returned HTTP $tagStatus. Fetching the GitHub commit for a Git push."
        $fetchOptions = @('--no-tags')
        $shallow = git rev-parse --is-shallow-repository
        if ($LASTEXITCODE -ne 0) { throw 'Run the sync from a Git checkout.' }
        if ($shallow -eq 'true') { $fetchOptions += '--unshallow' }
        git @gitHttp fetch @fetchOptions "https://github.com/$source.git" $sha
        if ($LASTEXITCODE -ne 0) { throw "Cannot fetch GitHub release commit $sha." }

        # Git reads the token from the environment without putting it in argv or remote URLs.
        $credentialHelper = '!f() { if test "$1" = get; then printf "username=oauth2\npassword=%s\n" "$GITEE_RELEASE_TOKEN"; fi; }; f'
        Write-Host "Pushing $ref to Gitee."
        git @gitHttp -c 'credential.helper=' -c "credential.helper=$credentialHelper" push --no-follow-tags $giteeRemote "${sha}:$ref"
        if ($LASTEXITCODE -ne 0) { throw "Cannot create Gitee tag $Tag from GitHub commit $sha." }
    } else {
        throw "Could not create Gitee tag $Tag (HTTP $tagStatus)."
    }
    Write-Host "Created Gitee tag $Tag at $sha."
}

$dir = Join-Path ([IO.Path]::GetTempPath()) ("rmt-gitee-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    Write-Host "Downloading the two GitHub release ZIPs."
    gh release download $Tag --repo $source --dir $dir --pattern $names[0] --pattern $names[1]
    if ($LASTEXITCODE -ne 0) { throw "Cannot download the GitHub release assets for $Tag." }
    foreach ($name in $names) {
        $asset = $release.assets | Where-Object name -CEQ $name
        if ((Get-Item -LiteralPath (Join-Path $dir $name)).Length -ne $asset.size) {
            throw "Downloaded size does not match GitHub for $name."
        }
    }

    Write-Host "Checking Gitee release $Tag."
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
    } elseif ($status -ne 200) {
        throw "Could not read Gitee release $Tag (HTTP $status)."
    }
    if (-not $gitee.id -or $gitee.tag_name -cne $Tag -or $gitee.prerelease -ne $release.isPrerelease) {
        throw "Gitee release $Tag could not be read or has a different prerelease setting."
    }

    $attachmentApi = "$api/releases/$($gitee.id)/attach_files"
    $attachments = @()
    if ($gitee.assets | Where-Object { $_.name -cin $names }) {
        $attachments = Invoke-RestMethod -Uri "${attachmentApi}?per_page=100" -TimeoutSec 30
    }
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
        Write-Host "Uploading $name to Gitee."
        $file = Join-Path $dir $name
        $result = curl --silent --show-error --fail --http1.1 --header 'Expect:' `
            --connect-timeout 20 --max-time 360 --speed-limit 1024 --speed-time 60 `
            --variable '%GITEE_RELEASE_TOKEN' --expand-form 'access_token={{GITEE_RELEASE_TOKEN}}' `
            --form "file=@$file;type=application/zip" `
            --write-out '%{stderr}Gitee HTTP %{http_code}, sent %{size_upload} bytes in %{time_total}s\n' `
            $attachmentApi
        if ($LASTEXITCODE -ne 0) { throw "Attachment upload failed for $name (curl exit $LASTEXITCODE)." }
        $uploaded = $result | ConvertFrom-Json
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
