#Requires AutoHotkey v2.0
; 1.2.2 -> 1.3：按指令语义迁移，不按字符串全文替换。
; 迁移只读写给定目录；不借用当前配置的资源序号或软件偏好。
; 拆分「运行 / 游戏视角」仍看 1.2.2 的数字；拆完再把指令枚举写成中文。
Compat13_Schemas() {
    return Map("SearchFile", SearchData, "SearchProFile", SearchData, "SearchAllFile", SearchAllData,
        "MMProFile", MMProData, "RunFile", RunData, "FileIOFile", FileIOData,
        "CompareFile", CompareData, "CompareProFile", CompareProData,
        "LoopFile", LoopData, "VariableFile", VariableData, "OperationFile", OperationData,
        "InputFile", InputData, "OutputFile", OutputData, "ExVariableFile", ExVariableData,
        "BGMouseFile", BGMouseData, "BGKeyFile", BGKeyData, "ArrayFile", ArrayData,
        "WindowManageFile", WindowManageData, "KeyCheckFile", KeyCheckData,
        "ScreenShotFile", ScreenShotData, "SubMacroFile", SubMacroData,
        "TextOpsFile", TextOpsData, "TimingFile", TimingData, "CommentFile", CommentData,
        "GraphNodeFile", MacroGraphNode, "GraphStartNodeFile", MacroGraphStartNode)
}

; 缺失字段从当前类补齐；数组保留旧条目数量（不能截成新版默认的一/两项）。
Compat13_FillDefaults(data, defaults) {
    for name, value in defaults.OwnProps() {
        if (!data.HasOwnProp(name))
            data.%name% := value
    }
}

Compat13_Drop(data, names) {
    for name in names {
        if (data.HasOwnProp(name))
            data.DeleteProp(name)
    }
}

; 1.2.2 普通「运行」：Mode 1 = 不等待，Option 1 = 默认（0 起）。缺字段按这两个默认值看，避免新类的中文默认值把全部运行改成运行Pro。
Compat13_IsPlainRun(data) {
    mode := data.HasOwnProp("Mode") ? data.Mode : 1
    opt := data.HasOwnProp("Option") ? data.Option : 1
    plainMode := mode == 1 || mode == "1" || mode == "不等待"
    plainOpt := opt == 1 || opt == "1" || opt == "默认"
    return plainMode && plainOpt
}

Compat13_IsGameView(data) {
    mode := data.HasOwnProp("MouseMoveMode") ? data.MouseMoveMode : 0
    return mode == 2 || mode == "2" || mode == "游戏视角"
}

; 序列码前缀即指令键。须在运行/游戏视角拆分之后调用，否则数字比较会失效。
Compat13_ApplyEnums(data, key) {
    if (!IsObject(data))
        return
    prefix := RegExReplace(String(key), "\d+$", "")
    if (prefix == "" && data.HasProp("SerialStr"))
        prefix := RegExReplace(String(data.SerialStr), "\d+$", "")
    CmdEnumNorm(prefix, data)
}

Compat13_Store(values, key, data) {
    Compat13_ApplyEnums(data, key)
    values[key] := JSON.stringify(data, 0)
}

Compat13_Normalize(data, stem) {
    schemas := Compat13_Schemas()
    if (!schemas.Has(stem))
        return
    ; 旧字段先归一化，避免默认字段挡住 RunPath/RunMode 等更早版本的映射。
    if (stem == "RunFile")
        CompatEnsureRunData(data)
    if (stem == "TimingFile")
        NormalizeTimingData(data)
    if ((stem == "SearchFile" || stem == "SearchProFile") && !data.HasOwnProp("SearchImageType"))
        data.SearchImageType := 1 ; 新增软件级模型选项使用默认值，不借用当前正在运行的方案。
    ; 旧文本替换只保存 MatchType，补默认值前同步编辑器使用的 ArgsType。
    if (stem == "TextOpsFile" && data.HasOwnProp("Type") && data.Type == "文本替换"
        && data.HasOwnProp("MatchType"))
        data.ArgsType := data.MatchType
    defaults := schemas[stem]()
    if (stem == "TimingFile") {
        ; 缺少周期参数时保留缺失状态，避免替旧宏猜测执行频率。
        defaults.DeleteProp("CustomInterval")
        defaults.DeleteProp("CustomUnit")
    }
    Compat13_FillDefaults(data, defaults)
    if (stem == "FileIOFile") {
        types := Map("1", "读取Excel", "2", "写入Excel", "3", "读取文件", "4", "写入文件")
        data.OperType := types.Has(String(data.OperType)) ? types[String(data.OperType)] : FileIONormType(data.OperType)
    }
    if (stem == "SearchFile" || stem == "SearchProFile") {
        ; 废弃的窗口规则不自动挑选，不用其它分辨率条目覆盖当前选定参数。
        Compat13_Drop(data, ["ConfigName", "ConfigArr"])
        if (!data.HasOwnProp("Adaptive"))
            data.Adaptive := 0
    }
    if (stem == "MMProFile") {
        ; 先兼容更早版本布尔模式，再移除已废弃的窗口规则。
        if (data.HasOwnProp("IsGameView") && data.IsGameView)
            data.MouseMoveMode := 2
        else if (data.HasOwnProp("IsRelative") && data.IsRelative)
            data.MouseMoveMode := 1
        Compat13_Drop(data, ["ConfigName", "ConfigArr", "IsGameView", "IsRelative"])
    }
    groups := Map(
        "CompareFile", ["ToggleArr", "NameArr", "CompareTypeArr", "VariableArr"],
        "LoopFile", ["ToggleArr", "NameArr", "CompareTypeArr", "VariableArr"],
        "VariableFile", ["ToggleArr", "OperaTypeArr", "VariableArr", "CopyVariableArr", "MinVariableArr", "MaxVariableArr"],
        "OperationFile", ["ToggleArr", "UpdateNameArr", "ExpressionArr"])
    if (groups.Has(stem)) {
        defaults := schemas[stem]()
        fields := groups[stem]
        count := data.ToggleArr.Length
        for field in fields {
            arr := data.%field%
            while (arr.Length < count)
                arr.Push(defaults.%field%[1])
        }
    }
}

; 改名碰撞时分配新序号，所有引用随后按完整指令序列码改写。
Compat13_Rename(root, oldKey, prefix, renames) {
    suffix := RegExReplace(oldKey, "^.*?(\d+)$", "$1")
    newKey := prefix suffix
    n := 1
    while (root.Has(newKey)) {
        newKey := prefix n
        n++
    }
    data := JSON.parse(root[oldKey], , false)
    data.SerialStr := newKey
    root[newKey] := JSON.stringify(data, 0)
    root.Delete(oldKey)
    renames[oldKey] := newKey
    return newKey
}

Compat13_UpgradeDir(dir) {
    sec := IniImport_Section()
    renames := Map()
    changed := false
    for stem, cls in Compat13_Schemas() {
        path := dir "\" stem ".toml"
        if (!FileExist(path))
            continue
        root := Cfg_Load(path)
        if (!root.Has(sec))
            continue
        values := root[sec]
        before := JSON.stringify(values, 0)
        for key, val in values.Clone() {
            data := CompatParseData(val)
            if (!IsObject(data))
                continue
            Compat13_Normalize(data, stem)
            if (stem == "FileIOFile" && RegExMatch(key, "^文件读写\d+$") && FileIOIsExcelType(data.OperType)) {
                Compat13_Store(values, key, data)
                Compat13_Rename(values, key, "Excel", renames)
            }
            else if (stem == "RunFile" && RegExMatch(key, "^运行\d+$") && !Compat13_IsPlainRun(data)) {
                Compat13_Store(values, key, data)
                Compat13_Rename(values, key, "运行Pro", renames)
            }
            else if (stem == "MMProFile" && RegExMatch(key, "^(移动Pro|鼠标移动Pro)\d+$")) {
                if (Compat13_IsGameView(data)) {
                    delta := DeltaMoveData()
                    delta.SerialStr := key
                    delta.DeltaX := data.PosVarX
                    delta.DeltaY := data.PosVarY
                    delta.Count := data.HasOwnProp("Count") ? data.Count : 1
                    delta.Interval := data.HasOwnProp("Interval") ? data.Interval : 1000
                    ; 增量移动有独立资源文件，不能写进 MMProFile。
                    dest := dir "\DeltaMoveFile.toml"
                    deltaRoot := Cfg_Load(dest)
                    target := Cfg_Seg(deltaRoot, sec)
                    n := 1
                    while (target.Has("增量移动" n))
                        n++
                    delta.SerialStr := "增量移动" n
                    target[delta.SerialStr] := JSON.stringify(delta, 0)
                    Cfg_WriteRoot(deltaRoot, dest)
                    values.Delete(key)
                    renames[key] := delta.SerialStr
                } else {
                    Compat13_Drop(data, ["Count", "Interval"])
                    Compat13_Store(values, key, data)
                    if (RegExMatch(key, "^移动Pro\d+$"))
                        Compat13_Rename(values, key, "鼠标移动Pro", renames)
                }
            }
            else
                Compat13_Store(values, key, data)
        }
        if (before != JSON.stringify(values, 0)) {
            Cfg_WriteRoot(root, path)
            changed := true
        }
    }
    changed := Compat13_UpgradeLooseEnums(dir) || changed
    rewrite := (macro) => Compat13_Macro(macro, renames)
    return Compat_RewriteMacroFiles(dir, rewrite, Compat13_RewriteBranches) || changed
}

; 只遍历宏表和指令资源里的宏字段，避免改写备注、提示正文和路径。
Compat_RewriteMacroFiles(dir, rewriteMacro, rewriteBranches, beforeWrite := "", skipFile := "") {
    changed := false
    loop files, dir "\*.toml" {
        if (A_LoopFileName == skipFile)
            continue
        path := A_LoopFileFullPath
        if (A_LoopFileName == "MacroFile.toml") {
            ; 通过 TomlUtil 保留 [[table]] 数组，不能使用 Cfg 的标量存储层写宏表。
            TomlUtil_Invalidate(path)
            root := TomlUtil_RootMap(path)
            dirty := false
            for section, fields in root {
                if (!(fields is Map))
                    continue
                for key, value in fields {
                    field := TomlUtil_StripKey(key)
                    if (Type(value) == "String" && RegExMatch(field, "^(?:Macro|PreMacro|PostMacro|[A-Za-z]+MacroArr\d+)$")) {
                        next := rewriteMacro.Call(value)
                        if (next != value) {
                            fields[key] := next
                            dirty := true
                        }
                    }
                }
            }
            if (dirty) {
                if (beforeWrite != "")
                    beforeWrite.Call()
                TomlUtil_Write(root, path)
                CfgInvalidate(path)
                changed := true
            }
            continue
        }
        root := Cfg_Load(path)
        dirty := false
        for section, fields in root {
            for key, value in fields {
                if (Type(value) != "String")
                    continue
                data := CompatParseData(value)
                if (!IsObject(data))
                    continue
                if (rewriteBranches.Call(data, rewriteMacro)) {
                    fields[key] := JSON.stringify(data, 0)
                    dirty := true
                }
            }
        }
        if (dirty) {
            if (beforeWrite != "")
                beforeWrite.Call()
            Cfg_WriteRoot(root, path)
            changed := true
        }
    }
    return changed
}

; 不参与运行/游戏视角拆分的指令文件。枚举数字同样写成中文。
Compat13_UpgradeLooseEnums(dir) {
    changed := false
    sec := IniImport_Section()
    for stem in ["SearchComboFile", "JoyCheckFile", "IntervalFile", "KeyDataFile", "MoveDataFile", "WaitFile"
        , "TimeDataFile", "CountDownFile", "WaitConfirmFile", "RMTCMDFile", "DeltaMoveFile"] {
        path := dir "\" stem ".toml"
        if (!FileExist(path))
            continue
        root := Cfg_Load(path)
        if (!root.Has(sec))
            continue
        values := root[sec]
        before := JSON.stringify(values, 0)
        for key, val in values.Clone() {
            data := CompatParseData(val)
            if (!IsObject(data))
                continue
            Compat13_Store(values, key, data)
        }
        if (before != JSON.stringify(values, 0)) {
            Cfg_WriteRoot(root, path)
            changed := true
        }
    }
    return changed
}

Compat13_RewriteBranches(data, rewrite) {
    return Compat_RewriteMacroFields(data, rewrite,
        ["TrueMacro", "FalseMacro", "DefaultMacro", "LoopBody", "CurCMD"], ["MacroArr"])
}

Compat_RewriteMacroFields(data, rewrite, fields, arrays) {
    changed := false
    for field in fields {
        if (!data.HasOwnProp(field) || Type(data.%field%) != "String")
            continue
        next := rewrite.Call(data.%field%)
        if (next != data.%field%) {
            data.%field% := next
            changed := true
        }
    }
    for field in arrays {
        if (!data.HasOwnProp(field) || !(data.%field% is Array))
            continue
        for index, value in data.%field% {
            if (Type(value) != "String")
                continue
            next := rewrite.Call(value)
            if (next != value) {
                data.%field%[index] := next
                changed := true
            }
        }
    }
    return changed
}

Compat13_Macro(macro, renames) {
    ; 保留分隔符、换行和空参数，只替换每条命令本身。
    result := ""
    start := 1
    while (pos := RegExMatch(macro, "[^,，`n⫶]+", &match, start)) {
        result .= SubStr(macro, start, pos - start) Compat13_Command(renames, match)
        start := pos + StrLen(match[0])
    }
    return result SubStr(macro, start)
}

Compat13_Command(renames, match) {
    original := match[0]
    cmd := Trim(original)
    parts := SplitCommand(cmd)
    if (parts.Length == 0)
        return original
    marker := GetCmdSymbol(parts[1])
    parts[1] := GetCmdStr(parts[1])
    if (renames.Has(parts[1]))
        parts[1] := renames[parts[1]]
    if (parts[1] == "移动")
        parts[1] := "鼠标移动"
    ; 内联指令里的模式/动作编号写成中文。序列码指令（按键1、鼠标移动2）没有这些段。
    if (parts[1] == "鼠标移动" && parts.Length >= 5 && IsNumber(parts[5]))
        parts[5] := CmdEnumMoveMode(parts[5])
    if (parts[1] == "按键" && parts.Length >= 3 && IsNumber(parts[3]))
        parts[3] := CmdEnumKeyAct(parts[3])
    ; 纯手柄按钮/模拟轴迁到新手柄语法；混合键鼠+手柄组合仍由旧执行器整体发送，避免拆开改变同时按下语义。
    if (parts[1] == "按键" && parts.Length >= 2) {
        joy := []
        allJoy := true
        for key in StrSplit(parts[2], "⎖") {
            mapped := Compat13_JoyShort(key)
            if (mapped == key) {
                allJoy := false
                break
            }
            joy.Push(mapped)
        }
        if (allJoy && joy.Length) {
            parts[1] := "手柄"
            parts[2] := ""
            for key in joy
                parts[2] .= (parts[2] == "" ? "" : "+") key
        }
    }
    result := marker
    for i, part in parts
        result .= (i == 1 ? "" : "_") part
    return StrReplace(original, cmd, result)
}

Compat13_JoyShort(key) {
    ; 旧录制使用 Joy1..14，旧通用按钮名使用 AxisLT / DpadUp。
    names := ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "LS", "RS", "Back", "Start", "Home", "Pad"]
    if (RegExMatch(key, "^Joy(\d+)$", &m) && Integer(m[1]) >= 1 && Integer(m[1]) <= names.Length)
        return names[Integer(m[1])]
    aliases := Map("AxisLT", "JoyLT", "AxisRT", "JoyRT", "DpadUp", "JoyDpadUp",
        "DpadDown", "JoyDpadDown", "DpadLeft", "JoyDpadLeft", "DpadRight", "JoyDpadRight")
    return JoyInternalToShort(aliases.Has(key) ? aliases[key] : key)
}

; 只在旧 MainSettings.ini 转换时应用。没有对应项的键不带入，缺省值由 1.3 加载器提供。
; 不迁移运行态/旧界面选中索引，不把旧分散颜色或自定义色板强行映射成新主题槽位。
Compat13_Settings(sections) {
    supported := Map()
    for key in ["CurSettingName", "SettingArrStr", "MacroTotalCount", "NormalPeriod", "HoldFloat", "PreIntervalFloat", "IntervalFloat", "CoordXFloat", "CoordYFloat"]
        supported[key] := true
    for key in ["SuspendHotkey", "PauseHotkey", "KillMacroHotkey", "IsToolCheck", "ToolCheckHotKey", "RecordMacroHotKey", "ToolTextFilterHotKey", "ScreenShotHotKey"]
        supported[key] := true
    for key in ["FreePasteHotKey", "RecordKeyboard", "RecordMouse", "RecordJoy", "RecordMouseTrail", "RecordMouseTrailSpeed", "RecordHoldMuti", "RecordAutoLoosen"]
        supported[key] := true
    for key in ["RecordJoyInterval", "RecordShowBorder", "OCRType", "IsBootStart", "IsAdminStart", "ShowSplitLine", "FixedMenuWheel", "MenuWheelSelectMode"]
        supported[key] := true
    for key in ["MenuWheelShowTooltip", "MenuWheelScale", "Theme", "UIPanelShowOnActive", "UIPanelBtnHeight"]
        supported[key] := true
    for key in ["UIPanelFontSize", "UIPanelBtnWidth", "UIPanelCols", "IsModalSubGui", "MutiThreadNum", "DynamicCorePoolSize", "ElasticTimeout", "MacroStopType"]
        supported[key] := true
    for key in ["SoftBGColor", "NoVariableTip", "CMDTip", "CheckForeground", "ScreenShotType", "KeyDownDown", "AutoLoosenModifier", "ContinuousTrigger"]
        supported[key] := true
    for key in ["AgreeAgreement", "WinPosX", "WinPosY", "Lang", "FontType", "JoyType", "TriggerJoyType", "PreferredMacroEditor"]
        supported[key] := true
    for key in ["SharedCopy", "GeneralContextMenu", "BranchContextMenu", "RemarkAutoType", "CMDWidth", "CMDHeight", "CMDPosX", "CMDPosY"]
        supported[key] := true
    for key in ["CountDownStyle", "CountDownPadZero", "CountDownAlpha", "CountDownFontSize"]
        supported[key] := true
    for key in ["CMDTransparency", "CMDFontSize", "CMDLogToFile", "CMDLogFilePath", "CMDLogAutoClear", "VarListenTop", "VarListenWidth", "VarListenHeight"]
        supported[key] := true
    sec := IniImport_Section()
    if (sections.Has(sec)) {
        values := sections[sec]
        for key in values.Clone() {
            if (!supported.Has(key))
                values.Delete(key)
        }
        ; 已有对应含义的枚举照用；非法/已移除的选项删除，让读取端使用当前默认值。
        if (values.Has("JoyType") && values["JoyType"] == "PS5")
            values["JoyType"] := "DS4" ; 与 1.3 加载器已有的 ViGEm 别名对应。
        enums := Map("MacroStopType", "1,2",
            "KeyDownDown", "1,2", "MenuWheelSelectMode", "1,2", "JoyType", "Xbox,DS4")
        for key, options in enums {
            if (values.Has(key) && !InStr("," options ",", "," values[key] ","))
                values.Delete(key)
        }
    }
    ; 预设名称交给现有主题加载器校验；不支持的预设自动回退默认主题。
    theme := Map()
    if (sections.Has("ThemeColors") && sections["ThemeColors"].Has("AppTheme")) {
        name := sections["ThemeColors"]["AppTheme"]
        if (name != "Custom")
            theme["AppTheme"] := name
    }
    for name in sections.Clone() {
        if (name != sec)
            sections.Delete(name)
    }
    if (theme.Count)
        sections["ThemeColors"] := theme
    return sections
}

; 完整 1.3 阶段：设置语义、指令拆分、宏结构及宏目标引用。
Compat13_UpgradeProfile(dir) {
    changed := Compat13_UpgradeSettings(dir)
    changed := Compat13_UpgradeDir(dir) || changed
    return IniImport_ExpandFlatMacroFile(dir) || changed
}

Compat13_UpgradeSettings(dir) {
    path := dir "\MainSettings.toml"
    if (!FileExist(path))
        return false
    root := Cfg_Load(path)
    before := JSON.stringify(root, 0)
    root := Compat13_Settings(root)
    if (JSON.stringify(root, 0) == before)
        return false
    Cfg_WriteRoot(root, path)
    return true
}
