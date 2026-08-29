#Requires AutoHotkey v2.0

; =================================================================
; 语音转文字窗口（SttGui）—— XAML 版
; 工具页签入口 → 打开窗口 → 「开始」录音 / 「停止」并识别 → 结果可复制。
; 默认不置顶；窗口内提供「窗口置顶」可选框（XAMLHost Window.Topmost）。
; 底层引擎 Main\Util\SttUtil.ahk → VoiceDll.dll Stt_* 导出
; （sherpa-onnx OfflineRecognizer + paraformer 离线识别，与 KWS 语音触发独立）。
; 模型缺失时提供「下载模型」按钮（首次按需下载，不进发布包）。
; =================================================================

class SttGui {
    ; ---------- 单例入口 ----------
    static instances := Map()

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
        this.recording := false
        this.recordStartTick := 0
        this.decoding := false
        ; 下载流程状态："" 无 / "dl" 下载中 / "ex" 解压中 / "err" 失败
        this.downloadState := ""
        this.dlPid := 0
        this.dlTar := ""
        this.dlDir := ""
        this._topOn := false
        this.timerFunc := ObjBindMethod(this, "OnTimer")
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

        ; 按钮行（置顶可选框靠右）
        btnRow := body.Add("Grid").Grid_Row(1)
        btnRow.Cols("Auto", "Auto", "Auto", "Auto", "*", "Auto")
        ; 顺序：开始 / 停止 / 复制 / 清空 / 弹性间隔 / 置顶可选框
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
        body.Add("TextBlock").Grid_Row(5).Text(GetLang("点击开始后说话，点击停止后自动识别。模型支持中文与简单英文（无标点）。"))
            .Foreground("{DynamicResource TextSub}").TextWrapping("Wrap").Margin("0,2,0,0")

        ; === 创建 XAMLHost ===
        ownerHwnd := (IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.HasProp("Hwnd")) ? MainSoftData.MyGui.Hwnd : 0
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", ownerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="470" Height="420" Opacity="0"')
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
        SetTimer(this.timerFunc, 200)
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

    ; ---------- 置顶可选框 ----------
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
        ready := engine.IsReady()
        ; DLL 缺失时不给下载（需重装插件）
        this.ui.Update("BtnDownload", "Visibility", engine.IsModelReady() ? "Collapsed" : "Visible")
        if (this.downloadState == "dl") {
            status := GetLang("模型下载中，请稍候（约 82MB）……")
            this.ui.Update("BtnDownload", "IsEnabled", "False")
        } else if (this.downloadState == "ex") {
            status := GetLang("模型解压中……")
            this.ui.Update("BtnDownload", "IsEnabled", "False")
        } else if (this.recording) {
            status := GetLang("录音中 ") this._FormatElapsed()
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (this.decoding) {
            status := GetLang("识别中……")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (this.downloadState == "err") {
            status := GetLang("模型下载失败，请检查网络后重试")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else if (!ready) {
            status := engine.IsDllReady()
                ? GetLang("识别模型未就绪，请先下载模型")
                : GetLang("语音插件未安装（缺少 VoiceDll.dll）")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        } else {
            status := GetLang("就绪（已加载模型，约占用 80MB 内存）")
            this.ui.Update("BtnDownload", "IsEnabled", "True")
        }
        this.ui.Update("TxtStatus", "Text", status)
        this.ui.Update("BtnStart", "IsEnabled", (ready && !this.recording && !this.decoding && this.downloadState == "") ? "True" : "False")
        this.ui.Update("BtnStop", "IsEnabled", this.recording ? "True" : "False")
    }

    _FormatElapsed() {
        sec := Floor((A_TickCount - this.recordStartTick) / 1000)
        return Format("{:02d}:{:02d}", Floor(sec / 60), Mod(sec, 60))
    }

    ; ---------- 定时器：录音计时 + 解码轮询 + 下载进度 ----------
    OnTimer() {
        if (!this.hasGui || !IsObject(this.ui))
            return
        if (this.downloadState == "dl" || this.downloadState == "ex") {
            if (!ProcessExist(this.dlPid)) {
                if (this.downloadState == "dl") {
                    ; 下载完成，进入解压
                    if (this._StartExtract()) {
                        this.downloadState := "ex"
                    } else {
                        this.downloadState := "err"
                    }
                } else {
                    ; 解压完成，校验并落位
                    this._FinishExtract()
                    this.downloadState := ""
                }
            }
            this._RefreshUi()
            return
        }
        if (this.recording || this.decoding) {
            engine := InitSttEngine()
            if (this.decoding) {
                state := engine.GetState()
                if (state == 3) {
                    this.decoding := false
                    result := engine.GetResult()
                    this.ui.Update("EdResult", "Text", result)
                } else if (state == 4) {
                    this.decoding := false
                    err := engine.GetLastError()
                    this.ui.Update("TxtStatus", "Text", GetLang("识别失败：") (err != "" ? err : "未知错误"))
                }
            }
            this._RefreshUi()
        }
    }

    ; ---------- 按钮 ----------
    OnStartClick(state := "", ctrl := "", event := "") {
        engine := InitSttEngine()
        if (!engine.Begin()) {
            err := engine.GetLastError()
            this.ui.Update("TxtStatus", "Text", GetLang("开始录音失败：") (err != "" ? err : "未知错误"))
            return
        }
        this.recording := true
        this.recordStartTick := A_TickCount
        this.ui.Update("EdResult", "Text", "")
        this._RefreshUi()
    }

    OnStopClick(state := "", ctrl := "", event := "") {
        if (!this.recording)
            return
        this.recording := false
        engine := InitSttEngine()
        if (!engine.End()) {
            this._RefreshUi()
            return
        }
        this.decoding := true
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
    }

    ; ---------- 模型按需下载（curl + tar，异步 Run + 进程轮询） ----------
    OnDownloadClick(state := "", ctrl := "", event := "") {
        engine := InitSttEngine()
        if (this.downloadState != "" || engine.IsModelReady())
            return
        this.dlTar := A_Temp "\rmt-stt-model.tar.bz2"
        this.dlDir := A_Temp "\rmt-stt-model"
        ; 下载模型包（走 gh-proxy 加速，与 buildDll.ps1 一致）
        url := "https://gh-proxy.org/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2"
        cmd := Format('curl.exe -k --ssl-no-revoke -L --fail -s -S -o "{}" "{}"', this.dlTar, url)
        try {
            Run(cmd, A_Temp, "Hide", &pid)
            this.dlPid := pid
            this.downloadState := "dl"
            this._RefreshUi()
        } catch as e {
            this.downloadState := "err"
            this._RefreshUi()
        }
    }

    _StartExtract() {
        ; 校验下载产物大小（完整包约 80MB+）
        if (!FileExist(this.dlTar) || FileGetSize(this.dlTar) < 60 * 1024 * 1024)
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
        engine := InitSttEngine()
        src := this.dlDir "\sherpa-onnx-paraformer-zh-small-2024-03-09"
        if (FileExist(src "\model.int8.onnx") && FileExist(src "\tokens.txt")) {
            DirCreate(engine.ModelDir)
            FileCopy(src "\model.int8.onnx", engine.ModelDir "\model.int8.onnx", true)
            FileCopy(src "\tokens.txt", engine.ModelDir "\tokens.txt", true)
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
        engine := InitSttEngine()
        if (this.recording)
            engine.Cancel()
        ; 解码中则等下一轮轮询自然结束（结果丢弃）；释放模型回收内存
        if (!this.decoding)
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
