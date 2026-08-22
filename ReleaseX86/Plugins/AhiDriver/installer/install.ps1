param(
    [ValidateSet("menu", "install", "uninstall", "repair", "status")]
    [string]$Action = "menu",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
try {
    chcp 65001 > $null
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$ScriptPath = $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptPath
$Installer = Join-Path $Root "install-interception.exe"
$LogFile = Join-Path $Root "install-log.txt"
$DriversDir = Join-Path $env:WINDIR "System32\drivers"
$KbdSys = Join-Path $DriversDir "keyboard.sys"
$MouSys = Join-Path $DriversDir "mouse.sys"
$KbdClass = "{4D36E96B-E325-11CE-BFC1-08002BE10318}"
$MouClass = "{4D36E96F-E325-11CE-BFC1-08002BE10318}"

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $Message
}

function Test-IsAdmin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-IsAdmin) { return }
    Write-Host "正在请求管理员权限..."
    Write-Host "请在 UAC 提示中选择「是」。"
    Write-Host ""
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action $Action"
    if ($NoPause) { $argList += " -NoPause" }
    try {
        $proc = Start-Process -FilePath $ps -ArgumentList $argList -Verb RunAs -Wait -PassThru
        if ($null -eq $proc) { exit 1 }
        exit $proc.ExitCode
    } catch {
        Write-Host "[错误] 自动提权失败：$($_.Exception.Message)"
        Write-Host "请右键「安装卸载.bat」-> 以管理员身份运行"
        Pause-Exit 1
    }
}

function Pause-Exit([int]$Code) {
    if (-not $NoPause) {
        Write-Host ""
        Write-Host "按 Enter 键退出..."
        [void][Console]::ReadLine()
    }
    exit $Code
}

function Get-FileProduct([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return [Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName } catch { return "" }
}

function Get-UpperFilters([string]$ClassGuid) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$ClassGuid"
    $v = (Get-ItemProperty -Path $path -Name UpperFilters -ErrorAction SilentlyContinue).UpperFilters
    if ($null -eq $v) { return [string[]]@() }
    return [string[]]@($v | ForEach-Object { "$_" } | Where-Object { $_ -and $_.Trim() -ne "" })
}

function Set-UpperFilters([string]$ClassGuid, [string[]]$Filters) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$ClassGuid"
    $flat = [string[]]@($Filters | ForEach-Object { "$_" } | Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notlike "System.Object*" })
    New-ItemProperty -Path $path -Name UpperFilters -PropertyType MultiString -Value $flat -Force | Out-Null
}

function Ensure-FilterFirst {
    param([string[]]$Current, [string]$Name)
    $result = New-Object System.Collections.Generic.List[string]
    [void]$result.Add($Name)
    foreach ($item in @($Current)) {
        $s = "$item"
        if ($s -and $s.Trim() -ne "" -and $s -notlike "System.Object*" -and $s.ToLowerInvariant() -ne $Name.ToLowerInvariant()) {
            [void]$result.Add($s)
        }
    }
    return [string[]]$result.ToArray()
}

function Remove-FilterName {
    param([string[]]$Current, [string]$Name)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Current)) {
        $s = "$item"
        if ($s -and $s.Trim() -ne "" -and $s -notlike "System.Object*" -and $s.ToLowerInvariant() -ne $Name.ToLowerInvariant()) {
            [void]$result.Add($s)
        }
    }
    return [string[]]$result.ToArray()
}

function Ensure-DriverService([string]$Name, [string]$DisplayName) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -Path $path -Name DisplayName -PropertyType String -Value $DisplayName -Force | Out-Null
    New-ItemProperty -Path $path -Name Type -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $path -Name ErrorControl -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $path -Name Start -PropertyType DWord -Value 3 -Force | Out-Null
    $image = "\SystemRoot\System32\drivers\$Name.sys"
    New-ItemProperty -Path $path -Name ImagePath -PropertyType ExpandString -Value $image -Force | Out-Null
}

function Get-StatusInfo {
    $kbdProduct = Get-FileProduct $KbdSys
    $mouProduct = Get-FileProduct $MouSys
    $kbdFilters = Get-UpperFilters $KbdClass
    $mouFilters = Get-UpperFilters $MouClass
    $kbdSvc = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\keyboard"
    $mouSvc = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\mouse"
    $filesOk = ($kbdProduct -eq "Interception" -and $mouProduct -eq "Interception")
    $hooksOk = ($kbdFilters -contains "keyboard") -and ($mouFilters -contains "mouse")
    $svcOk = $kbdSvc -and $mouSvc
    return [pscustomobject]@{
        FilesOk     = $filesOk
        HooksOk     = $hooksOk
        ServicesOk  = $svcOk
        KbdProduct  = $kbdProduct
        MouProduct  = $mouProduct
        KbdFilters  = ($kbdFilters -join ", ")
        MouFilters  = ($mouFilters -join ", ")
        Complete    = ($filesOk -and $hooksOk -and $svcOk)
    }
}

function Show-Status {
    $s = Get-StatusInfo
    Write-Host "========== 当前状态 =========="
    Write-Host ("keyboard.sys     : " + $(if ($s.KbdProduct) { $s.KbdProduct } else { "不存在" }))
    Write-Host ("mouse.sys        : " + $(if ($s.MouProduct) { $s.MouProduct } else { "不存在" }))
    Write-Host ("键盘 UpperFilters: " + $(if ($s.KbdFilters) { $s.KbdFilters } else { "(空)" }))
    Write-Host ("鼠标 UpperFilters: " + $(if ($s.MouFilters) { $s.MouFilters } else { "(空)" }))
    Write-Host ("服务项是否齐全   : " + $(if ($s.ServicesOk) { "是" } else { "否" }))
    Write-Host ("是否安装完整     : " + $(if ($s.Complete) { "是" } else { "否" }))
    Write-Host "=============================="
    Write-Log ("状态 文件=$($s.FilesOk) 钩子=$($s.HooksOk) 服务=$($s.ServicesOk) 完整=$($s.Complete)")
    return $s
}

function Invoke-OfficialInstaller([string]$Mode) {
    if (-not (Test-Path -LiteralPath $Installer)) {
        Write-Log "[错误] 找不到安装程序：$Installer"
        return 1
    }
    Write-Host ""
    Write-Host "正在运行：install-interception.exe $Mode"
    Write-Host "----------------------------------------"
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $Installer
    $pinfo.Arguments = $Mode
    $pinfo.UseShellExecute = $false
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.WorkingDirectory = (Split-Path -Parent $Installer)
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $pinfo
    try { [void]$proc.Start() } catch {
        Write-Host "[错误] $($_.Exception.Message)"
        return 1
    }
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($stdout) { Write-Host $stdout; Write-Log ("STDOUT: " + ($stdout -replace "\r?\n", " | ")) }
    if ($stderr) { Write-Host $stderr; Write-Log ("STDERR: " + ($stderr -replace "\r?\n", " | ")) }
    Write-Host "----------------------------------------"
    Write-Log ("退出码 = " + $proc.ExitCode)
    return $proc.ExitCode
}

function Repair-Install {
    Write-Log "开始：修复/补全安装"
    $s = Show-Status
    Write-Host ""

    if (-not $s.FilesOk) {
        Write-Host "驱动文件缺失，先尝试官方安装器..."
        $code = Invoke-OfficialInstaller "/install"
        $s = Get-StatusInfo
        if (-not $s.FilesOk) {
            Write-Host "[错误] 官方安装器未能写入驱动文件。"
            Write-Host "退出码：$code"
            return 1
        }
    } else {
        Write-Host "已检测到 Interception 驱动文件，跳过文件复制。"
    }

    Write-Host "正在写入服务项..."
    Ensure-DriverService -Name "keyboard" -DisplayName "Keyboard Upper Filter Driver"
    Ensure-DriverService -Name "mouse" -DisplayName "Mouse Upper Filter Driver"

    Write-Host "正在更新 UpperFilters（保留原有过滤项）..."
    $kbd = Ensure-FilterFirst -Current (Get-UpperFilters $KbdClass) -Name "keyboard"
    if ($kbd -notcontains "kbdclass") { $kbd = [string[]]($kbd + @("kbdclass")) }
    Set-UpperFilters $KbdClass $kbd
    Write-Log ("键盘 UpperFilters = " + ($kbd -join ", "))

    $mou = Ensure-FilterFirst -Current (Get-UpperFilters $MouClass) -Name "mouse"
    if ($mou -notcontains "mouclass") { $mou = [string[]]($mou + @("mouclass")) }
    Set-UpperFilters $MouClass $mou
    Write-Log ("鼠标 UpperFilters = " + ($mou -join ", "))

    Write-Host ""
    $s2 = Show-Status
    if ($s2.Complete) {
        Write-Host "修复成功。"
        Write-Host "请立即重启电脑，驱动才会生效。"
        return 0
    }
    Write-Host "修复未完成，请查看上方状态。"
    return 1
}

function Uninstall-Interception {
    Write-Log "开始：卸载"
    Write-Host "正在移除注册表过滤钩子..."
    $kbd = Remove-FilterName -Current (Get-UpperFilters $KbdClass) -Name "keyboard"
    if (-not $kbd -or $kbd.Count -eq 0) { $kbd = [string[]]@("kbdclass") }
    if ($kbd -notcontains "kbdclass") { $kbd = [string[]]($kbd + @("kbdclass")) }
    Set-UpperFilters $KbdClass $kbd
    Write-Log ("键盘 UpperFilters = " + ($kbd -join ", "))

    $mou = Remove-FilterName -Current (Get-UpperFilters $MouClass) -Name "mouse"
    if (-not $mou -or $mou.Count -eq 0) { $mou = [string[]]@("mouclass") }
    if ($mou -notcontains "mouclass") { $mou = [string[]]($mou + @("mouclass")) }
    Set-UpperFilters $MouClass $mou
    Write-Log ("鼠标 UpperFilters = " + ($mou -join ", "))

    Write-Host "正在调用官方卸载程序（文件被占用时可能失败）..."
    [void](Invoke-OfficialInstaller "/uninstall")

    foreach ($name in @("keyboard", "mouse")) {
        $svc = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
        if (Test-Path $svc) {
            try {
                Remove-Item -LiteralPath $svc -Recurse -Force -ErrorAction Stop
                Write-Log "已删除服务项：$name"
            } catch {
                Write-Log ("未能删除服务项 ${name}：$($_.Exception.Message)")
            }
        }
    }

    foreach ($f in @($KbdSys, $MouSys)) {
        if (Test-Path -LiteralPath $f) {
            try {
                Remove-Item -LiteralPath $f -Force -ErrorAction Stop
                Write-Log "已删除文件：$f"
            } catch {
                Write-Log ("未能删除文件 ${f}：$($_.Exception.Message)")
                Write-Host "驱动文件正被占用（常见情况）。卸载钩子后重启，一般即可失效；"
                Write-Host "若需删除文件，可重启后再执行一次卸载。"
            }
        }
    }

    Write-Host ""
    Write-Host "卸载操作已完成（注册表钩子已移除）。"
    Write-Host "请重启电脑。重启后如需重装，再运行本脚本并选择「修复/补全安装」。"
    return 0
}

function Show-Menu {
    Clear-Host
    Write-Host "========================================"
    Write-Host "  Interception 驱动 安装 / 卸载"
    Write-Host "========================================"
    Write-Host ""
    $s = Get-StatusInfo
    Write-Host ("  管理员权限 : " + $(if (Test-IsAdmin) { "是" } else { "否" }))
    Write-Host ("  驱动文件   : " + $(if ($s.FilesOk) { "已就绪 (Interception)" } else { "缺失或不是 Interception" }))
    Write-Host ("  注册表钩子 : " + $(if ($s.HooksOk) { "已挂接" } else { "未挂接" }))
    Write-Host ("  安装完整   : " + $(if ($s.Complete) { "是" } else { "否" }))
    Write-Host ""
    if ($s.FilesOk -and -not $s.HooksOk) {
        Write-Host "  检测到：驱动文件已在，但注册表未挂接。"
        Write-Host "  建议选择 [3] 修复/补全安装"
        Write-Host ""
    } elseif ($s.Complete) {
        Write-Host "  当前已安装完整。若程序仍不可用，请先重启电脑。"
        Write-Host ""
    }
    Write-Host "  [1] 官方安装"
    Write-Host "  [2] 卸载"
    Write-Host "  [3] 修复/补全安装  （推荐，文件已存在时用这个）"
    Write-Host "  [4] 查看状态"
    Write-Host "  [0] 退出"
    Write-Host ""
    $opt = Read-Host "请选择"
    switch ($opt) {
        "1" { return "install" }
        "2" { return "uninstall" }
        "3" { return "repair" }
        "4" { return "status" }
        "0" { return "exit" }
        default {
            Write-Host "无效选项，请重新选择。"
            Start-Sleep -Seconds 1
            return (Show-Menu)
        }
    }
}

# Main
Ensure-Admin

if ($Action -eq "menu") {
    $choice = Show-Menu
    if ($choice -eq "exit") { exit 0 }
    $Action = $choice
}

$code = 0
switch ($Action) {
    "install" {
        $s = Get-StatusInfo
        if ($s.FilesOk) {
            Write-Host "驱动文件已存在。官方 /install 通常会报错："
            Write-Host "  Could not write to \system32\drivers"
            Write-Host "已自动改为「修复/补全安装」..."
            Write-Host ""
            $code = Repair-Install
        } else {
            $code = Invoke-OfficialInstaller "/install"
            $s2 = Get-StatusInfo
            if (($code -ne 0) -or (-not $s2.Complete)) {
                Write-Host "官方安装不完整，继续尝试修复/补全..."
                $code = Repair-Install
            }
        }
    }
    "uninstall" { $code = Uninstall-Interception }
    "repair"    { $code = Repair-Install }
    "status"    { [void](Show-Status); $code = 0 }
}

Write-Host ""
if ($code -eq 0) {
    if ($Action -ne "status") {
        Write-Host "操作结束。若进行了安装/修复/卸载，请立即重启电脑。"
    }
} else {
    Write-Host "操作失败，退出码：$code"
    Write-Host "详细日志：$LogFile"
}
Pause-Exit $code