# Regression Checklist

Use this checklist before release and after large WebView or macro behavior changes.

## Automated Checks

Run from the repository root:

```powershell
cd WebViewApp
npm.cmd run build
cd ..
node .\scripts\verify-webview-contract.mjs
node .\scripts\verify-webview-dist.mjs
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut=UTF-8 /Validate .\RMT.ahk
git diff --check
```

Expected result:

- WebView settings and saved compatibility controls are complete across AHK and React files.
- `WebViewApp/dist/index.html` references only existing tracked assets.
- `RMT.ahk` validates.
- React/TypeScript builds and updates `WebViewApp/dist`.
- `git diff --check` has no errors.

If the build creates renamed dist assets, stage `WebViewApp/dist` before running the dist asset release check.

Run the visual regression checks after layout-sensitive WebView changes:

```powershell
cd WebViewApp
npm.cmd run test:visual
```

Expected result:

- The default `1070x590` window has no horizontal page scrollbar.
- The left global sidebar has no independent scrollbar.
- The macro operation/status columns stay visible.
- Disabled macro controls stay on one line.

## Startup

- Start `RMT.ahk` with AutoHotkey v2.
- Main WebView window opens without a blank page.
- The title shows the expected `RMTv` version.
- Tabs are visible and switching tabs does not throw bridge errors.
- Existing settings and macro data load without reset prompts or missing-value errors.

## Macro Tables

- Expand and collapse a fold.
- Edit fold remark, front info, trigger type, trigger, hold time, and forbid state.
- Edit an item trigger, trigger type, macro text, mode, loop count, hold time, timing serial, tip sound, pause, forbid, and remark.
- Add and delete one item.
- Add and delete one fold.
- Drag an item within its module and confirm the order changes.
- Copy one macro and paste it into a module.
- Save, reload, and confirm the edited values remain.

## Runtime Controls

- Toggle suspend.
- Toggle pause.
- Start a simple macro and confirm running count updates.
- Stop all running macros with the kill action.
- Confirm runtime status refreshes in the WebView without reopening the app.

## Tools

- Toggle mouse inspection.
- Toggle recording.
- Open tool record settings.
- Run screenshot OCR extraction if OCR dependencies are available.
- Run selected image OCR extraction if OCR dependencies are available.
- Clear tool output text.
- Toggle always-on-top and confirm the state returns correctly.

## Settings

- Change numeric interval/coordinate/thread settings and save.
- Change screenshot and key-down modes.
- Toggle boot start, split line, fixed menu wheel, no-variable-tip, and command tip settings.
- Toggle modal sub-window, save, restart, and confirm it persists.
- Open hotkey editors for app and tool hotkeys.
- Save, restart, and confirm settings persist.

## Legacy Dialogs Still Used

- Open trigger key/string editors from the macro table.
- Open the macro detail editor from a row.
- Open variable monitor.
- Open configuration manager.
- Open key-down help.

## Window Chrome

- Right-click buttons, blank areas, and input fields without showing the WebView default context menu.
- Keyboard copy and paste still work in input fields.
- Hover below toolbar buttons, tab labels, and blank content without seeing a resize cursor.
- Hover and drag the outer left, right, top, bottom edges and four corners to resize.
- Maximize the window and confirm resize cursors disappear, then restore and confirm edge resize works again.

## Help And Static Content

- Help links open their target pages.
- Reward QR images render.
- Thanks page links open through the bridge.

## Config Compatibility

- Start with an existing `Setting/` directory.
- Confirm missing new fields receive defaults instead of breaking startup.
- Save settings and restart.
- Confirm macro tables and hotkeys still load.
- Keep a backup before testing destructive migration behavior.
