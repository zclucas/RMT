#Requires AutoHotkey v2.0

; 窗口级热键管理器：替代原 WindowHotkeyManager 和全局 SoftHotKeyArr
; 键盘键（带 ownerHwnd）→ AHK 原生 Hotkey + HotIfWinActive，仅在目标窗口前台时拦截，失焦时按键透传给其他程序
; 键盘键（不带 ownerHwnd）→ Win32 RegisterHotKey，系统级拦截（供轮盘等需要全局捕获的场景）
; 鼠标键（Wheel/LButton）→ 集中注册一次，按需订阅/取消订阅

class WinHotkey {
    static _nextId := 0xA000          ; RegisterHotKey 起始 ID
    static _handlers := Map()         ; id → { key, callback }  （RegisterHotKey 用）
    static _ahkHkEntries := Map()     ; token → { key, winTitle }  （AHK 原生 Hotkey 用，窗口级）
    static _mouseHandlers := Map()    ; key → [callback1, callback2, ...]  （集中式鼠标热键）
    static _wmHooked := false

    ; ========== 键盘热键（各组件独立注册/注销）==========

    ; 注册键盘热键
    ; ownerHwnd 可选：若提供，则使用 HotIfWinActive 仅在目标窗口前台时拦截（失焦时不吞键，透传给其他程序）
    ; 不提供 ownerHwnd 时使用 Win32 RegisterHotKey（系统级拦截，供轮盘等需要全局捕获的场景）
    ; 返回已注册的 ID/Token 数组，供调用者后续 Unregister 时使用
    static Register(keys, callback, ownerHwnd := 0) {
        ids := []
        if (ownerHwnd) {
            ; 窗口级热键：HotIfWinActive 限定，避免全局吞键
            winTitle := "ahk_id " ownerHwnd
            HotIfWinActive(winTitle)
            for idx, k in keys {
                token := "ahk:" ownerHwnd ":" k
                if (WinHotkey._ahkHkEntries.Has(token)) {
                    ids.Push(token)  ; 已注册，直接返回 token
                    continue
                }
                try {
                    Hotkey(k, callback)
                    WinHotkey._ahkHkEntries[token] := { key: k, winTitle: winTitle }
                    ids.Push(token)
                }
            }
            HotIfWinActive  ; 复位上下文，避免影响后续 Hotkey 调用
        } else {
            ; 全局热键：Win32 RegisterHotKey（系统级拦截）
            hwnd := A_ScriptHwnd
            for idx, k in keys {
                vk := GetKeyVK(k)
                if (!vk)
                    continue
                id := WinHotkey._nextId++
                r := DllCall("RegisterHotKey", "Ptr", hwnd, "Int", id, "UInt", 0, "UInt", vk)
                if (r) {
                    WinHotkey._handlers[id] := { key: k, cb: callback }
                    ids.Push(id)
                }
            }
            if (WinHotkey._handlers.Count > 0 && !WinHotkey._wmHooked) {
                OnMessage(0x0312, ObjBindMethod(WinHotkey, "_OnWMHotkey"))
                WinHotkey._wmHooked := true
            }
        }
        return ids
    }

    ; 注销指定 ID/Token 的键盘热键
    static UnregisterId(id) {
        if (Type(id) == "String" && SubStr(id, 1, 4) == "ahk:") {
            ; AHK 窗口级热键注销
            if (WinHotkey._ahkHkEntries.Has(id)) {
                entry := WinHotkey._ahkHkEntries[id]
                HotIfWinActive(entry.winTitle)
                try Hotkey(entry.key, "Off")
                HotIfWinActive  ; 复位上下文
                WinHotkey._ahkHkEntries.Delete(id)
            }
        } else if (WinHotkey._handlers.Has(id)) {
            DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", id)
            WinHotkey._handlers.Delete(id)
        }
    }

    ; 批量注销键盘热键
    static UnregisterAll(ids := "") {
        if (ids != "" && ids.Length > 0)
            for id in ids
                WinHotkey.UnregisterId(id)
    }

    ; ========== 鼠标热键（集中式：全局只注册一次，组件按需订阅）==========

    ; 订阅鼠标热键（首次订阅时自动注册全局 AHK 热键）
    static SubscribeMouse(key, callback) {
        if (!WinHotkey._mouseHandlers.Has(key))
            WinHotkey._mouseHandlers[key] := []
        WinHotkey._mouseHandlers[key].Push(callback)

        ; 首次订阅时注册全局热键（~前缀：不拦截原始事件，允许透传给其他程序）
        if (WinHotkey._mouseHandlers[key].Length == 1) {
            try Hotkey("~" key, ObjBindMethod(WinHotkey, "_OnMouseKey", key), "On")
        }
    }

    ; 取消订阅鼠标热键（无订阅者时自动注销全局热键）
    static UnsubscribeMouse(key, callback) {
        if (!WinHotkey._mouseHandlers.Has(key))
            return
        arr := WinHotkey._mouseHandlers[key]
        ; 移除指定的回调
        newArr := []
        for cb in arr {
            if (cb != callback)
                newArr.Push(cb)
        }
        if (newArr.Length == 0) {
            WinHotkey._mouseHandlers.Delete(key)
            try Hotkey("~" key, "Off")
        } else {
            WinHotkey._mouseHandlers[key] := newArr
        }
    }

    ; 取消订阅所有鼠标热键（主窗口关闭时调用）
    static UnsubscribeAllMouse() {
        for key in WinHotkey._mouseHandlers {
            try Hotkey("~" key, "Off")
        }
        WinHotkey._mouseHandlers.Clear()
    }

    ; 内部：鼠标热键统一分发
    static _OnMouseKey(key, *) {
        if (!WinHotkey._mouseHandlers.Has(key))
            return
        for cb in WinHotkey._mouseHandlers[key] {
            try cb.Call(key)
        }
    }

    ; ========== WM_HOTKEY 消息处理（仅 RegisterHotKey 路径使用）==========

    static _OnWMHotkey(wParam, lParam, msg, hwnd) {
        id := wParam & 0xFFFFFFFF
        if (WinHotkey._handlers.Has(id)) {
            entry := WinHotkey._handlers[id]
            entry.cb.Call(entry.key)
        }
    }
}
