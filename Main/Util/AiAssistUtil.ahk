#Requires AutoHotkey v2.0
#Include JsonUtil.ahk

; =====================================================================
; AI 助手：配置读写 + 经 RMT.dll(C#) 调用 OpenAI 兼容 Chat/Models
; API URL 形如 https://api.openai.com/v1（可指向兼容网关）
; =====================================================================

class AiAssist {
    static AccessLabels := ["只读", "工作区", "完全访问"]
    static ApprovalLabels := ["手动审批", "自动审批", "完全访问"]
    ; 模型商：id / 显示名 / API URL（自定义 url 为空，需手填）
    static Providers := [
        Map("id", "openai", "name", "OpenAI", "url", "https://api.openai.com/v1"),
        Map("id", "azure", "name", "Azure OpenAI", "url", ""),
        Map("id", "deepseek", "name", "DeepSeek", "url", "https://api.deepseek.com/v1"),
        Map("id", "dashscope", "name", "通义千问", "url", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        Map("id", "volcengine", "name", "火山方舟", "url", "https://ark.cn-beijing.volces.com/api/v3"),
        Map("id", "hunyuan", "name", "腾讯混元", "url", "https://api.hunyuan.cloud.tencent.com/v1"),
        Map("id", "qianfan", "name", "百度千帆", "url", "https://qianfan.baidubce.com/v2"),
        Map("id", "moonshot", "name", "月之暗面", "url", "https://api.moonshot.cn/v1"),
        Map("id", "zhipu", "name", "智谱 GLM", "url", "https://open.bigmodel.cn/api/paas/v4"),
        Map("id", "baichuan", "name", "百川智能", "url", "https://api.baichuan-ai.com/v1"),
        Map("id", "yi", "name", "零一万物", "url", "https://api.lingyiwanwu.com/v1"),
        Map("id", "stepfun", "name", "阶跃星辰", "url", "https://api.stepfun.com/v1"),
        Map("id", "minimax", "name", "MiniMax", "url", "https://api.minimax.chat/v1"),
        Map("id", "siliconflow", "name", "硅基流动", "url", "https://api.siliconflow.cn/v1"),
        Map("id", "gemini", "name", "Google Gemini", "url", "https://generativelanguage.googleapis.com/v1beta/openai"),
        Map("id", "xai", "name", "xAI Grok", "url", "https://api.x.ai/v1"),
        Map("id", "mistral", "name", "Mistral", "url", "https://api.mistral.ai/v1"),
        Map("id", "groq", "name", "Groq", "url", "https://api.groq.com/openai/v1"),
        Map("id", "together", "name", "Together AI", "url", "https://api.together.xyz/v1"),
        Map("id", "fireworks", "name", "Fireworks", "url", "https://api.fireworks.ai/inference/v1"),
        Map("id", "openrouter", "name", "OpenRouter", "url", "https://openrouter.ai/api/v1"),
        Map("id", "ollama", "name", "Ollama", "url", "http://localhost:11434/v1"),
        Map("id", "lmstudio", "name", "LM Studio", "url", "http://localhost:1234/v1"),
        Map("id", "custom", "name", "自定义", "url", "")
    ]

    static EnsureDefaults() {
        global MainSoftData
        if (!IsSet(MainSoftData) || !IsObject(MainSoftData))
            return
        if (!MainSoftData.HasOwnProp("AiApiKey"))
            MainSoftData.AiApiKey := ""
        if (!MainSoftData.HasOwnProp("AiApiBaseUrl"))
            MainSoftData.AiApiBaseUrl := "https://api.openai.com/v1"
        if (!MainSoftData.HasOwnProp("AiProvider"))
            MainSoftData.AiProvider := "openai"
        if (!MainSoftData.HasOwnProp("AiModel"))
            MainSoftData.AiModel := ""
        if (!MainSoftData.HasOwnProp("AiModelList"))
            MainSoftData.AiModelList := ""
        if (!MainSoftData.HasOwnProp("AiAccessMode"))
            MainSoftData.AiAccessMode := 2   ; 工作区（可读任意，写入仅软件目录）
        if (!MainSoftData.HasOwnProp("AiApprovalMode"))
            MainSoftData.AiApprovalMode := 2 ; 自动审批
    }

    static LoadFromIni() {
        global MainSoftData, IniFile, IniSection
        AiAssist.EnsureDefaults()
        MainSoftData.AiApiKey := IniRead(IniFile, IniSection, "AiApiKey", "")
        MainSoftData.AiApiBaseUrl := IniRead(IniFile, IniSection, "AiApiBaseUrl", "https://api.openai.com/v1")
        MainSoftData.AiProvider := IniRead(IniFile, IniSection, "AiProvider", "")
        MainSoftData.AiModel := IniRead(IniFile, IniSection, "AiModel", "")
        MainSoftData.AiModelList := IniRead(IniFile, IniSection, "AiModelList", "")
        MainSoftData.AiAccessMode := Integer(IniRead(IniFile, IniSection, "AiAccessMode", 2))
        MainSoftData.AiApprovalMode := Integer(IniRead(IniFile, IniSection, "AiApprovalMode", 2))
        if (MainSoftData.AiAccessMode < 1 || MainSoftData.AiAccessMode > 3)
            MainSoftData.AiAccessMode := 2
        if (MainSoftData.AiApprovalMode < 1 || MainSoftData.AiApprovalMode > 3)
            MainSoftData.AiApprovalMode := 2
        if (Trim(MainSoftData.AiProvider) == "")
            MainSoftData.AiProvider := AiAssist.MatchProviderId(MainSoftData.AiApiBaseUrl)
    }

    static SaveToIni() {
        global MainSoftData, IniFile, IniSection
        AiAssist.EnsureDefaults()
        IniWrite(MainSoftData.AiApiKey, IniFile, IniSection, "AiApiKey")
        IniWrite(MainSoftData.AiApiBaseUrl, IniFile, IniSection, "AiApiBaseUrl")
        IniWrite(MainSoftData.AiProvider, IniFile, IniSection, "AiProvider")
        IniWrite(MainSoftData.AiModel, IniFile, IniSection, "AiModel")
        IniWrite(MainSoftData.AiModelList, IniFile, IniSection, "AiModelList")
        IniWrite(MainSoftData.AiAccessMode, IniFile, IniSection, "AiAccessMode")
        IniWrite(MainSoftData.AiApprovalMode, IniFile, IniSection, "AiApprovalMode")
    }

    static ProviderIndex(id := "") {
        global MainSoftData
        if (id == "")
            id := MainSoftData.HasProp("AiProvider") ? MainSoftData.AiProvider : "openai"
        for i, p in AiAssist.Providers {
            if (p["id"] = id)
                return i
        }
        return AiAssist.Providers.Length  ; 自定义
    }

    static ProviderByIndex(idx) {
        idx := Integer(idx)
        if (idx < 1 || idx > AiAssist.Providers.Length)
            idx := AiAssist.Providers.Length
        return AiAssist.Providers[idx]
    }

    static MatchProviderId(url) {
        url := AiAssist.NormalizeBaseUrl(url)
        if (url == "")
            return "custom"
        for p in AiAssist.Providers {
            if (p["id"] = "custom")
                continue
            if (AiAssist.NormalizeBaseUrl(p["url"]) = url)
                return p["id"]
        }
        return "custom"
    }

    static IsConfigured() {
        global MainSoftData
        AiAssist.EnsureDefaults()
        return Trim(MainSoftData.AiApiKey) != "" && Trim(MainSoftData.AiApiBaseUrl) != "" && Trim(MainSoftData.AiModel) != ""
    }

    static NormalizeBaseUrl(url) {
        url := Trim(url)
        url := RTrim(url, "/\")
        return url
    }

    static ModelListArr() {
        global MainSoftData
        AiAssist.EnsureDefaults()
        arr := []
        seen := Map()
        if (Trim(MainSoftData.AiModel) != "") {
            arr.Push(MainSoftData.AiModel)
            seen[MainSoftData.AiModel] := true
        }
        for part in StrSplit(MainSoftData.AiModelList, ",") {
            m := Trim(part)
            if (m == "" || seen.Has(m))
                continue
            seen[m] := true
            arr.Push(m)
        }
        return arr
    }

    static AccessLabel(mode := "") {
        global MainSoftData
        if (mode == "")
            mode := MainSoftData.AiAccessMode
        mode := Integer(mode)
        if (mode < 1 || mode > 3)
            mode := 2
        return AiAssist.AccessLabels[mode]
    }

    static ApprovalLabel(mode := "") {
        global MainSoftData
        if (mode == "")
            mode := MainSoftData.AiApprovalMode
        mode := Integer(mode)
        if (mode < 1 || mode > 3)
            mode := 2
        return AiAssist.ApprovalLabels[mode]
    }

    ; GET {base}/models → 模型 id 数组（C# RMT.AiAssist）
    static FetchModels(baseUrl := "", apiKey := "") {
        global MainSoftData
        AiAssist.EnsureDefaults()
        if (baseUrl == "")
            baseUrl := MainSoftData.AiApiBaseUrl
        if (apiKey == "")
            apiKey := MainSoftData.AiApiKey
        baseUrl := AiAssist.NormalizeBaseUrl(baseUrl)
        if (baseUrl == "" || Trim(apiKey) == "")
            throw Error(GetLang("请先填写 API Key 与 API URL"))
        ai := GetRmtAi()
        idsJson := ai.GetModels(baseUrl, apiKey)
        ids := AiAssist._ParseJsonStringArray(idsJson)
        if (ids.Length < 1)
            throw Error(GetLang("未解析到可用模型，请检查 API URL 是否指向 OpenAI 兼容接口"))
        return ids
    }

    ; messages: [{role, content}, ...] ；返回助手文本（C# RMT.AiAssist）
    static Chat(messages, model := "", baseUrl := "", apiKey := "") {
        global MainSoftData
        AiAssist.EnsureDefaults()
        if (baseUrl == "")
            baseUrl := MainSoftData.AiApiBaseUrl
        if (apiKey == "")
            apiKey := MainSoftData.AiApiKey
        if (model == "")
            model := MainSoftData.AiModel
        baseUrl := AiAssist.NormalizeBaseUrl(baseUrl)
        if (baseUrl == "" || Trim(apiKey) == "" || Trim(model) == "")
            throw Error(GetLang("请先在 AI 设置中填写 API Key、API URL 与模型"))
        messagesJson := AiAssist._BuildMessagesJson(messages)
        ai := GetRmtAi()
        return String(ai.ChatCompletion(baseUrl, apiKey, model, messagesJson))
    }

    ; 异步对话：不阻塞 AHK。随后用 ChatState / TakeChat 取结果。
    static BeginChat(messages, model := "", baseUrl := "", apiKey := "") {
        global MainSoftData
        AiAssist.EnsureDefaults()
        if (baseUrl == "")
            baseUrl := MainSoftData.AiApiBaseUrl
        if (apiKey == "")
            apiKey := MainSoftData.AiApiKey
        if (model == "")
            model := MainSoftData.AiModel
        baseUrl := AiAssist.NormalizeBaseUrl(baseUrl)
        if (baseUrl == "" || Trim(apiKey) == "" || Trim(model) == "")
            throw Error(GetLang("请先在 AI 设置中填写 API Key、API URL 与模型"))
        messagesJson := AiAssist._BuildMessagesJson(messages)
        toolsJson := AiAssist.BuildToolsJson()
        ai := GetRmtAi()
        ; COM 不识别 C# 重载：新 DLL 固定 5 参；旧 DLL 只有 4 参时回退
        try ai.BeginChatCompletion(baseUrl, apiKey, model, messagesJson, toolsJson)
        catch
            ai.BeginChatCompletion(baseUrl, apiKey, model, messagesJson)
    }

    static ChatState() {
        ai := GetRmtAi()
        return Integer(ai.GetChatState())
    }

    static TakeChat() {
        ai := GetRmtAi()
        return String(ai.TakeChatResult())
    }

    static PeekChat() {
        return String(GetRmtAi().PeekChatPartial())
    }

    static CancelChat() {
        try GetRmtAi().CancelChat()
        catch {
        }
    }

    static BuildSystemPrompt() {
        global MainSoftData
        access := AiAssist.AccessLabel()
        approval := AiAssist.ApprovalLabel()
        mode := Integer(MainSoftData.AiAccessMode)
        prompt := "你是 RMT（按键宏工具）内置助手，直接在当前已打开的配置里工作。"
            . "`n当前写入权限：" access "；指令审批：" approval "。"
            . "`n回答风格对齐 Cursor Agent：直接给结论与可执行结果，少寒暄；用 Markdown 组织（短标题、列表、代码块、表格）。"
            . "`n如需引导用户查看某条宏，使用链接格式：[说明](rmt:页签序号:宏序号)，例如 [当前页第1个宏](rmt:1:1)。"
            . "`nread_file 可读任意本地文件；list_dir 可列任意目录。用户消息里的下划线文件名是附件，正文通常已附在消息中。"
        if (mode <= 1) {
            prompt .= "`n当前为只读：只能读取文件/配置并解释，不要声称已改配置，不要调用任何写入或执行工具。"
        } else {
            prompt .= "`n你拥有内置工具，必须自己调用，不要说「没有读文件/执行工具」。"
                . "`n配置：list_macros / read_macro / update_macro / add_macro。"
                . "`n用户要求新增/修改宏时：先 list_macros 或 read_macro 确认目标，再 update_macro / add_macro。"
                . "`n改完后必须用中文一两句话说明改了哪条、指令是什么。禁止只回空内容，禁止说「请到软件里手动修改」。"
                . "`n指令串（英文逗号连接）："
                . "`n- 按键_a_点击_100、按键_LButton_点击_50、间隔_80"
                . "`n- 移动_X_Y_速度_模式（模式0=屏幕绝对坐标，1=相对；速度默认90）"
                . "`n- 变量_名字_当前鼠标坐标X 或 变量_名字_当前鼠标坐标Y（记下触发时的鼠标位置）"
                . "`n回到原位示例：变量_sx_当前鼠标坐标X,变量_sy_当前鼠标坐标Y,移动_1919_0_90_0,按键_LButton_点击_50,移动_sx_sy_90_0"
                . "`n屏幕右上角用接近屏幕宽、Y=0 的绝对坐标；用户写「1:2」表示第1页第2条宏。"
            if (Integer(MainSoftData.AiApprovalMode) == 1)
                prompt .= "`n手动审批：写操作前用户会确认；被拒绝则改用说明。"
            prompt .= "`nwrite_file / run_command / run_script 已可用（.ahk / .ps1 / .bat / .py）。"
            if (mode >= 3)
                prompt .= "当前为完全访问：读写没有任何路径限制。"
            else
                prompt .= "当前为工作区：可读任意文件，写入/执行只能落在若梦兔软件目录内。"
                    . "若用户要求写到桌面或其他目录外路径，工具会失败；你必须用中文明确说明："
                    . "写入失败是因为当前写入权限为「工作区」，请到 AI 设置把写入权限改为「完全访问」。禁止只回空内容。"
        }
        snap := AiAssist.WorkspaceSnapshot()
        if (snap != "")
            prompt .= "`n`n## 当前配置`n" snap
        toolsDoc := AiAssist.LoadMcpToolsPrompt()
        if (toolsDoc != "")
            prompt .= "`n`n---`n以下为独立 MCP（Cursor 用 RMTMcps.exe）对照说明，内置对话不要调用这些工具名：`n" toolsDoc
        return prompt
    }

    static CanWrite() {
        global MainSoftData
        AiAssist.EnsureDefaults()
        return Integer(MainSoftData.AiAccessMode) >= 2
    }

    static CanWriteFile() {
        global MainSoftData
        AiAssist.EnsureDefaults()
        return Integer(MainSoftData.AiAccessMode) >= 2
    }

    static CanReadFile() {
        return true
    }

    static CanRun() {
        return AiAssist.CanWriteFile()
    }

    static IsFullAccess() {
        global MainSoftData
        AiAssist.EnsureDefaults()
        return Integer(MainSoftData.AiAccessMode) >= 3
    }

    static BuildToolsJson() {
        if (!AiAssist.CanWrite() && !AiAssist.CanReadFile())
            return ""
        tools := []
        if (AiAssist.CanReadFile()) {
            tools.Push(AiAssist._ToolDef("read_file", "读取任意本地文本文件。用户拖入/粘贴的附件优先用这个（或看消息里已附的正文）。", '[{"name":"path","type":"string","desc":"绝对路径或相对工作目录的路径"},{"name":"max_chars","type":"integer","desc":"最多返回字符数，默认 20000"}]'))
            tools.Push(AiAssist._ToolDef("list_dir", "列出任意本地目录下的文件和子目录。", '[{"name":"path","type":"string","desc":"目录路径，默认工作目录"}]'))
            tools.Push(AiAssist._ToolDef("list_macros", "列出当前已加载配置里的宏（页签、序号、触发键、备注、指令摘要）。", "[]"))
            tools.Push(AiAssist._ToolDef("read_macro", "读取一条宏的完整字段。", '[{"name":"tab","type":"integer","desc":"页签序号，1-based"},{"name":"index","type":"integer","desc":"宏序号，1-based"}]'))
        }
        if (AiAssist.CanWrite()) {
            tools.Push(AiAssist._ToolDef("update_macro", "就地修改一条已有宏并立即保存、刷新界面。", '[{"name":"tab","type":"integer","desc":"页签序号"},{"name":"index","type":"integer","desc":"宏序号"},{"name":"trigger_key","type":"string","desc":"触发键，如 r / F6"},{"name":"remark","type":"string","desc":"备注"},{"name":"macro","type":"string","desc":"指令串，如 变量_sx_当前鼠标坐标X,移动_1919_0_90_0,按键_LButton_点击_50,移动_sx_sy_90_0"},{"name":"commands","type":"string","desc":"JSON 数组，元素 type=key|interval|move"},{"name":"loop_count","type":"string","desc":"循环次数"},{"name":"forbid","type":"boolean","desc":"是否禁用"},{"name":"trigger_type","type":"integer","desc":"1按下 2松开 3松止 4开关 5长按 6双击"}]'))
            tools.Push(AiAssist._ToolDef("add_macro", "在指定页签新增一条宏并立即保存。", '[{"name":"tab","type":"integer","desc":"页签序号，默认当前页"},{"name":"trigger_key","type":"string","desc":"触发键"},{"name":"remark","type":"string","desc":"备注"},{"name":"macro","type":"string","desc":"指令串"},{"name":"commands","type":"string","desc":"JSON 指令数组"}]'))
        }
        if (AiAssist.CanWriteFile()) {
            scope := AiAssist.IsFullAccess() ? "路径不限" : "仅限若梦兔软件目录内"
            tools.Push(AiAssist._ToolDef("write_file", "写入文本文件。" scope "。", '[{"name":"path","type":"string","desc":"相对软件目录或绝对路径"},{"name":"content","type":"string","desc":"文件全文","req":true}]'))
            tools.Push(AiAssist._ToolDef("run_command", "执行系统命令并返回输出（cmd）。" scope "。", '[{"name":"command","type":"string","desc":"要执行的命令行"},{"name":"workdir","type":"string","desc":"工作目录，默认若梦兔软件目录"}]'))
            tools.Push(AiAssist._ToolDef("run_script", "运行脚本：.ahk / .ps1 / .bat / .cmd / .py。可给 path，或 content+lang。" scope "。", '[{"name":"path","type":"string","desc":"脚本文件路径"},{"name":"content","type":"string","desc":"脚本正文（无 path 时使用）"},{"name":"lang","type":"string","desc":"ahk/ps1/bat/py，与 content 配合"}]'))
        }
        out := ""
        for t in tools {
            if (out != "")
                out .= ","
            out .= t
        }
        return "[" out "]"
    }

    static _ToolDef(name, desc, propsJson) {
        props := ""
        required := ""
        try {
            arr := JSON.parse(propsJson)
            if (Type(arr) = "Array") {
                for p in arr {
                    if (Type(p) != "Map")
                        continue
                    n := String(p["name"])
                    typ := p.Has("type") ? String(p["type"]) : "string"
                    d := p.Has("desc") ? String(p["desc"]) : ""
                    if (props != "")
                        props .= ","
                    props .= '"' AiAssist._JsonEsc(n) '":{"type":"' typ '","description":"' AiAssist._JsonEsc(d) '"}'
                    need := false
                    if (p.Has("req"))
                        need := !!p["req"]
                    else if (n = "index" || n = "path" || n = "command")
                        need := true
                    if (need) {
                        if (required != "")
                            required .= ","
                        required .= '"' n '"'
                    }
                }
            }
        } catch {
        }
        req := (required != "") ? ',"required":[' required ']' : ""
        return '{"type":"function","function":{"name":"' name '","description":"' AiAssist._JsonEsc(desc) '","parameters":{"type":"object","properties":{' props '}' req '}}}'
    }

    static WorkspaceSnapshot(maxItems := 24) {
        global MySoftData, MainSoftData
        if (!IsSet(MySoftData) || !IsObject(MySoftData) || !MySoftData.HasProp("TableInfo"))
            return ""
        cur := 0
        try cur := Integer(MainSoftData.TableIndex)
        catch
            cur := 0
        lines := []
        lines.Push("当前页签：" cur)
        n := 0
        for tableItem in MySoftData.TableInfo {
            if (!IsObject(tableItem) || !CheckIsMacroTable(tableItem.Index))
                continue
            title := tableItem.Name != "" ? tableItem.Name : tableItem.Symbol
            i := 1
            for item in tableItem.Items {
                if (n >= maxItems) {
                    lines.Push("…其余宏已省略，用 list_macros 查看")
                    return AiAssist._JoinLines(lines)
                }
                mk := Trim(item.Macro)
                if (StrLen(mk) > 80)
                    mk := SubStr(mk, 1, 80) "…"
                lines.Push(Format("[{1}:{2}] 触发={3} 备注={4} 指令={5}", tableItem.Index, i, item.TK, item.Remark, mk))
                n++
                i++
            }
            if (tableItem.Items.Length < 1)
                lines.Push(Format("[{1}] {2}：空", tableItem.Index, title))
        }
        return AiAssist._JoinLines(lines)
    }

    static _JoinLines(lines) {
        out := ""
        for line in lines
            out .= (out = "" ? "" : "`n") line
        return out
    }

    static ReasoningOf(payload) {
        if (!IsObject(payload) || Type(payload) != "Map")
            return ""
        if (payload.Has("reasoning_content") && Trim(String(payload["reasoning_content"])) != "")
            return String(payload["reasoning_content"])
        if (payload.Has("reasoning") && Trim(String(payload["reasoning"])) != "")
            return String(payload["reasoning"])
        return ""
    }

    static ParseToolPayload(reply) {
        mark := "§TOOLS§"
        if (SubStr(reply, 1, StrLen(mark)) != mark)
            return ""
        raw := SubStr(reply, StrLen(mark) + 1)
        try {
            obj := JSON.parse(raw)
            if (Type(obj) = "Map")
                return obj
        } catch {
        }
        return ""
    }

    static ExecTool(name, argsJson) {
        args := Map()
        try {
            obj := JSON.parse(argsJson)
            if (Type(obj) = "Map")
                args := obj
        } catch {
        }
        try {
            switch name {
                case "list_macros":
                    return AiAssist._ToolListMacros()
                case "read_macro":
                    return AiAssist._ToolReadMacro(args)
                case "update_macro":
                    return AiAssist._ToolUpdateMacro(args)
                case "add_macro":
                    return AiAssist._ToolAddMacro(args)
                case "write_file":
                    return AiAssist._ToolWriteFile(args)
                case "read_file":
                    return AiAssist._ToolReadFile(args)
                case "list_dir":
                    return AiAssist._ToolListDir(args)
                case "run_command":
                    return AiAssist._ToolRunCommand(args)
                case "run_script":
                    return AiAssist._ToolRunScript(args)
                default:
                    return '{"ok":false,"error":"未知工具"}'
            }
        } catch as e {
            msg := IsObject(e) && e.HasProp("Message") ? e.Message : String(e)
            return '{"ok":false,"error":"' AiAssist._JsonEsc(msg) '"}'
        }
    }

    static _NeedApproval(action) {
        global MainSoftData
        if (Integer(MainSoftData.AiApprovalMode) != 1)
            return true
        return RmtDialog.Confirm(action, GetLang("AI 修改确认"))
    }

    static _ResolveTable(tab) {
        global MySoftData, MainSoftData
        tab := Integer(tab)
        if (tab < 1)
            tab := Integer(MainSoftData.TableIndex)
        if (tab < 1 || tab > MySoftData.TableInfo.Length)
            throw Error(GetLang("页签不存在"))
        tableItem := MySoftData.TableInfo[tab]
        if (!CheckIsMacroTable(tab))
            throw Error(GetLang("该页签不是宏表"))
        return tableItem
    }

    static _ToolListMacros() {
        snap := AiAssist.WorkspaceSnapshot(80)
        return '{"ok":true,"macros":"' AiAssist._JsonEsc(snap) '"}'
    }

    static _ToolReadMacro(args) {
        tableItem := AiAssist._ResolveTable(args.Has("tab") ? args["tab"] : 0)
        idx := Integer(args.Has("index") ? args["index"] : 0)
        if (idx < 1 || idx > tableItem.Items.Length)
            throw Error(GetLang("宏序号不存在"))
        item := tableItem.Items[idx]
        return '{"ok":true,"tab":' tableItem.Index ',"index":' idx
            . ',"trigger_key":"' AiAssist._JsonEsc(item.TK)
            . '","remark":"' AiAssist._JsonEsc(item.Remark)
            . '","macro":"' AiAssist._JsonEsc(item.Macro)
            . '","loop_count":"' AiAssist._JsonEsc(item.LoopCount)
            . '","forbid":' (item.Forbid ? "true" : "false")
            . ',"trigger_type":' Integer(item.TriggerType) '}'
    }

    static _MacroFromArgs(args) {
        if (args.Has("macro") && Trim(String(args["macro"])) != "")
            return Trim(String(args["macro"]))
        if (!args.Has("commands"))
            return ""
        raw := args["commands"]
        arr := ""
        if (Type(raw) = "Array")
            arr := raw
        else {
            try arr := JSON.parse(String(raw))
            catch
                arr := ""
        }
        if (Type(arr) != "Array")
            return ""
        parts := []
        for cmd in arr {
            if (Type(cmd) != "Map")
                continue
            typ := cmd.Has("type") ? String(cmd["type"]) : ""
            if (typ = "interval") {
                ms := cmd.Has("ms") ? Integer(cmd["ms"]) : 50
                parts.Push("间隔_" ms)
            } else if (typ = "key") {
                key := cmd.Has("key") ? String(cmd["key"]) : "a"
                act := cmd.Has("action") ? String(cmd["action"]) : "点击"
                dur := cmd.Has("duration") ? Integer(cmd["duration"]) : 100
                line := "按键_" key "_" act "_" dur
                if (cmd.Has("count"))
                    line .= "_" Integer(cmd["count"])
                if (cmd.Has("interval"))
                    line .= "_" Integer(cmd["interval"])
                parts.Push(line)
            } else if (typ = "move") {
                x := cmd.Has("x") ? String(cmd["x"]) : "0"
                y := cmd.Has("y") ? String(cmd["y"]) : "0"
                speed := cmd.Has("speed") ? Integer(cmd["speed"]) : 90
                mode := cmd.Has("mode") ? Integer(cmd["mode"]) : 0
                parts.Push("移动_" x "_" y "_" speed "_" mode)
            }
        }
        out := ""
        for p in parts
            out .= (out = "" ? "" : ",") p
        return out
    }

    static _RefreshMacroUi(tableItem, idx) {
        global MyMainWin
        HotReloadPublish(tableItem.Index, 0)
        if (!IsObject(MyMainWin))
            return
        try {
            if (MyMainWin.HasProp("_useVirtual") && MyMainWin._useVirtual.Has(tableItem.Index) && IsObject(MyMainWin._vl))
                MyMainWin._vl.RefreshRow(tableItem.Index, idx)
            else
                MyMainWin.RefreshItemRow(tableItem.Index, idx)
        }
        try MyMainWin.SelectSideTreeItem(tableItem.Index, idx)
        try MyMainWin.RefreshSideTree(tableItem.Index)
    }

    static _ToolUpdateMacro(args) {
        if (!AiAssist.CanWrite())
            throw Error(GetLang("当前为只读，无法修改"))
        tableItem := AiAssist._ResolveTable(args.Has("tab") ? args["tab"] : 0)
        idx := Integer(args.Has("index") ? args["index"] : 0)
        if (idx < 1 || idx > tableItem.Items.Length)
            throw Error(GetLang("宏序号不存在"))
        item := tableItem.Items[idx]
        desc := Format(GetLang("修改第 {1} 页第 {2} 条宏"), tableItem.Index, idx)
        if (!AiAssist._NeedApproval(desc))
            return '{"ok":false,"error":"用户拒绝审批"}'
        if (args.Has("trigger_key"))
            item.TK := String(args["trigger_key"])
        if (args.Has("remark"))
            item.Remark := String(args["remark"])
        mk := AiAssist._MacroFromArgs(args)
        if (mk != "")
            item.Macro := mk
        if (args.Has("loop_count"))
            item.LoopCount := String(args["loop_count"])
        if (args.Has("forbid"))
            item.Forbid := !!args["forbid"]
        if (args.Has("trigger_type"))
            item.TriggerType := Integer(args["trigger_type"])
        AiAssist._RefreshMacroUi(tableItem, idx)
        return '{"ok":true,"tab":' tableItem.Index ',"index":' idx
            . ',"trigger_key":"' AiAssist._JsonEsc(item.TK)
            . '","macro":"' AiAssist._JsonEsc(item.Macro) '"}'
    }

    static _ToolAddMacro(args) {
        global MyMainWin
        if (!AiAssist.CanWrite())
            throw Error(GetLang("当前为只读，无法修改"))
        tableItem := AiAssist._ResolveTable(args.Has("tab") ? args["tab"] : 0)
        if (!AiAssist._NeedApproval(Format(GetLang("在第 {1} 页新增宏"), tableItem.Index)))
            return '{"ok":false,"error":"用户拒绝审批"}'
        foldIndex := tableItem.Folds.Length >= 1 ? 1 : 0
        if (foldIndex >= 1)
            tableItem.Folds[foldIndex].FoldState := false
        item := MacroItem()
        item.FoldID := (foldIndex >= 1) ? tableItem.Folds[foldIndex].ID : ""
        item.ID := (item.FoldID != "") ? NewMacroPath(tableItem, item.FoldID) : GetCMDSerialStr("Item")
        item.TimingSerial := GetCMDSerialStr("Timing")
        if (args.Has("trigger_key"))
            item.TK := String(args["trigger_key"])
        if (args.Has("remark"))
            item.Remark := String(args["remark"])
        mk := AiAssist._MacroFromArgs(args)
        if (mk != "")
            item.Macro := mk
        AddIndex := GetFoldAddItemIndex(tableItem, foldIndex > 0 ? foldIndex : 1)
        tableItem.Items.InsertAt(AddIndex, item)
        tableItem.RebuildIndex()
        RebuildTableLocator()
        if (IsObject(MyMainWin))
            MyMainWin.RenderTab(tableItem)
        HotReloadPublish(tableItem.Index, 0)
        idx := GetItemIndexInTable(tableItem, item.ID)
        try MyMainWin.SelectSideTreeItem(tableItem.Index, idx)
        return '{"ok":true,"tab":' tableItem.Index ',"index":' idx
            . ',"trigger_key":"' AiAssist._JsonEsc(item.TK)
            . '","macro":"' AiAssist._JsonEsc(item.Macro) '"}'
    }

    static _NormPath(p) {
        p := Trim(StrReplace(String(p), "/", "\"))
        buf := Buffer(1040)
        n := DllCall("GetFullPathNameW", "Str", p, "UInt", 520, "Ptr", buf, "Ptr", 0)
        if (n)
            p := StrGet(buf, "UTF-16")
        return RTrim(p, "\")
    }

    static _WorkspaceRoot() {
        return AiAssist._NormPath(A_WorkingDir)
    }

    static _IsUnderWorkspace(full) {
        root := AiAssist._WorkspaceRoot()
        n := StrLower(AiAssist._NormPath(full))
        root := StrLower(root)
        return (n = root || SubStr(n, 1, StrLen(root) + 1) = root "\")
    }

    static WorkspaceDeniedMsg(path := "") {
        root := AiAssist._WorkspaceRoot()
        msg := Format(GetLang("写入失败：当前写入权限为「工作区」，只能写入若梦兔软件目录（{1}）。目标不在工作区内。请到「AI 设置 → 写入权限」改为「完全访问」后再试。"), root)
        if (Trim(path) != "")
            msg .= "`n" GetLang("目标路径：") path
        return msg
    }

    static _CommandTargetsOutside(cmd) {
        if (AiAssist._LooksOutsideWorkspace(cmd))
            return true
        for script in AiAssist._CmdReferencedScripts(cmd) {
            if (AiAssist._ScriptFileTargetsOutside(script))
                return true
        }
        return false
    }

    ; 工作区：命令/脚本里只要指向桌面、用户目录或软件目录外的绝对路径，一律拦截
    static _LooksOutsideWorkspace(text) {
        s := String(text)
        if (s == "")
            return false
        sl := StrLower(StrReplace(s, "/", "\"))
        if (InStr(sl, "\desktop") || InStr(s, "桌面")
            || InStr(sl, "\downloads") || InStr(sl, "\documents")
            || InStr(sl, "\下载") || InStr(sl, "\文档"))
            return true
        if (RegExMatch(s, "i)%USERPROFILE%|%HOMEPATH%|expanduser|Path.home|A_Desktop|A_MyDocuments")
            || InStr(s, "$env:USERPROFILE"))
            return true
        for p in AiAssist._ExtractAbsPaths(s) {
            if (!AiAssist._IsUnderWorkspace(p))
                return true
        }
        return false
    }

    static _ExtractAbsPaths(text) {
        paths := []
        s := String(text)
        pos := 1
        len := StrLen(s)
        while (pos <= len) {
            ch := SubStr(s, pos, 1)
            if ((ch = Chr(34) || ch = "'") && pos < len) {
                close := InStr(s, ch, false, pos + 1)
                if (!close)
                    break
                inner := Trim(SubStr(s, pos + 1, close - pos - 1))
                if (AiAssist._LooksAbsPath(inner))
                    paths.Push(inner)
                pos := close + 1
                continue
            }
            if (RegExMatch(SubStr(s, pos), "i)^([A-Za-z]:[/\\][^ \t<>|]+)", &m)) {
                p := RTrim(m[1], ".,;)+")
                if (AiAssist._LooksAbsPath(p))
                    paths.Push(p)
                pos += StrLen(m[1])
                continue
            }
            pos++
        }
        return paths
    }

    static _LooksAbsPath(p) {
        p := Trim(p)
        return (RegExMatch(p, "i)^[A-Za-z]:[/\\]") || SubStr(p, 1, 2) = "\\")
    }

    static _CmdReferencedScripts(cmd) {
        files := []
        s := String(cmd)
        pos := 1
        while (RegExMatch(s, "i)([^ \t]+?\.(py|ps1|ahk|bat|cmd))", &m, pos)) {
            p := Trim(m[1], Chr(34) "'")
            if (p != "")
                files.Push(p)
            pos := m.Pos + m.Len
            if (pos < 1)
                break
        }
        return files
    }

    static _ScriptFileTargetsOutside(rawPath) {
        p := Trim(String(rawPath))
        if (p == "")
            return false
        full := ""
        try full := AiAssist._ResolveUserPath(p, true)
        catch
            return AiAssist._LooksOutsideWorkspace(p)
        if (full == "" || !FileExist(full) || DirExist(full))
            return false
        body := ""
        try body := FileRead(full, "UTF-8")
        catch {
            try body := FileRead(full)
        }
        return (body != "" && AiAssist._LooksOutsideWorkspace(body))
    }

    static _ResolveUserPath(raw, allowOutside := false) {
        p := Trim(StrReplace(String(raw), "/", "\"))
        if (p == "")
            throw Error(GetLang("路径不能为空"))
        if (RegExMatch(p, "^[A-Za-z]:\\") || SubStr(p, 1, 2) = "\\")
            full := AiAssist._NormPath(p)
        else
            full := AiAssist._NormPath(A_WorkingDir "\" p)
        if (!allowOutside && !AiAssist._IsUnderWorkspace(full))
            throw Error(AiAssist.WorkspaceDeniedMsg(full))
        return full
    }

    static _ToolWriteFile(args) {
        if (!AiAssist.CanWriteFile())
            throw Error(GetLang("当前权限不能写文件"))
        full := AiAssist._ResolveUserPath(args.Has("path") ? args["path"] : "", AiAssist.IsFullAccess())
        if (!AiAssist._NeedApproval(GetLang("写入文件") "：`n" full))
            return '{"ok":false,"error":"用户拒绝审批"}'
        dir := ""
        SplitPath(full, , &dir)
        if (dir != "" && !DirExist(dir))
            DirCreate(dir)
        f := FileOpen(full, "w", "UTF-8")
        f.Write(String(args.Has("content") ? args["content"] : ""))
        f.Close()
        return '{"ok":true,"path":"' AiAssist._JsonEsc(full) '"}'
    }

    static _ToolReadFile(args) {
        if (!AiAssist.CanReadFile())
            throw Error(GetLang("当前权限不能读文件"))
        full := AiAssist._ResolveUserPath(args.Has("path") ? args["path"] : "", true)
        if (!FileExist(full))
            throw Error(GetLang("文件不存在") "：" full)
        maxChars := 20000
        if (args.Has("max_chars") && Integer(args["max_chars"]) > 0)
            maxChars := Integer(args["max_chars"])
        if (maxChars > 80000)
            maxChars := 80000
        raw := ""
        try raw := FileRead(full, "UTF-8")
        catch {
            raw := FileRead(full)
        }
        truncated := false
        if (StrLen(raw) > maxChars) {
            raw := SubStr(raw, 1, maxChars)
            truncated := true
        }
        return '{"ok":true,"path":"' AiAssist._JsonEsc(full) '","truncated":' (truncated ? "true" : "false")
            . ',"content":"' AiAssist._JsonEsc(raw) '"}'
    }

    static _ToolListDir(args) {
        if (!AiAssist.CanReadFile())
            throw Error(GetLang("当前权限不能读文件"))
        raw := args.Has("path") ? String(args["path"]) : ""
        full := (Trim(raw) == "") ? A_WorkingDir : AiAssist._ResolveUserPath(raw, true)
        if (!DirExist(full))
            throw Error(GetLang("目录不存在") "：" full)
        names := []
        loop files full "\*", "FD" {
            if (names.Length >= 80)
                break
            mark := InStr(A_LoopFileAttrib, "D") ? "/" : ""
            names.Push(A_LoopFileName mark)
        }
        list := ""
        for n in names
            list .= (list == "" ? "" : ", ") n
        return '{"ok":true,"path":"' AiAssist._JsonEsc(full) '","entries":"' AiAssist._JsonEsc(list) '"}'
    }

    static _ToolRunCommand(args) {
        if (!AiAssist.CanRun())
            throw Error(GetLang("当前权限不能执行命令"))
        cmd := Trim(String(args.Has("command") ? args["command"] : ""))
        if (cmd == "")
            throw Error(GetLang("命令不能为空"))
        work := Trim(String(args.Has("workdir") ? args["workdir"] : ""))
        if (work == "")
            work := AiAssist._WorkspaceRoot()
        else
            work := AiAssist._ResolveUserPath(work, AiAssist.IsFullAccess())
        if (!AiAssist.IsFullAccess() && AiAssist._CommandTargetsOutside(cmd))
            throw Error(AiAssist.WorkspaceDeniedMsg(cmd))
        if (!AiAssist._NeedApproval(GetLang("执行命令") "：`n" cmd))
            return '{"ok":false,"error":"用户拒绝审批"}'
        return AiAssist._RunCaptured(cmd, work)
    }

    static _ToolRunScript(args) {
        if (!AiAssist.CanRun())
            throw Error(GetLang("当前权限不能执行脚本"))
        path := Trim(String(args.Has("path") ? args["path"] : ""))
        content := String(args.Has("content") ? args["content"] : "")
        lang := StrLower(Trim(String(args.Has("lang") ? args["lang"] : "")))
        tmp := ""
        if (path != "") {
            path := AiAssist._ResolveUserPath(path, AiAssist.IsFullAccess())
            if (!AiAssist.IsFullAccess() && AiAssist._ScriptFileTargetsOutside(path))
                throw Error(AiAssist.WorkspaceDeniedMsg(path))
        } else {
            if (content == "")
                throw Error(GetLang("请提供脚本路径或正文"))
            if (lang == "")
                lang := "ahk"
            dir := AiAssist.IsFullAccess() ? (A_Temp "\RMT\AiScript") : (AiAssist._WorkspaceRoot() "\Log\AiScript")
            if (!DirExist(dir))
                DirCreate(dir)
            ext := lang
            if (ext = "powershell")
                ext := "ps1"
            else if (ext = "cmd" || ext = "bat")
                ext := "bat"
            else if (ext = "python")
                ext := "py"
            else if (ext = "autohotkey")
                ext := "ahk"
            if (!AiAssist.IsFullAccess() && AiAssist._LooksOutsideWorkspace(content))
                throw Error(AiAssist.WorkspaceDeniedMsg())
            tmp := dir "\" FormatTime(A_Now, "yyyyMMddHHmmss") "_" Random(100, 999) "." ext
            f := FileOpen(tmp, "w", "UTF-8")
            f.Write(content)
            f.Close()
            path := tmp
        }
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        desc := GetLang("运行脚本") "：`n" path
        if (!AiAssist._NeedApproval(desc))
            return '{"ok":false,"error":"用户拒绝审批"}'
        line := ""
        if (ext = "ahk")
            line := '"' A_AhkPath '" "' path '"'
        else if (ext = "ps1")
            line := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' path '"'
        else if (ext = "bat" || ext = "cmd")
            line := '"' path '"'
        else if (ext = "py")
            line := 'python "' path '"'
        else
            line := '"' path '"'
        return AiAssist._RunCaptured(line, AiAssist._WorkspaceRoot())
    }

    static _RunCaptured(line, workdir) {
        workdir := AiAssist._NormPath(workdir)
        if (!AiAssist.IsFullAccess() && !AiAssist._IsUnderWorkspace(workdir))
            throw Error(AiAssist.WorkspaceDeniedMsg(workdir))
        outFile := A_Temp "\RMT\ai_cmd_out.txt"
        errFile := A_Temp "\RMT\ai_cmd_err.txt"
        dir := A_Temp "\RMT"
        if (!DirExist(dir))
            DirCreate(dir)
        try FileDelete(outFile)
        try FileDelete(errFile)
        exitCode := 0
        try exitCode := RunWait(A_ComSpec ' /c ' line ' > "' outFile '" 2> "' errFile '"', workdir, "Hide")
        catch as e
            throw Error(IsObject(e) && e.HasProp("Message") ? e.Message : String(e))
        out := ""
        err := ""
        try out := FileRead(outFile, "UTF-8")
        catch {
            try out := FileRead(outFile)
        }
        try err := FileRead(errFile, "UTF-8")
        catch {
        }
        if (StrLen(out) > 12000)
            out := SubStr(out, 1, 12000) "`n…(已截断)"
        if (StrLen(err) > 4000)
            err := SubStr(err, 1, 4000) "`n…(已截断)"
        return '{"ok":true,"exit_code":' Integer(exitCode)
            . ',"stdout":"' AiAssist._JsonEsc(out) '","stderr":"' AiAssist._JsonEsc(err) '"}'
    }

    ; 读取 Plugins\RMTMcps\README.md 中 RMT_AI_PROMPT 标记段。
    ; 工具清单只维护在 README，重编 RMTMcps.exe 后改文档即可，不必改本脚本。
    ; 按文件修改时间失效缓存，改 README 后下次对话自动生效。
    static LoadMcpToolsPrompt() {
        static cached := ""
        static cachedMtime := ""
        path := A_ScriptDir "\Plugins\RMTMcps\README.md"
        if (!FileExist(path))
            return ""
        mtime := ""
        try mtime := FileGetTime(path, "M")
        if (mtime != "" && mtime = cachedMtime && cached != "")
            return cached
        try
            text := FileRead(path, "UTF-8")
        catch {
            return cached
        }
        beginTag := "<!-- RMT_AI_PROMPT_BEGIN -->"
        endTag := "<!-- RMT_AI_PROMPT_END -->"
        b := InStr(text, beginTag)
        e := InStr(text, endTag)
        if (b > 0 && e > b) {
            start := b + StrLen(beginTag)
            text := Trim(SubStr(text, start, e - start), " `t`r`n")
        } else {
            maxChars := 8000
            if (StrLen(text) > maxChars)
                text := SubStr(text, 1, maxChars) "`n…(README.md 已截断)"
        }
        cached := text
        cachedMtime := mtime
        return cached
    }

    static _BuildMessagesJson(messages) {
        msgParts := ""
        for m in messages {
            if (Type(m) = "Map" && m.Has("raw") && m["raw"] != "") {
                if (msgParts != "")
                    msgParts .= ","
                msgParts .= m["raw"]
                continue
            }
            role := (Type(m) = "Map" && m.Has("role")) ? String(m["role"]) : "user"
            content := (Type(m) = "Map" && m.Has("content")) ? String(m["content"]) : ""
            extra := ""
            if (Type(m) = "Map" && m.Has("tool_call_id") && m["tool_call_id"] != "")
                extra .= ',"tool_call_id":"' AiAssist._JsonEsc(m["tool_call_id"]) '"'
            if (Type(m) = "Map" && m.Has("tool_calls") && m["tool_calls"] != "")
                extra .= ',"tool_calls":' m["tool_calls"]
            if (Type(m) = "Map" && m.Has("reasoning_content") && m["reasoning_content"] != "")
                extra .= ',"reasoning_content":"' AiAssist._JsonEsc(m["reasoning_content"]) '"'
            else if (Type(m) = "Map" && m.Has("reasoning") && m["reasoning"] != "")
                extra .= ',"reasoning_content":"' AiAssist._JsonEsc(m["reasoning"]) '"'
            if (msgParts != "")
                msgParts .= ","
            msgParts .= '{"role":"' AiAssist._JsonEsc(role) '","content":"' AiAssist._JsonEsc(content) '"' extra '}'
        }
        return "[" msgParts "]"
    }

    static _JsonEsc(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, "`r`n", "\n")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\n")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, '"', '\"')
        return s
    }

    ; 解析 C# 返回的 ["a","b"] 或 AHK JSON.parse 数组
    static _ParseJsonStringArray(json) {
        ids := []
        try {
            obj := JSON.parse(json)
            if (Type(obj) = "Array") {
                for item in obj {
                    if (item != "")
                        ids.Push(String(item))
                }
                return ids
            }
        } catch {
        }
        pos := 1
        while (RegExMatch(json, '"((?:\\.|[^"\\])*)"', &m, pos)) {
            ids.Push(StrReplace(m[1], '\"', '"'))
            pos := m.Pos + m.Len
        }
        return ids
    }
}

; =====================================================================
; AI 对话会话持久化（对话记录）
; 文件：Setting\AiChatHistory.json
; =====================================================================
class AiChatStore {
    static MaxSessions := 50
    static MaxTitleLen := 40

    static FilePath() {
        dir := A_WorkingDir "\Setting"
        if (dir == "\Setting" || dir == "")
            dir := A_ScriptDir "\Setting"
        if (!DirExist(dir))
            DirCreate(dir)
        return dir "\AiChatHistory.json"
    }

    static LoadAll() {
        path := AiChatStore.FilePath()
        if (!FileExist(path))
            return []
        try {
            raw := FileRead(path, "UTF-8")
            obj := JSON.parse(raw)
            if (Type(obj) = "Map" && obj.Has("sessions") && Type(obj["sessions"]) = "Array")
                return obj["sessions"]
            if (Type(obj) = "Object" && obj.HasOwnProp("sessions") && Type(obj.sessions) = "Array")
                return obj.sessions
            if (Type(obj) = "Array")
                return obj
        } catch {
        }
        return []
    }

    static SaveAll(sessions) {
        if (Type(sessions) != "Array")
            sessions := []
        ; 按 updated 降序，截断数量
        AiChatStore._SortByUpdated(sessions)
        while (sessions.Length > AiChatStore.MaxSessions)
            sessions.Pop()
        path := AiChatStore.FilePath()
        tmp := path ".tmp"
        try {
            payload := Map("sessions", sessions)
            raw := JSON.stringify(payload, 0)
            f := FileOpen(tmp, "w", "UTF-8")
            f.Write(raw)
            f.Close()
            if (FileExist(path))
                FileDelete(path)
            FileMove(tmp, path)
        } catch {
            try {
                if (FileExist(tmp))
                    FileDelete(tmp)
            }
        }
    }

    static List() {
        return AiChatStore.LoadAll()
    }

    static Get(id) {
        id := String(id)
        if (id == "")
            return ""
        for s in AiChatStore.LoadAll() {
            if (Type(s) = "Map" && String(s.Has("id") ? s["id"] : "") = id)
                return s
        }
        return ""
    }

    static Delete(id) {
        id := String(id)
        if (id == "")
            return false
        sessions := AiChatStore.LoadAll()
        out := []
        found := false
        for s in sessions {
            sid := (Type(s) = "Map" && s.Has("id")) ? String(s["id"]) : ""
            if (sid = id) {
                found := true
                continue
            }
            out.Push(s)
        }
        if (found)
            AiChatStore.SaveAll(out)
        return found
    }

    ; 有消息才写入；返回 session id
    static Upsert(id, messages) {
        msgs := AiChatStore._NormalizeMessages(messages)
        if (msgs.Length < 1)
            return String(id)
        sessions := AiChatStore.LoadAll()
        title := AiChatStore._TitleFromMessages(msgs)
        updated := A_Now
        id := Trim(String(id))
        if (id == "")
            id := AiChatStore._NewId()
        found := false
        for i, s in sessions {
            if (Type(s) != "Map" || !s.Has("id") || String(s["id"]) != id)
                continue
            s["title"] := title
            s["updated"] := updated
            s["messages"] := msgs
            sessions[i] := s
            found := true
            break
        }
        if (!found)
            sessions.InsertAt(1, Map("id", id, "title", title, "updated", updated, "messages", msgs))
        AiChatStore.SaveAll(sessions)
        return id
    }

    static FormatUpdated(updated) {
        u := String(updated)
        if (StrLen(u) >= 14) {
            try
                return FormatTime(u, "yyyy-MM-dd HH:mm")
            catch {
            }
        }
        return u
    }

    static _NewId() {
        return FormatTime(A_Now, "yyyyMMddHHmmss") "_" Random(1000, 9999)
    }

    static _TitleFromMessages(msgs) {
        for m in msgs {
            if (Type(m) != "Map")
                continue
            role := m.Has("role") ? String(m["role"]) : ""
            if (role != "user")
                continue
            t := String(m.Has("content") ? m["content"] : "")
            t := RegExReplace(t, "\[([^\]]+)\]\(rmtfile:[^)]+\)", "$1")
            t := Trim(RegExReplace(t, "[\r\n\t]+", " "))
            if (t == "")
                continue
            if (StrLen(t) > AiChatStore.MaxTitleLen)
                return SubStr(t, 1, AiChatStore.MaxTitleLen) "…"
            return t
        }
        return GetLang("未命名对话")
    }

    static _NormalizeMessages(messages) {
        out := []
        if (Type(messages) != "Array")
            return out
        for m in messages {
            if (Type(m) != "Map")
                continue
            role := m.Has("role") ? String(m["role"]) : "user"
            content := m.Has("content") ? String(m["content"]) : ""
            ; 用户/助手只要有正文就保留；tool 结果一并落盘，便于完整回放
            if (role = "system")
                continue
            if (Trim(content) == "" && !m.Has("tool_calls") && !m.Has("reasoning_content") && !m.Has("reasoning"))
                continue
            rec := Map("role", role, "content", content)
            if (m.Has("tool_calls"))
                rec["tool_calls"] := String(m["tool_calls"])
            if (m.Has("tool_call_id"))
                rec["tool_call_id"] := String(m["tool_call_id"])
            if (m.Has("reasoning_content") && m["reasoning_content"] != "")
                rec["reasoning_content"] := String(m["reasoning_content"])
            else if (m.Has("reasoning") && m["reasoning"] != "")
                rec["reasoning_content"] := String(m["reasoning"])
            out.Push(rec)
        }
        return out
    }

    static _SortByUpdated(sessions) {
        ; 简单插入排序（会话数少）
        n := sessions.Length
        i := 2
        while (i <= n) {
            cur := sessions[i]
            curU := AiChatStore._UpdatedKey(cur)
            j := i - 1
            while (j >= 1 && AiChatStore._UpdatedKey(sessions[j]) < curU) {
                sessions[j + 1] := sessions[j]
                j--
            }
            sessions[j + 1] := cur
            i++
        }
    }

    static _UpdatedKey(s) {
        if (Type(s) != "Map" || !s.Has("updated"))
            return ""
        return String(s["updated"])
    }
}
