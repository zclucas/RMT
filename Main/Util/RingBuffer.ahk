#Requires AutoHotkey v2.0
#Include ..\Shared\WorkerIpcLayout.ahk
; RingBuffer for Single Producer / Single Consumer
; Layout:
; offset 0:   head (uint)
; offset 64:  tail (uint)
; offset 128: notifyFlag (int)
; offset 192: buf (data area)
class RingBuffer {
    __New(ptr, capacityBytes) {
        if (capacityBytes < 64 || (capacityBytes & (capacityBytes - 1)))
            throw Error("RingBuffer capacity must be power of 2")

        this.basePtr := ptr
        this.headPtr := ptr + WorkerIpcLayout.HeadOffset
        this.tailPtr := ptr + WorkerIpcLayout.TailOffset
        this.notifyFlagPtr := ptr + WorkerIpcLayout.NotifyOffset
        this.bufPtr := ptr + WorkerIpcLayout.RingMetadataBytes
        this.capacityBytes := capacityBytes
        this.mask := capacityBytes - 1
        this.valid := true
        this.outbox := []
        this.partial := ""
    }

    ; 保留未写入的消息，发送端有空间后按原顺序补发。
    Send(type, id, payload := "", flags := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (!this.valid)
                return false
            this.outbox.Push({type: type, id: id, payload: payload, flags: flags, nextCharIndex: 1})
            this.Flush()
            return true
        } finally Critical(previousCritical)
    }

    Flush() {
        previousCritical := A_IsCritical
        Critical("On")
        written := false
        try {
            while (this.valid && this.outbox.Length) {
                packet := this.outbox[1]
                ; 帧最大占用四分之一容量，尾部填充也不会阻塞空缓冲区。
                chunkSize := Min(WorkerIpcLayout.MaxChunkChars, (this.capacityBytes // 4 - WorkerIpcLayout.FrameHeaderBytes) // WorkerIpcLayout.Utf16UnitBytes - 1)
                chunk := SubStr(packet.payload, packet.nextCharIndex, Max(2, chunkSize))
                more := packet.nextCharIndex + StrLen(chunk) <= StrLen(packet.payload)
                if (more) {
                    lastUnit := NumGet(StrPtr(chunk), (StrLen(chunk) - 1) * 2, "UShort")
                    if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF)
                        chunk := SubStr(chunk, 1, -1)
                }
                if (!this._Push(more ? WorkerIpcLayout.ContinuationType : packet.type, packet.id, chunk, packet.flags))
                    break
                written := true
                if (more)
                    packet.nextCharIndex += StrLen(chunk)
                else
                    this.outbox.RemoveAt(1)
            }
            return written
        } finally Critical(previousCritical)
    }

    ; 共享内存被 Unmap 前必须调用：之后任何读写都安全地退化为空/失败，
    ; 避免 Worker 被强杀/重建时，残留引用读取已释放内存导致 invalid memory read/write。
    Invalidate() {
        this.valid := false
        this.outbox := []
        this.partial := ""
    }

    GetHead() => this.valid ? NumGet(this.headPtr, "UInt") : 0
    SetHead(v) {
        if (this.valid)
            NumPut("UInt", v, this.headPtr)
    }
    GetTail() => this.valid ? NumGet(this.tailPtr, "UInt") : 0
    SetTail(v) {
        if (this.valid)
            NumPut("UInt", v, this.tailPtr)
    }
    IsEmpty() => !this.valid || this.GetHead() == this.GetTail()

    ; Push: [Type][ID][flags][Len][Payload]
    Push(type, id, str := "", flags := 0) {
        ; 单生产者/单消费者是按进程划分的；AHK 定时器和消息回调仍可能中断同进程线程。
        previousCritical := A_IsCritical
        Critical("On")
        try return this._Push(type, id, str, flags)
        finally Critical(previousCritical)
    }

    _Push(type, id, str, flags) {
        if (!this.valid)
            return false

        payloadBytes := (StrLen(str) + 1) * WorkerIpcLayout.Utf16UnitBytes
        headerSize := WorkerIpcLayout.FrameHeaderBytes
        frameBytes := (headerSize + payloadBytes + WorkerIpcLayout.AlignmentBytes - 1) & ~(WorkerIpcLayout.AlignmentBytes - 1)

        head := this.GetHead()
        tail := this.GetTail()

        usedBytes := (head - tail) & WorkerIpcLayout.CounterMask
        if (usedBytes + frameBytes + WorkerIpcLayout.AlignmentBytes >= this.capacityBytes)
            return false

        bufferOffset := head & this.mask

        if (bufferOffset + frameBytes > this.capacityBytes) {
            if (this.capacityBytes - bufferOffset >= 4)
                NumPut("Int", WorkerIpcLayout.WrapMarker, this.bufPtr, bufferOffset)
            head += this.capacityBytes - bufferOffset
            bufferOffset := 0

            usedBytes := (head - tail) & WorkerIpcLayout.CounterMask
            if (usedBytes + frameBytes + WorkerIpcLayout.AlignmentBytes >= this.capacityBytes)
                return false
        }

        NumPut("UInt", type, this.bufPtr, bufferOffset)
        NumPut("UInt", id, this.bufPtr, bufferOffset + WorkerIpcLayout.FrameIdOffset)
        NumPut("Int64", flags, this.bufPtr, bufferOffset + WorkerIpcLayout.FrameFlagsOffset)
        NumPut("UInt", payloadBytes, this.bufPtr, bufferOffset + WorkerIpcLayout.FrameLengthOffset)
        StrPut(str, this.bufPtr + bufferOffset + WorkerIpcLayout.FrameHeaderBytes, "UTF-16")

        this.SetHead(head + frameBytes)
        return true
    }

    Pop(&type, &id, &str, &flags := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            while (this._Pop(&type, &id, &str, &flags)) {
                if (type == WorkerIpcLayout.ContinuationType) {
                    this.partial .= str
                    continue
                }
                if (this.partial != "") {
                    str := this.partial str
                    this.partial := ""
                }
                return true
            }
            return false
        }
        finally Critical(previousCritical)
    }

    _Pop(&type, &id, &str, &flags) {
        if (!this.valid)
            return false

        head := this.GetHead()
        tail := this.GetTail()

        if (tail == head)
            return false

        available := (head - tail) & WorkerIpcLayout.CounterMask
        if (available >= this.capacityBytes || (available & (WorkerIpcLayout.AlignmentBytes - 1)) || (tail & (WorkerIpcLayout.AlignmentBytes - 1)))
            throw Error("Invalid IPC buffer cursor")
        bufferOffset := tail & this.mask

        signedType := NumGet(this.bufPtr, bufferOffset, "Int")
        if (signedType == WorkerIpcLayout.WrapMarker) {
            if (this.capacityBytes - bufferOffset >= available)
                throw Error("Invalid IPC wrap marker")
            tail += (this.capacityBytes - bufferOffset)
            this.SetTail(tail)
            return this._Pop(&type, &id, &str, &flags)
        }

        if (Min(available, this.capacityBytes - bufferOffset) < WorkerIpcLayout.MinimumFrameBytes)
            throw Error("Incomplete IPC frame")
        type := NumGet(this.bufPtr, bufferOffset, "UInt")
        id := NumGet(this.bufPtr, bufferOffset + WorkerIpcLayout.FrameIdOffset, "UInt")
        flags := NumGet(this.bufPtr, bufferOffset + WorkerIpcLayout.FrameFlagsOffset, "Int64")
        payloadBytes := NumGet(this.bufPtr, bufferOffset + WorkerIpcLayout.FrameLengthOffset, "UInt")
        frameBytes := (WorkerIpcLayout.FrameHeaderBytes + payloadBytes + WorkerIpcLayout.AlignmentBytes - 1) & ~(WorkerIpcLayout.AlignmentBytes - 1)
        if (payloadBytes < WorkerIpcLayout.Utf16UnitBytes || (payloadBytes & 1) || frameBytes > Min(available, this.capacityBytes - bufferOffset))
            throw Error("Invalid IPC frame length")
        if (NumGet(this.bufPtr, bufferOffset + WorkerIpcLayout.FrameHeaderBytes + payloadBytes - WorkerIpcLayout.Utf16UnitBytes, "UShort") != 0)
            throw Error("Unterminated IPC frame")
        str := payloadBytes == WorkerIpcLayout.Utf16UnitBytes ? "" : StrGet(this.bufPtr + bufferOffset + WorkerIpcLayout.FrameHeaderBytes, payloadBytes // WorkerIpcLayout.Utf16UnitBytes - 1, "UTF-16")
        this.SetTail(tail + frameBytes)
        return true
    }
}

; Event Helpers
CreateEvent() {
    return DllCall("CreateEventW", "ptr", 0, "int", false, "int", false, "ptr", 0, "ptr")
}

SetEvent(h) {
    DllCall("SetEvent", "ptr", h)
}

ResetEvent(h) {
    DllCall("ResetEvent", "ptr", h)
}

CloseHandle(h) {
    DllCall("CloseHandle", "ptr", h)
}

/*
====================================================================
R1 輕量化分隔符協定 (取代 JSON)
- 採用自訂分隔符：`0x01` (欄位分隔)、`0x02` (指令分隔)、`0x03` (轉義字元)。
- 實作防錯的 Escape/Unescape 迴圈解析器 (EscapeIPC / UnescapeIPC)，能正確處理尾端損壞的封包。
- 指令重構：改用雙字元 Opcode (如 SV、SA、JY、TR 等) 進行封包路由與分派。
====================================================================
*/
global IPC_SEP := Chr(1)
global IPC_REC := Chr(2)
global IPC_ESC := Chr(3)

EscapeIPC(str) {
    ; 数据中不能再保留分隔符本身：接收端先 StrSplit，再反转义。
    ; 必须先转义 ESC，否则真实的 ESC + 数字会与编码冲突。
    str := StrReplace(str, IPC_ESC, IPC_ESC "3")
    str := StrReplace(str, IPC_SEP, IPC_ESC "1")
    str := StrReplace(str, IPC_REC, IPC_ESC "2")
    return str
}

UnescapeIPC(str) {
    result := ""
    textIndex := 1
    while (escapeIndex := InStr(str, IPC_ESC, true, textIndex)) {
        result .= SubStr(str, textIndex, escapeIndex - textIndex)
        nextChar := SubStr(str, escapeIndex + 1, 1)
        if (nextChar == "1" || nextChar == "2" || nextChar == "3") {
            result .= nextChar == "1" ? IPC_SEP : (nextChar == "2" ? IPC_REC : IPC_ESC)
            textIndex := escapeIndex + 2
        } else {
            result .= IPC_ESC
            textIndex := escapeIndex + 1
        }
    }
    return result SubStr(str, textIndex)
}

EncodeCommand(opcode, args*) {
    packet := opcode
    for arg in args {
        packet .= IPC_SEP EscapeIPC(String(arg))
    }
    return packet
}

EncodeBatch(commands*) {
    packet := "R1"
    for cmd in commands {
        packet .= IPC_REC cmd
    }
    return packet
}
