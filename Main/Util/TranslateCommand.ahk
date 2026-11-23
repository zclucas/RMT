#Requires AutoHotkey v2.0
#Include TranslateUtil.ahk

; =====================================================================
; 翻译指令：数据 + 执行
;
; 两种引擎，同一套输入输出：
;   Index-Translate（本地）—— 走 TranslateEngine，进程内推理，不联网
;   AI 通道（远程）        —— 走 AI 设置里的 OpenAI 兼容接口，链路与 AI判断 一致
;
; 指令只负责「取文本 → 翻译 → 写变量」，译文怎么用是后面指令的事。
; =====================================================================

class TranslateData {
    SerialStr := ""
    Source := "变量"                 ; 变量 / 剪切板 / 固定文本
    Text := ""                       ; 变量名或固定文本，随 Source 变
    Target := "简体中文"             ; 目标语言
    TargetCustom := ""               ; Target 选「自定义」时的语言名，如 泰语
    Engine := "Index-Translate 2B"   ; 见 TranslateCommand.Engines
    Device := "自动"                 ; 自动 / GPU / CPU，只对本地引擎有效
    Glossary := ""                   ; 旧版术语表原文，兼容读取且不自动改写
    GlossaryItems := []              ; 新版结构化术语表 [{source, target}]
    ResultVar := "TransRes"
    ErrorVar := ""
}

class TranslateCommand {
    static FriendlyErrorPrefix := "RMT_TRANSLATE_USER|"
    static MissingModelPrefix := "RMT_TRANSLATE_MISSING_MODEL|"
    static Sources := ["变量", "剪切板", "固定文本"]
    static Engines := ["Index-Translate 2B", "Index-Translate 9B", "AI 通道"]
    ; 推理设备，只对本地引擎有效。自动与 GPU 在功能上只差一件事：
    ; 自动在没有 GPU 时静默落 CPU，GPU 会明确报「本机没有可用 GPU」，
    ; 免得以为在用显卡其实在跑 CPU。
    static Devices := ["自动", "GPU", "CPU"]
    ; 目标语言 → 模型文件与 prompt 里的语言名。
    ; 本地模型的 GGUF 文件名与这里分开维护：9B 没下载时指令会给出明确提示，不会误用 2B。
    ; 末尾的「自定义」不是语言：选中时取 data.TargetCustom 当语言名（模型支持 150 种语言）。
    static Targets := ["简体中文", "繁体中文", "英语", "日语", "韩语", "俄语", "法语", "德语", "西班牙语", "自定义"]
    static TargetPrompt := Map(
        "简体中文", "简体中文", "繁体中文", "繁体中文（台湾用语）",
        "英语", "英语", "日语", "日语", "韩语", "韩语", "俄语", "俄语",
        "法语", "法语", "德语", "德语", "西班牙语", "西班牙语")
    static EngineModels := Map(
        "Index-Translate 2B", "Index-Translate-2B.Q4_K_M.gguf",
        "Index-Translate 9B", "Index-Translate-9B.Q4_K_M.gguf")

    static IsLocal(engine) => TranslateCommand.EngineModels.Has(engine)

    static TimeoutMs() {
        global MainSoftData
        timeout := MainSoftData.HasOwnProp("TranslateTimeoutMs") ? Integer(MainSoftData.TranslateTimeoutMs) : 30000
        return (timeout >= 1000 && timeout <= 3600000) ? timeout : 30000
    }

    static UserError(message) => Error(TranslateCommand.FriendlyErrorPrefix . message)

    ; 设备归一：旧配置没有 Device 字段，按「自动」处理。
    static ResolveDevice(data) {
        return data.HasOwnProp("Device") ? CmdEnumZh(data.Device, TranslateCommand.Devices) : "自动"
    }

    ; 设备 → llama 的卸载层数：自动 / GPU = -1（有 GPU 就全卸载，没有落 CPU），
    ; CPU = 0（完全不碰显存，显存紧张或驱动不稳时用）。
    static ResolveGpuLayers(data) {
        return TranslateCommand.ResolveDevice(data) == "CPU" ? 0 : -1
    }

    ; 从指令数据里取待翻译文本。文本一律走变量替换（{变量} 形式），
    ; 剪切板是取当前内容，固定文本原样返回。
    static ReadSource(data, resolve) {
        switch data.Source {
            case "剪切板": return A_Clipboard
            case "固定文本": return data.Text
            default: return resolve(data.Text)
        }
    }

    ; 目标语言归一：「自定义」取 TargetCustom（旧配置没有这个字段，给空报错），
    ; 其余按枚举表归一。返回语言名；再经 TargetPrompt 映射成 prompt 用的写法。
    static ResolveTarget(data) {
        target := CmdEnumZh(data.Target, TranslateCommand.Targets)
        if (target == "自定义") {
            target := Trim(data.HasOwnProp("TargetCustom") ? data.TargetCustom : "")
            if (target == "")
                throw TranslateCommand.UserError(GetLang("自定义目标语言不能为空"))
        }
        return target
    }

    static Execute(data, resolve, cancelled, &timedOut := false) {
        timedOut := false
        text := Trim(TranslateCommand.ReadSource(data, resolve))
        if (text == "")
            throw TranslateCommand.UserError(GetLang("翻译内容为空"))

        target := TranslateCommand.ResolveTarget(data)
        promptTarget := TranslateCommand.TargetPrompt.Has(target) ? TranslateCommand.TargetPrompt[target] : target
        glossary := data.HasOwnProp("Glossary") ? data.Glossary : ""
        glossaryItems := data.HasOwnProp("GlossaryItems") && data.GlossaryItems is Array ? data.GlossaryItems : []

        if (TranslateCommand.IsLocal(data.Engine))
            return TranslateCommand.ExecuteLocal(text, promptTarget, glossary, glossaryItems, data, cancelled, &timedOut)
        return TranslateCommand.ExecuteRemote(text, promptTarget, glossary, glossaryItems, data, cancelled, &timedOut)
    }

    static ExecuteLocal(text, target, glossary, glossaryItems, data, cancelled, &timedOut := false, &elapsedMs := 0) {
        if (cancelled())
            return ""
        engine := TranslateEngine.Shared()
        if (!engine.IsDllReady() && !TranslateEngine.Available())
            throw Error(GetLang("翻译组件缺失，请先编译 Plugins\Translate"))
        ; 换模型或换推理设备才重新 Load；同一组合内反复调用复用已加载的模型
        want := TranslateCommand.EngineModels[data.Engine]
        if (!TranslateEngine.HasModel(want))
            throw Error(TranslateCommand.MissingModelPrefix want)
        layers := TranslateCommand.ResolveGpuLayers(data)
        ; 明确选 GPU 却没有可用后端时直接报，不要静默落 CPU 让人以为在用显卡
        if (layers == -1 && TranslateCommand.ResolveDevice(data) == "GPU" && !engine.HasGpu())
            throw TranslateCommand.UserError(GetLang("本机没有可用的 GPU 推理后端，请把设备改成自动或 CPU"))
        if (engine.modelPath == "" || !InStr(engine.modelPath, want) || engine.gpuLayers != layers) {
            err := engine.Load(want, Map("nGpuLayers", layers))
            if (err != "")
                throw Error(err)
        }
        result := engine.Translate(text, target, glossary, glossaryItems, TranslateCommand.TimeoutMs())
        if (result["ok"] != 1 && InStr(result["error"], "文本过长"))
            throw TranslateCommand.UserError(result["error"])
        if (result["ok"] != 1)
            throw Error(result["error"])
        elapsedMs := result["elapsedMs"]
        timedOut := result["truncated"] == 1
        return result["text"]
    }

    ; 与 AI判断 同一条链路：POST {base}/chat/completions。
    ; 区别只在 prompt 与不需要 JSON 约束。
    static ExecuteRemote(text, target, glossary, glossaryItems, data, cancelled, &timedOut := false, &elapsedMs := 0) {
        global SettingFile, SettingSection
        key := Trim(CfgRead(SettingFile, SettingSection, "AiApiKey", ""))
        baseUrl := RTrim(Trim(CfgRead(SettingFile, SettingSection, "AiApiBaseUrl", "")), "/")
        model := Trim(CfgRead(SettingFile, SettingSection, "AiModel", ""))
        if (baseUrl == "" || model == "")
            throw TranslateCommand.UserError(GetLang("请先在 AI 设置中填写 API URL 与模型"))

        prompt := "把下面的内容翻译成" target "。只输出译文，不要解释、不要加引号、不要重复原文。"
        if (Trim(glossary) != "")
            prompt .= "`n术语对照（必须遵守）：`n" glossary
        if (glossaryItems.Length) {
            prompt .= "`n术语对照（必须遵守）："
            for item in glossaryItems
                prompt .= "`n" item.source " → " item.target
        }
        request := HttpRequestData()
        request.Method := "POST"
        request.Url := baseUrl "/chat/completions"
        request.Headers := "Content-Type: application/json; charset=utf-8" (key == "" ? "" : "`nAuthorization: Bearer " key)
        request.TimeoutMs := TranslateCommand.TimeoutMs()
        request.Retries := 0
        request.Body := JSON.stringify({model: model, temperature: 0, messages: [
            {role: "system", content: "你是翻译器，只输出译文。"},
            {role: "user", content: prompt "`n`n" text}
        ]}, 0)
        startTick := A_TickCount
        response := HttpRequestExecute(request, (t) => t, cancelled)
        elapsedMs := A_TickCount - startTick
        if (cancelled())
            return ""
        timedOut := response.TimedOut
        if (response.Status < 200 || response.Status >= 300)
            throw TranslateCommand.UserError(GetLang(response.Error != "" ? response.Error : "AI 请求失败") " [" response.Status "]")
        try {
            body := JSON.parse(response.Body)
            content := Trim(body["choices"][1]["message"]["content"], " `t`r`n")
        } catch {
            throw TranslateCommand.UserError(GetLang("AI 返回内容无法解析"))
        }
        if (content == "")
            throw TranslateCommand.UserError(GetLang("AI 返回内容为空"))
        return content
    }
}

OnTranslate(tableItem, cmd, index) {
    data := GetMacroCMDData(StrSplit(cmd, "_")[1])
    cancelled := () => tableItem.Items[index].Killed
    if (cancelled())
        return
    value := ""
    failure := ""
    friendlyFailure := false
    timedOut := false
    resolve := (text) => GetReplaceVarText(tableItem, index, text)
    try value := TranslateCommand.Execute(data, resolve, cancelled, &timedOut)
    catch as e {
        failure := e.Message
        if (SubStr(failure, 1, StrLen(TranslateCommand.FriendlyErrorPrefix)) == TranslateCommand.FriendlyErrorPrefix) {
            failure := SubStr(failure, StrLen(TranslateCommand.FriendlyErrorPrefix) + 1)
            friendlyFailure := true
        } else if (SubStr(failure, 1, StrLen(TranslateCommand.MissingModelPrefix)) == TranslateCommand.MissingModelPrefix) {
            modelName := SubStr(failure, StrLen(TranslateCommand.MissingModelPrefix) + 1)
            try RmtRequestInternalDownload("translate-model:" . modelName)
            failure := Format(GetLang("本地翻译模型 {} 未下载，已请求后台下载；当前宏已中断。"), modelName)
        }
    }
    if (cancelled())
        return
    SaveTranslateResult(data, value, failure)
    if (friendlyFailure) {
        RMTErrorShow(failure, RMT_LV_WARN, "TranslateCommand")
        return
    }
    if (timedOut)
        RMTErrorShow(GetLang("翻译结果可能不完整，已写入部分译文。"), RMT_LV_WARN, "TranslateCommand")
    if (failure != "")
        throw Error(failure)
}

SaveTranslateResult(data, value, failure) {
    errorVar := data.HasOwnProp("ErrorVar") ? data.ErrorVar : ""
    names := []
    values := []
    for pair in [[data.ResultVar, value], [errorVar, failure]] {
        if (pair[1] == "")
            continue
        names.Push(pair[1])
        values.Push(pair[2])
    }
    if (names.Length)
        MySetGlobalVariable(names, values, false)
}

RegisterTranslateVars(data) {
    errorVar := data.HasOwnProp("ErrorVar") ? data.ErrorVar : ""
    for name in [data.ResultVar, errorVar]
        if (name != "")
            MySoftData.GlobalVariMap[name] := true
}
