# Gitee is the only source used by the production downloader in this test.
param(
    [Parameter(Mandatory)][ValidatePattern('^(Common|v[0-9.]+(?:F\d+)?_x(?:64|86))$')][string]$Tag,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_][a-zA-Z0-9._-]*\.tar\.bz2$')][string]$AssetName
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:RUNNER_TEMP 'rmt-volume-check'
$sourceDir = New-Item -ItemType Directory -Path (Join-Path $root 'source') -Force
$restoredDir = New-Item -ItemType Directory -Path (Join-Path $root 'restored') -Force
$extractDir = New-Item -ItemType Directory -Path (Join-Path $root 'extracted') -Force
$source = Join-Path $sourceDir $AssetName
$restored = Join-Path $restoredDir $AssetName
gh release download $Tag --repo zclucas/RMTAssets --pattern $AssetName --dir $sourceDir
if ($LASTEXITCODE) { throw 'Cannot download reference original from GitHub.' }
$url = "https://gitee.com/fateman/RMTAssets/releases/download/$Tag/$AssetName"
$downloader = Join-Path $PSScriptRoot '../../Main/Util/RmtDownloadFile.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $downloader -Url $url -Path $restored -Headers "$restored.headers" -TimeoutSec 900
if ($LASTEXITCODE) { throw 'Gitee volume download/merge failed.' }
$expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
if ((Get-Item -LiteralPath $source).Length -ne (Get-Item -LiteralPath $restored).Length -or
    (Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash -cne $expected) { throw 'Restored archive differs from original.' }
@'
import hashlib, json, pathlib, sys, tarfile
source, restored, extracted, report, url = sys.argv[1:]
count = 0
total = 0
with tarfile.open(restored, 'r:bz2') as archive:
    archive.extractall(extracted, filter='data')
with tarfile.open(source, 'r:bz2') as archive:
    for member in archive:
        if not member.isfile():
            continue
        actual = pathlib.Path(extracted, member.name)
        assert actual.stat().st_size == member.size, member.name
        def digest(stream):
            h = hashlib.sha256()
            for block in iter(lambda: stream.read(1024*1024), b''):
                h.update(block)
            return h.hexdigest()
        with archive.extractfile(member) as reference, actual.open('rb') as target:
            assert digest(reference) == digest(target), member.name
        count += 1
        total += member.size
assert count > 0, 'Empty archive'
with open(restored, 'rb') as archive:
    sha = hashlib.file_digest(archive, 'sha256').hexdigest()
result = dict(status='passed', source_url=url, archive_bytes=pathlib.Path(restored).stat().st_size,
              archive_sha256=sha, extracted_files=count, extracted_bytes=total)
pathlib.Path(report).write_text(json.dumps(result, indent=2), encoding='utf8')
print(json.dumps(result, indent=2))
'@ | python - $source $restored $extractDir (Join-Path $root 'result.json') $url
if ($LASTEXITCODE) { throw 'Extraction/content verification failed.' }
if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value "Gitee volume download, SHA-256 merge and extraction passed: $AssetName"
}
