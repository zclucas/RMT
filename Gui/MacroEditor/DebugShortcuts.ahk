
    ; IDE 式调试热键（设置→快捷键）。字段名沿用历史：
    ;   DebugRunHotkey→「继续」、DebugStepHotkey→「步入」。不改写存量值，仅改 getter 语义：
    ;   旧默认 f6 自动升 f11；用户自定义值原样保留。
    _GetContinueHotkey() {                          ; 旧 DebugRunHotkey；旧默认 f5 恰=新 F5
        v := MainSoftData.HasProp("DebugRunHotkey") ? MainSoftData.DebugRunHotkey : ""
        return (v == "" || v == "f5") ? "f5" : v
    }

    _GetStepIntoHotkey() {                          ; 旧 DebugStepHotkey；旧默认 f6 → 新默认 f11
        v := MainSoftData.HasProp("DebugStepHotkey") ? MainSoftData.DebugStepHotkey : ""
        return (v == "" || v == "f6") ? "f11" : v
    }

    ; 其余调试热键：全部走设置（设置→快捷键「调试」块），空值回落到默认
    _GetStepOverHotkey() {
        v := MainSoftData.HasProp("DebugStepOverHotkey") ? MainSoftData.DebugStepOverHotkey : ""
        return v == "" ? "f10" : v
    }

    _GetStepOutHotkey() {
        v := MainSoftData.HasProp("DebugStepOutHotkey") ? MainSoftData.DebugStepOutHotkey : ""
        return v == "" ? "+f11" : v
    }

    _GetRunToCursorHotkey() {
        v := MainSoftData.HasProp("DebugRunToCursorHotkey") ? MainSoftData.DebugRunToCursorHotkey : ""
        return v == "" ? "^f10" : v
    }

    _GetToggleSkipHotkey() {
        v := MainSoftData.HasProp("DebugToggleSkipHotkey") ? MainSoftData.DebugToggleSkipHotkey : ""
        return v == "" ? "^/" : v
    }

    _GetRunAllHotkey() {
        v := MainSoftData.HasProp("DebugRunAllHotkey") ? MainSoftData.DebugRunAllHotkey : ""
        return v == "" ? "^f5" : v
    }

    _ContinueLabel() {
        return GetLang("继续") " (" FormatHotkeyDisplay(this._GetContinueHotkey()) ")"
    }

    _StepOverLabel() {
        return GetLang("步进") " (" FormatHotkeyDisplay(this._GetStepOverHotkey()) ")"
    }

    _StepIntoLabel() {
        return GetLang("步入") " (" FormatHotkeyDisplay(this._GetStepIntoHotkey()) ")"
    }

    _StepOutLabel() {
        return GetLang("步出") " (" FormatHotkeyDisplay(this._GetStepOutHotkey()) ")"
    }

    _RunToCursorLabel() {
        return GetLang("运行到光标处") " (" FormatHotkeyDisplay(this._GetRunToCursorHotkey()) ")"
    }

    _ToggleSkipLabel() {
        return GetLang("跳过指令") " (" FormatHotkeyDisplay(this._GetToggleSkipHotkey()) ")"
    }

    _DebugRunLabel() {
        return GetLang("运行") " (" FormatHotkeyDisplay(this._GetRunAllHotkey()) ")"
    }
