<#
.SYNOPSIS
    RMT_OpenCv DLL 编译脚本 (MSVC)
.DESCRIPTION
    产物输出到 ./x64 或 ./x86 目录（无文件名后缀）
.PARAMETER Arch
    目标架构: x86 或 x64，默认 x64
.EXAMPLE
    .\build.ps1 x86
    .\build.ps1 x64
#>

param(
    [ValidateSet("x86", "x64")]
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RMT_OpenCv DLL 编译脚本 (MSVC)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "        目标架构: $Arch" -ForegroundColor Yellow

# ==================== 根据架构设置参数 ====================
if ($Arch -eq "x86") {
    $Machine = "x86"
    $VcvarsSuffix = "vcvars32.bat"
} else {
    $Machine = "x64"
    $VcvarsSuffix = "vcvars64.bat"
}

# 输出目录和文件
$OutputDir = Join-Path $PSScriptRoot $Arch
$OutDll = Join-Path $OutputDir "RMT_OpenCV.dll"

# OpenCV 路径（优先本地 x86/x64 目录，其次环境变量）
$localLibDir = Join-Path $PSScriptRoot $Arch
$localLib = Join-Path $localLibDir "opencv_world481.lib"
if (Test-Path $localLib) {
    $opencvLib = $localLib
} elseif ($env:OPENCV_DIR) {
    $opencvLib = Join-Path (Join-Path $env:OPENCV_DIR "$Arch\vc16\lib") "opencv_world481.lib"
} else {
    $opencvLib = Join-Path "C:\opencv\build\$Arch\vc16\lib" "opencv_world481.lib"
}
# include 路径（本地优先，其次环境变量，最后默认）
$includeDir = $null
$candidateIncludes = @(
    Join-Path $PSScriptRoot "..\..\opencv\build\include"
)
if ($env:OPENCV_INCLUDE) { $candidateIncludes += $env:OPENCV_INCLUDE }
if ($env:OPENCV_DIR) { $candidateIncludes += (Join-Path $env:OPENCV_DIR "include") }
$candidateIncludes += "C:\opencv\build\include"
foreach ($dir in $candidateIncludes) {
    if ($dir -and (Test-Path $dir)) {
        $includeDir = $dir
        break
    }
}
if (-not $includeDir) { $includeDir = "C:\opencv\build\include" }

# 源文件和构建目录
$SrcFile = Join-Path $PSScriptRoot "RMT_OpenCv.cpp"
$BuildDir = Join-Path $PSScriptRoot "build_$Arch"
$OutDir = Join-Path $BuildDir "Release"

# ==================== 查找 MSVC 编译器 ====================
$vcvarsPaths = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio",
    "${env:ProgramFiles}\Microsoft Visual Studio"
)
$vsVersions = @(18, 17, 16, 15, "2019", "2017")
$vsEditions = @("BuildTools", "Community", "Professional")
$VcVarsBat = $null

foreach ($vsBase in $vcvarsPaths) {
    foreach ($ver in $vsVersions) {
        foreach ($edition in $vsEditions) {
            $candidate = Join-Path $vsBase "$ver\$edition\VC\Auxiliary\Build\$VcvarsSuffix"
            if (Test-Path $candidate) {
                $VcVarsBat = $candidate
                break
            }
        }
        if ($VcVarsBat) { break }
    }
    if ($VcVarsBat) { break }
}

if (-not $VcVarsBat) {
    Write-Host "[错误] 未找到 MSVC $Arch 编译器！" -ForegroundColor Red
    Write-Host "请安装 Build Tools 并勾选「使用 C++ 的桌面开发」($Arch 支持)" -ForegroundColor Red
    Read-Host "按回车退出"; Pop-Location; exit 1
}
Write-Host "[OK] MSVC 编译器已就绪 ($Arch)" -ForegroundColor Green

# ==================== 检查 OpenCV lib ====================
if (-not (Test-Path $opencvLib)) {
    Write-Host "[错误] 未找到 OpenCV lib 文件！" -ForegroundColor Red
    Write-Host "  期望路径: $opencvLib" -ForegroundColor Red
    Write-Host ""
    Write-Host "请先运行 world\build.ps1 $Arch 编译 $Arch 版本的 OpenCV World" -ForegroundColor Yellow
    Read-Host "按回车退出"; Pop-Location; exit 1
}
Write-Host "[OK] OpenCV lib: $opencvLib" -ForegroundColor Green
Write-Host "[OK] Include:   $includeDir" -ForegroundColor Green

# ==================== 创建目录 ====================
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# ==================== 构建编译命令（通过 cmd 调用 vcvars） ====================
$objFile = Join-Path $BuildDir "RMT_OpenCv.obj"

Write-Host ""
Write-Host "[1/3] 正在编译 RMT_OpenCv.cpp ($Arch) ..." -ForegroundColor Green

$compileCmd = @"
chcp 65001 >nul && call "$VcVarsBat" >nul 2>&1 && cl /c /EHsc /std:c++17 /O2 /MD /utf-8 /D "WIN32" /D "_WINDOWS" /D "NDEBUG" /D "IMAGEFINDER_EXPORTS" /I "$includeDir" /Fo"$objFile" "$SrcFile"
"@

cmd /c $compileCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 编译失败！" -ForegroundColor Red
    Read-Host "按回车退出"; Pop-Location; exit 1
}

Write-Host ""
Write-Host "[2/3] 正在链接 RMT_OpenCv.dll ($Arch) ..." -ForegroundColor Green

$linkCmd = @"
chcp 65001 >nul && call "$VcVarsBat" >nul 2>&1 && link /DLL /MACHINE:$Machine /OUT:"$OutDir\RMT_OpenCV.dll" "$objFile" "$opencvLib" Dwmapi.lib kernel32.lib user32.lib gdi32.lib winspool.lib shell32.lib ole32.lib oleaut32.lib uuid.lib comdlg32.lib advapi32.lib
"@

cmd /c $linkCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 链接失败！" -ForegroundColor Red
    Read-Host "按回车退出"; Pop-Location; exit 1
}

# ==================== 复制到目标文件夹 ====================
Copy-Item -Path "$OutDir\RMT_OpenCV.dll" -Destination $OutDll -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  编译成功！（$Arch）" -ForegroundColor Green
Write-Host "  输出: $OutDll" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# 清理中间文件
Remove-Item -Path $objFile -ErrorAction SilentlyContinue
Write-Host "        中间文件已清理"

Read-Host "按回车退出"
Pop-Location
