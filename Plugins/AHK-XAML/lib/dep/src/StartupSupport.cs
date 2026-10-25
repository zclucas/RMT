// =============================================================================
// Startup & window chrome: static ctor, menu fixes, component styles
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

public partial class AhkWpfEngine
{
    static AhkWpfEngine()
    {
        _highlightBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(254, 239, 195));
        _highlightBrush.Freeze();
        _activeMatchBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 165, 0));
        _activeMatchBrush.Freeze();
        EventManager.RegisterClassHandler(typeof(ScrollViewer), FrameworkElement.LoadedEvent, new RoutedEventHandler(OnScrollViewerLoaded), false);
        EventManager.RegisterClassHandler(typeof(ScrollViewer), UIElement.PreviewMouseWheelEvent, new System.Windows.Input.MouseWheelEventHandler(OnPreviewMouseWheel), false);
        // 菜单/子菜单里的 ScrollViewer 收不到滚轮是 WPF 已知问题（只能拖滚动条）。
        // 直接在 MenuItem 上挂 PreviewMouseWheel 类处理器：悬停任一菜单项滚动滚轮时，
        // 向上找到其所属 ScrollViewer 并滚动，确保右键菜单/二级菜单可用滚轮滚动。
        // handledEventsToo=true：即使 ScrollViewer 的类处理器 OnPreviewMouseWheel 已把事件标记为
        // Handled（canScroll=false 分支会这么做），仍要在更深层的 MenuItem 上收到并滚动，
        // 否则右键二级菜单永远收不到有效滚轮。
        EventManager.RegisterClassHandler(typeof(System.Windows.Controls.MenuItem), UIElement.PreviewMouseWheelEvent, new System.Windows.Input.MouseWheelEventHandler(OnMenuItemPreviewMouseWheel), true);
        // 子菜单定位：给我们右键菜单(MG_*)的子菜单 Popup 设 CustomPopupPlacementCallback，
        // 顶部对齐、向右下展开，避免 WPF 在屏幕下方把子菜单整体上翻（下方还有空间却太靠上）。
        EventManager.RegisterClassHandler(typeof(System.Windows.Controls.MenuItem), FrameworkElement.LoadedEvent, new RoutedEventHandler(OnMenuItemLoadedFixSubmenu), false);
        // 启动即修正菜单右对齐（左手模式），使所有上下文菜单/子菜单向右弹。
        FixMenuDropAlignment();
        RmtTaskbarGroup.EnsureHooked();
    }

    // 给 MG_* 菜单项的子菜单 Popup 安装自定义定位：右侧、顶部对齐、优先向下展开。
    private static void OnMenuItemLoadedFixSubmenu(object sender, RoutedEventArgs e)
    {
        try
        {
            var mi = sender as System.Windows.Controls.MenuItem;
            if (mi == null || mi.Name == null || !mi.Name.StartsWith("MG_") || mi.Template == null)
                return;
            var popup = mi.Template.FindName("PART_Popup", mi) as System.Windows.Controls.Primitives.Popup;
            if (popup == null || (popup.Tag as string) == "CPP")
                return;
            popup.Tag = "CPP";
            popup.Placement = System.Windows.Controls.Primitives.PlacementMode.Custom;
            popup.CustomPopupPlacementCallback = (popupSize, targetSize, offset) =>
            {
                double x = targetSize.Width - 3; // 目标右侧（保留原 -3 水平微调）
                double y = 0;                    // 顶部对齐，向下展开
                return new[] { new System.Windows.Controls.Primitives.CustomPopupPlacement(
                    new Point(x, y), System.Windows.Controls.Primitives.PopupPrimaryAxis.Horizontal) };
            };
        }
        catch { }
    }

    // 修复 SystemParameters.MenuDropAlignment=true（系统"菜单右对齐/左手模式"）导致 WPF
    // 上下文菜单及子菜单向光标「左侧」弹出的问题：反射把私有静态字段置 false，强制左对齐(向右弹)。
    // 该字段会在系统偏好变化时被 WPF 重置，故每次打开菜单前再调一次以确保生效。
    private static void FixMenuDropAlignment()
    {
        try
        {
            var f = typeof(SystemParameters).GetField("_menuDropAlignment", BindingFlags.NonPublic | BindingFlags.Static);
            if (f != null && (bool)f.GetValue(null))
                f.SetValue(null, false);
        }
        catch { }
    }

    // 滚轮悬停菜单项时滚动其所属 ScrollViewer（修复 WPF 菜单/子菜单滚轮不生效）。
    // 不看 args.Handled：上游 ScrollViewer 类处理器可能已把事件标记 Handled 但并未真正滚动
    // （canScroll 误判为 false），这里按需真正滚动最近的可滚动 ScrollViewer。
    private static void OnMenuItemPreviewMouseWheel(object sender, System.Windows.Input.MouseWheelEventArgs args)
    {
        DependencyObject d = sender as DependencyObject;
        while (d != null)
        {
            d = System.Windows.Media.VisualTreeHelper.GetParent(d);
            if (d is ScrollViewer)
            {
                var sv = (ScrollViewer)d;
                string svTag = sv.Tag as string ?? "";
                try { LogDebug("[WheelDbg] MenuItemWheel sender='" + ((sender as FrameworkElement) != null ? ((FrameworkElement)sender).Name : "?") + "' foundSV name='" + (sv.Name ?? "") + "' tag='" + svTag + "' scrollableH=" + sv.ScrollableHeight.ToString("F0") + " handled=" + args.Handled); } catch { }
                // 已被 OnScrollViewerLoaded 挂上滚轮陷阱("Trapped")的 ScrollViewer 由陷阱负责滚动，
                // 这里跳过以免重复滚动；只兜底处理未被陷阱接管的菜单 ScrollViewer（如本例二级菜单）。
                if (!svTag.Contains("Trapped") && sv.ScrollableHeight > 0)
                {
                    sv.ScrollToVerticalOffset(sv.VerticalOffset - args.Delta / 3.0);
                    args.Handled = true;
                }
                break;
            }
        }
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

                                        System.Windows.Application.Current.Dispatcher.BeginInvoke(new Action(() =>
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
            try { LogDebug("[WheelDbg] ScrollViewerLoaded name='" + (sv.Name ?? "") + "' inPopup=" + inPopup + " tag='" + (sv.Tag as string ?? "") + "'"); } catch { }
        }
    }

    private static void OnPreviewMouseWheel(object sender, System.Windows.Input.MouseWheelEventArgs args)
    {
        if (!args.Handled)
        {
            ScrollViewer sv = null;
            if (sender is ScrollViewer) sv = (ScrollViewer)sender;
            else sv = BridgeUtil.FindVisualChild<ScrollViewer>(sender as DependencyObject);

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

    /// <summary>
    /// Sync brush/radius/theme keys from a window into Application.Resources for DynamicResource.
    /// Never sync Style / ControlTemplate / Type-keyed (implicit) resources: they must stay window-local.
    /// Copying implicit Button styles (e.g. UIMacro panel) into Application poisons later windows
    /// after the source window closes — subsequent CREATE_WINDOW fails or hangs.
    /// </summary>
    private static void SyncWindowResourcesToApp(Window win)
    {
        if (win == null || Application.Current == null)
            return;
        // 这里写的是全局资源字典：每改一个键都会让**所有已打开窗口**重新求值 DynamicResource。
        // 一个窗口几十个键串着写＝几十轮全量重算（实测 140ms）。现在全局已有的键直接跳过，
        // 只有第一次开窗（字典还是空的）才会真正写一批，后续开窗这里基本空转。
        System.Windows.Threading.DispatcherProcessingDisabled scope = default(System.Windows.Threading.DispatcherProcessingDisabled);
        bool scoped = false;
        try
        {
            scope = win.Dispatcher.DisableProcessing();
            scoped = true;
        }
        catch { }
        try
        {
            foreach (System.Collections.DictionaryEntry entry in win.Resources)
            {
                if (entry.Key is Type)
                    continue;
                if (entry.Value is Style || entry.Value is FrameworkTemplate)
                    continue;
                try
                {
                    // 全局已有这个键就不再写：新窗口 XAML 里的只是静态默认值，
                    // 覆盖全局不但把当前主题改回默认，还要让所有窗口重算一遍 DynamicResource。
                    // 主题色随后由 AHK 侧按主题写入，全局字典以主题为准。
                    if (Application.Current.Resources.Contains(entry.Key))
                        continue;
                    AhkWpfEngine.SetAppResource(entry.Key, entry.Value);
                }
                catch { }
            }
        }
        finally
        {
            if (scoped)
            {
                try { scope.Dispose(); } catch { }
            }
        }
    }

    /// <summary>
    /// Drop any implicit (Type-keyed) styles previously leaked into Application.Resources.
    /// MergedDictionaries from LoadComponentStyles are untouched.
    /// </summary>
    private static void ClearLeakedAppImplicitStyles()
    {
        if (Application.Current == null)
            return;
        try
        {
            var keys = new System.Collections.Generic.List<object>();
            foreach (object key in Application.Current.Resources.Keys)
            {
                if (key is Type)
                    keys.Add(key);
            }
            foreach (object key in keys)
                Application.Current.Resources.Remove(key);
        }
        catch { }
    }

}
