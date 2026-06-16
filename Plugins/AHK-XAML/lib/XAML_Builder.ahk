#Requires AutoHotkey v2.0

; ==============================================================================
; AHK-XAML Automatic Builder Include
; ==============================================================================
; Include this file at the end of your main application script.
; When the script is run with the "/build" flag, this will automatically
; trigger app.ExportBundle() to compile the WPF UI into a bundled DLL.
; ==============================================================================

if (A_Args.Length > 0 && A_Args[1] == "/build") {
    dllName := (A_Args.Length > 1) ? A_Args[2] : ""
    if (IsSet(app) && IsObject(app)) {
        try {
            app.ExportBundle(dllName)
        } catch Any as err {
            MsgBox("Bundle export failed:`n`n" err.Message "`n`nin " err.File " at line " err.Line, "Build Error", "Iconx")
        }
    } else {
        MsgBox("Error: 'app' instance of XAML_GUI was not found at global scope.`nCannot compile bundle.", "Build Error", "Iconx")
    }
    ExitApp()
}