#Requires AutoHotkey v2.0
#Include ..\Shared\RuntimeChoice.ahk

; 1.2.2 之后新增指令使用当前选项，不接受预览版编号或未知值回退。
CurrentCommandChoice(value, names) {
    value := GetConfigKey(value, names)
    for name in names
        if (Type(value) == "String" && value == name)
            return name
    throw ValueError(GetLang("不支持的指令选项") "：" value)
}

CurrentCommandChoiceIndex(value, names) {
    value := CurrentCommandChoice(value, names)
    for index, name in names
        if (value == name)
            return index - 1
}

; 指令枚举存中文。names 为存储顺序，base 为旧数字起点（1 或 0）。
; 已是中文（或当前语言译文）时原样收成中文键；旧数字按顺序映射。

CmdEnumZh(value, names, base := 1) {
    if (!IsObject(names) || names.Length == 0)
        return ""
    key := GetConfigKey(String(value), names)
    for name in names {
        if (key == name)
            return name
    }
    if (IsNumber(value)) {
        idx := Integer(value) - base + 1
        if (idx >= 1 && idx <= names.Length)
            return names[idx]
    }
    return names[1]
}

; 下拉 SelectedIndex（0 起）
CmdEnumIndex(value, names, base := 1) {
    zh := CmdEnumZh(value, names, base)
    for i, name in names {
        if (name == zh)
            return i - 1
    }
    return 0
}

CmdEnumFromIndex(idx, names, fallback := "") {
    if (!IsNumber(idx) || Integer(idx) < 0 || Integer(idx) >= names.Length)
        return fallback != "" ? fallback : (names.Length ? names[1] : "")
    return names[Integer(idx) + 1]
}

CmdEnumNormList(arr, names, base := 1) {
    if (!IsObject(arr))
        return
    loop arr.Length {
        if (IsObject(arr[A_Index]))
            CmdEnumNormList(arr[A_Index], names, base)
        else
            arr[A_Index] := CmdEnumZh(arr[A_Index], names, base)
    }
}

CmdEnumSet(Data, field, names, base := 1) {
    if (!IsObject(Data) || !Data.HasProp(field))
        return
    Data.%field% := CmdEnumZh(Data.%field%, names, base)
}

; 只把数字收成中文。已经是中文或名单外的值保持原样，避免误伤旧别名。
CmdEnumNum(value, names, base := 1) {
    if (!IsNumber(value)) {
        key := GetConfigKey(String(value), names)
        for name in names
            if (key == name)
                return name
        return value
    }
    idx := Integer(value) - base + 1
    if (idx >= 1 && idx <= names.Length)
        return names[idx]
    return value
}

CmdEnumSetNum(Data, field, names, base := 1) {
    if (!IsObject(Data) || !Data.HasProp(field))
        return
    Data.%field% := CmdEnumNum(Data.%field%, names, base)
}

CmdEnumSetKey(Data, field, names) {
    if (Data.HasProp(field) && Type(Data.%field%) == "String")
        Data.%field% := GetConfigKey(Data.%field%, names)
}

CmdEnumCompareNames() => ["大于", "大于等于", "等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配", "不等于", "变量不存在"]
CmdEnumCompareShowNames() => ["大于", "大于等于", "等于", "不等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配", "变量不存在"]
CmdEnumLogicNames() => ["且", "或"]
CmdEnumOperaNames() => ["数值", "随机数值", "字符", "系统", "时间", "删除"]
; 界面使用新类别；旧数值枚举顺序仍用于兼容读取。
CmdEnumVariableNames() => ["赋值", "随机数值", "系统", "时间", "删除"]
CmdEnumWaitNames() => ["等待变量值", "等待按键按下", "等待按键松开", "等待屏幕变化", "等待鼠标移动",
    "等待鼠标停止移动", "等待剪切板变化", "等待进程存在", "等待进程关闭", "等待窗口存在",
    "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口关闭", "等待窗口最小化",
    "等待文件存在", "等待文件删除", "等待文件变化", "等待时间", "等待时间区间", "等待确定", "等待窗口移动"]

CurrentCommandChoiceWait(value) => CurrentCommandChoice(value, CmdEnumWaitNames())

CmdEnumWaitEditorNames() => CmdEnumWaitNames()

CmdEnumWaitEditorLabels() {
    labels := []
    for key in CmdEnumWaitEditorNames()
        labels.Push(GetLang(SubStr(key, 3)))
    return labels
}
CmdEnumSearchNames() => ["屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"]
; 前四项保留旧序号；新存储值区分旧后台点击与明确的仅移动。
CmdEnumMouseActNames() => ["无动作", "移动至目标", "移动至目标点击1次", "移动至目标点击2次", "移动至目标右键点击1次", "仅移动", "移动并左击"]

CmdEnumSearchMouseActItems(variableCount := false) {
    return variableCount ? ["无动作", "仅移动", "移动并左击", "移动并右击"]
        : ["无动作", "仅移动", "移动并左击1次", "移动并左击2次", "移动并右击1次"]
}

CmdEnumSearchMouseActValues(variableCount := false) {
    return variableCount ? ["无动作", "仅移动", "移动并左击", "移动至目标右键点击1次"]
        : ["无动作", "仅移动", "移动并左击", "移动至目标点击2次", "移动至目标右键点击1次"]
}

CmdEnumSearchMouseActIndex(value, variableCount := false) {
    act := CmdEnumMouseAct(value)
    if (act == "移动至目标")
        act := "仅移动"
    if (act == "移动至目标点击1次" || (variableCount && act == "移动至目标点击2次"))
        act := "移动并左击"
    return CmdEnumIndex(act, CmdEnumSearchMouseActValues(variableCount))
}
CmdEnumMMActionNames() => ["移动", "移动后单击", "移动后双击", "A到B拖拽", "拖拽"]
CmdEnumMoveModeNames() => ["绝对移动", "相对移动", "游戏视角"]
CmdEnumRefNames() => ["屏幕", "窗口"]
CmdEnumCondiNames() => ["无", "继续条件", "退出条件"]
CmdEnumIntervalNames() => ["固定", "随机"]
CmdEnumKeyActNames() => ["按下", "松开", "点击"]
CmdEnumBgOperNames() => ["点击", "双击", "按下", "松开"]
CmdEnumMouseBtnNames() => ["左键", "中键", "右键", "滚轮"]
CmdEnumExtractNames() => ["屏幕", "剪切板", "窗口"]
CmdEnumRunModeNames() => ["不等待", "等待+返回值", "不等待+输入", "等待+输入输出"]
CmdEnumRunOptionNames() => ["后台", "默认", "最小化", "最大化"]
CmdEnumTimingTypeNames() => ["单次", "软件启动时", "周期触发"]
CmdEnumTimingUnitNames() => ["秒", "分钟", "小时", "天", "周", "月"]
CmdEnumTimingDurationNames() => ["无限制", "固定时长"]
CmdEnumShotNames() => ["屏幕抓图", "窗口抓图"]
CmdEnumNameTypeNames() => ["默认", "固定名称"]
CmdEnumKeyCheckNames() => ["同时按下", "有一个按下"]
CmdEnumJoyAnalogNames() => ["大于设定值", "大于等于", "等于设定值", "小于等于", "小于设定值"]
CmdEnumStateNames() => ["物理状态", "逻辑状态"]

CmdEnumCompare(value) => CmdEnumZh(value, CmdEnumCompareNames())
CmdEnumLogic(value) => CmdEnumZh(value, CmdEnumLogicNames())

CmdEnumOpera(value) {
    if (GetConfigKey(String(value), ["赋值"]) == "赋值")
        return "赋值"
    if (IsNumber(value) && Integer(value) == 7)
        return "时间"
    key := GetConfigKey(String(value), ["随机"])
    if (key == "随机")
        return "随机数值"
    return CmdEnumZh(value, CmdEnumOperaNames())
}

CmdEnumMoveMode(value) {
    switch value, false {
        case "Absolute", "Absolute Move", "絕對移動": return "绝对移动"
        case "Relative", "Relative Move", "相對移動": return "相对移动"
        case "Game View", "遊戲視角": return "游戏视角"
    }
    return CmdEnumZh(value, CmdEnumMoveModeNames(), 0)
}

CanonicalMoveCommandName(key) {
    switch key, false {
        case "移动", "鼠标移动", "滑鼠移動", "移動", "Mouse Move", "Move": return "移动"
        case "移动Pro", "鼠标移动Pro", "滑鼠移動Pro", "移動Pro", "Mouse Move Pro", "Move Pro", "Move+": return "移动Pro"
    }
    return key
}

; 普通移动始终内联：移动_X_Y_速度[_相对移动|_游戏视角]。绝对移动省略方式段。
FormatMoveInlineCmd(posX, posY, speed := 90, moveMode := 0, name := "移动") {
    cmd := name "_" posX "_" posY "_" (speed == "" ? 90 : speed)
    mode := CmdEnumMoveMode(moveMode)
    if (mode == "相对移动" || mode == "游戏视角")
        cmd .= "_" mode
    return cmd
}
CmdEnumRef(value) => CmdEnumZh(value, CmdEnumRefNames(), 0)
CmdEnumKeyAct(value) => CmdEnumZh(value, CmdEnumKeyActNames())
CmdEnumRunOption(value) => CmdEnumZh(value, CmdEnumRunOptionNames(), 0)
CmdEnumNameType(value) => CmdEnumZh(value, CmdEnumNameTypeNames(), 0)
CmdEnumWait(value) => CurrentCommandChoiceWait(value)
CmdEnumSearch(value) => CmdEnumZh(value, CmdEnumSearchNames())
CmdEnumMouseAct(value) {
    key := GetLangKey(String(value))
    aliases := Map("移动并左击1次", "移动至目标点击1次", "移动并左击2次", "移动至目标点击2次",
        "移动并右击1次", "移动至目标右键点击1次", "移动并右击", "移动至目标右键点击1次",
        "移动至目标点击", "移动至目标点击1次")
    return CmdEnumZh(aliases.Get(key, value), CmdEnumMouseActNames())
}
CmdEnumMMAction(value) => CmdEnumZh(value, CmdEnumMMActionNames())
CmdEnumTimingType(value) {
    key := GetConfigKey(String(value), ["自定义"])
    if (key == "自定义")
        return "周期触发"
    return CmdEnumZh(value, CmdEnumTimingTypeNames())
}
CmdEnumTimingUnit(value) => CmdEnumZh(value, CmdEnumTimingUnitNames())
CmdEnumTimingDuration(value) => CmdEnumZh(value, CmdEnumTimingDurationNames())

CurrentJoyCheck(value) {
    names := CmdEnumKeyCheckNames()
    names.Push(CmdEnumJoyAnalogNames()*)
    return CurrentCommandChoice(value, names)
}

; 仅用于1.2.2按键检测迁移为手柄检测时读取旧编号。
CmdEnumJoyCheck(value, analog) {
    if (!IsNumber(value)) {
        names := CmdEnumKeyCheckNames()
        names.Push(CmdEnumJoyAnalogNames()*)
        key := GetConfigKey(String(value), names)
        for name in names {
            if (key == name)
                return name
        }
    }
    return CmdEnumZh(value, analog ? CmdEnumJoyAnalogNames() : CmdEnumKeyCheckNames())
}

CmdEnumJoyAnalog(Data) {
    if (!IsObject(Data) || !Data.HasProp("KeyArr") || !IsObject(Data.KeyArr))
        return false
    for key in Data.KeyArr {
        if (RegExMatch(String(key), "^(?:JoyAxis)?(L[XY]|R[XY]|LT|RT):(-?[0-9]+)$"))
            return true
    }
    return false
}

CmdEnumNormOperaList(arr) {
    if (!IsObject(arr))
        return
    loop arr.Length
        arr[A_Index] := CmdEnumOpera(arr[A_Index])
}

CmdEnumNormSearchObj(obj) {
    if (!IsObject(obj))
        return
    if (obj.HasProp("SearchType"))
        obj.SearchType := CmdEnumSearch(obj.SearchType)
    if (obj.HasProp("MouseActionType"))
        obj.MouseActionType := CmdEnumMouseAct(obj.MouseActionType)
}

; 读入指令配置后把枚举数字收成中文。cmd 为指令中文键。
CmdEnumNorm(cmd, Data) {
    if (!IsObject(Data))
        return
    switch cmd {
        case "RMT指令":
            if (Data.HasProp("Category"))
                Data.Category := RmtCommandCategoryKey(Data.Category)
            if (Data.HasProp("CmdStr"))
                Data.CmdStr := RmtCommandActionKey(Data.CmdStr)
        case "搜索", "搜索Pro":
            CmdEnumNormSearchObj(Data)
            if (Data.HasProp("SearchTargetArr") && IsObject(Data.SearchTargetArr)) {
                for t in Data.SearchTargetArr
                    CmdEnumNormSearchObj(t)
            }
        case "搜索All", "搜索Combo":
            Data.SearchType := CurrentCommandChoice(Data.SearchType, CmdEnumSearchNames())
            Data.MouseActionType := CurrentCommandChoice(Data.MouseActionType, CmdEnumMouseActNames())
            if (cmd == "搜索Combo")
                for target in Data.SearchTargetArr
                    target.SearchType := CurrentCommandChoice(target.SearchType, CmdEnumSearchNames())
        case "移动Pro", "鼠标移动Pro":
            CmdEnumSet(Data, "MouseMoveMode", CmdEnumMoveModeNames(), 0)
            ; 相对模式旧编号 4 是「拖拽」；绝对模式的 4 才是「A到B拖拽」
            if (Data.MouseMoveMode == "相对移动" && (Data.ActionType == 4 || Data.ActionType == "4"))
                Data.ActionType := "拖拽"
            else
                CmdEnumSet(Data, "ActionType", CmdEnumMMActionNames())
            CmdEnumSet(Data, "RefMode", CmdEnumRefNames(), 0)
        case "移动", "鼠标移动":
            if (Data.HasProp("MoveMode"))
                Data.MoveMode := CmdEnumMoveMode(Data.MoveMode)
        case "等待":
            Data.WaitType := CurrentCommandChoiceWait(Data.WaitType)
        case "如果":
            CmdEnumSet(Data, "LogicalType", CmdEnumLogicNames())
            if (Data.HasProp("CompareTypeArr"))
                CmdEnumNormList(Data.CompareTypeArr, CmdEnumCompareNames())
        case "如果Pro":
            if (Data.HasProp("LogicTypeArr"))
                CmdEnumNormList(Data.LogicTypeArr, CmdEnumLogicNames())
            if (Data.HasProp("CompareTypeArr"))
                CmdEnumNormList(Data.CompareTypeArr, CmdEnumCompareNames())
        case "循环":
            CmdEnumSet(Data, "CondiType", CmdEnumCondiNames())
            CmdEnumSet(Data, "LogicType", CmdEnumLogicNames())
            if (Data.HasProp("CompareTypeArr"))
                CmdEnumNormList(Data.CompareTypeArr, CmdEnumCompareNames())
        case "变量":
            if (Data.HasProp("OperaTypeArr"))
                CmdEnumNormOperaList(Data.OperaTypeArr)
        case "变量提取":
            CmdEnumSet(Data, "ExtractType", CmdEnumExtractNames())
        case "后台鼠标":
            CmdEnumSet(Data, "OperateType", CmdEnumBgOperNames())
            CmdEnumSet(Data, "MouseType", CmdEnumMouseBtnNames())
        case "后台按键":
            CmdEnumSet(Data, "Type", CmdEnumKeyActNames())
        case "按键":
            CmdEnumSet(Data, "KeyType", CmdEnumKeyActNames())
        case "输入":
            types := InputTypeKeys("继续")
            types.Push("继续&取消")
            CmdEnumSetKey(Data, "Type", types)
            CmdEnumSetKey(Data, "PauseType", ["暂停当前宏", "暂停所有宏"])
            CmdEnumSetKey(Data, "CancelType", ["终止当前宏", "终止所有宏"])
            CmdEnumSetKey(Data, "TimeoutAction", ["无", "用默认值", "保持原值", "终止当前宏", "终止所有宏"])
        case "等待确定":
            CmdEnumSetKey(Data, "Type", ["继续", "继续&终止&暂停"])
            CmdEnumSetKey(Data, "PauseType", ["暂停当前宏", "暂停所有宏"])
            CmdEnumSetKey(Data, "PauseBtnType", ["暂停当前宏", "暂停所有宏"])
            CmdEnumSetKey(Data, "TerminateType", ["终止当前宏", "终止所有宏"])
            CmdEnumSetKey(Data, "TimeoutAction", ["无", "自动继续", "自动终止", "自动暂停"])
        case "间隔":
            CmdEnumSet(Data, "Type", CmdEnumIntervalNames())
        case "按键检测":
            CmdEnumSet(Data, "CheckType", CmdEnumKeyCheckNames())
            CmdEnumSet(Data, "StateType", CmdEnumStateNames())
        case "手柄检测":
            Data.CheckType := CurrentJoyCheck(Data.CheckType)
            Data.StateType := CurrentCommandChoice(Data.StateType, CmdEnumStateNames())
        case "运行", "运行Pro":
            CmdEnumSet(Data, "Mode", CmdEnumRunModeNames())
            CmdEnumSet(Data, "Option", CmdEnumRunOptionNames(), 0)
        case "Timing":
            if (Data.HasProp("Type"))
                Data.Type := CmdEnumTimingType(Data.Type)
            CmdEnumSetNum(Data, "CustomUnit", CmdEnumTimingUnitNames())
            if (Data.HasProp("DurationMode"))
                Data.DurationMode := CmdEnumTimingDuration(Data.DurationMode)
            if (Data.HasProp("DurationUnit"))
                Data.DurationUnit := CmdEnumTimingUnit(Data.DurationUnit)
        case "抓图":
            CmdEnumSet(Data, "ScreenShotType", CmdEnumShotNames())
            CmdEnumSet(Data, "NameType", CmdEnumNameTypeNames(), 0)
        case "输出":
            CmdEnumSetNum(Data, "OutputType", ["发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板", "字符变量"])
        case "宏操作":
            CmdEnumSetNum(Data, "MacroType", ["当前宏", "按键宏", "字串宏", "轮盘宏", "定时宏", "宏"])
            if (Data.HasProp("MacroType") && Data.MacroType == "菜单宏")
                Data.MacroType := "轮盘宏"
            callTypes := ["插入到当前宏", "触发", "暂停", "取消暂停", "终止"]
            if (Data.HasProp("CallType") && !IsNumber(Data.CallType))
                callTypes.Push("循环-跳过本轮", "循环-跳出", "分支-跳出")
            CmdEnumSetNum(Data, "CallType", callTypes)
        case "窗口信息":
            Data.ActionType := CurrentCommandChoice(Data.ActionType, ["位置与宽高", "标题类名句柄", "进程信息", "窗口状态", "匹配窗口列表"])
        case "窗口管理", "窗口操作":
            ; 保留旧数字顺序，新类型只在界面插入，避免旧配置操作错位。
            CmdEnumSetNum(Data, "ActionType", ["激活窗口", "最大化窗口", "最小化窗口", "还原窗口", "关闭窗口", "移动窗口", "调整宽高", "置顶窗口", "取消置顶", "修改标题", "修改透明度", "开启鼠标穿透", "关闭鼠标穿透"])
            static windowActions := Map(
                "Activate Window", "激活窗口", "Maximize Window", "最大化窗口", "Minimize Window", "最小化窗口",
                "Restore Window", "还原窗口", "Close Window", "关闭窗口", "Move Window", "移动窗口",
                "Resize Window", "调整宽高", "Set Topmost", "置顶窗口", "Unset Topmost", "取消置顶",
                "Set Title", "修改标题", "Set Transparency", "修改透明度", "Enable Click-Through", "开启鼠标穿透",
                "Disable Click-Through", "关闭鼠标穿透",
                "调整大小", "调整宽高")
            if (!Data.HasProp("ActionType"))
                return
            actions := ["位置与宽高", "标题类名句柄", "进程信息", "窗口状态",
                "匹配窗口列表", "相对移动", "窗口居中", "位置和宽高", "切换置顶", "切换鼠标穿透"]
            Data.ActionType := GetConfigKey(windowActions.Get(Data.ActionType, Data.ActionType), actions)
        case "文件读写", "Excel":
            if (Data.HasProp("OperType")) {
                types := Map("1", "读取Excel", "2", "写入Excel", "3", "读取文件", "4", "写入文件")
                key := String(Data.OperType)
                Data.OperType := types.Has(key) ? types[key] : FileIONormType(Data.OperType)
            }
            CmdEnumSetKey(Data, "OperMode", ["读取全部内容", "逐行读取", "指定行", "覆盖写入", "追加写入", "追加写入-行", "行号自增",
                "单元格", "指定列", "指定区域-行", "指定区域-列", "列号自增"])
        case "文本处理":
            textTypes := TextOpsTypeNames()
            CmdEnumSetKey(Data, "Type", textTypes)
            if (Data.HasProp("Type"))
                CmdEnumSetKey(Data, "ArgsType", TextOpsModes(Data.Type))
    }
}

; 查询字段顺序同时用于编辑器和执行结果。
WindowInfoFields(action) {
    switch action {
        case "位置与宽高": return ["坐标X", "坐标Y", "宽度", "高度"]
        case "标题类名句柄": return ["标题", "类名", "句柄"]
        case "进程信息": return ["进程名", "进程ID", "程序路径"]
        case "窗口状态": return ["存在", "激活", "最小化", "最大化", "置顶", "透明度", "鼠标穿透"]
        case "匹配窗口列表": return ["句柄数组"]
    }
    return []
}

WindowEnsureResults(data) {
    if (!data.HasProp("CloseProcess"))
        data.CloseProcess := false
    Loop 7 {
        prop := "ResultVar" A_Index
        if (!data.HasProp(prop))
            data.%prop% := WindowResultDefaultName(data.HasProp("ActionType") ? data.ActionType : "激活窗口", A_Index)
    }
}

WindowRegisterResults(data) {
    for i, label in WindowInfoFields(data.ActionType) {
        prop := "ResultVar" i
        name := GetVarName(data.%prop%)
        if (name == "")
            continue
        if (data.ActionType == "匹配窗口列表")
            MySoftData.GlobalArrMap[name] := true
        else {
            MySoftData.GlobalVariMap[name] := true
            if (label == "句柄")
                MySoftData.HandleVarMap[name] := true
        }
    }
}

WindowMatchModes(allowAll := true) => allowAll ? ["所有", "首个", "最后"] : ["首个", "最后"]

WindowDefaultMatchMode(action, explicit) {
    return explicit && action != "激活窗口" ? "所有" : "首个"
}

; UI 分类与具体动作分离：仍保存原动作键，已有宏无需迁移。
WindowActionGroup(action) {
    switch action {
        case "激活窗口", "关闭窗口": return "窗口操作"
        case "调整宽高", "位置和宽高": return "调整尺寸"
        case "移动窗口", "相对移动", "窗口居中": return "移动窗口"
        case "最大化窗口", "最小化窗口", "还原窗口": return "显示状态"
        case "置顶窗口", "取消置顶", "切换置顶": return "置顶"
        case "开启鼠标穿透", "关闭鼠标穿透", "切换鼠标穿透": return "鼠标穿透"
    }
    return action
}

WindowGroupActions(group) {
    switch group {
        case "窗口操作": return ["激活窗口", "关闭窗口"]
        case "调整尺寸": return ["调整宽高", "位置和宽高"]
        case "移动窗口": return ["移动窗口", "相对移动", "窗口居中"]
        case "显示状态": return ["最大化窗口", "最小化窗口", "还原窗口"]
        case "置顶": return ["置顶窗口", "取消置顶", "切换置顶"]
        case "鼠标穿透": return ["开启鼠标穿透", "关闭鼠标穿透", "切换鼠标穿透"]
    }
    return [group]
}

WindowGroupModes(group) {
    switch group {
        case "窗口操作": return GetLangArr(["激活", "关闭"])
        case "调整尺寸": return GetLangArr(["仅宽高", "位置和宽高"])
        case "移动窗口": return GetLangArr(["绝对位置", "相对移动", "窗口居中"])
        case "显示状态": return GetLangArr(["最大化", "最小化", "还原"])
        case "置顶", "鼠标穿透": return GetLangArr(["开启", "关闭", "切换"])
    }
    return []
}

WindowModeIndex(action) {
    for i, item in WindowGroupActions(WindowActionGroup(action)) {
        if (item == action)
            return i - 1
    }
    return 0
}

WindowActionFromMode(group, mode) {
    actions := WindowGroupActions(group)
    for i, label in WindowGroupModes(group) {
        if (label == mode)
            return actions[i]
    }
    return actions[1]
}

WindowEditorHint(action) {
    switch action {
        case "位置与宽高": return "坐标取窗口左上角，宽高包含标题栏和边框。结果留空则跳过。"
        case "窗口状态": return "结果保存到变量，留空则跳过。状态为 0/1；透明度为 0–100，100 表示完全不透明。"
        case "匹配窗口列表": return "填写数组名，按匹配方式保存窗口句柄；没有匹配时返回空数组。"
        case "标题类名句柄", "进程信息": return "结果保存到变量，留空则跳过。没有匹配时返回空值。"
        case "移动窗口": return "输入屏幕坐标（像素），也可选择变量。"
        case "相对移动": return "输入偏移量（像素），也可选择变量。正数向右/下，负数向左/上。"
        case "窗口居中": return "居中到窗口所在显示器的工作区，避开任务栏。"
        case "调整宽高", "位置和宽高": return "宽高为包含标题栏和边框的像素尺寸，须大于 0；支持变量。"
        case "修改透明度": return "输入 0–100 或变量；0 表示完全透明，100 表示完全不透明。"
        case "关闭窗口": return "默认只关闭窗口；需要结束后台驻留程序时，可勾选关闭进程。"
        case "开启鼠标穿透", "关闭鼠标穿透", "切换鼠标穿透": return "开启后，鼠标点击将穿过该窗口，作用于下方窗口。"
        case "修改标题": return "输入新标题，支持引用变量。"
    }
    return "操作作用于绑定的目标窗口。"
}

WindowNumericInputError(label, value) {
    value := Trim(value)
    if (value == "")
        return label "不能为空，可填写数值或变量"
    if (label == "透明度")
        value := StrReplace(value, "%")
    if (!IsNumber(value))
        return "" ; 变量在执行时解析，编辑时不要求已有值。
    if (label == "宽度" || label == "高度") {
        if (value <= 0 || value != Integer(value))
            return label "须为大于 0 的整数，或填写变量"
    } else if (label == "透明度") {
        if (value < 0 || value > 100)
            return "透明度须在 0–100 之间，或填写变量"
    } else if (value != Integer(value))
        return label "须为整数，或填写变量"
    return ""
}

WindowResultDefaultName(action, index) {
    switch action {
        case "标题类名句柄": names := ["WinTitle", "WinClass", "WinHwnd"]
        case "进程信息": names := ["ProcName", "ProcId", "ProcPath"]
        case "窗口状态": names := ["WinExists", "WinActive", "WinMin", "WinMax", "WinTop", "WinAlpha", "WinPass"]
        case "匹配窗口列表": names := ["WinList"]
        default: names := ["WinX", "WinY", "WinWidth", "WinHeight"]
    }
    return index >= 1 && index <= names.Length ? names[index] : "Result" index
}

; 仅在用户切换类别时替换未修改的默认名；加载已有宏时不重命名输出。
WindowNextResultName(value, oldAction, newAction, index) {
    if (oldAction != newAction && value == WindowResultDefaultName(oldAction, index))
        return WindowResultDefaultName(newAction, index)
    return value
}

WindowInfoFieldTip(action, index) {
    if (action == "位置与宽高") {
        switch index {
            case 1: return "窗口左上角的屏幕 X 坐标。留空则跳过。"
            case 2: return "窗口左上角的屏幕 Y 坐标。留空则跳过。"
            case 3, 4: return "窗口尺寸包含标题栏和边框。留空则跳过。"
        }
    }
    if (action == "匹配窗口列表")
        return "所有匹配窗口句柄"
    if (action != "窗口状态")
        return "填写保存结果的变量名；留空则跳过"
    tips := [
        "1：找到匹配窗口；0：未找到匹配窗口。",
        "1：目标窗口是当前活动窗口；0：未激活或未找到窗口。",
        "1：目标窗口已最小化；0：未最小化或未找到窗口。",
        "1：目标窗口已最大化；0：未最大化或未找到窗口。",
        "1：目标窗口已置顶；0：未置顶或未找到窗口。",
        "0–100：0 为完全透明，100 为完全不透明。未设置透明度时返回 100；未找到窗口时返回空值。",
        "1：已开启鼠标穿透；0：未开启或未找到窗口。开启时点击穿过窗口作用于下方窗口。"
    ]
    return index >= 1 && index <= tips.Length ? tips[index] : ""
}
