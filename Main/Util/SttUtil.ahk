#Requires AutoHotkey v2.0
#Include ..\Shared\OfficialLanguages.ahk

; =================================================================
; SttUtil — 语音转文字（STT）：DLL 宿主 + 会话编排
;
; 本文件两层，职责不混：
;   class SttEngine    DLL 宿主层。LoadLibrary、模型文件探测、全部 DllCall 都在这。
;                      契约以 Plugins\Voice\src\VoiceDll.h 为准，本类只是它的宿主。
;   class VoiceInput   会话编排层。什么时候开录、按节拍取文本、说完怎么收尾。
;                      不持有窗口、不碰控件、不弹提示；一个 DllCall 都没有，全经 SttEngine。
;
; 【当前方案：流式，本地 CPU 推理，不联网】
;   链路：SttStream_* → sherpa-onnx OnlineRecognizer
;   模型：models\stt_stream\            —— 中英混合（x-asr streaming zipformer2 transducer）
;         models\stt_stream\<语言>\     —— 其他语言（es / fr / de，固定 encoder/decoder/joiner）
;         chunk 档位 160/480/960/1920ms，见 SttGui.StreamPkg（默认 480ms）
;   语言：SttEngine.LanguageModels + DefaultLanguage()，跟着界面语言走；
;         同一时刻 DLL 内只有一份模型，切语言会重新 Init（1~3 秒，只在换语言时发生一次）
;   生命周期：StreamEnsureInit → StreamBegin → 每 40ms StreamPoll（取当前文本）
;            → StreamEnd(0)（返回即落定，内部已等完尾音并做完收尾解码）→ StreamGetResult
;   所有 DllCall 必须显式写 CDecl —— 32 位下 AHK 默认按 stdcall 调，漏了会弹坏栈。
;
; 【已移除：离线 two-pass】原先 AHK 侧的 Stt_* 封装与 ModelDir 已删除——项目里零调用者。
;   DLL 侧 Stt_* 导出仍在，日后要恢复精修按 VoiceDll.h 重新加一层即可。
; 与 KWS 语音触发（VoiceUtil.ahk）完全独立，互不干扰。
; =================================================================

class SttEngine {
    ; 支持的语音语言。code 是模型目录名（zh-en 直接用 models\stt_stream 根目录），
    ; label/flag 供下载界面显示；新增语言只需在这里加一项 + 放好模型目录。
    static LanguageModels := Map(
        "zh-en", {label: "中英混合", flag: ""},
        "zh-TW", {label: "繁體中文", flag: "tw"},
        "es", {label: "Español", flag: "es"},
        "fr", {label: "Français", flag: "fr"},
        "de", {label: "Deutsch", flag: "de"},
        "it", {label: "Italiano", flag: "it"})

    static ModelLanguage(language) => language == "zh-TW" ? "zh-en" : language

    ; 界面语言 → 语音语言。没装对应模型的语言回落到中英混合。
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
        this.streamLoaded := false    ; 流式模型是否已在 DLL 内加载（SttStream_Init 成功）
        this.streamLanguage := ""     ; 已加载的是哪种语言（DLL 内只有一份模型）
        this.asyncLanguage := ""      ; 后台加载（InitAsync）申请的语言，用于确认加载完的是不是它
        this.lastError := ""
        ; 按 AHK 进程位宽选择运行时目录（与 SherpaVoiceEngine 一致）
        arch := (A_PtrSize == 8) ? "x64" : "x86"
        this.RunDir := A_WorkingDir "\Plugins\Voice\" arch
        this.DllPath := this.RunDir "\VoiceDll.dll"
        this.StreamModelDir := A_WorkingDir "\Plugins\Voice\models\stt_stream"   ; 流式（当前唯一链路）
        this._pollBuf := 0            ; StreamPoll 复用的接收缓冲（每 40ms 一次，别反复分配 16KB）
        this._TryLoadDll()
    }

    ; 尝试加载 VoiceDll。
    ; 用 LOAD_WITH_ALTERED_SEARCH_PATH(0x8)：依赖先按 VoiceDll 所在目录解析，
    ; 同目录的 onnxruntime / sherpa 自动找到；
    ; 同目录没有的 VC++ 运行库会继续按标准路径落到系统目录，不依赖随包副本。
    ; 所以不需要手工维护依赖清单——那玩意儿会漏，也管不了以后新加的依赖。
    _TryLoadDll() {
        if (this.hDll != 0)
            return true
        if (!FileExist(this.DllPath))
            return false
        try {
            this.hDll := DllCall("LoadLibraryExW", "Str", this.DllPath, "Ptr", 0, "UInt", 0x8, "Ptr")
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

    ; DLL 的 ABI 版本（见 Plugins\Voice\src\VoiceDll.h 的 VOICE_API_VERSION）。
    ; 更旧的 DLL 没有这个导出，返回 -1；宿主可用它确认语音组件与代码是一次编译出来的。
    ApiVersion() {
        if (!this.IsDllReady())
            return -1
        try
            return DllCall(this.DllPath "\Voice_ApiVersion", "CDecl Int")
        catch
            return -1
    }

    ; 某语言的模型目录：中英混合在根目录，其余语言各占一个子目录。
    ; 繁體中文复用中英混合模型（结果由 _StreamOutput 转繁），所以先过 ModelLanguage。
    StreamDirectory(language := "zh-en") {
        language := SttEngine.ModelLanguage(language)
        return language == "zh-en" ? this.StreamModelDir : this.StreamModelDir "\" language
    }

    ; 流式模型两种形态：
    ;   transducer 三件套（encoder/decoder/joiner + tokens，如 x-asr zipformer2）
    ;   zipformer2 CTC 单模型（model*.onnx + tokens）
    ; 返回 [encoder, decoder, joiner, tokens]；CTC 形态时 decoder/joiner 为 ""
    ; 非中英混合的语言包文件名固定，不走 glob（避免同目录里的旧文件被误选）。
    _StreamFiles(language := "zh-en") {
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
        dir := this.StreamDirectory(language)
        for name in ["bpe.model", "bbpe.model"] {
            path := dir "\" name
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

    ; 流式主链路是否可用
    IsStreamReady(language := "zh-en") {
        return this.IsDllReady() && this.IsStreamModelReady(language)
    }

    ; 释放流式模型（窗口关闭时调用，及时回收内存）
    Close() {
        if (!this.IsDllReady())
            return
        DllCall(this.DllPath "\SttStream_Close", "CDecl Int")
        this.streamLoaded := false
        this.streamLanguage := ""
        this.asyncLanguage := ""
    }

    ; ---------- 流式识别（本地 OnlineRecognizer + zipformer2 CTC） ----------
    ; 后台加载状态：0未开始 1加载中 2成功 3失败；旧 DLL 无此导出时返回 -1
    StreamInitState() {
        if (!this.IsDllReady())
            return 0
        try
            return DllCall(this.DllPath "\SttStream_InitState", "CDecl Int")
        catch
            return -1
    }

    ; 后台线程加载流式模型（不阻塞调用方）。返回 true 表示已排队/已在加载/已就绪；
    ; 旧 DLL 没有该导出或模型不就绪时返回 false，调用方回退到同步 StreamEnsureInit。
    ; 记下申请的语言：DLL 不暴露「后台加载的是哪种」，加载完靠它确认能否采纳。
    StreamEnsureInitAsync(language := "zh-en") {
        ; 同一种模型（简/繁共用 zh-en）已在内存里：只需换标签，不用再排一次后台加载
        if (this.streamLoaded && SttEngine.ModelLanguage(this.streamLanguage) == SttEngine.ModelLanguage(language)) {
            this.streamLanguage := language
            return true
        }
        if (!this.IsStreamReady(language))
            return false
        f := this._StreamFiles(language)
        if (f[1] == "")
            return false
        this.asyncLanguage := language
        try
            r := DllCall(this.DllPath "\SttStream_InitAsync", "WStr", f[1], "WStr", f[2], "WStr", f[3], "WStr", f[4], "CDecl Int")
        catch
            return false
        return r != 0
    }

    ; 确保流式模型已加载（首次调用真正执行 SttStream_Init）
    StreamEnsureInit(language := "zh-en") {
        ; 加载期间别的线程来查状态要读到一致的结果，也避免两处同时发起加载
        wasCritical := A_IsCritical
        Critical("On")
        try return this._EnsureStreamModel(language)
        finally Critical(wasCritical)
    }

    _EnsureStreamModel(language) {
        ; 同一种模型就不重载：简体与繁體共用 zh-en 模型，只换输出转换，不重读 80MB。
        ; 命中时把 streamLanguage 改成这次要的语言，_StreamOutput 据此决定要不要转繁。
        if (this.streamLoaded && SttEngine.ModelLanguage(this.streamLanguage) == SttEngine.ModelLanguage(language)) {
            this.streamLanguage := language
            return true
        }
        ; 后台已加载完：同一个语言就直接采纳，避免重复加载一份模型
        stA := this.StreamInitState()
        if (stA == 2 && this._AsyncLangMatches(language)) {
            this.streamLoaded := true
            this.streamLanguage := language
            return true
        }
        ; 后台正在加载同一个语言：等它完成（最多 6 秒）
        if (stA == 1 && this._AsyncLangMatches(language)) {
            loop 120 {
                Sleep(50)
                stA := this.StreamInitState()
                if (stA == 2) {
                    this.streamLoaded := true
                    this.streamLanguage := language
                    return true
                }
                if (stA == 3) {
                    this.streamLoaded := false
                    this.streamLanguage := ""
                    this.lastError := this.StreamGetLastError()
                    return false
                }
            }
            return false
        }
        ; 走到这里：要么后台加载的是别的语言，要么根本没在加载。
        ; 换语言只能同步重载（1~3 秒），录音中不允许换（StreamBusy）。
        if (!this.IsStreamReady(language) || this.StreamBusy())
            return false
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

    ; 后台那次加载申请的就是这个语言（也可能是不知道 —— 老 DLL 或外部发起，按同语言处理）
    _AsyncLangMatches(language) {
        return this.asyncLanguage == "" || this.asyncLanguage == language
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
        r := DllCall(this.DllPath "\SttStream_Begin", "CDecl Int")
        this.lastError := r ? "" : this.StreamGetLastError()
        return r != 0
    }

    ; 有没有正在占用的流（录音中 / 收尾中）。这两个状态下不能重载模型。
    StreamBusy() {
        state := this.StreamGetState()
        return state == 1 || state == 2
    }

    ; 取当前累积文本。解码已在 DLL 内部线程完成，这里只是一次内存拷贝；
    ; 录音中每 ~40ms 调一次，成本可忽略。
    StreamPoll() {
        if (!this.IsDllReady())
            return ""
        if (!this._pollBuf)
            this._pollBuf := Buffer(16384)
        r := DllCall(this.DllPath "\SttStream_Poll", "Ptr", this._pollBuf, "Int", 16384, "CDecl Int")
        if (!r)
            return ""
        return this._StreamOutput(StrGet(this._pollBuf, "UTF-8"))
    }

    ; 停止并收尾。返回时本轮文本已落定（state=3），可直接 StreamGetResult。
    ; refine=1 时额外交给离线模型重识别整段，那是**异步**的（state=2，之后才 3），
    ; 调用方得自己等状态——输入法的实时场景用 0，别拿异步结果覆盖已上屏的字。
    StreamEnd(refine := 0) {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\SttStream_End", "Int", refine ? 1 : 0, "CDecl Int") != 0
    }

    ; 停止并丢弃
    StreamCancel() {
        if (!this.IsDllReady())
            return false
        return DllCall(this.DllPath "\SttStream_Cancel", "CDecl Int") != 0
    }

    ; 0空闲 1录音中 2精修中 3完成 4错误
    StreamGetState() {
        if (!this.IsDllReady())
            return 0
        return DllCall(this.DllPath "\SttStream_GetState", "CDecl Int")
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

; ---------- 启动预热 ----------
; 只探磁盘：该语言的流式模型齐备（encoder/model + tokens）才算装了。
; 不碰 DLL，未安装语音扩展的机器零开销。
SttStreamModelOnDisk(language := "zh-en") {
    ; 繁體中文用的是中英混合模型，目录仍在根上
    language := SttEngine.ModelLanguage(language)
    dir := A_WorkingDir "\Plugins\Voice\models\stt_stream"
    if (language != "zh-en")
        dir .= "\" language
    if (!FileExist(dir "\tokens.txt"))
        return false
    return FileExist(dir "\encoder*.onnx") || FileExist(dir "\model*.onnx")
}

; 后台预热流式语音模型（RMT 启动后调用）：只走 DLL 的异步加载，绝不阻塞主线程。
; 返回 true = 已在加载 / 已就绪；false = 缺模型、缺 DLL，或旧版 DLL 没有异步导出
; （旧 DLL 不在这里退化成同步加载——那会把启动卡住 1~3 秒，弹窗里再懒加载即可）。
SttWarmupStreamAsync(language := "") {
    if (language == "")
        language := SttEngine.DefaultLanguage()
    if (!SttStreamModelOnDisk(language))
        return false
    try {
        engine := InitSttEngine()
        ; 简/繁共用 zh-en 模型：模型已在内存就只换标签，不再排后台加载
        if (engine.streamLoaded && SttEngine.ModelLanguage(engine.streamLanguage) == SttEngine.ModelLanguage(language)) {
            engine.streamLanguage := language
            return true
        }
        if (!engine.IsDllReady() || !engine.IsStreamModelReady(language))
            return false
        st := engine.StreamInitState()
        if (st == 2 && engine._AsyncLangMatches(language)) {   ; 后台已加载完：采纳，别重复加载一份
            engine.streamLoaded := true
            engine.streamLanguage := language
            return true
        }
        if (st == 1 && engine._AsyncLangMatches(language))     ; 后台正在加载
            return true
        return engine.StreamEnsureInitAsync(language)
    } catch {
        return false
    }
}

; =====================================================================
; 会话编排层：VoiceInput（上接 SttEngine，业务方只调这个类）
;
; 职责边界：只做「会话编排」——什么时候开录、按节拍把 DLL 里的文本捞出来、
; 说完之后怎么收尾取最终结果。它不持有窗口、不碰控件、不弹提示、不做文案，
; 也不知道麦克风缓冲有多深、模型分块多大——那些都是 DLL 的事。
;
; 真正的活在 VoiceDll 里：WASAPI 采集、分块、解码、收尾补零、收尾前的尾音
; 落定全在 DLL 内部完成。本类每次调用只是一次 DllCall，取文本是一次内存拷贝。
;
; 识别语言由 Start 决定：跟着界面语言（SttEngine.DefaultLanguage）走，
; 一个会话内固定不变，中途改界面语言要等下一次开录才生效。
;
; 回调（构造后赋值，都可选）：
;   OnText(text)      实时识别文本，整段而非增量；没变化不重复触发
;   OnState(state)    "recording" / "idle"，界面据此换皮肤
;   OnNotify(key, detail)
;                     需要告诉用户的事，文案由调用方决定：
;                     loading / loadFailed / readyRetry / startFailed
;   HoldCheck()       返回 true 表示用户仍按着。按住说话的「松手」判定就靠它：
;                     按键只在按下时通知一次，松开没有事件，40ms 轮询时发现键已弹起即收尾。
;                     也用于「等模型加载完，但人已经松手了」的判断
;
; 用法（业务方只调下面这几个，不需要知道 model / stream / 状态码）：
;   vi := VoiceInput()
;   vi.OnText := (t) => ...
;   vi.Toggle()        ; 点麦克风：录→停、等→取消、闲→开录
;   vi.Start(true)     ; true = 按住说话发起；false = 点按钮发起
;   vi.Finish()        ; 用户松手：立刻收尾（尾音由 DLL 自己收干净）
;   vi.Commit()        ; 点确定：同步拿最终结果
;   vi.Close()         ; 关窗：停录、清定时器
;
; 缺模型时 Start 内部会弹下载引导并返回 false，业务方不必判断模型是否存在。
; =====================================================================
class VoiceInput {
    ; DLL 内部只有一路流：同一时刻只能有一个实例占用麦克风。
    ; 新会话开始时会把上一个实例落定（它的 OnText 仍会收到自己的最终文本），
    ; 免得两个窗口同时开录、互相抢流。
    static Active := ""

    __New() {
        this.OnText := ""
        this.OnState := ""
        this.OnNotify := ""
        this.HoldCheck := ""

        this.disposed := false
        this.rec := false          ; 正在录音
        this.byHold := false       ; 本次录音由按住键发起（松手即收尾）
        this.waiting := false      ; 模型还在加载：先受理，加载完自动开录
        this.waitByHold := false
        this.waitTicks := 0
        this.live := ""            ; 本轮识别文本（不含输入框原有内容）
        this.lang := ""            ; 本轮用的语音语言（Start 时定，会话内不变）
                                   ; 叫 lang 不叫 language：类成员名大小写不敏感，
                                   ; 与下面的 Language() 访问器同名会互相覆盖（Property is read-only）

        this.tickTimer := ObjBindMethod(this, "_Poll")
        this.waitTimer := ObjBindMethod(this, "_PollWait")
        this.stopTimer := ObjBindMethod(this, "_FinishNow")
    }

    ; ---------- 状态 ----------

    IsRecording() => this.rec
    IsWaiting() => this.waiting
    Language() => this.lang

    ; ---------- 生命周期 ----------

    ; 开窗后预热模型。和启动预热（SttWarmupStreamAsync）走同一个函数，这里只做转发，
    ; 预热逻辑不许有两份——两份必然在「已加载完」这类边界上判断不一致。
    Warmup() {
        if (this.disposed || this.rec)
            return false
        return SttWarmupStreamAsync(SttEngine.DefaultLanguage())
    }

    ; 麦克风按钮的统一入口：录音中→停并落定；等模型→取消；否则开录。
    ; 返回 true 表示已开始（或已排队等模型）。
    Toggle(byHold := false) {
        if (this.disposed)
            return false
        if (this.rec) {
            this.Stop(true)
            return false
        }
        if (this.waiting) {
            this.CancelWait()
            return false
        }
        return this.Start(byHold)
    }

    ; 开录。byHold=true 表示这是「按住说话」发起的——松手才会收尾，
    ; 且模型加载完时若人已松手就不再开录。返回是否已开始（或已排队）。
    Start(byHold := false) {
        if (this.disposed || this.rec || this.waiting)
            return false
        ; 语言跟着界面走，一个会话内不变（换语言要重载模型，不能在录到一半换）
        this.lang := SttEngine.DefaultLanguage()
        ; 没装扩展/没下该语言的模型：这里会把下载引导排到伪线程再弹，业务方不用管。
        if (!SttPromptModelDownload(this.lang))
            return false
        engine := this._Engine()
        if (!IsObject(engine))
            return false
        this._Acquire()
        ; 模型还在后台加载：排个队，加载完自动开录，不用让用户干等重按。
        ; 只有后台加载的就是本语言时才值得等；加载的是别的语言，等完也得重载，没意义。
        if (engine.StreamInitState() == 1 && engine._AsyncLangMatches(this.lang)) {
            this._BeginWait(byHold)
            return true
        }
        this.byHold := byHold
        return this._Begin()
    }

    ; 说完（松开按键）：直接收尾。尾音（设备缓冲里还没被拉走的最后几十毫秒）
    ; 由 DLL 的 End 自己等干净，这里不掐表。
    ; 但收尾要等尾音 + 解码（合计约 80ms），而松手是在 40ms 轮询里发现的，
    ; 压在这一拍上会把轮询和界面一起拖住，所以挪到伪线程里做。
    Finish() {
        if (this.disposed || !this.rec || !this.byHold)
            return
        SetTimer(this.stopTimer, -1)
    }

    _FinishNow() {
        if (this.disposed || !this.rec || !this.byHold)
            return
        this.Stop(true)
    }

    ; 立即停。collect=true 时把最终文本回抛（松手、切窗、再点麦克风走这条）；
    ; false 只停采集、丢弃结果（关窗走这条）。
    Stop(collect := true) {
        this._Release()
        if (!this.rec) {
            SetTimer(this.tickTimer, 0)
            return
        }
        this.rec := false
        this.byHold := false
        SetTimer(this.tickTimer, 0)
        engine := this._Engine()
        ; End 返回时本轮文本已落定，取一次即可，不需要再轮询状态
        if (!IsObject(engine) || !engine.StreamEnd(0)) {
            this._SetState("idle")
            return
        }
        if (collect)
            this._TakeFinal(engine)
        this._SetState("idle")
    }

    ; 同步收尾（点确定时用）。返回本轮识别文本；窗口按「原有内容 + 这段」上屏即可。
    Commit() {
        if (!this.rec)
            return this.live
        this.Stop(true)
        return this.live
    }

    ; 放弃「等模型加载」：把界面从「加载中」退回空闲
    CancelWait() {
        this._EndWait()
        this._SetState("idle")
    }

    ; 关窗前清理：停录、停定时器、作废所有进行中的状态
    Close() {
        this.Stop(false)
        this._EndWait()
        SetTimer(this.tickTimer, 0)
        this.disposed := true
    }

    ; ---------- 内部：麦克风占用 ----------

    ; 抢占唯一的一路流：先把上一个还开着的会话落定，再登记自己。
    _Acquire() {
        prev := VoiceInput.Active
        if (IsObject(prev) && prev != this) {
            try prev.Stop(true)
        }
        VoiceInput.Active := this
    }

    _Release() {
        if (VoiceInput.Active == this)
            VoiceInput.Active := ""
    }

    ; ---------- 内部：录音 ----------

    _Begin() {
        engine := this._Engine()
        if (!IsObject(engine))
            return false
        if (!engine.StreamBegin(this.lang)) {
            this._Notify("startFailed", engine.lastError)
            this._Release()
            return false
        }
        this.rec := true
        this.live := ""
        this._SetState("recording")
        SetTimer(this.tickTimer, 40)
        return true
    }

    ; 录音中的统一节拍：兜底停录 + 捞实时文本。
    ; 解码已在 DLL 内部线程完成，这里每拍只是一次内存拷贝。
    _Poll() {
        if (!this.rec) {
            SetTimer(this.tickTimer, 0)
            return
        }
        ; 松手：按住说话键只在松开时收尾，这里靠物理键态发现松手（没有 KeyUp 事件）。
        ; 收尾要等尾音 + 解码（约 80ms），不能压在 40ms 轮询这一拍上，交给 Finish 挪到伪线程。
        if (this.byHold && !this._Held()) {
            this.Finish()
            return
        }
        engine := this._Engine()
        if (!IsObject(engine))
            return
        live := ""
        try live := engine.StreamPoll()
        if (Trim(live) != "" && live != this.live) {
            this.live := live
            this._EmitText()
        }
    }

    ; 收尾解码偶尔比实时文本短（尾部没解全），此时保留已上屏的那份更完整
    _TakeFinal(engine) {
        result := ""
        try result := Trim(engine.StreamGetResult())
        if (StrLen(result) > StrLen(this.live)) {
            this.live := result
            this._EmitText()
        }
    }

    ; ---------- 内部：等模型加载 ----------

    _BeginWait(byHold) {
        this.waiting := true
        this.waitByHold := byHold
        this.waitTicks := 0
        this._Notify("loading")
        SetTimer(this.waitTimer, 100)
    }

    _PollWait() {
        if (!this.waiting || this.disposed) {
            this.waiting := false
            SetTimer(this.waitTimer, 0)
            return
        }
        st := this._InitState()
        if (st == 1) {                      ; 还在加载
            this.waitTicks++
            if (this.waitTicks > 300)       ; 30 秒还没好：放弃（正常 1~3 秒）
                this._EndWait()
            return
        }
        SetTimer(this.waitTimer, 0)
        this.waiting := false
        this.waitTicks := 0
        if (st != 2 && st != -1) {          ; 3=加载失败
            this._Notify("loadFailed")
            this._SetState("idle")
            this._Release()
            return
        }
        ; 按住说话的：已经松手就不开录（话早说完了），让窗口提示再按一次
        if (this.waitByHold && !this._Held()) {
            this._Notify("readyRetry")
            this._SetState("idle")
            this._Release()
            return
        }
        this.byHold := this.waitByHold
        this._Begin()
    }

    _EndWait() {
        this.waiting := false
        this.waitByHold := false
        this.waitTicks := 0
        SetTimer(this.waitTimer, 0)
        this._Release()
    }

    ; ---------- 内部：回调与工具 ----------

    _EmitText() {
        if (this.OnText != "")
            try this.OnText.Call(this.live)
    }

    _SetState(state) {
        if (this.OnState != "")
            try this.OnState.Call(state)
    }

    _Notify(key, detail := "") {
        if (this.OnNotify != "")
            try this.OnNotify.Call(key, detail)
    }

    ; 用户是否仍按着（由调用方提供，本类不关心是哪个键）
    _Held() {
        if (this.HoldCheck == "")
            return true
        try return this.HoldCheck.Call()
        return true
    }

    _InitState() {
        engine := this._Engine()
        return IsObject(engine) ? engine.StreamInitState() : -1
    }

    _Engine() {
        if (!IsSet(InitSttEngine))
            return ""
        engine := ""
        try engine := InitSttEngine()
        return IsObject(engine) ? engine : ""
    }
}
