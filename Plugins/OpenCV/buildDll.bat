@echo off
chcp 65001 >nul

:: ---- 切换到脚本所在目录（确保相对路径正确）----
pushd "%~dp0"

echo ========================================
echo   RMT_OpenCv DLL 编译脚本 (MSVC)
echo ========================================

:: ---- 配置项（优先从环境变量读取）----
:: OPENCV_DIR 应指向 OpenCV 的 build 目录（如 C:\opencv\build）
if not defined OPENCV_DIR set "OPENCV_DIR=C:\opencv\build"
set "SRC_DIR=."
set "BUILD_DIR=.\build"
set "OUT_DIR=%BUILD_DIR%\Release"

:: ---- 查找 MSVC 编译器（支持 VS 2015~2026）----
set "VCTOOLS="
for %%v in (18 17 16 15 2019 2017) do (
    if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCTOOLS=%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    )
    if exist "%ProgramFiles%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCTOOLS=%ProgramFiles%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
    :: 部分路径是这样的
    if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCTOOLS=%ProgramFiles(x86)%\Microsoft Visual Studio\%%v\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
)
if defined VCTOOLS (
    call "%VCTOOLS%" >nul 2>&1
    echo [OK] MSVC 编译器已就绪
) else (
    echo [错误] 未找到 MSVC 编译器！
    echo 请安装 Build Tools 并勾选「使用 C++ 的桌面开发」
    popd
    exit /b 1
)

:: ---- 创建目录 ----
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo.
echo [1/3] 正在编译 RMT_OpenCv.cpp ...

cl /c /EHsc /std:c++17 /O2 /MD /utf-8 ^
   /D "WIN32" /D "_WINDOWS" /D "NDEBUG" /D "IMAGEFINDER_EXPORTS" ^
   /I "%OPENCV_DIR%\include" ^
   /Fo"%BUILD_DIR%\RMT_OpenCv.obj" "%SRC_DIR%\RMT_OpenCv.cpp"

if %ERRORLEVEL% neq 0 (
    echo [错误] 编译失败！
    goto :cleanup
)

echo.
echo [2/3] 正在链接 RMT_OpenCv.dll ...

link /DLL /MACHINE:x64 /OUT:"%OUT_DIR%\RMT_OpenCv.dll" ^
   "%BUILD_DIR%\RMT_OpenCv.obj" ^
   "%OPENCV_DIR%\x64\vc16\lib\opencv_world481.lib" ^
   Dwmapi.lib kernel32.lib user32.lib gdi32.lib winspool.lib shell32.lib ^
   ole32.lib oleaut32.lib uuid.lib comdlg32.lib advapi32.lib

if %ERRORLEVEL% neq 0 (
    echo [错误] 链接失败！
    goto :cleanup
)

echo.
echo ========================================
echo   编译成功！输出路径：
echo   %~dp0%OUT_DIR%\RMT_OpenCv.dll
echo ========================================
goto :cleanup

:cleanup
echo [清理] 删除中间文件...
del /q "%BUILD_DIR%\RMT_OpenCv.obj" >nul 2>&1
echo       已清理完毕
popd
