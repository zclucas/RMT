#Requires AutoHotkey v2.0
#Include AiDirectObserve.ahk
#Include AiDirectNative.ahk
#Include AiDirectDebug.ahk

; AI 的单步运行入口：复用现有指令执行原语，仅使用内存中的运行状态。
; 不分配指令序列号、不写 DataCacheMap、不创建宏、不触发宏或 Worker 任务。
class AiDirectControl {
    static active := ""
    static sequence := 0

    static Catalog() {
        catalog := Map(
            "搜索图片", {source: "搜索", help: "在屏幕范围找图并等待，path 为已有图片绝对路径；similar=0~100默认85；backend=auto/opencv/rmt（native同rmt），auto在OpenCV未命中或不可用时尝试RMT搜图；color_match可开启OpenCV颜色比较；fallback_text 可指定找图失败后改找的文字；timeout_ms=0~30000，interval_ms=100~2000；可传截图矩形。返回 found、匹配中心坐标 x/y、method、attempts；未找到不能据此点击。", fields: "path,similar,backend,color_match,ocr_engine,fallback_text,timeout_ms,interval_ms,x,y,end_x,end_y", required: "path"},
            "搜索文本", {source: "搜索/等待", help: "OCR搜索 text（默认按字面量；regex=true按正则）；ocr_engine=auto/rapidocr/tesseract，auto未命中或报错切换引擎；等待出现后返回屏幕 x,y。timeout_ms=0~30000默认3000，interval_ms=100~2000默认300；可传截图矩形。返回 found，找不到时改用控件或观察，不要猜坐标。", fields: "text,regex,ocr_engine,timeout_ms,interval_ms,x,y,end_x,end_y", required: "text"},
            "控件列表", {source: "控件信息", help: "枚举指定 hwnd 窗口的控件，返回 name、selector、位置和可用状态；filter 可按文字过滤，limit=1~150默认80。selector来自本工具，勿编造。", fields: "hwnd,filter,limit", required: "hwnd"},
            "控件操作", {source: "控件操作", help: "selector 为控件列表返回的字符串；action=点击控件/聚焦控件/写入控件值/读取控件值/等待控件出现/检测控件存在/读取位置/宽高；写入时传 value；timeout_ms=1~30000默认3000。优先语义操作；不支持时返回错误，可改用OCR、按键或坐标。", fields: "selector,action,value,timeout_ms", required: "selector,action"},
            "诊断环境", {source: "插件诊断", help: "检查OpenCV与运行库、OCR加载、控件接口可用性，返回实际错误与替代建议；不下载、不安装。", fields: "", required: ""},
            "重试插件", {source: "插件诊断", help: "文件或依赖已补齐后，清除OpenCV失败缓存并重新加载，再诊断；不会下载或安装软件。", fields: "", required: ""},
            "窗口列表", {source: "窗口信息", help: "列出可见窗口及屏幕客户区坐标。坐标为屏幕像素。", fields: "", required: ""},
            "激活窗口", {source: "窗口操作", help: "激活窗口；hwnd 必须来自窗口列表。", fields: "hwnd", required: "hwnd"},
            "移动", {source: "移动", help: "移动到屏幕绝对坐标 x,y；speed 1~100，默认90。", fields: "x,y,speed", required: "x,y"},
            "点击", {source: "按键/移动", help: "在屏幕坐标 x,y 点击；button=LButton/RButton/MButton；count=1或2。", fields: "x,y,button,count,speed", required: "x,y"},
            "拖拽", {source: "移动Pro", help: "从屏幕 x,y 按住左键拖到 end_x,end_y，结束或失败时松开。", fields: "x,y,end_x,end_y,speed", required: "x,y,end_x,end_y"},
            "按键", {source: "按键", help: "keys 为 AHK 键名数组，如 [Ctrl,s]，组合按下后逆序松开。hold_ms=1~2000。只接受键名，不接受脚本或 Send 表达式。", fields: "keys,hold_ms", required: "keys"},
            "输入文本", {source: "输出", help: "将 text 作为纯文本输入当前焦点，不解释快捷键。", fields: "text", required: "text"},
            "等待", {source: "等待", help: "condition=duration/window_exists/window_closed/file_exists/file_deleted；duration 的 ms=0~30000，其余 target 为窗口 HWND 或文件绝对路径；timeout_ms=1~30000，interval_ms=20~1000。返回 matched/timed_out。", fields: "condition,ms,target,timeout_ms,interval_ms", required: "condition"},
            "Excel读取", {source: "Excel", help: "使用现有 Excel DLL 读取，不生成配置。path 为绝对工作簿路径；sheet 为工作表名或1起序号，默认1；row/column 为1起坐标；end_row/end_column 默认起点，最多400格。返回按行排列的 values。", fields: "path,sheet,row,column,end_row,end_column", required: "path,row,column"},
            "Excel写入", {source: "Excel", help: "使用现有 Excel DLL 写入并保存。path/sheet/row/column 同读取；values 必须为二维数组，最多400格，字符串以等号开头时是公式；可随后 Excel读取验证。", fields: "path,sheet,row,column,values", required: "path,row,column,values"},
            "截图", {source: "截图/AI判断", help: "截取屏幕矩形 x,y,end_x,end_y（省略时主屏全屏），保存 PNG 并返回 OCR 文字及 ocr_items 屏幕坐标，可用于定位文字后点击。path 可指定输出绝对路径。OCR不是视觉判断，判断图片请调用 AI判断。", fields: "x,y,end_x,end_y,path", required: ""},
            "AI判断", {source: "AI判断", help: "调用当前已配置的模型判断屏幕图像或OCR文字。question 为问题；options 至少两行，每行 标签|返回值；source=image（默认，需要视觉模型）或text（OCR）；屏幕矩形 x,y,end_x,end_y 可省略。返回 value，失败不会假定为否。timeout_ms=1000~60000。", fields: "question,options,source,x,y,end_x,end_y,timeout_ms", required: "question,options"}
        )
        AiDirectNative.AddCatalog(catalog)
        AiDirectDebug.AddCatalog(catalog)
        return catalog
    }

    static Describe(args) {
        catalog := this.Catalog()
        name := args.Get("command", "")
        if (name != "") {
            if (!catalog.Has(name))
                throw Error("不支持的直接指令：" name)
            schema := catalog[name]
            if (AiDirectNative.Names().Has(name))
                schema.defaults := AiDirectNative.Defaults(name)
            if (AiDirectNative.Names().Has(name))
                schema.choices := AiDirectNative.Choices(name)
            if (AiDirectNative.Names().Has(name))
                schema.field_help := AiDirectNative.FieldHelp(name)
            return JSON.stringify(Map("ok", JSON.true, "command", name, "schema", schema, "requires_full_access", JSON.true), 0)
        }
        return JSON.stringify(Map("ok", JSON.true, "instructions", catalog, "coverage", AiDirectNative.Coverage(catalog), "requires_full_access", JSON.true), 0)
    }

    static Cancel() {
        if (IsObject(this.active))
            this.active.Killed := true
        scope := DirectCommandScope()
        if (IsObject(scope) && scope.HasOwnProp("cancelItem"))
            scope.cancelItem.Killed := true
    }

    static Execute(args) {
        if (!AiAssist.CanRun())
            throw Error("直接操作电脑需要「AI 设置 → 写入权限 → 完全访问」。")
        if (IsObject(this.active))
            throw Error("上一条直接指令仍在运行。")
        name := args.Get("command", "")
        catalog := this.Catalog()
        if (!catalog.Has(name))
            throw Error("不支持的直接指令：" name)
        p := args.Get("parameters", Map())
        if (Type(p) != "Map")
            throw Error("parameters 必须是 JSON 对象。")
        spec := catalog[name]
        for key, value in p {
            if (!InStr("," spec.fields ",", "," key ","))
                throw Error("未知参数：" key)
        }
        for key in StrSplit(spec.required, ",") {
            if (key != "" && !p.Has(key))
                throw Error("缺少参数：" key)
        }
        this.sequence += 1
        item := MacroItem()
        item.ID := "ai-direct-" this.sequence
        item.Mode := "AHK Send"
        item.BindWindow := ""
        table := {ID: item.ID, Index: 0, Items: [item], Folds: []}
        this.active := item
        try {
            if (!AiAssist._NeedApproval("直接执行「" name "」`n" JSON.stringify(p, 0)))
                throw Error("用户拒绝审批。")
            this.Check(item)
            started := A_TickCount
            result := this.Run(name, p, table, item)
            this.Check(item)
            result["ok"] := JSON.true
            result["command"] := name
            result["elapsed_ms"] := A_TickCount - started
            AiDirectDebug.Record(name, p, result)
            return JSON.stringify(result, 0)
        } catch as e {
            AiDirectDebug.Record(name, p, Map("ok", JSON.false, "error", e.Message))
            throw e
        } finally {
            ; 组合键中途取消/异常，也必须逆序松开；拖拽本身另有 finally。
            keys := []
            for key in item.HoldKey
                keys.Push(key)
            loop keys.Length
                try {
                    key := keys[keys.Length - A_Index + 1]
                    if (item.HoldKey[key] == "Normal")
                        SendNormalKey(key, 0, table, 1)
                }
            try ReleaseTableItemHoldKeys(table, 1)
            this.active := ""
        }
    }

    static Check(item) {
        if (item.Killed)
            throw Error("操作已取消；已发生的操作不会自动撤销。")
        if (!AiAssist.CanRun()) {
            item.Killed := true
            throw Error("直接操作权限已撤销。")
        }
    }

    static Int(p, key, fallback, minimum, maximum) {
        value := p.Get(key, fallback)
        if (!IsInteger(value) || value < minimum || value > maximum)
            throw Error(key " 必须为 " minimum "~" maximum " 的整数。")
        return Integer(value)
    }

    static Point(p, xKey := "x", yKey := "y") {
        x := this.Int(p, xKey, "", SysGet(76), SysGet(76) + SysGet(78) - 1)
        y := this.Int(p, yKey, "", SysGet(77), SysGet(77) + SysGet(79) - 1)
        return [x, y]
    }

    static Region(p) {
        count := 0
        for field in ["x", "y", "end_x", "end_y"]
            count += p.Has(field) ? 1 : 0
        if (!count)
            return [0, 0, A_ScreenWidth, A_ScreenHeight]
        if (count != 4)
            throw Error("截图范围需同时填写 x,y,end_x,end_y。")
        start := this.Point(p)
        endX := this.Int(p, "end_x", "", start[1] + 1, SysGet(76) + SysGet(78))
        endY := this.Int(p, "end_y", "", start[2] + 1, SysGet(77) + SysGet(79))
        return [start[1], start[2], endX, endY]
    }

    static Run(name, p, table, item) {
        if (AiDirectNative.Names().Has(name))
            return AiDirectNative.Execute(name, p, table, item)
        if (AiDirectDebug.IsCommand(name))
            return AiDirectDebug.Execute(name, p, item)
        switch name {
            case "搜索图片", "搜索文本":
                return AiDirectObserve.Search(name, p, item)
            case "控件列表":
                return AiDirectObserve.Controls(p, item)
            case "控件操作":
                return AiDirectObserve.Control(p, item)
            case "诊断环境", "重试插件":
                return AiDirectObserve.Diagnose(name == "重试插件", item)
            case "窗口列表":
                windows := []
                for hwnd in WinGetList() {
                    try {
                        title := WinGetTitle(hwnd)
                        if (title == "" || !DllCall("IsWindowVisible", "Ptr", hwnd))
                            continue
                        WinGetClientPos(&x, &y, &w, &h, hwnd)
                        windows.Push(Map("hwnd", hwnd, "title", title, "process", WinGetProcessName(hwnd), "x", x, "y", y, "width", w, "height", h))
                        if (windows.Length >= 80)
                            break
                    }
                }
                return Map("windows", windows)
            case "激活窗口":
                hwnd := this.Int(p, "hwnd", "", 1, 0x7FFFFFFFFFFFFFFF)
                if (!DllCall("IsWindow", "Ptr", hwnd))
                    throw Error("目标窗口已不存在。")
                WinActivate(hwnd)
                if (!WinWaitActive(hwnd, , 2))
                    throw Error("无法激活目标窗口。")
                return Map("hwnd", hwnd, "title", WinGetTitle(hwnd))
            case "移动", "点击", "拖拽":
                point := this.Point(p)
                speed := this.Int(p, "speed", 90, 1, 100)
                if (name == "拖拽") {
                    end := this.Point(p, "end_x", "end_y")
                    ok := MouseDragByStrategy(table, 1, "AHK Send", "绝对移动", point[1], point[2], end[1], end[2], speed)
                } else {
                    count := name == "点击" ? this.Int(p, "count", 1, 1, 2) : 0
                    button := p.Get("button", "LButton")
                    if (button != "LButton" && button != "RButton" && button != "MButton")
                        throw Error("button 必须为 LButton/RButton/MButton。")
                    ok := MouseMoveByStrategy("AHK Send", "绝对移动", point[1], point[2], speed, button == "LButton" ? count : 0, false, item)
                    if (ok && count && button != "LButton")
                        ok := MouseClickByKeyMode("AHK Send", count, button)
                }
                if (!ok)
                    throw Error("鼠标操作未完成。")
                CoordMode("Mouse", "Screen")
                MouseGetPos(&x, &y)
                return Map("x", x, "y", y)
            case "按键":
                keys := p["keys"]
                if (Type(keys) != "Array" || keys.Length < 1 || keys.Length > 8)
                    throw Error("keys 必须包含1~8个键名。")
                seen := Map()
                for key in keys {
                    if (Type(key) != "String" || !RegExMatch(key, "^[a-zA-Z0-9_]+$") || !GetKeyVK(key) || seen.Has(StrLower(key)))
                        throw Error("无效或重复的键名。")
                    seen[StrLower(key)] := true
                }
                hold := this.Int(p, "hold_ms", 50, 1, 2000)
                SendKeysDown(keys, table, 1, SendNormalKey)
                InterruptibleSleep(table, 1, hold, false)
                SendKeysUp(keys, table, 1, SendNormalKey)
                return Map("keys", keys)
            case "输入文本":
                if (Type(p["text"]) != "String" || StrLen(p["text"]) > 10000)
                    throw Error("text 必须是最多10000字符的字符串。")
                SendText(p["text"])
                return Map("characters", StrLen(p["text"]))
            case "等待":
                return this.Wait(p, table, item)
            case "Excel读取", "Excel写入":
                return this.Excel(name, p, item)
            case "截图", "AI判断":
                region := this.Region(p)
                if (name == "AI判断") {
                    source := p.Get("source", "image")
                    if (source != "image" && source != "text")
                        throw Error("source 必须为 image 或 text。")
                    data := AiDecisionData()
                    data.Source := source == "image" ? "屏幕内容" : "屏幕文字"
                    data.Question := String(p["question"])
                    options := p["options"]
                    if (Type(options) == "Array") {
                        lines := ""
                        for option in options {
                            if (Type(option) == "Map")
                                line := String(option.Get("label", "")) "|" String(option.Get("value", ""))
                            else if (Type(option) == "String")
                                line := option
                            else
                                throw Error("options 数组必须包含字符串或 label/value 对象。")
                            lines .= (lines == "" ? "" : "`n") line
                        }
                        options := lines
                    }
                    if (Type(options) != "String")
                        throw Error("options 必须为选项文本或选项数组。")
                    data.Options := options
                    data.Region := Format("{},{},{},{}", region*)
                    data.TimeoutMs := this.Int(p, "timeout_ms", 30000, 1000, 60000)
                    data.TimeoutAction := "停止"
                    try value := AiDecision.Execute(data, (text) => text, () => item.Killed, &timedOut, "", MainSoftData)
                    catch as e {
                        if (source == "image" && RegExMatch(e.Message, "HTTP (400|422)\b"))
                            throw Error(e.Message "；当前模型或接口可能不支持图像输入，可改用视觉模型，或 source=text 仅判断截图文字。")
                        throw e
                    }
                    if (timedOut)
                        throw Error("截图判断超时。")
                    return Map("value", value, "source", source)
                }
                output := p.Has("path") ? p["path"] : RmtCacheDir() "\AI\screen-" A_Now "-" this.sequence ".png"
                path := AiAssist._ResolveUserPath(output, true)
                if (StrLower(SubStr(path, -4)) != ".png")
                    throw Error("截图输出必须为 .png。")
                SplitPath(path, , &dir)
                DirCreate(dir)
                bitmap := AiDecision.CaptureRegion(region)
                try {
                    if (Gdip_SaveBitmapToFile(bitmap, path) != 0)
                        throw Error("截图保存失败。")
                    text := "", ocrError := "", ocrItems := []
                    try {
                        items := GetBitmapTextObjArr(bitmap)
                        for word in (items == "" ? [] : items) {
                            text .= (text == "" ? "" : "`n") word.Text
                            if (ocrItems.Length < 200) {
                                xs := [], ys := []
                                for point in word.boxPoint {
                                    xs.Push(point.x + region[1])
                                    ys.Push(point.y + region[2])
                                }
                                ocrItems.Push(Map("text", word.Text, "x", Round((Min(xs*) + Max(xs*)) / 2), "y", Round((Min(ys*) + Max(ys*)) / 2),
                                    "left", Min(xs*), "top", Min(ys*), "right", Max(xs*), "bottom", Max(ys*)))
                            }
                        }
                    } catch as e
                        ocrError := e.Message
                } finally Gdip_DisposeImage(bitmap)
                return Map("path", path, "x", region[1], "y", region[2], "width", region[3] - region[1], "height", region[4] - region[2],
                    "ocr_text", SubStr(text, 1, 16000), "ocr_items", ocrItems, "ocr_error", ocrError)
        }
    }

    static Wait(p, table, item) {
        kind := p["condition"]
        if (kind == "duration") {
            ms := this.Int(p, "ms", "", 0, 30000)
            InterruptibleSleep(table, 1, ms)
            return Map("matched", JSON.true, "timed_out", JSON.false)
        }
        if (!InStr(",window_exists,window_closed,file_exists,file_deleted,", "," kind ","))
            throw Error("未知等待条件。")
        target := p.Get("target", "")
        if (InStr(kind, "window_") == 1)
            target := this.Int(p, "target", "", 1, 0x7FFFFFFFFFFFFFFF)
        else
            target := AiAssist._ResolveUserPath(target, true)
        timeout := this.Int(p, "timeout_ms", 10000, 1, 30000)
        interval := this.Int(p, "interval_ms", 100, 20, 1000)
        deadline := A_TickCount + timeout
        loop {
            this.Check(item)
            exists := InStr(kind, "window_") == 1 ? !!DllCall("IsWindow", "Ptr", target) : !!FileExist(target)
            matched := kind == "window_closed" || kind == "file_deleted" ? !exists : exists
            if (matched || A_TickCount >= deadline)
                return Map("matched", matched ? JSON.true : JSON.false, "timed_out", matched ? JSON.false : JSON.true)
            InterruptibleSleep(table, 1, Min(interval, Max(1, deadline - A_TickCount)))
        }
    }

    static Excel(name, p, item) {
        path := AiAssist._ResolveUserPath(p["path"], true)
        if (!FileExist(path) || !RegExMatch(path, "i)\.(xlsx|xlsm|xlsb|xls)$"))
            throw Error("工作簿不存在或扩展名无效。")
        row := this.Int(p, "row", "", 1, 1048576)
        col := this.Int(p, "column", "", 1, 16384)
        sheet := p.Get("sheet", 1)
        if ((Type(sheet) != "String" && !IsInteger(sheet)) || sheet == "")
            throw Error("sheet 必须为工作表名称或1起序号。")
        write := name == "Excel写入"
        if (write) {
            values := p["values"]
            if (Type(values) != "Array" || values.Length < 1)
                throw Error("values 必须为非空二维数组。")
            size := 0, width := 0
            for line in values {
                if (Type(line) != "Array" || !line.Length)
                    throw Error("values 的每一项必须为非空行数组。")
                width := Max(width, line.Length)
                for cell in line {
                    if (IsObject(cell))
                        throw Error("单元格只接受字符串或数字。")
                }
                size += line.Length
            }
            if (size > 400 || row + values.Length - 1 > 1048576 || col + width - 1 > 16384)
                throw Error("写入范围越界或超过400格。")
            endRow := row, endCol := col
        } else {
            endRow := this.Int(p, "end_row", row, row, 1048576)
            endCol := this.Int(p, "end_column", col, col, 16384)
            if ((endRow - row + 1) * (endCol - col + 1) > 400)
                throw Error("单次最多读取400格。")
            values := ""
        }
        if (!ExcelDllRun(path, sheet, "RowRange", write, row, col, endRow, endCol, values, &raw, item, true))
            throw Error("Excel 操作已取消或未完成；写入是否已保存请重新读取核对。")
        result := Map("path", path, "sheet", sheet, "row", row, "column", col)
        if (write)
            result["written_cells"] := size
        else {
            rows := [], width := endCol - col + 1
            for cell in raw {
                if (!rows.Length || rows[-1].Length == width)
                    rows.Push([])
                rows[-1].Push(cell)
            }
            result["values"] := rows
        }
        return result
    }
}
