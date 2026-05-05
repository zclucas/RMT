# Project Handoff

## Project Snapshot
- Project: RMT Dev_UI WebView2 migration and maintenance branch.
- Path: `C:\Users\T8numen\Documents\Playground\rmt-test\RMT-zclucas-Dev_UI`
- Branch: `Dev_UI`
- Stack: AutoHotkey v2 runtime with React 18, TypeScript, Vite, WebView2, Playwright visual tests.
- Key entry points: `RMT.ahk`, `Main/UIUtil.ahk`, `WebViewApp/src`, `WebViewApp/dist`, `Web/JS/SingleHtml.js`, `scripts/verify.ps1`, `PackRMT.ps1`.

## Current State
- Completed: WebView UI stabilization, proportional scaling, no horizontal/left-sidebar scrollbars, disabled control fixes, Chinese WebView copy, fallback state split, bridge contract guard, WebView2 wrapper guard, generated-help guard.
- Completed: Latest completed maintenance commit before this handoff is `d7d6ecc chore: verify generated help docs`.
- Completed: Pushed current `Dev_UI` to `https://github.com/T8numen/RMT/tree/Dev_UI`; remote branch points to `d7d6ecc6a4e570b9358a7c0cb740d4aae3d3299a`.
- Worktree: Clean when this handoff was created.
- Important uncommitted changes: None expected after committing this handoff file.

## How To Continue
- Next steps: Add a `WebViewApp/dist` sync check so source changes cannot pass verification without committed generated assets.
- Next steps: Add a packaging smoke check for required release files: executable/script, `WebViewApp/dist`, `Plugins/WebViewToo`, and `RMT帮助文档.html`.
- Next steps: Add help Markdown local link/image checks for `Web/*.md`.
- Next steps: Expand Playwright visual states for multiple modules, disabled modules, long macro names, narrow windows, tools, and settings.
- Next steps: Add fixture-based config compatibility checks for `RmtBuildState()` using representative old configs.
- Next steps: Consider GitHub Actions for contract check, help-doc check, and TypeScript build before adding heavier AHK/Playwright checks.
- Recommended commands: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1`
- Recommended commands: `cd WebViewApp; npm.cmd run test:visual`
- Recommended commands: `powershell -ExecutionPolicy Bypass -File .\scripts\check-active-worktree.ps1`
- Notes: The most useful next implementation is the `WebViewApp/dist` sync check because it is low risk and prevents a common release mistake.

## Validation
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1` passed after adding the generated-help guard.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-help-docs.ps1` passed after refreshing `RMT帮助文档.html` and `index.html`.
- Ran: `git push https://github.com/T8numen/RMT.git HEAD:Dev_UI` succeeded.
- Ran: `git ls-remote https://github.com/T8numen/RMT.git refs/heads/Dev_UI` confirmed remote `Dev_UI` points to `d7d6ecc6a4e570b9358a7c0cb740d4aae3d3299a`.
- Not run: Manual launch of `RMT.ahk` after the last docs-only guard commit.
- Not run: Playwright visual tests after the last docs-only guard commit; prior visual checks were added and used for layout stabilization.
- Remaining risk: Manual runtime smoke testing is still needed before release packaging.

## Risks
- Known risks: Multiple local RMT clones exist, so launching the wrong `RMT.ahk` can make fixes appear missing.
- Known risks: `PackRMT.ps1` copies root `index.html` as release `RMT帮助文档.html`; stale generated help is now guarded, but packaging contents still need smoke checks.
- Known risks: AutoHotkey runtime error dialog Help opens the installed AutoHotkey CHM, not an RMT-owned document.
- Known risks: React/Vite build may fail under sandbox with `spawn EPERM`; rerun outside sandbox when needed.
- Blockers: None observed.
- Needs user confirmation: Whether to configure a persistent Git remote for `https://github.com/T8numen/RMT.git` instead of using direct push URLs.

## Context Notes
- Project rules: Default replies should be Simplified Chinese; keep AutoHotkey v2 compatibility; React owns WebView layout/input; AHK owns runtime behavior and bridge dispatch.
- Project rules: Keep `WebViewApp/src/types.ts`, `WebViewApp/src/fallbackState.ts`, and `Main/UIUtil.ahk` bridge state/action behavior aligned.
- Project rules: Commit `WebViewApp/dist` when changing frontend source; record maintenance-significant changes in `history.md`.
- Project rules: Do not bump versions for routine unreleased maintenance; release version sources are `Main/UIUtil.ahk`, `WebViewApp/package.json`, `WebViewApp/package-lock.json`, and `WebViewApp/src/fallbackState.ts`.
- Version/history: Current WebView version is `2.0.1`; recent maintenance history is recorded under `history.md` `Unreleased`.
- Android/LSPosed: Not applicable; this is a Windows AutoHotkey/WebView2 project, not an Android or LSPosed module.
