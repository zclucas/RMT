; ==============================================================================
; AHK-XAML Global Configuration
; ==============================================================================

; --- Engine Compilation ---
; When true, the C# engine (.dll) is recompiled from XAML_AHK_Bridge.cs on every run.
; When false, uses the pre-compiled ahk-xaml.dll from the lib directory.
global XAML_FORCE_DYNAMIC_COMPILE := true

; --- Component Style Loading ---
; "BAML"  → Load pre-compiled binary styles from the embedded BAML resource (fastest).
; "XAML"  → Parse the plain-text xaml.components.xaml at runtime (allows live style editing).
global XAML_COMPONENTS_LOAD_MODE := "BAML"

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
global XAML_ENABLE_WEBVIEW := false

; --- Auto-Prewarm Engine ---
; When true, automatically spins up the background WPF engine as soon as the script launches.
; This completely eliminates the ~300ms cold-start delay when the dialog is shown!
global XAML_AUTO_PREWARM := false

; --- Backward Compatibility ---
; XAML_DEBUG is derived from the new flags for any scripts that still reference it.
global XAML_DEBUG := XAML_FORCE_DYNAMIC_COMPILE