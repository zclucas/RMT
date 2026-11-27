#Requires AutoHotkey v2.0
#Include TimeoutPolicy.ahk
#Include BrowserActions.ahk

class BrowserConnectionError extends Error {
}

class BrowserTimeoutError extends Error {
}

; ==============================================================================
; 浏览器操作底层工具 (CDP / RMT_Browser.dll)
; ==============================================================================

class BrowserUtil {
    static _hDll := 0
    static _dllPath := ""

    static InitDll() {
        if (this._hDll)
            return true
        dllName := "RMT_Browser.dll"
        paths := []
        arch := A_PtrSize == 8 ? "x64" : "x86"
        for root in [A_WorkingDir, A_WorkingDir "\..", A_ScriptDir, A_ScriptDir "\.."] {
            if (arch == "x86")
                paths.Push(root "\Plugins\Browser\x86\" dllName)
            paths.Push(root "\Plugins\Browser\" dllName)
        }
        paths.Push(A_WorkingDir "\Release" arch "\Plugins\Browser\" dllName)
        for p in paths {
            if (FileExist(p)) {
                this._hDll := DllCall("LoadLibrary", "Str", p, "Ptr")
                if (this._hDll) {
                    this._dllPath := p
                    return true
                }
            }
        }
        return false
    }

    static _Utf8(value) {
        bytes := Buffer(StrPut(String(value), "UTF-8"))
        StrPut(String(value), bytes, "UTF-8")
        return bytes
    }

    static GetLastError() {
        if (!this.InitDll())
            return "RMT_Browser.dll 未找到或加载失败"
        buf := Buffer(2048, 0)
        DllCall("RMT_Browser\Browser_GetLastError", "Ptr", buf.Ptr, "Int", 2048, "Cdecl Int")
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetLastErrorCode() {
        if (!this.InitDll())
            return -1
        return DllCall("RMT_Browser\Browser_GetLastErrorCode", "Cdecl Int")
    }

    static _ThrowLastError(selectorType := "") {
        message := this.GetLastError()
        if (this.GetLastErrorCode() == -5 && InStr(message, "Launch browser failed:") != 1)
            throw BrowserConnectionError(GetLang("该指令需要 CDP 支持，请先在「浏览器 → 网页 → 打开网址」勾选 CDP 打开目标网页。"))
        ; CSS 交互在找元素超时后返回 Element not found，XPath 的即时查找用另一种错误。
        if (InStr(message, "Element not found") == 1) {
            if (selectorType = "CSS" && InStr(message, "Element not found:") == 1)
                throw BrowserTimeoutError(message)
        } else if (RegExMatch(message, "i)^(?:(?:Launch browser failed|Connect failed):\s*)?(?:timeout\b|timed out\b)|\b(?:ERR_(?:CONNECTION_)?TIMED_OUT|(?:request|navigation|operation|command|response) (?:timed out|timeout))\b"))
            throw BrowserTimeoutError(message)
        throw Error(message)
    }

    ; 获取系统中已安装的 Chromium 浏览器列表及路径
    static GetInstalledBrowsers() {
        list := []
        seenPaths := Map()

        checkAdd := (name, p) => (
            p != "" && FileExist(p) && !seenPaths.Has(p) ? (seenPaths[p] := true, list.Push({name: name, path: p})) : 0
        )

        pf  := EnvGet("ProgramFiles")
        pfx := EnvGet("ProgramFiles(x86)")
        pf64 := EnvGet("ProgramW6432")
        lad := EnvGet("LocalAppData")

        ; 1. Chrome
        for reg in [
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
            "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
            "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
        ] {
            try {
                p := Trim(RegRead(reg), '" ')
                checkAdd("Chrome", p)
            }
        }
        for p in [
            lad "\Google\Chrome\Application\chrome.exe",
            pf  "\Google\Chrome\Application\chrome.exe",
            pfx "\Google\Chrome\Application\chrome.exe"
        ] {
            checkAdd("Chrome", p)
        }

        ; 2. Edge
        for reg in [
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
            "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
            "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe"
        ] {
            try {
                p := Trim(RegRead(reg), '" ')
                checkAdd("Edge", p)
            }
        }
        for p in [
            pfx "\Microsoft\Edge\Application\msedge.exe",
            pf  "\Microsoft\Edge\Application\msedge.exe",
            lad "\Microsoft\Edge\Application\msedge.exe"
        ] {
            checkAdd("Edge", p)
        }

        ; 3. Brave
        for p in [
            pf "\BraveSoftware\Brave-Browser\Application\brave.exe",
            pfx "\BraveSoftware\Brave-Browser\Application\brave.exe",
            lad "\BraveSoftware\Brave-Browser\Application\brave.exe"
        ] {
            checkAdd("Brave", p)
        }

        ; 4. Vivaldi
        for p in [
            lad "\Vivaldi\Application\vivaldi.exe",
            pf "\Vivaldi\Application\vivaldi.exe"
        ] {
            checkAdd("Vivaldi", p)
        }

        ; 5. Opera
        for p in [
            lad "\Programs\Opera\opera.exe",
            pf "\Opera\opera.exe"
        ] {
            checkAdd("Opera", p)
        }

        ; 补全 Chromium 及其衍生浏览器的 App Paths 注册与常见安装位置。
        for name, exe in Map("Brave", "brave.exe", "Vivaldi", "vivaldi.exe", "Opera", "opera.exe", "Chromium", "chromium.exe") {
            for root in ["HKCU\SOFTWARE", "HKLM\SOFTWARE", "HKLM\SOFTWARE\WOW6432Node"]
                try checkAdd(name, Trim(RegRead(root "\Microsoft\Windows\CurrentVersion\App Paths\" exe), '" '))
        }
        for root in [pf, pfx, pf64, lad] {
            if (root == "")
                continue
            checkAdd("Chrome", root "\Google\Chrome\Application\chrome.exe")
            checkAdd("Edge", root "\Microsoft\Edge\Application\msedge.exe")
            checkAdd("Brave", root "\BraveSoftware\Brave-Browser\Application\brave.exe")
            checkAdd("Chromium", root "\Chromium\Application\chrome.exe")
            checkAdd("Chromium", root "\Chromium\Application\chromium.exe")
            checkAdd("Vivaldi", root "\Vivaldi\Application\vivaldi.exe")
            checkAdd("Opera", root "\Opera\opera.exe")
            checkAdd("Opera", root "\Programs\Opera\opera.exe")
        }
        return list
    }

    static GetDefaultBrowserPath() {
        ; 查询 HTTPS 协议的当前关联程序，跟随系统默认浏览器设置。
        chars := 0
        DllCall("Shlwapi\AssocQueryStringW", "UInt", 0, "UInt", 2, "Str", "https", "Str", "open", "Ptr", 0, "UInt*", &chars, "Int")
        if (!chars)
            throw Error("无法获取系统默认浏览器路径")
        path := Buffer(chars * 2, 0)
        result := DllCall("Shlwapi\AssocQueryStringW", "UInt", 0, "UInt", 2, "Str", "https", "Str", "open", "Ptr", path.Ptr, "UInt*", &chars, "Int")
        executable := StrGet(path, "UTF-16")
        if (result != 0 || executable == "" || !FileExist(executable))
            throw Error("无法获取系统默认浏览器路径")
        return executable
    }

    static Launch(browserType := "Chrome", browserPath := "", headless := 0, userDataDir := "", port := 9222) {
        if (BrowserActions.BrowserType(browserType) == "默认浏览器") {
            browserPath := this.GetDefaultBrowserPath()
            browserType := "自定义路径"
        }
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Launch", "Ptr", this._Utf8(browserType), "Ptr", this._Utf8(browserPath), "Int", headless, "Ptr", this._Utf8(userDataDir), "Int", port, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static OpenUrl(url, browserType := "Chrome", browserPath := "", incognito := false, headless := 0, userDataDir := "", port := 9222, timeoutMs := 5000, newWindow := false, useCDP := false) {
        browserPath := this.ResolveBrowserPath(browserType, browserPath)
        command := this.OpenUrlCommand(url, "自定义路径", browserPath, incognito, newWindow)
        if (!useCDP) {
            Run(command)
            return true
        }
        if (!headless && userDataDir == "" && this.TryManagedConnection(browserPath, port)) {
            this.OpenConnectedUrl(url, incognito ? 1 : (newWindow ? 2 : 0), timeoutMs)
            return true
        }
        if (this.HasPort(BrowserPageInfo.DebugPorts(0), port))
            port := 0
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_OpenUrl", "Ptr", this._Utf8("自定义路径"), "Ptr", this._Utf8(browserPath),
            "Int", headless, "Ptr", this._Utf8(userDataDir), "Int", port, "Ptr", this._Utf8(url),
            "Int", incognito ? 1 : (newWindow ? 2 : 0), "Int", timeoutMs, "Cdecl Int")
        if (this.ConnectionPort())
            this.RegisterCDPSession(browserPath)
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static ResolveBrowserPath(browserType, browserPath := "") {
        browserType := BrowserActions.BrowserType(browserType)
        if (browserType == "默认浏览器")
            browserPath := this.GetDefaultBrowserPath()
        else if (browserType != "自定义路径" && browserType != "自定义") {
            browserPath := ""
            for browser in this.GetInstalledBrowsers() {
                if (browser.name == browserType) {
                    browserPath := browser.path
                    break
                }
            }
        }
        if (browserPath == "" || !FileExist(browserPath) || InStr(browserPath, '"'))
            throw Error("找不到所选浏览器，请检查安装或自定义路径")
        return StrReplace(browserPath, "/", "\")
    }

    static OpenUrlCommand(url, browserType := "Chrome", browserPath := "", incognito := false, newWindow := false) {
        browserPath := this.ResolveBrowserPath(browserType, browserPath)
        if (Trim(url) == "" || InStr(url, "`r") || InStr(url, "`n"))
            throw Error("请输入有效的网址")
        SplitPath(browserPath, &exeName)
        if (incognito)
            options := StrLower(exeName) == "msedge.exe" ? "--inprivate --new-tab"
                : StrLower(exeName) == "firefox.exe" ? "-private-window" : "--incognito --new-tab"
        else
            options := newWindow ? "--new-window" : "--new-tab"
        ; URL 置于选项终止符后，避免被解析为浏览器启动参数。
        return '"' browserPath '" ' options ' -- "' StrReplace(url, '"', "%22") '"'
    }

    static BrowserWindows(browserPath := "") {
        windows := []
        for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1") {
            try {
                if (!DllCall("IsWindowVisible", "Ptr", hwnd))
                    continue
                if (browserPath != "" ? StrCompare(WinGetProcessPath(hwnd), browserPath, false) != 0
                    : !RegExMatch(WinGetProcessName(hwnd), "i)^(chrome|msedge|chromium|brave|vivaldi|opera)\.exe$"))
                    continue
                windows.Push(hwnd)
            }
        }
        return windows
    }

    static HasPort(ports, wanted) {
        for port in ports
            if (port == wanted)
                return true
        return false
    }

    static ConnectionPort() {
        if (!this.InitDll())
            return 0
        return DllCall("RMT_Browser\Browser_GetConnectionPort", "Cdecl Int")
    }

    static CDPStateDir() => RmtCacheDir() "\BrowserCDP"

    static ProcessStamp(pid) {
        handle := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
        if (!handle)
            return ""
        try {
            times := Buffer(32)
            if (!DllCall("GetProcessTimes", "Ptr", handle, "Ptr", times, "Ptr", times.Ptr + 8, "Ptr", times.Ptr + 16, "Ptr", times.Ptr + 24))
                return ""
            return Format("{:X}", NumGet(times, 0, "Int64"))
        } finally DllCall("CloseHandle", "Ptr", handle)
    }

    static DebugPortPID(port) {
        bytes := 0
        DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", 0, "UInt*", &bytes, "Int", false, "UInt", 2, "Int", 3, "UInt", 0)
        if (!bytes)
            return 0
        table := Buffer(bytes)
        if (DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", table, "UInt*", &bytes, "Int", false, "UInt", 2, "Int", 3, "UInt", 0))
            return 0
        loop NumGet(table, 0, "UInt") {
            offset := 4 + (A_Index - 1) * 24
            localPort := DllCall("Ws2_32\ntohs", "UShort", NumGet(table, offset + 8, "UShort"), "UShort")
            address := NumGet(table, offset + 4, "UInt")
            if (localPort == port && NumGet(table, offset, "UInt") == 2 && (address == 0 || address == 0x0100007F))
                return NumGet(table, offset + 20, "UInt")
        }
        return 0
    }

    static RegisterCDPSession(browserPath) {
        port := this.ConnectionPort(), pid := this.DebugPortPID(port)
        stamp := this.ProcessStamp(pid)
        if (!pid || stamp == "")
            throw BrowserConnectionError(GetLang("无法记录 CDP 会话，请重新勾选 CDP 打开网址。"))
        actualPath := ProcessGetPath(pid)
        if (StrCompare(actualPath, browserPath, false) != 0)
            throw BrowserConnectionError(GetLang("CDP 会话与所选浏览器不匹配，请重新打开网址。"))
        dir := this.CDPStateDir()
        DirCreate(dir)
        record := Map("port", port, "pid", pid, "stamp", stamp, "path", actualPath)
        temporary := dir "\" port "-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount ".tmp"
        file := FileOpen(temporary, "w", "UTF-8-RAW")
        file.Write(JSON.stringify(record))
        file.Close()
        FileMove(temporary, dir "\" port ".json", 1)
    }

    static CDPSessions() {
        sessions := []
        loop files this.CDPStateDir() "\*.json" {
            try {
                session := JSON.parse(FileRead(A_LoopFileFullPath, "UTF-8"))
                pid := session["pid"]
                if (this.DebugPortPID(session["port"]) == pid && this.ProcessStamp(pid) == session["stamp"]
                    && StrCompare(ProcessGetPath(pid), session["path"], false) == 0)
                    sessions.Push(session)
            }
        }
        return sessions
    }

    static ManagedSessionForWindow(hwnd) {
        pid := WinGetPID(hwnd)
        for session in this.CDPSessions()
            if (session["pid"] == pid)
                return session
        return ""
    }

    static TryManagedConnection(browserPath := "", preferredPort := 9222) {
        sessions := this.CDPSessions(), current := this.ConnectionPort()
        for session in sessions {
            if (browserPath != "" && StrCompare(session["path"], browserPath, false) != 0)
                continue
            if (session["port"] == current)
                return true
        }
        for wanted in [preferredPort, 0] {
            for session in sessions {
                if ((wanted && session["port"] != wanted)
                    || (browserPath != "" && StrCompare(session["path"], browserPath, false) != 0))
                    continue
                try {
                    this.Connect("127.0.0.1", session["port"])
                    return true
                }
            }
        }
        return false
    }

    static EnsureConnection(port := 9222) {
        if (this.TryManagedConnection("", port))
            return true
        throw BrowserConnectionError(GetLang("该指令需要 CDP 支持，请先在「浏览器 → 网页 → 打开网址」勾选 CDP 打开目标网页。"))
    }

    static OpenConnectedUrl(url, mode := 0, timeoutMs := 5000) {
        res := DllCall("RMT_Browser\Browser_OpenConnectedUrl", "Ptr", this._Utf8(url), "Int", mode, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static Connect(host := "127.0.0.1", port := 9222) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Connect", "Ptr", this._Utf8(host), "Int", port, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static Navigate(url, timeoutMs := 30000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Navigate", "Ptr", this._Utf8(url), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static Reload(ignoreCache := 0) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Reload", "Int", ignoreCache, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static GoBack() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_GoBack", "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static GoForward() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_GoForward", "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    ; --- 标签页管理 ---

    static GetTabs() {
        this.EnsureConnection()
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetTabs", "Ptr", buf.Ptr, "Int", 65536, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static SwitchTab(targetRef) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_SwitchTab", "Ptr", this._Utf8(String(targetRef)), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static GetActiveTabId() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(256, 0)
        res := DllCall("RMT_Browser\Browser_GetActiveTabId", "Ptr", buf.Ptr, "Int", 256, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static NewTab(url := "about:blank") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(256, 0)
        res := DllCall("RMT_Browser\Browser_NewTab", "Ptr", this._Utf8(url), "Ptr", buf.Ptr, "Int", 256, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static NewTabInContext(url := "about:blank", contextId := "") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(256, 0)
        res := DllCall("RMT_Browser\Browser_NewTabInContext", "Ptr", this._Utf8(url), "Ptr", this._Utf8(contextId), "Ptr", buf.Ptr, "Int", 256, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static CreateContext() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(256, 0)
        res := DllCall("RMT_Browser\Browser_CreateContext", "Ptr", buf.Ptr, "Int", 256, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static CloseContext(contextId) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CloseContext", "Ptr", this._Utf8(String(contextId)), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static CloseTabByRef(targetRef := "") {
        if (targetRef == "")
            return this.CloseTab()
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CloseTabByRef", "Ptr", this._Utf8(String(targetRef)), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    ; --- 等待条件 ---

    static WaitElement(selector, selectorType := "CSS", condition := "appear", timeoutMs := 10000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_WaitElement", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", this._Utf8(condition), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static WaitText(selector, selectorType := "CSS", expectedText := "", timeoutMs := 10000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_WaitText", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", this._Utf8(expectedText), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static WaitPageLoad(loadState := "load", timeoutMs := 30000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_WaitPageLoad", "Ptr", this._Utf8(loadState), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    ; --- DOM 交互 ---

    static Click(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Click", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static DoubleClick(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_DoubleClick", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static RightClick(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_RightClick", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static Type(selector, selectorType := "CSS", text := "", clearBefore := 1, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Type", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", this._Utf8(text), "Int", clearBefore, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static Clear(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Clear", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static Select(selector, selectorType := "CSS", value := "", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Select", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", this._Utf8(value), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static Check(selector, selectorType := "CSS", checked := 1, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Check", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", checked, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static ScrollTo(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_ScrollTo", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static Hover(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Hover", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError(selectorType)
        return true
    }

    static GetElementCount(selector, selectorType := "CSS") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        count := 0
        res := DllCall("RMT_Browser\Browser_GetElementCount", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int*", &count, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return count
    }

    static GetElementState(selector, selectorType := "CSS") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(2048, 0)
        res := DllCall("RMT_Browser\Browser_GetElementState", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", buf.Ptr, "Int", 2048, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    ; --- CDP 鼠标与键盘模拟 ---

    static MouseMove(x, y) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_MouseMove", "Double", Float(x), "Double", Float(y), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static MouseClick(x, y, button := "left") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_MouseClick", "Double", Float(x), "Double", Float(y), "Ptr", this._Utf8(button), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static MouseWheel(deltaX, deltaY) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_MouseWheel", "Double", Float(deltaX), "Double", Float(deltaY), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static KeyPress(key, modifiers := 0) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_KeyPress", "Ptr", this._Utf8(key), "Int", modifiers, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    ; --- Storage & Cookies ---

    static GetCookie(name := "") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetCookie", "Ptr", this._Utf8(name), "Ptr", buf.Ptr, "Int", 65536, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static SetCookie(name, value, domain := "", path := "/") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_SetCookie", "Ptr", this._Utf8(name), "Ptr", this._Utf8(value), "Ptr", this._Utf8(domain), "Ptr", this._Utf8(path), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static ClearCookies() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_ClearCookies", "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static GetStorage(storageType := "local", key := "") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetStorage", "Ptr", this._Utf8(StrLower(storageType)), "Ptr", this._Utf8(key), "Ptr", buf.Ptr, "Int", 65536, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static SetStorage(storageType := "local", key := "", value := "") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_SetStorage", "Ptr", this._Utf8(StrLower(storageType)), "Ptr", this._Utf8(key), "Ptr", this._Utf8(value), "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    ; --- 数据提取与 JS ---

    static Evaluate(script, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_Evaluate", "Ptr", this._Utf8(script), "Ptr", buf.Ptr, "Int", 65536, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    ; 只读表达式允许重新求值扩容；操作脚本仍使用 Evaluate，避免重复执行操作。
    static EvaluateRead(script, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        deadline := A_TickCount + Integer(timeoutMs), capacity := 65536
        loop {
            remaining := deadline - A_TickCount
            if (remaining <= 0)
                throw BrowserTimeoutError(GetLang("读取网页信息超时。"))
            buf := Buffer(capacity, 0)
            res := DllCall("RMT_Browser\Browser_Evaluate", "Ptr", this._Utf8(script), "Ptr", buf.Ptr,
                "Int", capacity, "Int", remaining, "Cdecl Int")
            if (res != 0)
                this._ThrowLastError()
            ; 在 UTF-8 解码前检查字节数，避免截断多字节字符后误判长度。
            if (DllCall("lstrlenA", "Ptr", buf.Ptr, "Int") < capacity - 1)
                return StrGet(buf.Ptr, "UTF-8")
            if (capacity >= 64 * 1024 * 1024)
                throw Error(GetLang("网页信息超过64MB，无法完整读取。"))
            capacity *= 2
        }
    }

    static StartElementPicker(token, selectorType, preferControl := false) {
        args := JSON.stringify([token, selectorType, preferControl], 0)
        script := "
        (
            (([token, type, preferControl]) => {
                window.__rmtActivePicker?.stop();
                const overlay = document.createElement('rmt-element-picker');
                overlay.style.cssText = 'all:initial!important;position:fixed!important;inset:0!important;'
                    + 'display:block!important;pointer-events:none!important;z-index:2147483647!important';
                const canvas = document.createElement('canvas');
                canvas.style.cssText = 'display:block;width:100%;height:100%;pointer-events:none';
                overlay.attachShadow({mode: 'closed'}).append(canvas);
                const ctx = canvas.getContext('2d');
                document.documentElement.append(overlay);
                let pointer = null, frame = 0, lastRect = '';

                function selectorFor(el) {
                    if (type === 'CSS' && el.id) {
                        const byId = '#' + CSS.escape(el.id);
                        const matches = document.querySelectorAll(byId);
                        if (matches.length === 1 && matches[0] === el) return byId;
                    }
                    const parts = [];
                    for (let node = el; node; node = node.parentElement) {
                        const name = node.localName;
                        let index = 1;
                        let hasSibling = false;
                        for (let sibling = node.previousElementSibling; sibling; sibling = sibling.previousElementSibling) {
                            if (sibling.localName === name) {
                                index++;
                                hasSibling = true;
                            }
                        }
                        if (type === 'XPath') {
                            parts.unshift('*[local-name()="' + name + '"][' + index + ']');
                        } else {
                            for (let sibling = node.nextElementSibling; !hasSibling && sibling; sibling = sibling.nextElementSibling)
                                hasSibling = sibling.localName === name;
                            parts.unshift(CSS.escape(name) + (hasSibling ? ':nth-of-type(' + index + ')' : ''));
                        }
                    }
                    return type === 'XPath' ? '/' + parts.join('/') : parts.join(' > ');
                }

                function targetFor(target) {
                    if (!(target instanceof Element) || target.getRootNode() !== document) return null;
                    return preferControl ? target.closest('button,a,input,select,textarea,[role=button],[contenteditable]') || target : target;
                }
                function hover(event) {
                    pointer = [event.clientX, event.clientY];
                    if (!frame) frame = requestAnimationFrame(draw);
                }
                function clearOverlay() {
                    if (!lastRect) return;
                    ctx.resetTransform();
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                    lastRect = '';
                }
                function leave(event) {
                    if (event.type === 'pointerout' && event.relatedTarget) return;
                    if (event.type === 'blur' && event.target !== window) return;
                    pointer = null;
                    cancelAnimationFrame(frame);
                    frame = 0;
                    clearOverlay();
                }
                function draw() {
                    // 重新命中鼠标位置，滚动和布局变化时高亮也能跟上。
                    frame = requestAnimationFrame(draw);
                    const target = targetFor(document.elementFromPoint(...pointer));
                    if (!target || target.matches('iframe,frame')) return clearOverlay();
                    const rect = target.getBoundingClientRect();
                    const w = innerWidth, h = innerHeight, scale = devicePixelRatio || 1;
                    const l = Math.max(0, rect.left), t = Math.max(0, rect.top);
                    const r = Math.min(w, rect.right), b = Math.min(h, rect.bottom);
                    if (r <= l || b <= t) return clearOverlay();

                    let pl = 0, pt = 0, pr = w, pb = h;
                    for (let node = target.parentElement; node; node = node.parentElement) {
                        const parent = node.getBoundingClientRect();
                        if (parent.left > rect.left || parent.top > rect.top
                            || parent.right < rect.right || parent.bottom < rect.bottom) continue;
                        if (parent.left === rect.left && parent.top === rect.top
                            && parent.right === rect.right && parent.bottom === rect.bottom) continue;
                        pl = Math.max(0, parent.left);
                        pt = Math.max(0, parent.top);
                        pr = Math.min(w, parent.right);
                        pb = Math.min(h, parent.bottom);
                        break;
                    }
                    const key = [w, h, scale, l, t, r, b, pl, pt, pr, pb].join();
                    if (key === lastRect) return;
                    lastRect = key;
                    const width = Math.round(w * scale), height = Math.round(h * scale);
                    if (canvas.width !== width) canvas.width = width;
                    if (canvas.height !== height) canvas.height = height;
                    ctx.setTransform(scale, 0, 0, scale, 0, 0);
                    ctx.clearRect(0, 0, w, h);
                    ctx.fillStyle = '#0c142260';
                    ctx.beginPath();
                    ctx.rect(0, 0, w, h);
                    ctx.rect(l, t, r - l, b - t);
                    ctx.fill('evenodd');
                    ctx.fillStyle = '#2c90ef38';
                    ctx.fillRect(l, t, r - l, b - t);

                    ctx.lineWidth = 1;
                    ctx.strokeStyle = '#9bd5ffe6';
                    ctx.setLineDash([4, 3]);
                    ctx.beginPath();
                    for (const x of [l, r]) {
                        ctx.moveTo(x, t); ctx.lineTo(x, pt);
                        ctx.moveTo(x, b); ctx.lineTo(x, pb);
                    }
                    for (const y of [t, b]) {
                        ctx.moveTo(l, y); ctx.lineTo(pl, y);
                        ctx.moveTo(r, y); ctx.lineTo(pr, y);
                    }
                    ctx.stroke();
                    ctx.setLineDash([]);
                    ctx.strokeStyle = '#55b5ff';
                    ctx.strokeRect(l, t, r - l, b - t);
                }
                function suppress(event) {
                    if (event.button !== 0) return;
                    event.preventDefault();
                    event.stopImmediatePropagation();
                }
                function confirm() {
                    const target = targetFor(pointer ? document.elementFromPoint(...pointer)
                        : Array.from(document.querySelectorAll(':hover')).pop());
                    if (target && !target.matches('iframe,frame')) finish('picked:' + selectorFor(target));
                    return picker.result;
                }
                function escape(event) {
                    if (event.key !== 'Escape') return;
                    event.preventDefault();
                    event.stopImmediatePropagation();
                    finish('cancelled');
                }
                function finish(result) {
                    if (picker.result !== 'pending') return;
                    picker.result = result;
                    clearTimeout(deadline);
                    cancelAnimationFrame(frame);
                    overlay.remove();
                    for (const [type, listener] of Object.entries(listeners))
                        window.removeEventListener(type, listener, true);
                }
                const picker = {
                    result: 'pending',
                    confirm,
                    stop() {
                        finish('cancelled');
                        delete window[token];
                        if (window.__rmtActivePicker === picker) delete window.__rmtActivePicker;
                    }
                };
                const listeners = {pointermove: hover, pointerout: leave, blur: leave,
                    pointerdown: suppress, pointerup: suppress, click: suppress, keydown: escape};
                const deadline = setTimeout(() => finish('cancelled'), 120000);
                window[token] = window.__rmtActivePicker = picker;
                for (const [type, listener] of Object.entries(listeners))
                    window.addEventListener(type, listener, true);
                return 'ready';
            })
        )"
        if (this.Evaluate(script "(" args ")") != "ready")
            throw Error(GetLang("无法在当前网页启动元素拾取。"))
    }

    static GetText(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetText", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", buf.Ptr, "Int", 65536, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetAttribute(selector, selectorType := "CSS", attrName := "href", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetAttribute", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Ptr", this._Utf8(attrName), "Ptr", buf.Ptr, "Int", 65536, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetHtml(selector := "", selectorType := "CSS", outerHtml := 1, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(131072, 0)
        res := DllCall("RMT_Browser\Browser_GetHtml", "Ptr", this._Utf8(selector), "Ptr", this._Utf8(StrLower(selectorType)), "Int", outerHtml, "Ptr", buf.Ptr, "Int", 131072, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetUrl() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(4096, 0)
        res := DllCall("RMT_Browser\Browser_GetUrl", "Ptr", buf.Ptr, "Int", 4096, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetTitle() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(4096, 0)
        res := DllCall("RMT_Browser\Browser_GetTitle", "Ptr", buf.Ptr, "Int", 4096, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static CaptureScreenshot(filePath, fullPage := 0) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CaptureScreenshot", "Ptr", this._Utf8(filePath), "Int", fullPage, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static CloseTab() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CloseTab", "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static CloseBrowser() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        port := this.ConnectionPort()
        res := DllCall("RMT_Browser\Browser_CloseBrowser", "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        ; 关闭响应可能早于进程退出，先撤销记录，防止再次连接退出中的实例。
        if (port > 0)
            try FileDelete(this.CDPStateDir() "\" port ".json")
        return true
    }

    static ClearCacheAndReload() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        result := DllCall("RMT_Browser\Browser_ClearCacheAndReload", "Cdecl Int")
        if (result != 0)
            this._ThrowLastError()
        return true
    }

    static CurrentTabAction(operation, cancelled := "", port := 9222) {
        snapshot := "", hwnd := 0
        for candidate in WinGetList("ahk_class Chrome_WidgetWin_1") {
            BrowserPageInfo.CheckCancelled(cancelled)
            if (!BrowserPageInfo.IsBrowser(candidate) || !DllCall("IsWindowVisible", "Ptr", candidate))
                continue
            try info := BrowserPageInfo.Snapshot(candidate)
            catch OSError
                continue
            if (info.tabs.Length) {
                snapshot := info
                hwnd := candidate
                break
            }
        }
        if (!IsObject(snapshot))
            throw TargetError(GetLang("未找到带标签页的浏览器窗口。"))
        BrowserPageInfo.CheckCancelled(cancelled)
        if (operation == "清空缓存") {
            id := BrowserPageInfo.TargetId(snapshot, port)
            this.SwitchTab(id)
            return this.ClearCacheAndReload()
        }
        if (operation == "关闭") {
            walker := WindowControl._Object(14, WindowControl._Automation())
            for tab in snapshot.tabs {
                if (!tab.selected)
                    continue
                BrowserPageInfo.CheckCancelled(cancelled)
                if (this._InvokeTabClose(tab.element, walker))
                    return true
                tab.selection := WindowControl._Pattern(tab.element, "selection")
                if (tab.selection && this._MiddleClickTab(hwnd, tab, cancelled))
                    return true
                throw Error(GetLang("无法关闭当前标签页。"))
            }
            throw TargetError(GetLang("未找到当前标签页。"))
        }
        commands := Map("后退", 1, "前进", 2, "刷新", 3)
        if (!commands.Has(operation))
            throw ValueError(GetLang("未知的标签页操作。"))
        ; WM_APPCOMMAND 直接交给目标浏览器处理，无需 CDP 或切换前台焦点。
        SendMessage(0x319, hwnd, commands[operation] << 16, , hwnd, , , , 1000)
        return true
    }

    static CloseWindows(browser, scope, customPath, cancelled) {
        scope := StrReplace(StrReplace(scope, "页签", "标签页"), "分页", "标签页")
        static browsers := Map("chrome.exe", "Chrome", "msedge.exe", "Edge", "chromium.exe", "Chromium",
            "brave.exe", "Brave", "vivaldi.exe", "Vivaldi", "opera.exe", "Opera")
        customPath := Trim(customPath, ' "')
        if (browser == "自定义" ? customPath == "" : (browser != "Chrome" && browser != "Edge" && browser != "所有浏览器"))
            return
        if (scope != "所有标签页" && scope != "非当前标签页" && scope != "当前标签页")
            return

        for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1") {
            if (cancelled())
                break
            try {
                if (DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")) ; GW_OWNER
                    continue
                name := browsers.Get(StrLower(WinGetProcessName(hwnd)), "")
                if (browser == "自定义" ? WinGetProcessPath(hwnd) != customPath
                    : (name == "" || (browser != "所有浏览器" && name != browser)))
                    continue
                this._CloseWindow(hwnd, scope, cancelled)
            }
        }
    }

    static _CloseWindow(hwnd, scope, cancelled) {
        if (scope == "所有标签页") {
            WinClose(hwnd)
            return
        }
        automation := WindowControl._Automation()
        root := WindowControl._Object(6, automation, "Ptr", hwnd)
        walker := WindowControl._Object(14, automation)
        tabs := []
        this._CollectWindowTabs(root, walker, tabs)
        current := 0
        for index, tab in tabs {
            if (WindowControl._Int(tab.selection, 6)) { ; get_CurrentIsSelected
                current := index
                break
            }
        }
        if (!current)
            return

        restore := false
        try {
            for index, tab in tabs {
                if (cancelled())
                    break
                if ((index == current) != (scope == "当前标签页"))
                    continue
                try {
                    if (this._InvokeTabClose(tab.element, walker))
                        continue
                    ; 紧凑标签页可能只在选中时提供关闭按钮。
                    if (index != current) {
                        restore := true
                        ComCall(3, tab.selection) ; Select
                    }
                    if (!cancelled() && WindowControl._Int(tab.selection, 6)
                        && (index == current || !this._InvokeTabClose(tab.element, walker))
                        && !this._MiddleClickTab(hwnd, tab, cancelled))
                        break
                }
            }
        } finally {
            if (restore)
                try ComCall(3, tabs[current].selection)
        }
    }

    static _CollectWindowTabs(element, walker, tabs) {
        if (!element)
            return
        type := WindowControl._Int(element, 21)
        if (type == 50030) ; 跳过网页文档
            return
        if (type == 50019 && RegExMatch(WindowControl._String(element, 30), "^(?:Edge)?Tab$")) {
            selection := WindowControl._Pattern(element, "selection")
            if (selection)
                tabs.Push({element: element, selection: selection})
            return
        }
        child := WindowControl._Object(4, walker, "Ptr", element)
        while (child) {
            this._CollectWindowTabs(child, walker, tabs)
            child := WindowControl._Object(6, walker, "Ptr", child)
        }
    }

    static _InvokeTabClose(tab, walker) {
        child := WindowControl._Object(4, walker, "Ptr", tab)
        while (child) {
            if (RegExMatch(WindowControl._String(child, 30), "^(?:Edge)?TabCloseButton$")) {
                invoke := WindowControl._Pattern(child, "invoke")
                if (invoke) {
                    ComCall(3, invoke)
                    return true
                }
            }
            child := WindowControl._Object(6, walker, "Ptr", child)
        }
        return false
    }

    static _MiddleClickTab(hwnd, tab, cancelled) {
        ; 固定标签页可能没有关闭按钮，中键只发送到当前匹配窗口的标签页位置。
        if (WindowControl._Int(tab.element, 38)) ; get_CurrentIsOffscreen
            return false
        rect := Buffer(16)
        ComCall(43, tab.element, "Ptr", rect)
        left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
        if (right <= left || bottom <= top)
            return false
        point := Buffer(8)
        NumPut("Int", (left + right) // 2, "Int", (top + bottom) // 2, point)
        if (!DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", point))
            return false
        ControlClick("x" NumGet(point, 0, "Int") " y" NumGet(point, 4, "Int"), hwnd, , "Middle", 1, "NA Pos")
        ; 等浏览器处理这次点击，再继续切换或关闭其他标签页。
        loop 10 {
            if (cancelled())
                break
            try {
                if (!WindowControl._Int(tab.selection, 6))
                    return true
            } catch {
                return true
            }
            Sleep(25)
        }
        return false
    }
}

; 宏指令执行分发函数

#Include BrowserCommand.ahk
