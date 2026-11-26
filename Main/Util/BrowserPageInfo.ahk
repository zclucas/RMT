#Requires AutoHotkey v2.0
#Include WindowControlUtil.ahk

class BrowserPageReadError extends Error {
}

; 普通浏览器通过 UIA 读取，不启动或接管浏览器。
class BrowserPageInfo {
    static Sources := ["当前页签", "目标网址", "窗口绑定"]
    static Fields := ["页签ID", "网址", "标题"]

    static IsBrowser(hwnd) {
        try return WinGetClass(hwnd) == "Chrome_WidgetWin_1"
            && RegExMatch(WinGetProcessName(hwnd), "i)^(chrome|msedge)\.exe$")
        catch
            return false
    }

    static Read(source, field, targetUrl := "", winInfo := "", port := 9222, cancelled := "") {
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
            throw TargetError(GetLang("未找到 Chrome 或 Edge 浏览器窗口。"))
        if (source == "目标网址") {
            if (Trim(targetUrl) == "")
                throw ValueError(GetLang("目标网址不能为空。"))
            info := this.FindUrl(windows, targetUrl, cancelled)
        } else if (source == "当前页签") {
            info := ""
            for hwnd in windows {
                try snapshot := this.Snapshot(hwnd)
                catch OSError
                    continue
                ; 同步提示等 Chromium 对话框也使用浏览器窗口类，但没有标签栏。
                if (!snapshot.tabs.Length)
                    continue
                info := this.ReadWindow(hwnd, cancelled, field != "标题")
                break
            }
            if (!IsObject(info))
                throw TargetError(GetLang("未找到带页签的 Chrome 或 Edge 浏览器窗口。"))
        } else {
            info := this.ReadWindow(windows[1], cancelled, field != "标题")
        }
        switch field {
            case "网址": return info.url
            case "标题": return info.title
            case "页签ID": return this.TargetId(info, port)
            default: throw ValueError(GetLang("未知的页签信息类型。"))
        }
    }

    static CheckCancelled(cancelled) {
        if (IsObject(cancelled) && cancelled())
            throw Error(GetLang("页签信息读取已取消。"))
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
        return {hwnd: hwnd, url: url, title: title, tabs: tabs}
    }

    static ReadWindow(hwnd, cancelled := "", requireUrl := true) {
        deadline := A_TickCount + 3000
        loop {
            this.CheckCancelled(cancelled)
            try {
                info := this.Snapshot(hwnd)
                if ((!requireUrl || info.url != "") && info.title != "")
                    return info
            } catch OSError {
                ; 标签切换时可访问树会重建，重新获取树而不复用失效节点。
            }
            if (A_TickCount >= deadline)
                throw BrowserPageReadError(GetLang("无法读取页签网址和标题，请确保目标页面已加载且浏览器未最小化。"))
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

    static FindUrl(windows, url, cancelled := "") {
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
                        throw Error(GetLang("查找页签超时，请缩小窗口范围或使用窗口绑定。"))
                    this.SelectTab(tab.element)
                    try info := this.ReadWindow(hwnd, cancelled)
                    catch BrowserPageReadError {
                        this.CheckCancelled(cancelled)
                        continue
                    }
                    if (this.SameUrl(info.url, url)) {
                        if (IsObject(found))
                            throw TargetError(GetLang("有多个页签使用此网址，请改用窗口绑定定位。"))
                        found := info
                    }
                }
            } finally {
                if (IsObject(original))
                    try this.SelectTab(original)
            }
        }
        if (!IsObject(found))
            throw TargetError(GetLang("未找到对应网址的页签。"))
        return found
    }

    static TargetId(info, port) {
        if (!IsInteger(port) || port < 1 || port > 65535)
            throw ValueError(GetLang("浏览器调试端口无效。"))
        session := BrowserUtil.ManagedSessionForWindow(info.hwnd)
        if (!IsObject(session))
            throw BrowserConnectionError(GetLang("页签ID需要 CDP 支持，请通过「浏览器 → 网页 → 打开网址」勾选 CDP 打开该网页。"))
        BrowserUtil.Connect("127.0.0.1", session["port"])
        targets := JSON.parse(BrowserUtil.GetTabs())
        matches := []
        for target in targets {
            if (target["type"] == "page" && this.SameUrl(target["url"], info.url) && target["title"] == info.title)
                matches.Push(target.Has("targetId") ? target["targetId"] : target["id"])
        }
        if (matches.Length != 1)
            throw TargetError(GetLang(matches.Length ? "有多个同名同网址页签，无法唯一确定页签ID。" : "未找到对应页签，请确认目标网页由勾选 CDP 的打开网址指令创建。"))
        return matches[1]
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
