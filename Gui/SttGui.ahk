#Requires AutoHotkey v2.0

; =================================================================
; 语音转文字窗口（SttGui）—— XAML 版，本地流式识别
; 工具页入口 → 打开窗口 →「开始」边说边出字 →「停止」出最终结果 → 可复制。
; 全部本地 CPU 推理，不联网。
;
; 模型：x-asr streaming zipformer2 transducer（中英混排，带标点）
;   目录 models\stt_stream\ —— encoder/decoder/joiner + tokens.txt + bpe.model
;   chunk 档位 160/480/960/1920ms，见 SttGui.StreamPkg（默认 480ms）
; 见 Main\Util\SttUtil.ahk 的 SttEngine.Stream* 系列封装。
; 西班牙语、法语、德语使用 Kroko 流式模型，首次使用时按需下载。
; 默认不置顶；窗口内提供「窗口置顶」可选框。
; =================================================================

class SttGui {
    ; ---------- 单例入口 ----------
    static instances := Map()
    static activeDownload := ""

    static _promptQueued := false
    static _extensionInstalling := false

    ; 语音入口共用的自检。引擎和模型就绪时返回 true，模型未就绪时再询问下载。
    static RequestModelDownload(language) {
        if (SttGui._extensionInstalling)
            return false
        engine := InitSttEngine()
        if (engine._TryLoadDll() && engine.IsStreamModelReady(language))
            return true
        if (IsObject(SttGui.activeDownload)) {
            if (IsObject(SttGui.activeDownload.progress))
                SetTimer(ObjBindMethod(SttGui.activeDownload.progress, "Show"), -1)
            return false
        }
        ; 离开语音按钮的点击回调再开确认框，避免在回调里同步开窗。
        if (SttGui._promptQueued)
            return false
        SttGui._promptQueued := true
        SetTimer(ObjBindMethod(SttGui, "_PromptModelDownload", language), -1)
        return false
    }

    static _PromptModelDownload(language) {
        try {
            engine := InitSttEngine()
            if (SttGui._extensionInstalling || IsObject(SttGui.activeDownload))
                return
            if (!engine._TryLoadDll()) {
                if (RmtDialog.Choose(GetLang("语音引擎未就绪，是否下载语音扩展？"), GetLang("提示")
                    , [GetLang("下载语音扩展"), GetLang("取消")]) == 1)
                    SttGui._InstallVoiceExtension(language)
                return
            }
            if (engine.IsStreamModelReady(language))
                return
            choice := RmtDialog.Choose(GetLang("语音识别模型未就绪，是否下载？"), GetLang("提示"), [GetLang("下载识别模型"), GetLang("取消")])
            if (choice != 1)
                return
            SttGui._BeginModelDownload(language)
        } finally {
            SttGui._promptQueued := false
        }
    }

    static _BeginModelDownload(language) {
        if (IsObject(SttGui.activeDownload))
            return true
        inst := SttGui()
        inst._StartModelDownload(language)
        return inst.downloadState == "dl" || inst.downloadState == "ex"
    }

    static DownloadVoiceExtension(*) {
        SttGui._InstallVoiceExtension(SttEngine.DefaultLanguage())
    }

    static _InstallVoiceExtension(language) {
        if (SttGui._extensionInstalling)
            return
        SttGui._extensionInstalling := true
        try {
            result := SttGui._DownloadExtensionFiles()
            if (result == "cancel")
                return
            if (result != "ok")
                throw Error("Voice extension download failed")
            try MyMainWin.RefreshVoiceExtensionButton()
            engine := InitSttEngine()
            if (!engine._TryLoadDll()) {
                Toast.Warning(GetLang("语音引擎未就绪"))
                return
            }
            voice := InitVoiceEngine()
            if (!voice.IsSupported()) {
                voice._InitEngine()
                voice.Start()
            }
            if (IsObject(SttGui.activeDownload)) {
                SttGui.activeDownload.progress.Show()
            } else if (!engine.IsStreamModelReady(language)) {
                SttGui._BeginModelDownload(language)
            } else {
                Toast.Success(GetLang("语音扩展已就绪"))
            }
        } catch {
            Toast.Error(GetLang("语音扩展下载失败，请稍后重试"))
        } finally SttGui._extensionInstalling := false
    }

    static MissingVoiceExtensionFiles() {
        runDir := A_WorkingDir "\Plugins\Voice\" (A_PtrSize == 8 ? "x64" : "x86")
        runtimeFiles := ["sherpa-onnx-c-api.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll"
            , "vcruntime140.dll", "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "api-ms-win-core-path-l1-1-0.dll"]
        if (A_PtrSize == 8)
            runtimeFiles.Push("vcruntime140_1.dll")
        runtimeFiles.Push("VoiceDll.dll")

        missing := []
        for file in runtimeFiles
            if (RmtAssetMissing(runDir "\" file))
                missing.Push({fullPath: runDir "\" file, entry: file})

        kwsDir := A_WorkingDir "\Plugins\Voice\models\kws\"
        kwsFiles := ["decoder-epoch-13-avg-2-chunk-16-left-64.onnx", "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
            , "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx", "tokens.txt"]
        for file in kwsFiles
            if (RmtAssetMissing(kwsDir file))
                missing.Push({fullPath: kwsDir file, entry: file})

        return missing
    }

    static _DownloadExtensionFiles() {
        missing := SttGui.MissingVoiceExtensionFiles()
        if (!missing.Length)
            return "ok"

        runtimeUrl := RmtAssetsBaseUrl(RmtAssetsReleaseTag())
        progress := RmtProgress(GetLang("下载语音扩展"), GetLang("准备下载"), XamlWin.ActiveOwner(), GetLang("取消下载"))
        progress.Show()
        try {
            progress.Report("Voice.zip")
            return DownloadRmtAssetBundle(runtimeUrl "Voice.zip", missing, progress)
        } finally progress.Close()
    }

    ; 流式模型包（chunksize 越大越准、延迟越高：160ms / 480ms / 960ms / 1920ms）
    static StreamPkg := "sherpa-onnx-x-asr-480ms-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-05"
    ; Banafo Kroko-ASR 社区模型（CC BY-SA），下载包中的 README 保留上游署名与许可链接。
    static KrokoArchiveBytes := Map("es", 124394665, "fr", 57220361, "de", 57565698)
    static ItalianModelSource := "https://huggingface.co/Banafo/Kroko-ASR/resolve/d45212aeb212dd66083dd22710c9954f40ff8cc1/Kroko-IT-Community-64-L-Streaming-001.data"

    static ShowGui() {
        key := "global"
        if (SttGui.instances.Has(key)) {
            inst := SttGui.instances[key]
            if (inst.hasGui) {
                try WinActivate("ahk_id " inst.Hwnd())
                return
            }
            SttGui.instances.Delete(key)
        }
        inst := SttGui()
        SttGui.instances[key] := inst
        inst._BuildAndShow()
    }

    __New() {
        this.ui := ""
        this.hasGui := false
        this.language := SttEngine.DefaultLanguage()
        this.recording := false
        this.recordStartTick := 0
        this.lastLiveText := ""        ; 上一次 Poll 到的文本（避免重复入队）
        this.shownText := ""           ; 已上屏文本
        this.pendingText := ""         ; 待逐字上屏队列（平滑渲染用）
        this.liveRate := 1.0           ; 每 tick 放字数（按积压量自适应）
        this.liveAcc := 0.0            ; 小数累加器
        this.loading := false          ; 正在加载模型（会阻塞，用于状态提示）
        ; 下载流程状态："" 无 / "dl" 下载中 / "ex" 解压中 / "err" 失败
        this.downloadState := ""
        this.dlQueue := []             ; 待下载模型队列
        this.dlPid := 0
        this.dlTar := ""
        this.dlBytes := 0
        this.dlExpectedBytes := 0
        this.dlDir := ""
        this.dlSpec := ""              ; 当前模型规格（Map）
        this.progress := ""
        this._lastProgressTick := 0
        this._topOn := false
        this.timerFunc := ObjBindMethod(this, "OnTimer")
        this.preloadFunc := ObjBindMethod(this, "OnPreload")
    }

    ; 窗口打开后预热：先把流式模型加载好（约 0.6s），让「开始」几乎零等待。
    ; 离线精修模型（约 0.8s）不在这里加载——推迟到点停止时，反正那时也要等结果。
    OnPreload() {
        if (!this.hasGui || !IsObject(this.ui))
            return
        engine := InitSttEngine()
        if (engine.streamLanguage == this.language || !engine.IsStreamReady(this.language) || engine.StreamBusy())
            return
        this.loading := true
        this._RefreshUi()
        try engine.StreamEnsureInit(this.language)
        this.loading := false
        try this._RefreshUi()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ; ---------- 模型下载清单 ----------
    ; 返回所选语言缺失的模型规格
    _MissingModels(language) {
        engine := InitSttEngine()
        if (engine.IsStreamModelReady(language))
            return []
        language := SttEngine.ModelLanguage(language)
        if (language == "zh-en")
            return [Map(
                "pkg", SttGui.StreamPkg,
                "url", RmtAssetsBaseUrl("Common") SttGui.StreamPkg ".tar.bz2",
                "dir", engine.StreamModelDir,
                "files", ["encoder.int8.onnx", "decoder.onnx", "joiner.int8.onnx", "tokens.txt", "bpe.model"],
                "minBytes", 100 * 1024 * 1024
            )]
        if (language == "it")
            return [Map(
                "url", SttGui.ItalianModelSource,
                "dir", engine.StreamDirectory(language),
                "files", ["encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt", "voice-models-LICENSE.txt"],
                "krokoBlocks", [154878660, 617488, 336817, 6107],
                "exactBytes", 155839229
            )]
        pkg := "sherpa-onnx-streaming-zipformer-" language "-kroko-2025-08-06"
        return [Map(
            "pkg", pkg,
            "url", "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/" pkg ".tar.bz2",
            "dir", engine.StreamDirectory(language),
            "files", ["encoder.onnx", "decoder.onnx", "joiner.onnx", "README.md", "tokens.txt"],
            "exactBytes", SttGui.KrokoArchiveBytes[language]
        )]
    }

    _BuildAndShow() {
        global MainSoftData
        this.hasGui := true
        title := GetLang("语音转文字")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("12,10")
        body.Rows("Auto", "26", "40", "Auto", "*", "Auto")

        selector := body.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,6")
        selector.Add("TextBlock").Text(GetLang("识别语言")).VerticalAlignment("Center").Margin("0,0,10,0")
        languageItems := ""
        selectedIndex := 0
        for code, info in SttEngine.LanguageModels {
            languageItems .= LanguageOptionXaml(code, code == "zh-en" ? GetLang("中英混合") : info.label, info.flag)
            if (code == this.language)
                selectedIndex := A_Index - 1
        }

        ; 状态行
        body.Add("TextBlock").Grid_Row(1).Name("TxtStatus").Text("").Foreground("{DynamicResource TextMain}")
            .VerticalAlignment("Center").TextTrimming("CharacterEllipsis")

        ; 按钮行（置顶开关靠右）
        btnRow := body.Add("Grid").Grid_Row(2)
        btnRow.Cols("Auto", "Auto", "Auto", "Auto", "*", "Auto")
        btnRow.Add("Button").Grid_Column(0).Name("BtnStart").Content(GetLang("开始")).MinWidth(80).Padding("8,0").Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("Button").Grid_Column(1).Name("BtnStop").Content(GetLang("停止")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("Button").Grid_Column(2).Name("BtnCopy").Content(GetLang("复制")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("Button").Grid_Column(3).Name("BtnClear").Content(GetLang("清空")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("CheckBox").Grid_Column(5).Name("TopCon").Content(GetLang("窗口置顶"))
            .VerticalAlignment("Center").Margin("0,0,0,0").Foreground("{DynamicResource TextMain}")

        ; 结果标题
        body.Add("TextBlock").Grid_Row(3).Text(GetLang("识别结果：")).Margin("0,8,0,4").VerticalAlignment("Center")

        ; 结果编辑框（只读，可全选复制）
        body.Add("TextBox").Grid_Row(4).Name("EdResult").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top").Margin("0,0,0,4")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 提示文案
        body.Add("TextBlock").Grid_Row(5).Text(GetLang("语音在本地实时转写。首次使用某种语言时需下载模型。"))
            .Foreground("{DynamicResource TextSub}").TextWrapping("Wrap").Margin("0,2,0,0")

        ; === 创建 XAMLHost ===
        ownerHwnd := (IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.HasProp("Hwnd")) ? MainSoftData.MyGui.Hwnd : 0
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        selector.Add("ComboBox", languageItems).Name("SttLanguage").MinWidth(155).MinHeight(28).SelectedIndex(selectedIndex)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", ownerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="640" Height="440"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnClose"))
        this.ui.OnEvent("BtnStart", "Click", ObjBindMethod(this, "OnStartClick"))
        this.ui.OnEvent("BtnStop", "Click", ObjBindMethod(this, "OnStopClick"))
        this.ui.OnEvent("BtnCopy", "Click", ObjBindMethod(this, "OnCopyClick"))
        this.ui.OnEvent("BtnClear", "Click", ObjBindMethod(this, "OnClearClick"))
        this.ui.OnEvent("SttLanguage", "SelectionChanged", ObjBindMethod(this, "OnLanguageChanged"))
        this.ui.OnEvent("TopCon", "Checked", ObjBindMethod(this, "OnTogTop"))
        this.ui.OnEvent("TopCon", "Unchecked", ObjBindMethod(this, "OnTogTop"))

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this))) {
            this.hasGui := false
            SttGui.instances.Delete("global")
            return
        }
        this._RefreshUi()
        ; 100ms：管道延迟更低，同时作为逐字上屏的节拍（10 字/秒，快于说话速度）
        SetTimer(this.timerFunc, 100)
        ; 窗口已显示，300ms 后再预热模型，避免拖慢开窗本身
        SetTimer(this.preloadFunc, -300)
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this._Cleanup()
    }

    OnLanguageChanged(state, ctrl, event) {
        language := this.ui.Query(ctrl)
        if (!SttEngine.LanguageModels.Has(language) || this.recording || this.loading)
            return
        this.language := language
        this._RefreshUi()
        SetTimer(this.preloadFunc, -300)
    }

    ; ---------- 开关 ----------
    OnTogTop(state := unset, ctrl := unset, event := unset) {
        ; XAML 侧勾选/取消传 event=Checked/Unchecked；批量回传时走 state 字典
        if (IsSet(event) && event != "")
            this._topOn := (event == "Checked")
        else if (IsSet(state) && IsObject(state) && state.Has("TopCon"))
            this._topOn := (state["TopCon"] = "True" || state["TopCon"] = 1)
        else
            return
        this._ApplyTopMost()
    }

    _ApplyTopMost() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("Window", "Topmost", this._topOn ? "True" : "False")
        hwnd := this.Hwnd()
        if (hwnd)
            try WinSetAlwaysOnTop(this._topOn ? 1 : 0, "ahk_id " hwnd)
    }

    ; ---------- 状态刷新 ----------
    _RefreshUi() {
        if (!IsObject(this.ui))
            return
        engine := InitSttEngine()
        dllOk := engine.IsDllReady()
        streamOk := engine.IsStreamModelReady(this.language)
        download := SttGui.activeDownload
        downloading := IsObject(download)
            && SttEngine.ModelLanguage(download.language) == SttEngine.ModelLanguage(this.language)
        canStart := !this.recording && !this.loading && !downloading

        if (this.loading) {
            status := GetLang("模型正在加载…")
        } else if (downloading && download.downloadState == "dl") {
            status := GetLang("模型下载中，请稍候")
        } else if (downloading) {
            status := GetLang("模型解压中……")
        } else if (this.recording) {
            status := GetLang("正在聆听…")
        } else if (!dllOk) {
            status := GetLang("语音插件未安装（缺少 VoiceDll.dll）")
        } else if (!streamOk) {
            status := GetLang("识别模型未就绪，请先下载模型")
        } else if (engine.streamLanguage != this.language) {
            status := GetLang("就绪（模型预热中）")
        } else {
            status := GetLang("就绪（流式模型已加载）")
        }
        this.ui.Update("TxtStatus", "Text", status)
        this.ui.Update("BtnStart", "Content", dllOk && streamOk ? GetLang("开始") : GetLang("下载识别模型"))
        this.ui.Update("BtnStart", "IsEnabled", canStart ? "True" : "False")
        this.ui.Update("SttLanguage", "IsEnabled", canStart ? "True" : "False")
        this.ui.Update("BtnStop", "IsEnabled", this.recording ? "True" : "False")
    }

    _FormatElapsed() {
        sec := Floor((A_TickCount - this.recordStartTick) / 1000)
        return Format("{:02d}:{:02d}", Floor(sec / 60), Mod(sec, 60))
    }

    _DownloadPercent() => Min(100, Floor(100 * this.dlBytes / this.dlExpectedBytes))

    _DownloadProgressText() {
        status := GetLang("模型下载中，请稍候") "  " Format("{:.1f}", this.dlBytes / 1000000)
        if (this.dlExpectedBytes > 0)
            status .= Format(" / {:.1f} MB", this.dlExpectedBytes / 1000000)
        else
            status .= " MB"
        return status
    }

    _UpdateDownloadProgress() {
        this._lastProgressTick := A_TickCount
        ; 只读取最终下载响应的长度，跳过重定向头。无长度时仍显示已下载量。
        if (!this.dlExpectedBytes) {
            try {
                headers := FileRead(this.dlTar ".headers", "UTF-8")
                if (RegExMatch(headers, "m)^HTTP/\S+ 200[^\r\n]*\R((?:[^\r\n]+\R)*)\R", &response)
                    && RegExMatch(response[1], "im)^Content-Length:[ \t]*(\d+)", &length))
                    this.dlExpectedBytes := Integer(length[1])
            }
        }
        try this.dlBytes := FileGetSize(this.dlTar)
        this.progress.Report(this._DownloadProgressText(), this.dlExpectedBytes > 0 ? this._DownloadPercent() : "")
    }

    ; ---------- 定时器：实时上屏 + 收尾轮询 + 下载进度 ----------
    OnTimer() {
        ; --- 模型下载/解压 ---
        if (this.downloadState == "dl" || this.downloadState == "ex") {
            oldState := this.downloadState
            if (!this.dlPid || !ProcessExist(this.dlPid)) {
                if (this.downloadState == "dl") {
                    try FileDelete(this.dlTar ".headers")
                    if (this._StartExtract())
                        this.downloadState := "ex"
                    else
                        this.downloadState := "err"
                } else {
                    if (!this._FinishExtract()) {
                        this.downloadState := "err"
                    } else if (this.dlQueue.Length) {
                        if (!this._StartNextDownload())
                            this.downloadState := "err"
                    } else {
                        this.downloadState := ""
                    }
                }
            }
            if (this.downloadState == "dl") {
                if (oldState != "dl" || A_TickCount - this._lastProgressTick >= 500)
                    this._UpdateDownloadProgress()
            } else if (oldState != this.downloadState) {
                if (this.downloadState == "ex") {
                    this.progress.Report(GetLang("模型解压中……"))
                    if (SttGui.instances.Has("global"))
                        SttGui.instances["global"]._RefreshUi()
                    return
                }
                SttGui.activeDownload := ""
                this._ClearDownloadFiles()
                this.progress.Close()
                this.progress := ""
                SetTimer(this.timerFunc, 0)
                if (SttGui.instances.Has("global")) {
                    window := SttGui.instances["global"]
                    window._RefreshUi()
                    SetTimer(window.preloadFunc, -300)
                }
                if (this.downloadState == "")
                    Toast.Success(GetLang("语音识别模型下载成功"))
                else
                    Toast.Error(GetLang("模型下载失败，请检查网络后重试"))
            }
            return
        }

        if (!this.hasGui || !IsObject(this.ui))
            return

        if (!this.recording)
            return

        engine := InitSttEngine()

        ; --- 流式：增量上屏（平滑逐字渲染） ---
        txt := engine.StreamPoll()
        if (txt != this.lastLiveText) {
            this.lastLiveText := txt
            this._EnqueueLive(txt)
        }
        this._FlushLive()
    }

    ; ---------- 平滑上屏：把模型一次性吐出的一块文本，按节拍逐字流出 ----------
    ; 模型每 ~0.7s 出一个 chunk（5~7 字），整段替换会一顿一顿；
    ; 这里把新增部分排进队列，每 tick 追加 1~3 字，观感即匀速流出，真实延迟不变。
    _EnqueueLive(txt) {
        if (txt == "")
            return
        ; 已知文本 = 已上屏 + 待上屏队列。Poll 返回的是累积全文，
        ; 必须按「已知文本」取差集，否则会把队列里未上屏的部分重复追加。
        known := this.shownText this.pendingText
        newPart := (known == "") ? txt : (InStr(txt, known) == 1 ? SubStr(txt, StrLen(known) + 1) : "")
        if (known != "" && newPart == "") {
            ; 模型回溯改写了已上屏内容：直接整段替换为最新结果，放弃动画
            this._SetFinalText(txt)
            return
        }
        this.pendingText .= newPart

        ; 放字速率 = 积压量 / 目标排空时长。
        ; 排空时长决定「显示滞后语音」多少：3 拍=300ms，够平滑又不至于落后。
        ; 下限 1.0 字/拍（10 字/秒）必须高于说话速度，否则滞后会越积越多；
        ; 积压超 8 字说明落后了，压到 2 拍内追平。
        plen := StrLen(this.pendingText)
        div := (plen > 8) ? 2.0 : 3.0
        this.liveRate := Min(4.0, Max(1.0, plen / div))
    }

    ; 按小数累加器匀速放字（不足 1 字时攒着，下一 tick 再放）
    _FlushLive() {
        if (this.pendingText == "")
            return
        this.liveAcc += this.liveRate
        n := Floor(this.liveAcc)
        if (n < 1)
            return
        if (n > StrLen(this.pendingText))
            n := StrLen(this.pendingText)
        this.liveAcc := 0
        this.shownText .= SubStr(this.pendingText, 1, n)
        this.pendingText := SubStr(this.pendingText, n + 1)
        this._RenderResult(this.shownText)
    }

    ; 写结果框并滚到末尾
    _RenderResult(t) {
        this.ui.Update("EdResult", "Text", t)
        try this.ui.Update("EdResult", "CaretIndex", StrLen(t))
    }

    ; 最终文本（精修结果/回溯修正）：整段落地，不走动画
    _SetFinalText(t) {
        this.pendingText := ""
        this.shownText := t
        this.liveAcc := 0.0
        this._RenderResult(t)
    }

    ; ---------- 按钮 ----------
    OnStartClick(state := "", ctrl := "", event := "") {
        engine := InitSttEngine()
        if (this.recording || this.loading)
            return

        if (!SttGui.RequestModelDownload(this.language))
            return
        ; 若预热还没跑完（开窗 300ms 内就点了开始），这里会阻塞加载一次；
        ; 正常情况下 OnPreload 已加载好，这一步直接返回。
        if (engine.streamLanguage != this.language) {
            this.loading := true
            this._RefreshUi()
            Sleep(50)
        }
        ok := engine.StreamBegin(this.language)
        this.loading := false
        if (!ok) {
            this.ui.Update("EdResult", "Foreground", "{DynamicResource InputText}")
            this._RefreshUi()
            this.ui.Update("TxtStatus", "Text", GetLang("开始录音失败：") engine._ErrText(engine.lastError))
            return
        }
        this.recording := true
        this.lastLiveText := ""
        this.shownText := ""
        this.pendingText := ""
        this.liveRate := 1.0
        this.liveAcc := 0.0
        this.recordStartTick := A_TickCount
        this.ui.Update("EdResult", "Text", "")
        this.ui.Update("EdResult", "Foreground", "{DynamicResource TextSub}")
        this._RefreshUi()
    }

    OnStopClick(state := "", ctrl := "", event := "") {
        if (!this.recording)
            return
        engine := InitSttEngine()
        ; 单模型：停止即收尾（refine=0），最终结果由流式识别器直接给出
        if (!engine.StreamEnd(0)) {
            this.recording := false
            this.ui.Update("EdResult", "Foreground", "{DynamicResource InputText}")
            this._RefreshUi()
            this.ui.Update("TxtStatus", "Text", GetLang("识别失败：") engine._ErrText(engine.StreamGetLastError()))
            return
        }
        this._SetFinalText(engine.StreamGetResult())
        this.recording := false
        this.ui.Update("EdResult", "Foreground", "{DynamicResource InputText}")
        this._RefreshUi()
    }

    OnCopyClick(state := "", ctrl := "", event := "") {
        text := this.ui.Query("EdResult")
        if (Trim(text) == "")
            return
        A_Clipboard := text
        this.ui.Update("TxtStatus", "Text", GetLang("已复制到剪贴板"))
    }

    OnClearClick(state := "", ctrl := "", event := "") {
        this.ui.Update("EdResult", "Text", "")
        this.ui.Update("EdResult", "Foreground", "{DynamicResource InputText}")
        this.lastLiveText := ""
        this.shownText := ""
        this.pendingText := ""
        this.liveAcc := 0.0
    }

    ; ---------- 模型按需下载（curl + tar，异步 Run + 进程轮询，支持多模型排队） ----------
    _StartModelDownload(language) {
        if (IsObject(SttGui.activeDownload))
            return
        this.language := language
        this.dlQueue := this._MissingModels(language)
        if (!this.dlQueue.Length)
            return
        if (!this._StartNextDownload()) {
            this.downloadState := "err"
            this._RefreshUi()
            Toast.Error(GetLang("模型下载启动失败，请稍后重试"))
            return
        }
        SttGui.activeDownload := this
        this.progress := RmtProgress(GetLang("下载识别模型"), GetLang("模型下载中，请稍候"))
        SetTimer(this.timerFunc, 0)
        this.progress.Show()
        if (SttGui.instances.Has("global"))
            SttGui.instances["global"]._RefreshUi()
        this._UpdateDownloadProgress()
        SetTimer(this.timerFunc, 100)
    }

    _StartNextDownload() {
        if (!this.dlQueue.Length)
            return false
        spec := this.dlQueue.RemoveAt(1)
        this.dlBytes := 0
        this.dlExpectedBytes := 0
        this.dlTar := A_Temp "\rmt-stt-model-" DllCall("GetCurrentProcessId") "-" A_TickCount ".download"
        cmd := Format('curl.exe -L --fail -s -S --suppress-connect-headers -D "{}" -o "{}" "{}"',
            this.dlTar ".headers", this.dlTar, spec["url"])
        try {
            Run(cmd, A_Temp, "Hide", &pid)
            this.dlPid := pid
            this.dlSpec := spec
            this.downloadState := "dl"
            return true
        } catch {
            this._ClearDownloadFiles()
            return false
        }
    }

    _StartExtract() {
        try {
            ; 每次使用独立目录；tar -C 要求目标目录已存在。
            if (!FileExist(this.dlTar))
                return false
            bytes := FileGetSize(this.dlTar)
            if (this.dlSpec.Has("exactBytes") ? bytes != this.dlSpec["exactBytes"] : bytes < this.dlSpec["minBytes"])
                return false
            this.dlDir := A_Temp "\rmt-stt-model-" DllCall("GetCurrentProcessId") "-" A_TickCount "-" Random(1000, 9999)
            DirCreate(this.dlDir)
            if (this.dlSpec.Has("krokoBlocks")) {
                this.dlPid := 0
                return this._ExtractKrokoModel()
            }
            cmd := Format('tar.exe -xjf "{}" -C "{}"', this.dlTar, this.dlDir)
            Run(cmd, A_Temp, "Hide", &pid)
            this.dlPid := pid
            return true
        } catch {
            return false
        }
    }

    _ExtractKrokoModel() {
        ; Kroko 社区容器：小端 UInt 长度、JSON 头，再跟四个带长度的文件。
        spec := this.dlSpec
        source := FileOpen(this.dlTar, "r")
        headerSize := source.ReadUInt()
        if (headerSize == 0 || headerSize > 4096)
            return false
        headerBytes := Buffer(headerSize)
        if (source.RawRead(headerBytes, headerSize) != headerSize)
            return false
        header := JSON.parse(StrGet(headerBytes, headerSize, "UTF-8"))
        if (!header["free"] || header["language"]["iso"] != "IT")
            return false
        chunk := Buffer(1024 * 1024)
        for i, expected in spec["krokoBlocks"] {
            if (source.ReadUInt() != expected || source.Pos + expected > source.Length)
                return false
            target := FileOpen(this.dlDir "\" spec["files"][i], "w")
            remaining := expected
            while (remaining > 0) {
                count := Min(remaining, chunk.Size)
                if (source.RawRead(chunk, count) != count || target.RawWrite(chunk, count) != count)
                    return false
                remaining -= count
            }
            target.Close()
        }
        if (!source.AtEOF)
            return false
        source.Close()
        FileAppend("Banafo Kroko-ASR, Italian 64-L Community model (CC BY-SA).`n"
            . "ONNX files extracted from the upstream container without modifying the weights.`n"
            . "https://huggingface.co/Banafo/Kroko-ASR`n" SttGui.ItalianModelSource "`n"
            , this.dlDir "\voice-models-LICENSE.txt", "UTF-8")
        return true
    }

    _FinishExtract() {
        spec := this.dlSpec
        src := spec.Has("pkg") ? this.dlDir "\" spec["pkg"] : this.dlDir
        files := spec.Has("files") ? spec["files"] : ["model.int8.onnx", "tokens.txt"]
        try {
            ; 校验完整文件集后再部署，避免损坏/不完整的压缩包被当作成功。
            for f in files {
                if (!FileExist(src "\" f) || FileGetSize(src "\" f) == 0)
                    return false
            }
            DirCreate(spec["dir"])
            for f in files
                FileCopy(src "\" f, spec["dir"] "\" f, true)
            license := "voice-models-LICENSE.txt"
            if (FileExist(src "\" license) && !spec.Has("krokoBlocks"))
                FileCopy(src "\" license, spec["dir"] "\" license, true)
        } catch {
            return false
        }
        return true
    }

    _ClearDownloadFiles() {
        if (this.dlTar != "") {
            try FileDelete(this.dlTar ".headers")
            try FileDelete(this.dlTar)
        }
        if (this.dlDir != "")
            try DirDelete(this.dlDir, true)
        this.dlTar := ""
        this.dlDir := ""
    }

    ; ---------- 关闭 ----------
    _Cleanup() {
        if (this != SttGui.activeDownload)
            SetTimer(this.timerFunc, 0)
        SetTimer(this.preloadFunc, 0)
        engine := InitSttEngine()
        if (this.recording)
            engine.StreamCancel()
        ; 识别中则等下一轮轮询自然结束（结果丢弃）；释放模型回收内存
        if (!engine.StreamBusy())
            engine.Close()
        this.ui := ""
        this.hasGui := false
        if (SttGui.instances.Has("global"))
            SttGui.instances.Delete("global")
    }

    OnClose(state := "", ctrl := "", event := "") {
        if (IsObject(this.ui))
            try this.ui.Update("Window", "Close", "")
    }
}
