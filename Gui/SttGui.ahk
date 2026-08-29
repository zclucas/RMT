#Requires AutoHotkey v2.0

; =================================================================
; 语音转文字窗口（SttGui）—— XAML 版，本地流式识别（单模型）
; 工具页入口 → 打开窗口 →「开始」边说边出字 →「停止」出最终结果 → 可复制。
; 全部本地 CPU 推理，不联网。
;
; 模型：x-asr streaming zipformer2 transducer（中英混排，带标点）
;   目录 models\stt_stream\ —— encoder/decoder/joiner + tokens.txt + bpe.model
;   chunk 档位 160/480/960/1920ms，见 SttGui.StreamPkg（默认 480ms）
; 见 Main\Util\SttUtil.ahk 的 SttEngine.Stream* 系列封装。
; 模型缺失时提供「下载识别模型」按钮（按需下载，不进发布包）。
; 默认不置顶；窗口内提供「窗口置顶」可选框。
; =================================================================

class SttGui {
    ; ---------- 单例入口 ----------
    static instances := Map()

    ; 流式模型包（chunksize 越大越准、延迟越高：160ms / 480ms / 960ms / 1920ms）
    static StreamPkg := "sherpa-onnx-x-asr-480ms-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-05"

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
        this.recording := false        ; 正在采集（流式或离线）
        this.finalizing := false       ; 停止后等待最终文本（精修中）
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
        this.dlTotal := 0
        this.dlPid := 0
        this.dlTar := ""
        this.dlDir := ""
        this.dlSpec := ""              ; 当前模型规格（Map）
        this.dlCur := ""               ; 当前正在下载的模型说明
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
        if (engine.streamLoaded || !engine.IsStreamReady())
            return
        this.loading := true
        this._RefreshUi()
        try engine.StreamEnsureInit()
        this.loading := false
        try this._RefreshUi()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ; ---------- 模型下载清单 ----------
    ; 返回缺失的模型规格数组（顺序：先流式后精修）
    _MissingModels() {
        engine := InitSttEngine()
        ; 单模型：只下载流式模型（transducer 三件套 encoder/decoder/joiner + tokens）
        list := []
        if (!engine.IsStreamModelReady()) {
            list.Push(Map(
                "label", GetLang("识别模型"),
                "pkg", SttGui.StreamPkg,
                "url", "https://gh-proxy.org/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/" SttGui.StreamPkg ".tar.bz2",
                "dir", engine.StreamModelDir,
                "files", ["encoder.int8.onnx", "decoder.onnx", "joiner.int8.onnx", "tokens.txt", "bpe.model"],
                "minBytes", 100 * 1024 * 1024
            ))
        }
        return list
    }

    _BuildAndShow() {
        global MainSoftData
        this.hasGui := true
        title := GetLang("语音转文字")
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 内容 ===
        body := main.Add("Grid").Grid_Row(1).Margin("12,10")
        ; 行2（下载模型按钮）用 Auto：默认 Collapsed 时不占位
        body.Rows("26", "40", "Auto", "Auto", "*", "Auto")

        ; 状态行
        body.Add("TextBlock").Grid_Row(0).Name("TxtStatus").Text("").Foreground("{DynamicResource TextSub}")
            .VerticalAlignment("Center").TextTrimming("CharacterEllipsis")

        ; 按钮行（置顶开关靠右）
        btnRow := body.Add("Grid").Grid_Row(1)
        btnRow.Cols("Auto", "Auto", "Auto", "Auto", "*", "Auto")
        btnRow.Add("Button").Grid_Column(0).Name("BtnStart").Content(GetLang("开始")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("Button").Grid_Column(1).Name("BtnStop").Content(GetLang("停止")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("Button").Grid_Column(2).Name("BtnCopy").Content(GetLang("复制")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("Button").Grid_Column(3).Name("BtnClear").Content(GetLang("清空")).Width(80).Height(32).MinHeight(32).Margin("0,4,6,4")
        btnRow.Add("CheckBox").Grid_Column(5).Name("TopCon").Content(GetLang("窗口置顶"))
            .VerticalAlignment("Center").Margin("0,0,0,0").Foreground("{DynamicResource TextMain}")

        ; 模型缺失时的下载按钮（默认隐藏）
        body.Add("Button").Grid_Row(2).Name("BtnDownload").Content(GetLang("下载识别模型"))
            .Width(180).Height(32).MinHeight(32).HorizontalAlignment("Left").Margin("0,4,0,4").Visibility("Collapsed")

        ; 结果标题
        body.Add("TextBlock").Grid_Row(3).Text(GetLang("识别结果：")).Margin("0,8,0,4").VerticalAlignment("Center")

        ; 结果编辑框（只读，可全选复制）
        body.Add("TextBox").Grid_Row(4).Name("EdResult").TextWrapping("Wrap").IsReadOnly("True")
            .VerticalContentAlignment("Top").Margin("0,0,0,4")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 提示文案
        body.Add("TextBlock").Grid_Row(5).Text(GetLang("边说边出字，全部本地运行，不联网。支持中英文混合。"))
            .Foreground("{DynamicResource TextSub}").TextWrapping("Wrap").Margin("0,2,0,0")

        ; === 创建 XAMLHost ===
        ownerHwnd := (IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.HasProp("Hwnd")) ? MainSoftData.MyGui.Hwnd : 0
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", ownerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="580" Height="440" Opacity="0"')
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
        this.ui.OnEvent("BtnDownload", "Click", ObjBindMethod(this, "OnDownloadClick"))
        this.ui.OnEvent("TopCon", "Checked", ObjBindMethod(this, "OnTogTop"))
        this.ui.OnEvent("TopCon", "Unchecked", ObjBindMethod(this, "OnTogTop"))

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                try SetTimer((*) => this.ui.Update("Window", "Opacity", "1"), -10)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd) {
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
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this._Cleanup()
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
        engine := InitSttEngine()
        dllOk := engine.IsDllReady()
        streamOk := engine.IsStreamModelReady()
        canStart := streamOk && !this.recording && !this.finalizing
            && !this.loading && this.downloadState == ""

        ; 下载按钮：模型缺失就显示（DLL 缺失时不给下载，需重装插件）
        this.ui.Update("BtnDownload", "Visibility", (dllOk && !streamOk) ? "Visible" : "Collapsed")

        if (this.loading) {
            status := GetLang("模型加载中……")
            this.ui.Update("BtnDownload", "IsEnabled", "False")
        } else if (this.downloadState == "dl") {
            status := GetLang("模型下载中，请稍候") "（" this.dlCur "）……"
            this.ui.Update("BtnDownload", "IsEnabled", "False")
        } else if (this.downloadState == "ex") {
            status := GetLang("模型解压中……")
            this.ui.Update("BtnDownload", "IsEnabled", "False")
        } else if (this.recording) {
            status := GetLang("录音中 ") this._FormatElapsed()
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (this.finalizing) {
            status := GetLang("识别中……")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (this.downloadState == "err") {
            status := GetLang("模型下载失败，请检查网络后重试")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (!dllOk) {
            status := GetLang("语音插件未安装（缺少 VoiceDll.dll）")
        } else if (!streamOk) {
            status := GetLang("识别模型未就绪，请先下载模型")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (!engine.streamLoaded) {
            status := GetLang("就绪（模型预热中）")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else {
            status := GetLang("就绪（流式模型已加载）")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        }
        this.ui.Update("TxtStatus", "Text", status)
        this.ui.Update("BtnStart", "IsEnabled", (canStart && dllOk) ? "True" : "False")
        this.ui.Update("BtnStop", "IsEnabled", this.recording ? "True" : "False")
    }

    _FormatElapsed() {
        sec := Floor((A_TickCount - this.recordStartTick) / 1000)
        return Format("{:02d}:{:02d}", Floor(sec / 60), Mod(sec, 60))
    }

    ; ---------- 定时器：实时上屏 + 收尾轮询 + 下载进度 ----------
    OnTimer() {
        if (!this.hasGui || !IsObject(this.ui))
            return

        ; --- 模型下载/解压 ---
        if (this.downloadState == "dl" || this.downloadState == "ex") {
            if (!ProcessExist(this.dlPid)) {
                if (this.downloadState == "dl") {
                    if (this._StartExtract())
                        this.downloadState := "ex"
                    else
                        this.downloadState := "err"
                } else {
                    this._FinishExtract()
                    if (this.dlQueue.Length) {
                        if (!this._StartNextDownload())
                            this.downloadState := "err"
                    } else {
                        this.downloadState := ""
                        this.dlCur := ""
                    }
                }
            }
            this._RefreshUi()
            return
        }

        if (!this.recording && !this.finalizing)
            return

        engine := InitSttEngine()

        ; --- 流式：增量上屏（平滑逐字渲染） ---
        if (this.recording) {
            txt := engine.StreamPoll()
            if (txt != this.lastLiveText) {
                this.lastLiveText := txt
                this._EnqueueLive(txt)
            }
            this._FlushLive()
        }

        ; --- 停止后收尾 ---
        if (this.finalizing) {
            state := engine.StreamGetState()
            if (state == 3 || state == 4) {
                this.finalizing := false
                if (state == 3)
                    this._SetFinalText(engine.StreamGetResult())
                else
                    this.ui.Update("TxtStatus", "Text", GetLang("识别失败：") engine._ErrText(engine.StreamGetLastError()))
            }
        }
        this._RefreshUi()
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
        if (this.recording || this.finalizing)
            return

        if (!engine.IsStreamReady()) {
            this.ui.Update("TxtStatus", "Text", GetLang("识别模型未就绪，请先下载模型"))
            return
        }
        ; 若预热还没跑完（开窗 300ms 内就点了开始），这里会阻塞加载一次；
        ; 正常情况下 OnPreload 已加载好，这一步直接返回。
        if (!engine.streamLoaded) {
            this.loading := true
            this._RefreshUi()
        }
        ok := engine.StreamBegin()
        this.loading := false
        if (!ok) {
            this.ui.Update("TxtStatus", "Text", GetLang("开始录音失败：") engine._ErrText(engine.StreamGetLastError()))
            this._RefreshUi()
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
        this._RefreshUi()
    }

    OnStopClick(state := "", ctrl := "", event := "") {
        if (!this.recording)
            return
        engine := InitSttEngine()
        ; 单模型：停止即收尾（refine=0），最终结果由流式识别器直接给出
        if (!engine.StreamEnd(0)) {
            this.recording := false
            this.ui.Update("TxtStatus", "Text", GetLang("识别失败：") engine._ErrText(engine.StreamGetLastError()))
            this._RefreshUi()
            return
        }
        this.recording := false
        this.finalizing := true
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
        this.lastLiveText := ""
        this.shownText := ""
        this.pendingText := ""
        this.liveAcc := 0.0
    }

    ; ---------- 模型按需下载（curl + tar，异步 Run + 进程轮询，支持多模型排队） ----------
    OnDownloadClick(state := "", ctrl := "", event := "") {
        if (this.downloadState != "")
            return
        this.dlQueue := this._MissingModels()
        this.dlTotal := this.dlQueue.Length
        if (!this.dlTotal)
            return
        if (!this._StartNextDownload())
            this.downloadState := "err"
        this._RefreshUi()
    }

    _StartNextDownload() {
        if (!this.dlQueue.Length)
            return false
        spec := this.dlQueue.RemoveAt(1)
        idx := this.dlTotal - this.dlQueue.Length
        this.dlCur := spec["label"] " (" idx "/" this.dlTotal ")"
        this.dlTar := A_Temp "\rmt-stt-model.tar.bz2"
        this.dlDir := A_Temp "\rmt-stt-model"
        cmd := Format('curl.exe -k --ssl-no-revoke -L --fail -s -S -o "{}" "{}"', this.dlTar, spec["url"])
        try {
            Run(cmd, A_Temp, "Hide", &pid)
            this.dlPid := pid
            this.dlSpec := spec
            this.downloadState := "dl"
            return true
        } catch {
            return false
        }
    }

    _StartExtract() {
        if (!this.dlSpec.Has("minBytes"))
            return false
        ; 校验下载产物大小
        if (!FileExist(this.dlTar) || FileGetSize(this.dlTar) < this.dlSpec["minBytes"])
            return false
        DirDelete(this.dlDir, true)
        cmd := Format('tar.exe -xjf "{}" -C "{}"', this.dlTar, this.dlDir)
        try {
            Run(cmd, A_Temp, "Hide", &pid)
            this.dlPid := pid
            return true
        } catch {
            return false
        }
    }

    _FinishExtract() {
        spec := this.dlSpec
        src := this.dlDir "\" spec["pkg"]
        files := spec.Has("files") ? spec["files"] : ["model.int8.onnx", "tokens.txt"]
        if (FileExist(src "\" files[1])) {
            DirCreate(spec["dir"])
            for f in files {
                if (FileExist(src "\" f))
                    FileCopy(src "\" f, spec["dir"] "\" f, true)
                else
                    try this.ui.Update("TxtStatus", "Text", GetLang("模型文件缺失：") f)
            }
        }
        ; 清理临时文件
        try FileDelete(this.dlTar)
        try DirDelete(this.dlDir, true)
        this.dlTar := ""
        this.dlDir := ""
    }

    ; ---------- 关闭 ----------
    _Cleanup() {
        SetTimer(this.timerFunc, 0)
        SetTimer(this.preloadFunc, 0)
        engine := InitSttEngine()
        if (this.recording)
            engine.StreamCancel()
        ; 识别中则等下一轮轮询自然结束（结果丢弃）；释放模型回收内存
        if (!this.finalizing)
            engine.Close()
        this.ui := ""
        this.hasGui := false
        if (SttGui.instances.Has("global"))
            SttGui.instances.Delete("global")
    }

    OnClose(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        ui := this.ui
        this._Cleanup()
        try ui.Update("Window", "Close", "")
    }
}
