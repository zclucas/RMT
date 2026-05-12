#Requires AutoHotkey v2.0

class SharedMemory {
    __New(name, size) {
        this.size := size
        this.hMap := DllCall("CreateFileMapping"
            , "ptr", -1
            , "ptr", 0
            , "uint", 0x04 ; PAGE_READWRITE
            , "uint", 0
            , "uint", size
            , "str", name
            , "ptr")
        if (!this.hMap)
            throw Error("Failed to CreateFileMapping: " name " (Error: " A_LastError ")")
            
        this.ptr := DllCall("MapViewOfFile"
            , "ptr", this.hMap
            , "uint", 0xF001F ; FILE_MAP_ALL_ACCESS
            , "uint", 0
            , "uint", 0
            , "ptr", size
            , "ptr")
        if (!this.ptr)
            throw Error("Failed to MapViewOfFile for: " name " (Error: " A_LastError ")")
    }

    Close() {
        if (this.ptr) {
            DllCall("UnmapViewOfFile", "ptr", this.ptr)
            this.ptr := 0
        }
        if (this.hMap) {
            DllCall("CloseHandle", "ptr", this.hMap)
            this.hMap := 0
        }
    }

    __Delete() {
        this.Close()
    }
}
