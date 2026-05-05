# Active Worktree

This maintenance line uses `RMT-zclucas-Dev_UI` as the active local worktree.

## Entry Point

Launch this file when manually checking the WebView UI:

```powershell
C:\Users\T8numen\Documents\Playground\rmt-test\RMT-zclucas-Dev_UI\RMT.ahk
```

The runtime loads the React build from:

```text
WebViewApp/dist/index.html
```

## Guard Script

From the repository root, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-active-worktree.ps1
```

The script prints the current repository path, Git branch, `RMT.ahk` entry, WebView dist status, and sibling `RMT*` directories that can cause accidental launches from an older clone.

The guard does not rename, move, or delete any sibling folders.
