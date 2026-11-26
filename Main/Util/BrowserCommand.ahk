#Requires AutoHotkey v2.0
#Include BrowserPageInfo.ahk

OnBrowser(tableItem, cmd, index) {
    parts := StrSplit(cmd, "_")
    data := GetMacroCMDData(parts[1])
    item := tableItem.Items[index]
    if (item.Killed)
        return

    resolve := (text) => GetReplaceVarText(tableItem, index, text)

    actionType := CmdEnumZh(data.ActionType, BrowserActions.Names)
    if (BrowserActions.IsCloseAction(actionType)) {
        if (actionType == "关闭浏览器") {
            try BrowserUtil.CloseBrowser() ; 保留旧宏关闭受控会话的行为
        } else {
            browser := BrowserActions.GetCloseBrowserType(data.HasOwnProp("BrowserType") ? data.BrowserType : "Chrome")
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
    usesTimeout := BrowserActions.UsesTimeout(actionType)
    legacy := !data.HasOwnProp("TimeoutStatusVar")
    timeoutAction := usesTimeout || legacy ? TimeoutPolicy.Get(data) : ""
    attempts := 1
    if (timeoutAction == "" && (usesTimeout || legacy) && onError == "重试")
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

    timedOut := !success && (lastError is BrowserTimeoutError)
    if (!item.Killed && usesTimeout)
        TimeoutPolicy.WriteStatus(data, timedOut)
    stop := timeoutAction == "" ? (!(usesTimeout || legacy) || onError == "停止")
        : (!timedOut || TimeoutPolicy.Stops(timeoutAction))
    if (!success && !item.Killed && stop)
        throw Error("浏览器操作失败 [" actionType "]: " lastErrMsg)
}

BrowserTargetRef(tableItem, index, data, resolve) {
    raw := data.HasOwnProp("TargetRef") ? Trim(data.TargetRef) : ""
    if (raw != "" && !InStr(raw, "{") && TryGetTabVarValue(&value, tableItem, index, raw, true))
        return value
    return resolve(raw)
}

_ExecuteBrowserAction(tableItem, index, data, actionType, resolve, selType) {
    if (BrowserActions.UsesTimeout(actionType)) {
        data := data.Clone()
        data.TimeoutMs := TimeoutPolicy.ResolveMs(data.TimeoutMs, resolve, 2147483647)
    }
    if (actionType != "打开网址" && actionType != "页签信息")
        BrowserUtil.EnsureConnection(InputField(data, "BrowserPort", 9222))
    if (BrowserActions.UsesTarget(actionType)) {
        targetRef := BrowserTargetRef(tableItem, index, data, resolve)
        if (targetRef != "")
            BrowserUtil.SwitchTab(targetRef)
    }

    switch actionType {
        case "页签信息":
            source := CmdEnumZh(InputField(data, "PageSource", "当前页签"), BrowserPageInfo.Sources)
            field := CmdEnumZh(InputField(data, "PageField", "网址"), BrowserPageInfo.Fields)
            binding := source == "窗口绑定" ? resolve(ResolveBindWindow(tableItem, index, InputField(data, "WinInfo", ""))) : ""
            return BrowserPageInfo.Read(source, field, source == "目标网址" ? resolve(data.Url) : "", binding,
                InputField(data, "BrowserPort", 9222), () => tableItem.Items[index].Killed)

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

            mode := BrowserActions.GetOpenMode(data)
            BrowserUtil.OpenUrl(url, bType, bPath, mode == "无痕模式", hLess, uDir, hPort, timeoutMs, mode == "新窗口", InputField(data, "UseCDP", false))
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
            targetRef := BrowserTargetRef(tableItem, index, data, resolve)
            if (targetRef == "")
                targetRef := "1"
            BrowserUtil.SwitchTab(targetRef)
            return targetRef

        case "关闭分页", "关闭标签":
            targetRef := BrowserTargetRef(tableItem, index, data, resolve)
            BrowserUtil.CloseTabByRef(targetRef)
            return true

        case "获取分页列表":
            return BrowserUtil.GetTabs()

        case "获取当前分页ID":
            return BrowserUtil.GetActiveTabId()

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
            keyStr := resolve(data.Text)
            if (keyStr == "")
                throw Error("按键不能为空")
            mod := data.HasOwnProp("Modifiers") ? Integer(data.Modifiers) : 0
            for singleKey in StrSplit(keyStr, ["⎖", ","]) {
                singleKey := Trim(singleKey)
                if (singleKey != "")
                    BrowserUtil.KeyPress(singleKey, mod)
            }
            return keyStr

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
            )" "(" args ")", Integer(data.TimeoutMs))
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
