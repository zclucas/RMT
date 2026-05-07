# Help And Documentation Assets

RMT ships its own help content. It does not currently include a local mirror of the official AutoHotkey v2 documentation at `https://www.autohotkey.com/docs/v2/`.

## Project Help Files

- `Web/*.md` are the source documents for RMT user help.
- `index.html` is the generated offline HTML output for RMT help.
- `Web/JS/SingleHtml.js` regenerates this output. Use `node Web\JS\SingleHtml.js --check` to check whether it is current without rewriting files.
- `Plugins/WebViewToo/Pages/index.html` is the local WebViewToo help page.

## AutoHotkey Error Help

When AutoHotkey shows a runtime error dialog, the Help button belongs to the installed AutoHotkey runtime, not to RMT. On this machine, AutoHotkey v2 provides its local help file at:

```text
C:\Program Files\AutoHotkey\v2\AutoHotkey.chm
```

That CHM is installed outside this repository. Do not treat it as a project-owned file or edit it as part of normal RMT maintenance.
