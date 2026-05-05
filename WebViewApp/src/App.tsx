import {
  ArrowDown,
  ArrowUp,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Clipboard,
  Eraser,
  ExternalLink,
  FileText,
  Gift,
  GripVertical,
  HelpCircle,
  Image as ImageIcon,
  Keyboard,
  ListTree,
  Maximize2,
  Menu as MenuIcon,
  Minus,
  MousePointer2,
  Pause,
  Play,
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

const triggerTypeLabels = ["按下", "松开", "松止", "开关", "长按"];
const modeLabels = ["AHK Send", "keybd_event", "罗技"];
const startTipLabels = ["无", "触发提示", "循环首次提示"];
const endTipLabels = ["无", "结束提示", "循环结束提示"];
const screenshotLabels = ["微软截图", "RMT截图", "SC截图"];
const keyDownLabels = ["自动松开", "忽略重复按下", "允许重复按下"];
const ocrLabels = ["中文", "英文"];
const uiDesignWidth = 1360;
const uiDesignHeight = 720;
const minUiScale = 0.65;

function cloneState(state: RmtState): RmtState {
  return structuredClone(state);
}

function classNames(...values: Array<string | false | null | undefined>): string {
  return values.filter(Boolean).join(" ");
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
      setMessage(result.message || (result.ok ? "" : "操作失败"));
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

  const scaleStyle = {
    "--rmt-ui-scale": String(uiScale)
  } as React.CSSProperties;

  return (
    <div className="rmt-scale-viewport" ref={scaleHostRef}>
      <div className="rmt-scale-content" style={scaleStyle}>
        <div className="app-shell classic-app">
          <TitleBar state={state} runAction={runAction} />

          <div className="classic-body">
            <GlobalSidebar state={state} runAction={runAction} />

            <section className="classic-main">
              <TopTabs state={state} runAction={runAction} />

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
                  <div className="content-header">
                    <div>
                      <div className="eyebrow">{activeTab.symbol}</div>
                      <h1>{activeTab.name}</h1>
                    </div>
                    <div className="runtime-summary">
                      <span className={classNames("dot", state.isMacroWorking && "running")} />
                      <span>运行中 {state.macroRunningCount}</span>
                    </div>
                  </div>

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
                      patchLocalSettings={patchLocalSettings}
                      updateSetting={updateSetting}
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
        <button title="最小化" onClick={() => runAction("minimize")} type="button">
          <Minus size={16} />
        </button>
        <button title="最大化/还原" onClick={() => runAction("maximize")} type="button">
          <Maximize2 size={15} />
        </button>
        <button className="close" title="关闭" onClick={() => runAction("close")} type="button">
          <X size={16} />
        </button>
      </div>
    </header>
  );
}

function TopTabs({ state, runAction }: { state: RmtState; runAction: RunAction }) {
  return (
    <nav className="classic-tabs" aria-label="RMT 功能页签">
      {state.tabs.map((tab) => {
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
    return "打赏";
  }
  if (tab.kind === "thanks") {
    return "感谢";
  }
  return tab.name;
}

function GlobalSidebar({ state, runAction }: { state: RmtState; runAction: RunAction }) {
  return (
    <aside className="classic-global-sidebar">
      <div className="sidebar-section">
        <span className="side-label">当前配置</span>
        <button className="config-select-button" onClick={() => runAction("openSettingManager")} title={state.currentSettingName} type="button">
          {state.currentSettingName}
        </button>
        <button className="side-button green" onClick={() => runAction("openSettingManager")} type="button">
          <Settings size={15} />
          配置管理
        </button>
      </div>

      <div className="sidebar-section global-actions">
        <span className="side-label">全局操作</span>
        <button
          className={classNames("side-card", state.isSuspend && "is-active")}
          onClick={() => runAction("toggleSuspend")}
          type="button"
        >
          <span>
            <Pause size={15} />
            休眠
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
            暂停
          </span>
          <kbd>{formatHotkey(state.settings.pauseHotkey)}</kbd>
        </button>
        <button className="side-button red" onClick={() => runAction("killAll")} type="button">
          <Square size={15} />
          终止宏
        </button>
        <kbd className="shortcut-line">{formatHotkey(state.settings.killMacroHotkey)}</kbd>
        <button className="side-button gray" onClick={() => runAction("reload")} type="button">
          <RefreshCw size={15} />
          重载
        </button>
        <button className="side-button blue" onClick={() => runAction("openHelp")} type="button">
          <HelpCircle size={15} />
          帮助
        </button>
      </div>

      <div className="sidebar-save">
        <button className="side-button green" onClick={() => runAction("save")} type="button">
          <Save size={15} />
          保存
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
  return parts.length > 0 ? parts.join("+") : "未设置";
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
            新增模块
          </button>
        </div>
      )}

      {table.folds.map((fold) => (
          <section className={classNames("macro-module-section", fold.forbid && "is-disabled")} key={fold.index}>
            <div className="module-config-row">
              <label className="module-field remark-field">
                <span>备注:</span>
                <input
                  value={fold.remark}
                  placeholder={`模块 ${fold.index}`}
                  onChange={(event) => patchLocalFold(table.index, fold.index, "remark", event.target.value)}
                  onBlur={(event) => updateFold(table.index, fold.index, "remark", event.target.value)}
                />
              </label>
              <label className="module-field front-field">
                <span>前台:</span>
                <input
                  value={fold.frontInfo}
                  placeholder="窗口标题 / 进程规则"
                  onChange={(event) => patchLocalFold(table.index, fold.index, "frontInfo", event.target.value)}
                  onBlur={(event) => updateFold(table.index, fold.index, "frontInfo", event.target.value)}
                />
              </label>
              <button onClick={() => runAction("openTriggerEditor", { tableIndex: table.index, foldIndex: fold.index })} type="button">
                <SquarePen size={15} />
                编辑
              </button>
              <button onClick={() => runAction("addItem", { tableIndex: table.index, foldIndex: fold.index })} type="button">
                <Plus size={15} />
                新增宏
              </button>
              <button onClick={() => runAction("addFold", { tableIndex: table.index, afterFoldIndex: fold.index })} type="button">
                <Plus size={15} />
                新增模块
              </button>
              <button
                onClick={() =>
                  confirmAction("确认删除当前模块以及模块中的所有宏配置？", "deleteFold", {
                    tableIndex: table.index,
                    foldIndex: fold.index
                  })
                }
                type="button"
              >
                <Trash2 size={15} />
                删除模块
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
                禁用
              </label>
              <button
                className="module-expand-button"
                onClick={() => runAction("toggleFold", { tableIndex: table.index, foldIndex: fold.index })}
                title={fold.collapsed ? "展开模块" : "折叠模块"}
                type="button"
              >
                {fold.collapsed ? <ChevronRight size={18} /> : <ChevronDown size={18} />}
              </button>
            </div>

            {!fold.collapsed && (
              <div className="module-macro-list">
                <div className="module-macro-header">
                  <span />
                  <span>宏名称</span>
                  <span>触发编辑器</span>
                  <span>触发类型</span>
                  <span>循环次数</span>
                  <span>宏设置</span>
                  <span>宏编辑器</span>
                  <span>移动</span>
                  <span>状态</span>
                  <span>操作</span>
                </div>

                {fold.items.length === 0 && <div className="module-empty-row">当前模块没有宏。</div>}

                {fold.items.map((item) => (
                  <div
                    className={classNames("module-macro-row", (item.forbid || item.pause) && "row-muted")}
                    key={item.serial || item.index}
                  >
                    <div className="macro-row-index">
                      <span className="drag-handle" title="可用移动按钮调整顺序">
                        <GripVertical size={16} />
                      </span>
                      <strong>{item.index}.</strong>
                    </div>
                    <input
                      value={item.remark}
                      placeholder="宏名称"
                      onChange={(event) => patchLocalItem(table.index, item.index, "remark", event.target.value)}
                      onBlur={(event) => updateItem(table.index, item.index, "remark", event.target.value)}
                    />
                    <button
                      className="trigger-editor-button"
                      title={table.isTimingTable ? "编辑定时配置" : table.isStringTable ? "编辑字串触发" : "编辑触发键"}
                      onClick={() => runAction("openTriggerEditor", { tableIndex: table.index, itemIndex: item.index })}
                      type="button"
                    >
                      {item.trigger || "编辑"}
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
                      {triggerTypeLabels.map((label, index) => (
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
                      title={item.macro || "编辑宏"}
                      type="button"
                    >
                      <SquarePen size={14} />
                      编辑
                    </button>
                    <div className="move-buttons">
                      <button
                        disabled={item.index <= 1}
                        onClick={() => runAction("moveItem", { tableIndex: table.index, itemIndex: item.index, direction: -1 })}
                        title="上移"
                        type="button"
                      >
                        <ArrowUp size={14} />
                      </button>
                      <button
                        disabled={item.index >= itemCount}
                        onClick={() => runAction("moveItem", { tableIndex: table.index, itemIndex: item.index, direction: 1 })}
                        title="下移"
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
                      禁用
                    </label>
                    <button
                      className="danger"
                      onClick={() =>
                        confirmAction("确认删除当前宏？", "deleteItem", {
                          tableIndex: table.index,
                          itemIndex: item.index
                        })
                      }
                      type="button"
                    >
                      <Trash2 size={14} />
                      删除
                    </button>
                  </div>
                ))}
              </div>
            )}

            {fold.collapsed && <div className="module-collapsed-note">模块 {fold.index} 已折叠，点击右侧箭头展开。</div>}
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
        设置
      </summary>
      <div className="macro-settings-panel">
        <label>
          <span>模式</span>
          <select
            value={item.mode}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalItem(tableIndex, item.index, "mode", value);
              updateItem(tableIndex, item.index, "mode", value);
            }}
          >
            {modeLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>时长</span>
          <input
            type="number"
            min={0}
            value={item.holdTime}
            onChange={(event) => patchLocalItem(tableIndex, item.index, "holdTime", Number(event.target.value))}
            onBlur={(event) => updateItem(tableIndex, item.index, "holdTime", Number(event.target.value))}
          />
        </label>
        <label>
          <span>开始音</span>
          <select
            value={item.startTipSound}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalItem(tableIndex, item.index, "startTipSound", value);
              updateItem(tableIndex, item.index, "startTipSound", value);
            }}
          >
            {startTipLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>结束音</span>
          <select
            value={item.endTipSound}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalItem(tableIndex, item.index, "endTipSound", value);
              updateItem(tableIndex, item.index, "endTipSound", value);
            }}
          >
            {endTipLabels.map((label, index) => (
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
  const toolInfoRows = [
    ["屏幕坐标", tools.mousePos],
    ["窗口坐标", tools.mouseWinPos],
    ["窗口标题", tools.processTitle],
    ["进程名", tools.processName],
    ["窗口类", tools.processClass],
    ["PID", tools.processPid],
    ["句柄", tools.processId],
    ["位置颜色", tools.color]
  ];

  return (
    <section className="panel-grid tool-layout">
      <div className="section-block">
        <h2>工具热键</h2>
        <HotkeyField label="鼠标信息" value={tools.toolCheckHotKey} target="toolCheckHotKey" onLocal={(value) => patchLocalTools("toolCheckHotKey", value)} onCommit={(value) => updateTool("toolCheckHotKey", value)} runAction={runAction} />
        <HotkeyField label="指令录制" value={tools.toolRecordMacroHotKey} target="toolRecordMacroHotKey" onLocal={(value) => patchLocalTools("toolRecordMacroHotKey", value)} onCommit={(value) => updateTool("toolRecordMacroHotKey", value)} runAction={runAction} />
        <HotkeyField label="截图识别" value={tools.toolTextFilterHotKey} target="toolTextFilterHotKey" onLocal={(value) => patchLocalTools("toolTextFilterHotKey", value)} onCommit={(value) => updateTool("toolTextFilterHotKey", value)} runAction={runAction} />
        <HotkeyField label="截图" value={tools.screenShotHotKey} target="screenShotHotKey" onLocal={(value) => patchLocalTools("screenShotHotKey", value)} onCommit={(value) => updateTool("screenShotHotKey", value)} runAction={runAction} />
        <HotkeyField label="自由粘贴" value={tools.freePasteHotKey} target="freePasteHotKey" onLocal={(value) => patchLocalTools("freePasteHotKey", value)} onCommit={(value) => updateTool("freePasteHotKey", value)} runAction={runAction} />
      </div>

      <div className="section-block">
        <h2>工具窗口</h2>
        <div className="button-row">
          <button onClick={() => runAction("openVarMonitor")} type="button">
            <Play size={16} />
            变量监视器
          </button>
          <button onClick={() => runAction("openFreePaste")} type="button">
            <Clipboard size={16} />
            自由粘贴
          </button>
          <button onClick={() => runAction("openToolRecordSetting")} type="button">
            <Settings size={16} />
            录制选项
          </button>
          <button onClick={() => runAction("editCmdTip")} type="button">
            <SquarePen size={16} />
            指令显示
          </button>
        </div>
      </div>

      <div className="section-block span-2">
        <h2>鼠标信息</h2>
        <div className="button-row">
          <button className={classNames(tools.isToolCheck && "primary")} onClick={() => runAction("toggleToolCheck")} type="button">
            <MousePointer2 size={16} />
            {tools.isToolCheck ? "停止检测" : "开始检测"}
          </button>
          <label className="check-row block inline-check">
            <input
              type="checkbox"
              checked={tools.alwaysOnTop}
              onChange={(event) => {
                patchLocalTools("alwaysOnTop", event.target.checked);
                updateTool("alwaysOnTop", event.target.checked);
              }}
            />
            窗口置顶
          </label>
        </div>
        <div className="info-grid">
          {toolInfoRows.map(([label, value]) => (
            <div className="info-item" key={label}>
              <span>{label}</span>
              <strong title={value}>{value || "-"}</strong>
            </div>
          ))}
        </div>
      </div>

      <div className="section-block span-2">
        <h2>文本识别与录制输出</h2>
        <Field label="识别模型">
          <select
            value={tools.ocrType}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalTools("ocrType", value);
              updateTool("ocrType", value);
            }}
          >
            {ocrLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </Field>
        <div className="button-row">
          <button onClick={() => runAction("toolTextFilterScreenShot")} type="button">
            <Clipboard size={16} />
            截图提取文本
          </button>
          <button onClick={() => runAction("toolTextFilterSelectImage")} type="button">
            <ImageIcon size={16} />
            从图片提取
          </button>
          <button className="danger" onClick={() => runAction("clearToolText")} type="button">
            <Eraser size={16} />
            清空内容
          </button>
          <button className={classNames(tools.isToolRecord && "primary")} onClick={() => runAction("toggleToolRecord")} type="button">
            {tools.isToolRecord ? <Pause size={16} /> : <Play size={16} />}
            {tools.isToolRecord ? "停止录制" : "开始录制"}
          </button>
        </div>
        <textarea className="tool-output" readOnly value={tools.toolText} />
      </div>
    </section>
  );
}

function SettingsPanel({
  state,
  settings,
  patchLocalSettings,
  updateSetting,
  runAction
}: {
  state: RmtState;
  settings: RmtSettings;
  patchLocalSettings: (field: keyof RmtSettings, value: unknown) => void;
  updateSetting: (field: keyof RmtSettings, value: unknown) => void;
  runAction: RunAction;
}) {
  return (
    <section className="panel-grid">
      <div className="section-block">
        <h2>快捷键</h2>
        <HotkeyField label="休眠" value={settings.suspendHotkey} target="suspendHotkey" onLocal={(value) => patchLocalSettings("suspendHotkey", value)} onCommit={(value) => updateSetting("suspendHotkey", value)} runAction={runAction} />
        <HotkeyField label="暂停" value={settings.pauseHotkey} target="pauseHotkey" onLocal={(value) => patchLocalSettings("pauseHotkey", value)} onCommit={(value) => updateSetting("pauseHotkey", value)} runAction={runAction} />
        <HotkeyField label="终止所有宏" value={settings.killMacroHotkey} target="killMacroHotkey" onLocal={(value) => patchLocalSettings("killMacroHotkey", value)} onCommit={(value) => updateSetting("killMacroHotkey", value)} runAction={runAction} />
      </div>

      <div className="section-block">
        <h2>执行参数</h2>
        <Field label="按住时间浮动">
          <TextInput value={settings.holdFloat} onLocal={(value) => patchLocalSettings("holdFloat", value)} onCommit={(value) => updateSetting("holdFloat", value)} />
        </Field>
        <Field label="每次间隔浮动">
          <TextInput value={settings.preIntervalFloat} onLocal={(value) => patchLocalSettings("preIntervalFloat", value)} onCommit={(value) => updateSetting("preIntervalFloat", value)} />
        </Field>
        <Field label="间隔指令浮动">
          <TextInput value={settings.intervalFloat} onLocal={(value) => patchLocalSettings("intervalFloat", value)} onCommit={(value) => updateSetting("intervalFloat", value)} />
        </Field>
        <Field label="坐标 X 浮动">
          <TextInput value={settings.coordXFloat} onLocal={(value) => patchLocalSettings("coordXFloat", value)} onCommit={(value) => updateSetting("coordXFloat", value)} />
        </Field>
        <Field label="坐标 Y 浮动">
          <TextInput value={settings.coordYFloat} onLocal={(value) => patchLocalSettings("coordYFloat", value)} onCommit={(value) => updateSetting("coordYFloat", value)} />
        </Field>
        <Field label="多线程数">
          <TextInput value={settings.mutiThreadNum} onLocal={(value) => patchLocalSettings("mutiThreadNum", value)} onCommit={(value) => updateSetting("mutiThreadNum", value)} />
        </Field>
      </div>

      <div className="section-block">
        <h2>界面与开关</h2>
        <label className="check-row block">
          <input
            type="checkbox"
            checked={settings.bootStart}
            onChange={(event) => {
              patchLocalSettings("bootStart", event.target.checked);
              updateSetting("bootStart", event.target.checked);
            }}
          />
          开机自启
        </label>
        <label className="check-row block">
          <input
            type="checkbox"
            checked={settings.cmdTip}
            onChange={(event) => {
              patchLocalSettings("cmdTip", event.target.checked);
              updateSetting("cmdTip", event.target.checked);
            }}
          />
          指令显示
        </label>
        <label className="check-row block">
          <input
            type="checkbox"
            checked={settings.noVariableTip}
            onChange={(event) => {
              patchLocalSettings("noVariableTip", event.target.checked);
              updateSetting("noVariableTip", event.target.checked);
            }}
          />
          无变量提醒
        </label>
        <label className="check-row block">
          <input
            type="checkbox"
            checked={settings.fixedMenuWheel}
            onChange={(event) => {
              patchLocalSettings("fixedMenuWheel", event.target.checked);
              updateSetting("fixedMenuWheel", event.target.checked);
            }}
          />
          菜单轮位置固定
        </label>
        <label className="check-row block">
          <input
            type="checkbox"
            checked={settings.showSplitLine}
            onChange={(event) => {
              patchLocalSettings("showSplitLine", event.target.checked);
              updateSetting("showSplitLine", event.target.checked);
            }}
          />
          分割线
        </label>

        <Field label="语言">
          <select
            value={settings.lang}
            onChange={(event) => {
              patchLocalSettings("lang", event.target.value);
              updateSetting("lang", event.target.value);
            }}
          >
            {settings.langOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </Field>
        <Field label="字体">
          <select
            value={settings.fontType}
            onChange={(event) => {
              patchLocalSettings("fontType", event.target.value);
              updateSetting("fontType", event.target.value);
            }}
          >
            {settings.fontOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </Field>
        <Field label="截图方式">
          <select
            value={settings.screenShotType}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalSettings("screenShotType", value);
              updateSetting("screenShotType", value);
            }}
          >
            {screenshotLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="按下时按下">
          <select
            value={settings.keyDownDownType}
            onChange={(event) => {
              const value = Number(event.target.value);
              patchLocalSettings("keyDownDownType", value);
              updateSetting("keyDownDownType", value);
            }}
          >
            {keyDownLabels.map((label, index) => (
              <option key={label} value={index + 1}>
                {label}
              </option>
            ))}
          </select>
        </Field>
        <button onClick={() => runAction("keyDownHelp")} type="button">
          <HelpCircle size={16} />
          说明
        </button>
        <button onClick={() => runAction("openSettingManager")} type="button">
          <Settings size={16} />
          配置管理
        </button>
      </div>

      <div className="section-block diagnostics-block">
        <h2>诊断</h2>
        <div className="info-grid">
          <div className="info-item">
            <span>版本</span>
            <strong>{state.version}</strong>
          </div>
          <div className="info-item">
            <span>配置</span>
            <strong title={state.currentSettingName}>{state.currentSettingName}</strong>
          </div>
          <div className="info-item">
            <span>运行中</span>
            <strong>{state.macroRunningCount}</strong>
          </div>
          <div className="info-item">
            <span>累计执行</span>
            <strong>{state.macroTotalCount}</strong>
          </div>
        </div>
        <div className="button-row diagnostics-actions">
          <button onClick={() => runAction("copyDiagnostics")} type="button">
            <Clipboard size={16} />
            复制诊断信息
          </button>
        </div>
      </div>
    </section>
  );
}

function HelpPanel({ runAction }: { runAction: RunAction }) {
  const links: Array<{ label: string; action: "openHelp" } | { label: string; action: "openUrl"; url: string }> = [
    { label: "快速上手/指令手册", action: "openHelp" },
    { label: "版本更新视频", action: "openUrl", url: "https://www.bilibili.com/video/BV1oWVRzaEzk" },
    { label: "配置共享仓库", action: "openUrl", url: "https://zclucas.github.io/RMT-Setting/" },
    { label: "GitHub", action: "openUrl", url: "https://github.com/zclucas/RMT" },
    { label: "Gitee", action: "openUrl", url: "https://gitee.com/fateman/RMT" },
    { label: "GitHub 讨论", action: "openUrl", url: "https://github.com/zclucas/RMT/discussions" },
    { label: "QQ群", action: "openUrl", url: "https://qm.qq.com/q/DgpDumEPzq" },
    { label: "QQ频道", action: "openUrl", url: "https://pd.qq.com/s/5wyjvj7zw" },
    { label: "Discord", action: "openUrl", url: "https://discord.gg/m8ewvgtzat" },
    { label: "Bug 文档", action: "openUrl", url: "https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj" },
    { label: "需求文档", action: "openUrl", url: "https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo" },
    { label: "使用备注", action: "openUrl", url: "https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2" }
  ];

  return (
    <section className="section-block readable">
      <h2>免责声明</h2>
      <p>本软件按原样提供，使用者需要自行承担使用、修改或分发带来的风险。</p>
      <p>请勿将本软件用于违法用途，包括但不限于游戏作弊、未经授权的系统访问或数据篡改。</p>
      <div className="link-list">
        {links.map((link) => (
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
      <h2>打赏作者</h2>
      <p>若梦兔（RMT）是一款完全免费的开源软件，始终陪在你身边。</p>
      <p>至今已为您执行 {totalText} 次宏指令。诚邀本月打赏成为若梦兔的“守护者”，一起让若梦兔走得更远。</p>
      <div className="qr-grid">
        <figure>
          <img alt="微信打赏二维码" src="/Images/Soft/WeiXin.png" />
          <figcaption>微信打赏</figcaption>
        </figure>
        <figure>
          <img alt="支付宝打赏二维码" src="/Images/Soft/ZhiFuBao.png" />
          <figcaption>支付宝打赏</figcaption>
        </figure>
      </div>
      <p>当然，如果你暂时不方便，分享给朋友也是很棒的支持。开发不易，感谢你的每一份温暖。</p>
    </section>
  );
}

function ThanksPanel({ runAction }: { runAction: RunAction }) {
  const developers = [
    ["GushuLily", "https://github.com/GushuLily"],
    ["张正波", "https://gitee.com/bogezzb"],
    ["yun", "https://github.com/yunkuangao"],
    ["boxstudy", "https://github.com/boxstudy"],
    ["sovaedv776", "https://github.com/sovaedv776"]
  ];
  const projects = [
    ["OpenCV", "https://github.com/opencv/opencv"],
    ["ahk2_lib", "https://github.com/thqby/ahk2_lib"],
    ["RapidOCR", "https://github.com/RapidAI/RapidOCR"],
    ["AHK-CvJoyInterface", "https://github.com/evilC/AHK-CvJoyInterface"],
    ["IbInputSimulator", "https://github.com/Chaoses-Ib/IbInputSimulator"],
    ["AHK-ViGEm-Bus", "https://github.com/evilC/AHK-ViGEm-Bus"],
    ["AHK-ViGEm-Bus-v2", "https://github.com/CesarHlp1/AHK-ViGEm-Bus-v2.ahk"],
    ["ScreenCapture", "https://github.com/xland/ScreenCapture"]
  ];
  const community = ["AYu", "万年置伞", "别说*不下啦", "仰望", "话听", "yun"];

  return (
    <section className="section-block thanks-panel">
      <h2>特别感谢</h2>
      <div className="thanks-group">
        <h3>项目贡献者</h3>
        <div className="tag-list">
          {developers.map(([label, url]) => (
            <button className="link-chip" key={label} onClick={() => runAction("openUrl", { url })} type="button">
              {label}
            </button>
          ))}
        </div>
      </div>
      <div className="thanks-group">
        <h3>开源项目</h3>
        <div className="tag-list">
          {projects.map(([label, url]) => (
            <button className="link-chip" key={label} onClick={() => runAction("openUrl", { url })} type="button">
              {label}
            </button>
          ))}
        </div>
      </div>
      <div className="thanks-group">
        <h3>社区支持</h3>
        <div className="tag-list muted-tags">
          {community.map((name) => (
            <span key={name}>{name}</span>
          ))}
        </div>
      </div>
      <p>感谢所有打赏支持若梦兔的守护者，以及参与完善 Bug 和需求文档的朋友。</p>
      <p>感谢每一位陪伴项目成长的粉丝和群友们。每一次鼓励、每一条建议，都是这个项目继续迭代的动力。</p>
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="field-row">
      <span>{label}</span>
      {children}
    </label>
  );
}

function HotkeyField({
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
    <Field label={label}>
      <div className="hotkey-edit-cell">
        <TextInput value={value} onLocal={onLocal} onCommit={onCommit} />
        <button className="icon-button" title="打开快捷方式编辑器" onClick={() => runAction("openHotkeyEditor", { target })} type="button">
          <SquarePen size={15} />
        </button>
      </div>
    </Field>
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
