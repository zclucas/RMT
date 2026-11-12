# 上传打包产物到 zclucas/RMTAssets（从 CI 迁出的独立脚本，可本地测试）
# 输入：release-info.json + RMTv*.zip + RMTAssets_* 目录（版本发布工作流的 artifact）
# 行为：
#   1. 按 RMTAssets_* 目录实际存在情况决定 tag 组（Common 恒有，x64/x86 看产物）
#   2. 校验 zip 完整性（附件存在、非 .zip 条目、内部条目为空均报错）
#   3. release 已存在 → gh release upload --clobber；否则创建（--latest=false）
#   4. 全部上传成功后，清理已被替代的旧附件
# 需要环境变量 GH_TOKEN（对 RMTAssets 有 Contents 写权限的 token）。
param(
    [Parameter(Mandatory)][string]$InfoPath,   # release-info.json 路径
    [Parameter(Mandatory)][string]$OutDir,     # RMTRelease 目录（含 zip 与 RMTAssets_*）
    [Parameter(Mandatory)][string]$Repo        # 目标仓库，如 zclucas/RMTAssets
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $env:GH_TOKEN) {
    throw 'GH_TOKEN 未设置：需要一个对 RMTAssets 有 Contents 写权限的 token（Actions Secret RMT_ASSETS_TOKEN）。'
}

$info = Get-Content -LiteralPath $InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$assetTag = $info.asset_tag
Write-Host "来源版本: $($info.version)（$($info.channel)），资源 tag 前缀: $assetTag"

# 1) 按目录存在情况决定 tag 组
#    架构 tag 带完整版本号（v1.3F2_x64 / v1.3_x64）：测试版与正式版资源互不覆盖；
#    Common（赞助 logo 等跨版本内容）不再由打包生成，仅在目录存在时上传。
$releaseDirs = [ordered]@{}
$commonDir = Join-Path $OutDir 'RMTAssets_Common'
$x64Dir = Join-Path $OutDir 'RMTAssets_x64'
$x86Dir = Join-Path $OutDir 'RMTAssets_x86'
if (Test-Path -LiteralPath $commonDir) { $releaseDirs['Common'] = $commonDir }
if (Test-Path -LiteralPath $x64Dir)    { $releaseDirs["v${assetTag}_x64"] = $x64Dir }
if (Test-Path -LiteralPath $x86Dir)    { $releaseDirs["v${assetTag}_x86"] = $x86Dir }
if ($releaseDirs.Count -lt 2) {
    throw "资源目录不完整（至少要有 x64 / x86 两个架构包）：$($releaseDirs.Keys -join ', ')"
}

# 2) 校验 zip 完整性，收集各 tag 的 zip 附件与内部文件清单
$assetsByTag = [ordered]@{}
$packedFilesByTag = @{}
foreach ($tag in $releaseDirs.Keys) {
    $assetDir = $releaseDirs[$tag]
    $assets = @(Get-ChildItem -LiteralPath $assetDir -File)
    if ($assets.Count -eq 0 -or ($assets | Where-Object { $_.Length -eq 0 -or $_.Extension -ne '.zip' })) {
        throw "资源目录没有生成可上传的完整文件：$assetDir"
    }
    $assetsByTag[$tag] = @($assets.FullName)
    $packedFilesByTag[$tag] = @(foreach ($asset in $assets) {
        $zip = [IO.Compression.ZipFile]::OpenRead($asset.FullName)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.Length -le 0) { throw "资源包条目为空：$($asset.Name) / $($entry.FullName)" }
                $entry.FullName
            }
        } finally {
            $zip.Dispose()
        }
    })
}

# 3) 上传（存在则覆盖，不存在则创建）
foreach ($tag in $assetsByTag.Keys) {
    $assets = $assetsByTag[$tag]
    # PS5.1: 原生 stderr 不能重定向（2>$null 在 ErrorActionPreference=Stop 下会抛终止异常），
    # "release not found" 打到日志属首次发布的正常现象，以下面退出码为准。
    gh release view $tag --repo $Repo --json tagName | Out-Null
    if ($LASTEXITCODE -eq 0) {
        gh release upload $tag @assets --repo $Repo --clobber
    } else {
        gh release create $tag @assets --repo $Repo --title $tag --latest=false `
            --notes "RMT $($info.version) from $($info.tag) ($($info.sha))"
    }
    if ($LASTEXITCODE -ne 0) { throw "资源发布失败：$Repo $tag" }
    Write-Host "Published $($assets.Count) assets to $Repo $tag"
}

# 4) 全部新包发布成功后，再删除已被替代的旧附件
#    各版本 tag 互相独立，清理只发生在本版本 tag 内，不影响其他版本。
$oldKwsNames = @('kws_decoder.onnx', 'kws_encoder.int8.onnx', 'kws_joiner.onnx', 'kws_tokens.txt')
$commonKey = $null
foreach ($t in $assetsByTag.Keys) {
    if ($releaseDirs[$t] -like '*RMTAssets_Common') { $commonKey = $t; break }
}
$commonPacked = if ($commonKey) { $packedFilesByTag[$commonKey] } else { @() }
foreach ($tag in $assetsByTag.Keys) {
    $obsolete = if ($tag -eq $commonKey) {
        $oldKwsNames + 'VoiceKws.zip'
    } else {
        $packedFilesByTag[$tag] + $commonPacked + $oldKwsNames
    }
    $publishedNames = @($assetsByTag[$tag] | Split-Path -Leaf)
    $existingNames = gh release view $tag --repo $Repo --json assets --jq '.assets[].name'
    if ($LASTEXITCODE -ne 0) { throw "无法读取 $Repo $tag 的附件" }
    foreach ($name in $existingNames) {
        if ($name -cnotin $obsolete -or $name -cin $publishedNames) { continue }
        gh release delete-asset $tag $name --repo $Repo --yes
        if ($LASTEXITCODE -ne 0) { throw "无法删除 $Repo $tag 中的旧附件：$name" }
    }
}

Write-Host "[RESULT] ASSETS OK ($($assetsByTag.Keys -join ', '))"
