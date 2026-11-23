#Requires AutoHotkey v2.0

; 鼠标监视专用 PDH 采样器：计数器跨采样周期复用，不通过 WMI 重建整组性能数据。
class MouseGpuSampler {
    ; DllCall 临时载入后会卸载 DLL；PDH 查询句柄依赖模块内状态，必须保持模块驻留。
    static _module := DllCall("LoadLibraryW", "Str", "pdh.dll", "Ptr")
    __New() {
        this.query := 0
        this.primed := false
        query := 0
        if (DllCall("pdh\PdhOpenQueryW", "Ptr", 0, "UPtr", 0, "Ptr*", &query, "UInt"))
            return
        this.query := query
        this.engine := this._Add("\GPU Engine(*)\Utilization Percentage")
        this.dedicated := this._Add("\GPU Process Memory(*)\Dedicated Usage")
        this.shared := this._Add("\GPU Process Memory(*)\Shared Usage")
    }

    _Add(path) {
        counter := 0
        if (DllCall("pdh\PdhAddEnglishCounterW", "Ptr", this.query, "Str", path,
            "UPtr", 0, "Ptr*", &counter, "UInt"))
            return 0
        return counter
    }

    Sample(pid) {
        result := Map("Pid", pid)
        if (!this.query || DllCall("pdh\PdhCollectQueryData", "Ptr", this.query, "UInt"))
            return result
        if (this.primed && this.engine) {
            values := this._Read(this.engine, pid)
            if (IsObject(values)) {
                peak := 0
                for value in values
                    peak := Max(peak, value)
                result["GpuVar"] := Min(100, peak)
            }
        }
        this.primed := true
        if (this.dedicated && this.shared) {
            dedicated := this._Read(this.dedicated, pid)
            shared := this._Read(this.shared, pid)
            if (IsObject(dedicated) && IsObject(shared)) {
                bytes := 0
                for values in [dedicated, shared]
                    for value in values
                        bytes += value
                result["GpuMemory"] := bytes
            }
        }
        return result
    }

    _Read(counter, pid) {
        size := 0, count := 0
        status := DllCall("pdh\PdhGetFormattedCounterArrayW", "Ptr", counter, "UInt", 0x200,
            "UInt*", &size, "UInt*", &count, "Ptr", 0, "UInt")
        if (status != 0x800007D2 || !size)
            return status == 0 ? [] : ""
        ; 实例可能在两次调用之间增减；缓冲区不足时重新询问大小。
        loop 3 {
            itemsBuffer := Buffer(size)
            status := DllCall("pdh\PdhGetFormattedCounterArrayW", "Ptr", counter, "UInt", 0x200,
                "UInt*", &size, "UInt*", &count, "Ptr", itemsBuffer, "UInt")
            if (status == 0)
                break
            if (status != 0x800007D2)
                return ""
            size := 0
            DllCall("pdh\PdhGetFormattedCounterArrayW", "Ptr", counter, "UInt", 0x200,
                "UInt*", &size, "UInt*", &count, "Ptr", 0)
            if (!size)
                return ""
        }
        if (status != 0 || count * 24 > itemsBuffer.Size)
            return ""
        values := []
        prefix := "pid_" pid "_"
        ; PDH_FMT_COUNTERVALUE_ITEM_W：指针、8 字节对齐的状态/值，x86/x64 均为 24 字节。
        loop count {
            offset := (A_Index - 1) * 24
            name := NumGet(itemsBuffer, offset, "Ptr")
            state := NumGet(itemsBuffer, offset + 8, "UInt")
            if (name && state <= 1 && InStr(StrGet(name, "UTF-16"), prefix) == 1)
                values.Push(Max(0, NumGet(itemsBuffer, offset + 16, "Double")))
        }
        return values
    }

    Close() {
        if (this.query) {
            DllCall("pdh\PdhCloseQuery", "Ptr", this.query)
            this.query := 0
        }
    }
    __Delete() => this.Close()

    static Run(memory, parent) {
        sampler := MouseGpuSampler()
        try {
            while (DllCall("WaitForSingleObject", "Ptr", parent, "UInt", 0, "UInt") == 258) {
                pid := NumGet(memory.ptr, memory.size - 8, "UInt")
                if (pid) {
                    result := sampler.Sample(pid)
                    ProcessInfo.PublishMouseSample(memory, result)
                }
                Sleep(200)
            }
        } finally sampler.Close()
    }
}
