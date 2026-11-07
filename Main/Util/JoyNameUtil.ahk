#Requires AutoHotkey v2.0
; 手柄键名映射：短名 <-> 内部名
; 主进程与 Worker 进程都要用（DataClass / RecordUtil / RMTUtil 都会调用），故放在 AssetUtil 链里

JoyShortToInternal(short) {
    static m := ""
    if (!IsObject(m)) {
        m := Map(
            "A", "JoyA", "B", "JoyB", "X", "JoyX", "Y", "JoyY",
            "LB", "JoyLB", "RB", "JoyRB", "LT", "JoyLT", "RT", "JoyRT",
            "LS", "JoyLS", "RS", "JoyRS", "Back", "JoyBack", "Start", "JoyStart",
            "Home", "JoyHome", "Pad", "JoyPad",
            "上", "JoyDpadUp", "下", "JoyDpadDown", "左", "JoyDpadLeft", "右", "JoyDpadRight",
            "无方向", "JoyDpadNone", "无", "JoyDpadNone",
            "LX", "JoyAxisLX", "LY", "JoyAxisLY", "RX", "JoyAxisRX", "RY", "JoyAxisRY")
    }
    return m.Get(short, "")
}

JoyInternalToShort(internal) {
    if (internal == "")
        return ""
    if (RegExMatch(internal, "^(JoyAxisL[XY]|JoyAxisR[XY]|JoyAxisLT|JoyAxisRT):(-?[0-9]+)$", &am))
        return SubStr(am[1], 8) ":" am[2]
    static m := ""
    if (!IsObject(m)) {
        m := Map(
            "JoyA", "A", "JoyB", "B", "JoyX", "X", "JoyY", "Y",
            "JoyLB", "LB", "JoyRB", "RB", "JoyLT", "LT", "JoyRT", "RT",
            "JoyLS", "LS", "JoyRS", "RS", "JoyBack", "Back", "JoyStart", "Start",
            "JoyHome", "Home", "JoyPad", "Pad",
            "JoyDpadUp", "上", "JoyDpadDown", "下", "JoyDpadLeft", "左", "JoyDpadRight", "右",
            "JoyDpadNone", "无方向",
            "JoyAxisLX", "LX", "JoyAxisLY", "LY", "JoyAxisRX", "RX", "JoyAxisRY", "RY",
            "JoyAxisLT", "LT", "JoyAxisRT", "RT")
    }
    return m.Get(internal, internal)
}

; 把手柄指令串（手柄_短名_点击_…）拆成内部轴/按钮/类型/附加段
; 主进程 MacroUtil.OnPressJoy 和 Worker 共用，故一并放在这里
JoyCmdToPressKeyParts(cmd) {
    paramArr := SplitCommand(cmd)
    axes := []
    buttons := []
    ktype := GetLang("点击")
    rest := []
    typeWords := Map(GetLang("按下"), true, GetLang("松开"), true, GetLang("点击"), true)
    i := 2
    while (i <= paramArr.Length) {
        p := paramArr[i]
        if (RegExMatch(p, "^(LX|LY|RX|RY|LT|RT):(-?[0-9]+)$", &m)) {
            axes.Push("JoyAxis" m[1] ":" m[2])
        } else if (typeWords.Has(p)) {
            ktype := p
            j := i + 1
            while (j <= paramArr.Length) {
                rest.Push(paramArr[j])
                j++
            }
            break
        } else {
            for short in StrSplit(StrReplace(p, "+", "⎖"), "⎖") {
                inn := JoyShortToInternal(Trim(short))
                if (inn != "")
                    buttons.Push(inn)
            }
        }
        i++
    }
    return { axes: axes, buttons: buttons, ktype: ktype, rest: rest }
}

; 非官方 XInputGetStateEx（ordinal 100）带 Guide/Home 位 0x0400；读不到则退回 XInputGetState
JoyXInputEx(index := 0) {
    static proc := 0
    if (proc == 0) {
        ; XInput 版本取决于系统/手柄驱动；xinput9_1_0 是很多 Xbox 手柄
        ; 实际可用的兼容层，不能只尝试 1_4/1_3。
        for dll in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll", "xinput1_2.dll", "xinput1_1.dll"] {
            hMod := DllCall("GetModuleHandle", "Str", dll, "Ptr")
            if (!hMod)
                hMod := DllCall("LoadLibrary", "Str", dll, "Ptr")
            if (!hMod)
                continue
            proc := DllCall("GetProcAddress", "Ptr", hMod, "AStr", "XInputGetState", "Ptr")
            if (proc)
                break
            ; 某些旧实现只导出 ordinal 100（含 Guide 位的扩展接口）。
            proc := DllCall("GetProcAddress", "Ptr", hMod, "Ptr", 100, "Ptr")
            if (proc)
                break
        }
        if (!proc)
            proc := -1
    }
    if (proc == -1)
        return 0
    buf := Buffer(16, 0)
    if (DllCall(proc, "UInt", index, "Ptr", buf.Ptr) != 0)
        return 0
    lx := Integer(Round(NumGet(buf, 8, "Short") * 100 / 32768))
    ly := Integer(Round(NumGet(buf, 10, "Short") * 100 / 32768))
    rx := Integer(Round(NumGet(buf, 12, "Short") * 100 / 32768))
    ry := Integer(Round(NumGet(buf, 14, "Short") * 100 / 32768))
    clamp(v) => (v < -100 ? -100 : (v > 100 ? 100 : v))
    return {
        wButtons: NumGet(buf, 4, "UShort"),
        lt: NumGet(buf, 6, "UChar"),
        rt: NumGet(buf, 7, "UChar"),
        lx: clamp(lx),
        ly: clamp(ly),
        rx: clamp(rx),
        ry: clamp(ry)
    }
}
