#Requires AutoHotkey v2.0
#Include ..\Shared\OfficialLanguages.ahk

; =================================================================
; SttUtil — 语音转文字（STT）引擎封装
;
; 【当前方案：单模型流式】按语言加载一个模型，本地 CPU 推理
;   链路：SttStream_* → sherpa-onnx OnlineRecognizer
;   模型：models\stt_stream\ —— x-asr streaming zipformer2 transducer
;         （encoder/decoder/joiner + tokens.txt + bpe.model，中英混排带标点）
;         chunk 档位 160/480/960/1920ms，见 SttGui.StreamPkg（默认 480ms）
;   生命周期：StreamEnsureInit → StreamBegin → 每 ~100ms StreamPoll（取当前文本）
;            → StreamEnd(0) → 轮询 StreamGetState（3完成/4错误）→ StreamGetResult
;
; 【已停用：离线 two-pass】Stt_*（OfflineRecognizer + paraformer，models\stt\）
;   下方 EnsureInit/Begin/End/... 与 ModelDir 保留但**无调用者**，
;   DLL 侧 Stt_* 导出仍在，若日后要恢复精修只需重新接上 UI。
; 与 KWS 语音触发（VoiceUtil.ahk）完全独立，互不干扰。
; =================================================================

class SttEngine {
    static LanguageModels := Map(
        "zh-en", {label: "中英混合", flag: ""},
        "zh-TW", {label: "繁體中文", flag: "tw"},
        "es", {label: "Español", flag: "es"},
        "fr", {label: "Français", flag: "fr"},
        "de", {label: "Deutsch", flag: "de"},
        "it", {label: "Italiano", flag: "it"})

    static ModelLanguage(language) => language == "zh-TW" ? "zh-en" : language

    static DefaultLanguage() {
        global MainSoftData
        lang := ""
        try lang := MainSoftData.Lang
        languages := OfficialLanguages()
        code := languages.Has(lang) ? languages[lang].code : ""
        return SttEngine.LanguageModels.Has(code) ? code : "zh-en"
    }

    __New() {
        this.hDll := 0
        this.loaded := false          ; 离线模型是否已在 DLL 内加载（Stt_Init 成功）
        this.streamLoaded := false    ; 流式模型是否已在 DLL 内加载（SttStream_Init 成功）
        this.streamLanguage := ""
        this._streamStart := ""
        this.lastError := ""
        ; 按 AHK 进程位宽选择运行时目录（与 SherpaVoiceEngine 一致）
        arch := (A_PtrSize == 8) ? "x64" : "x86"
        this.RunDir := A_WorkingDir "\Plugins\Voice\" arch
        this.DllPath := this.RunDir "\VoiceDll.dll"
        this.ModelDir := A_WorkingDir "\Plugins\Voice\models\stt"                ; [已停用] 离线 paraformer
        this.StreamModelDir := A_WorkingDir "\Plugins\Voice\models\stt_stream"
        this._TryLoadDll()
    }

    ; 尝试加载 VoiceDll（先预加载依赖，避免依赖搜索错位；与 SherpaVoiceEngine 同法）
    _TryLoadDll() {
        if (this.hDll != 0)
            return true
        if (!FileExist(this.DllPath))
            return false
        ; Win10 常未安装带 VCRUNTIME140_1 的 VC++ 运行库。运行库不在旁边时，
        ; onnxruntime 加载失败，语音按钮只会弹出「语音引擎未就绪」，到不了模型下载。
        for dep in ["vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-c-api.dll"] {
            dp := this.RunDir "\" dep
            if (FileExist(dp)) {
                try
                    DllCall("LoadLibrary", "Str", dp, "Ptr")
            }
        }
        try {
            this.hDll := DllCall("LoadLibrary", "Str", this.DllPath, "Ptr")
            if (this.hDll != 0)
                return true
        } catch as e {
            this.lastError := "DLL加载失败: " (e.HasProp("Message") ? e.Message : "")
        }
        this.hDll := 0
        return false
    }

    IsDllReady() {
        return (this.hDll != 0)
    }

    IsModelReady() {
        return FileExist(this.ModelDir "\model.int8.onnx")
            && FileExist(this.ModelDir "\tokens.txt")
    }

    ; 流式模型两种形态：
    ;   transducer 三件套（encoder/decoder/joiner + tokens，如 x-asr zipformer2）
    ;   zipformer2 CTC 单模型（model*.onnx + tokens）
    ; 返回 [encoder, decoder, joiner, tokens]；CTC 形态时 decoder/joiner 为 ""
    StreamDirectory(language) {
        language := SttEngine.ModelLanguage(language)
        return language == "zh-en" ? this.StreamModelDir : this.StreamModelDir "\" language
    }

    _StreamFiles(language) {
        language := SttEngine.ModelLanguage(language)
        dir := this.StreamDirectory(language)
        tokens := dir "\tokens.txt"
        if (language != "zh-en")
            return [dir "\encoder.onnx", dir "\decoder.onnx", dir "\joiner.onnx", tokens]
        enc := this._FindFirst(dir "\encoder*.onnx")
        dec := this._FindFirst(dir "\decoder*.onnx")
        join := this._FindFirst(dir "\joiner*.onnx")
        if (enc != "" && dec != "" && join != "" && FileExist(tokens))
            return [enc, dec, join, tokens]
        model := this._FindFirst(dir "\model*.onnx")
        return [model, "", "", tokens]
    }

    IsStreamModelReady(language := "zh-en") {
        files := this._StreamFiles(language)
        if (files[1] == "")
            return false
        ; 与 DLL 的选择顺序一致。部分模型不使用 BPE，词表存在时才检查。
        for name in ["bpe.model", "bbpe.model"] {
            path := this.StreamDirectory(language) "\" name
            if (FileExist(path)) {
                files.Push(path)
                break
            }
        }
        try {
            for path in files {
                if (path != "" && FileOpen(path, "r").Length == 0)
                    return false
            }
        } catch {
            return false
        }
        return true
    }

    ; DLL 与模型齐备才可用
    IsReady() {
        return this.IsDllReady() && this.IsModelReady()
    }

    ; 流式主链路是否可用
    IsStreamReady(language := "zh-en") {
        return this.IsDllReady() && this.IsStreamModelReady(language)
    }

    ; 确保模型已加载（首次调用真正执行 Stt_Init，之后直接返回）
    EnsureInit() {
        if (this.loaded)
            return true
        if (!this.IsReady())
            return false
        model := this._FindFirst(this.ModelDir "\model*.onnx")
        tokens := this.ModelDir "\tokens.txt"
        if (model == "")
            return false
        r := DllCall(this.DllPath "\Stt_Init", "WStr", model, "WStr", tokens, "CDecl Int")
        if (r) {
            this.loaded := true
            this.lastError := ""
        } else {
            this.loaded := false
            this.lastError := this.GetLastError()
        }
        return this.loaded
    }

    ; ---------- 录音/解码生命周期 ----------
    ; 开始录音。返回 1 成功；0 失败（GetLastError 取原因）
    Begin() {
        if (!this.EnsureInit())
            return false
        r := DllCall(this.DllPath "\Stt_Begin", "Int")
        if (!r)
            this.lastError := this.GetLastError()
        return r != 0
    }

    ; 停止录音并异步开始解码（立即返回，轮询 GetState）
    End() {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\Stt_End", "Int") != 0
    }

    ; 停止录音并丢弃（不解码）
    Cancel() {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\Stt_Cancel", "Int") != 0
    }

    ; 0空闲 1录音中 2解码中 3完成 4错误
    GetState() {
        if (!this.IsDllReady())
            return 0
        return DllCall(this.DllPath "\Stt_GetState", "Int")
    }

    ; 解码完成后取识别全文（UTF-8 转宽字符）
    GetResult() {
        if (!this.IsDllReady())
            return ""
        buf := Buffer(16384)
        r := DllCall(this.DllPath "\Stt_GetResult", "Ptr", buf, "Int", 16384, "CDecl Int")
        if (!r)
            return ""
        return StrGet(buf, 16384, "UTF-8")
    }

    GetLastError() {
        if (!this.IsDllReady())
            return this.lastError
        buf := Buffer(512)
        DllCall(this.DllPath "\Stt_GetLastError", "Ptr", buf, "Int", 512, "CDecl Int")
        return StrGet(buf, 512, "UTF-8")
    }

    ; 释放模型（窗口关闭时调用，及时回收 ~80MB 内存）
    Close() {
        if (!this.IsDllReady() || IsObject(this._streamStart))
            return
        DllCall(this.DllPath "\Stt_Close")
        DllCall(this.DllPath "\SttStream_Close")
        this.loaded := false
        this.streamLoaded := false
        this.streamLanguage := ""
    }

    ; ---------- 流式识别（本地 OnlineRecognizer + zipformer2 CTC） ----------
    ; 确保流式模型已加载（首次调用真正执行 SttStream_Init）
    StreamEnsureInit(language := "zh-en") {
        wasCritical := A_IsCritical
        Critical("On")
        try return this._EnsureStreamModel(language)
        finally Critical(wasCritical)
    }

    _EnsureStreamModel(language) {
        if (this.streamLoaded && this.streamLanguage == language)
            return true
        if (!this.IsStreamReady(language) || this.StreamBusy())
            return false
        if (this.streamLoaded && SttEngine.ModelLanguage(this.streamLanguage) == SttEngine.ModelLanguage(language)) {
            this.streamLanguage := language
            return true
        }
        f := this._StreamFiles(language)
        if (f[1] == "")
            return false
        ; VoiceDll 导出使用 CDecl，32 位调用需要显式指定。
        r := DllCall(this.DllPath "\SttStream_Init", "WStr", f[1], "WStr", f[2], "WStr", f[3], "WStr", f[4], "CDecl Int")
        if (r) {
            this.streamLoaded := true
            this.streamLanguage := language
            this.lastError := ""
        } else {
            this.streamLoaded := false
            this.streamLanguage := ""
            this.lastError := this.StreamGetLastError()
        }
        return this.streamLoaded
    }

    ; 建流 + 起采集
    StreamBegin(language := "zh-en") {
        wasCritical := A_IsCritical
        Critical("On")
        try return this._BeginStream(language)
        finally Critical(wasCritical)
    }

    _BeginStream(language) {
        if (this.StreamBusy()) {
            this.lastError := GetLang("已有语音录入正在进行")
            return false
        }
        this.lastError := ""
        if (!this.StreamEnsureInit(language)) {
            if (this.lastError == "")
                this.lastError := GetLang("识别模型未就绪，请先下载模型")
            return false
        }
        r := DllCall(this.DllPath "\SttStream_Begin", "Int")
        this.lastError := r ? "" : this.StreamGetLastError()
        return r != 0
    }

    ; 输入弹窗异步建流。旧语音扩展仍可通过同步接口录音。
    StreamStartAsync(language, onDone) {
        if (this.StreamBusy()) {
            onDone.Call(false, GetLang("已有语音录入正在进行"))
            return
        }
        if (!DllCall("GetProcAddress", "Ptr", this.hDll, "AStr", "SttStream_StartAsync", "Ptr")) {
            ok := this.StreamBegin(language)
            onDone.Call(ok, this.lastError)
            return
        }
        loadModel := !this.streamLoaded || SttEngine.ModelLanguage(this.streamLanguage) != SttEngine.ModelLanguage(language)
        files := loadModel ? this._StreamFiles(language) : ["", "", "", ""]
        if (loadModel && files[1] == "") {
            onDone.Call(false, GetLang("识别模型未就绪，请先下载模型"))
            return
        }
        request := {language: language, loadModel: loadModel, onDone: onDone, cancelled: false}
        this._streamStart := request
        try {
            if (DllCall(this.DllPath "\SttStream_StartAsync", "WStr", files[1], "WStr", files[2]
                , "WStr", files[3], "WStr", files[4], "CDecl Int")) {
                request.poll := ObjBindMethod(this, "_PollStreamStart")
                SetTimer(request.poll, 30)
                return
            }
        } catch {
        }
        this._streamStart := ""
        onDone.Call(false, "")
    }

    StreamCancelStart() {
        if (!IsObject(this._streamStart))
            return
        this._streamStart.cancelled := true
        DllCall(this.DllPath "\SttStream_CancelStart", "CDecl")
    }

    _PollStreamStart() {
        Critical("On")
        request := this._streamStart
        status := DllCall(this.DllPath "\SttStream_GetStartStatus", "CDecl Int")
        if (status == 0)
            return
        SetTimer(request.poll, 0)
        ; 失败或取消时保守地让下次重载，避免沿用已被替换的模型。
        if (request.loadModel) {
            this.streamLoaded := status == 1
            this.streamLanguage := this.streamLoaded ? request.language : ""
        }
        if (status == 1)
            this.streamLanguage := request.language
        if (request.cancelled && status == 1)
            this.StreamCancel()
        errorText := status == -1 ? this.StreamGetLastError() : ""
        this._streamStart := ""
        if (!request.cancelled)
            request.onDone.Call(status == 1, errorText)
    }

    StreamBusy() {
        if (IsObject(this._streamStart))
            return true
        state := this.StreamGetState()
        return state == 1 || state == 2
    }

    ; 喂音频 + 增量解码 + 取当前累积文本（录音中每 ~150ms 调一次）
    StreamPoll() {
        if (!this.IsDllReady())
            return ""
        buf := Buffer(16384)
        r := DllCall(this.DllPath "\SttStream_Poll", "Ptr", buf, "Int", 16384, "CDecl Int")
        if (!r)
            return ""
        return this._StreamOutput(StrGet(buf, 16384, "UTF-8"))
    }

    ; 停止并收尾；refine=1 时再交给离线 paraformer 精修（异步）
    StreamEnd(refine := 1) {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\SttStream_End", "Int", refine ? 1 : 0, "CDecl Int") != 0
    }

    ; 停止并丢弃
    StreamCancel() {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\SttStream_Cancel", "Int") != 0
    }

    ; 0空闲 1录音中 2精修中 3完成 4错误
    StreamGetState() {
        if (!this.IsDllReady())
            return 0
        return DllCall(this.DllPath "\SttStream_GetState", "Int")
    }

    StreamGetResult() {
        if (!this.IsDllReady())
            return ""
        buf := Buffer(16384)
        r := DllCall(this.DllPath "\SttStream_GetResult", "Ptr", buf, "Int", 16384, "CDecl Int")
        if (!r)
            return ""
        return this._StreamOutput(StrGet(buf, 16384, "UTF-8"))
    }

    _StreamOutput(text) {
        if (text == "" || this.streamLanguage != "zh-TW")
            return text
        ; LCMAP_TRADITIONAL_CHINESE
        size := DllCall("Kernel32\LCMapStringEx", "WStr", "zh-TW", "UInt", 0x04000000
            , "WStr", text, "Int", -1, "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Int")
        if (!size)
            return text
        output := Buffer(size * 2)
        written := DllCall("Kernel32\LCMapStringEx", "WStr", "zh-TW", "UInt", 0x04000000
            , "WStr", text, "Int", -1, "Ptr", output, "Int", size, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Int")
        return written ? StrGet(output, "UTF-16") : text
    }

    StreamGetLastError() {
        if (!this.IsDllReady())
            return this.lastError
        buf := Buffer(512)
        DllCall(this.DllPath "\SttStream_GetLastError", "Ptr", buf, "Int", 512, "CDecl Int")
        return StrGet(buf, 512, "UTF-8")
    }

    ; 离线验证：分片喂 wav 模拟实时上屏（不依赖麦克风）
    StreamTestWav(wavPath, language := "zh-en") {
        if (!this.StreamEnsureInit(language))
            return ""
        buf := Buffer(4096)
        r := DllCall(this.DllPath "\SttStream_TestWav", "WStr", wavPath, "Ptr", buf, "Int", 4096, "CDecl Int")
        if (!r)
            return ""
        return this._StreamOutput(StrGet(buf, 4096, "UTF-8"))
    }

    ; 离线测试：转写一个 wav 文件（自动化验证用）
    TestWav(wavPath) {
        if (!this.EnsureInit())
            return ""
        buf := Buffer(4096)
        r := DllCall(this.DllPath "\Stt_TestWav", "WStr", wavPath, "Ptr", buf, "Int", 4096, "CDecl Int")
        if (!r)
            return ""
        return StrGet(buf, 4096, "UTF-8")
    }

    ; 错误消息兜底（空错误串 → 未知错误）
    _ErrText(err) {
        return (err != "") ? err : "未知错误"
    }

    ; 返回目录下第一个匹配 glob 的完整路径；无则 ""
    _FindFirst(p) {
        loop files, p {
            return A_LoopFileFullPath
        }
        return ""
    }
}

; ---------- 全局单例 ----------
global MySttEngine := ""
InitSttEngine() {
    global MySttEngine
    if (!IsSet(MySttEngine) || !IsObject(MySttEngine))
        MySttEngine := SttEngine()
    return MySttEngine
}
