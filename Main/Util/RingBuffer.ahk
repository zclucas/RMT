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
- 徹底移除底層通訊對 JSON 序列化/反序列化的依賴，解決字串解析效能瓶頸。
- 採用自訂分隔符：`0x01` (欄位分隔)、`0x02` (指令分隔)、`0x03` (轉義字元)。
- 實作防錯的 Escape/Unescape 迴圈解析器 (EscapeIPC / UnescapeIPC)，能正確處理尾端損壞的封包。
- 指令重構：全面改用雙字元 Opcode (如 SV、SA、JY、TR 等) 進行封包路由與分派。

陣列同步優化
- 支援無限多維嵌套陣列同步：廢除原本受限於二維的 MainIndex/Index 系統，改用點狀路徑 (Dot Path, 如 1.2.3)。
====================================================================
*/

EscapeIPC(str) {
    str := StrReplace(str, Chr(3), Chr(3) Chr(3))
    str := StrReplace(str, Chr(1), Chr(3) Chr(1))
    str := StrReplace(str, Chr(2), Chr(3) Chr(2))
    return str
}

UnescapeIPC(str) {
    out := ""
    escape := false
    Loop Parse, str {
        c := A_LoopField
        if (escape) {
            out .= c
            escape := false
        } else if (c == Chr(3)) {
            escape := true
        } else {
            out .= c
        }
    }
    if (escape)
        out .= Chr(3)
    return out
}

EncodeCommand(opcode, args*) {
    packet := opcode
    for arg in args {
        packet .= Chr(1) EscapeIPC(String(arg))
    }
    return packet
}

EncodeBatch(commands*) {
    packet := "R1"
    for cmd in commands {
        packet .= Chr(2) cmd
    }
    return packet
}