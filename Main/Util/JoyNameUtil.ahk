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
