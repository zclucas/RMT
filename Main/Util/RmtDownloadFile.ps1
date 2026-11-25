# Runs in its own process so cancellation also stops network and merge work.
param([string]$Url, [string]$Path, [string]$Headers, [int]$TimeoutSec = 7200, [string]$ResourceTag = '')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
$buffer = New-Object byte[] (1MB)

function Open-Response([string]$Address, [int]$Limit = 30, $ExtraHeaders = $null) {
    $remaining = ($deadline - [DateTime]::UtcNow).TotalMilliseconds
    if ($remaining -le 0) { throw 'Download timed out.' }
    $request = [Net.HttpWebRequest]::Create($Address)
    $request.Timeout = [int][Math]::Min($Limit * 1000, $remaining)
    $request.ReadWriteTimeout = $request.Timeout
    $request.UserAgent = 'RMT-AssetDownloader/1'
    $request.AllowAutoRedirect = $true
    if ($ExtraHeaders) {
        foreach ($header in $ExtraHeaders.PSObject.Properties) {
            if ($header.Name -notmatch '^[A-Za-z0-9-]+$' -or $header.Value -isnot [string] -or $header.Value -match '[\r\n]') {
                throw 'Invalid LFS download header.'
            }
            $request.Headers[$header.Name] = $header.Value
        }
    }
    return $request.GetResponse()
}
function Get-WebException($Record) {
    $errorObject = $Record.Exception
    while ($errorObject -and !($errorObject -is [Net.WebException])) { $errorObject = $errorObject.InnerException }
    return $errorObject
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

function Expand-VerifiedArchive($Manifest) {
    $entry = $Manifest.unpacked
    $name = [Uri]::UnescapeDataString(([Uri]$Url).AbsolutePath.Split('/')[-1])
    if ($Manifest.version -ne 1 -or $Manifest.name -cne $name -or $Manifest.size -le 0 -or
        $Manifest.sha256 -cnotmatch '^[0-9a-f]{64}$' -or !$entry -or
        $entry.name -cne ($name -creplace '\.zip$', '') -or $entry.name -match '[/\\]' -or
        $entry.size -le 0 -or $entry.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid ZIP descriptor.' }
    Write-Length $entry.size
    $response = Open-Response $Url
    $output = [IO.File]::Create($Path)
    try { Copy-Response $response $output $Manifest.size } finally { $output.Dispose() }
    $inputFile = [IO.File]::OpenRead($Path)
    try {
        if ((Segment-Hash $inputFile 0 $Manifest.size) -cne $Manifest.sha256) { throw 'Archive checksum mismatch.' }
    } finally { $inputFile.Dispose() }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stage = $Path + '.unpacked'
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            if ($archive.Entries.Count -ne 1 -or $archive.Entries[0].FullName -cne $entry.name -or
                $archive.Entries[0].Length -ne $entry.size) { throw 'Unexpected model archive entry.' }
            $source = $archive.Entries[0].Open()
            $target = [IO.File]::Create($stage)
            try {
                $copied = 0L
                while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ([DateTime]::UtcNow -gt $deadline) { throw 'Download timed out.' }
                    $copied += $read
                    if ($copied -gt $entry.size) { throw 'Unexpected unpacked model length.' }
                    $target.Write($buffer, 0, $read)
                }
                if ($copied -ne $entry.size) { throw 'Truncated model archive.' }
            } finally { $source.Dispose(); $target.Dispose() }
        } finally { $archive.Dispose() }
        $inputFile = [IO.File]::OpenRead($stage)
        try {
            if ((Segment-Hash $inputFile 0 $entry.size) -cne $entry.sha256) { throw 'Model checksum mismatch.' }
        } finally { $inputFile.Dispose() }
        [IO.File]::Delete($Path)
        [IO.File]::Move($stage, $Path)
    } finally { if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) } }
}

function Receive-LfsModel($Manifest) {
    $name = [Uri]::UnescapeDataString(([Uri]$Url).AbsolutePath.Split('/')[-1])
    if ($Manifest.version -ne 1 -or $Manifest.name -cne $name -or $Manifest.size -le 0 -or
        $Manifest.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Manifest.lfs_endpoint -cne 'https://gitcode.com/ruomengtu/RMTAssets.git/info/lfs/objects/batch') {
        throw 'Invalid LFS descriptor.'
    }
    $remaining = ($deadline - [DateTime]::UtcNow).TotalMilliseconds
    if ($remaining -le 0) { throw 'Download timed out.' }
    $request = [Net.HttpWebRequest]::Create($Manifest.lfs_endpoint)
    $request.Method = 'POST'
    $request.ContentType = 'application/vnd.git-lfs+json'
    $request.Accept = 'application/vnd.git-lfs+json'
    $request.UserAgent = 'git-lfs/3.7.1 (RMT)'
    $request.Timeout = [int][Math]::Min(60000, $remaining)
    $request.ReadWriteTimeout = $request.Timeout
    $payload = @{operation='download'; transfers=@('basic'); objects=@(@{oid=$Manifest.sha256; size=$Manifest.size})} | ConvertTo-Json -Depth 6 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $request.ContentLength = $bytes.Length
    $outgoing = $request.GetRequestStream()
    try { $outgoing.Write($bytes, 0, $bytes.Length) } finally { $outgoing.Dispose() }
    $response = $request.GetResponse()
    $reader = New-Object IO.StreamReader($response.GetResponseStream())
    try {
        $json = $reader.ReadToEnd()
        if ($json.Length -gt 4MB) { throw 'LFS response too large.' }
        $batch = $json | ConvertFrom-Json
    } finally { $reader.Dispose(); $response.Dispose() }
    if ($batch.objects.Count -ne 1) { throw 'Unexpected LFS object count.' }
    $object = $batch.objects[0]
    $action = $object.actions.download
    if ($object.oid -cne $Manifest.sha256 -or $object.size -ne $Manifest.size -or !$action -or
        ([Uri]$action.href).Scheme -cne 'https') { throw 'No valid anonymous LFS download action.' }
    Write-Length $Manifest.size
    $response = Open-Response $action.href 60 $action.header
    $output = [IO.File]::Create($Path)
    try { Copy-Response $response $output $Manifest.size } finally { $output.Dispose() }
    $inputFile = [IO.File]::OpenRead($Path)
    try {
        if ((Segment-Hash $inputFile 0 $Manifest.size) -cne $Manifest.sha256) { throw 'LFS model checksum mismatch.' }
    } finally { $inputFile.Dispose() }
}

function Receive-Asset {
    # GitHub fallback always downloads the original, even when volumes are published there.
    $manifest = $null
    $address = [Uri]$Url
    if ($address.Host -eq 'gitcode.com' -and $address.AbsolutePath -like '*/releases/download/*') {
        try {
            $response = Open-Response ($Url + '.parts.json') 15
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            try {
                $json = $reader.ReadToEnd()
                if ($json.Length -gt 4MB) { throw 'Manifest too large.' }
                $manifest = $json | ConvertFrom-Json
            } finally { $reader.Dispose(); $response.Dispose() }
            if (!$manifest) { throw 'Empty manifest.' }
        } catch {
            $webError = Get-WebException $_
            if (!$webError -or !$webError.Response -or [int]$webError.Response.StatusCode -ne 404) { throw }
            $webError.Response.Dispose()
        }
    }
    if ($manifest -and $manifest.format -ceq 'lfs') {
        Receive-LfsModel $manifest
    } elseif ($manifest -and $manifest.format -ceq 'zip') {
        Expand-VerifiedArchive $manifest
    } elseif (!$manifest) {
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
                $part.size -gt 195000000 -or $part.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid volume.' }
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
}

function Get-ResourceCatalog {
    param([switch]$Refresh)
    if ($ResourceTag -cnotmatch '^v[0-9]+(\.[0-9]+)+(F[0-9]+)?_x(64|86)$') { throw 'Invalid resource version.' }
    $cache = Join-Path $PSScriptRoot ("A-Assets-$ResourceTag.json")
    if ($Refresh -and [IO.File]::Exists($cache)) { [IO.File]::Delete($cache) }
    if ([IO.File]::Exists($cache)) {
        try {
            $catalog = [IO.File]::ReadAllText($cache) | ConvertFrom-Json
            if ($catalog.schema -eq 1 -and $catalog.tag -ceq $ResourceTag -and $catalog.assets) { return $catalog }
        } catch { }
        [IO.File]::Delete($cache)
    }
    $lastError = $null
    foreach ($catalogName in @('A-Assets.json', 'resources.json')) {
        $missing = 0
        foreach ($base in @('https://gitcode.com/ruomengtu/RMTAssets/releases/download/', 'https://github.com/zclucas/RMTAssets/releases/download/')) {
            try {
                $response = Open-Response ($base + $ResourceTag + '/' + $catalogName) 20
                $reader = New-Object IO.StreamReader($response.GetResponseStream())
                try {
                    $text = New-Object Text.StringBuilder
                    $buffer = New-Object char[] 4096
                    while (($count = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        if ($text.Length + $count -gt 4MB) { throw 'Resource catalog too large.' }
                        [void]$text.Append($buffer, 0, $count)
                    }
                    $json = $text.ToString()
                } finally { $reader.Dispose(); $response.Dispose() }
                $catalog = $json | ConvertFrom-Json
                if ($catalog.schema -ne 1 -or $catalog.tag -cne $ResourceTag -or !$catalog.assets) { throw 'Invalid resource catalog.' }
                [IO.File]::WriteAllText($cache, $json)
                return $catalog
            } catch {
                $lastError = $_
                $webError = Get-WebException $_
                if ($webError -and $webError.Response) {
                    if ([int]$webError.Response.StatusCode -eq 404) { $missing++ }
                    $webError.Response.Dispose()
                }
            }
        }
        # Accept the legacy filename only after both sites confirm the new name is absent.
        if ($missing -ne 2) { break }
    }
    throw "Version resource catalog unavailable: $lastError"
}

function Receive-CatalogResource {
    param([switch]$RefreshCatalog)
    $requestedUrl = $Url
    $integrityFailed = $false
    $name = [Uri]::UnescapeDataString(([Uri]$Url).AbsolutePath.Split('/')[-1])
    $catalog = Get-ResourceCatalog -Refresh:$RefreshCatalog
    $property = $catalog.assets.PSObject.Properties | Where-Object { $_.Name -ceq $name }
    if (!$property -and $name -ceq 'Index-Translate-2B.Q4_K_M.gguf.zip') {
        $name = $name.Substring(0, $name.Length - 4)
        $property = $catalog.assets.PSObject.Properties | Where-Object { $_.Name -ceq $name }
    }
    if (!$property) { throw 'Resource is not pinned by this version.' }
    $entry = $property.Value
    if ($entry.scope -cnotin @('Common', 'Patch', $ResourceTag) -or $entry.name -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9._-]*$' -or
        $entry.size -le 0 -or $entry.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid pinned resource.' }
    $bases = @('https://gitcode.com/ruomengtu/RMTAssets/releases/download/', 'https://github.com/zclucas/RMTAssets/releases/download/')
    if (([Uri]$Url).Host -ceq 'github.com') { [array]::Reverse($bases) }
    $scopes = @(@{ Tag = $ResourceTag; Name = $name })
    if ($entry.scope -cne $ResourceTag) { $scopes += @{ Tag = $entry.scope; Name = $entry.name } }
    foreach ($scope in $scopes) {
        $failed = $null
        foreach ($base in $bases) {
            $script:Url = $base + $scope.Tag + '/' + $scope.Name
            try {
                Receive-Asset
                $file = [IO.File]::OpenRead($Path)
                try {
                    if ($file.Length -ne $entry.size -or (Segment-Hash $file 0 $entry.size) -cne $entry.sha256) {
                        throw 'Pinned resource checksum mismatch.'
                    }
                } finally { $file.Dispose() }
                return
            } catch {
                if ($_.Exception.Message -eq 'Pinned resource checksum mismatch.') { $integrityFailed = $true }
                $webError = Get-WebException $_
                $notFound = $webError -and $webError.Response -and [int]$webError.Response.StatusCode -eq 404
                if (!$notFound) { $failed = $_ }
                if ($webError -and $webError.Response) { $webError.Response.Dispose() }
                if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
            }
        }
        # Only two confirmed 404s permit moving from the version to its shared scope.
        # Transport and integrity errors may try the other mirror, never newer content.
        if ($failed) {
            if ($integrityFailed -and !$RefreshCatalog) {
                # Explicit historical cleanup can retire files and repin its ZIP.
                # Refresh once; unchanged or invalid pins still fail closed.
                $script:Url = $requestedUrl
                Receive-CatalogResource -RefreshCatalog
                return
            }
            throw $failed
        }
    }
    throw 'Pinned resource is missing from both providers.'
}

try {
    if ($ResourceTag -and $Url -match '^https://(?:gitcode\.com/ruomengtu|github\.com/zclucas)/RMTAssets/releases/download/') {
        Receive-CatalogResource
    } else {
        Receive-Asset
    }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
