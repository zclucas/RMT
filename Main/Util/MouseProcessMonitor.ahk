#Requires AutoHotkey v2.0

class MouseProcessMonitor {
    static _hwnd := 0
    static _pid := 0
    static _nextSample := 0
    static _job := ""
    static _values := Map()
    static _exitRegistered := false
    static _process := 0
    static _cpuTime := 0
    static _cpuTick := 0
    static _cores := 0

    static Update(hwnd, pid) {
        now := A_TickCount
        this._hwnd := hwnd
        if (pid != this._pid) {
            this._CloseProcess()
            this._pid := pid
            this._values := Map()
        }
        if (this._job)
            NumPut("UInt", hwnd ? pid : 0, this._job.Memory.ptr, this._job.Memory.size - 8)
        if (!hwnd || !pid)
            return

        this._UpdateFastValues()
        if (this._job) {
            job := this._job
            this._ReadJobValues(job)
            if (DllCall("WaitForSingleObject", "Ptr", job.Handle, "UInt", 0, "UInt") == 0) {
                ; 进程可能刚好在上一次读取期间完成写入，释放映射前再取最终结果。
                this._ReadJobValues(job)
                this._ReleaseJob()
                this._nextSample := now + 1000
            } else if (now - job.LastData >= 7000) {
                this._ReleaseJob(true)
                this._nextSample := now + 1000
            }
        }
        if (!this._job && now >= this._nextSample)
            this._StartJob()
    }

    ; 与坐标信息共用 100ms 刷新周期；CPU 使用相邻两帧差值，不在界面线程 Sleep。
    static _UpdateFastValues() {
        if (!this._process) {
            this._process := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", this._pid, "Ptr")
            if (!this._process)
                return
            times := ProcessInfo.Times(this._process)
            if (!times || times.Exited) {
                this._CloseProcess()
                return
            }
            this._values["StartTimeVar"] := ProcessInfo.LocalTime(times.Created)
            this._cpuTime := times.Cpu
            this._cpuTick := DllCall("GetTickCount64", "UInt64")
            if (!this._cores)
                this._cores := Max(1, DllCall("GetActiveProcessorCount", "UShort", 0xffff, "UInt"))
        } else
            times := ProcessInfo.Times(this._process)
        if (!times || times.Exited) {
            this._CloseProcess()
            this._values := Map()
            return
        }
        now := 0
        DllCall("GetSystemTimeAsFileTime", "Int64*", &now)
        this._values["UptimeVar"] := Max(0, now - times.Created) / 10000000
        tick := DllCall("GetTickCount64", "UInt64")
        elapsed := tick - this._cpuTick
        if (elapsed >= 50) {
            used := Min(this._cores, Max(0, (times.Cpu - this._cpuTime) / (10000 * elapsed)))
            this._values["CpuCores"] := used
            this._values["CpuTotalCores"] := this._cores
            this._values["CpuVar"] := 100 * used / this._cores
            this._cpuTime := times.Cpu
            this._cpuTick := tick
        }
    }

    static _CloseProcess() {
        if (this._process)
            DllCall("CloseHandle", "Ptr", this._process)
        this._process := 0
        this._cpuTick := 0
        this._cpuTime := 0
    }

    static _ReadJobValues(job) {
        version := NumGet(job.Memory.ptr, job.Memory.size - 4, "UInt")
        if (Mod(version, 2) || (job.HasProp("ReadVersion") && job.ReadVersion == version))
            return
        chars := NumGet(job.Memory.ptr, 0, "UInt")
        if (chars <= 0 || chars >= (job.Memory.size - 12) // 2)
            return
        payload := StrGet(job.Memory.ptr + 4, chars, "UTF-16")
        if (version != NumGet(job.Memory.ptr, job.Memory.size - 4, "UInt"))
            return
        try {
            values := JSON.parse(payload, false, true)
            if (values is Map && values.Count) {
                job.ReadVersion := version
                job.LastData := A_TickCount
                ; 切换目标期间可能收到上一 PID 的结果，不能覆盖当前进程的信息。
                if (values.Get("Pid", 0) != this._pid)
                    return
                for field in ["GpuVar", "GpuMemory"] {
                    if (values.Has(field))
                        this._values[field] := values[field]
                }
            }
        }
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
            NumPut("UInt", this._pid, memory.ptr, memory.size - 8)
            child := LaunchWorkerProcess(exe, args "--mouse-gpu-info", memory.hMap)
            this._job := {Handle: child.handle, Memory: memory, Started: A_TickCount, LastData: A_TickCount}
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
        this._CloseProcess()
        this._hwnd := 0
        this._pid := 0
    }

    static Text(field) {
        value := this._values.Get(field, "")
        if (field == "CpuVar") {
            if (value == "")
                return ""
            size := Format(GetLang("{} 核"), Format("{:.2f}", this._values["CpuCores"]))
            return size " · " Format("{:.2f}%", value)
        }
        if (field == "GpuVar") {
            bytes := this._values.Get("GpuMemory", "")
            size := bytes == "" ? "" : Format("{:.1f} MiB", bytes / 1048576)
            percent := value == "" ? "" : Format("{:.2f}%", value)
            return size (size != "" && percent != "" ? " · " : "") percent
        }
        if (field == "UptimeVar" && value != "") {
            return ProcessInfo.FormatUptime(value)
        }
        return value
    }
}
