#Requires AutoHotkey v2.0

; 直接操作的观察、替代路径与诊断。搜索只定位，不隐式点击。
class AiDirectObserve {
    static Failure(argsJson, error) {
        command := ""
        try command := JSON.parse(argsJson).Get("command", "")
        message := error.Message
        code := "execution_failed", next := ["截图", "控件列表"]
        if (InStr(message, "完全访问"))
            code := "permission_denied", next := []
        else if (InStr(message, "取消"))
            code := "cancelled", next := []
        else if (InStr(message, "不支持的指令选项") || InStr(message, "表达式需要") || InStr(message, "取值无效") || InStr(message, "缺少Param")
            || InStr(message, "缺少参数") || InStr(message, "未知参数"))
            code := "invalid_arguments", next := ["list_instructions", "变量监视"]
        else if (InStr(message, "OpenCV") || InStr(message, "运行库") || InStr(message, "OCR"))
            code := "dependency_unavailable", next := ["诊断环境", "重试插件", "搜索文本", "控件列表"]
        else if (InStr(message, "图片文件不存在"))
            code := "image_missing", next := ["搜索文本", "控件列表", "截图"]
        else if (error is WindowControlTimeoutError)
            code := "control_timeout", next := ["控件列表", "搜索文本", "截图"]
        else if (InStr(message, "控件") || InStr(message, "选择器"))
            code := "control_unavailable", next := ["控件列表", "搜索文本", "按键"]
        else if (command == "浏览器")
            code := "browser_failed", next := ["变量监视", "窗口列表", "控件列表", "搜索文本"]
        else if (command == "网络请求")
            code := "request_failed", next := ["变量监视", "list_instructions"]
        else if (command == "文件读写")
            code := "file_failed", next := ["变量监视", "list_instructions"]
        else if (InStr(message, "必须") || InStr(message, "缺少参数") || InStr(message, "未知参数"))
            code := "invalid_arguments", next := ["list_instructions"]
        return JSON.stringify(Map("ok", JSON.false, "command", command, "error", message, "error_code", code, "error_location", error.What, "error_trace", SubStr(error.Stack, 1, 4000),
            "suggested_commands", next, "guidance", "先核对参数和实际状态，同一路径最多重试2次；无效时改用建议方式。插件缺失先诊断，补齐后重试加载；不要下载来源不明的DLL。已发生的操作不会自动撤销。"), 0)
    }

    static Search(name, p, item) {
        region := AiDirectControl.Region(p)
        timeout := AiDirectControl.Int(p, "timeout_ms", 3000, 0, 30000)
        interval := AiDirectControl.Int(p, "interval_ms", 300, 100, 2000)
        attempts := [], image := name == "搜索图片", method := image ? "image" : "text"
        if (image) {
            path := AiAssist._ResolveUserPath(p["path"], true)
            if (!FileExist(path))
                throw Error("图片文件不存在：" path)
            backend := StrLower(p.Get("backend", "auto"))
            if (backend == "rmt")
                backend := "native"
            if (backend != "auto" && backend != "opencv" && backend != "native")
                throw Error("backend 必须为 auto/opencv/rmt/native。")
            similar := AiDirectControl.Int(p, "similar", 85, 0, 100)
            colorMatch := p.Get("color_match", false) ? true : false
            pluginError := backend == "native" ? "" : OpenCvEnsure()
            if (pluginError != "" && backend == "opencv")
                throw Error(pluginError)
            native := backend == "native" || pluginError != ""
            if (pluginError != "")
                attempts.Push(Map("method", "opencv", "error", pluginError))
        } else if (Type(p["text"]) != "String" || Trim(p["text"]) == "")
            throw Error("text 必须为非空字符串。")
        engine := StrLower(p.Get("ocr_engine", "auto"))
        if (engine != "auto" && engine != "rapidocr" && engine != "tesseract")
            throw Error("ocr_engine 必须为 auto/rapidocr/tesseract。")
        deadline := A_TickCount + timeout
        textFallback := false, lastError := ""
        loop {
            AiDirectControl.Check(item)
            found := false, x := 0, y := 0
            if (image && !textFallback) {
                method := native ? "native_image" : "opencv_image"
                try {
                    if (native) {
                        CoordMode("Pixel", "Screen")
                        found := ImageSearch(&x, &y, region[1], region[2], region[3] - 1, region[4] - 1, "*" Round(255 * (100 - similar) / 100) " " path)
                        if (found) {
                            size := GetImageSize(path)
                            x += size[1] // 2, y += size[2] // 2
                        }
                    } else {
                        status := FindScreenImage(&x, &y, path, region[1], region[2], region[3], region[4], similar, false, colorMatch)
                        if (status < 0)
                            throw Error("OpenCV 图片搜索失败（" status "）：" GetImageLastErrorText())
                        found := status == 1
                        if (found) {
                            size := GetImageSize(path)
                            x += size[1] // 2, y += size[2] // 2
                        }
                    }
                } catch as e {
                    lastError := e.Message
                    attempts.Push(Map("method", method, "error", lastError))
                    if (backend == "auto" && !native) {
                        native := true
                        continue
                    }
                    if (p.Get("fallback_text", "") == "")
                        throw e
                }
                if (!found && backend == "auto" && !native) {
                    attempts.Push(Map("method",method,"found",JSON.false,"similar",similar,"color_match",colorMatch))
                    native := true
                    continue
                }
                if (!found && p.Get("fallback_text", "") != "") {
                    attempts.Push(Map("method", method, "found", JSON.false))
                    textFallback := true
                }
            }
            if ((!image || textFallback) && !found) {
                method := "ocr_text"
                text := image ? String(p["fallback_text"]) : p["text"]
                pattern := !image && p.Get("regex", false) ? text : "\Q" StrReplace(text, "\E", "\E\\E\Q") "\E"
                ; 与已有屏幕文字搜索共用截图、OCR与匹配定位。
                engines := engine == "auto" ? ["RapidOCR","Tesseract OCR"] : [engine == "rapidocr" ? "RapidOCR" : "Tesseract OCR"]
                for ocr in engines {
                    method := ocr == "RapidOCR" ? "rapidocr_text" : "tesseract_text"
                    try {
                        found := FindScreenText(&x,&y,region[1],region[2],region[3],region[4],pattern,"屏幕",ocr)
                        if (found)
                            break
                        if (attempts.Length < 30)
                            attempts.Push(Map("method",method,"found",JSON.false))
                    } catch as e {
                        lastError := e.Message
                        if (attempts.Length < 30)
                            attempts.Push(Map("method",method,"error",lastError))
                        if (engine != "auto")
                            throw e
                    }
                }
            }
            AiDirectControl.Check(item)
            if (found)
                return Map("found", JSON.true, "matched", JSON.true, "x", Round(x), "y", Round(y), "method", method, "attempts", attempts)
            if (A_TickCount >= deadline)
                return Map("found", JSON.false, "matched", JSON.false, "timed_out", timeout ? JSON.true : JSON.false,
                    "method", method, "attempts", attempts, "last_error",lastError,"suggested_commands", ["搜索文本", "控件列表", "截图"], "guidance", "未定位目标，不要点击；检查范围、文本或模板，按反馈调整similar/color_match/ocr_engine/等待时间，或使用控件。")
            Sleep(Min(interval, Max(1, deadline - A_TickCount)))
        }
    }

    static Controls(p, item) {
        hwnd := AiDirectControl.Int(p, "hwnd", "", 1, 0x7FFFFFFFFFFFFFFF)
        if (!DllCall("IsWindow", "Ptr", hwnd))
            throw Error("目标窗口不存在。")
        limit := AiDirectControl.Int(p, "limit", 80, 1, 150)
        filter := String(p.Get("filter", ""))
        root := WindowControl._Object(6, WindowControl._Automation(), "Ptr", hwnd)
        walker := WindowControl._Object(14, WindowControl._Automation())
        result := [], pending := [{element: root, path: []}], visited := 0, deadline := A_TickCount + 4000
        while (pending.Length && result.Length < limit && visited < 600 && A_TickCount < deadline) {
            AiDirectControl.Check(item)
            current := pending.RemoveAt(1)
            child := WindowControl._Object(4, walker, "Ptr", current.element)
            counts := Map()
            while (child && ++visited <= 600 && A_TickCount < deadline) {
                AiDirectControl.Check(item)
                key := WindowControl.Describe(child)
                key["class"] := WindowControl._StableClass(key["class"])
                identity := JSON.stringify([key["type"], key["id"], key["id"] == "" ? key["name"] : "", key["id"] == "" ? key["class"] : ""], 0)
                counts[identity] := counts.Get(identity, 0) + 1
                key["index"] := counts[identity]
                path := current.path.Clone(), path.Push(key)
                if (path.Length < 10)
                    pending.Push({element: child, path: path})
                if (filter == "" || InStr(key["name"], filter) || InStr(key["id"], filter)) {
                    selector := Map("exe", WinGetProcessName(hwnd), "windowClass", WinGetClass(hwnd), "titleContains", WinGetTitle(hwnd), "path", path)
                    entry := Map("name", key["name"], "type", key["type"], "id", key["id"], "enabled", WindowControl._Int(child, 28) ? JSON.true : JSON.false,
                        "selector", JSON.stringify(selector, 0))
                    try entry["bounds"] := WindowControl._Bounds(child)
                    result.Push(entry)
                    if (result.Length >= limit)
                        break
                }
                child := WindowControl._Object(6, walker, "Ptr", child)
            }
        }
        return Map("hwnd", hwnd, "controls", result, "truncated", pending.Length || visited >= 600 || A_TickCount >= deadline ? JSON.true : JSON.false)
    }

    static Control(p, item) {
        data := WindowControlData()
        data.Selector := String(p["selector"])
        data.ActionType := String(p["action"])
        data.TimeoutMs := AiDirectControl.Int(p, "timeout_ms", 3000, 1, 30000)
        data.TimeoutAction := "停止"
        if (data.ActionType == "点击控件") {
            element := WindowControl.Find(WindowControl.ParseSelector(data.Selector))
            if (!element || !WindowControl._Int(element, 28))
                throw Error("控件不存在或已禁用，请重新枚举。")
            if (invoke := WindowControl._Pattern(element, "invoke")) {
                ComCall(3, invoke)
                return Map("value", 1, "action", data.ActionType, "method", "uia_invoke", "guidance", "已调用控件，请读取状态或截图确认效果。")
            }
            hwnd := WindowControl._NativeHwnd(element)
            if (hwnd && WinGetClass(hwnd) == "Button") {
                PostMessage(0xF5, 0, 0, , "ahk_id " hwnd)
                return Map("value", 1, "action", data.ActionType, "method", "native_button", "guidance", "已发送控件消息，请读取状态或截图确认效果。")
            }
        }
        if (data.ActionType == "读取控件值") {
            element := WindowControl.Find(WindowControl.ParseSelector(data.Selector))
            if (!element)
                throw Error("没有找到控件，请重新枚举。")
            value := WindowControl.ProbeValue(element)
            if (!value.supported)
                throw Error(value.reason)
            return Map("value", value.value, "kind", value.kind)
        }
        value := WindowControl.Execute(data, String(p.Get("value", "")), () => item.Killed)
        return Map("value", value, "action", data.ActionType)
    }

    static Diagnose(reset, item) {
        AiDirectControl.Check(item)
        if (reset)
            OpenCvResetEnsureCache()
        cvError := OpenCvEnsure()
        ocrError := "", controlsError := ""
        try GetChineseOcr()
        catch as e
            ocrError := e.Message
        try WindowControl._Automation()
        catch as e
            controlsError := e.Message
        shmError := ""
        try {
            if (!ShmVariableMap.H_DLL || !DllCall("GetProcAddress", "Ptr", ShmVariableMap.H_DLL, "AStr", "ShmVar_GetKeys", "Ptr"))
                shmError := "共享变量插件缺少ShmVar_GetKeys接口，请更新匹配版本并重启RMT。"
        } catch as e
            shmError := e.Message
        return Map("shared_variables", Map("available", shmError == "" ? JSON.true : JSON.false, "error", shmError),
            "opencv", Map("available", cvError == "" ? JSON.true : JSON.false, "error", cvError, "directory", OpenCvDllDir()),
            "ocr", Map("available", ocrError == "" ? JSON.true : JSON.false, "error", ocrError),
            "controls", Map("available", controlsError == "" ? JSON.true : JSON.false, "error", controlsError),
            "guidance", "OpenCV不可用时可尝试搜索图片 backend=native；找图无效改搜索文本等待或控件操作。OCR不可用可枚举控件。缺失文件从RMT官方发行包修复，已有文件补齐后执行重试插件。")
    }
}
