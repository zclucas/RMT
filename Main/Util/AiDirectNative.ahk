#Requires AutoHotkey v2.0

; 复用单条指令处理器；data 是本次调用的类型化参数，不是持久化指令配置。
class AiDirectNative {
    static Names() {
        static names := Map(
            "变量", "赋值、删除变量；数组长度必须一致。",
            "手柄", "复用按键指令发送虚拟手柄按钮点击或轴值；KeyName必须以Joy开头。点击后松开，轴操作结束回中；依赖现有ViGEm驱动，不自动安装。",
            "运行", "仅直接打开已有exe程序；Target为完整exe路径，Mode必须不等待。不接受命令行或脚本。",
            "运行Pro", "仅直接打开已有exe程序；Target为完整exe路径，Mode必须不等待。不接受命令行或脚本。",
            "提示", "复用软件弹窗、临时提示、区域高亮等辅助反馈，最多30秒；音频及倒计时不阻塞等待。",
            "运算", "使用现有表达式计算器，不是脚本执行器。",
            "文本处理", "Type=文本分割/文本提取/文本替换/时间戳处理/去除空格/大小写转换/文本统计/文本拼接。",
            "数组", "Type=创建/克隆/删除/包含/取值/赋值/插入/追加/移除/移除最后/反转/长度。",
            "变量提取", "从屏幕、窗口或剪切板文字提取变量；SearchCount限1~10。原始文本字符串可改用文本处理的文本提取。",
            "网络请求", "GET/POST/PUT/DELETE；返回状态码、响应和错误。非2xx不是目标成功。",
            "浏览器", "复用浏览器指令；不允许执行JavaScript或注入脚本。桥接不可用时可用控件、OCR、键鼠。",
            "进程管理", "复用进程查询、列出和管理；先查询目标，再决定操作。",
            "文件读写", "读写文本文件；Excel请用Excel读取/Excel写入。读取文件必须已存在。",
            "窗口信息", "查询窗口信息，SearchValue使用实际窗口绑定。",
            "窗口操作", "窗口移动、缩放、置顶等；先窗口列表确认目标，操作后再查询验证。",
            "按键检测", "检测键鼠状态并写入VarName。",
            "手柄检测", "检测手柄按键或轴状态并写入VarName。",
            "后台鼠标", "向指定窗口发送鼠标操作；仅允许点击/双击/滚轮，避免遗留按下状态。",
            "后台按键", "向指定窗口发送点击按键；不允许独立按下或松开。",
            "增量移动", "复用现有增量鼠标移动。返回mouse_before/mouse_after/mouse_delta实际屏幕坐标；相对输入受系统加速影响，不应仅凭截图判断光标位置。",
            "翻译", "复用现有翻译服务，返回译文及实际错误。",
            "YOLO检测", "复用现有YOLO检测；模型或插件缺失会返回实际错误。",
            "时间", "指定时刻等待或区间判断；直接等待最多30秒。",
            "输入", "现有交互输入弹窗；限时30秒，用户输入后返回结果。",
            "等待确定", "现有确认弹窗；限时30秒，不暂停其他宏。")
        return names
    }

    static AddCatalog(catalog) {
        for name, help in this.Names()
            catalog[name] := {source: name, help: help " parameters={data:{字段:值}}，先单独查询本指令取得defaults；只填需要覆盖的字段，字段名及大小写须一致。结果包含输出变量和消息；executed仅表示处理器返回，必须核验实际效果。", fields: "data", required: "data"}
    }

    static Coverage(catalog) {
        aliases := Map("间隔", "等待", "搜索", "搜索图片/搜索文本", "搜索Pro", "搜索图片/搜索文本",
            "搜索All", "搜索文本/控件列表", "搜索Combo", "搜索图片/搜索文本", "移动Pro", "拖拽", "输出", "输入文本",
            "Excel", "Excel读取/Excel写入", "控件信息", "控件列表", "抓图", "截图")
        result := Map()
        for name in MacroCommandActions() {
            if (catalog.Has(name))
                result[name] := Map("status", "direct", "command", name)
            else if (aliases.Has(name))
                result[name] := Map("status", "adapted", "command", aliases[name], "note", "按单步语义提供；嵌套分支、批量模式由AI按反馈编排。")
            else
                result[name] := Map("status", "context_only", "reason", "仍依赖宏/设备/界面上下文，未开放直接执行；流程由AI按单步反馈决定，既有宏可用调试器检查。")
        }
        return result
    }

    static Defaults(name) {
        source := name == "手柄" ? "按键" : name
        if (!MySoftData.DataClassMap.Has(source))
            throw Error("指令类型尚未初始化：" name)
        data := MySoftData.DataClassMap[source]()
        if (name == "文件读写")
            data.OperMode := "读取全部内容"
        if (name == "后台按键")
            data.Type := "点击"
        result := Map()
        for key, value in data.OwnProps() {
            if (key != "SerialStr" && !InStr(key, "Macro"))
                result[key] := value
        }
        return result
    }

    static Choices(name) {
        switch name {
            case "时间": return Map("SubMode", ["等待", "区间判断"])
            case "YOLO检测": return Map("Source", Yolo.Sources, "Device", Yolo.Devices, "ActionType", Yolo.Actions)
            case "变量提取": return Map("ExtractType", ["屏幕", "剪切板", "窗口"])
            case "浏览器": return Map("ActionType", BrowserActions.Names, "BrowserType", BrowserActions.BrowserTypes)
            case "进程管理": return Map("Action", ProcessManage.Actions, "MatchBy", ProcessManage.MatchModes)
            case "翻译": return Map("Source", TranslateCommand.Sources, "Engine", TranslateCommand.Engines, "Device", TranslateCommand.Devices)
            case "文本处理": return Map("Type", ["文本分割", "文本提取", "文本替换", "时间戳处理", "去除空格", "大小写转换", "文本统计", "文本拼接"])
            case "文件读写": return Map("OperType", ["读取文件", "写入文件"], "OperMode", ["读取全部内容", "逐行读取", "指定行", "覆盖写入", "追加写入", "追加写入-行", "行号自增"])
            case "数组": return Map("Type", ["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"])
            case "输入": return Map("Type", InputTypeKeys())
            case "提示": return Map("Type", PromptTypes())
        }
        return Map()
    }

    static FieldHelp(name) {
        switch name {
            case "浏览器": return Map("outputs", "获取标题、获取网址等普通动作使用SaveVar接收结果，并写SaveVar_Success/_Error。标签页信息使用PageTitleVar/PageUrlVar/PageIdVar等；获取标题/获取网址兼容对应Page变量。只需标题时勿额外要求标签页ID。后台打开用Headless=1、独立UserDataDir；点击提交后等待文字/元素，再读取标题和结果。元素信息可能匹配多个标签页，先用TargetRef或更具体选择器定位。")
            case "手柄", "按键": return Map("gamepad", "手柄配置复用kind=按键（手柄为别名）。按钮KeyType=点击、KeyName=JoyA/B/X/Y等；轴需IsAxis=1、KeyName=JoyAxisLX/LY/RX/RY/LT/RT、AxisValue。摇杆-100~100，扳机0~100。单次手柄操作以HoldTime毫秒保持后回中，范围1~2000；配置模式的轴持续保持至后续回中或宏结束。普通按键的KeyName使用键鼠键名。")
            case "变量": return Map("assignment", "赋值必须填CopyVariableArr（字符串字面量/数值/变量引用），MinVariableArr和MaxVariableArr只用于随机数值。示例：ToggleArr=[1],OperaTypeArr=[赋值],VariableArr=[Count],CopyVariableArr=[123],MinVariableArr=[0],MaxVariableArr=[10]。ToggleArr=0跳过该行；六个数组长度一致。IsIgnoreExist=0允许覆盖。字面花括号须写/{和/}，例如JSON用/{.../}包住内容；未转义的{名称}按变量引用处理。标量删除用变量，数组删除用数组指令。")
            case "运算": return Map("expression", "ToggleArr、UpdateNameArr、ExpressionArr长度一致；启用行ToggleArr=1。表达式用{变量名}引用数值，字符串不能参与数值运算。示例UpdateNameArr=[Total],ExpressionArr=[{Count}*2]。")
            case "数组": return Map("array", "Name是目标数组名；创建用InitArr。追加/赋值/插入用ArgsName，ArgsType=变量或值时填数值或裸变量名（例如Count），单层{Count}会规范化为裸名；ArgsType=数组时填数组名。取值的1起下标用ArgsIndex，结果用SaveName；长度结果也用SaveName。MainIndex=0表示顶层数组。用变量监视核对数组内容。")
            case "时间": return Map("time", "等待：SubMode=等待，Param2=时长时Param1填秒数或时:分:秒；Param2=时刻时Param1填时:分:秒；Param2=时间戳时Param1填Unix毫秒时间戳。Seconds/Hour/Min/Sec不是等待时长输入；Timeout为毫秒上限。区间判断：Param1开始、Param2结束、Param5=时刻/时间戳，Param4=跳过/终止/等待；没有结果变量，直接执行另返回in_range布尔值，不能仅凭executed判断区间为真。")
            case "文件读写": return Map("file", "文本写入用OperType=写入文件、OperMode=覆盖写入/追加写入、FilePath、Content；读取用读取文件、读取全部内容、SaveName。写入后读取验证，文件不存在会失败。")
            case "网络请求": return Map("http", "Url、Method、TimeoutMs；StatusVar/ResponseVar/ErrorVar接收状态码、正文与错误。非2xx为失败，修正URL/参数再重试；变量监视核验实际状态码和响应。")
            case "进程管理": return Map("outputs", "检测进程/结束进程的结果写ResultVar（1/0）；ExistVar仅在进程信息动作写入。列出进程用ResultArray。进程信息可写NameVar/PidVar/PathVar/ExistVar等。")
            case "后台按键": return Map("keyboard", "直接执行Type只能为点击，FrontStr填窗口绑定或HWND字符串，KeyArr填键名数组如[Space]。目标控件应先聚焦，再读实际输出核验，未生效可换控件操作。配置模式另可按下/松开。")
            case "变量提取": return Map("extract", "ExtractType仅屏幕/剪切板/窗口；ExtractStr是模板，&x提取数值、&c提取文字（例如alpha &x），不是正则。ToggleArr与VariableArr按提取项顺序对应。原始字符串用文本处理：Type=文本提取,Name=alpha 123,ArgsType=数字提取,SaveName=Numbers，结果为数组。")
            case "YOLO检测":
                models := []
                try models := YoloModelStore.List()
                return Map("models", models, "image", "ModelName从models选择已登记模型。后台检测可用Source=图片文件、ImagePath=已有图片绝对路径、ActionType=无动作。结果coordinateSpace=image，检测框为图片像素坐标，不能当屏幕坐标点击。屏幕模式仍用Region。核验CountVar和ResultVar中的类别、置信度、框及ErrorVar，不能只看executed。")
            case "文本处理":
                modes := Map()
                for kind in TextOpsTypeNames()
                    modes[kind] := TextOpsModes(kind)
                return Map("text", "文本拼接用ArgsName和SaveName；文本替换用Name、Search、Replace、MatchType=普通文本、SaveName。ArgsType按modes_by_type取值；省略时按当前Type选默认子类型。原始字面花括号用/{和/}，变量用{名称}引用。", "modes_by_type", modes)
        }
        return Map()
    }

    static ContextDefaults(name, data, values) {
        ; 数组的数值/变量输入使用裸名；兼容模型常用的单层变量引用写法。
        if (name == "数组" && data.ArgsType == "变量或值" && RegExMatch(String(data.ArgsName), "^\{([^{}]+)\}$", &reference))
            data.ArgsName := reference[1]
        if (name == "浏览器" && data.SaveVar == "")
            data.SaveVar := BrowserResultVariable(data, data.ActionType)
        if (name == "文本处理" && (!values.Has("ArgsType") || values["ArgsType"] == "") && TextOpsModes(data.Type).Length)
            data.ArgsType := TextOpsDefaultMode(data.Type)
    }

    static ValidateContext(name, data) {
        if (name != "文本处理" || data.HasOwnProp("LegacyTextProcess"))
            return
        if (data.Type == "文本拼接" && data.ArgsType == "拼接文本")
            return
        field := data.Type == "文本替换" ? "MatchType" : "ArgsType"
        for mode in TextOpsModes(data.Type) {
            if (data.%field% == mode)
                return
        }
        throw Error(field "取值无效，请按field_help的modes_by_type选择「" data.Type "」子类型。")
    }

    static Apply(target, values, path := "data", depth := 0) {
        if (Type(values) != "Map" || depth > 5)
            throw Error(path " 必须是参数对象。")
        for key, value in values {
            if (key == "SerialStr" || InStr(key, "Macro") || !target.HasOwnProp(key))
                throw Error("未知参数或禁止的流程字段：" path "." key)
            original := target.%key%
            if (Type(value) == "Map") {
                if (!IsObject(original) || Type(original) == "Array")
                    throw Error(path "." key " 参数类型不匹配。")
                this.Apply(original, value, path "." key, depth + 1)
            } else {
                if (IsObject(original) && Type(original) != Type(value))
                    throw Error(path "." key " 参数类型不匹配。")
                if (Type(value) == "Array" && value.Length > 400)
                    throw Error(path "." key " 最多400项。")
                target.%key% := value
            }
        }
    }

    static Execute(name, p, table, item) {
        data := MySoftData.DataClassMap[name == "手柄" ? "按键" : name]()
        if (name == "文件读写")
            data.OperMode := p["data"].Get("OperType", "读取文件") == "写入文件" ? "覆盖写入" : "读取全部内容"
        if (name == "后台按键")
            data.Type := "点击"
        this.Apply(data, p["data"])
        this.ContextDefaults(name, data, p["data"])
        for field, choices in this.Choices(name) {
            found := false
            for choice in choices {
                if (data.%field% == choice)
                    found := true
            }
            if (!found)
                throw Error(field " 必须使用list_instructions返回的choices。")
        }
        if (name == "变量") {
            for field in ["OperaTypeArr", "VariableArr", "CopyVariableArr", "MinVariableArr", "MaxVariableArr"] {
                if (data.%field%.Length != data.ToggleArr.Length)
                    throw Error("变量指令各参数数组长度必须一致。")
            }
        }
        if (name == "运算" && (data.ToggleArr.Length != data.UpdateNameArr.Length || data.ToggleArr.Length != data.ExpressionArr.Length))
            throw Error("运算指令各参数数组长度必须一致。")
        NormalizeCommandData(name, data)
        this.ValidateContext(name, data)
        if (name == "手柄") {
            if (!RegExMatch(data.KeyName, "^Joy(?:A|B|X|Y|LB|RB|LT|RT|LS|RS|Back|Start|Home|Dpad(?:Up|Down|Left|Right)|Axis(?:LX|LY|RX|RY|LT|RT))$"))
                throw Error("KeyName 必须为有效Joy手柄按钮或轴名。")
            if (data.KeyType != "点击" && !data.IsAxis)
                throw Error("手柄按钮直接操作必须为点击。")
            if (!IsInteger(data.Count) || data.Count < 1 || data.Count > 20 || !IsInteger(data.HoldTime) || data.HoldTime < 1 || data.HoldTime > 2000
                || !IsInteger(data.IntervalTime) || data.IntervalTime < 0 || data.IntervalTime > 2000)
                throw Error("手柄Count必须1~20，HoldTime必须1~2000，IntervalTime必须0~2000。")
            if (data.IsAxis && (!InStr(data.KeyName,"JoyAxis") || !IsNumber(data.AxisValue) || Abs(data.AxisValue) > 100))
                throw Error("手柄轴名及AxisValue必须有效，范围-100~100。")
            if (!IsViGEmInstalled())
                throw Error("ViGEm驱动不可用，请诊断环境；手柄输出需要现有驱动。")
        }
        if (name == "运行" || name == "运行Pro") {
            target := AiAssist._ResolveUserPath(data.Target, true)
            if (!RegExMatch(target, "i)\.exe$") || !FileExist(target) || data.Mode != "不等待")
                throw Error("运行只接受已有exe完整路径，Mode必须为不等待；禁止脚本或命令行代替操作。")
            data.Target := '"' target '"'
        }
        if (name == "提示") {
            data.Duration := Min(Max(data.Duration, 1), 30000)
            data.WaitEnd := "不等待"
            data.AudioWait := "不等待"
        }
        if (name == "输入" || name == "等待确定") {
            data.PauseType := "暂停当前宏"
            data.TimeoutAction := "无"
            if (data.HasOwnProp("TerminateType"))
                data.TerminateType := "终止当前宏"
            if (data.HasOwnProp("PauseBtnType"))
                data.PauseBtnType := "暂停当前宏"
        }
        if (name == "窗口信息" || name == "窗口操作") {
            query := GetParamsWinInfoStr(GetReplaceVarText(table, 1, data.SearchValue))
            if (query == "" || !WindowMatchedHandles(query).Length)
                throw Error("未找到目标窗口，请先查询窗口列表并核对SearchValue。")
        }
        ; 禁止嵌套宏分支、任意脚本和无限等待；数据保持原生字段语义。
        for key, value in data.OwnProps() {
            if (InStr(key, "Macro") && value != "")
                throw Error("直接指令不允许执行宏分支：" key)
        }
        if (name == "浏览器" && (data.JsCode != "" || data.ActionType == "执行JS" || InStr(data.ActionType, "脚本") || InStr(data.ActionType, "JavaScript")))
            throw Error("直接操作禁止生成或执行脚本；请使用浏览器元素、控件或键鼠指令。")
        if (name == "文件读写") {
            if (InStr(data.OperType, "Excel"))
                throw Error("Excel请使用Excel读取或Excel写入。")
            data.FilePath := AiAssist._ResolveUserPath(GetReplaceVarText(table, 1, data.FilePath), true)
            if (FileIOIsReadType(FileIONormType(data.OperType)) && !FileExist(data.FilePath))
                throw Error("读取文件不存在：" data.FilePath)
        }
        if (name == "后台鼠标" && data.OperateType != "点击" && data.OperateType != "双击")
            throw Error("后台鼠标直接操作必须为点击或双击。")
        if (name == "后台按键" && data.Type != "点击")
            throw Error("后台按键直接操作必须为点击。")
        if (name == "变量提取" && (!IsInteger(data.SearchCount) || data.SearchCount < 1 || data.SearchCount > 10))
            throw Error("SearchCount 必须为1~10。")
        if (data.HasOwnProp("TimeoutMs")) {
            if (!IsNumber(data.TimeoutMs) || data.TimeoutMs <= 0)
                data.TimeoutMs := 30000
            data.TimeoutMs := Min(data.TimeoutMs, 30000)
        }
        if (name == "时间" && TimeNormSubMode(data) == "等待" && Trim(String(data.Param1)) == "")
            throw Error("时间等待缺少Param1目标时间或时长，请查询list_instructions的field_help；Seconds不是等待时长输入。")
        if (name == "时间")
            data.Timeout := data.Timeout > 0 ? Min(data.Timeout, 30000) : 30000
        if (name == "等待确定")
            data.PauseType := "暂停当前宏"
        if (name == "浏览器" && data.SaveVar == "")
            data.SaveVar := "AI浏览器结果"
        if (name == "翻译" && data.ErrorVar == "")
            data.ErrorVar := "AI翻译错误"
        if (name == "YOLO检测") {
            if (data.ErrorVar == "")
                data.ErrorVar := "AI检测错误"
            if (data.ResultVar == "")
                data.ResultVar := "AI检测结果"
        }
        if (name == "进程管理") {
            if (data.ResultVar == "")
                data.ResultVar := "AI进程结果"
            if (data.ResultArray == "")
                data.ResultArray := "AI进程列表"
        }
        before := AiDirectDebug.Variables(Map())
        scope := {token: name "§AI", data: data, messages: []}
        if (IsObject(DirectCommandScope()))
            throw Error("上一条原生指令仍在运行。")
        DirectCommandScope(scope)
        expired := false
        watchdog := () => (expired := true, item.Killed := true)
        SetTimer(watchdog, -30000)
        try {
            cursorBefore := Buffer(8, 0)
            if (name == "增量移动" && !DllCall("user32\GetCursorPos", "Ptr", cursorBefore))
                throw Error("无法读取移动前的鼠标坐标。")
            timeTargetMs := "", timeTarget := ""
            if (name == "时间" && TimeNormSubMode(data) == "等待") {
                timeTargetMs := TimeWaitTargetMilliseconds(table, 1, data)
                timeTarget := timeTargetMs == "" ? TimeCalcTargetDateTime(table, 1, data) : ""
                if (timeTargetMs == "" && timeTarget == "")
                    throw Error("时间等待的Param1无法解析，请按field_help填写目标时间或时长。")
                if (timeTargetMs != "") {
                    data.Param1 := String(timeTargetMs)
                    data.Param2 := "时间戳"
                }
            }
            if (name == "手柄") {
                MySoftData.HasJoyMacro := true
                OnPressKey(table, scope.token, 1)
                if (data.IsAxis)
                    InterruptibleSleep(table, 1, data.HoldTime, false)
            } else
                MacroCommandActions()[name](table, scope.token, 1)
            if (expired)
                throw Error("直接指令执行超时，已取消后续操作。")
            AiDirectControl.Check(item)
            after := AiDirectDebug.Variables(Map())
            changes := Map()
            for group in ["variables", "arrays"] {
                changes[group] := Map()
                for key, value in after[group] {
                    if (!before[group].Has(key) || JSON.stringify([before[group][key]], 0) != JSON.stringify([value], 0))
                        changes[group][key] := value
                }
                for key in before[group] {
                    if (!after[group].Has(key))
                        changes[group][key] := Map("deleted", JSON.true)
                }
            }
            failure := ""
            for field in ["ErrorVar", "ErrorSaveName"] {
                if (data.HasOwnProp(field) && data.%field% != "" && MySoftData.VariableMap.Has(data.%field%) && MySoftData.VariableMap[data.%field%] != "")
                    failure .= String(MySoftData.VariableMap[data.%field%]) "`n"
            }
            for message in scope.messages
                failure .= message["message"] "`n"
            if (name == "网络请求" && MySoftData.VariableMap.Has(data.StatusVar)) {
                status := MySoftData.VariableMap[data.StatusVar]
                if (!IsNumber(status) || status < 200 || status >= 300)
                    failure .= "HTTP状态码：" status
            }
            if (name == "浏览器" && MySoftData.VariableMap.Has(data.SaveVar "_Success") && !MySoftData.VariableMap[data.SaveVar "_Success"])
                failure .= String(MySoftData.VariableMap[data.SaveVar "_Error"])
            if (failure != "")
                throw Error(Trim(failure, "`r`n"))
            outputs := Map()
            for field, value in data.OwnProps() {
                candidates := Type(value) == "Array" ? value : [value]
                for candidate in candidates {
                    if (Type(candidate) != "String" || candidate == "")
                        continue
                    if (MySoftData.VariableMap.Has(candidate))
                        outputs[candidate] := AiDirectDebug.Value(MySoftData.VariableMap[candidate])
                    else if (MySoftData.ArrayMap.Has(candidate))
                        outputs[candidate] := AiDirectDebug.Value(MySoftData.ArrayMap[candidate])
                }
            }
            result := Map("executed", JSON.true, "verified", JSON.false, "outputs", outputs, "changes", changes, "messages", scope.messages,
                "snapshot_warnings", after["warnings"], "snapshot_truncated", after["truncated"],
                "guidance", "处理器已返回；请读取输出变量，检查状态或截图验证实际目标。无变化不等于成功，必要时变量监视或换其他指令。")
            if (name == "时间" && TimeNormSubMode(data) == "区间判断")
                result["in_range"] := TimeWindowInRange(table, 1, data) ? JSON.true : JSON.false
            if (name == "时间" && TimeNormSubMode(data) == "等待") {
                matched := timeTargetMs == "" ? A_Now >= timeTarget : UnixNow() >= timeTargetMs
                result["matched"] := matched ? JSON.true : JSON.false
                result["timed_out"] := matched ? JSON.false : JSON.true
            }
            if (name == "增量移动") {
                cursorAfter := Buffer(8, 0)
                if (!DllCall("user32\GetCursorPos", "Ptr", cursorAfter))
                    throw Error("无法读取移动后的鼠标坐标。")
                beforeX := NumGet(cursorBefore, 0, "Int"), beforeY := NumGet(cursorBefore, 4, "Int")
                afterX := NumGet(cursorAfter, 0, "Int"), afterY := NumGet(cursorAfter, 4, "Int")
                result["mouse_before"] := [beforeX, beforeY]
                result["mouse_after"] := [afterX, afterY]
                result["mouse_delta"] := [afterX-beforeX, afterY-beforeY]
            }
            return result
        } finally {
            SetTimer(watchdog, 0)
            DirectCommandScope("")
        }
    }
}
