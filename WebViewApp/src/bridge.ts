import type { RmtAction, RmtResult, RmtState } from "./types";

declare global {
  interface Window {
    ahk?: {
      RmtAction?: (json: string) => Promise<string> | string;
      gui?: {
        Minimize?: () => void;
        Maximize?: () => void;
        Restore?: () => void;
      };
      global?: {
        WinClose?: (target: string) => void;
      };
    };
    __rmtReceiveState?: (state: RmtState) => void;
  }
}

const fallbackState: RmtState = {
  version: "RMTv2.0.0",
  currentSettingName: "RMT默认配置",
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
      name: "按键宏",
      symbol: "Normal",
      kind: "macro",
      table: {
        index: 1,
        symbol: "Normal",
        name: "按键宏",
        isMacroTable: true,
        isMenuTable: false,
        isTimingTable: false,
        isStringTable: false,
        isReplaceTable: false,
        folds: [
          {
            index: 1,
            remark: "示例模块",
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
                remark: "示例宏",
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
    { index: 7, name: "工具", symbol: "Tool", kind: "tool" },
    { index: 8, name: "设置", symbol: "Setting", kind: "settings" },
    { index: 9, name: "帮助", symbol: "Help", kind: "help" },
    { index: 10, name: "打赏作者", symbol: "Reward", kind: "reward" },
    { index: 11, name: "特别感谢", symbol: "Thank", kind: "thanks" }
  ]
};

export async function callRmt(action: RmtAction): Promise<RmtResult> {
  if (!window.ahk?.RmtAction) {
    return {
      ok: true,
      message: "Running without AHK bridge.",
      state: fallbackState
    };
  }

  const raw = await window.ahk.RmtAction(JSON.stringify(action));
  return JSON.parse(String(raw)) as RmtResult;
}

export function getFallbackState(): RmtState {
  return fallbackState;
}
