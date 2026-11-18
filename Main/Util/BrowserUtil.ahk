#Requires AutoHotkey v2.0
#Include TimeoutPolicy.ahk

class BrowserTimeoutError extends Error {
}

; ==============================================================================
; 浏览器操作底层工具 (CDP / RMT_Browser.dll)
; ==============================================================================

class BrowserUtil {
    static Actions := [
        "打开网址", "新建分页", "切换分页", "关闭分页", "获取分页列表",
        "等待元素", "等待文字", "等待加载",
        "点击", "双击", "右键", "输入", "清空", "选择下拉", "勾选", "滚动至元素", "悬停", "元素数量", "元素状态",
        "鼠标移动", "鼠标点击", "鼠标滚轮", "按键输入",
        "Cookie操作", "Storage操作",
        "执行JS", "提取文本", "提取属性", "提取HTML", "获取网址", "获取标题", "网页截图",
        "刷新", "后退", "前进", "关闭标签", "关闭浏览器", "当前页跳转", "提取控件值", "关闭"
    ]
    static CloseBrowserTypes := ["Chrome", "Edge", "所有浏览器", "自定义"]
    static CloseScopes := ["所有页签", "非当前页签", "当前页签"]

    static IsCloseAction(action) => action == "关闭" || action == "关闭浏览器"

    static GetCloseBrowserType(value) {
        name := GetLangKey(value)
        return name == "自定义路径" ? "自定义" : name
    }

    static _hDll := 0
    static _dllPath := ""

    static InitDll() {
        if (this._hDll)
            return true
        dllName := "RMT_Browser.dll"
        paths := [
            A_WorkingDir "\Plugins\Browser\" dllName,
            A_WorkingDir "\..\Plugins\Browser\" dllName,
            A_ScriptDir "\Plugins\Browser\" dllName,
            A_ScriptDir "\..\Plugins\Browser\" dllName,
            A_WorkingDir "\ReleaseX64\Plugins\Browser\" dllName,
            A_WorkingDir "\..\ReleaseX64\Plugins\Browser\" dllName
        ]
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

        return list
    }

    static Launch(browserType := "Chrome", browserPath := "", headless := 0, userDataDir := "", port := 9222) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Launch", "Ptr", this._Utf8(browserType), "Ptr", this._Utf8(browserPath), "Int", headless, "Ptr", this._Utf8(userDataDir), "Int", port, "Cdecl Int")
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

    ; --- 分页管理 ---

    static GetTabs() {
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

    static NewTab(url := "about:blank") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(256, 0)
        res := DllCall("RMT_Browser\Browser_NewTab", "Ptr", this._Utf8(url), "Ptr", buf.Ptr, "Int", 256, "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return StrGet(buf.Ptr, "UTF-8")
    }

    static CloseTabByRef(targetRef := "") {
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
                function click(event) {
                    if (event.button !== 0) return;
                    suppress(event);
                    const target = targetFor(event.target);
                    if (target) finish('picked:' + selectorFor(target));
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
                    stop() {
                        finish('cancelled');
                        delete window[token];
                        if (window.__rmtActivePicker === picker) delete window.__rmtActivePicker;
                    }
                };
                const listeners = {pointermove: hover, pointerout: leave, blur: leave,
                    pointerdown: suppress, pointerup: suppress, click, keydown: escape};
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
        res := DllCall("RMT_Browser\Browser_CloseBrowser", "Cdecl Int")
        if (res != 0)
            this._ThrowLastError()
        return true
    }

    static CloseWindows(browser, scope, customPath, cancelled) {
        static browsers := Map("chrome.exe", "Chrome", "msedge.exe", "Edge", "chromium.exe", "Chromium",
            "brave.exe", "Brave", "vivaldi.exe", "Vivaldi", "opera.exe", "Opera")
        customPath := Trim(customPath, ' "')
        if (browser == "自定义" ? customPath == "" : (browser != "Chrome" && browser != "Edge" && browser != "所有浏览器"))
            return
        if (scope != "所有页签" && scope != "非当前页签" && scope != "当前页签")
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
        if (scope == "所有页签") {
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
                if ((index == current) != (scope == "当前页签"))
                    continue
                try {
                    if (this._InvokeTabClose(tab.element, walker))
                        continue
                    ; 紧凑页签可能只在选中时提供关闭按钮。
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
        ; 固定页签可能没有关闭按钮，中键只发送到当前匹配窗口的页签位置。
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
        ; 等浏览器处理这次点击，再继续切换或关闭其他页签。
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
OnBrowser(tableItem, cmd, index) {
    parts := StrSplit(cmd, "_")
    data := GetMacroCMDData(parts[1])
    item := tableItem.Items[index]
    if (item.Killed)
        return

    resolve := (text) => GetReplaceVarText(tableItem, index, text)

    actionType := CmdEnumZh(data.ActionType, BrowserUtil.Actions)
    if (BrowserUtil.IsCloseAction(actionType)) {
        if (actionType == "关闭浏览器") {
            try BrowserUtil.CloseBrowser() ; 保留旧宏关闭受控会话的行为
        } else {
            browser := BrowserUtil.GetCloseBrowserType(data.HasOwnProp("BrowserType") ? data.BrowserType : "Chrome")
            scope := data.HasOwnProp("CloseScope") ? GetLangKey(data.CloseScope) : "所有页签"
            path := ""
            try {
                if (browser == "自定义" && data.HasOwnProp("BrowserPath"))
                    path := resolve(data.BrowserPath)
                BrowserUtil.CloseWindows(browser, scope, path, () => item.Killed)
            }
        }
        return
    }

    selType := data.HasOwnProp("SelectorType") ? data.SelectorType : "CSS"
    onError := data.HasOwnProp("OnError") ? data.OnError : "停止"
    timeoutAction := TimeoutPolicy.Get(data)
    attempts := 1
    if (timeoutAction == "" && onError == "重试")
        attempts := data.HasOwnProp("RetryCount") ? Max(1, Integer(data.RetryCount)) : 3

    startTime := A_TickCount
    success := false
    lastErrMsg := ""
    val := ""

    lastError := ""
    loop {
        if (item.Killed)
            return
        try {
            val := _ExecuteBrowserAction(tableItem, index, data, actionType, resolve, selType)
            success := true
            break
        } catch as err {
            lastError := err
            lastErrMsg := err.Message
            retry := timeoutAction == "" ? A_Index < attempts
                : (err is BrowserTimeoutError) && TimeoutPolicy.CanRetry(timeoutAction, A_Index)
            if (!retry)
                break
            if (!TimeoutPolicy.WaitBeforeRetry(() => item.Killed))
                return
        }
    }

    elapsed := A_TickCount - startTime

    ; 保存结果变量与元数据 (res, res_Success, res_Error, res_ElapsedMs)
    if (data.SaveVar != "" && !item.Killed) {
        saveVar := data.SaveVar
        MySetGlobalVariable([saveVar], [val], false)
        MySetGlobalVariable([saveVar "_Success"], [success ? "1" : "0"], false)
        MySetGlobalVariable([saveVar "_Error"], [success ? "" : lastErrMsg], false)
        MySetGlobalVariable([saveVar "_ElapsedMs"], [String(elapsed)], false)
    }

    stop := timeoutAction == "" ? onError == "停止"
        : !(lastError is BrowserTimeoutError && timeoutAction == "忽略")
    if (!success && !item.Killed && stop)
        throw Error("浏览器操作失败 [" actionType "]: " lastErrMsg)
}

_ExecuteBrowserAction(tableItem, index, data, actionType, resolve, selType) {
    switch actionType {
        case "打开网址":
            url := resolve(data.Url)
            if (url == "")
                throw Error("URL 不能为空")
            bType := data.HasOwnProp("BrowserType") ? data.BrowserType : "Chrome"
            bPath := data.HasOwnProp("BrowserPath") ? resolve(data.BrowserPath) : ""
            uDir := data.HasOwnProp("UserDataDir") ? resolve(data.UserDataDir) : ""
            hPort := data.HasOwnProp("BrowserPort") ? Integer(data.BrowserPort) : 9222
            hLess := data.HasOwnProp("Headless") ? Integer(data.Headless) : 0
            timeoutMs := Integer(data.TimeoutMs)

            BrowserUtil.Launch(bType, bPath, hLess, uDir, hPort)
            BrowserUtil.Navigate(url, timeoutMs)
            return url

        case "当前页跳转":
            url := resolve(data.Url)
            if (url == "")
                throw Error("URL 不能为空")
            BrowserUtil.Navigate(url, Integer(data.TimeoutMs))
            return url

        case "新建分页":
            url := resolve(data.Url)
            if (url == "")
                url := "about:blank"
            return BrowserUtil.NewTab(url)

        case "切换分页":
            targetRef := data.HasOwnProp("TargetRef") ? resolve(data.TargetRef) : "1"
            if (targetRef == "")
                targetRef := "1"
            BrowserUtil.SwitchTab(targetRef)
            return targetRef

        case "关闭分页", "关闭标签":
            targetRef := data.HasOwnProp("TargetRef") ? resolve(data.TargetRef) : ""
            BrowserUtil.CloseTabByRef(targetRef)
            return true

        case "获取分页列表":
            return BrowserUtil.GetTabs()

        case "等待元素":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            condZh := data.HasOwnProp("Condition") ? data.Condition : "出现"
            condMap := Map("出现", "appear", "消失", "disappear", "可见", "visible")
            cond := condMap.Has(condZh) ? condMap[condZh] : "appear"
            BrowserUtil.WaitElement(selector, selType, cond, Integer(data.TimeoutMs))
            return true

        case "等待文字":
            selector := resolve(data.Selector)
            txt := resolve(data.Text)
            BrowserUtil.WaitText(selector, selType, txt, Integer(data.TimeoutMs))
            return true

        case "等待加载":
            stateZh := data.HasOwnProp("LoadState") ? data.LoadState : "完全加载"
            stateMap := Map("完全加载", "load", "DOM加载", "domcontentloaded", "网络空闲", "networkidle")
            state := stateMap.Has(stateZh) ? stateMap[stateZh] : "load"
            BrowserUtil.WaitPageLoad(state, Integer(data.TimeoutMs))
            return true

        case "点击":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            BrowserUtil.Click(selector, selType, Integer(data.TimeoutMs))
            return true

        case "双击":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            BrowserUtil.DoubleClick(selector, selType, Integer(data.TimeoutMs))
            return true

        case "右键":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            BrowserUtil.RightClick(selector, selType, Integer(data.TimeoutMs))
            return true

        case "输入":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            text := resolve(data.Text)
            BrowserUtil.Type(selector, selType, text, data.ClearBefore, Integer(data.TimeoutMs))
            return text

        case "清空":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            BrowserUtil.Clear(selector, selType, Integer(data.TimeoutMs))
            return true

        case "选择下拉":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            val := resolve(data.Text)
            BrowserUtil.Select(selector, selType, val, Integer(data.TimeoutMs))
            return val

        case "勾选":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            chk := data.HasOwnProp("Checked") ? Integer(data.Checked) : 1
            BrowserUtil.Check(selector, selType, chk, Integer(data.TimeoutMs))
            return chk

        case "滚动至元素":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            BrowserUtil.ScrollTo(selector, selType, Integer(data.TimeoutMs))
            return true

        case "悬停":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            BrowserUtil.Hover(selector, selType, Integer(data.TimeoutMs))
            return true

        case "元素数量":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            cnt := BrowserUtil.GetElementCount(selector, selType)
            return cnt

        case "元素状态":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            return BrowserUtil.GetElementState(selector, selType)

        case "鼠标移动":
            x := Float(resolve(data.CoordX))
            y := Float(resolve(data.CoordY))
            BrowserUtil.MouseMove(x, y)
            return true

        case "鼠标点击":
            x := Float(resolve(data.CoordX))
            y := Float(resolve(data.CoordY))
            btn := data.HasOwnProp("MouseBtn") ? data.MouseBtn : "左键"
            btnEn := (btn == "右键") ? "right" : ((btn == "中键") ? "middle" : "left")
            BrowserUtil.MouseClick(x, y, btnEn)
            return true

        case "鼠标滚轮":
            dx := Float(resolve(data.CoordX))
            dy := Float(resolve(data.CoordY))
            BrowserUtil.MouseWheel(dx, dy)
            return true

        case "按键输入":
            key := resolve(data.Text)
            if (key == "")
                throw Error("按键不能为空")
            mod := data.HasOwnProp("Modifiers") ? Integer(data.Modifiers) : 0
            BrowserUtil.KeyPress(key, mod)
            return key

        case "Cookie操作":
            opt := resolve(data.Text) ; "get" / "set" / "clear"
            cName := resolve(data.AttrName)
            if (opt == "clear" || opt == "清空") {
                BrowserUtil.ClearCookies()
                return true
            } else if (opt == "set" || opt == "设置") {
                cVal := resolve(data.JsCode)
                cDom := data.HasOwnProp("CookieDomain") ? resolve(data.CookieDomain) : ""
                cPath := data.HasOwnProp("CookiePath") ? resolve(data.CookiePath) : "/"
                BrowserUtil.SetCookie(cName, cVal, cDom, cPath)
                return true
            } else {
                return BrowserUtil.GetCookie(cName)
            }

        case "Storage操作":
            opt := resolve(data.Text) ; "get" / "set"
            sType := data.HasOwnProp("StorageType") ? data.StorageType : "Local"
            sKey := resolve(data.AttrName)
            if (opt == "set" || opt == "设置") {
                sVal := resolve(data.JsCode)
                BrowserUtil.SetStorage(sType, sKey, sVal)
                return true
            } else {
                return BrowserUtil.GetStorage(sType, sKey)
            }

        case "执行JS":
            js := resolve(data.JsCode)
            if (js == "")
                throw Error("JS代码 不能为空")
            return BrowserUtil.Evaluate(js, Integer(data.TimeoutMs))

        case "提取文本":
            selector := resolve(data.Selector)
            return BrowserUtil.GetText(selector, selType, Integer(data.TimeoutMs))

        case "提取控件值":
            selector := resolve(data.Selector)
            BrowserUtil.WaitElement(selector, selType, "appear", Integer(data.TimeoutMs))
            args := JSON.stringify([selector, selType], 0)
            result := BrowserUtil.Evaluate("
            (
                (([selector, type]) => {
                    const el = type.toLowerCase() === 'xpath'
                        ? document.evaluate(selector, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue
                        : document.querySelector(selector);
                    if (!el || !('value' in el)) return 'missing';
                    if (el.type === 'checkbox' || el.type === 'radio') return el.checked ? 'value:1' : 'value:0';
                    if (el.multiple && el.selectedOptions)
                        return 'value:' + JSON.stringify(Array.from(el.selectedOptions, option => option.value));
                    return 'value:' + el.value;
                })
            )" "(" args ")")
            if (SubStr(result, 1, 6) != "value:")
                throw Error(GetLang("找不到可读取值的控件。"))
            return SubStr(result, 7)

        case "提取属性":
            selector := resolve(data.Selector)
            attr := resolve(data.AttrName)
            return BrowserUtil.GetAttribute(selector, selType, attr, Integer(data.TimeoutMs))

        case "提取HTML":
            selector := resolve(data.Selector)
            outer := data.HasOwnProp("OuterHtml") ? Integer(data.OuterHtml) : 1
            return BrowserUtil.GetHtml(selector, selType, outer, Integer(data.TimeoutMs))

        case "获取网址":
            return BrowserUtil.GetUrl()

        case "获取标题":
            return BrowserUtil.GetTitle()

        case "网页截图":
            path := resolve(data.Text)
            if (path == "") {
                ssDir := A_ScriptDir "\Images\ScreenShot"
                if (!DirExist(ssDir))
                    DirCreate(ssDir)
                path := ssDir "\Browser_" A_Now ".png"
            }
            fullPage := data.HasOwnProp("OuterHtml") ? Integer(data.OuterHtml) : 0
            BrowserUtil.CaptureScreenshot(path, fullPage)
            return path

        case "刷新":
            BrowserUtil.Reload(0)
            return true

        case "后退":
            BrowserUtil.GoBack()
            return true

        case "前进":
            BrowserUtil.GoForward()
            return true

    }
}
