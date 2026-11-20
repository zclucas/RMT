<#
.SYNOPSIS
    RMT TranslateDll 一键编译部署脚本 (MSVC + CMake + Ninja)
.DESCRIPTION
    Plugins\Translate 自包含构建布局：
      src\            源码（TranslateDll.cpp + TranslateDll.h）
      x64\            运行库产物（TranslateDll.dll + llama/ggml 运行库 + CPU 变体 + GPU 后端 ggml-vulkan.dll，均入库）
      models\         GGUF 模型（跨架构共享，1.3 GB，不进仓库，按需下载）
      third_party\    llama.cpp 源码与 CMake 构建目录（git 忽略）

    llama.cpp 以共享库方式构建：llama.dll / ggml.dll / ggml-base.dll 与
    TranslateDll.dll 同目录分发（LOAD_WITH_ALTERED_SEARCH_PATH 保证依赖
    从本目录解析），不会跟 Plugins\Voice 那份 onnxruntime.dll 争抢同名依赖。
    CPU 计算后端用 GGML_BACKEND_DL 拆成 ggml-cpu-<variant>.dll 运行时加载，
    按机器的指令集（SSE4.2 / AVX / AVX2 …）自动挑选变体，旧机器落 baseline。
    GGML_BACKEND_DL 强制 BUILD_SHARED_LIBS=ON：ggml-base 必须是共享的，
    否则每个后端 DLL 各自内嵌一份静态 ggml-base，运行时两份状态必崩。
    代价是构建要跑一遍 CMake（首次 3~8 分钟），之后改 C++ 只重编封装这一层。

    GPU 后端不走本机构建：Vulkan 要把 200 多个着色器 × 6 种变体用 glslc 现编成
    SPIR-V 嵌进 ggml-vulkan.dll（43 MB），耗时 20~40 分钟且本机 glslc 并发调用
    会挂死。改为直接用官方同版本（b12540）发布包里的 ggml-vulkan.dll，放在 x64\
    并入库；本机构建不产出也不覆盖，误删从 git 还原。它只依赖 ggml-base.dll +
    vulkan-1.dll，无需额外运行库。

    编译器环境不调 vcvars64.bat：那套脚本靠 reg.exe 探测安装，受限环境里会半途失败，
    表现为「找不到 cl.exe / rc.exe」。这里直接按目录拼 PATH/INCLUDE/LIB，结果可复现。
.EXAMPLE
    .\buildDll.ps1                  ; 下载源码 + CMake 编共享库 + 编译部署
    .\buildDll.ps1 -SkipModel       ; 不下载 GGUF（只编 DLL）
    .\buildDll.ps1 -SkipLlamaBuild  ; 复用已编好的共享库，只重编 TranslateDll.cpp
    .\buildDll.ps1 -NoPause         ; 结束后不等待按键
.PARAMETER SkipModel
    跳过 GGUF 模型（约 1.3 GB）的下载部署。只改 C++ 代码时用。
    需要模型时单独跑 .\GetTranslateModel.ps1。
.PARAMETER SkipLlamaBuild
    跳过 llama.cpp 共享库构建，直接链接上次的产物。改封装层代码时用。
#>

param(
    [switch]$NoPause,
    [switch]$SkipModel,
    [switch]$SkipLlamaBuild
)

$ErrorActionPreference = "Stop"
$TransDir = $PSScriptRoot

# ==================== 版本常量（升级时只改这里） ====================
# llama.cpp 用 tag 固定版本：llama.h 的 C API 在小版本间也会改签名，
# 升级时先看 src\TranslateDll.cpp 里用到的函数有没有变。
$LlamaTag   = "b12540"
$LlamaRepo  = "https://github.com/ggml-org/llama.cpp"
$GhProxy    = "https://gh-proxy.com/"      # release / codeload 直连慢时走代理
$ModelName  = "Index-Translate-2B.Q4_K_M.gguf"
$ModelRepo  = "IndexTeam/Index-Translate-2B-GGUF"
$ModelUrlMs = "https://modelscope.cn/models/$ModelRepo/resolve/master/$ModelName"
$ModelUrlHf = "https://huggingface.co/$ModelRepo/resolve/main/$ModelName"
$ModelMinBytes = 1200MB    # 小于这个数说明是半包，重新下

# ==================== 目录 ====================
$DepDir    = Join-Path $TransDir "third_party"
$DlDir     = Join-Path $DepDir "downloads"
$SrcDir    = Join-Path $DepDir "llama.cpp-$LlamaTag"
$BuildDir  = Join-Path $DepDir "build_x64"
$RunDir    = Join-Path $TransDir "x64"
$ModelDir  = Join-Path $TransDir "models"
$SrcCpp    = Join-Path $TransDir "src\TranslateDll.cpp"
$SrcH      = Join-Path $TransDir "src\TranslateDll.h"
$OutDll    = Join-Path $RunDir "TranslateDll.dll"
New-Item -ItemType Directory -Force -Path $DepDir, $DlDir, $RunDir, $ModelDir | Out-Null

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RMT TranslateDll 编译部署 (x64)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SrcCpp)) { Write-Host "[错误] 未找到源码: $SrcCpp" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
if (-not (Test-Path $SrcH))   { Write-Host "[错误] 未找到头文件: $SrcH" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
Write-Host "[OK] 源码就位" -ForegroundColor Green

# ==================== 下载工具 ====================
function Invoke-Download($Urls, $Dest, $Label, [int64]$MinBytes = 1MB) {
    if (Test-Path $Dest) {
        $sz = (Get-Item $Dest).Length
        if ($sz -ge $MinBytes) { Write-Host "[OK] $Label 已缓存: $([math]::Round($sz/1MB,1)) MB" -ForegroundColor Green; return }
        Write-Host "[警告] $Label 缓存不完整（$([math]::Round($sz/1MB,1)) MB），重新下载" -ForegroundColor Yellow
        Remove-Item $Dest -Force
    }
    foreach ($u in $Urls) {
        Write-Host "[下载] $Label ← $u" -ForegroundColor Yellow
        try {
            # --ssl-no-revoke：部分环境的证书吊销检查会直接失败（CRYPT_E_NO_REVOCATION_CHECK）
            & curl.exe -L --ssl-no-revoke --retry 3 --retry-delay 2 --max-time 3600 -o $Dest $u
            if ((Test-Path $Dest) -and ((Get-Item $Dest).Length -ge $MinBytes)) {
                Write-Host "[OK] $Label 下载完成 ($([math]::Round((Get-Item $Dest).Length/1MB,1)) MB)" -ForegroundColor Green
                return
            }
            Write-Host "[失败] 该源不可用，换下一个" -ForegroundColor Yellow
            if (Test-Path $Dest) { Remove-Item $Dest -Force }
        } catch {
            Write-Host "[失败] $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host "[错误] $Label 下载失败，请手动放置到: $Dest" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}

function Expand-Zip($Zip, $Target) {
    $mark = Join-Path $Target (".ok_" + [IO.Path]::GetFileNameWithoutExtension($Zip))
    if (Test-Path $mark) { return }
    Write-Host "[解压] $([IO.Path]::GetFileName($Zip)) ..." -ForegroundColor Yellow
    Expand-Archive -Path $Zip -DestinationPath $Target -Force
    if (-not (Test-Path $Target)) { Write-Host "[错误] 解压失败" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
    Set-Content -Path $mark -Value "done"
}

# ==================== 源码 ====================
if (-not (Test-Path $SrcDir)) {
    $srcZip = Join-Path $DlDir "llama-$LlamaTag.zip"
    Invoke-Download @(
        "$GhProxy$LlamaRepo/archive/refs/tags/$LlamaTag.zip",
        "https://gitcode.com/gh_mirrors/ll/llama.cpp/-/archive/$LlamaTag/llama.cpp-$LlamaTag.zip",
        "$LlamaRepo/archive/refs/tags/$LlamaTag.zip"
    ) $srcZip "llama.cpp 源码 $LlamaTag" 10MB
    Expand-Zip $srcZip $DepDir
    if (-not (Test-Path $SrcDir)) {
        # GitHub 的 zip 顶层目录名可能带后缀，兜底找一个 llama.cpp-* 目录
        $found = Get-ChildItem $DepDir -Directory -Filter "llama.cpp-*" | Select-Object -First 1
        if ($found) { $SrcDir = $found.FullName }
    }
    if (-not (Test-Path $SrcDir)) { Write-Host "[错误] 解压后未找到源码目录" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
}
Write-Host "[OK] llama.cpp 源码: $SrcDir" -ForegroundColor Green

# ==================== 工具链 ====================
# CMake / Ninja：优先 PATH，其次 Visual Studio 自带的副本
function Find-Tool($names, $patterns) {
    foreach ($n in $names) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    foreach ($p in $patterns) {
        $hit = Get-ChildItem $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
$CMake = Find-Tool @("cmake.exe") @(
    "$env:ProgramFiles\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe")
$Ninja = Find-Tool @("ninja.exe") @(
    "$env:ProgramFiles\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe")
if (-not $CMake -or -not $Ninja) {
    Write-Host "[错误] 未找到 cmake.exe / ninja.exe" -ForegroundColor Red
    Write-Host "  安装 Visual Studio Build Tools 时勾选「C++ CMake tools for Windows」。" -ForegroundColor Yellow
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
Write-Host "[OK] cmake: $CMake" -ForegroundColor Green
Write-Host "[OK] ninja: $Ninja" -ForegroundColor Green

# MSVC 工具集：取版本号最高的一个（14.4x / 14.5x 都行，关键是要有 x64 的 cl.exe）
$MsvcRoot = $null
foreach ($base in @("${env:ProgramFiles(x86)}\Microsoft Visual Studio", "$env:ProgramFiles\Microsoft Visual Studio")) {
    # 末尾要带 \* ：通配符落在最后一段时，Get-ChildItem 返回的是被匹配的目录本身而不是它的子目录
    $cand = Get-ChildItem "$base\*\*\VC\Tools\MSVC\*" -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName "bin\Hostx64\x64\cl.exe") } |
            Sort-Object Name -Descending | Select-Object -First 1
    if ($cand) { $MsvcRoot = $cand.FullName; break }
}
if (-not $MsvcRoot) { Write-Host "[错误] 未找到 MSVC x64 工具集（cl.exe）" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }

# Windows SDK：同样取版本号最高的一个，且要有 rc.exe（资源编译器，CMake 检查编译器时要用）
$SdkVer = $null
$sdkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$cand = Get-ChildItem "$sdkBin\10.*" -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "x64\rc.exe") } |
        Sort-Object Name -Descending | Select-Object -First 1
if ($cand) { $SdkVer = $cand.Name }
if (-not $SdkVer) { Write-Host "[错误] 未找到 Windows SDK（rc.exe）" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
Write-Host "[OK] MSVC: $MsvcRoot" -ForegroundColor Green
Write-Host "[OK] SDK:  $SdkVer" -ForegroundColor Green

$SdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
$BuildBat = Join-Path $BuildDir "_build.bat"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# 编译器环境：不调 vcvars64.bat（依赖 reg.exe），直接按目录拼。CRLF 换行必须，
# 否则 cmd 会把 set 行和下一行粘在一起。
function New-BuildBat($content) {
    $text = $content -replace "`r`n", "`n"
    $text = $text -replace "`n", "`r`n"
    [IO.File]::WriteAllText($BuildBat, $text, (New-Object Text.UTF8Encoding($false)))
}

$EnvBlock = @"
@echo off
chcp 65001 >nul
set "PATH=$MsvcRoot\bin\Hostx64\x64;$SdkRoot\bin\$SdkVer\x64;$(Split-Path $CMake);$(Split-Path $Ninja);%PATH%"
set "INCLUDE=$MsvcRoot\include;$SdkRoot\Include\$SdkVer\ucrt;$SdkRoot\Include\$SdkVer\um;$SdkRoot\Include\$SdkVer\shared;$SdkRoot\Include\$SdkVer\winrt;$SdkRoot\Include\$SdkVer\cppwinrt"
set "LIB=$MsvcRoot\lib\x64;$SdkRoot\Lib\$SdkVer\ucrt\x64;$SdkRoot\Lib\$SdkVer\um\x64"
"@

# ==================== GPU 后端（预编译件，不在本机构建） ====================
# llama.cpp 的 Vulkan 后端要把 200 多个 .comp 着色器 × 6 种变体用 glslc 现编成
# SPIR-V 再嵌进 ggml-vulkan.dll（43 MB）。本机 glslc 并发调用会挂死，且这套东西
# 与源码版本一一对应、没有定制的必要，所以直接用官方同版本（b12540）发布包里的
# ggml-vulkan.dll，已入库在 x64\；本机构建不产出、也不覆盖它。
# 运行时由 Translate_Load 按目录加载；用户机器没有 vulkan-1.dll（无显卡驱动）
# 时该 DLL 加载失败自动跳过，落回 CPU 变体，不报错。

# ==================== 编译 llama.cpp 共享库 ====================
$existingLib = Get-ChildItem $BuildDir -Recurse -Filter "llama.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
$NeedBuild = -not $existingLib
if ($SkipLlamaBuild -and $NeedBuild) {
    Write-Host "[错误] -SkipLlamaBuild 指定了，但 $BuildDir 下没有 llama.dll" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
if ($NeedBuild) {
    Write-Host ""
    Write-Host "[1/3] 配置并编译 llama.cpp 共享库（首次约 3~8 分钟）..." -ForegroundColor Green
    # GGML_NATIVE=OFF + GGML_CPU_ALL_VARIANTS：CPU 按指令集拆成多个变体 DLL，
    # 运行时自动挑选（haswell=AVX2 等），不用本机特性也不要求用户机器有 AVX2。
    # GGML_BACKEND_DL 是 ALL_VARIANTS 的前置条件（变体必须是运行时加载的 DLL），
    # 它又强制 BUILD_SHARED_LIBS=ON（原因见文件头注释）——所以 llama 是 llama.dll。
    # GGML_VULKAN=OFF：Vulkan 后端不用源码编（着色器现编太慢且本机 glslc 会挂死），
    # 官方同版本预编译件已入库在 x64\ggml-vulkan.dll，本机构建不产出不覆盖。
    # 注意：改这些 GGML flag 后必须删掉 third_party\build_x64 强制重建 llama，
    # 否则脚本按「已有 llama.dll」复用旧产物，变体不会编出来。
    # CMAKE_MSVC_RUNTIME_LIBRARY 与封装层的 /MD 保持一致，否则 CRT 冲突。
    New-BuildBat @"
$EnvBlock
cmake -S "$SrcDir" -B "$BuildDir" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_APP=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON -DGGML_VULKAN=OFF -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL
if errorlevel 1 exit /b 110
cmake --build "$BuildDir"
if errorlevel 1 exit /b 111
exit /b 0
"@
    & cmd.exe /c "`"$BuildBat`""
    if ($LASTEXITCODE -ne 0) { Write-Host "[错误] llama.cpp 编译失败 (exit=$LASTEXITCODE)" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
} else {
    Write-Host "[OK] 复用已编译的共享库: $existingLib" -ForegroundColor Green
}

# 收集链接用的导入库：llama.lib / ggml.lib / ggml-base.lib（对应同目录分发的
# llama.dll / ggml.dll / ggml-base.dll，硬导入）。
# ggml-cpu-<variant>.lib 是运行时加载的后端 DLL 的导入库，链接它会让
# TranslateDll.dll 硬依赖全部 8 个变体——必须排除，后端只走运行时加载。
$Libs = @(Get-ChildItem $BuildDir -Recurse -Filter "*.lib" -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match "^(llama|ggml-base|ggml)\.lib$" } |
          Select-Object -ExpandProperty FullName)
if ($Libs.Count -eq 0) { Write-Host "[错误] 没有找到 llama.lib / ggml*.lib（CMake 产物路径可能变了）" -ForegroundColor Red; if (-not $NoPause) { Read-Host "按回车退出" }; exit 1 }
Write-Host "[OK] 待链接导入库 $($Libs.Count) 个" -ForegroundColor Green

# ==================== 编译封装 DLL ====================
$libArgs = ($Libs | ForEach-Object { "`"$_`"" }) -join " "
$tmpObj = Join-Path $BuildDir "TranslateDll.obj"
$tmpDll = Join-Path $BuildDir "TranslateDll.dll"

New-BuildBat @"
$EnvBlock
cl /nologo /O2 /MD /EHsc /W3 /utf-8 /DWIN32_LEAN_AND_MEAN /DNDEBUG /DUNICODE /D_UNICODE /Fo"$tmpObj" /I"$SrcDir\include" /I"$SrcDir\ggml\include" /I"$TransDir\src" "$SrcCpp" /link /DLL /MACHINE:X64 /OUT:"$tmpDll" $libArgs advapi32.lib shell32.lib ole32.lib user32.lib ws2_32.lib dbghelp.lib
if errorlevel 1 exit /b 101
exit /b 0
"@

Write-Host ""
Write-Host "[2/3] 正在编译 TranslateDll.cpp ..." -ForegroundColor Green
& cmd.exe /c "`"$BuildBat`""
$compileExit = $LASTEXITCODE
Remove-Item $BuildBat -ErrorAction SilentlyContinue
if ($compileExit -ne 0 -or -not (Test-Path $tmpDll)) {
    Write-Host "[错误] 编译失败！exit=$compileExit" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
Write-Host "[OK] 编译成功" -ForegroundColor Green

# ==================== 模型 ====================
if ($SkipModel) {
    Write-Host "[跳过] GGUF 模型（-SkipModel）；需要时跑 .\GetTranslateModel.ps1" -ForegroundColor DarkGray
} else {
    $modelPath = Join-Path $ModelDir $ModelName
    Invoke-Download @($ModelUrlMs, $ModelUrlHf) $modelPath "翻译模型 $ModelName（约 1.3 GB）" $ModelMinBytes
}

# ==================== 部署 ====================
Write-Host ""
Write-Host "[3/3] 部署 TranslateDll.dll + llama/ggml 运行库 + CPU 变体后端 ..." -ForegroundColor Green
Copy-Item -Path $tmpDll -Destination $OutDll -Force
Remove-Item $tmpObj -ErrorAction SilentlyContinue
Remove-Item (Join-Path $BuildDir "TranslateDll.lib") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $BuildDir "TranslateDll.exp") -ErrorAction SilentlyContinue

# 共享库：llama.dll + ggml*.dll（ggml-cpu- 变体单独处理）；与 TranslateDll.dll
# 同目录（TranslateDll 硬导入 llama/ggml，AHK 侧 LOAD_WITH_ALTERED_SEARCH_PATH
# 保证从本目录解析；CPU 变体由 TranslateDll 按自身路径运行时加载）。
$runtimeDlls = @(Get-ChildItem $BuildDir -Recurse -Filter "*.dll" -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match "^(llama|ggml)" -and $_.Name -notmatch "^ggml-cpu-" })
if ($runtimeDlls.Count -eq 0) {
    Write-Host "[错误] 构建目录里没有 llama.dll / ggml*.dll（共享库没编出来？）" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
foreach ($dll in $runtimeDlls) {
    Copy-Item -Path $dll.FullName -Destination $RunDir -Force
}
Write-Host "[OK] 运行库 $($runtimeDlls.Count) 个: $(($runtimeDlls | ForEach-Object { $_.Name }) -join ", ")" -ForegroundColor Green

# CPU 后端按指令集拆成 ggml-cpu-<variant>.dll，运行时自动挑选。
$backendDlls = @(Get-ChildItem $BuildDir -Recurse -Filter "ggml-cpu-*.dll" -ErrorAction SilentlyContinue)
if ($backendDlls.Count -eq 0) {
    Write-Host "[错误] 构建目录里没有 ggml-cpu-*.dll（GGML_BACKEND_DL 变体没编出来？）" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "按回车退出" }
    exit 1
}
foreach ($dll in $backendDlls) {
    Copy-Item -Path $dll.FullName -Destination $RunDir -Force
}
Write-Host "[OK] CPU 后端 $($backendDlls.Count) 个: $(($backendDlls | ForEach-Object { $_.Name }) -join ", ")" -ForegroundColor Green

# GPU 后端 ggml-vulkan.dll 是入库的官方 b12540 预编译件（含已编好的 SPIR-V），
# 与上面自编的 CPU 变体并列，运行时由 Translate_Load 一并注册；本机构建不产出
# 不覆盖，误删从 git 还原。无显卡驱动的机器加载失败自动跳过。
if (Test-Path (Join-Path $RunDir "ggml-vulkan.dll")) {
    $vkSize = [math]::Round((Get-Item (Join-Path $RunDir "ggml-vulkan.dll")).Length / 1MB, 1)
    Write-Host "[OK] GPU 后端: x64\ggml-vulkan.dll（官方预编译件，$vkSize MB）" -ForegroundColor Green
} else {
    Write-Host "[提示] x64\ggml-vulkan.dll 不在，本次仅 CPU 推理（git checkout 还原）" -ForegroundColor Yellow
}

$dllSize = [math]::Round((Get-Item $OutDll).Length / 1KB, 1)
Write-Host "[OK] 部署完成: $OutDll ($dllSize KB)" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TranslateDll 编译部署成功！" -ForegroundColor Green
Write-Host "  产物: x64\TranslateDll.dll + llama/ggml 运行库 + CPU 变体后端（+ ggml-vulkan.dll）" -ForegroundColor White
Write-Host "  模型: models\$ModelName" -ForegroundColor White
Write-Host "  构建缓存: $DepDir（git 已忽略）" -ForegroundColor White
Write-Host "  重启 RMT 后生效" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

if (-not $NoPause) { Read-Host "按回车退出" }
