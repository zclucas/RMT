#Requires AutoHotkey v2.0
#Include ..\Shared\OfficialLanguages.ahk
#Include XamlText.ahk                 ; EscapeXamlXml：本文件第 32 行直接用，不能等 XAML 库
global MainSoftData                ; 在 GlobalUtil.ahk 中由 MainConfig() 赋值
LangKeyMap := Map()
LangValueMap := Map()              ; 文本反向映射（本地化显示名 -> 内部简中键）

; 指令与界面关键 key（优先保证反向映射正确）
LangCmdKeyArr := [
    "关闭进程", "窗口操作", "调整尺寸", "仅宽高", "激活", "显示状态", "置顶", "鼠标穿透", "绝对位置", "最大化", "最小化", "还原", "开启", "关闭", "切换",
    "窗口位置", "获取窗口宽高", "位置与宽高", "标题类名句柄", "进程信息", "窗口状态", "透明度与鼠标穿透状态", "匹配窗口列表", "激活窗口", "移动窗口", "相对移动",
    "窗口居中", "调整宽高", "位置和宽高", "最大化窗口", "最小化窗口", "还原窗口", "置顶窗口", "取消置顶", "切换置顶", "修改标题", "修改透明度",
    "开启鼠标穿透", "关闭鼠标穿透", "切换鼠标穿透", "关闭窗口", "截图", "截图提取文本", "自由贴", "开启指令显示", "关闭指令显示", "显示菜单", "关闭菜单",
    "打开界面窗口", "关闭界面窗口", "禁用模块", "取消禁用模块",
    "启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠",
    "休眠", "暂停所有宏", "恢复所有宏", "终止所有宏", "重载", "关闭软件", "间隔", "按键", "手柄", "手柄检测", "搜索", "搜索Pro", "搜索All", "搜索Combo",
    "组合搜索", "搜索Multi", "移动", "移动Pro", "鼠标移动", "鼠标移动Pro", "增量移动", "流程跳转", "循环-跳过本轮", "循环-跳出", "分支-跳出",
    "输出", "提示", "运行", "运行Pro", "循环", "宏操作", "变量", "变量提取", "如果", "如果Pro", "运算", "RMT指令", "后台鼠标", "后台按键",
    "等待", "等待确定", "时间", "倒计时", "按键检测", "窗口管理", "窗口信息", "调整窗口", "窗口操作", "进程管理", "注释", "抓图",
    "循环次数", "宏循环次数", "运行时坐标X", "运行时坐标Y", "运行时窗口坐标X", "运行时窗口坐标Y", "按下", "松开", "点击", "创建", "克隆", "删除", "包含",
    "取值", "赋值", "插入", "追加", "移除", "移除最后", "长度", "变量或值", "数组", "文本分割", "文本提取", "文本替换", "去除空格",
    "时间戳处理", "自定义格式", "提取时间量", "提取所有时间量", "日期时间", "日期", "时刻",
    "大小写转换", "文本统计", "去除前空白字符", "去除后空白字符", "去除前后空白字符", "去除所有空白字符", "全部大写", "全部小写",
    "首字母大写", "字符数", "单词数", "行数", "数字提取", "字母提取", "中文提取", "内容分割", "定长分割", "当前宏",
    "插入到当前宏", "触发", "暂停", "取消暂停", "终止", "制表符", "弹窗", "状态", "选择", "选择文件", "多选", "文本文件", "继续", "继续&取消", "继续&终止&暂停",
    "用默认值", "保持原值", "自动继续", "自动终止", "自动暂停", "等待结束",
    "暂停当前宏", "暂停所有宏", "终止当前宏", "终止所有宏", "读取全部内容", "逐行读取", "指定行", "单元格", "指定列", "指定区域-行",
    "指定区域-列", "网络请求", "浏览器", "控件信息", "控件操作", "AI判断", "YOLO检测", "JSON", "表单", "原始文本", "文件读写", "Excel", "读取文件", "写入文件", "读取文本文件", "写入文本文件",
    "发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板",
    "翻译", "翻译编辑器", "来源", "内容", "目标语言", "引擎", "术语表", "固定文本",
    "简体中文", "繁体中文", "英语", "日语", "韩语", "俄语", "法语", "德语", "西班牙语",
    "翻译内容为空", "翻译模型未下载", "翻译组件缺失，请先编译 Plugins\Translate", "翻译组件版本不匹配，请重新编译", "翻译已取消", "翻译组件仅支持 64 位",
    "翻译超时(ms)", "本地与 AI 通道共用，范围 1000～3600000 毫秒。", "下载管理", "管理下载", "打开下载目录", "打开目录",
    "共 {} 个下载任务，{} 个进行中", "排队中", "下载中", "已完成", "失败", "已取消", "取消", "重试",
    "无法启动下载进程", "下载超时", "下载文件无效", "curl 下载失败，错误码 {}",
    "翻译模型：{}", "翻译模型已就绪", "翻译组件已就绪", "已加入后台下载，可在设置中查看进度。", "翻译模型下载失败，请在下载管理中重试。",
    "本地翻译模型未下载（{}，约 {}），是否加入后台下载？", "翻译组件", "翻译组件已加入后台下载，可在设置中查看进度。",
    "翻译组件下载失败，请在下载管理中重试。", "安装翻译组件", "正在解压", "翻译组件下载完成，但解压失败。",
    "本地翻译模型 {} 未下载，已请求后台下载；当前宏已中断。", "翻译结果可能不完整，已写入部分译文。", "结果可能不完整",
    "友好错误会提示并继续；技术错误仍会中断。填入后也会把错误信息写入该变量。", "原文已存在，请先删除旧术语对照。"
]

LanguageOptionXaml(key, label, flag := "") {
    label := EscapeXamlXml(label)
    key := EscapeXamlXml(key)
    if (SubStr(key, 1, 1) == "{")
        key := "{}" key
    if (SubStr(label, 1, 1) == "{")
        label := "{}" label
    attrs := ' Tag="' key '" TextSearch.Text="' label '"'
    path := LangDir "\Flags\" flag ".png"
    if (flag == "" || !FileExist(path))
        return '<ComboBoxItem' attrs ' Content="' label '"/>'
    return '<ComboBoxItem' attrs '><StackPanel Orientation="Horizontal">'
        . '<Image Width="20" Height="14" Margin="0,0,7,0" Source="' EscapeXamlXml(StrReplace(path, "\", "/")) '"/>'
        . '<TextBlock VerticalAlignment="Center" Text="' label '"/></StackPanel></ComboBoxItem>'
}

LangInitSetting() {
    MainSoftData.LangArr := ["简中"]   ; 简中为内置默认，首位展示
    LangMap := Map("简中", 1)

    if (DirExist(LangDir)) {
        officialNames := ["繁體中文"]
        for name in OfficialLanguages() {
            if (name != "简中" && name != "繁體中文")
                officialNames.Push(name)
        }
        for name in officialNames {
            if (FileExist(LangDir "\" name ".txt")) {
                LangMap[name] := 1
                MainSoftData.LangArr.Push(name)
            }
        }
        loop files, LangDir "\*.txt" {
            SplitPath A_LoopFileName, &OutFileName, &OutDir, &OutExtension, &OutNameNoExt, &OutDrive
            if (OutNameNoExt == "简中" || OutNameNoExt == "中文")
                continue
            if (!LangMap.Has(OutNameNoExt)) {
                LangMap[OutNameNoExt] := 1
                MainSoftData.LangArr.Push(OutNameNoExt)
            }
        }
    }

    ; 未知语言统一换成简中
    if (!LangMap.Has(MainSoftData.Lang)) {
        ChineseMap := Map("7804", 1, "0004", 1, "0804", 1, "1004", 1, "7C04", 1, "0C04", 1, "1404", 1, "0404", 1)
        if (ChineseMap.Has(A_Language))
            MainSoftData.Lang := "简中"
        else if (LangMap.Has("English"))
            MainSoftData.Lang := "English"
        else
            MainSoftData.Lang := "简中"
    }
}

LangKeysInit() {
    global LangKeyMap
    LangKeyMap := Map()
    LangValueMap.Clear()
    CommandLanguageIndex(true)

    if (MainSoftData.Lang == "简中")
        return

    LangFilePath := Format("{}\{}.txt", LangDir, MainSoftData.Lang)
    if (!FileExist(LangFilePath)) {
        MainSoftData.Lang := "简中"
        return
    }

    try {
        LangKeyMap := ReadLanguageFile(LangFilePath)
        for key, val in LangKeyMap {
            if (val != "" && !LangValueMap.Has(val))
                LangValueMap[val] := Trim(key)
        }
    } catch as e {
        MsgBox GetLang("读取文件失败:") e.Message
    }

    commandKeys := LangCmdKeyArr.Clone()
    try {
        for def in MacroCategoryDefs()
            commandKeys.Push(def[2])
    }
    for value in commandKeys {
        key := GetLang(value)
        if (key != value)
            LangValueMap[key] := value
    }
}

ReadLanguageFile(path) {
    translations := Map()
    file := FileOpen(path, "r", "UTF-8")
    try {
        while !file.AtEOF {
            line := file.ReadLine()
            eqPos := RegExMatch(line, "(?<!\\)=")
            if (eqPos <= 1)
                continue
            rawKey := StrReplace(SubStr(line, 1, eqPos - 1), "\=", "=")
            val := SubStr(line, eqPos + 1)
            if (InStr(rawKey, "``n", true)) {
                rawKey := StrReplace(rawKey, "``n", "`n", true)
                val := StrReplace(val, "``n", "`n", true)
            }
            translations[rawKey] := val
            trimmedKey := Trim(rawKey)
            if (trimmedKey != rawKey && !translations.Has(trimmedKey))
                translations[trimmedKey] := val
        }
    } finally {
        file.Close()
    }
    return translations
}

InstalledLanguageMaps() {
    static cache := Map()
    if (!IsSet(LangDir) || LangDir == "")
        return []
    if (!cache.Has(LangDir)) {
        maps := []
        loop files, LangDir "\*.txt" {
            if (A_LoopFileName == "简中.txt" || A_LoopFileName == "中文.txt")
                continue
            try maps.Push(ReadLanguageFile(A_LoopFileFullPath))
        }
        cache[LangDir] := maps
    }
    return cache[LangDir]
}

; 同一译文可能用于不同字段，按当前字段的可选键查找。
GetConfigKey(value, keys) {
    for key in keys {
        if (value == key)
            return key
    }
    label := Trim(value)
    if (label == "")
        return value
    for key in keys {
        if (label == Trim(GetLang(key)))
            return key
    }
    for translations in InstalledLanguageMaps() {
        for key in keys {
            if (label == Trim(translations.Get(key, "")))
                return key
        }
    }
    return value
}

; 动态切换当前应用语言
SetAppLanguage(lang) {
    MainSoftData.Lang := lang
    LangKeysInit()
}

; getstatus 的 language：内置语言用语言代码，自定义语言用文件名（小写、去空格）
GetClientLanguageCode() {
    lang := ""
    try lang := MainSoftData.Lang
    if (lang == "")
        return "zh"
    languages := OfficialLanguages()
    if (languages.Has(lang))
        return languages[lang].code
    code := StrLower(StrReplace(lang, " ", ""))
    return code == "" ? "zh" : code
}

GetLang(Key) {
    if (SubStr(Key, 1, 1) == "❖")
        return GetBuiltinVarName(Key, true)
    ; 简中指令显示短名称，配置继续使用原指令键。
    if (MainSoftData.Lang == "简中") {
        switch Key {
            case "进程管理": return "进程"
            case "完整路径匹配": return "完整路径"
        }
        return Key
    }
    if (LangKeyMap.Count == 0)
        return Key

    if (LangKeyMap.Has(Key))
        return LangKeyMap[Key]

    return Key
}

GetLangArr(KeyArr) {
    ResArr := []
    for Value in KeyArr
        ResArr.Push(GetLang(Value))
    return ResArr
}

GetLangKey(Value) {
    if (SubStr(Value, 1, 1) == "❖")
        return GetBuiltinVarName(Value)
    ; 简中模式或未加载映射时直接返回原 value
    if (MainSoftData.Lang == "简中" || LangValueMap.Count == 0)
        return Value

    if (LangValueMap.Has(Value))
        return LangValueMap[Value]

    return Value
}

GetLangKeyArr(ValueArr) {
    ResArr := []
    for Value in ValueArr
        ResArr.Push(GetLangKey(Value))
    return ResArr
}

CommandNames() {
    static names := [
        "间隔", "按键", "手柄", "手柄检测", "搜索", "搜索Pro", "搜索All", "搜索Combo", "组合搜索", "搜索Multi",
        "移动", "移动Pro", "鼠标移动", "鼠标移动Pro", "增量移动", "输出", "提示", "运行", "运行Pro",
        "循环", "宏操作", "变量", "变量提取", "如果", "如果Pro", "运算", "RMT指令", "后台鼠标", "后台按键",
        "文本处理", "数组", "输入", "等待", "等待确定", "时间", "倒计时", "按键检测", "窗口管理", "窗口信息",
        "调整窗口", "窗口操作", "进程管理", "注释", "抓图", "网络请求", "浏览器", "控件信息", "控件操作", "AI判断", "YOLO检测",
        "文件读写", "Excel", "图形节点", "图形开始节点", "Timing", "流程跳转"
    ]
    return names
}

CommandLanguageIndex(reset := false) {
    static index := ""
    if (reset) {
        index := ""
        return
    }
    if (IsObject(index))
        return index
    keys := Map("进程", "进程管理",
        "Window Management", "窗口管理", "Window", "窗口管理", "視窗管理", "窗口管理")
    aliases := Map()
    for name in CommandNames() {
        key := CanonicalMoveCommandName(name)
        keys[name] := key
        if (!aliases.Has(key))
            aliases[key] := Map()
        if (name != key)
            aliases[key][name] := true
    }
    for label, key in keys {
        if (label != key)
            aliases[key][label] := true
    }
    maps := [LangKeyMap]
    maps.Push(InstalledLanguageMaps()*)
    for translations in maps {
        for name in CommandNames() {
            label := Trim(translations.Get(name, ""))
            if (label == "" || label == name)
                continue
            key := CanonicalMoveCommandName(name)
            if (!keys.Has(label))
                keys[label] := key
            aliases[key][label] := true
        }
    }
    index := {Keys: keys, Aliases: aliases}
    return index
}

; 指令名称使用独立索引，避免与普通界面词条混淆。
GetCommandKey(name) {
    return CommandLanguageIndex().Keys.Get(name, CanonicalMoveCommandName(name))
}

RmtCommandCategoryKey(value) => GetConfigKey(value, ["全部", "图文", "输入控制", "宏控制", "调试", "软件自身"])

RmtCommandActionKey(value) {
    static names := ["截图", "截图提取文本", "自由贴", "启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠",
        "禁用鼠标移动", "启用鼠标加速", "禁用鼠标加速", "显示菜单", "关闭菜单", "打开界面窗口", "关闭界面窗口",
        "禁用模块", "取消禁用模块", "暂停所有宏", "恢复所有宏", "终止所有宏", "开启变量监视", "关闭变量监视",
        "开启指令显示", "关闭指令显示", "关闭软件", "休眠", "重载"]
    return GetConfigKey(value, names)
}

GetLangMacro(MacroStr, Mode) {
    result := ""
    start := 1
    while (pos := RegExMatch(MacroStr, "[^,，\r\n⫶]+", &match, start)) {
        line := match[0]
        command := Trim(line, " `t")
        if (command != "") {
            leading := StrLen(line) - StrLen(LTrim(line, " `t"))
            line := SubStr(line, 1, leading) . GetLangCmd(command, Mode)
                . SubStr(line, leading + StrLen(command) + 1)
        }
        result .= SubStr(MacroStr, start, pos - start) line
        start := pos + match.Len
    }
    return result SubStr(MacroStr, start)
}

; mode 1 多语言显示，mode 2 简中存储。
GetLangCmd(Cmd, Mode) {
    if (!RegExMatch(Cmd, "^((?:🚫|▶|⭐)*)([^_\d|]+)(\d*)", &head))
        return Cmd
    key := GetCommandKey(head[2])
    tail := SubStr(Cmd, head.Len + 1)
    if (head[3] == "" && (key == "RMT指令" || key == "按键" || key == "手柄") && SubStr(tail, 1, 1) == "_") {
        params := SplitCommand(Cmd)
        if (params.Length >= 3) {
            second := key == "RMT指令" ? RmtCommandCategoryKey(params[2]) : params[2]
            third := key == "RMT指令" ? RmtCommandActionKey(params[3]) : GetConfigKey(params[3], CmdEnumKeyActNames())
            if (Mode == 1) {
                if (key == "RMT指令")
                    second := GetLang(second)
                third := GetLang(third)
            }
            tail := "_" second "_" third SubStr(tail, StrLen(params[2]) + StrLen(params[3]) + 3)
        }
    }
    name := Mode == 1 ? Trim(GetLang(key)) : key
    return head[1] name head[3] tail
}

GetLangStr(Str, Mode) {
    return TranslateBuiltinVarReferences(Str, Mode == 1)
}
