# WebView Bridge Contract

The WebView bridge is the boundary between the React UI and the AutoHotkey runtime.

## Ownership

AHK owns:

- Reading and writing settings and macro data.
- Macro execution, hotkeys, timing, workers, OCR, screenshots, plugins, and file IO.
- Runtime validation that can affect saved data or macro behavior.
- Legacy dialogs that have not been migrated.

React owns:

- Main window layout, tabs, tables, toolbars, and form controls.
- Local UI state needed for editing and display.
- Calling AHK through `window.ahk.RmtAction`.
- Rendering the state returned by AHK.

React must not duplicate macro execution logic or write project settings directly.

## Data Flow

1. React calls `RmtAction({ type, payload })`.
2. `Main/UIUtil.ahk` handles the action in `RmtWebAction()`.
3. AHK updates runtime or saved state.
4. AHK returns `RmtOk()`/`RmtError()` with the latest `RmtBuildState()` result.
5. React re-renders from the returned state.

For external AHK changes, call `RmtPostState()` so the WebView receives a fresh state snapshot.

## State Contract

The source of truth for the frontend shape is `WebViewApp/src/types.ts`.

The source of truth for state construction is `RmtBuildState()` in `Main/UIUtil.ahk`.

The frontend action contract is the `RmtAction` union in `WebViewApp/src/types.ts`.

When adding a state field:

1. Add it to `RmtBuildState()` or a nested builder such as `RmtBuildSettings()`/`RmtBuildTools()`.
2. Add it to `WebViewApp/src/types.ts`.
3. Add a fallback value in `WebViewApp/src/fallbackState.ts`.
4. Render or consume it in React.
5. Run `npm.cmd run build` from `WebViewApp`.
6. Run AutoHotkey validation on `RMT.ahk`.

Keep field names stable once released. If a rename is unavoidable, support the old field until config and UI migration are covered.

## Action Contract

Current action groups:

- State: `getState`, `setTab`
- Runtime: `toggleSuspend`, `togglePause`, `killAll`
- App/window: `save`, `reload`, `minimize`, `maximize`, `close`
- Navigation/help: `openHelp`, `openUrl`, `openVarMonitor`
- Tool/settings dialogs: `openSettingManager`, `openToolRecordSetting`, `editCmdTip`, `openFreePaste`, `openHotkeyEditor`, `keyDownHelp`
- Tool runtime: `toggleToolCheck`, `toggleToolRecord`, `toolTextFilterScreenShot`, `toolTextFilterSelectImage`, `clearToolText`
- Data update: `updateSetting`, `updateTool`, `updateItem`, `updateFold`, `toggleFold`
- Structure update: `addItem`, `deleteItem`, `moveItem`, `moveItemTo`, `copyItem`, `pasteItem`, `addFold`, `deleteFold`
- Editors: `openTriggerEditor`, `openMacroEditor`

When adding an action:

1. Define a small payload shape.
2. Validate payload values in AHK before mutating state.
3. Return a fresh state snapshot after successful mutation.
4. Keep legacy dialogs as fallback until the WebView flow reaches parity.
5. Run `npm.cmd run build` from `WebViewApp`.
6. Document the action here if it becomes part of normal UI behavior.

## Error Handling

Bridge failures should return `ok: false` with a concise `message`. React should keep the UI responsive and display the message without assuming a partial mutation succeeded.
