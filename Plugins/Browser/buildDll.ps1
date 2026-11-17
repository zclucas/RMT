param(
    [ValidateSet("x64")]
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$CdpInclude = "c:\sundry\project\RMT\Test\reference\CDP-for-CPP\include"
$CdpLib = "c:\sundry\project\RMT\Test\reference\CDP-for-CPP\build\Release\cdp.lib"

$OutputDir = $ScriptDir
$OutDll = Join-Path $OutputDir "RMT_Browser.dll"

$vcvars = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    Write-Error "vcvars64.bat not found"
}

$SrcFile = Join-Path $ScriptDir "RMT_Browser.cpp"
$ObjFile = Join-Path $ScriptDir "RMT_Browser.obj"

Write-Host "Compiling RMT_Browser.cpp..." -ForegroundColor Cyan
$compileCmd = @"
chcp 65001 >nul && call "$vcvars" >nul 2>&1 && cl /c /EHsc /std:c++latest /O2 /MD /utf-8 /D "WIN32" /D "_WINDOWS" /D "NDEBUG" /D "BROWSER_EXPORTS" /I "$CdpInclude" /Fo"$ObjFile" "$SrcFile"
"@

cmd /c $compileCmd
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed"
}

Write-Host "Linking RMT_Browser.dll..." -ForegroundColor Cyan
$linkCmd = @"
chcp 65001 >nul && call "$vcvars" >nul 2>&1 && link /DLL /MACHINE:X64 /OUT:"$OutDll" "$ObjFile" "$CdpLib" ws2_32.lib crypt32.lib shell32.lib ole32.lib advapi32.lib kernel32.lib user32.lib
"@

cmd /c $linkCmd
if ($LASTEXITCODE -ne 0) {
    Write-Error "Linking failed"
}

Write-Host "Build succeeded: $OutDll" -ForegroundColor Green

# Copy to ReleaseX64\Plugins\Browser
$ReleasePluginDir = "c:\sundry\project\RMT\ReleaseX64\Plugins\Browser"
if (-not (Test-Path $ReleasePluginDir)) {
    New-Item -ItemType Directory -Path $ReleasePluginDir -Force | Out-Null
}
Copy-Item -Path $OutDll -Destination $ReleasePluginDir -Force
Write-Host "Copied to $ReleasePluginDir" -ForegroundColor Green
