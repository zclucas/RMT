#Requires AutoHotkey v2.0

; 固定的历史配置编号，不是界面 SelectedIndex；既有编号不能重排，新值只能追加。
; 这里只负责数字/译名到语义键的兼容转换，显示顺序由界面列表维护。
; 业务代码比较 Key() 返回的名称；界面按当前选项文本调用 Code()，调整显示顺序不改变配置含义。
class RuntimeChoice {
    static Definitions := Map(
        "LegacyTextProcessType", {legacyBase: 1, fallback: "", names: ["文本分割", "文本替换", "数字提取", "字母提取", "中文提取", "去空格处理", "大小写转换", "URL编解码", "Base64编解码", "文本统计", "固定长度分割", "多字符分割", "行过滤", "去重处理", "排序处理", "随机文本", "日期时间"]},
        "LegacyTextResultAction", {legacyBase: 1, fallback: "", names: ["覆盖变量", "追加结果", "前置结果"]},
        "LegacyWhitespace", {legacyBase: 1, fallback: "", names: ["去除前后空格", "去除所有空格", "去除多余空格"]},
        "LegacyCaseConversion", {legacyBase: 1, fallback: "", names: ["全部大写", "全部小写", "首字母大写"]},
        "LegacyUrlCodec", {legacyBase: 1, fallback: "", names: ["URL编码", "URL解码"]},
        "LegacyBase64Codec", {legacyBase: 1, fallback: "", names: ["Base64编码", "Base64解码"]},
        "LegacyTextStatistics", {legacyBase: 1, fallback: "", names: ["字符数", "单词数", "行数", "中文字符数"]},
        "AiAccessMode", {legacyBase: 1, fallback: "工作区", names: ["只读", "工作区", "完全访问"]},
        "AiApprovalMode", {legacyBase: 1, fallback: "自动审批", names: ["手动审批", "自动审批", "完全访问"]},
        "ScreenShotType", {legacyBase: 1, fallback: "SC截图", names: ["微软截图", "RMT截图", "SC截图"]},
        "SearchImageType", {legacyBase: 1, fallback: "OpenCV", names: ["OpenCV", "RMT搜图"]},
        "OCRTypeValue", {legacyBase: 1, fallback: "RapidOCR", names: ["RapidOCR", "Tesseract OCR"]},
        "ExcelBackend", {legacyBase: 1, fallback: "C# DLL", names: ["C# DLL", "AHK（兼容）"]},
        "MacroStopType", {legacyBase: 1, fallback: "智能终止", names: ["智能终止", "强制终止"]},
        "KeyDownDownType", {legacyBase: 1, fallback: "自动松开", names: ["自动松开", "忽略重复按下", "允许重复按下"]},
        "RemarkAutoType", {legacyBase: 1, fallback: "自动生成", names: ["不生成", "自动生成", "覆盖生成"]},
        "PreferredMacroEditor", {legacyBase: 1, fallback: "逻辑树", names: ["逻辑树", "图形节点"]},
        "RecordMouseTrail", {legacyBase: 0, fallback: "关键点位", names: ["不录制", "关键点位", "关键点相对位移", "全量"]},
        "MenuWheelSelectMode", {legacyBase: 1, fallback: "划线选择", names: ["点击选择", "划线选择"]},
        "CountDownStyle", {legacyBase: 1, fallback: "智能", names: ["时分秒", "智能", "秒"]},
        "CMDLogAutoClear", {legacyBase: 0, fallback: "从不", names: ["从不", "每天", "每周"]},
        "KeyMode", {legacyBase: 1, fallback: "AHK Send", names: ["AHK Send", "keybd_event", "罗技", "AHI", "VIIPER"]},
        "TriggerType", {legacyBase: 1, fallback: "按下", names: ["按下", "松开", "松止", "开关", "长按", "双击"]},
        "StartTipSound", {legacyBase: 1, fallback: "无", names: ["无", "触发提示", "循环首次提示"]},
        "EndTipSound", {legacyBase: 1, fallback: "无", names: ["无", "结束提示", "循环结束提示"]},
        "StopTipSound", {legacyBase: 1, fallback: "无", names: ["无", "终止提示"]})

    static Controls := Map("AiAccessCon", "AiAccessMode", "AiApprovalCon", "AiApprovalMode", "CmbScreenShot", "ScreenShotType", "CmbSearchImage", "SearchImageType",
        "CmbOCRType", "OCRTypeValue", "CmbExcelBackend", "ExcelBackend", "CmbMacroStop", "MacroStopType",
        "CmbKeyDownDown", "KeyDownDownType", "CmbRemarkAuto", "RemarkAutoType", "CmbPreferredEditor", "PreferredMacroEditor",
        "MouseTrailModeCon", "RecordMouseTrail", "WheelSelectModeCon", "MenuWheelSelectMode",
        "CountDownStyleCon", "CountDownStyle", "CmdTipAutoClearCon", "CMDLogAutoClear")

    static Key(kind, value) {
        definition := this.Definitions[kind]
        if (IsInteger(value)) {
            index := Integer(value) - definition.legacyBase + 1
            return index >= 1 && index <= definition.names.Length ? definition.names[index] : definition.fallback
        }
        for name in definition.names
            if (name == value)
                return name
        key := GetConfigKey(String(value), definition.names)
        for name in definition.names
            if (name == key)
                return name
        return definition.fallback
    }

    ; 仅供保留旧数字配置/控件适配层使用，业务分支不依赖这些编号。
    static Code(kind, value) {
        key := this.Key(kind, value)
        definition := this.Definitions[kind]
        for index, name in definition.names
            if (name == key)
                return index - 1 + definition.legacyBase
    }
}
