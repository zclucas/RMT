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
    static _instances := Map()
    static _msgHooked := false
    static daemonHwnd := 0
    static daemonReceiver := 0
    static instanceCounter := 0
    static _appDir := ""

    static GetAppDir() {
        if (XAMLHost._appDir != "")
            return XAMLHost._appDir
        
        ; 优先级: 1. 编译后的脚本目录 2. 库文件所在目录
        if (A_IsCompiled) {
            XAMLHost._appDir := A_ScriptDir
        } else {
            SplitPath(A_LineFile, , &libDir)
            XAMLHost._appDir := libDir "\.."
        }
        
        ; 创建必要的子目录
        if !DirExist(XAMLHost._appDir "\Logs")
            DirCreate(XAMLHost._appDir "\Logs")
        if !DirExist(XAMLHost._appDir "\Cache")
            DirCreate(XAMLHost._appDir "\Cache")
            
        return XAMLHost._appDir
    }

    __New(xaml := "", exePath := "", ownerHwnd := 0) {
        XAMLHost.RestoreWebView2Dlls()
        XAMLHost.instanceCounter++
        this.id := "WPF_" A_TickCount "_" XAMLHost.instanceCounter "_" Random(1000, 9999)
        XAMLHost._instances[this.id] := this
        this.xaml := xaml
        this.exePath := exePath
        this.ownerHwnd := ownerHwnd
        this.events := Map()
        this.tracked := Map()
        this.wpfHwnd := 0
        this.pid := 0
        this.errLog := XAMLHost.GetAppDir() "\Logs\AhkWpfError.log"


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
        this.events[controlName][eventName].Push({ Callback: callback, Priority: priority })
    }

    Track(controlName) {
        this.tracked[controlName] := true
    }

    Update(controlName, propertyName, valueStr) {
        if !this.wpfHwnd
            return
        val := StrReplace(valueStr, "`r", "&#x0D;")
        val := StrReplace(val, "`n", "&#x0A;")
        payload := controlName "|" propertyName "|" val
        buf := Buffer(StrPut(payload, "UTF-8"))
        StrPut(payload, buf, "UTF-8")

        cds := Buffer(A_PtrSize * 3)
        NumPut("Ptr", 0, cds, 0)
        NumPut("UInt", buf.Size, cds, A_PtrSize)
        NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)

        DllCall("user32\SendMessageW", "Ptr", this.wpfHwnd, "UInt", 0x004A, "Ptr", 0, "Ptr", cds.Ptr)
    }

    BatchUpdate(updatesArray) {
        if (!this.wpfHwnd)
            return

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

        baseDllName := (IsSet(XAML_ENABLE_WEBVIEW) && XAML_ENABLE_WEBVIEW) ? "ahk-xaml-webview.dll" : "ahk-xaml.dll"

        SplitPath(A_LineFile, , &libDir)
        sharedExe := libDir "\" baseDllName

        if (A_IsCompiled && FileExist(A_ScriptDir "\Plugins\AHK-XAML\lib\" baseDllName)) {
            targetExe := A_ScriptDir "\Plugins\AHK-XAML\lib\" baseDllName
        } else if (!A_IsCompiled) {
            sourceCs := libDir "\XAML_AHK_Bridge.cs"
            if (FileExist(sourceCs) && FileExist(sharedExe) && FileGetTime(sourceCs) > FileGetTime(sharedExe)) {
                try {
                    while ProcessExist("ahk-xaml.dll") {
                        ProcessClose("ahk-xaml.dll")
                        Sleep(50)
                    }
                    while ProcessExist("ahk-xaml-webview.dll") {
                        ProcessClose("ahk-xaml-webview.dll")
                        Sleep(50)
                    }
                }
                try FileDelete(sharedExe)
            }
            if !FileExist(sharedExe) {
                if !XAMLHost.CompileEngine(libDir, sharedExe)
                    return
            }
            targetExe := sharedExe
            XAMLHost.RestoreWebView2Dlls()
        } else {
            MsgBox("Error: " baseDllName " not found.`nExpected: " A_ScriptDir "\Plugins\AHK-XAML\lib\" baseDllName, "AHK-XAML", "Iconx")
            return
        }

        logArg := (IsSet(XAML_ENABLE_LOGGING) && !XAML_ENABLE_LOGGING) ? ' --no-log' : ''
        Run('"' targetExe '" --daemon "' ProcessExist() '" "' String(XAMLHost.daemonReceiver.Hwnd) '"' logArg, "", "Hide")
    }

    CheckForCrashes() {
        if (this.wpfHwnd != 0) {
            SetTimer(ObjBindMethod(this, "CheckForCrashes"), 0)
            return
        }
        if FileExist(this.errLog) {
            SetTimer(ObjBindMethod(this, "CheckForCrashes"), 0)
            err := FileRead(this.errLog)
            FileDelete(this.errLog)

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
            snipLbl := errGui.Add("Text", "y+15", "Generated XAML Snippet:")
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

        tempTxt := XAMLHost.GetAppDir() "\Cache\gui_temp.txt"

        if FileExist(tempTxt)
            FileDelete(tempTxt)
        FileAppend(payload, tempTxt, "UTF-8")

        targetExe := (this.exePath != "") ? this.exePath : ""
        SplitPath(A_LineFile, , &libDir)
        sharedExe := libDir "\ahk-xaml.dll"

        if (A_IsCompiled && FileExist(A_ScriptDir "\Plugins\AHK-XAML\lib\ahk-xaml.dll")) {
            targetExe := A_ScriptDir "\Plugins\AHK-XAML\lib\ahk-xaml.dll"
        } else if (!A_IsCompiled) {
            sourceCs := libDir "\XAML_AHK_Bridge.cs"
            if (FileExist(sourceCs) && FileExist(sharedExe) && FileGetTime(sourceCs) > FileGetTime(sharedExe)) {
                try {
                    while ProcessExist("ahk-xaml.dll") {
                        ProcessClose("ahk-xaml.dll")
                        Sleep(50)
                    }
                    while ProcessExist("ahk-xaml-webview.dll") {
                        ProcessClose("ahk-xaml-webview.dll")
                        Sleep(50)
                    }
                }
                try FileDelete(sharedExe)
            }
            if !FileExist(sharedExe) {
                if !XAMLHost.CompileEngine(libDir, sharedExe)
                    return
            }
            targetExe := sharedExe
        }

        if !FileExist(targetExe) {
            MsgBox("Fatal Error: Could not locate ahk-xaml.dll to perform compilation.", "AHK-XAML", "Iconx")
            return
        }

        RunWait('"' targetExe '" --compress "' tempTxt '" "' filePath '"', "", "Hide")

        if FileExist(tempTxt)
            FileDelete(tempTxt)
    }

    static CompileEngine(libDir, sharedExe, extraResources := []) {
        XAMLHost.RestoreWebView2Dlls()
        errLog := XAMLHost.GetAppDir() "\Logs\AhkWpfError.log"
        sourceCs := libDir "\XAML_AHK_Bridge.cs"
        if !FileExist(sourceCs) {
            MsgBox("XAML_AHK_Bridge.cs not found in lib directory!`nCannot compile shared engine.", "AHK-XAML", "Iconx")
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
            coreDll := libDir "\WebView2\Microsoft.Web.WebView2.Core.dll"
            wpfDll := libDir "\WebView2\Microsoft.Web.WebView2.Wpf.dll"
            if (FileExist(coreDll) && FileExist(wpfDll)) {
                wvRefs := ' /reference:"' coreDll '" /reference:"' wpfDll '"'
                wvDef := ' /define:ENABLE_WEBVIEW'
            } else {
                ToolTip("WebView2 DLLs not found in lib\WebView2. Compiling without WebView2 support.")
                SetTimer(() => ToolTip(), -4000)
            }
        }

        gifDll := libDir "\WpfAnimatedGif.dll"
        gifRef := FileExist(gifDll) ? ' /reference:"' gifDll '"' : ""

        mdDll := libDir "\MaterialDesignThemes.Wpf.dll"
        mdRef := FileExist(mdDll) ? ' /reference:"' mdDll '"' : ""

        ; Embed component resources directly into the DLL for zero-disk-IO loading
        embeddedRes := ""
        bamlPath := libDir "\xaml.components.baml"
        xamlPath := libDir "\xaml.components.xaml"
        if FileExist(bamlPath) {
            embeddedRes .= ' /resource:"' bamlPath '"'
        } else if FileExist(xamlPath) {
            embeddedRes .= ' /resource:"' xamlPath '"'
        }

        for _, res in extraResources {
            if FileExist(res)
                embeddedRes .= ' /resource:"' res '"'
        }

        cmd := A_ComSpec ' /c ""' cscPath '" /nologo /target:winexe /platform:anycpu /out:"' sharedExe '" /lib:"' wpfDir '" /reference:System.dll /reference:System.Core.dll /reference:System.Xml.dll /reference:PresentationFramework.dll /reference:PresentationCore.dll /reference:WindowsBase.dll /reference:System.Xaml.dll /reference:UIAutomationProvider.dll /reference:UIAutomationTypes.dll' wvRefs gifRef mdRef wvDef embeddedRes ' "' sourceCs '" > "' errLog '" 2>&1"'
        RunWait(cmd, "", "Hide")

        if !FileExist(sharedExe) {
            errOut := FileExist(errLog) ? FileRead(errLog) : "Unknown compilation error."
            XAMLHost.ShowErrorDialog("Engine Compile Error", "Failed to compile background engine.", "", errOut)
            return false
        }
        return true
    }

    BundleCustomEngine(targetExe) {
        cleanXaml := StrReplace(this.xaml, "%resources%", "")
        cleanXaml := StrReplace(cleanXaml, "%components%", "")
        
        tempDir := XAMLHost.GetAppDir() "\Cache"
        
        tempXaml := tempDir "\app_payload.xaml"
        tempBaml := tempDir "\app_payload.baml"
        tempEvents := tempDir "\app_payload.events"
        
        try FileDelete(tempXaml)
        try FileDelete(tempBaml)
        try FileDelete(tempEvents)
        
        FileAppend(cleanXaml, tempXaml, "UTF-8")
        
        SplitPath(A_LineFile, , &libDir)
        toolPath := libDir "\..\tools\compile_baml.ps1"
        if FileExist(toolPath) {
            cmd := 'powershell.exe -ExecutionPolicy Bypass -File "' toolPath '" -InputXaml "' tempXaml '" -OutputBaml "' tempBaml '"'
            RunWait(cmd, "", "Hide")
        }
        
        eventsStr := ""
        for ctrlName, evtMap in this.events {
            for evtName, arr in evtMap {
                eventsStr .= ctrlName ":" evtName ","
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
            MsgBox("Failed to compile BAML during bundle export! Check the compiler log.", "AHK-XAML", "Iconx")
            return false
        }
        
        if FileExist(tempEvents)
            resList.Push(tempEvents)
            
        try {
            while ProcessExist(targetExe) {
                ProcessClose(targetExe)
                Sleep(50)
            }
            FileDelete(targetExe)
        }
            
        success := XAMLHost.CompileEngine(libDir, targetExe, resList)
        
        try FileDelete(tempXaml)
        try FileDelete(tempBaml)
        try FileDelete(tempEvents)
        
        return success
    }

    _EnsureDaemon() {
        baseDllName := (IsSet(XAML_ENABLE_WEBVIEW) && XAML_ENABLE_WEBVIEW) ? "ahk-xaml-webview.dll" : "ahk-xaml.dll"
        SplitPath(A_LineFile, , &libDir)
        sharedExe := libDir "\" baseDllName
        if XAMLHost.daemonHwnd
            return sharedExe

        if FileExist(this.errLog)
            FileDelete(this.errLog)

        if (A_IsCompiled && FileExist(A_ScriptDir "\Plugins\AHK-XAML\lib\" baseDllName)) {
            targetExe := A_ScriptDir "\Plugins\AHK-XAML\lib\" baseDllName
        } else if (!A_IsCompiled) {
            sourceCs := libDir "\XAML_AHK_Bridge.cs"
            if (FileExist(sourceCs) && FileExist(sharedExe) && FileGetTime(sourceCs) > FileGetTime(sharedExe)) {
                try {
                    while ProcessExist("ahk-xaml.dll") {
                        ProcessClose("ahk-xaml.dll")
                        Sleep(50)
                    }
                    while ProcessExist("ahk-xaml-webview.dll") {
                        ProcessClose("ahk-xaml-webview.dll")
                        Sleep(50)
                    }
                }
                try FileDelete(sharedExe)
            }
            if !FileExist(sharedExe) {
                if !XAMLHost.CompileEngine(libDir, sharedExe)
                    return ""
            }
            targetExe := sharedExe

            XAMLHost.RestoreWebView2Dlls()
        } else {
            MsgBox("Error: " baseDllName " not found.`nExpected: " A_ScriptDir "\Plugins\AHK-XAML\lib\" baseDllName, "AHK-XAML", "Iconx")
            return
        }

        if FileExist(this.errLog)
            FileDelete(this.errLog)

        if !XAMLHost.daemonHwnd {
            XAMLHost.Prewarm(targetExe)
            startWait := A_TickCount
            while (!XAMLHost.daemonHwnd && A_TickCount - startWait < 5000) {
                Sleep(10)
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

    static OnCopyData(wParam, lParam, msg, hwnd) {
        if (msg != 0x004A)
            return 0

        lpData := NumGet(lParam, A_PtrSize * 2, "Ptr")
        payload := StrGet(lpData, "UTF-8")
        if (!IsSet(XAML_ENABLE_LOGGING) || XAML_ENABLE_LOGGING)
            try FileAppend("OnCopyData: " payload "`n", XAMLHost.GetAppDir() "\Logs\AhkTrace.log", "UTF-8")
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
            try FileAppend("AHK OnCopyData WebMessageReceived: " payload "`n", XAMLHost.GetAppDir() "\Logs\AhkWebViewDebug.log")
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
        }
        if (ctrlName == "Window" && eventName == "Closed") {
            instance.wpfHwnd := 0
        }

        stateMap := Map()

        eventData := ""
        if (parts.Length >= 5) {
            eventData := XAMLHost.DecodeValue(parts[5])
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
            return result.Has(names[1]) ? result[names[1]] : ""
        return result
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
        libDir := ""
        SplitPath(A_LineFile, , &libDir)
        wvDir := libDir "\WebView2"
        
        if (FileExist(wvDir "\Microsoft.Web.WebView2.Core.dll") && 
            FileExist(wvDir "\Microsoft.Web.WebView2.Wpf.dll") && 
            FileExist(wvDir "\WebView2Loader.dll")) {
            return false
        }
        
        nativeDomDir := "C:\projects\NativeDOM\examples\webview\plugin\sdk"
        sourceCore := nativeDomDir "\lib\net45\Microsoft.Web.WebView2.Core.dll"
        sourceWpf  := nativeDomDir "\lib\net45\Microsoft.Web.WebView2.Wpf.dll"
        sourceLoader := nativeDomDir "\build\native\x64\WebView2Loader.dll"
        
        if (FileExist(sourceCore) && FileExist(sourceWpf) && FileExist(sourceLoader)) {
            if (!DirExist(wvDir)) {
                DirCreate(wvDir)
            }
            try {
                FileCopy(sourceCore, wvDir "\Microsoft.Web.WebView2.Core.dll", 1)
                FileCopy(sourceWpf, wvDir "\Microsoft.Web.WebView2.Wpf.dll", 1)
                FileCopy(sourceLoader, wvDir "\WebView2Loader.dll", 1)
                
                try FileDelete(libDir "\ahk-xaml-webview.dll")
                try FileDelete(XAMLHost.GetAppDir() "\Cache\ahk-xaml-webview.dll")
                
                ToolTip("WebView2 DLLs successfully restored from NativeDOM!")
                SetTimer(() => ToolTip(), -4000)
                return true
            } catch as err {
                ; Silently fail
            }
        }
        return false
    }
}

XAML_TEMPLATE := '
(
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            xmlns:sys="clr-namespace:System;assembly=mscorlib"
            xmlns:primitives="clr-namespace:System.Windows.Controls.Primitives;assembly=PresentationFramework"
            Width="940" Height="700"
            WindowStyle="None" AllowsTransparency="False" Background="Transparent"
            WindowStartupLocation="CenterScreen"
            TextElement.Foreground="{DynamicResource TextMain}" FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif">
        
        <WindowChrome.WindowChrome>
            <WindowChrome GlassFrameThickness="-1" CaptionHeight="%CaptionHeight%" CornerRadius="{DynamicResource WindowRadius}" />
        </WindowChrome.WindowChrome>
    
        <Window.Resources>
            %resources%
        </Window.Resources>
    
        %app%
    </Window>
)'

; We no longer inject the massive xaml.components.xaml styles into every single window's XAML string.
; Instead, they are parsed exactly once in the background .NET daemon on startup and loaded into application-level resources,
; yielding a ~98% reduction in parsed XAML size per window and near-instant window creation/tear-off.