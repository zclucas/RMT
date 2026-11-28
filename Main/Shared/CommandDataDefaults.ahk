; 只省略当前类型不使用、且仍等于默认值的字段。
; 编辑和执行使用完整对象，落盘使用副本，切换类型时已填写的值不会丢失。
CommandDefaultRules(cmd, data, defaults) {
    rules := Map()
    value(field) => data.HasOwnProp(field) ? data.%field% : defaults.%field%
    use(fields, active) {
        for field in StrSplit(fields, " ")
            rules[field] := active
    }
    switch cmd {
        case "搜索", "搜索Pro", "搜索All", "搜索Combo":
            kind := value("SearchType")
            single := cmd != "搜索Combo"
            image := single && InStr(kind, "图片") != 0
            color := single && InStr(kind, "颜色") != 0
            text := single && InStr(kind, "文本") != 0
            use("ConfigName ConfigArr", false)
            use("SearchType Similar StartPosX StartPosY EndPosX EndPosY", single)
            use("WinInfo", single && InStr(kind, "窗口") != 0)
            use("SearchColor", color)
            use("SearchText OCRType OcrEngine", text)
            use("SearchImagePath SearchImageType ColorMatch MultiPointData MultiPointSeedData SuperMultiPointSeedData SuperMultiPointIgnoreData MultiPointTolerance SuperMultiPointTolerance MultiPointMode", image)
            use("Speed ClickCount", value("MouseActionType") != "无动作")
            use("ResultSaveName TrueValue FalseValue", value("ResultToggle"))
            use("CoordXName CoordYName", value("CoordToogle"))
        case "浏览器":
            action := value("ActionType")
            open := action == "打开网址"
            tabs := action == "切换标签页" || action == "关闭标签页"
            page := action == "标签页信息"
            selector := BrowserActions.UsesSelector(action) || (tabs && value("TabMatchMode") == "元素匹配") || (page && value("PageSource") == "元素匹配")
            use("BrowserType Headless OpenMode UseCDP UserDataDir", open)
            use("Url", open || (page && BrowserPageInfo.UsesMatchValue(value("PageSource"))))
            use("BrowserPath", open && value("BrowserType") == "自定义路径")
            use("BrowserPort", open || page || action == "关闭标签页")
            use("CurrentTabAction", action == "当前标签页")
            use("TabMatchMode", tabs)
            use("TabCloseMode", action == "关闭标签页")
            use("Selector SelectorType", selector)
            use("ElementExistsVar ElementValueVar ElementRefVar ElementTabIdVar ElementStateVar ElementHtmlVar", action == "元素信息")
            use("ElementXVar ElementYVar ElementPageXVar ElementPageYVar ElementWidthVar ElementHeightVar", action == "元素位置/宽高")
            use("PageSource PageIdVar PageUrlVar PageTitleVar PageStateVar", action == "标签页信息")
            use("Condition", action == "等待元素" || action == "元素状态")
            use("LoadState", action == "等待加载")
            use("Text", action == "等待文字" || action == "输入" || action == "选择下拉" || action == "按键输入" || action == "Cookie操作" || action == "Storage操作")
            use("ClearBefore", action == "输入")
            use("Checked", action == "勾选")
            use("FullPage", action == "网页截图")
            use("JsCode", action == "执行JS" || action == "Cookie操作" || action == "Storage操作")
            use("AttrName", action == "Cookie操作" || action == "Storage操作")
            use("MouseBtn", action == "鼠标点击")
            use("Modifiers", action == "鼠标点击" || action == "按键输入")
            use("CoordX CoordY", action == "鼠标移动" || action == "鼠标点击" || action == "鼠标滚轮")
            use("StorageType", action == "Storage操作")
            use("CookieDomain CookiePath", action == "Cookie操作")
            use("SaveVar", !page && !BrowserElementInfo.IsRead(action))
            use("TimeoutMs TimeoutAction TimeoutStatusVar", BrowserActions.UsesTimeout(action))
        case "等待":
            kind := value("WaitType")
            use("Conditions ConditionLogic", kind == "等待变量值")
            use("KeyDevice KeyOptions", kind == "等待按键按下" || kind == "等待按键松开")
            use("TimeConfig", kind == "等待时间" || kind == "等待时间区间")
            use("ConfirmConfig", kind == "等待确定")
            use("ProcessTargetType", kind == "等待进程存在" || kind == "等待进程关闭")
            use("StartPosX StartPosY EndPosX EndPosY", kind == "等待屏幕变化" || kind == "等待窗口屏幕变化")
        case "提示":
            kind := value("Type")
            use("AudioMode AudioPath Beep AudioWait AudioPlayback", kind == "音频")
            use("TipMode TextSource", kind == "临时提示")
            use("PasteMode PastePosition PasteTextSource PasteName", kind == "自由贴")
            use("ImageSource ImagePath", kind == "临时提示" || kind == "自由贴")
            use("RegionMode RegionName EndPosX EndPosY", kind == "区域高亮")
            use("Color Thickness", kind == "区域高亮" || kind == "屏幕边缘闪光")
            use("FlashMode FlashDuration FlashCount Monitors", kind == "屏幕边缘闪光")
            use("CountDownMode CountDownName Seconds Hour Min Sec Param1 Param2 WaitEnd", kind == "倒计时")
            use("Width Height", kind == "临时提示" || kind == "自由贴" || kind == "区域高亮")
            use("PosX PosY", kind == "临时提示" || kind == "自由贴" || kind == "区域高亮" || kind == "倒计时")
        case "输出":
            use("VariableName", value("OutputType") == "字符变量")
            use("HudPos HudX HudY HudFontSize HudAlpha HudColor HudBgColor", value("OutputType") == "悬浮显示")
        case "循环":
            use("LogicType ToggleArr NameArr CompareTypeArr VariableArr", value("CondiType") != "无")
        case "如果":
            use("SaveName TrueValue FalseValue", value("SaveToggle"))
        case "变量":
            random := false, copy := false
            for operation in value("OperaTypeArr") {
                operation := CmdEnumOpera(operation)
                random := random || operation == "随机数值"
                copy := copy || (operation != "随机数值" && operation != "删除")
            }
            use("MinVariableArr MaxVariableArr", random)
            use("CopyVariableArr", copy)
        case "变量提取":
            kind := value("ExtractType")
            use("WinInfo", kind == "窗口")
            use("OCRType OcrEngine StartPosX StartPosY EndPosX EndPosY", kind != "剪切板")
        case "移动Pro", "鼠标移动Pro":
            absolute := value("MouseMoveMode") == "绝对移动"
            use("Speed ActionType", value("MouseMoveMode") != "游戏视角")
            use("EndPosVarX EndPosVarY", absolute && value("ActionType") == "A到B拖拽")
            use("RefMode", absolute)
            use("WinInfo", absolute && value("RefMode") == "窗口")
        case "按键":
            axis := value("IsAxis") && InStr(value("KeyName"), "JoyAxis")
            click := !axis && value("KeyType") == "点击"
            use("AxisValue", axis)
            use("KeyType Count", !axis)
            use("HoldTime", click)
            use("IntervalTime", click && value("Count") != 1)
        case "按键检测", "手柄检测":
            use("StateType", !CommandHasAnalogKeys(data))
        case "间隔":
            use("Time2", value("Type") == "随机")
        case "增量移动":
            use("Interval", value("Count") != 1)
        case "时间":
            range := value("SubMode") == "区间判断"
            use("Param4 Param5", range)
            use("CheckInterval Timeout", !range)
            use("Hour Min Sec Seconds WaitEnd PosX PosY", false)
        case "倒计时":
            duration := value("Param2") == "时长"
            use("Hour Min Sec", duration)
            use("Param1", !duration)
            use("Seconds", false)
        case "等待确定":
            buttons := value("Type") == "继续&终止&暂停"
            use("TerminateType", buttons || value("TimeoutAction") == "自动终止")
            use("PauseBtnType", buttons || value("TimeoutAction") == "自动暂停")
        case "Timing":
            use("EndStamp", false)
            use("CustomInterval CustomUnit", CmdEnumTimingType(value("Type")) == "周期触发")
            use("Duration DurationUnit", CmdEnumTimingDuration(value("DurationMode")) == "固定时长")
        case "图形节点":
            ; 空偏移表示未设置，使用自动布局；真实偏移、节点坐标和连线仍保留。
            use("TrueBranchDX TrueBranchDY FalseBranchDX FalseBranchDY ExpandShift SuccDX SuccDY FoldSuccDX FoldSuccDY ProBranchOff", false)
        case "网络请求":
            use("BodyType Body", value("Method") != "GET")
        case "AI判断":
            source := value("Source")
            use("Region", AiDecision.IsScreenSource(source))
            use("WindowRegion WinInfo", AiDecision.IsWindowSource(source))
        case "翻译":
            use("Text", value("Source") != "剪切板")
            use("TargetCustom", value("Target") == "自定义")
            use("Device", TranslateCommand.IsLocal(value("Engine")))
        case "YOLO检测":
            task := CommandYoloTask(data)
            known := task != ""
            boxes := !known || task == "detect" || task == "segment" || task == "pose" || task == "obb"
            clickable := boxes || task == "semantic"
            use("Iou MaxDet CountVar TargetMode", boxes)
            use("ConfLevel", !known || (task != "depth" && task != "semantic"))
            use("Classes ActionType", clickable)
            use("OffsetX OffsetY", clickable && value("ActionType") != "无动作")
            use("KeypointConf AnchorKpt", !known || task == "pose")
            use("MinMaskRatio", !known || task == "segment")
            use("MinRatio RatioVar", !known || task == "semantic")
            use("TopK ConfVar", !known || task == "classify")
            use("ClassVar", !known || task == "classify" || task == "semantic")
            use("SampleX SampleY DepthVar", !known || task == "depth")
        case "抓图":
            use("StartPosX StartPosY EndPosX EndPosY", value("ScreenShotType") != "自定义截图")
            use("WinInfo", value("ScreenShotType") == "窗口抓图")
            use("FixedName ResultToggle SavePath", false)
            use("ResultSaveName", true)
        case "后台鼠标":
            use("ScrollV ScrollH", value("MouseType") == "滚轮")
            use("ClickTime", value("OperateType") == "点击" || value("OperateType") == "双击")
        case "后台按键":
            use("ClickTime ClickCount ClickInterval", value("Type") == "点击")
        case "输入":
            use("Options", value("Type") == "选择" || value("Type") == "多选")
        case "文件读写", "Excel":
            kind := value("OperType")
            excel := InStr(kind, "Excel") != 0
            read := InStr(kind, "读取") != 0
            mode := value("OperMode")
            range := mode == "指定区域-行" || mode == "指定区域-列"
            use("Encoding", !excel)
            use("TextRowVar", !excel && (mode == "指定行" || mode == "逐行读取" || mode == "行号自增"))
            use("NameOrSerial RowVar ColVar", excel)
            use("RowEndVar ColEndVar", excel && read && range)
            use("Content", !read && (!excel || !range))
            use("ArrName", !read && excel && range)
            use("SaveName", read)
            use("SaveType", false)
        case "窗口操作", "窗口管理", "窗口信息":
            action := value("ActionType")
            use("PosX PosY", action == "移动窗口" || action == "相对移动" || action == "位置和宽高")
            use("Width Height", action == "调整宽高" || action == "位置和宽高")
            use("NewTitle", action == "修改标题")
            use("Transparency", action == "修改透明度")
        case "文本处理":
            use("Search Replace MatchType", value("Type") == "文本替换")
        case "数组":
            kind := value("Type")
            use("InitArr IsIgnoreExist", kind == "创建")
            use("MainIndex", kind != "创建" && kind != "删除")
            use("ArgsIndex", kind == "取值" || kind == "赋值" || kind == "插入" || kind == "移除")
            use("ArgsType ArgsName", kind == "包含" || kind == "赋值" || kind == "插入" || kind == "追加")
            use("SaveType", kind == "取值" || kind == "移除" || kind == "移除最后")
            use("SaveName", kind == "克隆" || kind == "包含" || kind == "长度" || kind == "取值" || kind == "移除" || kind == "移除最后")
        case "宏操作":
            use("InsertCount", value("CallType") == "插入到当前宏")
        case "进程管理":
            action := value("Action")
            use("PickMatch", action == "进程信息")
            use("CountVar NameVar PidVar PathVar ExistVar StatusVar StartTimeVar UptimeVar CpuVar GpuVar", action == "进程信息")
            use("ResultVar", action == "检测进程" || action == "结束进程")
            use("ResultArray", action == "列出进程")
            use("EndAll", action == "结束进程")
        case "控件操作", "控件信息":
            action := value("ActionType")
            use("Argument WriteKind", action == "写入控件值")
            use("ClickType ClickHoldMs ClickPoint", action == "点击控件")
            use("ScrollOffset", action == "滚动到控件")
            use("WaitType WaitValueKind WaitLogic WaitConditions", action == "等待控件出现")
            if (cmd == "控件信息") {
                use("ValueVar ControlVar HwndVar StateVar", action == "检测控件存在")
                use("XVar YVar WindowXVar WindowYVar WidthVar HeightVar", action == "读取位置/宽高")
            }
        case "RMT指令":
            use("MenuIndex", value("CmdStr") == "显示菜单")
            use("TableSymbol FoldID", value("CmdStr") == "禁用模块" || value("CmdStr") == "取消禁用模块")
    }
    if (defaults.HasOwnProp("ErrMode"))
        use("ErrRetryCount ErrRetryInterval", value("ErrMode") == "retry")
    return rules
}

; 只读模型任务缓存，序列化不能触发模型加载、下载或写入全局模型库。
CommandYoloTask(data) {
    global ProjectRootDir
    if (!IsSet(ProjectRootDir) || !data.HasOwnProp("ModelName") || Trim(data.ModelName) == "" || InStr(data.ModelName, "{"))
        return ""
    task := YoloModelStore.GetTask(data.ModelName)
    return Yolo.Tasks.Has(task) ? task : ""
}

CommandHasAnalogKeys(data) {
    if (!data.HasOwnProp("KeyArr") || !(data.KeyArr is Array))
        return false
    for key in data.KeyArr
        if (RegExMatch(key, "^(?:JoyAxis)?(L[XY]|R[XY]|LT|RT):(-?[0-9]+)$"))
            return true
    return false
}

CommandDefaultValues(cmd, data) {
    dataClass := MySoftData.DataClassMap[cmd]
    defaults := dataClass()
    if (cmd == "变量" && data.HasOwnProp("OperaTypeArr") && data.OperaTypeArr is Array) {
        for field in ["CopyVariableArr", "MinVariableArr", "MaxVariableArr"] {
            fallback := defaults.%field%[1]
            defaults.%field% := []
            loop data.OperaTypeArr.Length
                defaults.%field%.Push(fallback)
        }
    }
    return defaults
}

; 仅读取上述可省略字段的默认值，不补齐版本标记等具有兼容语义的字段。
RestoreCommandDefaults(cmd, data) {
    if (!IsObject(data) || !IsSet(MySoftData) || !MySoftData.HasProp("DataClassMap") || !MySoftData.DataClassMap.Has(cmd))
        return data
    defaults := CommandDefaultValues(cmd, data)
    for field, active in CommandDefaultRules(cmd, data, defaults) {
        ; 旧配置缺少生效中的周期或持续时长时，不替用户猜测触发频率与截止时间。
        if (cmd == "Timing" && active)
            continue
        if (!data.HasOwnProp(field) && defaults.HasOwnProp(field))
            data.%field% := defaults.%field%
    }
    if (CommandHasSearchTargets(cmd, data)) {
        for target in data.SearchTargetArr {
            if (IsObject(target) && target.HasOwnProp("SearchType"))
                RestoreCommandDefaults("搜索", target)
        }
    }
    return data
}

CompactCommandData(cmd, data) {
    result := data.Clone()
    if (!IsSet(MySoftData) || !MySoftData.HasProp("DataClassMap") || !MySoftData.DataClassMap.Has(cmd))
        return result
    defaults := CommandDefaultValues(cmd, data)
    for field, active in CommandDefaultRules(cmd, data, defaults) {
        if (active || !result.HasOwnProp(field) || !defaults.HasOwnProp(field))
            continue
        current := result.%field%, fallback := defaults.%field%
        equal := IsObject(current) || IsObject(fallback)
            ? JSON.stringify([current], 0) == JSON.stringify([fallback], 0)
            : (Type(current) == Type(fallback) && current == fallback)
                || (Type(fallback) != "String" && IsNumber(current) && IsNumber(fallback) && Number(current) == Number(fallback))
        if (equal)
            result.DeleteProp(field)
    }
    if (CommandHasSearchTargets(cmd, data)) {
        result.SearchTargetArr := []
        for target in data.SearchTargetArr
            result.SearchTargetArr.Push(IsObject(target) && target.HasOwnProp("SearchType") ? CompactCommandData("搜索", target) : target)
    }
    return result
}

CommandHasSearchTargets(cmd, data) {
    return (cmd == "搜索" || cmd == "搜索Pro" || cmd == "搜索All" || cmd == "搜索Combo")
        && data.HasOwnProp("SearchTargetArr") && data.SearchTargetArr is Array
}

SerializeCommandData(data, cmd := "") {
    if (cmd == "") {
        SplitSerialTextAndNumbers(data.SerialStr, &name, &number)
        cmd := GetCommandKey(name)
    }
    return JSON.stringify(CompactCommandData(cmd, data), 0)
}
