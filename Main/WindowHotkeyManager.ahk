#Requires AutoHotkey v2.0

/**
 * 窗口热键管理器
 * 为特定窗口实例注册专属热键，窗口激活时拦截处理，失活时Send转发
 */
class WindowHotkeyManager {
    static KeyHandlers := Map()

    /**
     * 注册窗口实例的热键
     * @param instance 窗口实例（需有 Gui 属性或 GetWinHwnd 方法）
     * @param hotkeys 热键数组，如 ["f5", "f6"]
     * @param callback 回调函数 callback(key, isDown)
     */
    static Register(instance, hotkeys, callback) {
        for key in hotkeys {
            key := StrLower(key)
            if (!WindowHotkeyManager.KeyHandlers.Has(key))
                WindowHotkeyManager.KeyHandlers[key] := []
            WindowHotkeyManager.KeyHandlers[key].Push({
                instance: instance,
                callback: callback
            })
        }
    }

    /**
     * 注销窗口实例的所有热键
     */
    static Unregister(instance) {
        for key, handlers in WindowHotkeyManager.KeyHandlers {
            i := handlers.Length
            while (i > 0) {
                if (handlers[i].instance == instance)
                    handlers.RemoveAt(i)
                i--
            }
            if (handlers.Length == 0)
                WindowHotkeyManager.KeyHandlers.Delete(key)
        }
    }

    /**
     * 检查某个键是否被管理器管理
     */
    static IsManaged(key) {
        return WindowHotkeyManager.KeyHandlers.Has(StrLower(key))
    }

    /**
     * 将按键分发给激活窗口的回调，返回是否被处理
     */
    static HandleKey(key, isDown) {
        key := StrLower(key)
        handlers := WindowHotkeyManager.KeyHandlers[key]
        if (!handlers)
            return false
        for h in handlers {
            hwnd := WindowHotkeyManager.GetInstanceHwnd(h.instance)
            if (hwnd && WinActive("ahk_id " hwnd)) {
                h.callback.Call(key, isDown)
                return true
            }
        }
        return false
    }

    /**
     * 检查某个键是否有激活的窗口
     */
    static IsAnyWindowActive(key) {
        key := StrLower(key)
        handlers := WindowHotkeyManager.KeyHandlers[key]
        if (!handlers)
            return false
        for h in handlers {
            hwnd := WindowHotkeyManager.GetInstanceHwnd(h.instance)
            if (hwnd && WinActive("ahk_id " hwnd))
                return true
        }
        return false
    }

    /**
     * 获取实例的窗口句柄
     * 优先使用 Gui.Hwnd，其次调用 GetWinHwnd()
     */
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
