#Requires AutoHotkey v2.0

; 指令枚举存中文。names 为存储顺序，base 为旧数字起点（1 或 0）。
; 已是中文（或当前语言译文）时原样收成中文键；旧数字按顺序映射。

CmdEnumZh(value, names, base := 1) {
    if (!IsObject(names) || names.Length == 0)
        return ""
    key := GetLangKey(Trim(String(value)))
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
        key := GetLangKey(Trim(String(value)))
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

CmdEnumCompareNames() => ["大于", "大于等于", "等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配", "不等于"]
CmdEnumCompareShowNames() => ["大于", "大于等于", "等于", "不等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配"]
CmdEnumLogicNames() => ["且", "或"]
CmdEnumOperaNames() => ["数值", "随机数值", "字符", "系统", "时间", "删除"]
CmdEnumWaitNames() => ["等待变量值", "等待按键按下", "等待按键松开", "等待屏幕变化", "等待鼠标移动",
    "等待鼠标停止移动", "等待剪切板变化", "等待进程存在", "等待进程关闭", "等待窗口存在",
    "等待窗口激活", "等待窗口屏幕变化", "等待窗口大小变化", "等待窗口关闭", "等待窗口最小化",
    "等待文件存在", "等待文件删除", "等待文件变化", "等待日期"]

; 编辑器只提供条件等待；日期统一使用时间指令。旧枚举保留，兼容已保存的宏。
CmdEnumWaitEditorNames() {
    names := CmdEnumWaitNames()
    names.Pop()
    return names
}

CmdEnumWaitEditorLabels() {
    labels := []
    for key in CmdEnumWaitEditorNames()
        labels.Push(GetLang(SubStr(key, 3)))
    return labels
}
CmdEnumSearchNames() => ["屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"]
CmdEnumMouseActNames() => ["无动作", "移动至目标", "移动至目标点击1次", "移动至目标点击2次"]
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
    if (IsNumber(value) && Integer(value) == 7)
        return "时间"
    key := GetLangKey(Trim(String(value)))
    if (key == "随机")
        return "随机数值"
    return CmdEnumZh(value, CmdEnumOperaNames())
}

CmdEnumMoveMode(value) => CmdEnumZh(value, CmdEnumMoveModeNames(), 0)
CmdEnumRef(value) => CmdEnumZh(value, CmdEnumRefNames(), 0)
CmdEnumKeyAct(value) => CmdEnumZh(value, CmdEnumKeyActNames())
CmdEnumRunOption(value) => CmdEnumZh(value, CmdEnumRunOptionNames(), 0)
CmdEnumNameType(value) => CmdEnumZh(value, CmdEnumNameTypeNames(), 0)
CmdEnumWait(value) => CmdEnumZh(value, CmdEnumWaitNames())
CmdEnumSearch(value) => CmdEnumZh(value, CmdEnumSearchNames())
CmdEnumMouseAct(value) => CmdEnumZh(value, CmdEnumMouseActNames())
CmdEnumMMAction(value) => CmdEnumZh(value, CmdEnumMMActionNames())
CmdEnumTimingType(value) {
    key := GetLangKey(Trim(String(value)))
    if (key == "自定义")
        return "周期触发"
    return CmdEnumZh(value, CmdEnumTimingTypeNames())
}
CmdEnumTimingUnit(value) => CmdEnumZh(value, CmdEnumTimingUnitNames())
CmdEnumTimingDuration(value) => CmdEnumZh(value, CmdEnumTimingDurationNames())

CmdEnumJoyCheck(value, analog) {
    key := GetLangKey(Trim(String(value)))
    for name in CmdEnumKeyCheckNames() {
        if (key == name)
            return name
    }
    for name in CmdEnumJoyAnalogNames() {
        if (key == name)
            return name
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
        case "搜索", "搜索Pro", "搜索Combo", "组合搜索", "搜索Multi":
            CmdEnumNormSearchObj(Data)
            if (Data.HasProp("SearchTargetArr") && IsObject(Data.SearchTargetArr)) {
                for t in Data.SearchTargetArr
                    CmdEnumNormSearchObj(t)
            }
        case "移动Pro", "鼠标移动Pro":
            CmdEnumSet(Data, "MouseMoveMode", CmdEnumMoveModeNames(), 0)
            ; 相对模式旧编号 4 是「拖拽」；绝对模式的 4 才是「A到B拖拽」
            if (Data.MouseMoveMode == "相对移动" && (Data.ActionType == 4 || Data.ActionType == "4"))
                Data.ActionType := "拖拽"
            else
                CmdEnumSet(Data, "ActionType", CmdEnumMMActionNames())
            CmdEnumSet(Data, "RefMode", CmdEnumRefNames(), 0)
        case "移动", "鼠标移动":
            CmdEnumSet(Data, "MoveMode", CmdEnumMoveModeNames(), 0)
        case "等待":
            CmdEnumSet(Data, "WaitType", CmdEnumWaitNames())
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
        case "间隔":
            CmdEnumSet(Data, "Type", CmdEnumIntervalNames())
        case "按键检测":
            CmdEnumSet(Data, "CheckType", CmdEnumKeyCheckNames())
            CmdEnumSet(Data, "StateType", CmdEnumStateNames())
        case "手柄检测":
            if (Data.HasProp("CheckType"))
                Data.CheckType := CmdEnumJoyCheck(Data.CheckType, CmdEnumJoyAnalog(Data))
            CmdEnumSet(Data, "StateType", CmdEnumStateNames())
        case "运行", "运行Pro":
            CmdEnumSet(Data, "Mode", CmdEnumRunModeNames())
            CmdEnumSet(Data, "Option", CmdEnumRunOptionNames(), 0)
        case "Timing":
            if (Data.HasProp("Type"))
                Data.Type := CmdEnumTimingType(Data.Type)
            CmdEnumSet(Data, "CustomUnit", CmdEnumTimingUnitNames())
            if (Data.HasProp("DurationMode"))
                Data.DurationMode := CmdEnumTimingDuration(Data.DurationMode)
            if (Data.HasProp("DurationUnit"))
                Data.DurationUnit := CmdEnumTimingUnit(Data.DurationUnit)
        case "抓图":
            CmdEnumSet(Data, "ScreenShotType", CmdEnumShotNames())
            CmdEnumSet(Data, "NameType", CmdEnumNameTypeNames(), 0)
        case "时间":
            CompatEnsureTimeData(Data)
        case "倒计时":
            CompatEnsureCountDownData(Data)
        case "输出":
            CmdEnumSetNum(Data, "OutputType", ["发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板", "字符变量"])
        case "宏操作":
            CmdEnumSetNum(Data, "MacroType", ["当前宏", "按键宏", "字串宏", "菜单宏", "定时宏", "宏"])
            CmdEnumSetNum(Data, "CallType", ["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        case "窗口管理":
            ; 保留旧数字顺序，新类型只在界面插入，避免旧配置操作错位。
            CmdEnumSetNum(Data, "ActionType", ["激活窗口", "最大化窗口", "最小化窗口", "还原窗口", "关闭窗口", "移动窗口", "调整宽高", "置顶窗口", "取消置顶", "修改标题", "修改透明度", "开启鼠标穿透", "关闭鼠标穿透"])
            if (Data.ActionType == "调整大小")
                Data.ActionType := "调整宽高"
            if (!Data.HasProp("WidthVarName"))
                Data.WidthVarName := "Var1"
            if (!Data.HasProp("HeightVarName"))
                Data.HeightVarName := "Var2"
        case "文件读写", "Excel":
            if (Data.HasProp("OperType")) {
                types := Map("1", "读取Excel", "2", "写入Excel", "3", "读取文件", "4", "写入文件")
                key := String(Data.OperType)
                Data.OperType := types.Has(key) ? types[key] : FileIONormType(Data.OperType)
            }
    }
}
