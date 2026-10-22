#Requires AutoHotkey v2.0

; 手柄实时检测：窗口打开时按真实手柄自动勾选按键、写入摇杆轴值（对标 KeyPickerHook）
; 纯 GUI 用途——从 Main\AssetUtil.ahk 移出，因为 AssetUtil 也被 Thread\Work.ahk 引用，
; 留在那里会让 Worker 进程编译时找不到 GI_*/RecordRealAxisValue 等录制层函数
class JoyPickerHook {
    static _busy := false
    static _snapLogLeft := 0
    static BitMap := Map(0, "上", 1, "下", 2, "左", 3, "右", 4, "Start", 5, "Back", 6, "LS", 7, "RS", 8, "LB", 9, "RB", 10, "Home", 11, "Pad", 12, "A", 13, "B", 14, "X", 15, "Y")
    static AhkBtnMap := Map(
        "Joy1", "A", "Joy2", "B", "Joy3", "X", "Joy4", "Y",
        "Joy5", "LB", "Joy6", "RB", "Joy7", "Back", "Joy8", "Start",
        "Joy9", "LS", "Joy10", "RS", "Joy13", "Home", "Joy14", "Pad")
    static AhkPovMap := Map(0, "上", 9000, "右", 18000, "下", 27000, "左")

    static Attach(host) {
        if (!IsObject(host) || (host.HasProp("_closed") && host._closed))
            return
        JoyPickerLogReset()
        JoyPickerHook._snapLogLeft := 12
        who := "JoyGui"
        try who := host.__Class
        JoyPickerLog("Attach begin host=" who)
        JoyPickerHook.Detach(host)
        epoch := host.HasProp("_joyEpoch") ? Integer(host._joyEpoch) + 1 : 1
        host._joyEpoch := epoch
        host._joyListenPrev := Map()
        host._joyUserOff := Map()
        host._joyStickOff := Map()
        host._joyPrimed := false
        host._joyBusy := false
        host._joyLogUi := false
        host._joyPendingBtns := []
        host._joyPendingStick := 0
        host._joyStickSeen := 0
        host._joyTick := ObjBindMethod(JoyPickerHook, "_Tick", host, epoch)
        host._joyFlush := ObjBindMethod(JoyPickerHook, "_Flush", host, epoch)
        try GI_EnsureWrapper()
        catch as e
            JoyPickerLog("Attach GI_EnsureWrapper FAIL " e.Message)
        try SetTimer(host._joyTick, 0)
        try SetTimer(host._joyFlush, 0)
        SetTimer(host._joyTick, 30)
        JoyPickerLog("Attach done timer=30 epoch=" epoch)
    }

    static Detach(host) {
        if (!IsObject(host))
            return
        host._joyEpoch := host.HasProp("_joyEpoch") ? Integer(host._joyEpoch) + 1 : 1
        if (host.HasProp("_joyTick") && host._joyTick != "") {
            try SetTimer(host._joyTick, 0)
            host._joyTick := ""
        }
        if (host.HasProp("_joyFlush") && host._joyFlush != "") {
            try SetTimer(host._joyFlush, 0)
            host._joyFlush := ""
        }
        host._joyListenPrev := Map()
        host._joyUserOff := Map()
        host._joyStickOff := Map()
        host._joyPrimed := false
        host._joyPendingBtns := []
        host._joyPendingStick := 0
        host._joyStickSeen := 0
        host._joyBusy := false
        host._joyLogUi := false
    }

    static _IsReady(host) {
        if (!IsObject(host) || !IsObject(host.ui) || (host.HasProp("_closed") && host._closed))
            return false
        if (host.HasProp("_stickDrag") && host._stickDrag != "") {
            if (!GetKeyState("LButton", "P")) {
                try host.OnPadMouseUp()
            }
            if (host.HasProp("_stickDrag") && host._stickDrag != "")
                return false
        }
        return true
    }

    static _HostHasBtn(host, short) {
        if (!IsObject(host) || !host.HasProp("CheckedArr"))
            return false
        for v in host.CheckedArr {
            if (v == short)
                return true
        }
        return false
    }

    static _Tick(host, epoch, *) {
        ; 只采样，不改界面。ui.Update 放 _Flush，避免轮询线程里 IPC 套叠闪退
        if (!IsObject(host) || !host.HasProp("_joyEpoch") || Integer(host._joyEpoch) != Integer(epoch))
            return
        if (host.HasProp("_joyBusy") && host._joyBusy)
            return
        if (!JoyPickerHook._IsReady(host))
            return
        snap := 0
        try snap := JoyPickerHook._Snapshot()
        catch as e {
            JoyPickerLog("Tick Snapshot EXCEPTION " e.Message " @ " e.What " L" e.Line)
            return
        }
        if (!IsObject(snap))
            return
        prev := host._joyListenPrev
        if (!IsObject(prev))
            prev := Map()
        userOff := host.HasProp("_joyUserOff") && IsObject(host._joyUserOff) ? host._joyUserOff : Map()
        btnMode := false
        try btnMode := host._LtRtAsButton()
        if (!host.HasProp("_joyPrimed") || !host._joyPrimed) {
            onList := ""
            for short, on in snap.btns {
                prev["b" short] := !!on
                if (on)
                    onList .= (onList == "" ? "" : ",") short
            }
            host._joyListenPrev := prev
            host._joyPrimed := true
            JoyPickerLog("Tick prime on=[" onList "] lx=" snap.lx " ly=" snap.ly " rx=" snap.rx " ry=" snap.ry " lt=" snap.lt " rt=" snap.rt)
            return
        }
        pending := host.HasProp("_joyPendingBtns") && IsObject(host._joyPendingBtns) ? host._joyPendingBtns : []
        for short, on in snap.btns {
            isTrig := (short == "LT" || short == "RT")
            if (isTrig && !btnMode) {
                prev["b" short] := false
                continue
            }
            was := prev.Get("b" short, false)
            if (!on && userOff.Has(short))
                userOff.Delete(short)
            if (on && !was && !userOff.Has(short)) {
                dup := false
                for s in pending {
                    if (s == short) {
                        dup := true
                        break
                    }
                }
                if (!dup)
                    pending.Push(short)
            }
            prev["b" short] := !!on
        }
        host._joyListenPrev := prev
        host._joyUserOff := userOff
        host._joyPendingBtns := pending
        stick := 0
        ls := Sqrt(snap.lx * snap.lx + snap.ly * snap.ly)
        rs := Sqrt(snap.rx * snap.rx + snap.ry * snap.ry)
        if (ls >= 20 || rs >= 20 || snap.lt >= 8 || snap.rt >= 8) {
            cand := { lx: snap.lx, ly: snap.ly, rx: snap.rx, ry: snap.ry, lt: snap.lt, rt: snap.rt, btnMode: btnMode }
            last := host.HasProp("_joyStickSeen") ? host._joyStickSeen : 0
            if (!IsObject(last) || Abs(cand.lx - last.lx) >= 2 || Abs(cand.ly - last.ly) >= 2 || Abs(cand.rx - last.rx) >= 2 || Abs(cand.ry - last.ry) >= 2 || Abs(cand.lt - last.lt) >= 2 || Abs(cand.rt - last.rt) >= 2) {
                stick := cand
                host._joyStickSeen := cand
            }
        } else
            host._joyStickSeen := 0
        host._joyPendingStick := stick
        if (pending.Length > 0 || IsObject(stick)) {
            if (pending.Length > 0) {
                pb := ""
                for s in pending
                    pb .= (pb == "" ? "" : ",") s
                JoyPickerLog("Tick queue btns=[" pb "]")
            } else
                JoyPickerLog("Tick stick ls=" stick.lx "," stick.ly " rs=" stick.rx "," stick.ry)
            if (host.HasProp("_joyFlush") && host._joyFlush != "")
                SetTimer(host._joyFlush, -1)
        }
    }

    static _Flush(host, epoch, *) {
        if (!IsObject(host) || !host.HasProp("_joyEpoch") || Integer(host._joyEpoch) != Integer(epoch))
            return
        if (!JoyPickerHook._IsReady(host))
            return
        if (host.HasProp("_joyBusy") && host._joyBusy) {
            if (host.HasProp("_closed") && host._closed)
                return
            JoyPickerLog("Flush busy, retry")
            if (host.HasProp("_joyFlush") && host._joyFlush != "")
                SetTimer(host._joyFlush, -1)
            return
        }
        host._joyBusy := true
        host._joyLogUi := true
        JoyPickerLog("Flush begin")
        try {
            btns := host.HasProp("_joyPendingBtns") ? host._joyPendingBtns : []
            stick := host.HasProp("_joyPendingStick") ? host._joyPendingStick : 0
            host._joyPendingBtns := []
            host._joyPendingStick := 0
            if (IsObject(btns)) {
                for short in btns {
                    if (!JoyPickerHook._IsReady(host) || Integer(host._joyEpoch) != Integer(epoch))
                        return
                    JoyPickerLog("Flush btn " short)
                    try host._OnLiveButton(short)
                    catch as e
                        JoyPickerLog("Flush btn FAIL " short " " e.Message " L" e.Line)
                    JoyPickerLog("Flush btn done " short)
                }
            }
            if (IsObject(stick)) {
                JoyPickerLog("Flush stick ls=" stick.lx "," stick.ly " rs=" stick.rx "," stick.ry)
                try host._ApplyLiveStick("AxisLS", "LX", "LY", stick.lx, stick.ly)
                catch as e
                    JoyPickerLog("Flush LS FAIL " e.Message " L" e.Line)
                JoyPickerLog("Flush LS done")
                try host._ApplyLiveStick("AxisRS", "RX", "RY", stick.rx, stick.ry)
                catch as e
                    JoyPickerLog("Flush RS FAIL " e.Message " L" e.Line)
                JoyPickerLog("Flush RS done")
                if (!stick.btnMode) {
                    JoyPickerLog("Flush trig lt=" stick.lt " rt=" stick.rt)
                    try host._ApplyLiveTriggersExclusive(stick.lt, stick.rt)
                    catch as e
                        JoyPickerLog("Flush trig FAIL " e.Message " L" e.Line)
                    JoyPickerLog("Flush trig done")
                }
            }
            JoyPickerLog("Flush end ok")
        } catch as e {
            JoyPickerLog("Flush EXCEPTION " e.Message " @ " e.What " L" e.Line)
        } finally {
            try host._joyLogUi := false
            try host._joyBusy := false
        }
    }

    static _Snapshot() {
        gi := 0
        nGi := 0
        try {
            if (JoyPickerHook._snapLogLeft > 0)
                JoyPickerLog("Snapshot GI begin")
            GI_EnsureWrapper()
            states := GI_CollectStates()
            if (IsObject(states)) {
                nGi := states.Length
                for s in states
                    gi := JoyPickerHook._MergeSnap(gi, JoyPickerHook._FromXi(s))
            }
            if (JoyPickerHook._snapLogLeft > 0)
                JoyPickerLog("Snapshot GI end n=" nGi " obj=" (IsObject(gi) ? 1 : 0))
        } catch as e {
            JoyPickerLog("Snapshot GI EXCEPTION " e.Message " L" e.Line)
        }
        ahk := 0
        try ahk := JoyPickerHook._FromAhk()
        catch as e
            JoyPickerLog("Snapshot AHK EXCEPTION " e.Message " L" e.Line)
        usedGi := nGi > 0 && IsObject(gi)
        if (!IsObject(gi))
            gi := ahk
        else if (IsObject(ahk)) {
            ; GI 已有设备时不要用 AHK 轴覆盖：GetKeyState JoyX=0 会被映射成 -100，
            ; 空闲左摇杆会变成 (-100,100)，每 30ms 冲刷界面导致无法微调、点击失效。
            for short, on in ahk.btns {
                if (short == "LT" || short == "RT" || short == "上" || short == "下" || short == "左" || short == "右")
                    continue
                if (on)
                    gi.btns[short] := true
            }
        }
        xi := 0
        try xi := JoyPickerHook._FromXInputEx()
        catch as e
            JoyPickerLog("Snapshot XI EXCEPTION " e.Message " L" e.Line)
        if (!IsObject(gi))
            gi := xi
        else if (IsObject(xi)) {
            for short, on in xi.btns {
                if (short == "LT" || short == "RT")
                    continue
                if (on)
                    gi.btns[short] := true
            }
            if (gi.lt < xi.lt)
                gi.lt := xi.lt
            if (gi.rt < xi.rt)
                gi.rt := xi.rt
            ; GI 摇杆为空时用 XInput 补（空闲为 0，不会像 AHK JoyX=0 那样变成 -100）
            if (Sqrt(gi.lx * gi.lx + gi.ly * gi.ly) < 15 && Sqrt(xi.lx * xi.lx + xi.ly * xi.ly) >= 20) {
                gi.lx := xi.lx
                gi.ly := xi.ly
            }
            if (Sqrt(gi.rx * gi.rx + gi.ry * gi.ry) < 15 && Sqrt(xi.rx * xi.rx + xi.ry * xi.ry) >= 20) {
                gi.rx := xi.rx
                gi.ry := xi.ry
            }
        }
        if (!IsObject(gi))
            return 0
        z := ""
        if (IsObject(ahk) && ahk.HasProp("trigAxis") && IsNumber(ahk.trigAxis))
            z := Integer(ahk.trigAxis)
        tr := JoyPickerHook._ResolveSharedTrigger(gi.lt, gi.rt, z)
        gi.lt := tr.ltVal
        gi.rt := tr.rtVal
        gi.btns["LT"] := tr.lt
        gi.btns["RT"] := tr.rt
        if (JoyPickerHook._snapLogLeft > 0) {
            onList := ""
            for short, on in gi.btns {
                if (on)
                    onList .= (onList == "" ? "" : ",") short
            }
            JoyPickerLog("Snapshot out on=[" onList "] lx=" gi.lx " ly=" gi.ly " rx=" gi.rx " ry=" gi.ry " lt=" gi.lt " rt=" gi.rt " z=" z)
            JoyPickerHook._snapLogLeft -= 1
        }
        return gi
    }

    ; LT/RT 共享一根轴（JoyZ 中位约 50）：偏高=LT，偏低=RT；独立双扳机则按较大一侧
    static _ResolveSharedTrigger(lt, rt, z := "") {
        if (!IsNumber(z)) {
            if (lt >= 25 && lt > rt)
                return { lt: true, rt: false, ltVal: Integer(lt), rtVal: 0 }
            if (rt >= 25 && rt > lt)
                return { lt: false, rt: true, ltVal: 0, rtVal: Integer(rt) }
            return { lt: false, rt: false, ltVal: 0, rtVal: 0 }
        }
        shared := Integer(z)
        if (shared < 0)
            shared := 0
        if (shared > 100)
            shared := 100
        if (shared >= 65) {
            v := Integer((shared - 50) * 2)
            if (v < 0)
                v := 0
            if (v > 100)
                v := 100
            return { lt: true, rt: false, ltVal: v, rtVal: 0 }
        }
        if (shared <= 35) {
            v := Integer((50 - shared) * 2)
            if (v < 0)
                v := 0
            if (v > 100)
                v := 100
            return { lt: false, rt: true, ltVal: 0, rtVal: v }
        }
        return { lt: false, rt: false, ltVal: 0, rtVal: 0 }
    }

    static _MergeSnap(a, b) {
        if (!IsObject(a))
            return b
        if (!IsObject(b))
            return a
        for short, on in b.btns {
            if (short == "LT" || short == "RT")
                continue
            if (on)
                a.btns[short] := true
        }
        if (Abs(b.lx) > Abs(a.lx))
            a.lx := b.lx
        if (Abs(b.ly) > Abs(a.ly))
            a.ly := b.ly
        if (Abs(b.rx) > Abs(a.rx))
            a.rx := b.rx
        if (Abs(b.ry) > Abs(a.ry))
            a.ry := b.ry
        if (b.lt > a.lt)
            a.lt := b.lt
        if (b.rt > a.rt)
            a.rt := b.rt
        if (b.HasProp("trigAxis") && IsNumber(b.trigAxis))
            a.trigAxis := b.trigAxis
        return a
    }

    static _FromXi(s) {
        btns := Map()
        for bit, short in JoyPickerHook.BitMap
            btns[short] := ((s.wButtons >> bit) & 1) != 0
        lt := RecordRealAxisValue("JoyZMin", s)
        rt := RecordRealAxisValue("JoyZMax", s)
        gi := s.HasProp("giButtons") ? Integer(s.giButtons) : 0
        btns["LT"] := false
        btns["RT"] := false
        if ((s.wButtons & 0x0400) || (gi & 0x40000000))
            btns["Home"] := true
        if ((s.wButtons & 0x0800) || (gi & 0x80000000))
            btns["Pad"] := true
        return {
            btns: btns,
            lx: RecordRealAxisValue("JoyX", s),
            ly: RecordRealAxisValue("JoyY", s),
            rx: RecordRealAxisValue("JoyU", s),
            ry: RecordRealAxisValue("JoyR", s),
            lt: lt,
            rt: rt
        }
    }

    static _AhkAxis(idx, name, invert := false) {
        try {
            raw := GetKeyState(idx name)
            if (!IsNumber(raw))
                return 0
            v := Integer((Float(raw) - 50) * 2)
            if (invert)
                v := -v
            if (v < -100)
                v := -100
            if (v > 100)
                v := 100
            return v
        }
        return 0
    }

    static _AhkTrig(idx, name) {
        try {
            raw := GetKeyState(idx name)
            if (!IsNumber(raw))
                return 0
            v := Integer(raw)
            if (v < 0)
                v := 0
            if (v > 100)
                v := 100
            return v
        }
        return 0
    }

    static _FromAhk() {
        btns := Map("A", false, "B", false, "X", false, "Y", false, "LB", false, "RB", false,
            "Back", false, "Start", false, "LS", false, "RS", false, "Home", false, "Pad", false,
            "上", false, "下", false, "左", false, "右", false, "LT", false, "RT", false)
        lx := 0, ly := 0, rx := 0, ry := 0, lt := 0, rt := 0, trigAxis := ""
        found := false
        loop 4 {
            idx := A_Index
            name := ""
            try name := GetKeyState(idx "JoyName")
            if (name == "")
                continue
            if (InStr(name, "ViGEm") || InStr(name, "vXbox") || InStr(name, "Nefarius"))
                continue
            found := true
            for ahk, short in JoyPickerHook.AhkBtnMap {
                try {
                    if (GetKeyState(idx ahk))
                        btns[short] := true
                }
            }
            try {
                if (GetKeyState(idx "Joy13"))
                    btns["Home"] := true
            }
            try {
                pov := GetKeyState(idx "JoyPOV")
                if (IsNumber(pov)) {
                    pv := Integer(pov)
                    if (pv >= 0 && pv != 65535 && JoyPickerHook.AhkPovMap.Has(pv))
                        btns[JoyPickerHook.AhkPovMap[pv]] := true
                }
            }
            info := ""
            try info := GetKeyState(idx "JoyInfo")
            vx := JoyPickerHook._AhkAxis(idx, "JoyX")
            vy := JoyPickerHook._AhkAxis(idx, "JoyY", true)
            ; 未初始化 DI 轴常为 0/100，映射后正好是对角满行程，当成无效
            if (!(Abs(vx) == 100 && Abs(vy) == 100)) {
                if (Abs(vx) > Abs(lx))
                    lx := vx
                if (Abs(vy) > Abs(ly))
                    ly := vy
            }
            if (InStr(info, "U")) {
                vr := JoyPickerHook._AhkAxis(idx, "JoyU")
                if (Abs(vr) > Abs(rx))
                    rx := vr
            }
            if (InStr(info, "R")) {
                vr := JoyPickerHook._AhkAxis(idx, "JoyR", true)
                if (Abs(vr) > Abs(ry))
                    ry := vr
            }
            if (InStr(info, "Z") && trigAxis == "")
                trigAxis := JoyPickerHook._AhkTrig(idx, "JoyZ")
        }
        if (!found)
            return 0
        return { btns: btns, lx: lx, ly: ly, rx: rx, ry: ry, lt: lt, rt: rt, trigAxis: trigAxis }
    }

    static _FromXInputEx() {
        bitMap := Map(0, "上", 1, "下", 2, "左", 3, "右", 4, "Start", 5, "Back", 6, "LS", 7, "RS", 8, "LB", 9, "RB", 10, "Home", 12, "A", 13, "B", 14, "X", 15, "Y")
        btns := Map()
        for , short in bitMap
            btns[short] := false
        btns["Pad"] := false
        btns["LT"] := false
        btns["RT"] := false
        lx := 0, ly := 0, rx := 0, ry := 0, lt := 0, rt := 0
        found := false
        loop 4 {
            st := JoyXInputEx(A_Index - 1)
            if (!IsObject(st))
                continue
            found := true
            wb := Integer(st.wButtons)
            for bit, short in bitMap {
                if ((wb >> bit) & 1)
                    btns[short] := true
            }
            ltp := Integer(Round(st.lt * 100 / 255))
            rtp := Integer(Round(st.rt * 100 / 255))
            if (ltp > lt)
                lt := ltp
            if (rtp > rt)
                rt := rtp
            if (st.HasProp("lx") && Abs(st.lx) > Abs(lx))
                lx := st.lx
            if (st.HasProp("ly") && Abs(st.ly) > Abs(ly))
                ly := st.ly
            if (st.HasProp("rx") && Abs(st.rx) > Abs(rx))
                rx := st.rx
            if (st.HasProp("ry") && Abs(st.ry) > Abs(ry))
                ry := st.ry
        }
        if (!found)
            return 0
        return { btns: btns, lx: lx, ly: ly, rx: rx, ry: ry, lt: lt, rt: rt }
    }
}
