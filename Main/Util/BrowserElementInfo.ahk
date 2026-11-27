#Requires AutoHotkey v2.0

class BrowserElementInfo {
    static InfoOutputs := Map("元素变量", "ElementRefVar", "存在变量", "ElementExistsVar", "元素值变量", "ElementValueVar", "标签页ID", "ElementTabIdVar", "元素状态", "ElementStateVar", "HTML变量", "ElementHtmlVar")
    static PositionOutputs := Map("视口X变量", "ElementXVar", "视口Y变量", "ElementYVar", "页面X变量", "ElementPageXVar", "页面Y变量", "ElementPageYVar", "宽度变量", "ElementWidthVar", "高度变量", "ElementHeightVar")
    static IsRead(action) => action == "元素信息" || action == "元素位置/宽高"
    static Outputs(action) => action == "元素信息" ? this.InfoOutputs : this.PositionOutputs

    static SelectedTabs() {
        selected := [], port := BrowserUtil.ConnectionPort()
        for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1") {
            if (!BrowserPageInfo.IsBrowser(hwnd) || !BrowserPageInfo.OwnsDebugPort(hwnd, port))
                continue
            try {
                for tab in BrowserPageInfo.Snapshot(hwnd).tabs
                    if (tab.selected)
                        selected.Push(tab.element)
            }
        }
        return selected
    }

    static RestoreTabs(previous, selected) {
        if (previous != "")
            try BrowserUtil.SwitchTab(previous)
        for element in selected
            try BrowserPageInfo.SelectTab(element)
    }

    static MatchTabs(selector, selectorType := "CSS", cancelled := "", targets := "") {
        if (Trim(selector) == "")
            throw ValueError(GetLang("元素选择器不能为空。"))
        BrowserPageInfo.CheckCancelled(cancelled)
        if (!IsObject(targets))
            targets := JSON.parse(BrowserUtil.GetTabs())
        previous := BrowserUtil.GetActiveTabId(), selected := this.SelectedTabs(), matches := []
        try {
            for target in targets {
                BrowserPageInfo.CheckCancelled(cancelled)
                id := target.Has("targetId") ? target["targetId"] : target["id"]
                BrowserUtil.SwitchTab(id)
                info := this.Read({ActionType:"元素信息", TimeoutMs:TimeoutPolicy.DefaultMs}, selector, selectorType)
                if (info["ElementExistsVar"])
                    matches.Push(id)
            }
            BrowserPageInfo.CheckCancelled(cancelled)
        } finally {
            this.RestoreTabs(previous, selected)
        }
        return matches
    }

    static ReadPageFields(selector, selectorType, fields, port := 9222, cancelled := "") {
        BrowserUtil.EnsureConnection(port)
        selected := this.SelectedTabs()
        matches := this.MatchTabs(selector, selectorType, cancelled)
        if (matches.Length != 1)
            throw TargetError(GetLang(matches.Length ? "匹配到多个标签页，请缩小匹配范围。" : "未找到匹配的标签页。"))
        previous := BrowserUtil.GetActiveTabId(), values := Map()
        try {
            BrowserUtil.SwitchTab(matches[1])
            for field in fields {
                BrowserPageInfo.CheckCancelled(cancelled)
                switch field {
                    case "标签页ID": values[field] := matches[1]
                    case "网址": values[field] := BrowserUtil.GetUrl()
                    case "标题": values[field] := BrowserUtil.GetTitle()
                    case "加载状态":
                        state := BrowserUtil.Evaluate("/^(?:chrome|edge)-error:/.test(document.documentURI) ? 'unreachable' : document.readyState")
                        states := Map("unreachable", "不可访问", "loading", "加载中", "interactive", "可交互", "complete", "加载完成")
                        if (!states.Has(state))
                            throw BrowserPageReadError(GetLang("无法读取网页加载状态。"))
                        values[field] := states[state]
                    default: throw ValueError(GetLang("未知的标签页信息类型。"))
                }
            }
        } finally {
            this.RestoreTabs(previous, selected)
        }
        return values
    }

    static ReadMatched(data, selector, selectorType, cancelled := "") {
        matches := this.MatchTabs(selector, selectorType, cancelled)
        if (matches.Length > 1)
            throw TargetError(GetLang("匹配到多个标签页，请缩小匹配范围。"))
        if (!matches.Length) {
            if (data.ActionType == "元素位置/宽高")
                throw TargetError(GetLang("未找到匹配的网页元素。"))
            return Map("ElementExistsVar", 0, "ElementRefVar", "", "ElementTabIdVar", "", "ElementStateVar", "不可见", "ElementHtmlVar", "", "ElementValueVar", "")
        }
        previous := BrowserUtil.GetActiveTabId(), selected := this.SelectedTabs()
        try {
            BrowserPageInfo.CheckCancelled(cancelled)
            BrowserUtil.SwitchTab(matches[1])
            return this.Read(data, selector, selectorType)
        } finally {
            this.RestoreTabs(previous, selected)
        }
    }

    static Read(data, selector, selectorType) {
        position := BrowserActions.Action(data.ActionType) == "元素位置/宽高"
        if (position)
            BrowserUtil.WaitElement(selector, selectorType, "appear", Integer(data.TimeoutMs))
        args := JSON.stringify([selector, selectorType, position, !position && InputField(data, "ElementValueVar", "") != "",
            !position && InputField(data, "ElementHtmlVar", "") != ""], 0)
        result := JSON.parse(BrowserUtil.EvaluateRead("
        (
            (([selector, type, position, readValue, readHtml]) => {
                let el;
                try {
                    el = type.toLowerCase() === 'xpath'
                        ? document.evaluate(selector, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue
                        : document.querySelector(selector);
                    if (el && el.nodeType !== Node.ELEMENT_NODE)
                        throw new Error('The selector must locate a webpage element.');
                } catch (error) {
                    return JSON.stringify({error: String(error.message)});
                }
                if (!el) return JSON.stringify({ElementExistsVar: 0, ElementRefVar: '', ElementStateVar: '不可见', ElementValueVar: '', ElementHtmlVar: ''});
                const style = getComputedStyle(el);
                const rects = el.getClientRects();
                const visible = style.visibility !== 'hidden' && style.visibility !== 'collapse'
                    && Array.from(rects).some(r => r.width > 0 && r.height > 0);
                const interactive = visible && !el.matches(':disabled') && !el.closest('[inert]')
                    && el.getAttribute('aria-disabled') !== 'true' && style.pointerEvents !== 'none';
                const result = {ElementExistsVar: 1, ElementRefVar: selector, ElementValueVar: '', ElementHtmlVar: readHtml ? el.outerHTML : '',
                    ElementStateVar: (interactive ? '可交互' : '不可交互') + '-' + (visible ? '可见' : '不可见')};
                if (readValue) {
                    if (el.type === 'checkbox' || el.type === 'radio')
                        result.ElementValueVar = el.checked ? 1 : 0;
                    else if (el.multiple && el.selectedOptions)
                        result.ElementValueVar = JSON.stringify(Array.from(el.selectedOptions, option => option.value));
                    else if (el.matches('input,textarea,select,output,progress,meter'))
                        result.ElementValueVar = String(el.value ?? '');
                    else
                        result.ElementValueVar = el.innerText ?? el.textContent ?? '';
                }
                if (position) {
                    const rect = el.getBoundingClientRect();
                    result.ElementXVar = rect.left + rect.width / 2;
                    result.ElementYVar = rect.top + rect.height / 2;
                    result.ElementPageXVar = result.ElementXVar + window.scrollX;
                    result.ElementPageYVar = result.ElementYVar + window.scrollY;
                    result.ElementWidthVar = rect.width;
                    result.ElementHeightVar = rect.height;
                }
                return JSON.stringify(result);
            })
        )" "(" args ")", Integer(data.TimeoutMs)))
        if (!(result is Map) || !result.Has("ElementExistsVar"))
            throw Error(result is Map && result.Has("error") ? result["error"] : GetLang("无法读取网页元素信息。"))
        if (position && !result["ElementExistsVar"])
            throw TargetError(GetLang("未找到匹配的网页元素。"))
        result["ElementTabIdVar"] := result["ElementExistsVar"] ? BrowserUtil.GetActiveTabId() : ""
        return result
    }
}
