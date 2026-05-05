# Project Instructions

## Project Overview

- RMT is a Windows AutoHotkey v2 application.
- The main UI is migrated through WebView2 with React/TypeScript sources under `WebViewApp`.
- AutoHotkey remains responsible for runtime behavior, saved data, macro execution, OCR, hotkeys, and legacy dialogs.
- React owns layout, rendering, and user input collection. Bridge behavior belongs in `Main/UIUtil.ahk`.

## Build, Test, And Run

- Install frontend dependencies from `WebViewApp` with `npm.cmd install`.
- Build the WebView frontend from `WebViewApp` with `npm.cmd run build`.
- Run full repository verification from the repo root with `.\scripts\verify.ps1`.
- Use scoped verification when needed:
  - `.\scripts\verify.ps1 -SkipWebBuild`
  - `.\scripts\verify.ps1 -SkipAhkValidate`
  - `.\scripts\verify.ps1 -AhkExe "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"`
- Run packaging from the repo root with `.\PackRMT.ps1`.
- For non-interactive packaging, use `.\PackRMT.ps1 -ReleaseType both -NoWait`.

## Coding Conventions

- Keep AutoHotkey code compatible with AutoHotkey v2.
- Keep `WebViewApp/src/types.ts` aligned with the state returned by `RmtBuildState()` in `Main/UIUtil.ahk`.
- Add WebView behavior through explicit bridge actions instead of bypassing the AHK state model.
- Commit updated `WebViewApp/dist` outputs when changing `WebViewApp` source.
- Record user-visible or maintenance-significant changes in `history.md` under `Unreleased`.

## Versioning And Release

- Do not bump the version for routine unreleased maintenance.
- When preparing a release, update all version sources together:
  - `Main/UIUtil.ahk`: `RMT_WEBVIEW_VERSION`
  - `WebViewApp/package.json`: `version`
  - `WebViewApp/package-lock.json`: root package versions
  - `WebViewApp/src/bridge.ts`: fallback state `version`
- Follow `docs/release.md` for public release packaging and smoke testing.
- Keep generated release archives outside source control unless the release process explicitly requires committing them.

## Known Pitfalls

- `scripts\verify.ps1` requires the AHK, package, and bridge versions to match.
- `PackRMT.ps1` copies root `index.html` into release folders as `RMT帮助文档.html`.
- The WebView runtime loader files live under `Plugins\WebViewToo\Lib`.
- If React build fails with `spawn EPERM` in a sandboxed environment, rerun the same command outside the sandbox.
