#Requires AutoHotkey v2.0

Compat13_UpgradeCommands(dir) {
    renames := Map()
    Compat13_UpgradeWindows(dir, renames)
    Compat13_CopyCommands(dir, renames, "WaitFile", "等待",
        Map("InputFile", "输入"), Compat13_WaitData)
    Compat13_CopyCommands(dir, renames, "JoyCheckFile", "手柄检测",
        Map("KeyCheckFile", "按键检测"), Compat13_JoyCheckData)
    migration := Compat13_InlineCommands(dir, renames)
    Compat_RewriteMacroFiles(dir, migration.Rewrite.Bind(migration), Compat13_RewriteAllBranches,
        migration.Save.Bind(migration))
    migration.Finish()
    Compat13_ClearRenameJournal(dir, ["WindowManageFile"])
}

Compat13_UpgradeWindows(dir, renames) {
    path := dir "\WindowManageFile.toml"
    if (!FileExist(path))
        return
    root := Cfg_Load(path, true).Clone()
    section := IniImport_Section()
    values := root[section] := Cfg_Seg(root, section).Clone()
    saved := root["Compat13Renames"] := Cfg_Seg(root, "Compat13Renames").Clone()
    for key, target in saved
        renames[key] := target
    dirty := false
    for key, raw in values.Clone() {
        if (!RegExMatch(key, "i)^(?:窗口管理|視窗管理|Window Management|Window)\d+$"))
            continue
        data := TryParseCommandData(raw)
        if (!IsObject(data))
            continue
        defaults := WindowManageData()
        defaults.SearchValue := ""
        if (!data.HasOwnProp("ActionType"))
            data.ActionType := defaults.ActionType
        if (data.ActionType == "移动")
            data.ActionType := "移动窗口"
        CmdEnumNorm("窗口管理", data)
        Compat13_FillDefaults(data, defaults)
        prefix := WindowInfoFields(data.ActionType).Length ? "窗口信息" : "调整窗口"
        if (!data.HasOwnProp("MatchMode") || Trim(data.MatchMode) == "")
            data.MatchMode := data.ActionType == "匹配窗口列表" ? "所有" : "首个"
        values[key] := JSON.stringify(data, 0)
        saved[key] := Compat13_Rename(values, key, prefix, renames)
        dirty := true
    }
    if (dirty)
        Cfg_WriteRoot(root, path)
}

Compat13_CopyCommands(dir, renames, targetStem, targetPrefix, sources, convert) {
    path := dir "\" targetStem ".toml"
    root := Cfg_Load(path, true).Clone()
    section := IniImport_Section()
    values := root[section] := Cfg_Seg(root, section).Clone()
    saved := root["Compat135Sources"] := Cfg_Seg(root, "Compat135Sources").Clone()
    dirty := false
    next := 1
    for stem, prefix in sources {
        for key, raw in CfgSection(dir "\" stem ".toml", IniImport_Section()) {
            if (!RegExMatch(key, "^" prefix "(\d+)$", &m))
                continue
            data := convert.Call(prefix, TryParseCommandData(raw))
            if (!IsObject(data))
                continue
            if (Compat13_IsSameTarget(values, saved.Get(key, ""), data)) {
                renames[key] := saved[key]
            } else {
                while (values.Has(targetPrefix next))
                    next += 1
                data.SerialStr := targetPrefix next++
                values[data.SerialStr] := JSON.stringify(data, 0)
                renames[key] := saved[key] := data.SerialStr
                dirty := true
            }
        }
    }
    ; 先写入资源，重试时通过迁移记录复用序列号。
    if (dirty)
        Cfg_WriteRoot(root, path)
}

Compat13_IsSameTarget(values, target, data) {
    if (!values.Has(target))
        return false
    data.SerialStr := target
    return values[target] == JSON.stringify(data, 0)
}

Compat13_JoyCheckData(prefix, data) {
    if (!IsObject(data) || !data.HasOwnProp("KeyArr") || !(data.KeyArr is Array) || !data.KeyArr.Length)
        return ""
    keys := []
    for key in data.KeyArr {
        short := Compat13_JoyShort(key)
        ; 字母键 A/B/X/Y 不能当成手柄短名。混合输入仍按原条件整体检测。
        if (short == key)
            return ""
        internal := JoyShortToInternal(short)
        if (internal == "" || InStr(internal, "JoyAxis") == 1)
            return ""
        keys.Push(internal)
    }
    data.KeyArr := keys
    Compat13_FillDefaults(data, KeyCheckData())
    CmdEnumNorm("手柄检测", data)
    return data
}

Compat13_WaitData(prefix, old) {
    if (!IsObject(old))
        return ""
    inputType := InputField(old, "Type")
    if (inputType != "继续" && inputType != "继续&取消")
        return ""
    data := WaitData(true)
    data.WaitType := "等待确定"
    data.TimeoutMs := InputField(old, "TimeoutMs", 0)
    for field, value in data.ConfirmConfig.OwnProps()
        data.ConfirmConfig.%field% := InputField(old, field, value)
    if (!old.HasOwnProp("Prompt"))
        data.ConfirmConfig.Prompt := InputField(old, "Content")
    if (inputType == "继续&取消")
        data.ConfirmConfig.TerminateType := InputField(old, "CancelType", "终止当前宏")
    if (old.HasOwnProp("AutoRemark"))
        data.AutoRemark := old.AutoRemark
    return data
}

class Compat13_InlineCommands {
    __New(dir, renames) {
        this.dir := dir
        this.renames := renames
        this.files := Map()
    }

    Rewrite(macro) {
        ; 仅处理指令首段，保留标记、备注及分隔符。
        result := ""
        start := 1
        while (pos := RegExMatch(macro, "[^,，\r\n⫶]+", &m, start)) {
            result .= SubStr(macro, start, pos - start) this.Command(m[0])
            start := pos + StrLen(m[0])
        }
        return result SubStr(macro, start)
    }

    Command(command) {
        if (!RegExMatch(command, "^([ \t]*(?:🚫|▶|⭐)*)([^_|]+?)(?=[ \t]*(?:[_|]|$))", &m))
            return command
        key := m[2]
        tail := SubStr(command, StrLen(m[0]) + 1)
        if (this.renames.Has(key))
            return m[1] this.renames[key] tail
        if (CanonicalMoveCommandName(key) == "移动") {
            ; 旧编辑器允许小数坐标，执行时取整。备注和错误策略留在命令尾部。
            if (RegExMatch(tail, "^_([^_|]+)_([^_|]+)(?:_([+-]?\d+))?(?:_(绝对移动|相对移动|游戏视角|絕對移動|相對移動|遊戲視角|Absolute Move|Relative Move|Absolute|Relative|Game View|[012]))?(?=[_| \t]|$)", &move)
                && IsNumber(move[1]) && IsNumber(move[2])) {
                mode := CmdEnumMoveMode(move[4])
                if (mode == "游戏视角") {
                    data := DeltaMoveData()
                    data.DeltaX := Integer(Number(move[1])), data.DeltaY := Integer(Number(move[2]))
                    target := this.Store("DeltaMoveFile", "增量移动", data)
                } else {
                    data := MoveDataConfig()
                    data.PosX := Integer(Number(move[1])), data.PosY := Integer(Number(move[2]))
                    data.Speed := move[3] == "" ? 90 : Integer(move[3])
                    data.MoveMode := mode
                    target := this.Store("MoveDataFile", "移动", data)
                }
                return m[1] target SubStr(tail, StrLen(move[0]) + 1)
            }
            return m[1] "移动" tail
        }
        if (key == "RMT指令" && RegExMatch(tail, "^_(图文|输入控制|宏控制|调试|软件自身)_([^_| \t]+)", &action)) {
            data := RMTCMDData()
            data.Category := action[1]
            data.CmdStr := action[2]
            suffix := SubStr(tail, StrLen(action[0]) + 1)
            if (action[2] == "显示菜单" && RegExMatch(suffix, "^_(\d+)(?=[_| \t]|$)", &menu)) {
                data.MenuIndex := Integer(menu[1])
                suffix := SubStr(suffix, StrLen(menu[0]) + 1)
            } else if (action[2] == "禁用模块" || action[2] == "取消禁用模块")
                return command
            return m[1] this.Store("RMTCMDFile", "RMT指令", data) suffix
        }
        return command
    }

    Open(stem) {
        if (!this.files.Has(stem)) {
            path := this.dir "\" stem ".toml"
            root := Cfg_Load(path, true).Clone()
            section := IniImport_Section()
            values := root[section] := Cfg_Seg(root, section).Clone()
            journal := root["CompatInlinePending"] := Cfg_Seg(root, "CompatInlinePending").Clone()
            this.files[stem] := {Path: path, Root: root, Values: values, Journal: journal, Next: 1, Dirty: false}
        }
        return this.files[stem]
    }

    Store(stem, prefix, data) {
        file := this.Open(stem)
        while (file.Values.Has(prefix file.Next))
            file.Next += 1
        data.SerialStr := prefix file.Next++
        file.Values[data.SerialStr] := JSON.stringify(data, 0)
        file.Journal[data.SerialStr] := true
        file.Dirty := true
        return data.SerialStr
    }

    Finish() {
        pending := Map()
        for stem in ["MoveDataFile", "DeltaMoveFile", "RMTCMDFile"] {
            if (!CfgHasSection(this.dir "\" stem ".toml", "CompatInlinePending"))
                continue
            file := this.Open(stem)
            for serial in file.Journal
                pending[serial] := true
        }
        if (!pending.Count)
            return
        ; 如果资源已写、宏写入失败，重试只清理从未被宏引用的暂存资源。
        Compat_RewriteMacroFiles(this.dir, this.MarkReferenced.Bind(this, pending), Compat13_RewriteAllBranches)
        for stem, file in this.files {
            if (!file.Journal.Count)
                continue
            for serial in file.Journal {
                if (pending.Has(serial) && file.Values.Has(serial))
                    file.Values.Delete(serial)
            }
            file.Root.Delete("CompatInlinePending")
            Cfg_WriteRoot(file.Root, file.Path)
        }
    }

    MarkReferenced(pending, macro) {
        for command in SplitMacro(macro) {
            if (RegExMatch(command, "^(?:🚫|▶|⭐)*([^_| 	]+)", &m) && pending.Has(m[1]))
                pending.Delete(m[1])
        }
        return macro
    }

    Save() {
        for stem, file in this.files {
            if (file.Dirty) {
                Cfg_WriteRoot(file.Root, file.Path)
                file.Dirty := false
            }
        }
    }
}
