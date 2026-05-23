#Requires AutoHotkey v2.0

class WindowHotkeyManager {
    static KeyHandlers := Map()

    static Register(instance, hotkeys, callback, aliveCheck := "") {
        for key in hotkeys {
            key := StrLower(key)
            isFirst := !WindowHotkeyManager.KeyHandlers.Has(key)
            if (isFirst)
                WindowHotkeyManager.KeyHandlers[key] := []
            duplicate := false
            for h in WindowHotkeyManager.KeyHandlers[key] {
                if (h.instance == instance) {
                    h.callback := callback
                    h.aliveCheck := aliveCheck
                    duplicate := true
                    break
                }
            }
            if (!duplicate)
                WindowHotkeyManager.KeyHandlers[key].Push({
                    instance: instance,
                    callback: callback,
                    aliveCheck: aliveCheck
                })
        }
    }

    static Unregister(instance) {
        keysToClean := []
        for key, handlers in WindowHotkeyManager.KeyHandlers {
            i := handlers.Length
            while (i > 0) {
                if (handlers[i].instance == instance)
                    handlers.RemoveAt(i)
                i--
            }
            if (handlers.Length == 0)
                keysToClean.Push(key)
        }
        for k in keysToClean
            WindowHotkeyManager.KeyHandlers.Delete(k)
    }

    static IsManaged(key) {
        return WindowHotkeyManager.KeyHandlers.Has(StrLower(key))
    }

    static HandleKey(key, isDown) {
        key := StrLower(key)
        WindowHotkeyManager._CleanupDead(key)
        if (!WindowHotkeyManager.KeyHandlers.Has(key))
            return false
        handlers := WindowHotkeyManager.KeyHandlers[key]
        for h in handlers {
            if (WindowHotkeyManager._IsActive(h)) {
                h.callback.Call(key, isDown)
                return true
            }
        }
        return false
    }

    static IsAnyWindowActive(key) {
        key := StrLower(key)
        WindowHotkeyManager._CleanupDead(key)
        if (!WindowHotkeyManager.KeyHandlers.Has(key))
            return false
        handlers := WindowHotkeyManager.KeyHandlers[key]
        for h in handlers {
            if (WindowHotkeyManager._IsActive(h))
                return true
        }
        return false
    }

    static _IsActive(h) {
        if (h.aliveCheck != "" && IsObject(h.aliveCheck)) {
            try
                return h.aliveCheck.Call()
            catch
                return false
        }
        hwnd := WindowHotkeyManager.GetInstanceHwnd(h.instance)
        return !!(hwnd && WinActive("ahk_id " hwnd))
    }

    static _CleanupDead(key) {
        if (!WindowHotkeyManager.KeyHandlers.Has(key))
            return
        handlers := WindowHotkeyManager.KeyHandlers[key]
        i := handlers.Length
        while (i > 0) {
            h := handlers[i]
            isAlive := true
            hwnd := WindowHotkeyManager.GetInstanceHwnd(h.instance)
            if (hwnd) {
                if (!WinExist("ahk_id " hwnd))
                    isAlive := false
            } else {
                if (h.aliveCheck != "" && IsObject(h.aliveCheck)) {
                    try
                        isAlive := h.aliveCheck.Call()
                    catch
                        isAlive := false
                } else {
                    isAlive := false
                }
            }
            if (!isAlive)
                handlers.RemoveAt(i)
            i--
        }
        if (handlers.Length == 0)
            WindowHotkeyManager.KeyHandlers.Delete(key)
    }

    static GetInstanceHwnd(instance) {
        try {
            if (IsObject(instance.Gui))
                return instance.Gui.Hwnd
        }
        try {
            return instance.GetWinHwnd()
        }
        return 0
    }
}
