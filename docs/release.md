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
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -AhkExe .\.tools\AutoHotkey\v2\AutoHotkey64.exe
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

GitHub Actions can also create release zips without committing generated output. Open the `Package` workflow from the Actions tab, run it manually, and choose:

- `release_type`: `x64` for a test package, or `both` for x64 and x32 packages.
- `distribution`: `lite`, `runtime`, or `both`.
- `retention_days`: how long GitHub keeps the uploaded workflow artifact.

The workflow uploads the generated zip files as run artifacts. It downloads and expands Microsoft WebView2 Fixed Runtime only when `distribution` is `runtime` or `both`.

Use `-OutputDir` for repeatable local or CI packaging without deleting the desktop `RMTRelease` directory:

```powershell
.\PackRMT.ps1 -ReleaseType both -Distribution lite -OutputDir C:\tmp\RMTRelease -NoWait
```

The script prefers the repository-local Chinese AutoHotkey runtime and Ahk2Exe files under `.tools\AutoHotkey`. See `docs\ahk-chinese-error-runtime.md` for the runtime source patch, license notes, and rebuild steps.

Distribution variants:

- `-Distribution lite`: no bundled WebView2 Fixed Runtime. The target machine must already have Microsoft Edge WebView2 Runtime.
- `-Distribution runtime`: bundles WebView2 Fixed Runtime from `Runtimes\WebView2\Fixed\x64`, `Runtimes\WebView2\Fixed\x86`, or `.tools\WebView2Runtime\Fixed\{arch}`.
- `-Distribution both`: creates both variants.

For GitHub Actions packaging, `scripts\prepare-webview2-runtime.ps1` reads the official Microsoft WebView2 download page, downloads the selected Fixed Version Runtime cab files, expands them with `expand.exe`, and stores them under `.tools\WebView2Runtime\Fixed`.

Packaging behavior:

- Reads the version from `Main/UIUtil.ahk`.
- Recreates `ReleaseX64` and `ReleaseX32` from canonical source resources before compiling; these directories are generated packaging staging areas.
- Compiles `Thread\Work.ahk` to `Work1.exe`.
- Packages `index.html` as the offline RMT help document when Node.js and `Web/JS/SingleHtml.js` are available.
- Copies `WebViewApp\dist` into release output.
- Copies `Plugins\WebViewToo\Lib` into release output.
- Creates output under `RMTRelease\RMTv{version}` by default, or under `-OutputDir`, with `_lite` and/or `_runtime` suffixes.

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
- `index.html`

Confirm `node_modules` is not included. For `_lite` packages, confirm `Runtimes\WebView2\Fixed` is not included. For `_runtime` packages, confirm `Runtimes\WebView2\Fixed\{arch}\msedgewebview2.exe` exists.

Manually inspect the release layout when packaging outside the default desktop `RMTRelease\RMTv{version}` location.

For `_runtime` packages using WebView2 Fixed Runtime v120 or newer on Windows 10, Microsoft documents an AppContainer permission requirement for unpackaged Win32 apps. If a Windows 10 target shows WebView2 startup failures with the bundled runtime, grant read/execute permissions to the deployed Fixed Runtime folder:

```powershell
icacls ".\Runtimes\WebView2\Fixed\x64" /grant *S-1-15-2-2:(OI)(CI)(RX)
icacls ".\Runtimes\WebView2\Fixed\x64" /grant *S-1-15-2-1:(OI)(CI)(RX)
```

Use `x86` instead of `x64` for the x32 package.

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
