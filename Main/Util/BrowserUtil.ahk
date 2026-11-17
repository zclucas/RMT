#Requires AutoHotkey v2.0

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
        res := DllCall("RMT_Browser\Browser_Launch", "AStr", browserType, "AStr", browserPath, "Int", headless, "AStr", userDataDir, "Int", port, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Connect(host := "127.0.0.1", port := 9222) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Connect", "AStr", host, "Int", port, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Navigate(url, timeoutMs := 30000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Navigate", "AStr", url, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Reload(ignoreCache := 0) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Reload", "Int", ignoreCache, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static GoBack() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_GoBack", "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static GoForward() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_GoForward", "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    ; --- 分页管理 ---

    static GetTabs() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetTabs", "Ptr", buf.Ptr, "Int", 65536, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static SwitchTab(targetRef) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_SwitchTab", "AStr", String(targetRef), "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static NewTab(url := "about:blank") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(256, 0)
        res := DllCall("RMT_Browser\Browser_NewTab", "AStr", url, "Ptr", buf.Ptr, "Int", 256, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static CloseTabByRef(targetRef := "") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CloseTabByRef", "AStr", String(targetRef), "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    ; --- 等待条件 ---

    static WaitElement(selector, selectorType := "CSS", condition := "appear", timeoutMs := 10000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_WaitElement", "AStr", selector, "AStr", selectorType, "AStr", condition, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static WaitText(selector, selectorType := "CSS", expectedText := "", timeoutMs := 10000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_WaitText", "AStr", selector, "AStr", selectorType, "AStr", expectedText, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static WaitPageLoad(loadState := "load", timeoutMs := 30000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_WaitPageLoad", "AStr", loadState, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    ; --- DOM 交互 ---

    static Click(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Click", "AStr", selector, "AStr", selectorType, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Type(selector, selectorType := "CSS", text := "", clearBefore := 1, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Type", "AStr", selector, "AStr", selectorType, "AStr", text, "Int", clearBefore, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Clear(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Clear", "AStr", selector, "AStr", selectorType, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Select(selector, selectorType := "CSS", value := "", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Select", "AStr", selector, "AStr", selectorType, "AStr", value, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Check(selector, selectorType := "CSS", checked := 1, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Check", "AStr", selector, "AStr", selectorType, "Int", checked, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static ScrollTo(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_ScrollTo", "AStr", selector, "AStr", selectorType, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static Hover(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_Hover", "AStr", selector, "AStr", selectorType, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static GetElementCount(selector, selectorType := "CSS") {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        count := 0
        res := DllCall("RMT_Browser\Browser_GetElementCount", "AStr", selector, "AStr", selectorType, "Int*", &count, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return count
    }

    ; --- 数据提取与 JS ---

    static Evaluate(script, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_Evaluate", "AStr", script, "Ptr", buf.Ptr, "Int", 65536, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetText(selector, selectorType := "CSS", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetText", "AStr", selector, "AStr", selectorType, "Ptr", buf.Ptr, "Int", 65536, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetAttribute(selector, selectorType := "CSS", attrName := "href", timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(65536, 0)
        res := DllCall("RMT_Browser\Browser_GetAttribute", "AStr", selector, "AStr", selectorType, "AStr", attrName, "Ptr", buf.Ptr, "Int", 65536, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetHtml(selector := "", selectorType := "CSS", outerHtml := 1, timeoutMs := 5000) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(131072, 0)
        res := DllCall("RMT_Browser\Browser_GetHtml", "AStr", selector, "AStr", selectorType, "Int", outerHtml, "Ptr", buf.Ptr, "Int", 131072, "Int", timeoutMs, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetUrl() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(4096, 0)
        res := DllCall("RMT_Browser\Browser_GetUrl", "Ptr", buf.Ptr, "Int", 4096, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static GetTitle() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        buf := Buffer(4096, 0)
        res := DllCall("RMT_Browser\Browser_GetTitle", "Ptr", buf.Ptr, "Int", 4096, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return StrGet(buf.Ptr, "UTF-8")
    }

    static CaptureScreenshot(filePath, fullPage := 0) {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CaptureScreenshot", "AStr", filePath, "Int", fullPage, "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static CloseTab() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CloseTab", "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
    }

    static CloseBrowser() {
        if (!this.InitDll())
            throw Error("RMT_Browser.dll 未找到或加载失败")
        res := DllCall("RMT_Browser\Browser_CloseBrowser", "Cdecl Int")
        if (res != 0)
            throw Error(this.GetLastError())
        return true
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

    actionType := CmdEnumZh(data.ActionType, [
        "打开网址", "新建分页", "切换分页", "关闭分页", "获取分页列表",
        "等待元素", "等待文字", "等待加载",
        "点击", "输入", "清空", "选择下拉", "勾选", "滚动至元素", "悬停", "元素数量",
        "执行JS", "提取文本", "提取属性", "提取HTML", "获取网址", "获取标题", "网页截图",
        "刷新", "后退", "前进", "关闭标签", "关闭浏览器"
    ])

    selType := data.HasOwnProp("SelectorType") ? data.SelectorType : "CSS"
    onError := data.HasOwnProp("OnError") ? data.OnError : "停止"
    retryCount := data.HasOwnProp("RetryCount") ? Integer(data.RetryCount) : 3
    if (retryCount < 1)
        retryCount := 1

    startTime := A_TickCount
    success := false
    lastErrMsg := ""
    val := ""

    runAction := () => (
        _ExecuteBrowserAction(tableItem, index, data, actionType, resolve, selType)
    )

    ; 失败重试循环
    loop retryCount {
        if (item.Killed)
            return
        try {
            val := runAction()
            success := true
            break
        } catch as err {
            lastErrMsg := err.Message
            if (A_Index < retryCount && onError == "重试")
                Sleep(500)
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

    if (!success) {
        if (onError == "停止") {
            throw Error("浏览器操作失败 [" actionType "]: " lastErrMsg)
        } else if (onError == "忽略") {
            return
        }
    }
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

        case "执行JS":
            js := resolve(data.JsCode)
            if (js == "")
                throw Error("JS代码 不能为空")
            return BrowserUtil.Evaluate(js, Integer(data.TimeoutMs))

        case "提取文本":
            selector := resolve(data.Selector)
            return BrowserUtil.GetText(selector, selType, Integer(data.TimeoutMs))

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

        case "关闭浏览器":
            BrowserUtil.CloseBrowser()
            return true
    }
}
