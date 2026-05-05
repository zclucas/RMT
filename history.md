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

## v1.1.3

- Replaced the main AHK `Gui` window with `WebViewToo`/WebView2.
- Added a React + TypeScript frontend under `WebViewApp`.
- Added an AHK bridge for reading and updating existing RMT table, fold, item, tool, and settings state from the WebView UI.
- Updated packaging to include `WebViewApp/dist` and the `WebViewToo` runtime files.
