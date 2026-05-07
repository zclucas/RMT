# Active Worktree

This maintenance line uses `RMT-zclucas-v1.1.2` as the active local worktree.

## Entry Point

Launch this file when manually checking the WebView UI:

```powershell
C:\Users\T8numen\Documents\Playground\rmt-test\RMT-zclucas-v1.1.2\RMT.ahk
```

The runtime loads the React build from:

```text
WebViewApp/dist/index.html
```

## Manual Guard

Before launching, confirm the current repository path and branch:

```powershell
pwd
git branch --show-current
```

Then launch the `RMT.ahk` path listed above so an older sibling clone is not opened by mistake.
