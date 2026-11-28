#Requires AutoHotkey v2.0
#Include ProcessInfoUtil.ahk

class ProcessManageData {
    SerialStr := ""
    Action := "检测进程"
    MatchBy := "进程名"
    Target := ""
    PickMatch := "首个"
    EndAll := false
    ResultVar := ""
    CountVar := ""
    NameVar := ""
    PidVar := ""
    PathVar := ""
    ExistVar := ""
    StatusVar := ""
    StartTimeVar := ""
    UptimeVar := ""
    CpuVar := ""
    GpuVar := ""
    ResultArray := ""
}

class ProcessManage {
    static Actions := ["检测进程", "列出进程", "进程信息", "结束进程"]
    static MatchModes := ["窗口绑定", "进程名", "完整路径匹配", "PID", "正则匹配"]
    static MatchPicks := ["首个", "最后"]

    static ActionKey(action) => CurrentCommandChoice(action, this.Actions)

    static OutputFields(action) {
        switch this.ActionKey(action) {
            case "进程信息": return ["CountVar", "NameVar", "PidVar", "PathVar", "ExistVar", ProcessInfo.Metrics*]
            case "列出进程": return []
            default: return ["ResultVar"]
        }
    }

    static RegisterOutputs(data) {
        for field in this.OutputFields(data.Action) {
            if (data.HasProp(field) && data.%field% != "")
                MySoftData.GlobalVariMap[data.%field%] := true
        }
        if (data.Action == "列出进程" && data.ResultArray != "")
            MySoftData.GlobalArrMap[data.ResultArray] := true
    }

    static ValidateTarget(data, target, editing := false) {
        if (target == "") {
            if (data.MatchBy == "窗口绑定") {
                if (!editing && data.Target != "")
                    return
                throw ValueError(GetLang("窗口绑定不能为空"))
            }
            if (data.Action == "列出进程" && data.MatchBy == "进程名" && Trim(data.Target) == "")
                return
            if (data.MatchBy == "正则匹配")
                throw ValueError(GetLang("正则表达式不能为空"))
            if (data.MatchBy == "完整路径匹配")
                throw ValueError(GetLang("请输入程序完整路径。"))
            throw ValueError(GetLang("请输入进程名或 PID。"))
        }
        if (data.MatchBy == "正则匹配") {
            if (target == data.Target && this.RegexVariable(target)) {
                if (editing)
                    return
                throw ValueError(GetLang("当前环境不存在变量") " " SubStr(target, 2, -1))
            }
            RegExMatch("", target)
            return
        }
        if (editing && RegExMatch(target, "\{[^{}]+\}"))
            return
        if (data.MatchBy == "完整路径匹配" && !RegExMatch(this.NormalizePath(target), "i)^(?:[a-z]:\\|\\\\[^\\]+\\[^\\]+\\)"))
            throw ValueError(GetLang("请输入程序完整路径。"))
        if (data.MatchBy == "PID" && (!RegExMatch(target, "^\d+$") || !IsInteger(target)
            || Integer(target) < 1 || Integer(target) > 0xffffffff))
            throw ValueError(GetLang("PID 必须是有效的正整数。"))
    }

    static RegexVariable(target) => RegExMatch(target, "^\{[^\d{},][^{}]*\}$")

    static ResolveTarget(data, resolve, resolveBinding := unset) {
        if (data.MatchBy == "窗口绑定") {
            binding := resolveBinding.Call(data.Target)
            return IsMouseWindowBinding(binding) ? binding : Trim(resolve.Call(binding))
        }
        ; 正则以整项变量引用读取，保留表达式本身的量词和 Unicode 属性。
        if (data.MatchBy == "正则匹配" && !this.RegexVariable(data.Target))
            return data.Target
        return Trim(resolve.Call(data.Target))
    }

    static Execute(data, target, preview := false) {
        result := {ResultVar: 0, CountVar: 0, NameVar: "", PidVar: "", PathVar: "", ExistVar: 0,
            ResultArray: [], EndedCount: 0, ErrorVar: ""}
        for field in ProcessInfo.Metrics
            result.%field% := ""
        try {
            this.ValidateTarget(data, target)
            if (data.MatchBy == "PID")
                target := Integer(target)
            snapshotTime := 0
            DllCall("GetSystemTimeAsFileTime", "Int64*", &snapshotTime)
            matches := data.MatchBy == "窗口绑定" ? this.FindBoundProcesses(target) : this.Find(data.MatchBy, target)
            switch this.ActionKey(data.Action) {
                case "检测进程":
                    result.ResultVar := matches.Length > 0 ? 1 : 0
                case "进程信息":
                    result.CountVar := matches.Length
                    result.ExistVar := matches.Length ? 1 : 0
                    if (matches.Length) {
                        process := this.PickProcess(matches, data.MatchBy, data.PickMatch == "最后")
                        result.NameVar := process.Name
                        result.PidVar := process.Pid
                        result.PathVar := this.Path(process.Pid)
                        ProcessInfo.ReadMetrics(data, process, snapshotTime, result, preview)
                    }
                case "列出进程":
                    for process in matches
                        result.ResultArray.Push(process.Pid)
                case "结束进程":
                    if (matches.Length > 1 && !data.EndAll)
                        throw Error(GetLang("匹配到多个进程，请指定 PID。"))
                    for process in matches {
                        try {
                            this.End(process.Pid, snapshotTime)
                            result.EndedCount += 1
                        } catch as e {
                            result.ErrorVar .= (result.ErrorVar == "" ? "" : "`n") "PID " process.Pid " · " e.Message
                        }
                    }
                    result.ResultVar := result.EndedCount > 0 && result.ErrorVar == "" ? 1 : 0
            }
        } catch as e {
            result.ErrorVar := e.Message
        }
        return result
    }

    static FindBoundProcesses(binding) {
        matches := [], seen := Map()
        for hwnd in GetHwndList(binding) {
            try {
                pid := WinGetPID(hwnd)
                if (!seen.Has(pid)) {
                    name := WinGetProcessName(hwnd)
                    matches.Push({Name: name, Pid: pid, Hwnd: hwnd})
                    seen[pid] := true
                }
            }
        }
        return matches
    }

    static PickProcess(matches, matchBy, pickLast) {
        if (matchBy == "窗口绑定")
            return matches[pickLast ? -1 : 1]
        picked := matches[1]
        for process in matches {
            if (pickLast ? process.Pid > picked.Pid : process.Pid < picked.Pid)
                picked := process
        }
        return picked
    }

    static Find(matchBy, target) {
        matches := []
        if (matchBy == "完整路径匹配") {
            target := this.NormalizePath(target)
            SplitPath(target, &targetName)
        }
        snapshot := DllCall("CreateToolhelp32Snapshot", "UInt", 0x2, "UInt", 0, "Ptr")
        if (snapshot == -1)
            throw OSError()
        try {
            ; PROCESSENTRY32W 的指针字段影响后续字段的对齐。
            entry := Buffer(A_PtrSize == 8 ? 568 : 556, 0)
            nameOffset := A_PtrSize == 8 ? 44 : 36
            NumPut("UInt", entry.Size, entry)
            api := "Process32FirstW"
            while DllCall(api, "Ptr", snapshot, "Ptr", entry, "Int") {
                api := "Process32NextW"
                pid := NumGet(entry, 8, "UInt")
                if (!pid)
                    continue
                name := StrGet(entry.Ptr + nameOffset, "UTF-16")
                switch matchBy {
                    case "PID": matched := pid == target
                    case "完整路径匹配": matched := name = targetName && this.Path(pid) = target
                    case "正则匹配": matched := RegExMatch(name, target)
                    default: matched := target == "" || name = target
                }
                if (matched)
                    matches.Push({Name: name, Pid: pid})
            }
            if (A_LastError != 18) ; ERROR_NO_MORE_FILES
                throw OSError()
        } finally DllCall("CloseHandle", "Ptr", snapshot)
        return matches
    }

    static NormalizePath(path) => StrReplace(Trim(path, " `t`r`n" Chr(34)), "/", "\")

    static Path(pid) {
        try return ProcessGetPath(pid)
        return ""
    }

    static End(pid, snapshotTime) {
        handle := DllCall("OpenProcess", "UInt", 0x1001, "Int", false, "UInt", pid, "Ptr")
        if (!handle)
            throw OSError()
        try {
            created := 0, exited := 0, kernel := 0, user := 0
            if (!DllCall("GetProcessTimes", "Ptr", handle, "Int64*", &created, "Int64*", &exited,
                "Int64*", &kernel, "Int64*", &user, "Int"))
                throw OSError()
            ; 持有同一个句柄，且跳过快照后复用 PID 的进程。
            if (created > snapshotTime)
                throw Error(GetLang("进程已变化，请重新检测。"))
            if (!DllCall("TerminateProcess", "Ptr", handle, "UInt", 1, "Int"))
                throw OSError()
        } finally DllCall("CloseHandle", "Ptr", handle)
    }
}

OnProcessManage(tableItem, cmd, index) {
    data := GetMacroCMDData(SplitCommand(cmd)[1])
    target := ProcessManage.ResolveTarget(data, (text) => GetReplaceVarText(tableItem, index, text),
        (binding) => ResolveBindWindow(tableItem, index, binding))
    result := ProcessManage.Execute(data, target)
    if (data.Action == "列出进程" && data.ResultArray != "")
        MySetGlobalArray(data.ResultArray, result.ResultArray)
    names := [], values := []
    fields := ProcessManage.OutputFields(data.Action)
    for field in fields {
        if (!data.HasProp(field) || data.%field% == "")
            continue
        names.Push(data.%field%)
        values.Push(result.%field%)
    }
    if (names.Length)
        MySetGlobalVariable(names, values, false)
    if (result.ErrorVar != "")
        throw Error(result.ErrorVar)
}
