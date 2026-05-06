# Project Handoff

## Project Snapshot
- Project: RMT 1.1.2 UI migration line, prepared as RMT 2.0.
- Path: C:\Users\T8numen\Documents\Playground\rmt-test\RMT-zclucas-v1.1.2
- Branch: codex/Dev_UI-rmt2-webview. The requested remote Dev_UI branch already existed and rejected a fast-forward push, so this branch is the safe handoff branch.
- Stack: AutoHotkey v2 desktop app, WebView2 through WebViewToo, React 18 + TypeScript + Vite UI, Playwright visual tests, PowerShell packaging.
- Key entry points: RMT.ahk, Main\UIUtil.ahk, WebViewApp\src\App.tsx, PackRMT.ps1, Thread\Work.ahk.

## Current State
- Completed: WebView UI migration from the older Dev_UI test line; version moved to RMTv2.0; author feedback items 1-17 addressed; dark preset and disabled-state contrast adjusted; lite/runtime packaging modes added; docs and history updated.
- Worktree: Expected to be clean after committing this HANDOFF.md file on codex/Dev_UI-rmt2-webview.
- Important uncommitted changes: None expected after the handoff commit; run git status --short --branch before continuing.

## How To Continue
- Next steps: Review the pushed branch, decide whether to merge it into the existing Dev_UI branch or replace Dev_UI after confirming the remote branch history, then run an end-to-end packaged launch test.
- Recommended commands: npm.cmd run build in WebViewApp; npm.cmd run test:visual in WebViewApp; AutoHotkey64.exe /ErrorStdOut=UTF-8 /Validate .\RMT.ahk; AutoHotkey64.exe /ErrorStdOut=UTF-8 /Validate .\Thread\Work.ahk; .\PackRMT.ps1 -Distribution both -NoWait after Ahk2Exe is available.
- Notes: PackRMT.ps1 supports -Distribution lite, runtime, and both. The runtime build expects a bundled WebView2 Fixed Runtime under Runtime\WebView2 when that variant is produced.

## Validation
- Ran: WebViewApp npm.cmd run build; npm.cmd run test:visual:update; npm.cmd run test:visual; AutoHotkey validation for RMT.ahk and Thread\Work.ahk; node Web\JS\SingleHtml.js --check; git diff --check; custom checks for version/distribution cleanup and WebView bridge action coverage.
- Not run: Full Ahk2Exe packaging smoke test, because Ahk2Exe.exe was not found under .tools or C:\Program Files\AutoHotkey.
- Remaining risk: Real packaged EXE launch, bundled WebView2 Fixed Runtime discovery, and native WebView bridge behavior still need manual smoke testing on the release machine.

## Risks
- Known risks: Remote T8numen/RMT Dev_UI already contains commits not present locally; avoid force-pushing until that branch is reviewed. Some files produced LF-to-CRLF warnings during git add.
- Blockers: Ahk2Exe.exe is missing, so PackRMT.ps1 cannot complete the final EXE build check yet.
- Needs user confirmation: Whether the existing GitHub Dev_UI branch should be merged, replaced, or left alongside codex/Dev_UI-rmt2-webview.

## Context Notes
- Project rules: Reply in Simplified Chinese by default; keep edits focused; maintain history.md, version numbers, and release/archive notes for software changes.
- Version/history: RMT.ahk displays RMTv2.0; WebViewApp package version is 2.0.0; history.md has the 2.0 migration summary.
- Android/LSPosed: Not an Android or LSPosed project; Android-specific validation does not apply.
