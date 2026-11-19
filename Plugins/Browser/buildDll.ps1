param(
    [ValidateSet("x64", "x86")]
    [string]$Arch = "x64",
    # 可传入本地 CDP-for-CPP 源码目录进行离线构建。
    [string]$CdpSource = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$source = if ($CdpSource) { (Resolve-Path -LiteralPath $CdpSource).Path } else { "" }
$build = Join-Path $repo "Test\output\browser-native-$Arch"
$cmake = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if (!$cmake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $cmake = & $vswhere -latest -products '*' -find 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' | Select-Object -First 1
    }
}
if (!$cmake) { throw "CMake was not found." }
$platform = if ($Arch -eq "x86") { "Win32" } else { "x64" }
& $cmake -S $PSScriptRoot -B $build -A $platform "-DCDP_SOURCE_DIR=$source"
if ($LASTEXITCODE) { throw "CMake configuration failed ($LASTEXITCODE)" }
& $cmake --build $build --config Release --target RMT_Browser --parallel 4
if ($LASTEXITCODE) { throw "Browser DLL build failed ($LASTEXITCODE)" }

$destination = if ($Arch -eq "x86") { Join-Path $PSScriptRoot "x86" } else { $PSScriptRoot }
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath "$build\Release\RMT_Browser.dll" -Destination $destination -Force
