export const uiCopy = {
  common: {
    actionFailed: "操作失败",
    runningWithoutBridge: "Running without AHK bridge.",
    unsetHotkey: "未设置"
  },
  window: {
    minimize: "最小化",
    maximize: "最大化/还原",
    close: "关闭"
  },
  tabs: {
    ariaLabel: "RMT 功能页签",
    rewardShort: "打赏",
    thanksShort: "感谢",
    more: "更多",
    hiddenTopButtons: "隐藏的顶部按钮"
  },
  sidebar: {
    configManager: "配置管理",
    globalActions: "全局操作",
    suspend: "休眠",
    pause: "暂停",
    killMacro: "终止宏",
    reload: "重载",
    help: "RMT说明文档",
    save: "保存"
  },
  macro: {
    triggerTypeLabels: ["按下", "松开", "松止", "开关", "长按"],
    triggerType: "触发类型",
    modeLabels: ["AHK Send", "keybd_event", "罗技"],
    startTipLabels: ["无", "触发提示", "循环首次提示"],
    endTipLabels: ["无", "结束提示", "循环结束提示"],
    addModule: "新增模块",
    remark: "备注:",
    front: "前台:",
    modulePlaceholder: "模块",
    frontPlaceholder: "窗口标题 / 进程规则",
    edit: "编辑",
    editFront: "编辑前台窗口信息",
    addMacro: "新增宏",
    deleteModule: "删除模块",
    confirmDeleteModule: "确认删除当前模块以及模块中的所有宏配置？",
    disabled: "禁用",
    expandModule: "展开模块",
    collapseModule: "折叠模块",
    headers: ["宏名称", "触发编辑器", "触发类型", "循环次数", "宏设置", "宏编辑器", "操作"],
    infiniteLoop: "无限",
    emptyModule: "当前模块没有宏。",
    dragHint: "拖拽调整顺序",
    macroName: "宏名称",
    editTiming: "编辑定时配置",
    editStringTrigger: "编辑字串触发",
    editTriggerKey: "编辑触发键",
    editMacro: "编辑宏",
    copy: "复制",
    copyMacro: "复制宏",
    pasteMacro: "粘贴宏",
    delete: "删除",
    confirmDeleteMacro: "确认删除当前宏？",
    settings: "设置",
    mode: "模式",
    holdTime: "时长",
    startSound: "开始音",
    endSound: "结束音"
  },
  tool: {
    hotkeys: "工具热键",
    mouseInfoHotkey: "鼠标信息",
    recordHotkey: "指令录制",
    textFilterHotkey: "截图识别",
    screenshotHotkey: "截图",
    freePasteHotkey: "自由粘贴",
    toggle: "开关",
    relatedOptions: "相关选项",
    toolWindows: "工具窗口",
    variableMonitor: "变量监视器",
    openMonitor: "打开监视器",
    freePaste: "自由粘贴",
    recordOptions: "录制选项",
    commandDisplay: "指令显示",
    mouseInfo: "鼠标信息",
    startDetect: "开始检测",
    stopDetect: "停止检测",
    alwaysOnTop: "窗口置顶",
    infoRows: ["屏幕坐标", "窗口坐标", "窗口标题", "进程名", "窗口类", "PID", "句柄", "位置颜色"],
    textAndRecord: "文本识别与录制输出",
    ocrModel: "识别模型",
    ocrLabels: ["中文", "英文"],
    extractFromScreenshot: "截图提取文本",
    extractFromImage: "从图片提取",
    clearContent: "清空内容",
    startRecord: "开始录制",
    stopRecord: "停止录制"
  },
  settings: {
    hotkeys: "快捷键",
    suspend: "休眠",
    pause: "暂停",
    killAllMacros: "终止所有宏",
    execution: "执行参数",
    numericOptions: "数值选项",
    switchOptions: "开关选项",
    dropdownOptions: "下拉框选项",
    interfaceOptions: "界面选项",
    holdFloat: "点击时间浮动(%)",
    preIntervalFloat: "每次间隔浮动(%)",
    intervalFloat: "间隔指令浮动(%)",
    coordXFloat: "坐标X浮动(px)",
    coordYFloat: "坐标Y浮动(px)",
    multiThreadNum: "多线程数(-1~10)",
    softBGColor: "软件背景颜色",
    uiSwitches: "界面与开关",
    bootStart: "开机自启",
    cmdTip: "指令显示",
    noVariableTip: "无变量提醒",
    fixedMenuWheel: "菜单轮位置固定",
    modalSubGui: "模态子窗口",
    showSplitLine: "分割线",
    topButtonVisibility: "顶部按钮显示",
    colorPreset: "颜色方案",
    lang: "语言",
    fontType: "字体",
    screenshotType: "截图方式",
    keyDownMode: "按下时按下",
    help: "说明",
    configManager: "配置管理",
    version: "版本",
    config: "配置",
    running: "运行中",
    totalRuns: "累计执行",
    openHotkeyEditor: "打开快捷方式编辑器",
    screenshotLabels: ["微软截图", "RMT截图", "SC截图"],
    keyDownLabels: ["自动松开", "忽略重复按下", "允许重复按下"]
  },
  help: {
    title: "免责声明",
    supplement: "本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力",
    body: [
      "1. 本软件按“原样”提供，开发者不承担因使用、修改或分发导致的任何法律责任。",
      "2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。",
      "3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。",
      "4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"
    ],
    stopUse: "若不同意上述条款，请立即停止使用本软件。",
    resourceRows: [
      {
        label: "更新视频合集：",
        links: [{ label: "版本更新视频，直播交流问答", action: "openUrl" as const, url: "https://www.bilibili.com/video/BV1oWVRzaEzk" }]
      },
      {
        label: "操作说明文档：",
        links: [{ label: "快速上手，指令手册、常见问题、常见报错、更新日志等", action: "openHelp" as const }]
      },
      {
        label: "配置共享仓库：",
        links: [{ label: "案例学习、获取他人分享的宏配置（支持下载导入）", action: "openUrl" as const, url: "https://zclucas.github.io/RMT-Setting/" }]
      },
      {
        label: "国内开源网址：",
        links: [{ label: "https://gitee.com/fateman/RMT", action: "openUrl" as const, url: "https://gitee.com/fateman/RMT" }]
      },
      {
        label: "国外开源网址：",
        links: [{ label: "https://github.com/zclucas/RMT", action: "openUrl" as const, url: "https://github.com/zclucas/RMT" }]
      },
      {
        label: "软件检查更新：",
        text: "浏览开源网址，查看右侧发行版处即可知道软件最新版本"
      },
      {
        label: "软件交流渠道：",
        links: [
          { label: "QQ群（837661891）", action: "openUrl" as const, url: "https://qm.qq.com/q/DgpDumEPzq" },
          { label: "QQ频道", action: "openUrl" as const, url: "https://pd.qq.com/s/5wyjvj7zw" },
          { label: "GitHub 论坛", action: "openUrl" as const, url: "https://github.com/zclucas/RMT/discussions" },
          { label: "Discord", action: "openUrl" as const, url: "https://discord.gg/m8ewvgtzat" }
        ]
      },
      {
        label: "软件反馈表格：",
        suffix: "（仅交流群成员有编辑权限）",
        links: [
          { label: "bug文档", action: "openUrl" as const, url: "https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj" },
          { label: "需求文档", action: "openUrl" as const, url: "https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo" },
          { label: "使用备注", action: "openUrl" as const, url: "https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2" }
        ]
      },
      {
        label: "软件开源协议：",
        text: "AGPL-3.0"
      }
    ],
    links: [
      { label: "快速上手/指令手册", action: "openHelp" as const },
      { label: "版本更新视频", action: "openUrl" as const, url: "https://www.bilibili.com/video/BV1oWVRzaEzk" },
      { label: "配置共享仓库", action: "openUrl" as const, url: "https://zclucas.github.io/RMT-Setting/" },
      { label: "GitHub", action: "openUrl" as const, url: "https://github.com/zclucas/RMT" },
      { label: "Gitee", action: "openUrl" as const, url: "https://gitee.com/fateman/RMT" },
      { label: "GitHub 讨论", action: "openUrl" as const, url: "https://github.com/zclucas/RMT/discussions" },
      { label: "QQ群", action: "openUrl" as const, url: "https://qm.qq.com/q/DgpDumEPzq" },
      { label: "QQ频道", action: "openUrl" as const, url: "https://pd.qq.com/s/5wyjvj7zw" },
      { label: "Discord", action: "openUrl" as const, url: "https://discord.gg/m8ewvgtzat" },
      { label: "Bug 文档", action: "openUrl" as const, url: "https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj" },
      { label: "需求文档", action: "openUrl" as const, url: "https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo" },
      { label: "使用备注", action: "openUrl" as const, url: "https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2" }
    ]
  },
  reward: {
    title: "打赏作者",
    intro: "若梦兔（RMT）是一款完全免费的开源软件，始终陪在你身边。",
    totalPrefix: "至今已为您执行",
    totalSuffix: "次宏指令。诚邀本月打赏成为若梦兔的“守护者”，一起让若梦兔走得更远。",
    wechatAlt: "微信打赏二维码",
    wechat: "微信打赏",
    alipayAlt: "支付宝打赏二维码",
    alipay: "支付宝打赏",
    closing: "当然，如果你暂时不方便，分享给朋友也是很棒的支持。开发不易，感谢你的每一份温暖。"
  },
  thanks: {
    title: "特别感谢",
    contributors: "项目贡献者",
    openSource: "开源项目",
    community: "社区支持",
    developers: [
      ["GushuLily", "https://github.com/GushuLily"],
      ["张正波", "https://gitee.com/bogezzb"],
      ["yun", "https://github.com/yunkuangao"],
      ["boxstudy", "https://github.com/boxstudy"],
      ["sovaedv776", "https://github.com/sovaedv776"],
      ["T8numen", "https://github.com/T8numen"]
    ],
    projects: [
      ["OpenCV", "https://github.com/opencv/opencv"],
      ["ahk2_lib", "https://github.com/thqby/ahk2_lib"],
      ["RapidOCR", "https://github.com/RapidAI/RapidOCR"],
      ["AHK-CvJoyInterface", "https://github.com/evilC/AHK-CvJoyInterface"],
      ["IbInputSimulator", "https://github.com/Chaoses-Ib/IbInputSimulator"],
      ["AHK-ViGEm-Bus", "https://github.com/evilC/AHK-ViGEm-Bus"],
      ["AHK-ViGEm-Bus-v2", "https://github.com/CesarHlp1/AHK-ViGEm-Bus-v2.ahk"],
      ["ScreenCapture", "https://github.com/xland/ScreenCapture"]
    ],
    communityNames: ["AYu", "万年置伞", "别说*不下啦", "仰望", "话听", "yun"],
    body: [
      "感谢所有打赏支持若梦兔的守护者，以及参与完善 Bug 和需求文档的朋友。",
      "感谢每一位陪伴项目成长的粉丝和群友们。每一次鼓励、每一条建议，都是这个项目继续迭代的动力。"
    ]
  },
  fallback: {
    configName: "RMT默认配置",
    language: "中文",
    font: "微软雅黑",
    tabNames: {
      normal: "按键宏",
      string: "字串宏",
      menu: "菜单宏",
      timing: "定时宏",
      macro: "宏",
      replace: "按键替换",
      tool: "工具",
      settings: "设置",
      help: "帮助",
      reward: "打赏作者",
      thanks: "特别感谢"
    },
    sampleModule: "示例模块",
    sampleMacro: "示例宏"
  }
} as const;
