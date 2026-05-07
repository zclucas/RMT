# History

## Unreleased

- Added a manual GitHub Actions packaging workflow with release artifact upload and on-demand WebView2 Fixed Runtime download.
- Aligned release packaging with the upstream single-file help output at `index.html`.
- Converted `ReleaseX32` and `ReleaseX64` into generated packaging staging directories instead of tracked duplicate runtime trees.
- Added a Windows verification workflow and maintenance fixes for version checks, release output paths, release layout checks, and tracked AutoHotkey tool ignore rules.
- Added a repository-local Chinese AutoHotkey runtime for packaged RMT error dialogs, including a Chinese error help page and rebuild notes.
- Fixed WebView edge resize hitboxes and disabled the default WebView context menu.
- Restored the modal sub-window setting initialization and WebView settings binding.
- Added WebView contract and dist asset verification scripts for maintenance checks.
- Clarified WebView dist asset staging requirements and named local resize overlay constants.
- Adjusted the first batch of WebView UI layout details, including title bar, sidebar buttons, macro row actions, settings switches, and static content pages.
- Linked WebView button colors to the active UI color preset across sidebar, legacy, and macro row controls.
- Added menu macro module trigger type controls and covered the fold update path with visual tests.
- Added an opt-in WebView Vite dev server mode while keeping `WebViewApp/dist` as the default release path.
- Refined the WebView UI shell, sidebar, macro rows, settings switches, and static content pages for tighter legacy-style layout.

## 2.0

- Migrated the main window to the WebView UI and updated the displayed version to `RMTv2.0`.
- Added module-local drag sorting, macro copy, and module paste actions.
- Kept required tabs always visible and removed the unused settings diagnostics block.
- Restored tool/settings hotkey display formatting, including `!o` as `Alt+O`.
- Restored the menu macro module trigger control, compacted help/reward/thanks pages, and removed extra tool-page controls.
- Persisted the WebView scale/window size across restarts.
- Removed the WebView validation-only `scripts` directory from the source tree.
- Added the T8numen contributor entry with delayed handbook-inspired hover effects.
