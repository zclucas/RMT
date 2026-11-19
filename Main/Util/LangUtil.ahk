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
    "等待", "等待确定", "时间", "倒计时", "按键检测", "窗口管理", "窗口信息", "调整窗口", "进程管理", "注释", "抓图",
    "循环次数", "宏循环次数", "当前坐标X", "当前坐标Y", "按下", "松开", "点击", "创建", "克隆", "删除", "包含",
    "取值", "赋值", "插入", "追加", "移除", "移除最后", "长度", "变量或值", "数组", "文本分割", "文本提取", "文本替换", "去除空格",
    "时间戳处理", "自定义格式", "提取时间量", "提取所有时间量", "日期时间", "日期", "时刻",
    "大小写转换", "文本统计", "去除前空白字符", "去除后空白字符", "去除前后空白字符", "去除所有空白字符", "全部大写", "全部小写",
    "首字母大写", "字符数", "单词数", "行数", "数字提取", "字母提取", "中文提取", "内容分割", "定长分割", "当前宏",
    "插入到当前宏", "触发", "暂停", "取消暂停", "终止", "制表符", "弹窗", "状态", "选择", "选择文件", "多选", "文本文件", "继续", "继续&取消", "继续&终止&暂停",
    "用默认值", "保持原值", "自动继续", "自动终止", "自动暂停", "等待结束",
    "暂停当前宏", "暂停所有宏", "终止当前宏", "终止所有宏", "读取全部内容", "逐行读取", "指定行", "单元格", "指定列", "指定区域-行",
    "指定区域-列", "网络请求", "浏览器", "窗口控件", "AI判断", "YOLO检测", "JSON", "表单", "原始文本", "文件读写", "Excel", "读取文件", "写入文件", "读取文本文件", "写入文本文件",
    "发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板"
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
    LangKeyMap.Clear()
    LangValueMap.Clear()

    ; 内部硬编码即为简中，简中模式下无需加载外部文件，直接直通
    if (MainSoftData.Lang == "简中")
        return

    LangFilePath := Format("{}\{}.txt", LangDir, MainSoftData.Lang)
    if (!FileExist(LangFilePath)) {
        MainSoftData.Lang := "简中"
        return
    }

    try {
        file := FileOpen(LangFilePath, "r", "UTF-8")
        while !file.AtEOF {
            line := file.ReadLine()
            if (line = "")
                continue

            eqPos := RegExMatch(line, "(?<!\\)=")
            if (eqPos > 1) {
                rawKey := StrReplace(SubStr(line, 1, eqPos - 1), "\=", "=")
                val := SubStr(line, eqPos + 1)
                if (InStr(rawKey, "``n", true)) {
                    rawKey := StrReplace(rawKey, "``n", "`n", true)
                    val := StrReplace(val, "``n", "`n", true)
                }
                LangKeyMap[rawKey] := val
                trimmedKey := Trim(rawKey)
                if (trimmedKey != rawKey && !LangKeyMap.Has(trimmedKey))
                    LangKeyMap[trimmedKey] := val
                if (val != "" && !LangValueMap.Has(val))
                    LangValueMap[val] := trimmedKey
            }
        }
        file.Close()
    } catch as e {
        MsgBox GetLang("读取文件失败:") e.Message
    }

    ; 指令关键 key 优先保证反向映射准确
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
    ; 简中指令显示短名称，配置继续使用原指令键。
    if (MainSoftData.Lang == "简中") {
        switch Key {
            case "进程管理": return "进程"
            case "窗口控件": return "控件"
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
    ; 简中模式或未加载映射时直接返回原 value
    if (MainSoftData.Lang == "简中" || LangValueMap.Count == 0)
        return Value

    if (LangValueMap.Has(Value))
        return LangValueMap[Value]

    return Value
}

GetLangKeyArr(ValueArr) {
    if (MainSoftData.Lang == "简中" || LangValueMap.Count == 0)
        return ValueArr.Clone()

    ResArr := []
    for Value in ValueArr
        ResArr.Push(GetLangKey(Value))
    return ResArr
}

; 短名称只在解析指令时反查，避免影响「等待」的进程分类和普通词条。
GetCommandKey(name) {
    switch name {
        case "进程": return "进程管理"
        case "控件": return "窗口控件"
        default: return GetLangKey(name)
    }
}

GetLangMacro(MacroStr, Mode) {
    if (MacroStr == "")
        return MacroStr
    if (Mode == 1 && MainSoftData.Lang == "简中"
        && !InStr(MacroStr, "进程管理") && !InStr(MacroStr, "窗口控件"))
        return MacroStr

    cmdArr := SplitMacro(MacroStr)
    for cmdStr in cmdArr {
        cmdStr := GetLangCmd(cmdStr, Mode)
        cmdArr[A_Index] := cmdStr
    }
    return GetMacroStrByCmdArr(cmdArr)
}

; mode 1多语言模式  2简中语言模式
GetLangCmd(Cmd, Mode) {
    if (Cmd == "")
        return Cmd
    paramArr := SplitCommand(Cmd)

    action := Mode == 1 ? GetLang : GetLangKey
    cmdSymbol := GetCmdSymbol(paramArr[1])
    rawCmd := GetCmdStr(paramArr[1])

    ; 統一拆分指令名與尾部編號：
    ; - 帶編號序列指令（如 "搜尋1"）：textOnly="搜尋", numbersOnly="1"
    ; - 無編號純指令（如 "按鍵"、"間隔"）：textOnly="按鍵", numbersOnly=""
    ; 兩者皆可通用同一行邏輯轉換，省去繁瑣的分支判斷與正規表示式（RegExReplace）
    SplitSerialTextAndNumbers(rawCmd, &textOnly, &numbersOnly)
    ; 將指令名歸一化為內部簡中鍵，統一處理特定指令的內部參數翻譯
    key := GetCommandKey(textOnly)
    displayName := Mode == 1 ? GetLang(key == "进程管理" || key == "窗口控件" ? key : textOnly) : key
    if (Mode == 1 && MainSoftData.Lang == "简中") {
        if (displayName == textOnly)
            return Cmd
        return cmdSymbol . displayName . numbersOnly . SubStr(Cmd, StrLen(paramArr[1]) + 1)
    }
    paramArr[1] := cmdSymbol . displayName . numbersOnly
    if (key == "RMT指令" && paramArr.Length >= 2)
        paramArr[2] := action(paramArr[2])
    else if (key == "按键" && paramArr.Length >= 3)
        paramArr[3] := action(paramArr[3])

    ; 重組並返回處理後的完整指令字串
    return GetCmdByParams(paramArr)
}

; mode 1多语言模式  2简中语言模式
GetLangStr(Str, Mode) {
    if (Mode == 1 && MainSoftData.Lang == "简中")
        return Str

    for displayVar in GetSpecialVarArr() {
        zhKey := GetLangKey(displayVar)
        if (zhKey == displayVar)
            continue
        fromStr := Mode == 1 ? zhKey : displayVar
        toStr   := Mode == 1 ? displayVar : zhKey
        Str := StrReplace(Str, fromStr, toStr)
    }
    return Str
}
