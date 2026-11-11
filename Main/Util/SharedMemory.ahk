#Requires AutoHotkey v2.0

class SharedMemory {
    ; attach = true 时按名称挂到已存在的映射（OpenFileMapping）。
    ; 悬浮窗文本槽由主进程创建，Worker 只写不建，因此只需 attach 模式：
    ; Worker 可直接写入最新值并唤醒引擎窗口，全程不经过主进程。
    __New(name, size, attach := false) {
        this.size := size
        if (attach)
            this.hMap := DllCall("OpenFileMappingW"
                , "uint", 0xF001F ; FILE_MAP_ALL_ACCESS：视图读写权限
                , "int", 0
                , "str", name
                , "ptr")
        else
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
