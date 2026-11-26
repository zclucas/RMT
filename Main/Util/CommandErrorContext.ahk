#Requires AutoHotkey v2.0

; 主进程、Worker 共用。正常执行不序列化数据，只在报错时生成快照。
class CommandErrorContext {
    static Frames := []
    static Editor := ""

    static Location(table, index) {
        category := "宏"
        for def in MacroCategoryDefs()
            if (def[1] == table.Symbol)
                category := def[2]
        item := table.Items[index]
        module := 0, ordinal := 0
        for n, fold in table.Folds
            if (fold.ID == item.FoldID) {
                module := n
                break
            }
        for n, candidate in table.Items {
            if (candidate.FoldID == item.FoldID)
                ordinal += 1
            if (n == index)
                break
        }
        return module ? category "-模块" module "-宏" ordinal : "单条指令测试"
    }

    static Describe(cmd, location, mode := "runtime", data := unset) {
        details := cmd
        try {
            if (!IsSet(data))
                data := GetMacroCMDData(StrSplit(cmd, "_")[1])
            details .= "`n" JSON.stringify(data)
        } catch as err {
            details .= "`n指令数据读取失败：" err.Message
        }
        return {mode: mode, location: location, command: details}
    }

    static Current(stack := "") {
        if (stack == "")
            stack := Error().Stack
        ; 新的 UI/定时器线程不能误用被中断宏的上下文。
        if (!this.Frames.Length || !InStr(stack, "[ExecuteMacroCmdOnce]")) {
            if (IsObject(this.Editor) && InStr(stack, "_RunDiagnosticCallback"))
                return this.Editor.Call()
            return ""
        }
        frame := this.Frames[this.Frames.Length]
        location := "单条指令测试"
        try location := this.Location(frame.table, frame.index)
        context := this.Describe(frame.cmd, location)
        if (IsObject(this.Editor) && InStr(stack, "_RunDiagnosticCallback") && InStr(stack, "OnTriggerSepcialItemMacro")) {
            context.mode := "editor"
            try context.location := this.Editor.Call().location
        }
        return context
    }
}
