#Requires AutoHotkey v2.0

; 同一秒内的等长改写也应使配置缓存失效。一次查询取得原始 FILETIME 和文件大小。
FileStamp(path) {
    attributes := Buffer(36)
    if (path == "" || !DllCall("GetFileAttributesExW", "Str", path, "Int", 0, "Ptr", attributes))
        return "0"
    return NumGet(attributes, 20, "Int64") "|" NumGet(attributes, 28, "UInt") "|" NumGet(attributes, 32, "UInt")
}
