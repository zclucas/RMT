
    ; ============ 设置中心：交互与辅助 ============

    ; 页面切换（RadioButton 视觉态由本方法显式设置，避免依赖 GroupName 作用域）
    OnSettingNavClick(pageId, state, ctrl, event) {
        for pid in ["behavior", "macro", "record", "trigger", "hotkey", "appearance", "ai", "diagnostic"] {
            try this.ui.Update("SetNav_" pid, "IsChecked", pid == pageId ? "True" : "False")
            try this.ui.Update("SetPage_" pid, "Visibility", pid == pageId ? "Visible" : "Collapsed")
        }
    }

    MarkSettingDirty(ctrl := "") {
        pageId := ""
        if (RegExMatch(ctrl, "i)^(Edit(Hold|PreInterval|Interval|Coord)|CmbKeyDown|CmbMacroStop|ChkNoVariable|ChkForeground|ChkContinuous|ChkAutoLoosen|StartTipAudio|EndTipAudio)"))
            pageId := "macro"
        else if (RegExMatch(ctrl, "i)^(Wheel|UIPanel|CountDown)") )
            pageId := "trigger"
        else if (RegExMatch(ctrl, "i)^(ShowBorder|HoldMuti|AutoLoosenCon|KeyboardTog|MouseTog|MouseTrail|JoyTog|JoyInterval)") )
            pageId := "record"
        else if (RegExMatch(ctrl, "i)^(LogLevel_|ChkLog|ChkCMD|CmdTip|Val_)") )
            pageId := (InStr(ctrl, "Val_") = 1) ? "hotkey" : "diagnostic"
        else if (RegExMatch(ctrl, "i)^Ai") || ctrl == "ThemePresetCon")
            pageId := ctrl == "ThemePresetCon" ? "appearance" : "ai"
        else if (RegExMatch(ctrl, "i)^(CmbFont|ThemeFont|Palette)") )
            pageId := "appearance"
        else if (RegExMatch(ctrl, "i)^(ChkBoot|ChkAdmin|ChkData|ChkModal|CmbLang|CmbPreferred|CmbScreen|CmbOCR|CmbExcelBackend|CmbSearchImage|ChkSearchImageAdaptive|CmbRemark|CmbTriggerJoy|CmbJoy|ChkJoy|EditMuti|TabVisible)") )
            pageId := "behavior"
        else if (ctrl == "EditNetPort")
            pageId := "behavior"
        if (pageId != "") {
            this._settingDirty[pageId] := true
            labels := Map("behavior", "系统", "macro", "宏", "record", "指令录制", "trigger", "界面", "hotkey", "快捷键", "appearance", "主题", "ai", "AI 助手", "diagnostic", "日志")
            try this.ui.Update("SetNavText_" pageId, "Text", GetLang(labels[pageId]) " *")
        }
        this._RefreshAllSettingModules()
    }

    ClearSettingDirty() {
        labels := Map("behavior", "系统", "macro", "宏", "record", "指令录制", "trigger", "界面", "hotkey", "快捷键", "appearance", "主题", "ai", "AI 助手", "diagnostic", "日志")
        this._settingDirty := Map()
        for pageId, label in labels
            try this.ui.Update("SetNavText_" pageId, "Text", GetLang(label))
    }

    _InitSettingModuleSpecs() {
        tabFields := []
        for def in MacroCategoryDefs()
            tabFields.Push({key: def[1], def: true, ctrl: "TabVisible_" def[1], kind: "tab"})
        this._setMods := [
            {id: "soft", fields: [{key: "IsBootStart", def: false, ctrl: "ChkBootStart", kind: "chk", hook: "boot"}, {key: "IsAdminStart", def: false, ctrl: "ChkAdminStart", kind: "chk", hook: "admin"}, {key: "IsDataReport", def: true, ctrl: "ChkDataReport", kind: "chk"}, {key: "Lang", def: "简中", ctrl: "CmbLang", kind: "cmbText"}, {key: "PreferredMacroEditor", def: 1, ctrl: "CmbPreferredEditor", kind: "cmb"}, {key: "IsModalSubGui", def: true, ctrl: "ChkModalSubGui", kind: "chk"}]},
            {id: "general", fields: [{key: "OCRTypeValue", def: 1, ctrl: "CmbOCRType", kind: "cmb"}, {key: "ExcelBackend", def: 1, ctrl: "CmbExcelBackend", kind: "cmb"}, {key: "ScreenShotType", def: 3, ctrl: "CmbScreenShot", kind: "cmb"}, {key: "SearchImageType", def: 1, ctrl: "CmbSearchImage", kind: "cmb"}, {key: "SearchImageAdaptive", def: false, ctrl: "ChkSearchImageAdaptive", kind: "chk"}, {key: "MutiThreadNum", def: -1, ctrl: "EditMutiThreadNum", kind: "num"}, {key: "NetworkPort", def: 16888, ctrl: "EditNetPort", kind: "num"}, {key: "RemarkAutoType", def: 2, ctrl: "CmbRemarkAuto", kind: "cmb"}]},
            {id: "trig", fields: [{key: "CheckForeground", def: false, ctrl: "ChkForeground", kind: "chk"}, {key: "AutoLoosenModifier", def: true, ctrl: "ChkAutoLoosen", kind: "chk"}, {key: "ContinuousTrigger", def: true, ctrl: "ChkContinuous", kind: "chk"}, {key: "MacroStopType", def: 1, ctrl: "CmbMacroStop", kind: "cmb"}, {key: "KeyDownDownType", def: 1, ctrl: "CmbKeyDownDown", kind: "cmb"}, {key: "NoVariableTip", def: false, ctrl: "ChkNoVariable", kind: "chk"}]},
            {id: "audio", fields: [{key: "StartTipAudio", def: A_WorkingDir "\Audio\Start.wav", ctrl: "StartTipAudioCon", kind: "txt"}, {key: "EndTipAudio", def: A_WorkingDir "\Audio\End.wav", ctrl: "EndTipAudioCon", kind: "txt"}, {key: "StopTipAudio", def: A_WorkingDir "\Audio\End.wav", ctrl: "StopTipAudioCon", kind: "txt"}]},
            {id: "tabs", fields: tabFields},
            {id: "joy", fields: [{key: "TriggerJoyType", def: "Xbox", ctrl: "CmbTriggerJoyType", kind: "cmbText"}, {key: "JoyType", def: "Xbox", ctrl: "CmbJoyType", kind: "cmbText"}, {key: "JoyLtRtAsButton", def: true, ctrl: "ChkJoyLtRtAsButton", kind: "chk"}]},
            {id: "float", fields: [{key: "HoldFloat", def: 0, ctrl: "EditHoldFloat", kind: "num"}, {key: "PreIntervalFloat", def: 0, ctrl: "EditPreIntervalFloat", kind: "num"}, {key: "IntervalFloat", def: 0, ctrl: "EditIntervalFloat", kind: "num"}, {key: "CoordXFloat", def: 0, ctrl: "EditCoordXFloat", kind: "num"}, {key: "CoordYFloat", def: 0, ctrl: "EditCoordYFloat", kind: "num"}]},
            {id: "recCommon", fields: [{key: "RecordShowBorder", def: true, ctrl: "ShowBorderCon", kind: "chk"}, {key: "RecordHoldMuti", def: true, ctrl: "HoldMutiCon", kind: "chk"}, {key: "RecordAutoLoosen", def: true, ctrl: "AutoLoosenCon", kind: "chk"}]},
            {id: "recKey", fields: [{key: "RecordKeyboard", def: true, ctrl: "KeyboardTogCon", kind: "chk"}]},
            {id: "recMouse", fields: [{key: "RecordMouse", def: true, ctrl: "MouseTogCon", kind: "chk"}, {key: "RecordMouseTrail", def: 1, ctrl: "MouseTrailModeCon", kind: "cmb0"}, {key: "RecordMouseTrailSpeed", def: 95, ctrl: "MouseTrailSpeedCon", kind: "num"}]},
            {id: "recJoy", fields: [{key: "RecordJoy", def: false, ctrl: "JoyTogCon", kind: "chk"}, {key: "RecordJoyInterval", def: 100, ctrl: "JoyIntervalCon", kind: "num"}]},
            {id: "hk1", fields: [{key: "SuspendHotkey", def: "!p", ctrl: "Val_SuspendHotkey", kind: "hk"}, {key: "PauseHotkey", def: "!i", ctrl: "Val_PauseHotkey", kind: "hk"}, {key: "KillMacroHotkey", def: "!k", ctrl: "Val_KillMacroHotkey", kind: "hk"}, {key: "ToolRecordMacroHotKey", def: "!r", ctrl: "Val_ToolRecordMacroHotKey", kind: "hk"}, {key: "ToolTextFilterHotKey", def: "", ctrl: "Val_ToolTextFilterHotKey", kind: "hk"}]},
            {id: "hk2", fields: [{key: "ScreenShotHotKey", def: "", ctrl: "Val_ScreenShotHotKey", kind: "hk"}, {key: "FreePasteHotKey", def: "", ctrl: "Val_FreePasteHotKey", kind: "hk"}, {key: "ToolCheckHotkey", def: "!o", ctrl: "Val_ToolCheckHotkey", kind: "hk"}]},
            {id: "hk3", fields: [{key: "DebugRunHotkey", def: "f5", ctrl: "Val_DebugRunHotkey", kind: "hk"}, {key: "DebugStepOverHotkey", def: "f10", ctrl: "Val_DebugStepOverHotkey", kind: "hk"}, {key: "DebugStepHotkey", def: "f11", ctrl: "Val_DebugStepHotkey", kind: "hk"}, {key: "DebugStepOutHotkey", def: "+f11", ctrl: "Val_DebugStepOutHotkey", kind: "hk"}, {key: "DebugRunToCursorHotkey", def: "^f10", ctrl: "Val_DebugRunToCursorHotkey", kind: "hk"}, {key: "DebugToggleSkipHotkey", def: "^/", ctrl: "Val_DebugToggleSkipHotkey", kind: "hk"}, {key: "DebugRunAllHotkey", def: "^f5", ctrl: "Val_DebugRunAllHotkey", kind: "hk"}]},
            {id: "cmdTip", fields: [{key: "CMDTip", def: false, ctrl: "ChkCMDTip", kind: "chkMy", hook: "cmdtip"}, {key: "CMDWidth", defFn: "cmdW", ctrl: "CmdTipWidthCon", kind: "sld", val: "CmdTipWidthVal"}, {key: "CMDHeight", def: 300, ctrl: "CmdTipHeightCon", kind: "sld", val: "CmdTipHeightVal"}, {key: "CMDPosX", defFn: "cmdX", ctrl: "CmdTipPosXCon", kind: "num"}, {key: "CMDPosY", def: 0, ctrl: "CmdTipPosYCon", kind: "num"}, {key: "CMDFontSize", def: 12, ctrl: "CmdTipFontCon", kind: "sld", val: "CmdTipFontVal"}, {key: "CMDTransparency", def: 50, ctrl: "CmdTipAlphaCon", kind: "sld", val: "CmdTipAlphaVal"}, {key: "CMDLogToFile", def: false, ctrl: "CmdTipLogFileCon", kind: "chk"}]},
            {id: "logErr", fields: [{key: "SysLogMinLevel", def: "warn,error", ctrl: "LogLevel_warn", kind: "logLevel"}, {key: "LogWarnBubble", def: true, ctrl: "ChkLogWarnBubble", kind: "chk"}, {key: "LogErrorBadge", def: true, ctrl: "ChkLogErrorBadge", kind: "chk"}, {key: "CMDLogFilePath", def: "", ctrl: "CmdTipLogPathCon", kind: "txt"}, {key: "CMDLogAutoClear", def: 2, ctrl: "CmdTipAutoClearCon", kind: "cmb0"}]},
            {id: "wheel", fields: [{key: "FixedMenuWheel", def: false, ctrl: "WheelFixedPosCon", kind: "chk"}, {key: "MenuWheelShowTooltip", def: false, ctrl: "WheelShowTooltipCon", kind: "chk"}, {key: "MenuWheelSelectMode", def: 2, ctrl: "WheelSelectModeCon", kind: "cmb"}, {key: "MenuWheelScale", def: 100, ctrl: "WheelScaleCon", kind: "sld", val: "WheelScaleVal"}]},
            {id: "countdown", fields: [{key: "CountDownStyle", def: 2, ctrl: "CountDownStyleCon", kind: "cmb"}, {key: "CountDownPadZero", def: true, ctrl: "CountDownPadCon", kind: "chk"}, {key: "CountDownAlpha", def: 70, ctrl: "CountDownAlphaCon", kind: "sld", val: "CountDownAlphaVal"}, {key: "CountDownFontSize", def: 15, ctrl: "CountDownFontCon", kind: "sld", val: "CountDownFontVal"}]},
            {id: "uipanel", fields: [{key: "UIPanelBtnWidth", def: 80, ctrl: "UIPanelBtnWidthCon", kind: "sld", val: "UIPanelBtnWidthVal"}, {key: "UIPanelBtnHeight", def: 34, ctrl: "UIPanelBtnHeightCon", kind: "sld", val: "UIPanelBtnHeightVal"}, {key: "UIPanelFontSize", def: 12, ctrl: "UIPanelFontSizeCon", kind: "sld", val: "UIPanelFontSizeVal"}, {key: "UIPanelCols", def: 3, ctrl: "UIPanelColsCon", kind: "sld", val: "UIPanelColsVal"}, {key: "UIPanelShowOnActive", def: true, ctrl: "UIPanelShowOnActiveCon", kind: "chk"}]},
            {id: "theme", fields: [{key: "AppTheme", def: "Default", ctrl: "ThemePresetCon", kind: "theme"}]},
            {id: "font", fields: [{key: "FontType", def: "微软雅黑", ctrl: "CmbFont", kind: "cmbText"}, {key: "FontSize", def: 15, ctrl: "ThemeFontSizeCon", kind: "sld", val: "ThemeFontSizeVal"}]},
            {id: "palette", fields: [{key: "AppTheme", def: "Default", ctrl: "ThemePresetCon", kind: "theme"}]},
            {id: "aiModel", fields: [{key: "AiProvider", def: "openai", ctrl: "AiProviderCon", kind: "aiProv"}, {key: "AiApiBaseUrl", def: "https://api.openai.com/v1", ctrl: "AiBaseUrlCon", kind: "txt"}, {key: "AiApiKey", def: "", ctrl: "AiApiKeyCon", kind: "pwd"}, {key: "AiModel", def: "", ctrl: "AiModelCon", kind: "txt"}]},
            {id: "aiPerm", fields: [{key: "AiAccessMode", def: 2, ctrl: "AiAccessCon", kind: "cmb"}, {key: "AiApprovalMode", def: 2, ctrl: "AiApprovalCon", kind: "cmb"}]}
        ]
    }

    _BindSettingModuleResets() {
        if (!IsObject(this._setMods))
            return
        for mod in this._setMods
            this._Bind("BtnSetReset_" mod.id, "Click", ObjBindMethod(this, "OnSettingModuleReset", mod.id))
    }

    _SettingFieldDef(f) {
        if (f.HasOwnProp("defFn") && f.defFn == "cmdW")
            return GetDefaultCMDTipWidth()
        if (f.HasOwnProp("defFn") && f.defFn == "cmdX")
            return A_ScreenWidth - GetDefaultCMDTipWidth()
        return f.def
    }

    _SettingFieldCur(f) {
        if (f.kind == "tab")
            return this._TabVisibleVal(f.key)
        if (f.kind == "chkMy")
            return !!MySoftData.CMDTip
        if (f.kind == "pwd")
            return Trim(String(MainSoftData.HasProp(f.key) ? MainSoftData.%f.key% : ""))
        if (f.kind == "hk")
            return Trim(String(MainSoftData.HasProp(f.key) ? MainSoftData.%f.key% : ""))
        return MainSoftData.HasProp(f.key) ? MainSoftData.%f.key% : this._SettingFieldDef(f)
    }

    _SettingFieldDirty(f) {
        cur := this._SettingFieldCur(f)
        def := this._SettingFieldDef(f)
        if (f.kind == "chk" || f.kind == "chkMy" || f.kind == "tab")
            return !!cur != !!def
        if (IsNumber(cur) && IsNumber(def))
            return Integer(cur) != Integer(def)
        return String(cur) != String(def)
    }

    _RefreshAllSettingModules() {
        if (this.HasProp("_setModLock") && this._setModLock)
            return
        if (!IsObject(this._setMods) || !IsObject(this.ui))
            return
        for mod in this._setMods {
            dirty := false
            for f in mod.fields {
                if (this._SettingFieldDirty(f)) {
                    dirty := true
                    break
                }
            }
            try this.ui.Update("BtnSetReset_" mod.id, "Visibility", dirty ? "Visible" : "Collapsed")
        }
    }

    OnSettingModuleReset(modId, state := "", ctrl := "", event := "") {
        global StartTipAudio, EndTipAudio, StopTipAudio
        if (!IsObject(this._setMods))
            return
        spec := ""
        for mod in this._setMods {
            if (mod.id == modId) {
                spec := mod
                break
            }
        }
        if (!IsObject(spec))
            return
        this._setModLock := true
        try {
            for f in spec.fields
                this._ApplySettingFieldDefault(f)
        } finally {
            this._setModLock := false
        }
        if (modId == "audio") {
            StartTipAudio := MainSoftData.StartTipAudio
            EndTipAudio := MainSoftData.EndTipAudio
            StopTipAudio := MainSoftData.StopTipAudio
        }
        hint := (spec.fields.Length > 0) ? spec.fields[1].ctrl : ""
        this.MarkSettingDirty(hint)
        this._RefreshAllSettingModules()
    }

    _ApplySettingFieldDefault(f) {
        def := this._SettingFieldDef(f)
        switch f.kind {
            case "chk":
                MainSoftData.%f.key% := !!def
                try this.ui.Update(f.ctrl, "IsChecked", def ? "True" : "False")
                if (f.HasOwnProp("hook") && f.hook == "boot")
                    OnBootStartChanged("")
                else if (f.HasOwnProp("hook") && f.hook == "admin")
                    OnAdminStartChanged("")
            case "chkMy":
                try this.ui.Update(f.ctrl, "IsChecked", def ? "True" : "False")
                MySoftData.CMDTip := !!def
                SetCMDTipValue(!!def)
            case "tab":
                MainSoftData.TabVisibleMap[f.key] := !!def
                try this.ui.Update(f.ctrl, "IsChecked", def ? "True" : "False")
            case "cmb":
                MainSoftData.%f.key% := Integer(def)
                try this.ui.Update(f.ctrl, "SelectedIndex", Integer(def) - 1)
            case "cmb0":
                MainSoftData.%f.key% := Integer(def)
                try this.ui.Update(f.ctrl, "SelectedIndex", Integer(def))
            case "cmbText":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", String(def))
            case "logLevel":
                MainSoftData.%f.key% := def
                for level in RMTLogLevelKeys()
                    try this.ui.Update("LogLevel_" level, "IsChecked", RMTLogLevelEnabled(level, def) ? "True" : "False")
            case "sld":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Value", String(def))
                if (f.HasOwnProp("val"))
                    try this.ui.Update(f.val, "Text", String(def))
            case "num":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", String(def))
            case "txt":
                MainSoftData.%f.key% := def
                shown := (f.key == "CMDLogFilePath") ? CMDLogPathDisplay(def) : String(def)
                try this.ui.Update(f.ctrl, "Text", shown)
            case "pwd":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Password", String(def))
            case "hk":
                MainSoftData.%f.key% := def
                try this.ui.Update(f.ctrl, "Text", (def == "" ? GetLang("无") : FormatHotkeyDisplay(def)))
            case "theme":
                tidx := 0
                for ti, tp in AppThemeUtil.Presets {
                    if (tp.Key == "Default") {
                        tidx := ti - 1
                        break
                    }
                }
                try this.ui.Update("ThemePresetCon", "SelectedIndex", tidx)
                this.OnSettingThemeChanged("", "ThemePresetCon", "")
            case "aiProv":
                MainSoftData.AiProvider := "openai"
                try this.ui.Update("AiProviderCon", "SelectedIndex", AiAssist.ProviderIndex("openai") - 1)
                this.OnAiProviderChanged("", "AiProviderCon", "")
        }
        if (f.kind == "cmbText" && f.key == "TriggerJoyType")
            this._RefreshJoyLtRtAsButtonText()
    }

    OnSettingLogBrowse(*) {
        start := CMDLogResolveDir(MainSoftData.CMDLogFilePath)
        if (!DirExist(start))
            start := CMDLogAppDir()
        selected := FileSelect("D", start, GetLang("日志文件路径"))
        if (selected == "")
            return
        MainSoftData.CMDLogFilePath := CMDLogCalibrateStored(selected)
        this.ui.Update("CmdTipLogPathCon", "Text", CMDLogPathDisplay(MainSoftData.CMDLogFilePath))
        this.MarkSettingDirty("CmdTipLogPathCon")
        if (IsSet(MyCMDTipGui) && IsObject(MyCMDTipGui))
            MyCMDTipGui.ApplySettings()
    }

    OnSettingAudioBrowse(field, *) {
        global MainSoftData, StartTipAudio, EndTipAudio, StopTipAudio
        current := MainSoftData.%field%
        selected := FileSelect(1, current, GetLang("选择提示音"), "音频文件 (*.wav;*.mp3;*.wma;*.aac;*.flac)|*.wav;*.mp3;*.wma;*.aac;*.flac")
        if (selected == "")
            return
        MainSoftData.%field% := selected
        if (field == "StartTipAudio")
            StartTipAudio := selected
        else if (field == "EndTipAudio")
            EndTipAudio := selected
        else
            StopTipAudio := selected
        this.ui.Update(field "Con", "Text", selected)
        this.MarkSettingDirty(field "Con")
    }

    ; 0 基索引下拉（配置值即索引，如 RecordMouseTrail / CMDLogAutoClear）
    OnComboIndex0(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := Integer(this.ui.Query(ctrl ">SelectedIndex"))
        this.MarkSettingDirty(ctrl)
    }

    ; 滑块 → 写字段 + 同步数值框
    OnSettingSlider(fieldName, valName, mn, mx, state, ctrl, event) {
        v := this.ui.Query(ctrl)
        if (!IsNumber(v))
            return
        v := Max(mn, Min(mx, Integer(Round(Number(v)))))
        MainSoftData.%fieldName% := v
        this.MarkSettingDirty(ctrl)
        try this.ui.Update(valName, "Text", String(v))
    }

    ; 数值框 → 写字段 + 同步滑块
    OnSettingNumText(fieldName, name, mn, mx, state, ctrl, event) {
        t := Trim(this.ui.Query(ctrl))
        if (t == "" || !IsNumber(t))
            return
        v := Max(mn, Min(mx, Integer(Round(Number(t)))))
        MainSoftData.%fieldName% := v
        this.MarkSettingDirty(ctrl)
        try this.ui.Update(name, "Value", String(v))
    }

    OnSettingBoundedIntText(fieldName, mn, mx, state, ctrl, event) {
        t := Trim(this.ui.Query(ctrl))
        if (t == "" || !IsInteger(t)) {
            try this.ui.Update(ctrl, "Text", String(MainSoftData.%fieldName%))
            return
        }
        v := Max(mn, Min(mx, Integer(t)))
        MainSoftData.%fieldName% := v
        this.MarkSettingDirty(ctrl)
        try this.ui.Update(ctrl, "Text", String(v))
    }

    ; 主题：字体大小（滑块/数值框），原位预览并与「应用并保存」一致地写回 FontSize
    OnSettingFontSize(state, ctrl, event) {
        v := this.ui.Query("ThemeFontSizeCon")
        if (!IsNumber(v))
            return
        this._ApplySettingFontSize(Integer(Round(Number(v))))
    }
    OnSettingFontSizeText(state, ctrl, event) {
        t := Trim(this.ui.Query("ThemeFontSizeVal"))
        if (t == "" || !IsNumber(t)) {
            try this.ui.Update("ThemeFontSizeVal", "Text", String(MainSoftData.FontSize))
            return
        }
        this._ApplySettingFontSize(Integer(Round(Number(t))))
    }
    _ApplySettingFontSize(fs) {
        fs := Max(0, Min(40, fs))
        MainSoftData.FontSize := fs
        this.MarkSettingDirty("ThemeFontSizeCon")
        try this.ui.Update("ThemeFontSizeCon", "Value", String(fs))
        try this.ui.Update("ThemeFontSizeVal", "Text", String(fs))
        try {
            ApplyUserFontSize(fs, false)
            this.ui.Update("Window", "ApplyFonts", XAMLHost.BuildApplyFontsPayload(0, fs))
        }
    }

    ; 快捷键录入：复用 HotkeySettingGui 的录入链（MyEditHotkeyGui + 触发键/字串编辑器）
    OnSettingEditHotkey(fieldName, onlyTrigger, state, ctrl, event) {
        cur := MainSoftData.HasProp(fieldName) ? String(MainSoftData.%fieldName%) : ""
        showCon := HotkeyValueHolder(cur)
        keyCon := HotkeyValueHolder(cur)
        AfterSure(*) {
            newVal := keyCon.Value
            MainSoftData.%fieldName% := newVal
            try this.ui.Update("Val_" fieldName, "Text", (newVal == "" ? GetLang("无") : FormatHotkeyDisplay(newVal)))
            this.MarkSettingDirty("Val_" fieldName)
            this._ignoreConfirmUntil := A_TickCount + 500
            try WinActivate("ahk_id " this.ui.wpfHwnd)
        }
        MyEditHotkeyGui.AfterSureAction := AfterSure
        OnOpenEditHotkeyGui(showCon, keyCon, onlyTrigger)
    }

    ; AI：模型商 → 写 id，并同步 API URL 可编辑性（仅 azure / 自定义可编辑）
    OnAiProviderChanged(state, ctrl, event) {
        idx := this.ui.Query("AiProviderCon>SelectedIndex")
        if (!IsNumber(idx))
            return
        prov := AiAssist.ProviderByIndex(Integer(idx) + 1)
        MainSoftData.AiProvider := prov["id"]
        this.MarkSettingDirty(ctrl)
        editable := (prov["id"] = "custom" || Trim(prov["url"]) == "")
        try this.ui.Update("AiBaseUrlCon", "IsReadOnly", editable ? "False" : "True")
        try this.ui.Update("AiBaseUrlCon", "IsEnabled", editable ? "True" : "False")
        try this.ui.Update("AiBaseUrlCon", "Text", Trim(prov["url"]))
    }

    ; AI：模型列表（可编辑下拉）→ AiModel + 合并 AiModelList
    OnAiModelChanged(state, ctrl, event) {
        m := Trim(this.ui.Query("AiModelCon"))
        if (m == "")
            return
        MainSoftData.AiModel := m
        this.MarkSettingDirty(ctrl)
        list := m
        for id in AiAssist.ModelListArr() {
            id := Trim(id)
            if (id != "" && id != m)
                list .= "," id
        }
        MainSoftData.AiModelList := list
    }

    ; AI：拉取模型列表（仅写内存，落盘由「应用并保存」统一处理）
    OnAiRefreshModels(state, ctrl, event) {
        baseUrl := Trim(this.ui.Query("AiBaseUrlCon"))
        apiKey := Trim(this.ui.Query("AiApiKeyCon"))
        if (apiKey == "" || baseUrl == "") {
            Toast.Warning(GetLang("请先填写 API Key 与 API URL"))
            return
        }
        try this.ui.Update("BtnAiRefreshModels", "IsEnabled", "False")
        try {
            ids := AiAssist.FetchModels(baseUrl, apiKey)
            if (ids.Length < 1)
                throw Error(GetLang("未解析到可用模型，请检查 API URL 是否指向 OpenAI 兼容接口"))
            MainSoftData.AiModelList := ""
            for id in ids
                MainSoftData.AiModelList .= (MainSoftData.AiModelList == "" ? "" : ",") id
            try this.ui.Update("AiModelCon", "ClearItems", "")
            for id in ids
                try this.ui.Update("AiModelCon", "AddItem", id)
            keep := MainSoftData.AiModel
            if (keep == "")
                keep := ids[1]
            try this.ui.Update("AiModelCon", "Text", keep)
            Toast.Success(GetLang("已刷新模型列表"))
        } catch as e {
            Toast.Error(e.Message)
        } finally {
            try this.ui.Update("BtnAiRefreshModels", "IsEnabled", "True")
        }
    }

    ; ============ 设置中心：主题（预设 + 颜色 1~14）============

    ; 预设下拉：末位为「自定义」（只切换 key，保留当前颜色）
    OnSettingThemeChanged(state, ctrl, event) {
        idx := this.ui.Query("ThemePresetCon>SelectedIndex")
        if (!IsNumber(idx))
            return
        idx := Integer(idx)
        this.MarkSettingDirty(ctrl)
        if (idx < 0 || idx >= AppThemeUtil.Presets.Length) {
            MainSoftData.AppTheme := "Custom"
        } else {
            preset := AppThemeUtil.Presets[idx + 1]
            MainSoftData.AppTheme := preset.Key
            colors := AppThemeUtil.NewColorMapFromPreset(preset)
            MainSoftData.ThemeColors := colors
            AppThemeUtil.ApplyToRuntime(colors)
            try AppThemeUtil.ApplyWinThemeToXaml(this.ui, colors)
        }
        this._RenderSettingPalette()
    }

    ; 把颜色 1~14 刷到色值框 / 色块；仅「自定义」时色块可点
    _RenderSettingPalette() {
        if (!(MainSoftData.HasProp("ThemeColors") && IsObject(MainSoftData.ThemeColors)))
            return
        editable := (MainSoftData.AppTheme == "Custom")
        for i, entry in AppThemeUtil.BuildPalette(MainSoftData.ThemeColors) {
            try this.ui.Update("PaletteText_" i, "Text", entry.Color)
            try this.ui.Update("PalettePreview_" i, "Background", entry.Color)
            try this.ui.Update("PalettePreview_" i, "Cursor", editable ? "Hand" : "Arrow")
            try this.ui.Update("PalettePreview_" i, "IsHitTestVisible", editable ? "True" : "False")
        }
    }

    ; 取色：仅自定义主题；取色后写回 ThemeColors 并即时预览
    OnSettingPickColor(slot, state, ctrl, event) {
        if (MainSoftData.AppTheme != "Custom")
            return
        if (!(MainSoftData.HasProp("ThemeColors") && IsObject(MainSoftData.ThemeColors)))
            return
        key := "Theme_Color" Format("{:02}", slot)
        cur := MainSoftData.ThemeColors.Has(key) ? MainSoftData.ThemeColors[key] : "#FF000000"
        result := XColorPicker.Show({Title: GetLang("颜色") slot, DefaultColor: cur, Owner: this.ui.wpfHwnd, Modal: true})
        if (result.Status != "OK")
            return
        MainSoftData.ThemeColors[key] := AppThemeUtil.NormalizeArgb(result.Color)
        AppThemeUtil.ApplyToRuntime(MainSoftData.ThemeColors)
        try AppThemeUtil.ApplyWinThemeToXaml(this.ui, MainSoftData.ThemeColors)
        this._RenderSettingPalette()
    }

    ; ============ 设置中心：右键菜单有序列表 ============

    _CtxItemLabel(key) {
        static m := Map("Edit", "编辑", "Skip", "跳过指令", "Debug", "调试起点", "Insert", "插入指令", "Copy", "复制", "SharedCopy", "共享复制", "Paste", "粘贴", "Delete", "删除", "Add", "添加指令", "BranchCopy", "复制", "BranchSharedCopy", "共享复制")
        if (key == "Separator")
            return "───────"
        return m.Has(key) ? GetLang(m[key]) : key
    }

    _InitCtxLists() {
        this._ctxGenAll := ["Edit", "Skip", "Debug", "Insert", "Copy", "SharedCopy", "Paste", "Delete", "Separator"]
        this._ctxBranchAll := ["Add", "BranchCopy", "BranchSharedCopy", "Paste", "Delete", "Separator"]
        defGen := ["Edit", "Skip", "Debug", "Separator", "Insert", "Separator", "Copy", "SharedCopy", "Paste", "Separator", "Delete"]
        defBranch := ["Add", "Separator", "BranchCopy", "BranchSharedCopy", "Paste", "Separator", "Delete"]
        gRaw := MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : ""
        bRaw := MainSoftData.HasProp("BranchContextMenu") ? MainSoftData.BranchContextMenu : ""
        this._ctxGenActive := this._ParseCtxList(gRaw, defGen)
        this._ctxBranchActive := this._ParseCtxList(bRaw, defBranch)
        this._RebuildCtxAvail()
    }

    _ParseCtxList(raw, def) {
        out := []
        if (Trim(String(raw)) == "") {
            for k in def
                out.Push(k)
            return out
        }
        for k in StrSplit(String(raw), ",") {
            k := Trim(k)
            if (k != "")
                out.Push(k)
        }
        return out
    }

    _InArr(arr, v) {
        for x in arr {
            if (x == v)
                return true
        }
        return false
    }

    ; 可用项目 = 全集里未出现在显示项目的项；分隔线始终可用（可重复添加、不被消耗）
    _RebuildCtxAvail() {
        this._ctxGenAvail := []
        for k in this._ctxGenAll {
            if (k == "Separator" || !this._InArr(this._ctxGenActive, k))
                this._ctxGenAvail.Push(k)
        }
        this._ctxBranchAvail := []
        for k in this._ctxBranchAll {
            if (k == "Separator" || !this._InArr(this._ctxBranchActive, k))
                this._ctxBranchAvail.Push(k)
        }
    }

    _RenderOneCtxList(listId, arr) {
        try this.ui.Update(listId, "ClearItems", "")
        for k in arr
            try this.ui.Update(listId, "AddItem", this._CtxItemLabel(k))
    }

    _RenderCtxLists(reselId := "", reselIdx := -1, sync := true) {
        this._RebuildCtxAvail()
        this._RenderOneCtxList("GenActiveList", this._ctxGenActive)
        this._RenderOneCtxList("GenAvailList", this._ctxGenAvail)
        this._RenderOneCtxList("BranchActiveList", this._ctxBranchActive)
        this._RenderOneCtxList("BranchAvailList", this._ctxBranchAvail)
        if (sync)
            this._SyncCtxConfig()
        if (reselId != "" && reselIdx >= 0)
            try this.ui.Update(reselId, "SelectedIndex", String(reselIdx))
    }

    ; 显示项目 → 配置键（CSV）；SharedCopy 由两份列表派生
    _SyncCtxConfig() {
        MainSoftData.GeneralContextMenu := this._JoinCtxList(this._ctxGenActive)
        MainSoftData.BranchContextMenu := this._JoinCtxList(this._ctxBranchActive)
        MainSoftData.SharedCopy := (this._InArr(this._ctxGenActive, "SharedCopy") || this._InArr(this._ctxBranchActive, "BranchSharedCopy"))
    }

    _JoinCtxList(arr) {
        s := ""
        for i, k in arr
            s .= (i > 1 ? "," : "") k
        return s
    }

    _CtxSelIdx(listId) {
        raw := this.ui.Query(listId ">SelectedIndex")
        return IsNumber(raw) ? Integer(raw) : -1
    }

    OnCtxMove(dir, which, state, ctrl, event) {
        listId := (which == "gen") ? "GenActiveList" : "BranchActiveList"
        active := (which == "gen") ? this._ctxGenActive : this._ctxBranchActive
        sel := this._CtxSelIdx(listId)
        if (sel < 0 || sel >= active.Length)
            return
        ai := sel + 1
        if (dir == "up") {
            if (ai <= 1)
                return
            tmp := active[ai]
            active[ai] := active[ai - 1]
            active[ai - 1] := tmp
            this._RenderCtxLists(listId, ai - 2)
        } else {
            if (ai >= active.Length)
                return
            tmp := active[ai]
            active[ai] := active[ai + 1]
            active[ai + 1] := tmp
            this._RenderCtxLists(listId, ai)
        }
    }

    OnCtxAdd(which, state, ctrl, event) {
        isGen := (which == "gen")
        avail := isGen ? this._ctxGenAvail : this._ctxBranchAvail
        active := isGen ? this._ctxGenActive : this._ctxBranchActive
        availId := isGen ? "GenAvailList" : "BranchAvailList"
        activeId := isGen ? "GenActiveList" : "BranchActiveList"
        sel := this._CtxSelIdx(availId)
        if (sel < 0 || sel >= avail.Length)
            return
        item := avail[sel + 1]
        actSel := this._CtxSelIdx(activeId)
        insertAt := (actSel >= 0 && actSel < active.Length) ? actSel + 2 : active.Length + 1
        active.InsertAt(insertAt, item)
        if (item != "Separator")
            avail.RemoveAt(sel + 1)
        this._RenderCtxLists(activeId, insertAt - 1)
    }

    OnCtxRemove(which, state, ctrl, event) {
        isGen := (which == "gen")
        active := isGen ? this._ctxGenActive : this._ctxBranchActive
        activeId := isGen ? "GenActiveList" : "BranchActiveList"
        sel := this._CtxSelIdx(activeId)
        if (sel < 0 || sel >= active.Length)
            return
        active.RemoveAt(sel + 1)
        newSel := (sel > 0) ? sel - 1 : (active.Length > 0 ? 0 : -1)
        this._RenderCtxLists(activeId, newSel)
    }

    OnIntEdit(fieldName, state, ctrl, event) {
        v := Trim(this.ui.Query(ctrl))
        if (v != "" && IsInteger(v)) {
            MainSoftData.%fieldName% := Integer(v)
            this.MarkSettingDirty(ctrl)
        }
    }

    OnTextEdit(fieldName, state, ctrl, event) {
        global StartTipAudio, EndTipAudio, StopTipAudio
        if (fieldName == "CMDLogFilePath") {
            old := MainSoftData.CMDLogFilePath
            MainSoftData.CMDLogFilePath := CMDLogStoreFromUserText(this.ui.Query(ctrl))
            try this.ui.Update(ctrl, "Text", CMDLogPathDisplay(MainSoftData.CMDLogFilePath))
            if (MainSoftData.CMDLogFilePath != old && IsSet(MyCMDTipGui) && IsObject(MyCMDTipGui))
                MyCMDTipGui.ApplySettings()
            this.MarkSettingDirty(ctrl)
            return
        }
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
        if (fieldName == "StartTipAudio")
            StartTipAudio := MainSoftData.StartTipAudio
        else if (fieldName == "EndTipAudio") {
            EndTipAudio := MainSoftData.EndTipAudio
        } else if (fieldName == "StopTipAudio")
            StopTipAudio := MainSoftData.StopTipAudio
        this.MarkSettingDirty(ctrl)
    }

    ; 论坛分享：退出登录 —— 清空本机凭据（论坛侧那条密钥不撤销，用户可自行去 个人设置 → 应用 撤销）
    OnShareLogoutClick(state, ctrl, event) {
        if (this._shareLoginTick != "") {              ; 正在等授权：一并取消
            SetTimer(this._shareLoginTick, 0)
            this._shareLoginTick := ""
            try GetDiscourse().CancelUserAuth()
        }
        SetShareAuth("", "")
        this._SetShareLoginState(this._ShareLoginStateText())
    }

    ; ---- 论坛分享：浏览器授权登录（Discourse /user-api-key/new） ----
    ; 点按钮 → C# 起本地固定端口监听 + 打开浏览器授权页 → 轮询 GetAuthState()，
    ; 2 = 已用 RSA 私钥解出 key → 写 ini → 再用 key 打 /session/current.json 校验并显示用户名。
    ; 前置条件：站点后台 allowed_user_api_auth_redirects 必须逐字包含
    ;   http://127.0.0.1:38471/authcb（另 :38472 / :38473 是端口被占时的顺延位），
    ;   该设置不支持通配符，端口必须与 C# 的 AuthCallbackPorts 一致。
    OnShareLoginClick(state, ctrl, event) {
        if (this._shareLoginTick != "") {              ; 等待中再点 = 取消
            SetTimer(this._shareLoginTick, 0)
            this._shareLoginTick := ""
            try GetDiscourse().CancelUserAuth()
            this._SetShareLoginState(this._ShareLoginStateText())
            return
        }
        try GetDiscourse().BeginUserAuth(GetShareServerUrl())
        catch as e {
            this._SetShareLoginState(GetLang("无法开始授权：") . e.Message)
            return
        }
        this._SetShareLoginState(GetLang("已打开浏览器，请登录论坛并点「授权」…（再点本按钮可取消）"))
        this._shareLoginTick := ObjBindMethod(this, "PollShareLogin")
        SetTimer(this._shareLoginTick, 300)
    }

    PollShareLogin() {
        st := 0
        try st := Integer(GetDiscourse().GetAuthState())
        catch as e {
            SetTimer(this._shareLoginTick, 0)
            this._shareLoginTick := ""
            this._SetShareLoginState(GetLang("授权失败：") . e.Message)
            return
        }
        if (st = 1)                                   ; 1 = 仍在等回调（C# 侧 5 分钟超时）
            return
        SetTimer(this._shareLoginTick, 0)
        this._shareLoginTick := ""
        if (st != 2) {
            this._SetShareLoginState(this._ShareLoginStateText())
            return
        }
        raw := "", err := ""
        try raw := GetDiscourse().TakeAuthResult()
        try err := GetDiscourse().GetAuthError()
        key := ""
        if (raw != "" && RegExMatch(raw, '"key"\s*:\s*"([^"]+)"', &m))
            key := m[1]
        if (key == "") {
            if (err == "")
                err := GetLang("授权页未返回凭据")
            this._SetShareLoginState(GetLang("授权失败：") . err)
            return
        }
        ; 用户密钥模式：用户名必须留空（C# 的 ApplyAuth 据此发 User-Api-Key 而非 Api-Key）
        SetShareAuth("", key)
        this._SetShareLoginState(GetLang("已授权，正在校验…"))
        this.StartShareVerify(key)
    }

    ; 用刚拿到的 key 打一次 /session/current.json：既确认凭据可用，也顺带取回用户名显示
    StartShareVerify(key) {
        if (this._shareVerifyTick != "")
            return
        try GetDiscourse().SetAuth("", key)
        try GetDiscourse().BeginGetTextAuth(GetShareServerUrl() . "/session/current.json")
        this._shareVerifyTick := ObjBindMethod(this, "PollShareVerify")
        SetTimer(this._shareVerifyTick, 400)
    }

    PollShareVerify() {
        st := 0
        try st := Integer(GetDiscourse().GetTextAuthState())
        catch {
            SetTimer(this._shareVerifyTick, 0)
            this._shareVerifyTick := ""
            this._SetShareLoginState(GetLang("已保存凭据（未能校验）"))
            return
        }
        if (st = 1)
            return
        SetTimer(this._shareVerifyTick, 0)
        this._shareVerifyTick := ""
        body := ""
        if (st = 2)
            try body := GetDiscourse().TakeTextAuthResult()
        if (body != "" && RegExMatch(body, '"username"\s*:\s*"([^"]+)"', &m))
            this._SetShareLoginState(GetLang("已登录：") . m[1])
        else
            this._SetShareLoginState(GetLang("凭据已保存，但校验未通过（可能已在论坛被撤销）"))
    }

    ; 状态行初始文案：只读 ini，不联网（启动时不发请求；校验只在点「登录论坛」后做）
    _ShareLoginStateText() {
        if (GetShareApiKey() == "")
            return GetLang("未登录")
        u := GetShareApiUser()
        return (u != "") ? GetLang("已登录（管理员 Key）：") . u : GetLang("已登录")
    }

    _SetShareLoginState(text) {
        try this.ui.Update("TxtShareLoginState", "Text", text)
    }

    ; §11 背景图：浏览选择图片文件（写入配置，保存后重启生效）
    OnBackImageBrowse(state, ctrl, event) {
        path := FileSelect(1, , GetLang("选择背景图片"), "图片 (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp)|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp")
        if (path == "")
            return
        MainSoftData.BackImagePath := path
        this.ui.Update("EditBackImage", "Text", path)
    }

    OnBackImageClear(state, ctrl, event) {
        MainSoftData.BackImagePath := ""
        this.ui.Update("EditBackImage", "Text", "")
    }

    OnSettingHelpClick(name, state := "", ctrl := "", event := "") {
        if (!this.HasProp("_setHelpMap") || !this._setHelpMap.Has(name))
            return
        item := this._setHelpMap[name]
        if (item.HasProp("fn") && item.fn != "") {
            item.fn()
            return
        }
        RmtDialog.Info(item.text, item.title)
    }

    OnCheckEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl) == "True"
        this.MarkSettingDirty(ctrl)
    }

    ; §10 显示页签勾选：写入 TabVisibleMap（保存后重启生效）
    OnTabVisibleCheck(symbol, state, ctrl, event) {
        if (!MainSoftData.TabVisibleMap.Has(symbol))
            return
        MainSoftData.TabVisibleMap[symbol] := this.ui.Query(ctrl) == "True"
        this.MarkSettingDirty(ctrl)
    }

    _TabVisibleVal(symbol) {
        return (MainSoftData.TabVisibleMap.Has(symbol)) ? MainSoftData.TabVisibleMap[symbol] : true
    }

    ; 日志级别随设置保存生效。
    OnLogLevelChanged(level, state, ctrl, event) {
        checked := this.ui.Query(ctrl) == "True"
        MainSoftData.SysLogMinLevel := RMTLogToggleLevel(MainSoftData.SysLogMinLevel, level, checked)
        this.MarkSettingDirty(ctrl)
    }

    OnComboText(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
        this.MarkSettingDirty(ctrl)
    }

    OnTriggerJoyTypeChanged(state, ctrl, event) {
        this.OnComboText("TriggerJoyType", state, ctrl, event)
        this._RefreshJoyLtRtAsButtonText()
    }

    _JoyLtRtAsButtonLabel() {
        isPs5 := (MainSoftData.TriggerJoyType == "PS5")
        return GetLang(isPs5 ? "L2、R2按键化" : "LT、RT按键化")
    }

    _JoyLtRtAsButtonDesc() {
        isPs5 := (MainSoftData.TriggerJoyType == "PS5")
        return Format(GetLang("开启后 {} 当普通按键；关闭则当扳机轴，可设 0~100。"), isPs5 ? "L2/R2" : "LT/RT")
    }

    _RefreshJoyLtRtAsButtonText() {
        if (!IsObject(this.ui))
            return
        this.ui.Update("LblJoyLtRtAsButton", "Text", this._JoyLtRtAsButtonLabel())
        this.ui.Update("LblJoyLtRtAsButton_Desc", "Text", this._JoyLtRtAsButtonDesc())
    }

    OnComboIndex(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := Integer(this.ui.Query(ctrl ">SelectedIndex")) + 1
        this.MarkSettingDirty(ctrl)
    }

    _IntRow(label, name, val, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name '" Text="' val '" Width="100" MinHeight="24" Padding="4,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
    }

    _CheckRow(label, name, val, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<CheckBox Name="' name '" Content="' this._XmlEsc(label) '" IsChecked="' (val ? "True" : "False") '" VerticalAlignment="Center"/>'
            . '</StackPanel>'
    }

    _ComboRow(label, name, items, sel, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        selIdx := ""
        itemsXaml := ""
        for k, it in items {
            ; INI 读出的数值可能是字符串（如 "1"），需按整数匹配
            isSel := IsInteger(sel) ? (k == Integer(sel)) : (it == sel)
            if (isSel)
                selIdx := k - 1
            itemsXaml .= '<ComboBoxItem Content="' this._XmlEsc(it) '"/>'
        }
        selAttr := (selIdx == "") ? "" : ' SelectedIndex="' selIdx '"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="80" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<ComboBox Name="' name '" Width="130" MinHeight="24" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"' selAttr '>' itemsXaml '</ComboBox>'
            . '</StackPanel>'
    }
