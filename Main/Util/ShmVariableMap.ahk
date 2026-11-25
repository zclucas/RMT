#Requires AutoHotkey v2.0

/**
 * ShmVariableMap: 基于 Plugins\ShmVar\ShmVar.dll 的纯共享内存全局变量映射
 * 遵循 AHK v2 Map 语法接口：
 *   - map[key] := val
 *   - val := map[key] / map.Get(key, default)
 *   - map.Has(key)
 *   - map.Delete(key)
 *   - map.Clear()
 *   - map.Count
 *   - for k, v in map
 */
class ShmVariableMap {
    static DLL_PATH := ""
    static H_DLL := 0

    __New(mapName := "RMT_Shared_Variables", initialSize := 16777216) {
        this.mapName := mapName
        this.initialSize := initialSize
        ShmVariableMap._EnsureDll()

        nameBuf := Buffer(StrPut(mapName, "UTF-8"))
        StrPut(mapName, nameBuf, "UTF-8")
        rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_Init", "Ptr", nameBuf.Ptr, "UPtr", initialSize, "Cdecl Int")
        if (rc < 0) {
            throw Error("ShmVar_Init 失败，错误码: " rc)
        }
    }

    static _EnsureDll() {
        global AppRootDir, ProjectRootDir
        if (ShmVariableMap.H_DLL)
            return true

        dllName := "ShmVar.dll"
        hModule := DllCall("GetModuleHandleW", "Str", dllName, "Ptr")
        if (hModule) {
            modulePath := Buffer(32768 * 2, 0)
            length := DllCall("GetModuleFileNameW", "Ptr", hModule, "Ptr", modulePath, "UInt", 32768, "UInt")
            if (!length || length >= 32768)
                throw Error("获取 ShmVar.dll 路径失败，LastError: " A_LastError)
            ShmVariableMap.DLL_PATH := StrGet(modulePath, length)
            ShmVariableMap.H_DLL := hModule
            return true
        }

        ; 优先使用入口确定的根目录，并保留独立脚本与 Worker 的路径备援。
        candidates := []
        if (IsSet(AppRootDir) && AppRootDir != "")
            candidates.Push(AppRootDir "\Plugins\ShmVar\" dllName)
        if (IsSet(ProjectRootDir) && ProjectRootDir != "")
            candidates.Push(ProjectRootDir "\Plugins\ShmVar\" dllName)
        candidates.Push(A_ScriptDir "\Plugins\ShmVar\" dllName,
            A_ScriptDir "\..\Plugins\ShmVar\" dllName,
            A_ScriptDir "\..\..\Plugins\ShmVar\" dllName,
            A_WorkingDir "\Plugins\ShmVar\" dllName,
            A_WorkingDir "\..\Plugins\ShmVar\" dllName)
        dllPath := ""
        for p in candidates {
            if FileExist(p) {
                dllPath := p
                break
            }
        }
        if (dllPath == "")
            throw Error("未找到 " dllName "，请确认 Plugins\ShmVar\" dllName " 文件完整")

        ; 規整為標準絕對路徑
        buf := Buffer(65536 * 2, 0)
        n := DllCall("GetFullPathNameW", "Str", dllPath, "UInt", 65536, "Ptr", buf, "Ptr", 0, "UInt")
        dllPath := (n > 0 && n < 65536) ? StrGet(buf, n) : dllPath

        ; 按外掛目錄解析相依性（0x8 = LOAD_WITH_ALTERED_SEARCH_PATH）
        hMod := DllCall("LoadLibraryExW", "Str", dllPath, "Ptr", 0, "UInt", 0x8, "Ptr")
        if (!hMod) {
            hMod := DllCall("LoadLibraryW", "Str", dllPath, "Ptr")
        }
        if (!hMod) {
            throw Error("加载 ShmVar.dll 失败，LastError: " A_LastError " 路径: " dllPath)
        }

        ShmVariableMap.DLL_PATH := dllPath
        ShmVariableMap.H_DLL := hMod
        return true
    }

    static _ToUtf8(str) {
        buf := Buffer(StrPut(str, "UTF-8"))
        StrPut(str, buf, "UTF-8")
        return buf
    }

    __Item[key] {
        get {
            if (!this.Has(key))
                throw UnsetError("键不存在: " key)
            return this._Get(key)
        }
        set {
            this._Set(key, value)
        }
    }

    Get(key, defaultValue := unset) {
        if (this.Has(key))
            return this._Get(key)
        if (IsSet(defaultValue))
            return defaultValue
        throw UnsetError("键不存在: " key)
    }

    Set(key, value) {
        this._Set(key, value)
        return this
    }

    _Set(key, val) {
        kBuf := ShmVariableMap._ToUtf8(String(key))
        rc := 0

        if (IsInteger(val)) {
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_SetInt", "Ptr", kBuf.Ptr, "Int64", val, "Cdecl Int")
        } else if (IsFloat(val)) {
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_SetDouble", "Ptr", kBuf.Ptr, "Double", val, "Cdecl Int")
        } else {
            ; 字符串或对象序列化为 UTF-8 字符串
            sVal := String(val)
            vBuf := ShmVariableMap._ToUtf8(sVal)
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_SetStr", "Ptr", kBuf.Ptr, "Ptr", vBuf.Ptr, "Cdecl Int")
        }

        if (rc < 0) {
            throw Error("ShmVar_Set 失败，key=" key " 错误码=" rc)
        }
    }

    _Get(key) {
        kBuf := ShmVariableMap._ToUtf8(String(key))
        vType := 0
        vSize := 0

        rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetType", "Ptr", kBuf.Ptr, "Int*", &vType, "UPtr*", &vSize, "Cdecl Int")
        if (rc < 0)
            throw UnsetError("ShmVar_GetType 找不到键或失败，key=" key " 错误码=" rc)

        ; ShmVarType: NONE=0, INT=1, DOUBLE=2, STRING=3, BYTES=4
        if (vType == 1) {
            intVal := 0
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetInt", "Ptr", kBuf.Ptr, "Int64*", &intVal, "Cdecl Int")
            if (rc < 0)
                throw Error("ShmVar_GetInt 失败，key=" key " 错误码=" rc)
            return intVal
        } else if (vType == 2) {
            dVal := 0.0
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetDouble", "Ptr", kBuf.Ptr, "Double*", &dVal, "Cdecl Int")
            if (rc < 0)
                throw Error("ShmVar_GetDouble 失败，key=" key " 错误码=" rc)
            return dVal
        } else if (vType == 3) {
            if (vSize <= 0)
                return ""
            strBuf := Buffer(vSize + 1, 0)
            outLen := 0
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetStr", "Ptr", kBuf.Ptr, "Ptr", strBuf.Ptr, "UPtr", strBuf.Size, "UPtr*", &outLen, "Cdecl Int")
            if (rc < 0)
                throw Error("ShmVar_GetStr 失败，key=" key " 错误码=" rc)
            return StrGet(strBuf.Ptr, "UTF-8")
        } else if (vType == 4) {
            ; 任意二进制数据，作为 Buffer 返回
            if (vSize <= 0)
                return Buffer(0)
            byteBuf := Buffer(vSize)
            outLen := 0
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetBytes", "Ptr", kBuf.Ptr, "Ptr", byteBuf.Ptr, "UPtr", byteBuf.Size, "UPtr*", &outLen, "Cdecl Int")
            if (rc < 0)
                throw Error("ShmVar_GetBytes 失败，key=" key " 错误码=" rc)
            return byteBuf
        }
        return ""
    }

    Has(key) {
        kBuf := ShmVariableMap._ToUtf8(String(key))
        vType := 0
        vSize := 0
        rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetType", "Ptr", kBuf.Ptr, "Int*", &vType, "UPtr*", &vSize, "Cdecl Int")
        return rc == 0
    }

    Delete(key) {
        kBuf := ShmVariableMap._ToUtf8(String(key))
        prevVal := ""
        if (this.Has(key)) {
            try prevVal := this._Get(key)
        }
        rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_Delete", "Ptr", kBuf.Ptr, "Cdecl Int")
        if (rc < 0 && rc != -4) { ; -4 is SHMVAR_ERR_NOT_FOUND
            throw Error("ShmVar_Delete 失败，key=" key " 错误码=" rc)
        }
        return prevVal
    }

    Clear() {
        for k in this._Keys() {
            try this.Delete(k)
        }
    }

    Count {
        get => this._Keys().Length
    }

    _Keys() {
        ; 从共享内存枚举，主进程与新 Worker 都能发现其他进程创建的键。
        loop 8 {
            required := 0
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetKeys", "Ptr", 0, "UPtr", 0, "UPtr*", &required, "Cdecl Int")
            if (rc == 0 && required == 0)
                return []
            if (rc != -6)
                throw Error("ShmVar_GetKeys 失败，错误码=" rc)
            buf := Buffer(required)
            rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_GetKeys", "Ptr", buf.Ptr, "UPtr", buf.Size, "UPtr*", &required, "Cdecl Int")
            if (rc == -6)
                continue ; 查询长度后其他进程新增了键，重新取快照。
            if (rc < 0)
                throw Error("ShmVar_GetKeys 失败，错误码=" rc)
            keys := [], offset := 0
            while (offset < required) {
                key := StrGet(buf.Ptr + offset, "UTF-8")
                keys.Push(key)
                offset += StrPut(key, "UTF-8")
            }
            return keys
        }
        throw Error("共享变量持续变化，无法获取键名快照")
    }

    __Enum(numParams) {
        ; 过滤并收集当前实际存在的键值
        items := []
        for k in this._Keys() {
            if (this.Has(k)) {
                try items.Push([k, this._Get(k)])
            }
        }

        idx := 0
        total := items.Length
        return Enumerator

        Enumerator(&k, &v := unset) {
            if (++idx > total)
                return false
            k := items[idx][1]
            if (numParams > 1)
                v := items[idx][2]
            return true
        }
    }

    Close() {
        if (ShmVariableMap.H_DLL) {
            DllCall(ShmVariableMap.DLL_PATH "\ShmVar_Close", "Cdecl Int")
        }
    }
}
