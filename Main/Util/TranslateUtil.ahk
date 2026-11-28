#Requires AutoHotkey v2.0

; =================================================================
; TranslateUtil — 本地翻译：DLL 宿主层
;
; 契约以 Plugins\Translate\src\TranslateDll.h 为准，本类只是它的宿主。
;   推理在进程内做（llama.cpp 以共享库形式与 TranslateDll.dll 同目录），不起外部服务、不联网。
;   DLL 是全局单例：一个进程一份模型，指令连续调用复用，只有换模型或换 CPU/GPU 才重新 Load。
;
; 与 AI 通道（AiAssist / AiDecision）的分工：
;   AiAssist 走 HTTP，把文本送到别处算；本类不联网，模型文件就在 models\ 下。
;   翻译指令把两者都当成「引擎」选项，Host 只认 TranslateEngine 的接口。
;
; 所有 DllCall 必须显式写 CDecl —— 32 位下 AHK 默认按 stdcall 调，漏了会弹坏栈。
; =================================================================

class TranslateEngine {
    ; 与 TranslateDll.h 的 TRANSLATE_API_VERSION 对应
    static ContractVersion := 3
    ; 默认模型文件名（Plugins\Translate\models 下）
    static DefaultModel := "Index-Translate-2B.Q4_K_M.gguf"
    ; 输出缓冲（wchar_t 计）。译文按字符截断，8192 字足够一屏文案；超出会在 stats 里标 truncated
    static OutChars := 8192

    static _shared := ""

    ; 全局单例：模型加载要 1~2 秒，指令里每条都 new 一次是不可接受的
    static Shared() {
        if (TranslateEngine._shared == "")
            TranslateEngine._shared := TranslateEngine()
        return TranslateEngine._shared
    }

    ; ProjectRootDir 在启动链里赋值，不是超全局变量，函数内必须显式声明，
    ; 否则 AHK 会报「局部变量从未赋值」。
    static PluginDir() {
        global ProjectRootDir
        return ProjectRootDir "\Plugins\Translate"
    }

    static ArchDir() {
        return TranslateEngine.PluginDir() "\" (A_PtrSize == 8 ? "x64" : "x86")
    }

    static ModelDir() {
        return TranslateEngine.PluginDir() "\models"
    }

    ; DLL 是否随包存在（不代表能加载成功）
    static Available() => FileExist(TranslateEngine.ArchDir() "\TranslateDll.dll") != ""

    ; 模型是否已下载
    static HasModel(name := "") {
        name := (name == "" ? TranslateEngine.DefaultModel : name)
        path := TranslateEngine.ModelDir() "\" name
        if (!FileExist(path))
            return false
        minBytes := InStr(name, "-9B") ? 5000 * 1024 * 1024 : 1200 * 1024 * 1024
        try return FileGetSize(path) >= minBytes
        return false
    }

    __New() {
        this.hDll := 0
        this.loaded := false
        this.modelPath := ""
        this.gpuLayers := ""    ; 已加载模型用的卸载层数（"" = 未加载），换设备要重新 Load
        this._lastError := ""
        this.dllPath := TranslateEngine.ArchDir() "\TranslateDll.dll"
        this._opt := 0          ; Load 用的参数缓冲，复用
        this._stats := 0        ; Stats 缓冲
        this._out := 0          ; 译文缓冲
        this._TryLoadDll()
    }

    ; 依赖按 DLL 所在目录解析（0x8 = LOAD_WITH_ALTERED_SEARCH_PATH）。
    ; llama.dll / ggml*.dll 与 TranslateDll.dll 同目录，是硬导入——必须先这样加载，
    ; 裸 DllCall 会去 exe 目录找，找不到就整个加载失败。
    ; CPU 变体后端与 ggml-vulkan.dll 反过来由 DLL 自己按所在目录运行时加载。
    _TryLoadDll() {
        if (this.hDll != 0)
            return true
        if (!FileExist(this.dllPath))
            return false
        try {
            this.hDll := DllCall("LoadLibraryExW", "Str", this.dllPath, "Ptr", 0, "UInt", 0x8, "Ptr")
            if (this.hDll != 0)
                return true
        } catch as e {
            this._lastError := "DLL 加载失败: " (e.HasProp("Message") ? e.Message : "")
        }
        this.hDll := 0
        return false
    }

    IsDllReady() => this.hDll != 0

    ; 本机是否有可用的 GPU 后端（Vulkan）。不需要先 Load 模型——DLL 内部会按自身目录
    ; 加载后端后枚举设备；组件缺失或无效时报告不可用。
    HasGpu() {
        if (!this.IsDllReady() && !this._TryLoadDll())
            return false
        try
            return DllCall(this.dllPath "\Translate_HasGpu", "CDecl Int") = 1
        catch
            return false
    }

    ; DLL 的 ABI 版本；组件缺失或无效时返回 -1
    ApiVersion() {
        if (!this.IsDllReady())
            return -1
        try
            return DllCall(this.dllPath "\Translate_ApiVersion", "CDecl Int")
        catch
            return -1
    }

    BackendVersion() {
        if (!this.IsDllReady())
            return ""
        buf := Buffer(128, 0)
        try DllCall(this.dllPath "\Translate_BackendVersion", "Ptr", buf, "Int", 128, "CDecl Int")
        catch
            return ""
        return StrGet(buf, "CP0")
    }

    ; 最近一次失败原因（UTF-8 → AHK 字符串）
    LastError() {
        if (!this.IsDllReady())
            return this._lastError
        buf := Buffer(1024, 0)
        try DllCall(this.dllPath "\Translate_LastError", "Ptr", buf, "Int", 1024, "CDecl Int")
        catch
            return this._lastError
        return StrGet(buf, "UTF-8")
    }

    IsLoaded() {
        if (!this.IsDllReady())
            return false
        try
            return DllCall(this.dllPath "\Translate_IsLoaded", "CDecl Int") = 1
        catch
            return false
    }

    ; 加载模型。opt 可省：
    ;   nCtx（默认 2048）nThreads（0=自动）maxTokens（默认 512）
    ; 返回 "" 表示成功，否则是错误文本。
    Load(modelName := "", opt := "") {
        ; 2B 模型的常驻内存放不进 32 位地址空间，32 位宿主没有这个插件，别报成「组件缺失」
        if (A_PtrSize == 4)
            return GetLang("翻译组件仅支持 64 位")
        if (!this.IsDllReady() && !this._TryLoadDll())
            return GetLang("翻译组件缺失，请先编译 Plugins\Translate")
        if (this.ApiVersion() != TranslateEngine.ContractVersion)
            return GetLang("翻译组件版本不匹配，请重新编译")

        modelName := (modelName == "" ? TranslateEngine.DefaultModel : modelName)
        path := (InStr(modelName, "\") ? modelName : TranslateEngine.ModelDir() "\" modelName)
        if (!FileExist(path))
            return GetLang("翻译模型未下载") ": " modelName

        if (!IsObject(opt))
            opt := Map()
        if (this._opt == 0)
            this._opt := Buffer(24, 0)
        NumPut("Int", 24, this._opt, 0)
        NumPut("Int", opt.Has("nCtx") ? Integer(opt["nCtx"]) : 2048, this._opt, 4)
        NumPut("Int", opt.Has("nThreads") ? Integer(opt["nThreads"]) : 0, this._opt, 8)
        NumPut("Int", opt.Has("maxTokens") ? Integer(opt["maxTokens"]) : 512, this._opt, 12)
        NumPut("Int", opt.Has("nBatch") ? Integer(opt["nBatch"]) : 512, this._opt, 16)
        ; nGpuLayers 偏移 20：-1 = 自动（有 Vulkan GPU 全卸载，没有落 CPU）；0 = 仅 CPU。
        layers := opt.Has("nGpuLayers") ? Integer(opt["nGpuLayers"]) : -1
        NumPut("Int", layers, this._opt, 20)

        ok := 0
        try
            ok := DllCall(this.dllPath "\Translate_Load", "WStr", path, "Ptr", this._opt, "CDecl Int")
        catch as e {
            this._lastError := "Load 调用失败: " (e.HasProp("Message") ? e.Message : "")
            return this._lastError
        }
        if (!ok)
            return this.LastError()
        this.loaded := true
        this.modelPath := path
        this.gpuLayers := layers
        return ""
    }

    Unload() {
        if (!this.IsDllReady())
            return
        try DllCall(this.dllPath "\Translate_Unload", "CDecl")
        this.loaded := false
        this.modelPath := ""
        this.gpuLayers := ""
    }

    ; 翻译一条。返回 Map：
    ;   ok      1 成功 / 0 失败
    ;   text    译文（ok=1）
    ;   error   错误文本（ok=0）
    ;   promptTokens / outputTokens / elapsedMs / truncated
    Translate(text, target, glossaryItems := [], timeoutMs := 30000) {
        if (!this.IsLoaded()) {
            err := this.Load()
            if (err != "")
                return Map("ok", 0, "text", "", "error", err)
        }
        if (this._out == 0)
            this._out := Buffer(TranslateEngine.OutChars * 2, 0)
        if (this._stats == 0)
            this._stats := Buffer(16, 0)
        NumPut("Int", 0, this._out, 0)
        NumPut("Int", 0, this._stats, 0)

        itemBuffer := 0
        itemBuffers := []
        if (IsObject(glossaryItems) && glossaryItems.Length) {
            itemBuffer := Buffer(glossaryItems.Length * A_PtrSize * 2, 0)
            for index, item in glossaryItems {
                source := String(item.source)
                targetText := String(item.target)
                sourceBuffer := Buffer(StrPut(source, "UTF-16") * 2, 0)
                targetBuffer := Buffer(StrPut(targetText, "UTF-16") * 2, 0)
                StrPut(source, sourceBuffer, "UTF-16")
                StrPut(targetText, targetBuffer, "UTF-16")
                offset := (index - 1) * A_PtrSize * 2
                NumPut("Ptr", sourceBuffer.Ptr, itemBuffer, offset)
                NumPut("Ptr", targetBuffer.Ptr, itemBuffer, offset + A_PtrSize)
                itemBuffers.Push(sourceBuffer, targetBuffer)
            }
        }

        r := 0
        try
            r := DllCall(this.dllPath "\Translate_Run", "WStr", text, "WStr", target,
                "Ptr", itemBuffer, "Int", IsObject(glossaryItems) ? glossaryItems.Length : 0, "Int", Integer(timeoutMs),
                "Ptr", this._out, "Int", TranslateEngine.OutChars, "Ptr", this._stats, "CDecl Int")
        catch as e {
            return Map("ok", 0, "text", "", "error", "Run 调用失败: " (e.HasProp("Message") ? e.Message : ""))
        }
        if (r != 1) {
            err := (r == -1) ? GetLang("翻译已取消") : this.LastError()
            return Map("ok", 0, "text", "", "error", err, "cancelled", (r == -1))
        }
        return Map(
            "ok", 1,
            "text", StrGet(this._out, "UTF-16"),
            "error", "",
            "promptTokens", NumGet(this._stats, 0, "Int"),
            "outputTokens", NumGet(this._stats, 4, "Int"),
            "elapsedMs", NumGet(this._stats, 8, "Int"),
            "truncated", NumGet(this._stats, 12, "Int"))
    }

    ; 中断正在跑的翻译。AHK 是单线程，同步 DllCall 期间调不到这里；
    ; 留给伪线程/Worker 场景，或以后改成异步推理时用。
    Cancel() {
        if (!this.IsDllReady())
            return
        try DllCall(this.dllPath "\Translate_Cancel", "CDecl")
    }
}
