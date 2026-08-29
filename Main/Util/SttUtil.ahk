#Requires AutoHotkey v2.0

; =================================================================
; SttUtil — 语音转文字（STT）引擎封装
;
; 职责：
;   1. 复用 Plugins\Voice\VoiceDll.dll 的 Stt_* 导出
;      （sherpa-onnx OfflineRecognizer + paraformer 离线识别）
;   2. 模型位于 Plugins\Voice\models\stt\（model.int8.onnx + tokens.txt）
;   3. 生命周期：EnsureInit（加载模型）→ Begin（录音）→ End（异步解码）
;      → 轮询 GetState → GetResult 取全文
;   4. 与 KWS 语音触发（VoiceUtil.ahk）完全独立，互不干扰
; =================================================================

class SttEngine {
    __New() {
        this.hDll := 0
        this.loaded := false          ; 模型是否已在 DLL 内加载（Stt_Init 成功）
        this.lastError := ""
        ; 按 AHK 进程位宽选择运行时目录（与 SherpaVoiceEngine 一致）
        arch := (A_PtrSize == 8) ? "x64" : "x86"
        this.RunDir := A_WorkingDir "\Plugins\Voice\" arch
        this.DllPath := this.RunDir "\VoiceDll.dll"
        this.ModelDir := A_WorkingDir "\Plugins\Voice\models\stt"
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

    ; DLL 与模型齐备才可用
    IsReady() {
        return this.IsDllReady() && this.IsModelReady()
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
        this.loaded := false
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
