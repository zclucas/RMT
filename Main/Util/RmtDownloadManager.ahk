#Requires AutoHotkey v2.0

class RmtDownloadManager {
    static jobs := Map()
    static queue := []
    static activeId := ""
    static timer := ""

    static DownloadBlocking(url, targetPath, timeoutSec, progress) {
        return DownloadAsync(url, targetPath, timeoutSec, progress)
    }

    static Enqueue(name, urls, targetPath, minBytes := 0, timeoutSec := 7200, onComplete := 0) {
        if (!IsObject(urls))
            urls := [String(urls)]
        if (!urls.Length || targetPath == "")
            throw Error("Download requires at least one URL and a target path")

        SplitPath(targetPath, , &targetDir)
        if (targetDir != "")
            DirCreate(targetDir)
        id := StrLower(targetPath)
        resumeIndex := this.jobs.Has(id) && FileExist(targetPath ".part")
            && this.jobs[id].HasOwnProp("urlIndex")
            ? this.jobs[id].urlIndex : 1
        if (this.jobs.Has(id)) {
            job := this.jobs[id]
            if (job.status == "queued" || job.status == "downloading")
                return id
            if (job.status == "completed" && this._FileReady(targetPath, minBytes)) {
                job.onComplete := onComplete
                this._Notify(job)
                return id
            }
        } else {
            job := {id: id, createdAt: A_TickCount}
        }

        job.name := name
        job.urls := urls.Clone()
        ; GitCode 下载原文件或 LFS 模型；备用地址直连 GitHub 原附件。
        for url in urls {
            alternative := RmtDownloadDirectUrl(url)
            if (RmtIsAssetUrl(url) && alternative != "") {
                exists := false
                for candidate in job.urls {
                    if (candidate == alternative) {
                        exists := true
                        break
                    }
                }
                if (!exists)
                    job.urls.Push(alternative)
            }
        }
        job.targetPath := targetPath
        job.partPath := targetPath ".part"
        job.headersPath := targetPath ".headers"
        job.minBytes := Max(0, Integer(minBytes))
        job.timeoutSec := Max(1, Integer(timeoutSec))
        job.onComplete := onComplete
        job.urlIndex := Min(Max(1, resumeIndex), job.urls.Length)
        job.pid := 0
        job.processHandle := 0
        job.receivedBytes := 0
        job.expectedBytes := 0
        job.error := ""
        job.status := "queued"
        this.jobs[id] := job

        if (this._FileReady(targetPath, job.minBytes)) {
            job.status := "completed"
            job.receivedBytes := FileGetSize(targetPath)
            job.expectedBytes := job.receivedBytes
            this._Notify(job)
            return id
        }

        this.queue.Push(id)
        this._StartNext()
        return id
    }

    static Retry(id) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!this.jobs.Has(id))
                return false
            job := this.jobs[id]
            if (job.status != "completed" && job.status != "failed" && job.status != "cancelled")
                return false
            this._DeleteJobFiles(job)
            this.Enqueue(job.name, job.urls, job.targetPath, job.minBytes, job.timeoutSec, job.onComplete)
            return true
        } finally Critical(previousCritical)
    }

    static Delete(id) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!this.jobs.Has(id))
                return false
            job := this.jobs[id]
            if (job.status != "completed" && job.status != "failed" && job.status != "cancelled")
                return false
            this._DeleteJobFiles(job)
            this.jobs.Delete(id)
            return true
        } finally Critical(previousCritical)
    }

    static _DeleteJobFiles(job) {
        paths := [job.headersPath, job.partPath, job.partPath ".unpacked", job.targetPath]
        try {
            ; 先确认全部文件可删除，避免目标正在使用时先丢掉断点文件。
            for path in paths {
                if (InStr(path, "*") || InStr(path, "?") || InStr(FileExist(path), "D"))
                    throw Error(GetLang("下载目标不是文件，无法删除"))
                if (!FileExist(path))
                    continue
                handle := DllCall("CreateFileW", "Str", path, "UInt", 0x10000, "UInt", 0,
                    "Ptr", 0, "UInt", 3, "UInt", 0x80, "Ptr", 0, "Ptr")
                if (handle == -1)
                    throw OSError(A_LastError)
                DllCall("CloseHandle", "Ptr", handle)
            }
            for path in paths
                if (FileExist(path))
                    FileDelete(path)
        } catch OSError as problem {
            if (problem.Number == 32 || problem.Number == 33 || problem.Number == 1224)
                throw Error(GetLang("正在使用，无法删除"))
            throw Error(GetLang("删除失败") "：" problem.Message)
        }
    }

    static Cancel(id) {
        if (!this.jobs.Has(id))
            return false
        job := this.jobs[id]
        if (job.status == "queued") {
            job.status := "cancelled"
            this._Notify(job)
            return true
        }
        if (job.status != "downloading")
            return false
        if (job.pid && ProcessExist(job.pid))
            try ProcessClose(job.pid)
        this._CloseProcessHandle(job)
        try FileDelete(job.headersPath)
        job.status := "cancelled"
        this.activeId := ""
        this._Notify(job)
        this._StartNext()
        return true
    }

    static Snapshot() {
        result := []
        for id, job in this.jobs
            result.Push(job)
        return result
    }

    static _FileReady(path, minBytes) {
        if (RmtAssetMissing(path))
            return false
        try return FileGetSize(path) >= minBytes
        return false
    }

    static _StartNext() {
        if (this.activeId != "")
            return
        while (this.queue.Length) {
            id := this.queue.RemoveAt(1)
            if (!this.jobs.Has(id))
                continue
            job := this.jobs[id]
            if (job.status != "queued")
                continue
            if (this._FileReady(job.targetPath, job.minBytes)) {
                job.status := "completed"
                job.receivedBytes := FileGetSize(job.targetPath)
                job.expectedBytes := job.receivedBytes
                this._Notify(job)
                continue
            }
            this.activeId := id
            if (!this._StartUrl(job))
                this._TryNextUrl(job, GetLang("无法启动下载进程"))
            if (this.activeId != "")
                break
        }
        if (this.activeId != "" && this.timer == "") {
            this.timer := ObjBindMethod(this, "_Poll")
            SetTimer(this.timer, 500)
        } else if (this.activeId == "" && this.timer != "") {
            SetTimer(this.timer, 0)
            this.timer := ""
        }
    }

    static _StartUrl(job) {
        if (job.urlIndex > job.urls.Length)
            return false
        try FileDelete(job.headersPath)
        job.receivedBytes := 0
        job.expectedBytes := 0
        curl := A_WinDir "\System32\curl.exe"
        if (!FileExist(curl))
            curl := "curl.exe"
        cmd := this._Quote(curl) " -L --fail -sS --show-error --connect-timeout 30"
            . " --max-time " job.timeoutSec " --retry 2 -C - -D " this._Quote(job.headersPath)
            . " -o " this._Quote(job.partPath) " " this._Quote(job.urls[job.urlIndex])
        try {
            if (RmtIsAssetUrl(job.urls[job.urlIndex]))
                cmd := RmtAssetDownloadCommand(job.urls[job.urlIndex], job.partPath, job.headersPath, job.timeoutSec)
            Run(cmd, A_WorkingDir, "Hide", &pid)
            job.pid := pid
            job.processHandle := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
            job.startedAt := A_TickCount
            job.status := "downloading"
            return true
        } catch as error {
            job.error := error.Message
            return false
        }
    }

    static _Poll() {
        if (this.activeId == "" || !this.jobs.Has(this.activeId)) {
            this.activeId := ""
            this._StartNext()
            return
        }
        job := this.jobs[this.activeId]
        try job.receivedBytes := FileGetSize(job.partPath)
        if (!job.expectedBytes)
            job.expectedBytes := RmtDownloadContentLength(job.headersPath)

        if (A_TickCount - job.startedAt > job.timeoutSec * 1000 + 5000) {
            if (job.pid && ProcessExist(job.pid))
                try ProcessClose(job.pid)
            this._CloseProcessHandle(job)
            this._TryNextUrl(job, GetLang("下载超时"))
            return
        }

        exitCode := 259
        hasExitCode := job.processHandle
            ? DllCall("GetExitCodeProcess", "Ptr", job.processHandle, "UInt*", &exitCode, "Int")
            : false
        if (hasExitCode && exitCode == 259)
            return
        if (!hasExitCode && job.pid && ProcessExist(job.pid))
            return

        this._CloseProcessHandle(job)
        if ((hasExitCode && exitCode == 0 || !hasExitCode)
            && this._FileReady(job.partPath, job.minBytes)) {
            try {
                FileMove(job.partPath, job.targetPath, true)
                job.receivedBytes := FileGetSize(job.targetPath)
                job.expectedBytes := job.receivedBytes
                job.status := "completed"
                job.error := ""
                this._FinishActive(job)
                return
            } catch as error {
                this._TryNextUrl(job, error.Message)
                return
            }
        }
        this._TryNextUrl(job, hasExitCode
            ? Format(GetLang("curl 下载失败，错误码 {}"), exitCode) : GetLang("下载文件无效"))
    }

    static _TryNextUrl(job, error) {
        this._CloseProcessHandle(job)
        job.error := error
        try FileDelete(job.headersPath)
        try FileDelete(job.partPath ".unpacked")
        if (job.urlIndex < job.urls.Length) {
            job.urlIndex += 1
            try FileDelete(job.partPath)
            if (this._StartUrl(job))
                return
        }
        job.status := "failed"
        this._FinishActive(job)
    }

    static _FinishActive(job) {
        this.activeId := ""
        this._Notify(job)
        this._StartNext()
    }

    static _Notify(job) {
        if (IsObject(job.onComplete)) {
            try job.onComplete.Call(job)
            catch as error
                RMTErrorShow("下载完成回调失败：" error.Message, RMT_LV_WARN, "RmtDownloadManager")
        }
    }

    static _CloseProcessHandle(job) {
        if (job.processHandle) {
            DllCall("CloseHandle", "Ptr", job.processHandle)
            job.processHandle := 0
        }
    }

    static _Quote(value) {
        return '"' StrReplace(String(value), '"', '\"') '"'
    }
}

; 主程序内嵌脚本，发行版不依赖源码目录；独立进程可被下载取消直接终止。
RmtAssetDownloadCommand(url, path, headers, timeoutSec) {
    static script := ""
    if (script == "" || !FileExist(script)) {
        dir := A_Temp "\RMT-AssetDownload-" DllCall("GetCurrentProcessId")
        DirCreate(dir)
        script := dir "\Download.ps1"
        FileInstall("Main\Util\RmtDownloadFile.ps1", script, true)
    }
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    return '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script
        . '" -Url "' url '" -Path "' path '" -Headers "' headers '" -TimeoutSec ' timeoutSec
}
