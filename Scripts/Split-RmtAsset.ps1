# Byte volumes preserve the original archive/installer; no extra decompressor is needed.
function Get-RmtObsoleteAssetVolumes {
    param([string[]]$OriginalNames, [string[]]$PublishedNames, [string[]]$ExistingNames)
    foreach ($name in $ExistingNames) {
        if ($name -cin $PublishedNames) { continue }
        foreach ($original in $OriginalNames) {
            if ($name -cmatch ('^' + [regex]::Escape($original) + '\.(?:parts\.json|part\d{4})$')) {
                $name
                break
            }
        }
    }
}

function Split-RmtAsset {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OutDir,
        [ValidateRange(1, 95000000)][int]$PartBytes = 95000000
    )
    $source = Get-Item -LiteralPath $Path
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $parts = @()
    $inputStream = [IO.File]::OpenRead($source.FullName)
    $buffer = New-Object byte[] (1MB)
    try {
        $index = 0
        while ($inputStream.Position -lt $inputStream.Length) {
            $index++
            $name = '{0}.part{1:D4}' -f $source.Name, $index
            $partPath = Join-Path $OutDir $name
            $outputStream = [IO.File]::Create($partPath)
            try {
                $remaining = $PartBytes
                while ($remaining -gt 0 -and ($read = $inputStream.Read($buffer, 0, [Math]::Min($buffer.Length, $remaining))) -gt 0) {
                    $outputStream.Write($buffer, 0, $read)
                    $remaining -= $read
                }
            } finally { $outputStream.Dispose() }
            $parts += [ordered]@{ name = $name; size = (Get-Item -LiteralPath $partPath).Length; sha256 = (Get-FileHash -LiteralPath $partPath -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
    } finally { $inputStream.Dispose() }
    if (!$parts.Count) { throw 'Cannot split an empty asset.' }
    $manifest = [ordered]@{
        version = 1; name = $source.Name; size = $source.Length
        sha256 = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        parts = @($parts)
    }
    $manifestPath = Join-Path $OutDir ($source.Name + '.parts.json')
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    @($parts | ForEach-Object { Join-Path $OutDir $_.name }) + @($manifestPath)
}
