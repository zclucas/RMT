#Requires AutoHotkey v2.0
; RingBuffer for Single Producer / Single Consumer
; Layout:
; offset 0:   head (uint)
; offset 64:  tail (uint)
; offset 128: notifyFlag (int)
; offset 192: buf (data area)
class RingBuffer {
    __New(ptr, cap) {
        if (cap & (cap - 1))
            throw Error("RingBuffer capacity must be power of 2")

        this.basePtr := ptr
        this.headPtr := ptr
        this.tailPtr := ptr + 64
        this.notifyFlagPtr := ptr + 128
        this.bufPtr := ptr + 192
        this.cap := cap
        this.mask := cap - 1
        this.valid := true
    }

    ; 共享内存被 Unmap 前必须调用：之后任何读写都安全地退化为空/失败，
    ; 避免 Worker 被强杀/重建时，残留引用读取已释放内存导致 invalid memory read/write。
    Invalidate() {
        this.valid := false
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

    ; Push: [Type][ID][hEvent][Len][Payload]
    Push(type, id, str := "", hEvent := 0) {
        ; 单生产者/单消费者是按进程划分的；AHK 定时器和消息回调仍可能中断同进程线程。
        previousCritical := A_IsCritical
        Critical("On")
        try return this._Push(type, id, str, hEvent)
        finally Critical(previousCritical)
    }

    _Push(type, id, str, hEvent) {
        if (!this.valid)
            return false

        len := (StrLen(str) + 1) * 2
        headerSize := 20
        total := (headerSize + len + 7) & ~7

        head := this.GetHead()
        tail := this.GetTail()

        size := (head - tail) & 0xFFFFFFFF
        if (size + total + 8 >= this.cap)
            return false

        pos := head & this.mask

        if (pos + total > this.cap) {
            if (this.cap - pos >= 4)
                NumPut("Int", -1, this.bufPtr, pos)
            head += this.cap - pos
            pos := 0

            size := (head - tail) & 0xFFFFFFFF
            if (size + total + 8 >= this.cap)
                return false
        }

        NumPut("UInt", type, this.bufPtr, pos)
        NumPut("UInt", id, this.bufPtr, pos + 4)
        NumPut("Int64", hEvent, this.bufPtr, pos + 8)
        NumPut("UInt", len, this.bufPtr, pos + 16)
        StrPut(str, this.bufPtr + pos + 20, "UTF-16")

        this.SetHead(head + total)
        return true
    }

    Pop(&type, &id, &str, &hEvent := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        try return this._Pop(&type, &id, &str, &hEvent)
        finally Critical(previousCritical)
    }

    _Pop(&type, &id, &str, &hEvent) {
        if (!this.valid)
            return false

        head := this.GetHead()
        tail := this.GetTail()

        if (tail == head)
            return false

        pos := tail & this.mask

        type_signed := NumGet(this.bufPtr, pos, "Int")
        if (type_signed == -1) {
            tail += (this.cap - pos)
            this.SetTail(tail)
            return this._Pop(&type, &id, &str, &hEvent)
        }

        type := NumGet(this.bufPtr, pos, "UInt")
        id := NumGet(this.bufPtr, pos + 4, "UInt")
        hEvent := NumGet(this.bufPtr, pos + 8, "Int64")
        len := NumGet(this.bufPtr, pos + 16, "UInt")
        str := StrGet(this.bufPtr + pos + 20, "UTF-16")

        total := (20 + len + 7) & ~7
        this.SetTail(tail + total)
        return true
    }
}

; Event Helpers
CreateEvent(name := "") {
    return DllCall("CreateEventW", "ptr", 0, "int", false, "int", false, "ptr", name ? StrPtr(name) : 0, "ptr")
}

OpenEvent(name) {
    return DllCall("OpenEventW", "uint", 0x00100002, "int", false, "ptr", StrPtr(name), "ptr")
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
    pos := 1
    while (pos <= StrLen(str)) {
        char := SubStr(str, pos, 1)
        nextChar := SubStr(str, pos + 1, 1)
        if (char == IPC_ESC && (nextChar == "1" || nextChar == "2" || nextChar == "3")) {
            result .= nextChar == "1" ? IPC_SEP : (nextChar == "2" ? IPC_REC : IPC_ESC)
            pos += 2
        } else {
            result .= char
            pos++
        }
    }
    return result
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
