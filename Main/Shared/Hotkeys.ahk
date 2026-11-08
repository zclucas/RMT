; 按键选择器：物理按键名 → 键盘网格 value（与 KeyGui ConMap 一致）
NormalizeKeyPickerName(name) {
    static alias := Map(
        "LControl", "LCtrl", "RControl", "RCtrl", "Control", "Ctrl",
        "Backspace", "BS", "Escape", "Esc",
        "Insert", "Ins", "Delete", "Del",
        "PageUp", "PgUp", "PageDown", "PgDn",
        ",", "逗号", "Apps", "AppsKey")
    if (name == "")
        return ""
    if (alias.Has(name))
        return alias[name]
    if (StrLen(name) == 1) {
        c := Ord(name)
        if (c >= 65 && c <= 90)
            return Chr(c + 32)
    }
    return name
}

; 按键/后台按键/按键检测：窗口打开时按物理键自动勾选对应按钮
class KeyPickerHook {
    static MouseKeys := ["WheelUp", "WheelDown", "WheelLeft", "WheelRight", "XButton1", "XButton2"]

    static Attach(host, skipF1 := false) {
        KeyPickerHook.Detach(host)
        host._kpSkipF1 := skipF1
        host._kpEditableFocus := false
        host._kpHookDown := Map()
        ih := InputHook("V")
        ih.KeyOpt("{All}", "N")
        ih.OnKeyDown := (ihObj, vk, sc) => KeyPickerHook._OnDown(host, vk, sc)
        ih.OnKeyUp := (ihObj, vk, sc) => KeyPickerHook._OnUp(host, vk)
        host._kpIh := ih
        ih.Start()
        host._kpMouseAction := (thisHotkey) => KeyPickerHook._OnMouseHotkey(host, thisHotkey)
        for hk in KeyPickerHook.MouseKeys {
            try Hotkey("~" hk, host._kpMouseAction, "On")
        }
        ; 空格只在选键窗激活且未在输入时拦截，避免全局/输入框空格失效
        host._kpSpaceHotIf := (*) => KeyPickerHook._IsHostReady(host)
        host._kpSpaceAction := (*) => KeyPickerHook._OnSpace(host)
        try {
            HotIf(host._kpSpaceHotIf)
            Hotkey("Space", host._kpSpaceAction, "On")
            HotIf()
        }
        ; 焦点状态由引擎统一判断后上报（哪个控件能输入归渲染引擎管），
        ; 这里只接收结果，不再逐个控件挂 GotFocus。
        host.ui.OnEvent("Window", "FocusEditable", (state, *) => KeyPickerHook._OnFocusEditable(host, state))
    }

    static _OnFocusEditable(host, state) {
        ; 拿不到值就保持原状态：宁可少选一个键，也不要把「正在输入」判成「没在输入」
        if (!IsObject(state) || !state.Has("FocusEditable"))
            return
        host._kpEditableFocus := (state["FocusEditable"] == "1")
    }

    static Detach(host) {
        if (!IsObject(host))
            return
        if (host.HasProp("_kpIh") && IsObject(host._kpIh)) {
            try host._kpIh.Stop()
            host._kpIh := ""
        }
        if (host.HasProp("_kpMouseAction") && host._kpMouseAction != "") {
            for hk in KeyPickerHook.MouseKeys {
                try Hotkey("~" hk, host._kpMouseAction, "Off")
            }
            host._kpMouseAction := ""
        }
        if (host.HasProp("_kpSpaceHotIf") && host._kpSpaceHotIf != "") {
            try {
                HotIf(host._kpSpaceHotIf)
                Hotkey("Space", "Off")
                HotIf()
            }
            host._kpSpaceHotIf := ""
            host._kpSpaceAction := ""
        }
        host._kpHookDown := Map()
        host._kpEditableFocus := false
    }

    static _IsHostReady(host) {
        if (!IsObject(host) || !IsObject(host.ui) || (host.HasProp("_closed") && host._closed))
            return false
        if (host.HasProp("_kpEditableFocus") && host._kpEditableFocus)
            return false
        hwnd := 0
        try hwnd := host.Hwnd()
        return hwnd && WinActive("ahk_id " hwnd)
    }

    static _OnDown(host, vk, sc) {
        try {
            if (!KeyPickerHook._IsHostReady(host))
                return
            if (!host.HasProp("_kpHookDown") || !IsObject(host._kpHookDown))
                return
            if (host._kpHookDown.Has(vk))
                return
            host._kpHookDown[vk] := true
            key := NormalizeKeyPickerName(GetKeyName(Format("vk{:x}sc{:x}", vk, sc)))
            if (key == "" || key == "Space" || key == "LButton" || key == "MButton" || key == "RButton")
                return
            if (host._kpSkipF1 && key == "F1")
                return
            if (host.ConMap.Has(key))
                host.OnCheckedKey(key)
        }
    }

    static _OnUp(host, vk) {
        try {
            if (!IsObject(host) || !host.HasProp("_kpHookDown") || !IsObject(host._kpHookDown))
                return
            if (host._kpHookDown.Has(vk))
                host._kpHookDown.Delete(vk)
        }
    }

    static _OnSpace(host) {
        try {
            if (!KeyPickerHook._IsHostReady(host))
                return
            if (host.ConMap.Has("Space"))
                host.OnCheckedKey("Space")
        }
    }

    static _OnMouseHotkey(host, thisHotkey := "") {
        try {
            if (!KeyPickerHook._IsHostReady(host))
                return
            hk := thisHotkey != "" ? thisHotkey : A_ThisHotkey
            hk := StrReplace(hk, "~", "")
            if (hk == "" || hk == "LButton" || hk == "MButton" || hk == "RButton")
                return
            if (!host.ConMap.Has(hk))
                return
            now := A_TickCount
            if (host.HasProp("_kpMouseTick") && host._kpMouseTick.Has(hk) && now - host._kpMouseTick[hk] < 180)
                return
            if (!host.HasProp("_kpMouseTick") || !IsObject(host._kpMouseTick))
                host._kpMouseTick := Map()
            host._kpMouseTick[hk] := now
            if (hk == "WheelUp" || hk == "WheelDown") {
                KeyPickerHook._SetPicked(host, hk, true)
                KeyPickerHook._SetPicked(host, hk == "WheelUp" ? "WheelDown" : "WheelUp", false)
                return
            }
            host.OnCheckedKey(hk)
        }
    }

    static _IsPicked(host, key) {
        for , value in host.CheckedArr {
            if (value == key)
                return true
        }
        return false
    }

    static _SetPicked(host, key, selected) {
        if (!host.ConMap.Has(key) || KeyPickerHook._IsPicked(host, key) == selected)
            return
        host.OnCheckedKey(key)
    }
}

CheckIsNormalHotKey(key) {
    if (SubStr(key, 1, 1) == ":")
        return false

    if (InStr(key, "Joy"))
        return false

    if (InStr(key, "XButton"))
        return false

    if (InStr(key, "Wheel"))
        return false

    if (InStr(key, "Button"))
        return false

    if (MySoftData.SpecialKeyMap.Has(key))
        return false

    return true
}

GetHotKeyCtrlType(key) {
    isHotKey := CheckIsNormalHotKey(key)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    return CtrlType
}

; AHK 热键符号转可读显示：!p → Alt+P，^+a → Ctrl+Shift+A
FormatHotkeyDisplay(key) {
    key := Trim(String(key))
    if (key == "")
        return ""
    ; 字串触发等非标准热键原样显示
    if (SubStr(key, 1, 1) == ":")
        return key
    if (InStr(key, " & ")) {
        parts := StrSplit(key, " & ")
        out := ""
        for idx, part in parts {
            if (idx > 1)
                out .= " + "
            out .= FormatHotkeyDisplay(Trim(part))
        }
        return out
    }

    rest := key
    mods := []
    ; 左右修饰键需优先于单字符前缀匹配
    prefixes := [
        {p: "<^", n: "LCtrl"}, {p: ">^", n: "RCtrl"}, {p: "^", n: "Ctrl"},
        {p: "<!", n: "LAlt"}, {p: ">!", n: "RAlt"}, {p: "!", n: "Alt"},
        {p: "<+", n: "LShift"}, {p: ">+", n: "RShift"}, {p: "+", n: "Shift"},
        {p: "<#", n: "LWin"}, {p: ">#", n: "RWin"}, {p: "#", n: "Win"}
    ]
    loop {
        matched := false
        for item in prefixes {
            plen := StrLen(item.p)
            if (SubStr(rest, 1, plen) == item.p) {
                mods.Push(item.n)
                rest := SubStr(rest, plen + 1)
                matched := true
                break
            }
        }
        if (!matched)
            break
    }

    if (SubStr(rest, 1, 1) == "~")
        rest := SubStr(rest, 2)
    if (SubStr(rest, 1, 1) == "*")
        rest := SubStr(rest, 2)

    mainKey := rest
    if (mainKey != "")
        mainKey := StrUpper(SubStr(mainKey, 1, 1)) SubStr(mainKey, 2)

    result := ""
    for modName in mods {
        if (result != "")
            result .= "+"
        result .= modName
    }
    if (mainKey != "") {
        if (result != "")
            result .= "+"
        result .= mainKey
    }
    return result
}

CheckIfHasModifyKey(keyCombo) {
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]
    for prefix in modPrefixes {
        if (SubStr(keyCombo, 1, StrLen(prefix)) == prefix) {
            return true
        }
    }
    return false
}

IsComboKey(keyCombo) {
    return InStr(keyCombo, " & ")
}

; 是否为修饰键名（含左右侧）
IsModifierKeyName(keyName) {
    static ModMap := Map(
        "Ctrl", 1, "LCtrl", 1, "RCtrl", 1, "Control", 1, "LControl", 1, "RControl", 1,
        "Alt", 1, "LAlt", 1, "RAlt", 1,
        "Shift", 1, "LShift", 1, "RShift", 1,
        "Win", 1, "LWin", 1, "RWin", 1)
    return ModMap.Has(keyName)
}

; 模拟松开指定按键
ReleaseKeyByName(key) {
    if (key == "" || key == "None")
        return
    ; 泛化 Ctrl/Alt/Shift/Win：映射到左右键，但只松开实际按下的一侧
    ; 注意：不可对未按下的 RAlt 发 KEYUP——RAlt(AltGr) 在许多布局下等价于 Ctrl+Alt，会冒出幽灵 Ctrl
    keys := []
    switch key {
        case "Ctrl", "Control":
            keys := ["LCtrl", "RCtrl"]
        case "LControl":
            keys := ["LCtrl"]
        case "RControl":
            keys := ["RCtrl"]
        case "Alt":
            keys := ["LAlt", "RAlt"]
        case "Shift":
            keys := ["LShift", "RShift"]
        case "Win":
            keys := ["LWin", "RWin"]
        default:
            keys := [key]
    }
    for k in keys {
        if (!GetKeyState(k, "P"))
            continue
        try {
            VK := GetKeyVK(k)
            SC := GetKeySC(k)
            flags := 0x2  ; KEYEVENTF_KEYUP
            if (k == "RAlt" || k == "RCtrl")
                flags |= 0x1  ; KEYEVENTF_EXTENDEDKEY
            DllCall("keybd_event", "UChar", VK, "UChar", SC, "UInt", flags, "UPtr", 0)
        }
    }
}

; 触发宏前松开组合键中的修饰键（支持 ^a 与 Ctrl & A 两种格式）
LoosenModifyKey(keyCombo) {
    keyCombo := Trim(String(keyCombo))
    keyCombo := LTrim(keyCombo, "~")
    if (keyCombo == "")
        return

    ; 新格式：Ctrl & A / LShift & F1
    if (InStr(keyCombo, " & ")) {
        for part in StrSplit(keyCombo, " & ") {
            name := LTrim(Trim(part), "~")
            if (IsModifierKeyName(name))
                ReleaseKeyByName(name)
        }
        return
    }

    ; 旧格式：^a / <+!b
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]
    loop {
        hasAdd := false
        for prefix in modPrefixes {
            if (SubStr(keyCombo, 1, StrLen(prefix)) == prefix) {
                modifiers.Push(prefix)
                keyCombo := SubStr(keyCombo, StrLen(prefix) + 1)
                hasAdd := true
                break
            }
        }
        if (!hasAdd)
            break
    }

    for mod in modifiers {
        key := ""
        switch mod {
            case "^": key := "Ctrl"
            case "<^": key := "LCtrl"
            case ">^": key := "RCtrl"
            case "!": key := "Alt"
            case "<!": key := "LAlt"
            case ">!": key := "RAlt"
            case "+": key := "Shift"
            case "<+": key := "LShift"
            case ">+": key := "RShift"
            case "#": key := "Win"
            case "<#": key := "LWin"
            case ">#": key := "RWin"
        }
        if (key != "")
            ReleaseKeyByName(key)
    }
}

; 去掉热键前缀符号，取出真正的键名：^a → a、<^a → a、~*$b → b。
; 组合键（^q & w）拆开后每段可能带修饰符前缀，直接喂 GetKeyState 会抛「Parameter #1 is invalid」。
StripHotkeyPrefix(keyName) {
    k := Trim(String(keyName))
    static prefixes := ["<^", ">^", "^", "<!", ">!", "!", "<+", ">+", "+", "<#", ">#", "#", "~", "*", "$"]
    loop {
        matched := false
        for p in prefixes {
            if (SubStr(k, 1, StrLen(p)) == p) {
                k := SubStr(k, StrLen(p) + 1)
                matched := true
                break
            }
        }
        if (!matched)
            break
    }
    return Trim(k)
}

; 检查单个物理键是否按下（含手柄键）
IsPhysicalKeyPressed(mainKey) {
    mainKey := StripHotkeyPrefix(mainKey)
    if (mainKey == "")
        return true

    ; 手柄键：RMT 用友好名（JoyA/JoyBack…），必须先映射成 AHK 名（1Joy1…），
    ; 否则 GetKeyState("1JoyA") 同样非法。
    isJoyKey := RegExMatch(mainKey, "Joy")
    if (isJoyKey) {
        if (IsObject(MySoftData) && MySoftData.HasProp("GetJoyToAhkMap")) {
            try {
                joyMap := MySoftData.GetJoyToAhkMap()
                if (joyMap.Has(mainKey))
                    mainKey := joyMap[mainKey]
            }
        }
        isJoyAxis := RegExMatch(mainKey, "Min") || RegExMatch(mainKey, "Max")
        joyName := isJoyAxis ? SubStr(mainKey, 1, 4) : mainKey
        loop 4 {
            try {
                if (GetKeyState(A_Index joyName))
                    return true
            }
        }
        return false
    }

    ; 非法键名（未收录的键/显示名）按「未按下」处理：宁可放开重复触发，也不能把触发键锁死
    try
        return !!GetKeyState(mainKey, "P")
    catch
        return false
}

AreKeysPressed(keyCombo) {
    keyCombo := LTrim(Trim(String(keyCombo)), "~")
    if (keyCombo == "")
        return false

    ; 新格式：Ctrl & A（每段可能带 ^ ! + # 前缀，如 ^q & w）
    if (InStr(keyCombo, " & ")) {
        for part in StrSplit(keyCombo, " & ") {
            part := StripHotkeyPrefix(part)
            if (part == "")
                continue
            if (!IsPhysicalKeyPressed(part))
                return false
        }
        return true
    }

    ; 旧格式：^a / <+!b
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]
    loop {
        hasAdd := false
        for prefix in modPrefixes {
            if (SubStr(keyCombo, 1, StrLen(prefix)) == prefix) {
                modifiers.Push(prefix)
                keyCombo := SubStr(keyCombo, StrLen(prefix) + 1)
                hasAdd := true
                break
            }
        }
        if (!hasAdd)
            break
    }

    mainKey := keyCombo
    for mod in modifiers {
        switch mod {
            case "^": if (!GetKeyState("Ctrl"))
                return false
            case "<^": if !GetKeyState("LCtrl")
                return false
            case ">^": if !GetKeyState("RCtrl")
                return false
            case "!": if !(GetKeyState("Alt"))
                return false
            case "<!": if !GetKeyState("LAlt")
                return false
            case ">!": if !GetKeyState("RAlt")
                return false
            case "+": if !(GetKeyState("Shift"))
                return false
            case "<+": if !GetKeyState("LShift")
                return false
            case ">+": if !GetKeyState("RShift")
                return false
            case "#": if (!GetKeyState("LWin") && !GetKeyState("RWin"))
                return false
            case "<#": if !GetKeyState("LWin")
                return false
            case ">#": if !GetKeyState("RWin")
                return false
            default: return false
        }
    }

    if (mainKey == "")
        return true
    return IsPhysicalKeyPressed(mainKey)
}

GetRecordTriggerKeyMap() {
    triggerKey := MainSoftData.ToolRecordMacroHotKey
    ; 初始化存储修饰键的数组
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]

    ; 检查是否以修饰键开头
    loop {
        hasAdd := false
        for prefix in modPrefixes {
            if (SubStr(triggerKey, 1, StrLen(prefix)) == prefix) {
                modifiers.Push(prefix)
                triggerKey := SubStr(triggerKey, StrLen(prefix) + 1)
                hasAdd := true
                break
            }
        }
        if (!hasAdd)
            break
    }

    ; 剩余部分是主键
    resultMap := Map()
    if (triggerKey != "")
        resultMap.Set(triggerKey, 0)

    for index, value in modifiers {
        if (value == "^" || value == "<^" || value == ">^") {
            resultMap.Set("Ctrl", 0)
            resultMap.Set("LCtrl", 0)
            resultMap.Set("RCtrl", 0)
        }

        if (value == "!" || value == "<!" || value == ">!") {
            resultMap.Set("Alt", 0)
            resultMap.Set("LAlt", 0)
            resultMap.Set("RAlt", 0)
        }

        if (value == "+" || value == "<+" || value == ">+") {
            resultMap.Set("Shift", 0)
            resultMap.Set("LShift", 0)
            resultMap.Set("RShift", 0)
        }

        if (value == "#" || value == "<#" || value == ">#") {
            resultMap.Set("Win", 0)
            resultMap.Set("LWin", 0)
            resultMap.Set("RWin", 0)
        }
    }

    return resultMap
}
