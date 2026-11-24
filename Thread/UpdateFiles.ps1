param([int]$CleanupPid = 0, [switch]$Recover)
$ErrorActionPreference = 'Stop'

function Write-RmtUpdateProgress([string]$Phase, [string]$Percent = '', [bool]$ShowAlternative = $false) {
    $progress = "$Percent|$Phase"
    if ($ShowAlternative) { $progress += '|1' }
    try { [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'progress.txt'), $progress, [Text.Encoding]::UTF8) } catch { }
}

function Receive-RmtPackage($Job, [string]$Path) {
    Write-RmtUpdateProgress '正在下载更新包…'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $backup = if ($Job.url -like 'https://gitcode.com/ruomengtu/RMT/releases/download/*') {
        $Job.url.Replace('https://gitcode.com/ruomengtu/', 'https://github.com/zclucas/')
    }
    try { Receive-RmtPackageFromUrl $Job $Path $Job.url ([bool]$backup) }
    catch {
        if (!$backup) { throw }
        [IO.File]::Delete($Path)
        Write-RmtUpdateProgress '正在下载更新包…'
        Receive-RmtPackageFromUrl $Job $Path $backup $false
    }
}

function Receive-RmtPackageFromUrl($Job, [string]$Path, [string]$url, [bool]$hasAlternative) {
    $request = [Net.HttpWebRequest]::Create($url)
    $request.UserAgent = 'RMT-Updater'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $response = $request.GetResponse()
    try {
        if ($response.ResponseUri.Scheme -ne 'https') { throw 'Invalid download redirect.' }
        $total = [long]$Job.bytes
        if ($total -le 0) { $total = $response.ContentLength }
        $stream = $response.GetResponseStream()
        try {
            $file = [IO.File]::Open($Path, 'CreateNew', 'Write', 'None')
            try {
                $buffer = New-Object byte[] (256KB)
                $done = 0L
                $last = -1
                $lastAlternative = $false
                $timer = [Diagnostics.Stopwatch]::StartNew()
                while (($size = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($timer.Elapsed.TotalMinutes -ge 30) { throw 'Download timed out.' }
                    $file.Write($buffer, 0, $size)
                    $done += $size
                    if ($total -gt 0) {
                        if ($done -gt $total) { throw 'Unexpected package size.' }
                        $percent = [int][Math]::Floor(65 * $done / $total)
                        $elapsed = $timer.Elapsed.TotalSeconds
                        $showAlternative = $hasAlternative -and $elapsed -ge 3 -and $elapsed * ($total - $done) / $done -gt 3600
                        if ($percent -ne $last -or $showAlternative -ne $lastAlternative) {
                            Write-RmtUpdateProgress '正在下载更新包…' $percent $showAlternative
                            $last = $percent
                            $lastAlternative = $showAlternative
                        }
                    }
                }
                if (!$done -or ($total -gt 0 -and $done -ne $total)) { throw 'Incomplete package.' }
            } finally { $file.Dispose() }
        } finally { $stream.Dispose() }
    } finally { $response.Dispose() }
}

function Get-RmtPeMachine([string]$Path) {
    $reader = New-Object IO.BinaryReader([IO.File]::OpenRead($Path))
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Invalid executable: $Path" }
        $reader.BaseStream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($reader.BaseStream.Length - 6)) { throw "Invalid executable: $Path" }
        $reader.BaseStream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid executable: $Path" }
        return $reader.ReadUInt16()
    } finally { $reader.Dispose() }
}

function Assert-RmtRelativePath([string]$Relative) {
    foreach ($part in $Relative.Split('\')) {
        if (!$part -or $part -match '(^\.{1,2}$|[ .]$|[<>:"/\\|?*\x00-\x1f]|^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$))') {
            throw "Unsafe package path: $Relative"
        }
    }
}

function Get-RmtInstallPath([string]$Root, [string]$Relative) {
    Assert-RmtRelativePath $Relative
    $target = $Root
    foreach ($part in $Relative.Split('\')) {
        $target = Join-Path $target $part
        $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Package path points outside the installation: $target"
        }
    }
    return $target
}

function Expand-RmtPackage([string]$Zip, [string]$Destination, [string]$Arch, [string]$PackageName) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    if ($PackageName -notmatch '^RMTv([0-9.]+(?:F\d+)?)_(x64|x86|x32)\.zip$') { throw 'Invalid package name.' }
    $legacyExe = 'RMTv' + $Matches[1] + '.exe'
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    $files = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $wrapper = [IO.Path]::GetFileNameWithoutExtension($PackageName) + '\'
        $index = 0
        $lastPercent = -1
        foreach ($entry in $archive.Entries) {
            $index++
            $relative = $entry.FullName.Replace('/', '\')
            if ($relative.StartsWith($wrapper, [StringComparison]::OrdinalIgnoreCase)) {
                $relative = $relative.Substring($wrapper.Length)
            }
            if ($relative -eq '') { continue }
            Assert-RmtRelativePath ($relative.TrimEnd(''))
            if ($relative.EndsWith('\')) { continue }
            if ($relative -ieq $legacyExe) {
                $relative = 'RMT.exe'
            } elseif ($relative -inotin @('RMT.exe', 'index.html', 'LICENSE', 'DISCLAIMER.md', 'README.md', 'README.en.md') -and
                    $relative -notmatch '^(Audio|Images|Joy|Lang|MinTool|Plugins|Thread)\\') {
                continue
            }
            if ($relative -match '^Images\\(?:ScreenShot|FreePaste)(?:\\|$)') { continue }
            $file = Join-Path $Destination $relative
            if ($files.ContainsKey($relative)) { throw "Duplicate ZIP entry: $relative" }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $file, $false)
            $files.Add($relative, $file)
            $percent = 70 + [int][Math]::Floor(15 * $index / $archive.Entries.Count)
            if ($percent -ne $lastPercent) {
                Write-RmtUpdateProgress '正在解压更新包…' $percent
                $lastPercent = $percent
            }
        }
    } finally { $archive.Dispose() }
    $expected = if ($Arch -eq 'x64') { 0x8664 } else { 0x14C }
    foreach ($exe in @('RMT.exe', 'Thread\Work.exe')) {
        if (!$files.ContainsKey($exe) -or (Get-RmtPeMachine $files[$exe]) -ne $expected) {
            throw "Missing or incompatible package executable: $exe"
        }
    }
    return $files
}

function Write-RmtPendingPlan($Plan, [string]$Stage, [string]$UpdaterExe) {
    [IO.File]::Copy($UpdaterExe, (Join-Path $Stage 'Update.exe'))
    $temp = Join-Path $Stage 'pending.tmp'
    $data = [Text.Encoding]::UTF8.GetBytes(($Plan | ConvertTo-Json -Depth 4 -Compress))
    $stream = [IO.FileStream]::new($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try {
        $stream.Write($data, 0, $data.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    [IO.File]::Move($temp, (Join-Path $Stage 'pending.json'))
}

function Restore-RmtPackage([string]$Root, [string]$Stage, $Plan) {
    Write-RmtUpdateProgress '正在恢复原程序…'
    $backup = Join-Path $Stage 'backup'
    $staged = Join-Path $Stage 'files'
    $failed = [Collections.Generic.List[string]]::new()
    for ($i = $Plan.Files.Count - 1; $i -ge 0; $i--) {
        $row = $Plan.Files[$i]
        try {
            $target = Get-RmtInstallPath $Root $row.Relative
            $saved = Get-RmtInstallPath $backup $row.Relative
            if ([IO.File]::Exists($saved)) {
                if ([IO.File]::Exists($target)) {
                    $discard = Join-Path $Stage ('discard-' + [Guid]::NewGuid().ToString('N'))
                    [IO.File]::Replace($saved, $target, $discard)
                } else {
                    [IO.File]::Move($saved, $target)
                }
            } elseif (!$row.HadFile -and ![IO.File]::Exists((Get-RmtInstallPath $staged $row.Relative))) {
                # 已消耗的暂存文件才由这次更新创建。
                [IO.File]::Delete($target)
            }
        } catch { $failed.Add($row.Relative) }
    }
    if ($failed.Count) { throw "Restore failed: $($failed -join ', ')`nBackup: $backup" }
    [IO.File]::Delete((Join-Path $Stage 'pending.json'))
}

function Install-RmtPackage($Job, [string]$Zip, [string]$UpdaterExe) {
    $root = [IO.Path]::GetFullPath($Job.root)
    $rootItem = Get-Item -LiteralPath $root -Force
    if (!$rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Invalid installation directory: $root"
    }
    $originalName = [IO.Path]::GetFileName($Job.original)
    if ($originalName -notmatch '^RMT(?:v[\d.F]+)?\.exe$' -or
        [IO.Path]::GetFullPath($Job.original) -ine (Join-Path $root $originalName) -or
        !(Test-Path -LiteralPath $Job.original -PathType Leaf)) { throw 'RMT executable is missing.' }

    $stage = Join-Path $root ('.rmt-update-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $staged = Join-Path $stage 'files'
    $backup = Join-Path $stage 'backup'
    $pendingFile = Join-Path $stage 'pending.json'
    try {
        Write-RmtUpdateProgress '正在解压更新包…' 70
        $files = Expand-RmtPackage $Zip $staged $Job.arch $Job.name
        if ($Job.name -match '^RMTv[0-9.]+F\d+_(x64|x86|x32)\.zip$') {
            $settings = Get-RmtInstallPath $root 'Setting'
            if ([IO.Directory]::Exists($settings)) {
                Write-RmtUpdateProgress '正在备份配置…' 80
                $settingsBackup = Get-RmtInstallPath $root 'SettingOld'
                [void][IO.Directory]::CreateDirectory($settingsBackup)
                $stagedSettings = Join-Path $stage 'Setting'
                Copy-Item -LiteralPath $settings -Destination $stagedSettings -Recurse -Force
                $backupName = 'Update-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
                [IO.Directory]::Move($stagedSettings, (Join-Path $settingsBackup $backupName))
            }
        }
        $pending = @($files.Keys | Where-Object { $_ -ine 'RMT.exe' } | Sort-Object) + @('RMT.exe')
        if ($originalName -ine 'RMT.exe') { $pending += $originalName }
        $plan = @{ Original = $originalName; Texts = $Job.texts; Files = @(foreach ($relative in $pending) {
            $target = Get-RmtInstallPath $root $relative
            @{ Relative = $relative; HadFile = [IO.File]::Exists($target) }
        }) }
        # 先落盘替换清单和恢复程序，再写入安装目录。
        Write-RmtPendingPlan $plan $stage $UpdaterExe

        $done = 0
        $lastPercent = -1
        foreach ($row in $plan.Files) {
            $relative = $row.Relative
            $target = Get-RmtInstallPath $root $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $saved = Join-Path $backup $relative
            if ($row.HadFile) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved)) }
            if (!$files.ContainsKey($relative)) {
                [IO.File]::Move($target, $saved)
            } elseif ($row.HadFile) {
                [IO.File]::Replace($files[$relative], $target, $saved)
            } else {
                [IO.File]::Move($files[$relative], $target)
            }
            $done++
            $percent = 85 + [int][Math]::Floor(15 * $done / $pending.Count)
            if ($percent -ne $lastPercent) {
                Write-RmtUpdateProgress '正在替换程序文件…' $percent
                $lastPercent = $percent
            }
        }
        [IO.File]::Delete($pendingFile)
    } catch {
        $problem = $_
        if ([IO.File]::Exists($pendingFile)) {
            try { Restore-RmtPackage $root $stage $plan } catch {
                [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'rollback-failed'), $stage)
                throw "$problem`n$($_.Exception.Message)"
            }
        }
        throw $problem
    } finally {
        if (![IO.File]::Exists($pendingFile)) {
            try { [IO.Directory]::Delete($stage, $true) } catch { }
        }
    }
}

function Save-RmtPackage([string]$Zip, [string]$Path, [bool]$Overwrite) {
    $part = $Path + '.rmt-part-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::Copy($Zip, $part)
        if ($Overwrite -and [IO.File]::Exists($Path)) {
            [IO.File]::Replace($part, $Path, $part + '.backup')
        } else {
            [IO.File]::Move($part, $Path)
        }
    } finally {
        if ([IO.File]::Exists($part)) { [IO.File]::Delete($part) }
        if ([IO.File]::Exists($part + '.backup')) { [IO.File]::Delete($part + '.backup') }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $stageDir = Get-Item -LiteralPath $PSScriptRoot -Force
    if ($CleanupPid -gt 0) {
        $parentDir = $stageDir.Parent.FullName
        if ($stageDir.Name -match '^\.rmt-update-[a-f0-9]{32}$') {
            $managed = [IO.File]::Exists((Join-Path $PSScriptRoot 'success')) -and
                ![IO.File]::Exists((Join-Path $PSScriptRoot 'pending.json'))
        } else {
            $job = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'job.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $cache = Join-Path ([IO.Path]::GetFullPath($job.root)) 'Cache'
            $managed = $parentDir -ieq $cache -and $stageDir.Name -match '^RMT-Update-\d+-\d+-\d+$'
        }
        if ($managed -and !($stageDir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $process = Get-Process -Id $CleanupPid -ErrorAction SilentlyContinue
            if (!$process -or $process.WaitForExit(60000)) {
                Set-Location -LiteralPath $parentDir
                [Environment]::CurrentDirectory = $parentDir
                [IO.Directory]::Delete($stageDir.FullName, $true)
            }
        }
        exit
    }
    $guard = $null
    try {
        if ($Recover) {
            $guard = [Threading.Mutex]::OpenExisting('Local\RMT_AppUpdate', [Security.AccessControl.MutexRights]::Synchronize)
            if ($stageDir.Name -notmatch '^\.rmt-update-[a-f0-9]{32}$' -or
                ($stageDir.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid recovery directory.' }
            $plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pending.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            Restore-RmtPackage $stageDir.Parent.FullName $PSScriptRoot $plan
        } else {
            $job = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'job.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($job.mode -eq 'replace') {
                # 即使进度窗口进程意外退出，实际替换进程仍持有启动保护。
                $guard = [Threading.Mutex]::OpenExisting('Local\RMT_AppUpdate', [Security.AccessControl.MutexRights]::Synchronize)
            }
            $zip = Join-Path $PSScriptRoot 'download.zip'
            Receive-RmtPackage $job $zip
            Write-RmtUpdateProgress '正在验证更新包…' 65
            if ($job.digest -and (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $job.digest) {
                throw 'SHA-256 mismatch.'
            }
            if ($job.mode -eq 'replace') {
                Install-RmtPackage $job $zip (Join-Path $PSScriptRoot 'Update.exe')
            } else {
                Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
                $archive = [IO.Compression.ZipFile]::OpenRead($zip)
                try {
                    if (!$archive.Entries.Count) { throw 'Empty package.' }
                } finally { $archive.Dispose() }
                Save-RmtPackage $zip $job.path ([bool]$job.overwrite)
            }
        }
        [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'success'), '')
    } catch {
        [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'error.txt'), $_.Exception.Message, [Text.Encoding]::UTF8)
        exit 1
    } finally {
        if ($guard) { $guard.Dispose() }
    }
}
