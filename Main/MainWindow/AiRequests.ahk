
    _AiSendTabInput(t) {
        text := ""
        try text := this.ui.Query("AiInput_" t)
        text := Trim(this._AiNormalizeNewlines(text, false), "`n")
        if (text == "" && this._AiAttachList(t).Length < 1)
            return
        if (this._AiAnyBusy()) {
            Toast.Info(GetLang("正在等待上一条回复…"))
            return
        }
        AiAssist.EnsureDefaults()
        if (!AiAssist.IsConfigured()) {
            Toast.Warning(GetLang("请先在设置中填写 API Key、API URL 与模型"))
            AiSettingGui.ShowGui()
            return
        }
        this._aiBusy[t] := true
        if (!IsObject(this._aiCancel))
            this._aiCancel := Map()
        this._aiCancel[t] := false
        if (!IsObject(this._aiEmptyRetry))
            this._aiEmptyRetry := Map()
        this._aiEmptyRetry[t] := false
        this._aiChatTab := t
        ; 发起请求时锁定目标宏和配置，工具轮次不会跟随用户后来切换的选中项。
        this._aiRequestMacro := this._ResolveSideTreeItem(t)
        this._aiRequestConfig := MySoftData.CurSettingName
        if (!IsObject(this._aiToolRound))
            this._aiToolRound := Map()
        this._aiToolRound[t] := 0
        this._AiClearToolNotes(t)
        this._AiSetSendMode(t, true)
        this._AiShowThinking(t, false, GetLang("正在分析你的问题"))
        try this.ui.Update("AiInput_" t, "Text", "")
        try {
            attTxt := this._AiConsumeAttachText(t)
            if (attTxt != "")
                text := Trim(text attTxt)
            this._FitAiInput(t)
            try this._AiAppendMsg(t, true, text)
            catch
                this._AiAppendMsg(t, true, this._AiPlainAttachLabel(text))
            try this._AiHistPush(t, "user", text)
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
            return
        }
        SetTimer(this.aiStartTick, -30)
    }

    _AiStartChat(*) {
        t := this._aiChatTab
        if (t < 1 || !this._AiIsBusy(t) || this._AiCancelRequested(t))
            return
        try {
            msgs := this._AiBuildApiMessages(t)
            AiAssist.BeginChat(msgs)
            SetTimer(this.aiChatTick, 200)
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
        }
    }

    _AiPlainAttachLabel(text) {
        t := Trim(RegExReplace(String(text), "\[([^\]]+)\]\(rmtfile:[^)]+\)", "$1"))
        return (t != "") ? t : GetLang("附件")
    }

    _AiErrText(e) {
        errMsg := IsObject(e) && e.HasProp("Message") ? e.Message : String(e)
        detail := errMsg
        if (IsObject(e) && e.HasProp("File") && e.File != "")
            detail .= "`n" e.File (e.HasProp("Line") ? ":" e.Line : "")
        try RMTLogSys(RMT_LV_WARN, "AI", detail)
        errMsg := RegExReplace(errMsg, "i)^\s*\(0x[0-9a-f]+\)\s*")
        return Trim(RegExReplace(errMsg, "i)\s*Source:\s*RMT\s*$"))
    }

    _AiPollChat() {
        t := this._aiChatTab
        if (t < 1) {
            SetTimer(this.aiChatTick, 0)
            return
        }
        if (this._AiCancelRequested(t)) {
            this._AiFinishChat(t, "", "", true)
            return
        }
        st := 0
        try st := AiAssist.ChatState()
        catch {
            this._AiFinishChat(t, "", GetLang("无法读取请求状态"))
            return
        }
        if (st == 1) {
            this._AiPulseThinking(t)
            return
        }
        if (st == 0) {
            ; idle：可能尚未 latch，或结果已被另一轮 Take 取走；勿当成「中断」清掉 busy
            return
        }
        ; Stop polling while synchronous tools or approval dialogs are running.
        ; The next request installs its own poll timer after the tool batch ends.
        SetTimer(this.aiChatTick, 0)
        reply := ""
        errMsg := ""
        try reply := AiAssist.TakeChat()
        catch as e
            errMsg := this._AiErrText(e)
        if (errMsg == "") {
            this._aiExecutingTools := true
            try {
                if (this._AiRunToolsAndResumeChat(t, reply))
                    return
            } catch as e {
                errMsg := this._AiErrText(e)
            } finally {
                this._aiExecutingTools := false
            }
        }
        this._AiFinishChat(t, reply, errMsg)
    }

    ; 返回 true 表示已接管本轮，调用者应等待下一轮或由这里结束对话。
    _AiRunToolsAndResumeChat(t, reply) {
        payload := AiAssist.ParseToolPayload(reply)
        if (!IsObject(payload))
            return false
        calls := (payload.Has("calls") && Type(payload["calls"]) = "Array") ? payload["calls"] : []
        if (calls.Length < 1)
            return false
        if (!IsObject(this._aiToolRound))
            this._aiToolRound := Map()
        rnd := this._aiToolRound.Has(t) ? Integer(this._aiToolRound[t]) : 0
        if (this._AiCancelRequested(t))
            return false
        if (rnd >= 8) {
            this._aiToolRound[t] := 0
            return false
        }
        this._aiToolRound[t] := rnd + 1
        this._AiShowThinking(t, true, GetLang("正在调用工具"))
        content := payload.Has("content") ? String(payload["content"]) : ""
        tcParts := ""
        for call in calls {
            if (Type(call) != "Map")
                continue
            cid := call.Has("id") ? String(call["id"]) : ("call_" A_Index)
            name := call.Has("name") ? String(call["name"]) : ""
            args := call.Has("arguments") ? String(call["arguments"]) : "{}"
            if (tcParts != "")
                tcParts .= ","
            tcParts .= '{"id":"' AiAssist._JsonEsc(cid) '","type":"function","function":{"name":"' AiAssist._JsonEsc(name) '","arguments":"' AiAssist._JsonEsc(args) '"}}'
        }
        asst := Map("role", "assistant", "content", content, "tool_calls", "[" tcParts "]")
        reason := AiAssist.ReasoningOf(payload)
        if (reason != "")
            asst["reasoning_content"] := reason
        this._AiHistPushMap(t, asst)
        for call in calls {
            if (Type(call) != "Map")
                continue
            cid := call.Has("id") ? String(call["id"]) : ("call_" A_Index)
            name := call.Has("name") ? String(call["name"]) : ""
            args := call.Has("arguments") ? String(call["arguments"]) : "{}"
            this._AiShowThinking(t, true, this._AiToolDoingText(name, args))
            if (this._AiCancelRequested(t))
                result := "Cancelled by user"
            else if (InStr(name, "_macro") && this._aiRequestConfig != MySoftData.CurSettingName)
                result := '{"ok":false,"error":"当前配置已切换，请在目标配置中重新发送消息"}'
            else
                result := AiAssist.ExecTool(name, args)
            this._AiNoteToolResult(t, name, args, result)
            this._AiHistPushMap(t, Map("role", "tool", "content", result, "tool_call_id", cid))
        }
        if (this._AiCancelRequested(t))
            return false
        this._AiShowThinking(t, false, GetLang("正在根据工具结果继续思考"))
        try {
            msgs := this._AiBuildApiMessages(t)
            AiAssist.BeginChat(msgs)
            SetTimer(this.aiChatTick, 200)
            return true
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
            return true
        }
    }

    _AiFinishChat(t, reply, errMsg, cancelled := false) {
        SetTimer(this.aiChatTick, 0)
        if (!IsObject(this._aiBusy))
            this._aiBusy := Map()
        if (cancelled || this._AiCancelRequested(t)) {
            this._aiBusy[t] := false
            if (!IsObject(this._aiCancel))
                this._aiCancel := Map()
            this._aiCancel[t] := false
            if (IsObject(this._aiToolRound) && this._aiToolRound.Has(t))
                this._aiToolRound[t] := 0
            this._AiSetSendMode(t, false)
            this._AiHideThinking(t)
            msg := GetLang("（已取消）")
            this._AiAppendMsg(t, false, msg)
            try this._AiHistPush(t, "assistant", msg)
            this._AiClearToolNotes(t)
            return
        }
        if (errMsg != "") {
            this._aiBusy[t] := false
            if (IsObject(this._aiToolRound) && this._aiToolRound.Has(t))
                this._aiToolRound[t] := 0
            this._AiSetSendMode(t, false)
            this._AiHideThinking(t)
            fail := GetLang("请求失败") "：`n" errMsg
            this._AiAppendMsg(t, false, fail)
            try this._AiHistPush(t, "assistant", fail)
            this._AiClearToolNotes(t)
            return
        }
        payload := AiAssist.ParseToolPayload(reply)
        reason := ""
        if (IsObject(payload) && payload.Has("content"))
            reply := String(payload["content"])
        if (IsObject(payload))
            reason := AiAssist.ReasoningOf(payload)
        reply := Trim(reply)
        if (reply == "")
            reply := Trim(this._AiComposeToolReply(t))
        if (reply == "" && !this._AiEmptyRetried(t)) {
            this._AiRetryEmptyReply(t)
            return
        }
        this._aiBusy[t] := false
        if (IsObject(this._aiToolRound) && this._aiToolRound.Has(t))
            this._aiToolRound[t] := 0
        this._AiSetSendMode(t, false)
        this._AiHideThinking(t)
        if (reply == "")
            reply := GetLang("这次没有生成说明。请再试一次，或把目标宏说得更具体（例如 1:2、触发键、要做的动作）。")
        else if (this._AiHasPermissionFail(t) && !InStr(reply, "写入权限") && !InStr(reply, "完全访问")) {
            extra := this._AiComposeToolFailReply(t)
            if (extra != "")
                reply .= "`n`n" extra
        }
        asst := Map("role", "assistant", "content", reply)
        if (reason != "")
            asst["reasoning_content"] := reason
        try this._AiHistPushMap(t, asst)
        this._AiAppendMsg(t, false, reply)
        this._AiClearToolNotes(t)
        if (IsObject(this._aiEmptyRetry))
            this._aiEmptyRetry[t] := false
    }

    _AiAnyBusy() {
        if (IsObject(this._aiBusy)) {
            for tab, busy in this._aiBusy {
                if (busy)
                    return true
            }
        }
        return false
    }

    _AiIsBusy(t) {
        return IsObject(this._aiBusy) && this._aiBusy.Has(t) && this._aiBusy[t]
    }

    _AiCancelRequested(t) {
        return IsObject(this._aiCancel) && this._aiCancel.Has(t) && this._aiCancel[t]
    }

    _AiCancelFromUser(t) {
        if (!this._AiIsBusy(t))
            return
        SetTimer(this.aiStartTick, 0)
        if (!IsObject(this._aiCancel))
            this._aiCancel := Map()
        this._aiCancel[t] := true
        this._aiChatTab := t
        AiAssist.CancelChat()
        if (this.HasOwnProp("_aiExecutingTools") && this._aiExecutingTools)
            return
        this._AiFinishChat(t, "", "", true)
    }

    _AiSetSendMode(t, busy) {
        glyph := busy ? Chr(0xE769) : Chr(0xE724)
        tip := busy ? GetLang("取消") : GetLang("发送")
        try this.ui.Update("AiSend_" t, "Content", glyph)
        try this.ui.Update("AiSend_" t, "ToolTip", tip)
        try this.ui.Update("AiSend_" t, "IsEnabled", "True")
    }

    _AiEmptyRetried(t) {
        return IsObject(this._aiEmptyRetry) && this._aiEmptyRetry.Has(t) && this._aiEmptyRetry[t]
    }

    _AiRetryEmptyReply(t) {
        if (!IsObject(this._aiEmptyRetry))
            this._aiEmptyRetry := Map()
        this._aiEmptyRetry[t] := true
        this._aiBusy[t] := true
        this._aiChatTab := t
        this._AiSetSendMode(t, true)
        this._AiShowThinking(t, false, GetLang("正在整理回复"))
        this._AiHistPush(t, "user", "请用中文说明刚才的结果或无法完成的原因，不要空回复。")
        try {
            msgs := this._AiBuildApiMessages(t)
            AiAssist.BeginChat(msgs)
            SetTimer(this.aiChatTick, 200)
        } catch as e {
            this._AiFinishChat(t, "", this._AiErrText(e))
        }
    }

    _AiThinkLabel(t) {
        if (IsObject(this._aiThinkDetail) && this._aiThinkDetail.Has(t) && Trim(this._aiThinkDetail[t]) != "")
            return this._aiThinkDetail[t]
        if (IsObject(this._aiThinkMode) && this._aiThinkMode.Has(t) && this._aiThinkMode[t] = "edit")
            return GetLang("正在编辑")
        return GetLang("正在思考")
    }

    _AiShowThinking(t, editing := false, detail := "") {
        if (!IsObject(this._aiThinkPhase))
            this._aiThinkPhase := Map()
        if (!IsObject(this._aiThinkMode))
            this._aiThinkMode := Map()
        if (!IsObject(this._aiThinkDetail))
            this._aiThinkDetail := Map()
        this._aiThinkPhase[t] := 0
        this._aiThinkMode[t] := editing ? "edit" : "think"
        if (detail != "")
            this._aiThinkDetail[t] := detail
        else if (!this._aiThinkDetail.Has(t) || this._aiThinkDetail[t] == "")
            this._aiThinkDetail[t] := editing ? GetLang("正在编辑") : GetLang("正在思考")
        try this.ui.Update("AiThinkTxt_" t, "Text", this._AiThinkLabel(t) "…")
        try this.ui.Update("AiThinkTxt_" t, "Visibility", "Visible")
    }

    _AiPulseThinking(t) {
        if (!IsObject(this._aiThinkPhase))
            this._aiThinkPhase := Map()
        phase := this._aiThinkPhase.Has(t) ? Integer(this._aiThinkPhase[t]) : 0
        phase := Mod(phase + 1, 4)
        this._aiThinkPhase[t] := phase
        dots := ""
        loop phase
            dots .= "."
        if (dots == "")
            dots := "…"
        try this.ui.Update("AiThinkTxt_" t, "Text", this._AiThinkLabel(t) dots)
    }

    _AiHideThinking(t) {
        if (IsObject(this._aiThinkMode) && this._aiThinkMode.Has(t))
            this._aiThinkMode[t] := "think"
        if (IsObject(this._aiThinkDetail) && this._aiThinkDetail.Has(t))
            this._aiThinkDetail[t] := ""
        try this.ui.Update("AiThinkTxt_" t, "Visibility", "Collapsed")
    }

    _AiToolArgPath(argsJson) {
        try {
            obj := JSON.parse(argsJson)
            if (Type(obj) = "Map") {
                if (obj.Has("path") && Trim(String(obj["path"])) != "")
                    return String(obj["path"])
                if (obj.Has("command") && Trim(String(obj["command"])) != "")
                    return String(obj["command"])
            }
        } catch {
        }
        return ""
    }

    _AiToolDoingText(name, argsJson) {
        path := this._AiToolArgPath(argsJson)
        SplitPath(path, &fn)
        switch name {
            case "write_file":
                return GetLang("正在写入文件") (fn != "" ? "：" fn : "")
            case "read_file":
                return GetLang("正在读取文件") (fn != "" ? "：" fn : "")
            case "list_dir":
                return GetLang("正在列出目录") (path != "" ? "：" path : "")
            case "run_command":
                return GetLang("正在执行命令")
            case "run_script":
                return GetLang("正在运行脚本") (fn != "" ? "：" fn : "")
            case "update_macro", "set_macro_step_enabled", "apply_macro_step_edit", "undo_macro_step_edit":
                return GetLang("正在修改宏")
            case "add_macro":
                return GetLang("正在新增宏")
            case "list_macros":
                return GetLang("正在查看宏列表")
            case "read_macro", "read_macro_step":
                return GetLang("正在读取宏")
            case "preview_macro_step_edit":
                return GetLang("正在生成修改预览")
            case "validate_macro":
                return GetLang("正在校验宏")
            default:
                return GetLang("正在调用") " " name
        }
    }

    _AiNoteToolResult(t, name, argsJson, result) {
        if (!IsObject(this._aiToolNotes))
            this._aiToolNotes := Map()
        if (!this._aiToolNotes.Has(t))
            this._aiToolNotes[t] := []
        ok := true
        err := ""
        summary := ""
        try {
            obj := JSON.parse(result)
            if (Type(obj) = "Map") {
                if (obj.Has("ok") && !obj["ok"])
                    ok := false
                if (obj.Has("error"))
                    err := String(obj["error"])
                if (ok && name = "validate_macro")
                    summary := AiMacroValidation.FormatReport(obj)
                else if (ok && name = "preview_macro_step_edit") {
                    summary := obj.Get("changed", false) ? GetLang("预览已生成，尚未保存。") : GetLang("参数没有变化。")
                    for change in obj.Get("changes", [])
                        summary .= "`n`n" change["field"] "："
                            . JSON.stringify(change["before"], 0) " → " JSON.stringify(change["after"], 0)
                }
            }
        } catch {
        }
        path := this._AiToolArgPath(argsJson)
        this._aiToolNotes[t].Push(Map("name", name, "ok", ok, "error", err, "path", path, "summary", summary))
        if (!ok && err != "")
            this._AiShowThinking(t, true, GetLang("工具失败") "：" this._AiShortErr(err))
    }

    _AiShortErr(err) {
        e := Trim(RegExReplace(String(err), "[\r\n]+", " "))
        if (StrLen(e) > 48)
            return SubStr(e, 1, 48) "…"
        return e
    }

    _AiHasPermissionFail(t) {
        if (!IsObject(this._aiToolNotes) || !this._aiToolNotes.Has(t))
            return false
        for n in this._aiToolNotes[t] {
            if (Type(n) != "Map" || !n.Has("error"))
                continue
            e := String(n["error"])
            if (InStr(e, "工作区") || InStr(e, "写入权限") || InStr(e, "完全访问") || InStr(e, "permission"))
                return true
        }
        return false
    }

    _AiComposeToolReply(t) {
        fail := this._AiComposeToolFailReply(t)
        if (fail != "")
            return fail
        if (!IsObject(this._aiToolNotes) || !this._aiToolNotes.Has(t))
            return ""
        okN := 0
        failN := 0
        done := ""
        summaries := ""
        firstError := ""
        for n in this._aiToolNotes[t] {
            if (Type(n) != "Map")
                continue
            nm := n.Has("name") ? String(n["name"]) : ""
            if (n.Has("ok") && n["ok"]) {
                okN += 1
                if (nm = "undo_macro_step_edit")
                    done := GetLang("已撤销参数修改")
                else if (nm = "update_macro" || nm = "set_macro_step_enabled" || nm = "apply_macro_step_edit")
                    done := GetLang("已按你的要求改好对应宏")
                else if (nm = "add_macro" && done == "")
                    done := GetLang("已新增宏")
                if (n.Get("summary", "") != "")
                    summaries .= (summaries == "" ? "" : "`n`n") n["summary"]
            } else {
                failN += 1
                if (firstError == "" && n.Get("error", "") != "")
                    firstError := n["error"]
            }
        }
        if (okN < 1 && failN < 1)
            return ""
        if (okN > 0 && failN < 1)
            return done != "" ? done "。" : (summaries != "" ? summaries : GetLang("操作已完成") "。")
        if (firstError != "")
            return (summaries != "" ? summaries "`n`n" : "") GetLang("工具失败") "：" firstError
        if (okN > 0)
            return GetLang("部分操作已完成，另有步骤失败。请换种说法再试，或检查目标宏是否存在。")
        return GetLang("操作未成功。请检查目标宏是否存在，或把页签和序号说得更具体。")
    }

    _AiComposeToolFailReply(t) {
        if (!this._AiHasPermissionFail(t))
            return ""
        lines := []
        lines.Push(GetLang("写入失败：当前写入权限为「工作区」，不能写到桌面等软件目录以外的位置。"))
        lines.Push(GetLang("请到「AI 设置 → 写入权限」改为「完全访问」后再试。"))
        seen := Map()
        for n in this._aiToolNotes[t] {
            if (Type(n) != "Map" || (n.Has("ok") && n["ok"]))
                continue
            p := n.Has("path") ? Trim(n["path"]) : ""
            if (p != "" && !seen.Has(p)) {
                seen[p] := true
                lines.Push("")
                fence := Chr(96) Chr(96) Chr(96)
                lines.Push(GetLang("目标："))
                lines.Push(fence)
                lines.Push(p)
                lines.Push(fence)
            }
        }
        out := ""
        for line in lines
            out .= (out == "" ? "" : "`n") line
        return out
    }

    _AiClearToolNotes(t) {
        if (IsObject(this._aiToolNotes) && this._aiToolNotes.Has(t))
            this._aiToolNotes[t] := []
    }
