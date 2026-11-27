#Requires AutoHotkey v2.0
#Include WindowControlUtil.ahk

class BrowserPageReadError extends Error {
}

; 普通浏览器通过 UIA 读取，不启动或接管浏览器。
class BrowserPageInfo {
    static Sources := ["当前标签页", "网址", "标题", "正则表达式-网址", "正则表达式-标题"]
    static Fields := ["标签页ID", "网址", "标题", "加载状态"]
    static Outputs := Map("标签页ID", "PageIdVar", "网址", "PageUrlVar", "标题", "PageTitleVar", "加载状态", "PageStateVar")

    static NormalizeSource(source) {
        switch source {
            case "当前页签", "当前分页": return "当前标签页"
            case "目标网址": return "网址"
            case "正则网址", "正则表达式匹配网址": return "正则表达式-网址"
        }
        return source
    }

    static NormalizeField(field) => field == "页签ID" || field == "分页ID" ? "标签页ID" : field

    static UsesMatchValue(source) => this.NormalizeSource(source) == "网址" || this.NormalizeSource(source) == "标题" || this.IsRegex(source)
    static IsRegex(source) => this.NormalizeSource(source) == "正则表达式-网址" || this.NormalizeSource(source) == "正则表达式-标题"
    static MatchesTitle(source) => this.NormalizeSource(source) == "标题" || this.NormalizeSource(source) == "正则表达式-标题"

    static OutputVariables(data) {
        outputs := Map(), hasOutputs := false
        for field, name in this.Outputs {
            hasOutputs := hasOutputs || data.HasOwnProp(name)
            outputs[field] := data.HasOwnProp(name) ? data.%name% : ""
        }
        ; 旧单项配置转换成对应的独立变量，显式留空的新配置不回退。
        if (!hasOutputs && data.HasOwnProp("SaveVar") && data.SaveVar != "") {
            field := CmdEnumZh(this.NormalizeField(InputField(data, "PageField", "网址")), this.Fields)
            outputs[field] := data.SaveVar
        }
        return outputs
    }

    static IsBrowser(hwnd) {
        try return WinGetClass(hwnd) == "Chrome_WidgetWin_1"
            && RegExMatch(WinGetProcessName(hwnd), "i)^(chrome|msedge|brave|vivaldi|opera|chromium)\.exe$")
        catch
            return false
    }

    static Read(source, field, targetUrl := "", winInfo := "", port := 9222, cancelled := "") {
        field := this.NormalizeField(field)
        return this.ReadFields(source, [field], targetUrl, winInfo, port, cancelled)[field]
    }

    static ReadFields(source, fields, targetUrl := "", winInfo := "", port := 9222, cancelled := "") {
        source := this.NormalizeSource(source)
        normalizedFields := []
        for field in fields
            normalizedFields.Push(this.NormalizeField(field))
        fields := normalizedFields
        requireUrl := false
        for field in fields
            if (field != "标题")
                requireUrl := true
        if (source == "窗口绑定") {
            windows := []
            for hwnd in GetHwndList(winInfo)
                if (this.IsBrowser(hwnd))
                    windows.Push(hwnd)
        } else {
            windows := []
            for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1")
                if (this.IsBrowser(hwnd) && DllCall("IsWindowVisible", "Ptr", hwnd))
                    windows.Push(hwnd)
        }
        if (!windows.Length)
            throw TargetError(GetLang("未找到支持的浏览器窗口。"))
        if (this.UsesMatchValue(source)) {
            if (Trim(targetUrl) == "")
                throw ValueError(GetLang("请填写标签页匹配值。"))
            info := this.FindUrl(windows, targetUrl, cancelled, this.IsRegex(source), this.MatchesTitle(source) ? "标题" : "网址", requireUrl)
        } else if (source == "当前标签页") {
            info := ""
            for hwnd in windows {
                try snapshot := this.Snapshot(hwnd)
                catch OSError
                    continue
                ; 同步提示等 Chromium 对话框也使用浏览器窗口类，但没有标签栏。
                if (!snapshot.tabs.Length)
                    continue
                info := this.ReadWindow(hwnd, cancelled, requireUrl)
                break
            }
            if (!IsObject(info))
                throw TargetError(GetLang("未找到带标签页的浏览器窗口。"))
        } else {
            info := this.ReadWindow(windows[1], cancelled, requireUrl)
        }
        values := Map(), targetId := ""
        for field in fields
            if (field == "标签页ID" || field == "加载状态") {
                targetId := this.TargetId(info, port)
                break
            }
        for field in fields {
            this.CheckCancelled(cancelled)
            switch field {
                case "网址": values[field] := info.url
                case "标题": values[field] := info.title
                case "标签页ID", "加载状态":
                    values[field] := field == "标签页ID" ? targetId : this.LoadState(info, targetId)
                default: throw ValueError(GetLang("未知的标签页信息类型。"))
            }
        }
        return values
    }

    static LoadState(info, targetId) {
        original := this.Snapshot(info.hwnd)
        previousId := BrowserUtil.GetActiveTabId()
        try {
            BrowserUtil.SwitchTab(targetId)
            ; Chromium 网络错误页也会报告 complete，需先识别浏览器内部错误文档。
            state := BrowserUtil.Evaluate("/^(?:chrome|edge)-error:/.test(document.documentURI) ? 'unreachable' : document.readyState")
            switch state {
                case "unreachable": return "不可访问"
                case "loading": return "加载中"
                case "interactive": return "可交互"
                case "complete": return "加载完成"
                default: throw BrowserPageReadError(GetLang("无法读取网页加载状态。"))
            }
        } finally {
            if (previousId != "" && previousId != targetId)
                try BrowserUtil.SwitchTab(previousId)
            for tab in original.tabs
                if (tab.selected)
                    try this.SelectTab(tab.element)
        }
    }

    static CheckCancelled(cancelled) {
        if (IsObject(cancelled) && cancelled())
            throw Error(GetLang("标签页信息读取已取消。"))
    }

    static Snapshot(hwnd) {
        automation := WindowControl._Automation()
        root := WindowControl._Object(6, automation, "Ptr", hwnd)
        walker := WindowControl._Object(14, automation)
        pending := [root], tabs := [], documents := [], title := "", address := "", visited := 0
        while (pending.Length && ++visited <= 1500) {
            node := pending.Pop()
            type := WindowControl._Int(node, 21)
            cls := WindowControl._String(node, 30)
            if (type == 50019 && (cls == "Tab" || cls == "EdgeTab")) {
                pattern := WindowControl._Pattern(node, "selection")
                if (pattern) {
                    selected := WindowControl._Int(pattern, 6)
                    tabs.Push({element: node, selected: selected})
                    if (selected)
                        title := WindowControl._String(node, 23)
                }
            }
            if ((type == 50030 || cls == "OmniboxViewViews") && !WindowControl._Int(node, 38)) {
                if (pattern := WindowControl._Pattern(node, "value")) {
                    value := WindowControl._String(pattern, 4)
                    if (type == 50030 && value != "")
                        documents.Push({url: value, title: WindowControl._String(node, 23)})
                    else if (cls == "OmniboxViewViews")
                        address := value
                }
            }
            ; 网页 DOM 不参与浏览器标签栏和地址栏的遍历。
            if (type == 50030)
                continue
            child := WindowControl._Object(4, walker, "Ptr", node)
            children := []
            while (child) {
                children.Push(child)
                child := WindowControl._Object(6, walker, "Ptr", child)
            }
            loop children.Length
                pending.Push(children[children.Length - A_Index + 1])
        }
        url := ""
        for document in documents {
            ; Chromium 会在标签的可访问名称末尾追加内存占用等信息。
            if (document.title == title || (document.title != "" && InStr(title, document.title " - ", true) == 1
                && InStr(WinGetTitle(hwnd), document.title, true) == 1)) {
                url := document.url
                title := document.title
                break
            }
        }
        if (url == "" && title == "" && documents.Length == 1)
            url := documents[1].url
        ; 地址栏可能省略协议，只有完整地址才可作为后备值。
        if (url == "" && RegExMatch(address, "i)^[a-z][a-z0-9+.-]*:"))
            url := address
        errorPage := RegExMatch(url, "i)^(chrome|edge)-error:") != 0
        if (errorPage && address != "")
            url := address
        return {hwnd: hwnd, url: url, title: title, tabs: tabs, address: address, errorPage: errorPage}
    }

    static ReadWindow(hwnd, cancelled := "", requireUrl := true) {
        deadline := A_TickCount + 3000
        loop {
            this.CheckCancelled(cancelled)
            try {
                info := this.Snapshot(hwnd)
                if ((!requireUrl || info.url != "") && info.title != "") {
                    ; 错误文档地址是内部 URL；受控窗口优先还原 CDP 中保留的目标网址。
                    if (info.errorPage)
                        try this.TargetId(info, 9222)
                    return info
                }
            } catch OSError {
                ; 标签切换时可访问树会重建，重新获取树而不复用失效节点。
            }
            if (A_TickCount >= deadline)
                throw BrowserPageReadError(GetLang("无法读取标签页网址和标题，请确保目标页面已加载且浏览器未最小化。"))
            Sleep(100)
        }
    }

    static SelectTab(element) {
        pattern := WindowControl._RequiredPattern(element, "selection")
        ComCall(3, pattern)
    }

    static SameUrl(left, right) {
        ; 保留路径、查询串和大小写，避免把不同页面错误地视为同一页。
        return StrCompare(left, right, true) == 0
    }

    static FindUrl(windows, url, cancelled := "", regex := false, field := "网址", requireUrl := true) {
        if (regex)
            RegExMatch("", url) ; 在切换任何标签页前验证表达式。
        found := "", deadline := A_TickCount + 30000
        for hwnd in windows {
            this.CheckCancelled(cancelled)
            original := ""
            try {
                snapshot := this.Snapshot(hwnd)
                for tab in snapshot.tabs
                    if (tab.selected)
                        original := tab.element
                for tab in snapshot.tabs {
                    this.CheckCancelled(cancelled)
                    if (A_TickCount >= deadline)
                        throw Error(GetLang("查找标签页超时，请缩小网址匹配范围。"))
                    this.SelectTab(tab.element)
                    try info := this.ReadWindow(hwnd, cancelled, field == "网址" || requireUrl)
                    catch BrowserPageReadError {
                        this.CheckCancelled(cancelled)
                        continue
                    }
                    value := field == "标题" ? info.title : info.url
                    if (regex ? RegExMatch(value, url) : this.SameUrl(value, url)) {
                        if (IsObject(found))
                            throw TargetError(GetLang("匹配到多个标签页，请缩小匹配范围。"))
                        found := info
                    }
                }
            } finally {
                if (IsObject(original))
                    try this.SelectTab(original)
            }
        }
        if (!IsObject(found))
            throw TargetError(GetLang("未找到匹配的标签页。"))
        return found
    }

    static TargetId(info, port) {
        if (!IsInteger(port) || port < 1 || port > 65535)
            throw ValueError(GetLang("浏览器调试端口无效。"))
        session := BrowserUtil.ManagedSessionForWindow(info.hwnd)
        if (!IsObject(session))
            throw BrowserConnectionError(GetLang("标签页ID需要 CDP 支持，请通过「浏览器 → 网页 → 打开网址」勾选 CDP 打开该网页。"))
        BrowserUtil.Connect("127.0.0.1", session["port"])
        targets := JSON.parse(BrowserUtil.GetTabs())
        matches := []
        for target in targets {
            sameUrl := this.SameUrl(target["url"], info.url)
            if (info.HasOwnProp("errorPage") && info.errorPage && info.address != "")
                sameUrl := sameUrl || this.SameUrl(RTrim(RegExReplace(target["url"], "i)^https?://"), "/"), RTrim(info.address, "/"))
            if (target["type"] == "page" && sameUrl && target["title"] == info.title)
                matches.Push(target)
        }
        if (matches.Length != 1)
            throw TargetError(GetLang(matches.Length ? "有多个同名同网址标签页，无法唯一确定标签页ID。" : "未找到对应标签页，请确认目标网页由勾选 CDP 的打开网址指令创建。"))
        target := matches[1]
        info.url := target["url"]
        return target.Has("targetId") ? target["targetId"] : target["id"]
    }

    static OwnsDebugPort(hwnd, port) => BrowserUtil.HasPort(this.DebugPorts(hwnd), port)

    static DebugPorts(hwnd) {
        bytes := 0
        DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", 0, "UInt*", &bytes, "Int", false, "UInt", 2, "Int", 3, "UInt", 0)
        if (!bytes)
            return []
        table := Buffer(bytes)
        if (DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", table, "UInt*", &bytes, "Int", false, "UInt", 2, "Int", 3, "UInt", 0))
            return []
        ports := []
        pid := hwnd ? WinGetPID(hwnd) : 0
        loop NumGet(table, 0, "UInt") {
            offset := 4 + (A_Index - 1) * 24
            localPort := DllCall("Ws2_32\ntohs", "UShort", NumGet(table, offset + 8, "UShort"), "UShort")
            address := NumGet(table, offset + 4, "UInt")
            if (NumGet(table, offset, "UInt") == 2 && (address == 0 || address == 0x0100007F)
                && (!pid || NumGet(table, offset + 20, "UInt") == pid))
                ports.Push(localPort)
        }
        return ports
    }
}
