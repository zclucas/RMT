@echo off
chcp 65001 >nul 2>nul
setlocal EnableDelayedExpansion

:: ============================================================
::   RMT 精简版 OpenCV World 编译脚本
::   目标: 仅编译 core + imgcodecs + imgproc → 单文件 world DLL
::   预期产出: ~10-15 MB (vs 原版 60 MB)
::   用法: 双击运行 或 cmd 中执行 build.bat
:: ============================================================

pushd "%~dp0"

echo.
echo  ============================================
echo    RMT 精简版 OpenCV World 编译脚本
echo  ============================================
echo.

:: ==================== 配置区 ====================
set "OPENCV_VERSION=4.8.1"
set "OPENCV_TAG=4.8.1"
set "SRC_DIR=%~dp0src\opencv"
set "BUILD_DIR=%~dp0build"
set "DIST_DIR=%~dp0dist"
set "THREADS=8"

:: ==================== 环境检测 ====================

echo [1/6] 检测编译环境...

:: 检测 CMake
where cmake >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 cmake！
    echo 请安装 CMake 并添加到 PATH，或从 https://cmake.org/download/ 下载
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('cmake --version 2^>^&1') do set "CMAKE_VER=%%i" & goto :got_cmake
:got_cmake
echo        CMake: %CMAKE_VER%

:: 检测 Git（用于克隆源码）
where git >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 git！
    echo 请安装 Git 并添加到 PATH
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('git --version 2^>^&1') do set "GIT_VER=%%i" & goto :got_git
:got_git
echo        Git:  %GIT_VER%

:: ---- 查找 MSVC 编译器（支持 VS 2015~2026）----
:: 参考 buildDll.bat 的检测逻辑
set "VCVARS="
for %%v in (18 17 16 15 2019 2017) do (
    if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    )
    if exist "%ProgramFiles%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCVARS=%ProgramFiles%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
    :: 部分路径是这样的
    if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
)
if defined VCVARS (
    call "%VCVARS%" >nul 2>&1
    echo [OK] MSVC 编译器已就绪

    :: 根据 VS 版本自动选择 CMake Generator
    for /f "tokens=3" %%g in ('findstr /C:"Visual Studio" "%VCVARS%" 2^>nul') do (
        echo        VS: %%g
    )

) else (
    echo [错误] 未找到 MSVC 编译器！
    echo 请安装 Build Tools 并勾选「使用 C++ 的桌面开发」
    pause
    exit /b 1
)

:: ==================== 获取源码 ====================
echo.
echo [2/6] 检查 OpenCV 源码...

if not exist "%SRC_DIR%\.git" (
    echo        正在克隆 OpenCV %OPENCV_VERSION% 源码...
    echo        （首次下载约需 2~5 分钟，取决于网络）
    git clone --depth 1 --branch %OPENCV_TAG% https://github.com/opencv/opencv.git "%SRC_DIR%"
    if %ERRORLEVEL% neq 0 (
        echo [错误] 克隆失败！请检查网络连接
        pause
        exit /b 1
    )
    echo        克隆完成
) else (
    echo        源码已存在: %SRC_DIR%
)

:: ==================== CMake 配置 ====================
echo.
echo [3/6] CMake 配置（精简模式）...

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

cd /d "%BUILD_DIR%"

cmake "%SRC_DIR%" ^
    -A x64 ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%DIST_DIR%" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DOPENCV_GENERATE_PKGCONFIG=OFF ^
    -DBUILD_LIST="core;imgcodecs;imgproc;highgui" ^
    -DBUILD_opencv_world=ON ^
    -DBUILD_opencv_python2=OFF ^
    -DBUILD_opencv_python3=OFF ^
    -DBUILD_opencv_java=OFF ^
    -DBUILD_TESTS=OFF ^
    -DBUILD_PERF_TESTS=OFF ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_DOCS=OFF ^
    -DWITH_TBB=OFF ^
    -DWITH_HPX=OFF ^
    -DWITH_OPENMP=OFF ^
    -DWITH_GCD=OFF ^
    -DWITH_CONCURRENCY=OFF ^
    -DWITH_PTHREADS_PF=OFF ^
    -DWITH_OPENGL=OFF ^
    -DWITH_OPENCL=OFF ^
    -DWITH_IPP=OFF ^
    -DWITH_VTK=OFF ^
    -DWITH_QUIRC=OFF ^
    -DWITH_FFMPEG=OFF ^
    -DWITH_GSTREAMER=OFF ^
    -DWITH_DSHOW=OFF ^
    -DWITH_MSMF=OFF ^
    -DWITH_VFW=OFF ^
    -DBUILD_JPEG=ON ^
    -DBUILD_PNG=ON ^
    -DBUILD_BMP=ON ^
    -DBUILD_TIFF=OFF ^
    -DBUILD_OPENEXR=OFF ^
    -DBUILD_JASPER=OFF ^
    -DBUILD_WEBP=OFF ^
    -DBUILD_HDR=OFF ^
    -DBUILD_SUNRASTER=OFF ^
    -DBUILD_XBM=OFF ^
    -DBUILD_XPM=OFF ^
    -DBUILD_GIF=OFF ^
    -DBUILD_PXM=OFF ^
    -DBUILD_PFMOFF=OFF ^
    -DENABLE_PRECOMPILED_HEADERS=ON ^
    -DENABLE_CCACHE=OFF ^
    -DCMAKE_VERBOSE_MAKEFILE=OFF

if %ERRORLEVEL% neq 0 (
    echo.
    echo [错误] CMake 配置失败！
    echo 可能的原因：
    echo   1. 未找到 MSVC 编译器或 Windows SDK
    echo   2. OpenCV 源码不完整
    pause
    cd /d "%~dp0"
    exit /b 1
)

echo        CMake 配置完成

:: ==================== 编译 ====================
echo.
echo [4/6] 开始编译（使用 %THREADS% 个并行任务）...
echo        这一步需要较长时间（约 10~30 分钟），请耐心等待...
echo.

cmake --build . --config Release --parallel %THREADS%

if %ERRORLEVEL% neq 0 (
    echo [错误] 编译失败！
    pause
    cd /d "%~dp0"
    exit /b 1
)

echo        编译成功！

:: ==================== 收集产物 ====================
echo.
echo [5/6] 收集编译产物...

:: 复制 dll（在 bin/Release 下）
copy /y "%BUILD_DIR%\bin\Release\opencv_world481.dll" "%~dp0..\" >nul 2>&1

:: UPX 压缩
echo        正在使用 UPX 压缩...
set "UPX_EXE=%~dp0..\..\upx.exe"
if exist "%UPX_EXE%" (
    "%UPX_EXE%" --best --lzma "%~dp0..\opencv_world481.dll"
    if !ERRORLEVEL! equ 0 (
        echo        UPX 压缩完成
    ) else (
        echo        [警告] UPX 压缩失败，保留未压缩文件
    )
) else (
    echo        [警告] 未找到 UPX: %UPX_EXE%，跳过压缩
)

echo        产物已收集到 %~dp0..\

:: ==================== 结果报告 ====================
echo.
echo [6/6] 编译结果报告
echo.
echo  ============================================
echo   精简版 OpenCV World 编译完成！
echo  ============================================
echo.

for %%F in ("%~dp0..\opencv_world481.dll") do (
    set "SIZE=%%~zF"
    set /a "SIZE_MB=!SIZE! / 1048576"
    set /a "SIZE_KB=(!SIZE! %% 1048576) / 1024"
    echo   文件: opencv_world481.dll
    echo   大小: !SIZE_MB!.!SIZE_KB! MB
)

echo.
echo   输出目录:
echo     DLL: %~dp0..\
echo.
echo   使用方法:
echo     1. 运行 buildDll.bat 重新编译 RMT_OpenCV.dll
echo.
echo  ============================================

cd /d "%~dp0"
endlocal
