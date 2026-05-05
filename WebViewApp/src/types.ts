export type TabKind = "macro" | "tool" | "settings" | "help" | "reward" | "thanks";

export interface RmtItem {
  index: number;
  serial: string;
  colorState: number;
  trigger: string;
  triggerType: number;
  macro: string;
  mode: number;
  forbid: boolean;
  remark: string;
  loopCount: string;
  holdTime: number;
  timingSerial: string;
  startTipSound: number;
  endTipSound: number;
  pause: boolean;
}

export interface RmtFold {
  index: number;
  remark: string;
  frontInfo: string;
  indexSpan: string;
  forbid: boolean;
  collapsed: boolean;
  triggerType: number;
  trigger: string;
  holdTime: number;
  items: RmtItem[];
}

export interface RmtTable {
  index: number;
  symbol: string;
  name: string;
  isMacroTable: boolean;
  isMenuTable: boolean;
  isTimingTable: boolean;
  isStringTable: boolean;
  isReplaceTable: boolean;
  folds: RmtFold[];
}

export interface RmtTab {
  index: number;
  name: string;
  symbol: string;
  kind: TabKind;
  table?: RmtTable;
}

export interface RmtSettings {
  holdFloat: string;
  preIntervalFloat: string;
  intervalFloat: string;
  coordXFloat: string;
  coordYFloat: string;
  suspendHotkey: string;
  pauseHotkey: string;
  killMacroHotkey: string;
  bootStart: boolean;
  showSplitLine: boolean;
  fixedMenuWheel: boolean;
  mutiThreadNum: string;
  softBGColor: string;
  noVariableTip: boolean;
  cmdTip: boolean;
  screenShotType: number;
  keyDownDownType: number;
  lang: string;
  fontType: string;
  langOptions: string[];
  fontOptions: string[];
}

export interface RmtToolState {
  toolCheckHotKey: string;
  toolRecordMacroHotKey: string;
  toolTextFilterHotKey: string;
  screenShotHotKey: string;
  freePasteHotKey: string;
  isToolCheck: boolean;
  isToolRecord: boolean;
  alwaysOnTop: boolean;
  ocrType: number;
  mousePos: string;
  mouseWinPos: string;
  processTitle: string;
  processName: string;
  processClass: string;
  processPid: string;
  processId: string;
  color: string;
  toolText: string;
}

export interface RmtState {
  version: string;
  currentSettingName: string;
  activeTabIndex: number;
  isSuspend: boolean;
  isPause: boolean;
  isMacroWorking: boolean;
  macroRunningCount: number;
  macroTotalCount: number;
  tabs: RmtTab[];
  settings: RmtSettings;
  tools: RmtToolState;
}

export interface RmtResult {
  ok: boolean;
  message: string;
  state: RmtState;
}

export interface RmtAction {
  type: string;
  payload?: unknown;
}
