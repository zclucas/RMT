# Development Workflow

This project is an AutoHotkey v2 application with a React/TypeScript WebView2 main UI.

## Prerequisites

- AutoHotkey v2, default path: `C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe`
- WebView2 Runtime
- Node.js/npm for `WebViewApp`

Install frontend dependencies once:

```powershell
cd WebViewApp
npm.cmd install
```

## Verify A Change

Run the full local verification from the repository root:

```powershell
.\scripts\verify.ps1
```

The script checks:

- `RMT_WEBVIEW_VERSION`, `WebViewApp/package.json`, and the bridge fallback version match.
- `RMT.ahk` passes AutoHotkey validation.
- React/TypeScript builds successfully and writes `WebViewApp/dist`.
- `git diff --check` reports no whitespace errors.

Useful scoped checks:

```powershell
.\scripts\verify.ps1 -SkipWebBuild
.\scripts\verify.ps1 -SkipAhkValidate
.\scripts\verify.ps1 -AhkExe "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"
```

For manual release or large-change checks, also follow `docs/regression-checklist.md`.
For packaging a public build, follow `docs/release.md`.

## WebView UI Work

- React owns layout, rendering, and input collection.
- AHK owns runtime behavior, saved data, macro execution, OCR, hotkeys, and legacy dialogs.
- Add or change behavior through an explicit bridge action in `Main/UIUtil.ahk`.
- Keep `WebViewApp/src/types.ts` aligned with the state returned by `RmtBuildState()`.
- Run `npm.cmd run build` before committing frontend changes so `WebViewApp/dist` stays current.

## Release Notes

Record user-visible or maintenance-significant changes in `history.md` under `Unreleased`.

Do not bump the version for routine unreleased commits. Bump all version sources together when preparing a release:

- `Main/UIUtil.ahk`
- `WebViewApp/package.json`
- `WebViewApp/src/bridge.ts`
