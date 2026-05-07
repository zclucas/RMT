import { uiCopy } from "./copy";
import type { RmtState } from "./types";

export const fallbackState: RmtState = {
  version: "RMTv2.0",
  currentSettingName: uiCopy.fallback.configName,
  activeTabIndex: 1,
  isSuspend: false,
  isPause: false,
  isMacroWorking: false,
  macroRunningCount: 0,
  macroTotalCount: 0,
  settings: {
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
    modalSubGui: false,
    mutiThreadNum: "3",
    softBGColor: "f0f0f0",
    noVariableTip: true,
    cmdTip: false,
    screenShotType: 3,
    keyDownDownType: 1,
    lang: uiCopy.fallback.language,
    fontType: uiCopy.fallback.font,
    langOptions: [uiCopy.fallback.language, "English"],
    fontOptions: [uiCopy.fallback.font, "Arial", "Consolas"]
  },
  tools: {
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
  },
  tabs: [
    {
      index: 1,
      name: uiCopy.fallback.tabNames.normal,
      symbol: "Normal",
      kind: "macro",
      table: {
        index: 1,
        symbol: "Normal",
        name: uiCopy.fallback.tabNames.normal,
        isMacroTable: true,
        isMenuTable: false,
        isTimingTable: false,
        isStringTable: false,
        isReplaceTable: false,
        folds: [
          {
            index: 1,
            remark: uiCopy.fallback.sampleModule,
            frontInfo: "",
            indexSpan: "1-1",
            forbid: false,
            collapsed: false,
            triggerType: 1,
            trigger: "",
            holdTime: 500,
            items: [
              {
                index: 1,
                serial: "demo",
                colorState: 0,
                trigger: "F1",
                triggerType: 1,
                macro: "按键_a_点击_100",
                mode: 1,
                forbid: false,
                remark: uiCopy.fallback.sampleMacro,
                loopCount: "1",
                holdTime: 500,
                timingSerial: "",
                startTipSound: 1,
                endTipSound: 1,
                pause: false
              }
            ]
          }
        ]
      }
    },
    { index: 7, name: uiCopy.fallback.tabNames.tool, symbol: "Tool", kind: "tool" },
    { index: 8, name: uiCopy.fallback.tabNames.settings, symbol: "Setting", kind: "settings" },
    { index: 9, name: uiCopy.fallback.tabNames.help, symbol: "Help", kind: "help" },
    { index: 10, name: uiCopy.fallback.tabNames.reward, symbol: "Reward", kind: "reward" },
    { index: 11, name: uiCopy.fallback.tabNames.thanks, symbol: "Thank", kind: "thanks" }
  ]
};
