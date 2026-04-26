# RMT 一键打包脚本 (64位)
# 用法: 右键 → 使用 PowerShell 运行
# 功能: 编译AHK(全局) → 编译DLL → 复制资源 → 打包文档 → UPX压缩

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "RMT Build & Package (x64)"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseDir = Join-Path $ScriptDir "ReleaseX64"
$Upx = Join-Path $ScriptDir "Plugins\upx.exe"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  RMT  一键打包工具 (x64)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

function Exit-Error($Msg) {
    Write-Host "[错误] $Msg" -ForegroundColor Red
    Write-Host "`n按任意键退出..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# ==================== 前置检查 ====================
$Errors = @()
$Ahk2ExeCmd = Get-Command Ahk2Exe -ErrorAction SilentlyContinue
if (-not $Ahk2ExeCmd) { $Errors += "未找到全局 Ahk2Exe 命令，请确认 AutoHotkey 已安装并加入 PATH" }
if (-not (Test-Path $Upx)) { $Errors += "未找到 UPX: $Upx" }
if ($Errors.Count -gt 0) {
    Write-Host "[错误] 前置检查失败:" -ForegroundColor Red
    $Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`n按任意键退出..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
$Ahk2Exe = $Ahk2ExeCmd.Source
Write-Host "[前置检查] 通过  Ahk2Exe=$Ahk2Exe / UPX 就绪" -ForegroundColor Green

# ==================== Step 1: 清理旧版本 ====================
Write-Host "`n--- [1/6] 清理旧版本 ---" -ForegroundColor Yellow
if (Test-Path $ReleaseDir) {
    Remove-Item -Path $ReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
Write-Host "  ReleaseX64 已就绪" -ForegroundColor DarkGray

# ==================== Step 2: 编译 AHK (全局命令) ====================
Write-Host "`n--- [2/6] 编译 AHK 脚本 (全局 Ahk2Exe) ---" -ForegroundColor Yellow

function Compile-AHK($Src, $Dst, $WorkDir) {
    $SrcName = Split-Path $Src -Leaf
    Write-Host "  编译: $SrcName ..." -ForegroundColor White
    $DstParent = Split-Path $Dst -Parent
    if (-not (Test-Path $DstParent)) { New-Item -ItemType Directory -Path $DstParent -Force | Out-Null }

    $argsStr = "/in `"$Src`" /out `"$Dst`""
    $proc = Start-Process -FilePath $Ahk2Exe -ArgumentList $argsStr -Wait -PassThru -WindowStyle Hidden -WorkingDirectory $WorkDir
    if ($proc.ExitCode -ne 0 -or -not (Test-Path $Dst)) {
        Exit-Error "$SrcName 编译失败! ExitCode: $($proc.ExitCode)"
    }
    $size = [math]::Round((Get-Item $Dst).Length / 1024, 1)
    Write-Host "    OK  ${size} KB" -ForegroundColor Green
}

Compile-AHK (Join-Path $ScriptDir "RMT.ahk") (Join-Path $ReleaseDir "RMT.exe") $ScriptDir
Compile-AHK (Join-Path $ScriptDir "Thread\Work.ahk") (Join-Path $ReleaseDir "Thread\Work1.exe") (Join-Path $ScriptDir "Thread")

# ==================== Step 3: 编译 DLL ====================
Write-Host "`n--- [3/6] 编译 DLL ---" -ForegroundColor Yellow

$OpenCvBuildBat = Join-Path $ScriptDir "Plugins\OpenCV\buildDll.bat"
if (-not (Test-Path $OpenCvBuildBat)) {
    Exit-Error "未找到 OpenCV 编译脚本: $OpenCvBuildBat"
}

Write-Host "  编译 RMT_OpenCV.dll ..." -ForegroundColor White
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"`"$OpenCvBuildBat`"" -Wait -PassThru -WindowStyle Hidden
if ($proc.ExitCode -ne 0) {
    Exit-Error "RMT_OpenCV.dll 编译失败! ExitCode: $($proc.ExitCode)，请检查 MSVC 和 OpenCV 环境是否正确配置"
}

$BuiltDll = Join-Path $ScriptDir "Plugins\OpenCV\build\Release\RMT_OpenCV.dll"
if (-not (Test-Path $BuiltDll)) {
    Exit-Error "编译完成但未找到输出文件: $BuiltDll"
}
Copy-Item -Path $BuiltDll -Destination (Join-Path $ScriptDir "Plugins\OpenCV\RMT_OpenCV.dll") -Force
$size = [math]::Round((Get-Item (Join-Path $ScriptDir "Plugins\OpenCV\RMT_OpenCV.dll")).Length / 1024, 1)
Write-Host "    OK  ${size} KB (已回填到 Plugins/OpenCV/)" -ForegroundColor Green

# ==================== Step 4: 复制资源文件到 ReleaseX64 ====================
Write-Host "`n--- [4/6] 复制资源文件 ---" -ForegroundColor Yellow

$CopyMap = @{
    "Audio"                                    = "Audio"
    "Joy"                                      = "Joy"
    "Lang"                                     = "Lang"
    "VBS"                                      = "VBS"
    "Plugins/OpenCV/RMT_OpenCV.dll"            = "Plugins/OpenCV/RMT_OpenCV.dll"
    "Plugins/OpenCV/opencv_world481.dll"       = "Plugins/OpenCV/opencv_world481.dll"
    "Plugins/RMT/RMT.dll"                      = "Plugins/RMT/RMT.dll"
    "Plugins/ViGEm/ViGEmWrapper.dll"          = "Plugins/ViGEm/ViGEmWrapper.dll"
    "Plugins/IbInputSimulator.dll"             = "Plugins/IbInputSimulator.dll"
    "Plugins/RapidOcr/64bit"                   = "Plugins/RapidOcr/64bit"
    "Plugins/RapidOcr/ch_models"               = "Plugins/RapidOcr/ch_models"
    "Plugins/RapidOcr/en_models"               = "Plugins/RapidOcr/en_models"
    "Plugins/ScreenCapture/ScreenCapture.exe"  = "Plugins/ScreenCapture/ScreenCapture.exe"
}

foreach ($SrcRel in $CopyMap.Keys) {
    $DstRel = $CopyMap[$SrcRel]
    $SrcFull = Join-Path $ScriptDir $SrcRel
    $DstFull = Join-Path $ReleaseDir $DstRel

    if (-not (Test-Path $SrcFull)) {
        Exit-Error "源文件缺失: $SrcRel"
    }

    if (Test-Path $SrcFull -PathType Leaf) {
        $DstParent = Split-Path $DstFull -Parent
        if (-not (Test-Path $DstParent)) { New-Item -ItemType Directory -Path $DstParent -Force | Out-Null }
        Copy-Item -Path $SrcFull -Destination $DstFull -Force
    } else {
        Copy-Item -Path $SrcFull -Destination $DstFull -Recurse -Force
    }
    Write-Host "  ✓ $SrcRel" -ForegroundColor DarkGray
}

# ==================== Step 5: 打包帮助文档 (复用 PackHelp.ps1) ====================
Write-Host "`n--- [5/6] 打包帮助文档 ---" -ForegroundColor Yellow
$PackHelp = Join-Path $ScriptDir "PackHelp.ps1"
if (-not (Test-Path $PackHelp)) {
    Exit-Error "未找到文档打包脚本: PackHelp.ps1"
}

Push-Location $ScriptDir
$proc = Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -File `"$PackHelp`" -NoWait" -Wait -PassThru -WindowStyle Hidden
Pop-Location

$DocSrc = Join-Path $ScriptDir "RMT帮助文档.html"
$DocDst = Join-Path $ReleaseDir "RMT帮助文档.html"
if (-not (Test-Path $DocSrc)) {
    Exit-Error "文档生成失败，未找到输出: $DocSrc"
}
Copy-Item -Path $DocSrc -Destination $DocDst -Force
$size = [math]::Round((Get-Item $DocSrc).Length / 1024, 1)
Write-Host "  ✓ RMT帮助文档.html (${size} KB)" -ForegroundColor DarkGray

# ==================== Step 6: UPX 压缩 ====================
Write-Host "`n--- [6/6] UPX 压缩 ---" -ForegroundColor Yellow

$Exts = @("*.exe", "*.dll")
$CompressedCount = 0
$TotalSizeBefore = 0
$TotalSizeAfter = 0

foreach ($Ext in $Exts) {
    Get-ChildItem -Path $ReleaseDir -Recurse -File -Filter $Ext | ForEach-Object {
        $sizeBefore = $_.Length
        $TotalSizeBefore += $sizeBefore
        Start-Process -FilePath $Upx -ArgumentList "--best", "--lzma", $_.FullName -Wait -WindowStyle Hidden 2>&1 | Out-Null
        $sizeAfter = (Get-Item $_.FullName).Length
        $TotalSizeAfter += $sizeAfter
        if ($sizeAfter -lt $sizeBefore) {
            $ratio = [math]::Round((1 - $sizeAfter / $sizeBefore) * 100, 1)
            Write-Host "  ✓ $($_.Name)  ${ratio}% 缩减" -ForegroundColor DarkGray
            $CompressedCount++
        } else {
            Write-Host "  - $($_.Name)" -ForegroundColor DarkGray
        }
    }
}

# ==================== 完成 ====================
$TotalBeforeMB = [math]::Round($TotalSizeBefore / 1MB, 2)
$TotalAfterMB = [math]::Round($TotalSizeAfter / 1MB, 2)
$SavedMB = [math]::Round(($TotalSizeBefore - $TotalSizeAfter) / 1MB, 2)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  ✓ 打包完成!" -ForegroundColor Green
Write-Host "  输出目录: $ReleaseDir" -ForegroundColor White
Write-Host "  压缩文件: $CompressedCount 个" -ForegroundColor White
Write-Host "  原始大小: ${TotalBeforeMB} MB" -ForegroundColor White
Write-Host "  压缩后:   ${TotalAfterMB} MB  (节省 ${SavedMB} MB)" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Green
