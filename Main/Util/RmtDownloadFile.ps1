# Runs in its own process so cancellation also stops network and merge work.
param([string]$Url, [string]$Path, [string]$Headers, [int]$TimeoutSec = 7200)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
$buffer = New-Object byte[] (1MB)

function Open-Response([string]$Address, [int]$Limit = 30) {
    $remaining = ($deadline - [DateTime]::UtcNow).TotalMilliseconds
    if ($remaining -le 0) { throw 'Download timed out.' }
    $request = [Net.HttpWebRequest]::Create($Address)
    $request.Timeout = [int][Math]::Min($Limit * 1000, $remaining)
    $request.ReadWriteTimeout = $request.Timeout
    $request.UserAgent = 'RMT-AssetDownloader/1'
    $request.AllowAutoRedirect = $true
    return $request.GetResponse()
}
function Write-Length([long]$Length) {
    [IO.File]::WriteAllText($Headers, "HTTP/1.1 200 OK`r`nContent-Length: $Length`r`n`r`n")
}
function Copy-Response($Response, $Output, [long]$Expected = -1) {
    $stream = $Response.GetResponseStream()
    $copied = 0L
    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ([DateTime]::UtcNow -gt $deadline) { throw 'Download timed out.' }
            $copied += $read
            if ($Expected -ge 0 -and $copied -gt $Expected) { throw 'Unexpected asset length.' }
            $Output.Write($buffer, 0, $read)
        }
        if ($Expected -ge 0 -and $copied -ne $Expected) { throw 'Incomplete asset.' }
    } finally { $stream.Dispose(); $Response.Dispose() }
}
function Segment-Hash($InputFile, [long]$Offset, [long]$Length) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $InputFile.Position = $Offset
        while ($Length -gt 0) {
            $read = $InputFile.Read($buffer, 0, [int][Math]::Min($buffer.Length, $Length))
            if (!$read) { throw 'Incomplete volume.' }
            $null = $sha.TransformBlock($buffer, 0, $read, $buffer, 0)
            $Length -= $read
        }
        $null = $sha.TransformFinalBlock($buffer, 0, 0)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

try {
    # Older releases have no manifest. Only a missing manifest permits a direct download.
    $manifest = $null
    try {
        $response = Open-Response ($Url + '.parts.json') 15
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        try {
            $json = $reader.ReadToEnd()
            if ($json.Length -gt 4MB) { throw 'Manifest too large.' }
            $manifest = $json | ConvertFrom-Json
        } finally { $reader.Dispose(); $response.Dispose() }
        if (!$manifest) { throw 'Empty manifest.' }
    } catch [Net.WebException] {
        if (!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) { throw }
        $_.Exception.Response.Dispose()
    }
    if (!$manifest) {
        $response = Open-Response $Url
        Write-Length $response.ContentLength
        $output = [IO.File]::Create($Path)
        try { Copy-Response $response $output $response.ContentLength } finally { $output.Dispose() }
    } else {
        $name = [Uri]::UnescapeDataString(($Url -split '/')[-1])
        if ($manifest.version -ne 1 -or $manifest.name -cne $name -or $manifest.size -le 0 -or
            $manifest.sha256 -cnotmatch '^[0-9a-f]{64}$' -or !$manifest.parts.Count -or $manifest.parts.Count -gt 10000) {
            throw 'Invalid volume manifest.'
        }
        $total = 0L
        $index = 0
        foreach ($part in $manifest.parts) {
            $index++
            if ($part.name -cne ('{0}.part{1:D4}' -f $name, $index) -or $part.size -le 0 -or
                $part.size -gt 95000000 -or $part.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid volume.' }
            $total += $part.size
        }
        if ($total -ne $manifest.size) { throw 'Invalid total length.' }
        Write-Length $total
        $output = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        try {
            $offset = 0L
            $baseUrl = $Url.Substring(0, $Url.LastIndexOf('/') + 1)
            foreach ($part in $manifest.parts) {
                if ($output.Length -ge $offset + $part.size -and (Segment-Hash $output $offset $part.size) -ceq $part.sha256) {
                    $offset += $part.size
                    continue
                }
                # Resume only verified whole volumes. Discard the interrupted/corrupt tail.
                $output.SetLength($offset)
                $output.Position = $offset
                $response = Open-Response ($baseUrl + $part.name)
                Copy-Response $response $output $part.size
                $output.Flush()
                if ((Segment-Hash $output $offset $part.size) -cne $part.sha256) {
                    $output.SetLength($offset)
                    throw 'Volume checksum mismatch.'
                }
                $offset += $part.size
            }
            $output.SetLength($total)
            if ((Segment-Hash $output 0 $total) -cne $manifest.sha256) {
                $output.SetLength(0)
                throw 'Asset checksum mismatch.'
            }
        } finally { $output.Dispose() }
    }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
