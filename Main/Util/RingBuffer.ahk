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
        this.notifyPtr := ptr + 128
        this.bufPtr := ptr + 192
        this.cap := cap
        this.mask := cap - 1
    }

    GetHead() => NumGet(this.headPtr, 0, "UInt")
    SetHead(v) => NumPut("UInt", v, this.headPtr)

    GetTail() => NumGet(this.tailPtr, 0, "UInt")
    SetTail(v) => NumPut("UInt", v, this.tailPtr)

    GetNotifyFlag() => NumGet(this.notifyPtr, 0, "Int")
    SetNotifyFlag(v) => NumPut("Int", v, this.notifyPtr, 0)

    ExchangeNotifyFlag(v) {
        static pXchg := 0

        if (!pXchg) {
            mcodeHex := A_PtrSize == 8
                ? "89D0F08701C3"
                : "8B4424088B542404F08702C3"

            size := StrLen(mcodeHex) // 2

            pXchg := DllCall("Kernel32\VirtualAlloc"
                , "ptr", 0
                , "ptr", size
                , "uint", 0x1000
                , "uint", 0x40
                , "ptr")

            Loop size {
                byte := "0x" . SubStr(mcodeHex, (A_Index - 1) * 2 + 1, 2)
                NumPut("UChar", Integer(byte), pXchg + A_Index - 1)
            }
        }

        return DllCall(pXchg
            , "ptr", this.notifyPtr
            , "int", v
            , "int")
    }

    IsEmpty() => this.GetHead() == this.GetTail()

    ; Push: [Type][ID][hEvent][Len][Payload]
    Push(type, id, str := "", hEvent := 0) {
        len := (StrLen(str) + 1) * 2
        headerSize := 20 ; Fixed header: 4 type + 4 ID + 8 hEvent + 4 len
        total := (headerSize + len + 7) & ~7 ; 8-byte aligned

        head := this.GetHead()
        tail := this.GetTail()

        ; check available space
        avail := (tail > head) ? (tail - head) : (this.cap - (head - tail))
        if (avail <= total + 8)
            return false

        pos := head & this.mask

        ; if it doesn't fit at the end of buffer, insert wrap marker and wrap around
        if (pos + total > this.cap) {
            if (this.cap - pos >= 4) {
                NumPut("Int", -1, this.bufPtr, pos)
            }
            head += this.cap - pos
            pos := 0

            ; Re-check space after wrap
            avail := (tail > head) ? (tail - head) : (this.cap - (head - tail))
            if (avail <= total + 8)
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

        if (tail >= head)
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

        ; Read string, stopping at first null terminator
        str := StrGet(this.bufPtr + pos + 20)

        total := (20 + len + 7) & ~7
        this.SetTail(tail + total)
        return true
    }
}

; Event Helpers
CreateEvent(name := 0) {
    return DllCall("CreateEvent", "ptr", 0, "int", false, "int", false, "ptr", name ? StrPtr(name) : 0, "ptr")
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