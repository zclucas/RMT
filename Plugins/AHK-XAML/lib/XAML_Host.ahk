#Requires AutoHotkey v2.0
#SingleInstance Force


class CodeBox {
    static Init() {
        if !DllCall("GetModuleHandle", "Str", "msftedit.dll", "Ptr")
            DllCall("LoadLibrary", "Str", "msftedit.dll", "Ptr")
    }

    static Add(guiObj, options, text := "", fgColor := 0xE0E0E0) {
        this.Init()

        ; Extract background option to handle natively for RichEdit
        bkgColor := 0x1E1E1E
        if RegExMatch(options, "i)Background([0-9a-fA-F]{6})", &m) {
            bkgColor := Integer("0x" m[1])
            options := RegExReplace(options, "i)Background[0-9a-fA-F]{6}", "")
        }

        ; Normalize newlines to CR for perfectly accurate regex index mapping
        text := StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "`r")

        ; Base RichEdit properties: WS_VSCROLL | WS_HSCROLL | ES_READONLY | ES_NOHIDESEL | ES_AUTOHSCROLL | ES_AUTOVSCROLL | ES_MULTILINE
        ctrl := guiObj.Add("Custom", "ClassRichEdit50W +0x003009C4 " options, "")

        bgrBkg := ((bkgColor & 0xFF0000) >> 16) | (bkgColor & 0x00FF00) | ((bkgColor & 0x0000FF) << 16)
        SendMessage(0x0443, 0, bgrBkg, ctrl.Hwnd) ; EM_SETBKGNDCOLOR

        SendMessage(0x000C, 0, StrPtr(text), ctrl.Hwnd) ; WM_SETTEXT

        this.SetFormat(ctrl.Hwnd, fgColor, true, false)
        this.Highlight(ctrl.Hwnd, text)

        return ctrl
    }

    static Highlight(hwnd, text) {
        SendMessage(0x000B, 0, 0, hwnd) ; Disable redraw during syntax highlighting

        colors := Map(
            "Comment", 0x6A9955, "String", 0xCE9178, "Keyword", 0x569CD6,
            "Type", 0x4EC9B0, "Number", 0xB5CEA8, "Punctuation", 0x8F8F8F,
            "XMLTag", 0x569CD6, "Error", 0xF44747, "LogAt", 0xC586C0
        )

        ; Rule priority order is essential (later items overwrite earlier matches)
        rules := [{ p: "[\{\}\(\)\[\]<>]", c: colors["Punctuation"], b: false }, { p: "\b\d+(\.\d+)?\b", c: colors["Number"], b: false }, { p: "\b(string|int|bool|var|object|double|float|long|Exception)\b", c: colors["Type"], b: true }, { p: "\b(if|else|while|for|foreach|return|class|static|void|public|private|protected|async|await|try|catch|using|namespace|new)\b", c: colors["Keyword"], b: true }, { p: "\b(true|false|null)\b", c: colors["Keyword"], b: true }, { p: "\b(Error|Exception|Fail|Failed|Critical|FATAL|ERROR)\b", c: colors["Error"], b: true }, { p: "\b(at|in|line)\b", c: colors["LogAt"], b: false }, { p: "<\/?[\w:-]+>?", c: colors["XMLTag"], b: true }, { p: '(?m)".*?"', c: colors["String"], b: false }, { p: "(?m)'.*?'", c: colors["String"], b: false }, { p: "(?m)//.*", c: colors["Comment"], b: false }, { p: "(?s)<!--.*?-->", c: colors["Comment"], b: false }, { p: "(?s)/\*.*?\*/", c: colors["Comment"], b: false }
        ]

        for rule in rules {
            pos := 1
            while (match := RegExMatch(text, rule.p, &m, pos)) {
                this.SetSel(hwnd, match - 1, match - 1 + m.Len[0])
                this.SetFormat(hwnd, rule.c, false, rule.b)
                pos := match + m.Len[0]
            }
        }

        this.SetSel(hwnd, 0, 0)
        SendMessage(0x000B, 1, 0, hwnd) ; Re-enable redraw
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    }

    static SetSel(hwnd, start, end) {
        cr := Buffer(8, 0)
        NumPut("Int", start, cr, 0)
        NumPut("Int", end, cr, 4)
        SendMessage(0x0437, 0, cr.Ptr, hwnd) ; EM_EXSETSEL
    }

    static SetFormat(hwnd, colorRGB, isDefault := false, bold := false) {
        bgr := ((colorRGB & 0xFF0000) >> 16) | (colorRGB & 0x00FF00) | ((colorRGB & 0x0000FF) << 16)
        cf2 := Buffer(116, 0)
        NumPut("UInt", 116, cf2, 0)

        mask := 0x40000000 ; CFM_COLOR
        effects := 0
        if (bold) {
            mask |= 0x00000001 ; CFM_BOLD
            effects |= 0x00000001 ; CFE_BOLD
        }

        NumPut("UInt", mask, cf2, 4)
        NumPut("UInt", effects, cf2, 8)
        NumPut("UInt", bgr, cf2, 20)
        SendMessage(0x0444, isDefault ? 4 : 1, cf2.Ptr, hwnd) ; EM_SETCHARFORMAT
    }
}

class XAMLHost {
    static LastTheme := "Dark Mica (Win 11)"
    static LastThemeIni := ""
    static LastScale := "Balanced"
    static LastRadius := "Smooth (8)"
    static LastIcon := 0
    static _instances := Map()
    static _msgHooked := false
    static daemonHwnd := 0
    static daemonReceiver := 0
    static instanceCounter := 0
    static _appDir := ""
    static CLR_Started := false
    static CLR_BridgeAssembly := ""
    static CLR_AppDomain := ""
    static CLR_BridgeClass := ""

    static GetAppDir() {
        if (XAMLHost._appDir != "")
            return XAMLHost._appDir
        
        if (A_IsCompiled) {
            XAMLHost._appDir := A_ScriptDir
        } else {
            SplitPath(A_LineFile, , &libDir)
            XAMLHost._appDir := libDir "\.."
        }
        
        if !DirExist(A_WorkingDir "\Log")
            DirCreate(A_WorkingDir "\Log")
        if !DirExist(XAMLHost._appDir "\Cache")
            DirCreate(XAMLHost._appDir "\Cache")

        EnvSet("RMT_LOG_DIR", A_WorkingDir "\Log")
            
        return XAMLHost._appDir
    }

    static GetEngineDllName() {
        global CUSTOM_DLL_BUNDLE_NAME, XAML_ENABLE_WEBVIEW, XAML_ENABLE_AVALONEDIT, XAML_ENABLE_DOCUMENT, XAML_ENABLE_SHADERS
        if (IsSet(CUSTOM_DLL_BUNDLE_NAME) && CUSTOM_DLL_BUNDLE_NAME != "")
            return CUSTOM_DLL_BUNDLE_NAME
        if (A_Args.Length > 0 && A_Args[1] == "/build") {
            if (A_Args.Length > 1 && A_Args[2] != "")
                return A_Args[2]
            SplitPath(A_ScriptName, , , , &nameNoExt)
            return nameNoExt "_bundled.dll"
        }
        if (A_IsCompiled) {
            return "ahk-xaml.dll"
        }
        suffix := ""
        if (IsSet(XAML_ENABLE_WEBVIEW) && XAML_ENABLE_WEBVIEW)
            suffix .= "-wv2"
        if (IsSet(XAML_ENABLE_AVALONEDIT) && XAML_ENABLE_AVALONEDIT)
            suffix .= "-ava"
        if (IsSet(XAML_ENABLE_DOCUMENT) && XAML_ENABLE_DOCUMENT)
            suffix .= "-docs"
        if (IsSet(XAML_ENABLE_SHADERS) && XAML_ENABLE_SHADERS)
            suffix .= "-fx"
        return "ahk-xaml" suffix ".dll"
    }

    __New(xaml := "", exePath := "", ownerHwnd := 0) {
        if (!A_IsCompiled) {
            XAMLHost.RestoreWebView2Dlls()
            XAMLHost.RestoreAvalonEditDlls()
            XAMLHost.RestoreDocumentDlls()
        }
        XAMLHost.instanceCounter++
        this.id := "WPF_" A_TickCount "_" XAMLHost.instanceCounter "_" Random(1000, 9999)
        XAMLHost._instances[this.id] := this

        if (InStr(xaml, "%Width%"))
            xaml := StrReplace(xaml, "%Width%", "940")
        if (InStr(xaml, "%Height%"))
            xaml := StrReplace(xaml, "%Height%", "700")
        if (InStr(xaml, "%ResizeMode%"))
            xaml := StrReplace(xaml, "%ResizeMode%", "CanResize")

        this.xaml := xaml
        this.exePath := exePath
        this.ownerHwnd := ownerHwnd
        this.events := Map()
        this.tracked := Map()
        this.wpfHwnd := 0
        this.pid := 0
        XAMLHost.GetAppDir()
        if !DirExist(A_WorkingDir "\Log")
            DirCreate(A_WorkingDir "\Log")
        this.errLog := A_WorkingDir "\Log\AhkWpfError.log"


        this.receiver := Gui()
        DllCall("user32\ChangeWindowMessageFilterEx", "Ptr", this.receiver.Hwnd, "UInt", 0x004A, "UInt", 1, "Ptr", 0)

        if (!XAMLHost._msgHooked) {
            OnMessage(0x004A, ObjBindMethod(XAMLHost, "OnCopyData"), 255)
            XAMLHost._msgHooked := true
        }
    }

    OnEvent(controlName, eventName, callback, priority := 0) {
        if !this.events.Has(controlName)
            this.events[controlName] := Map()
        if !this.events[controlName].Has(eventName)
            this.events[controlName][eventName] := []

        evtObj := { Callback: callback, Priority: priority, LimitFPS: 0, QueueLimited: false }
        this.events[controlName][eventName].Push(evtObj)

        ; Return a chainable config object for this event registration
        return { Limit: (thisObj, fps, queue := false) => (evtObj.LimitFPS := fps, evtObj.QueueLimited := queue, this) }
    }

    Track(controlName) {
        this.tracked[controlName] := true
    }

    IsDevToolsWindow() {
        if (!IsSet(XAML_DevTools_Instance) || !IsObject(XAML_DevTools_Instance))
            return false
        try {
            if (HasProp(XAML_DevTools_Instance, "app") && XAML_DevTools_Instance.app && HasProp(XAML_DevTools_Instance.app, "host") && XAML_DevTools_Instance.app.host)
                return (this.id == XAML_DevTools_Instance.app.host.id)
        }
        return false
    }

    Update(controlName, propertyName, valueStr) {
        if !this.wpfHwnd {
            if !this.HasOwnProp("_updateQueue")
                this._updateQueue := []
            this._updateQueue.Push({ type: "single", ctrl: controlName, prop: propertyName, val: valueStr })
            return
        }
        val := StrReplace(valueStr, "`r", "&#x0D;")
        val := StrReplace(val, "`n", "&#x0A;")
        payload := controlName "|" propertyName "|" val
        if (!this.IsDevToolsWindow()) {
            XAMLHost.LogDevTools("OUT", payload)
        }
        buf := Buffer(StrPut(payload, "UTF-8"))
        StrPut(payload, buf, "UTF-8")

        cds := Buffer(A_PtrSize * 3)
        NumPut("Ptr", 0, cds, 0)
        NumPut("UInt", buf.Size, cds, A_PtrSize)
        NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)

        DllCall("user32\SendMessageW", "Ptr", this.wpfHwnd, "UInt", 0x004A, "Ptr", 0, "Ptr", cds.Ptr)
    }

    BatchUpdate(updatesArray) {
        if !this.wpfHwnd {
            if !this.HasOwnProp("_updateQueue")
                this._updateQueue := []
            this._updateQueue.Push({ type: "batch", arr: updatesArray })
            return
        }

        payload := ""
        for updateObj in updatesArray {
            if (!updateObj.HasProp("ControlName") || !updateObj.HasProp("PropertyName") || !updateObj.HasProp("Value"))
                continue

            val := String(updateObj.Value)
            val := StrReplace(val, "`r", "&#x0D;")
            val := StrReplace(val, "`n", "&#x0A;")
            payload .= updateObj.ControlName "|" updateObj.PropertyName "|" val "`n"
        }

        if (payload != "") {
            if (!this.IsDevToolsWindow()) {
                XAMLHost.LogDevTools("OUT", payload)
            }
            buf := Buffer(StrPut(payload, "UTF-8"))
            StrPut(payload, buf, "UTF-8")

            cds := Buffer(A_PtrSize * 3)
            NumPut("Ptr", 0, cds, 0)
            NumPut("UInt", buf.Size, cds, A_PtrSize)
            NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)

            DllCall("user32\SendMessageW", "Ptr", this.wpfHwnd, "UInt", 0x004A, "Ptr", 0, "Ptr", cds.Ptr)
        }
    }


    ; Enable lightweight event mode: events only include the triggering control's value.
    ; Use ui.Query("TxtName") or ui.Query("*") for additional values.
    ; This dramatically reduces IPC payload for UIs with many tracked controls.
    SetLightweightEvents(enabled := true) {
        if (!this.wpfHwnd)
            return
        this.Update("CONFIG", "LightweightEvents", enabled ? "1" : "0")
    }

    static Prewarm(exePath := "") {
        wvDataDir := (IsSet(XAML_WEBVIEW_USER_DATA_DIR) && XAML_WEBVIEW_USER_DATA_DIR != "") ? XAML_WEBVIEW_USER_DATA_DIR : A_Temp "\AhkWpf\WebView2Data"
        EnvSet("AHK_XAML_WEBVIEW_DIR", wvDataDir)
        if XAMLHost.daemonHwnd
            return
        if (!XAMLHost.daemonReceiver) {
            XAMLHost.daemonReceiver := Gui()
            DllCall("user32\ChangeWindowMessageFilterEx", "Ptr", XAMLHost.daemonReceiver.Hwnd, "UInt", 0x004A, "UInt", 1, "Ptr", 0)
            if (!XAMLHost._msgHooked) {
                OnMessage(0x004A, ObjBindMethod(XAMLHost, "OnCopyData"), 255)
                XAMLHost._msgHooked := true
            }
        }

        if !DirExist(A_Temp "\AhkWpf")
            DirCreate(A_Temp "\AhkWpf")

        baseDllName := XAMLHost.GetEngineDllName()
        targetExe := (exePath != "") ? exePath : A_Temp "\AhkWpf\" baseDllName

        SplitPath(A_LineFile, , &libDir)
        sharedExe := libDir "\dep\" baseDllName

        if (A_IsCompiled && FileExist(A_ScriptDir "\" baseDllName)) {
            targetExe := A_ScriptDir "\" baseDllName
        } else if (A_IsCompiled) {
            return
        } else if (!A_IsCompiled) {
            buildLoc := IsSet(XAML_ENGINE_BUILD_LOCATION) ? XAML_ENGINE_BUILD_LOCATION : "temp"
            if (exePath == "") {
                if (buildLoc == "lib/dep") {
                    targetExe := sharedExe
                } else {
                    targetExe := A_Temp "\AhkWpf\" baseDllName
                }
            }

            if (buildLoc == "temp") {
                if !FileExist(targetExe) {
                    if FileExist(sharedExe) {
                        try FileCopy(sharedExe, targetExe, 1)
                    } else if !XAMLHost.CompileEngine(libDir, targetExe) {
                        return
                    }
                }
            } else if (buildLoc == "lib/dep") {
                if !FileExist(targetExe) {
                    if !XAMLHost.CompileEngine(libDir, targetExe)
                        return
                }
            } else { ; both
                if !FileExist(sharedExe) {
                    if !XAMLHost.CompileEngine(libDir, sharedExe)
                        return
                }
                if (!FileExist(targetExe) || FileGetTime(sharedExe) != FileGetTime(targetExe)) {
                    try FileCopy(sharedExe, targetExe, 1)
                }
            }

            XAMLHost.RestoreWebView2Dlls()
            XAMLHost.RestoreAvalonEditDlls()
            XAMLHost.RestoreDocumentDlls()
            SplitPath(targetExe, , &targetDir)
            XAMLHost.CopyRequiredDlls(libDir, targetDir)

        } else {
            ;;@Ahk2Exe-IgnoreBegin
            ;if !FileExist(targetExe)
            ;    FileInstall("dep\ahk-xaml.dll", targetExe, 1)
            ;;@Ahk2Exe-IgnoreEnd
        }

        logArg := (IsSet(XAML_ENABLE_LOGGING) && !XAML_ENABLE_LOGGING) ? ' --no-log' : ''
        XAMLHost.RunProcess(targetExe, '--daemon "' ProcessExist() '" "' String(XAMLHost.daemonReceiver.Hwnd) '"' logArg, "", true)
    }

    static RunProcess(exePath, args, workingDir := "", hide := true) {
        cmdLine := '"' exePath '" ' args
        siSize := A_PtrSize == 8 ? 104 : 68
        si := Buffer(siSize, 0)
        NumPut("UInt", siSize, si, 0) ; cb
        if (hide) {
            NumPut("UInt", 0x00000001, si, A_PtrSize == 8 ? 60 : 44) ; dwFlags = STARTF_USESHOWWINDOW
            NumPut("UShort", 0, si, A_PtrSize == 8 ? 64 : 48)        ; wShowWindow = SW_HIDE
        }
        piSize := A_PtrSize == 8 ? 24 : 16
        pi := Buffer(piSize, 0)
        status := DllCall("kernel32\CreateProcessW",
            "Ptr", 0,          ; lpApplicationName
            "Str", cmdLine,    ; lpCommandLine
            "Ptr", 0,          ; lpProcessAttributes
            "Ptr", 0,          ; lpThreadAttributes
            "Int", 0,          ; bInheritHandles
            "UInt", 0,         ; dwCreationFlags
            "Ptr", 0,          ; lpEnvironment
            "Ptr", workingDir == "" ? 0 : StrPtr(workingDir), ; lpCurrentDirectory
            "Ptr", si.Ptr,     ; lpStartupInfo
            "Ptr", pi.Ptr,     ; lpProcessInformation
            "Int"              ; Return type
        )
        if (!status)
            return false
        hProcess := NumGet(pi, 0, "Ptr")
        hThread := NumGet(pi, A_PtrSize, "Ptr")
        DllCall("kernel32\CloseHandle", "Ptr", hProcess)
        DllCall("kernel32\CloseHandle", "Ptr", hThread)
        return true
    }

    static RunProcessWait(exePath, args, workingDir := "", hide := true) {
        cmdLine := '"' exePath '" ' args
        siSize := A_PtrSize == 8 ? 104 : 68
        si := Buffer(siSize, 0)
        NumPut("UInt", siSize, si, 0) ; cb
        if (hide) {
            NumPut("UInt", 0x00000001, si, A_PtrSize == 8 ? 60 : 44) ; dwFlags = STARTF_USESHOWWINDOW
            NumPut("UShort", 0, si, A_PtrSize == 8 ? 64 : 48)        ; wShowWindow = SW_HIDE
        }
        piSize := A_PtrSize == 8 ? 24 : 16
        pi := Buffer(piSize, 0)
        status := DllCall("kernel32\CreateProcessW",
            "Ptr", 0,          ; lpApplicationName
            "Str", cmdLine,    ; lpCommandLine
            "Ptr", 0,          ; lpProcessAttributes
            "Ptr", 0,          ; lpThreadAttributes
            "Int", 0,          ; bInheritHandles
            "UInt", 0,         ; dwCreationFlags
            "Ptr", 0,          ; lpEnvironment
            "Ptr", workingDir == "" ? 0 : StrPtr(workingDir), ; lpCurrentDirectory
            "Ptr", si.Ptr,     ; lpStartupInfo
            "Ptr", pi.Ptr,     ; lpProcessInformation
            "Int"              ; Return type
        )
        if (!status)
            return -1
        hProcess := NumGet(pi, 0, "Ptr")
        hThread := NumGet(pi, A_PtrSize, "Ptr")
        DllCall("kernel32\WaitForSingleObject", "Ptr", hProcess, "UInt", 0xFFFFFFFF)
        exitCode := 0
        exitCodeBuf := Buffer(4, 0)
        DllCall("kernel32\GetExitCodeProcess", "Ptr", hProcess, "Ptr", exitCodeBuf.Ptr)
        exitCode := NumGet(exitCodeBuf, 0, "UInt")
        DllCall("kernel32\CloseHandle", "Ptr", hProcess)
        DllCall("kernel32\CloseHandle", "Ptr", hThread)
        return exitCode
    }

    CheckForCrashes() {
        if (this.wpfHwnd != 0) {
            SetTimer(ObjBindMethod(this, "CheckForCrashes"), 0)
            return
        }
        if FileExist(this.errLog) {
            try {
                err := FileRead(this.errLog)
                FileDelete(this.errLog)
            } catch {
                return
            }
            SetTimer(ObjBindMethod(this, "CheckForCrashes"), 0)

            ahkLine := "Unknown"
            snippet := ""
            if RegExMatch(err, "s)AHK_LINE:(.*?)\nXAML_SNIPPET:(.*?)\n\n(.*)", &m) {
                ahkLine := m[1]
                snippet := m[2]
                err := m[3]
            }

            header := "The Background Engine crashed! Details below:"
            if (ahkLine != "Unknown") {
                header := "Engine crashed while rendering AHK Line " ahkLine "!"
            }

            lineNum := 0, colNum := 0
            if (RegExMatch(err, "i)Line\s*(?:number)?\s*['`"]?(\d+)['`"]?\s*(?:and|,)?\s*(?:line)?\s*position\s*['`"]?(\d+)['`"]?", &match)) {
                lineNum := Integer(match[1])
                colNum := Integer(match[2])
            }

            hasRetry := (IsSet(XAML_DIAGNOSTICS_ENABLED) && XAML_DIAGNOSTICS_ENABLED && lineNum > 0)

            while (true) {
                action := XAMLHost.ShowErrorDialog("Engine Crash", header, snippet, err, hasRetry)
                if (action == "skip_property") {
                    if (this.SkipPropertyAndRetry(err, lineNum, colNum)) {
                        break
                    }
                } else if (action == "skip_element") {
                    if (this.SkipElementAndRetry(err, lineNum, colNum)) {
                        break
                    }
                } else {
                    ExitApp()
                }
            }
        }
    }

    static ShowErrorDialog(title, header, snippet, details, hasRetryOptions := false, reason := "") {
        ; Pre-format the error text for better readability
        details := StrReplace(details, " ---> ", "`r`n`r`n---> ")
        details := StrReplace(details, "`r`n", "`n")
        details := StrReplace(details, "`n", "`r`n")
        details := StrReplace(details, "`r`n   at ", "`r`n`r`n   at ", , &_, 1)

        errGui := Gui("+Resize +MinSize800x600", title)
        errGui.BackColor := "White"
        errGui.MarginX := 20
        errGui.MarginY := 20

        errGui.SetFont("s13 bold cD00000", "Segoe UI")
        headerText := errGui.Add("Text", "w860", header)

        if (reason != "") {
            errGui.SetFont("s11 bold c003366", "Segoe UI")
            reasonLbl := errGui.Add("Text", "y+15", "Root Cause:")
            errGui.SetFont("s10 bold cWhite", "Consolas")
            reasonEdit := CodeBox.Add(errGui, "y+5 w860 ReadOnly -Wrap -E0x200 Background1E1E1E", "`r`n  " reason "`r`n", 0xFFFFFF)
        } else {
            reasonLbl := ""
            reasonEdit := ""
        }

        exceptionMsg := ""
        stackTrace := details
        if InStr(title, "Compile Error") {
            lines := StrSplit(details, "`n", "`r")
            for line in lines {
                if InStr(line, "error CS") {
                    exceptionMsg .= line "`n"
                }
            }
            if exceptionMsg != ""
                exceptionMsg := Trim(exceptionMsg, "`n")
        } else {
            pos := InStr(details, "   at ")
            if (pos > 0) {
                exceptionMsg := Trim(SubStr(details, 1, pos - 1), "`r`n ")
                stackTrace := Trim(SubStr(details, pos), "`r`n ")
            } else {
                exceptionMsg := details
                stackTrace := ""
            }
        }

        excEdit := ""
        if (exceptionMsg != "") {
            ; Use regex to add spacing and indentation
            exceptionMsg := RegExReplace(exceptionMsg, "m)^([\w\.]+Exception):\s*(.*)", "$1:`r`n    $2")
            exceptionMsg := RegExReplace(exceptionMsg, "m)^(--->\s*[\w\.]+Exception):\s*(.*)", "`r`n$1:`r`n    $2")

            ; Add empty lines at the top and bottom to create pseudo-padding inside the edit control
            exceptionMsg := "`r`n" exceptionMsg "`r`n"

            errGui.SetFont("s10 bold cWhite", "Consolas")
            excEdit := CodeBox.Add(errGui, "y+15 w860 ReadOnly -Wrap -E0x200 Background1E1E1E", exceptionMsg, 0xFFFFFF)
            lineCount := StrSplit(exceptionMsg, "`n").Length
            h := Min(200, Max(40, lineCount * 17 + 8))
            excEdit.Move(, , , h)
        }

        snipLbl := "", snipEdit := ""
        if (snippet != "") {
            errGui.SetFont("s11 bold c003366", "Segoe UI")
            snipLbl := errGui.Add("Text", "y+15", InStr(title, "Compile Error") ? "Code Snippet:" : "Generated XAML Snippet:")
            errGui.SetFont("s9 norm cE0E0E0", "Consolas")
            snipEdit := CodeBox.Add(errGui, "y+5 w860 h150 ReadOnly +VScroll +HScroll -Wrap Background1E1E1E", "`r`n" snippet, 0xE0E0E0)

            ; Auto scroll to the '>>' marker
            lines := StrSplit(snippet, "`n", "`r")
            targetLine := 0
            for index, line in lines {
                if InStr(line, ">>") {
                    targetLine := index
                    break
                }
            }
            if (targetLine > 0) {
                SendMessage(0xB6, 0, targetLine > 3 ? targetLine - 3 : targetLine, snipEdit.Hwnd)
            }
        }

        errGui.SetFont("s11 bold c003366", "Segoe UI")
        traceLbl := errGui.Add("Text", "y+15", stackTrace != "" ? "Full Exception Trace:" : "Details:")
        errGui.SetFont("s9 norm cE0E0E0", "Consolas")
        traceEdit := CodeBox.Add(errGui, "y+5 w860 h250 ReadOnly +VScroll +HScroll -Wrap Background1E1E1E", "`r`n" (stackTrace != "" ? stackTrace : details), 0xE0E0E0)

        userAction := "abort"

        errGui.SetFont("s10 norm cBlack", "Segoe UI")
        btnCopy := errGui.Add("Button", "w150 x20 y+20", "📋 Copy to Clipboard")
        btnExport := errGui.Add("Button", "w150 x+10", "💾 Export to File")

        btnSkipProp := ""
        btnSkipElem := ""
        if (hasRetryOptions) {
            btnSkipProp := errGui.Add("Button", "w150 x+10", "⚡ Skip Property")
            btnSkipElem := errGui.Add("Button", "w150 x+10", "⚡ Skip Element")
            btnClose := errGui.Add("Button", "w120 x+10 Default", "Abort")
        } else {
            btnClose := errGui.Add("Button", "w120 x+340 Default", "Close")
        }

        btnCopy.OnEvent("Click", (*) => CopyToClipboard())
        CopyToClipboard() {
            A_Clipboard := header "`r`n`r`n" (snippet ? "XAML SNIPPET:`r`n" snippet "`r`n`r`n" : "") "DETAILS:`r`n" details
            MsgBox("Error details copied to clipboard.", "Copied", "Iconi 0x40000 T2")
        }

        btnExport.OnEvent("Click", (*) => ExportLog())
        ExportLog() {
            fileSavePath := FileSelect("S", "AhkEngineCrash_" A_Now ".log", "Save Error Log", "Log Files (*.log)")
            if (fileSavePath != "") {
                try {
                    if FileExist(fileSavePath)
                        FileDelete(fileSavePath)
                    content := "TIME: " A_Now "`r`n"
                    content .= "HEADER: " header "`r`n`r`n"
                    if (snippet)
                        content .= "XAML SNIPPET:`r`n" snippet "`r`n`r`n"
                    content .= "EXCEPTION DETAILS:`r`n" details
                    FileAppend(content, fileSavePath)
                    MsgBox("Error log saved successfully.", "Export Complete", "Iconi")
                } catch as err {
                    MsgBox("Failed to save error log: " err.Message, "Export Failed", "Iconx")
                }
            }
        }

        if (hasRetryOptions) {
            btnSkipProp.OnEvent("Click", (*) => (userAction := "skip_property", errGui.Destroy()))
            btnSkipElem.OnEvent("Click", (*) => (userAction := "skip_element", errGui.Destroy()))
            btnClose.OnEvent("Click", (*) => (userAction := "abort", errGui.Destroy()))
        } else {
            btnClose.OnEvent("Click", (*) => (userAction := "close", errGui.Destroy()))
        }
        errGui.OnEvent("Close", (*) => (userAction := "abort"))

        errGui.OnEvent("Size", Gui_Size)

        Gui_Size(guiObj, minMax, width, height) {
            if (minMax = -1)
                return
            marg := 20
            availW := width - marg * 2

            headerText.GetPos(&tx, &ty, &tw, &th)
            headerText.Move(, , availW)
            currentY := ty + th + 10

            if (reasonLbl != "") {
                reasonLbl.GetPos(&rx, &ry, &rw, &rh)
                reasonLbl.Move(, currentY)
                currentY += rh + 5
            }

            if (reasonEdit != "") {
                reasonEdit.GetPos(&rex, &rey, &rew, &reh)
                reasonEdit.Move(, currentY, availW)
                currentY += reh + 15
            }

            if (excEdit != "") {
                excEdit.GetPos(&ex, &ey, &ew, &eh)
                excEdit.Move(, currentY, availW)
                currentY += eh + 15
            }

            btnClose.GetPos(&bx, &by, &bw, &bh)
            btnY := height - marg - bh
            btnCopy.Move(, btnY)
            btnExport.Move(, btnY)
            if (hasRetryOptions) {
                btnClose.Move(width - marg - bw, btnY)
                btnSkipElem.Move(width - marg - bw - 10 - 150, btnY, 150)
                btnSkipProp.Move(width - marg - bw - 10 - 150 - 10 - 150, btnY, 150)
            } else {
                btnClose.Move(width - marg - bw, btnY)
            }

            availH := btnY - 15 - currentY

            if (snipEdit != "") {
                snipLbl.GetPos(&slx, &sly, &slw, &slh)
                snipLbl.Move(, currentY)
                currentY += slh + 5

                snipH := Max(60, availH * 0.35)
                snipEdit.Move(, currentY, availW, snipH)
                currentY += snipH + 15
                availH := btnY - 15 - currentY
            }

            traceLbl.GetPos(&tlx, &tly, &tlw, &tlh)
            traceLbl.Move(, currentY)
            currentY += tlh + 5

            traceH := Max(60, btnY - 15 - currentY)
            traceEdit.Move(, currentY, availW, traceH)
        }
        btnClose.Focus()

        errGui.Show()
        WinWaitClose(errGui)
        return userAction
    }

    Export(filePath) {
        eventBindings := ""
        for ctrlName, events in this.events {
            for eventName, evtList in events {
                eventBindings .= ctrlName ":" eventName ","
            }
        }
        eventBindings := RTrim(eventBindings, ",")

        payload := this.xaml "`n---AHK-XAML-EVENTS---`n" eventBindings

        tempTxt := A_Temp "\AhkWpf\gui_temp.txt"
        if !DirExist(A_Temp "\AhkWpf")
            DirCreate(A_Temp "\AhkWpf")

        if FileExist(tempTxt)
            FileDelete(tempTxt)
        FileAppend(payload, tempTxt, "UTF-8")

        baseDllName := XAMLHost.GetEngineDllName()
        targetExe := (this.exePath != "") ? this.exePath : A_Temp "\AhkWpf\" baseDllName
        SplitPath(A_LineFile, , &libDir)
        sharedExe := libDir "\dep\" baseDllName

        if (A_IsCompiled && FileExist(A_ScriptDir "\" baseDllName)) {
            targetExe := A_ScriptDir "\" baseDllName
        } else if (!A_IsCompiled) {
            if !FileExist(sharedExe) {
                if !XAMLHost.CompileEngine(libDir, sharedExe)
                    return
            }
            targetExe := sharedExe
        }

        if !FileExist(targetExe) {
            MsgBox("Fatal Error: Could not locate " baseDllName " to perform compilation.", "AHK-XAML", "Iconx")
            return
        }

        XAMLHost.RunProcessWait(targetExe, '--compress "' tempTxt '" "' filePath '"', "", true)

        if FileExist(tempTxt)
            FileDelete(tempTxt)
    }

    static CompileEngine(libDir, sharedExe, extraResources := [], embedDeps := false) {
        global XAML_ENABLE_WEBVIEW, XAML_ENABLE_AVALONEDIT, XAML_ENABLE_DOCUMENT, XAML_ENABLE_SHADERS
        if (A_IsCompiled) {
            MsgBox("AHK-XAML: Dynamic compilation is not available when the script is compiled. Please compile the engine separately.")
            return
        }

        XAMLHost.RestoreWebView2Dlls()
        errLog := A_Temp "\AhkWpf\AhkWpfError.log"
        sourceCs := libDir "\dep\XAML_AHK_Bridge.cs"
        if !FileExist(sourceCs) {
            MsgBox("XAML_AHK_Bridge.cs not found in lib\dep directory!`nCannot compile shared engine.", "AHK-XAML", "Iconx")
            return false
        }

        cscPath := "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        if !FileExist(cscPath)
            cscPath := "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"

        SplitPath(cscPath, , &cscDir)
        wpfDir := cscDir "\WPF"

        wvRefs := ""
        wvDef := ""
        if (IsSet(XAML_ENABLE_WEBVIEW) && XAML_ENABLE_WEBVIEW) {
            coreDll := libDir "\dep\WebView2\Microsoft.Web.WebView2.Core.dll"
            wpfDll := libDir "\dep\WebView2\Microsoft.Web.WebView2.Wpf.dll"
            if (FileExist(coreDll) && FileExist(wpfDll)) {
                wvRefs := ' /reference:"' coreDll '" /reference:"' wpfDll '"'
                if (embedDeps) {
                    wvRefs .= ' /resource:"' coreDll '",Microsoft.Web.WebView2.Core.dll /resource:"' wpfDll '",Microsoft.Web.WebView2.Wpf.dll'
                }
                wvDef := ' /define:ENABLE_WEBVIEW'
            } else {
                ToolTip("WebView2 DLLs not found in lib\dep\WebView2. Compiling without WebView2 support.")
                SetTimer(() => ToolTip(), -4000)
            }
        }

        ; --- AvalonEdit IDE Component ---
        aeRefs := ""
        aeDef := ""
        if (IsSet(XAML_ENABLE_AVALONEDIT) && XAML_ENABLE_AVALONEDIT) {
            aeDll := libDir "\dep\AvalonEdit\ICSharpCode.AvalonEdit.dll"
            if (FileExist(aeDll)) {
                aeRefs := ' /reference:"' aeDll '" /reference:System.Windows.Forms.dll /reference:WindowsFormsIntegration.dll'
                if (embedDeps) {
                    aeRefs .= ' /resource:"' aeDll '",ICSharpCode.AvalonEdit.dll'
                }
                aeDef := ' /define:ENABLE_AVALONEDIT'
            } else {
                ToolTip("AvalonEdit DLL not found in lib\dep\AvalonEdit. Compiling without IDE support.")
                SetTimer(() => ToolTip(), -4000)
            }
        }

        ; --- Document Editor (OpenXml + NPOI) ---
        docRefs := ""
        docDef := ""
        if (IsSet(XAML_ENABLE_DOCUMENT) && XAML_ENABLE_DOCUMENT) {
            oxDll := libDir "\dep\OpenXml\DocumentFormat.OpenXml.dll"
            if (FileExist(oxDll)) {
                docRefs := ' /reference:"' oxDll '"'
                if (embedDeps) {
                    docRefs .= ' /resource:"' oxDll '",DocumentFormat.OpenXml.dll'
                }
                ; Also add NPOI if available for .doc support
                npoiDll := libDir "\dep\OpenXml\NPOI.dll"
                if (FileExist(npoiDll)) {
                    docRefs .= ' /reference:"' npoiDll '"'
                    if (embedDeps) {
                        docRefs .= ' /resource:"' npoiDll '",NPOI.dll'
                    }
                    npoiOoxmlDll := libDir "\dep\OpenXml\NPOI.OOXML.dll"
                    npoiOpenXml4NetDll := libDir "\dep\OpenXml\NPOI.OpenXml4Net.dll"
                    if (FileExist(npoiOoxmlDll)) {
                        docRefs .= ' /reference:"' npoiOoxmlDll '"'
                        if (embedDeps) {
                            docRefs .= ' /resource:"' npoiOoxmlDll '",NPOI.OOXML.dll'
                        }
                    }
                    if (FileExist(npoiOpenXml4NetDll)) {
                        docRefs .= ' /reference:"' npoiOpenXml4NetDll '"'
                        if (embedDeps) {
                            docRefs .= ' /resource:"' npoiOpenXml4NetDll '",NPOI.OpenXml4Net.dll'
                        }
                    }
                }
                docDef := ' /define:ENABLE_DOCUMENT'
            } else {
                ToolTip("OpenXml DLL not found in lib\dep\OpenXml. Compiling without Document Editor support.")
                SetTimer(() => ToolTip(), -4000)
            }
        }

        shDef := ""
        if (IsSet(XAML_ENABLE_SHADERS) && XAML_ENABLE_SHADERS) {
            shDef := ' /define:ENABLE_SHADERS'
        }

        gifRef := ""
        gifDll := libDir "\dep\WpfAnimatedGif\WpfAnimatedGif.dll"
        if (FileExist(gifDll)) {
            gifRef := ' /reference:"' gifDll '"'
            if (embedDeps) {
                gifRef .= ' /resource:"' gifDll '",WpfAnimatedGif.dll'
            }
        }

        ; Embed component resources directly into the DLL for zero-disk-IO loading
        embeddedRes := ""
        bamlPath := libDir "\dep\xaml.components.baml"
        xamlPath := libDir "\dep\xaml.components.xaml"
        if FileExist(bamlPath) {
            embeddedRes .= ' /resource:"' bamlPath '"'
        } else if FileExist(xamlPath) {
            embeddedRes .= ' /resource:"' xamlPath '"'
        }

        for _, res in extraResources {
            if FileExist(res) {
                SplitPath(res, &resName)
                embeddedRes .= ' /resource:"' res '",' resName
            }
        }

        try FileDelete(sharedExe)
        if FileExist(sharedExe) {
            SplitPath(sharedExe, &sharedName)
            MsgBox("Error: The target DLL '" sharedName "' is locked by a running process.`n`nPlease close all running instances of your application and try compiling again.", "Build Error", "Iconx")
            return false
        }

        cmd := A_ComSpec ' /c ""' cscPath '" /nologo /target:winexe /out:"' sharedExe '" /lib:"' wpfDir '" /reference:System.dll /reference:System.Core.dll /reference:System.Xml.dll /reference:PresentationFramework.dll /reference:PresentationCore.dll /reference:WindowsBase.dll /reference:System.Xaml.dll /reference:UIAutomationProvider.dll /reference:UIAutomationTypes.dll' wvRefs wvDef aeRefs aeDef docRefs docDef shDef gifRef embeddedRes ' "' sourceCs '" > "' errLog '" 2>&1"'
        RunWait(cmd, "", "Hide")

        if !FileExist(sharedExe) {
            errOut := FileExist(errLog) ? FileRead(errLog) : "Unknown compilation error."
            snippet := ""
            reason := ""

            if RegExMatch(errOut, "m)^([a-zA-Z]:\\[^\(]+)\((\d+),(\d+)\):\s*error\s*(CS\d+:\s*[^\r\n]+)", &match) {
                filePath := match[1]
                lineNum := Integer(match[2])
                colNum := Integer(match[3])
                reason := match[4]

                if FileExist(filePath) {
                    try {
                        lines := StrSplit(FileRead(filePath), "`n", "`r")
                        if (lineNum > 0 && lineNum <= lines.Length) {
                            codeLine := lines[lineNum]
                            pointerLine := ""
                            loop colNum - 1
                                pointerLine .= " "
                            pointerLine .= "^"

                            startLine := Max(1, lineNum - 3)
                            endLine := Min(lines.Length, lineNum + 3)

                            for idx, lineStr in lines {
                                if (idx >= startLine && idx <= endLine) {
                                    if (idx == lineNum) {
                                        snippet .= ">> " idx ":  " codeLine "`n"
                                        snippet .= "   " RegExReplace(idx, ".", " ") "   " pointerLine "`n"
                                    } else {
                                        snippet .= "   " idx ":  " lineStr "`n"
                                    }
                                }
                            }
                            snippet := Trim(snippet, "`n")
                        }
                    }
                }
            }

            XAMLHost.ShowErrorDialog("Engine Compile Error", "Failed to compile background engine.", snippet, errOut, false, reason)
            return false
        }
        try FileDelete(errLog)
        return true
    }

    static CopyRequiredDlls(libDir, targetDir) {
        depDir := libDir "\dep"
        if (IsSet(XAML_ENABLE_WEBVIEW) && XAML_ENABLE_WEBVIEW) {
            if FileExist(depDir "\WebView2\WebView2Loader.dll") {
                try FileCopy(depDir "\WebView2\WebView2Loader.dll", targetDir "\WebView2Loader.dll", 1)
                try FileCopy(depDir "\WebView2\Microsoft.Web.WebView2.Core.dll", targetDir "\Microsoft.Web.WebView2.Core.dll", 1)
                try FileCopy(depDir "\WebView2\Microsoft.Web.WebView2.Wpf.dll", targetDir "\Microsoft.Web.WebView2.Wpf.dll", 1)
            }
        }
        if (IsSet(XAML_ENABLE_AVALONEDIT) && XAML_ENABLE_AVALONEDIT) {
            if FileExist(depDir "\AvalonEdit\ICSharpCode.AvalonEdit.dll")
                try FileCopy(depDir "\AvalonEdit\ICSharpCode.AvalonEdit.dll", targetDir "\ICSharpCode.AvalonEdit.dll", 1)
        }
        if (IsSet(XAML_ENABLE_DOCUMENT) && XAML_ENABLE_DOCUMENT) {
            if FileExist(depDir "\OpenXml\DocumentFormat.OpenXml.dll")
                try FileCopy(depDir "\OpenXml\DocumentFormat.OpenXml.dll", targetDir "\DocumentFormat.OpenXml.dll", 1)
            if FileExist(depDir "\OpenXml\NPOI.dll")
                try FileCopy(depDir "\OpenXml\NPOI.dll", targetDir "\NPOI.dll", 1)
            if FileExist(depDir "\OpenXml\NPOI.OOXML.dll")
                try FileCopy(depDir "\OpenXml\NPOI.OOXML.dll", targetDir "\NPOI.OOXML.dll", 1)
            if FileExist(depDir "\OpenXml\NPOI.OpenXml4Net.dll")
                try FileCopy(depDir "\OpenXml\NPOI.OpenXml4Net.dll", targetDir "\NPOI.OpenXml4Net.dll", 1)
        }
    }


    BundleCustomEngine(targetExe) {
        if (A_IsCompiled) {
            MsgBox("AHK-XAML: Dynamic compilation is not available when the script is compiled. Please compile the engine separately.")
            return
        }
        ; If running in /build mode, write AXML metadata directly to the source script for standalone compiled execution
        if (A_Args.Length > 0 && A_Args[1] == "/build" && IsSet(AXML) && HasProp(AXML, "ParsedData") && AXML.ParsedData.Length > 0) {
            metadataStr := AXML.SerializeParsedData()
            escapedMetadata := StrReplace(metadataStr, "`r", "")
            escapedMetadata := StrReplace(escapedMetadata, "`n", "``n")
            escapedMetadata := StrReplace(escapedMetadata, '"', '""')
            metadataBlock := '`n;=== AXML METADATA ===`nAXML_METADATA := "' escapedMetadata '"`n;=== AXML METADATA END ===`n'

            try {
                scriptContent := FileRead(A_ScriptFullPath, "UTF-8")
                ; Strip existing metadata block if present
                scriptContent := RegExReplace(scriptContent, "s)(?:\r?\n)?[ \t]*;=== AXML METADATA ===.*;=== AXML METADATA END ===(?:\r?\n)?")

                ; Insert at the top of the file, right after #Requires if present, otherwise at the very top
                if (pos := RegExMatch(scriptContent, "mi)^[ \t]*#Requires\b")) {
                    posLineEnd := InStr(scriptContent, "`n", , pos)
                    left := SubStr(scriptContent, 1, posLineEnd)
                    right := SubStr(scriptContent, posLineEnd + 1)
                    scriptContent := left metadataBlock right
                } else {
                    scriptContent := metadataBlock scriptContent
                }

                FileDelete(A_ScriptFullPath)
                FileAppend(scriptContent, A_ScriptFullPath, "UTF-8")
            }
        }

        cleanXaml := StrReplace(this.xaml, "%resources%", "")
        cleanXaml := StrReplace(cleanXaml, "%components%", "")

        tempDir := A_Temp "\AhkWpf"
        if !DirExist(tempDir)
            DirCreate(tempDir)

        tempXaml := tempDir "\app_payload.xaml"
        tempBaml := tempDir "\app_payload.baml"
        tempEvents := tempDir "\app_payload.events"

        try FileDelete(tempXaml)
        try FileDelete(tempBaml)
        try FileDelete(tempEvents)

        FileAppend(cleanXaml, tempXaml, "UTF-8")

        SplitPath(A_LineFile, , &libDir)
        toolPath := libDir "\..\tools\compile_baml.ps1"
        forceXaml := (IsSet(XAML_FORCE_XAML_BUNDLING) && XAML_FORCE_XAML_BUNDLING) || EnvGet("AHK_XAML_FORCE_XAML") == "1"
        if (!forceXaml && FileExist(toolPath)) {
            cmd := 'powershell.exe -ExecutionPolicy Bypass -File "' toolPath '" -InputXaml "' tempXaml '" -OutputBaml "' tempBaml '"'
            RunWait(cmd, "", "Hide")
        }

        eventsStr := ""
        for ctrlName, evtMap in this.events {
            for evtName, arr in evtMap {
                limit := 0
                queue := false
                for evtObj in arr {
                    if (evtObj.HasProp("LimitFPS") && evtObj.LimitFPS > 0) {
                        limit := evtObj.LimitFPS
                        queue := evtObj.QueueLimited
                    }
                }

                evtToken := ctrlName ":" evtName
                if (limit > 0)
                    evtToken .= "@" limit (queue ? "Q" : "")

                eventsStr .= evtToken ","
            }
        }
        eventsStr := Trim(eventsStr, ",")
        if (eventsStr != "") {
            FileAppend(eventsStr, tempEvents, "UTF-8")
        }

        resList := []
        if FileExist(tempBaml) {
            resList.Push(tempBaml)
        } else {
            ToolTip("Warning: BAML compilation failed. Falling back to XAML bundling...")
            SetTimer(() => ToolTip(), -3000)
            if FileExist(tempXaml) {
                resList.Push(tempXaml)
            } else {
                MsgBox("Failed to bundle custom engine: XAML payload file not found.", "AHK-XAML", "Iconx")
                return false
            }
        }

        if FileExist(tempEvents)
            resList.Push(tempEvents)

        tempAxml := tempDir "\app_payload.axml"
        try FileDelete(tempAxml)
        if (IsSet(AXML) && HasProp(AXML, "ParsedData") && AXML.ParsedData.Length > 0) {
            FileAppend(AXML.SerializeParsedData(), tempAxml, "UTF-8")
            resList.Push(tempAxml)
        }

        SplitPath(targetExe, &targetName)
        try {
            while ProcessExist(targetName) {
                ProcessClose(targetName)
                Sleep(50)
            }
        }
        try FileDelete(targetExe)
        if FileExist(targetExe) {
            MsgBox("Error: The target DLL '" targetName "' is locked by a running process.`n`nPlease close all running instances of your application and try building again.", "Build Error", "Iconx")
            return false
        }

        success := XAMLHost.CompileEngine(libDir, targetExe, resList, true)

        if (success) {
            SplitPath(targetExe, , &targetDir)
            ; Copy native WebView2Loader.dll if WebView2 is enabled
            if (IsSet(XAML_ENABLE_WEBVIEW) && XAML_ENABLE_WEBVIEW) {
                depDir := libDir "\dep"
                if FileExist(depDir "\WebView2\WebView2Loader.dll") {
                    try FileCopy(depDir "\WebView2\WebView2Loader.dll", targetDir "\WebView2Loader.dll", 1)
                }
            }
        }

        try FileDelete(tempXaml)
        try FileDelete(tempBaml)
        try FileDelete(tempEvents)
        try FileDelete(tempAxml)

        return success
    }

    _EnsureDaemon() {
        wvDataDir := (IsSet(XAML_WEBVIEW_USER_DATA_DIR) && XAML_WEBVIEW_USER_DATA_DIR != "") ? XAML_WEBVIEW_USER_DATA_DIR : A_Temp "\AhkWpf\WebView2Data"
        EnvSet("AHK_XAML_WEBVIEW_DIR", wvDataDir)
        baseDllName := XAMLHost.GetEngineDllName()
        targetExe := (this.exePath != "") ? this.exePath : A_Temp "\AhkWpf\" baseDllName
        if XAMLHost.daemonHwnd
            return targetExe

        if !DirExist(A_Temp "\AhkWpf")
            DirCreate(A_Temp "\AhkWpf")
        if FileExist(this.errLog) {
            try FileDelete(this.errLog)
        }

        SplitPath(A_LineFile, , &libDir)
        sharedExe := libDir "\dep\" baseDllName

        if (A_IsCompiled) {
            targetExe := sharedExe
        } else if (!A_IsCompiled) {
            sourceCs := libDir "\dep\XAML_AHK_Bridge.cs"
            configAhk := libDir "\XAML_Config.ahk"
            configTime := FileExist(configAhk) ? FileGetTime(configAhk) : 0
            forceCompile := IsSet(XAML_FORCE_DYNAMIC_COMPILE) && XAML_FORCE_DYNAMIC_COMPILE
            buildLoc := IsSet(XAML_ENGINE_BUILD_LOCATION) ? XAML_ENGINE_BUILD_LOCATION : "temp"

            if (buildLoc == "lib/dep") {
                targetExe := sharedExe
            } else {
                targetExe := A_Temp "\AhkWpf\" baseDllName
            }

            if (forceCompile && FileExist(sourceCs)) {
                compileTarget := (buildLoc == "temp") ? targetExe : sharedExe
                if (!FileExist(compileTarget) || FileGetTime(sourceCs) > FileGetTime(compileTarget) || configTime > FileGetTime(compileTarget)) {
                    try {
                        while ProcessExist(baseDllName) {
                            ProcessClose(baseDllName)
                            Sleep(50)
                        }
                    }
                    try FileDelete(compileTarget)
                    if !XAMLHost.CompileEngine(libDir, compileTarget)
                        return ""
                }
            }

            if (!FileExist(targetExe)) {
                if (buildLoc == "temp" && FileExist(sharedExe)) {
                    try FileCopy(sharedExe, targetExe, 1)
                } else if (!forceCompile) {
                    if !XAMLHost.CompileEngine(libDir, targetExe)
                        return ""
                }
            }

            if (buildLoc == "both" && FileExist(sharedExe)) {
                if (!FileExist(targetExe) || FileGetTime(sharedExe) != FileGetTime(targetExe)) {
                    try FileCopy(sharedExe, targetExe, 1)
                }
            }

            if (this.exePath != "" && !FileExist(targetExe)) {
                MsgBox("Custom Engine DLL not found: " targetExe, "AHK-XAML", "Iconx")
                return ""
            }

            XAMLHost.RestoreWebView2Dlls()
            XAMLHost.RestoreAvalonEditDlls()
            XAMLHost.RestoreDocumentDlls()
            SplitPath(targetExe, , &targetDir)
            XAMLHost.CopyRequiredDlls(libDir, targetDir)
        } else {
            ;@Ahk2Exe-IgnoreBegin
            if !FileExist(targetExe)
                FileInstall("dep\ahk-xaml.dll", targetExe, 1)
            ;@Ahk2Exe-IgnoreEnd
        }

        if FileExist(this.errLog) {
            try FileDelete(this.errLog)
        }

        if !XAMLHost.daemonHwnd {
            if (IsSet(XAML_IN_PROCESS_PREVIEW) && XAML_IN_PROCESS_PREVIEW) {
                if (!XAMLHost.daemonReceiver) {
                    XAMLHost.daemonReceiver := Gui()
                    DllCall("user32\ChangeWindowMessageFilterEx", "Ptr", XAMLHost.daemonReceiver.Hwnd, "UInt", 0x004A, "UInt", 1, "Ptr", 0)
                    if (!XAMLHost._msgHooked) {
                        OnMessage(0x004A, ObjBindMethod(XAMLHost, "OnCopyData"), 255)
                        XAMLHost._msgHooked := true
                    }
                }
                XAMLHost.InitializeInProcess(targetExe)
                engineType := XAMLHost.CLR_BridgeAssembly.GetType_2("AhkWpfEngine")
                static nullObj := ComValue(13, 0)
                args := ComObjArray(0xC, 1)
                args[0] := String(XAMLHost.daemonReceiver.Hwnd)
                XAMLHost.daemonHwnd := engineType.InvokeMember_3("StartInProcess", 0x158, nullObj, nullObj, args)
            } else {
                XAMLHost.Prewarm(targetExe)
                startWait := A_TickCount
                while (!XAMLHost.daemonHwnd && A_TickCount - startWait < 5000) {
                    Sleep(10)
                }
            }
        }
        return targetExe
    }

    _BuildTrackedCsv() {
        uniqueCsv := Map()
        for ctrlName in this.events
            uniqueCsv[ctrlName] := true
        for ctrlName in this.tracked
            uniqueCsv[ctrlName] := true
        trackedCsv := ""
        for name in uniqueCsv
            trackedCsv .= name ","
        return RTrim(trackedCsv, ",")
    }

    _BuildEventBindings() {
        eventBindings := ""
        for cName, events in this.events {
            for eName, evtList in events {
                eventBindings .= cName ":" eName ","
            }
        }
        return RTrim(eventBindings, ",")
    }

    _SendToEngine(payload) {
        if (!this.IsDevToolsWindow()) {
            XAMLHost.LogDevTools("OUT", payload)
        }
        buf := Buffer(StrPut(payload, "UTF-8"))
        StrPut(payload, buf, "UTF-8")
        cds := Buffer(A_PtrSize * 3)
        NumPut("Ptr", 0, cds, 0)
        NumPut("UInt", buf.Size, cds, A_PtrSize)
        NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)
        DllCall("user32\SendMessageW", "Ptr", XAMLHost.daemonHwnd, "UInt", 0x004A, "Ptr", 0, "Ptr", cds.Ptr)
    }

    Show(assetPath := "") {
        targetExe := this._EnsureDaemon()
        if (targetExe == "")
            return

        trackedCsv := this._BuildTrackedCsv()

        if (assetPath != "") {
            ; File-based asset path (BAML or .bin)
            ; Build event bindings from runtime registrations (includes events added after ExportBAML)
            eventBindings := this._BuildEventBindings()
            payload := "CREATE_WINDOW|" this.id "|" trackedCsv "|" A_ScriptName "|" String(this.ownerHwnd) "|" assetPath "|" eventBindings
            this.wpfHwnd := 0
            this._SendToEngine(payload)
        } else {
            ; Inline mode: embed XAML + events directly in the CREATE_WINDOW message
            ; This eliminates the Engine|Ready -> XAML_PAYLOAD round-trip entirely
            eventBindings := this._BuildEventBindings()
            cleanXaml := StrReplace(this.xaml, "%resources%", "")
            inlinePayload := cleanXaml "`n---AHK-XAML-EVENTS---`n" eventBindings
            payload := "CREATE_WINDOW_INLINE|" this.id "|" trackedCsv "|" A_ScriptName "|" String(this.ownerHwnd) "|" inlinePayload

            ; CRITICAL: Reset wpfHwnd BEFORE sending, not after.
            ; _SendToEngine uses SendMessageW which may trigger LoadedHwnd reentrantly
            ; (the daemon's Dispatcher can process the BeginInvoke during the synchronous wait).
            ; If we reset AFTER, we clobber the valid HWND set by the LoadedHwnd handler.
            this.wpfHwnd := 0
            this._SendToEngine(payload)
        }

        SetTimer(ObjBindMethod(this, "CheckForCrashes"), 50)
    }

    static LogDevTools(dir, payload) {
        try {
            if (IsSet(XAML_DevTools_Instance) && IsObject(XAML_DevTools_Instance) && HasMethod(XAML_DevTools_Instance, "LogIPC")) {
                SetTimer(LogIPCCallback, -1)
            }
        }

        LogIPCCallback() {
            try {
                if (IsSet(XAML_DevTools_Instance) && IsObject(XAML_DevTools_Instance) && HasMethod(XAML_DevTools_Instance, "LogIPC")) {
                    XAML_DevTools_Instance.LogIPC(dir, payload)
                }
            }
        }
    }

    static OnCopyData(wParam, lParam, msg, hwnd) {
        if (msg != 0x004A)
            return 0

        lpData := NumGet(lParam, A_PtrSize * 2, "Ptr")
        payload := StrGet(lpData, "UTF-8")
        parts := StrSplit(payload, "|")
        if (parts.Length >= 3) {
            isDevTools := false
            if (IsSet(XAML_DevTools_Instance) && IsObject(XAML_DevTools_Instance) && HasProp(XAML_DevTools_Instance, "app") && XAML_DevTools_Instance.app && HasProp(XAML_DevTools_Instance.app, "host") && XAML_DevTools_Instance.app.host) {
                isDevTools := (parts[2] == XAML_DevTools_Instance.app.host.id)
            }
            if (!isDevTools) {
                XAMLHost.LogDevTools("IN", payload)
            }
        }
        if (!IsSet(XAML_ENABLE_LOGGING) || XAML_ENABLE_LOGGING)
            try FileAppend("OnCopyData: " payload "`n", A_Temp "\AhkWpf\AhkTrace.log", "UTF-8")
        if (!InStr(payload, "EVENT|") && !InStr(payload, "DAEMON|") && !InStr(payload, "MRESPONSE|"))
            return 0

        lines := StrSplit(payload, "`n", "`r")
        parts := StrSplit(lines[1], "|", , 5)

        if (parts[1] == "DAEMON" && parts[2] == "Ready") {
            XAMLHost.daemonHwnd := Integer(parts[3])
            return 1
        }

        ; Handle MQUERY responses (targeted query results)
        if (parts[1] == "MRESPONSE") {
            winId := parts[2]
            if !XAMLHost._instances.Has(winId)
                return 0
            inst := XAMLHost._instances[winId]
            ; Parse length-prefixed state lines from lines[2..n]
            resultMap := Map()
            Loop lines.Length {
                if (A_Index == 1 || lines[A_Index] == "")
                    continue
                pos := InStr(lines[A_Index], "=")
                if pos {
                    k := SubStr(lines[A_Index], 1, pos - 1)
                    resultMap[k] := XAMLHost.DecodeValue(SubStr(lines[A_Index], pos + 1))
                }
            }
            inst._queryResult := resultMap
            inst._queryWaiting := false
            return 1
        }

        if (parts.Length < 4)
            return 0

        winId := parts[2], ctrlName := parts[3], eventName := parts[4]
        if (eventName == "WebMessageReceived") {
            try FileAppend("AHK OnCopyData WebMessageReceived: " payload "`n", A_Temp "\AhkWebViewDebug.log")
        }
        if !XAMLHost._instances.Has(winId)
            return 0

        instance := XAMLHost._instances[winId]

        if (ctrlName == "Engine" && eventName == "Error") {
            ; The payload contains newlines which were truncated by StrSplit(lines[1])
            ; Re-extract from the original message to get the full exception!
            pos := InStr(payload, "|Engine|Error|")
            if (pos) {
                rawPayload := SubStr(payload, pos + 14)
                errorMsg := XAMLHost.DecodeValue(rawPayload)
            } else {
                errorMsg := XAMLHost.DecodeValue(parts[5])
            }

            ahkLine := "Unknown"
            snippet := ""
            reason := ""
            if RegExMatch(errorMsg, "s)AHK_LINE:(.*?)\nXAML_SNIPPET:(.*?)\nREASON:(.*?)\n\n(.*)", &m) {
                ahkLine := m[1]
                snippet := m[2]
                reason := m[3]
                errorMsg := m[4]
            } else if RegExMatch(errorMsg, "s)AHK_LINE:(.*?)\nXAML_SNIPPET:(.*?)\n\n(.*)", &m) {
                ahkLine := m[1]
                snippet := m[2]
                errorMsg := m[3]
            }

            header := "The Background Engine crashed! Details below:"
            if (ahkLine != "Unknown") {
                header := "Engine crashed while rendering AHK Line " ahkLine "!"
            }

            lineNum := 0, colNum := 0
            if (RegExMatch(errorMsg, "i)Line\s*(?:number)?\s*['`"]?(\d+)['`"]?\s*(?:and|,)?\s*(?:line)?\s*position\s*['`"]?(\d+)['`"]?", &match)) {
                lineNum := Integer(match[1])
                colNum := Integer(match[2])
            }

            hasRetry := (IsSet(XAML_DIAGNOSTICS_ENABLED) && XAML_DIAGNOSTICS_ENABLED && lineNum > 0)

            while (true) {
                action := XAMLHost.ShowErrorDialog("Engine Crash", header, snippet, errorMsg, hasRetry, reason)
                if (action == "skip_property") {
                    if (instance.SkipPropertyAndRetry(errorMsg, lineNum, colNum)) {
                        break
                    }
                } else if (action == "skip_element") {
                    if (instance.SkipElementAndRetry(errorMsg, lineNum, colNum)) {
                        break
                    }
                } else {
                    ExitApp()
                }
            }
            return 1
        }

        if (ctrlName == "Engine" && eventName == "Ready") {
            targetHwnd := Integer(parts[5])

            eventBindings := ""
            for cName, events in instance.events {
                for eName, evtList in events {
                    eventBindings .= cName ":" eName ","
                }
            }
            eventBindings := RTrim(eventBindings, ",")

            payload := "XAML_PAYLOAD|" instance.xaml "`n---AHK-XAML-EVENTS---`n" eventBindings
            buf := Buffer(StrPut(payload, "UTF-8"))
            StrPut(payload, buf, "UTF-8")

            cds := Buffer(A_PtrSize * 3)
            NumPut("Ptr", 0, cds, 0)
            NumPut("UInt", buf.Size, cds, A_PtrSize)
            NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)

            DllCall("user32\SendMessageW", "Ptr", targetHwnd, "UInt", 0x004A, "Ptr", 0, "Ptr", cds.Ptr)
            payload := ""
            buf := ""
            return 1
        }

        if (ctrlName == "Window" && eventName == "LoadedHwnd") {
            instance.wpfHwnd := Integer(parts[5])
            if instance.HasOwnProp("_updateQueue") {
                for item in instance._updateQueue {
                    if (item.type == "single")
                        instance.Update(item.ctrl, item.prop, item.val)
                    else if (item.type == "batch")
                        instance.BatchUpdate(item.arr)
                }
                instance._updateQueue := []
            }
        }
        if (ctrlName == "Window" && eventName == "Closed") {
            instance.wpfHwnd := 0
        }

        stateMap := Map()

        eventData := ""
        if (parts.Length >= 5) {
            prefix := "EVENT|" winId "|" ctrlName "|" eventName "|"
            pos := InStr(payload, prefix)
            if (pos) {
                rawPayload := SubStr(payload, pos + StrLen(prefix))
                eventData := XAMLHost.DecodeValue(rawPayload)
            } else {
                eventData := XAMLHost.DecodeValue(parts[5])
            }
            if (eventData != "")
                stateMap[eventName] := eventData
        }

        if (eventName == "Drop" && eventData != "") {
            stateMap["DropFiles"] := StrSplit(eventData, "|")
        }
        if (eventName == "DragMove" && eventData != "") {
            stateMap["DragCoords"] := eventData
        }

        Loop lines.Length {
            if (A_Index == 1 || lines[A_Index] == "")
                continue
            pos := InStr(lines[A_Index], "=")
            if pos {
                k := SubStr(lines[A_Index], 1, pos - 1)
                stateMap[k] := XAMLHost.DecodeValue(SubStr(lines[A_Index], pos + 1))
            }
        }

        baseEventName := eventName
        extraArg := ""
        if InStr(eventName, ":") {
            parts := StrSplit(eventName, ":")
            baseEventName := parts[1]
            extraArg := parts[2]
        }

        hasEvent := instance.events.Has(ctrlName) && instance.events[ctrlName].Has(baseEventName)
        if (!IsSet(XAML_ENABLE_LOGGING) || XAML_ENABLE_LOGGING) {
            try FileAppend("OnCopyData dispatch check: " ctrlName "." baseEventName " hasEvent=" (hasEvent ? "true" : "false") " eventsCount=" (instance.events.Has(ctrlName) ? instance.events[ctrlName].Count : 0) "`n", A_Temp "\AhkWpf\AhkTrace.log", "UTF-8")
        }

        if (instance.events.Has(ctrlName) && instance.events[ctrlName].Has(baseEventName)) {
            if (baseEventName == "SelectionBox" || baseEventName == "CtrlSelectionBox") {
                str := ""
                for k, v in stateMap
                    str .= k "=" v ", "
                if (!IsSet(XAML_ENABLE_LOGGING) || XAML_ENABLE_LOGGING)
                    try FileAppend("OnCopyData SelectionBox: " str "`n", A_ScriptDir "\debug.log")
            }
            evtList := instance.events[ctrlName][baseEventName]
            for evtObj in evtList {
                cb := evtObj.Callback

                ; Handle optional event key args without breaking older 3-param callbacks
                if (extraArg != "")
                    SetTimer(cb.Bind(stateMap, ctrlName, { Key: extraArg }), -1, evtObj.Priority)
                else
                    SetTimer(cb.Bind(stateMap, ctrlName, baseEventName), -1, evtObj.Priority)
            }
        }
        return 1
    }

    ; =========================================================================
    ; Length-Prefixed Value Decoder (replaces Base64)
    ; Format: "BYTELEN:rawvalue" — e.g. "16:Hello😀 Worl|d"
    ; Falls back to base64 if value doesn't match length-prefix pattern.
    ; =========================================================================

    static DecodeValue(encoded) {
        if (encoded == "")
            return ""
        ; Length-prefixed format: "123:actual value here"
        if RegExMatch(encoded, "^(\d+):", &m) {
            byteLen := Integer(m[1])
            valueStart := m.Pos[0] + m.Len[0]
            rawAfterColon := SubStr(encoded, valueStart)
            if (byteLen == 0)
                return ""
            ; Count how many chars span byteLen UTF-8 bytes
            charCount := XAMLHost.UTF8BytesToCharCount(rawAfterColon, byteLen)
            return SubStr(rawAfterColon, 1, charCount)
        }
        ; Fallback: legacy base64 (safe to remove after long-term testing)
        return XAMLHost.Base64Decode(encoded)
    }

    ; Count how many characters span targetBytes UTF-8 bytes starting from the beginning of str
    static UTF8BytesToCharCount(str, targetBytes) {
        bytes := 0
        chars := 0
        sLen := StrLen(str)
        while (bytes < targetBytes && chars < sLen) {
            cp := Ord(SubStr(str, chars + 1, 1))
            if (cp <= 0x7F)
                bytes += 1
            else if (cp <= 0x7FF)
                bytes += 2
            else if (cp >= 0xD800 && cp <= 0xDBFF) {
                ; Surrogate pair in UTF-16 → 4 bytes in UTF-8
                bytes += 4
                chars += 1  ; skip low surrogate
            }
            else if (cp <= 0xFFFF)
                bytes += 3
            else
                bytes += 4
            chars++
        }
        return chars
    }

    ; =========================================================================
    ; Query API — on-demand value reads from the WPF process
    ; Supports single, multi, and wildcard (*) queries
    ; =========================================================================

    ; Query specific control values on-demand.
    ; Usage:
    ;   val := ui.Query("TxtName")              ; single → string
    ;   state := ui.Query("TxtName", "SldPower") ; multi → Map
    ;   all := ui.Query("*")                     ; wildcard → Map of all tracked
    Query(names*) {
        if (!this.wpfHwnd || names.Length == 0)
            return (names.Length == 1) ? "" : Map()

        ; Build CSV of control names
        csv := ""
        for n in names
            csv .= n ","
        csv := RTrim(csv, ",")

        ; Send MQUERY to the WPF engine
        payload := "MQUERY|" csv
        buf := Buffer(StrPut(payload, "UTF-8"))
        StrPut(payload, buf, "UTF-8")
        cds := Buffer(A_PtrSize * 3)
        NumPut("Ptr", 0, cds, 0)
        NumPut("UInt", buf.Size, cds, A_PtrSize)
        NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)

        this._queryResult := Map()
        this._queryWaiting := true
        DllCall("user32\SendMessageW", "Ptr", this.wpfHwnd, "UInt", 0x004A, "Ptr", 0, "Ptr", cds.Ptr)

        ; Wait for MRESPONSE (arrives via OnCopyData during message pump)
        startTick := A_TickCount
        while (this._queryWaiting && A_TickCount - startTick < 500)
            Sleep(1)

        result := this._queryResult
        this._queryResult := ""
        this._queryWaiting := false

        ; Single query returns a plain string; multi returns Map
        if (names.Length == 1 && names[1] != "*")
            return (Type(result) == "Map" && result.Has(names[1])) ? result[names[1]] : ""
        return Type(result) == "Map" ? result : Map()
    }

    ; =========================================================================
    ; Legacy Base64 — DEPRECATED, kept as fallback during transition.
    ; TODO: Remove after long-term testing confirms length-prefix works everywhere.
    ; =========================================================================

    static Base64Encode(str) {
        if (str == "")
            return ""
        buf := Buffer(StrPut(str, "UTF-8"))
        StrPut(str, buf, "UTF-8")
        DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x00000001, "Ptr", 0, "UInt*", &size := 0)
        b64 := Buffer(size * 2)
        DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x00000001, "Ptr", b64, "UInt*", &size)
        return StrReplace(StrReplace(StrGet(b64, "UTF-16"), "`r", ""), "`n", "")
    }

    static Base64Decode(b64) {
        if (b64 == "")
            return ""
        size := 0
        DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        buf := Buffer(size)
        DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        return StrGet(buf, "UTF-8")
    }

    GetCharIndex(xaml, lineNumber, linePosition) {
        pos := 1
        Loop lineNumber - 1 {
            nextNewline := RegExMatch(xaml, "\r?\n", &m, pos)
            if (!nextNewline)
                break
            pos := nextNewline + m.Len[0]
        }
        return pos + linePosition - 1
    }

    FindElementBoundaries(xaml, index) {
        ; Find the start of the tag enclosing 'index'
        tagStart := 0
        p := index
        while (p > 0) {
            char := SubStr(xaml, p, 1)
            if (char == "<") {
                nextChar := SubStr(xaml, p + 1, 1)
                if (nextChar != "!" && nextChar != "/") {
                    tagStart := p
                    break
                }
            }
            p--
        }
        if (!tagStart)
            return ""

        ; Extract tag name
        subXaml := SubStr(xaml, tagStart)
        if (!RegExMatch(subXaml, "^<([\w:]+)", &m))
            return ""
        tagName := m[1]

        ; Check if it's self-closing before any nested tag of same name
        firstGt := InStr(xaml, ">", , tagStart)
        if (firstGt) {
            sub := SubStr(xaml, tagStart, firstGt - tagStart + 1)
            if (RegExMatch(sub, "/\s*>$")) {
                return { start: tagStart, end: firstGt, tag: tagName }
            }
        }

        ; Not self-closing, scan for matching </tagName>
        depth := 1
        pos := tagStart + 1
        len := StrLen(xaml)
        while (pos <= len) {
            char := SubStr(xaml, pos, 1)
            if (char == "<") {
                subAtPos := SubStr(xaml, pos)
                if (SubStr(xaml, pos + 1, 1) == "/") {
                    ; Closing tag?
                    if (RegExMatch(subAtPos, "^</" tagName "\s*>", &m)) {
                        depth--
                        if (depth == 0) {
                            return { start: tagStart, end: pos + m.Len[0] - 1, tag: tagName }
                        }
                        pos += m.Len[0]
                        continue
                    }
                } else {
                    ; Opening tag?
                    if (RegExMatch(subAtPos, "^<" tagName "\b", &m)) {
                        depth++
                        pos += m.Len[0]
                        continue
                    }
                }
            }
            pos++
        }
        return ""
    }

    GetPropertyCandidates(errorMsg) {
        firstLine := StrSplit(errorMsg, "`n")[1]
        candidates := []
        pos := 1
        while (RegExMatch(firstLine, "[" . Chr(39) . Chr(34) . "]([\w\.:]+)[" . Chr(39) . Chr(34) . "]", &m, pos)) {
            val := m[1]
            candidates.Push(val)
            if (InStr(val, ".")) {
                parts := StrSplit(val, ".")
                if (parts.Length >= 2) {
                    candidates.Push(parts[parts.Length - 1] . "." . parts[parts.Length])
                }
                candidates.Push(parts[parts.Length])
            }
            pos := m.Pos[0] + m.Len[0]
        }
        return candidates
    }

    SkipPropertyAndRetry(errorMsg, lineNum, colNum) {
        if (lineNum <= 0 || colNum <= 0) {
            MsgBox("Could not locate the exact error position to skip the property.", "Skip Failed", "Iconx")
            return false
        }

        charIndex := this.GetCharIndex(this.xaml, lineNum, colNum)
        if (charIndex <= 0) {
            MsgBox("Error position out of bounds.", "Skip Failed", "Iconx")
            return false
        }

        elem := this.FindElementBoundaries(this.xaml, charIndex)
        if (!elem) {
            MsgBox("Could not find the element at the error line.", "Skip Failed", "Iconx")
            return false
        }

        openingTagEnd := InStr(this.xaml, ">", , elem.start)
        if (!openingTagEnd || openingTagEnd > elem.end) {
            MsgBox("Malformed element opening tag.", "Skip Failed", "Iconx")
            return false
        }
        openingTag := SubStr(this.xaml, elem.start, openingTagEnd - elem.start + 1)

        candidates := this.GetPropertyCandidates(errorMsg)

        removed := false
        candidateName := ""
        for candidate in candidates {
            ; Match attribute: candidate="..." or candidate='...'
            pat := "i)\b([\w:]*?" . candidate . ")\s*=\s*(?:" . Chr(34) . "[^" . Chr(34) . "]*" . Chr(34) . "|'[^']*')"
            if (RegExMatch(openingTag, pat)) {
                openingTag := RegExReplace(openingTag, pat, "")
                removed := true
                candidateName := candidate
                break
            }
        }

        if (!removed) {
            MsgBox("Could not automatically identify the property to skip from error: " errorMsg, "Skip Failed", "Iconx")
            return false
        }

        this.xaml := SubStr(this.xaml, 1, elem.start - 1) . openingTag . SubStr(this.xaml, openingTagEnd + 1)

        ToolTip("Skipped property: " candidateName)
        SetTimer(() => ToolTip(), -3000)

        SetTimer(() => this.Show(), -10)
        return true
    }

    SkipElementAndRetry(errorMsg, lineNum, colNum) {
        if (lineNum <= 0 || colNum <= 0) {
            MsgBox("Could not locate the exact error position to skip the element.", "Skip Failed", "Iconx")
            return false
        }

        charIndex := this.GetCharIndex(this.xaml, lineNum, colNum)
        if (charIndex <= 0) {
            MsgBox("Error position out of bounds.", "Skip Failed", "Iconx")
            return false
        }

        elem := this.FindElementBoundaries(this.xaml, charIndex)
        if (!elem) {
            MsgBox("Could not find the element to skip at the error line.", "Skip Failed", "Iconx")
            return false
        }

        this.xaml := SubStr(this.xaml, 1, elem.start - 1) . SubStr(this.xaml, elem.end + 1)

        ToolTip("Skipped element: <" elem.tag ">")
        SetTimer(() => ToolTip(), -3000)

        SetTimer(() => this.Show(), -10)
        return true
    }

    static RestoreWebView2Dlls() {
        if (!IsSet(XAML_ENABLE_WEBVIEW) || !XAML_ENABLE_WEBVIEW)
            return false
        libDir := ""
        SplitPath(A_LineFile, , &libDir)
        wvDir := libDir "\dep\WebView2"

        if (FileExist(wvDir "\Microsoft.Web.WebView2.Core.dll") &&
            FileExist(wvDir "\Microsoft.Web.WebView2.Wpf.dll") &&
            FileExist(wvDir "\WebView2Loader.dll")) {
            return false
        }

        loaderArch := (A_PtrSize == 8) ? "x64" : "x86"
        targetDlls := [
            wvDir "\Microsoft.Web.WebView2.Core.dll",
            wvDir "\Microsoft.Web.WebView2.Wpf.dll",
            wvDir "\WebView2Loader.dll"
        ]

        tmpDir := A_Temp "\AhkWpf\nuget_Microsoft_Web_WebView2"
        extractCmds := "Copy-Item '" tmpDir "\lib\net45\Microsoft.Web.WebView2.Core.dll' '" wvDir "\Microsoft.Web.WebView2.Core.dll' -Force; "
            . "Copy-Item '" tmpDir "\lib\net45\Microsoft.Web.WebView2.Wpf.dll' '" wvDir "\Microsoft.Web.WebView2.Wpf.dll' -Force; "
            . "Copy-Item '" tmpDir "\build\native\" loaderArch "\WebView2Loader.dll' '" wvDir "\WebView2Loader.dll' -Force"

        if XAMLHost.Downloader("Microsoft.Web.WebView2", "1.0.1722.45", "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.1722.45", wvDir, targetDlls, extractCmds) {
            try FileDelete(libDir "\dep\ahk-xaml-webview.dll")
            try FileDelete(A_Temp "\AhkWpf\ahk-xaml-webview.dll")
            return true
        }
        return false
    }

    ; Auto-download AvalonEdit from NuGet if not present in lib/dep/AvalonEdit/
    static RestoreAvalonEditDlls() {
        if (!IsSet(XAML_ENABLE_AVALONEDIT) || !XAML_ENABLE_AVALONEDIT)
            return false
        libDir := ""
        SplitPath(A_LineFile, , &libDir)
        aeDir := libDir "\dep\AvalonEdit"
        aeDll := aeDir "\ICSharpCode.AvalonEdit.dll"
        if FileExist(aeDll)
            return false

        tmpDir := A_Temp "\AhkWpf\nuget_AvalonEdit"
        extractCmds := "Copy-Item '" tmpDir "\lib\net462\ICSharpCode.AvalonEdit.dll' '" aeDll "' -Force"

        if XAMLHost.Downloader("AvalonEdit", "6.3.0.90", "https://www.nuget.org/api/v2/package/AvalonEdit/6.3.0.90", aeDir, [aeDll], extractCmds) {
            try FileDelete(libDir "\dep\ahk-xaml*.dll")
            try FileDelete(A_Temp "\AhkWpf\ahk-xaml*.dll")
            return true
        }
        return false
    }

    ; Auto-download DocumentFormat.OpenXml from NuGet if not present in lib/dep/OpenXml/
    static RestoreDocumentDlls() {
        if (!IsSet(XAML_ENABLE_DOCUMENT) || !XAML_ENABLE_DOCUMENT)
            return false
        libDir := ""
        SplitPath(A_LineFile, , &libDir)
        oxDir := libDir "\dep\OpenXml"
        oxDll := oxDir "\DocumentFormat.OpenXml.dll"
        if FileExist(oxDll)
            return false

        tmpDir := A_Temp "\AhkWpf\nuget_DocumentFormat_OpenXml"
        extractCmds := "Copy-Item '" tmpDir "\lib\net46\DocumentFormat.OpenXml.dll' '" oxDll "' -Force"

        if XAMLHost.Downloader("DocumentFormat.OpenXml", "2.20.0", "https://www.nuget.org/api/v2/package/DocumentFormat.OpenXml/2.20.0", oxDir, [oxDll], extractCmds) {
            try FileDelete(libDir "\dep\ahk-xaml*.dll")
            try FileDelete(A_Temp "\AhkWpf\ahk-xaml*.dll")
            return true
        }
        return false
    }

    ; Shared non-blocking rich GUI downloader helper
    static Downloader(packageName, version, url, installDir, targetDlls, extractCommands) {
        ; Create modern dark GUI
        pg := Gui("+AlwaysOnTop -MinimizeBox -SysMenu +ToolWindow", "AHK-XAML — Bootstrap Downloader")
        pg.SetFont("s10 bold", "Segoe UI")
        pg.BackColor := "0x11111b"

        pg.Add("Text", "x15 y12 w270 c89B4FA", "📦 Restoring Dependency")
        pg.SetFont("s9 norm", "Segoe UI")
        statusText := pg.Add("Text", "x15 y35 w270 h18 cCDD6F4", "Downloading " packageName " " version "...")
        progressBar := pg.Add("Progress", "x15 y58 w270 h6 c89B4FA Background313244 -Smooth +0x8", 50)
        pg.Show("w300 h78 NoActivate")

        ; Enable continuous marquee style (PBM_SETMARQUEE)
        SendMessage(0x040A, 1, 30, progressBar.Hwnd)

        tmpDir := A_Temp "\AhkWpf\nuget_" StrReplace(packageName, ".", "_")
        nupkg := tmpDir "\package.nupkg.zip"

        try {
            if !DirExist(A_Temp "\AhkWpf")
                DirCreate(A_Temp "\AhkWpf")
            if DirExist(tmpDir)
                DirDelete(tmpDir, true)
            DirCreate(tmpDir)
        }

        ; Generate PowerShell command
        q := Chr(34)
        psCmd := "powershell.exe -NoProfile -Command " q
            . "try { "
            . "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; "
            . "Invoke-WebRequest -Uri '" url "' -OutFile '" nupkg "' -UserAgent 'Mozilla/5.0'; "
            . "Expand-Archive -Path '" nupkg "' -DestinationPath '" tmpDir "' -Force; "
            . "if (!(Test-Path '" installDir "')) { New-Item -ItemType Directory -Force -Path '" installDir "' | Out-Null }; "
            . extractCommands "; "
            . "} catch { $_.Exception.Message | Out-File '" tmpDir "\err.txt' }"
            . q

        success := false
        try {
            ; Run background process
            Run(psCmd, "", "Hide", &pid)

            ; Wait and animate
            dots := ""
            loopCount := 0
            while ProcessExist(pid) {
                loopCount++
                if (Mod(loopCount, 15) == 0) {
                    dots .= "."
                    if (StrLen(dots) > 3)
                        dots := ""
                    statusText.Value := "Downloading and extracting " dots
                }
                Sleep(50)
            }

            ; Inspect completion results
            if FileExist(tmpDir "\err.txt") {
                errContent := FileRead(tmpDir "\err.txt")
                throw Error(errContent)
            }

            ; Check that all target DLLs now exist
            for dll in targetDlls {
                if !FileExist(dll)
                    throw Error("Failed to extract: " dll)
            }

            success := true
            statusText.Value := "✓ Installed successfully!"
            progressBar.Opt("cA6E3A1") ; premium success green
            progressBar.Value := 100
            Sleep(800)
        } catch as e {
            success := false
            statusText.Value := "✗ Failed!"
            progressBar.Opt("cF38BA8") ; premium error red
            progressBar.Value := 100

            ; Show standard error dialog or tooltip
            MsgBox("Failed to restore " packageName " " version ":`n`n" e.Message, "Bootstrap Restore Error", "Iconx AlwaysOnTop")
        }

        pg.Destroy()
        try DirDelete(tmpDir, true)
        return success
    }

    static InitializeInProcess(dllPath) {
        if (XAMLHost.CLR_Started)
            return XAMLHost.CLR_BridgeClass

        CLSID := Buffer(16), IID := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{CB2F6723-AB3A-11D2-9C40-00C04FA30A3E}", "Ptr", CLSID)
        DllCall("ole32\CLSIDFromString", "WStr", "{CB2F6722-AB3A-11D2-9C40-00C04FA30A3E}", "Ptr", IID)

        hr := DllCall("mscoree\CorBindToRuntimeEx"
            , "WStr", "v4.0.30319"
            , "Ptr", 0
            , "UInt", 0
            , "Ptr", CLSID, "Ptr", IID
            , "Ptr*", &pHost := 0, "Int")
        if (hr < 0)
            throw Error("CorBindToRuntimeEx failed: " Format("0x{:08X}", hr))

        ComCall(10, pHost, "Int")   ; ICorRuntimeHost::Start
        ComCall(13, pHost, "Ptr*", &pDomain := 0, "Int")  ; GetDefaultDomain

        XAMLHost.CLR_AppDomain := ComValue(9, pDomain)

        domType := XAMLHost.CLR_AppDomain.GetType()
        mscorlib := domType.Assembly
        asmType := mscorlib.GetType_2("System.Reflection.Assembly")
        static nullObj := ComValue(13, 0)

        ; Pre-load all dependency DLLs in the directory first to ensure type loader references resolve successfully
        SplitPath(dllPath, &dllName, &dllDir)
        Loop Files, dllDir "\*.dll" {
            if (A_LoopFileName == dllName)
                continue
            try {
                depFileObj := FileOpen(A_LoopFileFullPath, "r")
                depSize := depFileObj.Length
                depBuf := Buffer(depSize)
                depFileObj.Pos := 0
                depFileObj.RawRead(depBuf, depSize)
                depFileObj.Close()

                depBytes := ComObjArray(0x11, depSize)
                depPvData := 0
                DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(depBytes), "Ptr*", &depPvData)
                DllCall("ntdll\RtlMoveMemory", "Ptr", depPvData, "Ptr", depBuf.Ptr, "Ptr", depSize)
                DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(depBytes))

                depLoadArgs := ComObjArray(0xC, 1)
                depLoadArgs[0] := depBytes
                asmType.InvokeMember_3("Load", 0x158, nullObj, nullObj, depLoadArgs)
            }
        }

        fileObj := FileOpen(dllPath, "r")
        fileSize := fileObj.Length
        rawBuf := Buffer(fileSize)
        fileObj.Pos := 0
        fileObj.RawRead(rawBuf, fileSize)
        fileObj.Close()

        bytes := ComObjArray(0x11, fileSize)
        pvData := 0
        DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(bytes), "Ptr*", &pvData)
        DllCall("ntdll\RtlMoveMemory", "Ptr", pvData, "Ptr", rawBuf.Ptr, "Ptr", fileSize)
        DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(bytes))

        loadArgs := ComObjArray(0xC, 1)
        loadArgs[0] := bytes
        bridgeAsm := asmType.InvokeMember_3("Load", 0x158, nullObj, nullObj, loadArgs)

        XAMLHost.CLR_BridgeAssembly := bridgeAsm
        try bridgeAsm.CreateInstance("AhkInProcessBootstrapper") ; Hook AssemblyResolve event
        XAMLHost.CLR_BridgeClass := bridgeAsm.CreateInstance("AhkWpfEngine")
        XAMLHost.CLR_Started := true

        return XAMLHost.CLR_BridgeClass
    }

    static DockWindow(childHwnd, parentHwnd, x := 0, y := 0, width := 0, height := 0) {
        ; 1. Set the parent relationship
        DllCall("user32\SetParent", "Ptr", childHwnd, "Ptr", parentHwnd, "Ptr")

        ; 2. Modify window styles: clear WS_POPUP, WS_CAPTION, WS_THICKFRAME
        ; and set WS_CHILD, WS_VISIBLE, WS_CLIPSIBLINGS
        GWL_STYLE := -16
        WS_POPUP := 0x80000000
        WS_CHILD := 0x40000000
        WS_VISIBLE := 0x10000000
        WS_CLIPSIBLINGS := 0x04000000
        WS_CAPTION := 0x00C00000
        WS_THICKFRAME := 0x00040000

        styles := DllCall("user32\GetWindowLongW", "Ptr", childHwnd, "Int", GWL_STYLE, "Int")
        styles := (styles & ~WS_POPUP & ~WS_CAPTION & ~WS_THICKFRAME) | WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS
        DllCall("user32\SetWindowLongW", "Ptr", childHwnd, "Int", GWL_STYLE, "Ptr", styles, "Ptr")

        ; 3. Resize and position child window
        if (width > 0 && height > 0) {
            DllCall("user32\MoveWindow", "Ptr", childHwnd, "Int", x, "Int", y, "Int", width, "Int", height, "Int", 1, "Int")
        }
    }
}

XAML_TEMPLATE := '
(
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            xmlns:sys="clr-namespace:System;assembly=mscorlib"
            xmlns:primitives="clr-namespace:System.Windows.Controls.Primitives;assembly=PresentationFramework"
            Width="%Width%" Height="%Height%"
            ResizeMode="%ResizeMode%"
            WindowStyle="None" AllowsTransparency="False" Background="Transparent"
            WindowStartupLocation="CenterScreen"
            TextElement.Foreground="{DynamicResource TextMain}" FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif">
        
        <WindowChrome.WindowChrome>
            <WindowChrome GlassFrameThickness="-1" CaptionHeight="%CaptionHeight%" CornerRadius="{DynamicResource WindowRadius}" />
        </WindowChrome.WindowChrome>
    
        <Window.Resources>
            <sys:Double x:Key="TitleBarHeight">%CaptionHeight%</sys:Double>
            <SolidColorBrush x:Key="BgColor" Color="#1E1E1E" />
            <SolidColorBrush x:Key="TitleBarColor" Color="Transparent" />
            <SolidColorBrush x:Key="TitleBarForeground" Color="#FFFFFF" />
            <SolidColorBrush x:Key="TextMain" Color="#FFFFFF" />
            <SolidColorBrush x:Key="TextSub" Color="#CCCCCC" />
            <SolidColorBrush x:Key="SidebarColor" Color="#252526" />
            <SolidColorBrush x:Key="ControlBg" Color="#333333" />
            <SolidColorBrush x:Key="ControlBorder" Color="#2D2D2D" />
            <CornerRadius x:Key="WindowRadius">12</CornerRadius>
            <Thickness x:Key="WindowBorderThickness">0</Thickness>
            <SolidColorBrush x:Key="WindowBorderBrush" Color="Transparent" />
            <sys:Double x:Key="TitleBarGradientOpacity">0</sys:Double>
            %resources%
        </Window.Resources>
    
        %app%
    </Window>
)'

; We no longer inject the massive xaml.components.xaml styles into every single window's XAML string.
; Instead, they are parsed exactly once in the background .NET daemon on startup and loaded into application-level resources,
; yielding a ~98% reduction in parsed XAML size per window and near-instant window creation/tear-off.
