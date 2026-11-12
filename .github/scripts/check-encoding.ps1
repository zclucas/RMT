# .ahk 源码编码检查（CI / 本地均可用）
# 约定：
#   1. 所有 .ahk 必须是合法 UTF-8；
#   2. 换行必须是 CRLF（不允许裸 LF 或混合换行）；
#   3. BOM 白名单：仅以下文件允许（且必须）带 UTF-8 BOM。
# 退出码：0 = 通过，1 = 存在问题。
param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'

if (-not $Root) {
    # 脚本位于 <repo>\.github\scripts\，仓库根为其上上级
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# 允许（且要求）带 UTF-8 BOM 的文件，按仓库相对路径精确匹配（2026-11-12 盘点存量）
$bomAllowed = @(
    'Gui\ColorPanelGui.ahk',
    'Gui\IntervalGui.ahk',
    'Gui\JoyPickerHook.ahk',
    'Gui\SettingMgrGui.ahk',
    'Gui\TargetGui.ahk',
    'Gui\UIMacroGui.ahk',
    'Main\FolderPackager.ahk',
    'Main\GestureUtil.ahk',
    'Main\GlobalUtil.ahk',
    'Main\Util\ArrayUtil.ahk',
    'Main\Util\CompatTov1-2.ahk',
    'Main\Util\Compatv1-3.ahk',
    'Main\Util\FileIOUtil.ahk',
    'Main\Util\IniImportUtil.ahk',
    'Main\Util\JoyNameUtil.ahk',
    'Main\Util\MacroUtil.ahk',
    'Main\Util\MouseMovePreview.ahk',
    'Main\Util\TextOpsUtil.ahk',
    'Main\Util\Toml\TomlBase.ahk',
    'Plugins\TesseractOcr\TesseractOcr.ahk',
    'Plugins\VIIPER\VIIPER.ahk'
)

# 排除非源码目录
$excludedDirs = @('\.git\', '\ReleaseX64\', '\ReleaseX86\', '\Test\', '\Cache\', '\Log\', '\Setting\')

$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)   # 严格模式：非法序列抛异常
$lenientUtf8 = New-Object System.Text.UTF8Encoding($false, $false)

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.ahk' -File | Where-Object {
    $rel = $_.FullName.Substring($Root.Length + 1).Replace('/', '\')
    $keep = $true
    foreach ($d in $excludedDirs) {
        if ($rel -like "*$d*") { $keep = $false; break }
    }
    $keep
})

if ($files.Count -eq 0) {
    Write-Host "[ERROR] no .ahk files found under $Root"
    exit 1
}

Write-Host "checking $($files.Count) .ahk files under $Root"

$errors = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length + 1).Replace('/', '\')
    $bytes = [IO.File]::ReadAllBytes($f.FullName)

    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    # 1) 必须是合法 UTF-8
    try {
        if ($hasBom) { [void]$strictUtf8.GetString($bytes, 3, $bytes.Length - 3) }
        else         { [void]$strictUtf8.GetString($bytes) }
    } catch {
        $errors += "[$rel] not valid UTF-8 (mojibake? saved as GBK/ANSI?)"
        continue
    }

    # 2) BOM 策略
    if ($hasBom -and $bomAllowed -notcontains $rel) {
        $errors += "[$rel] unexpected UTF-8 BOM (add the path to `$bomAllowed if intentional)"
    }
    if (-not $hasBom -and $bomAllowed -contains $rel) {
        $errors += "[$rel] missing expected UTF-8 BOM"
    }

    # 3) 换行必须是 CRLF：先解码文本，剥掉所有 CRLF 后不允许再出现 LF
    $text = if ($hasBom) { $lenientUtf8.GetString($bytes, 3, $bytes.Length - 3) }
            else         { $lenientUtf8.GetString($bytes) }
    $stripped = $text -replace "`r`n", ''
    if ($stripped -match "`n") {
        $errors += "[$rel] bare LF found (line endings must be CRLF)"
    }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "[ERROR] encoding check failed, $($errors.Count) problem(s):"
    foreach ($e in $errors) { Write-Host "  $e" }
    exit 1
}

Write-Host ""
Write-Host "[RESULT] ENCODING OK ($($files.Count) files)"
exit 0
