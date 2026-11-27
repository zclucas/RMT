#Requires AutoHotkey v2.0

class BrowserActions {
    static Names {
        get {
            static names := 0
            if (!names) {
                names := []
                for group in this.Groups
                    for action in group.actions
                        names.Push(action)
            }
            return names
        }
    }

    static OpenModes := ["默认", "新窗口", "无痕模式"]
    static BrowserTypes := ["默认浏览器", "Chrome", "Edge", "Brave", "Vivaldi", "Opera", "Chromium", "自定义路径"]
    static CurrentTabActions := ["刷新", "后退", "前进", "关闭", "清空缓存"]
    static TabMatchModes := ["标签页ID", "网址", "标题", "正则表达式-网址", "正则表达式-标题", "元素匹配"]
    static CloseTabMatchModes := ["当前标签页", "标签页ID", "网址", "标题", "正则表达式-网址", "正则表达式-标题", "元素匹配"]
    static TabCloseModes := ["匹配标签页", "非匹配标签页"]
    static TabCloseMode(value) => this._Choice(value, this.TabCloseModes, "关闭方式")
    static MatchModes(action) => action == "关闭标签页" ? this.CloseTabMatchModes : this.TabMatchModes
    static MatchMode(value, action := "关闭标签页") => this._Choice(value, this.MatchModes(action), "标签页匹配方式")
    static Action(value) => this._Choice(value, this.Names, "浏览器操作")
    static BrowserType(value) => this._Choice(value, this.BrowserTypes, "浏览器类型")
    static GetOpenMode(data) => this._Choice(data.OpenMode, this.OpenModes, "打开方式")

    static _Choice(value, choices, label := "浏览器选项") {
        value := GetConfigKey(value, choices)
        for choice in choices
            if (Type(value) == "String" && value == choice)
                return choice
        throw ValueError(GetLang("不支持的") GetLang(label) "：" value)
    }

    static ChoiceIndex(value, choices) {
        value := this._Choice(value, choices)
        for index, choice in choices
            if (value == choice)
                return index - 1
    }

    static ClosesCurrentTabOnly(matchMode, closeMode := "匹配标签页") {
        return GetLangKey(matchMode) == "当前标签页" && GetLangKey(closeMode) == "匹配标签页"
    }

    static RequiresCDP(action, pageField := "网址", matchMode := "", closeMode := "匹配标签页") {
        action := this.Action(action)
        if (matchMode == "元素匹配")
            return true
        if (action == "关闭标签页" && this.ClosesCurrentTabOnly(matchMode, closeMode))
            return false
        return (action == "当前标签页" && pageField == "清空缓存") || (action != "打开网址" && action != "当前标签页"
            && (this.Action(action) != "标签页信息" || pageField == "标签页ID" || pageField == "加载状态"))
    }

    static IsTabAction(action) {
        action := this.Action(action)
        for group in this.Groups {
            if (group.name != "网页")
                continue
            for name in group.actions
                if (name == action)
                    return true
        }
        return false
    }

    static UsesTimeout(action) {
        static actions := Map(
            "打开网址", true, "等待元素", true, "等待文字", true, "等待加载", true,
            "点击", true, "双击", true, "右键", true, "输入", true, "清空", true, "选择下拉", true,
            "勾选", true, "滚动至元素", true, "悬停", true, "执行JS", true,
            "元素位置/宽高", true)
        return actions.Has(action)
    }

    ; 分组结构定义
    static Groups := [
        {
            name: "网页",
            actions: ["打开网址", "标签页信息", "当前标签页", "切换标签页", "关闭标签页"]
        },
        {
            name: "元素信息",
            actions: ["元素信息", "元素位置/宽高"]
        },
        {
            name: "等待条件",
            actions: ["等待元素", "等待文字", "等待加载"]
        },
        {
            name: "元素互动",
            actions: ["点击", "双击", "右键", "输入", "清空", "选择下拉", "勾选", "滚动至元素", "悬停"]
        },
        {
            name: "键鼠模拟",
            actions: ["鼠标移动", "鼠标点击", "鼠标滚轮", "按键输入"]
        },
        {
            name: "数据提取",
            actions: ["元素数量", "元素状态", "获取网址", "获取标题", "获取标签页列表"]
        },
        {
            name: "页面工具",
            actions: ["网页截图", "执行JS", "Cookie操作", "Storage操作"]
        }
    ]

    static UsesSelector(action) {
        static actions := Map("等待元素", true, "等待文字", true, "点击", true, "双击", true, "右键", true,
            "输入", true, "清空", true, "选择下拉", true, "勾选", true, "滚动至元素", true, "悬停", true,
            "元素数量", true, "元素状态", true,
            "元素信息", true, "元素位置/宽高", true)
        return actions.Has(action)
    }

    static UsesTarget(action) {
        return (this.UsesSelector(action) && !BrowserElementInfo.IsRead(action)) || action == "执行JS" || action == "网页截图"
            || action == "获取网址" || action == "获取标题"
            || action == "等待加载"
            || action == "鼠标移动" || action == "鼠标点击" || action == "鼠标滚轮"
            || action == "按键输入" || action == "Storage操作" || action == "Cookie操作"
    }
}
