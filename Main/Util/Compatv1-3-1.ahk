#Requires AutoHotkey v2.0

Compat131_UpgradeProfile(dir) {
    migration := CompatPromptMigration(dir)
    return Compat_RewriteMacroFiles(dir, migration.Rewrite.Bind(migration),
        Compat131_RewriteBranches, migration.Save.Bind(migration), "PromptFile.toml")
}

Compat131_RewriteBranches(data, rewrite) {
    return Compat_RewriteMacroFields(data, rewrite,
        ["CurCMD", "LoopBody", "TrueMacro", "FalseMacro", "DefaultMacro", "SubMacro"],
        ["MacroArr", "TrueMacroArr", "FalseMacroArr", "StartMacroArr", "EndMacroArr"])
}

class CompatPromptMigration {
    static Prefixes := Map("输出", "输出", "Output", "输出", "Out", "输出",
        "RMT指令", "RMT指令", "RMT Inst", "RMT指令", "RMTCMD", "RMT指令",
        "倒计时", "倒计时", "CountDown", "倒计时", "Countdown", "倒计时",
        "时间", "时间", "Time", "时间")

    __New(dir) {
        this.path := dir "\PromptFile.toml"
        this.root := Cfg_Load(this.path)
        section := IniImport_Section()
        this.values := Cfg_Seg(this.root, section)
        ; 目标先落盘，再改写引用。中途失败时可复用原目标序列号。
        this.targets := Cfg_Seg(this.root, "PromptMigration")
        this.sources := Map()
        this.next := 1
        this.dirty := false
        for file in ["OutputFile", "RMTCMDFile", "CountDownFile", "TimeDataFile", "TimeFile"] {
            for serial, value in CfgSection(dir "\" file ".toml", section) {
                if (!RegExMatch(serial, "^(.+?)(\d+)$", &m) || !CompatPromptMigration.Prefixes.Has(m[1]))
                    continue
                canonical := CompatPromptMigration.Prefixes[m[1]] m[2]
                if (!this.sources.Has(canonical) || (file != "TimeFile" && serial == canonical))
                    this.sources[canonical] := value
            }
        }
    }

    Rewrite(macro) {
        ; ⫶ 也是宏分隔符，先识别完整的旧内联自由贴。
        static pattern := "(?:[ \t]*(?:🚫|▶|⭐)*(?:RMT指令|RMT Inst|RMTCMD)⫶[^,，\r\n⫶]+⫶(?:自由贴|Free Paste)(?=[ \t]*(?:[,，\r\n⫶]|$)))|[^,，\r\n⫶]+"
        result := ""
        start := 1
        while (pos := RegExMatch(macro, pattern, &m, start)) {
            result .= SubStr(macro, start, pos - start) this.Command(m[0])
            start := pos + StrLen(m[0])
        }
        return result SubStr(macro, start)
    }

    Command(command) {
        static markers := "^([ \t]*(?:🚫|▶|⭐)*)"
        if (RegExMatch(command, markers "WaitConfirm(\d+)(?=$|[_| \t])", &m))
            return m[1] "等待确定" m[2] SubStr(command, StrLen(m[0]) + 1)
        if (RegExMatch(command, markers "(?:RMT指令|RMT Inst|RMTCMD)([_⫶])[^_⫶]+\2(?:自由贴|Free Paste)(?=$|[_| \t])", &m)) {
            target := this.Target("RMT指令_自由贴", "RMT指令", {CmdStr: "自由贴"})
            return m[1] target SubStr(command, StrLen(m[0]) + 1)
        }
        if (!RegExMatch(command, markers "([^_⫶|]+?)(\d+)(?=$|[_| \t])", &m)
            || !CompatPromptMigration.Prefixes.Has(m[2]))
            return command
        key := CompatPromptMigration.Prefixes[m[2]]
        source := key m[3]
        target := this.Target(source, key)
        if (target == "" && key == "时间" && this.sources.Has(source))
            target := source
        return target == "" ? command : m[1] target SubStr(command, StrLen(m[0]) + 1)
    }

    Target(source, key, data := "") {
        if (this.targets.Has(source) && this.values.Has(this.targets[source]))
            return this.targets[source]
        if (!IsObject(data)) {
            raw := this.sources.Get(source, "")
            if (Type(raw) != "String")
                return ""
            data := TryParseCommandData(raw)
            if (!IsObject(data))
                return ""
        }
        prompt := PromptFromLegacy(key, data)
        if (!IsObject(prompt))
            return ""
        while (this.values.Has("提示" this.next) || this.values.Has("Prompt" this.next))
            this.next += 1
        serial := "提示" this.next++
        prompt.SerialStr := serial
        this.values[serial] := JSON.stringify(prompt, 0)
        this.targets[source] := serial
        this.dirty := true
        return serial
    }

    Save() {
        if (this.dirty) {
            Cfg_WriteRoot(this.root, this.path)
            this.dirty := false
        }
    }
}

PromptFromLegacy(key, old) {
    data := PromptData()
    switch key {
        case "输出":
            switch old.HasOwnProp("OutputType") ? String(old.OutputType) : "" {
                case "软件弹窗", "Popup", "5":
                    data.Type := "软件弹窗"
                case "临时提示", "Temp Prompt", "3":
                    data.Type := "临时提示"
                case "系统语音", "Speech", "6":
                    data.Type := "音频"
                    data.AudioMode := "系统语音"
                default:
                    return ""
            }
            data.Text := old.HasOwnProp("Text") ? old.Text : ""
        case "RMT指令":
            action := old.HasOwnProp("CmdStr") ? old.CmdStr : ""
            if (action != "自由贴" && action != "Free Paste"
                && !(action == "" && old.HasOwnProp("OperateType") && old.OperateType == 3))
                return ""
            data.Type := "自由贴"
            data.PasteTextSource := "剪贴板图文"
        case "时间", "倒计时":
            if (key == "时间" && TimeNormSubMode(old) != "倒计时")
                return ""
            data.Type := "倒计时"
            for field in ["Param1", "PosX", "PosY", "WaitEnd"] {
                if (old.HasOwnProp(field) && old.%field% != "")
                    data.%field% := old.%field%
            }
            data.Seconds := old.HasOwnProp("Seconds") ? old.Seconds : 0
            data.Sec := 0
            for field in ["Hour", "Min", "Sec"] {
                if (old.HasOwnProp(field))
                    data.%field% := old.%field%
            }
            if (data.WaitEnd == "No Wait")
                data.WaitEnd := "不等待"
            else if (data.WaitEnd == "Wait Until End")
                data.WaitEnd := "等待结束"
            data.Param2 := CountDownKind(old)
            if (data.Param2 == "时长" && IsNumber(data.Hour) && IsNumber(data.Min)
                && IsNumber(data.Sec) && data.Hour * 3600 + data.Min * 60 + data.Sec <= 0) {
                if (IsInteger(data.Seconds) && data.Seconds > 0) {
                    data.Hour := data.Seconds // 3600
                    data.Min := Mod(data.Seconds // 60, 60)
                    data.Sec := Mod(data.Seconds, 60)
                } else if (!IsNumber(data.Seconds) && data.Seconds != "") {
                    data.Hour := 0
                    data.Min := 0
                    data.Sec := data.Seconds
                }
            }
            if (data.Param2 == "时刻" && data.Param1 == "")
                data.Param1 := data.Hour ":" data.Min ":" data.Sec
    }
    return data
}
