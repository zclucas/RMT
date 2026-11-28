#Requires AutoHotkey v2.0
#Include TimeoutPolicy.ahk
#Include ControlExcelUtil.ahk

class WindowControlTimeoutError extends Error {
}

class WindowControlData {
    SerialStr := ""
    ActionType := "点击控件"
    Selector := ""
    Argument := ""
    WriteKind := "text"
    WaitType := "等待出现"
    ClickType := "左键单击"
    ClickHoldMs := 500
    ScrollOffset := 0
    WaitValueKind := "text"
    WaitLogic := "且"
    WaitConditions := [["等于", "", "运行时控件值"]]
    ResultVar := ""
    ErrorVar := ""
    TimeoutMs := TimeoutPolicy.DefaultMs
    TimeoutAction := TimeoutPolicy.DefaultAction
    TimeoutStatusVar := TimeoutPolicy.DefaultStatusVar
}

class ControlInfoData extends WindowControlData {
    ActionType := "检测控件存在"
    ResultVar := "Res"
    ValueVar := "ConValue"
    ControlVar := "TargetCon"
    HwndVar := ""
    StateVar := ""
    XVar := "ConX"
    YVar := "ConY"
    WindowXVar := "ConWinX"
    WindowYVar := "ConWinY"
    WidthVar := "ConWidth"
    HeightVar := "ConHeight"
    TimeoutAction := ""
    TimeoutStatusVar := ""
}

class WindowControl {
    static Actions := ["点击控件", "聚焦控件", "写入控件值", "滚动到控件", "等待控件出现", "检测控件存在", "读取位置/宽高"]
    static InfoActions := ["检测控件存在", "读取位置/宽高"]
    static PositionFields := ["XVar", "YVar", "WindowXVar", "WindowYVar", "WidthVar", "HeightVar"]

    static NormalizeAction(action) => this.Choice(action, this.Actions, "控件操作")

    static Choice(value, choices, label := "控件选项") {
        value := GetConfigKey(value, choices)
        for choice in choices
            if (Type(value) == "String" && value == choice)
                return choice
        throw ValueError(GetLang("不支持的") GetLang(label) "：" value)
    }

    static ChoiceIndex(value, choices) {
        value := this.Choice(value, choices)
        for index, choice in choices
            if (value == choice)
                return index - 1
    }
    static OperationActions := ["点击控件", "写入控件值", "等待控件出现", "聚焦控件", "滚动到控件"]
    static WaitTypes := ["等待出现", "等待消失", "可用", "禁用", "值变化", "值满足条件", "值不满足条件"]
    static ClickTypes := ["左键单击", "左键双击", "左键长按", "右键单击", "右键双击", "右键长按"]

    static ResolveClickHoldMs(value, resolve := "") {
        if (TimeoutPolicy.IsVariable(value)) {
            if (IsObject(resolve))
                value := resolve(value)
            else if (!TryGetVarValue(&value, SubStr(value, 2, -1), false, Map(), false))
                throw Error(GetLang("长按时间变量尚未赋值。"))
        }
        if (!IsInteger(value) || value < 1 || value > 3600000)
            throw Error(GetLang("长按时间应为 1～3600000 的整数毫秒。"))
        return Integer(value)
    }

    static ConditionOperators(kind) => kind == "text"
        ? ["等于", "不等于", "包含", "不包含", "开头是", "结尾是", "为空", "不为空"]
        : ["大于", "大于等于", "等于", "不等于", "小于", "小于等于"]

    ; Automation ID is scoped to siblings. Fall back to name and class, then the occurrence in that group.
    static Describe(element) {
        if (element is ExcelControlTarget)
            return Map("type", 50029, "id", element.range.Address[false, false, 1], "name", element.Name(), "class", "ExcelCell")
        return Map("type", this._Int(element, 21), "id", this._String(element, 29),
            "name", this._String(element, 23), "class", this._String(element, 30))
    }

    static FromPoint(x, y) {
        hit := this._HitTest(x, y)
        if (cell := ControlExcel.FromPoint(hit.hwnd, x, y)) {
            key := this.Describe(cell)
            key["index"] := 1
            return Map("exe", WinGetProcessName(hit.hwnd), "windowClass", WinGetClass(hit.hwnd),
                "titleContains", "", "path", [key], "excel", cell.Metadata())
        }
        path := []
        node := hit.element
        while (node && !this._Equals(node, hit.root)) {
            key := this.Describe(node)
            key["class"] := this._StableClass(key["class"])
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
                return {target: target, parent: parent, window: window, element: hit.element}
            node := this._Object(3, hit.walker, "Ptr", node)
        }
        return node ? {target: target, parent: window, window: window, element: hit.element} : 0
    }

    static _Bounds(element, hwnd := 0) {
        if (element is ExcelControlTarget)
            return element.Bounds()
        rect := Buffer(16)
        ; DWM 的可见边框不含窗口外围用于拖拽缩放的透明区域。
        if (!hwnd || DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", rect.Size, "Int"))
            ComCall(43, element, "Ptr", rect) ; get_CurrentBoundingRectangle
        return {left: NumGet(rect, 0, "Int"), top: NumGet(rect, 4, "Int"),
            right: NumGet(rect, 8, "Int"), bottom: NumGet(rect, 12, "Int")}
    }

    static IsControlReference(text) => RegExMatch(text, "^\{[^{}\r\n]+\}$")

    static ResolveTarget(text, resolver := "") {
        if (this.IsControlReference(text)) {
            name := SubStr(text, 2, -1)
            if (IsObject(resolver))
                text := resolver(name)
            else if (!TryGetVarValue(&text, name, false, Map(), false))
                throw TargetError(GetLang("控件变量尚未赋值：") name)
            if (Type(text) != "String" || Trim(text) == "")
                throw TargetError(GetLang("控件变量为空或无效：") name)
        }
        this.ParseSelector(text)
        return text
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
            if (selector.Has("excel")) {
                cell := selector["excel"]
                if (!(cell is Map) || Type(cell.Get("workbook", 0)) != "String" || cell["workbook"] == ""
                    || Type(cell.Get("sheet", 0)) != "String" || cell["sheet"] == ""
                    || Type(cell.Get("address", 0)) != "String" || !RegExMatch(cell["address"], "^[A-Z]{1,3}[1-9]\d{0,6}$"))
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
                if (selector.Has("excel"))
                    element := ControlExcel.Find(hwnd, selector["excel"])
                else {
                    element := this._Object(6, this._Automation(), "Ptr", hwnd)
                    if (element)
                        element := this._ResolvePath(element, selector["path"])
                }
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

    static Execute(data, arg, cancelled, resolve := "", outputs := unset, waitBaseline := unset) {
        if (IsSet(outputs)) {
            outputs.hwnd := 0
            outputs.bounds := ""
        }
        selector := this.ParseSelector(this.ResolveTarget(data.Selector))
        action := this.NormalizeAction(data.ActionType)
        waiting := this.UsesTimeout(action)
        waitType := data.WaitType
        baseline := IsSet(waitBaseline) ? waitBaseline : {set: false, value: ""}
        deadline := this.UsesTimeout(action) ? A_TickCount + TimeoutPolicy.ResolveMs(data.TimeoutMs) : 0
        while (!cancelled()) {
            element := this.Find(selector)
            if (waiting ? this._WaitReady(element, waitType, data, baseline, resolve) : !!element)
                break
            if (!this.UsesTimeout(action)) {
                if (action == "检测控件存在")
                    return 0
                throw TargetError(GetLang("没有找到可选取的窗口控件。"))
            }
            if (A_TickCount >= deadline)
                throw WindowControlTimeoutError(GetLang("等待控件超时。"))
            Sleep(Max(0, Min(75, deadline - A_TickCount)))
        }
        if (cancelled())
            return ""

        switch action {
            case "等待控件出现", "检测控件存在":
                if (action == "检测控件存在" && IsSet(outputs)) {
                    outputs.hwnd := this._NativeHwnd(element)
                    outputs.value := ""
                    if (data.ValueVar != "") {
                        result := this.ProbeValue(element)
                        if (result.supported)
                            outputs.value := result.value
                    }
                    if (data.StateVar != "") {
                        enabled := outputs.hwnd ? DllCall("IsWindowEnabled", "Ptr", outputs.hwnd) : this._Int(element, 28)
                        visible := !this._Int(element, 38) && (!outputs.hwnd || DllCall("IsWindowVisible", "Ptr", outputs.hwnd))
                        outputs.state := (enabled ? "可交互" : "不可交互") "-" (visible ? "可见" : "不可见")
                    }
                }
                return 1
            case "读取位置/宽高":
                bounds := this._Bounds(element)
                if (bounds.right <= bounds.left || bounds.bottom <= bounds.top)
                    throw Error(GetLang("控件未提供有效位置。"))
                bounds.x := Floor((bounds.left + bounds.right) / 2)
                bounds.y := Floor((bounds.top + bounds.bottom) / 2)
                point := Buffer(8)
                NumPut("Int", bounds.x, "Int", bounds.y, point)
                if (!DllCall("ScreenToClient", "Ptr", this._ElementWindow(element), "Ptr", point))
                    throw OSError()
                bounds.windowX := NumGet(point, 0, "Int")
                bounds.windowY := NumGet(point, 4, "Int")
                if (IsSet(outputs))
                    outputs.bounds := bounds
                return JSON.stringify(Map("x", bounds.x, "y", bounds.y,
                    "windowX", bounds.windowX, "windowY", bounds.windowY,
                    "width", bounds.right - bounds.left, "height", bounds.bottom - bounds.top), 0)
            case "点击控件":
                hold := InStr(data.ClickType, "长按") ? this.ResolveClickHoldMs(data.ClickHoldMs, resolve) : 0
                return this._ClickElement(element, data.ClickType, cancelled, hold)
            case "聚焦控件":
                if (element is ExcelControlTarget)
                    element.Reveal()
                else
                    ComCall(3, element)
            case "写入控件值":
                return this.WriteValue(element, arg)
            case "滚动到控件":
                if (element is ExcelControlTarget)
                    element.Reveal()
                else
                    ComCall(3, this._RequiredPattern(element, "scroll"))
                offset := data.ScrollOffset
                if (IsObject(resolve))
                    offset := resolve(String(offset))
                if (!IsInteger(offset) || Abs(Number(offset)) > 100000)
                    throw Error(GetLang("偏移值应为 -100000～100000 的整数像素。"))
                if (offset != 0) {
                    if (element is ExcelControlTarget)
                        element.Offset(Integer(offset))
                    else
                        this._OffsetScroll(element, Integer(offset))
                }
        }
        return 1
    }

    static _WaitReady(element, waitType, data, baseline, resolve := "") {
        if (waitType == "等待消失")
            return !element
        if (!element)
            return false
        if (waitType == "等待出现")
            return true
        if (waitType == "可用" || waitType == "禁用")
            return !!this._Int(element, 28) == (waitType == "可用")
        result := this.ProbeValue(element)
        if (!result.supported)
            throw Error(result.reason)
        if (waitType == "值变化") {
            if (!baseline.set) {
                baseline.set := true, baseline.value := String(result.value)
                return false
            }
            return !(String(result.value) == baseline.value)
        }
        matched := this.MatchWaitConditions(result.value, data, this.ValueKind(result), resolve)
        return waitType == "值不满足条件" ? !matched : matched
    }

    static GetWaitConditions(data) {
        for condition in data.WaitConditions
            if (!(condition is Array) || condition.Length != 3)
                throw ValueError(GetLang("控件等待条件格式无效。"))
        return data.WaitConditions
    }

    static IsRuntimeControlValue(source) => source == "运行时控件值" || source == "{运行时控件值}"
        || source == "❖运行时控件值" || source == "{❖运行时控件值}"

    static WaitConditionOperators(kind, source) {
        if (this.IsRuntimeControlValue(source))
            return this.ConditionOperators(kind)
        return ["等于", "不等于", "大于", "大于等于", "小于", "小于等于", "包含", "不包含", "开头是", "结尾是", "为空", "不为空"]
    }

    static MatchWaitConditions(value, data, kind, resolve := "") {
        useOr := data.WaitLogic == "或"
        for condition in this.GetWaitConditions(data) {
            current := this.IsRuntimeControlValue(condition[3])
            left := current ? value : condition[3]
            expected := condition[2]
            if (IsObject(resolve)) {
                if (!current)
                    left := resolve(String(left))
                expected := resolve(String(expected))
            }
            compareKind := current ? kind : this.WaitOperandKind(condition[1], left, expected)
            matched := this.CompareValue(left, expected, condition[1], compareKind)
            if (useOr && matched)
                return true
            if (!useOr && !matched)
                return false
        }
        return !useOr
    }

    static WaitOperandKind(operator, left, right) {
        if (operator == "大于" || operator == "大于等于" || operator == "小于" || operator == "小于等于")
            return "number"
        return (operator == "等于" || operator == "不等于") && IsNumber(left) && IsNumber(right) ? "number" : "text"
    }

    static ValueKind(result) {
        if (result.HasOwnProp("category"))
            return result.category
        if (result.kind == GetLang("文本"))
            return "text"
        if (result.kind == GetLang("范围比例（0～1）"))
            return "ratio"
        if (result.kind == GetLang("选项序号（1～n，未选 0）"))
            return "index"
        return "state"
    }

    static CompareValue(value, expected, operator, kind) {
        valid := false
        for candidate in this.ConditionOperators(kind)
            if (candidate == operator)
                valid := true
        if (!valid)
            throw Error(GetLang("条件运算符无效。"))
        if (kind != "text") {
            if (!IsNumber(value) || !IsNumber(expected))
                throw Error(GetLang("条件值必须为数字。"))
            value := Number(value), expected := Number(expected)
            if (kind == "ratio" && (expected < 0 || expected > 1))
                throw Error(GetLang("比例条件值应为 0～1。"))
            if (kind == "index" && (!IsInteger(expected) || expected < 0))
                throw Error(GetLang("序号条件值应为非负整数。"))
        } else {
            value := String(value), expected := String(expected)
        }
        switch operator {
            case "等于": return value == expected
            case "不等于": return !(value == expected)
            case "大于": return value > expected
            case "大于等于": return value >= expected
            case "小于": return value < expected
            case "小于等于": return value <= expected
            case "包含": return InStr(value, expected, true) > 0
            case "不包含": return !InStr(value, expected, true)
            case "开头是": return SubStr(value, 1, StrLen(expected)) == expected
            case "结尾是": return expected == "" || SubStr(value, -StrLen(expected)) == expected
            case "为空": return value == ""
            case "不为空": return value != ""
        }
        throw Error(GetLang("条件运算符无效。"))
    }

    static _ClickElement(element, kind, cancelled, holdMs := 500) {
        kind := GetLangKey(kind)
        valid := false
        for candidate in this.ClickTypes
            if (candidate == kind)
                valid := true
        if (!valid)
            throw Error(GetLang("点击参数无效。"))
        if (element is ExcelControlTarget) {
            element.Reveal()
            bounds := element.Bounds()
            element := this._HitTest(Floor((bounds.left + bounds.right) / 2), Floor((bounds.top + bounds.bottom) / 2)).element
        }
        if (!this._Int(element, 28))
            throw Error(GetLang("此控件已禁用。"))
        if (cancelled())
            return ""
        ; Invoke 表达控件默认动作；右键、双击和长按仍需对应鼠标事件。
        if (kind == "左键单击" && (invoke := this._Pattern(element, "invoke"))) {
            ; 已调用后报错不能再模拟点击，避免控件已响应却被重复触发。
            ComCall(3, invoke)
            return cancelled() ? "" : 1
        }
        hwnd := this._ElementWindow(element)
        WinActivate("ahk_id " hwnd)
        deadline := A_TickCount + 2000
        while (!WinActive("ahk_id " hwnd)) {
            if (cancelled())
                return ""
            if (A_TickCount >= deadline)
                throw Error(GetLang("无法激活目标窗口。"))
            Sleep(20)
        }
        if (this._Int(element, 38) && (scroll := this._Pattern(element, "scroll")))
            ComCall(3, scroll)
        bounds := this._Bounds(element)
        walker := this._Object(14, this._Automation())
        node := element
        loop 64 {
            node := this._Object(3, walker, "Ptr", node)
            if (!node)
                break
            clip := this._Bounds(node)
            if (clip.right > clip.left && clip.bottom > clip.top) {
                bounds.left := Max(bounds.left, clip.left), bounds.top := Max(bounds.top, clip.top)
                bounds.right := Min(bounds.right, clip.right), bounds.bottom := Min(bounds.bottom, clip.bottom)
            }
        }
        if (bounds.right <= bounds.left || bounds.bottom <= bounds.top)
            throw Error(GetLang("目标控件不在可点击区域。"))
        valid := false
        x := Floor((bounds.left + bounds.right) / 2)
        y := Floor((bounds.top + bounds.bottom) / 2)
        hit := this._HitTest(x, y).element
        loop 64 {
            if (this._Equals(hit, element)) {
                valid := true
                break
            }
            hit := this._Object(3, walker, "Ptr", hit)
            if (!hit)
                break
        }
        if (!valid)
            throw Error(GetLang("目标控件被遮挡，无法点击。"))
        button := InStr(kind, "右键") ? "Right" : "Left"
        count := InStr(kind, "双击") ? 2 : 1
        hold := InStr(kind, "长按") ? this.ResolveClickHoldMs(holdMs) : 0
        ; 屏幕坐标不受当前 CoordMode 影响；取消或点击异常也必须恢复光标。
        cursor := Buffer(8)
        if (!DllCall("GetCursorPos", "Ptr", cursor))
            throw OSError()
        try {
            if (!DllCall("SetCursorPos", "Int", x, "Int", y))
                throw OSError()
            loop count {
                if (cancelled())
                    return ""
                try {
                    Click(button " Down")
                    endTime := A_TickCount + hold
                    while (A_TickCount < endTime && !cancelled())
                        Sleep(Max(1, Min(20, endTime - A_TickCount)))
                } finally {
                    Click(button " Up")
                }
                if (A_Index < count)
                    Sleep(50)
            }
        } finally {
            DllCall("SetCursorPos", "Int", NumGet(cursor, 0, "Int"), "Int", NumGet(cursor, 4, "Int"))
        }
        return cancelled() ? "" : 1
    }

    static _ElementWindow(element) {
        if (element is ExcelControlTarget)
            return element.hwnd
        walker := this._Object(14, this._Automation())
        loop 64 {
            hwnd := 0
            ComCall(36, element, "Ptr*", &hwnd)
            if (hwnd)
                return DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
            element := this._Object(3, walker, "Ptr", element)
            if (!element)
                break
        }
        throw Error(GetLang("无法确定控件所属窗口。"))
    }

    ; 返回控件自身的 HWND；UIA 虚拟控件没有独立窗口时返回 0。
    static _NativeHwnd(element) {
        if (element is ExcelControlTarget)
            return 0
        hwnd := 0
        ComCall(36, element, "Ptr*", &hwnd)
        return hwnd
    }

    static _OffsetScroll(element, offset) {
        walker := this._Object(14, this._Automation())
        node := element
        loop 64 {
            if ((pattern := this._Pattern(node, "scrollContainer")) && this._Int(pattern, 10)) {
                view := this._Double(pattern, 8)
                bounds := this._Bounds(node)
                travel := (bounds.bottom - bounds.top) * (100 / Max(view, 0.001) - 1)
                if (travel > 0) {
                    percent := Max(0, Min(100, this._Double(pattern, 6) + offset * 100 / travel))
                    ComCall(4, pattern, "Double", -1, "Double", percent)
                    return
                }
            }
            node := this._Object(3, walker, "Ptr", node)
            if (!node)
                break
        }
        throw Error(GetLang("目标容器不支持滚动偏移。"))
    }

    ; 拾取预览与基础信息共用读取逻辑，空文本也是可读取的值。
    static ProbeValue(element, preview := false) {
        try {
            if (cell := ControlExcel.FromElement(element))
                return cell.Read()
            type := this._Int(element, 21)
            if (pattern := this._Pattern(element, "toggle")) {
                state := this._Int(pattern, 4)
                return this._Value(state == 2 ? 0.5 : state, "勾选状态（0/1，半选 0.5）")
            }
            if (webSwitch := this._WebSwitch(element))
                return this._Value(webSwitch.state, "开关状态（0/1）")
            if (type == 50003)
                return this._ComboValue(element)
            if (pattern := this._Pattern(element, "range")) {
                current := this._Double(pattern, 4)
                low := this._Double(pattern, 7), high := this._Double(pattern, 6)
                if (high <= low)
                    return {supported: false, value: "", reason: GetLang("控件未提供有效数值范围。")}
                return this._Value(Max(0, Min(1, (current - low) / (high - low))), "范围比例（0～1）")
            }
            if (pattern := this._Pattern(element, "expand")) {
                state := this._Int(pattern, 5)
                if (state != 3) ; LeafNode 没有展开状态。
                    return this._Value(state == 0 ? 0 : 1, "展开状态（0/1）")
            }
            if (pattern := this._Pattern(element, "selection"))
                return this._Value(this._Int(pattern, 6) ? 1 : 0, "选中状态（0/1）")
            ; 部分 UIA 提供者将原生 Edit 的文本截到4096字；直接读取原生文本。
            if (type == 50004 && (hwnd := this._NativeControl(element, "edit"))
                && !(DllCall("GetWindowLongW", "Ptr", hwnd, "Int", -16, "UInt") & 0x20)) {
                length := this._Send(hwnd, 0xE) ; WM_GETTEXTLENGTH
                if (preview)
                    length := Min(length, 100)
                if (length > 32 * 1024 * 1024)
                    throw Error(GetLang("控件文本超过64MB，无法完整读取。"))
                text := Buffer((length + 1) * 2, 0)
                copied := this._Send(hwnd, 0xD, length + 1, text.Ptr) ; WM_GETTEXT
                return this._Value(StrGet(text.Ptr, copied, "UTF-16"), "文本")
            }
            if (pattern := this._Pattern(element, "text")) {
                range := this._Object(7, pattern)
                return this._Value(this._String(range, 12, "Int", preview ? 100 : -1), "文本")
            }
            if (pattern := this._Pattern(element, "value"))
                return this._Value(this._String(pattern, 4), "文本")
            if (type == 50026 || type == 50033 || type == 50032 || type == 50021 || type == 50010)
                return {supported: false, value: "", reason: GetLang("布局控件无法读取值。")}
            ; 仅文字语义的控件允许回退到 Name，不能把布局名称误认为值。
            if (type == 50000 || type == 50004 || type == 50005 || type == 50006
                || type == 50017 || type == 50020 || type == 50022 || type == 50030)
                return this._Value(this._String(element, 23), "文本")
            ; 网页菜单、自定义项等常只公开可访问名称，将其作为文本值。
            if (type == 50007 || type == 50011 || type == 50019 || type == 50025 || type == 50029 || type == 50031) {
                name := this._String(element, 23)
                if (Trim(name) != "")
                    return this._Value(name, "文本")
            }
            return {supported: false, value: "", reason: GetLang("此控件不支持读取值。")}
        } catch as e {
            return {supported: false, value: "", reason: GetLang("控件值读取失败。") " " e.Message}
        }
    }

    static _Value(value, kind) => {supported: true, value: value, kind: GetLang(kind), reason: ""}

    static _Double(target, method) {
        value := 0.0
        ComCall(method, target, "Double*", &value)
        return value
    }

    static _ComboValue(element) {
        ; 原生 ComboBox 的折叠项可能不在 UIA 树中，优先读取其选项序号。
        hwnd := 0
        ComCall(36, element, "Ptr*", &hwnd)
        if (hwnd && RegExMatch(WinGetClass(hwnd), "i)^(ComboBox|WindowsForms10\.COMBOBOX(?:\..*)?)$")) {
            selected := 0
            if (!DllCall("SendMessageTimeoutW", "Ptr", hwnd, "UInt", 0x147, "Ptr", 0, "Ptr", 0,
                "UInt", 2, "UInt", 200, "Ptr*", &selected, "Ptr"))
                throw Error(GetLang("控件值读取失败。"))
            ; CB_ERR (-1) 表示未选择，统一返回 0。
            return this._Value((selected == -1 || selected == 0xFFFFFFFF) ? 0 : selected + 1, "选项序号（1～n，未选 0）")
        }
        selection := this._Pattern(element, "selectionContainer")
        if (!selection)
            return {supported: false, value: "", reason: GetLang("控件未提供可读取的选项序号。")}
        selected := this._Object(3, selection)
        count := this._Int(selected, 3)
        if (!count)
            return this._Value(0, "选项序号（1～n，未选 0）")
        if (count != 1)
            return {supported: false, value: "", reason: GetLang("控件未提供唯一选中项。")}
        item := this._Object(4, selected, "Int", 0)
        ; PositionInSet 是提供者声明的完整集合序号，适用于虚拟化列表。
        position := this._PropertyInt(item, 30152)
        if (position > 0)
            return this._Value(position, "选项序号（1～n，未选 0）")
        if (container := this._Pattern(element, "itemContainer")) {
            previous := 0
            deadline := A_TickCount + 500
            loop 4096 {
                if (A_TickCount > deadline)
                    break
                next := this._ContainerItem(container, previous)
                if (!next)
                    break
                if (this._Equals(next, item))
                    return this._Value(A_Index, "选项序号（1～n，未选 0）")
                previous := next
            }
        }
        return this._ComboIndex(element, item)
    }

    static _ComboIndex(element, selected) {
        ; 不展开下拉框、不改变选择；按现有树中的 ListItem 顺序定位。
        walker := this._Object(14, this._Automation())
        stack := [], node := this._Object(4, walker, "Ptr", element), index := 0, visited := 0, found := 0
        size := this._PropertyInt(selected, 30153), deadline := A_TickCount + 500
        while (node && ++visited <= 4096 && A_TickCount <= deadline) {
            if (this._Int(node, 21) == 50007) {
                index++
                if (this._Equals(node, selected))
                    found := index
            } else {
                child := this._Object(4, walker, "Ptr", node)
                if (child) {
                    stack.Push(node)
                    node := child
                    continue
                }
            }
            loop {
                sibling := this._Object(6, walker, "Ptr", node)
                if (sibling || !stack.Length) {
                    node := sibling
                    break
                }
                node := stack.Pop()
            }
        }
        ; 有 SizeOfSet 时必须验证集合完整，不能把虚拟化后的局部序号当作完整序号。
        if (!node && found && (!size || size == index))
            return this._Value(found, "选项序号（1～n，未选 0）")
        return {supported: false, value: "", reason: GetLang("控件未提供可读取的选项序号。")}
    }

    static _PropertyInt(element, id) {
        variant := Buffer(24, 0)
        try {
            ComCall(10, element, "Int", id, "Ptr", variant)
            return NumGet(variant, 0, "UShort") == 3 ? NumGet(variant, 8, "Int") : 0
        } finally {
            DllCall("oleaut32\VariantClear", "Ptr", variant)
        }
    }

    static ProbeWrite(element) {
        try {
            if (cell := ControlExcel.FromElement(element))
                return {supported: cell.Writable(), kind: "text", stateType: "", reason: cell.Writable() ? "" : GetLang("Excel 单元格已保护，无法修改。")}
            type := this._Int(element, 21)
            kind := "text", pattern := 0, reason := "", stateType := ""
            if (pattern := this._Pattern(element, "toggle")) {
                kind := "state", stateType := "toggle"
            }
            else if (webSwitch := this._WebSwitch(element)) {
                kind := "state", stateType := "switch"
                if (webSwitch.disabled)
                    reason := GetLang("此开关已禁用，无法写入。")
                else if (!this._Pattern(element, "invoke"))
                    reason := GetLang("此开关未提供可执行的切换操作。")
            }
            else if (type == 50003) {
                kind := "index"
                if (!this._NativeControl(element, "combo") && !this._Pattern(element, "itemContainer")
                    && !this._Pattern(element, "selectionContainer"))
                    reason := GetLang("控件不支持按序号选择。")
            } else if (pattern := this._Pattern(element, "range")) {
                kind := "ratio"
                if (this._Double(pattern, 6) <= this._Double(pattern, 7))
                    reason := GetLang("控件未提供有效数值范围。")
                else if (this._Int(pattern, 5) && !this._NativeControl(element, "progress"))
                    reason := GetLang("此控件为只读，无法写入。")
            } else if ((pattern := this._Pattern(element, "expand")) && this._Int(pattern, 5) != 3) {
                kind := "state", stateType := "expand"
            } else if (pattern := this._Pattern(element, "selection")) {
                kind := "state", stateType := "selection"
            }
            else if (pattern := this._Pattern(element, "value")) {
                if (this._Int(pattern, 5))
                    reason := GetLang("此控件为只读，无法写入。")
            } else
                reason := GetLang("此控件不支持写入值。")
            if (!this._Int(element, 28))
                reason := GetLang("此控件已禁用，无法写入。")
            return {supported: reason == "", kind: kind, reason: reason, stateType: stateType}
        } catch as e {
            return {supported: false, kind: "text", reason: e.Message}
        }
    }

    ; 拾取只检查启用状态和位置，不触发点击。
    static ProbeClick(element) {
        try {
            if (element is ExcelControlTarget)
                return {supported: true}
            bounds := this._Bounds(element)
            return {supported: !!this._Int(element, 28) && bounds.right > bounds.left && bounds.bottom > bounds.top}
        } catch {
            return {supported: false}
        }
    }

    static ValidateWriteArgument(kind, arg) {
        if (kind == "text")
            return
        if (!IsNumber(arg))
            throw Error(GetLang("控件值必须是数字。"))
        switch kind {
            case "state":
                if (Number(arg) != 0 && Number(arg) != 1)
                    throw Error(GetLang("状态请输入 0 或 1。"))
            case "ratio":
                if (Number(arg) < 0 || Number(arg) > 1)
                    throw Error(GetLang("比例请输入 0～1。"))
            case "index":
                if (!IsInteger(arg) || Integer(arg) < 1)
                    throw Error(GetLang("选项序号请输入从 1 开始的整数。"))
        }
    }

    static WriteValue(element, arg) {
        if (cell := ControlExcel.FromElement(element))
            return cell.Write(arg)
        profile := this.ProbeWrite(element)
        if (!profile.supported)
            throw Error(profile.reason)
        this.ValidateWriteArgument(profile.kind, arg)
        switch profile.kind {
            case "text":
                ComCall(3, this._RequiredPattern(element, "value"), "WStr", arg)
                return arg
            case "index":
                return this._SelectCombo(element, Integer(arg))
            case "ratio":
                pattern := this._RequiredPattern(element, "range")
                low := this._Double(pattern, 7), high := this._Double(pattern, 6)
                raw := low + Number(arg) * (high - low)
                if (hwnd := this._NativeControl(element, "progress"))
                    this._Send(hwnd, 0x402, Round(raw)) ; PBM_SETPOS
                else
                    ComCall(3, pattern, "Double", raw)
                return Number(arg)
            case "state":
                state := Number(arg)
                if (pattern := this._Pattern(element, "toggle")) {
                    current := this._Int(pattern, 4)
                    loop 3 {
                        if (current == state)
                            return state
                        ComCall(3, pattern)
                        deadline := A_TickCount + 500
                        ; 等待提供者更新状态，避免异步 Toggle 被重复触发。
                        loop {
                            next := this._Int(pattern, 4)
                            if (next != current)
                                break
                            if (A_TickCount >= deadline)
                                throw Error(GetLang("控件未达到指定状态。"))
                            Sleep(20)
                        }
                        current := next
                    }
                    if (current != state)
                        throw Error(GetLang("控件未达到指定状态。"))
                } else if (this._WebSwitch(element)) {
                    return this._WriteWebSwitch(element, state)
                } else if (profile.stateType == "expand") {
                    pattern := this._RequiredPattern(element, "expand")
                    if ((this._Int(pattern, 5) != 0 ? 1 : 0) != state)
                        ComCall(state ? 3 : 4, pattern)
                } else if (pattern := this._Pattern(element, "selection")) {
                    if (!!this._Int(pattern, 6) != state)
                        ComCall(state ? 3 : 5, pattern)
                } else
                    ComCall(state ? 3 : 4, this._RequiredPattern(element, "expand"))
                return state
        }
    }

    static _WebSwitch(element) {
        cls := this._String(element, 30)
        if (!RegExMatch(cls, "(^|\s)vui_switch--switch(?=\s|$)"))
            return 0
        return {state: RegExMatch(cls, "(^|\s)is-checked(?=\s|$)") ? 1 : 0,
            disabled: !!RegExMatch(cls, "(^|\s)(is-disabled|is-loading)(?=\s|$)")}
    }

    static _StableClass(cls) {
        if (!RegExMatch(cls, "(^|\s)vui_switch--switch(?=\s|$)"))
            return cls
        return Trim(RegExReplace(RegExReplace(cls, "(^|\s)(is-checked|is-disabled|is-loading)(?=\s|$)", " "), "\s+", " "))
    }

    static _WriteWebSwitch(element, state) {
        current := this._WebSwitch(element)
        if (!current || current.disabled)
            throw Error(GetLang("此开关当前无法写入。"))
        if (current.state == state)
            return state
        ; 只切换一次，等待网页更新状态，避免异步响应时重复点击。
        ComCall(3, this._RequiredPattern(element, "invoke"))
        deadline := A_TickCount + 1500
        loop {
            current := this._WebSwitch(element)
            if (current && current.state == state)
                return state
            if (A_TickCount >= deadline)
                throw Error(GetLang("开关未达到指定状态。"))
            Sleep(30)
        }
    }

    static _NativeControl(element, kind) {
        hwnd := 0
        ComCall(36, element, "Ptr*", &hwnd)
        if (!hwnd)
            return 0
        name := WinGetClass(hwnd)
        return kind == "edit" ? (RegExMatch(name, "i)^(Edit|WindowsForms10\.EDIT(?:\..*)?)$") ? hwnd : 0)
            : kind == "combo" ? (RegExMatch(name, "i)^(ComboBox|WindowsForms10\.COMBOBOX(?:\..*)?)$") ? hwnd : 0)
            : (name == "msctls_progress32" ? hwnd : 0)
    }

    static _Send(hwnd, message, wParam := 0, lParam := 0) {
        result := 0
        if (!DllCall("SendMessageTimeoutW", "Ptr", hwnd, "UInt", message, "Ptr", wParam, "Ptr", lParam,
            "UInt", 2, "UInt", 300, "Ptr*", &result, "Ptr"))
            throw Error(GetLang("控件操作失败。"))
        return result
    }

    static _ContainerItem(container, previous := 0) {
        empty := Buffer(16, 0)
        return A_PtrSize == 8
            ? this._Object(3, container, "Ptr", previous, "Int", 0, "Ptr", empty)
            : this._Object(3, container, "Ptr", previous, "Int", 0, "Int64", 0, "Int64", 0)
    }

    static _SelectCombo(element, index) {
        if (hwnd := this._NativeControl(element, "combo")) {
            count := this._Send(hwnd, 0x146) ; CB_GETCOUNT
            if (index > count)
                throw Error(GetLang("选项序号超出范围。"))
            this._Send(hwnd, 0x14E, index - 1) ; CB_SETCURSEL
            parent := DllCall("GetParent", "Ptr", hwnd, "Ptr")
            id := DllCall("GetDlgCtrlID", "Ptr", hwnd, "Int") & 0xFFFF
            if (parent) {
                this._Send(parent, 0x111, id | (1 << 16), hwnd) ; CBN_SELCHANGE
                this._Send(parent, 0x111, id | (9 << 16), hwnd) ; CBN_SELENDOK
            }
            return index
        }
        if (container := this._Pattern(element, "itemContainer")) {
            item := 0, deadline := A_TickCount + 1500
            loop index {
                if (A_Index > 4096 || A_TickCount > deadline)
                    throw Error(GetLang("无法定位指定选项。"))
                item := this._ContainerItem(container, item)
                if (!item)
                    throw Error(GetLang("选项序号超出范围。"))
            }
            ComCall(3, this._RequiredPattern(item, "selection"))
            return index
        }
        ; 已公开完整集合的普通控件树可以按 ListItem 顺序选择。
        walker := this._Object(14, this._Automation())
        pending := [], node := this._Object(4, walker, "Ptr", element), items := [], visited := 0
        while (node && ++visited <= 4096) {
            if (this._Int(node, 21) == 50007)
                items.Push(node)
            else if (child := this._Object(4, walker, "Ptr", node)) {
                pending.Push(node)
                node := child
                continue
            }
            loop {
                next := this._Object(6, walker, "Ptr", node)
                if (next || !pending.Length) {
                    node := next
                    break
                }
                node := pending.Pop()
            }
        }
        if (node || index > items.Length)
            throw Error(GetLang("无法定位指定选项。"))
        item := items[index], size := this._PropertyInt(item, 30153), position := this._PropertyInt(item, 30152)
        if ((size && size != items.Length) || (position && position != index))
            throw Error(GetLang("控件未公开完整选项列表。"))
        ComCall(3, this._RequiredPattern(item, "selection"))
        return index
    }

    static UsesArgument(action) => action == "写入控件值" || action == "设置勾选" || action == "设置范围值"

    static UsesTimeout(action) => this.NormalizeAction(action) == "等待控件出现"

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
        if (target is ExcelControlTarget)
            return method == 21 ? 50029 : method == 28 ? 1 : method == 38 ? target.Offscreen() : 0
        value := 0
        ComCall(method, target, "Int*", &value)
        return value
    }

    static _String(target, method, args*) {
        if (target is ExcelControlTarget)
            return method == 23 ? target.Name() : method == 29 ? target.range.Address[false, false, 1] : method == 30 ? "ExcelCell" : ""
        ptr := 0
        args.Push("Ptr*", &ptr)
        ComCall(method, target, args*)
        if (!ptr)
            return ""
        try return StrGet(ptr, "UTF-16")
        finally DllCall("oleaut32\SysFreeString", "Ptr", ptr)
    }

    static _Equals(left, right) {
        if (left is ExcelControlTarget || right is ExcelControlTarget)
            return left is ExcelControlTarget && right is ExcelControlTarget && left.hwnd == right.hwnd && left.Name() == right.Name()
        equal := 0
        ComCall(3, this._Automation(), "Ptr", left, "Ptr", right, "Int*", &equal)
        return equal
    }

    static _Matches(element, key) {
        if (this._Int(element, 21) != key["type"])
            return false
        if (key["id"] != "")
            return this._String(element, 29) == key["id"]
        return this._String(element, 23) == key["name"] && this._StableClass(this._String(element, 30)) == key["class"]
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
        if (element is ExcelControlTarget)
            return 0
        static patterns := Map(
            "invoke", [10000, "{FB377FBE-8EA6-46D5-9C73-6499642D3059}"],
            "value", [10002, "{A94CD8B1-0844-4CD6-9D2D-640537AB39E9}"],
            "range", [10003, "{59213F4F-7346-49E5-B120-80555987A148}"],
            "expand", [10005, "{619BE086-1F4E-4EE4-BAFA-210128738730}"],
            "itemContainer", [10019, "{C690FDB2-27A8-423C-812D-429773C9084E}"],
            "selectionContainer", [10001, "{5ED5202E-B2AC-47A6-B638-4B0BF140D78E}"],
            "selection", [10010, "{A8EFA66A-0FDA-421A-9194-38021F3578EA}"],
            "text", [10014, "{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}"],
            "toggle", [10015, "{94CF8058-9B8D-4AB9-8BFD-4CD0A33C8C70}"],
            "scroll", [10017, "{B488300F-D015-4F19-9C29-BB595E3645EF}"],
            "scrollContainer", [10004, "{88F4D42A-E881-459D-A77C-73BBBB7E02DC}"])
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
    timedOut := false
    waitBaseline := {set: false, value: ""}
    action := TimeoutPolicy.Get(data)
    loop {
        try {
            runData := data.Clone()
            if (WindowControl.UsesTimeout(WindowControl.NormalizeAction(data.ActionType)))
                runData.TimeoutMs := TimeoutPolicy.ResolveMs(data.TimeoutMs, (text) => GetReplaceVarText(tableItem, index, text))
            runData.Selector := WindowControl.ResolveTarget(data.Selector, ResolveControlVariable.Bind(tableItem, index))
            value := WindowControl.Execute(runData, GetReplaceVarText(tableItem, index, data.Argument), cancelled,
                (text) => GetReplaceVarText(tableItem, index, text), outputs := {}, waitBaseline)
            failure := ""
            timedOut := false
            break
        } catch as e {
            failure := e.Message
            timedOut := e is WindowControlTimeoutError
            if (!timedOut || !TimeoutPolicy.CanRetry(action, A_Index))
                break
            if (!TimeoutPolicy.WaitBeforeRetry(cancelled))
                return
        }
    }
    if (cancelled())
        return
    if (WindowControl.UsesTimeout(data.ActionType))
        TimeoutPolicy.WriteStatus(data, timedOut)
    names := [], values := []
    controlAction := WindowControl.NormalizeAction(data.ActionType)
    if (failure != "" && controlAction == "检测控件存在")
        value := 0
    if (controlAction == "检测控件存在" && data.HwndVar != "") {
        names.Push(data.HwndVar)
        values.Push(failure == "" && value == 1 ? outputs.hwnd : 0)
    }
    if (controlAction == "检测控件存在" && data.StateVar != "") {
        names.Push(data.StateVar)
        values.Push(failure == "" && value == 1 ? outputs.state : "不可见")
    }
    if (controlAction == "检测控件存在" && data.ValueVar != "") {
        names.Push(data.ValueVar)
        values.Push(failure == "" && value == 1 ? outputs.value : "")
    }
    if (controlAction == "读取位置/宽高") {
        bounds := failure == "" ? outputs.bounds : ""
        for pair in [["XVar", "x"], ["YVar", "y"], ["WindowXVar", "windowX"], ["WindowYVar", "windowY"],
            ["WidthVar", "width"], ["HeightVar", "height"]] {
            if (data.%pair[1]% == "")
                continue
            names.Push(data.%pair[1]%)
            values.Push(!IsObject(bounds) ? 0 : pair[2] == "width" ? bounds.right - bounds.left
                : pair[2] == "height" ? bounds.bottom - bounds.top : bounds.%pair[2]%)
        }
    }
    if (WindowControl.NormalizeAction(data.ActionType) == "检测控件存在"
        && data.ControlVar != "") {
        names.Push(data.ControlVar)
        values.Push(failure == "" && value == 1 ? runData.Selector : "")
    }
    if (names.Length)
        MySetGlobalVariable(names, values, false)
    SaveCommandResult(data, value, failure, !timedOut || action == "")
    if (timedOut && TimeoutPolicy.Stops(action))
        throw Error(failure)
}

ResolveControlVariable(tableItem, index, name) {
    if (!TryGetTabVarValue(&value, tableItem, index, name, false, false))
        throw TargetError(GetLang("控件变量尚未赋值：") name)
    return value
}
