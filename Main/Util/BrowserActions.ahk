#Requires AutoHotkey v2.0

class BrowserActions {
    ; 保留历史数字配置的索引；新动作在 Groups 中注册即可。
    static _legacyNames := [
        "打开网址", "新建分页", "切换分页", "关闭分页", "获取分页列表",
        "等待元素", "等待文字", "等待加载",
        "点击", "双击", "右键", "输入", "清空", "选择下拉", "勾选", "滚动至元素", "悬停", "元素数量", "元素状态",
        "鼠标移动", "鼠标点击", "鼠标滚轮", "按键输入",
        "Cookie操作", "Storage操作",
        "执行JS", "提取文本", "提取属性", "提取HTML", "获取网址", "获取标题", "网页截图",
        "刷新", "后退", "前进", "关闭标签", "关闭浏览器", "当前页跳转", "提取控件值", "关闭", "获取当前分页ID"
    ]
    static Names {
        get {
            static names := 0
            if (!names) {
                names := this._legacyNames.Clone()
                seen := Map()
                for action in names
                    seen[action] := true
                for group in this.Groups {
                    for action in group.actions {
                        if (!seen.Has(action)) {
                            names.Push(action)
                            seen[action] := true
                        }
                    }
                }
            }
            return names
        }
    }

    static CloseBrowserTypes := ["Chrome", "Edge", "所有浏览器", "自定义"]
    static CloseScopes := ["所有标签页", "非当前标签页", "当前标签页"]
    static OpenModes := ["默认", "新窗口", "无痕模式"]
    static BrowserTypes := ["默认浏览器", "Chrome", "Edge", "Brave", "Vivaldi", "Opera", "Chromium", "自定义路径"]
    static CurrentTabActions := ["刷新", "后退", "前进", "关闭"]
    static TabMatchModes := ["自动匹配", "标签页ID", "序号", "网址", "标题", "正则表达式-网址", "正则表达式-标题"]
    ; 仅供历史指令继续执行和编辑，不再作为新增操作提供。
    static LegacyTabActions := ["当前页跳转", "新建标签页", "获取当前标签页ID", "关闭浏览器", "关闭", "刷新", "后退", "前进"]

    static Normalize(action) {
        switch action {
            case "页签信息": return "标签页信息"
            case "切换分页": return "切换标签页"
            case "关闭分页", "关闭标签": return "关闭标签页"
            case "新建分页": return "新建标签页"
            case "获取分页列表": return "获取标签页列表"
            case "获取当前分页ID": return "获取当前标签页ID"
        }
        return action
    }

    static Action(value) => this.Normalize(CmdEnumZh(this.Normalize(GetLangKey(value)), this.Names))

    static BrowserType(value) => GetLangKey(value) == "系统默认浏览器" ? "默认浏览器" : GetLangKey(value)

    static GetOpenMode(data) {
        if (data.HasOwnProp("OpenMode"))
            return CmdEnumZh(data.OpenMode, this.OpenModes)
        return data.HasOwnProp("Incognito") && data.Incognito ? "无痕模式" : "默认"
    }

    static IsCloseAction(action) => action == "关闭" || action == "关闭浏览器"

    static RequiresCDP(action, pageField := "网址") {
        return action != "打开网址" && action != "关闭" && action != "当前标签页"
            && (this.Normalize(action) != "标签页信息" || pageField == "标签页ID" || pageField == "页签ID" || pageField == "加载状态")
    }

    static IsTabAction(action) {
        action := this.Normalize(action)
        if (action == "刷新" || action == "后退" || action == "前进")
            return true
        for name in this.LegacyTabActions
            if (name == action)
                return true
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
            "打开网址", true, "当前页跳转", true, "等待元素", true, "等待文字", true, "等待加载", true,
            "点击", true, "双击", true, "右键", true, "输入", true, "清空", true, "选择下拉", true,
            "勾选", true, "滚动至元素", true, "悬停", true, "执行JS", true,
            "提取文本", true, "提取控件值", true, "提取属性", true, "提取HTML", true)
        return actions.Has(action)
    }

    static GetCloseBrowserType(value) {
        name := GetLangKey(value)
        return name == "自定义路径" ? "自定义" : name
    }

    ; 分组结构定义
    static Groups := [
        {
            name: "网页",
            actions: ["打开网址", "标签页信息", "当前标签页", "切换标签页", "关闭标签页"]
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
            actions: ["提取文本", "提取控件值", "提取属性", "提取HTML", "元素数量", "元素状态", "获取网址", "获取标题", "获取标签页列表"]
        },
        {
            name: "页面工具",
            actions: ["网页截图", "执行JS", "Cookie操作", "Storage操作"]
        }
    ]

    static UsesSelector(action) {
        static actions := Map("等待元素", true, "等待文字", true, "点击", true, "双击", true, "右键", true,
            "输入", true, "清空", true, "选择下拉", true, "勾选", true, "滚动至元素", true, "悬停", true,
            "元素数量", true, "元素状态", true, "提取文本", true, "提取控件值", true, "提取属性", true, "提取HTML", true)
        return actions.Has(action)
    }

    static UsesTarget(action) {
        return this.UsesSelector(action) || action == "执行JS" || action == "网页截图"
            || action == "获取网址" || action == "获取标题" || action == "当前页跳转"
            || action == "刷新" || action == "后退" || action == "前进" || action == "等待加载"
            || action == "鼠标移动" || action == "鼠标点击" || action == "鼠标滚轮"
            || action == "按键输入" || action == "Storage操作" || action == "Cookie操作"
    }
}
