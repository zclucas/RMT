#Requires AutoHotkey v2.0

class MouseProcessMonitor {
    static _hwnd := 0
    static _pid := 0
    static _nextSample := 0
    static _job := ""
    static _values := Map()
    static _exitRegistered := false

    static Update(hwnd, pid) {
        now := A_TickCount
        if (hwnd != this._hwnd || pid != this._pid) {
            this._ReleaseJob(true)
            this._hwnd := hwnd
            this._pid := pid
            this._values := Map()
            this._nextSample := now + 250
        }
        if (!hwnd || !pid)
            return

        if (this._job) {
            job := this._job
            if (DllCall("WaitForSingleObject", "Ptr", job.Handle, "UInt", 0, "UInt") == 0) {
                chars := NumGet(job.Memory.ptr, 0, "UInt")
                this._values := Map()
                if (chars > 0 && chars < (job.Memory.size - 4) // 2)
                    try this._values := JSON.parse(StrGet(job.Memory.ptr + 4, chars, "UTF-16"), false, true)
                this._ReleaseJob()
                this._nextSample := now + 1000
            } else if (now - job.Started >= 7000) {
                this._ReleaseJob(true)
                this._values := Map()
                this._nextSample := now + 1000
            }
        }
        if (!this._job && now >= this._nextSample)
            this._StartJob()
    }

    static _StartJob() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!this._exitRegistered) {
                OnExit((*) => MouseProcessMonitor.Stop())
                this._exitRegistered := true
            }
            memory := SharedMemory(ProcessInfo.MouseSampleSize)
            exe := A_IsCompiled ? A_ScriptDir "\Thread\Work.exe" : A_AhkPath
            args := A_IsCompiled ? "" : '/ErrorStdOut=UTF-8 "' A_ScriptDir '\Thread\Work.ahk" '
            child := LaunchWorkerProcess(exe, args "--mouse-process-info " this._hwnd " " this._pid, memory.hMap)
            this._job := {Handle: child.handle, Memory: memory, Started: A_TickCount}
        } catch {
            this._nextSample := A_TickCount + 1000
        } finally Critical(previousCritical)
    }

    static _ReleaseJob(cancel := false) {
        if (!this._job)
            return
        job := this._job
        this._job := ""
        if (cancel)
            DllCall("TerminateProcess", "Ptr", job.Handle, "UInt", 0)
        DllCall("CloseHandle", "Ptr", job.Handle)
        job.Memory.Close()
    }

    static Stop() {
        this._ReleaseJob(true)
        this._hwnd := 0
        this._pid := 0
    }

    static Text(field) {
        value := this._values.Get(field, "")
        if (field == "CpuVar") {
            if (value == "")
                return ""
            size := Format(GetLang("{} / {} 核"), Format("{:.2f}", this._values["CpuCores"]), this._values["CpuTotalCores"])
            return size " · " Format("{:.2f}%", value)
        }
        if (field == "GpuVar") {
            bytes := this._values.Get("GpuMemory", "")
            size := bytes == "" ? "" : Format("{:.1f} MiB", bytes / 1048576)
            percent := value == "" ? "" : Format("{:.2f}%", value)
            return size (size != "" && percent != "" ? " · " : "") percent
        }
        if (field == "UptimeVar" && value != "")
            return Format("{:.1f} s", value)
        return value
    }
}
