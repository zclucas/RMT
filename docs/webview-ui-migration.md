# WebView UI migration plan

## Current checkpoint

- Branch: `codex-rmt-webview-ui-migration`
- State: the main `RMT.ahk` window is hosted by `WebViewToo` and loads the React/TypeScript app from `WebViewApp/dist`.
- Migrated areas: macro table parity, tools/settings parity, help, reward, and thanks pages.
- Verified bridge: React can call `window.ahk.RmtAction({ type: "getState" })` and receive version, tabs, settings, and tools state.

## Ownership boundary

AHK remains the owner of:

- Macro execution, hotkeys, timers, worker processes, OCR, screenshots, file IO, plugin calls.
- Reading/writing `Setting` and macro data files.
- Legacy dialogs that have not yet been migrated.
- Validation that affects runtime behavior.

React remains the owner of:

- Main window layout, tabs, tables, forms, toolbars, and interaction state.
- User input collection and display state.
- Calling AHK through `RmtAction`.
- Rendering state returned by AHK.

React must not duplicate macro execution logic. New UI behavior should be represented as a bridge action and handled by AHK.

## Migration phases

### Phase 1: Main macro table parity

Scope:

- Macro tab table rendering for all item-table tabs.
- Fold header editing: remark, front info, trigger type, trigger, hold time, forbid, collapsed state.
- Item row editing: trigger, trigger type, macro text, mode, forbid, remark, loop count, hold time, timing serial, tip sound, pause.
- Add, delete, and move item/fold actions.
- Save/reload/status refresh from existing AHK state.

Acceptance:

- `npm.cmd run build`
- `AutoHotkeyUX.exe /ErrorStdOut=UTF-8 /Validate .\RMT.ahk`
- AHK action smoke for `getState`, `updateItem`, `updateFold`, `addItem`, `deleteItem`, `toggleFold`, `save`.
- Real WebView bridge smoke returns `ok:true` with tabs/settings/tools.

### Phase 2: Settings and tools parity

Scope:

- Settings tab: hotkeys, numeric settings, toggles, dropdowns, language/font/screenshot options.
- Tools tab: mouse/window info, record toggles, OCR type, tool text buffer, tool action buttons.
- Preserve existing AHK handlers for tool operations.

Acceptance:

- Settings changes round-trip through AHK state and persist through existing save flow.
- Hotkey and runtime status changes update React without reopening the window.
- Tool status changes from hotkeys call `RmtPostState()`.

### Phase 3: Dialog migration decision

Keep in AHK until main window is stable:

- `MacroEditGui`
- `TimingGui`
- `ReplaceKeyGui`
- `EditHotkeyGui`
- `VarListenGui`
- `CMDTipGui`
- `ToolRecordSettingGui`
- `SettingMgrGui`

Candidates for later React migration:

- Macro editor detail forms that are opened often from table rows.
- Hotkey editor if bridge validation is stable.
- Configuration manager after save/load behavior is fully covered by smoke tests.

Acceptance:

- Each migrated dialog has a matching `RmtAction` set.
- AHK remains the source of truth for saved data and validation.
- Legacy dialog can be removed only after equivalent WebView flow is verified.
- Legacy cleanup ownership is tracked in `docs/legacy-gui-cleanup.md`.

### Phase 4: Packaging and release hardening

Scope:

- Ensure `WebViewApp/dist` and `Plugins/WebViewToo/Lib` are copied into release output.
- Keep release output independent from `node_modules`.
- Keep version and `history.md` updated per release.

Acceptance:

- Packaging script parses `RMT_WEBVIEW_VERSION`.
- Release folders contain `WebViewApp/dist/index.html`.
- Release smoke can open the WebView page without source files.
- Release steps are documented in `docs/release.md`.

## Current bridge actions

- State: `getState`, `setTab`
- Runtime: `toggleSuspend`, `togglePause`, `killAll`
- App/window: `save`, `reload`, `minimize`, `maximize`, `close`
- Navigation/help: `openHelp`, `openUrl`, `openVarMonitor`
- Tool/settings dialogs: `openToolRecordSetting`, `editCmdTip`, `keyDownHelp`
- Data update: `updateSetting`, `updateTool`, `updateItem`, `updateFold`, `toggleFold`
- Structure update: `addItem`, `deleteItem`, `moveItem`, `addFold`, `deleteFold`
- Editors: `openMacroEditor`

## Known risks

- Some old AHK functions still read pseudo controls such as `.Value` and `.Text`; these must remain compatible until those flows are rewritten.
- `ExecuteScriptAsync` should not be used to synchronously read JS `Promise` results. Use page-to-AHK callbacks or state-returning bridge actions.
- Complex dialogs should not be migrated before main table save/edit parity is stable.
- Console mojibake does not necessarily mean source encoding is broken, but UI strings must be visually checked inside WebView before release.

## Verification commands

```powershell
cd C:\Users\T8numen\Documents\Playground\rmt-test\RMT-Dev_WebView2
.\scripts\verify.ps1
```
