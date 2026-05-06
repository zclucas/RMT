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
  hiddenTopButtonIndexes: number[];
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

export type RmtAction =
  | { type: "getState" }
  | { type: "setTab"; payload: { tabIndex: number } }
  | { type: "toggleSuspend" }
  | { type: "togglePause" }
  | { type: "killAll" }
  | { type: "save" }
  | { type: "reload" }
  | { type: "openHelp" }
  | { type: "openUrl"; payload: { url: string } }
  | { type: "openVarMonitor" }
  | { type: "openSettingManager" }
  | { type: "openToolRecordSetting" }
  | { type: "editCmdTip" }
  | { type: "openFreePaste" }
  | { type: "toggleToolCheck" }
  | { type: "toggleToolRecord" }
  | { type: "toolTextFilterScreenShot" }
  | { type: "toolTextFilterSelectImage" }
  | { type: "clearToolText" }
  | { type: "copyDiagnostics" }
  | { type: "openHotkeyEditor"; payload: { target: keyof RmtSettings | keyof RmtToolState } }
  | { type: "keyDownHelp" }
  | { type: "minimize" }
  | { type: "maximize" }
  | { type: "close" }
  | { type: "updateSetting"; payload: { field: keyof RmtSettings; value: unknown } }
  | { type: "updateTool"; payload: { field: keyof RmtToolState; value: unknown } }
  | { type: "updateItem"; payload: { tableIndex: number; itemIndex: number; field: keyof RmtItem; value: unknown } }
  | { type: "updateFold"; payload: { tableIndex: number; foldIndex: number; field: keyof RmtFold; value: unknown } }
  | { type: "toggleFold"; payload: { tableIndex: number; foldIndex: number } }
  | { type: "addItem"; payload: { tableIndex: number; foldIndex: number } }
  | { type: "deleteItem"; payload: { tableIndex: number; itemIndex: number } }
  | { type: "moveItem"; payload: { tableIndex: number; itemIndex: number; direction: -1 | 1 } }
  | { type: "addFold"; payload: { tableIndex: number; afterFoldIndex: number } }
  | { type: "deleteFold"; payload: { tableIndex: number; foldIndex: number } }
  | { type: "openTriggerEditor"; payload: { tableIndex: number; itemIndex?: number; foldIndex?: number } }
  | { type: "openMacroEditor"; payload: { tableIndex: number; itemIndex: number } };

export type RmtActionType = RmtAction["type"];

export type RmtActionPayload<T extends RmtActionType> = Extract<RmtAction, { type: T }> extends {
  payload: infer Payload;
}
  ? Payload
  : never;
