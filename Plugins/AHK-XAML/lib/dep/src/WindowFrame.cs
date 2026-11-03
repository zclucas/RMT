// =============================================================================
// 窗口外框：1px 边框 + 自绘阴影
//
// 系统阴影挂在 DWM 非客户区外面。WindowChrome 在直角时把窗口区域贴齐底边，
// 底部阴影会被裁掉；Win10 不认圆角偏好，很多机器上整圈阴影都没有。
// 边框画在窗口内容最外一圈（跟窗口走，不会被挡住）。
// 阴影是一张中心镂空的图，垫在窗口后面；镂空是为了层级偶发颠倒时也不盖住界面。
// 最大化时两者都收起，避免贴着屏幕边出现一条缝。
// =============================================================================
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;

internal static class RmtWindowFrame
{
    const double Pad = 28;

    sealed class Host
    {
        public Window Owner;
        public EdgeAdorner Edge;
        public Window Shade;
        public Grid ShadeRoot;
        public Border Plate;
        public bool Hooks;
        public bool RetryPosted;
        public bool ShadeShown;
        public int LastL, LastT, LastW, LastH;
        public bool HasRect;
        public double MaskW = -1, MaskH = -1, MaskR = -1;
        public double Radius = -1;
        public Color EdgeColor;
        public bool HasEdgeColor;
        public bool BorderOn;
    }

    static readonly Dictionary<Window, Host> Map = new Dictionary<Window, Host>();
    static bool Busy;

    [DllImport("user32.dll")]
    static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")]
    static extern bool IsZoomed(IntPtr hwnd);
    [DllImport("user32.dll")]
    static extern uint GetDpiForWindow(IntPtr hwnd);

    public static bool Wants(Window w)
    {
        if (w == null) return false;
        try
        {
            if (w.Title != null && w.Title.StartsWith("Developer Tools - ")) return false;
            if (w.Resources.Contains("RmtNoWindowFrame")) return false;
        }
        catch { }
        if (!w.AllowsTransparency) return true;
        var bg = w.Background as SolidColorBrush;
        if (bg == null || bg.Color.A == 0) return false;
        FrameworkElement root = w.Content as FrameworkElement;
        var box = root as Viewbox;
        if (box != null) root = box.Child as FrameworkElement;
        var border = root as Border;
        if (border != null && border.Effect is DropShadowEffect && border.BorderThickness.Left >= 1)
            return false;
        return true;
    }

    public static void Sync(Window w)
    {
        if (w == null || Busy) return;
        if (!Wants(w))
        {
            Hide(w);
            return;
        }
        Host host = Get(w);
        try
        {
            EnsureEdge(host);
            bool alive = ShouldShow(w);
            bool max = w.WindowState == WindowState.Maximized;
            bool shadow = alive && !max && ShadowWanted(w);
            ApplyEdge(host, alive && !max);
            if (shadow)
            {
                EnsureShade(host);
                Place(host, true);
            }
            else
            {
                HideShade(host);
            }
        }
        catch { }
    }

    public static void Follow(Window w)
    {
        if (w == null || Busy) return;
        Host host;
        if (!Map.TryGetValue(w, out host)) return;
        try
        {
            bool alive = ShouldShow(w);
            bool max = w.WindowState == WindowState.Maximized;
            ApplyEdge(host, alive && !max);
            if (!alive || max || !ShadowWanted(w))
            {
                HideShade(host);
                return;
            }
            if (host.Shade == null) return;
            Place(host, false);
        }
        catch { }
    }

    public static void DisableSystemShadow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        try
        {
            int off = 1; // DWMNCRP_DISABLED
            AhkWpfEngine.DwmSetWindowAttribute(hwnd, 2, ref off, 4);
            AhkWpfEngine.MARGINS zero = new AhkWpfEngine.MARGINS(0, 0, 0, 0);
            AhkWpfEngine.DwmExtendFrameIntoClientArea(hwnd, ref zero);
        }
        catch { }
    }

    static Host Get(Window w)
    {
        Host host;
        if (!Map.TryGetValue(w, out host))
        {
            host = new Host();
            host.Owner = w;
            Map[w] = host;
        }
        if (!host.Hooks)
        {
            host.Hooks = true;
            w.Closed += delegate { Detach(w); };
            w.IsVisibleChanged += delegate { Sync(w); };
        }
        return host;
    }

    static void Detach(Window w)
    {
        Host host;
        if (!Map.TryGetValue(w, out host)) return;
        Map.Remove(w);
        try
        {
            if (host.Edge != null)
            {
                var layer = AdornerLayer.GetAdornerLayer(host.Edge.AdornedElement);
                if (layer != null) layer.Remove(host.Edge);
            }
        }
        catch { }
        try
        {
            if (host.Shade != null) host.Shade.Close();
        }
        catch { }
    }

    static void Hide(Window w)
    {
        Host host;
        if (!Map.TryGetValue(w, out host)) return;
        HideShade(host);
        ApplyEdge(host, false);
    }

    static bool ShouldShow(Window w)
    {
        if (w == null || !w.IsVisible || w.Opacity < 0.05) return false;
        if (w.WindowState == WindowState.Minimized) return false;
        IntPtr hwnd = IntPtr.Zero;
        try { hwnd = new WindowInteropHelper(w).Handle; } catch { }
        if (hwnd == IntPtr.Zero) return false;
        try
        {
            if (!AhkWpfEngine.IsWindowVisible(hwnd)) return false;
            if (IsIconic(hwnd)) return false;
        }
        catch { return false; }
        AhkWpfEngine.RECT wr;
        if (!AhkWpfEngine.GetWindowRect(hwnd, out wr)) return false;
        if (wr.right - wr.left < 8 || wr.bottom - wr.top < 8) return false;
        return true;
    }

    static bool ShadowWanted(Window w)
    {
        if (w.WindowState == WindowState.Maximized) return false;
        try
        {
            IntPtr hwnd = new WindowInteropHelper(w).Handle;
            if (hwnd != IntPtr.Zero && IsZoomed(hwnd)) return false;
        }
        catch { }
        try
        {
            if (w.Resources.Contains("GlassFrameThicknessVal"))
            {
                double g = (double)w.Resources["GlassFrameThicknessVal"];
                if (Math.Abs(g) < 0.001) return false;
            }
        }
        catch { }
        return true;
    }

    static void EnsureEdge(Host host)
    {
        if (host.Edge != null) return;
        FrameworkElement target = AdornerTarget(host.Owner);
        if (target == null)
        {
            Retry(host);
            return;
        }
        var layer = AdornerLayer.GetAdornerLayer(target);
        if (layer == null)
        {
            Retry(host);
            return;
        }
        host.Edge = new EdgeAdorner(target);
        layer.Add(host.Edge);
    }

    static void Retry(Host host)
    {
        if (host.RetryPosted || host.Owner == null) return;
        host.RetryPosted = true;
        host.Owner.Dispatcher.BeginInvoke(new Action(delegate
        {
            host.RetryPosted = false;
            Sync(host.Owner);
        }), System.Windows.Threading.DispatcherPriority.ContextIdle);
    }

    static FrameworkElement AdornerTarget(Window w)
    {
        var deco = FindChild<AdornerDecorator>(w);
        if (deco != null && deco.Child is FrameworkElement) return (FrameworkElement)deco.Child;
        return w.Content as FrameworkElement;
    }

    static T FindChild<T>(DependencyObject parent) where T : DependencyObject
    {
        if (parent == null) return null;
        int n = VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < n; i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            var found = child as T;
            if (found != null) return found;
            found = FindChild<T>(child);
            if (found != null) return found;
        }
        return null;
    }

    static void ApplyEdge(Host host, bool on)
    {
        if (host.Edge == null) return;
        double radius = on ? RadiusOf(host.Owner) : 0;
        Color color = BorderColor(host.Owner);
        if (host.BorderOn == on && host.HasEdgeColor && host.EdgeColor == color && Math.Abs(host.Radius - radius) < 0.1)
            return;
        host.BorderOn = on;
        host.EdgeColor = color;
        host.HasEdgeColor = true;
        host.Radius = radius;
        host.Edge.Show = on;
        host.Edge.Radius = radius;
        host.Edge.Edge = color;
        host.Edge.InvalidateVisual();
    }

    static void EnsureShade(Host host)
    {
        if (host.Shade != null) return;
        var plate = new Border();
        plate.IsHitTestVisible = false;
        plate.HorizontalAlignment = HorizontalAlignment.Stretch;
        plate.VerticalAlignment = VerticalAlignment.Stretch;
        plate.Margin = new Thickness(Pad);
        plate.Background = Brushes.Black;
        plate.Effect = new DropShadowEffect
        {
            BlurRadius = 18,
            ShadowDepth = 2,
            Direction = 270,
            Opacity = 0.55,
            Color = Colors.Black,
            RenderingBias = RenderingBias.Performance
        };
        var root = new Grid();
        root.IsHitTestVisible = false;
        root.Background = Brushes.Transparent;
        root.Children.Add(plate);
        var shade = new Window();
        shade.WindowStyle = WindowStyle.None;
        shade.AllowsTransparency = true;
        shade.Background = Brushes.Transparent;
        shade.ShowInTaskbar = false;
        shade.ShowActivated = false;
        shade.Focusable = false;
        shade.ResizeMode = ResizeMode.NoResize;
        shade.WindowStartupLocation = WindowStartupLocation.Manual;
        shade.Content = root;
        shade.SourceInitialized += delegate
        {
            try
            {
                IntPtr hwnd = new WindowInteropHelper(shade).Handle;
                int ex = AhkWpfEngine.GetWindowLong(hwnd, -20);
                ex |= 0x20;       // WS_EX_TRANSPARENT
                ex |= 0x80;       // WS_EX_TOOLWINDOW
                ex |= 0x08000000; // WS_EX_NOACTIVATE
                AhkWpfEngine.SetWindowLong(hwnd, -20, new IntPtr(ex));
            }
            catch { }
        };
        host.Plate = plate;
        host.ShadeRoot = root;
        host.Shade = shade;
    }

    static void Place(Host host, bool rebuild)
    {
        if (host.Shade == null || host.Owner == null) return;
        IntPtr ownerHwnd = IntPtr.Zero;
        try { ownerHwnd = new WindowInteropHelper(host.Owner).Handle; } catch { }
        if (ownerHwnd == IntPtr.Zero) return;
        AhkWpfEngine.RECT wr;
        if (!AhkWpfEngine.GetWindowRect(ownerHwnd, out wr)) return;
        int ww = wr.right - wr.left;
        int hh = wr.bottom - wr.top;
        if (ww < 8 || hh < 8) return;
        double scale = DpiScale(ownerHwnd);
        double left = wr.left / scale - Pad;
        double top = wr.top / scale - Pad;
        double width = ww / scale + Pad * 2;
        double height = hh / scale + Pad * 2;
        double radius = RadiusOf(host.Owner);

        Busy = true;
        try
        {
            host.Shade.Topmost = host.Owner.Topmost;
            bool moved = !host.HasRect || host.LastL != wr.left || host.LastT != wr.top || host.LastW != ww || host.LastH != hh;
            if (moved)
            {
                host.Shade.Left = left;
                host.Shade.Top = top;
                host.Shade.Width = width;
                host.Shade.Height = height;
                host.LastL = wr.left;
                host.LastT = wr.top;
                host.LastW = ww;
                host.LastH = hh;
                host.HasRect = true;
            }
            if (moved || rebuild || Math.Abs(host.MaskR - radius) > 0.1)
            {
                host.Plate.CornerRadius = new CornerRadius(Math.Max(0, radius));
                ApplyMask(host, width, height, radius);
            }
            if (!host.ShadeShown)
            {
                host.Shade.Opacity = 0;
                host.Shade.Show();
                host.ShadeShown = true;
            }
            IntPtr shadeHwnd = new WindowInteropHelper(host.Shade).Handle;
            if (shadeHwnd != IntPtr.Zero)
                AhkWpfEngine.SetWindowPos(shadeHwnd, ownerHwnd, 0, 0, 0, 0, 0x0013);
            if (host.Shade.Opacity < 1) host.Shade.Opacity = 1;
        }
        finally
        {
            Busy = false;
        }
    }

    // 父级 OpacityMask 作用在子元素效果之后：挖掉窗口正下方的实心块，只留外圈阴影。
    static void ApplyMask(Host host, double width, double height, double radius)
    {
        if (host.ShadeRoot == null) return;
        if (Math.Abs(host.MaskW - width) < 0.5 && Math.Abs(host.MaskH - height) < 0.5 && Math.Abs(host.MaskR - radius) < 0.1)
            return;
        double holeW = Math.Max(0, width - Pad * 2);
        double holeH = Math.Max(0, height - Pad * 2);
        var geo = new GeometryGroup();
        geo.FillRule = FillRule.EvenOdd;
        geo.Children.Add(new RectangleGeometry(new Rect(0, 0, width, height)));
        geo.Children.Add(new RectangleGeometry(new Rect(Pad, Pad, holeW, holeH), Math.Max(0, radius), Math.Max(0, radius)));
        var drawing = new GeometryDrawing(Brushes.White, null, geo);
        var brush = new DrawingBrush(drawing);
        brush.Stretch = Stretch.None;
        brush.ViewboxUnits = BrushMappingMode.Absolute;
        brush.ViewportUnits = BrushMappingMode.Absolute;
        brush.Viewbox = new Rect(0, 0, width, height);
        brush.Viewport = new Rect(0, 0, width, height);
        try { brush.Freeze(); } catch { }
        host.ShadeRoot.OpacityMask = brush;
        host.MaskW = width;
        host.MaskH = height;
        host.MaskR = radius;
    }

    static void HideShade(Host host)
    {
        if (host.Shade == null || !host.ShadeShown) return;
        try { host.Shade.Hide(); } catch { }
        host.ShadeShown = false;
        host.HasRect = false;
    }

    static double DpiScale(IntPtr hwnd)
    {
        uint dpi = 96;
        try { dpi = GetDpiForWindow(hwnd); } catch { }
        if (dpi < 96)
        {
            try { dpi = AhkWpfEngine.GetDpiForSystem(); } catch { dpi = 96; }
        }
        if (dpi < 96) dpi = 96;
        return dpi / 96.0;
    }

    static double RadiusOf(Window w)
    {
        if (w == null || w.AllowsTransparency || w.WindowState == WindowState.Maximized) return 0;
        try
        {
            if (w.Resources.Contains("WindowRadius"))
                return Math.Max(0, ((CornerRadius)w.Resources["WindowRadius"]).TopLeft);
        }
        catch { }
        return 0;
    }

    static Color BorderColor(Window w)
    {
        Color edge = Color.FromRgb(0x99, 0x99, 0x99);
        Color bg = Color.FromRgb(0xF0, 0xF0, 0xF0);
        Color got;
        if (TryColor(w, "WindowBorderBrush", out got)) edge = got;
        else if (TryColor(w, "ControlBorder", out got)) edge = got;
        else if (TryColor(w, "GroupStroke", out got)) edge = got;
        if (TryColor(w, "BgColor", out got)) bg = got;
        else
        {
            var brush = w.Background as SolidColorBrush;
            if (brush != null && brush.Color.A > 0) bg = brush.Color;
        }
        return Contrast(edge, bg);
    }

    static bool TryColor(Window w, string key, out Color color)
    {
        color = Colors.Transparent;
        try
        {
            object o = null;
            if (w.Resources.Contains(key)) o = w.Resources[key];
            else o = w.TryFindResource(key);
            var brush = o as SolidColorBrush;
            if (brush == null || brush.Color.A == 0) return false;
            color = brush.Color;
            return true;
        }
        catch { return false; }
    }

    static Color Contrast(Color edge, Color bg)
    {
        int dr = edge.R - bg.R;
        int dg = edge.G - bg.G;
        int db = edge.B - bg.B;
        if (dr * dr + dg * dg + db * db >= 45 * 45) return edge;
        double lum = (0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B) / 255.0;
        int dir = lum > 0.55 ? -1 : 1;
        return Color.FromRgb(Clamp(bg.R + dir * 80), Clamp(bg.G + dir * 80), Clamp(bg.B + dir * 80));
    }

    static byte Clamp(int v)
    {
        if (v < 0) return 0;
        if (v > 255) return 255;
        return (byte)v;
    }

    sealed class EdgeAdorner : Adorner
    {
        public bool Show;
        public double Radius;
        public Color Edge;

        public EdgeAdorner(UIElement adorned) : base(adorned)
        {
            IsHitTestVisible = false;
            SnapsToDevicePixels = true;
        }

        protected override void OnRender(DrawingContext dc)
        {
            if (!Show) return;
            double w = AdornedElement.RenderSize.Width;
            double h = AdornedElement.RenderSize.Height;
            if (w < 2 || h < 2) return;
            const double t = 1;
            var outer = new RectangleGeometry(new Rect(0, 0, w, h), Radius, Radius);
            double innerR = Math.Max(0, Radius - t);
            var inner = new RectangleGeometry(new Rect(t, t, Math.Max(0, w - t * 2), Math.Max(0, h - t * 2)), innerR, innerR);
            var band = new CombinedGeometry(GeometryCombineMode.Exclude, outer, inner);
            var brush = new SolidColorBrush(Edge);
            brush.Freeze();
            dc.DrawGeometry(brush, null, band);
        }
    }
}
