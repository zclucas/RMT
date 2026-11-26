#Requires AutoHotkey v2.0

; 一轮录制固定模式与目标；仅在成功生成指令后推进时间和按键状态。
class BackgroundRecorder {
    static Active := false
    static HwndList := []
    static TargetWin := ""
    static Holds := Map()
    static MouseTypes := Map("LButton", "左键", "RButton", "右键", "MButton", "中键")

    static Prepare() {
        this.Active := false
        this.HwndList := []
        this.TargetWin := ""
        this.Holds := Map()
        if (!MainSoftData.RecordBackground)
            return
        binding := MainSoftData.RecordBackgroundWin
        if (binding == "")
            binding := "{宏设置窗口绑定}"
        editor := MainSoftData.MacroEditGui
        context := IsObject(editor) && editor.HasOwnProp("WindowBindingContext") ? editor.WindowBindingContext : ""
        resolved := ResolveEditorBindWindow(context, binding)
        this.HwndList := GetHwndList(resolved)
        if (!this.HwndList.Length)
            throw TargetError(GetLang("未找到目标窗口。"))
        this.TargetWin := binding
        this.Active := true
    }

    static Add(item, isDown, curTime, &macroStr) {
        static wheels := Map("WheelUp", [1, 0], "WheelDown", [-1, 0], "WheelLeft", [0, -1], "WheelRight", [0, 1])
        key := item["name"]
        mouse := item["type"] == "mouse"
        wheel := mouse && wheels.Has(key)
        if (!this.Active || (mouse ? !MainSoftData.RecordMouse || (!this.MouseTypes.Has(key) && !wheel)
            : item["type"] != "key" || !MainSoftData.RecordKeyboard))
            return
        if (wheel && !isDown)
            return
        if (!wheel && !isDown) {
            ; 在目标内按下、窗口外松开仍需配对，未录到按下的松开不应单独输出。
            if (!this.Holds.Has(key))
                return
            point := this.Holds[key]
            ; 鼠标释放使用原窗口的当前客户区坐标，保留拖动终点；窗口销毁时回退到按下位置。
            if (point.mouse && item.Has("x") && item.Has("y") && item["x"] != "" && item["y"] != "") {
                try {
                    WinGetClientPos(&cx, &cy, , , "ahk_id " point.hwnd)
                    point := {mouse: true, x: item["x"] - cx, y: item["y"] - cy}
                }
            }
        } else {
            if (!wheel && this.Holds.Has(key))
                return
            point := this._Point(item)
            if (!IsObject(point))
                return
            point.mouse := mouse
        }
        if (wheel) {
            point.scroll := wheels[key]
            this._Append(key, true, point, curTime, &macroStr)
            return
        }
        this._Append(key, isDown, point, curTime, &macroStr)
        if (isDown)
            this.Holds[key] := point
        else
            this.Holds.Delete(key)
    }

    static _Point(item) {
        if (!item.Has("x") || !item.Has("y") || item["x"] == "" || item["y"] == "")
            return ""
        x := item["x"], y := item["y"]
        hwnd := DllCall("User32\WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
        if (hwnd)
            hwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        for target in this.HwndList {
            if (target != hwnd)
                continue
            try {
                WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
                if (x >= cx && y >= cy && x < cx + cw && y < cy + ch)
                    return {hwnd: hwnd, x: x - cx, y: y - cy}
            }
            break
        }
        return ""
    }

    static _Append(key, isDown, point, curTime, &macroStr) {
        serial := AllocateCommandSerial(point.mouse ? "后台鼠标" : "后台按键")
        data := GetMacroCMDData(serial)
        if (point.mouse) {
            data.TargetTitle := this.TargetWin
            data.PosVarX := point.x
            data.PosVarY := point.y
            data.ClickTime := 50
            if (point.HasOwnProp("scroll")) {
                data.MouseType := "滚轮"
                data.OperateType := "点击"
                data.ScrollV := point.scroll[1]
                data.ScrollH := point.scroll[2]
            } else {
                data.MouseType := this.MouseTypes[key]
                data.OperateType := isDown ? "按下" : "松开"
            }
        } else {
            data.FrontStr := this.TargetWin
            data.KeyArr := [key == "," ? GetLang("逗号") : key]
            data.Type := isDown ? "按下" : "松开"
        }
        SaveMacroCMDData(data)
        macroStr .= GetLang("间隔") "_" Max(0, curTime - MainSoftData.RecordLastTime) "," serial ","
        MainSoftData.RecordLastTime := curTime
    }

    static ReleaseAll(&macroStr) {
        for key, point in this.Holds.Clone() {
            this._Append(key, false, point, MainSoftData.RecordLastTime, &macroStr)
            this.Holds.Delete(key)
        }
    }
}
