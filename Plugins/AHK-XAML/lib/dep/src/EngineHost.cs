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
                string tempPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf");
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

                                if (text.StartsWith("CREATE_WINDOW_INLINE|"))
                                {
                                    // Fast path: XAML + events are embedded directly in the message
                                    // Format: CREATE_WINDOW_INLINE|winId|trackedCsv|scriptName|ownerHwnd|xaml\n---AHK-XAML-EVENTS---\nevents
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
                                    string[] p = text.Split(new[] { '|' }, 7);
                                    if (p.Length >= 7)
                                    {
                                        string wId = p[1];
                                        string tCsv = p[2];
                                        string sName = p[3];
                                        string oHwnd = p[4];
                                        string xPath = p[5];
                                        string ePath = p[6];

                                        System.Windows.Threading.Dispatcher.CurrentDispatcher.BeginInvoke(new Action(() =>
                                        {
                                            try
                                            {
                                                AhkWpfEngine eng = new AhkWpfEngine();
                                                eng.RunEngine(wId, ahkHwnd.ToString(), tCsv, sName, xPath, ePath, oHwnd, true);
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
                            }
                            catch { }
                            handled = true;
                        }
                        return IntPtr.Zero;
                    });

                    byte[] rBytes = Encoding.UTF8.GetBytes("DAEMON|Ready|" + msgWindow.Handle.ToString() + "\n");
                    var rCds = new COPYDATASTRUCT { cbData = rBytes.Length + 1, lpData = Marshal.AllocHGlobal(rBytes.Length + 1) };
                    Marshal.Copy(rBytes, 0, rCds.lpData, rBytes.Length); Marshal.WriteByte(rCds.lpData, rBytes.Length, 0);
                    SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref rCds);
                    Marshal.FreeHGlobal(rCds.lpData);

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

                    // Force JIT compilation of WPF rendering engine and core control templates in the background
                    var dummy = new Window { Width = 0, Height = 0, WindowStyle = WindowStyle.None, ShowInTaskbar = false, AllowsTransparency = true, Opacity = 0 };
                    var prewarmPanel = new StackPanel();
                    prewarmPanel.Children.Add(new Button { Content = "Prewarm" });
                    prewarmPanel.Children.Add(new TextBox { Text = "Prewarm" });
                    prewarmPanel.Children.Add(new System.Windows.Controls.CheckBox { Content = "Prewarm" });
                    prewarmPanel.Children.Add(new ListBox());
                    prewarmPanel.Children.Add(new TreeView());
                    dummy.Content = prewarmPanel;
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

            // 窗口缩放支持（对所有窗口统一生效，无需改各 GUI 的 XAML）：
            // 把根内容包进 Viewbox（等比缩放）。根内容尺寸固定为窗口设计尺寸（win.Width/Height），
            // 窗口默认大小时 1:1 无变化；用户拉大/缩小时内容等比缩放。
            try
            {
                var rootContent = win.Content as FrameworkElement;
                if (rootContent != null && !(rootContent is System.Windows.Controls.Viewbox)
                    && !double.IsNaN(win.Width))
                {
                    if (double.IsNaN(rootContent.Width))
                        rootContent.Width = win.Width;
                    // SizeToContent=Height 时窗口高度为 NaN，只钉宽度，Viewbox 按宽把字号拉到与其它弹窗一致
                    if (!double.IsNaN(win.Height) && double.IsNaN(rootContent.Height))
                        rootContent.Height = win.Height;
                    var oldContent = win.Content;
                    win.Content = null;   // 先从窗口摘除，避免逻辑树父冲突
                    var vb = new System.Windows.Controls.Viewbox
                    {
                        Stretch = System.Windows.Media.Stretch.Uniform,
                        StretchDirection = System.Windows.Controls.StretchDirection.Both,
                        Child = (UIElement)oldContent
                    };
                    win.Content = vb;
                }
            }
            catch { }
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
        if (dragArea != null) dragArea.MouseLeftButtonDown += (s, e) => { try { win.DragMove(); } catch { } };
        var btnClose = win.FindName("BtnClose") as ButtonBase;
        if (btnClose != null) btnClose.Click += (s, e) => { try { win.Close(); } catch { } };
        var btnMaximize = win.FindName("BtnMaximize") as ButtonBase;
        if (btnMaximize != null) btnMaximize.Click += (s, e) => { win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; };
        var btnMinimize = win.FindName("BtnMinimize") as ButtonBase;
        if (btnMinimize != null) btnMinimize.Click += (s, e) => { win.WindowState = WindowState.Minimized; };

        win.Resources["BaseWindowRadius"] = new CornerRadius(12);
        if (Application.Current != null) Application.Current.Resources["BaseWindowRadius"] = win.Resources["BaseWindowRadius"];

        win.StateChanged += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|StateChanged|" + win.WindowState.ToString() + "\n");
            UpdateSnapState(win);
        };
        win.Activated += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|Activated\n");
        };
        win.Deactivated += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|Deactivated\n");
        };
        win.LocationChanged += (s, e) => UpdateSnapState(win);
        win.SizeChanged += (s, e) => UpdateSnapState(win);

        win.Loaded += (s, e) =>
        {
            IntPtr hwndVal = new WindowInteropHelper(win).Handle;
            HwndSource.FromHwnd(hwndVal).AddHook(WndProc);
            // Async: 避免 CREATE_WINDOW 的 SendMessage 与 LoadedHwnd 回调互相嵌套死锁
            SendToAhkAsync("EVENT|" + winId + "|Window|LoadedHwnd|" + hwndVal.ToString() + "\n");
            UpdateSnapState(win);
            InheritWindowIconAndTitle(win, ownerHwndStr);
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

        // Set owner
        if (ownerHwndStr != "0")
        {
            try
            {
                IntPtr oHwnd = new IntPtr(long.Parse(ownerHwndStr));
                if (oHwnd != IntPtr.Zero)
                {
                    win.Resources["OriginalNativeOwner"] = oHwnd;
                    new WindowInteropHelper(win).Owner = oHwnd;
                }
            }
            catch { }
        }

        InheritWindowIconAndTitle(win, ownerHwndStr);
#if ENABLE_WEBVIEW
        ConfigureWebView2CreationProperties(win);
#endif
        if (isDaemon)
        {
            // Opacity=0：首帧 present 前挂 LWA_ALPHA=0，全程不 WinHide，避免「白壳→隐藏→再显示」
            PrepareDeferredReveal(win);
            win.Show();
            ReinforceNativeAlphaHide(win);
        }
        else
        {
            win.ShowDialog();
        }
    }

    public void RunEngine(string id, string hwndStr, string trackedCsv, string scriptName, string xamlFilePath, string eventsFilePath, string ownerHwndStr = "0", bool isDaemon = false)
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
                    foreach (string btnName in new[] { "BtnToggleSidebar", "BtnClose", "BtnClosePanel", "BtnWinClose", "BtnMinimize", "BtnMaximize" })
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
        if (btnMaximize != null) btnMaximize.Click += (s, e) => { win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; };

        var btnMinimize = win.FindName("BtnMinimize") as ButtonBase;
        if (btnMinimize != null) btnMinimize.Click += (s, e) => { win.WindowState = WindowState.Minimized; };

        win.Resources["BaseWindowRadius"] = new CornerRadius(12);
        if (Application.Current != null) Application.Current.Resources["BaseWindowRadius"] = win.Resources["BaseWindowRadius"];

        win.StateChanged += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|StateChanged|" + win.WindowState.ToString() + "\n");
            UpdateSnapState(win);
        };
        win.Activated += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|Activated\n");
        };
        win.Deactivated += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|Deactivated\n");
        };
        win.LocationChanged += (s, e) => UpdateSnapState(win);
        win.SizeChanged += (s, e) => UpdateSnapState(win);

        win.Loaded += (s, e) =>
        {
            IntPtr hwnd = new WindowInteropHelper(win).Handle;
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);
            // Async: 避免 CREATE_WINDOW 的 SendMessage 与 LoadedHwnd 回调互相嵌套死锁
            SendToAhkAsync("EVENT|" + winId + "|Window|LoadedHwnd|" + hwnd.ToString() + "\n");
            UpdateSnapState(win);
            InheritWindowIconAndTitle(win, ownerHwndStr);
            DumpState("Window", "Loaded");
#if ENABLE_WEBVIEW
            InitializeWebView2IfPresent(win);
#endif

            // Aggressively flush the working set from RAM (WPF caches huge amounts of unused startup structures)
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            timer.Tick += (sender, args) =>
            {
                timer.Stop();
                win.Topmost = true;
                win.Topmost = false;
                // 揭盖前窗口处于 SW_HIDE 隐藏阶段：不激活（Activate 会把隐藏窗口重新显示成白壳）
                if (!win.Resources.Contains("_NativeAlphaPending"))
                    win.Activate();
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

        if (ownerHwndStr != "0")
        {
            try
            {
                IntPtr oHwnd = new IntPtr(long.Parse(ownerHwndStr));
                if (oHwnd != IntPtr.Zero)
                {
                    win.Resources["OriginalNativeOwner"] = oHwnd;
                    new System.Windows.Interop.WindowInteropHelper(win).Owner = oHwnd;
                }
            }
            catch { }
        }

        eventsContent = null;

        InheritWindowIconAndTitle(win, ownerHwndStr);
#if ENABLE_WEBVIEW
        ConfigureWebView2CreationProperties(win);
#endif
        if (isDaemon)
        {
            // Opacity=0：首帧 present 前挂 LWA_ALPHA=0，全程不 WinHide，避免「白壳→隐藏→再显示」
            PrepareDeferredReveal(win);
            win.Show();
            ReinforceNativeAlphaHide(win);
        }
        else
        {
            win.ShowDialog();
        }
    }

    // 非透明窗口：WPF Opacity 在首帧 present 前对 HWND 无效。
    // 用 SourceInitialized（HWND 已建、尚未画第一帧）挂 WS_EX_LAYERED+alpha=0；
    // 并在 Show 前就把窗口移到屏幕外（-32000）——LWA alpha 在部分 DWM/WindowChrome 组合下
    // 不可靠，若 Show 后再移，Show 瞬间会在屏上露出白壳（用户可见的闪烁）。
    // 居中位置在 Show 前按 CenterScreen 规则预计算存入 _RevealPos，揭盖时由 CommandDispatcher 还原。
    // 禁止 AHK 侧 WinHide/WinShow：会变成白壳→隐藏→再显示。
    private static void PrepareDeferredReveal(Window win)
    {
        if (win == null || win.AllowsTransparency || win.Opacity >= 1)
            return;
        try
        {
            win.ShowActivated = false; // 内容未就绪前不抢焦点
            win.Resources["_NativeAlphaPending"] = true;
            // 揭盖还原位：窗口 XAML 已显式定位（Manual+Left/Top，如主窗口的保存位置）则沿用，
            // 避免揭盖时先居中再被 WinMove 拉回导致可见跳变（闪烁）；
            // 未显式定位的窗口（CenterScreen 默认）按 CenterScreen 规则居中（DIP 坐标）。
            if (!double.IsNaN(win.Left) && !double.IsNaN(win.Top))
                win.Resources["_RevealPos"] = new System.Windows.Point(win.Left, win.Top);
            else
            {
                double winW = double.IsNaN(win.Width) ? 800 : win.Width;
                double winH = double.IsNaN(win.Height) ? 600 : win.Height;
                double cx = Math.Max(0, (System.Windows.SystemParameters.PrimaryScreenWidth - winW) / 2);
                double cy = Math.Max(0, (System.Windows.SystemParameters.PrimaryScreenHeight - winH) / 2);
                win.Resources["_RevealPos"] = new System.Windows.Point(cx, cy);
            }
            win.WindowStartupLocation = System.Windows.WindowStartupLocation.Manual;
            win.Left = -32000;
            win.Top = -32000;
            // HWND 创建瞬间、首帧绘制前
            win.SourceInitialized += (s, e) =>
            {
                try { ApplyNativeAlphaZero(win); }
                catch { }
            };
            // 提前建 HWND，让 SourceInitialized 在 Show 前就触发
            var helper = new System.Windows.Interop.WindowInteropHelper(win);
            helper.EnsureHandle();
            // Show 前关 DWM backdrop（Win11 默认 Acrylic 偏紫，首帧会闪紫）
            try
            {
                int noBackdrop = 0; // DWMSBT_NONE
                int darkMode = 0;
                DwmSetWindowAttribute(helper.Handle, 20, ref darkMode, 4);
                DwmSetWindowAttribute(helper.Handle, 38, ref noBackdrop, 4);
            }
            catch { }
            ApplyNativeAlphaZero(win);
            // Show 前移到屏幕外：SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
            SetWindowPos(helper.Handle, IntPtr.Zero, -32000, -32000, 0, 0, 0x0001 | 0x0004 | 0x0010);
        }
        catch { }
    }

    private static void ReinforceNativeAlphaHide(Window win)
    {
        if (win == null || !win.Resources.Contains("_NativeAlphaPending"))
            return;
        try
        {
            IntPtr h = new System.Windows.Interop.WindowInteropHelper(win).Handle;
            if (h != IntPtr.Zero)
                SetWindowPos(h, IntPtr.Zero, -32000, -32000, 0, 0, 0x0001 | 0x0004 | 0x0010);
            ApplyNativeAlphaZero(win);
        }
        catch { }
    }

    private static void ApplyNativeAlphaZero(Window win)
    {
        IntPtr hwnd = new System.Windows.Interop.WindowInteropHelper(win).Handle;
        if (hwnd == IntPtr.Zero)
            return;
        int ex = GetWindowLong(hwnd, -20);
        if ((ex & 0x80000) == 0)
            SetWindowLong(hwnd, -20, new IntPtr(ex | 0x80000)); // WS_EX_LAYERED
        SetLayeredWindowAttributes(hwnd, 0, 0, 0x2);            // LWA_ALPHA=0
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
            Application.Current.Resources["WindowRadius"] = win.Resources["WindowRadius"];
            Application.Current.Resources["CloseBtnRadius"] = win.Resources["CloseBtnRadius"];
        }

        var btnMaximizeTxt = win.FindName("BtnMaximizeTxt") as TextBlock;
        if (btnMaximizeTxt != null)
        {
            btnMaximizeTxt.Text = win.WindowState == WindowState.Maximized ? "\uE923" : "\uE922";
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
            string folder = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf");
            string name = new System.Reflection.AssemblyName(args.Name).Name;
            string assemblyPath = System.IO.Path.Combine(folder, name + ".dll");
            if (System.IO.File.Exists(assemblyPath)) {
                return System.Reflection.Assembly.LoadFrom(assemblyPath);
            }
        } catch { }
        return null;
    }
}
