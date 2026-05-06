# Legacy AHKGui Cleanup Audit

The WebView main window is active, but many AHKGui dialogs are still runtime dependencies. Do not delete legacy GUI files just because the first screen is now React.

## Cleanup Rule

A legacy GUI can be removed only after all of these are true:

- No `#Include` path requires the file.
- No `ShowGui()` or constructor call is reachable from `RMT.ahk`, `Thread\Work.ahk`, a bridge action, hotkey flow, macro execution flow, or packaging flow.
- The WebView replacement has matching validation and save behavior.
- React build, AutoHotkey validation, and `git diff --check` pass.
- The relevant path in `docs/regression-checklist.md` passes.

## Still Required By WebView Bridge

These dialogs are intentionally opened from React through `RmtWebAction()` or helper actions in `Main/UIUtil.ahk`:

- `Gui\VarListenGui.ahk`: `openVarMonitor`
- `Gui\SettingMgrGui.ahk`: `openSettingManager`
- `Gui\ToolRecordSettingGui.ahk`: `openToolRecordSetting`
- `Gui\CMDTipSettingGui.ahk`: `editCmdTip`
- `Gui\FreePasteGui.ahk`: `openFreePaste`
- `Gui\EditHotkeyGui.ahk`: `openHotkeyEditor`
- `Gui\TriggerKeyGui.ahk`: `openTriggerEditor`
- `Gui\TriggerStrGui.ahk`: `openTriggerEditor`
- `Gui\TimingGui.ahk`: `openTriggerEditor`, `openMacroEditor`
- `Gui\MacroEditGui.ahk`: `openMacroEditor`
- `Gui\ReplaceKeyGui.ahk`: `openMacroEditor`

These must remain until each equivalent WebView flow is implemented and verified.

## Macro Editor Dependency Group

`Gui\MacroEditGui.ahk` includes and coordinates most command editor dialogs:

- `IntervalGui`, `KeyGui`, `MouseMoveGui`, `SearchGui`, `SearchProGui`, `RunGui`
- `CompareGui`, `CompareProGui`, `CompareProEditItemGui`, `MMProGui`
- `OutputGui`, `VariableGui`, `ExVariableGui`, `TextOpsGui`, `ArrayGui`
- `SubMacroGui`, `LoopGui`, `OperationGui`, `BGMouseGui`, `BGKeyGui`
- `RMTCMDGui`, `InputGui`, `FileIOGui`

Treat this as one migration group. Removing one sub-dialog independently can break nested macro editing.

## Runtime And Worker Dialogs

These dialogs are not just main-window UI and should remain until their runtime flows are separately replaced:

- `Gui\MenuWheelGui.ahk`: runtime menu wheel.
- `Gui\CMDTipGui.ahk`: command tip overlay.
- `Gui\CustomMsgBoxGui.ahk`: output/message popup.
- `Gui\CustomInputGui.ahk`, `Gui\InputBtnGui.ahk`: worker input flows used by `Thread\Work.ahk` and input utilities.
- `Gui\TargetGui.ahk`, `Gui\ColorPanelGui.ahk`, `Gui\FrontInfoGui.ahk`, `Gui\WinRuleGui.ahk`: helper pickers used by editor dialogs.
- `Gui\UseExplainGui.ahk`: setting/package help flow.

## Candidates For Later Migration

Good later WebView migration candidates:

- Hotkey editor: smaller payload, clear validation boundary.
- Configuration manager: useful after config backup/migration behavior is covered.
- Tool record settings: limited settings surface.
- Trigger key/string editors: high user value, but validation and hotkey encoding must stay AHK-owned.
- Macro editor group: high impact, but should be migrated last because it owns many command-specific dialogs.

## Main-Window Legacy Code

`Main\UIUtil.ahk` still contains old main-window builder helpers such as `AddSettingUI()` and other `Gui.Add()` control construction paths. They are not safe to remove until:

- WebView startup has no fallback path that calls them.
- Main window save/reload/state refresh no longer depends on pseudo controls or old control wrappers.
- AHK validation and the full regression checklist pass after removal.

Prefer deleting main-window legacy code in small commits after bridge parity is complete.
