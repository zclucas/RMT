#Requires AutoHotkey v2.0

class ProcessManageData {
    SerialStr := ""
    Action := "检测进程"
    MatchBy := "进程名"
    Target := ""
    EndAll := false
    ResultVar := ""
    CountVar := ""
    NameVar := ""
    PidVar := ""
    PathVar := ""
    ResultArray := ""
    ErrorVar := ""
}

class ProcessManage {
    static Actions := ["检测进程", "获取进程信息", "列出进程", "结束进程"]
    static MatchModes := ["进程名", "PID"]

    static OutputFields(action) {
        switch action {
            case "获取进程信息": return ["CountVar", "NameVar", "PidVar", "PathVar"]
            case "列出进程": return []
            default: return ["ResultVar"]
        }
    }

    static RegisterOutputs(data) {
        for field in this.OutputFields(data.Action) {
            if (data.%field% != "")
                MySoftData.GlobalVariMap[data.%field%] := true
        }
        if (data.ErrorVar != "")
            MySoftData.GlobalVariMap[data.ErrorVar] := true
        if (data.Action == "列出进程" && data.ResultArray != "")
            MySoftData.GlobalArrMap[data.ResultArray] := true
    }

    static ValidateTarget(data, target, editing := false) {
        if (target == "") {
            if (data.Action == "列出进程" && data.MatchBy == "进程名" && Trim(data.Target) == "")
                return
            throw ValueError(GetLang("请输入进程名或 PID。"))
        }
        if (editing && RegExMatch(target, "\{[^{}]+\}"))
            return
        if (data.MatchBy == "PID" && (!RegExMatch(target, "^\d+$") || !IsInteger(target)
            || Integer(target) < 1 || Integer(target) > 0xffffffff))
            throw ValueError(GetLang("PID 必须是有效的正整数。"))
    }

    static Execute(data, target) {
        result := {ResultVar: 0, CountVar: 0, NameVar: "", PidVar: "", PathVar: "", ResultArray: [], ErrorVar: ""}
        try {
            this.ValidateTarget(data, target)
            if (data.MatchBy == "PID")
                target := Integer(target)
            snapshotTime := 0
            DllCall("GetSystemTimeAsFileTime", "Int64*", &snapshotTime)
            matches := this.Find(data.MatchBy, target)
            switch data.Action {
                case "检测进程":
                    result.ResultVar := matches.Length > 0 ? 1 : 0
                case "获取进程信息":
                    result.CountVar := matches.Length
                    if (matches.Length == 1) {
                        process := matches[1]
                        result.NameVar := process.Name
                        result.PidVar := process.Pid
                        result.PathVar := this.Path(process.Pid)
                    }
                case "列出进程":
                    for process in matches
                        result.ResultArray.Push([process.Name, process.Pid, this.Path(process.Pid)])
                case "结束进程":
                    if (matches.Length > 1 && !data.EndAll)
                        throw Error(GetLang("匹配到多个进程，请指定 PID 或勾选结束全部匹配项。"))
                    for process in matches {
                        try {
                            this.End(process.Pid, snapshotTime)
                            result.ResultVar += 1
                        } catch as e {
                            result.ErrorVar .= (result.ErrorVar == "" ? "" : "`n") "PID " process.Pid " · " e.Message
                        }
                    }
            }
        } catch as e {
            result.ErrorVar := e.Message
        }
        return result
    }

    static Find(matchBy, target) {
        matches := []
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
                if (matchBy == "PID" ? pid == target : target == "" || name = target)
                    matches.Push({Name: name, Pid: pid})
            }
            if (A_LastError != 18) ; ERROR_NO_MORE_FILES
                throw OSError()
        } finally DllCall("CloseHandle", "Ptr", snapshot)
        return matches
    }

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
    target := Trim(GetReplaceVarText(tableItem, index, data.Target))
    result := ProcessManage.Execute(data, target)
    if (data.Action == "列出进程" && data.ResultArray != "")
        MySetGlobalArray(data.ResultArray, result.ResultArray)
    names := [], values := []
    fields := ProcessManage.OutputFields(data.Action)
    fields.Push("ErrorVar")
    for field in fields {
        if (data.%field% == "")
            continue
        names.Push(data.%field%)
        values.Push(result.%field%)
    }
    if (names.Length)
        MySetGlobalVariable(names, values, false)
    if (result.ErrorVar != "" && data.ErrorVar == "")
        throw Error(result.ErrorVar)
}
