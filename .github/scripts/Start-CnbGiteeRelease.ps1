param([Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference = 'Stop'
$repo = $env:CNB_RELEASE_REPO
if ($repo -notmatch '^[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)+$' -or -not $env:CNB_TRIGGER_TOKEN) {
    throw 'Configure CNB_RELEASE_REPO and CNB_TRIGGER_TOKEN before triggering CNB.'
}
$assets = gh release view $Tag --repo zclucas/RMT --json assets
if ($LASTEXITCODE) { throw 'Failed to read release metadata.' }
$names = @("RMT${Tag}_x64.zip", "RMT${Tag}_x86.zip")
$packages = @(($assets | ConvertFrom-Json).assets | Where-Object name -cin $names | Select-Object name,size,digest)
if ($packages.Count -ne 2 -or ($packages | Where-Object digest -NotMatch '^sha256:[0-9a-f]{64}$')) {
    throw 'Both GitHub package digests are required to publish via CNB.'
}
$headers = @{ Authorization = "Bearer $env:CNB_TRIGGER_TOKEN"; Accept = 'application/json' }
$api = "https://api.cnb.cool/$repo/-/build"
$payload = @{
    branch = 'main'
    event = 'api_trigger_gitee_release'
    title = "Gitee $Tag"
    env = @{
        RELEASE_TAG = $Tag
        RELEASE_ASSETS = ConvertTo-Json -InputObject $packages -Compress
        GITEE_TARGET = 'fateman/RMT'
    }
} | ConvertTo-Json -Depth 4
$build = Invoke-RestMethod "$api/start" -Method Post -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 30
if (-not $build.success -or $build.sn -notmatch '^[a-zA-Z0-9_-]+$') { throw 'CNB did not accept the build.' }
Write-Host "CNB build: $($build.buildLogUrl)"
$timer = [Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalMinutes -lt 10) {
    Start-Sleep -Seconds 5
    $state = Invoke-RestMethod "$api/status/$($build.sn)" -Headers $headers -TimeoutSec 20 -MaximumRetryCount 2
    if ($state.status -in 'success','succeeded','passed') {
        if (-not $state.pipelinesStatus -or @($state.pipelinesStatus.psobject.Properties).Count -eq 0) { throw 'CNB reported no pipelines.' }
        Write-Host "CNB confirmed both Gitee downloads in $([int]$timer.Elapsed.TotalSeconds)s after dispatch."
        return
    }
    if ($state.status -match 'fail|error|cancel|skip|timeout') { throw "CNB ended with $($state.status)." }
}
throw 'CNB did not confirm publication within ten minutes of dispatch.'
