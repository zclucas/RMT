# Project Instructions

## Project Overview

- RMT is an AutoHotkey v2 macro tool with a React/TypeScript WebView2 UI.
- Key entry points are `RMT.ahk`, `Main\UIUtil.ahk`, `Main\WebView2UI.ahk`, `WebViewApp\src`, `Web\JS\SingleHtml.js`, and `PackRMT.ps1`.
- Treat `WebViewApp` as the source for the new UI. Treat root `index.html` and release folders as generated packaging output unless a task explicitly targets packaged artifacts.

## Build, Test, And Run

- Build the WebView UI with `npm run build` from `WebViewApp`.
- Run the repository verification script with `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -AhkExe .\.tools\AutoHotkey\v2\AutoHotkey64.exe`.
- Package releases with `powershell -ExecutionPolicy Bypass -File .\PackRMT.ps1 -ReleaseType both -Distribution both -OutputDir C:\tmp\RMTRelease -NoWait` when release validation is required.
- Validate release layout with `powershell -ExecutionPolicy Bypass -File .\scripts\verify-release-layout.ps1 -ReleaseRoot C:\tmp\RMTRelease\RMTv2.0`.

## Coding Conventions

- Keep edits scoped to the requested behavior and follow the existing AutoHotkey, React, TypeScript, and CSS patterns.
- Preserve Simplified Chinese UI copy unless the task explicitly asks for another language.
- Avoid treating `ReleaseX32`, `ReleaseX64`, or other generated staging folders as source of truth.
- Do not fetch, push, tag, publish, or create release artifacts unless the user explicitly asks.

## UI Workflow

- For UI changes, update `WebViewApp\src` first, then build so generated WebView assets stay in sync.
- For live UI development without rebuilding after every edit, run the Vite dev server and start RMT with `RMT_WEBVIEW_DEV=1`; see `docs\development.md`.
- Keep UI compact and practical; use color for state and emphasis, not as unrelated decoration.
- When changing colors or buttons, prefer existing theme/color utilities so controls react consistently to color method changes.
- Verify that button labels fit, especially in macro item rows and settings controls.

## Version And History

- Record maintenance-significant changes in `history.md`.
- Follow existing version and release documentation before bumping versions or archiving packages.
- Do not commit local handoff or temporary planning files unless the user explicitly asks.
