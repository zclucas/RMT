function Get-VoiceModelUrls([string]$FileName) {
    $direct = "https://github.com/zclucas/RMTAssets/releases/download/Common/$FileName"
    "https://ghfile.geekertao.top/$direct"
    $direct
}

function Receive-VoiceDependency([string[]]$Urls, [string]$Destination) {
    $part = "$Destination.$([guid]::NewGuid()).part"
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    try {
        foreach ($url in $Urls) {
            Write-Host "       $url" -ForegroundColor DarkGray
            try {
                if ($curl) {
                    & $curl -fLsS --connect-timeout 12 --max-time 600 -o $part $url
                    if ($LASTEXITCODE -ne 0) { throw "curl $LASTEXITCODE" }
                } else {
                    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
                }
                if ((Get-Item -LiteralPath $part).Length -le 1MB) { throw '下载文件不完整' }
            } catch {
                Write-Warning "$url — $($_.Exception.Message)"
                continue
            }
            Move-Item -LiteralPath $part -Destination $Destination -Force
            return
        }
        throw "下载失败：$Destination"
    } finally {
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
    }
}
