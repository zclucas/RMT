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

        static mcodeHex := A_PtrSize == 8
            ? "89D0F08701C3"
            : "8B4424088B542404F08702C3"
        this.pXchg := DllCall("GlobalAlloc", "uint", 0, "ptr", StrLen(mcodeHex) // 2, "ptr")
        loop StrLen(mcodeHex) // 2
            NumPut("uchar", "0x" . SubStr(mcodeHex, (A_Index - 1) * 2 + 1, 2), this.pXchg, A_Index - 1)
        DllCall("VirtualProtect", "ptr", this.pXchg, "ptr", StrLen(mcodeHex) // 2, "uint", 0x40, "uint*", 0)
    }

    __Delete() {
        if (this.pXchg)
            DllCall("GlobalFree", "ptr", this.pXchg)
    }

    GetHead() => NumGet(this.headPtr, "UInt")
    SetHead(v) => NumPut("UInt", v, this.headPtr)
    GetTail() => NumGet(this.tailPtr, "UInt")
    SetTail(v) => NumPut("UInt", v, this.tailPtr)

    ExchangeNotifyFlag(v) => DllCall(this.pXchg, "ptr", this.notifyFlagPtr, "int", v, "int")
    SetNotifyFlag(v) => NumPut("Int", v, this.notifyFlagPtr)

    IsEmpty() => this.GetHead() == this.GetTail()

    ; Push: [Type][ID][hEvent][Len][Payload]
    Push(type, id, str := "", hEvent := 0) {
        len := (StrLen(str) + 1) * 2
        headerSize := 20
        total := (headerSize + len + 7) & ~7

        head := this.GetHead()
        tail := this.GetTail()

        ; Unsigned 32-bit safe size
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
        StrPut(str, this.bufPtr + pos + 20)

        this.SetHead(head + total)
        return true
    }

    Pop(&type, &id, &str, &hEvent := 0) {
        head := this.GetHead()
        tail := this.GetTail()

        if (tail == head)
            return false

        pos := tail & this.mask

        type_signed := NumGet(this.bufPtr, pos, "Int")
        if (type_signed == -1) {
            tail += (this.cap - pos)
            this.SetTail(tail)
            return this.Pop(&type, &id, &str, &hEvent)
        }

        type := NumGet(this.bufPtr, pos, "UInt")
        id := NumGet(this.bufPtr, pos + 4, "UInt")
        hEvent := NumGet(this.bufPtr, pos + 8, "Int64")
        len := NumGet(this.bufPtr, pos + 16, "UInt")
        str := StrGet(this.bufPtr + pos + 20)

        total := (20 + len + 7) & ~7
        this.SetTail(tail + total)
        return true
    }
}

; Event Helpers
CreateEvent(name := 0) {
    return DllCall("CreateEvent", "ptr", 0, "int", true, "int", false, "ptr", name ? StrPtr(name) : 0, "ptr")
}

OpenEvent(name) {
    return DllCall("OpenEvent", "uint", 0x1F0003, "int", 0, "str", name, "ptr")
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