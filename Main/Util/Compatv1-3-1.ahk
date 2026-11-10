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
        return target == "" ? command : m[1] target SubStr(command, StrLen(m[0]) + 1)
    }

    Target(source, key, data := "") {
        if (this.targets.Has(source) && this.values.Has(this.targets[source]))
            return this.targets[source]
        if (!IsObject(data)) {
            raw := this.sources.Get(source, "")
            if (Type(raw) != "String")
                return ""
            data := CompatParseData(raw)
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
