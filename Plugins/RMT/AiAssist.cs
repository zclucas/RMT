using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace RMT
{
    /// <summary>
    /// AI 助手 OpenAI 兼容 HTTP（models / chat/completions）。
    /// 由 AHK 经 CLR 调用：CreateInstance("RMT.AiAssist")。
    /// </summary>
    public class AiAssist
    {
        private static readonly HttpClient Client;
        private readonly object _chatLock = new object();
        private int _chatState;      // 0=idle 1=running 2=ready 3=error
        private string _chatResult = "";
        private string _chatError = "";
        private string _chatPartial = "";
        private int _chatSeq;
        private CancellationTokenSource _chatCts;

        static AiAssist()
        {
            try
            {
                // 兼容旧系统默认协议过低导致 HTTPS 失败
                System.Net.ServicePointManager.SecurityProtocol |=
                    (System.Net.SecurityProtocolType)3072; // Tls12
            }
            catch { }

            Client = new HttpClient();
            Client.Timeout = TimeSpan.FromSeconds(120);
        }

        /// <summary>
        /// GET {baseUrl}/models，返回 JSON 数组字符串：["model-a","model-b"]
        /// 失败时抛出 Exception（AHK catch 可读 Message）。
        /// </summary>
        public string GetModels(string baseUrl, string apiKey)
        {
            baseUrl = NormalizeBaseUrl(baseUrl);
            if (string.IsNullOrEmpty(baseUrl) || string.IsNullOrEmpty(apiKey))
                throw new Exception("请先填写 API Key 与 API URL");

            string body = Request("GET", baseUrl + "/models", apiKey, null);
            string idsJson = ParseModelIdsJson(body);
            if (idsJson == "[]")
                throw new Exception("未解析到可用模型，请检查 API URL 是否指向 OpenAI 兼容接口");
            return idsJson;
        }

        /// <summary>
        /// POST {baseUrl}/chat/completions。
        /// messagesJson 形如 [{"role":"user","content":"..."},...]
        /// 返回助手 content 文本。
        /// </summary>
        public string ChatCompletion(string baseUrl, string apiKey, string model, string messagesJson)
        {
            return ChatCompletion(baseUrl, apiKey, model, messagesJson, 0.4);
        }

        public string ChatCompletion(string baseUrl, string apiKey, string model, string messagesJson, double temperature)
        {
            return ChatCompletion(baseUrl, apiKey, model, messagesJson, temperature, "");
        }

        public string ChatCompletion(string baseUrl, string apiKey, string model, string messagesJson, double temperature, string toolsJson)
        {
            baseUrl = NormalizeBaseUrl(baseUrl);
            if (string.IsNullOrEmpty(baseUrl) || string.IsNullOrEmpty(apiKey) || string.IsNullOrEmpty(model))
                throw new Exception("请先在 AI 设置中填写 API Key、API URL 与模型");
            if (string.IsNullOrEmpty(messagesJson))
                throw new Exception("messages 不能为空");

            string payload = "{\"model\":\"" + JsonEsc(model)
                + "\",\"messages\":" + messagesJson
                + ",\"temperature\":" + temperature.ToString(System.Globalization.CultureInfo.InvariantCulture);
            if (!string.IsNullOrEmpty(toolsJson))
                payload += ",\"tools\":" + toolsJson + ",\"tool_choice\":\"auto\"";
            payload += "}";

            string body = Request("POST", baseUrl + "/chat/completions", apiKey, payload);
            return ParseChatResult(body);
        }

        private string ChatCompletionStream(string baseUrl, string apiKey, string model, string messagesJson, double temperature, string toolsJson, int seq, CancellationToken token)
        {
            baseUrl = NormalizeBaseUrl(baseUrl);
            if (string.IsNullOrEmpty(baseUrl) || string.IsNullOrEmpty(apiKey) || string.IsNullOrEmpty(model))
                throw new Exception("请先在 AI 设置中填写 API Key、API URL 与模型");
            if (string.IsNullOrEmpty(messagesJson))
                throw new Exception("messages 不能为空");

            string payload = "{\"model\":\"" + JsonEsc(model)
                + "\",\"messages\":" + messagesJson
                + ",\"temperature\":" + temperature.ToString(System.Globalization.CultureInfo.InvariantCulture)
                + ",\"stream\":true";
            if (!string.IsNullOrEmpty(toolsJson))
                payload += ",\"tools\":" + toolsJson + ",\"tool_choice\":\"auto\"";
            payload += "}";

            try
            {
                using (var req = new HttpRequestMessage(HttpMethod.Post, baseUrl + "/chat/completions"))
                {
                    req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey ?? "");
                    try { req.Headers.Accept.ParseAdd("text/event-stream"); } catch { }
                    req.Content = new StringContent(payload, Encoding.UTF8, "application/json");

                    HttpResponseMessage resp = Client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, token)
                        .ConfigureAwait(false).GetAwaiter().GetResult();
                    int code = (int)resp.StatusCode;
                    if (code < 200 || code >= 300)
                    {
                        string errText = "";
                        try { errText = resp.Content.ReadAsStringAsync().ConfigureAwait(false).GetAwaiter().GetResult() ?? ""; } catch { }
                        if (code == 400 || code == 404 || code == 422)
                            return ChatCompletion(baseUrl, apiKey, model, messagesJson, temperature, toolsJson);
                        string snippet = errText.Replace("\r", " ").Replace("\n", " ").Trim();
                        if (snippet.Length > 180)
                            snippet = snippet.Substring(0, 180);
                        throw new Exception("API 请求失败 HTTP " + code + (snippet.Length > 0 ? "\n" + snippet : ""));
                    }

                    using (Stream stream = resp.Content.ReadAsStreamAsync().ConfigureAwait(false).GetAwaiter().GetResult())
                    using (var reader = new StreamReader(stream, Encoding.UTF8))
                    {
                        var content = new StringBuilder();
                        var reasoning = new StringBuilder();
                        var tools = new Dictionary<int, ToolAcc>();
                        string line;
                        while ((line = reader.ReadLine()) != null)
                        {
                            token.ThrowIfCancellationRequested();
                            if (CurrentSeq() != seq)
                                break;
                            line = (line ?? "").Trim();
                            if (line.Length == 0)
                                continue;
                            if (line.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
                                line = line.Substring(5).Trim();
                            if (line == "[DONE]")
                                break;
                            if (!line.StartsWith("{"))
                                continue;
                            if (line.IndexOf("\"chat.completion.chunk\"") < 0
                                && line.IndexOf("\"message\"") >= 0
                                && line.IndexOf("\"choices\"") >= 0)
                            {
                                string full = ParseChatResult(line);
                                PublishPartial(seq, ParseChatContent(line));
                                return full;
                            }
                            ApplyStreamChunk(line, content, reasoning, tools, seq);
                        }
                        return BuildStreamResult(content, reasoning, tools);
                    }
                }
            }
            catch (Exception ex)
            {
                if (ex.Message != null && ex.Message.StartsWith("API 请求失败"))
                    throw;
                if (ex is AggregateException)
                {
                    AggregateException ae = (AggregateException)ex;
                    if (ae.InnerException != null)
                        throw new Exception(ae.InnerException.Message, ae.InnerException);
                }
                throw new Exception(ex.Message, ex);
            }
        }

        private int CurrentSeq()
        {
            lock (_chatLock)
                return _chatSeq;
        }

        private void PublishPartial(int seq, string text)
        {
            lock (_chatLock)
            {
                if (seq == _chatSeq)
                    _chatPartial = text ?? "";
            }
        }

        private void ApplyStreamChunk(string json, StringBuilder content, StringBuilder reasoning, Dictionary<int, ToolAcc> tools, int seq)
        {
            int deltaAt = json.IndexOf("\"delta\"");
            if (deltaAt < 0)
                return;
            string after = json.Substring(deltaAt);
            Match cm = Regex.Match(after, "\"content\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (cm.Success)
            {
                string piece = UnescapeJsonString(cm.Groups[1].Value);
                if (piece.Length > 0)
                {
                    content.Append(piece);
                    PublishPartial(seq, content.ToString());
                }
            }
            if (!AppendDeltaString(after, "reasoning_content", reasoning)
                && !AppendDeltaString(after, "reasoning", reasoning))
                AppendDeltaString(after, "thinking", reasoning);
            AccToolDelta(tools, after);
        }

        private static bool AppendDeltaString(string json, string key, StringBuilder dest)
        {
            if (dest == null || string.IsNullOrEmpty(json) || string.IsNullOrEmpty(key))
                return false;
            Match m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (!m.Success)
                return false;
            string piece = UnescapeJsonString(m.Groups[1].Value);
            if (piece.Length > 0)
                dest.Append(piece);
            return true;
        }

        private static void AccToolDelta(Dictionary<int, ToolAcc> map, string json)
        {
            int tc = json.IndexOf("\"tool_calls\"");
            if (tc < 0)
                return;
            string part = json.Substring(tc);
            Match idxM = Regex.Match(part, "\"index\"\\s*:\\s*(\\d+)");
            int idx = idxM.Success ? int.Parse(idxM.Groups[1].Value) : map.Count;
            ToolAcc acc;
            if (!map.TryGetValue(idx, out acc))
            {
                acc = new ToolAcc();
                map[idx] = acc;
            }
            string id = ExtractJsonString(part, "id");
            string name = ExtractJsonString(part, "name");
            string args = ExtractJsonString(part, "arguments");
            if (!string.IsNullOrEmpty(id))
                acc.Id = id;
            if (!string.IsNullOrEmpty(name))
                acc.Name = name;
            if (args != null)
                acc.Args.Append(args);
        }

        private static string BuildStreamResult(StringBuilder content, StringBuilder reasoning, Dictionary<int, ToolAcc> tools)
        {
            string text = content != null ? content.ToString() : "";
            string think = reasoning != null ? reasoning.ToString() : "";
            string callsJson = "";
            if (tools != null && tools.Count > 0)
            {
                var calls = new StringBuilder();
                List<int> keys = new List<int>(tools.Keys);
                keys.Sort();
                foreach (int k in keys)
                {
                    ToolAcc acc = tools[k];
                    if (calls.Length > 0)
                        calls.Append(',');
                    string id = string.IsNullOrEmpty(acc.Id) ? ("call_" + k) : acc.Id;
                    calls.Append("{\"id\":\"").Append(JsonEsc(id))
                        .Append("\",\"name\":\"").Append(JsonEsc(acc.Name ?? ""))
                        .Append("\",\"arguments\":\"").Append(JsonEsc(acc.Args != null ? acc.Args.ToString() : ""))
                        .Append("\"}");
                }
                callsJson = calls.ToString();
            }
            return WrapChatPayload(text, think, callsJson);
        }

        private static string WrapChatPayload(string content, string reasoning, string callsJson)
        {
            bool hasCalls = !string.IsNullOrEmpty(callsJson);
            bool hasReason = !string.IsNullOrEmpty(reasoning);
            if (!hasCalls && !hasReason)
            {
                if (string.IsNullOrEmpty(content))
                    throw new Exception("无法解析模型回复，请检查接口是否兼容 OpenAI Chat Completions");
                return content;
            }
            return "§TOOLS§{\"content\":\"" + JsonEsc(content ?? "")
                + "\",\"reasoning_content\":\"" + JsonEsc(reasoning ?? "")
                + "\",\"calls\":[" + (callsJson ?? "") + "]}";
        }

        private static string ExtractJsonString(string json, string key)
        {
            if (string.IsNullOrEmpty(json) || string.IsNullOrEmpty(key))
                return null;
            Match m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (!m.Success)
                return null;
            return UnescapeJsonString(m.Groups[1].Value);
        }

        private class ToolAcc
        {
            public string Id = "";
            public string Name = "";
            public StringBuilder Args = new StringBuilder();
        }

        /// <summary>
        /// 异步发起对话。AHK 经 COM 只能看到一个签名，必须固定 5 个参数（toolsJson 可空串）。
        /// </summary>
        public void BeginChatCompletion(string baseUrl, string apiKey, string model, string messagesJson, string toolsJson)
        {
            int seq;
            lock (_chatLock)
            {
                // 始终开新请求：递增 seq 使旧 Task 结果被丢弃，避免 state==1 时静默 return 导致无回复
                _chatState = 1;
                _chatResult = "";
                _chatError = "";
                _chatPartial = "";
                _chatSeq++;
                seq = _chatSeq;
            }

            string b = baseUrl;
            string k = apiKey;
            string m = model;
            string j = messagesJson;
            string t = toolsJson ?? "";
            double temp = 0.4;
            CancellationTokenSource cts;
            lock (_chatLock)
            {
                if (_chatCts != null)
                {
                    try { _chatCts.Cancel(); } catch { }
                }
                _chatCts = new CancellationTokenSource();
                cts = _chatCts;
            }
            CancellationToken token = cts.Token;
            Task.Run(() =>
            {
                try
                {
                    string r = ChatCompletionStream(b, k, m, j, temp, t, seq, token);
                    lock (_chatLock)
                    {
                        if (seq != _chatSeq)
                            return;
                        _chatResult = r ?? "";
                        _chatState = 2;
                    }
                }
                catch (Exception ex)
                {
                    if (token.IsCancellationRequested || ex is OperationCanceledException || ex is TaskCanceledException)
                    {
                        lock (_chatLock)
                        {
                            if (seq != _chatSeq)
                                return;
                            _chatState = 0;
                            _chatResult = "";
                            _chatError = "";
                        }
                        return;
                    }
                    lock (_chatLock)
                    {
                        if (seq != _chatSeq)
                            return;
                        _chatError = ex.Message ?? "请求失败";
                        _chatState = 3;
                    }
                }
            });
        }

        /// <summary>取消进行中的对话请求。休眠/暂停/终止宏不要调用这个。</summary>
        public void CancelChat()
        {
            lock (_chatLock)
            {
                _chatSeq++;
                _chatState = 0;
                _chatResult = "";
                _chatError = "";
                _chatPartial = "";
                if (_chatCts != null)
                {
                    try { _chatCts.Cancel(); } catch { }
                }
            }
        }

        /// <summary>0=空闲 1=进行中 2=成功 3=失败</summary>
        public int GetChatState()
        {
            lock (_chatLock)
                return _chatState;
        }

        /// <summary>取走结果并回到 idle。失败时抛出含 API 信息的异常。</summary>
        public string TakeChatResult()
        {
            lock (_chatLock)
            {
                int st = _chatState;
                string r = _chatResult ?? "";
                string err = _chatError ?? "请求失败";
                _chatState = 0;
                _chatResult = "";
                _chatError = "";
                _chatPartial = "";
                if (st == 3)
                    throw new Exception(err);
                return r;
            }
        }

        /// <summary>流式生成中已收到的正文（不含工具标记）。AHK 轮询刷新气泡。</summary>
        public string PeekChatPartial()
        {
            lock (_chatLock)
                return _chatPartial ?? "";
        }

        /// <summary>
        /// 通用请求：返回响应正文；非 2xx 抛出含状态码与片段的异常。
        /// </summary>
        public string Request(string method, string url, string apiKey, string jsonBody)
        {
            try
            {
                using (var req = new HttpRequestMessage(new HttpMethod((method ?? "GET").ToUpperInvariant()), url))
                {
                    req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey ?? "");
                    if (jsonBody != null && string.Equals(method, "POST", StringComparison.OrdinalIgnoreCase))
                    {
                        req.Content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
                    }

                    HttpResponseMessage resp = Client.SendAsync(req).ConfigureAwait(false).GetAwaiter().GetResult();
                    string text = resp.Content.ReadAsStringAsync().ConfigureAwait(false).GetAwaiter().GetResult() ?? "";
                    int code = (int)resp.StatusCode;
                    if (code < 200 || code >= 300)
                    {
                        string snippet = text.Replace("\r", " ").Replace("\n", " ").Trim();
                        if (snippet.Length > 180)
                            snippet = snippet.Substring(0, 180);
                        throw new Exception("API 请求失败 HTTP " + code + (snippet.Length > 0 ? "\n" + snippet : ""));
                    }
                    return text;
                }
            }
            catch (Exception ex)
            {
                if (ex is AggregateException)
                {
                    AggregateException ae = (AggregateException)ex;
                    if (ae.InnerException != null)
                        throw new Exception(ae.InnerException.Message, ae.InnerException);
                }
                if (ex.Message != null && ex.Message.StartsWith("API 请求失败"))
                    throw;
                throw new Exception(ex.Message, ex);
            }
        }

        public static string NormalizeBaseUrl(string url)
        {
            if (url == null)
                return "";
            url = url.Trim().TrimEnd('/', '\\');
            return url;
        }

        private static string JsonEsc(string s)
        {
            if (s == null)
                return "";
            return s.Replace("\\", "\\\\")
                .Replace("\"", "\\\"")
                .Replace("\r\n", "\\n")
                .Replace("\n", "\\n")
                .Replace("\r", "\\n")
                .Replace("\t", "\\t");
        }

        private static string ParseModelIdsJson(string body)
        {
            var sb = new StringBuilder();
            sb.Append('[');
            bool first = true;
            foreach (Match m in Regex.Matches(body ?? "", "\"id\"\\s*:\\s*\"([^\"]+)\""))
            {
                if (!first)
                    sb.Append(',');
                first = false;
                sb.Append('"').Append(JsonEsc(m.Groups[1].Value)).Append('"');
            }
            sb.Append(']');
            return sb.ToString();
        }

        private static string ParseChatResult(string body)
        {
            if (string.IsNullOrEmpty(body))
                throw new Exception("无法解析模型回复，请检查接口是否兼容 OpenAI Chat Completions");

            string content = ParseChatContent(body);
            string reasoning = ParseReasoningContent(body);
            var calls = new StringBuilder();
            foreach (Match m in Regex.Matches(body,
                "\"id\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"[\\s\\S]{0,240}?\"name\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"[\\s\\S]{0,80}?\"arguments\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"",
                RegexOptions.Singleline))
            {
                if (calls.Length > 0)
                    calls.Append(',');
                calls.Append("{\"id\":\"").Append(JsonEsc(UnescapeJsonString(m.Groups[1].Value)))
                    .Append("\",\"name\":\"").Append(JsonEsc(UnescapeJsonString(m.Groups[2].Value)))
                    .Append("\",\"arguments\":\"").Append(JsonEsc(UnescapeJsonString(m.Groups[3].Value)))
                    .Append("\"}");
            }
            if (calls.Length < 1)
            {
                foreach (Match m in Regex.Matches(body,
                    "\"name\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"\\s*,\\s*\"arguments\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"",
                    RegexOptions.Singleline))
                {
                    if (calls.Length > 0)
                        calls.Append(',');
                    calls.Append("{\"id\":\"call_").Append(calls.Length).Append("\",\"name\":\"")
                        .Append(JsonEsc(UnescapeJsonString(m.Groups[1].Value)))
                        .Append("\",\"arguments\":\"").Append(JsonEsc(UnescapeJsonString(m.Groups[2].Value)))
                        .Append("\"}");
                }
            }
            return WrapChatPayload(content, reasoning, calls.ToString());
        }

        private static string ParseReasoningContent(string body)
        {
            if (string.IsNullOrEmpty(body))
                return "";
            Match m = Regex.Match(body, "\"reasoning_content\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (!m.Success)
                m = Regex.Match(body, "\"reasoning\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (!m.Success)
                m = Regex.Match(body, "\"thinking\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (!m.Success)
                return "";
            return UnescapeJsonString(m.Groups[1].Value);
        }

        private static string ParseChatContent(string body)
        {
            if (string.IsNullOrEmpty(body))
                return "";

            // content 可能为 null（纯 tool_calls）
            if (Regex.IsMatch(body, "\"content\"\\s*:\\s*null"))
                return "";

            // 优先取 choices[0].message.content
            Match m = Regex.Match(body,
                "\"choices\"\\s*:\\s*\\[\\s*\\{[\\s\\S]*?\"message\"\\s*:\\s*\\{[\\s\\S]*?\"content\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"",
                RegexOptions.Singleline);
            if (!m.Success)
            {
                m = Regex.Match(body, "\"content\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            }
            if (!m.Success)
                return "";

            return UnescapeJsonString(m.Groups[1].Value);
        }

        private static string UnescapeJsonString(string s)
        {
            if (string.IsNullOrEmpty(s))
                return "";
            var sb = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                if (s[i] == '\\' && i + 1 < s.Length)
                {
                    char n = s[++i];
                    switch (n)
                    {
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case '"': sb.Append('"'); break;
                        case '\\': sb.Append('\\'); break;
                        case '/': sb.Append('/'); break;
                        case 'u':
                            if (i + 4 < s.Length)
                            {
                                int code;
                                if (int.TryParse(s.Substring(i + 1, 4), System.Globalization.NumberStyles.HexNumber, null, out code))
                                {
                                    sb.Append((char)code);
                                    i += 4;
                                    break;
                                }
                            }
                            sb.Append(n);
                            break;
                        default: sb.Append(n); break;
                    }
                }
                else
                    sb.Append(s[i]);
            }
            return sb.ToString();
        }
    }
}
