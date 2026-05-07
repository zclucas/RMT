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

Run the local verification from the repository root:

```powershell
cd WebViewApp
npm.cmd run build
cd ..
node .\scripts\verify-webview-contract.mjs
node .\scripts\verify-webview-dist.mjs
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut=UTF-8 /Validate .\RMT.ahk
git diff --check
```

This checks:

- React/TypeScript builds successfully and writes `WebViewApp/dist`.
- WebView setting fields stay aligned across TypeScript state, fallback data, fixtures, and AHK state builders.
- `WebViewApp/dist/index.html` only references built assets that exist and are tracked by Git.
- `RMT.ahk` passes AutoHotkey validation.
- `git diff --check` reports no whitespace errors.

If `npm.cmd run build` creates renamed `WebViewApp/dist/assets/main-*.js` files, stage the rebuilt `WebViewApp/dist` assets before treating `verify-webview-dist.mjs` as a release-blocking check.

For manual release or large-change checks, also follow `docs/regression-checklist.md`.
For packaging a public build, follow `docs/release.md`.

When changing `Web/*.md`, `Web/CSS/*`, or help search scripts, run:

```powershell
node Web\JS\SingleHtml.js
```

## WebView UI Work

- React owns layout, rendering, and input collection.
- AHK owns runtime behavior, saved data, macro execution, OCR, hotkeys, and legacy dialogs.
- Add or change behavior through an explicit bridge action in `Main/UIUtil.ahk`.
- Keep `WebViewApp/src/types.ts` aligned with the state returned by `RmtBuildState()`.
- Run `npm.cmd run build` before committing frontend changes so `WebViewApp/dist` stays current.
- Run `node .\scripts\verify-webview-contract.mjs` after changing WebView settings or saved setting compatibility controls.
- Run `node .\scripts\verify-webview-dist.mjs` after rebuilding and staging `WebViewApp/dist`.
- Run `npm.cmd run test:visual` from `WebViewApp` after layout-sensitive WebView changes.

### WebView Dev Server

By default, RMT loads the built UI from `WebViewApp/dist/index.html`. This remains the release path.

For frontend development, start Vite in one terminal:

```powershell
cd WebViewApp
npm.cmd run dev -- --host 127.0.0.1 --port 5173
```

Then start RMT with the dev switch in another terminal:

```powershell
$env:RMT_WEBVIEW_DEV = "1"
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" .\RMT.ahk
```

RMT will load `http://127.0.0.1:5173/` only when that local server responds. If the server is not running, it falls back to `WebViewApp/dist/index.html`.

To use a different local Vite port:

```powershell
$env:RMT_WEBVIEW_DEV_URL = "http://127.0.0.1:5174/"
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" .\RMT.ahk
```

Only `localhost`, `127.0.0.1`, and `[::1]` URLs are accepted for the dev switch.

## Release Notes

Record user-visible or maintenance-significant changes in `history.md` under `Unreleased`.

Do not bump the version for routine unreleased commits. Bump all version sources together when preparing a release:

- `Main/UIUtil.ahk`
- `WebViewApp/package.json`
- `WebViewApp/src/fallbackState.ts`
