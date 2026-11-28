#Requires AutoHotkey v2.0
#Include BrowserPageInfo.ahk
#Include BrowserElementInfo.ahk

OnBrowser(tableItem, cmd, index) {
    parts := StrSplit(cmd, "_")
    data := GetMacroCMDData(parts[1])
    item := tableItem.Items[index]
    if (item.Killed)
        return

    resolve := (text) => GetReplaceVarText(tableItem, index, text)

    actionType := BrowserActions.Action(data.ActionType)
    selType := data.SelectorType
    usesTimeout := BrowserActions.UsesTimeout(actionType)
    timeoutAction := usesTimeout ? data.TimeoutAction : "停止"
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
            retry := usesTimeout && (err is BrowserTimeoutError) && TimeoutPolicy.CanRetry(timeoutAction, A_Index)
            if (!retry)
                break
            if (!TimeoutPolicy.WaitBeforeRetry(() => item.Killed))
                return
        }
    }

    elapsed := A_TickCount - startTime

    ; 保存结果变量与元数据 (res, res_Success, res_Error, res_ElapsedMs)
    if (actionType == "标签页信息" && success && !item.Killed) {
        for field, name in BrowserPageInfo.OutputVariables(data)
            if (name != "")
                MySetGlobalVariable([name], [val[field]], false)
    }
    if (BrowserElementInfo.IsRead(actionType) && success && !item.Killed) {
        for label, name in BrowserElementInfo.Outputs(actionType)
            if (data.%name% != "")
                MySetGlobalVariable([data.%name%], [val[name]], false)
    }
    if (data.SaveVar != "" && !item.Killed && !BrowserElementInfo.IsRead(actionType) && actionType != "标签页信息") {
        saveVar := data.SaveVar
        MySetGlobalVariable([saveVar], [val], false)
        MySetGlobalVariable([saveVar "_Success"], [success ? "1" : "0"], false)
        MySetGlobalVariable([saveVar "_Error"], [success ? "" : lastErrMsg], false)
        MySetGlobalVariable([saveVar "_ElapsedMs"], [String(elapsed)], false)
    }

    timedOut := !success && (lastError is BrowserTimeoutError)
    if (!item.Killed && usesTimeout)
        TimeoutPolicy.WriteStatus(data, timedOut)
    stop := !timedOut || !usesTimeout || TimeoutPolicy.Stops(timeoutAction)
    if (!success && !item.Killed && stop)
        throw Error("浏览器操作失败 [" actionType "]: " lastErrMsg)
}

BrowserTargetRef(tableItem, index, data, resolve) => resolve(Trim(data.TargetRef))

BrowserMatchingIds(targets, mode, value, currentId := "") {
    if (mode != "当前标签页" && value == "")
        throw ValueError(GetLang("请填写标签页匹配值。"))
    if (BrowserPageInfo.IsRegex(mode))
        RegExMatch("", value)
    matches := []
    for target in targets {
        id := target.Has("targetId") ? target["targetId"] : target["id"]
        matched := false
        switch mode {
            case "当前标签页": matched := id == currentId
            case "标签页ID": matched := StrCompare(id, value, true) == 0
            case "网址": matched := StrCompare(target["url"], value, true) == 0
            case "标题": matched := StrCompare(target["title"], value, true) == 0
            case "正则表达式-网址": matched := RegExMatch(target["url"], value) != 0
            case "正则表达式-标题": matched := RegExMatch(target["title"], value) != 0
        }
        if (matched)
            matches.Push(id)
    }
    return matches
}

BrowserMatchedTarget(tableItem, index, data, resolve) {
    mode := BrowserActions.MatchMode(data.TabMatchMode, data.ActionType)
    if (mode == "元素匹配") {
        matches := BrowserElementInfo.MatchTabs(resolve(data.Selector), BrowserActions._Choice(data.SelectorType, ["CSS", "XPath"]), () => tableItem.Items[index].Killed)
        if (matches.Length != 1)
            throw TargetError(GetLang(matches.Length ? "匹配到多个标签页，请缩小匹配范围。" : "未找到匹配的标签页。"))
        return matches[1]
    }
    raw := data.TargetRef
    value := Trim(BrowserPageInfo.IsRegex(mode) ? BrowserResolveRegex(raw, resolve) : resolve(raw))
    matches := BrowserMatchingIds(JSON.parse(BrowserUtil.GetTabs()), mode, value)
    if (matches.Length != 1)
        throw TargetError(GetLang(matches.Length ? "匹配到多个标签页，请缩小匹配范围。" : "未找到匹配的标签页。"))
    return matches[1]
}

BrowserCloseTargets(targets, matches, inverse := false) {
    if (!matches.Length)
        throw TargetError(GetLang("未找到匹配的标签页。"))
    selected := Map(), result := []
    for id in matches
        selected[id] := true
    for target in targets {
        id := target.Has("targetId") ? target["targetId"] : target["id"]
        if (inverse ? !selected.Has(id) : selected.Has(id))
            result.Push(id)
    }
    return result
}

BrowserResolveRegex(text, resolve) {
    ; {2}、{1,3} 是正则量词，不能交给通用变量替换当作 {变量名} 处理。
    prefix := Chr(0xE000) "RMT_REGEX_"
    while (InStr(text, prefix))
        prefix .= "_"
    protected := "", quantifiers := [], position := 1
    while (found := RegExMatch(text, "\{\d+(?:,\d*)?\}", &match, position)) {
        quantifiers.Push(match[0])
        protected .= SubStr(text, position, found - position) prefix quantifiers.Length Chr(0xE001)
        position := found + match.Len
    }
    protected .= SubStr(text, position)
    result := resolve(protected)
    for index, quantifier in quantifiers
        result := StrReplace(result, prefix index Chr(0xE001), quantifier)
    return result
}

_ExecuteBrowserAction(tableItem, index, data, actionType, resolve, selType) {
    actionType := BrowserActions.Action(actionType)
    if (actionType == "当前标签页")
        return BrowserUtil.CurrentTabAction(BrowserActions._Choice(data.CurrentTabAction, BrowserActions.CurrentTabActions), () => tableItem.Items[index].Killed, data.BrowserPort)
    if (actionType == "关闭标签页" && BrowserActions.ClosesCurrentTabOnly(data.TabMatchMode, data.TabCloseMode))
        return BrowserUtil.CurrentTabAction("关闭", () => tableItem.Items[index].Killed)
    if (BrowserActions.UsesTimeout(actionType)) {
        data := data.Clone()
        data.TimeoutMs := TimeoutPolicy.ResolveMs(data.TimeoutMs, resolve, 2147483647)
    }
    if (actionType != "打开网址" && actionType != "标签页信息")
        BrowserUtil.EnsureConnection(data.BrowserPort)
    if (BrowserActions.UsesTarget(actionType)) {
        targetRef := BrowserTargetRef(tableItem, index, data, resolve)
        if (targetRef != "")
            BrowserUtil.SwitchTab(targetRef)
    }

    switch actionType {
        case "元素信息", "元素位置/宽高":
            return BrowserElementInfo.ReadMatched(data, resolve(data.Selector), selType, () => tableItem.Items[index].Killed)
        case "标签页信息":
            source := BrowserPageInfo.NormalizeSource(data.PageSource)
            fields := []
            for field, name in BrowserPageInfo.OutputVariables(data)
                if (name != "")
                    fields.Push(field)
            if (!fields.Length)
                throw ValueError(GetLang("请至少填写一个信息变量。"))
            if (source == "元素匹配")
                return BrowserElementInfo.ReadPageFields(resolve(data.Selector), selType, fields, data.BrowserPort, () => tableItem.Items[index].Killed)
            url := !BrowserPageInfo.UsesMatchValue(source) ? "" : BrowserPageInfo.IsRegex(source) ? BrowserResolveRegex(data.Url, resolve) : resolve(data.Url)
            return BrowserPageInfo.ReadFields(source, fields, url,
                data.BrowserPort, () => tableItem.Items[index].Killed)

        case "打开网址":
            url := resolve(data.Url)
            if (url == "")
                throw Error("URL 不能为空")
            bType := data.BrowserType
            bPath := bType == "自定义路径" ? resolve(data.BrowserPath) : ""
            uDir := resolve(data.UserDataDir)
            hPort := Integer(data.BrowserPort)
            hLess := Integer(data.Headless)
            timeoutMs := Integer(data.TimeoutMs)

            mode := BrowserActions.GetOpenMode(data)
            BrowserUtil.OpenUrl(url, bType, bPath, mode == "无痕模式", hLess, uDir, hPort, timeoutMs, mode == "新窗口", data.UseCDP)
            return url

        case "切换标签页":
            targetRef := BrowserMatchedTarget(tableItem, index, data, resolve)
            BrowserUtil.SwitchTab(targetRef)
            return targetRef

        case "关闭标签页":
            mode := BrowserActions.MatchMode(data.TabMatchMode, data.ActionType)
            raw := data.TargetRef
            value := (mode == "元素匹配" || mode == "当前标签页") ? "" : Trim(BrowserPageInfo.IsRegex(mode) ? BrowserResolveRegex(raw, resolve) : resolve(raw))
            currentId := mode == "当前标签页" ? BrowserPageInfo.Read("当前标签页", "标签页ID", "", data.BrowserPort, () => tableItem.Items[index].Killed) : ""
            targets := JSON.parse(BrowserUtil.GetTabs())
            matches := mode == "元素匹配" ? BrowserElementInfo.MatchTabs(resolve(data.Selector), selType, () => tableItem.Items[index].Killed, targets)
                : BrowserMatchingIds(targets, mode, value, currentId)
            ids := BrowserCloseTargets(targets, matches, BrowserActions.TabCloseMode(data.TabCloseMode) == "非匹配标签页")
            for id in ids {
                if (tableItem.Items[index].Killed)
                    return false
                BrowserUtil.CloseTabByRef(id)
            }
            return true

        case "获取标签页列表":
            return BrowserUtil.GetTabs()

        case "等待元素":
            selector := resolve(data.Selector)
            if (selector == "")
                throw Error("Selector 不能为空")
            condZh := data.Condition
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
            stateZh := data.LoadState
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
            chk := Integer(data.Checked)
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
            btn := data.MouseBtn
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
            mod := Integer(data.Modifiers)
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
                cDom := resolve(data.CookieDomain)
                cPath := resolve(data.CookiePath)
                BrowserUtil.SetCookie(cName, cVal, cDom, cPath)
                return true
            } else {
                return BrowserUtil.GetCookie(cName)
            }

        case "Storage操作":
            opt := resolve(data.Text) ; "get" / "set"
            sType := data.StorageType
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
            fullPage := Integer(data.FullPage)
            BrowserUtil.CaptureScreenshot(path, fullPage)
            return path

        default:
            throw ValueError(GetLang("不支持的浏览器操作：") actionType)
    }
}
