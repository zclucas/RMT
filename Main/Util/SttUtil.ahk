#Requires AutoHotkey v2.0

; =================================================================
; SttUtil — 语音转文字（STT）引擎封装
;
; 【当前方案：单模型流式】本地 CPU 推理，不联网
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
    __New() {
        this.hDll := 0
        this.loaded := false          ; 离线模型是否已在 DLL 内加载（Stt_Init 成功）
        this.streamLoaded := false    ; 流式模型是否已在 DLL 内加载（SttStream_Init 成功）
        this.lastError := ""
        ; 按 AHK 进程位宽选择运行时目录（与 SherpaVoiceEngine 一致）
        arch := (A_PtrSize == 8) ? "x64" : "x86"
        this.RunDir := A_WorkingDir "\Plugins\Voice\" arch
        this.DllPath := this.RunDir "\VoiceDll.dll"
        this.ModelDir := A_WorkingDir "\Plugins\Voice\models\stt"                ; [已停用] 离线 paraformer
        this.StreamModelDir := A_WorkingDir "\Plugins\Voice\models\stt_stream"   ; 流式（当前唯一链路）
        this._TryLoadDll()
    }

    ; 尝试加载 VoiceDll（先预加载依赖，避免依赖搜索错位；与 SherpaVoiceEngine 同法）
    _TryLoadDll() {
        if (!FileExist(this.DllPath))
            return false
        for dep in ["onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-c-api.dll"] {
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
    _StreamFiles() {
        dir := this.StreamModelDir
        tokens := dir "\tokens.txt"
        enc := this._FindFirst(dir "\encoder*.onnx")
        dec := this._FindFirst(dir "\decoder*.onnx")
        join := this._FindFirst(dir "\joiner*.onnx")
        if (enc != "" && dec != "" && join != "" && FileExist(tokens))
            return [enc, dec, join, tokens]
        model := this._FindFirst(dir "\model*.onnx")
        return [model, "", "", tokens]
    }

    IsStreamModelReady() {
        f := this._StreamFiles()
        return (f[1] != "" && FileExist(f[4]))
    }

    ; DLL 与模型齐备才可用
    IsReady() {
        return this.IsDllReady() && this.IsModelReady()
    }

    ; 流式主链路是否可用
    IsStreamReady() {
        return this.IsDllReady() && this.IsStreamModelReady()
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
        r := DllCall(this.DllPath "\Stt_Init", "WStr", model, "WStr", tokens, "Int")
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
        r := DllCall(this.DllPath "\Stt_GetResult", "Ptr", buf, "Int", 16384, "Int")
        if (!r)
            return ""
        return StrGet(buf, 16384, "UTF-8")
    }

    GetLastError() {
        if (!this.IsDllReady())
            return this.lastError
        buf := Buffer(512)
        DllCall(this.DllPath "\Stt_GetLastError", "Ptr", buf, "Int", 512, "Int")
        return StrGet(buf, 512, "UTF-8")
    }

    ; 释放模型（窗口关闭时调用，及时回收 ~80MB 内存）
    Close() {
        if (!this.IsDllReady())
            return
        DllCall(this.DllPath "\Stt_Close")
        DllCall(this.DllPath "\SttStream_Close")
        this.loaded := false
        this.streamLoaded := false
    }

    ; ---------- 流式识别（本地 OnlineRecognizer + zipformer2 CTC） ----------
    ; 确保流式模型已加载（首次调用真正执行 SttStream_Init）
    StreamEnsureInit() {
        if (this.streamLoaded)
            return true
        if (!this.IsStreamReady())
            return false
        f := this._StreamFiles()
        if (f[1] == "")
            return false
        r := DllCall(this.DllPath "\SttStream_Init", "WStr", f[1], "WStr", f[2], "WStr", f[3], "WStr", f[4], "Int")
        if (r) {
            this.streamLoaded := true
            this.lastError := ""
        } else {
            this.streamLoaded := false
            this.lastError := this.StreamGetLastError()
        }
        return this.streamLoaded
    }

    ; 建流 + 起采集
    StreamBegin() {
        if (!this.StreamEnsureInit())
            return false
        r := DllCall(this.DllPath "\SttStream_Begin", "Int")
        if (!r)
            this.lastError := this.StreamGetLastError()
        return r != 0
    }

    ; 喂音频 + 增量解码 + 取当前累积文本（录音中每 ~150ms 调一次）
    StreamPoll() {
        if (!this.IsDllReady())
            return ""
        buf := Buffer(16384)
        r := DllCall(this.DllPath "\SttStream_Poll", "Ptr", buf, "Int", 16384, "Int")
        if (!r)
            return ""
        return StrGet(buf, 16384, "UTF-8")
    }

    ; 停止并收尾；refine=1 时再交给离线 paraformer 精修（异步）
    StreamEnd(refine := 1) {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\SttStream_End", "Int", refine ? 1 : 0, "Int") != 0
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
        r := DllCall(this.DllPath "\SttStream_GetResult", "Ptr", buf, "Int", 16384, "Int")
        if (!r)
            return ""
        return StrGet(buf, 16384, "UTF-8")
    }

    StreamGetLastError() {
        if (!this.IsDllReady())
            return this.lastError
        buf := Buffer(512)
        DllCall(this.DllPath "\SttStream_GetLastError", "Ptr", buf, "Int", 512, "Int")
        return StrGet(buf, 512, "UTF-8")
    }

    ; 离线验证：分片喂 wav 模拟实时上屏（不依赖麦克风）
    StreamTestWav(wavPath) {
        if (!this.StreamEnsureInit())
            return ""
        buf := Buffer(4096)
        r := DllCall(this.DllPath "\SttStream_TestWav", "WStr", wavPath, "Ptr", buf, "Int", 4096, "Int")
        if (!r)
            return ""
        return StrGet(buf, 4096, "UTF-8")
    }

    ; 离线测试：转写一个 wav 文件（自动化验证用）
    TestWav(wavPath) {
        if (!this.EnsureInit())
            return ""
        buf := Buffer(4096)
        r := DllCall(this.DllPath "\Stt_TestWav", "WStr", wavPath, "Ptr", buf, "Int", 4096, "Int")
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
