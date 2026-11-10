#Requires AutoHotkey v2.0

Compat132_UpgradeProfile(dir) {
    migration := CompatFlowJumpMigration(dir)
    return Compat_RewriteMacroFiles(dir, migration.Rewrite.Bind(migration),
        Compat131_RewriteBranches, migration.Save.Bind(migration), "SubMacroFile.toml")
}

class CompatFlowJumpMigration {
    __New(dir) {
        this.path := dir "\SubMacroFile.toml"
        this.root := Cfg_Load(this.path).Clone()
        section := IniImport_Section()
        this.values := this.root[section] := Cfg_Seg(this.root, section).Clone()
        this.next := 1
        this.dirty := false
        for serial in this.values {
            if (RegExMatch(serial, "i)^(?:宏操作|Ctrl)(\d+)$", &m))
                this.next := Max(this.next, Integer(m[1]) + 1)
        }
    }

    Rewrite(macro) {
        ; 按指令边界匹配，保留分隔符、禁用标记和调试标记。
        static pattern := "(^|[,，\r\n⫶])([ \t]*(?:🚫|▶|⭐)*)(?:流程跳转|FlowJump)_([^,，\r\n⫶_]+)(?=[,，\r\n⫶]|$)"
        result := ""
        start := 1
        while (pos := RegExMatch(macro, pattern, &m, start)) {
            action := ""
            remark := ""
            switch Trim(m[3]) {
                case "循环-跳过本轮", "Loop-Continue":
                    action := "循环-跳过本轮"
                    remark := "循环-跳出本轮"
                case "循环-跳出", "Loop-Exit":
                    action := "循环-跳出"
                    remark := "循环-跳出"
                case "分支-跳出", "Branch-Exit":
                    action := "分支-跳出"
                    remark := "分支跳出"
            }
            replacement := m[0]
            if (remark != "") {
                ; 每个出现位置有独立配置，编辑一条跳转不会改动其他条目。
                serial := "宏操作" this.next++
                data := SubMacroData()
                data.SerialStr := serial
                data.MacroType := "当前宏"
                data.CallType := action
                data.MacroSerial := ""
                this.values[serial] := JSON.stringify(data, 0)
                this.dirty := true
                replacement := m[1] m[2] serial "_" remark SubStr(m[3], StrLen(RTrim(m[3], " `t")) + 1)
            }
            result .= SubStr(macro, start, pos - start) replacement
            start := pos + StrLen(m[0])
        }
        return result SubStr(macro, start)
    }

    Save() {
        ; 先写入指令配置，再改写宏引用，保证中断后可重新升级。
        if (this.dirty) {
            Cfg_WriteRoot(this.root, this.path)
            this.dirty := false
        }
    }
}
