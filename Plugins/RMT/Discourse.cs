using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;

namespace RMT
{
    /// <summary>
    /// Discourse 站点客户端（列表/搜索/下载附件 + 上传/发帖/UserApiKey 授权）。
    /// AHK 侧用法与 Http 相同：Begin* → 定时器轮询 Get*State，为 2 时 Take*Result。
    /// </summary>
    public class Discourse
    {
        private static readonly HttpClient SharedClient;

        private readonly object _textLock = new object();
        private int _textState;         // 0=idle 1=running 2=ready
        private string _textResult = "";
        private string _textError = "";
        private int _textSeq;

        private readonly object _dlLock = new object();
        private int _dlState;           // 0=idle 1=running 2=ready
        private string _dlResult = "";  // "OK" 或错误信息
        private int _dlSeq;

        static Discourse()
        {
            try
            {
                System.Net.ServicePointManager.SecurityProtocol |=
                    (System.Net.SecurityProtocolType)3072; // Tls12
            }
            catch { }

            // 显式指定 TLS1.2（宿主进程内 ServicePointManager 对 HttpClientHandler 不保证生效；
            // 本机实测 .NET+TLS1.2 到共享站点可正常握手）
            var handler = new HttpClientHandler();
            try
            {
                handler.SslProtocols = System.Security.Authentication.SslProtocols.Tls12;
            }
            catch { }
            try
            {
                handler.SslProtocols |= (System.Security.Authentication.SslProtocols)12288; // Tls13
            }
            catch { }

            SharedClient = new HttpClient(handler);
            SharedClient.Timeout = TimeSpan.FromSeconds(90);
            try
            {
                SharedClient.DefaultRequestHeaders.UserAgent.ParseAdd("RMT-Client/1.0");
            }
            catch { }
        }

        /// <summary>把整条异常链的消息串起来（.NET 网络异常的真实原因在 InnerException 里）。</summary>
        private static string Describe(Exception ex)
        {
            string msg = ex == null ? "" : ex.Message;
            Exception inner = ex == null ? null : ex.InnerException;
            int depth = 0;
            while (inner != null && depth++ < 4)
            {
                if (!string.IsNullOrEmpty(inner.Message))
                    msg += " <- " + inner.Message;
                inner = inner.InnerException;
            }
            return msg;
        }

        /// <summary>异步 GET 文本（JSON API），不阻塞调用线程。</summary>
        public void BeginGetText(string url)
        {
            int seq;
            lock (_textLock)
            {
                if (_textState == 1)
                    return;
                _textState = 1;
                _textResult = "";
                _textError = "";
                _textSeq++;
                seq = _textSeq;
            }

            string u = url ?? "";
            Task.Run(async () =>
            {
                string body = "";
                string err = "";
                try
                {
                    body = await GetTextCoreAsync(u).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    err = "[D2] " + Describe(ex);
                }

                lock (_textLock)
                {
                    if (seq != _textSeq)
                        return;
                    _textResult = body ?? "";
                    _textError = err;
                    _textState = 2;
                }
            });
        }

        /// <summary>0=空闲 1=进行中 2=已完成可取结果</summary>
        public int GetTextState()
        {
            lock (_textLock)
                return _textState;
        }

        /// <summary>取走结果并回到 idle；失败返回空串，错误信息经 GetTextError() 获取。</summary>
        public string TakeTextResult()
        {
            lock (_textLock)
            {
                if (_textState != 2)
                    return "";
                string r = _textResult ?? "";
                _textResult = "";
                _textState = 0;
                return r;
            }
        }

        /// <summary>最近一次文本请求的错误信息（未失败时为空）。</summary>
        public string GetTextError()
        {
            lock (_textLock)
                return _textError ?? "";
        }

        /// <summary>异步下载文件到本地，不阻塞调用线程。</summary>
        public void BeginDownload(string url, string savePath)
        {
            int seq;
            lock (_dlLock)
            {
                if (_dlState == 1)
                    return;
                _dlState = 1;
                _dlResult = "";
                _dlSeq++;
                seq = _dlSeq;
            }

            string u = url ?? "";
            string p = savePath ?? "";
            Task.Run(async () =>
            {
                string result;
                try
                {
                    result = await DownloadCoreAsync(u, p).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    result = "下载失败: " + Describe(ex);
                }

                lock (_dlLock)
                {
                    if (seq != _dlSeq)
                        return;
                    _dlResult = result ?? "";
                    _dlState = 2;
                }
            });
        }

        /// <summary>0=空闲 1=进行中 2=已完成可取结果</summary>
        public int GetDownloadState()
        {
            lock (_dlLock)
                return _dlState;
        }

        /// <summary>取走结果并回到 idle；"OK" 表示成功，否则为错误信息。</summary>
        public string TakeDownloadResult()
        {
            lock (_dlLock)
            {
                if (_dlState != 2)
                    return "";
                string r = _dlResult ?? "";
                _dlResult = "";
                _dlState = 0;
                return r;
            }
        }

        private static async Task<string> GetTextCoreAsync(string url)
        {
            if (!NetworkInterface.GetIsNetworkAvailable())
                throw new Exception("网络不可用");

            HttpResponseMessage response = await SharedClient.GetAsync(url).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsStringAsync().ConfigureAwait(false) ?? "";
        }

        private static async Task<string> DownloadCoreAsync(string url, string savePath)
        {
            if (!NetworkInterface.GetIsNetworkAvailable())
                throw new Exception("网络不可用");

            HttpResponseMessage response = await SharedClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();

            string dir = Path.GetDirectoryName(savePath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                Directory.CreateDirectory(dir);

            using (FileStream fs = new FileStream(savePath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
            {
                await response.Content.CopyToAsync(fs).ConfigureAwait(false);
            }
            return "OK";
        }

        // ================= 上传 / 发帖 / 授权（写通道，需鉴权） =================

        private string _authUser = "";  // 非空 = 管理员/普通 Api-Key 模式（Api-Key + Api-Username）
        private string _authKey = "";   // 空 = 未鉴权

        private readonly object _upLock = new object();
        private int _upState;           // 0=idle 1=running 2=ready
        private string _upResult = "";  // 成功=响应 JSON（含 url/short_path）
        private string _upError = "";
        private int _upSeq;

        private readonly object _poLock = new object();
        private int _poState;
        private string _poResult = "";  // 成功=响应 JSON（含 topic_id/username）
        private string _poError = "";
        private int _poSeq;

        private readonly object _auLock = new object();
        private int _auState;
        private string _auResult = "";  // 成功=响应 JSON {"key":...}
        private string _auError = "";
        private int _auSeq;

        /// <summary>
        /// 本地回调端口。站点后台 allowed_user_api_auth_redirects 不支持通配符
        /// （实测 http://127.0.0.1:*、http://127.0.0.1* 等一律不匹配，只有完整地址逐字相等才放行），
        /// 因此不能用端口 0 让系统随机分配，必须固定端口并把这三个地址写进站点设置。
        /// 端口被占用时顺延到下一个。改这里必须同步改站点 allowed_user_api_auth_redirects。
        /// </summary>
        private static readonly int[] AuthCallbackPorts = { 38471, 38472, 38473 };

        private readonly object _tx2Lock = new object();
        private int _tx2State;          // 带鉴权的 GET（如 /session/current.json 拿用户名）
        private string _tx2Result = "";
        private string _tx2Error = "";
        private int _tx2Seq;

        /// <summary>设置鉴权：apiUser 非空走 Api-Key+Api-Username，否则走 User-Api-Key。</summary>
        public void SetAuth(string apiUser, string apiKey)
        {
            _authUser = apiUser == null ? "" : apiUser.Trim();
            _authKey = apiKey == null ? "" : apiKey.Trim();
        }

        private void ApplyAuth(HttpRequestMessage req)
        {
            if (string.IsNullOrEmpty(_authKey))
                return;
            if (_authUser.Length > 0)
            {
                req.Headers.Add("Api-Key", _authKey);
                req.Headers.Add("Api-Username", _authUser);
            }
            else
            {
                req.Headers.Add("User-Api-Key", _authKey);
            }
        }

        private static async Task<string> SendForJsonAsync(HttpRequestMessage req)
        {
            if (!NetworkInterface.GetIsNetworkAvailable())
                throw new Exception("网络不可用");
            req.Headers.Accept.ParseAdd("application/json");
            HttpResponseMessage resp = await SharedClient.SendAsync(req).ConfigureAwait(false);
            string body = await resp.Content.ReadAsStringAsync().ConfigureAwait(false) ?? "";
            if (!resp.IsSuccessStatusCode)
                throw new Exception(HttpErrorText((int)resp.StatusCode, body));
            return body;
        }

        /// <summary>
        /// 4xx/5xx 的可读文案。Discourse 错误体形如
        ///   {"action":"create_post","errors":["此标题已被\u003ca href='…267'\u003e其他话题\u003c/a\u003e使用。"]}
        /// 整段 JSON 甩给用户没法看，这里抽 errors[]、还原 \uXXXX 转义、HTML 转纯文本
        /// （&lt;a&gt; 保留成「文字（地址）」），多条用「；」拼接；抽不出来就退回响应体片段。
        /// </summary>
        private static string HttpErrorText(int status, string body)
        {
            string s = body ?? "";
            System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(
                s, "\"errors\"\\s*:\\s*\\[(.*?)\\]",
                System.Text.RegularExpressions.RegexOptions.Singleline);
            if (!m.Success)
                return "HTTP " + status + ": " + Snip(s);

            StringBuilder sb = new StringBuilder();
            foreach (System.Text.RegularExpressions.Match one in System.Text.RegularExpressions.Regex.Matches(
                         m.Groups[1].Value, "\"((?:[^\"\\\\]|\\\\.)*)\""))
            {
                string t = one.Groups[1].Value;
                // \uXXXX 转义还原（Discourse 用 \u003c / \u003e 编码 HTML 标签）
                t = System.Text.RegularExpressions.Regex.Replace(t, "\\\\u([0-9a-fA-F]{4})",
                    h => ((char)Convert.ToInt32(h.Groups[1].Value, 16)).ToString());
                t = t.Replace("\\/", "/").Replace("\\\"", "\"").Replace("\\n", " ").Trim();
                if (t.Length == 0)
                    continue;
                // 链接保留为「文字（地址）」，其余标签直接去掉
                t = System.Text.RegularExpressions.Regex.Replace(t,
                    "<a\\s+[^>]*href=['\"]([^'\"]*)['\"][^>]*>(.*?)</a>", "$2（$1）",
                    System.Text.RegularExpressions.RegexOptions.Singleline);
                t = System.Text.RegularExpressions.Regex.Replace(t, "<[^>]*>", "").Trim();
                if (t.Length == 0)
                    continue;
                if (sb.Length > 0)
                    sb.Append("；");
                sb.Append(t);
            }

            string text = sb.ToString();
            if (text.Length == 0)
                return "HTTP " + status + ": " + Snip(s);
            return "HTTP " + status + ": " + Snip(text);
        }

        private static string Snip(string s)
        {
            s = s == null ? "" : s.Replace("\r", " ").Replace("\n", " ").Trim();
            return s.Length <= 300 ? s : s.Substring(0, 300) + "...";
        }

        /// <summary>
        /// 上传用文件名：转成纯 ASCII 且保证以 .rmt 结尾（非 ASCII 字符 → '_'）。
        /// 规避 .NET Framework 序列化 multipart 头时对非 ASCII 的处理问题（见 BeginUploadFile 注释）。
        /// </summary>
        private static string SafeFileName(string name)
        {
            string n = string.IsNullOrEmpty(name) ? "share.rmt" : name;
            StringBuilder sb = new StringBuilder(n.Length + 4);
            foreach (char c in n)
            {
                bool ok = c > 0x20 && c < 0x7F && c != '"' && c != ';' && c != '\\' && c != '/';
                sb.Append(ok ? c : '_');
            }

            string s = sb.ToString().Trim('_', ' ');
            if (s.ToLowerInvariant().EndsWith(".rmt"))
                s = s.Substring(0, s.Length - 4);
            s = s.Trim('_', ' ', '.');
            // 纯中文名会退化成空串 → 用原名哈希兜底，保证同名可区分、重名可覆盖
            if (s.Length == 0)
                s = "rmt-" + Hash8(n);
            return s + ".rmt";
        }

        private static string Hash8(string s)
        {
            using (SHA1 sha = SHA1.Create())
            {
                byte[] h = sha.ComputeHash(Encoding.UTF8.GetBytes(s == null ? "" : s));
                StringBuilder b = new StringBuilder(8);
                for (int i = 0; i < 4; i++)
                    b.Append(h[i].ToString("x2"));
                return b.ToString();
            }
        }

        /// <summary>诊断日志：写 Log\Discourse.log（相对 RMT.dll 所在目录往上两级）。</summary>
        private static void Dbg(string msg)
        {
            try
            {
                string dll = System.Reflection.Assembly.GetExecutingAssembly().Location;
                string root = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(dll), @"..\.."));
                string dir = Path.Combine(root, "Log");
                if (!Directory.Exists(dir))
                    Directory.CreateDirectory(dir);
                File.AppendAllText(Path.Combine(dir, "Discourse.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + msg + Environment.NewLine,
                    new UTF8Encoding(false));
            }
            catch { }
        }

        /// <summary>
        /// 诊断：用 1 字节的假内容把同一个 filename 的头序列化出来，记录 .NET 实际写出的字节，
        /// 用来在服务端再次拒收时确认 wire 上的文件名长什么样。
        /// </summary>
        private static async Task DbgWireHeader(string sendName)
        {
            try
            {
                MultipartFormDataContent probe = new MultipartFormDataContent();
                probe.Add(new StringContent("composer"), "type");
                ByteArrayContent pc = new ByteArrayContent(new byte[] { 0 });
                pc.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
                probe.Add(pc, "file", sendName);
                byte[] hdr = await probe.ReadAsByteArrayAsync().ConfigureAwait(false);
                int k = Math.Min(hdr.Length, 360);
                string ascii = "", hex = "";
                for (int i = 0; i < k; i++)
                {
                    ascii += (hdr[i] >= 0x20 && hdr[i] < 0x7F) ? (char)hdr[i] : '.';
                    hex += hdr[i].ToString("X2") + " ";
                }
                Dbg("[upload] wire_ascii=" + ascii.Replace("\r", "\\r").Replace("\n", "\\n"));
                Dbg("[upload] wire_hex=" + hex);
                probe.Dispose();
            }
            catch { }
        }

        /// <summary>上传附件（multipart → /uploads.json）。成功后 TakeUploadResult 为响应 JSON。</summary>
        public void BeginUploadFile(string url, string filePath)
        {
            int seq;
            lock (_upLock)
            {
                if (_upState == 1)
                    return;
                _upState = 1;
                _upResult = "";
                _upError = "";
                _upSeq++;
                seq = _upSeq;
            }

            string u = url ?? "";
            string p = filePath ?? "";
            Task.Run(async () =>
            {
                string body = "";
                string err = "";
                try
                {
                    if (!File.Exists(p))
                        throw new Exception("文件不存在: " + p);
                    byte[] bytes = File.ReadAllBytes(p);

                    // 文件名统一降级为纯 ASCII。
                    // 现象：中文名分享包（取消禁用配置才能生效.rmt）上传被服务端拒收，返回
                    //   422 {"errors":["抱歉，您尝试上传的文件不被允许（允许的扩展名：…）"]}
                    // 而同一文件、同一 key 用 curl/node 原样上传（含中文名）能成功 → 说明问题出在
                    // .NET Framework 序列化 multipart 头这一步（它按 ISO-8859-1 编码该头）。
                    // 展示名不依赖文件名（在 .rmt 内的 meta 与帖子标题里），故直接 ASCII 化规避。
                    string rawName = Path.GetFileName(p);
                    string sendName = SafeFileName(rawName);
                    Dbg("[upload] path=" + p + " | rawName=" + rawName + " | sendName=" + sendName + " | bytes=" + bytes.Length);
                    await DbgWireHeader(sendName).ConfigureAwait(false);

                    MultipartFormDataContent form = new MultipartFormDataContent();
                    form.Add(new StringContent("composer"), "type");
                    ByteArrayContent fc = new ByteArrayContent(bytes);
                    fc.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
                    form.Add(fc, "file", sendName);

                    HttpRequestMessage req = new HttpRequestMessage(HttpMethod.Post, u) { Content = form };
                    ApplyAuth(req);
                    body = await SendForJsonAsync(req).ConfigureAwait(false);
                    Dbg("[upload] ok, resp=" + Snip(body));
                }
                catch (Exception ex)
                {
                    err = "[D3] " + Describe(ex);
                    Dbg("[upload] FAIL " + err);
                }

                lock (_upLock)
                {
                    if (seq != _upSeq)
                        return;
                    _upResult = body ?? "";
                    _upError = err;
                    _upState = 2;
                }
            });
        }

        public int GetUploadState() { lock (_upLock) return _upState; }

        public string TakeUploadResult()
        {
            lock (_upLock)
            {
                if (_upState != 2)
                    return "";
                string r = _upResult ?? "";
                _upResult = "";
                _upState = 0;
                return r;
            }
        }

        public string GetUploadError() { lock (_upLock) return _upError ?? ""; }

        /// <summary>发帖（form-urlencoded → /posts.json）。tagsCsv 逗号分隔（对应 tags[]）。</summary>
        public void BeginCreatePost(string url, string title, string raw, int categoryId, string tagsCsv)
        {
            int seq;
            lock (_poLock)
            {
                if (_poState == 1)
                    return;
                _poState = 1;
                _poResult = "";
                _poError = "";
                _poSeq++;
                seq = _poSeq;
            }

            string u = url ?? "", t = title ?? "", r = raw ?? "", tags = tagsCsv ?? "";
            int cat = categoryId;
            Task.Run(async () =>
            {
                string body = "";
                string err = "";
                try
                {
                    List<KeyValuePair<string, string>> pairs = new List<KeyValuePair<string, string>>();
                    pairs.Add(new KeyValuePair<string, string>("title", t));
                    pairs.Add(new KeyValuePair<string, string>("raw", r));
                    pairs.Add(new KeyValuePair<string, string>("category", cat.ToString()));
                    string[] tagArr = tags.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string tag in tagArr)
                    {
                        string tg = tag.Trim();
                        if (tg.Length > 0)
                            pairs.Add(new KeyValuePair<string, string>("tags[]", tg));
                    }

                    HttpRequestMessage req = new HttpRequestMessage(HttpMethod.Post, u)
                    {
                        Content = new FormUrlEncodedContent(pairs)
                    };
                    ApplyAuth(req);
                    body = await SendForJsonAsync(req).ConfigureAwait(false);
                    Dbg("[post] ok, title=" + t + " cat=" + cat + " resp=" + Snip(body));
                }
                catch (Exception ex)
                {
                    err = "[D4] " + Describe(ex);
                    Dbg("[post] FAIL title=" + t + " cat=" + cat + " | " + err);
                }

                lock (_poLock)
                {
                    if (seq != _poSeq)
                        return;
                    _poResult = body ?? "";
                    _poError = err;
                    _poState = 2;
                }
            });
        }

        /// <summary>
        /// 在本主题下发一层回复（版本层）：POST /posts.json + topic_id，不带 title/category/tags。
        /// 与「改首楼」相比不受站点 post_edit_time_limit 约束，且不会覆盖任何已有内容。
        /// 复用 _po* 发帖状态机（GetPostState / TakePostResult / GetPostError）。
        /// </summary>
        public void BeginCreateReply(string url, int topicId, string raw)
        {
            int seq;
            lock (_poLock)
            {
                if (_poState == 1)
                    return;
                _poState = 1;
                _poResult = "";
                _poError = "";
                _poSeq++;
                seq = _poSeq;
            }

            string u = url ?? "", r = raw ?? "";
            int tid = topicId;
            Task.Run(async () =>
            {
                string body = "";
                string err = "";
                try
                {
                    List<KeyValuePair<string, string>> pairs = new List<KeyValuePair<string, string>>();
                    pairs.Add(new KeyValuePair<string, string>("topic_id", tid.ToString()));
                    pairs.Add(new KeyValuePair<string, string>("raw", r));

                    HttpRequestMessage req = new HttpRequestMessage(HttpMethod.Post, u)
                    {
                        Content = new FormUrlEncodedContent(pairs)
                    };
                    ApplyAuth(req);
                    body = await SendForJsonAsync(req).ConfigureAwait(false);
                    Dbg("[reply] ok, topic=" + tid + " resp=" + Snip(body));
                }
                catch (Exception ex)
                {
                    err = "[D6] " + Describe(ex);
                    Dbg("[reply] FAIL topic=" + tid + " | " + err);
                }

                lock (_poLock)
                {
                    if (seq != _poSeq)
                        return;
                    _poResult = body ?? "";
                    _poError = err;
                    _poState = 2;
                }
            });
        }

        public int GetPostState() { lock (_poLock) return _poState; }

        public string TakePostResult()
        {
            lock (_poLock)
            {
                if (_poState != 2)
                    return "";
                string r = _poResult ?? "";
                _poResult = "";
                _poState = 0;
                return r;
            }
        }

        public string GetPostError() { lock (_poLock) return _poError ?? ""; }

        private readonly object _puLock = new object();
        private int _puState;           // PUT /posts/{id}.json —— 更新已有分享的正文（版本更新）
        private string _puResult = "";
        private string _puError = "";
        private int _puSeq;

        /// <summary>
        /// 更新已有帖子的正文（PUT /posts/{id}.json，form-urlencoded post[raw]=...）。
        /// 仅作者本人或 staff 能改（Discourse 侧判定）；标题不动 —— 同名帖标题本就一致。
        /// 注意：当前客户端未调用它 —— 版本更新已改成「每版一层楼」发回复（BeginCreateReply），
        /// 因为改首楼会受站点 post_edit_time_limit（24 小时）限制，且会覆盖旧版内容。
        /// 保留此通道备将来改首楼说明/修格式用。
        /// </summary>
        public void BeginUpdatePost(string url, int postId, string raw)
        {
            int seq;
            lock (_puLock)
            {
                if (_puState == 1)
                    return;
                _puState = 1;
                _puResult = "";
                _puError = "";
                _puSeq++;
                seq = _puSeq;
            }

            string u = url ?? "";
            string r = raw ?? "";
            Task.Run(async () =>
            {
                string body = "";
                string err = "";
                try
                {
                    List<KeyValuePair<string, string>> pairs = new List<KeyValuePair<string, string>>();
                    pairs.Add(new KeyValuePair<string, string>("post[raw]", r));

                    HttpRequestMessage req = new HttpRequestMessage(HttpMethod.Put, u)
                    {
                        Content = new FormUrlEncodedContent(pairs)
                    };
                    ApplyAuth(req);
                    body = await SendForJsonAsync(req).ConfigureAwait(false);
                    Dbg("[update] ok, post=" + postId + " resp=" + Snip(body));
                }
                catch (Exception ex)
                {
                    err = "[D7] " + Describe(ex);
                    Dbg("[update] FAIL post=" + postId + " | " + err);
                }

                lock (_puLock)
                {
                    if (seq != _puSeq)
                        return;
                    _puResult = body ?? "";
                    _puError = err;
                    _puState = 2;
                }
            });
        }

        public int GetUpdatePostState() { lock (_puLock) return _puState; }

        public string TakeUpdatePostResult()
        {
            lock (_puLock)
            {
                if (_puState != 2)
                    return "";
                string r = _puResult ?? "";
                _puResult = "";
                _puState = 0;
                return r;
            }
        }

        public string GetUpdatePostError() { lock (_puLock) return _puError ?? ""; }

        /// <summary>带鉴权的 GET 文本（如 /session/current.json 取当前用户名）。</summary>
        public void BeginGetTextAuth(string url)
        {
            int seq;
            lock (_tx2Lock)
            {
                if (_tx2State == 1)
                    return;
                _tx2State = 1;
                _tx2Result = "";
                _tx2Error = "";
                _tx2Seq++;
                seq = _tx2Seq;
            }

            string u = url ?? "";
            Task.Run(async () =>
            {
                string body = "";
                string err = "";
                try
                {
                    HttpRequestMessage req = new HttpRequestMessage(HttpMethod.Get, u);
                    ApplyAuth(req);
                    body = await SendForJsonAsync(req).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    err = "[D5] " + Describe(ex);
                }

                lock (_tx2Lock)
                {
                    if (seq != _tx2Seq)
                        return;
                    _tx2Result = body ?? "";
                    _tx2Error = err;
                    _tx2State = 2;
                }
            });
        }

        public int GetTextAuthState() { lock (_tx2Lock) return _tx2State; }

        public string TakeTextAuthResult()
        {
            lock (_tx2Lock)
            {
                if (_tx2State != 2)
                    return "";
                string r = _tx2Result ?? "";
                _tx2Result = "";
                _tx2State = 0;
                return r;
            }
        }

        public string GetTextAuthError() { lock (_tx2Lock) return _tx2Error ?? ""; }

        /// <summary>
        /// User API Key 浏览器授权：
        /// 生成 RSA 密钥对 → 打开 /user-api-key/new → 本地固定端口收回调 →
        /// RSA 解密 payload（PKCS#1 v1.5）→ 校验 nonce → TakeAuthResult 得 {"key":...}。
        /// 前置条件：站点后台 allowed_user_api_auth_redirects 必须逐字包含
        /// http://127.0.0.1:38471/authcb、:38472、:38473（该设置不支持通配符）。
        /// </summary>
        public void BeginUserAuth(string siteUrl)
        {
            int seq;
            lock (_auLock)
            {
                if (_auState == 1)
                    return;
                _auState = 1;
                _auResult = "";
                _auError = "";
                _auSeq++;
                seq = _auSeq;
            }

            string base0 = (siteUrl ?? "").TrimEnd('/');
            Task.Run(() =>
            {
                string result = "";
                string err = "";
                try
                {
                    if (base0.Length == 0)
                        throw new Exception("站点地址为空");

                    string nonce = RandomHex(16);
                    string clientId = Guid.NewGuid().ToString("N");

                    using (RSACryptoServiceProvider rsa = new RSACryptoServiceProvider(2048))
                    {
                        string pem = ToSpkiPem(rsa.ExportParameters(false));

                        TcpListener listener = null;
                        int port = 0;
                        foreach (int p in AuthCallbackPorts)
                        {
                            try
                            {
                                TcpListener t = new TcpListener(IPAddress.Loopback, p);
                                t.Start();
                                listener = t;
                                port = p;
                                break;
                            }
                            catch { }
                        }
                        if (listener == null)
                            throw new Exception("本地回调端口 38471-38473 全部被占用，请关闭占用程序后重试");

                        string redirect = "http://127.0.0.1:" + port + "/authcb";

                        // scopes 必须用逗号分隔：服务端按 params[:scopes].split(",") 切分后再比对
                        // allow_user_api_key_scopes，写成 "read|write" 会被当成单个 scope 而 403。
                        // padding 显式声明 pkcs1，与下面 rsa.Decrypt(cipher, false) 对应。
                        string authUrl = base0 + "/user-api-key/new"
                            + "?application_name=" + Uri.EscapeDataString("RMT")
                            + "&client_id=" + clientId
                            + "&scopes=" + Uri.EscapeDataString("read,write")
                            + "&public_key=" + Uri.EscapeDataString(pem)
                            + "&nonce=" + nonce
                            + "&padding=pkcs1"
                            + "&auth_redirect=" + Uri.EscapeDataString(redirect);

                        try
                        {
                            Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true });
                        }
                        catch
                        {
                            listener.Stop();
                            throw new Exception("无法打开浏览器，请手动访问授权链接");
                        }

                        // 等待浏览器回调（最多 5 分钟）；_auSeq 变动说明已被取消或发起了新授权，立即退出
                        string payloadRaw = "";
                        DateTime deadline = DateTime.UtcNow.AddMinutes(5);
                        while (DateTime.UtcNow < deadline)
                        {
                            if (_auSeq != seq)
                                break;
                            if (!listener.Pending())
                            {
                                Thread.Sleep(120);
                                continue;
                            }
                            TcpClient cl = listener.AcceptTcpClient();
                            try
                            {
                                cl.ReceiveTimeout = 5000;
                                using (NetworkStream ns = cl.GetStream())
                                {
                                    byte[] buf = new byte[65536];
                                    int len = ns.Read(buf, 0, buf.Length);
                                    string reqText = Encoding.UTF8.GetString(buf, 0, len);
                                    payloadRaw = ExtractQueryParam(reqText, "payload");

                                    string respHtml = "<html><body><h2>授权成功</h2><p>请回到 RMT 客户端继续。</p></body></html>";
                                    string resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" + respHtml;
                                    byte[] rb = Encoding.UTF8.GetBytes(resp);
                                    ns.Write(rb, 0, rb.Length);
                                }
                            }
                            catch { }
                            try { cl.Close(); } catch { }
                            if (payloadRaw.Length > 0)
                                break;
                        }
                        listener.Stop();

                        if (payloadRaw.Length == 0)
                            throw new Exception("授权超时或被取消");

                        // 查询串里原始 + 会被部分端点当空格，先归位再解码
                        string payloadEnc = payloadRaw.Replace(" ", "%2B");
                        string payloadB64 = Uri.UnescapeDataString(payloadEnc);
                        byte[] cipher;
                        try { cipher = Convert.FromBase64String(payloadB64); }
                        catch { throw new Exception("回调 payload 解码失败"); }

                        byte[] plain;
                        try { plain = rsa.Decrypt(cipher, false); }
                        catch { throw new Exception("payload 解密失败（密钥不匹配）"); }

                        string json = Encoding.UTF8.GetString(plain);
                        string key = ExtractJsonString(json, "key");
                        string retNonce = ExtractJsonString(json, "nonce");
                        if (key.Length == 0)
                            throw new Exception("授权响应缺少 key");
                        if (retNonce.Length > 0 && retNonce != nonce)
                            throw new Exception("nonce 校验失败");

                        result = "{\"key\":\"" + key.Replace("\"", "") + "\"}";
                    }
                }
                catch (Exception ex)
                {
                    err = "[D6] " + Describe(ex);
                }

                lock (_auLock)
                {
                    if (seq != _auSeq)
                        return;
                    _auResult = result;
                    _auError = err;
                    _auState = 2;
                }
            });
        }

        public int GetAuthState() { lock (_auLock) return _auState; }

        public string TakeAuthResult()
        {
            lock (_auLock)
            {
                if (_auState != 2)
                    return "";
                string r = _auResult ?? "";
                _auResult = "";
                _auState = 0;
                return r;
            }
        }

        public string GetAuthError() { lock (_auLock) return _auError ?? ""; }

        /// <summary>
        /// 取消正在等待的浏览器授权：自增 _auSeq 让在途任务立刻退出（其回写也会因 seq 过期被丢弃），
        /// 并把状态复位成 idle，这样用户马上就能再点一次「登录」。
        /// </summary>
        public void CancelUserAuth()
        {
            lock (_auLock)
            {
                _auSeq++;
                _auState = 0;
                _auResult = "";
                _auError = "";
            }
        }

        /// <summary>同步计算文件 SHA256（HEX 小写）。分享元数据用。</summary>
        public string Sha256File(string path)
        {
            if (path == null || !File.Exists(path))
                return "";
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = File.OpenRead(path))
            {
                byte[] hash = sha.ComputeHash(fs);
                StringBuilder sb = new StringBuilder(hash.Length * 2);
                foreach (byte b in hash)
                    sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        private static string RandomHex(int bytes)
        {
            byte[] b = new byte[bytes];
            using (RNGCryptoServiceProvider rng = new RNGCryptoServiceProvider())
                rng.GetBytes(b);
            StringBuilder sb = new StringBuilder(bytes * 2);
            foreach (byte x in b)
                sb.Append(x.ToString("x2"));
            return sb.ToString();
        }

        // RSA 公钥 → SPKI PEM（.NET Framework 无 ExportSubjectPublicKeyInfo，手拼 DER）
        private static string ToSpkiPem(RSAParameters p)
        {
            byte[] oid = new byte[] { 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00 };
            byte[] n = DerUnsignedInt(p.Modulus);
            byte[] e = DerUnsignedInt(p.Exponent);
            byte[] keySeq = DerSequence(DerInteger(n), DerInteger(e));
            byte[] alg = DerSequence(oid);
            byte[] spki = DerSequence(alg, DerBitString(keySeq));
            return "-----BEGIN PUBLIC KEY-----\n" + Convert.ToBase64String(spki, Base64FormattingOptions.InsertLineBreaks) + "\n-----END PUBLIC KEY-----";
        }

        private static byte[] DerLength(int len)
        {
            if (len < 0x80)
                return new byte[] { (byte)len };
            if (len < 0x100)
                return new byte[] { 0x81, (byte)len };
            return new byte[] { 0x82, (byte)(len >> 8), (byte)(len & 0xFF) };
        }

        private static byte[] DerTlv(byte tag, byte[] content)
        {
            byte[] lenBytes = DerLength(content.Length);
            byte[] outBuf = new byte[1 + lenBytes.Length + content.Length];
            outBuf[0] = tag;
            Buffer.BlockCopy(lenBytes, 0, outBuf, 1, lenBytes.Length);
            Buffer.BlockCopy(content, 0, outBuf, 1 + lenBytes.Length, content.Length);
            return outBuf;
        }

        private static byte[] DerSequence(params byte[][] parts)
        {
            int total = 0;
            foreach (byte[] p in parts) total += p.Length;
            byte[] inner = new byte[total];
            int off = 0;
            foreach (byte[] p in parts) { Buffer.BlockCopy(p, 0, inner, off, p.Length); off += p.Length; }
            return DerTlv(0x30, inner);
        }
        private static byte[] DerInteger(byte[] inner) { return DerTlv(0x02, inner); }
        private static byte[] DerBitString(byte[] inner)
        {
            byte[] withPad = new byte[inner.Length + 1];
            withPad[0] = 0; // 无未用位
            Buffer.BlockCopy(inner, 0, withPad, 1, inner.Length);
            return DerTlv(0x03, withPad);
        }

        // 整数：去前导 0 并保证正数（最高位为 1 时补 0x00）
        private static byte[] DerUnsignedInt(byte[] v)
        {
            int first = 0;
            while (first < v.Length - 1 && v[first] == 0)
                first++;
            int len = v.Length - first;
            bool needPad = (v[first] & 0x80) != 0;
            byte[] outBuf = new byte[len + (needPad ? 1 : 0)];
            if (needPad)
                outBuf[0] = 0;
            Buffer.BlockCopy(v, first, outBuf, needPad ? 1 : 0, len);
            return outBuf;
        }

        // 从 HTTP 请求首行/头部提取查询参数
        private static string ExtractQueryParam(string reqText, string name)
        {
            int lineEnd = reqText.IndexOf("\r\n");
            string firstLine = lineEnd > 0 ? reqText.Substring(0, lineEnd) : reqText;
            int qPos = firstLine.IndexOf('?');
            if (qPos < 0)
                return "";
            int spPos = firstLine.IndexOf(' ', qPos);
            string query = spPos > qPos ? firstLine.Substring(qPos + 1, spPos - qPos - 1) : firstLine.Substring(qPos + 1);
            foreach (string pair in query.Split('&'))
            {
                int eq = pair.IndexOf('=');
                if (eq <= 0)
                    continue;
                if (pair.Substring(0, eq) == name)
                    return pair.Substring(eq + 1);
            }
            return "";
        }

        // 从解密后的 JSON 中取字符串字段（不引入 JSON 依赖）
        private static string ExtractJsonString(string json, string name)
        {
            if (json == null)
                return "";
            string needle = "\"" + name + "\"";
            int k = json.IndexOf(needle);
            if (k < 0)
                return "";
            int colon = json.IndexOf(':', k + needle.Length);
            if (colon < 0)
                return "";
            int q1 = json.IndexOf('"', colon + 1);
            if (q1 < 0)
                return "";
            StringBuilder sb = new StringBuilder();
            for (int i = q1 + 1; i < json.Length; i++)
            {
                char c = json[i];
                if (c == '\\')
                {
                    if (i + 1 < json.Length) { sb.Append(json[i + 1]); i++; }
                    continue;
                }
                if (c == '"')
                    break;
                sb.Append(c);
            }
            return sb.ToString();
        }
    }
}
