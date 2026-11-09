# RMT.dll build: compile Plugins\RMT\*.cs with csc.exe (no VS class-lib project needed)
param(
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$RmtDir = $PSScriptRoot
$OutDll = Join-Path $RmtDir "RMT.dll"
$OutHelper = Join-Path $RmtDir "RMT.ExcelHelper.exe"
$ErrLog = Join-Path $env:TEMP "RMT-dll-build.log"

function Find-Csc {
    $candidates = New-Object System.Collections.Generic.List[string]
    $roots = @()
    if ($env:ProgramFiles) { $roots += $env:ProgramFiles }
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($pf86) { $roots += $pf86 }

    $years = @("2022", "2019", "2017")
    $editions = @("Enterprise", "Professional", "Community", "BuildTools")
    foreach ($root in $roots) {
        foreach ($y in $years) {
            foreach ($e in $editions) {
                $p = Join-Path $root ("Microsoft Visual Studio\{0}\{1}\MSBuild\Current\Bin\Roslyn\csc.exe" -f $y, $e)
                if (Test-Path -LiteralPath $p) { [void]$candidates.Add($p) }
            }
        }
    }

    $fw64 = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    $fw32 = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
    if (Test-Path -LiteralPath $fw64) { [void]$candidates.Add($fw64) }
    if (Test-Path -LiteralPath $fw32) { [void]$candidates.Add($fw32) }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

$csc = Find-Csc
if (-not $csc) {
    Write-Host "ERROR: csc.exe not found (.NET Framework 4.x or VS Build Tools required)" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "Press Enter" }
    exit 1
}

$fwLib = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319"
if (-not (Test-Path -LiteralPath $fwLib)) {
    $fwLib = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319"
}

$sources = @(Get-ChildItem -LiteralPath $RmtDir -Filter "*.cs" | ForEach-Object { $_.FullName })
if ($sources.Count -lt 1) {
    Write-Host "ERROR: no .cs files in $RmtDir" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "Press Enter" }
    exit 1
}

Write-Host "csc : $csc"
Write-Host "out : $OutDll"
Write-Host "src : $($sources.Count) files"

if (Test-Path -LiteralPath $OutDll) {
    try {
        Remove-Item -LiteralPath $OutDll -Force -ErrorAction Stop
    } catch {
        Write-Host "ERROR: RMT.dll is locked. Close RMT and retry." -ForegroundColor Red
        Write-Host $_.Exception.Message
        if (-not $NoPause) { Read-Host "Press Enter" }
        exit 1
    }
}

$refNames = @(
    "System.dll",
    "System.Core.dll",
    "System.Net.Http.dll",
    "System.Management.dll",
    "System.Runtime.Serialization.dll"
)
$refArgs = @()
foreach ($name in $refNames) {
    $p = Join-Path $fwLib $name
    if (Test-Path -LiteralPath $p) {
        $refArgs += "/reference:`"$p`""
    }
}

$srcArgs = @()
foreach ($s in $sources) {
    $srcArgs += "`"$s`""
}

$argList = @("/nologo", "/target:library", "/optimize+", "/out:`"$OutDll`"", "/lib:`"$fwLib`"") + $refArgs + $srcArgs
$argString = ($argList -join " ")

cmd.exe /c "`"$csc`" $argString > `"$ErrLog`" 2>&1"
$code = $LASTEXITCODE

if ((-not (Test-Path -LiteralPath $OutDll)) -or ($code -ne 0)) {
    Write-Host "ERROR: compile failed (exit $code). Log: $ErrLog" -ForegroundColor Red
    if (Test-Path -LiteralPath $ErrLog) {
        Get-Content -LiteralPath $ErrLog | Write-Host
    }
    if (-not $NoPause) { Read-Host "Press Enter" }
    exit 1
}

Write-Host "OK: $OutDll" -ForegroundColor Green

$excelSources = @($sources | Where-Object { (Split-Path -Leaf $_) -like 'Excel*.cs' } | ForEach-Object { "`"$_`"" })
$helperArgs = @("/nologo", "/target:winexe", "/main:RMT.ExcelElevation", "/optimize+", "/out:`"$OutHelper`"", "/lib:`"$fwLib`"") + $refArgs + $excelSources
cmd.exe /c "`"$csc`" $($helperArgs -join ' ') > `"$ErrLog`" 2>&1"
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $OutHelper)) {
    Write-Host "ERROR: Excel helper compilation failed. Log: $ErrLog" -ForegroundColor Red
    Get-Content -LiteralPath $ErrLog | Write-Host
    if (-not $NoPause) { Read-Host "Press Enter" }
    exit 1
}
Write-Host "OK: $OutHelper" -ForegroundColor Green
if (-not $NoPause) { Read-Host "Press Enter" }
exit 0
