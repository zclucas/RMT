# Help And Documentation Assets

RMT ships its own help content. It does not currently include a local mirror of the official AutoHotkey v2 documentation at `https://www.autohotkey.com/docs/v2/`.

## Project Help Files

- `Web/*.md` are the source documents for RMT user help.
- `RMT帮助文档.html` and `index.html` are generated offline HTML outputs for RMT help.
- `Web/JS/SingleHtml.js` regenerates those outputs. Use `node Web\JS\SingleHtml.js --check` to check whether they are current without rewriting files.
- `RMT帮助文档-搜索侧栏版.html` and `RMT帮助文档-搜索顶部版.html` are local search variants.
- `Plugins/WebViewToo/Pages/index.html` is the local WebViewToo help page.

## AutoHotkey Error Help

When AutoHotkey shows a runtime error dialog, the Help button belongs to the installed AutoHotkey runtime, not to RMT. On this machine, AutoHotkey v2 provides its local help file at:

```text
C:\Program Files\AutoHotkey\v2\AutoHotkey.chm
```

That CHM is installed outside this repository. Do not treat it as a project-owned file or edit it as part of normal RMT maintenance.
