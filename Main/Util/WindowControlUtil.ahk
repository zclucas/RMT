#Requires AutoHotkey v2.0

class WindowControlData {
    SerialStr := ""
    ActionType := "点击控件"
    Selector := ""
    Argument := ""
    ResultVar := ""
    ErrorVar := ""
    TimeoutMs := 3000
}

class WindowControl {
    static Actions := ["点击控件", "聚焦控件", "写入控件值", "读取控件值", "读取控件文本", "读取控件信息",
        "选中控件", "加入选区", "移出选区", "切换勾选", "设置勾选", "展开控件", "折叠控件", "滚动到控件",
        "设置范围值", "读取范围值", "等待控件出现", "检测控件存在"]

    ; Automation ID is scoped to siblings. Fall back to name and class, then the occurrence in that group.
    static Describe(element) {
        return Map("type", this._Int(element, 21), "id", this._String(element, 29),
            "name", this._String(element, 23), "class", this._String(element, 30))
    }

    static FromPoint(x, y) {
        hit := this._HitTest(x, y)
        path := []
        node := hit.element
        while (node && !this._Equals(node, hit.root)) {
            key := this.Describe(node)
            key["index"] := 1
            sibling := this._Object(7, hit.walker, "Ptr", node)
            while (sibling) {
                if (this._Matches(sibling, key))
                    key["index"] += 1
                sibling := this._Object(7, hit.walker, "Ptr", sibling)
            }
            path.InsertAt(1, key)
            node := this._Object(3, hit.walker, "Ptr", node)
        }
        if (!node || !path.Length)
            throw Error(GetLang("没有找到可选取的窗口控件。"))
        return Map("exe", WinGetProcessName(hit.hwnd), "windowClass", WinGetClass(hit.hwnd),
            "titleContains", "", "path", path)
    }

    static _HitTest(x, y) {
        point := (y << 32) | (x & 0xFFFFFFFF)
        hwnd := DllCall("WindowFromPoint", "Int64", point, "Ptr")
        rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        automation := this._Automation()
        element := this._Object(7, automation, "Int64", point)
        if (!element || !rootHwnd)
            throw Error(GetLang("没有找到可选取的窗口控件。"))

        root := this._Object(6, automation, "Ptr", rootHwnd)
        walker := this._Object(14, automation)
        element := this._Object(8, walker, "Ptr", element)
        return {element: element, root: root, walker: walker, hwnd: rootHwnd}
    }

    static HoverBounds(x, y) {
        hit := this._HitTest(x, y)
        if (!hit.element || !hit.root || this._Equals(hit.element, hit.root))
            return 0
        target := this._Bounds(hit.element)
        window := this._Bounds(hit.root, hit.hwnd)
        ; 找到能容纳控件的最近父级，跳过没有布局范围的辅助节点。
        node := this._Object(3, hit.walker, "Ptr", hit.element)
        while (node && !this._Equals(node, hit.root)) {
            parent := this._Bounds(node)
            if (parent.left <= target.left && parent.top <= target.top
                && parent.right >= target.right && parent.bottom >= target.bottom
                && (parent.left < target.left || parent.top < target.top
                    || parent.right > target.right || parent.bottom > target.bottom))
                return {target: target, parent: parent, window: window}
            node := this._Object(3, hit.walker, "Ptr", node)
        }
        return node ? {target: target, parent: window, window: window} : 0
    }

    static _Bounds(element, hwnd := 0) {
        rect := Buffer(16)
        ; DWM 的可见边框不含窗口外围用于拖拽缩放的透明区域。
        if (!hwnd || DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", rect.Size, "Int"))
            ComCall(43, element, "Ptr", rect) ; get_CurrentBoundingRectangle
        return {left: NumGet(rect, 0, "Int"), top: NumGet(rect, 4, "Int"),
            right: NumGet(rect, 8, "Int"), bottom: NumGet(rect, 12, "Int")}
    }

    static ParseSelector(text) {
        try {
            selector := JSON.parse(text)
            if (!(selector is Map) || Type(selector.Get("exe", "")) != "String"
                || !RegExMatch(selector.Get("exe", ""), "i)^[^`r`n]+\.exe$")
                || Type(selector.Get("windowClass", 0)) != "String" || selector["windowClass"] == ""
                || Type(selector.Get("titleContains", "")) != "String"
                || !(selector.Get("path", "") is Array) || !selector["path"].Length)
                throw ValueError()
            for part in selector["path"] {
                if (!(part is Map) || !IsInteger(part.Get("type", "")) || !IsInteger(part.Get("index", ""))
                    || part["index"] < 1 || Type(part.Get("id", 0)) != "String"
                    || Type(part.Get("name", 0)) != "String" || Type(part.Get("class", 0)) != "String")
                    throw ValueError()
            }
            return selector
        } catch {
            throw Error(GetLang("控件选择器无效，请重新拾取。"))
        }
    }

    static Find(selector) {
        active := WinExist("A")
        matched := 0
        ambiguous := false
        title := selector.Get("titleContains", "")
        for hwnd in WinGetList() {
            try {
                if (WinGetProcessName(hwnd) != selector["exe"] || WinGetClass(hwnd) != selector["windowClass"]
                    || (title != "" && !InStr(WinGetTitle(hwnd), title)))
                    continue
                element := this._Object(6, this._Automation(), "Ptr", hwnd)
                if (element)
                    element := this._ResolvePath(element, selector["path"])
            } catch {
                continue
            }
            if (!element)
                continue
            if (hwnd == active)
                return element
            if (matched)
                ambiguous := true
            else
                matched := element
        }
        if (ambiguous)
            throw Error(GetLang("匹配到多个窗口，请在选择器中填写标题关键词。"))
        return matched
    }

    static Execute(data, arg, cancelled) {
        selector := this.ParseSelector(data.Selector)
        action := CmdEnumZh(data.ActionType, this.Actions)
        deadline := A_TickCount + Integer(data.TimeoutMs)
        while (!cancelled()) {
            element := this.Find(selector)
            if (element)
                break
            if (A_TickCount >= deadline) {
                if (action == "检测控件存在")
                    return 0
                throw Error(GetLang("等待控件超时。"))
            }
            Sleep(75)
        }
        if (cancelled())
            return ""

        switch action {
            case "等待控件出现", "检测控件存在":
                return 1
            case "点击控件":
                ComCall(3, this._RequiredPattern(element, "invoke"))
            case "聚焦控件":
                ComCall(3, element)
            case "写入控件值":
                ComCall(3, this._RequiredPattern(element, "value"), "WStr", arg)
            case "读取控件值":
                return this._String(this._RequiredPattern(element, "value"), 4)
            case "读取控件文本":
                text := this._Pattern(element, "text")
                if (text) {
                    range := this._Object(7, text)
                    return this._String(range, 12, "Int", -1)
                }
                value := this._Pattern(element, "value")
                return value ? this._String(value, 4) : this._String(element, 23)
            case "读取控件信息":
                info := this.Describe(element)
                info["enabled"] := this._Int(element, 28)
                info["offscreen"] := this._Int(element, 38)
                info["bounds"] := this._Bounds(element)
                return JSON.stringify(info, 0)
            case "选中控件", "加入选区", "移出选区":
                ComCall(Map("选中控件", 3, "加入选区", 4, "移出选区", 5)[action], this._RequiredPattern(element, "selection"))
            case "切换勾选", "设置勾选":
                toggle := this._RequiredPattern(element, "toggle")
                if (action == "切换勾选") {
                    ComCall(3, toggle)
                    return this._Int(toggle, 4)
                }
                if (arg != "0" && arg != "1")
                    throw Error(GetLang("勾选状态请输入 0 或 1。"))
                loop 2 {
                    if (this._Int(toggle, 4) == Integer(arg))
                        return Integer(arg)
                    ComCall(3, toggle)
                }
                if (this._Int(toggle, 4) != Integer(arg))
                    throw Error(GetLang("控件未达到指定状态。"))
                return Integer(arg)
            case "展开控件", "折叠控件":
                ComCall(action == "展开控件" ? 3 : 4, this._RequiredPattern(element, "expand"))
            case "滚动到控件":
                ComCall(3, this._RequiredPattern(element, "scroll"))
            case "设置范围值":
                if (!IsNumber(arg))
                    throw Error(GetLang("控件值必须是数字。"))
                ComCall(3, this._RequiredPattern(element, "range"), "Double", Number(arg))
            case "读取范围值":
                value := 0.0
                ComCall(4, this._RequiredPattern(element, "range"), "Double*", &value)
                return value
        }
        return 1
    }

    static UsesArgument(action) => action == "写入控件值" || action == "设置勾选" || action == "设置范围值"

    static _Automation() {
        static automation := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}", "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        return automation
    }

    static _Object(method, target, args*) {
        ptr := 0
        args.Push("Ptr*", &ptr)
        ComCall(method, target, args*)
        return ptr ? ComValue(13, ptr, 1) : 0
    }

    static _Int(target, method) {
        value := 0
        ComCall(method, target, "Int*", &value)
        return value
    }

    static _String(target, method, args*) {
        ptr := 0
        args.Push("Ptr*", &ptr)
        ComCall(method, target, args*)
        if (!ptr)
            return ""
        try return StrGet(ptr, "UTF-16")
        finally DllCall("oleaut32\SysFreeString", "Ptr", ptr)
    }

    static _Equals(left, right) {
        equal := 0
        ComCall(3, this._Automation(), "Ptr", left, "Ptr", right, "Int*", &equal)
        return equal
    }

    static _Matches(element, key) {
        if (this._Int(element, 21) != key["type"])
            return false
        if (key["id"] != "")
            return this._String(element, 29) == key["id"]
        return this._String(element, 23) == key["name"] && this._String(element, 30) == key["class"]
    }

    static _ResolvePath(element, path) {
        walker := this._Object(14, this._Automation())
        for key in path {
            child := this._Object(4, walker, "Ptr", element)
            seen := 0
            while (child) {
                if (this._Matches(child, key) && ++seen == key["index"])
                    break
                child := this._Object(6, walker, "Ptr", child)
            }
            if (!child)
                return 0
            element := child
        }
        return element
    }

    ; UIAutomationClient.h: GetCurrentPatternAs returns the requested typed interface.
    static _Pattern(element, name) {
        static patterns := Map(
            "invoke", [10000, "{FB377FBE-8EA6-46D5-9C73-6499642D3059}"],
            "value", [10002, "{A94CD8B1-0844-4CD6-9D2D-640537AB39E9}"],
            "range", [10003, "{59213F4F-7346-49E5-B120-80555987A148}"],
            "expand", [10005, "{619BE086-1F4E-4EE4-BAFA-210128738730}"],
            "selection", [10010, "{A8EFA66A-0FDA-421A-9194-38021F3578EA}"],
            "text", [10014, "{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}"],
            "toggle", [10015, "{94CF8058-9B8D-4AB9-8BFD-4CD0A33C8C70}"],
            "scroll", [10017, "{B488300F-D015-4F19-9C29-BB595E3645EF}"])
        pattern := patterns[name]
        iid := Buffer(16)
        DllCall("ole32\IIDFromString", "WStr", pattern[2], "Ptr", iid, "HRESULT")
        try return this._Object(14, element, "Int", pattern[1], "Ptr", iid)
        catch
            return 0
    }

    static _RequiredPattern(element, name) {
        pattern := this._Pattern(element, name)
        if (!pattern)
            throw Error(GetLang("此控件不支持所选操作。"))
        return pattern
    }
}

OnWindowControl(tableItem, cmd, index) {
    data := GetMacroCMDData(StrSplit(cmd, "_")[1])
    cancelled := () => tableItem.Items[index].Killed
    if (cancelled())
        return
    value := ""
    failure := ""
    try value := WindowControl.Execute(data, GetReplaceVarText(tableItem, index, data.Argument), cancelled)
    catch as e
        failure := e.Message
    if (!cancelled())
        SaveCommandResult(data, value, failure)
}
