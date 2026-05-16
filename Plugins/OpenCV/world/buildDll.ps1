<#
.SYNOPSIS
    RMT 精简版 OpenCV World 编译脚本
.DESCRIPTION
    仅编译 core + imgcodecs + imgproc + highgui → 单文件 world DLL
    产物输出到 ../x64 或 ../x86 目录（无文件名后缀）
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

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "    RMT 精简版 OpenCV World 编译脚本" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "        目标架构: $Arch" -ForegroundColor Yellow

# ==================== 配置 ====================
$OpenCVVersion = "4.8.1"
$OpenCVTag = "4.8.1"
$SrcDir = Join-Path $PSScriptRoot "src\opencv"
$BuildDir = Join-Path $PSScriptRoot "build_$Arch"
$DistDir = Join-Path $PSScriptRoot "dist_$Arch"
$OutputDir = Join-Path $PSScriptRoot "..\$Arch"
$Threads = 8
$DllName = "opencv_world481.dll"

# 根据架构设置参数
if ($Arch -eq "x86") {
    $CmakeArch = "Win32"
    $VcvarsSuffix = "vcvars32.bat"
} else {
    $CmakeArch = "x64"
    $VcvarsSuffix = "vcvars64.bat"
}

# ==================== 环境检测 ====================
Write-Host ""
Write-Host "[1/6] 检测编译环境..." -ForegroundColor Green

$cmakeExe = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakeExe) {
    Write-Host "[错误] 未找到 cmake！" -ForegroundColor Red
    Write-Host "请安装 CMake 并添加到 PATH，或从 https://cmake.org/download/ 下载" -ForegroundColor Red
    Read-Host "按回车退出"; Pop-Location; exit 1
}
$cmakeVer = (& cmake --version 2>&1 | Select-Object -First 1)
Write-Host "        CMake: $cmakeVer"

$gitExe = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitExe) {
    Write-Host "[错误] 未找到 git！" -ForegroundColor Red
    Write-Host "请安装 Git 并添加到 PATH" -ForegroundColor Red
    Read-Host "按回车退出"; Pop-Location; exit 1
}
$gitVer = (& git --version 2>&1)
Write-Host "        Git:  $gitVer"

# 查找 MSVC 编译器
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
Write-Host "        MSVC: $(Split-Path (Split-Path $VcVarsBat -Parent) -Leaf)" -ForegroundColor Green

# ==================== 获取源码 ====================
Write-Host ""
Write-Host "[2/6] 检查 OpenCV 源码..." -ForegroundColor Green

if (-not (Test-Path (Join-Path $SrcDir ".git"))) {
    Write-Host "        正在克隆 OpenCV $OpenCVVersion 源码..." -ForegroundColor Yellow
    Write-Host "        （首次下载约需 2~5 分钟，取决于网络）"
    & git clone --depth 1 --branch $OpenCVTag https://github.com/opencv/opencv.git $SrcDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 克隆失败！请检查网络连接" -ForegroundColor Red
        Read-Host "按回车退出"; Pop-Location; exit 1
    }
    Write-Host "        克隆完成"
} else {
    Write-Host "        源码已存在: $SrcDir"
}

# ==================== CMake 配置 ====================
Write-Host ""
Write-Host "[3/6] CMake 配置（精简模式, $Arch）..." -ForegroundColor Green

if (-not (Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null }

Push-Location $BuildDir

$cmakeArgs = @(
    $SrcDir,
    "-A", $CmakeArch,
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_INSTALL_PREFIX=$DistDir",
    "-DBUILD_SHARED_LIBS=ON",
    "-DOPENCV_GENERATE_PKGCONFIG=OFF",
    '-DBUILD_LIST=core;imgcodecs;imgproc;highgui',
    "-DBUILD_opencv_world=ON",
    "-DBUILD_opencv_python2=OFF",
    "-DBUILD_opencv_python3=OFF",
    "-DBUILD_opencv_java=OFF",
    "-DBUILD_TESTS=OFF",
    "-DBUILD_PERF_TESTS=OFF",
    "-DBUILD_EXAMPLES=OFF",
    "-DBUILD_DOCS=OFF",
    "-DWITH_TBB=OFF",
    "-DWITH_HPX=OFF",
    "-DWITH_OPENMP=OFF",
    "-DWITH_GCD=OFF",
    "-DWITH_CONCURRENCY=OFF",
    "-DWITH_PTHREADS_PF=OFF",
    "-DWITH_OPENGL=OFF",
    "-DWITH_OPENCL=OFF",
    "-DWITH_IPP=OFF",
    "-DWITH_VTK=OFF",
    "-DWITH_QUIRC=OFF",
    "-DWITH_FFMPEG=OFF",
    "-DWITH_GSTREAMER=OFF",
    "-DWITH_DSHOW=OFF",
    "-DWITH_MSMF=OFF",
    "-DWITH_VFW=OFF",
    "-DBUILD_JPEG=ON",
    "-DBUILD_PNG=ON",
    "-DBUILD_BMP=ON",
    "-DBUILD_TIFF=OFF",
    "-DBUILD_OPENEXR=OFF",
    "-DBUILD_JASPER=OFF",
    "-DBUILD_WEBP=OFF",
    "-DBUILD_HDR=OFF",
    "-DBUILD_SUNRASTER=OFF",
    "-DBUILD_XBM=OFF",
    "-DBUILD_XPM=OFF",
    "-DBUILD_GIF=OFF",
    "-DBUILD_PXM=OFF",
    "-DENABLE_PRECOMPILED_HEADERS=ON",
    "-DENABLE_CCACHE=OFF",
    "-DCMAKE_VERBOSE_MAKEFILE=OFF"
)

& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[错误] CMake 配置失败！" -ForegroundColor Red
    Write-Host "可能的原因：" -ForegroundColor Yellow
    Write-Host "  1. 未找到 MSVC 编译器或 Windows SDK ($Arch)" -ForegroundColor Yellow
    Write-Host "  2. OpenCV 源码不完整" -ForegroundColor Yellow
    Read-Host "按回车退出"; Pop-Location; Pop-Location; exit 1
}
Write-Host "        CMake 配置完成"

# ==================== 编译 ====================
Write-Host ""
Write-Host "[4/6] 开始编译（使用 $Threads 个并行任务）..." -ForegroundColor Green
Write-Host "        这一步需要较长时间（约 10~30 分钟），请耐心等待..."

& cmake --build . --config Release --parallel $Threads
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 编译失败！" -ForegroundColor Red
    Read-Host "按回车退出"; Pop-Location; Pop-Location; exit 1
}
Write-Host "        编译成功！"

# ==================== 收集产物 ====================
Write-Host ""
Write-Host "[5/6] 收集编译产物到 $OutputDir ..." -ForegroundColor Green

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$srcDll = Join-Path $BuildDir "bin\Release\$DllName"
$dstDll = Join-Path $OutputDir $DllName
Copy-Item -Path $srcDll -Destination $dstDll -Force

# 复制 lib 文件（供 RMT_OpenCV 链接使用）
$LibName = "opencv_world481.lib"
$srcLib = Join-Path $BuildDir "lib\$LibName"
$dstLib = Join-Path $OutputDir $LibName
if (Test-Path $srcLib) {
    Copy-Item -Path $srcLib -Destination $dstLib -Force
    Write-Host "        Lib:  $dstLib"
} else {
    # 尝试 lib/Release 子目录
    $srcLib2 = Join-Path $BuildDir "lib\Release\$LibName"
    if (Test-Path $srcLib2) {
        Copy-Item -Path $srcLib2 -Destination $dstLib -Force
        Write-Host "        Lib:  $dstLib"
    } else {
        Write-Host "        [警告] 未找到 $LibName，RMT_OpenCV 将无法链接" -ForegroundColor Yellow
    }
}

# UPX 压缩
Write-Host "        正在使用 UPX 压缩..."
$upxExe = Join-Path $PSScriptRoot "..\upx.exe"
if (Test-Path $upxExe) {
    & $upxExe --best --lzma $dstDll
    if ($LASTEXITCODE -eq 0) {
        Write-Host "        UPX 压缩完成"
    } else {
        Write-Host "        [警告] UPX 压缩失败，保留未压缩文件" -ForegroundColor Yellow
    }
} else {
    Write-Host "        [警告] 未找到 UPX: $upxExe，跳过压缩" -ForegroundColor Yellow
}

Pop-Location

# ==================== 结果报告 ====================
Write-Host ""
Write-Host "[6/6] 编译结果报告" -ForegroundColor Green
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   精简版 OpenCV World 编译完成！（$Arch）" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

$fileInfo = Get-Item $dstDll -ErrorAction SilentlyContinue
if ($fileInfo) {
    $sizeMB = [math]::Round($fileInfo.Length / 1MB, 1)
    Write-Host "   文件: $DllName" -ForegroundColor White
    Write-Host "   大小: ${sizeMB} MB" -ForegroundColor White
    Write-Host "   架构: $Arch" -ForegroundColor White
}

Write-Host ""
Write-Host "   输出目录:" -ForegroundColor Gray
    Write-Host "     $OutputDir" -ForegroundColor Gray
Write-Host ""
Write-Host "   下一步:" -ForegroundColor Gray
Write-Host "     .\..\build.ps1 $Arch" -ForegroundColor Gray
Write-Host ""
Write-Host "   切换架构:" -ForegroundColor Gray
Write-Host "     .\build.ps1 x86  或  .\build.ps1 x64" -ForegroundColor Gray
Write-Host "  ============================================" -ForegroundColor Cyan

Pop-Location
