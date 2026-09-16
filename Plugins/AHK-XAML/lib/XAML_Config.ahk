; ==============================================================================
; AHK-XAML Global Configuration
; Note -- these can be overriden in a script; look at webview, docviewer examples
; ==============================================================================

; --- Engine Compilation ---
; When true, the C# engine (.dll) is recompiled from the src\*.cs files (split from the former XAML_AHK_Bridge.cs) on every run.
; When false, uses the pre-compiled ahk-xaml.dll from the lib/dep directory.
global XAML_FORCE_DYNAMIC_COMPILE := true

; --- Engine Build Location ---
; Controls where the C# engine (.dll) is compiled or placed during development runs:
;   "temp"    - Only compile/copy to %TEMP%\AhkWpf (keeps lib/dep clean, default)
;   "lib/dep" - Compile to lib/dep and run from there directly
;   "both"    - Compile to lib/dep and also copy to %TEMP%\AhkWpf (old behavior)
;
; 本项目取 "both"：WebView2 打开后引擎产物名带后缀（见 XAMLHost.GetEngineDllName
; → ahk-xaml-wv2.dll）。留 "temp" 的话它只落在 %TEMP%，lib\dep 里始终是旧的无
; WebView 版本，PackRMT.ps1 打出来的 Release 会缺引擎、进而要在用户机上重编。
global XAML_ENGINE_BUILD_LOCATION := "both"

; --- Developer Diagnostics ---
; When true, crash dialogs show interactive "Skip Property" / "Skip Element" buttons
; for rapid iteration. Disable in production for a cleaner user experience.
global XAML_DIAGNOSTICS_ENABLED := true

; Enable to dump the AXML Abstract Syntax Tree to a local file when parsing AXML files
global XAML_AXML_DEBUG_MODE := true

; --- Logging System ---
; When true, the framework writes trace and error logs to disk (e.g., AhkWpfError.log).
; Set to false to disable all disk I/O for logging.
global XAML_ENABLE_LOGGING := true

; --- XAML Line Tracing ---
; Enable XAML line-number and file tracing comments (<!-- [ahk:File.ahk:LineNumber] -->)
; during generation. Turn off for production or to reduce XAML string size.
global XAML_ENABLE_TRACING := true

; --- WebView2 ---
; 开启原因：帮助文档改用软件内嵌的小窗显示（Main/Util/HelpDocWin.ahk），
; 窗口属于软件自身，标题栏/尺寸/位置可控，不像 msedge --app 那样由浏览器接管。
; 只影响能装 WebView2 运行时的系统（Win10 1803+）；Win7 由 HasWebView2Runtime()
; 拦下并退回 --app 方案，不会走到这里。
; 依赖 DLL 首次运行自动从 NuGet 下载到 lib\dep\WebView2\。
global XAML_ENABLE_WEBVIEW := true

; --- WebView2 User Data Directory ---
; The directory where WebView2 stores its browser cache, cookies, and user data.
; If not specified, defaults to A_Temp "\AhkWpf\WebView2Data".
global XAML_WEBVIEW_USER_DATA_DIR := ""

; --- AvalonEdit IDE Component ---
; When true, compiles with ICSharpCode.AvalonEdit for a robust code editor
; with syntax highlighting, code folding, line numbers, autocomplete, and LSP hooks.
; Requires AvalonEdit DLLs in lib/dep/AvalonEdit/ (auto-downloaded from NuGet if missing).
global XAML_ENABLE_AVALONEDIT := false

; --- Document Editor ---
; When true, compiles with OpenXml SDK + NPOI for rich document viewing/editing
; with DOCX/DOC import/export, formatting toolbar, tables, images, and more.
; Requires DLLs in lib/dep/OpenXml/ (auto-downloaded from NuGet if missing).
global XAML_ENABLE_DOCUMENT := false

; --- DirectX 9 Pixel Shader Effects ---
; When true, compiles custom DirectX 9 pixel shaders (Glow, Acrylic, Ripple, Cyberpunk Gradient)
; into the background engine. Requires no external dependencies, but increases engine size.
global XAML_ENABLE_SHADERS := false

; --- Auto-Prewarm Engine ---
; When true, automatically spins up the background WPF engine as soon as the script launches.
; This completely eliminates the ~300ms cold-start delay when the dialog is shown!
global XAML_AUTO_PREWARM := false

; --- Developer Tools ---
; When true, enables the premium developer tools panel.
; Pressing F12 in any active app window opens the floating DevTools suite.
global XAML_ENABLE_DEVTOOLS := true

; --- In-Process CLR Hosting (Opt-In) ---
; When true, boots the WPF engine in-process inside the parent AHK thread using CLR hosting.
; When false, spawns a separate background daemon process (default, robust).
; 注意：进程内模式下 daemon HWND 属于 AHK 自身；若 EnsureDaemonMatches 误判路径并 KillDaemon，
; 旧逻辑会 ProcessClose 当前进程导致多窗口闪退。默认务必为 false。
global XAML_IN_PROCESS_PREVIEW := false

; --- 全局字体缩放（主题字体大小驱动所有界面字号）---
; 统一接口：界面声明只用 XAMLHost.FontSize() / TitleFontSize()；Show 时 ScaleFontSize / ApplyFontSizeDelta / Viewbox
; 设计基准与软件默认均为主题字体大小（15）。改主题滑条时：XAML_FontSizeDelta := 主题FontSize - 基准。
; 实际字号 = max(主题字体大小, 声明字号 + (主题字体大小 - 基准))，主题值为下限。
; 图形节点编辑器通过 XAMLHost.skipFontScale 排除；其余界面均走统一接口。
global XAML_FontSizeBase := 15
global XAML_FontSizeDefault := 15
global XAML_FontSizeDelta := 0
; 主题字体粗细 / 文字清晰度（窗口级默认值，元素显式设置时以元素为准）
global XAML_FontWeight := "400"               ; 100-900（100细~400常规~700粗~900黑）
global XAML_TextClarity := 1                  ; 1=标准(平滑 Ideal)；2=锐利(Display)；3=极锐利(Aliased)