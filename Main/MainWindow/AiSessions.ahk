
    _AiHistPush(t, role, content) {
        this._AiHistPushMap(t, Map("role", role, "content", content))
    }

    _AiHistPushMap(t, m) {
        if (!IsObject(this._aiHist))
            this._aiHist := Map()
        if (!this._aiHist.Has(t))
            this._aiHist[t] := []
        this._aiHist[t].Push(m)
        this._AiPersistSession(t)
    }

    AiGetSessionId(t) {
        if (!IsObject(this._aiSessionId) || !this._aiSessionId.Has(t))
            return ""
        return String(this._aiSessionId[t])
    }

    ; saveCurrent=true 时先落盘当前会话再清空
    AiNewChat(t, saveCurrent := true, showToast := true) {
        if (this._AiIsBusy(t)) {
            Toast.Info(GetLang("正在等待上一条回复…"))
            return
        }
        t := Integer(t)
        if (t < 1)
            return
        if (saveCurrent)
            this._AiPersistSession(t)
        this._AiClearChatUi(t)
        if (!IsObject(this._aiHist))
            this._aiHist := Map()
        this._aiHist[t] := []
        if (!IsObject(this._aiSessionId))
            this._aiSessionId := Map()
        this._aiSessionId[t] := ""
        if (!IsObject(this._aiSeededTabs))
            this._aiSeededTabs := Map()
        this._aiSeededTabs[t] := true  ; 阻止再次注入演示对话
        if (showToast)
            Toast.Success(GetLang("已新建对话"))
    }

    AiLoadSession(t, id) {
        if (this._AiIsBusy(t)) {
            Toast.Info(GetLang("正在等待上一条回复…"))
            return
        }
        t := Integer(t)
        id := Trim(String(id))
        if (t < 1 || id == "")
            return
        sess := AiChatStore.Get(id)
        if (!IsObject(sess)) {
            Toast.Warning(GetLang("找不到该对话记录"))
            return
        }
        ; 切换前保存当前（不同会话时）
        curId := this.AiGetSessionId(t)
        if (curId != "" && curId != id)
            this._AiPersistSession(t)
        else if (curId == "" && IsObject(this._aiHist) && this._aiHist.Has(t) && this._aiHist[t].Length > 0)
            this._AiPersistSession(t)

        msgs := []
        if (sess.Has("messages") && Type(sess["messages"]) = "Array") {
            for m in sess["messages"] {
                if (Type(m) != "Map")
                    continue
                role := m.Has("role") ? String(m["role"]) : "user"
                content := m.Has("content") ? String(m["content"]) : ""
                if (role = "system" || (Trim(content) == "" && !m.Has("tool_calls") && role != "tool"))
                    continue
                rec := Map("role", role, "content", content)
                if (m.Has("tool_calls"))
                    rec["tool_calls"] := String(m["tool_calls"])
                if (m.Has("tool_call_id"))
                    rec["tool_call_id"] := String(m["tool_call_id"])
                if (m.Has("reasoning_content") && m["reasoning_content"] != "")
                    rec["reasoning_content"] := String(m["reasoning_content"])
                msgs.Push(rec)
            }
        }
        this._AiClearChatUi(t)
        if (!IsObject(this._aiHist))
            this._aiHist := Map()
        this._aiHist[t] := msgs.Clone()
        if (!IsObject(this._aiSessionId))
            this._aiSessionId := Map()
        this._aiSessionId[t] := id
        if (!IsObject(this._aiSeededTabs))
            this._aiSeededTabs := Map()
        this._aiSeededTabs[t] := true
        for m in msgs {
            if ((m["role"] = "user" || m["role"] = "assistant") && Trim(m["content"]) != "")
                this._AiAppendMsg(t, m["role"] = "user", m["content"])
        }
        Toast.Success(GetLang("已打开对话"))
    }

    _AiPersistAllTabs() {
        if (!IsObject(this._aiHist))
            return
        for t, _ in this._aiHist
            this._AiPersistSession(t)
    }

    _AiPersistSession(t) {
        if (!IsObject(this._aiHist) || !this._aiHist.Has(t))
            return
        msgs := this._aiHist[t]
        if (Type(msgs) != "Array" || msgs.Length < 1)
            return
        if (!IsObject(this._aiSessionId))
            this._aiSessionId := Map()
        curId := this._aiSessionId.Has(t) ? String(this._aiSessionId[t]) : ""
        newId := ""
        try newId := AiChatStore.Upsert(curId, msgs)
        if (newId != "")
            this._aiSessionId[t] := newId
        try {
            if (AiHistoryGui.instances.Has("main")) {
                inst := AiHistoryGui.instances["main"]
                if (IsObject(inst) && !inst.closed)
                    inst._RefreshList()
            }
        }
    }

    _AiClearChatUi(t) {
        try this.ui.Update("SideAiMsgs_" t, "ClearItems", "")
        this._AiHideThinking(t)
    }

    _AiBuildApiMessages(t) {
        msgs := []
        selectedIndex := 0
        if (this.HasOwnProp("_aiRequestMacro") && IsObject(this._aiRequestMacro)
            && this._aiRequestConfig = MySoftData.CurSettingName
            && t >= 1 && t <= MySoftData.TableInfo.Length && CheckIsMacroTable(t)) {
            tableItem := MySoftData.TableInfo[t]
            idx := GetItemIndexInTable(tableItem, this._aiRequestMacro.ID)
            if (idx > 0 && tableItem.Items[idx] == this._aiRequestMacro)
                selectedIndex := idx
        }
        msgs.Push(Map("role", "system", "content", AiAssist.BuildSystemPrompt(t, selectedIndex)))
        if (IsObject(this._aiHist) && this._aiHist.Has(t)) {
            arr := this._aiHist[t]
            start := 1
            maxKeep := 24
            if (arr.Length > maxKeep)
                start := arr.Length - maxKeep + 1
            ; Keep a whole user turn: a fixed message cutoff can orphan tool
            ; results from their assistant tool_calls (or split a parallel batch).
            while (start > 1) {
                first := arr[start]
                if (Type(first) = "Map" && first.Has("role") && first["role"] = "user")
                    break
                start--
            }
            i := start
            while (i <= arr.Length) {
                m := arr[i]
                if (Type(m) = "Map")
                    msgs.Push(this._AiApiMessage(m))
                i++
            }
        }
        return msgs
    }

    _AiApiMessage(m) {
        role := m.Has("role") ? String(m["role"]) : "user"
        content := m.Has("content") ? String(m["content"]) : ""
        if (role = "user")
            content := this._AiExpandAttachForApi(content)
        out := Map("role", role, "content", content)
        if (m.Has("tool_calls"))
            out["tool_calls"] := m["tool_calls"]
        if (m.Has("tool_call_id"))
            out["tool_call_id"] := m["tool_call_id"]
        if (m.Has("reasoning_content") && m["reasoning_content"] != "")
            out["reasoning_content"] := m["reasoning_content"]
        else if (m.Has("reasoning") && m["reasoning"] != "")
            out["reasoning_content"] := m["reasoning"]
        if (m.Has("raw"))
            out["raw"] := m["raw"]
        return out
    }

    _AiExpandAttachForApi(text) {
        paths := this._AiExtractFilePaths(text)
        if (paths.Length < 1)
            return text
        display := Trim(RegExReplace(text, "\[([^\]]+)\]\(rmtfile:[^)]+\)", "$1"))
        extra := ""
        for path in paths {
            extra .= this._AiReadAttachBody(path)
        }
        return Trim(display) extra
    }

    _AiReadAttachBody(path) {
        if (path == "" || !FileExist(path))
            return "`n`n[文件不存在] " path
        SplitPath(path, &name, , &ext)
        ext := StrLower(ext)
        if (RegExMatch(ext, "i)^(png|jpe?g|gif|bmp|webp|ico)$"))
            return "`n`n[图片] " name " 路径: " path
        maxChars := 24000
        raw := ""
        try {
            f := FileOpen(path, "r", "UTF-8")
            raw := f.Read(maxChars + 1)
            f.Close()
        } catch {
            try {
                f := FileOpen(path, "r")
                raw := f.Read(maxChars + 1)
                f.Close()
            } catch {
                return "`n`n[无法读取] " name " 路径: " path
            }
        }
        if (StrLen(raw) > maxChars)
            raw := SubStr(raw, 1, maxChars) "`n…(已截断)"
        fence := Chr(96) Chr(96) Chr(96)
        return "`n`n### 附件 " name "`n路径: " path "`n" fence ext "`n" raw "`n" fence
    }
