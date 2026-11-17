#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, Off
#Include ..\Main\Util\JsonUtil.ahk
#Include ..\Main\Util\RmtProgress.ahk
#Include ..\Main\Util\RmtRelease.ahk
#Include ..\Main\Util\RmtReleaseScan.ahk

if (A_Args.Length && A_Args[1] == "--check") {
    if (A_Args.Length != 3)
        ExitApp(2)
    CheckReleases(A_Args[2], A_Args[3])
    ExitApp()
}

SetWorkingDir(A_ScriptDir)
stage := A_ScriptDir
script := stage "\UpdateFiles.ps1"
parent := 0
engine := 0
mutex := 0
progress := ""
job := ""
closedParent := false
cleanup := false
recovering := A_Args.Length && A_Args[1] == "--recover"
try {
    if (recovering) {
        SplitPath(stage, &folder, &root)
        if (!RegExMatch(folder, "i)^\.rmt-update-[a-f0-9]{32}$"))
            throw ValueError("Invalid recovery directory.")
        job := JSON.parse(FileRead(stage "\pending.json", "UTF-8"), , false)
        if (!RegExMatch(job.Original, "i)^RMT(?:v[\d.F]+)?\.exe$"))
            throw ValueError("Invalid RMT installation path")
        job.root := root
        job.original := root "\" job.Original
        job.mode := "recover"
    } else {
        job := JSON.parse(FileRead(stage "\job.json", "UTF-8"), , false)
        package := RmtRelease.Asset(job.name, job.url)
        if (!IsObject(package) || package.arch != job.arch || !(job.mode == "replace" || job.mode == "download"))
            throw ValueError("Invalid update request")
        SplitPath(job.original, &exe, &dir)
        if (job.mode == "replace" && (dir != job.root || !RegExMatch(exe, "i)^RMT(?:v[\d.F]+)?\.exe$")))
            throw ValueError("Invalid RMT installation path")
    }
    if (A_IsCompiled)
        FileInstall "UpdateFiles.ps1", script, true
    cleanup := A_IsCompiled
    ps := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    command := '"' ps '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script '"'
    if (job.mode != "download") {
        mutex := RmtUpdateMutex()
        if (!mutex)
            throw Error("Another update is already running.")
    }
    if (job.mode == "replace") {
        parent := DllCall("OpenProcess", "UInt", 0x100000, "Int", false, "UInt", job.parent, "Ptr")
        if (!parent)
            throw OSError()
        if (job.engine)
            engine := DllCall("OpenProcess", "UInt", 0x100000, "Int", false, "UInt", job.engine, "Ptr")
    }
    title := UpdateText(job, "软件更新")
    phase := recovering ? "正在恢复原程序…" : job.mode == "replace" ? "等待 RMT 退出…" : "正在下载更新包…"
    progress := RmtProgress(title, UpdateText(job, phase), , , true)
    progress.Show()
    if (!recovering) {
        if (FileExist(stage "\cancel"))
            throw Error("Update canceled.")
        FileAppend("", stage "\ready")
    }
    if (parent) {
        UpdateWait(parent, stage)
        closedParent := true
        if (engine)
            UpdateWait(engine, stage)
    }
    Run(command (recovering ? " -Recover" : ""), stage, "Hide", &transfer)
    previous := ""
    while (ProcessExist(transfer)) {
        current := ""
        try current := FileRead(stage "\progress.txt", "UTF-8")
        if (current != "" && current != previous) {
            parts := StrSplit(Trim(current, "`r`n"), "|", , 2)
            if (parts.Length == 2) {
                progress.Report(UpdateText(job, parts[2]), IsNumber(parts[1]) ? Number(parts[1]) : "")
                previous := current
            }
        }
        Sleep(100)
    }
    progress.Close()
    if (!FileExist(stage "\success"))
        throw Error(FileExist(stage "\error.txt") ? FileRead(stage "\error.txt", "UTF-8") : "Update process stopped.")
    if (mutex) {
        DllCall("CloseHandle", "Ptr", mutex)
        mutex := 0
    }
    if (job.mode != "download") {
        closedParent := false
        launcher := recovering ? job.original : job.root "\RMT.exe"
        try Run('"' launcher '"', job.root)
        catch as err
            MsgBox(UpdateText(job, "更新已完成，无法自动启动 RMT。") "`n" err.Message, title, 48)
    } else
        MsgBox(UpdateText(job, "更新包已保存。") "`n" job.path, title, 64)
} catch as err {
    if (IsObject(progress))
        progress.Close()
    if (mutex) {
        DllCall("CloseHandle", "Ptr", mutex)
        mutex := 0
    }
    MsgBox(UpdateText(job, "更新失败。") "`n" err.Message, UpdateText(job, "软件更新"), 16)
    if (closedParent && !FileExist(stage "\rollback-failed") && FileExist(job.original))
        try Run('"' job.original '"', job.root)
} finally {
    for handle in [parent, engine, mutex]
        if (handle)
            DllCall("CloseHandle", "Ptr", handle)
    if (cleanup)
        try Run(command " -CleanupPid " ProcessExist(), stage, "Hide")
}
ExitApp()

UpdateText(job, phrase) {
    if (IsObject(job) && job.HasProp("texts") && job.texts.HasProp(phrase))
        return job.texts.%phrase%
    return phrase
}

CheckReleases(stage, version) {
    SplitPath(stage, &folder, &parentDir)
    SplitPath(A_ScriptDir, , &appDir)
    if (parentDir != appDir "\Cache" || !RegExMatch(folder, "^RMT-Update-\d+-\d+-\d+$"))
        return
    response := {assets: [], error: ""}
    try {
        current := RmtRelease.Version(version)
        if (!IsObject(current))
            throw ValueError("Invalid RMT version.")
        response.assets := RmtReleaseScan.FetchReleases(current)
    } catch as err
        response.error := err.Message
    try FileAppend(JSON.stringify(response, 0), stage "\result.json", "UTF-8")
}

UpdateWait(handle, stage) {
    deadline := A_TickCount + 45000
    loop {
        status := DllCall("WaitForSingleObject", "Ptr", handle, "UInt", 0, "UInt")
        if (status == 0)
            return
        if (status != 258 || A_TickCount >= deadline || FileExist(stage "\cancel"))
            throw Error("RMT did not exit. Close RMT and try again.")
        Sleep(80)
    }
}
