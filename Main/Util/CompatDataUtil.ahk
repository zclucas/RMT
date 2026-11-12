#Requires AutoHotkey v2.0

;「运行」指令字段兼容，对齐到 1.2 RunData：{SerialStr, Target, Mode, Option}
; 版本演变：
;   1.1.2: {SerialStr, RunPath, BackPlay}          — 仅 Run(路径)，BackPlay 仅用于 mp3 后台播放
;   中间版: RunPath→Target, RunMode→Mode, SaveName→SaveNameArr, 曾有 Hide
;   1.2:   {SerialStr, Target, Mode, Option} + Mode 相关可选字段(SaveNameArr/StdIn/Encoding)
CompatEnsureRunData(Data) {
    if (Data == "" || !IsObject(Data))
        return false
    fixed := false

    ; 1) 路径：RunPath → Target
    if (ObjHasOwnProp(Data, "RunPath")) {
        if (!ObjHasOwnProp(Data, "Target") || Data.Target == "")
            Data.Target := Data.RunPath
        Data.DeleteProp("RunPath")
        fixed := true
    }

    ; 2) 模式：RunMode → Mode（旧 RunMode=3 等待+管道 ≡ 新 Mode=4；新 Mode=3 为异步管道）
    if (ObjHasOwnProp(Data, "RunMode")) {
        if (!ObjHasOwnProp(Data, "Mode"))
            Data.Mode := (Data.RunMode = 3) ? 4 : Data.RunMode
        Data.DeleteProp("RunMode")
        fixed := true
    }

    ; 3) 窗口选项：Hide → Option（0=后台, 1=默认, 2=最小化, 3=最大化）
    if (ObjHasOwnProp(Data, "Hide")) {
        if (!ObjHasOwnProp(Data, "Option"))
            Data.Option := Data.Hide ? 0 : 1
        Data.DeleteProp("Hide")
        fixed := true
    }

    ; 4) 废弃：BackPlay（1.1.2 mp3 后台播放勾选，1.2 已移除，无对应字段）
    if (ObjHasOwnProp(Data, "BackPlay")) {
        Data.DeleteProp("BackPlay")
        fixed := true
    }

    ; 5) 变量名：SaveName → SaveNameArr
    if (ObjHasOwnProp(Data, "SaveName")) {
        if (!ObjHasOwnProp(Data, "SaveNameArr"))
            Data.SaveNameArr := [Data.SaveName, "StdOut", "StdErr"]
        Data.DeleteProp("SaveName")
        fixed := true
    }

    ; 6) 必填字段缺省（对齐 RunData / 1.1.2 语义：不等待 + 默认窗口）
    if (!ObjHasOwnProp(Data, "Target")) {
        Data.Target := ""
        fixed := true
    }
    if (!ObjHasOwnProp(Data, "Mode")) {
        Data.Mode := 1
        fixed := true
    }
    if (!ObjHasOwnProp(Data, "Option")) {
        Data.Option := 1
        fixed := true
    }

    ; 7) 按 Mode 补齐/清理附属字段（与 RunProGui 的保存逻辑一致）
    mode := CmdEnumZh(Data.Mode, CmdEnumRunModeNames())
    if (mode == "不等待") {
        if (ObjHasOwnProp(Data, "StdIn")) {
            Data.DeleteProp("StdIn")
            fixed := true
        }
        if (ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.DeleteProp("SaveNameArr")
            fixed := true
        }
        if (ObjHasOwnProp(Data, "Encoding")) {
            Data.DeleteProp("Encoding")
            fixed := true
        }
    } else if (mode == "等待+返回值") {
        if (ObjHasOwnProp(Data, "StdIn")) {
            Data.DeleteProp("StdIn")
            fixed := true
        }
        if (!ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.SaveNameArr := [""]
            fixed := true
        } else if (Data.SaveNameArr.Length != 1) {
            Data.SaveNameArr := [Data.SaveNameArr.Length ? Data.SaveNameArr[1] : ""]
            fixed := true
        }
        if (ObjHasOwnProp(Data, "Encoding")) {
            Data.DeleteProp("Encoding")
            fixed := true
        }
    } else if (mode == "不等待+输入") {
        if (!ObjHasOwnProp(Data, "StdIn")) {
            Data.StdIn := ""
            fixed := true
        }
        if (ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.DeleteProp("SaveNameArr")
            fixed := true
        }
    } else if (mode == "等待+输入输出") {
        if (!ObjHasOwnProp(Data, "StdIn")) {
            Data.StdIn := ""
            fixed := true
        }
        if (!ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.SaveNameArr := ["", "StdOut", "StdErr"]
            fixed := true
        } else {
            while (Data.SaveNameArr.Length < 3) {
                Data.SaveNameArr.Push(["", "StdOut", "StdErr"][Data.SaveNameArr.Length + 1])
                fixed := true
            }
        }
    }
    if (mode == "不等待+输入" || mode == "等待+输入输出") {
        if (!Data.HasOwnProp("Encoding") || !IsObject(Data.Encoding)) {
            Data.Encoding := {}
            fixed := true
        }
        for field in (mode == "不等待+输入" ? ["In"] : ["In", "Out", "Err"]) {
            if (!Data.Encoding.HasOwnProp(field)) {
                Data.Encoding.%field% := "UTF-8"
                fixed := true
            }
        }
    }

    return fixed
}

; 时间指令：SubMode 数字/英文 → 中文；去掉已废弃字段（星期、字体、透明度）
CompatEnsureTimeData(Data) {
    if (Data == "" || !IsObject(Data))
        return false
    fixed := false
    sm := TimeNormSubMode(Data)
    if (!ObjHasOwnProp(Data, "SubMode") || String(Data.SubMode) != sm) {
        Data.SubMode := sm
        fixed := true
    }
    if (sm == "区间判断" && ObjHasOwnProp(Data, "Param4") && Data.Param4 != "") {
        nw := TimeNormMismatch(Data.Param4)
        if (Data.Param4 != nw) {
            Data.Param4 := nw
            fixed := true
        }
    }
    for k in ["FontSize", "Alpha", "Param3"] {
        if (ObjHasOwnProp(Data, k)) {
            Data.DeleteProp(k)
            fixed := true
        }
    }
    return fixed
}

; 倒计时：去掉已迁到设置的字体/透明度；补齐坐标与不等待
CompatEnsureCountDownData(Data) {
    if (Data == "" || !IsObject(Data))
        return false
    fixed := false
    if (!ObjHasOwnProp(Data, "WaitEnd") || Data.WaitEnd == "") {
        Data.WaitEnd := "不等待"
        fixed := true
    }
    if (!ObjHasOwnProp(Data, "PosX") || Data.PosX == "") {
        Data.PosX := 200
        fixed := true
    }
    if (!ObjHasOwnProp(Data, "PosY") || Data.PosY == "") {
        Data.PosY := 200
        fixed := true
    }
    for k in ["FontSize", "Alpha"] {
        if (ObjHasOwnProp(Data, k)) {
            Data.DeleteProp(k)
            fixed := true
        }
    }
    return fixed
}

; 输出：补齐悬浮显示相关字段。旧版配置 JSON 缺少这些键，直接读取会抛属性不存在。
CompatEnsureOutputData(Data) {
    if (Data == "" || !IsObject(Data))
        return false
    fixed := false
    defaults := Map(
        "HudPos", "窗口右上", "HudX", 0, "HudY", 0,
        "HudFontSize", 22, "HudAlpha", 240,
        "HudColor", "FFFFFF", "HudBgColor", "202020"
    )
    for name, def in defaults {
        if (!ObjHasOwnProp(Data, name)) {
            Data.%name% := def
            fixed := true
        }
    }
    return fixed
}

;旧版本兼容：条目对象化后，确保每个 MacroItem 的运行时状态字段已初始化（迁移期）
CompatEnsureArrLength(tableItem) {
    static CtlKeys := Map(
        "宏循环次数", 0,
        "循环-跳过本轮", false,
        "循环-跳出", false,
        "分支-跳出", false
    )
    for item in tableItem.Items {
        if (!item.HoldKey)
            item.HoldKey := Map()
        ; 空 Map() 是真值，需按缺失键补齐，不能只判 !item.VariableMap
        if (!ObjHasOwnProp(item, "VariableMap"))   ;属性未创建
            item.VariableMap := Map()
        for key, def in CtlKeys {
            if (!item.VariableMap.Has(key))
                item.VariableMap[key] := def
        }
    }
}

CompatNormalizeTimingData(data) {
    if (data.HasOwnProp("StampUnit") && data.StampUnit == "ms")
        return false
    ; 1.1 用 StartTime 保存日期，定时类型编号与 1.2 的 StartStamp 格式不同。
    if (data.HasOwnProp("StartTime") && data.HasOwnProp("Type") && IsInteger(data.Type)) {
        switch Integer(data.Type) {
            case 2, 3, 4, 5:
                units := ["小时", "天", "周", "月"]
                data.CustomUnit := units[Integer(data.Type) - 1]
                data.CustomInterval := 1
                data.Type := "周期触发"
            case 6:
                data.Type := "软件启动时"
            case 7:
                data.Type := "周期触发"
        }
    }
    for part in ["Start", "End"] {
        stamp := part "Stamp"
        time := part "Time"
        if (data.HasOwnProp(stamp) && IsNumber(data.%stamp%))
            data.%stamp% *= 1000
        else if (data.HasOwnProp(time) && data.%time% != "")
            data.%stamp% := TimeStrToStamp(data.%time%)
    }
    data.StampUnit := "ms"
    return true
}
