# history

## Unreleased

- Added the WebView UI deep migration plan and bridge ownership boundaries.
- Expanded the React macro table with mode, hold-time, tip-sound controls, and full-table move button parity.
- Fixed macro row movement so the key mode moves with the macro item.
- Added WebView entry points for legacy trigger editors and delete confirmations in the macro table.
- Refined the WebView macro table density, column sizing, and sticky row actions for the default window size.
- Expanded the WebView tools and settings panels with mouse inspection, OCR output, recorder controls, and legacy hotkey editor entry points.
- Migrated the remaining WebView help, reward, and thanks pages from placeholders to maintained React content.
- Added a repeatable verification script and maintenance docs for development, the WebView bridge, and config compatibility.
- Added a regression checklist for release and large WebView change validation.
- Added a release workflow covering version updates, packaging, release output inspection, and packaged smoke tests.
- Added a legacy AHKGui cleanup audit to separate required fallback dialogs from later migration candidates.
- Added a WebView settings diagnostics entry that copies runtime and packaging context for support.
- Ignored local runtime settings and generated worker executables to avoid accidental commits.
- Tightened React bridge action typing so payloads are checked per WebView action.

## v1.1.3

- Replaced the main AHK `Gui` window with `WebViewToo`/WebView2.
- Added a React + TypeScript frontend under `WebViewApp`.
- Added an AHK bridge for reading and updating existing RMT table, fold, item, tool, and settings state from the WebView UI.
- Updated packaging to include `WebViewApp/dist` and the `WebViewToo` runtime files.
