# Release Workflow

Use this workflow when preparing a public RMT build. Routine unreleased maintenance commits do not need a version bump.

## 1. Prepare Version And Notes

Update the version in all version sources:

- `Main/UIUtil.ahk`: `RMT_WEBVIEW_VERSION`
- `WebViewApp/package.json`: `version`
- `WebViewApp/src/fallbackState.ts`: fallback `version`

Move completed `history.md` entries from `Unreleased` into a new version section.

## 2. Verify Source

Run from the repository root:

```powershell
cd WebViewApp
npm.cmd run build
cd ..
node .\scripts\verify-webview-contract.mjs
node .\scripts\verify-webview-dist.mjs
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut=UTF-8 /Validate .\RMT.ahk
git diff --check
```

If the React build fails with `spawn EPERM` in a sandboxed environment, rerun `npm.cmd run build` outside the sandbox.
If the build creates renamed dist assets, stage `WebViewApp/dist` before running `verify-webview-dist.mjs` as the final release check.

## 3. Manual Regression

Follow:

```text
docs/regression-checklist.md
```

At minimum, verify startup, macro table save/reload, settings persistence, tool toggles, and help/static content.
Also verify window chrome behavior from the checklist after WebView sizing or context-menu changes.

## 4. Package

Run the existing packaging script from the repository root:

```powershell
.\PackRMT.ps1
```

For non-interactive release packaging:

```powershell
.\PackRMT.ps1 -ReleaseType both -Distribution both -NoWait
```

The script prefers the repository-local Chinese AutoHotkey runtime and Ahk2Exe files under `.tools\AutoHotkey`. See `docs\ahk-chinese-error-runtime.md` for the runtime source patch, license notes, and rebuild steps.

Distribution variants:

- `-Distribution lite`: no bundled WebView2 Fixed Runtime. The target machine must already have Microsoft Edge WebView2 Runtime.
- `-Distribution runtime`: bundles WebView2 Fixed Runtime from `Runtimes\WebView2\Fixed\x64`, `Runtimes\WebView2\Fixed\x86`, or `.tools\WebView2Runtime\Fixed\{arch}`.
- `-Distribution both`: creates both variants.

Packaging behavior:

- Reads the version from `Main/UIUtil.ahk`.
- Compiles `Thread\Work.ahk` to `Work1.exe`.
- Packages `RMT帮助文档.html` when Node.js and `Web/JS/SingleHtml.js` are available.
- Copies `WebViewApp\dist` into release output.
- Copies `Plugins\WebViewToo\Lib` into release output.
- Creates desktop output under `RMTRelease\RMTv{version}` with `_lite` and/or `_runtime` suffixes.

Choose:

- Test build: X64 only.
- Formal build: X64 + X32 when the 32-bit AutoHotkey base is available.

## 5. Inspect Release Output

For each generated release folder, confirm these files or directories exist:

- `RMTv{version}.exe`
- `Thread\Work1.exe`
- `Lang\`
- `Plugins\WebViewToo\Lib\`
- `WebViewApp\dist\index.html`
- `WebViewApp\dist\assets\*.js`
- `WebViewApp\dist\assets\*.css`
- `RMT帮助文档.html`

Confirm `node_modules` is not included. For `_lite` packages, confirm `Runtimes\WebView2\Fixed` is not included. For `_runtime` packages, confirm `Runtimes\WebView2\Fixed\{arch}\msedgewebview2.exe` exists.

Manually inspect the release layout when packaging outside the default desktop `RMTRelease\RMTv{version}` location.

## 6. Smoke Test Packaged Build

Start the packaged `RMTv{version}.exe` from the generated release folder.

Check:

- WebView opens without a blank page.
- Help/reward/static images load from packaged paths.
- A simple macro can run and stop.
- Settings save and reload within the packaged folder.

## 7. Finalize

- Commit version and `history.md` changes.
- Tag the release after the packaged smoke test passes.
- Keep generated release archives outside source control unless the release process explicitly requires committing them.
