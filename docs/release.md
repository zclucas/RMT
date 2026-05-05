# Release Workflow

Use this workflow when preparing a public RMT build. Routine unreleased maintenance commits do not need a version bump.

## 1. Prepare Version And Notes

Update the version in all version sources:

- `Main/UIUtil.ahk`: `RMT_WEBVIEW_VERSION`
- `WebViewApp/package.json`: `version`
- `WebViewApp/src/bridge.ts`: fallback `version`

Move completed `history.md` entries from `Unreleased` into a new version section.

## 2. Verify Source

Run from the repository root:

```powershell
.\scripts\verify.ps1
```

If the React build fails with `spawn EPERM` in a sandboxed environment, rerun the same command outside the sandbox.

## 3. Manual Regression

Follow:

```text
docs/regression-checklist.md
```

At minimum, verify startup, macro table save/reload, settings persistence, tool toggles, and help/static content.

## 4. Package

Run the existing packaging script from the repository root:

```powershell
.\PackRMT.ps1
```

Packaging behavior:

- Reads the version from `Main/UIUtil.ahk`.
- Compiles `Thread\Work.ahk` to `Work1.exe`.
- Packages `RMT帮助文档.html` when Node.js and `Web/JS/SingleHtml.js` are available.
- Copies `WebViewApp\dist` into release output.
- Copies `Plugins\WebViewToo\Lib` into release output.
- Creates desktop output under `RMTRelease\RMTv{version}`.

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

Confirm `node_modules` is not included.

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
