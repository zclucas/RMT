<#
构建 RMT_YOLO.dll。

用法：
    .\build.ps1            构建 x64
    .\build.ps1 x86        构建 x86（需要先 rustup target add i686-pc-windows-msvc）

产物落在 ..\x64\ 或 ..\x86\（即 Plugins\YOLO\x64\，与 OpenCV 插件同一约定），
宿主从这里加载 RMT_YOLO.dll。内核用 load-dynamic 方式使用 ONNX Runtime，所以
onnxruntime.dll 必须与 RMT_YOLO.dll 同目录（脚本会从 Plugins\Voice\<架构>\ 自动取）。
#>
param([string]$Arch = "x64")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "未找到 cargo。" -ForegroundColor Red
    Write-Host "请先安装 Rust 工具链（要求 1.92+）：https://rustup.rs" -ForegroundColor Yellow
    Exit 1
}

$isX86 = $Arch -ieq "x86"
$target = if ($isX86) { "i686-pc-windows-msvc" } else { "x86_64-pc-windows-msvc" }
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) $(if ($isX86) { "x86" } else { "x64" })

$installed = & rustup target list --installed 2>$null
if ($installed -notcontains $target) {
    Write-Host "缺少目标平台 $target，请先执行：" -ForegroundColor Yellow
    Write-Host "    rustup target add $target" -ForegroundColor Yellow
    Exit 1
}

Write-Host "构建 $target ..." -ForegroundColor Cyan
& cargo build --release --target $target
if ($LASTEXITCODE -ne 0) {
    Write-Host "构建失败。" -ForegroundColor Red
    Exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item (Join-Path "target\$target\release" "RMT_YOLO.dll") $outDir -Force

# 内核走 load-dynamic（见 Cargo.toml），运行时要 onnxruntime.dll 与主库同目录，
# 否则 ort 在第一次调用时 LoadLibrary 失败。
# 项目里唯一的官方副本在 Plugins\Voice\<架构>\（sherpa-onnx 打包的官方 ONNX Runtime，
# 版本 1.27.1，OrtGetApiBase()->GetApi(17) 非空，满足 ort 2.0 的 ORT_API_VERSION=17）。
# 想换独立版本时把文件放进 deps\ 即可优先使用。
$pluginsDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ortNames = @("onnxruntime.dll", "onnxruntime_providers_shared.dll")
foreach ($name in $ortNames) {
    $sources = @(
        (Join-Path $PSScriptRoot "deps\$name"),
        (Join-Path $pluginsDir "Voice\$Arch\$name")
    )
    $found = $sources | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        Copy-Item $found $outDir -Force
    } else {
        Write-Host "缺少 $name（$Arch）。放一份到 deps\ 或先构建 Voice 插件，否则宿主加载会失败。" -ForegroundColor Yellow
    }
}

# 旧版本静态链接时会把 DirectML.dll 拷到输出目录，留着会白占 17 MB 且不再被使用。
foreach ($stale in @("DirectML.dll", "onnxruntime_providers_cuda.dll", "onnxruntime_providers_tensorrt.dll")) {
    $path = Join-Path $outDir $stale
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "已清理历史残留：$stale" -ForegroundColor Gray
    }
}

Write-Host "完成：$outDir" -ForegroundColor Green
Get-ChildItem $outDir | Select-Object Name, @{N = "MB"; E = { [math]::Round($_.Length / 1MB, 2) } }
