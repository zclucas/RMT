#Requires AutoHotkey v2.0
#Include MouseGpuSampler.ahk

class ProcessInfo {
    static Metrics := ["StatusVar", "StartTimeVar", "UptimeVar", "CpuVar", "GpuVar", "IntegrityVar"]
    static MouseMetrics := ["StartTimeVar", "UptimeVar", "CpuVar", "GpuVar"]
    static MouseSampleSize := 4096

    static ReadMetrics(data, process, snapshotTime, result, preview, withUsageSize := false, onProgress := 0) {
        want := Map()
        for field in this.Metrics {
            if (preview || (data.HasProp(field) && data.%field% != ""))
                want[field] := true
        }
        if (!want.Count)
            return

        ; 查询和采样期间持有同一个进程句柄，避免把复用 PID 的新进程读成原进程。
        handle := DllCall("OpenProcess", "UInt", 0x101000, "Int", false, "UInt", process.Pid, "Ptr")
        if (!handle)
            return
        try {
            times := this.Times(handle)
            if (!times || times.Created > snapshotTime || times.Exited)
                return
            if (want.Has("StartTimeVar"))
                try result.StartTimeVar := this.LocalTime(times.Created)
            if (want.Has("UptimeVar"))
                result.UptimeVar := Round(Max(0, snapshotTime - times.Created) / 10000000, 3)
            if (want.Has("IntegrityVar"))
                try result.IntegrityVar := this.Integrity(handle)
            if (want.Has("StatusVar"))
                try result.StatusVar := this.Status(handle, process)
            ; 鼠标监视先回传基础信息，避免 GPU/WMI 或 CPU 采样拖住整组字段。
            if (onProgress)
                onProgress.Call(result)
            if (want.Has("CpuVar")) {
                try {
                    sample := this.CpuUsage(handle)
                    if (sample) {
                        result.CpuVar := sample.Percent
                        if (withUsageSize) {
                            result.CpuCores := sample.UsedCores
                            result.CpuTotalCores := sample.TotalCores
                        }
                    }
                }
            }
            if (onProgress)
                onProgress.Call(result)
            if (want.Has("GpuVar") && DllCall("WaitForSingleObject", "Ptr", handle, "UInt", 0, "UInt") == 258) {
                try result.GpuVar := this.GpuUsage(process.Pid)
                if (withUsageSize)
                    try result.GpuMemory := this.GpuMemory(process.Pid)
            }
        } finally DllCall("CloseHandle", "Ptr", handle)
    }

    static MouseSample(hwnd, pid, onProgress := 0) {
        result := {}
        if (WinGetPID(hwnd) != pid)
            return result
        snapshotTime := 0
        DllCall("GetSystemTimeAsFileTime", "Int64*", &snapshotTime)
        requested := {}
        for field in this.MouseMetrics
            requested.%field% := true
        this.ReadMetrics(requested, {Hwnd: hwnd, Pid: pid}, snapshotTime, result, false, true, onProgress)
        return result
    }

    static PublishMouseSample(memory, sample) {
        payload := JSON.stringify(sample, 0)
        ; 首部 4 字节存长度，尾部 8 字节保留请求 PID 与写入序号，正文不覆盖控制字段。
        if (StrLen(payload) >= (memory.size - 12) // 2)
            return
        version := NumGet(memory.ptr, memory.size - 4, "UInt")
        NumPut("UInt", version + 1, memory.ptr, memory.size - 4)
        NumPut("UInt", 0, memory.ptr)
        StrPut(payload, memory.ptr + 4, (memory.size - 12) // 2, "UTF-16")
        NumPut("UInt", StrLen(payload), memory.ptr)
        NumPut("UInt", version + 2, memory.ptr, memory.size - 4)
    }

    static Times(handle) {
        created := 0, exited := 0, kernel := 0, user := 0
        if (!DllCall("GetProcessTimes", "Ptr", handle, "Int64*", &created, "Int64*", &exited,
            "Int64*", &kernel, "Int64*", &user, "Int"))
            return false
        return {Created: created, Exited: exited, Cpu: kernel + user}
    }

    static LocalTime(fileTime) {
        utc := Buffer(16), localTime := Buffer(16)
        if (!DllCall("FileTimeToSystemTime", "Int64*", &fileTime, "Ptr", utc)
            || !DllCall("SystemTimeToTzSpecificLocalTime", "Ptr", 0, "Ptr", utc, "Ptr", localTime))
            return ""
        return Format("{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
            NumGet(localTime, 0, "UShort"), NumGet(localTime, 2, "UShort"), NumGet(localTime, 6, "UShort"),
            NumGet(localTime, 8, "UShort"), NumGet(localTime, 10, "UShort"), NumGet(localTime, 12, "UShort"))
    }

    static CpuUsage(handle) {
        before := this.Times(handle)
        start := DllCall("GetTickCount64", "UInt64")
        if (!before || before.Exited)
            return ""
        Sleep(250)
        after := this.Times(handle)
        elapsed := DllCall("GetTickCount64", "UInt64") - start
        cores := DllCall("GetActiveProcessorCount", "UShort", 0xffff, "UInt")
        if (!after || after.Exited || elapsed <= 0 || !cores)
            return ""
        usedCores := Min(cores, Max(0, (after.Cpu - before.Cpu) / (10000 * elapsed)))
        return {UsedCores: usedCores, TotalCores: cores, Percent: Round(100 * usedCores / cores, 2)}
    }

    static GpuUsage(pid) {
        ; WMI 提供已计算的利用率，并使用与系统语言无关的类名。
        peak := 0
        for engine in this.GpuCounters("GPUEngine", "UtilizationPercentage", pid)
            peak := Max(peak, Number(engine.UtilizationPercentage))
        return Min(100, peak)
    }

    static GpuMemory(pid) {
        bytes := 0
        for adapter in this.GpuCounters("GPUProcessMemory", "DedicatedUsage, SharedUsage", pid)
            bytes += Number(adapter.DedicatedUsage) + Number(adapter.SharedUsage)
        return bytes
    }

    static GpuCounters(className, fields, pid) {
        static wmi := ComObjGet("winmgmts:\\.\root\cimv2")
        return wmi.ExecQuery("SELECT " fields " FROM Win32_PerfFormattedData_GPUPerformanceCounters_" className
            " WHERE Name LIKE 'pid[_]" pid "[_]%'")
    }

    static Integrity(handle) {
        token := 0
        if (!DllCall("advapi32\OpenProcessToken", "Ptr", handle, "UInt", 8, "Ptr*", &token))
            return ""
        try {
            size := 0
            ; TokenIntegrityLevel (25) 返回 TOKEN_MANDATORY_LABEL，SID 是第一个字段。
            DllCall("advapi32\GetTokenInformation", "Ptr", token, "Int", 25, "Ptr", 0, "UInt", 0, "UInt*", &size)
            if (!size)
                return ""
            label := Buffer(size)
            if (!DllCall("advapi32\GetTokenInformation", "Ptr", token, "Int", 25, "Ptr", label, "UInt", size, "UInt*", &size))
                return ""
            sid := NumGet(label, 0, "Ptr")
            count := NumGet(DllCall("advapi32\GetSidSubAuthorityCount", "Ptr", sid, "Ptr"), 0, "UChar")
            level := NumGet(DllCall("advapi32\GetSidSubAuthority", "Ptr", sid, "UInt", count - 1, "Ptr"), 0, "UInt")
            switch {
                case level < 0x1000: return "不受信任"
                case level < 0x2000: return "低"
                case level < 0x3000: return "中"
                case level < 0x4000: return "高"
                case level < 0x5000: return "系统"
                default: return "受保护"
            }
        } finally DllCall("CloseHandle", "Ptr", token)
    }

    static Status(handle, process) {
        threads := this.ThreadStates(process.Pid)
        if (threads.Length) {
            suspended := true
            for thread in threads
                suspended := suspended && thread.Suspended
            if (suspended)
                return "挂起"
        }

        hung := Map(), hasWindow := false
        windows := process.HasProp("Hwnd") ? [process.Hwnd] : WinGetList("ahk_pid " process.Pid)
        for hwnd in windows {
            if (!DllCall("IsWindowVisible", "Ptr", hwnd))
                continue
            hasWindow := true
            if (DllCall("IsHungAppWindow", "Ptr", hwnd)) {
                pid := 0
                tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
                if (tid && pid == process.Pid)
                    hung[tid] := true
            }
        }
        if (this.HasBlockingChain(threads, hung))
            return "阻塞"
        if (hung.Count)
            return "无响应"
        if (!hasWindow && DllCall("WaitForInputIdle", "Ptr", handle, "UInt", 0, "UInt") == 258)
            return "加载"
        return threads.Length || hasWindow ? "正常" : ""
    }

    static ThreadStates(pid) {
        ; SystemProcessInformation 的进程头和线程数组相邻，布局随指针宽度变化。
        size := 65536
        loop 5 {
            snapshot := Buffer(size)
            used := 0
            status := DllCall("ntdll\NtQuerySystemInformation", "Int", 5, "Ptr", snapshot, "UInt", size, "UInt*", &used, "UInt")
            if (!status)
                break
            if (status != 0xc0000004 || A_Index == 5)
                return []
            size := Max(size * 2, used + 65536)
        }
        if (A_PtrSize == 8)
            pidOffset := 80, header := 256, stride := 80, tidOffset := 48, stateOffset := 68
        else
            pidOffset := 68, header := 184, stride := 64, tidOffset := 36, stateOffset := 52
        pos := 0, limit := Min(used, snapshot.Size)
        while (pos + header <= limit) {
            next := NumGet(snapshot, pos, "UInt")
            if (next && (next < header || pos + next > limit))
                break
            if (NumGet(snapshot, pos + pidOffset, "UPtr") == pid) {
                count := NumGet(snapshot, pos + 4, "UInt")
                if (pos + header + count * stride > (next ? pos + next : limit))
                    return []
                threads := []
                loop count {
                    entry := pos + header + (A_Index - 1) * stride
                    state := NumGet(snapshot, entry + stateOffset, "UInt")
                    reason := NumGet(snapshot, entry + stateOffset + 4, "UInt")
                    if (state != 4)
                        threads.Push({Id: NumGet(snapshot, entry + tidOffset, "UPtr"),
                            Waiting: state == 5, Suspended: state == 5 && (reason == 5 || reason == 12)})
                }
                return threads
            }
            if (!next)
                break
            pos += next
        }
        return []
    }

    static HasBlockingChain(threads, hung) {
        candidates := hung.Clone()
        for thread in threads {
            if (thread.Waiting && !thread.Suspended && !candidates.Has(thread.Id))
                candidates[thread.Id] := false
        }
        if (!candidates.Count)
            return false
        session := DllCall("advapi32\OpenThreadWaitChainSession", "UInt", 0, "Ptr", 0, "Ptr")
        if (!session)
            return false
        try {
            ; WCT_MAX_NODE_COUNT = 16，WAITCHAIN_NODE_INFO 在 x86 和 x64 均为 280 字节。
            nodes := Buffer(16 * 280)
            for tid, windowHung in candidates {
                count := 16, cycle := 0
                if (DllCall("advapi32\GetThreadWaitChain", "Ptr", session, "Ptr", 0, "UInt", 1,
                    "UInt", tid, "UInt*", &count, "Ptr", nodes, "Int*", &cycle)
                    && (cycle || (windowHung && count > 1)))
                    return true
            }
        } finally DllCall("advapi32\CloseThreadWaitChainSession", "Ptr", session)
        return false
    }
}
