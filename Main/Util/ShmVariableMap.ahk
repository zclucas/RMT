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
        this._localKeys := Map() ; 辅助本地跟踪键名以支持 __Enum 与 Count
        ShmVariableMap._EnsureDll()

        nameBuf := Buffer(StrPut(mapName, "UTF-8"))
        StrPut(mapName, nameBuf, "UTF-8")
        rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_Init", "Ptr", nameBuf.Ptr, "UPtr", initialSize, "Cdecl Int")
        if (rc < 0) {
            throw Error("ShmVar_Init 失败，错误码: " rc)
        }
    }

    static _EnsureDll() {
        if (ShmVariableMap.H_DLL)
            return true

        ; 多候選路徑依序嘗試，相容開發/生產/Worker 各種啟動目錄
        ; A_ScriptDir  : 主腳本目錄（RMT.ahk → 專案根；Work.ahk → Thread/；Work.exe → ReleaseX64/Thread/）
        ; A_WorkingDir : 程式工作目錄（通常與 A_ScriptDir 相同，或是 AHK 安裝目錄）
        candidates := [
            A_ScriptDir "\Plugins\ShmVar\ShmVar.dll",           ; 主進程（專案根 / 編譯exe同級）
            A_ScriptDir "\..\Plugins\ShmVar\ShmVar.dll",        ; Worker 開發（Thread\..\Plugins\）
            A_ScriptDir "\..\..\Plugins\ShmVar\ShmVar.dll",     ; Worker 生產（ReleaseX64\Thread\..\..\）
            A_WorkingDir "\Plugins\ShmVar\ShmVar.dll",          ; 工作目錄備援
            A_WorkingDir "\..\Plugins\ShmVar\ShmVar.dll"        ; 工作目錄向上一層備援
        ]

        dllPath := ""
        for p in candidates {
            if FileExist(p) {
                dllPath := p
                break
            }
        }

        if (dllPath == "") {
            throw Error("未找到 ShmVar.dll，尝试路径: " candidates[1] " / " candidates[2])
        }

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
        this._localKeys[String(key)] := true
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
        if (rc == 0) {
            this._localKeys[String(key)] := true
            return true
        }
        if (this._localKeys.Has(String(key)))
            this._localKeys.Delete(String(key))
        return false
    }

    Delete(key) {
        kBuf := ShmVariableMap._ToUtf8(String(key))
        prevVal := ""
        if (this.Has(key)) {
            try prevVal := this._Get(key)
        }
        rc := DllCall(ShmVariableMap.DLL_PATH "\ShmVar_Delete", "Ptr", kBuf.Ptr, "Cdecl Int")
        if (this._localKeys.Has(String(key)))
            this._localKeys.Delete(String(key))
        if (rc < 0 && rc != -4) { ; -4 is SHMVAR_ERR_NOT_FOUND
            throw Error("ShmVar_Delete 失败，key=" key " 错误码=" rc)
        }
        return prevVal
    }

    Clear() {
        for k in [this._localKeys*] {
            try this.Delete(k)
        }
        this._localKeys.Clear()
    }

    Count {
        get {
            cnt := 0
            stale := []
            for k in this._localKeys {
                if (this.Has(k))
                    cnt++
                else
                    stale.Push(k)
            }
            for k in stale
                this._localKeys.Delete(k)
            return cnt
        }
    }

    __Enum(numParams) {
        ; 过滤并收集当前实际存在的键值
        items := []
        stale := []
        for k in this._localKeys {
            if (this.Has(k)) {
                try items.Push([k, this._Get(k)])
            } else {
                stale.Push(k)
            }
        }
        for k in stale
            this._localKeys.Delete(k)

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
