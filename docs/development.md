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
- The WebView state/action contract matches between TypeScript and `Main/UIUtil.ahk`.
- The runtime include graph loads only the WebViewToo WebView2 wrapper.
- Generated RMT help HTML matches the current `Web/*.md` sources and help assets.
- Local links and images in `Web/*.md` resolve to existing files.
- `RmtBuildState()` keeps representative old in-memory config fixtures compatible with the WebView state shape.
- `RMT.ahk` passes AutoHotkey validation.
- React/TypeScript builds successfully and writes `WebViewApp/dist`.
- `WebViewApp/dist` stays synced with the tracked generated assets after build.
- `git diff --check` reports no whitespace errors.

Useful scoped checks:

```powershell
.\scripts\verify.ps1 -SkipWebBuild
.\scripts\verify.ps1 -SkipAhkValidate
.\scripts\verify.ps1 -SkipBridgeContract
.\scripts\verify.ps1 -SkipWebViewWrapperCheck
.\scripts\verify.ps1 -SkipHelpDocsCheck
.\scripts\verify.ps1 -SkipHelpLinkCheck
.\scripts\verify.ps1 -SkipBuildStateFixtures
.\scripts\verify.ps1 -SkipWebViewDistSync
.\scripts\verify.ps1 -AhkExe "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"
```

Confirm the local worktree and launch entry when multiple RMT clones exist:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-active-worktree.ps1
```

For manual release or large-change checks, also follow `docs/regression-checklist.md`.
For packaging a public build, follow `docs/release.md`.

When changing `Web/*.md`, `Web/CSS/*`, or help search scripts, run:

```powershell
node Web\JS\SingleHtml.js
.\scripts\verify-help-docs.ps1
.\scripts\verify-help-links.ps1
```

## WebView UI Work

- React owns layout, rendering, and input collection.
- AHK owns runtime behavior, saved data, macro execution, OCR, hotkeys, and legacy dialogs.
- Add or change behavior through an explicit bridge action in `Main/UIUtil.ahk`.
- Keep `WebViewApp/src/types.ts` aligned with the state returned by `RmtBuildState()`.
- Update `scripts/fixtures/rmt-build-state-fixtures.ahk` when adding state fields that need old-config defaults.
- Run `npm.cmd run build` before committing frontend changes so `WebViewApp/dist` stays current.
- Run `.\scripts\verify-webview-dist-sync.ps1` after frontend builds when checking generated assets without the full verifier.
- Run `npm.cmd run test:visual` from `WebViewApp` after layout-sensitive WebView changes.

## Release Notes

Record user-visible or maintenance-significant changes in `history.md` under `Unreleased`.

Do not bump the version for routine unreleased commits. Bump all version sources together when preparing a release:

- `Main/UIUtil.ahk`
- `WebViewApp/package.json`
- `WebViewApp/src/fallbackState.ts`
