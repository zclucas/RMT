import type { RmtFold, RmtItem, RmtSettings, RmtState, RmtTab, RmtToolState } from "../../src/types";

const baseSettings: RmtSettings = {
  holdFloat: "0",
  preIntervalFloat: "0",
  intervalFloat: "0",
  coordXFloat: "0",
  coordYFloat: "0",
  suspendHotkey: "!p",
  pauseHotkey: "!i",
  killMacroHotkey: "!k",
  bootStart: false,
  showSplitLine: false,
  hiddenTopButtonIndexes: [],
  colorPresetId: "rmt-green",
  uiScale: 1,
  fixedMenuWheel: false,
  mutiThreadNum: "3",
  softBGColor: "f0f0f0",
  noVariableTip: true,
  cmdTip: false,
  screenShotType: 3,
  keyDownDownType: 1,
  lang: "中文",
  fontType: "微软雅黑",
  langOptions: ["中文", "English"],
  fontOptions: ["微软雅黑", "Arial", "Consolas"]
};

const baseTools: RmtToolState = {
  toolCheckHotKey: "!o",
  toolRecordMacroHotKey: "!r",
  toolTextFilterHotKey: "!u",
  screenShotHotKey: "!F1",
  freePasteHotKey: "!F2",
  isToolCheck: false,
  isToolRecord: false,
  alwaysOnTop: false,
  ocrType: 1,
  mousePos: "",
  mouseWinPos: "",
  processTitle: "",
  processName: "",
  processClass: "",
  processPid: "",
  processId: "",
  color: "",
  toolText: ""
};

function createItem(index: number, overrides: Partial<RmtItem> = {}): RmtItem {
  return {
    index,
    serial: `visual-${index}`,
    colorState: 0,
    trigger: `F${index}`,
    triggerType: 1,
    macro: `按键_${index}_点击_100`,
    mode: 1,
    forbid: false,
    remark: `宏 ${index}`,
    loopCount: "1",
    holdTime: 500,
    timingSerial: "",
    startTipSound: 1,
    endTipSound: 1,
    pause: false,
    ...overrides
  };
}

function createFold(index: number, items: RmtItem[], overrides: Partial<RmtFold> = {}): RmtFold {
  return {
    index,
    remark: `模块 ${index}`,
    frontInfo: index === 1 ? "窗口标题 / 进程规则" : "",
    indexSpan: items.length > 0 ? `${items[0].index}-${items[items.length - 1].index}` : "",
    forbid: false,
    collapsed: false,
    triggerType: 1,
    trigger: "",
    holdTime: 500,
    items,
    ...overrides
  };
}

function createMacroTab(index: number, symbol: string, name: string, folds: RmtFold[], tableFlags = {}): RmtTab {
  return {
    index,
    name,
    symbol,
    kind: "macro",
    table: {
      index,
      symbol,
      name,
      isMacroTable: index === 1,
      isMenuTable: index === 3,
      isTimingTable: index === 4,
      isStringTable: index === 2,
      isReplaceTable: index === 6,
      folds,
      ...tableFlags
    }
  };
}

function createBaseTabs(folds: RmtFold[]): RmtTab[] {
  return [
    createMacroTab(1, "Normal", "按键宏", folds),
    createMacroTab(2, "String", "字串宏", [createFold(1, [createItem(1, { trigger: "hello", remark: "文本展开" })])]),
    createMacroTab(3, "Menu", "菜单宏", []),
    createMacroTab(4, "Timing", "定时宏", [createFold(1, [createItem(1, { trigger: "08:30", remark: "早间任务" })])]),
    createMacroTab(5, "Multi", "宏", []),
    createMacroTab(6, "Replace", "按键替换", []),
    { index: 7, name: "工具", symbol: "Tool", kind: "tool" },
    { index: 8, name: "设置", symbol: "Setting", kind: "settings" },
    { index: 9, name: "帮助", symbol: "Help", kind: "help" },
    { index: 10, name: "打赏", symbol: "Reward", kind: "reward" },
    { index: 11, name: "感谢", symbol: "Thank", kind: "thanks" }
  ];
}

function createState(overrides: Partial<RmtState> = {}): RmtState {
  const folds = [createFold(1, [createItem(1, { forbid: true }), createItem(2), createItem(3, { pause: true })])];

  return {
    version: "RMTv2.0",
    currentSettingName: "RMT默认配置",
    activeTabIndex: 1,
    isSuspend: false,
    isPause: false,
    isMacroWorking: false,
    macroRunningCount: 0,
    macroTotalCount: 18,
    settings: baseSettings,
    tools: baseTools,
    tabs: createBaseTabs(folds),
    ...overrides
  };
}

const denseFolds = [
  createFold(1, [
    createItem(1, { forbid: true, remark: "禁用宏需要保持状态列布局稳定" }),
    createItem(2, { remark: "很长的宏名称不应把右侧操作列推出屏幕外" }),
    createItem(3, { pause: true, remark: "暂停宏行需要保持弱化但可读" })
  ]),
  createFold(
    2,
    [
      createItem(4, { trigger: "Ctrl+Shift+Alt+F8", loopCount: "999", remark: "较长触发键和循环次数" }),
      createItem(5, { remark: "第二模块里带有更长前台匹配上下文的宏" })
    ],
    {
      remark: "带长描述名称的禁用模块",
      frontInfo: "用于游戏客户端的很长前台窗口标题 / 进程规则",
      forbid: true
    }
  ),
  createFold(3, [createItem(6, { remark: "折叠模块占位行" })], {
    remark: "折叠模块",
    collapsed: true
  })
];

export const visualState = createState();

export const denseMacroState = createState({
  macroRunningCount: 2,
  macroTotalCount: 128,
  tabs: createBaseTabs(denseFolds)
});

export const darkMacroState = createState({
  macroRunningCount: 2,
  macroTotalCount: 128,
  settings: {
    ...baseSettings,
    colorPresetId: "night-black"
  },
  tabs: createBaseTabs(denseFolds)
});

export const toolVisualState = createState({
  activeTabIndex: 7,
  isMacroWorking: true,
  macroRunningCount: 2,
  tools: {
    ...baseTools,
    isToolCheck: true,
    isToolRecord: true,
    alwaysOnTop: true,
    ocrType: 2,
    mousePos: "1920, 1080",
    mouseWinPos: "640, 360",
    processTitle: "Very long foreground process title used to verify clipping in the tool panel",
    processName: "ExampleGameClient-Win64-Shipping.exe",
    processClass: "UnrealWindow",
    processPid: "18244",
    processId: "0x00120A",
    color: "#4f86f7",
    toolText: "OCR 第 1 行：物品栏已选中\nOCR 第 2 行：冷却剩余 00:03\n录制：Ctrl+1，等待 100 ms，左键点击"
  }
});

export const settingsVisualState = createState({
  activeTabIndex: 8,
  macroRunningCount: 4,
  macroTotalCount: 512,
  settings: {
    ...baseSettings,
    bootStart: true,
    showSplitLine: true,
    fixedMenuWheel: true,
    cmdTip: true,
    holdFloat: "120",
    preIntervalFloat: "35",
    intervalFloat: "80",
    coordXFloat: "15",
    coordYFloat: "24",
    mutiThreadNum: "8",
    colorPresetId: "day-white",
    hiddenTopButtonIndexes: [9, 10, 11]
  }
});
