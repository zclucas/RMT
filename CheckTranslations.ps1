# ==============================================================================
# RMT 多语言翻译检查与自动同步工具 (CheckTranslations.ps1)
# 
# 核心机制:
#   1. 以 AHK 源码中的实际引用 (codeKeys) 作为唯一基准 (Source of Truth)
#   2. 检查各语言包是否存在「漏翻 (Missing)」: 代码中已使用，但语言包缺失或为空
#   3. 检查各语言包是否存在「多翻 (Redundant)」: 语言包中残留，但代码中已废弃删除
#   4. 检查各语言包是否存在「重复 (Duplicate)」: 语言包内部同名 key 重复定义
#   5. 支持安全清理、末尾换行自适应补齐、Fix 后二次复验，并提供打包即时中断
#
# 参数说明:
#   .\CheckTranslations.ps1                    # 默认检查 Lang\ 下所有语言包
#   .\CheckTranslations.ps1 -Lang English      # 仅检查指定语言包 (Lang\English.txt)
#   .\CheckTranslations.ps1 -Strict            # 严格模式：发现任何缺陷均退出码 1（供 PackRMT 打包调用）
#   .\CheckTranslations.ps1 -Clean             # 自动清理废弃冗余词条与内部重复项
#   .\CheckTranslations.ps1 -AppendMissing     # 自动追加漏翻词条至文件末尾（附默认值）
#   .\CheckTranslations.ps1 -Fix               # 一键修复：清理废弃项 + 补全缺漏项 + 二次复验
#   .\CheckTranslations.ps1 -ExportMissing dir # 将各语言包的漏翻词条独立导出到指定目录
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Lang = "",
    [switch]$Strict = $false,
    [switch]$Clean = $false,
    [switch]$AppendMissing = $false,
    [switch]$Fix = $false,
    [string]$ExportMissing = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$LangDir = Join-Path $Root "Lang"

if (-not (Test-Path $LangDir)) {
    Write-Error "未找到 Lang 目录: $LangDir"
    exit 1
}

if ($Fix) {
    $Clean = $true
    $AppendMissing = $true
}

$utf8Bom = [System.Text.UTF8Encoding]::new($true)

# ==============================================================================
# 1. 扫描 AHK 源码，构建 codeKeys（Source of Truth）
# ==============================================================================
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " 正在提取 RMT 源码中的多语言键 (GetLang / 指令集 / 类别) " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$ahkFiles = Get-ChildItem -Path $Root -Filter "*.ahk" -Recurse | Where-Object {
    $_.FullName -notmatch '\\Test\\' -and $_.FullName -notmatch '\\\.git\\'
}

$codeKeys = [System.Collections.Generic.HashSet[string]]::new()
$codeOrigins = @{}
$fullCodeBuilder = [System.Text.StringBuilder]::new()

$getLangRegex = [regex]'GetLang(?:Key)?\s*\(\s*(["''])(.*?)\1\s*\)'
# 支持跨行匹配的 GetLangArr / GetLangKeyArr
$getLangArrRegex = [regex]::new('GetLang(?:Key)?Arr\s*\(\s*\[(.*?)\]\s*\)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$itemRegex = [regex]'["''](.*?)["'']'

foreach ($file in $ahkFiles) {
    $rel = $file.FullName.Substring($Root.Length + 1)
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    [void]$fullCodeBuilder.AppendLine($content)

    # 过滤整行注释，减少无效内容干扰
    $lines = $content -split "`r?`n"
    $cleanLines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $lines) {
        $t = $l.TrimStart()
        if ($t.StartsWith(";") -or $t.StartsWith("#") -or $t -eq "") {
            continue
        }
        $cleanLines.Add($l)
    }
    $cleanContent = [string]::Join("`n", $cleanLines)

    # 提取 GetLang("...") / GetLangKey("...")
    foreach ($m in $getLangRegex.Matches($cleanContent)) {
        $val = $m.Groups[2].Value
        if ($val -ne "" -and $val -notmatch '^\$') {
            [void]$codeKeys.Add($val)
            if (-not $codeOrigins.ContainsKey($val)) { $codeOrigins[$val] = $rel }
        }
    }

    # 提取 GetLangArr([...]) / GetLangKeyArr([...])（支持多行数组）
    foreach ($m in $getLangArrRegex.Matches($cleanContent)) {
        $arrContent = $m.Groups[1].Value
        foreach ($item in $itemRegex.Matches($arrContent)) {
            $val = $item.Groups[1].Value
            if ($val -ne "") {
                [void]$codeKeys.Add($val)
                if (-not $codeOrigins.ContainsKey($val)) { $codeOrigins[$val] = $rel }
            }
        }
    }
}

# 提取 LangCmdKeyArr（支持多行）
$langUtilPath = Join-Path $Root "Main\Util\LangUtil.ahk"
if (Test-Path $langUtilPath) {
    $langUtilContent = [System.IO.File]::ReadAllText($langUtilPath, [System.Text.Encoding]::UTF8)
    $cmdArrRegex = [regex]::new('LangCmdKeyArr\s*:=\s*\[(.*?)\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($cmdArrRegex.IsMatch($langUtilContent)) {
        $arrStr = $cmdArrRegex.Match($langUtilContent).Groups[1].Value
        foreach ($item in $itemRegex.Matches($arrStr)) {
            $val = $item.Groups[1].Value
            if ($val -ne "") {
                [void]$codeKeys.Add($val)
                if (-not $codeOrigins.ContainsKey($val)) { $codeOrigins[$val] = "Main\Util\LangUtil.ahk" }
            }
        }
    }
}

# 提取宏类别与默认页签定义
$storagePath = Join-Path $Root "Main\Shared\MacroTableStorage.ahk"
if (Test-Path $storagePath) {
    $storageContent = [System.IO.File]::ReadAllText($storagePath, [System.Text.Encoding]::UTF8)
    $tabCatRegex = [regex]'\["[A-Za-z]+",\s*"([^"]+)",'
    foreach ($m in $tabCatRegex.Matches($storageContent)) {
        $val = $m.Groups[1].Value
        if ($val -ne "") {
            [void]$codeKeys.Add($val)
            if (-not $codeOrigins.ContainsKey($val)) { $codeOrigins[$val] = "Main\Shared\MacroTableStorage.ahk" }
        }
    }
}

# 提取含有等号的 codeKey 列表，用于解决拆分歧义
$keysWithEquals = @($codeKeys | Where-Object { $_.Contains("=") })

$fullCodeString = $fullCodeBuilder.ToString()
Write-Host "扫描完成: 共在 $($ahkFiles.Count) 个源码文件中提取出 $($codeKeys.Count) 个有效多语言词条`n" -ForegroundColor Gray

# ==============================================================================
# 2. 解析语言包辅助函数
# ==============================================================================
function Analyze-LangFile([string]$filePath) {
    $rawLines = Get-Content $filePath -Encoding UTF8
    $langDict = [ordered]@{}
    $langKeys = [System.Collections.Generic.List[string]]::new()
    $duplicateKeys = [System.Collections.Generic.List[string]]::new()
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($line in $rawLines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "") { continue }

        $k = $null
        $v = $null

        # 优先匹配已知包含 '=' 的词条
        foreach ($eqk in $keysWithEquals) {
            if ($trimmed.StartsWith("$eqk=")) {
                $k = $eqk
                $v = $trimmed.Substring($eqk.Length + 1).Trim()
                break
            }
        }

        # 常规分割：首个等号
        if ($null -eq $k) {
            $eqPos = $trimmed.IndexOf("=")
            if ($eqPos -gt 0) {
                $k = $trimmed.Substring(0, $eqPos)
                $v = $trimmed.Substring($eqPos + 1).Trim()
            }
        }

        if ($k -ne $null -and $k -ne "") {
            $lookupKey = if ($codeKeys.Contains($k)) { $k } else { $k.Trim() }

            if ($seenKeys.Contains($lookupKey)) {
                $duplicateKeys.Add($lookupKey)
            } else {
                [void]$seenKeys.Add($lookupKey)
                $langDict[$lookupKey] = $v
                $langKeys.Add($lookupKey)
            }
        }
    }

    # 漏翻检查
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $codeKeys) {
        $lookupKey = if ($langDict.Contains($k)) { $k } elseif ($langDict.Contains($k.Trim())) { $k.Trim() } else { $null }
        if ($null -eq $lookupKey -or [string]::IsNullOrWhiteSpace($langDict[$lookupKey])) {
            $missingList.Add($k)
        }
    }

    # 多翻检查：既不在 codeKeys 中，且在全文源码中也无任何直接出现
    $redundantList = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $langKeys) {
        if (-not $codeKeys.Contains($k) -and -not $codeKeys.Contains($k.Trim()) -and -not $fullCodeString.Contains($k)) {
            $redundantList.Add($k)
        }
    }

    # 唯有 漏翻=0、多翻=0 且 重复=0 视为完全通过
    $isPass = ($missingList.Count -eq 0 -and $redundantList.Count -eq 0 -and $duplicateKeys.Count -eq 0)

    return [pscustomobject]@{
        RawLines = $rawLines
        LangDict = $langDict
        LangKeys = $langKeys
        Duplicates = $duplicateKeys
        Missing = $missingList
        Redundant = $redundantList
        Pass = $isPass
    }
}

# ==============================================================================
# 3. 收集待检查的语言包
# ==============================================================================
$targetFiles = @()
if ($Lang -ne "") {
    $langFileName = if ($Lang.EndsWith(".txt")) { $Lang } else { "$Lang.txt" }
    $langFilePath = Join-Path $LangDir $langFileName
    if (-not (Test-Path $langFilePath)) {
        Write-Error "找不到语言文件: $langFilePath"
        exit 1
    }
    $targetFiles = @(Get-Item $langFilePath)
} else {
    $targetFiles = @(Get-ChildItem -Path $LangDir -Filter "*.txt" |
        Where-Object { $_.BaseName -ne "简中" -and $_.BaseName -ne "中文" } |
        Sort-Object Name)
}

if ($targetFiles.Count -eq 0) {
    Write-Host "Lang\ 目录下未找到任何外语语言包文件（仅内置简中）。`n" -ForegroundColor Yellow
    exit 0
}

Write-Host "待检查语言包列表: $(($targetFiles | ForEach-Object { $_.Name }) -join ', ')`n" -ForegroundColor DarkCyan

$summaryList = [System.Collections.Generic.List[object]]::new()

# ==============================================================================
# 4. 逐个语言包检查并执行修复（若启用）
# ==============================================================================
foreach ($file in $targetFiles) {
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "正在检查语言包: $($file.Name)" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkCyan

    $result = Analyze-LangFile $file.FullName

    Write-Host "  词条总数: $($result.LangKeys.Count)" -ForegroundColor Gray
    
    if ($result.Missing.Count -eq 0) {
        Write-Host "  [OK] 漏翻: 0 项" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] 漏翻: $($result.Missing.Count) 项 (代码中有使用，但语言包缺少翻译)" -ForegroundColor Red
    }

    if ($result.Redundant.Count -eq 0) {
        Write-Host "  [OK] 多翻(废弃): 0 项" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] 多翻(废弃): $($result.Redundant.Count) 项 (语言包中残留，但在代码中已完全废弃)" -ForegroundColor Yellow
    }

    if ($result.Duplicates.Count -eq 0) {
        Write-Host "  [OK] 内部重复: 0 项" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] 内部重复: $($result.Duplicates.Count) 项 (同名 key 重复定义)" -ForegroundColor Yellow
    }

    # 导出漏翻词条（每个语言独立命名，避免相互覆盖）
    if ($ExportMissing -ne "" -and $result.Missing.Count -gt 0) {
        $exportDir = $ExportMissing
        if (-not (Test-Path $exportDir)) {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        }
        $exportFileName = "Missing_$($file.BaseName).txt"
        $exportPath = Join-Path $exportDir $exportFileName
        $missingLines = $result.Missing | ForEach-Object { "$_=$($codeOrigins[$_])" }
        [System.IO.File]::WriteAllLines($exportPath, $missingLines, $utf8Bom)
        Write-Host "  已导出漏翻词条至: $exportPath" -ForegroundColor Cyan
    }

    # 打印前 10 项漏翻样例
    if ($result.Missing.Count -gt 0) {
        Write-Host "`n  [漏翻样例 (前 10 项)]:" -ForegroundColor Red
        for ($i = 0; $i -lt [Math]::Min(10, $result.Missing.Count); $i++) {
            $k = $result.Missing[$i]
            Write-Host "    $($i + 1). '$k'  (位置: $($codeOrigins[$k]))" -ForegroundColor DarkRed
        }
        if ($result.Missing.Count -gt 10) {
            Write-Host "    ... 还有 $($result.Missing.Count - 10) 项未列出" -ForegroundColor DarkGray
        }
    }

    # 打印前 10 项多翻样例
    if ($result.Redundant.Count -gt 0) {
        Write-Host "`n  [多翻/废弃样例 (前 10 项)]:" -ForegroundColor Yellow
        for ($i = 0; $i -lt [Math]::Min(10, $result.Redundant.Count); $i++) {
            $k = $result.Redundant[$i]
            Write-Host "    $($i + 1). '$k' = '$($result.LangDict[$k])'" -ForegroundColor DarkYellow
        }
        if ($result.Redundant.Count -gt 10) {
            Write-Host "    ... 还有 $($result.Redundant.Count - 10) 项未列出" -ForegroundColor DarkGray
        }
    }

    # ==============================================================================
    # 5. 执行自动修复逻辑（Clean / AppendMissing / Fix）
    # ==============================================================================
    $fileModified = $false

    if ($Clean -and ($result.Redundant.Count -gt 0 -or $result.Duplicates.Count -gt 0)) {
        Write-Host "`n  正在清理 $($file.Name) 中的废弃项 ($($result.Redundant.Count)) 与重复项 ($($result.Duplicates.Count))..." -ForegroundColor Cyan
        $redundantSet = [System.Collections.Generic.HashSet[string]]::new($result.Redundant)
        $cleanedKeys = [System.Collections.Generic.HashSet[string]]::new()
        $newLines = [System.Collections.Generic.List[string]]::new()

        foreach ($line in $result.RawLines) {
            $trimmed = $line.Trim()
            $eqPos = $trimmed.IndexOf("=")
            if ($eqPos -gt 0) {
                $k = $trimmed.Substring(0, $eqPos).Trim()
                # 剔除废弃项
                if ($redundantSet.Contains($k)) {
                    continue
                }
                # 剔除重复定义（保留首见项）
                if ($cleanedKeys.Contains($k)) {
                    continue
                }
                [void]$cleanedKeys.Add($k)
            }
            $newLines.Add($line)
        }

        # 安全写入：先写临时文件再原子替换
        $tempFile = "$($file.FullName).tmp"
        [System.IO.File]::WriteAllLines($tempFile, $newLines, $utf8Bom)
        Move-Item -Path $tempFile -Destination $file.FullName -Force
        $fileModified = $true
        Write-Host "  [OK] $($file.Name) 废弃词条与重复项清理完毕！" -ForegroundColor Green
    }

    if ($AppendMissing -and $result.Missing.Count -gt 0) {
        Write-Host "`n  正在向 $($file.Name) 追加 $($result.Missing.Count) 个漏翻词条（附默认值）..." -ForegroundColor Cyan
        
        # 检查现有文件末尾是否已有换行，若无则先追加换行避免粘连
        $currentBytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($currentBytes.Length -gt 0) {
            $lastByte = $currentBytes[$currentBytes.Length - 1]
            if ($lastByte -ne 10 -and $lastByte -ne 13) {
                [System.IO.File]::AppendAllText($file.FullName, "`r`n", $utf8Bom)
            }
        }

        $appendLines = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $result.Missing) {
            $appendLines.Add("$k=$k")
        }
        [System.IO.File]::AppendAllLines($file.FullName, $appendLines, $utf8Bom)
        $fileModified = $true
        Write-Host "  [OK] $($file.Name) 漏翻词条追加完毕！" -ForegroundColor Green
    }

    # 若执行过修改，重新读取并二次验证，确保报告反映真实最终状态
    if ($fileModified) {
        Write-Host "  正在对 $($file.Name) 重新进行复检确认..." -ForegroundColor Gray
        $result = Analyze-LangFile $file.FullName
        Write-Host "  [复检结果] 词条数: $($result.LangKeys.Count) | 漏翻: $($result.Missing.Count) | 多翻: $($result.Redundant.Count) | 重复: $($result.Duplicates.Count)" -ForegroundColor $(if ($result.Pass) { "Green" } else { "Yellow" })
    }

    $summaryList.Add([pscustomobject]@{
        File = $file.Name
        TotalKeys = $result.LangKeys.Count
        Missing = $result.Missing.Count
        Redundant = $result.Redundant.Count
        Duplicates = $result.Duplicates.Count
        Pass = $result.Pass
    })

    Write-Host ""
}

# ==============================================================================
# 6. 最终汇总报告与退出状态
# ==============================================================================
Write-Host "========================================================" -ForegroundColor DarkCyan
Write-Host " 多语言翻译检查汇总报告 " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor DarkCyan

$failedCount = 0
foreach ($item in $summaryList) {
    if (-not $item.Pass) { $failedCount++ }
    $statusColor = if ($item.Pass) { "Green" } else { "Red" }
    $statusText = if ($item.Pass) { "[通过]" } else { "[未通过]" }
    Write-Host "  $statusText $($item.File.PadRight(18)) 词条数: $($item.TotalKeys.ToString().PadRight(6)) 漏翻: $($item.Missing.ToString().PadRight(5)) 多翻: $($item.Redundant.ToString().PadRight(5)) 重复: $($item.Duplicates)" -ForegroundColor $statusColor
}
Write-Host ""

if ($failedCount -gt 0) {
    if ($Strict) {
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        Write-Host " [打包错误] 有 $failedCount 个语言包未通过完整性检查，打包已被即时中断！" -ForegroundColor Red
        Write-Host " 提示: 请先运行 .\CheckTranslations.ps1 查看详细未翻译词条，" -ForegroundColor Red
        Write-Host "       或运行 .\CheckTranslations.ps1 -Fix 自动同步词条。" -ForegroundColor Red
        Write-Host "--------------------------------------------------------`n" -ForegroundColor Red
        $global:LASTEXITCODE = 1
        exit 1
    } else {
        Write-Host "提示: 存在语言包未通过检查。运行 .\CheckTranslations.ps1 -Fix 可一键自动清理废弃词条并补全缺漏项。`n" -ForegroundColor Yellow
        $global:LASTEXITCODE = 1
        exit 1
    }
} else {
    Write-Host "恭喜！所有 $($targetFiles.Count) 个语言包均已通过完整性校验（无漏翻、无多翻、无重复）。`n" -ForegroundColor Green
    $global:LASTEXITCODE = 0
    exit 0
}
