using System;
using System.Linq;
using System.Windows;
using System.Windows.Markup;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using System.Reflection;
using System.Windows.Documents;
using System.Windows.Media;
using WpfAnimatedGif;
#if ENABLE_WEBVIEW
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Web.WebView2.Core;
#endif
#if ENABLE_AVALONEDIT
using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.CodeCompletion;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Editing;
using ICSharpCode.AvalonEdit.Folding;
using ICSharpCode.AvalonEdit.Rendering;
using ICSharpCode.AvalonEdit.Search;
#endif
#if ENABLE_DOCUMENT
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
#endif
using Color = System.Windows.Media.Color;


[assembly: AssemblyTitle("ahk-xaml Engine")]
[assembly: AssemblyDescription("WPF Rendering Engine for AutoHotkey")]
[assembly: AssemblyCompany("owhs")]
[assembly: AssemblyProduct("ahk-xaml Shared Engine")]
[assembly: AssemblyCopyright("Copyright © 2026")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDispatch)]
public class AhkWpfEngine
{
    [StructLayout(LayoutKind.Sequential)]
    public struct COPYDATASTRUCT
    {
        public IntPtr dwData; public int cbData; public IntPtr lpData;
    }
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, ref COPYDATASTRUCT lParam);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern IntPtr LoadCursor(IntPtr hInstance, int lpCursorName);
    [DllImport("user32.dll")]
    public static extern IntPtr SetCursor(IntPtr hCursor);
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS
    {
        public int leftWidth;
        public int rightWidth;
        public int topHeight;
        public int bottomHeight;
        public MARGINS(int left, int right, int top, int bottom)
        {
            leftWidth = left; rightWidth = right; topHeight = top; bottomHeight = bottom;
        }
    }
    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    public static int GetWindowLong(IntPtr hWnd, int nIndex)
    {
        if (IntPtr.Size == 4) return GetWindowLong32(hWnd, nIndex);
        return (int)(long)GetWindowLongPtr64(hWnd, nIndex);
    }
    public static IntPtr SetWindowLong(IntPtr hWnd, int nIndex, IntPtr dwNewLong)
    {
        if (IntPtr.Size == 4) return new IntPtr(SetWindowLong32(hWnd, nIndex, dwNewLong.ToInt32()));
        return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
    }

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static bool EnableLogging = true;
    private static ITaskbarList _taskbarList = null;
    public static void SetTaskbarPresence(IntPtr hwnd, bool show)
    {
        try
        {
            if (_taskbarList == null)
            {
                _taskbarList = (ITaskbarList)new TaskbarList();
                _taskbarList.HrInit();
            }
            if (show)
            {
                _taskbarList.AddTab(hwnd);
            }
            else
            {
                _taskbarList.DeleteTab(hwnd);
            }
        }
        catch { }
    }

    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);

    [StructLayout(LayoutKind.Sequential)]
    public struct MINMAXINFO { public POINT ptReserved; public POINT ptMaxSize; public POINT ptMaxPosition; public POINT ptMinTrackSize; public POINT ptMaxTrackSize; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int left, top, right, bottom; }
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr handle, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll", EntryPoint = "SendMessage", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "GetClassLong")]
    public static extern uint GetClassLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "GetClassLongPtr")]
    public static extern IntPtr GetClassLongPtr64(IntPtr hWnd, int nIndex);

    public static IntPtr GetClassLongPtr(IntPtr hWnd, int nIndex)
    {
        if (IntPtr.Size == 4) return new IntPtr(GetClassLong32(hWnd, nIndex));
        return GetClassLongPtr64(hWnd, nIndex);
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern uint ExtractIconEx(string szFileName, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);

    string winId; IntPtr ahkHwnd; string[] tracked; Window win;
    System.Collections.Generic.HashSet<string> _boundEvents = new System.Collections.Generic.HashSet<string>();
    System.Collections.Generic.Dictionary<string, object> _controlCache = new System.Collections.Generic.Dictionary<string, object>();
    bool LightweightEvents = false; // When true, events only send the triggering control's value (use ui.Query() for others)
    System.Collections.Generic.Dictionary<string, string> canvasModes = new System.Collections.Generic.Dictionary<string, string>();
    System.Collections.Generic.Dictionary<string, string> _docViewModes = new System.Collections.Generic.Dictionary<string, string>();
    System.Collections.Generic.Dictionary<string, string> _spellCheckLangs = new System.Collections.Generic.Dictionary<string, string>();
    System.Windows.Shapes.Rectangle selectionBox = null;
    Point selectionStart;
    System.Windows.Shapes.Path tempConnection = null;
    FrameworkElement connectionSourcePort = null;

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
    string _loadedDictionaryPath = null;
    static void InitHighlightBrushes() { } // Brushes initialized in static field initializers

    static AhkWpfEngine()
    {
        _highlightBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(254, 239, 195));
        _highlightBrush.Freeze();
        _activeMatchBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 165, 0));
        _activeMatchBrush.Freeze();
        EventManager.RegisterClassHandler(typeof(ScrollViewer), FrameworkElement.LoadedEvent, new RoutedEventHandler(OnScrollViewerLoaded), false);
        EventManager.RegisterClassHandler(typeof(ScrollViewer), UIElement.PreviewMouseWheelEvent, new System.Windows.Input.MouseWheelEventHandler(OnPreviewMouseWheel), false);
    }

    private static HwndSource inProcessMsgWindow;

    public static IntPtr StartInProcess(string ahkHwndStr)
    {
        IntPtr ahkHwnd = (IntPtr)long.Parse(ahkHwndStr);
        IntPtr resultHwnd = IntPtr.Zero;
        using (var readyEvent = new System.Threading.ManualResetEvent(false))
        {
            var thread = new System.Threading.Thread(() =>
            {
                try
                {
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
                                return Assembly.LoadFrom(localDllPath);
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

                    EventManager.RegisterClassHandler(typeof(Slider), Slider.PreviewMouseLeftButtonDownEvent, new System.Windows.Input.MouseButtonEventHandler(Slider_PreviewMouseLeftButtonDown), true);

                    if (System.Windows.Application.Current == null)
                    {
                        var app = new System.Windows.Application();
                        LoadComponentStyles(app);
                    }

                    HwndSourceParameters parameters = new HwndSourceParameters("InProcessReceiver", 0, 0);
                    parameters.WindowStyle = 0;
                    inProcessMsgWindow = new HwndSource(parameters);

                    inProcessMsgWindow.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
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
                                    string[] p = text.Split(new[] { '|' }, 6);
                                    if (p.Length >= 6)
                                    {
                                        string wId = p[1];
                                        string tCsv = p[2];
                                        string sName = p[3];
                                        string oHwnd = p[4];
                                        string inlineData = p[5];

                                        System.Windows.Application.Current.Dispatcher.BeginInvoke(new Action(() =>
                                        {
                                            try
                                            {
                                                AhkWpfEngine eng = new AhkWpfEngine();
                                                eng.RunEngineInline(wId, ahkHwnd.ToString(), tCsv, sName, oHwnd, inlineData, true);
                                            }
                                            catch (Exception ex)
                                            {
                                                byte[] b = Encoding.UTF8.GetBytes("EVENT|" + wId + "|Engine|Error|" + LengthPrefix(ex.ToString()) + "\n");
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

                                        System.Windows.Application.Current.Dispatcher.BeginInvoke(new Action(() =>
                                        {
                                            try
                                            {
                                                AhkWpfEngine eng = new AhkWpfEngine();
                                                eng.RunEngine(wId, ahkHwnd.ToString(), tCsv, sName, xPath, ePath, oHwnd, true);
                                            }
                                            catch (Exception ex)
                                            {
                                                byte[] b = Encoding.UTF8.GetBytes("EVENT|" + wId + "|Engine|Error|" + LengthPrefix(ex.ToString()) + "\n");
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

                    resultHwnd = inProcessMsgWindow.Handle;
                    readyEvent.Set();

                    System.Windows.Threading.Dispatcher.Run();
                }
                catch (Exception)
                {
                    readyEvent.Set();
                }
            });

            thread.SetApartmentState(System.Threading.ApartmentState.STA);
            thread.IsBackground = true;
            thread.Start();

            readyEvent.WaitOne(5000);
        }

        return resultHwnd;
    }

    private static void OnScrollViewerLoaded(object sender, RoutedEventArgs e)
    {
        ScrollViewer sv = sender as ScrollViewer;
        if (sv != null && (sv.Tag as string == null || !(sv.Tag as string).Contains("Trapped")))
        {
            bool inPopup = false;
            DependencyObject d = sv;
            while (d != null)
            {
                if (d is System.Windows.Controls.Primitives.Popup || d.GetType().Name == "PopupRoot") { inPopup = true; break; }
                if (d is System.Windows.Media.Visual || d is System.Windows.Media.Media3D.Visual3D) d = System.Windows.Media.VisualTreeHelper.GetParent(d);
                else d = LogicalTreeHelper.GetParent(d);
            }
            if (inPopup)
            {
                sv.Tag = ((sv.Tag as string) ?? "") + " Trapped";
                System.Windows.Input.MouseWheelEventHandler handler = (s, args) =>
                {
                    var _sv = (ScrollViewer)s;
                    _sv.ScrollToVerticalOffset(_sv.VerticalOffset - args.Delta / 3.0);
                    args.Handled = true;
                };
                sv.PreviewMouseWheel += handler;
                sv.MouseWheel += handler;
            }
        }
    }

    private static void OnPreviewMouseWheel(object sender, System.Windows.Input.MouseWheelEventArgs args)
    {
        if (!args.Handled)
        {
            ScrollViewer sv = null;
            if (sender is ScrollViewer) sv = (ScrollViewer)sender;
            else sv = FindVisualChild<ScrollViewer>(sender as DependencyObject);

            if (sv == null) return;
            if (IsEventForNestedOrPopup(args.OriginalSource as DependencyObject, sv)) return;

            bool canScroll = false;
            if (sv.ComputedVerticalScrollBarVisibility == Visibility.Visible)
            {
                if (args.Delta > 0 && sv.VerticalOffset > 0) canScroll = true;
                else if (args.Delta < 0 && sv.VerticalOffset < sv.ScrollableHeight) canScroll = true;
            }

            string tag = sv.Tag as string ?? "";
            bool passScroll = tag.Contains("PassScroll");
            bool containScroll = tag.Contains("ContainScroll");

            if (!canScroll || passScroll)
            {
                args.Handled = true;

                if (containScroll) return;

                Window window = Window.GetWindow(sender as DependencyObject);
                if (window != null && !window.IsEnabled) return;

                var eventArg = new System.Windows.Input.MouseWheelEventArgs(args.MouseDevice, args.Timestamp, args.Delta) { RoutedEvent = UIElement.MouseWheelEvent, Source = sender };
                var parent = System.Windows.Media.VisualTreeHelper.GetParent(sender as DependencyObject) as UIElement;
                if (parent != null) parent.RaiseEvent(eventArg);
            }
        }
    }

    private static bool IsEventForNestedOrPopup(DependencyObject originalSource, ScrollViewer currentScrollViewer)
    {
        if (originalSource == null || currentScrollViewer == null) return false;
        DependencyObject d = originalSource;
        while (d != null && d != currentScrollViewer)
        {
            if (d is System.Windows.Controls.Primitives.Popup || d.GetType().Name == "PopupRoot")
            {
                return true;
            }
            if (d is ScrollViewer && d != currentScrollViewer)
            {
                return true;
            }
            if (d is System.Windows.Media.Visual || d is System.Windows.Media.Media3D.Visual3D)
            {
                d = System.Windows.Media.VisualTreeHelper.GetParent(d);
            }
            else
            {
                d = LogicalTreeHelper.GetParent(d);
            }
        }
        return false;
    }

    private static T FindVisualChild<T>(DependencyObject obj) where T : DependencyObject
    {
        if (obj != null)
        {
            for (int i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(obj); i++)
            {
                var child = System.Windows.Media.VisualTreeHelper.GetChild(obj, i);
                if (child is T) return (T)child;
                T childItem = FindVisualChild<T>(child);
                if (childItem != null) return childItem;
            }
        }
        return null;
    }

    private static void Slider_PreviewMouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        var s = sender as Slider;
        if (s == null) return;

        var track = s.Template.FindName("PART_Track", s) as Track;
        if (track != null && track.Thumb != null && track.Thumb.IsMouseOver)
            return;

        if (track != null && track.Thumb != null)
        {
            s.Dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    s.UpdateLayout();
                    var args = new System.Windows.Input.MouseButtonEventArgs(e.MouseDevice, e.Timestamp, System.Windows.Input.MouseButton.Left);
                    args.RoutedEvent = UIElement.MouseLeftButtonDownEvent;
                    track.Thumb.RaiseEvent(args);
                }
                catch { }
            }), System.Windows.Threading.DispatcherPriority.Input);
        }
    }


    /// <summary>
    /// Three-tier component style loader for ultra-fast startup:
    /// 1. BAML binary from embedded resource (fastest — no XML parsing)
    /// 2. Embedded XAML text resource (fast — no disk I/O)
    /// 3. Disk file fallback (legacy — reads from exe directory)
    /// </summary>
    private static void LoadComponentStyles(Application app)
    {
        var asm = System.Reflection.Assembly.GetExecutingAssembly();

        // Tier 1: Try loading pre-compiled BAML from embedded resource
        var bamlStream = asm.GetManifestResourceStream("xaml.components.baml");
        if (bamlStream != null)
        {
            try
            {
                using (bamlStream)
                {
                    var reader = new System.Windows.Baml2006.Baml2006Reader(bamlStream);
                    var writer = new System.Xaml.XamlObjectWriter(reader.SchemaContext);
                    while (reader.Read())
                    {
                        writer.WriteNode(reader);
                    }
                    ResourceDictionary dict = (ResourceDictionary)writer.Result;
                    app.Resources.MergedDictionaries.Add(dict);
                }
                return; // BAML loaded successfully — fastest path
            }
            catch
            {
                // BAML load failed — fall through to text-based loading
            }
        }

        // Tier 2: Try loading XAML text from embedded resource (no disk I/O)
        var xamlStream = asm.GetManifestResourceStream("xaml.components.xaml");
        if (xamlStream != null)
        {
            try
            {
                string componentsXaml;
                using (xamlStream)
                using (var reader = new System.IO.StreamReader(xamlStream, Encoding.UTF8))
                {
                    componentsXaml = reader.ReadToEnd();
                }
                if (componentsXaml.Contains("<Window.Resources>"))
                {
                    componentsXaml = componentsXaml.Replace("<Window.Resources>", "<ResourceDictionary xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xmlns:x=\"http://schemas.microsoft.com/winfx/2006/xaml\" xmlns:sys=\"clr-namespace:System;assembly=mscorlib\" xmlns:primitives=\"clr-namespace:System.Windows.Controls.Primitives;assembly=PresentationFramework\">");
                    componentsXaml = componentsXaml.Replace("</Window.Resources>", "</ResourceDictionary>");
                }
                using (var stream = new System.IO.MemoryStream(Encoding.UTF8.GetBytes(componentsXaml)))
                {
                    ResourceDictionary dict = (ResourceDictionary)XamlReader.Load(stream);
                    app.Resources.MergedDictionaries.Add(dict);
                }
                return; // Embedded XAML loaded successfully
            }
            catch
            {
                // Embedded XAML failed — fall through to disk
            }
        }

        // Tier 3: Fallback to disk file (legacy / development override)
        string exePath = asm.Location;
        string exeDir = System.IO.Path.GetDirectoryName(exePath);
        string componentsPath = System.IO.Path.Combine(exeDir, "xaml.components.xaml");
        if (System.IO.File.Exists(componentsPath))
        {
            string diskXaml = System.IO.File.ReadAllText(componentsPath, Encoding.UTF8);
            if (diskXaml.Contains("<Window.Resources>"))
            {
                diskXaml = diskXaml.Replace("<Window.Resources>", "<ResourceDictionary xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xmlns:x=\"http://schemas.microsoft.com/winfx/2006/xaml\" xmlns:sys=\"clr-namespace:System;assembly=mscorlib\" xmlns:primitives=\"clr-namespace:System.Windows.Controls.Primitives;assembly=PresentationFramework\">");
                diskXaml = diskXaml.Replace("</Window.Resources>", "</ResourceDictionary>");
            }
            using (var stream = new System.IO.MemoryStream(Encoding.UTF8.GetBytes(diskXaml)))
            {
                ResourceDictionary dict = (ResourceDictionary)XamlReader.Load(stream);
                app.Resources.MergedDictionaries.Add(dict);
            }
        }
    }

    [STAThread]
    public static void Main(string[] args)
    {
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
                                                byte[] b = Encoding.UTF8.GetBytes("EVENT|" + wId + "|Engine|Error|" + LengthPrefix(ex.ToString()) + "\n");
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
                                                byte[] b = Encoding.UTF8.GetBytes("EVENT|" + wId + "|Engine|Error|" + LengthPrefix(ex.ToString()) + "\n");
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
                            string exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                            string exeDir = System.IO.Path.GetDirectoryName(exePath);
                            System.IO.File.AppendAllText(System.IO.Path.Combine(exeDir, "daemon_error.txt"), "Error loading components: " + ex.ToString() + "\n");
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
                        string wvDataDir = !string.IsNullOrEmpty(customDir) ? customDir : System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "WebView2Data");
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
                        string wvDataDir = !string.IsNullOrEmpty(customDir) ? customDir : System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "WebView2Data");
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
                                string dir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf");
                                if (!System.IO.Directory.Exists(dir)) System.IO.Directory.CreateDirectory(dir);
                                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "AhkWpf_StateDump_" + scriptName + ".ini"), state);
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
                string dir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf");
                if (!System.IO.Directory.Exists(dir)) System.IO.Directory.CreateDirectory(dir);
                if (EnableLogging) System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "AhkWpfError.log"), ex.ToString());
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
            foreach (System.Collections.DictionaryEntry entry in win.Resources)
            {
                Application.Current.Resources[entry.Key] = entry.Value;
            }
            xamlContent = null;
            xamlBytes = null;
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
            SendToAhk("EVENT|" + winId + "|Window|LoadedHwnd|" + hwndVal.ToString() + "\n");
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
            SendToAhk("EVENT|" + winId + "|Window|Closing\n");
        };
        win.Closed += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|Closed\n");
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
                string[] kv = evtStr.Split(':');
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
            win.Show();
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
                    System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "xaml_debug_startup.log"),
                    "Assembly: " + asm.FullName + "\n" +
                    "Resources: " + names + "\n" +
                    "app_payload.baml exists: " + bamlExists + "\n" +
                    "app_payload.xaml exists: " + xamlExists + "\n"
                );
            }
            catch (Exception ex)
            {
                try { System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "xaml_debug_err.log"), ex.ToString()); } catch { }
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
                        try { System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "decomp_err.log"), dx.ToString()); } catch { }
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
                    try { System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "xaml_load_err.log"), ex.ToString()); } catch { }
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
                            System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "baml_debug.log"),
                            DateTime.Now + " BAML NameScope: registered " + nameCount + " names. FindName test DGX_Table_List=" + (win.FindName("DGX_Table_List") != null) + "\n"
                        );
                    }
                    catch { }
                }
                foreach (System.Collections.DictionaryEntry entry in win.Resources)
                {
                    Application.Current.Resources[entry.Key] = entry.Value;
                }
                // Re-apply WindowChrome (stripped during BAML compilation)
                if (win.WindowStyle == WindowStyle.None && !win.AllowsTransparency)
                {
                    var chrome = new System.Windows.Shell.WindowChrome();
                    chrome.GlassFrameThickness = new Thickness(-1);
                    double captionHeight = 50;
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
                    foreach (string btnName in new[] { "BtnToggleSidebar", "BtnClose", "BtnMinimize", "BtnMaximize" })
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
                            System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "baml_err.log"),
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
                    foreach (System.Collections.DictionaryEntry entry in win.Resources)
                    {
                        Application.Current.Resources[entry.Key] = entry.Value;
                    }
                }
            }
        }
        else
        {
            // Text-based path (existing behavior)
            if (EnableLogging)
            {
                try { System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "xaml_content_debug.log"), xamlContent ?? "NULL"); } catch { }
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
                foreach (System.Collections.DictionaryEntry entry in win.Resources)
                {
                    Application.Current.Resources[entry.Key] = entry.Value;
                }
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
            string dumpPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpf_StateDump_" + scriptName + ".ini");
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
            SendToAhk("EVENT|" + winId + "|Window|LoadedHwnd|" + hwnd.ToString() + "\n");
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
            SendToAhk("EVENT|" + winId + "|Window|Closing\n");
        };
        win.Closed += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|Window|Closed\n");
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
                string[] kv = evtStr.Split(':');
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
            win.Show();
        }
        else
        {
            win.ShowDialog();
        }
    }

    private void WalkLogicalOrVisualTree(DependencyObject parent, Action<DependencyObject> callback)
    {
        if (parent == null) return;
        callback(parent);

        try
        {
            foreach (object child in LogicalTreeHelper.GetChildren(parent))
            {
                if (child is DependencyObject)
                {
                    WalkLogicalOrVisualTree((DependencyObject)child, callback);
                }
            }
        }
        catch { }

        try
        {
            int count = System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent);
            for (int i = 0; i < count; i++)
            {
                var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, i);
                WalkLogicalOrVisualTree(child, callback);
            }
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

#if ENABLE_WEBVIEW
    private System.Collections.Generic.Dictionary<string, string> _initialWebViewSources = new System.Collections.Generic.Dictionary<string, string>();

    private void PreprocessXamlAndExtractWebViewSources(ref string xaml)
    {
        if (string.IsNullOrEmpty(xaml)) return;
        try
        {
            var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWebViewDebug.log");
            System.IO.File.AppendAllText(logPath, "PreprocessXamlAndExtractWebViewSources called. XAML Length: " + xaml.Length + "\n");
            
            var regex = new System.Text.RegularExpressions.Regex(@"<wv2:WebView2\b[^>]*>", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            xaml = regex.Replace(xaml, (System.Text.RegularExpressions.Match match) =>
            {
                string tag = match.Value;
                System.IO.File.AppendAllText(logPath, "Found tag: " + tag + "\n");
                
                var nameMatch = System.Text.RegularExpressions.Regex.Match(tag, @"\b(?:x:)?Name\s*=\s*""([^""]*)""", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                var sourceMatch = System.Text.RegularExpressions.Regex.Match(tag, @"\bSource\s*=\s*""([^""]*)""", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                
                if (nameMatch.Success && sourceMatch.Success)
                {
                    string name = nameMatch.Groups[1].Value;
                    string source = sourceMatch.Groups[1].Value;
                    
                    _initialWebViewSources[name] = source;
                    System.IO.File.AppendAllText(logPath, "Successfully extracted Name='" + name + "', Source='" + source + "'\n");
                    
                    tag = System.Text.RegularExpressions.Regex.Replace(tag, @"\bSource\s*=\s*""[^""]*""\s*", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                }
                else
                {
                    System.IO.File.AppendAllText(logPath, "Tag mismatch: NameMatch=" + nameMatch.Success + ", SourceMatch=" + sourceMatch.Success + "\n");
                }
                return tag;
            });
        }
        catch (Exception ex)
        {
            try { System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWebViewDebug.log"), "Regex Error: " + ex.ToString() + "\n"); } catch {}
        }
    }

    private void ConfigureWebView2CreationProperties(Window win)
    {
        try
        {
            string customDir = Environment.GetEnvironmentVariable("AHK_XAML_WEBVIEW_DIR");
            string wvDataDir = !string.IsNullOrEmpty(customDir) ? customDir : System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "WebView2Data");
            
            WalkLogicalOrVisualTree(win, (DependencyObject d) =>
            {
                if (d is Microsoft.Web.WebView2.Wpf.WebView2)
                {
                    var wv = (Microsoft.Web.WebView2.Wpf.WebView2)d;
                    if (wv.CreationProperties == null)
                    {
                        wv.CreationProperties = new Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties
                        {
                            UserDataFolder = wvDataDir
                        };
                    }
                }
            });
        }
        catch { }
    }

    private async void InitializeWebView2IfPresent(Window win)
    {
        try
        {
            var webViews = new System.Collections.Generic.List<WebView2>();
            WalkVisualTree(win, (obj) => {
                if (obj is WebView2) {
                    webViews.Add((WebView2)obj);
                }
            });
            if (webViews.Count == 0) return;

            string customDir = Environment.GetEnvironmentVariable("AHK_XAML_WEBVIEW_DIR");
            string wvDataDir = !string.IsNullOrEmpty(customDir) ? customDir : System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "WebView2Data");
            var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWebViewDebug.log");
            
            System.IO.File.AppendAllText(logPath, "InitializeWebView2IfPresent called. Found " + webViews.Count + " WebViews. wvDataDir: " + wvDataDir + "\n");
            
            foreach (var wv in webViews) {
                try {
                    System.IO.File.AppendAllText(logPath, "Initializing WebView with Name: '" + wv.Name + "'\n");
                    wv.WebMessageReceived += (ws, we) => {
                        string debugMsg = we.WebMessageAsJson;
                        try { System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWebViewDebug.log"), "C# WebMessageReceived: " + debugMsg + "\n"); } catch {}
                        SendToAhk("EVENT|" + winId + "|" + wv.Name + "|WebMessageReceived|" + LengthPrefix(debugMsg) + "\n");
                    };
                    wv.NavigationCompleted += (ws, we) => {
                        SendToAhk("EVENT|" + winId + "|" + wv.Name + "|NavigationCompleted|" + LengthPrefix(wv.Source != null ? wv.Source.ToString() : "") + "\n");
                    };
                    
                    var env = await CoreWebView2Environment.CreateAsync(null, wvDataDir);
                    await wv.EnsureCoreWebView2Async(env);
                    System.IO.File.AppendAllText(logPath, "EnsureCoreWebView2Async completed successfully.\n");

                    if (!string.IsNullOrEmpty(wv.Name) && _initialWebViewSources.ContainsKey(wv.Name))
                    {
                        System.IO.File.AppendAllText(logPath, "Navigating to extracted Source URL: " + _initialWebViewSources[wv.Name] + "\n");
                        wv.Source = new Uri(_initialWebViewSources[wv.Name]);
                    }
                    else
                    {
                        System.IO.File.AppendAllText(logPath, "No extracted source URL found in _initialWebViewSources (Name='" + wv.Name + "', keyExists=" + _initialWebViewSources.ContainsKey(wv.Name ?? "") + ")\n");
                    }
                } catch (Exception ex) {
                    System.IO.File.AppendAllText(logPath, "WebView Init Exception: " + ex.ToString() + "\n");
                    System.Windows.MessageBox.Show("WebView Init Error:\n" + ex.ToString(), "AHK-XAML WebView Error");
                }
            }
        }
        catch (Exception ex)
        {
            try { System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWebViewDebug.log"), "InitializeWebView2IfPresent outer Exception: " + ex.ToString() + "\n"); } catch {}
        }
    }
#endif

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

    private void BindEvent(string ctrlName, string eventName, int fpsLimit = 0, bool queueLimited = false)
    {
        string eventKey = ctrlName + ":" + eventName;
        if (!_boundEvents.Add(eventKey)) return;
        try
        {
            object ctrl = ctrlName == "Window" ? (object)win : FindControlByPath(ctrlName);
            if (ctrl == null)
            {
                _boundEvents.Remove(eventKey);
                try {
                    System.IO.File.AppendAllText(
                        System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpfDebug.log"),
                        string.Format("BindEvent info: Control '{0}' not found for event '{1}' (may be dynamic)\n", ctrlName, eventName)
                    );
                } catch { }
                return;
            }

            if (eventName == "IsVisibleChanged")
            {
                if (ctrl is UIElement)
                {
                    ((UIElement)ctrl).IsVisibleChanged += (s, e) =>
                    {
                        string val = LengthPrefix(e.NewValue.ToString());
                        SendToAhk("EVENT|" + winId + "|" + ctrlName + "|IsVisibleChanged|" + val + "\n");
                    };
                }
                return;
            }

            var evt = ctrl.GetType().GetEvent(eventName);
            if (evt == null)
            {
                _boundEvents.Remove(eventKey);
                return;
            }

            var parameters = evt.EventHandlerType.GetMethod("Invoke").GetParameters();

            if (eventName == "Drop")
            {
                if (ctrl is UIElement)
                {
                    ((UIElement)ctrl).AllowDrop = true;
                    ((UIElement)ctrl).Drop += (s, e) =>
                    {
                        if (e.Data.GetDataPresent(DataFormats.FileDrop))
                        {
                            string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                            string fileList = LengthPrefix(string.Join("|", files));
                            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|Drop|" + fileList + "\n");
                        }
                    };
                }
                return;
            }

            var pExprs = parameters.Select(p => System.Linq.Expressions.Expression.Parameter(p.ParameterType, p.Name)).ToArray();
            System.Linq.Expressions.MethodCallExpression call;

            if (fpsLimit > 0)
            {
                var throttler = new EventThrottler(fpsLimit, queueLimited, this, ctrlName, eventName);
                var throttlerConst = System.Linq.Expressions.Expression.Constant(throttler);

                if (pExprs.Length >= 2)
                {
                    var method = typeof(EventThrottler).GetMethod("InvokeWithArgs");
                    var objCast = System.Linq.Expressions.Expression.Convert(pExprs[1], typeof(object));
                    call = System.Linq.Expressions.Expression.Call(throttlerConst, method, objCast);
                }
                else
                {
                    var method = typeof(EventThrottler).GetMethod("Invoke");
                    call = System.Linq.Expressions.Expression.Call(throttlerConst, method);
                }
            }
            else
            {
                if (pExprs.Length >= 2)
                {
                    var dumpStateWithArgsMethod = this.GetType().GetMethod("DumpStateWithArgs", BindingFlags.NonPublic | BindingFlags.Instance);
                    var objCast = System.Linq.Expressions.Expression.Convert(pExprs[1], typeof(object));
                    call = System.Linq.Expressions.Expression.Call(System.Linq.Expressions.Expression.Constant(this), dumpStateWithArgsMethod, System.Linq.Expressions.Expression.Constant(ctrlName), System.Linq.Expressions.Expression.Constant(eventName), objCast);
                }
                else
                {
                    var dumpStateMethod = this.GetType().GetMethod("DumpState", BindingFlags.NonPublic | BindingFlags.Instance);
                    call = System.Linq.Expressions.Expression.Call(System.Linq.Expressions.Expression.Constant(this), dumpStateMethod, System.Linq.Expressions.Expression.Constant(ctrlName), System.Linq.Expressions.Expression.Constant(eventName));
                }
            }

            var lambda = System.Linq.Expressions.Expression.Lambda(evt.EventHandlerType, call, pExprs);
            evt.AddEventHandler(ctrl, lambda.Compile());
        }
        catch (Exception ex)
        {
            _boundEvents.Remove(eventKey);
            try {
                System.IO.File.AppendAllText(
                    System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpfDebug.log"),
                    string.Format("BindEvent exception: Control '{0}', Event '{1}' - {2}\n", ctrlName, eventName, ex.ToString())
                );
            } catch { }
        }
    }

    public class EventThrottler
    {
        private int _delayMs;
        private bool _queueLimited;
        private object _bridge;
        private string _ctrlName;
        private string _eventName;
        private DateTime _lastFire = DateTime.MinValue;
        private bool _timerRunning = false;
        private object _lastArgs = null;
        private bool _hasPending = false;
        private object _sync = new object();
        private System.Collections.Generic.Queue<object> _queue = new System.Collections.Generic.Queue<object>();

        public EventThrottler(int fpsLimit, bool queueLimited, object bridge, string ctrlName, string eventName)
        {
            _delayMs = 1000 / fpsLimit;
            _queueLimited = queueLimited;
            _bridge = bridge;
            _ctrlName = ctrlName;
            _eventName = eventName;
        }

        public void Invoke() { InvokeWithArgs(null); }

        public void InvokeWithArgs(object args)
        {
            lock (_sync)
            {
                var now = DateTime.UtcNow;
                if (_queueLimited)
                {
                    _queue.Enqueue(args);
                    if (!_timerRunning)
                    {
                        _timerRunning = true;
                        ProcessQueueAsync();
                    }
                }
                else
                {
                    if (now - _lastFire >= TimeSpan.FromMilliseconds(_delayMs))
                    {
                        _lastFire = now;
                        FireEvent(args);
                    }
                    else
                    {
                        _lastArgs = args;
                        _hasPending = true;
                        if (!_timerRunning)
                        {
                            _timerRunning = true;
                            int waitMs = (int)(_delayMs - (now - _lastFire).TotalMilliseconds);
                            if (waitMs <= 0) waitMs = 1;
                            System.Threading.Tasks.Task.Delay(waitMs).ContinueWith(t =>
                            {
                                lock (_sync)
                                {
                                    _timerRunning = false;
                                    if (_hasPending)
                                    {
                                        _hasPending = false;
                                        _lastFire = DateTime.UtcNow;
                                        FireEvent(_lastArgs);
                                        _lastArgs = null;
                                    }
                                }
                            });
                        }
                    }
                }
            }
        }

        private async void ProcessQueueAsync()
        {
            while (true)
            {
                object args = null;
                lock (_sync)
                {
                    if (_queue.Count > 0) args = _queue.Dequeue();
                    else { _timerRunning = false; return; }
                }
                FireEvent(args);
                await System.Threading.Tasks.Task.Delay(_delayMs);
            }
        }

        private void FireEvent(object args)
        {
            var bridgeType = _bridge.GetType();
            Action action = () =>
            {
                try
                {
                    if (args != null)
                    {
                        bridgeType.GetMethod("DumpStateWithArgs", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(_bridge, new object[] { _ctrlName, _eventName, args });
                    }
                    else
                    {
                        bridgeType.GetMethod("DumpState", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(_bridge, new object[] { _ctrlName, _eventName });
                    }
                }
                catch { }
            };

            if (Application.Current != null && !Application.Current.Dispatcher.CheckAccess())
            {
                Application.Current.Dispatcher.BeginInvoke(action);
            }
            else
            {
                action();
            }
        }
    }

    // Length-prefixed encoding helper: encodes a value as "BYTELEN:rawvalue"
    // This replaces Base64 encoding — zero overhead, binary-safe for any characters
    // including emojis, pipes, newlines, null chars, CJK, etc.
    private static string LengthPrefix(string val)
    {
        if (val == null) val = "";
        int byteLen = Encoding.UTF8.GetByteCount(val);
        return byteLen + ":" + val;
    }

    // Reusable helper: extract the current value of a named control.
    // Used by both CollectState() and MQUERY handler.
    // Extract visible text from a TextBlock with Run elements (from emoji auto-detection)
    private string GetTextFromInlines(TextBlock tb)
    {
        var sb = new StringBuilder();
        foreach (var inline in tb.Inlines)
        {
            if (inline is System.Windows.Documents.Run)
            {
                sb.Append(((System.Windows.Documents.Run)inline).Text);
            }
        }
        return sb.ToString();
    }

    private string GetControlValue(string trackName)
    {
        string cName = trackName;
        string suffix = null;

        // New: '>' delimiter for rich queries (e.g. "MyList>Count", "MyGrid>SelectedRow")
        int gtIdx = cName.IndexOf('>');
        if (gtIdx > 0)
        {
            suffix = cName.Substring(gtIdx + 1);
            cName = cName.Substring(0, gtIdx);
        }
        // Legacy: _CaretIndex backward compat
        else if (cName.EndsWith("_CaretIndex"))
        {
            cName = cName.Substring(0, cName.Length - 11);
            suffix = "CaretIndex";
        }

        var c = win.FindName(cName);
        if (c == null) return null;

        string val = "";

        // --- Suffix queries (rich component data) ---
        if (suffix != null)
        {
            switch (suffix)
            {
                case "CaretIndex":
                    if (c is TextBox) val = ((TextBox)c).CaretIndex.ToString();
                    break;
                case "Count":
                    if (c is ItemsControl) val = ((ItemsControl)c).Items.Count.ToString();
                    break;
                case "SelectedIndex":
                    if (c is System.Windows.Controls.Primitives.Selector)
                        val = ((System.Windows.Controls.Primitives.Selector)c).SelectedIndex.ToString();
                    else if (c is TabControl)
                        val = ((TabControl)c).SelectedIndex.ToString();
                    break;
                case "SelectedHeader":
                    if (c is TabControl)
                    {
                        TabControl _tc = (TabControl)c;
                        if (_tc.SelectedItem is TabItem)
                        {
                            TabItem _ti = (TabItem)_tc.SelectedItem;
                            val = _ti.Header != null ? _ti.Header.ToString() : "";
                        }
                    }
                    break;
                case "Items":
                    if (c is ItemsControl)
                    {
                        ItemsControl _ic = (ItemsControl)c;
                        var items = new System.Collections.Generic.List<string>();
                        foreach (var item in _ic.Items)
                        {
                            if (item is ContentControl)
                            {
                                ContentControl _cc = (ContentControl)item;
                                object _tag = _cc.Tag;
                                object _content = _cc.Content;
                                if (_tag != null && _tag.ToString() != "")
                                {
                                    items.Add(_tag.ToString());
                                }
                                else if (_content is TextBlock)
                                {
                                    // Handle emoji auto-detection: Content is a TextBlock with Runs
                                    TextBlock _tb = (TextBlock)_content;
                                    items.Add(_tb.Text != null && _tb.Text.Length > 0 ? _tb.Text : GetTextFromInlines(_tb));
                                }
                                else if (_content is string)
                                {
                                    items.Add((string)_content);
                                }
                                else if (_content != null)
                                {
                                    items.Add(_content.ToString());
                                }
                                else
                                {
                                    items.Add("");
                                }
                            }
                            else
                            {
                                items.Add(item != null ? item.ToString() : "");
                            }
                        }
                        val = string.Join("|", items);
                    }
                    break;
                case "SelectedRow":
                    // DataGrid: return pipe-delimited cell values of selected row
                    if (c is DataGrid && ((DataGrid)c).SelectedItem != null)
                    {
                        DataGrid _dg = (DataGrid)c;
                        var props = _dg.SelectedItem.GetType().GetProperties();
                        var cells = new System.Collections.Generic.List<string>();
                        foreach (var p in props)
                        {
                            try
                            {
                                object pv = p.GetValue(_dg.SelectedItem);
                                cells.Add(pv != null ? pv.ToString() : "");
                            }
                            catch { }
                        }
                        val = string.Join("|", cells);
                    }
                    break;
                case "FilteredCount":
                    // DataGrid: count of visible rows in the current view
                    if (c is DataGrid)
                    {
                        DataGrid _dg2 = (DataGrid)c;
                        var view = System.Windows.Data.CollectionViewSource.GetDefaultView(_dg2.ItemsSource != null ? _dg2.ItemsSource : _dg2.Items);
                        if (view != null)
                        {
                            int count = 0;
                            foreach (var item in view) count++;
                            val = count.ToString();
                        }
                        else
                        {
                            val = _dg2.Items.Count.ToString();
                        }
                    }
                    break;
                case "Nodes":
                    // Canvas-based node editor: serialize node positions and data
                    if (c is Canvas)
                    {
                        Canvas _canvas = (Canvas)c;
                        var nodes = new System.Collections.Generic.List<string>();
                        foreach (UIElement child in _canvas.Children)
                        {
                            if (child is FrameworkElement)
                            {
                                FrameworkElement _fe = (FrameworkElement)child;
                                if (_fe.Name != null && _fe.Name != "")
                                {
                                    double x = Canvas.GetLeft(_fe); if (double.IsNaN(x)) x = 0;
                                    double y = Canvas.GetTop(_fe); if (double.IsNaN(y)) y = 0;
                                    string nodeTag = _fe.Tag as string;
                                    if (nodeTag == null) nodeTag = "";
                                    nodes.Add(_fe.Name + ":" + x + "," + y + (nodeTag != "" ? ":" + nodeTag : ""));
                                }
                            }
                        }
                        val = string.Join("|", nodes);
                    }
                    break;
                case "Connections":
                    // Canvas: find Path elements that represent connections (by Tag convention)
                    if (c is Canvas)
                    {
                        Canvas _canvas2 = (Canvas)c;
                        var conns = new System.Collections.Generic.List<string>();
                        foreach (UIElement child in _canvas2.Children)
                        {
                            if (child is System.Windows.Shapes.Path)
                            {
                                System.Windows.Shapes.Path _path = (System.Windows.Shapes.Path)child;
                                string connTag = _path.Tag as string;
                                if (connTag != null && connTag.StartsWith("conn:"))
                                {
                                    conns.Add(connTag.Substring(5));
                                }
                            }
                        }
                        val = string.Join("|", conns);
                    }
                    break;
                case "SelectedNode":
                    // Canvas: find the focused/selected node element
                    if (c is Canvas)
                    {
                        Canvas _canvas3 = (Canvas)c;
                        foreach (UIElement child in _canvas3.Children)
                        {
                            if (child is FrameworkElement)
                            {
                                FrameworkElement _fe2 = (FrameworkElement)child;
                                string _feTag = _fe2.Tag as string;
                                if (_feTag != null && _feTag.Contains("selected"))
                                {
                                    val = _fe2.Name != null ? _fe2.Name : "";
                                    break;
                                }
                            }
                        }
                    }
                    break;
                case "Position":
                    if (c is System.Windows.Media.Visual)
                    {
                        try
                        {
                            var visual = (System.Windows.Media.Visual)c;
                            var parentWindow = Window.GetWindow(visual);
                            if (parentWindow != null)
                            {
                                var pos = visual.TransformToAncestor(parentWindow).Transform(new System.Windows.Point(0, 0));
                                val = pos.X + "," + pos.Y;
                            }
                        }
                        catch { }
                    }
                    break;
                case "Handle":
                    val = new System.Windows.Interop.WindowInteropHelper(win).Handle.ToString();
                    break;
                default:
                    // Generic: try to read an arbitrary dependency property by name
                    if (c is FrameworkElement)
                    {
                        try
                        {
                            var pi = c.GetType().GetProperty(suffix);
                            if (pi != null)
                            {
                                object pVal = pi.GetValue(c);
                                val = pVal != null ? pVal.ToString() : "";
                            }
                        }
                        catch { }
                    }
                    break;
            }
            return val;
        }

        // --- Default value extraction (no suffix) ---
        if (c is TextBox) val = ((TextBox)c).Text;
        else if (c is PasswordBox) val = ((PasswordBox)c).Password;
        else if (c is ToggleButton) { bool? isChecked = ((ToggleButton)c).IsChecked; val = isChecked.HasValue ? isChecked.Value.ToString() : "False"; }
        else if (c is RangeBase) val = ((RangeBase)c).Value.ToString();
        else if (c is ComboBox)
        {
            ComboBox cb = (ComboBox)c;
            if (cb.SelectedItem is ComboBoxItem)
            {
                object tag = ((ComboBoxItem)cb.SelectedItem).Tag;
                object content = ((ComboBoxItem)cb.SelectedItem).Content;
                if (tag != null && tag.ToString() != "") val = tag.ToString();
                else if (content is TextBlock) val = GetTextFromInlines((TextBlock)content);
                else if (content != null) val = content.ToString();
                else val = "";
            }
            else val = cb.Text;
        }
        else if (c is TreeView)
        {
            TreeView tv = (TreeView)c;
            if (tv.SelectedItem is TreeViewItem)
            {
                object tag = ((TreeViewItem)tv.SelectedItem).Tag;
                val = tag != null && tag.ToString() != "" ? tag.ToString() : "";
                if (string.IsNullOrEmpty(val))
                {
                    object header = ((TreeViewItem)tv.SelectedItem).Header;
                    val = header != null ? header.ToString() : "";
                }
            }
        }
        else if (c is ListBox)
        {
            ListBox lb = (ListBox)c;
            if (lb.SelectedItem is ListBoxItem)
            {
                object tag = ((ListBoxItem)lb.SelectedItem).Tag;
                object content = ((ListBoxItem)lb.SelectedItem).Content;
                if (tag != null && tag.ToString() != "") val = tag.ToString();
                else if (content is TextBlock) val = GetTextFromInlines((TextBlock)content);
                else if (content != null) val = content.ToString();
                else val = "";
            }
            else if (lb.SelectedItem != null) val = lb.SelectedItem.ToString();
        }
        // New: TextBlock, TabControl, DataGrid, Image — previously unsupported
        else if (c is TextBlock) val = ((TextBlock)c).Text;
        else if (c is System.Windows.Controls.Image)
        {
            var imgSrc = ((System.Windows.Controls.Image)c).Source;
            val = imgSrc != null ? imgSrc.ToString() : "";
        }
        else if (c is TabControl) val = ((TabControl)c).SelectedIndex.ToString();
        else if (c is DataGrid) val = ((DataGrid)c).SelectedIndex.ToString();

        if (val == null) val = "";
        return val;
    }

    public string CollectState()
    {
        var sb = new StringBuilder();
        foreach (var t in tracked)
        {
            string val = GetControlValue(t);
            if (val != null)
            {
                sb.Append(t + "=" + LengthPrefix(val) + "\n");
            }
        }
        return sb.ToString();
    }

    // Collect state for specific control names only (used by MQUERY)
    public string CollectStateFor(string[] names)
    {
        var sb = new StringBuilder();
        foreach (var name in names)
        {
            string trimmed = name.Trim();
            if (trimmed.Length == 0) continue;
            string val = GetControlValue(trimmed);
            if (val != null)
            {
                sb.Append(trimmed + "=" + LengthPrefix(val) + "\n");
            }
        }
        return sb.ToString();
    }

    private DateTime lastSendMouseMove = DateTime.MinValue;

    private void DumpStateWithArgs(string cName, string eName, object e)
    {
        if (e is System.Windows.Input.KeyEventArgs)
        {
            eName += ":" + ((System.Windows.Input.KeyEventArgs)e).Key.ToString();
        }
#if ENABLE_WEBVIEW
        else if (e is Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs) {
            var we = (Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs)e;
            var sb = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName + "|" + LengthPrefix(we.WebMessageAsJson) + "\n");
            SendToAhk(sb.ToString());
            return;
        }
#endif
        else if (e is System.Windows.Input.MouseEventArgs)
        {
            if (eName == "MouseMove" || eName == "PreviewMouseMove")
            {
                if ((DateTime.Now - lastSendMouseMove).TotalMilliseconds < 16) return;
                lastSendMouseMove = DateTime.Now;
            }
            var me = (System.Windows.Input.MouseEventArgs)e;
            var ctrl = FindControlByPath(cName) as System.Windows.IInputElement;
            if (ctrl != null)
            {
                var pos = me.GetPosition(ctrl);
                string coords = ((int)pos.X) + "," + ((int)pos.Y);
                var sb = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName + "|" + LengthPrefix(coords) + "\n");
                sb.Append(cName + "=" + LengthPrefix(coords) + "\n");
                sb.Append("DragCoords=" + LengthPrefix(coords) + "\n");
                SendToAhkAsync(sb.ToString());
                return;
            }
        }
        DumpState(cName, eName);
    }

    private System.Collections.Generic.Dictionary<string, DateTime> lastEventSendTimes = new System.Collections.Generic.Dictionary<string, DateTime>();

    private void DumpState(string cName, string eName)
    {
        var ctrl = FindControlByPath(cName) as FrameworkElement;
        if (ctrl != null)
        {
            string tag = ctrl.Tag as string ?? "";

            if (eName == "TextChanged" && !ctrl.IsKeyboardFocusWithin && !tag.Contains("AllowPassive")) return;
            if (eName == "ValueChanged" && !ctrl.IsMouseOver && !ctrl.IsKeyboardFocusWithin && !ctrl.IsMouseCaptured && !tag.Contains("AllowPassive")) return;

            if (tag.Contains("Throttle"))
            {
                int delay = 50;
                var match = System.Text.RegularExpressions.Regex.Match(tag, @"Throttle:(\d+)");
                if (match.Success) delay = int.Parse(match.Groups[1].Value);

                string key = cName + "|" + eName;
                if (lastEventSendTimes.ContainsKey(key))
                {
                    if ((DateTime.Now - lastEventSendTimes[key]).TotalMilliseconds < delay)
                    {
                        return;
                    }
                }
                lastEventSendTimes[key] = DateTime.Now;
            }
        }

        if (eName == "MouseMove" || eName == "PreviewMouseMove")
        {
            if ((DateTime.Now - lastSendMouseMove).TotalMilliseconds < 16) return;
            lastSendMouseMove = DateTime.Now;
        }
        var sb = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName + "\n");
        if (LightweightEvents)
        {
            // Lightweight mode: only send the triggering control's value.
            // Callbacks should use ui.Query() for additional values.
            string triggerVal = GetControlValue(cName);
            if (triggerVal != null)
            {
                sb.Append(cName + "=" + LengthPrefix(triggerVal) + "\n");
            }
        }
        else
        {
            // Full mode (default): send all tracked controls' values.
            // Backwards compatible — callbacks can read any tracked control from state map.
            sb.Append(CollectState());
        }
        SendToAhkAsync(sb.ToString());
    }

    private void SendToAhkAsync(string text)
    {
        System.Threading.ThreadPool.QueueUserWorkItem(_ =>
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text);
            var cds = new COPYDATASTRUCT { cbData = bytes.Length + 1, lpData = Marshal.AllocHGlobal(bytes.Length + 1) };
            Marshal.Copy(bytes, 0, cds.lpData, bytes.Length);
            Marshal.WriteByte(cds.lpData, bytes.Length, 0);
            SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref cds);
            Marshal.FreeHGlobal(cds.lpData);
        });
    }

    private void SendToAhk(string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        var cds = new COPYDATASTRUCT { cbData = bytes.Length + 1, lpData = Marshal.AllocHGlobal(bytes.Length + 1) };
        Marshal.Copy(bytes, 0, cds.lpData, bytes.Length);
        Marshal.WriteByte(cds.lpData, bytes.Length, 0);
        SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref cds);
        Marshal.FreeHGlobal(cds.lpData);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == 0x004A)
        {
            try
            {
                var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(lParam, typeof(COPYDATASTRUCT));
                byte[] bytes = new byte[cds.cbData];
                Marshal.Copy(cds.lpData, bytes, 0, cds.cbData);
                ProcessMessage(hwnd, Encoding.UTF8.GetString(bytes).TrimEnd('\0'));
            }
            catch { }
            handled = true;
        }
        else if (msg == 0x0084) // WM_NCHITTEST
        {
            try
            {
                var btn = win.FindName("BtnMaximize") as System.Windows.Controls.Button;
                if (btn != null && btn.IsVisible)
                {
                    short screenX = (short)(lParam.ToInt64() & 0xFFFF);
                    short screenY = (short)((lParam.ToInt64() >> 16) & 0xFFFF);

                    Point topLeft = btn.PointToScreen(new Point(0, 0));
                    Point bottomRight = btn.PointToScreen(new Point(btn.ActualWidth, btn.ActualHeight));

                    if (screenX >= topLeft.X && screenX <= bottomRight.X &&
                        screenY >= topLeft.Y && screenY <= bottomRight.Y)
                    {
                        // Apply custom hover highlight (same as #20FFFFFF style trigger)
                        btn.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(0x20, 0xFF, 0xFF, 0xFF));

                        handled = true;
                        return new IntPtr(9); // HTMAXBUTTON
                    }
                    else
                    {
                        // Reset background if cursor moved off the button
                        if (btn.Background != System.Windows.Media.Brushes.Transparent)
                        {
                            btn.Background = System.Windows.Media.Brushes.Transparent;
                        }
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x0020) // WM_SETCURSOR
        {
            try
            {
                int hitTest = (int)(lParam.ToInt64() & 0xFFFF);
                if (hitTest == 9) // HTMAXBUTTON
                {
                    IntPtr hCursor = LoadCursor(IntPtr.Zero, 32649); // IDC_HAND
                    if (hCursor != IntPtr.Zero)
                    {
                        SetCursor(hCursor);
                        handled = true;
                        return new IntPtr(1); // True
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x02A2 || msg == 0x02A3) // WM_NCMOUSELEAVE or WM_MOUSELEAVE
        {
            try
            {
                var btn = win.FindName("BtnMaximize") as System.Windows.Controls.Button;
                if (btn != null && btn.Background != System.Windows.Media.Brushes.Transparent)
                {
                    btn.Background = System.Windows.Media.Brushes.Transparent;
                }
            }
            catch { }
        }
        else if (msg == 0x00A1) // WM_NCLBUTTONDOWN
        {
            if (wParam.ToInt32() == 9) // HTMAXBUTTON
            {
                win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                handled = true;
                return IntPtr.Zero;
            }
        }
        else if (msg == 0x0024)
        { // WM_GETMINMAXINFO
            try
            {
                MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(lParam, typeof(MINMAXINFO));
                IntPtr monitor = MonitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
                if (monitor != IntPtr.Zero)
                {
                    MONITORINFO monitorInfo = new MONITORINFO();
                    monitorInfo.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                    GetMonitorInfo(monitor, ref monitorInfo);
                    RECT rcWorkArea = monitorInfo.rcWork;
                    RECT rcMonitorArea = monitorInfo.rcMonitor;
                    mmi.ptMaxPosition.x = Math.Abs(rcWorkArea.left - rcMonitorArea.left);
                    mmi.ptMaxPosition.y = Math.Abs(rcWorkArea.top - rcMonitorArea.top);
                    mmi.ptMaxSize.x = Math.Abs(rcWorkArea.right - rcWorkArea.left);
                    mmi.ptMaxSize.y = Math.Abs(rcWorkArea.bottom - rcWorkArea.top);
                }
                Marshal.StructureToPtr(mmi, lParam, true);
            }
            catch { }
        }
        else if (msg == 0x020A)
        { // WM_MOUSEWHEEL
            if (win != null && !win.IsEnabled) { handled = true; return IntPtr.Zero; }
            try
            {
                int delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);
                DependencyObject target = System.Windows.Input.Mouse.DirectlyOver as DependencyObject;

                while (target != null)
                {
                    ScrollViewer sv = target as ScrollViewer;
                    if (sv != null && sv.VerticalScrollBarVisibility == ScrollBarVisibility.Disabled && sv.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled)
                    {
                        bool canScroll = (delta > 0 && sv.HorizontalOffset > 1.0) || (delta < 0 && (sv.ScrollableWidth - sv.HorizontalOffset) > 1.0);
                        if (canScroll)
                        {
                            sv.ScrollToHorizontalOffset(sv.HorizontalOffset - delta);
                            handled = true;
                            break;
                        }
                    }

                    if (target is System.Windows.Media.Visual || target is System.Windows.Media.Media3D.Visual3D)
                    {
                        target = System.Windows.Media.VisualTreeHelper.GetParent(target);
                    }
                    else
                    {
                        target = LogicalTreeHelper.GetParent(target);
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x020E)
        { // WM_MOUSEHWHEEL
            if (win != null && !win.IsEnabled) { handled = true; return IntPtr.Zero; }
            try
            {
                int delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);
                DependencyObject target = System.Windows.Input.Mouse.DirectlyOver as DependencyObject;
                while (target != null)
                {
                    ScrollViewer sv = target as ScrollViewer;
                    if (sv != null && sv.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled)
                    {
                        bool canScroll = (delta < 0 && sv.HorizontalOffset > 1.0) || (delta > 0 && (sv.ScrollableWidth - sv.HorizontalOffset) > 1.0);
                        if (canScroll)
                        {
                            sv.ScrollToHorizontalOffset(sv.HorizontalOffset + delta);
                            handled = true;
                            break;
                        }
                    }
                    if (target is System.Windows.Media.Visual || target is System.Windows.Media.Media3D.Visual3D)
                    {
                        target = System.Windows.Media.VisualTreeHelper.GetParent(target);
                    }
                    else
                    {
                        target = LogicalTreeHelper.GetParent(target);
                    }
                }
            }
            catch { }
        }
        return IntPtr.Zero;
    }

    private void ProcessMessage(IntPtr hwnd, string text)
    {
        foreach (string line in text.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                ProcessSingleMessage(hwnd, line);
            }
            catch (Exception ex)
            {
                if (EnableLogging)
                {
                    try { System.IO.File.AppendAllText(System.Environment.ExpandEnvironmentVariables("%TEMP%\\AhkWpf\\AhkWpfDebug.log"), "ProcessMessage line failed: " + line + " => " + ex.Message + "\n"); } catch { }
                }
            }
        }
    }

    private bool _isInspectMode = false;
    private FrameworkElement _lastHighlightedElement = null;
    private bool IsIncludedInDevTools(DependencyObject root)
    {
        if (root == null) return false;
        var fe = root as FrameworkElement;

        // Skip internal control template parts unless explicitly generated by AHK
        if (fe != null && fe.TemplatedParent != null)
        {
            if (string.IsNullOrEmpty(fe.Uid) || !fe.Uid.StartsWith("ahk:"))
                return false;
        }

        string name = fe != null ? fe.Name : "";

        if (name.StartsWith("PART_")) return false;
        if (root is System.Windows.Controls.Primitives.ScrollBar) return false;
        if (root is System.Windows.Controls.ScrollContentPresenter) return false;

        return (!string.IsNullOrEmpty(name) && !name.StartsWith("PART_")) ||
               root is System.Windows.Controls.Button || root is System.Windows.Controls.TextBox ||
               root is System.Windows.Controls.ComboBox || root is System.Windows.Controls.TreeView ||
               root is System.Windows.Controls.ListBox || root is System.Windows.Controls.TabControl ||
               root is System.Windows.Controls.DataGrid || root is System.Windows.Controls.Image ||
               root is System.Windows.Controls.ScrollViewer || root is System.Windows.Controls.TextBlock ||
               root is System.Windows.Controls.Panel ||
               root is Window;
    }

    private bool IsPickerSkippable(FrameworkElement fe)
    {
        if (fe == null) return false;
        if (fe is Window) return true;
        string name = fe.Name ?? "";
        if (name == "AppGrid" || name == "AppScale" || name == "AppOverlay") return true;
        if (name.IndexOf("Overlay", StringComparison.OrdinalIgnoreCase) >= 0) return true;
        return false;
    }

    private FrameworkElement GetElementAtPoint(DependencyObject root, System.Windows.Point pos, Window win)
    {
        var uiRoot = root as UIElement;
        if (uiRoot != null && (!uiRoot.IsVisible || uiRoot.Opacity == 0)) return null;

        int count = System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = count - 1; i >= 0; i--)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(root, i);
            var result = GetElementAtPoint(child, pos, win);
            if (result != null) return result;
        }

        var fe = root as FrameworkElement;
        if (fe != null && fe.ActualWidth > 0 && fe.ActualHeight > 0)
        {
            if (IsIncludedInDevTools(fe) && !IsPickerSkippable(fe))
            {
                try
                {
                    var transform = fe.TransformToAncestor(win);
                    System.Windows.Rect bounds = new System.Windows.Rect(0, 0, fe.ActualWidth, fe.ActualHeight);
                    System.Windows.Rect rectOnWin = transform.TransformBounds(bounds);
                    if (rectOnWin.Contains(pos))
                    {
                        return fe;
                    }
                }
                catch { }
            }
        }
        return null;
    }

    private void Win_InspectMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_isInspectMode) return;
        var win = sender as Window;
        if (win == null) return;

        var fe = GetElementAtPoint(win, e.GetPosition(win), win);
        if (fe != _lastHighlightedElement)
        {
            SetHighlight(fe, fe != null);
            _lastHighlightedElement = fe;
        }
    }

    private void Win_InspectMouseDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!_isInspectMode) return;
        e.Handled = true;
        var win = sender as Window;
        if (win == null) return;

        var fe = GetElementAtPoint(win, e.GetPosition(win), win);
        if (fe != null)
        {
            string hash = fe.GetHashCode().ToString();
            SendToAhk("EVENT|" + winId + "|AppWindow|InspectPicked|" + LengthPrefix(hash) + "\n");
        }

        // Turn off inspect mode after picking
        _isInspectMode = false;
        SetHighlight(null, false);
        _lastHighlightedElement = null;
        win.PreviewMouseMove -= Win_InspectMouseMove;
        win.PreviewMouseDown -= Win_InspectMouseDown;
        win.Cursor = System.Windows.Input.Cursors.Arrow;
        SetHighlight(win, false);
    }

    private void ProcessSingleMessage(IntPtr hwnd, string text)
    {
        string[] parts = text.Split(new[] { '|' }, 3);
        if (parts.Length < 2) return;
        if (parts.Length > 2)
        {
            parts[2] = parts[2].Replace("&#x0A;", "\n").Replace("&#x0D;", "\r");
        }

        // MQUERY: batched targeted query — returns values for specific controls in one IPC call
        // Format: MQUERY|ctrl1,ctrl2,ctrl3  or  MQUERY|*  (all tracked)
        if (parts[0] == "MQUERY" && parts.Length >= 2)
        {
            string query = parts.Length >= 3 ? parts[1] + "|" + parts[2] : parts[1];
            string stateData;
            if (query.Trim() == "*")
            {
                stateData = CollectState();
            }
            else
            {
                string[] names = query.Split(',');
                stateData = CollectStateFor(names);
            }
            int count = stateData.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;
            SendToAhk("MRESPONSE|" + winId + "|" + count + "\n" + stateData);
            return;
        }

        // CONFIG: runtime configuration changes
        // Format: CONFIG|Key|Value
        if (parts[0] == "CONFIG" && parts.Length >= 3)
        {
            if (parts[1] == "LightweightEvents")
            {
                LightweightEvents = parts[2] == "1" || parts[2].ToLower() == "true";
            }
            return;
        }

        // DEVTOOLS: Chrome-like developer tools hooks
        // Format: DEVTOOLS|Command|Arg
        if (parts[0] == "DEVTOOLS")
        {
            if (parts[1] == "GetTree")
            {
                string treeData = SerializeVisualTree(win);
                SendToAhk("EVENT|" + winId + "|Engine|DevToolsTree|" + LengthPrefix(treeData) + "\n");
            }
            else if (parts[1] == "Highlight" && parts.Length >= 3)
            {
                string elementName = parts[2];
                FrameworkElement element = null;
                if (elementName == "Window")
                {
                    element = win;
                }
                else if (!string.IsNullOrEmpty(elementName))
                {
                    element = FindElementByHash(win, elementName);
                    if (element == null)
                    {
                        element = win.FindName(elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        element = FindLogicalNodeDeep(win, elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        WalkVisualTree(win, (DependencyObject d) =>
                        {
                            if (element != null) return;
                            var fe = d as FrameworkElement;
                            if (fe != null && fe.Name == elementName)
                            {
                                element = fe;
                            }
                        });
                    }
                }

                SetHighlight(element, element != null);
            }
            else if (parts[1] == "GetProps" && parts.Length >= 3)
            {
                string elementName = parts[2];
                FrameworkElement element = null;
                if (elementName == "Window")
                {
                    element = win;
                }
                else if (!string.IsNullOrEmpty(elementName))
                {
                    element = FindElementByHash(win, elementName);
                    if (element == null)
                    {
                        element = win.FindName(elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        element = FindLogicalNodeDeep(win, elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        WalkVisualTree(win, (DependencyObject d) =>
                        {
                            if (element != null) return;
                            var fe = d as FrameworkElement;
                            if (fe != null && fe.Name == elementName)
                            {
                                element = fe;
                            }
                        });
                    }
                }

                if (element != null)
                {
                    string propsData = InspectElementProperties(element);
                    SendToAhk("EVENT|" + winId + "|Engine|DevToolsProps|" + LengthPrefix(elementName + "\n" + propsData) + "\n");
                }
            }
            return;
        }

        if (parts[0] == "AppWindow" && parts[1] == "InspectMode" && parts.Length >= 3)
        {
            _isInspectMode = parts[2] == "1" || parts[2].ToLower() == "true";
            if (_isInspectMode)
            {
                _lastHighlightedElement = null;
                win.PreviewMouseMove -= Win_InspectMouseMove;
                win.PreviewMouseDown -= Win_InspectMouseDown;
                win.PreviewMouseMove += Win_InspectMouseMove;
                win.PreviewMouseDown += Win_InspectMouseDown;
                win.Cursor = System.Windows.Input.Cursors.Cross;
            }
            else
            {
                win.PreviewMouseMove -= Win_InspectMouseMove;
                win.PreviewMouseDown -= Win_InspectMouseDown;
                win.Cursor = System.Windows.Input.Cursors.Arrow;
                SetHighlight(win, false);
            }
            return;
        }

        if (parts.Length < 3) return;
        if (parts[0] == "Window" && parts[1] == "DWM")
        {
            string[] p = parts[2].Split(',');
            int backdrop = int.Parse(p[0]), dark = int.Parse(p[1]);
            win.Resources["DWM_Backdrop"] = backdrop;
            win.Resources["DWM_Dark"] = dark;
            if (win.AllowsTransparency) return; // Do not apply DWM backdrop / colors that clobber transparency!

            DwmSetWindowAttribute(hwnd, 20, ref dark, 4);
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, 4);
            int borderColor = -2; // DWMWA_COLOR_NONE (0xFFFFFFFE)
            DwmSetWindowAttribute(hwnd, 34, ref borderColor, 4);

            // Re-apply shadow policy if glass frame thickness was set to prevent theme change override
            if (win.Resources.Contains("GlassFrameThicknessVal"))
            {
                double val = (double)win.Resources["GlassFrameThicknessVal"];
                int policy = (val == 0) ? 1 : 2;
                DwmSetWindowAttribute(hwnd, 2, ref policy, 4);

                MARGINS margins = (val == 0) ? new MARGINS(0, 0, 0, 0) : new MARGINS(-1, -1, -1, -1);
                DwmExtendFrameIntoClientArea(hwnd, ref margins);
                SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0037);
            }
        }
        else if (parts[0] == "Window" && parts[1] == "ResizeMode")
        {
            try
            {
                if (parts[2].ToLower() == "noresize" || parts[2] == "0")
                {
                    win.ResizeMode = System.Windows.ResizeMode.NoResize;
                    var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
                    if (chrome != null)
                    {
                        chrome.ResizeBorderThickness = new Thickness(0);
                    }
                }
                else
                {
                    win.ResizeMode = System.Windows.ResizeMode.CanResize;
                    var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
                    if (chrome != null)
                    {
                        double val = 0;
                        if (win.Resources.Contains("GlassFrameThicknessVal"))
                        {
                            val = (double)win.Resources["GlassFrameThicknessVal"];
                        }
                        if (val == 0)
                        {
                            chrome.ResizeBorderThickness = win.AllowsTransparency ? new Thickness(0) : new Thickness(6);
                        }
                        else
                        {
                            chrome.ResizeBorderThickness = new Thickness(0);
                        }
                    }
                }
            }
            catch { }
        }
        else if (parts[0] == "Window" && parts[1] == "NativeOwner")
        {
            try
            {
                IntPtr ownerHwnd = new IntPtr(long.Parse(parts[2]));
                if (ownerHwnd != IntPtr.Zero)
                {
                    win.Resources["OriginalNativeOwner"] = ownerHwnd;
                }
                IntPtr hwndVal = new WindowInteropHelper(win).Handle;
                if (hwndVal != IntPtr.Zero)
                {
                    SetWindowLong(hwndVal, -8, ownerHwnd);
                }
                InheritWindowIconAndTitle(win, parts[2]);
            }
            catch { }
        }
        else if (parts[0] == "Window" && parts[1] == "GlassFrameThickness")
        {
            var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
            if (chrome != null)
            {
                double val = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                win.Resources["GlassFrameThicknessVal"] = val;
                chrome.GlassFrameThickness = new Thickness(val);
                if (val == 0)
                {
                    chrome.ResizeBorderThickness = win.AllowsTransparency ? new Thickness(0) : new Thickness(6);
                }
                else
                {
                    chrome.ResizeBorderThickness = new Thickness(0);
                }
                IntPtr hwndVal = new WindowInteropHelper(win).Handle;
                if (hwndVal != IntPtr.Zero)
                {
                    if (!win.AllowsTransparency)
                    {
                        int policy = (val == 0) ? 1 : 2; // 1 = DWMNCRP_DISABLED (No Shadow), 2 = DWMNCRP_ENABLED (Shadow)
                        DwmSetWindowAttribute(hwndVal, 2, ref policy, 4); // DWMWA_NCRENDERING_POLICY = 2

                        MARGINS margins = (val == 0) ? new MARGINS(0, 0, 0, 0) : new MARGINS(-1, -1, -1, -1);
                        DwmExtendFrameIntoClientArea(hwndVal, ref margins);

                        SetWindowPos(hwndVal, IntPtr.Zero, 0, 0, 0, 0, 0x0037); // SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER

                        if (win.Resources.Contains("DWM_Backdrop") && win.Resources.Contains("DWM_Dark"))
                        {
                            int backdrop = (int)win.Resources["DWM_Backdrop"];
                            int dark = (int)win.Resources["DWM_Dark"];
                            DwmSetWindowAttribute(hwndVal, 20, ref dark, 4);
                            DwmSetWindowAttribute(hwndVal, 38, ref backdrop, 4);
                            int borderColor = -2; // DWMWA_COLOR_NONE
                            DwmSetWindowAttribute(hwndVal, 34, ref borderColor, 4);
                        }
                    }
                    UpdateSnapState(win);
                }
            }
        }
        else if (parts[0] == "Window" && parts[1] == "ApplyVisibilityStyles")
        {
            try
            {
                string[] sub = parts[2].Split(',');
                bool showInAltTab = sub[0] == "1";
                bool showInTaskbar = sub[1] == "1";

                IntPtr hwndVal = new WindowInteropHelper(win).Handle;
                if (hwndVal != IntPtr.Zero)
                {
                    bool wasVisible = IsWindowVisible(hwndVal);
                    if (wasVisible)
                    {
                        ShowWindow(hwndVal, 0); // SW_HIDE = 0
                    }

                    IntPtr originalOwner = IntPtr.Zero;
                    if (win.Resources.Contains("OriginalNativeOwner"))
                    {
                        originalOwner = (IntPtr)win.Resources["OriginalNativeOwner"];
                    }

                    if (showInAltTab)
                    {
                        SetWindowLong(hwndVal, -8, IntPtr.Zero);
                    }
                    else
                    {
                        SetWindowLong(hwndVal, -8, originalOwner);
                    }

                    int exStyle = GetWindowLong(hwndVal, -20); // GWL_EXSTYLE = -20
                    if (showInAltTab && showInTaskbar)
                    {
                        exStyle &= ~0x80; // Remove WS_EX_TOOLWINDOW
                        exStyle |= 0x40000; // Add WS_EX_APPWINDOW
                    }
                    else if (showInAltTab && !showInTaskbar)
                    {
                        exStyle &= ~0x80; // Remove WS_EX_TOOLWINDOW
                        exStyle &= ~0x40000; // Remove WS_EX_APPWINDOW
                    }
                    else if (!showInAltTab && showInTaskbar)
                    {
                        exStyle &= ~0x80; // Remove WS_EX_TOOLWINDOW
                        exStyle &= ~0x40000; // Remove WS_EX_APPWINDOW
                    }
                    else
                    { // !showInAltTab && !showInTaskbar
                        exStyle &= ~0x40000; // Remove WS_EX_APPWINDOW
                        exStyle |= 0x80; // Add WS_EX_TOOLWINDOW
                    }

                    SetWindowLong(hwndVal, -20, new IntPtr(exStyle));

                    SetTaskbarPresence(hwndVal, showInTaskbar);

                    SetWindowPos(hwndVal, IntPtr.Zero, 0, 0, 0, 0, 0x0037); // SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER

                    if (wasVisible)
                    {
                        ShowWindow(hwndVal, 8); // SW_SHOWNA = 8
                    }

                    // Re-apply DWM attributes after recreate
                    if (!win.AllowsTransparency && win.Resources.Contains("DWM_Backdrop") && win.Resources.Contains("DWM_Dark"))
                    {
                        int backdrop = (int)win.Resources["DWM_Backdrop"];
                        int dark = (int)win.Resources["DWM_Dark"];
                        DwmSetWindowAttribute(hwndVal, 20, ref dark, 4);
                        DwmSetWindowAttribute(hwndVal, 38, ref backdrop, 4);
                        int borderColor = -2; // DWMWA_COLOR_NONE
                        DwmSetWindowAttribute(hwndVal, 34, ref borderColor, 4);
                    }

                    if (!win.AllowsTransparency && win.Resources.Contains("GlassFrameThicknessVal"))
                    {
                        double val = (double)win.Resources["GlassFrameThicknessVal"];
                        int policy = (val == 0) ? 1 : 2;
                        DwmSetWindowAttribute(hwndVal, 2, ref policy, 4);
                        MARGINS margins = (val == 0) ? new MARGINS(0, 0, 0, 0) : new MARGINS(-1, -1, -1, -1);
                        DwmExtendFrameIntoClientArea(hwndVal, ref margins);
                    }

                    UpdateSnapState(win);
                }
            }
            catch { }
        }
        else if (parts[0] == "Resource")
        {
            string[] rParts = parts[2].Split(new[] { ':' }, 2);
            if (rParts.Length == 2 && (rParts[0] == "Brush" || rParts[0] == "Thickness" || rParts[0] == "CornerRadius" || rParts[0] == "Double"))
            {
                string type = rParts[0];
                string val = rParts[1];
                if (type == "Brush") win.Resources[parts[1]] = new System.Windows.Media.BrushConverter().ConvertFromString(val);
                else if (type == "Thickness") win.Resources[parts[1]] = new System.Windows.ThicknessConverter().ConvertFromString(val);
                else if (type == "CornerRadius")
                {
                    if (parts[1] == "WindowRadius")
                    {
                        win.Resources["BaseWindowRadius"] = new System.Windows.CornerRadiusConverter().ConvertFromString(val);
                        if (Application.Current != null && !win.Title.StartsWith("Developer Tools - ")) Application.Current.Resources["BaseWindowRadius"] = win.Resources["BaseWindowRadius"];
                        UpdateSnapState(win);
                    }
                    else
                    {
                        win.Resources[parts[1]] = new System.Windows.CornerRadiusConverter().ConvertFromString(val);
                        if (parts[1] == "PanelRadius")
                        {
                            var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
                            if (chrome != null)
                            {
                                chrome.CornerRadius = (CornerRadius)win.Resources["PanelRadius"];
                            }
                            UpdateSnapState(win);
                        }
                    }
                }
                else if (type == "Double") win.Resources[parts[1]] = double.Parse(val, System.Globalization.CultureInfo.InvariantCulture);
            }
            else
            {
                try
                {
                    win.Resources[parts[1]] = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]);
                }
                catch
                {
                    try
                    {
                        win.Resources[parts[1]] = new System.Windows.CornerRadiusConverter().ConvertFromString(parts[2]);
                    }
                    catch
                    {
                        try
                        {
                            win.Resources[parts[1]] = new System.Windows.ThicknessConverter().ConvertFromString(parts[2]);
                        }
                        catch
                        {
                            try
                            {
                                win.Resources[parts[1]] = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                            }
                            catch { }
                        }
                    }
                }
            }
            if (Application.Current != null && !win.Title.StartsWith("Developer Tools - ")) Application.Current.Resources[parts[1]] = win.Resources[parts[1]];
            // Force-apply ScrollBarWidth to all ScrollBar elements in the visual tree
            if (parts[1] == "ScrollBarWidth" && win.Resources[parts[1]] is double)
            {
                double sz = (double)win.Resources[parts[1]];
                WalkVisualTree(win, (obj) =>
                {
                    if (obj is ScrollBar)
                    {
                        ScrollBar sb = (ScrollBar)obj;
                        if (sb.Orientation == System.Windows.Controls.Orientation.Vertical) sb.Width = sz;
                        else sb.Height = sz;
                    }
                });
            }
        }
        else
        {
            object ctrl = parts[0] == "Window" ? win : FindControlByPath(parts[0]);
            if (ctrl == null && parts[0] != "Window")
            {
                if (EnableLogging)
                {
                    try { System.IO.File.AppendAllText(System.Environment.ExpandEnvironmentVariables("%TEMP%\\AhkWpf\\AhkWpfDebug.log"), "Control not found: " + parts[0] + "\n"); } catch { }
                }
            }
            if (ctrl != null)
            {
                if (parts[1] == "AddItem")
                {
                    _controlCache.Clear();
                    if (ctrl is ListBox)
                    {
                        ListBox lb = (ListBox)ctrl;
                        int prevIdx = lb.SelectedIndex;
                        lb.Items.Add(parts[2]);
                        if (prevIdx != -1)
                        {
                            lb.SelectedIndex = prevIdx;
                        }
                        else
                        {
                            lb.SelectedIndex = lb.Items.Count - 1;
                            lb.ScrollIntoView(lb.SelectedItem);
                        }
                    }
                    else if (ctrl is TreeView)
                    {
                        TreeViewItem newItem = new TreeViewItem { Header = parts[2] };
                        int openParen = parts[2].LastIndexOf('(');
                        int closeParen = parts[2].LastIndexOf(')');
                        if (openParen >= 0 && closeParen > openParen)
                        {
                            string itemName = parts[2].Substring(openParen + 1, closeParen - openParen - 1);
                            newItem.Name = itemName;
                            try { win.UnregisterName(itemName); } catch { }
                            try { win.RegisterName(itemName, newItem); } catch { }
                        }
                        ((TreeView)ctrl).Items.Add(newItem);
                    }
                    else if (ctrl is TreeViewItem)
                    {
                        TreeViewItem newItem = new TreeViewItem { Header = parts[2] };
                        int openParen = parts[2].LastIndexOf('(');
                        int closeParen = parts[2].LastIndexOf(')');
                        if (openParen >= 0 && closeParen > openParen)
                        {
                            string itemName = parts[2].Substring(openParen + 1, closeParen - openParen - 1);
                            newItem.Name = itemName;
                            try { win.UnregisterName(itemName); } catch { }
                            try { win.RegisterName(itemName, newItem); } catch { }
                        }
                        ((TreeViewItem)ctrl).Items.Add(newItem);
                    }
                    else if (ctrl is ItemsControl)
                    {
                        ((ItemsControl)ctrl).Items.Add(parts[2]);
                    }
                }
                else if (parts[1] == "AddXamlItem")
                {
                    _controlCache.Clear();
                    try
                    {
                        object element = XamlReader.Parse(parts[2]);

                        var visited = new System.Collections.Generic.HashSet<object>();
                        Action<object> registerNames = null;
                        registerNames = new Action<object>((object obj) =>
                        {
                            if (obj == null || !visited.Add(obj)) return;
                            var fe = obj as FrameworkElement;
                            if (fe != null)
                            {
                                if (!string.IsNullOrEmpty(fe.Name))
                                {
                                    try {
                                        var ns = NameScope.GetNameScope(win);
                                        try {
                                            System.IO.File.AppendAllText(
                                                System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpfDebug.log"),
                                                string.Format("AddXamlItem RegisterName: fe.Name={0}, ns is null={1}\n", fe.Name, ns == null)
                                            );
                                        } catch { }
                                        if (ns != null) {
                                            try { ns.UnregisterName(fe.Name); } catch { }
                                            ns.RegisterName(fe.Name, fe);
                                        } else {
                                            try { win.UnregisterName(fe.Name); } catch { }
                                            win.RegisterName(fe.Name, fe);
                                        }
                                    } catch (Exception ex) {
                                        try {
                                            System.IO.File.AppendAllText(
                                                System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpfDebug.log"),
                                                "RegisterName Error for " + fe.Name + ": " + ex.ToString() + "\n"
                                            );
                                        } catch { }
                                    }
                                }
                                else
                                {
                                    try {
                                        System.IO.File.AppendAllText(
                                            System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpfDebug.log"),
                                            "RegisterName Warning: Element " + fe.GetType().Name + " has empty Name\n"
                                        );
                                    } catch { }
                                }
                            }
                            var dobj = obj as DependencyObject;
                            if (dobj != null)
                            {
                                foreach (object child in System.Windows.LogicalTreeHelper.GetChildren(dobj))
                                {
                                    registerNames(child);
                                }
                                var cc = dobj as System.Windows.Controls.ContentControl;
                                if (cc != null && cc.Content != null) registerNames(cc.Content);
                                var dec = dobj as System.Windows.Controls.Decorator;
                                if (dec != null && dec.Child != null) registerNames(dec.Child);
                                var panel = dobj as System.Windows.Controls.Panel;
                                if (panel != null)
                                {
                                    foreach (UIElement c in panel.Children) registerNames(c);
                                }
                                var ic = dobj as ItemsControl;
                                if (ic != null)
                                {
                                    foreach (object item in ic.Items) registerNames(item);
                                }
                            }
                        });
                        registerNames(element);

                        if (ctrl is ItemsControl)
                        {
                            ((ItemsControl)ctrl).Items.Add(element);
                        }
                        else if (ctrl is System.Windows.Controls.Panel)
                        {
                            ((System.Windows.Controls.Panel)ctrl).Children.Add((UIElement)element);
                        }
                        else if (ctrl is System.Windows.Controls.Border)
                        {
                            ((System.Windows.Controls.Border)ctrl).Child = (UIElement)element;
                        }
                        else if (ctrl is ContentControl)
                        {
                            ((ContentControl)ctrl).Content = element;
                        }
                    }
                    catch (Exception ex)
                    {
                        try
                        {
                            System.IO.File.AppendAllText(
                                System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf", "AhkWpfDebug.log"),
                                "XamlParse Error in AddXamlItem:\n" + ex.ToString() + "\n\n"
                            );
                        }
                        catch { }
                        Console.WriteLine("XamlParse Error: " + ex.Message);
                    }
                }
                else if (parts[1] == "SelectByTag" && ctrl is TreeView)
                {
                    string tagHash = parts[2];
                    Func<ItemsControl, TreeViewItem> findAndExpand = null;
                    findAndExpand = (parent) =>
                    {
                        foreach (object item in parent.Items)
                        {
                            TreeViewItem tvi = item as TreeViewItem;
                            if (tvi != null)
                            {
                                if (tvi.Tag != null && tvi.Tag.ToString() == tagHash)
                                {
                                    return tvi;
                                }
                                TreeViewItem found = findAndExpand(tvi);
                                if (found != null)
                                {
                                    tvi.IsExpanded = true;
                                    return found;
                                }
                            }
                        }
                        return null;
                    };

                    TreeViewItem result = findAndExpand((TreeView)ctrl);
                    if (result != null)
                    {
                        result.IsSelected = true;
                        result.BringIntoView();
                    }
                }
                else if (parts[1] == "Document" && ctrl is RichTextBox)
                {
                    try
                    {
                        FlowDocument doc = (FlowDocument)XamlReader.Parse(parts[2]);
                        ((RichTextBox)ctrl).Document = doc;
                    }
                    catch (Exception ex)
                    {
                        if (EnableLogging)
                        {
                            try { System.IO.File.AppendAllText("xaml_parse_error.log", "Parse Error: " + ex.Message + "\n" + (ex.InnerException != null ? ex.InnerException.Message : "") + "\nString: " + parts[2] + "\n\n"); } catch { }
                        }
                    }
                }
                else if (parts[1] == "Background")
                {
                    if (ctrl is System.Windows.Controls.Control)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Control)ctrl).SetResourceReference(System.Windows.Controls.Control.BackgroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Control)ctrl).Background = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is System.Windows.Controls.Border)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Border)ctrl).SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Border)ctrl).Background = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is System.Windows.Controls.Panel)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Panel)ctrl).SetResourceReference(System.Windows.Controls.Panel.BackgroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Panel)ctrl).Background = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                }
                else if (parts[1] == "Foreground")
                {
                    if (ctrl is System.Windows.Controls.Control)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Control)ctrl).SetResourceReference(System.Windows.Controls.Control.ForegroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Control)ctrl).Foreground = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is TextBlock)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((TextBlock)ctrl).SetResourceReference(TextBlock.ForegroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((TextBlock)ctrl).Foreground = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is TextElement)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((TextElement)ctrl).SetResourceReference(TextElement.ForegroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((TextElement)ctrl).Foreground = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                }
                else if (parts[1] == "BorderBrush")
                {
                    if (ctrl is System.Windows.Controls.Border)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Border)ctrl).SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Border)ctrl).BorderBrush = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is System.Windows.Controls.Control)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Control)ctrl).SetResourceReference(System.Windows.Controls.Control.BorderBrushProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Control)ctrl).BorderBrush = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                }
                else if (parts[1] == "Stroke" && ctrl is System.Windows.Shapes.Shape)
                {
                    if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Shapes.Shape)ctrl).SetResourceReference(System.Windows.Shapes.Shape.StrokeProperty, parts[2].Substring(17, parts[2].Length - 18));
                    else ((System.Windows.Shapes.Shape)ctrl).Stroke = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                }
                else if (parts[1] == "Fill" && ctrl is System.Windows.Shapes.Shape)
                {
                    if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Shapes.Shape)ctrl).SetResourceReference(System.Windows.Shapes.Shape.FillProperty, parts[2].Substring(17, parts[2].Length - 18));
                    else ((System.Windows.Shapes.Shape)ctrl).Fill = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                }
                else if (parts[1] == "StrokeThickness" && ctrl is System.Windows.Shapes.Shape)
                {
                    ((System.Windows.Shapes.Shape)ctrl).StrokeThickness = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                }
                else if (parts[1] == "RemoveItem" && ctrl is ItemsControl)
                {
                    _controlCache.Clear();
                    var itemsControl = (ItemsControl)ctrl;
                    object toRemove = null;
                    foreach (var item in itemsControl.Items)
                    {
                        bool match = item.ToString() == parts[2];
                        if (!match && item is System.Windows.Controls.ListBoxItem)
                        {
                            var lbi = (System.Windows.Controls.ListBoxItem)item;
                            match = (lbi.Content != null && lbi.Content.ToString() == parts[2]);
                        }
                        if (match)
                        {
                            toRemove = item;
                            break;
                        }
                    }
                    if (toRemove != null)
                    {
                        if (toRemove is DependencyObject)
                        {
                            try { UnregisterNamesRecursive((DependencyObject)toRemove); } catch { }
                        }
                        try { itemsControl.Items.Remove(toRemove); } catch { }
                    }
                }
                else if (parts[1] == "ClearItems")
                {
                    _controlCache.Clear();
                    if (ctrl is ItemsControl)
                    {
                        var ic = (ItemsControl)ctrl;
                        var itemsList = new System.Collections.Generic.List<object>();
                        try
                        {
                            foreach (var item in ic.Items) itemsList.Add(item);
                        }
                        catch { }
                        foreach (var item in itemsList)
                        {
                            if (item is DependencyObject)
                            {
                                try { UnregisterNamesRecursive((DependencyObject)item); } catch { }
                            }
                        }
                        try { ic.Items.Clear(); } catch { }
                    }
                    else if (ctrl is System.Windows.Controls.Panel)
                    {
                        var panel = (System.Windows.Controls.Panel)ctrl;
                        var childrenList = new System.Collections.Generic.List<UIElement>();
                        try
                        {
                            foreach (UIElement child in panel.Children) childrenList.Add(child);
                        }
                        catch { }
                        foreach (var child in childrenList)
                        {
                            if (child is DependencyObject)
                            {
                                try { UnregisterNamesRecursive((DependencyObject)child); } catch { }
                            }
                        }
                        try { panel.Children.Clear(); } catch { }
                    }
                    else if (ctrl is System.Windows.Controls.Border)
                    {
                        var border = (System.Windows.Controls.Border)ctrl;
                        if (border.Child != null)
                        {
                            try { UnregisterNamesRecursive(border.Child); } catch { }
                        }
                        try { border.Child = null; } catch { }
                    }
                    else if (ctrl is ContentControl)
                    {
                        var cc = (ContentControl)ctrl;
                        if (cc.Content is DependencyObject)
                        {
                            try { UnregisterNamesRecursive((DependencyObject)cc.Content); } catch { }
                        }
                        try { cc.Content = null; } catch { }
                    }
                }
                else if (parts[1] == "Play" && ctrl is MediaElement)
                {
                    ((MediaElement)ctrl).Play();
                }
                else if (parts[1] == "Pause" && ctrl is MediaElement)
                {
                    ((MediaElement)ctrl).Pause();
                }
                else if (parts[1] == "Stop" && ctrl is MediaElement)
                {
                    ((MediaElement)ctrl).Stop();
                }
                else if (parts[1] == "Seek" && ctrl is MediaElement)
                {
                    double secs;
                    if (double.TryParse(parts[2], out secs))
                    {
                        ((MediaElement)ctrl).Position = TimeSpan.FromSeconds(secs);
                    }
                }
                else if (parts[1] == "NavigateToString" && ctrl is System.Windows.Controls.WebBrowser)
                {
                    try
                    {
                        byte[] htmlBytes = Convert.FromBase64String(parts[2]);
                        string html = Encoding.UTF8.GetString(htmlBytes);
                        ((System.Windows.Controls.WebBrowser)ctrl).NavigateToString(html);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine("NavigateToString error: " + ex.Message);
                    }
                }
                else if (parts[1] == "BindEvent")
                {
                    BindEvent(parts[0], parts[2]);
                }
#if ENABLE_WEBVIEW
                else if (parts[1] == "Navigate" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try {
                        ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.Navigate(parts[2]);
                    } catch { }
                } else if (parts[1] == "ExecuteScript" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try {
                        ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.ExecuteScriptAsync(Encoding.UTF8.GetString(Convert.FromBase64String(parts[2])));
                    } catch { }
                } else if (parts[1] == "PostWebMessage" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try {
                        ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.PostWebMessageAsString(parts[2]);
                    } catch { }
                } else if (parts[1] == "GoBack" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).GoBack(); } catch { }
                } else if (parts[1] == "GoForward" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).GoForward(); } catch { }
                } else if (parts[1] == "Refresh" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).Reload(); } catch { }
                } else if (parts[1] == "OpenDevTools" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.OpenDevToolsWindow(); } catch { }
                }
#endif
#if ENABLE_AVALONEDIT
                else if (ctrl is ContentControl && parts[1].StartsWith("AE_")) {
                    // AvalonEdit commands — the ContentControl hosts the TextEditor
                    var host = ctrl as ContentControl;
                    var editor = host != null ? host.Content as TextEditor : null;
                    if (editor == null) {
                        // First-time init: create AvalonEdit inside the ContentControl
                        if (parts[1] == "AE_Init") {
                            editor = new TextEditor();
                            editor.FontFamily = new System.Windows.Media.FontFamily("Consolas");
                            editor.FontSize = 14;
                            editor.ShowLineNumbers = true;
                            editor.WordWrap = false;
                            editor.HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
                            editor.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
                            editor.Options.EnableHyperlinks = false;
                            editor.Options.EnableEmailHyperlinks = false;
                            editor.Options.ShowEndOfLine = false;
                            editor.Options.ShowSpaces = false;
                            editor.Options.ShowTabs = false;
                            editor.Options.HighlightCurrentLine = true;
                            editor.Options.AllowScrollBelowDocument = true;
                            editor.Options.ConvertTabsToSpaces = true;
                            editor.Options.IndentationSize = 4;
                            // Install search panel
                            SearchPanel.Install(editor);
                            // Wire events
                            string eName = ((FrameworkElement)host).Name;
                            editor.TextChanged += (s, e2) => {
                                SendToAhk("EVENT|" + winId + "|" + eName + "|TextChanged|" + LengthPrefix(editor.Document.LineCount.ToString()) + "\n");
                            };
                            editor.TextArea.Caret.PositionChanged += (s, e2) => {
                                int line = editor.TextArea.Caret.Line;
                                int col = editor.TextArea.Caret.Column;
                                int offset = editor.TextArea.Caret.Offset;
                                SendToAhk("EVENT|" + winId + "|" + eName + "|CaretChanged|" + LengthPrefix(line + "," + col + "," + offset) + "\n");
                            };
                            ((ContentControl)host).Content = editor;
                            // Apply initial theme from parts[2] if provided
                            if (parts.Length > 2 && !string.IsNullOrEmpty(parts[2])) {
                                ApplyAvalonEditTheme(editor, parts[2]);
                            }
                        }
                    }
                    if (editor != null) {
                        string aeCmd = parts[1].Substring(3); // strip "AE_"
                        string aeVal = parts.Length > 2 ? parts[2] : "";
                        switch (aeCmd) {
                            case "Init": break; // Already handled above
                            case "SetText":
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    editor.Document.Text = decoded;
                                } catch {
                                    editor.Document.Text = aeVal;
                                }
                                break;
                            case "GetText": {
                                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(editor.Document.Text));
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)host).Name + "|TextContent|" + LengthPrefix(b64) + "\n");
                                break;
                            }
                            case "AppendText":
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    editor.AppendText(decoded);
                                } catch {
                                    editor.AppendText(aeVal);
                                }
                                break;
                            case "SetLanguage":
                                try {
                                    var hlDef = HighlightingManager.Instance.GetDefinition(aeVal);
                                    if (hlDef == null) {
                                        // Try common aliases
                                        switch (aeVal.ToLower()) {
                                            case "ahk": case "autohotkey": hlDef = HighlightingManager.Instance.GetDefinition("Python"); break; // Closest built-in
                                            case "cs": case "csharp": hlDef = HighlightingManager.Instance.GetDefinition("C#"); break;
                                            case "js": case "javascript": hlDef = HighlightingManager.Instance.GetDefinition("JavaScript"); break;
                                            case "py": case "python": hlDef = HighlightingManager.Instance.GetDefinition("Python"); break;
                                            case "xml": case "xaml": hlDef = HighlightingManager.Instance.GetDefinition("XML"); break;
                                            case "html": hlDef = HighlightingManager.Instance.GetDefinition("HTML"); break;
                                            case "css": hlDef = HighlightingManager.Instance.GetDefinition("CSS"); break;
                                            case "json": hlDef = HighlightingManager.Instance.GetDefinition("JavaScript"); break;
                                            case "sql": hlDef = HighlightingManager.Instance.GetDefinition("TSQL"); break;
                                            case "md": case "markdown": hlDef = HighlightingManager.Instance.GetDefinition("MarkDown"); break;
                                            case "cpp": case "c++": case "c": hlDef = HighlightingManager.Instance.GetDefinition("C++"); break;
                                            case "java": hlDef = HighlightingManager.Instance.GetDefinition("Java"); break;
                                            case "ps": case "powershell": hlDef = HighlightingManager.Instance.GetDefinition("PowerShell"); break;
                                            case "bat": case "batch": case "cmd": hlDef = HighlightingManager.Instance.GetDefinition("BAT"); break;
                                            case "vb": case "vbnet": hlDef = HighlightingManager.Instance.GetDefinition("VB"); break;
                                            case "php": hlDef = HighlightingManager.Instance.GetDefinition("PHP"); break;
                                        }
                                    }
                                    editor.SyntaxHighlighting = hlDef;
                                } catch { }
                                break;
                            case "SetTheme":
                                ApplyAvalonEditTheme(editor, aeVal);
                                break;
                            case "ShowLineNumbers":
                                editor.ShowLineNumbers = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "WordWrap":
                                editor.WordWrap = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ReadOnly":
                                editor.IsReadOnly = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "FontSize":
                                double fs; if (double.TryParse(aeVal, out fs)) editor.FontSize = fs;
                                break;
                            case "FontFamily":
                                editor.FontFamily = new System.Windows.Media.FontFamily(aeVal);
                                break;
                            case "TabSize":
                                int ts; if (int.TryParse(aeVal, out ts)) editor.Options.IndentationSize = ts;
                                break;
                            case "GotoLine": {
                                int ln; if (int.TryParse(aeVal, out ln) && ln > 0 && ln <= editor.Document.LineCount) {
                                    editor.ScrollToLine(ln);
                                    editor.TextArea.Caret.Line = ln;
                                    editor.TextArea.Caret.Column = 1;
                                }
                                break;
                            }
                            case "GotoOffset": {
                                int off; if (int.TryParse(aeVal, out off)) {
                                    if (off >= 0 && off <= editor.Document.TextLength) {
                                        editor.CaretOffset = off;
                                        editor.ScrollTo(editor.TextArea.Caret.Line, editor.TextArea.Caret.Column);
                                    }
                                }
                                break;
                            }
                            case "Select": {
                                string[] sel = aeVal.Split(',');
                                if (sel.Length >= 2) {
                                    int start, len;
                                    if (int.TryParse(sel[0], out start) && int.TryParse(sel[1], out len)) {
                                        if (start >= 0 && start + len <= editor.Document.TextLength) {
                                            editor.Select(start, len);
                                            editor.ScrollTo(editor.TextArea.Caret.Line, editor.TextArea.Caret.Column);
                                        }
                                    }
                                }
                                break;
                            }
                            case "InsertText": {
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    editor.Document.Insert(editor.CaretOffset, decoded);
                                } catch {
                                    editor.Document.Insert(editor.CaretOffset, aeVal);
                                }
                                break;
                            }
                            case "Find": {
                                // Open built-in search panel with query
                                var sp = SearchPanel.Install(editor);
                                // The SearchPanel doesn't expose a programmatic "search for" method easily,
                                // so we use reflection or just open it
                                sp.Open();
                                if (!string.IsNullOrEmpty(aeVal)) {
                                    // Set search text via reflection
                                    try {
                                        var searchProp = sp.GetType().GetProperty("SearchPattern");
                                        if (searchProp != null) searchProp.SetValue(sp, aeVal);
                                    } catch { }
                                }
                                break;
                            }
                            case "ReplaceAll": {
                                string[] rp = aeVal.Split(new[] { "|||" }, StringSplitOptions.None);
                                if (rp.Length >= 2) {
                                    string findText = rp[0], replText = rp[1];
                                    editor.Document.Text = editor.Document.Text.Replace(findText, replText);
                                }
                                break;
                            }
                            case "HighlightLine": {
                                // Set current line highlight — AvalonEdit does this natively
                                // but we can also add a custom background marker
                                int hlLine;
                                if (int.TryParse(aeVal, out hlLine) && hlLine > 0 && hlLine <= editor.Document.LineCount) {
                                    editor.ScrollToLine(hlLine);
                                    var docLine = editor.Document.GetLineByNumber(hlLine);
                                    editor.Select(docLine.Offset, docLine.Length);
                                }
                                break;
                            }
                            case "FoldAll":
                                if (editor.Tag is FoldingManager) {
                                    var fm = (FoldingManager)editor.Tag;
                                    foreach (var fold in fm.AllFoldings) fold.IsFolded = true;
                                }
                                break;
                            case "UnfoldAll":
                                if (editor.Tag is FoldingManager) {
                                    var fm = (FoldingManager)editor.Tag;
                                    foreach (var fold in fm.AllFoldings) fold.IsFolded = false;
                                }
                                break;
                            case "SetFolding": {
                                // Initialize or update folding based on brace-matching
                                FoldingManager foldMgr = editor.Tag as FoldingManager;
                                if (foldMgr == null) {
                                    foldMgr = FoldingManager.Install(editor.TextArea);
                                    editor.Tag = foldMgr;
                                    
                                    // Replace standard boxy FoldingMargin with SexyFoldingMargin
                                    for (int i = 0; i < editor.TextArea.LeftMargins.Count; i++) {
                                        var margin = editor.TextArea.LeftMargins[i];
                                        if (margin.GetType().Name == "FoldingMargin") {
                                            editor.TextArea.LeftMargins[i] = new SexyFoldingMargin() { FoldingManager = foldMgr };
                                            break;
                                        }
                                    }
                                }
                                var strategy = new BraceFoldingStrategy();
                                strategy.UpdateFoldings(foldMgr, editor.Document);
                                
                                // Re-apply theme styling to the folding margin if current theme is stored
                                if (editor.Resources.Contains("CurrentTheme")) {
                                    ApplyAvalonEditTheme(editor, (string)editor.Resources["CurrentTheme"]);
                                }
                                break;
                            }
                            case "ShowCompletion": {
                                // Show a WPF-styled autocomplete popup with the provided items
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    string[] items = decoded.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                                    var completionWindow = new CompletionWindow(editor.TextArea);
                                    
                                    // Custom visual styling matching the host/editor theme
                                    try {
                                        completionWindow.Background = editor.Background;
                                        completionWindow.BorderBrush = editor.LineNumbersForeground ?? System.Windows.Media.Brushes.Gray;
                                        completionWindow.BorderThickness = new System.Windows.Thickness(1);
                                        completionWindow.Foreground = editor.Foreground;
                                        completionWindow.FontFamily = editor.FontFamily;
                                        completionWindow.FontSize = editor.FontSize;
                                        completionWindow.MinWidth = 240;
                                        completionWindow.WindowStyle = System.Windows.WindowStyle.None;
                                        completionWindow.ResizeMode = System.Windows.ResizeMode.NoResize;
                                        
                                        var listBox = completionWindow.CompletionList.ListBox;
                                        if (listBox != null) {
                                            listBox.Background = System.Windows.Media.Brushes.Transparent;
                                            listBox.BorderThickness = new System.Windows.Thickness(0);
                                            listBox.Foreground = editor.Foreground;
                                            listBox.FontFamily = editor.FontFamily;
                                            listBox.FontSize = editor.FontSize;
                                            listBox.Padding = new System.Windows.Thickness(4);
                                            
                                            // Styled ListBoxItem container for hover/selection visual parity
                                            var itemStyle = new System.Windows.Style(typeof(System.Windows.Controls.ListBoxItem));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.BackgroundProperty, System.Windows.Media.Brushes.Transparent));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.ForegroundProperty, editor.Foreground));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.PaddingProperty, new System.Windows.Thickness(10, 5, 10, 5)));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.MarginProperty, new System.Windows.Thickness(0, 1, 0, 1)));
                                            
                                            // Selection Highlight
                                            var triggerSelected = new System.Windows.Trigger { Property = System.Windows.Controls.ListBoxItem.IsSelectedProperty, Value = true };
                                            triggerSelected.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.BackgroundProperty, editor.TextArea.SelectionBrush ?? System.Windows.Media.Brushes.DodgerBlue));
                                            triggerSelected.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.ForegroundProperty, editor.Foreground));
                                            
                                            // Hover Highlight
                                            var triggerHover = new System.Windows.Trigger { Property = System.Windows.Controls.ListBoxItem.IsMouseOverProperty, Value = true };
                                            System.Windows.Media.Brush hoverBrush = null;
                                            var selBrush = editor.TextArea.SelectionBrush as System.Windows.Media.SolidColorBrush;
                                            if (selBrush != null) {
                                                hoverBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(40, selBrush.Color.R, selBrush.Color.G, selBrush.Color.B));
                                            } else {
                                                hoverBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(20, 128, 128, 128));
                                            }
                                            triggerHover.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.BackgroundProperty, hoverBrush));
                                            
                                            itemStyle.Triggers.Add(triggerSelected);
                                            itemStyle.Triggers.Add(triggerHover);
                                            listBox.ItemContainerStyle = itemStyle;
                                        }
                                    } catch { }
                                    
                                    foreach (string item in items) {
                                        string[] itemParts = item.Split(new[] { '|' }, 2);
                                        string completionText = itemParts[0].Trim();
                                        string desc = itemParts.Length > 1 ? itemParts[1].Trim() : "";
                                        completionWindow.CompletionList.CompletionData.Add(
                                            new AhkCompletionData(completionText, desc));
                                    }
                                    completionWindow.Show();
                                    completionWindow.Closed += (s2, e2) => {
                                        // Notify AHK which item was selected
                                        SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)host).Name + "|CompletionClosed|\n");
                                    };
                                } catch { }
                                break;
                            }
                            case "AddMarker": {
                                // Format: line,type (error|warning|info|breakpoint)
                                // TODO: Add colored marker support with custom margin rendering
                                break;
                            }
                            case "ClearMarkers":
                                break;
                            case "HighlightCurrentLine":
                                editor.Options.HighlightCurrentLine = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ShowSpaces":
                                editor.Options.ShowSpaces = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ShowTabs":
                                editor.Options.ShowTabs = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ShowEndOfLine":
                                editor.Options.ShowEndOfLine = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                        }
                    }
                }
#endif
#if ENABLE_DOCUMENT
                else if (parts[1].StartsWith("Doc_") && ctrl is RichTextBox) {
                    var rtb = (RichTextBox)ctrl;
                    if (rtb.Tag == null || rtb.Tag.ToString() != "wired") {
                        rtb.SelectionChanged += (s, e) => {
                            var r = rtb.Selection;
                            var fw = r.GetPropertyValue(TextElement.FontWeightProperty);
                            var fs = r.GetPropertyValue(TextElement.FontStyleProperty);
                            var td = r.GetPropertyValue(Inline.TextDecorationsProperty);
                            var sz = r.GetPropertyValue(TextElement.FontSizeProperty);
                            var ff = r.GetPropertyValue(TextElement.FontFamilyProperty);
                            
                            string b = (fw != DependencyProperty.UnsetValue && (FontWeight)fw >= FontWeights.SemiBold) ? "1" : "0";
                            string i = (fs != DependencyProperty.UnsetValue && (FontStyle)fs == FontStyles.Italic) ? "1" : "0";
                            string u = (td != DependencyProperty.UnsetValue && td == TextDecorations.Underline) ? "1" : "0";
                            string st = (td != DependencyProperty.UnsetValue && td == TextDecorations.Strikethrough) ? "1" : "0";
                            double sizeVal = (sz != DependencyProperty.UnsetValue) ? (double)sz : 14.0;
                            string size = sizeVal.ToString();
                            string font = "Segoe UI";
                            bool fontIsInstalled = true;
                            if (ff != DependencyProperty.UnsetValue) {
                                string rawFont = ff.ToString();
                                // Determine if the selected text contains CJK characters
                                bool selectionHasCJK = false;
                                try {
                                    string selText = r.Text;
                                    if (!string.IsNullOrEmpty(selText)) {
                                        foreach (char ch in selText) {
                                            if (ch > 127) { selectionHasCJK = true; break; }
                                        }
                                    }
                                    if (!selectionHasCJK) {
                                        // No text selected or no CJK in selection — check the Run at caret
                                        var caretPos = r.Start;
                                        if (caretPos != null) {
                                            // Walk the parent chain to find the enclosing Run
                                            DependencyObject parent = caretPos.Parent;
                                            while (parent != null && !(parent is System.Windows.Documents.Run)) {
                                                parent = LogicalTreeHelper.GetParent(parent);
                                            }
                                            if (parent is System.Windows.Documents.Run) {
                                                string runText = ((System.Windows.Documents.Run)parent).Text;
                                                if (!string.IsNullOrEmpty(runText)) {
                                                    foreach (char ch in runText) {
                                                        if (ch > 127) { selectionHasCJK = true; break; }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } catch { }

                                // Parse the comma-separated font chain
                                var fontParts = rawFont.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
                                string primaryFont = "";
                                if (selectionHasCJK && fontParts.Length > 0) {
                                    // For CJK text, find the first CJK-capable font in the chain
                                    string cjkFont = null;
                                    foreach (var fp in fontParts) {
                                        string candidate = fp.Trim();
                                        int hashIdx = candidate.IndexOf('#');
                                        if (hashIdx >= 0) candidate = candidate.Substring(hashIdx + 1);
                                        // Check if this looks like a CJK font
                                        bool isCJK = false;
                                        foreach (char ch in candidate) {
                                            if (ch > 127) { isCJK = true; break; }
                                        }
                                        if (!isCJK) {
                                            string lower = candidate.ToLower();
                                            if (lower.Contains("sim") || lower.Contains("song") || lower.Contains("hei") || 
                                                lower.Contains("kai") || lower.Contains("ming") || lower.Contains("yahei") ||
                                                lower.Contains("gothic") || lower.Contains("malgun") || lower.Contains("meiryo") ||
                                                lower.Contains("dotum") || lower.Contains("batang") || lower.Contains("gulim") ||
                                                lower.Contains("fang")) {
                                                isCJK = true;
                                            }
                                        }
                                        if (isCJK) { cjkFont = candidate; break; }
                                    }
                                    primaryFont = cjkFont ?? fontParts[0].Trim();
                                } else if (fontParts.Length > 0) {
                                    primaryFont = fontParts[0].Trim();
                                }
                                // If per-user font path, extract the actual font name after '#'
                                int hashIdx2 = primaryFont.IndexOf('#');
                                if (hashIdx2 >= 0) {
                                    primaryFont = primaryFont.Substring(hashIdx2 + 1);
                                }
                                // Check if primary font is actually installed via WPF or alias
                                fontIsInstalled = IsFontInstalledWithAlias(primaryFont, GetInstalledFonts());
                                // Prefix with ! if not installed so AHK can show the fallback indicator
                                font = fontIsInstalled ? primaryFont : ("!" + primaryFont);
                            }
                            
                            string style = "Body";
                            if (sz != DependencyProperty.UnsetValue) {
                                double dSz = (double)sz;
                                FontWeight w = (fw != DependencyProperty.UnsetValue) ? (FontWeight)fw : FontWeights.Normal;
                                if (dSz >= 24 && w >= FontWeights.Bold) style = "H1";
                                else if (dSz >= 20 && w >= FontWeights.SemiBold) style = "H2";
                                else if (dSz >= 16 && w >= FontWeights.SemiBold) style = "H3";
                                else if (dSz >= 14 && w >= FontWeights.SemiBold) style = "H4";
                                else if (dSz >= 12 && w >= FontWeights.SemiBold) style = "H5";
                                else if (dSz >= 11 && w >= FontWeights.SemiBold) style = "H6";
                            }
                            
                            string fmt = string.Format("B:{0},I:{1},U:{2},S:{3},Size:{4},Style:{5},Font:{6}", b, i, u, st, size, style, font);
                            SendToAhk(string.Format("EVENT|{0}|{1}|SelectionFormat|{2}\n", winId, ((FrameworkElement)ctrl).Name, LengthPrefix(fmt)));
                        };

                        // Debouncer for page break spacer updates
                        var spacerTimer = new System.Windows.Threading.DispatcherTimer();
                        spacerTimer.Interval = TimeSpan.FromMilliseconds(1500);
                        spacerTimer.Tick += (s2, e2) => {
                            spacerTimer.Stop();
                            string currentMode = "paper";
                            if (_docViewModes.ContainsKey(rtb.Name)) {
                                currentMode = _docViewModes[rtb.Name];
                            }
                            if (currentMode != "paper") return;

                            var pageB = win.FindName(rtb.Name + "_PageBorder") as System.Windows.Controls.Border;
                            if (pageB != null) {
                                var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                string thm = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                _InsertPageBreakSpacers(rtb, thm);
                            }
                        };

                        rtb.TextChanged += (s, e) => {
                            if (!_isUpdatingSpacers) {
                                spacerTimer.Stop();
                                spacerTimer.Start();
                            }
                        };

                        // Setup click listener on outer ScrollViewer to focus RTB
                        Action wireScrollViewer = () => {
                            FrameworkElement walkUp = rtb.Parent as FrameworkElement;
                            ScrollViewer editorSv = null;
                            while (walkUp != null) {
                                if (walkUp is ScrollViewer) { editorSv = (ScrollViewer)walkUp; break; }
                                walkUp = System.Windows.Media.VisualTreeHelper.GetParent(walkUp) as FrameworkElement;
                            }
                            if (editorSv != null && editorSv.Tag == null) {
                                editorSv.MouseLeftButtonDown += (s2, e2) => {
                                    if (e2.OriginalSource == editorSv || e2.OriginalSource is Grid || e2.OriginalSource is System.Windows.Controls.Border) {
                                        rtb.Focus();
                                        System.Windows.Input.Keyboard.Focus(rtb);
                                    }
                                };
                                editorSv.Tag = "wired";
                            }
                        };

                        if (rtb.IsLoaded) {
                            wireScrollViewer();
                        } else {
                            rtb.Loaded += (s, e) => wireScrollViewer();
                        }

                        rtb.Tag = "wired";
                    }
                    string docCmd = parts[1].Substring(4);
                    string docVal = parts.Length > 2 ? parts[2] : "";
                    switch (docCmd) {
                        case "Import": {
                            try {
                                string filePath = docVal;
                                if (System.IO.File.Exists(filePath)) {
                                    string ext = System.IO.Path.GetExtension(filePath).ToLower();
                                    FlowDocument doc = new FlowDocument();
                                    if (ext == ".docx") {
                                        doc = DocxToFlowDocument(filePath);
                                    } else if (ext == ".doc") {
                                        doc = DocToFlowDocument(filePath);
                                    } else if (ext == ".rtf") {
                                        var range = new TextRange(doc.ContentStart, doc.ContentEnd);
                                        using (var fs = new System.IO.FileStream(filePath, System.IO.FileMode.Open)) {
                                            range.Load(fs, DataFormats.Rtf);
                                        }
                                    } else if (ext == ".txt") {
                                        doc.Blocks.Add(new System.Windows.Documents.Paragraph(
                                            new System.Windows.Documents.Run(System.IO.File.ReadAllText(filePath))));
                                    }
                                    if (doc.Tag == null) {
                                        doc.Tag = new DocLayoutSettings {
                                            PageWidth = 816,
                                            PageHeight = 1056,
                                            PagePadding = new Thickness(96, 72, 96, 72)
                                        };
                                    }
                                    rtb.Document = doc;
                                    
                                    string configLang = "en-US";
                                    if (_spellCheckLangs.ContainsKey(rtb.Name)) {
                                        configLang = _spellCheckLangs[rtb.Name];
                                    }
                                    
                                    string langToApply = configLang;
                                    if (configLang == "auto") {
                                        langToApply = DetectLanguage(rtb);
                                    }
                                    
                                    try {
                                        var xmlLang = System.Windows.Markup.XmlLanguage.GetLanguage(langToApply);
                                        rtb.Language = xmlLang;
                                        rtb.Document.Language = xmlLang;
                                        bool wasEnabled = rtb.SpellCheck.IsEnabled;
                                        rtb.SpellCheck.IsEnabled = false;
                                        rtb.SpellCheck.IsEnabled = wasEnabled;
                                    } catch { }

                                    string viewMode = "paper";
                                    if (_docViewModes.ContainsKey(rtb.Name)) {
                                        viewMode = _docViewModes[rtb.Name];
                                    } else {
                                        _docViewModes[rtb.Name] = viewMode;
                                    }
                                    var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string currentTheme = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                    ApplyViewMode(rtb, viewMode, currentTheme, win);
                                    SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentLoaded|" + LengthPrefix(filePath) + "\n");
                                    SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "Export": {
                            try {
                                // Strip page break spacers before saving
                                bool hadSpacers = _pageBreakSpacers.Count > 0;
                                _RemovePageBreakSpacers(rtb);
                                
                                // Get the active document (might be in FlowDocumentReader if in Page/TwoUp view)
                                string rtbN = ((FrameworkElement)ctrl).Name;
                                var pageReader = win.FindName(rtbN + "_PageReader") as FlowDocumentReader;
                                FlowDocument exportDoc = rtb.Document;
                                if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                                    exportDoc = pageReader.Document;
                                }
                                
                                string filePath = docVal;
                                string ext = System.IO.Path.GetExtension(filePath).ToLower();
                                if (ext == ".docx") {
                                    FlowDocumentToDocx(exportDoc, filePath);
                                } else if (ext == ".rtf") {
                                    var range = new TextRange(exportDoc.ContentStart, exportDoc.ContentEnd);
                                    using (var fs = new System.IO.FileStream(filePath, System.IO.FileMode.Create)) {
                                        range.Save(fs, DataFormats.Rtf);
                                    }
                                } else {
                                    var range = new TextRange(exportDoc.ContentStart, exportDoc.ContentEnd);
                                    System.IO.File.WriteAllText(filePath, range.Text);
                                }
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentSaved|" + LengthPrefix(filePath) + "\n");
                                
                                // Re-insert spacers if we were in page view
                                if (hadSpacers) {
                                    var containerEl2 = win.FindName(((FrameworkElement)ctrl).Name + "_Container") as FrameworkElement;
                                    string thm = (containerEl2 != null && containerEl2.Tag is string) ? (string)containerEl2.Tag : "Normal";
                                    _InsertPageBreakSpacers(rtb, thm);
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "Format": {
                            ApplyDocFormat(rtb, docVal);
                            break;
                        }
                        case "FormatStyle": {
                            var r = rtb.Selection;
                            if (docVal == "H1") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 24.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Bold);
                            } else if (docVal == "H2") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 20.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H3") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 16.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H4") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 14.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H5") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 12.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H6") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 11.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 14.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Normal);
                            }
                            break;
                        }
                        case "InsertTable": {
                            string[] dims = docVal.Split(',');
                            int rows = 3, cols = 3;
                            if (dims.Length >= 2) { int.TryParse(dims[0], out rows); int.TryParse(dims[1], out cols); }
                            var table = new System.Windows.Documents.Table();
                            table.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                            table.BorderThickness = new Thickness(1);
                            table.CellSpacing = 0;
                            table.Margin = new Thickness(0, 10, 0, 10);
                            for (int c = 0; c < cols; c++) {
                                table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                            }
                            var rg = new System.Windows.Documents.TableRowGroup();
                            for (int r = 0; r < rows; r++) {
                                var row = new System.Windows.Documents.TableRow();
                                for (int c = 0; c < cols; c++) {
                                    var cellPara = new System.Windows.Documents.Paragraph(new System.Windows.Documents.Run(r == 0 ? "Header" : ""));
                                    cellPara.Margin = new Thickness(0);
                                    if (r == 0) cellPara.TextAlignment = System.Windows.TextAlignment.Center;
                                    var cell = new System.Windows.Documents.TableCell(cellPara);
                                    cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                    cell.BorderThickness = new Thickness(0.5);
                                    cell.Padding = new Thickness(10, 8, 10, 8);
                                    if (r == 0) {
                                        cell.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(68, 114, 196));
                                        cell.Foreground = System.Windows.Media.Brushes.White;
                                        cellPara.FontWeight = FontWeights.Bold;
                                    }
                                    row.Cells.Add(cell);
                                }
                                rg.Rows.Add(row);
                            }
                            table.RowGroups.Add(rg);
                            
                            var currentPara = rtb.CaretPosition.Paragraph;
                            if (currentPara != null) {
                                rtb.Document.Blocks.InsertAfter(currentPara, table);
                            } else {
                                rtb.Document.Blocks.Add(table);
                            }
                            break;
                        }
                        case "GetOutline": {
                            string rtbN = ((FrameworkElement)ctrl).Name;
                            var pageReader = win.FindName(rtbN + "_PageReader") as FlowDocumentReader;
                            FlowDocument activeDoc = rtb.Document;
                            if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                                activeDoc = pageReader.Document;
                            }
                            //System.IO.File.WriteAllText(@"c:\projects\ahk\ahk-xaml\examples\clones\outline_debug.txt", "--- GET OUTLINE START ---\n");
                            System.Text.StringBuilder sb = new System.Text.StringBuilder();
                            int pIdx = 0;
                            System.Windows.Documents.TextPointer ptr = activeDoc.ContentStart;
                            while (ptr != null && ptr.CompareTo(rtb.Document.ContentEnd) < 0) {
                                if (ptr.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.ElementStart) {
                                    System.Windows.Documents.TextElement element = ptr.GetAdjacentElement(LogicalDirection.Forward) as System.Windows.Documents.TextElement;
                                    System.Windows.Documents.Paragraph p = element as System.Windows.Documents.Paragraph;
                                    if (p != null) {
                                        var range = new TextRange(p.ContentStart, p.ContentEnd);
                                        string headingText = range.Text.Trim();
                                        int nlIdx = headingText.IndexOf('\n');
                                        if (nlIdx > 0) headingText = headingText.Substring(0, nlIdx).Trim();
                                        
                                        if (!string.IsNullOrEmpty(headingText) && headingText.Length < 100) {
                                            bool isHeading = false;
                                            string level = "H2";
                                            
                                            double effSize = p.FontSize;
                                            FontWeight effWeight = p.FontWeight;
                                            
                                            double maxEffSize = p.FontSize;
                                            FontWeight maxEffWeight = p.FontWeight;

                                            System.Windows.Documents.TextPointer pointer = p.ContentStart;
                                            while (pointer != null && pointer.CompareTo(p.ContentEnd) < 0) {
                                                if (pointer.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text) {
                                                    string runText = pointer.GetTextInRun(LogicalDirection.Forward);
                                                    if (runText.Trim().Length > 0) {
                                                        System.Windows.Documents.TextElement textElement = pointer.Parent as System.Windows.Documents.TextElement;
                                                        if (textElement != null) {
                                                            if (textElement.FontSize > maxEffSize) {
                                                                maxEffSize = textElement.FontSize;
                                                                maxEffWeight = textElement.FontWeight;
                                                            } else if (textElement.FontSize == maxEffSize && textElement.FontWeight > maxEffWeight) {
                                                                maxEffWeight = textElement.FontWeight;
                                                            }
                                                        }
                                                    }
                                                }
                                                pointer = pointer.GetNextContextPosition(LogicalDirection.Forward);
                                            }
                                            
                                            effSize = maxEffSize;
                                            effWeight = maxEffWeight;

                                            bool isHeavy = (effWeight == FontWeights.Bold || effWeight == FontWeights.SemiBold || effWeight == FontWeights.Black || effWeight == FontWeights.ExtraBold);
                                            if (effSize >= 25.5) {
                                                isHeading = true;
                                                level = "H1";
                                            } else if (effSize >= 23.5) {
                                                isHeading = true;
                                                level = "H2";
                                            } else if (effSize >= 19.5) {
                                                isHeading = true;
                                                level = "H3";
                                            } else if (effSize >= 15.5) {
                                                isHeading = true;
                                                level = "H4";
                                            } else if (effSize >= 13.5 && isHeavy) {
                                                isHeading = true;
                                                level = "H5";
                                            } else if (effSize >= 11.5 && isHeavy) {
                                                isHeading = true;
                                                level = "H6";
                                            } else if (effSize >= 10.5 && isHeavy) {
                                                isHeading = true;
                                                level = "H6";
                                            } else if (isHeavy) {
                                                isHeading = true;
                                                level = "H3";
                                            }
                                            
                                            //System.IO.File.AppendAllText(@"c:\projects\ahk\ahk-xaml\examples\clones\outline_debug.txt", string.Format("[{0}] Text='{1}' Size={2} Weight={3} isHeading={4}\n", pIdx, headingText, effSize, effWeight, isHeading));
                                            
                                            if (isHeading) {
                                                sb.Append(pIdx + "," + level + "," + headingText + "\n");
                                            }
                                        }
                                        pIdx++;
                                    }
                                }
                                ptr = ptr.GetNextContextPosition(LogicalDirection.Forward);
                            }
                            string base64Outline = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(sb.ToString()));
                            SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|Outline|" + base64Outline + "\n");
                            break;
                        }
                        case "GoToBlock": {
                            try {
                                string type = "paragraph";
                                int targetIdx = 0;
                                if (docVal.Contains(":")) {
                                    string[] pts = docVal.Split(':');
                                    type = pts[0].ToLower();
                                    int.TryParse(pts[1], out targetIdx);
                                } else {
                                    int.TryParse(docVal, out targetIdx);
                                }
                                
                                int currentIdx = 0;
                                System.Windows.Documents.TextElement foundElement = null;

                                if (type == "paragraph") {
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (foundElement != null) return;
                                        if (block is System.Windows.Documents.Paragraph) {
                                            if (currentIdx == targetIdx) {
                                                foundElement = (System.Windows.Documents.Paragraph)block;
                                            }
                                            currentIdx++;
                                        }
                                    });
                                } else if (type == "table") {
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (foundElement != null) return;
                                        if (block is System.Windows.Documents.Table) {
                                            if (currentIdx == targetIdx) {
                                                foundElement = (System.Windows.Documents.Table)block;
                                            }
                                            currentIdx++;
                                        }
                                    });
                                } else if (type == "hyperlink") {
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (foundElement != null) return;
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (foundElement != null) return;
                                                if (inline is System.Windows.Documents.Hyperlink) {
                                                    if (currentIdx == targetIdx) {
                                                        foundElement = (System.Windows.Documents.Hyperlink)inline;
                                                    }
                                                    currentIdx++;
                                                }
                                            });
                                        }
                                    });
                                }

                                if (foundElement != null) {
                                    rtb.CaretPosition = foundElement.ContentStart;
                                    rtb.Selection.Select(foundElement.ContentStart, foundElement.ContentEnd);
                                    rtb.Focus();
                                    try {
                                        var rect = rtb.CaretPosition.GetCharacterRect(System.Windows.Documents.LogicalDirection.Forward);
                                        if (rect.Top != 0 || rect.Bottom != 0) {
                                            double targetOffset = rtb.VerticalOffset + rect.Top - 30;
                                            if (targetOffset < 0) targetOffset = 0;
                                            rtb.ScrollToVerticalOffset(targetOffset);
                                        } else {
                                            foundElement.BringIntoView();
                                        }
                                    } catch {
                                        try { foundElement.BringIntoView(); } catch {}
                                    }
                                }
                            } catch {}
                            break;
                        }
                        case "InsertImage": {
                            try {
                                if (System.IO.File.Exists(docVal)) {
                                    var bi = new System.Windows.Media.Imaging.BitmapImage(new Uri(docVal));
                                    var img = new System.Windows.Controls.Image { Source = bi, MaxWidth = 600, Stretch = System.Windows.Media.Stretch.Uniform };
                                    img.Cursor = System.Windows.Input.Cursors.SizeNWSE;
                                    
                                    // Add right-click context menu
                                    var ctxMenu = new ContextMenu();
                                    var miSmall = new MenuItem { Header = "Resize: Small (200px)" };
                                    var miMedium = new MenuItem { Header = "Resize: Medium (400px)" };
                                    var miLarge = new MenuItem { Header = "Resize: Large (600px)" };
                                    var miOriginal = new MenuItem { Header = "Resize: Original" };
                                    var miDelete = new MenuItem { Header = "Delete Image" };
                                    var miCopy = new MenuItem { Header = "Copy Image" };
                                    
                                    miSmall.Click += (s, e) => { img.MaxWidth = 200; img.Width = 200; };
                                    miMedium.Click += (s, e) => { img.MaxWidth = 400; img.Width = 400; };
                                    miLarge.Click += (s, e) => { img.MaxWidth = 600; img.Width = 600; };
                                    miOriginal.Click += (s, e) => { img.ClearValue(FrameworkElement.MaxWidthProperty); img.ClearValue(FrameworkElement.WidthProperty); };
                                    miDelete.Click += (s, e) => {
                                        try {
                                            var parent = LogicalTreeHelper.GetParent(img) as InlineUIContainer;
                                            if (parent != null) {
                                                var para = parent.Parent as System.Windows.Documents.Paragraph;
                                                if (para != null) para.Inlines.Remove(parent);
                                            }
                                        } catch { }
                                    };
                                    miCopy.Click += (s, e) => {
                                        try {
                                            Clipboard.SetImage(bi);
                                        } catch { }
                                    };
                                    
                                    ctxMenu.Items.Add(miSmall);
                                    ctxMenu.Items.Add(miMedium);
                                    ctxMenu.Items.Add(miLarge);
                                    ctxMenu.Items.Add(miOriginal);
                                    ctxMenu.Items.Add(new Separator());
                                    ctxMenu.Items.Add(miCopy);
                                    ctxMenu.Items.Add(miDelete);
                                    img.ContextMenu = ctxMenu;
                                    
                                    // Mouse-drag resizing: drag the image to resize proportionally
                                    bool isResizing = false;
                                    double startX = 0, startW = 0;
                                    img.MouseLeftButtonDown += (s, e) => {
                                        if (System.Windows.Input.Keyboard.Modifiers == System.Windows.Input.ModifierKeys.Shift) {
                                            isResizing = true;
                                            startX = e.GetPosition(img).X;
                                            startW = img.ActualWidth > 0 ? img.ActualWidth : 300;
                                            img.CaptureMouse();
                                            e.Handled = true;
                                        }
                                    };
                                    img.MouseMove += (s, e) => {
                                        if (isResizing) {
                                            double dx = e.GetPosition(img).X - startX;
                                            double newW = Math.Max(50, startW + dx);
                                            img.Width = newW;
                                            img.MaxWidth = newW;
                                            e.Handled = true;
                                        }
                                    };
                                    img.MouseLeftButtonUp += (s, e) => {
                                        if (isResizing) {
                                            isResizing = false;
                                            img.ReleaseMouseCapture();
                                            e.Handled = true;
                                        }
                                    };
                                    
                                    var container = new InlineUIContainer(img, rtb.CaretPosition);
                                }
                            } catch { }
                            break;
                        }
                        case "InsertHR": {
                            var line = new System.Windows.Documents.Paragraph();
                            line.BorderBrush = System.Windows.Media.Brushes.Gray;
                            line.BorderThickness = new Thickness(0, 0, 0, 1);
                            line.Margin = new Thickness(0, 10, 0, 10);
                            rtb.Document.Blocks.Add(line);
                            break;
                        }
                        case "SetLineSpacing": {
                            double spacingMultiplier;
                            if (double.TryParse(docVal, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out spacingMultiplier)) {
                                // Resolve grid line height
                                var lsSettings = rtb.Document.Tag as DocLayoutSettings;
                                double gridLH = 0;
                                if (lsSettings != null && lsSettings.LinePitch > 0) {
                                    gridLH = (lsSettings.LinePitch / 20.0) * (96.0 / 72.0);
                                }
                                // Apply to all paragraphs recursively
                                _ApplyLineSpacingToBlocks(rtb.Document.Blocks, spacingMultiplier, gridLH);
                                // Store multiplier for future reference
                                if (lsSettings != null) {
                                    lsSettings.LineSpacingOverride = spacingMultiplier;
                                }
                                // Re-insert page break spacers if in paper mode
                                if (_docViewModes.ContainsKey(rtb.Name) && _docViewModes[rtb.Name] == "paper") {
                                    var containerEl2 = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string thm2 = (containerEl2 != null && containerEl2.Tag is string) ? (string)containerEl2.Tag : "Normal";
                                    rtb.Dispatcher.BeginInvoke(new Action(() => {
                                        _InsertPageBreakSpacers(rtb, thm2);
                                    }), System.Windows.Threading.DispatcherPriority.Background);
                                }
                            }
                            break;
                        }
                        case "InsertLink": {
                            try {
                                string linkUrl = docVal;
                                string displayText = "";
                                if (!rtb.Selection.IsEmpty) {
                                    displayText = rtb.Selection.Text;
                                }
                                if (string.IsNullOrEmpty(displayText)) {
                                    displayText = linkUrl;
                                }
                                var linkRun = new System.Windows.Documents.Run(displayText);
                                var hyperlink = new System.Windows.Documents.Hyperlink(linkRun, rtb.CaretPosition);
                                try { hyperlink.NavigateUri = new Uri(linkUrl, UriKind.RelativeOrAbsolute); } catch { }
                                hyperlink.Foreground = new System.Windows.Media.SolidColorBrush(
                                    System.Windows.Media.Color.FromRgb(17, 85, 204));
                                hyperlink.ToolTip = linkUrl;
                                hyperlink.Cursor = System.Windows.Input.Cursors.Hand;
                                hyperlink.RequestNavigate += (s, e) => {
                                    try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); } catch { }
                                    e.Handled = true;
                                };
                            } catch { }
                            break;
                        }
                        case "GetWordCount": {
                            string rtbN = ((FrameworkElement)ctrl).Name;
                            var pageReader = win.FindName(rtbN + "_PageReader") as FlowDocumentReader;
                            FlowDocument activeDoc = rtb.Document;
                            if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                                activeDoc = pageReader.Document;
                            }
                            var range = new TextRange(activeDoc.ContentStart, activeDoc.ContentEnd);
                            string wcText = range.Text;
                            int words = wcText.Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries).Length;
                            int chars = wcText.Length;
                            SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|WordCount|" + LengthPrefix(words + "," + chars) + "\n");
                            break;
                        }
                        case "Zoom": {
                            double zoom;
                            if (double.TryParse(docVal, out zoom)) {
                                var parent = System.Windows.Media.VisualTreeHelper.GetParent(rtb) as FrameworkElement;
                                if (parent == null) parent = rtb;
                                var st = parent.LayoutTransform as System.Windows.Media.ScaleTransform;
                                if (st == null) {
                                    st = new System.Windows.Media.ScaleTransform(1, 1);
                                    parent.LayoutTransform = st;
                                }
                                st.ScaleX = zoom / 100.0;
                                st.ScaleY = zoom / 100.0;
                            }
                            break;
                        }
                        case "NewDocument": {
                            rtb.Document = new FlowDocument();
                            rtb.Document.FontFamily = new System.Windows.Media.FontFamily("Segoe UI, Segoe UI Emoji, Segoe UI Symbol");
                            rtb.Document.FontSize = 14;
                            
                            string viewMode = "paper";
                            if (_docViewModes.ContainsKey(rtb.Name)) {
                                viewMode = _docViewModes[rtb.Name];
                            } else {
                                _docViewModes[rtb.Name] = viewMode;
                            }
                            
                            var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                            string currentTheme = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                            
                            ApplyViewMode(rtb, viewMode, currentTheme, win);
                            break;
                        }
                        case "Undo":
                            rtb.Undo();
                            break;
                        case "Redo":
                            rtb.Redo();
                            break;
                        case "SelectAll": {
                            rtb.SelectAll();
                            break;
                        }
                        case "FindNext": {
                            string fnQuery = docVal; StringComparison fnCmp = StringComparison.OrdinalIgnoreCase;
                            int fnMc = docVal.IndexOf("|||MC:"); if (fnMc >= 0) { fnQuery = docVal.Substring(0, fnMc); fnCmp = docVal.Substring(fnMc + 6) == "1" ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase; }
                            if (!string.IsNullOrEmpty(fnQuery)) {
                                var map = BuildCharPositionMap(rtb.Document);
                                var sb = new StringBuilder();
                                foreach (var cp in map) sb.Append(cp.Character);
                                string plainText = sb.ToString();

                                TextPointer currentStart = rtb.Selection.IsEmpty ? rtb.Document.ContentStart : rtb.Selection.End;
                                int searchStartIdx = 0;
                                for (int i = 0; i < map.Count; i++) { if (map[i].Start.CompareTo(currentStart) >= 0) { searchStartIdx = i; break; } }

                                int idx = plainText.IndexOf(fnQuery, searchStartIdx, fnCmp);
                                if (idx < 0) idx = plainText.IndexOf(fnQuery, 0, fnCmp);

                                if (idx >= 0) {
                                    TextPointer start = map[idx].Start;
                                    TextPointer end = map[idx + fnQuery.Length - 1].End;
                                    if (start != null && end != null) {
                                        if (_activeMatchRange != null) { try { _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _highlightBrush); } catch { } }
                                        _activeMatchRange = new TextRange(start, end);
                                        _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _activeMatchBrush);
                                        rtb.Focus();
                                        rtb.Selection.Select(start, end); 
                                        if (start.Paragraph != null) start.Paragraph.BringIntoView(); 
                                    }
                                }
                            }
                            break;
                        }
                        case "FindPrevious": {
                            string fpQuery = docVal; StringComparison fpCmp = StringComparison.OrdinalIgnoreCase;
                            int fpMc = docVal.IndexOf("|||MC:"); if (fpMc >= 0) { fpQuery = docVal.Substring(0, fpMc); fpCmp = docVal.Substring(fpMc + 6) == "1" ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase; }
                            if (!string.IsNullOrEmpty(fpQuery)) {
                                var map = BuildCharPositionMap(rtb.Document);
                                var sb = new StringBuilder();
                                foreach (var cp in map) sb.Append(cp.Character);
                                string plainText = sb.ToString();

                                TextPointer currentStart = rtb.Selection.IsEmpty ? rtb.Document.ContentEnd : rtb.Selection.Start;
                                int searchStartIdx = map.Count - 1;
                                for (int i = map.Count - 1; i >= 0; i--) { if (map[i].End.CompareTo(currentStart) <= 0) { searchStartIdx = i; break; } }

                                int idx = plainText.LastIndexOf(fpQuery, searchStartIdx, fpCmp);
                                if (idx < 0) idx = plainText.LastIndexOf(fpQuery, map.Count - 1, fpCmp);

                                if (idx >= 0) {
                                    TextPointer start = map[idx].Start;
                                    TextPointer end = map[idx + fpQuery.Length - 1].End;
                                    if (start != null && end != null) {
                                        if (_activeMatchRange != null) { try { _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _highlightBrush); } catch { } }
                                        _activeMatchRange = new TextRange(start, end);
                                        _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _activeMatchBrush);
                                        rtb.Focus();
                                        rtb.Selection.Select(start, end); 
                                        if (start.Paragraph != null) start.Paragraph.BringIntoView(); 
                                    }
                                }
                            }
                            break;
                        }
                        case "ReplaceCurrent": {
                            string[] rp = docVal.Split(new[] { "|||" }, StringSplitOptions.None);
                            if (rp.Length >= 2) {
                                string find = rp[0]; string replace = rp[1];
                                StringComparison rcCmp = StringComparison.OrdinalIgnoreCase;
                                for (int pi = 2; pi < rp.Length; pi++) { if (rp[pi] == "MC:1") rcCmp = StringComparison.Ordinal; }
                                
                                if (!rtb.Selection.IsEmpty && rtb.Selection.Text.Equals(find, rcCmp)) rtb.Selection.Text = replace;

                                var map = BuildCharPositionMap(rtb.Document);
                                var sb = new StringBuilder(); foreach (var cp in map) sb.Append(cp.Character);
                                string plainText = sb.ToString();
                                TextPointer currentStart = rtb.Selection.End;
                                int searchStartIdx = 0;
                                for (int i = 0; i < map.Count; i++) { if (map[i].Start.CompareTo(currentStart) >= 0) { searchStartIdx = i; break; } }
                                int idx = plainText.IndexOf(find, searchStartIdx, rcCmp);
                                if (idx < 0) idx = plainText.IndexOf(find, 0, rcCmp);
                                if (idx >= 0) {
                                    TextPointer start = map[idx].Start; TextPointer end = map[idx + find.Length - 1].End;
                                    if (start != null && end != null) { rtb.Selection.Select(start, end); if (start.Paragraph != null) start.Paragraph.BringIntoView(); }
                                }
                            }
                            break;
                        }
                        case "ReplaceAll": {
                            string[] rp = docVal.Split(new[] { "|||" }, StringSplitOptions.None);
                            if (rp.Length >= 2) {
                                string find = rp[0]; string replace = rp[1];
                                bool isPreview = rp.Length > 2 && rp[2] == "1";
                                bool raMatchCase = false;
                                for (int pi = 2; pi < rp.Length; pi++) { if (rp[pi] == "MC:1") raMatchCase = true; }
                                
                                if (isPreview) {
                                    if (_isPreviewActive) rtb.Undo();
                                    rtb.BeginChange();
                                    ReplaceAllBackward(rtb, find, replace, raMatchCase);
                                    rtb.EndChange();
                                    _isPreviewActive = true;
                                } else {
                                    rtb.BeginChange();
                                    ReplaceAllBackward(rtb, find, replace, raMatchCase);
                                    rtb.EndChange();
                                }
                            }
                            break;
                        }
                        case "HighlightFinds": {
                            // Parse match-case flag: value may end with |||MC:0 or |||MC:1
                            string hlQuery = docVal ?? "";
                            bool hlMatchCase = false;
                            int hlMcIdx = hlQuery.IndexOf("|||MC:");
                            if (hlMcIdx >= 0) { hlMatchCase = hlQuery.Substring(hlMcIdx + 6) == "1"; hlQuery = hlQuery.Substring(0, hlMcIdx); }

                            _pendingHighlightQuery = hlQuery;
                            _pendingHighlightMatchCase = hlMatchCase;
                            _pendingHighlightRtb = rtb;
                            if (_highlightDebounce == null) {
                                _highlightDebounce = new System.Windows.Threading.DispatcherTimer {
                                    Interval = TimeSpan.FromMilliseconds(200)
                                };
                                _highlightDebounce.Tick += (ds, de) => {
                                    _highlightDebounce.Stop();
                                    ClearSearchHighlights(_pendingHighlightRtb);
                                    if (!string.IsNullOrEmpty(_pendingHighlightQuery) && _pendingHighlightQuery.Length >= 2) {
                                        HighlightAllMatches(_pendingHighlightRtb, _pendingHighlightQuery, _pendingHighlightMatchCase);
                                    }
                                };
                            }
                            _highlightDebounce.Stop();
                            if (string.IsNullOrEmpty(hlQuery)) { 
                                ClearSearchHighlights(rtb); 
                                var tb = win.FindName(rtb.Name + "_MatchCount") as System.Windows.Controls.TextBlock;
                                if (tb != null) tb.Text = "";
                            } else { 
                                _highlightDebounce.Start(); 
                            }
                            break;
                        }
                        case "ConfirmReplace": {
                            _isPreviewActive = false;
                            break;
                        }
                        case "CancelReplace": {
                            if (_isPreviewActive) {
                                rtb.Undo();
                                _isPreviewActive = false;
                            }
                            break;
                        }
                        case "ApplyDarkMode": {
                            ApplyDarkModeToDocument(rtb.Document);
                            break;
                        }
                        case "RestoreColors": {
                            RestoreDocumentColors(rtb.Document);
                            break;
                        }
                        case "SetupToolbarResponsive": {
                            // Setup responsive toolbar: hide/show named groups based on window width
                            // docVal = comma-separated list of group names in order of priority (first hidden first)
                            // Format can be "MainGrp" or "MainGrp|PopoverGrp"
                            if (!string.IsNullOrEmpty(docVal)) {
                                string[] groupNames = docVal.Split(',');
                                // Thresholds (in window pixels): each group gets hidden below this width
                                double[] thresholds = new double[] { 860, 760, 660, 560, 460 };
                                
                                Action<double> evaluateWidth = (w) => {
                                    for (int gi = 0; gi < groupNames.Length; gi++) {
                                        string[] pairs = groupNames[gi].Trim().Split('|');
                                        var mainGrp = win.FindName(pairs[0]) as FrameworkElement;
                                        var popGrp = pairs.Length > 1 ? win.FindName(pairs[1]) as FrameworkElement : null;
                                        
                                        if (mainGrp != null) {
                                            double threshold = gi < thresholds.Length ? thresholds[gi] : 400;
                                            bool isVisible = w > threshold;
                                            mainGrp.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;
                                            if (popGrp != null) {
                                                popGrp.Visibility = isVisible ? Visibility.Collapsed : Visibility.Visible;
                                            }
                                        }
                                    }
                                };

                                win.SizeChanged += (s, e) => {
                                    evaluateWidth(win.ActualWidth);
                                };
                                // Trigger initial evaluation
                                evaluateWidth(win.ActualWidth);
                            }
                            break;
                        }
                        case "QueryDOM": {
                            try {
                                string selector = docVal.ToLower();
                                StringBuilder sb = new StringBuilder();

                                if (selector == "headings") {
                                    int pIdx = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            string styleId = p.Tag as string ?? "";
                                            
                                            if (string.IsNullOrEmpty(styleId)) {
                                                if (p.FontWeight == FontWeights.Bold && p.FontSize > 14) {
                                                    styleId = "Heading1";
                                                }
                                            }
                                            
                                            string domText = new TextRange(p.ContentStart, p.ContentEnd).Text.Trim();
                                            bool isHeading = styleId.StartsWith("Heading", StringComparison.OrdinalIgnoreCase) || 
                                                             styleId.StartsWith("H", StringComparison.OrdinalIgnoreCase);
                                            
                                            if (!string.IsNullOrEmpty(domText) && isHeading) {
                                                sb.Append(pIdx + "|" + styleId + "|" + domText + "\n");
                                            }
                                            pIdx++;
                                        }
                                    });
                                } else if (selector == "hyperlinks") {
                                    int hlCount = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    string url = hl.NavigateUri != null ? hl.NavigateUri.ToString() : "";
                                                    string domText = new TextRange(hl.ContentStart, hl.ContentEnd).Text.Trim();
                                                    if (string.IsNullOrEmpty(domText)) domText = url;
                                                    
                                                    string relId = "memHl_" + hlCount;
                                                    if (!string.IsNullOrEmpty(url)) {
                                                        sb.Append(domText + "|" + url + "|" + relId + "\n");
                                                    }
                                                    hlCount++;
                                                }
                                            });
                                        }
                                    });
                                } else if (selector == "tables") {
                                    int tIdx = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Table) {
                                            var t = (System.Windows.Documents.Table)block;
                                            int rows = 0;
                                            foreach (var rg in t.RowGroups) rows += rg.Rows.Count;
                                            
                                            int cols = 0;
                                            if (t.RowGroups.Count > 0 && t.RowGroups[0].Rows.Count > 0) {
                                                cols = t.RowGroups[0].Rows[0].Cells.Count;
                                            }
                                            
                                            string firstCellText = "";
                                            if (t.RowGroups.Count > 0 && t.RowGroups[0].Rows.Count > 0 && t.RowGroups[0].Rows[0].Cells.Count > 0) {
                                                var firstCell = t.RowGroups[0].Rows[0].Cells[0];
                                                firstCellText = new TextRange(firstCell.ContentStart, firstCell.ContentEnd).Text.Trim();
                                            }
                                            if (firstCellText.Length > 30) firstCellText = firstCellText.Substring(0, 27) + "...";
                                            
                                            sb.Append(tIdx + "|" + rows + "|" + cols + "|" + firstCellText + "\n");
                                            tIdx++;
                                        }
                                    });
                                } else if (selector == "paragraphs") {
                                    int pIdx = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            string domText = new TextRange(p.ContentStart, p.ContentEnd).Text.Trim();
                                            string style = p.Tag as string ?? "Normal";
                                            if (!string.IsNullOrEmpty(domText)) {
                                                sb.Append(pIdx + "|" + style + "|" + domText + "\n");
                                            }
                                            pIdx++;
                                        }
                                    });
                                } else if (selector == "fonts") {
                                    var uniqueFonts = new System.Collections.Generic.HashSet<string>();
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            if (p.FontFamily != null) uniqueFonts.Add(p.FontFamily.Source);
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Run) {
                                                    var run = (System.Windows.Documents.Run)inline;
                                                    if (run.FontFamily != null) uniqueFonts.Add(run.FontFamily.Source);
                                                } else if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    if (hl.FontFamily != null) uniqueFonts.Add(hl.FontFamily.Source);
                                                }
                                            });
                                        }
                                    });
                                    foreach (var fName in uniqueFonts) {
                                        if (!string.IsNullOrEmpty(fName)) {
                                            sb.Append(fName + "\n");
                                        }
                                    }
                                }

                                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(sb.ToString()));
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerQueryDone|" + LengthPrefix(selector + "|" + b64) + "\n");
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "HighlightStyle": {
                            try {
                                string[] hp = docVal.Split('|');
                                if (hp.Length >= 2) {
                                    string styleId = hp[0];
                                    string colorName = hp[1];
                                    
                                    System.Windows.Media.Brush hlBrush = System.Windows.Media.Brushes.Yellow;
                                    try {
                                        hlBrush = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFromString(colorName);
                                    } catch {}

                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            string pStyle = p.Tag as string ?? "";
                                            
                                            if (string.IsNullOrEmpty(pStyle)) {
                                                if (p.FontWeight == FontWeights.Bold && p.FontSize > 14) {
                                                    pStyle = "Heading1";
                                                }
                                            }

                                            if (string.Equals(pStyle, styleId, StringComparison.OrdinalIgnoreCase) || 
                                                (styleId == "Heading" && pStyle.StartsWith("Heading", StringComparison.OrdinalIgnoreCase))) {
                                                
                                                TraverseInlines(p.Inlines, (inline) => {
                                                    if (inline is System.Windows.Documents.Run) {
                                                        var run = (System.Windows.Documents.Run)inline;
                                                        run.Background = hlBrush;
                                                    }
                                                });
                                            }
                                        }
                                    });
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "AuditLinks": {
                            try {
                                StringBuilder sb = new StringBuilder();
                                int hlCount = 0;
                                
                                TraverseBlocks(rtb.Document.Blocks, (block) => {
                                    if (block is System.Windows.Documents.Paragraph) {
                                        var p = (System.Windows.Documents.Paragraph)block;
                                        TraverseInlines(p.Inlines, (inline) => {
                                            if (inline is System.Windows.Documents.Hyperlink) {
                                                var hl = (System.Windows.Documents.Hyperlink)inline;
                                                string url = hl.NavigateUri != null ? hl.NavigateUri.ToString() : "";
                                                string domText = new TextRange(hl.ContentStart, hl.ContentEnd).Text.Trim();
                                                if (string.IsNullOrEmpty(domText)) domText = url;
                                                
                                                string relId = "memHl_" + hlCount;
                                                if (!string.IsNullOrEmpty(url)) {
                                                    sb.Append(relId + "|" + url + "|" + domText + "\n");
                                                }
                                                hlCount++;
                                            }
                                        });
                                    }
                                });
                                
                                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(sb.ToString()));
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerAuditDone|" + LengthPrefix(b64) + "\n");
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "RewriteLinks": {
                            try {
                                string[] lines = docVal.Split('\n');
                                var replacements = new System.Collections.Generic.Dictionary<string, string>();
                                foreach (var line in lines) {
                                    if (string.IsNullOrEmpty(line)) continue;
                                    string[] parts2 = line.Split('|');
                                    if (parts2.Length >= 2) {
                                        replacements[parts2[0].Trim()] = parts2[1].Trim();
                                    }
                                }

                                if (replacements.Count > 0) {
                                    int hlCount = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    string relId = "memHl_" + hlCount;
                                                    if (replacements.ContainsKey(relId)) {
                                                        string newUrl = replacements[relId];
                                                        try {
                                                            hl.NavigateUri = new Uri(newUrl, UriKind.RelativeOrAbsolute);
                                                            hl.ToolTip = newUrl;
                                                        } catch {}
                                                    }
                                                    hlCount++;
                                                }
                                            });
                                        }
                                    });
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "StandardizeFont": {
                            try {
                                string[] hp = docVal.Split('|');
                                if (hp.Length >= 2) {
                                    string fromFont = hp[0].Trim();
                                    string toFont = hp[1].Trim();
                                    var targetFamily = new System.Windows.Media.FontFamily(toFont);

                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            if (p.FontFamily != null && string.Equals(p.FontFamily.Source, fromFont, StringComparison.OrdinalIgnoreCase)) {
                                                p.FontFamily = targetFamily;
                                            }
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Run) {
                                                    var run = (System.Windows.Documents.Run)inline;
                                                    if (run.FontFamily != null && string.Equals(run.FontFamily.Source, fromFont, StringComparison.OrdinalIgnoreCase)) {
                                                        run.FontFamily = targetFamily;
                                                    }
                                                } else if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    if (hl.FontFamily != null && string.Equals(hl.FontFamily.Source, fromFont, StringComparison.OrdinalIgnoreCase)) {
                                                        hl.FontFamily = targetFamily;
                                                    }
                                                }
                                            });
                                        }
                                    });
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "CompileTemplate": {
                            try {
                                string[] lines = docVal.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                                if (lines.Length > 0) {
                                    System.Windows.Documents.Paragraph placeholder = null;
                                    System.Windows.Documents.BlockCollection parentCollection = null;
                                    int placeholderIdx = -1;

                                    Action<System.Windows.Documents.BlockCollection> searchCollection = null;
                                    searchCollection = (coll) => {
                                        if (placeholder != null) return;
                                        for (int i = 0; i < coll.Count; i++) {
                                            var b = coll.ElementAt(i);
                                            if (b is System.Windows.Documents.Paragraph) {
                                                var p = (System.Windows.Documents.Paragraph)b;
                                                string pText = new TextRange(p.ContentStart, p.ContentEnd).Text;
                                                if (pText.Contains("{{REPORT_TABLE}}")) {
                                                    placeholder = p;
                                                    parentCollection = coll;
                                                    placeholderIdx = i;
                                                    return;
                                                }
                                            } else if (b is System.Windows.Documents.Section) {
                                                searchCollection(((System.Windows.Documents.Section)b).Blocks);
                                            } else if (b is System.Windows.Documents.List) {
                                                foreach (var li in ((System.Windows.Documents.List)b).ListItems) {
                                                    searchCollection(li.Blocks);
                                                }
                                            } else if (b is System.Windows.Documents.Table) {
                                                foreach (var rg in ((System.Windows.Documents.Table)b).RowGroups) {
                                                    foreach (var row in rg.Rows) {
                                                        foreach (var cell in row.Cells) {
                                                            searchCollection(cell.Blocks);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    };

                                    searchCollection(rtb.Document.Blocks);

                                    if (placeholder != null && parentCollection != null) {
                                        var table = new System.Windows.Documents.Table();
                                        table.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                        table.BorderThickness = new Thickness(1);
                                        table.CellSpacing = 0;
                                        table.Margin = new Thickness(0, 8, 0, 8);
                                        
                                        string[] headers = lines[0].Split(',');
                                        int colCount = headers.Length;
                                        
                                        for (int i = 0; i < colCount; i++) {
                                            table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                                        }

                                        var rg = new System.Windows.Documents.TableRowGroup();

                                        var headerRow = new System.Windows.Documents.TableRow();
                                        foreach (string colText in headers) {
                                            var cell = new System.Windows.Documents.TableCell();
                                            cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                            cell.BorderThickness = new Thickness(0.5);
                                            cell.Padding = new Thickness(8, 6, 8, 6);
                                            cell.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(47, 85, 151));
                                            
                                            var p = new System.Windows.Documents.Paragraph();
                                            p.TextAlignment = System.Windows.TextAlignment.Center;
                                            var run = new System.Windows.Documents.Run(colText.Trim());
                                            run.FontWeight = FontWeights.Bold;
                                            run.Foreground = System.Windows.Media.Brushes.White;
                                            run.FontSize = 12;
                                            p.Inlines.Add(run);
                                            cell.Blocks.Add(p);
                                            headerRow.Cells.Add(cell);
                                        }
                                        rg.Rows.Add(headerRow);

                                        for (int rIdx = 1; rIdx < lines.Length; rIdx++) {
                                            string[] cells = lines[rIdx].Split(',');
                                            var row = new System.Windows.Documents.TableRow();
                                            System.Windows.Media.Color bgCol = (rIdx % 2 == 1) ? System.Windows.Media.Color.FromRgb(242, 245, 249) : System.Windows.Media.Color.FromRgb(255, 255, 255);
                                            var bgBrush = new System.Windows.Media.SolidColorBrush(bgCol);

                                            for (int cIdx = 0; cIdx < colCount; cIdx++) {
                                                string cellVal = cIdx < cells.Length ? cells[cIdx].Trim() : "";
                                                var cell = new System.Windows.Documents.TableCell();
                                                cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                                cell.BorderThickness = new Thickness(0.5);
                                                cell.Padding = new Thickness(8, 6, 8, 6);
                                                cell.Background = bgBrush;

                                                var p = new System.Windows.Documents.Paragraph();
                                                p.TextAlignment = System.Windows.TextAlignment.Left;
                                                var run = new System.Windows.Documents.Run(cellVal);
                                                run.FontSize = 11;
                                                p.Inlines.Add(run);
                                                cell.Blocks.Add(p);
                                                row.Cells.Add(cell);
                                            }
                                            rg.Rows.Add(row);
                                        }

                                        table.RowGroups.Add(rg);

                                        parentCollection.InsertAfter(placeholder, table);
                                        parentCollection.Remove(placeholder);
                                    }
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "SetPageView": {
                            try {
                                string viewMode = (docVal ?? "").ToLower().Trim();
                                var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                string currentTheme = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                ApplyViewMode(rtb, viewMode, currentTheme, win);
                            } catch (Exception ex) {
                                string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log");
                                System.IO.File.AppendAllText(debugPath, "SetPageView EXCEPTION: " + ex.ToString() + "\n");
                            }
                            break;
                        }
                        case "UpdateSpacers": {
                            try {
                                string currentMode = "paper";
                                if (_docViewModes.ContainsKey(rtb.Name)) {
                                    currentMode = _docViewModes[rtb.Name];
                                }
                                if (currentMode == "paper") {
                                    var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string thm = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                    _InsertPageBreakSpacers(rtb, thm);
                                }
                                
                                // Also update flow document reader if active
                                string readerName = rtb.Name + "_PageReader";
                                FlowDocumentReader reader = win.FindName(readerName) as FlowDocumentReader;
                                if (reader != null && reader.Visibility == Visibility.Visible) {
                                    var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string thm = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                    StyleReaderVisuals(reader, thm, win);
                                }
                            } catch { }
                            break;
                        }
                        // ================================================================
                        // TABLE OPERATIONS
                        // ================================================================
                        case "InsertRowAbove":
                        case "InsertRowBelow": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    if (row != null && rg != null) {
                                        int colCount = row.Cells.Count;
                                        var newRow = new System.Windows.Documents.TableRow();
                                        for (int c = 0; c < colCount; c++) {
                                            var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                                            newCell.BorderBrush = cell.BorderBrush;
                                            newCell.BorderThickness = cell.BorderThickness;
                                            newCell.Padding = cell.Padding;
                                            newRow.Cells.Add(newCell);
                                        }
                                        int idx = rg.Rows.IndexOf(row);
                                        if (docCmd == "InsertRowAbove") {
                                            rg.Rows.Insert(idx, newRow);
                                        } else {
                                            rg.Rows.Insert(idx + 1, newRow);
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "InsertColumnLeft":
                        case "InsertColumnRight": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    var table = rg.Parent as System.Windows.Documents.Table;
                                    if (table != null) {
                                        int colIdx = row.Cells.IndexOf(cell);
                                        int insertIdx = docCmd == "InsertColumnLeft" ? colIdx : colIdx + 1;
                                        table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                                        foreach (var trg in table.RowGroups) {
                                            foreach (var tr in trg.Rows) {
                                                var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                                                newCell.BorderBrush = cell.BorderBrush;
                                                newCell.BorderThickness = cell.BorderThickness;
                                                newCell.Padding = cell.Padding;
                                                if (insertIdx <= tr.Cells.Count) {
                                                    tr.Cells.Insert(insertIdx, newCell);
                                                } else {
                                                    tr.Cells.Add(newCell);
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "DeleteRow": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    if (rg != null && rg.Rows.Count > 1) {
                                        rg.Rows.Remove(row);
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "DeleteColumn": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    var table = rg.Parent as System.Windows.Documents.Table;
                                    if (table != null) {
                                        int colIdx = row.Cells.IndexOf(cell);
                                        if (row.Cells.Count > 1) {
                                            foreach (var trg in table.RowGroups) {
                                                foreach (var tr in trg.Rows) {
                                                    if (colIdx < tr.Cells.Count) {
                                                        tr.Cells.RemoveAt(colIdx);
                                                    }
                                                }
                                            }
                                            if (table.Columns.Count > 0) {
                                                table.Columns.RemoveAt(table.Columns.Count - 1);
                                            }
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "CellBackground": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var color = ShowColorPickerDialog(win);
                                    if (color.HasValue) {
                                        cell.Background = new System.Windows.Media.SolidColorBrush(color.Value);
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "TableBorders": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    var table = rg.Parent as System.Windows.Documents.Table;
                                    if (table != null) {
                                        // Toggle between thick, thin, and no borders
                                        double currentThick = table.BorderThickness.Left;
                                        Thickness newBorder;
                                        if (currentThick >= 1.5) newBorder = new Thickness(0);
                                        else if (currentThick >= 0.5) newBorder = new Thickness(2);
                                        else newBorder = new Thickness(1);
                                        table.BorderThickness = newBorder;
                                        foreach (var trg in table.RowGroups) {
                                            foreach (var tr in trg.Rows) {
                                                foreach (var tc in tr.Cells) {
                                                    tc.BorderThickness = new Thickness(Math.Max(0.5, newBorder.Left * 0.5));
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "MergeCells": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    int current = cell.ColumnSpan;
                                    cell.ColumnSpan = current + 1;
                                }
                            } catch { }
                            break;
                        }
                        case "SplitCell": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null && cell.ColumnSpan > 1) {
                                    cell.ColumnSpan = cell.ColumnSpan - 1;
                                }
                            } catch { }
                            break;
                        }
                        // ================================================================
                        // FORMATTING COMMANDS
                        // ================================================================
                        case "Superscript": {
                            try {
                                var sel = rtb.Selection;
                                if (!sel.IsEmpty) {
                                    var current = sel.GetPropertyValue(Inline.BaselineAlignmentProperty);
                                    if (current is BaselineAlignment && (BaselineAlignment)current == BaselineAlignment.Superscript)
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Baseline);
                                    else
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Superscript);
                                    sel.ApplyPropertyValue(TextElement.FontSizeProperty, 10.0);
                                }
                            } catch { }
                            break;
                        }
                        case "Subscript": {
                            try {
                                var sel = rtb.Selection;
                                if (!sel.IsEmpty) {
                                    var current = sel.GetPropertyValue(Inline.BaselineAlignmentProperty);
                                    if (current is BaselineAlignment && (BaselineAlignment)current == BaselineAlignment.Subscript)
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Baseline);
                                    else
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Subscript);
                                    sel.ApplyPropertyValue(TextElement.FontSizeProperty, 10.0);
                                }
                            } catch { }
                            break;
                        }
                        case "IncreaseFontSize": {
                            try {
                                var sel = rtb.Selection;
                                var sz = sel.GetPropertyValue(TextElement.FontSizeProperty);
                                double currentSize = (sz != DependencyProperty.UnsetValue) ? (double)sz : 14.0;
                                double[] sizes = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72 };
                                double newSize = 72;
                                for (int si = 0; si < sizes.Length; si++) {
                                    if (sizes[si] > currentSize) { newSize = sizes[si]; break; }
                                }
                                sel.ApplyPropertyValue(TextElement.FontSizeProperty, newSize);
                            } catch { }
                            break;
                        }
                        case "DecreaseFontSize": {
                            try {
                                var sel = rtb.Selection;
                                var sz = sel.GetPropertyValue(TextElement.FontSizeProperty);
                                double currentSize = (sz != DependencyProperty.UnsetValue) ? (double)sz : 14.0;
                                double[] sizes = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72 };
                                double newSize = 8;
                                for (int si = sizes.Length - 1; si >= 0; si--) {
                                    if (sizes[si] < currentSize) { newSize = sizes[si]; break; }
                                }
                                sel.ApplyPropertyValue(TextElement.FontSizeProperty, newSize);
                            } catch { }
                            break;
                        }
                        case "TextColor": {
                            try {
                                var color = ShowColorPickerDialog(win);
                                if (color.HasValue) {
                                    rtb.Selection.ApplyPropertyValue(TextElement.ForegroundProperty,
                                        new System.Windows.Media.SolidColorBrush(color.Value));
                                }
                            } catch { }
                            break;
                        }
                        case "Highlight": {
                            try {
                                var color = ShowColorPickerDialog(win);
                                if (color.HasValue) {
                                    rtb.Selection.ApplyPropertyValue(TextElement.BackgroundProperty,
                                        new System.Windows.Media.SolidColorBrush(color.Value));
                                }
                            } catch { }
                            break;
                        }
                        case "ClearFormatting": {
                            try {
                                var sel = rtb.Selection;
                                sel.ApplyPropertyValue(TextElement.FontSizeProperty, 14.0);
                                sel.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Normal);
                                sel.ApplyPropertyValue(TextElement.FontStyleProperty, FontStyles.Normal);
                                sel.ApplyPropertyValue(Inline.TextDecorationsProperty, null);
                                sel.ApplyPropertyValue(TextElement.ForegroundProperty, System.Windows.Media.Brushes.Black);
                                sel.ApplyPropertyValue(TextElement.BackgroundProperty, System.Windows.Media.Brushes.Transparent);
                                sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Baseline);
                            } catch { }
                            break;
                        }
                        // ================================================================
                        // SPELL CHECK COMMANDS
                        // ================================================================
                        case "LoadDictionary": {
                            try {
                                var dlg = new Microsoft.Win32.OpenFileDialog();
                                dlg.Title = "Select Dictionary File (.dic / .lex)";
                                dlg.Filter = "Dictionary Files (*.dic;*.lex)|*.dic;*.lex|All Files|*.*";
                                if (dlg.ShowDialog(win) == true) {
                                    string dictPath = dlg.FileName;
                                    try {
                                        Uri dictUri = new Uri(dictPath);
                                        if (!rtb.SpellCheck.CustomDictionaries.Contains(dictUri)) {
                                            rtb.SpellCheck.CustomDictionaries.Add(dictUri);
                                        }
                                    } catch { }
                                    SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                                }
                            } catch { }
                            break;
                        }
                        case "AddDictionary": {
                            try {
                                string dictPath = docVal;
                                if (!string.IsNullOrEmpty(dictPath)) {
                                    Uri dictUri = new Uri(dictPath);
                                    if (!rtb.SpellCheck.CustomDictionaries.Contains(dictUri)) {
                                        rtb.SpellCheck.CustomDictionaries.Add(dictUri);
                                    }
                                    SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                                }
                            } catch { }
                            break;
                        }
                        case "SpellCheckOff": {
                            try {
                                rtb.SpellCheck.IsEnabled = false;
                                SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                            } catch { }
                            break;
                        }
                        case "SpellCheck": {
                            try {
                                string scAction = (docVal ?? "").ToLower().Trim();
                                if (scAction == "on") {
                                    rtb.SpellCheck.IsEnabled = true;
                                } else if (scAction == "off") {
                                    rtb.SpellCheck.IsEnabled = false;
                                } else if (scAction == "toggle") {
                                    rtb.SpellCheck.IsEnabled = !rtb.SpellCheck.IsEnabled;
                                } else if (scAction.StartsWith("setlang:")) {
                                    string langTag = scAction.Substring(8);
                                    _spellCheckLangs[rtb.Name] = langTag;
                                    string langToApply = langTag;
                                    if (langTag == "auto") {
                                        langToApply = DetectLanguage(rtb);
                                    }
                                    var xmlLang = System.Windows.Markup.XmlLanguage.GetLanguage(langToApply);
                                    rtb.Language = xmlLang;
                                    if (rtb.Document != null) {
                                        rtb.Document.Language = xmlLang;
                                    }
                                    bool wasEnabled = rtb.SpellCheck.IsEnabled;
                                    rtb.SpellCheck.IsEnabled = false;
                                    rtb.SpellCheck.IsEnabled = wasEnabled;
                                }
                                SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                            } catch { }
                            break;
                        }
                        case "QuerySpellCheck": {
                            try {
                                SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                            } catch { }
                            break;
                        }
                    }
                }
#endif
                else if (parts[1] == "StartPositionTimer" && ctrl is MediaElement)
                {
                    // Handle all position tracking and seeking in C# to avoid IPC feedback loops
                    var me = (MediaElement)ctrl;
                    string sliderName = parts.Length > 2 ? parts[2] : "";
                    if (!string.IsNullOrEmpty(sliderName))
                    {
                        var slider = win.FindName(sliderName) as Slider;
                        if (slider != null)
                        {
                            bool isSeeking = false;
                            bool isUpdating = false;

                            // Detect user drag start/end via Thumb routed events
                            slider.AddHandler(Thumb.DragStartedEvent, new DragStartedEventHandler((ds, de) =>
                            {
                                isSeeking = true;
                            }));
                            slider.AddHandler(Thumb.DragCompletedEvent, new DragCompletedEventHandler((dc, dce) =>
                            {
                                me.Position = TimeSpan.FromSeconds(slider.Value);
                                isSeeking = false;
                            }));

                            // Also handle click-on-track seeking
                            slider.PreviewMouseLeftButtonUp += (mu, mue) =>
                            {
                                if (!isSeeking)
                                {
                                    me.Position = TimeSpan.FromSeconds(slider.Value);
                                }
                            };

                            // Timer syncs slider position (only when user isn't seeking)
                            var posTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
                            posTimer.Tick += (s, e) =>
                            {
                                if (me.NaturalDuration.HasTimeSpan && !isSeeking)
                                {
                                    isUpdating = true;
                                    slider.Maximum = me.NaturalDuration.TimeSpan.TotalSeconds;
                                    slider.Value = me.Position.TotalSeconds;
                                    isUpdating = false;
                                }
                            };
                            posTimer.Start();
                        }
                    }
                }
                else if (parts[1] == "SetPosition" && ctrl is UIElement)
                {
                    var coords = parts[2].Split(',');
                    if (coords.Length >= 2)
                    {
                        Canvas.SetLeft((UIElement)ctrl, double.Parse(coords[0], System.Globalization.CultureInfo.InvariantCulture));
                        Canvas.SetTop((UIElement)ctrl, double.Parse(coords[1], System.Globalization.CultureInfo.InvariantCulture));
                    }
                }
                else if (parts[1] == "SetCanvasMode" && ctrl is Canvas)
                {
                    canvasModes[parts[0]] = parts[2];
                }
                else if (parts[1] == "EnableZoomPan" && ctrl is Canvas)
                {
                    EnableCanvasZoomPan((Canvas)ctrl);
                }
                else if (parts[1] == "ZoomAll" && ctrl is Canvas)
                {
                    ZoomAllCanvas((Canvas)ctrl);
                }
                else if (parts[1] == "Zoom" && ctrl is Canvas)
                {
                    ZoomCanvas((Canvas)ctrl, double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture));
                }
                else if (parts[1] == "EnableDrag" && ctrl is FrameworkElement)
                {
                    EnableCanvasDrag((FrameworkElement)ctrl, parts[0], parts.Length > 2 ? parts[2] : "");
                }
                else if (parts[1] == "BeginStoryboard" && ctrl is FrameworkElement)
                {
                    var sb = ((FrameworkElement)ctrl).FindResource(parts[2]) as System.Windows.Media.Animation.Storyboard;
                    if (sb != null) sb.Begin((FrameworkElement)ctrl);
                }
                else if (parts[1] == "EnableListBoxDragDrop" && ctrl is ListBox)
                {
                    EnableListBoxDragDrop((ListBox)ctrl, parts[0]);
                }
                else if (parts[1] == "EnableListBoxDragSource" && ctrl is ListBox)
                {
                    string dragFormat = parts.Length > 2 ? parts[2] : "ListBoxItem";
                    EnableListBoxDragSource((ListBox)ctrl, parts[0], dragFormat);
                }
                else if (parts[1] == "EnableDragSource" && ctrl is UIElement)
                {
                    string dragFormat = parts.Length > 2 ? parts[2] : "DragItem";
                    EnableGenericDragSource((UIElement)ctrl, parts[0], dragFormat);
                }
                else if (parts[1] == "EnableDropTarget" && ctrl is UIElement)
                {
                    string dropFormat = parts.Length > 2 ? parts[2] : "DragItem";
                    EnableGenericDropTarget((UIElement)ctrl, parts[0], dropFormat);
                }
                else if (parts[1] == "Close" && ctrl is Window)
                {
                    var ownerHwnd = new System.Windows.Interop.WindowInteropHelper((Window)ctrl).Owner;
                    if (ownerHwnd != IntPtr.Zero)
                    {
                        SetForegroundWindow(ownerHwnd);
                    }
                    win.Dispatcher.BeginInvoke(new Action(() => ((Window)ctrl).Close()));
                }
                else if (parts[1] == "AppendText" && ctrl is System.Windows.Controls.TextBox)
                {
                    var tb = (System.Windows.Controls.TextBox)ctrl;
                    tb.AppendText(parts[2]);
                    tb.ScrollToEnd();
                }
                else if (parts[1] == "InsertText" && ctrl is System.Windows.Controls.TextBox)
                {
                    var tb = (System.Windows.Controls.TextBox)ctrl;
                    int idx = tb.CaretIndex;
                    string pre = tb.Text.Substring(0, idx);
                    string post = tb.Text.Substring(idx);
                    tb.Text = pre + parts[2] + post;
                    tb.CaretIndex = idx + parts[2].Length;
                }
                else if (parts[1] == "NativeOwner" && ctrl is Window)
                {
                    new System.Windows.Interop.WindowInteropHelper((Window)ctrl).Owner = new IntPtr(long.Parse(parts[2]));
                    InheritWindowIconAndTitle((Window)ctrl, parts[2]);
                }
                else if (parts[1] == "Focus" && ctrl is UIElement)
                {
                    if (parts[2].ToLower() == "true" || parts[2] == "1") ((UIElement)ctrl).Focus();
                    else System.Windows.Input.Keyboard.ClearFocus();
                }
                else if (parts[1] == "BringIntoView" && ctrl is FrameworkElement)
                {
                    ((FrameworkElement)ctrl).BringIntoView();
                }
                else if (parts[1] == "Invoke" && ctrl is System.Windows.Controls.Primitives.ButtonBase)
                {
                    if (ctrl is System.Windows.Controls.Primitives.ToggleButton)
                    {
                        var tPeer = new System.Windows.Automation.Peers.ToggleButtonAutomationPeer((System.Windows.Controls.Primitives.ToggleButton)ctrl);
                        var toggleProv = tPeer.GetPattern(System.Windows.Automation.Peers.PatternInterface.Toggle) as System.Windows.Automation.Provider.IToggleProvider;
                        if (toggleProv != null) toggleProv.Toggle();
                    }
                    else if (ctrl is System.Windows.Controls.Button)
                    {
                        var peer = new System.Windows.Automation.Peers.ButtonAutomationPeer((System.Windows.Controls.Button)ctrl);
                        var invokeProv = peer.GetPattern(System.Windows.Automation.Peers.PatternInterface.Invoke) as System.Windows.Automation.Provider.IInvokeProvider;
                        if (invokeProv != null) invokeProv.Invoke();
                    }
                }
                else if (parts[1] == "TrapScroll" && ctrl is ScrollViewer)
                {
                    var sv = (ScrollViewer)ctrl;
                    System.Windows.Input.MouseWheelEventHandler handler = (s, e) =>
                    {
                        sv.ScrollToVerticalOffset(sv.VerticalOffset - e.Delta / 3.0);
                        e.Handled = true;
                    };
                    sv.PreviewMouseWheel -= handler;
                    sv.PreviewMouseWheel += handler;
                    sv.MouseWheel -= handler;
                    sv.MouseWheel += handler;
                }
                else if (parts[1].StartsWith("Effect.") && ctrl is UIElement)
                {
                    // Navigate through the Effect property to set sub-properties on ShaderEffect objects.
                    // e.g. "MyBorder|Effect.BlurRadius|0.5" => get MyBorder.Effect, then set .BlurRadius = 0.5
                    var effect = ((UIElement)ctrl).Effect;
                    string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_effect_debug.log");
                    try { System.IO.File.AppendAllText(debugPath, DateTime.Now.ToString("HH:mm:ss.fff") + " ctrl=" + parts[0] + " type=" + ctrl.GetType().Name + " effect=" + (effect != null ? effect.GetType().FullName : "NULL") + " prop=" + parts[1] + " val=" + parts[2] + "\n"); } catch { }
                    if (effect != null)
                    {
                        string subPropName = parts[1].Substring(7); // strip "Effect."
                        var subProp = effect.GetType().GetProperty(subPropName);
                        if (subProp != null)
                        {
                            object val = null;
                            string pt = subProp.PropertyType.Name;
                            if (pt == "Brush") val = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]);
                            else if (pt == "Color") val = System.Windows.Media.ColorConverter.ConvertFromString(parts[2]);
                            else if (pt == "Point")
                            {
                                string[] coords = parts[2].Split(',');
                                if (coords.Length == 2)
                                    val = new Point(double.Parse(coords[0], System.Globalization.CultureInfo.InvariantCulture), double.Parse(coords[1], System.Globalization.CultureInfo.InvariantCulture));
                                else
                                    val = System.Windows.Point.Parse(parts[2]);
                            }
                            else if (subProp.PropertyType.IsEnum) val = Enum.Parse(subProp.PropertyType, parts[2], true);
                            else if (pt == "Double") val = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                            else if (pt == "Boolean") val = Convert.ToBoolean(parts[2]);
                            else val = Convert.ChangeType(parts[2], subProp.PropertyType);
                            subProp.SetValue(effect, val, null);
                        }
                        else
                        {
                            try { System.IO.File.AppendAllText(debugPath, "  -> Property '" + subPropName + "' NOT FOUND on " + effect.GetType().Name + "\n"); } catch { }
                        }
                    }
                }
                else
                {
                    var prop = ctrl.GetType().GetProperty(parts[1]);
                    if (prop != null)
                    {
                        object val = null;
                        string pt = prop.PropertyType.Name;
                        if (pt == "Brush") val = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]);
                        else if (pt == "Color") val = System.Windows.Media.ColorConverter.ConvertFromString(parts[2]);
                        else if (pt == "Point")
                        {
                            string[] coords = parts[2].Split(',');
                            if (coords.Length == 2)
                            {
                                val = new Point(
                                    double.Parse(coords[0], System.Globalization.CultureInfo.InvariantCulture),
                                    double.Parse(coords[1], System.Globalization.CultureInfo.InvariantCulture)
                                );
                            }
                            else
                            {
                                val = System.Windows.Point.Parse(parts[2]);
                            }
                        }
                        else if (prop.PropertyType.IsEnum) val = Enum.Parse(prop.PropertyType, parts[2], true);
                        else if (pt == "Double") val = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                        else if (pt == "Boolean" || pt == "Nullable`1") val = Convert.ToBoolean(parts[2]);
                        else if (pt == "Thickness") val = new System.Windows.ThicknessConverter().ConvertFromString(parts[2]);
                        else if (pt == "CornerRadius") val = new System.Windows.CornerRadiusConverter().ConvertFromString(parts[2]);
                        else if (pt == "ImageSource")
                        {
                            if (parts[2].StartsWith("HICON:"))
                            {
                                IntPtr hIcon = new IntPtr(long.Parse(parts[2].Substring(6)));
                                val = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(hIcon, System.Windows.Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                            }
                            else if (parts[2].StartsWith("HBITMAP:"))
                            {
                                IntPtr hBmp = new IntPtr(long.Parse(parts[2].Substring(8)));
                                val = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(hBmp, IntPtr.Zero, System.Windows.Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                            }
                            else if (parts[2].EndsWith(".gif", StringComparison.OrdinalIgnoreCase)) 
                            {
                                var bmp = new System.Windows.Media.Imaging.BitmapImage(new Uri(parts[2], UriKind.RelativeOrAbsolute));
                                ImageBehavior.SetAnimatedSource((System.Windows.Controls.Image)ctrl, bmp);
                                return;
                            }
                            else
                            {
                                val = new System.Windows.Media.ImageSourceConverter().ConvertFromString(parts[2]);
                            }
                        }
                        else if (pt == "GridLength") val = new System.Windows.GridLengthConverter().ConvertFromString(parts[2]);
                        else if (pt == "Object" || pt == "String") val = parts[2];
                        else if (pt == "Uri") val = new Uri(parts[2], UriKind.RelativeOrAbsolute);
                        else if (pt == "Rect") val = System.Windows.Rect.Parse(parts[2]);
                        else if (pt == "Geometry") val = System.Windows.Media.Geometry.Parse(parts[2]);
                        else val = Convert.ChangeType(parts[2], prop.PropertyType);
                        prop.SetValue(ctrl, val, null);
                    }
                }
            }
        }
    }

    private void UnregisterNamesRecursive(DependencyObject d)
    {
        var visited = new System.Collections.Generic.HashSet<object>();
        UnregisterNamesRecursiveInternal(d, visited);
    }

    private void UnregisterNamesRecursiveInternal(DependencyObject d, System.Collections.Generic.HashSet<object> visited)
    {
        if (d == null || !visited.Add(d)) return;
        var fe = d as FrameworkElement;
        if (fe != null && !string.IsNullOrEmpty(fe.Name))
        {
            try {
                var ns = NameScope.GetNameScope(win);
                if (ns != null) { ns.UnregisterName(fe.Name); }
                else { win.UnregisterName(fe.Name); }
            } catch { }
            try {
                var keys = _boundEvents.Where(k => k.StartsWith(fe.Name + ":")).ToList();
                foreach (var key in keys) {
                    _boundEvents.Remove(key);
                }
            } catch { }
        }
        var fce = d as FrameworkContentElement;
        if (fce != null && !string.IsNullOrEmpty(fce.Name))
        {
            try {
                var ns = NameScope.GetNameScope(win);
                if (ns != null) { ns.UnregisterName(fce.Name); }
                else { win.UnregisterName(fce.Name); }
            } catch { }
            try {
                var keys = _boundEvents.Where(k => k.StartsWith(fce.Name + ":")).ToList();
                foreach (var key in keys) {
                    _boundEvents.Remove(key);
                }
            } catch { }
        }
        foreach (object child in LogicalTreeHelper.GetChildren(d))
        {
            if (child is DependencyObject)
            {
                UnregisterNamesRecursiveInternal((DependencyObject)child, visited);
            }
        }
        var cc = d as ContentControl;
        if (cc != null && cc.Content is DependencyObject)
        {
            UnregisterNamesRecursiveInternal((DependencyObject)cc.Content, visited);
        }
        var dec = d as Decorator;
        if (dec != null && dec.Child != null)
        {
            UnregisterNamesRecursiveInternal(dec.Child, visited);
        }
        var panel = d as Panel;
        if (panel != null)
        {
            foreach (UIElement child in panel.Children)
            {
                UnregisterNamesRecursiveInternal(child, visited);
            }
        }
        var ic = d as ItemsControl;
        if (ic != null)
        {
            foreach (object item in ic.Items)
            {
                if (item is DependencyObject)
                {
                    UnregisterNamesRecursiveInternal((DependencyObject)item, visited);
                }
            }
        }
    }

    private DependencyObject FindLogicalNodeDeep(DependencyObject parent, string name)
    {
        var visited = new System.Collections.Generic.HashSet<object>();
        return FindControlDeepInternal(parent, name, visited);
    }

    private DependencyObject FindControlDeepInternal(DependencyObject d, string name, System.Collections.Generic.HashSet<object> visited)
    {
        if (d == null || !visited.Add(d)) return null;

        var fe = d as FrameworkElement;
        if (fe != null && fe.Name == name) return d;

        var fce = d as FrameworkContentElement;
        if (fce != null && fce.Name == name) return d;

        if (fe != null && fe.ContextMenu != null)
        {
            var found = FindControlDeepInternal(fe.ContextMenu, name, visited);
            if (found != null) return found;
        }

        // 1. ContentControl Content
        var cc = d as ContentControl;
        if (cc != null && cc.Content is DependencyObject)
        {
            var found = FindControlDeepInternal((DependencyObject)cc.Content, name, visited);
            if (found != null) return found;
        }

        // 2. Decorator Child
        var dec = d as Decorator;
        if (dec != null && dec.Child != null)
        {
            var found = FindControlDeepInternal(dec.Child, name, visited);
            if (found != null) return found;
        }

        // 3. Panel Children
        var panel = d as Panel;
        if (panel != null)
        {
            foreach (UIElement child in panel.Children)
            {
                var found = FindControlDeepInternal(child, name, visited);
                if (found != null) return found;
            }
        }

        // 4. ItemsControl Items
        var ic = d as ItemsControl;
        if (ic != null)
        {
            foreach (object item in ic.Items)
            {
                if (item is DependencyObject)
                {
                    var found = FindControlDeepInternal((DependencyObject)item, name, visited);
                    if (found != null) return found;
                }
            }
        }

        // 5. Logical Tree Helper
        foreach (object child in LogicalTreeHelper.GetChildren(d))
        {
            if (child is DependencyObject)
            {
                var found = FindControlDeepInternal((DependencyObject)child, name, visited);
                if (found != null) return found;
            }
        }

        return null;
    }

    private void WalkVisualTree(System.Windows.DependencyObject parent, Action<System.Windows.DependencyObject> callback)
    {
        int count = System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < count; i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, i);
            callback(child);
            WalkVisualTree(child, callback);
        }
    }

    private object FindControlByPath(string path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        object cached;
        if (_controlCache.TryGetValue(path, out cached)) return cached;

        string[] parts = path.Split('>');
        object current = null;
        if (win != null)
        {
            if (parts[0] == "Window")
            {
                current = win;
            }
            else
            {
                current = win.FindName(parts[0]);
                if (current == null && win.Content is FrameworkElement)
                {
                    current = ((FrameworkElement)win.Content).FindName(parts[0]);
                }
                if (current == null)
                {
                    var ns = NameScope.GetNameScope(win);
                    if (ns != null)
                    {
                        current = ns.FindName(parts[0]);
                    }
                }
            }
        }
        if (current == null)
        {
            current = FindLogicalNodeDeep(win, parts[0]);
        }
        if (current == null && win != null)
        {
            WalkVisualTree(win, (DependencyObject d) =>
            {
                if (current != null) return;
                FrameworkElement fe = d as FrameworkElement;
                if (fe != null && fe.Name == parts[0])
                {
                    current = d;
                }
            });
        }

        if (current != null)
        {
            for (int i = 1; i < parts.Length; i++)
            {
                string segment = parts[i];
                if (current is ItemsControl)
                {
                    ItemsControl ic = (ItemsControl)current;
                    object found = null;
                    foreach (var item in ic.Items)
                    {
                        if (item is HeaderedItemsControl)
                        {
                            var hic = (HeaderedItemsControl)item;
                            string headerStr = hic.Header != null ? hic.Header.ToString() : "";
                            if (headerStr.Contains("(" + segment + ")") || headerStr == segment || hic.Name == segment || (hic.Tag != null && hic.Tag.ToString() == segment))
                            {
                                found = hic;
                                break;
                            }
                        }
                        else if (item is FrameworkElement)
                        {
                            var fe = (FrameworkElement)item;
                            if (fe.Name == segment || (fe.Tag != null && fe.Tag.ToString() == segment))
                            {
                                found = fe;
                                break;
                            }
                        }
                    }
                    if (found != null)
                    {
                        current = found;
                    }
                    else
                    {
                        current = null;
                    }
                }
                else if (current is DependencyObject)
                {
                    object found = null;
                    WalkVisualTree((DependencyObject)current, (DependencyObject d) =>
                    {
                        if (found != null) return;
                        FrameworkElement fe = d as FrameworkElement;
                        if (fe != null && (fe.Name == segment || (fe.Tag != null && fe.Tag.ToString() == segment)))
                        {
                            found = fe;
                        }
                    });
                    if (found != null)
                    {
                        current = found;
                    }
                    else
                    {
                        current = null;
                    }
                }
                else
                {
                    current = null;
                }
                if (current == null) break;
            }
        }
        _controlCache[path] = current;
        return current;
    }

    // Canvas drag infrastructure: enables real-time C#-side mouse tracking that sends events to AHK
    private System.Collections.Generic.Dictionary<string, double> nodeGridSizes = new System.Collections.Generic.Dictionary<string, double>();
    private System.Collections.Generic.Dictionary<FrameworkElement, bool> dragEnabled = new System.Collections.Generic.Dictionary<FrameworkElement, bool>();

    private void EnableCanvasDrag(FrameworkElement ctrl, string ctrlName, string mode)
    {
        if (mode == "crop")
        {
            EnableCropDrag(ctrl, ctrlName);
            return;
        }

        double gridSize = 1;
        if (mode.StartsWith("grid=")) double.TryParse(mode.Substring(5), out gridSize);
        if (gridSize < 1) gridSize = 1;

        nodeGridSizes[ctrlName] = gridSize;
        if (dragEnabled.ContainsKey(ctrl) && dragEnabled[ctrl]) return;
        dragEnabled[ctrl] = true;

        bool isDragging = false;
        Point dragStart = new Point();
        double startLeft = 0, startTop = 0;
        DateTime lastSend = DateTime.MinValue;

        ctrl.MouseLeftButtonDown += (s, e) =>
        {
            isDragging = true;
            dragStart = e.GetPosition((UIElement)ctrl.Parent);
            startLeft = Canvas.GetLeft(ctrl);
            startTop = Canvas.GetTop(ctrl);
            if (double.IsNaN(startLeft)) startLeft = 0;
            if (double.IsNaN(startTop)) startTop = 0;
            System.Windows.Controls.Panel.SetZIndex(ctrl, 999);

            bool isCtrl = System.Windows.Input.Keyboard.Modifiers.HasFlag(System.Windows.Input.ModifierKeys.Control);
            string evName = isCtrl ? "CtrlSelectNode" : "SelectNode";
            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|" + evName + "|\n");

            ctrl.CaptureMouse();
            e.Handled = true;
        };
        ctrl.MouseMove += (s, e) =>
        {
            if (!isDragging) return;
            var pos = e.GetPosition((UIElement)ctrl.Parent);
            double dx = pos.X - dragStart.X;
            double dy = pos.Y - dragStart.Y;
            double newLeft = startLeft + dx;
            double newTop = startTop + dy;

            double currentGridSize = nodeGridSizes.ContainsKey(ctrlName) ? nodeGridSizes[ctrlName] : 1;
            if (currentGridSize > 1)
            {
                newLeft = Math.Round(newLeft / currentGridSize) * currentGridSize;
                newTop = Math.Round(newTop / currentGridSize) * currentGridSize;
            }

            Canvas.SetLeft(ctrl, newLeft);
            Canvas.SetTop(ctrl, newTop);
            // Throttle event sends to every 50ms
            if ((DateTime.Now - lastSend).TotalMilliseconds > 50)
            {
                lastSend = DateTime.Now;
                SendToAhk("EVENT|" + winId + "|" + ctrlName + "|DragMove|" +
                    LengthPrefix(newLeft.ToString("F0") + "," + newTop.ToString("F0")) + "\n");
            }
            e.Handled = true;
        };
        ctrl.MouseLeftButtonUp += (s, e) =>
        {
            if (!isDragging) return;
            isDragging = false;
            System.Windows.Controls.Panel.SetZIndex(ctrl, 0);
            ctrl.ReleaseMouseCapture();
            // Send final position
            double finalLeft = Canvas.GetLeft(ctrl);
            double finalTop = Canvas.GetTop(ctrl);
            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|DragMove|" +
                LengthPrefix(finalLeft.ToString("F0") + "," + finalTop.ToString("F0")) + "\n");
            DumpState(ctrlName, "DragEnd");
            e.Handled = true;
        };
    }

    private static void HideReaderToolbar(FlowDocumentReader reader)
    {
        if (reader == null) return;
        try
        {
            reader.ApplyTemplate();
            DependencyObject contentHost = FindVisualChildByName(reader, "PART_ContentHost");
            if (contentHost != null)
            {
                DependencyObject current = contentHost;
                DependencyObject childOfReader = null;
                while (current != null && current != reader)
                {
                    childOfReader = current;
                    current = VisualTreeHelper.GetParent(current);
                }

                int childCount = VisualTreeHelper.GetChildrenCount(reader);
                for (int i = 0; i < childCount; i++)
                {
                    var child = VisualTreeHelper.GetChild(reader, i) as FrameworkElement;
                    if (child != null && child != childOfReader)
                    {
                        child.Visibility = Visibility.Collapsed;
                    }
                }

                if (childOfReader != null)
                {
                    current = contentHost;
                    DependencyObject childOfRoot = null;
                    while (current != null && current != childOfReader)
                    {
                        childOfRoot = current;
                        current = VisualTreeHelper.GetParent(current);
                    }

                    int rootChildCount = VisualTreeHelper.GetChildrenCount(childOfReader);
                    for (int i = 0; i < rootChildCount; i++)
                    {
                        var child = VisualTreeHelper.GetChild(childOfReader, i) as FrameworkElement;
                        if (child != null && child != childOfRoot)
                        {
                            child.Visibility = Visibility.Collapsed;
                        }
                    }
                }
            }
            else
            {
                HideAllToolBarsRecursive(reader);
            }
        }
        catch (Exception ex)
        {
            System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log"), 
                "HideReaderToolbar Exception: " + ex.ToString() + "\n");
        }
    }

    private static DependencyObject FindVisualChildByName(DependencyObject parent, string name)
    {
        if (parent == null) return null;
        int count = VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is FrameworkElement)
            {
                var fe = (FrameworkElement)child;
                if (fe.Name == name) return child;
            }
            var found = FindVisualChildByName(child, name);
            if (found != null) return found;
        }
        return null;
    }

    private static void HideAllToolBarsRecursive(DependencyObject obj)
    {
        if (obj == null) return;
        if (obj is System.Windows.Controls.ToolBar)
        {
            var tb = (System.Windows.Controls.ToolBar)obj;
            tb.Visibility = Visibility.Collapsed;
        }
        int count = VisualTreeHelper.GetChildrenCount(obj);
        for (int i = 0; i < count; i++)
        {
            HideAllToolBarsRecursive(VisualTreeHelper.GetChild(obj, i));
        }
    }

    private static void UpdatePageStatus(FlowDocumentReader reader, Window win)
    {
        try {
            string rtbName = reader.Name.Replace("_PageReader", "");
            var pageTxt = win.FindName(rtbName + "_PageNumberText") as TextBlock;
            var btnPrev = win.FindName(rtbName + "_BtnPrevPage") as Button;
            var btnNext = win.FindName(rtbName + "_BtnNextPage") as Button;
            
            if (pageTxt != null)
            {
                pageTxt.Text = "Page " + reader.PageNumber + " of " + reader.PageCount;
            }
            if (btnPrev != null)
            {
                btnPrev.IsEnabled = reader.CanGoToPreviousPage;
            }
            if (btnNext != null)
            {
                btnNext.IsEnabled = reader.CanGoToNextPage;
            }
        } catch {}
    }

    private static void StyleReaderVisuals(FlowDocumentReader reader, string theme, Window win)
    {
        if (reader == null) return;

        // 1. Generate and inject XAML resource styles
        try {
            string xaml = GetReaderStylesXaml(theme, win);
            var resDict = (ResourceDictionary)System.Windows.Markup.XamlReader.Parse(xaml);
            
            // Merge or replace reader's resources
            reader.Resources.MergedDictionaries.Clear();
            reader.Resources.MergedDictionaries.Add(resDict);
        }
        catch (Exception ex) {
            System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log"), 
                "StyleReaderVisuals XAML Parse Exception: " + ex.ToString() + "\n");
        }

        // 2. Explicitly walk the visual tree and force property overrides for maximum robustness
        try {
            reader.ApplyTemplate();
            StyleVisualTreeRecursive(reader, theme, win);
        }
        catch (Exception ex) {
            System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log"), 
                "StyleReaderVisuals VisualTree Walk Exception: " + ex.ToString() + "\n");
        }
    }

    private static string GetReaderStylesXaml(string theme, Window win)
    {
        string tbBg = "Transparent";
        string borderBrush = "Transparent";
        string textMain = "Black";
        string controlBg = "White";
        string accent = "#005CBA";
        string hoverBg = "#15000000";
        string activeBg = "#25000000";

        if (theme == "Dark")
        {
            tbBg = "#252526";
            borderBrush = "#3F3F46";
            textMain = "#E0E0E0";
            controlBg = "#2D2D2D";
            accent = "#007ACC";
            hoverBg = "#15FFFFFF";
            activeBg = "#25FFFFFF";
        }
        else if (theme == "Theme")
        {
            tbBg = "{DynamicResource SidebarColor}";
            borderBrush = "{DynamicResource ControlBorder}";
            textMain = "{DynamicResource TextMain}";
            controlBg = "{DynamicResource ControlBg}";
            accent = "{DynamicResource Accent}";
            
            bool isDark = true;
            try {
                var textBrush = win.TryFindResource("TextMain") as SolidColorBrush;
                if (textBrush != null)
                {
                    var c = textBrush.Color;
                    double brightness = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) / 255.0;
                    isDark = brightness > 0.5;
                }
            } catch {}
            hoverBg = isDark ? "#15FFFFFF" : "#15000000";
            activeBg = isDark ? "#25FFFFFF" : "#25000000";
        }
        else // Normal
        {
            tbBg = "#F3F3F3";
            borderBrush = "#E0E0E0";
            textMain = "#333333";
            controlBg = "#FFFFFF";
            accent = "#005CBA";
            hoverBg = "#15000000";
            activeBg = "#25000000";
        }

        string xaml = @"
<ResourceDictionary xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                    xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml"">
    <Style TargetType=""ToolBar"">
        <Setter Property=""Background"" Value=""" + tbBg + @""" />
        <Setter Property=""BorderBrush"" Value=""" + borderBrush + @""" />
        <Setter Property=""BorderThickness"" Value=""0,1,0,0"" />
    </Style>
    
    <Style TargetType=""TextBlock"">
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""FontFamily"" Value=""Segoe UI"" />
        <Setter Property=""FontSize"" Value=""12"" />
    </Style>

    <Style TargetType=""TextBox"">
        <Setter Property=""Background"" Value=""" + controlBg + @""" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderBrush"" Value=""" + borderBrush + @""" />
        <Setter Property=""BorderThickness"" Value=""1"" />
        <Setter Property=""Padding"" Value=""4,2"" />
        <Setter Property=""SelectionBrush"" Value=""" + accent + @""" />
    </Style>

    <Style TargetType=""Button"">
        <Setter Property=""Background"" Value=""Transparent"" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderThickness"" Value=""0"" />
        <Setter Property=""Padding"" Value=""6,4"" />
        <Setter Property=""Margin"" Value=""2,0"" />
        <Setter Property=""Cursor"" Value=""Hand"" />
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""Button"">
                    <Border x:Name=""bg"" Background=""{TemplateBinding Background}"" CornerRadius=""4"" BorderThickness=""0"" Padding=""{TemplateBinding Padding}"">
                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsMouseOver"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + hoverBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Opacity"" Value=""0.4"" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType=""ToggleButton"">
        <Setter Property=""Background"" Value=""Transparent"" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderThickness"" Value=""0"" />
        <Setter Property=""Padding"" Value=""6,4"" />
        <Setter Property=""Margin"" Value=""2,0"" />
        <Setter Property=""Cursor"" Value=""Hand"" />
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""ToggleButton"">
                    <Border x:Name=""bg"" Background=""{TemplateBinding Background}"" CornerRadius=""4"" BorderThickness=""0"" Padding=""{TemplateBinding Padding}"">
                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsMouseOver"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + hoverBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsChecked"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + activeBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Opacity"" Value=""0.4"" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    
    <Style TargetType=""RepeatButton"">
        <Setter Property=""Background"" Value=""Transparent"" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderThickness"" Value=""0"" />
        <Setter Property=""Padding"" Value=""6,4"" />
        <Setter Property=""Margin"" Value=""2,0"" />
        <Setter Property=""Cursor"" Value=""Hand"" />
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""RepeatButton"">
                    <Border x:Name=""bg"" Background=""{TemplateBinding Background}"" CornerRadius=""4"" BorderThickness=""0"" Padding=""{TemplateBinding Padding}"">
                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsMouseOver"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + hoverBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Opacity"" Value=""0.4"" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>";

        return xaml;
    }

    private static void StyleVisualTreeRecursive(DependencyObject obj, string theme, Window win)
    {
        if (obj == null) return;

        // Skip children of PART_ContentHost (the document pages)
        FrameworkElement fe = obj as FrameworkElement;
        if (fe != null && fe.Name == "PART_ContentHost")
        {
            return;
        }

        // Explicitly apply themes to elements
        System.Windows.Controls.Border border = obj as System.Windows.Controls.Border;
        if (border != null)
        {
            if (border.TemplatedParent == null || border.TemplatedParent is FlowDocumentReader)
            {
                if (theme == "Dark")
                {
                    border.Background = new SolidColorBrush(Color.FromRgb(37, 37, 38));
                    border.BorderBrush = new SolidColorBrush(Color.FromRgb(63, 63, 70));
                }
                else if (theme == "Theme")
                {
                    border.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "SidebarColor");
                    border.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, "ControlBorder");
                }
                else
                {
                    border.Background = new SolidColorBrush(Color.FromRgb(243, 243, 243));
                    border.BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                }
            }
        }
        else {
            System.Windows.Controls.ToolBar toolbar = obj as System.Windows.Controls.ToolBar;
            if (toolbar != null)
            {
                if (theme == "Dark")
                {
                    toolbar.Background = new SolidColorBrush(Color.FromRgb(37, 37, 38));
                    toolbar.BorderBrush = new SolidColorBrush(Color.FromRgb(63, 63, 70));
                }
                else if (theme == "Theme")
                {
                    toolbar.SetResourceReference(System.Windows.Controls.ToolBar.BackgroundProperty, "SidebarColor");
                    toolbar.SetResourceReference(System.Windows.Controls.ToolBar.BorderBrushProperty, "ControlBorder");
                }
                else
                {
                    toolbar.Background = new SolidColorBrush(Color.FromRgb(243, 243, 243));
                    toolbar.BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                }
            }
            else {
                System.Windows.Controls.Button btn = obj as System.Windows.Controls.Button;
                if (btn != null)
                {
                    if (theme == "Dark")
                    {
                        btn.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                    }
                    else if (theme == "Theme")
                    {
                        btn.SetResourceReference(System.Windows.Controls.Button.ForegroundProperty, "TextMain");
                    }
                    else
                    {
                        btn.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                    }
                }
                else {
                    System.Windows.Controls.Primitives.ToggleButton toggleBtn = obj as System.Windows.Controls.Primitives.ToggleButton;
                    if (toggleBtn != null)
                    {
                        if (theme == "Dark")
                        {
                            toggleBtn.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                        }
                        else if (theme == "Theme")
                        {
                            toggleBtn.SetResourceReference(System.Windows.Controls.Primitives.ToggleButton.ForegroundProperty, "TextMain");
                        }
                        else
                        {
                            toggleBtn.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                        }
                    }
                    else {
                        System.Windows.Controls.Primitives.RepeatButton repeatBtn = obj as System.Windows.Controls.Primitives.RepeatButton;
                        if (repeatBtn != null)
                        {
                            if (theme == "Dark")
                            {
                                repeatBtn.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                            }
                            else if (theme == "Theme")
                            {
                                repeatBtn.SetResourceReference(System.Windows.Controls.Primitives.RepeatButton.ForegroundProperty, "TextMain");
                            }
                            else
                            {
                                repeatBtn.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                            }
                        }
                        else {
                            System.Windows.Controls.TextBlock textBlock = obj as System.Windows.Controls.TextBlock;
                            if (textBlock != null)
                            {
                                if (theme == "Dark")
                                {
                                    textBlock.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                                }
                                else if (theme == "Theme")
                                {
                                    textBlock.SetResourceReference(System.Windows.Controls.TextBlock.ForegroundProperty, "TextMain");
                                }
                                else
                               {
                                    textBlock.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                                }
                            }
                            else {
                                System.Windows.Controls.TextBox textBox = obj as System.Windows.Controls.TextBox;
                                if (textBox != null)
                                {
                                    if (theme == "Dark")
                                    {
                                        textBox.Background = new SolidColorBrush(Color.FromRgb(45, 45, 45));
                                        textBox.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                                        textBox.BorderBrush = new SolidColorBrush(Color.FromRgb(63, 63, 70));
                                    }
                                    else if (theme == "Theme")
                                    {
                                        textBox.SetResourceReference(System.Windows.Controls.TextBox.BackgroundProperty, "ControlBg");
                                        textBox.SetResourceReference(System.Windows.Controls.TextBox.ForegroundProperty, "TextMain");
                                        textBox.SetResourceReference(System.Windows.Controls.TextBox.BorderBrushProperty, "ControlBorder");
                                    }
                                    else
                                    {
                                        textBox.Background = new SolidColorBrush(Color.FromRgb(255, 255, 255));
                                        textBox.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                                        textBox.BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Traverse children
        int count = VisualTreeHelper.GetChildrenCount(obj);
        for (int i = 0; i < count; i++)
        {
            StyleVisualTreeRecursive(VisualTreeHelper.GetChild(obj, i), theme, win);
        }
    }

    private void EnableElementDrag(FrameworkElement element, string options)
    {
        if (element.Tag != null && element.Tag.ToString() == "DragEnabled") return;
        element.Tag = "DragEnabled";

        bool snapToGrid = options.Contains("grid");
        bool boxDragging = false;
        Point boxDragStart = new Point();
        double boxStartLeft = 0, boxStartTop = 0;

        element.MouseLeftButtonDown += (s, e) =>
        {
            boxDragging = true;
            boxDragStart = e.GetPosition((UIElement)element.Parent);
            boxStartLeft = Canvas.GetLeft(element);
            boxStartTop = Canvas.GetTop(element);
            if (double.IsNaN(boxStartLeft)) boxStartLeft = 0;
            if (double.IsNaN(boxStartTop)) boxStartTop = 0;
            element.CaptureMouse();
            e.Handled = true;
        };
        element.MouseMove += (s, e) =>
        {
            if (!boxDragging) return;
            var pos = e.GetPosition((UIElement)element.Parent);
            double newX = boxStartLeft + (pos.X - boxDragStart.X);
            double newY = boxStartTop + (pos.Y - boxDragStart.Y);
            if (snapToGrid)
            {
                newX = Math.Round(newX / 10) * 10;
                newY = Math.Round(newY / 10) * 10;
            }
            Canvas.SetLeft(element, newX);
            Canvas.SetTop(element, newY);
            e.Handled = true;
        };
        element.MouseLeftButtonUp += (s, e) =>
        {
            if (!boxDragging) return;
            boxDragging = false;
            element.ReleaseMouseCapture();
            e.Handled = true;
        };
    }

    private void EnableCropDrag(FrameworkElement box, string boxName)
    {
        bool boxDragging = false;
        Point boxDragStart = new Point();
        double boxStartLeft = 0, boxStartTop = 0;

        box.MouseLeftButtonDown += (s, e) =>
        {
            boxDragging = true;
            boxDragStart = e.GetPosition((UIElement)box.Parent);
            boxStartLeft = Canvas.GetLeft(box);
            boxStartTop = Canvas.GetTop(box);
            if (double.IsNaN(boxStartLeft)) boxStartLeft = 0;
            if (double.IsNaN(boxStartTop)) boxStartTop = 0;
            box.CaptureMouse();
            e.Handled = true;
        };
        box.MouseMove += (s, e) =>
        {
            if (!boxDragging) return;
            var pos = e.GetPosition((UIElement)box.Parent);
            Canvas.SetLeft(box, boxStartLeft + (pos.X - boxDragStart.X));
            Canvas.SetTop(box, boxStartTop + (pos.Y - boxDragStart.Y));
            e.Handled = true;
        };
        box.MouseLeftButtonUp += (s, e) =>
        {
            if (!boxDragging) return;
            boxDragging = false;
            box.ReleaseMouseCapture();
            e.Handled = true;
        };

        string baseName = boxName.Replace("_Box", "");
        var hSE = win.FindName(baseName + "_HSE") as FrameworkElement;
        if (hSE != null)
        {
            bool seResizing = false;
            Point seStart = new Point();
            double seStartW = 0, seStartH = 0;

            hSE.MouseLeftButtonDown += (s, e) =>
            {
                seResizing = true;
                seStart = e.GetPosition((UIElement)box.Parent);
                seStartW = box.Width;
                seStartH = box.Height;
                if (double.IsNaN(seStartW)) seStartW = 100;
                if (double.IsNaN(seStartH)) seStartH = 100;
                hSE.CaptureMouse();
                e.Handled = true;
            };
            hSE.MouseMove += (s, e) =>
            {
                if (!seResizing) return;
                var pos = e.GetPosition((UIElement)box.Parent);
                double nw = Math.Max(50, seStartW + (pos.X - seStart.X));
                double nh = Math.Max(50, seStartH + (pos.Y - seStart.Y));
                box.Width = nw;
                box.Height = nh;
                e.Handled = true;
            };
            hSE.MouseLeftButtonUp += (s, e) =>
            {
                if (!seResizing) return;
                seResizing = false;
                hSE.ReleaseMouseCapture();
                e.Handled = true;
            };
        }

        var hNW = win.FindName(baseName + "_HNW") as FrameworkElement;
        if (hNW != null)
        {
            bool nwResizing = false;
            Point nwStart = new Point();
            double nwStartL = 0, nwStartT = 0, nwStartW = 0, nwStartH = 0;

            hNW.MouseLeftButtonDown += (s, e) =>
            {
                nwResizing = true;
                nwStart = e.GetPosition((UIElement)box.Parent);
                nwStartL = Canvas.GetLeft(box);
                nwStartT = Canvas.GetTop(box);
                nwStartW = box.Width;
                nwStartH = box.Height;
                if (double.IsNaN(nwStartL)) nwStartL = 0;
                if (double.IsNaN(nwStartT)) nwStartT = 0;
                if (double.IsNaN(nwStartW)) nwStartW = 100;
                if (double.IsNaN(nwStartH)) nwStartH = 100;
                hNW.CaptureMouse();
                e.Handled = true;
            };
            hNW.MouseMove += (s, e) =>
            {
                if (!nwResizing) return;
                var pos = e.GetPosition((UIElement)box.Parent);
                double dx = pos.X - nwStart.X;
                double dy = pos.Y - nwStart.Y;
                double nw = Math.Max(50, nwStartW - dx);
                double nh = Math.Max(50, nwStartH - dy);
                if (nw > 50) { Canvas.SetLeft(box, nwStartL + dx); box.Width = nw; }
                if (nh > 50) { Canvas.SetTop(box, nwStartT + dy); box.Height = nh; }
                e.Handled = true;
            };
            hNW.MouseLeftButtonUp += (s, e) =>
            {
                if (!nwResizing) return;
                nwResizing = false;
                hNW.ReleaseMouseCapture();
                e.Handled = true;
            };
        }
    }

    private void EnableCanvasZoomPan(Canvas canvas)
    {
        if (canvas.Tag != null && canvas.Tag.ToString() == "ZoomPanEnabled") return;
        canvas.Tag = "ZoomPanEnabled";

        var scaleTransform = new System.Windows.Media.ScaleTransform(1, 1);
        var translateTransform = new System.Windows.Media.TranslateTransform(0, 0);
        var tg = new System.Windows.Media.TransformGroup();
        tg.Children.Add(scaleTransform);
        tg.Children.Add(translateTransform);
        canvas.RenderTransform = tg;
        canvas.RenderTransformOrigin = new Point(0, 0);

        var parent = canvas.Parent as FrameworkElement;

        canvas.PreviewMouseWheel += (s, e) =>
        {
            //System.IO.File.AppendAllText("ahk_pan_debug.log", "PreviewMouseWheel fired! Delta: " + e.Delta + "\n");
            double zoom = e.Delta > 0 ? 1.1 : 0.9;
            double scaleX = scaleTransform.ScaleX;
            double newScale = scaleX * zoom;
            if (newScale < 0.2) newScale = 0.2;
            if (newScale > 5.0) newScale = 5.0;

            var canvasPos = e.GetPosition(canvas);
            translateTransform.X = translateTransform.X + canvasPos.X * (scaleX - newScale);
            translateTransform.Y = translateTransform.Y + canvasPos.Y * (scaleX - newScale);

            scaleTransform.ScaleX = newScale;
            scaleTransform.ScaleY = newScale;
            e.Handled = true;
        };

        bool isPanning = false;
        bool panMoved = false;
        Point panStart = new Point();
        double panStartTX = 0, panStartTY = 0;

        bool isKnifing = false;
        System.Windows.Shapes.Path tempKnife = null;
        Point knifeStart = new Point();
        Point lastKnifePos = new Point();
        string lastSelectionSet = "";

        canvas.PreviewMouseDown += (s, e) =>
        {
            if (e.ChangedButton == System.Windows.Input.MouseButton.Middle)
            {
                //System.IO.File.AppendAllText("ahk_pan_debug.log", "Middle PreviewMouseDown fired! Starting pan.\n");
                isPanning = true;
                panMoved = false;
                panStart = e.GetPosition(parent != null ? parent : canvas);
                panStartTX = translateTransform.X;
                panStartTY = translateTransform.Y;
                canvas.CaptureMouse();
                canvas.Cursor = System.Windows.Input.Cursors.Hand;
                e.Handled = true;
            }
        };

        canvas.PreviewMouseRightButtonDown += (s, e) =>
        {
            var pos = e.GetPosition(canvas);
            string coords = pos.X.ToString(System.Globalization.CultureInfo.InvariantCulture) + "," + pos.Y.ToString(System.Globalization.CultureInfo.InvariantCulture);
            SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|ContextMenuOpened|" + LengthPrefix(coords) + "\n");
        };

        // Mode logic: Left click on empty space (Canvas) triggers Pan or Select
        canvas.MouseLeftButtonDown += (s, e) =>
        {
            var el = e.OriginalSource as FrameworkElement;
            if (el != null && el.Name != null && el.Name.StartsWith("Port_"))
            {
                connectionSourcePort = el;
                if (tempConnection == null)
                {
                    tempConnection = new System.Windows.Shapes.Path
                    {
                        Stroke = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(96, 160, 255)),
                        StrokeThickness = 2.5,
                        Opacity = 0.8,
                        IsHitTestVisible = false
                    };
                    System.Windows.Controls.Panel.SetZIndex(tempConnection, -1);
                    canvas.Children.Add(tempConnection);
                }
                tempConnection.Visibility = Visibility.Visible;
                canvas.CaptureMouse();
                e.Handled = true;
                return;
            }

            // If the user clicked on a node or anything else, let it handle its own drag
            if (e.OriginalSource != canvas) return;

            string mode = "Pan";
            if (canvasModes.ContainsKey(canvas.Name)) mode = canvasModes[canvas.Name];
            //System.IO.File.AppendAllText("ahk_pan_debug.log", "MouseLeftButtonDown fired! Mode: " + mode + "\n");

            if (mode == "Pan")
            {
                isPanning = true;
                panMoved = false;
                panStart = e.GetPosition(parent != null ? parent : canvas);
                panStartTX = translateTransform.X;
                panStartTY = translateTransform.Y;
                canvas.CaptureMouse();
                canvas.Cursor = System.Windows.Input.Cursors.Hand;
                e.Handled = true;
            }
            else if (mode == "Select")
            {
                selectionStart = e.GetPosition(canvas);
                if (selectionBox == null)
                {
                    selectionBox = new System.Windows.Shapes.Rectangle
                    {
                        Stroke = System.Windows.Media.Brushes.DodgerBlue,
                        StrokeThickness = 1,
                        Fill = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(50, 30, 144, 255)),
                        IsHitTestVisible = false
                    };
                    System.Windows.Controls.Panel.SetZIndex(selectionBox, 9999);
                    canvas.Children.Add(selectionBox);
                }
                Canvas.SetLeft(selectionBox, selectionStart.X);
                Canvas.SetTop(selectionBox, selectionStart.Y);
                selectionBox.Width = 0;
                selectionBox.Height = 0;
                selectionBox.Visibility = Visibility.Visible;
                lastSelectionSet = "FORCE_UPDATE";
                canvas.CaptureMouse();
                e.Handled = true;
            }
            else if (mode == "Knife")
            {
                isKnifing = true;
                knifeStart = e.GetPosition(canvas);
                lastKnifePos = knifeStart;
                if (tempKnife == null)
                {
                    tempKnife = new System.Windows.Shapes.Path
                    {
                        Stroke = System.Windows.Media.Brushes.Red,
                        StrokeThickness = 2,
                        StrokeDashArray = new System.Windows.Media.DoubleCollection(new double[] { 4, 4 }),
                        IsHitTestVisible = false
                    };
                    System.Windows.Controls.Panel.SetZIndex(tempKnife, 9999);
                    canvas.Children.Add(tempKnife);
                }
                tempKnife.Visibility = Visibility.Visible;
                canvas.CaptureMouse();
                e.Handled = true;
            }
        };
        canvas.MouseMove += (s, e) =>
        {
            if (isPanning)
            {
                var pos = e.GetPosition(parent != null ? parent : canvas);
                if (Math.Abs(pos.X - panStart.X) > 2 || Math.Abs(pos.Y - panStart.Y) > 2) panMoved = true;
                translateTransform.X = panStartTX + (pos.X - panStart.X);
                translateTransform.Y = panStartTY + (pos.Y - panStart.Y);
                //System.IO.File.AppendAllText("ahk_pan_debug.log", "Canvas Moved! New TX: " + translateTransform.X + " TY: " + translateTransform.Y + " parent: " + (parent != null ? parent.Name : "null") + "\n");
                e.Handled = true;
            }
            else if (selectionBox != null && selectionBox.Visibility == Visibility.Visible)
            {
                var pos = e.GetPosition(canvas);
                double x = Math.Min(pos.X, selectionStart.X);
                double y = Math.Min(pos.Y, selectionStart.Y);
                double w = Math.Abs(pos.X - selectionStart.X);
                double h = Math.Abs(pos.Y - selectionStart.Y);
                Canvas.SetLeft(selectionBox, x);
                Canvas.SetTop(selectionBox, y);
                selectionBox.Width = w;
                selectionBox.Height = h;

                var currentSelected = new System.Collections.Generic.List<string>();
                foreach (UIElement child in canvas.Children)
                {
                    var fe = child as FrameworkElement;
                    if (fe != null && fe.Name != null && fe.Name.StartsWith("Node_"))
                    {
                        double nx = Canvas.GetLeft(fe);
                        double ny = Canvas.GetTop(fe);
                        if (double.IsNaN(nx)) nx = 0;
                        if (double.IsNaN(ny)) ny = 0;
                        double nw = fe.ActualWidth;
                        double nh = fe.ActualHeight;
                        if (nx < x + w && nx + nw > x && ny < y + h && ny + nh > y)
                        {
                            currentSelected.Add(fe.Name.Substring(5));
                        }
                    }
                }
                string newSet = string.Join(",", currentSelected);
                if (newSet != lastSelectionSet)
                {
                    lastSelectionSet = newSet;
                    bool isCtrl = System.Windows.Input.Keyboard.Modifiers.HasFlag(System.Windows.Input.ModifierKeys.Control);
                    string evName = isCtrl ? "CtrlSelectionBox" : "SelectionBox";
                    SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|" + evName + "|" +
                        LengthPrefix(newSet) + "\n");
                }
                e.Handled = true;
            }
            else if (connectionSourcePort != null && tempConnection != null && tempConnection.Visibility == Visibility.Visible)
            {
                var pos = e.GetPosition(canvas);
                double startX = Canvas.GetLeft(connectionSourcePort) + connectionSourcePort.Width / 2;
                double startY = Canvas.GetTop(connectionSourcePort) + connectionSourcePort.Height / 2;
                if (double.IsNaN(startX)) startX = 0;
                if (double.IsNaN(startY)) startY = 0;
                double endX = pos.X;
                double endY = pos.Y;

                // Allow dragging from out port to in port
                double dx = Math.Max(40, Math.Abs(endX - startX) * 0.5);
                double c1X = startX + dx;
                double c2X = endX - dx;
                if (connectionSourcePort.Name.StartsWith("Port_In"))
                {
                    c1X = startX - dx;
                    c2X = endX + dx;
                }

                string geom = string.Format(System.Globalization.CultureInfo.InvariantCulture, "M{0},{1} C{2},{3} {4},{5} {6},{7}", startX, startY, c1X, startY, c2X, endY, endX, endY);
                try { tempConnection.Data = System.Windows.Media.Geometry.Parse(geom); } catch { }
                e.Handled = true;
            }
            else if (isKnifing && tempKnife != null && tempKnife.Visibility == Visibility.Visible)
            {
                var pos = e.GetPosition(canvas);
                string geom = string.Format(System.Globalization.CultureInfo.InvariantCulture, "M{0},{1} L{2},{3}", knifeStart.X, knifeStart.Y, pos.X, pos.Y);
                try { tempKnife.Data = System.Windows.Media.Geometry.Parse(geom); } catch { }

                System.Windows.Media.VisualTreeHelper.HitTest(canvas, null,
                    new System.Windows.Media.HitTestResultCallback((result) =>
                    {
                        var hitEl = result.VisualHit as FrameworkElement;
                        if (hitEl != null && hitEl.Name != null && hitEl.Name.Contains("_Path_") && hitEl.Visibility == Visibility.Visible)
                        {
                            hitEl.Visibility = Visibility.Collapsed;
                            SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|DeleteConnection|" +
                                LengthPrefix(hitEl.Name) + "\n");
                        }
                        return System.Windows.Media.HitTestResultBehavior.Continue;
                    }),
                    new System.Windows.Media.GeometryHitTestParameters(new System.Windows.Media.LineGeometry(lastKnifePos, pos))
                );
                lastKnifePos = pos;
                e.Handled = true;
            }
        };
        canvas.MouseUp += (s, e) =>
        {
            if (e.ChangedButton == System.Windows.Input.MouseButton.Middle && isPanning)
            {
                isPanning = false;
                canvas.ReleaseMouseCapture();
                canvas.Cursor = System.Windows.Input.Cursors.Arrow;
                e.Handled = true;
            }
        };
        canvas.MouseLeftButtonUp += (s, e) =>
        {
            if (isPanning)
            {
                isPanning = false;
                canvas.ReleaseMouseCapture();
                canvas.Cursor = System.Windows.Input.Cursors.Arrow;
                if (!panMoved)
                {
                    SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|ClearSelection|\n");
                }
                e.Handled = true;
            }
            else if (selectionBox != null && selectionBox.Visibility == Visibility.Visible)
            {
                selectionBox.Visibility = Visibility.Collapsed;
                canvas.ReleaseMouseCapture();
                if (lastSelectionSet == "FORCE_UPDATE")
                {
                    SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|ClearSelection|\n");
                }
                lastSelectionSet = "";
                e.Handled = true;
            }
            else if (connectionSourcePort != null && tempConnection != null && tempConnection.Visibility == Visibility.Visible)
            {
                tempConnection.Visibility = Visibility.Collapsed;
                canvas.ReleaseMouseCapture();
                Point dropPos = e.GetPosition(canvas);

                // Magnetic search for closest port
                FrameworkElement closestPort = null;
                double minDistance = 2500; // 50^2 for generous port snapping

                // First pass: check if dropped directly inside a Node body
                FrameworkElement targetNode = null;
                foreach (UIElement child in canvas.Children)
                {
                    var fe = child as FrameworkElement;
                    if (fe != null && fe.Name != null && fe.Name.StartsWith("Node_"))
                    {
                        double nx = Canvas.GetLeft(fe);
                        double ny = Canvas.GetTop(fe);
                        if (double.IsNaN(nx) || double.IsNaN(ny)) continue;
                        if (dropPos.X >= nx && dropPos.X <= nx + fe.ActualWidth &&
                            dropPos.Y >= ny && dropPos.Y <= ny + fe.ActualHeight)
                        {
                            targetNode = fe;
                            break;
                        }
                    }
                }

                if (targetNode != null)
                {
                    // Extract node ID and find its complementary port
                    string nodeId = targetNode.Name.Substring(5);
                    string expectedPortName = connectionSourcePort.Name.StartsWith("Port_Out") ? "Port_In_" + nodeId : "Port_Out_" + nodeId;
                    foreach (UIElement child in canvas.Children)
                    {
                        var fe = child as FrameworkElement;
                        if (fe != null && fe.Name == expectedPortName)
                        {
                            closestPort = fe;
                            break;
                        }
                    }
                }

                // Second pass: if no direct node hit, do proximity search for ports
                if (closestPort == null)
                {
                    foreach (UIElement child in canvas.Children)
                    {
                        var fe = child as FrameworkElement;
                        if (fe != null && fe.Name != null && fe.Name.StartsWith("Port_") && fe != connectionSourcePort)
                        {
                            double px = Canvas.GetLeft(fe) + fe.Width / 2;
                            double py = Canvas.GetTop(fe) + fe.Height / 2;
                            if (double.IsNaN(px) || double.IsNaN(py)) continue;

                            double distSq = (dropPos.X - px) * (dropPos.X - px) + (dropPos.Y - py) * (dropPos.Y - py);
                            if (distSq < minDistance)
                            {
                                minDistance = distSq;
                                closestPort = fe;
                            }
                        }
                    }
                }

                if (closestPort != null)
                {
                    SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|ConnectPorts|" +
                        LengthPrefix(connectionSourcePort.Name + "," + closestPort.Name) + "\n");
                }
                connectionSourcePort = null;
                e.Handled = true;
            }
            else if (isKnifing && tempKnife != null && tempKnife.Visibility == Visibility.Visible)
            {
                tempKnife.Visibility = Visibility.Collapsed;
                isKnifing = false;
                canvas.ReleaseMouseCapture();
                e.Handled = true;
            }
            else
            {
                // Clicked empty space
                SendToAhk("EVENT|" + winId + "|" + canvas.Name + "|ClearSelection|\n");
            }
        };
    }

    private void ZoomAllCanvas(Canvas canvas)
    {
        var tg = canvas.RenderTransform as System.Windows.Media.TransformGroup;
        if (tg != null && tg.Children.Count >= 2)
        {
            var scaleTransform = tg.Children[0] as System.Windows.Media.ScaleTransform;
            var translateTransform = tg.Children[1] as System.Windows.Media.TranslateTransform;

            if (scaleTransform != null && translateTransform != null)
            {
                double minX = double.MaxValue, minY = double.MaxValue;
                double maxX = double.MinValue, maxY = double.MinValue;

                foreach (UIElement child in canvas.Children)
                {
                    var fe = child as FrameworkElement;
                    if (fe == null || fe.Name == null || !fe.Name.StartsWith("Node_")) continue;

                    double left = Canvas.GetLeft(child);
                    double top = Canvas.GetTop(child);
                    if (double.IsNaN(left)) left = 0;
                    if (double.IsNaN(top)) top = 0;

                    if (fe.ActualWidth > 0 && fe.ActualHeight > 0)
                    {
                        minX = Math.Min(minX, left);
                        minY = Math.Min(minY, top);
                        maxX = Math.Max(maxX, left + fe.ActualWidth);
                        maxY = Math.Max(maxY, top + fe.ActualHeight);
                    }
                }

                if (minX <= maxX && minY <= maxY)
                {
                    double contentWidth = maxX - minX;
                    double contentHeight = maxY - minY;

                    var parent = canvas.Parent as FrameworkElement;
                    if (parent != null && parent.ActualWidth > 0 && parent.ActualHeight > 0)
                    {
                        double viewportWidth = parent.ActualWidth;
                        double viewportHeight = parent.ActualHeight;

                        // Add 250px total padding (125px per side)
                        double scaleX = viewportWidth / (contentWidth + 250);
                        double scaleY = viewportHeight / (contentHeight + 250);
                        double scale = Math.Min(scaleX, scaleY);
                        if (scale > 2.0) scale = 2.0;
                        if (scale < 0.2) scale = 0.2;

                        scaleTransform.CenterX = 0;
                        scaleTransform.CenterY = 0;
                        scaleTransform.ScaleX = scale;
                        scaleTransform.ScaleY = scale;

                        translateTransform.X = (viewportWidth - contentWidth * scale) / 2 - minX * scale - canvas.Margin.Left;
                        translateTransform.Y = (viewportHeight - contentHeight * scale) / 2 - minY * scale - canvas.Margin.Top;
                    }
                }
            }
        }
    }

    private void ZoomCanvas(Canvas canvas, double zoomFactor)
    {
        var tg = canvas.RenderTransform as System.Windows.Media.TransformGroup;
        if (tg != null && tg.Children.Count >= 2)
        {
            var scaleTransform = tg.Children[0] as System.Windows.Media.ScaleTransform;
            var translateTransform = tg.Children[1] as System.Windows.Media.TranslateTransform;

            if (scaleTransform != null && translateTransform != null)
            {
                var parent = canvas.Parent as FrameworkElement;
                if (parent != null)
                {
                    double centerX = parent.ActualWidth / 2;
                    double centerY = parent.ActualHeight / 2;
                    var parentCenter = new Point(centerX, centerY);
                    var canvasPos = parent.TranslatePoint(parentCenter, canvas);

                    double newScale = scaleTransform.ScaleX * zoomFactor;
                    if (newScale > 5.0) newScale = 5.0;
                    if (newScale < 0.1) newScale = 0.1;

                    double scaleX = scaleTransform.ScaleX;
                    translateTransform.X = translateTransform.X + canvasPos.X * (scaleX - newScale);
                    translateTransform.Y = translateTransform.Y + canvasPos.Y * (scaleX - newScale);

                    scaleTransform.ScaleX = newScale;
                    scaleTransform.ScaleY = newScale;
                }
            }
        }
    }

    // Generic drag-source: enables any element to be dragged with a custom payload
    // Usage from AHK: ui.Update("MyButton", "EnableDragSource", "DesignerComponent")
    // The drag payload will be the element's Tag property (if set), or its x:Name
    private System.Collections.Generic.Dictionary<UIElement, bool> dragSourceEnabled = new System.Collections.Generic.Dictionary<UIElement, bool>();

    private void EnableGenericDragSource(UIElement element, string ctrlName, string dataFormat)
    {
        if (dragSourceEnabled.ContainsKey(element) && dragSourceEnabled[element]) return;
        dragSourceEnabled[element] = true;

        Point dragStartPos = new Point();
        bool mouseDown = false;

        element.PreviewMouseLeftButtonDown += (s, e) =>
        {
            dragStartPos = e.GetPosition(null);
            mouseDown = true;
        };

        element.PreviewMouseLeftButtonUp += (s, e) =>
        {
            mouseDown = false;
        };

        element.PreviewMouseMove += (s, e) =>
        {
            if (!mouseDown || e.LeftButton != System.Windows.Input.MouseButtonState.Pressed)
            {
                mouseDown = false;
                return;
            }

            Point pos = e.GetPosition(null);
            if (Math.Abs(pos.X - dragStartPos.X) > SystemParameters.MinimumHorizontalDragDistance ||
                Math.Abs(pos.Y - dragStartPos.Y) > SystemParameters.MinimumVerticalDragDistance)
            {

                mouseDown = false;

                // Determine payload: use Tag if set, otherwise use control name
                string payload = ctrlName;
                var fe = element as FrameworkElement;
                if (fe != null && fe.Tag != null && fe.Tag.ToString() != "" && fe.Tag.ToString() != "DragEnabled")
                {
                    payload = fe.Tag.ToString();
                }

                DataObject dragData = new DataObject(dataFormat, payload);
                dragData.SetData("DragSourceName", ctrlName);

                try
                {
                    DragDrop.DoDragDrop(element, dragData, DragDropEffects.Copy | DragDropEffects.Move);
                }
                catch { }
            }
        };
    }

    // Generic drop-target: enables any element to accept drops and sends events to AHK
    // Usage from AHK: ui.Update("CanvasArea", "EnableDropTarget", "DesignerComponent")
    // Events sent: DragEnter (with payload), DragLeave, Drop (with payload + source name)
    private System.Collections.Generic.Dictionary<UIElement, bool> dropTargetEnabled = new System.Collections.Generic.Dictionary<UIElement, bool>();

    private void EnableGenericDropTarget(UIElement element, string ctrlName, string dataFormat)
    {
        if (dropTargetEnabled.ContainsKey(element) && dropTargetEnabled[element]) return;
        dropTargetEnabled[element] = true;

        element.AllowDrop = true;

        element.DragEnter += (s, e) =>
        {
            if (e.Data.GetDataPresent(dataFormat))
            {
                e.Effects = DragDropEffects.Copy;
                string payload = e.Data.GetData(dataFormat) as string ?? "";
                SendToAhk("EVENT|" + winId + "|" + ctrlName + "|DragEnter|" +
                    LengthPrefix(payload) + "\n");
            }
            else if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                e.Effects = DragDropEffects.Copy;
            }
            else
            {
                e.Effects = DragDropEffects.None;
            }
            e.Handled = true;
        };

        element.DragOver += (s, e) =>
        {
            if (e.Data.GetDataPresent(dataFormat) || e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                e.Effects = DragDropEffects.Copy;
            }
            else
            {
                e.Effects = DragDropEffects.None;
            }
            e.Handled = true;
        };

        element.DragLeave += (s, e) =>
        {
            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|DragLeave|\n");
        };

        element.Drop += (s, e) =>
        {
            if (e.Data.GetDataPresent(dataFormat))
            {
                string payload = e.Data.GetData(dataFormat) as string ?? "";
                string sourceName = e.Data.GetData("DragSourceName") as string ?? "";
                var dropPos = e.GetPosition((UIElement)s);
                string dropData = payload + "|" + sourceName + "|" +
                    dropPos.X.ToString("F0", System.Globalization.CultureInfo.InvariantCulture) + "," +
                    dropPos.Y.ToString("F0", System.Globalization.CultureInfo.InvariantCulture);
                SendToAhk("EVENT|" + winId + "|" + ctrlName + "|Drop|" +
                    LengthPrefix(dropData) + "\n");
            }
            else if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                SendToAhk("EVENT|" + winId + "|" + ctrlName + "|FileDrop|" +
                    LengthPrefix(string.Join("|", files)) + "\n");
            }
            e.Handled = true;
        };
    }

    private void EnableListBoxDragDrop(ListBox listBox, string ctrlName)
    {
        listBox.AllowDrop = true;
        Point dragStart = new Point();
        bool isDragging = false;

        listBox.PreviewMouseLeftButtonDown += (s, e) =>
        {
            dragStart = e.GetPosition(null);
            isDragging = true;
        };

        listBox.PreviewMouseMove += (s, e) =>
        {
            if (e.LeftButton == System.Windows.Input.MouseButtonState.Pressed && isDragging)
            {
                Point pos = e.GetPosition(null);
                if (Math.Abs(pos.X - dragStart.X) > SystemParameters.MinimumHorizontalDragDistance ||
                    Math.Abs(pos.Y - dragStart.Y) > SystemParameters.MinimumVerticalDragDistance)
                {

                    var item = GetListBoxItemUnderMouse(listBox, e.GetPosition(listBox));
                    if (item != null)
                    {
                        string content = "";
                        if (item.Content is string)
                        {
                            content = (string)item.Content;
                        }
                        else if (item.Content is System.Windows.Controls.TextBlock)
                        {
                            content = ((System.Windows.Controls.TextBlock)item.Content).Text;
                        }
                        else
                        {
                            content = item.Content != null ? item.Content.ToString() : "";
                        }

                        DataObject dragData = new DataObject("KanbanItem", content);
                        dragData.SetData("SourceBox", ctrlName);

                        DragDrop.DoDragDrop(listBox, dragData, DragDropEffects.Move);
                    }
                    isDragging = false;
                }
            }
        };

        listBox.Drop += (s, e) =>
        {
            if (e.Data.GetDataPresent("KanbanItem"))
            {
                string content = (string)e.Data.GetData("KanbanItem");
                string sourceBox = (string)e.Data.GetData("SourceBox");

                if (sourceBox != ctrlName)
                {
                    SendToAhk("EVENT|" + winId + "|" + ctrlName + "|ItemDropped|" +
                        LengthPrefix(sourceBox + "|" + content) + "\n");
                }
            }
        };
    }

    private ListBoxItem GetListBoxItemUnderMouse(ListBox lb, Point p)
    {
        System.Windows.Media.HitTestResult hit = System.Windows.Media.VisualTreeHelper.HitTest(lb, p);
        if (hit != null)
        {
            DependencyObject depObj = hit.VisualHit;
            while (depObj != null && !(depObj is ListBoxItem))
            {
                depObj = System.Windows.Media.VisualTreeHelper.GetParent(depObj);
            }
            return depObj as ListBoxItem;
        }
        return null;
    }

    private void EnableListBoxDragSource(ListBox listBox, string ctrlName, string dataFormat)
    {
        Point dragStart = new Point();
        bool isDragging = false;

        listBox.PreviewMouseLeftButtonDown += (s, e) =>
        {
            dragStart = e.GetPosition(null);
            isDragging = true;
        };

        listBox.PreviewMouseMove += (s, e) =>
        {
            if (e.LeftButton == System.Windows.Input.MouseButtonState.Pressed && isDragging)
            {
                Point pos = e.GetPosition(null);
                if (Math.Abs(pos.X - dragStart.X) > SystemParameters.MinimumHorizontalDragDistance ||
                    Math.Abs(pos.Y - dragStart.Y) > SystemParameters.MinimumVerticalDragDistance)
                {
                    var item = GetListBoxItemUnderMouse(listBox, e.GetPosition(listBox));
                    if (item != null)
                    {
                        string content = "";
                        if (item.Content is string)
                        {
                            content = (string)item.Content;
                        }
                        else if (item.Content is System.Windows.Controls.TextBlock)
                        {
                            content = ((System.Windows.Controls.TextBlock)item.Content).Text;
                        }
                        else
                        {
                            content = item.Content != null ? item.Content.ToString() : "";
                        }

                        DataObject dragData = new DataObject(dataFormat, content);
                        dragData.SetData("DragSourceName", ctrlName);
                        try
                        {
                            DragDrop.DoDragDrop(listBox, dragData, DragDropEffects.Copy | DragDropEffects.Move);
                        }
                        catch { }
                    }
                    isDragging = false;
                }
            }
        };
    }

#if ENABLE_AVALONEDIT
    // AvalonEdit theme application
    private void CustomizeFoldingMargin(TextEditor editor, System.Windows.Media.Brush markerBrush, System.Windows.Media.Brush selectedMarkerBrush, System.Windows.Media.Brush markerBgBrush) {
        foreach (var margin in editor.TextArea.LeftMargins) {
            if (margin.GetType().Name == "FoldingMargin" || margin.GetType().FullName.Contains("FoldingMargin")) {
                try {
                    var fMargin = margin;
                    var markerBrushProp = fMargin.GetType().GetProperty("FoldingMarkerBrush");
                    if (markerBrushProp != null) markerBrushProp.SetValue(fMargin, markerBrush, null);
                    
                    var selMarkerBrushProp = fMargin.GetType().GetProperty("SelectedFoldingMarkerBrush");
                    if (selMarkerBrushProp != null) selMarkerBrushProp.SetValue(fMargin, selectedMarkerBrush, null);
                    
                    var bgMarkerBrushProp = fMargin.GetType().GetProperty("FoldingMarkerBackgroundBrush");
                    if (bgMarkerBrushProp != null) bgMarkerBrushProp.SetValue(fMargin, markerBgBrush, null);
                } catch { }
            }
        }
    }

    private void ApplyAvalonEditTheme(TextEditor editor, string theme) {
        editor.Resources["CurrentTheme"] = theme;
        System.Windows.Media.Brush markerBrush = System.Windows.Media.Brushes.Gray;
        System.Windows.Media.Brush selectedMarkerBrush = System.Windows.Media.Brushes.Blue;
        System.Windows.Media.Brush markerBgBrush = System.Windows.Media.Brushes.White;

        switch (theme.ToLower()) {
            case "dark":
                editor.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 30));
                editor.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(212, 212, 212));
                editor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(40, 255, 255, 255));
                editor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(30, 255, 255, 255)), 1);
                editor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(100, 100, 100));
                editor.TextArea.SelectionBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(100, 38, 79, 120));
                editor.TextArea.SelectionForeground = null;
                
                markerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(90, 90, 90));
                selectedMarkerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(137, 180, 250)); // #89b4fa
                markerBgBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(37, 37, 38));
                break;
            case "light":
                editor.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 255, 255));
                editor.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 0, 0));
                editor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(25, 0, 0, 0));
                editor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(20, 0, 0, 0)), 1);
                editor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(150, 150, 150));
                editor.TextArea.SelectionBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(80, 0, 120, 215));
                editor.TextArea.SelectionForeground = null;
                
                markerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(160, 160, 160));
                selectedMarkerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 120, 215));
                markerBgBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(240, 240, 240));
                break;
            case "monokai":
                editor.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(39, 40, 34));
                editor.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(248, 248, 242));
                editor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(30, 255, 255, 255));
                editor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(System.Windows.Media.Brushes.Transparent, 0);
                editor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(100, 100, 80));
                editor.TextArea.SelectionBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(80, 73, 72, 62));
                
                markerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(117, 113, 94));
                selectedMarkerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(166, 226, 46));
                markerBgBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(62, 61, 50));
                break;
            case "one-dark": case "onedark":
                editor.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(40, 44, 52));
                editor.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(171, 178, 191));
                editor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(25, 255, 255, 255));
                editor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(System.Windows.Media.Brushes.Transparent, 0);
                editor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(76, 82, 99));
                editor.TextArea.SelectionBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(80, 62, 68, 81));
                
                markerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(92, 99, 112));
                selectedMarkerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(97, 175, 239));
                markerBgBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(49, 53, 63));
                break;
            case "dracula":
                editor.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(40, 42, 54));
                editor.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(248, 248, 242));
                editor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(25, 255, 255, 255));
                editor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(System.Windows.Media.Brushes.Transparent, 0);
                editor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(98, 114, 164));
                editor.TextArea.SelectionBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(80, 68, 71, 90));
                
                markerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(98, 114, 164));
                selectedMarkerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(189, 147, 249));
                markerBgBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(52, 55, 70));
                break;
            case "solarized-dark":
                editor.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 43, 54));
                editor.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(131, 148, 150));
                editor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(20, 255, 255, 255));
                editor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(System.Windows.Media.Brushes.Transparent, 0);
                editor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(88, 110, 117));
                editor.TextArea.SelectionBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(60, 7, 54, 66));
                
                markerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(88, 110, 117));
                selectedMarkerBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(38, 139, 210));
                markerBgBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(7, 54, 66));
                break;
            default:
                if (theme.Contains(":")) {
                    foreach (string pair in theme.Split(',')) {
                        string[] kv = pair.Split(':');
                        if (kv.Length != 2) continue;
                        try {
                            var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(kv[1]);
                            var brush = new System.Windows.Media.SolidColorBrush(color);
                            switch (kv[0].Trim().ToLower()) {
                                case "bg": editor.Background = brush; break;
                                case "fg": editor.Foreground = brush; break;
                                case "ln": editor.LineNumbersForeground = brush; break;
                                case "sel": editor.TextArea.SelectionBrush = brush; break;
                                case "cur": editor.TextArea.TextView.CurrentLineBackground = brush; break;
                            }
                        } catch { }
                    }
                }
                break;
        }

        CustomizeFoldingMargin(editor, markerBrush, selectedMarkerBrush, markerBgBrush);
    }
#endif

#if ENABLE_DOCUMENT
    private void ApplyDocFormat(RichTextBox rtb, string command) {
        string[] cmdParts = command.Split(new[] { '|' }, 2);
        string cmd = cmdParts[0];
        string val = cmdParts.Length > 1 ? cmdParts[1] : "";

        var selection = rtb.Selection;

        switch (cmd) {
            case "Bold":
                EditingCommands.ToggleBold.Execute(null, rtb);
                break;
            case "Italic":
                EditingCommands.ToggleItalic.Execute(null, rtb);
                break;
            case "Underline":
                EditingCommands.ToggleUnderline.Execute(null, rtb);
                break;
            case "Strikethrough":
                selection.ApplyPropertyValue(Inline.TextDecorationsProperty, TextDecorations.Strikethrough);
                break;
            case "FontFamily":
                if (!string.IsNullOrEmpty(val))
                    selection.ApplyPropertyValue(TextElement.FontFamilyProperty, ResolveFontFamily(val));
                break;
            case "FontSize":
                double fs; if (double.TryParse(val, out fs))
                    selection.ApplyPropertyValue(TextElement.FontSizeProperty, fs);
                break;
            case "FontColor":
                if (!string.IsNullOrEmpty(val)) {
                    try {
                        var brush = new System.Windows.Media.BrushConverter().ConvertFromString(val) as System.Windows.Media.Brush;
                        if (brush != null) selection.ApplyPropertyValue(TextElement.ForegroundProperty, brush);
                    } catch { }
                }
                break;
            case "Highlight":
                if (!string.IsNullOrEmpty(val)) {
                    try {
                        var brush = new System.Windows.Media.BrushConverter().ConvertFromString(val) as System.Windows.Media.Brush;
                        if (brush != null) selection.ApplyPropertyValue(TextElement.BackgroundProperty, brush);
                    } catch { }
                }
                break;
            case "AlignLeft":
                EditingCommands.AlignLeft.Execute(null, rtb);
                break;
            case "AlignCenter":
                EditingCommands.AlignCenter.Execute(null, rtb);
                break;
            case "AlignRight":
                EditingCommands.AlignRight.Execute(null, rtb);
                break;
            case "AlignJustify":
                EditingCommands.AlignJustify.Execute(null, rtb);
                break;
            case "BulletList":
                EditingCommands.ToggleBullets.Execute(null, rtb);
                break;
            case "NumberList":
                EditingCommands.ToggleNumbering.Execute(null, rtb);
                break;
            case "IncreaseIndent":
                EditingCommands.IncreaseIndentation.Execute(null, rtb);
                break;
            case "DecreaseIndent":
                EditingCommands.DecreaseIndentation.Execute(null, rtb);
                break;
            case "Superscript":
                selection.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Superscript);
                double curSize = 14;
                var szObj = selection.GetPropertyValue(TextElement.FontSizeProperty);
                if (szObj is double) curSize = (double)szObj;
                selection.ApplyPropertyValue(TextElement.FontSizeProperty, curSize * 0.7);
                break;
            case "Subscript":
                selection.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Subscript);
                double curSize2 = 14;
                var szObj2 = selection.GetPropertyValue(TextElement.FontSizeProperty);
                if (szObj2 is double) curSize2 = (double)szObj2;
                selection.ApplyPropertyValue(TextElement.FontSizeProperty, curSize2 * 0.7);
                break;
            case "ClearFormatting":
                selection.ClearAllProperties();
                break;
            case "Heading": {
                double headingSize = 24;
                if (!string.IsNullOrEmpty(val)) {
                    switch (val) {
                        case "1": headingSize = 28; break;
                        case "2": headingSize = 24; break;
                        case "3": headingSize = 20; break;
                        case "4": headingSize = 18; break;
                        case "5": headingSize = 16; break;
                        case "6": headingSize = 14; break;
                    }
                }
                selection.ApplyPropertyValue(TextElement.FontSizeProperty, headingSize);
                selection.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Bold);
                break;
            }
            case "TableCellBackground": {
                if (!string.IsNullOrEmpty(val)) {
                    try {
                        var brush = new System.Windows.Media.BrushConverter().ConvertFromString(val) as System.Windows.Media.Brush;
                        if (brush != null) {
                            var cell = GetCurrentCell(rtb);
                            if (cell != null) cell.Background = brush;
                        }
                    } catch { }
                }
                break;
            }
            case "TableMergeRight": {
                var cell = GetCurrentCell(rtb);
                if (cell != null) {
                    cell.ColumnSpan = cell.ColumnSpan + 1;
                }
                break;
            }
            case "TableAddRowBelow": {
                var cell = GetCurrentCell(rtb);
                if (cell != null) {
                    var row = cell.Parent as System.Windows.Documents.TableRow;
                    var rg = row != null ? row.Parent as System.Windows.Documents.TableRowGroup : null;
                    if (row != null && rg != null) {
                        var newRow = new System.Windows.Documents.TableRow();
                        int colCount = 0;
                        foreach (var c in row.Cells) colCount += c.ColumnSpan;
                        for (int i = 0; i < colCount; i++) {
                            var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                            newCell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                            newCell.BorderThickness = new Thickness(0.5);
                            newCell.Padding = new Thickness(10, 8, 10, 8);
                            newRow.Cells.Add(newCell);
                        }
                        int rowIdx = rg.Rows.IndexOf(row);
                        if (rowIdx < rg.Rows.Count - 1)
                            rg.Rows.Insert(rowIdx + 1, newRow);
                        else
                            rg.Rows.Add(newRow);
                    }
                }
                break;
            }
            case "TableAddRowAbove": {
                var cell = GetCurrentCell(rtb);
                if (cell != null) {
                    var row = cell.Parent as System.Windows.Documents.TableRow;
                    var rg = row != null ? row.Parent as System.Windows.Documents.TableRowGroup : null;
                    if (row != null && rg != null) {
                        var newRow = new System.Windows.Documents.TableRow();
                        int colCount = 0;
                        foreach (var c in row.Cells) colCount += c.ColumnSpan;
                        for (int i = 0; i < colCount; i++) {
                            var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                            newCell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                            newCell.BorderThickness = new Thickness(0.5);
                            newCell.Padding = new Thickness(10, 8, 10, 8);
                            newRow.Cells.Add(newCell);
                        }
                        int rowIdx = rg.Rows.IndexOf(row);
                        rg.Rows.Insert(rowIdx, newRow);
                    }
                }
                break;
            }
            case "TableAddColumnRight": {
                var cell = GetCurrentCell(rtb);
                if (cell != null) {
                    var row = cell.Parent as System.Windows.Documents.TableRow;
                    var rg = row != null ? row.Parent as System.Windows.Documents.TableRowGroup : null;
                    var table = rg != null ? rg.Parent as System.Windows.Documents.Table : null;
                    if (table != null && rg != null) {
                        int cellIdx = row.Cells.IndexOf(cell);
                        table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                        foreach (var r in rg.Rows) {
                            int insertAt = Math.Min(cellIdx + 1, r.Cells.Count);
                            var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                            newCell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                            newCell.BorderThickness = new Thickness(0.5);
                            newCell.Padding = new Thickness(10, 8, 10, 8);
                            r.Cells.Insert(insertAt, newCell);
                        }
                    }
                }
                break;
            }
            case "TableDeleteRow": {
                var cell = GetCurrentCell(rtb);
                if (cell != null) {
                    var row = cell.Parent as System.Windows.Documents.TableRow;
                    var rg = row != null ? row.Parent as System.Windows.Documents.TableRowGroup : null;
                    if (rg != null && rg.Rows.Count > 1) {
                        rg.Rows.Remove(row);
                    }
                }
                break;
            }
            case "TableDeleteColumn": {
                var cell = GetCurrentCell(rtb);
                if (cell != null) {
                    var row = cell.Parent as System.Windows.Documents.TableRow;
                    var rg = row != null ? row.Parent as System.Windows.Documents.TableRowGroup : null;
                    var table = rg != null ? rg.Parent as System.Windows.Documents.Table : null;
                    if (table != null && rg != null) {
                        int cellIdx = row.Cells.IndexOf(cell);
                        foreach (var r in rg.Rows.ToList()) {
                            if (cellIdx >= 0 && cellIdx < r.Cells.Count && r.Cells.Count > 1)
                                r.Cells.RemoveAt(cellIdx);
                        }
                        if (table.Columns.Count > 1)
                            table.Columns.RemoveAt(table.Columns.Count - 1);
                    }
                }
                break;
            }
        }
    }

    private System.Windows.Documents.TableCell GetCurrentCell(RichTextBox rtb) {
        DependencyObject pointer = rtb.CaretPosition.Parent;
        while (pointer != null && !(pointer is System.Windows.Documents.TableCell)) {
            pointer = System.Windows.Media.VisualTreeHelper.GetParent(pointer);
        }
        if (pointer == null) {
            pointer = rtb.CaretPosition.Parent;
            while (pointer != null && !(pointer is System.Windows.Documents.TableCell)) {
                pointer = LogicalTreeHelper.GetParent(pointer);
            }
        }
        return pointer as System.Windows.Documents.TableCell;
    }

    public class DocLayoutSettings {
        public double PageWidth { get; set; }
        public double PageHeight { get; set; }
        public Thickness PagePadding { get; set; }
        public double LinePitch { get; set; } // From <w:docGrid w:linePitch="312"/> in twips; 0 = not set
        public double LineSpacingOverride { get; set; } // User-set multiplier (0 = use document default)
    }

    private void _ApplyLineSpacingToBlocks(BlockCollection blocks, double multiplier, double gridLH) {
        foreach (var block in blocks) {
            if (block is System.Windows.Documents.Paragraph) {
                var para = (System.Windows.Documents.Paragraph)block;
                double effFontSize = para.FontSize;
                double baseHeight;
                if (gridLH > 0) {
                    baseHeight = Math.Max(gridLH, effFontSize * 1.2);
                } else {
                    baseHeight = effFontSize * 1.2;
                }
                para.LineHeight = baseHeight * multiplier;
                para.LineStackingStrategy = LineStackingStrategy.MaxHeight;
            } else if (block is System.Windows.Documents.Section) {
                _ApplyLineSpacingToBlocks(((System.Windows.Documents.Section)block).Blocks, multiplier, gridLH);
            } else if (block is System.Windows.Documents.List) {
                foreach (var li in ((System.Windows.Documents.List)block).ListItems) {
                    _ApplyLineSpacingToBlocks(li.Blocks, multiplier, gridLH);
                }
            }
        }
    }

    private string _themeMajorLatin = "Calibri Light";
    private string _themeMinorLatin = "Calibri";
    private string _themeMajorEastAsia = "Microsoft YaHei";
    private string _themeMinorEastAsia = "SimSun";

    private static RunProperties GetStyleRunProperties(string styleId, Styles styles) {
        if (styles == null || string.IsNullOrEmpty(styleId)) return null;
        var style = styles.Elements<DocumentFormat.OpenXml.Wordprocessing.Style>().FirstOrDefault(s => s.StyleId == styleId);
        if (style == null) return null;
        var rPr = style.Elements<RunProperties>().FirstOrDefault();
        if (rPr != null) return rPr;
        var basedOn = style.Elements<BasedOn>().FirstOrDefault();
        if (basedOn != null && basedOn.Val != null) {
            return GetStyleRunProperties(basedOn.Val.Value, styles);
        }
        return null;
    }

    private static ParagraphProperties GetStyleParagraphProperties(string styleId, Styles styles) {
        if (styles == null || string.IsNullOrEmpty(styleId)) return null;
        var style = styles.Elements<DocumentFormat.OpenXml.Wordprocessing.Style>().FirstOrDefault(s => s.StyleId == styleId);
        if (style == null) return null;
        var pPr = style.Elements<ParagraphProperties>().FirstOrDefault();
        if (pPr != null) return pPr;
        var basedOn = style.Elements<BasedOn>().FirstOrDefault();
        if (basedOn != null && basedOn.Val != null) {
            return GetStyleParagraphProperties(basedOn.Val.Value, styles);
        }
        return null;
    }

    private static T GetPropertyFromStyleHierarchy<T>(string styleId, Styles styles) where T : OpenXmlElement {
        if (styles == null || string.IsNullOrEmpty(styleId)) return null;
        var style = styles.Elements<DocumentFormat.OpenXml.Wordprocessing.Style>().FirstOrDefault(s => s.StyleId == styleId);
        if (style == null) return null;
        // Style definitions use StyleRunProperties (not RunProperties) for <w:rPr> children
        var srPr = style.Elements<DocumentFormat.OpenXml.Wordprocessing.StyleRunProperties>().FirstOrDefault();
        if (srPr != null) {
            var prop = srPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        // Also check RunProperties in case some documents use it (shouldn't per spec, but be safe)
        var rPr = style.Elements<RunProperties>().FirstOrDefault();
        if (rPr != null) {
            var prop = rPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        var basedOn = style.Elements<BasedOn>().FirstOrDefault();
        if (basedOn != null && basedOn.Val != null) {
            return GetPropertyFromStyleHierarchy<T>(basedOn.Val.Value, styles);
        }
        return null;
    }

    private static T GetParagraphPropertyFromStyleHierarchy<T>(string styleId, Styles styles) where T : OpenXmlElement {
        if (styles == null || string.IsNullOrEmpty(styleId)) return null;
        var style = styles.Elements<DocumentFormat.OpenXml.Wordprocessing.Style>().FirstOrDefault(s => s.StyleId == styleId);
        if (style == null) return null;
        // Style definitions use StyleParagraphProperties (not ParagraphProperties)
        var spPr = style.Elements<DocumentFormat.OpenXml.Wordprocessing.StyleParagraphProperties>().FirstOrDefault();
        if (spPr != null) {
            var prop = spPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        // Also check ParagraphProperties for compatibility
        var pPr = style.Elements<ParagraphProperties>().FirstOrDefault();
        if (pPr != null) {
            var prop = pPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        var basedOn = style.Elements<BasedOn>().FirstOrDefault();
        if (basedOn != null && basedOn.Val != null) {
            return GetParagraphPropertyFromStyleHierarchy<T>(basedOn.Val.Value, styles);
        }
        return null;
    }

    private T GetParagraphProperty<T>(ParagraphProperties pPr, string paragraphStyleId, Styles styles, ParagraphProperties defaultPPr) where T : OpenXmlElement {
        if (pPr != null) {
            var prop = pPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        if (!string.IsNullOrEmpty(paragraphStyleId)) {
            var prop = GetParagraphPropertyFromStyleHierarchy<T>(paragraphStyleId, styles);
            if (prop != null) return prop;
        }
        if (defaultPPr != null) {
            var prop = defaultPPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        return null;
    }

    private static string ResolveRunFontName(RunFonts runFonts, string themeMajorLatin, string themeMinorLatin, string themeMajorEastAsia, string themeMinorEastAsia, bool hasNonAscii) {
        if (runFonts == null) return null;
        string fontName = null;
        if (hasNonAscii) {
            if (runFonts.EastAsia != null) fontName = runFonts.EastAsia.Value;
            else if (runFonts.EastAsiaTheme != null && runFonts.EastAsiaTheme.Value != null) {
                var themeVal = runFonts.EastAsiaTheme.Value.ToString();
                if (themeVal.Contains("major") || themeVal.Contains("Major")) fontName = themeMajorEastAsia;
                else if (themeVal.Contains("minor") || themeVal.Contains("Minor")) fontName = themeMinorEastAsia;
            }
            if (!string.IsNullOrEmpty(fontName)) return fontName;
        }
        if (runFonts.Ascii != null) fontName = runFonts.Ascii.Value;
        else if (runFonts.AsciiTheme != null && runFonts.AsciiTheme.Value != null) {
            var themeVal = runFonts.AsciiTheme.Value.ToString();
            if (themeVal.Contains("major") || themeVal.Contains("Major")) fontName = themeMajorLatin;
            else if (themeVal.Contains("minor") || themeVal.Contains("Minor")) fontName = themeMinorLatin;
        }
        if (!string.IsNullOrEmpty(fontName)) return fontName;
        if (runFonts.HighAnsi != null) fontName = runFonts.HighAnsi.Value;
        else if (runFonts.HighAnsiTheme != null && runFonts.HighAnsiTheme.Value != null) {
            var themeVal = runFonts.HighAnsiTheme.Value.ToString();
            if (themeVal.Contains("major") || themeVal.Contains("Major")) fontName = themeMajorLatin;
            else if (themeVal.Contains("minor") || themeVal.Contains("Minor")) fontName = themeMinorLatin;
        }
        return fontName;
    }

    private FlowDocument DocxToFlowDocument(string filePath) {
        var doc = new FlowDocument();
        doc.FontFamily = new System.Windows.Media.FontFamily("Segoe UI, Segoe UI Emoji, Segoe UI Symbol");
        doc.FontSize = 14;
        doc.PagePadding = new Thickness(96, 72, 96, 72); // Standard page margins (1" left/right, 0.75" top/bottom)
        // Set high-quality text rendering on the document itself
        TextOptions.SetTextFormattingMode(doc, TextFormattingMode.Ideal);
        TextOptions.SetTextRenderingMode(doc, TextRenderingMode.ClearType);
        TextOptions.SetTextHintingMode(doc, TextHintingMode.Fixed);

        using (var wordDoc = WordprocessingDocument.Open(filePath, false)) {
            var mainPart = wordDoc.MainDocumentPart;
            var body = mainPart.Document.Body;
            
            // Try to parse theme fonts
            _themeMajorLatin = "Calibri Light";
            _themeMinorLatin = "Calibri";
            _themeMajorEastAsia = "Microsoft YaHei";
            _themeMinorEastAsia = "SimSun";
            try {
                var themePart = mainPart.ThemePart;
                if (themePart != null && themePart.Theme != null) {
                    var themeElements = themePart.Theme.Elements<DocumentFormat.OpenXml.Drawing.ThemeElements>().FirstOrDefault();
                    var fontScheme = themeElements != null ? themeElements.Elements<DocumentFormat.OpenXml.Drawing.FontScheme>().FirstOrDefault() : null;
                    if (fontScheme != null) {
                        var majorFont = fontScheme.Elements<DocumentFormat.OpenXml.Drawing.MajorFont>().FirstOrDefault();
                        if (majorFont != null) {
                            var latin = majorFont.Elements<DocumentFormat.OpenXml.Drawing.LatinFont>().FirstOrDefault();
                            if (latin != null && latin.Typeface != null) _themeMajorLatin = latin.Typeface.Value;
                            var ea = majorFont.Elements<DocumentFormat.OpenXml.Drawing.EastAsianFont>().FirstOrDefault();
                            if (ea != null && ea.Typeface != null) _themeMajorEastAsia = ea.Typeface.Value;
                        }
                        var minorFont = fontScheme.Elements<DocumentFormat.OpenXml.Drawing.MinorFont>().FirstOrDefault();
                        if (minorFont != null) {
                            var latin = minorFont.Elements<DocumentFormat.OpenXml.Drawing.LatinFont>().FirstOrDefault();
                            if (latin != null && latin.Typeface != null) _themeMinorLatin = latin.Typeface.Value;
                            var ea = minorFont.Elements<DocumentFormat.OpenXml.Drawing.EastAsianFont>().FirstOrDefault();
                            if (ea != null && ea.Typeface != null) _themeMinorEastAsia = ea.Typeface.Value;
                        }
                    }
                }
            } catch { }

            // Try to parse document default font and size
            string defaultFont = "Segoe UI";
            double defaultPtSize = 11.0;
            try {
                var stylesPart = mainPart.StyleDefinitionsPart;
                if (stylesPart != null && stylesPart.Styles != null) {
                    var docDefaults = stylesPart.Styles.DocDefaults;
                    if (docDefaults != null && docDefaults.RunPropertiesDefault != null && docDefaults.RunPropertiesDefault.Elements<RunProperties>().FirstOrDefault() != null) {
                        var defaultRPr = docDefaults.RunPropertiesDefault.Elements<RunProperties>().FirstOrDefault();
                        if (defaultRPr.RunFonts != null) {
                            string asciiFont = ResolveRunFontName(defaultRPr.RunFonts, _themeMajorLatin, _themeMinorLatin, _themeMajorEastAsia, _themeMinorEastAsia, false);
                            string eastAsiaFont = ResolveRunFontName(defaultRPr.RunFonts, _themeMajorLatin, _themeMinorLatin, _themeMajorEastAsia, _themeMinorEastAsia, true);
                            
                            string defaultFontChain = "";
                            if (!string.IsNullOrEmpty(asciiFont)) defaultFontChain += asciiFont;
                            if (!string.IsNullOrEmpty(eastAsiaFont) && eastAsiaFont != asciiFont) {
                                if (defaultFontChain != "") defaultFontChain += ", ";
                                defaultFontChain += eastAsiaFont;
                            }
                            if (!string.IsNullOrEmpty(defaultFontChain)) defaultFont = defaultFontChain;
                        }
                        if (defaultRPr.FontSize != null && defaultRPr.FontSize.Val != null) {
                            double sz;
                            if (double.TryParse(defaultRPr.FontSize.Val.Value, out sz)) {
                                defaultPtSize = sz / 2.0;
                            }
                        }
                    }
                }
            } catch { }

            doc.FontFamily = ResolveFontFamily(defaultFont);
            doc.FontSize = defaultPtSize * (96.0 / 72.0);

            // Try to parse page size and margins from SectionProperties
            try {
                var sectPr = body.Elements<SectionProperties>().LastOrDefault() ?? body.Descendants<SectionProperties>().LastOrDefault();
                if (sectPr != null) {
                    var pgSz = sectPr.Elements<PageSize>().FirstOrDefault();
                    if (pgSz != null) {
                        if (pgSz.Width != null && pgSz.Width.Value > 0)
                            doc.PageWidth = (pgSz.Width.Value / 20.0) * (96.0 / 72.0);
                        if (pgSz.Height != null && pgSz.Height.Value > 0)
                            doc.PageHeight = (pgSz.Height.Value / 20.0) * (96.0 / 72.0);
                    }
                    var pgMar = sectPr.Elements<PageMargin>().FirstOrDefault();
                    if (pgMar != null) {
                        double left = 96, top = 72, right = 96, bottom = 72;
                        if (pgMar.Left != null) left = (pgMar.Left.Value / 20.0) * (96.0 / 72.0);
                        if (pgMar.Top != null) top = (pgMar.Top.Value / 20.0) * (96.0 / 72.0);
                        if (pgMar.Right != null) right = (pgMar.Right.Value / 20.0) * (96.0 / 72.0);
                        if (pgMar.Bottom != null) bottom = (pgMar.Bottom.Value / 20.0) * (96.0 / 72.0);
                        doc.PagePadding = new Thickness(left, top, right, bottom);
                    }
                }
            } catch { }

            // Parse document grid (controls line spacing in Chinese docs)
            double docGridLinePitch = 0;
            try {
                var sectPr = body.Elements<SectionProperties>().LastOrDefault() ?? body.Descendants<SectionProperties>().LastOrDefault();
                if (sectPr != null) {
                    var docGrid = sectPr.Elements<DocumentFormat.OpenXml.Wordprocessing.DocGrid>().FirstOrDefault();
                    if (docGrid != null && docGrid.LinePitch != null && docGrid.LinePitch.Value > 0) {
                        docGridLinePitch = docGrid.LinePitch.Value; // Value is in twips (1/20th of a point)
                    }
                }
            } catch { }

            doc.Tag = new DocLayoutSettings {
                PageWidth = doc.PageWidth,
                PageHeight = doc.PageHeight,
                PagePadding = doc.PagePadding,
                LinePitch = docGridLinePitch
            };
            
            // Pre-build numbering lookup
            var numberingFormats = new System.Collections.Generic.Dictionary<string, string>(); // numId_level -> format
            var numberingCounters = new System.Collections.Generic.Dictionary<string, int>();
            var numPart = mainPart.NumberingDefinitionsPart;
            if (numPart != null && numPart.Numbering != null) {
                // Build abstractNumId -> NumberingInstance mapping
                var absNumFormats = new System.Collections.Generic.Dictionary<int, System.Collections.Generic.Dictionary<int, string>>();
                foreach (var absNum in numPart.Numbering.Elements<AbstractNum>()) {
                    if (absNum.AbstractNumberId == null) continue;
                    var levelFormats = new System.Collections.Generic.Dictionary<int, string>();
                    foreach (var lvl in absNum.Elements<Level>()) {
                        if (lvl.LevelIndex == null) continue;
                        string fmt = "bullet";
                        if (lvl.NumberingFormat != null && lvl.NumberingFormat.Val != null) {
                            fmt = lvl.NumberingFormat.Val.Value.ToString().ToLower();
                        }
                        levelFormats[lvl.LevelIndex.Value] = fmt;
                    }
                    absNumFormats[absNum.AbstractNumberId.Value] = levelFormats;
                }
                foreach (var numInst in numPart.Numbering.Elements<NumberingInstance>()) {
                    if (numInst.NumberID == null || numInst.AbstractNumId == null || numInst.AbstractNumId.Val == null) continue;
                    int absId = numInst.AbstractNumId.Val.Value;
                    if (absNumFormats.ContainsKey(absId)) {
                        foreach (var kv in absNumFormats[absId]) {
                            numberingFormats[numInst.NumberID.Value + "_" + kv.Key] = kv.Value;
                        }
                    }
                }
            }

            // Track current list state for grouping consecutive list items
            System.Windows.Documents.List currentList = null;
            string currentListKey = "";

            ParseBodyElements(body, doc, ref currentList, ref currentListKey, mainPart, numberingFormats);
        }
        return doc;
    }

    private void ParseBodyElements(OpenXmlElement parent, FlowDocument doc, ref System.Windows.Documents.List currentList, ref string currentListKey, MainDocumentPart mainPart, System.Collections.Generic.Dictionary<string, string> numberingFormats) {
        foreach (var element in parent.ChildElements) {
            if (element is DocumentFormat.OpenXml.Wordprocessing.Paragraph) {
                var para = (DocumentFormat.OpenXml.Wordprocessing.Paragraph)element;
                var pPr = para.ParagraphProperties;

                // Check if this is a list paragraph
                bool isList = false;
                int listLevel = 0;
                string listFormat = "bullet";
                string listKey = "";
                if (pPr != null && pPr.NumberingProperties != null) {
                    var numProps = pPr.NumberingProperties;
                    string numId = "0";
                    if (numProps.NumberingId != null && numProps.NumberingId.Val != null) {
                        numId = numProps.NumberingId.Val.Value.ToString();
                    }
                    if (numProps.NumberingLevelReference != null && numProps.NumberingLevelReference.Val != null) {
                        listLevel = numProps.NumberingLevelReference.Val.Value;
                    }
                    if (numId != "0") {
                        isList = true;
                        listKey = numId + "_" + listLevel;
                        if (numberingFormats.ContainsKey(listKey)) {
                            listFormat = numberingFormats[listKey];
                        }
                    }
                }

                if (isList) {
                    // Create or continue a List block
                    if (currentList == null || currentListKey != listKey) {
                        currentList = new System.Windows.Documents.List();
                        currentList.Margin = new Thickness(listLevel * 20 + 20, 2, 0, 2);
                        if (listFormat == "bullet" || listFormat == "none") {
                            currentList.MarkerStyle = TextMarkerStyle.Disc;
                        } else if (listFormat == "decimal" || listFormat == "arabic") {
                            currentList.MarkerStyle = TextMarkerStyle.Decimal;
                        } else if (listFormat == "lowerroman") {
                            currentList.MarkerStyle = TextMarkerStyle.LowerRoman;
                        } else if (listFormat == "upperroman") {
                            currentList.MarkerStyle = TextMarkerStyle.UpperRoman;
                        } else if (listFormat == "lowerletter") {
                            currentList.MarkerStyle = TextMarkerStyle.LowerLatin;
                        } else if (listFormat == "upperletter") {
                            currentList.MarkerStyle = TextMarkerStyle.UpperLatin;
                        } else {
                            currentList.MarkerStyle = TextMarkerStyle.Disc;
                        }
                        currentListKey = listKey;
                        doc.Blocks.Add(currentList);
                    }
                    var listItem = new System.Windows.Documents.ListItem();
                    var listPara = BuildFlowParagraph(para, pPr, mainPart, doc);
                    listItem.Blocks.Add(listPara);
                    currentList.ListItems.Add(listItem);
                } else {
                    // End any active list
                    currentList = null;
                    currentListKey = "";

                    var flowPara = BuildFlowParagraph(para, pPr, mainPart, doc);
                    doc.Blocks.Add(flowPara);
                }
            } else if (element is DocumentFormat.OpenXml.Wordprocessing.Table) {
                currentList = null;
                currentListKey = "";
                var flowTable = BuildFlowTable((DocumentFormat.OpenXml.Wordprocessing.Table)element, mainPart, doc);
                doc.Blocks.Add(flowTable);
            } else if (element is SdtBlock || element is SdtContentBlock || element is CustomXmlBlock) {
                ParseBodyElements(element, doc, ref currentList, ref currentListKey, mainPart, numberingFormats);
            }
        }
    }

    // Build a FlowDocument Paragraph from an OpenXML Paragraph
    private System.Windows.Documents.Paragraph BuildFlowParagraph(
        DocumentFormat.OpenXml.Wordprocessing.Paragraph para,
        ParagraphProperties pPr,
        MainDocumentPart mainPart,
        FlowDocument doc) {
        
        var flowPara = new System.Windows.Documents.Paragraph();
        double effFontSize = doc.FontSize;

        ParagraphProperties defaultPPr = null;
        RunProperties defaultRPr = null;
        Styles docStyles = null;
        try {
            var stylesPart = mainPart.StyleDefinitionsPart;
            if (stylesPart != null && stylesPart.Styles != null) {
                docStyles = stylesPart.Styles;
                var docDefaults = docStyles.DocDefaults;
                if (docDefaults != null) {
                    if (docDefaults.ParagraphPropertiesDefault != null) {
                        defaultPPr = docDefaults.ParagraphPropertiesDefault.Elements<ParagraphProperties>().FirstOrDefault();
                    }
                    if (docDefaults.RunPropertiesDefault != null) {
                        defaultRPr = docDefaults.RunPropertiesDefault.Elements<RunProperties>().FirstOrDefault();
                    }
                }
            }
        } catch { }

        string styleId = "";
        if (pPr != null && pPr.ParagraphStyleId != null && pPr.ParagraphStyleId.Val != null) {
            styleId = pPr.ParagraphStyleId.Val.Value;
        } else {
            styleId = "Normal";
        }

        flowPara.Tag = styleId;
        if (styleId.StartsWith("Heading") || styleId.StartsWith("heading")) {
            int level = 1;
            if (styleId.Length > 7) int.TryParse(styleId.Substring(7), out level);
            flowPara.FontWeight = FontWeights.Bold;
            flowPara.FontSize = Math.Max(11, 24 - (level * 2)) * (96.0 / 72.0); // Convert points to pixels
            flowPara.Margin = new Thickness(0, 12.0 * (96.0 / 72.0), 0, 4.0 * (96.0 / 72.0));
            effFontSize = flowPara.FontSize;
        } else if (styleId.Contains("Quote") || styleId.Contains("quote")) {
            flowPara.FontStyle = FontStyles.Italic;
            flowPara.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(100, 100, 100));
            flowPara.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(200, 200, 200));
            flowPara.BorderThickness = new Thickness(3.0 * (96.0 / 72.0), 0, 0, 0);
            flowPara.Padding = new Thickness(12.0 * (96.0 / 72.0), 4.0 * (96.0 / 72.0), 4.0 * (96.0 / 72.0), 4.0 * (96.0 / 72.0));
        } else if (!string.IsNullOrEmpty(styleId) && docStyles != null) {
            var fontSizeProp = GetPropertyFromStyleHierarchy<DocumentFormat.OpenXml.Wordprocessing.FontSize>(styleId, docStyles);
            if (fontSizeProp != null && fontSizeProp.Val != null) {
                double sz;
                if (double.TryParse(fontSizeProp.Val.Value, out sz)) {
                    effFontSize = (sz / 2.0) * (96.0 / 72.0);
                }
            } else if (defaultRPr != null) {
                var defaultFontSize = defaultRPr.Elements<DocumentFormat.OpenXml.Wordprocessing.FontSize>().FirstOrDefault();
                if (defaultFontSize != null && defaultFontSize.Val != null) {
                    double sz;
                    if (double.TryParse(defaultFontSize.Val.Value, out sz)) {
                        effFontSize = (sz / 2.0) * (96.0 / 72.0);
                    }
                }
            }
            // Apply bold from paragraph style hierarchy
            var styleBold = GetPropertyFromStyleHierarchy<DocumentFormat.OpenXml.Wordprocessing.Bold>(styleId, docStyles);
            if (styleBold != null && IsBoldTrue(styleBold)) {
                flowPara.FontWeight = FontWeights.Bold;
            } else {
                var styleBoldCs = GetPropertyFromStyleHierarchy<DocumentFormat.OpenXml.Wordprocessing.BoldComplexScript>(styleId, docStyles);
                if (styleBoldCs != null && (styleBoldCs.Val == null || styleBoldCs.Val.Value)) {
                    flowPara.FontWeight = FontWeights.Bold;
                }
            }
            // Apply italic from paragraph style hierarchy
            var styleItalic = GetPropertyFromStyleHierarchy<DocumentFormat.OpenXml.Wordprocessing.Italic>(styleId, docStyles);
            if (styleItalic != null && IsItalicTrue(styleItalic)) {
                flowPara.FontStyle = FontStyles.Italic;
            } else {
                var styleItalicCs = GetPropertyFromStyleHierarchy<DocumentFormat.OpenXml.Wordprocessing.ItalicComplexScript>(styleId, docStyles);
                if (styleItalicCs != null && (styleItalicCs.Val == null || styleItalicCs.Val.Value)) {
                    flowPara.FontStyle = FontStyles.Italic;
                }
            }
        }

        // Scan all runs inside the paragraph to resolve the actual maximum font size.
        // This ensures line heights scale proportionally to inline run sizes.
        double maxRunFontSize = effFontSize;
        foreach (var run in para.Descendants<DocumentFormat.OpenXml.Wordprocessing.Run>()) {
            string runStyleId = (run.RunProperties != null && run.RunProperties.RunStyle != null && run.RunProperties.RunStyle.Val != null)
                ? run.RunProperties.RunStyle.Val.Value
                : null;
            var rFontSize = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.FontSize>(run.RunProperties, runStyleId, styleId, docStyles, defaultRPr);
            if (rFontSize != null && rFontSize.Val != null) {
                double sz;
                if (double.TryParse(rFontSize.Val.Value, out sz)) {
                    double runSize = (sz / 2.0) * (96.0 / 72.0);
                    if (runSize > maxRunFontSize) {
                        maxRunFontSize = runSize;
                    }
                }
            }
        }
        effFontSize = maxRunFontSize;

        // Justification
        var jc = GetParagraphProperty<Justification>(pPr, styleId, docStyles, defaultPPr);
        if (jc != null) {
            var jcVal = jc.Val != null ? jc.Val.Value : JustificationValues.Left;
            switch (jcVal) {
                case JustificationValues.Center: flowPara.TextAlignment = System.Windows.TextAlignment.Center; break;
                case JustificationValues.Right: flowPara.TextAlignment = System.Windows.TextAlignment.Right; break;
                case JustificationValues.Both: flowPara.TextAlignment = System.Windows.TextAlignment.Justify; break;
                default: flowPara.TextAlignment = System.Windows.TextAlignment.Left; break;
            }
        }

        // Shading/Background
        var shading = GetParagraphProperty<Shading>(pPr, styleId, docStyles, defaultPPr);
        if (shading != null && shading.Fill != null) {
            string fillHex = shading.Fill.Value;
            if (!string.IsNullOrEmpty(fillHex) && fillHex != "auto" && fillHex != "Auto") {
                try {
                    flowPara.Background = new System.Windows.Media.SolidColorBrush(
                        (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#" + fillHex));
                    flowPara.Padding = new Thickness(10, 6, 10, 6);
                } catch { }
            }
        }

        // Default paragraph margin (Word style: 0 before, scaled after)
        flowPara.Margin = new Thickness(0, 0, 0, effFontSize * 0.6);

        // Indentation
        var indent = GetParagraphProperty<DocumentFormat.OpenXml.Wordprocessing.Indentation>(pPr, styleId, docStyles, defaultPPr);
        if (indent != null) {
            double leftIndent = 0, rightIndent = 0, firstLine = 0;
            if (indent.Left != null) {
                double val;
                if (double.TryParse(indent.Left.Value, out val))
                    leftIndent = (val / 20.0) * (96.0 / 72.0);
            }
            if (indent.Right != null) {
                double val;
                if (double.TryParse(indent.Right.Value, out val))
                    rightIndent = (val / 20.0) * (96.0 / 72.0);
            }
            if (indent.FirstLine != null) {
                double val;
                if (double.TryParse(indent.FirstLine.Value, out val))
                    firstLine = (val / 20.0) * (96.0 / 72.0);
            }
            if (leftIndent > 0 || rightIndent > 0) {
                double top = flowPara.Margin.Top;
                double bottom = flowPara.Margin.Bottom;
                flowPara.Margin = new Thickness(leftIndent, top, rightIndent, bottom);
            }
            if (firstLine > 0)
                flowPara.TextIndent = firstLine;
        }

        // Spacing (before/after) and Line spacing (within paragraph)
        var spacing = GetParagraphProperty<DocumentFormat.OpenXml.Wordprocessing.SpacingBetweenLines>(pPr, styleId, docStyles, defaultPPr);
        double before = 0;
        double after = 0; // Default no after-spacing; Chinese docs typically have 0pt after-paragraph spacing
        if (spacing != null) {
            if (spacing.BeforeLines != null) {
                double val = spacing.BeforeLines.Value;
                var ls = doc.Tag as DocLayoutSettings;
                double lineUnit = (ls != null && ls.LinePitch > 0) ? ((ls.LinePitch / 20.0) * (96.0 / 72.0)) : (effFontSize * 1.3);
                before = lineUnit * (val / 100.0);
            } else if (spacing.Before != null) {
                double val;
                if (double.TryParse(spacing.Before.Value, out val))
                    before = (val / 20.0) * (96.0 / 72.0);
            }

            if (spacing.AfterLines != null) {
                double val = spacing.AfterLines.Value;
                var ls = doc.Tag as DocLayoutSettings;
                double lineUnit = (ls != null && ls.LinePitch > 0) ? ((ls.LinePitch / 20.0) * (96.0 / 72.0)) : (effFontSize * 1.3);
                after = lineUnit * (val / 100.0);
            } else if (spacing.After != null) {
                double val;
                if (double.TryParse(spacing.After.Value, out val))
                    after = (val / 20.0) * (96.0 / 72.0);
            }
        }
        double leftMargin = flowPara.Margin.Left;
        double rightMargin = flowPara.Margin.Right;
        flowPara.Margin = new Thickness(leftMargin, before, rightMargin, after);

        // Resolve document grid line height (used as base unit for line spacing)
        var _layoutSettings = doc.Tag as DocLayoutSettings;
        double gridLineHeight = 0;
        if (_layoutSettings != null && _layoutSettings.LinePitch > 0) {
            gridLineHeight = (_layoutSettings.LinePitch / 20.0) * (96.0 / 72.0); // twips → WPF pixels
        }

        if (spacing != null && spacing.Line != null) {
            string lineStr = spacing.Line.Value;
            double lineVal;
            if (double.TryParse(lineStr, out lineVal)) {
                var lineRule = spacing.LineRule != null ? spacing.LineRule.Value : LineSpacingRuleValues.Auto;
                if (lineRule == LineSpacingRuleValues.Auto) {
                    double multiple = lineVal / 240.0;
                    if (gridLineHeight > 0) {
                        // Word uses grid pitch as the base unit for Auto multipliers
                        // 240 = 1 grid unit, 360 = 1.5 grid units, 480 = 2 grid units
                        double baseHeight = Math.Max(gridLineHeight, effFontSize * 1.2);
                        flowPara.LineHeight = baseHeight * multiple;
                    } else {
                        // No grid — use font-proportional with leading
                        flowPara.LineHeight = effFontSize * multiple * 1.2;
                    }
                    flowPara.LineStackingStrategy = LineStackingStrategy.MaxHeight;
                } else if (lineRule == LineSpacingRuleValues.Exact) {
                    flowPara.LineHeight = (lineVal / 20.0) * (96.0 / 72.0);
                    flowPara.LineStackingStrategy = LineStackingStrategy.BlockLineHeight;
                } else if (lineRule == LineSpacingRuleValues.AtLeast) {
                    flowPara.LineHeight = (lineVal / 20.0) * (96.0 / 72.0);
                    flowPara.LineStackingStrategy = LineStackingStrategy.MaxHeight;
                }
            }
        } else {
            // No explicit spacing — use document grid for line height
            if (gridLineHeight > 0) {
                // Snap text to grid: each line occupies ceil(fontHeight / gridPitch) grid units
                double fontNaturalHeight = effFontSize * 1.2; // approximate font line metrics
                double gridUnits = Math.Ceiling(fontNaturalHeight / gridLineHeight);
                flowPara.LineHeight = gridUnits * gridLineHeight;
            } else {
                // No grid — use font-proportional spacing (~130% of font em-size)
                flowPara.LineHeight = effFontSize * 1.3;
            }
            flowPara.LineStackingStrategy = LineStackingStrategy.MaxHeight;
        }

        // Process paragraph children (Runs, Hyperlinks, Bookmarks, etc.)
        foreach (var child in para.ChildElements) {
            if (child is DocumentFormat.OpenXml.Wordprocessing.Run) {
                var run = (DocumentFormat.OpenXml.Wordprocessing.Run)child;
                
                // Check for inline images (Drawing elements)
                var drawings = run.Descendants<DocumentFormat.OpenXml.Wordprocessing.Drawing>();
                bool hasDrawing = false;
                foreach (var drawing in drawings) {
                    hasDrawing = true;
                    try {
                        var img = ExtractImageFromDrawing(drawing, mainPart);
                        if (img != null) {
                            flowPara.Inlines.Add(new InlineUIContainer(img));
                        }
                    } catch {
                        flowPara.Inlines.Add(new System.Windows.Documents.Run("[Image]") {
                            Foreground = System.Windows.Media.Brushes.Gray,
                            FontStyle = FontStyles.Italic
                        });
                    }
                }
                string runStyleId = (run.RunProperties != null && run.RunProperties.RunStyle != null && run.RunProperties.RunStyle.Val != null) 
                    ? run.RunProperties.RunStyle.Val.Value 
                    : null;
                string text = run.InnerText;
                var flowRun = new System.Windows.Documents.Run(text);
                ApplyRunProperties(flowRun, run.RunProperties, runStyleId, styleId, docStyles, defaultRPr);
                flowPara.Inlines.Add(flowRun);

            } else if (child is DocumentFormat.OpenXml.Wordprocessing.Hyperlink) {
                var hyperlink = (DocumentFormat.OpenXml.Wordprocessing.Hyperlink)child;
                string url = "";
                
                // Resolve the URL from relationship
                if (hyperlink.Id != null) {
                    try {
                        var rel = mainPart.HyperlinkRelationships
                            .FirstOrDefault(r => r.Id == hyperlink.Id.Value);
                        if (rel != null) url = rel.Uri.ToString();
                    } catch { }
                }
                if (string.IsNullOrEmpty(url) && hyperlink.Anchor != null) {
                    url = "#" + hyperlink.Anchor.Value;
                }

                // Get link display text and formatting
                string linkText = "";
                var linkSpan = new System.Windows.Documents.Hyperlink();
                foreach (var hRun in hyperlink.Elements<DocumentFormat.OpenXml.Wordprocessing.Run>()) {
                    linkText += hRun.InnerText;
                    string linkRunStyleId = (hRun.RunProperties != null && hRun.RunProperties.RunStyle != null && hRun.RunProperties.RunStyle.Val != null) 
                        ? hRun.RunProperties.RunStyle.Val.Value 
                        : null;
                    var linkFlowRun = new System.Windows.Documents.Run(hRun.InnerText);
                    ApplyRunProperties(linkFlowRun, hRun.RunProperties, linkRunStyleId, styleId, docStyles, defaultRPr);
                    linkSpan.Inlines.Add(linkFlowRun);
                }

                if (!string.IsNullOrEmpty(url)) {
                    try { linkSpan.NavigateUri = new Uri(url, UriKind.RelativeOrAbsolute); } catch { }
                    linkSpan.ToolTip = url;
                    linkSpan.Cursor = System.Windows.Input.Cursors.Hand;
                    linkSpan.RequestNavigate += (sender, e) => {
                        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); } catch { }
                        e.Handled = true;
                    };
                }
                linkSpan.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(17, 85, 204));
                flowPara.Inlines.Add(linkSpan);

            } else if (child is DocumentFormat.OpenXml.Wordprocessing.BookmarkStart ||
                       child is DocumentFormat.OpenXml.Wordprocessing.BookmarkEnd ||
                       child is DocumentFormat.OpenXml.Wordprocessing.ProofError) {
                // Skip bookmark markers and proofing info
                continue;
            }
        }

        return flowPara;
    }

    // Check if a Bold element actually means "bold" (bare <w:b/> = true, <w:b w:val="0"/> = false)
    private static bool IsBoldTrue(DocumentFormat.OpenXml.Wordprocessing.Bold bold) {
        if (bold == null) return false;
        if (bold.Val == null) return true; // bare <w:b/> means true
        return bold.Val.Value; // OnOffValue resolves "0"/"false" to false, "1"/"true" to true
    }

    // Check if an Italic element actually means "italic"
    private static bool IsItalicTrue(DocumentFormat.OpenXml.Wordprocessing.Italic italic) {
        if (italic == null) return false;
        if (italic.Val == null) return true;
        return italic.Val.Value;
    }

    private T GetRunProperty<T>(RunProperties rPr, string runStyleId, string paragraphStyleId, Styles styles, RunProperties defaultRPr) where T : OpenXmlElement {
        if (rPr != null) {
            var prop = rPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        if (!string.IsNullOrEmpty(runStyleId)) {
            var prop = GetPropertyFromStyleHierarchy<T>(runStyleId, styles);
            if (prop != null) return prop;
        }
        if (!string.IsNullOrEmpty(paragraphStyleId)) {
            var prop = GetPropertyFromStyleHierarchy<T>(paragraphStyleId, styles);
            if (prop != null) return prop;
        }
        if (defaultRPr != null) {
            var prop = defaultRPr.Elements<T>().FirstOrDefault();
            if (prop != null) return prop;
        }
        return null;
    }

    // Apply run properties to a WPF Run
    private void ApplyRunProperties(System.Windows.Documents.Run flowRun, RunProperties rPr, string runStyleId, string paragraphStyleId, Styles styles, RunProperties defaultRPr) {
        if (rPr == null && string.IsNullOrEmpty(runStyleId) && string.IsNullOrEmpty(paragraphStyleId) && defaultRPr == null) return;
        
        var bold = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.Bold>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (bold != null && IsBoldTrue(bold)) {
            flowRun.FontWeight = FontWeights.Bold;
        } else {
            // Check BoldComplexScript for CJK text
            var boldCs = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.BoldComplexScript>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
            if (boldCs != null && (boldCs.Val == null || boldCs.Val.Value)) {
                flowRun.FontWeight = FontWeights.Bold;
            }
        }
        
        var italic = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.Italic>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (italic != null && IsItalicTrue(italic)) {
            flowRun.FontStyle = FontStyles.Italic;
        } else {
            var italicCs = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.ItalicComplexScript>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
            if (italicCs != null && (italicCs.Val == null || italicCs.Val.Value)) {
                flowRun.FontStyle = FontStyles.Italic;
            }
        }
        
        var decs = new TextDecorationCollection();
        var underline = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.Underline>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (underline != null && underline.Val != null && underline.Val.Value != UnderlineValues.None) {
            foreach (var d in TextDecorations.Underline) decs.Add(d);
        }
        var strike = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.Strike>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (strike != null) {
            foreach (var d in TextDecorations.Strikethrough) decs.Add(d);
        }
        if (decs.Count > 0) {
            flowRun.TextDecorations = decs;
        }

        var fontSize = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.FontSize>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (fontSize != null) {
            double sz;
            if (fontSize.Val != null && double.TryParse(fontSize.Val.Value, out sz))
                flowRun.FontSize = (sz / 2.0) * (96.0 / 72.0); // Convert points to WPF pixels
        }
        var color = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.Color>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (color != null && color.Val != null) {
            try {
                string cVal = color.Val.Value;
                if (cVal != "auto" && cVal != "Auto")
                    flowRun.Foreground = new System.Windows.Media.SolidColorBrush(
                        (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#" + cVal));
            } catch { }
        }
        
        string asciiFont = null;
        string eastAsiaFont = null;
        var runFonts = GetRunProperty<DocumentFormat.OpenXml.Wordprocessing.RunFonts>(rPr, runStyleId, paragraphStyleId, styles, defaultRPr);
        if (runFonts != null) {
            asciiFont = ResolveRunFontName(runFonts, _themeMajorLatin, _themeMinorLatin, _themeMajorEastAsia, _themeMinorEastAsia, false);
            eastAsiaFont = ResolveRunFontName(runFonts, _themeMajorLatin, _themeMinorLatin, _themeMajorEastAsia, _themeMinorEastAsia, true);
        }

        bool hasNonAscii = false;
        if (flowRun.Text != null) {
            foreach (char ch in flowRun.Text) {
                if (ch > 127) { hasNonAscii = true; break; }
            }
        }

        if (hasNonAscii && string.IsNullOrEmpty(eastAsiaFont)) {
            eastAsiaFont = _themeMinorEastAsia; // Fallback to document default East Asian font
        }
        if (string.IsNullOrEmpty(asciiFont)) {
            asciiFont = _themeMinorLatin; // Fallback to document default Latin font
        }

        string fontChain = "";
        if (hasNonAscii) {
            if (!string.IsNullOrEmpty(eastAsiaFont)) fontChain += eastAsiaFont;
            if (!string.IsNullOrEmpty(asciiFont) && asciiFont != eastAsiaFont) {
                if (fontChain != "") fontChain += ", ";
                fontChain += asciiFont;
            }
        } else {
            if (!string.IsNullOrEmpty(asciiFont)) fontChain += asciiFont;
            if (!string.IsNullOrEmpty(eastAsiaFont) && eastAsiaFont != asciiFont) {
                if (fontChain != "") fontChain += ", ";
                fontChain += eastAsiaFont;
            }
        }
        if (!string.IsNullOrEmpty(fontChain)) {
            flowRun.FontFamily = ResolveFontFamily(fontChain);
        }
        // Highlight
        if (rPr != null && rPr.Highlight != null && rPr.Highlight.Val != null) {
            flowRun.Background = HighlightColorToBrush(rPr.Highlight.Val.Value);
        }
        // Shading on run
        if (rPr != null && rPr.Shading != null && rPr.Shading.Fill != null) {
            string fillHex = rPr.Shading.Fill.Value;
            if (!string.IsNullOrEmpty(fillHex) && fillHex != "auto" && fillHex != "Auto") {
                try {
                    flowRun.Background = new System.Windows.Media.SolidColorBrush(
                        (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#" + fillHex));
                } catch { }
            }
        }
        // Superscript / Subscript
        if (rPr != null && rPr.VerticalTextAlignment != null && rPr.VerticalTextAlignment.Val != null) {
            if (rPr.VerticalTextAlignment.Val.Value == VerticalPositionValues.Superscript) {
                flowRun.Typography.Variants = System.Windows.FontVariants.Superscript;
                flowRun.FontSize = (flowRun.FontSize > 0 ? flowRun.FontSize : 14) * 0.7;
                flowRun.BaselineAlignment = BaselineAlignment.Superscript;
            } else if (rPr.VerticalTextAlignment.Val.Value == VerticalPositionValues.Subscript) {
                flowRun.Typography.Variants = System.Windows.FontVariants.Subscript;
                flowRun.FontSize = (flowRun.FontSize > 0 ? flowRun.FontSize : 14) * 0.7;
                flowRun.BaselineAlignment = BaselineAlignment.Subscript;
            }
        }
    }

    // Convert OOXML highlight color name to WPF Brush
    private System.Windows.Media.Brush HighlightColorToBrush(HighlightColorValues color) {
        switch (color) {
            case HighlightColorValues.Yellow: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 255, 0));
            case HighlightColorValues.Green: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 255, 0));
            case HighlightColorValues.Cyan: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 255, 255));
            case HighlightColorValues.Magenta: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 0, 255));
            case HighlightColorValues.Blue: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 0, 255));
            case HighlightColorValues.Red: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 0, 0));
            case HighlightColorValues.DarkBlue: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 0, 139));
            case HighlightColorValues.DarkCyan: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 139, 139));
            case HighlightColorValues.DarkGreen: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 100, 0));
            case HighlightColorValues.DarkMagenta: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(139, 0, 139));
            case HighlightColorValues.DarkRed: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(139, 0, 0));
            case HighlightColorValues.DarkYellow: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(128, 128, 0));
            case HighlightColorValues.DarkGray: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(169, 169, 169));
            case HighlightColorValues.LightGray: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(211, 211, 211));
            case HighlightColorValues.Black: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 0, 0));
            case HighlightColorValues.White: return new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 255, 255));
            default: return System.Windows.Media.Brushes.Yellow;
        }
    }

    // Extract an image from an OpenXML Drawing element
    private System.Windows.Controls.Image ExtractImageFromDrawing(
        DocumentFormat.OpenXml.Wordprocessing.Drawing drawing, MainDocumentPart mainPart) {
        
        // Try inline images first, then anchored
        var blipFill = drawing.Descendants<DocumentFormat.OpenXml.Drawing.Blip>().FirstOrDefault();
        if (blipFill == null || blipFill.Embed == null) return null;
        
        string relId = blipFill.Embed.Value;
        var imagePart = mainPart.GetPartById(relId);
        if (imagePart == null) return null;
        
        var bi = new System.Windows.Media.Imaging.BitmapImage();
        using (var stream = imagePart.GetStream()) {
            bi.BeginInit();
            bi.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
            bi.StreamSource = stream;
            bi.EndInit();
        }
        bi.Freeze();
        
        var img = new System.Windows.Controls.Image();
        img.Source = bi;
        img.Stretch = System.Windows.Media.Stretch.Uniform;
        
        // Try to get dimensions from extent (EMU → pixels, 1 EMU = 1/914400 inch, 96 DPI)
        double maxWidth = 600;
        var extents = drawing.Descendants<DocumentFormat.OpenXml.Drawing.Wordprocessing.Extent>().FirstOrDefault();
        if (extents != null) {
            if (extents.Cx != null && extents.Cx.Value > 0) {
                double widthPx = extents.Cx.Value / 914400.0 * 96.0;
                maxWidth = Math.Min(widthPx, 660);
            }
            if (extents.Cy != null && extents.Cy.Value > 0) {
                double heightPx = extents.Cy.Value / 914400.0 * 96.0;
                img.MaxHeight = heightPx;
            }
        }
        img.MaxWidth = maxWidth;
        img.Margin = new Thickness(0, 4, 0, 4);
        return img;
    }

    // Build a FlowDocument Table from an OpenXML Table
    private System.Windows.Documents.Table BuildFlowTable(
        DocumentFormat.OpenXml.Wordprocessing.Table oxTable, MainDocumentPart mainPart, FlowDocument doc) {
        
        var flowTable = new System.Windows.Documents.Table();
        flowTable.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(110, 110, 110));
        flowTable.BorderThickness = new Thickness(1);
        flowTable.CellSpacing = 0;
        flowTable.Margin = new Thickness(0, 8, 0, 8);

        // Parse TableGrid for high-fidelity column widths
        var tblGrid = oxTable.Elements<TableGrid>().FirstOrDefault();
        if (tblGrid != null) {
            var gridCols = tblGrid.Elements<GridColumn>().ToList();
            if (gridCols.Count > 0) {
                foreach (var gc in gridCols) {
                    double wVal = 100;
                    if (gc.Width != null) {
                        double twips;
                        if (double.TryParse(gc.Width.Value, out twips)) {
                            wVal = twips / 15.0; // convert twips to WPF pixels
                        }
                    }
                    flowTable.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(wVal) });
                }
            }
        }

        var rg = new System.Windows.Documents.TableRowGroup();
        foreach (var oxRow in oxTable.Elements<DocumentFormat.OpenXml.Wordprocessing.TableRow>()) {
            var flowRow = new System.Windows.Documents.TableRow();
            foreach (var oxCell in oxRow.Elements<DocumentFormat.OpenXml.Wordprocessing.TableCell>()) {
                var cell = new System.Windows.Documents.TableCell();
                cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(110, 110, 110));
                cell.BorderThickness = new Thickness(0.5);
                cell.Padding = new Thickness(8, 6, 8, 6);

                // Cell content — multiple paragraphs
                foreach (var cellPara in oxCell.Elements<DocumentFormat.OpenXml.Wordprocessing.Paragraph>()) {
                    var flowCellPara = BuildFlowParagraph(cellPara, cellPara.ParagraphProperties, mainPart, doc);
                    flowCellPara.Margin = new Thickness(0, 0, 0, 2);
                    cell.Blocks.Add(flowCellPara);
                }
                // If no blocks were added, add empty paragraph
                if (cell.Blocks.Count == 0) {
                    cell.Blocks.Add(new System.Windows.Documents.Paragraph());
                }

                // Cell properties
                var tcPr = oxCell.TableCellProperties;
                if (tcPr != null) {
                    var shading = tcPr.Shading;
                    if (shading != null && shading.Fill != null) {
                        string fillHex = shading.Fill.Value;
                        if (!string.IsNullOrEmpty(fillHex) && fillHex != "auto" && fillHex != "Auto") {
                            try {
                                cell.Background = new System.Windows.Media.SolidColorBrush(
                                    (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#" + fillHex));
                            } catch { }
                        }
                    }
                    var gridSpan = tcPr.GridSpan;
                    if (gridSpan != null && gridSpan.Val != null) {
                        int spanVal;
                        if (int.TryParse(gridSpan.Val.ToString(), out spanVal) && spanVal > 1) {
                            cell.ColumnSpan = spanVal;
                        }
                    }
                }
                flowRow.Cells.Add(cell);
            }
            rg.Rows.Add(flowRow);
        }
        flowTable.RowGroups.Add(rg);
        if (flowTable.Columns.Count == 0) {
            int maxCols = 1;
            foreach (var r in rg.Rows) {
                int rowColCount = 0;
                foreach (var c in r.Cells) rowColCount += c.ColumnSpan;
                if (rowColCount > maxCols) maxCols = rowColCount;
            }
            for (int i = 0; i < maxCols; i++)
                flowTable.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
        }

        // Fix table cropping: scale absolute column widths to fit within available content area
        try {
            double pageWidth = double.IsNaN(doc.PageWidth) ? 816.0 : doc.PageWidth;
            double availableWidth = pageWidth - doc.PagePadding.Left - doc.PagePadding.Right;
            if (availableWidth > 0 && flowTable.Columns.Count > 0) {
                double totalColWidth = 0;
                bool allAbsolute = true;
                foreach (var col in flowTable.Columns) {
                    if (col.Width.IsStar) { allAbsolute = false; break; }
                    totalColWidth += col.Width.Value;
                }
                // Only scale if columns use absolute widths and exceed available space
                if (allAbsolute && totalColWidth > availableWidth && totalColWidth > 0) {
                    double scale = availableWidth / totalColWidth;
                    foreach (var col in flowTable.Columns) {
                        col.Width = new GridLength(col.Width.Value * scale);
                    }
                }
            }
        } catch { }

        return flowTable;
    }

    // === Font Resolution ===
    // Static cache of installed system fonts for fast lookup
    private static System.Collections.Generic.HashSet<string> _installedFonts;
    private static string _userFontsUriStr;

    private static readonly System.Collections.Generic.Dictionary<string, string[]> _fontAliases = new System.Collections.Generic.Dictionary<string, string[]>(System.StringComparer.OrdinalIgnoreCase) {
        { "SimSun", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "宋体", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "Songti", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "NSimSun", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "新宋体", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "Microsoft YaHei", new[] { "Microsoft YaHei", "微软雅黑", "YaHei", "Microsoft YaHei UI", "微软雅黑 UI" } },
        { "微软雅黑", new[] { "Microsoft YaHei", "微软雅黑", "YaHei", "Microsoft YaHei UI", "微软雅黑 UI" } },
        { "YaHei", new[] { "Microsoft YaHei", "微软雅黑", "YaHei", "Microsoft YaHei UI", "微软雅黑 UI" } },
        { "KaiTi", new[] { "KaiTi", "楷体", "Kaiti", "KaiTi_GB2312", "楷体_GB2312" } },
        { "楷体", new[] { "KaiTi", "楷体", "Kaiti", "KaiTi_GB2312", "楷体_GB2312" } },
        { "楷体_GB2312", new[] { "KaiTi", "楷体", "Kaiti", "KaiTi_GB2312", "楷体_GB2312" } },
        { "FangSong", new[] { "FangSong", "仿宋", "Fangsong", "FangSong_GB2312", "仿宋_GB2312" } },
        { "仿宋", new[] { "FangSong", "仿宋", "Fangsong", "FangSong_GB2312", "仿宋_GB2312" } },
        { "仿宋_GB2312", new[] { "FangSong", "仿宋", "Fangsong", "FangSong_GB2312", "仿宋_GB2312" } },
        { "SimHei", new[] { "SimHei", "黑体", "Heiti" } },
        { "黑体", new[] { "SimHei", "黑体", "Heiti" } },
        { "LiSu", new[] { "LiSu", "隶书", "Lishu" } },
        { "隶书", new[] { "LiSu", "隶书", "Lishu" } },
        { "YouYuan", new[] { "YouYuan", "幼圆", "Youyuan" } },
        { "幼圆", new[] { "YouYuan", "幼圆", "Youyuan" } },
        { "Times", new[] { "Times New Roman", "Georgia", "Times" } },
        { "Courier", new[] { "Courier New", "Consolas" } },
        { "Helvetica", new[] { "Arial", "Segoe UI" } },
        { "Calibri", new[] { "Calibri", "Segoe UI", "Arial" } }
    };

    private static bool IsFontInstalledWithAlias(string fontName, System.Collections.Generic.HashSet<string> installed) {
        if (string.IsNullOrEmpty(fontName)) return false;
        if (installed.Contains(fontName)) return true;
        if (_fontAliases.ContainsKey(fontName)) {
            foreach (var alias in _fontAliases[fontName]) {
                if (installed.Contains(alias)) return true;
            }
        }
        return false;
    }
    
    private static bool IsSerifFont(string fontName) {
        if (string.IsNullOrEmpty(fontName)) return false;
        string name = fontName.ToLower();
        if (name.Contains("serif") || name.Contains("roman") || name.Contains("georgia") || 
            name.Contains("times") || name.Contains("garamond") || name.Contains("bookman") || 
            name.Contains("palatino") || name.Contains("century")) {
            return true;
        }
        if (name.Contains("song") || name.Contains("ming") || name.Contains("kai") ||
            name.Contains("宋") || name.Contains("明") || name.Contains("楷") ||
            name.Contains("新細明") || name.Contains("細明") || name.Contains("报宋")) {
            return true;
        }
        return false;
    }

    private static System.Collections.Generic.HashSet<string> GetInstalledFonts() {
        if (_installedFonts == null) {
            _installedFonts = new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
            
            // 1. Scan default system font families and all their localized names
            foreach (var family in System.Windows.Media.Fonts.SystemFontFamilies) {
                _installedFonts.Add(family.Source);
                try {
                    foreach (var name in family.FamilyNames.Values) {
                        _installedFonts.Add(name);
                    }
                } catch { }
            }
            
            // 2. Scan user local AppData fonts folder if it exists
            try {
                string localAppData = System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData);
                string userFontsDir = System.IO.Path.Combine(localAppData, @"Microsoft\Windows\Fonts");
                if (System.IO.Directory.Exists(userFontsDir)) {
                    _userFontsUriStr = "file:///" + userFontsDir.Replace('\\', '/').TrimEnd('/') + "/";
                    foreach (var family in System.Windows.Media.Fonts.GetFontFamilies(new Uri(_userFontsUriStr))) {
                        _installedFonts.Add(family.Source);
                        try {
                            foreach (var name in family.FamilyNames.Values) {
                                _installedFonts.Add(name);
                            }
                        } catch { }
                    }
                }
            } catch { }

            // 3. Scan system and user registry fonts to match AHK side
            foreach (var hive in new[] { Microsoft.Win32.Registry.LocalMachine, Microsoft.Win32.Registry.CurrentUser }) {
                try {
                    using (var key = hive.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")) {
                        if (key != null) {
                            foreach (var valName in key.GetValueNames()) {
                                string name = valName;
                                name = System.Text.RegularExpressions.Regex.Replace(name, @"\s*\((TrueType|OpenType|PostScript|Type 1|Vector|Stroke)\)$", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                                name = System.Text.RegularExpressions.Regex.Replace(name, @"\s+(Bold|Italic|Regular|Semibold|Semi-Bold|Light|Extra\s*Light|Medium|Black|Condensed|Oblique|Bold\s+Italic|Italic\s+Bold|Demibold|Heavy|Nord)\b", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                                name = name.Trim();
                                if (!string.IsNullOrEmpty(name)) {
                                    if (name.Contains("&")) {
                                        foreach (var sName in name.Split('&')) {
                                            string trimmedSub = sName.Trim();
                                            if (!string.IsNullOrEmpty(trimmedSub)) _installedFonts.Add(trimmedSub);
                                        }
                                    } else {
                                        _installedFonts.Add(name);
                                    }
                                }
                            }
                        }
                    }
                } catch { }
            }
        }
        return _installedFonts;
    }

    private System.Windows.Media.FontFamily ResolveFontFamily(string requestedFont) {
        if (string.IsNullOrEmpty(requestedFont)) return new System.Windows.Media.FontFamily("Segoe UI");
        
        var installed = GetInstalledFonts();
        var parts = requestedFont.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
        var resolvedFonts = new System.Collections.Generic.List<string>();
        
        foreach (var p in parts) {
            string fontName = p.Trim();
            if (string.IsNullOrEmpty(fontName)) continue;
            
            string resolvedName = null;
            if (installed.Contains(fontName)) {
                resolvedName = fontName;
            } else {
                if (_fontAliases.ContainsKey(fontName)) {
                    foreach (var alias in _fontAliases[fontName]) {
                        if (installed.Contains(alias)) {
                            resolvedName = alias;
                            break;
                        }
                    }
                }
            }
            
            if (resolvedName != null) {
                bool isUserFont = false;
                if (!string.IsNullOrEmpty(_userFontsUriStr)) {
                    try {
                        foreach (var family in System.Windows.Media.Fonts.GetFontFamilies(new Uri(_userFontsUriStr))) {
                            bool matched = string.Equals(family.Source, resolvedName, StringComparison.OrdinalIgnoreCase);
                            if (!matched) {
                                foreach (var name in family.FamilyNames.Values) {
                                    if (string.Equals(name, resolvedName, StringComparison.OrdinalIgnoreCase)) {
                                        matched = true;
                                        break;
                                    }
                                }
                            }
                            if (matched) {
                                resolvedFonts.Add(_userFontsUriStr + "#" + resolvedName);
                                isUserFont = true;
                                break;
                            }
                        }
                    } catch { }
                }
                if (!isUserFont) {
                    resolvedFonts.Add(resolvedName);
                }
            } else {
                resolvedFonts.Add(fontName); // Add anyway as fallback
            }
        }
        
        // Add default fallbacks based on whether the primary font is Serif
        string primaryFont = parts.Length > 0 ? parts[0].Trim() : "";
        if (IsSerifFont(primaryFont)) {
            resolvedFonts.AddRange(new[] { "Times New Roman", "SimSun", "Georgia", "PMingLiU", "KaiTi", "Segoe UI", "Segoe UI Emoji", "Segoe UI Symbol", "Arial", "Microsoft YaHei" });
        } else {
            resolvedFonts.AddRange(new[] { "Segoe UI", "Segoe UI Emoji", "Segoe UI Symbol", "Arial", "Microsoft YaHei", "SimSun", "Malgun Gothic", "Yu Gothic", "Times New Roman" });
        }
        
        // Remove duplicates while keeping order
        var uniqueFonts = new System.Collections.Generic.List<string>();
        foreach (var f in resolvedFonts) {
            if (!uniqueFonts.Contains(f)) {
                uniqueFonts.Add(f);
            }
        }
        
        string joined = string.Join(", ", uniqueFonts);
        return new System.Windows.Media.FontFamily(joined);
    }

    // === Page Break Spacer Management ===
    private static T FindParent<T>(DependencyObject child) where T : DependencyObject {
        DependencyObject parentObject = child;
        while (parentObject != null) {
            if (parentObject is T) return (T)parentObject;
            DependencyObject parentVisual = null;
            if (parentObject is Visual || parentObject is System.Windows.Media.Media3D.Visual3D) {
                parentVisual = VisualTreeHelper.GetParent(parentObject);
            }
            parentObject = parentVisual ?? LogicalTreeHelper.GetParent(parentObject);
        }
        return null;
    }

    private void LogEditorState(string context, RichTextBox rtb) {
        try {
            string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log");
            var sb = new StringBuilder();
            sb.AppendLine(string.Format("--- Editor State: {0} ({1:HH:mm:ss.fff}) ---", context, DateTime.Now));
            if (rtb == null) {
                sb.AppendLine("RTB is NULL");
            } else {
                sb.AppendLine(string.Format("RTB Name: {0}", rtb.Name));
                sb.AppendLine(string.Format("RTB Visibility: {0}", rtb.Visibility));
                sb.AppendLine(string.Format("RTB IsEnabled: {0}", rtb.IsEnabled));
                sb.AppendLine(string.Format("RTB IsReadOnly: {0}", rtb.IsReadOnly));
                sb.AppendLine(string.Format("RTB IsDocumentEnabled: {0}", rtb.IsDocumentEnabled));
                sb.AppendLine(string.Format("RTB Focusable: {0}", rtb.Focusable));
                sb.AppendLine(string.Format("RTB IsFocused: {0}", rtb.IsFocused));
                sb.AppendLine(string.Format("RTB IsKeyboardFocusWithin: {0}", rtb.IsKeyboardFocusWithin));
                sb.AppendLine(string.Format("RTB IsHitTestVisible: {0}", rtb.IsHitTestVisible));
                int blocksCount = -1;
                if (rtb.Document != null && rtb.Document.Blocks != null) {
                    blocksCount = rtb.Document.Blocks.Count;
                }
                sb.AppendLine(string.Format("RTB Document Blocks Count: {0}", blocksCount));
                
                DependencyObject parent = rtb;
                while (parent != null) {
                    DependencyObject parentVisual = null;
                    if (parent is Visual || parent is System.Windows.Media.Media3D.Visual3D) {
                        parentVisual = VisualTreeHelper.GetParent(parent);
                    }
                    parent = parentVisual ?? LogicalTreeHelper.GetParent(parent);
                    if (parent != null) {
                        var fe = parent as FrameworkElement;
                        sb.AppendLine(string.Format("Parent Type: {0}, Name: {1}, Visibility: {2}, IsEnabled: {3}, IsHitTestVisible: {4}", 
                            parent.GetType().Name, 
                            fe != null ? fe.Name : "N/A", 
                            fe != null ? fe.Visibility.ToString() : "N/A", 
                            fe != null ? fe.IsEnabled.ToString() : "N/A",
                            fe != null ? fe.IsHitTestVisible.ToString() : "N/A"));
                    }
                }
            }
            sb.AppendLine();
            System.IO.File.AppendAllText(debugPath, sb.ToString());
        } catch { }
    }

    private System.Collections.Generic.List<BlockUIContainer> _pageBreakSpacers
        = new System.Collections.Generic.List<BlockUIContainer>();
    private bool _isUpdatingSpacers = false;

    private void _GetLayoutBlocks(System.Windows.Documents.BlockCollection blocks, System.Collections.Generic.List<Block> flatList) {
        foreach (var block in blocks) {
            if (block is System.Windows.Documents.Section) {
                _GetLayoutBlocks(((System.Windows.Documents.Section)block).Blocks, flatList);
            } else {
                flatList.Add(block);
            }
        }
    }

    private double _GetActualBlockHeight(RichTextBox rtb, Block block, double availableWidth) {
        try {
            var rectStart = block.ContentStart.GetCharacterRect(LogicalDirection.Forward);
            var rectEnd = block.ContentEnd.GetCharacterRect(LogicalDirection.Backward);
            double height = rectEnd.Bottom - rectStart.Top;
            if (height > 0 && height < 5000) {
                return height;
            }
        } catch { }
        return _EstimateBlockHeight(block, availableWidth);
    }

    private void ApplyViewMode(RichTextBox rtb, string viewMode, string currentTheme, Window win)
    {
        string rtbName = rtb.Name;
        string readerName = rtbName + "_PageReader";
        string pageBorderName = rtbName + "_PageBorder";
        string editorWrapperName = rtbName + "_EditorWrapper";

        // Use FindName for robust lookup — visual tree walking fails when parents are Collapsed
        var pageBorder = win.FindName(pageBorderName) as System.Windows.Controls.Border;
        if (pageBorder == null) pageBorder = rtb.Parent as System.Windows.Controls.Border;
        Grid editorWrapper = win.FindName(editorWrapperName) as Grid;
        
        // Find editorCanvas and editorSv by walking from pageBorder upwards via logical tree
        // (logical tree is always available even when elements are Collapsed)
        FrameworkElement editorCanvas = null;
        ScrollViewer editorSv = null;
        if (pageBorder != null) {
            // pageBorder → Grid(editorCenter) → ScrollViewer(editorSv) → Border(editorCanvas)
            var editorCenter = LogicalTreeHelper.GetParent(pageBorder) as FrameworkElement;
            editorSv = editorCenter != null ? LogicalTreeHelper.GetParent(editorCenter) as ScrollViewer : null;
            editorCanvas = editorSv != null ? LogicalTreeHelper.GetParent(editorSv) as FrameworkElement : null;
        }
        // Fallback: try visual tree if logical tree didn't work
        if (editorSv == null) {
            editorSv = FindParent<ScrollViewer>(rtb);
        }
        if (editorCanvas == null && editorSv != null) {
            editorCanvas = LogicalTreeHelper.GetParent(editorSv) as FrameworkElement;
            if (editorCanvas == null) {
                try { editorCanvas = VisualTreeHelper.GetParent(editorSv) as FrameworkElement; } catch { }
            }
        }
        if (editorWrapper == null && editorCanvas != null) {
            editorWrapper = LogicalTreeHelper.GetParent(editorCanvas) as Grid;
            if (editorWrapper == null) {
                try { editorWrapper = VisualTreeHelper.GetParent(editorCanvas) as Grid; } catch { }
            }
        }

        FlowDocumentReader reader = null;
        if (editorWrapper != null) {
            foreach (var child in editorWrapper.Children) {
                if (child is FlowDocumentReader) {
                    reader = (FlowDocumentReader)child;
                    break;
                }
            }
        }
        // Also try FindName for the reader
        if (reader == null) {
            reader = win.FindName(readerName) as FlowDocumentReader;
        }

        // Save view mode
        _docViewModes[rtbName] = viewMode;

        // If transitioning away from twoup, restore the editor's visual chain first so the RTB is fully visible and connected when Document is assigned
        if (viewMode != "twoup") {
            _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);
        }

        // STEP 1: ALWAYS consolidate doc back to RTB first
        if (reader != null && reader.Document != null) {
            var transferDoc = reader.Document;
            reader.Document = null;
            transferDoc.ClearValue(FlowDocument.PageWidthProperty);
            transferDoc.ClearValue(FlowDocument.PageHeightProperty);
            transferDoc.PagePadding = new Thickness(60, 50, 60, 50);
            transferDoc.ClearValue(FlowDocument.BackgroundProperty);
            transferDoc.ClearValue(FlowDocument.ForegroundProperty);
            rtb.Document = transferDoc;
        }

        // If the mode is NOT twoup, remove reader from visual tree
        if (viewMode != "twoup") {
            if (editorWrapper != null) {
                var toRemove = new System.Collections.Generic.List<UIElement>();
                foreach (var child in editorWrapper.Children) {
                    if (child is FlowDocumentReader) {
                        toRemove.Add((UIElement)child);
                    }
                }
                foreach (var r in toRemove) {
                    editorWrapper.Children.Remove(r);
                    try { win.UnregisterName(((FrameworkElement)r).Name); } catch {}
                }
            }
            // Also try to unregister by name if it still exists
            try {
                var staleReader = win.FindName(readerName) as FlowDocumentReader;
                if (staleReader != null) {
                    var parentPanel = LogicalTreeHelper.GetParent(staleReader) as System.Windows.Controls.Panel;
                    if (parentPanel != null) parentPanel.Children.Remove(staleReader);
                    try { win.UnregisterName(readerName); } catch { }
                }
            } catch { }
            reader = null;
        }

        // STEP 2: Apply the requested view mode
        if (viewMode == "paper") {
            // Hide custom page nav in status bar
            var statusPageNav = win.FindName(rtbName + "_StatusPageNav") as FrameworkElement;
            if (statusPageNav != null) statusPageNav.Visibility = Visibility.Collapsed;

            // Robustly restore the entire editor visual chain
            _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);

            var settings = rtb.Document.Tag as DocLayoutSettings;
            double pgW = 816;
            double pgH = 1056;
            Thickness pgPad = new Thickness(96, 72, 96, 72);
            if (settings != null) {
                pgW = settings.PageWidth;
                pgH = settings.PageHeight;
                pgPad = settings.PagePadding;
            }
            if (pageBorder != null) {
                pageBorder.Width = pgW;
                pageBorder.MinHeight = pgH;
                pageBorder.ClearValue(FrameworkElement.HeightProperty);
                pageBorder.Effect = new System.Windows.Media.Effects.DropShadowEffect {
                    BlurRadius = 15,
                    ShadowDepth = 3,
                    Opacity = 0.15,
                    Color = System.Windows.Media.Colors.Black
                };
            }

            rtb.Document.ClearValue(FlowDocument.PageWidthProperty);
            rtb.Document.ClearValue(FlowDocument.PageHeightProperty);
            rtb.Document.PagePadding = pgPad;
            rtb.Document.ClearValue(FlowDocument.BackgroundProperty);
            rtb.Document.ClearValue(FlowDocument.ForegroundProperty);

            // Insert spacers
            _InsertPageBreakSpacers(rtb, currentTheme);

            // Deferred focus and scroll restore — use multiple passes at different priorities
            rtb.Dispatcher.BeginInvoke(new Action(() => {
                _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);
                if (rtb.Document != null) {
                    rtb.Document.IsEnabled = true;
                    rtb.CaretPosition = rtb.Document.ContentStart;
                }
                rtb.Focus();
                System.Windows.Input.Keyboard.Focus(rtb);
                rtb.Dispatcher.BeginInvoke(new Action(() => {
                    rtb.IsReadOnly = false;
                    rtb.Focusable = true;
                    rtb.IsEnabled = false;
                    rtb.IsEnabled = true;
                    rtb.Focus();
                    System.Windows.Input.Keyboard.Focus(rtb);
                }), System.Windows.Threading.DispatcherPriority.Input);
            }), System.Windows.Threading.DispatcherPriority.Loaded);

        } else if (viewMode == "twoup") {
            _RemovePageBreakSpacers(rtb);

            var statusPageNav = win.FindName(rtbName + "_StatusPageNav") as FrameworkElement;
            if (statusPageNav != null) statusPageNav.Visibility = Visibility.Visible;

            if (reader == null && editorWrapper != null) {
                reader = new FlowDocumentReader();
                reader.Name = readerName;
                try { win.RegisterName(readerName, reader); } catch { }
                reader.BorderThickness = new Thickness(0);
                reader.IsFindEnabled = false;
                reader.Visibility = Visibility.Collapsed;
                // Set text rendering quality for two-page mode
                TextOptions.SetTextFormattingMode(reader, TextFormattingMode.Ideal);
                TextOptions.SetTextRenderingMode(reader, TextRenderingMode.ClearType);
                TextOptions.SetTextHintingMode(reader, TextHintingMode.Fixed);
                RenderOptions.SetClearTypeHint(reader, ClearTypeHint.Enabled);
                reader.UseLayoutRounding = true;
                Grid.SetColumn(reader, 1);
                Grid.SetRow(reader, 0);

                reader.Loaded += (s, ev) => {
                    var container = win.FindName(rtbName + "_Container") as FrameworkElement;
                    string theme = (container != null && container.Tag is string) ? (string)container.Tag : "Normal";
                    StyleReaderVisuals(reader, theme, win);
                    HideReaderToolbar(reader);

                    var btnPrev = win.FindName(rtbName + "_BtnPrevPage") as Button;
                    var btnNext = win.FindName(rtbName + "_BtnNextPage") as Button;
                    if (btnPrev != null) {
                        btnPrev.Click += (s2, ev2) => System.Windows.Input.NavigationCommands.PreviousPage.Execute(null, reader);
                    }
                    if (btnNext != null) {
                        btnNext.Click += (s2, ev2) => System.Windows.Input.NavigationCommands.NextPage.Execute(null, reader);
                    }

                    var dpPageNum = System.ComponentModel.DependencyPropertyDescriptor.FromProperty(FlowDocumentReader.PageNumberProperty, typeof(FlowDocumentReader));
                    if (dpPageNum != null) {
                        dpPageNum.AddValueChanged(reader, (s2, ev2) => UpdatePageStatus(reader, win));
                    }
                    var dpPageCount = System.ComponentModel.DependencyPropertyDescriptor.FromProperty(FlowDocumentReader.PageCountProperty, typeof(FlowDocumentReader));
                    if (dpPageCount != null) {
                        dpPageCount.AddValueChanged(reader, (s2, ev2) => UpdatePageStatus(reader, win));
                    }

                    UpdatePageStatus(reader, win);
                };

                editorWrapper.Children.Add(reader);
            }

            if (reader != null) {
                var doc = rtb.Document;
                rtb.Document = new FlowDocument();
                reader.Document = doc;

                double pgW = 816;
                double pgH = 1056;
                Thickness pgPad = new Thickness(96, 72, 96, 72);
                var settings = doc.Tag as DocLayoutSettings;
                if (settings != null) {
                    pgW = settings.PageWidth;
                    pgH = settings.PageHeight;
                    pgPad = settings.PagePadding;
                }
                doc.PageWidth = pgW;
                doc.PageHeight = pgH;
                doc.PagePadding = pgPad;
                doc.ColumnWidth = double.MaxValue;
                
                // Set text rendering quality on the document itself
                TextOptions.SetTextFormattingMode(doc, TextFormattingMode.Ideal);
                TextOptions.SetTextRenderingMode(doc, TextRenderingMode.ClearType);
                TextOptions.SetTextHintingMode(doc, TextHintingMode.Fixed);
                // Also ensure the reader has these settings
                TextOptions.SetTextFormattingMode(reader, TextFormattingMode.Ideal);
                TextOptions.SetTextRenderingMode(reader, TextRenderingMode.ClearType);
                TextOptions.SetTextHintingMode(reader, TextHintingMode.Fixed);
                RenderOptions.SetClearTypeHint(reader, ClearTypeHint.Enabled);
                reader.UseLayoutRounding = true;

                if (currentTheme == "Dark") {
                    reader.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 30));
                    doc.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(38, 38, 38));
                    doc.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
                } else if (currentTheme == "Theme") {
                    reader.SetResourceReference(FlowDocumentReader.BackgroundProperty, "DropdownBg");
                    doc.SetResourceReference(FlowDocument.BackgroundProperty, "ControlBg");
                    doc.SetResourceReference(FlowDocument.ForegroundProperty, "TextMain");
                } else {
                    reader.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(230, 230, 230));
                    doc.Background = System.Windows.Media.Brushes.White;
                    doc.Foreground = System.Windows.Media.Brushes.Black;
                }

                if (editorCanvas != null) editorCanvas.Visibility = Visibility.Collapsed;
                reader.Visibility = Visibility.Visible;
                reader.ViewingMode = FlowDocumentReaderViewingMode.TwoPage;

                StyleReaderVisuals(reader, currentTheme, win);
                HideReaderToolbar(reader);
                UpdatePageStatus(reader, win);
            }

        } else {
            // Feed View
            var statusPageNav = win.FindName(rtbName + "_StatusPageNav") as FrameworkElement;
            if (statusPageNav != null) statusPageNav.Visibility = Visibility.Collapsed;

            // Robustly restore the entire editor visual chain
            _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);

            if (pageBorder != null) {
                var settings = rtb.Document.Tag as DocLayoutSettings;
                double pgW = 816;
                double pgH = 1056;
                Thickness pgPad = new Thickness(96, 72, 96, 72);
                if (settings != null) {
                    pgW = settings.PageWidth;
                    pgH = settings.PageHeight;
                    pgPad = settings.PagePadding;
                }
                pageBorder.Width = pgW;
                pageBorder.MinHeight = pgH;
                pageBorder.Effect = null;
            }

            _RemovePageBreakSpacers(rtb);

            rtb.Document.ClearValue(FlowDocument.PageWidthProperty);
            rtb.Document.ClearValue(FlowDocument.PageHeightProperty);
            rtb.Document.PagePadding = new Thickness(60, 50, 60, 50);
            rtb.Document.ClearValue(FlowDocument.BackgroundProperty);
            rtb.Document.ClearValue(FlowDocument.ForegroundProperty);

            // Deferred focus and scroll restore — use multiple passes at different priorities
            rtb.Dispatcher.BeginInvoke(new Action(() => {
                _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);
                if (rtb.Document != null) {
                    rtb.Document.IsEnabled = true;
                    rtb.CaretPosition = rtb.Document.ContentStart;
                }
                rtb.Focus();
                System.Windows.Input.Keyboard.Focus(rtb);
                rtb.Dispatcher.BeginInvoke(new Action(() => {
                    rtb.IsReadOnly = false;
                    rtb.Focusable = true;
                    rtb.IsEnabled = false;
                    rtb.IsEnabled = true;
                    rtb.Focus();
                    System.Windows.Input.Keyboard.Focus(rtb);
                }), System.Windows.Threading.DispatcherPriority.Input);
            }), System.Windows.Threading.DispatcherPriority.Loaded);
        }
    }

    // Robustly restore the entire editor visual chain from RTB up through all ancestors
    private static void _RestoreEditorChain(RichTextBox rtb, System.Windows.Controls.Border pageBorder, ScrollViewer editorSv, FrameworkElement editorCanvas) {
        // Force every element in the chain to Visible + Enabled + HitTestVisible
        // Walk from the innermost (RTB) outward
        _ForceElementVisible(rtb);
        rtb.IsReadOnly = false;
        rtb.IsDocumentEnabled = false;
        rtb.Focusable = true;
        rtb.AllowDrop = true;
        // Clear any stale UIElement properties
        rtb.ClearValue(UIElement.IsHitTestVisibleProperty);
        rtb.ClearValue(UIElement.FocusableProperty);
        rtb.ClearValue(UIElement.IsEnabledProperty);
        
        if (pageBorder != null) _ForceElementVisible(pageBorder);
        
        // editorCenter (the Grid between pageBorder and ScrollViewer)
        if (pageBorder != null) {
            var editorCenter = LogicalTreeHelper.GetParent(pageBorder) as FrameworkElement;
            if (editorCenter != null) _ForceElementVisible(editorCenter);
        }
        
        if (editorSv != null) {
            _ForceElementVisible(editorSv);
            // Explicitly restore scroll bar visibility in case it was altered
            editorSv.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            editorSv.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            editorSv.CanContentScroll = true;
            editorSv.ClearValue(UIElement.IsHitTestVisibleProperty);
            // Force ScrollViewer to recalculate scroll extents
            editorSv.InvalidateScrollInfo();
            editorSv.InvalidateMeasure();
            editorSv.InvalidateArrange();
        }
        
        if (editorCanvas != null) {
            _ForceElementVisible(editorCanvas);
            // Force layout recalculation
            editorCanvas.InvalidateMeasure();
            editorCanvas.InvalidateArrange();
        }
        
        // Walk up the entire visual tree from RTB and force everything visible + enabled
        DependencyObject current = rtb;
        int maxDepth = 20;
        while (current != null && maxDepth-- > 0) {
            if (current is FrameworkElement) {
                var fe = (FrameworkElement)current;
                fe.Visibility = Visibility.Visible;
                fe.IsEnabled = true;
                fe.IsHitTestVisible = true;
            }
            try { current = VisualTreeHelper.GetParent(current); } catch { break; }
        }
    }
    
    private static void _ForceElementVisible(FrameworkElement el) {
        if (el == null) return;
        el.Visibility = Visibility.Visible;
        el.IsEnabled = true;
        el.IsHitTestVisible = true;
        el.ClearValue(UIElement.IsEnabledProperty);
    }

    // Walk the logical tree from the caret to find the enclosing TableCell
    private static System.Windows.Documents.TableCell FindTableCellAtCaret(RichTextBox rtb) {
        try {
            var pos = rtb.CaretPosition;
            if (pos == null) return null;
            DependencyObject parent = pos.Parent;
            int maxDepth = 20;
            while (parent != null && maxDepth-- > 0) {
                if (parent is System.Windows.Documents.TableCell)
                    return (System.Windows.Documents.TableCell)parent;
                parent = LogicalTreeHelper.GetParent(parent);
            }
        } catch { }
        return null;
    }

    // WPF-native color picker dialog — shows a grid of preset colors + custom RGB sliders
    private static System.Windows.Media.Color? ShowColorPickerDialog(Window owner) {
        System.Windows.Media.Color? result = null;
        var dlg = new Window();
        dlg.Title = "Choose Color";
        dlg.Width = 380;
        dlg.Height = 400;
        dlg.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        dlg.Owner = owner;
        dlg.ResizeMode = ResizeMode.NoResize;
        dlg.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 30));

        var mainPanel = new StackPanel { Margin = new Thickness(12) };

        // Title
        var title = new TextBlock { Text = "Select a Color", FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = System.Windows.Media.Brushes.White, Margin = new Thickness(0, 0, 0, 8) };
        mainPanel.Children.Add(title);

        // Preset colors grid
        string[] presets = { "#000000", "#333333", "#555555", "#888888", "#AAAAAA", "#CCCCCC", "#EEEEEE", "#FFFFFF",
                             "#FF0000", "#FF4500", "#FF8C00", "#FFD700", "#FFFF00", "#9ACD32", "#32CD32", "#008000",
                             "#00CED1", "#4169E1", "#0000FF", "#8A2BE2", "#9932CC", "#FF1493", "#FF69B4", "#FFC0CB",
                             "#800000", "#A0522D", "#DAA520", "#808000", "#006400", "#008080", "#000080", "#4B0082",
                             "#F0E68C", "#FAEBD7", "#FFE4C4", "#FFDEAD", "#DEB887", "#D2B48C", "#BC8F8F", "#CD853F" };

        var grid = new System.Windows.Controls.WrapPanel { Margin = new Thickness(0, 4, 0, 8) };
        var preview = new System.Windows.Controls.Border {
            Width = double.NaN, Height = 36, Margin = new Thickness(0, 8, 0, 4),
            CornerRadius = new CornerRadius(4),
            Background = System.Windows.Media.Brushes.White,
            BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(80, 80, 80)),
            BorderThickness = new Thickness(1)
        };

        byte rVal = 0, gVal = 0, bVal = 0;

        // RGB Sliders
        var sliderPanel = new StackPanel { Margin = new Thickness(0, 4, 0, 0) };
        var rSlider = new Slider { Minimum = 0, Maximum = 255, Value = 0, Margin = new Thickness(0, 2, 0, 2) };
        var gSlider = new Slider { Minimum = 0, Maximum = 255, Value = 0, Margin = new Thickness(0, 2, 0, 2) };
        var bSlider = new Slider { Minimum = 0, Maximum = 255, Value = 0, Margin = new Thickness(0, 2, 0, 2) };
        var rLabel = new TextBlock { Text = "R: 0", Foreground = System.Windows.Media.Brushes.LightCoral, FontSize = 11 };
        var gLabel = new TextBlock { Text = "G: 0", Foreground = System.Windows.Media.Brushes.LightGreen, FontSize = 11 };
        var bLabel = new TextBlock { Text = "B: 0", Foreground = System.Windows.Media.Brushes.LightBlue, FontSize = 11 };

        Action updatePreview = () => {
            rVal = (byte)rSlider.Value; gVal = (byte)gSlider.Value; bVal = (byte)bSlider.Value;
            preview.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(rVal, gVal, bVal));
            rLabel.Text = "R: " + rVal; gLabel.Text = "G: " + gVal; bLabel.Text = "B: " + bVal;
        };
        rSlider.ValueChanged += (s, e) => updatePreview();
        gSlider.ValueChanged += (s, e) => updatePreview();
        bSlider.ValueChanged += (s, e) => updatePreview();

        foreach (string hex in presets) {
            var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(hex);
            var swatch = new System.Windows.Controls.Border {
                Width = 28, Height = 28, Margin = new Thickness(2),
                Background = new System.Windows.Media.SolidColorBrush(color),
                BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(60, 60, 60)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(3),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            var capturedColor = color;
            swatch.MouseLeftButtonDown += (s, e) => {
                rSlider.Value = capturedColor.R;
                gSlider.Value = capturedColor.G;
                bSlider.Value = capturedColor.B;
            };
            grid.Children.Add(swatch);
        }
        mainPanel.Children.Add(grid);
        mainPanel.Children.Add(preview);

        sliderPanel.Children.Add(rLabel); sliderPanel.Children.Add(rSlider);
        sliderPanel.Children.Add(gLabel); sliderPanel.Children.Add(gSlider);
        sliderPanel.Children.Add(bLabel); sliderPanel.Children.Add(bSlider);
        mainPanel.Children.Add(sliderPanel);

        // OK / Cancel buttons
        var btnPanel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var okBtn = new System.Windows.Controls.Button { Content = "OK", Width = 80, Height = 30, Margin = new Thickness(4, 0, 0, 0) };
        var cancelBtn = new System.Windows.Controls.Button { Content = "Cancel", Width = 80, Height = 30, Margin = new Thickness(4, 0, 0, 0) };
        okBtn.Click += (s, e) => { result = System.Windows.Media.Color.FromRgb(rVal, gVal, bVal); dlg.DialogResult = true; };
        cancelBtn.Click += (s, e) => { dlg.DialogResult = false; };
        btnPanel.Children.Add(cancelBtn);
        btnPanel.Children.Add(okBtn);
        mainPanel.Children.Add(btnPanel);

        dlg.Content = mainPanel;
        dlg.ShowDialog();
        return result;
    }

    // Sends the spell check state, active language, and custom dictionaries back to AHK via event routing
    private void SendSpellCheckInfo(RichTextBox rtb, string winId, string ctrlName) {
        try {
            bool isEnabled = rtb.SpellCheck.IsEnabled;
            string configLang = "en-US";
            if (_spellCheckLangs.ContainsKey(rtb.Name)) {
                configLang = _spellCheckLangs[rtb.Name];
            } else if (rtb.Language != null) {
                configLang = rtb.Language.ToString();
            }

            string currentLang = "Unknown";
            try {
                var scLang = rtb.Language;
                if (scLang != null) {
                    try {
                        var ci = new System.Globalization.CultureInfo(scLang.ToString());
                        currentLang = ci.DisplayName + " (" + ci.Name + ")";
                    } catch {
                        currentLang = scLang.ToString();
                    }
                    if (_spellCheckLangs.ContainsKey(rtb.Name) && _spellCheckLangs[rtb.Name] == "auto") {
                        currentLang += " (Autodetected)";
                    }
                }
            } catch { }

            string spellingDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Spelling");
            var dicts = new System.Collections.Generic.List<string>();
            try {
                if (System.IO.Directory.Exists(spellingDir)) {
                    foreach (var dir in System.IO.Directory.GetDirectories(spellingDir)) {
                        string langName = System.IO.Path.GetFileName(dir);
                        foreach (var f in System.IO.Directory.GetFiles(dir, "*.dic")) {
                            dicts.Add("📘 " + langName + " - " + System.IO.Path.GetFileName(f));
                        }
                        foreach (var f in System.IO.Directory.GetFiles(dir, "*.lex")) {
                            dicts.Add("📗 " + langName + " - " + System.IO.Path.GetFileName(f));
                        }
                    }
                }
            } catch { }
            try {
                foreach (var uriObj in rtb.SpellCheck.CustomDictionaries) {
                    var uri = uriObj as Uri;
                    dicts.Add("📙 Custom: " + (uri != null ? uri.LocalPath : uriObj.ToString()));
                }
            } catch { }

            string dictsJson = string.Join("|", dicts);
            string payload = isEnabled.ToString().ToLower() + "," + configLang + "," + currentLang + "," + dictsJson;
            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|SpellCheckInfo|" + LengthPrefix(payload) + "\n");
        } catch { }
    }

    private FlowDocument GetActiveDocument(RichTextBox rtb) {
        try {
            var pageReader = win.FindName(rtb.Name + "_PageReader") as FlowDocumentReader;
            if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                return pageReader.Document;
            }
        } catch { }
        return rtb.Document;
    }

    private string DetectLanguage(RichTextBox rtb) {
        try {
            FlowDocument activeDoc = GetActiveDocument(rtb);
            TextRange range = new TextRange(activeDoc.ContentStart, activeDoc.ContentEnd);
            string text = range.Text;
            if (string.IsNullOrWhiteSpace(text)) return "en-US";
            
            // Check for Chinese characters first (CJK Unified Ideographs: 4E00-9FFF)
            int cjkCount = 0;
            int totalCheck = Math.Min(text.Length, 2000);
            for (int i = 0; i < totalCheck; i++) {
                char c = text[i];
                if (c >= 0x4E00 && c <= 0x9FFF) {
                    cjkCount++;
                }
            }
            if (cjkCount > totalCheck * 0.05) {
                return "zh-CN";
            }
            
            // Check for Cyrillic (Russian) (0400-04FF)
            int cyrillicCount = 0;
            for (int i = 0; i < totalCheck; i++) {
                char c = text[i];
                if (c >= 0x0400 && c <= 0x04FF) {
                    cyrillicCount++;
                }
            }
            if (cyrillicCount > totalCheck * 0.1) {
                return "ru-RU";
            }
            
            // Check for Japanese (Hiragana/Katakana: 3040-309F / 30A0-30FF)
            int jpCount = 0;
            for (int i = 0; i < totalCheck; i++) {
                char c = text[i];
                if ((c >= 0x3040 && c <= 0x309F) || (c >= 0x30A0 && c <= 0x30FF)) {
                    jpCount++;
                }
            }
            if (jpCount > totalCheck * 0.05) {
                return "ja-JP";
            }
            
            // European languages stopwords frequency check
            string[] words = text.ToLower().Split(new[] { ' ', '\r', '\n', '\t', '.', ',', ';', '!', '?' }, StringSplitOptions.RemoveEmptyEntries);
            int enCount = 0;
            int frCount = 0;
            int deCount = 0;
            int esCount = 0;
            
            int wordLimit = Math.Min(words.Length, 200);
            for (int i = 0; i < wordLimit; i++) {
                string w = words[i];
                if (w == "the" || w == "and" || w == "of" || w == "to" || w == "is" || w == "that" || w == "in") enCount++;
                else if (w == "le" || w == "la" || w == "les" || w == "et" || w == "un" || w == "une" || w == "dans") frCount++;
                else if (w == "der" || w == "die" || w == "das" || w == "und" || w == "ist" || w == "in" || w == "zu") deCount++;
                else if (w == "el" || w == "la" || w == "los" || w == "y" || w == "en" || w == "un" || w == "una") esCount++;
            }
            
            if (frCount > enCount && frCount > deCount && frCount > esCount) return "fr-FR";
            if (deCount > enCount && deCount > frCount && deCount > esCount) return "de-DE";
            if (esCount > enCount && esCount > frCount && esCount > deCount) return "es-ES";
            
            return "en-US";
        } catch {
            return "en-US";
        }
    }

    private void _InsertPageBreakSpacers(RichTextBox rtb, string theme) {
        if (_isUpdatingSpacers) return;
        _isUpdatingSpacers = true;
        
        TextPointer caretPtr = null;
        try { caretPtr = rtb.CaretPosition; } catch { }
        
        rtb.BeginChange();
        try {
            _RemovePageBreakSpacers(rtb);
            _UnsplitParagraphs(rtb); // Rejoin any previously split paragraphs
            
            // Force visual layout pass to make character bounds queryable
            rtb.UpdateLayout();
            
            var doc = rtb.Document;
            var settings = doc.Tag as DocLayoutSettings;
            double pgW = 816;
            double pgH = 1056;
            Thickness pgPad = new Thickness(96, 72, 96, 72);
            if (settings != null) {
                pgW = settings.PageWidth;
                pgH = settings.PageHeight;
                pgPad = settings.PagePadding;
            }
            double pageContentHeight = pgH - (pgPad.Top + pgPad.Bottom);
            double availableWidth = pgW - (pgPad.Left + pgPad.Right);

            // Get document's first content Y position as origin
            double docOriginY = 0;
            try {
                var docStartRect = doc.ContentStart.GetCharacterRect(LogicalDirection.Forward);
                if (!docStartRect.IsEmpty && !double.IsInfinity(docStartRect.Top)) {
                    docOriginY = docStartRect.Top;
                }
            } catch { }

            // Gap visuals between pages
            double gapHeight = 40;
            double gapMargin = 10;
            double totalGapSize = gapHeight + gapMargin * 2; // 60px total

            // We need to iterate and potentially modify blocks, so we do multiple passes
            // Each pass: find the FIRST block that overflows, split/break it, insert spacer, re-layout
            int maxPasses = 100; // Safety limit
            int passCount = 0;
            double nextPageBreakY = docOriginY + pageContentHeight;
            int pageNumber = 1;

            while (passCount < maxPasses) {
                passCount++;
                var flatList = new System.Collections.Generic.List<Block>();
                _GetLayoutBlocks(doc.Blocks, flatList);

                Block overflowBlock = null;
                double overflowBlockTop = 0;
                double overflowBlockBottom = 0;
                double prevBottom = docOriginY;

                int startIndex = 0;
                if (_pageBreakSpacers.Count > 0) {
                    var lastSpacer = _pageBreakSpacers[_pageBreakSpacers.Count - 1];
                    int foundIdx = flatList.IndexOf(lastSpacer);
                    if (foundIdx != -1) {
                        startIndex = foundIdx + 1;
                    }
                }

                for (int idx = startIndex; idx < flatList.Count; idx++) {
                    var block = flatList[idx];
                    if (block is BlockUIContainer && (((BlockUIContainer)block).Tag as string) == "__PageBreakSpacer__") {
                        // Skip spacers — they are already positioned
                        continue;
                    }

                    double blockTop = 0;
                    double blockBottom = 0;
                    bool gotBounds = false;
                    try {
                        var rectStart = block.ContentStart.GetCharacterRect(LogicalDirection.Forward);
                        var rectEnd = block.ContentEnd.GetCharacterRect(LogicalDirection.Backward);
                        if (!rectStart.IsEmpty && !rectEnd.IsEmpty &&
                            !double.IsInfinity(rectStart.Top) && !double.IsInfinity(rectEnd.Bottom)) {
                            blockTop = rectStart.Top;
                            blockBottom = rectEnd.Bottom;
                            try {
                                blockTop -= block.Margin.Top;
                                blockBottom += block.Margin.Bottom;
                            } catch { }
                            gotBounds = true;
                        }
                    } catch { }

                    if (!gotBounds) {
                        double est = _EstimateBlockHeight(block, availableWidth);
                        blockTop = prevBottom;
                        blockBottom = blockTop + est;
                    }

                    // Case 1: Block SPANS the page boundary (starts before, ends after)
                    if (blockBottom > nextPageBreakY && blockTop < nextPageBreakY) {
                        overflowBlock = block;
                        overflowBlockTop = blockTop;
                        overflowBlockBottom = blockBottom;
                        break;
                    }
                    // Case 2: Block starts AFTER the page boundary entirely
                    // (the gap between previous content and this block crosses the boundary)
                    if (blockTop >= nextPageBreakY) {
                        overflowBlock = block;
                        overflowBlockTop = blockTop;
                        overflowBlockBottom = blockBottom;
                        break;
                    }
                    prevBottom = blockBottom;
                }

                if (overflowBlock == null) break; // No more overflows — done

                // We found a block that crosses the page boundary.
                // Try to split it at the line level if it's a Paragraph.
                pageNumber++;
                bool didSplit = false;

                if (overflowBlock is System.Windows.Documents.Paragraph) {
                    var para = (System.Windows.Documents.Paragraph)overflowBlock;
                    // Walk lines to find the split point
                    TextPointer splitPoint = _FindLineSplitPoint(para, nextPageBreakY);

                    if (splitPoint != null) {
                        // Split the paragraph at this line boundary
                        var secondHalf = _SplitParagraphAtPointer(para, splitPoint);
                        if (secondHalf != null) {
                            // Calculate remaining space on current page
                            double remainingSpace = 0;
                            try {
                                var newEndRect = para.ContentEnd.GetCharacterRect(LogicalDirection.Backward);
                                if (!newEndRect.IsEmpty && !double.IsInfinity(newEndRect.Bottom)) {
                                    remainingSpace = Math.Max(0, nextPageBreakY - newEndRect.Bottom);
                                }
                            } catch { }

                            // Insert spacer after the first half, then the second half after the spacer
                            var spacer = _CreatePageBreakSpacer(theme, pageNumber, remainingSpace);
                            try {
                                var siblings = para.SiblingBlocks;
                                if (siblings != null) {
                                    siblings.InsertAfter(para, spacer);
                                    siblings.InsertAfter(spacer, secondHalf);
                                    _pageBreakSpacers.Add(spacer);
                                    _splitParagraphs.Add(secondHalf); // Track for unsplitting later
                                    didSplit = true;
                                }
                            } catch { }
                        }
                    }
                }

                if (!didSplit) {
                    // Could not split (not a Paragraph, or split failed)
                    // Fall back: insert spacer BEFORE the block
                    double remainingSpace = Math.Max(0, nextPageBreakY - prevBottom);
                    var spacer = _CreatePageBreakSpacer(theme, pageNumber, remainingSpace);
                    try {
                        var siblings = overflowBlock.SiblingBlocks;
                        if (siblings != null) {
                            siblings.InsertBefore(overflowBlock, spacer);
                            _pageBreakSpacers.Add(spacer);
                        }
                    } catch { }
                }

                // Re-layout and recalculate next page break
                // One UpdateLayout call ensures the newly inserted spacer and split paragraphs
                // have valid layout information for GetCharacterRect queries
                rtb.UpdateLayout();
                // Find the actual Y position of the next page's start by locating
                // the first content block after the last spacer we inserted
                bool foundNextStart = false;
                var lastInsertedSpacer = _pageBreakSpacers[_pageBreakSpacers.Count - 1];
                Block nextContentBlock = lastInsertedSpacer.NextBlock;
                // Skip any spacer blocks
                while (nextContentBlock != null && nextContentBlock is BlockUIContainer &&
                       (((BlockUIContainer)nextContentBlock).Tag as string) == "__PageBreakSpacer__") {
                    nextContentBlock = nextContentBlock.NextBlock;
                }
                if (nextContentBlock != null) {
                    try {
                        var ncRect = nextContentBlock.ContentStart.GetCharacterRect(LogicalDirection.Forward);
                        if (!ncRect.IsEmpty && !double.IsInfinity(ncRect.Top)) {
                            // Account for top margin
                            double pageStartY = ncRect.Top;
                            try { pageStartY -= nextContentBlock.Margin.Top; } catch { }
                            nextPageBreakY = pageStartY + pageContentHeight;
                            foundNextStart = true;
                        }
                    } catch { }
                }
                if (!foundNextStart) {
                    // Fallback: just advance by one page from current boundary
                    nextPageBreakY += pageContentHeight + totalGapSize;
                }
            }
        } catch (Exception ex) {
            string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log");
            System.IO.File.AppendAllText(debugPath, string.Format("InsertSpacers ERROR: {0}\n", ex.ToString()));
        } finally {
            rtb.EndChange();
            _isUpdatingSpacers = false;
            if (caretPtr != null) {
                try { rtb.CaretPosition = caretPtr; } catch { }
            }
        }
    }

    // Find the TextPointer at the start of the first line that overflows the page boundary
    private TextPointer _FindLineSplitPoint(System.Windows.Documents.Paragraph para, double pageBreakY) {
        try {
            TextPointer lineStart = para.ContentStart.GetLineStartPosition(0);
            if (lineStart == null) lineStart = para.ContentStart;
            TextPointer lastGoodLine = null;

            int safetyLimit = 500;
            int lineCount = 0;
            while (lineStart != null && lineStart.CompareTo(para.ContentEnd) < 0 && lineCount < safetyLimit) {
                lineCount++;
                var lineRect = lineStart.GetCharacterRect(LogicalDirection.Forward);
                if (!lineRect.IsEmpty && !double.IsInfinity(lineRect.Top)) {
                    if (lineRect.Top >= pageBreakY) {
                        // This line starts at or past the page boundary — split here
                        return lineStart;
                    }
                    lastGoodLine = lineStart;
                }
                var nextLine = lineStart.GetLineStartPosition(1);
                if (nextLine == null || nextLine.CompareTo(lineStart) == 0) break;
                lineStart = nextLine;
            }
        } catch { }
        return null;
    }

    // Split a paragraph at a given TextPointer, returning the second half as a new Paragraph
    private System.Windows.Documents.Paragraph _SplitParagraphAtPointer(System.Windows.Documents.Paragraph para, TextPointer splitPoint) {
        try {
            // Verify split point is within the paragraph
            if (splitPoint.CompareTo(para.ContentStart) <= 0 || splitPoint.CompareTo(para.ContentEnd) >= 0)
                return null;

            var newPara = new System.Windows.Documents.Paragraph();
            // Copy paragraph-level formatting
            try { newPara.Margin = para.Margin; } catch { }
            try { newPara.LineHeight = para.LineHeight; } catch { }
            try { newPara.LineStackingStrategy = para.LineStackingStrategy; } catch { }
            try { newPara.TextAlignment = para.TextAlignment; } catch { }
            try { newPara.FontFamily = para.FontFamily; } catch { }
            try { newPara.FontSize = para.FontSize; } catch { }
            try { newPara.FontWeight = para.FontWeight; } catch { }
            try { newPara.FontStyle = para.FontStyle; } catch { }
            try { newPara.Foreground = para.Foreground; } catch { }
            try { newPara.Background = para.Background; } catch { }
            try { newPara.FlowDirection = para.FlowDirection; } catch { }
            try { newPara.TextIndent = para.TextIndent; } catch { }
            // Don't copy margin top for the second half (it's a continuation)
            newPara.Margin = new Thickness(para.Margin.Left, 0, para.Margin.Right, para.Margin.Bottom);
            // First half loses bottom margin
            para.Margin = new Thickness(para.Margin.Left, para.Margin.Top, para.Margin.Right, 0);

            // Snapshot the inlines list
            var allInlines = new System.Collections.Generic.List<Inline>();
            foreach (var il in para.Inlines) {
                allInlines.Add(il);
            }

            bool foundSplit = false;
            var inlinesToMove = new System.Collections.Generic.List<Inline>();

            for (int i = 0; i < allInlines.Count; i++) {
                var inline = allInlines[i];

                if (!foundSplit) {
                    // Check if split point is within or before this inline
                    if (splitPoint.CompareTo(inline.ElementEnd) <= 0) {
                        foundSplit = true;

                        if (inline is System.Windows.Documents.Run && splitPoint.CompareTo(inline.ContentStart) > 0) {
                            // Split point is INSIDE this Run
                            var run = (System.Windows.Documents.Run)inline;
                            string textBefore = new TextRange(run.ContentStart, splitPoint).Text;
                            string fullText = run.Text;
                            string textAfter = "";
                            if (textBefore.Length < fullText.Length) {
                                textAfter = fullText.Substring(textBefore.Length);
                            }

                            if (textAfter.Length > 0) {
                                run.Text = textBefore;
                                var newRun = new System.Windows.Documents.Run(textAfter);
                                _CopyRunFormatting(run, newRun);
                                newPara.Inlines.Add(newRun);
                            }
                        } else {
                            // Split point is at or before this inline — move entire inline
                            inlinesToMove.Add(inline);
                        }
                    }
                    // else: this inline is entirely before the split point — keep it
                } else {
                    // This inline is after the split — move it
                    inlinesToMove.Add(inline);
                }
            }

            // Move inlines to new paragraph
            foreach (var il in inlinesToMove) {
                try {
                    para.Inlines.Remove(il);
                    newPara.Inlines.Add(il);
                } catch { }
            }

            if (newPara.Inlines.Count == 0 && new TextRange(newPara.ContentStart, newPara.ContentEnd).Text.Length == 0) {
                return null; // Nothing to split
            }

            return newPara;
        } catch {
            return null;
        }
    }

    private void _CopyRunFormatting(System.Windows.Documents.Run source, System.Windows.Documents.Run target) {
        try { target.FontFamily = source.FontFamily; } catch { }
        try { target.FontSize = source.FontSize; } catch { }
        try { target.FontWeight = source.FontWeight; } catch { }
        try { target.FontStyle = source.FontStyle; } catch { }
        try { target.Foreground = source.Foreground; } catch { }
        try { target.Background = source.Background; } catch { }
        try { target.TextDecorations = source.TextDecorations; } catch { }
        try { target.FlowDirection = source.FlowDirection; } catch { }
    }

    // Track split paragraphs for unsplitting when re-paginating
    private System.Collections.Generic.List<Block> _splitParagraphs = new System.Collections.Generic.List<Block>();

    private void _UnsplitParagraphs(RichTextBox rtb) {
        // Re-join previously split paragraphs: merge second half back into first half
        foreach (var block in _splitParagraphs) {
            try {
                if (block is System.Windows.Documents.Paragraph) {
                    var secondHalf = (System.Windows.Documents.Paragraph)block;
                    // Find the paragraph before the spacer before this one
                    var prevBlock = secondHalf.PreviousBlock;
                    if (prevBlock != null && prevBlock is BlockUIContainer && 
                        (((BlockUIContainer)prevBlock).Tag as string) == "__PageBreakSpacer__") {
                        var spacer = prevBlock;
                        var firstHalf = spacer.PreviousBlock as System.Windows.Documents.Paragraph;
                        if (firstHalf != null) {
                            // Move all inlines from secondHalf back to firstHalf
                            var inlines = new System.Collections.Generic.List<Inline>();
                            foreach (var il in secondHalf.Inlines) {
                                inlines.Add(il);
                            }
                            foreach (var il in inlines) {
                                try {
                                    secondHalf.Inlines.Remove(il);
                                    firstHalf.Inlines.Add(il);
                                } catch { }
                            }
                            // Restore margins
                            firstHalf.Margin = new Thickness(firstHalf.Margin.Left, firstHalf.Margin.Top, firstHalf.Margin.Right, secondHalf.Margin.Bottom);
                            // Remove the empty second half
                            try {
                                if (secondHalf.SiblingBlocks != null) secondHalf.SiblingBlocks.Remove(secondHalf);
                                else rtb.Document.Blocks.Remove(secondHalf);
                            } catch { }
                        }
                    }
                }
            } catch { }
        }
        _splitParagraphs.Clear();
    }

    private void _RemovePageBreakSpacers(RichTextBox rtb) {
        var doc = rtb.Document;
        foreach (var spacer in _pageBreakSpacers) {
            try {
                if (spacer.SiblingBlocks != null) {
                    spacer.SiblingBlocks.Remove(spacer);
                } else {
                    doc.Blocks.Remove(spacer);
                }
            } catch { }
        }
        _pageBreakSpacers.Clear();
        
        var toRemove = new System.Collections.Generic.List<Block>();
        _FindOrphanedSpacers(doc.Blocks, toRemove);
        foreach (var block in toRemove) {
            try {
                if (block.SiblingBlocks != null) {
                    block.SiblingBlocks.Remove(block);
                } else {
                    doc.Blocks.Remove(block);
                }
            } catch { }
        }
    }

    private void _FindOrphanedSpacers(System.Windows.Documents.BlockCollection blocks, System.Collections.Generic.List<Block> toRemove) {
        foreach (var block in blocks) {
            if (block is System.Windows.Documents.Section) {
                _FindOrphanedSpacers(((System.Windows.Documents.Section)block).Blocks, toRemove);
            } else if (block is BlockUIContainer && (((BlockUIContainer)block).Tag as string) == "__PageBreakSpacer__") {
                toRemove.Add(block);
            }
        }
    }

    private BlockUIContainer _CreatePageBreakSpacer(string theme, int pageNum, double fillHeight = 0) {
        bool isDark = (theme == "Dark");
        
        var spacerPanel = new StackPanel();
        spacerPanel.Orientation = Orientation.Vertical;
        spacerPanel.Margin = new Thickness(-150, 0, -150, 0);
        spacerPanel.Focusable = false;
        spacerPanel.IsHitTestVisible = false;

        // Part 1: Fill remaining page space (transparent — looks like part of the page)
        if (fillHeight > 2) {
            var fillArea = new System.Windows.Controls.Border();
            fillArea.Height = fillHeight;
            fillArea.Background = System.Windows.Media.Brushes.Transparent;
            fillArea.IsHitTestVisible = false;
            spacerPanel.Children.Add(fillArea);
        }

        // Part 2: Visual gap between pages
        var spacerGrid = new Grid();
        spacerGrid.Height = 40;
        spacerGrid.Margin = new Thickness(0, 10, 0, 10);
        spacerGrid.Focusable = false;
        spacerGrid.IsHitTestVisible = false;

        // Background container representing the gap (matches surrounding canvas theme)
        var bgBorder = new System.Windows.Controls.Border();
        bgBorder.BorderThickness = new Thickness(0, 1, 0, 1);
        bgBorder.IsHitTestVisible = false;
        
        if (theme == "Dark") {
            bgBorder.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(18, 18, 18));
            bgBorder.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(51, 51, 51));
        } else if (theme == "Theme") {
            bgBorder.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "DropdownBg");
            bgBorder.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, "ControlBorder");
        } else {
            bgBorder.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "DropdownBg");
            bgBorder.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
        }

        spacerGrid.Children.Add(bgBorder);

        spacerPanel.Children.Add(spacerGrid);

        var container = new BlockUIContainer(spacerPanel);
        container.Tag = "__PageBreakSpacer__";
        container.Focusable = false;
        container.Margin = new Thickness(0);
        container.Padding = new Thickness(0);
        return container;
    }

    private double _EstimateBlockHeight(Block block, double availableWidth) {
        if (block is System.Windows.Documents.Paragraph) {
            var p = (System.Windows.Documents.Paragraph)block;
            string text = "";
            try {
                text = new TextRange(p.ContentStart, p.ContentEnd).Text;
            } catch { }
            
            double fontSize = 14;
            try {
                double rawFs = p.FontSize;
                if (!double.IsNaN(rawFs) && rawFs > 0) {
                    fontSize = rawFs;
                }
            } catch { }

            double lineHeight = fontSize * 1.5;
            double charsPerLine = Math.Max(1, availableWidth / (fontSize * 0.55));
            int lines = 1;
            if (text != null && text.Length > 0 && charsPerLine > 0) {
                try {
                    lines = Math.Max(1, (int)Math.Ceiling(text.Length / charsPerLine));
                } catch { }
            }

            double top = 0;
            double bottom = 0;
            try {
                double rawTop = p.Margin.Top;
                if (!double.IsNaN(rawTop)) top = rawTop;
            } catch { }
            try {
                double rawBottom = p.Margin.Bottom;
                if (!double.IsNaN(rawBottom)) bottom = rawBottom;
            } catch { }

            double est = lines * lineHeight + top + bottom + 4;
            
            try {
                string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log");
                System.IO.File.AppendAllText(debugPath, string.Format("EstimateBlockHeight: textLen={0}, fontSize={1}, lineHeight={2}, charsPerLine={3}, lines={4}, margin.top={5}, margin.bottom={6}, est={7}\n",
                    text != null ? text.Length : 0, fontSize, lineHeight, charsPerLine, lines, top, bottom, est));
            } catch { }

            return double.IsNaN(est) ? 24 : est;
        }
        if (block is System.Windows.Documents.Table) {
            var tbl = (System.Windows.Documents.Table)block;
            int rowCount = 0;
            foreach (var rg in tbl.RowGroups) rowCount += rg.Rows.Count;
            return rowCount * 32 + 20;
        }
        if (block is System.Windows.Documents.List) {
            return ((System.Windows.Documents.List)block).ListItems.Count * 26 + 10;
        }
        if (block is BlockUIContainer) return 40;
        return 24;
    }

    // === Non-Destructive Dark Mode ===
    // Use Dictionary keyed by DependencyObject (reference equality by default)
    private System.Collections.Generic.Dictionary<DependencyObject, System.Windows.Media.Brush[]>
        _darkModeStore = new System.Collections.Generic.Dictionary<DependencyObject, System.Windows.Media.Brush[]>();
    private bool _isDarkMode = false;
    private string _preDarkModeRtf = null;

    private void ApplyDarkModeToDocument(FlowDocument doc) {
        if (_isDarkMode) return;
        _darkModeStore = new System.Collections.Generic.Dictionary<DependencyObject, System.Windows.Media.Brush[]>();
        _isDarkMode = true;
        ApplyDarkModeToElement(doc);
    }

    private void RestoreDocumentColors(FlowDocument doc) {
        if (!_isDarkMode) return;
        
        RestoreElementColors(doc);
        
        _darkModeStore = new System.Collections.Generic.Dictionary<DependencyObject, System.Windows.Media.Brush[]>();
        _isDarkMode = false;
    }

    private void StoreOriginal(DependencyObject element, System.Windows.Media.Brush fg, System.Windows.Media.Brush bg) {
        _darkModeStore[element] = new System.Windows.Media.Brush[] { fg, bg };
    }

    private bool TryGetOriginal(DependencyObject element, out System.Windows.Media.Brush fg, out System.Windows.Media.Brush bg) {
        System.Windows.Media.Brush[] stored;
        if (_darkModeStore.TryGetValue(element, out stored)) {
            fg = stored[0];
            bg = stored[1];
            return true;
        }
        fg = null; bg = null;
        return false;
    }

    private void ApplyDarkModeToElement(DependencyObject obj) {
        if (obj == null) return;
        
        if (obj is System.Windows.Documents.TextElement) {
            var te = (System.Windows.Documents.TextElement)obj;
            var localFg = te.ReadLocalValue(System.Windows.Documents.TextElement.ForegroundProperty) as System.Windows.Media.Brush;
            var localBg = te.ReadLocalValue(System.Windows.Documents.TextElement.BackgroundProperty) as System.Windows.Media.Brush;
            StoreOriginal(te, localFg, localBg);
            
            if (te is System.Windows.Documents.Run) {
                var run = (System.Windows.Documents.Run)te;
                if (run.Foreground is System.Windows.Media.SolidColorBrush) {
                    var origFg = ((System.Windows.Media.SolidColorBrush)run.Foreground).Color;
                    if (origFg.R == 0 && origFg.G == 0 && origFg.B == 0) {
                        run.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
                    } else {
                        byte grey = (byte)(0.299 * origFg.R + 0.587 * origFg.G + 0.114 * origFg.B);
                        byte invGrey = (byte)Math.Min(255, 255 - grey + 60);
                        run.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(invGrey, invGrey, invGrey));
                    }
                } else {
                    run.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
                }
                
                if (run.Background != null && run.Background is System.Windows.Media.SolidColorBrush) {
                    var origBg = ((System.Windows.Media.SolidColorBrush)run.Background).Color;
                    run.Background = new System.Windows.Media.SolidColorBrush(ToDarkGreyscale(origBg));
                }
            } else if (te is System.Windows.Documents.Hyperlink) {
                te.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(108, 180, 238));
            } else if (te is System.Windows.Documents.Paragraph || te is System.Windows.Documents.TableCell || te is System.Windows.Documents.List) {
                te.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
                if (te.Background != null && te.Background is System.Windows.Media.SolidColorBrush) {
                    var origBg = ((System.Windows.Media.SolidColorBrush)te.Background).Color;
                    te.Background = new System.Windows.Media.SolidColorBrush(ToDarkGreyscale(origBg));
                }
            } else if (te is System.Windows.Documents.Table) {
                var table = (System.Windows.Documents.Table)te;
                var localBorder = table.ReadLocalValue(System.Windows.Documents.Block.BorderBrushProperty) as System.Windows.Media.Brush;
                StoreOriginal(table, localBorder, null);
                table.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(60, 60, 60));
            }
        }
        
        foreach (var child in LogicalTreeHelper.GetChildren(obj)) {
            if (child is DependencyObject) {
                ApplyDarkModeToElement((DependencyObject)child);
            }
        }
    }

    private void RestoreElementColors(DependencyObject obj) {
        if (obj == null) return;
        
        if (obj is System.Windows.Documents.TextElement) {
            var te = (System.Windows.Documents.TextElement)obj;
            System.Windows.Media.Brush fg, bg;
            if (TryGetOriginal(te, out fg, out bg)) {
                if (te is System.Windows.Documents.Table) {
                    if (fg == null) ((System.Windows.Documents.Table)te).ClearValue(System.Windows.Documents.Block.BorderBrushProperty);
                    else ((System.Windows.Documents.Table)te).BorderBrush = fg;
                } else {
                    if (fg == null) te.ClearValue(System.Windows.Documents.TextElement.ForegroundProperty);
                    else te.Foreground = fg;
                    
                    if (bg == null) te.ClearValue(System.Windows.Documents.TextElement.BackgroundProperty);
                    else te.Background = bg;
                }
            }
        }
        
        foreach (var child in LogicalTreeHelper.GetChildren(obj)) {
            if (child is DependencyObject) {
                RestoreElementColors((DependencyObject)child);
            }
        }
    }

    private System.Windows.Media.Color ToDarkGreyscale(System.Windows.Media.Color c) {
        byte grey = (byte)(0.299 * c.R + 0.587 * c.G + 0.114 * c.B);
        byte dark = (byte)(20 + (grey * 30 / 255));
        return System.Windows.Media.Color.FromRgb(dark, dark, dark);
    }

    private void FlowDocumentToDocx(FlowDocument flowDoc, string filePath) {
        using (var wordDoc = WordprocessingDocument.Create(filePath, WordprocessingDocumentType.Document)) {
            var mainPart = wordDoc.AddMainDocumentPart();
            mainPart.Document = new DocumentFormat.OpenXml.Wordprocessing.Document();
            var body = new DocumentFormat.OpenXml.Wordprocessing.Body();

            ConvertWpfBlocksToOpenXml(flowDoc.Blocks, body, mainPart);

            mainPart.Document.Append(body);
            mainPart.Document.Save();
        }
    }

    private void ConvertWpfBlocksToOpenXml(System.Windows.Documents.BlockCollection blocks, DocumentFormat.OpenXml.Wordprocessing.Body body, MainDocumentPart mainPart) {
        foreach (var block in blocks) {
            if (block is System.Windows.Documents.Paragraph) {
                var flowPara = (System.Windows.Documents.Paragraph)block;
                var oxPara = ConvertWpfParagraphToOpenXml(flowPara, mainPart);
                body.AppendChild(oxPara);
            } else if (block is System.Windows.Documents.Table) {
                var flowTable = (System.Windows.Documents.Table)block;
                var oxTable = ConvertWpfTableToOpenXml(flowTable, mainPart);
                body.AppendChild(oxTable);
            } else if (block is System.Windows.Documents.List) {
                var flowList = (System.Windows.Documents.List)block;
                foreach (var li in flowList.ListItems) {
                    ConvertWpfBlocksToOpenXml(li.Blocks, body, mainPart);
                }
            } else if (block is System.Windows.Documents.Section) {
                var flowSection = (System.Windows.Documents.Section)block;
                ConvertWpfBlocksToOpenXml(flowSection.Blocks, body, mainPart);
            }
        }
    }

    private DocumentFormat.OpenXml.Wordprocessing.Paragraph ConvertWpfParagraphToOpenXml(System.Windows.Documents.Paragraph flowPara, MainDocumentPart mainPart) {
        var oxPara = new DocumentFormat.OpenXml.Wordprocessing.Paragraph();

        var pPr = new DocumentFormat.OpenXml.Wordprocessing.ParagraphProperties();
        
        string styleId = flowPara.Tag as string ?? "";
        if (!string.IsNullOrEmpty(styleId)) {
            pPr.Append(new DocumentFormat.OpenXml.Wordprocessing.ParagraphStyleId { Val = styleId });
        }

        JustificationValues jv = JustificationValues.Left;
        switch (flowPara.TextAlignment) {
            case System.Windows.TextAlignment.Center: jv = JustificationValues.Center; break;
            case System.Windows.TextAlignment.Right: jv = JustificationValues.Right; break;
            case System.Windows.TextAlignment.Justify: jv = JustificationValues.Both; break;
        }
        pPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Justification { Val = jv });
        oxPara.Append(pPr);

        foreach (var inline in flowPara.Inlines) {
            AppendWpfInlineToOpenXmlParagraph(inline, oxPara, mainPart);
        }
        return oxPara;
    }

    private void AppendWpfInlineToOpenXmlParagraph(System.Windows.Documents.Inline inline, DocumentFormat.OpenXml.Wordprocessing.Paragraph oxPara, MainDocumentPart mainPart) {
        if (inline is System.Windows.Documents.Run) {
            var flowRun = (System.Windows.Documents.Run)inline;
            var oxRun = new DocumentFormat.OpenXml.Wordprocessing.Run();
            var rPr = new DocumentFormat.OpenXml.Wordprocessing.RunProperties();

            if (flowRun.FontWeight == FontWeights.Bold)
                rPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Bold());
            if (flowRun.FontStyle == FontStyles.Italic)
                rPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Italic());
            if (flowRun.TextDecorations != null && flowRun.TextDecorations == TextDecorations.Underline)
                rPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Underline { Val = UnderlineValues.Single });
            if (flowRun.FontSize != 14) {
                int halfPoints = (int)(flowRun.FontSize * 2);
                rPr.Append(new DocumentFormat.OpenXml.Wordprocessing.FontSize { Val = halfPoints.ToString() });
            }
            if (flowRun.Foreground is System.Windows.Media.SolidColorBrush) {
                var color = ((System.Windows.Media.SolidColorBrush)flowRun.Foreground).Color;
                rPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Color { Val = color.R.ToString("X2") + color.G.ToString("X2") + color.B.ToString("X2") });
            }
            if (flowRun.Background is System.Windows.Media.SolidColorBrush) {
                rPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Highlight { Val = HighlightColorValues.Yellow });
            }

            oxRun.Append(rPr);
            oxRun.Append(new DocumentFormat.OpenXml.Wordprocessing.Text(flowRun.Text) { Space = SpaceProcessingModeValues.Preserve });
            oxPara.Append(oxRun);
        }
        else if (inline is System.Windows.Documents.Hyperlink) {
            var flowLink = (System.Windows.Documents.Hyperlink)inline;
            string linkUrl = flowLink.NavigateUri != null ? flowLink.NavigateUri.ToString() : "";
            
            string linkText = "";
            foreach (var linkInline in flowLink.Inlines) {
                if (linkInline is System.Windows.Documents.Run) {
                    linkText += ((System.Windows.Documents.Run)linkInline).Text;
                }
            }
            if (string.IsNullOrEmpty(linkText)) linkText = linkUrl;

            if (!string.IsNullOrEmpty(linkUrl)) {
                string relId = "rIdH" + Guid.NewGuid().ToString().Substring(0, 8);
                try {
                    mainPart.AddHyperlinkRelationship(new Uri(linkUrl, UriKind.RelativeOrAbsolute), true, relId);
                    var oxHl = new DocumentFormat.OpenXml.Wordprocessing.Hyperlink { Id = relId };
                    
                    var oxRun = new DocumentFormat.OpenXml.Wordprocessing.Run();
                    var rPr = new DocumentFormat.OpenXml.Wordprocessing.RunProperties(
                        new DocumentFormat.OpenXml.Wordprocessing.Underline { Val = UnderlineValues.Single },
                        new DocumentFormat.OpenXml.Wordprocessing.Color { Val = "1155CC" }
                    );
                    oxRun.Append(rPr);
                    oxRun.Append(new DocumentFormat.OpenXml.Wordprocessing.Text(linkText) { Space = SpaceProcessingModeValues.Preserve });
                    oxHl.Append(oxRun);
                    oxPara.Append(oxHl);
                } catch {
                    var oxRun = new DocumentFormat.OpenXml.Wordprocessing.Run();
                    oxRun.Append(new DocumentFormat.OpenXml.Wordprocessing.Text(linkText));
                    oxPara.Append(oxRun);
                }
            }
        }
        else if (inline is System.Windows.Documents.Span) {
            var flowSpan = (System.Windows.Documents.Span)inline;
            foreach (var childInline in flowSpan.Inlines) {
                AppendWpfInlineToOpenXmlParagraph(childInline, oxPara, mainPart);
            }
        }
        else if (inline is InlineUIContainer) {
            var container = (InlineUIContainer)inline;
            if (container.Child is System.Windows.Controls.Image) {
                var img = (System.Windows.Controls.Image)container.Child;
                var bSrc = img.Source as System.Windows.Media.Imaging.BitmapSource;
                if (bSrc != null) {
                    try {
                        var imgPart = mainPart.AddImagePart(ImagePartType.Png);
                        using (var stream = imgPart.GetStream()) {
                            var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
                            encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bSrc));
                            encoder.Save(stream);
                        }
                        string relId = mainPart.GetIdOfPart(imgPart);
                        
                        double width = img.Width;
                        double height = img.Height;
                        if (double.IsNaN(width) || width <= 0) width = img.ActualWidth;
                        if (double.IsNaN(width) || width <= 0) width = bSrc.PixelWidth;
                        
                        if (double.IsNaN(height) || height <= 0) height = img.ActualHeight;
                        if (double.IsNaN(height) || height <= 0) height = bSrc.PixelHeight;

                        if (width > 650) {
                            height = height * 650 / width;
                            width = 650;
                        }

                        var drawing = CreateDrawingElement(relId, (int)width, (int)height);
                        var oxRun = new DocumentFormat.OpenXml.Wordprocessing.Run();
                        oxRun.Append(drawing);
                        oxPara.Append(oxRun);
                    } catch {}
                }
            }
        }
    }

    private DocumentFormat.OpenXml.Wordprocessing.Table ConvertWpfTableToOpenXml(System.Windows.Documents.Table flowTable, MainDocumentPart mainPart) {
        var oxTable = new DocumentFormat.OpenXml.Wordprocessing.Table();
        var tblPr = new DocumentFormat.OpenXml.Wordprocessing.TableProperties(
            new DocumentFormat.OpenXml.Wordprocessing.TableWidth { Type = TableWidthUnitValues.Pct, Width = "5000" },
            new DocumentFormat.OpenXml.Wordprocessing.TableBorders(
                new TopBorder { Val = BorderValues.Single, Size = 4, Space = 0, Color = "CCCCCC" },
                new BottomBorder { Val = BorderValues.Single, Size = 12, Space = 0, Color = "2F5597" },
                new LeftBorder { Val = BorderValues.None },
                new RightBorder { Val = BorderValues.None },
                new InsideHorizontalBorder { Val = BorderValues.Single, Size = 4, Space = 0, Color = "E0E0E0" },
                new InsideVerticalBorder { Val = BorderValues.None }
            )
        );
        oxTable.AppendChild(tblPr);

        var tblGrid = new DocumentFormat.OpenXml.Wordprocessing.TableGrid();
        if (flowTable.Columns.Count > 0) {
            for (int i = 0; i < flowTable.Columns.Count; i++) {
                tblGrid.AppendChild(new DocumentFormat.OpenXml.Wordprocessing.GridColumn());
            }
        } else {
            tblGrid.AppendChild(new DocumentFormat.OpenXml.Wordprocessing.GridColumn());
        }
        oxTable.AppendChild(tblGrid);

        foreach (var rg in flowTable.RowGroups) {
            foreach (var row in rg.Rows) {
                var oxRow = new DocumentFormat.OpenXml.Wordprocessing.TableRow();
                foreach (var cell in row.Cells) {
                    var oxCell = new DocumentFormat.OpenXml.Wordprocessing.TableCell();
                    
                    var tcPr = new DocumentFormat.OpenXml.Wordprocessing.TableCellProperties();
                    if (cell.Background is System.Windows.Media.SolidColorBrush) {
                        var col = ((System.Windows.Media.SolidColorBrush)cell.Background).Color;
                        string hex = col.R.ToString("X2") + col.G.ToString("X2") + col.B.ToString("X2");
                        tcPr.Append(new DocumentFormat.OpenXml.Wordprocessing.Shading { Val = ShadingPatternValues.Clear, Color = "auto", Fill = hex });
                    }
                    if (cell.ColumnSpan > 1) {
                        tcPr.Append(new DocumentFormat.OpenXml.Wordprocessing.GridSpan { Val = cell.ColumnSpan });
                    }
                    oxCell.Append(tcPr);

                    foreach (var b in cell.Blocks) {
                        if (b is System.Windows.Documents.Paragraph) {
                            var flowPara = (System.Windows.Documents.Paragraph)b;
                            oxCell.Append(ConvertWpfParagraphToOpenXml(flowPara, mainPart));
                        }
                    }
                    if (oxCell.ChildElements.Count == 0) {
                        oxCell.Append(new DocumentFormat.OpenXml.Wordprocessing.Paragraph());
                    }
                    oxRow.Append(oxCell);
                }
                oxTable.Append(oxRow);
            }
        }
        return oxTable;
    }

    private DocumentFormat.OpenXml.Wordprocessing.Drawing CreateDrawingElement(string relationshipId, int widthPx, int heightPx) {
        if (widthPx <= 0) widthPx = 300;
        if (heightPx <= 0) heightPx = 200;
        long cx = (long)(widthPx / 96.0 * 914400.0);
        long cy = (long)(heightPx / 96.0 * 914400.0);

        var drawing = new DocumentFormat.OpenXml.Wordprocessing.Drawing(
            new DocumentFormat.OpenXml.Drawing.Wordprocessing.Inline(
                new DocumentFormat.OpenXml.Drawing.Wordprocessing.Extent() { Cx = cx, Cy = cy },
                new DocumentFormat.OpenXml.Drawing.Wordprocessing.EffectExtent() { LeftEdge = 0L, TopEdge = 0L, RightEdge = 0L, BottomEdge = 0L },
                new DocumentFormat.OpenXml.Drawing.Wordprocessing.DocProperties() { Id = 1U, Name = "Image" },
                new DocumentFormat.OpenXml.Drawing.Wordprocessing.NonVisualGraphicFrameDrawingProperties(
                    new DocumentFormat.OpenXml.Drawing.GraphicFrameLocks() { NoChangeAspect = true }),
                new DocumentFormat.OpenXml.Drawing.Graphic(
                    new DocumentFormat.OpenXml.Drawing.GraphicData(
                        new DocumentFormat.OpenXml.Drawing.Pictures.Picture(
                            new DocumentFormat.OpenXml.Drawing.Pictures.NonVisualPictureProperties(
                                new DocumentFormat.OpenXml.Drawing.Pictures.NonVisualDrawingProperties() { Id = 2U, Name = "Image.png" },
                                new DocumentFormat.OpenXml.Drawing.Pictures.NonVisualPictureDrawingProperties()),
                            new DocumentFormat.OpenXml.Drawing.Pictures.BlipFill(
                                new DocumentFormat.OpenXml.Drawing.Blip() { Embed = relationshipId, CompressionState = DocumentFormat.OpenXml.Drawing.BlipCompressionValues.Print },
                                new DocumentFormat.OpenXml.Drawing.Stretch(
                                    new DocumentFormat.OpenXml.Drawing.FillRectangle())),
                            new DocumentFormat.OpenXml.Drawing.Pictures.ShapeProperties(
                                new DocumentFormat.OpenXml.Drawing.Transform2D(
                                    new DocumentFormat.OpenXml.Drawing.Offset() { X = 0L, Y = 0L },
                                    new DocumentFormat.OpenXml.Drawing.Extents() { Cx = cx, Cy = cy }),
                                new DocumentFormat.OpenXml.Drawing.PresetGeometry() { Preset = DocumentFormat.OpenXml.Drawing.ShapeTypeValues.Rectangle }))
                    ) { Uri = "http://schemas.openxmlformats.org/drawingml/2006/picture" }
                )
            ) { DistanceFromTop = 0U, DistanceFromBottom = 0U, DistanceFromLeft = 0U, DistanceFromRight = 0U }
        );
        return drawing;
    }

    private void TraverseBlocks(System.Windows.Documents.BlockCollection blocks, Action<System.Windows.Documents.Block> action) {
        foreach (var block in blocks) {
            action(block);
            if (block is System.Windows.Documents.Section) {
                TraverseBlocks(((System.Windows.Documents.Section)block).Blocks, action);
            } else if (block is System.Windows.Documents.List) {
                foreach (var li in ((System.Windows.Documents.List)block).ListItems) {
                    TraverseBlocks(li.Blocks, action);
                }
            } else if (block is System.Windows.Documents.Table) {
                foreach (var rg in ((System.Windows.Documents.Table)block).RowGroups) {
                    foreach (var row in rg.Rows) {
                        foreach (var cell in row.Cells) {
                            TraverseBlocks(cell.Blocks, action);
                        }
                    }
                }
            }
        }
    }

    private void TraverseInlines(System.Windows.Documents.InlineCollection inlines, Action<System.Windows.Documents.Inline> action) {
        foreach (var inline in inlines) {
            action(inline);
            if (inline is System.Windows.Documents.Span) {
                TraverseInlines(((System.Windows.Documents.Span)inline).Inlines, action);
            }
        }
    }

    private FlowDocument DocToFlowDocument(string filePath) {
        // .doc format requires COM interop or NPOI — try basic text extraction as fallback
        var doc = new FlowDocument();
        doc.FontFamily = new System.Windows.Media.FontFamily("Segoe UI");
        doc.FontSize = 14;
        doc.PagePadding = new Thickness(40);
        try {
            // Attempt RTF conversion via RichTextBox (works for some .doc files)
            byte[] bytes = System.IO.File.ReadAllBytes(filePath);
            // Check for RTF magic bytes
            string header = Encoding.ASCII.GetString(bytes, 0, Math.Min(5, bytes.Length));
            if (header.StartsWith("{\\rtf")) {
                var range = new TextRange(doc.ContentStart, doc.ContentEnd);
                using (var ms = new System.IO.MemoryStream(bytes)) {
                    range.Load(ms, DataFormats.Rtf);
                }
            } else {
                // Binary .doc — extract plain text as fallback
                var sb = new StringBuilder();
                for (int i = 0; i < bytes.Length; i++) {
                    if (bytes[i] >= 32 && bytes[i] < 127) sb.Append((char)bytes[i]);
                    else if (bytes[i] == 13 || bytes[i] == 10) sb.Append('\n');
                }
                doc.Blocks.Add(new System.Windows.Documents.Paragraph(
                    new System.Windows.Documents.Run(sb.ToString())));
            }
        } catch {
            doc.Blocks.Add(new System.Windows.Documents.Paragraph(
                new System.Windows.Documents.Run("Error: Could not open .doc file. For full .doc support, NPOI library is required.")));
        }
        doc.Tag = new DocLayoutSettings {
            PageWidth = 816,
            PageHeight = 1056,
            PagePadding = doc.PagePadding
        };
        return doc;
    }

    private struct CharPosition {
        public TextPointer Start;
        public TextPointer End;
        public char Character;
    }

    private System.Collections.Generic.List<CharPosition> BuildCharPositionMap(FlowDocument doc) {
        var map = new System.Collections.Generic.List<CharPosition>();
        TextPointer current = doc.ContentStart;
        while (current != null && current.CompareTo(doc.ContentEnd) < 0) {
            TextPointerContext context = current.GetPointerContext(LogicalDirection.Forward);
            if (context == TextPointerContext.Text) {
                string runText = current.GetTextInRun(LogicalDirection.Forward);
                for (int i = 0; i < runText.Length; i++) {
                    map.Add(new CharPosition {
                        Start = current.GetPositionAtOffset(i),
                        End = current.GetPositionAtOffset(i + 1),
                        Character = runText[i]
                    });
                }
            } else if (context == TextPointerContext.ElementEnd) {
                DependencyObject element = current.Parent;
                if (element is System.Windows.Documents.Paragraph || element is System.Windows.Documents.LineBreak) {
                    map.Add(new CharPosition {
                        Start = current,
                        End = current,
                        Character = '\r'
                    });
                    map.Add(new CharPosition {
                        Start = current,
                        End = current,
                        Character = '\n'
                    });
                }
            }
            current = current.GetNextContextPosition(LogicalDirection.Forward);
        }
        return map;
    }

    private void ClearSearchHighlights(RichTextBox rtb) {
        // Walk ALL inlines in the document and remove our highlight brush by color.
        // We cannot rely on stored TextRange objects because WPF splits Runs when
        // ApplyPropertyValue is called, making the original ranges stale.
        try {
            var highlightColor = _highlightBrush.Color;
            var activeColor = _activeMatchBrush.Color;
            TextPointer pos = rtb.Document.ContentStart;
            System.Windows.Documents.Inline lastProcessed = null;
            while (pos != null && pos.CompareTo(rtb.Document.ContentEnd) < 0) {
                var il = pos.Parent as System.Windows.Documents.Inline;
                if (il != null && il != lastProcessed) {
                    lastProcessed = il;
                    var scb = il.Background as System.Windows.Media.SolidColorBrush;
                    if (scb != null && (scb.Color == highlightColor || scb.Color == activeColor)) {
                        il.ClearValue(System.Windows.Documents.Inline.BackgroundProperty);
                    }
                }
                pos = pos.GetNextContextPosition(LogicalDirection.Forward);
            }
        } catch { }
        _highlightedRanges.Clear();
        _highlightedOriginalBackgrounds.Clear();
        _activeMatchRange = null;
    }

    private void ReplaceAllBackward(RichTextBox rtb, string find, string replace, bool matchCase) {
        if (string.IsNullOrEmpty(find)) return;
        var map = BuildCharPositionMap(rtb.Document);
        var sb = new StringBuilder();
        foreach (var cp in map) sb.Append(cp.Character);
        string plain = sb.ToString();

        StringComparison cmp = matchCase ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        int searchPos = 0;
        var matches = new System.Collections.Generic.List<int>();
        while (searchPos < plain.Length) {
            int idx = plain.IndexOf(find, searchPos, cmp);
            if (idx < 0) break;
            matches.Add(idx);
            searchPos = idx + find.Length;
        }

        for (int i = matches.Count - 1; i >= 0; i--) {
            int idx = matches[i];
            int endIdx = idx + find.Length - 1;
            if (endIdx < map.Count) {
                TextPointer start = map[idx].Start;
                TextPointer end = map[endIdx].End;
                if (start != null && end != null) {
                    var range = new TextRange(start, end);
                    range.Text = replace;
                }
            }
        }
    }

    private void HighlightAllMatches(RichTextBox rtb, string query, bool matchCase = false) {
        if (string.IsNullOrEmpty(query) || query.Length < 2) return;

        // Use the same precise character-level mapping as FindNext/FindPrevious
        var map = BuildCharPositionMap(rtb.Document);
        var sb = new StringBuilder();
        foreach (var cp in map) sb.Append(cp.Character);
        string plain = sb.ToString();

        StringComparison cmp = matchCase ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        int searchPos = 0;
        int matchCount = 0;
        while (searchPos < plain.Length) {
            int idx = plain.IndexOf(query, searchPos, cmp);
            if (idx < 0) break;

            int endIdx = idx + query.Length - 1;
            if (endIdx < map.Count) {
                TextPointer start = map[idx].Start;
                TextPointer end = map[endIdx].End;
                if (start != null && end != null) {
                    var range = new TextRange(start, end);
                    object origBg = range.GetPropertyValue(TextElement.BackgroundProperty);
                    _highlightedRanges.Add(range);
                    _highlightedOriginalBackgrounds.Add(origBg);
                    range.ApplyPropertyValue(TextElement.BackgroundProperty, _highlightBrush);
                    matchCount++;
                }
            }
            searchPos = idx + query.Length;
        }

        var win = System.Windows.Window.GetWindow(rtb);
        if (win != null) {
            var tb = win.FindName(rtb.Name + "_MatchCount") as System.Windows.Controls.TextBlock;
            if (tb != null) {
                tb.Text = matchCount == 1 ? "1 match" : matchCount + " matches";
            }
        }
    }

    private string GetDocumentRtf(FlowDocument doc) {
        var range = new TextRange(doc.ContentStart, doc.ContentEnd);
        using (var ms = new System.IO.MemoryStream()) {
            range.Save(ms, DataFormats.Rtf);
            return Encoding.UTF8.GetString(ms.ToArray());
        }
    }

    private void SetDocumentRtf(FlowDocument doc, string rtf) {
        var range = new TextRange(doc.ContentStart, doc.ContentEnd);
        using (var ms = new System.IO.MemoryStream(Encoding.UTF8.GetBytes(rtf))) {
            range.Load(ms, DataFormats.Rtf);
        }
    }

    private void ReplaceInFlowDocument(FlowDocument doc, string find, string replace, bool matchCase = false) {
        foreach (var block in doc.Blocks) {
            ReplaceInBlock(block, find, replace, matchCase);
        }
    }

    private void ReplaceInBlock(System.Windows.Documents.Block block, string find, string replace, bool matchCase = false) {
        if (block is System.Windows.Documents.Paragraph) {
            var para = (System.Windows.Documents.Paragraph)block;
            foreach (var inline in para.Inlines) {
                ReplaceInInline(inline, find, replace, matchCase);
            }
        } else if (block is System.Windows.Documents.Table) {
            var table = (System.Windows.Documents.Table)block;
            foreach (var rg in table.RowGroups) {
                foreach (var row in rg.Rows) {
                    foreach (var cell in row.Cells) {
                        foreach (var b in cell.Blocks) {
                            ReplaceInBlock(b, find, replace, matchCase);
                        }
                    }
                }
            }
        } else if (block is System.Windows.Documents.List) {
            var list = (System.Windows.Documents.List)block;
            foreach (var li in list.ListItems) {
                foreach (var b in li.Blocks) {
                    ReplaceInBlock(b, find, replace, matchCase);
                }
            }
        } else if (block is System.Windows.Documents.Section) {
            var section = (System.Windows.Documents.Section)block;
            foreach (var b in section.Blocks) {
                ReplaceInBlock(b, find, replace, matchCase);
            }
        }
    }

    private void ReplaceInInline(System.Windows.Documents.Inline inline, string find, string replace, bool matchCase = false) {
        StringComparison cmp = matchCase ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        if (inline is System.Windows.Documents.Run) {
            var run = (System.Windows.Documents.Run)inline;
            if (run.Text != null && run.Text.IndexOf(find, cmp) >= 0) {
                run.Text = ReplaceWithComparison(run.Text, find, replace, cmp);
            }
        } else if (inline is System.Windows.Documents.Span) {
            var span = (System.Windows.Documents.Span)inline;
            foreach (var subInline in span.Inlines) {
                ReplaceInInline(subInline, find, replace, matchCase);
            }
        }
    }

    private string ReplaceWithComparison(string text, string find, string replace, StringComparison cmp) {
        if (string.IsNullOrEmpty(text) || string.IsNullOrEmpty(find)) return text;
        int idx = 0;
        var sb = new StringBuilder();
        while (true) {
            int foundIdx = text.IndexOf(find, idx, cmp);
            if (foundIdx < 0) {
                sb.Append(text.Substring(idx));
                break;
            }
            sb.Append(text.Substring(idx, foundIdx - idx));
            sb.Append(replace);
            idx = foundIdx + find.Length;
        }
        return sb.ToString();
    }
#endif

    // --- DevTools Helpers ---
    private XamlHighlightAdorner _currentAdorner;
    private void SetHighlight(FrameworkElement element, bool enable)
    {
        if (_currentAdorner != null)
        {
            var layer = AdornerLayer.GetAdornerLayer(_currentAdorner.AdornedElement);
            if (layer != null)
            {
                layer.Remove(_currentAdorner);
            }
            _currentAdorner = null;
        }

        if (enable && element != null)
        {
            var layer = AdornerLayer.GetAdornerLayer(element);
            if (layer != null)
            {
                _currentAdorner = new XamlHighlightAdorner(element);
                layer.Add(_currentAdorner);
            }
        }
    }

    private FrameworkElement FindElementByHash(DependencyObject root, string hash)
    {
        if (root == null || string.IsNullOrEmpty(hash)) return null;
        if (root.GetHashCode().ToString() == hash) return root as FrameworkElement;

        int children = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < children; i++)
        {
            var found = FindElementByHash(VisualTreeHelper.GetChild(root, i), hash);
            if (found != null) return found;
        }
        return null;
    }

    private string SerializeVisualTree(DependencyObject root, int level = 0)
    {
        if (root == null) return "";
        var sb = new StringBuilder();
        var fe = root as FrameworkElement;

        string name = fe != null ? fe.Name : "";
        string type = root.GetType().Name;
        string visibility = fe != null ? fe.Visibility.ToString() : "Visible";
        double w = fe != null ? fe.ActualWidth : 0;
        double h = fe != null ? fe.ActualHeight : 0;
        string hash = root.GetHashCode().ToString();
        string uid = fe != null && fe.Uid != null && fe.Uid.StartsWith("ahk:") ? fe.Uid.Substring(4) : "";

        bool shouldInclude = IsIncludedInDevTools(root) || level == 0;

        if (shouldInclude)
        {
            sb.AppendFormat("{0}|{1}|{2}|{3:F0}|{4:F0}|{5}|{6}|{7}\n", level, type, name, w, h, visibility, hash, uid);
        }

        int children = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < children; i++)
        {
            sb.Append(SerializeVisualTree(VisualTreeHelper.GetChild(root, i), level + 1));
        }
        return sb.ToString();
    }

    private static readonly System.Collections.Generic.Dictionary<System.Type, System.Reflection.PropertyInfo[]> _propertiesCache =
        new System.Collections.Generic.Dictionary<System.Type, System.Reflection.PropertyInfo[]>();

    private static readonly System.Collections.Generic.Dictionary<System.Type, System.Reflection.EventInfo[]> _eventsCache =
        new System.Collections.Generic.Dictionary<System.Type, System.Reflection.EventInfo[]>();

    private static readonly System.Collections.Generic.Dictionary<string, System.ComponentModel.DependencyPropertyDescriptor> _dpDescriptorCache =
        new System.Collections.Generic.Dictionary<string, System.ComponentModel.DependencyPropertyDescriptor>();

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

    private string InspectElementProperties(FrameworkElement element)
    {
        if (element == null) return "";
        var sb = new StringBuilder();

        System.Type type = element.GetType();
        System.Reflection.PropertyInfo[] properties;
        lock (_propertiesCache)
        {
            if (!_propertiesCache.TryGetValue(type, out properties))
            {
                properties = type.GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
                _propertiesCache[type] = properties;
            }
        }

        foreach (var prop in properties)
        {
            try
            {
                if (!prop.CanRead) continue;
                if (prop.GetIndexParameters().Length > 0) continue;

                bool isLocal = false;
                bool isReadOnly = !prop.CanWrite || prop.GetSetMethod(false) == null;

                string key = type.FullName + "." + prop.Name;
                System.ComponentModel.DependencyPropertyDescriptor dpDescriptor;
                lock (_dpDescriptorCache)
                {
                    if (!_dpDescriptorCache.TryGetValue(key, out dpDescriptor))
                    {
                        dpDescriptor = System.ComponentModel.DependencyPropertyDescriptor.FromName(prop.Name, type, type);
                        _dpDescriptorCache[key] = dpDescriptor;
                    }
                }

                if (dpDescriptor != null)
                {
                    if (dpDescriptor.IsReadOnly) isReadOnly = true;
                    var vs = System.Windows.DependencyPropertyHelper.GetValueSource(element, dpDescriptor.DependencyProperty);
                    isLocal = (vs.BaseValueSource == System.Windows.BaseValueSource.Local);
                }

                object val = prop.GetValue(element, null);
                string strVal = "null";
                if (val != null)
                {
                    if (val is System.Collections.ICollection)
                    {
                        System.Collections.ICollection coll = (System.Collections.ICollection)val;
                        strVal = string.Format("Collection ({0} items)", coll.Count);
                    }
                    else
                    {
                        strVal = val.ToString();
                    }
                }

                string category = "Other";
                if (typeof(Delegate).IsAssignableFrom(prop.PropertyType) || prop.PropertyType.IsSubclassOf(typeof(Delegate)) || prop.Name.Contains("Event")) category = "Events";
                else if (prop.Name.Contains("Style") || prop.Name.Contains("Brush") || prop.Name.Contains("Color") || prop.Name.Contains("Margin") || prop.Name.Contains("Padding") || prop.Name.Contains("Thickness") || prop.Name.Contains("Background") || prop.Name.Contains("Foreground") || prop.Name.Contains("Font") || prop.Name.Contains("Border") || prop.Name.Contains("Align") || prop.Name.Contains("Width") || prop.Name.Contains("Height")) category = "Style";
                else category = "Properties";

                strVal = strVal.Replace("|", "&#x7C;").Replace("=", "&#x3D;").Replace("\n", "&#x0A;").Replace("\r", "&#x0D;");

                sb.AppendFormat("{0}|{1}|{2}|{3}:{4}={5}\n", category, isLocal ? "1" : "0", isReadOnly ? "1" : "0", prop.PropertyType.Name, prop.Name, strVal);
            }
            catch { }
        }

        System.Reflection.EventInfo[] events;
        lock (_eventsCache)
        {
            if (!_eventsCache.TryGetValue(type, out events))
            {
                events = type.GetEvents(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
                _eventsCache[type] = events;
            }
        }

        foreach (var ev in events)
        {
            try
            {
                sb.AppendFormat("Events|0|1|{0}:{1}=CLR Event\n", ev.EventHandlerType.Name, ev.Name);
            }
            catch { }
        }
        return sb.ToString();
    }
}

public class XamlHighlightAdorner : Adorner
{
    private readonly Pen _borderPen;
    private readonly Brush _fillBrush;

    public XamlHighlightAdorner(UIElement adornedElement) : base(adornedElement)
    {
        IsHitTestVisible = false;
        _fillBrush = new SolidColorBrush(System.Windows.Media.Color.FromArgb(51, 0, 128, 255));
        _fillBrush.Freeze();
        _borderPen = new Pen(new SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 120, 215)), 1.5);
        _borderPen.Freeze();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        Rect rect = new Rect(AdornedElement.RenderSize);
        drawingContext.DrawRectangle(_fillBrush, _borderPen, rect);
    }
}

#if ENABLE_AVALONEDIT
// Autocomplete item for AvalonEdit completion window
public class AhkCompletionData : ICSharpCode.AvalonEdit.CodeCompletion.ICompletionData {
    public AhkCompletionData(string text, string description = "") {
        this.Text = text;
        this.Description = description;
    }
    public System.Windows.Media.ImageSource Image { get { return null; } }
    public string Text { get; private set; }
    public object Content { get { return this.Text; } }
    public object Description { get; private set; }
    public double Priority { get { return 0; } }

    public void Complete(ICSharpCode.AvalonEdit.Editing.TextArea textArea,
        ICSharpCode.AvalonEdit.Document.ISegment completionSegment,
        EventArgs insertionRequestEventArgs) {
        textArea.Document.Replace(completionSegment, this.Text);
    }
}

// Brace-matching folding strategy for AvalonEdit
public class BraceFoldingStrategy {
    public void UpdateFoldings(ICSharpCode.AvalonEdit.Folding.FoldingManager manager,
        ICSharpCode.AvalonEdit.Document.TextDocument document) {
        var foldings = CreateNewFoldings(document);
        manager.UpdateFoldings(foldings, -1);
    }

    private System.Collections.Generic.IEnumerable<ICSharpCode.AvalonEdit.Folding.NewFolding> CreateNewFoldings(
        ICSharpCode.AvalonEdit.Document.TextDocument document) {
        var foldings = new System.Collections.Generic.List<ICSharpCode.AvalonEdit.Folding.NewFolding>();
        var stack = new System.Collections.Generic.Stack<int>();
        string text = document.Text;

        for (int i = 0; i < text.Length; i++) {
            if (text[i] == '{') {
                stack.Push(i);
            } else if (text[i] == '}' && stack.Count > 0) {
                int start = stack.Pop();
                if (i - start > 1) {
                    foldings.Add(new ICSharpCode.AvalonEdit.Folding.NewFolding(start, i + 1) { Name = "..." });
                }
            }
        }
        foldings.Sort((a, b) => a.StartOffset.CompareTo(b.StartOffset));
        return foldings;
    }
}

// Sexy, minimalist, hover-reactive folding margin mimicking VS Code
public class SexyFoldingMargin : ICSharpCode.AvalonEdit.Editing.AbstractMargin
{
    public FoldingManager FoldingManager { get; set; }
    
    public Brush FoldingMarkerBrush { get; set; }
    public Brush SelectedFoldingMarkerBrush { get; set; }
    public Brush FoldingMarkerBackgroundBrush { get; set; }
    
    public SexyFoldingMargin()
    {
        FoldingMarkerBrush = Brushes.Gray;
        SelectedFoldingMarkerBrush = Brushes.DodgerBlue;
        FoldingMarkerBackgroundBrush = Brushes.Transparent;
    }
    
    private int hoveredLine = -1;
    private bool isMarginHovered = false;
    
    protected override void OnTextViewChanged(TextView oldTextView, TextView newTextView)
    {
        if (oldTextView != null) {
            oldTextView.VisualLinesChanged -= OnVisualLinesChanged;
        }
        base.OnTextViewChanged(oldTextView, newTextView);
        if (newTextView != null) {
            newTextView.VisualLinesChanged += OnVisualLinesChanged;
        }
    }
    
    private void OnVisualLinesChanged(object sender, EventArgs e)
    {
        InvalidateVisual();
    }
    
    protected override Size MeasureOverride(Size availableSize)
    {
        return new Size(26, 0);
    }
    
    protected override void OnRender(DrawingContext drawingContext)
    {
        if (TextView == null || !TextView.VisualLinesValid || FoldingManager == null)
            return;
            
        var visualLines = TextView.VisualLines;
        if (visualLines.Count == 0)
            return;
            
        double viewTop = TextView.VerticalOffset;
        double width = RenderSize.Width;
        
        // Draw a completely transparent rectangle covering the entire margin area.
        // This is a CRITICAL WPF detail: elements with null background are transparent to hit-testing.
        // Drawing a transparent rectangle makes the entire 26px gutter fully hit-testable!
        drawingContext.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, width, RenderSize.Height));
        
        var foldings = FoldingManager.AllFoldings.ToList();
        
        Brush markerBrush = FoldingMarkerBrush ?? Brushes.Gray;
        Brush highlightBrush = SelectedFoldingMarkerBrush ?? Brushes.DodgerBlue;
        
        // Dynamic faint color matching standard theme folding guide
        Brush lineBrush = new SolidColorBrush(System.Windows.Media.Color.FromArgb(40, 128, 128, 128));
        SolidColorBrush scb = markerBrush as SolidColorBrush;
        if (scb != null) {
            lineBrush = new SolidColorBrush(System.Windows.Media.Color.FromArgb(50, scb.Color.R, scb.Color.G, scb.Color.B));
        }
        
        foreach (var line in visualLines) {
            int lineNum = line.FirstDocumentLine.LineNumber;
            double startY = line.VisualTop - viewTop;
            double endY = startY + line.Height;
            double centerY = startY + line.Height / 2;
            double centerX = width / 2;
            
            // Find all active/expanded foldings that cover this line
            var activeFolds = foldings.Where(f => !f.IsFolded && 
                lineNum >= TextView.Document.GetLineByOffset(f.StartOffset).LineNumber && 
                lineNum <= TextView.Document.GetLineByOffset(f.EndOffset).LineNumber).ToList();
                
            foreach (var fold in activeFolds) {
                int foldStartLine = TextView.Document.GetLineByOffset(fold.StartOffset).LineNumber;
                int foldEndLine = TextView.Document.GetLineByOffset(fold.EndOffset).LineNumber;
                
                double segmentStartY = startY;
                double segmentEndY = endY;
                
                if (lineNum == foldStartLine) {
                    segmentStartY = centerY + 6;
                }
                if (lineNum == foldEndLine) {
                    segmentEndY = centerY - 4;
                }
                
                bool isHovered = (hoveredLine >= foldStartLine && hoveredLine <= foldEndLine);
                Brush currentLineBrush = isHovered ? highlightBrush : lineBrush;
                Pen pen = new Pen(currentLineBrush, 1.5);
                
                drawingContext.DrawLine(pen, new Point(centerX, segmentStartY), new Point(centerX, segmentEndY));
                
                if (lineNum == foldEndLine) {
                    drawingContext.DrawLine(pen, new Point(centerX, segmentEndY), new Point(centerX + 4, segmentEndY));
                }
            }
            
            // Draw chevrons starting on this line
            var startFold = foldings.FirstOrDefault(f => 
                TextView.Document.GetLineByOffset(f.StartOffset).LineNumber == lineNum);
                
            if (startFold != null) {
                bool shouldDraw = isMarginHovered || startFold.IsFolded;
                if (shouldDraw) {
                    bool isHovered = (hoveredLine == lineNum);
                    Brush brush = isHovered ? highlightBrush : markerBrush;
                    Pen pen = new Pen(brush, 2.0);
                    
                    if (startFold.IsFolded) {
                        StreamGeometry geometry = new StreamGeometry();
                        using (StreamGeometryContext ctx = geometry.Open()) {
                            ctx.BeginFigure(new Point(centerX - 2, centerY - 4), false, false);
                            ctx.LineTo(new Point(centerX + 2, centerY), true, false);
                            ctx.LineTo(new Point(centerX - 2, centerY + 4), true, false);
                        }
                        geometry.Freeze();
                        drawingContext.DrawGeometry(null, pen, geometry);
                    } else {
                        StreamGeometry geometry = new StreamGeometry();
                        using (StreamGeometryContext ctx = geometry.Open()) {
                            ctx.BeginFigure(new Point(centerX - 4, centerY - 2), false, false);
                            ctx.LineTo(new Point(centerX, centerY + 2), true, false);
                            ctx.LineTo(new Point(centerX + 4, centerY - 2), true, false);
                        }
                        geometry.Freeze();
                        drawingContext.DrawGeometry(null, pen, geometry);
                    }
                }
            }
        }
    }
    
    protected override void OnMouseEnter(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseEnter(e);
        isMarginHovered = true;
        InvalidateVisual();
    }
    
    protected override void OnMouseLeave(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        isMarginHovered = false;
        hoveredLine = -1;
        InvalidateVisual();
    }
    
    protected override void OnMouseMove(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (TextView == null || !TextView.VisualLinesValid) return;
        
        Point p = e.GetPosition(this);
        double localY = p.Y;
        
        int newLine = -1;
        foreach (var line in TextView.VisualLines) {
            double startY = line.VisualTop - TextView.VerticalOffset;
            double endY = startY + line.Height;
            if (localY >= startY && localY <= endY) {
                newLine = line.FirstDocumentLine.LineNumber;
                break;
            }
        }
        
        if (newLine != hoveredLine) {
            hoveredLine = newLine;
            InvalidateVisual();
        }
    }
    
    protected override void OnMouseDown(System.Windows.Input.MouseButtonEventArgs e)
    {
        base.OnMouseDown(e);
        if (TextView == null || !TextView.VisualLinesValid || FoldingManager == null) return;
        
        Point p = e.GetPosition(this);
        double localY = p.Y;
        
        foreach (var line in TextView.VisualLines) {
            double startY = line.VisualTop - TextView.VerticalOffset;
            double endY = startY + line.Height;
            if (localY >= startY && localY <= endY) {
                int lineNum = line.FirstDocumentLine.LineNumber;
                int lineStartOffset = line.FirstDocumentLine.Offset;
                int lineEndOffset = line.FirstDocumentLine.EndOffset;
                
                // 1. Check direct chevron click
                var startFoldings = FoldingManager.AllFoldings
                    .Where(f => f.StartOffset >= lineStartOffset && f.StartOffset <= lineEndOffset)
                    .ToList();
                    
                if (startFoldings.Count > 0) {
                    startFoldings[0].IsFolded = !startFoldings[0].IsFolded;
                    e.Handled = true;
                    InvalidateVisual();
                    break;
                }
                
                // 2. Check vertical guide line click (collapse innermost expanded fold covering this line)
                var activeFolds = FoldingManager.AllFoldings
                    .Where(f => !f.IsFolded && 
                        lineNum >= TextView.Document.GetLineByOffset(f.StartOffset).LineNumber && 
                        lineNum <= TextView.Document.GetLineByOffset(f.EndOffset).LineNumber)
                    .OrderByDescending(f => f.StartOffset)
                    .ToList();
                    
                if (activeFolds.Count > 0) {
                    activeFolds[0].IsFolded = true;
                    e.Handled = true;
                    InvalidateVisual();
                    break;
                }
            }
        }
    }
}
#endif

[ComImport]
[Guid("56FDF342-FD6D-11d0-958A-006097C9A090")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITaskbarList
{
    void HrInit();
    void AddTab(IntPtr hwnd);
    void DeleteTab(IntPtr hwnd);
    void ActivateTab(IntPtr hwnd);
    void SetActiveAlt(IntPtr hwnd);
}

[ComImport]
[Guid("56FDF344-FD6D-11d0-958A-006097C9A090")]
public class TaskbarList
{
}

#if ENABLE_SHADERS
namespace AhkEffects
{
    public static class Bytecodes
    {
        public static readonly string Acrylic = "AAL///7/QQBDVEFCHAAAANcAAAAAAv//BAAAABwAAAAAAQAA0AAAAGwAAAACAAIAAQAKAHgAAAAAAAAAiAAAAAIAAQABAAYAeAAAAAAAAACUAAAAAgAAAAEAAgCgAAAAAAAAALAAAAADAAAAAQACAMAAAAAAAAAAQmx1clJhZGl1cwCrAAADAAEAAQABAAAAAAAAAE5vaXNlQW1vdW50AFRpbnRDb2xvcgCrqwEAAwABAAQAAQAAAAAAAABpbXBsaWNpdElucHV0AKurBAAMAAEAAQABAAAAAAAAAHBzXzJfMABNaWNyb3NvZnQgKFIpIEhMU0wgU2hhZGVyIENvbXBpbGVyIDEwLjEAq1EAAAUDAA+gAAAAP/yp8T0Sg8A9UI0XPlEAAAUEAA+gAAB6RDMz/kKa2ZtDAAAAAFEAAAUFAA+gg/kiPgAAAD/bD8lA2w9JwFEAAAUGAA+gjO4qRwAAAAAAAAAAAAAAAFEAAAUHAA+gAQ3QtWELtrerqio7iYiIOVEAAAUIAA+gq6qqvAAAAL4AAIA/AAAAPx8AAAIAAACAAAADsB8AAAIAAACQAAgPoAEAAAIAAAGAAAAAsAEAAAIBAAiAAwAAoAQAAAQAAAKAAgAAoAEA/4EAAFWwBAAABAEAA4ACAACgAQD/gQAA5LAEAAAEAgABgAIAAKABAP+AAAAAsAQAAAQCAAKAAgAAoAEA/4EAAFWwBAAABAMAAYACAACgAQD/gQAAALABAAACAwACgAAAVbAEAAAEBAABgAIAAKABAP+AAAAAsAEAAAIEAAKAAABVsAQAAAQFAAGAAgAAoAEA/4EAAACwBAAABAUAAoACAACgAQD/gAAAVbABAAACBgABgAAAALAEAAAEBgACgAIAAKABAP+AAABVsAQAAAQHAAOAAgAAoAEA/4AAAOSwQgAAAwAAD4AAAOSAAAjkoEIAAAMBAA+AAQDkgAAI5KBCAAADAgAPgAIA5IAACOSgQgAAAwMAD4ADAOSAAAjkoEIAAAMIAA+AAADksAAI5KBCAAADBAAPgAQA5IAACOSgQgAAAwUAD4AFAOSAAAjkoEIAAAMGAA+ABgDkgAAI5KBCAAADBwAPgAcA5IAACOSgBQAAAwAAD4AAAOSAAwBVoAQAAAQAAA+AAQDkgAMAqqAAAOSABAAABAAAD4ACAOSAAwCqoAAA5IAEAAAEAAAPgAMA5IADAFWgAADkgAQAAAQAAA+ACADkgAMA/6AAAOSABAAABAAAD4AEAOSAAwBVoAAA5IAEAAAEAAAPgAUA5IADAKqgAADkgAQAAAQAAA+ABgDkgAMAVaAAAOSABAAABAAAD4AHAOSAAwCqoAAA5IASAAAEAQAHgAAA/6AAAOSgAADkgAUAAAMCAAOAAADksAQAAKBaAAAEAQAIgAEA5IAEAMmgBAD/oAQAAAQBAAiAAQD/gAUAAKAFAFWgEwAAAgEACIABAP+ABAAABAEACIABAP+ABQCqoAUA/6AlAAAEAgACgAEA/4AHAOSgCADkoAUAAAMBAAiAAgBVgAYAAKATAAACAQAIgAEA/4ACAAADAQAIgAEA/4ADAAChBAAABAAAB4ABAP+AAQAAoAEA5IABAAACAAgPgAAA5ID//wAA";

        public static readonly string Confetti = "AAP///7/OABDVEFCHAAAALMAAAAAA///AwAAABwAAAAAAQAArAAAAFgAAAACAAAAAQACAGAAAAAAAAAAcAAAAAIAAQABAAYAfAAAAAAAAACMAAAAAwAAAAEAAgCcAAAAAAAAAENlbnRlcgCrAQADAAEAAgABAAAAAAAAAFByb2dyZXNzAKurqwAAAwABAAEAAQAAAAAAAABpbXBsaWNpdElucHV0AKurBAAMAAEAAQABAAAAAAAAAHBzXzNfMABNaWNyb3NvZnQgKFIpIEhMU0wgU2hhZGVyIENvbXBpbGVyIDEwLjEAq1EAAAUCAA+ggIgfv9+IH7/NzMw+AACAP1EAAAUDAA+gmpmZPpqZWT8AAIBAVn2+PFEAAAUEAA+gVOOVPHNoETwAAPBBAAAAAFEAAAUFAA+gAACAPwAAAAAAAIC/MzOzPlEAAAUGAA+gAACAP83MzD0nMSw8C7WWPFEAAAUHAA+gAACAP83MTD7NzEw/XkuuPFEAAAUIAA+gi2zPPM3MzD1mZmY/zcxMPlEAAAUJAA+g8KcGPGDlADy1yHY8fBTOPFEAAAUKAA+go0q6Pujrvr4yCGw8AAAAAFEAAAULAA+g402TvjeLbb+ie08+78YWv1EAAAUMAA+gzDN4vimXt776Kw2/ZYhrv1EAAAUNAA+gCKyMPCPbeTy4HpU8BoE1PFEAAAUOAA+gWZTWPq4LPL9LBpA8ZXV0v1EAAAUPAA+gAAAAADMzMz8AAIA/zcxMP1EAAAUQAA+gJTXLPkn/CL/XkCo/BSRRv1EAAAURAA+g4LeXvdfZ4r7RPPk85XRTv1EAAAUSAA+ghdQXvAHlgL+IqnE+9Xn7vlEAAAUTAA+gjQ7BPsvDWb8tDUo+b5Dcvh8AAAIFAACAAAADkB8AAAIAAACQAAgPoEIAAAMAAA+AAADkkAAI5KABAAACAQABgAEAAKBYAAAEAQACgAEAAIEFAACgBQBVoAIAAAMBAASAAQAAgAUAqqBYAAAEAQAEgAEAqoAFAACgBQBVoAIAAAMBAAKAAQCqgAEAVYApAAQCAQBVgQUAVaABAAACAAgPgAAA5IAqAAAAAQAAAgIAA4AAAOSgBAAABAEABoABAACAAgDQoAIA0IAFAAADAQAIgAEAAKABAACgBQAAAwMAAoABAP+ABQD/oAEAAAIDAAGABQBVoAIAAAMBAAaAAQDkgAMA0IAEAAAEAQAIgAEAAIACAKqhAgD/oAUAAAMCAAyAAQD/gAQARKACAAADAQAGgAEA5IEAANCQBQAAAwIADIACAOSAAgDkgFoAAAQCAASAAQDpiwEA6YECAKqAWgAABAEAAoABAOmLBACqoAQA/6ATAAACAQACgAEAVYAEAAAEAQACgAEAVYADAACgAwBVoAIAAAMBAASAAQAAgQUAAKAFAAADAQAUgAEAqoADAKqgBAAABAQAB4ABAFWADwDkoAAA5IEEAAAEBAAHgAEAqoAEAOSAAADkgAsAAAMEAAiAAAD/gAEAqoBYAAAEAAAPgAIAqoAEAOSAAADkgAQAAAQEAA+AAQAAgBMA5KACAESAAgAAAwQAD4ADAESABADkgAIAAAMEAA+ABADkgQAARJACAAADAQACgAQAVYsEAACLBAAABAEAAoABAP+AAwD/oAEAVYFaAAAEAgAEgAQA5IsEAKqgBAD/oBMAAAICAASAAgCqgAQAAAQCAASAAgCqgAMAAKADAFWgBAAABAUAB4ACAKqADwDOoAAA5IEEAAAEBQAHgAEAqoAFAOSAAADkgAsAAAMFAAiAAAD/gAEAqoBYAAAEAAAPgAEAVYAFAOSAAADkgFoAAAQBAAKABADuiwQA7oECAP+AWgAABAIABIAEAO6LBACqoAQA/6ATAAACAgAEgAIAqoAEAAAEAgAEgAIAqoADAACgAwBVoAQAAAQEAAeAAgCqgAYA1KAAAOSBBAAABAQAB4ABAKqABADkgAAA5IALAAADBAAIgAAA/4ABAKqAWAAABAAAD4ABAFWABADkgAAA5IAEAAAEBAAPgAEAAIASAOSgAgBEgAIAAAMEAA+AAwBEgAQA5IACAAADBAAPgAQA5IEAAESQBAAABAIADIABAP+ABgCqoAQARIxaAAAEAQACgAQA5IsEAKqgBAD/oBMAAAIBAAKAAQBVgAQAAAQBAAKAAQBVgAMAAKADAFWgBAAABAUAB4ABAFWABwDkoAAA5IEEAAAEBQAHgAEAqoAFAOSAAADkgAsAAAMFAAiAAAD/gAEAqoBYAAAEAQACgAIA/4AFAAChBQBVoVgAAAQBAAKAAgCqgAEAVYAFAFWgWAAABAAAD4ABAFWAAADkgAUA5IAFAAADAgAMgAEA/4ANAESgBQAAAwIADIACAOSAAgDkgFoAAAQBAAKABADuiwQA7oECAKqAWgAABAIABIAEAO6LBACqoAQA/6ATAAACAgAEgAIAqoAEAAAEAgAEgAIAqoADAACgAwBVoAQAAAQEAAeAAgCqgAYA1KAAAOSBBAAABAQAB4ABAKqABADkgAAA5IALAAADBAAIgAAA/4ABAKqAWAAABAAAD4ABAFWABADkgAAA5IAEAAAEBAAPgAEAAIARAOSgAgBEgAIAAAMEAA+AAwBEgAQA5IACAAADBAAPgAQA5IEAAESQAgAAAwEAAoAEAFWLBAAAiwQAAAQBAAKAAQD/gAYA/6ABAFWBWgAABAIABIAEAOSLBACqoAQA/6ATAAACAgAEgAIAqoAEAAAEAgAEgAIAqoADAACgAwBVoAQAAAQFAAeAAgCqgA8A5KAAAOSBBAAABAUAB4ABAKqABQDkgAAA5IALAAADBQAIgAAA/4ABAKqAWAAABAAAD4ABAFWABQDkgAAA5IBaAAAEAQACgAQA7osEAO6BAgD/gFoAAAQCAASABADuiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBAAHgAIAqoAGANSgAADkgQQAAAQEAAeAAQCqgAQA5IAAAOSACwAAAwQACIAAAP+AAQCqgFgAAAQAAA+AAQBVgAQA5IAAAOSABAAABAQAD4ABAACAEADkoAIARIACAAADBAAPgAMARIAEAOSAAgAAAwQAD4AEAOSBAABEkAIAAAMCAAyABADUiwQAhIsEAAAEAQACgAEA/4AHAP+gAgCqgVoAAAQCAASABADkiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBQAHgAIAqoAHAOSgAADkgQQAAAQFAAeAAQCqgAUA5IAAAOSACwAAAwUACIAAAP+AAQCqgFgAAAQAAA+AAQBVgAUA5IAAAOSABQAAAwMADIABAP+ADQDkoAQAAAQBAAKAAQD/gAgAAKACAP+BWgAABAIABIAEAO6LBACqoAQA/6ATAAACAgAEgAIAqoAEAAAEAgAEgAIAqoADAACgAwBVoAQAAAQEAAeAAgCqgAgA+aAAAOSBBAAABAQAB4ABAKqABADkgAAA5IALAAADBAAIgAAA/4ABAKqAWAAABAAAD4ABAFWABADkgAAA5IAEAAAEBAAPgAEAAIAOAOSgAgBEgAIAAAMEAA+AAwBEgAQA5IACAAADBAAPgAQA5IEAAESQBQAAAwIADIADAOSAAwDkgFoAAAQBAAKABADkiwQA5IECAKqAWgAABAIABIAEAOSLBACqoAQA/6ATAAACAgAEgAIAqoAEAAAEAgAEgAIAqoADAACgAwBVoAQAAAQFAAeAAgCqgA8AzqAAAOSBBAAABAUAB4ABAKqABQDkgAAA5IALAAADBQAIgAAA/4ABAKqAWAAABAAAD4ABAFWABQDkgAAA5IAEAAAEAwAMgAEA/4AJAACgBADkjFoAAAQBAAKABADuiwQAqqAEAP+gEwAAAgEAAoABAFWABAAABAEAAoABAFWAAwAAoAMAVaAEAAAEBAAHgAEAVYAGANSgAADkgQQAAAQEAAeAAQCqgAQA5IAAAOSACwAAAwQACIAAAP+AAQCqgFgAAAQBAAKAAwD/gAUAAKEFAFWhWAAABAEAAoADAKqAAQBVgAUAVaBYAAAEAAAPgAEAVYAAAOSABADkgAQAAAQEAA+AAQAAgAwA5KACAESAAgAAAwQAD4ADAESABADkgAIAAAMEAA+ABADkgQAARJBaAAAEAQACgAQA5IsEAOSBAgD/gFoAAAQCAASABADkiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBQAHgAIAqoAHAOSgAADkgQQAAAQFAAeAAQCqgAUA5IAAAOSACwAAAwUACIAAAP+AAQCqgFgAAAQAAA+AAQBVgAUA5IAAAOSABQAAAwIADIABAP+ACQCUoAUAAAMCAAyAAgDkgAIA5IBaAAAEAQACgAQA7osEAO6BAgCqgFoAAAQCAASABADuiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBAAHgAIAqoAGANSgAADkgQQAAAQEAAeAAQCqgAQA5IAAAOSACwAAAwQACIAAAP+AAQCqgFgAAAQAAA+AAQBVgAQA5IAAAOSABAAABAQAD4ABAACACwDkoAIARIACAAADBAAPgAMARIAEAOSAAgAAAwQAD4AEAOSBAABEkAIAAAMBAAKABABViwQAAIsEAAAEAQACgAEA/4AJAP+gAQBVgVoAAAQCAASABADkiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBQAHgAIAqoAGANSgAADkgQQAAAQFAAeAAQCqgAUA5IAAAOSAWgAABAEAAoAEAO6LBADugQIA/4BaAAAEAgAEgAQA7osEAKqgBAD/oBMAAAICAASAAgCqgAQAAAQCAASAAgCqgAMAAKADAFWgBAAABAQABAND4ABAFWABQDkgAAA5IAEAAAEAwAMgAEA/4AJAACgBADkjFoAAAQBAAKABADuiwQAqqAEAP+gEwAAAgEAAoABAFWABAAABAEAAoABAFWAAwAAoAMAVaAEAAAEBAAHgAEAVYAGANSgAADkgQQAAAQEAAeAAQCqgAQA5IAAAOSACwAAAwQACIAAAP+AAQCqgFgAAAQBAAKAAwD/gAUAAKEFAFWhWAAABAEAAoADAKqAAQBVgAUAVaBYAAAEAAAPgAEAVYAAAOSABADkgAQAAAQEAA+AAQAAgAwA5KACAESAAgAAAwQAD4ADAESABADkgAIAAAMEAA+ABADkgQAARJBaAAAEAQACgAQA5IsEAOSBAgD/gFoAAAQCAASABADkiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBQAHgAIAqoAHAOSgAADkgQQAAAQFAAeAAQCqgAUA5IAAAOSACwAAAwUACIAAAP+AAQCqgFgAAAQAAA+AAQBVgAUA5IAAAOSABQAAAwIADIABAP+ACQCUoAUAAAMCAAyAAgDkgAIA5IBaAAAEAQACgAQA7osEAO6BAgCqgFoAAAQCAASABADuiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBAAHgAIAqoAGANSgAADkgQQAAAQEAAeAAQCqgAQA5IAAAOSACwAAAwQACIAAAP+AAQCqgFgAAAQAAA+AAQBVgAQA5IAAAOSABAAABAQAD4ABAACACwDkoAIARIACAAADBAAPgAMARIAEAOSAAgAAAwQAD4AEAOSBAABEkAIAAAMBAAKABABViwQAAIsEAAAEAQACgAEA/4AJAP+gAQBVgVoAAAQCAASABADkiwQAqqAEAP+gEwAAAgIABIACAKqABAAABAIABIACAKqAAwAAoAMAVaAEAAAEBQAHgAIAqoAGANSgAADkgQQAAAQFAAeAAQCqgAUA5IAAAOSAWgAABAEAAoAEAO6LBADugQIA/4BaAAAEAgAEgAQA7osEAKqgBAD/oBMAAAICAASAAgCqgAQAAAQCAASAAgCqgAMAAKADAFWgBAAABAQAB4ACAKqADwDOoAAA5IEEAAAEBAAHgAEAqoAEAOSAAADkgAsAAAMEAAiAAAD/gAEAqoBYAAAEAAAPgAEAVYAEAOSAAADkgAQAAAQBAAOAAQAAgAoA5KACAOSAAgAAAwEAA4ADAOSAAQDkgAIAAAMBAAOAAQDkgQAA5JAEAAAEAgADgAEA/4AKAKqgAQDkjFoAAAQBAAGAAQDkiwQAqqAEAP+gEwAAAgEAAYABAACABAAABAEAAYABAACAAwAAoAMAVaAEAAAEAQALgAEAAIAHAKSgAACkgQQAAAQDAAeAAQCqgAEA9IAAAOSACwAAAwMACIAAAP+AAQCqgFgAAAQBAAGAAgBVgAUAAKEFAFWhWAAABAEAAYACAACAAQAAgAUAVaBYAAAEAAgPgAEAAIAAAOSAAwDkgCsAAAD//wAA";

        public static readonly string Glow = "AAL///7/SABDVEFCHAAAAPMAAAAAAv//BQAAABwAAAAAAQAA7AAAAIAAAAACAAAAAQACAIwAAAAAAAAAnAAAAAIAAQABAAYArAAAAAAAAAC8AAAAAgACAAEACgCsAAAAAAAAAMcAAAACAAMAAQAOAKwAAAAAAAAAzAAAAAMAAAABAAIA3AAAAAAAAABHbG93Q29sb3IAq6sBAAMAAQAEAAEAAAAAAAAAR2xvd1RoaWNrbmVzcwCrqwAAAwABAAEAAQAAAAAAAABQdWxzZVNwZWVkAFRpbWUAaW1wbGljaXRJbnB1dACrqwQADAABAAEAAQAAAAAAAABwc18yXzAATWljcm9zb2Z0IChSKSBITFNMIFNoYWRlciBDb21waWxlciAxMC4xAKtRAAAFBAAPoAAAAAAAAIC/AACAPwAAAD5RAAAFBQAPoJqZGT6amVk/AAAAAAAAAABRAAAFBgAPoIP5Ij4AAAA/2w/JQNsPScBRAAAFBwAPoAEN0LVhC7a3q6oqO4mIiDlRAAAFCAAPoKuqqrwAAAC+AACAPwAAAD8fAAACAAAAgAAAA7AfAAACAAAAkAAID6ABAAACAAABgAAAALACAAADAAACgAAAVbABAAChAgAAAwEAA4AAAOSwAQAAoQIAAAMCAAGAAAAAsAEAAKACAAADAgACgAAAVbABAAChAQAAAgMAAYABAAChAQAAAgMAAoAEAACgAgAAAwMAA4ADAOSAAADksAIAAAMEAAGAAAAAsAEAAKABAAACBAACgAAAVbABAAACBQAIgAEAAKAEAAAEBQADgAUA/4AEAMmgAADksAEAAAIGAAGAAAAAsAIAAAMGAAKAAABVsAEAAKACAAADBwADgAAA5LABAACgQgAAAwAAD4AAAOSAAAjkoEIAAAMBAA+AAQDkgAAI5KBCAAADAgAPgAIA5IAACOSgQgAAAwMAD4ADAOSAAAjkoEIAAAMIAA+AAADksAAI5KBCAAADBAAPgAQA5IAACOSgQgAAAwUAD4AFAOSAAAjkoEIAAAMGAA+ABgDkgAAI5KBCAAADBwAPgAcA5IAACOSgBQAAAwAAD4AAAOSAAwBVoAQAAAQAAA+AAQDkgAMAqqAAAOSABAAABAAAD4ACAOSAAwCqoAAA5IAEAAAEAAAPgAMA5IADAFWgAADkgAQAAAQAAA+ACADkgAMA/6AAAOSABAAABAAAD4AEAOSAAwBVoAAA5IAEAAAEAAAPgAUA5IADAKqgAADkgAQAAAQAAA+ABgDkgAMAVaAAAOSABAAABAAAD4AHAOSAAwCqoAAA5IASAAAEAQAHgAAA/6AAAOSgAADkgAUAAAMCAAOAAADksAQAAKBaAAAEAQAIgAIA5IAEAMmgBAD/oAQAAAQBAAiAAQD/gAUAAKAFAFWgEwAAAgEACIABAP+ABAAABAEACIABAP+ABQCqoAUA/6AlAAAEAgACgAEA/4AHAOSgCADkoAUAAAMBAAiAAgBVgAYAAKATAAACAQAIgAEA/4ACAAADAQAIgAEA/4ADAAChBAAABAAAB4ABAP+AAQAAoAEA5IABAAACAAgPgAAA5ID//wAA";

        public static readonly string Gradient = "AAL///7/WQBDVEFCHAAAADcBAAAAAv//CAAAABwAAAAAAQAAMAEAALwAAAACAAMAAQAOAMQAAAAAAAAA1AAAAAIABgABABoAxAAAAAAAAADfAAAAAgAAAAEAAgDoAAAAAAAAAPgAAAACAAEAAQAGAOgAAAAAAAAA/wAAAAIAAgABAAoA6AAAAAAAAAAGAQAAAgAEAAEAEgDEAAAAAAAAAAwBAAACAAUAAQAWAMQAAAAAAAAAEQEAAAMAAAABAAIAIAEAAAAAAABBbmdsZQCrqwAAAwABAAEAAQAAAAAAAABCcmlnaHRuZXNzAENvbG9yMQCrqwEAAwABAAQAAQAAAAAAAABDb2xvcjIAQ29sb3IzAFNwZWVkAFRpbWUAaW1wbGljaXRJbnB1dACrBAAMAAEAAQABAAAAAAAAAHBzXzJfMABNaWNyb3NvZnQgKFIpIEhMU0wgU2hhZGVyIENvbXBpbGVyIDEwLjEAq1EAAAUHAA+gYQs2OwAAAD/bD8lA2w9JwFEAAAUIAA+g8v9/PwAAAD8AAIA/8v//PlEAAAUJAA+gAQ3QtWELtrerqio7iYiIOVEAAAUKAA+gq6qqvAAAAL4AAIA/AAAAPx8AAAIAAACAAAADsB8AAAIAAACQAAgPoEIAAAMAAA+AAADksAAI5KABAAACAAADgAcA5KAEAAAEAAABgAMAAKAAAACAAABVgBMAAAIAAAGAAAAAgAQAAAQAAAGAAAAAgAcAqqAHAP+gJQAABAEAA4AAAACACQDkoAoA5KAFAAADAAABgAEAVYAAAFWwBAAABAAAAYAAAACwAQAAgAAAAIEBAAACAQABgAUAAKAEAAAEAAABgAEAAIAEAAChAAAAgAQAAAQAAAKAAAAAgAgAAKAIAFWgBAAABAAAAYAAAACACAD/oAgAVaATAAACAAABgAAAAIAEAAAEAAABgAAAAIAHAKqgBwD/oCUAAAQBAAGAAAAAgAkA5KAKAOSgAgAAAwAAAYABAACACACqoBMAAAIAAAKAAABVgAQAAAQAAAKAAABVgAcAqqAHAP+gJQAABAEAAoAAAFWACQDkoAoA5KACAAADAAACgAEAVYAIAKqgBQAAAwAAA4AAAOSABwBVoAEAAAIBAA+AAADkoAIAAAMBAA+AAQDkgQEA5KAEAAAEAQAPgAAAVYABAOSAAADkoBIAAAQCAA+AAAAAgAIA5KABAOSABQAAAwEAB4ACAOSABgAAoAUAAAMBAAiAAAD/gAAA/4ABAAACAgAHgAAA/4AFAAADAAAPgAEA5IACAOSAAQAAAgAID4AAAOSA//8AAA==";

        public static readonly string Ripple = "AAL///7/TABDVEFCHAAAAAMBAAAAAv//BgAAABwAAAAAAQAA/AAAAJQAAAACAAIAAQAKAKAAAAAAAAAAsAAAAAIAAAABAAIAuAAAAAAAAADIAAAAAgADAAEADgCgAAAAAAAAANIAAAACAAQAAQASAKAAAAAAAAAA2AAAAAIAAQABAAYAoAAAAAAAAADdAAAAAwAAAAEAAgDsAAAAAAAAAEFtcGxpdHVkZQCrqwAAAwABAAEAAQAAAAAAAABDZW50ZXIAqwEAAwABAAIAAQAAAAAAAABGcmVxdWVuY3kAU3BlZWQAVGltZQBpbXBsaWNpdElucHV0AKsEAAwAAQABAAEAAAAAAAAAcHNfMl8wAE1pY3Jvc29mdCAoUikgSExTTCBTaGFkZXIgQ29tcGlsZXIgMTAuMQCrUQAABQUAD6AAAAAAF7fROJqZGb4AAIA/UQAABQYAD6BVVdVAAACAP4P5Ij4AAAA/UQAABQcAD6DbD8lA2w9JwM3MzD4AAAAAUQAABQgAD6ABDdC1YQu2t6uqKjuJiIg5UQAABQkAD6Crqqq8AAAAvgAAgD8AAAA/HwAAAgAAAIAAAAOwHwAAAgAAAJAACA+gAgAAAwAAA4AAAOSwAADkoVoAAAQAAASAAADkgAAA5IAFAACgBwAAAgAABIAAAKqABgAAAgAABIAAAKqAAgAAAwAACIAAAKqABQBVoAEAAAIBAAiAAQAAoAQAAAQAAASAAQD/gAQAAKEAAKqABgAAAgAACIAAAP+ABQAAAwAAA4AAAP+AAADkgAUAAAMAAAiAAACqgAMAAKAEAAAEAAAIgAAA/4AGAKqgBgD/oBMAAAIAAAiAAAD/gAQAAAQAAAiAAAD/gAcAAKAHAFWgJQAABAIAAoAAAP+ACADkoAkA5KAFAAADAAAIgAIAVYACAACgBAAABAEAAYAAAKqABgAAoAYAVaACAAADAQACgAEA/4EFAP+gBQAAAwEAAYABAACAAQBVgAUAAAMAAAiAAAD/gAEAAIAEAAAEAAADgAAA5IAAAP+AAADksEIAAAMBAA+AAADkgAAI5KBCAAADAgAPgAAA5LAACOSgBAAABAEAB4AAAP+ABwCqoAEA5IACAAADAAABgAAAqoEFAKqgWAAABAAAAYAAAACABQAAoQUA/6FYAAAEAAABgAAAqoAFAACgAAAAgFgAAAQAAA+AAAAAgAIA5IABAOSAAQAAAgAID4AAAOSA//8AAA==";
    }

    public class AcrylicEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static AcrylicEffect()
        {
            string tempPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkAcrylicEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Acrylic);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public AcrylicEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(TintColorProperty);
            UpdateShaderValue(NoiseAmountProperty);
            UpdateShaderValue(BlurRadiusProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(AcrylicEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty TintColorProperty = DependencyProperty.Register("TintColor", typeof(Color), typeof(AcrylicEffect), new PropertyMetadata(Color.FromArgb(50, 255, 255, 255), PixelShaderConstantCallback(0)));
        public Color TintColor
        {
            get { return (Color)GetValue(TintColorProperty); }
            set { SetValue(TintColorProperty, value); }
        }

        public static readonly DependencyProperty NoiseAmountProperty = DependencyProperty.Register("NoiseAmount", typeof(double), typeof(AcrylicEffect), new PropertyMetadata(0.03, PixelShaderConstantCallback(1)));
        public double NoiseAmount
        {
            get { return (double)GetValue(NoiseAmountProperty); }
            set { SetValue(NoiseAmountProperty, value); }
        }

        public static readonly DependencyProperty BlurRadiusProperty = DependencyProperty.Register("BlurRadius", typeof(double), typeof(AcrylicEffect), new PropertyMetadata(0.01, PixelShaderConstantCallback(2)));
        public double BlurRadius
        {
            get { return (double)GetValue(BlurRadiusProperty); }
            set { SetValue(BlurRadiusProperty, value); }
        }
    }

    public class GlowEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static GlowEffect()
        {
            string tempPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkGlowEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Glow);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public GlowEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(GlowColorProperty);
            UpdateShaderValue(GlowThicknessProperty);
            UpdateShaderValue(PulseSpeedProperty);
            UpdateShaderValue(TimeProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(GlowEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty GlowColorProperty = DependencyProperty.Register("GlowColor", typeof(Color), typeof(GlowEffect), new PropertyMetadata(Color.FromRgb(0, 242, 254), PixelShaderConstantCallback(0)));
        public Color GlowColor
        {
            get { return (Color)GetValue(GlowColorProperty); }
            set { SetValue(GlowColorProperty, value); }
        }

        public static readonly DependencyProperty GlowThicknessProperty = DependencyProperty.Register("GlowThickness", typeof(double), typeof(GlowEffect), new PropertyMetadata(0.005, PixelShaderConstantCallback(1)));
        public double GlowThickness
        {
            get { return (double)GetValue(GlowThicknessProperty); }
            set { SetValue(GlowThicknessProperty, value); }
        }

        public static readonly DependencyProperty PulseSpeedProperty = DependencyProperty.Register("PulseSpeed", typeof(double), typeof(GlowEffect), new PropertyMetadata(2.0, PixelShaderConstantCallback(2)));
        public double PulseSpeed
        {
            get { return (double)GetValue(PulseSpeedProperty); }
            set { SetValue(PulseSpeedProperty, value); }
        }

        public static readonly DependencyProperty TimeProperty = DependencyProperty.Register("Time", typeof(double), typeof(GlowEffect), new PropertyMetadata(0.0, PixelShaderConstantCallback(3)));
        public double Time
        {
            get { return (double)GetValue(TimeProperty); }
            set { SetValue(TimeProperty, value); }
        }
    }

    public class RippleEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static RippleEffect()
        {
            string tempPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkRippleEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Ripple);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public RippleEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(CenterProperty);
            UpdateShaderValue(TimeProperty);
            UpdateShaderValue(AmplitudeProperty);
            UpdateShaderValue(FrequencyProperty);
            UpdateShaderValue(SpeedProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(RippleEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty CenterProperty = DependencyProperty.Register("Center", typeof(Point), typeof(RippleEffect), new PropertyMetadata(new Point(0.5, 0.5), PixelShaderConstantCallback(0)));
        public Point Center
        {
            get { return (Point)GetValue(CenterProperty); }
            set { SetValue(CenterProperty, value); }
        }

        public static readonly DependencyProperty TimeProperty = DependencyProperty.Register("Time", typeof(double), typeof(RippleEffect), new PropertyMetadata(0.0, PixelShaderConstantCallback(1)));
        public double Time
        {
            get { return (double)GetValue(TimeProperty); }
            set { SetValue(TimeProperty, value); }
        }

        public static readonly DependencyProperty AmplitudeProperty = DependencyProperty.Register("Amplitude", typeof(double), typeof(RippleEffect), new PropertyMetadata(0.03, PixelShaderConstantCallback(2)));
        public double Amplitude
        {
            get { return (double)GetValue(AmplitudeProperty); }
            set { SetValue(AmplitudeProperty, value); }
        }

        public static readonly DependencyProperty FrequencyProperty = DependencyProperty.Register("Frequency", typeof(double), typeof(RippleEffect), new PropertyMetadata(30.0, PixelShaderConstantCallback(3)));
        public double Frequency
        {
            get { return (double)GetValue(FrequencyProperty); }
            set { SetValue(FrequencyProperty, value); }
        }

        public static readonly DependencyProperty SpeedProperty = DependencyProperty.Register("Speed", typeof(double), typeof(RippleEffect), new PropertyMetadata(1.2, PixelShaderConstantCallback(4)));
        public double Speed
        {
            get { return (double)GetValue(SpeedProperty); }
            set { SetValue(SpeedProperty, value); }
        }
    }

    public class CyberpunkGradientEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static CyberpunkGradientEffect()
        {
            string tempPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkCyberpunkGradientEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Gradient);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public CyberpunkGradientEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(Color1Property);
            UpdateShaderValue(Color2Property);
            UpdateShaderValue(Color3Property);
            UpdateShaderValue(AngleProperty);
            UpdateShaderValue(SpeedProperty);
            UpdateShaderValue(TimeProperty);
            UpdateShaderValue(BrightnessProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(CyberpunkGradientEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty Color1Property = DependencyProperty.Register("Color1", typeof(Color), typeof(CyberpunkGradientEffect), new PropertyMetadata(Color.FromRgb(0, 242, 254), PixelShaderConstantCallback(0)));
        public Color Color1
        {
            get { return (Color)GetValue(Color1Property); }
            set { SetValue(Color1Property, value); }
        }

        public static readonly DependencyProperty Color2Property = DependencyProperty.Register("Color2", typeof(Color), typeof(CyberpunkGradientEffect), new PropertyMetadata(Color.FromRgb(253, 0, 140), PixelShaderConstantCallback(1)));
        public Color Color2
        {
            get { return (Color)GetValue(Color2Property); }
            set { SetValue(Color2Property, value); }
        }

        public static readonly DependencyProperty Color3Property = DependencyProperty.Register("Color3", typeof(Color), typeof(CyberpunkGradientEffect), new PropertyMetadata(Color.FromRgb(141, 0, 255), PixelShaderConstantCallback(2)));
        public Color Color3
        {
            get { return (Color)GetValue(Color3Property); }
            set { SetValue(Color3Property, value); }
        }

        public static readonly DependencyProperty AngleProperty = DependencyProperty.Register("Angle", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(45.0, PixelShaderConstantCallback(3)));
        public double Angle
        {
            get { return (double)GetValue(AngleProperty); }
            set { SetValue(AngleProperty, value); }
        }

        public static readonly DependencyProperty SpeedProperty = DependencyProperty.Register("Speed", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(0.5, PixelShaderConstantCallback(4)));
        public double Speed
        {
            get { return (double)GetValue(SpeedProperty); }
            set { SetValue(SpeedProperty, value); }
        }

        public static readonly DependencyProperty TimeProperty = DependencyProperty.Register("Time", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(0.0, PixelShaderConstantCallback(5)));
        public double Time
        {
            get { return (double)GetValue(TimeProperty); }
            set { SetValue(TimeProperty, value); }
        }

        public static readonly DependencyProperty BrightnessProperty = DependencyProperty.Register("Brightness", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(1.0, PixelShaderConstantCallback(6)));
        public double Brightness
        {
            get { return (double)GetValue(BrightnessProperty); }
            set { SetValue(BrightnessProperty, value); }
        }
    }
}
#endif

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


