#Requires AutoHotkey v2.0

; 补齐 1.2.2 的运行参数，并按执行模式清理无关字段。
CompatEnsureRunData(Data) {
    if (Data == "" || !IsObject(Data))
        return false
    fixed := false

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

    ; 按 Mode 补齐/清理附属字段（与 RunProGui 的保存逻辑一致）
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
