
    _AiNormalizeNewlines(text, forTextBox := true) {
        text := StrReplace(text, "`r`n", "`n")
        text := StrReplace(text, "`r", "`n")
        text := StrReplace(text, Chr(0x85), "`n")
        text := StrReplace(text, Chr(0x2028), "`n")
        text := StrReplace(text, Chr(0x2029), "`n")
        if (forTextBox)
            return StrReplace(text, "`n", "`r`n")
        return text
    }

    _AiIsStickBottom(t) {
        sh := ""
        try sh := this.ui.Query("SideAiPane_" t ">ScrollableHeight")
        if (sh == "" || !IsNumber(sh) || Float(sh) <= 2)
            return true
        vo := 0, vh := 0, eh := 0
        try vo := Float(this.ui.Query("SideAiPane_" t ">VerticalOffset"))
        try vh := Float(this.ui.Query("SideAiPane_" t ">ViewportHeight"))
        try eh := Float(this.ui.Query("SideAiPane_" t ">ExtentHeight"))
        if (eh <= 0)
            return true
        return (vo + vh >= eh - 12)
    }

    _AiScrollToEndSoon(t) {
        this._aiScrollTab := t
        SetTimer(this.aiScrollTick, -40)
    }

    _AiScrollPending() {
        t := this._aiScrollTab
        if (t < 1)
            return
        try this.ui.Update("SideAiPane_" t, "ScrollToEnd", "")
    }

    OnAiInputChanged(t, state, ctrl, event) {
        ; 高度由 TextBox 自己按内容重排，这里不用再量一次、也不用发渲染指令
        this._AiNormalizeInputBox(t)
        this._AiSyncPlaceholder(t)
        ; 首次输入时校准一次行高（决定「最多几行」的上限），量到之后不再重复
        if (!IsObject(this._aiRowH) || !this._aiRowH.Has(t)) {
            this._aiFitTab := t
            SetTimer(this.aiFitTick, -30)
        }
    }

    _AiNormalizeInputBox(t) {
        if (this._aiNormGuard.Has(t) && this._aiNormGuard[t])
            return
        text := ""
        try text := this.ui.Query("AiInput_" t)
        if (text == "")
            return
        norm := this._AiNormalizeNewlines(text, true)
        if (norm == text)
            return
        caret := StrLen(text)
        try {
            v := this.ui.Query("AiInput_" t ">CaretIndex")
            if (v != "")
                caret := Integer(v)
        }
        if (caret < 0)
            caret := 0
        if (caret > StrLen(text))
            caret := StrLen(text)
        newCaret := StrLen(this._AiNormalizeNewlines(SubStr(text, 1, caret), true))
        this._aiNormGuard[t] := true
        try {
            this.ui.Update("AiInput_" t, "Text", norm)
            this.ui.Update("AiInput_" t, "CaretIndex", String(newCaret))
        } finally {
            this._aiNormGuard[t] := false
        }
    }

    OnAiInputEnter(t, state, ctrl, event) {
        mods := ""
        if (IsObject(state) && state.Has("KeyModifiers"))
            mods := state["KeyModifiers"]
        if (InStr(mods, "Shift") || InStr(mods, "Alt")) {
            this._AiInsertNewline(t)
            return
        }
        this._AiSendTabInput(t)
    }

    OnAiSendClick(t, state, ctrl, event) {
        if (this._AiIsBusy(t)) {
            this._AiCancelFromUser(t)
            return
        }
        this._AiSendTabInput(t)
    }

    OnAiInputPasteKey(t, state, ctrl, event) {
        mods := ""
        if (IsObject(state) && state.Has("KeyModifiers"))
            mods := state["KeyModifiers"]
        if (!InStr(mods, "Ctrl"))
            return
        if (this._AiPasteClipboardFiles(t))
            return
        if (DllCall("IsClipboardFormatAvailable", "UInt", 8) || DllCall("IsClipboardFormatAvailable", "UInt", 2)) {
            if (this._AiPasteClipboardImage(t))
                return
        }
    }

    _AiPasteClipboardFiles(t) {
        if (!DllCall("IsClipboardFormatAvailable", "UInt", 15) || !DllCall("OpenClipboard", "Ptr", 0))
            return false
        files := []
        try {
            drop := DllCall("GetClipboardData", "UInt", 15, "Ptr")
            if (!drop)
                return false
            count := DllCall("shell32\DragQueryFileW", "Ptr", drop, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0, "UInt")
            loop Min(count, 12) {
                index := A_Index - 1
                len := DllCall("shell32\DragQueryFileW", "Ptr", drop, "UInt", index, "Ptr", 0, "UInt", 0, "UInt")
                if (!len || len > 32767)
                    continue
                buf := Buffer((len + 1) * 2)
                if DllCall("shell32\DragQueryFileW", "Ptr", drop, "UInt", index, "Ptr", buf, "UInt", len + 1, "UInt")
                    files.Push(StrGet(buf, len, "UTF-16"))
            }
        } finally DllCall("CloseClipboard")
        for path in files {
            attr := FileExist(path)
            if (attr && !InStr(attr, "D"))
                this._AiAddAttach(t, this._AiIsImageFile(path) ? "image" : "file", path)
        }
        return files.Length > 0
    }

    OnAiMicClick(t, *) {
        if (!IsObject(this._aiRec))
            this._aiRec := Map()
        if (this._aiRec.Has(t) && this._aiRec[t]) {
            this._AiStopRec(t)
            return
        }
        language := SttEngine.DefaultLanguage()
        if (!SttGui.RequestModelDownload(language))
            return
        engine := InitSttEngine()
        inputBefore := ""
        try inputBefore := Trim(this.ui.Query("AiInput_" t))
        initializing := engine.streamLanguage != language
        if (initializing && inputBefore == "") {
            try this.ui.Update("AiInputPh_" t, "Text", GetLang("模型正在加载…"))
            try this.ui.Update("AiInputPh_" t, "Visibility", "Visible")
            Sleep(50)
        }
        if (!engine.StreamBegin(language)) {
            this._AiSyncPlaceholder(t)
            Toast.Error(GetLang("开始录音失败：") engine._ErrText(engine.lastError))
            return
        }
        this._aiRec[t] := true
        this._aiSttTab := t
        this._aiSttBase := ""
        try this._aiSttBase := this.ui.Query("AiInput_" t)
        this._aiSttLive := ""
        try this.ui.Update("AiInput_" t, "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("AiMic_" t, "Foreground", "{DynamicResource Accent}")
        try this.ui.Update("AiMic_" t, "ToolTip", GetLang("停止录音"))
        try this.ui.Update("AiInputPh_" t, "Text", GetLang("正在聆听…"))
        this._AiSyncPlaceholder(t)
        SetTimer(this.aiSttTick, 150)
    }

    _AiPollStt() {
        t := this._aiSttTab
        if (t < 1 || !IsObject(this._aiRec) || !this._aiRec.Has(t) || !this._aiRec[t]) {
            SetTimer(this.aiSttTick, 0)
            return
        }
        engine := InitSttEngine()
        live := ""
        try live := engine.StreamPoll()
        if (Trim(live) != "" && live != this._aiSttLive)
            this._AiSetVoiceText(t, live)
    }

    _AiSetVoiceText(t, text) {
        this._aiSttLive := text
        base := this._aiSttBase
        separator := (base != "" && !RegExMatch(base, "\s$")) ? " " : ""
        this.ui.Update("AiInput_" t, "Text", base separator text)
        try this.ui.Update("AiInputPh_" t, "Text", GetLang("询问关于宏的任何问题…"))
        try this.ui.Update("AiInputPh_" t, "Visibility", "Collapsed")
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
        this._AiSyncPlaceholder(t)
    }

    _AiStopRec(t) {
        if (!IsObject(this._aiRec))
            this._aiRec := Map()
        this._aiRec[t] := false
        SetTimer(this.aiSttTick, 0)
        try this.ui.Update("AiInput_" t, "Foreground", "{DynamicResource InputText}")
        try this.ui.Update("AiMic_" t, "Foreground", "{DynamicResource TextMain}")
        try this.ui.Update("AiMic_" t, "ToolTip", GetLang("语音输入"))
        try this.ui.Update("AiInputPh_" t, "Text", GetLang("询问关于宏的任何问题…"))
        engine := InitSttEngine()
        if (!IsObject(engine))
            return
        if (!engine.StreamEnd(0)) {
            this._AiSyncPlaceholder(t)
            return
        }
        loop 40 {
            st := engine.StreamGetState()
            if (st == 3 || st == 4)
                break
            Sleep(50)
        }
        result := Trim(engine.StreamGetResult())
        if (result != "" && result != this._aiSttLive)
            this._AiSetVoiceText(t, result)
        this._AiSyncPlaceholder(t)
    }

    ; 拖入文件：顶部芯片（仅文件名，下划线，整块删除）
    OnAiInputFileDrop(t, state, ctrl, event) {
        files := this._AiParseDropFiles(state)
        if (files.Length < 1)
            return
        for path in files {
            path := Trim(path)
            if (path == "" || !FileExist(path))
                continue
            this._AiAddAttach(t, this._AiIsImageFile(path) ? "image" : "file", path)
        }
    }

    _AiParseDropFiles(state) {
        files := []
        raw := ""
        if (IsObject(state)) {
            if (state.Has("DropFiles") && Type(state["DropFiles"]) = "Array")
                return state["DropFiles"]
            if (state.Has("FileDrop"))
                raw := String(state["FileDrop"])
            else if (state.Has("Drop"))
                raw := String(state["Drop"])
        }
        if (raw == "")
            return files
        for part in StrSplit(raw, "|") {
            p := Trim(part)
            if (p != "")
                files.Push(p)
        }
        return files
    }

    _AiAttachList(t) {
        if (!IsObject(this._aiAttach))
            this._aiAttach := Map()
        if (!this._aiAttach.Has(t))
            this._aiAttach[t] := []
        return this._aiAttach[t]
    }

    _AiIsImageFile(path) {
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        return (ext = "png" || ext = "jpg" || ext = "jpeg" || ext = "gif" || ext = "bmp" || ext = "webp")
    }

    _AiAddAttach(t, kind, path) {
        list := this._AiAttachList(t)
        for a in list {
            if (a["path"] = path)
                return
        }
        if (list.Length >= 12) {
            Toast.Warning(GetLang("最多可添加 12 个附件"))
            return
        }
        this._aiAttachSeq := Integer(this._aiAttachSeq) + 1
        SplitPath(path, &name)
        if (name == "")
            name := path
        list.Push(Map("id", this._aiAttachSeq, "kind", kind, "path", path, "name", name))
        this._AiRefreshAttachBar(t)
    }

    _AiRemoveAttach(t, id) {
        list := this._AiAttachList(t)
        out := []
        for a in list {
            if (Integer(a["id"]) != Integer(id))
                out.Push(a)
        }
        this._aiAttach[t] := out
        this._AiRefreshAttachBar(t)
    }

    _AiClearAttach(t) {
        if (!IsObject(this._aiAttach))
            this._aiAttach := Map()
        this._aiAttach[t] := []
        this._AiRefreshAttachBar(t)
    }

    _AiRefreshAttachBar(t) {
        list := this._AiAttachList(t)
        try this.ui.Update("AiAttachBar_" t, "ClearItems", "")
        if (list.Length < 1) {
            try this.ui.Update("AiAttachBar_" t, "Visibility", "Collapsed")
            this._AiSyncPlaceholder(t)
            this._FitAiInput(t)
            return
        }
        try this.ui.Update("AiAttachBar_" t, "Visibility", "Visible")
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        for a in list {
            id := a["id"]
            if (a["kind"] = "image")
                xaml := this._AiImageChipXaml(t, id, a["path"], ns)
            else
                xaml := this._AiFileChipXaml(t, id, a["name"], ns)
            try this.ui.Update("AiAttachBar_" t, "AddXamlItem", xaml)
            this._AiBindAttachEvents(t, id)
        }
        this._AiSyncPlaceholder(t)
        this._FitAiInput(t)
    }

    _AiBindAttachEvents(t, id) {
        ; 动态 AddXamlItem 后必须 BindEvent，否则引擎未挂 WPF 事件，点击无反应
        try this._Bind("AiAttOpen_" t "_" id, "MouseLeftButtonUp", ObjBindMethod(this, "OnAiAttachOpen", t, id))
        try this._Bind("AiAttDel_" t "_" id, "Click", ObjBindMethod(this, "OnAiAttachDel", t, id))
    }

    _AiFileChipXaml(t, id, name, ns) {
        return this._AiChipWrapXaml(t, id, ns
            , '<TextBlock Name="AiAttOpen_' t '_' id '" Text="' this._XmlEsc(name) '" TextDecorations="Underline"'
            . ' Cursor="Hand" VerticalAlignment="Center" Margin="4,2,4,2" Foreground="{DynamicResource Accent}" FontSize="' this._AiChatBodyFontSize() '"/>')
    }

    _AiImageChipXaml(t, id, path, ns) {
        src := this._AiFileUri(path)
        return this._AiChipWrapXaml(t, id, ns
            , '<Image Name="AiAttOpen_' t '_' id '" Source="' this._XmlEsc(src) '" Width="32" Height="32"'
            . ' Margin="2" Stretch="UniformToFill" Cursor="Hand"/>')
    }

    _AiChipWrapXaml(t, id, ns, inner) {
        del := "AiAttDel_" t "_" id
        return '<Grid ' ns ' Margin="0,0,8,2" Background="Transparent">'
            . '<Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" CornerRadius="3" Padding="4,4,16,4">' inner '</Border>'
            . '<Button Name="' del '" Width="14" Height="14" Padding="0"'
            . ' HorizontalAlignment="Right" VerticalAlignment="Top"'
            . ' Background="{DynamicResource ControlBorder}" BorderThickness="0" Cursor="Hand"'
            . ' ToolTip="' this._XmlEsc(GetLang("删除")) '" Focusable="False" Panel.ZIndex="2">'
            . '<Button.Style><Style TargetType="Button">'
            . '<Setter Property="Opacity" Value="0"/>'
            . '<Style.Triggers>'
            . '<DataTrigger Binding="{Binding IsMouseOver, RelativeSource={RelativeSource AncestorType=Grid}}" Value="True">'
            . '<Setter Property="Opacity" Value="1"/>'
            . '</DataTrigger></Style.Triggers></Style></Button.Style>'
            . '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="7" Width="14" Height="14">'
            . '<TextBlock Text="' Chr(0xE711) '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"'
            . ' FontSize="8" Foreground="{DynamicResource TitleBarForeground}"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border></ControlTemplate></Button.Template></Button></Grid>'
    }

    _AiFileUri(path) {
        p := StrReplace(path, "\", "/")
        p := StrReplace(p, " ", "%20")
        if (RegExMatch(p, "^[A-Za-z]:"))
            p := "/" p
        return "file://" p
    }

    OnAiAttachOpen(t, id, *) {
        for a in this._AiAttachList(t) {
            if (Integer(a["id"]) = Integer(id)) {
                try Run('"' a["path"] '"')
                return
            }
        }
    }

    OnAiAttachDel(t, id, *) {
        this._AiRemoveAttach(t, id)
    }

    _AiSyncPlaceholder(t) {
        text := ""
        try text := this.ui.Query("AiInput_" t)
        rec := IsObject(this._aiRec) && this._aiRec.Has(t) && this._aiRec[t]
        hasAtt := this._AiAttachList(t).Length > 0
        hasLive := rec && this._aiSttLive != ""
        vis := (Trim(text) == "" && !hasAtt && !hasLive) ? "Visible" : "Collapsed"
        try this.ui.Update("AiInputPh_" t, "Visibility", vis)
    }

    _AiPasteClipboardImage(t) {
        dir := A_Temp "\RMT\AiPaste"
        if (!DirExist(dir))
            DirCreate(dir)
        path := dir "\" FormatTime(A_Now, "yyyyMMddHHmmss") "_" Random(100, 999) ".png"
        pBm := 0
        try pBm := Gdip_CreateBitmapFromClipboard()
        if (!pBm)
            return false
        ok := false
        try {
            Gdip_SaveBitmapToFile(pBm, path)
            ok := FileExist(path)
        }
        try Gdip_DisposeImage(pBm)
        if (!ok)
            return false
        this._AiAddAttach(t, "image", path)
        return true
    }

    _AiAppendInputText(t, extra) {
        extra := Trim(extra)
        if (extra == "")
            return
        text := ""
        try text := this.ui.Query("AiInput_" t)
        text := this._AiNormalizeNewlines(text, true)
        if (text != "" && !RegExMatch(text, "[`r`n\s]$"))
            text .= " "
        text .= extra
        try this.ui.Update("AiInput_" t, "Text", text)
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
        this._AiSyncPlaceholder(t)
    }

    _AiConsumeAttachText(t) {
        list := this._AiAttachList(t)
        if (list.Length < 1)
            return ""
        out := ""
        for a in list {
            name := a["name"]
            path := a["path"]
            out .= (out == "" ? "" : " ") "[" name "](" this._AiEncodeFileUrl(path) ")"
        }
        this._AiClearAttach(t)
        return (out == "") ? "" : "`n" out
    }

    _AiInsertNewline(t) {
        try this.ui.Update("AiInput_" t, "InsertText", "`r`n")
        caret := ""
        try caret := this.ui.Query("AiInput_" t ">CaretIndex")
        if (caret != "" && IsNumber(caret))
            this._aiPendingCaret[t] := Integer(caret)
        this._aiFitTab := t
        SetTimer(this.aiFitTick, -30)
    }

    _FitAiInputCur() {
        this._FitAiInput(this._aiFitTab)
    }

    ; 高度由 TextBox 按内容自己撑开（XAML 里不设 Height，只留 MinHeight/MaxHeight）：
    ; 换行位置、字宽、字体回退全交给 WPF 的排版，主程序不再自己算行数。
    ; 这里只维护上限——「最多显示 N 行」有多高取决于行高，而行高只随字号变，量一次就够。
    _FitAiInput(t) {
        if (t < 1)
            return
        if (!IsObject(this._aiRowH))
            this._aiRowH := Map()
        rowH := this._aiRowH.Has(t) ? this._aiRowH[t] : 0
        if (rowH <= 0) {
            try {
                parts := StrSplit(String(this.ui.Query("AiInput_" t ">TextLines")), ",")
                if (parts.Length >= 2 && IsNumber(parts[2]))
                    rowH := Float(parts[2])
            }
            ; 量不到就先用设计值顶上，但不写缓存——下次布局好了会重新量
            if (rowH > 0)
                this._aiRowH[t] := rowH
            else
                rowH := this._AiInputExtraLineH()
        }
        maxH := this._AiInputLineH() + (this._AiInputMaxLines() - 1) * rowH
        try this.ui.Update("AiInput_" t, "MaxHeight", String(maxH))
        try this.ui.Update("AiInputHost_" t, "MaxHeight", String(maxH + this._AiAttachHostExtra(t)))
        if (IsObject(this._aiPendingCaret) && this._aiPendingCaret.Has(t)) {
            try this.ui.Update("AiInput_" t, "CaretIndex", String(this._aiPendingCaret[t]))
            this._aiPendingCaret.Delete(t)
        }
        this._AiSyncPlaceholder(t)
    }

    _AiAttachHostExtra(t) {
        if (this._AiAttachList(t).Length < 1)
            return 0
        return this._AiAttachBarH()
    }
