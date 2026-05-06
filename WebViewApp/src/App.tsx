import {
  ArrowDown,
  ArrowUp,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  ExternalLink,
  FileText,
  Gift,
  GripVertical,
  HelpCircle,
  Keyboard,
  ListTree,
  Maximize2,
  Menu as MenuIcon,
  Minus,
  Pause,
  Plus,
  RefreshCw,
  Repeat2,
  Save,
  Settings,
  SlidersHorizontal,
  Square,
  SquarePen,
  Timer,
  Trash2,
  Wrench,
  X
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { callRmt, getFallbackState } from "./bridge";
import { uiCopy } from "./copy";
import type {
  RmtAction,
  RmtActionPayload,
  RmtActionType,
  RmtFold,
  RmtItem,
  RmtSettings,
  RmtState,
  RmtTab,
  RmtToolState
} from "./types";

type ActionArgs<T extends RmtActionType> = [RmtActionPayload<T>] extends [never]
  ? [payload?: never]
  : [payload: RmtActionPayload<T>];
type RunAction = <T extends RmtActionType>(type: T, ...args: ActionArgs<T>) => void | Promise<void>;
type RmtThemeMode = "light" | "dark";
type RmtColorPreset = {
  id: string;
  name: string;
  primaryColor: string;
  secondaryColor: string;
  accentColor: string;
  accentHoverColor: string;
  primaryHoverColor: string;
  primaryTextColor: string;
  titleTextColor: string;
  mode: RmtThemeMode;
};

const uiDesignWidth = 1360;
const uiDesignHeight = 720;
const minUiScale = 0.65;
const colorPresets: RmtColorPreset[] = [
  {
    id: "rmt-green",
    name: "若梦绿",
    primaryColor: "#178a56",
    secondaryColor: "#dff5e8",
    accentColor: "#178a56",
    accentHoverColor: "#116b43",
    primaryHoverColor: "#116b43",
    primaryTextColor: "#ffffff",
    titleTextColor: "#0b2819",
    mode: "light"
  },
  {
    id: "day-white",
    name: "日间白",
    primaryColor: "#f8fafc",
    secondaryColor: "#ffffff",
    accentColor: "#475569",
    accentHoverColor: "#334155",
    primaryHoverColor: "#eef2f6",
    primaryTextColor: "#ffffff",
    titleTextColor: "#17202a",
    mode: "light"
  },
  {
    id: "night-black",
    name: "夜间黑",
    primaryColor: "#111418",
    secondaryColor: "#2a3036",
    accentColor: "#d1d5db",
    accentHoverColor: "#f3f4f6",
    primaryHoverColor: "#1c2228",
    primaryTextColor: "#111418",
    titleTextColor: "#f8fafc",
    mode: "dark"
  },
  {
    id: "sea-blue",
    name: "海蓝",
    primaryColor: "#1f6fb2",
    secondaryColor: "#dceeff",
    accentColor: "#1f6fb2",
    accentHoverColor: "#17578d",
    primaryHoverColor: "#17578d",
    primaryTextColor: "#ffffff",
    titleTextColor: "#10283d",
    mode: "light"
  },
  {
    id: "warm-amber",
    name: "暖琥珀",
    primaryColor: "#9a6a00",
    secondaryColor: "#fff2cc",
    accentColor: "#9a6a00",
    accentHoverColor: "#765100",
    primaryHoverColor: "#765100",
    primaryTextColor: "#ffffff",
    titleTextColor: "#362605",
    mode: "light"
  },
  {
    id: "soft-rose",
    name: "柔玫",
    primaryColor: "#a04655",
    secondaryColor: "#fde5ea",
    accentColor: "#a04655",
    accentHoverColor: "#7f3643",
    primaryHoverColor: "#7f3643",
    primaryTextColor: "#ffffff",
    titleTextColor: "#3b131a",
    mode: "light"
  }
];
const defaultColorPreset = colorPresets[0];

function cloneState(state: RmtState): RmtState {
  return structuredClone(state);
}

function classNames(...values: Array<string | false | null | undefined>): string {
  return values.filter(Boolean).join(" ");
}

function getColorPreset(presetId?: string): RmtColorPreset {
  return colorPresets.find((preset) => preset.id === presetId) ?? defaultColorPreset;
}

function getThemeStyle(preset: RmtColorPreset, uiScale: number): React.CSSProperties {
  const darkMode = preset.mode === "dark";
  return {
    "--rmt-ui-scale": String(uiScale),
    "--rmt-primary": preset.accentColor,
    "--rmt-primary-hover": preset.accentHoverColor,
    "--rmt-primary-text": preset.primaryTextColor,
    "--rmt-primary-soft": preset.secondaryColor,
    "--rmt-title-bg": preset.secondaryColor,
    "--rmt-title-text": preset.titleTextColor,
    "--rmt-title-bottom": preset.accentColor,
    "--rmt-app-mark-bg": preset.accentColor,
    "--rmt-app-mark-text": preset.primaryTextColor,
    "--rmt-bg": darkMode ? "#121417" : "#f5f5f5",
    "--rmt-surface": darkMode ? "#1d2228" : "#ffffff",
    "--rmt-surface-muted": darkMode ? "#252b32" : "#f8fafb",
    "--rmt-border": darkMode ? "#343c45" : "#d8dfe6",
    "--rmt-border-strong": darkMode ? "#46505b" : "#cfd7df",
    "--rmt-text": darkMode ? "#eef3f8" : "#17202a",
    "--rmt-muted": darkMode ? "#a7b1bd" : "#566674",
    "--rmt-button-bg": darkMode ? "#252b32" : "#ffffff",
    "--rmt-button-hover": darkMode ? "#303740" : "#f1f5f8",
    "--rmt-danger": darkMode ? "#f87171" : "#f3423a",
    "--rmt-info": darkMode ? "#5db4f4" : "#2698e6",
    "--rmt-neutral-action": darkMode ? "#5b6570" : "#777777"
  } as React.CSSProperties;
}

export default function App() {
  const [state, setState] = useState<RmtState>(() => getFallbackState());
  const [message, setMessage] = useState("");
  const scaleHostRef = useRef<HTMLDivElement>(null);
  const [uiScale, setUiScale] = useState(1);
  const activeTab = useMemo(
    () => state.tabs.find((tab) => tab.index === state.activeTabIndex) ?? state.tabs[0],
    [state.activeTabIndex, state.tabs]
  );

  useEffect(() => {
    window.__rmtReceiveState = (nextState) => setState(nextState);
    runAction("getState");

    return () => {
      delete window.__rmtReceiveState;
    };
  }, []);

  useEffect(() => {
    const host = scaleHostRef.current;
    if (!host) {
      return;
    }

    const updateScale = () => {
      const { width, height } = host.getBoundingClientRect();
      if (width <= 0 || height <= 0) {
        return;
      }
      const nextScale = Math.max(Math.min(width / uiDesignWidth, height / uiDesignHeight, 1), minUiScale);
      const roundedScale = Number(nextScale.toFixed(3));
      setUiScale((current) => (Math.abs(current - roundedScale) > 0.005 ? roundedScale : current));
    };

    updateScale();
    window.addEventListener("resize", updateScale);
    if (typeof ResizeObserver === "undefined") {
      return () => {
        window.removeEventListener("resize", updateScale);
      };
    }

    const observer = new ResizeObserver(updateScale);
    observer.observe(host);

    return () => {
      observer.disconnect();
      window.removeEventListener("resize", updateScale);
    };
  }, []);

  async function runAction<T extends RmtActionType>(type: T, ...args: ActionArgs<T>) {
    try {
      const payload = args[0];
      const action = (payload === undefined ? { type } : { type, payload }) as RmtAction;
      const result = await callRmt(action);
      setState(result.state);
      setMessage(result.message || (result.ok ? "" : uiCopy.common.actionFailed));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  }

  function patchLocalItem(tableIndex: number, itemIndex: number, field: keyof RmtItem, value: unknown) {
    setState((current) => {
      const next = cloneState(current);
      const item = findItem(next, tableIndex, itemIndex);
      if (item) {
        (item[field] as unknown) = value;
      }
      return next;
    });
  }

  function patchLocalFold(tableIndex: number, foldIndex: number, field: keyof RmtFold, value: unknown) {
    setState((current) => {
      const next = cloneState(current);
      const fold = findFold(next, tableIndex, foldIndex);
      if (fold) {
        (fold[field] as unknown) = value;
      }
      return next;
    });
  }

  function patchLocalSettings(field: keyof RmtSettings, value: unknown) {
    setState((current) => ({ ...current, settings: { ...current.settings, [field]: value } }));
  }

  function patchLocalTools(field: keyof RmtToolState, value: unknown) {
    setState((current) => ({ ...current, tools: { ...current.tools, [field]: value } }));
  }

  function updateItem(tableIndex: number, itemIndex: number, field: keyof RmtItem, value: unknown) {
    void runAction("updateItem", { tableIndex, itemIndex, field, value });
  }

  function updateFold(tableIndex: number, foldIndex: number, field: keyof RmtFold, value: unknown) {
    void runAction("updateFold", { tableIndex, foldIndex, field, value });
  }

  function updateSetting(field: keyof RmtSettings, value: unknown) {
    void runAction("updateSetting", { field, value });
  }

  function updateTool(field: keyof RmtToolState, value: unknown) {
    void runAction("updateTool", { field, value });
  }

  const colorPreset = useMemo(() => getColorPreset(state.settings.colorPresetId), [state.settings.colorPresetId]);
  const scaleStyle = getThemeStyle(colorPreset, uiScale);

  return (
    <div className="rmt-scale-viewport" ref={scaleHostRef}>
      <div className="rmt-scale-content" style={scaleStyle}>
        <div className="app-shell classic-app" data-theme-mode={colorPreset.mode}>
          <TitleBar state={state} runAction={runAction} />

          <div className="classic-body">
            <GlobalSidebar state={state} runAction={runAction} />

            <section className="classic-main">
              <TopTabs
                state={state}
                hiddenTopButtonIndexes={state.settings.hiddenTopButtonIndexes}
                runAction={runAction}
              />

              {message && <div className="message classic-message">{message}</div>}

              {activeTab?.kind === "macro" && activeTab.table && (
                <div className="classic-work-area module-list-layout">
                  <MacroTable
                    tab={activeTab}
                    patchLocalItem={patchLocalItem}
                    patchLocalFold={patchLocalFold}
                    updateItem={updateItem}
                    updateFold={updateFold}
                    runAction={runAction}
                  />
                </div>
              )}

              {activeTab && activeTab.kind !== "macro" && (
                <main className="content classic-content">
                  {activeTab.kind !== "tool" && activeTab.kind !== "settings" && (
                    <div className="content-header">
                      <div>
                        <div className="eyebrow">{activeTab.symbol}</div>
                        <h1>{activeTab.name}</h1>
                      </div>
                      <div className="runtime-summary">
                        <span className={classNames("dot", state.isMacroWorking && "running")} />
                        <span>{uiCopy.settings.running} {state.macroRunningCount}</span>
                      </div>
                    </div>
                  )}

                  {activeTab.kind === "tool" && (
                    <ToolPanel
                      tools={state.tools}
                      patchLocalTools={patchLocalTools}
                      updateTool={updateTool}
                      runAction={runAction}
                    />
                  )}

                  {activeTab.kind === "settings" && (
                    <SettingsPanel
                      state={state}
                      settings={state.settings}
                      tools={state.tools}
                      patchLocalSettings={patchLocalSettings}
                      patchLocalTools={patchLocalTools}
                      updateSetting={updateSetting}
                      updateTool={updateTool}
                      runAction={runAction}
                    />
                  )}

                  {activeTab.kind === "help" && <HelpPanel runAction={runAction} />}
                  {activeTab.kind === "reward" && <RewardPanel macroTotalCount={state.macroTotalCount} />}
                  {activeTab.kind === "thanks" && <ThanksPanel runAction={runAction} />}
                </main>
              )}
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}

function TitleBar({
  state,
  runAction
}: {
  state: RmtState;
  runAction: RunAction;
}) {
  return (
    <header className="titlebar">
      <div className="drag-region">
        <div className="app-mark">RMT</div>
        <span>{state.version}</span>
      </div>
      <div className="window-actions">
        <button title={uiCopy.window.minimize} onClick={() => runAction("minimize")} type="button">
          <Minus size={16} />
        </button>
        <button title={uiCopy.window.maximize} onClick={() => runAction("maximize")} type="button">
          <Maximize2 size={15} />
        </button>
        <button className="close" title={uiCopy.window.close} onClick={() => runAction("close")} type="button">
          <X size={16} />
        </button>
      </div>
    </header>
  );
}

function TopTabs({
  state,
  hiddenTopButtonIndexes,
  runAction
}: {
  state: RmtState;
  hiddenTopButtonIndexes: number[];
  runAction: RunAction;
}) {
  const hiddenSet = new Set(hiddenTopButtonIndexes);
  const visibleTabs = state.tabs.filter((tab) => tab.kind === "settings" || !hiddenSet.has(tab.index));

  return (
    <nav className="classic-tabs" aria-label={uiCopy.tabs.ariaLabel}>
      {visibleTabs.map((tab) => {
        const Icon = getTabIcon(tab);
        return (
          <button
            className={classNames(tab.index === state.activeTabIndex && "active")}
            key={tab.index}
            onClick={() => runAction("setTab", { tabIndex: tab.index })}
            type="button"
          >
            <Icon size={16} />
            <span>{getTabLabel(tab)}</span>
          </button>
        );
      })}
    </nav>
  );
}

function getTabIcon(tab: RmtTab) {
  if (tab.kind === "macro") {
    switch (tab.table?.index ?? tab.index) {
      case 1:
        return Keyboard;
      case 2:
        return FileText;
      case 3:
        return MenuIcon;
      case 4:
        return Timer;
      case 5:
        return ListTree;
      case 6:
        return Repeat2;
      default:
        return Keyboard;
    }
  }

  switch (tab.kind) {
    case "tool":
      return Wrench;
    case "settings":
      return Settings;
    case "help":
      return HelpCircle;
    case "reward":
      return Gift;
    case "thanks":
      return CheckCircle2;
    default:
      return Keyboard;
  }
}

function getTabLabel(tab: RmtTab): string {
  if (tab.kind === "reward") {
    return uiCopy.tabs.rewardShort;
  }
  if (tab.kind === "thanks") {
    return uiCopy.tabs.thanksShort;
  }
  return tab.name;
}

function GlobalSidebar({ state, runAction }: { state: RmtState; runAction: RunAction }) {
  return (
    <aside className="classic-global-sidebar">
      <div className="sidebar-section">
        <span className="side-label">{uiCopy.sidebar.currentConfig}</span>
        <button className="config-select-button" onClick={() => runAction("openSettingManager")} title={state.currentSettingName} type="button">
          {state.currentSettingName}
        </button>
        <button className="side-button green" onClick={() => runAction("openSettingManager")} type="button">
          <Settings size={15} />
          {uiCopy.sidebar.configManager}
        </button>
      </div>

      <div className="sidebar-section global-actions">
        <span className="side-label">{uiCopy.sidebar.globalActions}</span>
        <button
          className={classNames("side-card", state.isSuspend && "is-active")}
          onClick={() => runAction("toggleSuspend")}
          type="button"
        >
          <span>
            <Pause size={15} />
            {uiCopy.sidebar.suspend}
          </span>
          <kbd>{formatHotkey(state.settings.suspendHotkey)}</kbd>
        </button>
        <button
          className={classNames("side-card", state.isPause && "is-active")}
          onClick={() => runAction("togglePause")}
          type="button"
        >
          <span>
            <Square size={15} />
            {uiCopy.sidebar.pause}
          </span>
          <kbd>{formatHotkey(state.settings.pauseHotkey)}</kbd>
        </button>
        <button className="side-button red" onClick={() => runAction("killAll")} type="button">
          <Square size={15} />
          {uiCopy.sidebar.killMacro}
        </button>
        <kbd className="shortcut-line">{formatHotkey(state.settings.killMacroHotkey)}</kbd>
        <button className="side-button gray" onClick={() => runAction("reload")} type="button">
          <RefreshCw size={15} />
          {uiCopy.sidebar.reload}
        </button>
        <button className="side-button blue" onClick={() => runAction("openHelp")} type="button">
          <HelpCircle size={15} />
          {uiCopy.sidebar.help}
        </button>
      </div>

      <div className="sidebar-save">
        <button className="side-button green" onClick={() => runAction("save")} type="button">
          <Save size={15} />
          {uiCopy.sidebar.save}
        </button>
      </div>
    </aside>
  );
}

function formatHotkey(value: string): string {
  const modifierLabels: Record<string, string> = {
    "!": "Alt",
    "^": "Ctrl",
    "+": "Shift",
    "#": "Win"
  };
  const modifiers: string[] = [];
  let key = value.trim();

  while (key.length > 0 && modifierLabels[key[0]]) {
    modifiers.push(modifierLabels[key[0]]);
    key = key.slice(1);
  }

  const mainKey = key.replace(/[{}]/g, "").trim();
  const parts = [...modifiers, mainKey].filter(Boolean);
  return parts.length > 0 ? parts.join("+") : uiCopy.common.unsetHotkey;
}

function MacroTable({
  tab,
  patchLocalItem,
  patchLocalFold,
  updateItem,
  updateFold,
  runAction
}: {
  tab: RmtTab;
  patchLocalItem: (tableIndex: number, itemIndex: number, field: keyof RmtItem, value: unknown) => void;
  patchLocalFold: (tableIndex: number, foldIndex: number, field: keyof RmtFold, value: unknown) => void;
  updateItem: (tableIndex: number, itemIndex: number, field: keyof RmtItem, value: unknown) => void;
  updateFold: (tableIndex: number, foldIndex: number, field: keyof RmtFold, value: unknown) => void;
  runAction: RunAction;
}) {
  const table = tab.table!;
  const itemCount = table.folds.reduce((count, fold) => count + fold.items.length, 0);
  const confirmAction = <T extends RmtActionType>(message: string, type: T, ...args: ActionArgs<T>) => {
    if (window.confirm(message)) {
      void runAction(type, ...args);
    }
  };

  return (
    <section className="macro-view classic-module-stack">
      {table.folds.length === 0 && (
        <div className="module-empty-row">
          <button onClick={() => runAction("addFold", { tableIndex: table.index, afterFoldIndex: 0 })} type="button">
            <Plus size={16} />
            {uiCopy.macro.addModule}
          </button>
        </div>
      )}

      {table.folds.map((fold) => (
          <section className={classNames("macro-module-section", fold.forbid && "is-disabled")} key={fold.index}>
            <div className="module-config-row">
              <label className="module-field remark-field">
                <span>{uiCopy.macro.remark}</span>
                <input
                  value={fold.remark}
                  placeholder={`${uiCopy.macro.modulePlaceholder} ${fold.index}`}
                  onChange={(event) => patchLocalFold(table.index, fold.index, "remark", event.target.value)}
                  onBlur={(event) => updateFold(table.index, fold.index, "remark", event.target.value)}
                />
              </label>
              <label className="module-field front-field">
                <span>{uiCopy.macro.front}</span>
                <input
                  value={fold.frontInfo}
                  placeholder={uiCopy.macro.frontPlaceholder}
                  onChange={(event) => patchLocalFold(table.index, fold.index, "frontInfo", event.target.value)}
                  onBlur={(event) => updateFold(table.index, fold.index, "frontInfo", event.target.value)}
                />
              </label>
              <button onClick={() => runAction("openTriggerEditor", { tableIndex: table.index, foldIndex: fold.index })} type="button">
                <SquarePen size={15} />
                {uiCopy.macro.edit}
              </button>
              <button onClick={() => runAction("addItem", { tableIndex: table.index, foldIndex: fold.index })} type="button">
                <Plus size={15} />
                {uiCopy.macro.addMacro}
              </button>
              <button onClick={() => runAction("addFold", { tableIndex: table.index, afterFoldIndex: fold.index })} type="button">
                <Plus size={15} />
                {uiCopy.macro.addModule}
              </button>
              <button
                onClick={() =>
                  confirmAction(uiCopy.macro.confirmDeleteModule, "deleteFold", {
                    tableIndex: table.index,
                    foldIndex: fold.index
                  })
                }
                type="button"
              >
                <Trash2 size={15} />
                {uiCopy.macro.deleteModule}
              </button>
              <label className="inline-check module-disabled">
                <input
                  type="checkbox"
                  checked={fold.forbid}
                  onChange={(event) => {
                    patchLocalFold(table.index, fold.index, "forbid", event.target.checked);
                    updateFold(table.index, fold.index, "forbid", event.target.checked);
                  }}
                />
                {uiCopy.macro.disabled}
              </label>
              <button
                className="module-expand-button"
                onClick={() => runAction("toggleFold", { tableIndex: table.index, foldIndex: fold.index })}
                title={fold.collapsed ? uiCopy.macro.expandModule : uiCopy.macro.collapseModule}
                type="button"
              >
                {fold.collapsed ? <ChevronRight size={18} /> : <ChevronDown size={18} />}
              </button>
            </div>

            {!fold.collapsed && (
              <div className="module-macro-list">
                <div className="module-macro-header">
                  <span />
                  {uiCopy.macro.headers.map((header) => (
                    <span key={header}>{header}</span>
                  ))}
                </div>

                {fold.items.length === 0 && <div className="module-empty-row">{uiCopy.macro.emptyModule}</div>}

                {fold.items.map((item) => (
                  <div
                    className={classNames("module-macro-row", (item.forbid || item.pause) && "row-muted")}
                    key={item.serial || item.index}
                  >
                    <div className="macro-row-index">
                      <span className="drag-handle" title={uiCopy.macro.dragHint}>
                        <GripVertical size={16} />
                      </span>
                      <strong>{item.index}.</strong>
                    </div>
                    <input
                      value={item.remark}
                      placeholder={uiCopy.macro.macroName}
                      onChange={(event) => patchLocalItem(table.index, item.index, "remark", event.target.value)}
                      onBlur={(event) => updateItem(table.index, item.index, "remark", event.target.value)}
                    />
                    <button
                      className="trigger-editor-button"
                      title={table.isTimingTable ? uiCopy.macro.editTiming : table.isStringTable ? uiCopy.macro.editStringTrigger : uiCopy.macro.editTriggerKey}
                      onClick={() => runAction("openTriggerEditor", { tableIndex: table.index, itemIndex: item.index })}
                      type="button"
                    >
                      {item.trigger || uiCopy.macro.edit}
                    </button>
                    <select
                      className="select-cell"
                      value={item.triggerType}
                      disabled={table.isTimingTable}
                      onChange={(event) => {
                        const value = Number(event.target.value);
                        patchLocalItem(table.index, item.index, "triggerType", value);
                        updateItem(table.index, item.index, "triggerType", value);
                      }}
                    >
                      {uiCopy.macro.triggerTypeLabels.map((label, index) => (
                        <option key={label} value={index + 1}>
                          {label}
                        </option>
                      ))}
                    </select>
                    <input
                      value={item.loopCount}
                      onChange={(event) => patchLocalItem(table.index, item.index, "loopCount", event.target.value)}
                      onBlur={(event) => updateItem(table.index, item.index, "loopCount", event.target.value)}
                    />
                    <MacroSettingsControl
                      item={item}
                      tableIndex={table.index}
                      patchLocalItem={patchLocalItem}
                      updateItem={updateItem}
                    />
                    <button
                      onClick={() => runAction("openMacroEditor", { tableIndex: table.index, itemIndex: item.index })}
                      title={item.macro || uiCopy.macro.editMacro}
                      type="button"
                    >
                      <SquarePen size={14} />
                      {uiCopy.macro.edit}
                    </button>
                    <div className="move-buttons">
                      <button
                        disabled={item.index <= 1}
                        onClick={() => runAction("moveItem", { tableIndex: table.index, itemIndex: item.index, direction: -1 })}
                        title={uiCopy.macro.moveUp}
                        type="button"
                      >
                        <ArrowUp size={14} />
                      </button>
                      <button
                        disabled={item.index >= itemCount}
                        onClick={() => runAction("moveItem", { tableIndex: table.index, itemIndex: item.index, direction: 1 })}
                        title={uiCopy.macro.moveDown}
                        type="button"
                      >
                        <ArrowDown size={14} />
                      </button>
                    </div>
                    <label className="inline-check row-disabled">
                      <input
                        type="checkbox"
                        checked={item.forbid}
                        onChange={(event) => {
                          patchLocalItem(table.index, item.index, "forbid", event.target.checked);
                          updateItem(table.index, item.index, "forbid", event.target.checked);
                        }}
                      />
                      {uiCopy.macro.disabled}
                    </label>
                    <button
                      className="danger"
                      onClick={() =>
                        confirmAction(uiCopy.macro.confirmDeleteMacro, "deleteItem", {
                          tableIndex: table.index,
                          itemIndex: item.index
                        })
                      }
                      type="button"
                    >
                      <Trash2 size={14} />
                      {uiCopy.macro.delete}
                    </button>
                  </div>
                ))}
              </div>
            )}

            {fold.collapsed && (
              <div className="module-collapsed-note">
                {uiCopy.macro.collapsedPrefix} {fold.index} {uiCopy.macro.collapsedSuffix}
              </div>
            )}
          </section>
      ))}
    </section>
  );
}

function MacroSettingsControl({
  item,
  tableIndex,
  patchLocalItem,
  updateItem
}: {
  item: RmtItem;
  tableIndex: number;
  patchLocalItem: (tableIndex: number, itemIndex: number, field: keyof RmtItem, value: unknown) => void;
  updateItem: (tableIndex: number, itemIndex: number, field: keyof RmtItem, value: unknown) => void;
}) {
  return (
    <details className="macro-settings-cell">
      <summary>
        <SlidersHorizontal size={14} />
        {uiCopy.macro.settings}
      </summary>
      <div className="macro-settings-panel">
        <label>
          <span>{uiCopy.macro.mode}</span>
          <select
            value={item.mode}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalItem(tableIndex, item.index, "mode", value);
              updateItem(tableIndex, item.index, "mode", value);
            }}
          >
            {uiCopy.macro.modeLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>{uiCopy.macro.holdTime}</span>
          <input
            type="number"
            min={0}
            value={item.holdTime}
            onChange={(event) => patchLocalItem(tableIndex, item.index, "holdTime", Number(event.target.value))}
            onBlur={(event) => updateItem(tableIndex, item.index, "holdTime", Number(event.target.value))}
          />
        </label>
        <label>
          <span>{uiCopy.macro.startSound}</span>
          <select
            value={item.startTipSound}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalItem(tableIndex, item.index, "startTipSound", value);
              updateItem(tableIndex, item.index, "startTipSound", value);
            }}
          >
            {uiCopy.macro.startTipLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>{uiCopy.macro.endSound}</span>
          <select
            value={item.endTipSound}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalItem(tableIndex, item.index, "endTipSound", value);
              updateItem(tableIndex, item.index, "endTipSound", value);
            }}
          >
            {uiCopy.macro.endTipLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </label>
      </div>
    </details>
  );
}

function LegacyGroup({
  title,
  className,
  children
}: {
  title: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <fieldset className={classNames("legacy-group", className)}>
      <legend>{title}</legend>
      {children}
    </fieldset>
  );
}

function LegacyHotkeyCell({
  label,
  value,
  target,
  onLocal,
  onCommit,
  runAction
}: {
  label: string;
  value: string;
  target: RmtActionPayload<"openHotkeyEditor">["target"];
  onLocal: (value: string) => void;
  onCommit: (value: string) => void;
  runAction: RunAction;
}) {
  return (
    <div className="legacy-hotkey-cell">
      <span>{label}:</span>
      <TextInput value={value} onLocal={onLocal} onCommit={onCommit} />
      <button onClick={() => runAction("openHotkeyEditor", { target })} type="button">
        {uiCopy.macro.edit}
      </button>
    </div>
  );
}

function LegacyField({
  label,
  children
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="legacy-field">
      <span>{label}:</span>
      {children}
    </div>
  );
}

function ToolPanel({
  tools,
  patchLocalTools,
  updateTool,
  runAction
}: {
  tools: RmtToolState;
  patchLocalTools: (field: keyof RmtToolState, value: unknown) => void;
  updateTool: (field: keyof RmtToolState, value: unknown) => void;
  runAction: RunAction;
}) {
  const toolInfoRows = uiCopy.tool.infoRows.map((label, index) => {
    const values = [
      tools.mousePos,
      tools.mouseWinPos,
      tools.processTitle,
      tools.processName,
      tools.processClass,
      tools.processPid,
      tools.processId,
      tools.color
    ];
    return [label, values[index]] as const;
  });

  return (
    <section className="legacy-page tool-legacy-page">
      <LegacyGroup title={uiCopy.tool.toolWindows}>
        <div className="legacy-row legacy-row-compact">
          <span className="legacy-label">{uiCopy.tool.variableMonitor}:</span>
          <button className="legacy-command" onClick={() => runAction("openVarMonitor")} type="button">
            {uiCopy.tool.openMonitor}
          </button>
        </div>

        <div className="legacy-row tool-hotkey-row">
          <span className="legacy-label">{uiCopy.tool.mouseInfoHotkey}:</span>
          <TextInput value={tools.toolCheckHotKey} onLocal={(value) => patchLocalTools("toolCheckHotKey", value)} onCommit={(value) => updateTool("toolCheckHotKey", value)} />
          <label className="legacy-check">
            <input type="checkbox" checked={tools.isToolCheck} onChange={() => runAction("toggleToolCheck")} />
            {uiCopy.tool.toggle}
          </label>
          <label className="legacy-check">
            <input
              type="checkbox"
              checked={tools.alwaysOnTop}
              onChange={(event) => {
                patchLocalTools("alwaysOnTop", event.target.checked);
                updateTool("alwaysOnTop", event.target.checked);
              }}
            />
            {uiCopy.tool.alwaysOnTop}
          </label>
        </div>

        <div className="legacy-info-form">
          {toolInfoRows.map(([label, value]) => (
            <div className="legacy-readonly-row" key={label}>
              <span>{label}:</span>
              <input readOnly title={value} value={value || ""} />
            </div>
          ))}
        </div>

        <div className="legacy-row tool-hotkey-row">
          <span className="legacy-label">{uiCopy.tool.recordHotkey}:</span>
          <TextInput value={tools.toolRecordMacroHotKey} onLocal={(value) => patchLocalTools("toolRecordMacroHotKey", value)} onCommit={(value) => updateTool("toolRecordMacroHotKey", value)} />
          <label className="legacy-check">
            <input type="checkbox" checked={tools.isToolRecord} onChange={() => runAction("toggleToolRecord")} />
            {uiCopy.tool.toggle}
          </label>
          <button className="legacy-command" onClick={() => runAction("openToolRecordSetting")} type="button">
            {uiCopy.tool.recordOptions}
          </button>
        </div>

        <div className="legacy-row tool-text-row">
          <span className="legacy-label">{uiCopy.tool.textFilterHotkey}:</span>
          <TextInput value={tools.toolTextFilterHotKey} onLocal={(value) => patchLocalTools("toolTextFilterHotKey", value)} onCommit={(value) => updateTool("toolTextFilterHotKey", value)} />
          <button className="legacy-command" onClick={() => runAction("toolTextFilterScreenShot")} type="button">
            {uiCopy.tool.extractFromScreenshot}
          </button>
          <button className="legacy-command" onClick={() => runAction("toolTextFilterSelectImage")} type="button">
            {uiCopy.tool.extractFromImage}
          </button>
        </div>

        <div className="legacy-row tool-options-row">
          <span className="legacy-label">{uiCopy.tool.relatedOptions}:</span>
          <span>{uiCopy.tool.ocrModel}:</span>
          <select
            value={tools.ocrType}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalTools("ocrType", value);
              updateTool("ocrType", value);
            }}
          >
            {uiCopy.tool.ocrLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
          <button className="legacy-command" onClick={() => runAction("openFreePaste")} type="button">
            {uiCopy.tool.freePaste}
          </button>
          <button className="legacy-command" onClick={() => runAction("editCmdTip")} type="button">
            {uiCopy.tool.commandDisplay}
          </button>
        </div>

        <div className="legacy-row tool-extra-hotkeys">
          <span className="legacy-label">{uiCopy.tool.screenshotHotkey}:</span>
          <TextInput value={tools.screenShotHotKey} onLocal={(value) => patchLocalTools("screenShotHotKey", value)} onCommit={(value) => updateTool("screenShotHotKey", value)} />
          <span>{uiCopy.tool.freePasteHotkey}:</span>
          <TextInput value={tools.freePasteHotKey} onLocal={(value) => patchLocalTools("freePasteHotKey", value)} onCommit={(value) => updateTool("freePasteHotKey", value)} />
        </div>

        <div className="legacy-output-label">
          {uiCopy.tool.textAndRecord}
          <button className="legacy-command danger" onClick={() => runAction("clearToolText")} type="button">
            {uiCopy.tool.clearContent}
          </button>
        </div>
        <textarea className="tool-output legacy-tool-output" readOnly value={tools.toolText} />
      </LegacyGroup>
    </section>
  );
}

function SettingsPanel({
  state,
  settings,
  tools,
  patchLocalSettings,
  patchLocalTools,
  updateSetting,
  updateTool,
  runAction
}: {
  state: RmtState;
  settings: RmtSettings;
  tools: RmtToolState;
  patchLocalSettings: (field: keyof RmtSettings, value: unknown) => void;
  patchLocalTools: (field: keyof RmtToolState, value: unknown) => void;
  updateSetting: (field: keyof RmtSettings, value: unknown) => void;
  updateTool: (field: keyof RmtToolState, value: unknown) => void;
  runAction: RunAction;
}) {
  const hiddenTopButtonSet = new Set(settings.hiddenTopButtonIndexes);
  const topButtonTabs = state.tabs.filter((tab) => tab.kind !== "settings");
  const activeColorPreset = getColorPreset(settings.colorPresetId);

  function setTopButtonVisible(tabIndex: number, visible: boolean) {
    const targetTab = state.tabs.find((tab) => tab.index === tabIndex);
    if (targetTab?.kind === "settings") {
      return;
    }

    const hiddenIndexes = new Set(settings.hiddenTopButtonIndexes);
    if (visible) {
      hiddenIndexes.delete(tabIndex);
    } else {
      hiddenIndexes.add(tabIndex);
    }
    const nextValue = Array.from(hiddenIndexes).sort((a, b) => a - b);
    patchLocalSettings("hiddenTopButtonIndexes", nextValue);
    updateSetting("hiddenTopButtonIndexes", nextValue);
  }

  function setColorPreset(presetId: string) {
    patchLocalSettings("colorPresetId", presetId);
    updateSetting("colorPresetId", presetId);
  }

  return (
    <section className="legacy-page settings-legacy-page">
      <LegacyGroup title={uiCopy.settings.hotkeys}>
        <div className="legacy-hotkey-grid">
          <LegacyHotkeyCell label={uiCopy.settings.suspend} value={settings.suspendHotkey} target="suspendHotkey" onLocal={(value) => patchLocalSettings("suspendHotkey", value)} onCommit={(value) => updateSetting("suspendHotkey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.settings.pause} value={settings.pauseHotkey} target="pauseHotkey" onLocal={(value) => patchLocalSettings("pauseHotkey", value)} onCommit={(value) => updateSetting("pauseHotkey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.settings.killAllMacros} value={settings.killMacroHotkey} target="killMacroHotkey" onLocal={(value) => patchLocalSettings("killMacroHotkey", value)} onCommit={(value) => updateSetting("killMacroHotkey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.tool.recordHotkey} value={tools.toolRecordMacroHotKey} target="toolRecordMacroHotKey" onLocal={(value) => patchLocalTools("toolRecordMacroHotKey", value)} onCommit={(value) => updateTool("toolRecordMacroHotKey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.tool.textFilterHotkey} value={tools.toolTextFilterHotKey} target="toolTextFilterHotKey" onLocal={(value) => patchLocalTools("toolTextFilterHotKey", value)} onCommit={(value) => updateTool("toolTextFilterHotKey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.tool.screenshotHotkey} value={tools.screenShotHotKey} target="screenShotHotKey" onLocal={(value) => patchLocalTools("screenShotHotKey", value)} onCommit={(value) => updateTool("screenShotHotKey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.tool.freePasteHotkey} value={tools.freePasteHotKey} target="freePasteHotKey" onLocal={(value) => patchLocalTools("freePasteHotKey", value)} onCommit={(value) => updateTool("freePasteHotKey", value)} runAction={runAction} />
          <LegacyHotkeyCell label={uiCopy.tool.mouseInfoHotkey} value={tools.toolCheckHotKey} target="toolCheckHotKey" onLocal={(value) => patchLocalTools("toolCheckHotKey", value)} onCommit={(value) => updateTool("toolCheckHotKey", value)} runAction={runAction} />
        </div>
      </LegacyGroup>

      <LegacyGroup title={uiCopy.settings.numericOptions}>
        <div className="legacy-numeric-grid">
          <LegacyField label={uiCopy.settings.holdFloat}>
            <TextInput value={settings.holdFloat} onLocal={(value) => patchLocalSettings("holdFloat", value)} onCommit={(value) => updateSetting("holdFloat", value)} />
          </LegacyField>
          <LegacyField label={uiCopy.settings.preIntervalFloat}>
            <TextInput value={settings.preIntervalFloat} onLocal={(value) => patchLocalSettings("preIntervalFloat", value)} onCommit={(value) => updateSetting("preIntervalFloat", value)} />
          </LegacyField>
          <LegacyField label={uiCopy.settings.intervalFloat}>
            <TextInput value={settings.intervalFloat} onLocal={(value) => patchLocalSettings("intervalFloat", value)} onCommit={(value) => updateSetting("intervalFloat", value)} />
          </LegacyField>
          <LegacyField label={uiCopy.settings.coordXFloat}>
            <TextInput value={settings.coordXFloat} onLocal={(value) => patchLocalSettings("coordXFloat", value)} onCommit={(value) => updateSetting("coordXFloat", value)} />
          </LegacyField>
          <LegacyField label={uiCopy.settings.coordYFloat}>
            <TextInput value={settings.coordYFloat} onLocal={(value) => patchLocalSettings("coordYFloat", value)} onCommit={(value) => updateSetting("coordYFloat", value)} />
          </LegacyField>
          <LegacyField label={uiCopy.settings.multiThreadNum}>
            <TextInput value={settings.mutiThreadNum} onLocal={(value) => patchLocalSettings("mutiThreadNum", value)} onCommit={(value) => updateSetting("mutiThreadNum", value)} />
          </LegacyField>
          <LegacyField label={uiCopy.settings.softBGColor}>
            <TextInput value={settings.softBGColor} onLocal={(value) => patchLocalSettings("softBGColor", value)} onCommit={(value) => updateSetting("softBGColor", value)} />
          </LegacyField>
        </div>
      </LegacyGroup>

      <LegacyGroup title={uiCopy.settings.switchOptions}>
        <div className="legacy-switch-grid">
          <label className="legacy-check">
            <input type="checkbox" checked={settings.bootStart} onChange={(event) => { patchLocalSettings("bootStart", event.target.checked); updateSetting("bootStart", event.target.checked); }} />
            {uiCopy.settings.bootStart}
          </label>
          <label className="legacy-check">
            <input type="checkbox" checked={settings.cmdTip} onChange={(event) => { patchLocalSettings("cmdTip", event.target.checked); updateSetting("cmdTip", event.target.checked); }} />
            {uiCopy.settings.cmdTip}
          </label>
          <button className="legacy-command" onClick={() => runAction("editCmdTip")} type="button">
            {uiCopy.tool.commandDisplay}
          </button>
          <button className="legacy-command" onClick={() => runAction("openToolRecordSetting")} type="button">
            {uiCopy.tool.recordOptions}
          </button>
          <label className="legacy-check">
            <input type="checkbox" checked={settings.noVariableTip} onChange={(event) => { patchLocalSettings("noVariableTip", event.target.checked); updateSetting("noVariableTip", event.target.checked); }} />
            {uiCopy.settings.noVariableTip}
          </label>
          <label className="legacy-check">
            <input type="checkbox" checked={settings.fixedMenuWheel} onChange={(event) => { patchLocalSettings("fixedMenuWheel", event.target.checked); updateSetting("fixedMenuWheel", event.target.checked); }} />
            {uiCopy.settings.fixedMenuWheel}
          </label>
          <label className="legacy-check">
            <input type="checkbox" checked={settings.showSplitLine} onChange={(event) => { patchLocalSettings("showSplitLine", event.target.checked); updateSetting("showSplitLine", event.target.checked); }} />
            {uiCopy.settings.showSplitLine}
          </label>
        </div>
      </LegacyGroup>

      <LegacyGroup title={uiCopy.settings.dropdownOptions}>
        <div className="legacy-dropdown-grid">
          <LegacyField label={uiCopy.settings.lang}>
            <select value={settings.lang} onChange={(event) => { patchLocalSettings("lang", event.target.value); updateSetting("lang", event.target.value); }}>
              {settings.langOptions.map((option) => (
                <option key={option} value={option}>{option}</option>
              ))}
            </select>
          </LegacyField>
          <LegacyField label={uiCopy.settings.fontType}>
            <select value={settings.fontType} onChange={(event) => { patchLocalSettings("fontType", event.target.value); updateSetting("fontType", event.target.value); }}>
              {settings.fontOptions.map((option) => (
                <option key={option} value={option}>{option}</option>
              ))}
            </select>
          </LegacyField>
          <LegacyField label={uiCopy.settings.screenshotType}>
            <select value={settings.screenShotType} onChange={(event) => { const value = Number(event.target.value); patchLocalSettings("screenShotType", value); updateSetting("screenShotType", value); }}>
              {uiCopy.settings.screenshotLabels.map((label, index) => (
                <option key={label} value={index + 1}>{label}</option>
              ))}
            </select>
          </LegacyField>
          <LegacyField label={uiCopy.settings.keyDownMode}>
            <div className="legacy-help-field">
              <select value={settings.keyDownDownType} onChange={(event) => { const value = Number(event.target.value); patchLocalSettings("keyDownDownType", value); updateSetting("keyDownDownType", value); }}>
                {uiCopy.settings.keyDownLabels.map((label, index) => (
                  <option key={label} value={index + 1}>{label}</option>
                ))}
              </select>
              <button onClick={() => runAction("keyDownHelp")} type="button">?</button>
            </div>
          </LegacyField>
        </div>
      </LegacyGroup>

      <LegacyGroup title={uiCopy.settings.interfaceOptions}>
        <div className="legacy-interface-grid">
          <div>
            <span className="legacy-subtitle">{uiCopy.settings.colorPreset}</span>
            <div className="color-preset-grid">
              {colorPresets.map((preset) => (
                <button
                  aria-pressed={preset.id === activeColorPreset.id}
                  className={classNames("color-preset-button", preset.id === activeColorPreset.id && "active")}
                  key={preset.id}
                  onClick={() => setColorPreset(preset.id)}
                  title={`${preset.name}: ${preset.primaryColor} / ${preset.secondaryColor}`}
                  type="button"
                >
                  <span className="color-preset-swatch" aria-hidden="true">
                    <span style={{ background: preset.primaryColor }} />
                    <span style={{ background: preset.secondaryColor }} />
                  </span>
                  <span>{preset.name}</span>
                </button>
              ))}
            </div>
          </div>
          <div>
            <span className="legacy-subtitle">{uiCopy.settings.topButtonVisibility}</span>
            <div className="top-button-toggle-grid">
              {topButtonTabs.map((tab) => (
                <label className="legacy-check" key={tab.index}>
                  <input type="checkbox" checked={!hiddenTopButtonSet.has(tab.index)} onChange={(event) => setTopButtonVisible(tab.index, event.target.checked)} />
                  {getTabLabel(tab)}
                </label>
              ))}
            </div>
          </div>
        </div>
      </LegacyGroup>

      <LegacyGroup title={uiCopy.settings.diagnostics} className="diagnostics-block legacy-diagnostics">
        <div className="info-grid">
          <div className="info-item"><span>{uiCopy.settings.version}</span><strong>{state.version}</strong></div>
          <div className="info-item"><span>{uiCopy.settings.config}</span><strong title={state.currentSettingName}>{state.currentSettingName}</strong></div>
          <div className="info-item"><span>{uiCopy.settings.running}</span><strong>{state.macroRunningCount}</strong></div>
          <div className="info-item"><span>{uiCopy.settings.totalRuns}</span><strong>{state.macroTotalCount}</strong></div>
        </div>
        <button className="legacy-command" onClick={() => runAction("copyDiagnostics")} type="button">
          {uiCopy.settings.copyDiagnostics}
        </button>
      </LegacyGroup>
    </section>
  );
}

function HelpPanel({ runAction }: { runAction: RunAction }) {
  return (
    <section className="section-block readable">
      <h2>{uiCopy.help.title}</h2>
      {uiCopy.help.body.map((paragraph) => (
        <p key={paragraph}>{paragraph}</p>
      ))}
      <div className="link-list">
        {uiCopy.help.links.map((link) => (
          <button
            key={link.label}
            onClick={() => (link.action === "openUrl" ? runAction("openUrl", { url: link.url }) : runAction("openHelp"))}
            type="button"
          >
            <ExternalLink size={16} />
            {link.label}
          </button>
        ))}
      </div>
    </section>
  );
}

function RewardPanel({ macroTotalCount }: { macroTotalCount: number }) {
  const totalText = new Intl.NumberFormat("zh-CN").format(macroTotalCount);

  return (
    <section className="section-block reward-panel">
      <h2>{uiCopy.reward.title}</h2>
      <p>{uiCopy.reward.intro}</p>
      <p>
        {uiCopy.reward.totalPrefix} {totalText} {uiCopy.reward.totalSuffix}
      </p>
      <div className="qr-grid">
        <figure>
          <img alt={uiCopy.reward.wechatAlt} src="/Images/Soft/WeiXin.png" />
          <figcaption>{uiCopy.reward.wechat}</figcaption>
        </figure>
        <figure>
          <img alt={uiCopy.reward.alipayAlt} src="/Images/Soft/ZhiFuBao.png" />
          <figcaption>{uiCopy.reward.alipay}</figcaption>
        </figure>
      </div>
      <p>{uiCopy.reward.closing}</p>
    </section>
  );
}

function ThanksPanel({ runAction }: { runAction: RunAction }) {
  return (
    <section className="section-block thanks-panel">
      <h2>{uiCopy.thanks.title}</h2>
      <div className="thanks-group">
        <h3>{uiCopy.thanks.contributors}</h3>
        <div className="tag-list">
          {uiCopy.thanks.developers.map(([label, url]) => (
            <button className="link-chip" key={label} onClick={() => runAction("openUrl", { url })} type="button">
              {label}
            </button>
          ))}
        </div>
      </div>
      <div className="thanks-group">
        <h3>{uiCopy.thanks.openSource}</h3>
        <div className="tag-list">
          {uiCopy.thanks.projects.map(([label, url]) => (
            <button className="link-chip" key={label} onClick={() => runAction("openUrl", { url })} type="button">
              {label}
            </button>
          ))}
        </div>
      </div>
      <div className="thanks-group">
        <h3>{uiCopy.thanks.community}</h3>
        <div className="tag-list muted-tags">
          {uiCopy.thanks.communityNames.map((name) => (
            <span key={name}>{name}</span>
          ))}
        </div>
      </div>
      {uiCopy.thanks.body.map((paragraph) => (
        <p key={paragraph}>{paragraph}</p>
      ))}
    </section>
  );
}

function TextInput({
  value,
  onLocal,
  onCommit
}: {
  value: string;
  onLocal: (value: string) => void;
  onCommit: (value: string) => void;
}) {
  return (
    <input
      value={value}
      onChange={(event) => onLocal(event.target.value)}
      onBlur={(event) => onCommit(event.target.value)}
    />
  );
}

function findFold(state: RmtState, tableIndex: number, foldIndex: number): RmtFold | undefined {
  return state.tabs
    .find((tab) => tab.table?.index === tableIndex)
    ?.table?.folds.find((fold) => fold.index === foldIndex);
}

function findItem(state: RmtState, tableIndex: number, itemIndex: number): RmtItem | undefined {
  return state.tabs
    .find((tab) => tab.table?.index === tableIndex)
    ?.table?.folds.flatMap((fold) => fold.items)
    .find((item) => item.index === itemIndex);
}
