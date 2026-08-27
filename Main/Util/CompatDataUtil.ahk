#Requires AutoHotkey v2.0

; 内存数据结构的旧版本兼容补齐，主程序与Worker都会用到，故放在共享层（AssetUtil.ahk）
; 配置文件的迁移改写逻辑见 FixCompatUtil.ahk，那些仅主程序需要，不要在此处引用

;1.0.8F4到新版本兼容, 模块中新增菜单模块相关数据
Compat1_0_8F4FlodInfo(FoldInfo) {
    if (FoldInfo == "")
        return

    if (!ObjHasOwnProp(FoldInfo, "FrontInfoArr"))
        FoldInfo.FrontInfoArr := []
    if (!ObjHasOwnProp(FoldInfo, "TKTypeArr"))
        FoldInfo.TKTypeArr := []
    if (!ObjHasOwnProp(FoldInfo, "TKArr"))
        FoldInfo.TKArr := []
    if (!ObjHasOwnProp(FoldInfo, "HoldTimeArr"))
        FoldInfo.HoldTimeArr := []
    if (!ObjHasOwnProp(FoldInfo, "UnorderedTriggerArr"))
        FoldInfo.UnorderedTriggerArr := []

    ; 属性存在但长度为 0（如 JSON 序列化了空 UnorderedTriggerArr）时也要按模块数补齐
    targetLen := 0
    if (ObjHasOwnProp(FoldInfo, "RemarkArr"))
        targetLen := FoldInfo.RemarkArr.Length
    if (ObjHasOwnProp(FoldInfo, "IndexSpanArr") && FoldInfo.IndexSpanArr.Length > targetLen)
        targetLen := FoldInfo.IndexSpanArr.Length

    loop targetLen {
        if (FoldInfo.FrontInfoArr.Length < A_Index)
            FoldInfo.FrontInfoArr.Push("")
        if (FoldInfo.TKTypeArr.Length < A_Index)
            FoldInfo.TKTypeArr.Push(1)
        if (FoldInfo.TKArr.Length < A_Index)
            FoldInfo.TKArr.Push("")
        if (FoldInfo.HoldTimeArr.Length < A_Index)
            FoldInfo.HoldTimeArr.Push(500)
        if (FoldInfo.UnorderedTriggerArr.Length < A_Index)
            FoldInfo.UnorderedTriggerArr.Push(false)
    }
}

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

    ; 7) 按 Mode 补齐/清理附属字段（与 RunGui.SaveRunData 一致）
    if (Data.Mode = 1) {
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
    } else if (Data.Mode = 2) {
        if (ObjHasOwnProp(Data, "StdIn")) {
            Data.DeleteProp("StdIn")
            fixed := true
        }
        if (!ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.SaveNameArr := [""]
            fixed := true
        } else if (Data.SaveNameArr.Length != 1) {
            Data.SaveNameArr := [Data.SaveNameArr[1]]
            fixed := true
        }
        if (ObjHasOwnProp(Data, "Encoding")) {
            Data.DeleteProp("Encoding")
            fixed := true
        }
    } else if (Data.Mode = 3) {
        if (!ObjHasOwnProp(Data, "StdIn")) {
            Data.StdIn := ""
            fixed := true
        }
        if (ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.DeleteProp("SaveNameArr")
            fixed := true
        }
    } else if (Data.Mode = 4) {
        if (!ObjHasOwnProp(Data, "StdIn")) {
            Data.StdIn := ""
            fixed := true
        }
        if (!ObjHasOwnProp(Data, "SaveNameArr")) {
            Data.SaveNameArr := ["", "StdOut", "StdErr"]
            fixed := true
        } else {
            while (Data.SaveNameArr.Length < 3) {
                Data.SaveNameArr.Push(Data.SaveNameArr.Length = 1 ? "StdOut" : "StdErr")
                fixed := true
            }
        }
    }

    return fixed
}

;旧版本兼容：确保各数组长度与ModeArr一致（新增字段补齐）
CompatEnsureArrLength(tableItem) {
    needFill := false
    if (tableItem.ModeArr.Length != tableItem.StartTipSoundArr.Length)
        needFill := true
    if (tableItem.ModeArr.Length != tableItem.EndTipSoundArr.Length)
        needFill := true
    if (tableItem.ModeArr.Length != tableItem.IcoPathArr.Length)
        needFill := true
    if (tableItem.ModeArr.Length != tableItem.UnorderedTriggerArr.Length)
        needFill := true
    if (tableItem.ModeArr.Length != tableItem.VoiceTriggerArr.Length)
        needFill := true
    if (tableItem.ModeArr.Length != tableItem.VoiceKeywordsArr.Length)
        needFill := true
    if (!needFill)
        return

    for index, value in tableItem.ModeArr {
        if (tableItem.StartTipSoundArr.Length < index)
            tableItem.StartTipSoundArr.Push(1)
        if (tableItem.EndTipSoundArr.Length < index)
            tableItem.EndTipSoundArr.Push(1)
        if (tableItem.IcoPathArr.Length < index)
            tableItem.IcoPathArr.Push("")
        if (tableItem.UnorderedTriggerArr.Length < index)
            tableItem.UnorderedTriggerArr.Push(0)
        if (tableItem.VoiceTriggerArr.Length < index)
            tableItem.VoiceTriggerArr.Push(0)
        if (tableItem.VoiceKeywordsArr.Length < index)
            tableItem.VoiceKeywordsArr.Push("")
    }
}
