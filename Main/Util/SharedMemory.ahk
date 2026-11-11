#Requires AutoHotkey v2.0

class SharedMemory {
    __New(size, inheritedHandle := 0) {
        this.size := size
        this.ptr := 0
        this.hMap := inheritedHandle
        if (!this.hMap)
            this.hMap := DllCall("CreateFileMappingW"
            , "ptr", -1
            , "ptr", 0
            , "uint", 0x04 ; PAGE_READWRITE
            , "uint", 0
            , "uint", size
            , "ptr", 0
            , "ptr")
        if (!this.hMap)
            throw Error("Failed to create Worker shared memory (Error: " A_LastError ")")
            
        this.ptr := DllCall("MapViewOfFile"
            , "ptr", this.hMap
            , "uint", 0x0006 ; FILE_MAP_READ | FILE_MAP_WRITE
            , "uint", 0
            , "uint", 0
            , "ptr", size
            , "ptr")
        if (!this.ptr)
            throw Error("Failed to map Worker shared memory (Error: " A_LastError ")")
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
