#Requires AutoHotkey v2.0
global MainSoftData                ; 在 GlobalUtil.ahk 中由 MainConfig() 赋值
LangKeyMap := Map()

;指令相关的key
LangCmdKeyArr := ["截图", "截图提取文本", "自由贴", "开启指令显示", "关闭指令显示", "显示菜单", "关闭菜单",
    "打开界面窗口", "关闭界面窗口", "禁用模块", "取消禁用模块",
    "启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠",
    "休眠", "暂停所有宏", "恢复所有宏", "终止所有宏", "重载", "关闭软件", "间隔", "按键", "搜索", "搜索Pro", "移动", "移动Pro",
    "鼠标移动", "鼠标移动Pro", "增量移动",
    "输出", "运行", "循环", "宏操作", "变量", "变量提取", "如果", "如果Pro", "运算", "RMT指令", "后台鼠标", "后台按键",
    "等待",
    "循环次数", "宏循环次数", "当前鼠标坐标X", "当前鼠标坐标Y", "按下", "松开", "点击", "创建", "克隆", "删除", "包含",
    "取值", "赋值", "插入", "追加", "移除", "移除最后", "长度", "变量或值", "数组", "文本分割", "文本提取", "文本替换", "去除空格",
    "大小写转换", "文本统计", "去除前空白字符", "去除后空白字符", "去除前后空白字符", "去除所有空白字符", "全部大写", "全部小写",
    "首字母大写", "字符数", "单词数", "行数", "数字提取", "字母提取", "中文提取", "内容分割", "定长分割", "当前宏", "按键宏", "字串宏",
    "菜单宏", "定时宏", "宏", "插入到当前宏", "触发", "暂停", "取消暂停", "终止", "制表符", "弹窗", "状态", "文本文件", "继续", "继续&取消",
    "暂停当前宏", "暂停所有宏", "终止当前宏", "终止所有宏", "读取全部内容", "逐行读取", "指定行", "单元格", "指定行", "指定列", "指定区域-行",
    "指定区域-列", "文件读写", "发送内容", "粘贴内容", "临时提示", "指令窗口", "软件弹窗", "系统语音", "复制到剪切板", "激活窗口", "最大化窗口", 
    "最小化窗口", "还原窗口", "关闭窗口", "移动窗口", "调整大小", "置顶窗口", "取消置顶", "修改标题",
    "修改透明度", "开启鼠标穿透", "关闭鼠标穿透"]
LangValueMap := Map()   ;部分文本需要反向映射

LangInitSetting() {
    LangMap := Map("中文", 1)   ;确保存在中文
    if (DirExist(LangDir)) {
        loop files, LangDir "\*.txt" {
            SplitPath A_LoopFileName, &OutFileName, &OutDir, &OutExtension, &OutNameNoExt, &OutDrive
            LangMap[OutNameNoExt] := 1
        }
    }

    for Key, Value in LangMap {
        MainSoftData.LangArr.Push(Key)
    }

    if (MainSoftData.Lang == "无语言") {
        ChineseMap := Map("7804", 1, "0004", 1, "0804", 1, "1004", 1, "7C04", 1, "0C04", 1, "1404", 1, "0404", 1)
        if (ChineseMap.Has(A_Language))
            MainSoftData.Lang := "中文"
        else {
            MainSoftData.Lang := "English"
        }
    }
}

LangKeysInit() {
    if (MainSoftData.Lang == "中文")  ;中文就不用做处理了
        return

    LangFilePath := Format("{}\{}.txt", LangDir, MainSoftData.Lang)
    if (!FileExist(LangFilePath))
        return

    try {
        ; 以 UTF-8 编码打开文件
        file := FileOpen(LangFilePath, "r", "UTF-8")

        while !file.AtEOF {
            line := file.ReadLine()
            if (line = "")  ; 跳过空行
                continue

            LineStrArr := StrSplit(line, "=")
            if (LineStrArr.Length == 2) {
                LangKeyMap[Trim(LineStrArr[1])] := Trim(LineStrArr[2])
            }
        }

        file.Close()
    } catch as e {
        MsgBox GetLang("读取文件失败:") e.Message
    }

    for value in LangCmdKeyArr {
        key := GetLang(value)
        if (key != value)
            LangValueMap.Set(key, value)
    }
}

LangRemoveRepeat() {
    LangFilePath := Format("{}\{}.txt", LangDir, "中文")
    NewLangFilePath := Format("{}\{}.txt", LangDir, "New中文")
    file := FileOpen(LangFilePath, "r", "UTF-8")
    ResultArr := []
    KeyMap := Map()
    while !file.AtEOF {
        line := file.ReadLine()
        if (line = "")  ; 跳过空行
            continue
        key := Trim(line)
        if (!KeyMap.Has(key)) {
            KeyMap[key] := 1
            ResultArr.Push(key)
        }
    }
    file.Close()

    ; FileDelete(LangFilePath)
    for value in ResultArr {
        FileAppend(value "`n", NewLangFilePath, "UTF-8")
    }
    MsgBox("中文Key去重成功")
}

GetLang(Key) {
    ;中文或者LangKeyMap不存在时 直接返回key就行
    if (MainSoftData.Lang == "中文" || LangKeyMap.Count == 0)
        return key

    if (LangKeyMap.Has(Key))
        return LangKeyMap[Key]

    return Key
}

GetLangArr(KeyArr) {
    ResArr := []
    for Value in KeyArr {
        ResArr.Push(GetLang(Value))
    }
    return ResArr
}

GetLangKey(value) {
    ;中文或者LangKeyMap不存在时 直接返回key就行
    if (MainSoftData.Lang == "中文" || LangValueMap.Count == 0)
        return value

    if (LangValueMap.Has(value))
        return LangValueMap[value]

    return value
}

GetLangKeyArr(ValueArr) {
    ResArr := []
    for Value in ValueArr {
        ResArr.Push(GetLangKey(Value))
    }
    return ResArr
}

GetLangMacro(MacroStr, Mode) {
    cmdArr := SplitMacro(MacroStr)
    for cmdStr in cmdArr {
        cmdStr := GetLangCmd(cmdStr, Mode)
        cmdArr[A_Index] := cmdStr
    }
    return GetMacroStrByCmdArr(cmdArr)
}

;mode 1多语言模式  2中文语言模式
GetLangCmd(Cmd, Mode) {
    paramArr := SplitCommand(Cmd)
    action := Mode == 1 ? GetLang : GetLangKey
    cmdSymbol := GetCmdSymbol(paramArr[1])
    paramArr[1] := GetCmdStr(paramArr[1])

    IsMM := IsMoveCmd(paramArr[1])
    IsPressKey := paramArr[1] == "按键" || paramArr[1] == GetLang("按键")
    IsInterval := paramArr[1] == "间隔" || paramArr[1] == GetLang("间隔")
    IsRMT := paramArr[1] == "RMT指令" || paramArr[1] == GetLang("RMT指令")
    if (IsMM || IsPressKey || IsInterval || IsRMT) {
        paramArr[1] := action(paramArr[1])
    }
    else {
        textOnly := RegExReplace(paramArr[1], "\d+")
        numbersOnly := RegExReplace(paramArr[1], "\D+")
        paramArr[1] := Format("{}{}", action(textOnly), numbersOnly)
    }
    paramArr[1] := Format("{}{}", cmdSymbol, paramArr[1])

    if (IsRMT) {
        paramArr[2] := action(paramArr[2])
    }

    if (IsPressKey && paramArr.Length >= 3) {
        paramArr[3] := action(paramArr[3])
    }
    return GetCmdByParams(paramArr)
}

;mode 1多语言模式  2中文语言模式
GetLangStr(Str, Mode) {
    SpecialKeyArr1 := GetLangKeyArr(GetSystemVarArr())
    SpecialKeyArr2 := GetSystemVarArr()
    KeyArr := Mode == 1 ? SpecialKeyArr1 : SpecialKeyArr2
    action := Mode == 1 ? GetLang : GetLangKey

    for index, value in KeyArr {
        Str := StrReplace(Str, value, action(value))
    }
    return Str
}
