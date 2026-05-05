# Project Handoff

## Project Snapshot
- Project: RMT Dev_UI WebView2 migration and maintenance branch.
- Path: `C:\Users\T8numen\Documents\Playground\rmt-test\RMT-zclucas-Dev_UI`
- Branch: `Dev_UI`
- Stack: AutoHotkey v2 runtime with React 18, TypeScript, Vite, WebView2, Playwright visual tests.
- Key entry points: `RMT.ahk`, `Main/UIUtil.ahk`, `WebViewApp/src`, `WebViewApp/dist`, `Web/JS/SingleHtml.js`, `scripts/verify.ps1`, `PackRMT.ps1`.

## Current State
- Completed: WebView UI stabilization, proportional scaling, no horizontal/left-sidebar scrollbars, disabled control fixes, Chinese WebView copy, fallback state split, bridge contract guard, WebView2 wrapper guard, generated-help guard.
- Completed: Added verification guards for `WebViewApp/dist` sync, help Markdown local links/images, and packaged release layout.
- Completed: Expanded Playwright visual coverage for default/wide/dense-narrow macro layouts plus active tool and populated settings views.
- Completed: Added `RmtBuildState()` fixture compatibility checks and a lightweight WebView GitHub Actions workflow.
- Completed: Latest completed maintenance commit before this handoff is `d7d6ecc chore: verify generated help docs`.
- Completed: Pushed current `Dev_UI` to `https://github.com/T8numen/RMT/tree/Dev_UI`; remote branch points to `d7d6ecc6a4e570b9358a7c0cb740d4aae3d3299a`.
- Worktree: Contains uncommitted verification-guard changes from this session until committed.
- Important uncommitted changes: verification scripts/fixtures, Playwright visual tests and snapshots, `.github/workflows/webview-verify.yml`, docs, `AGENTS.md`, `history.md`, and this handoff.

## How To Continue
- Next steps: Monitor the new GitHub Actions workflow after pushing this branch.
- Next steps: Before release packaging, run manual runtime smoke testing for `RMT.ahk` and packaged output.
- Recommended commands: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1`
- Recommended commands: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-release-layout.ps1` after packaging.
- Recommended commands: `cd WebViewApp; npm.cmd run test:visual`
- Recommended commands: `powershell -ExecutionPolicy Bypass -File .\scripts\check-active-worktree.ps1`
- Notes: The current prioritized maintenance plan has been implemented locally; remaining work is release/runtime validation and CI observation.

## Validation
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1` passed after adding the generated-help guard.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-help-docs.ps1` passed after refreshing `RMT帮助文档.html` and `index.html`.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-help-links.ps1` passed.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-webview-dist-sync.ps1` passed.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-release-layout.ps1 -ReleaseRoot .\__missing_release_root__` failed with the expected missing release root message, confirming script parsing and early validation.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-release-layout.ps1 -ReleaseDir .\.codex-temp-release-check\RMTv2.0.1_x64` passed against a temporary minimal release layout; the temporary directory was removed.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify-rmt-build-state-fixtures.ps1` passed.
- Ran: `npm.cmd run test:visual:update` passed and wrote new snapshots.
- Ran: `npm.cmd run test:visual` passed with 5 tests.
- Ran: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1` passed outside the sandbox after sandboxed React/Vite build hit `spawn EPERM`.
- Ran: `git push https://github.com/T8numen/RMT.git HEAD:Dev_UI` succeeded.
- Ran: `git ls-remote https://github.com/T8numen/RMT.git refs/heads/Dev_UI` confirmed remote `Dev_UI` points to `d7d6ecc6a4e570b9358a7c0cb740d4aae3d3299a`.
- Not run: Manual launch of `RMT.ahk` after the last docs-only guard commit.
- Not run: Playwright visual tests after the last docs-only guard commit; prior visual checks were added and used for layout stabilization.
- Remaining risk: Manual runtime smoke testing is still needed before release packaging.

## Risks
- Known risks: Multiple local RMT clones exist, so launching the wrong `RMT.ahk` can make fixes appear missing.
- Known risks: `PackRMT.ps1` copies root `index.html` as release `RMT帮助文档.html`; stale generated help and release layout are guarded, but manual packaged runtime smoke testing is still needed.
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
