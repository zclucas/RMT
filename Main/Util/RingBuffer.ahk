#Requires AutoHotkey v2.0

; RingBuffer for Single Producer / Single Consumer
; Layout:
; offset 0:  head (uint)
; offset 64: tail (uint)
; offset 128: buf
class RingBuffer {
    __New(ptr, cap) {
        if (cap & (cap - 1))
            throw Error("RingBuffer capacity must be power of 2")

        this.basePtr := ptr
        this.headPtr := ptr
        this.tailPtr := ptr + 64
        this.bufPtr := ptr + 128
        this.cap := cap
        this.mask := cap - 1
    }

    GetHead() => NumGet(this.headPtr, 0, "UInt")
    SetHead(v) => NumPut("UInt", v, this.headPtr)

    GetTail() => NumGet(this.tailPtr, 0, "UInt")
    SetTail(v) => NumPut("UInt", v, this.tailPtr)

    ; Push: [Type][ID][hEvent (optional)][Len][Payload]
    Push(type, id, str := "", hEvent := 0) {
        len := (StrLen(str) + 1) * 2
        ; if hEvent is provided, we need 8 extra bytes
        headerSize := hEvent ? 20 : 12 ; 4 type + 4 ID + (8 hEvent) + 4 len
        total := headerSize + len

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
        if (hEvent) {
            NumPut("Int64", hEvent, this.bufPtr, pos + 8)
            NumPut("UInt", len, this.bufPtr, pos + 16)
            StrPut(str, this.bufPtr + pos + 20)
        } else {
            NumPut("UInt", len, this.bufPtr, pos + 8)
            StrPut(str, this.bufPtr + pos + 12)
        }

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

        ; We need to know if the message HAS an hEvent.
        ; For now, let's assume type TASK has hEvent, others don't.
        ; Or we can add a flag to the type.
        ; Let's assume hEvent is present if the caller expects it (passed by reference).
        ; Actually, it's better to store a flag or use the 'type' field.
        ; For RMT: TASK (1) has hEvent, others don't.

        if (type == 1) { ; MsgType.TASK
            hEvent := NumGet(this.bufPtr, pos + 8, "Int64")
            len := NumGet(this.bufPtr, pos + 16, "UInt")
            str := StrGet(this.bufPtr + pos + 20, len // 2)
            this.SetTail(tail + 20 + len)
        } else {
            hEvent := 0
            len := NumGet(this.bufPtr, pos + 8, "UInt")
            str := StrGet(this.bufPtr + pos + 12, len // 2)
            this.SetTail(tail + 12 + len)
        }

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