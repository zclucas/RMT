// =============================================================================
// Engine lifecycle & host: Main, RunEngine, window events, state fields
// =============================================================================
using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using System.Reflection;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Markup;
using Color = System.Windows.Media.Color;

#if ENABLE_WEBVIEW
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Web.WebView2.Core;
#endif
public partial class AhkWpfEngine
{
    string winId; IntPtr ahkHwnd; string[] tracked; Window win;
    RmtFirstFrame firstFrame;
    bool waitForInitialUpdates;
    // XAML 里写的 WindowChrome.CaptionHeight（设计尺寸）。窗口标题栏热区是窗口 DIP，不跟着
    // 根内容 Viewbox 缩放，必须按当前缩放比换算，否则内容缩小后热区会压到标题栏下方的控件上。
    double _chromeCaptionDesign = -1;
    // 系统阴影补丁的尺寸签名。拖动时位置在变、尺寸不变，签名相同就不再打 DWM。
    string _systemShadowSig;
    bool _systemShadowPosted;
    System.Collections.Generic.HashSet<string> _boundEvents = new System.Collections.Generic.HashSet<string>();
    System.Collections.Generic.Dictionary<string, object> _boundEventCtrls = new System.Collections.Generic.Dictionary<string, object>();
    System.Collections.Generic.Dictionary<string, object> _controlCache = new System.Collections.Generic.Dictionary<string, object>();
    bool LightweightEvents = false; // When true, events only send the triggering control's value (use ui.Query() for others)
    System.Collections.Generic.Dictionary<string, string> canvasModes = new System.Collections.Generic.Dictionary<string, string>();
    // 画布本地坐标下的最近光标位置（PreviewMouseMove 更新；供粘贴锚点 / CanvasMouseLive 查询）
    System.Collections.Generic.Dictionary<string, Point> canvasMouseCache = new System.Collections.Generic.Dictionary<string, Point>();
    System.Collections.Generic.Dictionary<string, string> _docViewModes = new System.Collections.Generic.Dictionary<string, string>();
    System.Collections.Generic.Dictionary<string, string> _spellCheckLangs = new System.Collections.Generic.Dictionary<string, string>();
    System.Windows.Shapes.Rectangle selectionBox = null;
    Point selectionStart;
    // Search highlight and replace preview state
    System.Collections.Generic.List<System.Windows.Documents.TextRange> _highlightedRanges = new System.Collections.Generic.List<System.Windows.Documents.TextRange>();
    System.Collections.Generic.List<object> _highlightedOriginalBackgrounds = new System.Collections.Generic.List<object>();
    bool _isPreviewActive = false;
    System.Windows.Documents.TextRange _activeMatchRange = null;
    System.Windows.Threading.DispatcherTimer _highlightDebounce = null;
    string _pendingHighlightQuery = null;
    bool _pendingHighlightMatchCase = false;
    RichTextBox _pendingHighlightRtb = null;
    static readonly System.Windows.Media.SolidColorBrush _highlightBrush;
    static readonly System.Windows.Media.SolidColorBrush _activeMatchBrush;
    // 右键点的屏幕设备坐标（右键松开时由 PointToScreen 换算），仅用于诊断日志：与菜单实际左上角对比偏移。
    static double _ctxMenuClickDevX = 0;
    static double _ctxMenuClickDevY = 0;
    string _loadedDictionaryPath = null;
    static void InitHighlightBrushes() { } // Brushes initialized in static field initializers

    // ---- 异步建窗通道 ----
    // 建窗 XAML 常达数十 KB，只能通过 WM_COPYDATA 传输，而该消息仅支持 SendMessage：
    // AHK 须等待 daemon 从队列取出后才返回。daemon 为单线程，渲染其他窗口时该等待
    // 为数十至数百毫秒，期间 AHK 主线程完全阻塞，悬浮窗刷新定时器随之停滞。
    //
    // 改为「AHK 写共享内存 + PostMessage」：投递即返回，payload 在 WndProc 中同步拷出，
    // 建窗仍交由 Dispatcher 异步执行，AHK 侧不再有同步等待。
    private static uint _wmCreateAsync = 0;

    private static uint WmCreateAsync
    {
        get
        {
            if (_wmCreateAsync == 0)
                _wmCreateAsync = RegisterWindowMessageW("RMT_XAML_CREATE");
            return _wmCreateAsync;
        }
    }

    // 从消息携带的原子读取映射名，取出完整 payload。
    // 必须在 WndProc 中同步读完：AHK 侧随后可能复用同一映射发送下一条。
    private static string ReadCreatePayload(ushort atom)
    {
        if (atom == 0)
            return null;
        StringBuilder sb = new StringBuilder(512);
        uint n = GlobalGetAtomNameW(atom, sb, sb.Capacity);
        // 原子为引用计数：AHK 添加一次，此处用毕删除一次，双方无需额外回收
        try { GlobalDeleteAtom(atom); } catch { }
        if (n == 0)
            return null;
        string name = sb.ToString();
        IntPtr h = OpenFileMappingW(HUD_FILE_MAP_READ, false, name);
        if (h == IntPtr.Zero)
            return null;
        try
        {
            IntPtr p = MapViewOfFile(h, HUD_FILE_MAP_READ, 0, 0, UIntPtr.Zero);
            if (p == IntPtr.Zero)
                return null;
            try
            {
                int len = Marshal.ReadInt32(p, 0);
                if (len <= 0 || len > 64 * 1024 * 1024)
                    return null;
                byte[] bytes = new byte[len];
                Marshal.Copy(new IntPtr(p.ToInt64() + 4), bytes, 0, len);
                return Encoding.UTF8.GetString(bytes);
            }
            finally { UnmapViewOfFile(p); }
        }
        finally { CloseHandle(h); }
    }

    [STAThread]
    public static void Main(string[] args)
    {
        EnableDpiAwareness();
        AppDomain.CurrentDomain.AssemblyResolve += (sender, resolveArgs) =>
        {
            string name = new AssemblyName(resolveArgs.Name).Name;
            foreach (var a in AppDomain.CurrentDomain.GetAssemblies())
            {
                if (a.GetName().Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                {
                    return a;
                }
            }
            string resourceName = name + ".dll";
            var asm = Assembly.GetExecutingAssembly();
            string matchName = null;
            foreach (var r in asm.GetManifestResourceNames())
            {
                if (r.EndsWith(resourceName, StringComparison.OrdinalIgnoreCase))
                {
                    matchName = r;
                    break;
                }
            }
            if (matchName != null)
            {
                using (var stream = asm.GetManifestResourceStream(matchName))
                {
                    if (stream != null)
                    {
                        byte[] data = new byte[stream.Length];
                        stream.Read(data, 0, data.Length);
                        return Assembly.Load(data);
                    }
                }
            }
            try
            {
                string tempPath = GetCacheDir();
                string localDllPath = System.IO.Path.Combine(tempPath, resourceName);
                if (System.IO.File.Exists(localDllPath))
                {
                    return System.Reflection.Assembly.LoadFrom(localDllPath);
                }
                string exeDir = System.IO.Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
                if (!string.IsNullOrEmpty(exeDir))
                {
                    string altPath = System.IO.Path.Combine(exeDir, resourceName);
                    if (System.IO.File.Exists(altPath))
                    {
                        return System.Reflection.Assembly.LoadFrom(altPath);
                    }
                }
            }
            catch { }
            return null;
        };

        try
        {
            EventManager.RegisterClassHandler(typeof(Slider), Slider.PreviewMouseLeftButtonDownEvent, new System.Windows.Input.MouseButtonEventHandler(Slider_PreviewMouseLeftButtonDown), true);
            if (args.Length >= 3 && args[0] == "--daemon")
            {
                if (args.Contains("--no-log"))
                {
                    EnableLogging = false;
                }
                try
                {
                    if (EnableLogging)
                    {
                        //try { System.IO.File.AppendAllText(@"C:\projects\ahk\ahk-xaml\daemon_log.txt", "Daemon started with args: " + string.Join(" ", args) + "\n"); } catch { }
                    }
                    int ahkPid = int.Parse(args[1]);
                    IntPtr ahkHwnd = (IntPtr)long.Parse(args[2]);

                    HwndSourceParameters parameters = new HwndSourceParameters("DaemonReceiver", 0, 0);
                    parameters.WindowStyle = 0;
                    HwndSource msgWindow = new HwndSource(parameters);

                    // 建窗派发：同步（COPYDATA）与异步（共享内存 + PostMessage）入口共用。
                    // 仅执行解析与 BeginInvoke，实际建窗仍在 Dispatcher 上异步执行。
                    Action<string> dispatchCreate = delegate(string text)
                    {
                        if (text.StartsWith("CREATE_WINDOW_INLINE|"))
                        {
                            // 内联模式：XAML 与事件表直接嵌入消息
                            // 格式：CREATE_WINDOW_INLINE|winId|trackedCsv|scriptName|ownerHwnd|xaml\n---AHK-XAML-EVENTS---\nevents
                            string[] p = text.Split(new[] { '|' }, 6);
                            if (p.Length >= 6)
                            {
                                string wId = p[1];
                                string tCsv = p[2];
                                string sName = p[3];
                                string oHwnd = p[4];
                                string inlineData = p[5];

                                System.Windows.Threading.Dispatcher.CurrentDispatcher.BeginInvoke(new Action(() =>
                                {
                                    try
                                    {
                                        AhkWpfEngine eng = new AhkWpfEngine();
                                        eng.RunEngineInline(wId, ahkHwnd.ToString(), tCsv, sName, oHwnd, inlineData, true);
                                    }
                                    catch (Exception ex)
                                    {
                                        byte[] b = Encoding.UTF8.GetBytes("EVENT|" + wId + "|Engine|Error|" + BridgeUtil.LengthPrefix(ex.ToString()) + "\n");
                                        var c = new COPYDATASTRUCT { cbData = b.Length + 1, lpData = Marshal.AllocHGlobal(b.Length + 1) };
                                        Marshal.Copy(b, 0, c.lpData, b.Length); Marshal.WriteByte(c.lpData, b.Length, 0);
                                        SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref c);
                                        Marshal.FreeHGlobal(c.lpData);
                                    }
                                }));
                            }
                        }
                        else if (text.StartsWith("CREATE_WINDOW|"))
                        {
                            string[] p = text.Split(new[] { '|' }, 9);
                            if (p.Length >= 7)
                            {
                                string wId = p[1];
                                string tCsv = p[2];
                                string sName = p[3];
                                string oHwnd = p[4];
                                string xPath = p[5];
                                string ePath = p[6];
                                double parsedScale;
                                bool parsedSkip;
                                double? initialScale = p.Length > 7 && double.TryParse(p[7], System.Globalization.NumberStyles.Float,
                                    System.Globalization.CultureInfo.InvariantCulture, out parsedScale) && IsUiScalePreset(parsedScale)
                                    ? (double?)parsedScale : null;
                                bool? skipScale = p.Length > 8 && bool.TryParse(p[8], out parsedSkip) ? (bool?)parsedSkip : null;

                                System.Windows.Threading.Dispatcher.CurrentDispatcher.BeginInvoke(new Action(() =>
                                {
                                    try
                                    {
                                        AhkWpfEngine eng = new AhkWpfEngine();
                                        eng.RunEngine(wId, ahkHwnd.ToString(), tCsv, sName, xPath, ePath, oHwnd, true, initialScale, skipScale);
                                    }
                                    catch (Exception ex)
                                    {
                                        byte[] b = Encoding.UTF8.GetBytes("EVENT|" + wId + "|Engine|Error|" + BridgeUtil.LengthPrefix(ex.ToString()) + "\n");
                                        var c = new COPYDATASTRUCT { cbData = b.Length + 1, lpData = Marshal.AllocHGlobal(b.Length + 1) };
                                        Marshal.Copy(b, 0, c.lpData, b.Length); Marshal.WriteByte(c.lpData, b.Length, 0);
                                        SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref c);
                                        Marshal.FreeHGlobal(c.lpData);
                                    }
                                }));
                            }
                        }
                    };

                    msgWindow.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
                    {
                        if (msg == 0x004A)
                        {
                            try
                            {
                                var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(lParam, typeof(COPYDATASTRUCT));
                                byte[] bytes = new byte[cds.cbData];
                                Marshal.Copy(cds.lpData, bytes, 0, cds.cbData);
                                dispatchCreate(Encoding.UTF8.GetString(bytes).TrimEnd('\0'));
                            }
                            catch { }
                            handled = true;
                        }
                        else if (msg == (int)WmCreateAsync)
                        {
                            // 异步建窗：payload 存于共享内存，读取后立即返回，不等待建窗完成
                            try
                            {
                                string text = ReadCreatePayload((ushort)(wParam.ToInt64() & 0xFFFF));
                                if (text != null)
                                    dispatchCreate(text);
                            }
                            catch { }
                            handled = true;
                        }
                        return IntPtr.Zero;
                    });

                    System.Threading.Thread t = new System.Threading.Thread(() =>
                    {
                        try
                        {
                            var p = System.Diagnostics.Process.GetProcessById(ahkPid);
                            p.WaitForExit();
                            Environment.Exit(0);
                        }
                        catch { Environment.Exit(0); }
                    });
                    t.IsBackground = true;
                    t.Start();

                    Application app = new Application();
                    app.ShutdownMode = ShutdownMode.OnExplicitShutdown;

                    try
                    {
                        LoadComponentStyles(app);
                    }
                    catch (Exception ex)
                    {
                        try
                        {
                            System.IO.File.AppendAllText(GetLogPath("daemon_error.txt"), "Error loading components: " + ex.ToString() + "\n");
                        }
                        catch { }
                    }

                    // 预热窗口实验结论（2026-11，实测主窗可见时间，其余条件相同）：
                    //   原版 dummy（0x0 + Button/TextBox/CheckBox/ListBox/TreeView，Show 后立即 Hide）  859ms
                    //   轻量版（0x0 + 中文 TextBlock，等一帧再 Hide）                                 715ms
                    //   完全不预热                                                                    638ms  ← 最优
                    // 原因：预热窗口在 daemon 的 Ready 路径上是同步执行的（~78ms），换来的渲染/字形
                    // 收益远小于这笔开销；而主窗自己首次渲染时，渲染线程本来就和 UI 线程并行。
                    // 所以这里不再预热，保留说明避免以后重复踩坑。
                    // try
                    // {
                    //     var warm = new Window { Width = 0, Height = 0, WindowStyle = WindowStyle.None,
                    //         ShowInTaskbar = false, ShowActivated = false, ResizeMode = ResizeMode.NoResize,
                    //         Left = -10000, Top = -10000 };
                    //     warm.Content = new TextBlock { Text = "正在加载配置 中文预热点 ABCDEFGHIJ 0123456789" };
                    //     warm.Show();
                    //     app.Dispatcher.BeginInvoke(new Action(() => { try { warm.Hide(); } catch { } }),
                    //         System.Windows.Threading.DispatcherPriority.Background);
                    // }
                    // catch { }
#if ENABLE_WEBVIEW
                    try {
                        var wv = new Microsoft.Web.WebView2.Wpf.WebView2();
                        string customDir = Environment.GetEnvironmentVariable("AHK_XAML_WEBVIEW_DIR");
                        string wvDataDir = !string.IsNullOrEmpty(customDir) ? customDir : System.IO.Path.Combine(GetLogDir(), "WebView2Data");
                        wv.CreationProperties = new Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties {
                            UserDataFolder = wvDataDir
                        };
                    } catch { }
#endif
                    // 样式和预热都结束后再报 Ready。提前报的话，AHK 会在 UI 线程还堵在
                    // LoadComponentStyles 时送来 CREATE_WINDOW，超时后引擎被杀掉，主窗口永远不出现。
                    app.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        try
                        {
                            byte[] rBytes = Encoding.UTF8.GetBytes("DAEMON|Ready|" + msgWindow.Handle.ToString() + "\n");
                            var rCds = new COPYDATASTRUCT { cbData = rBytes.Length + 1, lpData = Marshal.AllocHGlobal(rBytes.Length + 1) };
                            Marshal.Copy(rBytes, 0, rCds.lpData, rBytes.Length);
                            Marshal.WriteByte(rCds.lpData, rBytes.Length, 0);
                            SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref rCds);
                            Marshal.FreeHGlobal(rCds.lpData);
                        }
                        catch { }
                    }));

                    app.Run();
                }
                catch { }
                return;
            }
            if (args.Length >= 2 && args[0] == "--prewarm")
            {
                try
                {
                    int pid = int.Parse(args[1]);
                    var dummy = new Window { Width = 0, Height = 0, WindowStyle = WindowStyle.None, ShowInTaskbar = false, AllowsTransparency = true, Opacity = 0 };
                    dummy.Show();
                    dummy.Hide();
#if ENABLE_WEBVIEW
                    try {
                        var wv = new Microsoft.Web.WebView2.Wpf.WebView2();
                        string customDir = Environment.GetEnvironmentVariable("AHK_XAML_WEBVIEW_DIR");
                        string wvDataDir = !string.IsNullOrEmpty(customDir) ? customDir : System.IO.Path.Combine(GetLogDir(), "WebView2Data");
                        wv.CreationProperties = new Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties {
                            UserDataFolder = wvDataDir
                        };
                    } catch { }
#endif
                    System.Threading.Thread t = new System.Threading.Thread(() =>
                    {
                        try
                        {
                            var p = System.Diagnostics.Process.GetProcessById(pid);
                            p.WaitForExit();
                            Environment.Exit(0);
                        }
                        catch { Environment.Exit(0); }
                    });
                    t.IsBackground = true;
                    t.Start();
                    new Application().Run();
                }
                catch { }
                return;
            }
            if (args.Length >= 3 && args[0] == "--compress")
            {
                try
                {
                    byte[] data = System.IO.File.ReadAllBytes(args[1]);
                    using (var fs = new System.IO.FileStream(args[2], System.IO.FileMode.Create))
                    using (var gz = new System.IO.Compression.GZipStream(fs, System.IO.Compression.CompressionMode.Compress))
                    {
                        gz.Write(data, 0, data.Length);
                    }
                }
                catch (Exception ex) { Console.WriteLine(ex); }
                return;
            }
            if (args.Length < 3) return;
            AhkWpfEngine engine = new AhkWpfEngine();
            if (args.Length >= 5)
            {
                int ahkPid = int.Parse(args[3]);
                string scriptName = args[4];
                System.Threading.Thread t = new System.Threading.Thread(() =>
                {
                    try
                    {
                        System.Diagnostics.Process p = System.Diagnostics.Process.GetProcessById(ahkPid);
                        p.WaitForExit();
                        Application.Current.Dispatcher.Invoke(() =>
                        {
                            try
                            {
                                string state = engine.CollectState();
                                System.IO.File.WriteAllText(GetLogPath("AhkWpf_StateDump_" + scriptName + ".ini"), state);
                            }
                            catch { }
                            Environment.Exit(0);
                        });
                    }
                    catch { Environment.Exit(0); }
                });
                t.IsBackground = true;
                t.Start();
            }
            engine.RunEngine(args[0], args[1], args[2], args.Length >= 5 ? args[4] : "", args.Length >= 6 ? args[5] : "", args.Length >= 7 ? args[6] : "", args.Length >= 8 ? args[7] : "0", false);
        }
        catch (Exception ex)
        {
            try
            {
                if (EnableLogging) System.IO.File.WriteAllText(GetLogPath("AhkWpfError.log"), ex.ToString());
            }
            catch { }
            Environment.Exit(1);
        }
    }

    public void RunEngineInline(string id, string hwndStr, string trackedCsv, string scriptName, string ownerHwndStr, string inlineData, bool isDaemon)
    {
        // ---- 开窗分段计时（诊断用，一行一条）----
        // 后台启动标记：AHK 在 inline 数据前加 #HIDDEN#，窗口建好后立刻收起（rmt -min）
        bool startHidden = false;
        if (inlineData.StartsWith("#HIDDEN#", StringComparison.Ordinal))
        {
            startHidden = true;
            inlineData = inlineData.Substring(8);
        }
        waitForInitialUpdates = inlineData.StartsWith("#INIT#", StringComparison.Ordinal);
        if (waitForInitialUpdates) inlineData = inlineData.Substring(6);
        // Fast path: parse XAML + events directly from the inline data
        string[] parts = inlineData.Split(new[] { "\n---AHK-XAML-EVENTS---\n" }, 2, StringSplitOptions.None);
        string xamlContent = parts[0];
        string eventsContent = parts.Length > 1 ? parts[1] : "";

        winId = id; ahkHwnd = (IntPtr)long.Parse(hwndStr);
        lock (_activeEngines)
        {
            _activeEngines[winId] = this;
        }
        tracked = trackedCsv.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);

#if ENABLE_WEBVIEW
        PreprocessXamlAndExtractWebViewSources(ref xamlContent);
#endif
        byte[] xamlBytes = Encoding.UTF8.GetBytes(xamlContent);
        // 只有 XAML 里真的带 WebView2 控件才需要遍历整棵树去配它。
        // 主窗口这种上千控件的大窗口，这一趟遍历实测要 700ms+，找不到就白烧。
        bool hasWebView2 = xamlContent.IndexOf("WebView2", StringComparison.OrdinalIgnoreCase) >= 0;
        if (Application.Current == null) new Application();
        try
        {
            using (var stream = new System.IO.MemoryStream(xamlBytes))
            {
                win = (Window)XamlReader.Load(stream);
            }
            SyncWindowResourcesToApp(win);
            xamlContent = null;
            xamlBytes = null;

            // Viewbox construction and resource scaling are shared with the file/BAML path
            // in PrepareWindowUiScale, after owner assignment and before the first Show.
        }
        catch (XamlParseException ex)
        {
            string[] xamlLines = Encoding.UTF8.GetString(xamlBytes).Replace("\r\n", "\n").Split('\n');
            string snippet = "Unknown";
            string ahkLine = "Unknown";
            if (ex.LineNumber > 0 && ex.LineNumber <= xamlLines.Length)
            {
                int startLine = Math.Max(0, ex.LineNumber - 8);
                int endLine = Math.Min(xamlLines.Length - 1, ex.LineNumber + 8);
                StringBuilder sb = new StringBuilder();
                for (int i = startLine; i <= endLine; i++)
                {
                    string prefix = (i == ex.LineNumber - 1) ? ">> " : "   ";
                    sb.AppendLine(prefix + (i + 1) + "| " + xamlLines[i].TrimEnd());
                }
                snippet = sb.ToString().TrimEnd();
            }
            string rootCause = ex.Message;
            Exception inner = ex.InnerException;
            while (inner != null) { rootCause = inner.Message; inner = inner.InnerException; }
            throw new Exception("AHK_LINE:" + ahkLine + "\nXAML_SNIPPET:\n" + snippet + "\nREASON:\n" + rootCause + "\n\n" + ex.ToString());
        }

        // Bind standard window chrome handlers
        var dragArea = win.FindName("DragArea") as UIElement;
        if (dragArea != null)
        {
            dragArea.MouseLeftButtonDown += (s, e) =>
            {
                // 悬浮窗自行处理拖动：DragMove 对 NoActivate 透明无边框窗口不保证生效
                if (_hud != null)
                {
                    HudBeginDrag(dragArea);
                    e.Handled = true;
                    return;
                }
                try { win.DragMove(); } catch { }
            };
            dragArea.MouseMove += (s, e) => { if (_hudDragging) HudDragTo(); };
            dragArea.MouseLeftButtonUp += (s, e) => { if (_hudDragging) HudEndDrag(dragArea); };
        }
        var btnClose = win.FindName("BtnClose") as ButtonBase;
        if (btnClose != null) btnClose.Click += (s, e) => { try { win.Close(); } catch { } };
        var btnMaximize = win.FindName("BtnMaximize") as ButtonBase;
        if (btnMaximize != null) btnMaximize.Click += (s, e) => { ToggleMaximized(); };
        var btnMinimize = win.FindName("BtnMinimize") as ButtonBase;
        if (btnMinimize != null) btnMinimize.Click += (s, e) => { win.WindowState = WindowState.Minimized; };
        var btnPin = win.FindName("BtnPin") as ButtonBase;
        if (btnPin != null) btnPin.Click += (s, e) => { win.Topmost = !win.Topmost; };

        win.Resources["BaseWindowRadius"] = new CornerRadius(12);
        if (Application.Current != null) AhkWpfEngine.SetAppResource("BaseWindowRadius", win.Resources["BaseWindowRadius"]);

        win.StateChanged += (s, e) =>
        {
            SendToAhkAsync("EVENT|" + winId + "|Window|StateChanged|" + win.WindowState.ToString() + "\n");
            UpdateSnapState(win);
            OnWindowStateChangedForViewbox();
        };
        // 激活/失活必须异步回 AHK：AHK 侧 WinActivate 走 SetForegroundWindow，前台切换会同步等
        // 目标窗口处理 WM_ACTIVATE；此刻再用同步 SendMessage 把事件塞回 AHK，而 AHK 正卡在
        // WinActivate 里没泵消息 —— 两边互等，只能靠系统超时解开（实测 125~170ms/次）。
        win.Activated += (s, e) =>
        {
            SendToAhkAsync("EVENT|" + winId + "|Window|Activated\n");
        };
        win.Deactivated += (s, e) =>
        {
            SendToAhkAsync("EVENT|" + winId + "|Window|Deactivated\n");
        };
        win.LocationChanged += (s, e) => UpdateSnapState(win);
        win.SizeChanged += (s, e) => { UpdateSnapState(win); FillViewboxIfLetterboxed(); SyncChromeCaption(); };

        win.Loaded += (s, e) =>
        {
            IntPtr hwndVal = new WindowInteropHelper(win).Handle;
            HwndSource.FromHwnd(hwndVal).AddHook(WndProc);
            FillViewboxViewport();
            SyncChromeCaption();
            // Async: 避免 CREATE_WINDOW 的 SendMessage 与 LoadedHwnd 回调互相嵌套死锁
            SendToAhkAsync("EVENT|" + winId + "|Window|LoadedHwnd|" + hwndVal.ToString() + "\n");
            UpdateSnapState(win);
            InheritWindowIconAndTitle(win, ownerHwndStr);
            // 输入限制（Tag="NumOnly" 等）在视觉树建好后一次挂完，主程序只写声明
            AttachInputMasks(win);
            DumpState("Window", "Loaded");
#if ENABLE_WEBVIEW
            InitializeWebView2IfPresent(win);
#endif
        };
        win.Closing += (s, e) =>
        {
            var ownHwnd = new WindowInteropHelper(win).Owner;
            if (ownHwnd != IntPtr.Zero)
            {
                SetWindowPos(ownHwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0003);
                SetForegroundWindow(ownHwnd);
            }
            // Async: avoid deadlock when AHK closes via synchronous SendMessage(Update Close)
            SendToAhkAsync("EVENT|" + winId + "|Window|Closing\n");
        };
        win.Closed += (s, e) =>
        {
            ClearLeakedAppImplicitStyles();
            SendToAhkAsync("EVENT|" + winId + "|Window|Closed\n");
            lock (_activeEngines)
            {
                _activeEngines.Remove(winId);
            }
        };

        // Bind events
        if (!string.IsNullOrEmpty(eventsContent))
        {
            string[] pairs = eventsContent.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string p in pairs)
            {
                string evtStr = p;
                int limitFps = 0;
                bool isQueue = false;
                int atIndex = p.IndexOf('@');
                if (atIndex > 0)
                {
                    evtStr = p.Substring(0, atIndex);
                    string limitStr = p.Substring(atIndex + 1);
                    if (limitStr.EndsWith("Q"))
                    {
                        isQueue = true;
                        limitStr = limitStr.Substring(0, limitStr.Length - 1);
                    }
                    int.TryParse(limitStr, out limitFps);
                }
                // 最多拆 2 段：控件名 / 事件名（事件名可含冒号）
                string[] kv = evtStr.Split(new[] { ':' }, 2);
                if (kv.Length == 2) BindEvent(kv[0], kv[1], limitFps, isQueue);
            }
        }

        ApplyNativeOwner(win, ownerHwndStr);
        InheritWindowIconAndTitle(win, ownerHwndStr);
#if ENABLE_WEBVIEW
        if (hasWebView2)
            ConfigureWebView2CreationProperties(win);
#endif
        ShowEngineWindow(win, isDaemon, startHidden);
    }

    public void RunEngine(string id, string hwndStr, string trackedCsv, string scriptName, string xamlFilePath, string eventsFilePath, string ownerHwndStr = "0", bool isDaemon = false, double? initialUiScale = null, bool? skipUiScale = null)
    {
        if (EnableLogging)
        {
            try
            {
                var asm = System.Reflection.Assembly.GetExecutingAssembly();
                var names = string.Join(",", asm.GetManifestResourceNames());
                bool bamlExists = false;
                bool xamlExists = false;
                using (var bamlStream = asm.GetManifestResourceStream("app_payload.baml"))
                {
                    bamlExists = bamlStream != null;
                }
                using (var xamlStream = asm.GetManifestResourceStream("app_payload.xaml"))
                {
                    xamlExists = xamlStream != null;
                }
                System.IO.File.WriteAllText(
                    GetLogPath("xaml_debug_startup.log"),
                    "Assembly: " + asm.FullName + "\n" +
                    "Resources: " + names + "\n" +
                    "app_payload.baml exists: " + bamlExists + "\n" +
                    "app_payload.xaml exists: " + xamlExists + "\n"
                );
            }
            catch (Exception ex)
            {
                try { System.IO.File.WriteAllText(GetLogPath("xaml_debug_err.log"), ex.ToString()); } catch { }
            }
        }

        winId = id; ahkHwnd = (IntPtr)long.Parse(hwndStr);
        lock (_activeEngines)
        {
            _activeEngines[winId] = this;
        }
        tracked = trackedCsv.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);

        string xamlContent = "";
        string eventsContent = "";

        var resourceNames = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceNames();
        bool hasCustomBaml = resourceNames.Contains("app_payload.baml");
        bool hasCustomXaml = resourceNames.Contains("app_payload.xaml");
        bool isCustomEngine = hasCustomBaml || hasCustomXaml;
        bool isBin = !isCustomEngine && !string.IsNullOrEmpty(xamlFilePath) && xamlFilePath.EndsWith(".bin", StringComparison.OrdinalIgnoreCase);
        bool isBaml = hasCustomBaml || (!isCustomEngine && !string.IsNullOrEmpty(xamlFilePath) && xamlFilePath.EndsWith(".baml", StringComparison.OrdinalIgnoreCase));

        if (isCustomEngine && isBaml)
        {
            // Bypass file loading and streams completely
        }
        else if (xamlFilePath == "STREAM")
        {
            HwndSourceParameters parameters = new HwndSourceParameters("MessageReceiver", 0, 0);
            parameters.WindowStyle = 0;
            HwndSource msgWindow = new HwndSource(parameters);

            bool received = false;
            msgWindow.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
            {
                if (msg == 0x004A)
                {
                    try
                    {
                        var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(lParam, typeof(COPYDATASTRUCT));
                        byte[] bytes = new byte[cds.cbData];
                        Marshal.Copy(cds.lpData, bytes, 0, cds.cbData);
                        string text = Encoding.UTF8.GetString(bytes).TrimEnd('\0');
                        if (text.StartsWith("XAML_PAYLOAD|"))
                        {
                            string payload = text.Substring(13);
                            string[] p = payload.Split(new[] { "\n---AHK-XAML-EVENTS---\n" }, 2, StringSplitOptions.None);
                            xamlContent = p[0];
                            if (p.Length > 1)
                            {
                                eventsContent = p[1];
                            }
                            received = true;
                        }
                    }
                    catch { }
                    handled = true;
                }
                return IntPtr.Zero;
            });

            SendToAhk("EVENT|" + winId + "|Engine|Ready|" + msgWindow.Handle.ToString() + "\n");

            DateTime startWait = DateTime.Now;
            while (!received && (DateTime.Now - startWait).TotalSeconds < 10)
            {
                System.Windows.Threading.Dispatcher.CurrentDispatcher.Invoke(System.Windows.Threading.DispatcherPriority.Background, new Action(delegate { }));
                System.Threading.Thread.Sleep(10);
            }
            msgWindow.Dispose();

            if (!received)
            {
                throw new Exception("Timed out waiting for XAML payload stream from AHK.");
            }
        }
        else if (!isCustomEngine && !string.IsNullOrEmpty(xamlFilePath) && System.IO.File.Exists(xamlFilePath))
        {
            if (isBin)
            {
                byte[] compressed = System.IO.File.ReadAllBytes(xamlFilePath);
                string payload = "";
                try
                {
                    using (var ms = new System.IO.MemoryStream(compressed))
                    using (var gz = new System.IO.Compression.GZipStream(ms, System.IO.Compression.CompressionMode.Decompress))
                    using (var reader = new System.IO.StreamReader(gz, Encoding.UTF8))
                    {
                        payload = reader.ReadToEnd();
                    }
                }
                catch (Exception dx)
                {
                    if (EnableLogging)
                    {
                        try { System.IO.File.WriteAllText(GetLogPath("decomp_err.log"), dx.ToString()); } catch { }
                    }
                    payload = Encoding.UTF8.GetString(compressed);
                }
                string[] parts = payload.Split(new[] { "\n---AHK-XAML-EVENTS---\n" }, 2, StringSplitOptions.None);
                xamlContent = parts[0];
                if (parts.Length > 1)
                {
                    eventsContent = parts[1];
                }
            }
            else
            {
                xamlContent = System.IO.File.ReadAllText(xamlFilePath, Encoding.UTF8);
            }
        }
        else
        {
            try
            {
                var streamName = (isCustomEngine && hasCustomXaml) ? "app_payload.xaml" : "AppXaml";
                using (var targetStream = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream(streamName))
                {
                    if (targetStream != null)
                    {
                        using (var reader = new System.IO.StreamReader(targetStream, Encoding.UTF8))
                        {
                            xamlContent = reader.ReadToEnd();
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                if (EnableLogging)
                {
                    try { System.IO.File.WriteAllText(GetLogPath("xaml_load_err.log"), ex.ToString()); } catch { }
                }
            }
        }

        // Load companion event bindings (.events resource or file) if not already set (e.g. from STREAM)
        if (string.IsNullOrEmpty(eventsContent))
        {
            if (isCustomEngine)
            {
                try
                {
                    using (var eventsStream = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("app_payload.events"))
                    {
                        if (eventsStream != null)
                        {
                            using (var reader = new System.IO.StreamReader(eventsStream, Encoding.UTF8))
                            {
                                eventsContent = reader.ReadToEnd();
                            }
                        }
                    }
                }
                catch { }
            }
            else if (!string.IsNullOrEmpty(xamlFilePath))
            {
                string eventsPath = System.IO.Path.ChangeExtension(xamlFilePath, ".events");
                if (System.IO.File.Exists(eventsPath))
                {
                    try
                    {
                        eventsContent = System.IO.File.ReadAllText(eventsPath, Encoding.UTF8);
                    }
                    catch { }
                }
            }
        }

        if (!isBin && !isBaml && xamlFilePath != "STREAM" && !string.IsNullOrEmpty(xamlFilePath) &&
            !xamlFilePath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) &&
            !xamlFilePath.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) &&
            System.IO.File.Exists(xamlFilePath))
        {
            try { System.IO.File.Delete(xamlFilePath); } catch { }
        }

        // BAML fast path — load pre-compiled binary directly, bypass XML parsing entirely
        if (isBaml && (isCustomEngine || (!string.IsNullOrEmpty(xamlFilePath) && System.IO.File.Exists(xamlFilePath))))
        {
            if (Application.Current == null) new Application();
            try
            {
                using (var bamlStream = isCustomEngine ?
                       System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("app_payload.baml") :
                       System.IO.File.OpenRead(xamlFilePath))
                {
                    var bamlReader = new System.Windows.Baml2006.Baml2006Reader(bamlStream);
                    var objWriter = new System.Xaml.XamlObjectWriter(bamlReader.SchemaContext);
                    while (bamlReader.Read())
                    {
                        objWriter.WriteNode(bamlReader);
                    }
                    win = (Window)objWriter.Result;
                }
                // Baml2006Reader doesn't wire up NameScope properly — FindName() fails.
                // Force a fresh NameScope and recursively register all named FrameworkElements.
                var ns = new NameScope();
                NameScope.SetNameScope(win, ns);
                int nameCount = 0;
                var visited = new System.Collections.Generic.HashSet<object>();
                Action<object> registerAll = null;
                registerAll = (object obj) =>
                {
                    if (obj == null || !visited.Add(obj)) return;
                    var fe = obj as FrameworkElement;
                    if (fe != null)
                    {
                        if (!string.IsNullOrEmpty(fe.Name))
                        {
                            try { ns.RegisterName(fe.Name, fe); nameCount++; } catch { }
                        }
                    }
                    var dobj = obj as DependencyObject;
                    if (dobj != null)
                    {
                        // Walk logical tree children
                        foreach (object child in LogicalTreeHelper.GetChildren(dobj))
                        {
                            registerAll(child);
                        }
                        // Also walk explicit content properties that LogicalTreeHelper may miss
                        var cc = dobj as System.Windows.Controls.ContentControl;
                        if (cc != null && cc.Content != null) registerAll(cc.Content);
                        var dec = dobj as System.Windows.Controls.Decorator;
                        if (dec != null && dec.Child != null) registerAll(dec.Child);
                        var panel = dobj as System.Windows.Controls.Panel;
                        if (panel != null)
                        {
                            foreach (UIElement c in panel.Children) registerAll(c);
                        }
                        var ic = dobj as ItemsControl;
                        if (ic != null)
                        {
                            foreach (object item in ic.Items) registerAll(item);
                        }
                    }
                };
                registerAll(win);
                if (EnableLogging)
                {
                    try
                    {
                        System.IO.File.AppendAllText(
                            GetLogPath("baml_debug.log"),
                            DateTime.Now + " BAML NameScope: registered " + nameCount + " names. FindName test DGX_Table_List=" + (win.FindName("DGX_Table_List") != null) + "\n"
                        );
                    }
                    catch { }
                }
                SyncWindowResourcesToApp(win);
                // Re-apply WindowChrome (stripped during BAML compilation)
                if (win.WindowStyle == WindowStyle.None && !win.AllowsTransparency)
                {
                    var chrome = new System.Windows.Shell.WindowChrome();
                    // GlassFrame=0 禁用 DWM 系统玻璃（Win11 下 GlassFrame=-1 的系统玻璃色偏紫，首帧会闪紫）
                    // UseAeroCaptionButtons 默认 true。Win10 会在标题栏右侧留出系统按钮空位，
                    // 自定义按钮被盖住或裁掉；Win11 没有这块空位，所以同一窗口两边看起来不一样。
                    chrome.UseAeroCaptionButtons = false;
                    chrome.GlassFrameThickness = new Thickness(0);
                    chrome.ResizeBorderThickness = new Thickness(6); // 四角缩放
                    double captionHeight = 30;
                    try
                    {
                        if (win.Resources.Contains("TitleBarHeight"))
                        {
                            captionHeight = System.Convert.ToDouble(win.Resources["TitleBarHeight"]);
                        }
                        else if (Application.Current.Resources.Contains("TitleBarHeight"))
                        {
                            captionHeight = System.Convert.ToDouble(Application.Current.Resources["TitleBarHeight"]);
                        }
                    }
                    catch { }
                    chrome.CaptionHeight = captionHeight;
                    try { chrome.CornerRadius = (CornerRadius)Application.Current.Resources["WindowRadius"]; } catch { chrome.CornerRadius = new CornerRadius(12); }
                    System.Windows.Shell.WindowChrome.SetWindowChrome(win, chrome);
                    // Re-apply IsHitTestVisibleInChrome on known buttons
                    foreach (string btnName in new[] { "BtnToggleSidebar", "BtnClose", "BtnClosePanel", "BtnWinClose", "BtnMinimize", "BtnMaximize", "BtnPin" })
                    {
                        var el = win.FindName(btnName) as System.Windows.IInputElement;
                        if (el != null) System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(el, true);
                    }
                }
            }
            catch (Exception bamlEx)
            {
                // BAML load failed — log and fall through to text-based loading
                if (EnableLogging)
                {
                    try
                    {
                        System.IO.File.AppendAllText(
                            GetLogPath("baml_err.log"),
                            DateTime.Now + " BAML load failed: " + bamlEx.ToString() + "\n"
                        );
                    }
                    catch { }
                }
                // Try falling back to .xaml companion file
                string fallbackXaml = System.IO.Path.ChangeExtension(xamlFilePath, ".xaml");
                if (System.IO.File.Exists(fallbackXaml))
                {
                    xamlContent = System.IO.File.ReadAllText(fallbackXaml, Encoding.UTF8);
#if ENABLE_WEBVIEW
                    PreprocessXamlAndExtractWebViewSources(ref xamlContent);
#endif
                    byte[] fb = Encoding.UTF8.GetBytes(xamlContent);
                    using (var stream = new System.IO.MemoryStream(fb))
                    {
                        win = (Window)XamlReader.Load(stream);
                    }
                    SyncWindowResourcesToApp(win);
                }
            }
        }
        else
        {
            // Text-based path (existing behavior)
            if (EnableLogging)
            {
                try { System.IO.File.WriteAllText(GetLogPath("xaml_content_debug.log"), xamlContent ?? "NULL"); } catch { }
            }
            byte[] xamlBytes;
            if (string.IsNullOrWhiteSpace(xamlContent))
            {
                xamlBytes = Encoding.UTF8.GetBytes("<Window xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" />");
            }
            else
            {
#if ENABLE_WEBVIEW
                PreprocessXamlAndExtractWebViewSources(ref xamlContent);
#endif
                xamlBytes = Encoding.UTF8.GetBytes(xamlContent);
            }
            if (Application.Current == null) new Application();
            try
            {
                using (var stream = new System.IO.MemoryStream(xamlBytes))
                {
                    win = (Window)XamlReader.Load(stream);
                }
                SyncWindowResourcesToApp(win);
                xamlContent = null;
                xamlBytes = null;
                GC.Collect();
            }
            catch (XamlParseException ex)
            {
                string[] xamlLines = Encoding.UTF8.GetString(xamlBytes).Replace("\r\n", "\n").Split('\n');
                string snippet = "Unknown";
                string ahkLine = "Unknown";
                if (ex.LineNumber > 0 && ex.LineNumber <= xamlLines.Length)
                {
                    int startLine = Math.Max(0, ex.LineNumber - 8);
                    int endLine = Math.Min(xamlLines.Length - 1, ex.LineNumber + 8);
                    StringBuilder sb = new StringBuilder();
                    for (int i = startLine; i <= endLine; i++)
                    {
                        string prefix = (i == ex.LineNumber - 1) ? ">> " : "   ";
                        sb.AppendLine(prefix + (i + 1) + "| " + xamlLines[i].TrimEnd());
                    }
                    snippet = sb.ToString().TrimEnd();

                    string errLine = xamlLines[ex.LineNumber - 1];
                    int idx1 = errLine.IndexOf("<!-- [ahk:");
                    if (idx1 != -1)
                    {
                        int idx2 = errLine.IndexOf("] -->", idx1);
                        if (idx2 != -1) ahkLine = errLine.Substring(idx1 + 10, idx2 - (idx1 + 10));
                    }
                    else
                    {
                        for (int i = ex.LineNumber - 1; i >= 0; i--)
                        {
                            int i1 = xamlLines[i].IndexOf("<!-- [ahk:");
                            if (i1 != -1)
                            {
                                int i2 = xamlLines[i].IndexOf("] -->", i1);
                                if (i2 != -1)
                                {
                                    ahkLine = "~" + xamlLines[i].Substring(i1 + 10, i2 - (i1 + 10));
                                    break;
                                }
                            }
                        }
                    }
                }
                string rootCause = ex.Message;
                Exception inner = ex.InnerException;
                while (inner != null) { rootCause = inner.Message; inner = inner.InnerException; }
                throw new Exception("AHK_LINE:" + ahkLine + "\nXAML_SNIPPET:\n" + snippet + "\nREASON:\n" + rootCause + "\n\n" + ex.ToString());
            }
        } // end text-based path
        if (!string.IsNullOrEmpty(scriptName))
        {
            string dumpPath = GetLogPath("AhkWpf_StateDump_" + scriptName + ".ini");
            if (System.IO.File.Exists(dumpPath))
            {
                try
                {
                    string[] lines = System.IO.File.ReadAllLines(dumpPath);
                    System.IO.File.Delete(dumpPath);
                    foreach (string line in lines)
                    {
                        string[] p = line.Split(new[] { '=' }, 2);
                        if (p.Length == 2)
                        {
                            var ctrl = win.FindName(p[0]);
                            if (ctrl != null)
                            {
                                string val = Encoding.UTF8.GetString(Convert.FromBase64String(p[1]));
                                if (ctrl is TextBox) ((TextBox)ctrl).Text = val;
                                else if (ctrl is PasswordBox) ((PasswordBox)ctrl).Password = val;
                                else if (ctrl is ToggleButton) { bool b; if (bool.TryParse(val, out b)) ((ToggleButton)ctrl).IsChecked = b; }
                                else if (ctrl is RangeBase) { double d; if (double.TryParse(val, out d)) ((RangeBase)ctrl).Value = d; }
                                else if (ctrl is ComboBox)
                                {
                                    ComboBox cb = (ComboBox)ctrl;
                                    bool found = false;
                                    foreach (var item in cb.Items)
                                    {
                                        ComboBoxItem cbi = item as ComboBoxItem;
                                        if (cbi != null && cbi.Content != null && cbi.Content.ToString() == val) { cb.SelectedItem = item; found = true; break; }
                                    }
                                    if (!found) cb.Text = val;
                                }
                            }
                        }
                    }
                }
                catch { }
            }
        }

        var dragArea = win.FindName("DragArea") as UIElement;
        if (dragArea != null) dragArea.MouseLeftButtonDown += (s, e) => { try { win.DragMove(); } catch { } };

        var txtLogo = win.FindName("TxtLogo") as UIElement;
        if (txtLogo != null) txtLogo.MouseLeftButtonDown += (s, e) => { try { win.DragMove(); } catch { } };

        var btnClose = win.FindName("BtnClose") as ButtonBase;
        if (btnClose != null) btnClose.Click += (s, e) => { try { win.Close(); } catch { } };

        var btnMaximize = win.FindName("BtnMaximize") as ButtonBase;
        if (btnMaximize != null) btnMaximize.Click += (s, e) => { ToggleMaximized(); };

        var btnMinimize = win.FindName("BtnMinimize") as ButtonBase;
        if (btnMinimize != null) btnMinimize.Click += (s, e) => { win.WindowState = WindowState.Minimized; };
        var btnPin = win.FindName("BtnPin") as ButtonBase;
        if (btnPin != null) btnPin.Click += (s, e) => { win.Topmost = !win.Topmost; };

        win.Resources["BaseWindowRadius"] = new CornerRadius(12);
        if (Application.Current != null) AhkWpfEngine.SetAppResource("BaseWindowRadius", win.Resources["BaseWindowRadius"]);

        win.StateChanged += (s, e) =>
        {
            SendToAhkAsync("EVENT|" + winId + "|Window|StateChanged|" + win.WindowState.ToString() + "\n");
            UpdateSnapState(win);
            OnWindowStateChangedForViewbox();
        };
        // 激活/失活必须异步回 AHK：AHK 侧 WinActivate 走 SetForegroundWindow，前台切换会同步等
        // 目标窗口处理 WM_ACTIVATE；此刻再用同步 SendMessage 把事件塞回 AHK，而 AHK 正卡在
        // WinActivate 里没泵消息 —— 两边互等，只能靠系统超时解开（实测 125~170ms/次）。
        win.Activated += (s, e) =>
        {
            SendToAhkAsync("EVENT|" + winId + "|Window|Activated\n");
        };
        win.Deactivated += (s, e) =>
        {
            SendToAhkAsync("EVENT|" + winId + "|Window|Deactivated\n");
        };
        win.LocationChanged += (s, e) => UpdateSnapState(win);
        win.SizeChanged += (s, e) => { UpdateSnapState(win); FillViewboxIfLetterboxed(); SyncChromeCaption(); };

        win.Loaded += (s, e) =>
        {
            IntPtr hwnd = new WindowInteropHelper(win).Handle;
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);
            FillViewboxViewport();
            SyncChromeCaption();
            // Async: 避免 CREATE_WINDOW 的 SendMessage 与 LoadedHwnd 回调互相嵌套死锁
            SendToAhkAsync("EVENT|" + winId + "|Window|LoadedHwnd|" + hwnd.ToString() + "\n");
            UpdateSnapState(win);
            InheritWindowIconAndTitle(win, ownerHwndStr);
            // 输入限制（Tag="NumOnly" 等）在视觉树建好后一次挂完，主程序只写声明
            AttachInputMasks(win);
            DumpState("Window", "Loaded");
#if ENABLE_WEBVIEW
            InitializeWebView2IfPresent(win);
#endif

            // Aggressively flush the working set from RAM (WPF caches huge amounts of unused startup structures)
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            timer.Tick += (sender, args) =>
            {
                timer.Stop();
                // Popup dialogs are already revealed; flipping Topmost here flashes the chrome.
                if (win.ShowInTaskbar)
                {
                    bool keepTopmost = win.Topmost;
                    win.Topmost = true;
                    win.Topmost = false;
                    if (keepTopmost) win.Topmost = true;
                }
                // 窗口在 Show 时已经正常激活，这里不再补 Activate：强行抢前台会把用户切走的窗口拉回来。
                try { System.Runtime.GCSettings.LargeObjectHeapCompactionMode = System.Runtime.GCLargeObjectHeapCompactionMode.CompactOnce; } catch { }
                GC.Collect(GC.MaxGeneration, GCCollectionMode.Forced, true, true);
                GC.WaitForPendingFinalizers();
                GC.Collect();
                try { EmptyWorkingSet(System.Diagnostics.Process.GetCurrentProcess().Handle); } catch { }
            };
            timer.Start();
        };
        win.Closing += (s, e) =>
        {
            var ownerHwnd = new System.Windows.Interop.WindowInteropHelper(win).Owner;
            if (ownerHwnd != IntPtr.Zero)
            {
                SetWindowPos(ownerHwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0003);
                SetForegroundWindow(ownerHwnd);
            }
            // Async: avoid deadlock when AHK closes via synchronous SendMessage(Update Close)
            SendToAhkAsync("EVENT|" + winId + "|Window|Closing\n");
        };
        win.Closed += (s, e) =>
        {
            ClearLeakedAppImplicitStyles();
            SendToAhkAsync("EVENT|" + winId + "|Window|Closed\n");
            lock (_activeEngines)
            {
                _activeEngines.Remove(winId);
            }
        };

        // Unified event binding — merge all event sources
        // eventsContent may come from: inline data, .bin, or BAML companion .events file
        // eventsFilePath may be: a file path, CSV event data, or "none"
        string allEvents = eventsContent ?? "";
        if (!string.IsNullOrEmpty(eventsFilePath) && eventsFilePath != "none")
        {
            if (System.IO.File.Exists(eventsFilePath))
            {
                // It's a file path — read and delete
                string fileEvents = System.IO.File.ReadAllText(eventsFilePath);
                try { System.IO.File.Delete(eventsFilePath); } catch { }
                allEvents = string.IsNullOrEmpty(allEvents) ? fileEvents : allEvents + "," + fileEvents;
            }
            else if (eventsFilePath.Contains(":"))
            {
                // It's inline CSV event data (e.g. "Window:Loaded,BtnClose:Click")
                allEvents = string.IsNullOrEmpty(allEvents) ? eventsFilePath : allEvents + "," + eventsFilePath;
            }
        }
        if (!string.IsNullOrEmpty(allEvents))
        {
            string[] pairs = allEvents.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            var bound = new System.Collections.Generic.HashSet<string>();
            foreach (string p in pairs)
            {
                string evtStr = p;
                int limitFps = 0;
                bool isQueue = false;
                int atIndex = p.IndexOf('@');
                if (atIndex > 0)
                {
                    evtStr = p.Substring(0, atIndex);
                    string limitStr = p.Substring(atIndex + 1);
                    if (limitStr.EndsWith("Q"))
                    {
                        isQueue = true;
                        limitStr = limitStr.Substring(0, limitStr.Length - 1);
                    }
                    int.TryParse(limitStr, out limitFps);
                }
                // 最多拆 2 段：控件名 / 事件名（事件名可含冒号）
                string[] kv = evtStr.Split(new[] { ':' }, 2);
                if (kv.Length == 2) BindEvent(kv[0], kv[1], limitFps, isQueue);
            }
        }

        ApplyNativeOwner(win, ownerHwndStr);

        eventsContent = null;

        InheritWindowIconAndTitle(win, ownerHwndStr);
#if ENABLE_WEBVIEW
        ConfigureWebView2CreationProperties(win);
#endif
        if (initialUiScale.HasValue && IsUiScalePreset(initialUiScale.Value)) win.Resources["RmtUiScale"] = initialUiScale.Value;
        if (skipUiScale.HasValue) win.Resources["RmtSkipUiScale"] = skipUiScale.Value;
        ShowEngineWindow(win, isDaemon);
    }

    // 失效/子窗口句柄不能当 Owner：CreateWindowEx 会抛「无效的窗口句柄」并打崩引擎。
    private static IntPtr ResolveOwnerHwnd(string ownerHwndStr)
    {
        if (string.IsNullOrEmpty(ownerHwndStr) || ownerHwndStr == "0")
            return IntPtr.Zero;
        try
        {
            IntPtr hwnd = new IntPtr(long.Parse(ownerHwndStr));
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd))
                return IntPtr.Zero;
            const int GWL_STYLE = -16;
            const int WS_CHILD = 0x40000000;
            if ((GetWindowLong(hwnd, GWL_STYLE) & WS_CHILD) != 0)
            {
                IntPtr root = GetAncestor(hwnd, 2); // GA_ROOT
                if (root != IntPtr.Zero && IsWindow(root) && (GetWindowLong(root, GWL_STYLE) & WS_CHILD) == 0)
                    return root;
                return IntPtr.Zero;
            }
            return hwnd;
        }
        catch
        {
            return IntPtr.Zero;
        }
    }

    private static void ApplyNativeOwner(Window win, string ownerHwndStr)
    {
        IntPtr oHwnd = ResolveOwnerHwnd(ownerHwndStr);
        if (oHwnd == IntPtr.Zero)
            return;
        try
        {
            win.Resources["OriginalNativeOwner"] = oHwnd;
            new WindowInteropHelper(win).Owner = oHwnd;
        }
        catch { }
    }

    // Keep the unconstrained normal size separate from the last applied (possibly clamped)
    // size. Multiplying the latter on each preset change permanently shrinks large dialogs.
    bool _uiScalePrepared, _uiScaleReady, _uiScaleBusy, _uiScaleFluid;
    bool _viewboxFilledForMax, _viewboxSavedSizeToContentSet, _viewboxReassertingMax, _viewboxDidReassertMax;
    SizeToContent _viewboxSavedSizeToContent;
    double _uiScaleFactor = 1, _uiScaleVisual = 1;
    double _uiScaleBaseWidth, _uiScaleBaseHeight, _uiScaleLastWidth, _uiScaleLastHeight;
    double _uiScaleMinWidth, _uiScaleMinHeight, _uiScaleMaxWidth, _uiScaleMaxHeight;
    double _viewboxDesignW, _viewboxDesignH;
    Transform _uiScaleOriginalTransform;

    private static bool IsUiScalePreset(double value)
    {
        return value == 0.8 || value == 0.9 || value == 1 || value == 1.1 || value == 1.25 || value == 1.5;
    }

    private bool SkipUiScale()
    {
        return win == null || win.AllowsTransparency
            || (win.Resources["RmtSkipUiScale"] is bool && (bool)win.Resources["RmtSkipUiScale"]);
    }

    private void PrepareWindowUiScale()
    {
        if (_uiScalePrepared || win == null) return;
        _uiScalePrepared = true;
        EnsureUiScalePopupHooks();
        bool skip = SkipUiScale();
        var root = win.Content as FrameworkElement;
        if (root == null) return;
        _uiScaleFluid = win.Resources["RmtFluidDialogLayout"] is bool && (bool)win.Resources["RmtFluidDialogLayout"];
        if (!_uiScaleFluid && !(root is Viewbox) && (!skip || !double.IsNaN(win.Width)))
        {
            if (double.IsNaN(root.Width) && win.Width > 0) root.Width = win.Width;
            if (double.IsNaN(root.Height) && win.Height > 0) root.Height = win.Height;
            if (root.Width > 1) _viewboxDesignW = root.Width;
            if (root.Height > 1) _viewboxDesignH = root.Height;
            win.Content = null;
            win.Content = new Viewbox { Stretch = Stretch.Uniform, StretchDirection = StretchDirection.Both, Child = root };
        }
        // Opting out skips only user presets, not the pre-existing resize Viewbox.
        if (skip) return;
        _uiScaleReady = true;
        _uiScaleOriginalTransform = root.LayoutTransform;
        _uiScaleMinWidth = win.MinWidth;
        _uiScaleMinHeight = win.MinHeight;
        _uiScaleMaxWidth = win.MaxWidth;
        _uiScaleMaxHeight = win.MaxHeight;
        _uiScaleBaseWidth = win.Width;
        _uiScaleBaseHeight = win.Height;
        double initial = win.Resources["RmtUiScale"] is double ? (double)win.Resources["RmtUiScale"] : 1;
        if (!IsUiScalePreset(initial)) initial = 1;
        ApplyUiScale(initial, true);
        // Loaded runs before the first frame is revealed. It also resolves SizeToContent,
        // native chrome insets, centered placement and the window's actual monitor/DPI.
        win.Loaded += (s, e) => { ApplyUiScale(_uiScaleFactor, true); };
        WindowState lastState = win.WindowState;
        win.StateChanged += (s, e) =>
        {
            WindowState previousState = lastState;
            lastState = win.WindowState;
            if (win.WindowState == WindowState.Minimized) return;
            // A user may resize and immediately maximize without any query or preset command.
            // At StateChanged ActualWidth is already maximized, but RestoreBounds is still normal.
            if (!_uiScaleBusy && !SkipUiScale()
                && previousState == WindowState.Normal && win.IsLoaded && win.WindowState != WindowState.Normal)
            {
                Rect restore = win.RestoreBounds;
                if (restore.Width > 1 && Math.Abs(restore.Width - _uiScaleLastWidth) > 2)
                    _uiScaleBaseWidth = restore.Width / _uiScaleFactor;
                if (restore.Height > 1 && Math.Abs(restore.Height - _uiScaleLastHeight) > 2)
                    _uiScaleBaseHeight = restore.Height / _uiScaleFactor;
            }
            // Viewport fill is owned by OnWindowStateChangedForViewbox so it can wait for
            // the maximized HWND size instead of retargeting against the restore Viewbox.
        };
    }

    [DllImport("user32.dll", EntryPoint = "MonitorFromRect")]
    private static extern IntPtr UiScaleMonitorFromRect(ref RECT rect, int flags);
    [DllImport("user32.dll", EntryPoint = "GetDpiForWindow")]
    private static extern uint UiScaleGetDpiForWindow(IntPtr hwnd);
    [DllImport("gdi32.dll", EntryPoint = "GetDeviceCaps")]
    private static extern int UiScaleGetDeviceCaps(IntPtr dc, int index);

    private static double UiScaleSystemDpi()
    {
        // GetDpiForWindow/GetDpiForSystem do not exist on Windows 7.
        IntPtr dc = GetDC(IntPtr.Zero);
        if (dc == IntPtr.Zero) return 1;
        try { return Math.Max(96, UiScaleGetDeviceCaps(dc, 88)) / 96.0; } // LOGPIXELSX
        finally { ReleaseDC(IntPtr.Zero, dc); }
    }

    private Rect UiScaleWorkArea()
    {
        var helper = new WindowInteropHelper(win);
        IntPtr hwnd = helper.Handle;
        if (hwnd == IntPtr.Zero) hwnd = helper.Owner;
        IntPtr monitor = MonitorFromWindow(hwnd, 2);
        double dpiX = UiScaleSystemDpi(), dpiY = dpiX;
        var source = PresentationSource.FromVisual(win);
        if (source != null && source.CompositionTarget != null)
        {
            dpiX = source.CompositionTarget.TransformToDevice.M11;
            dpiY = source.CompositionTarget.TransformToDevice.M22;
        }
        else if (hwnd != IntPtr.Zero)
        {
            try { uint dpi = UiScaleGetDpiForWindow(hwnd); if (dpi > 0) dpiX = dpiY = dpi / 96.0; } catch { }
        }
        if (helper.Handle == IntPtr.Zero && helper.Owner == IntPtr.Zero && !double.IsNaN(win.Left) && !double.IsNaN(win.Top))
        {
            RECT rect = new RECT();
            rect.left = (int)(win.Left * dpiX); rect.top = (int)(win.Top * dpiY);
            rect.right = rect.left + (int)(Math.Max(1, double.IsNaN(win.Width) ? 1 : win.Width) * dpiX);
            rect.bottom = rect.top + (int)(Math.Max(1, double.IsNaN(win.Height) ? 1 : win.Height) * dpiY);
            monitor = UiScaleMonitorFromRect(ref rect, 2);
        }
        MONITORINFO info = new MONITORINFO();
        info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (monitor != IntPtr.Zero && GetMonitorInfo(monitor, ref info))
            return new Rect(info.rcWork.left / dpiX, info.rcWork.top / dpiY,
                (info.rcWork.right - info.rcWork.left) / dpiX, (info.rcWork.bottom - info.rcWork.top) / dpiY);
        return SystemParameters.WorkArea;
    }

    private void RetargetUiScaleContent(double visualScale)
    {
        var box = win.Content as Viewbox;
        var child = box == null ? null : box.Child as FrameworkElement;
        if (child == null) return;
        double chromeW, chromeH;
        RmtCommonStyles.GetWindowChromeInset(win, out chromeW, out chromeH);
        // Width/Height are restore bounds while maximized, not the displayed viewport.
        double width = win.WindowState == WindowState.Maximized && win.ActualWidth > 1
            ? win.ActualWidth : win.Width - chromeW;
        double height = win.WindowState == WindowState.Maximized && win.ActualHeight > 1
            ? win.ActualHeight : win.Height - chromeH;
        if (!(width > 1)) width = box.ActualWidth;
        if (!(height > 1)) height = box.ActualHeight;
        Thickness margin = child.Margin;
        if (width > 1) child.Width = Math.Max(1, width / visualScale - margin.Left - margin.Right);
        bool autoHeight = win.SizeToContent == SizeToContent.Height || win.SizeToContent == SizeToContent.WidthAndHeight;
        if (height > 1 && (!autoHeight || win.WindowState == WindowState.Maximized))
            child.Height = Math.Max(1, height / visualScale - margin.Top - margin.Bottom);
        else if (autoHeight) child.Height = double.NaN;
        box.HorizontalAlignment = HorizontalAlignment.Stretch;
        box.VerticalAlignment = VerticalAlignment.Stretch;
        win.UpdateLayout();
    }

    private void ApplyUiScale(double factor, bool refresh = false)
    {
        if (!IsUiScalePreset(factor) || SkipUiScale() || _uiScaleBusy) return;
        if (!_uiScalePrepared) PrepareWindowUiScale();
        if (!_uiScaleReady || (!refresh && factor == _uiScaleFactor)) return;
        if (!refresh) CaptureUiScaleNormalSize();
        _uiScaleBusy = true;
        try
        {
            if (!refresh) CloseUiScaleNativePopups();
            win.UpdateLayout();
            bool normal = win.WindowState == WindowState.Normal;
            if (!refresh && !_uiScaleFluid && win.IsLoaded)
            {
                double actualScale = GetUiVisualScale();
                if (actualScale > 0) _uiScaleVisual = actualScale;
            }
            if (_uiScaleLastWidth == 0 && !_uiScaleFluid)
            {
                double initialScale = RmtCommonStyles.WindowContentVisualScale(win);
                if (initialScale > 0) _uiScaleVisual = initialScale;
            }
            _uiScaleVisual *= factor / _uiScaleFactor;
            _uiScaleFactor = factor;
            win.Resources["RmtUiScale"] = factor;
            Rect area = UiScaleWorkArea();
            // Scale constraints too: otherwise a design MinWidth can defeat 80%, or exceed
            // the current monitor. Work-area limits must win over the original minimum.
            win.MinWidth = Math.Min(_uiScaleMinWidth * factor, area.Width);
            win.MinHeight = Math.Min(_uiScaleMinHeight * factor, area.Height);
            double capW = Math.Max(win.MinWidth, Math.Min(_uiScaleMaxWidth * factor, area.Width));
            double capH = Math.Max(win.MinHeight, Math.Min(_uiScaleMaxHeight * factor, area.Height));
            if (win.WindowState == WindowState.Maximized)
            {
                // MaxWidth/MaxHeight clamp the maximized HWND; WPF then centers that smaller
                // surface and leaves the leftover work-area as left/right letterbox.
                win.MaxWidth = double.PositiveInfinity;
                win.MaxHeight = double.PositiveInfinity;
            }
            else
            {
                win.MaxWidth = capW;
                win.MaxHeight = capH;
            }
            double width = Math.Max(win.MinWidth, Math.Min(capW, _uiScaleBaseWidth * factor));
            double height = Math.Max(win.MinHeight, Math.Min(capH, _uiScaleBaseHeight * factor));
            // Setting Width/Height while maximized can relayout Content at restore size
            // before the Viewbox has the maximized viewport, which recreates the letterbox.
            if (win.WindowState != WindowState.Maximized)
            {
                if (width > 0) win.Width = width;
                if (height > 0 && win.SizeToContent != SizeToContent.Height && win.SizeToContent != SizeToContent.WidthAndHeight)
                    win.Height = height;
            }
            if (_uiScaleFluid)
            {
                var root = win.Content as FrameworkElement;
                if (root != null)
                {
                    var transform = new TransformGroup();
                    if (_uiScaleOriginalTransform != null) transform.Children.Add(_uiScaleOriginalTransform);
                    transform.Children.Add(new ScaleTransform(factor, factor));
                    root.LayoutTransform = transform;
                }
            }
            else if (win.WindowState != WindowState.Maximized)
                RetargetUiScaleContent(_uiScaleVisual);
            win.UpdateLayout();
            if (normal)
            {
                double shownW = win.IsLoaded ? win.ActualWidth : width;
                double shownH = win.IsLoaded ? win.ActualHeight : height;
                if (!double.IsNaN(win.Left) && shownW > 0) win.Left = Math.Max(area.Left, Math.Min(win.Left, area.Right - shownW));
                if (!double.IsNaN(win.Top) && shownH > 0) win.Top = Math.Max(area.Top, Math.Min(win.Top, area.Bottom - shownH));
                _uiScaleLastWidth = shownW;
                _uiScaleLastHeight = shownH;
                if (!(_uiScaleBaseWidth > 0) && shownW > 0) _uiScaleBaseWidth = shownW / factor;
                if (!(_uiScaleBaseHeight > 0) && shownH > 0) _uiScaleBaseHeight = shownH / factor;
            }
            SyncChromeCaption();
            RefreshUiScalePopups();
        }
        finally { _uiScaleBusy = false; }
    }

    private void CaptureUiScaleNormalSize()
    {
        if (!_uiScaleReady || _uiScaleBusy || win == null || !win.IsLoaded || win.WindowState != WindowState.Normal) return;
        win.UpdateLayout();
        // Only a genuine resize since our last application replaces the unclipped baseline.
        if (win.ActualWidth > 1 && Math.Abs(win.ActualWidth - _uiScaleLastWidth) > 2)
            _uiScaleBaseWidth = win.ActualWidth / _uiScaleFactor;
        if (win.ActualHeight > 1 && Math.Abs(win.ActualHeight - _uiScaleLastHeight) > 2)
            _uiScaleBaseHeight = win.ActualHeight / _uiScaleFactor;
    }

    private double GetUiBaseDimension(bool width)
    {
        CaptureUiScaleNormalSize();
        double baseline = width ? _uiScaleBaseWidth : _uiScaleBaseHeight;
        if (_uiScaleReady && baseline > 0) return baseline;
        if (win == null) return 0;
        double actual = width ? win.ActualWidth : win.ActualHeight;
        if (!(actual > 0)) actual = width ? win.Width : win.Height;
        return actual > 0 ? actual / _uiScaleFactor : 0;
    }

    private double GetUiVisualScale()
    {
        if (win == null) return 1;
        win.UpdateLayout();
        var box = win.Content as Viewbox;
        var root = box == null ? win.Content as FrameworkElement : box.Child as FrameworkElement;
        double actual = UiScaleElementVisualScale(root);
        return actual > 0 ? actual : _uiScaleVisual;
    }

    private static double UiScaleElementVisualScale(FrameworkElement element)
    {
        if (element == null) return double.NaN;
        var source = PresentationSource.FromVisual(element);
        var root = source == null ? null : source.RootVisual as Visual;
        if (root == null) return double.NaN;
        try
        {
            var transform = element.TransformToAncestor(root);
            Point origin = transform.Transform(new Point(0, 0));
            Point unit = transform.Transform(new Point(1, 0));
            return (unit - origin).Length;
        }
        catch { return double.NaN; }
    }

    // Popup HWNDs are outside the owner's visual tree. Scale their complete design surface
    // (padding, icons, borders and fonts), not just the inherited FontSize. Weak keys avoid
    // retaining closed dialogs, and original transforms prevent accumulation on reopening.
    private sealed class UiScalePopupState
    {
        public UiScalePopupState() { }
        internal Transform Original;
        internal WeakReference Owner;
    }
    private static bool _uiScalePopupHooks;
    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<FrameworkElement, UiScalePopupState>
        _uiScalePopups = new System.Runtime.CompilerServices.ConditionalWeakTable<FrameworkElement, UiScalePopupState>();
    private static readonly System.Collections.Generic.List<WeakReference> _uiScalePopupRoots = new System.Collections.Generic.List<WeakReference>();

    private static void EnsureUiScalePopupHooks()
    {
        if (_uiScalePopupHooks) return;
        _uiScalePopupHooks = true;
        // Unlike Loaded class handlers, these routed opening events are raised without
        // per-instance Loaded flags. Only disconnected surfaces need compensation:
        // Popup/ComboBox inside a Viewbox already receive WPF's native whole-tree scale.
        EventManager.RegisterClassHandler(typeof(ToolTip), ToolTip.OpenedEvent,
            new RoutedEventHandler((sender, args) => ScaleUiPopup((ToolTip)sender)), true);
        EventManager.RegisterClassHandler(typeof(ContextMenu), ContextMenu.OpenedEvent,
            new RoutedEventHandler((sender, args) => ScaleUiPopup((ContextMenu)sender)), true);
    }

    private static void ScaleUiPopup(FrameworkElement surface)
    {
        var tip = surface as ToolTip;
        var menu = surface as ContextMenu;
        FrameworkElement root = surface;
        FrameworkElement target = tip != null ? tip.PlacementTarget as FrameworkElement
            : menu != null ? menu.PlacementTarget as FrameworkElement : null;
        if (target == null) return;
        Window owner = Window.GetWindow(target);
        if (owner != null && (owner.AllowsTransparency
            || (owner.Resources["RmtSkipUiScale"] is bool && (bool)owner.Resources["RmtSkipUiScale"]))) return;
        double scale = UiScaleElementVisualScale(target);
        if (!(scale > 0) || double.IsInfinity(scale)) return;
        var state = _uiScalePopups.GetOrCreateValue(root);
        if (state.Original == null)
        {
            state.Original = root.LayoutTransform;
            _uiScalePopupRoots.Add(new WeakReference(root));
        }
        state.Owner = new WeakReference(surface);
        var group = new TransformGroup();
        group.Children.Add(state.Original);
        group.Children.Add(new ScaleTransform(scale, scale));
        root.LayoutTransform = group;
        root.UpdateLayout();
    }

    private void CloseUiScaleNativePopups()
    {
        // Native Popup transforms are captured when opened. Dismiss transient drop-downs
        // on a preset change; the next opening gets WPF's new scale without double scaling.
        var popups = new System.Collections.Generic.List<Popup>();
        var combos = new System.Collections.Generic.List<ComboBox>();
        WalkVisualTree(win, element =>
        {
            var popup = element as Popup;
            var combo = element as ComboBox;
            if (popup != null) popups.Add(popup);
            if (combo != null) combos.Add(combo);
        });
        foreach (var combo in combos) if (combo.IsDropDownOpen) combo.SetCurrentValue(ComboBox.IsDropDownOpenProperty, false);
        foreach (var popup in popups) if (popup.IsOpen) popup.SetCurrentValue(Popup.IsOpenProperty, false);
    }

    private static void RefreshUiScalePopups()
    {
        for (int i = _uiScalePopupRoots.Count - 1; i >= 0; i--)
        {
            var root = _uiScalePopupRoots[i].Target as FrameworkElement;
            if (root == null) { _uiScalePopupRoots.RemoveAt(i); continue; }
            UiScalePopupState state;
            if (!root.IsVisible || !_uiScalePopups.TryGetValue(root, out state) || state.Owner == null) continue;
            var surface = state.Owner.Target as FrameworkElement;
            if (surface != null) ScaleUiPopup(surface);
        }
    }

    bool _fillViewboxBusy;
    private void PrepareMaximizedLayoutConstraints()
    {
        if (win == null) return;
        try
        {
            win.MaxWidth = double.PositiveInfinity;
            win.MaxHeight = double.PositiveInfinity;
        }
        catch { }
        if (!_viewboxSavedSizeToContentSet)
        {
            _viewboxSavedSizeToContent = win.SizeToContent;
            _viewboxSavedSizeToContentSet = true;
        }
        // Width/Height/Left/Top while maximized rewrite the restore rectangle.
        // That is what pinned SizeToContent windows at the work-area origin (top-left).
        if (win.WindowState == WindowState.Maximized)
        {
            if (win.SizeToContent != SizeToContent.Manual)
                win.SizeToContent = SizeToContent.Manual;
            return;
        }
        double left = win.Left, top = win.Top;
        double liveW = win.ActualWidth > 1 ? win.ActualWidth : win.Width;
        double liveH = win.ActualHeight > 1 ? win.ActualHeight : win.Height;
        if (win.SizeToContent != SizeToContent.Manual)
            win.SizeToContent = SizeToContent.Manual;
        if (liveW > 1) win.Width = liveW;
        if (liveH > 1) win.Height = liveH;
        if (!double.IsNaN(left)) win.Left = left;
        if (!double.IsNaN(top)) win.Top = top;
    }

    private void RestoreMaximizedLayoutConstraints()
    {
        if (win == null || !_viewboxSavedSizeToContentSet) return;
        try
        {
            SizeToContent saved = _viewboxSavedSizeToContent;
            win.SizeToContent = saved;
            if (saved == SizeToContent.Height || saved == SizeToContent.WidthAndHeight)
                win.Height = double.NaN;
        }
        catch { }
        _viewboxSavedSizeToContentSet = false;
        _viewboxDidReassertMax = false;
    }

    private void ToggleMaximized()
    {
        if (win == null) return;
        if (win.WindowState == WindowState.Maximized)
            win.WindowState = WindowState.Normal;
        else
        {
            PrepareMaximizedLayoutConstraints();
            win.WindowState = WindowState.Maximized;
        }
    }

    private void ApplyRequestedWindowState(string state)
    {
        if (win == null || string.IsNullOrEmpty(state)) return;
        if (state.Equals("Maximized", StringComparison.OrdinalIgnoreCase))
        {
            if (win.WindowState != WindowState.Maximized)
            {
                PrepareMaximizedLayoutConstraints();
                win.WindowState = WindowState.Maximized;
            }
            return;
        }
        if (state.Equals("Minimized", StringComparison.OrdinalIgnoreCase))
        {
            win.WindowState = WindowState.Minimized;
            return;
        }
        win.WindowState = WindowState.Normal;
    }

    private void OnWindowStateChangedForViewbox()
    {
        if (win == null || win.WindowState == WindowState.Minimized) return;
        // Viewbox windows restore SizeToContent after the child is reset to design size.
        if (win.WindowState != WindowState.Maximized && !(win.Content is Viewbox))
            RestoreMaximizedLayoutConstraints();
        win.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Render, new Action(() =>
        {
            if (win == null || win.WindowState == WindowState.Minimized) return;
            FillViewboxViewport();
            SyncChromeCaption();
        }));
    }

    private void FillViewboxIfLetterboxed()
    {
        if (win == null || win.WindowState == WindowState.Minimized) return;
        if (win.WindowState != WindowState.Maximized && !ViewboxWouldLetterbox()) return;
        FillViewboxViewport();
    }

    private bool ViewboxWouldLetterbox()
    {
        var box = win.Content as Viewbox;
        var child = box == null ? null : box.Child as FrameworkElement;
        if (box == null || child == null) return false;
        double hostW = box.ActualWidth, hostH = box.ActualHeight;
        double childW = child.ActualWidth > 1 ? child.ActualWidth : child.Width;
        double childH = child.ActualHeight > 1 ? child.ActualHeight : child.Height;
        if (!(hostW > 1) || !(hostH > 1) || !(childW > 1) || !(childH > 1)) return false;
        double scaleW = hostW / childW, scaleH = hostH / childH;
        double larger = Math.Max(scaleW, scaleH);
        if (!(larger > 0)) return false;
        return Math.Abs(scaleW - scaleH) / larger > 0.02;
    }

    private void FillViewboxViewport()
    {
        if (win == null || _fillViewboxBusy) return;
        _fillViewboxBusy = true;
        try
        {
            var box = win.Content as Viewbox;
            var child = box == null ? null : box.Child as FrameworkElement;
            if (box == null || child == null) return;

            if (win.WindowState == WindowState.Maximized)
            {
                Rect area = UiScaleWorkArea();
                bool tooSmall = area.Width > 1 && win.ActualWidth > 1 && win.ActualWidth < area.Width * 0.85;
                if (!_viewboxDidReassertMax && (win.SizeToContent != SizeToContent.Manual || tooSmall))
                {
                    _viewboxDidReassertMax = true;
                    _viewboxReassertingMax = true;
                    try
                    {
                        if (tooSmall)
                        {
                            win.WindowState = WindowState.Normal;
                            PrepareMaximizedLayoutConstraints();
                            win.WindowState = WindowState.Maximized;
                            return;
                        }
                        PrepareMaximizedLayoutConstraints();
                    }
                    finally { _viewboxReassertingMax = false; }
                }
                if (!(_viewboxDesignW > 1) && child.Width > 1) _viewboxDesignW = child.Width;
                if (!(_viewboxDesignH > 1) && child.Height > 1) _viewboxDesignH = child.Height;
                win.UpdateLayout();
                area = UiScaleWorkArea();
                // SizeToContent windows keep ActualWidth at the design width until Manual
                // takes effect; the work area is the maximized HWND size we actually want.
                double vpW = area.Width > 1 ? area.Width : (win.ActualWidth > 1 ? win.ActualWidth : box.ActualWidth);
                double vpH = area.Height > 1 ? area.Height : (win.ActualHeight > 1 ? win.ActualHeight : box.ActualHeight);
                if (win.ActualWidth > vpW + 1) vpW = win.ActualWidth;
                if (win.ActualHeight > vpH + 1) vpH = win.ActualHeight;
                if (!(vpW > 1) || !(vpH > 1)) return;
                double designW = _viewboxDesignW > 1 ? _viewboxDesignW : (child.Width > 1 ? child.Width : child.ActualWidth);
                double designH = _viewboxDesignH > 1 ? _viewboxDesignH : (child.Height > 1 ? child.Height : child.ActualHeight);
                double scale;
                if (designW > 1 && designH > 1)
                    scale = Math.Min(vpW / designW, vpH / designH);
                else
                {
                    scale = _uiScaleReady ? _uiScaleVisual : RmtCommonStyles.WindowContentVisualScale(win);
                    if (!(scale > 0)) scale = 1;
                }
                if (scale < 0.2) scale = 0.2;
                if (scale > 4) scale = 4;
                child.Width = Math.Max(1, vpW / scale);
                child.Height = Math.Max(1, vpH / scale);
                child.HorizontalAlignment = HorizontalAlignment.Stretch;
                child.VerticalAlignment = VerticalAlignment.Stretch;
                box.HorizontalAlignment = HorizontalAlignment.Stretch;
                box.VerticalAlignment = VerticalAlignment.Stretch;
                box.Stretch = Stretch.Fill;
                box.StretchDirection = StretchDirection.Both;
                _viewboxFilledForMax = true;
                box.UpdateLayout();
                return;
            }

            if (_viewboxFilledForMax)
            {
                if (_viewboxDesignW > 1) child.Width = _viewboxDesignW;
                bool autoHeight = _viewboxSavedSizeToContentSet
                    && (_viewboxSavedSizeToContent == SizeToContent.Height
                        || _viewboxSavedSizeToContent == SizeToContent.WidthAndHeight);
                if (autoHeight) child.Height = double.NaN;
                else if (_viewboxDesignH > 1) child.Height = _viewboxDesignH;
                box.Stretch = Stretch.Uniform;
                box.StretchDirection = StretchDirection.Both;
                RestoreMaximizedLayoutConstraints();
                _viewboxFilledForMax = false;
                box.UpdateLayout();
            }

            double chromeW, chromeH;
            RmtCommonStyles.GetWindowChromeInset(win, out chromeW, out chromeH);
            double scaleN = _uiScaleReady ? _uiScaleVisual : RmtCommonStyles.WindowContentVisualScale(win);
            RmtCommonStyles.NormalizeWindowContentForResize(win, scaleN,
                chromeW, chromeH, preserveAutoHeight: win.SizeToContent == SizeToContent.Height);
        }
        catch { }
        finally { _fillViewboxBusy = false; }
    }

    // 标题栏热区是窗口 DIP，不跟着根内容 Viewbox 缩放，且 WPF 判定的范围是
    // 「ResizeBorderThickness.Top + CaptionHeight」两段合起来（WindowChromeWorker._HitTestNca）。
    // 所以 CaptionHeight 要按「视觉标题栏高度 × 缩放比 − 顶部缩放边框」换算：
    // 少了会把缩放边框算漏，热区越过标题栏压到页签条上，那一段点不动、也不出悬停高亮。
    private void SyncChromeCaption()
    {
        if (win == null) return;
        try
        {
            var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
            if (chrome == null) return;
            if (_chromeCaptionDesign < 0) _chromeCaptionDesign = chrome.CaptionHeight;
            if (!(_chromeCaptionDesign > 0)) return;
            var hostBox = win.Content as Viewbox;
            if (hostBox == null && !_uiScaleFluid) return;
            double scale;
            if (_uiScaleFluid)
            {
                var root = win.Content as FrameworkElement;
                if (root == null) return;
                Matrix matrix = root.LayoutTransform.Value;
                scale = Math.Sqrt(matrix.M21 * matrix.M21 + matrix.M22 * matrix.M22);
            }
            else
            {
                scale = RmtCommonStyles.WindowContentVisualScale(win);
                if (!(scale > 0)) return;
            }
            double target = Math.Round(_chromeCaptionDesign * scale - chrome.ResizeBorderThickness.Top, 2);
            if (target < 0) target = 0;
            if (Math.Abs(chrome.CaptionHeight - target) > 0.5)
                chrome.CaptionHeight = target;
        }
        catch { }
    }

    private void ShowEngineWindow(Window win, bool isDaemon, bool startHidden = false)
    {
        PrepareWindowUiScale();
        // Capture the opening monitor before Show changes the foreground window.
        IntPtr openingOwner = new WindowInteropHelper(win).Owner;
        IntPtr openingMonitor = MonitorFromWindow(openingOwner != IntPtr.Zero ? openingOwner : GetForegroundWindow(), 2);
        Action placeEditor = () => CenterEditor(openingMonitor);
        try
        {
            firstFrame = new RmtFirstFrame(win, waitForInitialUpdates, startHidden, placeEditor);
            ApplyTaskbarExStyle(win);
            if (startHidden) win.ShowActivated = false;
            if (isDaemon)
            {
                win.Show();
            }
            else
            {
                win.ShowDialog();
            }
        }
        catch (System.ComponentModel.Win32Exception)
        {
            try { new WindowInteropHelper(win).Owner = IntPtr.Zero; } catch { }
            if (win.Resources.Contains("OriginalNativeOwner"))
                win.Resources.Remove("OriginalNativeOwner");
            if (firstFrame == null)
                firstFrame = new RmtFirstFrame(win, waitForInitialUpdates, startHidden, placeEditor);
            if (isDaemon)
            {
                ApplyTaskbarExStyle(win);
                if (startHidden)
                    win.ShowActivated = false;
                win.Show();
            }
            else
            {
                win.ShowDialog();
            }
        }
    }

    private void CenterEditor(IntPtr monitor)
    {
        if (win.WindowState != WindowState.Normal
            || (win.FindName("MacroEditorTitle") == null && win.FindName("CmdEditorTitle") == null)
            || win.WindowStartupLocation != WindowStartupLocation.CenterScreen) return;
        var source = PresentationSource.FromVisual(win);
        if (source == null || source.CompositionTarget == null) return;
        MONITORINFO info = new MONITORINFO();
        info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(monitor, ref info)) return;
        Matrix dpi = source.CompositionTarget.TransformToDevice;
        double width = (info.rcWork.right - info.rcWork.left) / dpi.M11;
        double height = (info.rcWork.bottom - info.rcWork.top) / dpi.M22;
        // Final UI/font scaling has settled. Keep the entire Viewbox inside the work area.
        win.MinWidth = Math.Min(win.MinWidth, width);
        win.MinHeight = Math.Min(win.MinHeight, height);
        win.MaxWidth = Math.Min(win.MaxWidth, width);
        win.MaxHeight = Math.Min(win.MaxHeight, height);
        // Browser actions show different rows. Preserve SizeToContent so switching actions
        // can still change the height after the initial placement has completed.
        if (win.SizeToContent == SizeToContent.Manual || win.SizeToContent == SizeToContent.Height)
            win.Width = Math.Min(win.ActualWidth, width);
        if (win.SizeToContent == SizeToContent.Manual || win.SizeToContent == SizeToContent.Width)
            win.Height = Math.Min(win.ActualHeight, height);
        win.UpdateLayout();
        win.Left = info.rcWork.left / dpi.M11 + Math.Max(0, (width - win.ActualWidth) / 2);
        win.Top = info.rcWork.top / dpi.M22 + Math.Max(0, (height - win.ActualHeight) / 2);
    }

    // 有属主的窗口默认不占任务栏位。RMT 要「压在主窗口上方 + 自己有一个任务栏按钮」，
    // 所以补 WS_EX_APPWINDOW。关键是得在 Show 之前打上：以前是在窗口已经显示后由 AHK 补位，
    // 还得靠 hide/show 逼任务栏重新登记 —— 那两步一次 125ms，且会让已显示的窗口闪一下。
    private static void ApplyTaskbarExStyle(Window win)
    {
        try
        {
            if (win == null || !win.ShowInTaskbar)
                return;   // ShowInTaskbar=False 的弹窗本来就不该有任务栏按钮
            var helper = new System.Windows.Interop.WindowInteropHelper(win);
            IntPtr h = helper.Handle;
            if (h == IntPtr.Zero)
                return;   // 没提前建句柄的窗口不在这里动样式，交回 AHK 侧兜底
            int ex = GetWindowLong(h, -20);
            if ((ex & 0x40000) == 0)                        // WS_EX_APPWINDOW
                SetWindowLong(h, -20, new IntPtr(ex | 0x40000));
        }
        catch { }
    }

    private void InheritWindowIconAndTitle(Window win, string ownerHwndStr)
    {
        try
        {
            if (string.IsNullOrEmpty(win.Title))
            {
                string extractedTitle = null;
                var dragArea = win.FindName("DragArea") as FrameworkElement;
                if (dragArea != null)
                {
                    WalkLogicalOrVisualTree(dragArea, (DependencyObject d) =>
                    {
                        if (extractedTitle != null) return;
                        if (d is TextBlock)
                        {
                            var tb = (TextBlock)d;
                            if (!string.IsNullOrEmpty(tb.Text))
                            {
                                extractedTitle = tb.Text;
                            }
                        }
                    });
                }
                if (string.IsNullOrEmpty(extractedTitle))
                {
                    WalkLogicalOrVisualTree(win, (DependencyObject d) =>
                    {
                        if (extractedTitle != null) return;
                        if (d is TextBlock)
                        {
                            var tb = (TextBlock)d;
                            if (tb.Name == "TitleText" || tb.Name == "WindowTitle" || tb.Name == "HeaderTitle" || tb.Name == "DialogTitle")
                            {
                                extractedTitle = tb.Text;
                            }
                        }
                    });
                }

                if (!string.IsNullOrEmpty(extractedTitle))
                {
                    win.Title = extractedTitle;
                }
                else if (ownerHwndStr != "0")
                {
                    try
                    {
                        IntPtr oHwnd = new IntPtr(long.Parse(ownerHwndStr));
                        if (oHwnd != IntPtr.Zero)
                        {
                            StringBuilder sb = new StringBuilder(256);
                            GetWindowText(oHwnd, sb, sb.Capacity);
                            if (sb.Length > 0)
                            {
                                win.Title = sb.ToString();
                            }
                        }
                    }
                    catch { }
                }
            }

            if (win.Icon == null)
            {
                IntPtr hIcon = IntPtr.Zero;

                if (ownerHwndStr != "0")
                {
                    try
                    {
                        IntPtr oHwnd = new IntPtr(long.Parse(ownerHwndStr));
                        if (oHwnd != IntPtr.Zero)
                        {
                            hIcon = SendMessage(oHwnd, 0x007F /* WM_GETICON */, new IntPtr(1 /* ICON_BIG */), IntPtr.Zero);
                            if (hIcon == IntPtr.Zero)
                            {
                                hIcon = SendMessage(oHwnd, 0x007F /* WM_GETICON */, new IntPtr(0 /* ICON_SMALL */), IntPtr.Zero);
                            }
                            if (hIcon == IntPtr.Zero)
                            {
                                hIcon = GetClassLongPtr(oHwnd, -14 /* GCLP_HICON */);
                            }
                            if (hIcon == IntPtr.Zero)
                            {
                                hIcon = GetClassLongPtr(oHwnd, -34 /* GCLP_HICONSM */);
                            }
                        }
                    }
                    catch { }
                }

                if (hIcon == IntPtr.Zero)
                {
                    try
                    {
                        var proc = System.Diagnostics.Process.GetCurrentProcess();
                        IntPtr mainHwnd = proc.MainWindowHandle;
                        if (mainHwnd != IntPtr.Zero)
                        {
                            hIcon = SendMessage(mainHwnd, 0x007F /* WM_GETICON */, new IntPtr(1 /* ICON_BIG */), IntPtr.Zero);
                            if (hIcon == IntPtr.Zero)
                            {
                                hIcon = GetClassLongPtr(mainHwnd, -14 /* GCLP_HICON */);
                            }
                        }
                        if (hIcon == IntPtr.Zero)
                        {
                            string exePath = proc.MainModule.FileName;
                            IntPtr[] largeIcons = new IntPtr[1] { IntPtr.Zero };
                            uint extracted = ExtractIconEx(exePath, 0, largeIcons, null, 1);
                            if (extracted > 0 && largeIcons[0] != IntPtr.Zero)
                            {
                                hIcon = largeIcons[0];
                            }
                        }
                    }
                    catch { }
                }

                if (hIcon != IntPtr.Zero)
                {
                    win.Icon = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                        hIcon,
                        System.Windows.Int32Rect.Empty,
                        System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions()
                    );
                }
            }
        }
        catch { }
    }


    private void UpdateSnapState(Window win)
    {
        if (win.AllowsTransparency)
        {
            var btnMaximizeTxt2 = win.FindName("BtnMaximizeTxt") as TextBlock;
            if (btnMaximizeTxt2 != null)
            {
                btnMaximizeTxt2.Text = win.WindowState == WindowState.Maximized ? "\uE923" : "\uE922";
            }
            try { RmtWindowFrame.Sync(win); } catch { }
            ScheduleSystemShadow();
            return;
        }

        CornerRadius baseRad = new CornerRadius(0);
        if (win.Resources.Contains("PanelRadius"))
        {
            baseRad = (CornerRadius)win.Resources["PanelRadius"];
        }
        else if (win.Resources.Contains("BaseWindowRadius"))
        {
            baseRad = (CornerRadius)win.Resources["BaseWindowRadius"];
        }
        bool wantsRound = baseRad.TopLeft > 0;

        bool isSnappedOrMax = win.WindowState == WindowState.Maximized;
        if (!isSnappedOrMax)
        {
            var workArea = System.Windows.SystemParameters.WorkArea;
            isSnappedOrMax = (win.Top <= workArea.Top && win.Height >= workArea.Height) ||
                                (win.Left <= workArea.Left && win.Width >= workArea.Width);
        }

        int cornerPref = wantsRound ? 2 : 1; // 1 = DoNotRound, 2 = Round
        int hr = -1;
        try
        {
            IntPtr hwnd = new WindowInteropHelper(win).Handle;
            if (hwnd != IntPtr.Zero)
            {
                hr = DwmSetWindowAttribute(hwnd, 33, ref cornerPref, 4);
            }
        }
        catch { }
        // On Windows 11, if DwmSetWindowAttribute(33) succeeds, DWM rounds the physical window to exactly the requested radius.
        // On Windows 10, it fails, and the physical window remains square (0px).
        double actualRadius = (!isSnappedOrMax && wantsRound && hr == 0) ? baseRad.TopLeft : 0;

        win.Resources["WindowRadius"] = new CornerRadius(actualRadius);
        win.Resources["CloseBtnRadius"] = new CornerRadius(0, actualRadius, 0, 0);
        if (win.Resources.Contains("PanelRadius"))
        {
            win.Resources["PanelRadius"] = new CornerRadius(actualRadius);
        }

        var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
        if (chrome != null)
        {
            // Win10 默认给系统标题按钮留空位，自定义按钮会时有时无地被盖住
            chrome.UseAeroCaptionButtons = false;
            if (win.Resources.Contains("PanelRadius"))
            {
                chrome.CornerRadius = (CornerRadius)win.Resources["PanelRadius"];
            }
            else
            {
                chrome.CornerRadius = (CornerRadius)win.Resources["WindowRadius"];
            }
        }

        if (Application.Current != null && !win.Title.StartsWith("Developer Tools - "))
        {
            AhkWpfEngine.SetAppResource("WindowRadius", win.Resources["WindowRadius"]);
            AhkWpfEngine.SetAppResource("CloseBtnRadius", win.Resources["CloseBtnRadius"]);
        }

        var btnMaximizeTxt = win.FindName("BtnMaximizeTxt") as TextBlock;
        if (btnMaximizeTxt != null)
        {
            btnMaximizeTxt.Text = win.WindowState == WindowState.Maximized ? "\uE923" : "\uE922";
        }
        try { RmtWindowFrame.Sync(win); } catch { }
        ScheduleSystemShadow();
    }

    // 边框和阴影由 RmtWindowFrame 画。系统阴影在直角窗口上会裁掉底边，
    // Win10 上很多机器整圈都没有，所以不靠 DWM。
    void ScheduleSystemShadow(bool afterLayout = false)
    {
        if (_systemShadowPosted || win == null)
            return;
        IntPtr hwnd = IntPtr.Zero;
        try { hwnd = new WindowInteropHelper(win).Handle; } catch { }
        if (SystemShadowKey(win, hwnd) == _systemShadowSig)
            return;
        _systemShadowPosted = true;
        var priority = afterLayout
            ? System.Windows.Threading.DispatcherPriority.ContextIdle
            : System.Windows.Threading.DispatcherPriority.Render;
        win.Dispatcher.BeginInvoke(new Action(() =>
        {
            _systemShadowPosted = false;
            if (win == null)
                return;
            ApplySystemShadow(win);
        }), priority);
    }

    string SystemShadowKey(Window window, IntPtr hwnd)
    {
        int w = 0, h = 0;
        RECT wr;
        if (hwnd != IntPtr.Zero && GetWindowRect(hwnd, out wr))
        {
            w = wr.right - wr.left;
            h = wr.bottom - wr.top;
        }
        int radius = 0;
        try
        {
            if (window.Resources.Contains("WindowRadius"))
                radius = (int)Math.Round(((CornerRadius)window.Resources["WindowRadius"]).TopLeft);
        }
        catch { }
        bool enabled = true;
        try
        {
            if (window.Resources.Contains("GlassFrameThicknessVal"))
                enabled = Math.Abs((double)window.Resources["GlassFrameThicknessVal"]) > 0.001;
        }
        catch { }
        return (enabled ? "1" : "0") + ":" + (window.WindowState == WindowState.Maximized ? "M" : "N")
            + ":" + w + "x" + h + ":" + radius;
    }

    void ApplySystemShadow(Window window)
    {
        if (window == null)
            return;
        try { RmtWindowFrame.Sync(window); } catch { }
        IntPtr hwnd = IntPtr.Zero;
        try { hwnd = new WindowInteropHelper(window).Handle; } catch { }
        if (hwnd != IntPtr.Zero)
            _systemShadowSig = SystemShadowKey(window, hwnd);
        if (window.AllowsTransparency || hwnd == IntPtr.Zero)
            return;
        if (RmtWindowFrame.Wants(window))
        {
            try { RmtWindowFrame.DisableSystemShadow(hwnd); } catch { }
            var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(window);
            if (chrome != null)
            {
                var g = chrome.GlassFrameThickness;
                if (g.Left != 0 || g.Top != 0 || g.Right != 0 || g.Bottom != 0)
                    chrome.GlassFrameThickness = new Thickness(0);
            }
        }
    }

    private static readonly System.Collections.Generic.Dictionary<string, AhkWpfEngine> _activeEngines =
        new System.Collections.Generic.Dictionary<string, AhkWpfEngine>();

    public static AhkWpfEngine GetEngine(string id)
    {
        lock (_activeEngines)
        {
            AhkWpfEngine eng;
            _activeEngines.TryGetValue(id, out eng);
            return eng;
        }
    }

}


[ComVisible(true)]
public class AhkInProcessBootstrapper
{
    static AhkInProcessBootstrapper()
    {
        AppDomain.CurrentDomain.AssemblyResolve += ResolveAssembly;
    }
    public AhkInProcessBootstrapper() { }
    private static System.Reflection.Assembly ResolveAssembly(object sender, ResolveEventArgs args)
    {
        try {
            string folder = "";
            string asmLoc = System.Reflection.Assembly.GetExecutingAssembly().Location;
            if (!string.IsNullOrEmpty(asmLoc))
                folder = System.IO.Path.GetDirectoryName(asmLoc);
            string name = new System.Reflection.AssemblyName(args.Name).Name;
            string assemblyPath = System.IO.Path.Combine(folder, name + ".dll");
            if (System.IO.File.Exists(assemblyPath)) {
                return System.Reflection.Assembly.LoadFrom(assemblyPath);
            }
        } catch { }
        return null;
    }
}
