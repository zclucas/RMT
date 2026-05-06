import {
  ArrowDown,
  ArrowUp,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  ClipboardList,
  Copy,
  Eye,
  FileText,
  Gift,
  GripVertical,
  HelpCircle,
  Keyboard,
  ListTree,
  LucideIcon,
  Menu as MenuIcon,
  MousePointer2,
  Palette,
  Pause,
  Play,
  Plus,
  RefreshCw,
  Repeat2,
  Save,
  Search,
  Settings,
  SlidersHorizontal,
  Square,
  SquarePen,
  Timer,
  Trash2,
  Wrench
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import "./ui-proposals.css";

type ProposalId = "classic" | "toolbar" | "themes";
type ThemeId = "mint" | "steel" | "amber" | "forest" | "dark";

interface MacroRow {
  id: number;
  remark: string;
  trigger: string;
  type: string;
  loop: string;
  command: string;
  state: "启用" | "暂停";
}

interface MacroModule {
  id: string;
  remark: string;
  frontInfo: string;
  disabled: boolean;
  collapsed: boolean;
  rows: MacroRow[];
}

const proposals: Array<{
  id: ProposalId;
  name: string;
  shortName: string;
  note: string;
}> = [
  {
    id: "classic",
    name: "方案 A：经典页签复刻",
    shortName: "A 经典复刻",
    note: "按作者反馈回到旧版布局：固定左侧全局控制栏、顶部页签、可折叠模块区和紧凑表格。"
  },
  {
    id: "toolbar",
    name: "方案 B：经典页签 + 工具栏强化",
    shortName: "B 工具栏强化",
    note: "保留旧页签结构，把常用操作和运行状态集中到顶部工具区。"
  },
  {
    id: "themes",
    name: "方案 C：经典布局 + 多主题",
    shortName: "C 多主题",
    note: "布局贴近方案 A，重点预览多配色选择和主题切换。"
  }
];

const themes: Array<{
  id: ThemeId;
  name: string;
  swatch: string;
}> = [
  { id: "mint", name: "青绿", swatch: "#2f8f83" },
  { id: "steel", name: "蓝灰", swatch: "#3f6f98" },
  { id: "amber", name: "暖橙", swatch: "#b66b2e" },
  { id: "forest", name: "森林", swatch: "#3b7a4a" },
  { id: "dark", name: "暗色", swatch: "#1f2933" }
];

const tabItems: Array<{ name: string; icon: LucideIcon }> = [
  { name: "按键宏", icon: Keyboard },
  { name: "字串宏", icon: FileText },
  { name: "菜单宏", icon: MenuIcon },
  { name: "定时宏", icon: Timer },
  { name: "宏", icon: ListTree },
  { name: "按键替换", icon: Repeat2 },
  { name: "工具", icon: Wrench },
  { name: "设置", icon: Settings },
  { name: "帮助", icon: HelpCircle },
  { name: "打赏", icon: Gift },
  { name: "感谢", icon: CheckCircle2 }
];

const modules = [
  { name: "RMT默认初始化配置", count: 4, enabled: true },
  { name: "游戏窗口", count: 3, enabled: true },
  { name: "文本处理", count: 2, enabled: false },
  { name: "临时调试", count: 1, enabled: true }
];

const initialMacros: MacroRow[] = [
  { id: 1, remark: "取消禁用配置才能生效", trigger: "K", type: "按下", loop: "1", command: "设置 -> 编辑", state: "启用" },
  { id: 2, remark: "截图识别", trigger: "Ctrl+Q", type: "松开", loop: "1", command: "截图 -> OCR -> 输出", state: "启用" },
  { id: 3, remark: "窗口激活", trigger: "Alt+1", type: "开关", loop: "3", command: "查找窗口并前置", state: "暂停" },
  { id: 4, remark: "输入模板", trigger: "Shift+V", type: "长按", loop: "1", command: "粘贴固定文本", state: "启用" }
];

const initialMacroModules: MacroModule[] = [
  {
    id: "default",
    remark: "RMT默认初始化配置",
    frontInfo: "",
    disabled: false,
    collapsed: false,
    rows: [
      { id: 1, remark: "取消禁用配置才能生效", trigger: "k", type: "按下", loop: "1", command: "设置 -> 编辑", state: "暂停" },
      { id: 2, remark: "", trigger: "编辑", type: "按下", loop: "1", command: "设置 -> 编辑", state: "启用" }
    ]
  },
  {
    id: "module-b",
    remark: "1232",
    frontInfo: "",
    disabled: false,
    collapsed: false,
    rows: [
      { id: 3, remark: "", trigger: "编辑", type: "按下", loop: "1", command: "设置 -> 编辑", state: "启用" }
    ]
  },
  {
    id: "module-c",
    remark: "",
    frontInfo: "",
    disabled: false,
    collapsed: false,
    rows: [
      { id: 4, remark: "", trigger: "编辑", type: "按下", loop: "1", command: "设置 -> 编辑", state: "启用" }
    ]
  }
];

const settingsRows = [
  ["休眠", "F12"],
  ["暂停", "F11"],
  ["终止全部宏", "Ctrl+Esc"],
  ["截图方式", "RMT 截图"],
  ["语言", "中文"],
  ["字体", "Microsoft YaHei"]
];

function App() {
  const [activeProposal, setActiveProposal] = useState<ProposalId>(() => getInitialProposal());
  const [activeTheme, setActiveTheme] = useState<ThemeId>(() => getInitialTheme());
  const proposal = useMemo(
    () => proposals.find((item) => item.id === activeProposal) ?? proposals[0],
    [activeProposal]
  );

  useEffect(() => {
    const params = new URLSearchParams();
    params.set("proposal", activeProposal);
    if (activeProposal === "themes") {
      params.set("theme", activeTheme);
    }
    window.history.replaceState(null, "", `${window.location.pathname}?${params.toString()}`);
  }, [activeProposal, activeTheme]);

  return (
    <main className="prototype-shell" data-theme={activeProposal === "themes" ? activeTheme : "mint"}>
      <header className="prototype-header">
        <div>
          <div className="app-id">RMT UI Proposals</div>
          <h1>旧版布局方向预览</h1>
        </div>
        <div className="header-note">
          只看 UI，不接功能。重点验证：固定左侧控制栏、顶部图标页签、旧布局密度和宏排序体验。
        </div>
      </header>

      <section className="proposal-switcher" aria-label="UI 方案切换">
        {proposals.map((item) => (
          <button
            key={item.id}
            className={item.id === activeProposal ? "is-active" : ""}
            onClick={() => setActiveProposal(item.id)}
            type="button"
          >
            <span>{item.shortName}</span>
          </button>
        ))}
      </section>

      <section className="proposal-summary">
        <div>
          <h2>{proposal.name}</h2>
          <p>{proposal.note}</p>
        </div>
        {activeProposal === "themes" && (
          <div className="theme-picker" aria-label="主题选择">
            {themes.map((theme) => (
              <button
                key={theme.id}
                className={theme.id === activeTheme ? "is-selected" : ""}
                onClick={() => setActiveTheme(theme.id)}
                type="button"
              >
                <span style={{ background: theme.swatch }} />
                {theme.name}
              </button>
            ))}
          </div>
        )}
      </section>

      {activeProposal === "classic" && <ClassicProposal />}
      {activeProposal === "toolbar" && <ToolbarProposal />}
      {activeProposal === "themes" && <ThemeProposal />}
    </main>
  );
}

function getInitialProposal(): ProposalId {
  const value = new URLSearchParams(window.location.search).get("proposal");
  return proposals.some((proposal) => proposal.id === value) ? (value as ProposalId) : "classic";
}

function getInitialTheme(): ThemeId {
  const value = new URLSearchParams(window.location.search).get("theme");
  return themes.some((theme) => theme.id === value) ? (value as ThemeId) : "mint";
}

function ClassicProposal() {
  const [modules, setModules] = useState<MacroModule[]>(initialMacroModules);
  const [dragging, setDragging] = useState<{ moduleId: string; rowId: number } | null>(null);

  function toggleModule(moduleId: string) {
    setModules((current) =>
      current.map((module) => (module.id === moduleId ? { ...module, collapsed: !module.collapsed } : module))
    );
  }

  function toggleModuleDisabled(moduleId: string) {
    setModules((current) =>
      current.map((module) => (module.id === moduleId ? { ...module, disabled: !module.disabled } : module))
    );
  }

  function swapMacroRows(current: MacroModule[], sourceIndex: number, targetIndex: number) {
    const slots = getMacroSlots(current);
    if (sourceIndex < 0 || targetIndex < 0 || sourceIndex >= slots.length || targetIndex >= slots.length) {
      return current;
    }
    const source = slots[sourceIndex];
    const target = slots[targetIndex];
    const rowsByModule = new Map(current.map((module) => [module.id, [...module.rows]]));
    rowsByModule.get(source.moduleId)![source.rowIndex] = target.row;
    rowsByModule.get(target.moduleId)![target.rowIndex] = source.row;
    return current.map((module) => ({ ...module, rows: rowsByModule.get(module.id) ?? module.rows }));
  }

  function getMacroSlots(current: MacroModule[]) {
    return current.flatMap((module) =>
      module.rows.map((row, rowIndex) => ({
        moduleId: module.id,
        row,
        rowIndex
      }))
    );
  }

  function moveRow(moduleId: string, index: number, direction: -1 | 1) {
    setModules((current) => {
      const sourceIndex = getMacroSlots(current).findIndex((slot) => slot.moduleId === moduleId && slot.rowIndex === index);
      return swapMacroRows(current, sourceIndex, sourceIndex + direction);
    });
  }

  function dropRow(_moduleId: string, targetId: number) {
    if (!dragging || dragging.rowId === targetId) {
      setDragging(null);
      return;
    }
    setModules((current) => {
      const slots = getMacroSlots(current);
      return swapMacroRows(
        current,
        slots.findIndex((slot) => slot.row.id === dragging.rowId),
        slots.findIndex((slot) => slot.row.id === targetId)
      );
    });
    setDragging(null);
  }

  return (
    <RmtWindow variant="classic classic-v2">
      <div className="classic-body">
        <ClassicGlobalSidebar />
        <section className="classic-main">
          <ClassicTabs activeIndex={0} />
          <div className="classic-work-area module-list-layout">
            <div className="classic-module-stack">
              {modules.map((module, moduleIndex) => (
                <ClassicModuleSection
                  dragging={dragging}
                  key={module.id}
                  module={module}
                  moduleIndex={moduleIndex}
                  startNumber={modules.slice(0, moduleIndex).reduce((count, item) => count + item.rows.length, 0) + 1}
                  onDragStart={setDragging}
                  onDropRow={dropRow}
                  onMoveRow={moveRow}
                  onToggleDisabled={toggleModuleDisabled}
                  onToggleModule={toggleModule}
                />
              ))}
            </div>
          </div>
        </section>
      </div>
    </RmtWindow>
  );
}

function ToolbarProposal() {
  return (
    <RmtWindow variant="toolbar">
      <ClassicTabs activeIndex={0} />
      <TopCommandBar />
      <div className="toolbar-grid">
        <MacroPanel title="按键宏配置" />
        <InspectorPanel />
      </div>
      <BottomStatus />
    </RmtWindow>
  );
}

function ThemeProposal() {
  return (
    <RmtWindow variant="themes">
      <ClassicTabs activeIndex={0} />
      <LegacyHeader showThemeLabel />
      <div className="theme-grid">
        <MacroPanel title="按键宏配置" compact />
        <SettingsPreview />
      </div>
      <BottomStatus />
    </RmtWindow>
  );
}

function RmtWindow({ children, variant }: { children: React.ReactNode; variant: string }) {
  return (
    <section className={`rmt-window ${variant}`}>
      <div className="window-titlebar">
        <div className="window-brand">
          <span className="brand-mark">RMT</span>
          <strong>RMTv2.0</strong>
        </div>
        <div className="window-controls" aria-hidden="true">
          <span />
          <span />
          <span className="close" />
        </div>
      </div>
      {children}
    </section>
  );
}

function ClassicTabs({ activeIndex }: { activeIndex: number }) {
  return (
    <nav className="classic-tabs" aria-label="旧版页签">
      {tabItems.map((tab, index) => {
        const Icon = tab.icon;
        return (
          <button className={index === activeIndex ? "active" : ""} key={tab.name} type="button">
            <Icon size={16} />
            <span>{tab.name}</span>
          </button>
        );
      })}
    </nav>
  );
}

function ClassicGlobalSidebar() {
  return (
    <aside className="classic-global-sidebar">
      <div className="sidebar-section">
        <span className="side-label">当前配置</span>
        <button className="config-select-button" type="button">
          RMT默认配置
        </button>
        <button className="side-button green" type="button">
          <Settings size={15} />
          配置管理
        </button>
      </div>

      <div className="sidebar-section global-actions">
        <span className="side-label">全局操作</span>
        <button className="side-card" type="button">
          <span>
            <Pause size={15} />
            休眠
          </span>
          <kbd>Alt+P</kbd>
        </button>
        <button className="side-card" type="button">
          <span>
            <Square size={15} />
            暂停
          </span>
          <kbd>Alt+I</kbd>
        </button>
        <button className="side-button red" type="button">
          <Square size={15} />
          终止宏
        </button>
        <kbd className="shortcut-line">Alt+K</kbd>
        <button className="side-button gray" type="button">
          <RefreshCw size={15} />
          重载
        </button>
        <button className="side-button blue" type="button">
          <HelpCircle size={15} />
          帮助
        </button>
      </div>

      <div className="sidebar-save">
        <button className="side-button green" type="button">
          <Save size={15} />
          保存
        </button>
      </div>
    </aside>
  );
}

function ClassicModuleSection({
  dragging,
  module,
  moduleIndex,
  startNumber,
  onDragStart,
  onDropRow,
  onMoveRow,
  onToggleDisabled,
  onToggleModule
}: {
  dragging: { moduleId: string; rowId: number } | null;
  module: MacroModule;
  moduleIndex: number;
  startNumber: number;
  onDragStart: (dragging: { moduleId: string; rowId: number } | null) => void;
  onDropRow: (moduleId: string, targetId: number) => void;
  onMoveRow: (moduleId: string, index: number, direction: -1 | 1) => void;
  onToggleDisabled: (moduleId: string) => void;
  onToggleModule: (moduleId: string) => void;
}) {
  return (
    <section className={module.disabled ? "macro-module-section is-disabled" : "macro-module-section"}>
      <div className="module-config-row">
        <label className="module-field remark-field">
          <span>备注:</span>
          <input readOnly value={module.remark} />
        </label>
        <label className="module-field front-field">
          <span>前台:</span>
          <input readOnly value={module.frontInfo} />
        </label>
        <button type="button">
          <SquarePen size={15} />
          编辑
        </button>
        <button type="button">
          <Plus size={15} />
          新增宏
        </button>
        <button type="button">
          <Plus size={15} />
          新增模块
        </button>
        <button type="button">
          <Trash2 size={15} />
          删除模块
        </button>
        <label className="inline-check module-disabled">
          <input checked={module.disabled} onChange={() => onToggleDisabled(module.id)} type="checkbox" />
          禁用
        </label>
        <button className="module-expand-button" onClick={() => onToggleModule(module.id)} title="折叠/展开模块" type="button">
          {module.collapsed ? <ChevronRight size={18} /> : <ChevronDown size={18} />}
        </button>
      </div>

      {!module.collapsed && (
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
          {module.rows.map((row, rowIndex) => (
            <div
              className={dragging?.moduleId === module.id && dragging.rowId === row.id ? "module-macro-row is-dragging" : "module-macro-row"}
              draggable
              key={row.id}
              onDragEnd={() => onDragStart(null)}
              onDragOver={(event) => event.preventDefault()}
              onDragStart={() => onDragStart({ moduleId: module.id, rowId: row.id })}
              onDrop={() => onDropRow(module.id, row.id)}
            >
              <div className="macro-row-index">
                <span className="drag-handle" title="拖住滑动排序">
                  <GripVertical size={16} />
                </span>
                <strong>{startNumber + rowIndex}.</strong>
              </div>
              <input readOnly value={row.remark} />
              <button className="trigger-editor-button" type="button">
                {row.trigger}
              </button>
              <button className="select-cell" type="button">
                {row.type}
                <ChevronDown size={14} />
              </button>
              <button className="select-cell" type="button">
                {row.loop}
                <ChevronDown size={14} />
              </button>
              <button type="button">
                <SlidersHorizontal size={14} />
                设置
              </button>
              <button type="button">
                <SquarePen size={14} />
                编辑
              </button>
              <div className="move-buttons">
                <button
                  onClick={() => onMoveRow(module.id, rowIndex, -1)}
                  title="上移"
                  type="button"
                >
                  <ArrowUp size={14} />
                </button>
                <button
                  onClick={() => onMoveRow(module.id, rowIndex, 1)}
                  title="下移"
                  type="button"
                >
                  <ArrowDown size={14} />
                </button>
              </div>
              <label className="inline-check row-disabled">
                <input checked={module.disabled || row.state === "暂停"} readOnly type="checkbox" />
                禁用
              </label>
              <button className="danger" type="button">
                <Trash2 size={14} />
                删除
              </button>
            </div>
          ))}
        </div>
      )}
      {module.collapsed && <div className="module-collapsed-note">模块 {moduleIndex + 1} 已折叠，点击右侧箭头展开。</div>}
    </section>
  );
}

function ClassicConfigBar({
  moduleCollapsed,
  onToggleModule
}: {
  moduleCollapsed: boolean;
  onToggleModule: () => void;
}) {
  return (
    <div className="classic-configbar">
      <button className="module-toggle" onClick={onToggleModule} type="button">
        {moduleCollapsed ? <ChevronRight size={16} /> : <ChevronDown size={16} />}
        {moduleCollapsed ? "展开模块区" : "折叠模块区"}
      </button>
      <button className="select-like wide-select" type="button">
        RMT默认初始化配置
      </button>
      <label className="inline-input">
        前台:
        <input readOnly value="前台窗口" />
      </label>
      <button type="button">
        <SquarePen size={15} />
        编辑
      </button>
      <div className="configbar-spacer" />
      <button type="button">
        <Plus size={15} />
        新增宏
      </button>
      <button type="button">
        <Plus size={15} />
        新增模块
      </button>
      <button type="button">
        <Trash2 size={15} />
        删除模块
      </button>
      <label className="inline-check">
        <input readOnly type="checkbox" />
        禁用
      </label>
    </div>
  );
}

function ModulePanel({ collapsed = false, onToggle }: { collapsed?: boolean; onToggle?: () => void }) {
  if (collapsed) {
    return (
      <section className="panel module-panel collapsed">
        <button className="module-collapsed-button" onClick={onToggle} type="button">
          <ChevronRight size={16} />
          <span>模块</span>
        </button>
      </section>
    );
  }

  return (
    <section className="panel module-panel">
      <div className="panel-head">
        <h3>模块区</h3>
        <div className="panel-actions">
          <button className="icon-only" onClick={onToggle} title="折叠模块区" type="button">
            <ChevronDown size={15} />
          </button>
          <IconButton icon={<Plus size={14} />} label="新增" />
        </div>
      </div>
      <div className="module-list-preview">
        {modules.map((module, index) => (
          <button className={index === 0 ? "module-row active" : "module-row"} key={module.name} type="button">
            <ListTree size={15} />
            <span>{module.name}</span>
            <em>{module.count}</em>
            {!module.enabled && <small>禁用</small>}
          </button>
        ))}
      </div>
    </section>
  );
}

function ClassicMacroTable({
  draggingId,
  rows,
  onDragStart,
  onDropRow,
  onMoveRow,
  onToggleModule
}: {
  draggingId: number | null;
  rows: MacroRow[];
  onDragStart: (id: number | null) => void;
  onDropRow: (id: number) => void;
  onMoveRow: (index: number, direction: -1 | 1) => void;
  onToggleModule: () => void;
}) {
  return (
    <section className="panel classic-macro-panel">
      <div className="classic-table-head">
        <div>
          <h3>按键宏配置</h3>
          <span>支持按钮上下移动，也可以拖住排序柄滑动调换顺序。</span>
        </div>
        <button onClick={onToggleModule} type="button">
          <ListTree size={15} />
          模块区
        </button>
      </div>
      <div className="table-wrap">
        <table className="macro-table classic-macro-table">
          <thead>
            <tr>
              <th>排序</th>
              <th>序号</th>
              <th>宏名称</th>
              <th>触发编辑器</th>
              <th>触发类型</th>
              <th>循环次数</th>
              <th>宏设置</th>
              <th>宏编辑器</th>
              <th>移动</th>
              <th>状态</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <tr
                className={draggingId === row.id ? "is-dragging" : ""}
                draggable
                key={row.id}
                onDragEnd={() => onDragStart(null)}
                onDragOver={(event) => event.preventDefault()}
                onDragStart={() => onDragStart(row.id)}
                onDrop={() => onDropRow(row.id)}
              >
                <td>
                  <span className="drag-handle" title="拖住滑动排序">
                    <GripVertical size={16} />
                  </span>
                </td>
                <td>{index + 1}.</td>
                <td>
                  <input readOnly value={row.remark} />
                </td>
                <td>
                  <input readOnly value={row.trigger} />
                </td>
                <td>
                  <button className="select-cell" type="button">
                    {row.type}
                    <ChevronDown size={14} />
                  </button>
                </td>
                <td>
                  <input readOnly value={row.loop} />
                </td>
                <td>
                  <button type="button">
                    <SlidersHorizontal size={14} />
                    设置
                  </button>
                </td>
                <td>
                  <button type="button">
                    <SquarePen size={14} />
                    编辑
                  </button>
                </td>
                <td>
                  <div className="move-buttons">
                    <button disabled={index === 0} onClick={() => onMoveRow(index, -1)} title="上移" type="button">
                      <ArrowUp size={14} />
                    </button>
                    <button disabled={index === rows.length - 1} onClick={() => onMoveRow(index, 1)} title="下移" type="button">
                      <ArrowDown size={14} />
                    </button>
                  </div>
                </td>
                <td>
                  <span className={row.state === "启用" ? "state enabled" : "state paused"}>{row.state}</span>
                </td>
                <td>
                  <button className="danger" type="button">
                    <Trash2 size={14} />
                    删除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function LegacyHeader({ showThemeLabel = false }: { showThemeLabel?: boolean }) {
  return (
    <div className="legacy-header">
      <div className="field-inline wide">
        <span>配置</span>
        <button className="select-like" type="button">
          默认配置 <ChevronDown size={14} />
        </button>
      </div>
      <StatusButton icon={<Pause size={15} />} label="休眠" value="关闭" />
      <StatusButton icon={<Square size={15} />} label="暂停" value="关闭" />
      <IconButton icon={<Save size={15} />} label="保存" primary />
      <IconButton icon={<RefreshCw size={15} />} label="重载" />
      <IconButton icon={<HelpCircle size={15} />} label="帮助" />
      {showThemeLabel && (
        <div className="theme-current">
          <Palette size={15} />
          当前主题可切换
        </div>
      )}
    </div>
  );
}

function TopCommandBar() {
  return (
    <div className="top-commandbar">
      <div className="command-group">
        <IconButton icon={<Save size={15} />} label="保存配置" primary />
        <IconButton icon={<Play size={15} />} label="运行宏" />
        <IconButton icon={<Square size={15} />} label="终止全部" danger />
      </div>
      <div className="command-group">
        <IconButton icon={<Plus size={15} />} label="新增模块" />
        <IconButton icon={<SquarePen size={15} />} label="编辑宏" />
        <IconButton icon={<Copy size={15} />} label="复制" />
        <IconButton icon={<Trash2 size={15} />} label="删除" danger />
      </div>
      <div className="command-spacer" />
      <div className="runtime-box">
        <span className="runtime-dot" />
        运行中 0
      </div>
    </div>
  );
}

function MacroPanel({ title, compact = false }: { title: string; compact?: boolean }) {
  return (
    <section className={compact ? "panel macro-panel compact" : "panel macro-panel"}>
      <div className="panel-head">
        <h3>{title}</h3>
        <div className="panel-actions">
          <IconButton icon={<Plus size={14} />} label="新增宏" />
          <IconButton icon={<SquarePen size={14} />} label="宏编辑器" />
          <IconButton icon={<Search size={14} />} label="筛选" />
        </div>
      </div>
      <div className="table-wrap">
        <table className="macro-table">
          <thead>
            <tr>
              <th>序号</th>
              <th>备注</th>
              <th>触发</th>
              <th>类型</th>
              <th>循环</th>
              <th>宏指令</th>
              <th>状态</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {initialMacros.map((macro) => (
              <tr key={macro.id}>
                <td>{macro.id}</td>
                <td>{macro.remark}</td>
                <td>
                  <code>{macro.trigger}</code>
                </td>
                <td>{macro.type}</td>
                <td>{macro.loop}</td>
                <td className="command-cell">{macro.command}</td>
                <td>
                  <span className={macro.state === "启用" ? "state enabled" : "state paused"}>{macro.state}</span>
                </td>
                <td>
                  <div className="mini-actions">
                    <button title="编辑" type="button">
                      <SquarePen size={14} />
                    </button>
                    <button title="复制" type="button">
                      <Copy size={14} />
                    </button>
                    <button title="删除" type="button">
                      <Trash2 size={14} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function InspectorPanel() {
  return (
    <aside className="panel inspector-panel">
      <div className="panel-head">
        <h3>当前宏</h3>
      </div>
      <div className="inspector-block">
        <label>
          备注
          <input readOnly value="连点左键" />
        </label>
        <label>
          触发键
          <input readOnly value="F6" />
        </label>
        <label>
          宏指令
          <textarea readOnly value={"鼠标左键 20ms\n间隔 35ms\n重复 1 次"} />
        </label>
      </div>
      <div className="quick-stats">
        <Stat label="模块" value="4" />
        <Stat label="宏" value="10" />
        <Stat label="运行中" value="0" />
        <Stat label="已执行" value="1,286" />
      </div>
    </aside>
  );
}

function SettingsPreview() {
  return (
    <aside className="panel settings-preview">
      <div className="panel-head">
        <h3>设置预览</h3>
        <IconButton icon={<Settings size={14} />} label="设置" />
      </div>
      <div className="settings-list">
        {settingsRows.map(([label, value]) => (
          <div className="settings-row" key={label}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>
      <div className="toggle-preview">
        <label>
          <input checked readOnly type="checkbox" />
          指令显示
        </label>
        <label>
          <input readOnly type="checkbox" />
          开机自启
        </label>
        <label>
          <input checked readOnly type="checkbox" />
          分割线
        </label>
      </div>
    </aside>
  );
}

function BottomStatus() {
  return (
    <footer className="bottom-status">
      <span>
        <CheckCircle2 size={14} />
        WebView UI 原型
      </span>
      <span>
        <ClipboardList size={14} />
        宏总数 10
      </span>
      <span>
        <MousePointer2 size={14} />
        鼠标检测关闭
      </span>
      <span>
        <Eye size={14} />
        当前只展示静态界面
      </span>
    </footer>
  );
}

function StatusButton({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <button className="status-button" type="button">
      {icon}
      <span>{label}</span>
      <strong>{value}</strong>
    </button>
  );
}

function IconButton({
  icon,
  label,
  primary = false,
  danger = false
}: {
  icon: React.ReactNode;
  label: string;
  primary?: boolean;
  danger?: boolean;
}) {
  return (
    <button className={`${primary ? "primary " : ""}${danger ? "danger" : ""}`} type="button">
      {icon}
      {label}
    </button>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="stat">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
